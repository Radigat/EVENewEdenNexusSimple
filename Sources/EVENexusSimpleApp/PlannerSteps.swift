import EVENexusCore
import SwiftUI

extension PlannerStep {
  var title: LocalizedStringKey {
    switch self {
    case .settings: "Settings"
    case .products: "Products"
    case .stock: "Warehouse"
    case .costs: "Costs"
    case .adjust: "Adjust"
    case .shopping: "Purchasing"
    case .jobs: "Build jobs"
    case .sale: "Sale"
    }
  }
}

extension IndustryPlannerError {
  var localizedUI: String {
    String(
      format: AppLocalization.text(message.format),
      locale: AppLocalization.currentLanguage.locale,
      arguments: message.arguments
    )
  }
}

extension DomainWarning {
  /// The warning in the app language. Values such as item names pass through
  /// unchanged because they have no translation.
  var localizedUI: String {
    guard let text else { return AppLocalization.text(message) }
    return String(
      format: AppLocalization.text(text.format),
      locale: AppLocalization.currentLanguage.locale,
      arguments: text.arguments.map { AppLocalization.text($0) }
    )
  }
}

/// The Planner's departments. Only steps the plan has reached can be opened.
struct PlannerStepBar: View {
  let current: PlannerStep
  let access: PlannerStepAccess
  let onSelect: (PlannerStep) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: DesignTokens.spacingXS) {
        ForEach(PlannerStep.allCases) { step in
          button(for: step)
          if step != PlannerStep.allCases.last {
            Image(systemName: "chevron.right")
              .font(.caption2)
              .foregroundStyle(DesignTokens.textSecondary)
              .accessibilityHidden(true)
          }
        }
      }
      .padding(.vertical, DesignTokens.spacingXS)
    }
    .accessibilityIdentifier("planner.steps")
  }

  private func button(for step: PlannerStep) -> some View {
    let isCurrent = step == current
    let isDone = step < current && access.isReachable(step)
    return Button {
      onSelect(step)
    } label: {
      HStack(spacing: DesignTokens.spacingXS) {
        if isDone {
          Image(systemName: "checkmark").font(.caption2.weight(.bold))
        } else {
          Text(step.rawValue.formatted()).font(.caption.monospacedDigit().weight(.semibold))
        }
        Text(step.title).lineLimit(1).fixedSize()
      }
      .font(.callout.weight(isCurrent ? .semibold : .regular))
      .foregroundStyle(
        isCurrent
          ? DesignTokens.accent
          : (access.isReachable(step) ? DesignTokens.textPrimary : DesignTokens.textSecondary)
      )
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .background(
        isCurrent ? DesignTokens.accentSoft : Color.clear,
        in: RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
      )
      .contentShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    }
    .buttonStyle(.plain)
    .disabled(!access.isReachable(step))
    .accessibilityLabel(Text(step.title))
    .accessibilityValue(
      Text(isCurrent ? "Current step" : isDone ? "Done" : access.isReachable(step) ? "Open" : "Locked")
    )
    .accessibilityIdentifier("planner.step.\(step.rawValue)")
  }
}

/// Back and Next below the current step, with the reason when Next is locked.
struct PlannerStepNavigation: View {
  let current: PlannerStep
  let access: PlannerStepAccess
  let onSelect: (PlannerStep) -> Void

  private var lockedReason: LocalizedStringKey? {
    guard access.next(after: current) == nil,
      let next = PlannerStep(rawValue: current.rawValue + 1)
    else { return nil }
    switch next {
    case .settings, .products: return nil
    case .stock: return "Correct the product input first."
    case .costs: return "Calculate the plan first."
    case .adjust, .shopping, .jobs, .sale:
      return "Decide on the profitability warning first."
    }
  }

  var body: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      if let previous = access.previous(before: current) {
        Button("Back") { onSelect(previous) }
          .accessibilityIdentifier("planner.step.back")
      }
      Spacer()
      if let lockedReason {
        Text(lockedReason)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if current != PlannerStep.allCases.last {
        Button("Next") {
          if let next = access.next(after: current) { onSelect(next) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(access.next(after: current) == nil)
        .accessibilityIdentifier("planner.step.next")
      }
    }
  }
}

enum PlannerMaterialCheckSortColumn: Hashable {
  case item, required, fromStock, toBuy, toProduce
}

/// Answers "does the warehouse cover the order?" with the plan's own amounts.
struct PlannerMaterialCheckPanel: View {
  let materials: [MaterialRequirement]

  @State private var isExpanded = false
  @State private var sort = AppTableSortDescriptor(
    column: PlannerMaterialCheckSortColumn.item,
    direction: .ascending
  )

  private var rows: [MaterialRequirement] {
    materials
      .filter { $0.fromStock > 0 || $0.toBuy > 0 }
      .sorted { lhs, rhs in
        let ascending: Bool? =
          switch sort.column {
          case .item:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame
              ? nil : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
          case .required: order(lhs.required, rhs.required)
          case .fromStock: order(lhs.fromStock, rhs.fromStock)
          case .toBuy: order(lhs.toBuy, rhs.toBuy)
          case .toProduce: order(lhs.toProduce, rhs.toProduce)
          }
        guard let ascending else { return lhs.typeID < rhs.typeID }
        return sort.direction == .ascending ? ascending : !ascending
      }
  }

  private func order(_ lhs: Int64, _ rhs: Int64) -> Bool? {
    lhs == rhs ? nil : lhs < rhs
  }

  var body: some View {
    let fromStock = materials.filter { $0.fromStock > 0 }.count
    let rebought = materials.filter { $0.fromStock > 0 && $0.toBuy > 0 }.count
    let bought = materials.filter { $0.fromStock == 0 && $0.toBuy > 0 }.count
    Panel(title: "Material check") {
      Label(
        AppLocalization.format(
          "From the warehouse: %lld materials, of which topped up from the market: %lld. Only from the market: %lld.",
          Int64(fromStock),
          Int64(rebought),
          Int64(bought)
        ),
        systemImage: rebought + bought > 0 ? "cart" : "checkmark.circle"
      )
      FullWidthDisclosure(isExpanded: $isExpanded) {
        Text("Quantities per material")
      } content: {
        ScrollView(.horizontal) {
          Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
              header("Item", .item, alignment: .leading)
              header("Required", .required)
              header("From warehouse", .fromStock)
              header("From market", .toBuy)
              header("Build", .toProduce)
            }
            .font(.caption.weight(.semibold))
            Divider()
            ForEach(rows) { material in
              GridRow {
                EVEEntityText(value: material.name, font: .body)
                  .gridColumnAlignment(.leading)
                Text(material.required.formatted())
                Text(material.fromStock.formatted())
                Text(material.toBuy.formatted())
                Text(material.toProduce.formatted())
              }
              .font(.body.monospacedDigit())
            }
          }
          .padding(.bottom, DesignTokens.spacingXS)
        }
        .padding(.top, DesignTokens.spacingSM)
      }
      .accessibilityIdentifier("planner.material-check.disclosure")
    }
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: PlannerMaterialCheckSortColumn,
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
