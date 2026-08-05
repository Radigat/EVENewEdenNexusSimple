import Foundation

public struct PlayerStructureOption: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: Int64
  public let name: String
  public let ownerCorporationID: Int64
  public let solarSystemID: Int64
  public let regionID: Int64?
  public let typeID: Int64?
  public let source: SourceIdentity

  public init(
    id: Int64,
    name: String,
    ownerCorporationID: Int64,
    solarSystemID: Int64,
    regionID: Int64? = nil,
    typeID: Int64?,
    source: SourceIdentity
  ) {
    self.id = id
    self.name = name
    self.ownerCorporationID = ownerCorporationID
    self.solarSystemID = solarSystemID
    self.regionID = regionID
    self.typeID = typeID
    self.source = source
  }
}

private struct ESIStructureSearchResult: Decodable, Sendable {
  let structure: [Int64]?
}

private struct ESIPlayerStructureDetails: Decodable, Sendable {
  let name: String
  let ownerID: Int64
  let solarSystemID: Int64
  let typeID: Int64?

  enum CodingKeys: String, CodingKey {
    case name
    case ownerID = "owner_id"
    case solarSystemID = "solar_system_id"
    case typeID = "type_id"
  }
}

private enum StructureResolutionOutcome: Sendable {
  case resolved(PlayerStructureOption)
  case inaccessible
  case unavailable
}

public actor PlayerStructureSearchService {
  public static let searchScope = "esi-search.search_structures.v1"
  public static let detailScope = "esi-universe.read_structures.v1"
  public static let assetScope = "esi-assets.read_assets.v1"
  public static let industryJobsScope =
    "esi-industry.read_character_jobs.v1"
  public static let marketOrdersScope =
    "esi-markets.read_character_orders.v1"
  public static let maximumResolvedStructureCount = 500
  public static let maximumConcurrentStructureRequests = 6

  private let esi: ESIClient
  private struct SearchCacheKey: Hashable {
    let query: String
    let solarSystemID: Int64?
    let characterID: Int64
  }

  private struct SearchCacheEntry: Sendable {
    let expiresAt: Date
    let snapshot: Sourced<[PlayerStructureOption]>
  }

  private var searchCache: [SearchCacheKey: SearchCacheEntry] = [:]

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func search(
    query: String,
    solarSystemID: Int64,
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> Sourced<[PlayerStructureOption]> {
    try await search(
      query: query,
      restrictingToSolarSystemID: solarSystemID,
      characterID: characterID,
      lease: lease
    )
  }

  public func search(
    query: String,
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> Sourced<[PlayerStructureOption]> {
    try await search(
      query: query,
      restrictingToSolarSystemID: nil,
      characterID: characterID,
      lease: lease
    )
  }

  private func search(
    query: String,
    restrictingToSolarSystemID solarSystemID: Int64?,
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> Sourced<[PlayerStructureOption]> {
    let accepted = query.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard accepted.count >= 3 else {
      return Sourced(
        state: .fresh,
        value: [],
        source: SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate
        ),
        diagnostics: ["esi.structure-search.minimum-three-characters"]
      )
    }
    let cacheKey = SearchCacheKey(
      query: accepted.lowercased(),
      solarSystemID: solarSystemID,
      characterID: characterID
    )
    if let cached = searchCache[cacheKey], cached.expiresAt > .now {
      return cached.snapshot
    }
    let search = try await esi.get(
      ESIStructureSearchResult.self,
      endpoint: ESIEndpoint(
        path: "/characters/\(characterID)/search",
        query: [
          URLQueryItem(name: "categories", value: "structure"),
          URLQueryItem(name: "search", value: accepted),
          URLQueryItem(name: "strict", value: "false"),
        ],
        requiresAuthorization: true,
        requiredScope: Self.searchScope
      ),
      lease: lease
    )
    let structureIDs = Array((search.value.structure ?? []).prefix(50))
    var values: [PlayerStructureOption] = []
    var inaccessible = 0
    for structureID in structureIDs {
      try Task.checkCancellation()
      do {
        let detail = try await esi.get(
          ESIPlayerStructureDetails.self,
          endpoint: ESIEndpoint(
            path: "/universe/structures/\(structureID)",
            requiresAuthorization: true,
            requiredScope: Self.detailScope
          ),
          lease: lease
        )
        if let solarSystemID,
          detail.value.solarSystemID != solarSystemID
        {
          continue
        }
        values.append(
          PlayerStructureOption(
            id: structureID,
            name: detail.value.name,
            ownerCorporationID: detail.value.ownerID,
            solarSystemID: detail.value.solarSystemID,
            typeID: detail.value.typeID,
            source: detail.source
          )
        )
      } catch ESIError.forbidden {
        inaccessible += 1
      } catch ESIError.notFound {
        inaccessible += 1
      }
    }
    values.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let snapshot = Sourced(
      state: inaccessible > 0 ? .partial : .fresh,
      value: values,
      source: search.source,
      diagnostics:
        inaccessible > 0
        ? ["esi.structure-search.inaccessible:\(inaccessible)"] : []
    )
    if searchCache.count >= 128 {
      searchCache = searchCache.filter { $0.value.expiresAt > .now }
      if searchCache.count >= 128 { searchCache.removeAll(keepingCapacity: true) }
    }
    searchCache[cacheKey] = SearchCacheEntry(
      expiresAt: .now.addingTimeInterval(300),
      snapshot: snapshot
    )
    return snapshot
  }

  /// ESI does not expose a complete list of every structure on which a
  /// character appears in the docking ACL. This method instead discovers
  /// structure candidates from locations the character has demonstrably used:
  /// assets, industry jobs, and market orders. Each candidate is then verified
  /// through the ACL-protected universe structure endpoint.
  public func discoverKnownStructures(
    solarSystemID: Int64,
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> Sourced<[PlayerStructureOption]> {
    guard lease.scopes.contains(Self.detailScope) else {
      throw ESIError.missingScope(Self.detailScope)
    }

    var candidateIDs = Set<Int64>()
    var diagnostics: [String] = []
    var successfulSources = 0

    if lease.scopes.contains(Self.assetScope) {
      do {
        let response = try await esi.getAllPages(
          [ESIAssetDTO].self,
          endpoint: ESIEndpoint(
            path: "/characters/\(characterID)/assets",
            requiresAuthorization: true,
            requiredScope: Self.assetScope
          ),
          lease: lease
        )
        successfulSources += 1
        candidateIDs.formUnion(
          response.value.lazy
            .filter {
              $0.locationType == "other"
                || $0.locationID
                  >= AssetLocationKind.minimumPlayerStructureID
            }
            .map(\.locationID)
        )
      } catch {
        diagnostics.append("esi.structure-discovery.assets-unavailable")
      }
    } else {
      diagnostics.append("esi.structure-discovery.assets-scope-missing")
    }

    if lease.scopes.contains(Self.industryJobsScope) {
      do {
        let response = try await esi.getAllPages(
          [ESIIndustryJobDTO].self,
          endpoint: ESIEndpoint(
            path: "/characters/\(characterID)/industry/jobs",
            query: [
              URLQueryItem(name: "include_completed", value: "true")
            ],
            requiresAuthorization: true,
            requiredScope: Self.industryJobsScope
          ),
          lease: lease
        )
        successfulSources += 1
        candidateIDs.formUnion(response.value.map(\.facilityID))
      } catch {
        diagnostics.append("esi.structure-discovery.jobs-unavailable")
      }
    } else {
      diagnostics.append("esi.structure-discovery.jobs-scope-missing")
    }

    if lease.scopes.contains(Self.marketOrdersScope) {
      do {
        async let openOrders = esi.getAllPages(
          [ESICharacterOrderDTO].self,
          endpoint: ESIEndpoint(
            path: "/characters/\(characterID)/orders",
            requiresAuthorization: true,
            requiredScope: Self.marketOrdersScope
          ),
          lease: lease
        )
        async let orderHistory = esi.getAllPages(
          [ESICharacterOrderDTO].self,
          endpoint: ESIEndpoint(
            path: "/characters/\(characterID)/orders/history",
            requiresAuthorization: true,
            requiredScope: Self.marketOrdersScope
          ),
          lease: lease
        )
        let responses = try await (openOrders, orderHistory)
        successfulSources += 1
        candidateIDs.formUnion(responses.0.value.map(\.locationID))
        candidateIDs.formUnion(responses.1.value.map(\.locationID))
      } catch {
        diagnostics.append("esi.structure-discovery.orders-unavailable")
      }
    } else {
      diagnostics.append("esi.structure-discovery.orders-scope-missing")
    }

    var values: [PlayerStructureOption] = []
    var inaccessible = 0
    for structureID in candidateIDs.sorted() {
      try Task.checkCancellation()
      do {
        let detail = try await structureDetails(
          structureID: structureID,
          lease: lease
        )
        guard detail.value.solarSystemID == solarSystemID else { continue }
        values.append(
          option(
            structureID: structureID,
            detail: detail
          )
        )
      } catch ESIError.notFound {
        // NPC stations and stale location IDs are expected among location
        // candidates and are not player structures.
        continue
      } catch ESIError.forbidden {
        inaccessible += 1
      }
    }

    if inaccessible > 0 {
      diagnostics.append(
        "esi.structure-discovery.inaccessible:\(inaccessible)"
      )
    }
    values.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let state: DataFreshness =
      successfulSources == 0
      ? .unavailable
      : diagnostics.isEmpty ? .fresh : .partial
    return Sourced(
      state: state,
      value: successfulSources == 0 ? nil : values,
      source: SourceIdentity(
        provider: "ESI",
        version: EVEConstants.esiCompatibilityDate
      ),
      diagnostics: diagnostics
    )
  }

  /// Resolves structure IDs already present in an asset snapshot. Missing
  /// scope, docking ACL, stale IDs, and individual failures remain explicit;
  /// they never remove the corresponding asset location from the warehouse.
  public func resolveKnownStructures(
    structureIDs: Set<Int64>,
    lease: AccessTokenLease
  ) async -> Sourced<[PlayerStructureOption]> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard !structureIDs.isEmpty else {
      return Sourced(
        state: .fresh,
        value: [],
        source: source
      )
    }
    guard lease.scopes.contains(Self.detailScope) else {
      return Sourced(
        state: .forbidden,
        value: nil,
        source: source,
        diagnostics: [
          "esi.structure-resolution.scope-missing:\(Self.detailScope)"
        ]
      )
    }

    let sortedIDs = structureIDs.sorted()
    let acceptedIDs = Array(
      sortedIDs.prefix(Self.maximumResolvedStructureCount)
    )
    var values: [PlayerStructureOption] = []
    var inaccessible = 0
    var unavailable = 0
    var wasCancelled = false
    let esi = self.esi
    for start in stride(
      from: 0,
      to: acceptedIDs.count,
      by: Self.maximumConcurrentStructureRequests
    ) {
      if Task.isCancelled {
        wasCancelled = true
        break
      }
      let end = min(
        start + Self.maximumConcurrentStructureRequests,
        acceptedIDs.count
      )
      let batch = acceptedIDs[start..<end]
      let outcomes = await withTaskGroup(
        of: StructureResolutionOutcome.self,
        returning: [StructureResolutionOutcome].self
      ) { group in
        for structureID in batch {
          group.addTask {
            do {
              let detail = try await esi.get(
                ESIPlayerStructureDetails.self,
                endpoint: ESIEndpoint(
                  path: "/universe/structures/\(structureID)",
                  requiresAuthorization: true,
                  requiredScope: Self.detailScope
                ),
                lease: lease
              )
              return .resolved(
                PlayerStructureOption(
                  id: structureID,
                  name: detail.value.name,
                  ownerCorporationID: detail.value.ownerID,
                  solarSystemID: detail.value.solarSystemID,
                  typeID: detail.value.typeID,
                  source: detail.source
                )
              )
            } catch ESIError.forbidden {
              return .inaccessible
            } catch ESIError.notFound {
              return .inaccessible
            } catch {
              return .unavailable
            }
          }
        }
        var collected: [StructureResolutionOutcome] = []
        for await outcome in group {
          collected.append(outcome)
        }
        return collected
      }
      for outcome in outcomes {
        switch outcome {
        case .resolved(let option): values.append(option)
        case .inaccessible: inaccessible += 1
        case .unavailable: unavailable += 1
        }
      }
    }

    var diagnostics: [String] = []
    if sortedIDs.count > acceptedIDs.count {
      diagnostics.append(
        "esi.structure-resolution.limit:\(acceptedIDs.count)/\(sortedIDs.count)"
      )
    }
    if inaccessible > 0 {
      diagnostics.append(
        "esi.structure-resolution.inaccessible:\(inaccessible)"
      )
    }
    if unavailable > 0 {
      diagnostics.append(
        "esi.structure-resolution.unavailable:\(unavailable)"
      )
    }
    if wasCancelled {
      diagnostics.append("esi.structure-resolution.cancelled")
    }
    values.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    return Sourced(
      state: diagnostics.isEmpty ? .fresh : .partial,
      value: values,
      source: values.first?.source ?? source,
      diagnostics: diagnostics
    )
  }

  private func structureDetails(
    structureID: Int64,
    lease: AccessTokenLease
  ) async throws -> ESIResponse<ESIPlayerStructureDetails> {
    try await esi.get(
      ESIPlayerStructureDetails.self,
      endpoint: ESIEndpoint(
        path: "/universe/structures/\(structureID)",
        requiresAuthorization: true,
        requiredScope: Self.detailScope
      ),
      lease: lease
    )
  }

  private func option(
    structureID: Int64,
    detail: ESIResponse<ESIPlayerStructureDetails>
  ) -> PlayerStructureOption {
    PlayerStructureOption(
      id: structureID,
      name: detail.value.name,
      ownerCorporationID: detail.value.ownerID,
      solarSystemID: detail.value.solarSystemID,
      typeID: detail.value.typeID,
      source: detail.source
    )
  }
}

public struct TradingLocationSearchOption: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: Int64
  public let name: String
  public let solarSystemID: Int64
  public let regionID: Int64?
  public let ownerCorporationID: Int64
  public let ownerFactionID: Int64?
  public let source: SourceIdentity

  public init(
    id: Int64,
    name: String,
    solarSystemID: Int64,
    regionID: Int64? = nil,
    ownerCorporationID: Int64,
    ownerFactionID: Int64?,
    source: SourceIdentity
  ) {
    self.id = id
    self.name = name
    self.solarSystemID = solarSystemID
    self.regionID = regionID
    self.ownerCorporationID = ownerCorporationID
    self.ownerFactionID = ownerFactionID
    self.source = source
  }

  public var procurementLocation: ProcurementLocation {
    ProcurementLocation(
      id: "npc:\(id)",
      name: name,
      locationID: id,
      kind: .npcTradeHub,
      solarSystemID: solarSystemID,
      regionID: regionID,
      ownerCorporationID: ownerCorporationID,
      ownerFactionID: ownerFactionID
    )
  }
}

private struct ESIStationSearchResult: Decodable, Sendable {
  let station: [Int64]?
}

private struct ESIStationDetails: Decodable, Sendable {
  let name: String
  let ownerCorporationID: Int64
  let solarSystemID: Int64

  private enum CodingKeys: String, CodingKey {
    case name
    case ownerCorporationID = "owner"
    case solarSystemID = "system_id"
  }
}

private struct ESICorporationFaction: Decodable, Sendable {
  let factionID: Int64?

  private enum CodingKeys: String, CodingKey {
    case factionID = "faction_id"
  }
}

public actor TradingLocationSearchService {
  public static let maximumResultCount = 50
  public static let maximumConcurrentRequests = 6

  private let esi: ESIClient
  private var cachedSystemStations: [Int64: Sourced<[TradingLocationSearchOption]>] = [:]

  public init(esi: ESIClient) {
    self.esi = esi
  }

  /// Loads only the NPC stations listed by the selected solar-system route.
  /// Player Structures are intentionally not inferred from an empty station
  /// list because ESI exposes those through separate, authorization-dependent
  /// routes.
  public func stations(
    inSolarSystemID solarSystemID: Int64,
    force: Bool = false
  ) async throws -> Sourced<[TradingLocationSearchOption]> {
    guard solarSystemID > 0 else {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate
        ),
        diagnostics: ["esi.system-stations.invalid-system"]
      )
    }
    if !force, let cached = cachedSystemStations[solarSystemID] {
      return cached
    }
    let system = try await SolarSystemSearchService(esi: esi).details(
      systemID: solarSystemID
    )
    var options: [TradingLocationSearchOption] = []
    var unavailable = 0
    for start in stride(
      from: 0,
      to: system.stationIDs.count,
      by: Self.maximumConcurrentRequests
    ) {
      let end = min(
        start + Self.maximumConcurrentRequests,
        system.stationIDs.count
      )
      let results = await withTaskGroup(
        of: TradingLocationSearchOption?.self,
        returning: [TradingLocationSearchOption?].self
      ) { group in
        for stationID in system.stationIDs[start..<end] {
          group.addTask {
            try? await self.resolveNPCStation(stationID: stationID)
          }
        }
        var values: [TradingLocationSearchOption?] = []
        for await value in group { values.append(value) }
        return values
      }
      unavailable += results.filter { $0 == nil }.count
      options.append(contentsOf: results.compactMap { $0 })
    }
    options.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let snapshot = Sourced(
      state: unavailable == 0 ? .fresh : .partial,
      value: options,
      source: system.source,
      diagnostics:
        unavailable == 0
        ? [] : ["esi.system-stations.unavailable:\(unavailable)"]
    )
    cachedSystemStations[solarSystemID] = snapshot
    return snapshot
  }

  public func searchNPCStations(
    query: String
  ) async throws -> Sourced<[TradingLocationSearchOption]> {
    let accepted = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else {
      return Sourced(
        state: .fresh,
        value: [],
        source: SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate
        ),
        diagnostics: ["esi.station-search.minimum-three-characters"]
      )
    }
    let response = try await esi.get(
      ESIStationSearchResult.self,
      endpoint: ESIEndpoint(
        path: "/search/",
        query: [
          URLQueryItem(name: "categories", value: "station"),
          URLQueryItem(name: "search", value: accepted),
          URLQueryItem(name: "strict", value: "false"),
        ]
      )
    )
    let stationIDs = Array(
      (response.value.station ?? []).prefix(Self.maximumResultCount)
    )
    var options: [TradingLocationSearchOption] = []
    var unavailable = 0
    for start in stride(
      from: 0,
      to: stationIDs.count,
      by: Self.maximumConcurrentRequests
    ) {
      let end = min(
        start + Self.maximumConcurrentRequests,
        stationIDs.count
      )
      let results = await withTaskGroup(
        of: TradingLocationSearchOption?.self,
        returning: [TradingLocationSearchOption?].self
      ) { group in
        for stationID in stationIDs[start..<end] {
          group.addTask {
            try? await self.resolveNPCStation(stationID: stationID)
          }
        }
        var values: [TradingLocationSearchOption?] = []
        for await value in group { values.append(value) }
        return values
      }
      unavailable += results.filter { $0 == nil }.count
      options.append(contentsOf: results.compactMap { $0 })
    }
    options.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    return Sourced(
      state: unavailable == 0 ? .fresh : .partial,
      value: options,
      source: response.source,
      diagnostics:
        unavailable == 0
        ? [] : ["esi.station-search.unavailable:\(unavailable)"]
    )
  }

  public func resolveNPCStation(
    stationID: Int64
  ) async throws -> TradingLocationSearchOption {
    let station = try await esi.get(
      ESIStationDetails.self,
      endpoint: ESIEndpoint(path: "/universe/stations/\(stationID)/")
    )
    let corporation = try? await esi.get(
      ESICorporationFaction.self,
      endpoint: ESIEndpoint(
        path: "/corporations/\(station.value.ownerCorporationID)/"
      )
    )
    let knownStation = ProcurementLocation.standardTradeHubs.first {
      $0.locationID == stationID
        && $0.ownerCorporationID == station.value.ownerCorporationID
    }
    let system = try? await SolarSystemSearchService(esi: esi).details(
      systemID: station.value.solarSystemID
    )
    return TradingLocationSearchOption(
      id: stationID,
      name: station.value.name,
      solarSystemID: station.value.solarSystemID,
      regionID: system?.regionID ?? knownStation?.regionID,
      ownerCorporationID: station.value.ownerCorporationID,
      ownerFactionID:
        corporation?.value.factionID ?? knownStation?.ownerFactionID,
      source: station.source
    )
  }
}
