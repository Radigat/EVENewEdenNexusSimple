import Foundation

public struct ProductionOverviewCalculation: Equatable, Sendable {
  public let units: Int64
  public let materialCost: Double?
  public let installationCost: Double?
  public let blueprintCost: Double?
  public let logisticsCost: Double?
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let brokerFeeIsApplicable: Bool
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
    brokerFeeIsApplicable: Bool = true,
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
    self.brokerFeeIsApplicable = brokerFeeIsApplicable
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
    guard brokerFeeIsApplicable else { return nil }
    return fee(amount: saleTotal, rate: brokerFeeRate)
  }

  public var netSaleTotal: Double? {
    guard let saleTotal, let salesTax, let appliedBrokerFee else { return nil }
    let total = saleTotal - salesTax - appliedBrokerFee
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
      let appliedBrokerFee,
      let productionCost
    else { return nil }
    let soldGross = salePricePerUnit * Double(soldUnits)
    let soldSalesTax = soldGross * salesTaxRate
    let profit = soldGross - soldSalesTax - appliedBrokerFee - productionCost
    return profit.isFinite ? profit : nil
  }

  private var combinedFeeRate: Double? {
    guard let salesTaxRate = validRate(salesTaxRate) else { return nil }
    let brokerFeeRate: Double
    if brokerFeeIsApplicable {
      guard let knownBrokerFeeRate = validRate(self.brokerFeeRate) else {
        return nil
      }
      brokerFeeRate = knownBrokerFeeRate
    } else {
      brokerFeeRate = 0
    }
    let combined = salesTaxRate + brokerFeeRate
    return combined.isFinite && combined < 1 ? combined : nil
  }

  private var appliedBrokerFee: Double? {
    brokerFeeIsApplicable ? brokerFee : 0
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
  public let blueprintCost: Double?
  public let logisticsCost: Double?
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let brokerFeeIsApplicable: Bool
  public let suggestedSalePricePerUnit: Double?
  /// The sales-tax rate was missing from the stored plan and comes from the
  /// current Main Hub settings instead.
  public let salesTaxRateIsCurrentSetting: Bool
  /// The broker-fee rate was missing from the stored plan and comes from the
  /// current Main Hub settings instead.
  public let brokerFeeRateIsCurrentSetting: Bool

  public init(
    materialCost: Double?,
    installationCost: Double?,
    blueprintCost: Double? = nil,
    logisticsCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    brokerFeeIsApplicable: Bool = true,
    suggestedSalePricePerUnit: Double?,
    salesTaxRateIsCurrentSetting: Bool = false,
    brokerFeeRateIsCurrentSetting: Bool = false
  ) {
    self.materialCost = materialCost
    self.installationCost = installationCost
    self.blueprintCost = blueprintCost
    self.logisticsCost = logisticsCost
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.brokerFeeIsApplicable = brokerFeeIsApplicable
    self.suggestedSalePricePerUnit = suggestedSalePricePerUnit
    self.salesTaxRateIsCurrentSetting = salesTaxRateIsCurrentSetting
    self.brokerFeeRateIsCurrentSetting = brokerFeeRateIsCurrentSetting
  }

  /// Completes fee rates that the stored plan did not record with the
  /// current Main Hub rates. Recorded rates always win, and a broker fee
  /// that was not applicable stays not applicable.
  public func fillingMissingFeeRates(
    from current: ProductionOverviewFeeRates?
  ) -> ProductionOverviewRequestProjection {
    guard let current else { return self }
    let storedSalesTaxRate = Self.validRate(salesTaxRate)
    let storedBrokerFeeRate = Self.validRate(brokerFeeRate)
    let fallbackSalesTaxRate =
      storedSalesTaxRate == nil ? Self.validRate(current.salesTaxRate) : nil
    let fallbackBrokerFeeRate =
      brokerFeeIsApplicable && storedBrokerFeeRate == nil
      ? Self.validRate(current.brokerFeeRate) : nil
    guard fallbackSalesTaxRate != nil || fallbackBrokerFeeRate != nil else {
      return self
    }
    return ProductionOverviewRequestProjection(
      materialCost: materialCost,
      installationCost: installationCost,
      blueprintCost: blueprintCost,
      logisticsCost: logisticsCost,
      salesTaxRate: storedSalesTaxRate ?? fallbackSalesTaxRate,
      brokerFeeRate: storedBrokerFeeRate ?? fallbackBrokerFeeRate,
      brokerFeeIsApplicable: brokerFeeIsApplicable,
      suggestedSalePricePerUnit: suggestedSalePricePerUnit,
      salesTaxRateIsCurrentSetting:
        salesTaxRateIsCurrentSetting || fallbackSalesTaxRate != nil,
      brokerFeeRateIsCurrentSetting:
        brokerFeeRateIsCurrentSetting || fallbackBrokerFeeRate != nil
    )
  }

  private static func validRate(_ rate: Double?) -> Double? {
    guard let rate, rate.isFinite, rate >= 0, rate < 1 else { return nil }
    return rate
  }
}

/// Market fee rates currently configured for the Main Hub.
public struct ProductionOverviewFeeRates: Equatable, Sendable {
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?

  public init(salesTaxRate: Double?, brokerFeeRate: Double?) {
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
  }
}

extension ProductionBasis {
  /// Current Main Hub fee rates for production rows whose stored plan did
  /// not record them; `nil` without a configured Main Hub.
  public var productionOverviewFeeRates: ProductionOverviewFeeRates? {
    guard let taxes = mainTradingLocation?.marketTaxes else { return nil }
    let rates = ProductionOverviewFeeRates(
      salesTaxRate: taxes.effectiveSalesTaxRate,
      brokerFeeRate: taxes.effectiveBrokerFeeRate
    )
    guard rates.salesTaxRate != nil || rates.brokerFeeRate != nil else {
      return nil
    }
    return rates
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
    let blueprintCost = allocate(
      plan.costBreakdown?.blueprintCosts?.acceptedTotal,
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
    var salesTaxRate =
      validScenarioRate(plan.listedSale.salesTaxRate)
      ?? scenarioRate(
        amount: plan.listedSale.salesTax,
        gross: plan.listedSale.grossRevenue
      )
      ?? validScenarioRate(plan.immediateSale.salesTaxRate)
      ?? scenarioRate(
        amount: plan.immediateSale.salesTax,
        gross: plan.immediateSale.grossRevenue
      )
    let brokerFeeIsApplicable =
      plan.listedSale.brokerFeeIsApplicable
      ?? (plan.listedSale.outboundLogisticsAssessment?.status != .prohibited)
    if salesTaxRate == nil, !brokerFeeIsApplicable {
      salesTaxRate = firstScenarioRate(
        [
          plan.homeListedSale,
          plan.homeImmediateSale,
          plan.coalitionListedSale,
          plan.coalitionImmediateSale,
        ]
      )
    }
    let brokerFeeRate =
      brokerFeeIsApplicable
      ? validScenarioRate(plan.listedSale.brokerFeeRate)
        ?? scenarioRate(
          amount: plan.listedSale.brokerFee,
          gross: plan.listedSale.grossRevenue
        )
      : nil
    let productNode = plan.topLevelProductNode(for: requestID)
    let quote = productNode.flatMap { node in
      plan.listedSale.quotes.first {
        $0.typeID == node.typeID && $0.quantity == node.requiredQuantity
      }
    }
    let suggestedSalePricePerUnit = grossUnitPrice(
      quote: quote,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate,
      brokerFeeIsApplicable: brokerFeeIsApplicable
    )
    return ProductionOverviewRequestProjection(
      materialCost: projectedMaterialCost,
      installationCost: installationCost,
      blueprintCost: blueprintCost,
      logisticsCost: logisticsCost,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate,
      brokerFeeIsApplicable: brokerFeeIsApplicable,
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
    if knownMaterialTotal > 0 {
      guard let requestMaterialCost else { return nil }
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

  private static func validScenarioRate(_ rate: Double?) -> Double? {
    guard let rate, rate.isFinite, rate >= 0, rate < 1 else { return nil }
    return rate
  }

  private static func firstScenarioRate(
    _ scenarios: [SaleScenarioResult?]
  ) -> Double? {
    for scenario in scenarios.compactMap({ $0 }) {
      if let rate = validScenarioRate(scenario.salesTaxRate)
        ?? scenarioRate(
          amount: scenario.salesTax,
          gross: scenario.grossRevenue
        )
      {
        return rate
      }
    }
    return nil
  }

  private static func grossUnitPrice(
    quote: PriceQuote?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    brokerFeeIsApplicable: Bool
  ) -> Double? {
    guard let netUnitPrice = quote?.weightedUnitPrice,
      netUnitPrice.isFinite,
      netUnitPrice >= 0,
      let salesTaxRate
    else { return nil }
    let appliedBrokerFeeRate: Double
    if brokerFeeIsApplicable {
      guard let brokerFeeRate else { return nil }
      appliedBrokerFeeRate = brokerFeeRate
    } else {
      appliedBrokerFeeRate = 0
    }
    let retainedShare = 1 - salesTaxRate - appliedBrokerFeeRate
    guard retainedShare > 0 else { return nil }
    let gross = netUnitPrice / retainedShare
    return gross.isFinite && gross >= 0 ? gross : nil
  }
}
