import Foundation
import Testing

@testable import EVENexusCore

/// Doctrine stock (DOKTRIN_BEDARF_PLAN.md). The wiki snippets are synthetic
/// and only mirror the markup of the alliance wiki.
@Suite("Doctrine stock")
struct DoctrineStockTests {
  // MARK: EFT

  @Test
  func parsesEFTWithBracketedNameEmptySlotsOfflineChargesAndQuantities() throws {
    let fit = try #require(
      EFTFitParser.parse(
        """

        [Ferox, [DOC] Ferox MWD T2]

        Damage Control II
        Magnetic Field Stabilizer II
        Magnetic Field Stabilizer II
        [Empty Low slot]

        Small F-RX Compact Capacitor Booster, Navy Cap Booster 400
        [empty high slot]
        Shield Command Burst II /offline

        Warrior II x5

        Spike M x1500
        Navy Cap Booster 400 x15
        Warrior II x2
        """
      )
    )
    #expect(fit.hullName == "Ferox")
    #expect(fit.fitName == "[DOC] Ferox MWD T2")
    #expect(
      fit.items == [
        EFTFitItemLine(name: "Damage Control II", quantity: 1),
        EFTFitItemLine(name: "Magnetic Field Stabilizer II", quantity: 2),
        EFTFitItemLine(name: "Small F-RX Compact Capacitor Booster", quantity: 1),
        EFTFitItemLine(name: "Navy Cap Booster 400", quantity: 16),
        EFTFitItemLine(name: "Shield Command Burst II", quantity: 1),
        EFTFitItemLine(name: "Warrior II", quantity: 7),
        EFTFitItemLine(name: "Spike M", quantity: 1500),
      ]
    )
  }

  @Test
  func refitBlocksWithoutHeaderAreNoFits() {
    #expect(EFTFitParser.parse("\nNavy Cap Booster 400 x15\nPower Diagnostic System II x1\n") == nil)
    #expect(EFTFitParser.parse("[Empty High slot]\nWarrior II x5") == nil)
    #expect(EFTFitParser.looksLikeFit("  \n[Osprey, MWD Osprey]\nDamage Control II"))
    #expect(!EFTFitParser.looksLikeFit("Just text"))
  }

  // MARK: DokuWiki

  @Test
  func sectionIDsFollowDokuWiki() {
    var used: [String] = []
    #expect(DokuWikiRawParser.sectionID("General Fleet Fit", existing: &used) == "general_fleet_fit")
    // The wiki runs with `useslash`: “/” separates namespaces and vanishes
    // from anchors (rendered ID of the Hyena page, 25.11.2026).
    #expect(
      DokuWikiRawParser.sectionID("Harpy Fleet/Goku Fleet", existing: &used)
        == "harpy_fleetgoku_fleet")
    #expect(DokuWikiRawParser.sectionID("Freedom Fleet / Angel Fleet") == "freedom_fleetangel_fleet")
    #expect(DokuWikiRawParser.sectionID("[MWD] Fits", existing: &used) == "mwd_fits")
    #expect(DokuWikiRawParser.sectionID("Refits", existing: &used) == "refits")
    #expect(DokuWikiRawParser.sectionID("Refits", existing: &used) == "refits1")
    #expect(DokuWikiRawParser.sectionID("1. Intro", existing: &used) == "intro")
    #expect(DokuWikiRawParser.sectionID("2026", existing: &used) == "section2026")
    #expect(DokuWikiRawParser.sectionID("Défense Fits", existing: &used) == "defense_fits")
    #expect(DokuWikiRawParser.sectionID("Links/Command Bursts") == "linkscommand_bursts")
  }

  @Test
  func rawParserReadsHeadingsCodeBlocksAndLinks() {
    let page = DokuWikiRawParser.parse(
      """
      ====== Ferox Fleet======
      ===== Ship Fits and Details =====
      ==== DPS =====
      [[:member:alliance:military:doctrines:ships:ferox#General Fleet Fit|{{ img }}]]
      **[[/member/alliance/military/doctrines/ships/drake#ferox_fleet_fit|Drake Fittings]]**
      [[member:alliance:military:doctrines:ships:Claw]] [[tackle]] [[https://example.org|x]]
      <code>
      [Ferox, Inline Ferox]
      ===== not a heading =====
      Damage Control II
      </code>
      === Logi ===
      text <code>[Osprey, One Line]</code> [[.:ships:osprey#mwd_fits]]
      """,
      pageID: "member:alliance:military:doctrines:ferox_fleet"
    )
    #expect(page.title == "Ferox Fleet")
    #expect(page.headings.map(\.level) == [1, 2, 3, 4])
    #expect(
      page.headings.map(\.anchor) == ["ferox_fleet", "ship_fits_and_details", "dps", "logi"])
    #expect(page.codeBlocks.count == 2)
    #expect(page.codeBlocks[0].sectionAnchors == ["ferox_fleet", "ship_fits_and_details", "dps"])
    #expect(page.codeBlocks[0].text.contains("===== not a heading ====="))
    #expect(page.codeBlocks[1].text == "[Osprey, One Line]")
    #expect(
      page.codeBlocks[1].sectionAnchors
        == ["ferox_fleet", "ship_fits_and_details", "dps", "logi"])
    let ships = "member:alliance:military:doctrines:ships"
    #expect(
      page.links.map(\.pageID) == [
        "\(ships):ferox", "\(ships):drake", "\(ships):claw",
        "member:alliance:military:doctrines:tackle", "\(ships):osprey",
      ]
    )
    #expect(page.links.map(\.anchor) == ["general_fleet_fit", "ferox_fleet_fit", nil, nil, "mwd_fits"])
    #expect(page.links[0].sectionTitles == ["Ferox Fleet", "Ship Fits and Details", "DPS"])
  }

  /// The wiki hides `/* … */` comments; on 25.11.2026 a commented “Refits”
  /// heading of the Endurance page was the only anchor difference among 732.
  @Test
  func commentsAreSkippedOutsideCodeBlocks() {
    let page = DokuWikiRawParser.parse(
      """
      ====== Ship ======
      /*
      ===== Refits =====
      <code>
      [Rifter, Old Fit]
      Damage Control II
      </code>
      */
      ===== Refits =====
      <code>
      [Rifter, Fit /* not a comment */]
      Damage Control II
      </code>
      Text /* inline */ [[ships:rifter]] /* unclosed
      ===== Hidden =====
      """,
      pageID: "member:alliance:military:doctrines:ships:rifter"
    )
    #expect(page.headings.map(\.anchor) == ["ship", "refits"])
    #expect(page.codeBlocks.count == 1)
    #expect(page.codeBlocks.first?.text.contains("[Rifter, Fit /* not a comment */]") == true)
    #expect(page.links.map(\.pageID) == ["ships:rifter"])
  }

  @Test
  func indexParserListsOnlyExistingPagesOfTheNamespace() {
    let html = """
      <a href="/start?idx=member%3Aalliance%3Amilitary%3Adoctrines%3Aships" title="member:alliance:military:doctrines:ships" class="idx_dir">ships</a>
      <a href="/member/alliance/military/doctrines/ferox_fleet" class="wikilink1" title="member:alliance:military:doctrines:ferox_fleet" data-wiki-id="x">Ferox</a>
      <a href="/member/alliance/military/doctrines/ships/ferox" class="wikilink1" title="member:alliance:military:doctrines:ships:ferox">Ferox</a>
      <a href="/member/alliance/military/doctrines/start" class="wikilink1" title="member:alliance:military:doctrines:start">Start</a>
      <a href="/member/alliance/military/doctrines/ferox_fleet" class="wikilink1" title="member:alliance:military:doctrines:ferox_fleet">Again</a>
      <a href="/member/alliance/military/doctrines/missing" class="wikilink2" title="member:alliance:military:doctrines:missing">Missing</a>
      """
    #expect(
      DokuWikiIndexParser.pageIDs(inNamespace: "member:alliance:military:doctrines", html: html)
        == [
          "member:alliance:military:doctrines:ferox_fleet",
          "member:alliance:military:doctrines:start",
        ]
    )
  }

  @Test
  func configurationBuildsWikiURLs() {
    let configuration = DoctrineWikiConfiguration.braveCollective
    #expect(
      configuration.rawURL(pageID: "member:alliance:military:doctrines:ships:ferox").absoluteString
        == "https://wiki.bravecollective.com/member/alliance/military/doctrines/ships/ferox?do=export_raw"
    )
    #expect(
      configuration.indexURL(namespace: "member:alliance:military:doctrines").absoluteString
        == "https://wiki.bravecollective.com/?idx=member:alliance:military:doctrines"
    )
    #expect(
      configuration.pageURL(pageID: "member:alliance:military:doctrines:ferox_fleet", anchor: "dps")
        .absoluteString
        == "https://wiki.bravecollective.com/member/alliance/military/doctrines/ferox_fleet#dps"
    )
    #expect(configuration.host == "wiki.bravecollective.com")
  }

  // MARK: Library

  private static let doctrineNamespace = "member:alliance:military:doctrines"
  private static let shipNamespace = "member:alliance:military:doctrines:ships"

  private static func shipPage(_ name: String, _ raw: String) -> DokuWikiPage {
    DokuWikiRawParser.parse(raw, pageID: "\(shipNamespace):\(name)")
  }

  private static func doctrinePage(_ name: String, _ raw: String) -> DokuWikiPage {
    DokuWikiRawParser.parse(raw, pageID: "\(doctrineNamespace):\(name)")
  }

  private static let ferox = shipPage(
    "ferox",
    """
    ====== Ferox ======
    ===== General Fleet Fits =====
    <code>
    [Ferox, Ferox T2]
    Damage Control II
    Spike M x100
    </code>
    <code>
    [Ferox, Ferox Meta]
    Damage Control II
    Unknown Widget
    </code>
    ===== Refits =====
    <code>
    Spike M x100
    </code>
    """
  )

  private static let hyena = shipPage(
    "hyena",
    """
    ====== Hyena ======
    ===== General Fleet Fits =====
    <code>
    [Hyena, Web Hyena]
    Stasis Webifier II
    </code>
    ===== Windrunner Fit =====
    <code>
    [Hyena, Painter Hyena]
    Target Painter II
    </code>
    """
  )

  private static let orphan = shipPage(
    "rifter",
    """
    ====== Rifter ======
    <code>
    [Rifter, Unlinked]
    Damage Control II
    </code>
    """
  )

  private static let resolutions: [String: ItemTypeNameResolution] = [
    "Ferox": .resolved(typeID: 16227, name: "Ferox", language: .english),
    "Hyena": .resolved(typeID: 11387, name: "Hyena", language: .english),
    "Rifter": .resolved(typeID: 587, name: "Rifter", language: .english),
    "Osprey": .resolved(typeID: 620, name: "Osprey", language: .english),
    "Damage Control II": .resolved(typeID: 2048, name: "Damage Control II", language: .english),
    "Spike M": .resolved(typeID: 12814, name: "Spike M", language: .english),
    "Stasis Webifier II": .resolved(typeID: 526, name: "Stasis Webifier II", language: .english),
    "Target Painter II": .resolved(typeID: 19814, name: "Target Painter II", language: .english),
    "Unknown Widget": .unknown,
    "Twin Name": .ambiguous([1, 2]),
  ]

  private static func library() -> DoctrineLibrary {
    let fleet = doctrinePage(
      "ferox_fleet",
      """
      ====== Ferox Fleet ======
      ===== Ship Fits and Details =====
      [[:member:alliance:military:doctrines:ships:ferox#general_fleet_fit|{{ img }}]]
      **[[:member:alliance:military:doctrines:ships:ferox#general_fleet_fit|Ferox]]**
      [[/member/alliance/military/doctrines/ships/hyena#target_painting_fit|Hyena]]
      [[:member:alliance:military:doctrines:ships:legion|Legion]]
      ===== Other Ships You Can Use =====
      [[:member:alliance:military:doctrines:ships:hyena#windrunner_fit|Painter]]
      <code>
      [Osprey, Inline Osprey]
      Twin Name x2
      </code>
      """
    )
    let empty = doctrinePage("autobots", "====== Autobots ======\nNo fits yet.")
    let start = doctrinePage("start", "====== Doctrines ======\n[[ships:ferox]]")
    return DoctrineLibraryBuilder.build(
      configuration: .braveCollective,
      doctrinePages: [start, fleet, empty],
      shipPages: [ferox, hyena, orphan],
      resolutions: resolutions,
      unreadablePageIDs: ["\(shipNamespace):broken"],
      importedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }

  @Test
  func builderMapsDoctrinesToLinkedSectionsWithFallbackAndIssues() throws {
    let library = Self.library()
    #expect(library.doctrines.map(\.title) == ["Autobots", "Ferox Fleet"])
    let fleet = try #require(library.doctrines.first { $0.title == "Ferox Fleet" })
    let ships = Self.shipNamespace
    // Inline fit first, then the plural-tolerant section, then every Hyena
    // fit for the dead anchor; the optional Painter Hyena is already used.
    #expect(
      fleet.fitIDs == [
        "\(Self.doctrineNamespace):ferox_fleet#1",
        "\(ships):ferox#1", "\(ships):ferox#2",
        "\(ships):hyena#1", "\(ships):hyena#2",
      ]
    )
    #expect(library.fits.count == 6)
    #expect(library.fits.contains { $0.id == "\(ships):rifter#1" })
    #expect(library.fits.first { $0.id == "\(ships):ferox#2" }?.items.last?.typeID == nil)
    #expect(Set(library.issues) == [
      DoctrineImportIssue(kind: .pageUnreadable, pageID: "\(ships):broken", detail: ""),
      DoctrineImportIssue(kind: .unknownItemName, pageID: "\(ships):ferox", detail: "Unknown Widget"),
      DoctrineImportIssue(
        kind: .ambiguousItemName, pageID: "\(Self.doctrineNamespace):ferox_fleet", detail: "Twin Name"),
      DoctrineImportIssue(
        kind: .linkedSectionMissing,
        pageID: "\(Self.doctrineNamespace):ferox_fleet",
        detail: "\(ships):hyena#target_painting_fit"
      ),
      DoctrineImportIssue(
        kind: .linkedPageMissing,
        pageID: "\(Self.doctrineNamespace):ferox_fleet",
        detail: "\(ships):legion"
      ),
      DoctrineImportIssue(
        kind: .doctrineWithoutFits, pageID: "\(Self.doctrineNamespace):autobots", detail: ""),
    ])
    #expect(library.issues.count == 6)
  }

  @Test
  func libraryAndTargetsRoundTrip() throws {
    let library = Self.library()
    let decoded = try DoctrineLibrary.decode(DoctrineLibrary.encode(library))
    #expect(decoded == library)

    var json = try #require(
      String(data: DoctrineLibrary.encode(library), encoding: .utf8))
    json = json.replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":9")
    #expect(throws: DoctrineLibraryError.unsupportedFormat(9)) {
      try DoctrineLibrary.decode(Data(json.utf8))
    }

    let targets = try DoctrineTargets.decode(
      DoctrineTargets.encode(["a": 5, "b": 0, "c": 20_000]))
    #expect(targets == ["a": 5, "c": DoctrineTargets.maximumTarget])
    #expect(try DoctrineTargets.decode(Data(#"{"a":-3,"b":2}"#.utf8)) == ["b": 2])
  }

  // MARK: Demand

  private static func allumisSnapshot(feroxT2Target target: Int) -> AllumisDoctrineSnapshot {
    AllumisDoctrineSnapshot(
      importedAt: Date(timeIntervalSince1970: 1_800_000_100),
      source: "allumis",
      location: "staging",
      fits: [
        AllumisFitRecord(
          id: 1,
          fitName: "[DOC] Ferox T2",
          hull: DoctrineFitItem(name: "Ferox", typeID: 16227, quantity: 1),
          target: target,
          items: [
            DoctrineFitItem(name: "Damage Control II", typeID: 2048, quantity: 1),
            DoctrineFitItem(name: "Spike M", typeID: 12814, quantity: 100),
          ],
          refitItems: []
        )
      ],
      itemStatistics: [],
      issues: []
    )
  }

  @Test
  func demandCountsFitsOverTheLibraryAndTakesTheTargetFromAllumis() throws {
    let library = Self.library()
    let fleetID = "\(Self.doctrineNamespace):ferox_fleet"
    let wikiOnly = try #require(DoctrineAllumisMerger.merge(library: library, snapshot: nil))
    let none = DoctrineDemandAggregator.demands(sources: wikiOnly)
    // Without an Allumis import the target is unknown, not 0.
    #expect(none.allSatisfy { $0.requiredQuantity == nil })
    #expect(none.allSatisfy { $0.requiredQuantityByDoctrineID.isEmpty })
    let damageControl = try #require(none.first { $0.typeID == 2048 })
    // Ferox T2, Ferox Meta and the unlinked Rifter.
    #expect(damageControl.fitCount == 3)
    #expect(!damageControl.isHull)
    #expect(damageControl.doctrineIDs == [fleetID])
    #expect(none.first { $0.typeID == 16227 }?.isHull == true)
    // Unresolved names never become rows.
    #expect(none.map(\.typeID) == none.map(\.typeID).sorted())
    #expect(!none.contains { $0.name == "Unknown Widget" || $0.name == "Twin Name" })

    let merged = try #require(
      DoctrineAllumisMerger.merge(library: library, snapshot: Self.allumisSnapshot(feroxT2Target: 3)))
    let demands = DoctrineDemandAggregator.demands(sources: merged)
    func required(_ typeID: Int64) -> Int64? {
      demands.first { $0.typeID == typeID }?.requiredQuantity
    }
    #expect(required(16227) == 3)  // only Ferox T2 is at Allumis
    #expect(required(2048) == 3)
    #expect(required(12814) == 300)  // Spike M x100 × 3
    #expect(required(11387) == 0)  // Hyena fits have no Allumis target
    #expect(required(620) == 0)
    #expect(required(587) == 0)  // Rifter is in no doctrine
    #expect(demands.first { $0.typeID == 12814 }?.requiredQuantityByDoctrineID == [fleetID: 300])

    let huge = DoctrineDemandAggregator.demands(
      sources: try #require(
        DoctrineAllumisMerger.merge(library: library, snapshot: Self.allumisSnapshot(feroxT2Target: .max))))
    #expect(huge.first { $0.typeID == 12814 }?.requiredQuantity == 1_000_000)
  }

  // MARK: Rows

  private static func demand(
    _ typeID: Int64 = 1,
    required: Int64? = 0,
    name: String = "Item"
  ) -> DoctrineItemDemand {
    DoctrineItemDemand(
      typeID: typeID, name: name, fitCount: 1, requiredQuantity: required, isHull: false)
  }

  private static func input(
    listed: Int64? = 10,
    region: Double? = 2,
    buildability: DoctrineBuildability = .buildable,
    build: Double? = 100,
    purchase: Double? = 90,
    transport: Double? = 5,
    noSource: Bool = false,
    netSale: Double? = 120
  ) -> DoctrineStockRowInput {
    DoctrineStockRowInput(
      kind: .module,
      listedQuantity: listed,
      regionUnitsPerDay: region,
      hubUnitsPerDay: nil,
      hubVolumeIsComplete: nil,
      buildability: buildability,
      buildCostPerUnit: build,
      importPurchasePerUnit: purchase,
      importTransportPerUnit: transport,
      importHasNoSource: noSource,
      homeBestSellPrice: 125,
      homeNetSalePerUnit: netSale
    )
  }

  @Test
  func coverageDistinguishesOutOfStockNoSalesAndUnknown() {
    #expect(DoctrineStockCoverage.of(listed: 12, unitsPerDay: 4) == .days(3))
    #expect(DoctrineStockCoverage.of(listed: 0, unitsPerDay: 4) == .outOfStock)
    #expect(DoctrineStockCoverage.of(listed: 0, unitsPerDay: 0) == .noSales)
    #expect(DoctrineStockCoverage.of(listed: 5, unitsPerDay: 0) == .noSales)
    #expect(DoctrineStockCoverage.of(listed: nil, unitsPerDay: 4) == .unknown)
    #expect(DoctrineStockCoverage.of(listed: 5, unitsPerDay: nil) == .unknown)
    #expect(DoctrineStockCoverage.outOfStock.sortValue == 0)
    #expect(DoctrineStockCoverage.noSales.sortValue == .infinity)
    #expect(DoctrineStockCoverage.unknown.sortValue == nil)
  }

  @Test
  func rowComputesShortfallImportCostRecommendationAndProfit() {
    let row = DoctrineStockCalculator.row(
      demand: Self.demand(required: 25), input: Self.input())
    #expect(row.shortfall == 15)
    #expect(row.coverage == .days(5))
    #expect(row.importCostPerUnit == 95)
    #expect(row.recommendation == .importFromMainHub)
    #expect(row.savingsPerUnit == 5)
    #expect(row.profitPerUnit == 25)
    #expect(row.recommendedCostPerUnit == 95)

    let cheaperBuild = DoctrineStockCalculator.row(
      demand: Self.demand(required: 5), input: Self.input(build: 80))
    #expect(cheaperBuild.shortfall == 0)
    #expect(cheaperBuild.recommendation == .build)
    #expect(cheaperBuild.savingsPerUnit == 15)
    #expect(cheaperBuild.profitPerUnit == 40)

    let noTarget = DoctrineStockCalculator.row(
      demand: Self.demand(), input: Self.input(listed: nil))
    #expect(noTarget.shortfall == 0)
    let unknownStock = DoctrineStockCalculator.row(
      demand: Self.demand(required: 4), input: Self.input(listed: nil))
    #expect(unknownStock.shortfall == nil)
    // Without an Allumis import the target and so the shortfall are unknown.
    let unknownTarget = DoctrineStockCalculator.row(
      demand: Self.demand(required: nil), input: Self.input(listed: 0))
    #expect(unknownTarget.shortfall == nil)
    let overstocked = DoctrineStockCalculator.row(
      demand: Self.demand(required: 4), input: Self.input(listed: 9))
    #expect(overstocked.shortfall == 0)

    let unknownTransport = DoctrineStockCalculator.row(
      demand: Self.demand(), input: Self.input(transport: nil))
    #expect(unknownTransport.importCostPerUnit == nil)
    #expect(unknownTransport.recommendation == nil)
    #expect(unknownTransport.savingsPerUnit == nil)
    #expect(unknownTransport.profitPerUnit == nil)
  }

  @Test
  func recommendationNeedsBothCostsUnlessOneWayIsImpossible() {
    #expect(
      DoctrineStockCalculator.recommend(
        build: 10, buildability: .buildable, importCost: 10, importHasNoSource: false)
        == .importFromMainHub)
    #expect(
      DoctrineStockCalculator.recommend(
        build: nil, buildability: .notBuildable, importCost: 10, importHasNoSource: false)
        == .importFromMainHub)
    #expect(
      DoctrineStockCalculator.recommend(
        build: nil, buildability: .buildable, importCost: 10, importHasNoSource: false) == nil)
    #expect(
      DoctrineStockCalculator.recommend(
        build: 10, buildability: .buildable, importCost: nil, importHasNoSource: true) == .build)
    #expect(
      DoctrineStockCalculator.recommend(
        build: 10, buildability: .buildable, importCost: nil, importHasNoSource: false) == nil)
    let noBuildNoImport = DoctrineStockCalculator.row(
      demand: Self.demand(),
      input: Self.input(buildability: .notBuildable, build: nil, purchase: nil, noSource: true))
    #expect(noBuildNoImport.recommendation == nil)
    #expect(noBuildNoImport.profitPerUnit == nil)
  }

  @Test
  func sorterKeepsUnknownAfterKnownAscendingAndBeforeDescending() {
    let rows = [
      DoctrineStockCalculator.row(demand: Self.demand(5), input: Self.input(listed: nil)),
      DoctrineStockCalculator.row(demand: Self.demand(4), input: Self.input(listed: 0)),
      DoctrineStockCalculator.row(demand: Self.demand(3), input: Self.input(listed: 8)),
      DoctrineStockCalculator.row(demand: Self.demand(2), input: Self.input(region: 0)),
      DoctrineStockCalculator.row(demand: Self.demand(1), input: Self.input(listed: 8)),
    ]
    #expect(
      DoctrineStockRowSorter.sorted(rows, by: .coverage, ascending: true).map(\.typeID)
        == [4, 1, 3, 2, 5])
    #expect(
      DoctrineStockRowSorter.sorted(rows, by: .coverage, ascending: false).map(\.typeID)
        == [5, 2, 1, 3, 4])
    let named = [
      DoctrineStockCalculator.row(demand: Self.demand(2, name: "beta"), input: Self.input()),
      DoctrineStockCalculator.row(demand: Self.demand(1, name: "Alpha"), input: Self.input()),
      DoctrineStockCalculator.row(demand: Self.demand(3, name: "alpha"), input: Self.input()),
    ]
    #expect(
      DoctrineStockRowSorter.sorted(named, by: .name, ascending: true).map(\.typeID) == [1, 3, 2])
  }

  // MARK: Top lists

  private static func topRow(
    _ typeID: Int64,
    fits: Int = 1,
    required: Int64? = 0,
    listed: Int64? = 0,
    name: String = "Item",
    build: Double? = 100,
    netSale: Double? = 120,
    doctrines: [String] = []
  ) -> DoctrineStockRow {
    DoctrineStockCalculator.row(
      demand: DoctrineItemDemand(
        typeID: typeID, name: name, fitCount: fits, requiredQuantity: required, isHull: false,
        doctrineIDs: doctrines),
      input: Self.input(listed: listed, build: build, netSale: netSale)
    )
  }

  @Test
  func shortfallProfitIsShortfallTimesProfitAndZeroWithoutShortfall() {
    // Shortfall 15, import 95, net sale 120 → 25 per unit.
    #expect(Self.topRow(1, required: 25, listed: 10).shortfallProfit == 375)
    // No shortfall: nothing to earn, also while the profit is unknown.
    #expect(Self.topRow(2, required: 5, listed: 10).shortfallProfit == 0)
    #expect(Self.topRow(3, required: 5, listed: 10, netSale: nil).shortfallProfit == 0)
    // A shortfall with an unknown profit, or an unknown shortfall, is unknown.
    #expect(Self.topRow(4, required: 25, listed: 10, netSale: nil).shortfallProfit == nil)
    #expect(Self.topRow(5, required: nil, listed: 10).shortfallProfit == nil)
    #expect(Self.topRow(6, required: 25, listed: nil).shortfallProfit == nil)
    // A loss stays negative.
    #expect(Self.topRow(7, required: 12, listed: 10, netSale: 90).shortfallProfit == -10)
  }

  @Test
  func mostUsedRanksByFitsThenTargetThenTypeID() {
    let rows = [
      Self.topRow(1, fits: 3, required: 10),
      Self.topRow(2, fits: 9, required: 0),
      Self.topRow(3, fits: 3, required: nil),
      Self.topRow(4, fits: 3, required: 40),
      Self.topRow(5, fits: 3, required: 10),
      Self.topRow(6, fits: 0, required: 99),
    ]
    let result = DoctrineTopRanking.ranked(rows, by: .mostUsed)
    #expect(result.entries.map(\.id) == [2, 4, 1, 5, 3])
    #expect(result.entries.map(\.rank) == [1, 2, 3, 4, 5])
    #expect(result.candidateCount == 6)
    #expect(result.unknownCount == 0)
    #expect(result.nonPositiveCount == 1)
    let limited = DoctrineTopRanking.ranked(rows, by: .mostUsed, limit: 2)
    #expect(limited.entries.map(\.id) == [2, 4])
    #expect(DoctrineTopRanking.limit == 10)
  }

  @Test
  func profitOpportunitiesRankOnlyAShortfallWithAPositiveProfit() {
    let rows = [
      Self.topRow(1, required: 25, listed: 10),  // 15 × 25 = 375
      Self.topRow(2, required: 50, listed: 10),  // 40 × 25 = 1,000
      Self.topRow(3, required: 5, listed: 10),  // no shortfall → 0
      Self.topRow(4, required: 25, listed: 10, netSale: 90),  // loss
      Self.topRow(5, required: 25, listed: 10, netSale: nil),  // profit unknown
      Self.topRow(6, required: nil, listed: 10),  // no Allumis import
      Self.topRow(7, required: 25, listed: 10, build: 70),  // build: 15 × 50 = 750
      Self.topRow(8, required: 25, listed: 10),  // tie with 1, later type ID
    ]
    let result = DoctrineTopRanking.ranked(rows, by: .profitOpportunity)
    #expect(result.entries.map(\.id) == [2, 7, 1, 8])
    #expect(result.entries.first?.row.shortfallProfit == 1_000)
    #expect(result.candidateCount == 8)
    #expect(result.unknownCount == 2)
    #expect(result.nonPositiveCount == 2)
    #expect(DoctrineTopRanking.ranked([], by: .profitOpportunity) == .empty)
  }

  @Test
  func topEntrySorterKeepsUnknownAfterKnownAndTheRankAsTieBreaker() {
    let entries = [
      DoctrineTopEntry(
        rank: 1, row: Self.topRow(11, required: 30, listed: 10, name: "beta", build: 70)),
      DoctrineTopEntry(rank: 2, row: Self.topRow(12, required: nil, listed: 10, name: "Alpha")),
      DoctrineTopEntry(
        rank: 3, row: Self.topRow(13, required: 30, listed: 10, name: "alpha", doctrines: ["a", "b"])),
    ]
    func sorted(_ column: DoctrineTopSortColumn, _ ascending: Bool) -> [Int] {
      DoctrineTopEntrySorter.sorted(entries, by: column, ascending: ascending).map(\.rank)
    }
    #expect(sorted(.rank, true) == [1, 2, 3])
    #expect(sorted(.rank, false) == [3, 2, 1])
    #expect(sorted(.name, true) == [2, 3, 1])
    #expect(sorted(.name, false) == [1, 2, 3])
    // Unknown target after known ascending, before them descending; equal
    // values keep the ranking.
    #expect(sorted(.requiredQuantity, true) == [1, 3, 2])
    #expect(sorted(.requiredQuantity, false) == [2, 1, 3])
    #expect(sorted(.shortfall, true) == [1, 3, 2])
    #expect(sorted(.doctrines, false) == [3, 1, 2])
    // Build before import; no recommendation would come last ascending.
    #expect(sorted(.recommendation, true) == [1, 2, 3])
    #expect(sorted(.recommendation, false) == [2, 3, 1])
    #expect(sorted(.shortfallProfit, true) == [3, 1, 2])
    #expect(sorted(.shortfallProfit, false) == [2, 1, 3])
  }

  @Test
  func stockDifferenceIsCurrentStockMinusTargetWithItsSign() {
    #expect(Self.topRow(1, required: 30, listed: 10).stockDifference == -20)
    #expect(Self.topRow(2, required: 30, listed: 45).stockDifference == 15)
    #expect(Self.topRow(3, required: 30, listed: 30).stockDifference == 0)
    // A negative listed stock counts as 0, as in the shortfall.
    #expect(Self.topRow(4, required: 30, listed: -5).stockDifference == -30)
    #expect(Self.topRow(4, required: 30, listed: -5).shortfall == 30)
    // Without a target there is nothing to meet; unknown stays unknown.
    #expect(Self.topRow(5, required: 0, listed: 10).stockDifference == nil)
    #expect(Self.topRow(6, required: nil, listed: 10).stockDifference == nil)
    #expect(Self.topRow(7, required: 30, listed: nil).stockDifference == nil)
    // Never a wrapped value.
    #expect(Self.topRow(8, required: .max, listed: 0).stockDifference == -.max)
  }

  @Test
  func topEntrySorterSortsCurrentStockAndDifference() {
    let entries = [
      DoctrineTopEntry(rank: 1, row: Self.topRow(21, required: 30, listed: 45)),  // +15
      DoctrineTopEntry(rank: 2, row: Self.topRow(22, required: 0, listed: 80)),  // no target
      DoctrineTopEntry(rank: 3, row: Self.topRow(23, required: 30, listed: 10)),  // −20
      DoctrineTopEntry(rank: 4, row: Self.topRow(24, required: 30, listed: nil)),  // unknown
      DoctrineTopEntry(rank: 5, row: Self.topRow(25, required: 10, listed: 10)),  // 0
    ]
    func sorted(_ column: DoctrineTopSortColumn, _ ascending: Bool) -> [Int] {
      DoctrineTopEntrySorter.sorted(entries, by: column, ascending: ascending).map(\.rank)
    }
    // Largest gap first ascending; without a target and unknown after the
    // known values, in the order of the ranking.
    #expect(sorted(.stockDifference, true) == [3, 5, 1, 2, 4])
    #expect(sorted(.stockDifference, false) == [2, 4, 1, 5, 3])
    #expect(sorted(.listedQuantity, true) == [3, 5, 1, 2, 4])
    #expect(sorted(.listedQuantity, false) == [4, 2, 1, 3, 5])
  }

  @Test
  func itemKindsFollowTheSDECategory() {
    #expect(DoctrineItemKind.kind(categoryName: "Ship") == .hull)
    #expect(DoctrineItemKind.kind(categoryName: "Charge") == .charge)
    #expect(DoctrineItemKind.kind(categoryName: "Drone") == .drone)
    #expect(DoctrineItemKind.kind(categoryName: "Fighter") == .drone)
    #expect(DoctrineItemKind.kind(categoryName: "Module") == .module)
    #expect(DoctrineItemKind.kind(categoryName: "Implant") == .module)
    #expect(DoctrineItemKind.kind(categoryName: nil) == .module)
  }

  // MARK: Import

  private struct FakeWiki: Sendable {
    let pages: [String: (status: Int, mime: String, body: String)]

    func fetch(_ url: URL) async throws -> (Data, URLResponse) {
      let key = url.absoluteString
      guard let page = pages[key] else { throw URLError(.fileDoesNotExist) }
      let response = HTTPURLResponse(
        url: url,
        statusCode: page.status,
        httpVersion: nil,
        headerFields: ["Content-Type": "\(page.mime); charset=utf-8"]
      )!
      return (Data(page.body.utf8), response)
    }
  }

  private static func indexHTML(_ ids: [String]) -> String {
    ids.map { "<a href=\"/x\" class=\"wikilink1\" title=\"\($0)\">x</a>" }.joined(separator: "\n")
  }

  @Test
  func importerReadsIndexesAndPagesAndReportsUnreadablePages() async throws {
    let configuration = DoctrineWikiConfiguration.braveCollective
    let doctrine = "\(Self.doctrineNamespace):ferox_fleet"
    let ship = "\(Self.shipNamespace):ferox"
    let broken = "\(Self.shipNamespace):broken"
    let wiki = FakeWiki(pages: [
      configuration.indexURL(namespace: Self.doctrineNamespace).absoluteString: (
        200, "text/html", Self.indexHTML([doctrine, "\(Self.doctrineNamespace):start"])
      ),
      configuration.indexURL(namespace: Self.shipNamespace).absoluteString: (
        200, "text/html", Self.indexHTML([ship, broken])
      ),
      configuration.rawURL(pageID: doctrine).absoluteString: (
        200, "text/plain",
        "====== Ferox Fleet ======\n[[:\(ship)#general_fleet_fits|Ferox]]"
      ),
      configuration.rawURL(pageID: ship).absoluteString: (
        200, "text/plain", "====== Ferox ======\n===== General Fleet Fits =====\n<code>\n[Ferox, F]\nDamage Control II\n</code>"
      ),
      configuration.rawURL(pageID: broken).absoluteString: (
        200, "text/html", "<html>Login</html>"
      ),
    ])
    let progress = ProgressRecorder()
    let importer = DoctrineWikiImporter(
      configuration: configuration,
      pause: .zero,
      fetch: { try await wiki.fetch($0) },
      resolve: { names in
        Dictionary(uniqueKeysWithValues: names.map { name in
          (name, Self.resolutions[name] ?? .unknown)
        })
      }
    )
    let library = try await importer.run(
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      progress: { await progress.record($0) }
    )
    #expect(library.doctrines.map(\.title) == ["Ferox Fleet"])
    #expect(library.doctrines.first?.fitIDs == ["\(ship)#1"])
    #expect(library.issues == [DoctrineImportIssue(kind: .pageUnreadable, pageID: broken, detail: "")])
    #expect(library.source == "https://wiki.bravecollective.com")
    #expect(await progress.values.last == DoctrineWikiImportProgress(completed: 3, total: 3))
    #expect(await progress.values.first == DoctrineWikiImportProgress(completed: 0, total: 3))
  }

  @Test
  func importerReportsMissingSessionAndHTTPErrors() async {
    let configuration = DoctrineWikiConfiguration.braveCollective
    let indexURL = configuration.indexURL(namespace: Self.doctrineNamespace).absoluteString
    func importer(_ wiki: FakeWiki) -> DoctrineWikiImporter {
      DoctrineWikiImporter(
        configuration: configuration,
        pause: .zero,
        fetch: { try await wiki.fetch($0) },
        resolve: { _ in [:] }
      )
    }
    await #expect(throws: DoctrineWikiImportError.notSignedIn) {
      try await importer(FakeWiki(pages: [indexURL: (200, "text/html", "<html>Log In</html>")])).run()
    }
    await #expect(throws: DoctrineWikiImportError.httpStatus(503)) {
      try await importer(FakeWiki(pages: [indexURL: (503, "text/html", "")])).run()
    }
    let doctrine = "\(Self.doctrineNamespace):a"
    let onlyLoginPages = FakeWiki(pages: [
      indexURL: (200, "text/html", Self.indexHTML([doctrine])),
      configuration.indexURL(namespace: Self.shipNamespace).absoluteString: (200, "text/html", ""),
      configuration.rawURL(pageID: doctrine).absoluteString: (200, "text/html", "<html/>"),
    ])
    await #expect(throws: DoctrineWikiImportError.notSignedIn) {
      try await importer(onlyLoginPages).run()
    }
  }
}

private actor ProgressRecorder {
  private(set) var values: [DoctrineWikiImportProgress] = []

  func record(_ value: DoctrineWikiImportProgress) {
    values.append(value)
  }
}
