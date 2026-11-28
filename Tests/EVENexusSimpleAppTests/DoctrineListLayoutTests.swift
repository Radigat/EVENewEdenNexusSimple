import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

/// Owner request 27.11.2026: the doctrine list of the page “Doctrine stock”
/// uses several columns instead of one long list.
@MainActor
@Suite("Doctrine list layout")
struct DoctrineListLayoutTests {
  @Test
  func columnCountFollowsTheWidthWithGapsAndALimit() {
    let withAllumis = DoctrineListLayout.columnMinimumWidth(showsAllumis: true)
    let withoutAllumis = DoctrineListLayout.columnMinimumWidth(showsAllumis: false)
    #expect(withAllumis == 408)
    #expect(withoutAllumis == 234)

    // Unknown width while the page lays out for the first time.
    #expect(DoctrineListLayout.columnCount(width: 0, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: .infinity, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: 300, columnMinimumWidth: withAllumis) == 1)
    // Two columns need 2 × 408 plus a line with 16 pt on each side.
    #expect(DoctrineListLayout.columnCount(width: 848, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: 849, columnMinimumWidth: withAllumis) == 2)
    #expect(DoctrineListLayout.columnCount(width: 1_650, columnMinimumWidth: withAllumis) == 3)
    #expect(DoctrineListLayout.columnCount(width: 5_000, columnMinimumWidth: withoutAllumis) == 4)
  }

  @Test
  func rowsFillTheColumnsTopToBottomInTheirOrder() {
    let rows = Array(1...10)
    #expect(DoctrineListLayout.columns(rows, count: 3) == [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]])
    #expect(DoctrineListLayout.columns(rows, count: 1) == [rows])
    #expect(DoctrineListLayout.columns(Array(1...9), count: 3) == [[1, 2, 3], [4, 5, 6], [7, 8, 9]])
    // Fewer rows than columns give fewer columns, never empty ones.
    #expect(DoctrineListLayout.columns([1, 2], count: 4) == [[1], [2]])
    #expect(DoctrineListLayout.columns([1, 2, 3, 4, 5], count: 4) == [[1, 2], [3, 4], [5]])
    #expect(DoctrineListLayout.columns([Int](), count: 3).isEmpty)
    #expect(DoctrineListLayout.columns([1, 2], count: 0) == [[1, 2]])
  }
}

/// Owner request 27.11.2026: top lists “most used” and “profit
/// opportunities” on the page “Doctrine stock”.
@MainActor
@Suite("Doctrine top lists")
struct DoctrineTopListsTests {
  @Test
  func listsStandSideBySideOnlyWhenBothFit() {
    // With current stock and difference (owner request 28.11.2026).
    #expect(DoctrineTopListLayout.mostUsedMinimumWidth == 602)
    #expect(DoctrineTopListLayout.profitMinimumWidth == 598)
    // Both lists plus a line with 16 pt on each side.
    #expect(!DoctrineTopListLayout.isSideBySide(width: 1_232))
    #expect(DoctrineTopListLayout.isSideBySide(width: 1_233))
    #expect(!DoctrineTopListLayout.isSideBySide(width: 0))
    #expect(!DoctrineTopListLayout.isSideBySide(width: .infinity))
  }

  private func display(
    _ typeID: Int64,
    fits: Int,
    required: Int64?,
    build: Double?
  ) -> DoctrineStockDisplayRow {
    let row = DoctrineStockCalculator.row(
      demand: DoctrineItemDemand(
        typeID: typeID, name: "Item \(typeID)", fitCount: fits, requiredQuantity: required,
        isHull: false, doctrineIDs: ["d"]),
      input: DoctrineStockRowInput(
        kind: .module,
        listedQuantity: 10,
        regionUnitsPerDay: 1,
        hubUnitsPerDay: nil,
        hubVolumeIsComplete: nil,
        buildability: .buildable,
        buildCostPerUnit: build,
        importPurchasePerUnit: 90,
        importTransportPerUnit: 5,
        importHasNoSource: false,
        homeBestSellPrice: 125,
        homeNetSalePerUnit: 120
      )
    )
    return DoctrineStockDisplayRow(
      revision: 1,
      row: row,
      issues: [],
      buildHelp: "build \(typeID)",
      importHelp: "import \(typeID)",
      doctrinesWithTarget: [],
      otherDoctrines: ["D"],
      doctrinesHelp: "doctrines \(typeID)"
    )
  }

  @Test
  func modelRanksEveryRowAndKeepsTheHelpOfListedItems() {
    var rows = [
      display(1, fits: 5, required: 30, build: 70),  // build, 20 × 50
      display(2, fits: 8, required: 30, build: 100),  // import, 20 × 25
      display(3, fits: 2, required: 5, build: 100),  // no shortfall
    ]
    // Twelve more rows used in one fit each, without a shortfall.
    rows += (100..<112).map { display($0, fits: 1, required: 0, build: 100) }
    let model = DoctrineTopListsModel(revision: 4, rows: rows)
    #expect(model.revision == 4)
    #expect(model.mostUsed.entries.map(\.id) == [2, 1, 3, 100, 101, 102, 103, 104, 105, 106])
    #expect(model.mostUsed.candidateCount == 15)
    #expect(model.profitOpportunities.entries.map(\.id) == [1, 2])
    #expect(model.profitOpportunities.nonPositiveCount == 13)
    #expect(model.wayHelpByType == [1: "build 1", 2: "import 2"])
    #expect(model.doctrinesHelpByType[2] == "doctrines 2")
    #expect(model.doctrinesHelpByType[110] == nil)
    #expect(DoctrineTopListsModel.empty.mostUsed == .empty)
  }

  @Test
  func everyTopListTextIsTranslatedInBothLanguages() throws {
    let keys = [
      "Statistics",
      "Most used · Top %lld",
      "Items in the most fits of the wiki and of the group “Only at Allumis”; a tie goes to the larger target.",
      "No doctrine item yet.",
      "Profit opportunities · Top %lld",
      "Profit/unit × shortfall: what filling the target earns with an own sell order at the Home Hub. Only items with a shortfall and a positive profit are ranked.",
      "Without an Allumis import there is no shortfall and so no profit opportunity.",
      "No item has a shortfall and a positive profit yet.",
      "Total profit",
      "Profit/unit × shortfall.",
      "Way",
      "The cheaper way per unit: build, or import from the Main Hub.",
      "Place in the ranking.",
      "%lld items without a known profit or shortfall",
      "%lld items without a shortfall or a positive profit",
      "Current stock",
      "Sell units of every seller at the Home Hub at the latest stock point.",
      "Difference",
      "Current stock minus target: below 0 (red) too few, 0 or more (green) enough. “–” without a target.",
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
    #expect(AppLanguage.german.localized("Statistics") == "Statistik")
    #expect(AppLanguage.german.localized("Way") == "Weg")
    #expect(AppLanguage.german.localized("Current stock") == "Ist")
    #expect(AppLanguage.german.localized("Difference") == "Differenz")
  }

  @Test
  func differenceShowsItsSignAndZeroWithoutOne() {
    let format = DoctrineNumberFormat(locale: Locale(identifier: "de_DE"))
    #expect(format.signedInteger(-1_192) == "-1.192")
    #expect(format.signedInteger(64) == "+64")
    #expect(format.signedInteger(0) == "0")
    #expect(format.signedInteger(nil) == "—")
  }
}
