import Foundation

public struct ESIPublicContractDTO: Codable, Equatable, Sendable {
  public let buyout: Double?
  public let collateral: Double?
  public let contractID: Int64
  public let dateExpired: Date
  public let dateIssued: Date
  public let daysToComplete: Int?
  public let endLocationID: Int64?
  public let forCorporation: Bool?
  public let issuerCorporationID: Int64
  public let issuerID: Int64
  public let price: Double?
  public let reward: Double?
  public let startLocationID: Int64?
  public let title: String?
  public let type: String
  public let volume: Double?

  public init(
    buyout: Double? = nil,
    collateral: Double? = nil,
    contractID: Int64,
    dateExpired: Date,
    dateIssued: Date,
    daysToComplete: Int? = nil,
    endLocationID: Int64? = nil,
    forCorporation: Bool? = nil,
    issuerCorporationID: Int64,
    issuerID: Int64,
    price: Double? = nil,
    reward: Double? = nil,
    startLocationID: Int64? = nil,
    title: String? = nil,
    type: String,
    volume: Double? = nil
  ) {
    self.buyout = buyout
    self.collateral = collateral
    self.contractID = contractID
    self.dateExpired = dateExpired
    self.dateIssued = dateIssued
    self.daysToComplete = daysToComplete
    self.endLocationID = endLocationID
    self.forCorporation = forCorporation
    self.issuerCorporationID = issuerCorporationID
    self.issuerID = issuerID
    self.price = price
    self.reward = reward
    self.startLocationID = startLocationID
    self.title = title
    self.type = type
    self.volume = volume
  }

  private enum CodingKeys: String, CodingKey {
    case buyout, collateral, price, reward, title, type, volume
    case contractID = "contract_id"
    case dateExpired = "date_expired"
    case dateIssued = "date_issued"
    case daysToComplete = "days_to_complete"
    case endLocationID = "end_location_id"
    case forCorporation = "for_corporation"
    case issuerCorporationID = "issuer_corporation_id"
    case issuerID = "issuer_id"
    case startLocationID = "start_location_id"
  }
}

public struct ESIPublicContractItemDTO: Codable, Equatable, Sendable {
  public let isBlueprintCopy: Bool?
  public let isIncluded: Bool
  public let itemID: Int64?
  public let quantity: Int64
  public let rawQuantity: Int64?
  public let recordID: Int64
  public let typeID: Int64

  public init(
    isBlueprintCopy: Bool? = nil,
    isIncluded: Bool,
    itemID: Int64? = nil,
    quantity: Int64,
    rawQuantity: Int64? = nil,
    recordID: Int64,
    typeID: Int64
  ) {
    self.isBlueprintCopy = isBlueprintCopy
    self.isIncluded = isIncluded
    self.itemID = itemID
    self.quantity = quantity
    self.rawQuantity = rawQuantity
    self.recordID = recordID
    self.typeID = typeID
  }

  private enum CodingKeys: String, CodingKey {
    case quantity
    case isBlueprintCopy = "is_blueprint_copy"
    case isIncluded = "is_included"
    case itemID = "item_id"
    case rawQuantity = "raw_quantity"
    case recordID = "record_id"
    case typeID = "type_id"
  }
}

public struct PublicContractItemTypeMetadata: Equatable, Sendable {
  public let typeID: Int64
  public let typeName: String
  public let groupID: Int64
  public let groupName: String
  public let categoryID: Int64
  public let categoryName: String

  public init(
    typeID: Int64,
    typeName: String,
    groupID: Int64,
    groupName: String,
    categoryID: Int64,
    categoryName: String
  ) {
    self.typeID = typeID
    self.typeName = typeName
    self.groupID = groupID
    self.groupName = groupName
    self.categoryID = categoryID
    self.categoryName = categoryName
  }
}

public enum PublicContractItemDirection: String, CaseIterable, Codable,
  Hashable, Sendable
{
  case included
  case requested
  case both
}

public struct PublicContractSearchFilter: Equatable, Sendable {
  public var itemQuery: String
  public var groupID: Int64?
  public var categoryID: Int64?
  public var direction: PublicContractItemDirection
  public var limit: Int

  public init(
    itemQuery: String = "",
    groupID: Int64? = nil,
    categoryID: Int64? = nil,
    direction: PublicContractItemDirection = .included,
    limit: Int = 300
  ) {
    self.itemQuery = itemQuery
    self.groupID = groupID
    self.categoryID = categoryID
    self.direction = direction
    self.limit = min(1_000, max(1, limit))
  }
}

public struct PublicContractFacet: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let name: String
  public let parentID: Int64?
  public let resultCount: Int

  public init(
    id: Int64,
    name: String,
    parentID: Int64? = nil,
    resultCount: Int
  ) {
    self.id = id
    self.name = name
    self.parentID = parentID
    self.resultCount = resultCount
  }
}

public struct PublicContractSearchResult: Identifiable, Equatable, Sendable {
  public var id: String { "\(contractID):\(recordID)" }
  public let contractID: Int64
  public let recordID: Int64
  public let regionID: Int64
  public let regionName: String
  public let contractType: String
  public let forCorporation: Bool?
  public let title: String?
  public let price: Double?
  public let buyout: Double?
  public let reward: Double?
  public let collateral: Double?
  public let dateIssued: Date
  public let dateExpired: Date
  public let startLocationID: Int64?
  public let startLocationName: String?
  public let endLocationID: Int64?
  public let endLocationName: String?
  public let typeID: Int64
  public let typeName: String?
  public let groupID: Int64?
  public let groupName: String?
  public let categoryID: Int64?
  public let categoryName: String?
  public let isIncluded: Bool
  public let quantity: Int64
  public let isBlueprintCopy: Bool?
}

public enum PublicContractSyncPhase: String, Equatable, Sendable {
  case idle
  case loadingRegions
  case loadingContracts
  case loadingItems
  case completed
  case partial
  case cancelled
  case throttled
  case failed
}

public struct PublicContractSyncProgress: Equatable, Sendable {
  public let phase: PublicContractSyncPhase
  public let regionCount: Int
  /// Regions that have completed at least one successful import. A later
  /// refresh failure does not erase this first-import progress.
  public let completedRegions: Int
  public let freshRegions: Int
  public let remainingInitialRegions: Int
  public let activeRegionName: String?
  public let activeContractID: Int64?
  public let activeContracts: Int
  public let indexedContracts: Int
  public let pendingItemContracts: Int
  public let indexedItems: Int
  public let failedRegions: Int
  public let regionErrorMessage: String?
  public let failedRegionRetryAt: Date?
  public let failedItemContracts: Int
  public let lastCompletedAt: Date?
  public let nextRequestAt: Date?
  public let message: String?

  /// True only when an empty local search can honestly mean that no matching
  /// public offer is known in any ESI region. A partial, stale, failed or
  /// still-indexing store must remain unresolved to industry consumers.
  public var hasCompleteSearchCoverage: Bool {
    regionCount > 0
      && completedRegions == regionCount
      && freshRegions == regionCount
      && remainingInitialRegions == 0
      && pendingItemContracts == 0
      && failedRegions == 0
      && failedItemContracts == 0
  }

  public init(
    phase: PublicContractSyncPhase = .idle,
    regionCount: Int = 0,
    completedRegions: Int = 0,
    freshRegions: Int = 0,
    remainingInitialRegions: Int = 0,
    activeRegionName: String? = nil,
    activeContractID: Int64? = nil,
    activeContracts: Int = 0,
    indexedContracts: Int = 0,
    pendingItemContracts: Int = 0,
    indexedItems: Int = 0,
    failedRegions: Int = 0,
    regionErrorMessage: String? = nil,
    failedRegionRetryAt: Date? = nil,
    failedItemContracts: Int = 0,
    lastCompletedAt: Date? = nil,
    nextRequestAt: Date? = nil,
    message: String? = nil
  ) {
    self.phase = phase
    self.regionCount = regionCount
    self.completedRegions = completedRegions
    self.freshRegions = freshRegions
    self.remainingInitialRegions = remainingInitialRegions
    self.activeRegionName = activeRegionName
    self.activeContractID = activeContractID
    self.activeContracts = activeContracts
    self.indexedContracts = indexedContracts
    self.pendingItemContracts = pendingItemContracts
    self.indexedItems = indexedItems
    self.failedRegions = failedRegions
    self.regionErrorMessage = regionErrorMessage
    self.failedRegionRetryAt = failedRegionRetryAt
    self.failedItemContracts = failedItemContracts
    self.lastCompletedAt = lastCompletedAt
    self.nextRequestAt = nextRequestAt
    self.message = message
  }
}

public struct PublicContractAutomationState: Equatable, Sendable {
  public let isEnabled: Bool
  public let safetyNotBefore: Date?
  public let nextAutomaticRunAt: Date?

  public init(
    isEnabled: Bool,
    safetyNotBefore: Date? = nil,
    nextAutomaticRunAt: Date? = nil
  ) {
    self.isEnabled = isEnabled
    self.safetyNotBefore = safetyNotBefore
    self.nextAutomaticRunAt = nextAutomaticRunAt
  }
}

public enum PublicContractAutomationPolicy {
  public static let regularRefreshInterval: TimeInterval = 6 * 60 * 60
  public static let startupDelay: TimeInterval = 15

  /// Automatic imports respect a persisted safety window. An explicit user
  /// refresh may start immediately; ESI transport limits still apply.
  public static func shouldDeferStart(
    manualStart: Bool,
    safetyNotBefore: Date?,
    now: Date
  ) -> Bool {
    !manualStart && safetyNotBefore.map { $0 > now } == true
  }

  public static func safetyNotBefore(
    after progress: PublicContractSyncProgress,
    now: Date
  ) -> Date? {
    switch progress.phase {
    case .throttled:
      return max(
        progress.nextRequestAt ?? now.addingTimeInterval(15 * 60),
        now
      )
    case .partial:
      if let nextRequestAt = progress.nextRequestAt {
        return max(nextRequestAt, now)
      }
      return progress.pendingItemContracts > 0
        ? now.addingTimeInterval(15 * 60) : nil
    case .failed:
      return now.addingTimeInterval(30 * 60)
    default:
      return nil
    }
  }
}
