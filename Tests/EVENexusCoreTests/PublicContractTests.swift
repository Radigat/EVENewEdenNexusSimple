import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Public Contracts index")
struct PublicContractTests {
  @Test
  func contractReferenceUsesLowestComparableUnitPriceAtExactLocation() {
    let now = Date(timeIntervalSince1970: 20_000)
    let locationID: Int64 = 60_003_760
    let snapshot = PublicContractReferenceSnapshot.project(
      locationID: locationID,
      locationName: "Jita IV - Moon 4",
      offers: [
        100: [
          referenceOffer(
            contractID: 1,
            typeID: 100,
            price: 200,
            quantity: 1,
            locationID: locationID,
            now: now
          ),
          referenceOffer(
            contractID: 2,
            typeID: 100,
            price: 300,
            quantity: 2,
            locationID: locationID,
            now: now
          ),
          referenceOffer(
            contractID: 3,
            typeID: 100,
            price: 1,
            quantity: 1,
            locationID: locationID,
            offeredLineCount: 2,
            now: now
          ),
          referenceOffer(
            contractID: 4,
            typeID: 100,
            price: 1,
            quantity: 1,
            locationID: locationID,
            requestedLineCount: 1,
            now: now
          ),
          referenceOffer(
            contractID: 5,
            typeID: 100,
            price: 1,
            quantity: 1,
            locationID: 99,
            now: now
          ),
        ]
      ],
      progress: completeReferenceProgress(now: now),
      limitPerType: 500,
      capturedAt: now
    )

    #expect(snapshot.hasCompleteSearchCoverage)
    #expect(snapshot.prices[100]?.contractID == 2)
    #expect(snapshot.prices[100]?.totalContractPrice == 300)
    #expect(snapshot.prices[100]?.contractQuantity == 2)
    #expect(snapshot.prices[100]?.unitPrice == 150)
  }

  @Test
  func universeWideReferenceUsesLowestComparableRegionAndSupportsFutureScope() {
    let now = Date(timeIntervalSince1970: 20_500)
    let offers: [Int64: [PublicContractSearchResult]] = [
      100: [
        referenceOffer(
          contractID: 10,
          typeID: 100,
          price: 200,
          quantity: 1,
          locationID: 60_003_760,
          regionID: 10_000_002,
          now: now
        ),
        referenceOffer(
          contractID: 11,
          typeID: 100,
          price: 100,
          quantity: 1,
          locationID: 60_002_999,
          regionID: 10_000_043,
          now: now
        ),
      ]
    ]
    let universe = PublicContractReferenceSnapshot.projectUniverseWide(
      offers: offers,
      progress: completeReferenceProgress(now: now),
      limitPerType: 500,
      capturedAt: now
    )
    let selected = PublicContractReferenceSnapshot.projectUniverseWide(
      offers: offers,
      progress: completeReferenceProgress(now: now),
      limitPerType: 500,
      allowedRegionIDs: [10_000_002],
      capturedAt: now
    )

    #expect(universe.prices[100]?.contractID == 11)
    #expect(universe.allowedRegionIDs == nil)
    #expect(selected.prices[100]?.contractID == 10)
    #expect(selected.allowedRegionIDs == [10_000_002])
  }

  @Test
  func contractReferenceKeepsPartialOrTruncatedCoverageUnavailable() {
    let now = Date(timeIntervalSince1970: 21_000)
    let offer = referenceOffer(
      contractID: 7,
      typeID: 101,
      price: 50,
      quantity: 1,
      locationID: 60_003_760,
      now: now
    )
    let partial = PublicContractReferenceSnapshot.project(
      locationID: 60_003_760,
      locationName: "Jita IV - Moon 4",
      offers: [101: [offer]],
      progress: PublicContractSyncProgress(
        phase: .partial,
        regionCount: 2,
        completedRegions: 1,
        freshRegions: 1,
        remainingInitialRegions: 1,
        lastCompletedAt: now
      ),
      limitPerType: 500,
      capturedAt: now
    )
    let truncated = PublicContractReferenceSnapshot.project(
      locationID: 60_003_760,
      locationName: "Jita IV - Moon 4",
      offers: [101: [offer]],
      progress: completeReferenceProgress(now: now),
      limitPerType: 1,
      capturedAt: now
    )

    #expect(!partial.hasCompleteSearchCoverage)
    #expect(!truncated.hasCompleteSearchCoverage)
  }

  @Test
  func publicContractJSONPreservesMissingForCorporationAsUnknown() throws {
    let data = Data(
      #"[{"contract_id":233700434,"date_expired":"2026-08-03T15:41:25Z","date_issued":"2026-07-06T15:41:25Z","issuer_corporation_id":98120737,"issuer_id":93138851,"type":"item_exchange"}]"#
        .utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let contracts = try decoder.decode([ESIPublicContractDTO].self, from: data)

    #expect(contracts.count == 1)
    #expect(contracts.first?.forCorporation == nil)
  }

  @Test
  func publicContractItemJSONPreservesBlueprintRunsMEAndTE() throws {
    let data = Data(
      #"[{"is_blueprint_copy":true,"is_included":true,"material_efficiency":8,"quantity":1,"record_id":7,"runs":25,"time_efficiency":16,"type_id":9001}]"#
        .utf8
    )

    let items = try JSONDecoder().decode(
      [ESIPublicContractItemDTO].self,
      from: data
    )

    #expect(items.first?.isBlueprintCopy == true)
    #expect(items.first?.runs == 25)
    #expect(items.first?.materialEfficiency == 8)
    #expect(items.first?.timeEfficiency == 16)
  }

  @Test
  func attributableBlueprintOfferRejectsBundlesAndPreservesKnownCopyCost()
    async throws
  {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 5_000)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [contract(id: 70, now: now), contract(id: 71, now: now)],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    let blueprint = metadata(
      typeID: 9_001,
      name: "Fixture Blueprint",
      groupID: 9,
      group: "Blueprint",
      categoryID: 9,
      category: "Blueprint"
    )
    try await fixture.store.storeItems(
      contractID: 70,
      items: [
        item(
          recordID: 700,
          typeID: 9_001,
          isBlueprintCopy: true,
          materialEfficiency: 8,
          runs: 25,
          timeEfficiency: 16
        )
      ],
      metadata: [9_001: blueprint],
      fetchedAt: now
    )
    try await fixture.store.storeItems(
      contractID: 71,
      items: [
        item(
          recordID: 710,
          typeID: 9_001,
          isBlueprintCopy: true,
          materialEfficiency: 10,
          runs: 50,
          timeEfficiency: 20
        ),
        item(recordID: 711, typeID: 34, included: false),
      ],
      metadata: [9_001: blueprint],
      fetchedAt: now
    )

    let offers =
      try await fixture.store.includedOffers(
        typeIDs: [9_001],
        now: now
      )[9_001] ?? []
    let single = try #require(offers.first { $0.contractID == 70 })
    let bundle = try #require(offers.first { $0.contractID == 71 })
    #expect(single.isAttributableBlueprintOffer)
    #expect(single.effectiveContractPrice == 1_000_000)
    #expect(single.runs == 25)
    #expect(!bundle.isAttributableBlueprintOffer)
    #expect(bundle.requestedLineCount == 1)
    await fixture.cleanup()
  }

  @Test
  func itemGroupAndCategoryDistinguishArkFromArkonor() async throws {
    let fixture = try ContractStoreFixture()
    let store = fixture.store
    let now = Date(timeIntervalSince1970: 1_000)
    try await store.upsertRegions([(10_000_002, "The Forge")])
    try await store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [
        contract(id: 1, now: now, title: "Ark for sale"),
        contract(id: 2, now: now, title: "Arkonor lot"),
      ],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    try await store.storeItems(
      contractID: 1,
      items: [item(recordID: 11, typeID: 28_372)],
      metadata: [
        28_372: metadata(
          typeID: 28_372,
          name: "Ark",
          groupID: 902,
          group: "Jump Freighter",
          categoryID: 6,
          category: "Ship"
        )
      ],
      fetchedAt: now
    )
    try await store.storeItems(
      contractID: 2,
      items: [item(recordID: 22, typeID: 22)],
      metadata: [
        22: metadata(
          typeID: 22,
          name: "Arkonor",
          groupID: 450,
          group: "Arkonor",
          categoryID: 25,
          category: "Asteroid"
        )
      ],
      fetchedAt: now
    )

    let broad = try await store.search(
      PublicContractSearchFilter(itemQuery: "Ark", direction: .included),
      now: now
    )
    #expect(broad.map(\.typeName) == ["Ark", "Arkonor"])

    let jumpFreighter = try await store.search(
      PublicContractSearchFilter(
        itemQuery: "Ark",
        groupID: 902,
        categoryID: 6,
        direction: .included
      ),
      now: now
    )
    #expect(jumpFreighter.map(\.typeName) == ["Ark"])
    #expect(jumpFreighter.first?.groupName == "Jump Freighter")
    #expect(jumpFreighter.first?.categoryName == "Ship")

    let facets = try await store.facets()
    #expect(facets.categories.map(\.name) == ["Asteroid", "Ship"])
    #expect(facets.groups.contains { $0.name == "Jump Freighter" })
    await fixture.cleanup()
  }

  @Test
  func synchronizationDoesNotRefetchBeforeExpiryOrReloadKnownItems() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 2_000)
    let remote = ContractRemoteFixture(now: now)
    let catalog = ContractCatalogFixture()
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: catalog,
      store: fixture.store,
      regionRequestSpacing: 0.1,
      itemRequestSpacing: 0.25,
      now: { now },
      sleep: { _ in }
    )

    let first = try await indexer.synchronizeAll { _ in }
    #expect(first.phase == .completed)
    #expect(first.indexedContracts == 1)
    #expect(first.indexedItems == 1)
    #expect(await remote.contractRequestCount == 1)
    #expect(await remote.itemRequestCount == 1)
    #expect(await remote.contractCacheReleaseCount == 1)
    #expect(await remote.requestedLocationIDs == [60_003_760])
    let indexed = try await indexer.search(
      PublicContractSearchFilter(itemQuery: "Ark")
    )
    #expect(indexed.first?.startLocationName == "Jita IV - Moon 4 - Caldari Navy Assembly Plant")
    #expect(indexed.first?.endLocationID == 1_000_000_000_042)
    #expect(indexed.first?.endLocationName == nil)

    let second = try await indexer.synchronizeAll { _ in }
    #expect(second.phase == .completed)
    #expect(await remote.contractRequestCount == 1)
    #expect(await remote.itemRequestCount == 1)
    #expect(await remote.contractCacheReleaseCount == 1)
    await fixture.cleanup()
  }

  @Test
  func revalidatedRegionAdvancesFreshnessWithoutRewritingActivatedContracts()
    async throws
  {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 2_250)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [contract(id: 42, now: now, title: "Activated title")],
      fetchedAt: now.addingTimeInterval(-3_600),
      nextAllowedAt: now
    )
    try await fixture.store.storeItems(
      contractID: 42,
      items: [item(recordID: 1, typeID: 28_372)],
      metadata: [
        28_372: metadata(
          typeID: 28_372,
          name: "Ark",
          groupID: 902,
          group: "Jump Freighter",
          categoryID: 6,
          category: "Ship"
        )
      ],
      fetchedAt: now.addingTimeInterval(-3_600)
    )
    let remote = ContractRemoteFixture(
      now: now,
      contractStatusCode: 304,
      contractTitle: "Unactivated 304 payload"
    )
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      now: { now },
      sleep: { _ in }
    )

    let result = try await indexer.synchronizeAll { _ in }
    let rows = try await fixture.store.search(
      PublicContractSearchFilter(itemQuery: "Ark"),
      now: now
    )

    #expect(result.phase == .completed)
    #expect(rows.first?.title == "Activated title")
    #expect(await remote.itemRequestCount == 0)
    await fixture.cleanup()
  }

  @Test
  func synchronizationLoadsEveryContractItemPageBeforeActivation() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 2_500)
    let remote = ContractRemoteFixture(now: now, itemPageCount: 2)
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      regionRequestSpacing: 0.1,
      itemRequestSpacing: 0.25,
      now: { now },
      sleep: { _ in }
    )

    let result = try await indexer.synchronizeAll { _ in }

    #expect(result.phase == .completed)
    #expect(result.indexedItems == 2)
    #expect(await remote.itemRequestCount == 2)
    await fixture.cleanup()
  }

  @Test
  func pendingWorkPrunesExpiredContractsAndSkipsDetailFreeTypes() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 2_750)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [
        contract(id: 71, now: now),
        contract(id: 72, now: now, type: "courier"),
        contract(id: 73, now: now, expiresAfter: -1),
      ],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )

    let pending = try await fixture.store.pendingContractIDs(now: now)
    let progress = try await fixture.store.progress()

    #expect(pending == [71])
    #expect(progress.indexedContracts == 2)
    #expect(progress.pendingItemContracts == 1)
    #expect(progress.failedItemContracts == 0)
    await fixture.cleanup()
  }

  @Test
  func itemImportBoundsConcurrencyAndReleasesOneShotResponseBodies() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 2_900)
    let remote = ContractRemoteFixture(
      now: now,
      contractIDs: [81, 82, 83, 84],
      itemResponseDelay: .milliseconds(20)
    )
    let sleeps = ContractSleepRecorder()
    let progress = ContractProgressRecorder()
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      itemRequestSpacing: 0.5,
      itemRequestConcurrency: 2,
      itemBatchSize: 4,
      now: { now },
      sleep: { delay in await sleeps.record(delay) }
    )

    let result = try await indexer.synchronizeAll { state in
      progress.record(state)
    }

    #expect(result.phase == .completed)
    #expect(await remote.itemRequestCount == 4)
    #expect(await remote.maximumConcurrentItemRequests == 2)
    #expect(await remote.itemCacheReleaseCount >= 4)
    #expect(await sleeps.values.contains { $0 >= 0.5 })
    #expect(await progress.loadingItemUpdates == 1)
    await fixture.cleanup()
  }

  @Test
  func requestedItemsRemainSeparateFromOfferedItems() async throws {
    let fixture = try ContractStoreFixture()
    let store = fixture.store
    let now = Date(timeIntervalSince1970: 3_000)
    try await store.upsertRegions([(10_000_002, "The Forge")])
    try await store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [contract(id: 3, now: now)],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    try await store.storeItems(
      contractID: 3,
      items: [
        item(recordID: 31, typeID: 28_372, included: true),
        item(recordID: 32, typeID: 34, included: false),
      ],
      metadata: [
        28_372: metadata(
          typeID: 28_372,
          name: "Ark",
          groupID: 902,
          group: "Jump Freighter",
          categoryID: 6,
          category: "Ship"
        ),
        34: metadata(
          typeID: 34,
          name: "Tritanium",
          groupID: 18,
          group: "Mineral",
          categoryID: 4,
          category: "Material"
        ),
      ],
      fetchedAt: now
    )

    let requested = try await store.search(
      PublicContractSearchFilter(
        itemQuery: "Tritanium",
        direction: .requested
      ),
      now: now
    )
    #expect(requested.count == 1)
    #expect(requested.first?.isIncluded == false)
    let offered = try await store.search(
      PublicContractSearchFilter(
        itemQuery: "Tritanium",
        direction: .included
      ),
      now: now
    )
    #expect(offered.isEmpty)
    await fixture.cleanup()
  }

  @Test
  func industryOfferLookupUsesExactTypeIDsAndBoundsResultsPerType()
    async throws
  {
    let fixture = try ContractStoreFixture()
    let store = fixture.store
    let now = Date(timeIntervalSince1970: 3_250)
    try await store.upsertRegions([(10_000_002, "The Forge")])
    try await store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [
        contract(id: 61, now: now),
        contract(id: 62, now: now),
        contract(id: 63, now: now),
      ],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    let ark = metadata(
      typeID: 28_372,
      name: "Ark Blueprint",
      groupID: 902,
      group: "Jump Freighter Blueprint",
      categoryID: 9,
      category: "Blueprint"
    )
    try await store.storeItems(
      contractID: 61,
      items: [item(recordID: 611, typeID: 28_372)],
      metadata: [28_372: ark],
      fetchedAt: now
    )
    try await store.storeItems(
      contractID: 62,
      items: [item(recordID: 621, typeID: 28_372)],
      metadata: [28_372: ark],
      fetchedAt: now
    )
    try await store.storeItems(
      contractID: 63,
      items: [item(recordID: 631, typeID: 22, included: false)],
      metadata: [
        22: metadata(
          typeID: 22,
          name: "Arkonor Blueprint",
          groupID: 450,
          group: "Asteroid",
          categoryID: 25,
          category: "Asteroid"
        )
      ],
      fetchedAt: now
    )

    let offers = try await store.includedOffers(
      typeIDs: [28_372, 22, -1],
      now: now,
      limitPerType: 1
    )

    #expect(offers[28_372]?.map(\.contractID) == [61])
    #expect(offers[22] == nil)
    #expect(offers[-1] == nil)
    await fixture.cleanup()
  }

  @Test
  func completeSearchCoverageRejectsPartialStaleOrFailedIndexes() {
    let complete = PublicContractSyncProgress(
      phase: .completed,
      regionCount: 2,
      completedRegions: 2,
      freshRegions: 2
    )

    #expect(complete.hasCompleteSearchCoverage)
    #expect(
      !PublicContractSyncProgress(
        regionCount: 2,
        completedRegions: 2,
        freshRegions: 1
      ).hasCompleteSearchCoverage
    )
    #expect(
      !PublicContractSyncProgress(
        regionCount: 2,
        completedRegions: 2,
        freshRegions: 2,
        pendingItemContracts: 1
      ).hasCompleteSearchCoverage
    )
    #expect(
      !PublicContractSyncProgress(
        regionCount: 2,
        completedRegions: 2,
        freshRegions: 2,
        failedRegions: 1
      ).hasCompleteSearchCoverage
    )
  }

  @Test
  func missingForCorporationRemainsUnknownInTheLocalIndex() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 3_500)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [contract(id: 35, now: now, forCorporation: nil)],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    try await fixture.store.storeItems(
      contractID: 35,
      items: [item(recordID: 351, typeID: 28_372)],
      metadata: [
        28_372: metadata(
          typeID: 28_372,
          name: "Ark",
          groupID: 902,
          group: "Jump Freighter",
          categoryID: 6,
          category: "Ship"
        )
      ],
      fetchedAt: now
    )

    let results = try await fixture.store.search(
      PublicContractSearchFilter(itemQuery: "Ark"),
      now: now
    )

    #expect(results.first?.forCorporation == nil)
    await fixture.cleanup()
  }

  @Test
  func legacyContractStoreMigrationPreservesDataAndAllowsUnknownCorporationFlag()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-public-contracts-legacy-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let databaseURL = root.appendingPathComponent("contracts.sqlite")
    try makeLegacyContractDatabase(at: databaseURL)
    let store = try await PublicContractStore.open(url: databaseURL)
    let now = Date(timeIntervalSince1970: 10_000)

    let preserved = try await store.search(
      PublicContractSearchFilter(itemQuery: "Ark"),
      now: now
    )
    #expect(preserved.count == 1)
    #expect(preserved.first?.forCorporation == true)

    try await store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [contract(id: 42, now: now, forCorporation: nil)],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    let updated = try await store.search(
      PublicContractSearchFilter(itemQuery: "Ark"),
      now: now
    )
    let progress = try await store.progress()

    #expect(updated.count == 1)
    #expect(updated.first?.forCorporation == nil)
    #expect(progress.indexedContracts == 1)
    #expect(progress.indexedItems == 1)
    await store.close()
    try? FileManager.default.removeItem(at: root)
  }

  @Test
  func blueprintDetailMigrationDoesNotQueueEveryExistingBlueprintContract()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-public-contracts-blueprint-details-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let databaseURL = root.appendingPathComponent("contracts.sqlite")
    try makeLegacyContractDatabase(at: databaseURL, containsBlueprint: true)
    let store = try await PublicContractStore.open(url: databaseURL)
    let now = Date(timeIntervalSince1970: 10_000)

    let pending = try await store.pendingContractIDs(now: now)
    let preserved = try await store.search(
      PublicContractSearchFilter(itemQuery: "Ark Blueprint"),
      now: now
    )

    #expect(pending.isEmpty)
    #expect(preserved.count == 1)
    #expect(preserved.first?.runs == nil)
    #expect(preserved.first?.materialEfficiency == nil)
    #expect(preserved.first?.timeEfficiency == nil)
    await store.close()
    try? FileManager.default.removeItem(at: root)
  }

  @Test
  func unboundedBlueprintBackfillRollbackPreservesRowsAndFailedWork()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-public-contracts-blueprint-rollback-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let databaseURL = root.appendingPathComponent("contracts.sqlite")
    try makeLegacyContractDatabase(at: databaseURL, containsBlueprint: true)
    let initialStore = try await PublicContractStore.open(url: databaseURL)
    await initialStore.close()
    try markLegacyBlueprintBackfillPending(at: databaseURL)

    let repairedStore = try await PublicContractStore.open(url: databaseURL)
    let now = Date(timeIntervalSince1970: 10_000)
    let pending = try await repairedStore.pendingContractIDs(now: now)
    let preserved = try await repairedStore.search(
      PublicContractSearchFilter(itemQuery: "Ark Blueprint"),
      now: now
    )

    #expect(pending == [43])
    #expect(preserved.map(\.contractID) == [42, 43])
    await repairedStore.close()
    try? FileManager.default.removeItem(at: root)
  }

  @Test
  func lowErrorBudgetForcesResetWaitBeforeContinuing() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 4_000)
    let remote = ContractRemoteFixture(
      now: now,
      errorLimitRemain: 10,
      errorLimitReset: 7
    )
    let sleeps = ContractSleepRecorder()
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      errorBudgetFloor: 20,
      now: { now },
      sleep: { delay in await sleeps.record(delay) }
    )

    let result = try await indexer.synchronizeAll { _ in }
    let recordedSleeps = await sleeps.values

    #expect(result.phase == .completed)
    #expect(recordedSleeps.filter { $0 == 8 }.count >= 3)
    await fixture.cleanup()
  }

  @Test
  func rateLimitStopsTheRunWithoutStartingDetailRequests() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 5_000)
    let remote = ContractRemoteFixture(
      now: now,
      contractError: .rateLimited(retryAfter: 120)
    )
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      now: { now },
      sleep: { _ in }
    )

    let result = try await indexer.synchronizeAll { _ in }

    #expect(result.phase == .throttled)
    #expect(result.nextRequestAt == now.addingTimeInterval(120))
    #expect(await remote.itemRequestCount == 0)
    await fixture.cleanup()
  }

  @Test
  func automaticUpdatesRequireOptInAndPersistTheirSafetyWindow() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 6_000)

    let disabled = try await fixture.store.automationState(now: now)
    #expect(!disabled.isEnabled)
    #expect(disabled.nextAutomaticRunAt == nil)

    try await fixture.store.setAutomaticUpdatesEnabled(true)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(1_800)
    )
    let safetyDate = now.addingTimeInterval(8 * 60 * 60)
    try await fixture.store.setAutomaticSafetyNotBefore(safetyDate)
    await fixture.store.close()

    let reopened = try PublicContractStore(url: fixture.databaseURL)
    let restored = try await reopened.automationState(
      now: now,
      regularRefreshInterval: 6 * 60 * 60
    )

    #expect(restored.isEnabled)
    #expect(restored.safetyNotBefore == safetyDate)
    #expect(restored.nextAutomaticRunAt == safetyDate)
    await reopened.close()
    fixture.removeFiles()
  }

  @Test
  func failedInitialRegionsRemainWorkAndUseTheirEarliestRetry() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 6_500)
    let firstRetry = now.addingTimeInterval(120)
    try await fixture.store.setAutomaticUpdatesEnabled(true)
    try await fixture.store.upsertRegions([
      (10_000_001, "Derelik"),
      (10_000_002, "The Forge"),
    ])
    try await fixture.store.recordRegionFailure(
      regionID: 10_000_001,
      attemptedAt: now,
      retryAt: firstRetry,
      diagnostic: "esi.public-contracts.schema-mismatch"
    )
    try await fixture.store.recordRegionFailure(
      regionID: 10_000_002,
      attemptedAt: now,
      retryAt: now.addingTimeInterval(300),
      diagnostic: "esi.public-contracts.schema-mismatch"
    )

    let automation = try await fixture.store.automationState(now: now)
    let progress = try await fixture.store.progress()

    #expect(automation.nextAutomaticRunAt == firstRetry)
    #expect(progress.completedRegions == 0)
    #expect(progress.remainingInitialRegions == 2)
    #expect(progress.failedRegions == 2)
    #expect(progress.regionErrorMessage == "esi.public-contracts.schema-mismatch")
    #expect(progress.failedRegionRetryAt == firstRetry)
    await fixture.cleanup()
  }

  @Test
  func refreshFailureDoesNotEraseFirstImportCompletion() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 6_800)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [],
      fetchedAt: now,
      nextAllowedAt: now.addingTimeInterval(60)
    )
    try await fixture.store.recordRegionFailure(
      regionID: 10_000_002,
      attemptedAt: now.addingTimeInterval(60),
      retryAt: now.addingTimeInterval(3_600),
      diagnostic: "esi.public-contracts.schema-mismatch"
    )

    let progress = try await fixture.store.progress()

    #expect(progress.completedRegions == 1)
    #expect(progress.remainingInitialRegions == 0)
    #expect(progress.freshRegions == 0)
    #expect(progress.failedRegions == 1)
    await fixture.cleanup()
  }

  @Test
  func repeatedSchemaFailuresStopBeforeEveryRegionIsRequested() async throws {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 6_900)
    let remote = ContractRemoteFixture(
      now: now,
      contractError: .decoding,
      regionIDs: Array(10_000_001...10_000_005)
    )
    let indexer = PublicContractIndexer(
      remote: remote,
      catalog: ContractCatalogFixture(),
      store: fixture.store,
      regionRequestSpacing: 0.1,
      itemRequestSpacing: 0.25,
      schemaFailureLimit: 3,
      now: { now },
      sleep: { _ in }
    )

    let result = try await indexer.synchronizeAll { _ in }

    #expect(result.phase == .partial)
    #expect(result.failedRegions == 3)
    #expect(result.remainingInitialRegions == 5)
    #expect(result.nextRequestAt == now.addingTimeInterval(60 * 60))
    #expect(await remote.contractRequestCount == 3)
    #expect(await remote.itemRequestCount == 0)
    await fixture.cleanup()
  }

  @Test
  func automaticPolicyUsesConservativeRetryWindows() {
    let now = Date(timeIntervalSince1970: 7_000)
    let throttledUntil = now.addingTimeInterval(120)

    #expect(
      PublicContractAutomationPolicy.safetyNotBefore(
        after: PublicContractSyncProgress(
          phase: .throttled,
          nextRequestAt: throttledUntil
        ),
        now: now
      ) == throttledUntil
    )
    #expect(
      PublicContractAutomationPolicy.safetyNotBefore(
        after: PublicContractSyncProgress(
          phase: .partial,
          pendingItemContracts: 1
        ),
        now: now
      ) == now.addingTimeInterval(15 * 60)
    )
    #expect(
      PublicContractAutomationPolicy.safetyNotBefore(
        after: PublicContractSyncProgress(phase: .partial),
        now: now
      ) == nil
    )
    #expect(
      PublicContractAutomationPolicy.safetyNotBefore(
        after: PublicContractSyncProgress(phase: .failed),
        now: now
      ) == now.addingTimeInterval(30 * 60)
    )
    #expect(
      PublicContractAutomationPolicy.safetyNotBefore(
        after: PublicContractSyncProgress(phase: .completed),
        now: now
      ) == nil
    )
  }

  @Test
  func manualRefreshBypassesTheLocalAutomationSafetyWindow() {
    let now = Date(timeIntervalSince1970: 8_000)
    let safety = now.addingTimeInterval(15 * 60)

    #expect(
      PublicContractAutomationPolicy.shouldDeferStart(
        manualStart: false,
        safetyNotBefore: safety,
        now: now
      )
    )
    #expect(
      !PublicContractAutomationPolicy.shouldDeferStart(
        manualStart: true,
        safetyNotBefore: safety,
        now: now
      )
    )
  }

  @Test
  func bulkRegionPersistenceKeepsEveryContractAndReportsItsDuration()
    async throws
  {
    let fixture = try ContractStoreFixture()
    let now = Date(timeIntervalSince1970: 9_000)
    let contracts = (1...10_000).map {
      contract(id: Int64($0), now: now)
    }
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    let clock = ContinuousClock()

    let elapsed = try await clock.measure {
      try await fixture.store.recordRegionSuccess(
        regionID: 10_000_002,
        contracts: contracts,
        fetchedAt: now,
        nextAllowedAt: now.addingTimeInterval(1_800)
      )
    }

    let progress = try await fixture.store.progress()
    #expect(progress.activeContracts == contracts.count)
    print("public-contract-bulk-upsert count=10000 duration=\(elapsed)")
    await fixture.cleanup()
  }

  @Test
  func unchangedSuccessfulRegionDoesNotRewriteExistingContractRows()
    async throws
  {
    let fixture = try ContractStoreFixture()
    let observedAt = Date(timeIntervalSince1970: 9_500)
    let unchanged = contract(id: 42, now: observedAt)
    try await fixture.store.upsertRegions([(10_000_002, "The Forge")])
    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [unchanged],
      fetchedAt: observedAt,
      nextAllowedAt: observedAt.addingTimeInterval(1_800)
    )

    try await fixture.store.recordRegionSuccess(
      regionID: 10_000_002,
      contracts: [unchanged],
      fetchedAt: observedAt.addingTimeInterval(60),
      nextAllowedAt: observedAt.addingTimeInterval(1_860)
    )
    await fixture.store.close()

    #expect(
      try contractObservedAt(at: fixture.databaseURL, contractID: 42)
        == observedAt.timeIntervalSince1970
    )
    fixture.removeFiles()
  }

  private func contract(
    id: Int64,
    now: Date,
    title: String? = nil,
    forCorporation: Bool? = false,
    type: String = "item_exchange",
    expiresAfter: TimeInterval = 86_400
  ) -> ESIPublicContractDTO {
    ESIPublicContractDTO(
      contractID: id,
      dateExpired: now.addingTimeInterval(expiresAfter),
      dateIssued: now,
      forCorporation: forCorporation,
      issuerCorporationID: 99,
      issuerID: 100,
      price: 1_000_000,
      startLocationID: 60_003_760,
      title: title,
      type: type
    )
  }

  private func item(
    recordID: Int64,
    typeID: Int64,
    included: Bool = true,
    isBlueprintCopy: Bool? = nil,
    materialEfficiency: Int? = nil,
    runs: Int? = nil,
    timeEfficiency: Int? = nil
  ) -> ESIPublicContractItemDTO {
    ESIPublicContractItemDTO(
      isBlueprintCopy: isBlueprintCopy,
      isIncluded: included,
      materialEfficiency: materialEfficiency,
      quantity: 1,
      recordID: recordID,
      runs: runs,
      timeEfficiency: timeEfficiency,
      typeID: typeID
    )
  }

  private func metadata(
    typeID: Int64,
    name: String,
    groupID: Int64,
    group: String,
    categoryID: Int64,
    category: String
  ) -> PublicContractItemTypeMetadata {
    PublicContractItemTypeMetadata(
      typeID: typeID,
      typeName: name,
      groupID: groupID,
      groupName: group,
      categoryID: categoryID,
      categoryName: category
    )
  }

  private func referenceOffer(
    contractID: Int64,
    typeID: Int64,
    price: Double,
    quantity: Int64,
    locationID: Int64,
    regionID: Int64 = EVEConstants.theForgeRegionID,
    offeredLineCount: Int = 1,
    requestedLineCount: Int = 0,
    now: Date
  ) -> PublicContractSearchResult {
    PublicContractSearchResult(
      contractID: contractID,
      recordID: contractID * 10,
      regionID: regionID,
      regionName: "The Forge",
      contractType: "item_exchange",
      price: price,
      dateIssued: now,
      dateExpired: now.addingTimeInterval(86_400),
      startLocationID: locationID,
      startLocationName: "Fixture Location",
      typeID: typeID,
      typeName: "Fixture Product",
      isIncluded: true,
      quantity: quantity,
      offeredLineCount: offeredLineCount,
      requestedLineCount: requestedLineCount
    )
  }

  private func completeReferenceProgress(
    now: Date
  ) -> PublicContractSyncProgress {
    PublicContractSyncProgress(
      phase: .completed,
      regionCount: 2,
      completedRegions: 2,
      freshRegions: 2,
      remainingInitialRegions: 0,
      lastCompletedAt: now
    )
  }
}

private func makeLegacyContractDatabase(
  at url: URL,
  containsBlueprint: Bool = false
) throws {
  var database: OpaquePointer?
  guard sqlite3_open(url.path, &database) == SQLITE_OK else {
    throw NSError(domain: "PublicContractTests", code: 1)
  }
  defer { sqlite3_close(database) }
  let itemValues =
    containsBlueprint
    ? "42, 1, 28372, 'Ark Blueprint', 902, 'Jump Freighter Blueprint', 9, 'Blueprint', 1, 1, 1"
    : "42, 1, 28372, 'Ark', 902, 'Jump Freighter', 6, 'Ship', 1, 1, NULL"
  let sql = """
    PRAGMA foreign_keys=ON;
    CREATE TABLE regions(
      region_id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      last_attempt_at REAL,
      last_success_at REAL,
      next_allowed_at REAL,
      status TEXT NOT NULL DEFAULT 'pending',
      error_message TEXT
    );
    CREATE TABLE contracts(
      contract_id INTEGER PRIMARY KEY,
      region_id INTEGER NOT NULL REFERENCES regions(region_id),
      issuer_id INTEGER NOT NULL,
      issuer_corporation_id INTEGER NOT NULL,
      for_corporation INTEGER NOT NULL,
      contract_type TEXT NOT NULL,
      title TEXT,
      price REAL,
      buyout REAL,
      reward REAL,
      collateral REAL,
      volume REAL,
      date_issued REAL NOT NULL,
      date_expired REAL NOT NULL,
      days_to_complete INTEGER,
      start_location_id INTEGER,
      end_location_id INTEGER,
      observed_at REAL NOT NULL,
      item_status TEXT NOT NULL DEFAULT 'pending',
      item_fetched_at REAL,
      item_error TEXT
    );
    CREATE TABLE contract_items(
      contract_id INTEGER NOT NULL REFERENCES contracts(contract_id)
        ON DELETE CASCADE,
      record_id INTEGER NOT NULL,
      type_id INTEGER NOT NULL,
      type_name TEXT,
      group_id INTEGER,
      group_name TEXT,
      category_id INTEGER,
      category_name TEXT,
      is_included INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      item_id INTEGER,
      raw_quantity INTEGER,
      is_blueprint_copy INTEGER,
      PRIMARY KEY(contract_id, record_id)
    );
    INSERT INTO regions(
      region_id, name, last_attempt_at, last_success_at,
      next_allowed_at, status
    ) VALUES(10000002, 'The Forge', 9000, 9000, 10800, 'fresh');
    INSERT INTO contracts(
      contract_id, region_id, issuer_id, issuer_corporation_id,
      for_corporation, contract_type, price, date_issued, date_expired,
      observed_at, item_status, item_fetched_at
    ) VALUES(
      42, 10000002, 100, 99, 1, 'item_exchange', 1000000,
      9000, 100000, 9000, 'ready', 9000
    );
    INSERT INTO contract_items(
      contract_id, record_id, type_id, type_name, group_id, group_name,
      category_id, category_name, is_included, quantity, is_blueprint_copy
    ) VALUES(
      \(itemValues)
    );
    """
  var errorPointer: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
    let message = errorPointer.map { String(cString: $0) } ?? "legacy schema"
    sqlite3_free(errorPointer)
    throw NSError(
      domain: "PublicContractTests",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private func contractObservedAt(at url: URL, contractID: Int64) throws
  -> Double?
{
  var database: OpaquePointer?
  guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
  else {
    throw NSError(domain: "PublicContractTests", code: 5)
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT observed_at FROM contracts WHERE contract_id=?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw NSError(domain: "PublicContractTests", code: 6)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, contractID)
  guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
  return sqlite3_column_double(statement, 0)
}

private func markLegacyBlueprintBackfillPending(at url: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open(url.path, &database) == SQLITE_OK else {
    throw NSError(domain: "PublicContractTests", code: 3)
  }
  defer { sqlite3_close(database) }
  let sql = """
    INSERT INTO contracts(
      contract_id, region_id, issuer_id, issuer_corporation_id,
      for_corporation, contract_type, price, date_issued, date_expired,
      observed_at, item_status, item_fetched_at, item_error
    ) SELECT
      43, region_id, issuer_id, issuer_corporation_id,
      for_corporation, contract_type, price, date_issued, date_expired,
      observed_at, 'pending', item_fetched_at, 'temporary'
    FROM contracts WHERE contract_id=42;
    INSERT INTO contract_items(
      contract_id, record_id, type_id, type_name, group_id, group_name,
      category_id, category_name, is_included, quantity, item_id,
      raw_quantity, is_blueprint_copy, material_efficiency,
      time_efficiency, runs
    ) SELECT
      43, 2, type_id, type_name, group_id, group_name,
      category_id, category_name, is_included, quantity, item_id,
      raw_quantity, is_blueprint_copy, material_efficiency,
      time_efficiency, runs
    FROM contract_items WHERE contract_id=42;
    UPDATE contracts
    SET item_status='pending', item_error=NULL
    WHERE contract_id=42;
    INSERT INTO contract_settings(key, value)
    VALUES('blueprint_item_details_backfill_v1', 'complete');
    """
  var errorPointer: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
    let message = errorPointer.map { String(cString: $0) } ?? "backfill fixture"
    sqlite3_free(errorPointer)
    throw NSError(
      domain: "PublicContractTests",
      code: 4,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private struct ContractStoreFixture {
  let root: URL
  let databaseURL: URL
  let store: PublicContractStore

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-public-contracts-\(UUID().uuidString)",
      isDirectory: true
    )
    databaseURL = root.appendingPathComponent("contracts.sqlite")
    store = try PublicContractStore(url: databaseURL)
  }

  func cleanup() async {
    await store.close()
    removeFiles()
  }

  func removeFiles() {
    try? FileManager.default.removeItem(at: root)
  }
}

private actor ContractRemoteFixture: PublicContractRemoteFetching {
  private let now: Date
  private let errorLimitRemain: Int
  private let errorLimitReset: Int
  private let contractError: ESIError?
  private let itemPageCount: Int
  private let regionIDsValue: [Int64]
  private let contractIDs: [Int64]
  private let contractStatusCode: Int
  private let contractTitle: String?
  private let itemResponseDelay: Duration?
  private(set) var contractRequestCount = 0
  private(set) var itemRequestCount = 0
  private(set) var concurrentItemRequests = 0
  private(set) var maximumConcurrentItemRequests = 0
  private(set) var contractCacheReleaseCount = 0
  private(set) var itemCacheReleaseCount = 0
  private(set) var requestedLocationIDs: Set<Int64> = []

  init(
    now: Date,
    errorLimitRemain: Int = 100,
    errorLimitReset: Int = 60,
    contractError: ESIError? = nil,
    itemPageCount: Int = 1,
    regionIDs: [Int64] = [10_000_002],
    contractIDs: [Int64] = [42],
    contractStatusCode: Int = 200,
    contractTitle: String? = nil,
    itemResponseDelay: Duration? = nil
  ) {
    self.now = now
    self.errorLimitRemain = errorLimitRemain
    self.errorLimitReset = errorLimitReset
    self.contractError = contractError
    self.itemPageCount = itemPageCount
    self.regionIDsValue = regionIDs
    self.contractIDs = contractIDs
    self.contractStatusCode = contractStatusCode
    self.contractTitle = contractTitle
    self.itemResponseDelay = itemResponseDelay
  }

  func regionIDs() async throws -> ESIResponse<[Int64]> {
    response(regionIDsValue, expiresAt: now.addingTimeInterval(86_400))
  }

  func regionNames(ids: Set<Int64>) async -> Sourced<[Int64: String]> {
    Sourced(
      state: .fresh,
      value: Dictionary(
        uniqueKeysWithValues: ids.map { ($0, "Region \($0)") }
      ),
      source: source
    )
  }

  func locationNames(ids: Set<Int64>) async -> Sourced<[Int64: String]> {
    requestedLocationIDs.formUnion(ids)
    return Sourced(
      state: .fresh,
      value: [
        60_003_760: "Jita IV - Moon 4 - Caldari Navy Assembly Plant"
      ],
      source: source
    )
  }

  func contracts(
    regionID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractDTO]> {
    contractRequestCount += 1
    if let contractError { throw contractError }
    return response(
      contractIDs.map { contractID in
        ESIPublicContractDTO(
          contractID: contractID,
          dateExpired: now.addingTimeInterval(86_400),
          dateIssued: now,
          endLocationID: 1_000_000_000_042,
          forCorporation: false,
          issuerCorporationID: 99,
          issuerID: 100,
          price: 1_000_000,
          startLocationID: 60_003_760,
          title: contractTitle,
          type: "item_exchange"
        )
      },
      expiresAt: now.addingTimeInterval(1_800),
      pages: 1,
      statusCode: contractStatusCode
    )
  }

  func items(
    contractID: Int64,
    page: Int
  ) async throws -> ESIResponse<[ESIPublicContractItemDTO]> {
    itemRequestCount += 1
    concurrentItemRequests += 1
    defer { concurrentItemRequests -= 1 }
    maximumConcurrentItemRequests = max(
      maximumConcurrentItemRequests,
      concurrentItemRequests
    )
    if let itemResponseDelay {
      try await Task.sleep(for: itemResponseDelay)
    }
    return response(
      [
        ESIPublicContractItemDTO(
          isIncluded: true,
          quantity: 1,
          recordID: Int64(page),
          typeID: 28_372
        )
      ],
      expiresAt: now.addingTimeInterval(3_600),
      pages: itemPageCount
    )
  }

  func releaseCachedItemResponses(contractID: Int64?) async {
    itemCacheReleaseCount += 1
  }

  func releaseCachedContractResponses(regionID: Int64?) async {
    contractCacheReleaseCount += 1
  }

  private func response<Value: Sendable>(
    _ value: Value,
    expiresAt: Date?,
    pages: Int? = nil,
    statusCode: Int = 200
  ) -> ESIResponse<Value> {
    ESIResponse(
      value: value,
      source: source,
      statusCode: statusCode,
      expiresAt: expiresAt,
      lastModified: "fixture",
      pages: pages,
      errorLimitRemain: errorLimitRemain,
      errorLimitReset: errorLimitReset
    )
  }

  private var source: SourceIdentity {
    SourceIdentity(
      provider: "ESI fixture",
      version: EVEConstants.esiCompatibilityDate,
      capturedAt: now,
      snapshotID: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
    )
  }
}

private actor ContractSleepRecorder {
  private(set) var values: [TimeInterval] = []

  func record(_ value: TimeInterval) {
    values.append(value)
  }
}

@MainActor
private final class ContractProgressRecorder {
  private var values: [PublicContractSyncProgress] = []

  func record(_ value: PublicContractSyncProgress) {
    values.append(value)
  }

  var loadingItemUpdates: Int {
    values.filter { $0.phase == .loadingItems }.count
  }
}

private struct ContractCatalogFixture: PublicContractTypeMetadataQuerying {
  func publicContractItemMetadata(
    typeIDs: Set<Int64>
  ) async throws -> [Int64: PublicContractItemTypeMetadata] {
    guard typeIDs.contains(28_372) else { return [:] }
    return [
      28_372: PublicContractItemTypeMetadata(
        typeID: 28_372,
        typeName: "Ark",
        groupID: 902,
        groupName: "Jump Freighter",
        categoryID: 6,
        categoryName: "Ship"
      )
    ]
  }
}
