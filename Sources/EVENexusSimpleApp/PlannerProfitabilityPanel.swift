import EVENexusCore
import SwiftUI

enum PlannerSaleChoiceSortColumn: Hashable {
  case product, units, subtotal, landedCost, costPerUnit, minimumPrice
  case sale, revenue, profit, roi, status
}

enum PlannerAllianceSortColumn: Hashable {
  case product, units, price, fee, delivery
}

enum PlannerSaleSummarySortColumn: Hashable {
  case product, units, sale, revenue, cost, profit, roi
}

/// Missing values follow known ones ascending and precede them descending.
private func plannerSaleOrder<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
  switch (lhs, rhs) {
  case (nil, nil): nil
  case (nil, _): false
  case (_, nil): true
  case (let lhs?, let rhs?): lhs == rhs ? nil : lhs < rhs
  }
}

private func plannerProfitColor(_ profit: Double?) -> Color {
  guard let profit else { return DesignTokens.textSecondary }
  return profit > 0 ? DesignTokens.positive : DesignTokens.negative
}

private func plannerNameOrder(_ lhs: String, _ rhs: String) -> Bool? {
  let order = lhs.localizedCaseInsensitiveCompare(rhs)
  return order == .orderedSame ? nil : order == .orderedAscending
}

/// Step 4's answer to "Profitable?": one row per product with its costs and the
/// selected sale, the alliance prices and the owner's decision when a selected
/// sale earns no money.
struct PlannerProfitabilityPanel: View {
  let plan: IndustryPlanSnapshot
  let confirmedKey: String?
  /// Products whose line is still in the input and can be taken out.
  let removableRequestIDs: Set<UUID>
  let onConfirm: (String) -> Void
  let onRemove: (ProductionRequestLine) -> Void
  let onChoose: (ProductionRequestLine, PlannerProfitabilityScenario) -> Void
  let onAllianceInput: (ProductionRequestLine, PlannerAllianceSaleInput) -> Void

  private var profitability: PlannerProfitability { PlannerProfitability(plan: plan) }

  private var isCollective: Bool { profitability.products.count > 1 }

  private var usesStock: Bool { plan.materials.contains { $0.fromStock > 0 } }

  private var flaggedProducts: [PlannerProductProfitability] {
    profitability.products.filter { $0.verdict != .profitable }
  }

  var body: some View {
    Panel(title: "Profitable?") {
      verdictLabel
      PlannerSaleChoiceTable(plan: plan, onChoose: onChoose)
      if isCollective, usesStock {
        Text(
          "Stock goes to the upper product line first. The total stays the same, but the split between products depends on the order."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Divider()
      PlannerAllianceSaleTable(plan: plan, onApply: onAllianceInput)
      if profitability.needsDecision {
        decisionBlock
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("planner.profitability")
  }

  @ViewBuilder
  private var verdictLabel: some View {
    switch profitability.verdict {
    case .profitable:
      Label(
        AppLocalization.format(
          "Yes. Selected sales: %@ profit.",
          PlannerProductFormat.isk(profitability.totalProfit)
        ),
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(DesignTokens.positive)
    case .unprofitable:
      Label(
        "No. At least one selected sale makes no profit.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(DesignTokens.negative)
    case .notCheckable:
      Label(
        "Not checkable. Prices are missing or costs are still provisional.",
        systemImage: "questionmark.circle.fill"
      )
      .foregroundStyle(DesignTokens.caution)
    }
  }

  @ViewBuilder
  private var decisionBlock: some View {
    let key = profitability.confirmationKey(planID: plan.id)
    Divider()
    if isCollective {
      ForEach(flaggedProducts) { product in
        HStack(spacing: DesignTokens.spacingSM) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(DesignTokens.caution)
            .accessibilityHidden(true)
          EVEEntityText(value: product.request.productName, font: .body)
          Text(PlannerSaleChoiceTable.statusText(product.verdict))
            .foregroundStyle(DesignTokens.textSecondary)
          Spacer()
          if removableRequestIDs.contains(product.id) {
            Button("Remove") { onRemove(product.request) }
              .accessibilityLabel(
                Text(
                  AppLocalization.format("Remove %@", product.request.productName)
                )
              )
          }
        }
      }
    }
    HStack(spacing: DesignTokens.spacingSM) {
      if confirmedKey == key {
        Label("You chose to produce anyway.", systemImage: "hand.thumbsup")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Text("Decide whether to produce anyway. Your decision applies to this calculation and these sales only.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        Button("Produce anyway") { onConfirm(key) }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("planner.profitability.confirm")
      }
    }
  }
}

/// One row per product: its share of the costs and the sale selected for it.
/// Revenue minus the cost column is the profit of the same row.
struct PlannerSaleChoiceTable: View {
  let plan: IndustryPlanSnapshot
  let onChoose: (ProductionRequestLine, PlannerProfitabilityScenario) -> Void

  @State private var sort = AppTableSortDescriptor(
    column: PlannerSaleChoiceSortColumn.product,
    direction: .ascending
  )

  private struct Row: Identifiable {
    let product: PlannerProductProfitability
    let costs: PlannerProductCosts?
    let units: Int64?
    let figures: PlannerSaleFigures
    var id: UUID { product.id }
    var selected: PlannerProfitabilityScenario? { product.selected }
  }

  private var profitability: PlannerProfitability { PlannerProfitability(plan: plan) }

  private var rows: [Row] {
    profitability.products.map { product in
      let costs = plan.productCosts(for: product.id)
      let units = costs?.units ?? plan.topLevelProductNode(for: product.id)?.requiredQuantity
      return Row(
        product: product,
        costs: costs,
        units: units,
        figures: PlannerSaleFigures(costs: costs, units: units, sale: product.selected)
      )
    }
  }

  private var sortedRows: [Row] {
    rows.sorted { lhs, rhs in
      let ascending: Bool? =
        switch sort.column {
        case .product:
          plannerNameOrder(lhs.product.request.productName, rhs.product.request.productName)
        case .units: plannerSaleOrder(lhs.units, rhs.units)
        case .subtotal:
          plannerSaleOrder(lhs.costs?.productionSubtotal, rhs.costs?.productionSubtotal)
        case .landedCost: plannerSaleOrder(lhs.figures.cost, rhs.figures.cost)
        case .costPerUnit: plannerSaleOrder(lhs.figures.costPerItem, rhs.figures.costPerItem)
        case .minimumPrice: plannerSaleOrder(lhs.figures.minimumPrice, rhs.figures.minimumPrice)
        case .sale:
          plannerSaleOrder(lhs.selected.map(Self.title), rhs.selected.map(Self.title))
        case .revenue: plannerSaleOrder(lhs.selected?.netRevenue, rhs.selected?.netRevenue)
        case .profit: plannerSaleOrder(lhs.selected?.profit, rhs.selected?.profit)
        case .roi: plannerSaleOrder(lhs.selected?.roi, rhs.selected?.roi)
        case .status:
          plannerSaleOrder(lhs.product.verdict.rawValue, rhs.product.verdict.rawValue)
        }
      guard let ascending else {
        return lhs.product.request.lineNumber < rhs.product.request.lineNumber
      }
      return sort.direction == .ascending ? ascending : !ascending
    }
  }

  static func statusText(_ verdict: PlannerProfitabilityVerdict) -> String {
    switch verdict {
    case .profitable: AppLocalization.text("Profitable")
    case .unprofitable: AppLocalization.text("Not profitable")
    case .notCheckable: AppLocalization.text("Not checkable")
    }
  }

  /// The alliance sale has no scenario, so its market is its whole name.
  static func title(_ sale: PlannerProfitabilityScenario) -> String {
    let market = PlannerProductFormat.market(sale.market)
    guard let scenario = sale.scenario else { return market }
    return "\(market) · \(PlannerProductFormat.scenario(scenario))"
  }

  /// "~" marks a value that still lacks a manual transport or contract fee.
  static func money(_ value: Double?, _ sale: PlannerProfitabilityScenario?) -> String {
    let text = PlannerProductFormat.isk(value)
    return sale?.isProvisional == true && value != nil ? "~ \(text)" : text
  }

  private static func optionTitle(
    _ option: PlannerProfitabilityScenario,
    product: PlannerProductProfitability
  ) -> String {
    let title = AppLocalization.format(
      "%@ · profit: %@",
      title(option),
      money(option.profit, option)
    )
    return option == product.best
      ? AppLocalization.format("%@ (suggestion)", title) : title
  }

  /// A sum exists only when every product's value is known.
  private func total(_ value: (Row) -> Double?) -> Double? {
    var sum = 0.0
    for row in rows {
      guard let part = value(row), part.isFinite else { return nil }
      sum += part
    }
    return sum.isFinite ? sum : nil
  }

  var body: some View {
    ScrollView(.horizontal) {
      Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow {
          header("Product", .product, alignment: .leading)
          header("Units", .units)
          header("Subtotal", .subtotal)
            .help(Text("Material, installation and BPC/BPO of this product."))
          header("Incl. delivery", .landedCost)
            .help(Text("All costs of this product for the selected sale, including transport."))
          header("Cost per item", .costPerUnit)
          header("Minimum price", .minimumPrice)
            .help(Text("The unit price at which the sold units exactly cover all costs and fees."))
          header("Sale", .sale, alignment: .leading)
          header("Net revenue", .revenue)
            .help(Text("Price times sold units, minus taxes and fees."))
          header("Profit", .profit)
          header("ROI", .roi)
          header("Status", .status, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        Divider()
        ForEach(sortedRows) { row in
          GridRow {
            EVEEntityText(value: row.product.request.productName, font: .body)
              .gridColumnAlignment(.leading)
            Text(row.units.map { $0.formatted() } ?? AppLocalization.text("Unavailable"))
            Text(PlannerProductFormat.isk(row.costs?.productionSubtotal))
            Text(Self.money(row.figures.cost, row.selected))
            Text(PlannerProductFormat.unitISK(row.figures.costPerItem))
            Text(PlannerProductFormat.unitISK(row.figures.minimumPrice))
            saleMenu(row)
              .gridColumnAlignment(.leading)
            Text(Self.money(row.selected?.netRevenue, row.selected))
            Text(Self.money(row.selected?.profit, row.selected))
              .foregroundStyle(plannerProfitColor(row.selected?.profit))
            Text(PlannerProductFormat.percent(row.selected?.roi))
            Text(Self.statusText(row.product.verdict))
              .foregroundStyle(
                row.product.verdict == .profitable
                  ? DesignTokens.positive : DesignTokens.caution
              )
              .gridColumnAlignment(.leading)
          }
          .font(.body.monospacedDigit())
        }
        if rows.count > 1 {
          Divider()
          GridRow {
            Text("Total").gridColumnAlignment(.leading)
            Text("")
            Text(PlannerProductFormat.isk(total { $0.costs?.productionSubtotal }))
            Text(PlannerProductFormat.isk(total(\.figures.cost)))
            Text("")
            Text("")
            Text("")
            Text(PlannerProductFormat.isk(profitability.totalRevenue))
            Text(PlannerProductFormat.isk(profitability.totalProfit))
              .foregroundStyle(plannerProfitColor(profitability.totalProfit))
            Text("")
            Text("")
          }
          .font(.body.monospacedDigit().weight(.semibold))
        }
      }
      .padding(.bottom, DesignTokens.spacingXS)
    }
    .accessibilityIdentifier("planner.sale-choice.table")
  }

  /// Closed it names the sale only; open it shows each option's profit.
  private func saleMenu(_ row: Row) -> some View {
    Menu {
      ForEach(row.product.options) { option in
        Button {
          onChoose(row.product.request, option)
        } label: {
          Text(Self.optionTitle(option, product: row.product))
        }
      }
    } label: {
      Text(row.selected.map(Self.title) ?? AppLocalization.text("Not chosen"))
    }
    .fixedSize()
    .accessibilityLabel(
      Text(AppLocalization.format("Sale of %@", row.product.request.productName))
    )
    .accessibilityValue(
      Text(row.selected.map(Self.title) ?? AppLocalization.text("Not chosen"))
    )
    .accessibilityIdentifier("planner.sale-choice.\(row.product.request.lineNumber)")
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerSaleChoiceSortColumn,
    alignment: Alignment = .trailing
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      alignment: alignment
    )
  }
}

/// The owner's alliance prices: one row per product. Applying a row selects the
/// alliance market for that product.
struct PlannerAllianceSaleTable: View {
  let plan: IndustryPlanSnapshot
  let onApply: (ProductionRequestLine, PlannerAllianceSaleInput) -> Void

  @State private var sort = AppTableSortDescriptor(
    column: PlannerAllianceSortColumn.product,
    direction: .ascending
  )

  private struct Row: Identifiable {
    let request: ProductionRequestLine
    let produced: Int64?
    let result: PlannerAllianceSaleResult?
    var id: UUID { request.id }
  }

  private var rows: [Row] {
    plan.requests.map { request in
      Row(
        request: request,
        produced: plan.productCosts(for: request.id)?.units
          ?? plan.topLevelProductNode(for: request.id)?.requiredQuantity,
        result: plan.allianceSale(for: request.id)
      )
    }
  }

  private var sortedRows: [Row] {
    rows.sorted { lhs, rhs in
      let ascending: Bool? =
        switch sort.column {
        case .product: plannerNameOrder(lhs.request.productName, rhs.request.productName)
        case .units: plannerSaleOrder(Self.units(lhs), Self.units(rhs))
        case .price:
          plannerSaleOrder(lhs.result?.input.unitPrice, rhs.result?.input.unitPrice)
        case .fee: plannerSaleOrder(lhs.result?.input.feeRate, rhs.result?.input.feeRate)
        case .delivery:
          plannerNameOrder(Self.deliveryName(lhs), Self.deliveryName(rhs))
        }
      guard let ascending else { return lhs.request.lineNumber < rhs.request.lineNumber }
      return sort.direction == .ascending ? ascending : !ascending
    }
  }

  private static func units(_ row: Row) -> Int64? {
    row.result?.input.acceptedQuantity ?? row.produced
  }

  private static func deliveryName(_ row: Row) -> String {
    row.result?.input.deliveryHub.map(PlannerProductFormat.market)
      ?? AppLocalization.text("Production location")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Alliance market (manual)")
        .font(.subheadline.weight(.semibold))
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow {
          header("Product", .product)
          header("Units", .units)
          header("Unit price (ISK)", .price)
          header("Fee (%)", .fee)
          header("Delivery", .delivery)
          Text("")
        }
        .font(.caption.weight(.semibold))
        Divider()
        ForEach(sortedRows) { row in
          PlannerAllianceSaleRow(
            request: row.request,
            produced: row.produced,
            result: row.result,
            onApply: { onApply(row.request, $0) }
          )
        }
      }
      .fixedSize(horizontal: true, vertical: false)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("planner.alliance.table")
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerAllianceSortColumn
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      alignment: .leading
    )
  }
}

private struct PlannerAllianceSaleRow: View {
  /// A prefilled assumption the owner can overwrite; no known market fee.
  private static let defaultFeePercent = "2"

  let request: ProductionRequestLine
  let produced: Int64?
  let result: PlannerAllianceSaleResult?
  let onApply: (PlannerAllianceSaleInput) -> Void

  @State private var unitPriceText = ""
  @State private var unitsText = ""
  @State private var feeText = PlannerAllianceSaleRow.defaultFeePercent
  @State private var deliveryHub: PlannerTargetMarket?
  @State private var inputError: String?

  private var locale: Locale { AppLocalization.currentLanguage.locale }

  private var message: String? {
    inputError ?? result?.unavailableReason?.localizedUI
  }

  var body: some View {
    GridRow {
      EVEEntityText(value: request.productName, font: .body)
      unitsControl
      TextField("Required", text: $unitPriceText)
        .textFieldStyle(.roundedBorder)
        .groupedNumberInput($unitPriceText)
        .frame(width: 170)
        .onSubmit(apply)
        .accessibilityLabel(Text(AppLocalization.format("Unit price of %@", request.productName)))
        .accessibilityIdentifier("planner.alliance.\(request.lineNumber).unit-price")
      TextField("Fee (%)", text: $feeText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
        .labelsHidden()
        .onSubmit(apply)
        .accessibilityLabel(Text(AppLocalization.format("Fee of %@", request.productName)))
        .accessibilityIdentifier("planner.alliance.\(request.lineNumber).fee")
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
      .fixedSize()
      .accessibilityLabel(Text(AppLocalization.format("Delivery of %@", request.productName)))
      .accessibilityIdentifier("planner.alliance.\(request.lineNumber).delivery")
      Button("Apply", action: apply)
        .buttonStyle(.bordered)
        .accessibilityLabel(
          Text(AppLocalization.format("Apply alliance sale of %@", request.productName))
        )
        .accessibilityIdentifier("planner.alliance.\(request.lineNumber).apply")
    }
    .onAppear(perform: fillFields)
    if let message {
      GridRow {
        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(inputError == nil ? DesignTokens.caution : DesignTokens.negative)
          .gridCellColumns(5)
      }
    }
  }

  /// The field never holds more than was produced; the arrows stay within 1 and that.
  private var unitsControl: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      TextField("Units", text: $unitsText)
        .textFieldStyle(.roundedBorder)
        .groupedNumberInput($unitsText, allowsFraction: false)
        .frame(width: 70)
        .labelsHidden()
        .onChange(of: unitsText) {
          let limited = PlannerAllianceInputParser.limitedUnitsText(
            unitsText,
            produced: produced,
            locale: locale
          )
          if limited != unitsText { unitsText = limited }
        }
        .onKeyPress(.upArrow) { stepUnits(by: 1) }
        .onKeyPress(.downArrow) { stepUnits(by: -1) }
        .onSubmit(apply)
        .accessibilityLabel(Text(AppLocalization.format("Units of %@", request.productName)))
        .accessibilityIdentifier("planner.alliance.\(request.lineNumber).units")
      if let produced, produced >= 1 {
        Stepper(
          "Units",
          value: Binding(
            get: { currentUnits(produced: produced) },
            set: { unitsText = formattedUnits($0) }
          ),
          in: 1...produced
        )
        .labelsHidden()
        .accessibilityLabel(Text(AppLocalization.format("Units of %@", request.productName)))
        .accessibilityIdentifier("planner.alliance.\(request.lineNumber).units.stepper")
        Text(AppLocalization.format("of %@", produced.formatted()))
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func formattedUnits(_ units: Int64) -> String {
    units.formatted(.number.locale(locale).grouping(.automatic))
  }

  /// An empty field means all produced units, like the saved input.
  private func currentUnits(produced: Int64) -> Int64 {
    if case .value(let value) = PlannerAllianceInputParser.number(unitsText, locale: locale),
      value >= 1, value < Double(Int64.max)
    {
      return min(Int64(value), produced)
    }
    return produced
  }

  private func stepUnits(by delta: Int64) -> KeyPress.Result {
    guard let produced, produced >= 1 else { return .ignored }
    unitsText = formattedUnits(min(max(currentUnits(produced: produced) + delta, 1), produced))
    return .handled
  }

  private func fillFields() {
    let number = FloatingPointFormatStyle<Double>.number.locale(locale)
    let units = result?.input.acceptedQuantity ?? produced
    unitsText = units?.formatted(.number.locale(locale).grouping(.automatic)) ?? ""
    guard let input = result?.input else { return }
    unitPriceText = input.unitPrice.map { $0.formatted(number.grouping(.automatic)) } ?? ""
    feeText = input.feeRate.map { ($0 * 100).formatted(number.grouping(.never)) } ?? ""
    deliveryHub = input.deliveryHub
  }

  private func apply() {
    guard
      let input = PlannerAllianceInputParser.input(
        unitPrice: unitPriceText,
        acceptedQuantity: unitsText,
        feePercent: feeText,
        deliveryHub: deliveryHub,
        producedQuantity: produced,
        locale: locale
      )
    else {
      inputError = AppLocalization.text(
        "Check the alliance fields: price and fee must be numbers, the units a whole number from 1 to the produced quantity and the fee below 100 %."
      )
      return
    }
    inputError = nil
    onApply(input)
  }
}

enum PlannerProductCharacterSortColumn: Hashable {
  case product, units, location, character
}

/// Where a product is built and which kind of job that is.
struct PlannerProductLocation: Equatable {
  let structureID: UUID
  let pool: IndustrySlotPool
}

struct PlannerProductCharacterRow: Identifiable {
  let productName: String
  let lineNumber: Int
  var units: Int64
  let structureName: String?
  let options: [CharacterIdentity]
  let selectedID: Int64?
  var id: String { productName }
  var selectedName: String? { options.first { $0.id == selectedID }?.name }
}

/// Step 3: the products to build, each with the character who builds it.
struct PlannerProductCharacterTable: View {
  let rows: [PlannerProductCharacterRow]
  let onChoose: (Int64, String) -> Void

  @State private var sort = AppTableSortDescriptor(
    column: PlannerProductCharacterSortColumn.product,
    direction: .ascending
  )

  private var sortedRows: [PlannerProductCharacterRow] {
    rows.sorted { lhs, rhs in
      let ascending: Bool? =
        switch sort.column {
        case .product: plannerNameOrder(lhs.productName, rhs.productName)
        case .units: plannerSaleOrder(lhs.units, rhs.units)
        case .location: plannerSaleOrder(lhs.structureName, rhs.structureName)
        case .character: plannerSaleOrder(lhs.selectedName, rhs.selectedName)
        }
      guard let ascending else { return lhs.lineNumber < rhs.lineNumber }
      return sort.direction == .ascending ? ascending : !ascending
    }
  }

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
      GridRow {
        header("Product", .product)
        header("Units", .units)
        header("Production location", .location)
        header("Character", .character)
      }
      .font(.caption.weight(.semibold))
      Divider()
      ForEach(sortedRows) { row in
        GridRow {
          EVEEntityText(value: row.productName, font: .body)
          Text(row.units.formatted())
            .font(.body.monospacedDigit())
          if let structureName = row.structureName {
            EVEEntityText(value: structureName, font: .body)
          } else {
            Text("Unavailable")
              .foregroundStyle(DesignTokens.textSecondary)
          }
          characterControl(row)
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("planner.product-characters.table")
  }

  @ViewBuilder
  private func characterControl(_ row: PlannerProductCharacterRow) -> some View {
    if let selectedID = row.selectedID {
      HStack(spacing: DesignTokens.spacingSM) {
        Picker(
          "Character",
          selection: Binding(
            get: { selectedID },
            set: { onChoose($0, row.productName) }
          )
        ) {
          ForEach(row.options) { character in
            Text(character.name).tag(character.id)
          }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(Text(AppLocalization.format("Character of %@", row.productName)))
        .accessibilityIdentifier("planner.product-character.\(row.lineNumber)")
        if let name = row.selectedName {
          EVEEntityText(value: name, font: .caption)
        }
      }
    } else {
      Text("No character")
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerProductCharacterSortColumn
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      alignment: .leading
    )
  }
}

/// Step 8: the read-only result of the choices made in step 4.
struct PlannerSaleSummaryPanel: View {
  let plan: IndustryPlanSnapshot
  let onChangeSale: () -> Void

  @State private var sort = AppTableSortDescriptor(
    column: PlannerSaleSummarySortColumn.product,
    direction: .ascending
  )

  private struct Row: Identifiable {
    let product: PlannerProductProfitability
    let units: Int64?
    let figures: PlannerSaleFigures
    var id: UUID { product.id }
    var selected: PlannerProfitabilityScenario? { product.selected }
  }

  private var profitability: PlannerProfitability { PlannerProfitability(plan: plan) }

  private var rows: [Row] {
    profitability.products.map { product in
      let costs = plan.productCosts(for: product.id)
      let units = costs?.units ?? plan.topLevelProductNode(for: product.id)?.requiredQuantity
      return Row(
        product: product,
        units: units,
        figures: PlannerSaleFigures(costs: costs, units: units, sale: product.selected)
      )
    }
  }

  private var sortedRows: [Row] {
    rows.sorted { lhs, rhs in
      let ascending: Bool? =
        switch sort.column {
        case .product:
          plannerNameOrder(lhs.product.request.productName, rhs.product.request.productName)
        case .units: plannerSaleOrder(lhs.units, rhs.units)
        case .sale:
          plannerSaleOrder(
            lhs.selected.map(PlannerSaleChoiceTable.title),
            rhs.selected.map(PlannerSaleChoiceTable.title)
          )
        case .revenue: plannerSaleOrder(lhs.selected?.netRevenue, rhs.selected?.netRevenue)
        case .cost: plannerSaleOrder(lhs.figures.cost, rhs.figures.cost)
        case .profit: plannerSaleOrder(lhs.selected?.profit, rhs.selected?.profit)
        case .roi: plannerSaleOrder(lhs.selected?.roi, rhs.selected?.roi)
        }
      guard let ascending else {
        return lhs.product.request.lineNumber < rhs.product.request.lineNumber
      }
      return sort.direction == .ascending ? ascending : !ascending
    }
  }

  var body: some View {
    Panel(title: "Summary") {
      Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow {
          header("Product", .product, alignment: .leading)
          header("Units", .units)
          header("Sale", .sale, alignment: .leading)
          header("Net revenue", .revenue)
          header("Costs", .cost)
          header("Profit", .profit)
          header("ROI", .roi)
        }
        .font(.caption.weight(.semibold))
        Divider()
        ForEach(sortedRows) { row in
          GridRow {
            EVEEntityText(value: row.product.request.productName, font: .body)
              .gridColumnAlignment(.leading)
            Text(row.units.map { $0.formatted() } ?? AppLocalization.text("Unavailable"))
            Text(row.selected.map(PlannerSaleChoiceTable.title) ?? AppLocalization.text("Not chosen"))
              .gridColumnAlignment(.leading)
            Text(PlannerSaleChoiceTable.money(row.selected?.netRevenue, row.selected))
            Text(PlannerSaleChoiceTable.money(row.figures.cost, row.selected))
            Text(PlannerSaleChoiceTable.money(row.selected?.profit, row.selected))
              .foregroundStyle(plannerProfitColor(row.selected?.profit))
            Text(PlannerProductFormat.percent(row.selected?.roi))
          }
          .font(.body.monospacedDigit())
        }
        if rows.count > 1 {
          Divider()
          GridRow {
            Text("Total").gridColumnAlignment(.leading)
            Text("")
            Text("")
            Text(PlannerProductFormat.isk(profitability.totalRevenue))
            Text(PlannerProductFormat.isk(profitability.totalCost))
            Text(PlannerProductFormat.isk(profitability.totalProfit))
              .foregroundStyle(plannerProfitColor(profitability.totalProfit))
            Text("")
          }
          .font(.body.monospacedDigit().weight(.semibold))
        }
      }
      Button("Change sale", action: onChangeSale)
        .accessibilityIdentifier("planner.summary.change-sale")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("planner.summary")
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerSaleSummarySortColumn,
    alignment: Alignment = .trailing
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      alignment: alignment
    )
  }
}
