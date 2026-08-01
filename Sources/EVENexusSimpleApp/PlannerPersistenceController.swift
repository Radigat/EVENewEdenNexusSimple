import EVENexusCore
import Foundation
import SwiftData

struct RestoredPlannerState {
  let input: String
  let manualStockInput: String
  let plan: IndustryPlanSnapshot?
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

  static func restore(
    draft: StoredPlannerDraft?,
    activePlans: [StoredPlan],
    productionRecords: [StoredProductionRecord]
  ) -> RestoredPlannerState {
    let active = activePlans.max { $0.priceTimestamp < $1.priceTimestamp }
    let recentProduction = productionRecords.max {
      $0.completedAt < $1.completedAt
    }
    let restoredPlan =
      active.flatMap(decodePlan)
      ?? recentProduction.flatMap(decodePlan)
    let restoredInput =
      draft?.input
      ?? active?.input
      ?? recentProduction?.input
      ?? ""
    return RestoredPlannerState(
      input: restoredInput,
      manualStockInput:
        draft?.manualStockInput
        ?? recentProduction?.manualStockInput
        ?? "",
      plan: restoredPlan
    )
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
    input: String,
    activePlans: [StoredPlan],
    in modelContext: ModelContext
  ) throws {
    guard let data = try? JSONEncoder().encode(plan) else {
      throw PlannerPersistenceError.invalidPlanSnapshot
    }
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

  @discardableResult
  static func recordProductionOverview(
    _ plan: IndustryPlanSnapshot,
    productionBasis: ProductionBasis,
    existingRows: [StoredProductionOverviewRow],
    completedAt: Date = .now,
    in modelContext: ModelContext
  ) throws -> [StoredProductionOverviewRow] {
    guard let data = try? JSONEncoder().encode(plan) else {
      throw PlannerPersistenceError.invalidPlanSnapshot
    }
    let materialCosts = plan.requests.map {
      requestMaterialCost(for: $0.id, in: plan)
    }
    let knownMaterialTotal = materialCosts.compactMap { $0 }.reduce(0, +)
    let nextNumber =
      (existingRows.map(\.sequenceNumber).max() ?? 0) + 1
    let feeRate: Double?
    if let salesTaxRate =
      productionBasis.marketTaxes.effectiveSalesTaxRate,
      let brokerFeeRate =
        productionBasis.marketTaxes.effectiveBrokerFeeRate
    {
      feeRate = salesTaxRate + brokerFeeRate
    } else {
      feeRate = nil
    }

    let rows = plan.requests.enumerated().map { index, request in
      let node = plan.nodes.last {
        $0.topLevelRequestID == request.id && $0.action == .produce
      }
      let quote =
        plan.listedSale.quotes.indices.contains(index)
        ? plan.listedSale.quotes[index] : nil
      let grossUnitPrice: Double? =
        quote?.weightedUnitPrice.flatMap { netUnitPrice in
          guard let feeRate, feeRate < 1 else { return nil }
          return netUnitPrice / (1 - feeRate)
        }
      let grossTotal = grossUnitPrice.map {
        $0 * Double(node?.requiredQuantity ?? Int64(request.wantedQuantity))
      }
      let marketTax = grossTotal.flatMap { gross in
        quote?.total.map { gross - $0 }
      }
      let indexCost = allocatedIndexCost(
        plan: plan,
        requestMaterialCost: materialCosts[index],
        knownMaterialTotal: knownMaterialTotal,
        requestCount: plan.requests.count
      )
      let row = StoredProductionOverviewRow(
        sequenceNumber: nextNumber + index,
        recordedAt: completedAt,
        planID: plan.id,
        requestID: request.id,
        productName: request.productName,
        runs: Int64(node?.runs ?? 0),
        materialEfficiency: request.materialEfficiency,
        timeEfficiency: request.timeEfficiency,
        systemName: systemName(
          for: node,
          productionBasis: productionBasis
        ),
        units: node?.requiredQuantity ?? Int64(request.wantedQuantity),
        materialCost: materialCosts[index],
        indexCost: indexCost,
        blueprintCost: request.blueprintCostISK,
        marketTax: marketTax,
        salePricePerUnit: grossUnitPrice,
        sourceSnapshot: data,
        sdeBuild: plan.provenance.sdeBuild,
        esiCompatibilityDate: plan.provenance.esiCompatibilityDate,
        priceTimestamp: plan.provenance.priceTimestamp,
        ruleVersion: plan.provenance.ruleVersion
      )
      modelContext.insert(row)
      return row
    }
    try modelContext.save()
    return rows
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

  private static func productionName(
    for plan: IndustryPlanSnapshot
  ) -> String {
    plan.requests.map(\.productName).joined(separator: ", ")
  }

  private static func requestMaterialCost(
    for requestID: UUID,
    in plan: IndustryPlanSnapshot
  ) -> Double? {
    let materialInputs = plan.nodes.filter {
      $0.topLevelRequestID == requestID
        && ($0.action == .buy || $0.action == .useStock)
    }
    var total = 0.0
    for input in materialInputs {
      guard
        let material = plan.materials.first(where: {
          $0.typeID == input.typeID
        })
      else { return nil }
      let legacyQuote =
        input.action == .useStock ? material.stockQuote : material.quote
      guard
        let unitPrice =
          material.replacementQuote?.weightedUnitPrice
          ?? legacyQuote?.weightedUnitPrice
      else { return nil }
      total += unitPrice * Double(input.requiredQuantity)
    }
    return total
  }

  private static func allocatedIndexCost(
    plan: IndustryPlanSnapshot,
    requestMaterialCost: Double?,
    knownMaterialTotal: Double,
    requestCount: Int
  ) -> Double? {
    guard let installationCost = plan.installationCost else { return nil }
    if knownMaterialTotal > 0, let requestMaterialCost {
      return installationCost * requestMaterialCost / knownMaterialTotal
    }
    guard requestCount > 0 else { return nil }
    return installationCost / Double(requestCount)
  }

  private static func systemName(
    for node: PlanNode?,
    productionBasis: ProductionBasis
  ) -> String {
    if node?.activity == .reaction {
      return productionBasis.reactionSystem.solarSystemName
    }
    if let category = node?.manufacturingCategory,
      let name = productionBasis.selection(for: category)?.solarSystemName
    {
      return name
    }
    return "Nicht aufgelöst"
  }
}
