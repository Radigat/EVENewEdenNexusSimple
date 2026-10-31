import EVENexusCore
import SwiftUI

enum PlannerProductSortColumn: Hashable {
  case product, units, material, installation, blueprint, logistics
  case totalCost, costPerUnit, target, revenue, profit, roi
}

/// Per-product path of a plan with several end products: cost shares, sale
/// decision and profit. Single-product plans keep the plan-wide panels.
struct PlannerProductEconomicsPanel: View {
  let plan: IndustryPlanSnapshot
  let isHistorical: Bool
  let contractFeeRate: (PlannerTargetMarket?) -> Double?
  let onDecisionChange: (UUID, PlannerProductDecision) -> Void

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
    return (plan.productEconomics ?? []).map { costs in
      let chosen = PlannerProductEconomics.chosenOutcome(
        plan: plan,
        requestID: costs.requestID
      )
      return Row(
        costs: costs,
        lineNumber: lines[costs.requestID] ?? 0,
        target: plan.targetMarket(for: costs.requestID),
        revenue: chosen?.netRevenue,
        profit: chosen?.profit,
        roi: chosen?.roi
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
      .font(.caption)
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
          .font(.caption.weight(.semibold))
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
            .font(.body.monospacedDigit())
          }
          Divider()
          GridRow {
            Text("Total").font(.body.weight(.semibold))
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
          .font(.body.monospacedDigit().weight(.semibold))
        }
        .padding(.bottom, DesignTokens.spacingXS)
      }
      .accessibilityIdentifier("planner.products.table")
      if let costs = selectedCosts {
        Divider()
        PlannerProductSaleDetail(
          plan: plan,
          costs: costs,
          isHistorical: isHistorical,
          contractFeeRate: contractFeeRate,
          onDecisionChange: onDecisionChange
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

/// Target market, scenarios and alliance input of one product.
private struct PlannerProductSaleDetail: View {
  let plan: IndustryPlanSnapshot
  let costs: PlannerProductCosts
  let isHistorical: Bool
  let contractFeeRate: (PlannerTargetMarket?) -> Double?
  let onDecisionChange: (UUID, PlannerProductDecision) -> Void

  @State private var unitPriceText = ""
  @State private var acceptedText = ""
  @State private var feeText = ""
  @State private var deliveryHub: PlannerTargetMarket?
  @State private var inputError: String?

  private var decision: PlannerProductDecision {
    plan.productDecisions?[costs.requestID] ?? PlannerProductDecision()
  }

  private var locale: Locale { AppLocalization.currentLanguage.locale }

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
    .onAppear(perform: fillFields)
  }

  @ViewBuilder
  private var targetSection: some View {
    if isHistorical {
      LabeledContent(
        "Target market",
        value: ProductionOverviewTargetMarketPresentation.text(decision.targetMarket)
      )
    } else {
      Picker(
        "Target market",
        selection: Binding(
          get: { decision.targetMarket },
          set: { market in
            var updated = decision
            updated.targetMarket = market
            onDecisionChange(costs.requestID, updated)
          }
        )
      ) {
        Text("Not chosen").tag(PlannerTargetMarket?.none)
        ForEach(PlannerTargetMarket.allCases, id: \.self) { market in
          Text(PlannerProductFormat.market(market))
            .tag(PlannerTargetMarket?.some(market))
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("planner.products.target-market")
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
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    } else {
      Text(
        "No sale scenario has an available, final profit, so no target market is suggested."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func scenarioCard(_ outcome: PlannerProductSaleOutcome) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(
        "\(PlannerProductFormat.scenario(outcome.scenario)) · \(PlannerProductFormat.market(outcome.market))"
      )
      .font(.subheadline.weight(.semibold))
      LabeledContent("Profit", value: PlannerProductFormat.isk(outcome.profit))
      LabeledContent("ROI", value: PlannerProductFormat.percent(outcome.roi))
      LabeledContent("Total cost", value: PlannerProductFormat.isk(outcome.totalCost))
      if outcome.hasPendingCost {
        Label(
          "Pending costs are not treated as 0 ISK.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption2)
        .foregroundStyle(DesignTokens.caution)
      }
    }
    .font(.caption.monospacedDigit())
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      if decision.targetMarket == outcome.market {
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
        .font(.subheadline.weight(.semibold))
      if let result {
        HStack(spacing: DesignTokens.spacingMD) {
          LabeledContent(
            result.isProvisional ? "Profit (provisional)" : "Profit",
            value: PlannerProductFormat.isk(result.profit)
          )
          LabeledContent("ROI", value: PlannerProductFormat.percent(result.roi))
        }
        .font(.caption.monospacedDigit())
        if let reason = result.unavailableReason {
          Label(reason.localizedUI, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(DesignTokens.caution)
        }
      }
      if !isHistorical {
        Grid(alignment: .leading, verticalSpacing: DesignTokens.spacingXS) {
          GridRow {
            Text("Unit price (ISK)").font(.caption)
            TextField("Required", text: $unitPriceText)
              .textFieldStyle(.roundedBorder)
              .groupedNumberInput($unitPriceText)
              .accessibilityIdentifier("planner.products.alliance.unit-price")
          }
          GridRow {
            Text("Accepted units").font(.caption)
            TextField("All produced units", text: $acceptedText)
              .textFieldStyle(.roundedBorder)
              .groupedNumberInput($acceptedText, allowsFraction: false)
          }
          GridRow {
            Text("Fee (%)").font(.caption)
            TextField("Optional", text: $feeText)
              .textFieldStyle(.roundedBorder)
          }
          GridRow {
            Text("Delivery").font(.caption)
            Picker("Delivery", selection: $deliveryHub) {
              Text("Production location").tag(PlannerTargetMarket?.none)
              ForEach(
                PlannerTargetMarket.allCases.filter { $0 != .allianceMarket },
                id: \.self
              ) { market in
                Text(PlannerProductFormat.market(market))
                  .tag(PlannerTargetMarket?.some(market))
              }
            }
            .labelsHidden()
          }
        }
        .frame(maxWidth: 420)
        if let inputError {
          Text(inputError).font(.caption2).foregroundStyle(DesignTokens.negative)
        }
        Button("Apply alliance sale", action: apply)
          .buttonStyle(.bordered)
          .accessibilityIdentifier("planner.products.alliance.apply")
      }
    }
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      if decision.targetMarket == .allianceMarket {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.accent, lineWidth: 2)
      }
    }
  }

  private func fillFields() {
    guard let input = decision.allianceSale?.input else { return }
    unitPriceText =
      input.unitPrice.map { $0.formatted(.number.locale(locale).grouping(.automatic)) } ?? ""
    acceptedText =
      input.acceptedQuantity.map {
        $0.formatted(.number.locale(locale).grouping(.automatic))
      } ?? ""
    feeText =
      input.feeRate.map { ($0 * 100).formatted(.number.locale(locale).grouping(.never)) } ?? ""
    deliveryHub = input.deliveryHub
  }

  private func apply() {
    guard
      let input = PlannerAllianceInputParser.input(
        unitPrice: unitPriceText,
        acceptedQuantity: acceptedText,
        feePercent: feeText,
        deliveryHub: deliveryHub,
        producedQuantity: costs.units,
        locale: locale
      )
    else {
      inputError = AppLocalization.text(
        "Check the alliance fields: price and fee must be numbers, the accepted quantity a whole number of at least 1 and the fee below 100 %."
      )
      return
    }
    inputError = nil
    var updated = decision
    updated.allianceSale = PlannerAllianceSaleCalculator.calculate(
      plan: plan,
      input: input,
      publicContractFeeRate: contractFeeRate(input.deliveryHub),
      requestID: costs.requestID
    )
    onDecisionChange(costs.requestID, updated)
  }
}

/// Draft key of a product decision. Request IDs change with every calculation,
/// the input line and product name do not.
struct PlannerProductDecisionDraft: Codable, Equatable {
  var targetMarket: PlannerTargetMarket?
  var allianceInput: PlannerAllianceSaleInput?

  static func key(for request: ProductionRequestLine) -> String {
    "\(request.lineNumber):\(request.productName)"
  }
}
