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
      availableStock: [2: 100],
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
    #expect(intermediate.fromStock == 0)
    #expect(intermediate.toProduce == 2)
    #expect(intermediate.procurement?.supplyMode == .produce)
    #expect(intermediate.canProduce)
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
  func buysIntermediateInsteadOfCreatingItsProductionJob() async throws {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .buy,
        purchaseLocation: .amarr
      )
    )

    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )

    let intermediate = try #require(
      plan.materials.first { $0.typeID == 82 }
    )
    #expect(intermediate.canProduce)
    #expect(intermediate.procurement?.supplyMode == .buy)
    #expect(intermediate.procurement?.purchaseLocation == .amarr)
    #expect(intermediate.toBuy == 2)
    #expect(intermediate.toProduce == 0)
    #expect(!plan.nodes.contains { $0.typeID == 82 && $0.action == .produce })
    #expect(!plan.materials.contains { $0.typeID == 83 })
    #expect(plan.materialCost == 30)
  }

  @Test
  func buyingReactionIntermediateDoesNotBuyItsReactionInputs() async throws {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .buy,
        purchaseLocation: .jita
      ),
      intermediateActivity: .reaction,
      directRawQuantity: 3
    )

    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )

    let intermediate = try #require(
      plan.materials.first { $0.typeID == 82 }
    )
    let directlyRequiredRawMaterial = try #require(
      plan.materials.first { $0.typeID == 83 }
    )
    #expect(intermediate.productionActivity == .reaction)
    #expect(intermediate.toBuy == 2)
    #expect(intermediate.toProduce == 0)
    #expect(directlyRequiredRawMaterial.required == 3)
    #expect(directlyRequiredRawMaterial.toBuy == 3)
    #expect(!plan.nodes.contains { $0.typeID == 82 && $0.action == .produce })
    #expect(!plan.jobs.contains { $0.typeID == 82 })
    #expect(plan.materialCost == 36)
  }

  @Test
  func usesIntermediateWarehouseStockAndValuesItAtTheFullQuoteUnitPrice()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .warehouse,
        purchaseLocation: .amarr
      ),
      availableStock: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )

    let intermediate = try #require(
      plan.materials.first { $0.typeID == 82 }
    )
    #expect(intermediate.fromStock == 1)
    #expect(intermediate.toBuy == 1)
    #expect(intermediate.toProduce == 0)
    #expect(intermediate.stockQuote?.total == 10)
    #expect(intermediate.replacementQuote?.total == 30)
    #expect(intermediate.replacementQuote?.weightedUnitPrice == 15)
    #expect(intermediate.warehouseConsumptionValue == 15)
    #expect(plan.warehouseConsumptionValue == 15)
    #expect(plan.costBreakdown?.stockMaterialCost == 15)
    #expect(plan.materialCost == 30)
    #expect(!plan.nodes.contains { $0.typeID == 82 && $0.action == .produce })
    #expect(!plan.materials.contains { $0.typeID == 83 })
  }

  @Test
  func keepsWarehouseMaterialsInTotalCostAndSeparatesTheirValue()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 150,
      productTypeID: 15,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 16, quantity: 10)],
        products: [
          BlueprintProduct(typeID: 15, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: FixtureCatalog(
        names: [15: "Stocked Product", 16: "Stocked Material"],
        definitions: [15: product]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          15: [
            makeOrder(typeID: 15, side: .buy, price: 1_000),
            makeOrder(typeID: 15, side: .sell, price: 1_200),
          ],
          16: [makeOrder(typeID: 16, side: .sell, price: 10)],
        ],
        source: source
      ),
      adjustedPrices: [
        16: AdjustedPrice(typeID: 16, adjustedPrice: 5, averagePrice: 5)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0.01
        )
      ],
      availableStock: [16: 4],
      procurementPreferences: [
        16: MaterialProcurementPreference(
          supplyMode: .warehouse,
          purchaseLocation: .amarr
        )
      ],
      assetSource: StockSource(
        kind: .warehouse,
        reference: "all-character-assets"
      ),
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Stocked Product 1 0 0",
      context: context
    )

    let material = try #require(
      plan.materials.first { $0.typeID == 16 }
    )
    let costs = try #require(plan.costBreakdown)
    #expect(material.fromStock == 4)
    #expect(material.toBuy == 6)
    #expect(material.quote?.quantity == 6)
    #expect(material.stockQuote?.quantity == 4)
    #expect(material.replacementQuote?.quantity == 10)
    #expect(material.procurement?.purchaseLocation == .amarr)
    #expect(costs.purchasedMaterialCost == 60)
    #expect(costs.stockMaterialCost == 40)
    #expect(costs.materialCost == 100)
    #expect(plan.materialCost == 100)
    #expect(
      costs.totalProductionCost
        == plan.materialCost! + plan.installationCost!
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
    let listedJob = try #require(plan.jobs.first { $0.typeID == 10 })
    #expect(listedJob.productName == "Batch Product")
    #expect(listedJob.runs == 3)
    #expect(listedJob.outputQuantity == 300)
    #expect(listedJob.materialEfficiency == 10)
    #expect(listedJob.timeEfficiency == 20)
    #expect(listedJob.isTopLevel == true)
    #expect(listedJob.facilityName == "Fixture Station")
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
    #expect(
      blacklistWarnings.first?.message
        == "Helium Fuel Block cannot be produced and uses the selected purchase or warehouse source."
    )
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
    #expect(logistics.legs.count == 1)
    #expect(
      logistics.legs.first { $0.kind == .inboundMaterials }?.chargedBy
        == .volume
    )
    #expect(
      logistics.legs.first { $0.kind == .inboundMaterials }?.roundedCharge
        == 1_000_000
    )
    #expect(logistics.legs[0].origin == ProcurementLocation.jita.name)
    #expect(logistics.legs[0].destination == "Production")
    #expect(logistics.total == 1_000_000)
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
    #expect(
      costs.installationCost
        == costs.systemIndexCost! + costs.facilityTax!
        + costs.sccSurcharge! + costs.alphaSurcharge!
    )
    #expect(costs.logisticsCost == 1_000_000)
    #expect(costs.totalProductionCost == 8_001_025)
    #expect(costs.recomputedTotalProductionCost == 8_001_025)
    #expect(costs.hasConsistentTotal)
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
  func transportsAllPurchasedRawMaterialsFromMainHubToProduction()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 701,
      productTypeID: 71,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: [
          BlueprintMaterial(typeID: 72, quantity: 2),
          BlueprintMaterial(typeID: 73, quantity: 3),
        ],
        products: [
          BlueprintProduct(typeID: 71, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let basis = ProductionBasis(
      logistics: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: "UALX Production",
        homeTradeHub: .jita,
        iskPerCubicMeter: 10
      )
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [71: "Product", 72: "Amarr Raw", 73: "Local Raw"],
        definitions: [71: product],
        packagedVolumes: [72: 10, 73: 20]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          71: [
            makeOrder(typeID: 71, side: .buy, price: 100),
            makeOrder(typeID: 71, side: .sell, price: 110),
          ],
          72: [makeOrder(typeID: 72, side: .sell, price: 4)],
          73: [makeOrder(typeID: 73, side: .sell, price: 5)],
        ],
        source: source
      ),
      adjustedPrices: [
        72: AdjustedPrice(typeID: 72, adjustedPrice: 1, averagePrice: 1),
        73: AdjustedPrice(typeID: 73, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      procurementPreferences: [
        72: MaterialProcurementPreference(
          supplyMode: .buy,
          purchaseLocation: .amarr
        ),
        73: MaterialProcurementPreference(
          supplyMode: .buy,
          purchaseLocation: .jita
        ),
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Product 1 0 0",
      context: context
    )

    let logistics = try #require(plan.costBreakdown?.logistics)
    #expect(logistics.legs.count == 1)
    #expect(logistics.legs[0].origin == ProcurementLocation.jita.name)
    #expect(logistics.legs[0].destination == "UALX Production")
    #expect(plan.materialCost == 23)
  }

  @Test
  func recommendsBuildAndShowsSavingsForTheCompleteRequiredQuantity()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let component = BlueprintDefinition(
      blueprintTypeID: 902,
      productTypeID: 92,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 93, quantity: 3)],
        products: [BlueprintProduct(typeID: 92, quantity: 2, probability: nil)]
      ),
      source: source
    )
    let product = BlueprintDefinition(
      blueprintTypeID: 901,
      productTypeID: 91,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 92, quantity: 5)],
        products: [BlueprintProduct(typeID: 91, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let manufacturingService = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 9_001,
        name: "Fixture Manufacturing Service",
        activities: [.manufacturing],
        source: source
      )
    )
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: EVEConstants.jitaSystemID,
      solarSystemName: "Jita",
      regionID: EVEConstants.theForgeRegionID,
      securityStatus: 0.9,
      securityClass: "highsec"
    )
    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      logistics: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: "Production",
        homeTradeHub: .jita,
        iskPerCubicMeter: 1
      ),
      structures: [
        ConfiguredIndustryStructure(
          name: "Production",
          kind: .custom,
          manufacturingSystemID: manufacturingSystem.id,
          securityBand: .highSecurity,
          serviceModules: [manufacturingService],
          source: .manual
        )
      ]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [91: "Product", 92: "Component", 93: "Raw"],
        definitions: [91: product, 92: component],
        packagedVolumes: [92: 1, 93: 1]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          91: [
            makeOrder(typeID: 91, side: .buy, price: 5_000_000),
            makeOrder(typeID: 91, side: .sell, price: 6_000_000),
          ],
          92: [makeOrder(typeID: 92, side: .sell, price: 500_000)],
          93: [makeOrder(typeID: 93, side: .sell, price: 10)],
        ],
        source: source
      ),
      adjustedPrices: [
        92: AdjustedPrice(typeID: 92, adjustedPrice: 1, averagePrice: 1),
        93: AdjustedPrice(typeID: 93, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      defaultPurchaseLocation: .jita,
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Product 1 0 0",
      context: context
    )

    let componentMaterial = try #require(
      plan.materials.first { $0.typeID == 92 }
    )
    let analysis = try #require(componentMaterial.makeOrBuyAnalysis)
    #expect(analysis.requiredQuantity == 5)
    #expect(analysis.productionRuns == 3)
    #expect(analysis.producedQuantity == 6)
    #expect(analysis.purchaseQuote.filledQuantity == 5)
    #expect(analysis.purchaseQuote.isComplete)
    #expect(analysis.purchaseTotalCost == 3_500_000)
    #expect(analysis.buildMaterialCost == 90)
    #expect(analysis.buildLogisticsCost == 1_000_000)
    #expect(analysis.buildInstallationCost == 0.36)
    #expect(analysis.buildTotalCost == 1_000_090.36)
    #expect(analysis.recommendation == .produce)
    #expect(analysis.savings == 2_499_909.64)

    let produceApplication = MakeOrBuyRecommendationApplication(
      materials: plan.materials,
      existingPreferences: [
        92: MaterialProcurementPreference(
          supplyMode: .warehouse,
          purchaseLocation: .amarr
        )
      ],
      mainHub: .jita
    )
    #expect(produceApplication.appliedCount == 1)
    #expect(produceApplication.produceCount == 1)
    #expect(produceApplication.buyCount == 0)
    #expect(produceApplication.unavailableCount == 0)
    #expect(produceApplication.preferences[92]?.supplyMode == .produce)
    #expect(produceApplication.preferences[92]?.purchaseLocation == .jita)

    let buyContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [91: "Product", 92: "Component", 93: "Raw"],
        definitions: [91: product, 92: component],
        packagedVolumes: [92: 1, 93: 1]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          91: [makeOrder(typeID: 91, side: .sell, price: 6_000_000)],
          92: [makeOrder(typeID: 92, side: .sell, price: 500_000)],
          93: [makeOrder(typeID: 93, side: .sell, price: 500_000)],
        ],
        source: source
      ),
      adjustedPrices: [
        92: AdjustedPrice(typeID: 92, adjustedPrice: 1, averagePrice: 1),
        93: AdjustedPrice(typeID: 93, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      defaultPurchaseLocation: .jita,
      sdeBuild: 1
    )
    let buyPlan = try await IndustryPlanner().plan(
      input: "Product 1 0 0",
      context: buyContext
    )
    let buyAnalysis = try #require(
      buyPlan.materials.first { $0.typeID == 92 }?.makeOrBuyAnalysis
    )
    #expect(buyAnalysis.recommendation == .buy)
    #expect(buyAnalysis.buildTotalCost == 5_500_000.36)
    #expect(buyAnalysis.purchaseTotalCost == 3_500_000)
    #expect(abs((buyAnalysis.savings ?? 0) - 2_000_000.36) < 0.001)

    let buyApplication = MakeOrBuyRecommendationApplication(
      materials: buyPlan.materials,
      existingPreferences: [
        92: MaterialProcurementPreference(
          supplyMode: .warehouse,
          purchaseLocation: .amarr
        ),
        999: MaterialProcurementPreference(
          supplyMode: .warehouse,
          purchaseLocation: .amarr
        ),
      ],
      mainHub: .jita
    )
    #expect(buyApplication.appliedCount == 1)
    #expect(buyApplication.produceCount == 0)
    #expect(buyApplication.buyCount == 1)
    #expect(buyApplication.preferences[92]?.supplyMode == .buy)
    #expect(buyApplication.preferences[92]?.purchaseLocation == .jita)
    #expect(buyApplication.preferences[999]?.supplyMode == .warehouse)
    #expect(buyApplication.preferences[999]?.purchaseLocation == .amarr)
  }

  @Test
  func neverRecommendsBuyingWhenMainHubDepthCannotFillTheQuantity()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let component = BlueprintDefinition(
      blueprintTypeID: 912,
      productTypeID: 112,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .reaction,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 113, quantity: 1)],
        products: [BlueprintProduct(typeID: 112, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let product = BlueprintDefinition(
      blueprintTypeID: 911,
      productTypeID: 111,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 112, quantity: 5)],
        products: [BlueprintProduct(typeID: 111, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let limitedOrder = MarketOrder(
      id: 9_120,
      typeID: 112,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: .sell,
      price: 100,
      volumeRemaining: 4,
      minimumVolume: 1,
      issued: .now
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      reactionProfile: ReactionProfile(
        structureName: "Reaction Facility",
        manualEffectiveMaterialMultiplier: 1,
        manualEffectiveTimeMultiplier: 1,
        manualEffectiveJobCostMultiplier: 1
      ),
      productionBasis: ProductionBasis(
        logistics: LogisticsConfiguration(
          isEnabled: true,
          productionLocationName: "Production",
          homeTradeHub: .jita,
          iskPerCubicMeter: 1
        )
      ),
      catalog: FixtureCatalog(
        names: [111: "Product", 112: "Reaction Intermediate", 113: "Moon Input"],
        definitions: [111: product, 112: component],
        packagedVolumes: [112: 1, 113: 1]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          111: [makeOrder(typeID: 111, side: .sell, price: 1_000)],
          112: [limitedOrder],
          113: [makeOrder(typeID: 113, side: .sell, price: 1)],
        ],
        source: source
      ),
      adjustedPrices: [
        112: AdjustedPrice(typeID: 112, adjustedPrice: 1, averagePrice: 1),
        113: AdjustedPrice(typeID: 113, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        ),
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .reaction,
          costIndex: 0
        ),
      ],
      sdeBuild: 1
    )

    let plan = try await IndustryPlanner().plan(
      input: "Product 1 0 0",
      context: context
    )
    let analysis = try #require(
      plan.materials.first { $0.typeID == 112 }?.makeOrBuyAnalysis
    )
    #expect(analysis.purchaseQuote.filledQuantity == 4)
    #expect(analysis.purchaseQuote.total == nil)
    #expect(analysis.purchaseTotalCost == nil)
    #expect(analysis.recommendation == .unavailable)
    #expect(
      analysis.warnings.contains { $0.code == "market.insufficient-depth" }
    )

    let application = MakeOrBuyRecommendationApplication(
      materials: plan.materials,
      existingPreferences: [
        112: MaterialProcurementPreference(
          supplyMode: .warehouse,
          purchaseLocation: .amarr
        )
      ],
      mainHub: .jita
    )
    #expect(!application.hasApplicableRecommendations)
    #expect(application.unavailableCount == 1)
    #expect(application.preferences[112]?.supplyMode == .warehouse)
    #expect(application.preferences[112]?.purchaseLocation == .amarr)
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
        materials: [BlueprintMaterial(typeID: 62, quantity: 1)],
        products: [
          BlueprintProduct(typeID: 61, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let catalog = FixtureCatalog(
      names: [61: "Oversized Product", 62: "Oversized Material"],
      definitions: [61: product],
      packagedVolumes: [62: 350_001]
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: ProductionBasis(
        logistics: LogisticsConfiguration(
          isEnabled: true,
          includeInboundMaterials: true,
          includeOutboundProducts: false,
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
          ],
          62: [makeOrder(typeID: 62, side: .sell, price: 1)],
        ],
        source: source
      ),
      adjustedPrices: [
        62: AdjustedPrice(typeID: 62, adjustedPrice: 1, averagePrice: 1)
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

  private func intermediateChoiceContext(
    preference: MaterialProcurementPreference,
    availableStock: Int64 = 0,
    intermediateActivity: BlueprintActivityDefinition.Kind = .manufacturing,
    directRawQuantity: Int64 = 0
  ) -> IndustryPlanningContext {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let intermediate = BlueprintDefinition(
      blueprintTypeID: 802,
      productTypeID: 82,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: intermediateActivity,
        durationSeconds: 10,
        materials: [BlueprintMaterial(typeID: 83, quantity: 4)],
        products: [
          BlueprintProduct(typeID: 82, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    var productMaterials = [BlueprintMaterial(typeID: 82, quantity: 2)]
    if directRawQuantity > 0 {
      productMaterials.append(
        BlueprintMaterial(typeID: 83, quantity: directRawQuantity)
      )
    }
    let product = BlueprintDefinition(
      blueprintTypeID: 801,
      productTypeID: 81,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: productMaterials,
        products: [
          BlueprintProduct(typeID: 81, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let firstDepth = MarketOrder(
      id: 8201,
      typeID: 82,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: .sell,
      price: 10,
      volumeRemaining: 1,
      minimumVolume: 1,
      issued: .now
    )
    let secondDepth = MarketOrder(
      id: 8202,
      typeID: 82,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: .sell,
      price: 20,
      volumeRemaining: 100,
      minimumVolume: 1,
      issued: .now
    )
    return IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      reactionProfile:
        intermediateActivity == .reaction
        ? ReactionProfile(
          structureName: "Reaction Facility",
          manualEffectiveMaterialMultiplier: 1,
          manualEffectiveTimeMultiplier: 1,
          manualEffectiveJobCostMultiplier: 1
        ) : nil,
      catalog: FixtureCatalog(
        names: [
          81: "Choice Product",
          82: "Choice Intermediate",
          83: "Choice Raw",
        ],
        definitions: [81: product, 82: intermediate]
      ),
      market: MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          81: [
            makeOrder(typeID: 81, side: .buy, price: 100),
            makeOrder(typeID: 81, side: .sell, price: 110),
          ],
          82: [firstDepth, secondDepth],
          83: [makeOrder(typeID: 83, side: .sell, price: 2)],
        ],
        source: source
      ),
      adjustedPrices: [
        82: AdjustedPrice(typeID: 82, adjustedPrice: 5, averagePrice: 5),
        83: AdjustedPrice(typeID: 83, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        ),
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .reaction,
          costIndex: 0
        ),
      ],
      availableStock: availableStock > 0 ? [82: availableStock] : [:],
      procurementPreferences: [82: preference],
      sdeBuild: 1
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
