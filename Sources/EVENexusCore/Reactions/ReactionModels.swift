import Foundation

public enum CandidateReadiness: String, Codable, Sendable {
  case ready
  case needsReview
  case unsupported
}

public struct ReactionCandidate: Identifiable, Codable, Sendable {
  public let id: UUID
  public let recipe: BlueprintDefinition
  public let runs: Int
  public let securityBand: SecurityBand
  public let readiness: CandidateReadiness
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    recipe: BlueprintDefinition,
    runs: Int,
    securityBand: SecurityBand,
    readiness: CandidateReadiness,
    warnings: [DomainWarning] = []
  ) {
    self.id = id
    self.recipe = recipe
    self.runs = runs
    self.securityBand = securityBand
    self.readiness = readiness
    self.warnings = warnings
  }
}

public enum ReactionAnalysisBasis: String, Codable, Sendable {
  case configuredFacility
  case materialOnlyBaseline
}

public enum ReactionValueStatus: String, Codable, CaseIterable, Sendable {
  case positive
  case negative
  case neutral
  case unavailable
}

public enum ReactionJobRules {
  /// EVE industry jobs are limited to 30 days unless one run already takes
  /// longer; that single run remains valid. Reaction formulas themselves have
  /// unlimited uses, so the run limit must be derived from the formula duration
  /// and the effective time multiplier instead of a global constant.
  public static let maximumJobDurationSeconds: Int64 = 30 * 24 * 60 * 60

  /// The fastest currently published neutral SDE reaction takes six minutes.
  /// This is a safe initial UI bound until the active catalog has been analyzed.
  public static let neutralMaximumSelectableRuns = 7_200

  public static func maximumRunsPerJob(
    baseDurationSeconds: Int64,
    timeMultiplier: Double
  ) -> Int {
    guard baseDurationSeconds > 0,
      timeMultiplier.isFinite,
      timeMultiplier > 0
    else { return 1 }
    let effectiveSeconds = Double(baseDurationSeconds) * timeMultiplier
    guard effectiveSeconds.isFinite, effectiveSeconds > 0 else { return 1 }
    let runs = floor(Double(maximumJobDurationSeconds) / effectiveSeconds)
    guard runs.isFinite, runs >= 1 else { return 1 }
    return runs >= Double(Int.max) ? Int.max : Int(runs)
  }
}

public struct ReactionFacilityCostContext: Codable, Sendable {
  public let name: String
  public let materialMultiplier: Double
  public let timeMultiplier: Double
  public let jobCostMultiplier: Double
  public let facilityTaxRate: Double
  public let systemCostIndex: Double
  public let sccSurchargeRate: Double
  public let alphaSurchargeRate: Double
  public let ruleVersion: String

  public init(
    name: String,
    materialMultiplier: Double,
    timeMultiplier: Double,
    jobCostMultiplier: Double,
    facilityTaxRate: Double,
    systemCostIndex: Double,
    sccSurchargeRate: Double,
    alphaSurchargeRate: Double,
    ruleVersion: String
  ) {
    self.name = name
    self.materialMultiplier = materialMultiplier
    self.timeMultiplier = timeMultiplier
    self.jobCostMultiplier = jobCostMultiplier
    self.facilityTaxRate = facilityTaxRate
    self.systemCostIndex = systemCostIndex
    self.sccSurchargeRate = sccSurchargeRate
    self.alphaSurchargeRate = alphaSurchargeRate
    self.ruleVersion = ruleVersion
  }
}

public struct ReactionLogisticsCostContext: Sendable {
  public let configuration: LogisticsConfiguration
  public let origin: ProcurementLocation
  public let destinationName: String
  public let destinationLocationID: Int64?
  public let packagedVolumes: [Int64: Double]

  public init(
    configuration: LogisticsConfiguration,
    origin: ProcurementLocation,
    destinationName: String,
    destinationLocationID: Int64?,
    packagedVolumes: [Int64: Double]
  ) {
    self.configuration = configuration
    self.origin = origin
    self.destinationName = destinationName
    self.destinationLocationID = destinationLocationID
    self.packagedVolumes = packagedVolumes
  }
}

public struct ReactionMaterialValuation: Identifiable, Codable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let quantity: Int64
  public let quote: PriceQuote
}

/// One node of a traced reaction supply: bought at the market or built from
/// its children. `cost` is the node's own estimate before transport.
public struct ReactionSupplyNode: Identifiable, Codable, Sendable {
  public var id: String { "\(typeID)-\(quantity)" }
  public let typeID: Int64
  public let name: String
  public let quantity: Int64
  public let isBuilt: Bool
  public let cost: Double?
  /// Installation and reaction costs of this node and everything below it.
  public let installationCost: Double
  public let children: [ReactionSupplyNode]

  public init(
    typeID: Int64,
    name: String,
    quantity: Int64,
    isBuilt: Bool,
    cost: Double?,
    installationCost: Double,
    children: [ReactionSupplyNode]
  ) {
    self.typeID = typeID
    self.name = name
    self.quantity = quantity
    self.isBuilt = isBuilt
    self.cost = cost
    self.installationCost = installationCost
    self.children = children
  }
}

public struct ReactionSupplyTreeLine: Identifiable, Sendable {
  public let id: String
  public let depth: Int
  public let node: ReactionSupplyNode
}

public enum ReactionSupplyVariantKind: String, Codable, CaseIterable, Sendable {
  /// Direct inputs bought at the market; the classic reaction calculation.
  case intermediatesBought
  /// Every node with a complete self-build is built down to its raw materials.
  case fullChain
  /// The cheapest complete supply found.
  case cheapest
}

public struct ReactionSupplyVariant: Codable, Sendable {
  public let kind: ReactionSupplyVariantKind
  public let nodes: [ReactionSupplyNode]
  /// The summed shopping list, priced together against the order book.
  public let purchases: [ReactionMaterialValuation]
  public let materialCost: Double?
  public let logisticsCost: Double?
  /// Final reaction job plus every built intermediate job.
  public let installationCost: Double?
  public let totalCost: Double?
  /// Built intermediate jobs, without the final reaction job.
  public let builtJobCount: Int

  /// The supply tree in display order, parents directly above their children.
  public var treeLines: [ReactionSupplyTreeLine] {
    func lines(
      _ nodes: [ReactionSupplyNode],
      depth: Int,
      path: String
    ) -> [ReactionSupplyTreeLine] {
      nodes.flatMap { node -> [ReactionSupplyTreeLine] in
        let id = path + "/" + node.id
        return [ReactionSupplyTreeLine(id: id, depth: depth, node: node)]
          + lines(node.children, depth: depth + 1, path: id)
      }
    }
    return lines(nodes, depth: 0, path: "")
  }
}

public struct ReactionSupplyChainComparison: Codable, Sendable {
  public let directPurchaseTotal: Double?
  public let intermediatesBought: ReactionSupplyVariant
  public let fullChain: ReactionSupplyVariant
  /// `nil` when no supply is completely computable; never treated as zero.
  public let cheapest: ReactionSupplyVariant?

  public func variant(
    _ kind: ReactionSupplyVariantKind
  ) -> ReactionSupplyVariant? {
    switch kind {
    case .intermediatesBought: intermediatesBought
    case .fullChain: fullChain
    case .cheapest: cheapest
    }
  }

  /// Saving against buying the output directly; negative when buying is cheaper.
  public func savingsAgainstDirectPurchase(
    _ variant: ReactionSupplyVariant
  ) -> Double? {
    guard let directPurchaseTotal, let total = variant.totalCost else {
      return nil
    }
    let result = directPurchaseTotal - total
    return result.isFinite ? result : nil
  }
}

/// Recipes and rules for tracing reaction inputs down to their raw materials,
/// the same ones as the Planner's "build intermediates yourself" estimate.
public struct ReactionSupplyChainContext: Sendable {
  public let manufacturing: [BlueprintDefinition]
  public let facilities: [ManufacturingCategory: ManufacturingOpportunityFacilityContext]
  public let intermediateMaterialEfficiency: Int
  public let blacklist: ProductionBlacklistConfiguration

  public init(
    manufacturing: [BlueprintDefinition],
    facilities: [ManufacturingCategory: ManufacturingOpportunityFacilityContext],
    intermediateMaterialEfficiency: Int,
    blacklist: ProductionBlacklistConfiguration
  ) {
    self.manufacturing = manufacturing
    self.facilities = facilities
    self.intermediateMaterialEfficiency = intermediateMaterialEfficiency
    self.blacklist = blacklist
  }

  /// Every type a reaction's supply chain can touch, at any depth.
  public static func requiredTypeIDs(
    reactions: [BlueprintDefinition],
    manufacturing: [BlueprintDefinition]
  ) -> Set<Int64> {
    let recipes = Dictionary(
      grouping: (manufacturing + reactions).filter {
        !$0.activity.materials.isEmpty
      },
      by: \.productTypeID
    )
    var result = Set<Int64>()
    var pending = reactions.flatMap { definition in
      [definition.productTypeID]
        + definition.activity.materials.map(\.typeID)
        + definition.activity.products.map(\.typeID)
    }
    while let typeID = pending.popLast() {
      guard result.insert(typeID).inserted else { continue }
      for recipe in recipes[typeID] ?? [] {
        pending.append(contentsOf: recipe.activity.materials.map(\.typeID))
      }
    }
    return result
  }
}

public struct ReactionAnalysisRow: Identifiable, Codable, Sendable {
  public var id: Int64 { blueprintTypeID }
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let productName: String
  public let categoryName: String
  public let groupName: String
  public let runs: Int
  public let inputs: [ReactionMaterialValuation]
  public let outputs: [ReactionMaterialValuation]
  public var materialCost: Double?
  public var inputLogisticsCost: Double?
  public var installationCost: Double?
  public var evaluatedCost: Double?
  public let outputBuyCost: Double?
  public let outputPurchaseLogisticsCost: Double?
  public let outputPurchaseTotalCost: Double?
  public let immediateSaleRevenue: Double?
  public var makeOrBuySavings: Double?
  public var valueCreation: Double?
  public var valueCreationMargin: Double?
  public let durationSeconds: Int64
  public let maximumRunsPerJob: Int
  public let basis: ReactionAnalysisBasis
  public let warnings: [DomainWarning]
  public var supplyChain: ReactionSupplyChainComparison? = nil

  public var valueStatus: ReactionValueStatus {
    guard let valueCreation, valueCreation.isFinite else {
      return .unavailable
    }
    if valueCreation > 0 { return .positive }
    if valueCreation < 0 { return .negative }
    return .neutral
  }

  public var makeIsCheaperThanBuy: Bool? {
    guard let makeOrBuySavings else { return nil }
    return makeOrBuySavings >= 0
  }

  public var immediateSaleSpread: Double? {
    guard let immediateSaleRevenue, let evaluatedCost else { return nil }
    let spread = immediateSaleRevenue - evaluatedCost
    return spread.isFinite ? spread : nil
  }

  public var requiredJobCount: Int {
    guard runs > 0, maximumRunsPerJob > 0 else { return 1 }
    return max(1, (runs + maximumRunsPerJob - 1) / maximumRunsPerJob)
  }
}

public struct ReactionAnalysisSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let createdAt: Date
  public let runs: Int
  public let marketLocation: ProcurementLocation
  public let basis: ReactionAnalysisBasis
  public let basisName: String
  public let rows: [ReactionAnalysisRow]
  public let sdeSource: SourceIdentity
  public let marketSource: SourceIdentity
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    runs: Int,
    tradeHub: MarketTradeHub,
    basis: ReactionAnalysisBasis,
    basisName: String,
    rows: [ReactionAnalysisRow],
    sdeSource: SourceIdentity,
    marketSource: SourceIdentity,
    warnings: [DomainWarning] = []
  ) {
    self.id = id
    self.createdAt = createdAt
    self.runs = runs
    self.marketLocation = tradeHub.procurementLocation
    self.basis = basis
    self.basisName = basisName
    self.rows = rows
    self.sdeSource = sdeSource
    self.marketSource = marketSource
    self.warnings = warnings
  }

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    runs: Int,
    marketLocation: ProcurementLocation,
    basis: ReactionAnalysisBasis,
    basisName: String,
    rows: [ReactionAnalysisRow],
    sdeSource: SourceIdentity,
    marketSource: SourceIdentity,
    warnings: [DomainWarning] = []
  ) {
    self.id = id
    self.createdAt = createdAt
    self.runs = runs
    self.marketLocation = marketLocation
    self.basis = basis
    self.basisName = basisName
    self.rows = rows
    self.sdeSource = sdeSource
    self.marketSource = marketSource
    self.warnings = warnings
  }

  public var tradeHub: MarketTradeHub? {
    marketLocation.locationID.flatMap(MarketTradeHub.matching(stationID:))
  }

  public var maximumSelectableRuns: Int {
    rows.map(\.maximumRunsPerJob).max()
      ?? ReactionJobRules.neutralMaximumSelectableRuns
  }
}

public enum ReactionAnalysisSortOrder: String, Codable, CaseIterable, Sendable {
  case valueCreationDescending
  case valueCreationAscending
  case makeSavingsDescending
  case marginDescending
  case nameAscending

  public func sorted(_ rows: [ReactionAnalysisRow]) -> [ReactionAnalysisRow] {
    rows.sorted { lhs, rhs in
      switch self {
      case .valueCreationDescending:
        compare(lhs.valueCreation, rhs.valueCreation, lhs, rhs, ascending: false)
      case .valueCreationAscending:
        compare(lhs.valueCreation, rhs.valueCreation, lhs, rhs, ascending: true)
      case .makeSavingsDescending:
        compare(
          lhs.makeOrBuySavings,
          rhs.makeOrBuySavings,
          lhs,
          rhs,
          ascending: false
        )
      case .marginDescending:
        compare(
          lhs.valueCreationMargin,
          rhs.valueCreationMargin,
          lhs,
          rhs,
          ascending: false
        )
      case .nameAscending:
        byName(lhs, rhs)
      }
    }
  }

  private func compare(
    _ lhsValue: Double?,
    _ rhsValue: Double?,
    _ lhs: ReactionAnalysisRow,
    _ rhs: ReactionAnalysisRow,
    ascending: Bool
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case (let lhsValue?, let rhsValue?) where lhsValue != rhsValue:
      return ascending ? lhsValue < rhsValue : lhsValue > rhsValue
    case (_?, nil): return true
    case (nil, _?): return false
    default: return byName(lhs, rhs)
    }
  }

  private func byName(
    _ lhs: ReactionAnalysisRow,
    _ rhs: ReactionAnalysisRow
  ) -> Bool {
    lhs.productName.localizedCaseInsensitiveCompare(rhs.productName)
      == .orderedAscending
  }
}

public enum ReactionAnalysisError: Error, Equatable {
  case invalidRuns
  case noReactionDefinitions
  case invalidFacilityContext
  case inconsistentMarketLocation
}

public enum ReactionProfitabilityAnalyzer {
  /// Reuses the authoritative reaction quantity, rounding, duration and
  /// installation-cost rules for a production-profitability projection. The
  /// caller supplies logistics separately, so this result deliberately uses a
  /// zero-logistics context and exposes only the reaction job itself.
  public static func productionCostRow(
    definition: BlueprintDefinition,
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    runs: Int,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?
  ) throws -> ReactionAnalysisRow? {
    guard runs > 0 else { throw ReactionAnalysisError.invalidRuns }
    guard definition.activity.kind == .reaction,
      !definition.activity.materials.isEmpty,
      !definition.activity.products.isEmpty
    else { return nil }
    if let facility, !isValid(facility) {
      throw ReactionAnalysisError.invalidFacilityContext
    }
    let neutralLocation = ProcurementLocation.legacy(
      name: "Reaction production cost projection"
    )
    return analyze(
      definition: definition,
      typeNames: typeNames,
      classifications: classifications,
      runs: runs,
      market: market,
      adjustedPrices: adjustedPrices,
      facility: facility,
      logistics: ReactionLogisticsCostContext(
        configuration: LogisticsConfiguration(
          isEnabled: false,
          productionLocationName: neutralLocation.name,
          homeTradeHub: neutralLocation
        ),
        origin: neutralLocation,
        destinationName: neutralLocation.name,
        destinationLocationID: neutralLocation.locationID,
        packagedVolumes: [:]
      ),
      basis: facility == nil ? .materialOnlyBaseline : .configuredFacility
    )
  }

  public static func analyze(
    definitions: [BlueprintDefinition],
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    runs: Int,
    tradeHub: MarketTradeHub,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?,
    logistics: ReactionLogisticsCostContext,
    supplyChain: ReactionSupplyChainContext? = nil
  ) throws -> ReactionAnalysisSnapshot {
    try analyze(
      definitions: definitions,
      typeNames: typeNames,
      classifications: classifications,
      runs: runs,
      marketLocation: tradeHub.procurementLocation,
      market: market,
      adjustedPrices: adjustedPrices,
      facility: facility,
      logistics: logistics,
      supplyChain: supplyChain
    )
  }

  public static func analyze(
    definitions: [BlueprintDefinition],
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    runs: Int,
    marketLocation: ProcurementLocation,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?,
    logistics: ReactionLogisticsCostContext,
    supplyChain: ReactionSupplyChainContext? = nil
  ) throws -> ReactionAnalysisSnapshot {
    guard runs > 0 else { throw ReactionAnalysisError.invalidRuns }
    guard market.locationID == marketLocation.locationID,
      marketLocation.regionID.map({ market.regionID == $0 }) ?? true
    else { throw ReactionAnalysisError.inconsistentMarketLocation }
    let reactions = definitions.filter {
      $0.activity.kind == .reaction
        && !$0.activity.materials.isEmpty
        && !$0.activity.products.isEmpty
    }
    guard let sdeSource = reactions.first?.source else {
      throw ReactionAnalysisError.noReactionDefinitions
    }
    if let facility, !isValid(facility) {
      throw ReactionAnalysisError.invalidFacilityContext
    }

    let basis: ReactionAnalysisBasis =
      facility == nil ? .materialOnlyBaseline : .configuredFacility
    let basisName = facility?.name ?? "SDE material baseline"
    let supplyResolvers = facility == nil
      ? nil
      : supplyChain.map {
        supplyChainResolvers(
          context: $0,
          reactions: reactions,
          typeNames: typeNames,
          classifications: classifications,
          market: market,
          adjustedPrices: adjustedPrices,
          facility: facility,
          logistics: logistics
        )
      }
    let rows = reactions.compactMap { definition -> ReactionAnalysisRow? in
      let row = analyze(
        definition: definition,
        typeNames: typeNames,
        classifications: classifications,
        runs: runs,
        market: market,
        adjustedPrices: adjustedPrices,
        facility: facility,
        logistics: logistics,
        basis: basis
      )
      guard let row, let supplyResolvers else { return row }
      return applyingSupplyChain(
        to: row,
        source: definition.source,
        resolvers: supplyResolvers,
        typeNames: typeNames,
        market: market,
        logistics: logistics
      )
    }
    .sorted {
      $0.productName.localizedCaseInsensitiveCompare($1.productName)
        == .orderedAscending
    }

    var warnings: [DomainWarning] = []
    if facility == nil {
      warnings.append(
        DomainWarning(
          code: "reaction.material-only-baseline",
          message:
            "No verified reaction facility and system index are available. Results use SDE material quantities and exclude installation, structure, rig and clone costs.",
          severity: .warning,
          source: sdeSource
        )
      )
    }
    if !logistics.configuration.isEnabled {
      warnings.append(
        DomainWarning(
          code: "reaction.logistics-disabled",
          message:
            "Logistics is disabled in Profile, so both make and direct-purchase logistics use 0 ISK.",
          severity: .information,
          source: sdeSource
        )
      )
    }
    return ReactionAnalysisSnapshot(
      runs: runs,
      marketLocation: marketLocation,
      basis: basis,
      basisName: basisName,
      rows: rows,
      sdeSource: sdeSource,
      marketSource: market.source,
      warnings: warnings
    )
  }

  private static func analyze(
    definition: BlueprintDefinition,
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    runs: Int,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?,
    logistics: ReactionLogisticsCostContext,
    basis: ReactionAnalysisBasis
  ) -> ReactionAnalysisRow? {
    var warnings: [DomainWarning] = []
    let multiplier = facility?.materialMultiplier ?? 1
    let inputs: [ReactionMaterialValuation] =
      definition.activity.materials.compactMap {
        material -> ReactionMaterialValuation? in
        guard
          let raw = multiplied(material.quantity, by: runs),
          let quantity = scaled(
            rawQuantity: raw,
            runs: runs,
            multiplier: multiplier
          )
        else {
          warnings.append(
            DomainWarning(
              code: "reaction.quantity-overflow",
              message: "A reaction input quantity exceeded the supported range.",
              severity: .blocking,
              source: definition.source
            )
          )
          return nil
        }
        let quote = MarketPriceEngine.quote(
          typeID: material.typeID,
          quantity: quantity,
          scenario: .materialBuy,
          snapshot: market
        )
        warnings.append(contentsOf: quote.warnings)
        return ReactionMaterialValuation(
          typeID: material.typeID,
          name: typeNames[material.typeID] ?? "Type \(material.typeID)",
          quantity: quantity,
          quote: quote
        )
      }
    let outputs: [ReactionMaterialValuation] =
      definition.activity.products.compactMap {
        product -> ReactionMaterialValuation? in
        guard let quantity = multiplied(product.quantity, by: runs) else {
          warnings.append(
            DomainWarning(
              code: "reaction.quantity-overflow",
              message: "A reaction output quantity exceeded the supported range.",
              severity: .blocking,
              source: definition.source
            )
          )
          return nil
        }
        let quote = MarketPriceEngine.quote(
          typeID: product.typeID,
          quantity: quantity,
          scenario: .materialBuy,
          snapshot: market
        )
        warnings.append(contentsOf: quote.warnings)
        return ReactionMaterialValuation(
          typeID: product.typeID,
          name: typeNames[product.typeID] ?? "Type \(product.typeID)",
          quantity: quantity,
          quote: quote
        )
      }
    guard inputs.count == definition.activity.materials.count,
      outputs.count == definition.activity.products.count
    else { return nil }

    let materialCost = sumQuotes(inputs.map { $0.quote })
    let outputBuyCost = sumQuotes(outputs.map { $0.quote })
    let inputLogistics = logisticsCost(
      cargo: inputs,
      context: logistics,
      source: definition.source
    )
    warnings.append(contentsOf: inputLogistics.warnings)
    let outputPurchaseLogistics = logisticsCost(
      cargo: outputs,
      context: logistics,
      source: definition.source
    )
    warnings.append(contentsOf: outputPurchaseLogistics.warnings)
    let immediateQuotes = outputs.map { output in
      MarketPriceEngine.quote(
        typeID: output.typeID,
        quantity: output.quantity,
        scenario: .immediateSale,
        snapshot: market
      )
    }
    for quote in immediateQuotes {
      warnings.append(contentsOf: quote.warnings)
    }
    let immediateSaleRevenue = sumQuotes(immediateQuotes)
    let installationCost: Double?
    if let facility {
      installationCost = calculateInstallationCost(
        definition: definition,
        runs: runs,
        adjustedPrices: adjustedPrices,
        facility: facility
      )
    } else {
      installationCost = nil
    }
    if facility != nil, installationCost == nil {
      warnings.append(
        DomainWarning(
          code: "reaction.installation-cost-unavailable",
          message:
            "The installation cost is unavailable because an adjusted input price is missing.",
          severity: .blocking,
          source: definition.source
        )
      )
    }
    let evaluatedCost: Double?
    if let materialCost, let inputLogisticsCost = inputLogistics.cost {
      if facility == nil {
        evaluatedCost = safeSum([materialCost, inputLogisticsCost])
      } else if let installationCost {
        evaluatedCost = safeSum([
          materialCost, inputLogisticsCost, installationCost,
        ])
      } else {
        evaluatedCost = nil
      }
    } else {
      evaluatedCost = nil
    }
    let outputPurchaseTotalCost: Double?
    if let outputBuyCost,
      let outputPurchaseLogisticsCost = outputPurchaseLogistics.cost
    {
      outputPurchaseTotalCost = safeSum([
        outputBuyCost, outputPurchaseLogisticsCost,
      ])
    } else {
      outputPurchaseTotalCost = nil
    }
    let makeOrBuySavings = difference(outputPurchaseTotalCost, evaluatedCost)
    let valueCreation = makeOrBuySavings
    let valueCreationMargin: Double?
    if let valueCreation, let evaluatedCost, evaluatedCost > 0 {
      let margin = valueCreation / evaluatedCost
      valueCreationMargin = margin.isFinite ? margin : nil
    } else {
      valueCreationMargin = nil
    }
    let durationSeconds = scaledDuration(
      baseSeconds: definition.activity.durationSeconds,
      runs: runs,
      multiplier: facility?.timeMultiplier ?? 1
    )
    let maximumRunsPerJob = ReactionJobRules.maximumRunsPerJob(
      baseDurationSeconds: definition.activity.durationSeconds,
      timeMultiplier: facility?.timeMultiplier ?? 1
    )
    let classification = classifications[definition.productTypeID]
    return ReactionAnalysisRow(
      blueprintTypeID: definition.blueprintTypeID,
      productTypeID: definition.productTypeID,
      productName:
        typeNames[definition.productTypeID]
        ?? outputs.first?.name
        ?? "Type \(definition.productTypeID)",
      categoryName: classification?.categoryName ?? "Unclassified",
      groupName: classification?.groupName ?? "Unclassified reaction",
      runs: runs,
      inputs: inputs,
      outputs: outputs,
      materialCost: materialCost,
      inputLogisticsCost: inputLogistics.cost,
      installationCost: installationCost,
      evaluatedCost: evaluatedCost,
      outputBuyCost: outputBuyCost,
      outputPurchaseLogisticsCost: outputPurchaseLogistics.cost,
      outputPurchaseTotalCost: outputPurchaseTotalCost,
      immediateSaleRevenue: immediateSaleRevenue,
      makeOrBuySavings: makeOrBuySavings,
      valueCreation: valueCreation,
      valueCreationMargin: valueCreationMargin,
      durationSeconds: durationSeconds,
      maximumRunsPerJob: maximumRunsPerJob,
      basis: basis,
      warnings: deduplicatedWarnings(warnings)
    )
  }

  private static func logisticsCost(
    cargo: [ReactionMaterialValuation],
    context: ReactionLogisticsCostContext,
    source: SourceIdentity
  ) -> (cost: Double?, warnings: [DomainWarning]) {
    if let originID = context.origin.locationID,
      originID == context.destinationLocationID
    {
      return (0, [])
    }
    let configuration = context.configuration
    guard configuration.isEnabled else { return (0, []) }
    // Main → Home follows the leg choice of the logistics settings (owner
    // request 27.10.2026).
    guard configuration.includeInboundMaterials,
      case .contract(let pricing) = configuration.legPricing(for: .mainToHome)
    else {
      return (
        nil,
        [
          DomainWarning(
            code: "reaction.logistics-unavailable",
            message:
              "Enable complete Main Hub logistics in Profile to compare reaction and direct-purchase costs.",
            severity: .blocking,
            source: source
          )
        ]
      )
    }
    let result = LogisticsCostCalculator.calculateLegs(
      kind: .inboundMaterials,
      origin: context.origin.name,
      destination: context.destinationName,
      cargo: cargo.map {
        LogisticsCargoItem(
          typeID: $0.typeID,
          quantity: $0.quantity,
          collateral: $0.quote.total,
          packagedVolumePerUnit: context.packagedVolumes[$0.typeID]
        )
      },
      pricing: pricing
    )
    guard !result.warnings.contains(where: { $0.severity == .blocking }) else {
      return (nil, result.warnings)
    }
    let total = result.legs.reduce(0) { $0 + $1.roundedCharge }
    guard total.isFinite, total >= 0 else {
      return (
        nil,
        result.warnings + [
          DomainWarning(
            code: "reaction.invalid-logistics-cost",
            message: "The reaction logistics cost exceeded safe limits.",
            severity: .blocking,
            source: source
          )
        ]
      )
    }
    return (total, result.warnings)
  }

  private typealias SupplyResolver =
    ManufacturingOpportunityAnalyzer.ComponentCostResolver

  private static func supplyChainResolvers(
    context: ReactionSupplyChainContext,
    reactions: [BlueprintDefinition],
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?,
    logistics: ReactionLogisticsCostContext
  ) -> (cheapest: SupplyResolver, fullChain: SupplyResolver) {
    func resolver(
      strategy: SupplyResolver.Strategy,
      surcharge: ((Int64, Int64, Double) -> Double)?
    ) -> SupplyResolver {
      SupplyResolver(
        manufacturing: context.manufacturing,
        reactions: reactions,
        typeNames: typeNames,
        classifications: classifications,
        packagedVolumes: logistics.packagedVolumes,
        market: market,
        adjustedPrices: adjustedPrices,
        facilities: context.facilities,
        reactionFacility: facility,
        intermediateMaterialEfficiency:
          min(10, max(0, context.intermediateMaterialEfficiency)),
        blacklist: context.blacklist,
        strategy: strategy,
        purchaseSurcharge: surcharge
      )
    }
    return (
      resolver(strategy: .cheapest) { typeID, quantity, collateral in
        unroundedLogistics(
          typeID: typeID,
          quantity: quantity,
          collateral: collateral,
          context: logistics
        )
      },
      resolver(strategy: .alwaysBuild, surcharge: nil)
    )
  }

  /// Compares the supplies and moves the row's cost figures onto the cheapest
  /// one (owner decision 30.10.2026). The direct-purchase figures stay.
  private static func applyingSupplyChain(
    to row: ReactionAnalysisRow,
    source: SourceIdentity,
    resolvers: (cheapest: SupplyResolver, fullChain: SupplyResolver),
    typeNames: [Int64: String],
    market: MarketOrderSnapshot,
    logistics: ReactionLogisticsCostContext
  ) -> ReactionAnalysisRow {
    let intermediates = ReactionSupplyVariant(
      kind: .intermediatesBought,
      nodes: row.inputs.map {
        ReactionSupplyNode(
          typeID: $0.typeID,
          name: $0.name,
          quantity: $0.quantity,
          isBuilt: false,
          cost: $0.quote.isComplete ? $0.quote.total : nil,
          installationCost: 0,
          children: []
        )
      },
      purchases: row.inputs,
      materialCost: row.materialCost,
      logisticsCost: row.inputLogisticsCost,
      installationCost: row.installationCost,
      totalCost: row.evaluatedCost,
      builtJobCount: 0
    )
    func traced(
      _ kind: ReactionSupplyVariantKind,
      _ resolver: SupplyResolver
    ) -> ReactionSupplyVariant {
      supplyVariant(
        kind: kind,
        row: row,
        resolver: resolver,
        source: source,
        typeNames: typeNames,
        market: market,
        logistics: logistics
      )
    }
    let fullChain = traced(.fullChain, resolvers.fullChain)
    let mixed = traced(.cheapest, resolvers.cheapest)
    // Node decisions are estimates; only the final costing of the summed
    // shopping lists decides. A tie keeps the variant with fewer jobs.
    var best: ReactionSupplyVariant?
    for candidate in [intermediates, mixed, fullChain] {
      guard let total = candidate.totalCost else { continue }
      guard let current = best, let currentTotal = current.totalCost else {
        best = candidate
        continue
      }
      if total < currentTotal
        || (total == currentTotal
          && candidate.builtJobCount < current.builtJobCount)
      {
        best = candidate
      }
    }
    let cheapest: ReactionSupplyVariant? = best.map { best in
      ReactionSupplyVariant(
        kind: .cheapest,
        nodes: best.nodes,
        purchases: best.purchases,
        materialCost: best.materialCost,
        logisticsCost: best.logisticsCost,
        installationCost: best.installationCost,
        totalCost: best.totalCost,
        builtJobCount: best.builtJobCount
      )
    }
    var result = row
    result.supplyChain = ReactionSupplyChainComparison(
      directPurchaseTotal: row.outputPurchaseTotalCost,
      intermediatesBought: intermediates,
      fullChain: fullChain,
      cheapest: cheapest
    )
    guard let cheapest, let total = cheapest.totalCost else { return result }
    result.materialCost = cheapest.materialCost
    result.inputLogisticsCost = cheapest.logisticsCost
    result.installationCost = cheapest.installationCost
    result.evaluatedCost = total
    let savings = difference(row.outputPurchaseTotalCost, total)
    result.makeOrBuySavings = savings
    result.valueCreation = savings
    if let savings, total > 0 {
      let margin = savings / total
      result.valueCreationMargin = margin.isFinite ? margin : nil
    } else {
      result.valueCreationMargin = nil
    }
    return result
  }

  private static func supplyVariant(
    kind: ReactionSupplyVariantKind,
    row: ReactionAnalysisRow,
    resolver: SupplyResolver,
    source: SourceIdentity,
    typeNames: [Int64: String],
    market: MarketOrderSnapshot,
    logistics: ReactionLogisticsCostContext
  ) -> ReactionSupplyVariant {
    var nodes: [ReactionSupplyNode] = []
    var quantities: [Int64: Int64] = [:]
    var installation = row.installationCost
    var builtJobs = 0
    var isComplete = true
    for input in row.inputs {
      guard
        let resolved = resolver.resolve(
          typeID: input.typeID,
          quantity: input.quantity,
          consumerTypeID: row.productTypeID
        )
      else {
        // Stays visible as an open line; the variant remains unavailable.
        isComplete = false
        nodes.append(
          ReactionSupplyNode(
            typeID: input.typeID,
            name: input.name,
            quantity: input.quantity,
            isBuilt: false,
            cost: nil,
            installationCost: 0,
            children: []
          )
        )
        continue
      }
      nodes.append(resolved.node)
      installation = installation.map { $0 + resolved.installationCost }
      builtJobs += resolved.builtNodeCount
      quantities.merge(resolved.purchases) { lhs, rhs in
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
      }
    }
    let purchases = quantities.map { typeID, quantity in
      ReactionMaterialValuation(
        typeID: typeID,
        name: typeNames[typeID] ?? "Type \(typeID)",
        quantity: quantity,
        quote: MarketPriceEngine.quote(
          typeID: typeID,
          quantity: quantity,
          scenario: .materialBuy,
          snapshot: market
        )
      )
    }
    .sorted {
      let order = $0.name.localizedCaseInsensitiveCompare($1.name)
      return order == .orderedSame
        ? $0.typeID < $1.typeID : order == .orderedAscending
    }
    let materialCost = isComplete ? sumQuotes(purchases.map(\.quote)) : nil
    let logisticsValue =
      isComplete
      ? logisticsCost(cargo: purchases, context: logistics, source: source).cost
      : nil
    var totalCost: Double?
    if let materialCost, let logisticsValue, let installation {
      totalCost = safeSum([materialCost, logisticsValue, installation])
    }
    return ReactionSupplyVariant(
      kind: kind,
      nodes: nodes,
      purchases: purchases,
      materialCost: materialCost,
      logisticsCost: logisticsValue,
      installationCost: installation,
      totalCost: totalCost,
      builtJobCount: builtJobs
    )
  }

  /// Transport share of one bought node for the buy-or-build decision, without
  /// the per-contract rounding that only makes sense for a whole shipment.
  private static func unroundedLogistics(
    typeID: Int64,
    quantity: Int64,
    collateral: Double,
    context: ReactionLogisticsCostContext
  ) -> Double {
    if let originID = context.origin.locationID,
      originID == context.destinationLocationID
    {
      return 0
    }
    let configuration = context.configuration
    guard configuration.isEnabled, configuration.includeInboundMaterials,
      case .contract(let pricing) = configuration.legPricing(for: .mainToHome)
    else { return 0 }
    let charge = LogisticsCostCalculator.calculateLegs(
      kind: .inboundMaterials,
      origin: context.origin.name,
      destination: context.destinationName,
      cargo: [
        LogisticsCargoItem(
          typeID: typeID,
          quantity: quantity,
          collateral: collateral,
          packagedVolumePerUnit: context.packagedVolumes[typeID]
        )
      ],
      pricing: pricing
    ).legs.reduce(0) { $0 + $1.unroundedCharge }
    return charge.isFinite && charge >= 0 ? charge : 0
  }

  private static func deduplicatedWarnings(
    _ warnings: [DomainWarning]
  ) -> [DomainWarning] {
    var seen = Set<String>()
    return warnings.filter { seen.insert($0.code + "|" + $0.message).inserted }
  }

  private static func calculateInstallationCost(
    definition: BlueprintDefinition,
    runs: Int,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext
  ) -> Double? {
    var eiv = 0.0
    for material in definition.activity.materials {
      guard let adjusted = adjustedPrices[material.typeID]?.adjustedPrice,
        adjusted.isFinite,
        adjusted >= 0,
        let quantity = multiplied(material.quantity, by: runs)
      else { return nil }
      let value = adjusted * Double(quantity)
      guard value.isFinite, value >= 0 else { return nil }
      eiv += value
      guard eiv.isFinite else { return nil }
    }
    let rate =
      facility.systemCostIndex * facility.jobCostMultiplier
      + facility.facilityTaxRate
      + facility.sccSurchargeRate
      + facility.alphaSurchargeRate
    let result = eiv * rate
    return result.isFinite && result >= 0 ? result : nil
  }

  private static func isValid(_ facility: ReactionFacilityCostContext) -> Bool {
    [
      facility.materialMultiplier, facility.timeMultiplier,
      facility.jobCostMultiplier, facility.facilityTaxRate,
      facility.systemCostIndex, facility.sccSurchargeRate,
      facility.alphaSurchargeRate,
    ].allSatisfy { $0.isFinite && $0 >= 0 }
      && facility.materialMultiplier > 0
      && facility.timeMultiplier > 0
      && facility.jobCostMultiplier > 0
  }

  private static func multiplied(_ quantity: Int64, by runs: Int) -> Int64? {
    guard quantity > 0, runs > 0, let acceptedRuns = Int64(exactly: runs)
    else { return nil }
    let (value, overflow) = quantity.multipliedReportingOverflow(
      by: acceptedRuns
    )
    return overflow || value <= 0 ? nil : value
  }

  private static func scaled(
    rawQuantity: Int64,
    runs: Int,
    multiplier: Double
  ) -> Int64? {
    let value = Double(rawQuantity) * multiplier
    guard value.isFinite, value > 0, value < Double(Int64.max) else {
      return nil
    }
    return max(Int64(runs), Int64(ceil(value)))
  }

  private static func scaledDuration(
    baseSeconds: Int64,
    runs: Int,
    multiplier: Double
  ) -> Int64 {
    guard let raw = multiplied(baseSeconds, by: runs) else {
      return Int64.max
    }
    let value = Double(raw) * multiplier
    guard value.isFinite, value < Double(Int64.max) else {
      return Int64.max
    }
    return max(0, Int64(ceil(value)))
  }

  private static func sumQuotes(_ quotes: [PriceQuote]) -> Double? {
    guard quotes.allSatisfy(\.isComplete) else { return nil }
    return safeSum(quotes.compactMap(\.total))
  }

  private static func safeSum(_ values: [Double]) -> Double? {
    var total = 0.0
    for value in values {
      guard value.isFinite, value >= 0 else { return nil }
      total += value
      guard total.isFinite else { return nil }
    }
    return total
  }

  private static func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs, let rhs else { return nil }
    let result = lhs - rhs
    return result.isFinite ? result : nil
  }
}
