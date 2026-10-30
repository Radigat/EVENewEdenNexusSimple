import AppKit
import Combine
@testable import EVENexusCore
import SwiftData
import SwiftUI
import Testing

@testable import EVENexusSimpleApp

@MainActor
struct RuntimeFeatureStateTests {
  @Test
  func structureHubAnalysisKeepsItsProductScopeOnTheFullBook() {
    func order(_ id: Int64, _ typeID: Int64) -> MarketOrder {
      MarketOrder(
        id: id,
        typeID: typeID,
        locationID: 1_000,
        systemID: 1,
        side: .sell,
        price: 10,
        volumeRemaining: 1,
        minimumVolume: 1,
        issued: .now
      )
    }
    let book = MarketOrderSnapshot(
      id: UUID(),
      regionID: 10,
      locationID: 1_000,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [100: [order(1, 100)], 777: [order(2, 777)]],
      source: SourceIdentity(provider: "fixture", version: "1")
    )
    let structure = RuntimeState.opportunityAnalysisMarket(
      book,
      target: .playerStructure(structureID: 1_000, systemID: 1, regionID: 10),
      productTypeIDs: [100]
    )
    let station = RuntimeState.opportunityAnalysisMarket(
      book,
      target: .npcStation(regionID: 10, locationID: 1_000),
      productTypeIDs: [100]
    )

    #expect(Set(structure.ordersByType.keys) == [100])
    #expect(structure.source.snapshotID == book.source.snapshotID)
    #expect(Set(station.ordersByType.keys) == [100, 777])
  }

  @Test
  func tradeFollowsCoalitionHubOpportunitiesWithFourRoutes() {
    let sections = NavigationSection.allCases
    let coalition = sections.firstIndex(of: .coalitionHubOpportunities)
    let trade = sections.firstIndex(of: .trade)
    #expect(coalition != nil && trade == coalition.map { $0 + 1 })
    #expect(NavigationSection.establishedCases.contains(.trade))
    #expect(TradeModeOption.allCases.map(\.mode) == TradeMode.allCases)
    let runtime = RuntimeState(startBackgroundServices: false)
    // Without configured hubs no market data or fees are invented.
    #expect(runtime.tradeDataRole(for: .home) == nil)
    #expect(runtime.tradeMarketState(for: .home) == nil)
    #expect(runtime.tradeHubFees(for: .coalition).salesTaxRate == nil)
  }

  @Test
  func stockSaleComparisonFollowsTradeLogbookAndPersistsItsList() throws {
    let sections = NavigationSection.allCases
    let logbook = sections.firstIndex(of: .tradeLogbook)
    // Owner decision 29.10.2026: Market stock sits between the logbook and
    // the stock sale comparison.
    #expect(
      logbook != nil
        && sections.firstIndex(of: .marketStock) == logbook.map { $0 + 1 }
        && sections.firstIndex(of: .stockSaleComparison) == logbook.map { $0 + 2 }
    )
    #expect(NavigationSection.establishedCases.contains(.stockSaleComparison))
    #expect(NavigationSection.establishedCases.contains(.marketStock))
    // The default basis has only the default Main Hub; Home and Coalition
    // are not listed until configured.
    #expect(RuntimeState(startBackgroundServices: false).marketStockHubRoles == [.main])

    let schema = Schema(versionedSchema: EVENexusSchemaV2.self)
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration("StockSaleComparison", schema: schema, isStoredInMemoryOnly: true)
      ]
    )
    let context = container.mainContext
    let entries = [
      StockSaleEntry(
        typeID: 34, resolvedName: "Tritanium", pastedName: "Tritanium", quantity: 5,
        materialEfficiency: 10, timeEfficiency: 20
      ),
      StockSaleEntry(
        typeID: nil, resolvedName: nil, pastedName: "Unbekannt", quantity: 1,
        unresolvedReason: .unknownName
      ),
    ]
    try context.upsertAppSetting(
      key: AppSettingKey.stockSaleItems,
      value: String(decoding: try StockSaleEntryList.encode(entries), as: UTF8.self)
    )
    try context.save()
    let stored = try #require(try context.appSettingValue(for: AppSettingKey.stockSaleItems))
    #expect(try StockSaleEntryList.decode(Data(stored.utf8)) == entries)
  }

  @Test
  func tradeLogbookFollowsTradeAndPersistsInItsOwnFile() async throws {
    let sections = NavigationSection.allCases
    let trade = sections.firstIndex(of: .trade)
    #expect(trade != nil && sections.firstIndex(of: .tradeLogbook) == trade.map { $0 + 1 })

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("trade-logbook-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = RuntimeState(dataRoot: root, startBackgroundServices: false)
    await runtime.loadTradeLogbook()
    #expect(runtime.tradeLogbookState == .ready)
    #expect(runtime.tradeLogbookEntries.isEmpty)
    #expect(
      runtime.tradeLogbookURL.path
        == root.appendingPathComponent("trade/trade-logbook.sqlite").path
    )

    let entry = TradeLogbookEntry(
      typeID: 482,
      typeName: "Miner II",
      quantity: 10,
      buyUnitPrice: 500_000,
      buySide: .minSell,
      buyBrokerFeeRate: nil,
      sourceRole: .main,
      sourceLocationName: nil,
      targetRole: .home,
      targetLocationName: nil,
      plannedSellUnitPrice: 690_000,
      transportCostTotal: nil,
      salesTaxRate: nil,
      sellBrokerFeeRate: nil
    )
    #expect(await runtime.saveTradeLogbookEntry(entry))
    #expect(runtime.tradeLogbookEntries.map(\.id) == [entry.id])
    #expect(FileManager.default.fileExists(atPath: runtime.tradeLogbookURL.path))

    var invalid = entry
    invalid.quantity = 0
    #expect(!(await runtime.saveTradeLogbookEntry(invalid)))
    #expect(runtime.tradeLogbookError != nil)
    #expect(runtime.tradeLogbookEntries.first?.quantity == 10)

    await runtime.deleteTradeLogbookEntry(id: entry.id)
    #expect(runtime.tradeLogbookEntries.isEmpty)
  }

  @Test
  func hubScansRecordMarketStockPointsInTheirOwnFile() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("market-stock-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = RuntimeState(dataRoot: root, startBackgroundServices: false)
    #expect(
      runtime.marketStockHistoryURL.path
        == root.appendingPathComponent("market/market-stock-history.sqlite").path
    )
    let start = Date(timeIntervalSince1970: 1_793_253_600)
    func book(_ volume: Int64, at capturedAt: Date, state: DataFreshness = .fresh)
      -> MarketOrderSnapshot
    {
      MarketOrderSnapshot(
        id: UUID(),
        regionID: 10_000_002,
        locationID: 60_003_760,
        capturedAt: capturedAt,
        state: state,
        ordersByType: [
          34: [
            MarketOrder(
              id: 1, typeID: 34, locationID: 60_003_760, systemID: 30_000_142,
              side: .sell, price: 5, volumeRemaining: volume, minimumVolume: 1,
              issued: start)
          ]
        ],
        source: SourceIdentity(provider: "fixture", version: "1", capturedAt: capturedAt)
      )
    }
    await runtime.recordMarketStock(book(100, at: start), role: .main, trigger: .manualScan)
    #expect(runtime.marketStockLatestPointAt[.main] == start)
    #expect(runtime.marketStockError == nil)
    // An incomplete order book writes no point.
    await runtime.recordMarketStock(
      book(1, at: start.addingTimeInterval(3_600), state: .partial),
      role: .main,
      trigger: .automaticScan
    )
    #expect(runtime.marketStockLatestPointAt[.main] == start)
    let later = start.addingTimeInterval(6 * 3_600)
    await runtime.recordMarketStock(book(60, at: later), role: .main, trigger: .scheduled)
    #expect(runtime.marketStockLatestPointAt[.main] == later)

    let store = try await MarketStockHistoryStore.open(url: runtime.marketStockHistoryURL)
    let points = try await store.itemPoints(
      role: .main, locationID: 60_003_760, typeID: 34, now: later)
    #expect(points.map(\.trigger) == [.manualScan, .scheduled])
    #expect(points.last?.sell == MarketStockSideDelta(added: 0, partiallyFilled: 40, vanished: 0))
    await store.close()

    // Without background services no term is planned.
    runtime.scheduleMarketStockTerms()
    #expect(runtime.marketStockNextTermAt == nil)
  }

  @Test
  func characterWalletDataIsKeptInTheTradeLogbook() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("trade-wallet-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = RuntimeState(dataRoot: root, startBackgroundServices: false)
    let source = SourceIdentity(provider: "fixture", version: "1")
    let transaction = ESIWalletTransactionDTO(
      clientID: 1,
      date: Date(timeIntervalSince1970: 1_800_000_000),
      isBuy: true,
      quantity: 3,
      transactionID: 42,
      typeID: 34,
      unitPrice: 5,
      locationID: 60_003_760,
      journalRefID: 7,
      isPersonal: true
    )
    await runtime.recordTradeWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: Sourced(state: .fresh, value: [transaction], source: source),
      journal: Sourced(state: .fresh, value: [], source: source)
    )
    await runtime.recordTradeWallet(
      characterID: 92,
      characterName: "Alt",
      transactions: Sourced(state: .forbidden, value: nil, source: source),
      journal: Sourced(state: .forbidden, value: nil, source: source)
    )

    #expect(runtime.tradeWalletError == nil)
    #expect(runtime.tradeWalletStatuses.map(\.characterName) == ["Alt", "Trader"])
    #expect(runtime.tradeWalletStatuses.first?.transactionsState == .forbidden)
    #expect(runtime.tradeWalletStatuses.last?.storedTransactionCount == 1)

    // A fresh runtime reads the same file and its statuses.
    let reopened = RuntimeState(dataRoot: root, startBackgroundServices: false)
    await reopened.loadTradeLogbook()
    #expect(reopened.tradeWalletStatuses.count == 2)
  }

  @Test
  func reconciliationNeverInventsNamesAndKeepsTheImportStart() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("trade-reconcile-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = RuntimeState(dataRoot: root, startBackgroundServices: false)
    let source = SourceIdentity(provider: "fixture", version: "1")
    let mainLocation = try #require(runtime.tradeLocation(for: .main)?.locationID)
    await runtime.recordTradeWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: Sourced(
        state: .fresh,
        value: [
          ESIWalletTransactionDTO(
            clientID: 1,
            date: .now,
            isBuy: true,
            quantity: 3,
            transactionID: 42,
            typeID: 34,
            unitPrice: 5,
            locationID: mainLocation,
            journalRefID: nil,
            isPersonal: true
          )
        ],
        source: source
      ),
      journal: Sourced(state: .fresh, value: [], source: source)
    )
    await runtime.reconcileTradeLogbook(manufacturingTypeIDs: [])

    // No catalog in this data root: the purchase is counted, not named.
    #expect(runtime.tradeWalletError == nil)
    #expect(runtime.tradeLogbookEntries.isEmpty)
    #expect(runtime.tradeUnresolvedPurchaseCount == 1)
    let start = try #require(runtime.tradeWalletImportStart)
    #expect(start <= .now)

    let earlier = start.addingTimeInterval(-7 * 86_400)
    await runtime.setTradeWalletImportStart(earlier)
    let reopened = RuntimeState(dataRoot: root, startBackgroundServices: false)
    await reopened.loadTradeLogbook()
    #expect(reopened.tradeWalletImportStart == earlier)
  }

  @Test
  func characterSyncFailuresAreGroupedByReasonWithReadableTexts() {
    let keychain = EVEConnectionErrorText.message(for: AuthError.keychain(-25_300))
    let missing = EVEConnectionErrorText.message(for: AuthError.noStoredAuthorization)
    let offline = EVEConnectionErrorText.message(
      for: URLError(.notConnectedToInternet)
    )
    #expect(keychain != missing)
    #expect(offline != keychain)
    let result = CharacterBatchSyncResult(
      synchronizedCount: 1,
      totalCount: 4,
      failedCharacterNames: ["Pilot A", "Pilot B", "Pilot C"],
      failures: [
        CharacterSyncFailure(characterName: "Pilot A", reason: keychain),
        CharacterSyncFailure(characterName: "Pilot B", reason: offline),
        CharacterSyncFailure(characterName: "Pilot C", reason: keychain),
      ]
    )
    let groups = result.failureGroups
    #expect(groups.map(\.reason) == [keychain, offline])
    #expect(groups.map(\.characterNames) == [["Pilot A", "Pilot C"], ["Pilot B"]])
    // Results built without reasons keep working and show no group.
    #expect(
      CharacterBatchSyncResult(
        synchronizedCount: 0,
        totalCount: 1,
        failedCharacterNames: ["Pilot D"]
      ).failureGroups.isEmpty
    )
  }

  @Test
  func dashboardCardWidthsKeepRatiosAndStackOnNarrowWindows() {
    let finance = DashboardCardLayout(weights: [1, 2], minimumWidths: [280, 560])
    let wide = finance.widths(for: 1200)
    #expect(abs(wide[1] - 2 * wide[0]) < 0.01)
    #expect(finance.widths(for: 600) == [600, 600])
    let jobs = DashboardCardLayout(weights: [1, 1, 1], minimumWidths: [340, 340, 340])
    #expect(jobs.widths(for: 900) == [900, 900, 900])
    let three = jobs.widths(for: 1440)
    #expect(three.count == 3)
    #expect(three.allSatisfy { $0 >= 340 })
  }

  @Test
  func sharedAnalysisRefreshJoinsIdenticalRequestsAndSerializesChangedContexts() async {
    let refresh = SharedAnalysisRefresh()
    let gate = AnalysisRefreshTestGate()
    var calls: [String] = []
    let first = Task {
      await refresh.run(identity: "first") {
        calls.append("first")
        await gate.wait()
      }
    }
    while !gate.isWaiting { await Task.yield() }
    let same = Task { await refresh.run(identity: "first") { calls.append("duplicate") } }
    let changed = Task { await refresh.run(identity: "changed") { calls.append("changed") } }
    for _ in 0..<10 { await Task.yield() }
    #expect(calls == ["first"])
    gate.release()
    await first.value
    await same.value
    await changed.value
    #expect(calls == ["first", "changed"])
  }

  @Test
  func startupLoadRunsAnalysesAndScansOnlyAfterCharactersAndConfiguration() async {
    let load = StartupDataLoad()
    let characterGate = AnalysisRefreshTestGate()
    var calls: [String] = []
    let steps = StartupDataLoad.Steps(
      prepareConfiguration: { calls.append("configuration") },
      synchronizeCharacters: {
        calls.append("characters")
        await characterGate.wait()
        calls.append("characters-done")
        return CharacterBatchSyncResult(
          synchronizedCount: 2,
          totalCount: 3,
          failedCharacterNames: ["Pilot C"]
        )
      },
      refreshMarketAnalyses: { calls.append("analyses") },
      releaseAutomaticScans: { calls.append("scans") }
    )
    let run = Task { await load.run(steps) }
    while !characterGate.isWaiting { await Task.yield() }
    for _ in 0..<10 { await Task.yield() }
    #expect(load.phase == .loadingCharactersAndConfiguration)
    #expect(!calls.contains("analyses"))
    #expect(!calls.contains("scans"))
    characterGate.release()
    await run.value
    #expect(load.phase == .completed)
    let charactersDone = calls.firstIndex(of: "characters-done") ?? .max
    let configuration = calls.firstIndex(of: "configuration") ?? .max
    #expect((calls.firstIndex(of: "analyses") ?? -1) > charactersDone)
    #expect((calls.firstIndex(of: "scans") ?? -1) > charactersDone)
    #expect((calls.firstIndex(of: "analyses") ?? -1) > configuration)
    #expect(load.characterResult?.failedCharacterNames == ["Pilot C"])
  }

  @Test
  func startupLoadRunsOnceAndLateCallersJoinTheSameCharacterResult() async {
    let load = StartupDataLoad()
    var characterRuns = 0
    let steps = StartupDataLoad.Steps(
      prepareConfiguration: {},
      synchronizeCharacters: {
        characterRuns += 1
        return CharacterBatchSyncResult(
          synchronizedCount: 1,
          totalCount: 1,
          failedCharacterNames: []
        )
      },
      refreshMarketAnalyses: {},
      releaseAutomaticScans: {}
    )
    #expect(load.start(steps))
    #expect(!load.start(steps))
    await load.run(steps)
    let joined = await load.characterSynchronizationResult()
    #expect(characterRuns == 1)
    #expect(joined?.synchronizedCount == 1)
  }

  @Test
  func earlyDashboardReaderWaitsForTheExpectedStartupLoad() async {
    let load = StartupDataLoad(expectsStart: true)
    let reader = Task { await load.characterSynchronizationResult() }
    for _ in 0..<10 { await Task.yield() }
    load.start(
      StartupDataLoad.Steps(
        prepareConfiguration: {},
        synchronizeCharacters: {
          CharacterBatchSyncResult(
            synchronizedCount: 4,
            totalCount: 4,
            failedCharacterNames: []
          )
        },
        refreshMarketAnalyses: {},
        releaseAutomaticScans: {}
      )
    )
    #expect(await reader.value?.synchronizedCount == 4)
    #expect(await StartupDataLoad().characterSynchronizationResult() == nil)
  }

  @Test
  func cancelledStartupLoadDoesNotStartAnalysesOrScans() async {
    let load = StartupDataLoad()
    let characterGate = AnalysisRefreshTestGate()
    var calls: [String] = []
    let run = Task {
      await load.run(
        StartupDataLoad.Steps(
          prepareConfiguration: {},
          synchronizeCharacters: {
            await characterGate.wait()
            calls.append(Task.isCancelled ? "characters-cancelled" : "characters")
            return CharacterBatchSyncResult(
              synchronizedCount: 0,
              totalCount: 1,
              failedCharacterNames: []
            )
          },
          refreshMarketAnalyses: { calls.append("analyses") },
          releaseAutomaticScans: { calls.append("scans") }
        )
      )
    }
    while !characterGate.isWaiting { await Task.yield() }
    load.cancel()
    characterGate.release()
    await run.value
    #expect(load.phase == .cancelled)
    #expect(calls == ["characters-cancelled"])
  }

  @Test
  func automaticScansStayDisabledWithoutBackgroundServices() async {
    let runtime = RuntimeState(startBackgroundServices: false)
    #expect(!runtime.mainHubMarketAutomaticUpdatesEnabled)
    await runtime.releaseStartupAutomaticScans()
    #expect(!runtime.areStartupAutomaticScansReleased)
    #expect(await runtime.startupDataLoad.characterSynchronizationResult() == nil)
  }

  @Test
  func mainHubOpportunityFilesKeepTheirHistoricalPaths() {
    let root = URL(fileURLWithPath: "/tmp/eve-nexus-role-paths", isDirectory: true)
    #expect(
      RuntimeState.opportunityDemandFileURL(dataRoot: root, role: .main).path
        == "/tmp/eve-nexus-role-paths/market/main-hub-demand.json"
    )
    #expect(
      RuntimeState.opportunitySnapshotFileURL(dataRoot: root, role: .main).path
        == "/tmp/eve-nexus-role-paths/market/main-hub-opportunities.json"
    )
    #expect(
      RuntimeState.opportunitySnapshotFileURL(dataRoot: root, role: .coalition)
        .lastPathComponent == "coalition-hub-opportunities.json"
    )
  }

  @Test
  func startupStatusCombinesSourceStatesWithoutInventingFreshData() {
    typealias P = StartupDataStatusProjector
    #expect(P.combined([]) == nil)
    #expect(P.combined([.fresh, .fresh]) == .fresh)
    #expect(P.combined([.fresh, .stale]) == .stale)
    #expect(P.combined([.stale, .partial]) == .partial)
    #expect(P.combined([.fresh, .unavailable]) == .partial)
    #expect(P.combined([.forbidden, .forbidden]) == .forbidden)
    #expect(P.combined([.forbidden, .unavailable]) == .unavailable)
  }

  @Test
  func startupStatusFollowsTheLoadPhaseForCharactersAndWarehouse() {
    typealias P = StartupDataStatusProjector
    let synced = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(
      P.characters(
        phase: .loadingCharactersAndConfiguration,
        result: nil,
        lastSyncDates: [synced]
      ).status == .running
    )
    let partial = P.characters(
      phase: .completed,
      result: CharacterBatchSyncResult(
        synchronizedCount: 1,
        totalCount: 2,
        failedCharacterNames: ["Pilot B"]
      ),
      lastSyncDates: [synced, nil]
    )
    #expect(partial.status == .known(.partial))
    #expect(partial.timestamp == synced)
    #expect(
      P.characters(phase: .idle, result: nil, lastSyncDates: []).status
        == .known(.unavailable)
    )

    let observation = P.SourceObservation(freshness: .fresh, capturedAt: synced)
    // One character with assets and blueprints is complete.
    #expect(
      P.warehouseAndBlueprints(
        phase: .completed,
        characterCount: 1,
        observations: [observation, observation]
      ).status == .known(.fresh)
    )
    // A missing blueprint observation is not reported as fresh.
    #expect(
      P.warehouseAndBlueprints(
        phase: .completed,
        characterCount: 1,
        observations: [observation]
      ).status == .known(.partial)
    )
    #expect(
      P.warehouseAndBlueprints(
        phase: .completed,
        characterCount: 2,
        observations: []
      ).status == .waiting
    )
  }

  @Test
  func startupStatusKeepsAnalysisErrorsAndWaitingStatesVisible() {
    typealias P = StartupDataStatusProjector
    func status(
      phase: StartupDataLoad.Phase = .completed,
      refreshing: Bool = false,
      states: [DataFreshness]? = nil,
      error: Bool = false
    ) -> StartupDataStatus {
      P.analysis(
        area: .minerals,
        phase: phase,
        isRefreshing: refreshing,
        marketStates: states,
        hasError: error,
        timestamp: nil
      ).status
    }
    #expect(status(refreshing: true, states: [.fresh]) == .running)
    #expect(status(phase: .loadingCharactersAndConfiguration) == .waiting)
    #expect(status() == .known(.unavailable))
    #expect(status(error: true) == .known(.unavailable))
    #expect(status(states: [.fresh, .forbidden]) == .known(.partial))
    // A failed refresh keeps the last snapshot, but no longer as fresh.
    #expect(status(states: [.fresh], error: true) == .known(.stale))
    #expect(
      StartupDataStatusSection.detail(
        for: StartupDataStatusRow(area: .minerals, status: .waiting, timestamp: nil)
      ) == AppLocalization.text("Waiting")
    )
  }

  @Test
  func startupLoadPublishesPhaseChangesForTheDashboard() async {
    let load = StartupDataLoad()
    var publications = 0
    let subscription = load.objectWillChange.sink { publications += 1 }
    await load.run(
      StartupDataLoad.Steps(
        prepareConfiguration: {},
        synchronizeCharacters: {
          CharacterBatchSyncResult(
            synchronizedCount: 0,
            totalCount: 0,
            failedCharacterNames: []
          )
        },
        refreshMarketAnalyses: {},
        releaseAutomaticScans: {}
      )
    )
    subscription.cancel()
    #expect(load.phase == .completed)
    #expect(publications >= 3)
  }

  @Test
  func homeHubScanTargetSkipsMainHubAndRequiresExactIdentifiers() {
    typealias Target = HomeHubOpportunityScanTarget
    let structure = ProcurementLocation(
      id: "structure:1035000000001",
      name: "Home Keepstar",
      locationID: 1_035_000_000_001,
      kind: .playerStructure,
      solarSystemID: 30_004_000,
      regionID: 10_000_060
    )
    let amarr = ProcurementLocation(
      id: "npc:60008494",
      name: "Amarr VIII (Oris) - Emperor Family Academy",
      locationID: 60_008_494,
      kind: .npcTradeHub,
      solarSystemID: 30_002_187,
      regionID: 10_000_043
    )
    #expect(Target.resolve(mainHub: .jita, homeHub: nil) == .notConfigured)
    #expect(Target.resolve(mainHub: .jita, homeHub: .jita) == .sharesMainHub)
    #expect(
      Target.resolve(mainHub: .jita, homeHub: amarr)
        == .npcStation(regionID: 10_000_043, locationID: 60_008_494)
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: structure)
        == .playerStructure(
          structureID: 1_035_000_000_001,
          systemID: 30_004_000,
          regionID: 10_000_060
        )
    )
    // Without a Main Hub the Home Hub still resolves on its own.
    #expect(
      Target.resolve(mainHub: nil, homeHub: amarr)
        == .npcStation(regionID: 10_000_043, locationID: 60_008_494)
    )
    let structureWithoutSystem = ProcurementLocation(
      id: "structure:1035000000002",
      name: "Unresolved Structure",
      locationID: 1_035_000_000_002,
      kind: .playerStructure
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: structureWithoutSystem)
        == .unresolved
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: .legacy(name: "Old Home"))
        == .unresolved
    )
  }

  @Test
  func coalitionScanTargetSkipsMainAndHomeHubs() {
    let home = ProcurementLocation(
      id: "structure:1035000000001",
      name: "Home Keepstar",
      locationID: 1_035_000_000_001,
      kind: .playerStructure,
      solarSystemID: 30_004_000,
      regionID: 10_000_060
    )
    let coalition = ProcurementLocation(
      id: "structure:1035000000009",
      name: "Coalition Keepstar",
      locationID: 1_035_000_000_009,
      kind: .playerStructure,
      solarSystemID: 30_004_100,
      regionID: nil
    )
    typealias Target = HubOpportunityScanTarget
    #expect(
      Target.resolve(mainHub: .jita, homeHub: home, coalitionHub: nil)
        == .notConfigured
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: home, coalitionHub: .jita)
        == .sharesMainHub
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: home, coalitionHub: home)
        == .sharesHomeHub
    )
    #expect(
      Target.resolve(mainHub: .jita, homeHub: home, coalitionHub: coalition)
        == .playerStructure(
          structureID: 1_035_000_000_009,
          systemID: 30_004_100,
          regionID: nil
        )
    )
    #expect(Target.sharesHomeHub.requiresScan == false)
    #expect(Target.npcStation(regionID: 1, locationID: 2).requiresScan)
    let runtime = RuntimeState(startBackgroundServices: false)
    #expect(runtime.opportunityScanTarget(for: .coalition) == .notConfigured)
    #expect(runtime.opportunityState(for: .coalition).analysis == nil)
  }

  @Test
  func homeHubStateStartsEmptyWithoutBackgroundServices() {
    let runtime = RuntimeState(startBackgroundServices: false)
    #expect(runtime.homeHubOpportunityAnalysis == nil)
    #expect(runtime.homeHubMarketState == nil)
    #expect(runtime.homeHubOpportunityError == nil)
    #expect(!runtime.isAnalyzingHomeHubOpportunities)
    // A fresh profile has no Home Hub, so no Home-Hub scan is planned.
    #expect(runtime.productionBasis.homeTradingLocation == nil)
    #expect(runtime.homeHubOpportunityScanTarget == .notConfigured)
  }

  @Test
  func homeHubOpportunityTextsNameTheSaleHubOnly() {
    #expect(
      OpportunityHubText.adapt("Market Opportunities · Main Hub", for: .home)
        == "Market Opportunities · Home Hub"
    )
    #expect(
      OpportunityHubText.adapt("Noch kein Main-Hub-Scan", for: .home)
        == "Noch kein Home-Hub-Scan"
    )
    #expect(
      OpportunityHubText.adapt("Market Opportunities · Main Hub", for: .main)
        == "Market Opportunities · Main Hub"
    )
    #expect(
      OpportunityHubText.saleWarningCodes.contains(
        "manufacturing-opportunity.product-sell-order-unavailable"
      )
    )
    // Material-depth warnings describe Main-Hub purchases and stay unchanged.
    #expect(
      !OpportunityHubText.saleWarningCodes.contains(
        "manufacturing-opportunity.blueprint-cost-scope"
      )
    )
  }

  @Test
  func homeHubOpportunitiesFollowMainHubInNavigationAndCarryTheTargetMarket() {
    let sections = NavigationSection.allCases
    let main = sections.firstIndex(of: .manufacturingOpportunities)
    let home = sections.firstIndex(of: .homeHubOpportunities)
    #expect(main != nil && home == main.map { $0 + 1 })
    #expect(NavigationSection.establishedCases.contains(.homeHubOpportunities))

    let homeRequest = MainHubOpportunityPlannerHandoff.request(
      productTypeID: 100,
      productName: "Fixture Product",
      requestedRuns: 2,
      wantedQuantity: 2,
      materialEfficiency: 10,
      timeEfficiency: 20,
      targetMarket: .home
    )
    #expect(homeRequest.targetMarket == .home)
    #expect(homeRequest.inputLine.contains("Fixture Product"))
    let legacyRequest = MainHubOpportunityPlannerHandoff.request(
      productTypeID: 100,
      productName: "Fixture Product",
      requestedRuns: 2,
      wantedQuantity: 2,
      materialEfficiency: 10,
      timeEfficiency: 20
    )
    #expect(legacyRequest.targetMarket == nil)
  }

  @Test
  func coalitionHubOpportunitiesFollowHomeHubAndAdaptTheirTexts() {
    let sections = NavigationSection.allCases
    let home = sections.firstIndex(of: .homeHubOpportunities)
    let coalition = sections.firstIndex(of: .coalitionHubOpportunities)
    #expect(home != nil && coalition == home.map { $0 + 1 })
    #expect(
      OpportunityHubText.adapt("Marktchancen · Main Hub", for: .coalition)
        == "Marktchancen · Coalition Hub"
    )
    #expect(
      OpportunityHubText.adapt("Noch kein Main-Hub-Scan", for: .coalition)
        == "Noch kein Coalition-Hub-Scan"
    )
    #expect(
      OpportunityHubRole.coalition.storageKey("market-opportunities.filter.group")
        == "market-opportunities.coalition.filter.group"
    )
  }

  @Test
  func productionOverviewTargetMarketHasRankAndExplicitUnchosenText() {
    typealias Presentation = ProductionOverviewTargetMarketPresentation
    #expect(Presentation.rank(.mainHub) == 0)
    #expect(Presentation.rank(.homeHub) == 1)
    #expect(Presentation.rank(.coalitionHub) == 2)
    #expect(Presentation.rank(nil) == nil)
    #expect(Presentation.text(.homeHub) == "Home Hub")
    #expect(Presentation.text(nil) == AppLocalization.text("Not chosen"))
    #expect(AppSettingKey.plannerTargetMarketDraft == "planner.target-market.draft.v1")
  }

  @Test
  func allianceInputParserKeepsEmptyFieldsUnsetAndRejectsInvalidValues() {
    let german = Locale(identifier: "de_DE")
    let parsed = PlannerAllianceInputParser.input(
      unitPrice: "1.250.000,5",
      acceptedQuantity: "12",
      feePercent: "2,5",
      deliveryHub: .homeHub,
      locale: german
    )
    #expect(parsed?.unitPrice == 1_250_000.5)
    #expect(parsed?.acceptedQuantity == 12)
    #expect(parsed?.feeRate == 0.025)
    #expect(parsed?.deliveryHub == .homeHub)
    let empty = PlannerAllianceInputParser.input(
      unitPrice: "",
      acceptedQuantity: " ",
      feePercent: "",
      deliveryHub: nil,
      locale: german
    )
    #expect(empty == PlannerAllianceSaleInput())
    #expect(
      PlannerAllianceInputParser.input(
        unitPrice: "abc", acceptedQuantity: "", feePercent: "",
        deliveryHub: nil, locale: german
      ) == nil
    )
    #expect(
      PlannerAllianceInputParser.input(
        unitPrice: "10", acceptedQuantity: "1,5", feePercent: "",
        deliveryHub: nil, locale: german
      ) == nil
    )
    #expect(
      PlannerAllianceInputParser.input(
        unitPrice: "10", acceptedQuantity: "", feePercent: "100",
        deliveryHub: nil, locale: german
      ) == nil
    )
    #expect(ProductionOverviewTargetMarketPresentation.rank(.allianceMarket) == 3)
    // The complete output stays unset so a recalculated plan is sold in full.
    #expect(
      PlannerAllianceInputParser.input(
        unitPrice: "10", acceptedQuantity: "1.000", feePercent: "",
        deliveryHub: nil, producedQuantity: 1_000, locale: german
      )?.acceptedQuantity == nil
    )
    #expect(
      PlannerAllianceInputParser.input(
        unitPrice: "10", acceptedQuantity: "999", feePercent: "",
        deliveryHub: nil, producedQuantity: 1_000, locale: german
      )?.acceptedQuantity == 999
    )
  }

  @Test
  func allianceEditingTextGroupsThousandsAndKeepsTheDecimalSeparator() {
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")
    typealias Parser = PlannerAllianceInputParser
    #expect(Parser.groupedEditingText("6600000000", locale: german) == "6.600.000.000")
    #expect(Parser.groupedEditingText("6.600.0000", locale: german) == "66.000.000")
    #expect(Parser.groupedEditingText("1250000,", locale: german) == "1.250.000,")
    #expect(Parser.groupedEditingText("1250000,55", locale: german) == "1.250.000,55")
    #expect(Parser.groupedEditingText(",5", locale: german) == "0,5")
    #expect(Parser.groupedEditingText("1,2,3", locale: german) == "1,23")
    #expect(Parser.groupedEditingText("12a34", locale: german) == "1.234")
    #expect(Parser.groupedEditingText("", locale: german) == "")
    #expect(Parser.groupedEditingText("1234567.8", locale: english) == "1,234,567.8")
    #expect(
      Parser.groupedEditingText("1234,5", locale: german, allowsFraction: false)
        == "1.234"
    )
    #expect(
      Parser.number("6.600.000.000,25", locale: german) == .value(6_600_000_000.25)
    )
  }

  @Test
  func groupedNumberInputKeepsTypedFractionsAndFeedsPlainParsers() throws {
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")
    #expect(GroupedNumberText.editingText("100000000", locale: german) == "100.000.000")
    // Trailing fraction zeros stay while typing.
    #expect(GroupedNumberText.editingText("12,0", locale: german) == "12,0")
    #expect(GroupedNumberText.editingText("769,10", locale: german) == "769,10")

    #expect(GroupedNumberText.ungrouped("100.000.000", locale: german) == "100000000")
    #expect(Int64(GroupedNumberText.ungrouped("800.000", locale: german)) == 800_000)
    #expect(GroupedNumberText.ungrouped("1,234,567.8", locale: english) == "1234567.8")
    #expect(
      try ISKAmount.parse(GroupedNumberText.ungrouped("65.590.000,5", locale: german))
        .hundredths == 6_559_000_050
    )
  }

  @Test
  func purchaseLocationHintsSortTypedValuesWithUnknownLast() {
    func hint(_ typeID: Int64, _ name: String, price: Double?) -> MaterialPurchaseLocationHint {
      MaterialPurchaseLocationHint(
        item: EVEShoppingListItem(typeID: typeID, name: name, quantity: 1, marketQuote: nil),
        location: price == nil ? nil : .jita,
        unitPrice: price,
        mainHubUnitPrice: nil
      )
    }
    let hints = [hint(3, "C", price: nil), hint(2, "B", price: 9), hint(1, "A", price: 4)]
    let ascending = PurchaseLocationHintSorting.sorted(
      hints,
      by: AppTableSortDescriptor(column: .unitPrice, direction: .ascending)
    )
    #expect(ascending.map(\.item.name) == ["A", "B", "C"])
    let descending = PurchaseLocationHintSorting.sorted(
      hints,
      by: AppTableSortDescriptor(column: .unitPrice, direction: .descending)
    )
    #expect(descending.map(\.item.name) == ["C", "B", "A"])
    let byName = PurchaseLocationHintSorting.sorted(
      hints,
      by: AppTableSortDescriptor(column: .material, direction: .ascending)
    )
    #expect(byName.map(\.item.name) == ["A", "B", "C"])
  }

  @Test
  func marketConfigurationIdentityIsStableAndChangesWithTheProfile() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let original = runtime.marketAnalysisContextIdentity
    for _ in 0..<20 { #expect(runtime.marketAnalysisContextIdentity == original) }
    runtime.productionBasis.cloneState = runtime.productionBasis.cloneState == .alpha ? .omega : .alpha
    #expect(runtime.marketAnalysisContextIdentity != original)
  }

  @Test
  func dashboardComponentsRenderWithEmptyShortAndLongLists() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("eve-dashboard-20261017/visual-checks")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for width: CGFloat in [600, 1000, 1440] {
      var shortHeight: CGFloat = 0
      for count in [0, 5, 50] {
        let controller = NSHostingController(rootView:
          DashboardRenderingFixture(count: count)
            .environment(\.locale, Locale(identifier: "de"))
            .frame(width: width))
        let size = controller.sizeThatFits(in: CGSize(width: width, height: 8000))
        #expect(size.width <= width + 1)
        #expect(size.height.isFinite && size.height > 280 && size.height < 4000)
        if count == 5 { shortHeight = size.height }
        // At narrow widths all three cards add their own disclosure control.
        if count == 50 { #expect(size.height <= shortHeight + 96) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        let view = controller.view
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("dashboard-\(Int(width))-\(count).png"))
        window.close()
      }
    }
  }

  @Test
  func initialWindowMaximizationUsesVisibleScreenAreaOnlyOnce() {
    let initialFrame = NSRect(x: 40, y: 50, width: 600, height: 420)
    let visibleFrame = NSRect(x: 0, y: 25, width: 1_440, height: 875)
    let manuallyResizedFrame = NSRect(x: 80, y: 90, width: 900, height: 640)
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    var maximization = InitialWindowMaximization()

    maximization.apply(to: window, visibleFrame: visibleFrame)
    #expect(window.frame == visibleFrame)
    #expect(maximization.hasApplied)

    window.setFrame(manuallyResizedFrame, display: false)
    maximization.apply(to: window, visibleFrame: visibleFrame)
    #expect(window.frame == manuallyResizedFrame)
  }

  @Test
  func sidebarStatusMinimumMeasurementDoesNotInflateWindowHeight() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let controller = NSHostingController(
      rootView: PublicContractSidebarStatus(runtime: runtime)
        .environment(\.locale, Locale(identifier: "de"))
    )
    // NavigationSplitView probes zero width when deriving its minimum size.
    // The multiline footer must remain as short as at the narrowest sidebar.
    let minimum = controller.sizeThatFits(in: .zero)
    let narrow = controller.sizeThatFits(
      in: CGSize(width: DesignTokens.sidebarMinimum, height: 480)
    )
    #expect(minimum.height <= narrow.height + 1)
    #expect(minimum.height < 240)
  }

  @Test
  func settingsNavigationKeepsItsIntrinsicHeight() {
    let controller = NSHostingController(
      rootView: DataSettingsNavigationBar(selection: .constant(.esi))
        .environment(\.locale, Locale(identifier: "de"))
    )
    for width: CGFloat in [420, 900, 2300] {
      let short = controller.sizeThatFits(in: CGSize(width: width, height: 80))
      let tall = controller.sizeThatFits(in: CGSize(width: width, height: 1300))
      #expect(abs(short.height - tall.height) <= 1)
      #expect(tall.height <= 80)
    }
  }

  @Test
  func settingsNavigationWidthDoesNotFollowOversizedPageContent() {
    for windowSize in [
      NSSize(width: 900, height: 540),
      NSSize(width: 2_555, height: 1_300),
    ] {
      var navigationFrames: [NSRect] = []

      for pageWidth: CGFloat in [320, 4_000] {
        let marker = NSView()
        let controller = NSHostingController(
          rootView: NavigationSplitView {
            Text("Navigation").navigationSplitViewColumnWidth(220)
          } detail: {
            SettingsWorkspaceLayout {
              DataSettingsNavigationBar(selection: .constant(.esi))
                .background(SettingsNavigationFrameProbe(view: marker))
            } content: {
              ScrollView {
                Color.clear
                  .frame(width: pageWidth, height: 1_000)
              }
            }
          }
          .toolbar { Button("Settings action") {} }
          .environment(\.locale, Locale(identifier: "de"))
        )
        let window = NSWindow(
          contentRect: NSRect(origin: .zero, size: windowSize),
          styleMask: [.titled, .resizable, .fullSizeContentView],
          backing: .buffered,
          defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.toolbarStyle = .unified
        window.setContentSize(windowSize)
        defer { window.close() }

        controller.view.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        controller.view.layoutSubtreeIfNeeded()

        let navigationFrame = marker.convert(marker.bounds, to: nil)
        navigationFrames.append(navigationFrame)
        #expect(marker.window === window)
        #expect(navigationFrame.minX >= 219)
        #expect(navigationFrame.maxX <= window.contentLayoutRect.maxX + 1)
      }

      #expect(navigationFrames.count == 2)
      #expect(abs(navigationFrames[0].minX - navigationFrames[1].minX) <= 1)
      #expect(abs(navigationFrames[0].width - navigationFrames[1].width) <= 1)
    }
  }

  @Test
  func settingsNavigationStaysBelowNativeToolbar() {
    let marker = NSView()
    let controller = NSHostingController(
      rootView: NavigationSplitView {
        Text("Navigation").navigationSplitViewColumnWidth(220)
      } detail: {
        VStack(spacing: 0) {
          EVEOnlineServiceBanner()
          SettingsWorkspaceLayout {
            DataSettingsNavigationBar(selection: .constant(.esi))
              .background(SettingsNavigationFrameProbe(view: marker))
          } content: {
            ScrollView {
              Text("Synthetic settings content").frame(minHeight: 1000)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("ESI")
          }.background(DesignTokens.canvas)
        }
      }
      .environment(RuntimeState(startBackgroundServices: false))
      .toolbar { Button("Settings action") {} }
      .environment(\.locale, Locale(identifier: "de"))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
      styleMask: [.titled, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.toolbarStyle = .unified
    defer { window.close() }
    for size in [NSSize(width: 2555, height: 1300), NSSize(width: 900, height: 540)] {
      window.setContentSize(size)
      controller.view.layoutSubtreeIfNeeded()
      drainMainRunLoop()
      controller.view.layoutSubtreeIfNeeded()
      let header = marker.convert(marker.bounds, to: nil)
      print("HEADER frame=\(header) layout=\(window.contentLayoutRect) window=\(window.frame)")
      #expect(marker.window === window)
      #expect(header.height >= 24)
      #expect(header.maxY <= window.contentLayoutRect.maxY + 1)
    }
  }

  @Test
  func primaryNavigationKeepsPlannerAndIntegratesSupportingTools() {
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains("marketBrowser")
    )
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains(
        "recursiveProductionCalculation"
      )
    )
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains("industryJobs")
    )
    #expect(!NavigationSection.allCases.map(\.rawValue).contains("wallet"))
    #expect(NavigationSection.establishedCases.contains(.planner))
    #expect(NavigationSection.allCases.contains(.planner))
    #expect(
      NavigationSection.establishedCases.contains(.mineralPurchaseAnalysis)
    )
    #expect(DataSettingsSection.allCases.contains(.logistics))
    #expect(DataSettingsSection.allCases.contains(.general))
    #expect(DataSettingsSection.allCases.contains(.marketSettings))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Preisprofile"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Sicherung"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Projekte"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Reservierungen"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Einkauf"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Manuelle Lager"))
    #expect(ConsolidationArea.allCases == [.science, .sales])
  }

  @Test
  func mineralPurchaseAnalysisKeepsIndependentRuntimeAndExportIdentity() {
    let runtime = RuntimeState(startBackgroundServices: false)

    #expect(runtime.moonMaterialAnalysis == nil)
    #expect(runtime.mineralPurchaseAnalysis == nil)
    #expect(!runtime.isRefreshingMoonMaterialAnalysis)
    #expect(!runtime.isRefreshingMineralPurchaseAnalysis)

    let fileName = MaterialPurchaseImageExportNaming.fileName(
      kind: .minerals,
      at: Date(timeIntervalSince1970: 0)
    )
    #expect(fileName.hasPrefix("Mineralien-Kaufanalyse_"))
    #expect(fileName.hasSuffix(".png"))
  }

  @Test
  func unrelatedRuntimeChangesDoNotInvalidatePlannerFeature() {
    let runtime = RuntimeState(startBackgroundServices: false)

    runtime.statusMessage = "Public contracts are synchronizing"
    runtime.activeSDEBuild = 123
    runtime.installationPhase = "Preparing"
    runtime.cancelPublicContractSynchronization()

    #expect(runtime.plannerFeatureState.revision == 0)
  }

  @Test
  func plannerStateChangesInvalidateOnlyItsFeatureChannel() {
    let runtime = RuntimeState(startBackgroundServices: false)

    runtime.warehouseStockEnabled.toggle()
    #expect(runtime.plannerFeatureState.revision == 1)

    runtime.productionBasis = ProductionBasis()
    #expect(runtime.plannerFeatureState.revision == 2)

    runtime.plan = nil
    #expect(runtime.plannerFeatureState.revision == 3)
  }

  @Test
  func runtimeObservationFollowsOnlyTheReadProperties() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let flag = ObservationFlag()
    withObservationTracking {
      _ = runtime.manufacturingOpportunityAnalysis
      _ = runtime.isWorking
    } onChange: {
      flag.fire()
    }

    runtime.statusMessage = "Public contracts are synchronizing"
    runtime.activeSDEBuild = 123
    runtime.cancelPublicContractSynchronization()
    #expect(flag.count == 0)

    runtime.isWorking = true
    #expect(flag.count == 1)
  }

  @Test
  func marketAnalysisIdentityIsCachedButFollowsBasisChanges() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let initial = runtime.marketAnalysisContextIdentity
    #expect(runtime.marketAnalysisContextIdentity == initial)

    let flag = ObservationFlag()
    withObservationTracking {
      _ = runtime.marketAnalysisContextIdentity
    } onChange: {
      flag.fire()
    }
    runtime.productionBasis.name = "Changed basis"

    #expect(flag.count == 1)
    #expect(runtime.marketAnalysisContextIdentity != initial)
    let changed = runtime.marketAnalysisContextIdentity
    runtime.activeSDEBuild = 456
    #expect(runtime.marketAnalysisContextIdentity != changed)
  }

  @Test
  func wealthHistoryCacheDecodesOncePerStoredValue() throws {
    func snapshot(day: Int) -> DashboardWealthSnapshot {
      DashboardWealthSnapshot(
        capturedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
        valuationPolicy: "fixture",
        characters: [],
        knownTotalValue: Double(day),
        isComplete: true,
        freshness: .fresh,
        priceSource: SourceIdentity(provider: "Fixture", version: "1")
      )
    }
    func encoded(_ values: [DashboardWealthSnapshot]) throws -> String {
      try JSONEncoder().encode(values).base64EncodedString()
    }
    let cache = DashboardWealthHistoryCache()
    let first = try encoded([snapshot(day: 2), snapshot(day: 1)])

    #expect(cache.history(encoded: first).map(\.knownTotalValue) == [1, 2])
    #expect(cache.history(encoded: first).map(\.knownTotalValue) == [1, 2])
    let second = try encoded([snapshot(day: 3)])
    #expect(cache.history(encoded: second).map(\.knownTotalValue) == [3])
    #expect(cache.history(encoded: nil).isEmpty)
    #expect(cache.history(encoded: "not base64").isEmpty)
  }

  @Test
  func dashboardStartupRefreshCanBeReservedOnlyOncePerAppRuntime() {
    let runtime = RuntimeState(startBackgroundServices: false)

    #expect(runtime.reserveDashboardStartupRefresh())
    #expect(!runtime.reserveDashboardStartupRefresh())
  }

  @Test
  func netWorthHistoryUsesCalendarDistanceAndChangeFocusedScaling() {
    let first = Date(timeIntervalSince1970: 0)
    let secondDay = first.addingTimeInterval(24 * 60 * 60)
    let tenthDay = first.addingTimeInterval(9 * 24 * 60 * 60)

    #expect(
      abs(
        NetWorthHistoryGeometry.xFraction(
          date: secondDay,
          first: first,
          last: tenthDay
        ) - (1.0 / 9.0)
      ) < 0.000_001
    )
    let domain = NetWorthHistoryGeometry.valueDomain(
      values: [1_000_000_000, 1_010_000_000]
    )
    #expect(domain.lowerBound > 900_000_000)
    #expect(domain.upperBound > 1_010_000_000)
  }

  @Test
  func hostedPlannerSubscriberIgnoresUnrelatedRuntimePublication() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let counter = RenderCounter()
    let hostingView = NSHostingView(
      rootView: PlannerObservationProbe(runtime: runtime, counter: counter)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
    hostingView.layoutSubtreeIfNeeded()
    drainMainRunLoop()
    let initialRenderCount = counter.value

    runtime.statusMessage = "Public Contracts progress"
    drainMainRunLoop()
    hostingView.layoutSubtreeIfNeeded()
    #expect(counter.value == initialRenderCount)

    runtime.warehouseStockEnabled.toggle()
    drainMainRunLoop()
    hostingView.layoutSubtreeIfNeeded()
    #expect(counter.value > initialRenderCount)
  }

  @Test
  func plannerInterruptsBothAutomaticScansUntilItFinishes() {
    var coordinator = InteractivePlannerWorkCoordinator()

    let startedMainHub = coordinator.beginAutomaticWork(.mainHubMarket)
    let startedContracts = coordinator.beginAutomaticWork(.publicContracts)
    #expect(startedMainHub)
    #expect(startedContracts)

    let interrupted = coordinator.beginPlannerCalculation(id: 1)
    #expect(interrupted == [.mainHubMarket, .publicContracts])
    #expect(!coordinator.canSchedule(.mainHubMarket))
    #expect(!coordinator.canSchedule(.publicContracts))

    let mainHubFinishedWhilePlanning =
      coordinator.finishAutomaticWork(.mainHubMarket)
    let contractsFinishedWhilePlanning =
      coordinator.finishAutomaticWork(.publicContracts)
    let lastPlannerFinished = coordinator.finishPlannerCalculation(id: 1)
    #expect(!mainHubFinishedWhilePlanning)
    #expect(!contractsFinishedWhilePlanning)
    #expect(lastPlannerFinished)
    #expect(coordinator.canSchedule(.mainHubMarket))
    #expect(coordinator.canSchedule(.publicContracts))
  }

  @Test
  func overlappingPlannerCalculationsResumeAutomationOnlyAfterTheLastOne() {
    var coordinator = InteractivePlannerWorkCoordinator()

    _ = coordinator.beginPlannerCalculation(id: 1)
    _ = coordinator.beginPlannerCalculation(id: 2)

    let firstPlannerFinished = coordinator.finishPlannerCalculation(id: 1)
    #expect(!firstPlannerFinished)
    #expect(!coordinator.canSchedule(.mainHubMarket))
    #expect(!coordinator.canSchedule(.publicContracts))

    let secondPlannerFinished = coordinator.finishPlannerCalculation(id: 2)
    #expect(secondPlannerFinished)
    #expect(coordinator.canSchedule(.mainHubMarket))
    #expect(coordinator.canSchedule(.publicContracts))
  }

  @Test
  func publicContractBackgroundPresentationKeepsLongImportControllable() {
    let incomplete = PublicContractSyncProgress(
      phase: .idle,
      regionCount: 100,
      completedRegions: 75,
      remainingInitialRegions: 25,
      indexedContracts: 1_000,
      pendingItemContracts: 250
    )
    let waiting = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: incomplete,
      isSynchronizing: false,
      isCancelling: false,
      automaticUpdatesEnabled: false
    )
    #expect(waiting.phase == .incomplete)
    #expect(waiting.progressFraction == nil)

    let running = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: PublicContractSyncProgress(
        phase: .loadingItems,
        regionCount: 100,
        completedRegions: 100,
        indexedContracts: 1_000,
        pendingItemContracts: 250
      ),
      isSynchronizing: true,
      isCancelling: false,
      automaticUpdatesEnabled: true
    )
    #expect(running.phase == .synchronizing)
    #expect(abs((running.progressFraction ?? 0) - 0.85) < 0.000_001)

    let stopping = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: incomplete,
      isSynchronizing: true,
      isCancelling: true,
      automaticUpdatesEnabled: false
    )
    #expect(stopping.phase == .stopping)

    let partial = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: PublicContractSyncProgress(
        phase: .partial,
        regionCount: 100,
        completedRegions: 100,
        freshRegions: 99,
        failedRegions: 1
      ),
      isSynchronizing: false,
      isCancelling: false,
      automaticUpdatesEnabled: false
    )
    #expect(partial.phase == .partial)
  }

  @Test
  func publicContractTypingWaitsButReturnSearchesImmediately() {
    #expect(
      PublicContractSearchPolicy.delay(isExplicitSubmission: false)
        == .milliseconds(700)
    )
    #expect(
      PublicContractSearchPolicy.delay(isExplicitSubmission: true) == nil
    )
  }

  private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
  }
}

/// Observation fires `onChange` synchronously on the mutating (main) thread.
private final class ObservationFlag: @unchecked Sendable {
  private(set) var count = 0

  func fire() {
    count += 1
  }
}

@MainActor
private final class RenderCounter {
  private(set) var value = 0

  func record() {
    value += 1
  }
}

@MainActor
private final class AnalysisRefreshTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { continuation != nil }
  func wait() async {
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private struct PlannerObservationProbe: View {
  let runtime: RuntimeState
  let counter: RenderCounter
  @ObservedObject private var featureState: RuntimeFeatureState

  init(runtime: RuntimeState, counter: RenderCounter) {
    self.runtime = runtime
    self.counter = counter
    _featureState = ObservedObject(wrappedValue: runtime.plannerFeatureState)
  }

  var body: some View {
    counter.record()
    return Text("Planner revision \(featureState.revision)")
  }
}

private struct SettingsNavigationFrameProbe: NSViewRepresentable {
  let view: NSView
  func makeNSView(context: Context) -> NSView { view }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct DashboardRenderRow: Identifiable {
  let id: Int
}

private struct DashboardRenderingFixture: View {
  let count: Int
  private var rows: [DashboardRenderRow] { (0..<count).map { DashboardRenderRow(id: $0) } }
  private var samples: [DashboardWealthChartSample] {
    if count == 0 {
      return [DashboardWealthChartSample(date: Date(timeIntervalSince1970: 1_780_000_000), value: 0)]
    }
    return (0..<8).map {
      DashboardWealthChartSample(date: Date(timeIntervalSince1970: 1_780_000_000 + Double($0) * 86_400),
        value: 987_000_000_000 + Double($0 % 3) * 2_000_000_000)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      DashboardCardLayout(weights: [1, 1, 1], minimumWidths: [340, 340, 340]) {
        jobs(title: "Ready for delivery")
        jobs(title: "Next 48 hours")
        jobs(title: "Top 5 by material value")
      }
      DashboardCardLayout(weights: [1, 2], minimumWidths: [280, 560]) {
        Panel(title: "Wallet") {
          Text("987.654.321.098 ISK").font(.title).lineLimit(1).minimumScaleFactor(0.6)
          Text("3 Charaktere").font(.caption)
          DisclosureGroup("Character balances") { Text("Synthetic details") }
        }
        Panel(title: "Net worth over time") {
          Text("987.654.321.098 ISK").font(.title2)
          DashboardWealthChart(samples: samples, color: DesignTokens.accent, showsAxes: true)
            .frame(height: 280)
          DisclosureGroup("Character net worth") { Text("Synthetic details") }
        }
      }
    }
    .padding(DesignTokens.spacingLG)
    .background(DesignTokens.canvas)
  }

  private func jobs(title: LocalizedStringKey) -> some View {
    Panel(title: title) {
      DashboardPreviewList(rows: rows) { row in
        VStack(alignment: .leading) {
          EVEEntityText(value: "Synthetischer langer Produktname mit mehreren Bestandteilen \(row.id + 1)", font: .callout, lineLimit: 2)
          Text("987.654.321.098 ISK · 3 Charaktere").font(.caption).monospacedDigit()
        }
      }
    }
  }
}
