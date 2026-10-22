import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry planner")
struct IndustryPlannerTests {
  @Test
  func separateBPCJobsRoundMaterialsPerInstance() {
    let oneRunJob = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: 5,
      runs: 1,
      materialEfficiency: 10,
      facilityMultiplier: 0.99
    )
    let separateJobs = oneRunJob * 2
    let incorrectlyMergedJob = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: 5,
      runs: 2,
      materialEfficiency: 10,
      facilityMultiplier: 0.99
    )

    #expect(separateJobs == 10)
    #expect(incorrectlyMergedJob == 9)
  }

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
  func makespanWaitsForComponentJobsEvenWithFreeSlots() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    func definition(
      blueprint: Int64,
      product: Int64,
      seconds: Int64,
      materials: [BlueprintMaterial]
    ) -> BlueprintDefinition {
      BlueprintDefinition(
        blueprintTypeID: blueprint,
        productTypeID: product,
        maxProductionLimit: nil,
        activity: BlueprintActivityDefinition(
          kind: .manufacturing,
          durationSeconds: seconds,
          materials: materials,
          products: [
            BlueprintProduct(typeID: product, quantity: 1, probability: nil)
          ]
        ),
        source: source
      )
    }
    let catalog = FixtureCatalog(
      names: [1: "Ship", 2: "Component A", 4: "Component B", 3: "Mineral"],
      definitions: [
        1: definition(
          blueprint: 100,
          product: 1,
          seconds: 100,
          materials: [
            BlueprintMaterial(typeID: 2, quantity: 1),
            BlueprintMaterial(typeID: 4, quantity: 1),
          ]
        ),
        2: definition(
          blueprint: 101,
          product: 2,
          seconds: 50,
          materials: [BlueprintMaterial(typeID: 3, quantity: 1)]
        ),
        4: definition(
          blueprint: 102,
          product: 4,
          seconds: 50,
          materials: [BlueprintMaterial(typeID: 3, quantity: 1)]
        ),
      ]
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [3: [makeOrder(typeID: 3, side: .sell, price: 5)]],
      source: source
    )
    func plan(slots: Int) async throws -> IndustryPlanSnapshot {
      try await IndustryPlanner().plan(
        input: "Ship 1 0 0",
        context: IndustryPlanningContext(
          manufacturingProfile: ManufacturingProfile(),
          productionBasis: ProductionBasis(
            scheduling: ProductionSchedulingConfiguration(
              manufacturingSlots: slots
            )
          ),
          catalog: catalog,
          market: market,
          adjustedPrices: [:],
          systemIndices: [],
          sdeBuild: 1
        )
      )
    }
    let single = try await plan(slots: 1)
    let parallel = try await plan(slots: 5)
    #expect(single.jobs.count == 3)
    #expect(single.makespanSeconds == single.totalJobSeconds)
    // Both components run in parallel, the ship starts after the longer one.
    let ship = try #require(
      parallel.jobs.first { $0.typeID == 1 }?.durationSeconds
    )
    let component = try #require(
      parallel.jobs.first { $0.typeID == 2 }?.durationSeconds
    )
    #expect(parallel.makespanSeconds == ship + component)
    #expect(parallel.makespanSeconds < parallel.totalJobSeconds)
    #expect(parallel.slotSchedule?.source == .manual)
    #expect(parallel.slotSchedule?.manufacturingSlots == 5)
    #expect(parallel.estimatedMakespanSeconds == parallel.makespanSeconds)
  }

  @Test
  func splitIntermediateJobsRoundMaterialsPerInstalledJob() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let part = BlueprintDefinition(
      blueprintTypeID: 201,
      productTypeID: 2,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 86_400,
        materials: [BlueprintMaterial(typeID: 3, quantity: 7)],
        products: [BlueprintProduct(typeID: 2, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let module = BlueprintDefinition(
      blueprintTypeID: 200,
      productTypeID: 1,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 60,
        materials: [BlueprintMaterial(typeID: 2, quantity: 10)],
        products: [BlueprintProduct(typeID: 1, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [3: [makeOrder(typeID: 3, side: .sell, price: 5)]],
      source: source
    )
    var basis = ProductionBasis(
      scheduling: ProductionSchedulingConfiguration(
        manufacturingSlots: 5,
        doNotSplitShorterThanDays: 1,
        maximumJobDays: 3
      )
    )
    basis.defaultIntermediateME = 10
    basis.defaultIntermediateTE = 0
    let plan = try await IndustryPlanner().plan(
      input: "Module 1 0 0",
      context: IndustryPlanningContext(
        manufacturingProfile: ManufacturingProfile(),
        productionBasis: basis,
        catalog: FixtureCatalog(
          names: [1: "Module", 2: "Part", 3: "Mineral"],
          definitions: [1: module, 2: part]
        ),
        market: market,
        adjustedPrices: [:],
        systemIndices: [],
        sdeBuild: 1
      )
    )
    let partJobs = plan.jobs.filter { $0.typeID == 2 }
    // 10 runs × 1 day: no job above 3 days, and the five free slots are
    // filled while every piece keeps at least one day.
    #expect(partJobs.map(\.runs) == [2, 2, 2, 2, 2])
    #expect(partJobs.map(\.piece) == [1, 2, 3, 4, 5])
    #expect(partJobs.allSatisfy { $0.pieceCount == 5 })
    let perJob = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: 7,
      runs: 2,
      materialEfficiency: 10,
      facilityMultiplier:
        ManufacturingProfile().effectiveMaterialMultiplier
    )
    let mineral = try #require(plan.materials.first { $0.typeID == 3 })
    #expect(mineral.required == 5 * perJob)
    #expect(mineral.toBuy == 5 * perJob)
    let part2 = try #require(plan.materials.first { $0.typeID == 2 })
    #expect(part2.toProduce == 10)
    // Five parallel 2-day pieces, then the 1-minute module.
    let moduleSeconds = try #require(
      plan.jobs.first { $0.typeID == 1 }?.durationSeconds
    )
    let pieceSeconds = try #require(partJobs.first?.durationSeconds)
    #expect(plan.makespanSeconds == pieceSeconds + moduleSeconds)
    #expect(plan.slotSchedule?.entries?.count == 6)
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
  func productionTreeLinksTheParentToTheRecursiveIntermediateRoot()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      )
    )

    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )
    let referenced = Set(plan.nodes.flatMap(\.children))
    let root = try #require(
      plan.nodes.first { $0.typeID == 81 && !referenced.contains($0.id) }
    )
    let childID = try #require(root.children.first)
    let child = try #require(plan.nodes.first { $0.id == childID })

    #expect(root.requestedQuantity == 1)
    #expect(root.blueprintTypeID == 801)
    #expect(child.typeID == 82)
    #expect(child.action == .produce)
    #expect(child.requestedQuantity == 2)
    #expect(child.blueprintTypeID == 802)
    #expect(
      child.children.contains { childID in
        plan.nodes.first { $0.id == childID }?.typeID == 83
      })
  }

  @Test
  func stockFirstBuildUsesStockThenProducesOnlyTheShortfall()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita,
        usesAvailableStockFirst: true
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

    #expect(intermediate.required == 2)
    #expect(intermediate.fromStock == 1)
    #expect(intermediate.toProduce == 1)
    #expect(intermediate.toBuy == 0)
    #expect(intermediate.replacementQuote?.quantity == 2)
    #expect(intermediate.replacementQuote?.total == 30)
    #expect(intermediate.replacementQuote?.weightedUnitPrice == 15)
    #expect(intermediate.warehouseConsumptionValue == 15)
    #expect(plan.materials.first { $0.typeID == 83 }?.required == 4)
    #expect(plan.costBreakdown?.purchasedMaterialCost == 8)
    #expect(plan.costBreakdown?.stockMaterialCost == 15)
    #expect(plan.materialCost == 23)
    #expect(plan.costBreakdown?.materialCost == 23)
    let request = try #require(plan.requests.first)
    #expect(
      ProductionOverviewProjector.projection(for: request.id, in: plan)?
        .materialCost == 23
    )
    let restored = try JSONDecoder().decode(
      IndustryPlanSnapshot.self, from: JSONEncoder().encode(plan)
    )
    #expect(restored.materialCost == 23)
    #expect(
      ProductionOverviewProjector.projection(for: request.id, in: restored)?
        .materialCost == 23
    )
    #expect(
      plan.nodes.contains {
        $0.typeID == 82 && $0.action == .useStock
          && $0.requiredQuantity == 1
      })
    #expect(
      plan.nodes.contains {
        $0.typeID == 82 && $0.action == .produce
          && $0.requestedQuantity == 1
      })
  }

  @Test(arguments: [Int64(0), 1, 2])
  func stockFirstCostsOnlyStockAndRecursiveInputs(availableStock: Int64)
    async throws
  {
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: MaterialProcurementPreference(
          supplyMode: .produce,
          purchaseLocation: .jita,
          usesAvailableStockFirst: true
        ),
        availableStock: availableStock
      )
    )
    let intermediate = try #require(plan.materials.first { $0.typeID == 82 })
    let stockCost = Double(availableStock) * 15
    let rawCost = Double(2 - availableStock) * 8
    #expect(intermediate.fromStock == availableStock)
    #expect(intermediate.toProduce == 2 - availableStock)
    #expect(plan.materialCost == stockCost + rawCost)
    #expect(plan.costBreakdown?.purchasedMaterialCost == rawCost)
    #expect(plan.costBreakdown?.stockMaterialCost == stockCost)
    if availableStock == 0 {
      #expect(intermediate.replacementQuote == nil)
    } else {
      #expect(intermediate.replacementQuote?.total == 30)
      #expect(intermediate.replacementQuote?.weightedUnitPrice == 15)
    }
    if availableStock == 2 {
      #expect(!plan.materials.contains { $0.typeID == 83 })
      #expect(!plan.nodes.contains { $0.typeID == 82 && $0.action == .produce })
    }
    let request = try #require(plan.requests.first)
    #expect(
      ProductionOverviewProjector.projection(for: request.id, in: plan)?
        .materialCost == plan.materialCost
    )
  }

  @Test
  func stockFirstSharedDemandAgreesWithEveryRequestProjection() async throws {
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0\nChoice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: MaterialProcurementPreference(
          supplyMode: .produce,
          purchaseLocation: .jita,
          usesAvailableStockFirst: true
        ),
        availableStock: 1
      )
    )
    let intermediate = try #require(plan.materials.first { $0.typeID == 82 })
    #expect(intermediate.required == 4)
    #expect(intermediate.fromStock == 1)
    #expect(intermediate.toProduce == 3)
    #expect(intermediate.replacementQuote?.total == 70)
    #expect(intermediate.replacementQuote?.weightedUnitPrice == 17.5)
    // One aggregated 3-run job at ME 10 rounds 4 × 3 × 0.9 = 10.8 to 11 raw
    // units (2 ISK each); separate branch jobs would need 4 + 8 = 12.
    #expect(plan.materials.first { $0.typeID == 83 }?.required == 11)
    #expect(plan.costBreakdown?.purchasedMaterialCost == 22)
    #expect(plan.costBreakdown?.stockMaterialCost == 17.5)
    #expect(plan.materialCost == 39.5)
    let costs = try plan.requests.map { request in
      try #require(
        ProductionOverviewProjector.projection(for: request.id, in: plan)?
          .materialCost
      )
    }
    // Branch values 25.5 and 16 weight the requests; the shares are scaled
    // to the plan's material cost.
    #expect(abs(costs[0] - 39.5 * 25.5 / 41.5) < 1e-9)
    #expect(costs.reduce(0, +) == plan.materialCost)
  }

  @Test
  func stockFirstStillRequiresMarketDepthForTheFullIntermediateDemand()
    async throws
  {
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: MaterialProcurementPreference(
          supplyMode: .produce,
          purchaseLocation: .jita,
          usesAvailableStockFirst: true
        ),
        availableStock: 1,
        intermediateSecondDepth: 0
      )
    )
    let intermediate = try #require(plan.materials.first { $0.typeID == 82 })
    #expect(intermediate.stockQuote?.total == 10)
    #expect(intermediate.replacementQuote?.quantity == 2)
    #expect(intermediate.replacementQuote?.filledQuantity == 1)
    #expect(intermediate.replacementQuote?.total == nil)
    #expect(intermediate.replacementQuote?.weightedUnitPrice == nil)
    #expect(plan.materialCost == nil)
    #expect(plan.costBreakdown?.materialCost == nil)
    #expect(plan.costBreakdown?.stockMaterialCost == nil)
    #expect(plan.costBreakdown?.purchasedMaterialCost == 8)
    #expect(plan.costBreakdown?.totalProductionCost == nil)
    #expect(plan.immediateSale.profit == nil)
    #expect(plan.warnings.contains {
      $0.code == "market.insufficient-depth" && $0.severity == .blocking
    })
  }

  @Test
  func appliesProductSpecificEfficienciesToRecursiveManufacturingSteps()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      ),
      productionEfficiencies: [
        81: IndustryProductionEfficiency(
          materialEfficiency: 5,
          timeEfficiency: 10
        ),
        82: IndustryProductionEfficiency(
          materialEfficiency: 7,
          timeEfficiency: 14
        ),
      ]
    )

    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )

    let root = try #require(
      plan.nodes.first { $0.typeID == 81 && $0.action == .produce }
    )
    let intermediate = try #require(
      plan.nodes.first { $0.typeID == 82 && $0.action == .produce }
    )
    #expect(root.materialEfficiency == 5)
    #expect(root.timeEfficiency == 10)
    #expect(intermediate.materialEfficiency == 7)
    #expect(intermediate.timeEfficiency == 14)
    #expect(plan.jobs.first { $0.typeID == 82 }?.materialEfficiency == 7)
    #expect(plan.jobs.first { $0.typeID == 82 }?.timeEfficiency == 14)
  }

  @Test
  func rejectsInvalidProductSpecificEfficiency() async throws {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      ),
      productionEfficiencies: [
        82: IndustryProductionEfficiency(
          materialEfficiency: 11,
          timeEfficiency: 20
        )
      ]
    )

    await #expect(
      throws: IndustryPlannerError.invalidProductionEfficiency(typeID: 82)
    ) {
      try await IndustryPlanner().plan(
        input: "Choice Product 1 0 0",
        context: context
      )
    }
  }

  @Test
  func productionTreeProjectsFullPartialAndMissingWarehouseCoverage()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      )
    )
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )
    let locationID: Int64 = 1_000_000_000_101
    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 7,
          ownerName: "Builder",
          assets: Sourced(
            state: .fresh,
            value: AssetSnapshot(
              characterID: 7,
              state: .fresh,
              items: [
                AssetItem(
                  id: 7001,
                  typeID: 83,
                  quantity: 4,
                  locationID: locationID,
                  locationKind: .structure,
                  locationFlag: "Hangar",
                  singleton: false
                ),
                AssetItem(
                  id: 7002,
                  typeID: 82,
                  quantity: 2,
                  locationID: locationID,
                  locationKind: .structure,
                  locationFlag: "Hangar",
                  singleton: false
                ),
              ],
              resolvedLocationNames: [locationID: "Production"]
            ),
            source: SourceIdentity(provider: "ESI", version: "fixture")
          )
        )
      ]
    )
    let tree = ManufacturingProductionTreeProjector.project(
      targetQuantity: 1,
      mainHub: .jita,
      referencePlan: plan,
      selectedPlan: plan,
      warehouse: warehouse,
      warehouseHasSnapshot: true,
      protectedQuantities: [82: 1],
      reservedQuantities: [:],
      preferences: [:],
      blueprintPortfolio: BlueprintPortfolio(
        inventories: [
          OwnedBlueprintInventory(
            ownerID: 7,
            ownerName: "Builder",
            blueprints: Sourced(
              state: .fresh,
              value: [
                OwnedBlueprintInstance(
                  id: 8_002,
                  blueprintTypeID: 802,
                  locationID: locationID,
                  quantity: -2,
                  runs: 1,
                  materialEfficiency: 10,
                  timeEfficiency: 20,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: "fixture"
                  )
                ),
                OwnedBlueprintInstance(
                  id: 8_004,
                  blueprintTypeID: 802,
                  locationID: locationID,
                  quantity: -2,
                  runs: 1,
                  materialEfficiency: 10,
                  timeEfficiency: 20,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: "fixture"
                  )
                ),
                OwnedBlueprintInstance(
                  id: 8_005,
                  blueprintTypeID: 802,
                  locationID: locationID + 2,
                  quantity: -2,
                  runs: 10,
                  materialEfficiency: 10,
                  timeEfficiency: 20,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: "fixture"
                  )
                ),
                OwnedBlueprintInstance(
                  id: 8_003,
                  blueprintTypeID: 802,
                  locationID: locationID + 1,
                  quantity: -1,
                  runs: 0,
                  materialEfficiency: 8,
                  timeEfficiency: 16,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: "fixture"
                  )
                ),
              ],
              source: SourceIdentity(provider: "ESI", version: "fixture")
            )
          )
        ]
      ),
      blueprintNames: [801: "Product Blueprint", 802: "Component Blueprint"],
      blueprintContractOffers: [:],
      publicContractCoverageComplete: false,
      inventionDefinitions: [:],
      productionScope: ProductionWarehouseScope(
        locations: [
          ProductionWarehouseLocation(
            locationID: locationID,
            structureName: "Unconfigured structure",
            solarSystemID: 30_000_001,
            solarSystemName: "Test",
            activities: [.manufacturing]
          ),
          ProductionWarehouseLocation(
            locationID: locationID + 2,
            structureName: "Other Production",
            solarSystemID: 30_000_001,
            solarSystemName: "Test",
            activities: [.manufacturing]
          ),
          ProductionWarehouseLocation(
            locationID: locationID + 1,
            structureName: "Research",
            solarSystemID: 30_000_001,
            solarSystemName: "Test",
            activities: [.materialResearch, .timeResearch]
          ),
        ]
      )
    )
    let raw = try #require(tree.nodes.first { $0.typeID == 83 })
    let root = try #require(tree.nodes.first { $0.typeID == 81 })
    let intermediate = try #require(
      tree.nodes.first { $0.typeID == 82 && $0.action == .produce }
    )

    #expect(raw.totalRequiredQuantity == 8)
    #expect(raw.usableWarehouseQuantity == 4)
    #expect(raw.stockCoverage == .partial)
    #expect(root.blueprint?.recommendation == .manualExternalBPC)
    #expect(
      tree.warnings.contains {
        $0.code == "production-tree.public-contract-coverage-incomplete"
      }
    )
    #expect(intermediate.totalRequiredQuantity == 2)
    #expect(intermediate.factualWarehouseQuantity == 2)
    #expect(intermediate.protectedWarehouseQuantity == 1)
    #expect(intermediate.usableWarehouseQuantity == 1)
    #expect(intermediate.stockCoverage == .partial)
    #expect(intermediate.sourceCategory == "Material")
    #expect(intermediate.sourceGroup == "Construction Components")
    #expect(intermediate.sourceTechLevel == 2)
    #expect(intermediate.blueprint?.recommendation == .useOwnedBPC)
    #expect(intermediate.blueprint?.exactLocationBPCCount == 2)
    #expect(intermediate.blueprint?.exactLocationBPCRuns == 2)
    #expect(intermediate.blueprint?.exactLocationBPCRequiredCount == 2)
    let bpcQuality = try #require(
      intermediate.blueprint?.exactLocationEfficiencyOptions.first {
        $0.kind == .copy
      }
    )
    #expect(bpcQuality.materialEfficiency == 10)
    #expect(bpcQuality.timeEfficiency == 20)
    #expect(bpcQuality.availableRuns == 2)
    #expect(bpcQuality.instanceCount == 2)
    #expect(bpcQuality.ownerNames == ["Builder"])
    let repeatedAssessment = try #require(intermediate.blueprint)
    let supplyPlans = BlueprintSupplyPlanner.plans(
      referencePlan: plan,
      assessments: tree.nodes.compactMap(\.blueprint) + [repeatedAssessment],
      actions: [802: .useOwnedBPC],
      manualCosts: [:],
      preferredEfficiencies: [:],
      planID: UUID(),
      existingReservations: []
    )
    let concreteBPCSupply = try #require(supplyPlans[802])
    #expect(concreteBPCSupply.manufacturingJobs.count == 2)
    #expect(concreteBPCSupply.manufacturingJobs.map(\.runs) == [1, 1])
    #expect(concreteBPCSupply.reservations.count == 2)
    #expect(intermediate.blueprint?.otherLocationCount == 2)
    #expect(intermediate.blueprint?.otherLocationBPCCount == 1)
    #expect(intermediate.blueprint?.otherLocationBPOCount == 1)
    #expect(intermediate.blueprint?.researchLocationBPOCount == 1)
    #expect(
      intermediate.blueprint?.availableActions.contains(.buyContractBPC) == false
    )
    let transferPlan = try #require(
      BlueprintSupplyPlanner.plans(
        referencePlan: plan,
        assessments: tree.nodes.compactMap(\.blueprint),
        actions: [802: .useOwnedBPO],
        manualCosts: [802: 0],
        preferredEfficiencies: [:],
        planID: UUID(),
        existingReservations: [],
        preferredSources: [802: [.ownedBPO(itemID: 8_003)]]
      )[802]
    )
    let transfer = try #require(transferPlan.transfers.first)
    #expect(transfer.originLocationID == locationID + 1)
    #expect(transfer.destinationLocationID == locationID)
    #expect(transfer.isResolved)
  }

  @Test
  func requestedRootStaysABlueprintStepDespiteBuyPreference() async throws {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      )
    )
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )
    let rootTypeID = try #require(
      plan.nodes.first { $0.action == .produce && $0.blueprintTypeID == 801 }
    ).typeID
    // The planner's market-type preferences default every type without a
    // make-or-buy recommendation to "buy", including the requested product.
    let tree = ManufacturingProductionTreeProjector.project(
      targetQuantity: 1,
      mainHub: .jita,
      referencePlan: plan,
      selectedPlan: plan,
      warehouse: AssetWarehouse(inventories: []),
      warehouseHasSnapshot: false,
      protectedQuantities: [:],
      reservedQuantities: [:],
      preferences: [
        rootTypeID: MaterialProcurementPreference(
          supplyMode: .buy,
          purchaseLocation: .jita
        )
      ],
      blueprintPortfolio: BlueprintPortfolio(inventories: []),
      blueprintNames: [801: "Product Blueprint", 802: "Component Blueprint"],
      blueprintContractOffers: [:],
      publicContractCoverageComplete: true,
      inventionDefinitions: [:],
      productionScope: ProductionWarehouseScope(locations: [])
    )
    let root = try #require(tree.nodes.first { tree.rootIDs.contains($0.id) })
    #expect(root.selectedSupplyMode == .produce)
    #expect(root.blueprint?.blueprintTypeID == 801)
  }

  @Test
  func marketOriginalIsSeparateFromContractsAndNeverBecomesMarketCopy()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      )
    )
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )
    let marketSource = SourceIdentity(
      provider: "ESI market",
      version: "fixture"
    )
    let order = MarketOrder(
      id: 44_002,
      typeID: 802,
      locationID: EVEConstants.jitaIV4StationID,
      systemID: EVEConstants.jitaSystemID,
      side: .sell,
      price: 12_500_000,
      volumeRemaining: 1,
      minimumVolume: 1,
      issued: .now
    )
    let tree = ManufacturingProductionTreeProjector.project(
      targetQuantity: 1,
      mainHub: .jita,
      referencePlan: plan,
      selectedPlan: plan,
      warehouse: AssetWarehouse(inventories: []),
      warehouseHasSnapshot: false,
      protectedQuantities: [:],
      reservedQuantities: [:],
      preferences: [:],
      blueprintPortfolio: BlueprintPortfolio(inventories: []),
      blueprintNames: [801: "Product Blueprint", 802: "Component Blueprint"],
      blueprintContractOffers: [:],
      blueprintMarketOrders: [802: [order]],
      blueprintMarketSource: marketSource,
      blueprintMarketState: .fresh,
      publicContractCoverageComplete: true,
      inventionDefinitions: [:],
      productionScope: ProductionWarehouseScope(locations: [])
    )
    let assessment = try #require(
      tree.nodes.first { $0.blueprint?.blueprintTypeID == 802 }?.blueprint
    )

    #expect(assessment.availableActions.contains(.buyMarketBPO))
    #expect(!assessment.availableActions.contains(.buyContractBPO))
    #expect(!assessment.availableActions.contains(.buyContractBPC))
    #expect(assessment.marketBPOOptions.map(\.orderID) == [44_002])

    let supply = try #require(
      BlueprintSupplyPlanner.plans(
        referencePlan: plan,
        assessments: tree.nodes.compactMap(\.blueprint),
        actions: [802: .buyMarketBPO],
        manualCosts: [802: 250_000],
        preferredEfficiencies: [:],
        planID: UUID(),
        existingReservations: []
      )[802]
    )
    let job = try #require(supply.manufacturingJobs.first)
    #expect(job.allocation.source == .marketBPO(orderID: 44_002))
    #expect(job.allocation.provenance == .marketOriginal)
    #expect(job.allocation.availableRuns == nil)
    #expect(supply.capitalPurchaseCost == 12_500_000)
    #expect(supply.batchAllocationCost == 250_000)
    #expect(supply.reservations.isEmpty)
  }

  @Test
  func productionTreeOffersRetainedBPOInsideContainerAtExactLocation()
    async throws
  {
    let context = intermediateChoiceContext(
      preference: MaterialProcurementPreference(
        supplyMode: .produce,
        purchaseLocation: .jita
      )
    )
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: context
    )
    let locationID: Int64 = 1_000_000_000_101
    let containerID: Int64 = 9_001
    let blueprintItemID: Int64 = 9_002
    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 7,
          ownerName: "Builder",
          assets: Sourced(
            state: .fresh,
            value: AssetSnapshot(
              characterID: 7,
              state: .fresh,
              items: [
                AssetItem(
                  id: containerID,
                  typeID: 1_000,
                  quantity: 1,
                  locationID: locationID,
                  locationKind: .structure,
                  locationFlag: "Hangar",
                  singleton: true
                ),
                AssetItem(
                  id: blueprintItemID,
                  typeID: 802,
                  quantity: -1,
                  locationID: containerID,
                  locationKind: .item,
                  locationFlag: "Unlocked",
                  singleton: true
                ),
              ],
              resolvedLocationNames: [locationID: "Production"]
            ),
            source: SourceIdentity(provider: "ESI", version: "fixture")
          )
        )
      ]
    )
    let tree = ManufacturingProductionTreeProjector.project(
      targetQuantity: 1,
      mainHub: .jita,
      referencePlan: plan,
      selectedPlan: plan,
      warehouse: warehouse,
      warehouseHasSnapshot: true,
      protectedQuantities: [:],
      reservedQuantities: [:],
      preferences: [:],
      blueprintPortfolio: BlueprintPortfolio(
        inventories: [
          OwnedBlueprintInventory(
            ownerID: 7,
            ownerName: "Builder",
            blueprints: Sourced(
              state: .stale,
              value: [
                OwnedBlueprintInstance(
                  id: blueprintItemID,
                  blueprintTypeID: 802,
                  locationID: containerID,
                  quantity: -1,
                  runs: -1,
                  materialEfficiency: 10,
                  timeEfficiency: 20,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: "retained-fixture"
                  )
                )
              ],
              source: SourceIdentity(
                provider: "ESI",
                version: "retained-fixture"
              ),
              diagnostics: ["latest-refresh-state:unavailable"]
            )
          )
        ]
      ),
      blueprintNames: [801: "Product Blueprint", 802: "Component Blueprint"],
      blueprintContractOffers: [:],
      publicContractCoverageComplete: false,
      inventionDefinitions: [:],
      productionScope: ProductionWarehouseScope(
        locations: [
          ProductionWarehouseLocation(
            locationID: locationID,
            structureName: "Unconfigured structure",
            solarSystemID: 30_000_001,
            solarSystemName: "Test",
            activities: [.manufacturing]
          )
        ]
      )
    )
    let intermediate = try #require(
      tree.nodes.first { $0.typeID == 82 && $0.action == .produce }
    )
    let assessment = try #require(intermediate.blueprint)

    #expect(assessment.recommendation == .useOwnedBPO)
    #expect(assessment.availableActions.contains(.useOwnedBPO))
    #expect(assessment.exactLocationBPOCount == 1)
    #expect(assessment.exactLocationBPOSourceStates == [.stale])
    #expect(assessment.inventoryIsComplete == false)
  }

  @Test
  func bpcContractSelectionCombinesAttributableContractsForRequiredRuns() throws {
    let offers = [
      bpcContract(contractID: 1, runs: 20, price: 100),
      bpcContract(contractID: 2, runs: 20, price: 100),
      bpcContract(contractID: 3, runs: 50, price: 260),
      bpcContract(
        contractID: 4,
        runs: 100,
        price: 1,
        offeredLineCount: 2
      ),
    ]

    let selection = try #require(
      ProductionTreeBPCContractSelector.select(
        requiredRuns: 40,
        from: offers
      )
    )

    #expect(selection.contractCount == 2)
    #expect(selection.coveredRuns == 40)
    #expect(selection.totalPrice == 200)
    #expect(selection.offers.map(\.contractID) == [1, 2])
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
  func strictProductionTreeCostsRequireEveryProducedBlueprintAllocation()
    async throws
  {
    let preference = MaterialProcurementPreference(
      supplyMode: .produce,
      purchaseLocation: .jita
    )
    let unresolved = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: preference,
        requiresCompleteBlueprintCosts: true
      )
    )
    #expect(unresolved.costBreakdown?.totalProductionCost == nil)
    #expect(
      unresolved.warnings.contains {
        $0.code == "industry.blueprint-cost-unresolved"
      }
    )
    // An unresolved Blueprint is never shown or summed as 0 ISK: the
    // Blueprint total, the subtotal and every sale scenario stay unavailable.
    #expect(unresolved.costBreakdown?.blueprintCosts?.unresolvedBlueprintCount == 2)
    #expect(unresolved.costBreakdown?.blueprintCosts?.acceptedTotal == nil)
    #expect(unresolved.costBreakdown?.productionCostBeforeLogistics == nil)
    #expect(unresolved.costBreakdown?.hasConsistentTotal == true)
    #expect(unresolved.productionCostPerOutputUnit == nil)
    #expect(unresolved.immediateSale.totalCost == nil)
    #expect(unresolved.immediateSale.profit == nil)

    let allocations: [Int64: IndustryBlueprintCostAllocation] = [
      801: IndustryBlueprintCostAllocation(
        blueprintTypeID: 801,
        productName: "Choice Product",
        kind: .bpc,
        amount: 10,
        source: "fixture contract"
      ),
      802: IndustryBlueprintCostAllocation(
        blueprintTypeID: 802,
        productName: "Choice Intermediate",
        kind: .bpo,
        amount: 2,
        source: "fixture allocation"
      ),
    ]
    let complete = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: preference,
        blueprintCostAllocations: allocations,
        requiresCompleteBlueprintCosts: true
      )
    )
    #expect(complete.costBreakdown?.blueprintCosts?.total == 12)
    #expect(complete.costBreakdown?.blueprintCosts?.acceptedTotal == 12)
    #expect(complete.costBreakdown?.totalProductionCost != nil)

    let ownedFormula = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0",
      context: intermediateChoiceContext(
        preference: preference,
        intermediateActivity: .reaction,
        blueprintCostAllocations: [
          801: IndustryBlueprintCostAllocation(
            blueprintTypeID: 801,
            productName: "Choice Product",
            kind: .bpo,
            amount: 0,
            source: "fixture owned BPO"
          ),
          802: IndustryBlueprintCostAllocation(
            blueprintTypeID: 802,
            productName: "Choice Intermediate",
            kind: .formula,
            amount: 0,
            source: "fixture owned reaction formula"
          ),
        ],
        requiresCompleteBlueprintCosts: true
      )
    )
    #expect(ownedFormula.costBreakdown?.blueprintCosts?.total == 0)
    #expect(
      ownedFormula.costBreakdown?.blueprintCosts?.entries.contains {
        $0.kind == .formula
      } == true
    )
    #expect(ownedFormula.costBreakdown?.totalProductionCost != nil)
  }

  @Test
  func ownedOriginalCoversRunsBeyondItsPlannedSupply() async throws {
    let preference = MaterialProcurementPreference(
      supplyMode: .produce,
      purchaseLocation: .jita
    )
    // The supply plan was prepared for 2 intermediate runs, the final plan
    // needs 6. An original has unlimited runs, so nothing is short.
    let supplyJob = BlueprintManufacturingJob(
      demandID: BlueprintDemandID(
        requestID: UUID(),
        blueprintTypeID: 802,
        productTypeID: 82,
        nodePath: [81, 82]
      ),
      allocation: BlueprintRunAllocation(
        source: .ownedBPO(itemID: 9_802),
        provenance: .researchedOriginal,
        availableRuns: nil,
        allocatedRuns: 2,
        remainingRuns: nil,
        materialEfficiency: 10,
        timeEfficiency: 20,
        sourceState: .fresh
      ),
      blueprintTypeID: 802,
      productTypeID: 82,
      runs: 2,
      outputQuantity: 2
    )
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 3 0 0",
      context: intermediateChoiceContext(
        preference: preference,
        blueprintSupplyPlans: [
          802: BlueprintSupplyPlan(
            blueprintTypeID: 802,
            productTypeID: 82,
            productName: "Choice Intermediate",
            requiredRuns: 2,
            manufacturingJobs: [supplyJob]
          )
        ]
      )
    )
    #expect(
      !plan.warnings.contains {
        $0.code == "industry.blueprint-supply-insufficient-runs"
      }
    )
    let intermediateJobs = plan.jobs.filter { $0.typeID == 82 }
    #expect(intermediateJobs.reduce(0) { $0 + ($1.runs ?? 0) } == 6)
    #expect(intermediateJobs.allSatisfy { $0.materialEfficiency == 10 })
  }

  @Test
  func contractBPCSupplyChargesWholeContractsCoveringRequiredRuns() throws {
    let requestID = UUID()
    func job(
      _ source: BlueprintSourceReference,
      available: Int,
      allocated: Int,
      price: Double,
      me: Int
    ) -> BlueprintManufacturingJob {
      BlueprintManufacturingJob(
        demandID: BlueprintDemandID(
          requestID: requestID,
          blueprintTypeID: 20_281,
          productTypeID: 20_280,
          nodePath: [20_280]
        ),
        allocation: BlueprintRunAllocation(
          source: source,
          provenance: .contractCopy,
          availableRuns: available,
          allocatedRuns: allocated,
          remainingRuns: available - allocated,
          materialEfficiency: me,
          timeEfficiency: 20,
          sourceState: .fresh,
          acquisitionCost: price
        ),
        blueprintTypeID: 20_281,
        productTypeID: 20_280,
        runs: allocated,
        outputQuantity: Int64(allocated)
      )
    }
    func plan(
      _ jobs: [BlueprintManufacturingJob],
      cost: Double?
    ) -> BlueprintSupplyPlan {
      BlueprintSupplyPlan(
        blueprintTypeID: 20_281,
        productTypeID: 20_280,
        productName: "Siege Module I",
        requiredRuns: 5,
        manufacturingJobs: jobs,
        batchAllocationCost: cost
      )
    }
    // 5 runs: a 3-run BPC fully used plus a 3-run BPC with 2 used runs.
    // Both Contracts are bought whole, so the unused run is still paid.
    let covered = plan(
      [
        job(.contractBPC(recordID: 1), available: 3, allocated: 3,
          price: 3_500_000, me: 8),
        job(.contractBPC(recordID: 2), available: 3, allocated: 2,
          price: 3_980_000, me: 10),
      ],
      cost: 7_480_000
    )
    let allocation = try #require(
      ProductionTreeBlueprintCostProjector.contractBPCAllocations(
        supplyPlans: [20_281: covered]
      )[20_281]
    )
    #expect(allocation.kind == .bpc)
    #expect(allocation.amount == 7_480_000)

    let shortfall = plan(
      [job(.contractBPC(recordID: 1), available: 3, allocated: 3,
        price: 3_500_000, me: 8)],
      cost: 3_500_000
    )
    let mixed = plan(
      [
        job(.contractBPC(recordID: 1), available: 3, allocated: 3,
          price: 3_500_000, me: 8),
        job(.ownedBPC(itemID: 9), available: 2, allocated: 2,
          price: 0, me: 10),
      ],
      cost: 3_500_000
    )
    let unpriced = plan(covered.manufacturingJobs, cost: nil)
    for unresolved in [shortfall, mixed, unpriced] {
      #expect(
        ProductionTreeBlueprintCostProjector.contractBPCAllocations(
          supplyPlans: [20_281: unresolved]
        ).isEmpty
      )
    }
  }

  @Test
  func blueprintCostProjectorPreservesBPCAndBPOTreatment() throws {
    let allocations = ProductionTreeBlueprintCostProjector.allocations(
      for: [
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 900,
          productName: "Contract Product",
          action: .buyContractBPC,
          attributableBPCContractPrice: 7_000_000,
          attributableBPCContractCount: 2,
          attributableBPCContractRuns: 14
        ),
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 901,
          productName: "Owned Product",
          action: .useOwnedBPO,
          manualAmount: 250_000
        ),
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 902,
          productName: "Missing BPC Cost",
          action: .useOwnedBPC
        ),
      ]
    )

    let contract = try #require(allocations[900])
    #expect(contract.kind == .bpc)
    #expect(contract.amount == 7_000_000)
    #expect(contract.source.contains("2 exact Main Hub"))
    let owned = try #require(allocations[901])
    #expect(owned.kind == .bpo)
    #expect(owned.amount == 250_000)
    let ownedBPCWithoutCost = try #require(allocations[902])
    #expect(ownedBPCWithoutCost.kind == .bpc)
    #expect(ownedBPCWithoutCost.amount == 0)
    #expect(
      ownedBPCWithoutCost.source
        == ProductionTreeBlueprintCostProjector.ownedWithoutEnteredCostSource)
    let notOwned = ProductionTreeBlueprintCostProjector.allocations(
      for: [
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 903, productName: "Owned BPO", action: .useOwnedBPO),
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 904, productName: "Invented", action: .invent),
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 905, productName: "Copied", action: .copyOwnedBPO),
        ProductionTreeBlueprintCostChoice(
          blueprintTypeID: 906, productName: "Missing", action: .unavailable),
      ]
    )
    #expect(notOwned[903]?.amount == 0 && notOwned[903]?.kind == .bpo)
    #expect(notOwned[904] == nil)
    #expect(notOwned[905] == nil)
    #expect(notOwned[906] == nil)
  }

  @Test
  func strictBlueprintCostsAcceptManualTopLevelInput() async throws {
    let plan = try await IndustryPlanner().plan(
      input: "Choice Product 1 0 0 BPC 42",
      context: intermediateChoiceContext(
        preference: MaterialProcurementPreference(
          supplyMode: .buy,
          purchaseLocation: .jita
        ),
        blueprintCostAllocations: [
          802: IndustryBlueprintCostAllocation(
            blueprintTypeID: 802,
            productName: "Unused Intermediate",
            kind: .bpo,
            amount: 1_000,
            source: "unused fixture allocation"
          )
        ],
        requiresCompleteBlueprintCosts: true
      )
    )

    #expect(plan.costBreakdown?.blueprintCosts?.total == 42)
    #expect(plan.costBreakdown?.totalProductionCost != nil)
    #expect(
      !plan.warnings.contains {
        $0.code == "industry.blueprint-cost-unresolved"
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
    #expect(plan.plannedOutputUnits == 1)
    #expect(plan.productionCostPerOutputUnit == 8_001_025)
    #expect(plan.immediateSale.grossRevenue == 250_000_000)
    #expect(plan.immediateSale.salesTax == 12_500_000)
    #expect(plan.immediateSale.brokerFee == 0)
    #expect(plan.immediateSale.grossOrNetRevenue == 237_500_000)
    #expect(plan.listedSale.grossRevenue == 300_000_000)
    #expect(plan.listedSale.salesTax == 15_000_000)
    #expect(plan.listedSale.brokerFee == 3_000_000)
    #expect(plan.listedSale.grossOrNetRevenue == 282_000_000)

    let multiUnitPlan = try await IndustryPlanner().plan(
      input: "Finished Product 8 0 0 BPC 7000000",
      context: context
    )
    let multiUnitLandedTotal = try #require(
      multiUnitPlan.costBreakdown?.totalProductionCost
    )
    let multiUnitCost = try #require(
      multiUnitPlan.productionCostPerOutputUnit
    )
    #expect(multiUnitPlan.plannedOutputUnits == 8)
    #expect(
      abs(multiUnitCost - multiUnitLandedTotal / 8) < 0.000_001
    )
  }

  @Test
  func roundTripLogisticsReturnsFinishedProductsToTheMainHub()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 601,
      productTypeID: 61,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: [BlueprintMaterial(typeID: 62, quantity: 2)],
        products: [
          BlueprintProduct(typeID: 61, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let mainConfiguration = TradingLocationConfiguration(
      location: .jita,
      publicContractFeeRate: 0.03
    )
    let homeConfiguration = TradingLocationConfiguration(
      location: .amarr,
      publicContractFeeRate: 0.01
    )
    let coalitionLocation = ProcurementLocation(
      id: "structure:1040000000001",
      name: "Coalition Keepstar",
      locationID: 1_040_000_000_001,
      kind: .playerStructure,
      solarSystemID: 30_000_002,
      regionID: 10_000_001,
      ownerCorporationID: 98_000_001
    )
    let coalitionConfiguration = TradingLocationConfiguration(
      location: coalitionLocation,
      publicContractFeeRate: 0.02
    )
    let basis = ProductionBasis(
      tradingLocations: [
        mainConfiguration,
        homeConfiguration,
        coalitionConfiguration,
      ],
      mainTradingLocationID: mainConfiguration.id,
      homeTradingLocationID: homeConfiguration.id,
      coalitionTradingLocationID: coalitionConfiguration.id,
      logistics: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        includeOutboundProducts: false,
        productionLocationName: ProcurementLocation.amarr.name,
        homeTradeHub: .jita,
        iskPerCubicMeter: 1
      )
    )
    let mainMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        61: [
          makeOrder(typeID: 61, side: .buy, price: 100),
          makeOrder(typeID: 61, side: .sell, price: 110),
        ],
        62: [makeOrder(typeID: 62, side: .sell, price: 2)],
      ],
      source: source
    )
    let homeMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: ProcurementLocation.amarr.regionID ?? 0,
      locationID: ProcurementLocation.amarr.locationID ?? 0,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        61: [
          makeOrder(
            typeID: 61,
            side: .buy,
            price: 80,
            locationID: ProcurementLocation.amarr.locationID ?? 0,
            systemID: ProcurementLocation.amarr.solarSystemID ?? 0
          ),
          makeOrder(
            typeID: 61,
            side: .sell,
            price: 120,
            locationID: ProcurementLocation.amarr.locationID ?? 0,
            systemID: ProcurementLocation.amarr.solarSystemID ?? 0
          ),
        ]
      ],
      source: source
    )
    let coalitionMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: coalitionLocation.regionID ?? 0,
      locationID: coalitionLocation.locationID ?? 0,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        61: [
          makeOrder(
            typeID: 61,
            side: .buy,
            price: 70,
            locationID: coalitionLocation.locationID ?? 0,
            systemID: coalitionLocation.solarSystemID ?? 0
          ),
          makeOrder(
            typeID: 61,
            side: .sell,
            price: 130,
            locationID: coalitionLocation.locationID ?? 0,
            systemID: coalitionLocation.solarSystemID ?? 0
          ),
        ]
      ],
      source: source
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [61: "Round Trip Product", 62: "Round Trip Raw"],
        definitions: [61: product],
        packagedVolumes: [61: 10, 62: 5]
      ),
      market: mainMarket,
      homeMarket: homeMarket,
      coalitionMarket: coalitionMarket,
      mainContractReferences: publicContractReference(
        typeID: 61,
        unitPrice: 10_000,
        location: .jita
      ),
      homeContractReferences: publicContractReference(
        typeID: 61,
        unitPrice: 20_000,
        location: .amarr
      ),
      coalitionContractReferences: publicContractReference(
        typeID: 61,
        unitPrice: 30_000,
        location: coalitionLocation
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
      defaultPurchaseLocation: .jita,
      sdeBuild: 1,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      homeSalesTaxRate: 0.02,
      homeBrokerFeeRate: 0.03,
      coalitionSalesTaxRate: 0.04,
      coalitionBrokerFeeRate: 0.02
    )

    let plan = try await IndustryPlanner().plan(
      input: "Round Trip Product 1 0 0",
      context: context
    )
    let inboundLogistics = try #require(plan.costBreakdown?.logistics)
    let inbound = try #require(
      inboundLogistics.legs.first { $0.kind == .inboundMaterials }
    )
    let outboundLogistics = try #require(
      plan.immediateSale.outboundLogistics
    )
    let outbound = try #require(
      outboundLogistics.legs.first { $0.kind == .outboundProducts }
    )
    let homeImmediateSale = try #require(plan.homeImmediateSale)
    let homeListedSale = try #require(plan.homeListedSale)
    let homeContractSale = try #require(plan.homeContractSale)
    let mainContractSale = try #require(plan.mainContractSale)
    let coalitionImmediateSale = try #require(plan.coalitionImmediateSale)
    let coalitionListedSale = try #require(plan.coalitionListedSale)
    let coalitionContractSale = try #require(plan.coalitionContractSale)

    #expect(inboundLogistics.legs.count == 1)
    #expect(outboundLogistics.legs.count == 1)
    #expect(inbound.origin == ProcurementLocation.jita.name)
    #expect(inbound.destination == ProcurementLocation.amarr.name)
    #expect(outbound.origin == ProcurementLocation.amarr.name)
    #expect(outbound.destination == ProcurementLocation.jita.name)
    #expect(inboundLogistics.total == 1_000_000)
    #expect(outboundLogistics.total == 1_000_000)
    #expect(plan.costBreakdown?.logisticsCost == 1_000_000)
    #expect(plan.immediateSale.outboundLogisticsCost == 1_000_000)
    #expect(plan.listedSale.outboundLogisticsCost == 1_000_000)
    #expect(homeImmediateSale.outboundLogisticsCost == 0)
    #expect(homeListedSale.outboundLogisticsCost == 0)
    #expect(homeContractSale.outboundLogisticsCost == 0)
    #expect(coalitionImmediateSale.outboundLogisticsCost == 1_000_000)
    #expect(coalitionListedSale.outboundLogisticsCost == 1_000_000)
    #expect(coalitionContractSale.outboundLogisticsCost == 1_000_000)
    #expect(
      plan.immediateSale.inboundLogisticsAssessment?.status == .calculated
    )
    #expect(
      plan.immediateSale.outboundLogisticsAssessment?.status == .calculated
    )
    #expect(
      homeContractSale.outboundLogisticsAssessment?.status == .notRequired
    )
    #expect(
      coalitionContractSale.outboundLogisticsAssessment?.status == .calculated
    )
    #expect(
      plan.immediateSale.totalCost
        == (plan.costBreakdown?.totalProductionCost ?? 0) + 1_000_000
    )
    #expect(homeImmediateSale.totalCost == plan.costBreakdown?.totalProductionCost)
    #expect(plan.immediateSale.grossRevenue == 100)
    #expect(homeImmediateSale.grossRevenue == 80)
    #expect(homeImmediateSale.salesTax == 1.6)
    #expect(homeListedSale.grossRevenue == 120)
    #expect(homeListedSale.salesTax == 2.4)
    #expect(abs((homeListedSale.brokerFee ?? 0) - 3.6) < 0.000_001)
    #expect(mainContractSale.grossRevenue == 10_000)
    #expect(mainContractSale.salesTax == 0)
    #expect(mainContractSale.brokerFee == 0)
    #expect(mainContractSale.contractFee == 300)
    #expect(mainContractSale.grossOrNetRevenue == 9_700)
    #expect(homeContractSale.grossRevenue == 20_000)
    #expect(homeContractSale.salesTax == 0)
    #expect(homeContractSale.brokerFee == 0)
    #expect(homeContractSale.contractFee == 200)
    #expect(homeContractSale.grossOrNetRevenue == 19_800)
    #expect(homeContractSale.totalCost == plan.costBreakdown?.totalProductionCost)
    #expect(coalitionImmediateSale.grossRevenue == 70)
    #expect(abs((coalitionImmediateSale.salesTax ?? 0) - 2.8) < 0.000_001)
    #expect(coalitionImmediateSale.brokerFee == 0)
    #expect(coalitionListedSale.grossRevenue == 130)
    #expect(abs((coalitionListedSale.salesTax ?? 0) - 5.2) < 0.000_001)
    #expect(abs((coalitionListedSale.brokerFee ?? 0) - 2.6) < 0.000_001)
    #expect(coalitionContractSale.grossRevenue == 30_000)
    #expect(coalitionContractSale.salesTax == 0)
    #expect(coalitionContractSale.brokerFee == 0)
    #expect(coalitionContractSale.contractFee == 600)
    #expect(coalitionContractSale.grossOrNetRevenue == 29_400)
    #expect(
      coalitionContractSale.totalCost
        == (plan.costBreakdown?.totalProductionCost ?? 0) + 1_000_000
    )

    var jumpBasis = basis
    jumpBasis.logistics.jumpFreighter = JumpFreighterLogisticsConfiguration(
      isEnabled: true,
      hull: .ark,
      usableCargoCapacityM3: 350_000
    )
    var jumpOrders = mainMarket.ordersByType
    for (index, isotope) in JumpFuelIsotope.allCases.enumerated() {
      jumpOrders[isotope.typeID] = [
        makeOrder(
          typeID: isotope.typeID,
          side: .sell,
          price: Double(index + 1)
        )
      ]
    }
    let jumpMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: mainMarket.regionID,
      locationID: mainMarket.locationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: jumpOrders,
      source: source
    )
    let pilot = JumpFreighterPilot(
      characterID: 42,
      characterName: "Xanira",
      jumpDriveCalibrationLevel: 5,
      jumpFuelConservationLevel: 5,
      jumpFreightersLevel: 5,
      skillSource: source
    )
    let routeURL = try #require(
      URL(string: "https://evemaps.dotlan.net/jump/Ark,555/Amarr:C-J6MT")
    )
    let route = JumpRouteSnapshot(
      request: JumpRouteRequest(
        originSystemName: "Amarr",
        destinationSystemName: "C-J6MT",
        hull: .ark,
        pilot: pilot
      ),
      legs: [
        JumpRouteLeg(
          originSystemName: "Amarr",
          destinationSystemName: "C-J6MT",
          distanceLightYears: 20.314,
          isotopeQuantity: 44_690
        )
      ],
      totalDistanceLightYears: 20.314,
      isotope: .helium,
      isotopeQuantityPerFlight: 44_690,
      isotopeVolumePerFlightM3: 1_341,
      sourceURL: routeURL,
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )
    let jumpContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: jumpBasis,
      catalog: FixtureCatalog(
        names: [61: "Round Trip Product", 62: "Round Trip Raw"],
        definitions: [61: product],
        packagedVolumes: [61: 10, 62: 5]
      ),
      market: jumpMarket,
      homeMarket: homeMarket,
      coalitionMarket: coalitionMarket,
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
      defaultPurchaseLocation: .jita,
      sdeBuild: 1,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      homeSalesTaxRate: 0.02,
      homeBrokerFeeRate: 0.03,
      coalitionSalesTaxRate: 0.04,
      coalitionBrokerFeeRate: 0.02,
      jumpFreighterRoute: Sourced(
        state: .fresh,
        value: route,
        source: route.source
      )
    )
    let jumpPlan = try await IndustryPlanner().plan(
      input: "Round Trip Product 1 0 0",
      context: jumpContext
    )
    let jumpAssessment = try #require(
      jumpPlan.coalitionImmediateSale?.outboundLogisticsAssessment
    )
    #expect(jumpAssessment.status == .calculated)
    #expect(jumpAssessment.jumpFreighter?.flights.count == 1)
    #expect(jumpAssessment.jumpFreighter?.averageIsotopeUnitPrice == 2.5)
    #expect(jumpAssessment.cost == 111_725)
    #expect(jumpPlan.coalitionImmediateSale?.outboundLogisticsCost == 111_725)

    let capitalProduct = CapitalSelfJumpProduct(
      typeID: 61,
      name: "Rorqual",
      groupName: "Capital Industrial Ship"
    )
    let capitalRequest = CapitalJumpRouteRequest(
      originSystemName: "Amarr",
      destinationSystemName: "C-J6MT",
      capitalTypeID: capitalProduct.typeID,
      capitalName: capitalProduct.name,
      pilot: pilot
    )
    let capitalRoute = CapitalJumpRouteSnapshot(
      request: capitalRequest,
      legs: [
        JumpRouteLeg(
          originSystemName: "Amarr",
          destinationSystemName: "C-J6MT",
          distanceLightYears: 20.314,
          isotopeQuantity: 100
        )
      ],
      totalDistanceLightYears: 20.314,
      isotope: .oxygen,
      isotopeQuantityPerHull: 100,
      isotopeVolumePerHullM3: 3,
      sourceURL: try #require(
        URL(string: "https://evemaps.dotlan.net/jump/Rorqual,550/Amarr:C-J6MT")
      ),
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )
    let capitalContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: jumpBasis,
      catalog: FixtureCatalog(
        names: [61: "Rorqual", 62: "Round Trip Raw"],
        definitions: [61: product],
        classifications: [
          61: IndustryItemClassification(
            categoryName: "Ship",
            groupName: "Capital Industrial Ship",
            manufacturingCategory: .capital
          )
        ],
        packagedVolumes: [61: 1_300_000, 62: 5]
      ),
      market: jumpMarket,
      homeMarket: homeMarket,
      coalitionMarket: coalitionMarket,
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
      defaultPurchaseLocation: .jita,
      sdeBuild: 1,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      homeSalesTaxRate: 0.02,
      homeBrokerFeeRate: 0.03,
      coalitionSalesTaxRate: 0.04,
      coalitionBrokerFeeRate: 0.02,
      // This retained cargo route must not be used for the produced capital.
      jumpFreighterRoute: Sourced(
        state: .fresh,
        value: route,
        source: route.source
      ),
      capitalJumpRoutes: [
        capitalProduct.typeID: Sourced(
          state: .fresh,
          value: capitalRoute,
          source: capitalRoute.source
        )
      ]
    )
    let capitalPlan = try await IndustryPlanner().plan(
      input: "Rorqual 1 0 0",
      context: capitalContext
    )
    let capitalAssessment = try #require(
      capitalPlan.coalitionImmediateSale?.outboundLogisticsAssessment
    )
    #expect(capitalAssessment.status == .calculated)
    #expect(capitalAssessment.jumpFreighter == nil)
    #expect(capitalAssessment.selfJumpingCapitals?.jumps.count == 1)
    #expect(capitalAssessment.selfJumpingCapitals?.jumps.first?.quantity == 1)
    #expect(capitalAssessment.cost == 250)
  }

  @Test
  func identicalMainAndHomeHubRemoveAllTransportWithoutRequiringARate()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let product = BlueprintDefinition(
      blueprintTypeID: 611,
      productTypeID: 63,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 1,
        materials: [BlueprintMaterial(typeID: 64, quantity: 1)],
        products: [BlueprintProduct(typeID: 63, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let sharedConfiguration = TradingLocationConfiguration(location: .jita)
    let basis = ProductionBasis(
      tradingLocations: [sharedConfiguration],
      mainTradingLocationID: sharedConfiguration.id,
      homeTradingLocationID: sharedConfiguration.id,
      logistics: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        iskPerCubicMeter: nil
      )
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        63: [
          makeOrder(typeID: 63, side: .buy, price: 10),
          makeOrder(typeID: 63, side: .sell, price: 11),
        ],
        64: [makeOrder(typeID: 64, side: .sell, price: 1)],
      ],
      source: source
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [63: "Local Product", 64: "Local Raw"],
        definitions: [63: product],
        packagedVolumes: [63: 1, 64: 1]
      ),
      market: market,
      homeMarket: market,
      adjustedPrices: [
        64: AdjustedPrice(typeID: 64, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      sdeBuild: 1,
      salesTaxRate: 0,
      brokerFeeRate: 0,
      homeSalesTaxRate: 0,
      homeBrokerFeeRate: 0
    )

    let plan = try await IndustryPlanner().plan(
      input: "Local Product 1 0 0",
      context: context
    )

    #expect(basis.mainAndHomeAreIdentical)
    #expect(plan.costBreakdown?.logistics == nil)
    #expect(plan.costBreakdown?.logisticsCost == 0)
    #expect(plan.immediateSale.outboundLogistics == nil)
    #expect(plan.immediateSale.outboundLogisticsCost == 0)
    #expect(plan.homeImmediateSale?.outboundLogisticsCost == 0)
    #expect(plan.immediateSale.totalCost == plan.homeImmediateSale?.totalCost)
    #expect(
      !plan.warnings.contains { $0.code == "logistics.missing-volume-rate" }
    )
  }

  @Test
  func restrictedCapitalCannotReturnToMainButRemainsSellableAtHome()
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
        materials: [BlueprintMaterial(typeID: 72, quantity: 1)],
        products: [BlueprintProduct(typeID: 71, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let mainConfiguration = TradingLocationConfiguration(location: .jita)
    let homeLocation = ProcurementLocation(
      id: "structure:1040000000071",
      name: "Nullsec Home Keepstar",
      locationID: 1_040_000_000_071,
      kind: .playerStructure,
      solarSystemID: 30_000_071,
      regionID: 10_000_071
    )
    let homeConfiguration = TradingLocationConfiguration(
      location: homeLocation
    )
    let basis = ProductionBasis(
      tradingLocations: [mainConfiguration, homeConfiguration],
      mainTradingLocationID: mainConfiguration.id,
      homeTradingLocationID: homeConfiguration.id,
      logistics: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: homeLocation.name,
        homeTradeHub: .jita,
        iskPerCubicMeter: 1
      )
    )
    let mainMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        71: [makeOrder(typeID: 71, side: .buy, price: 1_000_000)],
        72: [makeOrder(typeID: 72, side: .sell, price: 1)],
      ],
      source: source
    )
    let homeMarket = MarketOrderSnapshot(
      id: UUID(),
      regionID: homeLocation.regionID ?? 0,
      locationID: homeLocation.locationID ?? 0,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        71: [
          makeOrder(
            typeID: 71,
            side: .buy,
            price: 2_000_000,
            locationID: homeLocation.locationID ?? 0,
            systemID: homeLocation.solarSystemID ?? 0
          ),
          makeOrder(
            typeID: 71,
            side: .sell,
            price: 2_100_000,
            locationID: homeLocation.locationID ?? 0,
            systemID: homeLocation.solarSystemID ?? 0
          ),
        ]
      ],
      source: source
    )
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [71: "Fixture Dreadnought", 72: "Capital Material"],
        definitions: [71: product],
        classifications: [
          71: IndustryItemClassification(
            categoryName: "Ship",
            groupName: "Dreadnought",
            manufacturingCategory: .capital
          )
        ],
        packagedVolumes: [71: 100_000, 72: 1]
      ),
      market: mainMarket,
      homeMarket: homeMarket,
      homeContractReferences: publicContractReference(
        typeID: 71,
        unitPrice: 2_200_000,
        location: homeLocation
      ),
      adjustedPrices: [
        72: AdjustedPrice(typeID: 72, adjustedPrice: 1, averagePrice: 1)
      ],
      systemIndices: [
        IndustrySystemIndex(
          solarSystemID: EVEConstants.jitaSystemID,
          activity: .manufacturing,
          costIndex: 0
        )
      ],
      sdeBuild: 1,
      salesTaxRate: 0.05,
      brokerFeeRate: 0.01,
      homeSalesTaxRate: 0.05,
      homeBrokerFeeRate: 0.01
    )

    let plan = try await IndustryPlanner().plan(
      input: "Fixture Dreadnought 1 0 0",
      context: context
    )
    let homeImmediate = try #require(plan.homeImmediateSale)
    let homeContract = try #require(plan.homeContractSale)

    #expect(plan.immediateSale.grossRevenue == nil)
    #expect(plan.listedSale.grossRevenue == nil)
    #expect(plan.listedSale.salesTaxRate == 0.05)
    #expect(plan.listedSale.brokerFeeRate == nil)
    #expect(plan.listedSale.brokerFeeIsApplicable == false)
    #expect(
      plan.immediateSale.outboundLogisticsAssessment?.status == .prohibited
    )
    #expect(plan.immediateSale.totalCost == nil)
    #expect(plan.immediateSale.profit == nil)
    #expect(homeImmediate.grossRevenue == 2_000_000)
    #expect(homeImmediate.outboundLogisticsAssessment?.status == .notRequired)
    #expect(homeContract.grossRevenue == 2_200_000)
    #expect(homeContract.salesTax == 0)
    #expect(homeContract.brokerFee == 0)
    #expect(homeContract.contractFee == nil)
    #expect(homeContract.grossOrNetRevenue == 2_200_000)
    #expect(homeContract.profit != nil)
    #expect(homeContract.hasPendingPublicContractFee)
    let overviewProjection = try #require(
      ProductionOverviewProjector.projection(
        for: plan.requests[0].id,
        in: plan
      )
    )
    #expect(overviewProjection.salesTaxRate == 0.05)
    #expect(overviewProjection.brokerFeeRate == nil)
    #expect(!overviewProjection.brokerFeeIsApplicable)
    var legacyObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(plan)
      ) as? [String: Any]
    )
    for scenarioKey in [
      "immediateSale",
      "listedSale",
      "homeImmediateSale",
      "homeListedSale",
    ] {
      guard var scenario = legacyObject[scenarioKey] as? [String: Any] else {
        continue
      }
      scenario.removeValue(forKey: "salesTaxRate")
      scenario.removeValue(forKey: "brokerFeeRate")
      scenario.removeValue(forKey: "brokerFeeIsApplicable")
      legacyObject[scenarioKey] = scenario
    }
    let legacyPlan = try JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: JSONSerialization.data(withJSONObject: legacyObject)
    )
    let legacyProjection = try #require(
      ProductionOverviewProjector.projection(
        for: legacyPlan.requests[0].id,
        in: legacyPlan
      )
    )
    #expect(legacyProjection.salesTaxRate == 0.05)
    #expect(legacyProjection.brokerFeeRate == nil)
    #expect(!legacyProjection.brokerFeeIsApplicable)
    #expect(
      plan.warnings.contains { $0.code == "logistics.capital-highsec-prohibited" }
    )
  }

  @Test
  func freightersRemainHighSecurityTransferExceptions() {
    let restricted = PlanNode(
      id: UUID(),
      typeID: 1,
      name: "Fixture Dreadnought",
      requestedQuantity: 1,
      requiredQuantity: 1,
      action: .produce,
      activity: .manufacturing,
      runs: 1,
      materialEfficiency: 0,
      timeEfficiency: 0,
      manufacturingCategory: .capital,
      sourceCategory: "Ship",
      sourceGroup: "Dreadnought",
      children: [],
      topLevelRequestID: UUID()
    )
    let freighter = PlanNode(
      id: UUID(),
      typeID: 2,
      name: "Fixture Freighter",
      requestedQuantity: 1,
      requiredQuantity: 1,
      action: .produce,
      activity: .manufacturing,
      runs: 1,
      materialEfficiency: 0,
      timeEfficiency: 0,
      manufacturingCategory: .capital,
      sourceCategory: "Ship",
      sourceGroup: "Freighter",
      children: [],
      topLevelRequestID: UUID()
    )
    let jumpFreighter = PlanNode(
      id: UUID(),
      typeID: 3,
      name: "Fixture Jump Freighter",
      requestedQuantity: 1,
      requiredQuantity: 1,
      action: .produce,
      activity: .manufacturing,
      runs: 1,
      materialEfficiency: 0,
      timeEfficiency: 0,
      manufacturingCategory: .capital,
      sourceCategory: "Ship",
      sourceGroup: "Jump Freighter",
      children: [],
      topLevelRequestID: UUID()
    )

    #expect(HighSecurityCapitalTransferPolicy.isRestrictedCapital(restricted))
    #expect(!HighSecurityCapitalTransferPolicy.isRestrictedCapital(freighter))
    #expect(!HighSecurityCapitalTransferPolicy.isRestrictedCapital(jumpFreighter))
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
          facilityTaxRate: 0,
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

    // The same cheaper purchase is impossible once the packaged item exceeds the 350,000 m³
    // transport limit (e.g. a freighter hull): the component must be built at the facility.
    let oversizedContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: FixtureCatalog(
        names: [91: "Product", 92: "Component", 93: "Raw"],
        definitions: [91: product, 92: component],
        packagedVolumes: [92: 400_000, 93: 1]
      ),
      market: buyContext.market,
      adjustedPrices: buyContext.adjustedPrices,
      systemIndices: buyContext.systemIndices,
      defaultPurchaseLocation: .jita,
      sdeBuild: 1
    )
    let oversizedPlan = try await IndustryPlanner().plan(
      input: "Product 1 0 0",
      context: oversizedContext
    )
    let oversizedAnalysis = try #require(
      oversizedPlan.materials.first { $0.typeID == 92 }?.makeOrBuyAnalysis
    )
    #expect(oversizedAnalysis.recommendation == .produce)
    #expect(oversizedAnalysis.purchaseTotalCost == nil)
    #expect(oversizedAnalysis.purchaseLogisticsCost == nil)
    #expect(oversizedAnalysis.savings == nil)
    #expect(oversizedAnalysis.buildTotalCost == 5_500_000.36)
    #expect(
      oversizedAnalysis.warnings.contains { $0.code == "make-or-buy.purchase-not-transportable" })
    let oversizedApplication = MakeOrBuyRecommendationApplication(
      materials: oversizedPlan.materials,
      existingPreferences: [:],
      mainHub: .jita
    )
    #expect(oversizedApplication.preferences[92]?.supplyMode == .produce)
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
  func tenRepackagedHulksUseOne37500CubicMeterContract() throws {
    let result = LogisticsCostCalculator.calculateLegs(
      kind: .outboundProducts,
      origin: "Production",
      destination: "Main Hub",
      cargo: [
        LogisticsCargoItem(
          typeID: 22_544,
          quantity: 10,
          collateral: 100_000_000,
          packagedVolumePerUnit: 3_750
        )
      ],
      iskPerCubicMeter: 100,
      maximumContractVolumeM3: 350_000
    )

    #expect(result.legs.count == 1)
    let leg = try #require(result.legs.first)
    #expect(leg.contractCount == 1)
    #expect(leg.cargoVolumeM3 == 37_500)
    #expect(leg.volumeCharge == 3_750_000)
    #expect(leg.roundedCharge == 4_000_000)
    #expect(result.warnings.isEmpty)
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
    #expect(
      logistics.legs.flatMap(\.cargoItems).map(\.name)
        == ["Bulky Material", "Bulky Material"]
    )
    #expect(
      logistics.legs.flatMap(\.cargoItems).reduce(0) { $0 + $1.quantity }
        == 383
    )
    #expect(
      zip(logistics.legs, logistics.legs.flatMap(\.cargoItems)).allSatisfy {
        pair in
        abs(pair.0.cargoVolumeM3 - pair.1.volumeM3) < 0.000_001
      }
    )
    #expect(logistics.total == 5_000_000)
    #expect(
      !plan.warnings.contains { $0.code == "logistics.contracts-split" }
    )
    #expect(plan.immediateSale.inboundLogisticsAssessment?.reason == nil)
  }

  @Test
  func decodesHistoricalLogisticsLegWithoutCargoLines() throws {
    let leg = LogisticsCostLeg(
      kind: .inboundMaterials,
      origin: "Jita IV - Moon 4",
      destination: "Darfnor",
      cargoVolumeM3: 1_000,
      collateral: 10_000,
      volumeCharge: 2_000,
      collateralCharge: 50,
      chargedBy: .volume,
      unroundedCharge: 2_000,
      roundedCharge: 1_000_000,
      cargo: [
        LogisticsCargoLine(
          typeID: 34,
          name: "Tritanium",
          quantity: 10_000,
          volumeM3: 1_000,
          collateral: 10_000
        )
      ]
    )
    let encoded = try JSONEncoder().encode(leg)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "cargo")

    let historical = try JSONDecoder().decode(
      LogisticsCostLeg.self,
      from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(historical.cargo == nil)
    #expect(historical.cargoItems.isEmpty)
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
      packagedVolumes: [61: 350_001, 62: 350_001]
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
      sdeBuild: 1,
      salesTaxRate: 0,
      brokerFeeRate: 0
    )

    let plan = try await IndustryPlanner().plan(
      input: "Oversized Product 1 0 0",
      context: context
    )

    #expect(plan.costBreakdown?.logistics == nil)
    #expect(plan.costBreakdown?.totalProductionCost == nil)
    #expect(plan.productionCostPerOutputUnit == nil)
    #expect(
      plan.immediateSale.inboundLogisticsAssessment?.status
        == .manualTransferRequired
    )
    #expect(
      plan.immediateSale.outboundLogisticsAssessment?.status
        == .manualTransferRequired
    )
    #expect(
      plan.immediateSale.totalCost
        == plan.costBreakdown?.productionCostBeforeLogistics
    )
    #expect(plan.immediateSale.profit != nil)
    #expect(plan.immediateSale.margin != nil)
    #expect(plan.immediateSale.roi != nil)
    #expect(plan.immediateSale.hasPendingManualTransportCost)
    #expect(
      plan.warnings.contains {
        $0.code == "logistics.single-item-volume-exceeded"
          && $0.severity == .warning
          && $0.message.contains("too large for a courier contract")
          && !$0.message.hasPrefix("Type ")
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
    intermediateSecondDepth: Int64 = 100,
    intermediateActivity: BlueprintActivityDefinition.Kind = .manufacturing,
    directRawQuantity: Int64 = 0,
    blueprintCostAllocations: [Int64: IndustryBlueprintCostAllocation] = [:],
    requiresCompleteBlueprintCosts: Bool = false,
    productionEfficiencies: [Int64: IndustryProductionEfficiency] = [:],
    blueprintSupplyPlans: [Int64: BlueprintSupplyPlan] = [:]
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
      volumeRemaining: intermediateSecondDepth,
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
        definitions: [81: product, 82: intermediate],
        classifications: [
          81: IndustryItemClassification(
            categoryName: "Ship",
            groupName: "Cruiser",
            manufacturingCategory: .small
          ),
          82: IndustryItemClassification(
            categoryName: "Material",
            groupName: "Construction Components",
            manufacturingCategory: .module,
            techLevel: 2
          ),
        ]
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
      sdeBuild: 1,
      blueprintCostAllocations: blueprintCostAllocations,
      requiresCompleteBlueprintCosts: requiresCompleteBlueprintCosts,
      productionEfficiencies: productionEfficiencies,
      blueprintSupplyPlans: blueprintSupplyPlans
    )
  }

  private func makeOrder(
    typeID: Int64,
    side: MarketOrderSide,
    price: Double,
    locationID: Int64 = EVEConstants.jitaIV4StationID,
    systemID: Int64 = EVEConstants.jitaSystemID
  ) -> MarketOrder {
    MarketOrder(
      id: Int64.random(in: 1...Int64.max),
      typeID: typeID,
      locationID: locationID,
      systemID: systemID,
      side: side,
      price: price,
      volumeRemaining: 1_000_000,
      minimumVolume: 1,
      issued: .now
    )
  }

  @Test
  func compressedOreUsesTheBestCharacterAndCheaperCompleteRoute()
    async throws
  {
    let source = SourceIdentity(provider: "fixture", version: "refining")
    let oreSkillTypeID: Int64 = 12_104
    let mineralTypeID: Int64 = 34
    let surplusMineralTypeID: Int64 = 16_001
    let oreTypeID: Int64 = 28_417
    let product = BlueprintDefinition(
      blueprintTypeID: 9_001,
      productTypeID: 9_000,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [
          BlueprintMaterial(typeID: mineralTypeID, quantity: 1_000)
        ],
        products: [
          BlueprintProduct(typeID: 9_000, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let compressedOre = CompressedOreOption(
      typeID: oreTypeID,
      name: "Compressed Veldspar",
      portionSize: 1,
      packagedVolume: nil,
      reprocessingSkillTypeID: oreSkillTypeID,
      kind: .asteroidOre,
      outputs: [
        ReprocessingMaterialOutput(typeID: mineralTypeID, quantity: 100),
        ReprocessingMaterialOutput(
          typeID: surplusMineralTypeID,
          quantity: 25
        ),
      ],
      source: source
    )
    let catalog = FixtureCatalog(
      names: [
        9_000: "Refining Test Product",
        mineralTypeID: "Tritanium",
        surplusMineralTypeID: "Fixture Surplus Mineral",
        oreTypeID: "Compressed Veldspar",
      ],
      definitions: [9_000: product],
      packagedVolumes: [mineralTypeID: 1_000, oreTypeID: 0.15],
      compressedOre: [compressedOre]
    )
    let volumeCatalog = PackagedVolumeSnapshotCatalog(
      base: catalog,
      packagedVolumes: [mineralTypeID: 1_000, oreTypeID: 0.15]
    )
    var service = IndustryServiceModuleConfiguration()
    service.name = "Standup Reprocessing Facility I"
    service.activities = [.reprocessing]
    service.normalOreYieldMultiplier = 0.5
    service.source = .staticData
    var facility = ConfiguredIndustryStructure(
      name: "Darfnor Refining Tatara",
      kind: .tatara,
      solarSystemID: 30_045_364,
      solarSystemName: "Darfnor",
      securityBand: .lowSecurity,
      reprocessingTaxRate: 0.01,
      serviceModules: [service]
    )
    facility.setReprocessingImplant(.rx804, for: 2)
    let basis = ProductionBasis(
      logistics: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        productionLocationName: "Darfnor",
        marketLocationName: "Jita IV - Moon 4",
        iskPerCubicMeter: 2_000
      ),
      compressedOreRefining: CompressedOreRefiningConfiguration(
        isEnabled: true
      ),
      structures: [facility]
    )
    func capability(
      id: Int64,
      name: String,
      level: Int
    ) -> CharacterCapabilitySnapshot {
      CharacterCapabilitySnapshot(
        character: CharacterIdentity(id: id, name: name),
        cloneState: .omega,
        skills: Sourced(
          state: .fresh,
          value: [
            TrainedSkill(
              skillID: ReprocessingYieldCalculator.reprocessingSkillTypeID,
              trainedLevel: level,
              activeLevel: level,
              skillpoints: 0
            ),
            TrainedSkill(
              skillID:
                ReprocessingYieldCalculator.reprocessingEfficiencySkillTypeID,
              trainedLevel: level,
              activeLevel: level,
              skillpoints: 0
            ),
            TrainedSkill(
              skillID: oreSkillTypeID,
              trainedLevel: level,
              activeLevel: level,
              skillpoints: 0
            ),
          ],
          source: source
        ),
        standings: Sourced(
          state: .unavailable,
          value: nil,
          source: source
        )
      )
    }
    func market(orePrice: Double) -> MarketOrderSnapshot {
      MarketOrderSnapshot(
        id: UUID(),
        regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: .now,
        state: .fresh,
        ordersByType: [
          mineralTypeID: [
            makeOrder(typeID: mineralTypeID, side: .sell, price: 10)
          ],
          oreTypeID: [
            makeOrder(typeID: oreTypeID, side: .sell, price: orePrice)
          ],
        ],
        source: source
      )
    }
    let capabilities = [
      capability(id: 1, name: "Lower Refiner", level: 3),
      capability(id: 2, name: "Best Refiner", level: 5),
    ]
    let context = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: volumeCatalog,
      market: market(orePrice: 100),
      adjustedPrices: [
        mineralTypeID: AdjustedPrice(
          typeID: mineralTypeID,
          adjustedPrice: 5,
          averagePrice: 5
        ),
        surplusMineralTypeID: AdjustedPrice(
          typeID: surplusMineralTypeID,
          adjustedPrice: 1,
          averagePrice: 1
        ),
      ],
      systemIndices: [],
      sdeBuild: 1,
      characterCapabilities: capabilities
    )

    let plan = try await IndustryPlanner().plan(
      input: "Refining Test Product 1 0 0",
      context: context
    )

    let refining = try #require(plan.compressedOreRefining)
    let purchase = try #require(refining.purchases.first)
    #expect(purchase.oreTypeID == oreTypeID)
    #expect(purchase.character.characterID == 2)
    #expect(purchase.character.oreProcessingLevel == 5)
    #expect(purchase.character.implant == .rx804)
    #expect(
      abs(purchase.facility.baseYieldMultiplier - (0.5 * 1.055))
        < 0.000_001
    )
    #expect(
      abs(
        purchase.yieldMultiplier
          - (0.5 * 1.055 * 1.15 * 1.10 * 1.10 * 1.04)
      ) < 0.000_001
    )
    #expect(refining.savings > 0)
    #expect(refining.selectedLandedCost < refining.directLandedCost)
    #expect(plan.costBreakdown?.refiningCost == refining.refiningFee)
    let demandedOutput = try #require(
      purchase.outputs.first { $0.typeID == mineralTypeID }
    )
    #expect(demandedOutput.name == "Tritanium")
    #expect(demandedOutput.usedInPlan == 1_000)
    #expect(
      demandedOutput.surplusToWarehouse
        == demandedOutput.quantity - 1_000
    )
    let warehouseOutput = try #require(
      purchase.outputs.first { $0.typeID == surplusMineralTypeID }
    )
    #expect(warehouseOutput.name == "Fixture Surplus Mineral")
    #expect(warehouseOutput.usedInPlan == 0)
    #expect(warehouseOutput.surplusToWarehouse == warehouseOutput.quantity)
    let optimizedLogistics = try #require(plan.costBreakdown?.logistics)
    #expect(optimizedLogistics.legs.count == 1)
    #expect(optimizedLogistics.legs.first?.contractCount == 1)
    #expect(optimizedLogistics.legs.first?.destination == "Darfnor")
    #expect(
      optimizedLogistics.legs.first?.cargo?.map(\.typeID) == [oreTypeID]
    )
    #expect(
      abs(
        refining.selectedLandedCost
          - (refining.orePurchaseCost + refining.refiningFee
            + optimizedLogistics.total)
      ) < 0.000_001
    )
    let shoppingList = EVEShoppingList.make(
      from: plan.materials,
      refiningPlan: refining
    )
    #expect(shoppingList.items.contains { $0.typeID == oreTypeID })
    #expect(!shoppingList.items.contains { $0.typeID == mineralTypeID })

    let expensiveContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      productionBasis: basis,
      catalog: volumeCatalog,
      market: market(orePrice: 1_000_000_000),
      adjustedPrices: [
        mineralTypeID: AdjustedPrice(
          typeID: mineralTypeID,
          adjustedPrice: 5,
          averagePrice: 5
        )
      ],
      systemIndices: [],
      sdeBuild: 1,
      characterCapabilities: capabilities
    )
    let directPlan = try await IndustryPlanner().plan(
      input: "Refining Test Product 1 0 0",
      context: expensiveContext
    )
    #expect(directPlan.compressedOreRefining == nil)
    let directLogistics = try #require(directPlan.costBreakdown?.logistics)
    #expect(directLogistics.legs.count == 3)
    #expect(directLogistics.legs.allSatisfy { $0.contractCount == 3 })
    #expect(
      directPlan.warnings.contains {
        $0.code == "refining.no-cheaper-compressed-ore"
      }
    )
    #expect(
      EVEShoppingList.make(from: directPlan.materials).items.contains {
        $0.typeID == mineralTypeID
      }
    )
  }

  /// Main Hub → Home Hub fixture with one mineral, one bulky purchased
  /// material that is shipped either way, and one compressed ore.
  private func compressedOreRouteContext(
    comparisonEnabled: Bool = true,
    oreUnitPrice: Double,
    oreVolumeRemaining: Int64 = 1_000_000
  ) -> IndustryPlanningContext {
    let source = SourceIdentity(provider: "fixture", version: "refining-route")
    let oreSkillTypeID: Int64 = 12_104
    let mineralTypeID: Int64 = 34
    let fillerTypeID: Int64 = 9_100
    let oreTypeID: Int64 = 28_417
    let product = BlueprintDefinition(
      blueprintTypeID: 9_001,
      productTypeID: 9_000,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 10,
        materials: [
          BlueprintMaterial(typeID: mineralTypeID, quantity: 1_000),
          BlueprintMaterial(typeID: fillerTypeID, quantity: 1),
        ],
        products: [
          BlueprintProduct(typeID: 9_000, quantity: 1, probability: nil)
        ]
      ),
      source: source
    )
    let compressedOre = CompressedOreOption(
      typeID: oreTypeID,
      name: "Compressed Veldspar",
      portionSize: 1,
      packagedVolume: 0.15,
      reprocessingSkillTypeID: oreSkillTypeID,
      kind: .asteroidOre,
      outputs: [
        ReprocessingMaterialOutput(typeID: mineralTypeID, quantity: 100)
      ],
      source: source
    )
    let volumes: [Int64: Double] = [
      mineralTypeID: 1,
      fillerTypeID: 1_900,
      oreTypeID: 0.15,
    ]
    let catalog = PackagedVolumeSnapshotCatalog(
      base: FixtureCatalog(
        names: [
          9_000: "Refining Route Product",
          mineralTypeID: "Tritanium",
          fillerTypeID: "Fixture Bulky Material",
          oreTypeID: "Compressed Veldspar",
        ],
        definitions: [9_000: product],
        packagedVolumes: volumes,
        compressedOre: [compressedOre]
      ),
      packagedVolumes: volumes
    )
    var service = IndustryServiceModuleConfiguration()
    service.name = "Standup Reprocessing Facility I"
    service.activities = [.reprocessing]
    service.normalOreYieldMultiplier = 0.5
    service.source = .staticData
    let facility = ConfiguredIndustryStructure(
      name: "Darfnor Refining Tatara",
      kind: .tatara,
      solarSystemID: 30_045_364,
      solarSystemName: "Darfnor",
      securityBand: .lowSecurity,
      reprocessingTaxRate: 0.01,
      serviceModules: [service]
    )
    let basis = ProductionBasis(
      logistics: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        productionLocationName: "Darfnor",
        marketLocationName: "Jita IV - Moon 4",
        iskPerCubicMeter: 1_000
      ),
      compressedOreRefining: CompressedOreRefiningConfiguration(
        isEnabled: comparisonEnabled
      ),
      structures: [facility]
    )
    let skills = [
      ReprocessingYieldCalculator.reprocessingSkillTypeID,
      ReprocessingYieldCalculator.reprocessingEfficiencySkillTypeID,
      oreSkillTypeID,
    ].map {
      TrainedSkill(skillID: $0, trainedLevel: 5, activeLevel: 5, skillpoints: 0)
    }
    let refiner = CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: 1, name: "Fixture Refiner"),
      cloneState: .omega,
      skills: Sourced(state: .fresh, value: skills, source: source),
      standings: Sourced(state: .unavailable, value: nil, source: source)
    )
    func sellOrder(
      typeID: Int64,
      price: Double,
      volume: Int64 = 1_000_000
    ) -> MarketOrder {
      MarketOrder(
        id: Int64.random(in: 1...Int64.max),
        typeID: typeID,
        locationID: EVEConstants.jitaIV4StationID,
        systemID: EVEConstants.jitaSystemID,
        side: .sell,
        price: price,
        volumeRemaining: volume,
        minimumVolume: 1,
        issued: .now
      )
    }
    return IndustryPlanningContext(
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
          mineralTypeID: [sellOrder(typeID: mineralTypeID, price: 10)],
          fillerTypeID: [sellOrder(typeID: fillerTypeID, price: 100)],
          oreTypeID: [
            sellOrder(
              typeID: oreTypeID,
              price: oreUnitPrice,
              volume: oreVolumeRemaining
            )
          ],
        ],
        source: source
      ),
      adjustedPrices: [
        mineralTypeID: AdjustedPrice(
          typeID: mineralTypeID,
          adjustedPrice: 5,
          averagePrice: 5
        )
      ],
      systemIndices: [],
      sdeBuild: 1,
      characterCapabilities: [refiner]
    )
  }

  @Test
  func compressedOreIsValuedInsideTheSharedInboundCourierCargo()
    async throws
  {
    // Standalone, the 1,000 m³ of Tritanium and the ore each cost one
    // rounded million. Inside the shared cargo, removing the minerals drops
    // the inbound shipment from 2,900 m³ (3 M ISK) to about 1,902 m³
    // (2 M ISK), which outweighs the 480,000 ISK ore premium.
    let plan = try await IndustryPlanner().plan(
      input: "Refining Route Product 1 0 0",
      context: compressedOreRouteContext(oreUnitPrice: 35_000)
    )

    let refining = try #require(plan.compressedOreRefining)
    let purchase = try #require(refining.purchases.first)
    #expect(purchase.oreTypeID == 28_417)
    #expect(purchase.quantity == 14)
    #expect(refining.coveredMinerals[34] == 1_000)
    #expect(refining.savings > 0)
    let logistics = try #require(plan.costBreakdown?.logistics)
    #expect(logistics.total == 2_000_000)
    #expect(
      plan.warnings.contains { $0.code == "refining.compressed-ore-selected" }
    )
  }

  @Test
  func compressedOreUsesAvailableDepthAndKeepsTheRestDirect() async throws {
    let plan = try await IndustryPlanner().plan(
      input: "Refining Route Product 1 0 0",
      context: compressedOreRouteContext(
        oreUnitPrice: 100,
        oreVolumeRemaining: 5
      )
    )

    let refining = try #require(plan.compressedOreRefining)
    let purchase = try #require(refining.purchases.first)
    #expect(purchase.quantity == 5)
    #expect(purchase.batches == 5)
    let covered = try #require(refining.coveredMinerals[34])
    #expect(covered > 0 && covered < 1_000)
    #expect(refining.remainingDirectMinerals[34] == 1_000 - covered)
    #expect(
      plan.warnings.contains { $0.code == "refining.ore-depth-limited" }
    )
  }

  @Test
  func disabledCompressedOreComparisonIsReportedForShippedMinerals()
    async throws
  {
    let plan = try await IndustryPlanner().plan(
      input: "Refining Route Product 1 0 0",
      context: compressedOreRouteContext(
        comparisonEnabled: false,
        oreUnitPrice: 100
      )
    )

    #expect(plan.compressedOreRefining == nil)
    #expect(
      plan.warnings.contains { $0.code == "refining.comparison-disabled" }
    )
    #expect(
      EVEShoppingList.make(from: plan.materials).items.contains {
        $0.typeID == 34
      }
    )
  }

  @Test
  func reprocessingYieldUsesSkillsAndFloorsEachBatchTotal() {
    let yield = ReprocessingYieldCalculator.yieldMultiplier(
      baseYieldMultiplier: 0.5,
      reprocessingLevel: 5,
      reprocessingEfficiencyLevel: 5,
      oreProcessingLevel: 5,
      implantYieldBonusPercent: 4
    )
    let expectedYield: Double = 0.5 * 1.15 * 1.10 * 1.10 * 1.04
    let actualYield = yield ?? 0
    #expect(abs(actualYield - expectedYield) < 0.000_001)
    #expect(
      ReprocessingYieldCalculator.outputQuantity(
        baseQuantity: 100,
        batches: 3,
        yieldMultiplier: 0.726
      ) == 217
    )
  }

  @Test
  func historicalReprocessingOutputDecodesWithoutAllocationDetails() throws {
    let historical = try JSONDecoder().decode(
      ReprocessingMaterialOutput.self,
      from: Data(#"{"typeID":16001,"quantity":42}"#.utf8)
    )

    #expect(historical.typeID == 16_001)
    #expect(historical.quantity == 42)
    #expect(historical.name == nil)
    #expect(historical.usedInPlan == nil)
    #expect(historical.surplusToWarehouse == nil)
  }

  @Test
  func incompleteContractIndexUsesOnlyObservedOffersAsProvisionalEvidence()
    throws
  {
    let complete = publicContractReference(
      typeID: 61,
      unitPrice: 2_500,
      location: .jita
    )
    let incomplete = PublicContractReferenceSnapshot(
      id: complete.id,
      capturedAt: complete.capturedAt,
      locationID: complete.locationID,
      locationName: complete.locationName,
      prices: complete.prices,
      hasCompleteSearchCoverage: false,
      source: complete.source,
      allowedRegionIDs: complete.allowedRegionIDs
    )

    let quote = IndustryPlanner().publicContractQuote(
      typeID: 61,
      quantity: 3,
      snapshot: incomplete,
      scenario: .contractSale
    )
    #expect(quote.total == 7_500)
    #expect(quote.filledQuantity == 3)
    #expect(
      quote.warnings.contains {
        $0.code == "contracts.reference-provisional"
      }
    )
    let result = SaleScenarioResult(
      scenario: .contractSale,
      grossOrNetRevenue: quote.total,
      profit: nil,
      margin: nil,
      roi: nil,
      quotes: [quote]
    )
    #expect(result.hasProvisionalPublicContractReference)

    let noObservedOffer = PublicContractReferenceSnapshot(
      capturedAt: incomplete.capturedAt,
      locationID: incomplete.locationID,
      locationName: incomplete.locationName,
      prices: [:],
      hasCompleteSearchCoverage: false,
      source: incomplete.source
    )
    let unavailable = IndustryPlanner().publicContractQuote(
      typeID: 61,
      quantity: 3,
      snapshot: noObservedOffer,
      scenario: .contractSale
    )
    #expect(unavailable.total == nil)
    #expect(unavailable.filledQuantity == 0)
    #expect(
      unavailable.warnings.contains {
        $0.code == "contracts.reference-partial"
      }
    )
  }

  private func publicContractReference(
    typeID: Int64,
    unitPrice: Double,
    location: ProcurementLocation
  ) -> PublicContractReferenceSnapshot {
    let capturedAt = Date(timeIntervalSince1970: 25_000)
    let locationID = location.locationID ?? 0
    let offer = PublicContractSearchResult(
      contractID: typeID * 100,
      recordID: typeID * 1_000,
      regionID: location.regionID ?? 0,
      regionName: "Fixture Region",
      contractType: "item_exchange",
      price: unitPrice,
      dateIssued: capturedAt,
      dateExpired: capturedAt.addingTimeInterval(86_400),
      startLocationID: locationID,
      startLocationName: location.name,
      typeID: typeID,
      typeName: "Fixture Product",
      isIncluded: true,
      quantity: 1,
      offeredLineCount: 1,
      requestedLineCount: 0
    )
    return PublicContractReferenceSnapshot.project(
      locationID: locationID,
      locationName: location.name,
      offers: [typeID: [offer]],
      progress: PublicContractSyncProgress(
        phase: .completed,
        regionCount: 1,
        completedRegions: 1,
        freshRegions: 1,
        remainingInitialRegions: 0,
        lastCompletedAt: capturedAt
      ),
      limitPerType: 500,
      capturedAt: capturedAt
    )
  }

  private func bpcContract(
    contractID: Int64,
    runs: Int,
    price: Double,
    offeredLineCount: Int = 1
  ) -> PublicContractSearchResult {
    PublicContractSearchResult(
      contractID: contractID,
      recordID: contractID * 10,
      regionID: EVEConstants.theForgeRegionID,
      regionName: "The Forge",
      contractType: "item_exchange",
      price: price,
      dateIssued: .now,
      dateExpired: .now.addingTimeInterval(86_400),
      startLocationID: EVEConstants.jitaIV4StationID,
      startLocationName: "Jita IV - Moon 4",
      typeID: 802,
      typeName: "Choice Intermediate Blueprint",
      isIncluded: true,
      quantity: 1,
      isBlueprintCopy: true,
      materialEfficiency: 10,
      timeEfficiency: 20,
      runs: runs,
      offeredLineCount: offeredLineCount,
      requestedLineCount: 0
    )
  }
}

private struct FixtureCatalog: IndustryCatalogQuerying {
  let names: [Int64: String]
  let definitions: [Int64: BlueprintDefinition]
  let classifications: [Int64: IndustryItemClassification]
  let packagedVolumes: [Int64: Double]
  let compressedOre: [CompressedOreOption]

  init(
    names: [Int64: String],
    definitions: [Int64: BlueprintDefinition],
    classifications: [Int64: IndustryItemClassification] = [:],
    packagedVolumes: [Int64: Double] = [:],
    compressedOre: [CompressedOreOption] = []
  ) {
    self.names = names
    self.definitions = definitions
    self.classifications = classifications
    self.packagedVolumes = packagedVolumes
    self.compressedOre = compressedOre
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

  func compressedOreOptions(
    producing materialTypeIDs: Set<Int64>
  ) async throws -> [CompressedOreOption] {
    compressedOre.filter { option in
      option.outputs.contains { materialTypeIDs.contains($0.typeID) }
    }
  }
}
