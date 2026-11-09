import EVENexusCore
import SwiftUI

/// Hands one buildable product to the Planner's product adder (owner rule
/// 09.11.2026). The adder preselects it with the ME/TE preset; the user
/// enters the runs, nothing is appended before the user adds the line.
struct PlannerBuildRequest: Identifiable, Equatable {
  let id: UUID
  let productTypeID: Int64

  init(id: UUID = UUID(), productTypeID: Int64) {
    self.id = id
    self.productTypeID = productTypeID
  }
}

/// The one place a build link click goes to. The main window owns the
/// router and navigates to the Planner; there is no router while the Planner
/// itself is shown, so the Planner never shows the link.
@MainActor
@Observable
final class PlannerBuildRouter {
  /// Visible type ID → product the Planner builds (active SDE); `nil` while
  /// no SDE is active, where every link stays hidden.
  var targets: [Int64: Int64]?
  var request: PlannerBuildRequest?

  init(targets: [Int64: Int64]? = nil) {
    self.targets = targets
  }

  /// The product a link for `typeID` builds, or `nil` without a link.
  func productTypeID(for typeID: Int64) -> Int64? {
    guard typeID > 0 else { return nil }
    return targets?[typeID]
  }

  func open(typeID: Int64) {
    guard let productTypeID = productTypeID(for: typeID) else { return }
    request = PlannerBuildRequest(productTypeID: productTypeID)
  }
}

private struct PlannerBuildRouterKey: EnvironmentKey {
  static let defaultValue: PlannerBuildRouter? = nil
}

private struct PlannerBuildClosesPresentationKey: EnvironmentKey {
  static let defaultValue: DismissAction? = nil
}

extension EnvironmentValues {
  /// Router of the main window; `nil` inside the Planner and outside the
  /// main window, where the build link stays hidden.
  var plannerBuildRouter: PlannerBuildRouter? {
    get { self[PlannerBuildRouterKey.self] }
    set { self[PlannerBuildRouterKey.self] = newValue }
  }

  /// Closes the sheet a build link sits in before the Planner opens. Only a
  /// presentation that outlives the area change sets it (the stock history
  /// of the main window); sheets and popovers of an area close with the
  /// area, and the main window owns its consolidation sheet. Never the
  /// window's own `dismiss`, which would close the main window.
  var plannerBuildClosesPresentation: DismissAction? {
    get { self[PlannerBuildClosesPresentationKey.self] }
    set { self[PlannerBuildClosesPresentationKey.self] = newValue }
  }
}

/// The build link next to an item name: a separate control after the stock
/// history link, so the name keeps its copy click. Hidden without a router
/// or when the Planner cannot build the type.
struct PlannerBuildButton: View {
  let typeID: Int64
  let name: String
  var accessibilityIdentifier: String? = nil

  @Environment(\.plannerBuildRouter) private var router
  @Environment(\.plannerBuildClosesPresentation) private var closePresentation

  var body: some View {
    if let router, router.productTypeID(for: typeID) != nil {
      Button {
        closePresentation?()
        router.open(typeID: typeID)
      } label: {
        Image(systemName: "hammer")
      }
      .buttonStyle(.borderless)
      .help(AppLocalization.text("Build in Planner"))
      .accessibilityLabel("Build in Planner")
      .accessibilityValue(Text(verbatim: name))
      .accessibilityHint(
        "Opens the Planner with this item selected for adding; enter the runs there."
      )
      .accessibilityIdentifier(accessibilityIdentifier ?? "planner-build.\(typeID)")
    }
  }
}

/// What a build link click hands to the Planner's product adder: the
/// resolved product, or an explicit reason why it cannot be preselected.
struct PlannerAdderPreselection: Identifiable, Equatable {
  enum Outcome: Equatable {
    case target(PlannerBuildTarget)
    /// The active SDE no longer offers the product; nothing is guessed.
    case notBuildable
    /// The SDE could not be read.
    case unavailable
  }

  let id: UUID
  let outcome: Outcome

  init(id: UUID = UUID(), outcome: Outcome) {
    self.id = id
    self.outcome = outcome
  }
}

/// Field values the product adder takes over for a selected product
/// (owner decision 09.11.2026): the same ME/TE preset for the build link and
/// the manual search; the build link leaves the runs to the user.
struct PlannerProductAdderSelectionDefaults: Equatable {
  let runs: Int?
  let materialEfficiency: Int
  let timeEfficiency: Int
  /// Reactions use no ME/TE; the adder locks both fields.
  let efficiencyLocked: Bool

  init(preset: PlannerBuildEfficiencyPreset, runs: Int?) {
    self.runs = runs
    materialEfficiency = preset.materialEfficiency
    timeEfficiency = preset.timeEfficiency
    efficiencyLocked = preset.efficiencyLocked
  }

  /// Manual search: manufacturing products only, the runs stay as entered
  /// (1 when empty).
  static func manualSearch(
    _ item: ManufacturingProductSearchResult,
    currentRuns: Int?
  ) -> Self {
    Self(
      preset: PlannerBuildEfficiencyPreset.resolve(
        activity: .manufacturing,
        metaGroupID: item.metaGroupID,
        techLevel: item.techLevel
      ),
      runs: currentRuns ?? 1
    )
  }

  /// Build link: the runs field stays empty for the user.
  static func buildLink(_ target: PlannerBuildTarget) -> Self {
    Self(preset: target.preset, runs: nil)
  }
}
