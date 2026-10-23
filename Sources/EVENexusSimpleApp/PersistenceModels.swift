import EVENexusCore
import Foundation
import SwiftData

enum AppSettingKey {
  static let ccpUserAgentOwnerContact = "sde.ownerContact"
  static let industryJobsPrefix = "dashboard.industry-jobs."
  static let openOrdersPrefix = "net-worth.open-orders."
  static let privateContractsPrefix = "net-worth.private-contracts."
  static let corporationWalletPrefix = "net-worth.corporation-wallet."
  static let dashboardWealthHistory = "dashboard.wealth-history.v1"
  /// Planner draft target market (HUB_CHANCEN_PLAN P10); value is the raw
  /// `PlannerTargetMarket`, a missing row means not chosen.
  static let plannerTargetMarketDraft = "planner.target-market.draft.v1"
  /// Planner draft input of the manual alliance sale (P11), JSON-encoded
  /// `PlannerAllianceSaleInput`.
  static let plannerAllianceSaleDraft = "planner.alliance-sale.draft.v1"

  static func industryJobs(characterID: Int64) -> String {
    "\(industryJobsPrefix)\(characterID)"
  }

  static func openOrders(characterID: Int64) -> String {
    "\(openOrdersPrefix)\(characterID)"
  }

  static func privateContracts(characterID: Int64) -> String {
    "\(privateContractsPrefix)\(characterID)"
  }

  static func corporationWallet(characterID: Int64) -> String {
    "\(corporationWalletPrefix)\(characterID)"
  }
}

enum EVENexusSchemaV2: VersionedSchema {
  static var versionIdentifier: Schema.Version {
    Schema.Version(2, 0, 0)
  }
  static let models: [any PersistentModel.Type] = [
    StoredProductionBasis.self,
    StoredManufacturingProfile.self,
    StoredReactionProfile.self,
    StoredCharacter.self,
    StoredStockTarget.self,
    StoredPlan.self,
    StoredPlannerDraft.self,
    StoredProductionRecord.self,
    StoredProductionOverviewRow.self,
    StoredSDEActivationPointer.self,
    StoredESISnapshotMetadata.self,
    AppSetting.self,
  ]
}

enum EVENexusMigrationPlan: SchemaMigrationPlan {
  static let schemas: [any VersionedSchema.Type] = [
    EVENexusSchemaV1.self,
    EVENexusSchemaV2.self,
    EVENexusSchemaV3.self,
  ]
  static var stages: [MigrationStage] {
    [
      .lightweight(
        fromVersion: EVENexusSchemaV1.self,
        toVersion: EVENexusSchemaV2.self
      ),
      .lightweight(fromVersion: EVENexusSchemaV2.self, toVersion: EVENexusSchemaV3.self)
    ]
  }
}

@MainActor
enum AppPersistence {
  static let schemaVersion = 3

  static func open(paths: AppDataPaths) throws -> ModelContainer {
    try ConsolidationPreferences.applyPending(paths: paths)
    try paths.prepareDirectories()
    _ = try PersistenceStoreSeeder.seedCanonicalStoreIfNeeded(paths: paths)
    _ = try PersistenceSafetyBackup.createIfNeeded(
      paths: paths,
      schemaVersion: schemaVersion
    )
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let configuration = ModelConfiguration(
      "EVENexusSimple",
      schema: schema,
      url: paths.swiftDataStoreURL,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(
      for: schema,
      migrationPlan: EVENexusMigrationPlan.self,
      configurations: [configuration]
    )
    try PersistenceRecovery.mergeIfPending(
      into: container,
      dataRoot: paths.dataRoot
    )
    return container
  }
}

@Model
final class StoredProductionBasis {
  @Attribute(.unique) var id: UUID
  var name: String
  var encodedBasis: Data
  var updatedAt: Date

  init(id: UUID, name: String, encodedBasis: Data, updatedAt: Date = .now) {
    self.id = id
    self.name = name
    self.encodedBasis = encodedBasis
    self.updatedAt = updatedAt
  }
}

@Model
final class StoredManufacturingProfile {
  @Attribute(.unique) var id: UUID
  var name: String
  var encodedProfile: Data
  var updatedAt: Date

  init(id: UUID, name: String, encodedProfile: Data, updatedAt: Date = .now) {
    self.id = id
    self.name = name
    self.encodedProfile = encodedProfile
    self.updatedAt = updatedAt
  }
}

@Model
final class StoredReactionProfile {
  @Attribute(.unique) var id: UUID
  var name: String
  var encodedProfile: Data
  var updatedAt: Date

  init(id: UUID, name: String, encodedProfile: Data, updatedAt: Date = .now) {
    self.id = id
    self.name = name
    self.encodedProfile = encodedProfile
    self.updatedAt = updatedAt
  }
}

@Model
final class StoredCharacter {
  @Attribute(.unique) var characterID: Int64
  var characterName: String
  var authorizationSnapshot: Data
  var capabilitySnapshot: Data?
  var assetSnapshot: Data?
  var corporationID: Int64?
  var corporationName: String?
  var corporationAssetSnapshot: Data?
  var blueprintSnapshot: Data?
  var walletBalanceSnapshot: Data?
  var lastSyncAt: Date?
  var walletLastSyncAt: Date?

  init(
    characterID: Int64,
    characterName: String,
    authorizationSnapshot: Data,
    capabilitySnapshot: Data? = nil,
    assetSnapshot: Data? = nil,
    corporationID: Int64? = nil,
    corporationName: String? = nil,
    corporationAssetSnapshot: Data? = nil,
    blueprintSnapshot: Data? = nil,
    walletBalanceSnapshot: Data? = nil,
    lastSyncAt: Date? = nil,
    walletLastSyncAt: Date? = nil
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.authorizationSnapshot = authorizationSnapshot
    self.capabilitySnapshot = capabilitySnapshot
    self.assetSnapshot = assetSnapshot
    self.corporationID = corporationID
    self.corporationName = corporationName
    self.corporationAssetSnapshot = corporationAssetSnapshot
    self.blueprintSnapshot = blueprintSnapshot
    self.walletBalanceSnapshot = walletBalanceSnapshot
    self.lastSyncAt = lastSyncAt
    self.walletLastSyncAt = walletLastSyncAt
  }
}

@Model
final class StoredStockTarget {
  @Attribute(.unique) var typeID: Int64
  var typeName: String
  var targetQuantity: Int64
  var updatedAt: Date

  init(
    typeID: Int64,
    typeName: String,
    targetQuantity: Int64,
    updatedAt: Date = .now
  ) {
    self.typeID = typeID
    self.typeName = typeName
    self.targetQuantity = max(0, targetQuantity)
    self.updatedAt = updatedAt
  }
}

@Model
final class StoredPlan {
  @Attribute(.unique) var id: UUID
  var name: String
  var input: String
  var snapshot: Data
  var sdeBuild: Int
  var esiCompatibilityDate: String
  var priceTimestamp: Date
  var ruleVersion: String
  var isActive: Bool

  init(
    id: UUID,
    name: String,
    input: String,
    snapshot: Data,
    sdeBuild: Int,
    esiCompatibilityDate: String,
    priceTimestamp: Date,
    ruleVersion: String,
    isActive: Bool
  ) {
    self.id = id
    self.name = name
    self.input = input
    self.snapshot = snapshot
    self.sdeBuild = sdeBuild
    self.esiCompatibilityDate = esiCompatibilityDate
    self.priceTimestamp = priceTimestamp
    self.ruleVersion = ruleVersion
    self.isActive = isActive
  }
}

@Model
final class StoredPlannerDraft {
  @Attribute(.unique) var key: String
  var input: String
  var manualStockInput: String
  var updatedAt: Date

  init(
    key: String = "primary",
    input: String,
    manualStockInput: String,
    updatedAt: Date = .now
  ) {
    self.key = key
    self.input = input
    self.manualStockInput = manualStockInput
    self.updatedAt = updatedAt
  }
}

@Model
final class StoredProductionRecord {
  @Attribute(.unique) var id: UUID
  var planID: UUID
  var name: String
  var input: String
  var manualStockInput: String
  var snapshot: Data
  var completedAt: Date
  var sdeBuild: Int
  var esiCompatibilityDate: String
  var priceTimestamp: Date
  var ruleVersion: String

  init(
    id: UUID = UUID(),
    planID: UUID,
    name: String,
    input: String,
    manualStockInput: String,
    snapshot: Data,
    completedAt: Date = .now,
    sdeBuild: Int,
    esiCompatibilityDate: String,
    priceTimestamp: Date,
    ruleVersion: String
  ) {
    self.id = id
    self.planID = planID
    self.name = name
    self.input = input
    self.manualStockInput = manualStockInput
    self.snapshot = snapshot
    self.completedAt = completedAt
    self.sdeBuild = sdeBuild
    self.esiCompatibilityDate = esiCompatibilityDate
    self.priceTimestamp = priceTimestamp
    self.ruleVersion = ruleVersion
  }
}

@Model
final class StoredProductionOverviewRow {
  @Attribute(.unique) var id: UUID
  var sequenceNumber: Int
  var recordedAt: Date
  var planID: UUID
  var requestID: UUID
  var productName: String
  var runs: Int64
  var materialEfficiency: Int
  var timeEfficiency: Int
  var systemName: String
  var units: Int64
  var materialCost: Double?
  var indexCost: Double?
  var blueprintCost: Double?
  var marketTax: Double?
  var salePricePerUnit: Double?
  var soldUnits: Int64
  var sourceSnapshot: Data
  var sdeBuild: Int
  var esiCompatibilityDate: String
  var priceTimestamp: Date
  var ruleVersion: String

  init(
    id: UUID = UUID(),
    sequenceNumber: Int,
    recordedAt: Date = .now,
    planID: UUID,
    requestID: UUID,
    productName: String,
    runs: Int64,
    materialEfficiency: Int,
    timeEfficiency: Int,
    systemName: String,
    units: Int64,
    materialCost: Double?,
    indexCost: Double?,
    blueprintCost: Double? = nil,
    marketTax: Double?,
    salePricePerUnit: Double?,
    soldUnits: Int64 = 0,
    sourceSnapshot: Data,
    sdeBuild: Int,
    esiCompatibilityDate: String,
    priceTimestamp: Date,
    ruleVersion: String
  ) {
    self.id = id
    self.sequenceNumber = sequenceNumber
    self.recordedAt = recordedAt
    self.planID = planID
    self.requestID = requestID
    self.productName = productName
    self.runs = runs
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.systemName = systemName
    self.units = units
    self.materialCost = materialCost
    self.indexCost = indexCost
    self.blueprintCost = blueprintCost
    self.marketTax = marketTax
    self.salePricePerUnit = salePricePerUnit
    self.soldUnits = soldUnits
    self.sourceSnapshot = sourceSnapshot
    self.sdeBuild = sdeBuild
    self.esiCompatibilityDate = esiCompatibilityDate
    self.priceTimestamp = priceTimestamp
    self.ruleVersion = ruleVersion
  }
}

@Model
final class StoredSDEActivationPointer {
  @Attribute(.unique) var key: String
  var buildNumber: Int
  var contentSHA256: String
  var activatedAt: Date

  init(
    key: String = "active",
    buildNumber: Int,
    contentSHA256: String,
    activatedAt: Date = .now
  ) {
    self.key = key
    self.buildNumber = buildNumber
    self.contentSHA256 = contentSHA256
    self.activatedAt = activatedAt
  }
}

@Model
final class StoredESISnapshotMetadata {
  @Attribute(.unique) var id: UUID
  var characterID: Int64
  var domain: String
  var freshness: String
  var provider: String
  var sourceVersion: String
  var sourceSnapshotID: UUID
  var capturedAt: Date
  var diagnostics: [String]

  init(
    id: UUID = UUID(),
    characterID: Int64,
    domain: String,
    freshness: String,
    provider: String,
    sourceVersion: String,
    sourceSnapshotID: UUID,
    capturedAt: Date,
    diagnostics: [String]
  ) {
    self.id = id
    self.characterID = characterID
    self.domain = domain
    self.freshness = freshness
    self.provider = provider
    self.sourceVersion = sourceVersion
    self.sourceSnapshotID = sourceSnapshotID
    self.capturedAt = capturedAt
    self.diagnostics = diagnostics
  }
}

@Model
final class AppSetting {
  @Attribute(.unique) var key: String
  var value: String

  init(key: String, value: String) {
    self.key = key
    self.value = value
  }
}

extension ModelContext {
  func appSettingValue(for key: String) throws -> String? {
    let descriptor = FetchDescriptor<AppSetting>(
      predicate: #Predicate { $0.key == key }
    )
    return try fetch(descriptor).first?.value
  }

  func upsertAppSetting(key: String, value: String) throws {
    let descriptor = FetchDescriptor<AppSetting>(
      predicate: #Predicate { $0.key == key }
    )
    let matches = try fetch(descriptor)
    if let setting = matches.first {
      setting.value = value
      for duplicate in matches.dropFirst() {
        delete(duplicate)
      }
    } else {
      insert(AppSetting(key: key, value: value))
    }
  }

  func deleteAppSetting(key: String) throws {
    let descriptor = FetchDescriptor<AppSetting>(
      predicate: #Predicate { $0.key == key }
    )
    for setting in try fetch(descriptor) {
      delete(setting)
    }
  }

  func upsertESISnapshotMetadata(
    characterID: Int64,
    domain: String,
    freshness: String,
    provider: String,
    sourceVersion: String,
    sourceSnapshotID: UUID,
    capturedAt: Date,
    diagnostics: [String]
  ) throws {
    let descriptor = FetchDescriptor<StoredESISnapshotMetadata>(
      predicate: #Predicate {
        $0.characterID == characterID && $0.domain == domain
      },
      sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    let matches = try fetch(descriptor)
    let metadata: StoredESISnapshotMetadata
    if let current = matches.first {
      metadata = current
      for duplicate in matches.dropFirst() {
        delete(duplicate)
      }
    } else {
      metadata = StoredESISnapshotMetadata(
        characterID: characterID,
        domain: domain,
        freshness: freshness,
        provider: provider,
        sourceVersion: sourceVersion,
        sourceSnapshotID: sourceSnapshotID,
        capturedAt: capturedAt,
        diagnostics: diagnostics
      )
      insert(metadata)
    }
    metadata.freshness = freshness
    metadata.provider = provider
    metadata.sourceVersion = sourceVersion
    metadata.sourceSnapshotID = sourceSnapshotID
    metadata.capturedAt = capturedAt
    metadata.diagnostics = diagnostics
  }

  func deleteESISnapshotMetadata(characterID: Int64) throws {
    let descriptor = FetchDescriptor<StoredESISnapshotMetadata>(
      predicate: #Predicate { $0.characterID == characterID }
    )
    for metadata in try fetch(descriptor) {
      delete(metadata)
    }
  }
}

@MainActor
enum CharacterSyncPersistence {
  static func apply(
    _ latest: CharacterSyncSnapshot,
    to character: StoredCharacter,
    in modelContext: ModelContext
  ) throws {
    // The previous snapshot only matters when a refresh returned no value.
    let needsPreviousCapabilities =
      latest.capabilities.skills.value == nil
      || latest.capabilities.standings.value == nil
    let previousCapabilities =
      needsPreviousCapabilities
      ? character.capabilitySnapshot.flatMap {
        try? JSONDecoder().decode(CharacterCapabilitySnapshot.self, from: $0)
      } : nil
    character.capabilitySnapshot = try JSONEncoder().encode(
      CharacterCapabilitySnapshot(
        id: latest.capabilities.id,
        character: latest.capabilities.character,
        cloneState: latest.capabilities.cloneState,
        skills: latest.capabilities.skills.retainingLastKnownValue(
          from: previousCapabilities?.skills
        ),
        standings: latest.capabilities.standings.retainingLastKnownValue(
          from: previousCapabilities?.standings
        )
      )
    )
    character.assetSnapshot = try retainedData(
      latest.assets,
      previousData: character.assetSnapshot
    )

    let previousCorporationID = character.corporationID
    let latestCorporationID = latest.capabilities.character.corporationID
    let canRetainCorporation = previousCorporationID == latestCorporationID
    character.corporationID = latestCorporationID
    character.corporationName =
      latest.corporationAssets.value?.corporationName
      ?? (canRetainCorporation ? character.corporationName : nil)
    character.corporationAssetSnapshot = try retainedData(
      latest.corporationAssets,
      previousData: canRetainCorporation
        ? character.corporationAssetSnapshot : nil
    )
    character.blueprintSnapshot = try retainedData(
      latest.blueprints,
      previousData: character.blueprintSnapshot
    )
    try persistSettingSnapshot(
      latest.jobs,
      key: AppSettingKey.industryJobs(characterID: character.characterID),
      in: modelContext
    )
    try persistSettingSnapshot(
      latest.openOrders,
      key: AppSettingKey.openOrders(characterID: character.characterID),
      in: modelContext
    )
    try persistSettingSnapshot(
      latest.privateContracts,
      key: AppSettingKey.privateContracts(characterID: character.characterID),
      in: modelContext
    )
    try persistCorporationWallet(
      latest.corporationWallet,
      characterID: character.characterID,
      corporationID: latestCorporationID,
      canRetainPrevious: canRetainCorporation,
      in: modelContext
    )
    character.walletBalanceSnapshot = try retainedData(
      latest.walletBalance,
      previousData: character.walletBalanceSnapshot
    )
    character.lastSyncAt = .now
    if latest.walletBalance.value != nil {
      character.walletLastSyncAt = latest.walletBalance.source.capturedAt
    }
    try persistMetadata(latest, in: modelContext)
  }

  private static func retainedData<Value: Codable & Sendable>(
    _ latest: Sourced<Value>,
    previousData: Data?
  ) throws -> Data {
    // `retainingLastKnownValue` ignores the previous snapshot whenever the
    // latest refresh has a value, so large blobs are decoded only on failure.
    let previous =
      latest.value == nil
      ? previousData.flatMap {
        try? JSONDecoder().decode(Sourced<Value>.self, from: $0)
      } : nil
    return try JSONEncoder().encode(
      latest.retainingLastKnownValue(from: previous)
    )
  }

  private static func persistSettingSnapshot<Value: Codable & Sendable>(
    _ latest: Sourced<Value>,
    key: String,
    in modelContext: ModelContext
  ) throws {
    let previous =
      latest.value == nil
      ? try modelContext.appSettingValue(for: key).flatMap {
        Data(base64Encoded: $0)
      }.flatMap {
        try? JSONDecoder().decode(Sourced<Value>.self, from: $0)
      } : nil
    let data = try JSONEncoder().encode(
      latest.retainingLastKnownValue(from: previous)
    )
    try modelContext.upsertAppSetting(
      key: key,
      value: data.base64EncodedString()
    )
  }

  private static func persistCorporationWallet(
    _ latest: Sourced<CorporationWalletSnapshot>,
    characterID: Int64,
    corporationID: Int64?,
    canRetainPrevious: Bool,
    in modelContext: ModelContext
  ) throws {
    let key = AppSettingKey.corporationWallet(characterID: characterID)
    let storedPrevious =
      latest.value == nil
      ? try modelContext.appSettingValue(for: key).flatMap {
        Data(base64Encoded: $0)
      }.flatMap {
        try? JSONDecoder().decode(
          Sourced<CorporationWalletSnapshot>.self,
          from: $0
        )
      } : nil
    let previous =
      canRetainPrevious && storedPrevious?.value?.corporationID == corporationID
      ? storedPrevious : nil
    let data = try JSONEncoder().encode(
      latest.retainingLastKnownValue(from: previous)
    )
    try modelContext.upsertAppSetting(
      key: key,
      value: data.base64EncodedString()
    )
  }

  private static func persistMetadata(
    _ snapshot: CharacterSyncSnapshot,
    in modelContext: ModelContext
  ) throws {
    let characterID = snapshot.authorization.characterID
    try persistMetadata(
      snapshot.capabilities.skills,
      domain: "skills",
      characterID: characterID,
      in: modelContext
    )
    try persistMetadata(
      snapshot.capabilities.standings,
      domain: "standings",
      characterID: characterID,
      in: modelContext
    )
    try persistMetadata(
      snapshot.blueprints, domain: "blueprints", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.assets, domain: "assets", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.corporationAssets, domain: "corporation-assets", characterID: characterID,
      in: modelContext)
    try persistMetadata(
      snapshot.jobs, domain: "industry-jobs", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.openOrders, domain: "open-orders", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.orderHistory, domain: "order-history", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.privateContracts, domain: "private-contracts", characterID: characterID,
      in: modelContext)
    try persistMetadata(
      snapshot.walletBalance, domain: "wallet-balance", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.walletJournal, domain: "wallet-journal", characterID: characterID, in: modelContext)
    try persistMetadata(
      snapshot.walletTransactions, domain: "wallet-transactions", characterID: characterID,
      in: modelContext)
    try persistMetadata(
      snapshot.corporationWallet, domain: "corporation-wallet", characterID: characterID,
      in: modelContext)
  }

  private static func persistMetadata<Value: Codable & Sendable>(
    _ sourced: Sourced<Value>,
    domain: String,
    characterID: Int64,
    in modelContext: ModelContext
  ) throws {
    try modelContext.upsertESISnapshotMetadata(
      characterID: characterID,
      domain: domain,
      freshness: sourced.state.rawValue,
      provider: sourced.source.provider,
      sourceVersion: sourced.source.version,
      sourceSnapshotID: sourced.source.snapshotID,
      capturedAt: sourced.source.capturedAt,
      diagnostics: sourced.diagnostics
    )
  }
}
