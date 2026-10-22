import Foundation
import Testing

@testable import EVENexusCore

@Suite("Trade calculator")
struct TradeCalculatorTests {
  @Test
  func priceStepsKeepFourSignificantDigits() {
    #expect(MarketPriceTick.nextBelow(706_000) == 705_900)
    #expect(MarketPriceTick.nextAbove(706_000) == 706_100)
    #expect(MarketPriceTick.nextBelow(5_490) == 5_489)
    #expect(MarketPriceTick.nextBelow(5.49) == 5.48)
    #expect(MarketPriceTick.nextAbove(5.49) == 5.5)
    // Crossing a power of ten changes the step on the lower side only.
    #expect(MarketPriceTick.nextBelow(1_000) == 999.9)
    #expect(MarketPriceTick.nextAbove(999.9) == 1_000)
    #expect(MarketPriceTick.nextBelow(100_000_000) == 99_990_000)
    #expect(MarketPriceTick.nextAbove(99_990_000) == 100_000_000)
    #expect(MarketPriceTick.nextAbove(100) == 100.1)
    // 0.01 ISK is the smallest valid price.
    #expect(MarketPriceTick.nextBelow(0.02) == 0.01)
    #expect(MarketPriceTick.nextBelow(0.01) == nil)
    #expect(MarketPriceTick.nextBelow(0) == nil)
    #expect(MarketPriceTick.nextAbove(.nan) == nil)
  }

  @Test
  func importRouteUsesInstantBuyListedSaleAndCourierVolumeCharge() throws {
    let row = TradeCalculator.row(
      item: item(
        volume: 10,
        source: summary(sell: 1_000_000, buy: 900_000),
        target: summary(sell: 1_500_000, buy: 1_200_000)
      ),
      mode: .mainToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: homeFees,
      transport: courierOnly
    )

    #expect(row.sourcePrice == 1_000_000)
    #expect(row.targetPrice == 1_500_000)
    #expect(close(row.differenceFraction, 0.5))
    #expect(row.purchaseCost == 1_000_000)
    // max(10 m³ × 1,000, 1,000,000 × 0.5 %) = 10,000
    #expect(close(row.transportCost, 10_000))
    // One step below 1,500,000 is 1,499,000; 3.6 % tax + 1.5 % broker.
    #expect(close(row.netSale, 1_499_000 * 0.949))
    let profit = 1_499_000 * 0.949 - 1_000_000 - 10_000
    #expect(close(row.profit, profit))
    #expect(close(row.margin, profit / (1_499_000 * 0.949)))
    #expect(close(row.returnOnInvestment, profit / 1_010_000))
    #expect(close(row.targetSpreadFraction, 0.25))
    #expect(row.issues.isEmpty)
  }

  @Test
  func buyOrderAddsBrokerFeeAndDirectSaleOnlyPaysTax() throws {
    let row = TradeCalculator.row(
      item: item(
        volume: 0.1,
        source: summary(sell: 1_000_000, buy: 900_000),
        target: summary(sell: 1_500_000, buy: 1_200_000)
      ),
      mode: .mainToHome,
      sourceSide: .maxBuy,
      targetSide: .maxBuy,
      sourceFees: TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.0135),
      targetFees: homeFees,
      transport: courierOnly
    )

    #expect(row.sourcePrice == 900_000)
    #expect(row.targetPrice == 1_200_000)
    #expect(close(row.differenceFraction, 1.0 / 3.0))
    // One step above 900,000 is 900,100.
    let cost = 900_100 * 1.0135
    #expect(close(row.purchaseCost, cost))
    // The collateral charge exceeds 0.1 m³ × 1,000.
    #expect(close(row.transportCost, cost * 0.005))
    #expect(close(row.netSale, 1_200_000 * 0.964))
    #expect(close(row.profit, 1_200_000 * 0.964 - cost - cost * 0.005))
  }

  @Test
  func listedSaleMatchesTheMarketPriceEngineOnTheSameGrossPrice() throws {
    let listedPrice = try #require(MarketPriceTick.nextBelow(1_500_000))
    let snapshot = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        34: [
          MarketOrder(
            id: 1,
            typeID: 34,
            locationID: EVEConstants.jitaIV4StationID,
            systemID: EVEConstants.jitaSystemID,
            side: .sell,
            price: listedPrice,
            volumeRemaining: 10,
            minimumVolume: 1,
            issued: .now
          )
        ]
      ],
      source: SourceIdentity(provider: "fixture", version: "1")
    )
    let engine = MarketPriceEngine.quote(
      typeID: 34,
      quantity: 1,
      scenario: .listedSale,
      snapshot: snapshot,
      salesTaxRate: 0.036,
      brokerFeeRate: 0.015
    )
    let row = TradeCalculator.row(
      item: item(
        volume: 1,
        source: summary(sell: 1_000_000, buy: nil),
        target: summary(sell: 1_500_000, buy: nil)
      ),
      mode: .mainToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: homeFees,
      targetFees: homeFees,
      transport: .none
    )

    #expect(close(row.netSale, try #require(engine.weightedUnitPrice)))
  }

  @Test
  func homeCoalitionRoutesUseOneStepOnBothSidesAndTheirLeg() {
    let fees = TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.02)
    let homeBook = summary(sell: 120, buy: 100)
    let coalitionBook = summary(sell: 110, buy: 95)
    let leg = TradeTransportBasis(legs: [freighterLeg])
    let towardsCoalition = TradeCalculator.row(
      item: item(volume: 1, source: homeBook, target: coalitionBook),
      mode: .homeToCoalition,
      sourceSide: .maxBuy,
      targetSide: .minSell,
      sourceFees: fees,
      targetFees: fees,
      transport: leg
    )

    // Buy order at 100.1, sell order at 109.9, full-load freighter share.
    let transport = 50_000_000.0 / 300_000
    #expect(close(towardsCoalition.purchaseCost, 100.1 * 1.02))
    #expect(close(towardsCoalition.transportCost, transport))
    #expect(close(towardsCoalition.netSale, 109.9 * 0.944))
    #expect(
      close(towardsCoalition.profit, 109.9 * 0.944 - 100.1 * 1.02 - transport)
    )
    #expect(close(towardsCoalition.targetSpreadFraction, 15.0 / 95.0))
    #expect(towardsCoalition.issues.isEmpty)

    // The opposite direction swaps the books: Home is now the target.
    let towardsHome = TradeCalculator.row(
      item: item(volume: 1, source: coalitionBook, target: homeBook),
      mode: .coalitionToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: fees,
      targetFees: fees,
      transport: leg
    )
    #expect(towardsHome.sourcePrice == 110)
    #expect(towardsHome.targetPrice == 120)
    #expect(close(towardsHome.differenceFraction, 10.0 / 110.0))
    // Without a resolved leg the transport stays unknown, never zero.
    let unresolved = TradeCalculator.row(
      item: item(volume: 1, source: coalitionBook, target: homeBook),
      mode: .coalitionToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: fees,
      targetFees: fees,
      transport: .none
    )
    #expect(unresolved.transportCost == nil)
    #expect(unresolved.issues == [.transportUnavailable])
  }

  @Test
  func missingInputsStayUnknownInsteadOfZero() {
    let noSource = TradeCalculator.row(
      item: item(volume: 10, source: nil, target: summary(sell: 100, buy: 90)),
      mode: .mainToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: homeFees,
      transport: courierOnly
    )
    #expect(noSource.sourcePrice == nil)
    #expect(noSource.differenceFraction == nil)
    #expect(noSource.purchaseCost == nil)
    #expect(noSource.transportCost == nil)
    #expect(noSource.profit == nil)
    #expect(noSource.netSale != nil)
    #expect(noSource.issues == [.missingSourcePrice])

    let noFeesRow = TradeCalculator.row(
      item: item(
        volume: 10,
        source: summary(sell: 100, buy: 90),
        target: summary(sell: 150, buy: nil)
      ),
      mode: .mainToHome,
      sourceSide: .maxBuy,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: noFees,
      transport: courierOnly
    )
    #expect(close(noFeesRow.differenceFraction, 150.0 / 90.0 - 1))
    #expect(noFeesRow.purchaseCost == nil)
    #expect(noFeesRow.netSale == nil)
    #expect(noFeesRow.targetSpreadFraction == nil)
    #expect(
      noFeesRow.issues == [.missingSourceBrokerFee, .missingTargetFees]
    )

    let noVolume = TradeCalculator.row(
      item: item(
        volume: nil,
        source: summary(sell: 100, buy: 90),
        target: summary(sell: 150, buy: 140)
      ),
      mode: .mainToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: homeFees,
      transport: courierOnly
    )
    #expect(noVolume.transportCost == nil)
    #expect(noVolume.profit == nil)
    #expect(noVolume.returnOnInvestment == nil)
    #expect(noVolume.issues == [.missingPackagedVolume])

    let noRoute = TradeCalculator.row(
      item: item(
        volume: 1,
        source: summary(sell: 100, buy: 90),
        target: summary(sell: 150, buy: 140)
      ),
      mode: .mainToCoalition,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: homeFees,
      transport: .none
    )
    #expect(noRoute.transportCost == nil)
    #expect(noRoute.issues == [.transportUnavailable])
  }

  @Test
  func coalitionRouteAddsCourierAndFullLoadJumpFreighterLegs() {
    let transport = TradeTransportBasis(legs: [courierLeg, freighterLeg])
    let perUnit = TradeCalculator.transportPerUnit(
      packagedVolume: 10,
      collateral: 1_000_000,
      transport: transport
    )
    // 10,000 courier + 50,000,000 ÷ 300,000 m³ × 10 m³.
    #expect(close(perUnit.cost, 10_000 + 50_000_000.0 / 300_000 * 10))
    #expect(perUnit.issues.isEmpty)

    let tooLarge = TradeCalculator.transportPerUnit(
      packagedVolume: 320_000,
      collateral: 1_000_000,
      transport: TradeTransportBasis(legs: [freighterLeg])
    )
    #expect(tooLarge.cost == nil)
    #expect(tooLarge.issues == [.exceedsJumpFreighterCapacity])

    let tooLargeForContract = TradeCalculator.transportPerUnit(
      packagedVolume: 400_000,
      collateral: 1_000_000,
      transport: courierOnly
    )
    #expect(tooLargeForContract.cost == nil)
    #expect(tooLargeForContract.issues == [.transportUnavailable])

    let unavailable = TradeCalculator.transportPerUnit(
      packagedVolume: 10,
      collateral: 1_000_000,
      transport: TradeTransportBasis(
        legs: [courierLeg, .unavailable(code: "jump-freighter.route-unavailable")]
      )
    )
    #expect(unavailable.cost == nil)
    #expect(unavailable.issues == [.transportUnavailable])
  }

  @Test
  func quantityQuoteRoundsContractsAndPaysEveryStartedFlight() {
    let courier = TradeCalculator.transportQuote(
      typeID: 34,
      name: "Fixture",
      quantity: 100,
      packagedVolumePerUnit: 10,
      unitCollateral: 1_000_000,
      transport: courierOnly
    )
    // 1,000 m³ × 1,000 = 1,000,000 exceeds 100 × 1,000,000 × 0.5 %.
    #expect(courier.total == 1_000_000)
    #expect(courier.perUnit == 10_000)

    let twoLegs = TradeCalculator.transportQuote(
      typeID: 34,
      name: "Fixture",
      quantity: 100,
      packagedVolumePerUnit: 10,
      unitCollateral: 1_000_000,
      transport: TradeTransportBasis(legs: [courierLeg, freighterLeg])
    )
    #expect(twoLegs.total == 51_000_000)

    let secondFlight = TradeCalculator.transportQuote(
      typeID: 34,
      name: "Fixture",
      quantity: 30_001,
      packagedVolumePerUnit: 10,
      unitCollateral: 1,
      transport: TradeTransportBasis(legs: [freighterLeg])
    )
    #expect(secondFlight.total == 100_000_000)

    let oversized = TradeCalculator.transportQuote(
      typeID: 34,
      name: "Fixture",
      quantity: 1,
      packagedVolumePerUnit: 400_000,
      unitCollateral: 1_000_000,
      transport: courierOnly
    )
    #expect(oversized.total == nil)
    #expect(oversized.issues == [.transportUnavailable])

    let noVolume = TradeCalculator.transportQuote(
      typeID: 34,
      name: "Fixture",
      quantity: 1,
      packagedVolumePerUnit: nil,
      unitCollateral: 1_000_000,
      transport: courierOnly
    )
    #expect(noVolume.total == nil)
    #expect(noVolume.issues.contains(.missingPackagedVolume))
  }

  @Test
  func rowsCarryTheDepthOfTheDisplayedPrices() {
    let source = MarketOrderTypeSummary(
      bestSellPrice: 100, bestBuyPrice: 90, bestSellVolume: 12, bestBuyVolume: 4
    )
    let target = MarketOrderTypeSummary(
      bestSellPrice: 150, bestBuyPrice: nil, bestSellVolume: 7, bestBuyVolume: nil
    )
    let listed = TradeCalculator.row(
      item: item(volume: 1, source: source, target: target),
      mode: .mainToHome,
      sourceSide: .minSell,
      targetSide: .minSell,
      sourceFees: noFees,
      targetFees: homeFees,
      transport: courierOnly
    )
    #expect(listed.sourceVolumeAtPrice == 12)
    #expect(listed.targetVolumeAtPrice == 7)

    let direct = TradeCalculator.row(
      item: item(volume: 1, source: source, target: target),
      mode: .mainToHome,
      sourceSide: .maxBuy,
      targetSide: .maxBuy,
      sourceFees: homeFees,
      targetFees: homeFees,
      transport: courierOnly
    )
    #expect(direct.sourceVolumeAtPrice == 4)
    #expect(direct.targetVolumeAtPrice == nil)
  }

  @Test
  func modesDescribeTheirHubsAndTransport() {
    // Station trading was removed; Home ↔ Coalition exists both ways.
    #expect(TradeMode.allCases == [
      .mainToHome, .mainToCoalition, .homeToCoalition, .coalitionToHome,
    ])
    #expect(TradeMode.mainToCoalition.sourceRole == .main)
    #expect(TradeMode.mainToCoalition.targetRole == .coalition)
    #expect(TradeMode.homeToCoalition.route == TradeRoute(source: .home, target: .coalition))
    #expect(TradeMode.coalitionToHome.route == TradeRoute(source: .coalition, target: .home))
    #expect(TradeMode.allCases.allSatisfy { $0.requiresTransport })
    #expect(!TradeRoute(source: .home, target: .home).requiresTransport)
    #expect(!TradeCalculator.includesOrderModificationFees)
  }

  private let noFees = TradeHubFees(salesTaxRate: nil, brokerFeeRate: nil)
  private let homeFees = TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.015)
  private let courierLeg = TradeTransportLeg.courier(
    TradeCourierLeg(
      origin: "Jita",
      destination: "Home",
      iskPerCubicMeter: 1_000
    )
  )
  private let freighterLeg = TradeTransportLeg.jumpFreighter(
    TradeJumpFreighterLeg(
      origin: "Home",
      destination: "Coalition",
      costPerFlight: 50_000_000,
      usableCargoCapacityM3: 300_000
    )
  )
  private var courierOnly: TradeTransportBasis {
    TradeTransportBasis(legs: [courierLeg])
  }

  private func item(
    volume: Double?,
    source: MarketOrderTypeSummary?,
    target: MarketOrderTypeSummary?
  ) -> TradeItemInput {
    TradeItemInput(
      typeID: 34,
      name: "Fixture",
      packagedVolume: volume,
      source: source,
      target: target
    )
  }

  private func summary(sell: Double?, buy: Double?) -> MarketOrderTypeSummary {
    MarketOrderTypeSummary(bestSellPrice: sell, bestBuyPrice: buy)
  }

  private func close(_ value: Double?, _ expected: Double) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= max(1e-9, abs(expected) * 1e-12)
  }
}

@Suite("Trade tiles, indicators and sorting")
struct TradeTileTests {
  private let groups = [
    MarketGroupDefinition(id: 1, parentID: nil, name: "Ship Equipment", hasTypes: true),
    MarketGroupDefinition(id: 10, parentID: 1, name: "Harvest Equipment", hasTypes: false),
    MarketGroupDefinition(id: 11, parentID: 10, name: "Mining Lasers", hasTypes: true),
    MarketGroupDefinition(id: 12, parentID: 1, name: "Armor", hasTypes: true),
    MarketGroupDefinition(id: 13, parentID: 1, name: "Empty", hasTypes: false),
    MarketGroupDefinition(id: 2, parentID: nil, name: "Materials", hasTypes: true),
  ]

  private func item(_ id: Int64, _ name: String, group: Int64) -> TradeCatalogItem {
    TradeCatalogItem(id: id, name: name, marketGroupID: group, packagedVolume: 1)
  }

  @Test
  func childGroupsBecomeTilesWithTheirWholeSubtree() throws {
    let node = try #require(groups.first { $0.id == 1 })
    let tiles = TradeTileBuilder.tiles(
      node: node,
      groups: groups,
      subtreeItems: [
        item(100, "Miner II", group: 11),
        item(101, "Miner I", group: 11),
        item(102, "Gas Scoop", group: 10),
        item(103, "Plate", group: 12),
        item(104, "Loose Module", group: 1),
      ]
    )

    // The node's own items come first, then children by name; the empty
    // child produces no tile.
    #expect(tiles.map(\.name) == ["Ship Equipment", "Armor", "Harvest Equipment"])
    #expect(tiles.map(\.kind) == [.nodeOwnItems, .childGroup, .childGroup])
    #expect(tiles[0].items.map(\.id) == [104])
    #expect(tiles[2].items.map(\.name) == ["Gas Scoop", "Miner I", "Miner II"])
    #expect(tiles[2].hasSubgroups)
    #expect(!tiles[1].hasSubgroups)
    #expect(Set(tiles.map(\.id)).count == tiles.count)
  }

  @Test
  func breadcrumbPathStopsAtCycles() {
    #expect(
      TradeTileBuilder.path(to: 11, groups: groups).map(\.id) == [1, 10, 11]
    )
    let cyclic = [
      MarketGroupDefinition(id: 5, parentID: 6, name: "A", hasTypes: true),
      MarketGroupDefinition(id: 6, parentID: 5, name: "B", hasTypes: true),
    ]
    #expect(TradeTileBuilder.path(to: 5, groups: cyclic).map(\.id) == [6, 5])
    #expect(TradeTileBuilder.path(to: 99, groups: groups).isEmpty)
  }

  @Test
  func differenceIndicatorUsesTheConfiguredThresholds() {
    typealias Indicator = TradeDifferenceIndicator
    #expect(Indicator.classify(nil) == nil)
    #expect(Indicator.classify(-0.0001) == .decrease)
    #expect(Indicator.classify(0) == .neutral)
    #expect(Indicator.classify(0.2499) == .neutral)
    #expect(Indicator.classify(0.25) == .increase)
    #expect(Indicator.classify(0.2999) == .increase)
    #expect(Indicator.classify(0.30) == .strongIncrease)
    #expect(
      Indicator.classify(0.15, increaseThreshold: 0.1, strongIncreaseThreshold: 0.2)
        == .increase
    )
    // A strong threshold below the single one never hides the single arrow.
    #expect(
      Indicator.classify(0.15, increaseThreshold: 0.1, strongIncreaseThreshold: 0.05)
        == .strongIncrease
    )
  }

  @Test
  func sortingKeepsUnknownValuesAfterKnownOnesAscending() {
    func display(_ id: Int64, _ name: String, profit: Double?, demand: Int64?)
      -> TradeDisplayRow
    {
      TradeDisplayRow(
        row: TradeRow(
          typeID: id,
          name: name,
          packagedVolume: nil,
          sourcePrice: nil,
          targetPrice: nil,
          differenceFraction: nil,
          purchaseCost: nil,
          transportCost: nil,
          netSale: nil,
          profit: profit,
          margin: nil,
          returnOnInvestment: nil,
          targetSpreadFraction: nil,
          issues: []
        ),
        currentDailyDemand: demand,
        averageDailyDemand: nil
      )
    }
    let rows = [
      display(4, "delta", profit: nil, demand: 3),
      display(3, "Charlie", profit: 10, demand: nil),
      display(2, "bravo", profit: 10, demand: 7),
      display(1, "Alpha", profit: -5, demand: 3),
    ]
    #expect(
      TradeRowSorter.sorted(rows, by: .profit, ascending: true).map(\.id)
        == [1, 2, 3, 4]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .profit, ascending: false).map(\.id)
        == [4, 2, 3, 1]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .currentDailyDemand, ascending: true).map(\.id)
        == [1, 4, 2, 3]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .name, ascending: true).map(\.id)
        == [1, 2, 3, 4]
    )
    #expect(
      TradeRowSorter.sorted(rows, by: .name, ascending: false).map(\.id)
        == [4, 3, 2, 1]
    )
  }
}
