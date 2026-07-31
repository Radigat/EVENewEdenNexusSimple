import Foundation

public enum MarketOrderSide: String, Codable, Sendable {
  case buy
  case sell
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

public enum JitaPriceEngine {
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
      $0.locationID == EVEConstants.jitaIV4StationID
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
            message: "Only \(filled) of \(quantity) units are available at Jita IV-4.",
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
          message: "No usable Jita market orders are available.",
          severity: .blocking,
          source: source
        )
      ]
    )
  }
}
