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
  public var targetQuantity: Int64
  public var materialEfficiency: Int
  public var timeEfficiency: Int

  public init(
    targetQuantity: Int64 = 1,
    materialEfficiency: Int = 10,
    timeEfficiency: Int = 20
  ) {
    self.targetQuantity = max(1, targetQuantity)
    self.materialEfficiency = min(10, max(0, materialEfficiency))
    self.timeEfficiency = min(20, max(0, timeEfficiency))
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
        Int64(lhs.materialEfficiency),
        Int64(rhs.materialEfficiency),
        lhs,
        rhs
      )
    case .timeEfficiency:
      return compare(
        Int64(lhs.timeEfficiency),
        Int64(rhs.timeEfficiency),
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
    case (_?, nil): return true
    case (nil, _?): return false
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
    case (_?, nil): return true
    case (nil, _?): return false
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
    lhs.productName.localizedCaseInsensitiveCompare(rhs.productName)
      == .orderedAscending
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
  public let facilityName: String?
  public let runs: Int
  public let outputPerRun: Int64
  public let producedQuantity: Int64
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let durationSeconds: Int64
  public let observedDailyDemand: Int64?
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

public struct ManufacturingOpportunityDemandSnapshot: Codable, Equatable,
  Sendable
{
  public static let methodVersion = "exact-hub-surviving-order-depletion-v1"

  public let regionID: Int64
  public let locationID: Int64
  public let utcDay: Date
  public let firstObservedAt: Date
  public let lastObservedAt: Date
  public let sampleCount: Int
  public let comparedOrderCount: Int
  public let decreasedOrderCount: Int
  public let observedUnitsByType: [Int64: Int64]
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
    observedUnitsByType: [Int64: Int64],
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
    self.observedUnitsByType = observedUnitsByType
    self.source = source
  }

  public func observedUnits(for typeID: Int64) -> Int64? {
    guard sampleCount >= 2 else { return nil }
    return observedUnitsByType[typeID, default: 0]
  }
}

public struct ManufacturingOpportunityDemandLedger: Codable, Equatable,
  Sendable
{
  public static let schemaVersion = 1

  private struct OrderBaseline: Codable, Equatable, Sendable {
    let typeID: Int64
    let locationID: Int64
    let side: MarketOrderSide
    let volumeRemaining: Int64
  }

  public let version: Int
  public private(set) var demand: ManufacturingOpportunityDemandSnapshot?
  private var previousOrdersByID: [Int64: OrderBaseline]
  private var previousSourceSnapshotID: UUID?

  public init() {
    version = Self.schemaVersion
    demand = nil
    previousOrdersByID = [:]
    previousSourceSnapshotID = nil
  }

  @discardableResult
  public mutating func observe(
    _ market: MarketOrderSnapshot
  ) -> ManufacturingOpportunityDemandSnapshot {
    let utcDay = Self.utcDay(containing: market.capturedAt)
    let currentOrders = Self.validOrders(in: market)
    let mustReset =
      demand.map {
        $0.regionID != market.regionID
          || $0.locationID != market.locationID
          || $0.utcDay != utcDay
      } ?? true

    if mustReset {
      let initial = ManufacturingOpportunityDemandSnapshot(
        regionID: market.regionID,
        locationID: market.locationID,
        utcDay: utcDay,
        firstObservedAt: market.capturedAt,
        lastObservedAt: market.capturedAt,
        sampleCount: 1,
        comparedOrderCount: 0,
        decreasedOrderCount: 0,
        observedUnitsByType: [:],
        source: market.source
      )
      demand = initial
      previousOrdersByID = currentOrders
      previousSourceSnapshotID = market.source.snapshotID
      return initial
    }

    if previousSourceSnapshotID == market.source.snapshotID,
      let demand
    {
      return demand
    }

    var volumes = demand?.observedUnitsByType ?? [:]
    var compared = demand?.comparedOrderCount ?? 0
    var decreased = demand?.decreasedOrderCount ?? 0
    for (orderID, current) in currentOrders {
      guard let previous = previousOrdersByID[orderID],
        previous.typeID == current.typeID,
        previous.locationID == current.locationID,
        previous.side == current.side
      else { continue }
      compared = Self.saturatedAdd(compared, 1)
      guard current.volumeRemaining < previous.volumeRemaining else {
        continue
      }
      decreased = Self.saturatedAdd(decreased, 1)
      let delta = previous.volumeRemaining - current.volumeRemaining
      volumes[current.typeID] = Self.saturatedAdd(
        volumes[current.typeID, default: 0],
        delta
      )
    }

    let updated = ManufacturingOpportunityDemandSnapshot(
      regionID: market.regionID,
      locationID: market.locationID,
      utcDay: utcDay,
      firstObservedAt: demand?.firstObservedAt ?? market.capturedAt,
      lastObservedAt: market.capturedAt,
      sampleCount: Self.saturatedAdd(demand?.sampleCount ?? 1, 1),
      comparedOrderCount: compared,
      decreasedOrderCount: decreased,
      observedUnitsByType: volumes,
      source: market.source
    )
    demand = updated
    previousOrdersByID = currentOrders
    previousSourceSnapshotID = market.source.snapshotID
    return updated
  }

  private static func validOrders(
    in market: MarketOrderSnapshot
  ) -> [Int64: OrderBaseline] {
    var result: [Int64: OrderBaseline] = [:]
    for order in market.ordersByType.values.joined()
    where order.locationID == market.locationID
      && order.price.isFinite
      && order.price > 0
      && order.volumeRemaining > 0
    {
      result[order.id] = OrderBaseline(
        typeID: order.typeID,
        locationID: order.locationID,
        side: order.side,
        volumeRemaining: order.volumeRemaining
      )
    }
    return result
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
  public let mainHubActiveOrderTypeCount: Int
  public let candidateCount: Int
  public let candidatesWithSellOrders: Int
  public let candidatesWithBuyOrders: Int

  public init(
    completeManufacturingDefinitionCount: Int,
    mainHubActiveOrderTypeCount: Int,
    candidateCount: Int,
    candidatesWithSellOrders: Int,
    candidatesWithBuyOrders: Int
  ) {
    self.completeManufacturingDefinitionCount =
      completeManufacturingDefinitionCount
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
  private var cachedSnapshot: ManufacturingOpportunitySnapshot?

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> ManufacturingOpportunitySnapshot? {
    try loadExistingIfNeeded()
    return cachedSnapshot
  }

  public func save(_ snapshot: ManufacturingOpportunitySnapshot) throws {
    try loadExistingIfNeeded()
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
  }

  private func loadExistingIfNeeded() throws {
    guard !hasLoaded else { return }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      hasLoaded = true
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
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) throws -> ManufacturingOpportunitySnapshot {
    guard settings.targetQuantity > 0,
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
    guard let sdeSource = manufacturing.first?.source else {
      throw ManufacturingOpportunityError.noManufacturingDefinitions
    }

    var rows: [ManufacturingOpportunityRow] = []
    rows.reserveCapacity(manufacturing.count)
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
        observedDailyDemand: demand?.observedUnits(
          for: definition.productTypeID
        ),
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
    rows.sort {
      $0.productName.localizedCaseInsensitiveCompare($1.productName)
        == .orderedAscending
    }
    var warnings = [
      DomainWarning(
        code: "manufacturing-opportunity.blueprint-cost-scope",
        message:
          "Blueprint acquisition or allocation remains excluded until an explicit amount is entered in the Cost Sheet. Logistics, installation, sales tax and broker fee use the saved Profile configuration automatically.",
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
    if let demand, demand.sampleCount >= 2 {
      warnings.insert(
        DomainWarning(
          code: "manufacturing-opportunity.observed-demand-lower-bound",
          message:
            "Demand today is a lower-bound observation at the exact Main Hub. It counts volume decreases only for order IDs present in two consecutive snapshots; disappeared, expired or cancelled orders are not guessed.",
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
            "Demand today is unavailable until two different exact Main Hub snapshots have been captured on the same UTC day.",
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
      demand: demand,
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
    observedDailyDemand: Int64?,
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
    guard !productOrders.isEmpty,
      let product = definition.activity.products.first(where: {
        $0.typeID == definition.productTypeID && $0.quantity > 0
      })
    else { return nil }
    let target = min(settings.targetQuantity, Int64(Int.max))
    let runs = IndustryPlanner.runsRequired(
      wantedQuantity: Int(target),
      outputPerRun: product.quantity
    )
    guard runs > 0, let produced = multiplied(product.quantity, by: runs)
    else { return nil }

    var warnings: [DomainWarning] = []
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
      facilityName: facility?.name,
      runs: runs,
      outputPerRun: product.quantity,
      producedQuantity: produced,
      materialEfficiency: settings.materialEfficiency,
      timeEfficiency: settings.timeEfficiency,
      durationSeconds: duration,
      observedDailyDemand: observedDailyDemand,
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

public enum ManufacturingOpportunityScenarioProjector {
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
    guard configuration.isEnabled else {
      return ManufacturingOpportunityLogisticsProjection(
        cost: 0,
        legs: [],
        warnings: []
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

    let productionLocation =
      row.facilityName ?? configuration.productionLocationName
    var legs: [LogisticsCostLeg] = []
    var warnings: [DomainWarning] = []
    if configuration.includeInboundMaterials
      && mainHub.name != productionLocation
    {
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
      let result = LogisticsCostCalculator.calculateLegs(
        kind: .inboundMaterials,
        origin: mainHub.name,
        destination: productionLocation,
        cargo: cargo,
        iskPerCubicMeter: rate,
        maximumContractVolumeM3: maximumVolume
      )
      legs.append(contentsOf: result.legs)
      warnings.append(contentsOf: result.warnings)
    }
    if configuration.includeOutboundProducts
      && productionLocation != mainHub.name
    {
      let result = LogisticsCostCalculator.calculateLegs(
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
      legs.append(contentsOf: result.legs)
      warnings.append(contentsOf: result.warnings)
    }
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
    let blueprintAllocation = selectedProduct(
      sheet.includesBlueprintAllocation,
      value: sheet.blueprintAllocationPerRun,
      multiplier: Double(row.runs)
    )
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
