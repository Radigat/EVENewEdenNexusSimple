import Foundation
import Testing

@testable import EVENexusCore

@Suite("Cross-region market browser")
struct MarketBrowserTests {
  @Test
  func preservesOrderFieldsAndReportsUnavailableRegionsAsPartial() async throws {
    let transport = MarketBrowserFixtureTransport()
    let service = MarketBrowserService(
      esi: ESIClient(transport: transport),
      maximumConcurrentRegionRequests: 2,
      maximumConcurrentRouteRequests: 2,
      maximumRouteSystems: 10
    )

    let sourced = try await service.snapshot(
      typeID: 34,
      itemName: "Tritanium",
      originSystemID: 30_000_001,
      originSystemName: "Origin"
    )
    let snapshot = try #require(sourced.value)

    #expect(sourced.state == .partial)
    #expect(snapshot.regionCount == 2)
    #expect(snapshot.loadedRegionCount == 1)
    #expect(snapshot.regionFailures.map(\.regionID) == [10_000_002])
    #expect(snapshot.orders.count == 2)

    let sell = try #require(snapshot.orders.first { $0.side == .sell })
    #expect(sell.regionName == "Alpha Region")
    #expect(sell.locationName == "Alpha Trade Station")
    #expect(sell.systemName == "Alpha System")
    #expect(sell.volumeRemaining == 25)
    #expect(sell.volumeTotal == 100)
    #expect(sell.minimumVolume == 1)
    #expect(sell.range == "station")
    #expect(sell.jumps == 2)
    #expect(sell.routeState == .reachable)
    #expect(sell.esiLastModifiedAt != nil)
    #expect(snapshot.summary.bestSellPrice == 5.5)
    #expect(snapshot.summary.bestBuyPrice == 5.0)
    #expect(snapshot.summary.activeSellVolume == 25)
    #expect(snapshot.summary.activeBuyVolume == 40)
  }

  @Test
  func routesNotRequestedRemainUnknownInsteadOfZero() async throws {
    let service = MarketBrowserService(
      esi: ESIClient(transport: MarketBrowserFixtureTransport()),
      maximumRouteSystems: 0
    )

    let sourced = try await service.snapshot(
      typeID: 34,
      itemName: "Tritanium",
      originSystemID: 30_000_001,
      originSystemName: "Origin"
    )
    let orders = try #require(sourced.value?.orders)

    #expect(orders.allSatisfy { $0.jumps == nil })
    #expect(orders.allSatisfy { $0.routeState == .notChecked })
  }

  @Test
  func filterKeepsUncheckedRoutesByDefaultAndCanExcludeThemExplicitly() {
    let unchecked = order(
      id: 1,
      locationID: 1_000_000_000_001,
      routeState: .notChecked,
      jumps: nil
    )
    var filter = MarketBrowserFilter()
    filter.maximumJumps = 10

    #expect(filter.accepts(unchecked))

    filter.includesUncheckedRoutes = false
    #expect(!filter.accepts(unchecked))

    filter.maximumJumps = nil
    filter.includesUncheckedRoutes = true
    filter.includesPlayerStructures = false
    #expect(!filter.accepts(unchecked))
  }

  @Test
  func summaryUsesVolumeWeightedActiveSellPrice() {
    let summary = MarketBrowserSummary.calculate(
      orders: [
        order(id: 1, price: 10, volume: 1),
        order(id: 2, price: 20, volume: 3),
      ]
    )

    #expect(summary.bestSellPrice == 10)
    #expect(summary.weightedAverageSellPrice == 17.5)
    #expect(summary.activeSellVolume == 4)
  }

  private func order(
    id: Int64,
    locationID: Int64 = 60_000_001,
    price: Double = 10,
    volume: Int64 = 1,
    routeState: MarketBrowserRouteState = .reachable,
    jumps: Int? = 1
  ) -> MarketBrowserOrder {
    MarketBrowserOrder(
      id: id,
      typeID: 34,
      regionID: 10_000_001,
      regionName: "Alpha Region",
      locationID: locationID,
      locationName: nil,
      systemID: 30_000_002,
      systemName: nil,
      side: .sell,
      price: price,
      volumeRemaining: volume,
      volumeTotal: volume,
      minimumVolume: 1,
      range: "station",
      issuedAt: .now,
      expiresAt: .now.addingTimeInterval(86_400),
      esiLastModifiedAt: nil,
      observedAt: .now,
      jumps: jumps,
      routeState: routeState
    )
  }
}

private actor MarketBrowserFixtureTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = request.url!
    var body: String
    var status: Int

    switch (request.httpMethod ?? "GET", url.path) {
    case ("GET", "/universe/regions"):
      body = "[10000001,10000002]"
      status = 200
    case ("POST", "/universe/names"):
      let ids = try JSONDecoder().decode([Int64].self, from: request.httpBody ?? Data())
      let names: [String: String] = [
        "10000001": "Alpha Region",
        "10000002": "Unavailable Region",
        "60000001": "Alpha Trade Station",
        "30000002": "Alpha System",
      ]
      body = ids.compactMap { id -> String? in
        guard let name = names[String(id)] else { return nil }
        let category = id >= 60_000_000 ? "station" : "solar_system"
        return "{\"category\":\"\(category)\",\"id\":\(id),\"name\":\"\(name)\"}"
      }.joined(separator: ",")
      body = "[\(body)]"
      status = 200
    case ("GET", "/markets/10000001/orders"):
      body = """
        [
          {
            "duration": 30,
            "is_buy_order": false,
            "issued": "2026-07-30T10:00:00Z",
            "location_id": 60000001,
            "min_volume": 1,
            "order_id": 9001,
            "price": 5.5,
            "range": "station",
            "system_id": 30000002,
            "type_id": 34,
            "volume_remain": 25,
            "volume_total": 100
          },
          {
            "duration": 30,
            "is_buy_order": true,
            "issued": "2026-07-30T10:00:00Z",
            "location_id": 60000001,
            "min_volume": 5,
            "order_id": 9002,
            "price": 5.0,
            "range": "region",
            "system_id": 30000002,
            "type_id": 34,
            "volume_remain": 40,
            "volume_total": 80
          }
        ]
        """
      status = 200
    case ("GET", "/markets/10000002/orders"):
      body = "{\"error\":\"fixture unavailable\"}"
      status = 500
    case ("POST", "/route/30000001/30000002"):
      body = "[30000001,30000003,30000002]"
      status = 200
    default:
      body = "{\"error\":\"unexpected fixture request\"}"
      status = 404
    }

    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Expires": "Sat, 01 Aug 2027 20:00:00 GMT",
          "Last-Modified": "Sat, 01 Aug 2026 17:00:00 GMT",
          "X-Pages": "1",
        ]
      )!
    )
  }
}
