import Foundation

public enum ConsolidationScience {
  /// Uses the existing science result as the sole source of blueprint runs and cost.
  public static func supply(
    job: BlueprintScienceJob, definition: BlueprintDefinition, requiredRuns: Int,
    name: String, ownerID: Int64, ownerName: String, locationID: Int64,
    materialCost: Double, sourceIDs: [UUID], originalME: Int = 0, originalTE: Int = 0,
    prerequisites: [BlueprintScienceJob] = []
  ) throws -> BlueprintSupplyPlan {
    guard requiredRuns > 0, requiredRuns <= 100_000, materialCost.isFinite, materialCost >= 0,
      definition.activity.kind == .manufacturing
    else { throw ConsolidationError.invalid("Ungültige Fertigungsanforderung.") }
    let source: BlueprintSourceReference
    let me: Int
    let te: Int
    let available: Int
    let cost: Double
    let expected: Double?
    let confidence: Double?
    let provenance: BlueprintPlanningProvenance
    switch job {
    case .copying(let copy):
      guard copy.blueprintTypeID == definition.blueprintTypeID, let fee = copy.installationCost,
        copy.durationSeconds != nil
      else { throw ConsolidationError.invalid("Kopierauftrag ist unvollständig.") }
      source = .plannedCopy(jobID: copy.id)
      me = copy.materialEfficiency
      te = copy.timeEfficiency
      available = copy.totalLicensedRuns
      cost = fee + materialCost
      expected = nil
      confidence = nil
      provenance = .copiedFromOriginal
    case .invention(let invention):
      guard invention.outputBlueprintTypeID == definition.blueprintTypeID,
        let expectedCost = invention.forecast.expectedCost,
        let confidenceCost = invention.forecast.confidencePlanCost, expectedCost.isFinite,
        confidenceCost.isFinite
      else { throw ConsolidationError.invalid("Invention-Auftrag ist unvollständig.") }
      let (runs, overflow) = invention.outputRuns.multipliedReportingOverflow(
        by: invention.forecast.requiredSuccesses)
      guard !overflow else { throw ConsolidationError.overflow }
      source = .plannedInvention(jobID: invention.id)
      me = invention.outputMaterialEfficiency
      te = invention.outputTimeEfficiency
      available = runs
      cost = confidenceCost
      expected = expectedCost
      confidence = confidenceCost
      provenance = .inventedCopy
    case .research(let research):
      guard research.blueprintTypeID == definition.blueprintTypeID,
        let fee = research.installationCost,
        research.durationSeconds != nil
      else { throw ConsolidationError.invalid("Forschungsauftrag ist unvollständig.") }
      source = research.sourceBPO
      available = requiredRuns
      me = research.activity == .materialEfficiency ? research.targetLevel : originalME
      te = research.activity == .timeEfficiency ? research.targetLevel * 2 : originalTE
      cost = fee + materialCost
      expected = nil
      confidence = nil
      provenance = .researchedOriginal
    }
    guard available >= requiredRuns, cost.isFinite else {
      throw ConsolidationError.invalid("Die geplanten Blueprint-Runs reichen nicht aus.")
    }
    let allocation = BlueprintRunAllocation(
      source: source, provenance: provenance, availableRuns: available,
      allocatedRuns: requiredRuns, remainingRuns: available - requiredRuns, materialEfficiency: me,
      timeEfficiency: te,
      ownerID: ownerID, ownerName: ownerName, locationID: locationID, sourceState: .fresh,
      acquisitionCost: cost,
      sourceSnapshotID: sourceIDs.first)
    let demand = BlueprintDemandID(
      requestID: UUID(), blueprintTypeID: definition.blueprintTypeID,
      productTypeID: definition.productTypeID, nodePath: [definition.productTypeID])
    let product = definition.activity.products.first { $0.typeID == definition.productTypeID }
    guard let product else { throw ConsolidationError.invalid("SDE-Produkt nicht aufgelöst.") }
    let output = try ConsolidationWorkspace.multiply(Int64(requiredRuns), product.quantity)
    let manufacturing = BlueprintManufacturingJob(
      demandID: demand, allocation: allocation,
      blueprintTypeID: definition.blueprintTypeID, productTypeID: definition.productTypeID,
      runs: requiredRuns, outputQuantity: output)
    var warnings: [DomainWarning] = []
    if case .invention = job {
      warnings.append(
        DomainWarning(
          code: "science.invention-probabilistic",
          message:
            "Invention ist eine probabilistische Planung. Die geplanten Erfolge sind kein vorhandener Lagerbestand.",
          severity: .warning))
    }
    return BlueprintSupplyPlan(
      blueprintTypeID: definition.blueprintTypeID, productTypeID: definition.productTypeID,
      productName: name, requiredRuns: requiredRuns, manufacturingJobs: [manufacturing],
      scienceJobs: prerequisites + [job],
      batchAllocationCost: cost, expectedInventionCost: expected, confidencePlanCost: confidence,
      warnings: warnings, sourceSnapshotIDs: sourceIDs)
  }
}
