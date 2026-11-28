import Foundation

// Doctrine stock (DOKTRIN_BEDARF_PLAN.md): required quantities, stock reach
// and the build-or-import quick calculation per doctrine item.

/// Filter groups of the doctrine table, from the SDE category.
public enum DoctrineItemKind: String, CaseIterable, Codable, Sendable {
  case hull
  case module
  case charge
  case drone

  /// Ship → hull, Charge → charge, Drone and Fighter → drone, every other
  /// category (modules, subsystems, implants, boosters, …) → module.
  public static func kind(categoryName: String?) -> DoctrineItemKind {
    switch categoryName {
    case "Ship": .hull
    case "Charge": .charge
    case "Drone", "Fighter": .drone
    default: .module
    }
  }
}

/// Need of one SDE type over the doctrine library.
public struct DoctrineItemDemand: Equatable, Sendable, Identifiable {
  public let typeID: Int64
  public let name: String
  /// Distinct fits of the merged library that contain the type as hull or
  /// item, in the wiki content or in the content of the paired Allumis fit.
  public let fitCount: Int
  /// Target (Soll) at the Home Hub: Σ over every Allumis fit of its target
  /// × quantity in the fit, hull once per fit, refits not counted (owner
  /// decision 27.11.2026). 0 when no Allumis fit with a target uses the
  /// type; nil without an Allumis import.
  public let requiredQuantity: Int64?
  /// The type is the hull of at least one fit.
  public let isHull: Bool
  /// Doctrines with at least one fit that contains the type, in library
  /// order.
  public let doctrineIDs: [String]
  /// Part of the target that comes from the fits of each doctrine; only
  /// doctrines with a part above 0. A fit used by two doctrines counts for
  /// both, so the parts can add up to more than the target.
  public let requiredQuantityByDoctrineID: [String: Int64]

  public var id: Int64 { typeID }

  public init(
    typeID: Int64,
    name: String,
    fitCount: Int,
    requiredQuantity: Int64?,
    isHull: Bool,
    doctrineIDs: [String] = [],
    requiredQuantityByDoctrineID: [String: Int64] = [:]
  ) {
    self.typeID = typeID
    self.name = name
    self.fitCount = fitCount
    self.requiredQuantity = requiredQuantity
    self.isHull = isHull
    self.doctrineIDs = doctrineIDs
    self.requiredQuantityByDoctrineID = requiredQuantityByDoctrineID
  }
}

public enum DoctrineDemandAggregator {
  public static let maximumQuantity: Int64 = 1_000_000_000_000

  /// Every resolved type of the merged library and of the paired Allumis
  /// fits. Unresolved names are left out; the import issues list them.
  /// - The target comes only from Allumis: each Allumis fit adds its
  ///   target × quantity of its own content once, also when several
  ///   doctrines use the fit. A paired wiki fit with other content does not
  ///   change the target.
  /// - Without an Allumis import every target is unknown.
  public static func demands(sources: DoctrineAllumisMerge) -> [DoctrineItemDemand] {
    let library = sources.library
    let allumisFits = sources.allumisFitByFitID
    var names: [Int64: String] = [:]
    var fitsByType: [Int64: Set<String>] = [:]
    var typesByFit: [String: Set<Int64>] = [:]
    var hullTypes: Set<Int64> = []
    func note(_ item: DoctrineFitItem, fitID: String, isHull: Bool) {
      guard let typeID = item.typeID else { return }
      if names[typeID] == nil { names[typeID] = item.name }
      fitsByType[typeID, default: []].insert(fitID)
      typesByFit[fitID, default: []].insert(typeID)
      if isHull { hullTypes.insert(typeID) }
    }
    for fit in library.fits {
      note(fit.hull, fitID: fit.id, isHull: true)
      for item in fit.items { note(item, fitID: fit.id, isHull: false) }
      if let allumisFit = allumisFits[fit.id] {
        note(allumisFit.hull, fitID: fit.id, isHull: true)
        for item in allumisFit.items { note(item, fitID: fit.id, isHull: false) }
      }
    }

    // Target per fit from the Allumis content.
    var requiredByFit: [String: [Int64: Int64]] = [:]
    for (fitID, fit) in allumisFits {
      let target = Int64(DoctrineTargets.clamped(fit.target))
      guard target > 0 else { continue }
      var quantities: [Int64: Int64] = [:]
      func add(_ typeID: Int64?, _ quantity: Int64) {
        guard let typeID, quantity > 0 else { return }
        let (product, productOverflow) = quantity.multipliedReportingOverflow(by: target)
        quantities[typeID] = saturatedAdd(
          quantities[typeID] ?? 0, productOverflow ? maximumQuantity : product)
      }
      add(fit.hull.typeID, 1)
      for item in fit.items { add(item.typeID, item.quantity) }
      requiredByFit[fitID] = quantities
    }
    var required: [Int64: Int64] = [:]
    for quantities in requiredByFit.values {
      for (typeID, quantity) in quantities {
        required[typeID] = saturatedAdd(required[typeID] ?? 0, quantity)
      }
    }

    var doctrinesByType: [Int64: [String]] = [:]
    var partsByType: [Int64: [String: Int64]] = [:]
    for doctrine in library.doctrines {
      var types: Set<Int64> = []
      var parts: [Int64: Int64] = [:]
      for fitID in doctrine.fitIDs {
        types.formUnion(typesByFit[fitID] ?? [])
        for (typeID, quantity) in requiredByFit[fitID] ?? [:] {
          parts[typeID] = saturatedAdd(parts[typeID] ?? 0, quantity)
        }
      }
      for typeID in types { doctrinesByType[typeID, default: []].append(doctrine.id) }
      for (typeID, quantity) in parts where quantity > 0 {
        partsByType[typeID, default: [:]][doctrine.id] = quantity
      }
    }

    return names.keys.sorted().map { typeID in
      DoctrineItemDemand(
        typeID: typeID,
        name: names[typeID] ?? "",
        fitCount: fitsByType[typeID]?.count ?? 0,
        requiredQuantity: sources.hasAllumisImport ? required[typeID] ?? 0 : nil,
        isHull: hullTypes.contains(typeID),
        doctrineIDs: doctrinesByType[typeID] ?? [],
        requiredQuantityByDoctrineID: partsByType[typeID] ?? [:]
      )
    }
  }

  private static func saturatedAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    return overflow ? maximumQuantity : min(maximumQuantity, sum)
  }
}

/// How long the listed stock lasts at the regional sales rate.
public enum DoctrineStockCoverage: Equatable, Sendable {
  /// Listed units ÷ units sold per day.
  case days(Double)
  /// Nothing listed while the item sells.
  case outOfStock
  /// The item did not sell in the window; the stock does not run out.
  case noSales
  /// Listed stock or sales rate unknown.
  case unknown

  public static func of(listed: Int64?, unitsPerDay: Double?) -> DoctrineStockCoverage {
    guard let listed, listed >= 0, let unitsPerDay, unitsPerDay.isFinite, unitsPerDay >= 0
    else { return .unknown }
    guard unitsPerDay > 0 else { return .noSales }
    guard listed > 0 else { return .outOfStock }
    return .days(Double(listed) / unitsPerDay)
  }

  /// Sort value: out of stock is 0 days, no sales lasts forever, unknown
  /// has no value.
  public var sortValue: Double? {
    switch self {
    case .days(let days): days
    case .outOfStock: 0
    case .noSales: .infinity
    case .unknown: nil
    }
  }
}

/// Whether the planner can build the type at all.
public enum DoctrineBuildability: String, Equatable, Sendable {
  case buildable
  case notBuildable
  /// No active SDE or the build index is not loaded yet.
  case unknown
}

/// Cheaper way to get one unit to the Home Hub.
public enum DoctrineSourcing: String, Equatable, Sendable {
  case build
  case importFromMainHub
}

/// Inputs of one row besides the demand.
public struct DoctrineStockRowInput: Equatable, Sendable {
  public let kind: DoctrineItemKind
  /// Sell units listed at the Home Hub at the latest stock point.
  public let listedQuantity: Int64?
  /// Ø units per day over 30 days in the Home Hub's region (ESI history).
  public let regionUnitsPerDay: Double?
  /// Ø partial fills per recorded day over 30 days at the Home Hub.
  public let hubUnitsPerDay: Double?
  public let hubVolumeIsComplete: Bool?
  public let buildability: DoctrineBuildability
  /// New production delivered to the Home Hub, per unit.
  public let buildCostPerUnit: Double?
  /// Main Hub purchase and transport to the Home Hub, per unit.
  public let importPurchasePerUnit: Double?
  public let importTransportPerUnit: Double?
  /// The Main Hub has no sell order: importing is not possible right now.
  public let importHasNoSource: Bool
  public let homeBestSellPrice: Double?
  /// Own sell order one step below the best sell, after sales tax and
  /// broker fee.
  public let homeNetSalePerUnit: Double?
  /// Lowest sell at the Main Hub, for the price ratio Home ÷ Main.
  public let mainBestSellPrice: Double?
  /// Allumis figures of the type; nil without an Allumis import.
  public let allumis: DoctrineAllumisItemFigures?

  public init(
    kind: DoctrineItemKind,
    listedQuantity: Int64?,
    regionUnitsPerDay: Double?,
    hubUnitsPerDay: Double?,
    hubVolumeIsComplete: Bool?,
    buildability: DoctrineBuildability,
    buildCostPerUnit: Double?,
    importPurchasePerUnit: Double?,
    importTransportPerUnit: Double?,
    importHasNoSource: Bool,
    homeBestSellPrice: Double?,
    homeNetSalePerUnit: Double?,
    mainBestSellPrice: Double? = nil,
    allumis: DoctrineAllumisItemFigures? = nil
  ) {
    self.kind = kind
    self.listedQuantity = listedQuantity
    self.regionUnitsPerDay = regionUnitsPerDay
    self.hubUnitsPerDay = hubUnitsPerDay
    self.hubVolumeIsComplete = hubVolumeIsComplete
    self.buildability = buildability
    self.buildCostPerUnit = buildCostPerUnit
    self.importPurchasePerUnit = importPurchasePerUnit
    self.importTransportPerUnit = importTransportPerUnit
    self.importHasNoSource = importHasNoSource
    self.homeBestSellPrice = homeBestSellPrice
    self.homeNetSalePerUnit = homeNetSalePerUnit
    self.mainBestSellPrice = mainBestSellPrice
    self.allumis = allumis
  }
}

public struct DoctrineStockRow: Equatable, Sendable, Identifiable {
  public let demand: DoctrineItemDemand
  public let input: DoctrineStockRowInput
  public let coverage: DoctrineStockCoverage
  /// Target minus listed, at least 0: what still has to be built or
  /// imported. 0 without a target; unknown while the target or the listed
  /// stock is.
  public let shortfall: Int64?
  public let importCostPerUnit: Double?
  public let recommendation: DoctrineSourcing?
  /// How much the recommended way saves per unit against the other one;
  /// only when both costs are known.
  public let savingsPerUnit: Double?
  /// Home Hub net sale minus the recommended cost per unit.
  public let profitPerUnit: Double?

  public var id: Int64 { demand.typeID }
  public var typeID: Int64 { demand.typeID }
  public var name: String { demand.name }
  public var kind: DoctrineItemKind { input.kind }

  /// Best Home Hub sell ÷ lowest Main Hub sell (1 = same price); unknown
  /// while one of them is missing.
  public var homeToMainPriceRatio: Double? {
    guard let home = input.homeBestSellPrice, home.isFinite, home > 0,
      let main = input.mainBestSellPrice, main.isFinite, main > 0
    else { return nil }
    let ratio = home / main
    return ratio.isFinite ? ratio : nil
  }

  public var recommendedCostPerUnit: Double? {
    switch recommendation {
    case .build?: input.buildCostPerUnit
    case .importFromMainHub?: importCostPerUnit
    case nil: nil
    }
  }

  /// What filling the shortfall earns: shortfall × profit per unit (owner
  /// decision 27.11.2026). 0 without a shortfall, also while the profit is
  /// unknown; unknown while the shortfall is, or with a shortfall while the
  /// profit is.
  public var shortfallProfit: Double? {
    guard let shortfall else { return nil }
    guard shortfall > 0 else { return 0 }
    guard let profitPerUnit else { return nil }
    let total = profitPerUnit * Double(shortfall)
    return total.isFinite ? total : nil
  }

  /// Current stock minus target, with its sign (owner decision 28.11.2026):
  /// below 0 too few, 0 or more enough. Unknown while the target or the
  /// listed stock is, and nil without a target (target 0), because then
  /// nothing has to be met. A negative listed stock counts as 0, as in the
  /// shortfall.
  public var stockDifference: Int64? {
    guard let required = demand.requiredQuantity, required > 0,
      let listed = input.listedQuantity
    else { return nil }
    let (difference, overflow) = max(0, listed).subtractingReportingOverflow(required)
    return overflow ? nil : difference
  }
}

public enum DoctrineStockCalculator {
  public static func row(
    demand: DoctrineItemDemand,
    input: DoctrineStockRowInput
  ) -> DoctrineStockRow {
    let coverage = DoctrineStockCoverage.of(
      listed: input.listedQuantity,
      unitsPerDay: input.regionUnitsPerDay
    )
    let shortfall: Int64? = demand.requiredQuantity.flatMap { required in
      required <= 0 ? 0 : input.listedQuantity.map { max(0, required - max(0, $0)) }
    }
    let build = valid(input.buildCostPerUnit)
    let importCost = valid(input.importPurchasePerUnit).flatMap { purchase in
      valid(input.importTransportPerUnit).flatMap { finite(purchase + $0) }
    }
    let recommendation = recommend(
      build: build,
      buildability: input.buildability,
      importCost: importCost,
      importHasNoSource: input.importHasNoSource
    )
    let savings: Double? = build.flatMap { build in
      importCost.map { abs($0 - build) }
    }
    let chosenCost: Double? =
      switch recommendation {
      case .build?: build
      case .importFromMainHub?: importCost
      case nil: nil
      }
    let profit = chosenCost.flatMap { cost in
      valid(input.homeNetSalePerUnit).flatMap { finite($0 - cost) }
    }
    return DoctrineStockRow(
      demand: demand,
      input: input,
      coverage: coverage,
      shortfall: shortfall,
      importCostPerUnit: importCost,
      recommendation: recommendation,
      savingsPerUnit: recommendation == nil ? nil : savings,
      profitPerUnit: profit
    )
  }

  /// The cheaper way per unit. With one cost unknown there is only a
  /// recommendation when the other way is impossible (not buildable, or no
  /// sell order at the Main Hub); an equal cost prefers the import.
  public static func recommend(
    build: Double?,
    buildability: DoctrineBuildability,
    importCost: Double?,
    importHasNoSource: Bool
  ) -> DoctrineSourcing? {
    switch (build, importCost) {
    case (let build?, let importCost?):
      return build < importCost ? .build : .importFromMainHub
    case (nil, .some):
      return buildability == .notBuildable ? .importFromMainHub : nil
    case (.some, nil):
      return importHasNoSource ? .build : nil
    case (nil, nil):
      return nil
    }
  }

  private static func valid(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func finite(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }
}

// MARK: Sorting

public enum DoctrineStockSortColumn: String, CaseIterable, Sendable {
  case name
  /// Number of doctrines that use the item.
  case doctrines
  case fitCount
  /// Target (Soll) from Allumis.
  case requiredQuantity
  /// Listed at the Home Hub (Ist).
  case listedQuantity
  case regionUnitsPerDay
  case hubUnitsPerDay
  case allumisAverageDailyVolume7Days
  case allumisLostLast10Days
  case coverage
  case shortfall
  case buildCostPerUnit
  case importCostPerUnit
  case homeBestSellPrice
  case homeToMainPriceRatio
  /// Sorted by the savings of the recommended way.
  case recommendation
  case profitPerUnit
}

/// Sorts by the typed value of a column. Unknown values stay after known
/// values ascending and before them descending (AGENTS.md); “no sales” is a
/// known, unlimited reach. The type ID is the final tie-breaker.
public enum DoctrineStockRowSorter {
  public static func sorted(
    _ rows: [DoctrineStockRow],
    by column: DoctrineStockSortColumn,
    ascending: Bool
  ) -> [DoctrineStockRow] {
    rows.sorted { lhs, rhs in
      if column == .name {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if order != .orderedSame {
          return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.typeID < rhs.typeID
      }
      switch (value(lhs, column), value(rhs, column)) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return ascending
      case (nil, .some):
        return !ascending
      case (nil, nil):
        break
      }
      return lhs.typeID < rhs.typeID
    }
  }

  static func value(_ row: DoctrineStockRow, _ column: DoctrineStockSortColumn) -> Double? {
    switch column {
    case .name: nil
    case .doctrines: Double(row.demand.doctrineIDs.count)
    case .fitCount: Double(row.demand.fitCount)
    case .requiredQuantity: row.demand.requiredQuantity.map(Double.init)
    case .listedQuantity: row.input.listedQuantity.map(Double.init)
    case .regionUnitsPerDay: row.input.regionUnitsPerDay
    case .hubUnitsPerDay: row.input.hubUnitsPerDay
    case .allumisAverageDailyVolume7Days: row.input.allumis?.averageDailyVolume7Days
    case .allumisLostLast10Days: row.input.allumis?.lostLast10Days.map(Double.init)
    case .coverage: row.coverage.sortValue
    case .shortfall: row.shortfall.map(Double.init)
    case .buildCostPerUnit: row.input.buildCostPerUnit
    case .importCostPerUnit: row.importCostPerUnit
    case .homeBestSellPrice: row.input.homeBestSellPrice
    case .homeToMainPriceRatio: row.homeToMainPriceRatio
    case .recommendation: row.savingsPerUnit
    case .profitPerUnit: row.profitPerUnit
    }
  }
}

// MARK: Top lists

/// The two top lists of the page (owner request 27.11.2026,
/// DOKTRIN_BEDARF_PLAN.md section I). Both rank every item of the table,
/// independent of its filters.
public enum DoctrineTopListKind: String, CaseIterable, Sendable {
  /// Fits that use the item; a tie goes to the larger target.
  case mostUsed
  /// Profit per unit × shortfall.
  case profitOpportunity
}

/// One item of a top list with its place.
public struct DoctrineTopEntry: Equatable, Sendable, Identifiable {
  /// Place in the ranking, from 1.
  public let rank: Int
  public let row: DoctrineStockRow

  public var id: Int64 { row.typeID }

  public init(rank: Int, row: DoctrineStockRow) {
    self.rank = rank
    self.row = row
  }
}

public struct DoctrineTopRankingResult: Equatable, Sendable {
  /// At most the limit, place 1 first.
  public let entries: [DoctrineTopEntry]
  /// Every row handed to the ranking.
  public let candidateCount: Int
  /// Rows whose value is unknown; never ranked, never counted as 0.
  public let unknownCount: Int
  /// Rows with a known value of 0 or less; never ranked.
  public let nonPositiveCount: Int

  public init(
    entries: [DoctrineTopEntry],
    candidateCount: Int,
    unknownCount: Int,
    nonPositiveCount: Int
  ) {
    self.entries = entries
    self.candidateCount = candidateCount
    self.unknownCount = unknownCount
    self.nonPositiveCount = nonPositiveCount
  }

  public static let empty = DoctrineTopRankingResult(
    entries: [], candidateCount: 0, unknownCount: 0, nonPositiveCount: 0)
}

/// Only rows with a known value above 0 rank, highest first.
/// - Most used: number of fits; a tie goes to the larger target, an unknown
///   target after a known one.
/// - Profit opportunity: `shortfallProfit`, so only items with a shortfall
///   and a positive profit per unit.
/// The type ID is the final tie-breaker.
public enum DoctrineTopRanking {
  public static let limit = 10

  public static func ranked(
    _ rows: [DoctrineStockRow],
    by kind: DoctrineTopListKind,
    limit: Int = DoctrineTopRanking.limit
  ) -> DoctrineTopRankingResult {
    var ranked: [(row: DoctrineStockRow, value: Double)] = []
    var unknownCount = 0
    var nonPositiveCount = 0
    for row in rows {
      guard let value = value(row, kind), value.isFinite else {
        unknownCount += 1
        continue
      }
      if value > 0 {
        ranked.append((row, value))
      } else {
        nonPositiveCount += 1
      }
    }
    ranked.sort { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      if kind == .mostUsed {
        switch (lhs.row.demand.requiredQuantity, rhs.row.demand.requiredQuantity) {
        case (let left?, let right?):
          if left != right { return left > right }
        case (.some, nil):
          return true
        case (nil, .some):
          return false
        case (nil, nil):
          break
        }
      }
      return lhs.row.typeID < rhs.row.typeID
    }
    let entries = ranked.prefix(max(0, limit)).enumerated().map { offset, item in
      DoctrineTopEntry(rank: offset + 1, row: item.row)
    }
    return DoctrineTopRankingResult(
      entries: entries,
      candidateCount: rows.count,
      unknownCount: unknownCount,
      nonPositiveCount: nonPositiveCount
    )
  }

  static func value(_ row: DoctrineStockRow, _ kind: DoctrineTopListKind) -> Double? {
    switch kind {
    case .mostUsed: Double(row.demand.fitCount)
    case .profitOpportunity: row.shortfallProfit
    }
  }
}

public enum DoctrineTopSortColumn: String, CaseIterable, Sendable {
  /// Place in the ranking.
  case rank
  case name
  case fitCount
  /// Number of doctrines that use the item.
  case doctrines
  /// Target (Soll) from Allumis.
  case requiredQuantity
  /// Current stock (Ist) at the Home Hub.
  case listedQuantity
  /// Current stock minus target; without a target it has no value.
  case stockDifference
  case shortfallProfit
  case profitPerUnit
  case shortfall
  /// Documented rank: build before import.
  case recommendation
}

/// Sorts the entries of a top list by the typed value of a column. Unknown
/// values stay after known values ascending and before them descending
/// (AGENTS.md); the place in the ranking is the final tie-breaker, so equal
/// values keep the order of the ranking.
public enum DoctrineTopEntrySorter {
  public static func sorted(
    _ entries: [DoctrineTopEntry],
    by column: DoctrineTopSortColumn,
    ascending: Bool
  ) -> [DoctrineTopEntry] {
    entries.sorted { lhs, rhs in
      if column == .name {
        let order = lhs.row.name.localizedCaseInsensitiveCompare(rhs.row.name)
        if order != .orderedSame {
          return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.rank < rhs.rank
      }
      switch (value(lhs, column), value(rhs, column)) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return ascending
      case (nil, .some):
        return !ascending
      case (nil, nil):
        break
      }
      return lhs.rank < rhs.rank
    }
  }

  static func value(_ entry: DoctrineTopEntry, _ column: DoctrineTopSortColumn) -> Double? {
    let row = entry.row
    switch column {
    case .rank: return Double(entry.rank)
    case .name: return nil
    case .fitCount: return Double(row.demand.fitCount)
    case .doctrines: return Double(row.demand.doctrineIDs.count)
    case .requiredQuantity: return row.demand.requiredQuantity.map(Double.init)
    case .listedQuantity: return row.input.listedQuantity.map(Double.init)
    case .stockDifference: return row.stockDifference.map(Double.init)
    case .shortfallProfit: return row.shortfallProfit
    case .profitPerUnit: return row.profitPerUnit
    case .shortfall: return row.shortfall.map(Double.init)
    case .recommendation:
      switch row.recommendation {
      case .build?: return 0
      case .importFromMainHub?: return 1
      case nil: return nil
      }
    }
  }
}
