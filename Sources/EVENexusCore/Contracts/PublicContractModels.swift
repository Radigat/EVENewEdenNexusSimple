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
  public let materialEfficiency: Int?
  public let quantity: Int64
  public let rawQuantity: Int64?
  public let recordID: Int64
  public let runs: Int?
  public let timeEfficiency: Int?
  public let typeID: Int64

  public init(
    isBlueprintCopy: Bool? = nil,
    isIncluded: Bool,
    itemID: Int64? = nil,
    materialEfficiency: Int? = nil,
    quantity: Int64,
    rawQuantity: Int64? = nil,
    recordID: Int64,
    runs: Int? = nil,
    timeEfficiency: Int? = nil,
    typeID: Int64
  ) {
    self.isBlueprintCopy = isBlueprintCopy
    self.isIncluded = isIncluded
    self.itemID = itemID
    self.materialEfficiency = materialEfficiency
    self.quantity = quantity
    self.rawQuantity = rawQuantity
    self.recordID = recordID
    self.runs = runs
    self.timeEfficiency = timeEfficiency
    self.typeID = typeID
  }

  private enum CodingKeys: String, CodingKey {
    case quantity
    case isBlueprintCopy = "is_blueprint_copy"
    case isIncluded = "is_included"
    case itemID = "item_id"
    case materialEfficiency = "material_efficiency"
    case rawQuantity = "raw_quantity"
    case recordID = "record_id"
    case runs
    case timeEfficiency = "time_efficiency"
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
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let runs: Int?
  public let offeredLineCount: Int
  public let requestedLineCount: Int

  public init(
    contractID: Int64,
    recordID: Int64,
    regionID: Int64,
    regionName: String,
    contractType: String,
    forCorporation: Bool? = nil,
    title: String? = nil,
    price: Double? = nil,
    buyout: Double? = nil,
    reward: Double? = nil,
    collateral: Double? = nil,
    dateIssued: Date,
    dateExpired: Date,
    startLocationID: Int64? = nil,
    startLocationName: String? = nil,
    endLocationID: Int64? = nil,
    endLocationName: String? = nil,
    typeID: Int64,
    typeName: String? = nil,
    groupID: Int64? = nil,
    groupName: String? = nil,
    categoryID: Int64? = nil,
    categoryName: String? = nil,
    isIncluded: Bool,
    quantity: Int64,
    isBlueprintCopy: Bool? = nil,
    materialEfficiency: Int? = nil,
    timeEfficiency: Int? = nil,
    runs: Int? = nil,
    offeredLineCount: Int,
    requestedLineCount: Int
  ) {
    self.contractID = contractID
    self.recordID = recordID
    self.regionID = regionID
    self.regionName = regionName
    self.contractType = contractType
    self.forCorporation = forCorporation
    self.title = title
    self.price = price
    self.buyout = buyout
    self.reward = reward
    self.collateral = collateral
    self.dateIssued = dateIssued
    self.dateExpired = dateExpired
    self.startLocationID = startLocationID
    self.startLocationName = startLocationName
    self.endLocationID = endLocationID
    self.endLocationName = endLocationName
    self.typeID = typeID
    self.typeName = typeName
    self.groupID = groupID
    self.groupName = groupName
    self.categoryID = categoryID
    self.categoryName = categoryName
    self.isIncluded = isIncluded
    self.quantity = quantity
    self.isBlueprintCopy = isBlueprintCopy
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.runs = runs
    self.offeredLineCount = offeredLineCount
    self.requestedLineCount = requestedLineCount
  }

  public var effectiveContractPrice: Double? {
    let value = price ?? buyout
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  public var isAttributableBlueprintOffer: Bool {
    guard contractType == "item_exchange",
      isIncluded,
      quantity == 1,
      offeredLineCount == 1,
      requestedLineCount == 0,
      effectiveContractPrice != nil
    else { return false }
    if runs == -1 { return true }
    return isBlueprintCopy == true
      && (runs ?? 0) > 0
      && materialEfficiency != nil
      && timeEfficiency != nil
  }

  public var isComparableSingleTypeItemExchangeOffer: Bool {
    contractType == "item_exchange"
      && isIncluded
      && quantity > 0
      && offeredLineCount == 1
      && requestedLineCount == 0
      && effectiveContractPrice != nil
  }
}

public enum PublicContractReferenceRule {
  public static let ruleVersion = "public-item-exchange-reference-2026-08-13"
}

public struct PublicContractReferencePrice: Codable, Equatable, Sendable {
  public let typeID: Int64
  public let contractID: Int64
  public let contractQuantity: Int64
  public let totalContractPrice: Double
  public let unitPrice: Double
  public let startLocationID: Int64?
  public let startLocationName: String?
  public let dateIssued: Date
  public let dateExpired: Date

  public init?(_ offer: PublicContractSearchResult) {
    guard offer.isComparableSingleTypeItemExchangeOffer,
      let totalContractPrice = offer.effectiveContractPrice
    else { return nil }
    let unitPrice = totalContractPrice / Double(offer.quantity)
    guard unitPrice.isFinite, unitPrice > 0 else { return nil }
    typeID = offer.typeID
    contractID = offer.contractID
    contractQuantity = offer.quantity
    self.totalContractPrice = totalContractPrice
    self.unitPrice = unitPrice
    startLocationID = offer.startLocationID
    startLocationName = offer.startLocationName
    dateIssued = offer.dateIssued
    dateExpired = offer.dateExpired
  }
}

public struct PublicContractReferenceSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let capturedAt: Date
  public let locationID: Int64
  public let locationName: String
  public let prices: [Int64: PublicContractReferencePrice]
  public let hasCompleteSearchCoverage: Bool
  public let source: SourceIdentity

  /// `nil` means every imported EVE region. A non-empty set is reserved for
  /// the user-configurable comparison scope without changing quote semantics.
  public let allowedRegionIDs: Set<Int64>?

  public init(
    id: UUID = UUID(),
    capturedAt: Date,
    locationID: Int64,
    locationName: String,
    prices: [Int64: PublicContractReferencePrice],
    hasCompleteSearchCoverage: Bool,
    source: SourceIdentity,
    allowedRegionIDs: Set<Int64>? = nil
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.locationID = locationID
    self.locationName = locationName
    self.prices = prices
    self.hasCompleteSearchCoverage = hasCompleteSearchCoverage
    self.source = source
    self.allowedRegionIDs = allowedRegionIDs
  }

  public static func project(
    locationID: Int64,
    locationName: String,
    offers: [Int64: [PublicContractSearchResult]],
    progress: PublicContractSyncProgress,
    limitPerType: Int,
    capturedAt: Date = .now
  ) -> PublicContractReferenceSnapshot {
    var prices: [Int64: PublicContractReferencePrice] = [:]
    for (typeID, candidates) in offers {
      prices[typeID] = candidates.compactMap(PublicContractReferencePrice.init)
        .filter { $0.startLocationID == locationID }
        .min {
          if $0.unitPrice != $1.unitPrice {
            return $0.unitPrice < $1.unitPrice
          }
          if $0.dateExpired != $1.dateExpired {
            return $0.dateExpired < $1.dateExpired
          }
          return $0.contractID < $1.contractID
        }
    }
    let boundedLimit = min(500, max(1, limitPerType))
    let truncated = offers.values.contains { $0.count >= boundedLimit }
    let source = SourceIdentity(
      provider: "ESI Public Contracts",
      version: PublicContractReferenceRule.ruleVersion,
      capturedAt: progress.lastCompletedAt ?? capturedAt
    )
    return PublicContractReferenceSnapshot(
      id: source.snapshotID,
      capturedAt: source.capturedAt,
      locationID: locationID,
      locationName: locationName,
      prices: prices,
      hasCompleteSearchCoverage:
        progress.hasCompleteSearchCoverage && !truncated,
      source: source
    )
  }

  public static func projectUniverseWide(
    offers: [Int64: [PublicContractSearchResult]],
    progress: PublicContractSyncProgress,
    limitPerType: Int,
    allowedRegionIDs: Set<Int64>? = nil,
    capturedAt: Date = .now
  ) -> PublicContractReferenceSnapshot {
    let acceptedRegionIDs = allowedRegionIDs.flatMap { $0.isEmpty ? nil : $0 }
    var prices: [Int64: PublicContractReferencePrice] = [:]
    for (typeID, candidates) in offers {
      prices[typeID] =
        candidates
        .filter { offer in
          acceptedRegionIDs?.contains(offer.regionID) ?? true
        }
        .compactMap(PublicContractReferencePrice.init)
        .min {
          if $0.unitPrice != $1.unitPrice {
            return $0.unitPrice < $1.unitPrice
          }
          if $0.dateExpired != $1.dateExpired {
            return $0.dateExpired < $1.dateExpired
          }
          return $0.contractID < $1.contractID
        }
    }
    let source = SourceIdentity(
      provider: "ESI Public Contracts",
      version: PublicContractReferenceRule.ruleVersion,
      capturedAt: progress.lastCompletedAt ?? capturedAt
    )
    let boundedLimit = min(500, max(1, limitPerType))
    let truncated = offers.values.contains { $0.count >= boundedLimit }
    return PublicContractReferenceSnapshot(
      id: source.snapshotID,
      capturedAt: source.capturedAt,
      locationID: 0,
      locationName: acceptedRegionIDs == nil
        ? "Entire universe" : "Selected regions",
      prices: prices,
      hasCompleteSearchCoverage:
        progress.hasCompleteSearchCoverage && !truncated,
      source: source,
      allowedRegionIDs: acceptedRegionIDs
    )
  }
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


/// One EVE region from the ESI region list of the Public Contracts index.
public struct PublicContractRegion: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let name: String

  public init(id: Int64, name: String) {
    self.id = id
    self.name = name
  }
}

/// Why a region is worth importing. The raw value is the display rank:
/// configured hub roles first, then production sites and the major NPC
/// trade hubs.
public enum PublicContractRegionRole: Int, CaseIterable, Comparable, Sendable {
  case mainHub
  case homeHub
  case coalitionHub
  case comparisonMarket
  case productionSite
  case tradeHub

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A selectable region with the hints shown behind its name.
public struct PublicContractRegionOption: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let name: String
  /// Sorted by display rank, without duplicates.
  public let roles: [PublicContractRegionRole]
  /// Built-in trade hubs located in this region, in their declared order.
  public let tradeHubs: [MarketTradeHub]

  public init(
    id: Int64,
    name: String,
    roles: [PublicContractRegionRole] = [],
    tradeHubs: [MarketTradeHub] = []
  ) {
    self.id = id
    self.name = name
    self.roles = roles
    self.tradeHubs = tradeHubs
  }

  public var isRecommended: Bool { !roles.isEmpty }
}

public enum PublicContractRegionCatalog {
  /// Annotates every known region with configured hub roles, production
  /// sites and built-in trade hubs. Recommended regions come first (by their
  /// highest-ranked role, then name); all other regions follow by name. The
  /// region ID is the final tie-breaker. `systemRegions` resolves locations
  /// that only know their solar system, such as player structures.
  public static func options(
    regions: [PublicContractRegion],
    basis: ProductionBasis,
    systemRegions: [Int64: Int64] = [:]
  ) -> [PublicContractRegionOption] {
    let roles = roleAssignments(basis: basis, systemRegions: systemRegions)
    let options = regions.map { region in
      PublicContractRegionOption(
        id: region.id,
        name: region.name,
        roles: (roles[region.id] ?? []).sorted(),
        tradeHubs: MarketTradeHub.allCases.filter { $0.regionID == region.id }
      )
    }
    return options.sorted { lhs, rhs in
      switch (lhs.roles.first, rhs.roles.first) {
      case let (left?, right?) where left != right:
        return left < right
      case (.some, nil):
        return true
      case (nil, .some):
        return false
      default:
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id < rhs.id
      }
    }
  }

  /// Region IDs of every configured hub role and production site. Used as
  /// the suggested starting selection when the user leaves the universe.
  public static func suggestedRegionIDs(
    basis: ProductionBasis,
    systemRegions: [Int64: Int64] = [:]
  ) -> Set<Int64> {
    Set(
      roleAssignments(basis: basis, systemRegions: systemRegions)
        .filter { !$0.value.subtracting([.tradeHub]).isEmpty }
        .keys
    )
  }

  /// Solar systems of hub locations whose region is not stored; the caller
  /// resolves them and passes the result as `systemRegions`.
  public static func unresolvedSolarSystemIDs(
    basis: ProductionBasis
  ) -> Set<Int64> {
    let locations =
      [
        basis.mainTradingLocation, basis.homeTradingLocation,
        basis.coalitionTradingLocation,
      ].compactMap { $0?.location }
      + basis.tradingLocations
      .filter { basis.comparisonTradingLocationIDs.contains($0.id) }
      .map(\.location)
    return Set(
      locations
        .filter { regionID(of: $0, systemRegions: [:]) == nil }
        .compactMap(\.solarSystemID)
        .filter { $0 > 0 }
    )
  }

  static func roleAssignments(
    basis: ProductionBasis,
    systemRegions: [Int64: Int64] = [:]
  ) -> [Int64: Set<PublicContractRegionRole>] {
    var roles: [Int64: Set<PublicContractRegionRole>] = [:]
    func regionID(of location: ProcurementLocation?) -> Int64? {
      Self.regionID(of: location, systemRegions: systemRegions)
    }
    func assign(_ role: PublicContractRegionRole, _ regionID: Int64?) {
      guard let regionID, regionID > 0 else { return }
      roles[regionID, default: []].insert(role)
    }
    assign(.mainHub, regionID(of: basis.mainTradingLocation?.location))
    assign(.homeHub, regionID(of: basis.homeTradingLocation?.location))
    assign(
      .coalitionHub,
      regionID(of: basis.coalitionTradingLocation?.location)
    )
    for market in basis.tradingLocations
    where basis.comparisonTradingLocationIDs.contains(market.id) {
      assign(.comparisonMarket, regionID(of: market.location))
    }
    for system in basis.configuredActivitySystems {
      assign(.productionSite, system.regionID)
    }
    for hub in MarketTradeHub.allCases {
      assign(.tradeHub, hub.regionID)
    }
    return roles
  }

  private static func regionID(
    of location: ProcurementLocation?,
    systemRegions: [Int64: Int64]
  ) -> Int64? {
    guard let location else { return nil }
    if let regionID = location.regionID { return regionID }
    if let regionID = location.locationID
      .flatMap(MarketTradeHub.matching(stationID:))?
      .regionID
    {
      return regionID
    }
    return location.solarSystemID.flatMap { systemRegions[$0] }
  }
}
