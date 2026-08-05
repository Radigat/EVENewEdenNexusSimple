import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Public Contracts index")
struct PublicContractTests {
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
    let store = try PublicContractStore(url: databaseURL)
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
    included: Bool = true
  ) -> ESIPublicContractItemDTO {
    ESIPublicContractItemDTO(
      isIncluded: included,
      quantity: 1,
      recordID: recordID,
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
}

private func makeLegacyContractDatabase(at url: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open(url.path, &database) == SQLITE_OK else {
    throw NSError(domain: "PublicContractTests", code: 1)
  }
  defer { sqlite3_close(database) }
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
      category_id, category_name, is_included, quantity
    ) VALUES(
      42, 1, 28372, 'Ark', 902, 'Jump Freighter', 6, 'Ship', 1, 1
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
  private let itemResponseDelay: Duration?
  private(set) var contractRequestCount = 0
  private(set) var itemRequestCount = 0
  private(set) var concurrentItemRequests = 0
  private(set) var maximumConcurrentItemRequests = 0
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
    itemResponseDelay: Duration? = nil
  ) {
    self.now = now
    self.errorLimitRemain = errorLimitRemain
    self.errorLimitReset = errorLimitReset
    self.contractError = contractError
    self.itemPageCount = itemPageCount
    self.regionIDsValue = regionIDs
    self.contractIDs = contractIDs
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
          type: "item_exchange"
        )
      },
      expiresAt: now.addingTimeInterval(1_800),
      pages: 1
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

  private func response<Value: Sendable>(
    _ value: Value,
    expiresAt: Date?,
    pages: Int? = nil
  ) -> ESIResponse<Value> {
    ESIResponse(
      value: value,
      source: source,
      statusCode: 200,
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
