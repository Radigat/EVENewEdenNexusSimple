import Foundation

public struct TradeHubMarketService: Sendable {
  private let esi: ESIClient
  private let maximumConcurrentOrderRequests: Int

  public init(
    esi: ESIClient,
    maximumConcurrentOrderRequests: Int = 6
  ) {
    self.esi = esi
    self.maximumConcurrentOrderRequests = min(
      12,
      max(1, maximumConcurrentOrderRequests)
    )
  }

  public func orderSnapshot(
    typeIDs: Set<Int64>,
    tradeHub: MarketTradeHub = .jita
  ) async throws
    -> MarketOrderSnapshot
  {
    try await orderSnapshot(
      typeIDs: typeIDs,
      regionID: tradeHub.regionID,
      locationID: tradeHub.stationID
    )
  }

  public func orderSnapshot(
    typeIDs: Set<Int64>,
    location: MoonMaterialMarketLocation
  ) async throws -> MarketOrderSnapshot {
    try await orderSnapshot(
      typeIDs: typeIDs,
      regionID: location.regionID,
      locationID: location.locationID
    )
  }

  public func orderSnapshot(
    typeIDs: Set<Int64>,
    regionID: Int64,
    locationID: Int64
  ) async throws -> MarketOrderSnapshot {
    var ordersByType: [Int64: [MarketOrder]] = [:]
    var source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    let orderedTypeIDs = typeIDs.sorted()
    try await withThrowingTaskGroup(
      of: MarketOrderBatch.self
    ) { group in
      var nextIndex = 0
      let initialCount = min(
        maximumConcurrentOrderRequests,
        orderedTypeIDs.count
      )
      for _ in 0..<initialCount {
        let typeID = orderedTypeIDs[nextIndex]
        nextIndex += 1
        group.addTask {
          try await fetchOrders(typeID: typeID, regionID: regionID)
        }
      }

      while let batch = try await group.next() {
        try Task.checkCancellation()
        ordersByType[batch.typeID] = batch.orders
        if batch.source.capturedAt > source.capturedAt {
          source = batch.source
        }
        if nextIndex < orderedTypeIDs.count {
          let typeID = orderedTypeIDs[nextIndex]
          nextIndex += 1
          group.addTask {
            try await fetchOrders(typeID: typeID, regionID: regionID)
          }
        }
      }
    }
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: regionID,
      locationID: locationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: ordersByType,
      source: source
    )
  }

  private func fetchOrders(
    typeID: Int64,
    regionID: Int64
  ) async throws -> MarketOrderBatch {
    try Task.checkCancellation()
    let response = try await esi.getAllPages(
      [ESIMarketOrderDTO].self,
      endpoint: ESIEndpoint(
        path: "/markets/\(regionID)/orders/",
        query: [
          URLQueryItem(name: "order_type", value: "all"),
          URLQueryItem(name: "type_id", value: String(typeID)),
        ]
      )
    )
    return MarketOrderBatch(
      typeID: typeID,
      orders: response.value.map {
        MarketOrder(
          id: $0.orderID,
          typeID: $0.typeID,
          locationID: $0.locationID,
          systemID: $0.systemID,
          side: $0.isBuyOrder ? .buy : .sell,
          price: $0.price,
          volumeRemaining: $0.volumeRemain,
          minimumVolume: $0.minVolume,
          issued: $0.issued
        )
      },
      source: response.source
    )
  }

  public func adjustedPrices() async throws -> [Int64: AdjustedPrice] {
    try await adjustedPriceSnapshot().prices
  }

  public func adjustedPriceSnapshot() async throws -> ReferencePriceSnapshot {
    let response = try await esi.get(
      [ESIAdjustedPriceDTO].self,
      endpoint: ESIEndpoint(path: "/markets/prices/")
    )
    let prices = Dictionary(
      uniqueKeysWithValues: response.value.map {
        (
          $0.typeID,
          AdjustedPrice(
            typeID: $0.typeID,
            adjustedPrice: $0.adjustedPrice,
            averagePrice: $0.averagePrice
          )
        )
      })
    return ReferencePriceSnapshot(
      capturedAt: response.source.capturedAt,
      prices: prices,
      source: response.source
    )
  }

  public func industrySystems() async throws -> [IndustrySystemIndex] {
    let response = try await esi.get(
      [ESIIndustrySystemDTO].self,
      endpoint: ESIEndpoint(path: "/industry/systems/")
    )
    return response.value.flatMap { system in
      system.costIndices.compactMap { index in
        guard
          let activity =
            BlueprintActivityDefinition.Kind(
              rawValue: index.activity
            )
        else { return nil }
        return IndustrySystemIndex(
          solarSystemID: system.solarSystemID,
          activity: activity,
          costIndex: index.costIndex
        )
      }
    }
  }
}

public typealias JitaMarketService = TradeHubMarketService

private struct MarketOrderBatch: Sendable {
  let typeID: Int64
  let orders: [MarketOrder]
  let source: SourceIdentity
}
