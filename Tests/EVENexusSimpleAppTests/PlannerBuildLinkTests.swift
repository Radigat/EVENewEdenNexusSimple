import AppKit
import EVENexusCore
import Foundation
import SwiftUI
import Testing

@testable import EVENexusSimpleApp

/// Owner rule 09.11.2026: every buildable item links to the Planner, which
/// preselects it in the product adder; the user enters the runs.
@MainActor
@Suite("Planner build link")
struct PlannerBuildLinkTests {
  @Test
  func routerOpensOnlyBuildableTypesAsTheirProduct() {
    let router = PlannerBuildRouter(targets: [100: 1, 1: 1])
    #expect(router.request == nil)

    router.open(typeID: 2)
    #expect(router.request == nil)
    router.open(typeID: 0)
    #expect(router.request == nil)

    router.open(typeID: 100)
    #expect(router.request?.productTypeID == 1)

    let withoutSDE = PlannerBuildRouter()
    withoutSDE.open(typeID: 1)
    #expect(withoutSDE.request == nil)
    #expect(withoutSDE.productTypeID(for: 1) == nil)
  }

  @Test
  func itemTextShowsTheHammerOnlyForBuildableTypesWithARouter() {
    let router = PlannerBuildRouter(targets: [34_000: 34_000])
    let item = EVEItemText(value: "Fixture Item", typeID: 34_000)
    let withoutRouter = width(of: item)
    let withRouter = width(of: item.environment(\.plannerBuildRouter, router))
    let switchedOff = width(
      of: EVEItemText(value: "Fixture Item", typeID: 34_000, showsPlannerBuild: false)
        .environment(\.plannerBuildRouter, router)
    )
    let rawMaterial = width(
      of: EVEItemText(value: "Fixture Item", typeID: 34)
        .environment(\.plannerBuildRouter, router)
    )
    let withoutSDE = width(
      of: item.environment(\.plannerBuildRouter, PlannerBuildRouter())
    )

    #expect(EVEItemText(value: "Fixture Item", typeID: 34_000).showsPlannerBuild)
    #expect(withRouter > withoutRouter)
    #expect(switchedOff == withoutRouter)
    #expect(withoutSDE == withoutRouter)
    // A type the Planner cannot build (raw material) gets no hammer.
    #expect(rawMaterial == width(of: EVEItemText(value: "Fixture Item", typeID: 34)))
  }

  @Test
  func buildLinkLeavesTheRunsToTheUser() {
    let tech2 = target(metaGroupID: 2, techLevel: 2, activity: .manufacturing)
    let defaults = PlannerProductAdderSelectionDefaults.buildLink(tech2)
    #expect(defaults.runs == nil)
    #expect(defaults.materialEfficiency == 3)
    #expect(defaults.timeEfficiency == 2)
    #expect(!defaults.efficiencyLocked)

    let reaction = PlannerProductAdderSelectionDefaults.buildLink(
      target(metaGroupID: nil, techLevel: nil, activity: .reaction)
    )
    #expect(reaction.runs == nil)
    #expect(reaction.efficiencyLocked)
    #expect(reaction.materialEfficiency == 0)
    #expect(reaction.timeEfficiency == 0)
  }

  @Test
  func manualSearchUsesTheSamePresetAndKeepsTheRuns() {
    func manual(_ metaGroupID: Int64?, _ techLevel: Int?, runs: Int?)
      -> PlannerProductAdderSelectionDefaults
    {
      PlannerProductAdderSelectionDefaults.manualSearch(
        product(metaGroupID: metaGroupID, techLevel: techLevel),
        currentRuns: runs
      )
    }
    func values(_ defaults: PlannerProductAdderSelectionDefaults) -> [Int?] {
      [defaults.runs, defaults.materialEfficiency, defaults.timeEfficiency]
    }
    let expected: [(PlannerProductAdderSelectionDefaults, [Int?])] = [
      (manual(1, 1, runs: 7), [7, 10, 20]),
      (manual(14, 3, runs: nil), [1, 3, 2]),
      (manual(4, 1, runs: 2), [2, 0, 0]),
      (manual(nil, nil, runs: 1), [1, 10, 20]),
    ]
    for (defaults, values_) in expected {
      #expect(values(defaults) == values_)
      #expect(!defaults.efficiencyLocked)
    }
  }

  /// One router, owned by the main window, and none inside the Planner.
  @Test
  func onlyTheMainWindowOpensThePlannerBuild() throws {
    var owners: [String] = []
    var appliers: [String] = []
    for (name, source) in try appSources() {
      let routers = source.components(separatedBy: "PlannerBuildRouter()").count - 1
      owners += Array(repeating: name, count: routers)
      let applied = source.components(separatedBy: "plannerBuildRequest = request").count - 1
      appliers += Array(repeating: name, count: applied)
    }
    #expect(owners == ["ContentView.swift"])
    #expect(appliers == ["ContentView.swift"])
    let sources = try appSources()
    let content = try #require(sources.first { $0.name == "ContentView.swift" })
    #expect(content.source.contains("selection == .planner ? nil : plannerBuildRouter"))
    let navigation = try #require(
      content.source.components(separatedBy: "private func openPlannerBuild(").last
    )
    let guarded = try #require(
      navigation.components(separatedBy: "profileNavigationGuard.attemptNavigation {").last
    )
    #expect(guarded.contains("consolidationArea = nil"))
    #expect(guarded.contains("plannerBuildRequest = request"))
  }

  /// The window's own `dismiss` closes the main window, so the link never
  /// uses it; only the stock history sheet hands over its own `dismiss`.
  @Test
  func theLinkClosesOnlyPresentationsThatOutliveTheAreaChange() throws {
    let sources = try appSources()
    let link = try #require(sources.first { $0.name == "PlannerBuildLink.swift" })
    #expect(!link.source.contains("@Environment(\\.dismiss)"))
    #expect(!link.source.contains("@Environment(\\.isPresented)"))
    var closers: [String] = []
    for (name, source) in sources {
      let count =
        source.components(separatedBy: ".environment(\\.plannerBuildClosesPresentation,").count - 1
      closers += Array(repeating: name, count: count)
    }
    #expect(closers == ["MarketStockItemDetailView.swift"])
  }

  @Test
  func everyBuildLinkTextIsTranslatedInBothLanguages() throws {
    let keys = [
      "Build in Planner",
      "Opens the Planner with this item selected for adding; enter the runs there.",
      "Reactions use no ME or TE.",
      "Selected %@ for adding. Enter the runs, then add it to the end of the planner input.",
      "The active SDE offers no Planner production for this item.",
      "The item could not be loaded from the active SDE.",
      "Search starts after 3 characters and shows only complete published manufacturing products from the active SDE. The hammer beside an item name elsewhere in the app also preselects reaction products here.",
    ]
    for language in AppLanguage.allCases {
      let path = try #require(
        AppLocalization.resourceBundle.path(forResource: language.rawValue, ofType: "lproj")
      )
      let bundle = try #require(Bundle(path: path))
      for key in keys {
        let missing = "\u{0}missing"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        #expect(value != missing, "\(language.rawValue): \(key)")
      }
    }
    #expect(AppLanguage.german.localized("Build in Planner") == "Im Planer bauen")
    // The code must use exactly these keys, or the text stays English.
    let sources = try appSources()
    let code = sources
      .filter { ["PlaceholderViews.swift", "PlannerBuildLink.swift"].contains($0.name) }
      .map(\.source).joined()
    for key in keys {
      #expect(code.contains("\"\(key)\""), "not used in code: \(key)")
    }
  }

  private func product(metaGroupID: Int64?, techLevel: Int?)
    -> ManufacturingProductSearchResult
  {
    ManufacturingProductSearchResult(
      id: 7_000,
      name: "Fixture Item",
      outputPerRun: 1,
      blueprintTypeID: 7_001,
      metaGroupID: metaGroupID,
      techLevel: techLevel
    )
  }

  private func target(
    metaGroupID: Int64?,
    techLevel: Int?,
    activity: BlueprintActivityDefinition.Kind
  ) -> PlannerBuildTarget {
    PlannerBuildTarget(
      product: product(metaGroupID: metaGroupID, techLevel: techLevel),
      activity: activity
    )
  }

  private func width(of view: some View) -> CGFloat {
    NSHostingView(rootView: view.fixedSize()).fittingSize.width
  }

  private func appSources() throws -> [(name: String, source: String)] {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/EVENexusSimpleApp")
    let files = try FileManager.default.contentsOfDirectory(
      at: sources,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "swift" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    #expect(!files.isEmpty)
    return try files.map {
      ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
    }
  }
}
