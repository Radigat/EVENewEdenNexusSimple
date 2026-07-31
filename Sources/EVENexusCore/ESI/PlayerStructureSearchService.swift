import Foundation

public struct PlayerStructureOption: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: Int64
  public let name: String
  public let ownerCorporationID: Int64
  public let solarSystemID: Int64
  public let typeID: Int64?
  public let source: SourceIdentity

  public init(
    id: Int64,
    name: String,
    ownerCorporationID: Int64,
    solarSystemID: Int64,
    typeID: Int64?,
    source: SourceIdentity
  ) {
    self.id = id
    self.name = name
    self.ownerCorporationID = ownerCorporationID
    self.solarSystemID = solarSystemID
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

public actor PlayerStructureSearchService {
  public static let searchScope = "esi-search.search_structures.v1"
  public static let detailScope = "esi-universe.read_structures.v1"
  public static let assetScope = "esi-assets.read_assets.v1"
  public static let industryJobsScope =
    "esi-industry.read_character_jobs.v1"
  public static let marketOrdersScope =
    "esi-markets.read_character_orders.v1"

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func search(
    query: String,
    solarSystemID: Int64,
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
        guard detail.value.solarSystemID == solarSystemID else { continue }
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
    return Sourced(
      state: inaccessible > 0 ? .partial : .fresh,
      value: values,
      source: search.source,
      diagnostics:
        inaccessible > 0
        ? ["esi.structure-search.inaccessible:\(inaccessible)"] : []
    )
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
            .filter { $0.locationType == "station" }
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
