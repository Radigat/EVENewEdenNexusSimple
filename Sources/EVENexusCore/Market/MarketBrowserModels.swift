import Foundation

public enum MarketSecurityBand: String, Codable, CaseIterable, Sendable {
  case highSecurity
  case lowSecurity
  case nullSecurity
  case unknown

  public static func resolved(
    securityStatus: Double?
  ) -> MarketSecurityBand {
    guard let securityStatus, securityStatus.isFinite else { return .unknown }
    if securityStatus >= 0.45 { return .highSecurity }
    if securityStatus > 0 { return .lowSecurity }
    return .nullSecurity
  }

  public static func eveDisplayStatus(
    _ securityStatus: Double?
  ) -> Double? {
    guard let securityStatus, securityStatus.isFinite else { return nil }
    if securityStatus > 0, securityStatus < 0.05 { return 0.1 }
    return (securityStatus * 10).rounded() / 10
  }
}

public struct MarketBrowserOrder: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let regionID: Int64
  public let regionName: String
  public let locationID: Int64
  public let locationName: String?
  public let systemID: Int64
  public let systemName: String?
  public let securityStatus: Double?
  public let side: MarketOrderSide
  public let price: Double
  public let volumeRemaining: Int64
  public let volumeTotal: Int64
  public let minimumVolume: Int64
  public let range: String
  public let issuedAt: Date
  public let expiresAt: Date
  public let esiLastModifiedAt: Date?
  public let observedAt: Date

  public var isPlayerStructure: Bool {
    locationID >= 1_000_000_000_000
  }

  public var securityBand: MarketSecurityBand {
    MarketSecurityBand.resolved(securityStatus: securityStatus)
  }

  public var eveDisplaySecurityStatus: Double? {
    MarketSecurityBand.eveDisplayStatus(securityStatus)
  }

  public init(
    id: Int64,
    typeID: Int64,
    regionID: Int64,
    regionName: String,
    locationID: Int64,
    locationName: String?,
    systemID: Int64,
    systemName: String?,
    securityStatus: Double? = nil,
    side: MarketOrderSide,
    price: Double,
    volumeRemaining: Int64,
    volumeTotal: Int64,
    minimumVolume: Int64,
    range: String,
    issuedAt: Date,
    expiresAt: Date,
    esiLastModifiedAt: Date?,
    observedAt: Date
  ) {
    self.id = id
    self.typeID = typeID
    self.regionID = regionID
    self.regionName = regionName
    self.locationID = locationID
    self.locationName = locationName
    self.systemID = systemID
    self.systemName = systemName
    self.securityStatus = securityStatus
    self.side = side
    self.price = price
    self.volumeRemaining = volumeRemaining
    self.volumeTotal = volumeTotal
    self.minimumVolume = minimumVolume
    self.range = range
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.esiLastModifiedAt = esiLastModifiedAt
    self.observedAt = observedAt
  }

  fileprivate func resolvingStructureName(
    _ structureNames: [Int64: String]
  ) -> MarketBrowserOrder {
    guard isPlayerStructure, let name = structureNames[locationID] else {
      return self
    }
    return MarketBrowserOrder(
      id: id,
      typeID: typeID,
      regionID: regionID,
      regionName: regionName,
      locationID: locationID,
      locationName: name,
      systemID: systemID,
      systemName: systemName,
      securityStatus: securityStatus,
      side: side,
      price: price,
      volumeRemaining: volumeRemaining,
      volumeTotal: volumeTotal,
      minimumVolume: minimumVolume,
      range: range,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      esiLastModifiedAt: esiLastModifiedAt,
      observedAt: observedAt
    )
  }
}

public struct MarketBrowserRegionFailure: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { regionID }
  public let regionID: Int64
  public let regionName: String
  public let diagnostic: String

  public init(regionID: Int64, regionName: String, diagnostic: String) {
    self.regionID = regionID
    self.regionName = regionName
    self.diagnostic = diagnostic
  }
}

public struct MarketBrowserSummary: Codable, Equatable, Sendable {
  public let bestSellPrice: Double?
  public let bestBuyPrice: Double?
  public let weightedAverageSellPrice: Double?
  public let averageSellFivePercent: Double?
  public let averageBuyFivePercent: Double?
  public let averageMargin: Double?
  public let averageMarginPercent: Double?
  public let activeSellVolume: Int64
  public let activeBuyVolume: Int64
  public let sellOrderCount: Int
  public let buyOrderCount: Int
  public let representedRegionCount: Int

  public var spread: Double? {
    guard let bestSellPrice, let bestBuyPrice else { return nil }
    return bestSellPrice - bestBuyPrice
  }

  public static func calculate(
    orders: [MarketBrowserOrder]
  ) -> MarketBrowserSummary {
    let valid = orders.filter {
      $0.price.isFinite && $0.price > 0 && $0.volumeRemaining > 0
    }
    let allSells = valid.filter { $0.side == .sell }
    let allBuys = valid.filter { $0.side == .buy }
    let bestSellPrice = allSells.map(\.price).min()
    let bestBuyPrice = allBuys.map(\.price).max()
    let sells = allSells.filter {
      guard let bestSellPrice else { return false }
      let threshold = bestSellPrice * 10
      return $0.price <= (threshold.isFinite ? threshold : .greatestFiniteMagnitude)
    }
    let buys = allBuys.filter {
      guard let bestBuyPrice else { return false }
      return $0.price >= bestBuyPrice * 0.1
    }
    let sellVolume = sells.reduce(Int64(0)) {
      $0.addingReportingOverflow($1.volumeRemaining).overflow
        ? Int64.max : $0 + $1.volumeRemaining
    }
    let buyVolume = buys.reduce(Int64(0)) {
      $0.addingReportingOverflow($1.volumeRemaining).overflow
        ? Int64.max : $0 + $1.volumeRemaining
    }
    let weightedTotal = sells.reduce(0.0) {
      $0 + ($1.price * Double($1.volumeRemaining))
    }
    let averageSellFivePercent = fivePercentAverage(
      orders: sells,
      bestPriceFirst: { $0.price < $1.price }
    )
    let averageBuyFivePercent = fivePercentAverage(
      orders: buys,
      bestPriceFirst: { $0.price > $1.price }
    )
    let averageMargin = averageSellFivePercent.flatMap { sell in
      averageBuyFivePercent.map { sell - $0 }
    }
    let averageMarginPercent: Double?
    if let averageMargin,
      let averageBuyFivePercent,
      averageBuyFivePercent > 0
    {
      averageMarginPercent = averageMargin / averageBuyFivePercent * 100
    } else {
      averageMarginPercent = nil
    }
    return MarketBrowserSummary(
      bestSellPrice: bestSellPrice,
      bestBuyPrice: bestBuyPrice,
      weightedAverageSellPrice:
        sellVolume > 0 && weightedTotal.isFinite
        ? weightedTotal / Double(sellVolume) : nil,
      averageSellFivePercent: averageSellFivePercent,
      averageBuyFivePercent: averageBuyFivePercent,
      averageMargin: averageMargin,
      averageMarginPercent: averageMarginPercent,
      activeSellVolume: sellVolume,
      activeBuyVolume: buyVolume,
      sellOrderCount: sells.count,
      buyOrderCount: buys.count,
      representedRegionCount: Set(valid.map(\.regionID)).count
    )
  }

  private static func fivePercentAverage(
    orders: [MarketBrowserOrder],
    bestPriceFirst: (MarketBrowserOrder, MarketBrowserOrder) -> Bool
  ) -> Double? {
    let totalVolume = orders.reduce(Int64(0)) {
      $0.addingReportingOverflow($1.volumeRemaining).overflow
        ? Int64.max : $0 + $1.volumeRemaining
    }
    guard totalVolume > 0 else { return nil }
    let targetVolume = max(
      1,
      totalVolume / 20 + (totalVolume % 20 == 0 ? 0 : 1)
    )
    var remaining = targetVolume
    var weightedTotal = 0.0
    for order in orders.sorted(by: bestPriceFirst) where remaining > 0 {
      let acceptedVolume = min(remaining, order.volumeRemaining)
      weightedTotal += order.price * Double(acceptedVolume)
      remaining -= acceptedVolume
    }
    guard remaining == 0, weightedTotal.isFinite else { return nil }
    return weightedTotal / Double(targetVolume)
  }
}

public struct MarketBrowserSnapshot: Codable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let itemName: String
  public let capturedAt: Date
  public let regionCount: Int
  public let loadedRegionCount: Int
  public let orders: [MarketBrowserOrder]
  public let regionFailures: [MarketBrowserRegionFailure]
  public let summary: MarketBrowserSummary
  public let source: SourceIdentity

  public init(
    id: UUID = UUID(),
    typeID: Int64,
    itemName: String,
    capturedAt: Date,
    regionCount: Int,
    loadedRegionCount: Int,
    orders: [MarketBrowserOrder],
    regionFailures: [MarketBrowserRegionFailure],
    source: SourceIdentity
  ) {
    self.id = id
    self.typeID = typeID
    self.itemName = itemName
    self.capturedAt = capturedAt
    self.regionCount = regionCount
    self.loadedRegionCount = loadedRegionCount
    self.orders = orders
    self.regionFailures = regionFailures
    summary = MarketBrowserSummary.calculate(orders: orders)
    self.source = source
  }

  public func resolvingStructureNames(
    _ structureNames: [Int64: String]
  ) -> MarketBrowserSnapshot {
    MarketBrowserSnapshot(
      id: id,
      typeID: typeID,
      itemName: itemName,
      capturedAt: capturedAt,
      regionCount: regionCount,
      loadedRegionCount: loadedRegionCount,
      orders: orders.map {
        $0.resolvingStructureName(structureNames)
      },
      regionFailures: regionFailures,
      source: source
    )
  }
}

public struct MarketBrowserFilter: Equatable, Sendable {
  public var regionQuery = ""
  public var locationQuery = ""
  public var minimumPrice: Double?
  public var maximumPrice: Double?
  public var minimumQuantity: Int64?
  public var includesNPCStations = true
  public var includesPlayerStructures = true
  public var includesHighSecurity = true
  public var includesLowSecurity = true
  public var includesNullSecurity = true
  public var includesUnknownSecurity = true
  public var marketHubsOnly = false

  public init() {}

  public func accepts(_ order: MarketBrowserOrder) -> Bool {
    if !regionQuery.isEmpty,
      !order.regionName.localizedCaseInsensitiveContains(regionQuery)
    {
      return false
    }
    if !locationQuery.isEmpty {
      if order.locationName?.localizedCaseInsensitiveContains(locationQuery)
        != true
        && order.systemName?.localizedCaseInsensitiveContains(locationQuery)
          != true
      {
        return false
      }
    }
    if let minimumPrice, order.price < minimumPrice { return false }
    if let maximumPrice, order.price > maximumPrice { return false }
    if let minimumQuantity, order.volumeRemaining < minimumQuantity {
      return false
    }
    if order.isPlayerStructure {
      if !includesPlayerStructures { return false }
    } else if !includesNPCStations {
      return false
    }
    switch order.securityBand {
    case .highSecurity where !includesHighSecurity: return false
    case .lowSecurity where !includesLowSecurity: return false
    case .nullSecurity where !includesNullSecurity: return false
    case .unknown where !includesUnknownSecurity: return false
    default: break
    }
    if marketHubsOnly,
      !MarketTradeHub.allCases.contains(where: {
        $0.stationID == order.locationID
      })
    {
      return false
    }
    return true
  }
}

public struct ManufacturingOpportunityScanProgress: Equatable, Sendable {
  public let completedPages: Int
  public let totalPages: Int

  public init(completedPages: Int = 0, totalPages: Int = 0) {
    self.completedPages = completedPages
    self.totalPages = totalPages
  }

  public var fractionCompleted: Double? {
    guard totalPages > 0 else { return nil }
    return min(1, max(0, Double(completedPages) / Double(totalPages)))
  }
}

public struct ManufacturingOpportunitySettings: Codable, Equatable, Sendable {
  public static let maximumRequestedRuns = 1_000_000
  public static let maximumTargetQuantity = Int64(
    ProductionInputParser.maximumWantedQuantity
  )

  public var targetQuantity: Int64
  /// Legacy explicit Blueprint runs retained only so older snapshots remain
  /// readable. Current Main-Hub scenarios use `targetQuantity` and derive the
  /// required runs independently for every product's SDE output per run.
  public var requestedRuns: Int?
  public var materialEfficiency: Int
  public var timeEfficiency: Int

  public init(
    targetQuantity: Int64 = 1,
    requestedRuns: Int? = nil,
    materialEfficiency: Int = 10,
    timeEfficiency: Int = 20
  ) {
    self.targetQuantity = min(
      Self.maximumTargetQuantity,
      max(1, targetQuantity)
    )
    self.requestedRuns = requestedRuns.map {
      min(Self.maximumRequestedRuns, max(1, $0))
    }
    self.materialEfficiency = min(10, max(0, materialEfficiency))
    self.timeEfficiency = min(20, max(0, timeEfficiency))
  }

  public func resolvedRuns(outputPerRun: Int64) -> Int {
    if let requestedRuns { return requestedRuns }
    let target = min(targetQuantity, Int64(Int.max))
    return IndustryPlanner.runsRequired(
      wantedQuantity: Int(target),
      outputPerRun: outputPerRun
    )
  }

  /// Main-Hub screening compares recipes before a concrete owned or acquired
  /// Blueprint is selected. Research levels therefore belong to the later
  /// production decision and must not be silently assumed by the opportunity
  /// scan.
  public var mainHubOpportunityBaseline: Self {
    Self(
      targetQuantity: targetQuantity,
      requestedRuns: nil,
      materialEfficiency: 0,
      timeEfficiency: 0
    )
  }
}

public enum ManufacturingOpportunityProductFamily: String, Codable,
  CaseIterable, Identifiable, Sendable
{
  case ships
  case modules
  case charges
  case drones
  case rigs
  case structures
  case reactions
  case boosters
  case implants
  case components
  case deployables
  case other

  public var id: Self { self }

  public static func classify(
    categoryName: String,
    groupName: String
  ) -> Self {
    let category = categoryName.lowercased()
    let group = groupName.lowercased()
    if category.contains("ship") { return .ships }
    if category.contains("charge") { return .charges }
    if category.contains("drone") { return .drones }
    if category.contains("structure") || group.contains("structure") {
      return .structures
    }
    if category.contains("deployable") { return .deployables }
    if category.contains("implant") { return .implants }
    if group.contains("booster") { return .boosters }
    if group.contains("reaction") { return .reactions }
    if group.contains("rig") { return .rigs }
    if group.contains("component") || category.contains("material") {
      return .components
    }
    if category.contains("module") { return .modules }
    return .other
  }
}

public enum ManufacturingOpportunityProductionClass: String, Codable,
  CaseIterable, Identifiable, Sendable
{
  case techI
  case techII
  case techIII
  case faction
  case storyline
  case other

  public var id: Self { self }

  public static func classify(
    metaGroupID: Int64?,
    techLevel: Int?
  ) -> Self {
    switch metaGroupID {
    case 1: return .techI
    case 2: return .techII
    case 14: return .techIII
    case 4: return .faction
    case 3: return .storyline
    case .some: return .other
    case nil:
      switch techLevel {
      case 1: return .techI
      case 2: return .techII
      case 3: return .techIII
      default: return .other
      }
    }
  }
}

public struct ManufacturingOpportunityEfficiencyAssumption: Equatable, Sendable {
  public let materialEfficiency: Int
  public let timeEfficiency: Int

  public init(materialEfficiency: Int, timeEfficiency: Int) {
    self.materialEfficiency = min(10, max(0, materialEfficiency))
    self.timeEfficiency = min(20, max(0, timeEfficiency))
  }
}

public enum ManufacturingOpportunityEfficiencyDefaults {
  public static func resolve(
    blueprintTypeID: Int64,
    categoryName: String,
    groupName: String,
    metaGroupID: Int64?,
    techLevel: Int?,
    fallbackMaterialEfficiency: Int,
    fallbackTimeEfficiency: Int,
    loyaltyStoreBlueprintTypeIDs: Set<Int64>
  ) -> ManufacturingOpportunityEfficiencyAssumption {
    if loyaltyStoreBlueprintTypeIDs.contains(blueprintTypeID) {
      return ManufacturingOpportunityEfficiencyAssumption(
        materialEfficiency: 0,
        timeEfficiency: 0
      )
    }
    let productFamily = ManufacturingOpportunityProductFamily.classify(
      categoryName: categoryName,
      groupName: groupName
    )
    let productionClass = ManufacturingOpportunityProductionClass.classify(
      metaGroupID: metaGroupID,
      techLevel: techLevel
    )
    if productFamily == .modules, productionClass == .techI {
      return ManufacturingOpportunityEfficiencyAssumption(
        materialEfficiency: 10,
        timeEfficiency: 20
      )
    }
    if productionClass == .techII {
      return ManufacturingOpportunityEfficiencyAssumption(
        materialEfficiency: 3,
        timeEfficiency: 2
      )
    }
    return ManufacturingOpportunityEfficiencyAssumption(
      materialEfficiency: fallbackMaterialEfficiency,
      timeEfficiency: fallbackTimeEfficiency
    )
  }
}

public enum ManufacturingOpportunityCatalogFilter {
  public static func accepts(
    activityKind: BlueprintActivityDefinition.Kind = .manufacturing,
    categoryName: String,
    groupName: String,
    metaGroupID: Int64?,
    techLevel: Int?,
    productFamilies: Set<ManufacturingOpportunityProductFamily>,
    productionClasses: Set<ManufacturingOpportunityProductionClass>
  ) -> Bool {
    let productFamily: ManufacturingOpportunityProductFamily =
      activityKind == .reaction
      ? .reactions
      : ManufacturingOpportunityProductFamily.classify(
        categoryName: categoryName,
        groupName: groupName
      )
    return productFamilies.contains(productFamily)
      && productionClasses.contains(
        ManufacturingOpportunityProductionClass.classify(
          metaGroupID: metaGroupID,
          techLevel: techLevel
        )
      )
  }
}

public struct ManufacturingOpportunityCostSheet: Codable, Equatable, Sendable {
  public var includesInstallation: Bool
  public var includesSalesTax: Bool
  public var includesBrokerFee: Bool
  public var includesBlueprintAllocation: Bool
  public var blueprintAllocationPerRun: Double?
  public var includesHauling: Bool
  public var haulingCostPerBatch: Double?

  public init(
    includesInstallation: Bool = true,
    includesSalesTax: Bool = true,
    includesBrokerFee: Bool = true,
    includesBlueprintAllocation: Bool = false,
    blueprintAllocationPerRun: Double? = nil,
    includesHauling: Bool = false,
    haulingCostPerBatch: Double? = nil
  ) {
    self.includesInstallation = includesInstallation
    self.includesSalesTax = includesSalesTax
    self.includesBrokerFee = includesBrokerFee
    self.includesBlueprintAllocation = includesBlueprintAllocation
    self.blueprintAllocationPerRun = blueprintAllocationPerRun
    self.includesHauling = includesHauling
    self.haulingCostPerBatch = haulingCostPerBatch
  }
}

public struct ManufacturingOpportunityCostProjection: Equatable, Sendable {
  public let materialCost: Double?
  public let installationCost: Double?
  public let blueprintAllocation: Double?
  public let logisticsCost: Double?
  public let totalCost: Double?
  public let grossRevenue: Double?
  public let salesTax: Double?
  public let brokerFee: Double?
  public let netRevenue: Double?
  public let profit: Double?
  public let returnOnInvestment: Double?
  public let iskPerHour: Double?
  public let iskPerCubicMeter: Double?
}

public enum ManufacturingOpportunitySortColumn: String, CaseIterable,
  Sendable
{
  case task
  case item
  case demand
  case quantity
  case runs
  case duration
  case cost
  case revenue
  case salesTax
  case brokerFee
  case profit
  case dailyProfitPotential
  case roi
  case iskPerHour
  case iskPerCubicMeter
  case materialEfficiency
  case timeEfficiency
  case group
  case category
}

public enum ManufacturingOpportunitySortDirection: String, Sendable {
  case ascending
  case descending

  public var toggled: Self {
    self == .ascending ? .descending : .ascending
  }
}

public struct ManufacturingOpportunitySortDescriptor: Equatable, Sendable {
  public let column: ManufacturingOpportunitySortColumn
  public let direction: ManufacturingOpportunitySortDirection

  public init(
    column: ManufacturingOpportunitySortColumn,
    direction: ManufacturingOpportunitySortDirection
  ) {
    self.column = column
    self.direction = direction
  }

  public func orderedBefore(
    lhs: ManufacturingOpportunityRow,
    lhsCosts: ManufacturingOpportunityCostProjection,
    rhs: ManufacturingOpportunityRow,
    rhsCosts: ManufacturingOpportunityCostProjection
  ) -> Bool {
    switch column {
    case .task:
      return byName(lhs, rhs)
    case .item:
      return compareText(lhs.productName, rhs.productName, lhs, rhs)
    case .demand:
      return compare(lhs.observedDailyDemand, rhs.observedDailyDemand, lhs, rhs)
    case .quantity:
      return compare(lhs.producedQuantity, rhs.producedQuantity, lhs, rhs)
    case .runs:
      return compare(Int64(lhs.runs), Int64(rhs.runs), lhs, rhs)
    case .duration:
      return compare(lhs.durationSeconds, rhs.durationSeconds, lhs, rhs)
    case .cost:
      return compare(lhsCosts.totalCost, rhsCosts.totalCost, lhs, rhs)
    case .revenue:
      return compare(lhsCosts.grossRevenue, rhsCosts.grossRevenue, lhs, rhs)
    case .salesTax:
      return compare(lhsCosts.salesTax, rhsCosts.salesTax, lhs, rhs)
    case .brokerFee:
      return compare(lhsCosts.brokerFee, rhsCosts.brokerFee, lhs, rhs)
    case .profit:
      return compare(lhsCosts.profit, rhsCosts.profit, lhs, rhs)
    case .dailyProfitPotential:
      return compare(
        ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
          for: lhs,
          costs: lhsCosts
        ),
        ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
          for: rhs,
          costs: rhsCosts
        ),
        lhs,
        rhs
      )
    case .roi:
      return compare(
        lhsCosts.returnOnInvestment,
        rhsCosts.returnOnInvestment,
        lhs,
        rhs
      )
    case .iskPerHour:
      return compare(lhsCosts.iskPerHour, rhsCosts.iskPerHour, lhs, rhs)
    case .iskPerCubicMeter:
      return compare(
        lhsCosts.iskPerCubicMeter,
        rhsCosts.iskPerCubicMeter,
        lhs,
        rhs
      )
    case .materialEfficiency:
      return compare(
        lhs.displayedMaterialEfficiency.map(Int64.init),
        rhs.displayedMaterialEfficiency.map(Int64.init),
        lhs,
        rhs
      )
    case .timeEfficiency:
      return compare(
        lhs.displayedTimeEfficiency.map(Int64.init),
        rhs.displayedTimeEfficiency.map(Int64.init),
        lhs,
        rhs
      )
    case .group:
      return compareText(lhs.groupName, rhs.groupName, lhs, rhs)
    case .category:
      return compareText(lhs.categoryName, rhs.categoryName, lhs, rhs)
    }
  }

  private func compare(
    _ lhsValue: Double?,
    _ rhsValue: Double?,
    _ lhs: ManufacturingOpportunityRow,
    _ rhs: ManufacturingOpportunityRow
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case (let left?, let right?) where left != right:
      return direction == .ascending ? left < right : left > right
    case (_?, nil): return direction == .ascending
    case (nil, _?): return direction == .descending
    default: return byName(lhs, rhs)
    }
  }

  private func compare(
    _ lhsValue: Int64?,
    _ rhsValue: Int64?,
    _ lhs: ManufacturingOpportunityRow,
    _ rhs: ManufacturingOpportunityRow
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case (let left?, let right?) where left != right:
      return direction == .ascending ? left < right : left > right
    case (_?, nil): return direction == .ascending
    case (nil, _?): return direction == .descending
    default: return byName(lhs, rhs)
    }
  }

  private func compareText(
    _ lhsValue: String,
    _ rhsValue: String,
    _ lhs: ManufacturingOpportunityRow,
    _ rhs: ManufacturingOpportunityRow
  ) -> Bool {
    let comparison = lhsValue.localizedCaseInsensitiveCompare(rhsValue)
    guard comparison != .orderedSame else { return byName(lhs, rhs) }
    return direction == .ascending
      ? comparison == .orderedAscending
      : comparison == .orderedDescending
  }

  private func byName(
    _ lhs: ManufacturingOpportunityRow,
    _ rhs: ManufacturingOpportunityRow
  ) -> Bool {
    let comparison = lhs.productName.localizedCaseInsensitiveCompare(
      rhs.productName
    )
    if comparison != .orderedSame {
      return comparison == .orderedAscending
    }
    return lhs.productTypeID < rhs.productTypeID
  }
}

public struct ManufacturingOpportunityLogisticsProjection: Equatable, Sendable {
  public let cost: Double?
  public let legs: [LogisticsCostLeg]
  public let warnings: [DomainWarning]

  public init(
    cost: Double?,
    legs: [LogisticsCostLeg],
    warnings: [DomainWarning]
  ) {
    self.cost = cost
    self.legs = legs
    self.warnings = warnings
  }
}

public struct ManufacturingOpportunitySourcingLine: Identifiable, Equatable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let requiredQuantity: Int64
  public let factualWarehouseQuantity: Int64
  public let protectedQuantity: Int64
  public let reservedQuantity: Int64
  public let usableWarehouseQuantity: Int64
  public let fromWarehouse: Int64
  public let toBuy: Int64
  public let marketFilledQuantity: Int64
  public let weightedUnitPrice: Double?
  public let warehouseReplacementValue: Double?
  public let purchaseCashRequirement: Double?
  public let hasCompleteMarketCoverage: Bool
}

public struct ManufacturingOpportunityProcurementProjection: Equatable,
  Sendable
{
  public let lines: [ManufacturingOpportunitySourcingLine]
  public let warehouseReplacementValue: Double?
  public let purchaseCashRequirement: Double?

  public var totalQuantityToBuy: Int64 {
    lines.reduce(0) { partial, line in
      let (sum, overflow) = partial.addingReportingOverflow(line.toBuy)
      return overflow ? Int64.max : sum
    }
  }

  public var multibuyText: String {
    lines.filter { $0.toBuy > 0 }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      .map { "\($0.name) \($0.toBuy)" }
      .joined(separator: "\n")
  }
}

public struct ManufacturingOpportunityFacilityContext: Codable, Sendable {
  public let name: String
  public let materialMultiplier: Double
  public let timeMultiplier: Double
  public let jobCostMultiplier: Double
  public let facilityTaxRate: Double
  public let systemCostIndex: Double
  public let sccSurchargeRate: Double
  public let alphaSurchargeRate: Double
  public let needsReview: Bool

  public init(
    name: String,
    materialMultiplier: Double,
    timeMultiplier: Double,
    jobCostMultiplier: Double,
    facilityTaxRate: Double,
    systemCostIndex: Double,
    sccSurchargeRate: Double,
    alphaSurchargeRate: Double,
    needsReview: Bool = false
  ) {
    self.name = name
    self.materialMultiplier = materialMultiplier
    self.timeMultiplier = timeMultiplier
    self.jobCostMultiplier = jobCostMultiplier
    self.facilityTaxRate = facilityTaxRate
    self.systemCostIndex = systemCostIndex
    self.sccSurchargeRate = sccSurchargeRate
    self.alphaSurchargeRate = alphaSurchargeRate
    self.needsReview = needsReview
  }
}

public struct ManufacturingOpportunityMaterial: Identifiable, Codable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  /// Published SDE quantity before run, ME and facility modifiers. Older saved
  /// scans keep this unavailable and use an explicitly marked approximation
  /// when the owner changes ME without refreshing the scan.
  public var baseQuantityPerRun: Int64? = nil
  public let quantity: Int64
  public let quote: PriceQuote
  public let packagedVolumePerUnit: Double?
}

public struct ManufacturingOpportunityRow: Identifiable, Codable, Sendable {
  public var id: Int64 { productTypeID }
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let productName: String
  public let categoryName: String
  public let groupName: String
  /// Missing only on legacy saved scans, which exclusively contained
  /// manufacturing rows.
  public var activityKind: BlueprintActivityDefinition.Kind? = nil
  public var metaGroupID: Int64? = nil
  public var techLevel: Int? = nil
  public let facilityName: String?
  public var facilityMaterialMultiplier: Double? = nil
  public var facilityTimeMultiplier: Double? = nil
  public var activityDurationSecondsPerRun: Int64? = nil
  public let runs: Int
  public let outputPerRun: Int64
  public let producedQuantity: Int64
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let durationSeconds: Int64
  public let observedDailyDemand: Int64?
  public var previousDayDemand: Int64? = nil
  public var averageDailyDemand: Int64? = nil
  public var recordedDemandDayCount: Int? = nil
  public var demandChangeFromPreviousDayPercent: Double? = nil
  public let activeBuyDemand: Int64
  public let activeSellSupply: Int64
  public let materials: [ManufacturingOpportunityMaterial]
  public let materialCost: Double?
  public let installationCost: Double?
  public let productionCostBeforeBlueprintAndLogistics: Double?
  public let grossRevenue: Double?
  public let salesTax: Double?
  public let brokerFee: Double?
  public let netRevenue: Double?
  public let contributionProfit: Double?
  public let returnOnInvestment: Double?
  public let iskPerHour: Double?
  public let iskPerCubicMeter: Double?
  public let packagedVolumePerUnit: Double?
  public let warnings: [DomainWarning]

  public var effectiveActivityKind: BlueprintActivityDefinition.Kind {
    activityKind ?? .manufacturing
  }

  public var supportsBlueprintEfficiency: Bool {
    effectiveActivityKind == .manufacturing
  }

  public var displayedMaterialEfficiency: Int? {
    supportsBlueprintEfficiency ? materialEfficiency : nil
  }

  public var displayedTimeEfficiency: Int? {
    supportsBlueprintEfficiency ? timeEfficiency : nil
  }
}

public enum ManufacturingOpportunitySearchPolicy {
  public static let minimumQueryLength = 3

  public static func effectiveQuery(_ rawQuery: String) -> String? {
    let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= minimumQueryLength else { return nil }
    return trimmed
  }

  public static func accepts(
    rawQuery: String,
    productName: String,
    groupName: String,
    categoryName: String
  ) -> Bool {
    accepts(
      effectiveQuery: effectiveQuery(rawQuery),
      productName: productName,
      groupName: groupName,
      categoryName: categoryName
    )
  }

  public static func accepts(
    effectiveQuery query: String?,
    productName: String,
    groupName: String,
    categoryName: String
  ) -> Bool {
    guard let query else { return true }
    return productName.localizedCaseInsensitiveContains(query)
      || groupName.localizedCaseInsensitiveContains(query)
      || categoryName.localizedCaseInsensitiveContains(query)
  }
}

public struct ManufacturingOpportunityDailyDemandRecord: Codable, Equatable,
  Sendable
{
  public let utcDay: Date
  public let observedAt: Date
  public let estimatedUnitsByType: [Int64: Int64]
  public let sourceSnapshotID: UUID

  public init(
    utcDay: Date,
    observedAt: Date,
    estimatedUnitsByType: [Int64: Int64],
    sourceSnapshotID: UUID
  ) {
    self.utcDay = utcDay
    self.observedAt = observedAt
    self.estimatedUnitsByType = estimatedUnitsByType
    self.sourceSnapshotID = sourceSnapshotID
  }

  public func estimatedUnits(for typeID: Int64) -> Int64? {
    estimatedUnitsByType[typeID]
  }
}

public struct ManufacturingOpportunityDailyDemandSummary: Equatable, Sendable {
  public let currentUnits: Int64?
  public let previousDayUnits: Int64?
  public let averageUnits: Int64?
  public let recordedDayCount: Int
  public let changeFromPreviousDayPercent: Double?
}

public struct ManufacturingOpportunityDemandSnapshot: Codable, Equatable,
  Sendable
{
  public static let methodVersion =
    "exact-hub-rolling-24h-surviving-order-depletion-daily-history-v3"
  public static let minimumRateObservationDuration: TimeInterval = 30 * 60

  public let regionID: Int64
  public let locationID: Int64
  public let utcDay: Date
  public let firstObservedAt: Date
  public let lastObservedAt: Date
  public let sampleCount: Int
  public let comparedOrderCount: Int
  public let decreasedOrderCount: Int
  public let comparedOrderCountByType: [Int64: Int]?
  public let observedUnitsByType: [Int64: Int64]
  public let dailyHistory: [ManufacturingOpportunityDailyDemandRecord]?
  public let source: SourceIdentity

  public init(
    regionID: Int64,
    locationID: Int64,
    utcDay: Date,
    firstObservedAt: Date,
    lastObservedAt: Date,
    sampleCount: Int,
    comparedOrderCount: Int,
    decreasedOrderCount: Int,
    comparedOrderCountByType: [Int64: Int]? = nil,
    observedUnitsByType: [Int64: Int64],
    dailyHistory: [ManufacturingOpportunityDailyDemandRecord]? = nil,
    source: SourceIdentity
  ) {
    self.regionID = regionID
    self.locationID = locationID
    self.utcDay = utcDay
    self.firstObservedAt = firstObservedAt
    self.lastObservedAt = lastObservedAt
    self.sampleCount = sampleCount
    self.comparedOrderCount = comparedOrderCount
    self.decreasedOrderCount = decreasedOrderCount
    self.comparedOrderCountByType = comparedOrderCountByType
    self.observedUnitsByType = observedUnitsByType
    self.dailyHistory = dailyHistory
    self.source = source
  }

  public func observedUnits(for typeID: Int64) -> Int64? {
    guard sampleCount >= 2,
      (comparedOrderCountByType?[typeID, default: 0] ?? 0) > 0
    else { return nil }
    return observedUnitsByType[typeID, default: 0]
  }

  public var observationDuration: TimeInterval {
    max(0, lastObservedAt.timeIntervalSince(firstObservedAt))
  }

  /// Normalizes the observed exact-hub lower bound to a 24-hour rate. A short
  /// manual rescan cannot create a misleading daily extrapolation.
  public func estimatedDailyUnits(for typeID: Int64) -> Double? {
    guard let observed = observedUnits(for: typeID),
      observationDuration >= Self.minimumRateObservationDuration
    else { return nil }
    let rate =
      Double(observed) * (24 * 60 * 60) / observationDuration
    return rate.isFinite && rate >= 0 ? rate : nil
  }

  public func dailySummary(
    for typeID: Int64
  ) -> ManufacturingOpportunityDailyDemandSummary {
    let currentUnits = Self.roundedDailyUnits(
      estimatedDailyUnits(for: typeID)
    )
    let records = (dailyHistory ?? []).sorted { $0.utcDay < $1.utcDay }
    let previousDay = utcDay.addingTimeInterval(-24 * 60 * 60)
    let previousUnits = records.first(where: { $0.utcDay == previousDay })?
      .estimatedUnits(for: typeID)
    let knownDailyUnits = records.compactMap { $0.estimatedUnits(for: typeID) }
    let averageUnits: Int64?
    if knownDailyUnits.isEmpty {
      averageUnits = nil
    } else {
      let average =
        knownDailyUnits.reduce(0.0) { $0 + Double($1) }
        / Double(knownDailyUnits.count)
      averageUnits = Self.roundedDailyUnits(average)
    }
    let changePercent: Double?
    if let currentUnits, let previousUnits {
      if previousUnits > 0 {
        let value =
          (Double(currentUnits) - Double(previousUnits))
          / Double(previousUnits) * 100
        changePercent = value.isFinite ? value : nil
      } else {
        changePercent = currentUnits == 0 ? 0 : nil
      }
    } else {
      changePercent = nil
    }
    return ManufacturingOpportunityDailyDemandSummary(
      currentUnits: currentUnits,
      previousDayUnits: previousUnits,
      averageUnits: averageUnits,
      recordedDayCount: knownDailyUnits.count,
      changeFromPreviousDayPercent: changePercent
    )
  }

  fileprivate func dailyRecord() -> ManufacturingOpportunityDailyDemandRecord? {
    guard observationDuration >= Self.minimumRateObservationDuration,
      let comparedOrderCountByType
    else { return nil }
    let values = comparedOrderCountByType.keys.reduce(
      into: [Int64: Int64]()
    ) { result, typeID in
      if let units = Self.roundedDailyUnits(estimatedDailyUnits(for: typeID)) {
        result[typeID] = units
      }
    }
    guard !values.isEmpty else { return nil }
    return ManufacturingOpportunityDailyDemandRecord(
      utcDay: utcDay,
      observedAt: lastObservedAt,
      estimatedUnitsByType: values,
      sourceSnapshotID: source.snapshotID
    )
  }

  fileprivate func withDailyHistory(
    _ history: [ManufacturingOpportunityDailyDemandRecord]?
  ) -> ManufacturingOpportunityDemandSnapshot {
    ManufacturingOpportunityDemandSnapshot(
      regionID: regionID,
      locationID: locationID,
      utcDay: utcDay,
      firstObservedAt: firstObservedAt,
      lastObservedAt: lastObservedAt,
      sampleCount: sampleCount,
      comparedOrderCount: comparedOrderCount,
      decreasedOrderCount: decreasedOrderCount,
      comparedOrderCountByType: comparedOrderCountByType,
      observedUnitsByType: observedUnitsByType,
      dailyHistory: history,
      source: source
    )
  }

  private static func roundedDailyUnits(_ rate: Double?) -> Int64? {
    guard let rate, rate.isFinite, rate >= 0, rate <= Double(Int64.max) else {
      return nil
    }
    return Int64(rate.rounded())
  }
}

public struct ManufacturingOpportunityDemandLedger: Codable, Equatable,
  Sendable
{
  public static let schemaVersion = 4
  private static let rollingWindow: TimeInterval = 24 * 60 * 60
  private static let maximumComparisonGap: TimeInterval = 24 * 60 * 60
  private static let retainedDailyHistoryCount = 30

  private struct OrderBaseline: Codable, Equatable, Sendable {
    let typeID: Int64
    let locationID: Int64
    let side: MarketOrderSide
    let volumeRemaining: Int64
  }

  private struct DemandInterval: Codable, Equatable, Sendable {
    let firstObservedAt: Date
    let lastObservedAt: Date
    let comparedOrderCount: Int
    let decreasedOrderCount: Int
    let comparedOrderCountByType: [Int64: Int]
    let observedUnitsByType: [Int64: Int64]
  }

  public let version: Int
  public private(set) var demand: ManufacturingOpportunityDemandSnapshot?
  private var previousOrdersByID: [Int64: OrderBaseline]
  private var previousSourceSnapshotID: UUID?
  private var previousObservedAt: Date?
  private var intervals: [DemandInterval]

  public var baselineOrderCount: Int { previousOrdersByID.count }

  public init() {
    version = Self.schemaVersion
    demand = nil
    previousOrdersByID = [:]
    previousSourceSnapshotID = nil
    previousObservedAt = nil
    intervals = []
  }

  @discardableResult
  public mutating func observe(
    _ market: MarketOrderSnapshot
  ) -> ManufacturingOpportunityDemandSnapshot {
    observe(market, cancellationCheck: {})
  }

  @discardableResult
  public mutating func observe(
    _ market: MarketOrderSnapshot,
    cancellationCheck: () throws -> Void
  ) rethrows -> ManufacturingOpportunityDemandSnapshot {
    try cancellationCheck()
    if previousSourceSnapshotID == market.source.snapshotID,
      let demand
    {
      return demand
    }

    let currentOrders = try Self.compactOrders(
      in: market,
      cancellationCheck: cancellationCheck
    )
    let comparisonGap = previousObservedAt.map {
      market.capturedAt.timeIntervalSince($0)
    }
    let scopeChanged =
      demand.map {
        $0.regionID != market.regionID
          || $0.locationID != market.locationID
      } ?? true
    let mustReset =
      scopeChanged
      || previousOrdersByID.isEmpty
      || comparisonGap == nil
      || comparisonGap.map { $0 <= 0 || $0 > Self.maximumComparisonGap }
        == true

    if mustReset {
      let initial = ManufacturingOpportunityDemandSnapshot(
        regionID: market.regionID,
        locationID: market.locationID,
        utcDay: Self.utcDay(containing: market.capturedAt),
        firstObservedAt: market.capturedAt,
        lastObservedAt: market.capturedAt,
        sampleCount: 1,
        comparedOrderCount: 0,
        decreasedOrderCount: 0,
        comparedOrderCountByType: [:],
        observedUnitsByType: [:],
        source: market.source
      )
      let history = Self.updatedDailyHistory(
        existing: scopeChanged ? [] : demand?.dailyHistory ?? [],
        snapshots: scopeChanged ? [] : [demand].compactMap { $0 },
        currentUTCDay: initial.utcDay
      )
      let initialWithHistory = initial.withDailyHistory(history)
      demand = initialWithHistory
      previousOrdersByID = currentOrders
      previousSourceSnapshotID = market.source.snapshotID
      previousObservedAt = market.capturedAt
      intervals = []
      return initialWithHistory
    }

    var intervalVolumes: [Int64: Int64] = [:]
    var intervalComparedByType: [Int64: Int] = [:]
    var intervalCompared = 0
    var intervalDecreased = 0
    var processedOrderCount = 0
    for (orderID, current) in currentOrders {
      processedOrderCount += 1
      if processedOrderCount.isMultiple(of: 2_048) {
        try cancellationCheck()
      }
      guard let previous = previousOrdersByID[orderID],
        previous.typeID == current.typeID,
        previous.locationID == current.locationID,
        previous.side == current.side
      else { continue }
      intervalCompared = Self.saturatedAdd(intervalCompared, 1)
      intervalComparedByType[current.typeID] = Self.saturatedAdd(
        intervalComparedByType[current.typeID, default: 0],
        1
      )
      guard current.volumeRemaining < previous.volumeRemaining else {
        continue
      }
      intervalDecreased = Self.saturatedAdd(intervalDecreased, 1)
      let delta = previous.volumeRemaining - current.volumeRemaining
      intervalVolumes[current.typeID] = Self.saturatedAdd(
        intervalVolumes[current.typeID, default: 0],
        delta
      )
    }
    try cancellationCheck()

    let interval = DemandInterval(
      firstObservedAt: previousObservedAt ?? market.capturedAt,
      lastObservedAt: market.capturedAt,
      comparedOrderCount: intervalCompared,
      decreasedOrderCount: intervalDecreased,
      comparedOrderCountByType: intervalComparedByType,
      observedUnitsByType: intervalVolumes
    )
    let cutoff = market.capturedAt.addingTimeInterval(-Self.rollingWindow)
    var acceptedIntervals = intervals.filter {
      $0.firstObservedAt >= cutoff && $0.lastObservedAt <= market.capturedAt
    }
    acceptedIntervals.append(interval)
    let aggregate = Self.aggregate(acceptedIntervals)
    let updated = ManufacturingOpportunityDemandSnapshot(
      regionID: market.regionID,
      locationID: market.locationID,
      utcDay: Self.utcDay(containing: market.capturedAt),
      firstObservedAt: aggregate.firstObservedAt,
      lastObservedAt: market.capturedAt,
      sampleCount: Self.saturatedAdd(acceptedIntervals.count, 1),
      comparedOrderCount: aggregate.comparedOrderCount,
      decreasedOrderCount: aggregate.decreasedOrderCount,
      comparedOrderCountByType: aggregate.comparedOrderCountByType,
      observedUnitsByType: aggregate.observedUnitsByType,
      source: market.source
    )
    let history = Self.updatedDailyHistory(
      existing: demand?.dailyHistory ?? [],
      snapshots: [demand, updated].compactMap { $0 },
      currentUTCDay: updated.utcDay
    )
    let updatedWithHistory = updated.withDailyHistory(history)
    demand = updatedWithHistory
    previousOrdersByID = currentOrders
    previousSourceSnapshotID = market.source.snapshotID
    previousObservedAt = market.capturedAt
    intervals = acceptedIntervals
    return updatedWithHistory
  }

  private static func updatedDailyHistory(
    existing: [ManufacturingOpportunityDailyDemandRecord],
    snapshots: [ManufacturingOpportunityDemandSnapshot],
    currentUTCDay: Date
  ) -> [ManufacturingOpportunityDailyDemandRecord] {
    var recordsByDay: [Date: ManufacturingOpportunityDailyDemandRecord] = [:]
    for record in existing {
      if let previous = recordsByDay[record.utcDay],
        previous.observedAt > record.observedAt
      {
        continue
      }
      recordsByDay[record.utcDay] = record
    }
    for snapshot in snapshots {
      guard let record = snapshot.dailyRecord() else { continue }
      if let previous = recordsByDay[record.utcDay],
        previous.observedAt > record.observedAt
      {
        continue
      }
      recordsByDay[record.utcDay] = record
    }
    let earliestRetainedDay = currentUTCDay.addingTimeInterval(
      -Double(Self.retainedDailyHistoryCount - 1) * 24 * 60 * 60
    )
    return recordsByDay.values
      .filter {
        $0.utcDay >= earliestRetainedDay && $0.utcDay <= currentUTCDay
      }
      .sorted { $0.utcDay < $1.utcDay }
      .suffix(Self.retainedDailyHistoryCount)
      .map { $0 }
  }

  private static func aggregate(
    _ intervals: [DemandInterval]
  ) -> (
    firstObservedAt: Date,
    comparedOrderCount: Int,
    decreasedOrderCount: Int,
    comparedOrderCountByType: [Int64: Int],
    observedUnitsByType: [Int64: Int64]
  ) {
    var compared = 0
    var decreased = 0
    var comparedByType: [Int64: Int] = [:]
    var unitsByType: [Int64: Int64] = [:]
    for interval in intervals {
      compared = saturatedAdd(compared, interval.comparedOrderCount)
      decreased = saturatedAdd(decreased, interval.decreasedOrderCount)
      for (typeID, count) in interval.comparedOrderCountByType {
        comparedByType[typeID] = saturatedAdd(
          comparedByType[typeID, default: 0],
          count
        )
      }
      for (typeID, units) in interval.observedUnitsByType {
        unitsByType[typeID] = saturatedAdd(
          unitsByType[typeID, default: 0],
          units
        )
      }
    }
    return (
      firstObservedAt: intervals.first?.firstObservedAt ?? .distantPast,
      comparedOrderCount: compared,
      decreasedOrderCount: decreased,
      comparedOrderCountByType: comparedByType,
      observedUnitsByType: unitsByType
    )
  }

  private static func compactOrders(
    in market: MarketOrderSnapshot,
    cancellationCheck: () throws -> Void
  ) rethrows -> [Int64: OrderBaseline] {
    var result: [Int64: OrderBaseline] = [:]
    result.reserveCapacity(
      market.ordersByType.values.reduce(0) { $0 + $1.count }
    )
    var processedOrderCount = 0
    for orders in market.ordersByType.values {
      for order in orders {
        processedOrderCount += 1
        if processedOrderCount.isMultiple(of: 2_048) {
          try cancellationCheck()
        }
        guard
          let compact = compactOrder(
            order,
            exactLocationID: market.locationID
          )
        else { continue }
        result[order.id] = compact
      }
    }
    try cancellationCheck()
    return result
  }

  private static func compactOrder(
    _ order: MarketOrder,
    exactLocationID: Int64
  ) -> OrderBaseline? {
    guard order.locationID == exactLocationID,
      order.price.isFinite,
      order.price > 0,
      order.volumeRemaining > 0
    else { return nil }
    return OrderBaseline(
      typeID: order.typeID,
      locationID: order.locationID,
      side: order.side,
      volumeRemaining: order.volumeRemaining
    )
  }

  private enum CodingKeys: String, CodingKey {
    case version = "v"
    case demand = "d"
    case orders = "o"
    case sourceSnapshotID = "s"
    case previousObservedAt = "p"
    case intervals = "i"
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case version
    case demand
    case previousOrdersByID
    case previousSourceSnapshotID
  }

  public init(from decoder: any Decoder) throws {
    if let compact = try? decoder.container(keyedBy: CodingKeys.self),
      compact.contains(.version)
    {
      let decodedVersion = try compact.decode(Int.self, forKey: .version)
      guard (2...Self.schemaVersion).contains(decodedVersion) else {
        throw DecodingError.dataCorruptedError(
          forKey: .version,
          in: compact,
          debugDescription: "Unsupported demand-ledger version."
        )
      }
      version = Self.schemaVersion
      demand = try compact.decodeIfPresent(
        ManufacturingOpportunityDemandSnapshot.self,
        forKey: .demand
      )
      previousSourceSnapshotID = try compact.decodeIfPresent(
        UUID.self,
        forKey: .sourceSnapshotID
      )
      previousObservedAt =
        try compact.decodeIfPresent(
          Date.self,
          forKey: .previousObservedAt
        ) ?? demand?.lastObservedAt
      intervals =
        decodedVersion >= 3
        ? try compact.decodeIfPresent(
          [DemandInterval].self,
          forKey: .intervals
        ) ?? [] : []
      var decodedOrders: [Int64: OrderBaseline] = [:]
      var rows = try compact.nestedUnkeyedContainer(forKey: .orders)
      while !rows.isAtEnd {
        var row = try rows.nestedUnkeyedContainer()
        let orderID = try row.decode(Int64.self)
        let typeID = try row.decode(Int64.self)
        let locationID = try row.decode(Int64.self)
        let sideValue = try row.decode(UInt8.self)
        guard let side = Self.side(encodedAs: sideValue) else {
          throw DecodingError.dataCorruptedError(
            in: row,
            debugDescription: "Invalid compact market-order side."
          )
        }
        let volumeRemaining = try row.decode(Int64.self)
        decodedOrders[orderID] = OrderBaseline(
          typeID: typeID,
          locationID: locationID,
          side: side,
          volumeRemaining: volumeRemaining
        )
      }
      previousOrdersByID = decodedOrders
      return
    }

    let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
    let legacyVersion = try legacy.decode(Int.self, forKey: .version)
    guard legacyVersion == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .version,
        in: legacy,
        debugDescription: "Unsupported demand-ledger version."
      )
    }
    version = Self.schemaVersion
    demand = try legacy.decodeIfPresent(
      ManufacturingOpportunityDemandSnapshot.self,
      forKey: .demand
    )
    previousOrdersByID = try legacy.decode(
      [Int64: OrderBaseline].self,
      forKey: .previousOrdersByID
    )
    previousSourceSnapshotID = try legacy.decodeIfPresent(
      UUID.self,
      forKey: .previousSourceSnapshotID
    )
    previousObservedAt = demand?.lastObservedAt
    intervals = []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.schemaVersion, forKey: .version)
    try container.encodeIfPresent(demand, forKey: .demand)
    try container.encodeIfPresent(
      previousSourceSnapshotID,
      forKey: .sourceSnapshotID
    )
    try container.encodeIfPresent(
      previousObservedAt,
      forKey: .previousObservedAt
    )
    try container.encode(intervals, forKey: .intervals)
    var rows = container.nestedUnkeyedContainer(forKey: .orders)
    for (orderID, order) in previousOrdersByID {
      var row = rows.nestedUnkeyedContainer()
      try row.encode(orderID)
      try row.encode(order.typeID)
      try row.encode(order.locationID)
      try row.encode(Self.encodedSide(order.side))
      try row.encode(order.volumeRemaining)
    }
  }

  private static func encodedSide(_ side: MarketOrderSide) -> UInt8 {
    switch side {
    case .buy: 0
    case .sell: 1
    }
  }

  private static func side(encodedAs value: UInt8) -> MarketOrderSide? {
    switch value {
    case 0: .buy
    case 1: .sell
    default: nil
    }
  }

  private static func utcDay(containing date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.startOfDay(for: date)
  }

  private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
  }

  private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : sum
  }
}

public enum ManufacturingOpportunityAutomaticRefreshPolicy {
  public static let minimumInterval: TimeInterval = 6 * 60 * 60
  public static let startupDelay: TimeInterval = 15

  public static func shouldRefresh(
    lastObservedAt: Date?,
    now: Date = .now
  ) -> Bool {
    guard let lastObservedAt else { return true }
    return now.timeIntervalSince(lastObservedAt) >= minimumInterval
  }

  public static func nextAutomaticRunAt(
    lastObservedAt: Date?,
    now: Date = .now
  ) -> Date {
    let startupBoundary = now.addingTimeInterval(startupDelay)
    guard let lastObservedAt else { return startupBoundary }
    return max(
      startupBoundary,
      lastObservedAt.addingTimeInterval(minimumInterval)
    )
  }
}

public struct ManufacturingOpportunityCoverage: Codable, Equatable, Sendable {
  public let completeManufacturingDefinitionCount: Int
  /// Missing on legacy saved scans created before reactions were included.
  public var completeReactionDefinitionCount: Int? = nil
  public let mainHubActiveOrderTypeCount: Int
  public let candidateCount: Int
  public let candidatesWithSellOrders: Int
  public let candidatesWithBuyOrders: Int

  public init(
    completeManufacturingDefinitionCount: Int,
    completeReactionDefinitionCount: Int? = nil,
    mainHubActiveOrderTypeCount: Int,
    candidateCount: Int,
    candidatesWithSellOrders: Int,
    candidatesWithBuyOrders: Int
  ) {
    self.completeManufacturingDefinitionCount =
      completeManufacturingDefinitionCount
    self.completeReactionDefinitionCount = completeReactionDefinitionCount
    self.mainHubActiveOrderTypeCount = mainHubActiveOrderTypeCount
    self.candidateCount = candidateCount
    self.candidatesWithSellOrders = candidatesWithSellOrders
    self.candidatesWithBuyOrders = candidatesWithBuyOrders
  }
}

public struct ManufacturingOpportunitySnapshot: Identifiable, Codable,
  Sendable
{
  public let id: UUID
  public let createdAt: Date
  public let settings: ManufacturingOpportunitySettings
  public let mainHub: ProcurementLocation
  public let productionWarehouseScope: ProductionWarehouseScope
  public let logisticsConfiguration: LogisticsConfiguration?
  public let rows: [ManufacturingOpportunityRow]
  public let coverage: ManufacturingOpportunityCoverage
  public let demand: ManufacturingOpportunityDemandSnapshot?
  public let sdeSource: SourceIdentity
  public let marketSource: SourceIdentity
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    settings: ManufacturingOpportunitySettings,
    mainHub: ProcurementLocation,
    productionWarehouseScope: ProductionWarehouseScope,
    logisticsConfiguration: LogisticsConfiguration? = nil,
    rows: [ManufacturingOpportunityRow],
    coverage: ManufacturingOpportunityCoverage,
    demand: ManufacturingOpportunityDemandSnapshot? = nil,
    sdeSource: SourceIdentity,
    marketSource: SourceIdentity,
    warnings: [DomainWarning]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.settings = settings
    self.mainHub = mainHub
    self.productionWarehouseScope = productionWarehouseScope
    self.logisticsConfiguration = logisticsConfiguration
    self.rows = rows
    self.coverage = coverage
    self.demand = demand
    self.sdeSource = sdeSource
    self.marketSource = marketSource
    self.warnings = warnings
  }
}

public enum ManufacturingOpportunitySnapshotStoreError: Error, Equatable,
  Sendable
{
  case unsupportedVersion
  case unreadable
  case unwritable
}

/// Atomic last-known-good persistence for the catalog-wide opportunity list.
/// An unreadable existing file is never silently replaced by a new scan.
public actor ManufacturingOpportunitySnapshotStore {
  public static let schemaVersion = 1

  private struct Envelope: Codable, Sendable {
    let version: Int
    let snapshot: ManufacturingOpportunitySnapshot
  }

  private let fileURL: URL
  private var hasLoaded = false
  private var hasValidatedStoredSnapshot = false
  private var cachedSnapshot: ManufacturingOpportunitySnapshot?

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> ManufacturingOpportunitySnapshot? {
    try loadExistingIfNeeded()
    return cachedSnapshot
  }

  public func save(_ snapshot: ManufacturingOpportunitySnapshot) throws {
    if !hasValidatedStoredSnapshot {
      try loadExistingIfNeeded()
    }
    let encoded: Data
    do {
      encoded = try JSONEncoder().encode(
        Envelope(version: Self.schemaVersion, snapshot: snapshot)
      )
    } catch {
      throw ManufacturingOpportunitySnapshotStoreError.unwritable
    }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try encoded.write(to: fileURL, options: .atomic)
    } catch {
      throw ManufacturingOpportunitySnapshotStoreError.unwritable
    }
    cachedSnapshot = snapshot
    hasLoaded = true
    hasValidatedStoredSnapshot = true
  }

  /// Releases the decoded in-memory copy while keeping the atomic on-disk
  /// snapshot as the last-known-good source for a later load.
  public func releaseCachedSnapshot() {
    cachedSnapshot = nil
    hasLoaded = false
  }

  private func loadExistingIfNeeded() throws {
    guard !hasLoaded else { return }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      hasLoaded = true
      hasValidatedStoredSnapshot = true
      cachedSnapshot = nil
      return
    }
    let envelope: Envelope
    do {
      envelope = try JSONDecoder().decode(
        Envelope.self,
        from: Data(contentsOf: fileURL)
      )
    } catch {
      throw ManufacturingOpportunitySnapshotStoreError.unreadable
    }
    guard envelope.version == Self.schemaVersion else {
      throw ManufacturingOpportunitySnapshotStoreError.unsupportedVersion
    }
    cachedSnapshot = envelope.snapshot
    hasLoaded = true
    hasValidatedStoredSnapshot = true
  }
}

public enum ManufacturingOpportunityError: Error, Equatable, Sendable {
  case invalidSettings
  case noManufacturingDefinitions
  case inconsistentMarketLocation
}

public enum ManufacturingOpportunityAnalyzer {
  public static func analyze(
    definitions: [BlueprintDefinition],
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    packagedVolumes: [Int64: Double],
    settings: ManufacturingOpportunitySettings,
    mainHub: ProcurementLocation,
    productionWarehouseScope: ProductionWarehouseScope,
    logisticsConfiguration: LogisticsConfiguration? = nil,
    market: MarketOrderSnapshot,
    demand: ManufacturingOpportunityDemandSnapshot? = nil,
    adjustedPrices: [Int64: AdjustedPrice],
    facilities: [ManufacturingCategory: ManufacturingOpportunityFacilityContext],
    reactionFacility: ReactionFacilityCostContext? = nil,
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) throws -> ManufacturingOpportunitySnapshot {
    let requestedRunsAreValid =
      settings.requestedRuns.map {
        (1...ManufacturingOpportunitySettings.maximumRequestedRuns).contains(
          $0
        )
      } ?? true
    guard
      (1...ManufacturingOpportunitySettings.maximumTargetQuantity)
        .contains(settings.targetQuantity),
      requestedRunsAreValid,
      (0...10).contains(settings.materialEfficiency),
      (0...20).contains(settings.timeEfficiency)
    else { throw ManufacturingOpportunityError.invalidSettings }
    guard market.locationID == mainHub.locationID,
      mainHub.regionID.map({ $0 == market.regionID }) ?? true
    else { throw ManufacturingOpportunityError.inconsistentMarketLocation }
    let manufacturing = definitions.filter {
      $0.activity.kind == .manufacturing
        && !$0.activity.materials.isEmpty
        && !$0.activity.products.isEmpty
    }
    let reactions = definitions.filter {
      $0.activity.kind == .reaction
        && !$0.activity.materials.isEmpty
        && !$0.activity.products.isEmpty
    }
    guard let sdeSource = (manufacturing.first ?? reactions.first)?.source else {
      throw ManufacturingOpportunityError.noManufacturingDefinitions
    }

    var rows: [ManufacturingOpportunityRow] = []
    rows.reserveCapacity(manufacturing.count + reactions.count)
    for (index, definition) in manufacturing.enumerated() {
      if index.isMultiple(of: 64) {
        try Task.checkCancellation()
      }
      if let candidate = row(
        definition: definition,
        typeNames: typeNames,
        classification: classifications[definition.productTypeID],
        packagedVolume: packagedVolumes[definition.productTypeID],
        packagedVolumes: packagedVolumes,
        settings: settings,
        market: market,
        demandSummary: demand?.dailySummary(for: definition.productTypeID),
        adjustedPrices: adjustedPrices,
        facility: facilities[
          classifications[definition.productTypeID]?.manufacturingCategory
            ?? .module
        ],
        salesTaxRate: salesTaxRate,
        brokerFeeRate: brokerFeeRate
      ) {
        rows.append(candidate)
      }
    }
    for (index, definition) in reactions.enumerated() {
      if index.isMultiple(of: 64) {
        try Task.checkCancellation()
      }
      if let candidate = try reactionRow(
        definition: definition,
        typeNames: typeNames,
        classifications: classifications,
        packagedVolume: packagedVolumes[definition.productTypeID],
        packagedVolumes: packagedVolumes,
        settings: settings,
        market: market,
        demandSummary: demand?.dailySummary(for: definition.productTypeID),
        adjustedPrices: adjustedPrices,
        facility: reactionFacility,
        salesTaxRate: salesTaxRate,
        brokerFeeRate: brokerFeeRate
      ) {
        rows.append(candidate)
      }
    }
    rows.sort {
      $0.productName.localizedCaseInsensitiveCompare($1.productName)
        == .orderedAscending
    }
    var warnings = [
      DomainWarning(
        code: "manufacturing-opportunity.blueprint-cost-scope",
        message:
          "Blueprint acquisition or allocation for manufacturing candidates remains excluded until an explicit amount is entered under Costs and budget. Reactions do not use Blueprint allocation. Logistics, installation, sales tax and broker fee use the saved Profile configuration automatically.",
        severity: .warning,
        source: sdeSource
      )
    ]
    if logisticsConfiguration == nil {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.logistics-snapshot-missing",
          message:
            "This saved scan predates the automatic logistics calculation. Update it before using profit, ROI or ISK rates.",
          severity: .blocking,
          source: sdeSource
        )
      )
    }
    if let demand,
      demand.sampleCount >= 2,
      demand.comparedOrderCountByType != nil,
      demand.observationDuration
        >= ManufacturingOpportunityDemandSnapshot
        .minimumRateObservationDuration
    {
      warnings.insert(
        DomainWarning(
          code: "manufacturing-opportunity.observed-demand-lower-bound",
          message:
            "Daily demand is a 24-hour-normalized lower-bound rate from the rolling exact Main Hub observation window. It counts volume decreases only for order IDs present in consecutive snapshots; disappeared, expired or cancelled orders are not guessed, and each type needs at least one comparable order.",
          severity: .information,
          source: demand.source
        ),
        at: 0
      )
    } else {
      warnings.insert(
        DomainWarning(
          code: "manufacturing-opportunity.observed-demand-needs-baseline",
          message:
            "Daily demand is unavailable until two different exact Main Hub snapshots at least 30 minutes apart contain a comparable order for that type.",
          severity: .information,
          source: market.source
        ),
        at: 0
      )
    }
    if salesTaxRate == nil || brokerFeeRate == nil {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.missing-sales-fees",
          message:
            "Trader sales tax or broker fee is unavailable, so net revenue, contribution, ROI and ISK rates remain unavailable.",
          severity: .blocking
        )
      )
    }
    return ManufacturingOpportunitySnapshot(
      settings: settings,
      mainHub: mainHub,
      productionWarehouseScope: productionWarehouseScope,
      logisticsConfiguration: logisticsConfiguration,
      rows: rows,
      coverage: ManufacturingOpportunityCoverage(
        completeManufacturingDefinitionCount: manufacturing.count,
        completeReactionDefinitionCount: reactions.count,
        mainHubActiveOrderTypeCount: market.ordersByType.values.reduce(0) {
          count, orders in
          count
            + (orders.contains(where: {
              $0.locationID == market.locationID && $0.price.isFinite
                && $0.price > 0 && $0.volumeRemaining > 0
            }) ? 1 : 0)
        },
        candidateCount: rows.count,
        candidatesWithSellOrders: rows.count { $0.activeSellSupply > 0 },
        candidatesWithBuyOrders: rows.count { $0.activeBuyDemand > 0 }
      ),
      // Daily history stays in the dedicated compact demand summary/ledger.
      // Rows already freeze the current, previous-day and average values, so
      // duplicating up to 30 per-type dictionaries in the opportunity file
      // would only increase startup RSS and disk I/O.
      demand: demand?.withDailyHistory(nil),
      sdeSource: sdeSource,
      marketSource: market.source,
      warnings: warnings
    )
  }

  private static func row(
    definition: BlueprintDefinition,
    typeNames: [Int64: String],
    classification: IndustryItemClassification?,
    packagedVolume: Double?,
    packagedVolumes: [Int64: Double],
    settings: ManufacturingOpportunitySettings,
    market: MarketOrderSnapshot,
    demandSummary: ManufacturingOpportunityDailyDemandSummary?,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ManufacturingOpportunityFacilityContext?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) -> ManufacturingOpportunityRow? {
    let productOrders = (market.ordersByType[definition.productTypeID] ?? [])
      .filter {
        $0.locationID == market.locationID && $0.price.isFinite && $0.price > 0
          && $0.volumeRemaining > 0
      }
    guard
      let product = definition.activity.products.first(where: {
        $0.typeID == definition.productTypeID && $0.quantity > 0
      })
    else { return nil }
    let runs = settings.resolvedRuns(outputPerRun: product.quantity)
    guard runs > 0, let produced = multiplied(product.quantity, by: runs)
    else { return nil }

    var warnings: [DomainWarning] = []
    if !productOrders.contains(where: { $0.side == .sell }) {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.product-sell-order-unavailable",
          message:
            "No active sell order is available for this product at the exact Main Hub. Revenue and dependent profitability values remain unavailable.",
          severity: .blocking,
          source: market.source
        )
      )
    }
    if facility == nil || facility?.needsReview == true {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.facility-unavailable",
          message:
            "The selected production facility or its modifiers are unavailable or need review.",
          severity: .blocking,
          source: definition.source
        )
      )
    }
    let multiplier = facility?.materialMultiplier ?? 1
    let materials = definition.activity.materials.compactMap {
      material -> ManufacturingOpportunityMaterial? in
      let quantity = IndustryPlanner.manufacturingMaterialQuantity(
        baseQuantity: material.quantity,
        runs: runs,
        materialEfficiency: settings.materialEfficiency,
        facilityMultiplier: multiplier
      )
      guard quantity > 0, quantity < Int64.max else { return nil }
      let quote = MarketPriceEngine.quote(
        typeID: material.typeID,
        quantity: quantity,
        scenario: .materialBuy,
        snapshot: market
      )
      warnings.append(contentsOf: quote.warnings)
      return ManufacturingOpportunityMaterial(
        typeID: material.typeID,
        name: typeNames[material.typeID] ?? "Type \(material.typeID)",
        baseQuantityPerRun: material.quantity,
        quantity: quantity,
        quote: quote,
        packagedVolumePerUnit: packagedVolumes[material.typeID]
      )
    }
    guard materials.count == definition.activity.materials.count else {
      return nil
    }
    let materialCost = sum(materials.map { $0.quote.total })
    let installationCost = facility.flatMap {
      installation(
        definition: definition,
        runs: runs,
        adjustedPrices: adjustedPrices,
        facility: $0
      )
    }
    if facility != nil, installationCost == nil {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.installation-unavailable",
          message:
            "Installation cost is unavailable because a required adjusted price or production-system index is missing.",
          severity: .blocking,
          source: definition.source
        )
      )
    }
    let operatingCost = pairSum(materialCost, installationCost)
    let bestSell = productOrders.filter { $0.side == .sell }.map(\.price).min()
    let grossRevenue = bestSell.flatMap { safeProduct($0, Double(produced)) }
    let salesTax = fee(grossRevenue, rate: salesTaxRate)
    let brokerFee = fee(grossRevenue, rate: brokerFeeRate)
    let netRevenue: Double?
    if let grossRevenue, let salesTax, let brokerFee {
      netRevenue = safeDifference(grossRevenue, salesTax + brokerFee)
    } else {
      netRevenue = nil
    }
    let contribution = difference(netRevenue, operatingCost)
    let roi: Double?
    if let contribution, let operatingCost, operatingCost > 0 {
      roi = finite(contribution / operatingCost)
    } else {
      roi = nil
    }
    let duration = durationSeconds(
      base: definition.activity.durationSeconds,
      runs: runs,
      timeEfficiency: settings.timeEfficiency,
      multiplier: facility?.timeMultiplier
    )
    let iskPerHour = contribution.flatMap {
      duration > 0 ? finite($0 / (Double(duration) / 3_600)) : nil
    }
    let totalVolume = packagedVolume.flatMap {
      $0 >= 0 ? safeProduct($0, Double(produced)) : nil
    }
    let iskPerCubicMeter = contribution.flatMap { profit in
      totalVolume.flatMap { $0 > 0 ? finite(profit / $0) : nil }
    }
    return ManufacturingOpportunityRow(
      blueprintTypeID: definition.blueprintTypeID,
      productTypeID: definition.productTypeID,
      productName: typeNames[definition.productTypeID]
        ?? "Type \(definition.productTypeID)",
      categoryName: classification?.categoryName ?? "Unclassified",
      groupName: classification?.groupName ?? "Unclassified",
      activityKind: .manufacturing,
      metaGroupID: classification?.metaGroupID,
      techLevel: classification?.techLevel,
      facilityName: facility?.name,
      facilityMaterialMultiplier: facility?.materialMultiplier,
      facilityTimeMultiplier: facility?.timeMultiplier,
      activityDurationSecondsPerRun: definition.activity.durationSeconds,
      runs: runs,
      outputPerRun: product.quantity,
      producedQuantity: produced,
      materialEfficiency: settings.materialEfficiency,
      timeEfficiency: settings.timeEfficiency,
      durationSeconds: duration,
      observedDailyDemand: demandSummary?.currentUnits,
      previousDayDemand: demandSummary?.previousDayUnits,
      averageDailyDemand: demandSummary?.averageUnits,
      recordedDemandDayCount: demandSummary?.recordedDayCount ?? 0,
      demandChangeFromPreviousDayPercent:
        demandSummary?.changeFromPreviousDayPercent,
      activeBuyDemand: saturatedVolume(productOrders, side: .buy),
      activeSellSupply: saturatedVolume(productOrders, side: .sell),
      materials: materials,
      materialCost: materialCost,
      installationCost: installationCost,
      productionCostBeforeBlueprintAndLogistics: operatingCost,
      grossRevenue: grossRevenue,
      salesTax: salesTax,
      brokerFee: brokerFee,
      netRevenue: netRevenue,
      contributionProfit: contribution,
      returnOnInvestment: roi,
      iskPerHour: iskPerHour,
      iskPerCubicMeter: iskPerCubicMeter,
      packagedVolumePerUnit: packagedVolume,
      warnings: warnings
    )
  }

  private static func reactionRow(
    definition: BlueprintDefinition,
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    packagedVolume: Double?,
    packagedVolumes: [Int64: Double],
    settings: ManufacturingOpportunitySettings,
    market: MarketOrderSnapshot,
    demandSummary: ManufacturingOpportunityDailyDemandSummary?,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) throws -> ManufacturingOpportunityRow? {
    guard
      let product = definition.activity.products.first(where: {
        $0.typeID == definition.productTypeID && $0.quantity > 0
      })
    else { return nil }
    let runs = settings.resolvedRuns(outputPerRun: product.quantity)
    guard runs > 0, let produced = multiplied(product.quantity, by: runs)
    else { return nil }
    guard
      let reaction = try ReactionProfitabilityAnalyzer.productionCostRow(
        definition: definition,
        typeNames: typeNames,
        classifications: classifications,
        runs: runs,
        market: market,
        adjustedPrices: adjustedPrices,
        facility: facility
      )
    else { return nil }

    let productOrders = (market.ordersByType[definition.productTypeID] ?? [])
      .filter {
        $0.locationID == market.locationID && $0.price.isFinite && $0.price > 0
          && $0.volumeRemaining > 0
      }
    var warnings = reaction.warnings
    if !productOrders.contains(where: { $0.side == .sell }) {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.product-sell-order-unavailable",
          message:
            "No active sell order is available for this reaction product at the exact Main Hub. Revenue and dependent profitability values remain unavailable.",
          severity: .blocking,
          source: market.source
        )
      )
    }
    if facility == nil {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.reaction-facility-unavailable",
          message:
            "The configured reaction facility or its reaction-system cost index is unavailable. Installation cost and dependent profitability values remain unavailable.",
          severity: .blocking,
          source: definition.source
        )
      )
    }
    let materials: [ManufacturingOpportunityMaterial] = reaction.inputs.compactMap {
      input -> ManufacturingOpportunityMaterial? in
      guard
        let base = definition.activity.materials.first(where: {
          $0.typeID == input.typeID
        })
      else { return nil }
      return ManufacturingOpportunityMaterial(
        typeID: input.typeID,
        name: input.name,
        baseQuantityPerRun: base.quantity,
        quantity: input.quantity,
        quote: input.quote,
        packagedVolumePerUnit: packagedVolumes[input.typeID]
      )
    }
    guard materials.count == definition.activity.materials.count else {
      return nil
    }
    let operatingCost = pairSum(reaction.materialCost, reaction.installationCost)
    let bestSell = productOrders.filter { $0.side == .sell }.map(\.price).min()
    let grossRevenue = bestSell.flatMap { safeProduct($0, Double(produced)) }
    let salesTax = fee(grossRevenue, rate: salesTaxRate)
    let brokerFee = fee(grossRevenue, rate: brokerFeeRate)
    let netRevenue: Double?
    if let grossRevenue, let salesTax, let brokerFee {
      netRevenue = safeDifference(grossRevenue, salesTax + brokerFee)
    } else {
      netRevenue = nil
    }
    let contribution = difference(netRevenue, operatingCost)
    let roi: Double?
    if let contribution, let operatingCost, operatingCost > 0 {
      roi = finite(contribution / operatingCost)
    } else {
      roi = nil
    }
    let iskPerHour = contribution.flatMap {
      reaction.durationSeconds > 0
        ? finite($0 / (Double(reaction.durationSeconds) / 3_600)) : nil
    }
    let totalVolume = packagedVolume.flatMap {
      $0 >= 0 ? safeProduct($0, Double(produced)) : nil
    }
    let iskPerCubicMeter = contribution.flatMap { profit in
      totalVolume.flatMap { $0 > 0 ? finite(profit / $0) : nil }
    }
    return ManufacturingOpportunityRow(
      blueprintTypeID: definition.blueprintTypeID,
      productTypeID: definition.productTypeID,
      productName: reaction.productName,
      categoryName: reaction.categoryName,
      groupName: reaction.groupName,
      activityKind: .reaction,
      metaGroupID: classifications[definition.productTypeID]?.metaGroupID,
      techLevel: classifications[definition.productTypeID]?.techLevel,
      facilityName: facility?.name,
      facilityMaterialMultiplier: facility?.materialMultiplier,
      facilityTimeMultiplier: facility?.timeMultiplier,
      activityDurationSecondsPerRun: definition.activity.durationSeconds,
      runs: runs,
      outputPerRun: product.quantity,
      producedQuantity: produced,
      materialEfficiency: 0,
      timeEfficiency: 0,
      durationSeconds: reaction.durationSeconds,
      observedDailyDemand: demandSummary?.currentUnits,
      previousDayDemand: demandSummary?.previousDayUnits,
      averageDailyDemand: demandSummary?.averageUnits,
      recordedDemandDayCount: demandSummary?.recordedDayCount ?? 0,
      demandChangeFromPreviousDayPercent:
        demandSummary?.changeFromPreviousDayPercent,
      activeBuyDemand: saturatedVolume(productOrders, side: .buy),
      activeSellSupply: saturatedVolume(productOrders, side: .sell),
      materials: materials,
      materialCost: reaction.materialCost,
      installationCost: reaction.installationCost,
      productionCostBeforeBlueprintAndLogistics: operatingCost,
      grossRevenue: grossRevenue,
      salesTax: salesTax,
      brokerFee: brokerFee,
      netRevenue: netRevenue,
      contributionProfit: contribution,
      returnOnInvestment: roi,
      iskPerHour: iskPerHour,
      iskPerCubicMeter: iskPerCubicMeter,
      packagedVolumePerUnit: packagedVolume,
      warnings: warnings
    )
  }

  private static func installation(
    definition: BlueprintDefinition,
    runs: Int,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ManufacturingOpportunityFacilityContext
  ) -> Double? {
    let values = [
      facility.materialMultiplier, facility.timeMultiplier,
      facility.jobCostMultiplier, facility.facilityTaxRate,
      facility.systemCostIndex, facility.sccSurchargeRate,
      facility.alphaSurchargeRate,
    ]
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 }),
      facility.materialMultiplier > 0, facility.timeMultiplier > 0,
      facility.jobCostMultiplier > 0
    else { return nil }
    var eiv = 0.0
    for material in definition.activity.materials {
      guard let price = adjustedPrices[material.typeID]?.adjustedPrice,
        price.isFinite, price >= 0,
        let quantity = multiplied(material.quantity, by: runs),
        let value = safeProduct(price, Double(quantity))
      else { return nil }
      eiv += value
      guard eiv.isFinite else { return nil }
    }
    let rate =
      facility.systemCostIndex * facility.jobCostMultiplier
      + facility.facilityTaxRate + facility.sccSurchargeRate
      + facility.alphaSurchargeRate
    return safeProduct(eiv, rate)
  }

  private static func durationSeconds(
    base: Int64,
    runs: Int,
    timeEfficiency: Int,
    multiplier: Double?
  ) -> Int64 {
    guard base > 0, runs > 0, let multiplier,
      multiplier.isFinite, multiplier > 0
    else { return 0 }
    let value =
      Double(base) * Double(runs) * multiplier
      * (1 - Double(timeEfficiency) / 100)
    guard value.isFinite, value > 0, value < Double(Int64.max) else {
      return 0
    }
    return Int64(ceil(value))
  }

  private static func saturatedVolume(
    _ orders: [MarketOrder], side: MarketOrderSide
  ) -> Int64 {
    orders.lazy.filter { $0.side == side }.reduce(0) { partial, order in
      let (sum, overflow) = partial.addingReportingOverflow(order.volumeRemaining)
      return overflow ? Int64.max : sum
    }
  }

  private static func multiplied(_ value: Int64, by multiplier: Int) -> Int64? {
    guard value > 0, multiplier > 0, let accepted = Int64(exactly: multiplier)
    else { return nil }
    let (result, overflow) = value.multipliedReportingOverflow(by: accepted)
    return overflow ? nil : result
  }

  private static func sum(_ values: [Double?]) -> Double? {
    var result = 0.0
    for value in values {
      guard let value, value.isFinite, value >= 0 else { return nil }
      result += value
      guard result.isFinite else { return nil }
    }
    return result
  }

  private static func pairSum(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs, let rhs else { return nil }
    let value = lhs + rhs
    return value.isFinite ? value : nil
  }

  private static func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs, let rhs else { return nil }
    return finite(lhs - rhs)
  }

  private static func safeDifference(_ lhs: Double, _ rhs: Double) -> Double? {
    finite(lhs - rhs)
  }

  private static func safeProduct(_ lhs: Double, _ rhs: Double) -> Double? {
    finite(lhs * rhs)
  }

  private static func fee(_ gross: Double?, rate: Double?) -> Double? {
    guard let gross, let rate, rate.isFinite, rate >= 0 else { return nil }
    return safeProduct(gross, rate)
  }

  private static func finite(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }
}

public enum ManufacturingOpportunityRunProjector {
  public static func project(
    _ row: ManufacturingOpportunityRow,
    requestedRuns: Int,
    materialEfficiency requestedME: Int? = nil,
    timeEfficiency requestedTE: Int? = nil
  ) -> ManufacturingOpportunityRow? {
    let materialEfficiency =
      row.supportsBlueprintEfficiency
      ? (requestedME ?? row.materialEfficiency) : 0
    let timeEfficiency =
      row.supportsBlueprintEfficiency
      ? (requestedTE ?? row.timeEfficiency) : 0
    guard row.runs > 0,
      (1...ManufacturingOpportunitySettings.maximumRequestedRuns).contains(
        requestedRuns
      ),
      (0...10).contains(materialEfficiency),
      (0...20).contains(timeEfficiency),
      let producedQuantity = multiplied(
        row.outputPerRun,
        by: requestedRuns
      ),
      let durationSeconds = projectedDuration(
        row,
        requestedRuns: requestedRuns,
        timeEfficiency: timeEfficiency
      )
    else { return nil }
    let scale = Double(requestedRuns) / Double(row.runs)
    guard scale.isFinite, scale > 0 else { return nil }
    let materials = row.materials.compactMap { material in
      projectedMaterial(
        material,
        row: row,
        requestedRuns: requestedRuns,
        materialEfficiency: materialEfficiency,
        scale: scale
      )
    }
    guard materials.count == row.materials.count else { return nil }
    let materialCost = sumProjected(materials.map(\.quote.total))
    let installationCost = scaledAmount(row.installationCost, by: scale)
    let productionCost = sumProjected([materialCost, installationCost])
    let grossRevenue = scaledAmount(row.grossRevenue, by: scale)
    let salesTax = scaledAmount(row.salesTax, by: scale)
    let brokerFee = scaledAmount(row.brokerFee, by: scale)
    let deductions = sumProjected([salesTax, brokerFee])
    let netRevenue = differenceProjected(grossRevenue, deductions)
    let contribution = differenceProjected(netRevenue, productionCost)
    let roi: Double?
    if let contribution, let productionCost, productionCost > 0 {
      roi = finiteProjected(contribution / productionCost)
    } else {
      roi = nil
    }
    let iskPerHour = contribution.flatMap {
      durationSeconds > 0
        ? finiteProjected($0 / (Double(durationSeconds) / 3_600)) : nil
    }
    let totalVolume = row.packagedVolumePerUnit.flatMap {
      finiteProjected($0 * Double(producedQuantity))
    }
    let iskPerCubicMeter = contribution.flatMap { profit in
      totalVolume.flatMap { $0 > 0 ? finiteProjected(profit / $0) : nil }
    }
    var warnings = row.warnings.filter {
      $0.code != "manufacturing-opportunity.run-projection"
    }
    if requestedRuns != row.runs
      || materialEfficiency != row.materialEfficiency
      || timeEfficiency != row.timeEfficiency
    {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.run-projection",
          message:
            "This item-only Runs/ME/TE scenario reuses the captured weighted Main Hub unit prices. It does not claim newly fetched market depth; run the full Main Hub update for a fresh depth snapshot.",
          severity: .information
        )
      )
    }
    if materialEfficiency != row.materialEfficiency,
      row.facilityMaterialMultiplier == nil
        || row.materials.contains(where: { $0.baseQuantityPerRun == nil })
    {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.efficiency-approximation",
          message:
            "This older saved scan does not contain every exact SDE rounding input. Update Main Hub Opportunities before treating the changed ME result as final.",
          severity: .warning
        )
      )
    }
    return ManufacturingOpportunityRow(
      blueprintTypeID: row.blueprintTypeID,
      productTypeID: row.productTypeID,
      productName: row.productName,
      categoryName: row.categoryName,
      groupName: row.groupName,
      activityKind: row.activityKind,
      metaGroupID: row.metaGroupID,
      techLevel: row.techLevel,
      facilityName: row.facilityName,
      facilityMaterialMultiplier: row.facilityMaterialMultiplier,
      facilityTimeMultiplier: row.facilityTimeMultiplier,
      activityDurationSecondsPerRun: row.activityDurationSecondsPerRun,
      runs: requestedRuns,
      outputPerRun: row.outputPerRun,
      producedQuantity: producedQuantity,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency,
      durationSeconds: durationSeconds,
      observedDailyDemand: row.observedDailyDemand,
      previousDayDemand: row.previousDayDemand,
      averageDailyDemand: row.averageDailyDemand,
      recordedDemandDayCount: row.recordedDemandDayCount,
      demandChangeFromPreviousDayPercent: row.demandChangeFromPreviousDayPercent,
      activeBuyDemand: row.activeBuyDemand,
      activeSellSupply: row.activeSellSupply,
      materials: materials,
      materialCost: materialCost,
      installationCost: installationCost,
      productionCostBeforeBlueprintAndLogistics: productionCost,
      grossRevenue: grossRevenue,
      salesTax: salesTax,
      brokerFee: brokerFee,
      netRevenue: netRevenue,
      contributionProfit: contribution,
      returnOnInvestment: roi,
      iskPerHour: iskPerHour,
      iskPerCubicMeter: iskPerCubicMeter,
      packagedVolumePerUnit: row.packagedVolumePerUnit,
      warnings: warnings
    )
  }

  private static func projectedMaterial(
    _ material: ManufacturingOpportunityMaterial,
    row: ManufacturingOpportunityRow,
    requestedRuns: Int,
    materialEfficiency: Int,
    scale: Double
  ) -> ManufacturingOpportunityMaterial? {
    let quantity: Int64
    let usedApproximation: Bool
    if row.effectiveActivityKind == .reaction,
      let baseQuantity = material.baseQuantityPerRun,
      let facilityMultiplier = row.facilityMaterialMultiplier,
      baseQuantity > 0,
      facilityMultiplier.isFinite,
      facilityMultiplier > 0,
      let rawQuantity = multiplied(baseQuantity, by: requestedRuns)
    {
      let value = Double(rawQuantity) * facilityMultiplier
      guard value.isFinite, value > 0, value < Double(Int64.max) else {
        return nil
      }
      quantity = max(Int64(requestedRuns), Int64(ceil(value)))
      usedApproximation = false
    } else if let baseQuantity = material.baseQuantityPerRun,
      let facilityMultiplier = row.facilityMaterialMultiplier,
      baseQuantity > 0,
      facilityMultiplier.isFinite,
      facilityMultiplier > 0
    {
      quantity = IndustryPlanner.manufacturingMaterialQuantity(
        baseQuantity: baseQuantity,
        runs: requestedRuns,
        materialEfficiency: materialEfficiency,
        facilityMultiplier: facilityMultiplier
      )
      usedApproximation = false
    } else if materialEfficiency == row.materialEfficiency,
      let scaled = scaledInteger(
        material.quantity,
        fromRuns: row.runs,
        toRuns: requestedRuns
      )
    {
      quantity = scaled
      usedApproximation = false
    } else {
      let oldFactor = 1 - Double(row.materialEfficiency) / 100
      let newFactor = 1 - Double(materialEfficiency) / 100
      guard oldFactor > 0,
        let scaledRuns = scaledInteger(
          material.quantity,
          fromRuns: row.runs,
          toRuns: requestedRuns
        ),
        let approximated = finiteProjected(
          Double(scaledRuns) * newFactor / oldFactor
        ),
        approximated > 0,
        approximated < Double(Int64.max)
      else { return nil }
      quantity = Int64(ceil(approximated))
      usedApproximation = true
    }
    var warnings = material.quote.warnings.filter {
      $0.code != "manufacturing-opportunity.run-projection"
        && $0.code != "manufacturing-opportunity.efficiency-approximation"
    }
    if row.runs != requestedRuns {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.run-projection",
          message:
            "The run-specific estimate reuses this quote's captured weighted unit price; additional market depth was not fetched.",
          severity: .information,
          source: material.quote.source
        )
      )
    }
    if usedApproximation {
      warnings.append(
        DomainWarning(
          code: "manufacturing-opportunity.efficiency-approximation",
          message:
            "This older saved scan has no published base material quantity. The changed ME quantity is an explicitly marked approximation; update Main Hub Opportunities for exact SDE rounding.",
          severity: .warning,
          source: material.quote.source
        )
      )
    }
    let total =
      material.quote.weightedUnitPrice.flatMap {
        finiteProjected($0 * Double(quantity))
      } ?? scaledAmount(material.quote.total, by: scale)
    let quote = PriceQuote(
      id: UUID(),
      typeID: material.quote.typeID,
      quantity: quantity,
      scenario: material.quote.scenario,
      total: total,
      weightedUnitPrice: material.quote.weightedUnitPrice,
      filledQuantity: total == nil ? 0 : quantity,
      capturedAt: material.quote.capturedAt,
      source: material.quote.source,
      warnings: warnings
    )
    return ManufacturingOpportunityMaterial(
      typeID: material.typeID,
      name: material.name,
      baseQuantityPerRun: material.baseQuantityPerRun,
      quantity: quantity,
      quote: quote,
      packagedVolumePerUnit: material.packagedVolumePerUnit
    )
  }

  private static func projectedDuration(
    _ row: ManufacturingOpportunityRow,
    requestedRuns: Int,
    timeEfficiency: Int
  ) -> Int64? {
    if let base = row.activityDurationSecondsPerRun,
      let multiplier = row.facilityTimeMultiplier,
      base > 0,
      multiplier.isFinite,
      multiplier > 0
    {
      let efficiencyMultiplier =
        row.supportsBlueprintEfficiency
        ? (1 - Double(timeEfficiency) / 100) : 1
      let value =
        Double(base) * Double(requestedRuns) * multiplier
        * efficiencyMultiplier
      guard value.isFinite, value > 0, value < Double(Int64.max) else {
        return nil
      }
      return Int64(ceil(value))
    }
    if timeEfficiency == row.timeEfficiency {
      return scaledInteger(
        row.durationSeconds,
        fromRuns: row.runs,
        toRuns: requestedRuns
      )
    }
    let oldFactor = 1 - Double(row.timeEfficiency) / 100
    let newFactor = 1 - Double(timeEfficiency) / 100
    guard oldFactor > 0,
      let scaledRuns = scaledInteger(
        row.durationSeconds,
        fromRuns: row.runs,
        toRuns: requestedRuns
      ),
      let value = finiteProjected(Double(scaledRuns) * newFactor / oldFactor),
      value >= 0,
      value < Double(Int64.max)
    else { return nil }
    return Int64(ceil(value))
  }

  private static func multiplied(_ value: Int64, by multiplier: Int) -> Int64? {
    let (result, overflow) = value.multipliedReportingOverflow(
      by: Int64(multiplier)
    )
    return overflow || result <= 0 ? nil : result
  }

  private static func scaledInteger(
    _ value: Int64,
    fromRuns: Int,
    toRuns: Int
  ) -> Int64? {
    guard value >= 0, fromRuns > 0, toRuns > 0 else { return nil }
    let (product, overflow) = value.multipliedReportingOverflow(
      by: Int64(toRuns)
    )
    guard !overflow else { return nil }
    let divisor = Int64(fromRuns)
    let quotient = product / divisor
    return product % divisor == 0 ? quotient : quotient + 1
  }

  private static func scaledAmount(_ value: Double?, by scale: Double) -> Double? {
    guard let value else { return nil }
    return finiteProjected(value * scale)
  }

  private static func sumProjected(_ values: [Double?]) -> Double? {
    var total = 0.0
    for value in values {
      guard let value, value.isFinite, value >= 0 else { return nil }
      total += value
      guard total.isFinite else { return nil }
    }
    return total
  }

  private static func differenceProjected(
    _ lhs: Double?,
    _ rhs: Double?
  ) -> Double? {
    guard let lhs, let rhs else { return nil }
    return finiteProjected(lhs - rhs)
  }

  private static func finiteProjected(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }
}

public enum ManufacturingOpportunityScenarioProjector {
  /// Profit that the selected run batch can realize against observed exact-hub
  /// daily demand. Demand below the produced quantity reduces the potential;
  /// demand at or above the batch quantity cannot exceed the batch profit.
  public static func dailyProfitPotential(
    for row: ManufacturingOpportunityRow,
    costs: ManufacturingOpportunityCostProjection
  ) -> Double? {
    guard let demand = row.observedDailyDemand,
      demand >= 0,
      row.producedQuantity > 0,
      let profit = costs.profit,
      profit.isFinite
    else { return nil }
    let unitProfit = profit / Double(row.producedQuantity)
    let sellableUnits = min(row.producedQuantity, demand)
    return finite(unitProfit * Double(sellableUnits))
  }

  public static func estimatedSellThroughDays(
    for row: ManufacturingOpportunityRow
  ) -> Double? {
    guard let demand = row.observedDailyDemand, demand > 0,
      row.producedQuantity > 0
    else { return nil }
    return finite(Double(row.producedQuantity) / Double(demand))
  }

  public static func costs(
    for row: ManufacturingOpportunityRow,
    sheet: ManufacturingOpportunityCostSheet
  ) -> ManufacturingOpportunityCostProjection {
    let manualHauling = selected(
      sheet.includesHauling,
      value: sheet.haulingCostPerBatch
    )
    return costs(for: row, sheet: sheet, logisticsCost: manualHauling)
  }

  public static func costs(
    for row: ManufacturingOpportunityRow,
    sheet: ManufacturingOpportunityCostSheet,
    logistics: ManufacturingOpportunityLogisticsProjection
  ) -> ManufacturingOpportunityCostProjection {
    costs(for: row, sheet: sheet, logisticsCost: logistics.cost)
  }

  public static func logistics(
    for row: ManufacturingOpportunityRow,
    procurement: ManufacturingOpportunityProcurementProjection,
    configuration: LogisticsConfiguration?,
    mainHub: ProcurementLocation,
    warehouseIsAvailable: Bool
  ) -> ManufacturingOpportunityLogisticsProjection {
    guard let configuration else {
      return ManufacturingOpportunityLogisticsProjection(
        cost: nil,
        legs: [],
        warnings: [
          DomainWarning(
            code: "manufacturing-opportunity.logistics-snapshot-missing",
            message:
              "The saved opportunity scan has no logistics configuration. Update the scan before using profit, ROI or ISK rates.",
            severity: .blocking
          )
        ]
      )
    }
    let homeHub = configuration.homeTradeHub
    let configuredProductionLocation = configuration.productionLocationName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let productionLocation =
      configuredProductionLocation.isEmpty
      ? homeHub.name : configuredProductionLocation
    let productionIsMainHub =
      productionLocation.compare(
        mainHub.name,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) == .orderedSame
      || configuredProductionLocation.isEmpty
        && mainHub.representsSameLocation(as: homeHub)
    if productionIsMainHub {
      return ManufacturingOpportunityLogisticsProjection(
        cost: 0,
        legs: [],
        warnings: []
      )
    }
    guard configuration.isEnabled else {
      return unavailableLogistics(
        code: "manufacturing-opportunity.round-trip-logistics-disabled",
        message:
          "The Main Hub and Home Hub differ, but Profile logistics is disabled. Round-trip logistics and profit remain unavailable instead of being treated as zero."
      )
    }
    guard let rate = configuration.effectiveISKPerCubicMeter else {
      return unavailableLogistics(
        code: "logistics.missing-volume-rate",
        message:
          "Logistics is enabled in Profile, but the ISK per m³ rate is missing or invalid."
      )
    }
    guard let maximumVolume = configuration.effectiveMaximumContractVolumeM3
    else {
      return unavailableLogistics(
        code: "logistics.invalid-volume-limit",
        message:
          "Logistics is enabled in Profile, but the contract volume limit is invalid."
      )
    }

    var legs: [LogisticsCostLeg] = []
    var warnings: [DomainWarning] = []
    guard warehouseIsAvailable else {
      return unavailableLogistics(
        code: "manufacturing-opportunity.production-warehouse-unavailable",
        message:
          "The production warehouse snapshot is unavailable, so the quantity that must be hauled from the Main Hub cannot be determined."
      )
    }
    let sourcingByTypeID = procurement.lines.reduce(
      into: [Int64: ManufacturingOpportunitySourcingLine]()
    ) { result, line in
      result[line.typeID] = line
    }
    let cargo = row.materials.compactMap {
      material -> LogisticsCargoItem? in
      guard let sourcing = sourcingByTypeID[material.typeID],
        sourcing.toBuy > 0
      else {
        return nil
      }
      return LogisticsCargoItem(
        typeID: material.typeID,
        quantity: sourcing.toBuy,
        collateral: sourcing.purchaseCashRequirement,
        packagedVolumePerUnit: material.packagedVolumePerUnit
      )
    }
    let inbound = LogisticsCostCalculator.calculateLegs(
      kind: .inboundMaterials,
      origin: mainHub.name,
      destination: productionLocation,
      cargo: cargo,
      iskPerCubicMeter: rate,
      maximumContractVolumeM3: maximumVolume
    )
    legs.append(contentsOf: inbound.legs)
    warnings.append(contentsOf: inbound.warnings)
    let outbound = LogisticsCostCalculator.calculateLegs(
      kind: .outboundProducts,
      origin: productionLocation,
      destination: mainHub.name,
      cargo: [
        LogisticsCargoItem(
          typeID: row.productTypeID,
          quantity: row.producedQuantity,
          collateral: row.grossRevenue,
          packagedVolumePerUnit: row.packagedVolumePerUnit
        )
      ],
      iskPerCubicMeter: rate,
      maximumContractVolumeM3: maximumVolume
    )
    legs.append(contentsOf: outbound.legs)
    warnings.append(contentsOf: outbound.warnings)
    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return ManufacturingOpportunityLogisticsProjection(
        cost: nil,
        legs: [],
        warnings: warnings
      )
    }
    let total = legs.reduce(0) { $0 + $1.roundedCharge }
    guard total.isFinite, total >= 0 else {
      return unavailableLogistics(
        code: "logistics.invalid-total",
        message: "The logistics total exceeded safe numeric limits."
      )
    }
    return ManufacturingOpportunityLogisticsProjection(
      cost: total,
      legs: legs,
      warnings: warnings
    )
  }

  private static func costs(
    for row: ManufacturingOpportunityRow,
    sheet: ManufacturingOpportunityCostSheet,
    logisticsCost: Double?
  ) -> ManufacturingOpportunityCostProjection {
    let installation = selected(
      sheet.includesInstallation,
      value: row.installationCost
    )
    let blueprintAllocation: Double? =
      row.supportsBlueprintEfficiency
      ? selectedProduct(
        sheet.includesBlueprintAllocation,
        value: sheet.blueprintAllocationPerRun,
        multiplier: Double(row.runs)
      ) : 0
    let totalCost = sum([
      row.materialCost,
      installation,
      blueprintAllocation,
      logisticsCost,
    ])
    let salesTax = selected(sheet.includesSalesTax, value: row.salesTax)
    let brokerFee = selected(sheet.includesBrokerFee, value: row.brokerFee)
    let deductions = sum([salesTax, brokerFee])
    let netRevenue = difference(row.grossRevenue, deductions)
    let profit = difference(netRevenue, totalCost)
    let roi: Double?
    if let profit, let totalCost, totalCost > 0 {
      roi = finite(profit / totalCost)
    } else {
      roi = nil
    }
    let iskPerHour = profit.flatMap {
      row.durationSeconds > 0
        ? finite($0 / (Double(row.durationSeconds) / 3_600)) : nil
    }
    let totalVolume = row.packagedVolumePerUnit.flatMap {
      finite($0 * Double(row.producedQuantity))
    }
    let iskPerCubicMeter = profit.flatMap { acceptedProfit in
      totalVolume.flatMap {
        $0 > 0 ? finite(acceptedProfit / $0) : nil
      }
    }
    return ManufacturingOpportunityCostProjection(
      materialCost: row.materialCost,
      installationCost: installation,
      blueprintAllocation: blueprintAllocation,
      logisticsCost: logisticsCost,
      totalCost: totalCost,
      grossRevenue: row.grossRevenue,
      salesTax: salesTax,
      brokerFee: brokerFee,
      netRevenue: netRevenue,
      profit: profit,
      returnOnInvestment: roi,
      iskPerHour: iskPerHour,
      iskPerCubicMeter: iskPerCubicMeter
    )
  }

  private static func unavailableLogistics(
    code: String,
    message: String
  ) -> ManufacturingOpportunityLogisticsProjection {
    ManufacturingOpportunityLogisticsProjection(
      cost: nil,
      legs: [],
      warnings: [
        DomainWarning(code: code, message: message, severity: .blocking)
      ]
    )
  }

  public static func procurement(
    for row: ManufacturingOpportunityRow,
    factualWarehouseQuantities: [Int64: Int64],
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64]
  ) -> ManufacturingOpportunityProcurementProjection {
    let lines = row.materials.map { material in
      sourcingLine(
        material,
        factualQuantity: factualWarehouseQuantities[material.typeID, default: 0],
        protectedQuantity: protectedQuantities[material.typeID, default: 0],
        reservedQuantity: reservedQuantities[material.typeID, default: 0]
      )
    }
    return ManufacturingOpportunityProcurementProjection(
      lines: lines,
      warehouseReplacementValue: sum(
        lines.map(\.warehouseReplacementValue)
      ),
      purchaseCashRequirement: sum(
        lines.map(\.purchaseCashRequirement)
      )
    )
  }

  /// Computes only the wallet cash needed for the factual material shortfall.
  /// This is the allocation-equivalent fast path for screening large candidate
  /// sets where constructing every detailed sourcing line would be wasteful.
  public static func purchaseCashRequirement(
    for row: ManufacturingOpportunityRow,
    factualWarehouseQuantities: [Int64: Int64],
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64]
  ) -> Double? {
    var total = 0.0
    for material in row.materials {
      let factual = max(
        0,
        factualWarehouseQuantities[material.typeID, default: 0]
      )
      let protected = min(
        factual,
        max(0, protectedQuantities[material.typeID, default: 0])
      )
      let afterProtection = factual - protected
      let reserved = min(
        afterProtection,
        max(0, reservedQuantities[material.typeID, default: 0])
      )
      let usable = afterProtection - reserved
      let toBuy = material.quantity - min(material.quantity, usable)
      guard toBuy > 0 else { continue }
      guard material.quote.isComplete,
        let unitPrice = material.quote.weightedUnitPrice,
        unitPrice.isFinite,
        unitPrice >= 0
      else { return nil }
      total += unitPrice * Double(toBuy)
      guard total.isFinite else { return nil }
    }
    return total
  }

  private static func sourcingLine(
    _ material: ManufacturingOpportunityMaterial,
    factualQuantity: Int64,
    protectedQuantity: Int64,
    reservedQuantity: Int64
  ) -> ManufacturingOpportunitySourcingLine {
    let factual = max(0, factualQuantity)
    let protected = min(factual, max(0, protectedQuantity))
    let afterProtection = factual - protected
    let reserved = min(afterProtection, max(0, reservedQuantity))
    let usable = afterProtection - reserved
    let fromWarehouse = min(material.quantity, usable)
    let toBuy = material.quantity - fromWarehouse
    let complete = material.quote.isComplete
    let unitPrice = complete ? material.quote.weightedUnitPrice : nil
    let stockValue = allocatedValue(
      quantity: fromWarehouse,
      unitPrice: unitPrice
    )
    let purchaseCash = allocatedValue(
      quantity: toBuy,
      unitPrice: unitPrice
    )
    return ManufacturingOpportunitySourcingLine(
      typeID: material.typeID,
      name: material.name,
      requiredQuantity: material.quantity,
      factualWarehouseQuantity: factual,
      protectedQuantity: protected,
      reservedQuantity: reserved,
      usableWarehouseQuantity: usable,
      fromWarehouse: fromWarehouse,
      toBuy: toBuy,
      marketFilledQuantity: material.quote.filledQuantity,
      weightedUnitPrice: unitPrice,
      warehouseReplacementValue: stockValue,
      purchaseCashRequirement: purchaseCash,
      hasCompleteMarketCoverage: complete
    )
  }

  private static func selected(_ isIncluded: Bool, value: Double?) -> Double? {
    guard isIncluded else { return 0 }
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func selectedProduct(
    _ isIncluded: Bool,
    value: Double?,
    multiplier: Double
  ) -> Double? {
    guard isIncluded else { return 0 }
    guard let value, value.isFinite, value >= 0,
      multiplier.isFinite, multiplier >= 0
    else { return nil }
    return finite(value * multiplier)
  }

  private static func allocatedValue(
    quantity: Int64,
    unitPrice: Double?
  ) -> Double? {
    guard quantity > 0 else { return 0 }
    guard let unitPrice, unitPrice.isFinite, unitPrice >= 0 else { return nil }
    return finite(unitPrice * Double(quantity))
  }

  private static func sum(_ values: [Double?]) -> Double? {
    var result = 0.0
    for value in values {
      guard let value, value.isFinite, value >= 0 else { return nil }
      result += value
      guard result.isFinite else { return nil }
    }
    return result
  }

  private static func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs, let rhs else { return nil }
    return finite(lhs - rhs)
  }

  private static func finite(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }
}

/// Applies an optional wallet-facing ceiling to the factual material shortfall.
/// Stock already present in the production Warehouse retains its replacement
/// value in profit, but it does not consume new wallet cash and is therefore not
/// counted here.
public enum ManufacturingOpportunityBudgetFilter {
  public static func accepts(
    maximumMaterialPurchaseISK: Double?,
    purchaseCashRequirement: Double?
  ) -> Bool {
    guard let maximumMaterialPurchaseISK else { return true }
    guard maximumMaterialPurchaseISK.isFinite,
      maximumMaterialPurchaseISK >= 0,
      let purchaseCashRequirement,
      purchaseCashRequirement.isFinite,
      purchaseCashRequirement >= 0
    else { return false }
    return purchaseCashRequirement <= maximumMaterialPurchaseISK
  }
}

/// Applies the optional quick filter to the factual multi-day demand average.
/// Zero disables the filter so unavailable averages remain visible. A
/// positive threshold requires a known average and never treats unavailable
/// demand as zero.
public enum ManufacturingOpportunityAverageDemandFilter {
  public static func accepts(
    minimumAverageDailyDemand: Int64,
    averageDailyDemand: Int64?
  ) -> Bool {
    guard minimumAverageDailyDemand > 0 else { return true }
    guard let averageDailyDemand else { return false }
    return averageDailyDemand >= minimumAverageDailyDemand
  }
}

public struct ManufacturingOpportunityScreeningCandidate: Sendable {
  public let row: ManufacturingOpportunityRow
  public let purchaseCashRequirement: Double?

  public init(
    row: ManufacturingOpportunityRow,
    purchaseCashRequirement: Double?
  ) {
    self.row = row
    self.purchaseCashRequirement = purchaseCashRequirement
  }
}

/// Produces the complete ranked Main-Hub screening used by the experimental
/// workflow. Presentation decides how many rows are visible at once; this
/// domain projection deliberately has no arbitrary top-N cutoff.
public enum ManufacturingOpportunityScreening {
  public static func candidates(
    snapshot: ManufacturingOpportunitySnapshot,
    query: String,
    factualWarehouseQuantities: [Int64: Int64],
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64],
    maximumMaterialPurchaseISK: Double?,
    productFamilies: Set<ManufacturingOpportunityProductFamily> = Set(
      ManufacturingOpportunityProductFamily.allCases
    ),
    productionClasses: Set<ManufacturingOpportunityProductionClass> = Set(
      ManufacturingOpportunityProductionClass.allCases
    ),
    selectedCategory: String = "",
    selectedGroup: String = "",
    loyaltyStoreBlueprintsOnly: Bool = false,
    loyaltyStoreBlueprintTypeIDs: Set<Int64> = []
  ) -> [ManufacturingOpportunityScreeningCandidate] {
    let acceptedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return snapshot.rows.compactMap { row in
      guard
        acceptedQuery.isEmpty
          || row.productName.localizedCaseInsensitiveContains(acceptedQuery)
          || row.groupName.localizedCaseInsensitiveContains(acceptedQuery)
          || row.categoryName.localizedCaseInsensitiveContains(acceptedQuery)
      else { return nil }
      guard
        ManufacturingOpportunityCatalogFilter.accepts(
          activityKind: row.effectiveActivityKind,
          categoryName: row.categoryName,
          groupName: row.groupName,
          metaGroupID: row.metaGroupID,
          techLevel: row.techLevel,
          productFamilies: productFamilies,
          productionClasses: productionClasses
        ),
        selectedCategory.isEmpty || row.categoryName == selectedCategory,
        selectedGroup.isEmpty || row.groupName == selectedGroup,
        !loyaltyStoreBlueprintsOnly
          || loyaltyStoreBlueprintTypeIDs.contains(row.blueprintTypeID)
      else { return nil }
      let purchaseCashRequirement: Double?
      if maximumMaterialPurchaseISK == nil {
        // Preserve the previous inexpensive screening path when no wallet
        // ceiling is active. Exact procurement is still calculated after a
        // product is selected.
        purchaseCashRequirement = nil
      } else {
        purchaseCashRequirement =
          ManufacturingOpportunityScenarioProjector
          .purchaseCashRequirement(
            for: row,
            factualWarehouseQuantities: factualWarehouseQuantities,
            protectedQuantities: protectedQuantities,
            reservedQuantities: reservedQuantities
          )
      }
      guard
        ManufacturingOpportunityBudgetFilter.accepts(
          maximumMaterialPurchaseISK: maximumMaterialPurchaseISK,
          purchaseCashRequirement: purchaseCashRequirement
        )
      else { return nil }
      return ManufacturingOpportunityScreeningCandidate(
        row: row,
        purchaseCashRequirement: purchaseCashRequirement
      )
    }.sorted { lhs, rhs in
      orderedBefore(lhs.row, rhs.row)
    }
  }

  private static func orderedBefore(
    _ lhs: ManufacturingOpportunityRow,
    _ rhs: ManufacturingOpportunityRow
  ) -> Bool {
    switch (lhs.contributionProfit, rhs.contributionProfit) {
    case (.some(let left), .some(let right)) where left != right:
      return left > right
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    default:
      let order = lhs.productName.localizedCaseInsensitiveCompare(
        rhs.productName
      )
      return order == .orderedSame
        ? lhs.productTypeID < rhs.productTypeID : order == .orderedAscending
    }
  }
}
