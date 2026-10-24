import Foundation

/// One tile of the Trade area: a direct child market group of the selected
/// node with every item of its subtree, or the node's own items.
public struct TradeTile: Identifiable, Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case childGroup
    case nodeOwnItems
  }

  /// Stable per node: the child group ID, or the negated node ID for the
  /// node's own items so it never collides with a child.
  public var id: Int64 {
    kind == .childGroup ? marketGroupID : -marketGroupID
  }
  public let kind: Kind
  public let marketGroupID: Int64
  public let name: String
  /// True when the tile's group has subgroups the user can open.
  public let hasSubgroups: Bool
  public let items: [TradeCatalogItem]

  public init(
    kind: Kind,
    marketGroupID: Int64,
    name: String,
    hasSubgroups: Bool,
    items: [TradeCatalogItem]
  ) {
    self.kind = kind
    self.marketGroupID = marketGroupID
    self.name = name
    self.hasSubgroups = hasSubgroups
    self.items = items
  }
}

/// Builds tiles from the selected market group (owner decision U4,
/// 22.10.2026): each direct child becomes a tile with its whole subtree;
/// items listed directly on the node form an extra tile named after it.
public enum TradeTileBuilder {
  public static func tiles(
    node: MarketGroupDefinition,
    groups: [MarketGroupDefinition],
    subtreeItems: [TradeCatalogItem]
  ) -> [TradeTile] {
    var childrenByParent: [Int64: [MarketGroupDefinition]] = [:]
    for group in groups {
      guard let parentID = group.parentID else { continue }
      childrenByParent[parentID, default: []].append(group)
    }
    let children = (childrenByParent[node.id] ?? []).sorted(by: nameOrder)

    // Map every group below the node to the direct child that contains it.
    var tileGroupByGroup: [Int64: Int64] = [:]
    for child in children {
      var pending = [child.id]
      var visited = Set<Int64>()
      while let current = pending.popLast() {
        guard visited.insert(current).inserted else { continue }
        tileGroupByGroup[current] = child.id
        pending.append(contentsOf: (childrenByParent[current] ?? []).map(\.id))
      }
    }

    var itemsByTile: [Int64: [TradeCatalogItem]] = [:]
    var ownItems: [TradeCatalogItem] = []
    for item in subtreeItems {
      if item.marketGroupID == node.id {
        ownItems.append(item)
      } else if let tileGroup = tileGroupByGroup[item.marketGroupID] {
        itemsByTile[tileGroup, default: []].append(item)
      }
    }

    var tiles: [TradeTile] = []
    if !ownItems.isEmpty {
      tiles.append(
        TradeTile(
          kind: .nodeOwnItems,
          marketGroupID: node.id,
          name: node.name,
          hasSubgroups: false,
          items: ownItems.sorted(by: itemOrder)
        )
      )
    }
    for child in children {
      let items = itemsByTile[child.id] ?? []
      guard !items.isEmpty else { continue }
      tiles.append(
        TradeTile(
          kind: .childGroup,
          marketGroupID: child.id,
          name: child.name,
          hasSubgroups: !(childrenByParent[child.id] ?? []).isEmpty,
          items: items.sorted(by: itemOrder)
        )
      )
    }
    return tiles
  }

  /// Root-to-node path for the breadcrumb; stops at a missing or cyclic
  /// parent instead of looping.
  public static func path(
    to nodeID: Int64,
    groups: [MarketGroupDefinition]
  ) -> [MarketGroupDefinition] {
    let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var path: [MarketGroupDefinition] = []
    var visited = Set<Int64>()
    var current = byID[nodeID]
    while let group = current, visited.insert(group.id).inserted {
      path.append(group)
      current = group.parentID.flatMap { byID[$0] }
    }
    return path.reversed()
  }

  private static func nameOrder(
    _ lhs: MarketGroupDefinition,
    _ rhs: MarketGroupDefinition
  ) -> Bool {
    let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
  }

  private static func itemOrder(
    _ lhs: TradeCatalogItem,
    _ rhs: TradeCatalogItem
  ) -> Bool {
    let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
  }
}

/// Arrow of the Diff % column. Thresholds are fractions (0.25 = 25 %).
public enum TradeDifferenceIndicator: String, Equatable, Sendable {
  case strongIncrease
  case increase
  case neutral
  case decrease

  public static let defaultIncreaseThreshold = 0.25
  public static let defaultStrongIncreaseThreshold = 0.30

  public static func classify(
    _ fraction: Double?,
    increaseThreshold: Double = defaultIncreaseThreshold,
    strongIncreaseThreshold: Double = defaultStrongIncreaseThreshold
  ) -> TradeDifferenceIndicator? {
    guard let fraction, fraction.isFinite else { return nil }
    if fraction < 0 { return .decrease }
    if fraction >= max(increaseThreshold, strongIncreaseThreshold) {
      return .strongIncrease
    }
    if fraction >= increaseThreshold { return .increase }
    return .neutral
  }
}

/// A calculated row plus the target hub's observed daily demand.
public struct TradeDisplayRow: Identifiable, Equatable, Sendable {
  public var id: Int64 { row.typeID }
  public let row: TradeRow
  public let currentDailyDemand: Int64?
  public let averageDailyDemand: Int64?
  /// Units of open logbook entries for this type at the target hub; zero is
  /// a known value (nothing open).
  public let openLogbookQuantity: Int64
  /// Regional ESI market history of the target hub's region; `nil` while
  /// unknown (not loaded, failed or region unknown), never zero.
  public let volumeHistory: MarketTypeVolumeHistory?

  public init(
    row: TradeRow,
    currentDailyDemand: Int64?,
    averageDailyDemand: Int64?,
    openLogbookQuantity: Int64 = 0,
    volumeHistory: MarketTypeVolumeHistory? = nil
  ) {
    self.row = row
    self.currentDailyDemand = currentDailyDemand
    self.averageDailyDemand = averageDailyDemand
    self.openLogbookQuantity = openLogbookQuantity
    self.volumeHistory = volumeHistory
  }

  /// Units traded in the target region during `window`.
  public func tradedVolume(_ window: MarketHistoryWindow) -> Int64? {
    volumeHistory?.tradedVolume(window)
  }

  /// Traded units per day during `window`.
  public func averageDailyVolume(_ window: MarketHistoryWindow) -> Double? {
    volumeHistory?.averageDailyVolume(window)
  }

  /// `profit × averageDailyVolume(window)` in ISK per day: an upper bound,
  /// because the regional volume is shared with every other trader. Unknown
  /// without profit or history; a negative profit stays negative.
  public func dailyProfitPotential(_ window: MarketHistoryWindow) -> Double? {
    guard let profit = row.profit, profit.isFinite,
      let perDay = averageDailyVolume(window)
    else { return nil }
    let value = profit * perDay
    return value.isFinite ? value : nil
  }
}

public enum TradeSortColumn: String, CaseIterable, Hashable, Sendable {
  case name
  case sourcePrice
  case targetPrice
  case difference
  case profitPerCubicMeter
  case purchaseCost
  case transportCost
  case netSale
  case profit
  case margin
  case returnOnInvestment
  case averageDailyDemand
  case currentDailyDemand
  case targetDepth
  case openLogbookQuantity
  case tradedVolume
  case averageDailyVolume
  case dailyProfitPotential
}

/// Sorts by the typed value of a column. Unknown values follow known values
/// in ascending order and precede them in descending order; the type ID is
/// the final tie-breaker.
public enum TradeRowSorter {
  public static func sorted(
    _ rows: [TradeDisplayRow],
    by column: TradeSortColumn,
    ascending: Bool,
    volumeWindow: MarketHistoryWindow = .sevenDays
  ) -> [TradeDisplayRow] {
    rows.sorted { lhs, rhs in
      if column == .name {
        let order = lhs.row.name.localizedCaseInsensitiveCompare(rhs.row.name)
        if order != .orderedSame {
          return ascending
            ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.id < rhs.id
      }
      switch (
        value(lhs, column, volumeWindow: volumeWindow),
        value(rhs, column, volumeWindow: volumeWindow)
      ) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return ascending
      case (nil, .some):
        return !ascending
      case (nil, nil):
        break
      }
      return lhs.id < rhs.id
    }
  }

  static func value(
    _ display: TradeDisplayRow,
    _ column: TradeSortColumn,
    volumeWindow: MarketHistoryWindow = .sevenDays
  ) -> Double? {
    let row = display.row
    return switch column {
    case .name: nil
    case .sourcePrice: row.sourcePrice
    case .targetPrice: row.targetPrice
    case .difference: row.differenceFraction
    case .profitPerCubicMeter: row.profitPerCubicMeter
    case .purchaseCost: row.purchaseCost
    case .transportCost: row.transportCost
    case .netSale: row.netSale
    case .profit: row.profit
    case .margin: row.margin
    case .returnOnInvestment: row.returnOnInvestment
    case .averageDailyDemand: display.averageDailyDemand.map(Double.init)
    case .currentDailyDemand: display.currentDailyDemand.map(Double.init)
    case .targetDepth: row.targetVolumeAtPrice.map(Double.init)
    case .openLogbookQuantity: Double(display.openLogbookQuantity)
    case .tradedVolume: display.tradedVolume(volumeWindow).map(Double.init)
    case .averageDailyVolume: display.averageDailyVolume(volumeWindow)
    case .dailyProfitPotential: display.dailyProfitPotential(volumeWindow)
    }
  }
}

/// Metric of the Top-20 tile. Raw values are stored; the former raw value
/// `difference` no longer resolves (HANDEL_PLAN.md section K).
public enum TradeTopRankingMetric: String, CaseIterable, Sendable {
  case profitPerCubicMeter
  case returnOnInvestment

  public var sortColumn: TradeSortColumn {
    switch self {
    case .profitPerCubicMeter: .profitPerCubicMeter
    case .returnOnInvestment: .returnOnInvestment
    }
  }
}

public struct TradeTopRankingResult: Equatable, Sendable {
  /// At most the ranking limit, highest value first.
  public let rows: [TradeDisplayRow]
  /// Candidates whose metric is unknown.
  public let unknownCount: Int
  /// Candidates whose metric is known but whose metric or profit is zero,
  /// negative or unknown.
  public let nonPositiveCount: Int
  /// Every candidate handed to the ranking.
  public let candidateCount: Int

  public init(
    rows: [TradeDisplayRow],
    unknownCount: Int,
    nonPositiveCount: Int,
    candidateCount: Int
  ) {
    self.rows = rows
    self.unknownCount = unknownCount
    self.nonPositiveCount = nonPositiveCount
    self.candidateCount = candidateCount
  }
}

/// Ranking of the Top-20 tile (owner decisions 23.10.2026, HANDEL_PLAN.md
/// sections J and K): only rows with a known positive profit and a known
/// positive metric rank, highest first with the type ID as tie-breaker.
/// Unknown and non-positive values are counted, never ranked and never
/// treated as zero.
public enum TradeTopRanking {
  public static let limit = 20

  public static func ranked(
    _ rows: [TradeDisplayRow],
    by metric: TradeTopRankingMetric,
    limit: Int = TradeTopRanking.limit
  ) -> TradeTopRankingResult {
    var positive: [TradeDisplayRow] = []
    var unknownCount = 0
    var nonPositiveCount = 0
    for row in rows {
      guard let value = TradeRowSorter.value(row, metric.sortColumn), value.isFinite
      else {
        unknownCount += 1
        continue
      }
      if value > 0, let profit = row.row.profit, profit.isFinite, profit > 0 {
        positive.append(row)
      } else {
        nonPositiveCount += 1
      }
    }
    let ranked = TradeRowSorter.sorted(positive, by: metric.sortColumn, ascending: false)
    return TradeTopRankingResult(
      rows: Array(ranked.prefix(max(0, limit))),
      unknownCount: unknownCount,
      nonPositiveCount: nonPositiveCount,
      candidateCount: rows.count
    )
  }
}
