import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB3 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
struct DashboardNetWorthRangeTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// Day 0 is 1 Nov 2026, 18:00 UTC.
  private func snapshot(
    day: Double,
    total: Double?,
    complete: Bool = true
  ) -> DashboardWealthSnapshot {
    DashboardWealthSnapshot(
      capturedAt: Date(timeIntervalSince1970: 1_793_556_000 + day * 86_400),
      valuationPolicy: "fixture",
      characters: [],
      knownTotalValue: total,
      isComplete: complete,
      freshness: .fresh,
      priceSource: SourceIdentity(provider: "Fixture", version: "1")
    )
  }

  // MARK: Range boundaries

  @Test
  func rangesCountBackFromTheLatestSnapshotIncludingItsDay() {
    let history = (0...100).map { snapshot(day: Double($0), total: Double($0)) }
    func days(_ range: NetWorthHistoryRange) -> [Double] {
      range.filter(history, calendar: calendar).compactMap(\.knownTotalValue)
    }
    #expect(days(.seven) == Array(94...100).map(Double.init))
    #expect(days(.thirty).first == 71)
    #expect(days(.thirty).count == 30)
    #expect(days(.ninety).first == 11)
    #expect(days(.all).count == 101)
  }

  @Test
  func rangeStartKeepsTheTimeOfTheLatestSnapshot() {
    // Six days and one hour before the latest snapshot is outside 7D;
    // exactly six days before is inside.
    let history = [
      snapshot(day: 0, total: 1),
      snapshot(day: 0.95, total: 2),
      snapshot(day: 1, total: 3),
      snapshot(day: 7, total: 4),
    ]
    let filtered = NetWorthHistoryRange.seven.filter(history, calendar: calendar)
    #expect(filtered.compactMap(\.knownTotalValue) == [3, 4])
  }

  @Test
  func emptyHistoryStaysEmpty() {
    for range in NetWorthHistoryRange.allCases {
      #expect(range.filter([], calendar: calendar).isEmpty)
    }
  }

  // MARK: Change inside the range

  @Test
  func changeIsLastMinusFirstKnownTotal() throws {
    let change = try #require(
      NetWorthRangeChange.change(in: [
        snapshot(day: 0, total: 200),
        snapshot(day: 1, total: 120),
        snapshot(day: 2, total: 250),
      ])
    )
    #expect(change.absolute == 50)
    #expect(change.relative == 0.25)
    #expect(!change.comparesKnownComponentsOnly)
    #expect(change.from == snapshot(day: 0, total: 0).capturedAt)
    #expect(change.to == snapshot(day: 2, total: 0).capturedAt)
  }

  @Test
  func oneKnownValueGivesNoChange() {
    #expect(NetWorthRangeChange.change(in: []) == nil)
    #expect(NetWorthRangeChange.change(in: [snapshot(day: 0, total: 10)]) == nil)
    #expect(
      NetWorthRangeChange.change(in: [
        snapshot(day: 0, total: nil),
        snapshot(day: 1, total: 10),
        snapshot(day: 2, total: .nan),
      ]) == nil
    )
  }

  @Test
  func missingTotalsAreSkippedAndIncompleteEndsAreMarked() throws {
    let change = try #require(
      NetWorthRangeChange.change(in: [
        snapshot(day: 0, total: nil),
        snapshot(day: 1, total: 100, complete: false),
        snapshot(day: 2, total: 90),
        snapshot(day: 3, total: nil),
      ])
    )
    #expect(change.absolute == -10)
    #expect(change.relative == -0.1)
    #expect(change.comparesKnownComponentsOnly)
    #expect(change.from == snapshot(day: 1, total: 0).capturedAt)

    // An incomplete snapshot between complete ends does not mark the change.
    let inner = try #require(
      NetWorthRangeChange.change(in: [
        snapshot(day: 0, total: 100),
        snapshot(day: 1, total: 50, complete: false),
        snapshot(day: 2, total: 110),
      ])
    )
    #expect(!inner.comparesKnownComponentsOnly)
  }

  @Test
  func relativeChangeNeedsAPositiveStart() throws {
    let fromZero = try #require(
      NetWorthRangeChange.change(in: [snapshot(day: 0, total: 0), snapshot(day: 1, total: 5)])
    )
    #expect(fromZero.absolute == 5)
    #expect(fromZero.relative == nil)
    let fromNegative = try #require(
      NetWorthRangeChange.change(in: [snapshot(day: 0, total: -5), snapshot(day: 1, total: 5)])
    )
    #expect(fromNegative.relative == nil)
  }
}
