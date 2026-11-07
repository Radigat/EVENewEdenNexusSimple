import Foundation

/// Answer to the Planner's question "Profitable?" for the selected sale (owner
/// decision 2026-10-31).
public enum PlannerProfitabilityVerdict: Int, Equatable, Sendable {
  /// The selected sale earns more than it costs.
  case profitable
  /// The selected sale has a final value and earns no more than it costs.
  case unprofitable
  /// No final value exists: prices are missing or costs are still provisional.
  case notCheckable
}

/// The owner's choice of a sale; `scenario` is `nil` for the alliance sale and
/// for a hub chosen before scenarios could be chosen, which means its listed sale.
public struct PlannerSaleChoice: Equatable, Sendable {
  public let market: PlannerTargetMarket
  public let scenario: PriceScenario?

  public init(market: PlannerTargetMarket, scenario: PriceScenario?) {
    self.market = market
    self.scenario = scenario
  }
}

/// One sale option of one product, as the sale scenarios calculate it.
public struct PlannerProfitabilityScenario: Identifiable, Equatable, Sendable {
  public var id: String { "\(market.rawValue).\(scenario?.rawValue ?? "alliance")" }
  public let market: PlannerTargetMarket
  /// `nil` for the alliance sale, which has no market scenario.
  public let scenario: PriceScenario?
  public let netRevenue: Double?
  public let totalCost: Double?
  public let profit: Double?
  public let roi: Double?
  public let isProvisional: Bool
  /// Share of the gross revenue that this sale's fees take.
  public let feeRate: Double?
  /// Units the alliance takes; `nil` means all produced units.
  public let soldQuantity: Int64?

  public init(
    market: PlannerTargetMarket,
    scenario: PriceScenario?,
    netRevenue: Double?,
    totalCost: Double?,
    profit: Double?,
    roi: Double?,
    isProvisional: Bool,
    feeRate: Double? = nil,
    soldQuantity: Int64? = nil
  ) {
    self.market = market
    self.scenario = scenario
    self.netRevenue = netRevenue
    self.totalCost = totalCost
    self.profit = profit
    self.roi = roi
    self.isProvisional = isProvisional
    self.feeRate = feeRate
    self.soldQuantity = soldQuantity
  }

  public var finalProfit: Double? {
    guard !isProvisional, let profit, profit.isFinite else { return nil }
    return profit
  }

  /// The alliance sale before a price was entered: selectable, without values.
  static let allianceWithoutInput = PlannerProfitabilityScenario(
    market: .allianceMarket,
    scenario: nil,
    netRevenue: nil,
    totalCost: nil,
    profit: nil,
    roi: nil,
    isProvisional: false
  )
}

public struct PlannerProductProfitability: Identifiable, Equatable, Sendable {
  public var id: UUID { request.id }
  public let request: ProductionRequestLine
  public let scenarios: [PlannerProfitabilityScenario]
  /// Option with the highest final profit; a tie keeps the earlier option.
  public let best: PlannerProfitabilityScenario?
  /// The owner's choice, otherwise the best option as a suggestion.
  public let selected: PlannerProfitabilityScenario?
  /// `true` while `selected` is the suggestion and not the owner's choice.
  public let isSuggestion: Bool
  public let verdict: PlannerProfitabilityVerdict

  public init(
    request: ProductionRequestLine,
    scenarios: [PlannerProfitabilityScenario],
    choice: PlannerSaleChoice? = nil
  ) {
    self.request = request
    self.scenarios = scenarios
    var best: PlannerProfitabilityScenario?
    for scenario in scenarios {
      guard let profit = scenario.finalProfit else { continue }
      if best?.finalProfit.map({ profit > $0 }) ?? true { best = scenario }
    }
    self.best = best
    // A chosen scenario the new calculation no longer has falls back to the suggestion.
    let chosen = choice.flatMap { Self.match($0, in: scenarios) }
    selected = chosen ?? best
    isSuggestion = chosen == nil
    if let profit = selected?.finalProfit {
      verdict = profit > 0 ? .profitable : .unprofitable
    } else {
      verdict = .notCheckable
    }
  }

  /// Every sale to choose from, highest final profit first and values without a
  /// final profit last. The alliance sale can always be chosen to enter a price.
  public var options: [PlannerProfitabilityScenario] {
    var options = scenarios
    if !options.contains(where: { $0.market == .allianceMarket }) {
      options.append(.allianceWithoutInput)
    }
    return options.enumerated().sorted { lhs, rhs in
      switch (lhs.element.profit, rhs.element.profit) {
      case (let left?, let right?) where left != right: left > right
      case (.some, nil): true
      case (nil, .some): false
      default: lhs.offset < rhs.offset
      }
    }
    .map(\.element)
  }

  private static func match(
    _ choice: PlannerSaleChoice,
    in scenarios: [PlannerProfitabilityScenario]
  ) -> PlannerProfitabilityScenario? {
    if choice.market == .allianceMarket {
      return scenarios.first { $0.market == .allianceMarket } ?? .allianceWithoutInput
    }
    let scenario = choice.scenario ?? .listedSale
    return scenarios.first { $0.market == choice.market && $0.scenario == scenario }
  }
}

/// The cost columns of one product's selected sale. They include the transport
/// of that sale, so revenue minus `cost` is the profit of the same row.
public struct PlannerSaleFigures: Equatable, Sendable {
  public let cost: Double?
  public let costPerItem: Double?
  /// The unit price at which the sold units exactly cover the costs and fees.
  public let minimumPrice: Double?

  public init(
    costs: PlannerProductCosts?,
    units: Int64?,
    sale: PlannerProfitabilityScenario?
  ) {
    let cost = sale?.totalCost ?? costs?.totalCost
    self.cost = cost
    costPerItem = Self.perUnit(cost, units)
    let soldUnits = sale?.soldQuantity ?? units
    if let feeRate = sale?.feeRate, feeRate >= 0, feeRate < 1,
      let costPerSoldUnit = Self.perUnit(cost, soldUnits)
    {
      let price = costPerSoldUnit / (1 - feeRate)
      minimumPrice = price.isFinite ? price : nil
    } else {
      minimumPrice = nil
    }
  }

  private static func perUnit(_ cost: Double?, _ units: Int64?) -> Double? {
    guard let cost, let units, units > 0 else { return nil }
    let value = cost / Double(units)
    return value.isFinite ? value : nil
  }
}

/// Which warnings concern the sales the owner selected. Warnings about a sale
/// path that is not selected do not change the numbers and stay out of the way.
public enum PlannerWarningRelevance {
  private static let contractCodes: Set<String> = [
    "planner.contract-reference-partial",
    "contracts.reference-provisional",
  ]
  private static let courierCode = "logistics.single-item-volume-exceeded"

  public static func relevant(
    _ warnings: [DomainWarning],
    plan: IndustryPlanSnapshot
  ) -> [DomainWarning] {
    let products = PlannerProfitability(plan: plan).products
    return warnings.filter { warning in
      if contractCodes.contains(warning.code) {
        return products.contains {
          $0.selected == nil || $0.selected?.scenario == .contractSale
        }
      }
      guard warning.code == courierCode,
        let name = warning.text?.arguments.first
      else { return true }
      let concerned = products.filter {
        $0.request.productName == name
          || plan.topLevelProductNode(for: $0.id)?.name == name
      }
      // An item that is no end product is a material on its way to production.
      return concerned.isEmpty
        || concerned.contains { needsManualTransport($0, plan: plan) }
    }
  }

  private static func needsManualTransport(
    _ product: PlannerProductProfitability,
    plan: IndustryPlanSnapshot
  ) -> Bool {
    guard let selected = product.selected else { return true }
    let results = PlannerTargetMarketSuggestion.scenarios(of: plan)
    if selected.market == .allianceMarket {
      guard let hub = plan.allianceSale(for: product.id)?.input.deliveryHub else {
        return false
      }
      return results.contains {
        $0.market == hub && $0.result?.hasPendingManualTransportCost == true
      }
    }
    return results.contains {
      $0.market == selected.market && $0.result?.scenario == selected.scenario
        && $0.result?.hasPendingManualTransportCost == true
    }
  }
}

/// Compares a plan's costs with its sale scenarios. It reads the calculated
/// scenarios and calculates nothing of its own.
public struct PlannerProfitability: Equatable, Sendable {
  public let products: [PlannerProductProfitability]

  init(products: [PlannerProductProfitability]) {
    self.products = products
  }

  public init(plan: IndustryPlanSnapshot) {
    products = plan.requests.map { request in
      var scenarios: [PlannerProfitabilityScenario]
      if plan.requests.count == 1 {
        scenarios = PlannerTargetMarketSuggestion.scenarios(of: plan).compactMap {
          market, result in
          result.map { Self.scenario(market: market, result: $0) }
        }
      } else {
        scenarios = PlannerProductEconomics.outcomes(plan: plan, requestID: request.id)
          .map {
            PlannerProfitabilityScenario(
              market: $0.market,
              scenario: $0.scenario,
              netRevenue: $0.netRevenue,
              totalCost: $0.totalCost,
              profit: $0.profit,
              roi: $0.roi,
              isProvisional: $0.hasPendingCost,
              feeRate: $0.feeRate
            )
          }
      }
      if let alliance = plan.allianceSale(for: request.id) {
        scenarios.append(Self.scenario(alliance: alliance))
      }
      return PlannerProductProfitability(
        request: request,
        scenarios: scenarios,
        choice: plan.targetMarket(for: request.id).map {
          PlannerSaleChoice(
            market: $0,
            scenario: plan.productDecisions?[request.id]?.saleScenario
          )
        }
      )
    }
  }

  /// Ties a "produce anyway" to this calculation and the sales the owner saw.
  public func confirmationKey(planID: UUID) -> String {
    let sales = products.map { product in
      "\(product.id):\(product.selected?.id ?? "none"):\(product.selected?.profit ?? .nan)"
    }
    return ([planID.uuidString] + sales.sorted()).joined(separator: "|")
  }

  /// Whether the owner has to decide before the plan continues.
  public var needsDecision: Bool {
    verdict != .profitable
  }

  public var verdict: PlannerProfitabilityVerdict {
    if products.contains(where: { $0.verdict == .unprofitable }) { return .unprofitable }
    if products.isEmpty || products.contains(where: { $0.verdict == .notCheckable }) {
      return .notCheckable
    }
    return .profitable
  }

  public var totalRevenue: Double? { total(\.netRevenue) }
  public var totalCost: Double? { total(\.totalCost) }
  public var totalProfit: Double? { total(\.profit) }

  /// A sum over the selected sales exists only when every product's value is known.
  private func total(_ value: KeyPath<PlannerProfitabilityScenario, Double?>) -> Double? {
    guard !products.isEmpty else { return nil }
    var sum = 0.0
    for product in products {
      guard let part = product.selected?[keyPath: value], part.isFinite else { return nil }
      sum += part
    }
    return sum.isFinite ? sum : nil
  }

  private static func scenario(
    market: PlannerTargetMarket,
    result: SaleScenarioResult
  ) -> PlannerProfitabilityScenario {
    PlannerProfitabilityScenario(
      market: market,
      scenario: result.scenario,
      netRevenue: result.grossOrNetRevenue,
      totalCost: result.totalCost,
      profit: result.profit,
      roi: result.roi,
      isProvisional: result.hasPendingScenarioCost,
      feeRate: PlannerProductEconomics.feeRate(of: result)
    )
  }

  private static func scenario(
    alliance: PlannerAllianceSaleResult
  ) -> PlannerProfitabilityScenario {
    PlannerProfitabilityScenario(
      market: .allianceMarket,
      scenario: nil,
      netRevenue: alliance.grossRevenue.flatMap { gross in
        alliance.fee.map { gross - $0 }
      },
      totalCost: alliance.totalCost,
      profit: alliance.profit,
      roi: alliance.roi,
      isProvisional: alliance.isProvisional,
      feeRate: alliance.appliedFeeRate,
      soldQuantity: alliance.soldQuantity
    )
  }
}

/// The Planner's steps in the owner's order (decision 2026-10-31).
public enum PlannerStep: Int, CaseIterable, Comparable, Identifiable, Sendable {
  case settings = 1
  case products
  case stock
  case costs
  case adjust
  case shopping
  case jobs
  case sale

  public var id: Int { rawValue }

  public static func < (lhs: PlannerStep, rhs: PlannerStep) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// Without a plan the Planner starts at the beginning, with one at its costs.
  public static func start(hasPlan: Bool) -> PlannerStep {
    hasPlan ? .costs : .settings
  }
}

/// The owner's answer to "Use warehouse?". "No" calculates without any stock;
/// a manual list stays saved but does not count.
public enum PlannerStockUse {
  public static func manualStockInput(_ text: String, usesStock: Bool) -> String {
    usesStock ? text : ""
  }

  public static func hasManualStock(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Stock for the Blueprint resolution of one calculation pass. A manual list
  /// replaces the warehouse there too, so both passes plan the same build steps
  /// and runs (owner decision 2026-10-31). `nil` keeps the warehouse.
  public static func blueprintStockOverride(
    manualStock: [Int64: Int64],
    calculatesWithoutStock: Bool
  ) -> [Int64: Int64]? {
    guard !manualStock.isEmpty else { return nil }
    return calculatesWithoutStock ? [:] : manualStock
  }
}

/// Which steps can be opened. Costs need a plan; everything after them also
/// needs a passed or confirmed profitability check.
public struct PlannerStepAccess: Equatable, Sendable {
  public let isInputReady: Bool
  public let hasPlan: Bool
  public let isProfitabilityCleared: Bool

  public init(isInputReady: Bool, hasPlan: Bool, isProfitabilityCleared: Bool) {
    self.isInputReady = isInputReady
    self.hasPlan = hasPlan
    self.isProfitabilityCleared = isProfitabilityCleared
  }

  /// A confirmation counts only for the calculation and sales it was given for.
  public init(
    isInputReady: Bool,
    plan: IndustryPlanSnapshot?,
    profitability: PlannerProfitability?,
    confirmedKey: String?
  ) {
    self.init(
      isInputReady: isInputReady,
      hasPlan: plan != nil,
      isProfitabilityCleared: plan.map { plan in
        guard let profitability else { return false }
        return !profitability.needsDecision
          || confirmedKey == profitability.confirmationKey(planID: plan.id)
      } ?? false
    )
  }

  public func isReachable(_ step: PlannerStep) -> Bool {
    switch step {
    case .settings, .products: true
    case .stock: isInputReady
    case .costs: hasPlan
    case .adjust, .shopping, .jobs, .sale: hasPlan && isProfitabilityCleared
    }
  }

  /// The wanted step, or the nearest earlier one that can be opened.
  public func clamped(_ step: PlannerStep) -> PlannerStep {
    PlannerStep.allCases.last { $0 <= step && isReachable($0) } ?? .settings
  }

  public func next(after step: PlannerStep) -> PlannerStep? {
    PlannerStep(rawValue: step.rawValue + 1).flatMap { isReachable($0) ? $0 : nil }
  }

  public func previous(before step: PlannerStep) -> PlannerStep? {
    PlannerStep.allCases.last { $0 < step && isReachable($0) }
  }

  /// A calculation leads to the costs unless it started after them and needs
  /// no new decision.
  public func step(afterCalculationFrom step: PlannerStep) -> PlannerStep {
    step > .costs && isReachable(step) ? step : .costs
  }
}

/// Why a plan cannot be recorded in the Production Overview yet.
public enum PlannerRecordBlocker: Equatable, Sendable {
  case planNotCurrent
  case missingTargetMarket(productNames: [String])

  public static func resolve(
    plan: IndustryPlanSnapshot,
    status: PlannerCalculationStatus
  ) -> PlannerRecordBlocker? {
    guard status == .current || status == .saved else { return .planNotCurrent }
    let missing = PlannerProfitability(plan: plan).products
      .filter { $0.selected == nil }
      .map(\.request.productName)
    return missing.isEmpty ? nil : .missingTargetMarket(productNames: missing)
  }
}
