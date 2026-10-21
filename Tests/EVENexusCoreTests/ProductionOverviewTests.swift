import Foundation
import Testing

@testable import EVENexusCore

@Suite("Production overview")
struct ProductionOverviewTests {
  @Test
  func allocatesSharedRecursiveCostsOnceAcrossFinishedProducts() throws {
    let firstID = UUID()
    let secondID = UUID()
    let source = SourceIdentity(provider: "fixture", version: "1")
    func quote(typeID: Int64, quantity: Int64, total: Double) -> PriceQuote {
      PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy,
        total: total,
        weightedUnitPrice: total / Double(quantity),
        filledQuantity: quantity,
        capturedAt: Date(timeIntervalSince1970: 100),
        source: source,
        warnings: []
      )
    }
    let firstQuote = quote(typeID: 34, quantity: 10, total: 100)
    let secondQuote = quote(typeID: 35, quantity: 30, total: 300)
    let requests = [
      ProductionRequestLine(
        id: firstID,
        lineNumber: 1,
        productName: "First Product",
        wantedQuantity: 1,
        materialEfficiency: 0,
        timeEfficiency: 0
      ),
      ProductionRequestLine(
        id: secondID,
        lineNumber: 2,
        productName: "Second Product",
        wantedQuantity: 1,
        materialEfficiency: 0,
        timeEfficiency: 0
      ),
    ]
    let plan = IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: requests,
      nodes: [
        PlanNode(
          id: UUID(), typeID: 100, name: "First Product",
          requiredQuantity: 1, action: .produce, activity: .manufacturing,
          runs: 1, materialEfficiency: 0, timeEfficiency: 0, children: [],
          topLevelRequestID: firstID
        ),
        PlanNode(
          id: UUID(), typeID: 34, name: "First Material",
          requiredQuantity: 10, action: .buy, activity: nil, runs: nil,
          materialEfficiency: nil, timeEfficiency: nil, children: [],
          topLevelRequestID: firstID
        ),
        PlanNode(
          id: UUID(), typeID: 200, name: "Second Product",
          requiredQuantity: 1, action: .produce, activity: .manufacturing,
          runs: 1, materialEfficiency: 0, timeEfficiency: 0, children: [],
          topLevelRequestID: secondID
        ),
        PlanNode(
          id: UUID(), typeID: 35, name: "Second Material",
          requiredQuantity: 30, action: .buy, activity: nil, runs: nil,
          materialEfficiency: nil, timeEfficiency: nil, children: [],
          topLevelRequestID: secondID
        ),
      ],
      materials: [
        MaterialRequirement(
          typeID: 34, name: "First Material", required: 10, fromStock: 0,
          toBuy: 10, toProduce: 0, quote: firstQuote,
          replacementQuote: firstQuote
        ),
        MaterialRequirement(
          typeID: 35, name: "Second Material", required: 30, fromStock: 0,
          toBuy: 30, toProduce: 0, quote: secondQuote,
          replacementQuote: secondQuote
        ),
      ],
      stockAllocations: [],
      jobs: [],
      materialCost: 400,
      installationCost: 80,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 400,
        purchasedMaterialCost: 400,
        stockMaterialCost: 0,
        blueprintCosts: BlueprintCostBreakdown(
          entries: [], requestsWithoutEnteredCost: [], total: 40
        ),
        systemIndexCost: 80,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 80,
        logistics: nil,
        logisticsCost: 20,
        totalProductionCost: 540
      ),
      immediateSale: Self.emptySale(.immediateSale),
      listedSale: Self.emptySale(.listedSale),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: nil,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )

    let first = try #require(
      ProductionOverviewProjector.projection(for: firstID, in: plan)
    )
    let second = try #require(
      ProductionOverviewProjector.projection(for: secondID, in: plan)
    )
    #expect(first.materialCost == 100)
    #expect(second.materialCost == 300)
    #expect(first.installationCost == 20)
    #expect(second.installationCost == 60)
    #expect(first.blueprintCost == 10)
    #expect(second.blueprintCost == 30)
    #expect(first.logisticsCost == 5)
    #expect(second.logisticsCost == 15)

    var legacyObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(plan)
      ) as? [String: Any]
    )
    for key in [
      "mainContractSale",
      "homeContractSale",
      "coalitionImmediateSale",
      "coalitionListedSale",
      "coalitionContractSale",
    ] {
      legacyObject.removeValue(forKey: key)
    }
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let restored = try JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: legacyData
    )
    #expect(restored.mainContractSale == nil)
    #expect(restored.homeContractSale == nil)
    #expect(restored.coalitionImmediateSale == nil)
    #expect(restored.coalitionListedSale == nil)
    #expect(restored.coalitionContractSale == nil)
  }

  @Test
  func projectionCarriesLogisticsAndSeparateFeeRatesFromThePlanSnapshot()
    throws
  {
    let requestID = UUID()
    let source = SourceIdentity(provider: "fixture", version: "1")
    let materialQuote = PriceQuote(
      id: UUID(),
      typeID: 34,
      quantity: 10,
      scenario: .materialBuy,
      total: 1_000,
      weightedUnitPrice: 100,
      filledQuantity: 10,
      capturedAt: Date(timeIntervalSince1970: 100),
      source: source,
      warnings: []
    )
    let listedQuote = PriceQuote(
      id: UUID(),
      typeID: 100,
      quantity: 1,
      scenario: .listedSale,
      total: 1_880,
      weightedUnitPrice: 1_880,
      filledQuantity: 1,
      capturedAt: Date(timeIntervalSince1970: 100),
      source: source,
      warnings: []
    )
    let homeListedQuote = PriceQuote(
      id: UUID(),
      typeID: 100,
      quantity: 1,
      scenario: .listedSale,
      total: 1_275,
      weightedUnitPrice: 1_275,
      filledQuantity: 1,
      capturedAt: Date(timeIntervalSince1970: 100),
      source: source,
      warnings: []
    )
    let request = ProductionRequestLine(
      id: requestID,
      lineNumber: 1,
      productName: "Fixture Ship",
      wantedQuantity: 1,
      materialEfficiency: 4,
      timeEfficiency: 2,
      blueprintKind: .bpc,
      blueprintCostISK: 50
    )
    let plan = IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: [request],
      nodes: [
        PlanNode(
          id: UUID(),
          typeID: 100,
          name: "Fixture Ship",
          requiredQuantity: 1,
          action: .produce,
          activity: .manufacturing,
          runs: 1,
          materialEfficiency: 4,
          timeEfficiency: 2,
          children: [],
          topLevelRequestID: requestID
        ),
        PlanNode(
          id: UUID(),
          typeID: 34,
          name: "Fixture Mineral",
          requiredQuantity: 10,
          action: .buy,
          activity: nil,
          runs: nil,
          materialEfficiency: nil,
          timeEfficiency: nil,
          children: [],
          topLevelRequestID: requestID
        ),
      ],
      materials: [
        MaterialRequirement(
          typeID: 34,
          name: "Fixture Mineral",
          required: 10,
          fromStock: 0,
          toBuy: 10,
          toProduce: 0,
          quote: materialQuote,
          replacementQuote: materialQuote
        )
      ],
      stockAllocations: [],
      jobs: [],
      materialCost: 1_000,
      installationCost: 200,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 1_000,
        purchasedMaterialCost: 1_000,
        stockMaterialCost: 0,
        blueprintCosts: BlueprintCostBreakdown(
          entries: [
            BlueprintCostEntry(
              requestID: requestID,
              productName: "Fixture Ship",
              kind: .bpc,
              amount: 50,
              treatment: ManualBlueprintKind.bpc.costTreatment
            )
          ],
          requestsWithoutEnteredCost: [],
          total: 50
        ),
        systemIndexCost: 200,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 200,
        logistics: nil,
        logisticsCost: 300,
        totalProductionCost: 1_550
      ),
      immediateSale: SaleScenarioResult(
        scenario: .immediateSale,
        grossRevenue: 2_000,
        salesTax: 100,
        brokerFee: 0,
        outboundLogisticsCost: 400,
        totalCost: 1_950,
        grossOrNetRevenue: 1_900,
        profit: 350,
        margin: 350 / 1_900,
        roi: 350 / 1_550,
        quotes: []
      ),
      listedSale: SaleScenarioResult(
        scenario: .listedSale,
        grossRevenue: 2_000,
        salesTax: 100,
        brokerFee: 20,
        outboundLogisticsCost: 400,
        totalCost: 1_950,
        grossOrNetRevenue: 1_880,
        profit: 330,
        margin: 330 / 1_880,
        roi: 330 / 1_550,
        quotes: [listedQuote]
      ),
      mainContractSale: nil,
      homeImmediateSale: SaleScenarioResult(
        scenario: .immediateSale,
        grossRevenue: 1_400,
        salesTax: 140,
        brokerFee: 0,
        outboundLogisticsCost: 0,
        totalCost: 1_550,
        grossOrNetRevenue: 1_260,
        profit: -290,
        margin: -290 / 1_260,
        roi: -290 / 1_550,
        quotes: []
      ),
      homeListedSale: SaleScenarioResult(
        scenario: .listedSale,
        grossRevenue: 1_500,
        salesTax: 150,
        brokerFee: 75,
        outboundLogisticsCost: 0,
        totalCost: 1_550,
        grossOrNetRevenue: 1_275,
        profit: -275,
        margin: -275 / 1_275,
        roi: -275 / 1_550,
        quotes: [homeListedQuote]
      ),
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )

    let projection = try #require(
      ProductionOverviewProjector.projection(
        for: requestID,
        in: plan
      )
    )

    #expect(projection.materialCost == 1_000)
    #expect(projection.installationCost == 200)
    #expect(projection.blueprintCost == 50)
    #expect(projection.logisticsCost == 300)
    #expect(projection.salesTaxRate == 0.05)
    #expect(projection.brokerFeeRate == 0.01)
    #expect(projection.suggestedSalePricePerUnit == 2_000)
  }

  @Test
  func separatesProductionCostFromSaleFeesAndIncludesLogistics() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 10,
      logisticsCost: 5,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      salePricePerUnit: 20,
      soldUnits: 4
    )

    #expect(calculation.productionCost == 135)
    #expect(calculation.saleTotal == 200)
    #expect(calculation.salesTax == 10)
    #expect(calculation.brokerFee == 2)
    #expect(calculation.netSaleTotal == 188)
    #expect(calculation.costPerUnit == 13.5)
    #expect(
      abs((calculation.minimumSalePricePerUnit ?? 0) - 15.797_872_34)
        < 0.000_001
    )
    #expect(calculation.projectedProfit == 53)
    #expect(abs((calculation.margin ?? 0) - 53 / 188) < 0.000_001)
    #expect(calculation.realProfit == -61)
  }

  @Test
  func salePriceChangesRecalculateTaxAndBrokerFee() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 10,
      logisticsCost: 5,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      salePricePerUnit: 30,
      soldUnits: 10
    )

    #expect(calculation.saleTotal == 300)
    #expect(calculation.salesTax == 15)
    #expect(calculation.brokerFee == 3)
    #expect(calculation.projectedProfit == 147)
    #expect(calculation.realProfit == 147)
  }

  @Test
  func knownSalesTaxRemainsVisibleWhenBrokerFeeIsUnavailable() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 10,
      logisticsCost: 5,
      salesTaxRate: 0.05,
      brokerFeeRate: nil,
      salePricePerUnit: 20,
      soldUnits: 4
    )

    #expect(calculation.productionCost == 135)
    #expect(calculation.costPerUnit == 13.5)
    #expect(calculation.saleTotal == 200)
    #expect(calculation.salesTax == 10)
    #expect(calculation.brokerFee == nil)
    #expect(calculation.netSaleTotal == nil)
    #expect(calculation.minimumSalePricePerUnit == nil)
    #expect(calculation.projectedProfit == nil)
    #expect(calculation.margin == nil)
    #expect(calculation.realProfit == nil)
  }

  @Test
  func capitalWithoutApplicableBrokerFeeStillCalculatesMinimumAndProfit() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 10,
      logisticsCost: 5,
      salesTaxRate: 0.05,
      brokerFeeRate: nil,
      brokerFeeIsApplicable: false,
      salePricePerUnit: 20,
      soldUnits: 4
    )

    #expect(calculation.productionCost == 135)
    #expect(calculation.salesTax == 10)
    #expect(calculation.brokerFee == nil)
    #expect(calculation.netSaleTotal == 190)
    #expect(
      abs((calculation.minimumSalePricePerUnit ?? 0) - 15.631_578_947)
        < 0.000_001
    )
    #expect(calculation.projectedProfit == 55)
    #expect(abs((calculation.margin ?? 0) - 55 / 190) < 0.000_001)
    #expect(calculation.realProfit == -59)
  }

  @Test
  func missingRecordedFeeRatesUseCurrentMainHubRates() {
    let recorded = ProductionOverviewRequestProjection(
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 10,
      logisticsCost: 5,
      salesTaxRate: nil,
      brokerFeeRate: nil,
      suggestedSalePricePerUnit: nil
    )
    let projection = recorded.fillingMissingFeeRates(
      from: ProductionOverviewFeeRates(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    )

    #expect(projection.salesTaxRate == 0.05)
    #expect(projection.brokerFeeRate == 0.01)
    #expect(projection.salesTaxRateIsCurrentSetting)
    #expect(projection.brokerFeeRateIsCurrentSetting)

    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: projection.materialCost,
      installationCost: projection.installationCost,
      blueprintCost: projection.blueprintCost,
      logisticsCost: projection.logisticsCost,
      salesTaxRate: projection.salesTaxRate,
      brokerFeeRate: projection.brokerFeeRate,
      brokerFeeIsApplicable: projection.brokerFeeIsApplicable,
      salePricePerUnit: 20,
      soldUnits: 10
    )
    #expect(calculation.projectedProfit == 53)
    #expect(calculation.realProfit == 53)
  }

  @Test
  func recordedFeeRatesWinOverCurrentMainHubRates() {
    let recorded = ProductionOverviewRequestProjection(
      materialCost: 100,
      installationCost: 20,
      logisticsCost: 5,
      salesTaxRate: 0.04,
      brokerFeeRate: nil,
      brokerFeeIsApplicable: false,
      suggestedSalePricePerUnit: nil
    )

    let projection = recorded.fillingMissingFeeRates(
      from: ProductionOverviewFeeRates(salesTaxRate: 0.05, brokerFeeRate: 0.01)
    )

    #expect(projection == recorded)
    #expect(projection.brokerFeeRate == nil)
    #expect(!projection.salesTaxRateIsCurrentSetting)
    #expect(!projection.brokerFeeRateIsCurrentSetting)
    #expect(recorded.fillingMissingFeeRates(from: nil) == recorded)
  }

  @Test
  func unavailableCurrentRatesKeepMissingFeeRatesExplicit() {
    let recorded = ProductionOverviewRequestProjection(
      materialCost: 100,
      installationCost: 20,
      logisticsCost: 5,
      salesTaxRate: nil,
      brokerFeeRate: nil,
      suggestedSalePricePerUnit: nil
    )

    let projection = recorded.fillingMissingFeeRates(
      from: ProductionOverviewFeeRates(salesTaxRate: 0.05, brokerFeeRate: nil)
    )

    #expect(projection.salesTaxRate == 0.05)
    #expect(projection.brokerFeeRate == nil)
    #expect(projection.salesTaxRateIsCurrentSetting)
    #expect(!projection.brokerFeeRateIsCurrentSetting)
  }

  @Test
  func realProfitUsesSoldTaxAndFullListingBrokerFee() {
    func calculation(soldUnits: Int64) -> ProductionOverviewCalculation {
      ProductionOverviewCalculation(
        units: 10,
        materialCost: 100,
        installationCost: 20,
        blueprintCost: 10,
        logisticsCost: 5,
        salesTaxRate: 0.05,
        brokerFeeRate: 0.01,
        salePricePerUnit: 20,
        soldUnits: soldUnits
      )
    }

    #expect(calculation(soldUnits: 0).realProfit == -137)
    #expect(calculation(soldUnits: 4).realProfit == -61)
    #expect(calculation(soldUnits: 10).realProfit == 53)
  }

  @Test
  func keepsUnavailableProductionInputsUnavailableInsteadOfInventingZero() {
    let calculation = ProductionOverviewCalculation(
      units: 1,
      materialCost: 10,
      installationCost: 20,
      blueprintCost: 5,
      logisticsCost: nil,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      salePricePerUnit: 30,
      soldUnits: 1
    )

    #expect(calculation.productionCost == nil)
    #expect(calculation.costPerUnit == nil)
    #expect(calculation.minimumSalePricePerUnit == nil)
    #expect(calculation.projectedProfit == nil)
    #expect(calculation.margin == nil)
    #expect(calculation.realProfit == nil)
  }

  @Test
  func rejectsNonFiniteNegativeAndImpossibleStoredValues() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: .infinity,
      installationCost: 20,
      blueprintCost: -1,
      logisticsCost: 5,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      salePricePerUnit: .nan,
      soldUnits: 11
    )

    #expect(calculation.productionCost == nil)
    #expect(calculation.saleTotal == nil)
    #expect(calculation.projectedProfit == nil)
    #expect(calculation.realProfit == nil)
  }

  private static func targetMarketPlan(
    main: SaleScenarioResult,
    homeListed: SaleScenarioResult? = nil,
    coalitionContract: SaleScenarioResult? = nil
  ) -> IndustryPlanSnapshot {
    IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: [],
      nodes: [],
      materials: [],
      stockAllocations: [],
      jobs: [],
      materialCost: 0,
      installationCost: 0,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 0,
        purchasedMaterialCost: 0,
        stockMaterialCost: 0,
        blueprintCosts: BlueprintCostBreakdown(
          entries: [], requestsWithoutEnteredCost: [], total: 0
        ),
        systemIndexCost: 0,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 0,
        logistics: nil,
        logisticsCost: 0,
        totalProductionCost: 0
      ),
      immediateSale: main,
      listedSale: Self.emptySale(.listedSale),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: homeListed,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: coalitionContract,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )
  }

  private static func sale(
    _ scenario: PriceScenario,
    profit: Double?,
    grossRevenue: Double? = nil,
    contractFee: Double? = nil
  ) -> SaleScenarioResult {
    SaleScenarioResult(
      scenario: scenario,
      grossRevenue: grossRevenue,
      contractFee: contractFee,
      grossOrNetRevenue: nil,
      profit: profit,
      margin: nil,
      roi: nil,
      quotes: []
    )
  }

  @Test
  func targetMarketSuggestionPicksTheHighestFinalProfit() {
    let plan = Self.targetMarketPlan(
      main: Self.sale(.immediateSale, profit: 100),
      homeListed: Self.sale(.listedSale, profit: 250),
      // Higher, but still before the contract fee: never suggested.
      coalitionContract: Self.sale(
        .contractSale,
        profit: 900,
        grossRevenue: 1_000,
        contractFee: nil
      )
    )
    let suggestion = PlannerTargetMarketSuggestion.suggest(plan)
    #expect(suggestion?.market == .homeHub)
    #expect(suggestion?.profit == 250)

    let tie = Self.targetMarketPlan(
      main: Self.sale(.immediateSale, profit: 250),
      homeListed: Self.sale(.listedSale, profit: 250)
    )
    #expect(PlannerTargetMarketSuggestion.suggest(tie)?.market == .mainHub)

    let none = Self.targetMarketPlan(main: Self.sale(.immediateSale, profit: nil))
    #expect(PlannerTargetMarketSuggestion.suggest(none) == nil)
    #expect(PlannerTargetMarket(role: .coalition) == .coalitionHub)
  }

  @Test
  func targetMarketIsSavedInTheSnapshotAndOptionalForOldPlans() throws {
    var plan = Self.targetMarketPlan(main: Self.sale(.immediateSale, profit: 1))
    let legacy = try JSONEncoder().encode(plan)
    #expect(
      !(String(data: legacy, encoding: .utf8) ?? "").contains("targetMarket")
    )
    #expect(
      try JSONDecoder().decode(IndustryPlanSnapshot.self, from: legacy)
        .targetMarket == nil
    )
    plan.targetMarket = .coalitionHub
    let labeled = try JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: JSONEncoder().encode(plan)
    )
    #expect(labeled.targetMarket == .coalitionHub)
    #expect(labeled.immediateSale.profit == 1)
  }

  private static func alliancePlan(
    producedQuantity: Int64 = 10,
    totalProductionCost: Double? = 1_000,
    mainOutboundLogistics: Double? = 50,
    extraRequest: Bool = false
  ) -> IndustryPlanSnapshot {
    let requestID = UUID()
    var requests = [
      ProductionRequestLine(
        id: requestID,
        lineNumber: 1,
        productName: "Alliance Product",
        wantedQuantity: Int(producedQuantity),
        materialEfficiency: 0,
        timeEfficiency: 0
      )
    ]
    if extraRequest {
      requests.append(
        ProductionRequestLine(
          id: UUID(),
          lineNumber: 2,
          productName: "Second Product",
          wantedQuantity: 1,
          materialEfficiency: 0,
          timeEfficiency: 0
        )
      )
    }
    return IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: requests,
      nodes: [
        PlanNode(
          id: UUID(), typeID: 100, name: "Alliance Product",
          requiredQuantity: producedQuantity, action: .produce,
          activity: .manufacturing, runs: 1, materialEfficiency: 0,
          timeEfficiency: 0, children: [], topLevelRequestID: requestID
        )
      ],
      materials: [],
      stockAllocations: [],
      jobs: [],
      materialCost: 0,
      installationCost: 0,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 0,
        purchasedMaterialCost: 0,
        stockMaterialCost: 0,
        blueprintCosts: BlueprintCostBreakdown(
          entries: [], requestsWithoutEnteredCost: [], total: 0
        ),
        systemIndexCost: 0,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 0,
        logistics: nil,
        logisticsCost: 0,
        totalProductionCost: totalProductionCost
      ),
      immediateSale: Self.emptySale(.immediateSale),
      listedSale: SaleScenarioResult(
        scenario: .listedSale,
        outboundLogisticsCost: mainOutboundLogistics,
        grossOrNetRevenue: nil,
        profit: 1,
        margin: nil,
        roi: nil,
        quotes: []
      ),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: nil,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )
  }

  @Test
  func allianceSaleChargesFullCostAndSellsOnlyTheAcceptedUnits() {
    let plan = Self.alliancePlan()
    let result = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: PlannerAllianceSaleInput(
        unitPrice: 200,
        acceptedQuantity: 6,
        deliveryHub: .mainHub,
        feeRate: 0.05
      )
    )
    #expect(result.unavailableReason == nil)
    #expect(result.soldQuantity == 6)
    #expect(result.grossRevenue == 1_200)
    #expect(result.fee == 60)
    #expect(result.deliveryCost == 50)
    #expect(result.totalCost == 1_050)
    #expect(result.profit == 90)
    #expect(!result.feeIsManualAssumption)

    // No fee entered: 0 % as an explicit manual assumption, full output sold.
    let defaultFee = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: PlannerAllianceSaleInput(unitPrice: 150)
    )
    #expect(defaultFee.feeIsManualAssumption)
    #expect(defaultFee.fee == 0)
    #expect(defaultFee.soldQuantity == 10)
    #expect(defaultFee.deliveryCost == 0)
    #expect(defaultFee.profit == 500)
    #expect(
      PlannerAllianceSaleCalculator.offerText(
        for: defaultFee,
        formattedUnitPrice: "150 ISK",
        formattedTotal: "1,500 ISK"
      ) == "WTS 10× Alliance Product @ 150 ISK each (1,500 ISK total)"
    )
  }

  @Test
  func allianceSaleStaysUnavailableWithoutPriceRouteOrSingleProduct() {
    let plan = Self.alliancePlan()
    let noPrice = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: PlannerAllianceSaleInput()
    )
    #expect(noPrice.profit == nil)
    #expect(noPrice.unavailableReason != nil)
    #expect(
      PlannerAllianceSaleCalculator.offerText(
        for: noPrice,
        formattedUnitPrice: "-",
        formattedTotal: "-"
      ) == nil
    )
    let noRoute = PlannerAllianceSaleCalculator.calculate(
      plan: Self.alliancePlan(mainOutboundLogistics: nil),
      input: PlannerAllianceSaleInput(unitPrice: 200, deliveryHub: .mainHub)
    )
    #expect(noRoute.profit == nil)
    #expect(noRoute.deliveryCost == nil)
    // A missing Coalition scenario never becomes free transport.
    let noCoalition = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: PlannerAllianceSaleInput(unitPrice: 200, deliveryHub: .coalitionHub)
    )
    #expect(noCoalition.profit == nil)
    let twoProducts = PlannerAllianceSaleCalculator.calculate(
      plan: Self.alliancePlan(extraRequest: true),
      input: PlannerAllianceSaleInput(unitPrice: 200)
    )
    #expect(twoProducts.profit == nil)
    let noCost = PlannerAllianceSaleCalculator.calculate(
      plan: Self.alliancePlan(totalProductionCost: nil),
      input: PlannerAllianceSaleInput(unitPrice: 200)
    )
    #expect(noCost.grossRevenue == 2_000)
    #expect(noCost.profit == nil)
    #expect(noCost.unavailableReason != nil)
    #expect(
      PlannerAllianceSaleCalculator.calculate(
        plan: plan,
        input: PlannerAllianceSaleInput(unitPrice: 200, feeRate: 1.2)
      ).profit == nil
    )
  }

  @Test
  func allianceMarketCanBeSuggestedAndOldSnapshotsStayReadable() throws {
    var plan = Self.alliancePlan()
    // The listed Main-Hub card earns 1 ISK; the alliance deal earns more.
    plan.allianceSale = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: PlannerAllianceSaleInput(unitPrice: 150)
    )
    #expect(PlannerTargetMarketSuggestion.suggest(plan)?.market == .allianceMarket)
    plan.targetMarket = .allianceMarket
    let decoded = try JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: JSONEncoder().encode(plan)
    )
    #expect(decoded.targetMarket == .allianceMarket)
    #expect(decoded.allianceSale?.profit == 500)
    // A P10 snapshot without the new field still decodes.
    var older = Self.alliancePlan()
    older.targetMarket = .homeHub
    let olderData = try JSONEncoder().encode(older)
    #expect(!(String(data: olderData, encoding: .utf8) ?? "").contains("allianceSale"))
    let olderDecoded = try JSONDecoder().decode(IndustryPlanSnapshot.self, from: olderData)
    #expect(olderDecoded.allianceSale == nil)
    #expect(olderDecoded.targetMarket == .homeHub)
  }

  private static func emptySale(
    _ scenario: PriceScenario
  ) -> SaleScenarioResult {
    SaleScenarioResult(
      scenario: scenario,
      grossOrNetRevenue: nil,
      profit: nil,
      margin: nil,
      roi: nil,
      quotes: []
    )
  }
}
