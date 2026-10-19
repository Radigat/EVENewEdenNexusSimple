import EVENexusCore
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

  func testMainHubHandoffCanReplaceAnInvalidRestoredPlannerDraft() {
    let request = MainHubOpportunityPlannerHandoff.request(
      productTypeID: 34_567,
      productName: "Fixture Module",
      requestedRuns: 5,
      wantedQuantity: 10,
      materialEfficiency: 10,
      timeEfficiency: 20
    )
    let invalidRestoredDraft = "Old incomplete line"

    XCTAssertTrue(
      PlannerLaunchInputPolicy.requiresExplicitChoice(
        currentInput: invalidRestoredDraft,
        hasCalculatedPlan: true
      )
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
    XCTAssertFalse(
      PlannerLaunchInputPolicy.requiresExplicitChoice(
        currentInput: "\n",
        hasCalculatedPlan: false
      )
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
