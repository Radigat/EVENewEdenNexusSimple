import Foundation

public struct IndustryBlueprintCostAllocation: Equatable, Sendable {
  public let blueprintTypeID: Int64
  public let productName: String
  public let kind: ManualBlueprintKind
  public let amount: Double
  public let source: String

  public init(
    blueprintTypeID: Int64,
    productName: String,
    kind: ManualBlueprintKind,
    amount: Double,
    source: String
  ) {
    self.blueprintTypeID = blueprintTypeID
    self.productName = productName
    self.kind = kind
    self.amount = amount
    self.source = source
  }
}

public struct IndustryProductionEfficiency: Equatable, Sendable {
  public let materialEfficiency: Int
  public let timeEfficiency: Int

  public init(materialEfficiency: Int, timeEfficiency: Int) {
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
  }

  public var isValid: Bool {
    (0...10).contains(materialEfficiency)
      && (0...20).contains(timeEfficiency)
  }
}

public struct IndustryPlanningContext: Sendable {
  public let manufacturingProfile: ManufacturingProfile
  public let reactionProfile: ReactionProfile?
  public let productionBasis: ProductionBasis?
  public let catalog: any IndustryCatalogQuerying
  public let market: MarketOrderSnapshot
  public let homeMarket: MarketOrderSnapshot?
  public let coalitionMarket: MarketOrderSnapshot?
  public let mainContractReferences: PublicContractReferenceSnapshot?
  public let homeContractReferences: PublicContractReferenceSnapshot?
  public let coalitionContractReferences: PublicContractReferenceSnapshot?
  public let adjustedPrices: [Int64: AdjustedPrice]
  public let systemIndices: [IndustrySystemIndex]
  public let availableStock: [Int64: Int64]
  public let procurementPreferences: [Int64: MaterialProcurementPreference]
  public let defaultPurchaseLocation: ProcurementLocation
  public let assetSource: StockSource?
  public let sdeBuild: Int
  public let snapshotIDs: [UUID]
  public let inputWarnings: [DomainWarning]
  public let homeMarketWarnings: [DomainWarning]
  public let coalitionMarketWarnings: [DomainWarning]
  public let contractReferenceWarnings: [DomainWarning]
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let homeSalesTaxRate: Double?
  public let homeBrokerFeeRate: Double?
  public let coalitionSalesTaxRate: Double?
  public let coalitionBrokerFeeRate: Double?
  public let blueprintCostAllocations: [Int64: IndustryBlueprintCostAllocation]
  public let requiresCompleteBlueprintCosts: Bool
  public let productionEfficiencies: [Int64: IndustryProductionEfficiency]
  public let blueprintSupplyPlans: [Int64: BlueprintSupplyPlan]
  public let planID: UUID?
  public let characterCapabilities: [CharacterCapabilitySnapshot]
  public let jumpFreighterRoute: Sourced<JumpRouteSnapshot>?
  public let jumpFreighterRouteWarnings: [DomainWarning]
  public let capitalJumpRoutes: [Int64: Sourced<CapitalJumpRouteSnapshot>]
  public let capitalJumpRouteWarnings: [DomainWarning]

  public init(
    manufacturingProfile: ManufacturingProfile,
    reactionProfile: ReactionProfile? = nil,
    productionBasis: ProductionBasis? = nil,
    catalog: any IndustryCatalogQuerying,
    market: MarketOrderSnapshot,
    homeMarket: MarketOrderSnapshot? = nil,
    coalitionMarket: MarketOrderSnapshot? = nil,
    mainContractReferences: PublicContractReferenceSnapshot? = nil,
    homeContractReferences: PublicContractReferenceSnapshot? = nil,
    coalitionContractReferences: PublicContractReferenceSnapshot? = nil,
    adjustedPrices: [Int64: AdjustedPrice],
    systemIndices: [IndustrySystemIndex],
    availableStock: [Int64: Int64] = [:],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    defaultPurchaseLocation: ProcurementLocation = .jita,
    assetSource: StockSource? = nil,
    sdeBuild: Int,
    snapshotIDs: [UUID] = [],
    inputWarnings: [DomainWarning] = [],
    homeMarketWarnings: [DomainWarning] = [],
    coalitionMarketWarnings: [DomainWarning] = [],
    contractReferenceWarnings: [DomainWarning] = [],
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil,
    homeSalesTaxRate: Double? = nil,
    homeBrokerFeeRate: Double? = nil,
    coalitionSalesTaxRate: Double? = nil,
    coalitionBrokerFeeRate: Double? = nil,
    blueprintCostAllocations: [Int64: IndustryBlueprintCostAllocation] = [:],
    requiresCompleteBlueprintCosts: Bool = false,
    productionEfficiencies: [Int64: IndustryProductionEfficiency] = [:],
    blueprintSupplyPlans: [Int64: BlueprintSupplyPlan] = [:],
    planID: UUID? = nil,
    characterCapabilities: [CharacterCapabilitySnapshot] = [],
    jumpFreighterRoute: Sourced<JumpRouteSnapshot>? = nil,
    jumpFreighterRouteWarnings: [DomainWarning] = [],
    capitalJumpRoutes: [Int64: Sourced<CapitalJumpRouteSnapshot>] = [:],
    capitalJumpRouteWarnings: [DomainWarning] = []
  ) {
    self.manufacturingProfile = manufacturingProfile
    self.reactionProfile = reactionProfile
    self.productionBasis = productionBasis
    self.catalog = catalog
    self.market = market
    self.homeMarket = homeMarket
    self.coalitionMarket = coalitionMarket
    self.mainContractReferences = mainContractReferences
    self.homeContractReferences = homeContractReferences
    self.coalitionContractReferences = coalitionContractReferences
    self.adjustedPrices = adjustedPrices
    self.systemIndices = systemIndices
    self.availableStock = availableStock
    self.procurementPreferences = procurementPreferences
    self.defaultPurchaseLocation = defaultPurchaseLocation
    self.assetSource = assetSource
    self.sdeBuild = sdeBuild
    self.snapshotIDs = snapshotIDs
    self.inputWarnings = inputWarnings
    self.homeMarketWarnings = homeMarketWarnings
    self.coalitionMarketWarnings = coalitionMarketWarnings
    self.contractReferenceWarnings = contractReferenceWarnings
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.homeSalesTaxRate = homeSalesTaxRate
    self.homeBrokerFeeRate = homeBrokerFeeRate
    self.coalitionSalesTaxRate = coalitionSalesTaxRate
    self.coalitionBrokerFeeRate = coalitionBrokerFeeRate
    self.blueprintCostAllocations = blueprintCostAllocations
    self.requiresCompleteBlueprintCosts = requiresCompleteBlueprintCosts
    self.productionEfficiencies = productionEfficiencies
    self.blueprintSupplyPlans = blueprintSupplyPlans
    self.planID = planID
    self.characterCapabilities = characterCapabilities
    self.jumpFreighterRoute = jumpFreighterRoute
    self.jumpFreighterRouteWarnings = jumpFreighterRouteWarnings
    self.capitalJumpRoutes = capitalJumpRoutes
    self.capitalJumpRouteWarnings = capitalJumpRouteWarnings
  }
}

public enum IndustryPlannerError: Error, Equatable, Sendable {
  case invalidInput([ProductionInputError])
  case unknownProduct(line: Int, name: String)
  case missingBlueprint(line: Int, name: String)
  case invalidStock(line: Int, value: String)
  case cycle([Int64])
  case unsupportedInvention(typeID: Int64)
  case complexityLimit
  case invalidProductionEfficiency(typeID: Int64)
}

private struct OreRefiningOptimizationResult {
  let purchases: [OreRefiningPurchase]
  let coveredMinerals: [Int64: Int64]
  let remainingDirectMinerals: [Int64: Int64]
  let warnings: [DomainWarning]
}

private struct OreRefiningProposal {
  let purchase: OreRefiningPurchase
  let covered: [Int64: Int64]
  let estimatedSavings: Double
}

public struct IndustryPlannerInputPreparation: Sendable {
  public let requests: [ProductionRequestLine]
  public let productTypeIDsByRequestID: [UUID: Int64]
  public let marketTypeIDs: Set<Int64>
  public let requestedProductTypeIDs: Set<Int64>
  public let requestedSelfJumpCapitals: [CapitalSelfJumpProduct]

  public init(
    requests: [ProductionRequestLine],
    productTypeIDsByRequestID: [UUID: Int64],
    marketTypeIDs: Set<Int64>,
    requestedProductTypeIDs: Set<Int64>,
    requestedSelfJumpCapitals: [CapitalSelfJumpProduct]
  ) {
    self.requests = requests
    self.productTypeIDsByRequestID = productTypeIDsByRequestID
    self.marketTypeIDs = marketTypeIDs
    self.requestedProductTypeIDs = requestedProductTypeIDs
    self.requestedSelfJumpCapitals = requestedSelfJumpCapitals
  }
}

public struct IndustryPlanner: Sendable {
  public init() {}

  /// Resolves and traverses planner input once for all data-loading decisions.
  /// The returned value can be reused by `plan(preparation:context:)` so an
  /// interactive recalculation does not parse or resolve the same roots again.
  public func prepare(
    input: String,
    catalog: any IndustryCatalogQuerying,
    includeCompressedOreOptions: Bool = false,
    includeJumpFuelIsotopes: Bool = false
  ) async throws -> IndustryPlannerInputPreparation {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }

    var productTypeIDsByRequestID: [UUID: Int64] = [:]
    var productTypeIDsByName: [String: Int64] = [:]
    var requestedProductTypeIDs = Set<Int64>()
    for request in parsed.requests {
      let typeID: Int64
      if let cached = productTypeIDsByName[request.productName] {
        typeID = cached
      } else if let resolved = try await catalog.typeID(named: request.productName) {
        typeID = resolved
        productTypeIDsByName[request.productName] = resolved
      } else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      productTypeIDsByRequestID[request.id] = typeID
      requestedProductTypeIDs.insert(typeID)
    }

    var marketTypeIDs = Set<Int64>()
    var visited = Set<Int64>()
    for typeID in requestedProductTypeIDs.sorted() {
      try await collectMarketTypes(
        typeID: typeID,
        catalog: catalog,
        path: [],
        visited: &visited,
        result: &marketTypeIDs
      )
    }
    if includeCompressedOreOptions,
      let options = try? await catalog.compressedOreOptions(
        producing: marketTypeIDs
      )
    {
      marketTypeIDs.formUnion(options.map(\.typeID))
    }
    if includeJumpFuelIsotopes {
      marketTypeIDs.formUnion(JumpFuelIsotope.marketTypeIDs)
    }

    // The SQLite catalog can resolve these immutable facts in bounded batch
    // queries. Warming the calculation-scoped catalog here removes hundreds
    // of repeated actor/SQLite round trips while the same graph is expanded.
    let metadataTypeIDs = marketTypeIDs
    async let resolvedNames = catalog.typeNames(ids: metadataTypeIDs)
    async let resolvedClassifications = catalog.industryClassifications(
      typeIDs: metadataTypeIDs
    )
    _ = try await (resolvedNames, resolvedClassifications)

    var capitalProducts: [Int64: CapitalSelfJumpProduct] = [:]
    for request in parsed.requests {
      guard let typeID = productTypeIDsByRequestID[request.id],
        capitalProducts[typeID] == nil
      else { continue }
      let classification = try await catalog.industryClassification(
        productTypeID: typeID
      )
      let canonicalName =
        try await catalog.typeName(id: typeID)
        ?? request.productName
      if let product = CapitalSelfJumpPolicy.product(
        typeID: typeID,
        name: canonicalName,
        classification: classification
      ) {
        capitalProducts[typeID] = product
      }
    }

    return IndustryPlannerInputPreparation(
      requests: parsed.requests,
      productTypeIDsByRequestID: productTypeIDsByRequestID,
      marketTypeIDs: marketTypeIDs,
      requestedProductTypeIDs: requestedProductTypeIDs,
      requestedSelfJumpCapitals: capitalProducts.values.sorted {
        $0.typeID < $1.typeID
      }
    )
  }

  public func requiredMarketTypeIDs(
    input: String,
    catalog: any IndustryCatalogQuerying,
    includeCompressedOreOptions: Bool = false,
    includeJumpFuelIsotopes: Bool = false
  ) async throws -> Set<Int64> {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }
    var result = Set<Int64>()
    var visited = Set<Int64>()
    for request in parsed.requests {
      guard
        let typeID = try await catalog.typeID(
          named: request.productName
        )
      else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      try await collectMarketTypes(
        typeID: typeID,
        catalog: catalog,
        path: [],
        visited: &visited,
        result: &result
      )
    }
    if includeCompressedOreOptions {
      // A legacy adapter can still produce a valid direct-mineral plan. The
      // calculation phase records the missing typeMaterials capability as an
      // explicit warning instead of failing before market data can load.
      if let options = try? await catalog.compressedOreOptions(
        producing: result
      ) {
        result.formUnion(options.map(\.typeID))
      }
    }
    if includeJumpFuelIsotopes {
      result.formUnion(JumpFuelIsotope.marketTypeIDs)
    }
    return result
  }

  public func requestedProductTypeIDs(
    input: String,
    catalog: any IndustryCatalogQuerying
  ) async throws -> Set<Int64> {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }
    var result = Set<Int64>()
    for request in parsed.requests {
      guard let typeID = try await catalog.typeID(named: request.productName)
      else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      result.insert(typeID)
    }
    return result
  }

  public func requestedSelfJumpCapitals(
    input: String,
    catalog: any IndustryCatalogQuerying
  ) async throws -> [CapitalSelfJumpProduct] {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }
    var products: [Int64: CapitalSelfJumpProduct] = [:]
    for request in parsed.requests {
      guard let typeID = try await catalog.typeID(named: request.productName)
      else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      let classification = try await catalog.industryClassification(
        productTypeID: typeID
      )
      let canonicalName =
        try await catalog.typeName(id: typeID)
        ?? request.productName
      if let product = CapitalSelfJumpPolicy.product(
        typeID: typeID,
        name: canonicalName,
        classification: classification
      ) {
        products[typeID] = product
      }
    }
    return products.values.sorted { $0.typeID < $1.typeID }
  }

  public func plan(
    input: String,
    context: IndustryPlanningContext
  ) async throws -> IndustryPlanSnapshot {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }
    var productTypeIDsByRequestID: [UUID: Int64] = [:]
    for request in parsed.requests {
      guard let typeID = try await context.catalog.typeID(named: request.productName)
      else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      productTypeIDsByRequestID[request.id] = typeID
    }
    return try await plan(
      requests: parsed.requests,
      productTypeIDsByRequestID: productTypeIDsByRequestID,
      context: context,
      reusableMakeOrBuyAnalyses: [:]
    )
  }

  public func plan(
    preparation: IndustryPlannerInputPreparation,
    context: IndustryPlanningContext
  ) async throws -> IndustryPlanSnapshot {
    try await preloadPlanningMetadata(
      typeIDs: preparation.marketTypeIDs,
      catalog: context.catalog
    )
    return try await plan(
      requests: preparation.requests,
      productTypeIDsByRequestID: preparation.productTypeIDsByRequestID,
      context: context,
      reusableMakeOrBuyAnalyses: [:]
    )
  }

  /// Runs an immediate second scenario against the same immutable SDE,
  /// market, facility and rule inputs while reusing matching full-quantity
  /// make-or-buy comparisons from the first pass. Stock, procurement choices
  /// and Blueprint allocations may differ; a changed market/SDE/rule identity
  /// disables reuse automatically.
  public func plan(
    preparation: IndustryPlannerInputPreparation,
    context: IndustryPlanningContext,
    reusingMakeOrBuyAnalysesFrom baseline: IndustryPlanSnapshot
  ) async throws -> IndustryPlanSnapshot {
    try await preloadPlanningMetadata(
      typeIDs: preparation.marketTypeIDs,
      catalog: context.catalog
    )
    let canReuse =
      baseline.provenance.sdeBuild == context.sdeBuild
      && baseline.provenance.ruleVersion == IndustryRuleSet.current.version
      && baseline.provenance.snapshotIDs.contains(context.market.id)
    let reusableAnalyses =
      canReuse
      ? Dictionary(
        uniqueKeysWithValues: baseline.materials.compactMap { material in
          material.makeOrBuyAnalysis.map { (material.typeID, $0) }
        }
      ) : [:]
    return try await plan(
      requests: preparation.requests,
      productTypeIDsByRequestID: preparation.productTypeIDsByRequestID,
      context: context,
      reusableMakeOrBuyAnalyses: reusableAnalyses
    )
  }

  private func plan(
    requests: [ProductionRequestLine],
    productTypeIDsByRequestID: [UUID: Int64],
    context: IndustryPlanningContext,
    reusableMakeOrBuyAnalyses: [Int64: MaterialMakeOrBuyAnalysis]
  ) async throws -> IndustryPlanSnapshot {
    if let invalid = context.productionEfficiencies.first(where: {
      !$0.value.isValid
    }) {
      throw IndustryPlannerError.invalidProductionEfficiency(
        typeID: invalid.key
      )
    }

    var state = BuildState(
      stock: context.availableStock,
      warnings:
        context.inputWarnings + context.homeMarketWarnings
        + context.coalitionMarketWarnings + context.contractReferenceWarnings
    )
    state.installBlueprintSupplyPlans(context.blueprintSupplyPlans)
    for request in requests {
      guard let typeID = productTypeIDsByRequestID[request.id] else {
        throw IndustryPlannerError.unknownProduct(
          line: request.lineNumber,
          name: request.productName
        )
      }
      guard
        let definition = try await context.catalog
          .productionDefinition(productTypeID: typeID)
      else {
        throw IndustryPlannerError.missingBlueprint(
          line: request.lineNumber,
          name: request.productName
        )
      }
      guard definition.activity.kind != .invention else {
        throw IndustryPlannerError.unsupportedInvention(typeID: typeID)
      }
      guard
        let outputQuantity = definition.activity.products.first(where: {
          $0.typeID == definition.productTypeID
        })?.quantity,
        outputQuantity > 0
      else {
        throw IndustryPlannerError.missingBlueprint(
          line: request.lineNumber,
          name: request.productName
        )
      }
      let requestedRuns = Self.runsRequired(
        wantedQuantity: request.wantedQuantity,
        outputPerRun: outputQuantity
      )
      try await expand(
        definition: definition,
        requestedQuantity: Int64(request.wantedQuantity),
        requestedRuns: requestedRuns,
        requestedME: request.materialEfficiency,
        requestedTE: request.timeEfficiency,
        topLevelID: request.id,
        path: [],
        context: context,
        state: &state
      )
    }

    return try await finish(
      requests: requests,
      context: context,
      state: state,
      reusableMakeOrBuyAnalyses: reusableMakeOrBuyAnalyses
    )
  }

  private func preloadPlanningMetadata(
    typeIDs: Set<Int64>,
    catalog: any IndustryCatalogQuerying
  ) async throws {
    async let resolvedNames = catalog.typeNames(ids: typeIDs)
    async let resolvedClassifications = catalog.industryClassifications(
      typeIDs: typeIDs
    )
    _ = try await (resolvedNames, resolvedClassifications)
  }

  private func expand(
    definition: BlueprintDefinition,
    requestedQuantity: Int64,
    requestedRuns: Int,
    requestedME: Int,
    requestedTE: Int,
    topLevelID: UUID,
    path: [Int64],
    context: IndustryPlanningContext,
    state: inout BuildState
  ) async throws {
    guard path.count < 128,
      state.nodes.count < 100_000,
      definition.activity.materials.count <= 10_000
    else {
      throw IndustryPlannerError.complexityLimit
    }
    let outputQuantity = max(1, definition.activity.products.first?.quantity ?? 1)
    let producedQuantity = Self.saturatedMultiply(
      Int64(requestedRuns),
      outputQuantity
    )
    if path.contains(definition.productTypeID) {
      throw IndustryPlannerError.cycle(path + [definition.productTypeID])
    }

    let nodeID = UUID()
    var childIDs: [UUID] = []
    let isReaction = definition.activity.kind == .reaction
    let efficiency = context.productionEfficiencies[definition.productTypeID]
    let fallbackME = isReaction ? 0 : efficiency?.materialEfficiency ?? requestedME
    let fallbackTE = isReaction ? 0 : efficiency?.timeEfficiency ?? requestedTE
    let blueprintJobSlices =
      isReaction
      ? [BlueprintJobSlice.fallback(runs: requestedRuns, me: 0, te: 0)]
      : state.consumeBlueprintJobs(
        blueprintTypeID: definition.blueprintTypeID,
        requiredRuns: requestedRuns,
        fallbackME: fallbackME,
        fallbackTE: fallbackTE
      )
    let jobMEs = Set(blueprintJobSlices.map(\.me))
    let jobTEs = Set(blueprintJobSlices.map(\.te))
    let nodeME = jobMEs.count == 1 ? jobMEs.first : nil
    let nodeTE = jobTEs.count == 1 ? jobTEs.first : nil
    let classification = try await context.catalog.industryClassification(
      productTypeID: definition.productTypeID
    )
    let manufacturingCategory =
      isReaction ? nil : classification?.manufacturingCategory ?? .module
    let facilitySelection = manufacturingCategory.flatMap {
      context.productionBasis?.selection(for: $0)
    }
    let selectedStructure = facilitySelection.flatMap {
      context.productionBasis?.structure(id: $0.structureID)
    }
    if facilitySelection?.needsReview == true {
      state.warnings.append(
        DomainWarning(
          code: "industry.facility-needs-review",
          message:
            "The selected facility for \(manufacturingCategory?.displayName ?? "manufacturing") contains unresolved modifiers.",
          severity: .blocking
        )
      )
    }

    for material in definition.activity.materials {
      let rawRequired = Self.saturatedMultiply(
        Int64(requestedRuns),
        material.quantity
      )
      let required: Int64
      if isReaction {
        required = Self.scaledReactionQuantity(
          rawRequired: rawRequired,
          runs: requestedRuns,
          multiplier:
            context.reactionProfile?.effectiveMaterialMultiplier ?? 1
        )
      } else {
        required = blueprintJobSlices.reduce(0) { partial, slice in
          Self.saturatedAdd(
            partial,
            Self.manufacturingMaterialQuantity(
              baseQuantity: material.quantity,
              runs: slice.runs,
              materialEfficiency: slice.me,
              facilityMultiplier:
                facilitySelection?.materialMultiplier
                ?? context.manufacturingProfile.effectiveMaterialMultiplier
            )
          )
        }
      }
      state.required[material.typeID] = Self.saturatedAdd(
        state.required[material.typeID, default: 0],
        required
      )
      let childName =
        try await context.catalog.typeName(id: material.typeID)
        ?? "Type \(material.typeID)"
      let childClassification =
        try await context.catalog.industryClassification(
          productTypeID: material.typeID
        )
      let isBlacklisted =
        context.productionBasis?.blacklist.blocks(
          typeName: childName,
          classification: childClassification
        ) ?? false
      let childDefinition = try await context.catalog
        .productionDefinition(productTypeID: material.typeID)
      let hasSupportedDefinition =
        childDefinition.map { $0.activity.kind != .invention } ?? false
      let canProduce = hasSupportedDefinition && !isBlacklisted
      let defaultMode: MaterialSupplyMode = canProduce ? .produce : .buy
      var preference =
        context.procurementPreferences[material.typeID]
        ?? MaterialProcurementPreference(
          supplyMode: defaultMode,
          purchaseLocation: context.defaultPurchaseLocation
        )
      if preference.supplyMode == .produce, !canProduce {
        preference.supplyMode = .buy
        if state.invalidProductionPreferenceTypeIDs.insert(material.typeID)
          .inserted
        {
          state.warnings.append(
            DomainWarning(
              code: "industry.production-unavailable",
              message:
                "\(childName) cannot be produced in this plan and remains a purchase.",
              severity: .information
            )
          )
        }
      }
      state.procurement[material.typeID] = preference
      let available = state.stock[material.typeID, default: 0]
      let shouldUseStock =
        preference.supplyMode == .warehouse
        || preference.usesAvailableStockFirst
      let fromStock = shouldUseStock ? min(available, required) : 0
      if fromStock > 0 {
        state.stock[material.typeID] = available - fromStock
        state.stockUsed[material.typeID] = Self.saturatedAdd(
          state.stockUsed[material.typeID, default: 0],
          fromStock
        )
        let stockID = UUID()
        childIDs.append(stockID)
        state.nodes.append(
          PlanNode(
            id: stockID,
            typeID: material.typeID,
            name: childName,
            requestedQuantity: fromStock,
            requiredQuantity: fromStock,
            action: .useStock,
            activity: nil,
            runs: nil,
            materialEfficiency: nil,
            timeEfficiency: nil,
            children: [],
            topLevelRequestID: topLevelID
          )
        )
      }
      let remaining = required - fromStock
      if preference.supplyMode == .warehouse, remaining > 0,
        state.stockShortfallWarningTypeIDs.insert(material.typeID).inserted
      {
        state.warnings.append(
          DomainWarning(
            code: "industry.warehouse-shortfall",
            message:
              "Only \(fromStock) of \(required) \(childName) can be supplied by the warehouse; the remainder stays on the shopping list.",
            severity: .information
          )
        )
      }
      guard remaining > 0 else { continue }

      if preference.supplyMode == .produce,
        let childDefinition
      {
        let childOutput = max(
          1,
          childDefinition.activity.products.first?.quantity ?? 1
        )
        let childRuns = Self.runsRequired(
          wantedQuantity: remaining,
          outputPerRun: childOutput
        )
        let before = state.nodes.count
        try await expand(
          definition: childDefinition,
          requestedQuantity: remaining,
          requestedRuns: childRuns,
          requestedME: childDefinition.activity.kind == .reaction
            ? 0
            : context.productionBasis?.defaultIntermediateME
              ?? context.manufacturingProfile.defaultIntermediateME,
          requestedTE: childDefinition.activity.kind == .reaction
            ? 0
            : context.productionBasis?.defaultIntermediateTE
              ?? context.manufacturingProfile.defaultIntermediateTE,
          topLevelID: topLevelID,
          path: path + [definition.productTypeID],
          context: context,
          state: &state
        )
        if state.nodes.count > before, let childRoot = state.nodes.last {
          childIDs.append(childRoot.id)
        }
        state.toProduce[material.typeID] = Self.saturatedAdd(
          state.toProduce[material.typeID, default: 0],
          Self.saturatedMultiply(Int64(childRuns), childOutput)
        )
      } else {
        if isBlacklisted,
          state.blacklistWarningTypeIDs.insert(material.typeID).inserted
        {
          state.warnings.append(
            DomainWarning(
              code: "industry.production-blacklist",
              message:
                "\(childName) cannot be produced and uses the selected purchase or warehouse source.",
              severity: .information
            )
          )
        }
        state.toBuy[material.typeID] = Self.saturatedAdd(
          state.toBuy[material.typeID, default: 0], remaining
        )
        let buyID = UUID()
        childIDs.append(buyID)
        state.nodes.append(
          PlanNode(
            id: buyID,
            typeID: material.typeID,
            name: childName,
            requestedQuantity: remaining,
            requiredQuantity: remaining,
            action: .buy,
            activity: nil,
            runs: nil,
            materialEfficiency: nil,
            timeEfficiency: nil,
            children: [],
            topLevelRequestID: topLevelID
          )
        )
      }
    }

    state.nodes.append(
      PlanNode(
        id: nodeID,
        typeID: definition.productTypeID,
        name: try await context.catalog.typeName(
          id: definition.productTypeID
        ) ?? "Type \(definition.productTypeID)",
        requestedQuantity: requestedQuantity,
        requiredQuantity: producedQuantity,
        action: .produce,
        activity: definition.activity.kind,
        runs: requestedRuns,
        materialEfficiency: isReaction ? nil : nodeME,
        timeEfficiency: isReaction ? nil : nodeTE,
        blueprintTypeID: definition.blueprintTypeID,
        facilityName:
          isReaction
          ? context.reactionProfile?.structureName
          : facilitySelection?.structureName
            ?? context.manufacturingProfile.structureName,
        manufacturingCategory: manufacturingCategory,
        sourceCategory: classification?.categoryName,
        sourceGroup: classification?.groupName,
        sourceTechLevel: classification?.techLevel,
        children: childIDs,
        topLevelRequestID: topLevelID
      )
    )
    state.jobDefinitions.append(
      contentsOf: blueprintJobSlices.map {
        JobDefinition(
          definition: definition,
          runs: $0.runs,
          me: $0.me,
          te: $0.te,
          isTopLevel: path.isEmpty,
          facilitySelection: facilitySelection,
          selectedStructure: selectedStructure,
          blueprintSupplyJobID: $0.supplyJobID,
          blueprintSource: $0.source
        )
      }
    )
    for childID in childIDs {
      state.explanations.append(
        ExplanationEdge(
          id: UUID(),
          fromNodeID: nodeID,
          toNodeID: childID,
          rule: "industry.material-requirement",
          explanation:
            "This child supplies material required by \(definition.productTypeID).",
          source: definition.source
        )
      )
    }
  }

  private func finish(
    requests: [ProductionRequestLine],
    context: IndustryPlanningContext,
    state: BuildState,
    reusableMakeOrBuyAnalyses: [Int64: MaterialMakeOrBuyAnalysis]
  ) async throws -> IndustryPlanSnapshot {
    let mainMarketBook = PreparedMarketOrderBook(snapshot: context.market)
    let systemIndexLookup = IndustrySystemIndexLookup(
      indices: context.systemIndices
    )
    var purchaseQuotes: [Int64: PriceQuote] = [:]
    var stockQuotes: [Int64: PriceQuote] = [:]
    var replacementQuotes: [Int64: PriceQuote] = [:]
    var warnings = state.warnings
    var purchasedMaterialCost = 0.0
    var purchasedMaterialCostComplete = true
    for (typeID, quantity) in state.toBuy.sorted(by: { $0.key < $1.key }) {
      let quote = mainMarketBook.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy
      )
      purchaseQuotes[typeID] = quote
      warnings.append(contentsOf: quote.warnings)
      if let total = quote.total {
        let updatedCost = purchasedMaterialCost + total
        if updatedCost.isFinite, updatedCost >= 0 {
          purchasedMaterialCost = updatedCost
        } else {
          purchasedMaterialCostComplete = false
        }
      } else {
        purchasedMaterialCostComplete = false
      }
    }
    for (typeID, quantity) in state.stockUsed.sorted(by: { $0.key < $1.key }) {
      let quote = mainMarketBook.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy
      )
      stockQuotes[typeID] = quote
      warnings.append(contentsOf: quote.warnings)
    }
    var replacementMaterialCost = 0.0
    var materialCostComplete = true
    let replacementLeafTypeIDs = Set(state.toBuy.keys).union(
      state.stockUsed.keys
    )
    for typeID in replacementLeafTypeIDs.sorted() {
      let quantity = state.required[typeID, default: 0]
      let quote = mainMarketBook.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy
      )
      replacementQuotes[typeID] = quote
      warnings.append(contentsOf: quote.warnings)
      // The full-demand quote supplies one replacement unit value for bought
      // and stocked inputs. Produced units are charged through their inputs.
      guard quote.isComplete,
        let total = quote.total, total.isFinite, total >= 0,
        let unitPrice = quote.weightedUnitPrice,
        unitPrice.isFinite, unitPrice >= 0
      else {
        materialCostComplete = false
        continue
      }
      let valuedQuantity =
        Double(state.toBuy[typeID, default: 0])
        + Double(state.stockUsed[typeID, default: 0])
      let contribution = valuedQuantity * unitPrice
      let updatedCost = replacementMaterialCost + contribution
      if contribution.isFinite, contribution >= 0,
        updatedCost.isFinite, updatedCost >= 0
      {
        replacementMaterialCost = updatedCost
      } else {
        materialCostComplete = false
      }
    }
    let directMaterialCost = replacementMaterialCost
    var stockMaterialCost = 0.0
    var stockMaterialCostComplete = true
    for (typeID, quantity) in state.stockUsed.sorted(by: { $0.key < $1.key }) {
      guard let unitPrice = replacementQuotes[typeID]?.weightedUnitPrice,
        unitPrice.isFinite,
        unitPrice >= 0
      else {
        stockMaterialCostComplete = false
        continue
      }
      let updatedCost = stockMaterialCost + Double(quantity) * unitPrice
      if updatedCost.isFinite, updatedCost >= 0 {
        stockMaterialCost = updatedCost
      } else {
        stockMaterialCostComplete = false
      }
    }

    var jobs: [IndustryJobCost] = []
    var totalSeconds: Int64 = 0
    var manufacturingDurations: [Int64] = []
    var reactionDurations: [Int64] = []
    var installationCostComplete = true
    let consolidatedJobs = consolidateIntermediateJobs(state.jobDefinitions)
    if consolidatedJobs.contains(where: {
      $0.definition.activity.kind == .reaction
    }) && context.reactionProfile == nil {
      warnings.append(
        DomainWarning(
          code: "reaction.profile-required",
          message:
            "Reaction jobs require a confirmed reaction profile; their modifiers need review.",
          severity: .blocking
        )
      )
      installationCostComplete = false
    }
    for job in consolidatedJobs {
      let timeMultiplier =
        job.definition.activity.kind == .reaction
        ? (context.reactionProfile?.effectiveTimeMultiplier ?? 1)
        : job.facilitySelection?.timeMultiplier
          ?? context.manufacturingProfile.effectiveTimeMultiplier
      let baseDuration = Double(
        job.definition.activity.durationSeconds
      )
      let runDuration = baseDuration * Double(job.runs)
      let teMultiplier =
        job.definition.activity.kind == .reaction
        ? 1.0 : (1.0 - Double(job.te) / 100.0)
      let effectiveDuration =
        runDuration * timeMultiplier * teMultiplier
      let durationSeconds: Int64
      if effectiveDuration <= 0 {
        durationSeconds = 0
      } else if !effectiveDuration.isFinite
        || effectiveDuration >= Double(Int64.max)
      {
        durationSeconds = Int64.max
      } else {
        durationSeconds = max(0, Int64(ceil(effectiveDuration)))
      }
      totalSeconds = Self.saturatedAdd(totalSeconds, durationSeconds)
      if job.definition.activity.kind == .reaction {
        reactionDurations.append(durationSeconds)
      } else {
        manufacturingDurations.append(durationSeconds)
      }
      var missingAdjustedPrice = false
      let eiv = job.definition.activity.materials.reduce(0.0) {
        partial, material in
        guard
          let adjusted = context.adjustedPrices[material.typeID]?
            .adjustedPrice,
          adjusted.isFinite,
          adjusted >= 0,
          material.quantity >= 0,
          job.runs >= 0
        else {
          missingAdjustedPrice = true
          return partial
        }
        let updated =
          partial
          + adjusted * Double(material.quantity) * Double(job.runs)
        guard updated.isFinite, updated >= 0 else {
          missingAdjustedPrice = true
          return partial
        }
        return updated
      }
      if missingAdjustedPrice {
        installationCostComplete = false
        warnings.append(
          DomainWarning(
            code: "industry.missing-adjusted-price",
            message: "An adjusted price required for EIV is missing.",
            severity: .blocking
          )
        )
      }
      let activity = job.definition.activity.kind
      let basisSystem =
        activity == .reaction
        ? job.selectedStructure.flatMap {
          context.productionBasis?.systemConfiguration(
            for: .reaction,
            structure: $0
          )
        }
        : context.productionBasis?.manufacturingSystem(
          for: job.selectedStructure
        )
      let systemID =
        activity == .reaction
        ? context.reactionProfile?.solarSystemID
          ?? basisSystem?.solarSystemID
          ?? context.manufacturingProfile.solarSystemID
        : basisSystem?.solarSystemID
          ?? job.selectedStructure?.solarSystemID
          ?? context.manufacturingProfile.solarSystemID
      let availableSystemIndex = systemIndexLookup.costIndex(
        solarSystemID: systemID,
        activity: activity
      )
      let index =
        basisSystem?.costIndexOverride
        ?? availableSystemIndex ?? 0
      if basisSystem?.costIndexOverride == nil
        && availableSystemIndex == nil
      {
        installationCostComplete = false
        warnings.append(
          DomainWarning(
            code: "industry.missing-system-index",
            message:
              "The system cost index for \(activity.rawValue) is unavailable.",
            severity: .blocking
          )
        )
      }
      let facilityTax =
        activity == .reaction
        ? context.productionBasis?.structure(
          id: context.productionBasis?.reactionStructureID
        )?.facilityTaxRate
          ?? context.reactionProfile?.facilityTaxRate ?? 0
        : job.selectedStructure?.facilityTaxRate
          ?? context.manufacturingProfile.facilityTaxRate
      let bonusMultiplier =
        activity == .reaction
        ? context.reactionProfile?.effectiveJobCostMultiplier ?? 1
        : job.selectedStructure?.jobCostMultiplier
          ?? context.manufacturingProfile.effectiveJobCostMultiplier
      let scc =
        activity == .reaction
        ? IndustryRuleSet.current.reactionSCCRate
        : IndustryRuleSet.current.manufacturingSCCRate
      let alpha =
        (context.productionBasis?.cloneState
          ?? (activity == .reaction
            ? context.reactionProfile?.cloneState
            : context.manufacturingProfile.cloneState))
          == .alpha
        ? IndustryRuleSet.current.alphaSurchargeRate : 0
      let calculatedTotal =
        eiv * ((index * bonusMultiplier) + facilityTax + scc + alpha)
      let total: Double
      if calculatedTotal.isFinite, calculatedTotal >= 0 {
        total = calculatedTotal
      } else {
        total = 0
        installationCostComplete = false
        warnings.append(
          DomainWarning(
            code: "industry.invalid-installation-cost",
            message:
              "An installation cost exceeded safe numeric limits and was not accepted.",
            severity: .blocking
          )
        )
      }
      jobs.append(
        IndustryJobCost(
          id: UUID(),
          typeID: job.definition.productTypeID,
          productName:
            try await context.catalog.typeName(
              id: job.definition.productTypeID
            ),
          activity: activity,
          runs: job.runs,
          outputQuantity: Self.saturatedMultiply(
            Int64(job.runs),
            max(
              1,
              job.definition.activity.products.first(where: {
                $0.typeID == job.definition.productTypeID
              })?.quantity ?? 1
            )
          ),
          materialEfficiency: activity == .reaction ? nil : job.me,
          timeEfficiency: activity == .reaction ? nil : job.te,
          isTopLevel: job.isTopLevel,
          estimatedItemValue: eiv,
          systemCostIndex: index,
          bonusMultiplier: bonusMultiplier,
          facilityTax: facilityTax,
          sccSurcharge: scc,
          alphaSurcharge: alpha,
          total: total,
          facilityName:
            activity == .reaction
            ? context.reactionProfile?.structureName
            : job.facilitySelection?.structureName
              ?? context.manufacturingProfile.structureName,
          manufacturingCategory: job.facilitySelection?.category,
          blueprintSupplyJobID: job.blueprintSupplyJobID,
          blueprintSource: job.blueprintSource,
          durationSeconds: durationSeconds
        )
      )
    }
    var scienceSeconds: Int64 = 0
    let concreteScienceJobs = Set(context.blueprintSupplyPlans.values.flatMap(\.scienceJobs))
    for job in concreteScienceJobs {
      let duration: Int64?
      switch job {
      case .copying(let value): duration = value.durationSeconds
      case .research(let value): duration = value.durationSeconds
      case .invention(let value): duration = value.durationSeconds
      }
      if let duration { scienceSeconds = Self.saturatedAdd(scienceSeconds, duration) }
      else { warnings.append(DomainWarning(code: "science.duration-unavailable", message: "Die Dauer eines vorgeschalteten Wissenschaftsauftrags ist nicht verfügbar.", severity: .blocking)) }
    }
    if !concreteScienceJobs.isEmpty {
      totalSeconds = Self.saturatedAdd(totalSeconds, scienceSeconds)
      warnings.append(DomainWarning(code: "science.sequential-prerequisites", message: "Geplante Wissenschaftsaufträge werden konservativ nacheinander vor der Fertigung eingeplant; tatsächliche Slot-Belegung und Invention-Erfolge können abweichen.", severity: .information))
    }
    let configuredScheduling = context.productionBasis?.scheduling
    let productionMakespan = max(
      Self.slotMakespan(
        durations: manufacturingDurations,
        slots: configuredScheduling?.manufacturingSlots ?? 1
      ),
      Self.slotMakespan(
        durations: reactionDurations,
        slots: configuredScheduling?.reactionSlots ?? 1
      )
    )
    let makespan = Self.saturatedAdd(scienceSeconds, productionMakespan)
    if consolidatedJobs.count > 1 {
      warnings.append(
        DomainWarning(
          code: "industry.slot-estimated-makespan",
          message:
            "Makespan uses the configured manufacturing and reaction slot counts; actual character availability can change it.",
          severity: .information
        )
      )
    }

    var materialTypeIDs = Set(state.required.keys)
    materialTypeIDs.formUnion(state.toBuy.keys)
    materialTypeIDs.formUnion(state.stockUsed.keys)
    materialTypeIDs.formUnion(state.toProduce.keys)
    var materials: [MaterialRequirement] = []
    for typeID in materialTypeIDs {
      let resolvedName = try await context.catalog.typeName(id: typeID)
      let classification =
        try await context.catalog.industryClassification(
          productTypeID: typeID
        )
      let productionActivity =
        try await context.catalog.productionDefinition(
          productTypeID: typeID
        )?.activity.kind
      let productionAllowed =
        productionActivity != nil
        && productionActivity != .invention
        && !(context.productionBasis?.blacklist.blocks(
          typeName: resolvedName ?? "Type \(typeID)",
          classification: classification
        ) ?? false)
      let analysis: MaterialMakeOrBuyAnalysis?
      if productionAllowed,
        let definition = try await context.catalog.productionDefinition(
          productTypeID: typeID
        )
      {
        let requiredQuantity = state.required[typeID, default: 0]
        if let reusable = reusableMakeOrBuyAnalyses[typeID],
          reusable.requiredQuantity == requiredQuantity
        {
          analysis = reusable
        } else {
          analysis = try await makeOrBuyAnalysis(
            definition: definition,
            requiredQuantity: requiredQuantity,
            context: context,
            marketBook: mainMarketBook,
            systemIndexLookup: systemIndexLookup
          )
        }
      } else {
        analysis = nil
      }
      materials.append(
        MaterialRequirement(
          typeID: typeID,
          name: resolvedName ?? "Type \(typeID)",
          required: state.required[typeID, default: 0],
          fromStock: state.stockUsed[typeID, default: 0],
          toBuy: state.toBuy[typeID, default: 0],
          toProduce: state.toProduce[typeID, default: 0],
          quote: purchaseQuotes[typeID],
          stockQuote: stockQuotes[typeID],
          replacementQuote: replacementQuotes[typeID],
          procurement: state.procurement[typeID],
          sourceCategory: classification?.categoryName,
          sourceGroup: classification?.groupName,
          productionActivity: productionActivity,
          productionAllowed: productionAllowed,
          makeOrBuyAnalysis: analysis
        )
      )
    }
    materials.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name)
        == .orderedAscending
    }

    let directMineralRequirements = Dictionary(
      uniqueKeysWithValues: state.toBuy.compactMap { typeID, quantity in
        replacementQuotes[typeID] == nil ? nil : (typeID, quantity)
      }
    )
    var refiningOptimization = try await optimizeCompressedOreRefining(
      requirements: directMineralRequirements,
      directQuotes: replacementQuotes,
      context: context,
      marketBook: mainMarketBook,
      homeHub:
        context.productionBasis?.homeTradingLocation?.location
        ?? .legacy(
          name:
            context.productionBasis?.logistics.productionLocationName
            ?? "Home Hub"
        )
    )
    if let optimization = refiningOptimization {
      warnings.append(contentsOf: optimization.warnings)
    }
    var effectivePurchasedMaterialCost = purchasedMaterialCost
    var effectiveMaterialCost = directMaterialCost
    var refiningFee = 0.0
    var remainingDirectQuotes: [Int64: PriceQuote] = purchaseQuotes
    if let optimization = refiningOptimization,
      !optimization.purchases.isEmpty,
      stockMaterialCostComplete
    {
      var selectedPurchaseCost = 0.0
      var complete = true
      var selectedDirectQuotes: [Int64: PriceQuote] = [:]
      for (typeID, originalQuantity) in state.toBuy {
        let quantity =
          optimization.coveredMinerals[typeID] == nil
          ? originalQuantity
          : optimization.remainingDirectMinerals[typeID, default: 0]
        guard quantity > 0 else { continue }
        let quote = mainMarketBook.quote(
          typeID: typeID,
          quantity: quantity,
          scenario: .materialBuy
        )
        warnings.append(contentsOf: quote.warnings)
        guard let total = quote.total else {
          complete = false
          break
        }
        selectedPurchaseCost += total
        selectedDirectQuotes[typeID] = quote
      }
      if complete {
        for purchase in optimization.purchases {
          guard let total = purchase.purchaseQuote.total else {
            complete = false
            break
          }
          selectedPurchaseCost += total
          refiningFee += purchase.refiningFee
        }
      }
      let selectedMaterialCost =
        stockMaterialCost + selectedPurchaseCost
        + refiningFee
      if complete, selectedPurchaseCost.isFinite,
        selectedMaterialCost.isFinite,
        selectedPurchaseCost >= 0, selectedMaterialCost >= 0
      {
        effectivePurchasedMaterialCost = selectedPurchaseCost
        effectiveMaterialCost = selectedMaterialCost
        remainingDirectQuotes = selectedDirectQuotes
      } else {
        refiningOptimization = nil
        refiningFee = 0
      }
    }

    let installation = jobs.reduce(0) { $0 + $1.total }
    if !installation.isFinite || installation < 0 {
      installationCostComplete = false
    }
    let systemIndexCost = jobs.reduce(0) {
      $0
        + $1.estimatedItemValue * $1.systemCostIndex * $1.bonusMultiplier
    }
    let facilityTaxCost = jobs.reduce(0) {
      $0 + $1.estimatedItemValue * $1.facilityTax
    }
    let sccSurchargeCost = jobs.reduce(0) {
      $0 + $1.estimatedItemValue * $1.sccSurcharge
    }
    let alphaSurchargeCost = jobs.reduce(0) {
      $0 + $1.estimatedItemValue * $1.alphaSurcharge
    }
    if [systemIndexCost, facilityTaxCost, sccSurchargeCost, alphaSurchargeCost]
      .contains(where: { !$0.isFinite || $0 < 0 })
    {
      installationCostComplete = false
    }
    let acceptedInstallation =
      installationCostComplete ? installation : nil
    let manualBlueprintEntries: [BlueprintCostEntry] = requests.compactMap {
      request in
      guard let kind = request.blueprintKind,
        let amount = request.blueprintCostISK
      else { return nil }
      return BlueprintCostEntry(
        requestID: request.id,
        productName: request.productName,
        kind: kind,
        amount: amount,
        treatment: kind.costTreatment
      )
    }
    let producedBlueprintTypeIDs = Set(
      state.nodes.compactMap { node in
        node.action == .produce ? node.blueprintTypeID : nil
      }
    )
    let automaticallyCoveredRequestIDs = Set(
      state.nodes.compactMap { node -> UUID? in
        guard node.action == .produce,
          let requestID = node.topLevelRequestID,
          let blueprintTypeID = node.blueprintTypeID,
          context.blueprintCostAllocations[blueprintTypeID] != nil
        else { return nil }
        return requestID
      }
    )
    let automaticBlueprintEntries: [BlueprintCostEntry] =
      context.blueprintCostAllocations.values.filter {
        producedBlueprintTypeIDs.contains($0.blueprintTypeID)
      }.sorted {
        $0.blueprintTypeID < $1.blueprintTypeID
      }.map { allocation in
        BlueprintCostEntry(
          requestID: UUID(),
          productName: allocation.productName,
          kind: allocation.kind,
          amount: allocation.amount,
          treatment: allocation.source
        )
      }
    let blueprintEntries = manualBlueprintEntries + automaticBlueprintEntries
    let requestsWithoutBlueprintCost = requests.compactMap { request in
      request.blueprintCostISK == nil
        && !automaticallyCoveredRequestIDs.contains(request.id)
        ? request.id : nil
    }
    let manuallyCoveredRequestIDs = Set(
      requests.compactMap { request in
        request.blueprintCostISK == nil ? nil : request.id
      }
    )
    let manuallyCoveredBlueprintTypeIDs = Set(
      state.nodes.compactMap { node -> Int64? in
        guard node.action == .produce,
          let requestID = node.topLevelRequestID,
          manuallyCoveredRequestIDs.contains(requestID)
        else { return nil }
        return node.blueprintTypeID
      }
    )
    let resolvedBlueprintTypeIDs = Set(
      context.blueprintCostAllocations.keys
    ).union(manuallyCoveredBlueprintTypeIDs)
    let unresolvedBlueprintTypeIDs = producedBlueprintTypeIDs.subtracting(
      resolvedBlueprintTypeIDs
    )
    let knownBlueprintCost = blueprintEntries.reduce(0) { $0 + $1.amount }
    let blueprintCost: Double? =
      context.requiresCompleteBlueprintCosts
        && !unresolvedBlueprintTypeIDs.isEmpty
      ? nil : knownBlueprintCost
    let blueprintCosts = BlueprintCostBreakdown(
      entries: blueprintEntries,
      requestsWithoutEnteredCost: requestsWithoutBlueprintCost,
      total: knownBlueprintCost
    )
    if !requestsWithoutBlueprintCost.isEmpty {
      warnings.append(
        DomainWarning(
          code: "industry.blueprint-cost-not-included",
          message:
            "\(requestsWithoutBlueprintCost.count) top-level production \(requestsWithoutBlueprintCost.count == 1 ? "line has" : "lines have") no entered BPC/BPO cost; the total excludes those blueprint costs.",
          severity: .information
        )
      )
    }
    if context.requiresCompleteBlueprintCosts,
      !unresolvedBlueprintTypeIDs.isEmpty
    {
      warnings.append(
        DomainWarning(
          code: "industry.blueprint-cost-unresolved",
          message:
            "\(unresolvedBlueprintTypeIDs.count) produced Blueprint source \(unresolvedBlueprintTypeIDs.count == 1 ? "has" : "have") no attributable acquisition or allocation cost. Total production cost and profit remain unavailable.",
          severity: .warning
        )
      )
    }
    let configuredHomeHub =
      context.productionBasis?.homeTradingLocation?.location
      ?? .legacy(
        name:
          context.productionBasis?.logistics.productionLocationName
          ?? "Home Hub"
      )
    let configuredCoalitionHub =
      context.productionBasis?.coalitionTradingLocation?.location
    let directInboundLogistics = try await logisticsBreakdown(
      configuration: context.productionBasis?.logistics,
      materials: materials,
      requests: requests,
      nodes: state.nodes,
      mainHub: context.defaultPurchaseLocation,
      homeHub: configuredHomeHub,
      marketBook: mainMarketBook,
      includeInboundMaterials:
        context.productionBasis?.logistics.includeInboundMaterials == true,
      includeOutboundProducts: false,
      catalog: context.catalog,
      refiningOptimization: nil
    )
    var inboundLogistics = directInboundLogistics
    if let optimization = refiningOptimization,
      !optimization.purchases.isEmpty
    {
      let optimizedInbound = try await logisticsBreakdown(
        configuration: context.productionBasis?.logistics,
        materials: materials,
        requests: requests,
        nodes: state.nodes,
        mainHub: context.defaultPurchaseLocation,
        homeHub: configuredHomeHub,
        marketBook: mainMarketBook,
        includeInboundMaterials:
          context.productionBasis?.logistics.includeInboundMaterials == true,
        includeOutboundProducts: false,
        catalog: context.catalog,
        refiningOptimization: optimization
      )
      if let directCost = directInboundLogistics.cost,
        let optimizedCost = optimizedInbound.cost,
        materialCostComplete,
        directMaterialCost + directCost
          > effectiveMaterialCost + optimizedCost
      {
        inboundLogistics = optimizedInbound
      } else {
        refiningOptimization = nil
        refiningFee = 0
        effectivePurchasedMaterialCost = purchasedMaterialCost
        effectiveMaterialCost = directMaterialCost
        remainingDirectQuotes = purchaseQuotes
        warnings.append(
          DomainWarning(
            code: "refining.no-full-route-savings",
            message:
              "After complete courier-contract splitting and rounding, compressed ore was not cheaper than direct mineral transport. The direct mineral route was preserved.",
            severity: .information
          )
        )
      }
    }
    warnings.append(
      contentsOf: inboundLogistics.warnings.filter {
        $0.code != "logistics.contracts-split"
      }
    )
    let restrictedCapitalNames = state.nodes.filter {
      $0.action == .produce && $0.topLevelRequestID != nil
        && HighSecurityCapitalTransferPolicy.isRestrictedCapital($0)
    }.map(\.name).sorted()
    let outboundLogistics:
      (
        breakdown: LogisticsCostBreakdown?,
        cost: Double?,
        warnings: [DomainWarning]
      )
    if restrictedCapitalNames.isEmpty {
      outboundLogistics = try await logisticsBreakdown(
        configuration: context.productionBasis?.logistics,
        materials: materials,
        requests: requests,
        nodes: state.nodes,
        mainHub: context.defaultPurchaseLocation,
        homeHub: configuredHomeHub,
        marketBook: mainMarketBook,
        includeInboundMaterials: false,
        // The configured Main Hub is a standard high-security NPC hub.
        includeOutboundProducts: true,
        catalog: context.catalog
      )
    } else {
      outboundLogistics = (
        nil,
        nil,
        [
          DomainWarning(
            code: "logistics.capital-highsec-prohibited",
            message:
              "The Main Hub sale is unavailable because the following capital production cannot enter or change ownership in high-security space: \(restrictedCapitalNames.joined(separator: ", ")). Home and Coalition Hub strategies remain independent.",
            severity: .warning
          )
        ]
      )
    }
    for warning in outboundLogistics.warnings
    where warning.code != "logistics.contracts-split"
      && !warnings.contains(where: {
        $0.code == warning.code && $0.message == warning.message
      })
    {
      warnings.append(warning)
    }
    let coalitionMarketBook = context.coalitionMarket.map {
      $0.id == context.market.id
        ? mainMarketBook : PreparedMarketOrderBook(snapshot: $0)
    }
    var coalitionOutboundLogistics:
      (
        breakdown: LogisticsCostBreakdown?,
        cost: Double?,
        warnings: [DomainWarning]
      ) = (nil, nil, [])
    var coalitionJumpFreighterBreakdown: JumpFreighterCostBreakdown?
    var coalitionCapitalSelfJumpBreakdown: CapitalSelfJumpCostBreakdown?
    var coalitionJumpFreighterStatus: LogisticsRouteStatus?
    var coalitionJumpFreighterWarnings: [DomainWarning] = []
    let jumpFreighterConfiguration =
      context.productionBasis?.logistics.jumpFreighter
    let selfJumpingCapitals = selfJumpingCapitalProducts(
      requests: requests,
      nodes: state.nodes
    )
    if let configuredCoalitionHub,
      jumpFreighterConfiguration?.isEnabled == true,
      !configuredHomeHub.representsSameLocation(as: configuredCoalitionHub),
      let jumpFreighterConfiguration
    {
      let cargo = try await outboundJumpFreighterCargo(
        requests: requests,
        nodes: state.nodes,
        catalog: context.catalog
      )
      let cargoResult:
        (
          breakdown: JumpFreighterCostBreakdown?,
          status: LogisticsRouteStatus,
          warnings: [DomainWarning]
        )
      if cargo.isEmpty {
        cargoResult = (nil, .notRequired, [])
      } else if context.jumpFreighterRoute?.state == .fresh,
        let route = context.jumpFreighterRoute?.value
      {
        let result = JumpFreighterLogisticsCalculator.calculate(
          configuration: jumpFreighterConfiguration,
          route: route,
          cargo: cargo,
          mainHubMarket: mainMarketBook
        )
        cargoResult = result
      } else {
        var routeWarnings = context.jumpFreighterRouteWarnings
        if routeWarnings.isEmpty {
          routeWarnings = [
            DomainWarning(
              code: "jump-freighter.route-unavailable",
              message:
                "The current DOTLAN Jump Freighter route is unavailable. Coalition Hub transport is not treated as free.",
              severity: .blocking,
              source: context.jumpFreighterRoute?.source
            )
          ]
        }
        cargoResult = (nil, .unavailable, routeWarnings)
      }
      let capitalResult = CapitalSelfJumpCalculator.calculate(
        products: selfJumpingCapitals,
        routes: context.capitalJumpRoutes,
        routeWarnings: context.capitalJumpRouteWarnings,
        mainHubMarket: mainMarketBook
      )
      coalitionJumpFreighterBreakdown = cargoResult.breakdown
      coalitionCapitalSelfJumpBreakdown = capitalResult.breakdown
      coalitionJumpFreighterWarnings =
        cargoResult.warnings + capitalResult.warnings
      let componentStatuses = [cargoResult.status, capitalResult.status]
      if componentStatuses.contains(.unavailable) {
        coalitionJumpFreighterStatus = .unavailable
      } else if componentStatuses.contains(.manualTransferRequired) {
        coalitionJumpFreighterStatus = .manualTransferRequired
      } else if componentStatuses.allSatisfy({ $0 == .notRequired }) {
        coalitionJumpFreighterStatus = .notRequired
      } else {
        coalitionJumpFreighterStatus = .calculated
      }
      for warning in coalitionJumpFreighterWarnings
      where !warnings.contains(where: {
        $0.code == warning.code && $0.message == warning.message
      }) {
        warnings.append(warning)
      }
    } else if let configuredCoalitionHub, let coalitionMarketBook,
      selfJumpingCapitals.isEmpty
    {
      coalitionOutboundLogistics = try await logisticsBreakdown(
        configuration: context.productionBasis?.logistics,
        materials: materials,
        requests: requests,
        nodes: state.nodes,
        mainHub: configuredCoalitionHub,
        homeHub: configuredHomeHub,
        marketBook: coalitionMarketBook,
        includeInboundMaterials: false,
        includeOutboundProducts: true,
        catalog: context.catalog
      )
      for warning in coalitionOutboundLogistics.warnings
      where warning.code != "logistics.contracts-split"
        && !warnings.contains(where: {
          $0.code == warning.code && $0.message == warning.message
        })
      {
        warnings.append(warning)
      }
    } else if configuredCoalitionHub != nil, !selfJumpingCapitals.isEmpty {
      coalitionOutboundLogistics = (
        nil,
        nil,
        [
          DomainWarning(
            code: "capital-self-jump.disabled",
            message:
              "At least one produced capital must self-jump from the Home Hub to the Coalition Hub. Enable jump logistics to calculate its DOTLAN route and fuel; the hull is not treated as courier cargo.",
            severity: .blocking
          )
        ]
      )
      warnings.append(contentsOf: coalitionOutboundLogistics.warnings)
    }
    let inboundRequiresManualTransfer = inboundLogistics.warnings.contains {
      $0.code == "logistics.single-item-volume-exceeded"
    }
    let logisticsCost =
      inboundRequiresManualTransfer ? nil : inboundLogistics.cost
    let inboundAssessment = logisticsRouteAssessment(
      result: inboundLogistics,
      origin: context.defaultPurchaseLocation.name,
      destination: configuredHomeHub.name
    )
    let mainOutboundAssessment = logisticsRouteAssessment(
      result: outboundLogistics,
      origin: configuredHomeHub.name,
      destination: context.defaultPurchaseLocation.name,
      prohibitedReason: restrictedCapitalNames.isEmpty
        ? nil
        : "Capital production restricted to security 0.4 or lower cannot be transferred to or sold at the high-security Main Hub."
    )
    let coalitionOutboundAssessment = configuredCoalitionHub.map { hub in
      if configuredHomeHub.representsSameLocation(as: hub) {
        return LogisticsRouteAssessment(
          status: .notRequired,
          origin: configuredHomeHub.name,
          destination: hub.name,
          cost: 0,
          reason: "Home Hub and Coalition Hub are the same location."
        )
      }
      if jumpFreighterConfiguration?.isEnabled == true {
        let reason = coalitionJumpFreighterWarnings.map(\.message)
          .joined(separator: " ")
        let status = coalitionJumpFreighterStatus ?? .unavailable
        return LogisticsRouteAssessment(
          status: status,
          origin: configuredHomeHub.name,
          destination: hub.name,
          jumpFreighter: coalitionJumpFreighterBreakdown,
          selfJumpingCapitals: coalitionCapitalSelfJumpBreakdown,
          cost:
            status == .unavailable
            ? nil
            : (coalitionJumpFreighterBreakdown?.totalCost ?? 0)
              + (coalitionCapitalSelfJumpBreakdown?.totalCost ?? 0),
          reason:
            reason.isEmpty
            ? (status == .calculated
              ? "Jump Freighter cargo flights and self-propelled capital jumps are valued with the arithmetic mean of the four current Main Hub isotope sell prices."
              : "The jump-logistics route cost is unavailable.")
            : reason
        )
      }
      return logisticsRouteAssessment(
        result: coalitionOutboundLogistics,
        origin: configuredHomeHub.name,
        destination: hub.name
      )
    }
    let acceptedMaterialCost =
      materialCostComplete ? effectiveMaterialCost : nil
    let totalCost = IndustryCostBreakdown.total(
      materialCost: acceptedMaterialCost,
      blueprintCost: blueprintCost,
      installationCost: acceptedInstallation,
      logisticsCost: logisticsCost
    )
    let costBreakdown = IndustryCostBreakdown(
      materialCost: acceptedMaterialCost,
      purchasedMaterialCost:
        purchasedMaterialCostComplete
        ? effectivePurchasedMaterialCost : nil,
      stockMaterialCost:
        stockMaterialCostComplete ? stockMaterialCost : nil,
      refiningCost:
        refiningOptimization?.purchases.isEmpty == false ? refiningFee : nil,
      blueprintCosts: blueprintCosts,
      systemIndexCost:
        installationCostComplete ? systemIndexCost : nil,
      facilityTax:
        installationCostComplete ? facilityTaxCost : nil,
      sccSurcharge:
        installationCostComplete ? sccSurchargeCost : nil,
      alphaSurcharge:
        installationCostComplete ? alphaSurchargeCost : nil,
      installationCost: acceptedInstallation,
      logistics:
        inboundRequiresManualTransfer ? nil : inboundLogistics.breakdown,
      logisticsCost: logisticsCost,
      totalProductionCost: totalCost
    )
    let productionCostBeforeLogistics =
      costBreakdown.productionCostBeforeLogistics
    let mainScenarioCost = Self.knownScenarioCost(
      productionCostBeforeLogistics: productionCostBeforeLogistics,
      routes: [inboundAssessment, mainOutboundAssessment]
    )
    var producedNodeByRequest: [UUID: PlanNode] = [:]
    producedNodeByRequest.reserveCapacity(requests.count)
    for node in state.nodes where node.action == .produce {
      guard let requestID = node.topLevelRequestID else { continue }
      producedNodeByRequest[requestID] = node
    }
    let mainSaleResults = saleScenarios(
      requests: requests,
      producedNodeByRequest: producedNodeByRequest,
      marketBook: mainMarketBook,
      marketLocation: context.defaultPurchaseLocation,
      totalCost: mainScenarioCost,
      tax: context.salesTaxRate,
      broker: context.brokerFeeRate,
      publicContractFeeRate:
        context.productionBasis?.mainTradingLocation?.publicContractFeeRate,
      contractReferences: context.mainContractReferences,
      inboundLogisticsAssessment: inboundAssessment,
      outboundLogisticsAssessment: mainOutboundAssessment,
      marketSaleProhibitedReason: restrictedCapitalNames.isEmpty
        ? nil
        : mainOutboundAssessment.reason,
      outboundLogistics: outboundLogistics.breakdown,
      outboundLogisticsCost: outboundLogistics.cost
    )
    let homeSaleResults = context.productionBasis?.homeTradingLocation.map {
      _ in
      let homeMarketBook = context.homeMarket.map { homeMarket in
        homeMarket.id == context.market.id
          ? mainMarketBook : PreparedMarketOrderBook(snapshot: homeMarket)
      }
      return saleScenarios(
        requests: requests,
        producedNodeByRequest: producedNodeByRequest,
        marketBook: homeMarketBook,
        marketLocation: configuredHomeHub,
        totalCost: Self.knownScenarioCost(
          productionCostBeforeLogistics: productionCostBeforeLogistics,
          routes: [
            inboundAssessment,
            LogisticsRouteAssessment(
              status: .notRequired,
              origin: configuredHomeHub.name,
              destination: configuredHomeHub.name,
              cost: 0,
              reason: "The finished product is sold where production is based."
            ),
          ]
        ),
        tax: context.homeSalesTaxRate,
        broker: context.homeBrokerFeeRate,
        publicContractFeeRate:
          context.productionBasis?.homeTradingLocation?.publicContractFeeRate,
        contractReferences: context.homeContractReferences,
        inboundLogisticsAssessment: inboundAssessment,
        outboundLogisticsAssessment: LogisticsRouteAssessment(
          status: .notRequired,
          origin: configuredHomeHub.name,
          destination: configuredHomeHub.name,
          cost: 0,
          reason: "The finished product is sold where production is based."
        ),
        outboundLogistics: nil,
        outboundLogisticsCost: 0
      )
    }
    let coalitionSaleResults = configuredCoalitionHub.map {
      configuredCoalitionHub in
      let marketBook = context.coalitionMarket.map { coalitionMarket in
        coalitionMarket.id == context.market.id
          ? mainMarketBook : PreparedMarketOrderBook(snapshot: coalitionMarket)
      }
      return saleScenarios(
        requests: requests,
        producedNodeByRequest: producedNodeByRequest,
        marketBook: marketBook,
        marketLocation: configuredCoalitionHub,
        totalCost: Self.knownScenarioCost(
          productionCostBeforeLogistics: productionCostBeforeLogistics,
          routes: [inboundAssessment, coalitionOutboundAssessment]
        ),
        tax: context.coalitionSalesTaxRate,
        broker: context.coalitionBrokerFeeRate,
        publicContractFeeRate:
          context.productionBasis?.coalitionTradingLocation?
          .publicContractFeeRate,
        contractReferences: context.coalitionContractReferences,
        inboundLogisticsAssessment: inboundAssessment,
        outboundLogisticsAssessment: coalitionOutboundAssessment,
        outboundLogistics:
          jumpFreighterConfiguration?.isEnabled == true
          ? nil : coalitionOutboundLogistics.breakdown,
        outboundLogisticsCost: coalitionOutboundAssessment?.cost
      )
    }
    let source =
      context.assetSource
      ?? StockSource(
        kind: .manual,
        reference: "manual"
      )
    let allocations = state.stockUsed.map {
      StockAllocation(typeID: $0.key, quantity: $0.value, source: source)
    }
    let priceDate =
      [
        context.market.capturedAt,
        context.homeMarket?.capturedAt,
        context.coalitionMarket?.capturedAt,
        context.mainContractReferences?.capturedAt,
        context.homeContractReferences?.capturedAt,
        context.coalitionContractReferences?.capturedAt,
      ].compactMap { $0 }.max() ?? context.market.capturedAt
    var marketSnapshotIDs = [context.market.id]
    if let homeMarketID = context.homeMarket?.id,
      homeMarketID != context.market.id
    {
      marketSnapshotIDs.append(homeMarketID)
    }
    if let coalitionMarketID = context.coalitionMarket?.id,
      !marketSnapshotIDs.contains(coalitionMarketID)
    {
      marketSnapshotIDs.append(coalitionMarketID)
    }
    for contractSnapshotID in [
      context.mainContractReferences?.id,
      context.homeContractReferences?.id,
      context.coalitionContractReferences?.id,
    ].compactMap({ $0 }) where !marketSnapshotIDs.contains(contractSnapshotID) {
      marketSnapshotIDs.append(contractSnapshotID)
    }
    if let jumpRouteSnapshotID = context.jumpFreighterRoute?.source.snapshotID,
      !marketSnapshotIDs.contains(jumpRouteSnapshotID)
    {
      marketSnapshotIDs.append(jumpRouteSnapshotID)
    }
    for snapshotID in context.capitalJumpRoutes.values.compactMap(
      { $0.source.snapshotID }
    ) where !marketSnapshotIDs.contains(snapshotID) {
      marketSnapshotIDs.append(snapshotID)
    }
    var compressedOreRefiningPlan: CompressedOreRefiningPlan?
    if let optimization = refiningOptimization,
      !optimization.purchases.isEmpty,
      let directInboundCost = directInboundLogistics.cost,
      let selectedInboundCost = inboundLogistics.cost
    {
      let directLandedCost = directMaterialCost + directInboundCost
      let selectedLandedCost = effectiveMaterialCost + selectedInboundCost
      let savings = directLandedCost - selectedLandedCost
      if savings.isFinite, savings > 0 {
        compressedOreRefiningPlan = CompressedOreRefiningPlan(
          purchases: optimization.purchases,
          coveredMinerals: optimization.coveredMinerals,
          remainingDirectMinerals:
            optimization.remainingDirectMinerals,
          remainingDirectQuotes: remainingDirectQuotes,
          orePurchaseCost: optimization.purchases.compactMap {
            $0.purchaseQuote.total
          }.reduce(0, +),
          refiningFee: refiningFee,
          directLandedCost: directLandedCost,
          selectedLandedCost: selectedLandedCost,
          savings: savings
        )
        warnings.append(
          DomainWarning(
            code: "refining.compressed-ore-selected",
            message:
              "Compressed ore was selected for part of the mineral demand because complete purchase, Reprocessing fee and inbound logistics are cheaper by \(savings.formatted(.currency(code: "ISK"))).",
            severity: .information
          )
        )
      }
    }
    let calculatedJobsBySupplyID = jobs.reduce(
      into: [UUID: IndustryJobCost](),
      { result, job in
        if let id = job.blueprintSupplyJobID { result[id] = job }
      }
    )
    let definitionsBySupplyID = consolidatedJobs.reduce(
      into: [UUID: JobDefinition](),
      { result, job in
        if let id = job.blueprintSupplyJobID { result[id] = job }
      }
    )
    let persistedBlueprintSupplyPlans = context.blueprintSupplyPlans.values
      .map { supplyPlan in
        let manufacturingJobs = supplyPlan.manufacturingJobs.map { supplyJob in
          guard let definition = definitionsBySupplyID[supplyJob.id] else {
            return supplyJob
          }
          let calculated = calculatedJobsBySupplyID[supplyJob.id]
          let materialMultiplier =
            definition.facilitySelection?.materialMultiplier
            ?? context.manufacturingProfile.effectiveMaterialMultiplier
          let materials = definition.definition.activity.materials.map {
            BlueprintMaterial(
              typeID: $0.typeID,
              quantity: Self.manufacturingMaterialQuantity(
                baseQuantity: $0.quantity,
                runs: definition.runs,
                materialEfficiency: definition.me,
                facilityMultiplier: materialMultiplier
              )
            )
          }
          return BlueprintManufacturingJob(
            id: supplyJob.id,
            demandID: supplyJob.demandID,
            allocation: supplyJob.allocation,
            blueprintTypeID: supplyJob.blueprintTypeID,
            productTypeID: supplyJob.productTypeID,
            runs: definition.runs,
            outputQuantity: calculated?.outputQuantity
              ?? supplyJob.outputQuantity,
            materials: materials,
            durationSeconds: calculated?.durationSeconds,
            installationCost: calculated?.total
          )
        }
        return BlueprintSupplyPlan(
          id: supplyPlan.id,
          planID: supplyPlan.planID,
          blueprintTypeID: supplyPlan.blueprintTypeID,
          productTypeID: supplyPlan.productTypeID,
          productName: supplyPlan.productName,
          requiredRuns: supplyPlan.requiredRuns,
          manufacturingJobs: manufacturingJobs,
          scienceJobs: supplyPlan.scienceJobs,
          transfers: supplyPlan.transfers,
          reservations: supplyPlan.reservations,
          capitalPurchaseCost: supplyPlan.capitalPurchaseCost,
          batchAllocationCost: supplyPlan.batchAllocationCost,
          expectedInventionCost: supplyPlan.expectedInventionCost,
          confidencePlanCost: supplyPlan.confidencePlanCost,
          warnings: supplyPlan.warnings,
          sourceSnapshotIDs: supplyPlan.sourceSnapshotIDs,
          ruleVersion: supplyPlan.ruleVersion
        )
      }.sorted {
        if $0.blueprintTypeID != $1.blueprintTypeID {
          return $0.blueprintTypeID < $1.blueprintTypeID
        }
        return $0.id.uuidString < $1.id.uuidString
      }
    return IndustryPlanSnapshot(
      id: context.planID ?? UUID(),
      createdAt: .now,
      requests: requests,
      nodes: state.nodes,
      materials: materials,
      stockAllocations: allocations,
      jobs: jobs,
      materialCost: acceptedMaterialCost,
      installationCost: acceptedInstallation,
      costBreakdown: costBreakdown,
      compressedOreRefining: compressedOreRefiningPlan,
      blueprintSupplyPlans:
        persistedBlueprintSupplyPlans,
      immediateSale: mainSaleResults.0,
      listedSale: mainSaleResults.1,
      mainContractSale: mainSaleResults.2,
      homeImmediateSale: homeSaleResults?.0,
      homeListedSale: homeSaleResults?.1,
      homeContractSale: homeSaleResults?.2,
      coalitionImmediateSale: coalitionSaleResults?.0,
      coalitionListedSale: coalitionSaleResults?.1,
      coalitionContractSale: coalitionSaleResults?.2,
      totalJobSeconds: totalSeconds,
      makespanSeconds: makespan,
      warnings: warnings,
      explanations: state.explanations,
      provenance: PlanProvenance(
        sdeBuild: context.sdeBuild,
        esiCompatibilityDate: EVEConstants.esiCompatibilityDate,
        snapshotIDs: context.snapshotIDs + marketSnapshotIDs,
        priceTimestamp: priceDate,
        ruleVersion: IndustryRuleSet.current.version
      )
    )
  }

  private func saleScenarios(
    requests: [ProductionRequestLine],
    producedNodeByRequest: [UUID: PlanNode],
    marketBook: PreparedMarketOrderBook?,
    marketLocation: ProcurementLocation,
    totalCost: Double?,
    tax: Double?,
    broker: Double?,
    publicContractFeeRate: Double?,
    contractReferences: PublicContractReferenceSnapshot?,
    inboundLogisticsAssessment: LogisticsRouteAssessment,
    outboundLogisticsAssessment: LogisticsRouteAssessment?,
    marketSaleProhibitedReason: String? = nil,
    outboundLogistics: LogisticsCostBreakdown?,
    outboundLogisticsCost: Double?
  ) -> (SaleScenarioResult, SaleScenarioResult, SaleScenarioResult) {
    var immediateQuotes: [PriceQuote] = []
    var listedQuotes: [PriceQuote] = []
    var contractSaleQuotes: [PriceQuote] = []
    for request in requests {
      guard let node = producedNodeByRequest[request.id] else { continue }
      if let marketBook {
        immediateQuotes.append(
          marketBook.quote(
            typeID: node.typeID,
            quantity: node.requiredQuantity,
            scenario: .immediateSale
          )
        )
        listedQuotes.append(
          marketBook.quote(
            typeID: node.typeID,
            quantity: node.requiredQuantity,
            scenario: .listedSale,
            salesTaxRate: tax,
            brokerFeeRate: broker
          )
        )
      } else {
        immediateQuotes.append(
          unavailableMarketQuote(
            typeID: node.typeID,
            quantity: node.requiredQuantity,
            scenario: .immediateSale
          )
        )
        listedQuotes.append(
          unavailableMarketQuote(
            typeID: node.typeID,
            quantity: node.requiredQuantity,
            scenario: .listedSale
          )
        )
      }
      contractSaleQuotes.append(
        publicContractQuote(
          typeID: node.typeID,
          quantity: node.requiredQuantity,
          snapshot: contractReferences,
          scenario: .contractSale
        )
      )
    }
    let publicContractFee: Double? = publicContractFeeRate.flatMap { rate in
      guard rate.isFinite, rate >= 0, rate < 1 else { return nil }
      let gross = contractSaleQuotes.compactMap(\.total)
      guard gross.count == contractSaleQuotes.count else { return nil }
      let fee = gross.reduce(0, +) * rate
      return fee.isFinite && fee >= 0 ? fee : nil
    }
    if let marketSaleProhibitedReason {
      let unavailable = prohibitedSaleResult(
        scenario: .listedSale,
        marketLocation: marketLocation,
        reason: marketSaleProhibitedReason,
        salesTaxRate: tax,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment
      )
      return (
        prohibitedSaleResult(
          scenario: .immediateSale,
          marketLocation: marketLocation,
          reason: marketSaleProhibitedReason,
          salesTaxRate: tax,
          inboundLogisticsAssessment: inboundLogisticsAssessment,
          outboundLogisticsAssessment: outboundLogisticsAssessment
        ),
        unavailable,
        prohibitedSaleResult(
          scenario: .contractSale,
          marketLocation: marketLocation,
          reason: marketSaleProhibitedReason,
          salesTaxRate: 0,
          inboundLogisticsAssessment: inboundLogisticsAssessment,
          outboundLogisticsAssessment: outboundLogisticsAssessment
        )
      )
    }
    return (
      result(
        scenario: .immediateSale,
        quotes: immediateQuotes,
        marketLocation: marketLocation,
        totalCost: totalCost,
        salesTaxRate: tax,
        brokerFeeRate: 0,
        contractFee: 0,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost
      ),
      result(
        scenario: .listedSale,
        quotes: listedQuotes,
        marketLocation: marketLocation,
        totalCost: totalCost,
        salesTaxRate: tax,
        brokerFeeRate: broker,
        contractFee: 0,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost
      ),
      result(
        scenario: .contractSale,
        quotes: contractSaleQuotes,
        marketLocation: marketLocation,
        totalCost: totalCost,
        salesTaxRate: 0,
        brokerFeeRate: 0,
        contractFee: publicContractFee,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost
      )
    )
  }

  func publicContractQuote(
    typeID: Int64,
    quantity: Int64,
    snapshot: PublicContractReferenceSnapshot?,
    scenario: PriceScenario
  ) -> PriceQuote {
    let capturedAt = snapshot?.capturedAt ?? .now
    let source =
      snapshot?.source
      ?? SourceIdentity(
        provider: "ESI Public Contracts",
        version: PublicContractReferenceRule.ruleVersion,
        capturedAt: capturedAt
      )
    func unavailable(_ code: String, _ message: String) -> PriceQuote {
      PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: nil,
        weightedUnitPrice: nil,
        filledQuantity: 0,
        capturedAt: capturedAt,
        source: source,
        warnings: [
          DomainWarning(code: code, message: message, severity: .warning)
        ]
      )
    }
    guard quantity > 0 else {
      return unavailable(
        "contracts.invalid-quantity",
        "The public-contract quantity is invalid."
      )
    }
    guard let snapshot else {
      return unavailable(
        "contracts.reference-unavailable",
        "A complete Public Contracts reference snapshot for the configured comparison regions is unavailable."
      )
    }
    guard let reference = snapshot.prices[typeID] else {
      if !snapshot.hasCompleteSearchCoverage {
        return unavailable(
          "contracts.reference-partial",
          "The Public Contracts index is still updating or incomplete and no comparable offer for this product has been observed."
        )
      }
      return unavailable(
        "contracts.no-comparable-offer",
        "No single-type public Item Exchange offer without requested items was found in the configured comparison regions."
      )
    }
    let total = reference.unitPrice * Double(quantity)
    guard total.isFinite, total >= 0 else {
      return unavailable(
        "contracts.invalid-reference-price",
        "The Public Contracts reference price exceeded safe numeric limits."
      )
    }
    var referenceWarnings: [DomainWarning] = []
    if !snapshot.hasCompleteSearchCoverage {
      referenceWarnings.append(
        DomainWarning(
          code: "contracts.reference-provisional",
          message:
            "The Public Contracts index is still updating or incomplete. This estimate uses the lowest comparable offer currently observed and is not claimed as the complete universe-wide minimum.",
          severity: .warning
        )
      )
    }
    let quantityWarning: [DomainWarning] =
      reference.contractQuantity == quantity
      ? []
      : [
        DomainWarning(
          code: "contracts.reference-quantity-normalized",
          message:
            "The lowest comparable public contract offers \(reference.contractQuantity.formatted()) units; its per-unit price is applied to the planned \(quantity.formatted()) units as a benchmark.",
          severity: .information
        )
      ]
    return PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: total,
      weightedUnitPrice: reference.unitPrice,
      filledQuantity: quantity,
      capturedAt: snapshot.capturedAt,
      source: snapshot.source,
      warnings: referenceWarnings + quantityWarning
    )
  }

  private func unavailableMarketQuote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario
  ) -> PriceQuote {
    let capturedAt = Date.now
    return PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: nil,
      weightedUnitPrice: nil,
      filledQuantity: 0,
      capturedAt: capturedAt,
      source: SourceIdentity(
        provider: "ESI Market",
        version: EVEConstants.esiCompatibilityDate,
        capturedAt: capturedAt
      ),
      warnings: [
        DomainWarning(
          code: "market.snapshot-unavailable",
          message: "The exact-hub market snapshot is unavailable.",
          severity: .warning
        )
      ]
    )
  }

  private func prohibitedSaleResult(
    scenario: PriceScenario,
    marketLocation: ProcurementLocation,
    reason: String,
    salesTaxRate: Double?,
    inboundLogisticsAssessment: LogisticsRouteAssessment,
    outboundLogisticsAssessment: LogisticsRouteAssessment?
  ) -> SaleScenarioResult {
    SaleScenarioResult(
      scenario: scenario,
      marketLocation: marketLocation,
      salesTaxRate: salesTaxRate,
      salesTax: nil,
      brokerFeeRate: nil,
      brokerFeeIsApplicable: false,
      brokerFee: nil,
      contractFee: nil,
      inboundLogisticsAssessment: inboundLogisticsAssessment,
      outboundLogisticsAssessment:
        outboundLogisticsAssessment
        ?? LogisticsRouteAssessment(
          status: .prohibited,
          origin: inboundLogisticsAssessment.destination,
          destination: marketLocation.name,
          reason: reason
        ),
      grossOrNetRevenue: nil,
      profit: nil,
      margin: nil,
      roi: nil,
      quotes: []
    )
  }

  private func logisticsRouteAssessment(
    result: (
      breakdown: LogisticsCostBreakdown?,
      cost: Double?,
      warnings: [DomainWarning]
    ),
    origin: String,
    destination: String,
    prohibitedReason: String? = nil
  ) -> LogisticsRouteAssessment {
    if let prohibitedReason {
      return LogisticsRouteAssessment(
        status: .prohibited,
        origin: origin,
        destination: destination,
        reason: prohibitedReason
      )
    }
    let reason = result.warnings.filter {
      $0.code != "logistics.contracts-split"
    }.map(\.message).joined(separator: " ")
    if result.warnings.contains(where: {
      $0.code == "logistics.single-item-volume-exceeded"
    }) {
      return LogisticsRouteAssessment(
        status: .manualTransferRequired,
        origin: origin,
        destination: destination,
        breakdown: result.breakdown,
        cost: result.cost,
        reason:
          reason.isEmpty
          ? "The cargo does not fit into the configured courier-contract volume and requires a manual transfer plan."
          : reason
      )
    }
    guard let cost = result.cost else {
      return LogisticsRouteAssessment(
        status: .unavailable,
        origin: origin,
        destination: destination,
        reason:
          reason.isEmpty ? "The route cost is unavailable." : reason
      )
    }
    let status: LogisticsRouteStatus =
      cost == 0 && (result.breakdown?.legs.isEmpty ?? true)
      ? .notRequired : .calculated
    return LogisticsRouteAssessment(
      status: status,
      origin: origin,
      destination: destination,
      breakdown: result.breakdown,
      cost: cost,
      reason: reason.isEmpty ? nil : reason
    )
  }

  private func result(
    scenario: PriceScenario,
    quotes: [PriceQuote],
    marketLocation: ProcurementLocation,
    totalCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    contractFee: Double?,
    inboundLogisticsAssessment: LogisticsRouteAssessment?,
    outboundLogisticsAssessment: LogisticsRouteAssessment?,
    outboundLogistics: LogisticsCostBreakdown?,
    outboundLogisticsCost: Double?
  ) -> SaleScenarioResult {
    let totals = quotes.compactMap(\.total)
    guard totals.count == quotes.count else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: nil,
        salesTaxRate: salesTaxRate,
        salesTax: nil,
        brokerFeeRate: brokerFeeRate,
        brokerFeeIsApplicable: scenario == .listedSale,
        brokerFee: nil,
        contractFee: nil,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost,
        totalCost: totalCost,
        grossOrNetRevenue: nil,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: quotes
      )
    }
    let quotedRevenue = totals.reduce(0, +)
    guard quotedRevenue.isFinite, quotedRevenue >= 0,
      let salesTaxRate,
      let brokerFeeRate,
      salesTaxRate.isFinite,
      brokerFeeRate.isFinite,
      salesTaxRate >= 0,
      brokerFeeRate >= 0,
      salesTaxRate + brokerFeeRate < 1,
      contractFee == nil
        || (contractFee?.isFinite == true && (contractFee ?? -1) >= 0)
    else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue:
          scenario == .immediateSale || scenario == .contractSale
          ? quotedRevenue : nil,
        salesTaxRate: salesTaxRate,
        salesTax: scenario == .contractSale ? 0 : nil,
        brokerFeeRate: brokerFeeRate,
        brokerFeeIsApplicable: scenario == .listedSale,
        brokerFee:
          scenario == .immediateSale || scenario == .contractSale ? 0 : nil,
        contractFee: nil,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost,
        totalCost: totalCost,
        grossOrNetRevenue: nil,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: quotes
      )
    }
    let grossRevenue =
      scenario == .listedSale
      ? quotedRevenue / (1 - salesTaxRate - brokerFeeRate)
      : quotedRevenue
    let salesTax = grossRevenue * salesTaxRate
    let brokerFee = grossRevenue * brokerFeeRate
    let pendingContractFee = scenario == .contractSale && contractFee == nil
    guard contractFee != nil || pendingContractFee else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: grossRevenue,
        salesTaxRate: salesTaxRate,
        salesTax: salesTax,
        brokerFeeRate: brokerFeeRate,
        brokerFeeIsApplicable: scenario == .listedSale,
        brokerFee: brokerFee,
        contractFee: nil,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost,
        totalCost: totalCost,
        grossOrNetRevenue: nil,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: quotes
      )
    }
    let netRevenue =
      grossRevenue - salesTax - brokerFee - (contractFee ?? 0)
    guard grossRevenue.isFinite, salesTax.isFinite, brokerFee.isFinite,
      netRevenue.isFinite
    else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: nil,
        salesTaxRate: salesTaxRate,
        salesTax: nil,
        brokerFeeRate: brokerFeeRate,
        brokerFeeIsApplicable: scenario == .listedSale,
        brokerFee: nil,
        contractFee: nil,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost,
        totalCost: totalCost,
        grossOrNetRevenue: nil,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: quotes
      )
    }
    guard let totalCost, totalCost.isFinite, totalCost >= 0 else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: grossRevenue,
        salesTaxRate: salesTaxRate,
        salesTax: salesTax,
        brokerFeeRate: brokerFeeRate,
        brokerFeeIsApplicable: scenario == .listedSale,
        brokerFee: brokerFee,
        contractFee: contractFee,
        inboundLogisticsAssessment: inboundLogisticsAssessment,
        outboundLogisticsAssessment: outboundLogisticsAssessment,
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost,
        totalCost: totalCost,
        grossOrNetRevenue: netRevenue,
        profit: nil,
        margin: nil,
        roi: nil,
        quotes: quotes
      )
    }
    let profit = netRevenue - totalCost
    return SaleScenarioResult(
      scenario: scenario,
      marketLocation: marketLocation,
      grossRevenue: grossRevenue,
      salesTaxRate: salesTaxRate,
      salesTax: salesTax,
      brokerFeeRate: brokerFeeRate,
      brokerFeeIsApplicable: scenario == .listedSale,
      brokerFee: brokerFee,
      contractFee: contractFee,
      inboundLogisticsAssessment: inboundLogisticsAssessment,
      outboundLogisticsAssessment: outboundLogisticsAssessment,
      outboundLogistics: outboundLogistics,
      outboundLogisticsCost: outboundLogisticsCost,
      totalCost: totalCost,
      grossOrNetRevenue: netRevenue,
      profit: profit,
      margin: netRevenue == 0 ? nil : profit / netRevenue,
      roi: totalCost == 0 ? nil : profit / totalCost,
      quotes: quotes
    )
  }

  /// Returns the sum of every currently known cost component. A manual route
  /// is deliberately omitted and remains visible on the scenario as pending;
  /// an unavailable or prohibited route still prevents a calculation.
  private static func knownScenarioCost(
    productionCostBeforeLogistics: Double?,
    routes: [LogisticsRouteAssessment?]
  ) -> Double? {
    guard let productionCostBeforeLogistics,
      productionCostBeforeLogistics.isFinite,
      productionCostBeforeLogistics >= 0
    else { return nil }
    var total = productionCostBeforeLogistics
    for route in routes.compactMap({ $0 }) {
      switch route.status {
      case .calculated, .notRequired:
        guard let cost = route.cost, cost.isFinite, cost >= 0 else {
          return nil
        }
        total += cost
      case .manualTransferRequired:
        if let knownPartialCost = route.cost {
          guard knownPartialCost.isFinite, knownPartialCost >= 0 else {
            return nil
          }
          total += knownPartialCost
        }
      case .prohibited, .unavailable:
        return nil
      }
      guard total.isFinite && total >= 0 else { return nil }
    }
    return total
  }

  private func outboundJumpFreighterCargo(
    requests: [ProductionRequestLine],
    nodes: [PlanNode],
    catalog: any IndustryCatalogQuerying
  ) async throws -> [LogisticsCargoItem] {
    let roots = topLevelProducedRoots(requests: requests, nodes: nodes)
    var quantityByType: [Int64: Int64] = [:]
    var nameByType: [Int64: String] = [:]
    for root in roots where CapitalSelfJumpPolicy.product(for: root) == nil {
      quantityByType[root.typeID] = Self.saturatedAdd(
        quantityByType[root.typeID, default: 0],
        root.requiredQuantity
      )
      nameByType[root.typeID] = root.name
    }
    var cargo: [LogisticsCargoItem] = []
    for typeID in quantityByType.keys.sorted() {
      cargo.append(
        LogisticsCargoItem(
          typeID: typeID,
          quantity: quantityByType[typeID, default: 0],
          collateral: nil,
          packagedVolumePerUnit: try await catalog.packagedVolume(
            typeID: typeID
          ),
          name: nameByType[typeID]
        )
      )
    }
    return cargo
  }

  private func selfJumpingCapitalProducts(
    requests: [ProductionRequestLine],
    nodes: [PlanNode]
  ) -> [(product: CapitalSelfJumpProduct, quantity: Int64)] {
    var products: [Int64: (CapitalSelfJumpProduct, Int64)] = [:]
    for root in topLevelProducedRoots(requests: requests, nodes: nodes) {
      guard let product = CapitalSelfJumpPolicy.product(for: root) else {
        continue
      }
      let current = products[product.typeID]?.1 ?? 0
      products[product.typeID] = (
        product,
        Self.saturatedAdd(current, root.requiredQuantity)
      )
    }
    return products.values.sorted { $0.0.typeID < $1.0.typeID }.map {
      (product: $0.0, quantity: $0.1)
    }
  }

  private func topLevelProducedRoots(
    requests: [ProductionRequestLine],
    nodes: [PlanNode]
  ) -> [PlanNode] {
    let referencedChildren = Set(nodes.flatMap(\.children))
    return requests.compactMap { request in
      nodes.last { node in
        node.topLevelRequestID == request.id
          && node.action == .produce
          && !referencedChildren.contains(node.id)
      }
    }
  }

  private func logisticsBreakdown(
    configuration: LogisticsConfiguration?,
    materials: [MaterialRequirement],
    requests: [ProductionRequestLine],
    nodes: [PlanNode],
    mainHub: ProcurementLocation,
    homeHub: ProcurementLocation,
    marketBook: PreparedMarketOrderBook,
    includeInboundMaterials: Bool,
    includeOutboundProducts: Bool,
    catalog: any IndustryCatalogQuerying,
    refiningOptimization: OreRefiningOptimizationResult? = nil
  ) async throws -> (
    breakdown: LogisticsCostBreakdown?,
    cost: Double?,
    warnings: [DomainWarning]
  ) {
    guard let configuration, configuration.isEnabled else {
      return (nil, 0, [])
    }
    guard includeInboundMaterials || includeOutboundProducts else {
      return (nil, 0, [])
    }
    guard !mainHub.representsSameLocation(as: homeHub) else {
      return (nil, 0, [])
    }
    guard let rate = configuration.effectiveISKPerCubicMeter else {
      return (
        nil,
        nil,
        [
          DomainWarning(
            code: "logistics.missing-volume-rate",
            message:
              "Logistics is enabled, but the ISK per m³ rate is missing or invalid.",
            severity: .blocking
          )
        ]
      )
    }
    guard
      let maximumContractVolume =
        configuration.effectiveMaximumContractVolumeM3
    else {
      return (
        nil,
        nil,
        [
          DomainWarning(
            code: "logistics.invalid-volume-limit",
            message:
              "Logistics is enabled, but the contract volume limit is invalid.",
            severity: .blocking
          )
        ]
      )
    }
    var legs: [LogisticsCostLeg] = []
    var warnings: [DomainWarning] = []

    if includeInboundMaterials {
      struct InboundCargo {
        let typeID: Int64
        let quantity: Int64
        let collateral: Double?
      }
      var coverageRemaining = refiningOptimization?.coveredMinerals ?? [:]
      var inboundCargo: [InboundCargo] = []
      for purchase in nodes where purchase.action == .buy {
        let covered = min(
          purchase.requiredQuantity,
          coverageRemaining[purchase.typeID, default: 0]
        )
        if covered > 0 {
          coverageRemaining[purchase.typeID] = max(
            0,
            coverageRemaining[purchase.typeID, default: 0] - covered
          )
        }
        let quantity = purchase.requiredQuantity - covered
        guard quantity > 0 else { continue }
        let quote = marketBook.quote(
          typeID: purchase.typeID,
          quantity: quantity,
          scenario: .materialBuy
        )
        warnings.append(contentsOf: quote.warnings)
        inboundCargo.append(
          InboundCargo(
            typeID: purchase.typeID,
            quantity: quantity,
            collateral: quote.total
          )
        )
      }
      for purchase in refiningOptimization?.purchases ?? [] {
        inboundCargo.append(
          InboundCargo(
            typeID: purchase.oreTypeID,
            quantity: purchase.quantity,
            collateral: purchase.purchaseQuote.total
          )
        )
      }
      if !inboundCargo.isEmpty {
        let result = try await logisticsLegs(
          kind: .inboundMaterials,
          origin: mainHub.name,
          destination: homeHub.name,
          cargo: inboundCargo.map {
            ($0.typeID, $0.quantity, $0.collateral)
          },
          rate: rate,
          maximumContractVolume: maximumContractVolume,
          catalog: catalog
        )
        legs.append(contentsOf: result.legs)
        warnings.append(contentsOf: result.warnings)
      }
    }

    if includeOutboundProducts {
      let referencedChildren = Set(nodes.flatMap(\.children))
      let roots = requests.compactMap { request in
        nodes.last { node in
          node.topLevelRequestID == request.id
            && node.action == .produce
            && !referencedChildren.contains(node.id)
        }
      }
      let grouped = Dictionary(grouping: roots) {
        acceptedLogisticsFacilityName(
          $0.facilityName,
          fallback: configuration.productionLocationName
        )
      }
      for (origin, products) in grouped.sorted(by: { $0.key < $1.key })
      where origin != mainHub.name {
        var cargo: [(Int64, Int64, Double?)] = []
        for product in products {
          let quote = marketBook.quote(
            typeID: product.typeID,
            quantity: product.requiredQuantity,
            scenario: .materialBuy
          )
          warnings.append(contentsOf: quote.warnings)
          cargo.append(
            (product.typeID, product.requiredQuantity, quote.total)
          )
        }
        let result = try await logisticsLegs(
          kind: .outboundProducts,
          origin: origin,
          destination: mainHub.name,
          cargo: cargo,
          rate: rate,
          maximumContractVolume: maximumContractVolume,
          catalog: catalog
        )
        legs.append(contentsOf: result.legs)
        warnings.append(contentsOf: result.warnings)
      }
    }

    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return (nil, nil, warnings)
    }
    let total = legs.reduce(0) { $0 + $1.roundedCharge }
    guard total.isFinite, total >= 0 else {
      return (
        nil,
        nil,
        warnings + [
          DomainWarning(
            code: "logistics.invalid-total",
            message: "The logistics total exceeded safe numeric limits.",
            severity: .blocking
          )
        ]
      )
    }
    return (
      LogisticsCostBreakdown(
        ruleVersion: configuration.effectiveRuleVersion,
        iskPerCubicMeter: rate,
        collateralRate: LogisticsConfiguration.collateralRate,
        maximumContractVolumeM3:
          maximumContractVolume,
        roundingIncrement: LogisticsConfiguration.roundingIncrement,
        legs: legs,
        total: total
      ),
      total,
      warnings
    )
  }

  private func acceptedLogisticsFacilityName(
    _ name: String?,
    fallback: String
  ) -> String {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty,
      name != "Unconfigured structure",
      name != "Unconfigured reactor",
      name != "Unnamed structure / station"
    else { return fallback }
    return name
  }

  private func makeOrBuyAnalysis(
    definition: BlueprintDefinition,
    requiredQuantity: Int64,
    context: IndustryPlanningContext,
    marketBook: PreparedMarketOrderBook,
    systemIndexLookup: IndustrySystemIndexLookup
  ) async throws -> MaterialMakeOrBuyAnalysis? {
    guard requiredQuantity > 0,
      definition.activity.kind != .invention,
      let outputQuantity = definition.activity.products.first(where: {
        $0.typeID == definition.productTypeID
      })?.quantity,
      outputQuantity > 0
    else { return nil }

    let runs = Self.runsRequired(
      wantedQuantity: requiredQuantity,
      outputPerRun: outputQuantity
    )
    let producedQuantity = Self.saturatedMultiply(
      Int64(runs),
      outputQuantity
    )
    let mainHub = context.defaultPurchaseLocation
    let marketMatchesMainHub =
      mainHub.locationID == context.market.locationID
    let purchaseQuote = marketBook.quote(
      typeID: definition.productTypeID,
      quantity: requiredQuantity,
      scenario: .materialBuy
    )
    var warnings = purchaseQuote.warnings
    if !marketMatchesMainHub {
      warnings.append(
        DomainWarning(
          code: "make-or-buy.market-location-mismatch",
          message:
            "The market snapshot does not belong to the configured Main Hub.",
          severity: .blocking
        )
      )
    }

    let facility = try await makeOrBuyFacility(
      definition: definition,
      context: context
    )
    warnings.append(contentsOf: facility.warnings)

    let inputQuantities = try await makeOrBuyInputQuantities(
      definition: definition,
      runs: runs,
      context: context
    )
    var inputQuotes: [(typeID: Int64, quantity: Int64, quote: PriceQuote)] = []
    var buildMaterialCost = 0.0
    var buildMaterialCostComplete = true
    for input in inputQuantities {
      let quote = marketBook.quote(
        typeID: input.typeID,
        quantity: input.quantity,
        scenario: .materialBuy
      )
      inputQuotes.append((input.typeID, input.quantity, quote))
      warnings.append(contentsOf: quote.warnings)
      guard let total = quote.total,
        total.isFinite,
        total >= 0,
        (buildMaterialCost + total).isFinite
      else {
        buildMaterialCostComplete = false
        continue
      }
      buildMaterialCost += total
    }

    let installation = makeOrBuyInstallationCost(
      definition: definition,
      runs: runs,
      facility: facility,
      context: context,
      systemIndexLookup: systemIndexLookup
    )
    warnings.append(contentsOf: installation.warnings)

    let purchaseLogistics = try await makeOrBuyLogisticsCost(
      configuration: context.productionBasis?.logistics,
      origin: mainHub,
      destinationName: facility.name,
      destinationLocationID: facility.locationID,
      cargo: [
        (
          definition.productTypeID,
          requiredQuantity,
          purchaseQuote.total
        )
      ],
      catalog: context.catalog
    )
    warnings.append(contentsOf: purchaseLogistics.warnings)

    let buildLogistics = try await makeOrBuyLogisticsCost(
      configuration: context.productionBasis?.logistics,
      origin: mainHub,
      destinationName: facility.name,
      destinationLocationID: facility.locationID,
      cargo: inputQuotes.map { ($0.typeID, $0.quantity, $0.quote.total) },
      catalog: context.catalog
    )
    warnings.append(contentsOf: buildLogistics.warnings)

    let purchaseTotal =
      marketMatchesMainHub
      ? Self.acceptedCostTotal([
        purchaseQuote.total,
        purchaseLogistics.cost,
      ]) : nil
    let acceptedBuildMaterialCost =
      buildMaterialCostComplete ? buildMaterialCost : nil
    let buildTotal =
      marketMatchesMainHub
      ? Self.acceptedCostTotal([
        acceptedBuildMaterialCost,
        installation.cost,
        buildLogistics.cost,
      ]) : nil
    let recommendation: MakeOrBuyRecommendation
    let savings: Double?
    if let purchaseTotal, let buildTotal {
      if buildTotal <= purchaseTotal {
        recommendation = .produce
        savings = purchaseTotal - buildTotal
      } else {
        recommendation = .buy
        savings = buildTotal - purchaseTotal
      }
    } else {
      recommendation = .unavailable
      savings = nil
    }

    return MaterialMakeOrBuyAnalysis(
      requiredQuantity: requiredQuantity,
      productionRuns: runs,
      producedQuantity: producedQuantity,
      mainHub: mainHub,
      purchaseQuote: purchaseQuote,
      purchaseLogisticsCost: purchaseLogistics.cost,
      purchaseTotalCost: purchaseTotal,
      buildMaterialCost: acceptedBuildMaterialCost,
      buildInstallationCost: installation.cost,
      buildLogisticsCost: buildLogistics.cost,
      buildTotalCost: buildTotal,
      recommendation: recommendation,
      savings: savings,
      warnings: Self.deduplicatedWarnings(warnings)
    )
  }

  private func makeOrBuyInputQuantities(
    definition: BlueprintDefinition,
    runs: Int,
    context: IndustryPlanningContext
  ) async throws -> [(typeID: Int64, quantity: Int64)] {
    let isReaction = definition.activity.kind == .reaction
    let classification = try await context.catalog.industryClassification(
      productTypeID: definition.productTypeID
    )
    let category = classification?.manufacturingCategory ?? .module
    let facilitySelection =
      isReaction ? nil : context.productionBasis?.selection(for: category)
    let me =
      context.productionBasis?.defaultIntermediateME
      ?? context.manufacturingProfile.defaultIntermediateME
    return definition.activity.materials.map { material in
      let rawRequired = Self.saturatedMultiply(Int64(runs), material.quantity)
      let required =
        isReaction
        ? Self.scaledReactionQuantity(
          rawRequired: rawRequired,
          runs: runs,
          multiplier: context.reactionProfile?.effectiveMaterialMultiplier ?? 1
        )
        : Self.manufacturingMaterialQuantity(
          baseQuantity: material.quantity,
          runs: runs,
          materialEfficiency: me,
          facilityMultiplier:
            facilitySelection?.materialMultiplier
            ?? context.manufacturingProfile.effectiveMaterialMultiplier
        )
      return (material.typeID, required)
    }
  }

  private func makeOrBuyFacility(
    definition: BlueprintDefinition,
    context: IndustryPlanningContext
  ) async throws -> MakeOrBuyFacility {
    if definition.activity.kind == .reaction {
      guard let reactionProfile = context.reactionProfile else {
        return MakeOrBuyFacility(
          name: context.productionBasis?.reactionSystem.solarSystemName
            ?? "Reaction facility",
          locationID: nil,
          systemID: context.productionBasis?.reactionSystem.solarSystemID,
          systemCostIndexOverride:
            context.productionBasis?.reactionSystem.costIndexOverride,
          materialMultiplier: nil,
          jobCostMultiplier: nil,
          facilityTaxRate: nil,
          needsReview: true,
          warnings: [
            DomainWarning(
              code: "make-or-buy.reaction-profile-required",
              message:
                "A verified reaction facility is required for the build comparison.",
              severity: .blocking
            )
          ]
        )
      }
      let selected = context.productionBasis?.structure(
        id: context.productionBasis?.reactionStructureID
      )
      let selectedSystem = selected.flatMap {
        context.productionBasis?.systemConfiguration(
          for: .reaction,
          structure: $0
        )
      }
      return MakeOrBuyFacility(
        name: reactionProfile.structureName,
        locationID: selected?.structureID,
        systemID: reactionProfile.solarSystemID,
        systemCostIndexOverride:
          selectedSystem?.costIndexOverride,
        materialMultiplier: reactionProfile.effectiveMaterialMultiplier,
        jobCostMultiplier: reactionProfile.effectiveJobCostMultiplier,
        facilityTaxRate:
          selected?.facilityTaxRate ?? reactionProfile.facilityTaxRate,
        needsReview: selected?.needsReview == true,
        warnings: selected?.needsReview == true
          ? [
            DomainWarning(
              code: "make-or-buy.facility-needs-review",
              message:
                "The configured reaction facility contains unresolved modifiers.",
              severity: .blocking
            )
          ] : []
      )
    }

    let classification = try await context.catalog.industryClassification(
      productTypeID: definition.productTypeID
    )
    let category = classification?.manufacturingCategory ?? .module
    let selection = context.productionBasis?.selection(for: category)
    let selected = selection.flatMap {
      context.productionBasis?.structure(id: $0.structureID)
    }
    let system = context.productionBasis?.manufacturingSystem(for: selected)
    let needsReview = selection?.needsReview == true
    return MakeOrBuyFacility(
      name:
        selection?.structureName
        ?? context.manufacturingProfile.structureName,
      locationID: selected?.structureID,
      systemID:
        system?.solarSystemID
        ?? selected?.solarSystemID
        ?? context.manufacturingProfile.solarSystemID,
      systemCostIndexOverride: system?.costIndexOverride,
      materialMultiplier:
        selection?.materialMultiplier
        ?? context.manufacturingProfile.effectiveMaterialMultiplier,
      jobCostMultiplier:
        selected?.jobCostMultiplier
        ?? context.manufacturingProfile.effectiveJobCostMultiplier,
      facilityTaxRate:
        selected?.facilityTaxRate
        ?? context.manufacturingProfile.facilityTaxRate,
      needsReview: needsReview,
      warnings: needsReview
        ? [
          DomainWarning(
            code: "make-or-buy.facility-needs-review",
            message:
              "The configured manufacturing facility contains unresolved modifiers.",
            severity: .blocking
          )
        ] : []
    )
  }

  private func makeOrBuyInstallationCost(
    definition: BlueprintDefinition,
    runs: Int,
    facility: MakeOrBuyFacility,
    context: IndustryPlanningContext,
    systemIndexLookup: IndustrySystemIndexLookup
  ) -> (cost: Double?, warnings: [DomainWarning]) {
    guard !facility.needsReview,
      let systemID = facility.systemID,
      let bonusMultiplier = facility.jobCostMultiplier,
      let facilityTax = facility.facilityTaxRate
    else { return (nil, facility.warnings) }
    guard
      let index = facility.systemCostIndexOverride
        ?? systemIndexLookup.costIndex(
          solarSystemID: systemID,
          activity: definition.activity.kind
        )
    else {
      return (
        nil,
        [
          DomainWarning(
            code: "make-or-buy.missing-system-index",
            message:
              "The system cost index required for the build comparison is unavailable.",
            severity: .blocking
          )
        ]
      )
    }
    var eiv = 0.0
    for material in definition.activity.materials {
      guard let adjusted = context.adjustedPrices[material.typeID]?.adjustedPrice,
        adjusted.isFinite,
        adjusted >= 0
      else {
        return (
          nil,
          [
            DomainWarning(
              code: "make-or-buy.missing-adjusted-price",
              message:
                "An adjusted price required for the build installation cost is unavailable.",
              severity: .blocking
            )
          ]
        )
      }
      eiv += adjusted * Double(material.quantity) * Double(runs)
      guard eiv.isFinite, eiv >= 0 else { return (nil, []) }
    }
    let scc =
      definition.activity.kind == .reaction
      ? IndustryRuleSet.current.reactionSCCRate
      : IndustryRuleSet.current.manufacturingSCCRate
    let alpha =
      (context.productionBasis?.cloneState
        ?? (definition.activity.kind == .reaction
          ? context.reactionProfile?.cloneState
          : context.manufacturingProfile.cloneState))
        == .alpha
      ? IndustryRuleSet.current.alphaSurchargeRate : 0
    let cost = eiv * ((index * bonusMultiplier) + facilityTax + scc + alpha)
    guard cost.isFinite, cost >= 0 else { return (nil, []) }
    return (cost, [])
  }

  private func makeOrBuyLogisticsCost(
    configuration: LogisticsConfiguration?,
    origin: ProcurementLocation,
    destinationName: String,
    destinationLocationID: Int64?,
    cargo: [(typeID: Int64, quantity: Int64, collateral: Double?)],
    catalog: any IndustryCatalogQuerying
  ) async throws -> (cost: Double?, warnings: [DomainWarning]) {
    if let originID = origin.locationID,
      originID == destinationLocationID
    {
      return (0, [])
    }
    guard let configuration,
      configuration.isEnabled,
      configuration.includeInboundMaterials,
      let rate = configuration.effectiveISKPerCubicMeter,
      let maximumVolume = configuration.effectiveMaximumContractVolumeM3
    else {
      return (
        nil,
        [
          DomainWarning(
            code: "make-or-buy.logistics-unavailable",
            message:
              "Enable complete Main Hub logistics in Profile to compare build and purchase costs.",
            severity: .blocking
          )
        ]
      )
    }
    let result = try await logisticsLegs(
      kind: .inboundMaterials,
      origin: origin.name,
      destination: destinationName,
      cargo: cargo,
      rate: rate,
      maximumContractVolume: maximumVolume,
      catalog: catalog
    )
    guard !result.warnings.contains(where: { $0.severity == .blocking }) else {
      return (nil, result.warnings)
    }
    let total = result.legs.reduce(0) { $0 + $1.roundedCharge }
    return total.isFinite && total >= 0
      ? (total, result.warnings)
      : (
        nil,
        result.warnings + [
          DomainWarning(
            code: "make-or-buy.invalid-logistics-cost",
            message: "The comparison logistics cost exceeded safe limits.",
            severity: .blocking
          )
        ]
      )
  }

  private static func acceptedCostTotal(_ values: [Double?]) -> Double? {
    guard values.allSatisfy({ $0?.isFinite == true && ($0 ?? -1) >= 0 }) else {
      return nil
    }
    let total = values.compactMap { $0 }.reduce(0, +)
    return total.isFinite && total >= 0 ? total : nil
  }

  private static func deduplicatedWarnings(
    _ warnings: [DomainWarning]
  ) -> [DomainWarning] {
    var seen = Set<String>()
    return warnings.filter { seen.insert($0.code + "|" + $0.message).inserted }
  }

  private func logisticsLegs(
    kind: LogisticsLegKind,
    origin: String,
    destination: String,
    cargo: [(typeID: Int64, quantity: Int64, collateral: Double?)],
    rate: Double,
    maximumContractVolume: Double,
    catalog: any IndustryCatalogQuerying
  ) async throws -> (
    legs: [LogisticsCostLeg],
    warnings: [DomainWarning]
  ) {
    let typeIDs = Set(cargo.map(\.typeID))
    async let packagedVolumes = catalog.packagedVolumes(typeIDs: typeIDs)
    async let typeNames = catalog.typeNames(ids: typeIDs)
    let metadata = try await (packagedVolumes, typeNames)
    var acceptedCargo: [LogisticsCargoItem] = []
    acceptedCargo.reserveCapacity(cargo.count)
    for item in cargo {
      acceptedCargo.append(
        LogisticsCargoItem(
          typeID: item.typeID,
          quantity: item.quantity,
          collateral: item.collateral,
          packagedVolumePerUnit: metadata.0[item.typeID],
          name: metadata.1[item.typeID]
        )
      )
    }
    return LogisticsCostCalculator.calculateLegs(
      kind: kind,
      origin: origin,
      destination: destination,
      cargo: acceptedCargo,
      iskPerCubicMeter: rate,
      maximumContractVolumeM3: maximumContractVolume
    )
  }

  private func optimizeCompressedOreRefining(
    requirements: [Int64: Int64],
    directQuotes: [Int64: PriceQuote],
    context: IndustryPlanningContext,
    marketBook: PreparedMarketOrderBook,
    homeHub: ProcurementLocation
  ) async throws -> OreRefiningOptimizationResult? {
    guard context.productionBasis?.compressedOreRefining.isEnabled == true,
      !requirements.isEmpty
    else { return nil }
    guard let basis = context.productionBasis else { return nil }

    let options: [CompressedOreOption]
    do {
      options = try await context.catalog.compressedOreOptions(
        producing: Set(requirements.keys)
      )
    } catch {
      return OreRefiningOptimizationResult(
        purchases: [],
        coveredMinerals: [:],
        remainingDirectMinerals: requirements,
        warnings: [
          DomainWarning(
            code: "refining.sde-type-materials-unavailable",
            message:
              "Compressed-ore optimization requires an SDE catalog imported with typeMaterials. The direct mineral route was preserved.",
            severity: .warning
          )
        ]
      )
    }
    guard !options.isEmpty else {
      return OreRefiningOptimizationResult(
        purchases: [],
        coveredMinerals: [:],
        remainingDirectMinerals: requirements,
        warnings: [
          DomainWarning(
            code: "refining.no-compressed-ore-options",
            message:
              "No resolved compressed ore in the active SDE produces the required mineral purchases. The direct mineral route was preserved.",
            severity: .information
          )
        ]
      )
    }
    let outputTypeIDs = Set(
      options.flatMap { option in option.outputs.map(\.typeID) }
    )
    let outputTypeNames =
      (try? await context.catalog.typeNames(ids: outputTypeIDs)) ?? [:]
    let facilities = basis.structures.filter(\.isReprocessingCapable)
    guard !facilities.isEmpty else {
      return OreRefiningOptimizationResult(
        purchases: [],
        coveredMinerals: [:],
        remainingDirectMinerals: requirements,
        warnings: [
          DomainWarning(
            code: "refining.facility-not-configured",
            message:
              "Enable a resolved Reprocessing service, its ore rig or base yield, and a confirmed Reprocessing tax on at least one structure. The direct mineral route was preserved.",
            severity: .warning
          )
        ]
      )
    }
    guard !context.characterCapabilities.isEmpty else {
      return OreRefiningOptimizationResult(
        purchases: [],
        coveredMinerals: [:],
        remainingDirectMinerals: requirements,
        warnings: [
          DomainWarning(
            code: "refining.character-skills-unavailable",
            message:
              "No connected character skill snapshot is available for Reprocessing. The direct mineral route was preserved.",
            severity: .warning
          )
        ]
      )
    }
    let logistics = basis.logistics
    if !context.defaultPurchaseLocation.representsSameLocation(as: homeHub) {
      guard logistics.isEnabled,
        logistics.effectiveISKPerCubicMeter != nil,
        logistics.effectiveMaximumContractVolumeM3 != nil
      else {
        return OreRefiningOptimizationResult(
          purchases: [],
          coveredMinerals: [:],
          remainingDirectMinerals: requirements,
          warnings: [
            DomainWarning(
              code: "refining.logistics-unavailable",
              message:
                "Compressed ore cannot be compared without the complete Main Hub logistics rate and contract-volume limit. The direct mineral route was preserved.",
              severity: .warning
            )
          ]
        )
      }
    }

    let directVolumes = try await context.catalog.packagedVolumes(
      typeIDs: Set(requirements.keys)
    )
    var remaining = requirements
    var purchases: [OreRefiningPurchase] = []
    var selectedOreTypeIDs = Set<Int64>()
    var warnings: [DomainWarning] = []
    let unresolvedOutputTypeIDs = outputTypeIDs.filter {
      outputTypeNames[$0] == nil
    }
    if !unresolvedOutputTypeIDs.isEmpty {
      warnings.append(
        DomainWarning(
          code: "refining.output-type-name-unresolved",
          message:
            "The active SDE did not resolve names for one or more factual Reprocessing outputs. Their Type IDs and quantities remain explicit.",
          severity: .warning
        )
      )
    }

    for _ in 0..<min(options.count, 64) {
      var best: OreRefiningProposal?
      for option in options where !selectedOreTypeIDs.contains(option.typeID) {
        guard let skillTypeID = option.reprocessingSkillTypeID else { continue }
        let relevantOutputs = option.outputs.filter {
          remaining[$0.typeID, default: 0] > 0
        }
        guard !relevantOutputs.isEmpty else { continue }
        for facility in facilities {
          guard
            let baseYield = facility.effectiveReprocessingYieldMultiplier(
              for: option.kind
            ), let taxRate = facility.reprocessingTaxRate,
            let character = bestReprocessingCharacter(
              capabilities: context.characterCapabilities,
              preferredCharacterID: facility.reprocessingCharacterID,
              implantsByCharacterID:
                facility.reprocessingImplantsByCharacterID,
              oreSkillTypeID: skillTypeID,
              baseYieldMultiplier: baseYield
            ),
            let yield = ReprocessingYieldCalculator.yieldMultiplier(
              baseYieldMultiplier: baseYield,
              reprocessingLevel: character.reprocessingLevel,
              reprocessingEfficiencyLevel:
                character.reprocessingEfficiencyLevel,
              oreProcessingLevel: character.oreProcessingLevel,
              implantYieldBonusPercent: (character.implant ?? .none).yieldBonusPercent
            )
          else { continue }
          for target in relevantOutputs {
            guard
              let batches = ReprocessingYieldCalculator.minimumBatches(
                requiredQuantity: remaining[target.typeID, default: 0],
                baseQuantity: target.quantity,
                yieldMultiplier: yield
              ),
              let quantity = Self.safeMultiply(
                batches,
                option.portionSize
              )
            else { continue }
            let quote = marketBook.quote(
              typeID: option.typeID,
              quantity: quantity,
              scenario: .materialBuy
            )
            guard let purchaseCost = quote.total else { continue }
            var produced: [ReprocessingMaterialOutput] = []
            var covered: [Int64: Int64] = [:]
            var feeBase = 0.0
            var complete = true
            for output in option.outputs {
              guard
                let amount = ReprocessingYieldCalculator.outputQuantity(
                  baseQuantity: output.quantity,
                  batches: batches,
                  yieldMultiplier: yield
                )
              else {
                complete = false
                break
              }
              let coveredAmount = min(
                amount,
                remaining[output.typeID, default: 0]
              )
              produced.append(
                ReprocessingMaterialOutput(
                  typeID: output.typeID,
                  quantity: amount,
                  name: outputTypeNames[output.typeID],
                  usedInPlan: coveredAmount,
                  surplusToWarehouse: amount - coveredAmount
                )
              )
              if coveredAmount > 0 { covered[output.typeID] = coveredAmount }
              guard
                let adjusted = context.adjustedPrices[output.typeID]?
                  .adjustedPrice,
                adjusted.isFinite, adjusted >= 0
              else {
                complete = false
                break
              }
              feeBase += adjusted * Double(amount)
            }
            guard complete, !covered.isEmpty,
              feeBase.isFinite, feeBase >= 0
            else { continue }
            let refiningFee = feeBase * taxRate
            guard refiningFee.isFinite, refiningFee >= 0 else { continue }
            let oreTransport = refiningTransportCost(
              typeID: option.typeID,
              quantity: quantity,
              packagedVolume: option.packagedVolume,
              collateral: purchaseCost,
              origin: context.defaultPurchaseLocation,
              homeHub: homeHub,
              configuration: logistics
            )
            guard let oreTransport else { continue }
            var avoidedPurchaseCost = 0.0
            var directCargo: [LogisticsCargoItem] = []
            for (mineralTypeID, amount) in covered {
              guard
                let unitPrice = directQuotes[mineralTypeID]?
                  .weightedUnitPrice,
                let volume = directVolumes[mineralTypeID]
              else {
                complete = false
                break
              }
              let collateral = unitPrice * Double(amount)
              avoidedPurchaseCost += collateral
              directCargo.append(
                LogisticsCargoItem(
                  typeID: mineralTypeID,
                  quantity: amount,
                  collateral: collateral,
                  packagedVolumePerUnit: volume
                )
              )
            }
            guard complete else { continue }
            let avoidedTransport = directTransportCost(
              cargo: directCargo,
              origin: context.defaultPurchaseLocation,
              homeHub: homeHub,
              configuration: logistics
            )
            guard let avoidedTransport else { continue }
            let estimatedSavings =
              avoidedPurchaseCost + avoidedTransport
              - purchaseCost - refiningFee - oreTransport
            guard estimatedSavings.isFinite, estimatedSavings > 0 else {
              continue
            }
            let proposal = OreRefiningProposal(
              purchase: OreRefiningPurchase(
                oreTypeID: option.typeID,
                oreName: option.name,
                quantity: quantity,
                batches: batches,
                purchaseQuote: quote,
                outputs: produced,
                yieldMultiplier: yield,
                facility: OreRefiningFacilitySelection(
                  structureID: facility.id,
                  structureName: facility.displayName,
                  solarSystemID: facility.solarSystemID,
                  solarSystemName: facility.solarSystemName,
                  baseYieldMultiplier: baseYield,
                  taxRate: taxRate
                ),
                character: character,
                refiningFee: refiningFee
              ),
              covered: covered,
              estimatedSavings: estimatedSavings
            )
            if isBetterRefiningProposal(proposal, than: best) {
              best = proposal
            }
          }
        }
      }
      guard let best else { break }
      purchases.append(best.purchase)
      selectedOreTypeIDs.insert(best.purchase.oreTypeID)
      for (typeID, amount) in best.covered {
        remaining[typeID] = max(0, remaining[typeID, default: 0] - amount)
      }
    }

    guard !purchases.isEmpty else {
      warnings.append(
        DomainWarning(
          code: "refining.no-cheaper-compressed-ore",
          message:
            "Complete Main Hub ore purchase, transport and Reprocessing fees were not cheaper than the direct mineral route. The direct mineral route was preserved.",
          severity: .information
        )
      )
      return OreRefiningOptimizationResult(
        purchases: [],
        coveredMinerals: [:],
        remainingDirectMinerals: requirements,
        warnings: warnings
      )
    }
    let covered = requirements.reduce(into: [Int64: Int64]()) {
      result, entry in
      let amount = entry.value - remaining[entry.key, default: 0]
      if amount > 0 { result[entry.key] = amount }
    }
    if purchases.contains(where: { $0.character.skillsState != .fresh }) {
      warnings.append(
        DomainWarning(
          code: "refining.character-skills-not-fresh",
          message:
            "At least one selected Reprocessing character uses a retained partial or stale skill snapshot. The state remains visible in the Refining breakdown.",
          severity: .warning
        )
      )
    }
    return OreRefiningOptimizationResult(
      purchases: purchases,
      coveredMinerals: covered,
      remainingDirectMinerals: remaining.filter { $0.value > 0 },
      warnings: warnings
    )
  }

  private func bestReprocessingCharacter(
    capabilities: [CharacterCapabilitySnapshot],
    preferredCharacterID: Int64?,
    implantsByCharacterID: [Int64: OreRefiningImplant]?,
    oreSkillTypeID: Int64,
    baseYieldMultiplier: Double
  ) -> OreRefiningCharacterSelection? {
    let acceptedStates: Set<DataFreshness> = [.fresh, .partial, .stale]
    let candidates = capabilities.compactMap {
      capability -> (
        OreRefiningCharacterSelection, Double
      )? in
      if let preferredCharacterID,
        capability.character.id != preferredCharacterID
      {
        return nil
      }
      guard acceptedStates.contains(capability.skills.state),
        let skills = capability.skills.value
      else { return nil }
      let levels = Dictionary(
        uniqueKeysWithValues: skills.map { ($0.skillID, $0.activeLevel) }
      )
      let reprocessing = levels[
        ReprocessingYieldCalculator.reprocessingSkillTypeID,
        default: 0
      ]
      let efficiency = levels[
        ReprocessingYieldCalculator.reprocessingEfficiencySkillTypeID,
        default: 0
      ]
      let ore = levels[oreSkillTypeID, default: 0]
      let implant = implantsByCharacterID?[capability.character.id] ?? .none
      guard
        let yield = ReprocessingYieldCalculator.yieldMultiplier(
          baseYieldMultiplier: baseYieldMultiplier,
          reprocessingLevel: reprocessing,
          reprocessingEfficiencyLevel: efficiency,
          oreProcessingLevel: ore,
          implantYieldBonusPercent: implant.yieldBonusPercent
        )
      else { return nil }
      return (
        OreRefiningCharacterSelection(
          characterID: capability.character.id,
          characterName: capability.character.name,
          reprocessingLevel: reprocessing,
          reprocessingEfficiencyLevel: efficiency,
          oreProcessingLevel: ore,
          implant: implant,
          skillsState: capability.skills.state,
          skillsSource: capability.skills.source
        ),
        yield
      )
    }
    return candidates.sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      if $0.0.skillsState != $1.0.skillsState {
        return refinementFreshnessRank($0.0.skillsState)
          > refinementFreshnessRank($1.0.skillsState)
      }
      if $0.0.characterName != $1.0.characterName {
        return $0.0.characterName.localizedCaseInsensitiveCompare(
          $1.0.characterName
        ) == .orderedAscending
      }
      return $0.0.characterID < $1.0.characterID
    }.first?.0
  }

  private func refiningTransportCost(
    typeID: Int64,
    quantity: Int64,
    packagedVolume: Double?,
    collateral: Double,
    origin: ProcurementLocation,
    homeHub: ProcurementLocation,
    configuration: LogisticsConfiguration
  ) -> Double? {
    if origin.representsSameLocation(as: homeHub) {
      return 0
    }
    guard let rate = configuration.effectiveISKPerCubicMeter,
      let maximum = configuration.effectiveMaximumContractVolumeM3
    else { return nil }
    let result = LogisticsCostCalculator.calculateLegs(
      kind: .inboundMaterials,
      origin: origin.name,
      destination: homeHub.name,
      cargo: [
        LogisticsCargoItem(
          typeID: typeID,
          quantity: quantity,
          collateral: collateral,
          packagedVolumePerUnit: packagedVolume
        )
      ],
      iskPerCubicMeter: rate,
      maximumContractVolumeM3: maximum
    )
    guard !result.warnings.contains(where: { $0.severity == .blocking })
    else { return nil }
    return result.legs.reduce(0) { $0 + $1.roundedCharge }
  }

  private func directTransportCost(
    cargo: [LogisticsCargoItem],
    origin: ProcurementLocation,
    homeHub: ProcurementLocation,
    configuration: LogisticsConfiguration
  ) -> Double? {
    if origin.representsSameLocation(as: homeHub) { return 0 }
    guard let rate = configuration.effectiveISKPerCubicMeter,
      let maximum = configuration.effectiveMaximumContractVolumeM3
    else { return nil }
    let result = LogisticsCostCalculator.calculateLegs(
      kind: .inboundMaterials,
      origin: origin.name,
      destination: homeHub.name,
      cargo: cargo,
      iskPerCubicMeter: rate,
      maximumContractVolumeM3: maximum
    )
    guard !result.warnings.contains(where: { $0.severity == .blocking })
    else { return nil }
    return result.legs.reduce(0) { $0 + $1.roundedCharge }
  }

  private func isBetterRefiningProposal(
    _ candidate: OreRefiningProposal,
    than current: OreRefiningProposal?
  ) -> Bool {
    guard let current else { return true }
    if candidate.estimatedSavings != current.estimatedSavings {
      return candidate.estimatedSavings > current.estimatedSavings
    }
    if candidate.purchase.oreTypeID != current.purchase.oreTypeID {
      return candidate.purchase.oreTypeID < current.purchase.oreTypeID
    }
    if candidate.purchase.facility.structureName
      != current.purchase.facility.structureName
    {
      return candidate.purchase.facility.structureName
        .localizedCaseInsensitiveCompare(
          current.purchase.facility.structureName
        ) == .orderedAscending
    }
    return candidate.purchase.character.characterID
      < current.purchase.character.characterID
  }

  private func refinementFreshnessRank(_ state: DataFreshness) -> Int {
    switch state {
    case .fresh: 3
    case .stale: 2
    case .partial: 1
    case .forbidden, .unavailable: 0
    }
  }

  private static func ceilingDivide(_ value: Int64, by divisor: Int64)
    -> Int64
  {
    guard value > 0, divisor > 0 else { return 0 }
    return 1 + (value - 1) / divisor
  }

  private static func safeMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64? {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? nil : result.partialValue
  }

  private func consolidateIntermediateJobs(
    _ jobs: [JobDefinition]
  ) -> [JobDefinition] {
    var result = jobs.filter(\.isTopLevel)
    var grouped: [JobKey: JobDefinition] = [:]
    for job in jobs where !job.isTopLevel {
      let key = JobKey(
        productTypeID: job.definition.productTypeID,
        activity: job.definition.activity.kind,
        me: job.me,
        te: job.te,
        facilityID: job.facilitySelection?.structureID,
        blueprintSupplyJobID: job.blueprintSupplyJobID
      )
      if let existing = grouped[key] {
        let (combinedRuns, overflow) = existing.runs.addingReportingOverflow(
          job.runs
        )
        grouped[key] = JobDefinition(
          definition: existing.definition,
          runs: overflow ? Int.max : combinedRuns,
          me: existing.me,
          te: existing.te,
          isTopLevel: false,
          facilitySelection: existing.facilitySelection,
          selectedStructure: existing.selectedStructure,
          blueprintSupplyJobID: existing.blueprintSupplyJobID,
          blueprintSource: existing.blueprintSource
        )
      } else {
        grouped[key] = job
      }
    }
    result.append(contentsOf: grouped.values)
    return result
  }

  public static func manufacturingMaterialQuantity(
    baseQuantity: Int64,
    runs: Int,
    materialEfficiency: Int,
    facilityMultiplier: Double
  ) -> Int64 {
    guard baseQuantity > 0, runs > 0 else { return 0 }
    let value =
      Double(baseQuantity) * Double(runs)
      * (1 - Double(materialEfficiency) / 100)
      * facilityMultiplier
    guard value.isFinite, value > 0 else {
      return value > 0 ? Int64.max : Int64(runs)
    }
    let rounded = ceil(value)
    guard rounded < Double(Int64.max) else { return Int64.max }
    return max(Int64(runs), Int64(rounded))
  }

  public static func runsRequired(
    wantedQuantity: Int,
    outputPerRun: Int64
  ) -> Int {
    guard wantedQuantity > 0, outputPerRun > 0 else { return 0 }
    let wanted = Int64(wantedQuantity)
    let completeRuns = wanted / outputPerRun
    let remainderRun = wanted % outputPerRun == 0 ? 0 : 1
    return Int(completeRuns + Int64(remainderRun))
  }

  private static func runsRequired(
    wantedQuantity: Int64,
    outputPerRun: Int64
  ) -> Int {
    guard wantedQuantity > 0, outputPerRun > 0 else { return 0 }
    let completeRuns = wantedQuantity / outputPerRun
    let extraRun: Int64 = wantedQuantity % outputPerRun == 0 ? 0 : 1
    let (runs, overflow) = completeRuns.addingReportingOverflow(extraRun)
    guard !overflow, runs < Int64(Int.max) else { return Int.max }
    return Int(runs)
  }

  private static func scaledReactionQuantity(
    rawRequired: Int64,
    runs: Int,
    multiplier: Double
  ) -> Int64 {
    guard rawRequired > 0, runs > 0 else { return 0 }
    let value = Double(rawRequired) * multiplier
    guard value.isFinite, value > 0 else {
      return value > 0 ? Int64.max : Int64(runs)
    }
    let rounded = ceil(value)
    guard rounded < Double(Int64.max) else { return Int64.max }
    return max(Int64(runs), Int64(rounded))
  }

  private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? (rhs >= 0 ? Int64.max : Int64.min) : result
  }

  private static func saturatedMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    if !overflow { return result }
    return (lhs >= 0) == (rhs >= 0) ? Int64.max : Int64.min
  }

  public static func slotMakespan(
    durations: [Int64],
    slots: Int
  ) -> Int64 {
    guard !durations.isEmpty else { return 0 }
    // More configured account slots than jobs cannot shorten the schedule
    // further. Capping the working array at the job count keeps very large,
    // valid account-wide slot values cheap and deterministic.
    let effectiveSlots = min(max(1, slots), durations.count)
    var loads = Array(repeating: Int64(0), count: effectiveSlots)
    for duration in durations.map({ max(0, $0) }).sorted(by: >) {
      let target =
        loads.indices.min {
          if loads[$0] == loads[$1] { return $0 < $1 }
          return loads[$0] < loads[$1]
        } ?? 0
      let (sum, overflow) = loads[target].addingReportingOverflow(duration)
      loads[target] = overflow ? Int64.max : sum
    }
    return loads.max() ?? 0
  }

  private func collectMarketTypes(
    typeID: Int64,
    catalog: any IndustryCatalogQuerying,
    path: [Int64],
    visited: inout Set<Int64>,
    result: inout Set<Int64>
  ) async throws {
    guard !path.contains(typeID) else {
      throw IndustryPlannerError.cycle(path + [typeID])
    }
    guard visited.insert(typeID).inserted else { return }
    result.insert(typeID)
    guard
      let definition = try await catalog.productionDefinition(
        productTypeID: typeID
      )
    else { return }
    for material in definition.activity.materials {
      result.insert(material.typeID)
      try await collectMarketTypes(
        typeID: material.typeID,
        catalog: catalog,
        path: path + [typeID],
        visited: &visited,
        result: &result
      )
    }
  }

  private static func addingCosts(
    _ base: Double?,
    _ additional: Double?
  ) -> Double? {
    guard let base, let additional,
      base.isFinite, additional.isFinite,
      base >= 0, additional >= 0
    else { return nil }
    let total = base + additional
    return total.isFinite && total >= 0 ? total : nil
  }
}

private struct JobDefinition: Sendable {
  let definition: BlueprintDefinition
  let runs: Int
  let me: Int
  let te: Int
  let isTopLevel: Bool
  let facilitySelection: ProductionFacilitySelection?
  let selectedStructure: ConfiguredIndustryStructure?
  let blueprintSupplyJobID: UUID?
  let blueprintSource: BlueprintSourceReference?

  init(
    definition: BlueprintDefinition,
    runs: Int,
    me: Int,
    te: Int,
    isTopLevel: Bool,
    facilitySelection: ProductionFacilitySelection?,
    selectedStructure: ConfiguredIndustryStructure?,
    blueprintSupplyJobID: UUID? = nil,
    blueprintSource: BlueprintSourceReference? = nil
  ) {
    self.definition = definition
    self.runs = runs
    self.me = me
    self.te = te
    self.isTopLevel = isTopLevel
    self.facilitySelection = facilitySelection
    self.selectedStructure = selectedStructure
    self.blueprintSupplyJobID = blueprintSupplyJobID
    self.blueprintSource = blueprintSource
  }
}

private struct MakeOrBuyFacility: Sendable {
  let name: String
  let locationID: Int64?
  let systemID: Int64?
  let systemCostIndexOverride: Double?
  let materialMultiplier: Double?
  let jobCostMultiplier: Double?
  let facilityTaxRate: Double?
  let needsReview: Bool
  let warnings: [DomainWarning]
}

private struct JobKey: Hashable, Sendable {
  let productTypeID: Int64
  let activity: BlueprintActivityDefinition.Kind
  let me: Int
  let te: Int
  let facilityID: UUID?
  let blueprintSupplyJobID: UUID?
}

private struct BlueprintJobSlice: Sendable {
  let supplyJobID: UUID?
  let source: BlueprintSourceReference?
  let runs: Int
  let me: Int
  let te: Int

  static func fallback(runs: Int, me: Int, te: Int) -> BlueprintJobSlice {
    BlueprintJobSlice(
      supplyJobID: nil,
      source: nil,
      runs: max(0, runs),
      me: me,
      te: te
    )
  }
}

private struct PendingBlueprintJob: Sendable {
  let job: BlueprintManufacturingJob
  var remainingRuns: Int
}

private struct IndustrySystemIndexLookup: Sendable {
  private struct Key: Hashable, Sendable {
    let solarSystemID: Int64
    let activity: BlueprintActivityDefinition.Kind
  }

  private let values: [Key: Double]

  init(indices: [IndustrySystemIndex]) {
    var indexed: [Key: Double] = [:]
    indexed.reserveCapacity(indices.count)
    for index in indices {
      let key = Key(
        solarSystemID: index.solarSystemID,
        activity: index.activity
      )
      if indexed[key] == nil {
        indexed[key] = index.costIndex
      }
    }
    values = indexed
  }

  func costIndex(
    solarSystemID: Int64,
    activity: BlueprintActivityDefinition.Kind
  ) -> Double? {
    values[Key(solarSystemID: solarSystemID, activity: activity)]
  }
}

private struct BuildState: Sendable {
  var stock: [Int64: Int64]
  var required: [Int64: Int64] = [:]
  var stockUsed: [Int64: Int64] = [:]
  var toBuy: [Int64: Int64] = [:]
  var toProduce: [Int64: Int64] = [:]
  var procurement: [Int64: MaterialProcurementPreference] = [:]
  var nodes: [PlanNode] = []
  var jobDefinitions: [JobDefinition] = []
  var warnings: [DomainWarning] = []
  var blacklistWarningTypeIDs: Set<Int64> = []
  var stockShortfallWarningTypeIDs: Set<Int64> = []
  var invalidProductionPreferenceTypeIDs: Set<Int64> = []
  var explanations: [ExplanationEdge] = []
  var blueprintSupplyTypeIDs: Set<Int64> = []
  var pendingBlueprintJobs: [Int64: [PendingBlueprintJob]] = [:]
  var blueprintJobCursors: [Int64: Int] = [:]

  mutating func installBlueprintSupplyPlans(
    _ plans: [Int64: BlueprintSupplyPlan]
  ) {
    blueprintSupplyTypeIDs = Set(plans.keys)
    pendingBlueprintJobs = plans.mapValues { plan in
      plan.manufacturingJobs.map {
        PendingBlueprintJob(job: $0, remainingRuns: max(0, $0.runs))
      }
    }
    warnings.append(contentsOf: plans.values.flatMap(\.warnings))
  }

  mutating func consumeBlueprintJobs(
    blueprintTypeID: Int64,
    requiredRuns: Int,
    fallbackME: Int,
    fallbackTE: Int
  ) -> [BlueprintJobSlice] {
    guard blueprintSupplyTypeIDs.contains(blueprintTypeID) else {
      return [.fallback(runs: requiredRuns, me: fallbackME, te: fallbackTE)]
    }
    var remaining = max(0, requiredRuns)
    var slices: [BlueprintJobSlice] = []
    var jobs = pendingBlueprintJobs[blueprintTypeID, default: []]
    var cursor = blueprintJobCursors[blueprintTypeID, default: 0]
    while remaining > 0, cursor < jobs.count {
      let used = min(remaining, max(0, jobs[cursor].remainingRuns))
      if used > 0 {
        let job = jobs[cursor].job
        slices.append(
          BlueprintJobSlice(
            supplyJobID: job.id,
            source: job.allocation.source,
            runs: used,
            me: job.allocation.materialEfficiency,
            te: job.allocation.timeEfficiency
          )
        )
        jobs[cursor].remainingRuns -= used
        remaining -= used
      }
      if jobs[cursor].remainingRuns == 0 { cursor += 1 }
    }
    pendingBlueprintJobs[blueprintTypeID] = jobs
    blueprintJobCursors[blueprintTypeID] = cursor
    if remaining > 0 {
      warnings.append(
        DomainWarning(
          code: "industry.blueprint-supply-insufficient-runs",
          message:
            "The concrete Blueprint supply for type \(blueprintTypeID) is short by \(remaining) runs. Those runs remain unresolved.",
          severity: .blocking
        )
      )
      slices.append(
        .fallback(runs: remaining, me: fallbackME, te: fallbackTE)
      )
    }
    return slices
  }
}

extension Sequence {
  fileprivate func asyncMap<T>(
    _ transform: (Element) async throws -> T
  ) async rethrows -> [T] {
    var values: [T] = []
    for element in self {
      values.append(try await transform(element))
    }
    return values
  }
}
