import EVENexusCore
import SwiftUI

struct PlannerCalculationStatusLabel: View {
  let status: PlannerCalculationStatus
  let planDate: Date?

  var body: some View {
    Label(title, systemImage: icon)
      .font(.callout)
      .foregroundStyle(color)
      .accessibilityIdentifier("planner.status")
  }

  private var title: String {
    let date = planDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
    return switch status {
    case .calculating: AppLocalization.text("Calculating…")
    case .failed: AppLocalization.text("Calculation stopped")
    case .noPlan: AppLocalization.text("No plan yet")
    case .saved: AppLocalization.format("Saved plan, prices from %@", date)
    case .current: AppLocalization.format("Up to date, prices from %@", date)
    case .outdated: AppLocalization.format("Outdated, prices from %@", date)
    }
  }

  private var icon: String {
    switch status {
    case .calculating: "arrow.triangle.2.circlepath"
    case .failed: "xmark.octagon.fill"
    case .noPlan: "info.circle"
    case .saved: "clock.arrow.circlepath"
    case .current: "checkmark.circle.fill"
    case .outdated: "exclamationmark.arrow.triangle.2.circlepath"
    }
  }

  private var color: Color {
    switch status {
    case .failed: DesignTokens.negative
    case .current: DesignTokens.positive
    case .outdated, .saved: DesignTokens.caution
    case .calculating, .noPlan: DesignTokens.textSecondary
    }
  }
}

struct PlannerRouteSummaryPanel: View {
  let summary: PlannerRouteSummary
  let manualChoiceCount: Int
  let onResetManualChoices: () -> Void

  var body: some View {
    Panel(title: "Chosen production route") {
      Text(
        AppLocalization.format(
          "%lld materials built · %lld bought · %lld from stock",
          Int64(summary.builtMaterialCount),
          Int64(summary.boughtMaterialCount),
          Int64(summary.stockMaterialCount)
        )
      )
      .font(.callout.monospacedDigit())
      if !summary.purchaseLocationNames.isEmpty {
        HStack(spacing: DesignTokens.spacingSM) {
          Text("Bought at")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          ForEach(summary.purchaseLocationNames, id: \.self) { name in
            EVEEntityText(value: name, font: .caption)
          }
        }
      }
      HStack {
        Text(
          AppLocalization.format(
            "Set by hand: %lld choices.",
            Int64(manualChoiceCount)
          )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        Button(action: onResetManualChoices) {
          Label("Reset manual choices", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .disabled(manualChoiceCount == 0)
        .accessibilityIdentifier("planner.manual-decisions.reset")
      }
    }
  }
}

struct PlannerSetupIssuesPanel: View {
  let issues: [PlannerSetupIssue]
  let onOpen: (DataSettingsSection) -> Void

  var body: some View {
    Panel(title: "Missing settings") {
      ForEach(issues, id: \.self) { issue in
        HStack {
          Label(message(issue), systemImage: "exclamationmark.triangle")
            .foregroundStyle(DesignTokens.caution)
          Spacer()
          Button(buttonTitle(issue)) { onOpen(section(issue)) }
            .buttonStyle(.bordered)
        }
      }
    }
    .accessibilityIdentifier("planner.setup-issues")
  }

  private func message(_ issue: PlannerSetupIssue) -> LocalizedStringKey {
    switch issue {
    case .staticDataMissing: "No static data catalog is installed."
    case .mainHubMissing: "No NPC trade hub is set as Main Hub."
    }
  }

  private func buttonTitle(_ issue: PlannerSetupIssue) -> LocalizedStringKey {
    switch issue {
    case .staticDataMissing: "Open SDE"
    case .mainHubMissing: "Open Market Settings"
    }
  }

  private func section(_ issue: PlannerSetupIssue) -> DataSettingsSection {
    switch issue {
    case .staticDataMissing: .sde
    case .mainHubMissing: .marketSettings
    }
  }
}

/// Why this Blueprint source was chosen, and a way back when chosen by hand.
struct PlannerBlueprintChoiceNote: View {
  let recommendation: ProductionTreeBlueprintAction
  let recommendationTitle: String
  let isManual: Bool
  let isHandedOff: Bool
  let onReset: () -> Void

  var body: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      if isHandedOff {
        Label("Handed over, stays fixed", systemImage: "arrow.right.doc.on.clipboard")
      } else if isManual {
        Label(
          AppLocalization.format("Set by hand; automatic: %@", recommendationTitle),
          systemImage: "hand.point.up.left"
        )
        Button("Back to automatic", action: onReset)
          .buttonStyle(.borderless)
      } else {
        Label(reason, systemImage: "wand.and.stars")
      }
    }
    .font(.caption)
    .foregroundStyle(DesignTokens.textSecondary)
  }

  private var reason: LocalizedStringKey {
    switch BlueprintSourceStage(action: recommendation) {
    case .ownedBPO: "Automatic, step 1: owned BPO at the production location."
    case .ownedBPC: "Automatic, step 2: owned BPC at the production location, rest from contracts."
    case .contractBPC: "Automatic, step 3: lowest material plus contract cost."
    case .otherSource: "Automatic, step 4: no owned source or BPC contract is available."
    case .reactionFormula: "Automatic: owned reaction formula."
    case .none: "Automatic: no usable source found."
    }
  }
}

/// Owned formulas that have to travel from the Main Hub with the materials.
struct PlannerFormulaShipmentList: View {
  let shipments: [PlannerFormulaShipment]

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Label("Ship with the materials", systemImage: "shippingbox")
        .font(.headline)
      ForEach(shipments, id: \.blueprintTypeID) { shipment in
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: DesignTokens.spacingSM) {
            EVEEntityText(value: shipment.formulaName)
            Text("from")
              .foregroundStyle(DesignTokens.textSecondary)
            EVEEntityText(value: shipment.originName, font: .body)
          }
          if shipment.collateral == nil {
            Text("Transport not included: no ESI price known.")
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
          }
        }
      }
    }
    .accessibilityIdentifier("planner.formula-shipments")
  }
}
