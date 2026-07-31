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

  @Test
  func marketOrderRequestsUseBoundedConcurrency() async throws {
    let transport = ConcurrentMarketTransport()
    let service = JitaMarketService(
      esi: ESIClient(transport: transport),
      maximumConcurrentOrderRequests: 3
    )

    let snapshot = try await service.orderSnapshot(
      typeIDs: Set((1...12).map(Int64.init))
    )

    #expect(snapshot.ordersByType.count == 12)
    #expect(await transport.requestCount == 12)
    #expect(await transport.maximumConcurrentRequests > 1)
    #expect(await transport.maximumConcurrentRequests <= 3)
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

private actor ConcurrentMarketTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0
  private(set) var maximumConcurrentRequests = 0
  private var activeRequests = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    activeRequests += 1
    maximumConcurrentRequests = max(
      maximumConcurrentRequests,
      activeRequests
    )
    defer { activeRequests -= 1 }
    try await Task.sleep(for: .milliseconds(15))
    return (
      Data("[]".utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Expires": "Wed, 30 Jul 2026 10:00:00 GMT",
          "X-Pages": "1",
        ]
      )!
    )
  }
}
