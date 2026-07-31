import Foundation
import SwiftData

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
