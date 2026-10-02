import Foundation
import Testing

@testable import EVENexusCore

@Suite("Production overview")
struct ProductionOverviewTests {
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
        grossOrNetRevenue: 1_880,
        profit: 330,
        margin: 330 / 1_880,
        roi: 330 / 1_550,
        quotes: [listedQuote]
      ),
      homeImmediateSale: nil,
      homeListedSale: nil,
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
}
