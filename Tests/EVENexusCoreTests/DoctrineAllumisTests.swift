import Foundation
import Testing

@testable import EVENexusCore

/// Doctrine stock with Allumis (DOKTRIN_BEDARF_PLAN.md, section G). The
/// JSON rows are synthetic and only mirror the shape of the Allumis table.
@Suite("Doctrine stock with Allumis")
struct DoctrineAllumisTests {
  // MARK: Configuration

  @Test
  func configurationBuildsTheTableURLAndRecognizesSignedInPages() {
    let configuration = AllumisConfiguration.braveDoctrineMarket
    #expect(
      configuration.detailedTableURL.absoluteString
        == "https://api.allumis.co.uk/api/?path=/doctrine/ships/detailedtable/&loc=staging")
    // Without the trailing slash Allumis redirects to plain http.
    #expect(configuration.loginURL.absoluteString == "https://api.allumis.co.uk/login/")
    #expect(configuration.isSignedInPage(URL(string: "https://api.allumis.co.uk/user/")))
    #expect(configuration.isSignedInPage(URL(string: "https://api.allumis.co.uk/user/doctrines/list/")))
    #expect(!configuration.isSignedInPage(URL(string: "https://allumis.co.uk/")))
    #expect(!configuration.isSignedInPage(URL(string: "https://api.allumis.co.uk/login")))
    #expect(!configuration.isSignedInPage(URL(string: "https://login.eveonline.com/user/")))
    #expect(!configuration.isSignedInPage(nil))
  }

  @Test
  func plainHTTPAllumisAddressesBecomeHTTPS() {
    let configuration = AllumisConfiguration.braveDoctrineMarket
    #expect(configuration.webHosts == ["api.allumis.co.uk", "allumis.co.uk"])
    #expect(
      configuration.secureReplacement(for: URL(string: "http://api.allumis.co.uk/login/"))?.absoluteString
        == "https://api.allumis.co.uk/login/")
    #expect(
      configuration.secureReplacement(
        for: URL(string: "http://api.allumis.co.uk:80/api/?path=/doctrine/ships/detailedtable/&loc=staging")
      )?.absoluteString
        == "https://api.allumis.co.uk/api/?path=/doctrine/ships/detailedtable/&loc=staging")
    #expect(
      configuration.secureReplacement(for: URL(string: "http://allumis.co.uk/"))?.absoluteString
        == "https://allumis.co.uk/")
    #expect(configuration.secureReplacement(for: URL(string: "https://api.allumis.co.uk/user/")) == nil)
    #expect(configuration.secureReplacement(for: URL(string: "http://login.eveonline.com/")) == nil)
    #expect(configuration.secureReplacement(for: URL(string: "http://evil-allumis.co.uk/")) == nil)
    #expect(configuration.secureReplacement(for: nil) == nil)
  }

  // MARK: Parsing

  private static let table = """
    [
      {"itemName": "Caracal", "fittingName": "[DOC] Tripod", "quantity": "1", "minStock": "5",
       "avg7dVol": 1.5, "dropped": "0", "destroyed": "4", "node_index": "12",
       "_children": [
         {"itemName": "Damage Control II", "fittingName": "Fit Item", "quantity": "1",
          "minStock": "5", "avg7dVol": 140.5, "dropped": "3", "destroyed": "7", "node_index": "900"},
         {"itemName": "Warp Scrambler II", "fittingName": "Refit Item", "quantity": "1",
          "minStock": "5", "avg7dVol": 2, "dropped": "0", "destroyed": "1", "node_index": "901"},
         {"itemName": "Broken Module", "fittingName": "Fit Item", "quantity": "0", "node_index": "902"}
       ]},
      {"itemName": "Ferox", "fittingName": "[DOC] Ferox MWD", "quantity": 1, "minStock": 20,
       "avg7dVol": "3", "dropped": "1", "destroyed": "2", "node_index": 3,
       "_children": [
         {"itemName": "Damage Control II", "fittingName": "Fit Item", "quantity": "1",
          "minStock": "20", "avg7dVol": 140.5, "dropped": "3", "destroyed": "9", "node_index": "910"},
         {"itemName": "Spike M", "fittingName": "Fit Item", "quantity": "1000",
          "minStock": "20000", "avg7dVol": null, "dropped": "0", "destroyed": "0", "node_index": "911"},
         {"itemName": "Spike M", "fittingName": "Fit Item", "quantity": "500",
          "minStock": "10000", "node_index": "912"}
       ]},
      {"itemName": "Ferox", "fittingName": "Duplicate", "minStock": "1", "node_index": "3"},
      {"itemName": "", "fittingName": "No hull", "minStock": "1", "node_index": "4"},
      {"itemName": "Rifter", "fittingName": "No id", "minStock": "1"}
    ]
    """

  @Test
  func parserReadsFitsTargetsItemsRefitsAndStatistics() throws {
    let parsed = try AllumisDetailedTableParser.parse(Data(Self.table.utf8))
    #expect(parsed.fits.map(\.id) == [3, 12])
    let ferox = parsed.fits[0]
    #expect(ferox.hullName == "Ferox")
    #expect(ferox.fitName == "[DOC] Ferox MWD")
    #expect(ferox.target == 20)
    #expect(
      ferox.items == [
        .init(name: "Damage Control II", quantity: 1),
        .init(name: "Spike M", quantity: 1500),
      ])
    let caracal = parsed.fits[1]
    #expect(caracal.target == 5)
    #expect(caracal.items == [.init(name: "Damage Control II", quantity: 1)])
    #expect(caracal.refitItems == [.init(name: "Warp Scrambler II", quantity: 1)])

    let statistics = Dictionary(uniqueKeysWithValues: parsed.statistics.map { ($0.name, $0) })
    #expect(statistics["Damage Control II"]?.averageDailyVolume7Days == 140.5)
    #expect(statistics["Damage Control II"]?.dropped == 3)
    // Differing values keep the larger one.
    #expect(statistics["Damage Control II"]?.destroyed == 9)
    #expect(statistics["Ferox"]?.averageDailyVolume7Days == 3)
    #expect(statistics["Spike M"]?.averageDailyVolume7Days == nil)
    #expect(statistics["Spike M"]?.dropped == 0)

    #expect(
      Set(parsed.invalidEntries) == [
        AllumisImportIssue(kind: .invalidEntry, fitName: "[DOC] Tripod", detail: "Broken Module"),
        AllumisImportIssue(kind: .invalidEntry, fitName: "No hull", detail: "itemName"),
        AllumisImportIssue(kind: .invalidEntry, fitName: "No id", detail: "node_index"),
      ])
    #expect(
      parsed.itemNames == ["Caracal", "Damage Control II", "Warp Scrambler II", "Ferox", "Spike M"])
  }

  @Test
  func parserRejectsAnythingButAnArrayOfRows() {
    #expect(throws: (any Error).self) {
      try AllumisDetailedTableParser.parse(Data("{\"error\": \"x\"}".utf8))
    }
    #expect(throws: (any Error).self) {
      try AllumisDetailedTableParser.parse(Data("<html></html>".utf8))
    }
  }

  // MARK: Import

  private struct FakeAllumis: Sendable {
    let status: Int
    let mime: String
    let body: String

    func fetch(_ url: URL) async throws -> (Data, URLResponse) {
      let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "\(mime); charset=utf-8"]
      )!
      return (Data(body.utf8), response)
    }
  }

  private static let resolutions: [String: ItemTypeNameResolution] = [
    "Ferox": .resolved(typeID: 37, name: "Ferox", language: .english),
    "Caracal": .resolved(typeID: 621, name: "Caracal", language: .english),
    "Damage Control II": .resolved(typeID: 2048, name: "Damage Control II", language: .english),
    "Spike M": .resolved(typeID: 12_612, name: "Spike M", language: .english),
    "Warp Scrambler II": .ambiguous([1, 2]),
  ]

  @Test
  func importerBuildsTheSnapshotAndReportsUnresolvedNames() async throws {
    let allumis = FakeAllumis(status: 200, mime: "application/json", body: Self.table)
    let requested = NameRecorder()
    let importer = AllumisImporter(
      fetch: { try await allumis.fetch($0) },
      resolve: { names in
        await requested.record(names)
        return Self.resolutions
      }
    )
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = try await importer.run(now: { date })
    #expect(await requested.names == ["Caracal", "Damage Control II", "Ferox", "Spike M", "Warp Scrambler II"])
    #expect(snapshot.importedAt == date)
    #expect(snapshot.location == "staging")
    #expect(snapshot.fits.map(\.hull.typeID) == [37, 621])
    #expect(snapshot.fits[1].refitItems == [DoctrineFitItem(name: "Warp Scrambler II", typeID: nil, quantity: 1)])
    #expect(
      snapshot.issues.contains(
        AllumisImportIssue(kind: .ambiguousItemName, fitName: "[DOC] Tripod", detail: "Warp Scrambler II")))
    #expect(
      snapshot.itemStatistics.first { $0.name == "Damage Control II" }
        == AllumisItemStatistic(
          name: "Damage Control II", typeID: 2048, averageDailyVolume7Days: 140.5, dropped: 3, destroyed: 9))
    let decoded = try AllumisDoctrineSnapshot.decode(AllumisDoctrineSnapshot.encode(snapshot))
    #expect(decoded == snapshot)
  }

  @Test
  func importerTreatsRedirectsLoginPagesAndBadTablesAsErrors() async {
    func run(_ allumis: FakeAllumis) async throws {
      _ = try await AllumisImporter(
        fetch: { try await allumis.fetch($0) },
        resolve: { _ in [:] }
      ).run()
    }
    await #expect(throws: AllumisImportError.notSignedIn) {
      try await run(FakeAllumis(status: 302, mime: "text/html", body: "Redirecting"))
    }
    await #expect(throws: AllumisImportError.notSignedIn) {
      try await run(FakeAllumis(status: 401, mime: "application/json", body: "{}"))
    }
    await #expect(throws: AllumisImportError.notSignedIn) {
      try await run(FakeAllumis(status: 200, mime: "text/html", body: "<html>LOG IN</html>"))
    }
    await #expect(throws: AllumisImportError.httpStatus(503)) {
      try await run(FakeAllumis(status: 503, mime: "text/html", body: ""))
    }
    await #expect(throws: AllumisImportError.unreadableResponse) {
      try await run(FakeAllumis(status: 200, mime: "application/json", body: "{\"rows\": []}"))
    }
    await #expect(throws: AllumisImportError.noFits) {
      try await run(FakeAllumis(status: 200, mime: "application/json", body: "[]"))
    }
  }

  // MARK: Matching

  private static func item(_ name: String, _ typeID: Int64?, _ quantity: Int64 = 1) -> DoctrineFitItem {
    DoctrineFitItem(name: name, typeID: typeID, quantity: quantity)
  }

  private static let feroxContent = [item("Damage Control II", 2048), item("Spike M", 12_612, 1500)]

  private static func wikiFit(_ id: String, hull: DoctrineFitItem, name: String, items: [DoctrineFitItem])
    -> DoctrineFitRecord
  {
    DoctrineFitRecord(id: id, pageID: "ships", sectionAnchors: [], hull: hull, fitName: name, items: items)
  }

  private static func allumisFit(
    _ id: Int64,
    hull: DoctrineFitItem,
    name: String,
    target: Int,
    items: [DoctrineFitItem],
    refits: [DoctrineFitItem] = []
  ) -> AllumisFitRecord {
    AllumisFitRecord(id: id, fitName: name, hull: hull, target: target, items: items, refitItems: refits)
  }

  private static let library = DoctrineLibrary(
    importedAt: Date(timeIntervalSince1970: 0),
    source: "wiki",
    doctrines: [
      DoctrineRecord(id: "ferox_fleet", title: "Ferox Fleet", fitIDs: ["A", "B"]),
      DoctrineRecord(id: "caracal_fleet", title: "Caracal Fleet", fitIDs: ["C", "D"]),
    ],
    fits: [
      wikiFit("A", hull: item("Ferox", 37), name: "[DOC] Ferox MWD", items: feroxContent),
      wikiFit("B", hull: item("Ferox", 37), name: "[DOC] Ferox AB", items: feroxContent),
      wikiFit("C", hull: item("Caracal", 621), name: "[WORKSHOP] Tripod  RLML", items: [item("Damage Control II", 2048)]),
      wikiFit("D", hull: item("Drake", 24_698), name: "Drake", items: []),
    ],
    issues: []
  )

  private static func snapshot(_ fits: [AllumisFitRecord], statistics: [AllumisItemStatistic] = [])
    -> AllumisDoctrineSnapshot
  {
    AllumisDoctrineSnapshot(
      importedAt: Date(timeIntervalSince1970: 100),
      source: "allumis",
      location: "staging",
      fits: fits,
      itemStatistics: statistics,
      issues: []
    )
  }

  @Test
  func mergePairsByContentAndNameThenContentThenNameAndGroupsTheRest() throws {
    let allumis = Self.snapshot([
      // Pass 1: same content and name pairs with B, although A comes first.
      Self.allumisFit(1, hull: Self.item("Ferox", 37), name: "Ferox AB", target: 20, items: Self.feroxContent),
      // Pass 2: same content, other name; refits do not count.
      Self.allumisFit(
        2, hull: Self.item("Ferox", 37), name: "Ferox Brawl", target: 5, items: Self.feroxContent.reversed(),
        refits: [Self.item("Warp Scrambler II", 448)]),
      // Pass 3: same hull and name, other content.
      Self.allumisFit(
        3, hull: Self.item("Caracal", 621), name: "[DOC] tripod rlml", target: 10,
        items: [Self.item("Damage Control II", 2048, 2)]),
      // No wiki counterpart.
      Self.allumisFit(4, hull: Self.item("Talwar", 32_878), name: "[DOC] Talwar", target: 7, items: []),
    ])
    let merge = try #require(DoctrineAllumisMerger.merge(library: Self.library, snapshot: allumis))
    #expect(merge.hasAllumisImport)
    #expect(merge.allumisTargetByFitID == ["A": 5, "B": 20, "C": 10, "allumis:4": 7])
    #expect(merge.allumisFitByFitID.mapValues(\.id) == ["A": 2, "B": 1, "C": 3, "allumis:4": 4])
    #expect(merge.contentDiffersFitIDs == ["C"])
    #expect(merge.matchedWikiFitCount == 3)
    #expect(merge.onlyAtAllumisFitCount == 1)
    #expect(merge.library.doctrines.map(\.id) == ["ferox_fleet", "caracal_fleet", "allumis:only"])
    #expect(merge.library.doctrines.last?.fitIDs == ["allumis:4"])
    #expect(merge.library.fits.last?.hull == Self.item("Talwar", 32_878))
    #expect(merge.library.fits.count == 5)

    let ferox = merge.allumisTargets(for: merge.library.doctrines[0])
    #expect(ferox.matchedFitCount == 2)
    #expect(ferox.targetCounts.map(\.target) == [20, 5])
    // Equal frequency: the larger target comes first.
    #expect(ferox.mostFrequentTarget == 20)
    let caracal = merge.allumisTargets(for: merge.library.doctrines[1])
    #expect(caracal.fitCount == 2)
    #expect(caracal.matchedFitCount == 1)
    #expect(caracal.contentDiffersFitCount == 1)
    #expect(caracal.mostFrequentTarget == 10)
    let unknown = merge.allumisTargets(for: DoctrineRecord(id: "x", title: "x", fitIDs: ["D"]))
    #expect(unknown.mostFrequentTarget == nil)
    #expect(unknown.matchedFitCount == 0)
  }

  @Test
  func mostFrequentTargetWinsAndEveryFitPairsOnlyOnce() throws {
    let allumis = Self.snapshot([
      Self.allumisFit(1, hull: Self.item("Ferox", 37), name: "x", target: 3, items: Self.feroxContent),
      Self.allumisFit(2, hull: Self.item("Ferox", 37), name: "y", target: 3, items: Self.feroxContent),
      // A third fit with the same content finds no free wiki fit.
      Self.allumisFit(5, hull: Self.item("Ferox", 37), name: "z", target: 9, items: Self.feroxContent),
    ])
    let merge = try #require(DoctrineAllumisMerger.merge(library: Self.library, snapshot: allumis))
    #expect(merge.allumisTargetByFitID["A"] == 3)
    #expect(merge.allumisTargetByFitID["B"] == 3)
    #expect(merge.library.doctrines.last?.fitIDs == ["allumis:5"])
    let ferox = merge.allumisTargets(for: merge.library.doctrines[0])
    #expect(ferox.targetCounts == [.init(target: 3, fitCount: 2)])
    #expect(ferox.mostFrequentTarget == 3)
  }

  @Test
  func mergeWorksWithOnlyOneSource() throws {
    #expect(DoctrineAllumisMerger.merge(library: nil, snapshot: nil) == nil)
    let wikiOnly = try #require(DoctrineAllumisMerger.merge(library: Self.library, snapshot: nil))
    #expect(wikiOnly.library == Self.library)
    #expect(!wikiOnly.hasAllumisImport)
    #expect(wikiOnly.allumisTargetByFitID.isEmpty)
    #expect(wikiOnly.allumisFitByFitID.isEmpty)
    #expect(wikiOnly.allTypeIDs == [37, 2048, 12_612, 621, 24_698])
    let allumisOnly = try #require(
      DoctrineAllumisMerger.merge(
        library: nil,
        snapshot: Self.snapshot([
          Self.allumisFit(8, hull: Self.item("Ferox", 37), name: "x", target: 4, items: [])
        ])
      ))
    #expect(allumisOnly.library.doctrines.map(\.id) == ["allumis:only"])
    #expect(allumisOnly.hasAllumisImport)
    #expect(allumisOnly.allumisTargetByFitID == ["allumis:8": 4])
  }

  @Test
  func fitNamesCompareWithoutTagsCaseAndExtraSpaces() {
    #expect(DoctrineAllumisMerger.normalizedFitName("[DOC] [MN]  Ferox   MWD ") == "ferox mwd")
    #expect(DoctrineAllumisMerger.normalizedFitName("Siren III") == "siren iii")
    #expect(DoctrineAllumisMerger.normalizedFitName("[DOC]") == "")
  }

  // MARK: Item figures

  @Test
  func itemFiguresKeepTheStatisticsOfListedTypes() {
    let allumis = Self.snapshot(
      [Self.allumisFit(1, hull: Self.item("Ferox", 37), name: "a", target: 20, items: Self.feroxContent)],
      statistics: [
        AllumisItemStatistic(name: "Damage Control II", typeID: 2048, averageDailyVolume7Days: 140.5, dropped: 3, destroyed: 9),
        AllumisItemStatistic(name: "Spike M", typeID: 12_612, averageDailyVolume7Days: nil, dropped: 0, destroyed: nil),
        AllumisItemStatistic(name: "Rifter", typeID: 587, averageDailyVolume7Days: 2, dropped: 1, destroyed: 1),
        AllumisItemStatistic(name: "Unknown", typeID: nil, averageDailyVolume7Days: 9, dropped: 9, destroyed: 9),
      ]
    )
    let figures = DoctrineAllumisItemAggregator.figures(snapshot: allumis)
    #expect(figures.count == 3)
    #expect(figures[2048]?.lostLast10Days == 12)
    #expect(figures[2048]?.averageDailyVolume7Days == 140.5)
    #expect(figures[12_612] != nil)
    #expect(figures[12_612]?.lostLast10Days == nil)
    #expect(figures[587]?.lostLast10Days == 2)
    // The hull has a target but no statistic.
    #expect(figures[37] == nil)
    #expect(DoctrineAllumisItemFigures.notListed.lostLast10Days == nil)
    #expect(DoctrineAllumisItemFigures.notListed.averageDailyVolume7Days == nil)
  }

  // MARK: Doctrine table

  @Test
  func targetSumsTheAllumisContentOncePerFitAndSplitsItOntoDoctrines() throws {
    // “mixed” shares fit A with the Ferox fleet and fit C with the Caracal
    // fleet.
    let library = DoctrineLibrary(
      importedAt: Self.library.importedAt,
      source: Self.library.source,
      doctrines: Self.library.doctrines + [DoctrineRecord(id: "mixed", title: "Mixed", fitIDs: ["A", "C"])],
      fits: Self.library.fits,
      issues: []
    )
    let allumis = Self.snapshot([
      // Pairs with B; the refit does not count.
      Self.allumisFit(
        1, hull: Self.item("Ferox", 37), name: "Ferox AB", target: 20, items: Self.feroxContent,
        refits: [Self.item("Warp Scrambler II", 448)]),
      // Pairs with A, which two doctrines use.
      Self.allumisFit(2, hull: Self.item("Ferox", 37), name: "Ferox Brawl", target: 5, items: Self.feroxContent),
      // Pairs with C by hull and name; its own content counts, also the
      // Ballistic Control System the wiki fit does not have.
      Self.allumisFit(
        3, hull: Self.item("Caracal", 621), name: "[DOC] tripod rlml", target: 10,
        items: [Self.item("Damage Control II", 2048, 2), Self.item("Ballistic Control System II", 22_291)]),
      Self.allumisFit(4, hull: Self.item("Talwar", 32_878), name: "[DOC] Talwar", target: 7, items: []),
      // Pairs with D, but without a target.
      Self.allumisFit(5, hull: Self.item("Drake", 24_698), name: "Drake", target: 0, items: []),
      Self.allumisFit(6, hull: Self.item("Unknown hull", nil), name: "Unknown", target: 9, items: []),
    ])
    let merge = try #require(DoctrineAllumisMerger.merge(library: library, snapshot: allumis))
    #expect(merge.allTypeIDs == [37, 2048, 12_612, 621, 24_698, 22_291, 32_878])
    let demands = DoctrineDemandAggregator.demands(sources: merge)
    let byType = Dictionary(uniqueKeysWithValues: demands.map { ($0.typeID, $0) })

    #expect(byType[37]?.requiredQuantity == 25)
    #expect(byType[2048]?.requiredQuantity == 45)  // 20 + 5 + 10 × 2
    #expect(byType[12_612]?.requiredQuantity == 37_500)  // (20 + 5) × 1500
    #expect(byType[621]?.requiredQuantity == 10)
    #expect(byType[22_291]?.requiredQuantity == 10)
    #expect(byType[32_878]?.requiredQuantity == 7)
    #expect(byType[24_698]?.requiredQuantity == 0)
    #expect(byType[448] == nil)
    #expect(demands.count == 7)

    // Parts per doctrine; a shared fit counts for each of its doctrines.
    #expect(byType[37]?.requiredQuantityByDoctrineID == ["ferox_fleet": 25, "mixed": 5])
    #expect(
      byType[2048]?.requiredQuantityByDoctrineID == ["ferox_fleet": 25, "caracal_fleet": 20, "mixed": 25])
    #expect(byType[22_291]?.requiredQuantityByDoctrineID == ["caracal_fleet": 10, "mixed": 10])
    #expect(byType[32_878]?.requiredQuantityByDoctrineID == ["allumis:only": 7])
    #expect(byType[24_698]?.requiredQuantityByDoctrineID == [:])

    // Doctrines and fits count the wiki and the Allumis content.
    #expect(byType[2048]?.doctrineIDs == ["ferox_fleet", "caracal_fleet", "mixed"])
    #expect(byType[2048]?.fitCount == 3)
    #expect(byType[22_291]?.doctrineIDs == ["caracal_fleet", "mixed"])
    #expect(byType[22_291]?.fitCount == 1)
    #expect(byType[22_291]?.name == "Ballistic Control System II")
    #expect(byType[32_878]?.doctrineIDs == ["allumis:only"])
    #expect(byType[32_878]?.isHull == true)
    #expect(byType[24_698]?.doctrineIDs == ["caracal_fleet"])
  }

  private static func row(
    _ typeID: Int64,
    doctrines: [String] = [],
    required: Int64? = 0,
    home: Double? = nil,
    main: Double? = nil,
    allumis: DoctrineAllumisItemFigures? = nil
  ) -> DoctrineStockRow {
    DoctrineStockCalculator.row(
      demand: DoctrineItemDemand(
        typeID: typeID, name: "Item", fitCount: 1, requiredQuantity: required, isHull: false,
        doctrineIDs: doctrines),
      input: DoctrineStockRowInput(
        kind: .module,
        listedQuantity: nil,
        regionUnitsPerDay: nil,
        hubUnitsPerDay: nil,
        hubVolumeIsComplete: nil,
        buildability: .unknown,
        buildCostPerUnit: nil,
        importPurchasePerUnit: nil,
        importTransportPerUnit: nil,
        importHasNoSource: false,
        homeBestSellPrice: home,
        homeNetSalePerUnit: nil,
        mainBestSellPrice: main,
        allumis: allumis
      )
    )
  }

  @Test
  func priceRatioNeedsBothPrices() {
    #expect(Self.row(1, home: 112, main: 100).homeToMainPriceRatio == 1.12)
    #expect(Self.row(1, home: 112, main: nil).homeToMainPriceRatio == nil)
    #expect(Self.row(1, home: nil, main: 100).homeToMainPriceRatio == nil)
    #expect(Self.row(1, home: 112, main: 0).homeToMainPriceRatio == nil)
  }

  @Test
  func newColumnsSortByTypedValueWithUnknownLast() {
    func figures(_ volume: Double?, lost: Int64?) -> DoctrineAllumisItemFigures {
      DoctrineAllumisItemFigures(averageDailyVolume7Days: volume, dropped: lost, destroyed: lost.map { _ in 0 })
    }
    let rows = [
      Self.row(1, doctrines: ["a"], required: 40, home: 150, main: 100, allumis: figures(2, lost: 5)),
      Self.row(2, doctrines: ["a", "b", "c"], required: nil, home: 90, main: 100, allumis: nil),
      Self.row(3, doctrines: [], required: 0, home: nil, main: 100, allumis: figures(nil, lost: nil)),
      Self.row(4, doctrines: ["a", "b"], required: 40, home: 100, main: 100, allumis: figures(7, lost: 1)),
    ]
    func order(_ column: DoctrineStockSortColumn, ascending: Bool) -> [Int64] {
      DoctrineStockRowSorter.sorted(rows, by: column, ascending: ascending).map(\.typeID)
    }
    #expect(order(.doctrines, ascending: false) == [2, 4, 1, 3])
    // An unknown target (no Allumis import) is not 0.
    #expect(order(.requiredQuantity, ascending: true) == [3, 1, 4, 2])
    #expect(order(.requiredQuantity, ascending: false) == [2, 1, 4, 3])
    #expect(order(.allumisAverageDailyVolume7Days, ascending: true) == [1, 4, 2, 3])
    #expect(order(.allumisLostLast10Days, ascending: false) == [2, 3, 1, 4])
    #expect(order(.homeToMainPriceRatio, ascending: true) == [2, 4, 1, 3])
  }
}

private actor NameRecorder {
  private(set) var names: [String] = []

  func record(_ values: [String]) {
    names = values
  }
}
