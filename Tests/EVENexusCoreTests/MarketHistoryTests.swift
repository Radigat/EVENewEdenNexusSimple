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
