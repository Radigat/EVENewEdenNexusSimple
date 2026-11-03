import CryptoKit
@testable import EVENexusCore
import EVEStaticDataKit
import Foundation
import Testing

@testable import EVENexusSimpleApp

/// Golden master of the Planner's runtime calculation (ANALYSE_2026-11-02,
/// prompt A1). Synthetic SDE catalog and synthetic ESI markets run through
/// `manufacturingProductionTree` and `calculate`; the complete results are
/// compared with the normalized JSON references in `Tests/GoldenMaster`.
/// Speed work must keep them unchanged. `EVE_NEXUS_RECORD_GOLDEN=1` rewrites
/// the references and fails the run so a recording is never mistaken for a
/// pass.
@MainActor
@Suite("Planner golden master", .serialized)
struct PlannerGoldenMasterTests {
  @Test
  func singleProductWithReactionStockAndTwoPurchaseLocations() async throws {
    let fixture = try await GoldenPlannerFixture.make()
    defer { fixture.remove() }
    let runtime = fixture.runtime
    let input = "Golden Ship 5 10 20"
    let manualStock = "Tritanium|50000\nGolden Component|10"

    let tree = try await runtime.manufacturingProductionTree(
      productName: "Golden Ship",
      targetQuantity: 5,
      materialEfficiency: 10,
      timeEfficiency: 20,
      assetWarehouse: AssetWarehouse(inventories: []),
      warehouseHasSnapshot: false,
      plannerInputOverride: input,
      requiresCompleteBlueprintCostsInSelectedPlan: false,
      availableStockOverride: [GoldenType.tritanium: 50_000, GoldenType.component: 10],
      usesExactPlannerPreferences: true,
      automaticSupply: true
    )
    try GoldenMaster.verify(tree, named: "planner-single-tree")

    let calculated = await runtime.calculate(
      input: input,
      manualStockInput: manualStock,
      purchaseLocationIDs: fixture.purchaseLocationIDs,
      blueprintCostAllocations: GoldenPlannerFixture.allocations,
      requiresCompleteBlueprintCosts: true,
      automaticSupply: true,
      manualSupplyTypeIDs: []
    )
    #expect(runtime.errorMessage == nil)
    // Only the caller decides which plan is shown (A3/G3).
    #expect(runtime.plan == nil)
    let plan = try #require(calculated)
    #expect(plan.materials.contains { $0.typeID == GoldenType.reactionProduct })
    try GoldenMaster.verify(plan, named: "planner-single-plan")
  }

  @Test
  func collectiveProductionOfTwoProducts() async throws {
    let fixture = try await GoldenPlannerFixture.make()
    defer { fixture.remove() }
    let runtime = fixture.runtime
    let input = "Golden Ship 3 10 20\nGolden Module 20 8 16"

    let tree = try await runtime.manufacturingProductionTree(
      productName: "Golden Ship",
      targetQuantity: 23,
      materialEfficiency: 10,
      timeEfficiency: 20,
      assetWarehouse: AssetWarehouse(inventories: []),
      warehouseHasSnapshot: false,
      plannerInputOverride: input,
      requiresCompleteBlueprintCostsInSelectedPlan: false,
      usesExactPlannerPreferences: true,
      automaticSupply: true
    )
    try GoldenMaster.verify(tree, named: "planner-collective-tree")

    let calculated = await runtime.calculate(
      input: input,
      purchaseLocationIDs: fixture.purchaseLocationIDs,
      blueprintCostAllocations: GoldenPlannerFixture.allocations,
      requiresCompleteBlueprintCosts: true,
      automaticSupply: true,
      manualSupplyTypeIDs: []
    )
    #expect(runtime.errorMessage == nil)
    let plan = try #require(calculated)
    #expect(plan.requests.count == 2)
    try GoldenMaster.verify(plan, named: "planner-collective-plan")
  }

  /// A3/G1: one click session with prefetch gives exactly the same tree and
  /// plan and loads the Main Hub market only once.
  @Test
  func sharedClickSessionGivesTheSameResultsWithFewerLoads() async throws {
    let input = "Golden Ship 5 10 20"
    let manualStock = "Tritanium|50000\nGolden Component|10"
    func run(withSession: Bool) async throws -> (
      ManufacturingProductionTreeSnapshot, IndustryPlanSnapshot?, Int
    ) {
      let fixture = try await GoldenPlannerFixture.make()
      defer { fixture.remove() }
      let runtime = fixture.runtime
      let metrics = PlannerCalculationMetrics()
      return try await PlannerCalculationMetrics.$current.withValue(metrics) {
        let session = withSession ? PlannerClickDataCache() : nil
        if let session {
          await runtime.prefetchPlannerClickData(
            session,
            input: input,
            purchaseLocationIDs: fixture.purchaseLocationIDs,
            authorizations: [],
            clientID: ""
          )
        }
        let tree = try await runtime.manufacturingProductionTree(
          productName: "Golden Ship",
          targetQuantity: 5,
          materialEfficiency: 10,
          timeEfficiency: 20,
          assetWarehouse: AssetWarehouse(inventories: []),
          warehouseHasSnapshot: false,
          plannerInputOverride: input,
          requiresCompleteBlueprintCostsInSelectedPlan: false,
          availableStockOverride: [GoldenType.tritanium: 50_000, GoldenType.component: 10],
          usesExactPlannerPreferences: true,
          automaticSupply: true,
          session: session
        )
        let plan = await runtime.calculate(
          input: input,
          manualStockInput: manualStock,
          purchaseLocationIDs: fixture.purchaseLocationIDs,
          blueprintCostAllocations: GoldenPlannerFixture.allocations,
          requiresCompleteBlueprintCosts: true,
          automaticSupply: true,
          manualSupplyTypeIDs: [],
          session: session
        )
        await session?.cancelAll()
        return (tree, plan, metrics.count(of: .marketSnapshots))
      }
    }

    let separate = try await run(withSession: false)
    let shared = try await run(withSession: true)

    try GoldenMaster.verify(shared.0, named: "planner-single-tree")
    try GoldenMaster.verify(try #require(shared.1), named: "planner-single-plan")
    // Main market, Blueprint and formula markets and the Home Hub once each;
    // without a session the calculation loads the Main market again.
    #expect(shared.2 == 4)
    #expect(separate.2 == 5)
  }

  @Test
  func normalizationIsIndependentOfIdentifiersAndHashOrder() throws {
    struct Sample {
      let id: UUID
      let createdAt: Date
      let byType: [Int64: Double]
      let tags: Set<String>
      let owner: [UUID: String]
    }
    let first = UUID()
    let second = UUID()
    let a = Sample(
      id: first,
      createdAt: .now,
      byType: [34: 4.5, 35: 10, 36: 60],
      tags: ["b", "a", "c"],
      owner: [first: "x"]
    )
    let b = Sample(
      id: second,
      createdAt: .distantPast,
      byType: [36: 60, 35: 10, 34: 4.5],
      tags: ["c", "a", "b"],
      owner: [second: "x"]
    )
    #expect(GoldenMaster.json(a) == GoldenMaster.json(b))
    #expect(GoldenMaster.json(a).contains("\"uuid-1\""))
  }
}

// MARK: - Fixture

enum GoldenType {
  static let tritanium: Int64 = 34
  static let pyerite: Int64 = 35
  static let mexallon: Int64 = 36
  static let atmosphericGases: Int64 = 16_634
  static let cadmium: Int64 = 16_643
  static let reactionProduct: Int64 = 1_001
  static let component: Int64 = 1_002
  static let ship: Int64 = 1_003
  static let module: Int64 = 1_004
  static let formula: Int64 = 1_101
  static let componentBlueprint: Int64 = 1_102
  static let shipBlueprint: Int64 = 1_103
  static let moduleBlueprint: Int64 = 1_104
}

@MainActor
struct GoldenPlannerFixture {
  let root: URL
  let runtime: RuntimeState
  let purchaseLocationIDs: Set<UUID>

  static let allocations: [Int64: IndustryBlueprintCostAllocation] = [
    GoldenType.componentBlueprint: .init(
      blueprintTypeID: GoldenType.componentBlueprint,
      productName: "Golden Component",
      kind: .bpo,
      amount: 0,
      source: "Golden master BPO"
    ),
    GoldenType.shipBlueprint: .init(
      blueprintTypeID: GoldenType.shipBlueprint,
      productName: "Golden Ship",
      kind: .bpc,
      amount: 2_000_000,
      source: "Golden master BPC"
    ),
    GoldenType.moduleBlueprint: .init(
      blueprintTypeID: GoldenType.moduleBlueprint,
      productName: "Golden Module",
      kind: .bpo,
      amount: 0,
      source: "Golden master BPO"
    ),
    GoldenType.formula: .init(
      blueprintTypeID: GoldenType.formula,
      productName: "Golden Reaction Product",
      kind: .formula,
      amount: 0,
      source: "Golden master formula"
    ),
  ]

  static func make() async throws -> GoldenPlannerFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-golden-master-\(UUID().uuidString)",
      isDirectory: true
    )
    let catalog = SQLiteStaticCatalog(
      rootURL:
        root
        .appendingPathComponent("sde", isDirectory: true)
        .appendingPathComponent("catalog-store", isDirectory: true)
    )
    _ = try await catalog.activate(try catalogSnapshot())

    let runtime = RuntimeState(
      dataRoot: root,
      startBackgroundServices: false,
      esiTransport: GoldenMarketTransport()
    )
    let main = TradingLocationConfiguration(
      location: .jita,
      marketTaxes: MarketTaxConfiguration(salesTaxRate: 0.036, brokerFeeRate: 0.015)
    )
    let home = TradingLocationConfiguration(
      location: .amarr,
      marketTaxes: MarketTaxConfiguration(salesTaxRate: 0.045, brokerFeeRate: 0.02)
    )
    runtime.productionBasis = ProductionBasis(
      tradingLocations: [main, home],
      mainTradingLocationID: main.id,
      homeTradingLocationID: home.id,
      logistics: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: ProcurementLocation.amarr.name,
        marketLocationName: ProcurementLocation.jita.name,
        homeTradeHub: .amarr,
        iskPerCubicMeter: 800
      )
    )
    runtime.reactionProfile = ReactionProfile(
      structureName: "Golden Reactor",
      manualEffectiveMaterialMultiplier: 1,
      manualEffectiveTimeMultiplier: 1,
      manualEffectiveJobCostMultiplier: 1
    )
    return GoldenPlannerFixture(
      root: root,
      runtime: runtime,
      purchaseLocationIDs: [main.id, home.id]
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  private static func catalogSnapshot() throws -> StaticDataCatalogSnapshot {
    let build = 4_242
    let hash = String(repeating: "a", count: 64)
    func type(
      _ id: Int64,
      _ name: String,
      group: Int64 = 20,
      category: Int64 = 10,
      packagedVolume: Double
    ) -> StaticItemTypeSnapshot {
      StaticItemTypeSnapshot(
        externalID: id,
        groupExternalID: group,
        categoryExternalID: category,
        marketGroupExternalID: nil,
        name: name,
        description: nil,
        volume: packagedVolume,
        packagedVolume: packagedVolume,
        basePrice: nil,
        portionSize: 1,
        published: true,
        iconExternalID: nil
      )
    }
    func blueprint(
      _ id: Int64,
      activity: StaticIndustryActivity,
      seconds: Int64,
      materials: [(Int64, Int64)],
      product: Int64,
      quantity: Int64
    ) -> StaticBlueprintSnapshot {
      StaticBlueprintSnapshot(
        blueprintTypeID: id,
        maxProductionLimit: activity == .reaction ? nil : 100,
        activities: [
          StaticBlueprintActivitySnapshot(
            activity: activity,
            timeSeconds: seconds,
            materials: materials.enumerated().map {
              StaticBlueprintMaterialSnapshot(
                itemTypeID: $0.element.0,
                quantity: $0.element.1,
                sortOrder: $0.offset
              )
            },
            products: [
              StaticBlueprintProductSnapshot(
                itemTypeID: product,
                quantity: quantity,
                probability: nil,
                sortOrder: 0
              )
            ]
          )
        ]
      )
    }
    return try StaticDataCatalogSnapshot(
      buildNumber: build,
      contentSHA256: hash,
      officialArchiveURL:
        "https://developers.eveonline.com/static-data/tranquility/eve-online-static-data-\(build)-jsonl.zip",
      sourceFormat: .jsonLines,
      categories: [
        StaticItemCategorySnapshot(externalID: 10, name: "Fixture", published: true)
      ],
      groups: [
        StaticItemGroupSnapshot(
          externalID: 20,
          categoryExternalID: 10,
          name: "Fixture Group",
          published: true
        ),
        StaticItemGroupSnapshot(
          externalID: 18,
          categoryExternalID: 10,
          name: "Mineral",
          published: true
        ),
        StaticItemGroupSnapshot(
          externalID: 427,
          categoryExternalID: 10,
          name: "Moon Materials",
          published: true
        ),
      ],
      itemTypes: [
        type(GoldenType.tritanium, "Tritanium", group: 18, packagedVolume: 0.01),
        type(GoldenType.pyerite, "Pyerite", group: 18, packagedVolume: 0.01),
        type(GoldenType.mexallon, "Mexallon", group: 18, packagedVolume: 0.01),
        type(
          GoldenType.atmosphericGases,
          "Atmospheric Gases",
          group: 427,
          packagedVolume: 0.05
        ),
        type(GoldenType.cadmium, "Cadmium", group: 427, packagedVolume: 0.05),
        type(GoldenType.reactionProduct, "Golden Reaction Product", packagedVolume: 1),
        type(GoldenType.component, "Golden Component", packagedVolume: 5),
        type(GoldenType.ship, "Golden Ship", packagedVolume: 2_500),
        type(GoldenType.module, "Golden Module", packagedVolume: 5),
        type(GoldenType.formula, "Golden Reaction Formula", packagedVolume: 0.01),
        type(GoldenType.componentBlueprint, "Golden Component Blueprint", packagedVolume: 0.01),
        type(GoldenType.shipBlueprint, "Golden Ship Blueprint", packagedVolume: 0.01),
        type(GoldenType.moduleBlueprint, "Golden Module Blueprint", packagedVolume: 0.01),
      ],
      blueprints: [
        blueprint(
          GoldenType.formula,
          activity: .reaction,
          seconds: 10_800,
          materials: [(GoldenType.atmosphericGases, 100), (GoldenType.cadmium, 100)],
          product: GoldenType.reactionProduct,
          quantity: 200
        ),
        blueprint(
          GoldenType.componentBlueprint,
          activity: .manufacturing,
          seconds: 600,
          materials: [(GoldenType.tritanium, 100), (GoldenType.pyerite, 40)],
          product: GoldenType.component,
          quantity: 1
        ),
        blueprint(
          GoldenType.shipBlueprint,
          activity: .manufacturing,
          seconds: 3_600,
          materials: [
            (GoldenType.component, 10),
            (GoldenType.reactionProduct, 50),
            (GoldenType.mexallon, 500),
          ],
          product: GoldenType.ship,
          quantity: 1
        ),
        blueprint(
          GoldenType.moduleBlueprint,
          activity: .manufacturing,
          seconds: 1_200,
          materials: [(GoldenType.component, 2), (GoldenType.tritanium, 1_000)],
          product: GoldenType.module,
          quantity: 1
        ),
      ],
      reactionRuleProfile: ReactionRuleProfile(
        catalogBuildNumber: build,
        catalogContentSHA256: hash,
        verificationStatus: .needsReview,
        verifiedAt: .distantPast,
        sourceURLs: ["fixture://type-dogma"],
        formulaGroupKinds: [:],
        facilities: [],
        reactors: [],
        rigs: [],
        reactionsSkillTypeID: 1,
        skillTimeBonusBasisPointsPerLevel: -400
      )
    )
  }
}

/// Answers the public ESI routes of one Planner calculation from fixed order
/// books for Jita (The Forge) and Amarr (Domain). Unknown routes answer 404.
struct GoldenMarketTransport: ESIHTTPTransporting {
  private struct Order {
    let id: Int64
    let typeID: Int64
    let locationID: Int64
    let systemID: Int64
    let isBuy: Bool
    let price: Double
    let volume: Int64
  }

  private static let theForge: Int64 = 10_000_002
  private static let domain: Int64 = 10_000_043
  private static let jitaStation: Int64 = 60_003_760
  private static let otherForgeStation: Int64 = 60_000_001
  private static let amarrStation: Int64 = 60_008_494

  private static let orders: [Int64: [Order]] = {
    var nextID: Int64 = 1
    func order(
      _ typeID: Int64,
      _ isBuy: Bool,
      _ price: Double,
      _ volume: Int64,
      at locationID: Int64 = jitaStation
    ) -> Order {
      defer { nextID += 1 }
      return Order(
        id: nextID,
        typeID: typeID,
        locationID: locationID,
        systemID: locationID == amarrStation ? 30_002_187 : 30_000_142,
        isBuy: isBuy,
        price: price,
        volume: volume
      )
    }
    let forgeOrders: [Order] = [
      order(GoldenType.tritanium, false, 4.0, 10_000_000),
      order(GoldenType.tritanium, false, 4.1, 50_000_000),
      order(GoldenType.tritanium, false, 3.0, 99_000_000, at: otherForgeStation),
      order(GoldenType.tritanium, true, 3.8, 100_000_000),
      order(GoldenType.pyerite, false, 10.0, 5_000_000),
      order(GoldenType.pyerite, false, 10.5, 20_000_000),
      order(GoldenType.pyerite, true, 9.0, 10_000_000),
      order(GoldenType.mexallon, false, 60, 1_000_000),
      order(GoldenType.mexallon, false, 62, 5_000_000),
      order(GoldenType.mexallon, true, 55, 1_000_000),
      order(GoldenType.atmosphericGases, false, 50, 100_000),
      order(GoldenType.atmosphericGases, false, 55, 1_000_000),
      order(GoldenType.atmosphericGases, true, 40, 500_000),
      order(GoldenType.cadmium, false, 400, 50_000),
      order(GoldenType.cadmium, false, 420, 500_000),
      order(GoldenType.cadmium, true, 350, 100_000),
      order(GoldenType.reactionProduct, false, 900, 20_000),
      order(GoldenType.reactionProduct, true, 700, 10_000),
      order(GoldenType.component, false, 9_000, 200),
      order(GoldenType.component, false, 9_500, 1_000),
      order(GoldenType.component, true, 7_000, 500),
      order(GoldenType.ship, false, 3_000_000, 20),
      order(GoldenType.ship, true, 2_500_000, 10),
      order(GoldenType.module, false, 70_000, 100),
      order(GoldenType.module, true, 55_000, 100),
      order(GoldenType.formula, false, 15_000_000, 10, at: otherForgeStation),
    ]
    let domainOrders: [Order] = [
      order(GoldenType.tritanium, false, 3.9, 5_000_000, at: amarrStation),
      order(GoldenType.pyerite, false, 11.0, 5_000_000, at: amarrStation),
      order(GoldenType.mexallon, false, 58, 200_000, at: amarrStation),
      order(GoldenType.cadmium, false, 390, 10_000, at: amarrStation),
      order(GoldenType.ship, false, 3_200_000, 5, at: amarrStation),
      order(GoldenType.ship, true, 2_600_000, 3, at: amarrStation),
      order(GoldenType.module, false, 75_000, 50, at: amarrStation),
    ]
    return [theForge: forgeOrders, domain: domainOrders]
  }()

  private static let adjustedPrices: [Int64: Double] = [
    GoldenType.tritanium: 4,
    GoldenType.pyerite: 9,
    GoldenType.mexallon: 55,
    GoldenType.atmosphericGases: 45,
    GoldenType.cadmium: 380,
    GoldenType.reactionProduct: 800,
    GoldenType.component: 8_000,
    GoldenType.ship: 2_800_000,
    GoldenType.module: 60_000,
  ]

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = try #require(request.url)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let query = Dictionary(
      (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
      uniquingKeysWith: { first, _ in first }
    )
    let segments = url.path.split(separator: "/").map(String.init)
    let body: Any
    switch segments {
    case ["markets", "prices"]:
      body = Self.adjustedPrices.keys.sorted().map {
        ["type_id": $0, "adjusted_price": Self.adjustedPrices[$0]!, "average_price": Self.adjustedPrices[$0]!]
      }
    case ["industry", "systems"]:
      body = [
        [
          "solar_system_id": 30_000_142,
          "cost_indices": [
            ["activity": "manufacturing", "cost_index": 0.0412],
            ["activity": "reaction", "cost_index": 0.0213],
          ],
        ]
      ]
    case let path where path.count == 3 && path[0] == "markets" && path[2] == "orders":
      let regionID = Int64(path[1]) ?? 0
      let typeID = Int64(query["type_id"] ?? "")
      let side = query["order_type"] ?? "all"
      let issued = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))
      body = (Self.orders[regionID] ?? [])
        .filter { order in
          (typeID == nil || order.typeID == typeID)
            && (side == "all" || (side == "buy") == order.isBuy)
        }
        .map { order -> [String: Any] in
          [
            "duration": 90,
            "is_buy_order": order.isBuy,
            "issued": issued,
            "location_id": order.locationID,
            "min_volume": 1,
            "order_id": order.id,
            "price": order.price,
            "range": "station",
            "system_id": order.systemID,
            "type_id": order.typeID,
            "volume_remain": order.volume,
            "volume_total": order.volume,
          ]
        }
    default:
      return (Data("{\"error\":\"not found\"}".utf8), Self.response(url, status: 404))
    }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    return (data, Self.response(url, status: 200))
  }

  private static func response(_ url: URL, status: Int) -> HTTPURLResponse {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": "application/json",
        "Expires": formatter.string(from: Date().addingTimeInterval(3_600)),
        "Last-Modified": "Sun, 01 Nov 2026 12:00:00 GMT",
        "X-Pages": "1",
      ]
    )!
  }
}

// MARK: - Normalized golden master

/// Turns any value into deterministic JSON: struct fields by name, collection
/// order kept, dictionaries and sets sorted, UUIDs numbered by first
/// appearance (`uuid-1`, …) and dates replaced by `"<date>"`. Numbers are
/// compared with a relative tolerance of 1e-9, so a different summation order
/// of equal values cannot fail the comparison.
enum GoldenMaster {
  indirect enum Node {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case uuid(UUID)
    case date
    case array([Node])
    case object([(String, Node)])
    case dictionary([(Node, Node)])
    case set([Node])
  }

  /// Lists whose order carries no meaning and follows Swift's per-process
  /// hash order today: `stockAllocations` is mapped from a dictionary
  /// (`IndustryPlanner`, `state.stockUsed`). They are compared as sets.
  static let unorderedFields: Set<String> = ["stockAllocations"]

  static let referenceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("GoldenMaster", isDirectory: true)

  static func json(_ value: Any) -> String {
    var numbering: [UUID: Int] = [:]
    var output = ""
    write(node(value), numbering: &numbering, indent: "", into: &output)
    return output + "\n"
  }

  static func verify(
    _ value: Any,
    named name: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let actual = json(value)
    let url = referenceDirectory.appendingPathComponent("\(name).json")
    if ProcessInfo.processInfo.environment["EVE_NEXUS_RECORD_GOLDEN"] == "1" {
      try FileManager.default.createDirectory(
        at: referenceDirectory,
        withIntermediateDirectories: true
      )
      try Data(actual.utf8).write(to: url)
      Issue.record(
        "Recorded \(name).json; run again without EVE_NEXUS_RECORD_GOLDEN.",
        sourceLocation: sourceLocation
      )
      return
    }
    guard let reference = try? Data(contentsOf: url) else {
      Issue.record(
        "Missing golden master \(url.path); record it with EVE_NEXUS_RECORD_GOLDEN=1.",
        sourceLocation: sourceLocation
      )
      return
    }
    let expected = try JSONSerialization.jsonObject(
      with: reference,
      options: [.fragmentsAllowed]
    )
    let current = try JSONSerialization.jsonObject(
      with: Data(actual.utf8),
      options: [.fragmentsAllowed]
    )
    var differences: [String] = []
    compare(expected, current, path: name, into: &differences)
    if differences.isEmpty, reference != Data(actual.utf8) {
      // Equal within the tolerance, but not byte for byte: worth knowing
      // when an optimization changes a summation order.
      print("golden-master \(name): equal within tolerance, not byte-identical")
    }
    if !differences.isEmpty {
      let sha = SHA256.hash(data: Data(actual.utf8))
        .map { String(format: "%02x", $0) }.joined()
      Issue.record(
        Comment(
          rawValue: "\(differences.count) difference(s) from \(name).json "
            + "(current sha256 \(sha)):\n"
            + differences.prefix(25).joined(separator: "\n")
        ),
        sourceLocation: sourceLocation
      )
    }
  }

  // MARK: Building

  static func node(_ value: Any) -> Node {
    switch value {
    case let value as Bool: return .bool(value)
    case let value as Int: return .number(Double(value))
    case let value as Int64: return .number(Double(value))
    case let value as Int32: return .number(Double(value))
    case let value as Int16: return .number(Double(value))
    case let value as Int8: return .number(Double(value))
    case let value as UInt: return .number(Double(value))
    case let value as UInt64: return .number(Double(value))
    case let value as UInt32: return .number(Double(value))
    case let value as UInt16: return .number(Double(value))
    case let value as UInt8: return .number(Double(value))
    case let value as Double: return value.isFinite ? .number(value) : .string("\(value)")
    case let value as Float: return .number(Double(value))
    case let value as String: return .string(value)
    case let value as Substring: return .string(String(value))
    case let value as Character: return .string(String(value))
    case let value as UUID: return .uuid(value)
    case is Date: return .date
    case let value as URL: return .string(value.absoluteString)
    case let value as Decimal: return .string("\(value)")
    case let value as Data:
      let digest = SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
      return .string("data:\(value.count):\(digest)")
    default: break
    }
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .optional:
      return mirror.children.first.map { node($0.value) } ?? .null
    case .collection:
      return .array(mirror.children.map { node($0.value) })
    case .set:
      return .set(mirror.children.map { node($0.value) })
    case .dictionary:
      return .dictionary(
        mirror.children.map { entry in
          let pair = Array(Mirror(reflecting: entry.value).children)
          return (node(pair[0].value), node(pair[1].value))
        }
      )
    case .enum:
      guard let payload = mirror.children.first else {
        return .string("\(value)")
      }
      return .object([(payload.label ?? "case", node(payload.value))])
    case .tuple:
      return .array(mirror.children.map { node($0.value) })
    default:
      var fields: [(String, Node)] = []
      var current: Mirror? = mirror
      while let level = current {
        for child in level.children {
          let label = child.label ?? "_"
          var value = node(child.value)
          if unorderedFields.contains(label), case .array(let items) = value {
            value = .set(items)
          }
          fields.append((label, value))
        }
        current = level.superclassMirror
      }
      if fields.isEmpty && mirror.displayStyle == nil {
        return .string("\(value)")
      }
      return .object(fields)
    }
  }

  /// Sort key of a node with every UUID anonymized.
  private static func anonymous(_ node: Node) -> String {
    var numbering: [UUID: Int] = [:]
    var output = ""
    write(node, numbering: &numbering, indent: nil, anonymizeUUIDs: true, into: &output)
    return output
  }

  // MARK: Writing

  private static func write(
    _ node: Node,
    numbering: inout [UUID: Int],
    indent: String?,
    anonymizeUUIDs: Bool = false,
    into output: inout String
  ) {
    let next = indent.map { $0 + "  " }
    let newline = indent == nil ? "" : "\n"
    func uuidText(_ uuid: UUID) -> String {
      if anonymizeUUIDs { return "uuid" }
      if let number = numbering[uuid] { return "uuid-\(number)" }
      let number = numbering.count + 1
      numbering[uuid] = number
      return "uuid-\(number)"
    }
    func keyText(_ key: Node) -> String {
      switch key {
      case .string(let text): return text
      case .number(let number): return numberText(number)
      case .uuid(let uuid): return uuidText(uuid)
      case .bool(let flag): return flag ? "true" : "false"
      default:
        var text = ""
        write(key, numbering: &numbering, indent: nil, anonymizeUUIDs: anonymizeUUIDs, into: &text)
        return text
      }
    }
    func writeObject(_ fields: [(String, Node)]) {
      guard !fields.isEmpty else {
        output += "{}"
        return
      }
      output += "{" + newline
      for (index, field) in fields.enumerated() {
        output += (next ?? "") + quoted(field.0) + (indent == nil ? ":" : ": ")
        write(field.1, numbering: &numbering, indent: next, anonymizeUUIDs: anonymizeUUIDs, into: &output)
        output += (index == fields.count - 1 ? "" : ",") + newline
      }
      output += (indent ?? "") + "}"
    }
    func writeArray(_ items: [Node]) {
      guard !items.isEmpty else {
        output += "[]"
        return
      }
      output += "[" + newline
      for (index, item) in items.enumerated() {
        output += next ?? ""
        write(item, numbering: &numbering, indent: next, anonymizeUUIDs: anonymizeUUIDs, into: &output)
        output += (index == items.count - 1 ? "" : ",") + newline
      }
      output += (indent ?? "") + "]"
    }
    switch node {
    case .null: output += "null"
    case .bool(let flag): output += flag ? "true" : "false"
    case .number(let number): output += numberText(number)
    case .string(let text): output += quoted(text)
    case .uuid(let uuid): output += quoted(uuidText(uuid))
    case .date: output += quoted("<date>")
    case .array(let items): writeArray(items)
    case .set(let items):
      writeArray(items.sorted { anonymous($0) < anonymous($1) })
    case .object(let fields):
      // Struct fields keep a stable name order; equal labels cannot occur.
      writeObject(fields.sorted { $0.0 < $1.0 })
    case .dictionary(let entries):
      let sorted = entries.sorted {
        let left = (anonymous($0.0), anonymous($0.1))
        let right = (anonymous($1.0), anonymous($1.1))
        return left < right
      }
      // Keys are numbered in sorted order before their values are written.
      let keyed = sorted.map { (keyText($0.0), $0.1) }
      writeObject(keyed)
    }
  }

  private static func numberText(_ number: Double) -> String {
    if number == number.rounded(), abs(number) < 9_007_199_254_740_992 {
      return String(Int64(number))
    }
    return "\(number)"
  }

  private static func quoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case let control where control.value < 0x20:
        result += String(format: "\\u%04x", control.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }

  // MARK: Comparing

  private static func compare(
    _ expected: Any,
    _ actual: Any,
    path: String,
    into differences: inout [String]
  ) {
    switch (expected, actual) {
    case let (left as [String: Any], right as [String: Any]):
      for key in Set(left.keys).union(right.keys).sorted() {
        guard let leftValue = left[key] else {
          differences.append("\(path).\(key): added")
          continue
        }
        guard let rightValue = right[key] else {
          differences.append("\(path).\(key): removed")
          continue
        }
        compare(leftValue, rightValue, path: "\(path).\(key)", into: &differences)
      }
    case let (left as [Any], right as [Any]):
      if left.count != right.count {
        differences.append("\(path): \(left.count) → \(right.count) elements")
      }
      for index in 0..<min(left.count, right.count) {
        compare(left[index], right[index], path: "\(path)[\(index)]", into: &differences)
      }
    case let (left as NSNumber, right as NSNumber)
    where CFGetTypeID(left) != CFBooleanGetTypeID()
      && CFGetTypeID(right) != CFBooleanGetTypeID():
      let a = left.doubleValue
      let b = right.doubleValue
      let tolerance = max(1e-9, 1e-9 * max(abs(a), abs(b)))
      if abs(a - b) > tolerance {
        differences.append("\(path): \(left) → \(right)")
      }
    default:
      if "\(expected)" != "\(actual)" || type(of: expected) != type(of: actual) {
        differences.append("\(path): \(expected) → \(actual)")
      }
    }
  }
}
