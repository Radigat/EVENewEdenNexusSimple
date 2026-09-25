import EVENexusCore
import Foundation
import SwiftData

struct RestoredPlannerState {
  let input: String
  let manualStockInput: String
  let plan: IndustryPlanSnapshot?
}

struct ProductionOverviewDraftRow: Identifiable {
  var id: UUID { requestID }
  let requestID: UUID
  let productTypeID: Int64?
  let productName: String
  let runs: Int64
  let materialEfficiency: Int
  let timeEfficiency: Int
  let systemName: String
  let units: Int64
  let materialCost: Double?
  let installationCost: Double?
  let logisticsCost: Double?
  let blueprintCost: Double?
  let salesTaxRate: Double?
  let brokerFeeRate: Double?
  let brokerFeeIsApplicable: Bool
  let salePricePerUnit: Double?

  var calculation: ProductionOverviewCalculation {
    ProductionOverviewCalculation(
      units: units,
      materialCost: materialCost,
      installationCost: installationCost,
      blueprintCost: blueprintCost,
      logisticsCost: logisticsCost,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate,
      brokerFeeIsApplicable: brokerFeeIsApplicable,
      salePricePerUnit: salePricePerUnit,
      soldUnits: 0
    )
  }
}

enum PlannerPersistenceError: LocalizedError {
  case invalidPlanSnapshot

  var errorDescription: String? {
    switch self {
    case .invalidPlanSnapshot:
      "The production plan could not be encoded for local storage."
    }
  }
}

@MainActor
enum PlannerPersistenceController {
  static let draftKey = "primary"
  static let recentProductionLimit = 5

  static func recentProductionOverviewDescriptor()
    -> FetchDescriptor<StoredProductionOverviewRow>
  {
    var descriptor = FetchDescriptor<StoredProductionOverviewRow>(
      sortBy: [
        SortDescriptor(\.recordedAt, order: .reverse),
        SortDescriptor(\.id),
      ]
    )
    descriptor.fetchLimit = recentProductionLimit
    return descriptor
  }

  static func restore(
    draft: StoredPlannerDraft?,
    activePlans: [StoredPlan],
    latestProductionRecord: StoredProductionRecord?
  ) -> RestoredPlannerState {
    let active = activePlans.max { $0.priceTimestamp < $1.priceTimestamp }
    let restoredPlan =
      active.flatMap(decodePlan)
      ?? latestProductionRecord.flatMap(decodePlan)
    let restoredInput =
      draft?.input
      ?? active?.input
      ?? latestProductionRecord?.input
      ?? ""
    return RestoredPlannerState(
      input: restoredInput,
      manualStockInput:
        draft?.manualStockInput
        ?? latestProductionRecord?.manualStockInput
        ?? "",
      plan: restoredPlan
    )
  }

  static func fetchLatestProductionRecord(
    in modelContext: ModelContext
  ) throws -> StoredProductionRecord? {
    var descriptor = FetchDescriptor<StoredProductionRecord>(
      sortBy: [
        SortDescriptor(\.completedAt, order: .reverse),
        SortDescriptor(\.id),
      ]
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  static func fetchProductionOverviewRow(
    id: UUID,
    in modelContext: ModelContext
  ) throws -> StoredProductionOverviewRow? {
    var descriptor = FetchDescriptor<StoredProductionOverviewRow>(
      predicate: #Predicate { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  static func saveDraft(
    input: String,
    manualStockInput: String,
    existingDraft: StoredPlannerDraft?,
    in modelContext: ModelContext
  ) throws {
    if let existingDraft {
      existingDraft.input = input
      existingDraft.manualStockInput = manualStockInput
      existingDraft.updatedAt = .now
    } else {
      modelContext.insert(
        StoredPlannerDraft(
          input: input,
          manualStockInput: manualStockInput
        )
      )
    }
    try modelContext.save()
  }

  static func saveActivePlan(
    _ plan: IndustryPlanSnapshot,
    encodedSnapshot data: Data,
    input: String,
    activePlans: [StoredPlan],
    in modelContext: ModelContext
  ) throws {
    for activePlan in activePlans where activePlan.id != plan.id {
      activePlan.isActive = false
    }
    if let existing = activePlans.first(where: { $0.id == plan.id }) {
      existing.name = productionName(for: plan)
      existing.input = input
      existing.snapshot = data
      existing.sdeBuild = plan.provenance.sdeBuild
      existing.esiCompatibilityDate = plan.provenance.esiCompatibilityDate
      existing.priceTimestamp = plan.provenance.priceTimestamp
      existing.ruleVersion = plan.provenance.ruleVersion
      existing.isActive = true
    } else {
      modelContext.insert(
        StoredPlan(
          id: plan.id,
          name: productionName(for: plan),
          input: input,
          snapshot: data,
          sdeBuild: plan.provenance.sdeBuild,
          esiCompatibilityDate: plan.provenance.esiCompatibilityDate,
          priceTimestamp: plan.provenance.priceTimestamp,
          ruleVersion: plan.provenance.ruleVersion,
          isActive: true
        )
      )
    }
    try modelContext.save()
  }

  nonisolated static func encodePlanSnapshot(
    _ plan: IndustryPlanSnapshot
  ) throws -> Data {
    do {
      return try JSONEncoder().encode(plan)
    } catch {
      throw PlannerPersistenceError.invalidPlanSnapshot
    }
  }

  @discardableResult
  static func recordProductionOverview(
    _ plan: IndustryPlanSnapshot,
    productionBasis: ProductionBasis,
    completedAt: Date = .now,
    in modelContext: ModelContext
  ) throws -> [StoredProductionOverviewRow] {
    guard let data = try? JSONEncoder().encode(plan) else {
      throw PlannerPersistenceError.invalidPlanSnapshot
    }
    var latestSequenceDescriptor =
      FetchDescriptor<StoredProductionOverviewRow>(
        sortBy: [
          SortDescriptor(\.sequenceNumber, order: .reverse),
          SortDescriptor(\.id),
        ]
      )
    latestSequenceDescriptor.fetchLimit = 1
    let nextNumber =
      (try modelContext.fetch(latestSequenceDescriptor).first?
        .sequenceNumber ?? 0) + 1

    let drafts = productionOverviewDrafts(
      for: plan,
      productionBasis: productionBasis
    )
    let rows = drafts.enumerated().map { index, draft in
      let row = StoredProductionOverviewRow(
        sequenceNumber: nextNumber + index,
        recordedAt: completedAt,
        planID: plan.id,
        requestID: draft.requestID,
        productName: draft.productName,
        runs: draft.runs,
        materialEfficiency: draft.materialEfficiency,
        timeEfficiency: draft.timeEfficiency,
        systemName: draft.systemName,
        units: draft.units,
        materialCost: draft.materialCost,
        indexCost: draft.installationCost,
        blueprintCost: draft.blueprintCost,
        marketTax: draft.calculation.salesTax,
        salePricePerUnit: draft.salePricePerUnit,
        sourceSnapshot: data,
        sdeBuild: plan.provenance.sdeBuild,
        esiCompatibilityDate: plan.provenance.esiCompatibilityDate,
        priceTimestamp: plan.provenance.priceTimestamp,
        ruleVersion: plan.provenance.ruleVersion
      )
      modelContext.insert(row)
      return row
    }
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
    return rows
  }

  static func productionOverviewDrafts(
    for plan: IndustryPlanSnapshot,
    productionBasis: ProductionBasis
  ) -> [ProductionOverviewDraftRow] {
    plan.requests.map { request in
      let node = plan.topLevelProductNode(for: request.id)
      let projection = ProductionOverviewProjector.projection(
        for: request.id,
        in: plan
      )
      return ProductionOverviewDraftRow(
        requestID: request.id,
        productTypeID: node?.typeID,
        productName: request.productName,
        runs: Int64(node?.runs ?? 0),
        materialEfficiency: request.materialEfficiency,
        timeEfficiency: request.timeEfficiency,
        systemName: systemName(
          for: node,
          productionBasis: productionBasis
        ),
        units: node?.requiredQuantity ?? Int64(request.wantedQuantity),
        materialCost: projection?.materialCost,
        installationCost: projection?.installationCost,
        logisticsCost: projection?.logisticsCost,
        blueprintCost:
          projection?.blueprintCost ?? request.blueprintCostISK,
        salesTaxRate: projection?.salesTaxRate,
        brokerFeeRate: projection?.brokerFeeRate,
        brokerFeeIsApplicable: projection?.brokerFeeIsApplicable ?? true,
        salePricePerUnit: projection?.suggestedSalePricePerUnit
      )
    }
  }

  static func decodePlan(_ plan: StoredPlan) -> IndustryPlanSnapshot? {
    try? JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: plan.snapshot
    )
  }

  static func decodePlan(
    _ record: StoredProductionRecord
  ) -> IndustryPlanSnapshot? {
    try? JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: record.snapshot
    )
  }

  static func decodePlan(
    _ row: StoredProductionOverviewRow
  ) -> IndustryPlanSnapshot? {
    try? JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: row.sourceSnapshot
    )
  }

  private static func productionName(
    for plan: IndustryPlanSnapshot
  ) -> String {
    plan.requests.map(\.productName).joined(separator: ", ")
  }

  private static func systemName(
    for node: PlanNode?,
    productionBasis: ProductionBasis
  ) -> String {
    if node?.activity == .reaction {
      return productionBasis.reactionSelection?.solarSystemName
        ?? productionBasis.reactionSystem.solarSystemName
    }
    if let category = node?.manufacturingCategory,
      let name = productionBasis.selection(for: category)?.solarSystemName
    {
      return name
    }
    return "Nicht aufgelöst"
  }
}
