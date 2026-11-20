import EVENexusCore
import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

final class EVEItemPresentationTests: XCTestCase {
  func testMainHubBuildHandoffCreatesExactPlannerInput() {
    let request = MainHubOpportunityPlannerHandoff.request(
      productTypeID: 587,
      productName: "Fixture Frigate",
      requestedRuns: 12,
      wantedQuantity: 12,
      materialEfficiency: 7,
      timeEfficiency: 14
    )

    XCTAssertEqual(request.productTypeID, 587)
    XCTAssertEqual(request.requestedRuns, 12)
    XCTAssertEqual(request.inputLine, "Fixture Frigate 12 7 14")
    XCTAssertTrue(request.blueprintSupplyPlans.isEmpty)
  }

  func testMainHubHandoffAppendsToExistingDraftAndReplacesOnlyAnEmptyPlanner() {
    let request = MainHubOpportunityPlannerHandoff.request(
      productTypeID: 34_567,
      productName: "Fixture Module",
      requestedRuns: 5,
      wantedQuantity: 10,
      materialEfficiency: 10,
      timeEfficiency: 20
    )
    let invalidRestoredDraft = "Old incomplete line"

    XCTAssertEqual(
      PlannerLaunchInputPolicy.mode(
        currentInput: invalidRestoredDraft,
        hasCalculatedPlan: true
      ),
      .append
    )
    XCTAssertEqual(
      PlannerLaunchInputPolicy.mode(
        currentInput: "",
        hasCalculatedPlan: true
      ),
      .append
    )
    let replacement = PlannerLaunchInputPolicy.applying(
      request,
      to: invalidRestoredDraft,
      mode: .replace
    )
    let parsedReplacement = ProductionInputParser.parse(replacement)

    XCTAssertEqual(replacement, "Fixture Module 10 10 20")
    XCTAssertTrue(parsedReplacement.isValid)
    XCTAssertEqual(parsedReplacement.requests.count, 1)
    XCTAssertEqual(
      PlannerLaunchInputPolicy.mode(
        currentInput: "\n",
        hasCalculatedPlan: false
      ),
      .replace
    )
    XCTAssertEqual(
      PlannerLaunchInputPolicy.applying(
        request,
        to: "Existing Product 1 0 0",
        mode: .append
      ),
      "Existing Product 1 0 0\nFixture Module 10 10 20"
    )
  }

  func testPlannerOverviewDisclosureStateKeepsFinanceCardsIndependent() {
    XCTAssertEqual(PlannerSaleHub.allCases.count * 3, 9)
    XCTAssertEqual(
      Set(PlannerFinanceSection.allCases.map(\.rawValue)).count,
      PlannerFinanceSection.allCases.count
    )

    var encoded = "not-json"
    encoded = PlannerDisclosureStorage.updating(
      encoded,
      id: PlannerFinanceSection.materials.rawValue,
      isExpanded: true
    )
    encoded = PlannerDisclosureStorage.updating(
      encoded,
      id: PlannerFinanceSection.inboundLogistics.rawValue,
      isExpanded: true
    )

    XCTAssertTrue(
      PlannerDisclosureStorage.contains(
        PlannerFinanceSection.materials.rawValue,
        in: encoded
      )
    )
    XCTAssertTrue(
      PlannerDisclosureStorage.contains(
        PlannerFinanceSection.inboundLogistics.rawValue,
        in: encoded
      )
    )

    encoded = PlannerDisclosureStorage.updating(
      encoded,
      id: PlannerFinanceSection.materials.rawValue,
      isExpanded: false
    )
    XCTAssertFalse(
      PlannerDisclosureStorage.contains(
        PlannerFinanceSection.materials.rawValue,
        in: encoded
      )
    )
    XCTAssertTrue(
      PlannerDisclosureStorage.contains(
        PlannerFinanceSection.inboundLogistics.rawValue,
        in: encoded
      )
    )
  }

  func testImageURLUsesOfficialTypeIconEndpoint() {
    XCTAssertEqual(
      EVETypeImageURL.icon(typeID: 34)?.absoluteString,
      "https://images.evetech.net/types/34/icon?size=64&tenant=tranquility"
    )
  }

  func testShipRenderURLUsesOfficialTypeRenderEndpoint() {
    XCTAssertEqual(
      EVETypeImageURL.render(typeID: 28_850)?.absoluteString,
      "https://images.evetech.net/types/28850/render?size=64&tenant=tranquility"
    )
  }

  func testImageURLRejectsInvalidTypeIDs() {
    XCTAssertNil(EVETypeImageURL.icon(typeID: 0))
    XCTAssertNil(EVETypeImageURL.icon(typeID: -1))
    XCTAssertNil(EVETypeImageURL.render(typeID: 0))
    XCTAssertNil(EVETypeImageURL.render(typeID: -1))
  }

  func testHubTableFieldTabOrderRunsThroughRowsAndSkipsMissingEfficiency() {
    let rows = [
      HubTableFieldNavigation.Row(typeID: 10, supportsEfficiency: true),
      HubTableFieldNavigation.Row(typeID: 20, supportsEfficiency: false),
      HubTableFieldNavigation.Row(typeID: 30, supportsEfficiency: true),
    ]
    func next(_ typeID: Int64, _ column: HubTableFieldID.Column, forward: Bool = true)
      -> HubTableFieldID?
    {
      HubTableFieldNavigation.neighbor(
        of: HubTableFieldID(typeID: typeID, column: column),
        forward: forward,
        rows: rows
      )
    }

    XCTAssertEqual(next(10, .runs), HubTableFieldID(typeID: 10, column: .material))
    XCTAssertEqual(next(10, .material), HubTableFieldID(typeID: 10, column: .time))
    XCTAssertEqual(next(10, .time), HubTableFieldID(typeID: 20, column: .runs))
    // A reaction row only has Runs.
    XCTAssertEqual(next(20, .runs), HubTableFieldID(typeID: 30, column: .runs))
    XCTAssertEqual(
      next(30, .runs, forward: false),
      HubTableFieldID(typeID: 20, column: .runs)
    )
    XCTAssertEqual(
      next(20, .runs, forward: false),
      HubTableFieldID(typeID: 10, column: .time)
    )
    // Both ends of the table and unknown fields end editing.
    XCTAssertNil(next(30, .time))
    XCTAssertNil(next(10, .runs, forward: false))
    XCTAssertNil(next(20, .material))
    XCTAssertNil(next(99, .runs))
  }

  /// A row must not change its height when a cell is clicked, in every text
  /// size and on every macOS version: the editing cell takes its height from
  /// the hidden text stand-in, because on macOS 15 the native field keeps
  /// one height for all text sizes. An emptied field keeps the height too.
  @MainActor
  func testClickToEditFieldKeepsItsHeightWhenEditingStarts() {
    for size in AppTextSize.allCases {
      func height(isEditing: Bool, text: String = "1234") -> CGFloat {
        NSHostingView(
          rootView: ClickToEditNumberField(
            title: "Runs",
            text: .constant(text),
            isEditing: isEditing,
            beginEditing: {},
            endEditing: {},
            moveFocus: { _ in }
          )
          .frame(width: 68)
          .fixedSize()
          .environment(\.appTextSize, size)
        ).fittingSize.height
      }
      let resting = height(isEditing: false)
      XCTAssertEqual(resting, height(isEditing: true), "text size \(size)")
      XCTAssertEqual(
        resting,
        height(isEditing: true, text: ""),
        "emptied field, text size \(size)"
      )
    }
  }

  /// A clicked cell takes the keyboard focus; Tab and Shift-Tab hand it to
  /// the neighbouring cell exactly once, and Shift-Tab on the first cell
  /// ends editing.
  @MainActor
  func testClickToEditFieldTakesFocusAndTabMovesToTheNeighbour() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    let log = ClickToEditProbeLog()
    window.contentView = NSHostingView(rootView: ClickToEditProbe(log: log))
    window.orderFront(nil)
    defer { window.close() }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
    var timestamp: TimeInterval = 0
    func press(shift: Bool) throws {
      timestamp += 1
      let character = shift ? "\u{19}" : "\t"
      window.sendEvent(
        try XCTUnwrap(
          NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.shift] : [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: ClickToEditNumberField.tabKeyCode
          )
        )
      )
      settle()
    }
    func editedText() -> String? { (window.firstResponder as? NSTextView)?.string }

    settle()
    XCTAssertEqual(editedText(), "11")
    try press(shift: false)
    XCTAssertEqual(editedText(), "22")
    try press(shift: true)
    XCTAssertEqual(editedText(), "11")
    try press(shift: true)
    XCTAssertNil(editedText())
    XCTAssertEqual(log.moves, ["forward 1", "back 2", "back 1"])
  }

  func testManufacturingOpportunityTableRejectsInvalidViewportGeometry() {
    XCTAssertEqual(
      ManufacturingOpportunityTableLayout.clampedViewportLength(-1),
      0
    )
    XCTAssertEqual(
      ManufacturingOpportunityTableLayout.clampedViewportLength(.infinity),
      0
    )
    XCTAssertEqual(
      ManufacturingOpportunityTableLayout.clampedViewportLength(.nan),
      0
    )
    XCTAssertEqual(
      ManufacturingOpportunityTableLayout.clampedViewportLength(640),
      640
    )
  }

  func testManufacturingOpportunityWorkspaceNeverExceedsItsViewport() {
    for proposedHeight in [-1.0, .infinity, .nan, 100, 519, 520, 760] {
      let layout = ManufacturingOpportunityWorkspaceLayout(
        viewportHeight: proposedHeight
      )
      XCTAssertGreaterThanOrEqual(layout.candidateHeight, 0)
      XCTAssertGreaterThanOrEqual(layout.workbenchHeight, 0)
      XCTAssertGreaterThanOrEqual(layout.dividerHeight, 0)
      XCTAssertEqual(
        layout.candidateHeight + layout.dividerHeight
          + layout.workbenchHeight,
        layout.viewportHeight,
        accuracy: 0.000_001
      )
    }
  }

  func testManufacturingOpportunityUpperControlsLeaveFiniteWorkspaceHeight() {
    for proposedHeight in [-1.0, .infinity, .nan, 100, 760, 1_200] {
      let controlsHeight =
        ManufacturingOpportunityPageLayout.upperControlsHeight(
          viewportHeight: proposedHeight,
          filtersAreExpanded: true,
          basisIsExpanded: true
        )
      let viewportHeight =
        ManufacturingOpportunityTableLayout.clampedViewportLength(
          proposedHeight
        )
      XCTAssertGreaterThanOrEqual(controlsHeight, 0)
      XCTAssertLessThanOrEqual(controlsHeight, viewportHeight)
      XCTAssertLessThanOrEqual(controlsHeight, 420)
    }
  }

  func testManufacturingOpportunityCollapsedControlsReleaseCalculatorHeight() {
    let collapsed = ManufacturingOpportunityPageLayout.upperControlsHeight(
      viewportHeight: 1_200,
      filtersAreExpanded: false,
      basisIsExpanded: false
    )
    let basisOnly = ManufacturingOpportunityPageLayout.upperControlsHeight(
      viewportHeight: 1_200,
      filtersAreExpanded: false,
      basisIsExpanded: true
    )
    let filtersOnly = ManufacturingOpportunityPageLayout.upperControlsHeight(
      viewportHeight: 1_200,
      filtersAreExpanded: true,
      basisIsExpanded: false
    )
    let expanded = ManufacturingOpportunityPageLayout.upperControlsHeight(
      viewportHeight: 1_200,
      filtersAreExpanded: true,
      basisIsExpanded: true
    )

    XCTAssertLessThan(collapsed, basisOnly)
    XCTAssertLessThan(basisOnly, filtersOnly)
    XCTAssertLessThan(filtersOnly, expanded)
  }

  func testManufacturingOpportunityWorkbenchNeverUsesNegativeGeometry() {
    for proposedSize in [
      CGSize(width: -1, height: -1),
      CGSize(width: CGFloat.infinity, height: CGFloat.nan),
      CGSize(width: 1, height: 1),
      CGSize(width: 960, height: 320),
    ] {
      let layout = ManufacturingOpportunityWorkbenchLayout(
        viewportSize: proposedSize
      )
      XCTAssertGreaterThanOrEqual(layout.columnWidth, 0)
      XCTAssertGreaterThanOrEqual(layout.viewportHeight, 0)
      XCTAssertEqual(
        layout.columnWidth * 2 + layout.dividerWidth,
        layout.viewportWidth,
        accuracy: 0.000_001
      )
    }
  }

  func testPlannerShowsOnlyDecisiveWarningsOnceWithBlockingFirst() {
    let shortRuns = IndustryWarningText.blueprintRunsShort(
      blueprintName: "Capital Cargo Bay Blueprint",
      missingRuns: 17
    )
    let warnings = [
      DomainWarning(
        code: "industry.production-blacklist",
        message: "Helium Fuel Block cannot be produced and uses the selected purchase or warehouse source.",
        severity: .information
      ),
      DomainWarning(
        code: "industry.warehouse-source-not-fresh",
        message: "Some character assets are not up to date.",
        severity: .warning
      ),
      DomainWarning(
        code: "industry.blueprint-supply-insufficient-runs",
        message: shortRuns,
        severity: .blocking
      ),
      DomainWarning(
        code: "industry.blueprint-supply-insufficient-runs",
        message: shortRuns,
        severity: .blocking
      ),
      DomainWarning(
        code: "industry.slot-estimated-makespan",
        message: "Makespan uses the configured slot counts.",
        severity: .information
      ),
    ]

    let visible = PlannerView.decisiveWarnings(warnings)

    XCTAssertEqual(
      visible.map(\.code),
      [
        "industry.blueprint-supply-insufficient-runs",
        "industry.warehouse-source-not-fresh",
      ]
    )
    XCTAssertEqual(
      shortRuns,
      "Not enough Blueprint runs for Capital Cargo Bay Blueprint: 17 required runs are not covered by your Blueprints."
    )
  }

  func testConcreteBlueprintChoicesMergeIdenticalCopiesWithoutItemIDs() {
    func bpc(
      _ itemID: Int64,
      location: String?,
      exact: Bool = true,
      runs: Int?,
      me: Int,
      te: Int
    ) -> ConcreteBlueprintSourceCandidate {
      ConcreteBlueprintSourceCandidate(
        source: .ownedBPC(itemID: itemID),
        locationName: location,
        isAtProductionLocation: exact,
        runs: runs,
        materialEfficiency: me,
        timeEfficiency: te,
        priceText: nil
      )
    }
    let choices = ConcreteBlueprintSourceMenu.choices([
      bpc(1_037_196_637_011, location: "Fixture Hub", runs: 1, me: 9, te: 14),
      bpc(1_049_158_211_897, location: "Fixture Hub", runs: 200, me: 10, te: 20),
      bpc(1_037_196_637_012, location: "Fixture Hub", runs: 1, me: 9, te: 14),
      bpc(1_037_196_637_013, location: "Fixture Hub", runs: 1, me: 9, te: 14),
      bpc(1_049_158_211_898, location: "Other Hub", exact: false, runs: 1, me: 9, te: 14),
      bpc(1_049_158_211_899, location: nil, runs: 1, me: 9, te: 14),
    ])

    XCTAssertEqual(choices.map(\.count), [3, 1, 1, 1])
    XCTAssertEqual(
      choices[0].sources,
      [
        .ownedBPC(itemID: 1_037_196_637_011),
        .ownedBPC(itemID: 1_037_196_637_012),
        .ownedBPC(itemID: 1_037_196_637_013),
      ]
    )
    XCTAssertTrue(choices[0].title.hasPrefix("3×"))
    XCTAssertTrue(choices[0].title.contains("Fixture Hub"))
    XCTAssertTrue(choices[0].title.contains("ME 9 · TE 14"))
    XCTAssertFalse(choices[1].title.hasPrefix("1×"))
    XCTAssertTrue(choices[1].title.contains("ME 10 · TE 20"))
    XCTAssertTrue(choices[2].title.contains("Other Hub"))
    XCTAssertNotEqual(choices[2].title, choices[0].title.replacingOccurrences(of: "3× · ", with: ""))
    for choice in choices {
      XCTAssertFalse(choice.title.contains("1037196637011"))
      XCTAssertFalse(choice.title.contains("Item"))
    }

    XCTAssertEqual(
      ConcreteBlueprintSourceMenu.selectedChoiceID(
        preferredSources: [.ownedBPC(itemID: 1_037_196_637_012)],
        in: choices
      ),
      choices[0].id
    )
    XCTAssertNil(
      ConcreteBlueprintSourceMenu.selectedChoiceID(
        preferredSources: [],
        in: choices
      )
    )
  }
}

@MainActor
private final class ClickToEditProbeLog {
  var moves: [String] = []
}

/// Two cells with the first one in edit mode, wired like the hub table.
private struct ClickToEditProbe: View {
  let log: ClickToEditProbeLog
  @State private var editing: HubTableFieldID? = HubTableFieldID(
    typeID: 1,
    column: .runs
  )
  @State private var first = "11"
  @State private var second = "22"

  var body: some View {
    HStack {
      field(1, $first)
      field(2, $second)
    }
    .frame(width: 200, height: 40)
  }

  private func field(_ typeID: Int64, _ text: Binding<String>) -> some View {
    let id = HubTableFieldID(typeID: typeID, column: .runs)
    return ClickToEditNumberField(
      title: "Runs",
      text: text,
      isEditing: editing == id,
      beginEditing: { editing = id },
      endEditing: { if editing == id { editing = nil } },
      moveFocus: { forward in
        log.moves.append("\(forward ? "forward" : "back") \(typeID)")
        editing = HubTableFieldNavigation.neighbor(
          of: id,
          forward: forward,
          rows: [
            HubTableFieldNavigation.Row(typeID: 1, supportsEfficiency: false),
            HubTableFieldNavigation.Row(typeID: 2, supportsEfficiency: false),
          ]
        )
      }
    )
  }
}
