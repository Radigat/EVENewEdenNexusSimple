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

public struct ReactionMaterialValuation: Identifiable, Codable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let quantity: Int64
  public let quote: PriceQuote
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
  public let materialCost: Double?
  public let installationCost: Double?
  public let evaluatedCost: Double?
  public let outputBuyCost: Double?
  public let immediateSaleRevenue: Double?
  public let makeOrBuySavings: Double?
  public let valueCreation: Double?
  public let valueCreationMargin: Double?
  public let durationSeconds: Int64
  public let maximumRunsPerJob: Int
  public let basis: ReactionAnalysisBasis
  public let warnings: [DomainWarning]

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
  public let tradeHub: MarketTradeHub
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
    self.tradeHub = tradeHub
    self.basis = basis
    self.basisName = basisName
    self.rows = rows
    self.sdeSource = sdeSource
    self.marketSource = marketSource
    self.warnings = warnings
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
  public static func analyze(
    definitions: [BlueprintDefinition],
    typeNames: [Int64: String],
    classifications: [Int64: IndustryItemClassification],
    runs: Int,
    tradeHub: MarketTradeHub,
    market: MarketOrderSnapshot,
    adjustedPrices: [Int64: AdjustedPrice],
    facility: ReactionFacilityCostContext?
  ) throws -> ReactionAnalysisSnapshot {
    guard runs > 0 else { throw ReactionAnalysisError.invalidRuns }
    guard market.locationID == tradeHub.stationID,
      market.regionID == tradeHub.regionID
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
    let rows = reactions.compactMap { definition in
      analyze(
        definition: definition,
        typeNames: typeNames,
        classifications: classifications,
        runs: runs,
        market: market,
        adjustedPrices: adjustedPrices,
        facility: facility,
        basis: basis
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
    return ReactionAnalysisSnapshot(
      runs: runs,
      tradeHub: tradeHub,
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
    if let materialCost {
      if facility == nil {
        evaluatedCost = materialCost
      } else if let installationCost {
        evaluatedCost = safeSum([materialCost, installationCost])
      } else {
        evaluatedCost = nil
      }
    } else {
      evaluatedCost = nil
    }
    let makeOrBuySavings = difference(outputBuyCost, evaluatedCost)
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
      installationCost: installationCost,
      evaluatedCost: evaluatedCost,
      outputBuyCost: outputBuyCost,
      immediateSaleRevenue: immediateSaleRevenue,
      makeOrBuySavings: makeOrBuySavings,
      valueCreation: valueCreation,
      valueCreationMargin: valueCreationMargin,
      durationSeconds: durationSeconds,
      maximumRunsPerJob: maximumRunsPerJob,
      basis: basis,
      warnings: warnings
    )
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
