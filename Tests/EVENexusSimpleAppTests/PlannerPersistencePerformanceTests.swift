import Foundation
import SwiftData
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

@MainActor
@Suite("Planner persistence limits")
struct PlannerPersistencePerformanceTests {
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
