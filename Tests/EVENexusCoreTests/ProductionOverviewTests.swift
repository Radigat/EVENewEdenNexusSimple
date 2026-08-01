import Testing

@testable import EVENexusCore

@Suite("Production overview")
struct ProductionOverviewTests {
  @Test
  func matchesTheExcelProductionOverviewFormulas() {
    let calculation = ProductionOverviewCalculation(
      units: 10,
      materialCost: 100,
      indexCost: 20,
      blueprintCost: 10,
      marketTax: 5,
      salePricePerUnit: 20,
      soldUnits: 4
    )

    #expect(calculation.productionCost == 135)
    #expect(calculation.saleTotal == 200)
    #expect(calculation.costPerUnit == 13.5)
    #expect(
      abs((calculation.minimumSalePricePerUnit ?? 0) - 14.85) < 0.000_001
    )
    #expect(calculation.projectedProfit == 65)
    #expect(calculation.margin == 0.325)
    #expect(calculation.realProfit == -55)
  }

  @Test
  func realProfitFollowsNotSoldPartialAndFullySoldQuantities() {
    func calculation(soldUnits: Int64) -> ProductionOverviewCalculation {
      ProductionOverviewCalculation(
        units: 10,
        materialCost: 100,
        indexCost: 20,
        blueprintCost: 10,
        marketTax: 5,
        salePricePerUnit: 20,
        soldUnits: soldUnits
      )
    }

    #expect(calculation(soldUnits: 0).realProfit == -135)
    #expect(calculation(soldUnits: 4).realProfit == -55)
    #expect(calculation(soldUnits: 10).realProfit == 65)
  }

  @Test
  func keepsUnavailableInputsUnavailableInsteadOfInventingZero() {
    let calculation = ProductionOverviewCalculation(
      units: 1,
      materialCost: 10,
      indexCost: 20,
      blueprintCost: nil,
      marketTax: 5,
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
      indexCost: 20,
      blueprintCost: -1,
      marketTax: 5,
      salePricePerUnit: .nan,
      soldUnits: 11
    )

    #expect(calculation.productionCost == nil)
    #expect(calculation.saleTotal == nil)
    #expect(calculation.projectedProfit == nil)
    #expect(calculation.realProfit == nil)
  }
}
