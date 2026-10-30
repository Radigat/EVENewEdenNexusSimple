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
/// Home ↔ Coalition added in both directions (owner decision 22.10.2026);
/// Home → Main and Coalition → Main added on 27.10.2026. New cases are
/// appended so stored raw values keep their meaning.
public enum TradeMode: String, Hashable, Codable, CaseIterable, Sendable {
  case mainToHome
  case mainToCoalition
  case homeToCoalition
  case coalitionToHome
  case homeToMain
  case coalitionToMain

  public var route: TradeRoute {
    switch self {
    case .mainToHome: TradeRoute(source: .main, target: .home)
    case .mainToCoalition: TradeRoute(source: .main, target: .coalition)
    case .homeToCoalition: TradeRoute(source: .home, target: .coalition)
    case .coalitionToHome: TradeRoute(source: .coalition, target: .home)
    case .homeToMain: TradeRoute(source: .home, target: .main)
    case .coalitionToMain: TradeRoute(source: .coalition, target: .main)
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

/// Who carries a contract leg and therefore how it is charged.
public enum TradeCourierProvider: Equatable, Sendable {
  /// Profile courier: the higher of volume and collateral charge, each
  /// contract rounded up to 1,000,000 ISK (existing logistics rule).
  case profileCourier
  /// Jump Freighter service: volume charge plus collateral charge, without
  /// rounding (owner decision 27.10.2026).
  case jumpFreighterService

  public var sumsVolumeAndCollateral: Bool { self == .jumpFreighterService }

  public var roundingIncrement: Double? {
    switch self {
    case .profileCourier: LogisticsConfiguration.roundingIncrement
    case .jumpFreighterService: nil
    }
  }
}

/// Courier contract leg, charged according to its provider.
public struct TradeCourierLeg: Equatable, Sendable {
  public let origin: String
  public let destination: String
  public let iskPerCubicMeter: Double
  public let maximumContractVolumeM3: Double
  public let collateralRate: Double
  public let provider: TradeCourierProvider

  public init(
    origin: String,
    destination: String,
    iskPerCubicMeter: Double,
    maximumContractVolumeM3: Double =
      LogisticsConfiguration.defaultMaximumContractVolumeM3,
    collateralRate: Double = LogisticsConfiguration.collateralRate,
    provider: TradeCourierProvider = .profileCourier
  ) {
    self.origin = origin
    self.destination = destination
    self.iskPerCubicMeter = iskPerCubicMeter
    self.maximumContractVolumeM3 = maximumContractVolumeM3
    self.collateralRate = collateralRate
    self.provider = provider
  }

  /// Per-unit charge without contract rounding.
  public func unitCharge(volume: Double, collateral: Double) -> Double {
    let volumeCharge = volume * iskPerCubicMeter
    let collateralCharge = collateral * collateralRate
    return provider.sumsVolumeAndCollateral
      ? volumeCharge + collateralCharge
      : max(volumeCharge, collateralCharge)
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

/// Ordered transport legs of a trade route, one per `HubTransportLeg` the
/// route uses (see `HubTransportConfiguration.legs(for:)`). A route within
/// one hub has no legs.
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

extension TradeRow {
  /// `profit ÷ packagedVolume` in ISK per m³ (HANDEL_PLAN.md, section J).
  /// Unknown without a profit or a positive, finite packaged volume.
  public var profitPerCubicMeter: Double? {
    guard let profit, let volume = packagedVolume, volume.isFinite, volume > 0
    else { return nil }
    let value = profit / volume
    return value.isFinite ? value : nil
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

/// A directed transport leg between two hubs. Each leg chooses its own
/// transport method (owner request 27.10.2026).
public enum HubTransportLeg: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case mainToHome
  case homeToMain
  case homeToCoalition
  case coalitionToHome
  case mainToCoalition
  case coalitionToMain

  public var id: Self { self }

  public var origin: OpportunityHubRole {
    switch self {
    case .mainToHome, .mainToCoalition: .main
    case .homeToMain, .homeToCoalition: .home
    case .coalitionToHome, .coalitionToMain: .coalition
    }
  }

  public var destination: OpportunityHubRole {
    switch self {
    case .homeToMain, .coalitionToMain: .main
    case .mainToHome, .coalitionToHome: .home
    case .homeToCoalition, .mainToCoalition: .coalition
    }
  }

  /// Main is a high-security hub a Jump Freighter cannot jump into or out of;
  /// a self-jump on such a leg needs a fixed route profile whose Main-side
  /// end is a jumpable system near the Main Hub.
  public var touchesMain: Bool { origin == .main || destination == .main }
}

public enum HubTransportMethod: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  /// The Profile courier rate of the logistics settings.
  case profileCourier
  /// Own Jump Freighter: isotope cost per flight from a DOTLAN-verified route.
  case selfJump
  /// A Jump Freighter service with user-entered prices for this leg.
  case jumpFreighterService

  public var id: Self { self }
}

/// User-entered prices of a Jump Freighter service for one leg. A missing or
/// invalid value keeps the leg unavailable; it never becomes 0 ISK.
public struct JumpFreighterServiceRate: Codable, Equatable, Sendable {
  public var iskPerCubicMeter: Double?
  /// Fraction of the collateral, for example 0.01 for 1 %.
  public var collateralRate: Double?
  public var maximumContractVolumeM3: Double

  public init(
    iskPerCubicMeter: Double? = nil,
    collateralRate: Double? = nil,
    maximumContractVolumeM3: Double =
      LogisticsConfiguration.defaultMaximumContractVolumeM3
  ) {
    self.iskPerCubicMeter = iskPerCubicMeter
    self.collateralRate = collateralRate
    self.maximumContractVolumeM3 = maximumContractVolumeM3
  }

  public var effectiveISKPerCubicMeter: Double? {
    guard let iskPerCubicMeter, iskPerCubicMeter.isFinite,
      iskPerCubicMeter >= 0
    else { return nil }
    return iskPerCubicMeter
  }

  public var effectiveCollateralRate: Double? {
    guard let collateralRate, collateralRate.isFinite, collateralRate >= 0,
      collateralRate < 1
    else { return nil }
    return collateralRate
  }

  public var effectiveMaximumContractVolumeM3: Double? {
    guard maximumContractVolumeM3.isFinite, maximumContractVolumeM3 > 0
    else { return nil }
    return maximumContractVolumeM3
  }

  public var isComplete: Bool {
    effectiveISKPerCubicMeter != nil && effectiveCollateralRate != nil
      && effectiveMaximumContractVolumeM3 != nil
  }
}

public struct HubTransportLegSetting: Codable, Equatable, Sendable {
  public let leg: HubTransportLeg
  public var method: HubTransportMethod
  public var service: JumpFreighterServiceRate
  /// Fixed jump-route profile for a self-jump. `nil` uses the Jump Freighter
  /// class assignment or automatic DOTLAN routing; legs touching Main
  /// require a profile.
  public var jumpRouteProfileID: UUID?

  public init(
    leg: HubTransportLeg,
    method: HubTransportMethod,
    service: JumpFreighterServiceRate = .init(),
    jumpRouteProfileID: UUID? = nil
  ) {
    self.leg = leg
    self.method = method
    self.service = service
    self.jumpRouteProfileID = jumpRouteProfileID
  }
}

/// Whether Main ↔ Coalition travels via the Home Hub (two legs) or directly.
public enum HubTransportRouting: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case viaHome
  case direct

  public var id: Self { self }
}

/// Transport choice per directed hub leg (owner request 27.10.2026). Legs
/// without a stored setting keep the earlier rule: Main ↔ Home by Profile
/// courier, Home ↔ Coalition by own Jump Freighter when jump logistics is
/// enabled and otherwise by Profile courier, Main ↔ Coalition via Home.
/// Trade, Planner, Hub opportunities and Reactions use it; a self-jump on a
/// leg touching the Main Hub is calculated only in Trade (owner decision
/// 27.10.2026).
public struct HubTransportConfiguration: Codable, Equatable, Sendable {
  public var legSettings: [HubTransportLegSetting]
  public var mainToCoalitionRouting: HubTransportRouting
  public var coalitionToMainRouting: HubTransportRouting

  public init(
    legSettings: [HubTransportLegSetting] = [],
    mainToCoalitionRouting: HubTransportRouting = .viaHome,
    coalitionToMainRouting: HubTransportRouting = .viaHome
  ) {
    self.legSettings = legSettings
    self.mainToCoalitionRouting = mainToCoalitionRouting
    self.coalitionToMainRouting = coalitionToMainRouting
  }

  private enum CodingKeys: String, CodingKey {
    case legSettings, mainToCoalitionRouting, coalitionToMainRouting
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    legSettings =
      try container.decodeIfPresent(
        [HubTransportLegSetting].self,
        forKey: .legSettings
      ) ?? []
    mainToCoalitionRouting =
      try container.decodeIfPresent(
        HubTransportRouting.self,
        forKey: .mainToCoalitionRouting
      ) ?? .viaHome
    coalitionToMainRouting =
      try container.decodeIfPresent(
        HubTransportRouting.self,
        forKey: .coalitionToMainRouting
      ) ?? .viaHome
  }

  public static func defaultMethod(
    for leg: HubTransportLeg,
    jumpFreighterEnabled: Bool
  ) -> HubTransportMethod {
    switch leg {
    case .homeToCoalition, .coalitionToHome:
      jumpFreighterEnabled ? .selfJump : .profileCourier
    case .mainToHome, .homeToMain, .mainToCoalition, .coalitionToMain:
      .profileCourier
    }
  }

  public func setting(
    for leg: HubTransportLeg,
    jumpFreighterEnabled: Bool
  ) -> HubTransportLegSetting {
    legSettings.last(where: { $0.leg == leg })
      ?? HubTransportLegSetting(
        leg: leg,
        method: Self.defaultMethod(
          for: leg,
          jumpFreighterEnabled: jumpFreighterEnabled
        )
      )
  }

  public mutating func set(_ setting: HubTransportLegSetting) {
    legSettings.removeAll { $0.leg == setting.leg }
    legSettings.append(setting)
  }

  /// The ordered legs a trade route travels.
  public func legs(for route: TradeRoute) -> [HubTransportLeg] {
    switch (route.source, route.target) {
    case (.main, .home): [.mainToHome]
    case (.home, .main): [.homeToMain]
    case (.home, .coalition): [.homeToCoalition]
    case (.coalition, .home): [.coalitionToHome]
    case (.main, .coalition):
      mainToCoalitionRouting == .direct
        ? [.mainToCoalition] : [.mainToHome, .homeToCoalition]
    case (.coalition, .main):
      coalitionToMainRouting == .direct
        ? [.coalitionToMain] : [.coalitionToHome, .homeToMain]
    case (.main, .main), (.home, .home), (.coalition, .coalition): []
    }
  }
}

/// Contract prices of a leg carried by the Profile courier or a Jump
/// Freighter service.
public struct LogisticsContractPricing: Equatable, Sendable {
  public let iskPerCubicMeter: Double
  public let maximumContractVolumeM3: Double
  public let collateralRate: Double
  public let provider: TradeCourierProvider

  public init(
    iskPerCubicMeter: Double,
    maximumContractVolumeM3: Double,
    collateralRate: Double = LogisticsConfiguration.collateralRate,
    provider: TradeCourierProvider = .profileCourier
  ) {
    self.iskPerCubicMeter = iskPerCubicMeter
    self.maximumContractVolumeM3 = maximumContractVolumeM3
    self.collateralRate = collateralRate
    self.provider = provider
  }

  /// Rounding step stored in a `LogisticsCostBreakdown`; 0 means none.
  public var breakdownRoundingIncrement: Double {
    provider.roundingIncrement ?? 0
  }
}

public enum LogisticsLegPricing: Equatable, Sendable {
  case contract(LogisticsContractPricing)
  /// Own Jump Freighter between Home and Coalition; callers use their Jump
  /// Freighter calculation.
  case selfJump
  case unavailable(DomainWarning)
}

extension LogisticsConfiguration {
  public func transportSetting(
    for leg: HubTransportLeg
  ) -> HubTransportLegSetting {
    hubTransport.setting(
      for: leg,
      jumpFreighterEnabled: jumpFreighter.isEnabled
    )
  }

  /// Pricing of one leg for Planner, Hub opportunities and Reactions. The
  /// Profile-logistics switch stays the callers' concern.
  public func legPricing(for leg: HubTransportLeg) -> LogisticsLegPricing {
    let setting = transportSetting(for: leg)
    switch setting.method {
    case .profileCourier:
      guard let rate = effectiveISKPerCubicMeter else {
        return .unavailable(
          DomainWarning(
            code: "logistics.missing-volume-rate",
            message:
              "Logistics is enabled, but the ISK per m³ rate is missing or invalid.",
            severity: .blocking
          )
        )
      }
      guard let maximumVolume = effectiveMaximumContractVolumeM3 else {
        return .unavailable(
          DomainWarning(
            code: "logistics.invalid-volume-limit",
            message:
              "Logistics is enabled, but the contract volume limit is invalid.",
            severity: .blocking
          )
        )
      }
      return .contract(
        LogisticsContractPricing(
          iskPerCubicMeter: rate,
          maximumContractVolumeM3: maximumVolume
        )
      )
    case .jumpFreighterService:
      guard let rate = setting.service.effectiveISKPerCubicMeter,
        let collateralRate = setting.service.effectiveCollateralRate,
        let maximumVolume = setting.service.effectiveMaximumContractVolumeM3
      else {
        return .unavailable(
          DomainWarning(
            code: "logistics.jf-service-rate-missing",
            message:
              "The Jump Freighter service prices of this leg are incomplete in the logistics settings.",
            severity: .blocking
          )
        )
      }
      return .contract(
        LogisticsContractPricing(
          iskPerCubicMeter: rate,
          maximumContractVolumeM3: maximumVolume,
          collateralRate: collateralRate,
          provider: .jumpFreighterService
        )
      )
    case .selfJump:
      guard !leg.touchesMain else {
        return .unavailable(
          DomainWarning(
            code: "logistics.main-self-jump-unsupported",
            message:
              "A self-jump to or from the Main Hub is calculated only in Trade. Choose the Profile courier or a Jump Freighter service for this leg.",
            severity: .blocking
          )
        )
      }
      return .selfJump
    }
  }
}

extension LogisticsCostCalculator {
  public static func calculateLegs(
    kind: LogisticsLegKind,
    origin: String,
    destination: String,
    cargo: [LogisticsCargoItem],
    pricing: LogisticsContractPricing
  ) -> (legs: [LogisticsCostLeg], warnings: [DomainWarning]) {
    calculateLegs(
      kind: kind,
      origin: origin,
      destination: destination,
      cargo: cargo,
      iskPerCubicMeter: pricing.iskPerCubicMeter,
      maximumContractVolumeM3: pricing.maximumContractVolumeM3,
      collateralRate: pricing.collateralRate,
      sumsVolumeAndCollateral: pricing.provider.sumsVolumeAndCollateral,
      roundingIncrement: pricing.provider.roundingIncrement
    )
  }
}
