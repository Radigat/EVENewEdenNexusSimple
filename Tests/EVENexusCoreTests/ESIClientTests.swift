import Foundation
import Testing

@testable import EVENexusCore

@Suite("ESI transport contract")
struct ESIClientTests {
  @Test
  func ownerContactBuildsDescriptiveUserAgentWithoutAcceptingUnsafeInput() {
    #expect(
      CCPUserAgentConfiguration.value(ownerContact: "owner@example.com")
        == "EVE-Nexus-Simple/1.0 (owner@example.com)"
    )
    #expect(
      CCPUserAgentConfiguration.value(ownerContact: "owner\n@example.com")
        == CCPUserAgentConfiguration.genericValue
    )
  }

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
  func freshResponsesAreReusedWithoutAnotherNetworkRequest() async throws {
    let transport = ExpiringCacheTransport()
    let now = Date(timeIntervalSince1970: 1_000)
    let client = ESIClient(
      transport: transport,
      now: { now }
    )

    let first = try await client.get(
      CharacterPartitionValue.self,
      endpoint: ESIEndpoint(path: "/cache/fresh")
    )
    let second = try await client.get(
      CharacterPartitionValue.self,
      endpoint: ESIEndpoint(path: "/cache/fresh")
    )

    #expect(first.value.value == 1)
    #expect(second.value.value == 1)
    #expect(first.source == second.source)
    #expect(await transport.requestCount == 1)
  }

  @Test
  func responseCacheEvictsLeastRecentlyUsedEntries() async throws {
    let transport = ExpiringCacheTransport()
    let client = ESIClient(
      transport: transport,
      maximumCachedResponses: 2,
      maximumCachedBytes: 1_024,
      now: { Date(timeIntervalSince1970: 1_000) }
    )

    for id in 1...3 {
      _ = try await client.get(
        CharacterPartitionValue.self,
        endpoint: ESIEndpoint(path: "/cache/\(id)")
      )
    }
    let usage = await client.cachedResponseUsage()
    #expect(usage.entries == 2)
    #expect(usage.bytes > 0)
    #expect(usage.bytes <= usage.maximumBytes)

    _ = try await client.get(
      CharacterPartitionValue.self,
      endpoint: ESIEndpoint(path: "/cache/1")
    )
    #expect(await transport.requestCount == 4)
  }

  @Test
  func bulkPublicCachePurgeOnlyRemovesTheSelectedEndpointFamily() async throws {
    let transport = ExpiringCacheTransport()
    let client = ESIClient(
      transport: transport,
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    let market = ESIEndpoint(path: "/markets/10000002/orders/")
    let status = ESIEndpoint(path: "/status/")

    _ = try await client.get(CharacterPartitionValue.self, endpoint: market)
    _ = try await client.get(CharacterPartitionValue.self, endpoint: status)
    await client.removeCachedPublicResponses(
      pathPrefix: "/markets/10000002/orders/"
    )
    #expect(await client.cachedResponseUsage().entries == 1)

    _ = try await client.get(CharacterPartitionValue.self, endpoint: market)
    _ = try await client.get(CharacterPartitionValue.self, endpoint: status)
    #expect(await transport.requestCount == 3)
  }

  @Test
  func disconnectPurgeRemovesOnlyTheCharactersCachedBodies() async throws {
    let transport = ExpiringCacheTransport()
    let client = ESIClient(
      transport: transport,
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    let endpoint = ESIEndpoint(
      path: "/private/cache",
      requiresAuthorization: true
    )
    let firstLease = AccessTokenLease(
      characterID: 1,
      accessToken: "one",
      expiresAt: .distantFuture,
      scopes: []
    )
    let secondLease = AccessTokenLease(
      characterID: 2,
      accessToken: "two",
      expiresAt: .distantFuture,
      scopes: []
    )

    _ = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: firstLease
    )
    _ = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: secondLease
    )
    await client.removeCachedResponses(forCharacterID: 1)

    _ = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: firstLease
    )
    _ = try await client.get(
      CharacterPartitionValue.self,
      endpoint: endpoint,
      lease: secondLease
    )
    #expect(await transport.requestCount == 3)
    #expect(await client.cachedResponseUsage().entries == 2)
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
    #expect(
      await transport.postedIDs
        == [30_000_143, 30_000_142, 30_004_807]
    )

    _ = try await service.search(query: "ita")
    #expect(await transport.requestCount == 2)
  }

  @Test
  func solarSystemSearchMatchesANameBeforeItsHyphenAtThreeCharacters()
    async throws
  {
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: SolarSystemSearchTransport())
    )

    let results = try await service.search(query: "B9E")

    #expect(results.map(\.name) == ["B9E-H6"])
    #expect(results.map(\.id) == [30_004_807])
  }

  @Test
  func cancelledSearchDoesNotRestartTheSharedUniverseIndex() async throws {
    let transport = SolarSystemSearchTransport(postDelayMilliseconds: 80)
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: transport)
    )
    let first = Task {
      try await service.search(query: "B9E")
    }
    try await Task.sleep(for: .milliseconds(20))
    first.cancel()

    let results = try await service.search(query: "B9E")
    _ = try? await first.value

    #expect(results.map(\.name) == ["B9E-H6"])
    #expect(await transport.requestCount == 2)
  }

  @Test
  func universeNameIndexBuildUsesBoundedParallelBatches() async throws {
    let transport = BatchedSolarSystemSearchTransport(systemCount: 4_001)
    let service = SolarSystemSearchService(
      esi: ESIClient(transport: transport)
    )

    let results = try await service.search(query: "SYS")

    #expect(results.count == 4_001)
    #expect(
      await transport.maximumConcurrentPostCount > 1
    )
    #expect(
      await transport.maximumConcurrentPostCount
        <= SolarSystemSearchService.maximumConcurrentNameRequests
    )
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
  func tradingLocationSearchResolvesNPCStationOwnerContext() async throws {
    let service = TradingLocationSearchService(
      esi: ESIClient(transport: TradingLocationSearchTransport())
    )

    let result = try await service.searchNPCStations(query: "fixture")
    let option = try #require(result.value?.first)

    #expect(result.state == .fresh)
    #expect(option.id == 60_000_001)
    #expect(option.name == "Fixture Trade Station")
    #expect(option.solarSystemID == 30_000_001)
    #expect(option.ownerCorporationID == 1_000_004)
    #expect(option.ownerFactionID == 500_002)
    #expect(option.procurementLocation.kind == .npcTradeHub)
  }

  @Test
  func selectedSystemLoadsOnlyItsPublishedNPCStations() async throws {
    let service = TradingLocationSearchService(
      esi: ESIClient(transport: TradingLocationSearchTransport())
    )

    let result = try await service.stations(
      inSolarSystemID: 30_000_001
    )

    #expect(result.state == .fresh)
    #expect(result.value?.map(\.id) == [60_000_001])
    #expect(result.value?.first?.solarSystemID == 30_000_001)
  }

  @Test
  func jitaResolutionRetainsKnownFactionWhenCorporationLookupFails()
    async throws
  {
    let service = TradingLocationSearchService(
      esi: ESIClient(transport: JitaFactionFallbackTransport())
    )

    let option = try await service.resolveNPCStation(
      stationID: ProcurementLocation.jita.locationID!
    )

    #expect(
      option.ownerCorporationID
        == ProcurementLocation.jita.ownerCorporationID
    )
    #expect(option.ownerFactionID == ProcurementLocation.jita.ownerFactionID)
  }

  @Test
  func tradingLocationStructureSearchIsNotRestrictedToProductionSystems()
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
      query: "hub",
      characterID: 99,
      lease: lease
    )

    #expect(
      result.value?.map(\.id) == [
        1_000_000_000_001, 1_000_000_000_002,
      ]
    )
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

  @Test
  func resolvesKnownAssetStructuresWithoutDroppingInaccessibleIDs()
    async
  {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: AssetStructureResolutionTransport())
    )
    let lease = AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: [PlayerStructureSearchService.detailScope]
    )

    let result = await service.resolveKnownStructures(
      structureIDs: [
        1_000_000_000_001,
        1_000_000_000_002,
      ],
      lease: lease
    )

    #expect(result.state == .partial)
    #expect(result.value?.map(\.id) == [1_000_000_000_001])
    #expect(
      result.diagnostics.contains(
        "esi.structure-resolution.inaccessible:1"
      )
    )
  }

  @Test
  func knownAssetStructureResolutionPreservesMissingScope() async {
    let service = PlayerStructureSearchService(
      esi: ESIClient(transport: AssetStructureResolutionTransport())
    )
    let result = await service.resolveKnownStructures(
      structureIDs: [1_000_000_000_001],
      lease: AccessTokenLease(
        characterID: 99,
        accessToken: "fixture",
        expiresAt: .distantFuture,
        scopes: []
      )
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
  }

  @Test
  func corporationAssetsRequireTheNewSSOScopeBeforeTransport() async {
    let transport = CorporationAssetTransport(isDirector: true)
    let result = await CorporationAssetSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: []),
      lease: corporationLease(scopes: [])
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(await transport.requestedPaths.isEmpty)
    #expect(
      result.diagnostics.contains(
        "esi.corporation-assets.scope-missing:\(CorporationAssetSyncService.assetScope)"
      )
    )
  }

  @Test
  func corporationAssetsRequireDirectorWithoutInferringAnEmptyHangar() async {
    let transport = CorporationAssetTransport(isDirector: false)
    let scopes = CorporationAssetSyncService.requiredScopes
    let result = await CorporationAssetSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes)
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(
      result.diagnostics == [
        "esi.corporation-assets.director-required"
      ]
    )
    #expect(
      await transport.requestedPaths == ["/characters/99/roles"]
    )
    #expect(
      CharacterSyncStatusAssessment.isRoleNotApplicable(
        domain: "corporation-assets",
        diagnostics: result.diagnostics
      )
    )
  }

  @Test
  func corporationAssetsFollowPaginationAndKeepDivisionNames() async {
    let transport = CorporationAssetTransport(isDirector: true)
    let scopes = CorporationAssetSyncService.requiredScopes
    let result = await CorporationAssetSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes)
    )

    #expect(result.state == .fresh)
    #expect(result.value?.corporationID == 98_000_001)
    #expect(result.value?.corporationName == "Example Industries")
    #expect(result.value?.corporationDivisionNames?[1] == "Minerals")
    #expect(
      result.value?.items.map(\.locationFlag).sorted() == [
        "CorpSAG1", "CorpSAG2",
      ])
    #expect(
      await transport.requestedPaths.filter {
        $0 == "/corporations/98000001/assets"
      }.count == 2
    )
  }

  @Test
  func corporationDivisionDecoderToleratesIncompleteOptionalLabels() throws {
    let divisions = try JSONDecoder().decode(
      ESICorporationDivisionsDTO.self,
      from: Data(
        #"{"hangar":[{"division":1},{"name":"Minerals"},{"division":2,"name":"Components"}]}"#.utf8
      )
    )

    #expect(divisions.hangar?.count == 3)
    #expect(divisions.hangar?.first?.division == 1)
    #expect(divisions.hangar?.first?.name == nil)
    #expect(divisions.hangar?.last?.name == "Components")
  }

  @Test
  func privateContractsRequireScopeBeforeTransport() async {
    let transport = PrivateContractTransport()
    let result = await PrivateContractSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      authorization: corporationAuthorization(scopes: []),
      lease: corporationLease(scopes: []),
      now: Date(timeIntervalSince1970: 1_775_260_800)
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(await transport.requestedPaths.isEmpty)
  }

  @Test
  func privateContractsKeepOnlyOwnActivePersonalValueAndCourierData() async {
    let transport = PrivateContractTransport()
    let scopes: Set<String> = [PrivateContractSyncService.requiredScope]
    let result = await PrivateContractSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes),
      now: Date(timeIntervalSince1970: 1_775_260_800)
    )

    #expect(result.state == .fresh)
    #expect(result.diagnostics.isEmpty)
    #expect(result.value?.itemContracts.map(\.contract.contractID) == [1])
    #expect(result.value?.inTransitCouriers.map(\.contractID) == [3])
    #expect(result.value?.itemContracts.first?.items.count == 2)
    #expect(
      await transport.requestedPaths == [
        "/characters/99/contracts",
        "/characters/99/contracts/1/items",
      ]
    )
  }

  @Test
  func privateContractItemFailurePreservesPartialState() async {
    let transport = PrivateContractTransport(failItems: true)
    let scopes: Set<String> = [PrivateContractSyncService.requiredScope]
    let result = await PrivateContractSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes),
      now: Date(timeIntervalSince1970: 1_775_260_800)
    )

    #expect(result.state == .partial)
    #expect(result.value?.itemContracts.isEmpty == true)
    #expect(result.value?.failedItemContractIDs == [1])
    #expect(result.value?.inTransitCouriers.map(\.contractID) == [3])
  }

  @Test
  func corporationWalletRequiresScopeBeforeTransport() async {
    let transport = CorporationWalletTransport(role: "Accountant")
    let result = await CorporationWalletSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: []),
      lease: corporationLease(scopes: [])
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(await transport.requestedPaths.isEmpty)
  }

  @Test
  func corporationWalletRequiresAccountantRole() async {
    let transport = CorporationWalletTransport(role: "Member")
    let scopes = CorporationWalletSyncService.requiredScopes
    let result = await CorporationWalletSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes)
    )

    #expect(result.state == .forbidden)
    #expect(result.value == nil)
    #expect(await transport.requestedPaths == ["/characters/99/roles"])
    #expect(
      CharacterSyncStatusAssessment.isRoleNotApplicable(
        domain: "corporation-wallet",
        diagnostics: result.diagnostics
      )
    )
  }

  @Test
  func corporationWalletLoadsEveryDivisionForAccountant() async {
    let transport = CorporationWalletTransport(role: "Junior_Accountant")
    let scopes = CorporationWalletSyncService.requiredScopes
    let result = await CorporationWalletSyncService(
      esi: ESIClient(transport: transport)
    ).synchronize(
      corporationID: 98_000_001,
      authorization: corporationAuthorization(scopes: scopes),
      lease: corporationLease(scopes: scopes)
    )

    #expect(result.state == .fresh)
    #expect(result.diagnostics.isEmpty)
    #expect(result.value?.corporationID == 98_000_001)
    #expect(result.value?.divisions.map(\.balance) == [100, 200])
    #expect(
      await transport.requestedPaths == [
        "/characters/99/roles",
        "/corporations/98000001/wallets",
      ]
    )
  }

  private func corporationAuthorization(
    scopes: Set<String>
  ) -> AuthorizationSnapshot {
    AuthorizationSnapshot(
      characterID: 99,
      characterName: "Director",
      scopes: scopes
    )
  }

  private func corporationLease(
    scopes: Set<String>
  ) -> AccessTokenLease {
    AccessTokenLease(
      characterID: 99,
      accessToken: "fixture",
      expiresAt: .distantFuture,
      scopes: scopes
    )
  }
}

@Suite("Dashboard projection contracts")
struct DashboardProjectionTests {
  private let source = SourceIdentity(
    provider: "fixture",
    version: "1",
    capturedAt: Date(timeIntervalSince1970: 1_000)
  )

  @Test
  func industryActivitiesAndSlotPoolsRemainDistinct() {
    let skills = Sourced(
      state: DataFreshness.fresh,
      value: [
        TrainedSkill(
          skillID: IndustrySlotCapacityRules.massProductionSkillTypeID,
          trainedLevel: 5,
          activeLevel: 5,
          skillpoints: 1
        ),
        TrainedSkill(
          skillID: IndustrySlotCapacityRules.advancedMassProductionSkillTypeID,
          trainedLevel: 4,
          activeLevel: 4,
          skillpoints: 1
        ),
        TrainedSkill(
          skillID: IndustrySlotCapacityRules.laboratoryOperationSkillTypeID,
          trainedLevel: 5,
          activeLevel: 5,
          skillpoints: 1
        ),
        TrainedSkill(
          skillID: IndustrySlotCapacityRules.advancedLaboratoryOperationSkillTypeID,
          trainedLevel: 3,
          activeLevel: 3,
          skillpoints: 1
        ),
        TrainedSkill(
          skillID: IndustrySlotCapacityRules.massReactionsSkillTypeID,
          trainedLevel: 4,
          activeLevel: 4,
          skillpoints: 1
        ),
      ],
      source: source
    )

    #expect(
      IndustrySlotCapacityRules.capacity(
        for: .manufacturing,
        skills: skills
      ) == 10
    )
    #expect(
      IndustrySlotCapacityRules.capacity(for: .reaction, skills: skills) == 4
    )
    #expect(
      IndustrySlotCapacityRules.capacity(for: .copying, skills: skills) == 9
    )
    #expect(
      IndustrySlotCapacityRules.capacity(for: .invention, skills: skills) == 9
    )
    #expect(DashboardIndustryActivity(esiActivityID: 3) == .timeResearch)
    #expect(DashboardIndustryActivity(esiActivityID: 4) == .materialResearch)
    #expect(DashboardIndustryActivity(esiActivityID: 9) == .reaction)
    #expect(DashboardIndustryActivity(esiActivityID: 11) == .reaction)
    #expect(DashboardIndustryActivity(esiActivityID: 99) == nil)
  }

  @Test
  func unavailableSkillsDoNotBecomeZeroCapacity() {
    let unavailable = Sourced<[TrainedSkill]>(
      state: .unavailable,
      value: nil,
      source: source
    )
    #expect(
      IndustrySlotCapacityRules.capacity(
        for: .manufacturing,
        skills: unavailable
      ) == nil
    )
  }

  @Test
  func jobStatusSeparatesRunningFromReadyForDelivery() {
    let now = Date(timeIntervalSince1970: 10_000)
    let active = ESIIndustryJobDTO(
      activityID: 8,
      blueprintID: 1,
      blueprintTypeID: 2,
      endDate: now.addingTimeInterval(60),
      facilityID: 3,
      jobID: 4,
      runs: 1,
      status: "active"
    )
    let ready = ESIIndustryJobDTO(
      activityID: 5,
      blueprintID: 5,
      blueprintTypeID: 6,
      endDate: now.addingTimeInterval(-60),
      facilityID: 7,
      jobID: 8,
      runs: 1,
      status: "ready"
    )

    #expect(active.dashboardActivity == .invention)
    #expect(active.isRunning(at: now))
    #expect(!active.isReadyForDelivery)
    #expect(!ready.isRunning(at: now))
    #expect(ready.isReadyForDelivery)
  }

  @Test
  func elapsedActiveJobIsProjectedAsReadyUntilTheNextESISync() {
    let now = Date(timeIntervalSince1970: 10_000)
    let cachedActive = ESIIndustryJobDTO(
      activityID: 1,
      blueprintID: 1,
      blueprintTypeID: 2,
      endDate: now.addingTimeInterval(-1),
      facilityID: 3,
      jobID: 4,
      runs: 1,
      status: "active"
    )

    #expect(!cachedActive.isRunning(at: now))
    #expect(cachedActive.isReadyForDelivery(at: now))
    #expect(!cachedActive.isDelivered)
  }

  @Test
  func pausedJobDoesNotBecomeReadyOnlyBecauseItsOldEndDateElapsed() {
    let now = Date(timeIntervalSince1970: 10_000)
    let paused = ESIIndustryJobDTO(
      activityID: 1,
      blueprintID: 1,
      blueprintTypeID: 2,
      endDate: now.addingTimeInterval(-1),
      facilityID: 3,
      jobID: 4,
      runs: 1,
      status: "paused"
    )

    #expect(paused.isRunning(at: now))
    #expect(!paused.isReadyForDelivery(at: now))
  }

  @Test
  func industryJobDecodesCurrentESIFieldsAndLegacySnapshots() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let current = try decoder.decode(
      ESIIndustryJobDTO.self,
      from: Data(
        """
        {
          "activity_id": 1,
          "blueprint_id": 11,
          "blueprint_location_id": 12,
          "blueprint_type_id": 13,
          "duration": 3600,
          "end_date": "2026-08-04T12:00:00Z",
          "facility_id": 1000000000001,
          "installer_id": 14,
          "job_id": 15,
          "output_location_id": 16,
          "product_type_id": 17,
          "runs": 2,
          "start_date": "2026-08-04T11:00:00Z",
          "station_id": 1000000000001,
          "status": "active",
          "successful_runs": 2
        }
        """.utf8
      )
    )
    #expect(current.productTypeID == 17)
    #expect(current.stationID == 1_000_000_000_001)
    #expect(current.facilityName == nil)
    #expect(current.startDate != nil)

    let legacy = try decoder.decode(
      ESIIndustryJobDTO.self,
      from: Data(
        """
        {
          "activity_id": 5,
          "blueprint_id": 21,
          "blueprint_type_id": 22,
          "end_date": "2026-08-04T10:00:00Z",
          "facility_id": 23,
          "job_id": 24,
          "runs": 1,
          "status": "ready"
        }
        """.utf8
      )
    )
    #expect(legacy.stationID == nil)
    #expect(legacy.productTypeID == nil)
    #expect(legacy.isReadyForDelivery)
  }

  @Test
  func mineralTrendUsesLatestTwoValidMarketDays() throws {
    let fixture = Data(
      """
      [
        {"average": 5, "date": "2026-07-30", "highest": 6, "lowest": 4, "order_count": 2, "volume": 100},
        {"average": 6, "date": "2026-08-01", "highest": 7, "lowest": 5, "order_count": 3, "volume": 200}
      ]
      """.utf8
    )
    let history = try JSONDecoder().decode(
      [ESIMarketHistoryDTO].self,
      from: fixture
    )
    let trend = MineralPriceTrendProjector.project(
      typeID: 34,
      name: "Tritanium",
      history: history
    )

    #expect(trend?.averagePrice == 6)
    #expect(trend?.changeFraction == 0.2)
    #expect(trend?.marketDate == "2026-08-01")
  }

  @Test
  func wealthProjectionKeepsUnpricedAssetsOutOfKnownComponents() {
    let assets = AssetSnapshot(
      characterID: 7,
      state: .fresh,
      items: [
        AssetItem(
          id: 1,
          typeID: 34,
          quantity: 10,
          locationID: 60_000_001,
          locationKind: .station,
          locationFlag: "Hangar",
          singleton: false
        ),
        AssetItem(
          id: 2,
          typeID: 999,
          quantity: 5,
          locationID: 60_000_001,
          locationKind: .station,
          locationFlag: "Hangar",
          singleton: false
        ),
      ]
    )
    let input = DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture"),
      wallet: Sourced(state: .fresh, value: 100, source: source),
      assets: Sourced(state: .fresh, value: assets, source: source)
    )
    let prices = ReferencePriceSnapshot(
      capturedAt: source.capturedAt,
      prices: [
        34: AdjustedPrice(
          typeID: 34,
          adjustedPrice: 4,
          averagePrice: 5
        )
      ],
      source: source
    )

    let snapshot = DashboardWealthProjector.project(
      inputs: [input],
      prices: prices,
      typeNames: [999: "Unpriced Fixture"]
    )

    #expect(snapshot.knownTotalValue == 150)
    #expect(!snapshot.isComplete)
    #expect(snapshot.characters.first?.assetValue == 50)
    #expect(snapshot.characters.first?.unvaluedAssetTypeCount == 1)
    #expect(
      snapshot.characters.first?.unvaluedAssetTypes.map(\.name)
        == ["Unpriced Fixture"]
    )
  }

  @Test
  func wealthProjectionIncludesOrdersAndExcludesBlueprintCopies() throws {
    let orders = try JSONDecoder().decode(
      [ESICharacterOrderDTO].self,
      from: Data(
        """
        [
          {
            "is_buy_order": false,
            "location_id": 60000001,
            "order_id": 10,
            "price": 10,
            "type_id": 34,
            "volume_remain": 4
          },
          {
            "escrow": 25,
            "is_buy_order": true,
            "location_id": 60000001,
            "order_id": 11,
            "price": 8,
            "type_id": 35,
            "volume_remain": 5
          }
        ]
        """.utf8
      )
    )
    let assets = AssetSnapshot(
      characterID: 7,
      state: .fresh,
      items: [
        AssetItem(
          id: 1,
          typeID: 34,
          quantity: 10,
          locationID: 60_000_001,
          locationKind: .station,
          locationFlag: "Hangar",
          singleton: false
        ),
        AssetItem(
          id: 2,
          typeID: 999,
          quantity: -2,
          locationID: 60_000_001,
          locationKind: .station,
          locationFlag: "Hangar",
          singleton: true
        ),
      ]
    )
    let input = DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture"),
      wallet: Sourced(state: .fresh, value: 100, source: source),
      assets: Sourced(
        state: .partial,
        value: assets,
        source: source,
        diagnostics: ["esi.structure-resolution.inaccessible:1"]
      ),
      openOrders: Sourced(state: .fresh, value: orders, source: source),
      privateContracts: Sourced(
        state: .fresh,
        value: PrivateContractSnapshot(
          characterID: 7,
          itemContracts: [],
          inTransitCouriers: []
        ),
        source: source
      )
    )
    let prices = ReferencePriceSnapshot(
      capturedAt: source.capturedAt,
      prices: [
        34: AdjustedPrice(typeID: 34, adjustedPrice: 4, averagePrice: 5),
        999: AdjustedPrice(
          typeID: 999,
          adjustedPrice: 1_000,
          averagePrice: 2_000
        ),
      ],
      source: source
    )

    let snapshot = DashboardWealthProjector.project(
      inputs: [input],
      prices: prices
    )

    #expect(snapshot.knownTotalValue == 215)
    #expect(snapshot.walletTotal == 100)
    #expect(snapshot.assetTotal == 50)
    #expect(snapshot.ordersTotal == 40)
    #expect(snapshot.escrowTotal == 25)
    #expect(snapshot.isComplete)
    #expect(snapshot.freshness == .fresh)
    #expect(snapshot.characters.first?.excludedBlueprintCopyCount == 1)
  }

  @Test
  func wealthProjectionKeepsMissingBuyOrderEscrowUnavailable() throws {
    let orders = try JSONDecoder().decode(
      [ESICharacterOrderDTO].self,
      from: Data(
        """
        [
          {
            "is_buy_order": true,
            "location_id": 60000001,
            "order_id": 11,
            "price": 8,
            "type_id": 35,
            "volume_remain": 5
          }
        ]
        """.utf8
      )
    )
    let assets = AssetSnapshot(
      characterID: 7,
      state: .fresh,
      items: []
    )
    let input = DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture"),
      wallet: Sourced(state: .fresh, value: 100, source: source),
      assets: Sourced(state: .fresh, value: assets, source: source),
      openOrders: Sourced(state: .fresh, value: orders, source: source)
    )
    let prices = ReferencePriceSnapshot(
      capturedAt: source.capturedAt,
      prices: [:],
      source: source
    )

    let snapshot = DashboardWealthProjector.project(
      inputs: [input],
      prices: prices
    )

    #expect(snapshot.knownTotalValue == 100)
    #expect(snapshot.escrowTotal == nil)
    #expect(!snapshot.isComplete)
    #expect(snapshot.characters.first?.missingEscrowOrderCount == 1)
  }

  @Test
  func wealthProjectionValuesContractItemsAndCourierCollateral() {
    let itemContract = ESIPrivateContractDTO(
      collateral: nil,
      contractID: 1,
      dateExpired: .distantFuture,
      forCorporation: false,
      issuerID: 7,
      status: "outstanding",
      type: "item_exchange"
    )
    let courier = ESIPrivateContractDTO(
      collateral: 123,
      contractID: 2,
      dateExpired: .distantFuture,
      forCorporation: false,
      issuerID: 7,
      status: "in_progress",
      type: "courier"
    )
    let contracts = PrivateContractSnapshot(
      characterID: 7,
      itemContracts: [
        PrivateContractItems(
          contract: itemContract,
          items: [
            ESIPrivateContractItemDTO(
              isIncluded: true,
              quantity: 10,
              rawQuantity: nil,
              recordID: 1,
              typeID: 34
            ),
            ESIPrivateContractItemDTO(
              isIncluded: false,
              quantity: 10,
              rawQuantity: nil,
              recordID: 2,
              typeID: 35
            ),
            ESIPrivateContractItemDTO(
              isIncluded: true,
              quantity: 1,
              rawQuantity: -2,
              recordID: 3,
              typeID: 999
            ),
            ESIPrivateContractItemDTO(
              isIncluded: true,
              quantity: 1,
              rawQuantity: -1,
              recordID: 4,
              typeID: 35
            ),
          ]
        )
      ],
      inTransitCouriers: [courier]
    )
    let input = DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture"),
      wallet: Sourced(state: .fresh, value: 0, source: source),
      assets: Sourced(
        state: .fresh,
        value: AssetSnapshot(characterID: 7, state: .fresh, items: []),
        source: source
      ),
      openOrders: Sourced(state: .fresh, value: [], source: source),
      privateContracts: Sourced(
        state: .fresh,
        value: contracts,
        source: source
      )
    )
    let snapshot = DashboardWealthProjector.project(
      inputs: [input],
      prices: ReferencePriceSnapshot(
        capturedAt: source.capturedAt,
        prices: [
          34: AdjustedPrice(typeID: 34, adjustedPrice: 4, averagePrice: 5),
          35: AdjustedPrice(typeID: 35, adjustedPrice: 6, averagePrice: 7),
        ],
        source: source
      )
    )

    #expect(snapshot.contractsTotal == 57)
    #expect(snapshot.courierTotal == 123)
    #expect(snapshot.knownTotalValue == 180)
    #expect(snapshot.contractsFreshness == .fresh)
    #expect(snapshot.courierFreshness == .fresh)
    #expect(snapshot.isComplete)
    #expect(
      snapshot.characters.first?.excludedContractBlueprintCopyCount == 1
    )
  }

  @Test
  func wealthProjectionCountsCorporationValueOnlyOncePerCorporation() {
    let corporationAssets = AssetSnapshot(
      characterID: 7,
      corporationID: 98_000_001,
      state: .fresh,
      items: [
        AssetItem(
          id: 1,
          typeID: 34,
          quantity: 10,
          locationID: 60_000_001,
          locationKind: .station,
          locationFlag: "CorpSAG1",
          singleton: false
        )
      ]
    )
    let corporationWallet = CorporationWalletSnapshot(
      actingCharacterID: 7,
      corporationID: 98_000_001,
      divisions: [
        ESICorporationWalletDTO(balance: 100, division: 1),
        ESICorporationWalletDTO(balance: 200, division: 2),
      ]
    )
    let inputs = [Int64(7), Int64(8)].map { characterID in
      DashboardWealthCharacterInput(
        character: CharacterIdentity(
          id: characterID,
          name: "Fixture \(characterID)",
          corporationID: 98_000_001
        ),
        wallet: Sourced(state: .fresh, value: 0, source: source),
        assets: Sourced(
          state: .fresh,
          value: AssetSnapshot(
            characterID: characterID,
            state: .fresh,
            items: []
          ),
          source: source
        ),
        openOrders: Sourced(state: .fresh, value: [], source: source),
        privateContracts: Sourced(
          state: .fresh,
          value: PrivateContractSnapshot(
            characterID: characterID,
            itemContracts: [],
            inTransitCouriers: []
          ),
          source: source
        ),
        corporationAssets: Sourced(
          state: .fresh,
          value: corporationAssets,
          source: source
        ),
        corporationWallet: Sourced(
          state: .fresh,
          value: corporationWallet,
          source: source
        )
      )
    }
    let snapshot = DashboardWealthProjector.project(
      inputs: inputs,
      prices: ReferencePriceSnapshot(
        capturedAt: source.capturedAt,
        prices: [
          34: AdjustedPrice(typeID: 34, adjustedPrice: 4, averagePrice: 5)
        ],
        source: source
      )
    )

    #expect(snapshot.corporationAssetTotal == 50)
    #expect(snapshot.corporationWalletTotal == 300)
    #expect(snapshot.knownTotalValue == 350)
    #expect(snapshot.corporationAssetFreshness == .fresh)
    #expect(snapshot.corporationWalletFreshness == .fresh)
    #expect(snapshot.corporationAssetCoverage?.corporationCount == 1)
    #expect(snapshot.corporationAssetCoverage?.includedCorporationCount == 1)
    #expect(snapshot.corporationWalletCoverage?.corporationCount == 1)
    #expect(snapshot.corporationWalletCoverage?.includedCorporationCount == 1)
  }

  @Test
  func wealthProjectionExplainsMissingCorporationRolesByCorporation() {
    let accessibleID: Int64 = 98_000_001
    let inaccessibleID: Int64 = 98_000_002
    let accessible = DashboardWealthCharacterInput(
      character: CharacterIdentity(
        id: 7,
        name: "Director",
        corporationID: accessibleID
      ),
      wallet: Sourced(state: .fresh, value: 0, source: source),
      assets: Sourced(
        state: .fresh,
        value: AssetSnapshot(characterID: 7, state: .fresh, items: []),
        source: source
      ),
      corporationAssets: Sourced(
        state: .fresh,
        value: AssetSnapshot(
          characterID: 7,
          corporationID: accessibleID,
          state: .fresh,
          items: []
        ),
        source: source
      ),
      corporationWallet: Sourced(
        state: .fresh,
        value: CorporationWalletSnapshot(
          actingCharacterID: 7,
          corporationID: accessibleID,
          divisions: []
        ),
        source: source
      )
    )
    let inaccessible = DashboardWealthCharacterInput(
      character: CharacterIdentity(
        id: 8,
        name: "Member",
        corporationID: inaccessibleID
      ),
      wallet: Sourced(state: .fresh, value: 0, source: source),
      assets: Sourced(
        state: .fresh,
        value: AssetSnapshot(characterID: 8, state: .fresh, items: []),
        source: source
      ),
      corporationAssets: Sourced<AssetSnapshot>(
        state: .forbidden,
        value: nil,
        source: source,
        diagnostics: ["esi.corporation-assets.director-required"]
      ),
      corporationWallet: Sourced<CorporationWalletSnapshot>(
        state: .forbidden,
        value: nil,
        source: source,
        diagnostics: ["esi.corporation-wallet.accountant-required"]
      )
    )

    let snapshot = DashboardWealthProjector.project(
      inputs: [accessible, inaccessible],
      prices: ReferencePriceSnapshot(
        capturedAt: source.capturedAt,
        prices: [:],
        source: source
      )
    )

    #expect(snapshot.corporationAssetTotal == 0)
    #expect(snapshot.corporationAssetFreshness == .partial)
    #expect(snapshot.corporationAssetCoverage?.corporationCount == 2)
    #expect(snapshot.corporationAssetCoverage?.includedCorporationCount == 1)
    #expect(snapshot.corporationAssetCoverage?.roleMissingCorporationCount == 1)
    #expect(snapshot.corporationWalletTotal == 0)
    #expect(snapshot.corporationWalletFreshness == .partial)
    #expect(snapshot.corporationWalletCoverage?.corporationCount == 2)
    #expect(snapshot.corporationWalletCoverage?.includedCorporationCount == 1)
    #expect(snapshot.corporationWalletCoverage?.roleMissingCorporationCount == 1)
  }

  @Test
  func legacyWealthCharacterHistoryDecodesNewCountersAsZero() throws {
    let fixture = Data(
      """
      {
        "characterID": 7,
        "characterName": "Fixture",
        "walletValue": 100,
        "assetValue": 50,
        "knownValue": 150,
        "unvaluedAssetTypeCount": 0,
        "isComplete": true,
        "freshness": "fresh"
      }
      """.utf8
    )

    let decoded = try JSONDecoder().decode(
      DashboardWealthCharacterValue.self,
      from: fixture
    )

    #expect(decoded.ordersValue == nil)
    #expect(decoded.excludedBlueprintCopyCount == 0)
    #expect(decoded.unvaluedOrderCount == 0)
    #expect(decoded.missingEscrowOrderCount == 0)
    #expect(decoded.contractsValue == nil)
    #expect(decoded.courierValue == nil)
    #expect(decoded.unvaluedContractItemTypeCount == 0)
    #expect(decoded.excludedContractBlueprintCopyCount == 0)
    #expect(decoded.unavailableContractCount == 0)
    #expect(decoded.invalidCourierCollateralCount == 0)
    #expect(decoded.unvaluedAssetTypes.isEmpty)
    #expect(decoded.unvaluedContractItemTypes.isEmpty)
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

private actor ExpiringCacheTransport: ESIHTTPTransporting {
  private(set) var requestCount = 0

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    return (
      Data(#"{"value":1}"#.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "ETag": #""cache-fixture""#,
          "Expires": "Wed, 30 Jul 2026 10:00:00 GMT",
        ]
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
  private let postDelayMilliseconds: Int
  private(set) var requestCount = 0
  private(set) var requestMethods: [String] = []
  private(set) var postedIDs: [Int64] = []

  init(postDelayMilliseconds: Int = 0) {
    self.postDelayMilliseconds = postDelayMilliseconds
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    requestCount += 1
    requestMethods.append(request.httpMethod ?? "GET")
    let body: String
    if request.httpMethod == "POST" {
      if postDelayMilliseconds > 0 {
        try await Task.sleep(
          for: .milliseconds(postDelayMilliseconds)
        )
      }
      postedIDs = try JSONDecoder().decode(
        [Int64].self,
        from: request.httpBody ?? Data()
      )
      body =
        """
        [
          {"category":"solar_system","id":30000143,"name":"Jitara"},
          {"category":"solar_system","id":30000142,"name":"Jita"},
          {"category":"solar_system","id":30004807,"name":"B9E-H6"}
        ]
        """
    } else {
      body = "[30000143,30000142,30004807]"
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

private actor BatchedSolarSystemSearchTransport: ESIHTTPTransporting {
  private let systemIDs: [Int64]
  private var activePostCount = 0
  private(set) var maximumConcurrentPostCount = 0

  init(systemCount: Int) {
    systemIDs = (0..<systemCount).map {
      30_000_000 + Int64($0)
    }
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let data: Data
    if request.httpMethod == "POST" {
      activePostCount += 1
      maximumConcurrentPostCount = max(
        maximumConcurrentPostCount,
        activePostCount
      )
      defer { activePostCount -= 1 }
      try await Task.sleep(for: .milliseconds(20))
      let ids = try JSONDecoder().decode(
        [Int64].self,
        from: request.httpBody ?? Data()
      )
      let values: [[String: Any]] = ids.map {
        [
          "category": "solar_system",
          "id": $0,
          "name": "SYS-\($0)",
        ]
      }
      data = try JSONSerialization.data(withJSONObject: values)
    } else {
      data = try JSONEncoder().encode(systemIDs)
    }
    return (
      data,
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
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

private struct TradingLocationSearchTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    let body: String
    switch path {
    case "/search", "/search/":
      body = #"{"station":[60000001]}"#
    case "/universe/systems/30000001", "/universe/systems/30000001/":
      body =
        #"{"constellation_id":20000001,"name":"Fixture System","security_status":0.7,"stations":[60000001],"system_id":30000001}"#
    case "/universe/constellations/20000001", "/universe/constellations/20000001/":
      body =
        #"{"constellation_id":20000001,"name":"Fixture Constellation","region_id":10000001}"#
    case "/universe/regions/10000001", "/universe/regions/10000001/":
      body = #"{"name":"Fixture Region","region_id":10000001}"#
    case "/universe/stations/60000001", "/universe/stations/60000001/":
      body =
        #"{"name":"Fixture Trade Station","owner":1000004,"system_id":30000001}"#
    case "/corporations/1000004", "/corporations/1000004/":
      body = #"{"faction_id":500002}"#
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

private struct JitaFactionFallbackTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    let body: String
    let status: Int
    switch path {
    case "/universe/stations/60003760", "/universe/stations/60003760/":
      status = 200
      body =
        #"{"name":"Jita IV - Moon 4 - Caldari Navy Assembly Plant","owner":1000035,"system_id":30000142}"#
    case "/corporations/1000035", "/corporations/1000035/":
      status = 503
      body = #"{"error":"fixture unavailable"}"#
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

private actor AssetStructureResolutionTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let accessible =
      request.url?.path == "/universe/structures/1000000000001"
    let status = accessible ? 200 : 403
    let body =
      accessible
      ? """
      {
        "name":"Low-sec Industry Hub",
        "owner_id":98000001,
        "solar_system_id":30000142,
        "type_id":35826
      }
      """
      : "{}"
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

private actor CorporationAssetTransport: ESIHTTPTransporting {
  let isDirector: Bool
  private(set) var requestedPaths: [String] = []

  init(isDirector: Bool) {
    self.isDirector = isDirector
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    requestedPaths.append(path)
    let body: String
    var headers: [String: String] = [:]
    switch path {
    case "/characters/99/roles":
      body = isDirector ? #"{"roles":["Director"]}"# : #"{"roles":["Member"]}"#
    case "/corporations/98000001/assets":
      let page = URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
      )?.queryItems?.first(where: { $0.name == "page" })?.value
      headers["X-Pages"] = "2"
      body =
        page == "2"
        ? """
        [{
          "item_id":12,
          "location_flag":"CorpSAG2",
          "location_id":60003760,
          "location_type":"station",
          "quantity":7,
          "is_singleton":false,
          "type_id":35
        }]
        """
        : """
        [{
          "item_id":11,
          "location_flag":"CorpSAG1",
          "location_id":60003760,
          "location_type":"station",
          "quantity":5,
          "is_singleton":false,
          "type_id":34
        }]
        """
    case "/corporations/98000001":
      body = #"{"name":"Example Industries"}"#
    case "/corporations/98000001/divisions":
      body = #"{"hangar":[{"division":1,"name":"Minerals"}]}"#
    default:
      body = "{}"
    }
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
    )
  }
}

private actor PrivateContractTransport: ESIHTTPTransporting {
  let failItems: Bool
  private(set) var requestedPaths: [String] = []

  init(failItems: Bool = false) {
    self.failItems = failItems
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    requestedPaths.append(path)
    let status: Int
    let body: String
    switch path {
    case "/characters/99/contracts":
      status = 200
      body = """
        [
          {"contract_id":1,"date_expired":"2026-12-01T00:00:00Z","for_corporation":false,"issuer_id":99,"status":"outstanding","type":"item_exchange"},
          {"contract_id":2,"date_expired":"2026-01-01T00:00:00Z","for_corporation":false,"issuer_id":99,"status":"outstanding","type":"auction"},
          {"collateral":250,"contract_id":3,"date_expired":"2026-12-01T00:00:00Z","for_corporation":false,"issuer_id":99,"status":"in_progress","type":"courier"},
          {"collateral":500,"contract_id":4,"date_expired":"2026-12-01T00:00:00Z","for_corporation":false,"issuer_id":100,"status":"in_progress","type":"courier"},
          {"contract_id":5,"date_expired":"2026-12-01T00:00:00Z","for_corporation":true,"issuer_id":99,"status":"outstanding","type":"item_exchange"}
        ]
        """
    case "/characters/99/contracts/1/items":
      status = failItems ? 404 : 200
      body =
        failItems
        ? "{}"
        : """
        [
          {"is_included":true,"quantity":10,"record_id":1,"type_id":34},
          {"is_included":false,"quantity":4,"record_id":2,"type_id":35}
        ]
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

private actor CorporationWalletTransport: ESIHTTPTransporting {
  let role: String
  private(set) var requestedPaths: [String] = []

  init(role: String) {
    self.role = role
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let path = request.url?.path ?? ""
    requestedPaths.append(path)
    let body: String
    switch path {
    case "/characters/99/roles":
      body = "{\"roles\":[\"\(role)\"]}"
    case "/corporations/98000001/wallets":
      body =
        """
        [
          {"balance":100,"division":1},
          {"balance":200,"division":2}
        ]
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
