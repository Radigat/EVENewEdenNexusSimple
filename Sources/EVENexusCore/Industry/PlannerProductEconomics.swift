import Foundation

/// One end product's causal share of the plan's costs (owner decision
/// 2026-10-31). The known shares of a block add up to the plan total exactly.
public struct PlannerProductCosts: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID { requestID }
  public let requestID: UUID
  public let typeID: Int64?
  public let productName: String
  public let units: Int64
  public let materialCost: Double?
  public let installationCost: Double?
  public let blueprintCost: Double?
  public let inboundLogisticsCost: Double?
  /// Share of the plan's outbound cargo; distributes sale transport.
  public let outboundShare: Double

  public var totalCost: Double? {
    guard let materialCost, let installationCost, let blueprintCost,
      let inboundLogisticsCost
    else { return nil }
    let total = materialCost + installationCost + blueprintCost + inboundLogisticsCost
    return total.isFinite ? total : nil
  }

  public var costPerUnit: Double? {
    guard units > 0 else { return nil }
    return totalCost.map { $0 / Double(units) }
  }

  /// Costs before the delivery from the Main Hub to the Home Hub.
  public var productionSubtotal: Double? {
    guard let materialCost, let installationCost, let blueprintCost else { return nil }
    let total = materialCost + installationCost + blueprintCost
    return total.isFinite ? total : nil
  }
}

/// Sale decision of one end product; `nil` fields were never chosen.
public struct PlannerProductDecision: Codable, Equatable, Sendable {
  public var targetMarket: PlannerTargetMarket?
  public var allianceSale: PlannerAllianceSaleResult?
  /// The scenario within a hub; `nil` keeps the listed sale of older decisions.
  public var saleScenario: PriceScenario?

  public init(
    targetMarket: PlannerTargetMarket? = nil,
    allianceSale: PlannerAllianceSaleResult? = nil,
    saleScenario: PriceScenario? = nil
  ) {
    self.targetMarket = targetMarket
    self.allianceSale = allianceSale
    self.saleScenario = saleScenario
  }
}

/// One market scenario for one end product.
public struct PlannerProductSaleOutcome: Identifiable, Equatable, Sendable {
  public var id: String { "\(market.rawValue).\(scenario.rawValue)" }
  public let market: PlannerTargetMarket
  public let scenario: PriceScenario
  public let netRevenue: Double?
  public let outboundLogisticsCost: Double?
  public let totalCost: Double?
  public let profit: Double?
  public let roi: Double?
  public let hasPendingCost: Bool
  public let feeRate: Double?
}

public enum PlannerProductEconomics {
  /// `volumes` are packaged m³ per type; a missing volume falls back to the
  /// material share instead of pretending the cargo is empty.
  public static func costs(
    plan: IndustryPlanSnapshot,
    volumes: [Int64: Double]
  ) -> [PlannerProductCosts] {
    let requests = plan.requests
    guard !requests.isEmpty else { return [] }
    let materialCosts = ProductionOverviewProjector.scaledMaterialCosts(
      requests.map {
        ProductionOverviewProjector.materialCost(for: $0.id, in: plan)
      },
      planTotal: plan.materialCost
    )
    let materialWeights = materialCosts.map { $0 ?? 0 }
    let producedNodes = plan.nodes.filter { $0.action == .produce }

    var installationWeights = Array(repeating: 0.0, count: requests.count)
    var installationKnown = plan.jobs.isEmpty == false
    for job in plan.jobs {
      let nodes = producedNodes.filter { $0.typeID == job.typeID }
      let weights = requests.map { request in
        nodes.filter { $0.topLevelRequestID == request.id }
          .reduce(0.0) { $0 + Double($1.requiredQuantity) }
      }
      let sum = weights.reduce(0, +)
      guard sum > 0 else {
        installationKnown = false
        continue
      }
      for index in requests.indices {
        installationWeights[index] += job.total * weights[index] / sum
      }
    }
    let installationCosts = shares(
      total: plan.costBreakdown?.installationCost ?? plan.installationCost,
      weights: installationKnown ? installationWeights : materialWeights
    )

    let blueprintCosts = shares(
      total: plan.costBreakdown?.blueprintCosts?.acceptedTotal,
      weights: blueprintWeights(
        plan: plan,
        producedNodes: producedNodes,
        materialWeights: materialWeights
      ),
      fallbackWeights: materialWeights
    )

    let inboundCosts = shares(
      total: plan.costBreakdown?.effectiveLogisticsCost,
      weights: inboundWeights(
        plan: plan,
        volumes: volumes,
        materialWeights: materialWeights
      ),
      fallbackWeights: materialWeights
    )

    let products = requests.map { plan.topLevelProductNode(for: $0.id) }
    let outboundWeights = products.map { node -> Double? in
      guard let node, let volume = volumes[node.typeID], volume >= 0 else {
        return nil
      }
      return volume * Double(node.requiredQuantity)
    }
    let outboundShares = normalized(
      outboundWeights.contains { $0 == nil }
        ? materialWeights : outboundWeights.map { $0 ?? 0 }
    )

    return requests.indices.map { index in
      PlannerProductCosts(
        requestID: requests[index].id,
        typeID: products[index]?.typeID,
        productName: products[index]?.name ?? requests[index].productName,
        units: products[index]?.requiredQuantity
          ?? Int64(requests[index].wantedQuantity),
        materialCost: materialCosts[index],
        installationCost: installationCosts[index],
        blueprintCost: blueprintCosts[index],
        inboundLogisticsCost: inboundCosts[index],
        outboundShare: outboundShares[index]
      )
    }
  }

  /// An entered cost belongs to its production line. An automatic entry has no
  /// such line and belongs to the products building that item, by built quantity.
  private static func blueprintWeights(
    plan: IndustryPlanSnapshot,
    producedNodes: [PlanNode],
    materialWeights: [Double]
  ) -> [Double] {
    let requests = plan.requests
    var weights = Array(repeating: 0.0, count: requests.count)
    for entry in plan.costBreakdown?.blueprintCosts?.entries ?? [] {
      if let index = requests.firstIndex(where: { $0.id == entry.requestID }) {
        weights[index] += entry.amount
        continue
      }
      let built = requests.map { request in
        producedNodes
          .filter { $0.topLevelRequestID == request.id && $0.name == entry.productName }
          .reduce(0.0) { $0 + Double($1.requiredQuantity) }
      }
      let portions = normalized(built.reduce(0, +) > 0 ? built : materialWeights)
      for index in requests.indices {
        weights[index] += entry.amount * portions[index]
      }
    }
    return weights
  }

  /// The freight of the delivery, split by what each product buys. A plan without
  /// saved freight falls back to the volume of everything bought.
  private static func inboundWeights(
    plan: IndustryPlanSnapshot,
    volumes: [Int64: Double],
    materialWeights: [Double]
  ) -> [Double] {
    let requests = plan.requests
    let buyNodes = plan.nodes.filter { $0.action == .buy }
    let cargo = (plan.costBreakdown?.logistics?.legs ?? [])
      .filter { $0.kind == .inboundMaterials }
      .flatMap(\.cargoItems)
    var weights = Array(repeating: 0.0, count: requests.count)
    guard cargo.isEmpty else {
      for line in cargo {
        let bought = requests.map { request in
          buyNodes
            .filter { $0.topLevelRequestID == request.id && $0.typeID == line.typeID }
            .reduce(0.0) { $0 + Double($1.requiredQuantity) }
        }
        let portions = normalized(bought.reduce(0, +) > 0 ? bought : materialWeights)
        for index in requests.indices {
          weights[index] += line.volumeM3 * portions[index]
        }
      }
      return weights
    }
    for (index, request) in requests.enumerated() {
      for node in buyNodes where node.topLevelRequestID == request.id {
        guard let volume = volumes[node.typeID], volume >= 0 else {
          return materialWeights
        }
        weights[index] += volume * Double(node.requiredQuantity)
      }
    }
    return weights
  }

  /// All market scenarios of one product. A product keeps its result even when
  /// another product of the plan has no price in that scenario.
  public static func outcomes(
    plan: IndustryPlanSnapshot,
    requestID: UUID
  ) -> [PlannerProductSaleOutcome] {
    guard let costs = plan.productCosts(for: requestID) else { return [] }
    return PlannerTargetMarketSuggestion.scenarios(of: plan).compactMap {
      market, result in
      guard let result else { return nil }
      let quote = result.quotes.first {
        $0.typeID == costs.typeID && $0.quantity == costs.units
      }
      let net = netRevenue(quote: quote, result: result)
      let inboundPending =
        result.inboundLogisticsAssessment?.status == .manualTransferRequired
      let inbound = costs.inboundLogisticsCost ?? (inboundPending ? 0 : nil)
      let outbound = outboundCost(result).map { $0 * costs.outboundShare }
      var cost: Double?
      if let material = costs.materialCost,
        let installation = costs.installationCost,
        let blueprint = costs.blueprintCost,
        let inbound, let outbound
      {
        cost = material + installation + blueprint + inbound + outbound
      }
      if cost?.isFinite != true { cost = nil }
      let profit = net.flatMap { net in cost.map { net - $0 } }
      let roi: Double? =
        if let profit, let cost, cost > 0 { profit / cost } else { nil }
      return PlannerProductSaleOutcome(
        market: market,
        scenario: result.scenario,
        netRevenue: net,
        outboundLogisticsCost: outbound,
        totalCost: cost,
        profit: profit,
        roi: roi,
        hasPendingCost: result.hasPendingScenarioCost,
        feeRate: feeRate(of: result)
      )
    }
  }

  /// Share of the gross revenue that the sale's market fees take.
  public static func feeRate(of result: SaleScenarioResult) -> Double? {
    switch result.scenario {
    case .immediateSale:
      return result.salesTaxRate
    case .listedSale:
      guard let tax = result.salesTaxRate else { return nil }
      guard result.brokerFeeIsApplicable ?? true else { return tax }
      return result.brokerFeeRate.map { tax + $0 }
    case .contractSale:
      guard let fee = result.contractFee, let gross = result.grossRevenue, gross > 0
      else { return nil }
      return fee / gross
    case .materialBuy:
      return nil
    }
  }

  /// Highest final profit of one product; pending costs are shown but never
  /// suggested, and a tie prefers the market scenarios.
  public static func suggestion(
    plan: IndustryPlanSnapshot,
    requestID: UUID
  ) -> (market: PlannerTargetMarket, profit: Double)? {
    var best: (market: PlannerTargetMarket, profit: Double)?
    for outcome in outcomes(plan: plan, requestID: requestID) {
      guard let profit = outcome.profit, !outcome.hasPendingCost else { continue }
      if best == nil || profit > best!.profit {
        best = (outcome.market, profit)
      }
    }
    if let alliance = plan.productDecisions?[requestID]?.allianceSale,
      let profit = alliance.profit, profit.isFinite, !alliance.isProvisional,
      best == nil || profit > best!.profit
    {
      best = (.allianceMarket, profit)
    }
    return best
  }

  /// Profit of the product's chosen market: the alliance result, or the listed
  /// scenario of the hub, as the Production Overview records it.
  public static func chosenOutcome(
    plan: IndustryPlanSnapshot,
    requestID: UUID
  ) -> (netRevenue: Double?, profit: Double?, roi: Double?)? {
    guard let market = plan.targetMarket(for: requestID) else { return nil }
    if market == .allianceMarket {
      guard let alliance = plan.allianceSale(for: requestID) else { return nil }
      let net = alliance.grossRevenue.flatMap { gross in
        alliance.fee.map { gross - $0 }
      }
      return (net, alliance.profit, alliance.roi)
    }
    let scenario = plan.productDecisions?[requestID]?.saleScenario ?? .listedSale
    let outcome = outcomes(plan: plan, requestID: requestID).first {
      $0.market == market && $0.scenario == scenario
    }
    return outcome.map { ($0.netRevenue, $0.profit, $0.roi) }
  }

  /// Splits `total` by `weights`; the last positive share takes the rounding
  /// remainder so the parts add up exactly. Zero weights use the fallback and
  /// finally an even split. A missing total stays missing for every product.
  static func shares(
    total: Double?,
    weights: [Double],
    fallbackWeights: [Double]? = nil
  ) -> [Double?] {
    guard let total, total.isFinite, total >= 0 else {
      return weights.map { _ in nil }
    }
    var effective = weights
    if effective.reduce(0, +) <= 0, let fallbackWeights {
      effective = fallbackWeights
    }
    let portions = normalized(effective)
    var result: [Double?] = portions.map { total * $0 }
    if let last = portions.lastIndex(where: { $0 > 0 }) {
      let others = portions.indices.filter { $0 != last }
        .reduce(0.0) { $0 + total * portions[$1] }
      result[last] = max(0, total - others)
    }
    return result
  }

  private static func normalized(_ weights: [Double]) -> [Double] {
    let usable = weights.map { $0.isFinite && $0 > 0 ? $0 : 0 }
    let sum = usable.reduce(0, +)
    guard sum > 0 else {
      return weights.map { _ in 1 / Double(max(1, weights.count)) }
    }
    return usable.map { $0 / sum }
  }

  private static func netRevenue(
    quote: PriceQuote?,
    result: SaleScenarioResult
  ) -> Double? {
    guard let total = quote?.total, total.isFinite else { return nil }
    let net: Double?
    switch result.scenario {
    case .listedSale:
      // A listed quote is already net of sales tax and broker fee.
      net = total
    case .immediateSale:
      net = result.salesTaxRate.map { total * (1 - $0) }
    case .contractSale:
      if let fee = result.contractFee, let gross = result.grossRevenue, gross > 0 {
        net = total * (1 - fee / gross)
      } else {
        net = total
      }
    case .materialBuy:
      net = nil
    }
    return net.flatMap { $0.isFinite ? $0 : nil }
  }

  private static func outboundCost(_ result: SaleScenarioResult) -> Double? {
    guard let assessment = result.outboundLogisticsAssessment else {
      return result.outboundLogisticsCost ?? 0
    }
    switch assessment.status {
    case .manualTransferRequired:
      return assessment.cost ?? 0
    case .calculated, .notRequired:
      return assessment.cost ?? result.outboundLogisticsCost
    default:
      return nil
    }
  }
}

extension IndustryPlanSnapshot {
  public func productCosts(for requestID: UUID) -> PlannerProductCosts? {
    productEconomics?.first { $0.requestID == requestID }
  }

  /// The product's own choice; a single-product plan keeps its plan-wide label.
  public func targetMarket(for requestID: UUID) -> PlannerTargetMarket? {
    productDecisions?[requestID]?.targetMarket
      ?? (requests.count == 1 ? targetMarket : nil)
  }

  public func allianceSale(for requestID: UUID) -> PlannerAllianceSaleResult? {
    productDecisions?[requestID]?.allianceSale
      ?? (requests.count == 1 ? allianceSale : nil)
  }

  /// Fixes the suggested sale of every product the owner did not decide, so the
  /// Production Overview records what the Planner shows as selected.
  public func applyingSuggestedSales() -> IndustryPlanSnapshot {
    var plan = self
    for product in PlannerProfitability(plan: self).products where product.isSuggestion {
      guard let selected = product.selected else { continue }
      var decision = plan.productDecisions?[product.id] ?? PlannerProductDecision()
      decision.targetMarket = selected.market
      decision.saleScenario = selected.scenario
      var decisions = plan.productDecisions ?? [:]
      decisions[product.id] = decision
      plan.productDecisions = decisions
      if requests.count == 1 { plan.targetMarket = selected.market }
    }
    return plan
  }
}
