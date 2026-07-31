import Testing

@testable import EVENexusCore

@Suite("EVE Multibuy export")
struct EVEMultibuyExportTests {
  @Test
  func exportsOnlyPurchasesInDeterministicEVEFormat() {
    let export = EVEMultibuyExport.make(
      from: [
        material(name: "Tritanium", toBuy: 5_000),
        material(name: "Produced Component", toBuy: 0, toProduce: 12),
        material(name: "Isogen", toBuy: 25),
      ]
    )

    #expect(export.itemCount == 2)
    #expect(export.text == "Isogen 25\nTritanium 5000")
  }

  @Test
  func includesIntermediatesThatThePlanExplicitlyBuys() {
    let export = EVEMultibuyExport.make(
      from: [
        material(
          name: "Construction Component",
          toBuy: 4,
          productionActivity: .manufacturing
        )
      ]
    )

    #expect(export.itemCount == 1)
    #expect(export.text == "Construction Component 4")
  }

  @Test
  func producesAnEmptyExportWhenNothingNeedsBuying() {
    let export = EVEMultibuyExport.make(
      from: [material(name: "Intermediate", toBuy: 0, toProduce: 3)]
    )

    #expect(export.itemCount == 0)
    #expect(export.text.isEmpty)
  }

  private func material(
    name: String,
    toBuy: Int64,
    toProduce: Int64 = 0,
    productionActivity: BlueprintActivityDefinition.Kind? = nil
  ) -> MaterialRequirement {
    MaterialRequirement(
      typeID: Int64(name.hashValue),
      name: name,
      required: toBuy + toProduce,
      fromStock: 0,
      toBuy: toBuy,
      toProduce: toProduce,
      quote: nil,
      productionActivity: productionActivity
    )
  }
}
