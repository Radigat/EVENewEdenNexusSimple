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
  func compactOrderSummaryKeepsOnlyUsableBestPrices() throws {
    let snapshot = makeSnapshot(
      orders: [
        order(id: 1, side: .sell, price: 12, volume: 10),
        order(id: 2, side: .sell, price: 10, volume: 10),
        order(id: 3, side: .buy, price: 8, volume: 10),
        order(id: 4, side: .buy, price: 9, volume: 10),
        order(id: 5, side: .sell, price: .infinity, volume: 10),
        order(id: 6, side: .buy, price: 100, volume: 0),
        order(id: 7, side: .sell, price: 1, volume: 10, hub: .amarr),
      ]
    )

    let summary = MarketOrderSummarySnapshot(snapshot: snapshot)
    let prices = try #require(summary.pricesByType[34])

    #expect(summary.regionID == snapshot.regionID)
    #expect(summary.locationID == snapshot.locationID)
    #expect(summary.source == snapshot.source)
    #expect(prices.bestSellPrice == 10)
    #expect(prices.bestBuyPrice == 9)
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
  func regionalTypeSnapshotDiscardsOrdersFromOtherStations() async throws {
    let transport = MixedLocationMarketTransport()
    let service = TradeHubMarketService(esi: ESIClient(transport: transport))

    let snapshot = try await service.orderSnapshot(
      typeIDs: [34],
      tradeHub: .amarr
    )
    let retained = try #require(snapshot.ordersByType[34])
    let quote = MarketPriceEngine.quote(
      typeID: 34,
      quantity: 10,
      scenario: .materialBuy,
      snapshot: snapshot
    )

    #expect(retained.count == 1)
    #expect(retained.first?.locationID == MarketTradeHub.amarr.stationID)
    #expect(quote.total == 110)
  }

  @Test
  func moonMarketRegionalRequestsLoadSellOrdersOnlyPerType() async throws {
    let transport = ConcurrentMarketTransport()
    let service = TradeHubMarketService(
      esi: ESIClient(transport: transport),
      maximumConcurrentOrderRequests: 2
    )

    _ = try await service.sellOrderSnapshot(
      typeIDs: [16_634, 16_635, 16_636],
      regionID: MarketTradeHub.jita.regionID,
      locationID: MarketTradeHub.jita.stationID
    )

    #expect(await transport.requestCount == 3)
    #expect(
      await transport.requestedURLs.allSatisfy { url in
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems
        return query?.contains(
          URLQueryItem(name: "order_type", value: "sell")
        ) == true
          && query?.contains(where: { $0.name == "type_id" }) == true
      }
    )
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
    let markets: [String: Sourced<MarketOrderSnapshot>] = [
      "main": Sourced(
        state: .fresh,
        value: makeMoonSnapshot(locationID: 1, systemID: 11, price: 100),
        source: source
      ),
      "home": Sourced(
        state: .fresh,
        value: makeMoonSnapshot(locationID: 2, systemID: 12, price: 120),
        source: source
      ),
      "coalition": Sourced(
        state: .fresh,
        value: makeMoonSnapshot(locationID: 3, systemID: 13, price: 110),
        source: source
      ),
      "same-price": Sourced(
        state: .fresh,
        value: makeMoonSnapshot(locationID: 4, systemID: 14, price: 100),
        source: source
      ),
      "fourth": Sourced(
        state: .fresh,
        value: makeMoonSnapshot(locationID: 5, systemID: 15, price: 130),
        source: source
      ),
      "stale": Sourced(
        state: .stale,
        value: makeMoonSnapshot(locationID: 6, systemID: 16, price: 90),
        source: source
      ),
    ]

    let ranks = MoonMaterialMarketPriceRankAnalyzer.ranks(
      typeID: 34,
      markets: markets
    )

    #expect(ranks["main"] == .cheapest)
    #expect(ranks["same-price"] == .cheapest)
    #expect(ranks["coalition"] == .secondCheapest)
    #expect(ranks["home"] == .thirdCheapest)
    #expect(ranks["fourth"] == nil)
    #expect(ranks["stale"] == nil)
  }

  @Test
  func moonMarketLocationsUseVerifiedRegionsAndExactLocationIDs() async throws {
    let regionID: Int64 = 10_000_061
    let locationID: Int64 = 1_046_664_001_931
    #expect(MarketTradeHub.hek.regionID == 10_000_042)

    let transport = ConcurrentMarketTransport()
    let service = TradeHubMarketService(
      esi: ESIClient(transport: transport)
    )
    let snapshot = try await service.orderSnapshot(
      typeIDs: [16_634],
      regionID: regionID,
      locationID: locationID
    )

    #expect(snapshot.regionID == regionID)
    #expect(snapshot.locationID == locationID)
    #expect(
      await transport.requestedURLs.allSatisfy {
        $0.path.contains(
          "/markets/\(regionID)/orders"
        )
      }
    )
  }

  @Test
  func playerStructureMarketUsesAuthorizedEndpointAndSuppliedSystem() async throws {
    let structureID: Int64 = 1_046_664_001_931
    let regionID: Int64 = 10_000_061
    let systemID: Int64 = 30_004_807
    let transport = StructureMarketTransport(structureID: structureID)
    let service = TradeHubMarketService(esi: ESIClient(transport: transport))
    let lease = AccessTokenLease(
      characterID: 91,
      accessToken: "fixture-token",
      expiresAt: .now.addingTimeInterval(3_600),
      scopes: [TradeHubMarketService.structureMarketScope]
    )

    let snapshot = try await service.structureOrderSnapshot(
      typeIDs: [16_634],
      regionID: regionID,
      systemID: systemID,
      structureID: structureID,
      lease: lease
    )

    let order = try #require(snapshot.ordersByType[16_634]?.first)
    #expect(await transport.requestCount == 1)
    #expect(
      await transport.requestedPath
        == "/markets/structures/\(structureID)"
    )
    #expect(await transport.authorization == "Bearer fixture-token")
    #expect(order.locationID == structureID)
    #expect(order.systemID == systemID)
    #expect(order.price == 215.5)
    #expect(snapshot.ordersByType[34] == nil)
  }

  @Test
  func playerStructureMarketRejectsMissingScopeBeforeNetwork() async {
    let structureID: Int64 = 1_049_588_174_021
    let regionID: Int64 = 10_000_009
    let systemID: Int64 = 30_000_772
    let transport = StructureMarketTransport(structureID: structureID)
    let service = TradeHubMarketService(esi: ESIClient(transport: transport))
    let lease = AccessTokenLease(
      characterID: 92,
      accessToken: "fixture-token",
      expiresAt: .now.addingTimeInterval(3_600),
      scopes: []
    )

    do {
      _ = try await service.structureOrderSnapshot(
        typeIDs: [16_634],
        regionID: regionID,
        systemID: systemID,
        structureID: structureID,
        lease: lease
      )
      Issue.record("Expected the structure market scope to be required")
    } catch {
      #expect(
        error as? ESIError
          == .missingScope(TradeHubMarketService.structureMarketScope)
      )
    }
    #expect(await transport.requestCount == 0)
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
    locationID: Int64,
    systemID: Int64,
    price: Double
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: 1,
      locationID: locationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        34: [
          MarketOrder(
            id: 1,
            typeID: 34,
            locationID: locationID,
            systemID: systemID,
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

private actor StructureMarketTransport: ESIHTTPTransporting {
  let structureID: Int64
  private(set) var requestCount = 0
  private(set) var requestedPath: String?
  private(set) var authorization: String?

  init(structureID: Int64) {
    self.structureID = structureID
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    requestedPath = request.url?.path
    authorization = request.value(forHTTPHeaderField: "Authorization")
    let json = """
      [
        {
          "is_buy_order": false,
          "issued": "2026-08-01T20:00:00Z",
          "location_id": \(structureID),
          "min_volume": 1,
          "order_id": 5001,
          "price": 215.5,
          "type_id": 16634,
          "volume_remain": 400
        },
        {
          "is_buy_order": false,
          "issued": "2026-08-01T20:00:00Z",
          "location_id": \(structureID),
          "min_volume": 1,
          "order_id": 5002,
          "price": 5.0,
          "type_id": 34,
          "volume_remain": 100
        }
      ]
      """
    return (
      Data(json.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["X-Pages": "1"]
      )!
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

private actor MixedLocationMarketTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let json = """
      [
        {
          "duration": 90,
          "is_buy_order": false,
          "issued": "2026-08-01T20:00:00Z",
          "location_id": \(MarketTradeHub.jita.stationID),
          "min_volume": 1,
          "order_id": 6001,
          "price": 5.0,
          "range": "region",
          "system_id": \(MarketTradeHub.jita.systemID),
          "type_id": 34,
          "volume_remain": 100,
          "volume_total": 100
        },
        {
          "duration": 90,
          "is_buy_order": false,
          "issued": "2026-08-01T20:00:00Z",
          "location_id": \(MarketTradeHub.amarr.stationID),
          "min_volume": 1,
          "order_id": 6002,
          "price": 11.0,
          "range": "region",
          "system_id": \(MarketTradeHub.amarr.systemID),
          "type_id": 34,
          "volume_remain": 100,
          "volume_total": 100
        }
      ]
      """
    return (
      Data(json.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["X-Pages": "1"]
      )!
    )
  }
}
