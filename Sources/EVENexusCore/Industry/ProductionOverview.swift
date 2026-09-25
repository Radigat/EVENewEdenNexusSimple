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

  public init(
    materialCost: Double?,
    installationCost: Double?,
    blueprintCost: Double? = nil,
    logisticsCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    brokerFeeIsApplicable: Bool = true,
    suggestedSalePricePerUnit: Double?
  ) {
    self.materialCost = materialCost
    self.installationCost = installationCost
    self.blueprintCost = blueprintCost
    self.logisticsCost = logisticsCost
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.brokerFeeIsApplicable = brokerFeeIsApplicable
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
    let blueprintCost = allocate(
      plan.costBreakdown?.blueprintCosts?.total,
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

  /// Freezes the selected reconstruction route into the immutable plan that is
  /// stored with Production Overview rows. Main → Home uses the Home-Hub sale
  /// scenarios. Main → Home → Main keeps the Main-Hub scenarios and folds the
  /// finished-product return leg into production logistics.
  public static func reconstructedPlan(
    _ plan: IndustryPlanSnapshot,
    route: RecursiveProductionLogisticsRoute
  ) -> IndustryPlanSnapshot {
    let selectedImmediate: SaleScenarioResult
    let selectedListed: SaleScenarioResult
    let outboundLogistics: LogisticsCostBreakdown?
    let outboundLogisticsCost: Double?

    switch route {
    case .mainToHome:
      selectedImmediate = plan.homeImmediateSale ?? plan.immediateSale
      selectedListed = plan.homeListedSale ?? plan.listedSale
      outboundLogistics = nil
      outboundLogisticsCost = 0
    case .mainToHomeToMain:
      selectedImmediate = plan.immediateSale
      selectedListed = plan.listedSale
      outboundLogistics =
        plan.listedSale.outboundLogistics
        ?? plan.immediateSale.outboundLogistics
      outboundLogisticsCost =
        plan.listedSale.outboundLogisticsCost
        ?? plan.immediateSale.outboundLogisticsCost
    }

    let costs = reconstructedCosts(
      plan.costBreakdown,
      outboundLogistics: outboundLogistics,
      outboundLogisticsCost: outboundLogisticsCost
    )
    let routeExplanation = ExplanationEdge(
      id: plan.id,
      fromNodeID: nil,
      toNodeID: nil,
      rule: "production-overview.recursive-reconstruction",
      explanation:
        route == .mainToHome
        ? "Current-market reconstruction recorded for Main Hub to Home Hub."
        : "Current-market reconstruction recorded for Main Hub to Home Hub to Main Hub, including finished-product return logistics.",
      source: nil
    )

    return IndustryPlanSnapshot(
      id: plan.id,
      createdAt: plan.createdAt,
      requests: plan.requests,
      nodes: plan.nodes,
      materials: plan.materials,
      stockAllocations: plan.stockAllocations,
      jobs: plan.jobs,
      materialCost: plan.materialCost,
      installationCost: plan.installationCost,
      costBreakdown: costs,
      immediateSale: selectedImmediate,
      listedSale: selectedListed,
      mainContractSale: plan.mainContractSale,
      homeImmediateSale: plan.homeImmediateSale,
      homeListedSale: plan.homeListedSale,
      homeContractSale: plan.homeContractSale,
      coalitionImmediateSale: plan.coalitionImmediateSale,
      coalitionListedSale: plan.coalitionListedSale,
      coalitionContractSale: plan.coalitionContractSale,
      totalJobSeconds: plan.totalJobSeconds,
      makespanSeconds: plan.makespanSeconds,
      warnings: plan.warnings,
      explanations: plan.explanations + [routeExplanation],
      provenance: plan.provenance
    )
  }

  private static func reconstructedCosts(
    _ costs: IndustryCostBreakdown?,
    outboundLogistics: LogisticsCostBreakdown?,
    outboundLogisticsCost: Double?
  ) -> IndustryCostBreakdown? {
    guard let costs else { return nil }
    let logisticsCost = sumKnownMoney(
      costs.effectiveLogisticsCost,
      outboundLogisticsCost
    )
    return IndustryCostBreakdown(
      materialCost: costs.materialCost,
      purchasedMaterialCost: costs.purchasedMaterialCost,
      stockMaterialCost: costs.stockMaterialCost,
      blueprintCosts: costs.blueprintCosts,
      systemIndexCost: costs.systemIndexCost,
      facilityTax: costs.facilityTax,
      sccSurcharge: costs.sccSurcharge,
      alphaSurcharge: costs.alphaSurcharge,
      installationCost: costs.installationCost,
      logistics: combinedLogistics(
        costs.logistics,
        outbound: outboundLogistics
      ),
      logisticsCost: logisticsCost,
      totalProductionCost: IndustryCostBreakdown.total(
        materialCost: costs.materialCost,
        blueprintCost: costs.blueprintCosts?.total,
        installationCost: costs.installationCost,
        logisticsCost: logisticsCost
      )
    )
  }

  private static func combinedLogistics(
    _ inbound: LogisticsCostBreakdown?,
    outbound: LogisticsCostBreakdown?
  ) -> LogisticsCostBreakdown? {
    guard let outbound else { return inbound }
    guard let inbound else { return outbound }
    guard let total = sumKnownMoney(inbound.total, outbound.total) else {
      return nil
    }
    return LogisticsCostBreakdown(
      ruleVersion: inbound.ruleVersion,
      iskPerCubicMeter: inbound.iskPerCubicMeter,
      collateralRate: inbound.collateralRate,
      maximumContractVolumeM3: inbound.maximumContractVolumeM3,
      roundingIncrement: inbound.roundingIncrement,
      legs: inbound.legs + outbound.legs,
      total: total
    )
  }

  private static func sumKnownMoney(
    _ first: Double?,
    _ second: Double?
  ) -> Double? {
    guard let first, let second,
      first.isFinite, second.isFinite,
      first >= 0, second >= 0
    else { return nil }
    let total = first + second
    return total.isFinite ? total : nil
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
