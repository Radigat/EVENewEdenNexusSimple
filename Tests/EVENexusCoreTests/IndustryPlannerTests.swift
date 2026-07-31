import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry planner")
struct IndustryPlannerTests {
  @Test
  func buildsIntermediateAndBuysRawMaterials() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let component = BlueprintDefinition(
      blueprintTypeID: 101,
      productTypeID: 2,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 3, quantity: 4)],
        products: [BlueprintProduct(typeID: 2, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let ship = BlueprintDefinition(
      blueprintTypeID: 100,
      productTypeID: 1,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 100,
        materials: [BlueprintMaterial(typeID: 2, quantity: 2)],
        products: [BlueprintProduct(typeID: 1, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [1: "Ship", 2: "Component", 3: "Mineral"],
      definitions: [1: ship, 2: component],
      classifications: [
        2: IndustryItemClassification(
          categoryName: "Commodity",
          groupName: "Construction Components",
          manufacturingCategory: .module
        ),
        3: IndustryItemClassification(
          categoryName: "Material",
          groupName: "Mineral",
          manufacturingCategory: .module
        ),
      ]
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        1: [
          makeOrder(typeID: 1, side: .buy, price: 1000),
          makeOrder(typeID: 1, side: .sell, price: 1200),
        ],
        3: [makeOrder(typeID: 3, side: .sell, price: 5)],
      ],
      source: source
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: catalog,
      market: market,
      adjustedPrices: [
        2: AdjustedPrice(typeID: 2, adjustedPrice: 10, averagePrice: 10),
        3: AdjustedPrice(typeID: 3, adjustedPrice: 2, averagePrice: 2),
      ],
      systemIndices: [],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Ship 1 10 20",
      context: context
    )

    #expect(plan.nodes.contains { $0.typeID == 2 && $0.action == .produce })
    #expect(plan.materials.contains { $0.typeID == 3 && $0.toBuy > 0 })
    let intermediate = try #require(
      plan.materials.first { $0.typeID == 2 }
    )
    let rawMaterial = try #require(
      plan.materials.first { $0.typeID == 3 }
    )
    #expect(intermediate.isProducedMaterial)
    #expect(intermediate.productionActivity == .manufacturing)
    #expect(intermediate.sourceGroup == "Construction Components")
    #expect(!rawMaterial.isProducedMaterial)
    #expect(rawMaterial.productionActivity == nil)
    #expect(rawMaterial.sourceCategory == "Material")
    #expect(rawMaterial.sourceGroup == "Mineral")
    #expect(plan.provenance.sdeBuild == 1)
    #expect(plan.installationCost == nil)
    #expect(plan.immediateSale.profit == nil)
    #expect(
      plan.warnings.contains {
        $0.code == "industry.missing-system-index"
          && $0.severity == .blocking
      }
    )
  }

  @Test
  func convertsWantToRunsAndAppliesBlueprintAndFacilityEfficiencies()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let batch = BlueprintDefinition(
      blueprintTypeID: 200,
      productTypeID: 10,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 60,
        materials: [BlueprintMaterial(typeID: 11, quantity: 4)],
        products: [
          BlueprintProduct(typeID: 10, quantity: 100, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [10: "Batch Product", 11: "Raw Material"],
      definitions: [10: batch]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: ProductionBasis(
        structures: [
          ConfiguredIndustryStructure(
            name: "Fixture Station",
            kind: .custom,
            securityBand: .highSecurity,
            structureMaterialBonusPercent: 10,
            structureTimeBonusPercent: 50,
            source: .manual
          )
        ]
      ),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          10: [
            makeOrder(typeID: 10, side: .buy, price: 10),
            makeOrder(typeID: 10, side: .sell, price: 12),
          ],
          11: [makeOrder(typeID: 11, side: .sell, price: 1)],
        ],
        source: source
      ),
      adjustedPrices: [
        11: AdjustedPrice(typeID: 11, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0.01
        )
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Batch Product 250 10 20",
      context: context
    )

    let job = try #require(
      plan.nodes.first { $0.typeID == 10 && $0.action == .produce }
    )
    let rawMaterial = try #require(
      plan.materials.first { $0.typeID == 11 }
    )
    #expect(job.runs == 3)
    #expect(job.requiredQuantity == 300)
    #expect(job.materialEfficiency == 10)
    #expect(job.timeEfficiency == 20)
    #expect(job.facilityName == "Fixture Station")
    #expect(rawMaterial.required == 10)
    #expect(rawMaterial.toBuy == 10)
    #expect(plan.totalJobSeconds == 72)
    #expect(plan.journalMetrics.requestedUnits == 250)
    #expect(plan.journalMetrics.purchasedUnits == 10)
    #expect(plan.journalMetrics.stockUnits == 0)
    #expect(plan.journalMetrics.intermediateUnits == 0)
    #expect(plan.journalMetrics.totalCost != nil)
    #expect(
      plan.journalMetrics.totalCost
        == plan.materialCost! + plan.installationCost!
    )
  }

  @Test
  func reportsBlacklistedPurchaseOnlyOnceAcrossProductionSteps() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let firstProduct = BlueprintDefinition(
      blueprintTypeID: 301,
      productTypeID: 31,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 33, quantity: 2)],
        products: [
          BlueprintProduct(typeID: 31, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let secondProduct = BlueprintDefinition(
      blueprintTypeID: 302,
      productTypeID: 32,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 33, quantity: 3)],
        products: [
          BlueprintProduct(typeID: 32, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [
        31: "First Product",
        32: "Second Product",
        33: "Helium Fuel Block",
      ],
      definitions: [
        31: firstProduct,
        32: secondProduct,
      ]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: ProductionBasis(
        blacklist: ProductionBlacklistConfiguration(
          typeNames: ["Helium Fuel Block"]
        )
      ),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          31: [
            makeOrder(typeID: 31, side: .buy, price: 100),
            makeOrder(typeID: 31, side: .sell, price: 120),
          ],
          32: [
            makeOrder(typeID: 32, side: .buy, price: 100),
            makeOrder(typeID: 32, side: .sell, price: 120),
          ],
          33: [makeOrder(typeID: 33, side: .sell, price: 10)],
        ],
        source: source
      ),
      adjustedPrices: [
        33: AdjustedPrice(typeID: 33, adjustedPrice: 5, averagePrice: 5)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0.01
        )
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "First Product 1 10 20\nSecond Product 1 10 20",
      context: context
    )

    let blacklistWarnings = plan.warnings.filter {
      $0.code == "industry.production-blacklist"
    }
    #expect(blacklistWarnings.count == 1)
    #expect(blacklistWarnings.first?.message == "Helium Fuel Block is bought.")
    #expect(
      plan.materials.first { $0.typeID == 33 }?.toBuy == 5
    )
  }

  @Test
  func includesRoundedLogisticsAndSeparatesEveryFee() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 401,
      productTypeID: 41,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 42, quantity: 10)],
        products: [
          BlueprintProduct(typeID: 41, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [41: "Finished Product", 42: "Purchased Material"],
      definitions: [41: product],
      packagedVolumes: [41: 100, 42: 20]
    )
    let basis = ProductionBasis(
      marketTaxes: MarketTaxConfiguration(
        traderCharacterID: 1,
        salesTaxRate: 0.05,
        brokerFeeRate: 0.01,
        calculation: feeCalculation(source: source)
      ),
      logistics: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: "Production",
        marketLocationName: "Jita",
        iskPerCubicMeter: 2_000
      )
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          41: [
            makeOrder(typeID: 41, side: .buy, price: 250_000_000),
            makeOrder(typeID: 41, side: .sell, price: 300_000_000),
          ],
          42: [makeOrder(typeID: 42, side: .sell, price: 100)],
        ],
        source: source
      ),
      adjustedPrices: [
        42: AdjustedPrice(typeID: 42, adjustedPrice: 50, averagePrice: 50)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0.01
        )
      ],
      sdeBuild: 1,
      salesTaxRate: basis.marketTaxes.effectiveSalesTaxRate,
      brokerFeeRate: basis.marketTaxes.effectiveBrokerFeeRate
    )

    let plan = try await IndustryPlanner().plan(
      input: "Finished Product 1 0 0 BPC 7000000",
      context: context
    )

    let costs = try #require(plan.costBreakdown)
    let blueprintCosts = try #require(costs.blueprintCosts)
    let logistics = try #require(costs.logistics)
    #expect(logistics.legs.count == 2)
    #expect(
      logistics.legs.first { $0.kind == .inboundMaterials }?.chargedBy
        == .volume
    )
    #expect(
      logistics.legs.first { $0.kind == .inboundMaterials }?.roundedCharge
        == 1_000_000
    )
    #expect(
      logistics.legs.first { $0.kind == .outboundProducts }?.chargedBy
        == .collateral
    )
    #expect(
      logistics.legs.first { $0.kind == .outboundProducts }?.roundedCharge
        == 2_000_000
    )
    #expect(logistics.total == 3_000_000)
    #expect(costs.materialCost == 1_000)
    #expect(blueprintCosts.total == 7_000_000)
    #expect(blueprintCosts.entries.first?.kind == .bpc)
    #expect(blueprintCosts.entries.first?.treatment.contains("Consumed") == true)
    #expect(blueprintCosts.requestsWithoutEnteredCost.isEmpty)
    #expect(costs.systemIndexCost == 5)
    #expect(costs.facilityTax == 0)
    #expect(costs.sccSurcharge == 20)
    #expect(costs.alphaSurcharge == 0)
    #expect(costs.installationCost == 25)
    #expect(costs.totalProductionCost == 10_001_025)
    #expect(plan.immediateSale.grossRevenue == 250_000_000)
    #expect(plan.immediateSale.salesTax == 12_500_000)
    #expect(plan.immediateSale.brokerFee == 0)
    #expect(plan.immediateSale.grossOrNetRevenue == 237_500_000)
    #expect(plan.listedSale.grossRevenue == 300_000_000)
    #expect(plan.listedSale.salesTax == 15_000_000)
    #expect(plan.listedSale.brokerFee == 3_000_000)
    #expect(plan.listedSale.grossOrNetRevenue == 282_000_000)
  }

  @Test
  func automaticallySplitsOversizedCargoIntoMultipleContracts() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 501,
      productTypeID: 51,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: [BlueprintMaterial(typeID: 52, quantity: 383)],
        products: [
          BlueprintProduct(typeID: 51, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [51: "Finished Product", 52: "Bulky Material"],
      definitions: [51: product],
      packagedVolumes: [52: 1_000]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: ProductionBasis(
        logistics: LogisticsConfiguration(
          isEnabled: true,
          includeInboundMaterials: true,
          includeOutboundProducts: false,
          iskPerCubicMeter: 10
        )
      ),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          51: [
            makeOrder(typeID: 51, side: .buy, price: 10),
            makeOrder(typeID: 51, side: .sell, price: 11),
          ],
          52: [makeOrder(typeID: 52, side: .sell, price: 1_000)],
        ],
        source: source
      ),
      adjustedPrices: [
        52: AdjustedPrice(typeID: 52, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Finished Product 1 0 0",
      context: context
    )

    let logistics = try #require(plan.costBreakdown?.logistics)
    #expect(logistics.legs.count == 2)
    #expect(logistics.legs.map(\.cargoVolumeM3) == [350_000, 33_000])
    #expect(logistics.legs.map(\.contractNumber) == [1, 2])
    #expect(logistics.legs.allSatisfy { $0.contractCount == 2 })
    #expect(logistics.legs.map(\.roundedCharge) == [4_000_000, 1_000_000])
    #expect(logistics.total == 5_000_000)
    #expect(
      plan.warnings.contains {
        $0.code == "logistics.contracts-split"
          && $0.severity == .information
      }
    )
  }

  @Test
  func rejectsOneItemThatCannotFitInsideAContract() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 601,
      productTypeID: 61,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: [],
        products: [
          BlueprintProduct(typeID: 61, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [61: "Oversized Product"],
      definitions: [61: product],
      packagedVolumes: [61: 350_001]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: ProductionBasis(
        logistics: LogisticsConfiguration(
          isEnabled: true,
          includeInboundMaterials: false,
          includeOutboundProducts: true,
          iskPerCubicMeter: 1
        )
      ),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          61: [
            makeOrder(typeID: 61, side: .buy, price: 10),
            makeOrder(typeID: 61, side: .sell, price: 11),
          ]
        ],
        source: source
      ),
      adjustedPrices: [:],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Oversized Product 1 0 0",
      context: context
    )

    #expect(plan.costBreakdown?.logistics == nil)
    #expect(plan.costBreakdown?.totalProductionCost == nil)
    #expect(
      plan.warnings.contains {
        $0.code == "logistics.single-item-volume-exceeded"
          && $0.severity == .blocking
      }
    )
  }

  private func feeCalculation(
    source: SourceIdentity
  ) -> MarketFeeCalculation {
    MarketFeeCalculation(
      characterID: 1,
      accountingLevel: 5,
      brokerRelationsLevel: 5,
      factionStanding: 0,
      corporationStanding: 0,
      skillsState: .fresh,
      standingsState: .fresh,
      skillsSource: source,
      standingsSource: source,
      calculatedAt: .now,
      ruleVersion: MarketTaxConfiguration.ruleVersion,
      warnings: []
    )
  }

  private func makeOrder(
    typeID: Int64,
    side: MarketOrderSide,
    price: Double
  ) -> MarketOrder {
    MarketOrder(
      id: Int64.random(in: 1...Int64.max),
      typeID: typeID,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: side,
      price: price,
      volumeRemaining: 1_000_000,
      minimumVolume: 1,
      issued: .now
    )
  }
}

private struct FixtureCatalog: IndustryCatalogQuerying {
  let names: [Int64: String]
  let definitions: [Int64: BlueprintDefinition]
  let classifications: [Int64: IndustryItemClassification]
  let packagedVolumes: [Int64: Double]

  init(
    names: [Int64: String],
    definitions: [Int64: BlueprintDefinition],
    classifications: [Int64: IndustryItemClassification] = [:],
    packagedVolumes: [Int64: Double] = [:]
  ) {
    self.names = names
    self.definitions = definitions
    self.classifications = classifications
    self.packagedVolumes = packagedVolumes
  }

  func typeID(named name: String) async throws -> Int64? {
    names.first {
      $0.value.caseInsensitiveCompare(name) == .orderedSame
    }?.key
  }

  func typeName(id: Int64) async throws -> String? {
    names[id]
  }

  func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    definitions[productTypeID]
  }

  func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    classifications[productTypeID]
  }

  func packagedVolume(typeID: Int64) async throws -> Double? {
    packagedVolumes[typeID]
  }
}
