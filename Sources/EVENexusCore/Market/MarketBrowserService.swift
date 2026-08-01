import Foundation

public struct MarketBrowserService: Sendable {
  private let esi: ESIClient
  private let universeNames: UniverseNameService
  private let maximumConcurrentRegionRequests: Int
  private let maximumConcurrentRouteRequests: Int
  private let maximumRouteSystems: Int

  public init(
    esi: ESIClient,
    universeNames: UniverseNameService? = nil,
    maximumConcurrentRegionRequests: Int = 8,
    maximumConcurrentRouteRequests: Int = 6,
    maximumRouteSystems: Int = 240
  ) {
    self.esi = esi
    self.universeNames = universeNames ?? UniverseNameService(esi: esi)
    self.maximumConcurrentRegionRequests = min(
      12,
      max(1, maximumConcurrentRegionRequests)
    )
    self.maximumConcurrentRouteRequests = min(
      8,
      max(1, maximumConcurrentRouteRequests)
    )
    self.maximumRouteSystems = min(1_000, max(0, maximumRouteSystems))
  }

  public func snapshot(
    typeID: Int64,
    itemName: String,
    originSystemID: Int64? = nil,
    originSystemName: String? = nil
  ) async throws -> Sourced<MarketBrowserSnapshot> {
    guard typeID > 0 else { throw MarketBrowserError.invalidTypeID }
    let directory = try await regionDirectory()
    let outcomes = await regionOrders(
      typeID: typeID,
      regions: directory.regions
    )
    try Task.checkCancellation()

    let successful = outcomes.compactMap { outcome -> RegionOrderBatch? in
      if case .success(let batch) = outcome { return batch }
      return nil
    }
    let failures = outcomes.compactMap {
      outcome -> MarketBrowserRegionFailure? in
      if case .failure(let failure) = outcome { return failure }
      return nil
    }.sorted { $0.regionName < $1.regionName }

    let idsToResolve = Set(
      successful.flatMap { batch in
        batch.orders.flatMap { [$0.locationID, $0.systemID] }
      }
    )
    let resolvedNames = await universeNames.names(for: idsToResolve)
    let routeResults = await routes(
      from: originSystemID,
      batches: successful
    )
    let orders = successful.flatMap { batch in
      batch.orders.map { dto in
        let route = routeResults[dto.systemID] ?? .notChecked
        return MarketBrowserOrder(
          id: dto.orderID,
          typeID: dto.typeID,
          regionID: batch.region.id,
          regionName: batch.region.name,
          locationID: dto.locationID,
          locationName: resolvedNames.value?[dto.locationID],
          systemID: dto.systemID,
          systemName: resolvedNames.value?[dto.systemID],
          side: dto.isBuyOrder ? .buy : .sell,
          price: dto.price,
          volumeRemaining: dto.volumeRemain,
          volumeTotal: dto.volumeTotal,
          minimumVolume: dto.minVolume,
          range: dto.range,
          issuedAt: dto.issued,
          expiresAt: dto.issued.addingTimeInterval(
            Double(dto.duration) * 86_400
          ),
          esiLastModifiedAt: batch.lastModifiedAt,
          observedAt: batch.source.capturedAt,
          jumps: route.jumps,
          routeState: route.state
        )
      }
    }
    let latestSource =
      successful.map(\.source).max {
        $0.capturedAt < $1.capturedAt
      } ?? directory.source
    var diagnostics = failures.map(\.diagnostic)
    diagnostics.append(contentsOf: directory.diagnostics)
    diagnostics.append(contentsOf: resolvedNames.diagnostics)
    if originSystemID != nil,
      orders.contains(where: { $0.routeState == .notChecked })
    {
      diagnostics.append("esi.market-browser.routes-partial")
    }
    diagnostics = Array(Set(diagnostics)).sorted()
    let state: DataFreshness = diagnostics.isEmpty ? .fresh : .partial
    let value = MarketBrowserSnapshot(
      typeID: typeID,
      itemName: itemName,
      originSystemID: originSystemID,
      originSystemName: originSystemName,
      capturedAt: .now,
      regionCount: directory.regions.count,
      loadedRegionCount: successful.count,
      orders: orders,
      regionFailures: failures,
      source: latestSource
    )
    return Sourced(
      state: state,
      value: value,
      source: latestSource,
      diagnostics: diagnostics
    )
  }

  private func regionDirectory() async throws -> RegionDirectory {
    let response = try await esi.get(
      [Int64].self,
      endpoint: ESIEndpoint(path: "/universe/regions")
    )
    let names = await universeNames.names(for: Set(response.value))
    let regions = response.value.filter { $0 > 0 }.map {
      MarketRegion(
        id: $0,
        name: names.value?[$0] ?? "Region \($0)"
      )
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    guard !regions.isEmpty else { throw MarketBrowserError.noRegions }
    return RegionDirectory(
      regions: regions,
      source: response.source,
      diagnostics: names.diagnostics
    )
  }

  private func regionOrders(
    typeID: Int64,
    regions: [MarketRegion]
  ) async -> [RegionOrderOutcome] {
    await withTaskGroup(
      of: (Int, RegionOrderOutcome).self,
      returning: [RegionOrderOutcome].self
    ) { group in
      var outcomes = [RegionOrderOutcome?](
        repeating: nil,
        count: regions.count
      )
      var nextIndex = 0

      func addNext() {
        guard nextIndex < regions.count else { return }
        let index = nextIndex
        let region = regions[index]
        nextIndex += 1
        group.addTask {
          do {
            let response = try await esi.getAllPages(
              [ESIMarketOrderDTO].self,
              endpoint: ESIEndpoint(
                path: "/markets/\(region.id)/orders/",
                query: [
                  URLQueryItem(name: "order_type", value: "all"),
                  URLQueryItem(name: "type_id", value: String(typeID)),
                ]
              )
            )
            return (
              index,
              .success(
                RegionOrderBatch(
                  region: region,
                  orders: response.value,
                  lastModifiedAt: Self.httpDate(response.lastModified),
                  source: response.source
                )
              )
            )
          } catch is CancellationError {
            return (
              index,
              .failure(
                MarketBrowserRegionFailure(
                  regionID: region.id,
                  regionName: region.name,
                  diagnostic: "esi.market-browser.cancelled"
                )
              )
            )
          } catch {
            return (
              index,
              .failure(
                MarketBrowserRegionFailure(
                  regionID: region.id,
                  regionName: region.name,
                  diagnostic: Self.regionDiagnostic(error)
                )
              )
            )
          }
        }
      }

      for _ in 0..<min(maximumConcurrentRegionRequests, regions.count) {
        addNext()
      }
      while let (index, outcome) = await group.next() {
        outcomes[index] = outcome
        addNext()
      }
      return outcomes.compactMap { $0 }
    }
  }

  private func routes(
    from originSystemID: Int64?,
    batches: [RegionOrderBatch]
  ) async -> [Int64: RouteResult] {
    guard let originSystemID, originSystemID > 0,
      maximumRouteSystems > 0
    else { return [:] }
    let allOrders = batches.flatMap(\.orders)
    let priorityOrders =
      allOrders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }
      + allOrders.filter(\.isBuyOrder).sorted { $0.price > $1.price }
    var seen = Set<Int64>()
    let systems = priorityOrders.compactMap { order -> Int64? in
      guard seen.insert(order.systemID).inserted else { return nil }
      return order.systemID
    }.prefix(maximumRouteSystems)
    return await withTaskGroup(
      of: (Int64, RouteResult).self,
      returning: [Int64: RouteResult].self
    ) { group in
      let accepted = Array(systems)
      var results: [Int64: RouteResult] = [
        originSystemID: .reachable(jumps: 0)
      ]
      var nextIndex = 0

      func addNext() {
        guard nextIndex < accepted.count else { return }
        let destination = accepted[nextIndex]
        nextIndex += 1
        group.addTask {
          if destination == originSystemID {
            return (destination, .reachable(jumps: 0))
          }
          do {
            let response = try await esi.post(
              [Int64].self,
              endpoint: ESIEndpoint(
                path: "/route/\(originSystemID)/\(destination)"
              ),
              body: ESIRouteRequest()
            )
            return (
              destination,
              .reachable(jumps: max(0, response.value.count - 1))
            )
          } catch let error as ESIError where error == .notFound {
            return (destination, .unreachable)
          } catch {
            return (destination, .notChecked)
          }
        }
      }

      for _ in 0..<min(maximumConcurrentRouteRequests, accepted.count) {
        addNext()
      }
      while let (systemID, result) = await group.next() {
        results[systemID] = result
        addNext()
      }
      return results
    }
  }

  private static func regionDiagnostic(_ error: Error) -> String {
    guard let error = error as? ESIError else {
      return "esi.market-browser.region-unavailable"
    }
    switch error {
    case .decoding:
      return "esi.market-browser.region-schema-mismatch"
    case .rateLimited:
      return "esi.market-browser.rate-limited"
    case .forbidden, .authorizationRequired, .missingScope:
      return "esi.market-browser.region-forbidden"
    case .cancelled:
      return "esi.market-browser.cancelled"
    default:
      return "esi.market-browser.region-unavailable"
    }
  }

  private static func httpDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }
}

public enum MarketBrowserError: Error, Equatable, Sendable {
  case invalidTypeID
  case noRegions
}

private struct MarketRegion: Sendable {
  let id: Int64
  let name: String
}

private struct RegionDirectory: Sendable {
  let regions: [MarketRegion]
  let source: SourceIdentity
  let diagnostics: [String]
}

private struct RegionOrderBatch: Sendable {
  let region: MarketRegion
  let orders: [ESIMarketOrderDTO]
  let lastModifiedAt: Date?
  let source: SourceIdentity
}

private enum RegionOrderOutcome: Sendable {
  case success(RegionOrderBatch)
  case failure(MarketBrowserRegionFailure)
}

private enum RouteResult: Sendable {
  case reachable(jumps: Int)
  case unreachable
  case notChecked

  var jumps: Int? {
    if case .reachable(let jumps) = self { return jumps }
    return nil
  }

  var state: MarketBrowserRouteState {
    switch self {
    case .reachable: .reachable
    case .unreachable: .unreachable
    case .notChecked: .notChecked
    }
  }
}

private struct ESIRouteRequest: Encodable, Sendable {
  let preference = "Shorter"
  let securityPenalty = 50

  enum CodingKeys: String, CodingKey {
    case preference
    case securityPenalty = "security_penalty"
  }
}
