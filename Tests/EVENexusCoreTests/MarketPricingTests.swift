import Foundation
import Testing

@testable import EVENexusCore

@Suite("Jita depth pricing")
struct MarketPricingTests {
  @Test
  func consumesCheapestSellDepth() {
    let snapshot = makeSnapshot(
      orders: [
        order(id: 1, side: .sell, price: 10, volume: 5),
        order(id: 2, side: .sell, price: 12, volume: 10),
      ]
    )

    let quote = JitaPriceEngine.quote(
      typeID: 34,
      quantity: 8,
      scenario: .materialBuy,
      snapshot: snapshot
    )

    #expect(quote.total == 86)
    #expect(quote.filledQuantity == 8)
    #expect(quote.isComplete)
  }

  @Test
  func missingDepthIsNotZero() {
    let snapshot = makeSnapshot(
      orders: [order(id: 1, side: .sell, price: 10, volume: 2)]
    )
    let quote = JitaPriceEngine.quote(
      typeID: 34,
      quantity: 8,
      scenario: .materialBuy,
      snapshot: snapshot
    )

    #expect(quote.total == nil)
    #expect(quote.warnings.first?.severity == .blocking)
  }

  @Test
  func listedSaleDeductsFees() {
    let snapshot = makeSnapshot(
      orders: [order(id: 1, side: .sell, price: 100, volume: 100)]
    )
    let quote = JitaPriceEngine.quote(
      typeID: 34,
      quantity: 10,
      scenario: .listedSale,
      snapshot: snapshot,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01
    )

    #expect(quote.total == 940)
  }

  @Test
  func rejectsInvalidOrdersAndFeeRates() {
    let snapshot = makeSnapshot(
      orders: [
        order(id: 1, side: .sell, price: -1, volume: 100),
        order(id: 2, side: .sell, price: .infinity, volume: 100),
      ]
    )
    let invalidOrders = JitaPriceEngine.quote(
      typeID: 34,
      quantity: 10,
      scenario: .materialBuy,
      snapshot: snapshot
    )
    let invalidFees = JitaPriceEngine.quote(
      typeID: 34,
      quantity: 10,
      scenario: .listedSale,
      snapshot: makeSnapshot(
        orders: [order(id: 3, side: .sell, price: 100, volume: 100)]
      ),
      salesTaxRate: 0.9,
      brokerFeeRate: 0.2
    )

    #expect(invalidOrders.total == nil)
    #expect(invalidFees.total == nil)
  }

  private func makeSnapshot(orders: [MarketOrder]) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [34: orders],
      source: SourceIdentity(provider: "fixture", version: "1")
    )
  }

  private func order(
    id: Int64,
    side: MarketOrderSide,
    price: Double,
    volume: Int64
  ) -> MarketOrder {
    MarketOrder(
      id: id,
      typeID: 34,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: side,
      price: price,
      volumeRemaining: volume,
      minimumVolume: 1,
      issued: .now
    )
  }
}
