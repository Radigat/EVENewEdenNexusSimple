import Foundation

/// Rolling windows of the regional ESI market history (owner decision
/// 2026-10-24: 1, 2, 5, 7 and 30 days).
public enum MarketHistoryWindow: Int, CaseIterable, Identifiable, Sendable {
  case oneDay = 1
  case twoDays = 2
  case fiveDays = 5
  case sevenDays = 7
  case thirtyDays = 30

  public var id: Int { rawValue }
  public var days: Int { rawValue }
}

/// Daily traded units of one type in one region from
/// `GET /markets/{region_id}/history/`. ESI reports the total of both order
/// sides per UTC day and omits days without trades, so a day inside the
/// window without an entry is a known zero. ESI does not split the volume
/// into buy and sell side; this model never estimates such a split.
public struct MarketTypeVolumeHistory: Equatable, Sendable {
  public let typeID: Int64
  public let regionID: Int64
  /// UTC midnight of the newest day the history covers. Windows end here.
  public let anchorDay: Date
  /// Traded units keyed by UTC midnight of the day.
  public let dailyVolumes: [Date: Int64]
  public let capturedAt: Date

  public init(
    typeID: Int64,
    regionID: Int64,
    anchorDay: Date,
    dailyVolumes: [Date: Int64],
    capturedAt: Date
  ) {
    self.typeID = typeID
    self.regionID = regionID
    self.anchorDay = Self.utcDay(anchorDay)
    self.dailyVolumes = dailyVolumes
    self.capturedAt = capturedAt
  }

  /// Units traded in the `window.days` UTC days ending with `anchorDay`.
  public func tradedVolume(_ window: MarketHistoryWindow) -> Int64 {
    let earliest = Self.utcCalendar.date(
      byAdding: .day,
      value: -(window.days - 1),
      to: anchorDay
    ) ?? anchorDay
    return dailyVolumes.reduce(into: Int64(0)) { total, entry in
      if entry.key >= earliest, entry.key <= anchorDay {
        total += entry.value
      }
    }
  }

  /// `tradedVolume(window) ÷ window.days`.
  public func averageDailyVolume(_ window: MarketHistoryWindow) -> Double {
    Double(tradedVolume(window)) / Double(window.days)
  }

  /// Builds the history from ESI rows. The anchor is the UTC day before the
  /// UTC date of `Last-Modified` (the history is refreshed once a day and
  /// then contains the previous day); without the header it is the UTC day
  /// before `capturedAt`; a reported day after that anchor moves it forward.
  /// Rows with an unreadable date or a negative volume are dropped.
  public static func make(
    typeID: Int64,
    regionID: Int64,
    rows: [ESIMarketHistoryDTO],
    lastModified: Date?,
    capturedAt: Date
  ) -> MarketTypeVolumeHistory {
    let reference = utcDay(lastModified ?? capturedAt)
    let expectedAnchor =
      utcCalendar.date(byAdding: .day, value: -1, to: reference) ?? reference
    var volumes: [Date: Int64] = [:]
    for row in rows where row.volume >= 0 {
      guard let day = parseDay(row.date) else { continue }
      volumes[day, default: 0] += row.volume
    }
    // A reported day newer than the expected anchor is never cut off.
    let anchor = max(expectedAnchor, volumes.keys.max() ?? expectedAnchor)
    return MarketTypeVolumeHistory(
      typeID: typeID,
      regionID: regionID,
      anchorDay: anchor,
      dailyVolumes: volumes,
      capturedAt: capturedAt
    )
  }

  static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  public static func utcDay(_ date: Date) -> Date {
    utcCalendar.startOfDay(for: date)
  }

  public static func utcDay(_ date: Date, addingDays days: Int) -> Date {
    let day = utcDay(date)
    return utcCalendar.date(byAdding: .day, value: days, to: day) ?? day
  }

  static func parseDay(_ value: String) -> Date? {
    let parts = value.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    let components = DateComponents(year: year, month: month, day: day)
    guard components.isValidDate(in: utcCalendar) else { return nil }
    return utcCalendar.date(from: components)
  }
}

/// Volume histories of several types in one region. Types whose request
/// failed are listed in `unavailableTypeIDs`; they are unknown, not zero.
public struct MarketVolumeHistorySnapshot: Equatable, Sendable {
  public let regionID: Int64
  public var historiesByType: [Int64: MarketTypeVolumeHistory]
  public var unavailableTypeIDs: Set<Int64>

  public init(
    regionID: Int64,
    historiesByType: [Int64: MarketTypeVolumeHistory] = [:],
    unavailableTypeIDs: Set<Int64> = []
  ) {
    self.regionID = regionID
    self.historiesByType = historiesByType
    self.unavailableTypeIDs = unavailableTypeIDs
  }

  /// The subset of `typeIDs` this snapshot does not cover for the current
  /// UTC day. A history is current when it already reaches yesterday (the
  /// newest day ESI can report) or was captured today, so a history loaded
  /// before the daily ESI refresh is not requested again the same day. A
  /// type whose request failed stays unavailable for the snapshot's
  /// lifetime instead of being retried; ESI remembers that failure for a day.
  public func typeIDsNeedingLoad(
    _ typeIDs: Set<Int64>,
    now: Date = .now
  ) -> Set<Int64> {
    let today = MarketTypeVolumeHistory.utcDay(now)
    let expectedAnchor = MarketTypeVolumeHistory.utcDay(now, addingDays: -1)
    return typeIDs.filter { typeID in
      guard let history = historiesByType[typeID] else {
        return !unavailableTypeIDs.contains(typeID)
      }
      return history.anchorDay < expectedAnchor && history.capturedAt < today
    }
  }

  /// Adds `other`; newer results replace older ones per type, and a type
  /// that loaded is no longer unavailable.
  public mutating func merge(_ other: MarketVolumeHistorySnapshot) {
    guard other.regionID == regionID else { return }
    for (typeID, history) in other.historiesByType {
      historiesByType[typeID] = history
      unavailableTypeIDs.remove(typeID)
    }
    for typeID in other.unavailableTypeIDs
    where historiesByType[typeID] == nil {
      unavailableTypeIDs.insert(typeID)
    }
  }
}

/// Units traded at the exact target hub during a window, from the daily
/// records of the hub's demand ledger (one rolling 24-hour lower-bound
/// estimate per UTC day with a scan). Days without a record are unknown,
/// not zero, so the sum covers only `recordedDays` of `windowDays`.
public struct HubTradedVolume: Equatable, Sendable {
  public let units: Int64
  public let recordedDays: Int
  public let windowDays: Int
  /// Market stock history only: partial fills plus vanished orders (traded,
  /// cancelled or expired), an upper bound for `units`.
  public let upperBoundUnits: Int64?
  /// Market stock history only: recorded days whose sums cover only part of
  /// the day (first point, gap).
  public let partialDays: Int

  public init(
    units: Int64,
    recordedDays: Int,
    windowDays: Int,
    upperBoundUnits: Int64? = nil,
    partialDays: Int = 0
  ) {
    self.units = units
    self.recordedDays = recordedDays
    self.windowDays = windowDays
    self.upperBoundUnits = upperBoundUnits
    self.partialDays = partialDays
  }

  /// Every day of the window has a complete record.
  public var isComplete: Bool { recordedDays >= windowDays && partialDays == 0 }

  /// `units ÷ recordedDays`.
  public var averagePerRecordedDay: Double {
    Double(units) / Double(max(recordedDays, 1))
  }
}

extension HubTradedVolume {
  /// The regional ESI history as the hub's volume, for a hub the owner marked
  /// as the only market of its region. ESI reports every day of the window
  /// (days without trades are known zeros), so the window is complete.
  public static func regionHistory(
    _ history: MarketTypeVolumeHistory,
    window: MarketHistoryWindow
  ) -> HubTradedVolume {
    HubTradedVolume(
      units: history.tradedVolume(window),
      recordedDays: window.days,
      windowDays: window.days
    )
  }
}

extension ManufacturingOpportunityDemandSnapshot {
  /// Hub-exact traded units of `typeID` in the `window.days` UTC days ending
  /// with the UTC day of `now`; `nil` when no day of the window has a record
  /// for this type.
  public func hubTradedVolume(
    for typeID: Int64,
    window: MarketHistoryWindow,
    now: Date = .now
  ) -> HubTradedVolume? {
    let lastDay = MarketTypeVolumeHistory.utcDay(now)
    let firstDay = MarketTypeVolumeHistory.utcDay(now, addingDays: -(window.days - 1))
    var unitsByDay: [Date: Int64] = [:]
    for record in dailyHistory ?? [] {
      let day = MarketTypeVolumeHistory.utcDay(record.utcDay)
      guard day >= firstDay, day <= lastDay,
        let units = record.estimatedUnits(for: typeID), units >= 0
      else { continue }
      unitsByDay[day] = units
    }
    guard !unitsByDay.isEmpty else { return nil }
    return HubTradedVolume(
      units: unitsByDay.values.reduce(0, +),
      recordedDays: unitsByDay.count,
      windowDays: window.days
    )
  }
}

/// Sell-side stock change at a hub during a window (MARKTBESTAND_PLAN C4).
public struct MarketStockNetChange: Equatable, Sendable {
  /// Sums of the known deltas of the window.
  public let sell: MarketStockSideDelta
  public let recordedDays: Int
  public let partialDays: Int
  public let windowDays: Int

  public init(
    sell: MarketStockSideDelta,
    recordedDays: Int,
    partialDays: Int,
    windowDays: Int
  ) {
    self.sell = sell
    self.recordedDays = recordedDays
    self.partialDays = partialDays
    self.windowDays = windowDays
  }

  /// Units listed now minus units listed at the window start.
  public var net: Int64 { sell.net }

  public var isComplete: Bool { recordedDays >= windowDays && partialDays == 0 }
}

extension MarketStockHubOverview {
  /// Coverage of `window`, when the overview was built for it.
  public func coverage(for window: MarketHistoryWindow) -> MarketStockWindowCoverage? {
    coverage.first { $0.days == window.days }
  }

  /// Stock of the latest point; a known 0 for an item not listed then.
  /// `nil` without any stored point of this hub.
  public func currentStock(for typeID: Int64) -> MarketStockItemValue? {
    guard latestCapturedAt != nil else { return nil }
    return itemsByType[typeID]?.current
      ?? MarketStockItemValue(typeID: typeID, sell: .empty, buy: .empty)
  }

  /// Sell-side partial fills of `typeID` during `window` (C4): surely traded
  /// units, with the total of partial fills and vanished orders as upper
  /// bound. `nil` while no day of the window has a known delta; an item
  /// without changes then is a known 0.
  public func hubTradedVolume(
    for typeID: Int64,
    window: MarketHistoryWindow
  ) -> HubTradedVolume? {
    guard let (sell, coverage) = knownSellTotals(for: typeID, window: window)
    else { return nil }
    return HubTradedVolume(
      units: sell.partiallyFilled,
      recordedDays: coverage.daysWithKnownDelta,
      windowDays: window.days,
      upperBoundUnits: sell.removed,
      partialDays: coverage.daysWithUnknownDelta
    )
  }

  /// Sell-side added, partially filled, vanished and net units during
  /// `window`; `nil` while no day of the window has a known delta.
  public func netChange(
    for typeID: Int64,
    window: MarketHistoryWindow
  ) -> MarketStockNetChange? {
    guard let (sell, coverage) = knownSellTotals(for: typeID, window: window)
    else { return nil }
    return MarketStockNetChange(
      sell: sell,
      recordedDays: coverage.daysWithKnownDelta,
      partialDays: coverage.daysWithUnknownDelta,
      windowDays: window.days
    )
  }

  private func knownSellTotals(
    for typeID: Int64,
    window: MarketHistoryWindow
  ) -> (MarketStockSideDelta, MarketStockWindowCoverage)? {
    guard latestCapturedAt != nil,
      let index = coverage.firstIndex(where: { $0.days == window.days }),
      coverage[index].daysWithKnownDelta > 0
    else { return nil }
    let totals = itemsByType[typeID]?.totals
    let sell = totals.flatMap { $0.indices.contains(index) ? $0[index].sell : nil }
    return (sell ?? .zero, coverage[index])
  }
}
