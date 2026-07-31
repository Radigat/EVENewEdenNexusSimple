import Foundation

public enum SecurityBand: String, Codable, CaseIterable, Sendable {
  case highSecurity
  case lowSecurity
  case nullSecurity
  case wormhole
  case unknown

  public static func resolved(
    solarSystemID: Int64,
    securityStatus: Double?,
    regionID: Int64? = nil
  ) -> SecurityBand {
    guard let securityStatus else { return .unknown }
    if (31_000_000..<32_000_000).contains(solarSystemID)
      || regionID.map({ (11_000_000..<12_000_000).contains($0) }) == true
    {
      return .wormhole
    }
    if securityStatus >= 0.45 { return .highSecurity }
    if securityStatus > 0 { return .lowSecurity }
    return .nullSecurity
  }
}

public struct FacilityRig: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var typeID: Int64?
  public var name: String
  public var materialMultiplier: Double
  public var timeMultiplier: Double
  public var jobCostMultiplier: Double
  public var source: SourceIdentity?

  public init(
    id: UUID = UUID(),
    typeID: Int64? = nil,
    name: String,
    materialMultiplier: Double = 1,
    timeMultiplier: Double = 1,
    jobCostMultiplier: Double = 1,
    source: SourceIdentity? = nil
  ) {
    self.id = id
    self.typeID = typeID
    self.name = name
    self.materialMultiplier = materialMultiplier
    self.timeMultiplier = timeMultiplier
    self.jobCostMultiplier = jobCostMultiplier
    self.source = source
  }
}

public struct ManufacturingProfile: Identifiable, Codable, Sendable {
  public let id: UUID
  public var name: String
  public var characterID: Int64?
  public var solarSystemID: Int64
  public var securityBand: SecurityBand
  public var structureTypeID: Int64?
  public var structureName: String
  public var rigs: [FacilityRig]
  public var facilityTaxRate: Double
  public var cloneState: CloneState
  public var defaultIntermediateME: Int
  public var defaultIntermediateTE: Int
  public var manualEffectiveMaterialMultiplier: Double?
  public var manualEffectiveTimeMultiplier: Double?
  public var manualEffectiveJobCostMultiplier: Double?
  public var effectiveSalesTaxRate: Double?
  public var effectiveBrokerFeeRate: Double?
  public var ruleVersion: String

  public init(
    id: UUID = UUID(),
    name: String = "Manufacturing",
    characterID: Int64? = nil,
    solarSystemID: Int64 = EVEConstants.jitaSystemID,
    securityBand: SecurityBand = .highSecurity,
    structureTypeID: Int64? = nil,
    structureName: String = "Unconfigured structure",
    rigs: [FacilityRig] = [],
    facilityTaxRate: Double = 0,
    cloneState: CloneState = .unknown,
    defaultIntermediateME: Int = 10,
    defaultIntermediateTE: Int = 20,
    manualEffectiveMaterialMultiplier: Double? = nil,
    manualEffectiveTimeMultiplier: Double? = nil,
    manualEffectiveJobCostMultiplier: Double? = nil,
    effectiveSalesTaxRate: Double? = nil,
    effectiveBrokerFeeRate: Double? = nil,
    ruleVersion: String = IndustryRuleSet.current.version
  ) {
    self.id = id
    self.name = name
    self.characterID = characterID
    self.solarSystemID = solarSystemID
    self.securityBand = securityBand
    self.structureTypeID = structureTypeID
    self.structureName = structureName
    self.rigs = rigs
    self.facilityTaxRate = facilityTaxRate
    self.cloneState = cloneState
    self.defaultIntermediateME = defaultIntermediateME
    self.defaultIntermediateTE = defaultIntermediateTE
    self.manualEffectiveMaterialMultiplier =
      manualEffectiveMaterialMultiplier
    self.manualEffectiveTimeMultiplier = manualEffectiveTimeMultiplier
    self.manualEffectiveJobCostMultiplier = manualEffectiveJobCostMultiplier
    self.effectiveSalesTaxRate = effectiveSalesTaxRate
    self.effectiveBrokerFeeRate = effectiveBrokerFeeRate
    self.ruleVersion = ruleVersion
  }

  public var effectiveMaterialMultiplier: Double {
    manualEffectiveMaterialMultiplier
      ?? rigs.reduce(1) { $0 * $1.materialMultiplier }
  }

  public var effectiveTimeMultiplier: Double {
    manualEffectiveTimeMultiplier
      ?? rigs.reduce(1) { $0 * $1.timeMultiplier }
  }

  public var effectiveJobCostMultiplier: Double {
    manualEffectiveJobCostMultiplier
      ?? rigs.reduce(1) { $0 * $1.jobCostMultiplier }
  }
}

public struct ReactionProfile: Identifiable, Codable, Sendable {
  public let id: UUID
  public var name: String
  public var characterID: Int64?
  public var solarSystemID: Int64
  public var securityBand: SecurityBand
  public var structureTypeID: Int64?
  public var structureName: String
  public var rigs: [FacilityRig]
  public var facilityTaxRate: Double
  public var cloneState: CloneState
  public var manualEffectiveMaterialMultiplier: Double?
  public var manualEffectiveTimeMultiplier: Double?
  public var manualEffectiveJobCostMultiplier: Double?
  public var ruleVersion: String

  public init(
    id: UUID = UUID(),
    name: String = "Reactions",
    characterID: Int64? = nil,
    solarSystemID: Int64 = EVEConstants.jitaSystemID,
    securityBand: SecurityBand = .lowSecurity,
    structureTypeID: Int64? = nil,
    structureName: String = "Unconfigured reactor",
    rigs: [FacilityRig] = [],
    facilityTaxRate: Double = 0,
    cloneState: CloneState = .unknown,
    manualEffectiveMaterialMultiplier: Double? = nil,
    manualEffectiveTimeMultiplier: Double? = nil,
    manualEffectiveJobCostMultiplier: Double? = nil,
    ruleVersion: String = IndustryRuleSet.current.version
  ) {
    self.id = id
    self.name = name
    self.characterID = characterID
    self.solarSystemID = solarSystemID
    self.securityBand = securityBand
    self.structureTypeID = structureTypeID
    self.structureName = structureName
    self.rigs = rigs
    self.facilityTaxRate = facilityTaxRate
    self.cloneState = cloneState
    self.manualEffectiveMaterialMultiplier =
      manualEffectiveMaterialMultiplier
    self.manualEffectiveTimeMultiplier = manualEffectiveTimeMultiplier
    self.manualEffectiveJobCostMultiplier = manualEffectiveJobCostMultiplier
    self.ruleVersion = ruleVersion
  }

  public var effectiveMaterialMultiplier: Double {
    manualEffectiveMaterialMultiplier
      ?? rigs.reduce(1) { $0 * $1.materialMultiplier }
  }

  public var effectiveTimeMultiplier: Double {
    manualEffectiveTimeMultiplier
      ?? rigs.reduce(1) { $0 * $1.timeMultiplier }
  }

  public var effectiveJobCostMultiplier: Double {
    manualEffectiveJobCostMultiplier
      ?? rigs.reduce(1) { $0 * $1.jobCostMultiplier }
  }
}

public struct IndustryRuleSet: Codable, Equatable, Sendable {
  public let version: String
  public let manufacturingSCCRate: Double
  public let reactionSCCRate: Double
  public let researchSCCRate: Double
  public let alphaSurchargeRate: Double

  public static let current = IndustryRuleSet(
    version: "2026.07-v1",
    manufacturingSCCRate: 0.04,
    reactionSCCRate: 0.04,
    researchSCCRate: 0.02,
    alphaSurchargeRate: 0.0025
  )
}
