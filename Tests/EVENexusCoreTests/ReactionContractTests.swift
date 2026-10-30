import Foundation
import Testing

@testable import EVENexusCore

@Suite("Reaction contract")
struct ReactionContractTests {
  @Test
  func reactionCandidateHasNoMEOrTEFields() {
    let definition = BlueprintDefinition(
      blueprintTypeID: 10,
      productTypeID: 11,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .reaction,
        durationSeconds: 180,
        materials: [BlueprintMaterial(typeID: 12, quantity: 100)],
        products: [BlueprintProduct(typeID: 11, quantity: 200, probability: nil)]
      ),
      source: SourceIdentity(provider: "fixture", version: "1")
    )
    let candidate = ReactionCandidate(
      recipe: definition,
      runs: 3,
      securityBand: .nullSecurity,
      readiness: .needsReview
    )

    #expect(candidate.recipe.activity.kind == .reaction)
    #expect(candidate.readiness == .needsReview)
    #expect(candidate.runs == 3)
  }

  @Test
  func analyzesMaterialDepthFacilityCostValueAndMakeOrBuy() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let definition = reactionDefinition(source: source)
    let snapshot = marketSnapshot(
      source: source,
      orders: [
        marketOrder(id: 1, typeID: 12, side: .sell, price: 2),
        marketOrder(id: 2, typeID: 11, side: .sell, price: 5),
        marketOrder(id: 3, typeID: 11, side: .buy, price: 4),
      ]
    )
    let facility = ReactionFacilityCostContext(
      name: "Fixture Tatara",
      materialMultiplier: 0.9,
      timeMultiplier: 0.8,
      jobCostMultiplier: 1,
      facilityTaxRate: 0,
      systemCostIndex: 0.1,
      sccSurchargeRate: 0.04,
      alphaSurchargeRate: 0,
      ruleVersion: "fixture-v1"
    )

    let analysis = try ReactionProfitabilityAnalyzer.analyze(
      definitions: [definition],
      typeNames: [11: "Reaction Product", 12: "Reaction Input"],
      classifications: [
        11: IndustryItemClassification(
          categoryName: "Material",
          groupName: "Composite Reaction",
          manufacturingCategory: .module
        )
      ],
      runs: 100,
      tradeHub: .jita,
      market: snapshot,
      adjustedPrices: [
        12: AdjustedPrice(typeID: 12, adjustedPrice: 1, averagePrice: nil)
      ],
      facility: facility,
      logistics: logisticsContext(isEnabled: false)
    )

    let row = try #require(analysis.rows.first)
    #expect(analysis.basis == .configuredFacility)
    #expect(row.inputs.first?.quantity == 900)
    #expect(row.outputs.first?.quantity == 20_000)
    #expect(row.materialCost == 1_800)
    #expect(row.inputLogisticsCost == 0)
    #expect(row.installationCost == 140)
    #expect(row.evaluatedCost == 1_940)
    #expect(row.outputBuyCost == 100_000)
    #expect(row.outputPurchaseLogisticsCost == 0)
    #expect(row.outputPurchaseTotalCost == 100_000)
    #expect(row.immediateSaleRevenue == 80_000)
    #expect(row.makeOrBuySavings == 98_060)
    #expect(row.valueCreation == 98_060)
    #expect(row.immediateSaleSpread == 78_060)
    #expect(row.valueStatus == .positive)
    #expect(row.makeIsCheaperThanBuy == true)
    #expect(row.durationSeconds == 14_400)
    #expect(row.maximumRunsPerJob == 18_000)
    #expect(row.requiredJobCount == 1)
  }

  @Test
  func logisticsIsAddedToBothReactionAndDirectPurchaseCosts() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let analysis = try ReactionProfitabilityAnalyzer.analyze(
      definitions: [reactionDefinition(source: source)],
      typeNames: [11: "Reaction Product", 12: "Reaction Input"],
      classifications: [:],
      runs: 100,
      tradeHub: .jita,
      market: marketSnapshot(
        source: source,
        orders: [
          marketOrder(id: 1, typeID: 12, side: .sell, price: 2),
          marketOrder(id: 2, typeID: 11, side: .sell, price: 5),
        ]
      ),
      adjustedPrices: [
        12: AdjustedPrice(typeID: 12, adjustedPrice: 1, averagePrice: nil)
      ],
      facility: ReactionFacilityCostContext(
        name: "Fixture Tatara",
        materialMultiplier: 0.9,
        timeMultiplier: 0.8,
        jobCostMultiplier: 1,
        facilityTaxRate: 0,
        systemCostIndex: 0.1,
        sccSurchargeRate: 0.04,
        alphaSurchargeRate: 0,
        ruleVersion: "fixture-v1"
      ),
      logistics: logisticsContext(isEnabled: true)
    )

    let row = try #require(analysis.rows.first)
    #expect(row.inputLogisticsCost == 1_000_000)
    #expect(row.evaluatedCost == 1_001_940)
    #expect(row.outputBuyCost == 100_000)
    #expect(row.outputPurchaseLogisticsCost == 2_000_000)
    #expect(row.outputPurchaseTotalCost == 2_100_000)
    #expect(row.makeOrBuySavings == 1_098_060)
    #expect(row.valueCreation == 1_098_060)
  }

  @Test
  func missingPackagedVolumeMakesLogisticsAndComparisonUnavailable() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let analysis = try ReactionProfitabilityAnalyzer.analyze(
      definitions: [reactionDefinition(source: source)],
      typeNames: [11: "Reaction Product", 12: "Reaction Input"],
      classifications: [:],
      runs: 100,
      tradeHub: .jita,
      market: marketSnapshot(
        source: source,
        orders: [
          marketOrder(id: 1, typeID: 12, side: .sell, price: 2),
          marketOrder(id: 2, typeID: 11, side: .sell, price: 5),
        ]
      ),
      adjustedPrices: [:],
      facility: nil,
      logistics: ReactionLogisticsCostContext(
        configuration: LogisticsConfiguration(
          isEnabled: true,
          includeInboundMaterials: true,
          productionLocationName: "Fixture Tatara",
          homeTradeHub: .jita,
          iskPerCubicMeter: 1_000
        ),
        origin: .jita,
        destinationName: "Fixture Tatara",
        destinationLocationID: 9_999,
        packagedVolumes: [11: 0.1]
      )
    )

    let row = try #require(analysis.rows.first)
    #expect(row.materialCost == 2_000)
    #expect(row.inputLogisticsCost == nil)
    #expect(row.evaluatedCost == nil)
    #expect(row.outputPurchaseTotalCost == 2_100_000)
    #expect(row.valueCreation == nil)
    #expect(
      row.warnings.contains {
        $0.code == "logistics.missing-packaged-volume"
          && $0.severity == .blocking
      }
    )
  }

  @Test
  func derivesPerFormulaRunLimitFromThirtyDayJobDuration() {
    #expect(
      ReactionJobRules.maximumRunsPerJob(
        baseDurationSeconds: 10_800,
        timeMultiplier: 0.4352
      ) == 551
    )
    #expect(
      ReactionJobRules.maximumRunsPerJob(
        baseDurationSeconds: 21_600,
        timeMultiplier: 0.4352
      ) == 275
    )
    #expect(
      ReactionJobRules.maximumRunsPerJob(
        baseDurationSeconds: 360,
        timeMultiplier: 1
      ) == 7_200
    )
    #expect(
      ReactionJobRules.maximumRunsPerJob(
        baseDurationSeconds: ReactionJobRules.maximumJobDurationSeconds + 1,
        timeMultiplier: 1
      ) == 1
    )
  }

  @Test
  func lowestValueCreationSortShowsLossesFirstAndUnavailableLast() {
    let rows = [
      analysisRow(id: 1, name: "Profit", valueCreation: 50),
      analysisRow(id: 2, name: "Large loss", valueCreation: -100),
      analysisRow(id: 3, name: "Small loss", valueCreation: -20),
      analysisRow(id: 4, name: "Unavailable", valueCreation: nil),
    ]

    let sorted = ReactionAnalysisSortOrder.valueCreationAscending.sorted(rows)

    #expect(
      sorted.map(\.productName) == [
        "Large loss", "Small loss", "Profit", "Unavailable",
      ])
  }

  @Test
  func missingMarketDepthRemainsUnavailableInsteadOfZero() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let analysis = try ReactionProfitabilityAnalyzer.analyze(
      definitions: [reactionDefinition(source: source)],
      typeNames: [11: "Reaction Product", 12: "Reaction Input"],
      classifications: [:],
      runs: 100,
      tradeHub: .jita,
      market: marketSnapshot(source: source, orders: []),
      adjustedPrices: [:],
      facility: nil,
      logistics: logisticsContext(isEnabled: false)
    )

    let row = try #require(analysis.rows.first)
    #expect(analysis.basis == .materialOnlyBaseline)
    #expect(row.materialCost == nil)
    #expect(row.installationCost == nil)
    #expect(row.evaluatedCost == nil)
    #expect(row.valueCreation == nil)
    #expect(row.valueStatus == .unavailable)
    #expect(row.warnings.contains { $0.severity == .blocking })
  }

  // Chain fixture: product 30 needs 10 x type 31 per run; 31 comes from a
  // reaction needing 2 x raw type 32 per run. No multipliers, no job costs.
  private func chainDefinition(
    blueprint: Int64,
    product: Int64,
    material: Int64,
    quantity: Int64,
    kind: BlueprintActivityDefinition.Kind = .reaction,
    source: SourceIdentity
  ) -> BlueprintDefinition {
    BlueprintDefinition(
      blueprintTypeID: blueprint,
      productTypeID: product,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: kind,
        durationSeconds: 3_600,
        materials: [BlueprintMaterial(typeID: material, quantity: quantity)],
        products: [BlueprintProduct(typeID: product, quantity: 1, probability: nil)]
      ),
      source: source
    )
  }

  private func chainAnalysis(
    orders: [MarketOrder],
    source: SourceIdentity,
    manufacturing: [BlueprintDefinition] = [],
    blacklist: ProductionBlacklistConfiguration = ProductionBlacklistConfiguration()
  ) throws -> ReactionAnalysisRow {
    let analysis = try ReactionProfitabilityAnalyzer.analyze(
      definitions: [
        chainDefinition(blueprint: 40, product: 30, material: 31, quantity: 10, source: source),
        chainDefinition(blueprint: 41, product: 31, material: 32, quantity: 2, source: source),
      ],
      typeNames: [30: "Final", 31: "Intermediate", 32: "Raw"],
      classifications: [:],
      runs: 1,
      tradeHub: .jita,
      market: marketSnapshot(source: source, orders: orders),
      adjustedPrices: [
        31: AdjustedPrice(typeID: 31, adjustedPrice: 0, averagePrice: nil),
        32: AdjustedPrice(typeID: 32, adjustedPrice: 0, averagePrice: nil),
      ],
      facility: ReactionFacilityCostContext(
        name: "Fixture Tatara",
        materialMultiplier: 1,
        timeMultiplier: 1,
        jobCostMultiplier: 1,
        facilityTaxRate: 0,
        systemCostIndex: 0,
        sccSurchargeRate: 0,
        alphaSurchargeRate: 0,
        ruleVersion: "fixture-v1"
      ),
      logistics: logisticsContext(isEnabled: false),
      supplyChain: ReactionSupplyChainContext(
        manufacturing: manufacturing,
        facilities: [:],
        intermediateMaterialEfficiency: 10,
        blacklist: blacklist
      )
    )
    return try #require(analysis.rows.first { $0.productTypeID == 30 })
  }

  @Test
  func cheapestChainBuildsFromRawMaterialsAndDrivesHeadlineValues() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let row = try chainAnalysis(
      orders: [
        marketOrder(id: 1, typeID: 30, side: .sell, price: 100),
        marketOrder(id: 2, typeID: 31, side: .sell, price: 8),
        marketOrder(id: 3, typeID: 32, side: .sell, price: 1),
      ],
      source: source
    )

    let chain = try #require(row.supplyChain)
    #expect(chain.directPurchaseTotal == 100)
    #expect(chain.intermediatesBought.totalCost == 80)
    #expect(chain.fullChain.totalCost == 20)
    #expect(chain.fullChain.purchases.map(\.typeID) == [32])
    #expect(chain.fullChain.purchases.first?.quantity == 20)
    #expect(chain.fullChain.builtJobCount == 1)
    let cheapest = try #require(chain.cheapest)
    #expect(cheapest.totalCost == 20)
    #expect(cheapest.treeLines.map(\.depth) == [0, 1])
    #expect(cheapest.treeLines.map(\.node.isBuilt) == [true, false])
    #expect(chain.savingsAgainstDirectPurchase(cheapest) == 80)
    #expect(row.evaluatedCost == 20)
    #expect(row.makeOrBuySavings == 80)
    #expect(row.valueCreation == 80)
    #expect(row.valueCreationMargin == 4)
    #expect(row.inputs.map(\.typeID) == [31])
    #expect(row.outputPurchaseTotalCost == 100)
  }

  @Test
  func dearerRawMaterialsKeepBoughtIntermediatesAsCheapest() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let row = try chainAnalysis(
      orders: [
        marketOrder(id: 1, typeID: 30, side: .sell, price: 100),
        marketOrder(id: 2, typeID: 31, side: .sell, price: 2),
        marketOrder(id: 3, typeID: 32, side: .sell, price: 5),
      ],
      source: source
    )

    let chain = try #require(row.supplyChain)
    #expect(chain.fullChain.totalCost == 100)
    #expect(chain.cheapest?.totalCost == 20)
    #expect(chain.cheapest?.builtJobCount == 0)
    #expect(row.valueCreation == 80)
  }

  @Test
  func missingIntermediateMarketUsesCompleteChainAndMissingRawStaysUnavailable() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let built = try chainAnalysis(
      orders: [
        marketOrder(id: 1, typeID: 30, side: .sell, price: 100),
        marketOrder(id: 3, typeID: 32, side: .sell, price: 1),
      ],
      source: source
    )
    #expect(built.supplyChain?.intermediatesBought.totalCost == nil)
    #expect(built.supplyChain?.cheapest?.totalCost == 20)
    #expect(built.valueCreation == 80)

    let missing = try chainAnalysis(
      orders: [marketOrder(id: 1, typeID: 30, side: .sell, price: 100)],
      source: source
    )
    #expect(missing.supplyChain?.cheapest == nil)
    #expect(missing.supplyChain?.fullChain.totalCost == nil)
    #expect(missing.valueCreation == nil)
    #expect(missing.valueStatus == .unavailable)
  }

  @Test
  func requiredTypesFollowManufacturedInputsToRawMaterials() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let ids = ReactionSupplyChainContext.requiredTypeIDs(
      reactions: [
        chainDefinition(blueprint: 40, product: 30, material: 31, quantity: 1, source: source)
      ],
      manufacturing: [
        chainDefinition(
          blueprint: 41,
          product: 31,
          material: 32,
          quantity: 1,
          kind: .manufacturing,
          source: source
        ),
        chainDefinition(
          blueprint: 42,
          product: 99,
          material: 98,
          quantity: 1,
          kind: .manufacturing,
          source: source
        ),
      ]
    )
    #expect(ids == [30, 31, 32])
  }

  private func reactionDefinition(source: SourceIdentity) -> BlueprintDefinition {
    BlueprintDefinition(
      blueprintTypeID: 10,
      productTypeID: 11,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .reaction,
        durationSeconds: 180,
        materials: [BlueprintMaterial(typeID: 12, quantity: 10)],
        products: [
          BlueprintProduct(typeID: 11, quantity: 200, probability: nil)
        ]
      ),
      source: source
    )
  }

  private func marketSnapshot(
    source: SourceIdentity,
    orders: [MarketOrder]
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: MarketTradeHub.jita.regionID,
      locationID: MarketTradeHub.jita.stationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: Dictionary(grouping: orders, by: \.typeID),
      source: source
    )
  }

  private func analysisRow(
    id: Int64,
    name: String,
    valueCreation: Double?
  ) -> ReactionAnalysisRow {
    ReactionAnalysisRow(
      blueprintTypeID: id,
      productTypeID: id + 100,
      productName: name,
      categoryName: "Fixture",
      groupName: "Fixture",
      runs: 100,
      inputs: [],
      outputs: [],
      materialCost: 100,
      inputLogisticsCost: 0,
      installationCost: nil,
      evaluatedCost: 100,
      outputBuyCost: valueCreation.map { 100 + $0 },
      outputPurchaseLogisticsCost: 0,
      outputPurchaseTotalCost: valueCreation.map { 100 + $0 },
      immediateSaleRevenue: nil,
      makeOrBuySavings: valueCreation,
      valueCreation: valueCreation,
      valueCreationMargin: valueCreation.map { $0 / 100 },
      durationSeconds: 1_000,
      maximumRunsPerJob: 500,
      basis: .materialOnlyBaseline,
      warnings: []
    )
  }

  private func logisticsContext(
    isEnabled: Bool
  ) -> ReactionLogisticsCostContext {
    ReactionLogisticsCostContext(
      configuration: LogisticsConfiguration(
        isEnabled: isEnabled,
        includeInboundMaterials: true,
        productionLocationName: "Fixture Tatara",
        homeTradeHub: .jita,
        iskPerCubicMeter: isEnabled ? 1_000 : nil
      ),
      origin: .jita,
      destinationName: "Fixture Tatara",
      destinationLocationID: 9_999,
      packagedVolumes: [11: 0.1, 12: 1]
    )
  }

  private func marketOrder(
    id: Int64,
    typeID: Int64,
    side: MarketOrderSide,
    price: Double
  ) -> MarketOrder {
    MarketOrder(
      id: id,
      typeID: typeID,
      locationID: MarketTradeHub.jita.stationID,
      systemID: MarketTradeHub.jita.systemID,
      side: side,
      price: price,
      volumeRemaining: 1_000_000,
      minimumVolume: 1,
      issued: .now
    )
  }
}
