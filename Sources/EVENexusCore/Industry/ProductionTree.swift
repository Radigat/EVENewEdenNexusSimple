import Foundation

public enum ProductionTreeStockCoverage: String, Sendable {
  case full
  case partial
  case none
  case unavailable
}

public enum ProductionTreeBlueprintAction: String, CaseIterable, Sendable {
  case useOwnedBPC
  case useOwnedBPO
  case copyOwnedBPO
  case invent
  case buyContract
  case unavailable
  case unresolved
}

public struct ProductionTreeBlueprintAssessment: Sendable {
  public let blueprintTypeID: Int64
  public let blueprintName: String
  public let requiredRuns: Int
  public let recommendation: ProductionTreeBlueprintAction
  public let availableActions: Set<ProductionTreeBlueprintAction>
  public let exactLocationBPCCount: Int
  public let exactLocationBPOCount: Int
  public let copyingLocationBPOCount: Int
  public let inventionSourceCount: Int
  public let researchLocationBPCCount: Int
  public let researchLocationBPOCount: Int
  public let exactLocationUnknownCount: Int
  public let otherLocationCount: Int
  public let indexedContractOfferCount: Int
  /// The complete contract price. It is deliberately not treated as a
  /// per-blueprint or per-run value because public contracts can be bundles.
  public let lowestWholeContractPrice: Double?
  public let inventoryIsComplete: Bool
}

public struct ManufacturingProductionTreeNode: Identifiable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let name: String
  public let requestedQuantity: Int64
  public let producedQuantity: Int64
  public let action: PlanAction
  public let activity: BlueprintActivityDefinition.Kind?
  public let runs: Int?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let facilityName: String?
  public let children: [UUID]
  public let canBuild: Bool
  public let selectedSupplyMode: MaterialSupplyMode
  public let recommendation: MakeOrBuyRecommendation?
  public let recommendationSavings: Double?
  public let totalRequiredQuantity: Int64
  public let factualWarehouseQuantity: Int64?
  public let protectedWarehouseQuantity: Int64?
  public let reservedWarehouseQuantity: Int64?
  public let usableWarehouseQuantity: Int64?
  public let stockCoverage: ProductionTreeStockCoverage
  public let blueprint: ProductionTreeBlueprintAssessment?
}

public struct ManufacturingProductionTreeSnapshot: Sendable {
  public let id: UUID
  public let createdAt: Date
  public let targetQuantity: Int64
  public let mainHub: ProcurementLocation
  public let referencePlan: IndustryPlanSnapshot
  public let selectedPlan: IndustryPlanSnapshot
  public let rootIDs: [UUID]
  public let nodes: [ManufacturingProductionTreeNode]
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    targetQuantity: Int64,
    mainHub: ProcurementLocation,
    referencePlan: IndustryPlanSnapshot,
    selectedPlan: IndustryPlanSnapshot,
    rootIDs: [UUID],
    nodes: [ManufacturingProductionTreeNode],
    warnings: [DomainWarning]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.targetQuantity = targetQuantity
    self.mainHub = mainHub
    self.referencePlan = referencePlan
    self.selectedPlan = selectedPlan
    self.rootIDs = rootIDs
    self.nodes = nodes
    self.warnings = warnings
  }

  public var nodesByID: [UUID: ManufacturingProductionTreeNode] {
    Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
  }
}

public enum ManufacturingProductionTreeProjector {
  public static func project(
    targetQuantity: Int64,
    mainHub: ProcurementLocation,
    referencePlan: IndustryPlanSnapshot,
    selectedPlan: IndustryPlanSnapshot,
    warehouse: AssetWarehouse,
    warehouseHasSnapshot: Bool,
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64],
    preferences: [Int64: MaterialProcurementPreference],
    blueprintPortfolio: BlueprintPortfolio,
    blueprintNames: [Int64: String],
    blueprintContractOffers: [Int64: [PublicContractSearchResult]],
    publicContractCoverageComplete: Bool,
    inventionDefinitions: [Int64: BlueprintDefinition],
    productionScope: ProductionWarehouseScope
  ) -> ManufacturingProductionTreeSnapshot {
    let referencedChildren = Set(referencePlan.nodes.flatMap(\.children))
    let rootIDs = referencePlan.nodes.filter {
      !referencedChildren.contains($0.id) && $0.action == .produce
    }.map(\.id)
    let materials = Dictionary(
      uniqueKeysWithValues: referencePlan.materials.map { ($0.typeID, $0) }
    )
    let factual = warehouse.factualQuantities
    let inventoryComplete =
      !blueprintPortfolio.sourceStates.isEmpty
      && blueprintPortfolio.sourceStates.allSatisfy { $0 == .fresh }
    let nodes = referencePlan.nodes.map { node in
      let material = materials[node.typeID]
      let totalRequired = max(
        0,
        material?.required
          ?? node.requestedQuantity
          ?? node.requiredQuantity
      )
      let stock = stockState(
        typeID: node.typeID,
        requiredQuantity: totalRequired,
        warehouseHasSnapshot: warehouseHasSnapshot,
        factualQuantities: factual,
        protectedQuantities: protectedQuantities,
        reservedQuantities: reservedQuantities
      )
      let analysis = material?.makeOrBuyAnalysis
      let canBuild = node.activity != nil
      let selectedMode =
        preferences[node.typeID]?.supplyMode
        ?? defaultSupplyMode(
          canBuild: canBuild,
          recommendation: analysis?.recommendation,
          action: node.action
        )
      let blueprint = node.blueprintTypeID.map { blueprintTypeID in
        blueprintAssessment(
          blueprintTypeID: blueprintTypeID,
          blueprintName:
            blueprintNames[blueprintTypeID]
            ?? "Blueprint type \(blueprintTypeID)",
          requiredRuns: max(0, node.runs ?? 0),
          activity: node.activity,
          portfolio: blueprintPortfolio,
          warehouse: warehouse,
          warehouseHasSnapshot: warehouseHasSnapshot,
          inventoryComplete: inventoryComplete,
          contracts: blueprintContractOffers[blueprintTypeID] ?? [],
          publicContractCoverageComplete: publicContractCoverageComplete,
          inventionDefinition: inventionDefinitions[blueprintTypeID],
          productionScope: productionScope
        )
      }
      return ManufacturingProductionTreeNode(
        id: node.id,
        typeID: node.typeID,
        name: node.name,
        requestedQuantity:
          node.requestedQuantity ?? node.requiredQuantity,
        producedQuantity: node.requiredQuantity,
        action: node.action,
        activity: node.activity,
        runs: node.runs,
        materialEfficiency: node.materialEfficiency,
        timeEfficiency: node.timeEfficiency,
        facilityName: node.facilityName,
        children: node.children,
        canBuild: canBuild,
        selectedSupplyMode: selectedMode,
        recommendation: analysis?.recommendation,
        recommendationSavings: analysis?.savings,
        totalRequiredQuantity: totalRequired,
        factualWarehouseQuantity: stock.factual,
        protectedWarehouseQuantity: stock.protected,
        reservedWarehouseQuantity: stock.reserved,
        usableWarehouseQuantity: stock.usable,
        stockCoverage: stock.coverage,
        blueprint: blueprint
      )
    }
    var warnings = referencePlan.warnings + selectedPlan.warnings
    if blueprintContractOffers.values.joined().contains(where: {
      $0.price != nil || $0.buyout != nil
    }) {
      warnings.append(
        DomainWarning(
          code: "production-tree.blueprint-contract-bundle-price",
          message:
            "Blueprint contract prices are whole-contract prices and are not allocated per blueprint or per run.",
          severity: .information
        )
      )
    }
    if !publicContractCoverageComplete {
      warnings.append(
        DomainWarning(
          code: "production-tree.public-contract-coverage-incomplete",
          message:
            "The public Contract index is incomplete, stale, or unavailable. Missing blueprint offers therefore remain unresolved rather than being treated as absent.",
          severity: .warning
        )
      )
    }
    return ManufacturingProductionTreeSnapshot(
      targetQuantity: targetQuantity,
      mainHub: mainHub,
      referencePlan: referencePlan,
      selectedPlan: selectedPlan,
      rootIDs: rootIDs,
      nodes: nodes,
      warnings: deduplicated(warnings)
    )
  }

  private static func defaultSupplyMode(
    canBuild: Bool,
    recommendation: MakeOrBuyRecommendation?,
    action: PlanAction
  ) -> MaterialSupplyMode {
    guard canBuild else { return .buy }
    switch recommendation {
    case .produce: return .produce
    case .buy: return .buy
    case .unavailable, nil:
      return action == .produce ? .produce : .buy
    }
  }

  private static func stockState(
    typeID: Int64,
    requiredQuantity: Int64,
    warehouseHasSnapshot: Bool,
    factualQuantities: [Int64: Int64],
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64]
  ) -> (
    factual: Int64?, protected: Int64?, reserved: Int64?, usable: Int64?,
    coverage: ProductionTreeStockCoverage
  ) {
    guard warehouseHasSnapshot else {
      return (nil, nil, nil, nil, .unavailable)
    }
    let factual = max(0, factualQuantities[typeID, default: 0])
    let protected = max(0, protectedQuantities[typeID, default: 0])
    let reserved = max(0, reservedQuantities[typeID, default: 0])
    let unavailable = saturatedAdd(protected, reserved)
    let usable = max(0, factual - min(factual, unavailable))
    let coverage: ProductionTreeStockCoverage
    if requiredQuantity <= 0 || usable >= requiredQuantity {
      coverage = .full
    } else if usable > 0 {
      coverage = .partial
    } else {
      coverage = .none
    }
    return (factual, protected, reserved, usable, coverage)
  }

  private static func blueprintAssessment(
    blueprintTypeID: Int64,
    blueprintName: String,
    requiredRuns: Int,
    activity: BlueprintActivityDefinition.Kind?,
    portfolio: BlueprintPortfolio,
    warehouse: AssetWarehouse,
    warehouseHasSnapshot: Bool,
    inventoryComplete: Bool,
    contracts: [PublicContractSearchResult],
    publicContractCoverageComplete: Bool,
    inventionDefinition: BlueprintDefinition?,
    productionScope: ProductionWarehouseScope
  ) -> ProductionTreeBlueprintAssessment {
    let productionActivity: IndustryActivitySystem? =
      switch activity {
      case .manufacturing: .manufacturing
      case .reaction: .reaction
      case .invention: .invention
      case nil: nil
      }
    let productionLocationIDs = Set(
      productionScope.locations.filter {
        productionActivity.map($0.activities.contains) ?? false
      }.map(\.locationID)
    )
    let copyingLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.copying)
      }.map(\.locationID)
    )
    let inventionLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.invention)
      }.map(\.locationID)
    )
    let researchLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.materialResearch)
          || $0.activities.contains(.timeResearch)
      }.map(\.locationID)
    )
    let entries = portfolio.entries.filter {
      $0.instance.blueprintTypeID == blueprintTypeID
    }
    let exactBPC = entries.filter {
      $0.instance.kind == .copy
        && productionLocationIDs.contains($0.instance.locationID)
        && (requiredRuns == 0 || $0.instance.runs >= requiredRuns)
    }
    let exactBPO = entries.filter {
      $0.instance.kind == .original
        && productionLocationIDs.contains($0.instance.locationID)
    }
    let copyingBPO = entries.filter {
      $0.instance.kind == .original
        && copyingLocationIDs.contains($0.instance.locationID)
    }
    let researchBPC = entries.filter {
      $0.instance.kind == .copy
        && researchLocationIDs.contains($0.instance.locationID)
    }
    let researchBPO = entries.filter {
      $0.instance.kind == .original
        && researchLocationIDs.contains($0.instance.locationID)
    }
    let knownItemIDs = Set(entries.map { $0.instance.id })
    let exactUnknownCount = warehouse.locations
      .filter { productionLocationIDs.contains($0.id) }
      .flatMap(\.owners).flatMap(\.items)
      .filter {
        $0.typeID == blueprintTypeID && !knownItemIDs.contains($0.id)
      }.count
    let inventionSources: [BlueprintPortfolioEntry]
    if let sourceTypeID = inventionDefinition?.blueprintTypeID {
      inventionSources = portfolio.entries.filter {
        $0.instance.blueprintTypeID == sourceTypeID
          && inventionLocationIDs.contains($0.instance.locationID)
          && ($0.instance.kind == .original
            || $0.instance.kind == .copy && $0.instance.runs > 0)
      }
    } else {
      inventionSources = []
    }
    let exactContracts = contracts.filter {
      $0.typeID == blueprintTypeID && $0.isIncluded
    }
    var actions: Set<ProductionTreeBlueprintAction> = []
    if !exactBPC.isEmpty { actions.insert(.useOwnedBPC) }
    if !exactBPO.isEmpty { actions.insert(.useOwnedBPO) }
    if !copyingBPO.isEmpty { actions.insert(.copyOwnedBPO) }
    if !inventionSources.isEmpty { actions.insert(.invent) }
    if !exactContracts.isEmpty { actions.insert(.buyContract) }
    let recommendation: ProductionTreeBlueprintAction
    if !exactBPC.isEmpty {
      recommendation = .useOwnedBPC
    } else if !exactBPO.isEmpty {
      recommendation = .useOwnedBPO
    } else if !inventionSources.isEmpty {
      recommendation = .invent
    } else if !copyingBPO.isEmpty {
      recommendation = .copyOwnedBPO
    } else if !exactContracts.isEmpty {
      recommendation = .buyContract
    } else {
      recommendation =
        inventoryComplete && warehouseHasSnapshot
          && publicContractCoverageComplete
        ? .unavailable : .unresolved
      actions.insert(recommendation)
    }
    let otherLocationCount = entries.filter {
      !productionLocationIDs.contains($0.instance.locationID)
        && !copyingLocationIDs.contains($0.instance.locationID)
        && !inventionLocationIDs.contains($0.instance.locationID)
        && !researchLocationIDs.contains($0.instance.locationID)
    }.count
    return ProductionTreeBlueprintAssessment(
      blueprintTypeID: blueprintTypeID,
      blueprintName: blueprintName,
      requiredRuns: requiredRuns,
      recommendation: recommendation,
      availableActions: actions,
      exactLocationBPCCount: exactBPC.count,
      exactLocationBPOCount: exactBPO.count,
      copyingLocationBPOCount: copyingBPO.count,
      inventionSourceCount: inventionSources.count,
      researchLocationBPCCount: researchBPC.count,
      researchLocationBPOCount: researchBPO.count,
      exactLocationUnknownCount: exactUnknownCount,
      otherLocationCount: otherLocationCount,
      indexedContractOfferCount: exactContracts.count,
      lowestWholeContractPrice: exactContracts.compactMap {
        $0.price ?? $0.buyout
      }.filter { $0.isFinite && $0 >= 0 }.min(),
      inventoryIsComplete: inventoryComplete && warehouseHasSnapshot
    )
  }

  private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : sum
  }

  private static func deduplicated(
    _ warnings: [DomainWarning]
  ) -> [DomainWarning] {
    var seen = Set<String>()
    return warnings.filter {
      seen.insert($0.code + "|" + $0.message).inserted
    }
  }
}
