import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry planner query efficiency")
struct IndustryPlannerPerformanceTests {
  @Test
  func preparedMarketBookMatchesQuotesAndRemovesRepeatedSorting() {
    let snapshot = Self.marketSnapshot(typeCount: 180, ordersPerType: 320)
    let clock = ContinuousClock()

    let baselineElapsed = clock.measure {
      for _ in 0..<4 {
        for typeID in 1...180 {
          _ = MarketPriceEngine.quote(
            typeID: Int64(typeID),
            quantity: 2_500,
            scenario: .materialBuy,
            snapshot: snapshot
          )
        }
      }
    }
    let preparationStart = clock.now
    let prepared = PreparedMarketOrderBook(snapshot: snapshot)
    let preparationElapsed = preparationStart.duration(to: clock.now)
    let preparedElapsed = clock.measure {
      for _ in 0..<4 {
        for typeID in 1...180 {
          _ = prepared.quote(
            typeID: Int64(typeID),
            quantity: 2_500,
            scenario: .materialBuy
          )
        }
      }
    }

    for typeID in [1, 45, 180] {
      for scenario in PriceScenario.allCases {
        let baseline = MarketPriceEngine.quote(
          typeID: Int64(typeID),
          quantity: 2_500,
          scenario: scenario,
          snapshot: snapshot,
          salesTaxRate: 0.04,
          brokerFeeRate: 0.03
        )
        let optimized = prepared.quote(
          typeID: Int64(typeID),
          quantity: 2_500,
          scenario: scenario,
          salesTaxRate: 0.04,
          brokerFeeRate: 0.03
        )
        #expect(optimized.typeID == baseline.typeID)
        #expect(optimized.quantity == baseline.quantity)
        #expect(optimized.scenario == baseline.scenario)
        #expect(optimized.total == baseline.total)
        #expect(optimized.weightedUnitPrice == baseline.weightedUnitPrice)
        #expect(optimized.filledQuantity == baseline.filledQuantity)
        #expect(optimized.warnings.count == baseline.warnings.count)
        for (optimizedWarning, baselineWarning) in zip(
          optimized.warnings,
          baseline.warnings
        ) {
          #expect(optimizedWarning.code == baselineWarning.code)
          #expect(optimizedWarning.message == baselineWarning.message)
          #expect(optimizedWarning.severity == baselineWarning.severity)
          #expect(optimizedWarning.source == baselineWarning.source)
        }
      }
    }

    print(
      "planner-market-quote baseline=\(baselineElapsed) preparation=\(preparationElapsed) prepared=\(preparedElapsed)"
    )
  }

  @Test
  func marketDiscoveryVisitsSharedProductionBranchesOnce() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let definitions: [Int64: BlueprintDefinition] = [
      1: Self.definition(
        blueprintID: 101,
        productID: 1,
        materials: [2, 3],
        source: source
      ),
      2: Self.definition(
        blueprintID: 102,
        productID: 2,
        materials: [4],
        source: source
      ),
      3: Self.definition(
        blueprintID: 103,
        productID: 3,
        materials: [4],
        source: source
      ),
    ]
    let catalog = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      definitions: definitions
    )

    let result = try await IndustryPlanner().requiredMarketTypeIDs(
      input: "Product 1 10 20",
      catalog: catalog
    )

    #expect(result == [1, 2, 3, 4])
    #expect(await catalog.definitionCallCounts() == [1: 1, 2: 1, 3: 1, 4: 1])
  }

  @Test
  func preparedInputReusesResolvedGraphDuringPlanCalculation() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let base = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      typeNames: [1: "Product"],
      definitions: [
        1: Self.definition(
          blueprintID: 101,
          productID: 1,
          materials: [],
          source: source
        )
      ]
    )
    let catalog = MemoizedIndustryCatalog(base: base)
    let planner = IndustryPlanner()
    let preparation = try await planner.prepare(
      input: "Product 1 10 20\nProduct 2 10 20",
      catalog: catalog
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        state: .fresh,
        ordersByType: [:],
        source: source
      ),
      adjustedPrices: [:],
      systemIndices: [],
      sdeBuild: 1
    )

    let plan = try await planner.plan(
      preparation: preparation,
      context: context
    )

    #expect(plan.requests.count == 2)
    #expect(preparation.marketTypeIDs == [1])
    #expect(await base.typeIDCallCount(named: "Product") == 1)
    #expect(await base.definitionCallCount(id: 1) == 1)
    #expect(await base.typeNameCallCount(id: 1) == 0)
    #expect(await base.classificationCallCount(id: 1) == 0)
    #expect(await base.typeNamesBatchCallCount() == 1)
    #expect(await base.classificationsBatchCallCount() == 1)
  }

  @Test
  func secondScenarioReusesMatchingMakeOrBuyAnalysisFromBaseline() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let base = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      typeNames: [1: "Product", 2: "Intermediate", 3: "Raw"],
      definitions: [
        1: Self.definition(
          blueprintID: 101,
          productID: 1,
          materials: [2],
          source: source
        ),
        2: Self.definition(
          blueprintID: 102,
          productID: 2,
          materials: [3],
          source: source
        ),
      ]
    )
    let catalog = MemoizedIndustryCatalog(base: base)
    let planner = IndustryPlanner()
    let preparation = try await planner.prepare(
      input: "Product 1 10 20",
      catalog: catalog
    )
    let market = Self.marketSnapshot(typeCount: 3, ordersPerType: 8)
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: catalog,
      market: market,
      adjustedPrices: [
        3: AdjustedPrice(typeID: 3, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [],
      sdeBuild: 1
    )

    let baseline = try await planner.plan(
      preparation: preparation,
      context: context
    )
    let baselineAnalysis = try #require(
      baseline.materials.first { $0.typeID == 2 }?.makeOrBuyAnalysis
    )
    let repeated = try await planner.plan(
      preparation: preparation,
      context: context,
      reusingMakeOrBuyAnalysesFrom: baseline
    )
    let repeatedAnalysis = try #require(
      repeated.materials.first { $0.typeID == 2 }?.makeOrBuyAnalysis
    )

    #expect(repeatedAnalysis.purchaseQuote.id == baselineAnalysis.purchaseQuote.id)

    let changedMarketContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: catalog,
      market: Self.marketSnapshot(typeCount: 3, ordersPerType: 8),
      adjustedPrices: [
        3: AdjustedPrice(typeID: 3, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [],
      sdeBuild: 1
    )
    let refreshed = try await planner.plan(
      preparation: preparation,
      context: changedMarketContext,
      reusingMakeOrBuyAnalysesFrom: baseline
    )
    let refreshedAnalysis = try #require(
      refreshed.materials.first { $0.typeID == 2 }?.makeOrBuyAnalysis
    )
    #expect(refreshedAnalysis.purchaseQuote.id != baselineAnalysis.purchaseQuote.id)
  }

  @Test
  func memoizedCatalogCachesPresentAndMissingResults() async throws {
    let base = CountingIndustryCatalog(
      typeIDs: ["Product": 1],
      typeNames: [1: "Product"]
    )
    let catalog = MemoizedIndustryCatalog(base: base)

    #expect(try await catalog.typeID(named: "Product") == 1)
    #expect(try await catalog.typeID(named: "Product") == 1)
    #expect(try await catalog.typeName(id: 1) == "Product")
    #expect(try await catalog.typeName(id: 1) == "Product")
    #expect(try await catalog.productionDefinition(productTypeID: 999) == nil)
    #expect(try await catalog.productionDefinition(productTypeID: 999) == nil)

    #expect(await base.typeIDCallCount(named: "Product") == 1)
    #expect(await base.typeNameCallCount(id: 1) == 1)
    #expect(await base.definitionCallCount(id: 999) == 1)
  }

  @Test
  func memoizedCatalogHotCacheAvoidsRepeatedBaseQueries() async throws {
    let base = CountingIndustryCatalog(typeNames: [1: "Product"])
    let catalog = MemoizedIndustryCatalog(base: base)
    #expect(try await catalog.typeName(id: 1) == "Product")
    let clock = ContinuousClock()

    let elapsed = try await clock.measure {
      for _ in 0..<20_000 {
        _ = try await catalog.typeName(id: 1)
      }
    }

    #expect(await base.typeNameCallCount(id: 1) == 1)
    print("planner-catalog-hot-cache=\(elapsed)")
  }

  private static func definition(
    blueprintID: Int64,
    productID: Int64,
    materials: [Int64],
    source: SourceIdentity
  ) -> BlueprintDefinition {
    BlueprintDefinition(
      blueprintTypeID: blueprintID,
      productTypeID: productID,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: materials.map {
          BlueprintMaterial(typeID: $0, quantity: 1)
        },
        products: [
          BlueprintProduct(
            typeID: productID,
            quantity: 1,
            probability: nil
          )
        ]
      ),
      source: source
    )
  }

  private static func marketSnapshot(
    typeCount: Int,
    ordersPerType: Int
  ) -> MarketOrderSnapshot {
    let ordersByType = Dictionary(
      uniqueKeysWithValues: (1...typeCount).map { rawTypeID in
        let typeID = Int64(rawTypeID)
        let orders = (0..<ordersPerType).map { index in
          MarketOrder(
            id: typeID * 10_000 + Int64(index),
            typeID: typeID,
            locationID: 60_003_760,
            systemID: 30_000_142,
            side: index.isMultiple(of: 5) ? .buy : .sell,
            price: Double(ordersPerType - index) + Double(typeID) / 1_000,
            volumeRemaining: 100,
            minimumVolume: 1,
            issued: Date(timeIntervalSince1970: Double(index))
          )
        }
        return (typeID, orders)
      }
    )
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: 10_000_002,
      locationID: 60_003_760,
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
      state: .fresh,
      ordersByType: ordersByType,
      source: SourceIdentity(provider: "fixture", version: "1")
    )
  }
}

private actor CountingIndustryCatalog: IndustryCatalogQuerying {
  private let typeIDs: [String: Int64]
  private let typeNames: [Int64: String]
  private let definitions: [Int64: BlueprintDefinition]
  private var typeIDCalls: [String: Int] = [:]
  private var typeNameCalls: [Int64: Int] = [:]
  private var definitionCalls: [Int64: Int] = [:]
  private var classificationCalls: [Int64: Int] = [:]
  private var typeNamesBatchCalls = 0
  private var classificationsBatchCalls = 0

  init(
    typeIDs: [String: Int64] = [:],
    typeNames: [Int64: String] = [:],
    definitions: [Int64: BlueprintDefinition] = [:]
  ) {
    self.typeIDs = typeIDs
    self.typeNames = typeNames
    self.definitions = definitions
  }

  func typeID(named name: String) async throws -> Int64? {
    typeIDCalls[name, default: 0] += 1
    return typeIDs[name]
  }

  func typeName(id: Int64) async throws -> String? {
    typeNameCalls[id, default: 0] += 1
    return typeNames[id]
  }

  func typeNames(ids: Set<Int64>) async throws -> [Int64: String] {
    typeNamesBatchCalls += 1
    return Dictionary(
      uniqueKeysWithValues: ids.compactMap { typeID in
        typeNames[typeID].map { (typeID, $0) }
      }
    )
  }

  func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    definitionCalls[productTypeID, default: 0] += 1
    return definitions[productTypeID]
  }

  func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    classificationCalls[productTypeID, default: 0] += 1
    return nil
  }

  func industryClassifications(typeIDs: Set<Int64>) async throws
    -> [Int64: IndustryItemClassification]
  {
    classificationsBatchCalls += 1
    return [:]
  }

  func packagedVolume(typeID: Int64) async throws -> Double? {
    nil
  }

  func definitionCallCounts() -> [Int64: Int] {
    definitionCalls
  }

  func definitionCallCount(id: Int64) -> Int {
    definitionCalls[id, default: 0]
  }

  func typeIDCallCount(named name: String) -> Int {
    typeIDCalls[name, default: 0]
  }

  func typeNameCallCount(id: Int64) -> Int {
    typeNameCalls[id, default: 0]
  }

  func classificationCallCount(id: Int64) -> Int {
    classificationCalls[id, default: 0]
  }

  func typeNamesBatchCallCount() -> Int {
    typeNamesBatchCalls
  }

  func classificationsBatchCallCount() -> Int {
    classificationsBatchCalls
  }
}
