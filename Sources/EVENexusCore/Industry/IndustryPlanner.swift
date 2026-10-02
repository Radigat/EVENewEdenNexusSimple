import Foundation

public struct IndustryPlanningContext: Sendable {
  public let manufacturingProfile: ManufacturingProfile
  public let reactionProfile: ReactionProfile?
  public let productionBasis: ProductionBasis?
  public let catalog: any IndustryCatalogQuerying
  public let market: MarketOrderSnapshot
  public let homeMarket: MarketOrderSnapshot?
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
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let homeSalesTaxRate: Double?
  public let homeBrokerFeeRate: Double?

  public init(
    manufacturingProfile: ManufacturingProfile,
    reactionProfile: ReactionProfile? = nil,
    productionBasis: ProductionBasis? = nil,
    catalog: any IndustryCatalogQuerying,
    market: MarketOrderSnapshot,
    homeMarket: MarketOrderSnapshot? = nil,
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
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil,
    homeSalesTaxRate: Double? = nil,
    homeBrokerFeeRate: Double? = nil
  ) {
    self.manufacturingProfile = manufacturingProfile
    self.reactionProfile = reactionProfile
    self.productionBasis = productionBasis
    self.catalog = catalog
    self.market = market
    self.homeMarket = homeMarket
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
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.homeSalesTaxRate = homeSalesTaxRate
    self.homeBrokerFeeRate = homeBrokerFeeRate
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
      warnings: context.inputWarnings + context.homeMarketWarnings
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
      requests: parsed.requests,
      context: context,
      state: state
    )
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
        materialEfficiency: isReaction ? nil : me,
        timeEfficiency: isReaction ? nil : te,
        blueprintTypeID: definition.blueprintTypeID,
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
    var replacementQuotes: [Int64: PriceQuote] = [:]
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
    for (typeID, quantity) in state.stockUsed.sorted(by: { $0.key < $1.key }) {
      let quote = JitaPriceEngine.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy,
        snapshot: context.market
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
      let quote = JitaPriceEngine.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: .materialBuy,
        snapshot: context.market
      )
      replacementQuotes[typeID] = quote
      warnings.append(contentsOf: quote.warnings)
      if let total = quote.total,
        (replacementMaterialCost + total).isFinite
      {
        replacementMaterialCost += total
      } else {
        materialCostComplete = false
      }
    }
    let materialCost = replacementMaterialCost
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
        analysis = try await makeOrBuyAnalysis(
          definition: definition,
          requiredQuantity: state.required[typeID, default: 0],
          context: context
        )
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
    let configuredHomeHub =
      context.productionBasis?.homeTradingLocation?.location
      ?? .legacy(
        name:
          context.productionBasis?.logistics.productionLocationName
          ?? "Home Hub"
      )
    let inboundLogistics = try await logisticsBreakdown(
      configuration: context.productionBasis?.logistics,
      materials: materials,
      requests: requests,
      nodes: state.nodes,
      mainHub: context.defaultPurchaseLocation,
      homeHub: configuredHomeHub,
      market: context.market,
      includeInboundMaterials:
        context.productionBasis?.logistics.includeInboundMaterials == true,
      includeOutboundProducts: false,
      catalog: context.catalog
    )
    warnings.append(contentsOf: inboundLogistics.warnings)
    let outboundLogistics = try await logisticsBreakdown(
      configuration: context.productionBasis?.logistics,
      materials: materials,
      requests: requests,
      nodes: state.nodes,
      mainHub: context.defaultPurchaseLocation,
      homeHub: configuredHomeHub,
      market: context.market,
      includeInboundMaterials: false,
      // Main-Hub sale scenarios always require the finished-product route.
      // This is scenario accounting, not the legacy optional profile flag.
      includeOutboundProducts: true,
      catalog: context.catalog
    )
    for warning in outboundLogistics.warnings
    where !warnings.contains(where: {
      $0.code == warning.code && $0.message == warning.message
    }) {
      warnings.append(warning)
    }
    let logisticsCost = inboundLogistics.cost
    let acceptedMaterialCost = materialCostComplete ? materialCost : nil
    let totalCost = IndustryCostBreakdown.total(
      materialCost: acceptedMaterialCost,
      blueprintCost: blueprintCost,
      installationCost: acceptedInstallation,
      logisticsCost: logisticsCost
    )
    let costBreakdown = IndustryCostBreakdown(
      materialCost: acceptedMaterialCost,
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
      logistics: inboundLogistics.breakdown,
      logisticsCost: logisticsCost,
      totalProductionCost: totalCost
    )
    let mainScenarioCost = Self.addingCosts(
      totalCost,
      outboundLogistics.cost
    )
    let mainSaleResults = saleScenarios(
      requests: requests,
      nodes: state.nodes,
      market: context.market,
      marketLocation: context.defaultPurchaseLocation,
      totalCost: mainScenarioCost,
      tax: context.salesTaxRate,
      broker: context.brokerFeeRate,
      outboundLogistics: outboundLogistics.breakdown,
      outboundLogisticsCost: outboundLogistics.cost
    )
    let homeSaleResults = context.homeMarket.map { homeMarket in
      saleScenarios(
        requests: requests,
        nodes: state.nodes,
        market: homeMarket,
        marketLocation: configuredHomeHub,
        totalCost: totalCost,
        tax: context.homeSalesTaxRate,
        broker: context.homeBrokerFeeRate,
        outboundLogistics: nil,
        outboundLogisticsCost: 0
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
    let priceDate = max(
      context.market.capturedAt,
      context.homeMarket?.capturedAt ?? context.market.capturedAt
    )
    var marketSnapshotIDs = [context.market.id]
    if let homeMarketID = context.homeMarket?.id,
      homeMarketID != context.market.id
    {
      marketSnapshotIDs.append(homeMarketID)
    }
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
      immediateSale: mainSaleResults.0,
      listedSale: mainSaleResults.1,
      homeImmediateSale: homeSaleResults?.0,
      homeListedSale: homeSaleResults?.1,
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
    nodes: [PlanNode],
    market: MarketOrderSnapshot,
    marketLocation: ProcurementLocation,
    totalCost: Double?,
    tax: Double?,
    broker: Double?,
    outboundLogistics: LogisticsCostBreakdown?,
    outboundLogisticsCost: Double?
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
        marketLocation: marketLocation,
        totalCost: totalCost,
        salesTaxRate: tax,
        brokerFeeRate: 0,
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
        outboundLogistics: outboundLogistics,
        outboundLogisticsCost: outboundLogisticsCost
      )
    )
  }

  private func result(
    scenario: PriceScenario,
    quotes: [PriceQuote],
    marketLocation: ProcurementLocation,
    totalCost: Double?,
    salesTaxRate: Double?,
    brokerFeeRate: Double?,
    outboundLogistics: LogisticsCostBreakdown?,
    outboundLogisticsCost: Double?
  ) -> SaleScenarioResult {
    let totals = quotes.compactMap(\.total)
    guard totals.count == quotes.count else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: nil,
        salesTax: nil,
        brokerFee: nil,
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
      salesTaxRate + brokerFeeRate < 1
    else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue:
          scenario == .immediateSale ? quotedRevenue : nil,
        salesTax: nil,
        brokerFee: scenario == .immediateSale ? 0 : nil,
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
    let netRevenue = grossRevenue - salesTax - brokerFee
    guard grossRevenue.isFinite, salesTax.isFinite, brokerFee.isFinite,
      netRevenue.isFinite, netRevenue >= 0
    else {
      return SaleScenarioResult(
        scenario: scenario,
        marketLocation: marketLocation,
        grossRevenue: nil,
        salesTax: nil,
        brokerFee: nil,
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
        salesTax: salesTax,
        brokerFee: brokerFee,
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
      salesTax: salesTax,
      brokerFee: brokerFee,
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

  private func logisticsBreakdown(
    configuration: LogisticsConfiguration?,
    materials: [MaterialRequirement],
    requests: [ProductionRequestLine],
    nodes: [PlanNode],
    mainHub: ProcurementLocation,
    homeHub: ProcurementLocation,
    market: MarketOrderSnapshot,
    includeInboundMaterials: Bool,
    includeOutboundProducts: Bool,
    catalog: any IndustryCatalogQuerying
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
      var parentByChild: [UUID: PlanNode] = [:]
      for parent in nodes {
        for childID in parent.children {
          parentByChild[childID] = parent
        }
      }
      let materialsByType = Dictionary(
        uniqueKeysWithValues: materials.map { ($0.typeID, $0) }
      )
      let groupedPurchases = Dictionary(
        grouping: nodes.filter { $0.action == .buy }
      ) { node in
        acceptedLogisticsFacilityName(
          parentByChild[node.id]?.facilityName,
          fallback: configuration.productionLocationName
        )
      }
      for (destination, purchases) in groupedPurchases.sorted(by: {
        $0.key < $1.key
      }) where mainHub.name != destination {
        let result = try await logisticsLegs(
          kind: .inboundMaterials,
          origin: mainHub.name,
          destination: destination,
          cargo: purchases.map { purchase in
            let unitPrice = materialsByType[purchase.typeID]?
              .replacementQuote?.weightedUnitPrice
            let collateral: Double?
            if let unitPrice, unitPrice.isFinite, unitPrice >= 0 {
              let total = unitPrice * Double(purchase.requiredQuantity)
              collateral = total.isFinite ? total : nil
            } else {
              collateral = nil
            }
            return (
              purchase.typeID,
              purchase.requiredQuantity,
              collateral
            )
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
          let quote = MarketPriceEngine.quote(
            typeID: product.typeID,
            quantity: product.requiredQuantity,
            scenario: .materialBuy,
            snapshot: market
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
    context: IndustryPlanningContext
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
    let purchaseQuote = MarketPriceEngine.quote(
      typeID: definition.productTypeID,
      quantity: requiredQuantity,
      scenario: .materialBuy,
      snapshot: context.market
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
      let quote = MarketPriceEngine.quote(
        typeID: input.typeID,
        quantity: input.quantity,
        scenario: .materialBuy,
        snapshot: context.market
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
      context: context
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
    context: IndustryPlanningContext
  ) -> (cost: Double?, warnings: [DomainWarning]) {
    guard !facility.needsReview,
      let systemID = facility.systemID,
      let bonusMultiplier = facility.jobCostMultiplier,
      let facilityTax = facility.facilityTaxRate
    else { return (nil, facility.warnings) }
    guard
      let index = facility.systemCostIndexOverride
        ?? context.systemIndices.first(where: {
          $0.solarSystemID == systemID
            && $0.activity == definition.activity.kind
        })?.costIndex
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
    var acceptedCargo: [LogisticsCargoItem] = []
    acceptedCargo.reserveCapacity(cargo.count)
    for item in cargo {
      acceptedCargo.append(
        LogisticsCargoItem(
          typeID: item.typeID,
          quantity: item.quantity,
          collateral: item.collateral,
          packagedVolumePerUnit: try await catalog.packagedVolume(
            typeID: item.typeID
          )
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
