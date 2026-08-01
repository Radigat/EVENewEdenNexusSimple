import Foundation

public enum MarketOrderSide: String, Codable, Sendable {
  case buy
  case sell
}

public enum MarketTradeHub: String, CaseIterable, Codable, Identifiable,
  Sendable
{
  case jita
  case amarr
  case dodixie
  case rens
  case hek

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .jita: "Jita IV - Moon 4 - Caldari Navy Assembly Plant"
    case .amarr: "Amarr VIII (Oris) - Emperor Family Academy"
    case .dodixie: "Dodixie IX - Moon 20 - Federation Navy Assembly Plant"
    case .rens: "Rens VI - Moon 8 - Brutor Tribe Treasury"
    case .hek: "Hek VIII - Moon 12 - Boundless Creation Factory"
    }
  }

  public var regionID: Int64 {
    switch self {
    case .jita: 10_000_002
    case .amarr: 10_000_043
    case .dodixie: 10_000_032
    case .rens: 10_000_030
    case .hek: 10_000_042
    }
  }

  public var systemID: Int64 {
    switch self {
    case .jita: 30_000_142
    case .amarr: 30_002_187
    case .dodixie: 30_002_659
    case .rens: 30_002_510
    case .hek: 30_002_053
    }
  }

  public var stationID: Int64 {
    switch self {
    case .jita: 60_003_760
    case .amarr: 60_008_494
    case .dodixie: 60_011_866
    case .rens: 60_004_588
    case .hek: 60_005_686
    }
  }

  public static func matching(stationID: Int64) -> MarketTradeHub? {
    allCases.first { $0.stationID == stationID }
  }

  public var procurementLocation: ProcurementLocation {
    ProcurementLocation.standardTradeHubs.first {
      $0.locationID == stationID
    } ?? .jita
  }
}

public enum MoonMaterialMarketLocation: String, CaseIterable, Codable,
  Identifiable, Sendable
{
  case jita
  case amarr
  case hek
  case dodixie
  case ualx3
  case cj6mt

  public var id: String { rawValue }

  public var shortName: String {
    switch self {
    case .jita: "Jita"
    case .amarr: "Amarr"
    case .hek: "Hek"
    case .dodixie: "Dodixie"
    case .ualx3: "UALX-3"
    case .cj6mt: "C-J6MT"
    }
  }

  public var regionID: Int64 {
    switch self {
    case .jita: 10_000_002
    case .amarr: 10_000_043
    case .hek: 10_000_042
    case .dodixie: 10_000_032
    case .ualx3: 10_000_061
    case .cj6mt: 10_000_009
    }
  }

  public var systemID: Int64 {
    switch self {
    case .jita: 30_000_142
    case .amarr: 30_002_187
    case .hek: 30_002_053
    case .dodixie: 30_002_659
    case .ualx3: 30_004_807
    case .cj6mt: 30_000_772
    }
  }

  public var locationID: Int64 {
    switch self {
    case .jita: 60_003_760
    case .amarr: 60_008_494
    case .hek: 60_005_686
    case .dodixie: 60_011_866
    case .ualx3: 1_046_664_001_931
    case .cj6mt: 1_049_588_174_021
    }
  }

  public var isPlayerStructure: Bool {
    switch self {
    case .ualx3, .cj6mt: true
    default: false
    }
  }
}

public struct MoonMaterial: Identifiable, Codable, Equatable, Sendable {
  public let id: Int64
  public let name: String

  public init(id: Int64, name: String) {
    self.id = id
    self.name = name
  }
}

public struct MoonMaterialCatalogSnapshot: Codable, Sendable {
  public let materials: [MoonMaterial]
  public let source: SourceIdentity

  public init(materials: [MoonMaterial], source: SourceIdentity) {
    self.materials = materials
    self.source = source
  }
}

public protocol MoonMaterialCatalogQuerying: Sendable {
  func moonMaterials() async throws -> MoonMaterialCatalogSnapshot
}

public struct MoonMaterialPriceBand: Codable, Equatable, Sendable {
  public let lowestSellPrice: Double
  public let maximumBandPrice: Double
  public let availableQuantity: Int64
  public let orderCount: Int

  public init(
    lowestSellPrice: Double,
    maximumBandPrice: Double,
    availableQuantity: Int64,
    orderCount: Int
  ) {
    self.lowestSellPrice = lowestSellPrice
    self.maximumBandPrice = maximumBandPrice
    self.availableQuantity = availableQuantity
    self.orderCount = orderCount
  }
}

public enum MoonMaterialMarketPriceRank: Int, Codable, Equatable, Sendable {
  case cheapest = 1
  case secondCheapest = 2
  case thirdCheapest = 3
}

public struct MoonMaterialPurchaseAnalysisSnapshot: Codable, Sendable {
  public let materialCatalog: MoonMaterialCatalogSnapshot
  public let markets: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>]
  public let refreshedAt: Date

  public init(
    materialCatalog: MoonMaterialCatalogSnapshot,
    markets: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>],
    refreshedAt: Date
  ) {
    self.materialCatalog = materialCatalog
    self.markets = markets
    self.refreshedAt = refreshedAt
  }
}

public struct MarketOrder: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let locationID: Int64
  public let systemID: Int64
  public let side: MarketOrderSide
  public let price: Double
  public let volumeRemaining: Int64
  public let minimumVolume: Int64
  public let issued: Date
}

public struct MarketOrderSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let regionID: Int64
  public let locationID: Int64
  public let capturedAt: Date
  public let state: DataFreshness
  public let ordersByType: [Int64: [MarketOrder]]
  public let source: SourceIdentity
}

public enum PriceScenario: String, Codable, CaseIterable, Sendable {
  case materialBuy
  case immediateSale
  case listedSale
}

public struct PriceQuote: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let quantity: Int64
  public let scenario: PriceScenario
  public let total: Double?
  public let weightedUnitPrice: Double?
  public let filledQuantity: Int64
  public let capturedAt: Date
  public let source: SourceIdentity
  public let warnings: [DomainWarning]

  public var isComplete: Bool {
    total != nil && filledQuantity == quantity
  }
}

public struct AdjustedPrice: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let adjustedPrice: Double?
  public let averagePrice: Double?
}

public struct ReferencePriceSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let capturedAt: Date
  public let prices: [Int64: AdjustedPrice]
  public let source: SourceIdentity

  public init(
    id: UUID = UUID(),
    capturedAt: Date,
    prices: [Int64: AdjustedPrice],
    source: SourceIdentity
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.prices = prices
    self.source = source
  }
}

public struct IndustrySystemIndex: Codable, Hashable, Sendable {
  public let solarSystemID: Int64
  public let activity: BlueprintActivityDefinition.Kind
  public let costIndex: Double
}

public enum MarketPriceEngine {
  public static func quote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    snapshot: MarketOrderSnapshot,
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil
  ) -> PriceQuote {
    let source = snapshot.source
    guard quantity > 0 else {
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: 0,
        weightedUnitPrice: 0,
        filledQuantity: 0,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: []
      )
    }

    let relevant = (snapshot.ordersByType[typeID] ?? []).filter {
      $0.locationID == snapshot.locationID
        && $0.price.isFinite
        && $0.price > 0
        && $0.volumeRemaining > 0
        && $0.minimumVolume > 0
    }
    let sorted: [MarketOrder]
    switch scenario {
    case .materialBuy, .listedSale:
      sorted = relevant.filter { $0.side == .sell }
        .sorted { $0.price < $1.price }
    case .immediateSale:
      sorted = relevant.filter { $0.side == .buy }
        .sorted { $0.price > $1.price }
    }

    guard !sorted.isEmpty else {
      return missingQuote(
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        source: source,
        capturedAt: snapshot.capturedAt,
        code: "market.no-orders"
      )
    }

    if scenario == .listedSale {
      guard let salesTaxRate, let brokerFeeRate,
        salesTaxRate.isFinite,
        brokerFeeRate.isFinite,
        salesTaxRate >= 0,
        brokerFeeRate >= 0,
        salesTaxRate + brokerFeeRate < 1
      else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.missing-sales-fees"
        )
      }
      let price = sorted[0].price
      let gross = price * Double(quantity)
      let net = gross * (1 - salesTaxRate - brokerFeeRate)
      guard gross.isFinite, net.isFinite else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.invalid-price"
        )
      }
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: net,
        weightedUnitPrice: net / Double(quantity),
        filledQuantity: quantity,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: []
      )
    }

    var remaining = quantity
    var filled: Int64 = 0
    var total = 0.0
    for order in sorted where remaining > 0 {
      if order.minimumVolume > 1,
        remaining < order.minimumVolume
      {
        continue
      }
      let take = min(remaining, order.volumeRemaining)
      guard take > 0 else { continue }
      total += Double(take) * order.price
      guard total.isFinite else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.invalid-price"
        )
      }
      remaining -= take
      filled += take
    }

    guard remaining == 0 else {
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: nil,
        weightedUnitPrice: nil,
        filledQuantity: filled,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: [
          DomainWarning(
            code: "market.insufficient-depth",
            message:
              "Only \(filled) of \(quantity) units are available at the selected trade hub.",
            severity: .blocking,
            source: source
          )
        ]
      )
    }

    return PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: total,
      weightedUnitPrice: total / Double(quantity),
      filledQuantity: filled,
      capturedAt: snapshot.capturedAt,
      source: source,
      warnings: []
    )
  }

  private static func missingQuote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    source: SourceIdentity,
    capturedAt: Date,
    code: String
  ) -> PriceQuote {
    PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: nil,
      weightedUnitPrice: nil,
      filledQuantity: 0,
      capturedAt: capturedAt,
      source: source,
      warnings: [
        DomainWarning(
          code: code,
          message: "No usable market orders are available at the selected trade hub.",
          severity: .blocking,
          source: source
        )
      ]
    )
  }
}

public enum MoonMaterialPriceBandAnalyzer {
  public static let defaultMarkup = 0.10

  public static func analyze(
    typeID: Int64,
    snapshot: MarketOrderSnapshot,
    markup: Double = defaultMarkup
  ) -> MoonMaterialPriceBand? {
    guard markup.isFinite, markup >= 0 else { return nil }
    let sellOrders = (snapshot.ordersByType[typeID] ?? []).filter {
      $0.locationID == snapshot.locationID
        && $0.side == .sell
        && $0.price.isFinite
        && $0.price > 0
        && $0.volumeRemaining > 0
        && $0.minimumVolume > 0
    }
    guard let lowestSellPrice = sellOrders.map(\.price).min() else {
      return nil
    }
    let maximumBandPrice = lowestSellPrice * (1 + markup)
    guard maximumBandPrice.isFinite else { return nil }
    let eligibleOrders = sellOrders.filter {
      $0.price <= maximumBandPrice
    }
    var availableQuantity: Int64 = 0
    for order in eligibleOrders {
      let (sum, overflow) = availableQuantity.addingReportingOverflow(
        order.volumeRemaining
      )
      availableQuantity = overflow ? .max : sum
    }
    return MoonMaterialPriceBand(
      lowestSellPrice: lowestSellPrice,
      maximumBandPrice: maximumBandPrice,
      availableQuantity: availableQuantity,
      orderCount: eligibleOrders.count
    )
  }
}

public enum MoonMaterialMarketPriceRankAnalyzer {
  public static func ranks(
    typeID: Int64,
    markets: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>]
  ) -> [MoonMaterialMarketLocation: MoonMaterialMarketPriceRank] {
    let observations: [(location: MoonMaterialMarketLocation, price: Double)] = markets.compactMap {
      entry in
      let (location, sourced) = entry
      guard sourced.state == .fresh,
        let snapshot = sourced.value,
        let band = MoonMaterialPriceBandAnalyzer.analyze(
          typeID: typeID,
          snapshot: snapshot
        )
      else { return nil }
      return (location: location, price: band.lowestSellPrice)
    }
    let rankedPrices = observations.map(\.price).sorted().reduce(
      into: [Double]()
    ) { distinctPrices, price in
      guard distinctPrices.last != price else { return }
      distinctPrices.append(price)
    }
    .prefix(3)

    var result: [MoonMaterialMarketLocation: MoonMaterialMarketPriceRank] = [:]
    for observation in observations {
      guard let index = rankedPrices.firstIndex(of: observation.price),
        let rank = MoonMaterialMarketPriceRank(rawValue: index + 1)
      else { continue }
      result[observation.location] = rank
    }
    return result
  }
}

public typealias JitaPriceEngine = MarketPriceEngine
