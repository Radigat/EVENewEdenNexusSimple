import Foundation
import Testing

@testable import EVENexusCore

@Suite("ESI transport contract")
struct ESIClientTests {
  @Test
  func currentAssetSchemaUsesIsSingleton() throws {
    let fixture = Data(
      """
      {
        "item_id": 11,
        "location_flag": "Hangar",
        "location_id": 22,
        "location_type": "station",
        "quantity": 3,
        "is_singleton": true,
        "type_id": 34
      }
      """.utf8
    )

    let asset = try JSONDecoder().decode(
      ESIAssetDTO.self,
      from: fixture
    )

    #expect(asset.singleton)
    #expect(asset.quantity == 3)
  }

  @Test
  func sellOrderDefaultsMissingBuyFlagToFalse() throws {
    let fixture = Data(
      """
      {
        "location_id": 60003760,
        "order_id": 42,
        "price": 12.5,
        "type_id": 34,
        "volume_remain": 100
      }
      """.utf8
    )

    let order = try JSONDecoder().decode(
      ESICharacterOrderDTO.self,
      from: fixture
    )

    #expect(!order.isBuyOrder)
    #expect(order.volumeRemain == 100)
  }

  @Test
  func followsAllReportedPages() async throws {
    let transport = PagingTransport()
    let client = ESIClient(transport: transport)

    let response = try await client.getAllPages(
      [Int].self,
      endpoint: ESIEndpoint(path: "/fixture/")
    )

    #expect(response.value == [1, 2, 3])
    #expect(response.pages == 2)
    #expect(await transport.requestCount == 2)
  }

  @Test
  func rejectsOversizedResponsesBeforeDecoding() async {
    let client = ESIClient(
      transport: OversizedTransport(),
      maximumResponseBytes: 1_024
    )

    await #expect(throws: ESIError.responseTooLarge) {
      _ = try await client.get(
        [Int].self,
        endpoint: ESIEndpoint(path: "/oversized")
      )
    }
  }

  @Test
  func rejectsUnboundedOrChangingPagination() async {
    let excessive = ESIClient(
      transport: ExcessivePagesTransport(),
      maximumPageCount: 10
    )
    await #expect(throws: ESIError.invalidPagination) {
      _ = try await excessive.getAllPages(
        [Int].self,
        endpoint: ESIEndpoint(path: "/pages")
      )
    }

    let changing = ESIClient(
      transport: ChangingPagesTransport(),
      maximumPageCount: 10
    )
    await #expect(throws: ESIError.invalidPagination) {
      _ = try await changing.getAllPages(
        [Int].self,
        endpoint: ESIEndpoint(path: "/pages")
      )
    }
  }

  @Test
  func genericPostIsNeverRetriedAutomatically() async {
    let transport = FailingPostTransport()
    let client = ESIClient(transport: transport)

    await #expect(throws: ESIError.server(503)) {
      _ = try await client.post(
        [Int].self,
        endpoint: ESIEndpoint(path: "/post"),
        body: [1, 2, 3]
      )
    }
    #expect(await transport.requestCount == 1)
  }

  @Test
  func privateEndpointRequiresLease() async {
    let client = ESIClient(transport: PagingTransport())

    await #expect(throws: ESIError.authorizationRequired) {
      _ = try await client.get(
        [Int].self,
        endpoint: ESIEndpoint(
          path: "/private/",
          requiresAuthorization: true
        )
      )
    }
  }

  @Test
  func privateConditionalCacheIsPartitionedByCharacter() async throws {
    let transport = CharacterPartitionTransport()
    let client = ESIClient(transport: transport)
    let endpoint = ESIEndpoint(
      path: "/private/cache-fixture",
      requiresAuthorization: true
    )

    let first = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: AccessTokenLease(
        characterID: 1,
        accessToken: "one",
        expiresAt: .distantFuture,
        scopes: []
      )
    )
    let second = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: AccessTokenLease(
        characterID: 2,
        accessToken: "two",
        expiresAt: .distantFuture,
        scopes: []
      )
    )

    #expect(first.value.value == 1)
    #expect(second.value.value == 2)
    #expect(await transport.secondRequestHadValidator == false)
  }

  @Test
  func solarSystemSearchWaitsForThreeCharacters() async throws {
    let transport = SolarSystemSearchTransport()
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: transport)
    )

    let results = try await service.search(query: "Ji")

    #expect(results.isEmpty)
    #expect(await transport.requestCount == 0)
  }

  @Test
  func solarSystemSearchBuildsAndReusesPublicUniverseIndex() async throws {
    let transport = SolarSystemSearchTransport()
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: transport)
    )

    let results = try await service.search(query: "jit")

    #expect(results.map(\.name) == ["Jita", "Jitara"])
    #expect(results.map(\.id) == [30_000_142, 30_000_143])
    #expect(await transport.requestMethods == ["GET", "POST"])
    #expect(await transport.postedIDs == [30_000_143, 30_000_142])

    _ = try await service.search(query: "ita")
    #expect(await transport.requestCount == 2)
  }

  @Test
  func solarSystemDetailsResolveRegionAndSecurity() async throws {
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: SolarSystemDetailsTransport())
    )

    let details = try await service.details(systemID: 30_000_142)

    #expect(details.name == "Jita")
    #expect(details.regionID == 10_000_002)
    #expect(details.regionName == "The Forge")
    #expect(details.securityStatus == 0.9459)
    #expect(details.stationIDs == [60_003_760])
  }

  @Test
  func industryIndexSyncPreservesEveryKnownActivity() async throws {
    let service = IndustrySystemIndexService(
      esi: ESIClient(transport: IndustryIndexTransport())
    )

    let result = try await service.synchronize()

    #expect(result.state == .fresh)
    #expect(result.value?.first?.solarSystemID == 30_000_142)
    #expect(
      result.value?.first?.indices.compactMap(\.activity)
        == [
          .manufacturing,
          .invention,
          .reaction,
          .researchingMaterialEfficiency,
        ]
    )
  }

  @Test
  func accessibleStructureSearchUsesBothScopesAndFiltersBySystem()
    async throws
  {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: StructureSearchTransport())
    )
    let lease = AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [
        PlayerStructureSearchService.searchScope,
        PlayerStructureSearchService.detailScope,
      ]
    )

    let result = try await service.search(
      query: "indu",
      solarSystemID: 30_000_142,
      characterID: 99,
      lease: lease
    )

    #expect(result.state == .fresh)
    #expect(result.value?.map(\.id) == [1_000_000_000_001])
    #expect(result.value?.first?.typeID == 35_826)
  }

  @Test
  func accessibleStructureSearchRejectsMissingDetailScope() async {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: StructureSearchTransport())
    )
    let lease = AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [PlayerStructureSearchService.searchScope]
    )

    await #expect(
      throws: ESIError.missingScope(
        PlayerStructureSearchService.detailScope
      )
    ) {
      _ = try await service.search(
        query: "indu",
        solarSystemID: 30_000_142,
        characterID: 99,
        lease: lease
      )
    }
  }

  @Test
  func discoversStructuresFromUsedCharacterLocations() async throws {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: StructureDiscoveryTransport())
    )
    let lease = AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [
        PlayerStructureSearchService.detailScope,
        PlayerStructureSearchService.assetScope,
        PlayerStructureSearchService.industryJobsScope,
        PlayerStructureSearchService.marketOrdersScope,
      ]
    )

    let result = try await service.discoverKnownStructures(
      solarSystemID: 30_000_142,
      characterID: 99,
      lease: lease
    )

    #expect(result.state == .fresh)
    #expect(
      result.value?.map(\.id) == [
        1_000_000_000_001,
        1_000_000_000_002,
        1_000_000_000_003,
      ]
    )
  }

  @Test
  func structureDiscoveryPreservesPartialScopeState() async throws {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: StructureDiscoveryTransport())
    )
    let lease = AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [
        PlayerStructureSearchService.detailScope,
        PlayerStructureSearchService.assetScope,
      ]
    )

    let result = try await service.discoverKnownStructures(
      solarSystemID: 30_000_142,
      characterID: 99,
      lease: lease
    )

    #expect(result.state == .partial)
    #expect(result.value?.map(\.id) == [1_000_000_000_001])
    #expect(
      result.diagnostics.contains(
        "esi.structure-discovery.jobs-scope-missing"
      )
    )
  }
}

@Suite("Character wallet contract")
struct CharacterWalletTests {
  private let source = SourceIdentity(
    provider: "ESI",
    version: EVEConstants.esiCompatibilityDate,
    capturedAt: Date(timeIntervalSince1970: 1_000),
    snapshotID: UUID(
      uuidString: "00000000-0000-0000-0000-000000000001"
    )!
  )

  @Test
  func portfolioTotalsAvailableBalancesWithoutTreatingMissingAsZero() {
    let portfolio = WalletPortfolioSnapshot(
      balances: [
        balance(
          characterID: 2,
          name: "Zulu",
          value: nil,
          state: .unavailable
        ),
        balance(
          characterID: 1,
          name: "Alpha",
          value: 125.25,
          state: .fresh
        ),
        balance(
          characterID: 3,
          name: "Bravo",
          value: 74.75,
          state: .stale
        ),
        balance(
          characterID: 4,
          name: "Forbidden",
          value: 999,
          state: .forbidden
        ),
      ]
    )

    #expect(
      portfolio.balances.map(\.character.name) == [
        "Alpha", "Bravo", "Forbidden", "Zulu",
      ]
    )
    #expect(portfolio.totalBalance == 200)
    #expect(portfolio.includedCharacterCount == 2)
    #expect(portfolio.totalCharacterCount == 4)
    #expect(portfolio.freshness == .partial)
  }

  @Test
  func completePortfolioPreservesStaleState() {
    let portfolio = WalletPortfolioSnapshot(
      balances: [
        balance(
          characterID: 1,
          name: "Alpha",
          value: 10,
          state: .fresh
        ),
        balance(
          characterID: 2,
          name: "Bravo",
          value: 20,
          state: .stale
        ),
      ]
    )

    #expect(portfolio.totalBalance == 30)
    #expect(portfolio.freshness == .stale)
  }

  @Test
  func balanceSyncUsesCharacterWalletEndpointAndScope() async throws {
    let transport = WalletTransport()
    let service = CharacterWalletService(
      esi: ESIClient(transport: transport)
    )
    let authorization = AuthorizationSnapshot(
      characterID: 42,
      characterName: "Fixture",
      scopes: [CharacterWalletService.requiredScope]
    )
    let lease = AccessTokenLease(
      characterID: 42,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [CharacterWalletService.requiredScope]
    )

    let result = await service.synchronizeBalance(
      authorization: authorization,
      lease: lease
    )

    #expect(result.state == .fresh)
    #expect(result.value == 123_456.78)
    #expect(await transport.requestPath == "/characters/42/wallet")
    #expect(await transport.authorizationHeader == "Bearer fixture")
  }

  @Test
  func missingWalletScopeRemainsForbidden() async {
    let transport = WalletTransport()
    let service = CharacterWalletService(
      esi: ESIClient(transport: transport)
    )
    let authorization = AuthorizationSnapshot(
      characterID: 42,
      characterName: "Fixture",
      scopes: []
    )
    let lease = AccessTokenLease(
      characterID: 42,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: []
    )

    let result = await service.synchronizeBalance(
      authorization: authorization,
      lease: lease
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(await transport.requestCount == 0)
  }

  private func balance(
    characterID: Int64,
    name: String,
    value: Double?,
    state: DataFreshness
  ) -> CharacterWalletBalance {
    CharacterWalletBalance(
      character: CharacterIdentity(id: characterID, name: name),
      balance: Sourced(
        state: state,
        value: value,
        source: source
      )
    )
  }
}

private struct CharacterPartitionValue: Decodable, Sendable {
  let value: Int
}

private actor WalletTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0
  private(set) var requestPath: String?
  private(set) var authorizationHeader: String?

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    requestPath = request.url?.path
    authorizationHeader = request.value(
      forHTTPHeaderField: "Authorization"
    )
    return (
      Data("123456.78".utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Expires": "Wed, 30 Jul 2026 10:00:00 GMT"
        ]
      )!
    )
  }
}

private actor CharacterPartitionTransport: ESIHTTPTransporting {
  private(set) var secondRequestHadValidator = false

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let isSecondCharacter =
      request.value(forHTTPHeaderField: "Authorization") == "Bearer two"
    let hadValidator =
      request.value(forHTTPHeaderField: "If-None-Match") != nil
    if isSecondCharacter {
      secondRequestHadValidator = hadValidator
    }
    let status = isSecondCharacter && hadValidator ? 304 : 200
    let body = isSecondCharacter ? #"{"value":2}"# : #"{"value":1}"#
    return (
      status == 304 ? Data() : Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["ETag": #""shared-validator""#]
      )!
    )
  }
}

private struct SolarSystemDetailsTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let body: String
    switch request.url?.path {
    case "/universe/systems/30000142":
      body =
        """
        {
          "constellation_id":20000020,
          "name":"Jita",
          "security_class":"B",
          "security_status":0.9459,
          "stations":[60003760],
          "system_id":30000142
        }
        """
    case "/universe/constellations/20000020":
      body =
        """
        {
          "constellation_id":20000020,
          "name":"Kimotoro",
          "region_id":10000002
        }
        """
    case "/universe/regions/10000002":
      body =
        """
        {"name":"The Forge","region_id":10000002}
        """
    default:
      body = "{}"
    }
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}

private actor PagingTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    let page =
      URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
      )?.queryItems?.first(where: { $0.name == "page" })?.value ?? "1"
    let body = page == "1" ? "[1,2]" : "[3]"
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "X-Pages": "2",
        "Expires": "Wed, 30 Jul 2026 08:00:00 GMT",
      ]
    )!
    return (Data(body.utf8), response)
  }
}

private struct OversizedTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let data = Data(repeating: 0x20, count: 2_048)
    return (
      data,
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": String(data.count)]
      )!
    )
  }
}

private struct ExcessivePagesTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    (
      Data("[]".utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["X-Pages": "11"]
      )!
    )
  }
}

private actor ChangingPagesTransport: ESIHTTPTransporting {
  private var requestCount = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    return (
      Data("[]".utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["X-Pages": requestCount == 1 ? "2" : "3"]
      )!
    )
  }
}

private actor FailingPostTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    return (
      Data(),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 503,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}

private actor SolarSystemSearchTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0
  private(set) var requestMethods: [String] = []
  private(set) var postedIDs: [Int64] = []

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    requestMethods.append(request.httpMethod ?? "GET")
    let body: String
    if request.httpMethod == "POST" {
      postedIDs = try JSONDecoder().decode(
        [Int64].self,
        from: request.httpBody ?? Data()
      )
      body =
        """
        [
          {"category":"solar_system","id":30000143,"name":"Jitara"},
          {"category":"solar_system","id":30000142,"name":"Jita"}
        ]
        """
    } else {
      body = "[30000143,30000142]"
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [:]
    )!
    return (Data(body.utf8), response)
  }
}

private struct IndustryIndexTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let body =
      """
      [{
        "solar_system_id": 30000142,
        "cost_indices": [
          {"activity":"reaction","cost_index":0.03},
          {"activity":"invention","cost_index":0.02},
          {"activity":"manufacturing","cost_index":0.01},
          {"activity":"researching_material_efficiency","cost_index":0.04}
        ]
      }]
      """
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}

private struct StructureSearchTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    let body: String
    switch path {
    case "/characters/99/search":
      body =
        """
        {"structure":[1000000000001,1000000000002]}
        """
    case "/universe/structures/1000000000001":
      body =
        """
        {
          "name":"Industry Hub",
          "owner_id":98000001,
          "solar_system_id":30000142,
          "type_id":35826
        }
        """
    case "/universe/structures/1000000000002":
      body =
        """
        {
          "name":"Other System",
          "owner_id":98000002,
          "solar_system_id":30002187,
          "type_id":35825
        }
        """
    default:
      body = "{}"
    }
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}

private struct StructureDiscoveryTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    let body: String
    let status: Int
    switch path {
    case "/characters/99/assets":
      status = 200
      body =
        """
        [{
          "item_id":11,
          "location_flag":"Hangar",
          "location_id":1000000000001,
          "location_type":"station",
          "quantity":1,
          "is_singleton":false,
          "type_id":34
        }]
        """
    case "/characters/99/industry/jobs":
      status = 200
      body =
        """
        [{
          "activity_id":1,
          "blueprint_id":12,
          "blueprint_type_id":13,
          "end_date":"2026-07-30T10:00:00Z",
          "facility_id":1000000000002,
          "job_id":14,
          "runs":1,
          "status":"active"
        }]
        """
    case "/characters/99/orders":
      status = 200
      body =
        """
        [{
          "location_id":1000000000003,
          "order_id":15,
          "price":1,
          "type_id":34,
          "volume_remain":1
        }]
        """
    case "/characters/99/orders/history":
      status = 200
      body = "[]"
    case "/universe/structures/1000000000001":
      status = 200
      body =
        """
        {"name":"Asset Hub","owner_id":1,"solar_system_id":30000142}
        """
    case "/universe/structures/1000000000002":
      status = 200
      body =
        """
        {"name":"Industry Hub","owner_id":1,"solar_system_id":30000142}
        """
    case "/universe/structures/1000000000003":
      status = 200
      body =
        """
        {"name":"Market Hub","owner_id":1,"solar_system_id":30000142}
        """
    default:
      status = 404
      body = "{}"
    }
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}
