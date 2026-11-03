@testable import EVENexusCore
import Foundation
import Observation
import Testing

@testable import EVENexusSimpleApp

/// A4/G7 (ANALYSE_2026-11-02): Trade rows are computed once per change of
/// their inputs and reused by every tile; the history progress no longer
/// redraws the tables.
@MainActor
@Suite("Trade row cache", .serialized)
struct TradeRowCacheTests {
  @Test
  func givesTheSameRowsAsComputingThemDirectly() {
    let cache = TradeRowCache()
    let items = Self.items(1...30)

    let firstHalf = cache.rows(
      for: Array(items.prefix(12)),
      sourceSide: .minSell,
      targetSide: .minSell,
      inputs: Self.inputs()
    ) { Self.compute($0, .minSell, .minSell) }
    let all = cache.rows(
      for: items,
      sourceSide: .minSell,
      targetSide: .minSell,
      inputs: Self.inputs()
    ) { Self.compute($0, .minSell, .minSell) }

    #expect(firstHalf == Self.compute(Array(items.prefix(12)), .minSell, .minSell))
    #expect(all == Self.compute(items, .minSell, .minSell))
    // The Top-20 tile over all items computed only the 18 new ones.
    #expect(cache.computedRowCount == 30)
  }

  @Test
  func aRedrawWithTheSameInputsComputesNothing() {
    let cache = TradeRowCache()
    let items = Self.items(1...10)
    var computed = 0
    for _ in 0..<5 {
      _ = cache.rows(
        for: items,
        sourceSide: .maxBuy,
        targetSide: .minSell,
        inputs: Self.inputs()
      ) { missing in
        computed += missing.count
        return Self.compute(missing, .maxBuy, .minSell)
      }
    }
    #expect(computed == 10)
  }

  @Test
  func otherQuoteSidesAreOtherRows() {
    let cache = TradeRowCache()
    let items = Self.items(1...4)
    let sell = cache.rows(
      for: items, sourceSide: .minSell, targetSide: .minSell, inputs: Self.inputs()
    ) { Self.compute($0, .minSell, .minSell) }
    let buy = cache.rows(
      for: items, sourceSide: .minSell, targetSide: .maxBuy, inputs: Self.inputs()
    ) { Self.compute($0, .minSell, .maxBuy) }

    #expect(sell == Self.compute(items, .minSell, .minSell))
    #expect(buy == Self.compute(items, .minSell, .maxBuy))
    #expect(cache.computedRowCount == 8)
  }

  @Test
  func everyInputChangeComputesTheRowsAgain() {
    let base = Self.inputs()
    let source = SourceIdentity(provider: "ESI", version: "fixture", snapshotID: UUID())
    let changes: [TradeRowCache.Inputs] = [
      Self.inputs(mode: .mainToCoalition),
      Self.inputs(sourceMarket: source),
      Self.inputs(sourceCapturedAt: Date(timeIntervalSince1970: 2)),
      Self.inputs(targetMarket: source),
      Self.inputs(targetCapturedAt: Date(timeIntervalSince1970: 2)),
      Self.inputs(sourceFees: TradeHubFees(salesTaxRate: 0.02, brokerFeeRate: 0.01)),
      Self.inputs(targetFees: TradeHubFees(salesTaxRate: 0.02, brokerFeeRate: 0.01)),
      Self.inputs(transport: TradeTransportBasis(legs: [.unavailable(code: "fixture")])),
      Self.inputs(stockRevision: 1),
      Self.inputs(historyRevision: 1),
      Self.inputs(logbookRevision: 1),
      Self.inputs(hubUsesRegion: true),
      Self.inputs(selectedWindow: .thirtyDays),
      Self.inputs(utcDay: Date(timeIntervalSince1970: 86_400)),
    ]
    for changed in changes {
      #expect(changed != base)
      let cache = TradeRowCache()
      let items = Self.items(1...3)
      _ = cache.rows(for: items, sourceSide: .minSell, targetSide: .minSell, inputs: base) {
        Self.compute($0, .minSell, .minSell)
      }
      _ = cache.rows(for: items, sourceSide: .minSell, targetSide: .minSell, inputs: changed) {
        Self.compute($0, .minSell, .minSell)
      }
      #expect(cache.computedRowCount == 6)
    }
  }

  /// The loading flag changes once at the start and once at the end of a
  /// history load, while the progress changes with every type.
  @Test
  func theLoadingFlagChangesOnlyAtStartAndEnd() async throws {
    let fixture = try await GoldenPlannerFixture.make()
    defer { fixture.remove() }
    let runtime = fixture.runtime
    let regionID: Int64 = 10_000_043
    let loading = ObservationCounter()
    let progress = ObservationCounter()
    loading.track { _ = runtime.tradeVolumeHistoryLoadingRegions }
    progress.track { _ = runtime.tradeVolumeHistoryProgress }

    await runtime.refreshTradeVolumeHistory(
      typeIDs: Set((1...12).map { Int64(1_000 + $0) }),
      regionID: regionID
    )
    let deadline = ContinuousClock.now + .seconds(10)
    while runtime.tradeVolumeHistories[regionID] == nil
      || !runtime.tradeVolumeHistoryLoadingRegions.isEmpty
    {
      guard ContinuousClock.now < deadline else { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    try await Task.sleep(for: .milliseconds(50))

    #expect(runtime.tradeVolumeHistories[regionID]?.unavailableTypeIDs.count == 12)
    #expect(runtime.tradeVolumeHistoryLoadingRegions.isEmpty)
    #expect(loading.count == 2)
    #expect(progress.count > loading.count)
  }

  // MARK: Fixtures

  static func items(_ ids: ClosedRange<Int>) -> [TradeCatalogItem] {
    ids.map {
      TradeCatalogItem(
        id: Int64($0),
        name: "Item \($0)",
        marketGroupID: 1,
        packagedVolume: Double($0) / 10
      )
    }
  }

  static func inputs(
    mode: TradeMode = .mainToHome,
    sourceMarket: SourceIdentity? = nil,
    sourceCapturedAt: Date? = Date(timeIntervalSince1970: 1),
    targetMarket: SourceIdentity? = nil,
    targetCapturedAt: Date? = Date(timeIntervalSince1970: 1),
    sourceFees: TradeHubFees = TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.015),
    targetFees: TradeHubFees = TradeHubFees(salesTaxRate: 0.045, brokerFeeRate: 0.02),
    transport: TradeTransportBasis = .none,
    stockRevision: Int = 0,
    historyRevision: Int = 0,
    logbookRevision: Int = 0,
    hubUsesRegion: Bool = false,
    selectedWindow: MarketHistoryWindow = .sevenDays,
    utcDay: Date = Date(timeIntervalSince1970: 0)
  ) -> TradeRowCache.Inputs {
    TradeRowCache.Inputs(
      mode: mode,
      sourceMarket: sourceMarket,
      sourceCapturedAt: sourceCapturedAt,
      targetMarket: targetMarket,
      targetCapturedAt: targetCapturedAt,
      sourceFees: sourceFees,
      targetFees: targetFees,
      transport: transport,
      stockRevision: stockRevision,
      historyRevision: historyRevision,
      logbookRevision: logbookRevision,
      hubUsesRegion: hubUsesRegion,
      selectedWindow: selectedWindow,
      utcDay: utcDay
    )
  }

  /// Rows as the Trade view builds them: the trade calculation plus demand
  /// values, from fixed prices per type.
  static func compute(
    _ items: [TradeCatalogItem],
    _ sourceSide: TradeQuoteSide,
    _ targetSide: TradeQuoteSide
  ) -> [TradeDisplayRow] {
    let inputs = items.map { item in
      TradeItemInput(
        typeID: item.id,
        name: item.name,
        packagedVolume: item.packagedVolume,
        source: MarketOrderTypeSummary(
          bestSellPrice: Double(item.id) * 10,
          bestBuyPrice: Double(item.id) * 9,
          bestSellVolume: 100,
          bestBuyVolume: 50
        ),
        target: MarketOrderTypeSummary(
          bestSellPrice: Double(item.id) * 14,
          bestBuyPrice: Double(item.id) * 12,
          bestSellVolume: 20,
          bestBuyVolume: 10
        )
      )
    }
    return TradeCalculator.rows(
      items: inputs,
      mode: .mainToHome,
      sourceSide: sourceSide,
      targetSide: targetSide,
      sourceFees: TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.015),
      targetFees: TradeHubFees(salesTaxRate: 0.045, brokerFeeRate: 0.02),
      transport: .none
    ).map { row in
      TradeDisplayRow(
        row: row,
        currentDailyDemand: row.typeID % 3 == 0 ? nil : row.typeID,
        averageDailyDemand: row.typeID * 2,
        openLogbookQuantity: row.typeID % 2
      )
    }
  }
}

/// Counts changes of what `read` reads; registers again after every change.
@MainActor
final class ObservationCounter {
  private(set) var count = 0

  func track(_ read: @escaping @MainActor () -> Void) {
    withObservationTracking {
      read()
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.count += 1
        self.track(read)
      }
    }
  }
}
