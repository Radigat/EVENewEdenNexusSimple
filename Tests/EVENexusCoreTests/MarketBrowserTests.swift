import Foundation
import Testing

@testable import EVENexusCore

@Suite("Cross-region market browser")
struct MarketBrowserTests {
  @Test
  func preservesOrderFieldsAndReportsUnavailableRegionsAsPartial() async throws {
    let transport = MarketBrowserFixtureTransport()
    let service = MarketBrowserService(
      esi: ESIClient(transport: transport),
      maximumConcurrentRegionRequests: 2
    )

    let sourced = try await service.snapshot(
      typeID: 34,
      itemName: "Tritanium"
    )
    let snapshot = try #require(sourced.value)

    #expect(sourced.state == .partial)
    #expect(snapshot.regionCount == 2)
    #expect(snapshot.loadedRegionCount == 1)
    #expect(snapshot.regionFailures.map(\.regionID) == [10_000_002])
    #expect(snapshot.orders.count == 3)

    let sell = try #require(snapshot.orders.first { $0.side == .sell })
    #expect(sell.regionName == "Alpha Region")
    #expect(sell.locationName == "Alpha Trade Station")
    #expect(sell.systemName == "Alpha System")
    #expect(sell.securityBand == .highSecurity)
    #expect(sell.volumeRemaining == 25)
    #expect(sell.volumeTotal == 100)
    #expect(sell.minimumVolume == 1)
    #expect(sell.range == "station")
    #expect(sell.esiLastModifiedAt != nil)
    #expect(snapshot.summary.bestSellPrice == 5.5)
    #expect(snapshot.summary.bestBuyPrice == 5.0)
    #expect(snapshot.summary.activeSellVolume == 30)
    #expect(snapshot.summary.activeBuyVolume == 40)
    #expect(snapshot.summary.averageSellFivePercent == 5.5)
    #expect(snapshot.summary.averageBuyFivePercent == 5.0)
    #expect(snapshot.summary.averageMargin == 0.5)
    #expect(snapshot.summary.averageMarginPercent == 10)

    let structure = try #require(
      snapshot.orders.first { $0.locationID == 1_000_000_000_001 }
    )
    #expect(structure.locationName == nil)
    #expect(structure.systemName == "Alpha System")
    let namedSnapshot = snapshot.resolvingStructureNames([
      structure.locationID: "Alpha Public Market"
    ])
    #expect(
      namedSnapshot.orders.first(where: { $0.id == structure.id })?
        .locationName == "Alpha Public Market"
    )
  }

  @Test
  func filterCanExcludePlayerStructures() {
    let structure = order(
      id: 1,
      locationID: 1_000_000_000_001
    )
    var filter = MarketBrowserFilter()
    #expect(filter.accepts(structure))

    filter.includesPlayerStructures = false
    #expect(!filter.accepts(structure))

    var securityFilter = MarketBrowserFilter()
    securityFilter.includesHighSecurity = false
    #expect(!securityFilter.accepts(order(id: 2, securityStatus: 0.9)))
    #expect(securityFilter.accepts(order(id: 3, securityStatus: 0.2)))
    securityFilter.includesLowSecurity = false
    #expect(!securityFilter.accepts(order(id: 3, securityStatus: 0.2)))
    #expect(securityFilter.accepts(order(id: 4, securityStatus: -0.1)))
  }

  @Test
  func systemSecurityUsesEVEClientDisplayRounding() {
    #expect(MarketSecurityBand.eveDisplayStatus(1) == 1)
    #expect(MarketSecurityBand.eveDisplayStatus(0.9459) == 0.9)
    #expect(MarketSecurityBand.eveDisplayStatus(0.05) == 0.1)
    #expect(MarketSecurityBand.eveDisplayStatus(0.01) == 0.1)
    #expect(MarketSecurityBand.eveDisplayStatus(0) == 0)
    #expect(MarketSecurityBand.eveDisplayStatus(-0.37) == -0.4)
    #expect(MarketSecurityBand.eveDisplayStatus(nil) == nil)
    #expect(MarketSecurityBand.eveDisplayStatus(.infinity) == nil)
  }

  @Test
  func summaryUsesVolumeWeightedActiveSellPrice() {
    let summary = MarketBrowserSummary.calculate(
      orders: [
        order(id: 1, price: 10, volume: 1),
        order(id: 2, price: 20, volume: 3),
        order(id: 3, price: 8, volume: 20, side: .buy),
        order(id: 4, price: 7, volume: 20, side: .buy),
      ]
    )

    #expect(summary.bestSellPrice == 10)
    #expect(summary.weightedAverageSellPrice == 17.5)
    #expect(summary.activeSellVolume == 4)
    #expect(summary.activeBuyVolume == 40)
    #expect(summary.averageSellFivePercent == 10)
    #expect(summary.averageBuyFivePercent == 8)
    #expect(summary.averageMargin == 2)
    #expect(summary.averageMarginPercent == 25)
  }

  @Test
  func fivePercentAveragesUseBestVolumeAndExcludeExtremeOrders() {
    let summary = MarketBrowserSummary.calculate(
      orders: [
        order(id: 1, price: 10, volume: 2),
        order(id: 2, price: 20, volume: 98),
        order(id: 3, price: 1_000, volume: 500),
        order(id: 4, price: 8, volume: 2, side: .buy),
        order(id: 5, price: 7, volume: 98, side: .buy),
        order(id: 6, price: 0.1, volume: 500, side: .buy),
      ]
    )

    #expect(summary.activeSellVolume == 100)
    #expect(summary.activeBuyVolume == 100)
    #expect(summary.averageSellFivePercent == 16)
    #expect(abs((summary.averageBuyFivePercent ?? 0) - 7.4) < 0.000_001)
  }

  @Test
  func catalogWideLocationSnapshotFiltersOtherLocationsAndReportsProgress()
    async throws
  {
    let progress = MarketScanProgressRecorder()
    let service = TradeHubMarketService(
      esi: ESIClient(transport: MarketBrowserFixtureTransport())
    )

    let snapshot = try await service.locationOrderSnapshot(
      regionID: 10_000_001,
      locationID: 60_000_001
    ) { completed, total in
      await progress.record(completed: completed, total: total)
    }

    #expect(snapshot.ordersByType[34]?.count == 2)
    #expect(
      snapshot.ordersByType.values.flatMap { $0 }.allSatisfy {
        $0.locationID == 60_000_001
      }
    )
    #expect(await progress.values == [[1, 1]])
  }

  @Test
  func manufacturingOpportunitySeparatesDemandFeesAndContribution() throws {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let definition = BlueprintDefinition(
      blueprintTypeID: 200,
      productTypeID: 100,
      maxProductionLimit: 100,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 3_600,
        materials: [BlueprintMaterial(typeID: 34, quantity: 10)],
        products: [BlueprintProduct(typeID: 100, quantity: 2, probability: nil)]
      ),
      source: source
    )
    let unlistedDefinition = BlueprintDefinition(
      blueprintTypeID: 201,
      productTypeID: 101,
      maxProductionLimit: 100,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 3_600,
        materials: [BlueprintMaterial(typeID: 34, quantity: 10)],
        products: [BlueprintProduct(typeID: 101, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: 10_000_002,
      locationID: 60_003_760,
      capturedAt: .now,
      state: .fresh,
      ordersByType: [
        34: [marketOrder(id: 1, typeID: 34, side: .sell, price: 10, volume: 100)],
        100: [
          marketOrder(id: 2, typeID: 100, side: .sell, price: 100, volume: 100),
          marketOrder(id: 3, typeID: 100, side: .buy, price: 90, volume: 50),
        ],
      ],
      source: source
    )
    let facility = ManufacturingOpportunityFacilityContext(
      name: "Home Factory",
      materialMultiplier: 1,
      timeMultiplier: 1,
      jobCostMultiplier: 1,
      facilityTaxRate: 0,
      systemCostIndex: 0.1,
      sccSurchargeRate: 0,
      alphaSurchargeRate: 0
    )
    let demand = ManufacturingOpportunityDemandSnapshot(
      regionID: market.regionID,
      locationID: market.locationID,
      utcDay: market.capturedAt,
      firstObservedAt: market.capturedAt.addingTimeInterval(-3_600),
      lastObservedAt: market.capturedAt,
      sampleCount: 2,
      comparedOrderCount: 2,
      decreasedOrderCount: 1,
      observedUnitsByType: [100: 17],
      source: source
    )

    let snapshot = try ManufacturingOpportunityAnalyzer.analyze(
      definitions: [definition, unlistedDefinition],
      typeNames: [34: "Tritanium", 100: "Fixture Product"],
      classifications: [
        100: IndustryItemClassification(
          categoryName: "Module",
          groupName: "Fixture Group",
          manufacturingCategory: .module
        )
      ],
      packagedVolumes: [100: 5],
      settings: ManufacturingOpportunitySettings(
        targetQuantity: 3,
        materialEfficiency: 10,
        timeEfficiency: 20
      ),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      market: market,
      demand: demand,
      adjustedPrices: [
        34: AdjustedPrice(typeID: 34, adjustedPrice: 2, averagePrice: nil)
      ],
      facilities: [.module: facility],
      salesTaxRate: 0.10,
      brokerFeeRate: 0.05
    )
    let row = try #require(snapshot.rows.first)

    #expect(snapshot.coverage.completeManufacturingDefinitionCount == 2)
    #expect(snapshot.coverage.mainHubActiveOrderTypeCount == 2)
    #expect(snapshot.coverage.candidateCount == 1)
    #expect(snapshot.coverage.candidatesWithSellOrders == 1)
    #expect(snapshot.coverage.candidatesWithBuyOrders == 1)
    #expect(row.runs == 2)
    #expect(row.producedQuantity == 4)
    #expect(row.materials.first?.quantity == 18)
    #expect(row.materialCost == 180)
    #expect(row.installationCost == 4)
    #expect(row.grossRevenue == 400)
    #expect(row.salesTax == 40)
    #expect(row.brokerFee == 20)
    #expect(row.netRevenue == 340)
    #expect(row.contributionProfit == 156)
    #expect(abs((row.returnOnInvestment ?? 0) - (156.0 / 184.0)) < 0.000_001)
    #expect(row.durationSeconds == 5_760)
    #expect(row.observedDailyDemand == 17)
    #expect(row.iskPerHour == 97.5)
    #expect(row.iskPerCubicMeter == 7.8)
    #expect(row.activeBuyDemand == 50)
    #expect(row.activeSellSupply == 100)
    let defaultCosts = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet()
    )
    #expect(defaultCosts.totalCost == 184)
    #expect(defaultCosts.profit == 156)
    let adjustedCosts = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(
        includesInstallation: false,
        includesSalesTax: false,
        includesBrokerFee: true,
        includesBlueprintAllocation: true,
        blueprintAllocationPerRun: 5,
        includesHauling: true,
        haulingCostPerBatch: 12
      )
    )
    #expect(adjustedCosts.totalCost == 202)
    #expect(adjustedCosts.netRevenue == 380)
    #expect(adjustedCosts.profit == 178)
    let procurement = ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: [34: 12],
      protectedQuantities: [34: 2],
      reservedQuantities: [34: 3]
    )
    let sourcing = try #require(procurement.lines.first)
    #expect(sourcing.usableWarehouseQuantity == 7)
    #expect(sourcing.fromWarehouse == 7)
    #expect(sourcing.toBuy == 11)
    #expect(sourcing.warehouseReplacementValue == 70)
    #expect(sourcing.purchaseCashRequirement == 110)
    #expect(procurement.multibuyText == "Tritanium 11")
    #expect(
      snapshot.warnings.contains {
        $0.code == "manufacturing-opportunity.observed-demand-lower-bound"
      }
    )
  }

  @Test
  func exactHubDemandTracksOnlySurvivingOrderVolumeDecreases() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T08:00:00Z")
    )
    let secondDate = firstDate.addingTimeInterval(3_600)
    let firstSource = SourceIdentity(
      provider: "Fixture",
      version: "1",
      capturedAt: firstDate,
      snapshotID: UUID()
    )
    let secondSource = SourceIdentity(
      provider: "Fixture",
      version: "1",
      capturedAt: secondDate,
      snapshotID: UUID()
    )
    let first = MarketOrderSnapshot(
      id: UUID(), regionID: 10_000_002, locationID: 60_003_760,
      capturedAt: firstDate, state: .fresh,
      ordersByType: [
        100: [
          marketOrder(id: 1, typeID: 100, side: .sell, price: 10, volume: 10),
          marketOrder(id: 2, typeID: 100, side: .buy, price: 9, volume: 6),
          marketOrder(id: 3, typeID: 100, side: .sell, price: 11, volume: 20),
        ]
      ],
      source: firstSource
    )

    var ledger = ManufacturingOpportunityDemandLedger()
    let baseline = ledger.observe(first)
    #expect(baseline.sampleCount == 1)
    #expect(baseline.observedUnits(for: 100) == nil)

    ledger = try JSONDecoder().decode(
      ManufacturingOpportunityDemandLedger.self,
      from: JSONEncoder().encode(ledger)
    )
    let second = MarketOrderSnapshot(
      id: UUID(), regionID: 10_000_002, locationID: 60_003_760,
      capturedAt: secondDate, state: .fresh,
      ordersByType: [
        100: [
          marketOrder(id: 1, typeID: 100, side: .sell, price: 10, volume: 7),
          marketOrder(id: 2, typeID: 100, side: .buy, price: 9, volume: 4),
          marketOrder(id: 4, typeID: 100, side: .sell, price: 12, volume: 100),
        ]
      ],
      source: secondSource
    )
    let observed = ledger.observe(second)

    #expect(observed.sampleCount == 2)
    #expect(observed.comparedOrderCount == 2)
    #expect(observed.decreasedOrderCount == 2)
    #expect(observed.observedUnits(for: 100) == 5)
    #expect(ledger.observe(second).sampleCount == 2)
  }

  @Test
  func exactHubDemandResetsAtTheNextUTCDay() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T23:30:00Z")
    )
    let nextDate = firstDate.addingTimeInterval(3_600)
    var ledger = ManufacturingOpportunityDemandLedger()
    _ = ledger.observe(
      marketSnapshot(
        at: firstDate,
        sourceID: UUID(),
        orders: [marketOrder(id: 1, typeID: 100, side: .sell, price: 10, volume: 10)]
      )
    )
    let next = ledger.observe(
      marketSnapshot(
        at: nextDate,
        sourceID: UUID(),
        orders: [marketOrder(id: 1, typeID: 100, side: .sell, price: 10, volume: 5)]
      )
    )

    #expect(next.sampleCount == 1)
    #expect(next.observedUnits(for: 100) == nil)
  }

  @Test
  func automaticOpportunityRefreshUsesASixHourSafetyInterval() throws {
    let now = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z")
    )
    #expect(
      ManufacturingOpportunityAutomaticRefreshPolicy.shouldRefresh(
        lastObservedAt: nil,
        now: now
      )
    )
    #expect(
      !ManufacturingOpportunityAutomaticRefreshPolicy.shouldRefresh(
        lastObservedAt: now.addingTimeInterval(-(6 * 60 * 60) + 1),
        now: now
      )
    )
    #expect(
      ManufacturingOpportunityAutomaticRefreshPolicy.shouldRefresh(
        lastObservedAt: now.addingTimeInterval(-6 * 60 * 60),
        now: now
      )
    )
    #expect(
      ManufacturingOpportunityAutomaticRefreshPolicy.nextAutomaticRunAt(
        lastObservedAt: nil,
        now: now
      ) == now.addingTimeInterval(15)
    )
    #expect(
      ManufacturingOpportunityAutomaticRefreshPolicy.nextAutomaticRunAt(
        lastObservedAt: now.addingTimeInterval(-60 * 60),
        now: now
      ) == now.addingTimeInterval(5 * 60 * 60)
    )
    #expect(
      ManufacturingOpportunityAutomaticRefreshPolicy.nextAutomaticRunAt(
        lastObservedAt: now.addingTimeInterval(-7 * 60 * 60),
        now: now
      ) == now.addingTimeInterval(15)
    )
  }

  @Test
  func opportunitySnapshotStoreRestoresTheLastCompleteListWithoutReplacingCorruption()
    async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("opportunities.json")
    let snapshot = opportunitySnapshot(productName: "Persisted Product")
    let store = ManufacturingOpportunitySnapshotStore(fileURL: fileURL)

    let initiallyStored = try await store.load()
    #expect(initiallyStored?.id == nil)
    try await store.save(snapshot)

    let reopened = ManufacturingOpportunitySnapshotStore(fileURL: fileURL)
    let loaded = try await reopened.load()
    let restored = try #require(loaded)
    #expect(restored.id == snapshot.id)
    #expect(restored.rows.map(\.productName) == ["Persisted Product"])
    #expect(restored.coverage.candidateCount == 1)

    let corrupted = Data("not-json".utf8)
    try corrupted.write(to: fileURL, options: .atomic)
    let protectedStore = ManufacturingOpportunitySnapshotStore(fileURL: fileURL)
    await #expect(throws: ManufacturingOpportunitySnapshotStoreError.unreadable) {
      _ = try await protectedStore.load()
    }
    await #expect(throws: ManufacturingOpportunitySnapshotStoreError.unreadable) {
      try await protectedStore.save(snapshot)
    }
    #expect(try Data(contentsOf: fileURL) == corrupted)
  }

  @Test
  func opportunityFiltersClassifyProductFamiliesWithoutGuessingTechLevel() {
    #expect(
      ManufacturingOpportunityProductFamily.classify(
        categoryName: "Ship", groupName: "Cruiser"
      ) == .ships
    )
    #expect(
      ManufacturingOpportunityProductFamily.classify(
        categoryName: "Module", groupName: "Armor Rig"
      ) == .rigs
    )
    #expect(
      ManufacturingOpportunityProductFamily.classify(
        categoryName: "Material", groupName: "Capital Construction Components"
      ) == .components
    )
    #expect(
      ManufacturingOpportunityProductFamily.classify(
        categoryName: "Commodity", groupName: "Unknown Published Group"
      ) == .other
    )
  }

  @Test
  func opportunitySearchStartsAtThreeCharacters() {
    #expect(ManufacturingOpportunitySearchPolicy.effectiveQuery("A") == nil)
    #expect(ManufacturingOpportunitySearchPolicy.effectiveQuery(" Ar ") == nil)
    #expect(
      ManufacturingOpportunitySearchPolicy.effectiveQuery(" Ark ") == "Ark"
    )
    #expect(
      ManufacturingOpportunitySearchPolicy.accepts(
        rawQuery: "Ar",
        productName: "Ark",
        groupName: "Jump Freighter",
        categoryName: "Ship"
      )
    )
    #expect(
      ManufacturingOpportunitySearchPolicy.accepts(
        rawQuery: "fre",
        productName: "Ark",
        groupName: "Jump Freighter",
        categoryName: "Ship"
      )
    )
    #expect(
      !ManufacturingOpportunitySearchPolicy.accepts(
        rawQuery: "rig",
        productName: "Ark",
        groupName: "Jump Freighter",
        categoryName: "Ship"
      )
    )
  }

  @Test
  func enabledUnknownCostSheetInputKeepsProfitUnavailable() throws {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let row = ManufacturingOpportunityRow(
      blueprintTypeID: 1,
      productTypeID: 2,
      productName: "Product",
      categoryName: "Module",
      groupName: "Module",
      facilityName: "Home",
      runs: 1,
      outputPerRun: 1,
      producedQuantity: 1,
      materialEfficiency: 10,
      timeEfficiency: 20,
      durationSeconds: 3_600,
      observedDailyDemand: nil,
      activeBuyDemand: 1,
      activeSellSupply: 1,
      materials: [],
      materialCost: 10,
      installationCost: 1,
      productionCostBeforeBlueprintAndLogistics: 11,
      grossRevenue: 20,
      salesTax: 2,
      brokerFee: 1,
      netRevenue: 17,
      contributionProfit: 6,
      returnOnInvestment: 6.0 / 11.0,
      iskPerHour: 6,
      iskPerCubicMeter: 6,
      packagedVolumePerUnit: 1,
      warnings: [
        DomainWarning(
          code: "fixture", message: "fixture", severity: .information,
          source: source
        )
      ]
    )
    let projection = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(
        includesBlueprintAllocation: true,
        blueprintAllocationPerRun: nil
      )
    )
    #expect(projection.blueprintAllocation == nil)
    #expect(projection.totalCost == nil)
    #expect(projection.profit == nil)
    #expect(projection.returnOnInvestment == nil)
  }

  @Test
  func opportunityLogisticsUsesOnlyTheProductionWarehouseShortfall() throws {
    let row = sortableOpportunityRow(
      name: "Product",
      value: 18,
      demand: 1,
      materialQuantity: 18,
      materialUnitPrice: 10,
      materialVolume: 5
    )
    let procurement = ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: [34: 12],
      protectedQuantities: [34: 2],
      reservedQuantities: [34: 3]
    )
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: procurement,
      configuration: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        includeOutboundProducts: false,
        productionLocationName: "Home Factory",
        homeTradeHub: .jita,
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )

    #expect(procurement.lines.first?.fromWarehouse == 7)
    #expect(procurement.lines.first?.toBuy == 11)
    #expect(logistics.cost == 1_000_000)
    #expect(logistics.legs.count == 1)
    #expect(logistics.legs.first?.cargoVolumeM3 == 55)
    #expect(logistics.legs.first?.collateral == 110)
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics
    )
    #expect(costs.logisticsCost == 1_000_000)
    #expect(costs.totalCost == 1_000_180)
    #expect(costs.profit == -999_980)

    let fullyStocked = ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: [34: 18],
      protectedQuantities: [:],
      reservedQuantities: [:]
    )
    let noHaul = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: fullyStocked,
      configuration: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        includeOutboundProducts: false,
        productionLocationName: "Home Factory",
        homeTradeHub: .jita,
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )
    #expect(noHaul.cost == 0)
    #expect(noHaul.legs.isEmpty)
  }

  @Test
  func missingProductionWarehouseKeepsLogisticsProfitAndROIUnavailable() {
    let row = sortableOpportunityRow(
      name: "Product",
      value: 1,
      demand: 1,
      materialQuantity: 1,
      materialUnitPrice: 10,
      materialVolume: 5
    )
    let procurement = ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:]
    )
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: procurement,
      configuration: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        productionLocationName: "Home Factory",
        homeTradeHub: .jita,
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: false
    )
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics
    )

    #expect(logistics.cost == nil)
    #expect(
      logistics.warnings.contains {
        $0.code == "manufacturing-opportunity.production-warehouse-unavailable"
      }
    )
    #expect(costs.totalCost == nil)
    #expect(costs.profit == nil)
    #expect(costs.returnOnInvestment == nil)
  }

  @Test
  func opportunityColumnsToggleBetweenAscendingAndDescending() {
    let low = sortableOpportunityRow(name: "Alpha", value: 1, demand: 1)
    let high = sortableOpportunityRow(name: "Zulu", value: 9, demand: 9)
    let lowCosts = sortableCosts(value: 1)
    let highCosts = sortableCosts(value: 9)
    let numericColumns: [ManufacturingOpportunitySortColumn] = [
      .demand, .quantity, .runs, .duration, .cost, .revenue, .salesTax,
      .brokerFee, .profit, .roi, .iskPerHour, .iskPerCubicMeter,
      .materialEfficiency, .timeEfficiency,
    ]
    for column in numericColumns {
      let ascending = ManufacturingOpportunitySortDescriptor(
        column: column,
        direction: .ascending
      )
      let descending = ManufacturingOpportunitySortDescriptor(
        column: column,
        direction: .descending
      )
      #expect(
        ascending.orderedBefore(
          lhs: low, lhsCosts: lowCosts,
          rhs: high, rhsCosts: highCosts
        )
      )
      #expect(
        descending.orderedBefore(
          lhs: high, lhsCosts: highCosts,
          rhs: low, rhsCosts: lowCosts
        )
      )
    }
    for column in [
      ManufacturingOpportunitySortColumn.item, .group, .category,
    ] {
      #expect(
        ManufacturingOpportunitySortDescriptor(
          column: column,
          direction: .ascending
        ).orderedBefore(
          lhs: low, lhsCosts: lowCosts,
          rhs: high, rhsCosts: highCosts
        )
      )
      #expect(
        ManufacturingOpportunitySortDescriptor(
          column: column,
          direction: .descending
        ).orderedBefore(
          lhs: high, lhsCosts: highCosts,
          rhs: low, rhsCosts: lowCosts
        )
      )
    }
  }

  @Test
  func opportunitySettingsClampPersistedTEOutsideTheEveRange() {
    let settings = ManufacturingOpportunitySettings(
      targetQuantity: 1,
      materialEfficiency: 42,
      timeEfficiency: 420
    )
    #expect(settings.materialEfficiency == 10)
    #expect(settings.timeEfficiency == 20)
  }

  @Test
  func missingTraderFeesKeepNetProfitAndROIUnavailable() throws {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let definition = BlueprintDefinition(
      blueprintTypeID: 200,
      productTypeID: 100,
      maxProductionLimit: 100,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 60,
        materials: [BlueprintMaterial(typeID: 34, quantity: 1)],
        products: [BlueprintProduct(typeID: 100, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let market = MarketOrderSnapshot(
      id: UUID(), regionID: 10_000_002, locationID: 60_003_760,
      capturedAt: .now, state: .fresh,
      ordersByType: [
        34: [marketOrder(id: 1, typeID: 34, side: .sell, price: 1, volume: 10)],
        100: [marketOrder(id: 2, typeID: 100, side: .sell, price: 10, volume: 10)],
      ], source: source
    )
    let facility = ManufacturingOpportunityFacilityContext(
      name: "Home", materialMultiplier: 1, timeMultiplier: 1,
      jobCostMultiplier: 1, facilityTaxRate: 0, systemCostIndex: 0,
      sccSurchargeRate: 0, alphaSurchargeRate: 0
    )
    let snapshot = try ManufacturingOpportunityAnalyzer.analyze(
      definitions: [definition], typeNames: [34: "Input", 100: "Output"],
      classifications: [
        100: IndustryItemClassification(
          categoryName: "Module", groupName: "Group",
          manufacturingCategory: .module
        )
      ], packagedVolumes: [100: 1],
      settings: ManufacturingOpportunitySettings(), mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      market: market,
      adjustedPrices: [34: AdjustedPrice(typeID: 34, adjustedPrice: 1, averagePrice: nil)],
      facilities: [.module: facility], salesTaxRate: nil, brokerFeeRate: nil
    )
    let row = try #require(snapshot.rows.first)
    #expect(row.grossRevenue == 10)
    #expect(row.netRevenue == nil)
    #expect(row.contributionProfit == nil)
    #expect(row.returnOnInvestment == nil)
    #expect(
      snapshot.warnings.contains { $0.code == "manufacturing-opportunity.missing-sales-fees" })
  }

  private func sortableOpportunityRow(
    name: String,
    value: Int64,
    demand: Int64?,
    materialQuantity: Int64 = 1,
    materialUnitPrice: Double = 1,
    materialVolume: Double = 1
  ) -> ManufacturingOpportunityRow {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let materialTotal = Double(materialQuantity) * materialUnitPrice
    return ManufacturingOpportunityRow(
      blueprintTypeID: value,
      productTypeID: value,
      productName: name,
      categoryName: name,
      groupName: name,
      facilityName: "Home Factory",
      runs: Int(value),
      outputPerRun: 1,
      producedQuantity: value,
      materialEfficiency: Int(value),
      timeEfficiency: Int(value),
      durationSeconds: value,
      observedDailyDemand: demand,
      activeBuyDemand: value,
      activeSellSupply: value,
      materials: [
        ManufacturingOpportunityMaterial(
          typeID: 34,
          name: "Material",
          quantity: materialQuantity,
          quote: PriceQuote(
            id: UUID(),
            typeID: 34,
            quantity: materialQuantity,
            scenario: .materialBuy,
            total: materialTotal,
            weightedUnitPrice: materialUnitPrice,
            filledQuantity: materialQuantity,
            capturedAt: .now,
            source: source,
            warnings: []
          ),
          packagedVolumePerUnit: materialVolume
        )
      ],
      materialCost: materialTotal,
      installationCost: 0,
      productionCostBeforeBlueprintAndLogistics: materialTotal,
      grossRevenue: materialTotal + 25,
      salesTax: 2,
      brokerFee: 3,
      netRevenue: materialTotal + 20,
      contributionProfit: 20,
      returnOnInvestment: 1,
      iskPerHour: Double(value),
      iskPerCubicMeter: Double(value),
      packagedVolumePerUnit: 1,
      warnings: []
    )
  }

  private func sortableCosts(
    value: Double
  ) -> ManufacturingOpportunityCostProjection {
    ManufacturingOpportunityCostProjection(
      materialCost: value,
      installationCost: value,
      blueprintAllocation: value,
      logisticsCost: value,
      totalCost: value,
      grossRevenue: value,
      salesTax: value,
      brokerFee: value,
      netRevenue: value,
      profit: value,
      returnOnInvestment: value,
      iskPerHour: value,
      iskPerCubicMeter: value
    )
  }

  private func order(
    id: Int64,
    locationID: Int64 = 60_000_001,
    price: Double = 10,
    volume: Int64 = 1,
    side: MarketOrderSide = .sell,
    securityStatus: Double? = 0.9
  ) -> MarketBrowserOrder {
    MarketBrowserOrder(
      id: id,
      typeID: 34,
      regionID: 10_000_001,
      regionName: "Alpha Region",
      locationID: locationID,
      locationName: nil,
      systemID: 30_000_002,
      systemName: nil,
      securityStatus: securityStatus,
      side: side,
      price: price,
      volumeRemaining: volume,
      volumeTotal: volume,
      minimumVolume: 1,
      range: "station",
      issuedAt: .now,
      expiresAt: .now.addingTimeInterval(86_400),
      esiLastModifiedAt: nil,
      observedAt: .now
    )
  }

  private func marketOrder(
    id: Int64,
    typeID: Int64,
    side: MarketOrderSide,
    price: Double,
    volume: Int64
  ) -> MarketOrder {
    MarketOrder(
      id: id,
      typeID: typeID,
      locationID: 60_003_760,
      systemID: 30_000_142,
      side: side,
      price: price,
      volumeRemaining: volume,
      minimumVolume: 1,
      issued: .now
    )
  }

  private func marketSnapshot(
    at date: Date,
    sourceID: UUID,
    orders: [MarketOrder]
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: 10_000_002,
      locationID: 60_003_760,
      capturedAt: date,
      state: .fresh,
      ordersByType: Dictionary(grouping: orders, by: \.typeID),
      source: SourceIdentity(
        provider: "Fixture",
        version: "1",
        capturedAt: date,
        snapshotID: sourceID
      )
    )
  }

  private func opportunitySnapshot(
    productName: String
  ) -> ManufacturingOpportunitySnapshot {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let row = ManufacturingOpportunityRow(
      blueprintTypeID: 1,
      productTypeID: 2,
      productName: productName,
      categoryName: "Module",
      groupName: "Fixture Group",
      facilityName: "Fixture Facility",
      runs: 1,
      outputPerRun: 1,
      producedQuantity: 1,
      materialEfficiency: 10,
      timeEfficiency: 20,
      durationSeconds: 60,
      observedDailyDemand: nil,
      activeBuyDemand: 1,
      activeSellSupply: 1,
      materials: [],
      materialCost: 1,
      installationCost: 1,
      productionCostBeforeBlueprintAndLogistics: 2,
      grossRevenue: 3,
      salesTax: 0.1,
      brokerFee: 0.1,
      netRevenue: 2.8,
      contributionProfit: 0.8,
      returnOnInvestment: 0.4,
      iskPerHour: 48,
      iskPerCubicMeter: 0.8,
      packagedVolumePerUnit: 1,
      warnings: []
    )
    return ManufacturingOpportunitySnapshot(
      settings: ManufacturingOpportunitySettings(),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      rows: [row],
      coverage: ManufacturingOpportunityCoverage(
        completeManufacturingDefinitionCount: 1,
        mainHubActiveOrderTypeCount: 1,
        candidateCount: 1,
        candidatesWithSellOrders: 1,
        candidatesWithBuyOrders: 1
      ),
      sdeSource: source,
      marketSource: source,
      warnings: []
    )
  }
}

private actor MarketScanProgressRecorder {
  private(set) var values: [[Int]] = []

  func record(completed: Int, total: Int) {
    values.append([completed, total])
  }
}

private actor MarketBrowserFixtureTransport: ESIHTTPTransporting {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = request.url!
    var body: String
    var status: Int

    switch (request.httpMethod ?? "GET", url.path) {
    case ("GET", "/universe/regions"):
      body = "[10000001,10000002]"
      status = 200
    case ("POST", "/universe/names"):
      let ids = try JSONDecoder().decode([Int64].self, from: request.httpBody ?? Data())
      if ids.contains(where: { $0 >= 1_000_000_000_000 }) {
        body = "{\"error\":\"structure name unavailable\"}"
        status = 404
        break
      }
      let names: [String: String] = [
        "10000001": "Alpha Region",
        "10000002": "Unavailable Region",
        "60000001": "Alpha Trade Station",
        "30000002": "Alpha System",
      ]
      body = ids.compactMap { id -> String? in
        guard let name = names[String(id)] else { return nil }
        let category = id >= 60_000_000 ? "station" : "solar_system"
        return "{\"category\":\"\(category)\",\"id\":\(id),\"name\":\"\(name)\"}"
      }.joined(separator: ",")
      body = "[\(body)]"
      status = 200
    case ("GET", "/markets/10000001/orders"):
      body = """
        [
          {
            "duration": 30,
            "is_buy_order": false,
            "issued": "2026-07-30T10:00:00Z",
            "location_id": 60000001,
            "min_volume": 1,
            "order_id": 9001,
            "price": 5.5,
            "range": "station",
            "system_id": 30000002,
            "type_id": 34,
            "volume_remain": 25,
            "volume_total": 100
          },
          {
            "duration": 30,
            "is_buy_order": true,
            "issued": "2026-07-30T10:00:00Z",
            "location_id": 60000001,
            "min_volume": 5,
            "order_id": 9002,
            "price": 5.0,
            "range": "region",
            "system_id": 30000002,
            "type_id": 34,
            "volume_remain": 40,
            "volume_total": 80
          },
          {
            "duration": 30,
            "is_buy_order": false,
            "issued": "2026-07-30T10:00:00Z",
            "location_id": 1000000000001,
            "min_volume": 1,
            "order_id": 9003,
            "price": 6.0,
            "range": "station",
            "system_id": 30000002,
            "type_id": 34,
            "volume_remain": 5,
            "volume_total": 10
          }
        ]
        """
      status = 200
    case ("GET", "/markets/10000002/orders"):
      body = "{\"error\":\"fixture unavailable\"}"
      status = 500
    case ("GET", "/universe/systems/30000002"):
      body = """
        {
          "constellation_id": 20000001,
          "name": "Alpha System",
          "security_class": "A",
          "security_status": 0.9,
          "stations": [60000001],
          "system_id": 30000002
        }
        """
      status = 200
    default:
      body = "{\"error\":\"unexpected fixture request\"}"
      status = 404
    }

    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: [
          "Expires": "Sat, 01 Aug 2027 20:00:00 GMT",
          "Last-Modified": "Sat, 01 Aug 2026 17:00:00 GMT",
          "X-Pages": "1",
        ]
      )!
    )
  }
}
