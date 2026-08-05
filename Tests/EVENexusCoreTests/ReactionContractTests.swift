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
