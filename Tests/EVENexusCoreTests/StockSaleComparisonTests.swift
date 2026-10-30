import Foundation
import Testing

@testable import EVENexusCore

@Suite("Stock sale comparison")
struct StockSaleComparisonTests {
  // MARK: Paste parser

  @Test
  func parsesInventoryTabLinesWithEnglishAndGermanSeparators() {
    let result = StockSalePasteParser.parse(
      """
      Tritanium\t1,000,000\tMineral\t\t\t10,000 m3\t5,000,000.00 ISK
      Pyerite\t1.234.567\tMineral
      Raven\t\tBattleship
      Mexallon\t12 345
      """
    )
    #expect(result.errors.isEmpty)
    #expect(
      result.lines.map(\.candidates) == [
        [StockSaleNameCandidate(name: "Tritanium", quantity: 1_000_000)],
        [StockSaleNameCandidate(name: "Pyerite", quantity: 1_234_567)],
        [StockSaleNameCandidate(name: "Raven", quantity: 1)],
        [StockSaleNameCandidate(name: "Mexallon", quantity: 12_345)],
      ]
    )
    #expect(result.lines.map(\.lineNumber) == [1, 2, 3, 4])
  }

  @Test
  func assetCopyWithGroupBeforeQuantityAndExtraColumnsUsesFirstNumericColumn() {
    let result = StockSalePasteParser.parse(
      """
      Arazu\tForce Recon Ship\t5
      Scourge Precision Cruise Missile\tAdvanced Cruise Missile\t66889
      Tremor S\tAdvanced Artillery Ammo\t92.000\tCharge\t\t920 m3\t1.234.567,00 ISK
      Expanded Cargohold II\tExpanded Cargohold\t62\tModule\tLow
      Guardian\tLogistics\t\tShip\t\t115.000 m3
      Damage Control II\tDamage Control\t1 500\t
      """
    )
    #expect(result.errors.isEmpty)
    #expect(
      result.lines.map(\.candidates) == [
        [StockSaleNameCandidate(name: "Arazu", quantity: 5)],
        [StockSaleNameCandidate(name: "Scourge Precision Cruise Missile", quantity: 66_889)],
        [StockSaleNameCandidate(name: "Tremor S", quantity: 92_000)],
        [StockSaleNameCandidate(name: "Expanded Cargohold II", quantity: 62)],
        [StockSaleNameCandidate(name: "Guardian", quantity: 1)],
        [StockSaleNameCandidate(name: "Damage Control II", quantity: 1_500)],
      ]
    )
  }

  @Test
  func linesWithoutTabTryTheWholeNameBeforeATrailingQuantity() {
    let result = StockSalePasteParser.parse(
      """
      Warrior II x 25
      Hobgoblin II x10
      Hammerhead II 1 500
      Antimatter Charge S
      """
    )
    #expect(result.errors.isEmpty)
    #expect(
      result.lines.map(\.candidates) == [
        [
          StockSaleNameCandidate(name: "Warrior II x 25", quantity: 1),
          StockSaleNameCandidate(name: "Warrior II", quantity: 25),
        ],
        [
          StockSaleNameCandidate(name: "Hobgoblin II x10", quantity: 1),
          StockSaleNameCandidate(name: "Hobgoblin II", quantity: 10),
        ],
        [
          StockSaleNameCandidate(name: "Hammerhead II 1 500", quantity: 1),
          StockSaleNameCandidate(name: "Hammerhead II", quantity: 1_500),
        ],
        [StockSaleNameCandidate(name: "Antimatter Charge S", quantity: 1)],
      ]
    )
  }

  @Test
  func invalidQuantitiesAndLimitsStayExplicitErrors() {
    let result = StockSalePasteParser.parse(
      "Tritanium\t0\nPyerite\tMineral\t99999999999999999\nMexallon\t5"
    )
    #expect(result.lines.map(\.candidates.first?.name) == ["Mexallon"])
    #expect(result.errors.map(\.reason) == [.invalidQuantity, .invalidQuantity])
    #expect(result.errors.map(\.lineNumber) == [1, 2])

    let tooLarge = String(repeating: "a", count: StockSalePasteParser.maximumInputBytes + 1)
    #expect(StockSalePasteParser.parse(tooLarge).errors.map(\.reason) == [.inputTooLarge])

    let many = (0...StockSalePasteParser.maximumLineCount).map { "Item \($0)\t1" }
      .joined(separator: "\n")
    let limited = StockSalePasteParser.parse(many)
    #expect(limited.lines.count == StockSalePasteParser.maximumLineCount)
    #expect(limited.errors.map(\.reason) == [.tooManyLines])

    #expect(StockSalePasteParser.parseQuantity("1’000") == 1_000)
    #expect(StockSalePasteParser.parseQuantity("1\u{00A0}000") == 1_000)
    #expect(StockSalePasteParser.parseQuantity("-5") == nil)
    #expect(StockSalePasteParser.parseQuantity("2000000000") == nil)
  }

  // MARK: Stored list

  @Test
  func mergingSumsTypesReplacesOnRequestAndKeepsUnresolvedLines() throws {
    let existing = [
      StockSaleEntry(typeID: 34, resolvedName: "Tritanium", pastedName: "Tritanium", quantity: 10)
    ]
    let pasted = [
      StockSaleEntry(typeID: 34, resolvedName: "Tritanium", pastedName: "Tritanium", quantity: 5),
      StockSaleEntry(typeID: 35, resolvedName: "Pyerite", pastedName: "Pyerit", quantity: 2),
      StockSaleEntry(
        typeID: nil, resolvedName: nil, pastedName: "Unbekannt", quantity: 1,
        unresolvedReason: .unknownName
      ),
      StockSaleEntry(
        typeID: nil, resolvedName: nil, pastedName: "Unbekannt", quantity: 1,
        unresolvedReason: .unknownName
      ),
    ]
    let merged = StockSaleEntryList.merging(existing, with: pasted, replacing: false)
    #expect(merged.map(\.quantity) == [15, 2, 1])
    #expect(merged[1].hasDifferentPastedName)
    #expect(!merged[0].hasDifferentPastedName)
    #expect(merged[2].unresolvedReason == .unknownName)

    let replaced = StockSaleEntryList.merging(existing, with: [pasted[1]], replacing: true)
    #expect(replaced.map(\.typeID) == [35])

    let overflow = StockSaleEntryList.merging(
      [
        StockSaleEntry(
          typeID: 34, resolvedName: "Tritanium", pastedName: "Tritanium",
          quantity: StockSalePasteParser.maximumQuantity
        )
      ],
      with: [pasted[0]],
      replacing: false
    )
    #expect(overflow.first?.quantity == StockSalePasteParser.maximumQuantity)
    #expect(overflow.last?.unresolvedReason == .invalidQuantity)
    #expect(overflow.last?.typeID == nil)

    let decoded = try StockSaleEntryList.decode(StockSaleEntryList.encode(merged))
    #expect(decoded == merged)

    let cleaned = StockSaleEntryList.removingUnresolved(merged)
    #expect(cleaned.map(\.typeID) == [34, 35])
    #expect(cleaned.map(\.quantity) == [15, 2])
  }

  // MARK: Calculator

  @Test
  func minimumPricesInvertTheNetRevenueRules() throws {
    let row = StockSaleComparisonCalculator.row(
      typeID: 1,
      name: "Item",
      quantity: 10,
      cost: cost(perUnit: 94),
      prices: MarketOrderTypeSummary(
        bestSellPrice: 120,
        bestBuyPrice: 100,
        bestSellVolume: 3,
        bestBuyVolume: 20
      ),
      fees: TradeHubFees(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    )
    let minimumListing = try #require(row.minimumListingPrice)
    let minimumDirect = try #require(row.minimumDirectSalePrice)
    #expect(abs(minimumListing - 100) < 1e-9)
    #expect(abs(minimumDirect - 94 / 0.95) < 1e-9)
    #expect(row.ownSellOrderPrice == 119.9)
    let listingPerUnit = try #require(row.listingProfitPerUnit)
    let directPerUnit = try #require(row.directProfitPerUnit)
    #expect(abs(listingPerUnit - (119.9 * 0.94 - 94)) < 1e-9)
    #expect(abs(directPerUnit - (100 * 0.95 - 94)) < 1e-9)
    #expect(abs((row.listingProfitTotal ?? 0) - listingPerUnit * 10) < 1e-9)
    #expect(row.directDepth == .sufficient)
    #expect(row.listingReachesMinimum == true)
    #expect(row.directReachesMinimum == true)
    #expect(row.recommendation == .listedSale)
  }

  @Test
  func shallowBuyDepthIsFlaggedButStillValued() {
    let row = StockSaleComparisonCalculator.row(
      typeID: 1,
      name: "Item",
      quantity: 10,
      cost: cost(perUnit: 50),
      prices: MarketOrderTypeSummary(bestSellPrice: nil, bestBuyPrice: 100, bestBuyVolume: 4),
      fees: TradeHubFees(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    )
    #expect(row.directDepth == .insufficient)
    #expect(abs((row.directProfitTotal ?? 0) - 450) < 1e-9)
    #expect(row.listingProfitTotal == nil)
    #expect(row.recommendation == .directSale)
    #expect(abs((row.recommendedProfitTotal ?? 0) - 450) < 1e-9)
  }

  @Test
  func recommendationPrefersDirectSaleOnTieAndKeepsBelowBreakEven() {
    #expect(
      StockSaleComparisonCalculator.recommend(listingTotal: 10, directTotal: 10).0 == .directSale
    )
    #expect(
      StockSaleComparisonCalculator.recommend(listingTotal: 11, directTotal: 10).0 == .listedSale
    )
    let keep = StockSaleComparisonCalculator.recommend(listingTotal: -5, directTotal: 0)
    #expect(keep.0 == .keep)
    #expect(keep.1 == 0)
    #expect(StockSaleComparisonCalculator.recommend(listingTotal: nil, directTotal: nil).0 == nil)
  }

  @Test
  func unknownCostsFeesOrPricesStayUnknownInsteadOfZero() {
    let noFees = StockSaleComparisonCalculator.row(
      typeID: 1, name: "Item", quantity: 1, cost: cost(perUnit: 10),
      prices: MarketOrderTypeSummary(bestSellPrice: 20, bestBuyPrice: 15),
      fees: TradeHubFees(salesTaxRate: nil, brokerFeeRate: nil)
    )
    #expect(noFees.minimumListingPrice == nil)
    #expect(noFees.minimumDirectSalePrice == nil)
    #expect(noFees.listingProfitTotal == nil)
    #expect(noFees.recommendation == nil)

    let noBroker = StockSaleComparisonCalculator.row(
      typeID: 1, name: "Item", quantity: 1, cost: cost(perUnit: 10),
      prices: MarketOrderTypeSummary(bestSellPrice: 20, bestBuyPrice: 15),
      fees: TradeHubFees(salesTaxRate: 0.05, brokerFeeRate: nil)
    )
    #expect(noBroker.minimumListingPrice == nil)
    #expect(noBroker.minimumDirectSalePrice != nil)
    #expect(noBroker.recommendation == .directSale)

    let noScan = StockSaleComparisonCalculator.row(
      typeID: 1, name: "Item", quantity: 1, cost: nil,
      prices: MarketOrderTypeSummary(bestSellPrice: 20, bestBuyPrice: 15),
      fees: TradeHubFees(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    )
    #expect(noScan.bestSellPrice == 20)
    #expect(noScan.minimumListingPrice == nil)
    #expect(noScan.directProfitPerUnit == nil)
    #expect(noScan.directDepth == .unknown)
  }

  // MARK: Sorter

  @Test
  func unknownValuesStayLastInBothDirectionsWithTypeTieBreaker() {
    let fees = TradeHubFees(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    let rows = [
      StockSaleComparisonCalculator.row(
        typeID: 3, name: "C", quantity: 1, cost: nil, prices: nil, fees: fees
      ),
      StockSaleComparisonCalculator.row(
        typeID: 2, name: "B", quantity: 1, cost: cost(perUnit: 10),
        prices: MarketOrderTypeSummary(bestSellPrice: nil, bestBuyPrice: 20), fees: fees
      ),
      StockSaleComparisonCalculator.row(
        typeID: 1, name: "A", quantity: 1, cost: cost(perUnit: 10),
        prices: MarketOrderTypeSummary(bestSellPrice: nil, bestBuyPrice: 20), fees: fees
      ),
      StockSaleComparisonCalculator.row(
        typeID: 4, name: "D", quantity: 1, cost: cost(perUnit: 10),
        prices: MarketOrderTypeSummary(bestSellPrice: nil, bestBuyPrice: 40), fees: fees
      ),
    ]
    #expect(
      StockSaleRowSorter.sorted(rows, by: .recommendation, ascending: false).map(\.typeID)
        == [4, 1, 2, 3]
    )
    #expect(
      StockSaleRowSorter.sorted(rows, by: .recommendation, ascending: true).map(\.typeID)
        == [1, 2, 4, 3]
    )
    #expect(
      StockSaleRowSorter.sorted(rows, by: .name, ascending: false).map(\.typeID) == [4, 3, 2, 1]
    )
  }

  // MARK: New production cost

  @Test
  func productionCostScalesRunsAndChargesFullInboundLogistics() throws {
    let row = opportunityRow()
    let snapshot = opportunitySnapshot(rows: [row])
    let cost = try #require(
      StockSaleProductionCostProjector.project(
        row: row,
        quantity: 25,
        materialEfficiency: 0,
        timeEfficiency: 0,
        buildsIntermediates: false,
        sheet: ManufacturingOpportunityCostSheet(),
        contract: ManufacturingOpportunityContractContext(references: nil, contractFeeRate: nil),
        snapshot: snapshot
      )
    )
    #expect(cost.runs == 3)
    #expect(cost.producedQuantity == 30)
    #expect(cost.materialEfficiency == 0)
    let material = try #require(cost.materialCostPerUnit)
    let installation = try #require(cost.installationCostPerUnit)
    let logistics = try #require(cost.logisticsCostPerUnit)
    let total = try #require(cost.costPerUnit)
    #expect(abs(material - 10) < 1e-9)
    #expect(abs(installation - 0.5) < 1e-9)
    // Inbound material and outbound product legs, each rounded to 1 M ISK.
    #expect(abs(logistics - 2_000_000.0 / 30) < 1e-6)
    #expect(
      abs(total - (material + installation + (cost.blueprintCostPerUnit ?? 0) + logistics)) < 1e-6)

    #expect(
      StockSaleProductionCostProjector.project(
        row: row, quantity: 0, materialEfficiency: 0, timeEfficiency: 0,
        buildsIntermediates: false, sheet: ManufacturingOpportunityCostSheet(),
        contract: ManufacturingOpportunityContractContext(references: nil, contractFeeRate: nil),
        snapshot: snapshot
      ) == nil
    )
  }

  // MARK: Fixtures

  private func cost(perUnit: Double) -> StockSaleProductionCost {
    StockSaleProductionCost(
      runs: 1,
      producedQuantity: 1,
      materialEfficiency: 10,
      timeEfficiency: 20,
      materialCostPerUnit: perUnit,
      installationCostPerUnit: 0,
      blueprintCostPerUnit: 0,
      logisticsCostPerUnit: 0,
      costPerUnit: perUnit,
      warnings: []
    )
  }

  private func opportunityRow() -> ManufacturingOpportunityRow {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    return ManufacturingOpportunityRow(
      blueprintTypeID: 1_001,
      productTypeID: 1_000,
      productName: "Product",
      categoryName: "Module",
      groupName: "Group",
      facilityName: "Home Factory",
      runs: 1,
      outputPerRun: 10,
      producedQuantity: 10,
      materialEfficiency: 0,
      timeEfficiency: 0,
      durationSeconds: 60,
      observedDailyDemand: nil,
      activeBuyDemand: 0,
      activeSellSupply: 0,
      materials: [
        ManufacturingOpportunityMaterial(
          typeID: 34,
          name: "Material",
          quantity: 10,
          quote: PriceQuote(
            id: UUID(),
            typeID: 34,
            quantity: 10,
            scenario: .materialBuy,
            total: 100,
            weightedUnitPrice: 10,
            filledQuantity: 10,
            capturedAt: .now,
            source: source,
            warnings: []
          ),
          packagedVolumePerUnit: 1
        )
      ],
      materialCost: 100,
      installationCost: 5,
      productionCostBeforeBlueprintAndLogistics: 105,
      grossRevenue: 200,
      salesTax: 10,
      brokerFee: 2,
      netRevenue: 188,
      contributionProfit: 83,
      returnOnInvestment: 83.0 / 105.0,
      iskPerHour: 1,
      iskPerCubicMeter: 1,
      packagedVolumePerUnit: 1,
      warnings: []
    )
  }

  private func opportunitySnapshot(
    rows: [ManufacturingOpportunityRow]
  ) -> ManufacturingOpportunitySnapshot {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    return ManufacturingOpportunitySnapshot(
      settings: ManufacturingOpportunitySettings(),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      logisticsConfiguration: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        includeOutboundProducts: false,
        productionLocationName: "Home Factory",
        homeTradeHub: .legacy(name: "Home Factory"),
        iskPerCubicMeter: 100
      ),
      rows: rows,
      coverage: ManufacturingOpportunityCoverage(
        completeManufacturingDefinitionCount: rows.count,
        mainHubActiveOrderTypeCount: rows.count,
        candidateCount: rows.count,
        candidatesWithSellOrders: rows.count,
        candidatesWithBuyOrders: rows.count
      ),
      sdeSource: source,
      marketSource: source,
      warnings: []
    )
  }
}
