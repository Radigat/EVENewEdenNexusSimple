import CSQLite
import EVEStaticDataKit
import Foundation

public enum StaticCatalogError: Error, Equatable, Sendable {
  case database(String)
  case noActiveCatalog
  case missingBuild(Int)
  case invalidPointer
}

public struct ItemTypeSearchResult: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let name: String

  public init(id: Int64, name: String) {
    self.id = id
    self.name = name
  }
}

public actor SQLiteStaticCatalog: IndustryCatalogQuerying,
  MoonMaterialCatalogQuerying,
  StaticDataCatalogStoring, StaticDataCatalogStaging,
  StaticDataCatalogStreamingStaging, StaticDataCatalogStreamingStoring,
  ActiveSDEVersionReading, StaticDataCatalogRollingBack,
  SDEPromotionSafetyBackingUp
{
  private struct ActivePointer: Codable, Sendable {
    let buildNumber: Int
    let contentSHA256: String
    let fileName: String
  }

  private let rootURL: URL
  private let fileManager: FileManager
  private var activePointerCache: ActivePointer?
  private var activeDatabaseCache:
    (
      fileName: String, database: SQLiteDatabase
    )?

  public init(
    rootURL: URL,
    fileManager: FileManager = .default
  ) {
    self.rootURL = rootURL
    self.fileManager = fileManager
  }

  public func activate(_ snapshot: StaticDataCatalogSnapshot) async throws
    -> StaticDataActivationResult
  {
    try ensureDirectories()
    let fileName =
      "sde-\(snapshot.buildNumber)-\(snapshot.contentSHA256.prefix(12)).sqlite"
    let destination = catalogsURL.appendingPathComponent(fileName)
    let reused = fileManager.fileExists(atPath: destination.path)
    if !reused {
      let temporary = stagingURL.appendingPathComponent(
        "activation-\(UUID().uuidString).sqlite"
      )
      try write(snapshot: snapshot, to: temporary)
      try validateDatabase(at: temporary)
      try fileManager.moveItem(at: temporary, to: destination)
    }
    try writePointer(
      ActivePointer(
        buildNumber: snapshot.buildNumber,
        contentSHA256: snapshot.contentSHA256,
        fileName: fileName
      )
    )
    return StaticDataActivationResult(
      buildNumber: snapshot.buildNumber,
      contentSHA256: snapshot.contentSHA256,
      counts: snapshot.counts,
      reusedExistingVersion: reused
    )
  }

  public func validateInIsolatedStore(
    _ snapshot: StaticDataCatalogSnapshot,
    operationID: UUID
  ) async throws -> SDEStagingValidationResult {
    try ensureDirectories()
    let url = stagingURL.appendingPathComponent(
      "\(operationID.uuidString).sqlite"
    )
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    try write(snapshot: snapshot, to: url)
    try validateDatabase(at: url)
    return SDEStagingValidationResult(
      buildNumber: snapshot.buildNumber,
      counts: snapshot.counts,
      reopenedSuccessfully: true
    )
  }

  public func cleanup(operationID: UUID) async throws {
    let url = stagingURL.appendingPathComponent(
      "\(operationID.uuidString).sqlite"
    )
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  public func validateStreamingInIsolatedStore(
    packageURL: URL,
    mapper: any StaticDataCatalogStreamingMapping,
    batchSize: Int,
    operationID: UUID
  ) async throws -> SDEStagingValidationResult {
    try ensureDirectories()
    let url = stagingURL.appendingPathComponent(
      "\(operationID.uuidString).sqlite"
    )
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    let metadata = try await mapper.packageMetadata(at: packageURL)
    let writer = try SQLiteBatchWriter(url: url)
    let result = try await mapper.streamStagingPackage(
      at: packageURL,
      batchSize: batchSize
    ) { batch in
      try await writer.append(batch)
    }
    guard result.metadata == metadata else {
      throw StaticCatalogError.database("stream-metadata-mismatch")
    }
    try await writer.finalize(metadata: metadata, counts: result.counts)
    await writer.close()
    try validateDatabase(at: url)
    return SDEStagingValidationResult(
      buildNumber: metadata.buildNumber,
      counts: result.counts,
      reopenedSuccessfully: true
    )
  }

  public func activateStreaming(
    packageURL: URL,
    mapper: any StaticDataCatalogStreamingMapping,
    batchSize: Int
  ) async throws -> StaticDataActivationResult {
    try ensureDirectories()
    let metadata = try await mapper.packageMetadata(at: packageURL)
    let fileName =
      "sde-\(metadata.buildNumber)-\(metadata.contentSHA256.prefix(12)).sqlite"
    let destination = catalogsURL.appendingPathComponent(fileName)
    if fileManager.fileExists(atPath: destination.path) {
      let counts = try readCounts(at: destination)
      try writePointer(
        ActivePointer(
          buildNumber: metadata.buildNumber,
          contentSHA256: metadata.contentSHA256,
          fileName: fileName
        )
      )
      return StaticDataActivationResult(
        buildNumber: metadata.buildNumber,
        contentSHA256: metadata.contentSHA256,
        counts: counts,
        reusedExistingVersion: true
      )
    }

    let temporary = stagingURL.appendingPathComponent(
      "promotion-\(metadata.contentSHA256).sqlite"
    )
    if fileManager.fileExists(atPath: temporary.path) {
      try fileManager.removeItem(at: temporary)
    }
    let writer = try SQLiteBatchWriter(url: temporary)
    do {
      let result = try await mapper.streamStagingPackage(
        at: packageURL,
        batchSize: batchSize
      ) { batch in
        try await writer.append(batch)
      }
      guard result.metadata == metadata else {
        throw StaticCatalogError.database("stream-metadata-mismatch")
      }
      try await writer.finalize(metadata: metadata, counts: result.counts)
      await writer.close()
      try validateDatabase(at: temporary)
      try fileManager.moveItem(at: temporary, to: destination)
      try writePointer(
        ActivePointer(
          buildNumber: metadata.buildNumber,
          contentSHA256: metadata.contentSHA256,
          fileName: fileName
        )
      )
      return StaticDataActivationResult(
        buildNumber: metadata.buildNumber,
        contentSHA256: metadata.contentSHA256,
        counts: result.counts,
        reusedExistingVersion: false
      )
    } catch {
      await writer.close()
      if fileManager.fileExists(atPath: temporary.path) {
        try? fileManager.removeItem(at: temporary)
      }
      throw error
    }
  }

  public func discardStreamingImport(contentSHA256: String) async throws {
    guard Self.isValidContentSHA256(contentSHA256) else {
      throw StaticCatalogError.invalidPointer
    }
    try ensureDirectories()
    let candidates = try fileManager.contentsOfDirectory(
      at: stagingURL,
      includingPropertiesForKeys: nil
    ).filter {
      $0.lastPathComponent.contains(contentSHA256)
        && $0.pathExtension == "sqlite"
    }
    for candidate in candidates {
      try fileManager.removeItem(at: candidate)
    }
  }

  public func activeSDEVersion() async throws -> ActiveSDEVersion? {
    guard let pointer = try loadPointer() else { return nil }
    return try ActiveSDEVersion(
      buildNumber: pointer.buildNumber,
      contentSHA256: pointer.contentSHA256
    )
  }

  public func createSafetyBackup(operationID: UUID) async throws -> Bool {
    guard let pointer = try loadPointer() else { return false }
    try ensureDirectories()
    let source = catalogsURL.appendingPathComponent(pointer.fileName)
    guard fileManager.fileExists(atPath: source.path) else {
      throw StaticCatalogError.missingBuild(pointer.buildNumber)
    }
    let destination = backupsURL.appendingPathComponent(
      "\(operationID.uuidString)-\(pointer.fileName)"
    )
    try fileManager.copyItem(at: source, to: destination)
    return true
  }

  public func rollback(toBuildNumber buildNumber: Int) async throws
    -> StaticDataActivationResult
  {
    try ensureDirectories()
    let candidates = try fileManager.contentsOfDirectory(
      at: catalogsURL,
      includingPropertiesForKeys: nil
    ).filter {
      $0.lastPathComponent.hasPrefix("sde-\(buildNumber)-")
        && $0.pathExtension == "sqlite"
    }
    guard
      let url = candidates.sorted(
        by: { $0.lastPathComponent < $1.lastPathComponent }
      ).last
    else {
      throw StaticCatalogError.missingBuild(buildNumber)
    }
    let database = try SQLiteDatabase(url: url)
    let metadata = try database.singleRow(
      "SELECT content_hash, categories, groups_count, item_types, blueprints, activities, materials, products, unresolved FROM metadata LIMIT 1"
    )
    guard metadata.count == 9,
      let hash = metadata[0],
      let categories = Int(metadata[1] ?? ""),
      let groups = Int(metadata[2] ?? ""),
      let types = Int(metadata[3] ?? ""),
      let blueprints = Int(metadata[4] ?? ""),
      let activities = Int(metadata[5] ?? ""),
      let materials = Int(metadata[6] ?? ""),
      let products = Int(metadata[7] ?? ""),
      let unresolved = Int(metadata[8] ?? "")
    else { throw StaticCatalogError.invalidPointer }
    try writePointer(
      ActivePointer(
        buildNumber: buildNumber,
        contentSHA256: hash,
        fileName: url.lastPathComponent
      )
    )
    return StaticDataActivationResult(
      buildNumber: buildNumber,
      contentSHA256: hash,
      counts: StaticDataCatalogCounts(
        categories: categories,
        groups: groups,
        itemTypes: types,
        blueprints: blueprints,
        activities: activities,
        materials: materials,
        products: products,
        unresolvedTypeReferences: unresolved
      ),
      reusedExistingVersion: true
    )
  }

  public func typeID(named name: String) async throws -> Int64? {
    let database = try activeDatabase()
    return try database.scalarInt64(
      "SELECT id FROM item_types WHERE name = \(sql(name)) COLLATE NOCASE AND published = 1 LIMIT 1"
    )
  }

  public func searchItemTypes(
    matching query: String,
    limit: Int = 30
  ) async throws -> [ItemTypeSearchResult] {
    let accepted = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else { return [] }
    let boundedLimit = min(max(1, limit), 100)
    let escaped =
      accepted
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
    let containsPattern = "%\(escaped)%"
    let prefixPattern = "\(escaped)%"
    let database = try activeDatabase()
    let rows = try database.rows(
      """
      SELECT id, name
      FROM item_types
      WHERE published = 1
        AND name LIKE \(sql(containsPattern)) ESCAPE '\\'
      ORDER BY
        CASE
          WHEN name = \(sql(accepted)) COLLATE NOCASE THEN 0
          WHEN name LIKE \(sql(prefixPattern)) ESCAPE '\\' THEN 1
          ELSE 2
        END,
        length(name),
        name COLLATE NOCASE
      LIMIT \(boundedLimit)
      """
    )
    return rows.compactMap { row in
      guard row.count == 2,
        let id = Int64(row[0] ?? ""),
        let name = row[1]
      else { return nil }
      return ItemTypeSearchResult(id: id, name: name)
    }
  }

  public func moonMaterials() async throws -> MoonMaterialCatalogSnapshot {
    guard let pointer = try loadPointer() else {
      throw StaticCatalogError.noActiveCatalog
    }
    let database = try activeDatabase()
    let rows = try database.rows(
      """
      SELECT t.id, t.name
      FROM item_types t
      JOIN groups_table g ON g.id = t.group_id
      WHERE g.name = 'Moon Materials'
        AND t.published = 1
      ORDER BY t.name COLLATE NOCASE
      """
    )
    let materials: [MoonMaterial] = rows.compactMap { row in
      guard row.count == 2,
        let typeID = Int64(row[0] ?? ""),
        let name = row[1]
      else { return nil }
      return MoonMaterial(id: typeID, name: name)
    }
    guard !materials.isEmpty else {
      throw StaticCatalogError.database("missing-moon-materials")
    }
    return MoonMaterialCatalogSnapshot(
      materials: materials,
      source: SourceIdentity(
        provider: "CCP SDE",
        version: String(pointer.buildNumber)
      )
    )
  }

  public func reactionRuleProfile() async throws -> ReactionRuleProfile? {
    let database = try activeDatabase()
    guard
      let json = try database.scalarString(
        "SELECT profile_json FROM reaction_rule_profile LIMIT 1"
      ),
      let data = json.data(using: .utf8)
    else { return nil }
    do {
      return try JSONDecoder().decode(ReactionRuleProfile.self, from: data)
    } catch {
      throw StaticCatalogError.database("invalid-reaction-rule-profile")
    }
  }

  public func typeName(id: Int64) async throws -> String? {
    let database = try activeDatabase()
    return try database.scalarString(
      "SELECT name FROM item_types WHERE id = \(id) LIMIT 1"
    )
  }

  public func typeNames(ids: Set<Int64>) async throws -> [Int64: String] {
    let orderedIDs = ids.filter { $0 > 0 }.sorted()
    guard !orderedIDs.isEmpty else { return [:] }
    let database = try activeDatabase()
    var result: [Int64: String] = [:]
    result.reserveCapacity(orderedIDs.count)
    for start in stride(from: 0, to: orderedIDs.count, by: 500) {
      try Task.checkCancellation()
      let end = min(start + 500, orderedIDs.count)
      let acceptedIDs = orderedIDs[start..<end]
        .map(String.init)
        .joined(separator: ",")
      let rows = try database.rows(
        """
        SELECT id, name
        FROM item_types
        WHERE id IN (\(acceptedIDs))
        """
      )
      for row in rows {
        guard row.count == 2,
          let id = Int64(row[0] ?? ""),
          let name = row[1]
        else { continue }
        result[id] = name
      }
    }
    return result
  }

  public func industryClassifications(
    typeIDs: Set<Int64>
  ) async throws -> [Int64: IndustryItemClassification] {
    let orderedIDs = typeIDs.filter { $0 > 0 }.sorted()
    guard !orderedIDs.isEmpty else { return [:] }
    let database = try activeDatabase()
    var result: [Int64: IndustryItemClassification] = [:]
    result.reserveCapacity(orderedIDs.count)
    for start in stride(from: 0, to: orderedIDs.count, by: 500) {
      try Task.checkCancellation()
      let end = min(start + 500, orderedIDs.count)
      let acceptedIDs = orderedIDs[start..<end]
        .map(String.init)
        .joined(separator: ",")
      let rows = try database.rows(
        """
        SELECT t.id, c.name, g.name
        FROM item_types t
        JOIN groups_table g ON g.id = t.group_id
        JOIN categories c ON c.id = t.category_id
        WHERE t.id IN (\(acceptedIDs))
        """
      )
      for row in rows {
        guard row.count == 3,
          let typeID = Int64(row[0] ?? ""),
          let categoryName = row[1],
          let groupName = row[2]
        else { continue }
        result[typeID] = IndustryItemClassification(
          categoryName: categoryName,
          groupName: groupName,
          manufacturingCategory: Self.manufacturingCategory(
            categoryName: categoryName,
            groupName: groupName
          )
        )
      }
    }
    return result
  }

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    let database = try activeDatabase()
    let row = try database.singleRow(
      """
      SELECT COALESCE(packaged_volume, volume)
      FROM item_types
      WHERE id = \(typeID) AND published = 1
      LIMIT 1
      """
    )
    guard let raw = row.first ?? nil,
      let volume = Double(raw),
      volume.isFinite,
      volume >= 0
    else { return nil }
    return volume
  }

  public func scienceSkills() async throws -> [ScienceSkillDefinition] {
    let database = try activeDatabase()
    let active = try await activeSDEVersion()
    let source = SourceIdentity(
      provider: "CCP SDE",
      version: String(active?.buildNumber ?? 0)
    )
    return try database.rows(
      """
      SELECT t.id, t.name
      FROM item_types t
      JOIN groups_table g ON g.id = t.group_id
      JOIN categories c ON c.id = t.category_id
      WHERE c.name = 'Skill'
        AND g.name = 'Science'
        AND t.published = 1
      ORDER BY t.name COLLATE NOCASE
      """
    ).compactMap { row in
      guard row.count == 2,
        let typeID = Int64(row[0] ?? ""),
        let name = row[1]
      else { return nil }
      return ScienceSkillDefinition(
        typeID: typeID,
        name: name,
        source: source
      )
    }
  }

  public func industryFacilityReferences() async throws
    -> IndustryFacilityReferenceSnapshot
  {
    guard let pointer = try loadPointer() else {
      throw StaticCatalogError.noActiveCatalog
    }
    let database = try activeDatabase()
    let source = SourceIdentity(
      provider: "CCP SDE",
      version: String(pointer.buildNumber)
    )
    let structureRows = try database.rows(
      """
      SELECT id, name, group_id
      FROM item_types
      WHERE published = 1
        AND group_id IN (1404, 1406, 1657)
      ORDER BY name COLLATE NOCASE
      """
    )
    let rigRows = try database.rows(
      """
      SELECT id, name
      FROM item_types
      WHERE published = 1
        AND name LIKE 'Standup %-Set %'
        AND name NOT LIKE '% Blueprint'
        AND (
          name LIKE '% Manufacturing %'
          OR name LIKE '% Reactor %'
          OR name LIKE '% Invention %'
          OR name LIKE '% Blueprint Copy %'
          OR name LIKE '% ME Research %'
          OR name LIKE '% TE Research %'
        )
        AND name NOT LIKE '% Thukker %'
      ORDER BY name COLLATE NOCASE
      """
    )
    let serviceRows = try database.rows(
      """
      SELECT id, name
      FROM item_types
      WHERE published = 1
        AND group_id IN (1322, 1415)
      ORDER BY name COLLATE NOCASE
      """
    )
    let namedStructures = Self.namedTypes(from: structureRows)
    let namedRigs = Self.namedTypes(from: rigRows)
    let namedServices = Self.namedTypes(from: serviceRows)
    let structureGroupIDs: [Int64: Int64] = Dictionary(
      uniqueKeysWithValues: structureRows.compactMap { row in
        guard row.count >= 3,
          let typeID = Int64(row[0] ?? ""),
          let groupID = Int64(row[2] ?? "")
        else { return nil }
        return (typeID, groupID)
      }
    )
    let requestedTypeIDs = Set(namedStructures.keys)
      .union(namedRigs.keys)
      .union(namedServices.keys)
    let dogma = try await loadTypeDogma(
      typeIDs: requestedTypeIDs,
      pointer: pointer
    )

    let structures = namedStructures.compactMap {
      typeID,
      name -> IndustryStructureDefinition? in
      guard
        let attributes = dogma[typeID],
        let rawSize = attributes[1_547],
        let size = IndustryStructureSize(rawValue: Int(rawSize)),
        let rawSlots = attributes[1_137]
      else { return nil }
      return IndustryStructureDefinition(
        typeID: typeID,
        name: name,
        size: size,
        rigSlots: max(0, Int(rawSlots)),
        manufacturingMaterialBonusPercent:
          Self.percentReduction(attributes[2_600]),
        manufacturingTimeBonusPercent:
          Self.percentReduction(attributes[2_602]),
        jobCostMultiplier: attributes[2_601] ?? 1,
        source: source,
        groupID: structureGroupIDs[typeID]
      )
    }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }

    let rigs = namedRigs.compactMap {
      typeID,
      name -> IndustryRigDefinition? in
      guard
        let attributes = dogma[typeID],
        let rawSize = attributes[1_547],
        let size = IndustryStructureSize(rawValue: Int(rawSize)),
        let lowSecurityMultiplier = attributes[2_356],
        let nullSecurityMultiplier = attributes[2_357]
      else { return nil }
      let isReaction = name.localizedCaseInsensitiveContains("Reactor")
      let scienceActivities = Self.scienceActivities(forRigName: name)
      let isScience = !scienceActivities.isEmpty
      let materialAttribute = isReaction ? 2_714 : (isScience ? 0 : 2_594)
      let timeAttribute = isReaction ? 2_713 : 2_593
      let rawMaterial = attributes[Int64(materialAttribute)] ?? 0
      let rawTime = attributes[Int64(timeAttribute)] ?? 0
      let rawJobCost = isScience ? (attributes[2_595] ?? 0) : 0
      return IndustryRigDefinition(
        typeID: typeID,
        name: name,
        size: size,
        manufacturingCategories:
          isReaction || isScience
          ? [] : Self.manufacturingCategories(forRigName: name),
        isReactionRig: isReaction,
        materialBonusPercent: abs(rawMaterial),
        timeBonusPercent: abs(rawTime),
        lowSecurityMultiplier: lowSecurityMultiplier,
        nullSecurityMultiplier: nullSecurityMultiplier,
        source: source,
        scienceActivities: scienceActivities,
        jobCostBonusPercent: abs(rawJobCost)
      )
    }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let knownStructureTypeIDs = Set(namedStructures.keys)
    let services = namedServices.compactMap {
      typeID,
      name -> IndustryServiceModuleDefinition? in
      guard let attributes = dogma[typeID] else { return nil }
      let activities = Self.serviceActivities(forModuleName: name)
      guard !activities.isEmpty else { return nil }
      let compatibleGroupIDs = [1_298, 1_299, 1_300].compactMap {
        attributeID -> Int64? in
        guard let value = attributes[Int64(attributeID)] else { return nil }
        let accepted = Int64(value)
        return [1_404, 1_406, 1_657].contains(accepted)
          ? accepted : nil
      }
      let compatibleTypeIDs = [1_302, 1_303, 1_304, 1_305].compactMap {
        attributeID -> Int64? in
        guard let value = attributes[Int64(attributeID)] else { return nil }
        let accepted = Int64(value)
        return knownStructureTypeIDs.contains(accepted) ? accepted : nil
      }
      return IndustryServiceModuleDefinition(
        typeID: typeID,
        name: name,
        activities: activities,
        compatibleStructureGroupIDs: compatibleGroupIDs,
        compatibleStructureTypeIDs: compatibleTypeIDs,
        normalOreYieldMultiplier:
          attributes[2_444] ?? attributes[717],
        moonOreYieldMultiplier:
          attributes[2_445] ?? attributes[717],
        iceYieldMultiplier:
          attributes[2_448] ?? attributes[717],
        gasYieldMultiplier: attributes[3_262],
        source: source
      )
    }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    return IndustryFacilityReferenceSnapshot(
      structures: structures,
      rigs: rigs,
      source: source,
      serviceModules: services
    )
  }

  public func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    let database = try activeDatabase()
    let rows = try database.rows(
      """
      SELECT c.name, g.name
      FROM item_types t
      JOIN groups_table g ON g.id = t.group_id
      JOIN categories c ON c.id = t.category_id
      WHERE t.id = \(productTypeID)
      LIMIT 1
      """
    )
    guard let row = rows.first, row.count == 2,
      let categoryName = row[0], let groupName = row[1]
    else { return nil }
    return IndustryItemClassification(
      categoryName: categoryName,
      groupName: groupName,
      manufacturingCategory: Self.manufacturingCategory(
        categoryName: categoryName,
        groupName: groupName
      )
    )
  }

  private static func manufacturingCategory(
    categoryName: String,
    groupName: String
  ) -> ManufacturingCategory {
    let category = categoryName.lowercased()
    let group = groupName.lowercased()
    if category.contains("structure") || group.contains("fuel block") {
      return .structures
    }
    guard category == "ship" else { return .module }
    let capitalTerms = [
      "carrier", "dreadnought", "force auxiliary", "supercarrier", "titan",
      "capital industrial", "freighter", "jump freighter",
    ]
    if capitalTerms.contains(where: group.contains) { return .capital }
    let largeTerms = ["battleship", "black ops", "marauder"]
    if largeTerms.contains(where: group.contains) { return .large }
    let mediumTerms = [
      "cruiser", "battlecruiser", "industrial command", "logistics",
      "recon ship",
    ]
    if mediumTerms.contains(where: group.contains) { return .medium }
    return .small
  }

  private static func namedTypes(
    from rows: [[String?]]
  ) -> [Int64: String] {
    Dictionary(
      uniqueKeysWithValues: rows.compactMap { row in
        guard row.count >= 2,
          let typeID = Int64(row[0] ?? ""),
          let name = row[1]
        else { return nil }
        return (typeID, name)
      }
    )
  }

  private static func manufacturingCategories(
    forRigName name: String
  ) -> [ManufacturingCategory] {
    let accepted = name.lowercased()
    if accepted.contains("ship manufacturing")
      && !accepted.contains("small")
      && !accepted.contains("medium")
      && !accepted.contains("large")
    {
      return [.small, .medium, .large, .capital]
    }
    if accepted.contains("small ship") { return [.small] }
    if accepted.contains("medium ship") { return [.medium] }
    if accepted.contains("large ship") { return [.large] }
    if accepted.contains("capital ship") { return [.capital] }
    if accepted.contains("structure and component") {
      return [.structures, .module]
    }
    if accepted.contains("structure manufacturing") {
      return [.structures]
    }
    return [.module]
  }

  private static func scienceActivities(
    forRigName name: String
  ) -> [IndustryActivitySystem] {
    let accepted = name.lowercased()
    if accepted.contains("invention") { return [.invention] }
    if accepted.contains("blueprint copy") { return [.copying] }
    if accepted.contains("me research") { return [.materialResearch] }
    if accepted.contains("te research") { return [.timeResearch] }
    return []
  }

  private static func serviceActivities(
    forModuleName name: String
  ) -> [IndustryFacilityServiceActivity] {
    let accepted = name.lowercased()
    if accepted.contains("invention lab") {
      return [.invention]
    }
    if accepted.contains("research lab") {
      return [.copying, .materialResearch, .timeResearch]
    }
    if accepted.contains("reprocessing facility") {
      return [.reprocessing]
    }
    if accepted.contains("reactor") {
      return [.reaction]
    }
    if accepted.contains("manufacturing plant")
      || accepted.contains("shipyard")
    {
      return [.manufacturing]
    }
    return []
  }

  private static func percentReduction(_ multiplier: Double?) -> Double {
    guard let multiplier else { return 0 }
    return max(0, (1 - multiplier) * 100)
  }

  private func loadTypeDogma(
    typeIDs: Set<Int64>,
    pointer: ActivePointer
  ) async throws -> [Int64: [Int64: Double]] {
    let packageURL = try activePackageURL(pointer: pointer)
    let typeDogmaURL = packageURL.appendingPathComponent("typeDogma.jsonl")
    let handle = try FileHandle(forReadingFrom: typeDogmaURL)
    defer { try? handle.close() }
    let decoder = JSONDecoder()
    var result: [Int64: [Int64: Double]] = [:]
    for try await line in handle.bytes.lines {
      try Task.checkCancellation()
      let record = try decoder.decode(
        TypeDogmaRecord.self,
        from: Data(line.utf8)
      )
      guard typeIDs.contains(record.typeID) else { continue }
      result[record.typeID] = Dictionary(
        uniqueKeysWithValues: record.attributes.map {
          ($0.attributeID, $0.value)
        }
      )
      if result.count == typeIDs.count { break }
    }
    return result
  }

  private func activePackageURL(pointer: ActivePointer) throws -> URL {
    let packagesURL =
      rootURL.deletingLastPathComponent()
      .appendingPathComponent("packages", isDirectory: true)
    let candidates = try fileManager.contentsOfDirectory(
      at: packagesURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    for candidate in candidates
    where candidate.pathExtension == "evesde" {
      let manifestURL = candidate.appendingPathComponent("manifest.json")
      guard
        let data = try? Data(contentsOf: manifestURL),
        let manifest = try? JSONDecoder().decode(
          MinimalPackageManifest.self,
          from: data
        ),
        manifest.snapshot.buildNumber == pointer.buildNumber,
        manifest.snapshot.contentSHA256 == pointer.contentSHA256
      else { continue }
      return candidate
    }
    throw StaticCatalogError.missingBuild(pointer.buildNumber)
  }

  public func blueprintResearchDefinition(blueprintTypeID: Int64) async throws
    -> BlueprintResearchDefinition?
  {
    let database = try activeDatabase()
    let header = try database.singleRow(
      """
      SELECT t.name, t.base_price
      FROM blueprints b
      JOIN item_types t ON t.id = b.blueprint_type_id
      WHERE b.blueprint_type_id = \(blueprintTypeID)
        AND t.published = 1
      LIMIT 1
      """
    )
    guard
      header.count == 2,
      let blueprintName = header[0]
    else { return nil }

    func materials(activity: String) throws -> [BlueprintMaterial] {
      try database.rows(
        """
        SELECT item_type_id, quantity
        FROM blueprint_materials
        WHERE blueprint_type_id = \(blueprintTypeID)
          AND activity = \(sql(activity))
          AND resolved = 1
        ORDER BY sort_order
        """
      ).compactMap { row in
        guard row.count == 2,
          let typeID = Int64(row[0] ?? ""),
          let quantity = Int64(row[1] ?? "")
        else { return nil }
        return BlueprintMaterial(typeID: typeID, quantity: quantity)
      }
    }

    let activityRows = try database.rows(
      """
      SELECT activity, time_seconds
      FROM blueprint_activities
      WHERE blueprint_type_id = \(blueprintTypeID)
        AND activity IN ('manufacturing', 'research_material', 'research_time')
      """
    )
    let times = Dictionary(
      uniqueKeysWithValues: activityRows.compactMap {
        row -> (String, Int64)? in
        guard row.count == 2,
          let activity = row[0],
          let seconds = Int64(row[1] ?? "")
        else { return nil }
        return (activity, seconds)
      }
    )
    let unresolvedCount =
      try database.scalarInt64(
        """
        SELECT COUNT(*)
        FROM blueprint_materials
        WHERE blueprint_type_id = \(blueprintTypeID)
          AND activity IN ('manufacturing', 'research_material', 'research_time')
          AND resolved = 0
        """
      ) ?? 0
    let active = try await activeSDEVersion()
    return BlueprintResearchDefinition(
      blueprintTypeID: blueprintTypeID,
      blueprintName: blueprintName,
      basePrice: header[1].flatMap(Double.init),
      manufacturingMaterials: try materials(activity: "manufacturing"),
      materialResearchMaterials: try materials(
        activity: "research_material"
      ),
      timeResearchMaterials: try materials(activity: "research_time"),
      materialResearchTimeSeconds: times["research_material"],
      timeResearchTimeSeconds: times["research_time"],
      hasUnresolvedReferences:
        unresolvedCount > 0
        || times["research_material"] == nil
        || times["research_time"] == nil,
      source: SourceIdentity(
        provider: "CCP SDE",
        version: String(active?.buildNumber ?? 0)
      )
    )
  }

  public func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    try await productionDefinition(
      productTypeID: productTypeID,
      requiredActivity: nil
    )
  }

  private func productionDefinition(
    productTypeID: Int64,
    requiredActivity: BlueprintActivityDefinition.Kind?
  ) async throws -> BlueprintDefinition? {
    let database = try activeDatabase()
    let rows = try database.rows(
      """
      SELECT b.blueprint_type_id, b.max_production_limit, a.activity,
             a.time_seconds
      FROM blueprint_products p
      JOIN blueprint_activities a
        ON a.blueprint_type_id = p.blueprint_type_id
       AND a.activity = p.activity
      JOIN blueprints b
        ON b.blueprint_type_id = a.blueprint_type_id
      JOIN item_types blueprint_type
        ON blueprint_type.id = b.blueprint_type_id
      JOIN item_types product_type
        ON product_type.id = p.item_type_id
      WHERE p.item_type_id = \(productTypeID)
        AND p.resolved = 1
        AND blueprint_type.published = 1
        AND product_type.published = 1
        AND a.activity IN ('manufacturing','reaction','invention')
        AND \(requiredActivity.map { "a.activity = \(sql($0.rawValue))" } ?? "1 = 1")
        AND NOT EXISTS (
          SELECT 1
          FROM blueprint_materials unresolved_material
          WHERE unresolved_material.blueprint_type_id = b.blueprint_type_id
            AND unresolved_material.activity = a.activity
            AND unresolved_material.resolved = 0
        )
      ORDER BY CASE a.activity
        WHEN 'manufacturing' THEN 0
        WHEN 'reaction' THEN 1
        ELSE 2 END
      LIMIT 1
      """
    )
    guard let row = rows.first,
      row.count == 4,
      let blueprintID = Int64(row[0] ?? ""),
      let activityRaw = row[2],
      let duration = Int64(row[3] ?? ""),
      let kind = BlueprintActivityDefinition.Kind(
        rawValue: activityRaw
      )
    else { return nil }
    let maximum = row[1].flatMap(Int64.init)
    let materials = try database.rows(
      """
      SELECT item_type_id, quantity
      FROM blueprint_materials
      WHERE blueprint_type_id = \(blueprintID)
        AND activity = \(sql(activityRaw))
        AND resolved = 1
      ORDER BY sort_order
      """
    ).compactMap { values -> BlueprintMaterial? in
      guard values.count == 2,
        let typeID = Int64(values[0] ?? ""),
        let quantity = Int64(values[1] ?? "")
      else { return nil }
      return BlueprintMaterial(typeID: typeID, quantity: quantity)
    }
    let products = try database.rows(
      """
      SELECT item_type_id, quantity, probability
      FROM blueprint_products
      WHERE blueprint_type_id = \(blueprintID)
        AND activity = \(sql(activityRaw))
        AND resolved = 1
      ORDER BY sort_order
      """
    ).compactMap { values -> BlueprintProduct? in
      guard values.count == 3,
        let typeID = Int64(values[0] ?? ""),
        let quantity = Int64(values[1] ?? "")
      else { return nil }
      return BlueprintProduct(
        typeID: typeID,
        quantity: quantity,
        probability: values[2].flatMap(Double.init)
      )
    }
    let active = try await activeSDEVersion()
    return BlueprintDefinition(
      blueprintTypeID: blueprintID,
      productTypeID: productTypeID,
      maxProductionLimit: maximum,
      activity: BlueprintActivityDefinition(
        kind: kind,
        durationSeconds: duration,
        materials: materials,
        products: products
      ),
      source: SourceIdentity(
        provider: "CCP SDE",
        version: String(active?.buildNumber ?? 0)
      )
    )
  }

  public func reactionDefinitions() async throws -> [BlueprintDefinition] {
    let database = try activeDatabase()
    let productRows = try database.rows(
      """
      SELECT p.item_type_id
      FROM blueprint_activities a
      JOIN blueprints b
        ON b.blueprint_type_id = a.blueprint_type_id
      JOIN blueprint_products p
        ON p.blueprint_type_id = a.blueprint_type_id
       AND p.activity = a.activity
      JOIN item_types blueprint_type
        ON blueprint_type.id = b.blueprint_type_id
      JOIN item_types product_type
        ON product_type.id = p.item_type_id
      WHERE a.activity = 'reaction'
        AND p.resolved = 1
        AND blueprint_type.published = 1
        AND product_type.published = 1
        AND NOT EXISTS (
          SELECT 1
          FROM blueprint_materials unresolved_material
          WHERE unresolved_material.blueprint_type_id = b.blueprint_type_id
            AND unresolved_material.activity = a.activity
            AND unresolved_material.resolved = 0
        )
      GROUP BY a.blueprint_type_id
      ORDER BY product_type.name COLLATE NOCASE
      """
    )
    var productTypeIDs: [Int64] = []
    productTypeIDs.reserveCapacity(productRows.count)
    for row in productRows {
      guard let raw = row.first ?? nil else { continue }
      guard let productTypeID = Int64(raw) else { continue }
      productTypeIDs.append(productTypeID)
    }
    var definitions: [BlueprintDefinition] = []
    definitions.reserveCapacity(productTypeIDs.count)
    for productTypeID in productTypeIDs {
      try Task.checkCancellation()
      guard
        let definition = try await productionDefinition(
          productTypeID: productTypeID,
          requiredActivity: .reaction
        ),
        definition.activity.kind == .reaction
      else { continue }
      definitions.append(definition)
    }
    return definitions
  }

  private var catalogsURL: URL {
    rootURL.appendingPathComponent("catalogs", isDirectory: true)
  }

  private var stagingURL: URL {
    rootURL.appendingPathComponent("staging", isDirectory: true)
  }

  private var backupsURL: URL {
    rootURL.appendingPathComponent("backups", isDirectory: true)
  }

  private var pointerURL: URL {
    rootURL.appendingPathComponent("active-sde.json")
  }

  private func ensureDirectories() throws {
    for url in [rootURL, catalogsURL, stagingURL, backupsURL] {
      try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: true
      )
    }
  }

  private func loadPointer() throws -> ActivePointer? {
    if let activePointerCache {
      return activePointerCache
    }
    guard fileManager.fileExists(atPath: pointerURL.path) else {
      return nil
    }
    let pointer = try JSONDecoder().decode(
      ActivePointer.self,
      from: Data(contentsOf: pointerURL)
    )
    try validate(pointer)
    activePointerCache = pointer
    return pointer
  }

  private func writePointer(_ pointer: ActivePointer) throws {
    try validate(pointer)
    try ensureDirectories()
    let data = try JSONEncoder().encode(pointer)
    try data.write(to: pointerURL, options: .atomic)
    activePointerCache = pointer
    if activeDatabaseCache?.fileName != pointer.fileName {
      activeDatabaseCache = nil
    }
  }

  private func activeDatabase() throws -> SQLiteDatabase {
    if let activeDatabaseCache {
      return activeDatabaseCache.database
    }
    guard let pointer = try loadPointer() else {
      throw StaticCatalogError.noActiveCatalog
    }
    let url = catalogsURL.appendingPathComponent(pointer.fileName)
    guard fileManager.fileExists(atPath: url.path) else {
      throw StaticCatalogError.missingBuild(pointer.buildNumber)
    }
    let database = try SQLiteDatabase(url: url, readOnly: true)
    activeDatabaseCache = (pointer.fileName, database)
    return database
  }

  private func validate(_ pointer: ActivePointer) throws {
    let expectedFileName =
      "sde-\(pointer.buildNumber)-\(pointer.contentSHA256.prefix(12)).sqlite"
    guard pointer.buildNumber > 0,
      Self.isValidContentSHA256(pointer.contentSHA256),
      pointer.fileName == expectedFileName,
      pointer.fileName == URL(fileURLWithPath: pointer.fileName).lastPathComponent
    else {
      throw StaticCatalogError.invalidPointer
    }
  }

  private static func isValidContentSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private func validateDatabase(at url: URL) throws {
    let reopened = try SQLiteDatabase(url: url, readOnly: true)
    guard try reopened.scalarString("PRAGMA integrity_check") == "ok" else {
      throw StaticCatalogError.database("integrity-check")
    }
    guard
      (try reopened.scalarInt64(
        "SELECT COUNT(*) FROM item_types"
      ) ?? 0) > 0
    else {
      throw StaticCatalogError.database("empty-types")
    }
  }

  private func readCounts(at url: URL) throws -> StaticDataCatalogCounts {
    let db = try SQLiteDatabase(url: url, readOnly: true)
    let values = try db.singleRow(
      "SELECT categories, groups_count, item_types, blueprints, activities, materials, products, unresolved FROM metadata LIMIT 1"
    )
    guard values.count == 8,
      let categories = Int(values[0] ?? ""),
      let groups = Int(values[1] ?? ""),
      let types = Int(values[2] ?? ""),
      let blueprints = Int(values[3] ?? ""),
      let activities = Int(values[4] ?? ""),
      let materials = Int(values[5] ?? ""),
      let products = Int(values[6] ?? ""),
      let unresolved = Int(values[7] ?? "")
    else {
      throw StaticCatalogError.database("invalid-counts")
    }
    return StaticDataCatalogCounts(
      categories: categories,
      groups: groups,
      itemTypes: types,
      blueprints: blueprints,
      activities: activities,
      materials: materials,
      products: products,
      unresolvedTypeReferences: unresolved
    )
  }

  private func write(
    snapshot: StaticDataCatalogSnapshot,
    to url: URL
  ) throws {
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
    let db = try SQLiteDatabase(url: url)
    try db.execute("PRAGMA journal_mode=DELETE")
    try db.execute("PRAGMA synchronous=FULL")
    try db.execute(
      """
      CREATE TABLE metadata (
        build_number INTEGER NOT NULL,
        content_hash TEXT NOT NULL,
        official_url TEXT NOT NULL,
        categories INTEGER NOT NULL,
        groups_count INTEGER NOT NULL,
        item_types INTEGER NOT NULL,
        blueprints INTEGER NOT NULL,
        activities INTEGER NOT NULL,
        materials INTEGER NOT NULL,
        products INTEGER NOT NULL,
        unresolved INTEGER NOT NULL
      );
      CREATE TABLE reaction_rule_profile (
        profile_json TEXT NOT NULL
      );
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, published INTEGER NOT NULL
      );
      CREATE TABLE groups_table (
        id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL,
        name TEXT NOT NULL, published INTEGER NOT NULL
      );
      CREATE TABLE item_types (
        id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL, market_group_id INTEGER,
        name TEXT NOT NULL, description TEXT, volume REAL,
        packaged_volume REAL, base_price REAL, portion_size INTEGER NOT NULL,
        published INTEGER NOT NULL, icon_id INTEGER
      );
      CREATE TABLE blueprints (
        blueprint_type_id INTEGER PRIMARY KEY, max_production_limit INTEGER
      );
      CREATE TABLE blueprint_activities (
        blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
        time_seconds INTEGER NOT NULL,
        PRIMARY KEY (blueprint_type_id, activity)
      );
      CREATE TABLE blueprint_materials (
        blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
        item_type_id INTEGER NOT NULL, resolved INTEGER NOT NULL,
        quantity INTEGER NOT NULL, sort_order INTEGER NOT NULL
      );
      CREATE TABLE blueprint_products (
        blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
        item_type_id INTEGER NOT NULL, resolved INTEGER NOT NULL,
        quantity INTEGER NOT NULL, probability REAL, sort_order INTEGER NOT NULL
      );
      CREATE INDEX idx_item_type_name ON item_types(name COLLATE NOCASE);
      CREATE INDEX idx_product_type ON blueprint_products(item_type_id);
      CREATE INDEX idx_material_blueprint
        ON blueprint_materials(blueprint_type_id, activity);
      """
    )
    try db.execute("BEGIN IMMEDIATE")
    do {
      let counts = snapshot.counts
      try db.execute(
        """
        INSERT INTO metadata VALUES (
          \(snapshot.buildNumber), \(sql(snapshot.contentSHA256)),
          \(sql(snapshot.officialArchiveURL)), \(counts.categories),
          \(counts.groups), \(counts.itemTypes), \(counts.blueprints),
          \(counts.activities), \(counts.materials), \(counts.products),
          \(counts.unresolvedTypeReferences)
        )
        """
      )
      if let profile = snapshot.reactionRuleProfile {
        let data = try JSONEncoder().encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
          throw StaticCatalogError.database("reaction-profile-encoding")
        }
        try db.execute(
          "INSERT INTO reaction_rule_profile VALUES (\(sql(json)))"
        )
      }
      for category in snapshot.categories {
        try db.execute(
          "INSERT INTO categories VALUES (\(category.externalID), \(sql(category.name)), \(category.published ? 1 : 0))"
        )
      }
      for group in snapshot.groups {
        try db.execute(
          "INSERT INTO groups_table VALUES (\(group.externalID), \(group.categoryExternalID), \(sql(group.name)), \(group.published ? 1 : 0))"
        )
      }
      for type in snapshot.itemTypes {
        try db.execute(
          """
          INSERT INTO item_types VALUES (
            \(type.externalID), \(type.groupExternalID),
            \(type.categoryExternalID), \(sql(type.marketGroupExternalID)),
            \(sql(type.name)), \(sql(type.description)),
            \(sql(type.volume)), \(sql(type.packagedVolume)),
            \(sql(type.basePrice)), \(type.portionSize),
            \(type.published ? 1 : 0), \(sql(type.iconExternalID))
          )
          """
        )
      }
      for blueprint in snapshot.blueprints {
        try db.execute(
          "INSERT INTO blueprints VALUES (\(blueprint.blueprintTypeID), \(sql(blueprint.maxProductionLimit)))"
        )
        for activity in blueprint.activities {
          try db.execute(
            "INSERT INTO blueprint_activities VALUES (\(blueprint.blueprintTypeID), \(sql(activity.activity.rawValue)), \(activity.timeSeconds))"
          )
          for material in activity.materials {
            try db.execute(
              """
              INSERT INTO blueprint_materials VALUES (
                \(blueprint.blueprintTypeID),
                \(sql(activity.activity.rawValue)),
                \(material.itemTypeID),
                \(material.typeIsResolved ? 1 : 0),
                \(material.quantity), \(material.sortOrder)
              )
              """
            )
          }
          for product in activity.products {
            try db.execute(
              """
              INSERT INTO blueprint_products VALUES (
                \(blueprint.blueprintTypeID),
                \(sql(activity.activity.rawValue)),
                \(product.itemTypeID),
                \(product.typeIsResolved ? 1 : 0),
                \(product.quantity), \(sql(product.probability)),
                \(product.sortOrder)
              )
              """
            )
          }
        }
      }
      try db.execute("COMMIT")
    } catch {
      try? db.execute("ROLLBACK")
      throw error
    }
  }
}

private struct MinimalPackageManifest: Decodable {
  let snapshot: Snapshot

  struct Snapshot: Decodable {
    let buildNumber: Int
    let contentSHA256: String
  }
}

private struct TypeDogmaRecord: Decodable {
  let typeID: Int64
  let attributes: [Attribute]

  struct Attribute: Decodable {
    let attributeID: Int64
    let value: Double
  }

  private enum CodingKeys: String, CodingKey {
    case typeID = "_key"
    case attributes = "dogmaAttributes"
  }
}

private final class SQLiteDatabase {
  private var handle: OpaquePointer?

  init(url: URL, readOnly: Bool = false) throws {
    let flags =
      readOnly
      ? SQLITE_OPEN_READONLY
      : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    let status = sqlite3_open_v2(url.path, &handle, flags, nil)
    guard status == SQLITE_OK else {
      let message =
        handle.map { String(cString: sqlite3_errmsg($0)) }
        ?? "open"
      sqlite3_close(handle)
      throw StaticCatalogError.database("\(message) [\(url.path)]")
    }
    sqlite3_busy_timeout(handle, 5_000)
  }

  deinit {
    sqlite3_close(handle)
  }

  func execute(_ sql: String) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
    guard status == SQLITE_OK else {
      let message =
        errorPointer.map { String(cString: $0) }
        ?? handle.map { String(cString: sqlite3_errmsg($0)) }
        ?? "execute"
      sqlite3_free(errorPointer)
      throw StaticCatalogError.database(message)
    }
  }

  func rows(_ sql: String) throws -> [[String?]] {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        == SQLITE_OK
    else {
      throw StaticCatalogError.database(
        handle.map { String(cString: sqlite3_errmsg($0)) }
          ?? "prepare"
      )
    }
    defer { sqlite3_finalize(statement) }
    var result: [[String?]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      result.append(
        (0..<sqlite3_column_count(statement)).map { index in
          guard let text = sqlite3_column_text(statement, index)
          else { return nil }
          return String(cString: text)
        }
      )
    }
    return result
  }

  func singleRow(_ sql: String) throws -> [String?] {
    try rows(sql).first ?? []
  }

  func scalarString(_ sql: String) throws -> String? {
    try singleRow(sql).first ?? nil
  }

  func scalarInt64(_ sql: String) throws -> Int64? {
    try scalarString(sql).flatMap(Int64.init)
  }
}

private actor SQLiteBatchWriter {
  private var database: SQLiteDatabase?

  init(url: URL) throws {
    let database = try SQLiteDatabase(url: url)
    try database.execute("PRAGMA journal_mode=DELETE")
    try database.execute("PRAGMA synchronous=FULL")
    try database.execute(Self.schema)
    self.database = database
  }

  func append(_ batch: StaticDataCatalogBatch) throws {
    guard let database else {
      throw StaticCatalogError.database("writer-closed")
    }
    try database.execute("BEGIN IMMEDIATE")
    do {
      switch batch {
      case .categories(let records):
        for category in records {
          try database.execute(
            "INSERT INTO categories VALUES (\(category.externalID), \(sql(category.name)), \(category.published ? 1 : 0))"
          )
        }
      case .groups(let records):
        for group in records {
          try database.execute(
            "INSERT INTO groups_table VALUES (\(group.externalID), \(group.categoryExternalID), \(sql(group.name)), \(group.published ? 1 : 0))"
          )
        }
      case .itemTypes(let records):
        for type in records {
          try database.execute(
            """
            INSERT INTO item_types VALUES (
              \(type.externalID), \(type.groupExternalID),
              \(type.categoryExternalID), \(sql(type.marketGroupExternalID)),
              \(sql(type.name)), \(sql(type.description)),
              \(sql(type.volume)), \(sql(type.packagedVolume)),
              \(sql(type.basePrice)), \(type.portionSize),
              \(type.published ? 1 : 0), \(sql(type.iconExternalID))
            )
            """
          )
        }
      case .blueprints(let records):
        for blueprint in records {
          try database.execute(
            "INSERT INTO blueprints VALUES (\(blueprint.blueprintTypeID), \(sql(blueprint.maxProductionLimit)))"
          )
          for activity in blueprint.activities {
            try database.execute(
              "INSERT INTO blueprint_activities VALUES (\(blueprint.blueprintTypeID), \(sql(activity.activity.rawValue)), \(activity.timeSeconds))"
            )
            for material in activity.materials {
              try database.execute(
                """
                INSERT INTO blueprint_materials VALUES (
                  \(blueprint.blueprintTypeID),
                  \(sql(activity.activity.rawValue)),
                  \(material.itemTypeID),
                  \(material.typeIsResolved ? 1 : 0),
                  \(material.quantity), \(material.sortOrder)
                )
                """
              )
            }
            for product in activity.products {
              try database.execute(
                """
                INSERT INTO blueprint_products VALUES (
                  \(blueprint.blueprintTypeID),
                  \(sql(activity.activity.rawValue)),
                  \(product.itemTypeID),
                  \(product.typeIsResolved ? 1 : 0),
                  \(product.quantity), \(sql(product.probability)),
                  \(product.sortOrder)
                )
                """
              )
            }
          }
        }
      case .reactionRuleProfile(let profile):
        let data = try JSONEncoder().encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
          throw StaticCatalogError.database("reaction-profile-encoding")
        }
        try database.execute(
          "DELETE FROM reaction_rule_profile"
        )
        try database.execute(
          "INSERT INTO reaction_rule_profile VALUES (\(sql(json)))"
        )
      }
      try database.execute("COMMIT")
    } catch {
      try? database.execute("ROLLBACK")
      throw error
    }
  }

  func finalize(
    metadata: StaticDataCatalogPackageMetadata,
    counts: StaticDataCatalogCounts
  ) throws {
    guard let database else {
      throw StaticCatalogError.database("writer-closed")
    }
    try database.execute(
      """
      INSERT INTO metadata VALUES (
        \(metadata.buildNumber), \(sql(metadata.contentSHA256)),
        \(sql(metadata.officialArchiveURL)), \(counts.categories),
        \(counts.groups), \(counts.itemTypes), \(counts.blueprints),
        \(counts.activities), \(counts.materials), \(counts.products),
        \(counts.unresolvedTypeReferences)
      )
      """
    )
  }

  func close() {
    database = nil
  }

  private static let schema = """
    CREATE TABLE metadata (
      build_number INTEGER NOT NULL,
      content_hash TEXT NOT NULL,
      official_url TEXT NOT NULL,
      categories INTEGER NOT NULL,
      groups_count INTEGER NOT NULL,
      item_types INTEGER NOT NULL,
      blueprints INTEGER NOT NULL,
      activities INTEGER NOT NULL,
      materials INTEGER NOT NULL,
      products INTEGER NOT NULL,
      unresolved INTEGER NOT NULL
    );
    CREATE TABLE reaction_rule_profile (
      profile_json TEXT NOT NULL
    );
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, published INTEGER NOT NULL
    );
    CREATE TABLE groups_table (
      id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL,
      name TEXT NOT NULL, published INTEGER NOT NULL
    );
    CREATE TABLE item_types (
      id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL,
      category_id INTEGER NOT NULL, market_group_id INTEGER,
      name TEXT NOT NULL, description TEXT, volume REAL,
      packaged_volume REAL, base_price REAL, portion_size INTEGER NOT NULL,
      published INTEGER NOT NULL, icon_id INTEGER
    );
    CREATE TABLE blueprints (
      blueprint_type_id INTEGER PRIMARY KEY, max_production_limit INTEGER
    );
    CREATE TABLE blueprint_activities (
      blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
      time_seconds INTEGER NOT NULL,
      PRIMARY KEY (blueprint_type_id, activity)
    );
    CREATE TABLE blueprint_materials (
      blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
      item_type_id INTEGER NOT NULL, resolved INTEGER NOT NULL,
      quantity INTEGER NOT NULL, sort_order INTEGER NOT NULL
    );
    CREATE TABLE blueprint_products (
      blueprint_type_id INTEGER NOT NULL, activity TEXT NOT NULL,
      item_type_id INTEGER NOT NULL, resolved INTEGER NOT NULL,
      quantity INTEGER NOT NULL, probability REAL, sort_order INTEGER NOT NULL
    );
    CREATE INDEX idx_item_type_name ON item_types(name COLLATE NOCASE);
    CREATE INDEX idx_product_type ON blueprint_products(item_type_id);
    CREATE INDEX idx_material_blueprint
      ON blueprint_materials(blueprint_type_id, activity);
    """
}

private func sql(_ value: String?) -> String {
  guard let value else { return "NULL" }
  return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

private func sql<T: CustomStringConvertible>(_ value: T?) -> String {
  value.map { String(describing: $0) } ?? "NULL"
}
