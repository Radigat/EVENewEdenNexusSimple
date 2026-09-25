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
}
