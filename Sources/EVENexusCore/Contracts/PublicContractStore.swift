import CSQLite
import Foundation

public enum PublicContractStoreError: Error, Equatable, Sendable {
  case database(String)
  case invalidRow
}

public actor PublicContractStore {
  private let database: PublicContractSQLiteDatabase

  public init(url: URL, fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    database = try PublicContractSQLiteDatabase(url: url)
    try database.execute("PRAGMA journal_mode=WAL")
    try database.execute("PRAGMA synchronous=NORMAL")
    try database.execute("PRAGMA foreign_keys=ON")
    try database.execute(Self.schema)
    try Self.migrateOptionalForCorporation(in: database)
    try Self.backfillContractLocations(in: database)
  }

  public func close() {
    database.close()
  }

  public func setAutomaticUpdatesEnabled(_ isEnabled: Bool) throws {
    try setSetting(
      key: "automatic_updates_enabled",
      value: isEnabled ? "1" : "0"
    )
  }

  public func setAutomaticSafetyNotBefore(_ date: Date?) throws {
    try setSetting(
      key: "automatic_safety_not_before",
      value: date.map { String($0.timeIntervalSince1970) }
    )
  }

  public func automationState(
    now: Date = .now,
    regularRefreshInterval: TimeInterval = 6 * 60 * 60
  ) throws -> PublicContractAutomationState {
    let isEnabled = try setting(key: "automatic_updates_enabled") == "1"
    let safetyNotBefore = try setting(key: "automatic_safety_not_before")
      .flatMap(Double.init)
      .map(Date.init(timeIntervalSince1970:))
    guard isEnabled else {
      return PublicContractAutomationState(
        isEnabled: false,
        safetyNotBefore: safetyNotBefore
      )
    }

    let state = try database.query(
      """
      SELECT
        (SELECT COUNT(*) FROM regions) AS regions,
        (SELECT COUNT(*) FROM regions WHERE last_success_at IS NULL)
          AS incomplete_regions,
        (SELECT COUNT(*) FROM regions
          WHERE last_success_at IS NULL
            AND (next_allowed_at IS NULL OR next_allowed_at <= ?))
          AS eligible_incomplete_regions,
        (SELECT MIN(next_allowed_at) FROM regions
          WHERE last_success_at IS NULL) AS next_incomplete_region,
        (SELECT MIN(next_allowed_at) FROM regions) AS next_region,
        (SELECT MAX(last_success_at) FROM regions) AS last_success,
        (SELECT COUNT(*) FROM contracts WHERE item_status='pending') AS pending_items
      """,
      [.real(now.timeIntervalSince1970)]
    ).first
    let hasInitialWork =
      (state?.int("regions") ?? 0) == 0
      || (state?.int("incomplete_regions") ?? 0) > 0
      || (state?.int("pending_items") ?? 0) > 0
    let baseDate: Date
    if hasInitialWork {
      let hasEligibleWork =
        (state?.int("regions") ?? 0) == 0
        || (state?.int("eligible_incomplete_regions") ?? 0) > 0
        || (state?.int("pending_items") ?? 0) > 0
      baseDate =
        hasEligibleWork
        ? now
        : state?.double("next_incomplete_region").map {
          Date(timeIntervalSince1970: $0)
        } ?? now
    } else {
      let regionDate =
        state?.double("next_region").map {
          Date(timeIntervalSince1970: $0)
        } ?? now
      let regularDate =
        state?.double("last_success").map {
          Date(
            timeIntervalSince1970: $0
              + max(30 * 60, regularRefreshInterval)
          )
        } ?? now
      baseDate = max(regionDate, regularDate)
    }
    let nextRunAt = max(baseDate, safetyNotBefore ?? .distantPast, now)
    return PublicContractAutomationState(
      isEnabled: true,
      safetyNotBefore: safetyNotBefore,
      nextAutomaticRunAt: nextRunAt
    )
  }

  public func upsertRegions(_ regions: [(id: Int64, name: String)]) throws {
    try database.transaction {
      for region in regions {
        try database.run(
          """
          INSERT INTO regions(region_id, name) VALUES(?, ?)
          ON CONFLICT(region_id) DO UPDATE SET name=excluded.name
          """,
          [.integer(region.id), .text(region.name)]
        )
      }
    }
  }

  public func regionSchedule(now: Date) throws -> [(id: Int64, name: String)] {
    try database.query(
      """
      SELECT region_id, name
      FROM regions
      WHERE next_allowed_at IS NULL OR next_allowed_at <= ?
      ORDER BY CASE
                 WHEN last_success_at IS NULL THEN 0
                 WHEN status='unavailable' THEN 1
                 ELSE 2
               END,
               name COLLATE NOCASE, region_id
      """,
      [.real(now.timeIntervalSince1970)]
    ).compactMap { row in
      guard let id = row.int64("region_id"), let name = row.string("name")
      else { return nil }
      return (id, name)
    }
  }

  public func recordRegionSuccess(
    regionID: Int64,
    contracts: [ESIPublicContractDTO],
    fetchedAt: Date,
    nextAllowedAt: Date?
  ) throws {
    try database.transaction {
      let currentIDs = Set(contracts.map(\.contractID))
      let existingRows = try database.query(
        "SELECT contract_id FROM contracts WHERE region_id = ?",
        [.integer(regionID)]
      )
      for row in existingRows {
        guard let contractID = row.int64("contract_id") else { continue }
        if !currentIDs.contains(contractID) {
          try database.run(
            "DELETE FROM contracts WHERE contract_id = ?",
            [.integer(contractID)]
          )
        }
      }
      for contract in contracts {
        try upsert(contract: contract, regionID: regionID, observedAt: fetchedAt)
        try registerLocation(contract.startLocationID)
        try registerLocation(contract.endLocationID)
      }
      try database.run(
        """
        UPDATE regions
        SET last_attempt_at=?, last_success_at=?, next_allowed_at=?,
            status='fresh', error_message=NULL
        WHERE region_id=?
        """,
        [
          .real(fetchedAt.timeIntervalSince1970),
          .real(fetchedAt.timeIntervalSince1970),
          nextAllowedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
          .integer(regionID),
        ]
      )
    }
  }

  public func locationIDsNeedingResolution(
    now: Date,
    limit: Int = 1_000
  ) throws -> Set<Int64> {
    let boundedLimit = min(1_000, max(1, limit))
    return Set(
      try database.query(
        """
        SELECT location_id
        FROM contract_locations
        WHERE resolution_state IN ('pending', 'unavailable')
          AND (next_allowed_at IS NULL OR next_allowed_at <= ?)
        ORDER BY location_id
        LIMIT ?
        """,
        [
          .real(now.timeIntervalSince1970),
          .integer(Int64(boundedLimit)),
        ]
      ).compactMap { $0.int64("location_id") }
    )
  }

  public func recordLocationResolution(
    attemptedIDs: Set<Int64>,
    names: [Int64: String],
    attemptedAt: Date,
    retryAt: Date
  ) throws {
    try database.transaction {
      for locationID in attemptedIDs {
        let name = names[locationID]?.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let resolvedName = name.flatMap { $0.isEmpty ? nil : $0 }
        try database.run(
          """
          INSERT INTO contract_locations(
            location_id, name, resolution_state, last_attempt_at,
            next_allowed_at
          ) VALUES(?, ?, ?, ?, ?)
          ON CONFLICT(location_id) DO UPDATE SET
            name=excluded.name,
            resolution_state=excluded.resolution_state,
            last_attempt_at=excluded.last_attempt_at,
            next_allowed_at=excluded.next_allowed_at
          """,
          [
            .integer(locationID),
            resolvedName.map(PublicContractSQLiteValue.text) ?? .null,
            .text(resolvedName == nil ? "unavailable" : "named"),
            .real(attemptedAt.timeIntervalSince1970),
            resolvedName == nil ? .real(retryAt.timeIntervalSince1970) : .null,
          ]
        )
      }
    }
  }

  public func recordRegionFailure(
    regionID: Int64,
    attemptedAt: Date,
    retryAt: Date,
    diagnostic: String
  ) throws {
    try database.run(
      """
      UPDATE regions
      SET last_attempt_at=?, next_allowed_at=?, status='unavailable',
          error_message=?
      WHERE region_id=?
      """,
      [
        .real(attemptedAt.timeIntervalSince1970),
        .real(retryAt.timeIntervalSince1970),
        .text(diagnostic),
        .integer(regionID),
      ]
    )
  }

  public func pendingContractIDs(
    now: Date = .now,
    limit: Int = 100
  ) throws -> [Int64] {
    try database.transaction {
      try database.run(
        """
        DELETE FROM contracts
        WHERE item_status='pending' AND date_expired <= ?
        """,
        [.real(now.timeIntervalSince1970)]
      )
      try database.run(
        """
        UPDATE contracts
        SET item_status='not_applicable', item_error=NULL
        WHERE item_status='pending' AND contract_type IN ('courier', 'loan')
        """
      )
    }
    return try database.query(
      """
      SELECT contract_id
      FROM contracts
      WHERE item_status='pending' AND date_expired > ?
      ORDER BY date_issued DESC, contract_id
      LIMIT ?
      """,
      [
        .real(now.timeIntervalSince1970),
        .integer(Int64(min(250, max(1, limit)))),
      ]
    ).compactMap { $0.int64("contract_id") }
  }

  public func storeItems(
    contractID: Int64,
    items: [ESIPublicContractItemDTO],
    metadata: [Int64: PublicContractItemTypeMetadata],
    fetchedAt: Date
  ) throws {
    try database.transaction {
      try database.run(
        "DELETE FROM contract_items WHERE contract_id=?",
        [.integer(contractID)]
      )
      for item in items {
        let type = metadata[item.typeID]
        try database.run(
          """
          INSERT INTO contract_items(
            contract_id, record_id, type_id, type_name, group_id, group_name,
            category_id, category_name, is_included, quantity, item_id,
            raw_quantity, is_blueprint_copy
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
          [
            .integer(contractID), .integer(item.recordID),
            .integer(item.typeID), type.map { .text($0.typeName) } ?? .null,
            type.map { .integer($0.groupID) } ?? .null,
            type.map { .text($0.groupName) } ?? .null,
            type.map { .integer($0.categoryID) } ?? .null,
            type.map { .text($0.categoryName) } ?? .null,
            .integer(item.isIncluded ? 1 : 0), .integer(item.quantity),
            item.itemID.map(PublicContractSQLiteValue.integer) ?? .null,
            item.rawQuantity.map(PublicContractSQLiteValue.integer) ?? .null,
            item.isBlueprintCopy.map {
              .integer($0 ? 1 : 0)
            } ?? .null,
          ]
        )
      }
      try database.run(
        """
        UPDATE contracts
        SET item_status='ready', item_fetched_at=?, item_error=NULL
        WHERE contract_id=?
        """,
        [.real(fetchedAt.timeIntervalSince1970), .integer(contractID)]
      )
    }
  }

  public func recordItemFailure(
    contractID: Int64,
    diagnostic: String,
    terminal: Bool
  ) throws {
    try database.run(
      """
      UPDATE contracts
      SET item_status=?, item_error=?
      WHERE contract_id=?
      """,
      [
        .text(terminal ? "unavailable" : "pending"),
        .text(diagnostic), .integer(contractID),
      ]
    )
  }

  public func search(
    _ filter: PublicContractSearchFilter,
    now: Date = .now
  ) throws -> [PublicContractSearchResult] {
    let query = filter.itemQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 3 || filter.groupID != nil || filter.categoryID != nil
    else { return [] }

    var conditions = ["c.date_expired > ?"]
    var values: [PublicContractSQLiteValue] = [
      .real(now.timeIntervalSince1970)
    ]
    if query.count >= 3 {
      conditions.append("i.type_name LIKE ? ESCAPE '\\' COLLATE NOCASE")
      values.append(.text("%\(Self.likePattern(query))%"))
    }
    if let groupID = filter.groupID {
      conditions.append("i.group_id = ?")
      values.append(.integer(groupID))
    }
    if let categoryID = filter.categoryID {
      conditions.append("i.category_id = ?")
      values.append(.integer(categoryID))
    }
    switch filter.direction {
    case .included:
      conditions.append("i.is_included = 1")
    case .requested:
      conditions.append("i.is_included = 0")
    case .both:
      break
    }
    values.append(.text(query))
    values.append(.integer(Int64(filter.limit)))
    let rows = try database.query(
      """
      SELECT c.contract_id, i.record_id, c.region_id, r.name AS region_name,
             c.contract_type, c.for_corporation, c.title,
             c.price, c.buyout, c.reward,
             c.collateral, c.date_issued, c.date_expired,
             c.start_location_id, sl.name AS start_location_name,
             c.end_location_id, el.name AS end_location_name,
             i.type_id, i.type_name,
             i.group_id, i.group_name, i.category_id, i.category_name,
             i.is_included, i.quantity, i.is_blueprint_copy
      FROM contract_items i
      JOIN contracts c ON c.contract_id=i.contract_id
      JOIN regions r ON r.region_id=c.region_id
      LEFT JOIN contract_locations sl ON sl.location_id=c.start_location_id
      LEFT JOIN contract_locations el ON el.location_id=c.end_location_id
      WHERE \(conditions.joined(separator: " AND "))
      ORDER BY CASE WHEN i.type_name = ? COLLATE NOCASE THEN 0 ELSE 1 END,
               c.date_expired, c.contract_id, i.record_id
      LIMIT ?
      """,
      values
    )
    return try rows.map(Self.searchResult)
  }

  /// Resolves exact offered item types for industry planning in bounded bulk
  /// queries. This avoids one wildcard name scan per blueprint and cannot
  /// confuse similarly named types such as a blueprint and another item.
  public func includedOffers(
    typeIDs: Set<Int64>,
    now: Date = .now,
    limitPerType: Int = 100
  ) throws -> [Int64: [PublicContractSearchResult]] {
    let accepted = typeIDs.filter { $0 > 0 }.sorted()
    guard !accepted.isEmpty else { return [:] }
    let boundedLimit = min(500, max(1, limitPerType))
    var grouped: [Int64: [PublicContractSearchResult]] = [:]

    // Stay below SQLite's conservative host-parameter limit, leaving room for
    // the expiry and per-type limit bindings.
    for start in stride(from: 0, to: accepted.count, by: 400) {
      let chunk = Array(accepted[start..<min(start + 400, accepted.count)])
      let placeholders = Array(repeating: "?", count: chunk.count)
        .joined(separator: ",")
      var values: [PublicContractSQLiteValue] = [
        .real(now.timeIntervalSince1970)
      ]
      values.append(contentsOf: chunk.map(PublicContractSQLiteValue.integer))
      values.append(.integer(Int64(boundedLimit)))
      let rows = try database.query(
        """
        WITH ranked AS (
          SELECT c.contract_id, i.record_id, c.region_id,
                 r.name AS region_name, c.contract_type,
                 c.for_corporation, c.title, c.price, c.buyout, c.reward,
                 c.collateral, c.date_issued, c.date_expired,
                 c.start_location_id, sl.name AS start_location_name,
                 c.end_location_id, el.name AS end_location_name,
                 i.type_id, i.type_name, i.group_id, i.group_name,
                 i.category_id, i.category_name, i.is_included, i.quantity,
                 i.is_blueprint_copy,
                 ROW_NUMBER() OVER (
                   PARTITION BY i.type_id
                   ORDER BY c.date_expired, c.contract_id, i.record_id
                 ) AS result_rank
          FROM contract_items i
          JOIN contracts c ON c.contract_id=i.contract_id
          JOIN regions r ON r.region_id=c.region_id
          LEFT JOIN contract_locations sl
            ON sl.location_id=c.start_location_id
          LEFT JOIN contract_locations el
            ON el.location_id=c.end_location_id
          WHERE c.date_expired > ?
            AND i.is_included = 1
            AND i.type_id IN (\(placeholders))
        )
        SELECT * FROM ranked
        WHERE result_rank <= ?
        ORDER BY type_id, date_expired, contract_id, record_id
        """,
        values
      )
      for row in rows {
        let result = try Self.searchResult(row)
        grouped[result.typeID, default: []].append(result)
      }
    }
    return grouped
  }

  public func includedOfferSnapshot(
    typeIDs: Set<Int64>,
    now: Date = .now,
    limitPerType: Int = 100
  ) throws -> (
    offers: [Int64: [PublicContractSearchResult]],
    progress: PublicContractSyncProgress
  ) {
    let offers = try includedOffers(
      typeIDs: typeIDs,
      now: now,
      limitPerType: limitPerType
    )
    return (offers, try progress())
  }

  public func facets() throws -> (
    categories: [PublicContractFacet], groups: [PublicContractFacet]
  ) {
    let categories = try database.query(
      """
      SELECT category_id AS id, category_name AS name,
             COUNT(DISTINCT contract_id) AS result_count
      FROM contract_items
      WHERE category_id IS NOT NULL AND category_name IS NOT NULL
      GROUP BY category_id, category_name
      ORDER BY category_name COLLATE NOCASE
      """
    ).compactMap { row -> PublicContractFacet? in
      guard let id = row.int64("id"), let name = row.string("name"),
        let count = row.int("result_count")
      else { return nil }
      return PublicContractFacet(id: id, name: name, resultCount: count)
    }
    let groups = try database.query(
      """
      SELECT group_id AS id, group_name AS name, category_id AS parent_id,
             COUNT(DISTINCT contract_id) AS result_count
      FROM contract_items
      WHERE group_id IS NOT NULL AND group_name IS NOT NULL
      GROUP BY group_id, group_name, category_id
      ORDER BY group_name COLLATE NOCASE
      """
    ).compactMap { row -> PublicContractFacet? in
      guard let id = row.int64("id"), let name = row.string("name"),
        let count = row.int("result_count")
      else { return nil }
      return PublicContractFacet(
        id: id,
        name: name,
        parentID: row.int64("parent_id"),
        resultCount: count
      )
    }
    return (categories, groups)
  }

  public func progress(
    phase: PublicContractSyncPhase = .idle,
    activeRegionName: String? = nil,
    activeContractID: Int64? = nil,
    message: String? = nil,
    nextRequestAt: Date? = nil
  ) throws -> PublicContractSyncProgress {
    let counts = try database.query(
      """
      SELECT
        (SELECT COUNT(*) FROM regions) AS regions,
        (SELECT COUNT(*) FROM regions WHERE last_success_at IS NOT NULL)
          AS completed_regions,
        (SELECT COUNT(*) FROM regions WHERE status='fresh') AS fresh_regions,
        (SELECT COUNT(*) FROM regions WHERE last_success_at IS NULL)
          AS remaining_initial_regions,
        (SELECT COUNT(*) FROM regions WHERE status='unavailable') AS failed_regions,
        (SELECT error_message FROM regions
          WHERE status='unavailable' AND error_message IS NOT NULL
          GROUP BY error_message
          ORDER BY COUNT(*) DESC, error_message
          LIMIT 1) AS region_error_message,
        (SELECT MIN(next_allowed_at) FROM regions
          WHERE status='unavailable') AS failed_region_retry,
        (SELECT COUNT(*) FROM contracts) AS contracts,
        (SELECT COUNT(*) FROM contracts WHERE item_status='pending') AS pending,
        (SELECT COUNT(*) FROM contracts WHERE item_status='unavailable') AS failed_items,
        (SELECT COUNT(*) FROM contract_items) AS items,
        (SELECT MAX(last_success_at) FROM regions) AS completed_at
      """
    ).first
    return PublicContractSyncProgress(
      phase: phase,
      regionCount: counts?.int("regions") ?? 0,
      completedRegions: counts?.int("completed_regions") ?? 0,
      freshRegions: counts?.int("fresh_regions") ?? 0,
      remainingInitialRegions: counts?.int("remaining_initial_regions") ?? 0,
      activeRegionName: activeRegionName,
      activeContractID: activeContractID,
      activeContracts: counts?.int("contracts") ?? 0,
      indexedContracts: counts?.int("contracts") ?? 0,
      pendingItemContracts: counts?.int("pending") ?? 0,
      indexedItems: counts?.int("items") ?? 0,
      failedRegions: counts?.int("failed_regions") ?? 0,
      regionErrorMessage: counts?.string("region_error_message"),
      failedRegionRetryAt: counts?.double("failed_region_retry").map {
        Date(timeIntervalSince1970: $0)
      },
      failedItemContracts: counts?.int("failed_items") ?? 0,
      lastCompletedAt: counts?.double("completed_at").map {
        Date(timeIntervalSince1970: $0)
      },
      nextRequestAt: nextRequestAt,
      message: message
    )
  }

  private func upsert(
    contract: ESIPublicContractDTO,
    regionID: Int64,
    observedAt: Date
  ) throws {
    try database.run(
      """
      INSERT INTO contracts(
        contract_id, region_id, issuer_id, issuer_corporation_id,
        for_corporation, contract_type, title, price, buyout, reward,
        collateral, volume, date_issued, date_expired, days_to_complete,
        start_location_id, end_location_id, observed_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(contract_id) DO UPDATE SET
        region_id=excluded.region_id, issuer_id=excluded.issuer_id,
        issuer_corporation_id=excluded.issuer_corporation_id,
        for_corporation=excluded.for_corporation,
        contract_type=excluded.contract_type, title=excluded.title,
        price=excluded.price, buyout=excluded.buyout, reward=excluded.reward,
        collateral=excluded.collateral, volume=excluded.volume,
        date_issued=excluded.date_issued, date_expired=excluded.date_expired,
        days_to_complete=excluded.days_to_complete,
        start_location_id=excluded.start_location_id,
        end_location_id=excluded.end_location_id,
        observed_at=excluded.observed_at
      """,
      [
        .integer(contract.contractID), .integer(regionID),
        .integer(contract.issuerID), .integer(contract.issuerCorporationID),
        contract.forCorporation.map {
          .integer($0 ? 1 : 0)
        } ?? .null,
        .text(contract.type),
        contract.title.map(PublicContractSQLiteValue.text) ?? .null,
        contract.price.map(PublicContractSQLiteValue.real) ?? .null,
        contract.buyout.map(PublicContractSQLiteValue.real) ?? .null,
        contract.reward.map(PublicContractSQLiteValue.real) ?? .null,
        contract.collateral.map(PublicContractSQLiteValue.real) ?? .null,
        contract.volume.map(PublicContractSQLiteValue.real) ?? .null,
        .real(contract.dateIssued.timeIntervalSince1970),
        .real(contract.dateExpired.timeIntervalSince1970),
        contract.daysToComplete.map { .integer(Int64($0)) } ?? .null,
        contract.startLocationID.map(PublicContractSQLiteValue.integer) ?? .null,
        contract.endLocationID.map(PublicContractSQLiteValue.integer) ?? .null,
        .real(observedAt.timeIntervalSince1970),
      ]
    )
  }

  private func setting(key: String) throws -> String? {
    try database.query(
      "SELECT value FROM contract_settings WHERE key=?",
      [.text(key)]
    ).first?.string("value")
  }

  private func setSetting(key: String, value: String?) throws {
    if let value {
      try database.run(
        """
        INSERT INTO contract_settings(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value
        """,
        [.text(key), .text(value)]
      )
    } else {
      try database.run(
        "DELETE FROM contract_settings WHERE key=?",
        [.text(key)]
      )
    }
  }

  private static func searchResult(
    _ row: PublicContractSQLiteRow
  ) throws -> PublicContractSearchResult {
    guard let contractID = row.int64("contract_id"),
      let recordID = row.int64("record_id"),
      let regionID = row.int64("region_id"),
      let regionName = row.string("region_name"),
      let contractType = row.string("contract_type"),
      let issued = row.double("date_issued"),
      let expired = row.double("date_expired"),
      let typeID = row.int64("type_id"),
      let included = row.int("is_included"),
      let quantity = row.int64("quantity")
    else { throw PublicContractStoreError.invalidRow }
    return PublicContractSearchResult(
      contractID: contractID,
      recordID: recordID,
      regionID: regionID,
      regionName: regionName,
      contractType: contractType,
      forCorporation: row.int("for_corporation").map { $0 == 1 },
      title: row.string("title"),
      price: row.double("price"),
      buyout: row.double("buyout"),
      reward: row.double("reward"),
      collateral: row.double("collateral"),
      dateIssued: Date(timeIntervalSince1970: issued),
      dateExpired: Date(timeIntervalSince1970: expired),
      startLocationID: row.int64("start_location_id"),
      startLocationName: row.string("start_location_name"),
      endLocationID: row.int64("end_location_id"),
      endLocationName: row.string("end_location_name"),
      typeID: typeID,
      typeName: row.string("type_name"),
      groupID: row.int64("group_id"),
      groupName: row.string("group_name"),
      categoryID: row.int64("category_id"),
      categoryName: row.string("category_name"),
      isIncluded: included == 1,
      quantity: quantity,
      isBlueprintCopy: row.int("is_blueprint_copy").map { $0 == 1 }
    )
  }

  private static func likePattern(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  private func registerLocation(_ locationID: Int64?) throws {
    guard let locationID, locationID > 0 else { return }
    let state =
      locationID >= Self.playerStructureIDFloor
      ? "authorization_required" : "pending"
    try database.run(
      """
      INSERT INTO contract_locations(location_id, resolution_state)
      VALUES(?, ?)
      ON CONFLICT(location_id) DO NOTHING
      """,
      [.integer(locationID), .text(state)]
    )
  }

  private static func backfillContractLocations(
    in database: PublicContractSQLiteDatabase
  ) throws {
    try database.transaction {
      for statement in [
        """
        INSERT OR IGNORE INTO contract_locations(
          location_id, resolution_state
        )
        SELECT DISTINCT start_location_id,
               CASE WHEN start_location_id >= 1000000000000
                    THEN 'authorization_required' ELSE 'pending' END
        FROM contracts
        WHERE start_location_id IS NOT NULL AND start_location_id > 0
        """,
        """
        INSERT OR IGNORE INTO contract_locations(
          location_id, resolution_state
        )
        SELECT DISTINCT end_location_id,
               CASE WHEN end_location_id >= 1000000000000
                    THEN 'authorization_required' ELSE 'pending' END
        FROM contracts
        WHERE end_location_id IS NOT NULL AND end_location_id > 0
        """,
      ] {
        try database.run(
          statement
        )
      }
    }
  }

  private static func migrateOptionalForCorporation(
    in database: PublicContractSQLiteDatabase
  ) throws {
    let requiresMigration = try database.query(
      "PRAGMA table_info(contracts)"
    ).contains { row in
      row.string("name") == "for_corporation" && row.int("notnull") == 1
    }
    guard requiresMigration else { return }

    try database.execute("PRAGMA foreign_keys=OFF")
    defer { try? database.execute("PRAGMA foreign_keys=ON") }
    try database.transaction {
      try database.execute(
        """
        CREATE TABLE contracts_optional_for_corporation(
          contract_id INTEGER PRIMARY KEY,
          region_id INTEGER NOT NULL REFERENCES regions(region_id),
          issuer_id INTEGER NOT NULL,
          issuer_corporation_id INTEGER NOT NULL,
          for_corporation INTEGER,
          contract_type TEXT NOT NULL,
          title TEXT,
          price REAL,
          buyout REAL,
          reward REAL,
          collateral REAL,
          volume REAL,
          date_issued REAL NOT NULL,
          date_expired REAL NOT NULL,
          days_to_complete INTEGER,
          start_location_id INTEGER,
          end_location_id INTEGER,
          observed_at REAL NOT NULL,
          item_status TEXT NOT NULL DEFAULT 'pending',
          item_fetched_at REAL,
          item_error TEXT
        )
        """
      )
      try database.execute(
        """
        INSERT INTO contracts_optional_for_corporation
        SELECT contract_id, region_id, issuer_id, issuer_corporation_id,
               for_corporation, contract_type, title, price, buyout, reward,
               collateral, volume, date_issued, date_expired,
               days_to_complete, start_location_id, end_location_id,
               observed_at, item_status, item_fetched_at, item_error
        FROM contracts
        """
      )
      try database.execute("DROP TABLE contracts")
      try database.execute(
        "ALTER TABLE contracts_optional_for_corporation RENAME TO contracts"
      )
    }
    try database.execute(Self.contractIndexes)
    guard try database.query("PRAGMA foreign_key_check").isEmpty else {
      throw PublicContractStoreError.database(
        "contracts migration failed foreign-key validation"
      )
    }
  }

  private static let playerStructureIDFloor: Int64 = 1_000_000_000_000

  private static let schema = """
      CREATE TABLE IF NOT EXISTS regions(
        region_id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        last_attempt_at REAL,
        last_success_at REAL,
        next_allowed_at REAL,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT
      );
      CREATE TABLE IF NOT EXISTS contracts(
        contract_id INTEGER PRIMARY KEY,
        region_id INTEGER NOT NULL REFERENCES regions(region_id),
        issuer_id INTEGER NOT NULL,
        issuer_corporation_id INTEGER NOT NULL,
        for_corporation INTEGER,
        contract_type TEXT NOT NULL,
        title TEXT,
        price REAL,
        buyout REAL,
        reward REAL,
        collateral REAL,
        volume REAL,
        date_issued REAL NOT NULL,
        date_expired REAL NOT NULL,
        days_to_complete INTEGER,
        start_location_id INTEGER,
        end_location_id INTEGER,
        observed_at REAL NOT NULL,
        item_status TEXT NOT NULL DEFAULT 'pending',
        item_fetched_at REAL,
        item_error TEXT
      );
      CREATE TABLE IF NOT EXISTS contract_items(
        contract_id INTEGER NOT NULL REFERENCES contracts(contract_id)
          ON DELETE CASCADE,
        record_id INTEGER NOT NULL,
        type_id INTEGER NOT NULL,
        type_name TEXT,
        group_id INTEGER,
        group_name TEXT,
        category_id INTEGER,
        category_name TEXT,
        is_included INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        item_id INTEGER,
        raw_quantity INTEGER,
        is_blueprint_copy INTEGER,
        PRIMARY KEY(contract_id, record_id)
      );
      CREATE TABLE IF NOT EXISTS contract_locations(
        location_id INTEGER PRIMARY KEY,
        name TEXT,
        resolution_state TEXT NOT NULL,
        last_attempt_at REAL,
        next_allowed_at REAL
      );
      CREATE TABLE IF NOT EXISTS contract_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      \(contractIndexes)
      CREATE INDEX IF NOT EXISTS idx_contract_item_name
        ON contract_items(type_name COLLATE NOCASE);
      CREATE INDEX IF NOT EXISTS idx_contract_item_group
        ON contract_items(group_id, category_id, is_included);
      CREATE INDEX IF NOT EXISTS idx_contract_item_type
        ON contract_items(type_id, is_included, contract_id);
    """

  private static let contractIndexes = """
      CREATE INDEX IF NOT EXISTS idx_contract_region
        ON contracts(region_id);
      CREATE INDEX IF NOT EXISTS idx_contract_expiry
        ON contracts(date_expired);
      CREATE INDEX IF NOT EXISTS idx_contract_item_status
        ON contracts(item_status, date_issued);
    """
}

private enum PublicContractSQLiteValue {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
}

private struct PublicContractSQLiteRow {
  let values: [String: PublicContractSQLiteValue]

  func string(_ key: String) -> String? {
    guard case .text(let value) = values[key] else { return nil }
    return value
  }

  func int64(_ key: String) -> Int64? {
    switch values[key] {
    case .integer(let value): value
    case .real(let value): Int64(value)
    case .text(let value): Int64(value)
    default: nil
    }
  }

  func int(_ key: String) -> Int? { int64(key).flatMap(Int.init) }

  func double(_ key: String) -> Double? {
    switch values[key] {
    case .real(let value): value
    case .integer(let value): Double(value)
    case .text(let value): Double(value)
    default: nil
    }
  }
}

private final class PublicContractSQLiteDatabase: @unchecked Sendable {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    let status = sqlite3_open_v2(
      url.path,
      &handle,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard status == SQLITE_OK else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
      sqlite3_close(handle)
      throw PublicContractStoreError.database(message)
    }
    sqlite3_busy_timeout(handle, 5_000)
  }

  deinit { close() }

  func close() {
    guard let handle else { return }
    sqlite3_close_v2(handle)
    self.handle = nil
  }

  func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try body()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func execute(_ sql: String) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
    guard status == SQLITE_OK else {
      let message =
        errorPointer.map { String(cString: $0) }
        ?? handle.map { String(cString: sqlite3_errmsg($0)) } ?? "execute"
      sqlite3_free(errorPointer)
      throw PublicContractStoreError.database(message)
    }
  }

  func run(_ sql: String, _ values: [PublicContractSQLiteValue] = []) throws {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw databaseError("step")
    }
  }

  func query(
    _ sql: String,
    _ values: [PublicContractSQLiteValue] = []
  ) throws -> [PublicContractSQLiteRow] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    var rows: [PublicContractSQLiteRow] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw databaseError("query") }
      var row: [String: PublicContractSQLiteValue] = [:]
      for index in 0..<sqlite3_column_count(statement) {
        guard let rawName = sqlite3_column_name(statement, index) else { continue }
        let name = String(cString: rawName)
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
          row[name] = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
          row[name] = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
          if let text = sqlite3_column_text(statement, index) {
            row[name] = .text(String(cString: text))
          }
        default:
          row[name] = .null
        }
      }
      rows.append(PublicContractSQLiteRow(values: row))
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
    else { throw databaseError("prepare") }
    return statement
  }

  private func bind(
    _ values: [PublicContractSQLiteValue],
    to statement: OpaquePointer?
  ) throws {
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case .null:
        status = sqlite3_bind_null(statement, index)
      case .integer(let value):
        status = sqlite3_bind_int64(statement, index, value)
      case .real(let value):
        status = sqlite3_bind_double(statement, index, value)
      case .text(let value):
        status = sqlite3_bind_text(
          statement,
          index,
          value,
          -1,
          unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
      }
      guard status == SQLITE_OK else { throw databaseError("bind") }
    }
  }

  private func databaseError(_ operation: String) -> PublicContractStoreError {
    .database(
      handle.map { "\(operation): \(String(cString: sqlite3_errmsg($0)))" }
        ?? operation
    )
  }
}
