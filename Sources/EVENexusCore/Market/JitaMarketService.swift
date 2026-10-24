import Foundation

public struct TradeHubMarketService: Sendable {
  public static let structureMarketScope =
    "esi-markets.structure_markets.v1"
  public static let structureMarketProvider = "ESI Player Structure Market"

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

  /// Loads the public regional order book once and retains only orders at the
  /// requested NPC station. This is intended for an explicit, cancellable
  /// catalog-wide scan; callers must surface progress because large regions can
  /// contain many pages.
  public func locationOrderSnapshot(
    regionID: Int64,
    locationID: Int64,
    progress:
      @escaping @Sendable (_ completedPages: Int, _ totalPages: Int) async
      -> Void = { _, _ in }
  ) async throws -> MarketOrderSnapshot {
    let endpoint = ESIEndpoint(
      path: "/markets/\(regionID)/orders/",
      query: [URLQueryItem(name: "order_type", value: "all")]
    )
    do {
      return try await readLocationOrders(
        endpoint: endpoint,
        regionID: regionID,
        locationID: locationID,
        progress: progress
      )
    } catch let change as ESIPageSnapshotChange {
      // ESI refreshed the order book during the read. Re-read once; pages of
      // the new snapshot come from the cache.
      await esi.removeCachedPages(
        of: endpoint,
        pageCount: change.pageCount,
        exceptLastModified: change.currentLastModified
      )
      do {
        return try await readLocationOrders(
          endpoint: endpoint,
          regionID: regionID,
          locationID: locationID,
          progress: progress
        )
      } catch is ESIPageSnapshotChange {
        throw ESIError.invalidPagination
      }
    }
  }

  private func readLocationOrders(
    endpoint: ESIEndpoint,
    regionID: Int64,
    locationID: Int64,
    progress: @escaping @Sendable (Int, Int) async -> Void
  ) async throws -> MarketOrderSnapshot {
    let first = try await esi.firstPage(
      [ESIMarketOrderDTO].self,
      endpoint: endpoint
    )
    let pageCount = max(first.pages ?? 1, 1)
    var ordersByType: [Int64: [MarketOrder]] = [:]

    func append(_ values: [ESIMarketOrderDTO]) {
      for order in values where order.locationID == locationID {
        ordersByType[order.typeID, default: []].append(
          MarketOrder(
            id: order.orderID,
            typeID: order.typeID,
            locationID: order.locationID,
            systemID: order.systemID,
            side: order.isBuyOrder ? .buy : .sell,
            price: order.price,
            volumeRemaining: order.volumeRemain,
            minimumVolume: order.minVolume,
            issued: order.issued
          )
        )
      }
    }

    append(first.value)
    await progress(1, pageCount)
    // Pages 2…n load concurrently; filtering and progress follow page order.
    let esi = esi
    try await ESIOrderedLoader.load(
      count: pageCount - 1,
      load: { index in
        try await esi.get(
          [ESIMarketOrderDTO].self,
          endpoint: ESIClient.pageEndpoint(endpoint, page: index + 2)
        )
      },
      deliver: { index, response in
        if let reportedPages = response.pages, reportedPages != pageCount {
          throw ESIError.invalidPagination
        }
        try ESIPageSnapshotChange.check(
          response.lastModified,
          firstPage: first.lastModified,
          pageCount: pageCount
        )
        append(response.value)
        await progress(index + 2, pageCount)
      }
    )
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: regionID,
      locationID: locationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: ordersByType,
      source: first.source
    )
  }

  /// Loads every page of a player-structure market. `typeIDs` keeps only the
  /// requested types and records an empty order list for each of them;
  /// `nil` keeps the complete order book of the structure (HANDEL_PLAN P3).
  public func structureOrderSnapshot(
    typeIDs: Set<Int64>?,
    regionID: Int64,
    systemID: Int64,
    structureID: Int64,
    lease: AccessTokenLease
  ) async throws -> MarketOrderSnapshot {
    try Task.checkCancellation()
    let response = try await esi.getAllPages(
      [ESIStructureMarketOrderDTO].self,
      endpoint: ESIEndpoint(
        path: "/markets/structures/\(structureID)/",
        requiresAuthorization: true,
        requiredScope: Self.structureMarketScope,
        sharesResponsesAcrossCharacters: true
      ),
      lease: lease
    )
    var ordersByType = Dictionary(
      uniqueKeysWithValues: (typeIDs ?? []).map { ($0, [MarketOrder]()) }
    )
    for order in response.value
    where typeIDs.map({ $0.contains(order.typeID) }) ?? true
      && order.locationID == structureID
    {
      ordersByType[order.typeID, default: []].append(
        MarketOrder(
          id: order.orderID,
          typeID: order.typeID,
          locationID: order.locationID,
          systemID: systemID,
          side: order.isBuyOrder ? .buy : .sell,
          price: order.price,
          volumeRemaining: order.volumeRemain,
          minimumVolume: order.minVolume,
          issued: order.issued
        )
      )
    }
    let source = SourceIdentity(
      provider: Self.structureMarketProvider,
      version: response.source.version,
      capturedAt: response.source.capturedAt,
      snapshotID: response.source.snapshotID
    )
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: regionID,
      locationID: structureID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: ordersByType,
      source: source
    )
  }

  public func orderSnapshot(
    typeIDs: Set<Int64>,
    regionID: Int64,
    locationID: Int64
  ) async throws -> MarketOrderSnapshot {
    try await regionalOrderSnapshot(
      typeIDs: typeIDs,
      regionID: regionID,
      locationID: locationID,
      orderType: "all"
    )
  }

  public func sellOrderSnapshot(
    typeIDs: Set<Int64>,
    regionID: Int64,
    locationID: Int64
  ) async throws -> MarketOrderSnapshot {
    try await regionalOrderSnapshot(
      typeIDs: typeIDs,
      regionID: regionID,
      locationID: locationID,
      orderType: "sell"
    )
  }

  private func regionalOrderSnapshot(
    typeIDs: Set<Int64>,
    regionID: Int64,
    locationID: Int64,
    orderType: String
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
          try await fetchOrders(
            typeID: typeID,
            regionID: regionID,
            locationID: locationID,
            orderType: orderType
          )
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
            try await fetchOrders(
              typeID: typeID,
              regionID: regionID,
              locationID: locationID,
              orderType: orderType
            )
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
    regionID: Int64,
    locationID: Int64,
    orderType: String
  ) async throws -> MarketOrderBatch {
    try Task.checkCancellation()
    let response = try await esi.getAllPages(
      [ESIMarketOrderDTO].self,
      endpoint: ESIEndpoint(
        path: "/markets/\(regionID)/orders/",
        query: [
          URLQueryItem(name: "order_type", value: orderType),
          URLQueryItem(name: "type_id", value: String(typeID)),
        ]
      )
    )
    return MarketOrderBatch(
      typeID: typeID,
      // The regional endpoint returns orders from every station in the
      // region. Downstream quotes are location-bound, so retaining unrelated
      // stations only increases peak memory during large plans and reaction
      // analyses.
      orders: response.value.lazy.filter {
        $0.typeID == typeID && $0.locationID == locationID
      }.map {
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

  /// Daily traded units per type in `regionID` from the public ESI market
  /// history, one request per type with bounded concurrency. A failed type is
  /// reported in `unavailableTypeIDs` and never as zero; the response cache
  /// keeps each history until its daily `Expires`.
  public func volumeHistory(
    typeIDs: Set<Int64>,
    regionID: Int64,
    progress:
      @escaping @Sendable (_ completed: Int, _ total: Int) async -> Void = {
        _,
        _ in
      }
  ) async throws -> MarketVolumeHistorySnapshot {
    let orderedTypeIDs = typeIDs.filter { $0 > 0 }.sorted()
    var snapshot = MarketVolumeHistorySnapshot(regionID: regionID)
    let limit = min(maximumConcurrentOrderRequests, 4)
    let esi = esi
    try await withThrowingTaskGroup(
      of: (Int64, MarketTypeVolumeHistory?).self
    ) { group in
      var nextIndex = 0
      var completed = 0
      func addNext() {
        guard nextIndex < orderedTypeIDs.count else { return }
        let typeID = orderedTypeIDs[nextIndex]
        nextIndex += 1
        group.addTask {
          try await Self.fetchHistory(
            typeID: typeID,
            regionID: regionID,
            esi: esi
          )
        }
      }
      for _ in 0..<min(limit, orderedTypeIDs.count) { addNext() }
      while let (typeID, history) = try await group.next() {
        try Task.checkCancellation()
        if let history {
          snapshot.historiesByType[typeID] = history
        } else {
          snapshot.unavailableTypeIDs.insert(typeID)
        }
        completed += 1
        await progress(completed, orderedTypeIDs.count)
        addNext()
      }
    }
    return snapshot
  }

  private static func fetchHistory(
    typeID: Int64,
    regionID: Int64,
    esi: ESIClient
  ) async throws -> (Int64, MarketTypeVolumeHistory?) {
    do {
      let response = try await esi.get(
        [ESIMarketHistoryDTO].self,
        endpoint: ESIEndpoint(
          path: "/markets/\(regionID)/history/",
          query: [URLQueryItem(name: "type_id", value: String(typeID))],
          rememberedFailureDuration: 24 * 60 * 60
        )
      )
      return (
        typeID,
        MarketTypeVolumeHistory.make(
          typeID: typeID,
          regionID: regionID,
          rows: response.value,
          lastModified: ESIClient.httpDate(response.lastModified),
          capturedAt: response.source.capturedAt
        )
      )
    } catch ESIError.cancelled {
      throw CancellationError()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return (typeID, nil)
    }
  }
}

public typealias JitaMarketService = TradeHubMarketService

private struct MarketOrderBatch: Sendable {
  let typeID: Int64
  let orders: [MarketOrder]
  let source: SourceIdentity
}

private struct ESIStructureMarketOrderDTO: Decodable, Sendable {
  let isBuyOrder: Bool
  let issued: Date
  let locationID: Int64
  let minVolume: Int64
  let orderID: Int64
  let price: Double
  let typeID: Int64
  let volumeRemain: Int64

  enum CodingKeys: String, CodingKey {
    case isBuyOrder = "is_buy_order"
    case issued
    case locationID = "location_id"
    case minVolume = "min_volume"
    case orderID = "order_id"
    case price
    case typeID = "type_id"
    case volumeRemain = "volume_remain"
  }
}
