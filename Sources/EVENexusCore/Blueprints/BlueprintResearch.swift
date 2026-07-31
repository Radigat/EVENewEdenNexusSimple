import Foundation

public enum BlueprintResearchError: Error, LocalizedError, Sendable {
  case definitionUnavailable(Int64)

  public var errorDescription: String? {
    switch self {
    case .definitionUnavailable(let typeID):
      "The active SDE does not contain a research definition for blueprint type \(typeID)."
    }
  }
}

public struct OwnedBlueprintInventory: Codable, Sendable {
  public let ownerID: Int64
  public let ownerName: String
  public let blueprints: Sourced<[OwnedBlueprintInstance]>

  public init(
    ownerID: Int64,
    ownerName: String,
    blueprints: Sourced<[OwnedBlueprintInstance]>
  ) {
    self.ownerID = ownerID
    self.ownerName = ownerName
    self.blueprints = blueprints
  }
}

public struct BlueprintPortfolioEntry: Identifiable, Codable, Sendable {
  public var id: Int64 { instance.id }
  public let ownerID: Int64
  public let ownerName: String
  public let sourceState: DataFreshness
  public let instance: OwnedBlueprintInstance

  public init(
    ownerID: Int64,
    ownerName: String,
    sourceState: DataFreshness,
    instance: OwnedBlueprintInstance
  ) {
    self.ownerID = ownerID
    self.ownerName = ownerName
    self.sourceState = sourceState
    self.instance = instance
  }
}

public struct BlueprintPortfolio: Codable, Sendable {
  public let entries: [BlueprintPortfolioEntry]
  public let sourceStates: [DataFreshness]
  public let snapshotIDs: [UUID]

  public init(inventories: [OwnedBlueprintInventory]) {
    var entries: [BlueprintPortfolioEntry] = []
    var states: [DataFreshness] = []
    var snapshotIDs: [UUID] = []
    for inventory in inventories.sorted(by: { $0.ownerID < $1.ownerID }) {
      states.append(inventory.blueprints.state)
      snapshotIDs.append(inventory.blueprints.source.snapshotID)
      guard let blueprints = inventory.blueprints.value else { continue }
      entries.append(
        contentsOf: blueprints.map {
          BlueprintPortfolioEntry(
            ownerID: inventory.ownerID,
            ownerName: inventory.ownerName,
            sourceState: inventory.blueprints.state,
            instance: $0
          )
        }
      )
    }
    self.entries = entries.sorted {
      if $0.ownerName != $1.ownerName {
        return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
          == .orderedAscending
      }
      return $0.instance.id < $1.instance.id
    }
    self.sourceStates = states
    self.snapshotIDs = snapshotIDs
  }
}

public enum BlueprintResearchActivity: String, Codable, CaseIterable, Sendable {
  case materialEfficiency
  case timeEfficiency

  public var industryActivity: IndustryActivitySystem {
    switch self {
    case .materialEfficiency: .materialResearch
    case .timeEfficiency: .timeResearch
    }
  }

  public func targetEfficiency(level: Int) -> Int {
    switch self {
    case .materialEfficiency: level
    case .timeEfficiency: level * 2
    }
  }
}

public struct BlueprintResearchDefinition: Codable, Sendable {
  public let blueprintTypeID: Int64
  public let blueprintName: String
  public let basePrice: Double?
  public let manufacturingMaterials: [BlueprintMaterial]
  public let materialResearchMaterials: [BlueprintMaterial]
  public let timeResearchMaterials: [BlueprintMaterial]
  public let materialResearchTimeSeconds: Int64?
  public let timeResearchTimeSeconds: Int64?
  public let hasUnresolvedReferences: Bool
  public let source: SourceIdentity

  public init(
    blueprintTypeID: Int64,
    blueprintName: String,
    basePrice: Double?,
    manufacturingMaterials: [BlueprintMaterial],
    materialResearchMaterials: [BlueprintMaterial] = [],
    timeResearchMaterials: [BlueprintMaterial] = [],
    materialResearchTimeSeconds: Int64?,
    timeResearchTimeSeconds: Int64?,
    hasUnresolvedReferences: Bool = false,
    source: SourceIdentity
  ) {
    self.blueprintTypeID = blueprintTypeID
    self.blueprintName = blueprintName
    self.basePrice = basePrice
    self.manufacturingMaterials = manufacturingMaterials
    self.materialResearchMaterials = materialResearchMaterials
    self.timeResearchMaterials = timeResearchMaterials
    self.materialResearchTimeSeconds = materialResearchTimeSeconds
    self.timeResearchTimeSeconds = timeResearchTimeSeconds
    self.hasUnresolvedReferences = hasUnresolvedReferences
    self.source = source
  }
}

public struct BlueprintResearchFacilityContext: Codable, Sendable {
  public let activity: BlueprintResearchActivity
  public let solarSystemID: Int64
  public let solarSystemName: String
  public let facilityName: String
  public let systemCostIndex: Double
  public let jobCostMultiplier: Double
  public let facilityTaxRate: Double
  public let sccSurchargeRate: Double
  public let alphaSurchargeRate: Double
  public let needsReview: Bool
  public let source: SourceIdentity

  public init(
    activity: BlueprintResearchActivity,
    solarSystemID: Int64,
    solarSystemName: String,
    facilityName: String,
    systemCostIndex: Double,
    jobCostMultiplier: Double,
    facilityTaxRate: Double,
    sccSurchargeRate: Double,
    alphaSurchargeRate: Double,
    needsReview: Bool,
    source: SourceIdentity
  ) {
    self.activity = activity
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.facilityName = facilityName
    self.systemCostIndex = systemCostIndex
    self.jobCostMultiplier = jobCostMultiplier
    self.facilityTaxRate = facilityTaxRate
    self.sccSurchargeRate = sccSurchargeRate
    self.alphaSurchargeRate = alphaSurchargeRate
    self.needsReview = needsReview
    self.source = source
  }

  public var totalFeeFactor: Double? {
    let value =
      systemCostIndex * jobCostMultiplier
      + facilityTaxRate
      + sccSurchargeRate
      + alphaSurchargeRate
    guard value.isFinite, value >= 0 else { return nil }
    return value
  }
}

public struct BlueprintResearchPricingInput: Sendable {
  public let adjustedPrices: [Int64: AdjustedPrice]
  public let adjustedPriceSource: SourceIdentity
  public let materialFacility: BlueprintResearchFacilityContext?
  public let timeFacility: BlueprintResearchFacilityContext?

  public init(
    adjustedPrices: [Int64: AdjustedPrice],
    adjustedPriceSource: SourceIdentity,
    materialFacility: BlueprintResearchFacilityContext?,
    timeFacility: BlueprintResearchFacilityContext?
  ) {
    self.adjustedPrices = adjustedPrices
    self.adjustedPriceSource = adjustedPriceSource
    self.materialFacility = materialFacility
    self.timeFacility = timeFacility
  }
}

public struct BlueprintResearchLevelCost: Identifiable, Codable, Sendable {
  public var id: Int { level }
  public let level: Int
  public let materialEfficiencyTarget: Int
  public let timeEfficiencyTarget: Int
  public let researchMultiplier: Double
  public let materialStepCost: Double?
  public let materialCumulativeCost: Double?
  public let timeStepCost: Double?
  public let timeCumulativeCost: Double?
}

public struct BlueprintResearchCostQuote: Codable, Sendable {
  public let blueprintTypeID: Int64
  public let blueprintName: String
  public let instanceID: Int64
  public let isResearchable: Bool
  public let currentMaterialLevel: Int
  public let currentTimeLevel: Int
  public let manufacturingBaseCost: Double?
  public let rawBlueprintBasePrice: Double?
  public let levels: [BlueprintResearchLevelCost]
  public let currentMaterialResearchValue: Double?
  public let currentTimeResearchValue: Double?
  public let currentTotalResearchValue: Double?
  public let remainingMaterialResearchCost: Double?
  public let remainingTimeResearchCost: Double?
  public let remainingTotalResearchCost: Double?
  public let estimatedReplacementValue: Double?
  public let ruleVersion: String
  public let calculatedAt: Date
  public let warnings: [DomainWarning]
  public let definitionSource: SourceIdentity
  public let adjustedPriceSource: SourceIdentity
  public let materialFacility: BlueprintResearchFacilityContext?
  public let timeFacility: BlueprintResearchFacilityContext?

  public func isMaterialLevelResearched(_ level: Int) -> Bool {
    level > 0 && level <= currentMaterialLevel
  }

  public func isTimeLevelResearched(_ level: Int) -> Bool {
    level > 0 && level <= currentTimeLevel
  }
}

public enum BlueprintResearchCostCalculator {
  public static let ruleVersion = "ccp-blueprint-research-2026-07-v1"

  public static let levelMultipliers: [Double] = [
    1,
    29.0 / 21.0,
    23.0 / 7.0,
    39.0 / 5.0,
    278.0 / 15.0,
    928.0 / 21.0,
    2_200.0 / 21.0,
    5_251.0 / 21.0,
    4_163.0 / 7.0,
    29_660.0 / 21.0,
  ]

  public static func quote(
    instance: OwnedBlueprintInstance,
    definition: BlueprintResearchDefinition,
    pricing: BlueprintResearchPricingInput,
    calculatedAt: Date = .now
  ) -> BlueprintResearchCostQuote {
    var warnings: [DomainWarning] = []
    let currentMaterialLevel = min(max(instance.materialEfficiency, 0), 10)
    let currentTimeLevel = min(max(instance.timeEfficiency / 2, 0), 10)

    if instance.materialEfficiency != currentMaterialLevel
      || instance.timeEfficiency != currentTimeLevel * 2
    {
      warnings.append(
        DomainWarning(
          code: "blueprint.research-efficiency-out-of-range",
          message:
            "The blueprint reports an ME or TE value outside the supported ten-level research scale.",
          severity: .warning,
          source: instance.source
        )
      )
    }
    if instance.kind != .original {
      warnings.append(
        DomainWarning(
          code: "blueprint.copy-not-researchable",
          message:
            "Blueprint copies retain their ME and TE values but cannot be researched.",
          severity: .information,
          source: instance.source
        )
      )
    }
    if definition.hasUnresolvedReferences {
      warnings.append(
        DomainWarning(
          code: "blueprint.research-unresolved-sde-reference",
          message:
            "The active SDE contains an unresolved material reference for this blueprint.",
          severity: .blocking,
          source: definition.source
        )
      )
    }

    let additionalResearchMaterials =
      definition.materialResearchMaterials
      + definition.timeResearchMaterials
    if !additionalResearchMaterials.isEmpty {
      warnings.append(
        DomainWarning(
          code: "blueprint.research-additional-materials",
          message:
            "This blueprint requires additional research materials. They are visible in the SDE but are not included in the replacement estimate until their level-scaling rule is owner-verified.",
          severity: .blocking,
          source: definition.source
        )
      )
    }

    var missingAdjustedPrice = false
    let manufacturingBaseCost = definition.manufacturingMaterials.reduce(0.0) {
      total, material in
      guard material.quantity >= 0,
        let price = pricing.adjustedPrices[material.typeID]?.adjustedPrice,
        price.isFinite,
        price >= 0
      else {
        missingAdjustedPrice = true
        return total
      }
      let next = total + price * Double(material.quantity)
      guard next.isFinite, next >= 0 else {
        missingAdjustedPrice = true
        return total
      }
      return next
    }
    if definition.manufacturingMaterials.isEmpty || missingAdjustedPrice {
      warnings.append(
        DomainWarning(
          code: "blueprint.research-missing-adjusted-price",
          message:
            "At least one adjusted price required for the research base cost is unavailable.",
          severity: .blocking,
          source: pricing.adjustedPriceSource
        )
      )
    }

    if pricing.materialFacility == nil {
      warnings.append(
        DomainWarning(
          code: "blueprint.material-research-facility-unavailable",
          message:
            "Configure a Material Research system and compatible facility in Profile to calculate ME costs.",
          severity: .blocking
        )
      )
    }
    if pricing.timeFacility == nil {
      warnings.append(
        DomainWarning(
          code: "blueprint.time-research-facility-unavailable",
          message:
            "Configure a Time Research system and compatible facility in Profile to calculate TE costs.",
          severity: .blocking
        )
      )
    }
    if pricing.materialFacility?.needsReview == true
      || pricing.timeFacility?.needsReview == true
    {
      warnings.append(
        DomainWarning(
          code: "blueprint.research-facility-needs-review",
          message:
            "At least one selected research facility has unresolved capability or modifier evidence.",
          severity: .warning
        )
      )
    }

    let acceptedBaseCost =
      definition.manufacturingMaterials.isEmpty || missingAdjustedPrice
      ? nil : manufacturingBaseCost
    var materialCumulative = 0.0
    var timeCumulative = 0.0
    let levels = levelMultipliers.enumerated().map { offset, multiplier in
      let level = offset + 1
      let materialStep = stepCost(
        baseCost: acceptedBaseCost,
        multiplier: multiplier,
        facility: pricing.materialFacility
      )
      let timeStep = stepCost(
        baseCost: acceptedBaseCost,
        multiplier: multiplier,
        facility: pricing.timeFacility
      )
      if let materialStep { materialCumulative += materialStep }
      if let timeStep { timeCumulative += timeStep }
      return BlueprintResearchLevelCost(
        level: level,
        materialEfficiencyTarget: level,
        timeEfficiencyTarget: level * 2,
        researchMultiplier: multiplier,
        materialStepCost: materialStep,
        materialCumulativeCost:
          materialStep == nil ? nil : materialCumulative,
        timeStepCost: timeStep,
        timeCumulativeCost: timeStep == nil ? nil : timeCumulative
      )
    }

    let currentME = cumulativeCost(
      level: currentMaterialLevel,
      levels: levels,
      keyPath: \.materialCumulativeCost
    )
    let currentTE = cumulativeCost(
      level: currentTimeLevel,
      levels: levels,
      keyPath: \.timeCumulativeCost
    )
    let maximumME = levels.last?.materialCumulativeCost
    let maximumTE = levels.last?.timeCumulativeCost
    let remainingME = difference(maximumME, currentME)
    let remainingTE = difference(maximumTE, currentTE)
    let currentTotal = sum(currentME, currentTE)
    let remainingTotal = sum(remainingME, remainingTE)

    let researchInputsComplete =
      additionalResearchMaterials.isEmpty
      && !definition.hasUnresolvedReferences
    let replacementValue: Double?
    if instance.kind == .original,
      researchInputsComplete,
      let basePrice = definition.basePrice,
      basePrice.isFinite,
      basePrice >= 0,
      let currentME,
      let currentTE
    {
      let total = basePrice + currentME + currentTE
      replacementValue = total.isFinite ? total : nil
    } else {
      replacementValue = nil
      if instance.kind == .original && definition.basePrice == nil {
        warnings.append(
          DomainWarning(
            code: "blueprint.research-missing-base-price",
            message:
              "The active SDE does not provide a base price for this blueprint, so a complete replacement value cannot be shown.",
            severity: .warning,
            source: definition.source
          )
        )
      }
    }

    return BlueprintResearchCostQuote(
      blueprintTypeID: definition.blueprintTypeID,
      blueprintName: definition.blueprintName,
      instanceID: instance.id,
      isResearchable: instance.kind == .original,
      currentMaterialLevel: currentMaterialLevel,
      currentTimeLevel: currentTimeLevel,
      manufacturingBaseCost: acceptedBaseCost,
      rawBlueprintBasePrice: definition.basePrice,
      levels: levels,
      currentMaterialResearchValue: currentME,
      currentTimeResearchValue: currentTE,
      currentTotalResearchValue: currentTotal,
      remainingMaterialResearchCost: remainingME,
      remainingTimeResearchCost: remainingTE,
      remainingTotalResearchCost: remainingTotal,
      estimatedReplacementValue: replacementValue,
      ruleVersion: ruleVersion,
      calculatedAt: calculatedAt,
      warnings: warnings,
      definitionSource: definition.source,
      adjustedPriceSource: pricing.adjustedPriceSource,
      materialFacility: pricing.materialFacility,
      timeFacility: pricing.timeFacility
    )
  }

  private static func stepCost(
    baseCost: Double?,
    multiplier: Double,
    facility: BlueprintResearchFacilityContext?
  ) -> Double? {
    guard let baseCost,
      let factor = facility?.totalFeeFactor,
      multiplier.isFinite,
      multiplier >= 0
    else { return nil }
    let value = baseCost * 0.02 * multiplier * factor
    guard value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func cumulativeCost(
    level: Int,
    levels: [BlueprintResearchLevelCost],
    keyPath: KeyPath<BlueprintResearchLevelCost, Double?>
  ) -> Double? {
    if level == 0 { return 0 }
    guard levels.indices.contains(level - 1) else { return nil }
    return levels[level - 1][keyPath: keyPath]
  }

  private static func difference(_ maximum: Double?, _ current: Double?)
    -> Double?
  {
    guard let maximum, let current else { return nil }
    return max(0, maximum - current)
  }

  private static func sum(_ first: Double?, _ second: Double?) -> Double? {
    guard let first, let second else { return nil }
    let value = first + second
    return value.isFinite ? value : nil
  }
}
