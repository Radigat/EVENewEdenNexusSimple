import Foundation
import SwiftData
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

@MainActor
@Suite("Planner persistence limits")
struct PlannerPersistencePerformanceTests {
  @Test
  func recoveryConfirmationUsesSelectedLanguageAndDescribesReplacement() {
    let source = URL(fileURLWithPath: "/fixture/earlier.store")
    let backup = URL(fileURLWithPath: "/fixture/backup")
    let counts = ["Characters": 2, "Production overview rows": 7]
    let replacementKey = "All application records will be replaced by the earlier data. Newer records remain only in the backup. No records will be merged. Keep this backup. Keychain, app preferences, SDE, and additional databases are retained."
    let prerequisiteKey = "Before restoring, quit every older version of this app. Older versions do not prevent simultaneous access to this data folder."
    let rawCopyKey = "The current data is backed up only as an unchanged raw copy because a readable SQLite backup could not be created. Keep that raw backup for recovery."
    for language in [AppLanguage.english, .german] {
      for readableBackup in [true, false] {
        let text = FullStoreRecovery.confirmationText(
          source: source, backupDirectory: backup, modelCounts: counts,
          currentSnapshotAvailable: readableBackup, language: language
        )
        #expect(text.contains(source.path))
        #expect(text.contains(backup.path))
        #expect(text.contains("\(language.localized("Characters")): 2"))
        #expect(text.contains("\(language.localized("Production overview rows")): 7"))
        #expect(text.contains(language.localized(replacementKey)))
        #expect(text.contains(language.localized(prerequisiteKey)))
        #expect(text.contains(language.localized(rawCopyKey)) == !readableBackup)
      }
    }
    #expect(AppLanguage.german.localized(replacementKey) != replacementKey)
    #expect(AppLanguage.german.localized(prerequisiteKey) != prerequisiteKey)
    #expect(AppLanguage.german.localized("Characters") == "Charaktere")
    #expect(AppLanguage.english.localized("Characters") == "Characters")
  }

  @Test
  func latestLegacyFallbackAndRequestedHistoryAreFetchedDirectly() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let older = makeLegacyRecord(
      input: "older",
      completedAt: Date(timeIntervalSince1970: 10)
    )
    let latest = makeLegacyRecord(
      input: "latest",
      completedAt: Date(timeIntervalSince1970: 20)
    )
    let requested = makeOverviewRow(sequenceNumber: 9)
    context.insert(older)
    context.insert(latest)
    context.insert(requested)
    try context.save()

    let fetchedLatest = try #require(
      try PlannerPersistenceController.fetchLatestProductionRecord(in: context)
    )
    let fetchedRequested = try #require(
      try PlannerPersistenceController.fetchProductionOverviewRow(
        id: requested.id,
        in: context
      )
    )

    #expect(fetchedLatest.id == latest.id)
    #expect(fetchedRequested.id == requested.id)
  }

  @Test
  func recentAndPagedQueriesKeepTheirConfiguredBounds() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    for sequenceNumber in 1...205 {
      context.insert(makeOverviewRow(sequenceNumber: sequenceNumber))
    }
    try context.save()

    let recent = try context.fetch(
      PlannerPersistenceController.recentProductionOverviewDescriptor()
    )
    let secondPage = try ProductionOverviewHistoryPager.load(
      requestedPageIndex: 1,
      pageSize: 100,
      in: context
    )

    #expect(recent.count == 5)
    #expect(recent.map(\.sequenceNumber) == [205, 204, 203, 202, 201])
    #expect(secondPage.totalRowCount == 205)
    #expect(secondPage.rows.count == 100)
    #expect(secondPage.rows.first?.sequenceNumber == 101)
    #expect(secondPage.rows.last?.sequenceNumber == 200)
  }

  @Test
  func activeSnapshotKeepsReservationsAndBeatsLegacyFallback() throws {
    let allocation = StockAllocation(
      typeID: 34,
      quantity: 42,
      source: StockSource(kind: .warehouse, reference: "fixture")
    )
    let plan = makePlan(stockAllocations: [allocation])
    let encoded = try JSONEncoder().encode(plan)
    let active = StoredPlan(
      id: plan.id,
      name: "Active fixture",
      input: "active input",
      snapshot: encoded,
      sdeBuild: plan.provenance.sdeBuild,
      esiCompatibilityDate: plan.provenance.esiCompatibilityDate,
      priceTimestamp: plan.provenance.priceTimestamp,
      ruleVersion: plan.provenance.ruleVersion,
      isActive: true
    )

    let restored = PlannerPersistenceController.restore(
      draft: nil,
      activePlans: [active],
      latestProductionRecord: makeLegacyRecord(
        input: "legacy input",
        completedAt: .now
      )
    )

    #expect(restored.input == "active input")
    #expect(restored.plan?.id == plan.id)
    #expect(restored.plan?.stockAllocations == [allocation])
  }

  @Test
  func recordingFindsNextSequenceWithoutLoadingHistoryArray() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    context.insert(makeOverviewRow(sequenceNumber: 7))
    context.insert(makeOverviewRow(sequenceNumber: 42))
    try context.save()
    let plan = makePlan()

    let recorded = try PlannerPersistenceController.recordProductionOverview(
      plan,
      productionBasis: ProductionBasis(),
      completedAt: Date(timeIntervalSince1970: 500),
      in: context
    )

    #expect(recorded.map(\.sequenceNumber) == [43])
    #expect(PlannerPersistenceController.decodePlan(recorded[0])?.id == plan.id)
  }

  @Test
  func recordingUsesAllocatedRecursiveBlueprintCost() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let plan = makePlan(
      blueprintCostISK: nil,
      automaticBlueprintCost: 25
    )

    let recorded = try PlannerPersistenceController.recordProductionOverview(
      plan,
      productionBasis: ProductionBasis(),
      in: context
    )

    #expect(recorded.count == 1)
    #expect(recorded[0].blueprintCost == 25)
  }

  @Test(arguments: [false, true])
  func recordingStockFirstPlanPreservesPlannerAndRequestCosts(
    multipleRequests: Bool
  ) async throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let existing = makeOverviewRow(sequenceNumber: 1)
    let existingSnapshot = existing.sourceSnapshot
    context.insert(existing)
    try context.save()

    let plan = try await makeStockFirstPlan(multipleRequests: multipleRequests)
    // Two requests share one aggregated 3-run intermediate job (39.5 ISK);
    // the branch values 25.5 and 16 weight the request shares.
    let first = 39.5 * 25.5 / 41.5
    let expectedCosts = multipleRequests ? [first, 39.5 - first] : [23.0]
    #expect(plan.materialCost == expectedCosts.reduce(0, +))
    let recorded = try PlannerPersistenceController.recordProductionOverview(
      plan, productionBasis: ProductionBasis(), in: context
    )
    #expect(recorded.count == expectedCosts.count)
    for (row, expectedCost) in zip(recorded, expectedCosts) {
      #expect(row.materialCost == expectedCost)
      let restored = try #require(PlannerPersistenceController.decodePlan(row))
      #expect(restored.materialCost == plan.materialCost)
      #expect(restored.costBreakdown?.materialCost == plan.materialCost)
      #expect(restored.costBreakdown?.purchasedMaterialCost
        == plan.costBreakdown?.purchasedMaterialCost)
      #expect(restored.costBreakdown?.stockMaterialCost
        == plan.costBreakdown?.stockMaterialCost)
      #expect(
        ProductionOverviewProjector.projection(for: row.requestID, in: restored)?
          .materialCost == row.materialCost
      )
    }
    #expect(recorded.compactMap(\.materialCost).reduce(0, +) == plan.materialCost)
    let untouched = try #require(
      try PlannerPersistenceController.fetchProductionOverviewRow(
        id: existing.id, in: ModelContext(container)
      )
    )
    #expect(untouched.materialCost == 100)
    #expect(untouched.sourceSnapshot == existingSnapshot)
  }

  @Test
  func pagedHistorySummaryKeepsCompleteTotalsAndUnavailableSemantics()
    async throws
  {
    let container = try makeContainer()
    let context = ModelContext(container)
    let plan = makePlan()
    let data = try JSONEncoder().encode(plan)
    let first = makeOverviewRow(
      sequenceNumber: 1,
      plan: plan,
      sourceSnapshot: data
    )
    let second = makeOverviewRow(
      sequenceNumber: 2,
      plan: plan,
      sourceSnapshot: data
    )
    context.insert(first)
    context.insert(second)
    try context.save()

    let reader = ProductionOverviewSummaryReader(modelContainer: container)
    let summary = try await reader.load()

    #expect(summary.rowCount == 2)
    #expect(summary.units == 20)
    #expect(summary.projectedProfit == 106)
    #expect(summary.realProfit == -122)
  }

  @Test
  func rowsFromOneImmutablePlanShareOneDecodedSnapshot() throws {
    let plan = makePlan()
    let data = try JSONEncoder().encode(plan)
    let first = makeOverviewRow(
      sequenceNumber: 1,
      plan: plan,
      sourceSnapshot: data
    )
    let second = makeOverviewRow(
      sequenceNumber: 2,
      plan: plan,
      sourceSnapshot: data
    )
    let cache = ProductionOverviewProjectionCache()

    _ = cache.projection(for: first)
    _ = cache.projection(for: second)

    #expect(cache.decodedSnapshotCount == 1)
  }

  @Test
  func productionBookIconUsesTheTopLevelProducedItem() throws {
    let plan = makePlan(includeEarlierMaterialNode: true)
    let row = makeOverviewRow(sequenceNumber: 1, plan: plan)
    let cache = ProductionOverviewProjectionCache()
    let requestID = try #require(plan.requests.first?.id)
    let draft = try #require(
      PlannerPersistenceController.productionOverviewDrafts(
        for: plan,
        productionBasis: ProductionBasis()
      ).first
    )

    #expect(plan.nodes.first?.typeID == 34)
    #expect(plan.topLevelProductNode(for: requestID)?.typeID == 100)
    #expect(cache.productTypeID(for: row) == 100)
    #expect(draft.productTypeID == 100)
  }

  private func makeStockFirstPlan(multipleRequests: Bool) async throws
    -> IndustryPlanSnapshot
  {
    let source = SourceIdentity(provider: "fixture", version: "stock-first")
    func blueprint(productTypeID: Int64, inputTypeID: Int64, quantity: Int64)
      -> BlueprintDefinition
    {
      BlueprintDefinition(
        blueprintTypeID: productTypeID + 700,
        productTypeID: productTypeID,
        maxProductionLimit: nil,
        activity: BlueprintActivityDefinition(
          kind: .manufacturing,
          durationSeconds: 10,
          materials: [BlueprintMaterial(typeID: inputTypeID, quantity: quantity)],
          products: [BlueprintProduct(typeID: productTypeID, quantity: 1, probability: nil)]
        ),
        source: source
      )
    }
    func order(id: Int64, typeID: Int64, price: Double, quantity: Int64) -> MarketOrder {
      MarketOrder(
        id: id, typeID: typeID,
        locationID: EVEConstants.jitaIV4StationID,
        systemID: EVEConstants.jitaSystemID,
        side: .sell, price: price, volumeRemaining: quantity,
        minimumVolume: 1, issued: Date(timeIntervalSince1970: 100)
      )
    }
    let catalog = StockFirstHistoryCatalog(definitions: [
      81: blueprint(productTypeID: 81, inputTypeID: 82, quantity: 2),
      82: blueprint(productTypeID: 82, inputTypeID: 83, quantity: 4),
    ])
    let planningContext = IndustryPlanningContext(
      manufacturingProfile: ManufacturingProfile(),
      catalog: catalog,
      market: MarketOrderSnapshot(
        id: UUID(), regionID: EVEConstants.theForgeRegionID,
        locationID: EVEConstants.jitaIV4StationID,
        capturedAt: Date(timeIntervalSince1970: 100), state: .fresh,
        ordersByType: [
          81: [order(id: 8101, typeID: 81, price: 100, quantity: 100)],
          82: [
            order(id: 8201, typeID: 82, price: 10, quantity: 1),
            order(id: 8202, typeID: 82, price: 20, quantity: 100),
          ],
          83: [order(id: 8301, typeID: 83, price: 2, quantity: 100)],
        ], source: source
      ),
      adjustedPrices: [
        82: AdjustedPrice(typeID: 82, adjustedPrice: 5, averagePrice: 5),
        83: AdjustedPrice(typeID: 83, adjustedPrice: 1, averagePrice: 1),
      ],
      systemIndices: [IndustrySystemIndex(
        solarSystemID: EVEConstants.jitaSystemID, activity: .manufacturing, costIndex: 0
      )],
      availableStock: [82: 1],
      procurementPreferences: [82: MaterialProcurementPreference(
        supplyMode: .produce, purchaseLocation: .jita, usesAvailableStockFirst: true
      )],
      sdeBuild: 1
    )
    let input = multipleRequests
      ? "Choice Product 1 0 0\nChoice Product 1 0 0" : "Choice Product 1 0 0"
    return try await IndustryPlanner().plan(input: input, context: planningContext)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: EVENexusSchemaV2.self)
    let configuration = ModelConfiguration(
      "PlannerPersistencePerformanceTests",
      schema: schema,
      isStoredInMemoryOnly: true
    )
    return try ModelContainer(
      for: schema,
      configurations: [configuration]
    )
  }

  private func makeLegacyRecord(
    input: String,
    completedAt: Date
  ) -> StoredProductionRecord {
    let plan = makePlan()
    return StoredProductionRecord(
      planID: plan.id,
      name: input,
      input: input,
      manualStockInput: "",
      snapshot: (try? JSONEncoder().encode(plan)) ?? Data(),
      completedAt: completedAt,
      sdeBuild: plan.provenance.sdeBuild,
      esiCompatibilityDate: plan.provenance.esiCompatibilityDate,
      priceTimestamp: plan.provenance.priceTimestamp,
      ruleVersion: plan.provenance.ruleVersion
    )
  }

  private func makeOverviewRow(
    sequenceNumber: Int,
    plan: IndustryPlanSnapshot? = nil,
    sourceSnapshot: Data? = nil
  ) -> StoredProductionOverviewRow {
    let acceptedPlan = plan ?? makePlan()
    let request = acceptedPlan.requests[0]
    return StoredProductionOverviewRow(
      sequenceNumber: sequenceNumber,
      recordedAt: Date(timeIntervalSince1970: Double(sequenceNumber)),
      planID: acceptedPlan.id,
      requestID: request.id,
      productName: request.productName,
      runs: 1,
      materialEfficiency: request.materialEfficiency,
      timeEfficiency: request.timeEfficiency,
      systemName: "Fixture System",
      units: 10,
      materialCost: 100,
      indexCost: 20,
      blueprintCost: 10,
      marketTax: 10,
      salePricePerUnit: 20,
      soldUnits: 4,
      sourceSnapshot:
        sourceSnapshot ?? ((try? JSONEncoder().encode(acceptedPlan)) ?? Data()),
      sdeBuild: acceptedPlan.provenance.sdeBuild,
      esiCompatibilityDate: acceptedPlan.provenance.esiCompatibilityDate,
      priceTimestamp: acceptedPlan.provenance.priceTimestamp,
      ruleVersion: acceptedPlan.provenance.ruleVersion
    )
  }

  private func makePlan(
    stockAllocations: [StockAllocation] = [],
    includeEarlierMaterialNode: Bool = false,
    blueprintCostISK: Double? = 10,
    automaticBlueprintCost: Double? = nil
  ) -> IndustryPlanSnapshot {
    let requestID = UUID()
    let request = ProductionRequestLine(
      id: requestID,
      lineNumber: 1,
      productName: "Fixture Ship",
      wantedQuantity: 10,
      materialEfficiency: 4,
      timeEfficiency: 2,
      blueprintKind: blueprintCostISK == nil ? nil : .bpc,
      blueprintCostISK: blueprintCostISK
    )
    var nodes: [PlanNode] = []
    if includeEarlierMaterialNode {
      nodes.append(
        PlanNode(
          id: UUID(),
          typeID: 34,
          name: "Fixture Material",
          requiredQuantity: 20,
          action: .buy,
          activity: nil,
          runs: nil,
          materialEfficiency: nil,
          timeEfficiency: nil,
          children: [],
          topLevelRequestID: requestID
        )
      )
    }
    nodes.append(
      PlanNode(
        id: UUID(),
        typeID: 100,
        name: "Fixture Ship",
        requiredQuantity: 10,
        action: .produce,
        activity: .manufacturing,
        runs: 1,
        materialEfficiency: 4,
        timeEfficiency: 2,
        children: [],
        topLevelRequestID: requestID
      )
    )
    return IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: [request],
      nodes: nodes,
      materials: [],
      stockAllocations: stockAllocations,
      jobs: [],
      materialCost: 100,
      installationCost: 20,
      costBreakdown: IndustryCostBreakdown(
        materialCost: 100,
        purchasedMaterialCost: 100,
        stockMaterialCost: 0,
        blueprintCosts: automaticBlueprintCost.map {
          BlueprintCostBreakdown(
            entries: [],
            requestsWithoutEnteredCost: [],
            total: $0
          )
        },
        systemIndexCost: 20,
        facilityTax: 0,
        sccSurcharge: 0,
        alphaSurcharge: 0,
        installationCost: 20,
        logistics: nil,
        logisticsCost: 5,
        totalProductionCost: nil
      ),
      immediateSale: SaleScenarioResult(
        scenario: .immediateSale,
        grossRevenue: 200,
        salesTax: 10,
        brokerFee: 0,
        grossOrNetRevenue: 190,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: []
      ),
      listedSale: SaleScenarioResult(
        scenario: .listedSale,
        grossRevenue: 200,
        salesTax: 10,
        brokerFee: 2,
        grossOrNetRevenue: 188,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: []
      ),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: nil,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )
  }
}

private struct StockFirstHistoryCatalog: IndustryCatalogQuerying {
  let definitions: [Int64: BlueprintDefinition]
  private let names: [Int64: String] = [
    81: "Choice Product", 82: "Choice Intermediate", 83: "Choice Raw"
  ]

  func typeID(named name: String) async throws -> Int64? {
    names.first { $0.value == name }?.key
  }

  func typeName(id: Int64) async throws -> String? {
    names[id]
  }

  func productionDefinition(productTypeID: Int64) async throws -> BlueprintDefinition? {
    definitions[productTypeID]
  }
}
