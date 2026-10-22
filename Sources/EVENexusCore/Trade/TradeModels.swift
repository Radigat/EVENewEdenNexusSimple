import Foundation

/// A directed trade route: buy at `source`, haul, sell at `target`. Routes
/// with the same hub on both ends need no transport.
public struct TradeRoute: Hashable, Codable, Sendable {
  public let source: OpportunityHubRole
  public let target: OpportunityHubRole

  public init(source: OpportunityHubRole, target: OpportunityHubRole) {
    self.source = source
    self.target = target
  }

  public var requiresTransport: Bool { source != target }
}

/// The separately presented trade views. Station trading was removed and
/// Home ↔ Coalition added in both directions (owner decision 22.10.2026).
public enum TradeMode: String, Hashable, Codable, CaseIterable, Sendable {
  case mainToHome
  case mainToCoalition
  case homeToCoalition
  case coalitionToHome

  public var route: TradeRoute {
    switch self {
    case .mainToHome: TradeRoute(source: .main, target: .home)
    case .mainToCoalition: TradeRoute(source: .main, target: .coalition)
    case .homeToCoalition: TradeRoute(source: .home, target: .coalition)
    case .coalitionToHome: TradeRoute(source: .coalition, target: .home)
    }
  }

  public var sourceRole: OpportunityHubRole { route.source }
  public var targetRole: OpportunityHubRole { route.target }
  public var requiresTransport: Bool { route.requiresTransport }
}

/// The Min-Sell | Max-Buy switch of a tile. On the source side it selects an
/// instant purchase from the cheapest sell order (`minSell`) or an own buy
/// order above the best bid (`maxBuy`). On the target side it selects an own
/// sell order below the best ask (`minSell`, the normal case) or a direct sale
/// into the best buy order (`maxBuy`).
public enum TradeQuoteSide: String, Codable, CaseIterable, Sendable {
  case minSell
  case maxBuy
}

/// Effective market fees of one hub. `nil` means unknown, never zero.
public struct TradeHubFees: Equatable, Sendable {
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?

  public init(salesTaxRate: Double?, brokerFeeRate: Double?) {
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
  }

  public init(_ taxes: MarketTaxConfiguration) {
    self.init(
      salesTaxRate: taxes.effectiveSalesTaxRate,
      brokerFeeRate: taxes.effectiveBrokerFeeRate
    )
  }
}

/// Courier contract leg. Each contract is charged the higher of its volume
/// charge and its collateral charge (existing logistics rule).
public struct TradeCourierLeg: Equatable, Sendable {
  public let origin: String
  public let destination: String
  public let iskPerCubicMeter: Double
  public let maximumContractVolumeM3: Double
  public let collateralRate: Double

  public init(
    origin: String,
    destination: String,
    iskPerCubicMeter: Double,
    maximumContractVolumeM3: Double =
      LogisticsConfiguration.defaultMaximumContractVolumeM3,
    collateralRate: Double = LogisticsConfiguration.collateralRate
  ) {
    self.origin = origin
    self.destination = destination
    self.iskPerCubicMeter = iskPerCubicMeter
    self.maximumContractVolumeM3 = maximumContractVolumeM3
    self.collateralRate = collateralRate
  }
}

/// Jump Freighter leg. Fuel is paid per flight regardless of the load, so the
/// per-unit tile value assumes a full load (owner decision 22.10.2026).
public struct TradeJumpFreighterLeg: Equatable, Sendable {
  public let origin: String
  public let destination: String
  public let costPerFlight: Double
  public let usableCargoCapacityM3: Double

  public init(
    origin: String,
    destination: String,
    costPerFlight: Double,
    usableCargoCapacityM3: Double
  ) {
    self.origin = origin
    self.destination = destination
    self.costPerFlight = costPerFlight
    self.usableCargoCapacityM3 = usableCargoCapacityM3
  }
}

public enum TradeTransportLeg: Equatable, Sendable {
  case courier(TradeCourierLeg)
  case jumpFreighter(TradeJumpFreighterLeg)
  /// No usable transport for this leg; the route cost stays unknown.
  case unavailable(code: String)
}

/// Ordered transport legs of a trade route. Main → Home is one courier leg;
/// Main → Coalition is Main → Home by courier plus the Home → Coalition leg of
/// the Hub opportunities; Home ↔ Coalition is that leg alone, reversed for
/// Coalition → Home (owner decisions 22.10.2026). A route within one hub has
/// no legs.
public struct TradeTransportBasis: Equatable, Sendable {
  public let legs: [TradeTransportLeg]

  public init(legs: [TradeTransportLeg]) {
    self.legs = legs
  }

  public static let none = TradeTransportBasis(legs: [])
}

/// Market and catalog inputs for one item.
public struct TradeItemInput: Equatable, Sendable {
  public let typeID: Int64
  public let name: String
  public let packagedVolume: Double?
  public let source: MarketOrderTypeSummary?
  public let target: MarketOrderTypeSummary?

  public init(
    typeID: Int64,
    name: String,
    packagedVolume: Double?,
    source: MarketOrderTypeSummary?,
    target: MarketOrderTypeSummary?
  ) {
    self.typeID = typeID
    self.name = name
    self.packagedVolume = packagedVolume
    self.source = source
    self.target = target
  }
}

/// Why a value of a trade row is unavailable. A row may carry several.
public enum TradeRowIssue: String, Codable, CaseIterable, Sendable {
  case missingSourcePrice = "trade.missing-source-price"
  case missingTargetPrice = "trade.missing-target-price"
  case missingSourceBrokerFee = "trade.missing-source-broker-fee"
  case missingTargetFees = "trade.missing-target-fees"
  case missingPackagedVolume = "trade.missing-packaged-volume"
  case transportUnavailable = "trade.transport-unavailable"
  case exceedsJumpFreighterCapacity = "trade.exceeds-jump-freighter-capacity"
  case noValidPriceStep = "trade.no-valid-price-step"
}

/// One calculated row. Every money value is per unit in ISK; fractions are
/// not multiplied by 100. Unknown values are `nil`, never zero.
public struct TradeRow: Identifiable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let packagedVolume: Double?
  /// Best price shown in the tile for the selected source side.
  public let sourcePrice: Double?
  /// Best price shown in the tile for the selected target side.
  public let targetPrice: Double?
  /// Units listed at exactly `sourcePrice` / `targetPrice` (order depth).
  public let sourceVolumeAtPrice: Int64?
  public let targetVolumeAtPrice: Int64?
  /// `(targetPrice − sourcePrice) ÷ sourcePrice`.
  public let differenceFraction: Double?
  /// Purchase cost C including the buy-order broker fee.
  public let purchaseCost: Double?
  /// Transport T; zero for station trading.
  public let transportCost: Double?
  /// Net sale N after sales tax and, for sell orders, broker fee.
  public let netSale: Double?
  public let profit: Double?
  /// `profit ÷ netSale`.
  public let margin: Double?
  /// `profit ÷ (purchaseCost + transportCost)`.
  public let returnOnInvestment: Double?
  /// `(bestSell − bestBuy) ÷ bestBuy` at the target hub.
  public let targetSpreadFraction: Double?
  public let issues: [TradeRowIssue]

  public init(
    typeID: Int64,
    name: String,
    packagedVolume: Double?,
    sourcePrice: Double?,
    targetPrice: Double?,
    sourceVolumeAtPrice: Int64? = nil,
    targetVolumeAtPrice: Int64? = nil,
    differenceFraction: Double?,
    purchaseCost: Double?,
    transportCost: Double?,
    netSale: Double?,
    profit: Double?,
    margin: Double?,
    returnOnInvestment: Double?,
    targetSpreadFraction: Double?,
    issues: [TradeRowIssue]
  ) {
    self.typeID = typeID
    self.name = name
    self.packagedVolume = packagedVolume
    self.sourcePrice = sourcePrice
    self.targetPrice = targetPrice
    self.sourceVolumeAtPrice = sourceVolumeAtPrice
    self.targetVolumeAtPrice = targetVolumeAtPrice
    self.differenceFraction = differenceFraction
    self.purchaseCost = purchaseCost
    self.transportCost = transportCost
    self.netSale = netSale
    self.profit = profit
    self.margin = margin
    self.returnOnInvestment = returnOnInvestment
    self.targetSpreadFraction = targetSpreadFraction
    self.issues = issues
  }
}

/// Exact route cost for a concrete quantity.
public struct TradeTransportQuote: Equatable, Sendable {
  public let total: Double?
  public let perUnit: Double?
  public let issues: [TradeRowIssue]
  public let warnings: [DomainWarning]

  public init(
    total: Double?,
    perUnit: Double?,
    issues: [TradeRowIssue],
    warnings: [DomainWarning]
  ) {
    self.total = total
    self.perUnit = perUnit
    self.issues = issues
    self.warnings = warnings
  }
}
