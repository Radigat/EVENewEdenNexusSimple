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
  func selectedTradeHubFiltersItsOwnStationOrders() {
    let snapshot = MarketOrderSnapshot(
      id: UUID(),
      regionID: MarketTradeHub.amarr.regionID,
      locationID: MarketTradeHub.amarr.stationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        34: [
          order(
            id: 1,
            side: .sell,
            price: 5,
            volume: 100,
            hub: .jita
          ),
          order(
            id: 2,
            side: .sell,
            price: 11,
            volume: 100,
            hub: .amarr
          ),
        ]
      ],
      source: SourceIdentity(provider: "fixture", version: "1")
    )

    let quote = MarketPriceEngine.quote(
      typeID: 34,
      quantity: 10,
      scenario: .materialBuy,
      snapshot: snapshot
    )

    #expect(quote.total == 110)
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
      typeIDs: Set((1...12).map(Int64.init)),
      tradeHub: .amarr
    )

    #expect(snapshot.ordersByType.count == 12)
    #expect(snapshot.regionID == MarketTradeHub.amarr.regionID)
    #expect(snapshot.locationID == MarketTradeHub.amarr.stationID)
    #expect(await transport.requestCount == 12)
    #expect(
      await transport.requestedURLs.allSatisfy {
        $0.path.contains("/markets/\(MarketTradeHub.amarr.regionID)/orders")
      }
    )
    #expect(await transport.maximumConcurrentRequests > 1)
    #expect(await transport.maximumConcurrentRequests <= 3)
  }

  @Test
  func moonMaterialBandSumsSellVolumeThroughExactTenPercentLimit() {
    let snapshot = makeSnapshot(
      orders: [
        order(id: 1, side: .sell, price: 100, volume: 10),
        order(id: 2, side: .sell, price: 110, volume: 20),
        order(id: 3, side: .sell, price: 110.01, volume: 40),
        order(id: 4, side: .buy, price: 109, volume: 1_000),
        order(
          id: 5,
          side: .sell,
          price: 90,
          volume: 1_000,
          hub: .amarr
        ),
      ]
    )

    let band = MoonMaterialPriceBandAnalyzer.analyze(
      typeID: 34,
      snapshot: snapshot
    )

    #expect(band?.lowestSellPrice == 100)
    #expect(abs((band?.maximumBandPrice ?? 0) - 110) < 0.000_001)
    #expect(band?.availableQuantity == 30)
    #expect(band?.orderCount == 2)
  }

  @Test
  func moonMaterialBandDoesNotInventAValueForAnEmptyLocation() {
    let snapshot = makeSnapshot(
      orders: [order(id: 1, side: .buy, price: 100, volume: 10)]
    )

    #expect(
      MoonMaterialPriceBandAnalyzer.analyze(
        typeID: 34,
        snapshot: snapshot
      ) == nil
    )
  }

  @Test
  func moonMarketRanksThreeLowestDistinctFreshPricesAndSharesTies() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let markets: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>] = [
      .jita: Sourced(
        state: .fresh,
        value: makeMoonSnapshot(location: .jita, price: 100),
        source: source
      ),
      .amarr: Sourced(
        state: .fresh,
        value: makeMoonSnapshot(location: .amarr, price: 120),
        source: source
      ),
      .hek: Sourced(
        state: .fresh,
        value: makeMoonSnapshot(location: .hek, price: 110),
        source: source
      ),
      .dodixie: Sourced(
        state: .fresh,
        value: makeMoonSnapshot(location: .dodixie, price: 100),
        source: source
      ),
      .ualx3: Sourced(
        state: .fresh,
        value: makeMoonSnapshot(location: .ualx3, price: 130),
        source: source
      ),
      .cj6mt: Sourced(
        state: .stale,
        value: makeMoonSnapshot(location: .cj6mt, price: 90),
        source: source
      ),
    ]

    let ranks = MoonMaterialMarketPriceRankAnalyzer.ranks(
      typeID: 34,
      markets: markets
    )

    #expect(ranks[.jita] == .cheapest)
    #expect(ranks[.dodixie] == .cheapest)
    #expect(ranks[.hek] == .secondCheapest)
    #expect(ranks[.amarr] == .thirdCheapest)
    #expect(ranks[.ualx3] == nil)
    #expect(ranks[.cj6mt] == nil)
  }

  @Test
  func moonMarketLocationsUseVerifiedRegionsAndExactLocationIDs() async throws {
    #expect(MarketTradeHub.hek.regionID == 10_000_042)
    #expect(MoonMaterialMarketLocation.ualx3.regionID == 10_000_061)
    #expect(MoonMaterialMarketLocation.cj6mt.regionID == 10_000_009)

    let transport = ConcurrentMarketTransport()
    let service = TradeHubMarketService(
      esi: ESIClient(transport: transport)
    )
    let snapshot = try await service.orderSnapshot(
      typeIDs: [16_634],
      location: .ualx3
    )

    #expect(snapshot.regionID == MoonMaterialMarketLocation.ualx3.regionID)
    #expect(snapshot.locationID == MoonMaterialMarketLocation.ualx3.locationID)
    #expect(
      await transport.requestedURLs.allSatisfy {
        $0.path.contains(
          "/markets/\(MoonMaterialMarketLocation.ualx3.regionID)/orders"
        )
      }
    )
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

  private func makeMoonSnapshot(
    location: MoonMaterialMarketLocation,
    price: Double
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: location.regionID,
      locationID: location.locationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        34: [
          MarketOrder(
            id: 1,
            typeID: 34,
            locationID: location.locationID,
            systemID: location.systemID,
            side: .sell,
            price: price,
            volumeRemaining: 10,
            minimumVolume: 1,
            issued: .now
          )
        ]
      ],
      source: SourceIdentity(provider: "fixture", version: "1")
    )
  }

  private func order(
    id: Int64,
    side: MarketOrderSide,
    price: Double,
    volume: Int64,
    hub: MarketTradeHub = .jita
  ) -> MarketOrder {
    MarketOrder(
      id: id,
      typeID: 34,
      locationID: hub.stationID,
      systemID: hub.systemID,
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
  private(set) var requestedURLs: [URL] = []
  private(set) var maximumConcurrentRequests = 0
  private var activeRequests = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    requestedURLs.append(request.url!)
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
