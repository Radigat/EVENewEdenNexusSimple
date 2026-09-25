import Foundation
import Testing

@testable import EVENexusCore

@Suite("Production input")
struct ProductionInputParserTests {
  @Test
  func ignoresAnEmptyFirstLine() {
    let result = ProductionInputParser.parse("\nOccult XL 1 10 20")

    #expect(result.errors.isEmpty)
    #expect(result.requests.count == 1)
    #expect(result.requests.first?.lineNumber == 2)
    #expect(result.requests.first?.productName == "Occult XL")
  }

  @Test
  func parsesProductWantMEAndTEWithoutDelimiters() {
    let result = ProductionInputParser.parse(
      "Ark 3 10 20\nCapital Cargo Bay\t25\t10\t20"
    )

    #expect(result.errors.isEmpty)
    #expect(result.requests.count == 2)
    #expect(result.requests[0].productName == "Ark")
    #expect(result.requests[0].wantedQuantity == 3)
    #expect(result.requests[1].productName == "Capital Cargo Bay")
    #expect(result.requests[1].wantedQuantity == 25)
    #expect(result.requests[0].blueprintCostISK == nil)
  }

  @Test
  func parsesManualBPCAndBPOCostPerTopLevelLine() {
    let result = ProductionInputParser.parse(
      "Ark 1 10 20 BPC 175000000\nCapital Cargo Bay 25 10 20 BPO 5000000"
    )

    #expect(result.errors.isEmpty)
    #expect(result.requests[0].blueprintKind == .bpc)
    #expect(result.requests[0].blueprintCostISK == 175_000_000)
    #expect(result.requests[1].blueprintKind == .bpo)
    #expect(result.requests[1].blueprintCostISK == 5_000_000)
  }

  @Test
  func rejectsBlueprintKindWithoutAValidCost() {
    let result = ProductionInputParser.parse(
      "Ark 1 10 20 BPC\nCapital Cargo Bay 25 10 20 BPO nope"
    )

    #expect(result.requests.isEmpty)
    #expect(result.errors.map(\.lineNumber) == [1, 2])
  }

  @Test
  func reportsEveryInvalidLine() {
    let result = ProductionInputParser.parse(
      "Ark no 10 20\nBad\nItem 1 11 20"
    )

    #expect(result.requests.isEmpty)
    #expect(result.errors.map(\.lineNumber) == [1, 2, 3])
  }

  @Test
  func rejectsLegacyPipeDelimitedRows() {
    let result = ProductionInputParser.parse("Ark | 3 | 10 | 20")

    #expect(result.requests.isEmpty)
    #expect(result.errors.count == 1)
  }

  @Test
  func rejectsExtremeQuantitiesAndOversizedInput() {
    let excessiveQuantity = ProductionInputParser.parse(
      "Ark \(ProductionInputParser.maximumWantedQuantity + 1) 10 20"
    )
    let oversized = ProductionInputParser.parse(
      String(
        repeating: "x",
        count: ProductionInputParser.maximumInputBytes + 1
      )
    )

    #expect(excessiveQuantity.requests.isEmpty)
    #expect(excessiveQuantity.errors.count == 1)
    #expect(oversized.requests.isEmpty)
    #expect(oversized.errors.count == 1)
  }

  @Test
  func formatsSavedRequestsAsParseableHistoricalInput() {
    let requests = [
      ProductionRequestLine(
        lineNumber: 1,
        productName: "Capital Cargo Bay",
        wantedQuantity: 25,
        materialEfficiency: 10,
        timeEfficiency: 20,
        blueprintKind: .bpo,
        blueprintCostISK: 5_000_000
      ),
      ProductionRequestLine(
        lineNumber: 2,
        productName: "Ark",
        wantedQuantity: 1,
        materialEfficiency: 9,
        timeEfficiency: 18
      ),
    ]

    let formatted = ProductionInputFormatter.format(requests)
    let reparsed = ProductionInputParser.parse(formatted)

    #expect(reparsed.errors.isEmpty)
    #expect(reparsed.requests.count == 2)
    #expect(reparsed.requests[0].productName == "Capital Cargo Bay")
    #expect(reparsed.requests[0].wantedQuantity == 25)
    #expect(reparsed.requests[0].materialEfficiency == 10)
    #expect(reparsed.requests[0].timeEfficiency == 20)
    #expect(reparsed.requests[0].blueprintKind == .bpo)
    #expect(reparsed.requests[0].blueprintCostISK == 5_000_000)
    #expect(reparsed.requests[1].productName == "Ark")
    #expect(reparsed.requests[1].blueprintKind == nil)
    #expect(reparsed.requests[1].blueprintCostISK == nil)
  }

  @Test
  func formatsManufacturingRunsAsTheExactWantedOutput() throws {
    let line = try ProductionInputFormatter.manufacturingLine(
      productName: "Tungsten Carbide",
      runs: 7,
      outputPerRun: 10_000,
      materialEfficiency: 10,
      timeEfficiency: 20
    )
    let reparsed = ProductionInputParser.parse(line)

    #expect(line == "Tungsten Carbide 70000 10 20")
    #expect(reparsed.requests.first?.wantedQuantity == 70_000)
    #expect(reparsed.requests.first?.materialEfficiency == 10)
    #expect(reparsed.requests.first?.timeEfficiency == 20)
  }

  @Test
  func rejectsRunSelectionThatWouldExceedThePlannerQuantityLimit() {
    #expect(throws: ProductionInputFormattingError.quantityLimitExceeded) {
      try ProductionInputFormatter.manufacturingLine(
        productName: "Fixture Product",
        runs: ProductionInputParser.maximumWantedQuantity,
        outputPerRun: 2,
        materialEfficiency: 10,
        timeEfficiency: 20
      )
    }
  }

  @Test
  func appendsASelectedProductAfterExistingPlannerRows() {
    #expect(
      ProductionInputFormatter.appending(
        "Tungsten Carbide 70000 10 20",
        to: "Ark 1 10 20\nCapital Cargo Bay 25 10 20"
      )
        == "Ark 1 10 20\nCapital Cargo Bay 25 10 20\nTungsten Carbide 70000 10 20"
    )
    #expect(
      ProductionInputFormatter.appending(
        "Ark 1 10 20",
        to: "Capital Cargo Bay 25 10 20\n"
      ) == "Capital Cargo Bay 25 10 20\nArk 1 10 20"
    )
  }

  @Test
  func parsesTabSeparatedEVEItemRowsWithGermanNumbers() throws {
    let input = """
      Arazu\t8\tForce Recon Ship\t\t\t80.000 m3\t1.167.920.630,64 ISK
      Cruise Missile Launcher II\t20\tMissile Launcher Cruise\t\tHigh\t400 m3\t51.487.319,60 ISK
      """

    let result = RecursiveProductionImportParser.parse(input)

    #expect(result.errors.isEmpty)
    #expect(result.lines.count == 2)
    let arazu = try #require(result.lines.first)
    #expect(arazu.itemName == "Arazu")
    #expect(arazu.quantity == 8)
    #expect(arazu.groupName == "Force Recon Ship")
    #expect(arazu.volumeM3 == 80_000)
    #expect(arazu.estimatedValueISK == 1_167_920_630.64)
    #expect(result.lines[1].volumeM3 == 400)
    #expect(result.estimatedValueISK == 1_219_407_950.24)
  }

  @Test
  func importedRowsBecomeStandardPlannerRequestsWithoutInventedBlueprintCost() {
    let result = RecursiveProductionImportParser.parse(
      "Ark\t1\tJump Freighter\t\t\t1.300.000 m3\t6.617.598.930,48 ISK"
    )
    let requests = result.lines.map {
      $0.plannerRequest(materialEfficiency: 10, timeEfficiency: 20)
    }

    #expect(requests.count == 1)
    #expect(requests[0].productName == "Ark")
    #expect(requests[0].wantedQuantity == 1)
    #expect(requests[0].materialEfficiency == 10)
    #expect(requests[0].timeEfficiency == 20)
    #expect(requests[0].blueprintKind == nil)
    #expect(requests[0].blueprintCostISK == nil)
  }

  @Test
  func acceptsSimpleRowsAndRejectsInvalidQuantitiesWithoutDroppingValidRows() {
    let result = RecursiveProductionImportParser.parse(
      "Arazu 8\nArk\t0\tJump Freighter\nInvalid\nBasilisk\t4\tLogistics"
    )

    #expect(result.lines.map(\.itemName) == ["Arazu", "Basilisk"])
    #expect(result.errors.map(\.lineNumber) == [2, 3])
  }

  @Test
  func distinguishesOneWayAndRoundTripLogisticsRoutes() {
    #expect(
      !RecursiveProductionLogisticsRoute.mainToHome
        .includesFinishedProductReturn
    )
    #expect(
      RecursiveProductionLogisticsRoute.mainToHomeToMain
        .includesFinishedProductReturn
    )
  }

  @Test
  func recursiveReconstructionForcesEveryProducibleTypeToBuild() {
    let existing = [
      Int64(10): MaterialProcurementPreference(
        supplyMode: .buy,
        purchaseLocation: .amarr,
        usesAvailableStockFirst: false
      ),
      Int64(99): MaterialProcurementPreference(
        supplyMode: .warehouse,
        purchaseLocation: .amarr,
        usesAvailableStockFirst: true
      ),
    ]

    let projected = RecursiveProductionPreferenceProjector.forceProduction(
      typeIDs: [10, 20],
      existing: existing,
      mainHub: .jita
    )

    #expect(projected[10]?.supplyMode == .produce)
    #expect(projected[10]?.purchaseLocation == .jita)
    #expect(projected[10]?.usesAvailableStockFirst == true)
    #expect(projected[20]?.supplyMode == .produce)
    #expect(projected[99]?.supplyMode == .warehouse)
  }

  @Test
  func ownedReactionFormulaDefaultIsExplicitAndRespectsOverrides() {
    let reaction = PlanNode(
      id: UUID(),
      typeID: 20,
      name: "Fixture Reaction",
      requiredQuantity: 10,
      action: .produce,
      activity: .reaction,
      runs: 5,
      materialEfficiency: nil,
      timeEfficiency: nil,
      blueprintTypeID: 200,
      children: [],
      topLevelRequestID: UUID()
    )
    let manufacturing = PlanNode(
      id: UUID(),
      typeID: 30,
      name: "Fixture Module",
      requiredQuantity: 1,
      action: .produce,
      activity: .manufacturing,
      runs: 1,
      materialEfficiency: 5,
      timeEfficiency: 10,
      blueprintTypeID: 300,
      children: [],
      topLevelRequestID: UUID()
    )

    let projected =
      RecursiveProductionBlueprintCostProjector
      .ownedReactionFormulaAllocations(
        nodes: [reaction, manufacturing],
        explicitActions: [:]
      )
    #expect(projected[200]?.kind == .formula)
    #expect(projected[200]?.amount == 0)
    #expect(projected[300] == nil)

    let overridden =
      RecursiveProductionBlueprintCostProjector
      .ownedReactionFormulaAllocations(
        nodes: [reaction],
        explicitActions: [200: .unresolved]
      )
    #expect(overridden.isEmpty)
  }
}
