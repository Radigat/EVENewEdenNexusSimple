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
  func catalogWideLocationSnapshotKeepsPageOrderAcrossConcurrentPages()
    async throws
  {
    let progress = MarketScanProgressRecorder()
    let service = TradeHubMarketService(
      esi: ESIClient(transport: PagedRegionalOrdersTransport(pageCount: 4))
    )

    let snapshot = try await service.locationOrderSnapshot(
      regionID: 10_000_001,
      locationID: 60_000_001
    ) { completed, total in
      await progress.record(completed: completed, total: total)
    }

    // One order per page at the hub, one elsewhere that must be dropped.
    #expect(snapshot.ordersByType[34]?.map(\.id) == [1, 2, 3, 4])
    #expect(await progress.values == [[1, 4], [2, 4], [3, 4], [4, 4]])
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
      comparedOrderCountByType: [100: 2],
      observedUnitsByType: [100: 17],
      dailyHistory: [
        ManufacturingOpportunityDailyDemandRecord(
          utcDay: market.capturedAt.addingTimeInterval(-24 * 60 * 60),
          observedAt: market.capturedAt.addingTimeInterval(-24 * 60 * 60),
          estimatedUnitsByType: [100: 100],
          sourceSnapshotID: UUID()
        ),
        ManufacturingOpportunityDailyDemandRecord(
          utcDay: market.capturedAt,
          observedAt: market.capturedAt,
          estimatedUnitsByType: [100: 408],
          sourceSnapshotID: source.snapshotID
        ),
      ],
      source: source
    )

    let snapshot = try ManufacturingOpportunityAnalyzer.analyze(
      definitions: [definition, unlistedDefinition],
      typeNames: [34: "Tritanium", 100: "Fixture Product"],
      classifications: [
        100: IndustryItemClassification(
          categoryName: "Module",
          groupName: "Fixture Group",
          manufacturingCategory: .module,
          metaGroupID: 2,
          techLevel: 2
        )
      ],
      packagedVolumes: [100: 5],
      settings: ManufacturingOpportunitySettings(
        targetQuantity: 3,
        requestedRuns: nil,
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
    #expect(row.metaGroupID == 2)
    #expect(row.techLevel == 2)
    #expect(row.observedDailyDemand == 408)
    #expect(row.previousDayDemand == 100)
    #expect(row.averageDailyDemand == 254)
    #expect(row.recordedDemandDayCount == 2)
    #expect(snapshot.demand?.dailyHistory == nil)

    #expect(snapshot.coverage.completeManufacturingDefinitionCount == 2)
    #expect(snapshot.coverage.mainHubActiveOrderTypeCount == 2)
    #expect(snapshot.coverage.candidateCount == 2)
    #expect(snapshot.coverage.candidatesWithSellOrders == 1)
    #expect(snapshot.coverage.candidatesWithBuyOrders == 1)
    let unlistedRow = try #require(
      snapshot.rows.first(where: { $0.productTypeID == 101 })
    )
    #expect(unlistedRow.grossRevenue == nil)
    #expect(unlistedRow.contributionProfit == nil)
    #expect(
      unlistedRow.warnings.contains {
        $0.code == "manufacturing-opportunity.product-sell-order-unavailable"
          && $0.severity == .blocking
      }
    )
    #expect(snapshot.settings.targetQuantity == 3)
    #expect(snapshot.settings.requestedRuns == nil)
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
    #expect(row.observedDailyDemand == 408)
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
    #expect(
      ManufacturingOpportunityScenarioProjector.purchaseCashRequirement(
        for: row,
        factualWarehouseQuantities: [34: 12],
        protectedQuantities: [34: 2],
        reservedQuantities: [34: 3]
      ) == procurement.purchaseCashRequirement
    )
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
    #expect(observed.estimatedDailyUnits(for: 100) == 120)
    #expect(observed.observedUnits(for: 999) == nil)
    #expect(ledger.observe(second).sampleCount == 2)
  }

  @Test
  func shortManualDemandRescanDoesNotCreateADailyRate() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T08:00:00Z")
    )
    var ledger = ManufacturingOpportunityDemandLedger()
    _ = ledger.observe(
      marketSnapshot(
        at: firstDate,
        sourceID: UUID(),
        orders: [
          marketOrder(
            id: 1,
            typeID: 100,
            side: .sell,
            price: 10,
            volume: 10
          )
        ]
      )
    )
    let observed = ledger.observe(
      marketSnapshot(
        at: firstDate.addingTimeInterval(60),
        sourceID: UUID(),
        orders: [
          marketOrder(
            id: 1,
            typeID: 100,
            side: .sell,
            price: 10,
            volume: 9
          )
        ]
      )
    )

    #expect(observed.observedUnits(for: 100) == 1)
    #expect(observed.estimatedDailyUnits(for: 100) == nil)
  }

  @Test
  func exactHubDemandContinuesAcrossUTCMidnightWithinTheRollingWindow() throws {
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

    #expect(next.sampleCount == 2)
    #expect(next.observedUnits(for: 100) == 5)
    #expect(next.estimatedDailyUnits(for: 100) == 120)
  }

  @Test
  func demandHistoryKeepsThePreviousUTCDayAndCalculatesAMultiDayAverage() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T08:00:00Z")
    )
    var ledger = ManufacturingOpportunityDemandLedger()

    func observe(hours: TimeInterval, volume: Int64) -> ManufacturingOpportunityDemandSnapshot {
      ledger.observe(
        marketSnapshot(
          at: firstDate.addingTimeInterval(hours * 60 * 60),
          sourceID: UUID(),
          orders: [
            marketOrder(
              id: 1,
              typeID: 100,
              side: .sell,
              price: 10,
              volume: volume
            )
          ]
        )
      )
    }

    _ = observe(hours: 0, volume: 100)
    #expect(observe(hours: 12, volume: 90).estimatedDailyUnits(for: 100) == 20)
    _ = observe(hours: 24, volume: 85)
    #expect(observe(hours: 36, volume: 75).estimatedDailyUnits(for: 100) == 15)
    let thirdDay = observe(hours: 48, volume: 65)
    let summary = thirdDay.dailySummary(for: 100)

    #expect(thirdDay.dailyHistory?.count == 3)
    #expect(summary.currentUnits == 20)
    #expect(summary.previousDayUnits == 15)
    #expect(summary.averageUnits == 18)
    #expect(summary.recordedDayCount == 3)
    #expect(
      abs((summary.changeFromPreviousDayPercent ?? 0) - 33.333_333) < 0.001
    )
    let unknown = thirdDay.dailySummary(for: 999)
    #expect(unknown.currentUnits == nil)
    #expect(unknown.previousDayUnits == nil)
    #expect(unknown.averageUnits == nil)
    #expect(unknown.recordedDayCount == 0)

    let restored = try JSONDecoder().decode(
      ManufacturingOpportunityDemandLedger.self,
      from: JSONEncoder().encode(ledger)
    )
    #expect(restored.demand?.dailySummary(for: 100) == summary)
  }

  @Test
  func demandLedgerMigratesTheVerboseV1BaselineToCompactV4() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z")
    )
    let firstSourceID = UUID()
    let firstMarket = marketSnapshot(
      at: firstDate,
      sourceID: firstSourceID,
      orders: [
        marketOrder(
          id: 1,
          typeID: 100,
          side: .sell,
          price: 10,
          volume: 10
        )
      ]
    )
    var original = ManufacturingOpportunityDemandLedger()
    let firstDemand = original.observe(firstMarket)
    let legacy = try JSONEncoder().encode(
      LegacyDemandLedgerFixture(
        version: 1,
        demand: firstDemand,
        previousOrdersByID: [
          1: LegacyOrderBaselineFixture(
            typeID: 100,
            locationID: firstMarket.locationID,
            side: .sell,
            volumeRemaining: 10
          )
        ],
        previousSourceSnapshotID: firstSourceID
      )
    )

    var migrated = try JSONDecoder().decode(
      ManufacturingOpportunityDemandLedger.self,
      from: legacy
    )
    let compact = try JSONEncoder().encode(migrated)
    let compactText = try #require(String(data: compact, encoding: .utf8))

    #expect(migrated.version == 4)
    #expect(migrated.baselineOrderCount == 1)
    #expect(compactText.contains("\"v\":4"))
    #expect(compactText.contains("\"o\":[["))
    #expect(!compactText.contains("volumeRemaining"))
    #expect(compact.count < legacy.count)

    let observed = migrated.observe(
      marketSnapshot(
        at: firstDate.addingTimeInterval(60),
        sourceID: UUID(),
        orders: [
          marketOrder(
            id: 1,
            typeID: 100,
            side: .sell,
            price: 10,
            volume: 7
          )
        ]
      )
    )
    #expect(observed.sampleCount == 2)
    #expect(observed.comparedOrderCount == 1)
    #expect(observed.observedUnits(for: 100) == 3)
  }

  @Test
  func cancelledDemandObservationLeavesThePreviousLedgerUnchanged() throws {
    let firstDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z")
    )
    var ledger = ManufacturingOpportunityDemandLedger()
    _ = ledger.observe(
      marketSnapshot(
        at: firstDate,
        sourceID: UUID(),
        orders: [
          marketOrder(
            id: 1,
            typeID: 100,
            side: .sell,
            price: 10,
            volume: 10
          )
        ]
      )
    )
    let unchanged = ledger
    let manyOrders = (1...4_096).map { index in
      marketOrder(
        id: Int64(index),
        typeID: 100,
        side: .sell,
        price: 10,
        volume: 9
      )
    }
    var cancellationCheckCount = 0

    #expect(throws: CancellationError.self) {
      _ = try ledger.observe(
        marketSnapshot(
          at: firstDate.addingTimeInterval(60),
          sourceID: UUID(),
          orders: manyOrders
        )
      ) {
        cancellationCheckCount += 1
        if cancellationCheckCount == 2 {
          throw CancellationError()
        }
      }
    }
    #expect(ledger == unchanged)
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
    await reopened.releaseCachedSnapshot()
    let reloadedAfterPressure = try await reopened.load()
    #expect(reloadedAfterPressure?.id == snapshot.id)

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
  func legacyOpportunityRowsDecodeWithoutDailyHistoryFields() throws {
    let snapshot = opportunitySnapshot(productName: "Legacy Product")
    let encoded = try JSONEncoder().encode(snapshot)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    var rows = try #require(object["rows"] as? [[String: Any]])
    var row = try #require(rows.first)
    row.removeValue(forKey: "previousDayDemand")
    row.removeValue(forKey: "averageDailyDemand")
    row.removeValue(forKey: "recordedDemandDayCount")
    row.removeValue(forKey: "demandChangeFromPreviousDayPercent")
    rows[0] = row
    object["rows"] = rows

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let restored = try JSONDecoder().decode(
      ManufacturingOpportunitySnapshot.self,
      from: legacyData
    )
    let restoredRow = try #require(restored.rows.first)
    #expect(restoredRow.previousDayDemand == nil)
    #expect(restoredRow.averageDailyDemand == nil)
    #expect(restoredRow.recordedDemandDayCount == nil)
    #expect(restoredRow.demandChangeFromPreviousDayPercent == nil)
  }

  @Test
  func opportunityFiltersCombineProductFamiliesAndProductionClasses() {
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
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: 1,
        techLevel: 1
      ) == .techI
    )
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: 2,
        techLevel: 2
      ) == .techII
    )
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: 14,
        techLevel: 3
      ) == .techIII
    )
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: 4,
        techLevel: 1
      ) == .faction
    )
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: 3,
        techLevel: 1
      ) == .storyline
    )
    #expect(
      ManufacturingOpportunityProductionClass.classify(
        metaGroupID: nil,
        techLevel: nil
      ) == .other
    )

    let ships: Set<ManufacturingOpportunityProductFamily> = [.ships]
    let factions: Set<ManufacturingOpportunityProductionClass> = [.faction]
    #expect(
      ManufacturingOpportunityCatalogFilter.accepts(
        categoryName: "Ship",
        groupName: "Frigate",
        metaGroupID: 4,
        techLevel: 1,
        productFamilies: ships,
        productionClasses: factions
      )
    )
    #expect(
      !ManufacturingOpportunityCatalogFilter.accepts(
        categoryName: "Ship",
        groupName: "Frigate",
        metaGroupID: 1,
        techLevel: 1,
        productFamilies: ships,
        productionClasses: factions
      )
    )
    #expect(
      !ManufacturingOpportunityCatalogFilter.accepts(
        categoryName: "Module",
        groupName: "Armor Repair Unit",
        metaGroupID: 4,
        techLevel: 1,
        productFamilies: ships,
        productionClasses: factions
      )
    )
    #expect(
      ManufacturingOpportunityCatalogFilter.accepts(
        activityKind: .reaction,
        categoryName: "Material",
        groupName: "Molecular-Forged Materials",
        metaGroupID: nil,
        techLevel: nil,
        productFamilies: [.reactions],
        productionClasses: [.other]
      )
    )
    #expect(
      !ManufacturingOpportunityCatalogFilter.accepts(
        activityKind: .reaction,
        categoryName: "Material",
        groupName: "Molecular-Forged Materials",
        metaGroupID: nil,
        techLevel: nil,
        productFamilies: [.components],
        productionClasses: [.other]
      )
    )
  }

  @Test
  func marketOpportunitiesUseReactionRulesWithoutMEOrBlueprintAllocation() throws {
    let source = SourceIdentity(provider: "Synthetic SDE", version: "reaction-v1")
    let inputTypeID: Int64 = 91_000_101
    let productTypeID: Int64 = 91_000_102
    let formulaTypeID: Int64 = 91_000_103
    let definition = BlueprintDefinition(
      blueprintTypeID: formulaTypeID,
      productTypeID: productTypeID,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .reaction,
        durationSeconds: 180,
        materials: [BlueprintMaterial(typeID: inputTypeID, quantity: 100)],
        products: [
          BlueprintProduct(typeID: productTypeID, quantity: 200, probability: nil)
        ]
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
        inputTypeID: [
          marketOrder(
            id: 91_000_201,
            typeID: inputTypeID,
            side: .sell,
            price: 2,
            volume: 10_000
          )
        ],
        productTypeID: [
          marketOrder(
            id: 91_000_202,
            typeID: productTypeID,
            side: .sell,
            price: 5,
            volume: 10_000
          ),
          marketOrder(
            id: 91_000_203,
            typeID: productTypeID,
            side: .buy,
            price: 4,
            volume: 10_000
          ),
        ],
      ],
      source: source
    )
    let reactionFacility = ReactionFacilityCostContext(
      name: "Synthetic Tatara",
      materialMultiplier: 0.9,
      timeMultiplier: 0.8,
      jobCostMultiplier: 1,
      facilityTaxRate: 0,
      systemCostIndex: 0.1,
      sccSurchargeRate: 0.04,
      alphaSurchargeRate: 0,
      ruleVersion: "synthetic-reaction-v1"
    )

    let snapshot = try ManufacturingOpportunityAnalyzer.analyze(
      definitions: [definition],
      typeNames: [
        inputTypeID: "Synthetic Reaction Input",
        productTypeID: "Synthetic Reaction Product",
      ],
      classifications: [
        productTypeID: IndustryItemClassification(
          categoryName: "Material",
          groupName: "Molecular-Forged Materials",
          manufacturingCategory: .module
        )
      ],
      packagedVolumes: [inputTypeID: 1, productTypeID: 2],
      settings: ManufacturingOpportunitySettings(requestedRuns: 3),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      logisticsConfiguration: LogisticsConfiguration(),
      market: market,
      adjustedPrices: [
        inputTypeID: AdjustedPrice(
          typeID: inputTypeID,
          adjustedPrice: 1,
          averagePrice: nil
        )
      ],
      facilities: [:],
      reactionFacility: reactionFacility,
      salesTaxRate: 0.10,
      brokerFeeRate: 0.05
    )

    #expect(snapshot.coverage.completeManufacturingDefinitionCount == 0)
    #expect(snapshot.coverage.completeReactionDefinitionCount == 1)
    let row = try #require(snapshot.rows.first)
    #expect(row.effectiveActivityKind == .reaction)
    #expect(row.supportsBlueprintEfficiency == false)
    #expect(row.displayedMaterialEfficiency == nil)
    #expect(row.displayedTimeEfficiency == nil)
    #expect(row.runs == 3)
    #expect(row.producedQuantity == 600)
    #expect(row.materials.first?.quantity == 270)
    #expect(row.materialCost == 540)
    #expect(abs((row.installationCost ?? 0) - 42) < 0.000_001)
    #expect(row.durationSeconds == 432)
    #expect(row.grossRevenue == 3_000)
    #expect(row.contributionProfit == 1_968)

    let projected = try #require(
      ManufacturingOpportunityRunProjector.project(
        row,
        requestedRuns: 4,
        materialEfficiency: 10,
        timeEfficiency: 20
      )
    )
    #expect(projected.materialEfficiency == 0)
    #expect(projected.timeEfficiency == 0)
    #expect(projected.materials.first?.quantity == 360)
    #expect(projected.producedQuantity == 800)
    #expect(projected.durationSeconds == 576)

    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(
        includesBlueprintAllocation: true,
        blueprintAllocationPerRun: 1_000
      )
    )
    #expect(costs.blueprintAllocation == 0)
    #expect(abs((costs.totalCost ?? 0) - 582) < 0.000_001)
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
  func opportunityLogisticsPricesInboundShortfallAndFullOutboundProduct()
    throws
  {
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
        homeTradeHub: .legacy(name: "Home Factory"),
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )

    #expect(procurement.lines.first?.fromWarehouse == 7)
    #expect(procurement.lines.first?.toBuy == 11)
    #expect(logistics.cost == 2_000_000)
    #expect(logistics.legs.count == 2)
    #expect(logistics.legs.first?.cargoVolumeM3 == 55)
    #expect(logistics.legs.first?.collateral == 110)
    #expect(logistics.legs.last?.kind == .outboundProducts)
    #expect(logistics.legs.last?.cargoVolumeM3 == 18)
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics
    )
    #expect(costs.logisticsCost == 2_000_000)
    #expect(costs.totalCost == 2_000_180)
    #expect(costs.profit == -1_999_980)

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
        homeTradeHub: .legacy(name: "Home Factory"),
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )
    #expect(noHaul.cost == 1_000_000)
    #expect(noHaul.legs.count == 1)
    #expect(noHaul.legs.first?.kind == .outboundProducts)
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
        homeTradeHub: .legacy(name: "Home Factory"),
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
  func disabledRoundTripLogisticsDoesNotBecomeZeroProfitInput() {
    let row = sortableOpportunityRow(name: "Product", value: 1, demand: 1)
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
        isEnabled: false,
        homeTradeHub: .legacy(name: "Home Factory")
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics
    )

    #expect(logistics.cost == nil)
    #expect(
      logistics.warnings.contains {
        $0.code == "manufacturing-opportunity.round-trip-logistics-disabled"
      }
    )
    #expect(costs.profit == nil)
  }

  @Test
  func identicalMainAndHomeHubHaveNoRoundTripCost() {
    let row = sortableOpportunityRow(name: "Product", value: 1, demand: 1)
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: ManufacturingOpportunityScenarioProjector.procurement(
        for: row,
        factualWarehouseQuantities: [:],
        protectedQuantities: [:],
        reservedQuantities: [:]
      ),
      configuration: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: ProcurementLocation.jita.name,
        homeTradeHub: .jita,
        iskPerCubicMeter: nil
      ),
      mainHub: .jita,
      warehouseIsAvailable: false
    )

    #expect(logistics.cost == 0)
    #expect(logistics.legs.isEmpty)
    #expect(logistics.warnings.isEmpty)
  }

  @Test
  func explicitProductionLocationPreventsFalseZeroMainHubLogistics() {
    let row = sortableOpportunityRow(name: "Product", value: 1, demand: 1)
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: ManufacturingOpportunityScenarioProjector.procurement(
        for: row,
        factualWarehouseQuantities: [34: 1],
        protectedQuantities: [:],
        reservedQuantities: [:]
      ),
      configuration: LogisticsConfiguration(
        isEnabled: true,
        productionLocationName: "UALX-3 - Production",
        homeTradeHub: .jita,
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true
    )

    #expect(logistics.cost == 1_000_000)
    #expect(logistics.legs.count == 1)
    #expect(logistics.legs.first?.origin == "UALX-3 - Production")
    #expect(logistics.legs.first?.destination == ProcurementLocation.jita.name)
    #expect(logistics.legs.first?.kind == .outboundProducts)
  }

  @Test
  func equalDisplayNamesDoNotHideDifferentLocationIdentities() {
    let row = sortableOpportunityRow(name: "Product", value: 1, demand: 1)
    let mainHub = ProcurementLocation(
      id: "npc:1",
      name: "Same visible name",
      locationID: 1,
      kind: .npcTradeHub
    )
    let homeHub = ProcurementLocation(
      id: "npc:2",
      name: "Same visible name",
      locationID: 2,
      kind: .npcTradeHub
    )
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: ManufacturingOpportunityScenarioProjector.procurement(
        for: row,
        factualWarehouseQuantities: [:],
        protectedQuantities: [:],
        reservedQuantities: [:]
      ),
      configuration: LogisticsConfiguration(
        isEnabled: true,
        homeTradeHub: homeHub,
        iskPerCubicMeter: 100
      ),
      mainHub: mainHub,
      warehouseIsAvailable: true
    )

    #expect(logistics.cost == 2_000_000)
    #expect(logistics.legs.count == 2)
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
      .dailyProfitPotential,
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
  func materialPurchaseBudgetRejectsUnknownAndAcceptsOnlyKnownCashWithinLimit() {
    #expect(
      ManufacturingOpportunityBudgetFilter.accepts(
        maximumMaterialPurchaseISK: nil,
        purchaseCashRequirement: nil
      )
    )
    #expect(
      ManufacturingOpportunityBudgetFilter.accepts(
        maximumMaterialPurchaseISK: 1_000,
        purchaseCashRequirement: 1_000
      )
    )
    #expect(
      !ManufacturingOpportunityBudgetFilter.accepts(
        maximumMaterialPurchaseISK: 1_000,
        purchaseCashRequirement: 1_001
      )
    )
    #expect(
      !ManufacturingOpportunityBudgetFilter.accepts(
        maximumMaterialPurchaseISK: 1_000,
        purchaseCashRequirement: nil
      )
    )
  }

  @Test
  func guidedScreeningKeepsCompleteRankingAndAppliesMaterialPurchaseBudget() {
    let rows = (1...25).map { index in
      sortableOpportunityRow(
        name: "Candidate \(index)",
        value: Int64(index),
        demand: Int64(index),
        materialQuantity: Int64(index),
        materialUnitPrice: 1
      )
    }
    let snapshot = opportunitySnapshot(rows: rows)

    let complete = ManufacturingOpportunityScreening.candidates(
      snapshot: snapshot,
      query: "",
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:],
      maximumMaterialPurchaseISK: nil
    )
    let budgeted = ManufacturingOpportunityScreening.candidates(
      snapshot: snapshot,
      query: "",
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:],
      maximumMaterialPurchaseISK: 10
    )

    #expect(complete.count == 25)
    #expect(budgeted.count == 10)
    #expect(
      budgeted.allSatisfy {
        ($0.purchaseCashRequirement ?? .infinity) <= 10
      }
    )
  }

  @Test
  func guidedScreeningCombinesCatalogCategoryGroupAndLoyaltyFilters() {
    let factionShip = sortableOpportunityRow(
      name: "Faction Ship",
      value: 1,
      demand: 1,
      blueprintTypeID: 101,
      categoryName: "Ship",
      groupName: "Battleship",
      metaGroupID: 4,
      techLevel: 1
    )
    let factionModule = sortableOpportunityRow(
      name: "Faction Module",
      value: 2,
      demand: 1,
      blueprintTypeID: 102,
      categoryName: "Module",
      groupName: "Armor Module",
      metaGroupID: 4,
      techLevel: 1
    )
    let techIIShip = sortableOpportunityRow(
      name: "Tech II Ship",
      value: 3,
      demand: 1,
      blueprintTypeID: 103,
      categoryName: "Ship",
      groupName: "Battleship",
      metaGroupID: 2,
      techLevel: 2
    )
    let snapshot = opportunitySnapshot(
      rows: [factionShip, factionModule, techIIShip]
    )

    let filtered = ManufacturingOpportunityScreening.candidates(
      snapshot: snapshot,
      query: "",
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:],
      maximumMaterialPurchaseISK: nil,
      productFamilies: [.ships],
      productionClasses: [.faction],
      selectedCategory: "Ship",
      selectedGroup: "Battleship",
      loyaltyStoreBlueprintsOnly: true,
      loyaltyStoreBlueprintTypeIDs: [101, 103]
    )

    #expect(filtered.map(\.row.productTypeID) == [1])
  }

  @Test
  func opportunitySettingsClampQuantityRunsAndResearchToSupportedRanges() {
    let settings = ManufacturingOpportunitySettings(
      targetQuantity: Int64.max,
      requestedRuns: Int.max,
      materialEfficiency: 42,
      timeEfficiency: 420
    )
    #expect(
      settings.targetQuantity
        == ManufacturingOpportunitySettings.maximumTargetQuantity
    )
    #expect(
      settings.requestedRuns
        == ManufacturingOpportunitySettings.maximumRequestedRuns
    )
    #expect(settings.materialEfficiency == 10)
    #expect(settings.timeEfficiency == 20)
  }

  @Test
  func mainHubOpportunityBaselineDefersMEAndTEToConcreteProduction() {
    let settings = ManufacturingOpportunitySettings(
      targetQuantity: 4,
      requestedRuns: 3,
      materialEfficiency: 10,
      timeEfficiency: 20
    ).mainHubOpportunityBaseline

    #expect(settings.targetQuantity == 4)
    #expect(settings.requestedRuns == nil)
    #expect(settings.materialEfficiency == 0)
    #expect(settings.timeEfficiency == 0)
  }

  @Test
  func opportunityEfficiencyDefaultsDistinguishT1ModulesAndLoyaltyStoreBPCs() {
    let researchedT1Module = ManufacturingOpportunityEfficiencyDefaults.resolve(
      blueprintTypeID: 101,
      categoryName: "Module",
      groupName: "Armor Repair Unit",
      metaGroupID: 1,
      techLevel: 1,
      fallbackMaterialEfficiency: 0,
      fallbackTimeEfficiency: 0,
      loyaltyStoreBlueprintTypeIDs: []
    )
    #expect(
      researchedT1Module
        == ManufacturingOpportunityEfficiencyAssumption(
          materialEfficiency: 10,
          timeEfficiency: 20
        )
    )

    let loyaltyStoreCopy = ManufacturingOpportunityEfficiencyDefaults.resolve(
      blueprintTypeID: 101,
      categoryName: "Module",
      groupName: "Armor Repair Unit",
      metaGroupID: 1,
      techLevel: 1,
      fallbackMaterialEfficiency: 10,
      fallbackTimeEfficiency: 20,
      loyaltyStoreBlueprintTypeIDs: [101]
    )
    #expect(
      loyaltyStoreCopy
        == ManufacturingOpportunityEfficiencyAssumption(
          materialEfficiency: 0,
          timeEfficiency: 0
        )
    )

    let t1Ship = ManufacturingOpportunityEfficiencyDefaults.resolve(
      blueprintTypeID: 102,
      categoryName: "Ship",
      groupName: "Frigate",
      metaGroupID: 1,
      techLevel: 1,
      fallbackMaterialEfficiency: 4,
      fallbackTimeEfficiency: 8,
      loyaltyStoreBlueprintTypeIDs: []
    )
    #expect(
      t1Ship
        == ManufacturingOpportunityEfficiencyAssumption(
          materialEfficiency: 4,
          timeEfficiency: 8
        )
    )
  }

  @Test
  func runProjectorRecalculatesOnlyTheRequestedRowFromCapturedPrices() throws {
    let original = sortableOpportunityRow(
      name: "Requested item",
      value: 2,
      demand: 30,
      materialQuantity: 3,
      materialUnitPrice: 4
    )

    let projected = try #require(
      ManufacturingOpportunityRunProjector.project(
        original,
        requestedRuns: 5
      )
    )

    #expect(original.runs == 2)
    #expect(original.producedQuantity == 2)
    #expect(projected.runs == 5)
    #expect(projected.producedQuantity == 5)
    #expect(projected.durationSeconds == 5)
    #expect(projected.materials.first?.quantity == 8)
    #expect(projected.materials.first?.quote.weightedUnitPrice == 4)
    #expect(projected.materials.first?.quote.total == 32)
    #expect(projected.materialCost == 32)
    #expect(projected.grossRevenue == 92.5)
    #expect(
      projected.warnings.contains {
        $0.code == "manufacturing-opportunity.run-projection"
      }
    )
  }

  @Test
  func runProjectorRejectsInvalidRequestedRuns() {
    let row = sortableOpportunityRow(name: "Item", value: 1, demand: nil)

    #expect(
      ManufacturingOpportunityRunProjector.project(row, requestedRuns: 0)
        == nil
    )
    #expect(
      ManufacturingOpportunityRunProjector.project(
        row,
        requestedRuns:
          ManufacturingOpportunitySettings.maximumRequestedRuns + 1
      ) == nil
    )
  }

  @Test
  func runProjectorAppliesExactMEAndTEInputsWhenScanHasSDEBasis() throws {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let row = ManufacturingOpportunityRow(
      blueprintTypeID: 1,
      productTypeID: 2,
      productName: "Tech II Product",
      categoryName: "Ship",
      groupName: "Expedition Frigate",
      metaGroupID: 2,
      techLevel: 2,
      facilityName: "Sotiyo",
      facilityMaterialMultiplier: 0.98,
      facilityTimeMultiplier: 0.9,
      activityDurationSecondsPerRun: 3_600,
      runs: 1,
      outputPerRun: 1,
      producedQuantity: 1,
      materialEfficiency: 0,
      timeEfficiency: 0,
      durationSeconds: 3_240,
      observedDailyDemand: 1,
      activeBuyDemand: 1,
      activeSellSupply: 1,
      materials: [
        ManufacturingOpportunityMaterial(
          typeID: 34,
          name: "Material",
          baseQuantityPerRun: 100,
          quantity: 98,
          quote: PriceQuote(
            id: UUID(),
            typeID: 34,
            quantity: 98,
            scenario: .materialBuy,
            total: 980,
            weightedUnitPrice: 10,
            filledQuantity: 98,
            capturedAt: .now,
            source: source,
            warnings: []
          ),
          packagedVolumePerUnit: 1
        )
      ],
      materialCost: 980,
      installationCost: 100,
      productionCostBeforeBlueprintAndLogistics: 1_080,
      grossRevenue: 4_000,
      salesTax: 100,
      brokerFee: 50,
      netRevenue: 3_850,
      contributionProfit: 2_770,
      returnOnInvestment: 2_770.0 / 1_080.0,
      iskPerHour: nil,
      iskPerCubicMeter: nil,
      packagedVolumePerUnit: 1,
      warnings: []
    )

    let projected = try #require(
      ManufacturingOpportunityRunProjector.project(
        row,
        requestedRuns: 2,
        materialEfficiency: 3,
        timeEfficiency: 2
      )
    )

    #expect(projected.materialEfficiency == 3)
    #expect(projected.timeEfficiency == 2)
    #expect(projected.materials.first?.quantity == 191)
    #expect(projected.materialCost == 1_910)
    #expect(projected.durationSeconds == 6_351)
    #expect(projected.installationCost == 200)
    #expect(
      !projected.warnings.contains {
        $0.code == "manufacturing-opportunity.efficiency-approximation"
      }
    )
  }

  @Test
  func averageDailyDemandQuickFilterPreservesUnknownOnlyWhenDisabled() {
    #expect(
      ManufacturingOpportunityAverageDemandFilter.accepts(
        minimumAverageDailyDemand: 0,
        averageDailyDemand: nil
      )
    )
    #expect(
      !ManufacturingOpportunityAverageDemandFilter.accepts(
        minimumAverageDailyDemand: 1,
        averageDailyDemand: nil
      )
    )
    #expect(
      !ManufacturingOpportunityAverageDemandFilter.accepts(
        minimumAverageDailyDemand: 2,
        averageDailyDemand: 1
      )
    )
    #expect(
      ManufacturingOpportunityAverageDemandFilter.accepts(
        minimumAverageDailyDemand: 2,
        averageDailyDemand: 2
      )
    )
  }

  @Test
  func legacyQuantitySettingsDecodeWithoutInventingExplicitRuns() throws {
    let legacy = Data(
      #"{"targetQuantity":5,"materialEfficiency":10,"timeEfficiency":20}"#
        .utf8
    )
    let settings = try JSONDecoder().decode(
      ManufacturingOpportunitySettings.self,
      from: legacy
    )

    #expect(settings.requestedRuns == nil)
    #expect(settings.resolvedRuns(outputPerRun: 2) == 3)
  }

  @Test
  func dailyProfitPotentialIsLimitedBySelectedBatchAndDemand() {
    let belowBatchDemand = sortableOpportunityRow(
      name: "Below batch demand",
      value: 10,
      demand: 5
    )
    let matchingDemand = sortableOpportunityRow(
      name: "Matching demand",
      value: 10,
      demand: 10
    )
    let aboveBatchDemand = sortableOpportunityRow(
      name: "Above batch demand",
      value: 10,
      demand: 1_000
    )
    let batchProfit = sortableCosts(value: 100)

    #expect(
      ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
        for: belowBatchDemand,
        costs: batchProfit
      ) == 50
    )
    #expect(
      ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
        for: matchingDemand,
        costs: batchProfit
      ) == 100
    )
    #expect(
      ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
        for: aboveBatchDemand,
        costs: batchProfit
      ) == 100
    )
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

  // MARK: Hub roles (HUB_CHANCEN_PLAN P3)

  private static let roleTestHomeHub = ProcurementLocation(
    id: "structure:1035000000001",
    name: "Home Keepstar",
    locationID: 1_035_000_000_001,
    kind: .playerStructure,
    solarSystemID: 30_004_000,
    regionID: 10_000_060
  )

  private func roleTestInputs() -> (
    definitions: [BlueprintDefinition],
    market: MarketOrderSnapshot,
    facility: ManufacturingOpportunityFacilityContext
  ) {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let definition = BlueprintDefinition(
      blueprintTypeID: 200,
      productTypeID: 100,
      maxProductionLimit: 100,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing,
        durationSeconds: 3_600,
        materials: [BlueprintMaterial(typeID: 34, quantity: 10)],
        products: [BlueprintProduct(typeID: 100, quantity: 1, probability: nil)]
      ),
      source: source
    )
    let market = MarketOrderSnapshot(
      id: UUID(),
      regionID: 10_000_002,
      locationID: 60_003_760,
      capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
      state: .fresh,
      ordersByType: [
        34: [marketOrder(id: 1, typeID: 34, side: .sell, price: 10, volume: 1_000)],
        100: [marketOrder(id: 2, typeID: 100, side: .sell, price: 200, volume: 100)],
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
    return ([definition], market, facility)
  }

  private func roleTestAnalyze(
    hubRole: OpportunityHubRole = .main,
    saleHub: ProcurementLocation? = nil,
    saleMarket: MarketOrderSnapshot? = nil,
    usesDefaults: Bool = false,
    inputs suppliedInputs: (
      definitions: [BlueprintDefinition],
      market: MarketOrderSnapshot,
      facility: ManufacturingOpportunityFacilityContext
    )? = nil,
    coalitionTransport: OpportunityCoalitionTransportBasis? = nil
  ) throws -> ManufacturingOpportunitySnapshot {
    let inputs = suppliedInputs ?? roleTestInputs()
    let settings = ManufacturingOpportunitySettings(
      targetQuantity: 5,
      requestedRuns: nil,
      materialEfficiency: 0,
      timeEfficiency: 0
    )
    let adjusted: [Int64: AdjustedPrice] = [
      34: AdjustedPrice(typeID: 34, adjustedPrice: 2, averagePrice: nil)
    ]
    if usesDefaults {
      return try ManufacturingOpportunityAnalyzer.analyze(
        definitions: inputs.definitions,
        typeNames: [34: "Tritanium", 100: "Fixture Product"],
        classifications: [:],
        packagedVolumes: [100: 5],
        settings: settings,
        mainHub: .jita,
        productionWarehouseScope: ProductionWarehouseScope(locations: []),
        market: inputs.market,
        adjustedPrices: adjusted,
        facilities: [.module: inputs.facility],
        salesTaxRate: 0.10,
        brokerFeeRate: 0.05
      )
    }
    return try ManufacturingOpportunityAnalyzer.analyze(
      definitions: inputs.definitions,
      typeNames: [34: "Tritanium", 100: "Fixture Product"],
      classifications: [:],
      packagedVolumes: [100: 5],
      settings: settings,
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      market: inputs.market,
      adjustedPrices: adjusted,
      facilities: [.module: inputs.facility],
      salesTaxRate: 0.10,
      brokerFeeRate: 0.05,
      hubRole: hubRole,
      saleHub: saleHub,
      saleMarket: saleMarket,
      coalitionTransport: coalitionTransport
    )
  }

  private func roleTestHomeMarket(
    productPrice: Double,
    remaining: Int64 = 40,
    capturedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
  ) -> MarketOrderSnapshot {
    let home = Self.roleTestHomeHub
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: home.regionID ?? 0,
      locationID: home.locationID ?? 0,
      capturedAt: capturedAt,
      state: .fresh,
      ordersByType: [
        100: [
          MarketOrder(
            id: 9,
            typeID: 100,
            locationID: home.locationID ?? 0,
            systemID: home.solarSystemID ?? 0,
            side: .sell,
            price: productPrice,
            volumeRemaining: remaining,
            minimumVolume: 1,
            issued: .now
          )
        ]
      ],
      source: SourceIdentity(provider: "Home fixture", version: "1")
    )
  }

  @Test
  func mainHubOpportunityScanStaysIdenticalWithExplicitMainRole() throws {
    let inputs = roleTestInputs()
    let defaults = try roleTestAnalyze(usesDefaults: true, inputs: inputs)
    let explicit = try roleTestAnalyze(hubRole: .main, inputs: inputs)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Rows carry fresh warning-source identities, so compare factual values.
    func facts(_ row: ManufacturingOpportunityRow) -> [String] {
      [
        "\(row.productTypeID)", "\(row.runs)", "\(row.producedQuantity)",
        "\(row.durationSeconds)", "\(row.activeBuyDemand)",
        "\(row.activeSellSupply)", "\(String(describing: row.materialCost))",
        "\(String(describing: row.installationCost))",
        "\(String(describing: row.grossRevenue))",
        "\(String(describing: row.salesTax))",
        "\(String(describing: row.brokerFee))",
        "\(String(describing: row.netRevenue))",
        "\(String(describing: row.contributionProfit))",
        "\(String(describing: row.returnOnInvestment))",
        "\(String(describing: row.iskPerHour))",
        "\(row.materials.map { "\($0.typeID):\($0.quantity)" })",
        "\(row.warnings.map(\.code))",
      ]
    }
    #expect(defaults.rows.map(facts) == explicit.rows.map(facts))
    #expect(defaults.rows.count == 1)
    #expect(defaults.coverage == explicit.coverage)
    #expect(defaults.warnings.map(\.code) == explicit.warnings.map(\.code))
    #expect(defaults.hubRole == nil)
    #expect(defaults.saleHub == nil)
    #expect(defaults.resolvedHubRole == .main)
    #expect(defaults.resolvedSaleHub == .jita)
    #expect(defaults.marketSource == explicit.marketSource)

    // Main-Hub files keep their historical keys: no role fields are written,
    // and a file without them decodes as a Main-Hub scan.
    let json = try #require(
      String(data: encoder.encode(defaults), encoding: .utf8)
    )
    #expect(!json.contains("hubRole"))
    #expect(!json.contains("saleHub"))
    let decoded = try JSONDecoder().decode(
      ManufacturingOpportunitySnapshot.self,
      from: encoder.encode(defaults)
    )
    #expect(decoded.resolvedHubRole == .main)
  }

  @Test
  func homeHubScanSellsAtItsOwnMarketButBuysMaterialsAtTheMainHub() throws {
    let inputs = roleTestInputs()
    let main = try roleTestAnalyze(inputs: inputs)
    let home = try roleTestAnalyze(
      hubRole: .home,
      saleHub: Self.roleTestHomeHub,
      saleMarket: roleTestHomeMarket(productPrice: 300),
      inputs: inputs
    )
    let mainRow = try #require(main.rows.first)
    let homeRow = try #require(home.rows.first)
    #expect(homeRow.materialCost == mainRow.materialCost)
    #expect(mainRow.grossRevenue == 200 * Double(mainRow.producedQuantity))
    #expect(homeRow.grossRevenue == 300 * Double(homeRow.producedQuantity))
    #expect(homeRow.activeSellSupply == 40)
    #expect(home.hubRole == .home)
    #expect(home.saleHub == Self.roleTestHomeHub)
    #expect(home.mainHub == .jita)
    #expect(home.marketSource.provider == "Home fixture")

    let decoded = try JSONDecoder().decode(
      ManufacturingOpportunitySnapshot.self,
      from: JSONEncoder().encode(home)
    )
    #expect(decoded.resolvedHubRole == .home)
    #expect(decoded.resolvedSaleHub == Self.roleTestHomeHub)
  }

  @Test
  func fullStructureBookKeepsHubOpportunityResultsAndProductDemand() throws {
    let inputs = roleTestInputs()
    let productOnly = roleTestHomeMarket(productPrice: 300)
    let fullBook = roleTestFullStructureBook(productPrice: 300)
    // The structure scan now loads the whole book (HANDEL_PLAN P3); the
    // analysis receives it restricted to the product types it had before.
    let before = try roleTestAnalyze(
      hubRole: .home,
      saleHub: Self.roleTestHomeHub,
      saleMarket: productOnly,
      inputs: inputs
    )
    let after = try roleTestAnalyze(
      hubRole: .home,
      saleHub: Self.roleTestHomeHub,
      saleMarket: fullBook.restricted(to: [100]),
      inputs: inputs
    )
    func facts(_ row: ManufacturingOpportunityRow) -> [String] {
      [
        "\(row.productTypeID)", "\(row.activeBuyDemand)",
        "\(row.activeSellSupply)", "\(String(describing: row.grossRevenue))",
        "\(String(describing: row.netRevenue))",
        "\(String(describing: row.contributionProfit))",
        "\(String(describing: row.returnOnInvestment))",
        "\(row.warnings.map(\.code))",
      ]
    }
    #expect(before.rows.map(facts) == after.rows.map(facts))
    #expect(before.coverage == after.coverage)
    // Without the restriction the extra trade items would change coverage.
    let unrestricted = try roleTestAnalyze(
      hubRole: .home,
      saleHub: Self.roleTestHomeHub,
      saleMarket: fullBook,
      inputs: inputs
    )
    #expect(
      unrestricted.coverage.mainHubActiveOrderTypeCount
        > before.coverage.mainHubActiveOrderTypeCount
    )

    // The demand ledger is keyed by order: extra items add their own demand
    // without changing the product's measured units.
    var productLedger = ManufacturingOpportunityDemandLedger()
    var fullLedger = ManufacturingOpportunityDemandLedger()
    productLedger.observe(productOnly)
    fullLedger.observe(fullBook)
    let later = Date(timeIntervalSince1970: 1_800_003_600)
    let productDemand = productLedger.observe(
      roleTestHomeMarket(productPrice: 300, remaining: 25, capturedAt: later)
    )
    let fullDemand = fullLedger.observe(
      roleTestFullStructureBook(productPrice: 300, remaining: 25, capturedAt: later)
    )
    #expect(productDemand.observedUnits(for: 100) == 15)
    #expect(fullDemand.observedUnits(for: 100) == 15)
    #expect(fullDemand.observedUnits(for: 777) == 3)
    #expect(productDemand.observedUnits(for: 777) == nil)
  }

  private func roleTestFullStructureBook(
    productPrice: Double,
    remaining: Int64 = 40,
    capturedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
  ) -> MarketOrderSnapshot {
    let home = Self.roleTestHomeHub
    let product = roleTestHomeMarket(
      productPrice: productPrice,
      remaining: remaining,
      capturedAt: capturedAt
    )
    func order(_ id: Int64, _ typeID: Int64, _ side: MarketOrderSide, _ volume: Int64)
      -> MarketOrder
    {
      MarketOrder(
        id: id,
        typeID: typeID,
        locationID: home.locationID ?? 0,
        systemID: home.solarSystemID ?? 0,
        side: side,
        price: side == .sell ? 50 : 40,
        volumeRemaining: volume,
        minimumVolume: 1,
        issued: .now
      )
    }
    var orders = product.ordersByType
    orders[777] = [
      order(70, 777, .sell, remaining == 40 ? 10 : 7),
      order(71, 777, .buy, 5),
    ]
    orders[778] = [order(72, 778, .buy, 9)]
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: product.regionID,
      locationID: product.locationID,
      capturedAt: capturedAt,
      state: .fresh,
      ordersByType: orders,
      source: SourceIdentity(provider: "Home fixture", version: "1")
    )
  }

  @Test
  func hubRolesRejectMissingOrMismatchedSaleMarkets() {
    #expect(throws: ManufacturingOpportunityError.inconsistentMarketLocation) {
      try roleTestAnalyze(hubRole: .home, saleHub: Self.roleTestHomeHub)
    }
    #expect(throws: ManufacturingOpportunityError.inconsistentMarketLocation) {
      try roleTestAnalyze(
        hubRole: .coalition,
        saleHub: .jita,
        saleMarket: roleTestHomeMarket(productPrice: 1)
      )
    }
    #expect(throws: ManufacturingOpportunityError.inconsistentMarketLocation) {
      try roleTestAnalyze(
        hubRole: .main,
        saleHub: Self.roleTestHomeHub,
        saleMarket: roleTestHomeMarket(productPrice: 1)
      )
    }
  }

  @Test
  func saleRoutesKeepMainRoundTripAndDropTheReturnLegForOtherHubs() {
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
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:]
    )
    let configuration = LogisticsConfiguration(
      isEnabled: true,
      includeInboundMaterials: true,
      includeOutboundProducts: false,
      productionLocationName: "Home Factory",
      homeTradeHub: .legacy(name: "Home Factory"),
      iskPerCubicMeter: 100
    )
    func logistics(
      _ route: ManufacturingOpportunitySaleRoute?
    ) -> ManufacturingOpportunityLogisticsProjection {
      guard let route else {
        return ManufacturingOpportunityScenarioProjector.logistics(
          for: row,
          procurement: procurement,
          configuration: configuration,
          mainHub: .jita,
          warehouseIsAvailable: true
        )
      }
      return ManufacturingOpportunityScenarioProjector.logistics(
        for: row,
        procurement: procurement,
        configuration: configuration,
        mainHub: .jita,
        warehouseIsAvailable: true,
        route: route
      )
    }
    let defaultRoute = logistics(nil)
    let mainRoute = logistics(.mainHubRoundTrip)
    #expect(defaultRoute.cost == 2_000_000)
    #expect(mainRoute.cost == defaultRoute.cost)
    #expect(mainRoute.legs.map(\.kind) == defaultRoute.legs.map(\.kind))

    let homeFactory = ProcurementLocation.legacy(name: "Home Factory")
    let home = logistics(.homeHub(homeFactory))
    #expect(home.cost == 1_000_000)
    #expect(home.legs.map(\.kind) == [.inboundMaterials])

    let coalition = logistics(
      .coalitionHub(homeHub: homeFactory, onwardTransportCost: 5_000_000)
    )
    #expect(coalition.cost == 6_000_000)
    #expect(coalition.legs.map(\.kind) == [.inboundMaterials])

    let unknownOnward = logistics(
      .coalitionHub(homeHub: homeFactory, onwardTransportCost: nil)
    )
    #expect(unknownOnward.cost == nil)
    #expect(
      unknownOnward.warnings.map(\.code)
        == ["manufacturing-opportunity.coalition-transport-unavailable"]
    )

    // A production site away from the Home Hub adds the hop to the Home Hub.
    let remoteHome = logistics(.homeHub(.legacy(name: "Remote Home Hub")))
    #expect(remoteHome.legs.map(\.kind) == [.inboundMaterials, .outboundProducts])
    #expect(remoteHome.cost == 2_000_000)
  }

  @Test
  func hubRoleFilesKeepMainNamesAndSeparateOtherRoles() {
    #expect(OpportunityHubRole.main.demandFileName == "main-hub-demand.json")
    #expect(
      OpportunityHubRole.main.opportunitiesFileName
        == "main-hub-opportunities.json"
    )
    #expect(OpportunityHubRole.home.demandFileName == "home-hub-demand.json")
    #expect(
      OpportunityHubRole.coalition.opportunitiesFileName
        == "coalition-hub-opportunities.json"
    )
    let names = OpportunityHubRole.allCases.flatMap {
      [$0.demandFileName, $0.opportunitiesFileName]
    }
    #expect(Set(names).count == names.count)
  }

  @Test
  func hubRoleKeysKeepMainAndRouteFollowsTheSnapshotRole() throws {
    #expect(
      OpportunityHubRole.main.storageKey("market-opportunities.filter.value")
        == "market-opportunities.filter.value"
    )
    #expect(
      OpportunityHubRole.home.storageKey("market-opportunities.filter.value")
        == "market-opportunities.home.filter.value"
    )
    #expect(
      OpportunityHubRole.home.storageKey(
        "manufacturing-opportunity.maximum-material-purchase-isk"
      ) == "manufacturing-opportunity.home.maximum-material-purchase-isk"
    )
    #expect(OpportunityHubRole.coalition.storageKey("plain") == "plain.coalition")

    let inputs = roleTestInputs()
    let main = try roleTestAnalyze(inputs: inputs)
    #expect(main.defaultSaleRoute == .mainHubRoundTrip)
    let home = try roleTestAnalyze(
      hubRole: .home,
      saleHub: Self.roleTestHomeHub,
      saleMarket: roleTestHomeMarket(productPrice: 300),
      inputs: inputs
    )
    #expect(home.defaultSaleRoute == .homeHub(Self.roleTestHomeHub))
  }

  @Test
  func coalitionTransportBasisPricesCourierAndKeepsCapitalsUnavailable() throws {
    let home = ProcurementLocation.legacy(name: "Home Factory")
    let courier = OpportunityCoalitionTransportBasis.courier(
      homeHub: home,
      coalitionHub: Self.roleTestHomeHub,
      iskPerCubicMeter: 100,
      maximumContractVolumeM3: 350_000
    )
    let row = sortableOpportunityRow(
      name: "Product",
      value: 18,
      demand: 1,
      materialQuantity: 18,
      materialUnitPrice: 10,
      materialVolume: 5
    )
    // 18 m³ × 100 ISK stays below the 0.5% collateral floor rounded to 1M.
    #expect(courier.transport(for: row).cost == 1_000_000)

    let carrier = sortableOpportunityRow(
      name: "Carrier",
      value: 1,
      demand: 1,
      categoryName: "Ship",
      groupName: "Carrier"
    )
    let courierCapital = courier.transport(for: carrier)
    #expect(courierCapital.cost == nil)
    #expect(courierCapital.warnings.map(\.code) == ["capital-self-jump.disabled"])

    let missing = OpportunityCoalitionTransportBasis.unavailable(
      homeHub: home,
      code: "coalition-transport.logistics-disabled",
      message: "disabled"
    )
    #expect(missing.transport(for: row).cost == nil)
    #expect(missing.homeHub == home)

    // The snapshot route carries the per-row onward cost into the logistics.
    let inputs = roleTestInputs()
    let coalition = try roleTestAnalyze(
      hubRole: .coalition,
      saleHub: Self.roleTestHomeHub,
      saleMarket: roleTestHomeMarket(productPrice: 300),
      inputs: inputs,
      coalitionTransport: courier
    )
    #expect(
      coalition.saleRoute(for: row)
        == .coalitionHub(homeHub: home, onwardTransportCost: 1_000_000)
    )
    #expect(
      coalition.defaultSaleRoute
        == .coalitionHub(homeHub: home, onwardTransportCost: nil)
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
        includeOutboundProducts: false,
        productionLocationName: "Home Factory",
        homeTradeHub: .legacy(name: "Home Factory"),
        iskPerCubicMeter: 100
      ),
      mainHub: .jita,
      warehouseIsAvailable: true,
      route: coalition.saleRoute(for: row)
    )
    #expect(logistics.cost == 2_000_000)

    // The basis survives the saved file; Main and Home scans never store one.
    let decoded = try JSONDecoder().decode(
      ManufacturingOpportunitySnapshot.self,
      from: JSONEncoder().encode(coalition)
    )
    #expect(decoded.resolvedHubRole == .coalition)
    #expect(decoded.saleRoute(for: row) == coalition.saleRoute(for: row))
    let main = try roleTestAnalyze(inputs: inputs, coalitionTransport: courier)
    #expect(main.coalitionTransport == nil)
  }

  @Test
  func coalitionOnwardTransportIsRecordedAndSortableWithUnknownValuesLast()
    throws
  {
    let home = ProcurementLocation.legacy(name: "Home Factory")
    let configuration = LogisticsConfiguration(
      isEnabled: true,
      includeInboundMaterials: true,
      includeOutboundProducts: false,
      productionLocationName: "Home Factory",
      homeTradeHub: .legacy(name: "Home Factory"),
      iskPerCubicMeter: 100
    )
    func costs(
      _ row: ManufacturingOpportunityRow,
      onward: Double?
    ) -> ManufacturingOpportunityCostProjection {
      let procurement = ManufacturingOpportunityScenarioProjector.procurement(
        for: row,
        factualWarehouseQuantities: [:],
        protectedQuantities: [:],
        reservedQuantities: [:]
      )
      let logistics = ManufacturingOpportunityScenarioProjector.logistics(
        for: row,
        procurement: procurement,
        configuration: configuration,
        mainHub: .jita,
        warehouseIsAvailable: true,
        route: .coalitionHub(homeHub: home, onwardTransportCost: onward)
      )
      return ManufacturingOpportunityScenarioProjector.costs(
        for: row,
        sheet: ManufacturingOpportunityCostSheet(),
        logistics: logistics
      )
    }
    let cheap = sortableOpportunityRow(name: "Cheap", value: 1, demand: 1)
    let costly = sortableOpportunityRow(name: "Costly", value: 2, demand: 1)
    let unknown = sortableOpportunityRow(name: "Unknown", value: 3, demand: 1)
    let cheapCosts = costs(cheap, onward: 1_000_000)
    let costlyCosts = costs(costly, onward: 3_000_000)
    let unknownCosts = costs(unknown, onward: nil)
    #expect(cheapCosts.onwardTransportCost == 1_000_000)
    #expect(costlyCosts.onwardTransportCost == 3_000_000)
    #expect(unknownCosts.onwardTransportCost == nil)
    #expect(unknownCosts.logisticsCost == nil)

    // Main and Home routes never report an onward amount.
    let homeRoute = ManufacturingOpportunityScenarioProjector.logistics(
      for: cheap,
      procurement: ManufacturingOpportunityScenarioProjector.procurement(
        for: cheap,
        factualWarehouseQuantities: [:],
        protectedQuantities: [:],
        reservedQuantities: [:]
      ),
      configuration: configuration,
      mainHub: .jita,
      warehouseIsAvailable: true,
      route: .homeHub(home)
    )
    #expect(homeRoute.onwardTransportCost == nil)

    let entries = [
      (unknown, unknownCosts), (costly, costlyCosts), (cheap, cheapCosts),
    ]
    func sorted(_ direction: ManufacturingOpportunitySortDirection) -> [String] {
      let descriptor = ManufacturingOpportunitySortDescriptor(
        column: .onwardTransport,
        direction: direction
      )
      return entries.sorted {
        descriptor.orderedBefore(
          lhs: $0.0,
          lhsCosts: $0.1,
          rhs: $1.0,
          rhsCosts: $1.1
        )
      }.map(\.0.productName)
    }
    #expect(sorted(.ascending) == ["Cheap", "Costly", "Unknown"])
    #expect(sorted(.descending) == ["Unknown", "Costly", "Cheap"])
  }

  private func contractReferences(
    unitPricesByType: [Int64: Double],
    complete: Bool
  ) throws -> PublicContractReferenceSnapshot {
    var prices: [Int64: PublicContractReferencePrice] = [:]
    for (typeID, price) in unitPricesByType {
      let offer = PublicContractSearchResult(
        contractID: typeID * 10,
        recordID: typeID * 10,
        regionID: 10_000_002,
        regionName: "The Forge",
        contractType: "item_exchange",
        price: price * 2,
        dateIssued: Date(timeIntervalSince1970: 1_800_000_000),
        dateExpired: Date(timeIntervalSince1970: 1_800_086_400),
        startLocationID: 60_003_760,
        typeID: typeID,
        isIncluded: true,
        quantity: 2,
        offeredLineCount: 1,
        requestedLineCount: 0
      )
      prices[typeID] = try #require(PublicContractReferencePrice(offer))
    }
    return PublicContractReferenceSnapshot(
      capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
      locationID: 0,
      locationName: "Entire universe",
      prices: prices,
      hasCompleteSearchCoverage: complete,
      source: SourceIdentity(provider: "ESI Public Contracts", version: "test")
    )
  }

  @Test
  func contractProjectionDeductsTheConfirmedFeeAndMarksMissingStates() throws {
    let row = sortableOpportunityRow(name: "Product", value: 10, demand: 1)
    let references = try contractReferences(
      unitPricesByType: [10: 50],
      complete: true
    )
    let total = 300.0
    let confirmed = ManufacturingOpportunityContractProjector.project(
      row: row,
      totalCost: total,
      context: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0.1
      )
    )
    #expect(confirmed.unitPrice == 50)
    #expect(confirmed.grossRevenue == 500)
    #expect(confirmed.contractFee == 50)
    #expect(confirmed.profit == 150)
    #expect(confirmed.returnOnInvestment == 0.5)
    #expect(!confirmed.isProvisional)
    #expect(!confirmed.isBeforeContractFee)

    let beforeFee = ManufacturingOpportunityContractProjector.project(
      row: row,
      totalCost: total,
      context: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: nil
      )
    )
    #expect(beforeFee.isBeforeContractFee)
    #expect(beforeFee.contractFee == nil)
    #expect(beforeFee.profit == 200)
    // An invalid rate is treated like a missing one, never as 0 %.
    #expect(
      ManufacturingOpportunityContractProjector.project(
        row: row,
        totalCost: total,
        context: ManufacturingOpportunityContractContext(
          references: references,
          contractFeeRate: 1.5
        )
      ).isBeforeContractFee
    )

    let provisional = ManufacturingOpportunityContractProjector.project(
      row: row,
      totalCost: total,
      context: ManufacturingOpportunityContractContext(
        references: try contractReferences(
          unitPricesByType: [10: 50],
          complete: false
        ),
        contractFeeRate: 0.1
      )
    )
    #expect(provisional.isProvisional)
    #expect(provisional.unitPrice == 50)

    let noOffer = ManufacturingOpportunityContractProjector.project(
      row: sortableOpportunityRow(name: "Other", value: 11, demand: 1),
      totalCost: total,
      context: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0.1
      )
    )
    #expect(noOffer.unitPrice == nil)
    #expect(noOffer.profit == nil)
    #expect(
      ManufacturingOpportunityContractProjector.project(
        row: row,
        totalCost: nil,
        context: ManufacturingOpportunityContractContext(
          references: references,
          contractFeeRate: 0.1
        )
      ).profit == nil
    )
  }

  private func bpcOffer(
    contractID: Int64,
    blueprintTypeID: Int64,
    runs: Int,
    price: Double
  ) -> PublicContractSearchResult {
    PublicContractSearchResult(
      contractID: contractID,
      recordID: contractID,
      regionID: 10_000_002,
      regionName: "The Forge",
      contractType: "item_exchange",
      price: price,
      dateIssued: Date(timeIntervalSince1970: 1_800_000_000),
      dateExpired: Date(timeIntervalSince1970: 1_800_086_400),
      startLocationID: 60_003_760,
      typeID: blueprintTypeID,
      isIncluded: true,
      quantity: 1,
      isBlueprintCopy: true,
      materialEfficiency: 0,
      timeEfficiency: 0,
      runs: runs,
      offeredLineCount: 1,
      requestedLineCount: 0
    )
  }

  @Test
  func loyaltyStoreAndFactionBlueprintsPriceTheBPCPurchaseIntoTheCost() throws {
    let logistics = ManufacturingOpportunityLogisticsProjection(
      cost: 0,
      legs: [],
      warnings: []
    )
    // Two runs; without a Blueprint share the scenario profit is 20 ISK.
    let loyaltyRow = sortableOpportunityRow(
      name: "Loyalty ship",
      value: 2,
      demand: 1,
      blueprintTypeID: 900
    )
    let references = try contractReferences(
      unitPricesByType: [:],
      complete: true
    )
    let offers: [Int64: [PublicContractSearchResult]] = [
      900: [bpcOffer(contractID: 1, blueprintTypeID: 900, runs: 5, price: 100)]
    ]
    let priced = ManufacturingOpportunityScenarioProjector.costs(
      for: loyaltyRow,
      sheet: ManufacturingOpportunityCostSheet(
        includesBlueprintAllocation: true,
        blueprintAllocationPerRun: 1_000
      ),
      logistics: logistics,
      contract: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0,
        blueprintOffers: offers,
        loyaltyStoreBlueprintTypeIDs: [900]
      )
    )
    // Only the two used runs of the five bought runs are charged, and the
    // manual allocation is replaced instead of being added.
    #expect(priced.blueprintAcquisition?.state == .contract)
    #expect(priced.blueprintAcquisition?.cost == 40)
    #expect(priced.blueprintAcquisition?.purchasePrice == 100)
    #expect(priced.blueprintAcquisition?.isProvisional == false)
    #expect(priced.blueprintAllocation == 40)
    #expect(priced.totalCost == 41)
    #expect(priced.profit == -20)

    let missing = ManufacturingOpportunityScenarioProjector.costs(
      for: loyaltyRow,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics,
      contract: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0,
        loyaltyStoreBlueprintTypeIDs: [900]
      )
    )
    #expect(missing.blueprintAcquisition?.state == .unavailable)
    #expect(missing.totalCost == nil)
    #expect(missing.profit == nil)

    let ownRights = ManufacturingOpportunityScenarioProjector.costs(
      for: loyaltyRow,
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics,
      contract: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0,
        loyaltyStoreBlueprintTypeIDs: [900],
        usesOwnBlueprintRights: true
      )
    )
    #expect(ownRights.blueprintAcquisition?.state == .ownRights)
    #expect(ownRights.profit == 20)

    // Faction products need a BPC even without Loyalty Store catalog data.
    let factionRow = sortableOpportunityRow(
      name: "Faction module",
      value: 2,
      demand: 1,
      blueprintTypeID: 901,
      metaGroupID: 4
    )
    #expect(
      ManufacturingOpportunityBlueprintAcquisitionProjector
        .requiresBlueprintCopy(row: factionRow, loyaltyStoreBlueprintTypeIDs: [])
    )
    let ordinary = ManufacturingOpportunityScenarioProjector.costs(
      for: sortableOpportunityRow(name: "Tech I", value: 2, demand: 1, metaGroupID: 1),
      sheet: ManufacturingOpportunityCostSheet(),
      logistics: logistics,
      contract: ManufacturingOpportunityContractContext(
        references: references,
        contractFeeRate: 0,
        loyaltyStoreBlueprintTypeIDs: [900]
      )
    )
    #expect(ordinary.blueprintAcquisition?.state == .notRequired)
    #expect(ordinary.profit == 20)
  }

  @Test
  func cheaperLoyaltyStoreRouteIsUsedOnlyWithEnoughLoyaltyPoints() throws {
    let logistics = ManufacturingOpportunityLogisticsProjection(
      cost: 0,
      legs: [],
      warnings: []
    )
    // Two runs; without a Blueprint share the scenario profit is 20 ISK.
    let row = sortableOpportunityRow(
      name: "Loyalty ship",
      value: 2,
      demand: 1,
      blueprintTypeID: 900
    )
    let references = try contractReferences(unitPricesByType: [:], complete: true)
    // Contract: 5 runs for 100 ISK → 40 ISK for two runs.
    let contracts: [Int64: [PublicContractSearchResult]] = [
      900: [bpcOffer(contractID: 1, blueprintTypeID: 900, runs: 5, price: 100)]
    ]
    func lpOffer(availableLP: Int64?) -> LoyaltyStoreBlueprintOffer {
      // The unresearched 5-run contract BPC sets 5 runs per purchase: one
      // purchase of 1 ISK + 2 ISK items + 5 LP × 1 ISK = 8 ISK, 2/5 charged.
      LoyaltyStoreBlueprintOffer(
        corporationID: 7,
        corporationName: "Navy",
        blueprintTypeID: 900,
        lpCost: 5,
        iskCost: 1,
        quantity: 1,
        requiredItemsValue: 2,
        iskPerLP: 1,
        bestCharacterName: availableLP == nil ? nil : "Pilot",
        availableLP: availableLP,
        availableISK: 4
      )
    }
    func costs(_ availableLP: Int64?) -> ManufacturingOpportunityCostProjection {
      ManufacturingOpportunityScenarioProjector.costs(
        for: row,
        sheet: ManufacturingOpportunityCostSheet(),
        logistics: logistics,
        contract: ManufacturingOpportunityContractContext(
          references: references,
          contractFeeRate: 0,
          blueprintOffers: contracts,
          loyaltyStoreBlueprintTypeIDs: [900],
          loyaltyStoreBlueprintOffers: [900: [lpOffer(availableLP: availableLP)]]
        )
      )
    }
    let enough = costs(5)
    #expect(enough.blueprintAcquisition?.state == .loyaltyStore)
    #expect(abs((enough.blueprintAcquisition?.cost ?? 0) - 3.2) < 1e-9)
    #expect(enough.blueprintAcquisition?.contractCost == 40)
    let route = try #require(enough.blueprintAcquisition?.loyaltyStore)
    #expect(route.totalLP == 5)
    #expect(route.purchases == 1)
    #expect(route.runsPerPurchase == 5)
    #expect(route.purchaseValue == 8)
    #expect(route.cashRequirement == 3)
    #expect(route.hasEnoughLP == true)
    #expect(route.hasEnoughISK == true)
    #expect(abs((enough.profit ?? 0) - 16.8) < 1e-9)

    // Too few or unknown LP: the contract stays the priced route.
    #expect(costs(4).blueprintAcquisition?.state == .contract)
    #expect(costs(4).blueprintAcquisition?.loyaltyStore?.hasEnoughLP == false)
    #expect(costs(nil).blueprintAcquisition?.state == .contract)
    #expect(costs(nil).blueprintAcquisition?.loyaltyStore?.hasEnoughLP == nil)
  }

  @Test
  func techIIRowsPriceTheExpectedInventionCostOrACheaperContract() throws {
    let logistics = ManufacturingOpportunityLogisticsProjection(
      cost: 0,
      legs: [],
      warnings: []
    )
    // Two runs; without a Blueprint share the scenario profit is 20 ISK.
    let row = sortableOpportunityRow(
      name: "Tech II module",
      value: 2,
      demand: 1,
      blueprintTypeID: 950,
      metaGroupID: 2
    )
    let references = try contractReferences(unitPricesByType: [:], complete: true)
    let estimate = ManufacturingOpportunityInventionEstimate(
      costPerRun: 3,
      attemptCost: 9,
      successProbability: 0.3,
      outputRuns: 10
    )
    func costs(
      estimates: [Int64: ManufacturingOpportunityInventionEstimate],
      contracts: [Int64: [PublicContractSearchResult]] = [:]
    ) -> ManufacturingOpportunityCostProjection {
      ManufacturingOpportunityScenarioProjector.costs(
        for: row,
        sheet: ManufacturingOpportunityCostSheet(),
        logistics: logistics,
        contract: ManufacturingOpportunityContractContext(
          references: references,
          contractFeeRate: 0,
          blueprintOffers: contracts,
          inventionEstimates: estimates
        )
      )
    }
    let invented = costs(estimates: [950: estimate])
    #expect(invented.blueprintAcquisition?.state == .invention)
    #expect(invented.blueprintAcquisition?.requiresInvention == true)
    #expect(invented.blueprintAcquisition?.inventionCost == 6)
    #expect(invented.blueprintAllocation == 6)
    #expect(invented.profit == 14)

    // A cheaper covering T2 BPC contract wins: 10 runs for 2 ISK → 0.4.
    let cheaperContract = costs(
      estimates: [950: estimate],
      contracts: [950: [bpcOffer(contractID: 2, blueprintTypeID: 950, runs: 10, price: 2)]]
    )
    #expect(cheaperContract.blueprintAcquisition?.state == .contract)
    #expect(cheaperContract.blueprintAcquisition?.inventionCost == 6)

    // Not estimated yet: never free.
    let pending = costs(estimates: [:])
    #expect(pending.blueprintAcquisition?.state == .unavailable)
    #expect(pending.profit == nil)

    // An unknown estimate input keeps the cost unavailable.
    let unknown = costs(
      estimates: [
        950: ManufacturingOpportunityInventionEstimate(
          costPerRun: nil,
          attemptCost: nil,
          successProbability: nil,
          outputRuns: nil
        )
      ]
    )
    #expect(unknown.blueprintAcquisition?.state == .unavailable)

    // The SDE has no invention source: an ordinary Blueprint.
    let notInvented = costs(estimates: [950: .notInvented])
    #expect(notInvented.blueprintAcquisition?.state == .notRequired)
    #expect(notInvented.profit == 20)
  }

  @Test
  func contractColumnsSortByTypedValuesWithUnavailableValuesLast() throws {
    let references = try contractReferences(
      unitPricesByType: [1: 5, 2: 9],
      complete: true
    )
    let context = ManufacturingOpportunityContractContext(
      references: references,
      contractFeeRate: 0
    )
    let rows = [
      sortableOpportunityRow(name: "Missing", value: 3, demand: 1),
      sortableOpportunityRow(name: "Expensive", value: 2, demand: 1),
      sortableOpportunityRow(name: "Cheap", value: 1, demand: 1),
    ]
    let entries = rows.map { row in
      (
        row,
        ManufacturingOpportunityScenarioProjector.costs(
          for: row,
          sheet: ManufacturingOpportunityCostSheet(),
          logistics: ManufacturingOpportunityLogisticsProjection(
            cost: 0,
            legs: [],
            warnings: []
          ),
          contract: context
        )
      )
    }
    func sorted(
      _ column: ManufacturingOpportunitySortColumn,
      _ direction: ManufacturingOpportunitySortDirection
    ) -> [String] {
      let descriptor = ManufacturingOpportunitySortDescriptor(
        column: column,
        direction: direction
      )
      return entries.sorted {
        descriptor.orderedBefore(
          lhs: $0.0,
          lhsCosts: $0.1,
          rhs: $1.0,
          rhsCosts: $1.1
        )
      }.map(\.0.productName)
    }
    #expect(sorted(.contractPrice, .ascending) == ["Cheap", "Expensive", "Missing"])
    #expect(sorted(.contractPrice, .descending) == ["Missing", "Expensive", "Cheap"])
    #expect(sorted(.contractProfit, .ascending).last == "Missing")
    #expect(entries.first?.1.contract?.unitPrice == nil)
  }

  @Test
  func hubTopListRanksTheHubProjectionAndSkipsRowsWithoutPotential() throws {
    let rows = (1...8).map { index in
      sortableOpportunityRow(
        name: "Product \(index)",
        value: Int64(index * 10),
        demand: index == 3 ? nil : Int64(index)
      )
    }
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let snapshot = ManufacturingOpportunitySnapshot(
      settings: ManufacturingOpportunitySettings(),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      logisticsConfiguration: LogisticsConfiguration(
        isEnabled: true,
        includeInboundMaterials: true,
        includeOutboundProducts: false,
        productionLocationName: ProcurementLocation.jita.name,
        homeTradeHub: .jita,
        iskPerCubicMeter: 100
      ),
      rows: rows,
      coverage: ManufacturingOpportunityCoverage(
        completeManufacturingDefinitionCount: rows.count,
        mainHubActiveOrderTypeCount: rows.count,
        candidateCount: rows.count,
        candidatesWithSellOrders: rows.count,
        candidatesWithBuyOrders: 0
      ),
      sdeSource: source,
      marketSource: source,
      warnings: []
    )
    // The hub view's own projection; the Dashboard only ranks it.
    let candidates = snapshot.rows.map { row in
      (
        row,
        ManufacturingOpportunityScenarioProjector.costs(
          for: row,
          sheet: ManufacturingOpportunityCostSheet(),
          logistics: ManufacturingOpportunityLogisticsProjection(
            cost: 0,
            legs: [],
            warnings: []
          ),
          contract: ManufacturingOpportunityContractContext(
            references: nil,
            contractFeeRate: nil
          )
        )
      )
    }
    let result = HubTopOpportunityResult.rank(
      role: .main,
      snapshotID: snapshot.id,
      candidates: candidates
    )
    let top = result.entries
    #expect(top.count == HubTopOpportunityResult.limit)
    #expect(!top.contains { $0.productName == "Product 3" })
    let potentials = top.map(\.dailyProfitPotential)
    #expect(potentials == potentials.sorted(by: >))
    for entry in top {
      let candidate = try #require(
        candidates.first { $0.0.productTypeID == entry.productTypeID }
      )
      #expect(
        ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
          for: candidate.0,
          costs: candidate.1
        ) == entry.dailyProfitPotential
      )
    }
    // Equal potentials keep a stable type-ID order.
    for (lhs, rhs) in zip(top, top.dropFirst())
    where lhs.dailyProfitPotential == rhs.dailyProfitPotential {
      #expect(lhs.productTypeID < rhs.productTypeID)
    }
    // The calculation time alone is no change.
    #expect(
      result
        == HubTopOpportunityResult(
          role: .main,
          snapshotID: snapshot.id,
          calculatedAt: .distantPast,
          entries: top
        )
    )
  }

  private func sortableOpportunityRow(
    name: String,
    value: Int64,
    demand: Int64?,
    materialQuantity: Int64 = 1,
    materialUnitPrice: Double = 1,
    materialVolume: Double = 1,
    blueprintTypeID: Int64? = nil,
    categoryName: String? = nil,
    groupName: String? = nil,
    metaGroupID: Int64? = nil,
    techLevel: Int? = nil
  ) -> ManufacturingOpportunityRow {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    let materialTotal = Double(materialQuantity) * materialUnitPrice
    return ManufacturingOpportunityRow(
      blueprintTypeID: blueprintTypeID ?? value,
      productTypeID: value,
      productName: name,
      categoryName: categoryName ?? name,
      groupName: groupName ?? name,
      metaGroupID: metaGroupID,
      techLevel: techLevel,
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

  private func opportunitySnapshot(
    rows: [ManufacturingOpportunityRow]
  ) -> ManufacturingOpportunitySnapshot {
    let source = SourceIdentity(provider: "Fixture", version: "1")
    return ManufacturingOpportunitySnapshot(
      settings: ManufacturingOpportunitySettings(),
      mainHub: .jita,
      productionWarehouseScope: ProductionWarehouseScope(locations: []),
      rows: rows,
      coverage: ManufacturingOpportunityCoverage(
        completeManufacturingDefinitionCount: rows.count,
        mainHubActiveOrderTypeCount: rows.count,
        candidateCount: rows.count,
        candidatesWithSellOrders: rows.count,
        candidatesWithBuyOrders: rows.count
      ),
      sdeSource: source,
      marketSource: source,
      warnings: []
    )
  }
}

private struct LegacyOrderBaselineFixture: Codable {
  let typeID: Int64
  let locationID: Int64
  let side: MarketOrderSide
  let volumeRemaining: Int64
}

private struct LegacyDemandLedgerFixture: Codable {
  let version: Int
  let demand: ManufacturingOpportunityDemandSnapshot?
  let previousOrdersByID: [Int64: LegacyOrderBaselineFixture]
  let previousSourceSnapshotID: UUID?
}

/// Regional order pages whose earlier pages answer more slowly.
private struct PagedRegionalOrdersTransport: ESIHTTPTransporting {
  let pageCount: Int

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let page =
      Int(
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
          .queryItems?.first(where: { $0.name == "page" })?.value ?? "1"
      ) ?? 1
    try await Task.sleep(for: .milliseconds((pageCount - page) * 4))
    func order(id: Int, locationID: Int64) -> String {
      """
      {"duration":30,"is_buy_order":false,"issued":"2026-07-30T10:00:00Z",\
      "location_id":\(locationID),"min_volume":1,"order_id":\(id),\
      "price":5.5,"range":"station","system_id":30000002,"type_id":34,\
      "volume_remain":25,"volume_total":100}
      """
    }
    let body =
      "[" + order(id: page, locationID: 60_000_001) + ","
      + order(id: 100 + page, locationID: 60_000_002) + "]"
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["X-Pages": String(pageCount)]
    )!
    return (Data(body.utf8), response)
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
