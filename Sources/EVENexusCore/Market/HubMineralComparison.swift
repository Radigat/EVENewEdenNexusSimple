import Foundation

// Mineral prices at the Home Hub against the Main Hub for the Dashboard tile
// "Minerals at the Home Hub" (owner decisions 25.11.2026,
// `Documentation/Consolidation/DECISIONS.md`).
//
// Both prices come from the mineral purchase analysis and are its 10 % limit:
// exactly 1.10 × the lowest valid sell order at the exact configured
// location. Only fresh markets count, like the purchase recommendation.
// Transport, taxes and fees are not included.

/// Usability of one hub market inside the comparison.
public enum HubMineralMarketAvailability: Equatable, Sendable {
  /// Fresh order book at the exact configured location.
  case fresh
  /// Not usable: the market's state, `nil` when it was never loaded.
  case unusable(DataFreshness?)
}

/// One price cell. A missing price is an explicit state, never zero.
public enum HubMineralPrice: Equatable, Sendable {
  /// 10 % limit of the lowest valid sell order, ISK per unit.
  case price(Double)
  /// The market is fresh but has no valid sell order for the mineral.
  case noOffer
  /// The market is not usable; its state, `nil` when it was never loaded.
  case marketUnavailable(DataFreshness?)

  public var value: Double? {
    if case .price(let value) = self { return value }
    return nil
  }
}

/// Colour meaning of a deviation, decided on the displayed percentage with
/// one decimal: a value shown as 0.0 % is even.
public enum HubMineralDeviationTone: Equatable, Sendable {
  case cheaperAtHome
  case moreExpensiveAtHome
  case even
}

public struct HubMineralComparisonRow: Identifiable, Equatable, Sendable {
  public let material: MaterialPurchaseItem
  public let homePrice: HubMineralPrice
  public let mainPrice: HubMineralPrice
  /// Position in the owner's reference order (Tritanium … Morphite).
  public let standardRank: Int

  public var id: Int64 { material.id }

  public init(
    material: MaterialPurchaseItem,
    homePrice: HubMineralPrice,
    mainPrice: HubMineralPrice,
    standardRank: Int
  ) {
    self.material = material
    self.homePrice = homePrice
    self.mainPrice = mainPrice
    self.standardRank = standardRank
  }

  /// (Home − Main) / Main as a fraction; `nil` unless both prices are known.
  /// Negative means cheaper at the Home Hub.
  public var deviation: Double? {
    guard let home = homePrice.value, let main = mainPrice.value, main > 0
    else { return nil }
    let value = (home - main) / main
    return value.isFinite ? value : nil
  }

  /// The deviation in percent, rounded to the one decimal the tile shows
  /// (half away from zero); a rounded zero is always +0.
  public var displayedDeviationPercent: Double? {
    guard let deviation else { return nil }
    let rounded = (deviation * 1_000).rounded(.toNearestOrAwayFromZero) / 10
    return rounded == 0 ? 0 : rounded
  }

  public var deviationTone: HubMineralDeviationTone? {
    guard let percent = displayedDeviationPercent else { return nil }
    if percent < 0 { return .cheaperAtHome }
    if percent > 0 { return .moreExpensiveAtHome }
    return .even
  }
}

public struct HubMineralComparison: Equatable, Sendable {
  public enum Status: Equatable, Sendable {
    case ready
    /// The analysis has no hub with this role.
    case missingHubs(home: Bool, main: Bool)
    /// Home Hub and Main Hub are the same location; nothing to compare.
    case sameLocation
  }

  public let status: Status
  public let homeHub: ProcurementLocation?
  public let mainHub: ProcurementLocation?
  /// `nil` unless the status is `.ready`.
  public let homeMarket: HubMineralMarketAvailability?
  public let mainMarket: HubMineralMarketAvailability?
  /// Every mineral of the analysis in the reference order; empty unless the
  /// status is `.ready`.
  public let rows: [HubMineralComparisonRow]

  public init(
    status: Status,
    homeHub: ProcurementLocation?,
    mainHub: ProcurementLocation?,
    homeMarket: HubMineralMarketAvailability?,
    mainMarket: HubMineralMarketAvailability?,
    rows: [HubMineralComparisonRow]
  ) {
    self.status = status
    self.homeHub = homeHub
    self.mainHub = mainHub
    self.homeMarket = homeMarket
    self.mainMarket = mainMarket
    self.rows = rows
  }
}

/// Columns of the tile. `standardOrder` has no header: it is the starting
/// order of the owner's reference until a header is clicked.
public enum HubMineralComparisonColumn: Hashable, Sendable {
  case standardOrder
  case mineral
  case homePrice
  case mainPrice
  case deviation
}

public enum HubMineralComparisonProjector {
  /// Tritanium, Pyerite, Mexallon, Isogen, Nocxium, Zydrine, Megacyte,
  /// Morphite: the order of the owner's reference tile.
  public static let standardMineralOrder: [Int64] = [
    34, 35, 36, 37, 38, 39, 40, 11_399,
  ]

  public static func project(
    _ analysis: MaterialPurchaseAnalysisSnapshot
  ) -> HubMineralComparison {
    let home = analysis.configuredHubs.first { $0.roles.contains(.home) }
    let main = analysis.configuredHubs.first { $0.roles.contains(.main) }
    guard let home, let main else {
      return HubMineralComparison(
        status: .missingHubs(home: home == nil, main: main == nil),
        homeHub: home?.location,
        mainHub: main?.location,
        homeMarket: nil,
        mainMarket: nil,
        rows: []
      )
    }
    guard home.id != main.id,
      !home.location.representsSameLocation(as: main.location)
    else {
      return HubMineralComparison(
        status: .sameLocation,
        homeHub: home.location,
        mainHub: main.location,
        homeMarket: nil,
        mainMarket: nil,
        rows: []
      )
    }
    let homeMarket = market(for: home, in: analysis)
    let mainMarket = market(for: main, in: analysis)
    let rows = analysis.materialCatalog.materials.map { material in
      HubMineralComparisonRow(
        material: material,
        homePrice: price(typeID: material.id, market: homeMarket),
        mainPrice: price(typeID: material.id, market: mainMarket),
        standardRank: standardMineralOrder.firstIndex(of: material.id)
          ?? standardMineralOrder.count
      )
    }
    return HubMineralComparison(
      status: .ready,
      homeHub: home.location,
      mainHub: main.location,
      homeMarket: homeMarket.availability,
      mainMarket: mainMarket.availability,
      rows: sorted(rows, by: .standardOrder, ascending: true)
    )
  }

  /// Header sorting by the typed value of the column: names textually,
  /// prices and deviation numerically. Missing values follow known values
  /// ascending and precede them descending; the type ID is the final
  /// tie-breaker in both directions.
  public static func sorted(
    _ rows: [HubMineralComparisonRow],
    by column: HubMineralComparisonColumn,
    ascending: Bool
  ) -> [HubMineralComparisonRow] {
    func optional(_ lhs: Double?, _ rhs: Double?) -> Bool? {
      switch (lhs, rhs) {
      case (let left?, let right?):
        return left == right ? nil : (ascending ? left < right : left > right)
      case (.some, nil): return ascending
      case (nil, .some): return !ascending
      case (nil, nil): return nil
      }
    }
    return rows.sorted { lhs, rhs in
      let ordered: Bool?
      switch column {
      case .standardOrder:
        ordered =
          lhs.standardRank == rhs.standardRank
          ? nil
          : (ascending
            ? lhs.standardRank < rhs.standardRank
            : lhs.standardRank > rhs.standardRank)
      case .mineral:
        let comparison = lhs.material.name.localizedCaseInsensitiveCompare(
          rhs.material.name
        )
        ordered =
          comparison == .orderedSame
          ? nil : ascending == (comparison == .orderedAscending)
      case .homePrice:
        ordered = optional(lhs.homePrice.value, rhs.homePrice.value)
      case .mainPrice:
        ordered = optional(lhs.mainPrice.value, rhs.mainPrice.value)
      case .deviation:
        ordered = optional(lhs.deviation, rhs.deviation)
      }
      return ordered ?? (lhs.id < rhs.id)
    }
  }

  private struct Market {
    let availability: HubMineralMarketAvailability
    let snapshot: MarketOrderSnapshot?
  }

  private static func market(
    for hub: MarketHubConfigurationSnapshot,
    in analysis: MaterialPurchaseAnalysisSnapshot
  ) -> Market {
    guard let sourced = analysis.configuredMarkets[hub.id] else {
      return Market(availability: .unusable(nil), snapshot: nil)
    }
    guard sourced.state == .fresh else {
      return Market(availability: .unusable(sourced.state), snapshot: nil)
    }
    guard let snapshot = sourced.value else {
      return Market(availability: .unusable(.unavailable), snapshot: nil)
    }
    guard snapshot.state == .fresh else {
      return Market(availability: .unusable(snapshot.state), snapshot: nil)
    }
    guard snapshot.locationID == hub.location.locationID else {
      return Market(availability: .unusable(.unavailable), snapshot: nil)
    }
    return Market(availability: .fresh, snapshot: snapshot)
  }

  private static func price(typeID: Int64, market: Market) -> HubMineralPrice {
    guard let snapshot = market.snapshot else {
      if case .unusable(let state) = market.availability {
        return .marketUnavailable(state)
      }
      return .marketUnavailable(nil)
    }
    guard
      let band = MaterialPurchasePriceBandAnalyzer.analyze(
        typeID: typeID,
        snapshot: snapshot
      )
    else { return .noOffer }
    return .price(band.maximumBandPrice)
  }
}

/// Number format of the tile, as in the owner's reference: two decimals
/// below 1,000 ISK, whole ISK from 1,000.
public enum HubMineralPriceFormat {
  public static func fractionDigits(for price: Double) -> Int {
    (price * 100).rounded() / 100 < 1_000 ? 2 : 0
  }
}
