import Foundation

// Market stock history core (MARKTBESTAND_PLAN.md, C1/C2/C7). A stock point
// is the listed quantity per item of one complete exact-hub order book; the
// delta between two points is derived from order-level changes. Pure
// calculation: no storage, no network.

/// Listed quantity of one market side for one item.
public struct MarketStockSideValue: Codable, Equatable, Sendable {
  public let units: Int64
  public let orderCount: Int
  /// Lowest sell or highest buy price; `nil` without an order on this side.
  public let bestPrice: Double?

  public init(units: Int64, orderCount: Int, bestPrice: Double?) {
    self.units = units
    self.orderCount = orderCount
    self.bestPrice = bestPrice
  }

  /// No order on this side. In a complete order book this is a known 0.
  public static let empty = MarketStockSideValue(
    units: 0,
    orderCount: 0,
    bestPrice: nil
  )
}

public struct MarketStockItemValue: Codable, Equatable, Sendable {
  public let typeID: Int64
  public let sell: MarketStockSideValue
  public let buy: MarketStockSideValue

  public init(
    typeID: Int64,
    sell: MarketStockSideValue,
    buy: MarketStockSideValue
  ) {
    self.typeID = typeID
    self.sell = sell
    self.buy = buy
  }
}

/// Stock of every item listed at one exact hub at one moment (C1).
public struct MarketStockPoint: Codable, Equatable, Sendable {
  public let regionID: Int64
  public let locationID: Int64
  public let capturedAt: Date
  public let sourceSnapshotID: UUID
  /// Only items with at least one valid order at the hub.
  public let itemsByType: [Int64: MarketStockItemValue]

  public init(
    regionID: Int64,
    locationID: Int64,
    capturedAt: Date,
    sourceSnapshotID: UUID,
    itemsByType: [Int64: MarketStockItemValue]
  ) {
    self.regionID = regionID
    self.locationID = locationID
    self.capturedAt = capturedAt
    self.sourceSnapshotID = sourceSnapshotID
    self.itemsByType = itemsByType
  }

  /// The order book is complete, so an item without a row is a known 0.
  public func value(for typeID: Int64) -> MarketStockItemValue {
    itemsByType[typeID]
      ?? MarketStockItemValue(typeID: typeID, sell: .empty, buy: .empty)
  }
}

/// One valid order of the compact baseline (fixed-size integers only).
public struct MarketStockOrderEntry: Codable, Equatable, Sendable {
  public let orderID: Int64
  public let typeID: Int64
  public let volumeRemaining: Int64
  public let isBuy: Bool

  public init(
    orderID: Int64,
    typeID: Int64,
    volumeRemaining: Int64,
    isBuy: Bool
  ) {
    self.orderID = orderID
    self.typeID = typeID
    self.volumeRemaining = volumeRemaining
    self.isBuy = isBuy
  }
}

/// Compact order list of one point, sorted by order ID with unique IDs, so
/// two baselines are compared in one merge pass without a dictionary (C7).
public struct MarketStockOrderBaseline: Codable, Equatable, Sendable {
  public let regionID: Int64
  public let locationID: Int64
  public let capturedAt: Date
  public let entries: [MarketStockOrderEntry]

  public init(
    regionID: Int64,
    locationID: Int64,
    capturedAt: Date,
    entries: [MarketStockOrderEntry]
  ) {
    self.regionID = regionID
    self.locationID = locationID
    self.capturedAt = capturedAt
    self.entries = entries
  }
}

public struct MarketStockObservation: Equatable, Sendable {
  public let point: MarketStockPoint
  public let baseline: MarketStockOrderBaseline
}

/// Order-level change of one market side between two points (C2).
public struct MarketStockSideDelta: Codable, Equatable, Sendable {
  /// Volume of new orders plus volume increases of listed orders.
  public let added: Int64
  /// Volume decrease of orders that are still listed: surely traded.
  public let partiallyFilled: Int64
  /// Remaining volume of orders that are no longer listed: traded,
  /// cancelled or expired, which ESI does not distinguish.
  public let vanished: Int64

  public init(added: Int64, partiallyFilled: Int64, vanished: Int64) {
    self.added = added
    self.partiallyFilled = partiallyFilled
    self.vanished = vanished
  }

  public static let zero = MarketStockSideDelta(
    added: 0,
    partiallyFilled: 0,
    vanished: 0
  )

  public var removed: Int64 {
    MarketStockMath.saturatedAdd(partiallyFilled, vanished)
  }

  /// Units now minus units before.
  public var net: Int64 {
    MarketStockMath.saturatedSubtract(added, removed)
  }
}

public struct MarketStockItemDelta: Codable, Equatable, Sendable {
  public let typeID: Int64
  public let sell: MarketStockSideDelta
  public let buy: MarketStockSideDelta

  public init(
    typeID: Int64,
    sell: MarketStockSideDelta,
    buy: MarketStockSideDelta
  ) {
    self.typeID = typeID
    self.sell = sell
    self.buy = buy
  }
}

public enum MarketStockDeltaUnavailableReason: String, Codable, Equatable,
  Sendable
{
  /// No earlier point of this hub.
  case noPreviousPoint
  /// Region or exact location differs from the earlier point.
  case locationChanged
  /// The earlier point is not older than the current one.
  case notChronological
  /// The points are further apart than the accepted gap.
  case gapTooLarge
}

public enum MarketStockDeltaResult: Equatable, Sendable {
  /// Only items with a change; a missing item changed by a known 0.
  case compared(
    previousCapturedAt: Date,
    deltasByType: [Int64: MarketStockItemDelta]
  )
  /// The delta is unknown, never 0.
  case unavailable(MarketStockDeltaUnavailableReason)
}

public enum MarketStockHistoryCalculator {
  /// Owner decision 29.10.2026: two points more than 72 hours apart give an
  /// unknown delta; the stock of each point stays known.
  public static let maximumComparisonGap: TimeInterval = 72 * 60 * 60

  /// Builds a point and its baseline from a complete exact-hub order book in
  /// one pass over the orders (C7). A book that is not `fresh` (partial,
  /// stale, forbidden, unavailable) gives `nil`: no point is written.
  /// Orders at another location or with an invalid price or no remaining
  /// volume are ignored, like in the demand ledger. A duplicated order ID
  /// (overlapping ESI pages) counts once.
  public static func observe(
    _ market: MarketOrderSnapshot
  ) -> MarketStockObservation? {
    observe(market, cancellationCheck: {})
  }

  public static func observe(
    _ market: MarketOrderSnapshot,
    cancellationCheck: () throws -> Void
  ) rethrows -> MarketStockObservation? {
    guard market.state == .fresh else { return nil }
    try cancellationCheck()
    var entries: [MarketStockOrderEntry] = []
    var prices: [Double] = []
    let capacity = market.ordersByType.values.reduce(0) { $0 + $1.count }
    entries.reserveCapacity(capacity)
    prices.reserveCapacity(capacity)
    var processed = 0
    for orders in market.ordersByType.values {
      for order in orders {
        processed += 1
        if processed.isMultiple(of: 4_096) { try cancellationCheck() }
        guard order.locationID == market.locationID,
          order.price.isFinite,
          order.price > 0,
          order.volumeRemaining > 0
        else { continue }
        entries.append(
          MarketStockOrderEntry(
            orderID: order.id,
            typeID: order.typeID,
            volumeRemaining: order.volumeRemaining,
            isBuy: order.side == .buy
          )
        )
        prices.append(order.price)
      }
    }
    try cancellationCheck()

    // Sort an index permutation so the price stays with its order without a
    // second order copy; ties keep the first occurrence.
    var order = Array(entries.indices)
    order.sort {
      entries[$0].orderID != entries[$1].orderID
        ? entries[$0].orderID < entries[$1].orderID : $0 < $1
    }
    try cancellationCheck()

    struct SideAccumulator {
      var units: Int64 = 0
      var count = 0
      var best: Double?
    }
    var sellByType: [Int64: SideAccumulator] = [:]
    var buyByType: [Int64: SideAccumulator] = [:]
    var sorted: [MarketStockOrderEntry] = []
    sorted.reserveCapacity(entries.count)
    var previousID: Int64?
    for index in order {
      let entry = entries[index]
      if entry.orderID == previousID { continue }
      previousID = entry.orderID
      sorted.append(entry)
      let price = prices[index]
      if entry.isBuy {
        var side = buyByType[entry.typeID, default: SideAccumulator()]
        side.units = MarketStockMath.saturatedAdd(side.units, entry.volumeRemaining)
        side.count += 1
        side.best = side.best.map { max($0, price) } ?? price
        buyByType[entry.typeID] = side
      } else {
        var side = sellByType[entry.typeID, default: SideAccumulator()]
        side.units = MarketStockMath.saturatedAdd(side.units, entry.volumeRemaining)
        side.count += 1
        side.best = side.best.map { min($0, price) } ?? price
        sellByType[entry.typeID] = side
      }
    }
    try cancellationCheck()

    func value(_ side: SideAccumulator?) -> MarketStockSideValue {
      guard let side else { return .empty }
      return MarketStockSideValue(
        units: side.units,
        orderCount: side.count,
        bestPrice: side.best
      )
    }
    var items: [Int64: MarketStockItemValue] = [:]
    items.reserveCapacity(max(sellByType.count, buyByType.count))
    for typeID in Set(sellByType.keys).union(buyByType.keys) {
      items[typeID] = MarketStockItemValue(
        typeID: typeID,
        sell: value(sellByType[typeID]),
        buy: value(buyByType[typeID])
      )
    }
    return MarketStockObservation(
      point: MarketStockPoint(
        regionID: market.regionID,
        locationID: market.locationID,
        capturedAt: market.capturedAt,
        sourceSnapshotID: market.source.snapshotID,
        itemsByType: items
      ),
      baseline: MarketStockOrderBaseline(
        regionID: market.regionID,
        locationID: market.locationID,
        capturedAt: market.capturedAt,
        entries: sorted
      )
    )
  }

  /// Order-level delta between the previous and the current baseline of the
  /// same hub (C2), in one merge pass over both sorted lists.
  public static func compare(
    previous: MarketStockOrderBaseline?,
    current: MarketStockOrderBaseline,
    maximumGap: TimeInterval = maximumComparisonGap
  ) -> MarketStockDeltaResult {
    compare(
      previous: previous,
      current: current,
      maximumGap: maximumGap,
      cancellationCheck: {}
    )
  }

  public static func compare(
    previous: MarketStockOrderBaseline?,
    current: MarketStockOrderBaseline,
    maximumGap: TimeInterval = maximumComparisonGap,
    cancellationCheck: () throws -> Void
  ) rethrows -> MarketStockDeltaResult {
    guard let previous else { return .unavailable(.noPreviousPoint) }
    guard previous.regionID == current.regionID,
      previous.locationID == current.locationID
    else { return .unavailable(.locationChanged) }
    let gap = current.capturedAt.timeIntervalSince(previous.capturedAt)
    guard gap > 0 else { return .unavailable(.notChronological) }
    guard gap <= maximumGap else { return .unavailable(.gapTooLarge) }

    struct SideAccumulator {
      var added: Int64 = 0
      var partiallyFilled: Int64 = 0
      var vanished: Int64 = 0
      var isZero: Bool { added == 0 && partiallyFilled == 0 && vanished == 0 }
    }
    var sell: [Int64: SideAccumulator] = [:]
    var buy: [Int64: SideAccumulator] = [:]
    func add(
      _ entry: MarketStockOrderEntry,
      _ update: (inout SideAccumulator) -> Void
    ) {
      if entry.isBuy {
        update(&buy[entry.typeID, default: SideAccumulator()])
      } else {
        update(&sell[entry.typeID, default: SideAccumulator()])
      }
    }
    func vanish(_ entry: MarketStockOrderEntry) {
      add(entry) {
        $0.vanished = MarketStockMath.saturatedAdd($0.vanished, entry.volumeRemaining)
      }
    }
    func appear(_ entry: MarketStockOrderEntry) {
      add(entry) {
        $0.added = MarketStockMath.saturatedAdd($0.added, entry.volumeRemaining)
      }
    }

    let old = previous.entries
    let new = current.entries
    var oldIndex = 0
    var newIndex = 0
    var steps = 0
    while oldIndex < old.count || newIndex < new.count {
      steps += 1
      if steps.isMultiple(of: 4_096) { try cancellationCheck() }
      if newIndex == new.count
        || oldIndex < old.count && old[oldIndex].orderID < new[newIndex].orderID
      {
        vanish(old[oldIndex])
        oldIndex += 1
      } else if oldIndex == old.count
        || new[newIndex].orderID < old[oldIndex].orderID
      {
        appear(new[newIndex])
        newIndex += 1
      } else {
        let before = old[oldIndex]
        let after = new[newIndex]
        oldIndex += 1
        newIndex += 1
        // ESI order IDs are unique; a changed item or side is treated as a
        // replaced order so units now minus units before stays exact.
        guard before.typeID == after.typeID, before.isBuy == after.isBuy
        else {
          vanish(before)
          appear(after)
          continue
        }
        if after.volumeRemaining < before.volumeRemaining {
          let filled = before.volumeRemaining - after.volumeRemaining
          add(after) {
            $0.partiallyFilled = MarketStockMath.saturatedAdd($0.partiallyFilled, filled)
          }
        } else if after.volumeRemaining > before.volumeRemaining {
          let raised = after.volumeRemaining - before.volumeRemaining
          add(after) {
            $0.added = MarketStockMath.saturatedAdd($0.added, raised)
          }
        }
      }
    }
    try cancellationCheck()

    func delta(_ side: SideAccumulator?) -> MarketStockSideDelta {
      guard let side else { return .zero }
      return MarketStockSideDelta(
        added: side.added,
        partiallyFilled: side.partiallyFilled,
        vanished: side.vanished
      )
    }
    var deltas: [Int64: MarketStockItemDelta] = [:]
    for typeID in Set(sell.keys).union(buy.keys) {
      let sellSide = sell[typeID]
      let buySide = buy[typeID]
      guard sellSide?.isZero == false || buySide?.isZero == false else {
        continue
      }
      deltas[typeID] = MarketStockItemDelta(
        typeID: typeID,
        sell: delta(sellSide),
        buy: delta(buySide)
      )
    }
    return .compared(
      previousCapturedAt: previous.capturedAt,
      deltasByType: deltas
    )
  }
}

/// What the item chart plots (MARKTBESTAND_PLAN E2).
public enum MarketStockChartMetric: String, CaseIterable, Identifiable, Sendable {
  case sellUnits
  case buyUnits
  case sellPrice

  public var id: Self { self }

  public func value(_ item: MarketStockItemValue) -> Double? {
    switch self {
    case .sellUnits: Double(item.sell.units)
    case .buyUnits: Double(item.buy.units)
    case .sellPrice: item.sell.bestPrice
    }
  }
}

public struct MarketStockChartSample: Equatable, Sendable {
  public let date: Date
  public let value: Double
  /// Consecutive samples of one segment are joined; a new segment starts
  /// after a gap, so a gap is never drawn as a line or as 0.
  public let segment: Int
  /// A daily value (older than the single-point window) or a single point.
  public let isDailyValue: Bool
}

public enum MarketStockChartBuilder {
  /// Daily values before `fineWindowStart`, single points from it on. A
  /// UTC day without a point between two samples, or a missing value (for
  /// example no sell order for a price), starts a new segment.
  public static func samples(
    days: [MarketStockDailyEntry],
    points: [MarketStockPointEntry],
    metric: MarketStockChartMetric,
    fineWindowStart: Date
  ) -> [MarketStockChartSample] {
    let fineStartDay = MarketStockHistoryStore.utcDay(containing: fineWindowStart)
    var raw: [(date: Date, value: Double?, isDaily: Bool)] = []
    for entry in days
    where MarketStockHistoryStore.utcDay(containing: entry.day) < fineStartDay {
      guard let recorded = entry.recorded else { continue }
      raw.append((recorded.lastPointAt, metric.value(recorded.value), true))
    }
    for point in points where point.capturedAt >= fineWindowStart {
      raw.append((point.capturedAt, metric.value(point.value), false))
    }
    raw.sort { $0.date < $1.date }
    var samples: [MarketStockChartSample] = []
    var segment = 0
    var previousDay: Int64?
    var previousWasGap = false
    for entry in raw {
      let day = MarketStockHistoryStore.utcDay(containing: entry.date)
      guard let value = entry.value else {
        previousWasGap = true
        continue
      }
      if let previousDay, previousWasGap || day - previousDay > 1 {
        segment += 1
      }
      samples.append(
        MarketStockChartSample(
          date: entry.date,
          value: value,
          segment: segment,
          isDailyValue: entry.isDaily
        )
      )
      previousDay = day
      previousWasGap = false
    }
    return samples
  }
}

/// One row of the item's daily table (E2); `nil` values are unknown.
public struct MarketStockDayRow: Identifiable, Equatable, Sendable {
  public var id: Date { day }
  public let day: Date
  public let sellUnits: Int64?
  public let added: Int64?
  public let partiallyFilled: Int64?
  public let vanished: Int64?
  public let net: Int64?
  /// The day has a point whose delta to its predecessor is unknown; its
  /// sums cover only part of the day.
  public let isPartial: Bool

  public init(_ entry: MarketStockDailyEntry) {
    day = entry.day
    isPartial = (entry.recorded?.unknownDeltaCount ?? 0) > 0
    sellUnits = entry.recorded?.value.sell.units
    let sell = entry.recorded?.sell
    added = sell?.added
    partiallyFilled = sell?.partiallyFilled
    vanished = sell?.vanished
    net = sell?.net
  }

  public enum Column: String, CaseIterable, Hashable, Sendable {
    case day
    case sellUnits
    case added
    case partiallyFilled
    case vanished
    case net
  }

  public func value(_ column: Column) -> Double? {
    switch column {
    case .day: day.timeIntervalSince1970
    case .sellUnits: sellUnits.map(Double.init)
    case .added: added.map(Double.init)
    case .partiallyFilled: partiallyFilled.map(Double.init)
    case .vanished: vanished.map(Double.init)
    case .net: net.map(Double.init)
    }
  }

  /// Typed order; unknown values follow known ones ascending and precede
  /// them descending; the day breaks ties.
  public static func sorted(
    _ rows: [MarketStockDayRow],
    by column: Column,
    ascending: Bool
  ) -> [MarketStockDayRow] {
    rows.sorted { lhs, rhs in
      switch (lhs.value(column), rhs.value(column)) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return ascending
      case (nil, .some):
        return !ascending
      case (nil, nil):
        break
      }
      return lhs.day < rhs.day
    }
  }
}

/// One item of the "Market stock" view (MARKTBESTAND_PLAN P7).
public struct MarketStockOverviewRow: Identifiable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  /// `nil` while the active SDE does not resolve the type.
  public let name: String?
  public let current: MarketStockItemValue
  /// Sell-side net and removed units per window length in days; a missing
  /// window has no known delta and is unknown, never 0.
  public let netByWindow: [Int: Int64]
  public let removedByWindow: [Int: Int64]

  public init(
    typeID: Int64,
    name: String?,
    current: MarketStockItemValue,
    netByWindow: [Int: Int64],
    removedByWindow: [Int: Int64]
  ) {
    self.typeID = typeID
    self.name = name
    self.current = current
    self.netByWindow = netByWindow
    self.removedByWindow = removedByWindow
  }

  /// Every item listed at the latest point or changed inside a window.
  public static func rows(
    _ overview: MarketStockHubOverview,
    names: [Int64: String]
  ) -> [MarketStockOverviewRow] {
    let knownWindows = overview.coverage.enumerated().filter {
      $0.element.daysWithKnownDelta > 0
    }
    return overview.itemsByType.values.map { item in
      var net: [Int: Int64] = [:]
      var removed: [Int: Int64] = [:]
      for (index, coverage) in knownWindows {
        let sell = item.totals.indices.contains(index) ? item.totals[index].sell : .zero
        net[coverage.days] = sell.net
        removed[coverage.days] = sell.removed
      }
      return MarketStockOverviewRow(
        typeID: item.typeID,
        name: names[item.typeID],
        current: item.current,
        netByWindow: net,
        removedByWindow: removed
      )
    }
  }

  public enum Column: Hashable, Sendable {
    case name
    case sellUnits
    case sellOrders
    case bestSell
    case buyUnits
    case buyOrders
    case bestBuy
    case net(days: Int)
    case removed(days: Int)
  }

  public func value(_ column: Column) -> Double? {
    switch column {
    case .name: nil
    case .sellUnits: Double(current.sell.units)
    case .sellOrders: Double(current.sell.orderCount)
    case .bestSell: current.sell.bestPrice
    case .buyUnits: Double(current.buy.units)
    case .buyOrders: Double(current.buy.orderCount)
    case .bestBuy: current.buy.bestPrice
    case .net(let days): netByWindow[days].map(Double.init)
    case .removed(let days): removedByWindow[days].map(Double.init)
    }
  }
}

/// Sort comparator for the native table: typed values, unknown values after
/// known ones ascending and before them descending, the type ID as stable
/// final tie-breaker.
public struct MarketStockOverviewComparator: SortComparator, Hashable, Sendable {
  public var column: MarketStockOverviewRow.Column
  public var order: SortOrder

  public init(column: MarketStockOverviewRow.Column, order: SortOrder = .forward) {
    self.column = column
    self.order = order
  }

  public func compare(
    _ lhs: MarketStockOverviewRow,
    _ rhs: MarketStockOverviewRow
  ) -> ComparisonResult {
    let primary: ComparisonResult
    if column == .name {
      switch (lhs.name, rhs.name) {
      case (let left?, let right?): primary = left.localizedStandardCompare(right)
      case (.some, nil): primary = .orderedAscending
      case (nil, .some): primary = .orderedDescending
      case (nil, nil): primary = .orderedSame
      }
    } else {
      switch (lhs.value(column), rhs.value(column)) {
      case (let left?, let right?):
        primary = left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
      case (.some, nil): primary = .orderedAscending
      case (nil, .some): primary = .orderedDescending
      case (nil, nil): primary = .orderedSame
      }
    }
    if primary != .orderedSame {
      guard order == .reverse else { return primary }
      return primary == .orderedAscending ? .orderedDescending : .orderedAscending
    }
    return lhs.typeID < rhs.typeID
      ? .orderedAscending : lhs.typeID > rhs.typeID ? .orderedDescending : .orderedSame
  }
}

enum MarketStockMath {
  static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? (rhs > 0 ? .max : .min) : value
  }

  static func saturatedSubtract(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
    return overflow ? (rhs > 0 ? .min : .max) : value
  }
}
