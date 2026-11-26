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
  /// Distinct fits of the whole library that contain the type, as hull or
  /// item.
  public let fitCount: Int
  /// Σ over doctrines of target × quantity in each of its fits.
  public let requiredQuantity: Int64
  /// The type is the hull of at least one fit.
  public let isHull: Bool
  /// Doctrines with at least one fit that contains the type, in library
  /// order.
  public let doctrineIDs: [String]

  public var id: Int64 { typeID }

  public init(
    typeID: Int64,
    name: String,
    fitCount: Int,
    requiredQuantity: Int64,
    isHull: Bool,
    doctrineIDs: [String] = []
  ) {
    self.typeID = typeID
    self.name = name
    self.fitCount = fitCount
    self.requiredQuantity = requiredQuantity
    self.isHull = isHull
    self.doctrineIDs = doctrineIDs
  }
}

public enum DoctrineDemandAggregator {
  public static let maximumQuantity: Int64 = 1_000_000_000_000

  /// Every resolved type of the library. Unresolved names are left out;
  /// the import issues list them.
  public static func demands(
    library: DoctrineLibrary,
    targets: [String: Int]
  ) -> [DoctrineItemDemand] {
    var names: [Int64: String] = [:]
    var fitsByType: [Int64: Set<String>] = [:]
    var hullTypes: Set<Int64> = []
    for fit in library.fits {
      if let typeID = fit.hull.typeID {
        names[typeID] = names[typeID] ?? fit.hull.name
        fitsByType[typeID, default: []].insert(fit.id)
        hullTypes.insert(typeID)
      }
      for item in fit.items {
        guard let typeID = item.typeID else { continue }
        names[typeID] = names[typeID] ?? item.name
        fitsByType[typeID, default: []].insert(fit.id)
      }
    }
    let fitsByID = Dictionary(
      library.fits.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var required: [Int64: Int64] = [:]
    func add(_ typeID: Int64?, _ quantity: Int64) {
      guard let typeID, quantity > 0 else { return }
      let (sum, overflow) = (required[typeID] ?? 0).addingReportingOverflow(quantity)
      required[typeID] = overflow ? maximumQuantity : min(maximumQuantity, sum)
    }
    var doctrinesByType: [Int64: [String]] = [:]
    for doctrine in library.doctrines {
      var types: Set<Int64> = []
      for fitID in doctrine.fitIDs {
        guard let fit = fitsByID[fitID] else { continue }
        if let typeID = fit.hull.typeID { types.insert(typeID) }
        types.formUnion(fit.items.compactMap(\.typeID))
      }
      for typeID in types { doctrinesByType[typeID, default: []].append(doctrine.id) }
    }
    for doctrine in library.doctrines {
      let target = Int64(DoctrineTargets.clamped(targets[doctrine.id] ?? 0))
      guard target > 0 else { continue }
      for fitID in doctrine.fitIDs {
        guard let fit = fitsByID[fitID] else { continue }
        add(fit.hull.typeID, target)
        for item in fit.items {
          let (product, overflow) = item.quantity.multipliedReportingOverflow(by: target)
          add(item.typeID, overflow ? maximumQuantity : product)
        }
      }
    }
    return names.keys.sorted().map { typeID in
      DoctrineItemDemand(
        typeID: typeID,
        name: names[typeID] ?? "",
        fitCount: fitsByType[typeID]?.count ?? 0,
        requiredQuantity: required[typeID] ?? 0,
        isHull: hullTypes.contains(typeID),
        doctrineIDs: doctrinesByType[typeID] ?? []
      )
    }
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
  /// Required minus listed, at least 0; unknown while the listed stock is.
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
    let shortfall: Int64? =
      demand.requiredQuantity <= 0
      ? 0
      : input.listedQuantity.map { max(0, demand.requiredQuantity - max(0, $0)) }
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
  case requiredQuantity
  case allumisRequiredQuantity
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
    case .requiredQuantity: Double(row.demand.requiredQuantity)
    case .allumisRequiredQuantity: row.input.allumis.map { Double($0.requiredQuantity) }
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
