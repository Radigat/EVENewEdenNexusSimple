import Testing

@testable import EVENexusCore

@Suite("Production input")
struct ProductionInputParserTests {
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
}
