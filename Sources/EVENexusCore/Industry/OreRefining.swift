import Foundation

public enum ReprocessableMaterialKind: String, Codable, Equatable, Sendable {
  case asteroidOre
  case moonOre
  case ice
  case gas
  case unknown
}

public struct ReprocessingMaterialOutput: Codable, Equatable, Sendable {
  public let typeID: Int64
  public let quantity: Int64
  /// Frozen EVE type name for a concrete refining-plan output. Static SDE
  /// recipe rows can leave this nil until the planner resolves their names.
  public let name: String?
  /// Quantity assigned to the current plan's outstanding mineral demand.
  /// Static recipe rows and historical snapshots can leave this nil.
  public let usedInPlan: Int64?
  /// Produced quantity not assigned to this plan. It is a planned warehouse
  /// intake and never a value credit against this product's costs.
  public let surplusToWarehouse: Int64?

  public init(
    typeID: Int64,
    quantity: Int64,
    name: String? = nil,
    usedInPlan: Int64? = nil,
    surplusToWarehouse: Int64? = nil
  ) {
    self.typeID = typeID
    self.quantity = quantity
    self.name = name
    self.usedInPlan = usedInPlan
    self.surplusToWarehouse = surplusToWarehouse
  }
}

public struct CompressedOreOption: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let portionSize: Int64
  public let packagedVolume: Double?
  public let reprocessingSkillTypeID: Int64?
  public let kind: ReprocessableMaterialKind
  public let outputs: [ReprocessingMaterialOutput]
  public let source: SourceIdentity

  public init(
    typeID: Int64,
    name: String,
    portionSize: Int64,
    packagedVolume: Double?,
    reprocessingSkillTypeID: Int64?,
    kind: ReprocessableMaterialKind,
    outputs: [ReprocessingMaterialOutput],
    source: SourceIdentity
  ) {
    self.typeID = typeID
    self.name = name
    self.portionSize = portionSize
    self.packagedVolume = packagedVolume
    self.reprocessingSkillTypeID = reprocessingSkillTypeID
    self.kind = kind
    self.outputs = outputs
    self.source = source
  }
}

public struct CompressedOreRefiningConfiguration: Codable, Equatable, Sendable {
  public static let ruleVersion = "compressed-ore-refining-upwell-2026-08-15"

  public var isEnabled: Bool
  public var ruleVersion: String

  public init(
    isEnabled: Bool = false,
    ruleVersion: String = CompressedOreRefiningConfiguration.ruleVersion
  ) {
    self.isEnabled = isEnabled
    self.ruleVersion = ruleVersion
  }
}

public enum OreRefiningImplant: String, CaseIterable, Codable, Equatable,
  Identifiable, Sendable
{
  case none
  case rx801
  case rx802
  case rx804

  public var id: Self { self }

  public var typeID: Int64? {
    switch self {
    case .none: nil
    case .rx801: 27_175
    case .rx802: 27_169
    case .rx804: 27_174
    }
  }

  public var name: String {
    switch self {
    case .none: "No Reprocessing implant"
    case .rx801: "Zainou 'Beancounter' Reprocessing RX-801"
    case .rx802: "Zainou 'Beancounter' Reprocessing RX-802"
    case .rx804: "Zainou 'Beancounter' Reprocessing RX-804"
    }
  }

  public var yieldBonusPercent: Double {
    switch self {
    case .none: 0
    case .rx801: 1
    case .rx802: 2
    case .rx804: 4
    }
  }
}

public struct OreRefiningCharacterSelection: Codable, Equatable, Sendable {
  public let characterID: Int64
  public let characterName: String
  public let reprocessingLevel: Int
  public let reprocessingEfficiencyLevel: Int
  public let oreProcessingLevel: Int
  /// Missing on historical plan snapshots, which means that the old
  /// calculation made no verified implant assumption.
  public let implant: OreRefiningImplant?
  public let skillsState: DataFreshness
  public let skillsSource: SourceIdentity

  public init(
    characterID: Int64,
    characterName: String,
    reprocessingLevel: Int,
    reprocessingEfficiencyLevel: Int,
    oreProcessingLevel: Int,
    implant: OreRefiningImplant? = nil,
    skillsState: DataFreshness,
    skillsSource: SourceIdentity
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.reprocessingLevel = reprocessingLevel
    self.reprocessingEfficiencyLevel = reprocessingEfficiencyLevel
    self.oreProcessingLevel = oreProcessingLevel
    self.implant = implant
    self.skillsState = skillsState
    self.skillsSource = skillsSource
  }
}

public struct OreRefiningFacilitySelection: Codable, Equatable, Sendable {
  public let structureID: UUID
  public let structureName: String
  public let solarSystemID: Int64
  public let solarSystemName: String
  public let baseYieldMultiplier: Double
  public let taxRate: Double

  public init(
    structureID: UUID,
    structureName: String,
    solarSystemID: Int64,
    solarSystemName: String,
    baseYieldMultiplier: Double,
    taxRate: Double
  ) {
    self.structureID = structureID
    self.structureName = structureName
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.baseYieldMultiplier = baseYieldMultiplier
    self.taxRate = taxRate
  }
}

public struct OreRefiningPurchase: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { oreTypeID }
  public let oreTypeID: Int64
  public let oreName: String
  public let quantity: Int64
  public let batches: Int64
  public let purchaseQuote: PriceQuote
  public let outputs: [ReprocessingMaterialOutput]
  public let yieldMultiplier: Double
  public let facility: OreRefiningFacilitySelection
  public let character: OreRefiningCharacterSelection
  public let refiningFee: Double

  public init(
    oreTypeID: Int64,
    oreName: String,
    quantity: Int64,
    batches: Int64,
    purchaseQuote: PriceQuote,
    outputs: [ReprocessingMaterialOutput],
    yieldMultiplier: Double,
    facility: OreRefiningFacilitySelection,
    character: OreRefiningCharacterSelection,
    refiningFee: Double
  ) {
    self.oreTypeID = oreTypeID
    self.oreName = oreName
    self.quantity = quantity
    self.batches = batches
    self.purchaseQuote = purchaseQuote
    self.outputs = outputs
    self.yieldMultiplier = yieldMultiplier
    self.facility = facility
    self.character = character
    self.refiningFee = refiningFee
  }
}

public struct CompressedOreRefiningPlan: Codable, Equatable, Sendable {
  public let purchases: [OreRefiningPurchase]
  public let coveredMinerals: [Int64: Int64]
  public let remainingDirectMinerals: [Int64: Int64]
  public let remainingDirectQuotes: [Int64: PriceQuote]
  public let orePurchaseCost: Double
  public let refiningFee: Double
  public let directLandedCost: Double
  public let selectedLandedCost: Double
  public let savings: Double
  public let ruleVersion: String

  public init(
    purchases: [OreRefiningPurchase],
    coveredMinerals: [Int64: Int64],
    remainingDirectMinerals: [Int64: Int64],
    remainingDirectQuotes: [Int64: PriceQuote],
    orePurchaseCost: Double,
    refiningFee: Double,
    directLandedCost: Double,
    selectedLandedCost: Double,
    savings: Double,
    ruleVersion: String = CompressedOreRefiningConfiguration.ruleVersion
  ) {
    self.purchases = purchases
    self.coveredMinerals = coveredMinerals
    self.remainingDirectMinerals = remainingDirectMinerals
    self.remainingDirectQuotes = remainingDirectQuotes
    self.orePurchaseCost = orePurchaseCost
    self.refiningFee = refiningFee
    self.directLandedCost = directLandedCost
    self.selectedLandedCost = selectedLandedCost
    self.savings = savings
    self.ruleVersion = ruleVersion
  }
}

public enum ReprocessingYieldCalculator {
  public static let reprocessingSkillTypeID: Int64 = 3_385
  public static let reprocessingEfficiencySkillTypeID: Int64 = 3_389

  public static func yieldMultiplier(
    baseYieldMultiplier: Double,
    reprocessingLevel: Int,
    reprocessingEfficiencyLevel: Int,
    oreProcessingLevel: Int,
    implantYieldBonusPercent: Double = 0
  ) -> Double? {
    guard baseYieldMultiplier.isFinite, baseYieldMultiplier > 0,
      (0...5).contains(reprocessingLevel),
      (0...5).contains(reprocessingEfficiencyLevel),
      (0...5).contains(oreProcessingLevel),
      implantYieldBonusPercent.isFinite,
      implantYieldBonusPercent >= 0
    else { return nil }
    let value =
      baseYieldMultiplier
      * (1 + Double(reprocessingLevel) * 0.03)
      * (1 + Double(reprocessingEfficiencyLevel) * 0.02)
      * (1 + Double(oreProcessingLevel) * 0.02)
      * (1 + implantYieldBonusPercent / 100)
    guard value.isFinite, value > 0 else { return nil }
    return min(1, value)
  }

  public static func outputQuantity(
    baseQuantity: Int64,
    batches: Int64,
    yieldMultiplier: Double
  ) -> Int64? {
    guard baseQuantity > 0, batches > 0,
      yieldMultiplier.isFinite, yieldMultiplier > 0
    else { return nil }
    let value = Double(baseQuantity) * Double(batches) * yieldMultiplier
    guard value.isFinite, value >= 1, value < Double(Int64.max) else {
      return nil
    }
    return Int64(floor(value))
  }

  public static func minimumBatches(
    requiredQuantity: Int64,
    baseQuantity: Int64,
    yieldMultiplier: Double
  ) -> Int64? {
    guard requiredQuantity > 0, baseQuantity > 0,
      yieldMultiplier.isFinite, yieldMultiplier > 0
    else { return nil }
    let outputPerBatch = Double(baseQuantity) * yieldMultiplier
    guard outputPerBatch.isFinite, outputPerBatch > 0 else { return nil }
    let estimate = ceil(Double(requiredQuantity) / outputPerBatch)
    guard estimate.isFinite, estimate >= 1, estimate < Double(Int64.max) else {
      return nil
    }
    var batches = Int64(estimate)
    while (outputQuantity(
      baseQuantity: baseQuantity,
      batches: batches,
      yieldMultiplier: yieldMultiplier
    ) ?? 0) < requiredQuantity {
      guard batches < Int64.max else { return nil }
      batches += 1
    }
    while batches > 1,
      (outputQuantity(
        baseQuantity: baseQuantity,
        batches: batches - 1,
        yieldMultiplier: yieldMultiplier
      ) ?? 0) >= requiredQuantity
    {
      batches -= 1
    }
    return batches
  }
}
