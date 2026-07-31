import Foundation

public enum IndustryStructureSize: Int, Codable, CaseIterable, Identifiable,
  Sendable
{
  case medium = 2
  case large = 3
  case extraLarge = 4

  public var id: Int { rawValue }

  public var displayName: String {
    switch self {
    case .medium: "Medium"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    }
  }
}

public struct IndustryStructureDefinition: Identifiable, Codable, Equatable,
  Sendable
{
  public let typeID: Int64
  public let name: String
  public let groupID: Int64?
  public let size: IndustryStructureSize
  public let rigSlots: Int
  public let manufacturingMaterialBonusPercent: Double
  public let manufacturingTimeBonusPercent: Double
  public let jobCostMultiplier: Double
  public let source: SourceIdentity

  public var id: Int64 { typeID }

  public init(
    typeID: Int64,
    name: String,
    size: IndustryStructureSize,
    rigSlots: Int,
    manufacturingMaterialBonusPercent: Double,
    manufacturingTimeBonusPercent: Double,
    jobCostMultiplier: Double,
    source: SourceIdentity,
    groupID: Int64? = nil
  ) {
    self.typeID = typeID
    self.name = name
    self.groupID = groupID
    self.size = size
    self.rigSlots = rigSlots
    self.manufacturingMaterialBonusPercent =
      manufacturingMaterialBonusPercent
    self.manufacturingTimeBonusPercent = manufacturingTimeBonusPercent
    self.jobCostMultiplier = jobCostMultiplier
    self.source = source
  }
}

public enum IndustryFacilityServiceActivity: String, Codable, CaseIterable,
  Identifiable, Sendable
{
  case manufacturing
  case reaction
  case invention
  case copying
  case materialResearch
  case timeResearch
  case reprocessing

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .manufacturing: "Manufacturing"
    case .reaction: "Reactions"
    case .invention: "Invention"
    case .copying: "Blueprint Copying"
    case .materialResearch: "Material Research"
    case .timeResearch: "Time Research"
    case .reprocessing: "Reprocessing"
    }
  }

  public init(_ activity: IndustryActivitySystem) {
    switch activity {
    case .manufacturing: self = .manufacturing
    case .reaction: self = .reaction
    case .invention: self = .invention
    case .copying: self = .copying
    case .materialResearch: self = .materialResearch
    case .timeResearch: self = .timeResearch
    }
  }

  public var industryActivity: IndustryActivitySystem? {
    switch self {
    case .manufacturing: .manufacturing
    case .reaction: .reaction
    case .invention: .invention
    case .copying: .copying
    case .materialResearch: .materialResearch
    case .timeResearch: .timeResearch
    case .reprocessing: nil
    }
  }
}

public struct IndustryServiceModuleDefinition: Identifiable, Codable,
  Equatable, Sendable
{
  public let typeID: Int64
  public let name: String
  public let activities: [IndustryFacilityServiceActivity]
  public let compatibleStructureGroupIDs: [Int64]
  public let compatibleStructureTypeIDs: [Int64]
  public let normalOreYieldMultiplier: Double?
  public let moonOreYieldMultiplier: Double?
  public let iceYieldMultiplier: Double?
  public let gasYieldMultiplier: Double?
  public let source: SourceIdentity

  public var id: Int64 { typeID }

  public init(
    typeID: Int64,
    name: String,
    activities: [IndustryFacilityServiceActivity],
    compatibleStructureGroupIDs: [Int64] = [],
    compatibleStructureTypeIDs: [Int64] = [],
    normalOreYieldMultiplier: Double? = nil,
    moonOreYieldMultiplier: Double? = nil,
    iceYieldMultiplier: Double? = nil,
    gasYieldMultiplier: Double? = nil,
    source: SourceIdentity
  ) {
    self.typeID = typeID
    self.name = name
    self.activities = activities
    self.compatibleStructureGroupIDs = compatibleStructureGroupIDs
    self.compatibleStructureTypeIDs = compatibleStructureTypeIDs
    self.normalOreYieldMultiplier = normalOreYieldMultiplier
    self.moonOreYieldMultiplier = moonOreYieldMultiplier
    self.iceYieldMultiplier = iceYieldMultiplier
    self.gasYieldMultiplier = gasYieldMultiplier
    self.source = source
  }

  public func isCompatible(
    structureTypeID: Int64?,
    structureGroupID: Int64?
  ) -> Bool {
    if let structureTypeID,
      compatibleStructureTypeIDs.contains(structureTypeID)
    {
      return true
    }
    if let structureGroupID,
      compatibleStructureGroupIDs.contains(structureGroupID)
    {
      return true
    }
    return compatibleStructureTypeIDs.isEmpty
      && compatibleStructureGroupIDs.isEmpty
  }
}

public struct IndustryRigDefinition: Identifiable, Codable, Equatable,
  Sendable
{
  public let typeID: Int64
  public let name: String
  public let size: IndustryStructureSize
  public let manufacturingCategories: [ManufacturingCategory]
  public let isReactionRig: Bool
  public let scienceActivities: [IndustryActivitySystem]
  public let materialBonusPercent: Double
  public let timeBonusPercent: Double
  public let jobCostBonusPercent: Double
  public let lowSecurityMultiplier: Double
  public let nullSecurityMultiplier: Double
  public let source: SourceIdentity

  public var id: Int64 { typeID }

  public init(
    typeID: Int64,
    name: String,
    size: IndustryStructureSize,
    manufacturingCategories: [ManufacturingCategory],
    isReactionRig: Bool,
    materialBonusPercent: Double,
    timeBonusPercent: Double,
    lowSecurityMultiplier: Double,
    nullSecurityMultiplier: Double,
    source: SourceIdentity,
    scienceActivities: [IndustryActivitySystem] = [],
    jobCostBonusPercent: Double = 0
  ) {
    self.typeID = typeID
    self.name = name
    self.size = size
    self.manufacturingCategories = manufacturingCategories
    self.isReactionRig = isReactionRig
    self.scienceActivities = scienceActivities
    self.materialBonusPercent = materialBonusPercent
    self.timeBonusPercent = timeBonusPercent
    self.jobCostBonusPercent = jobCostBonusPercent
    self.lowSecurityMultiplier = lowSecurityMultiplier
    self.nullSecurityMultiplier = nullSecurityMultiplier
    self.source = source
  }

  public func securityMultiplier(_ band: SecurityBand) -> Double {
    switch band {
    case .highSecurity: 1
    case .lowSecurity: lowSecurityMultiplier
    case .nullSecurity, .wormhole: nullSecurityMultiplier
    case .unknown: 1
    }
  }

  public func materialBonus(in band: SecurityBand) -> Double {
    materialBonusPercent * securityMultiplier(band)
  }

  public func timeBonus(in band: SecurityBand) -> Double {
    timeBonusPercent * securityMultiplier(band)
  }
}

public struct IndustryFacilityReferenceSnapshot: Codable, Equatable, Sendable {
  public let structures: [IndustryStructureDefinition]
  public let rigs: [IndustryRigDefinition]
  public let serviceModules: [IndustryServiceModuleDefinition]
  public let source: SourceIdentity

  public init(
    structures: [IndustryStructureDefinition],
    rigs: [IndustryRigDefinition],
    source: SourceIdentity,
    serviceModules: [IndustryServiceModuleDefinition] = []
  ) {
    self.structures = structures
    self.rigs = rigs
    self.serviceModules = serviceModules
    self.source = source
  }

  public func structure(typeID: Int64?) -> IndustryStructureDefinition? {
    guard let typeID else { return nil }
    return structures.first { $0.typeID == typeID }
  }

  public func rig(typeID: Int64?) -> IndustryRigDefinition? {
    guard let typeID else { return nil }
    return rigs.first { $0.typeID == typeID }
  }

  public func compatibleRigs(
    size: IndustryStructureSize?
  ) -> [IndustryRigDefinition] {
    guard let size else { return [] }
    return rigs.filter { $0.size == size }
  }

  public func serviceModule(
    typeID: Int64?
  ) -> IndustryServiceModuleDefinition? {
    guard let typeID else { return nil }
    return serviceModules.first { $0.typeID == typeID }
  }

  public func compatibleServiceModules(
    structureTypeID: Int64?,
    structureGroupID: Int64?
  ) -> [IndustryServiceModuleDefinition] {
    serviceModules.filter {
      $0.isCompatible(
        structureTypeID: structureTypeID,
        structureGroupID: structureGroupID
      )
    }
  }
}
