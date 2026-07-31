import EVENexusCore
import SwiftUI

struct IndustryIndexSummary: View {
  @EnvironmentObject private var runtime: RuntimeState
  let solarSystemID: Int64

  private var snapshot: IndustrySystemCostIndexSnapshot? {
    runtime.industrySystemIndices?.value?.first {
      $0.solarSystemID == solarSystemID
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Current ESI industry cost indices")
        .font(.caption.bold())
      if solarSystemID <= 0 {
        Text("Select a solar system to load its indices.")
          .foregroundStyle(DesignTokens.textSecondary)
      } else if runtime.isLoadingProfileReferenceData {
        ProgressView("Loading indices…").controlSize(.small)
      } else if runtime.industrySystemIndices?.state != .fresh {
        Label(
          "Industry indices are unavailable.",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(DesignTokens.caution)
      } else if let snapshot {
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 165), alignment: .leading)
          ],
          alignment: .leading,
          spacing: DesignTokens.spacingXS
        ) {
          ForEach(
            snapshot.indices.filter {
              $0.activity != IndustryCostActivity.none
            }
          ) { index in
            LabeledContent(index.displayName.localizedUI) {
              Text(
                index.value.formatted(
                  .percent
                    .locale(AppLocalization.currentLanguage.locale)
                    .precision(.fractionLength(3...5))
                )
              )
              .font(.caption.monospacedDigit())
            }
          }
        }
        Text(
          "ESI · \(runtime.industrySystemIndices?.source.capturedAt.formatted() ?? "unknown time")"
        )
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Label(
          "ESI returned no cost-index row for this system.",
          systemImage: "questionmark.circle"
        )
        .foregroundStyle(DesignTokens.caution)
      }
    }
    .font(.caption)
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.canvas.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }
}

struct ProductionLabelPicker: View {
  @Binding var configuration: ActivitySystemConfiguration

  var body: some View {
    LabeledContent("Personal production label") {
      Menu {
        ForEach(ManufacturingSystemLabel.allCases) { label in
          Button {
            toggle(label)
          } label: {
            Label(
              label.displayName.localizedUI,
              systemImage:
                configuration.productionLabels.contains(label)
                ? "checkmark" : "circle"
            )
          }
        }
      } label: {
        Text(configuration.productionLabelSummary.localizedUI)
          .lineLimit(2)
      }
      .menuStyle(.borderlessButton)
      .frame(minWidth: 220, alignment: .trailing)
    }
    Text(
      "This label is informational and does not change automatic facility selection."
    )
    .font(.caption)
    .foregroundStyle(DesignTokens.textSecondary)
  }

  private func toggle(_ label: ManufacturingSystemLabel) {
    if label == .all {
      configuration.productionLabels = [.all]
      return
    }
    configuration.productionLabels.remove(.all)
    if configuration.productionLabels.contains(label) {
      configuration.productionLabels.remove(label)
    } else {
      configuration.productionLabels.insert(label)
    }
    if configuration.productionLabels.isEmpty {
      configuration.productionLabels = [.all]
    }
  }
}
