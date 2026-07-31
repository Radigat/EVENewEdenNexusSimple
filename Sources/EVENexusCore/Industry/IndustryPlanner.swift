import Foundation

public struct IndustryPlanningContext: Sendable {
  public let manufacturingProfile: ManufacturingProfile
  public let reactionProfile: ReactionProfile?
  public let productionBasis: ProductionBasis?
  public let catalog: any IndustryCatalogQuerying
  public let market: MarketOrderSnapshot
  public let adjustedPrices: [Int64: AdjustedPrice]
  public let systemIndices: [IndustrySystemIndex]
  public let availableStock: [Int64: Int64]
  public let assetSource: StockSource?
  public let sdeBuild: Int
  public let snapshotIDs: [UUID]
  public let inputWarnings: [DomainWarning]
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?

  public init(
    manufacturingProfile: ManufacturingProfile,
    reactionProfile: ReactionProfile? = nil,
    productionBasis: ProductionBasis? = nil,
    catalog: any IndustryCatalogQuerying,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    systemIndices: [IndustrySystemIndex],
    availableStock: [Int64: Int64] = [:],
    assetSource: StockSource? = nil,
    sdeBuild: Int,
    snapshotIDs: [UUID] = [],
    inputWarnings: [DomainWarning] = [],
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil
  ) {
    self.manufacturingProfile = manufacturingProfile
    self.reactionProfile = reactionProfile
    self.productionBasis = productionBasis
    self.catalog = catalog
    self.market = market
    self.adjustedPrices = adjustedPrices
    self.systemIndices = systemIndices
    self.availableStock = availableStock
    self.assetSource = assetSource
    self.sdeBuild = sdeBuild
    self.snapshotIDs = snapshotIDs
    self.inputWarnings = inputWarnings
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
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
}

public struct IndustryPlanner: Sendable {
  public init() {}

  public func requiredMarketTypeIDs(
    input: String,
    catalog: any IndustryCatalogQuerying
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
    return result
  }

  public func plan(
    input: String,
    context: IndustryPlanningContext
  ) async throws -> IndustryPlanSnapshot {
    let parsed = ProductionInputParser.parse(input)
    guard parsed.errors.isEmpty else {
      throw IndustryPlannerError.invalidInput(parsed.errors)
    }

    var state = BuildState(
      stock: context.availableStock,
      warnings: context.inputWarnings
    )
    for request in parsed.requests {
      guard
        let typeID = try await context.catalog.typeID(
          named: request.productName
        )
      else {
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
      requests: parsed.requests,
      context: context,
      state: state
    )
  }

  private func expand(
    definition: BlueprintDefinition,
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
    let me = isReaction ? 0 : requestedME
    let te = isReaction ? 0 : requestedTE
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
      let required =
        isReaction
        ? Self.scaledReactionQuantity(
          rawRequired: rawRequired,
          runs: requestedRuns,
          multiplier:
            context.reactionProfile?.effectiveMaterialMultiplier ?? 1
        )
        : Self.manufacturingMaterialQuantity(
          baseQuantity: material.quantity,
          runs: requestedRuns,
          materialEfficiency: me,
          facilityMultiplier:
            facilitySelection?.materialMultiplier
            ?? context.manufacturingProfile.effectiveMaterialMultiplier
        )
      state.required[material.typeID] = Self.saturatedAdd(
        state.required[material.typeID, default: 0],
        required
      )
      let available = state.stock[material.typeID, default: 0]
      let fromStock = min(available, required)
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
            name: try await context.catalog.typeName(
              id: material.typeID
            ) ?? "Type \(material.typeID)",
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
      guard remaining > 0 else { continue }

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
      if let childDefinition = try await context.catalog
        .productionDefinition(productTypeID: material.typeID),
        childDefinition.activity.kind != .invention,
        !isBlacklisted
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
        if state.nodes.count > before {
          childIDs.append(state.nodes[before].id)
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
              message: "\(childName) is bought.",
              severity: .information
            )
          )
        }
        state.toBuy[material.typeID] = Self.saturatedAdd(
          state.toBuy[material.typeID, default: 0],
          remaining
        )
        let buyID = UUID()
        childIDs.append(buyID)
        state.nodes.append(
          PlanNode(
            id: buyID,
            typeID: material.typeID,
            name: childName,
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
        requiredQuantity: producedQuantity,
        action: .produce,
        activity: definition.activity.kind,
        runs: requestedRuns,
        materialEfficiency: isReaction ? nil : me,
        timeEfficiency: isReaction ? nil : te,
        facilityName:
          isReaction
          ? context.reactionProfile?.structureName
          : facilitySelection?.structureName
            ?? context.manufacturingProfile.structureName,
        manufacturingCategory: manufacturingCategory,
        children: childIDs,
        topLevelRequestID: topLevelID
      )
    )
    state.jobDefinitions.append(
      JobDefinition(
        definition: definition,
        runs: requestedRuns,
        me: me,
        te: te,
        isTopLevel: path.isEmpty,
        facilitySelection: facilitySelection,
        selectedStructure: selectedStructure
      )
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
    state: BuildState
  ) async throws -> IndustryPlanSnapshot {
    var purchaseQuotes: [Int64: PriceQuote] = [:]
    var stockQuotes: [Int64: PriceQuote] = [:]
    var warnings = state.warnings
    var purchasedMaterialCost = 0.0
    var purchasedMaterialCostComplete = true
    for (typeID, quantity) in state.toBuy.sorted(by: { $0.key < $1.key }) {
      let quote = JitaPriceEngine.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy,
        snapshot: context.market
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
    var stockMaterialCost = 0.0
    var stockMaterialCostComplete = true
    for (typeID, quantity) in state.stockUsed.sorted(by: { $0.key < $1.key }) {
      let quote = JitaPriceEngine.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy,
        snapshot: context.market
      )
      stockQuotes[typeID] = quote
      warnings.append(contentsOf: quote.warnings)
      if let total = quote.total {
        let updatedCost = stockMaterialCost + total
        if updatedCost.isFinite, updatedCost >= 0 {
          stockMaterialCost = updatedCost
        } else {
          stockMaterialCostComplete = false
        }
      } else {
        stockMaterialCostComplete = false
      }
    }
    let materialCostComplete =
      purchasedMaterialCostComplete && stockMaterialCostComplete
    let materialCost = purchasedMaterialCost + stockMaterialCost

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
        ? context.productionBasis?.reactionSystem
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
      let index =
        basisSystem?.costIndexOverride
        ?? context.systemIndices.first {
          $0.solarSystemID == systemID
            && $0.activity == activity
        }?.costIndex ?? 0
      if basisSystem?.costIndexOverride == nil
        && !context.systemIndices.contains(where: {
          $0.solarSystemID == systemID
            && $0.activity == activity
        })
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
          activity: activity,
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
          manufacturingCategory: job.facilitySelection?.category
        )
      )
    }
    let configuredScheduling = context.productionBasis?.scheduling
    let makespan = max(
      Self.slotMakespan(
        durations: manufacturingDurations,
        slots: configuredScheduling?.manufacturingSlots ?? 1
      ),
      Self.slotMakespan(
        durations: reactionDurations,
        slots: configuredScheduling?.reactionSlots ?? 1
      )
    )
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
          sourceCategory: classification?.categoryName,
          sourceGroup: classification?.groupName,
          productionActivity: productionActivity
        )
      )
    }
    materials.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name)
        == .orderedAscending
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
    let blueprintEntries: [BlueprintCostEntry] = requests.compactMap {
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
    let requestsWithoutBlueprintCost = requests.compactMap { request in
      request.blueprintCostISK == nil ? request.id : nil
    }
    let blueprintCost = blueprintEntries.reduce(0) { $0 + $1.amount }
    let blueprintCosts = BlueprintCostBreakdown(
      entries: blueprintEntries,
      requestsWithoutEnteredCost: requestsWithoutBlueprintCost,
      total: blueprintCost
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
    let logisticsResult = try await logisticsBreakdown(
      configuration: context.productionBasis?.logistics,
      materials: materials,
      requests: requests,
      nodes: state.nodes,
      catalog: context.catalog,
      market: context.market
    )
    warnings.append(contentsOf: logisticsResult.warnings)
    let logisticsIsEnabled =
      context.productionBasis?.logistics.isEnabled == true
    let logisticsComplete =
      !logisticsIsEnabled || logisticsResult.breakdown != nil
    let logisticsCost =
      logisticsIsEnabled ? logisticsResult.breakdown?.total : 0
    let totalCost =
      materialCostComplete && logisticsComplete
      ? acceptedInstallation.flatMap { installation in
        logisticsCost.map {
          materialCost + blueprintCost + installation + $0
        }
      }
      : nil
    let costBreakdown = IndustryCostBreakdown(
      materialCost: materialCostComplete ? materialCost : nil,
      purchasedMaterialCost:
        purchasedMaterialCostComplete ? purchasedMaterialCost : nil,
      stockMaterialCost:
        stockMaterialCostComplete ? stockMaterialCost : nil,
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
      logistics: logisticsResult.breakdown,
      totalProductionCost: totalCost
    )
    let saleResults = saleScenarios(
      requests: requests,
      nodes: state.nodes,
      market: context.market,
      totalCost: totalCost,
      tax: context.salesTaxRate,
      broker: context.brokerFeeRate
    )
    let source =
      context.assetSource
      ?? StockSource(
        kind: .manual,
        reference: "manual"
      )
    let allocations = state.stockUsed.map {
      StockAllocation(typeID: $0.key, quantity: $0.value, source: source)
    }
    let priceDate = context.market.capturedAt
    return IndustryPlanSnapshot(
      id: UUID(),
      createdAt: .now,
      requests: requests,
      nodes: state.nodes,
      materials: materials,
      stockAllocations: allocations,
      jobs: jobs,
      materialCost: materialCostComplete ? materialCost : nil,
      installationCost: acceptedInstallation,
      costBreakdown: costBreakdown,
      immediateSale: saleResults.0,
      listedSale: saleResults.1,
      totalJobSeconds: totalSeconds,
      makespanSeconds: makespan,
      warnings: warnings,
      explanations: state.explanations,
      provenance: PlanProvenance(
        sdeBuild: context.sdeBuild,
        esiCompatibilityDate: EVEConstants.esiCompatibilityDate,
        snapshotIDs: context.snapshotIDs + [context.market.id],
        priceTimestamp: priceDate,
        ruleVersion: IndustryRuleSet.current.version
      )
    )
  }

  private func saleScenarios(
    requests: [ProductionRequestLine],
    nodes: [PlanNode],
    market: MarketOrderSnapshot,
    totalCost: Double?,
    tax: Double?,
    broker: Double?
  ) -> (SaleScenarioResult, SaleScenarioResult) {
    var immediateQuotes: [PriceQuote] = []
    var listedQuotes: [PriceQuote] = []
    for request in requests {
      guard
        let node = nodes.last(where: {
          $0.topLevelRequestID == request.id && $0.action == .produce
        })
      else { continue }
      immediateQuotes.append(
        JitaPriceEngine.quote(
          typeID: node.typeID,
          quantity: node.requiredQuantity,
          scenario: .immediateSale,
          snapshot: market
        )
      )
      listedQuotes.append(
        JitaPriceEngine.quote(
          typeID: node.typeID,
          quantity: node.requiredQuantity,
          scenario: .listedSale,
          snapshot: market,
          salesTaxRate: tax,
          brokerFeeRate: broker
        )
      )
    }
    return (
      result(
        scenario: .immediateSale,
        quotes: immediateQuotes,
        totalCost: totalCost,
        salesTaxRate: tax,
        brokerFeeRate: 0
      ),
      result(
        scenario: .listedSale,
        quotes: listedQuotes,
        totalCost: totalCost,
        salesTaxRate: tax,
        brokerFeeRate: broker
      )
    )
  }

  private func result(
    scenario: PriceScenario,
    quotes: [PriceQuote],
    totalCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) -> SaleScenarioResult {
    let totals = quotes.compactMap(\.total)
    guard totals.count == quotes.count else {
      return SaleScenarioResult(
        scenario: scenario,
        grossRevenue: nil,
        salesTax: nil,
        brokerFee: nil,
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
      salesTaxRate + brokerFeeRate < 1
    else {
      return SaleScenarioResult(
        scenario: scenario,
        grossRevenue:
          scenario == .immediateSale ? quotedRevenue : nil,
        salesTax: nil,
        brokerFee: scenario == .immediateSale ? 0 : nil,
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
    let netRevenue = grossRevenue - salesTax - brokerFee
    guard grossRevenue.isFinite, salesTax.isFinite, brokerFee.isFinite,
      netRevenue.isFinite, netRevenue >= 0
    else {
      return SaleScenarioResult(
        scenario: scenario,
        grossRevenue: nil,
        salesTax: nil,
        brokerFee: nil,
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
        grossRevenue: grossRevenue,
        salesTax: salesTax,
        brokerFee: brokerFee,
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
      grossRevenue: grossRevenue,
      salesTax: salesTax,
      brokerFee: brokerFee,
      grossOrNetRevenue: netRevenue,
      profit: profit,
      margin: netRevenue == 0 ? nil : profit / netRevenue,
      roi: totalCost == 0 ? nil : profit / totalCost,
      quotes: quotes
    )
  }

  private func logisticsBreakdown(
    configuration: LogisticsConfiguration?,
    materials: [MaterialRequirement],
    requests: [ProductionRequestLine],
    nodes: [PlanNode],
    catalog: any IndustryCatalogQuerying,
    market: MarketOrderSnapshot
  ) async throws -> (
    breakdown: LogisticsCostBreakdown?,
    warnings: [DomainWarning]
  ) {
    guard let configuration, configuration.isEnabled else {
      return (nil, [])
    }
    guard let rate = configuration.effectiveISKPerCubicMeter else {
      return (
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

    if configuration.includeInboundMaterials {
      let cargo = materials.filter { $0.toBuy > 0 }
      let result = try await logisticsLegs(
        kind: .inboundMaterials,
        origin: configuration.marketLocationName,
        destination: configuration.productionLocationName,
        cargo: cargo.map {
          ($0.typeID, $0.toBuy, $0.quote?.total)
        },
        rate: rate,
        maximumContractVolume: maximumContractVolume,
        catalog: catalog
      )
      legs.append(contentsOf: result.legs)
      warnings.append(contentsOf: result.warnings)
    }

    if configuration.includeOutboundProducts {
      let topLevelProducts = requests.compactMap { request in
        nodes.last {
          $0.topLevelRequestID == request.id && $0.action == .produce
        }
      }
      var cargo: [(Int64, Int64, Double?)] = []
      for node in topLevelProducts {
        let collateralQuote = JitaPriceEngine.quote(
          typeID: node.typeID,
          quantity: node.requiredQuantity,
          scenario: .materialBuy,
          snapshot: market
        )
        warnings.append(contentsOf: collateralQuote.warnings)
        cargo.append(
          (node.typeID, node.requiredQuantity, collateralQuote.total)
        )
      }
      let result = try await logisticsLegs(
        kind: .outboundProducts,
        origin: configuration.productionLocationName,
        destination: configuration.marketLocationName,
        cargo: cargo,
        rate: rate,
        maximumContractVolume: maximumContractVolume,
        catalog: catalog
      )
      legs.append(contentsOf: result.legs)
      warnings.append(contentsOf: result.warnings)
    }

    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return (nil, warnings)
    }
    let total = legs.reduce(0) { $0 + $1.roundedCharge }
    guard total.isFinite, total >= 0 else {
      return (
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
      warnings
    )
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
    guard !cargo.isEmpty else { return ([], []) }
    struct CargoItem {
      let typeID: Int64
      let quantity: Int64
      let unitVolume: Double
      let unitCollateral: Double
    }
    struct ContractDraft {
      var volume: Double
      var collateral: Double
    }
    var cargoItems: [CargoItem] = []
    var totalVolume = 0.0
    var warnings: [DomainWarning] = []
    for item in cargo {
      guard item.quantity > 0,
        let unitVolume = try await catalog.packagedVolume(
          typeID: item.typeID
        ),
        unitVolume.isFinite,
        unitVolume >= 0
      else {
        warnings.append(
          DomainWarning(
            code: "logistics.missing-packaged-volume",
            message:
              "A packaged SDE volume required for \(kind.displayName.lowercased()) is unavailable.",
            severity: .blocking
          )
        )
        continue
      }
      let itemVolume = unitVolume * Double(item.quantity)
      guard itemVolume.isFinite, itemVolume >= 0 else {
        warnings.append(
          DomainWarning(
            code: "logistics.invalid-volume",
            message: "A logistics cargo volume exceeded safe numeric limits.",
            severity: .blocking
          )
        )
        continue
      }
      totalVolume += itemVolume
      guard let itemCollateral = item.collateral,
        itemCollateral.isFinite,
        itemCollateral >= 0
      else {
        warnings.append(
          DomainWarning(
            code: "logistics.missing-collateral",
            message:
              "Accurate market collateral for \(kind.displayName.lowercased()) is unavailable.",
            severity: .blocking
          )
        )
        continue
      }
      guard unitVolume <= maximumContractVolume else {
        warnings.append(
          DomainWarning(
            code: "logistics.single-item-volume-exceeded",
            message:
              "Type \(item.typeID) has a packaged volume of \(unitVolume.formatted()) m³ and cannot fit into the configured \(maximumContractVolume.formatted()) m³ contract limit.",
            severity: .blocking
          )
        )
        continue
      }
      cargoItems.append(
        CargoItem(
          typeID: item.typeID,
          quantity: item.quantity,
          unitVolume: unitVolume,
          unitCollateral: itemCollateral / Double(item.quantity)
        )
      )
    }
    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return ([], warnings)
    }
    guard totalVolume.isFinite, totalVolume >= 0 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.invalid-volume",
            message: "A logistics cargo volume exceeded safe numeric limits.",
            severity: .blocking
          )
        ]
      )
    }
    let minimumContractCount = ceil(totalVolume / maximumContractVolume)
    guard minimumContractCount <= 100_000 else {
      return (
        [],
        [
          DomainWarning(
            code: "logistics.contract-count-limit",
            message:
              "\(kind.displayName) would require more than 100,000 contracts and exceeds the planning safety limit.",
            severity: .blocking
          )
        ]
      )
    }
    cargoItems.sort {
      if $0.unitVolume != $1.unitVolume {
        return $0.unitVolume > $1.unitVolume
      }
      return $0.typeID < $1.typeID
    }
    var contracts: [ContractDraft] = []
    let tolerance = max(1, maximumContractVolume) * 1e-12
    for item in cargoItems {
      var remaining = item.quantity
      if item.unitVolume == 0 {
        if contracts.isEmpty {
          contracts.append(ContractDraft(volume: 0, collateral: 0))
        }
        contracts[0].collateral += item.unitCollateral * Double(remaining)
        continue
      }
      while remaining > 0 {
        var selectedIndex: Int?
        var acceptedQuantity: Int64 = 0
        for index in contracts.indices {
          let available =
            maximumContractVolume - contracts[index].volume
          let capacity = Int64(
            min(
              Double(remaining),
              floor(max(0, available + tolerance) / item.unitVolume)
            )
          )
          if capacity > 0 {
            selectedIndex = index
            acceptedQuantity = min(remaining, capacity)
            break
          }
        }
        if selectedIndex == nil {
          guard contracts.count < 100_000 else {
            return (
              [],
              warnings + [
                DomainWarning(
                  code: "logistics.contract-count-limit",
                  message:
                    "\(kind.displayName) requires more than 100,000 contracts and exceeds the planning safety limit.",
                  severity: .blocking
                )
              ]
            )
          }
          contracts.append(ContractDraft(volume: 0, collateral: 0))
          selectedIndex = contracts.index(before: contracts.endIndex)
          acceptedQuantity = min(
            remaining,
            max(
              1,
              Int64(
                min(
                  Double(remaining),
                  floor(
                    (maximumContractVolume + tolerance) / item.unitVolume
                  )
                )
              )
            )
          )
        }
        guard let selectedIndex else { continue }
        let quantity = acceptedQuantity
        contracts[selectedIndex].volume +=
          item.unitVolume * Double(quantity)
        contracts[selectedIndex].collateral +=
          item.unitCollateral * Double(quantity)
        remaining -= quantity
      }
    }

    let contractCount = contracts.count
    if contractCount > 1 {
      warnings.append(
        DomainWarning(
          code: "logistics.contracts-split",
          message:
            "\(kind.displayName) is automatically split into \(contractCount) contracts to stay within \(maximumContractVolume.formatted()) m³ per contract.",
          severity: .information
        )
      )
    }
    var legs: [LogisticsCostLeg] = []
    for (offset, contract) in contracts.enumerated() {
      let volumeCharge = contract.volume * rate
      let collateralCharge =
        contract.collateral * LogisticsConfiguration.collateralRate
      let chargedBy: LogisticsChargeBasis =
        volumeCharge >= collateralCharge ? .volume : .collateral
      let unroundedCharge = max(volumeCharge, collateralCharge)
      let roundedCharge =
        ceil(unroundedCharge / LogisticsConfiguration.roundingIncrement)
        * LogisticsConfiguration.roundingIncrement
      guard volumeCharge.isFinite, collateralCharge.isFinite,
        roundedCharge.isFinite, roundedCharge >= 0
      else {
        return (
          [],
          warnings + [
            DomainWarning(
              code: "logistics.invalid-charge",
              message: "A logistics charge exceeded safe numeric limits.",
              severity: .blocking
            )
          ]
        )
      }
      legs.append(
        LogisticsCostLeg(
          kind: kind,
          origin: origin,
          destination: destination,
          contractNumber: offset + 1,
          contractCount: contractCount,
          cargoVolumeM3: contract.volume,
          collateral: contract.collateral,
          volumeCharge: volumeCharge,
          collateralCharge: collateralCharge,
          chargedBy: chargedBy,
          unroundedCharge: unroundedCharge,
          roundedCharge: roundedCharge
        )
      )
    }
    return (legs, warnings)
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
        facilityID: job.facilitySelection?.structureID
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
          selectedStructure: existing.selectedStructure
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
}

private struct JobDefinition: Sendable {
  let definition: BlueprintDefinition
  let runs: Int
  let me: Int
  let te: Int
  let isTopLevel: Bool
  let facilitySelection: ProductionFacilitySelection?
  let selectedStructure: ConfiguredIndustryStructure?
}

private struct JobKey: Hashable, Sendable {
  let productTypeID: Int64
  let activity: BlueprintActivityDefinition.Kind
  let me: Int
  let te: Int
  let facilityID: UUID?
}

private struct BuildState: Sendable {
  var stock: [Int64: Int64]
  var required: [Int64: Int64] = [:]
  var stockUsed: [Int64: Int64] = [:]
  var toBuy: [Int64: Int64] = [:]
  var toProduce: [Int64: Int64] = [:]
  var nodes: [PlanNode] = []
  var jobDefinitions: [JobDefinition] = []
  var warnings: [DomainWarning] = []
  var blacklistWarningTypeIDs: Set<Int64> = []
  var explanations: [ExplanationEdge] = []
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
