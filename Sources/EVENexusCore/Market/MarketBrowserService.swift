import Foundation

public struct MarketBrowserService: Sendable {
  private let esi: ESIClient
  private let universeNames: UniverseNameService
  private let systemSecurity: SolarSystemSearchService
  private let maximumConcurrentRegionRequests: Int

  public init(
    esi: ESIClient,
    universeNames: UniverseNameService? = nil,
    systemSecurity: SolarSystemSearchService? = nil,
    maximumConcurrentRegionRequests: Int = 8
  ) {
    self.esi = esi
    self.universeNames = universeNames ?? UniverseNameService(esi: esi)
    self.systemSecurity = systemSecurity ?? SolarSystemSearchService(esi: esi)
    self.maximumConcurrentRegionRequests = min(
      12,
      max(1, maximumConcurrentRegionRequests)
    )
  }

  public func snapshot(
    typeID: Int64,
    itemName: String
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

    let allOrders = successful.flatMap(\.orders)
    let systemIDs = Set(allOrders.map(\.systemID))
    async let systemNamesValue = universeNames.names(for: systemIDs)
    async let systemSecurityValue = systemSecurity.securityStatuses(
      for: systemIDs
    )
    async let stationNamesValue = universeNames.names(
      for: Set(
        allOrders.lazy
          .map(\.locationID)
          .filter { $0 < 1_000_000_000_000 }
      )
    )
    let (systemNames, securityStatuses, stationNames) = await (
      systemNamesValue,
      systemSecurityValue,
      stationNamesValue
    )
    let resolvedNames =
      (systemNames.value ?? [:])
      .merging(stationNames.value ?? [:]) { current, _ in current }
    let orders = successful.flatMap { batch in
      batch.orders.map { dto in
        return MarketBrowserOrder(
          id: dto.orderID,
          typeID: dto.typeID,
          regionID: batch.region.id,
          regionName: batch.region.name,
          locationID: dto.locationID,
          locationName:
            resolvedNames[dto.locationID]
            ?? MarketTradeHub.matching(stationID: dto.locationID)?.name,
          systemID: dto.systemID,
          systemName: resolvedNames[dto.systemID],
          securityStatus: securityStatuses.value?[dto.systemID],
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
          observedAt: batch.source.capturedAt
        )
      }
    }
    let latestSource =
      successful.map(\.source).max {
        $0.capturedAt < $1.capturedAt
      } ?? directory.source
    var diagnostics = failures.map(\.diagnostic)
    diagnostics.append(contentsOf: directory.diagnostics)
    diagnostics.append(contentsOf: systemNames.diagnostics)
    diagnostics.append(contentsOf: stationNames.diagnostics)
    diagnostics.append(contentsOf: securityStatuses.diagnostics)
    diagnostics = Array(Set(diagnostics)).sorted()
    let state: DataFreshness = diagnostics.isEmpty ? .fresh : .partial
    let value = MarketBrowserSnapshot(
      typeID: typeID,
      itemName: itemName,
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
