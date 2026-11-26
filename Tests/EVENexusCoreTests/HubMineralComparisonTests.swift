import Foundation
import Testing

@testable import EVENexusCore

/// Dashboard tile "Minerals at the Home Hub" (owner decisions 25.11.2026).
@Suite("Home Hub mineral comparison")
struct HubMineralComparisonTests {
  private let source = SourceIdentity(provider: "fixture", version: "1")
  private let homeLocation = ProcurementLocation(
    id: "structure:1022734985679",
    name: "Fixture Home Structure",
    locationID: 1_022_734_985_679,
    kind: .playerStructure,
    solarSystemID: 30_004_759,
    regionID: 10_000_060
  )
  private let mainLocation = ProcurementLocation.jita

  private let minerals: [MaterialPurchaseItem] = [
    // Deliberately not in the reference order.
    MaterialPurchaseItem(id: 11_399, name: "Morphite"),
    MaterialPurchaseItem(id: 36, name: "Mexallon"),
    MaterialPurchaseItem(id: 34, name: "Tritanium"),
    MaterialPurchaseItem(id: 40, name: "Megacyte"),
    MaterialPurchaseItem(id: 35, name: "Pyerite"),
    MaterialPurchaseItem(id: 39, name: "Zydrine"),
    MaterialPurchaseItem(id: 37, name: "Isogen"),
    MaterialPurchaseItem(id: 38, name: "Nocxium"),
  ]

  private func sell(
    _ typeID: Int64,
    _ price: Double,
    at location: ProcurementLocation,
    id: Int64? = nil,
    volume: Int64 = 100
  ) -> MarketOrder {
    MarketOrder(
      id: id ?? typeID * 1_000 + Int64(price * 100),
      typeID: typeID,
      locationID: location.locationID!,
      systemID: location.solarSystemID!,
      side: .sell,
      price: price,
      volumeRemaining: volume,
      minimumVolume: 1,
      issued: .now
    )
  }

  private func market(
    _ orders: [MarketOrder],
    at location: ProcurementLocation,
    state: DataFreshness = .fresh
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: location.regionID!,
      locationID: location.locationID!,
      capturedAt: .now,
      state: state,
      ordersByType: Dictionary(grouping: orders, by: \.typeID),
      source: source
    )
  }

  private func analysis(
    hubs: [MarketHubConfigurationSnapshot],
    markets: [UUID: Sourced<MarketOrderSnapshot>]
  ) -> MaterialPurchaseAnalysisSnapshot {
    MaterialPurchaseAnalysisSnapshot(
      materialCatalog: MaterialPurchaseCatalogSnapshot(
        materials: minerals,
        source: source
      ),
      configuredHubs: hubs,
      configuredMarkets: markets,
      refreshedAt: .now
    )
  }

  private func standardAnalysis(
    homeOrders: [MarketOrder],
    mainOrders: [MarketOrder],
    homeState: DataFreshness = .fresh,
    mainState: DataFreshness = .fresh
  ) -> MaterialPurchaseAnalysisSnapshot {
    let main = MarketHubConfigurationSnapshot(
      id: UUID(),
      location: mainLocation,
      roles: [.main]
    )
    let home = MarketHubConfigurationSnapshot(
      id: UUID(),
      location: homeLocation,
      roles: [.home]
    )
    return analysis(
      hubs: [main, home],
      markets: [
        main.id: Sourced(
          state: mainState,
          value: market(mainOrders, at: mainLocation),
          source: source
        ),
        home.id: Sourced(
          state: homeState,
          value: market(homeOrders, at: homeLocation),
          source: source
        ),
      ]
    )
  }

  @Test
  func pricesAreTheTenPercentLimitAndRowsFollowTheReferenceOrder() throws {
    let comparison = HubMineralComparisonProjector.project(
      standardAnalysis(
        homeOrders: [
          sell(34, 3.78, at: homeLocation),
          sell(34, 3.90, at: homeLocation),
          sell(11_399, 17_330, at: homeLocation),
        ],
        mainOrders: [
          sell(34, 4.05, at: mainLocation),
          sell(11_399, 18_630, at: mainLocation),
        ]
      )
    )
    #expect(comparison.status == .ready)
    #expect(comparison.homeHub == homeLocation)
    #expect(comparison.mainHub == mainLocation)
    #expect(comparison.homeMarket == .fresh)
    #expect(comparison.mainMarket == .fresh)
    #expect(comparison.rows.map(\.id) == HubMineralComparisonProjector.standardMineralOrder)

    let tritanium = try #require(comparison.rows.first { $0.id == 34 })
    let home = try #require(tritanium.homePrice.value)
    let main = try #require(tritanium.mainPrice.value)
    #expect(abs(home - 3.78 * 1.10) < 1e-9)
    #expect(abs(main - 4.05 * 1.10) < 1e-9)
    // The common factor 1.10 cancels: same deviation as the lowest sell.
    let deviation = try #require(tritanium.deviation)
    #expect(abs(deviation - (3.78 - 4.05) / 4.05) < 1e-9)
    #expect(tritanium.displayedDeviationPercent == -6.7)
    #expect(tritanium.deviationTone == .cheaperAtHome)

    let morphite = try #require(comparison.rows.first { $0.id == 11_399 })
    #expect(morphite.displayedDeviationPercent == -7.0)
  }

  @Test
  func missingOfferIsNoOfferAndNeverZero() throws {
    let comparison = HubMineralComparisonProjector.project(
      standardAnalysis(
        homeOrders: [sell(35, 20.93, at: homeLocation)],
        mainOrders: [
          sell(34, 4.05, at: mainLocation),
          sell(35, 15.66, at: mainLocation),
        ]
      )
    )
    let tritanium = try #require(comparison.rows.first { $0.id == 34 })
    #expect(tritanium.homePrice == .noOffer)
    #expect(tritanium.homePrice.value == nil)
    #expect(tritanium.deviation == nil)
    #expect(tritanium.deviationTone == nil)
    let pyerite = try #require(comparison.rows.first { $0.id == 35 })
    #expect(pyerite.displayedDeviationPercent == 33.7)
    #expect(pyerite.deviationTone == .moreExpensiveAtHome)
  }

  @Test(arguments: [DataFreshness.stale, .forbidden, .unavailable, .partial])
  func unusableMarketShowsItsStateInEveryRow(state: DataFreshness) {
    let comparison = HubMineralComparisonProjector.project(
      standardAnalysis(
        homeOrders: [sell(34, 3.78, at: homeLocation)],
        mainOrders: [sell(34, 4.05, at: mainLocation)],
        mainState: state
      )
    )
    #expect(comparison.status == .ready)
    #expect(comparison.mainMarket == .unusable(state))
    #expect(comparison.homeMarket == .fresh)
    #expect(comparison.rows.count == minerals.count)
    #expect(comparison.rows.allSatisfy { $0.mainPrice == .marketUnavailable(state) })
    #expect(comparison.rows.allSatisfy { $0.deviation == nil })
    #expect(comparison.rows.first { $0.id == 34 }?.homePrice.value != nil)
  }

  @Test
  func marketNeverLoadedOrAtAnotherLocationIsUnavailable() {
    let main = MarketHubConfigurationSnapshot(id: UUID(), location: mainLocation, roles: [.main])
    let home = MarketHubConfigurationSnapshot(id: UUID(), location: homeLocation, roles: [.home])
    let comparison = HubMineralComparisonProjector.project(
      analysis(
        hubs: [main, home],
        markets: [
          // The Main Hub entry carries the Home Hub's order book.
          main.id: Sourced(
            state: .fresh,
            value: market([sell(34, 3.78, at: homeLocation)], at: homeLocation),
            source: source
          )
        ]
      )
    )
    #expect(comparison.homeMarket == .unusable(nil))
    #expect(comparison.mainMarket == .unusable(.unavailable))
    #expect(comparison.rows.first?.homePrice == .marketUnavailable(nil))
    #expect(comparison.rows.first?.mainPrice == .marketUnavailable(.unavailable))
  }

  @Test
  func missingHubsAndSameLocationAreOwnStates() {
    let mainOnly = MarketHubConfigurationSnapshot(id: UUID(), location: mainLocation, roles: [.main])
    let comparisonOnly = MarketHubConfigurationSnapshot(
      id: UUID(), location: homeLocation, roles: [.comparison]
    )
    let noHome = HubMineralComparisonProjector.project(
      analysis(hubs: [mainOnly, comparisonOnly], markets: [:])
    )
    #expect(noHome.status == .missingHubs(home: true, main: false))
    #expect(noHome.rows.isEmpty)
    #expect(noHome.mainHub == mainLocation)

    let nothing = HubMineralComparisonProjector.project(
      analysis(hubs: [comparisonOnly], markets: [:])
    )
    #expect(nothing.status == .missingHubs(home: true, main: true))

    let shared = MarketHubConfigurationSnapshot(
      id: UUID(), location: mainLocation, roles: [.main, .home]
    )
    let sameRole = HubMineralComparisonProjector.project(
      analysis(hubs: [shared], markets: [:])
    )
    #expect(sameRole.status == .sameLocation)
    #expect(sameRole.rows.isEmpty)

    let secondEntry = MarketHubConfigurationSnapshot(
      id: UUID(), location: mainLocation, roles: [.home]
    )
    let sameStation = HubMineralComparisonProjector.project(
      analysis(hubs: [mainOnly, secondEntry], markets: [:])
    )
    #expect(sameStation.status == .sameLocation)
  }

  @Test
  func headerSortingPlacesMissingValuesAndBreaksTiesByTypeID() {
    let comparison = HubMineralComparisonProjector.project(
      standardAnalysis(
        homeOrders: [
          sell(34, 5, at: homeLocation),
          sell(35, 20, at: homeLocation),
          sell(36, 60, at: homeLocation),
          sell(37, 10, at: homeLocation),
        ],
        mainOrders: [
          sell(34, 4, at: mainLocation),
          sell(35, 40, at: mainLocation),
          sell(36, 60, at: mainLocation),
          sell(37, 10, at: mainLocation),
        ]
      )
    )
    let rows = comparison.rows
    func ids(_ column: HubMineralComparisonColumn, _ ascending: Bool) -> [Int64] {
      HubMineralComparisonProjector.sorted(rows, by: column, ascending: ascending).map(\.id)
    }
    // Deviations: 34 +25 %, 35 −50 %, 36 and 37 0 %, all others missing.
    #expect(ids(.deviation, true) == [35, 36, 37, 34, 38, 39, 40, 11_399])
    #expect(ids(.deviation, false) == [38, 39, 40, 11_399, 34, 36, 37, 35])
    // Home prices 5, 20, 60, 10; missing after known ascending.
    #expect(ids(.homePrice, true) == [34, 37, 35, 36, 38, 39, 40, 11_399])
    #expect(ids(.homePrice, false) == [38, 39, 40, 11_399, 36, 35, 37, 34])
    #expect(ids(.mainPrice, true).prefix(4) == [34, 37, 35, 36])
    #expect(
      ids(.mineral, true) == [37, 40, 36, 11_399, 38, 35, 34, 39]
    )
    #expect(
      ids(.mineral, false) == [39, 34, 35, 38, 11_399, 36, 40, 37]
    )
    #expect(ids(.standardOrder, true) == HubMineralComparisonProjector.standardMineralOrder)
  }

  @Test
  func evenToneFollowsTheDisplayedDecimal() throws {
    let comparison = HubMineralComparisonProjector.project(
      standardAnalysis(
        homeOrders: [
          sell(34, 100.04, at: homeLocation),
          sell(35, 99.96, at: homeLocation),
          sell(36, 100.06, at: homeLocation),
        ],
        mainOrders: [
          sell(34, 100, at: mainLocation),
          sell(35, 100, at: mainLocation),
          sell(36, 100, at: mainLocation),
        ]
      )
    )
    let rows = Dictionary(uniqueKeysWithValues: comparison.rows.map { ($0.id, $0) })
    #expect(rows[34]?.displayedDeviationPercent == 0)
    #expect(rows[34]?.deviationTone == .even)
    let roundedNegative = try #require(rows[35]?.displayedDeviationPercent)
    #expect(roundedNegative == 0)
    #expect(roundedNegative.sign == .plus)
    #expect(rows[35]?.deviationTone == .even)
    #expect(rows[36]?.displayedDeviationPercent == 0.1)
    #expect(rows[36]?.deviationTone == .moreExpensiveAtHome)
  }

  @Test
  func priceFormatSwitchesToWholeISKFromOneThousand() {
    #expect(HubMineralPriceFormat.fractionDigits(for: 3.78) == 2)
    #expect(HubMineralPriceFormat.fractionDigits(for: 999.99) == 2)
    #expect(HubMineralPriceFormat.fractionDigits(for: 999.996) == 0)
    #expect(HubMineralPriceFormat.fractionDigits(for: 1_000) == 0)
    #expect(HubMineralPriceFormat.fractionDigits(for: 17_330) == 0)
  }
}
