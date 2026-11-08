import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB5 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
@MainActor
struct DashboardHeaderStatusTests {
  private let base = Date(timeIntervalSince1970: 1_793_556_000)

  private func source(
    _ area: DashboardSourceArea,
    _ status: StartupDataStatus,
    hoursAgo: Double? = nil
  ) -> DashboardSourceStatus {
    DashboardSourceStatus(
      area: area,
      status: status,
      timestamp: hoursAgo.map { base.addingTimeInterval(-$0 * 3_600) }
    )
  }

  // MARK: Summary

  @Test
  func everyFreshSourceGivesFreshWithTheOldestTime() {
    let summary = DashboardStatusProjector.summary([
      source(.characters, .known(.fresh), hoursAgo: 1),
      source(.wallets, .known(.fresh), hoursAgo: 2),
      source(.reactions, .known(.fresh), hoursAgo: 5),
      source(.netWorth, .known(.fresh)),
    ])
    #expect(summary.status == .known(.fresh))
    #expect(summary.oldestTimestamp == base.addingTimeInterval(-5 * 3_600))
    #expect(summary.sources.count == 4)
  }

  @Test
  func runningWinsOverEveryKnownState() {
    let summary = DashboardStatusProjector.summary([
      source(.characters, .known(.unavailable)),
      source(.minerals, .running),
    ])
    #expect(summary.status == .running)
  }

  @Test
  func mixedStatesCombineLikeTheStartupStatus() {
    #expect(
      DashboardStatusProjector.summary([
        source(.characters, .known(.fresh)),
        source(.moonMaterials, .known(.stale)),
      ]).status == .known(.stale)
    )
    #expect(
      DashboardStatusProjector.summary([
        source(.characters, .known(.fresh)),
        source(.wallets, .known(.forbidden)),
      ]).status == .known(.partial)
    )
    #expect(
      DashboardStatusProjector.summary([
        source(.characters, .known(.forbidden)),
        source(.wallets, .known(.unavailable)),
      ]).status == .known(.unavailable)
    )
  }

  @Test
  func waitingSourcesCountAsMissingUnlessAllWait() {
    #expect(
      DashboardStatusProjector.summary([
        source(.characters, .known(.fresh)),
        source(.reactions, .waiting),
      ]).status == .known(.partial)
    )
    #expect(
      DashboardStatusProjector.summary([
        source(.reactions, .waiting),
        source(.minerals, .waiting),
      ]).status == .waiting
    )
    let empty = DashboardStatusProjector.summary([])
    #expect(empty.status == .waiting)
    #expect(empty.oldestTimestamp == nil)
  }

  // MARK: Sources

  @Test
  func charactersUseTheRefreshAndTheOldestSync() {
    let dates: [Date?] = [base, base.addingTimeInterval(-7_200), nil]
    let refreshing = DashboardStatusProjector.characters(
      phase: .completed,
      isRefreshing: true,
      result: nil,
      lastSyncDates: dates
    )
    #expect(refreshing.status == .running)
    #expect(refreshing.timestamp == base.addingTimeInterval(-7_200))
    let failed = DashboardStatusProjector.characters(
      phase: .completed,
      isRefreshing: false,
      result: CharacterBatchSyncResult(
        synchronizedCount: 1,
        totalCount: 2,
        failedCharacterNames: ["Pilot B"]
      ),
      lastSyncDates: dates
    )
    #expect(failed.status == .known(.partial))
  }

  @Test
  func walletsWithoutCharactersAreUnavailable() {
    #expect(
      DashboardStatusProjector.wallets(
        freshness: .fresh, characterCount: 0, isRefreshing: false, lastSyncDates: []
      ).status == .known(.unavailable)
    )
    let wallets = DashboardStatusProjector.wallets(
      freshness: .partial,
      characterCount: 2,
      isRefreshing: false,
      lastSyncDates: [base, base.addingTimeInterval(-60)]
    )
    #expect(wallets.status == .known(.partial))
    #expect(wallets.timestamp == base.addingTimeInterval(-60))
    #expect(
      DashboardStatusProjector.wallets(
        freshness: .fresh, characterCount: 1, isRefreshing: true, lastSyncDates: []
      ).status == .running
    )
  }

  @Test
  func netWorthKeepsMissingAndFailedValuationsExplicit() {
    let snapshot = DashboardWealthSnapshot(
      capturedAt: base,
      valuationPolicy: "fixture",
      characters: [],
      knownTotalValue: 1,
      isComplete: false,
      freshness: .fresh,
      priceSource: SourceIdentity(provider: "Fixture", version: "1")
    )
    #expect(
      DashboardStatusProjector.netWorth(snapshot: nil, isRefreshing: false, hasError: false)
        .status == .known(.unavailable)
    )
    let partial = DashboardStatusProjector.netWorth(
      snapshot: snapshot, isRefreshing: false, hasError: false
    )
    #expect(partial.status == .known(.partial))
    #expect(partial.timestamp == base)
    #expect(
      DashboardStatusProjector.netWorth(snapshot: snapshot, isRefreshing: false, hasError: true)
        .status == .known(.stale)
    )
    #expect(
      DashboardStatusProjector.netWorth(snapshot: nil, isRefreshing: true, hasError: false)
        .status == .running
    )
  }

  @Test
  func analysisRowsMapOnlyTheThreeAnalyses() {
    let reactions = StartupDataStatusRow(
      area: .reactions, status: .known(.fresh), timestamp: base
    )
    #expect(DashboardStatusProjector.analysis(reactions)?.area == .reactions)
    let warehouse = StartupDataStatusRow(
      area: .warehouseAndBlueprints, status: .known(.fresh), timestamp: base
    )
    #expect(DashboardStatusProjector.analysis(warehouse) == nil)
  }
}
