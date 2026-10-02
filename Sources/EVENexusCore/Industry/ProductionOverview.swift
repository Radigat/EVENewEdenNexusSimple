import Foundation

public struct ProductionOverviewCalculation: Equatable, Sendable {
  public let units: Int64
  public let materialCost: Double?
  public let installationCost: Double?
  public let blueprintCost: Double?
  public let logisticsCost: Double?
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let salePricePerUnit: Double?
  public let soldUnits: Int64

  public init(
    units: Int64,
    materialCost: Double?,
    installationCost: Double?,
    blueprintCost: Double?,
    logisticsCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    salePricePerUnit: Double?,
    soldUnits: Int64
  ) {
    self.units = units
    self.materialCost = materialCost
    self.installationCost = installationCost
    self.blueprintCost = blueprintCost
    self.logisticsCost = logisticsCost
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.salePricePerUnit = salePricePerUnit
    self.soldUnits = soldUnits
  }

  public var productionCost: Double? {
    guard
      let materialCost = validMoney(materialCost),
      let installationCost = validMoney(installationCost),
      let blueprintCost = validMoney(blueprintCost),
      let logisticsCost = validMoney(logisticsCost)
    else { return nil }
    let total =
      materialCost + installationCost + blueprintCost + logisticsCost
    return total.isFinite ? total : nil
  }

  public var saleTotal: Double? {
    guard units > 0, let price = validMoney(salePricePerUnit) else {
      return nil
    }
    let total = price * Double(units)
    return total.isFinite ? total : nil
  }

  public var salesTax: Double? {
    fee(amount: saleTotal, rate: salesTaxRate)
  }

  public var brokerFee: Double? {
    fee(amount: saleTotal, rate: brokerFeeRate)
  }

  public var netSaleTotal: Double? {
    guard let saleTotal, let salesTax, let brokerFee else { return nil }
    let total = saleTotal - salesTax - brokerFee
    return total.isFinite && total >= 0 ? total : nil
  }

  public var costPerUnit: Double? {
    guard units > 0 else { return nil }
    return productionCost.map { $0 / Double(units) }
  }

  public var minimumSalePricePerUnit: Double? {
    guard units > 0, let productionCost,
      let combinedRate = combinedFeeRate
    else { return nil }
    let retainedShare = 1 - combinedRate
    guard retainedShare > 0 else { return nil }
    let price = productionCost * 1.1 / retainedShare / Double(units)
    return price.isFinite && price >= 0 ? price : nil
  }

  public var projectedProfit: Double? {
    guard let netSaleTotal, let productionCost else { return nil }
    let profit = netSaleTotal - productionCost
    return profit.isFinite ? profit : nil
  }

  public var margin: Double? {
    guard let netSaleTotal, netSaleTotal != 0, let projectedProfit else {
      return nil
    }
    return projectedProfit / netSaleTotal
  }

  public var realProfit: Double? {
    guard soldUnits >= 0, soldUnits <= units,
      let salePricePerUnit = validMoney(salePricePerUnit),
      let salesTaxRate = validRate(salesTaxRate),
      let brokerFee,
      let productionCost
    else { return nil }
    let soldGross = salePricePerUnit * Double(soldUnits)
    let soldSalesTax = soldGross * salesTaxRate
    let profit = soldGross - soldSalesTax - brokerFee - productionCost
    return profit.isFinite ? profit : nil
  }

  private var combinedFeeRate: Double? {
    guard let salesTaxRate = validRate(salesTaxRate),
      let brokerFeeRate = validRate(brokerFeeRate)
    else { return nil }
    let combined = salesTaxRate + brokerFeeRate
    return combined.isFinite && combined < 1 ? combined : nil
  }

  private func fee(amount: Double?, rate: Double?) -> Double? {
    guard let amount = validMoney(amount), let rate = validRate(rate) else {
      return nil
    }
    let value = amount * rate
    return value.isFinite ? value : nil
  }

  private func validMoney(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }

  private func validRate(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0, value < 1 else {
      return nil
    }
    return value
  }
}

public struct ProductionOverviewRequestProjection: Equatable, Sendable {
  public let materialCost: Double?
  public let installationCost: Double?
  public let logisticsCost: Double?
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let suggestedSalePricePerUnit: Double?

  public init(
    materialCost: Double?,
    installationCost: Double?,
    logisticsCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    suggestedSalePricePerUnit: Double?
  ) {
    self.materialCost = materialCost
    self.installationCost = installationCost
    self.logisticsCost = logisticsCost
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.suggestedSalePricePerUnit = suggestedSalePricePerUnit
  }
}

public enum ProductionOverviewProjector {
  public static func projection(
    for requestID: UUID,
    in plan: IndustryPlanSnapshot
  ) -> ProductionOverviewRequestProjection? {
    guard
      let requestIndex = plan.requests.firstIndex(where: {
        $0.id == requestID
      })
    else { return nil }
    let materialCosts: [Double?] = plan.requests.map { request in
      materialCost(for: request.id, in: plan)
    }
    let knownMaterialTotal = materialCosts.compactMap { $0 }.reduce(0, +)
    let projectedMaterialCost = materialCosts[requestIndex]
    let requestCount = plan.requests.count
    let installationCost = allocate(
      plan.costBreakdown?.installationCost ?? plan.installationCost,
      requestMaterialCost: projectedMaterialCost,
      knownMaterialTotal: knownMaterialTotal,
      requestCount: requestCount
    )
    let logisticsCost = allocate(
      plan.costBreakdown?.effectiveLogisticsCost,
      requestMaterialCost: projectedMaterialCost,
      knownMaterialTotal: knownMaterialTotal,
      requestCount: requestCount
    )
    let salesTaxRate =
      scenarioRate(
        amount: plan.listedSale.salesTax,
        gross: plan.listedSale.grossRevenue
      )
      ?? scenarioRate(
        amount: plan.immediateSale.salesTax,
        gross: plan.immediateSale.grossRevenue
      )
    let brokerFeeRate = scenarioRate(
      amount: plan.listedSale.brokerFee,
      gross: plan.listedSale.grossRevenue
    )
    let productNode = plan.nodes.last {
      $0.topLevelRequestID == requestID && $0.action == .produce
    }
    let quote = productNode.flatMap { node in
      plan.listedSale.quotes.first {
        $0.typeID == node.typeID && $0.quantity == node.requiredQuantity
      }
    }
    let suggestedSalePricePerUnit = grossUnitPrice(
      quote: quote,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate
    )
    return ProductionOverviewRequestProjection(
      materialCost: projectedMaterialCost,
      installationCost: installationCost,
      logisticsCost: logisticsCost,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate,
      suggestedSalePricePerUnit: suggestedSalePricePerUnit
    )
  }

  private static func materialCost(
    for requestID: UUID,
    in plan: IndustryPlanSnapshot
  ) -> Double? {
    let materialInputs = plan.nodes.filter {
      $0.topLevelRequestID == requestID
        && ($0.action == .buy || $0.action == .useStock)
    }
    var total = 0.0
    for input in materialInputs {
      guard
        let material = plan.materials.first(where: {
          $0.typeID == input.typeID
        })
      else { return nil }
      let legacyQuote =
        input.action == .useStock ? material.stockQuote : material.quote
      guard
        let unitPrice =
          material.replacementQuote?.weightedUnitPrice
          ?? legacyQuote?.weightedUnitPrice,
        unitPrice.isFinite,
        unitPrice >= 0
      else { return nil }
      let updated = total + unitPrice * Double(input.requiredQuantity)
      guard updated.isFinite, updated >= 0 else { return nil }
      total = updated
    }
    return total
  }

  private static func allocate(
    _ total: Double?,
    requestMaterialCost: Double?,
    knownMaterialTotal: Double,
    requestCount: Int
  ) -> Double? {
    guard let total, total.isFinite, total >= 0 else { return nil }
    if knownMaterialTotal > 0, let requestMaterialCost {
      let allocated = total * requestMaterialCost / knownMaterialTotal
      return allocated.isFinite && allocated >= 0 ? allocated : nil
    }
    guard requestCount > 0 else { return nil }
    return total / Double(requestCount)
  }

  private static func scenarioRate(
    amount: Double?,
    gross: Double?
  ) -> Double? {
    guard let amount, let gross,
      amount.isFinite,
      gross.isFinite,
      amount >= 0,
      gross > 0
    else { return nil }
    let rate = amount / gross
    return rate.isFinite && rate >= 0 && rate < 1 ? rate : nil
  }

  private static func grossUnitPrice(
    quote: PriceQuote?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) -> Double? {
    guard let netUnitPrice = quote?.weightedUnitPrice,
      netUnitPrice.isFinite,
      netUnitPrice >= 0,
      let salesTaxRate,
      let brokerFeeRate
    else { return nil }
    let retainedShare = 1 - salesTaxRate - brokerFeeRate
    guard retainedShare > 0 else { return nil }
    let gross = netUnitPrice / retainedShare
    return gross.isFinite && gross >= 0 ? gross : nil
  }
}
