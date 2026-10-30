import CSQLite
import Darwin
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Market stock history store")
struct MarketStockHistoryStoreTests {
  private static let regionID: Int64 = 10_000_002
  private static let hubID: Int64 = 60_003_760
  /// 2026-10-29 00:00 UTC.
  private static let dayStart = Date(timeIntervalSince1970: 1_793_232_000)
  private static let hour: TimeInterval = 60 * 60

  @Test
  func recordsPointsDeltasAndUpdatesTheDailyValue() async throws {
    try await withStore { store in
      let first = observation(
        [
          entry(1, type: 34, volume: 100),
          entry(2, type: 34, volume: 50),
          entry(3, type: 34, volume: 30, buy: true),
        ],
        at: Self.dayStart.addingTimeInterval(6 * Self.hour)
      )
      let second = observation(
        [
          entry(1, type: 34, volume: 60),
          entry(3, type: 34, volume: 10, buy: true),
          entry(4, type: 34, volume: 25),
        ],
        at: Self.dayStart.addingTimeInterval(13 * Self.hour)
      )
      #expect(
        try await store.record(first, role: .home, trigger: .scheduled)
          == .recorded(pointID: 1, delta: .unavailable(.noPreviousPoint))
      )
      #expect(
        try await store.record(second, role: .home, trigger: .automaticScan)
          == .recorded(
            pointID: 2,
            delta: .compared(previousCapturedAt: first.point.capturedAt)
          )
      )

      let points = try await store.itemPoints(
        role: .home,
        locationID: Self.hubID,
        typeID: 34,
        now: Self.dayStart.addingTimeInterval(14 * Self.hour)
      )
      #expect(points.count == 2)
      #expect(points[0].trigger == .scheduled)
      #expect(points[0].value.sell.units == 150)
      #expect(points[0].sell == nil)
      #expect(points[1].value.sell == MarketStockSideValue(units: 85, orderCount: 2, bestPrice: 10))
      #expect(points[1].sell == MarketStockSideDelta(added: 25, partiallyFilled: 40, vanished: 50))
      #expect(points[1].buy == MarketStockSideDelta(added: 0, partiallyFilled: 20, vanished: 0))

      let days = try await store.itemDays(
        role: .home,
        locationID: Self.hubID,
        typeID: 34,
        days: 2,
        now: Self.dayStart.addingTimeInterval(14 * Self.hour)
      )
      #expect(days.count == 2)
      // Yesterday has no point: unknown, never 0.
      #expect(days[0].day == Self.dayStart.addingTimeInterval(-24 * Self.hour))
      #expect(days[0].recorded == nil)
      let today = try #require(days[1].recorded)
      #expect(days[1].day == Self.dayStart)
      #expect(today.value.sell.units == 85)
      #expect(today.value.buy.units == 10)
      #expect(today.minimumSellUnits == 85)
      #expect(today.maximumSellUnits == 150)
      // Only the known delta counts; the first point's is unknown.
      #expect(today.sell == MarketStockSideDelta(added: 25, partiallyFilled: 40, vanished: 50))
      #expect(today.pointCount == 2)
      #expect(today.unknownDeltaCount == 1)
    }
  }

  @Test
  func itemsAppearingOrVanishingDuringTheDayKeepKnownZeros() async throws {
    try await withStore { store in
      let morning = Self.dayStart.addingTimeInterval(6 * Self.hour)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 10)], at: morning),
        role: .main,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(2, type: 35, volume: 7)],
          at: morning.addingTimeInterval(7 * Self.hour)
        ),
        role: .main,
        trigger: .scheduled
      )
      let now = morning.addingTimeInterval(8 * Self.hour)
      let gone = try #require(
        try await store.itemDays(
          role: .main, locationID: Self.hubID, typeID: 34, days: 1, now: now
        ).first?.recorded
      )
      #expect(gone.value.sell == .empty)
      #expect(gone.minimumSellUnits == 0)
      #expect(gone.maximumSellUnits == 10)
      #expect(gone.sell == MarketStockSideDelta(added: 0, partiallyFilled: 0, vanished: 10))
      let arrived = try #require(
        try await store.itemDays(
          role: .main, locationID: Self.hubID, typeID: 35, days: 1, now: now
        ).first?.recorded
      )
      #expect(arrived.value.sell.units == 7)
      #expect(arrived.minimumSellUnits == 0)
      #expect(arrived.maximumSellUnits == 7)
      // Never listed but the day has points: a known 0.
      let never = try #require(
        try await store.itemDays(
          role: .main, locationID: Self.hubID, typeID: 99, days: 1, now: now
        ).first?.recorded
      )
      #expect(never.value.sell == .empty)
      #expect(never.sell == .zero)
    }
  }

  @Test
  func pointsTooCloseOrOutOfOrderAreNotStored() async throws {
    try await withStore { store in
      let first = Self.dayStart.addingTimeInterval(6 * Self.hour)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 100)], at: first),
        role: .coalition,
        trigger: .scheduled
      )
      #expect(
        try await store.record(
          observation(
            [entry(1, type: 34, volume: 1)],
            at: first.addingTimeInterval(29 * 60)
          ),
          role: .coalition,
          trigger: .manualScan
        ) == .skippedTooClose(lastCapturedAt: first)
      )
      #expect(
        try await store.record(
          observation(
            [entry(1, type: 34, volume: 1)],
            at: first.addingTimeInterval(-60)
          ),
          role: .coalition,
          trigger: .manualScan
        ) == .skippedOutOfOrder(lastCapturedAt: first)
      )
      // The next delta starts from the older stored point.
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 70)],
          at: first.addingTimeInterval(30 * 60)
        ),
        role: .coalition,
        trigger: .manualScan
      )
      let points = try await store.itemPoints(
        role: .coalition,
        locationID: Self.hubID,
        typeID: 34,
        now: first.addingTimeInterval(Self.hour)
      )
      #expect(points.count == 2)
      #expect(points[1].sell == MarketStockSideDelta(added: 0, partiallyFilled: 30, vanished: 0))
    }
  }

  @Test
  func hubOverviewSumsWindowsAndReportsCoverage() async throws {
    try await withStore { store in
      // Day -2: first point (unknown delta); day -1: no point; today: two.
      let dayMinus2 = Self.dayStart.addingTimeInterval(-48 * Self.hour + 6 * Self.hour)
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 100), entry(2, type: 36, volume: 5)],
          at: dayMinus2
        ),
        role: .home,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 80)],
          at: Self.dayStart.addingTimeInterval(6 * Self.hour)
        ),
        role: .home,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 70), entry(3, type: 34, volume: 40)],
          at: Self.dayStart.addingTimeInterval(13 * Self.hour)
        ),
        role: .home,
        trigger: .scheduled
      )
      let overview = try await store.hubOverview(
        role: .home,
        locationID: Self.hubID,
        windows: [1, 7],
        now: Self.dayStart.addingTimeInterval(20 * Self.hour)
      )
      #expect(overview.latestCapturedAt == Self.dayStart.addingTimeInterval(13 * Self.hour))
      #expect(
        overview.coverage == [
          MarketStockWindowCoverage(
            days: 1, daysWithPoint: 1, daysWithKnownDelta: 1, daysWithUnknownDelta: 0),
          MarketStockWindowCoverage(
            days: 7, daysWithPoint: 2, daysWithKnownDelta: 1, daysWithUnknownDelta: 1),
        ]
      )
      #expect(overview.coverage[0].isComplete)
      #expect(!overview.coverage[1].isComplete)
      let item = try #require(overview.itemsByType[34])
      #expect(item.current.sell.units == 110)
      #expect(
        item.totals.map(\.sell) == [
          MarketStockSideDelta(added: 40, partiallyFilled: 30, vanished: 0),
          MarketStockSideDelta(added: 40, partiallyFilled: 30, vanished: 0),
        ]
      )
      // Sold out inside the window: listed with a known 0 stock.
      let soldOut = try #require(overview.itemsByType[36])
      #expect(soldOut.current.sell == .empty)
      #expect(soldOut.totals[1].sell.vanished == 5)

      let empty = try await store.hubOverview(
        role: .main,
        locationID: Self.hubID,
        now: Self.dayStart
      )
      #expect(empty.latestCapturedAt == nil)
      #expect(empty.itemsByType.isEmpty)
    }
  }

  @Test
  func compactionDropsOldPointsAndDaysOncePerDay() async throws {
    try await withStore { store in
      let old = Self.dayStart.addingTimeInterval(-95 * 24 * Self.hour)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 10)], at: old),
        role: .main,
        trigger: .scheduled
      )
      let eightDaysAgo = Self.dayStart.addingTimeInterval(-8 * 24 * Self.hour)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 9)], at: eightDaysAgo),
        role: .main,
        trigger: .scheduled
      )
      let recent = Self.dayStart.addingTimeInterval(6 * Self.hour)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 8)], at: recent),
        role: .main,
        trigger: .scheduled
      )
      let now = Self.dayStart.addingTimeInterval(12 * Self.hour)
      let result = try await store.compactIfDue(now: now)
      #expect(result == MarketStockCompactionResult(removedPoints: 2, removedDays: 1, didRun: true))
      #expect(
        try await store.compactIfDue(now: now)
          == MarketStockCompactionResult(removedPoints: 0, removedDays: 0, didRun: false)
      )
      let points = try await store.itemPoints(
        role: .main, locationID: Self.hubID, typeID: 34, days: 120, now: now
      )
      #expect(points.map(\.value.sell.units) == [8])
      // The 8-day-old daily value survives the point compaction.
      let days = try await store.itemDays(
        role: .main, locationID: Self.hubID, typeID: 34, days: 9, now: now
      )
      #expect(days.first?.recorded?.value.sell.units == 9)
      #expect(days.last?.recorded?.value.sell.units == 8)
      let all = try await store.itemDays(
        role: .main, locationID: Self.hubID, typeID: 34, days: 120, now: now
      )
      #expect(all.compactMap(\.recorded).count == 2)
    }
  }

  @Test
  func baselineSurvivesReopeningAndNewerSchemasAreRefused() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("market/market-stock-history.sqlite")
    let first = Self.dayStart.addingTimeInterval(6 * Self.hour)
    do {
      let store = try await MarketStockHistoryStore.open(url: url)
      _ = try await store.record(
        observation([entry(1, type: 34, volume: 100)], at: first),
        role: .main,
        trigger: .scheduled
      )
      await store.close()
    }
    let reopened = try await MarketStockHistoryStore.open(url: url)
    #expect(
      try await reopened.record(
        observation([entry(1, type: 34, volume: 60)], at: first.addingTimeInterval(Self.hour)),
        role: .main,
        trigger: .scheduled
      ) == .recorded(pointID: 2, delta: .compared(previousCapturedAt: first))
    )
    #expect(
      try await reopened.latestPointCapturedAt(role: .main, locationID: Self.hubID)
        == first.addingTimeInterval(Self.hour)
    )
    await reopened.close()

    var handle: OpaquePointer?
    #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
    #expect(sqlite3_exec(handle, "PRAGMA user_version = 99", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(handle)
    #expect(throws: MarketStockHistoryStoreError.unsupportedSchemaVersion(99)) {
      _ = try MarketStockHistoryStore(url: url)
    }
  }

  @Test
  func backupContainsTheCommittedHistory() async throws {
    let root = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppDataPaths.resolve(applicationSupportRoot: root, fileExists: { _ in false })
    try paths.prepareDirectories()
    var applicationStore: OpaquePointer?
    #expect(sqlite3_open(paths.swiftDataStoreURL.path, &applicationStore) == SQLITE_OK)
    #expect(
      sqlite3_exec(applicationStore, "CREATE TABLE fixture (n INTEGER);", nil, nil, nil)
        == SQLITE_OK)
    sqlite3_close(applicationStore)

    let url = paths.dataRoot.appendingPathComponent("market/market-stock-history.sqlite")
    let store = try await MarketStockHistoryStore.open(url: url)
    _ = try await store.record(
      observation([entry(1, type: 34, volume: 42)], at: Self.dayStart),
      role: .home,
      trigger: .scheduled
    )
    // The store stays open, its pages are still in the WAL.
    let target = root.appendingPathComponent("test.nexusbackup")
    try ConsolidationBackup.create(
      dataRoot: paths.dataRoot,
      destination: target,
      defaults: Data(),
      schema: 1
    )
    await store.close()
    let manifest = try ConsolidationBackup.verify(target)
    #expect(manifest.files["data/market/market-stock-history.sqlite"] != nil)
    let copy = try MarketStockHistoryStore(
      url: target.appendingPathComponent("data/market/market-stock-history.sqlite")
    )
    let days = try await copy.itemDays(
      role: .home, locationID: Self.hubID, typeID: 34, days: 1, now: Self.dayStart
    )
    #expect(days.first?.recorded?.value.sell.units == 42)
    await copy.close()
  }

  @Test
  func overviewFeedsTradeVolumesNetChangesAndStock() async throws {
    try await withStore { store in
      // Day -1: first point (unknown delta); today: two points.
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 100), entry(2, type: 34, volume: 50)],
          at: Self.dayStart.addingTimeInterval(-24 * Self.hour + 13 * Self.hour)
        ),
        role: .home,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 70), entry(3, type: 34, volume: 20)],
          at: Self.dayStart.addingTimeInterval(6 * Self.hour)
        ),
        role: .home,
        trigger: .scheduled
      )
      let overview = try await store.hubOverview(
        role: .home,
        locationID: Self.hubID,
        windows: MarketHistoryWindow.allCases.map(\.days),
        now: Self.dayStart.addingTimeInterval(8 * Self.hour)
      )
      // Partial fills 30 surely traded; at most 80 including the vanished
      // order of 50. Yesterday has a point without a known delta: partly
      // recorded.
      let twoDays = try #require(overview.hubTradedVolume(for: 34, window: .twoDays))
      #expect(
        twoDays
          == HubTradedVolume(
            units: 30, recordedDays: 1, windowDays: 2, upperBoundUnits: 80, partialDays: 1)
      )
      #expect(!twoDays.isComplete)
      let today = try #require(overview.hubTradedVolume(for: 34, window: .oneDay))
      #expect(today.units == 30)
      #expect(today.isComplete)
      let net = try #require(overview.netChange(for: 34, window: .sevenDays))
      #expect(net.sell == MarketStockSideDelta(added: 20, partiallyFilled: 30, vanished: 50))
      #expect(net.net == -60)
      #expect(!net.isComplete)
      // Listed at no point: a known 0, not unknown.
      #expect(overview.hubTradedVolume(for: 99, window: .sevenDays)?.units == 0)
      #expect(overview.currentStock(for: 34)?.sell.units == 90)
      #expect(overview.currentStock(for: 99)?.sell == .empty)

      // Only one point so far: stock known, traded volume unknown.
      _ = try await store.record(
        observation([entry(9, type: 34, volume: 5)], at: Self.dayStart),
        role: .coalition,
        trigger: .scheduled
      )
      let first = try await store.hubOverview(
        role: .coalition,
        locationID: Self.hubID,
        windows: MarketHistoryWindow.allCases.map(\.days),
        now: Self.dayStart.addingTimeInterval(Self.hour)
      )
      #expect(first.hubTradedVolume(for: 34, window: .sevenDays) == nil)
      #expect(first.netChange(for: 34, window: .sevenDays) == nil)
      #expect(first.currentStock(for: 34)?.sell.units == 5)
      // No point at all: everything unknown.
      let none = try await store.hubOverview(
        role: .main, locationID: Self.hubID, now: Self.dayStart)
      #expect(none.currentStock(for: 34) == nil)
      #expect(none.hubTradedVolume(for: 34, window: .oneDay) == nil)
    }
  }

  @Test
  func itemChartKeepsGapsAndSwitchesFromDailyValuesToPoints() async throws {
    try await withStore { store in
      let day = 24 * Self.hour
      // Days -12 and -11 (daily values), nothing on day -10 (gap), day -9,
      // then points inside the 7-day window on day -2.
      for (offset, volume) in [(-12.0, 100), (-11.0, 90), (-9.0, 80)] as [(Double, Int64)] {
        _ = try await store.record(
          observation(
            [entry(1, type: 34, volume: volume)],
            at: Self.dayStart.addingTimeInterval(offset * day + 13 * Self.hour)
          ),
          role: .main,
          trigger: .scheduled
        )
      }
      _ = try await store.record(
        observation([], at: Self.dayStart.addingTimeInterval(-2 * day + 6 * Self.hour)),
        role: .main,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(2, type: 34, volume: 40)],
          at: Self.dayStart.addingTimeInterval(-2 * day + 13 * Self.hour)
        ),
        role: .main,
        trigger: .scheduled
      )
      let now = Self.dayStart.addingTimeInterval(12 * Self.hour)
      let days = try await store.itemDays(
        role: .main, locationID: Self.hubID, typeID: 34, days: 30, now: now)
      let points = try await store.itemPoints(
        role: .main, locationID: Self.hubID, typeID: 34, days: 7, now: now)
      let elevenDaysAgo = try #require(days.first {
        $0.day == Self.dayStart.addingTimeInterval(-11 * day)
      }?.recorded)
      #expect(elevenDaysAgo.lastPointAt == Self.dayStart.addingTimeInterval(-11 * day + 13 * Self.hour))

      let fineStart = now.addingTimeInterval(-7 * day)
      let units = MarketStockChartBuilder.samples(
        days: days, points: points, metric: .sellUnits, fineWindowStart: fineStart)
      #expect(units.map(\.value) == [100, 90, 80, 0, 40])
      #expect(units.map(\.isDailyValue) == [true, true, true, false, false])
      // Gap on day -10 and between day -9 and day -2.
      #expect(units.map(\.segment) == [0, 0, 1, 2, 2])
      // No sell order at the 06:00 point: no price, so the line breaks.
      let prices = MarketStockChartBuilder.samples(
        days: days, points: points, metric: .sellPrice, fineWindowStart: fineStart)
      #expect(prices.map(\.value) == [10, 10, 10, 10])
      #expect(prices.map(\.segment) == [0, 0, 1, 2])

      let rows = days.map(MarketStockDayRow.init)
      let byStock = MarketStockDayRow.sorted(rows, by: .sellUnits, ascending: true)
      #expect(byStock.prefix(4).map(\.sellUnits) == [40, 80, 90, 100])
      #expect(byStock.last?.sellUnits == nil)
      let byStockDescending = MarketStockDayRow.sorted(rows, by: .sellUnits, ascending: false)
      #expect(byStockDescending.first?.sellUnits == nil)
      let firstDay = try #require(rows.first { $0.sellUnits == 100 })
      #expect(firstDay.isPartial)
      #expect(firstDay.net == nil)
      let secondDay = try #require(rows.first { $0.sellUnits == 90 })
      #expect(secondDay.net == -10)
      #expect(!secondDay.isPartial)
    }
  }

  @Test
  func overviewRowsSortTypedWithUnknownValuesAndNamesLast() async throws {
    try await withStore { store in
      let day = 24 * Self.hour
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 100), entry(2, type: 35, volume: 10)],
          at: Self.dayStart.addingTimeInterval(-day + 13 * Self.hour)
        ),
        role: .main,
        trigger: .scheduled
      )
      _ = try await store.record(
        observation(
          [entry(1, type: 34, volume: 60), entry(3, type: 36, volume: 5)],
          at: Self.dayStart.addingTimeInterval(6 * Self.hour)
        ),
        role: .main,
        trigger: .scheduled
      )
      let overview = try await store.hubOverview(
        role: .main, locationID: Self.hubID, windows: [1, 7, 30],
        now: Self.dayStart.addingTimeInterval(8 * Self.hour))
      let rows = MarketStockOverviewRow.rows(
        overview, names: [34: "Tritanium", 35: "Pyerite"])
      let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.typeID, $0) })
      #expect(rows.count == 3)
      #expect(byID[34]?.current.sell.units == 60)
      #expect(byID[34]?.netByWindow[1] == -40)
      #expect(byID[34]?.removedByWindow[7] == 40)
      // Sold out: listed with a known 0 stock and its vanished units.
      #expect(byID[35]?.current.sell == .empty)
      #expect(byID[35]?.removedByWindow[1] == 10)
      #expect(byID[36]?.name == nil)

      let byNet = rows.sorted(using: MarketStockOverviewComparator(column: .net(days: 1)))
      #expect(byNet.map(\.typeID) == [34, 35, 36])
      let byStockDescending = rows.sorted(
        using: MarketStockOverviewComparator(column: .sellUnits, order: .reverse))
      #expect(byStockDescending.map(\.typeID) == [34, 36, 35])
      // An unresolved name sorts after resolved ones ascending.
      let byName = rows.sorted(using: MarketStockOverviewComparator(column: .name))
      #expect(byName.map(\.typeID) == [35, 34, 36])
      // A window without a known delta is unknown: it sorts last ascending
      // and first descending.
      let unknown = MarketStockOverviewRow(
        typeID: 99, name: "Zydrine", current: MarketStockItemValue(typeID: 99, sell: .empty, buy: .empty),
        netByWindow: [:], removedByWindow: [:])
      #expect(
        (rows + [unknown]).sorted(using: MarketStockOverviewComparator(column: .net(days: 1)))
          .last?.typeID == 99)
      #expect(
        (rows + [unknown]).sorted(
          using: MarketStockOverviewComparator(column: .net(days: 1), order: .reverse)
        ).first?.typeID == 99)
    }
  }

  /// One Jita-sized point pair in the normal suite (C7 guard rail).
  @Test
  func jitaSizedPointIsWrittenWithinBudget() async throws {
    try await withStore { store in
      var simulator = HubSimulator(seed: 0xA11CE, typeCount: 15_000, ordersPerType: 12)
      let clock = ContinuousClock()
      var durations: [Duration] = []
      for step in 0..<2 {
        let observation = simulator.next(
          at: Self.dayStart.addingTimeInterval(Double(step) * 6 * Self.hour)
        )
        let duration = try await clock.measure {
          _ = try await store.record(observation, role: .main, trigger: .scheduled)
        }
        durations.append(duration)
      }
      print("market-stock store jita-sized write: \(durations)")
      #expect(durations.allSatisfy { $0 < .seconds(20) })
    }
  }

  /// Opt-in size measurement (MARKTBESTAND_PLAN P2), three Jita-sized hubs
  /// (15,000 items, 180,000 orders each), daily compaction like in use:
  /// - A: the first 7 days with six points per day;
  /// - B: steady state after 90 days (one point per day for days 90 to 8,
  ///   six per day for the last 7 days; the daily row count does not depend
  ///   on the points per day).
  /// Run with `MARKET_STOCK_MEASURE=1 swift test --filter measureNinetyDays`.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["MARKET_STOCK_MEASURE"] == "1")
  )
  func measureNinetyDays() async throws {
    let start = MemoryFootprint.current()
    // Calibration: the synthetic hubs alone, without the store.
    do {
      var hubs = (1...3).map {
        HubSimulator(seed: UInt64($0), typeCount: 15_000, ordersPerType: 12)
      }
      for step in 0..<6 {
        for index in hubs.indices {
          _ = hubs[index].next(at: Self.dayStart.addingTimeInterval(Double(step) * Self.hour))
        }
      }
    }
    let simulatorPeak = MemoryFootprint.peak()
    let sevenDays = try await simulate(days: 7, finePointsFromDay: 7)
    let ninetyDays = try await simulate(days: 90, finePointsFromDay: 7)
    let peak = MemoryFootprint.peak()
    let durations = (sevenDays.durations + ninetyDays.durations).sorted()
    let total = durations.reduce(Duration.zero, +)
    print(
      "market-stock measure: points=\(durations.count) "
        + "size7Days=\(sevenDays.size) size90Days=\(ninetyDays.size) "
        + "writeAvg=\(total / durations.count) "
        + "writeMedian=\(durations[durations.count / 2]) "
        + "writeMax=\(durations.last ?? .zero) "
        + "footprintStart=\(start) simulatorPeakGrowth=\(simulatorPeak - start) "
        + "peak=\(peak) peakGrowth=\(peak - start) "
        + "tables90Days=\(ninetyDays.tables)"
    )
  }

  private func simulate(
    days: Int,
    finePointsFromDay: Int
  ) async throws -> (size: Int64, durations: [Duration], tables: String) {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("market-stock-history.sqlite")
    let store = try await MarketStockHistoryStore.open(url: url)
    var hubs: [(OpportunityHubRole, HubSimulator)] = [
      (.main, HubSimulator(seed: 1, typeCount: 15_000, ordersPerType: 12)),
      (.home, HubSimulator(seed: 2, typeCount: 15_000, ordersPerType: 12)),
      (.coalition, HubSimulator(seed: 3, typeCount: 15_000, ordersPerType: 12)),
    ]
    let clock = ContinuousClock()
    var durations: [Duration] = []
    for dayOffset in stride(from: days - 1, through: 0, by: -1) {
      let day = Self.dayStart.addingTimeInterval(-Double(dayOffset) * 24 * Self.hour)
      let hours: [Double] =
        dayOffset < finePointsFromDay ? [1, 5, 6, 13, 17, 21] : [13]
      for hour in hours {
        for index in hubs.indices {
          let observation = hubs[index].1.next(at: day.addingTimeInterval(hour * Self.hour))
          let role = hubs[index].0
          durations.append(
            try await clock.measure {
              _ = try await store.record(observation, role: role, trigger: .scheduled)
            }
          )
        }
      }
      _ = try await store.compactIfDue(now: day.addingTimeInterval(23 * Self.hour))
    }
    await store.close()
    return (Self.fileSize(url), durations, Self.tableSizes(url))
  }

  /// Bytes per table and index from SQLite's `dbstat`, when available.
  private static func tableSizes(_ url: URL) -> String {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
    else { return "unavailable" }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        handle,
        "SELECT name, SUM(pgsize), SUM(ncell) FROM dbstat GROUP BY name ORDER BY 2 DESC",
        -1, &statement, nil) == SQLITE_OK
    else { return "dbstat unavailable" }
    defer { sqlite3_finalize(statement) }
    var parts: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "?"
      parts.append(
        "\(name)=\(sqlite3_column_int64(statement, 1))B/\(sqlite3_column_int64(statement, 2))cells"
      )
    }
    var freelist: OpaquePointer?
    if sqlite3_prepare_v2(handle, "PRAGMA freelist_count", -1, &freelist, nil) == SQLITE_OK,
      sqlite3_step(freelist) == SQLITE_ROW
    {
      parts.append("freePages=\(sqlite3_column_int64(freelist, 0))")
    }
    sqlite3_finalize(freelist)
    return parts.joined(separator: " ")
  }

  // MARK: Helpers

  private static func fileSize(_ url: URL) -> Int64 {
    ["", "-wal"].reduce(0) { total, suffix in
      let size =
        (try? FileManager.default.attributesOfItem(atPath: url.path + suffix)[.size]
          as? NSNumber)?.int64Value ?? 0
      return total + size
    }
  }

  private func withStore(
    _ body: (MarketStockHistoryStore) async throws -> Void
  ) async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = try await MarketStockHistoryStore.open(
      url: folder.appendingPathComponent("market/market-stock-history.sqlite")
    )
    do {
      try await body(store)
    } catch {
      await store.close()
      throw error
    }
    await store.close()
  }

  private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "market-stock-store-\(UUID())",
      isDirectory: true
    )
  }

  private func entry(
    _ orderID: Int64,
    type typeID: Int64,
    volume: Int64,
    buy: Bool = false
  ) -> MarketStockOrderEntry {
    MarketStockOrderEntry(
      orderID: orderID,
      typeID: typeID,
      volumeRemaining: volume,
      isBuy: buy
    )
  }

  /// Builds an observation directly from sorted order entries (price 10 for
  /// sells, 8 for buys) without an ESI order book.
  private func observation(
    _ entries: [MarketStockOrderEntry],
    at capturedAt: Date
  ) -> MarketStockObservation {
    Self.makeObservation(entries.sorted { $0.orderID < $1.orderID }, at: capturedAt) {
      $0.isBuy ? 8 : 10
    }
  }

  fileprivate static func makeObservation(
    _ sorted: [MarketStockOrderEntry],
    at capturedAt: Date,
    price: (MarketStockOrderEntry) -> Double
  ) -> MarketStockObservation {
    var sell: [Int64: MarketStockSideValue] = [:]
    var buy: [Int64: MarketStockSideValue] = [:]
    for entry in sorted {
      let current = (entry.isBuy ? buy : sell)[entry.typeID]
      let price = price(entry)
      let best = current?.bestPrice.map { entry.isBuy ? max($0, price) : min($0, price) }
      let updated = MarketStockSideValue(
        units: (current?.units ?? 0) + entry.volumeRemaining,
        orderCount: (current?.orderCount ?? 0) + 1,
        bestPrice: best ?? price
      )
      if entry.isBuy { buy[entry.typeID] = updated } else { sell[entry.typeID] = updated }
    }
    var items: [Int64: MarketStockItemValue] = [:]
    for typeID in Set(sell.keys).union(buy.keys) {
      items[typeID] = MarketStockItemValue(
        typeID: typeID,
        sell: sell[typeID] ?? .empty,
        buy: buy[typeID] ?? .empty
      )
    }
    return MarketStockObservation(
      point: MarketStockPoint(
        regionID: regionID,
        locationID: hubID,
        capturedAt: capturedAt,
        sourceSnapshotID: UUID(),
        itemsByType: items
      ),
      baseline: MarketStockOrderBaseline(
        regionID: regionID,
        locationID: hubID,
        capturedAt: capturedAt,
        entries: sorted
      )
    )
  }
}

/// Synthetic hub that changes like a busy market between points: a quarter
/// of the orders trade down, a tenth disappear, new orders arrive.
private struct HubSimulator {
  private var generator: StoreSeededGenerator
  private var entries: [MarketStockOrderEntry] = []
  private var nextOrderID: Int64 = 6_000_000_000
  private let typeCount: Int
  private let ordersPerType: Int
  private var isFirst = true

  init(seed: UInt64, typeCount: Int, ordersPerType: Int) {
    generator = StoreSeededGenerator(seed: seed)
    self.typeCount = typeCount
    self.ordersPerType = ordersPerType
  }

  mutating func next(at capturedAt: Date) -> MarketStockObservation {
    if isFirst {
      isFirst = false
      entries.reserveCapacity(typeCount * ordersPerType)
      for typeIndex in 0..<typeCount {
        for orderIndex in 0..<ordersPerType {
          appendOrder(type: Int64(1_000 + typeIndex), buy: orderIndex >= ordersPerType / 2)
        }
      }
    } else {
      var changed: [MarketStockOrderEntry] = []
      changed.reserveCapacity(entries.count)
      for entry in entries {
        switch Int.random(in: 0..<20, using: &generator) {
        case 0, 1:
          continue
        case 2...6:
          changed.append(
            MarketStockOrderEntry(
              orderID: entry.orderID,
              typeID: entry.typeID,
              volumeRemaining: max(1, entry.volumeRemaining / 2),
              isBuy: entry.isBuy
            )
          )
        default:
          changed.append(entry)
        }
      }
      entries = changed
      let removed = typeCount * ordersPerType - entries.count
      for _ in 0..<max(0, removed) {
        appendOrder(
          type: Int64(1_000 + Int.random(in: 0..<typeCount, using: &generator)),
          buy: Bool.random(using: &generator)
        )
      }
    }
    return MarketStockHistoryStoreTests.makeObservation(entries, at: capturedAt) {
      Double($0.typeID % 997) + ($0.isBuy ? 0.5 : 1.5)
    }
  }

  private mutating func appendOrder(type typeID: Int64, buy: Bool) {
    entries.append(
      MarketStockOrderEntry(
        orderID: nextOrderID,
        typeID: typeID,
        volumeRemaining: Int64.random(in: 1...100_000, using: &generator),
        isBuy: buy
      )
    )
    nextOrderID += 1
  }
}

private struct StoreSeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

/// Process memory footprint from `task_vm_info` (bytes).
private enum MemoryFootprint {
  static func current() -> Int64 { info().map { Int64($0.phys_footprint) } ?? 0 }
  static func peak() -> Int64 { info().map { Int64($0.ledger_phys_footprint_peak) } ?? 0 }

  private static func info() -> task_vm_info_data_t? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? info : nil
  }
}
