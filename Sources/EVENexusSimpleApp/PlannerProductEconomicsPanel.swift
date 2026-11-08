import EVENexusCore
import SwiftUI

enum PlannerProductSortColumn: Hashable {
  case product, units, material, installation, blueprint, logistics
  case totalCost, costPerUnit, target, revenue, profit, roi
}

/// Per-product path of a plan with several end products: cost shares, selected
/// sale and profit. Single-product plans keep the plan-wide panels.
struct PlannerProductEconomicsPanel: View {
  let plan: IndustryPlanSnapshot
  let isHistorical: Bool

  @State private var sort = AppTableSortDescriptor(
    column: PlannerProductSortColumn.product,
    direction: .ascending
  )
  @State private var selectedRequestID: UUID?

  private struct Row: Identifiable {
    let costs: PlannerProductCosts
    let lineNumber: Int
    let target: PlannerTargetMarket?
    let revenue: Double?
    let profit: Double?
    let roi: Double?
    var id: UUID { costs.requestID }
  }

  private var rows: [Row] {
    let lines = Dictionary(
      plan.requests.map { ($0.id, $0.lineNumber) },
      uniquingKeysWith: { current, _ in current }
    )
    let products = PlannerProfitability(plan: plan).products
    return (plan.productEconomics ?? []).map { costs in
      let selected = products.first { $0.id == costs.requestID }?.selected
      return Row(
        costs: costs,
        lineNumber: lines[costs.requestID] ?? 0,
        target: selected?.market,
        revenue: selected?.netRevenue,
        profit: selected?.profit,
        roi: selected?.roi
      )
    }
  }

  private var sortedRows: [Row] {
    rows.sorted { lhs, rhs in
      let ordered: Bool?
      switch sort.column {
      case .product:
        ordered = order(lhs.costs.productName, rhs.costs.productName)
      case .units: ordered = order(lhs.costs.units, rhs.costs.units)
      case .material: ordered = order(lhs.costs.materialCost, rhs.costs.materialCost)
      case .installation:
        ordered = order(lhs.costs.installationCost, rhs.costs.installationCost)
      case .blueprint: ordered = order(lhs.costs.blueprintCost, rhs.costs.blueprintCost)
      case .logistics:
        ordered = order(lhs.costs.inboundLogisticsCost, rhs.costs.inboundLogisticsCost)
      case .totalCost: ordered = order(lhs.costs.totalCost, rhs.costs.totalCost)
      case .costPerUnit: ordered = order(lhs.costs.costPerUnit, rhs.costs.costPerUnit)
      case .target:
        ordered = order(
          ProductionOverviewTargetMarketPresentation.rank(lhs.target),
          ProductionOverviewTargetMarketPresentation.rank(rhs.target)
        )
      case .revenue: ordered = order(lhs.revenue, rhs.revenue)
      case .profit: ordered = order(lhs.profit, rhs.profit)
      case .roi: ordered = order(lhs.roi, rhs.roi)
      }
      if let ordered { return ordered }
      return lhs.lineNumber < rhs.lineNumber
    }
  }

  /// Missing values follow known ones ascending and precede them descending.
  private func order<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
    let ascending: Bool?
    switch (lhs, rhs) {
    case (nil, nil): return nil
    case (nil, _): ascending = false
    case (_, nil): ascending = true
    case (let lhs?, let rhs?):
      ascending = lhs == rhs ? nil : lhs < rhs
    }
    guard let ascending else { return nil }
    return sort.direction == .ascending ? ascending : !ascending
  }

  private var selectedCosts: PlannerProductCosts? {
    let economics = plan.productEconomics ?? []
    return economics.first { $0.requestID == selectedRequestID } ?? economics.first
  }

  var body: some View {
    Panel(title: "Products in plan") {
      Text(
        "Shared costs are split by cause: materials and installation by each product's demand, blueprints by the product using them and transport by volume. The shares add up to the plan total."
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      ScrollView(.horizontal) {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
          GridRow {
            header("Product", .product, alignment: .leading)
            header("Units", .units)
            header("Material", .material)
            header("Installation", .installation)
            header("BPC/BPO", .blueprint)
            header("Logistics", .logistics)
            header("Total cost", .totalCost)
            header("Cost per item", .costPerUnit)
            header("Target market", .target, alignment: .leading)
            header("Revenue", .revenue)
            header("Profit", .profit)
            header("ROI", .roi)
          }
          .appFont(.caption.weight(.semibold))
          Divider()
          ForEach(sortedRows) { row in
            GridRow {
              HStack(spacing: DesignTokens.spacingXS) {
                Button {
                  selectedRequestID = row.id
                } label: {
                  Image(
                    systemName:
                      selectedCosts?.requestID == row.id
                      ? "largecircle.fill.circle" : "circle"
                  )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Select product"))
                EVEEntityText(value: row.costs.productName, font: .body)
              }
              .gridColumnAlignment(.leading)
              Text(row.costs.units.formatted())
              Text(isk(row.costs.materialCost))
              Text(isk(row.costs.installationCost))
              Text(isk(row.costs.blueprintCost))
              Text(isk(row.costs.inboundLogisticsCost))
              Text(isk(row.costs.totalCost))
              Text(isk(row.costs.costPerUnit))
              Text(ProductionOverviewTargetMarketPresentation.text(row.target))
                .gridColumnAlignment(.leading)
              Text(isk(row.revenue))
              Text(isk(row.profit))
              Text(percent(row.roi))
            }
            .appFont(.body.monospacedDigit())
          }
          Divider()
          GridRow {
            Text("Total").appFont(.body.weight(.semibold))
              .gridColumnAlignment(.leading)
            Text("")
            Text(isk(total(\.costs.materialCost)))
            Text(isk(total(\.costs.installationCost)))
            Text(isk(total(\.costs.blueprintCost)))
            Text(isk(total(\.costs.inboundLogisticsCost)))
            Text(isk(total(\.costs.totalCost)))
            Text("")
            Text("")
            Text(isk(total(\.revenue)))
            Text(isk(total(\.profit)))
            Text("")
          }
          .appFont(.body.monospacedDigit().weight(.semibold))
        }
        .padding(.bottom, DesignTokens.spacingXS)
      }
      .accessibilityIdentifier("planner.products.table")
      if let costs = selectedCosts {
        Divider()
        PlannerProductSaleDetail(
          plan: plan,
          costs: costs,
          isHistorical: isHistorical
        )
        .id(costs.requestID)
      }
    }
  }

  /// A total exists only when every product's value is known.
  private func total(_ value: KeyPath<Row, Double?>) -> Double? {
    let values = rows.map { $0[keyPath: value] }
    guard !values.isEmpty, !values.contains(where: { $0 == nil }) else { return nil }
    let sum = values.compactMap { $0 }.reduce(0, +)
    return sum.isFinite ? sum : nil
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerProductSortColumn,
    alignment: Alignment = .trailing
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      alignment: alignment
    )
  }

  private func isk(_ value: Double?) -> String {
    PlannerProductFormat.isk(value)
  }

  private func percent(_ value: Double?) -> String {
    PlannerProductFormat.percent(value)
  }
}

enum PlannerProductFormat {
  static func isk(_ value: Double?) -> String {
    guard let value, value.isFinite else {
      return AppLocalization.text("Unavailable")
    }
    return value.formatted(.currency(code: "ISK").precision(.fractionLength(0)))
  }

  /// Cheap items keep cents so they are not rounded to a misleading price.
  static func unitISK(_ value: Double?) -> String {
    guard let value, value.isFinite else {
      return AppLocalization.text("Unavailable")
    }
    guard abs(value) < 1_000 else { return isk(value) }
    return value.formatted(.currency(code: "ISK").precision(.fractionLength(0...2)))
  }

  static func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else {
      return AppLocalization.text("Unavailable")
    }
    return value.formatted(.percent.precision(.fractionLength(0...2)))
  }

  static func market(_ market: PlannerTargetMarket) -> String {
    ProductionOverviewTargetMarketPresentation.text(market)
  }

  static func scenario(_ scenario: PriceScenario) -> String {
    switch scenario {
    case .immediateSale: AppLocalization.text("Immediate sale")
    case .listedSale: AppLocalization.text("Listed sale")
    case .contractSale: AppLocalization.text("Contract sale")
    case .materialBuy: AppLocalization.text("Material purchase")
    }
  }
}

/// Target market, scenarios and alliance result of one product.
private struct PlannerProductSaleDetail: View {
  let plan: IndustryPlanSnapshot
  let costs: PlannerProductCosts
  let isHistorical: Bool

  private var decision: PlannerProductDecision {
    plan.productDecisions?[costs.requestID] ?? PlannerProductDecision()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      EVEEntityText(value: costs.productName, font: .headline)
      targetSection
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 260), alignment: .top)],
        alignment: .leading,
        spacing: DesignTokens.spacingSM
      ) {
        ForEach(
          PlannerProductEconomics.outcomes(plan: plan, requestID: costs.requestID)
        ) { outcome in
          scenarioCard(outcome)
        }
      }
      allianceSection
    }
  }

  @ViewBuilder
  private var targetSection: some View {
    if isHistorical {
      LabeledContent(
        "Target market",
        value: ProductionOverviewTargetMarketPresentation.text(decision.targetMarket)
      )
    }
    if let suggestion = PlannerProductEconomics.suggestion(
      plan: plan,
      requestID: costs.requestID
    ) {
      Text(
        AppLocalization.format(
          "Suggestion: %@ (highest available profit %@)",
          PlannerProductFormat.market(suggestion.market),
          PlannerProductFormat.isk(suggestion.profit)
        )
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    } else {
      Text(
        "No sale scenario has an available, final profit, so no target market is suggested."
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var selectedSale: PlannerProfitabilityScenario? {
    PlannerProfitability(plan: plan).products.first { $0.id == costs.requestID }?.selected
  }

  private func scenarioCard(_ outcome: PlannerProductSaleOutcome) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(
        "\(PlannerProductFormat.scenario(outcome.scenario)) · \(PlannerProductFormat.market(outcome.market))"
      )
      .appFont(.subheadline.weight(.semibold))
      LabeledContent("Profit", value: PlannerProductFormat.isk(outcome.profit))
      LabeledContent("ROI", value: PlannerProductFormat.percent(outcome.roi))
      LabeledContent("Total cost", value: PlannerProductFormat.isk(outcome.totalCost))
      if outcome.hasPendingCost {
        Label(
          "Pending costs are not treated as 0 ISK.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .appFont(.caption2)
        .foregroundStyle(DesignTokens.caution)
      }
    }
    .appFont(.caption.monospacedDigit())
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      if selectedSale?.market == outcome.market, selectedSale?.scenario == outcome.scenario {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.accent, lineWidth: 2)
      }
    }
  }

  @ViewBuilder
  private var allianceSection: some View {
    let result = decision.allianceSale
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Alliance market (manual)")
        .appFont(.subheadline.weight(.semibold))
      if let result {
        HStack(spacing: DesignTokens.spacingMD) {
          LabeledContent(
            result.isProvisional ? "Profit (provisional)" : "Profit",
            value: PlannerProductFormat.isk(result.profit)
          )
          LabeledContent("ROI", value: PlannerProductFormat.percent(result.roi))
        }
        .appFont(.caption.monospacedDigit())
        if let reason = result.unavailableReason {
          Label(reason.localizedUI, systemImage: "exclamationmark.triangle")
            .appFont(.caption2)
            .foregroundStyle(DesignTokens.caution)
        }
      }
    }
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      if selectedSale?.market == .allianceMarket {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.accent, lineWidth: 2)
      }
    }
  }
}

/// Draft key of a product decision. Request IDs change with every calculation,
/// the input line and product name do not.
struct PlannerProductDecisionDraft: Codable, Equatable {
  var targetMarket: PlannerTargetMarket?
  var allianceInput: PlannerAllianceSaleInput?
  var saleScenario: PriceScenario?

  static func key(for request: ProductionRequestLine) -> String {
    "\(request.lineNumber):\(request.productName)"
  }
}
