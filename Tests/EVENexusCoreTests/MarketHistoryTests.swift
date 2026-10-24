import Foundation
import Testing

@testable import EVENexusCore

@Suite("Regional market history volume")
struct MarketHistoryTests {
  private static func day(_ value: String) -> Date {
    MarketTypeVolumeHistory.parseDay(value)!
  }

  private static func row(_ date: String, _ volume: Int64) -> ESIMarketHistoryDTO {
    ESIMarketHistoryDTO(
      average: 10,
      date: date,
      highest: 11,
      lowest: 9,
      orderCount: 1,
      volume: volume
    )
  }

  private static func history(
    _ rows: [ESIMarketHistoryDTO],
    lastModified: Date? = ESIClient.httpDate("Sat, 24 Oct 2026 11:05:00 GMT")
  ) -> MarketTypeVolumeHistory {
    MarketTypeVolumeHistory.make(
      typeID: 34,
      regionID: 10_000_002,
      rows: rows,
      lastModified: lastModified,
      capturedAt: ESIClient.httpDate("Sat, 24 Oct 2026 12:00:00 GMT")!
    )
  }

  @Test
  func windowsSumTheDaysEndingWithTheAnchorAndMissingDaysAreZero() {
    let history = Self.history([
      Self.row("2026-10-23", 100),
      Self.row("2026-10-22", 50),
      // 2026-10-21 and 2026-10-20 had no trades and are omitted by ESI.
      Self.row("2026-10-19", 7),
      Self.row("2026-10-17", 3),
      Self.row("2026-09-24", 1_000),
      Self.row("2026-09-23", 9_999),
    ])

    #expect(history.anchorDay == Self.day("2026-10-23"))
    #expect(history.tradedVolume(.oneDay) == 100)
    #expect(history.tradedVolume(.twoDays) == 150)
    #expect(history.tradedVolume(.fiveDays) == 157)
    #expect(history.tradedVolume(.sevenDays) == 160)
    #expect(history.tradedVolume(.thirtyDays) == 1_160)
    #expect(history.averageDailyVolume(.twoDays) == 75)
    #expect(history.averageDailyVolume(.fiveDays) == 31.4)
  }

  @Test
  func emptyHistoryIsAKnownZero() {
    let history = Self.history([])
    for window in MarketHistoryWindow.allCases {
      #expect(history.tradedVolume(window) == 0)
      #expect(history.averageDailyVolume(window) == 0)
    }
  }

  @Test
  func anchorFallsBackToTheDayBeforeCaptureAndMovesToANewerReportedDay() {
    let withoutHeader = Self.history([Self.row("2026-10-22", 5)], lastModified: nil)
    #expect(withoutHeader.anchorDay == Self.day("2026-10-23"))
    #expect(withoutHeader.tradedVolume(.oneDay) == 0)
    #expect(withoutHeader.tradedVolume(.twoDays) == 5)

    let beforeRefresh = Self.history(
      [Self.row("2026-10-22", 5)],
      lastModified: ESIClient.httpDate("Fri, 23 Oct 2026 11:05:00 GMT")
    )
    #expect(beforeRefresh.anchorDay == Self.day("2026-10-22"))
    #expect(beforeRefresh.tradedVolume(.oneDay) == 5)

    let newerRow = Self.history(
      [Self.row("2026-10-23", 8)],
      lastModified: ESIClient.httpDate("Fri, 23 Oct 2026 11:05:00 GMT")
    )
    #expect(newerRow.anchorDay == Self.day("2026-10-23"))
    #expect(newerRow.tradedVolume(.oneDay) == 8)
  }

  @Test
  func invalidRowsAreDropped() {
    let history = Self.history([
      Self.row("2026-10-23", 10),
      Self.row("2026-13-01", 500),
      Self.row("yesterday", 500),
      Self.row("2026-10-22", -4),
    ])
    #expect(history.tradedVolume(.thirtyDays) == 10)
  }

  @Test
  func dailyProfitPotentialMultipliesProfitWithAverageVolume() {
    let history = Self.history([Self.row("2026-10-23", 70), Self.row("2026-10-20", 70)])
    func display(profit: Double?, history: MarketTypeVolumeHistory?) -> TradeDisplayRow {
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: 34, profit: profit),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        volumeHistory: history
      )
    }
    #expect(display(profit: 5, history: history).dailyProfitPotential(.sevenDays) == 100)
    #expect(display(profit: -2, history: history).dailyProfitPotential(.sevenDays) == -40)
    #expect(display(profit: nil, history: history).dailyProfitPotential(.sevenDays) == nil)
    #expect(display(profit: 5, history: nil).dailyProfitPotential(.sevenDays) == nil)
    #expect(display(profit: 5, history: nil).tradedVolume(.sevenDays) == nil)
  }

  @Test
  func profitPotentialsMultiplyProfitWithWindowVolume() {
    let history = Self.history([Self.row("2026-10-23", 70), Self.row("2026-10-20", 30)])
    let hub = [MarketHistoryWindow.sevenDays: HubTradedVolume(units: 12, recordedDays: 5, windowDays: 7)]
    func display(
      profit: Double?,
      history: MarketTypeVolumeHistory?,
      hub: [MarketHistoryWindow: HubTradedVolume]
    ) -> TradeDisplayRow {
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: 34, profit: profit),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        volumeHistory: history,
        hubTradedVolumes: hub
      )
    }
    let known = display(profit: 5, history: history, hub: hub)
    #expect(known.regionProfitPotential(.sevenDays) == 500)
    #expect(known.hubProfitPotential(.sevenDays) == 60)
    #expect(known.hubProfitPotential(.thirtyDays) == nil)
    #expect(display(profit: -2, history: history, hub: hub).regionProfitPotential(.sevenDays) == -200)
    #expect(display(profit: -2, history: history, hub: hub).hubProfitPotential(.sevenDays) == -24)
    #expect(display(profit: nil, history: history, hub: hub).regionProfitPotential(.sevenDays) == nil)
    #expect(display(profit: nil, history: history, hub: hub).hubProfitPotential(.sevenDays) == nil)
    #expect(display(profit: 5, history: nil, hub: [:]).regionProfitPotential(.sevenDays) == nil)
    #expect(display(profit: 5, history: nil, hub: [:]).hubProfitPotential(.sevenDays) == nil)

    let rows = [
      display(profit: 5, history: nil, hub: [:]),
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: 35, profit: 1),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        volumeHistory: history,
        hubTradedVolumes: [.sevenDays: HubTradedVolume(units: 100, recordedDays: 7, windowDays: 7)]
      ),
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: 36, profit: 10),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        volumeHistory: history,
        hubTradedVolumes: [.sevenDays: HubTradedVolume(units: 1, recordedDays: 7, windowDays: 7)]
      ),
    ]
    #expect(
      TradeRowSorter.sorted(rows, by: .hubProfitPotential, ascending: false, volumeWindow: .sevenDays)
        .map(\.id) == [34, 35, 36]
    )
    #expect(
      TradeRowSorter.sorted(
        rows,
        by: .regionProfitPotential,
        ascending: false,
        volumeWindow: .sevenDays
      ).map(\.id) == [34, 36, 35]
    )
    #expect(
      TradeRowSorter.sorted(
        rows,
        by: .regionProfitPotential,
        ascending: true,
        volumeWindow: .sevenDays
      ).map(\.id) == [35, 36, 34]
    )
  }

  @Test
  func snapshotMergeReplacesPerTypeAndClearsRecoveredFailures() {
    let loaded = Self.history([Self.row("2026-10-23", 1)])
    var snapshot = MarketVolumeHistorySnapshot(
      regionID: 10_000_002,
      unavailableTypeIDs: [34, 35]
    )
    snapshot.merge(
      MarketVolumeHistorySnapshot(
        regionID: 10_000_002,
        historiesByType: [34: loaded],
        unavailableTypeIDs: [36]
      )
    )
    #expect(snapshot.historiesByType[34] == loaded)
    #expect(snapshot.unavailableTypeIDs == [35, 36])

    snapshot.merge(MarketVolumeHistorySnapshot(regionID: 10_000_043, unavailableTypeIDs: [1]))
    #expect(!snapshot.unavailableTypeIDs.contains(1))
  }

  @Test
  func historiesLoadedTodayAreNotRequestedAgain() throws {
    // Captured 24.10. 12:00 UTC, before that day's refresh: anchor 22.10.
    let beforeRefresh = Self.history(
      [Self.row("2026-10-22", 1)],
      lastModified: ESIClient.httpDate("Fri, 23 Oct 2026 11:05:00 GMT")
    )
    let snapshot = MarketVolumeHistorySnapshot(
      regionID: 10_000_002,
      historiesByType: [34: beforeRefresh],
      unavailableTypeIDs: [35]
    )
    let sameDay = try #require(ESIClient.httpDate("Sat, 24 Oct 2026 20:00:00 GMT"))
    #expect(snapshot.typeIDsNeedingLoad([34, 35, 36], now: sameDay) == [36])

    let nextDay = try #require(ESIClient.httpDate("Sun, 25 Oct 2026 08:00:00 GMT"))
    #expect(snapshot.typeIDsNeedingLoad([34, 35], now: nextDay) == [34])

    let current = MarketVolumeHistorySnapshot(
      regionID: 10_000_002,
      historiesByType: [34: Self.history([Self.row("2026-10-23", 1)])]
    )
    #expect(current.typeIDsNeedingLoad([34], now: sameDay).isEmpty)
  }

  @Test
  func serviceRequestsOneHistoryPerTypeAndReportsFailuresAsUnavailable() async throws {
    let transport = HistoryTransport(failingTypeIDs: [36])
    let service = TradeHubMarketService(
      esi: ESIClient(transport: transport),
      maximumConcurrentOrderRequests: 6
    )

    let snapshot = try await service.volumeHistory(
      typeIDs: Set((30...41).map(Int64.init)).union([0]),
      regionID: 10_000_043
    )

    #expect(snapshot.regionID == 10_000_043)
    #expect(snapshot.historiesByType.count == 11)
    #expect(snapshot.unavailableTypeIDs == [36])
    #expect(snapshot.historiesByType[34]?.tradedVolume(.oneDay) == 12)
    #expect(snapshot.historiesByType[34]?.anchorDay == Self.day("2026-10-23"))
    #expect(await transport.maximumConcurrentRequests <= 4)
    let urls = await transport.requestedURLs
    #expect(urls.count == 12)
    #expect(
      urls.allSatisfy {
        $0.absoluteString.hasPrefix("https://esi.evetech.net/markets/10000043/history/?")
      }
    )
    #expect(urls.contains { $0.query?.contains("type_id=34") == true })
  }

  @Test
  func historyResponsesArePersistedDurably() {
    #expect(
      ESIClient.persistsDurably(
        path: "/markets/10000002/history/",
        query: [URLQueryItem(name: "type_id", value: "34")],
        partition: "public"
      )
    )
  }

  @Test
  func sorterOrdersVolumeColumnsByTheSelectedWindowWithUnknownLast() {
    let short = Self.history([Self.row("2026-10-23", 50)])
    let long = Self.history([Self.row("2026-10-23", 10), Self.row("2026-10-10", 500)])
    func display(_ id: Int64, _ history: MarketTypeVolumeHistory?) -> TradeDisplayRow {
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: id, profit: 1),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        volumeHistory: history
      )
    }
    let rows = [display(3, nil), display(2, long), display(1, short), display(4, short)]

    #expect(
      TradeRowSorter.sorted(rows, by: .tradedVolume, ascending: false, volumeWindow: .oneDay)
        .map(\.id) == [3, 1, 4, 2]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .tradedVolume, ascending: false, volumeWindow: .thirtyDays)
        .map(\.id) == [3, 2, 1, 4]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .averageDailyVolume, ascending: true, volumeWindow: .oneDay)
        .map(\.id) == [2, 1, 4, 3]
    )
    #expect(
      TradeRowSorter.sorted(
        rows,
        by: .dailyProfitPotential,
        ascending: true,
        volumeWindow: .thirtyDays
      ).map(\.id) == [1, 4, 2, 3]
    )
  }
}

enum TradeCalculatorTestRow {
  static func make(id: Int64, profit: Double?) -> TradeRow {
    TradeRow(
      typeID: id,
      name: "Item \(id)",
      packagedVolume: nil,
      sourcePrice: nil,
      targetPrice: nil,
      differenceFraction: nil,
      purchaseCost: nil,
      transportCost: nil,
      netSale: nil,
      profit: profit,
      margin: nil,
      returnOnInvestment: nil,
      targetSpreadFraction: nil,
      issues: []
    )
  }
}

private actor HistoryTransport: ESIHTTPTransporting {
  let failingTypeIDs: Set<Int64>
  private(set) var requestedURLs: [URL] = []
  private(set) var maximumConcurrentRequests = 0
  private var activeRequests = 0

  init(failingTypeIDs: Set<Int64>) {
    self.failingTypeIDs = failingTypeIDs
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = request.url!
    requestedURLs.append(url)
    activeRequests += 1
    maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
    defer { activeRequests -= 1 }
    try await Task.sleep(for: .milliseconds(10))
    let typeID =
      URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "type_id" }?.value.flatMap(Int64.init) ?? 0
    let failing = failingTypeIDs.contains(typeID)
    let body =
      failing
      ? #"{"error":"Type not found!"}"#
      : #"[{"average":5,"date":"2026-10-23","highest":6,"lowest":4,"order_count":3,"volume":12}]"#
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: url,
        statusCode: failing ? 404 : 200,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Expires": "Sun, 25 Oct 2026 11:05:00 GMT",
          "Last-Modified": "Sat, 24 Oct 2026 11:05:00 GMT",
        ]
      )!
    )
  }
}

@Suite("Hub-exact traded volume")
struct HubTradedVolumeTests {
  private static func day(_ value: String) -> Date {
    MarketTypeVolumeHistory.parseDay(value)!
  }

  private static func demand(
    _ days: [(String, [Int64: Int64])]
  ) -> ManufacturingOpportunityDemandSnapshot {
    ManufacturingOpportunityDemandSnapshot(
      regionID: 10_000_002,
      locationID: 60_003_760,
      utcDay: day("2026-10-24"),
      firstObservedAt: day("2026-10-24"),
      lastObservedAt: day("2026-10-24").addingTimeInterval(3_600),
      sampleCount: 2,
      comparedOrderCount: 1,
      decreasedOrderCount: 1,
      observedUnitsByType: [:],
      dailyHistory: days.map { date, units in
        ManufacturingOpportunityDailyDemandRecord(
          utcDay: day(date),
          observedAt: day(date).addingTimeInterval(3_600),
          estimatedUnitsByType: units,
          sourceSnapshotID: UUID()
        )
      },
      source: SourceIdentity(provider: "fixture", version: "1")
    )
  }

  @Test
  func windowsSumRecordedDaysEndingTodayAndCountCoverage() {
    let snapshot = Self.demand([
      ("2026-10-24", [34: 10]),
      ("2026-10-23", [34: 20, 35: 4]),
      // 2026-10-22 had no scan.
      ("2026-10-21", [34: 30]),
      ("2026-10-10", [34: 100]),
      ("2026-09-20", [34: 9_999]),
    ])
    let now = Self.day("2026-10-24").addingTimeInterval(12 * 3_600)

    let one = snapshot.hubTradedVolume(for: 34, window: .oneDay, now: now)
    #expect(one == HubTradedVolume(units: 10, recordedDays: 1, windowDays: 1))
    #expect(one?.isComplete == true)

    let five = snapshot.hubTradedVolume(for: 34, window: .fiveDays, now: now)
    #expect(five == HubTradedVolume(units: 60, recordedDays: 3, windowDays: 5))
    #expect(five?.isComplete == false)
    #expect(five?.averagePerRecordedDay == 20)

    #expect(
      snapshot.hubTradedVolume(for: 34, window: .thirtyDays, now: now)
        == HubTradedVolume(units: 160, recordedDays: 4, windowDays: 30)
    )
    // A day without a record for the type is unknown, not zero.
    #expect(
      snapshot.hubTradedVolume(for: 35, window: .sevenDays, now: now)
        == HubTradedVolume(units: 4, recordedDays: 1, windowDays: 7)
    )
    #expect(snapshot.hubTradedVolume(for: 36, window: .thirtyDays, now: now) == nil)
    // A later day without any scan leaves the window without records.
    let later = Self.day("2026-10-27")
    #expect(snapshot.hubTradedVolume(for: 34, window: .twoDays, now: later) == nil)
  }

  @Test
  func regionHistoryAsHubVolumeIsCompleteAndKeepsKnownZeros() {
    let history = MarketTypeVolumeHistory.make(
      typeID: 34,
      regionID: 10_000_060,
      rows: [
        ESIMarketHistoryDTO(
          average: 1, date: "2026-10-23", highest: 1, lowest: 1, orderCount: 1, volume: 7),
        ESIMarketHistoryDTO(
          average: 1, date: "2026-10-20", highest: 1, lowest: 1, orderCount: 1, volume: 3),
      ],
      lastModified: nil,
      capturedAt: Self.day("2026-10-24").addingTimeInterval(3_600)
    )
    #expect(
      HubTradedVolume.regionHistory(history, window: .sevenDays)
        == HubTradedVolume(units: 10, recordedDays: 7, windowDays: 7)
    )
    let quiet = HubTradedVolume.regionHistory(history, window: .twoDays)
    #expect(quiet == HubTradedVolume(units: 7, recordedDays: 2, windowDays: 2))
    #expect(quiet.isComplete)
  }

  @Test
  func sorterOrdersHubVolumeByTheSelectedWindowWithUnknownLast() {
    func display(_ id: Int64, _ volumes: [MarketHistoryWindow: HubTradedVolume])
      -> TradeDisplayRow
    {
      TradeDisplayRow(
        row: TradeCalculatorTestRow.make(id: id, profit: 1),
        currentDailyDemand: nil,
        averageDailyDemand: nil,
        hubTradedVolumes: volumes
      )
    }
    let rows = [
      display(3, [:]),
      display(2, [
        .oneDay: HubTradedVolume(units: 5, recordedDays: 1, windowDays: 1),
        .sevenDays: HubTradedVolume(units: 90, recordedDays: 7, windowDays: 7),
      ]),
      display(1, [
        .oneDay: HubTradedVolume(units: 50, recordedDays: 1, windowDays: 1),
        .sevenDays: HubTradedVolume(units: 50, recordedDays: 1, windowDays: 7),
      ]),
    ]
    #expect(
      TradeRowSorter.sorted(rows, by: .hubTradedVolume, ascending: true, volumeWindow: .oneDay)
        .map(\.id) == [2, 1, 3]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .hubTradedVolume, ascending: false, volumeWindow: .sevenDays)
        .map(\.id) == [3, 2, 1]
    )
  }
}
