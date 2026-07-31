import Foundation

public struct ProductionOverviewCalculation: Equatable, Sendable {
  public let units: Int64
  public let materialCost: Double?
  public let indexCost: Double?
  public let blueprintCost: Double?
  public let marketTax: Double?
  public let salePricePerUnit: Double?
  public let soldUnits: Int64

  public init(
    units: Int64,
    materialCost: Double?,
    indexCost: Double?,
    blueprintCost: Double?,
    marketTax: Double?,
    salePricePerUnit: Double?,
    soldUnits: Int64
  ) {
    self.units = units
    self.materialCost = materialCost
    self.indexCost = indexCost
    self.blueprintCost = blueprintCost
    self.marketTax = marketTax
    self.salePricePerUnit = salePricePerUnit
    self.soldUnits = soldUnits
  }

  public var productionCost: Double? {
    guard
      let materialCost = validMoney(materialCost),
      let indexCost = validMoney(indexCost),
      let blueprintCost = validMoney(blueprintCost),
      let marketTax = validMoney(marketTax)
    else { return nil }
    let total = materialCost + indexCost + blueprintCost + marketTax
    return total.isFinite ? total : nil
  }

  public var saleTotal: Double? {
    guard units > 0, let price = validMoney(salePricePerUnit) else {
      return nil
    }
    let total = price * Double(units)
    return total.isFinite ? total : nil
  }

  public var costPerUnit: Double? {
    guard units > 0 else { return nil }
    return productionCost.map { $0 / Double(units) }
  }

  public var minimumSalePricePerUnit: Double? {
    costPerUnit.map { $0 * 1.1 }
  }

  public var projectedProfit: Double? {
    guard let saleTotal, let productionCost else { return nil }
    return saleTotal - productionCost
  }

  public var margin: Double? {
    guard let saleTotal, saleTotal != 0, let projectedProfit else {
      return nil
    }
    return projectedProfit / saleTotal
  }

  public var realProfit: Double? {
    guard soldUnits >= 0, soldUnits <= units,
      let salePricePerUnit = validMoney(salePricePerUnit),
      let productionCost
    else { return nil }
    let profit = salePricePerUnit * Double(soldUnits) - productionCost
    return profit.isFinite ? profit : nil
  }

  private func validMoney(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }
}
