import Foundation
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
  func shoppingListShowsExactlyTheExportedPurchasesAndMarketCoverage() {
    let completeQuote = quote(
      typeID: 34,
      quantity: 5_000,
      total: 20_000,
      filledQuantity: 5_000
    )
    let partialQuote = quote(
      typeID: 37,
      quantity: 25,
      total: nil,
      filledQuantity: 10
    )
    let shoppingList = EVEShoppingList.make(
      from: [
        material(
          typeID: 34,
          name: "Tritanium",
          toBuy: 5_000,
          quote: completeQuote
        ),
        material(name: "Produced Component", toBuy: 0, toProduce: 12),
        material(
          typeID: 37,
          name: "Isogen",
          toBuy: 25,
          quote: partialQuote
        ),
      ]
    )

    #expect(shoppingList.items.map(\.name) == ["Isogen", "Tritanium"])
    #expect(shoppingList.items.map(\.quantity) == [25, 5_000])
    #expect(!shoppingList.items[0].hasCompleteMarketCoverage)
    #expect(shoppingList.items[1].hasCompleteMarketCoverage)
    #expect(shoppingList.totalQuantity == 5_025)
    #expect(shoppingList.purchaseTotal == nil)
  }

  @Test
  func shoppingListTotalsOnlyCompletelyCoveredPurchaseQuotes() {
    let shoppingList = EVEShoppingList.make(
      from: [
        material(
          typeID: 34,
          name: "Tritanium",
          toBuy: 5,
          quote: quote(
            typeID: 34,
            quantity: 5,
            total: 20,
            filledQuantity: 5
          )
        ),
        material(
          typeID: 37,
          name: "Isogen",
          toBuy: 2,
          quote: quote(
            typeID: 37,
            quantity: 2,
            total: 14,
            filledQuantity: 2
          )
        ),
      ]
    )

    #expect(shoppingList.purchaseTotal == 34)
  }

  @Test
  func producesAnEmptyExportWhenNothingNeedsBuying() {
    let export = EVEMultibuyExport.make(
      from: [material(name: "Intermediate", toBuy: 0, toProduce: 3)]
    )

    #expect(export.itemCount == 0)
    #expect(export.text.isEmpty)
  }

  @Test
  func exportsWarehouseConsumptionAsASeparateReplenishmentList() {
    let export = EVEMultibuyExport.makeWarehouseReplenishment(
      from: [
        material(name: "Tritanium", toBuy: 0, fromStock: 5_000),
        material(name: "Isogen", toBuy: 25, fromStock: 10),
        material(name: "Mexallon", toBuy: 20, fromStock: 0),
      ]
    )

    #expect(export.itemCount == 2)
    #expect(export.text == "Isogen 10\nTritanium 5000")
  }

  private func material(
    typeID: Int64? = nil,
    name: String,
    toBuy: Int64,
    toProduce: Int64 = 0,
    fromStock: Int64 = 0,
    productionActivity: BlueprintActivityDefinition.Kind? = nil,
    quote: PriceQuote? = nil
  ) -> MaterialRequirement {
    MaterialRequirement(
      typeID: typeID ?? Int64(name.hashValue),
      name: name,
      required: toBuy + toProduce + fromStock,
      fromStock: fromStock,
      toBuy: toBuy,
      toProduce: toProduce,
      quote: quote,
      productionActivity: productionActivity
    )
  }

  private func quote(
    typeID: Int64,
    quantity: Int64,
    total: Double?,
    filledQuantity: Int64
  ) -> PriceQuote {
    PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: .materialBuy,
      total: total,
      weightedUnitPrice: total.map { $0 / Double(quantity) },
      filledQuantity: filledQuantity,
      capturedAt: Date(timeIntervalSince1970: 1_000),
      source: SourceIdentity(provider: "fixture", version: "1"),
      warnings: []
    )
  }
}
