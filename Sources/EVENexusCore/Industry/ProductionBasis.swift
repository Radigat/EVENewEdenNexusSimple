import Foundation

public enum ManufacturingCategory: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case capital
  case medium
  case large
  case small
  case module
  case structures

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .capital: "Capital"
    case .large: "Large"
    case .medium: "Medium"
    case .small: "Small"
    case .module: "Modules & Components"
    case .structures: "Structures & Fuel"
    }
  }
}

public struct IndustryItemClassification: Codable, Equatable, Sendable {
  public let categoryName: String
  public let groupName: String
  public let manufacturingCategory: ManufacturingCategory

  public init(
    categoryName: String,
    groupName: String,
    manufacturingCategory: ManufacturingCategory
  ) {
    self.categoryName = categoryName
    self.groupName = groupName
    self.manufacturingCategory = manufacturingCategory
  }
}

public enum IndustryActivitySystem: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case manufacturing
  case reaction
  case invention
  case copying
  case materialResearch
  case timeResearch

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .manufacturing: "Manufacturing"
    case .reaction: "Reaction"
    case .invention: "Invention"
    case .copying: "Blueprint Copying"
    case .materialResearch: "Material Research"
    case .timeResearch: "Time Research"
    }
  }

  public var costActivity: IndustryCostActivity {
    switch self {
    case .manufacturing: .manufacturing
    case .reaction: .reaction
    case .invention: .invention
    case .copying: .copying
    case .materialResearch: .researchingMaterialEfficiency
    case .timeResearch: .researchingTimeEfficiency
    }
  }

  public var isScienceActivity: Bool {
    switch self {
    case .invention, .copying, .materialResearch, .timeResearch:
      true
    case .manufacturing, .reaction:
      false
    }
  }
}

public enum ManufacturingSystemLabel: String, Codable, CaseIterable,
  Identifiable, Sendable
{
  case all
  case smallShips
  case mediumShips
  case largeShips
  case capitalShips
  case modulesAndComponents
  case structuresAndFuel

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .all: "All manufacturing"
    case .smallShips: "Small ships"
    case .mediumShips: "Medium ships"
    case .largeShips: "Large ships"
    case .capitalShips: "Capital ships"
    case .modulesAndComponents: "Modules & components"
    case .structuresAndFuel: "Structures & fuel"
    }
  }
}

public struct ActivitySystemConfiguration: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public var activity: IndustryActivitySystem
  public var solarSystemID: Int64
  public var solarSystemName: String
  public var constellationID: Int64?
  public var constellationName: String?
  public var regionID: Int64?
  public var regionName: String?
  public var securityStatus: Double?
  public var securityClass: String?
  public var costIndexOverride: Double?
  public var productionLabels: Set<ManufacturingSystemLabel>

  public init(
    id: UUID = UUID(),
    activity: IndustryActivitySystem,
    solarSystemID: Int64 = EVEConstants.jitaSystemID,
    solarSystemName: String = "Jita",
    constellationID: Int64? = nil,
    constellationName: String? = nil,
    regionID: Int64? = nil,
    regionName: String? = nil,
    securityStatus: Double? = nil,
    securityClass: String? = nil,
    costIndexOverride: Double? = nil,
    productionLabels: Set<ManufacturingSystemLabel> = [.all]
  ) {
    self.id = id
    self.activity = activity
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.constellationID = constellationID
    self.constellationName = constellationName
    self.regionID = regionID
    self.regionName = regionName
    self.securityStatus = securityStatus
    self.securityClass = securityClass
    self.costIndexOverride = costIndexOverride
    self.productionLabels =
      productionLabels.isEmpty ? [.all] : productionLabels
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case activity
    case solarSystemID
    case solarSystemName
    case constellationID
    case constellationName
    case regionID
    case regionName
    case securityStatus
    case securityClass
    case costIndexOverride
    case productionLabels
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    activity = try container.decode(
      IndustryActivitySystem.self,
      forKey: .activity
    )
    solarSystemID = try container.decode(Int64.self, forKey: .solarSystemID)
    solarSystemName = try container.decode(
      String.self,
      forKey: .solarSystemName
    )
    constellationID = try container.decodeIfPresent(
      Int64.self,
      forKey: .constellationID
    )
    constellationName = try container.decodeIfPresent(
      String.self,
      forKey: .constellationName
    )
    regionID = try container.decodeIfPresent(
      Int64.self,
      forKey: .regionID
    )
    regionName = try container.decodeIfPresent(
      String.self,
      forKey: .regionName
    )
    securityStatus = try container.decodeIfPresent(
      Double.self,
      forKey: .securityStatus
    )
    securityClass = try container.decodeIfPresent(
      String.self,
      forKey: .securityClass
    )
    costIndexOverride = try container.decodeIfPresent(
      Double.self,
      forKey: .costIndexOverride
    )
    productionLabels =
      try container.decodeIfPresent(
        Set<ManufacturingSystemLabel>.self,
        forKey: .productionLabels
      ) ?? [.all]
    if productionLabels.isEmpty {
      productionLabels = [.all]
    }
  }

  public var productionLabelSummary: String {
    if productionLabels.contains(.all) { return ManufacturingSystemLabel.all.displayName }
    return ManufacturingSystemLabel.allCases
      .filter { productionLabels.contains($0) }
      .map(\.displayName)
      .joined(separator: ", ")
  }

  public var securityBand: SecurityBand {
    SecurityBand.resolved(
      solarSystemID: solarSystemID,
      securityStatus: securityStatus,
      regionID: regionID
    )
  }

  public mutating func apply(_ details: SolarSystemDetails) {
    solarSystemName = details.name
    constellationID = details.constellationID
    constellationName = details.constellationName
    regionID = details.regionID
    regionName = details.regionName
    securityStatus = details.securityStatus
    securityClass = details.securityClass
  }
}

public enum IndustryStructureKind: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case npcStation
  case raitaru
  case athanor
  case astrahus
  case azbel
  case tatara
  case fortizar
  case sotiyo
  case keepstar
  case draccousFortizar
  case horizonFortizar
  case marginisFortizar
  case moreauFortizar
  case prometheusFortizar
  case palatineKeepstar
  case custom

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .npcStation: "NPC Station / No structure bonus"
    case .raitaru: "Raitaru"
    case .athanor: "Athanor"
    case .astrahus: "Astrahus"
    case .azbel: "Azbel"
    case .tatara: "Tatara"
    case .fortizar: "Fortizar"
    case .sotiyo: "Sotiyo"
    case .keepstar: "Keepstar"
    case .draccousFortizar: "'Draccous' Fortizar"
    case .horizonFortizar: "'Horizon' Fortizar"
    case .marginisFortizar: "'Marginis' Fortizar"
    case .moreauFortizar: "'Moreau' Fortizar"
    case .prometheusFortizar: "'Prometheus' Fortizar"
    case .palatineKeepstar: "Upwell Palatine Keepstar"
    case .custom: "Custom"
    }
  }

  public static var selectableCases: [Self] {
    allCases.filter { $0 != .custom }
  }

  public var typeID: Int64? {
    switch self {
    case .npcStation, .custom: nil
    case .raitaru: 35_825
    case .azbel: 35_826
    case .sotiyo: 35_827
    case .astrahus: 35_832
    case .fortizar: 35_833
    case .keepstar: 35_834
    case .athanor: 35_835
    case .tatara: 35_836
    case .palatineKeepstar: 40_340
    case .moreauFortizar: 47_512
    case .draccousFortizar: 47_513
    case .horizonFortizar: 47_514
    case .marginisFortizar: 47_515
    case .prometheusFortizar: 47_516
    }
  }

  public init?(typeID: Int64) {
    guard
      let resolved = Self.selectableCases.first(where: {
        $0.typeID == typeID
      })
    else { return nil }
    self = resolved
  }

  public var defaultManufacturingMaterialBonusPercent: Double {
    switch self {
    case .raitaru, .azbel, .sotiyo: 1
    default: 0
    }
  }

  public var defaultManufacturingTimeBonusPercent: Double {
    switch self {
    case .raitaru: 15
    case .azbel: 20
    case .sotiyo: 30
    default: 0
    }
  }
}

public enum IndustryRigKind: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case none
  case smallShipI
  case smallShipII
  case mediumShipI
  case mediumShipII
  case largeShipI
  case largeShipII
  case capitalShipI
  case capitalShipII
  case equipmentI
  case equipmentII
  case structureI
  case structureII
  case compositeReactionI
  case compositeReactionII
  case hybridReactionI
  case hybridReactionII
  case biochemicalReactionI
  case biochemicalReactionII
  case custom

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .none: "No Rig"
    case .smallShipI: "Standup Ship Manufacturing Efficiency I — Small"
    case .smallShipII: "Standup Ship Manufacturing Efficiency II — Small"
    case .mediumShipI: "Standup Ship Manufacturing Efficiency I — Medium"
    case .mediumShipII: "Standup Ship Manufacturing Efficiency II — Medium"
    case .largeShipI: "Standup Ship Manufacturing Efficiency I — Large"
    case .largeShipII: "Standup Ship Manufacturing Efficiency II — Large"
    case .capitalShipI: "Standup Capital Ship Manufacturing Efficiency I"
    case .capitalShipII: "Standup Capital Ship Manufacturing Efficiency II"
    case .equipmentI: "Standup Equipment Manufacturing Efficiency I"
    case .equipmentII: "Standup Equipment Manufacturing Efficiency II"
    case .structureI: "Standup Structure Manufacturing Efficiency I"
    case .structureII: "Standup Structure Manufacturing Efficiency II"
    case .compositeReactionI: "Standup Composite Reactor Efficiency I"
    case .compositeReactionII: "Standup Composite Reactor Efficiency II"
    case .hybridReactionI: "Standup Hybrid Reactor Efficiency I"
    case .hybridReactionII: "Standup Hybrid Reactor Efficiency II"
    case .biochemicalReactionI:
      "Standup Biochemical Reactor Efficiency I"
    case .biochemicalReactionII:
      "Standup Biochemical Reactor Efficiency II"
    case .custom: "Custom Rig"
    }
  }

  public var manufacturingCategory: ManufacturingCategory? {
    switch self {
    case .smallShipI, .smallShipII: .small
    case .mediumShipI, .mediumShipII: .medium
    case .largeShipI, .largeShipII: .large
    case .capitalShipI, .capitalShipII: .capital
    case .equipmentI, .equipmentII: .module
    case .structureI, .structureII: .structures
    default: nil
    }
  }

  public var isReactionRig: Bool {
    switch self {
    case .compositeReactionI, .compositeReactionII,
      .hybridReactionI, .hybridReactionII,
      .biochemicalReactionI, .biochemicalReactionII:
      true
    default:
      false
    }
  }

  fileprivate var tier: Int? {
    switch self {
    case .smallShipI, .mediumShipI, .largeShipI, .capitalShipI,
      .equipmentI, .structureI, .compositeReactionI, .hybridReactionI,
      .biochemicalReactionI:
      1
    case .smallShipII, .mediumShipII, .largeShipII, .capitalShipII,
      .equipmentII, .structureII, .compositeReactionII, .hybridReactionII,
      .biochemicalReactionII:
      2
    default:
      nil
    }
  }
}

public enum IndustryModifierSource: String, Codable, Sendable {
  case ravworksReference
  case manual
  case staticData
  case unresolved
}

public struct IndustryRigConfiguration: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public var kind: IndustryRigKind
  public var name: String
  public var materialBonusPercent: Double
  public var timeBonusPercent: Double
  public var source: IndustryModifierSource
  public var typeID: Int64?
  public var compatibleStructureSize: IndustryStructureSize?
  public var manufacturingCategories: [ManufacturingCategory]?
  public var reactionRig: Bool?
  public var scienceActivities: [IndustryActivitySystem]?
  public var baseMaterialBonusPercent: Double?
  public var baseTimeBonusPercent: Double?
  public var jobCostBonusPercent: Double?
  public var baseJobCostBonusPercent: Double?
  public var lowSecurityMultiplier: Double?
  public var nullSecurityMultiplier: Double?

  public init(
    id: UUID = UUID(),
    kind: IndustryRigKind = .none,
    name: String? = nil,
    materialBonusPercent: Double? = nil,
    timeBonusPercent: Double? = nil,
    securityBand: SecurityBand = .highSecurity,
    source: IndustryModifierSource? = nil
  ) {
    self.id = id
    self.kind = kind
    self.name = name ?? kind.displayName
    let scale = Self.securityScale(securityBand)
    let baseMaterial = kind.tier == 2 ? 2.4 : (kind.tier == 1 ? 2 : 0)
    let baseTime = kind.tier == 2 ? 24.0 : (kind.tier == 1 ? 20 : 0)
    self.materialBonusPercent = materialBonusPercent ?? baseMaterial * scale
    self.timeBonusPercent = timeBonusPercent ?? baseTime * scale
    self.source = source ?? (kind == .custom ? .manual : .ravworksReference)
    self.typeID = nil
    self.compatibleStructureSize = nil
    self.manufacturingCategories = nil
    self.reactionRig = nil
    self.scienceActivities = nil
    self.baseMaterialBonusPercent = nil
    self.baseTimeBonusPercent = nil
    self.jobCostBonusPercent = nil
    self.baseJobCostBonusPercent = nil
    self.lowSecurityMultiplier = nil
    self.nullSecurityMultiplier = nil
  }

  public init(
    id: UUID = UUID(),
    definition: IndustryRigDefinition
  ) {
    self.id = id
    self.kind = .none
    self.name = definition.name
    self.materialBonusPercent = definition.materialBonusPercent
    self.timeBonusPercent = definition.timeBonusPercent
    self.source = .staticData
    self.typeID = definition.typeID
    self.compatibleStructureSize = definition.size
    self.manufacturingCategories = definition.manufacturingCategories
    self.reactionRig = definition.isReactionRig
    self.scienceActivities = definition.scienceActivities
    self.baseMaterialBonusPercent = definition.materialBonusPercent
    self.baseTimeBonusPercent = definition.timeBonusPercent
    self.jobCostBonusPercent = definition.jobCostBonusPercent
    self.baseJobCostBonusPercent = definition.jobCostBonusPercent
    self.lowSecurityMultiplier = definition.lowSecurityMultiplier
    self.nullSecurityMultiplier = definition.nullSecurityMultiplier
  }

  public func supports(_ category: ManufacturingCategory) -> Bool {
    if let manufacturingCategories {
      return manufacturingCategories.contains(category)
    }
    return kind.manufacturingCategory == category
  }

  public var isReactionRig: Bool {
    reactionRig ?? kind.isReactionRig
  }

  public func supportsScience(_ activity: IndustryActivitySystem) -> Bool {
    activity.isScienceActivity
      && (scienceActivities?.contains(activity) ?? false)
  }

  public func materialBonus(in band: SecurityBand) -> Double {
    guard let baseMaterialBonusPercent else {
      return materialBonusPercent
    }
    return baseMaterialBonusPercent * securityMultiplier(in: band)
  }

  public func timeBonus(in band: SecurityBand) -> Double {
    guard let baseTimeBonusPercent else {
      return timeBonusPercent
    }
    return baseTimeBonusPercent * securityMultiplier(in: band)
  }

  public func jobCostBonus(in band: SecurityBand) -> Double {
    guard let baseJobCostBonusPercent else {
      return jobCostBonusPercent ?? 0
    }
    return baseJobCostBonusPercent * securityMultiplier(in: band)
  }

  private func securityMultiplier(in band: SecurityBand) -> Double {
    switch band {
    case .highSecurity: 1
    case .lowSecurity: lowSecurityMultiplier ?? 1
    case .nullSecurity, .wormhole: nullSecurityMultiplier ?? 1
    case .unknown: 1
    }
  }

  public static func securityScale(_ band: SecurityBand) -> Double {
    switch band {
    case .highSecurity: 1
    case .lowSecurity: 1.9
    case .nullSecurity, .wormhole: 2.1
    case .unknown: 1
    }
  }
}

public struct IndustryServiceModuleConfiguration: Identifiable, Codable,
  Equatable, Sendable
{
  public let id: UUID
  public var typeID: Int64?
  public var name: String
  public var activities: [IndustryFacilityServiceActivity]
  public var compatibleStructureGroupIDs: [Int64]
  public var compatibleStructureTypeIDs: [Int64]
  public var normalOreYieldMultiplier: Double?
  public var moonOreYieldMultiplier: Double?
  public var iceYieldMultiplier: Double?
  public var gasYieldMultiplier: Double?
  public var source: IndustryModifierSource

  public init(
    id: UUID = UUID(),
    definition: IndustryServiceModuleDefinition? = nil
  ) {
    self.id = id
    typeID = definition?.typeID
    name = definition?.name ?? "Select service module"
    activities = definition?.activities ?? []
    compatibleStructureGroupIDs =
      definition?.compatibleStructureGroupIDs ?? []
    compatibleStructureTypeIDs =
      definition?.compatibleStructureTypeIDs ?? []
    normalOreYieldMultiplier = definition?.normalOreYieldMultiplier
    moonOreYieldMultiplier = definition?.moonOreYieldMultiplier
    iceYieldMultiplier = definition?.iceYieldMultiplier
    gasYieldMultiplier = definition?.gasYieldMultiplier
    source = definition == nil ? .unresolved : .staticData
  }

  public func supports(
    _ activity: IndustryFacilityServiceActivity
  ) -> Bool {
    source != .unresolved && activities.contains(activity)
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

public struct ConfiguredIndustryStructure: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public var name: String
  public var kind: IndustryStructureKind
  public var manufacturingSystemID: UUID?
  public var solarSystemID: Int64
  public var solarSystemName: String
  public var securityBand: SecurityBand
  public var facilityTaxRate: Double
  public var rigs: [IndustryRigConfiguration]
  public var serviceModules: [IndustryServiceModuleConfiguration]?
  public var structureMaterialBonusPercent: Double
  public var structureTimeBonusPercent: Double
  public var jobCostMultiplier: Double
  public var source: IndustryModifierSource
  public var structureID: Int64?
  public var eveStructureName: String?
  public var ownerCorporationID: Int64?
  public var structureTypeID: Int64?
  public var structureGroupID: Int64?
  public var rigSize: IndustryStructureSize?
  public var maximumRigSlots: Int?
  public var securityStatus: Double?

  public init(
    id: UUID = UUID(),
    name: String = "",
    kind: IndustryStructureKind = .npcStation,
    manufacturingSystemID: UUID? = nil,
    solarSystemID: Int64 = EVEConstants.jitaSystemID,
    solarSystemName: String = "Jita",
    securityBand: SecurityBand? = nil,
    securityStatus: Double? = nil,
    regionID: Int64? = nil,
    facilityTaxRate: Double = 0,
    rigs: [IndustryRigConfiguration] = [],
    serviceModules: [IndustryServiceModuleConfiguration]? = nil,
    structureMaterialBonusPercent: Double? = nil,
    structureTimeBonusPercent: Double? = nil,
    jobCostMultiplier: Double = 1,
    source: IndustryModifierSource? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.manufacturingSystemID = manufacturingSystemID
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.securityBand =
      securityBand
      ?? SecurityBand.resolved(
        solarSystemID: solarSystemID,
        securityStatus: securityStatus,
        regionID: regionID
      )
    self.facilityTaxRate = facilityTaxRate
    self.rigs = rigs
    self.serviceModules = serviceModules
    self.structureMaterialBonusPercent =
      structureMaterialBonusPercent
      ?? kind.defaultManufacturingMaterialBonusPercent
    self.structureTimeBonusPercent =
      structureTimeBonusPercent
      ?? kind.defaultManufacturingTimeBonusPercent
    self.jobCostMultiplier = jobCostMultiplier
    self.source = source ?? (kind == .custom ? .manual : .ravworksReference)
    self.structureID = nil
    self.eveStructureName = nil
    self.ownerCorporationID = nil
    self.structureTypeID = kind.typeID
    self.structureGroupID = nil
    self.rigSize = nil
    self.maximumRigSlots = kind == .npcStation ? 0 : 3
    self.securityStatus = securityStatus
  }

  public mutating func apply(
    definition: IndustryStructureDefinition
  ) {
    structureTypeID = definition.typeID
    structureGroupID = definition.groupID
    kind = IndustryStructureKind(typeID: definition.typeID) ?? kind
    rigSize = definition.size
    maximumRigSlots = definition.rigSlots
    structureMaterialBonusPercent =
      definition.manufacturingMaterialBonusPercent
    structureTimeBonusPercent = definition.manufacturingTimeBonusPercent
    jobCostMultiplier = definition.jobCostMultiplier
    source = .staticData
    rigs = Array(
      rigs.filter {
        $0.compatibleStructureSize == nil
          || $0.compatibleStructureSize == definition.size
      }.prefix(definition.rigSlots)
    )
    if let serviceModules {
      self.serviceModules = serviceModules.filter {
        $0.isCompatible(
          structureTypeID: definition.typeID,
          structureGroupID: definition.groupID
        )
      }
    }
  }

  public func materialBonusPercent(for category: ManufacturingCategory) -> Double {
    (1 - materialMultiplier(for: category)) * 100
  }

  public func timeBonusPercent(for category: ManufacturingCategory) -> Double {
    (1 - timeMultiplier(for: category)) * 100
  }

  public func materialMultiplier(for category: ManufacturingCategory) -> Double {
    let structureMultiplier = max(
      0,
      1 - structureMaterialBonusPercent / 100
    )
    return rigs.filter {
      $0.source != .unresolved
        && $0.supports(category)
        && ($0.compatibleStructureSize == nil
          || $0.compatibleStructureSize == rigSize)
    }.reduce(structureMultiplier) { multiplier, rig in
      multiplier * max(0, 1 - rig.materialBonus(in: securityBand) / 100)
    }
  }

  public func timeMultiplier(for category: ManufacturingCategory) -> Double {
    let structureMultiplier = max(
      0,
      1 - structureTimeBonusPercent / 100
    )
    return rigs.filter {
      $0.source != .unresolved
        && $0.supports(category)
        && ($0.compatibleStructureSize == nil
          || $0.compatibleStructureSize == rigSize)
    }.reduce(structureMultiplier) { multiplier, rig in
      multiplier * max(0, 1 - rig.timeBonus(in: securityBand) / 100)
    }
  }

  public var needsReview: Bool {
    securityBand == .unknown
      || source == .unresolved
      || rigs.contains { $0.source == .unresolved }
      || serviceCapabilityNeedsReview
  }

  public var serviceCapabilityNeedsReview: Bool {
    kind == .npcStation
      || serviceModules == nil
      || serviceModules?.contains { $0.source == .unresolved } == true
  }

  public func supportsService(
    _ activity: IndustryFacilityServiceActivity
  ) -> Bool {
    if kind == .npcStation { return true }
    guard let serviceModules else {
      return true
    }
    return serviceModules.contains { $0.supports(activity) }
  }

  public func supportsActivity(
    _ activity: IndustryActivitySystem
  ) -> Bool {
    supportsService(IndustryFacilityServiceActivity(activity))
  }

  public var hasReprocessingService: Bool {
    supportsService(.reprocessing)
  }

  public var isReactionCapable: Bool {
    guard securityBand != .highSecurity, securityBand != .unknown else {
      return false
    }
    return (kind == .athanor || kind == .tatara)
      && supportsActivity(.reaction)
  }

  public var reactionMaterialMultiplier: Double {
    let bonus = rigs.filter {
      $0.source != .unresolved && $0.isReactionRig
    }
    .map { $0.materialBonus(in: securityBand) }.reduce(0, +)
    return max(0, 1 - bonus / 100)
  }

  public var reactionTimeMultiplier: Double {
    let bonus = rigs.filter {
      $0.source != .unresolved && $0.isReactionRig
    }
    .map { $0.timeBonus(in: securityBand) }.reduce(0, +)
    return max(0, 1 - bonus / 100)
  }

  public var isScienceCapable: Bool {
    IndustryActivitySystem.allCases.contains {
      $0.isScienceActivity && isScienceCapable(for: $0)
    }
  }

  public func isScienceCapable(
    for activity: IndustryActivitySystem
  ) -> Bool {
    activity.isScienceActivity
      && securityBand != .unknown
      && kind != .custom
      && supportsActivity(activity)
  }

  public func scienceTimeMultiplier(
    for activity: IndustryActivitySystem
  ) -> Double {
    guard activity.isScienceActivity else { return 1 }
    return rigs.filter {
      $0.source != .unresolved
        && $0.supportsScience(activity)
        && ($0.compatibleStructureSize == nil
          || $0.compatibleStructureSize == rigSize)
    }.reduce(1) { multiplier, rig in
      multiplier * max(0, 1 - rig.timeBonus(in: securityBand) / 100)
    }
  }

  public func scienceJobCostMultiplier(
    for activity: IndustryActivitySystem
  ) -> Double {
    guard activity.isScienceActivity else { return jobCostMultiplier }
    let rigMultiplier = rigs.filter {
      $0.source != .unresolved
        && $0.supportsScience(activity)
        && ($0.compatibleStructureSize == nil
          || $0.compatibleStructureSize == rigSize)
    }.reduce(1) { multiplier, rig in
      multiplier * max(0, 1 - rig.jobCostBonus(in: securityBand) / 100)
    }
    return jobCostMultiplier * rigMultiplier
  }

  public var displayName: String {
    let accepted = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !accepted.isEmpty { return accepted }
    if let eveStructureName, !eveStructureName.isEmpty {
      return eveStructureName
    }
    return "Unnamed structure / station"
  }
}

public enum MarketBrokerFeeSource: String, Codable, Equatable, Sendable {
  case npcStation
  case playerStructureNotExposedByESI
  case unresolvedLocation
}

public struct MarketFeeCalculation: Codable, Equatable, Sendable {
  public let characterID: Int64
  public let locationID: Int64?
  public let locationName: String?
  public let brokerFeeSource: MarketBrokerFeeSource?
  public let accountingLevel: Int?
  public let brokerRelationsLevel: Int?
  public let factionStanding: Double?
  public let corporationStanding: Double?
  public let skillsState: DataFreshness
  public let standingsState: DataFreshness
  public let skillsSource: SourceIdentity
  public let standingsSource: SourceIdentity
  public let calculatedAt: Date
  public let ruleVersion: String
  public let warnings: [String]

  public init(
    characterID: Int64,
    locationID: Int64? = nil,
    locationName: String? = nil,
    brokerFeeSource: MarketBrokerFeeSource? = nil,
    accountingLevel: Int?,
    brokerRelationsLevel: Int?,
    factionStanding: Double?,
    corporationStanding: Double?,
    skillsState: DataFreshness,
    standingsState: DataFreshness,
    skillsSource: SourceIdentity,
    standingsSource: SourceIdentity,
    calculatedAt: Date,
    ruleVersion: String,
    warnings: [String]
  ) {
    self.characterID = characterID
    self.locationID = locationID
    self.locationName = locationName
    self.brokerFeeSource = brokerFeeSource
    self.accountingLevel = accountingLevel
    self.brokerRelationsLevel = brokerRelationsLevel
    self.factionStanding = factionStanding
    self.corporationStanding = corporationStanding
    self.skillsState = skillsState
    self.standingsState = standingsState
    self.skillsSource = skillsSource
    self.standingsSource = standingsSource
    self.calculatedAt = calculatedAt
    self.ruleVersion = ruleVersion
    self.warnings = warnings
  }

  public var freshness: DataFreshness {
    if skillsState == .forbidden || standingsState == .forbidden {
      return .forbidden
    }
    if skillsState == .unavailable || standingsState == .unavailable {
      return .unavailable
    }
    if skillsState == .partial || standingsState == .partial {
      return .partial
    }
    if skillsState == .stale || standingsState == .stale {
      return .stale
    }
    return .fresh
  }
}

public struct MarketTaxConfiguration: Codable, Equatable, Sendable {
  public static let ruleVersion = "ccp-market-fees-2026-07-02"

  public var traderCharacterID: Int64?
  public var salesTaxRate: Double?
  public var brokerFeeRate: Double?
  public var calculation: MarketFeeCalculation?

  public init(
    traderCharacterID: Int64? = nil,
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil,
    calculation: MarketFeeCalculation? = nil
  ) {
    self.traderCharacterID = traderCharacterID
    self.salesTaxRate = salesTaxRate
    self.brokerFeeRate = brokerFeeRate
    self.calculation = calculation
  }

  public var effectiveSalesTaxRate: Double? {
    guard calculation?.characterID == traderCharacterID else { return nil }
    return salesTaxRate
  }

  public var effectiveBrokerFeeRate: Double? {
    guard calculation?.characterID == traderCharacterID else { return nil }
    return brokerFeeRate
  }

  public func isTraderSelectionValid(
    connectedCharacterIDs: Set<Int64>
  ) -> Bool {
    guard let traderCharacterID else { return true }
    return connectedCharacterIDs.contains(traderCharacterID)
  }

  public mutating func selectTrader(
    characterID: Int64?,
    capability: CharacterCapabilitySnapshot?
  ) {
    traderCharacterID = characterID
    guard let characterID,
      let capability,
      capability.character.id == characterID
    else {
      salesTaxRate = nil
      brokerFeeRate = nil
      calculation = nil
      return
    }
    apply(capability: capability)
  }

  public mutating func apply(
    capability: CharacterCapabilitySnapshot,
    at location: ProcurementLocation = .jita
  ) {
    traderCharacterID = capability.character.id
    let acceptedSkillStates: Set<DataFreshness> = [.fresh, .stale]
    let acceptedStandingStates: Set<DataFreshness> = [.fresh, .stale]
    let skillValues =
      acceptedSkillStates.contains(capability.skills.state)
      ? capability.skills.value : nil
    let standingValues =
      acceptedStandingStates.contains(capability.standings.state)
      ? capability.standings.value : nil
    let accountingLevel = skillValues.map { skills in
      skills.first {
        $0.skillID == EVEConstants.accountingSkillTypeID
      }?.activeLevel ?? 0
    }
    let brokerRelationsLevel = skillValues.map { skills in
      skills.first {
        $0.skillID == EVEConstants.brokerRelationsSkillTypeID
      }?.activeLevel ?? 0
    }
    let factionStanding = standingValues.flatMap { standings in
      location.ownerFactionID.map { standings[$0] ?? 0 }
    }
    let corporationStanding = standingValues.flatMap { standings in
      location.ownerCorporationID.map { standings[$0] ?? 0 }
    }

    salesTaxRate = accountingLevel.map {
      max(0, 0.075 * (1 - 0.11 * Double(min(max($0, 0), 5))))
    }
    let brokerFeeSource: MarketBrokerFeeSource
    if location.kind == .playerStructure {
      brokerFeeSource = .playerStructureNotExposedByESI
      brokerFeeRate = nil
    } else if let brokerRelationsLevel, let factionStanding,
      let corporationStanding
    {
      brokerFeeSource = .npcStation
      brokerFeeRate = max(
        0.01,
        0.03
          - 0.003 * Double(min(max(brokerRelationsLevel, 0), 5))
          - 0.0003 * min(max(factionStanding, -10), 10)
          - 0.0002 * min(max(corporationStanding, -10), 10)
      )
    } else {
      brokerFeeSource = .unresolvedLocation
      brokerFeeRate = nil
    }

    var warnings: [String] = []
    if salesTaxRate == nil {
      warnings.append("Accounting skill data is unavailable.")
    }
    if brokerFeeSource == .playerStructureNotExposedByESI {
      warnings.append(
        "The Player Structure broker fee is owner-defined and is not exposed by ESI."
      )
    } else if brokerFeeRate == nil {
      warnings.append(
        "The station owner, Broker Relations or standing data is unavailable."
      )
    }
    if capability.skills.state == .stale
      || capability.standings.state == .stale
    {
      warnings.append("The fee calculation uses a stale ESI snapshot.")
    }
    calculation = MarketFeeCalculation(
      characterID: capability.character.id,
      locationID: location.locationID,
      locationName: location.name,
      brokerFeeSource: brokerFeeSource,
      accountingLevel: accountingLevel,
      brokerRelationsLevel: brokerRelationsLevel,
      factionStanding: factionStanding,
      corporationStanding: corporationStanding,
      skillsState: capability.skills.state,
      standingsState: capability.standings.state,
      skillsSource: capability.skills.source,
      standingsSource: capability.standings.source,
      calculatedAt: .now,
      ruleVersion: Self.ruleVersion,
      warnings: warnings
    )
  }

  private enum CodingKeys: String, CodingKey {
    case traderCharacterID
    case salesTaxRate
    case brokerFeeRate
    case calculation
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    traderCharacterID = try container.decodeIfPresent(
      Int64.self,
      forKey: .traderCharacterID
    )
    salesTaxRate = try container.decodeIfPresent(
      Double.self,
      forKey: .salesTaxRate
    )
    brokerFeeRate = try container.decodeIfPresent(
      Double.self,
      forKey: .brokerFeeRate
    )
    calculation = try container.decodeIfPresent(
      MarketFeeCalculation.self,
      forKey: .calculation
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(
      traderCharacterID,
      forKey: .traderCharacterID
    )
    try container.encodeIfPresent(salesTaxRate, forKey: .salesTaxRate)
    try container.encodeIfPresent(brokerFeeRate, forKey: .brokerFeeRate)
    try container.encodeIfPresent(calculation, forKey: .calculation)
  }
}

public struct ProductionSchedulingConfiguration: Codable, Equatable, Sendable {
  public var reactionSlots: Int
  public var manufacturingSlots: Int
  public var doNotSplitShorterThanDays: Double
  public var maximumJobDays: Double
  public var alwaysUseDefaultMode: Bool

  public init(
    reactionSlots: Int = 1,
    manufacturingSlots: Int = 1,
    doNotSplitShorterThanDays: Double = 1,
    maximumJobDays: Double = 3,
    alwaysUseDefaultMode: Bool = false
  ) {
    self.reactionSlots = reactionSlots
    self.manufacturingSlots = manufacturingSlots
    self.doNotSplitShorterThanDays = doNotSplitShorterThanDays
    self.maximumJobDays = maximumJobDays
    self.alwaysUseDefaultMode = alwaysUseDefaultMode
  }
}

public struct LogisticsConfiguration: Codable, Equatable, Sendable {
  public static let ruleVersion = "main-hub-to-production-2026-08-01"
  public static let legacySingleContractRuleVersion =
    "standard-haulage-2026-07-30"
  public static let collateralRate = 0.005
  public static let defaultMaximumContractVolumeM3 = 350_000.0
  public static let roundingIncrement = 1_000_000.0

  public var isEnabled: Bool
  public var includeInboundMaterials: Bool
  public var includeOutboundProducts: Bool
  public var productionLocationName: String
  public var marketLocationName: String
  public var homeTradeHub: ProcurementLocation
  public var iskPerCubicMeter: Double?
  public var maximumContractVolumeM3: Double
  public var ruleVersion: String

  public init(
    isEnabled: Bool = false,
    includeInboundMaterials: Bool = true,
    includeOutboundProducts: Bool = false,
    productionLocationName: String = "UALX-3 - Mothership Bellicose",
    marketLocationName: String =
      "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
    homeTradeHub: ProcurementLocation? = nil,
    iskPerCubicMeter: Double? = nil,
    maximumContractVolumeM3: Double =
      LogisticsConfiguration.defaultMaximumContractVolumeM3,
    ruleVersion: String = LogisticsConfiguration.ruleVersion
  ) {
    self.isEnabled = isEnabled
    self.includeInboundMaterials = includeInboundMaterials
    self.includeOutboundProducts = includeOutboundProducts
    self.productionLocationName = productionLocationName
    self.marketLocationName = marketLocationName
    self.homeTradeHub =
      homeTradeHub ?? .legacy(name: productionLocationName)
    self.iskPerCubicMeter = iskPerCubicMeter
    self.maximumContractVolumeM3 = maximumContractVolumeM3
    self.ruleVersion = ruleVersion
  }

  public var effectiveISKPerCubicMeter: Double? {
    guard let iskPerCubicMeter, iskPerCubicMeter.isFinite,
      iskPerCubicMeter > 0
    else { return nil }
    return iskPerCubicMeter
  }

  public var effectiveMaximumContractVolumeM3: Double? {
    guard maximumContractVolumeM3.isFinite, maximumContractVolumeM3 > 0
    else { return nil }
    return maximumContractVolumeM3
  }

  public var effectiveRuleVersion: String {
    Self.ruleVersion
  }

  private enum CodingKeys: String, CodingKey {
    case isEnabled, includeInboundMaterials, includeOutboundProducts
    case productionLocationName, marketLocationName, homeTradeHub
    case iskPerCubicMeter, maximumContractVolumeM3, ruleVersion
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    includeInboundMaterials =
      try container.decodeIfPresent(Bool.self, forKey: .includeInboundMaterials) ?? true
    includeOutboundProducts =
      try container.decodeIfPresent(Bool.self, forKey: .includeOutboundProducts) ?? false
    productionLocationName =
      try container.decodeIfPresent(String.self, forKey: .productionLocationName) ?? "UALX"
    marketLocationName =
      try container.decodeIfPresent(String.self, forKey: .marketLocationName)
      ?? ProcurementLocation.jita.name
    homeTradeHub =
      try container.decodeIfPresent(ProcurementLocation.self, forKey: .homeTradeHub)
      ?? .legacy(name: productionLocationName)
    iskPerCubicMeter = try container.decodeIfPresent(Double.self, forKey: .iskPerCubicMeter)
    maximumContractVolumeM3 =
      try container.decodeIfPresent(Double.self, forKey: .maximumContractVolumeM3)
      ?? Self.defaultMaximumContractVolumeM3
    ruleVersion =
      try container.decodeIfPresent(String.self, forKey: .ruleVersion) ?? Self.ruleVersion
  }
}

public struct TradingLocationConfiguration: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public var location: ProcurementLocation
  public var marketTaxes: MarketTaxConfiguration

  public init(
    id: UUID = UUID(),
    location: ProcurementLocation,
    traderCharacterID: Int64? = nil,
    marketTaxes: MarketTaxConfiguration? = nil
  ) {
    self.id = id
    self.location = location
    self.marketTaxes =
      marketTaxes
      ?? MarketTaxConfiguration(traderCharacterID: traderCharacterID)
  }

  public var traderCharacterID: Int64? {
    get { marketTaxes.traderCharacterID }
    set {
      marketTaxes.selectTrader(characterID: newValue, capability: nil)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case location
    case traderCharacterID
    case marketTaxes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    location = try container.decode(
      ProcurementLocation.self,
      forKey: .location
    )
    if let decodedTaxes = try container.decodeIfPresent(
      MarketTaxConfiguration.self,
      forKey: .marketTaxes
    ) {
      marketTaxes = decodedTaxes
    } else {
      marketTaxes = MarketTaxConfiguration(
        traderCharacterID: try container.decodeIfPresent(
          Int64.self,
          forKey: .traderCharacterID
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(location, forKey: .location)
    try container.encode(marketTaxes, forKey: .marketTaxes)
  }
}

extension ProcurementLocation {
  public static func playerStructure(
    _ structure: ConfiguredIndustryStructure
  ) -> ProcurementLocation? {
    guard structure.structureID != nil || structure.eveStructureName != nil else {
      return nil
    }
    return ProcurementLocation(
      id: structure.structureID.map { "structure:\($0)" }
        ?? "structure:\(structure.id.uuidString)",
      name: structure.displayName,
      locationID: structure.structureID,
      kind: .playerStructure,
      solarSystemID: structure.solarSystemID
    )
  }
}

public enum ProductionBlacklistPreset: String, Codable, CaseIterable,
  Identifiable, Sendable
{
  case fuelBlocks
  case tools
  case techOneHulls
  case capitalComponents
  case advancedComponents
  case advancedCapitalComponents
  case hybridComponents
  case intermediateCompositeReactions
  case compositeReactions
  case hybridReactions
  case biochemicalReactions
  case gasPhaseReactions

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .fuelBlocks: "Fuel Blocks"
    case .tools: "Tools (R.A.M.)"
    case .techOneHulls: "Tech 1 Hulls"
    case .capitalComponents: "Capital Components"
    case .advancedComponents: "Advanced Components"
    case .advancedCapitalComponents: "Advanced Capital Components"
    case .hybridComponents: "Hybrid Components"
    case .intermediateCompositeReactions:
      "Intermediate Composite Reactions"
    case .compositeReactions: "Composite Reactions"
    case .hybridReactions: "Hybrid Reactions"
    case .biochemicalReactions: "Biochemical Reactions"
    case .gasPhaseReactions: "Gas-Phase Reactions"
    }
  }
}

public struct ProductionBlacklistConfiguration: Codable, Equatable, Sendable {
  public var presets: Set<ProductionBlacklistPreset>
  public var typeNames: [String]

  public init(
    presets: Set<ProductionBlacklistPreset> = [],
    typeNames: [String] = []
  ) {
    self.presets = presets
    self.typeNames = typeNames
  }

  public func blocks(
    typeName: String,
    classification: IndustryItemClassification?
  ) -> Bool {
    if typeNames.contains(where: {
      $0.caseInsensitiveCompare(typeName) == .orderedSame
    }) {
      return true
    }
    let name = typeName.lowercased()
    let group = classification?.groupName.lowercased() ?? ""
    let category = classification?.categoryName.lowercased() ?? ""
    for preset in presets {
      switch preset {
      case .fuelBlocks where group.contains("fuel block"):
        return true
      case .tools
      where group.contains("tool") || name.hasPrefix("r.a.m."):
        return true
      case .techOneHulls where category == "ship":
        return true
      case .capitalComponents
      where group.contains("capital construction component"):
        return true
      case .advancedComponents
      where group.contains("advanced component"):
        return true
      case .advancedCapitalComponents
      where group.contains("advanced capital"):
        return true
      case .hybridComponents where group.contains("hybrid component"):
        return true
      case .intermediateCompositeReactions
      where group.contains("intermediate") && group.contains("reaction"):
        return true
      case .compositeReactions where group.contains("composite reaction"):
        return true
      case .hybridReactions where group.contains("hybrid reaction"):
        return true
      case .biochemicalReactions where group.contains("biochemical reaction"):
        return true
      case .gasPhaseReactions where group.contains("gas") && group.contains("reaction"):
        return true
      default:
        continue
      }
    }
    return false
  }
}

public struct InventionConfiguration: Codable, Equatable, Sendable {
  public var jobCostReductionRate: Double
  public var encryptionSkillLevel: Int?
  public var scienceSkillOneLevel: Int?
  public var scienceSkillTwoLevel: Int?

  public init(
    jobCostReductionRate: Double = 0,
    encryptionSkillLevel: Int? = nil,
    scienceSkillOneLevel: Int? = nil,
    scienceSkillTwoLevel: Int? = nil
  ) {
    self.jobCostReductionRate = jobCostReductionRate
    self.encryptionSkillLevel = encryptionSkillLevel
    self.scienceSkillOneLevel = scienceSkillOneLevel
    self.scienceSkillTwoLevel = scienceSkillTwoLevel
  }
}

public struct ProductionFacilitySelection: Codable, Equatable, Sendable {
  public let category: ManufacturingCategory
  public let structureID: UUID
  public let structureName: String
  public let solarSystemID: Int64?
  public let solarSystemName: String?
  public let materialBonusPercent: Double
  public let timeBonusPercent: Double
  public let materialMultiplier: Double
  public let timeMultiplier: Double
  public let isManualAssignment: Bool
  public let needsReview: Bool
  public let explanation: String
}

public struct ReactionFacilitySelection: Codable, Equatable, Sendable {
  public let structureID: UUID
  public let structureName: String
  public let solarSystemID: Int64
  public let solarSystemName: String
  public let materialBonusPercent: Double
  public let timeBonusPercent: Double
  public let materialMultiplier: Double
  public let timeMultiplier: Double
  public let isManualAssignment: Bool
  public let needsReview: Bool
  public let explanation: String
}

public struct ScienceFacilitySelection: Codable, Equatable, Sendable {
  public let activity: IndustryActivitySystem
  public let structureID: UUID
  public let structureName: String
  public let solarSystemID: Int64
  public let solarSystemName: String
  public let jobCostBonusPercent: Double
  public let timeBonusPercent: Double
  public let jobCostMultiplier: Double
  public let timeMultiplier: Double
  public let isManualAssignment: Bool
  public let needsReview: Bool
  public let explanation: String
}

public struct ProductionBasis: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var manufacturingSystems: [ActivitySystemConfiguration]
  public var reactionSystem: ActivitySystemConfiguration
  public var inventionSystem: ActivitySystemConfiguration
  public var copyingSystem: ActivitySystemConfiguration
  public var materialResearchSystem: ActivitySystemConfiguration
  public var timeResearchSystem: ActivitySystemConfiguration
  public var cloneState: CloneState
  public var marketTaxes: MarketTaxConfiguration
  public var tradingLocations: [TradingLocationConfiguration]
  public var mainTradingLocationID: UUID?
  public var homeTradingLocationID: UUID?
  public var logistics: LogisticsConfiguration
  public var scheduling: ProductionSchedulingConfiguration
  public var invention: InventionConfiguration
  public var blacklist: ProductionBlacklistConfiguration
  public var structures: [ConfiguredIndustryStructure]
  public var automaticStructureSelection: Bool
  public var manufacturingAssignments: [ManufacturingCategory: UUID]
  public var reactionStructureID: UUID?
  public var scienceAssignments: [IndustryActivitySystem: UUID]
  public var defaultIntermediateME: Int
  public var defaultIntermediateTE: Int
  public var ruleVersion: String

  public init(
    id: UUID = UUID(),
    name: String = "Production Basis",
    manufacturingSystems: [ActivitySystemConfiguration] = [
      .init(activity: .manufacturing)
    ],
    reactionSystem: ActivitySystemConfiguration = .init(
      activity: .reaction,
      solarSystemID: 0,
      solarSystemName: "Select reaction system"
    ),
    inventionSystem: ActivitySystemConfiguration = .init(
      activity: .invention,
      solarSystemID: 0,
      solarSystemName: "Select invention system"
    ),
    copyingSystem: ActivitySystemConfiguration = .init(
      activity: .copying,
      solarSystemID: 0,
      solarSystemName: "Select copying system"
    ),
    materialResearchSystem: ActivitySystemConfiguration = .init(
      activity: .materialResearch,
      solarSystemID: 0,
      solarSystemName: "Select material research system"
    ),
    timeResearchSystem: ActivitySystemConfiguration = .init(
      activity: .timeResearch,
      solarSystemID: 0,
      solarSystemName: "Select time research system"
    ),
    cloneState: CloneState = .unknown,
    marketTaxes: MarketTaxConfiguration = .init(),
    tradingLocations: [TradingLocationConfiguration] = [],
    mainTradingLocationID: UUID? = nil,
    homeTradingLocationID: UUID? = nil,
    logistics: LogisticsConfiguration = .init(),
    scheduling: ProductionSchedulingConfiguration = .init(),
    invention: InventionConfiguration = .init(),
    blacklist: ProductionBlacklistConfiguration = .init(),
    structures: [ConfiguredIndustryStructure] = [],
    automaticStructureSelection: Bool = true,
    manufacturingAssignments: [ManufacturingCategory: UUID] = [:],
    reactionStructureID: UUID? = nil,
    scienceAssignments: [IndustryActivitySystem: UUID] = [:],
    defaultIntermediateME: Int = 10,
    defaultIntermediateTE: Int = 20,
    ruleVersion: String = IndustryRuleSet.current.version
  ) {
    let acceptedManufacturingSystems =
      manufacturingSystems.isEmpty
      ? [ActivitySystemConfiguration(activity: .manufacturing)]
      : manufacturingSystems
    self.id = id
    self.name = name
    self.manufacturingSystems = acceptedManufacturingSystems
    self.reactionSystem = reactionSystem
    self.inventionSystem = inventionSystem
    self.copyingSystem = copyingSystem
    self.materialResearchSystem = materialResearchSystem
    self.timeResearchSystem = timeResearchSystem
    self.cloneState = cloneState
    self.marketTaxes = marketTaxes
    self.tradingLocations = tradingLocations
    self.mainTradingLocationID = mainTradingLocationID
    self.homeTradingLocationID = homeTradingLocationID
    self.logistics = logistics
    self.scheduling = scheduling
    self.invention = invention
    self.blacklist = blacklist
    if structures.isEmpty {
      let system = acceptedManufacturingSystems[0]
      self.structures = [
        ConfiguredIndustryStructure(
          manufacturingSystemID: system.id,
          solarSystemID: system.solarSystemID,
          solarSystemName: system.solarSystemName
        )
      ]
    } else {
      self.structures = structures
    }
    self.automaticStructureSelection = automaticStructureSelection
    self.manufacturingAssignments = manufacturingAssignments
    self.reactionStructureID = reactionStructureID
    self.scienceAssignments = scienceAssignments
    self.defaultIntermediateME = defaultIntermediateME
    self.defaultIntermediateTE = defaultIntermediateTE
    self.ruleVersion = ruleVersion
    normalizeTradingLocations()
    synchronizeStructuresWithManufacturingSystems()
    refreshAutomaticFacilityAssignments()
  }

  public var defaultManufacturingSystem: ActivitySystemConfiguration? {
    manufacturingSystems.first
  }

  public var configuredActivitySystems: [ActivitySystemConfiguration] {
    manufacturingSystems + [
      reactionSystem,
      inventionSystem,
      copyingSystem,
      materialResearchSystem,
      timeResearchSystem,
    ]
  }

  public var priceSourceTradingLocation: TradingLocationConfiguration? {
    mainTradingLocation
  }

  public var mainTradingLocation: TradingLocationConfiguration? {
    guard let mainTradingLocationID else { return nil }
    return tradingLocations.first { $0.id == mainTradingLocationID }
  }

  public var homeTradingLocation: TradingLocationConfiguration? {
    guard let homeTradingLocationID else { return nil }
    return tradingLocations.first { $0.id == homeTradingLocationID }
  }

  public var mainTradeHub: MarketTradeHub {
    guard let stationID = mainTradingLocation?.location.locationID,
      let hub = MarketTradeHub.matching(stationID: stationID)
    else {
      return .jita
    }
    return hub
  }

  public var configuredProcurementLocations: [ProcurementLocation] {
    tradingLocations.map(\.location)
  }

  public mutating func normalizeTradingLocations() {
    var seenLocationIDs = Set<String>()
    tradingLocations = tradingLocations.filter {
      seenLocationIDs.insert($0.location.id).inserted
    }

    let legacyMainLocation = ProcurementLocation.standardTradeHubs.first {
      $0.locationID == logistics.homeTradeHub.locationID
    } ?? .jita
    if !tradingLocations.contains(where: {
      $0.location.id == legacyMainLocation.id
    }) {
      tradingLocations.insert(
        TradingLocationConfiguration(
          location: legacyMainLocation,
          marketTaxes: marketTaxes
        ),
        at: 0
      )
    }

    let mainIsValid = mainTradingLocationID.map { mainID in
      tradingLocations.contains {
        $0.id == mainID
          && $0.location.locationID.map {
            MarketTradeHub.matching(stationID: $0) != nil
          } == true
      }
    } ?? false
    if !mainIsValid {
      mainTradingLocationID =
        tradingLocations.first {
          $0.location.id == legacyMainLocation.id
        }?.id
        ?? tradingLocations.first {
          $0.location.id == ProcurementLocation.jita.id
        }?.id
    }

    if let mainIndex = tradingLocations.firstIndex(where: {
      $0.id == mainTradingLocationID
    }) {
      let configuredTaxes = tradingLocations[mainIndex].marketTaxes
      if configuredTaxes.calculation == nil,
        marketTaxes.calculation != nil,
        configuredTaxes.traderCharacterID == marketTaxes.traderCharacterID
      {
        tradingLocations[mainIndex].marketTaxes = marketTaxes
      } else if configuredTaxes.traderCharacterID == nil,
        marketTaxes.traderCharacterID != nil
      {
        tradingLocations[mainIndex].marketTaxes = marketTaxes
      } else {
        marketTaxes = tradingLocations[mainIndex].marketTaxes
      }
      logistics.homeTradeHub = tradingLocations[mainIndex].location
    }

    if let homeTradingLocationID,
      !tradingLocations.contains(where: { $0.id == homeTradingLocationID })
    {
      self.homeTradingLocationID = nil
    }
  }

  @discardableResult
  public mutating func addTradingLocation(
    _ location: ProcurementLocation
  ) -> Bool {
    guard
      !tradingLocations.contains(where: {
        $0.location.id == location.id
      })
    else { return false }
    tradingLocations.append(
      TradingLocationConfiguration(location: location)
    )
    normalizeTradingLocations()
    return true
  }

  @discardableResult
  public mutating func removeTradingLocation(id: UUID) -> Bool {
    guard tradingLocations.contains(where: { $0.id == id }),
      id != mainTradingLocationID,
      id != homeTradingLocationID
    else { return false }
    tradingLocations.removeAll { $0.id == id }
    normalizeTradingLocations()
    return true
  }

  public mutating func setMainTradingLocation(id: UUID) {
    guard let location = tradingLocations.first(where: { $0.id == id }),
      location.location.locationID.map({
        MarketTradeHub.matching(stationID: $0) != nil
      }) == true
    else { return }
    mainTradingLocationID = id
    normalizeTradingLocations()
  }

  public mutating func setMainTradeHub(_ hub: MarketTradeHub) {
    let location = hub.procurementLocation
    if let existing = tradingLocations.first(where: {
      $0.location.id == location.id
    }) {
      setMainTradingLocation(id: existing.id)
      return
    }
    tradingLocations.append(TradingLocationConfiguration(location: location))
    mainTradingLocationID = tradingLocations.last?.id
    normalizeTradingLocations()
  }

  public mutating func setHomeTradingLocation(id: UUID?) {
    guard let id else {
      homeTradingLocationID = nil
      return
    }
    guard tradingLocations.contains(where: { $0.id == id }) else { return }
    homeTradingLocationID = id
  }

  public mutating func selectTrader(
    characterID: Int64?,
    forTradingLocationID id: UUID,
    capability: CharacterCapabilitySnapshot? = nil
  ) {
    guard let index = tradingLocations.firstIndex(where: { $0.id == id })
    else { return }
    tradingLocations[index].marketTaxes.selectTrader(
      characterID: characterID,
      capability: nil
    )
    if let capability, capability.character.id == characterID {
      tradingLocations[index].marketTaxes.apply(
        capability: capability,
        at: tradingLocations[index].location
      )
    }
    if id == mainTradingLocationID {
      marketTaxes = tradingLocations[index].marketTaxes
    }
  }

  public mutating func updateTradingLocation(
    id: UUID,
    location: ProcurementLocation
  ) {
    guard let index = tradingLocations.firstIndex(where: { $0.id == id })
    else { return }
    tradingLocations[index].location = location
    if id == mainTradingLocationID {
      logistics.homeTradeHub = location
    }
  }

  public mutating func applyMarketFees(
    capability: CharacterCapabilitySnapshot,
    forTradingLocationID id: UUID
  ) {
    guard let index = tradingLocations.firstIndex(where: { $0.id == id }),
      tradingLocations[index].traderCharacterID == capability.character.id
    else { return }
    tradingLocations[index].marketTaxes.apply(
      capability: capability,
      at: tradingLocations[index].location
    )
    if id == mainTradingLocationID {
      marketTaxes = tradingLocations[index].marketTaxes
    }
  }

  public func areTraderSelectionsValid(
    connectedCharacterIDs: Set<Int64>
  ) -> Bool {
    tradingLocations.allSatisfy { configuration in
      guard let traderCharacterID = configuration.traderCharacterID else {
        return true
      }
      return connectedCharacterIDs.contains(traderCharacterID)
    }
  }

  public func systemConfiguration(
    for activity: IndustryActivitySystem
  ) -> ActivitySystemConfiguration? {
    switch activity {
    case .manufacturing:
      defaultManufacturingSystem
    case .reaction:
      reactionSystem
    case .invention:
      inventionSystem
    case .copying:
      copyingSystem
    case .materialResearch:
      materialResearchSystem
    case .timeResearch:
      timeResearchSystem
    }
  }

  public func manufacturingSystem(
    for structure: ConfiguredIndustryStructure?
  ) -> ActivitySystemConfiguration? {
    guard let structure else { return defaultManufacturingSystem }
    if let systemID = structure.manufacturingSystemID,
      let configured = manufacturingSystems.first(where: {
        $0.id == systemID
      })
    {
      return configured
    }
    return manufacturingSystems.first {
      $0.solarSystemID == structure.solarSystemID
    }
  }

  public func configuredSystem(
    for structure: ConfiguredIndustryStructure
  ) -> ActivitySystemConfiguration? {
    if let systemID = structure.manufacturingSystemID,
      let configured = configuredActivitySystems.first(where: {
        $0.id == systemID
      })
    {
      return configured
    }
    return configuredActivitySystems.first {
      $0.solarSystemID == structure.solarSystemID
    }
  }

  public func eligibleActivities(
    for structure: ConfiguredIndustryStructure
  ) -> [IndustryActivitySystem] {
    IndustryActivitySystem.allCases.filter { activity in
      let hasMatchingSystem: Bool
      switch activity {
      case .manufacturing:
        hasMatchingSystem = manufacturingSystems.contains {
          $0.solarSystemID > 0
            && $0.solarSystemID == structure.solarSystemID
        }
      case .reaction:
        hasMatchingSystem =
          reactionSystem.solarSystemID > 0
          && reactionSystem.solarSystemID == structure.solarSystemID
      case .invention, .copying, .materialResearch, .timeResearch:
        hasMatchingSystem =
          systemConfiguration(for: activity)?.solarSystemID
          == structure.solarSystemID
          && structure.solarSystemID > 0
      }
      guard hasMatchingSystem else { return false }
      if activity == .reaction {
        return structure.isReactionCapable
      }
      if activity.isScienceActivity {
        return structure.isScienceCapable(for: activity)
      }
      return structure.supportsActivity(activity)
    }
  }

  public mutating func applySystemDetails(_ details: SolarSystemDetails) {
    for index in manufacturingSystems.indices
    where manufacturingSystems[index].solarSystemID == details.id {
      manufacturingSystems[index].solarSystemName = details.name
      manufacturingSystems[index].constellationID = details.constellationID
      manufacturingSystems[index].constellationName =
        details.constellationName
      manufacturingSystems[index].regionID = details.regionID
      manufacturingSystems[index].regionName = details.regionName
      manufacturingSystems[index].securityStatus = details.securityStatus
      manufacturingSystems[index].securityClass = details.securityClass
    }
    if reactionSystem.solarSystemID == details.id {
      reactionSystem.solarSystemName = details.name
      reactionSystem.constellationID = details.constellationID
      reactionSystem.constellationName = details.constellationName
      reactionSystem.regionID = details.regionID
      reactionSystem.regionName = details.regionName
      reactionSystem.securityStatus = details.securityStatus
      reactionSystem.securityClass = details.securityClass
    }
    for activity in IndustryActivitySystem.allCases where activity != .manufacturing {
      guard systemConfiguration(for: activity)?.solarSystemID == details.id
      else { continue }
      switch activity {
      case .manufacturing:
        break
      case .reaction:
        reactionSystem.apply(details)
      case .invention:
        inventionSystem.apply(details)
      case .copying:
        copyingSystem.apply(details)
      case .materialResearch:
        materialResearchSystem.apply(details)
      case .timeResearch:
        timeResearchSystem.apply(details)
      }
    }
    synchronizeStructuresWithManufacturingSystems()
    refreshAutomaticFacilityAssignments()
  }

  private mutating func synchronizeStructuresWithManufacturingSystems() {
    for index in structures.indices {
      let structure = structures[index]
      let assignedSystem = configuredSystem(for: structure)
      guard let assignedSystem else { continue }

      structures[index].solarSystemID = assignedSystem.solarSystemID
      structures[index].solarSystemName = assignedSystem.solarSystemName
      structures[index].securityStatus = assignedSystem.securityStatus
      structures[index].securityBand = assignedSystem.securityBand
    }
  }

  public mutating func applyFacilityReferences(
    _ snapshot: IndustryFacilityReferenceSnapshot
  ) {
    for index in structures.indices {
      if structures[index].kind == .custom {
        structures[index].kind = .npcStation
        structures[index].structureTypeID = nil
        structures[index].structureGroupID = nil
        structures[index].rigSize = nil
        structures[index].maximumRigSlots = 0
        structures[index].structureMaterialBonusPercent = 0
        structures[index].structureTimeBonusPercent = 0
        structures[index].jobCostMultiplier = 1
        structures[index].source = .staticData
        structures[index].rigs = []
        continue
      }
      if structures[index].kind == .npcStation {
        structures[index].structureTypeID = nil
        structures[index].structureGroupID = nil
        structures[index].rigSize = nil
        structures[index].maximumRigSlots = 0
        structures[index].structureMaterialBonusPercent = 0
        structures[index].structureTimeBonusPercent = 0
        structures[index].jobCostMultiplier = 1
        structures[index].source = .staticData
        structures[index].rigs = []
        continue
      }
      guard
        let definition = snapshot.structure(
          typeID: structures[index].kind.typeID
        )
      else {
        structures[index].source = .unresolved
        continue
      }
      structures[index].apply(definition: definition)
      structures[index].rigs = structures[index].rigs.map { configured in
        guard
          let definition = snapshot.rig(typeID: configured.typeID),
          definition.size == structures[index].rigSize
        else {
          var unresolved = configured
          unresolved.source = .unresolved
          return unresolved
        }
        return IndustryRigConfiguration(
          id: configured.id,
          definition: definition
        )
      }
      if let serviceModules = structures[index].serviceModules {
        structures[index].serviceModules = serviceModules.map { configured in
          guard
            let definition = snapshot.serviceModule(
              typeID: configured.typeID
            ),
            definition.isCompatible(
              structureTypeID: structures[index].structureTypeID,
              structureGroupID: structures[index].structureGroupID
            )
          else {
            var unresolved = configured
            unresolved.source = .unresolved
            return unresolved
          }
          return IndustryServiceModuleConfiguration(
            id: configured.id,
            definition: definition
          )
        }
      }
    }
    refreshAutomaticFacilityAssignments()
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case manufacturingSystems
    case manufacturingSystem
    case reactionSystem
    case inventionSystem
    case copyingSystem
    case materialResearchSystem
    case timeResearchSystem
    case cloneState
    case marketTaxes
    case tradingLocations
    case mainTradingLocationID
    case homeTradingLocationID
    case logistics
    case scheduling
    case invention
    case blacklist
    case structures
    case automaticStructureSelection
    case manufacturingAssignments
    case reactionStructureID
    case scienceAssignments
    case defaultIntermediateME
    case defaultIntermediateTE
    case ruleVersion
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedSystems = try container.decodeIfPresent(
      [ActivitySystemConfiguration].self,
      forKey: .manufacturingSystems
    )
    let legacySystem = try container.decodeIfPresent(
      ActivitySystemConfiguration.self,
      forKey: .manufacturingSystem
    )
    var systems = decodedSystems ?? legacySystem.map { [$0] } ?? []
    if systems.isEmpty {
      systems = [ActivitySystemConfiguration(activity: .manufacturing)]
    }
    var decodedStructures =
      try container.decodeIfPresent(
        [ConfiguredIndustryStructure].self,
        forKey: .structures
      ) ?? []
    if decodedStructures.isEmpty {
      let system = systems[0]
      decodedStructures = [
        ConfiguredIndustryStructure(
          manufacturingSystemID: system.id,
          solarSystemID: system.solarSystemID,
          solarSystemName: system.solarSystemName
        )
      ]
    } else {
      for index in decodedStructures.indices
      where decodedStructures[index].manufacturingSystemID == nil {
        decodedStructures[index].manufacturingSystemID =
          systems.first {
            $0.solarSystemID == decodedStructures[index].solarSystemID
          }?.id ?? systems.first?.id
      }
    }

    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name =
      try container.decodeIfPresent(String.self, forKey: .name)
      ?? "Production Basis"
    manufacturingSystems = systems
    reactionSystem =
      try container.decodeIfPresent(
        ActivitySystemConfiguration.self,
        forKey: .reactionSystem
      )
      ?? ActivitySystemConfiguration(
        activity: .reaction,
        solarSystemID: 0,
        solarSystemName: "Select reaction system"
      )
    inventionSystem =
      try container.decodeIfPresent(
        ActivitySystemConfiguration.self,
        forKey: .inventionSystem
      )
      ?? ActivitySystemConfiguration(
        activity: .invention,
        solarSystemID: 0,
        solarSystemName: "Select invention system"
      )
    copyingSystem =
      try container.decodeIfPresent(
        ActivitySystemConfiguration.self,
        forKey: .copyingSystem
      )
      ?? ActivitySystemConfiguration(
        activity: .copying,
        solarSystemID: 0,
        solarSystemName: "Select copying system"
      )
    materialResearchSystem =
      try container.decodeIfPresent(
        ActivitySystemConfiguration.self,
        forKey: .materialResearchSystem
      )
      ?? ActivitySystemConfiguration(
        activity: .materialResearch,
        solarSystemID: 0,
        solarSystemName: "Select material research system"
      )
    timeResearchSystem =
      try container.decodeIfPresent(
        ActivitySystemConfiguration.self,
        forKey: .timeResearchSystem
      )
      ?? ActivitySystemConfiguration(
        activity: .timeResearch,
        solarSystemID: 0,
        solarSystemName: "Select time research system"
      )
    cloneState =
      try container.decodeIfPresent(CloneState.self, forKey: .cloneState)
      ?? .unknown
    marketTaxes =
      try container.decodeIfPresent(
        MarketTaxConfiguration.self,
        forKey: .marketTaxes
      ) ?? .init()
    tradingLocations =
      try container.decodeIfPresent(
        [TradingLocationConfiguration].self,
        forKey: .tradingLocations
      ) ?? []
    let decodedLegacyOrHomeTradingLocationID = try container.decodeIfPresent(
      UUID.self,
      forKey: .homeTradingLocationID
    )
    mainTradingLocationID = try container.decodeIfPresent(
      UUID.self,
      forKey: .mainTradingLocationID
    )
    if mainTradingLocationID == nil {
      // Before the split, homeTradingLocationID actually named the Planner
      // Main Hub. Preserve that selection while leaving the new Home Hub
      // explicitly unconfigured.
      mainTradingLocationID = decodedLegacyOrHomeTradingLocationID
      homeTradingLocationID = nil
    } else {
      homeTradingLocationID = decodedLegacyOrHomeTradingLocationID
    }
    logistics =
      try container.decodeIfPresent(
        LogisticsConfiguration.self,
        forKey: .logistics
      ) ?? .init()
    scheduling =
      try container.decodeIfPresent(
        ProductionSchedulingConfiguration.self,
        forKey: .scheduling
      ) ?? .init()
    invention =
      try container.decodeIfPresent(
        InventionConfiguration.self,
        forKey: .invention
      ) ?? .init()
    blacklist =
      try container.decodeIfPresent(
        ProductionBlacklistConfiguration.self,
        forKey: .blacklist
      ) ?? .init()
    structures = decodedStructures
    automaticStructureSelection =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .automaticStructureSelection
      ) ?? true
    manufacturingAssignments =
      try container.decodeIfPresent(
        [ManufacturingCategory: UUID].self,
        forKey: .manufacturingAssignments
      ) ?? [:]
    reactionStructureID = try container.decodeIfPresent(
      UUID.self,
      forKey: .reactionStructureID
    )
    scienceAssignments =
      try container.decodeIfPresent(
        [IndustryActivitySystem: UUID].self,
        forKey: .scienceAssignments
      ) ?? [:]
    defaultIntermediateME =
      try container.decodeIfPresent(
        Int.self,
        forKey: .defaultIntermediateME
      ) ?? 10
    defaultIntermediateTE =
      try container.decodeIfPresent(
        Int.self,
        forKey: .defaultIntermediateTE
      ) ?? 20
    ruleVersion =
      try container.decodeIfPresent(String.self, forKey: .ruleVersion)
      ?? IndustryRuleSet.current.version
    normalizeTradingLocations()
    synchronizeStructuresWithManufacturingSystems()
    refreshAutomaticFacilityAssignments()
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(manufacturingSystems, forKey: .manufacturingSystems)
    try container.encode(reactionSystem, forKey: .reactionSystem)
    try container.encode(inventionSystem, forKey: .inventionSystem)
    try container.encode(copyingSystem, forKey: .copyingSystem)
    try container.encode(
      materialResearchSystem,
      forKey: .materialResearchSystem
    )
    try container.encode(timeResearchSystem, forKey: .timeResearchSystem)
    try container.encode(cloneState, forKey: .cloneState)
    try container.encode(marketTaxes, forKey: .marketTaxes)
    try container.encode(tradingLocations, forKey: .tradingLocations)
    try container.encodeIfPresent(
      mainTradingLocationID,
      forKey: .mainTradingLocationID
    )
    try container.encodeIfPresent(
      homeTradingLocationID,
      forKey: .homeTradingLocationID
    )
    try container.encode(logistics, forKey: .logistics)
    try container.encode(scheduling, forKey: .scheduling)
    try container.encode(invention, forKey: .invention)
    try container.encode(blacklist, forKey: .blacklist)
    try container.encode(structures, forKey: .structures)
    try container.encode(
      automaticStructureSelection,
      forKey: .automaticStructureSelection
    )
    try container.encode(
      manufacturingAssignments,
      forKey: .manufacturingAssignments
    )
    try container.encodeIfPresent(
      reactionStructureID,
      forKey: .reactionStructureID
    )
    try container.encode(scienceAssignments, forKey: .scienceAssignments)
    try container.encode(defaultIntermediateME, forKey: .defaultIntermediateME)
    try container.encode(defaultIntermediateTE, forKey: .defaultIntermediateTE)
    try container.encode(ruleVersion, forKey: .ruleVersion)
  }

  public func selection(
    for category: ManufacturingCategory
  ) -> ProductionFacilitySelection? {
    let assigned = manufacturingAssignments[category].flatMap { id in
      structures.first { $0.id == id }
    }
    let selected: ConfiguredIndustryStructure?
    let manual: Bool
    if !automaticStructureSelection, let assigned {
      selected = assigned
      manual = true
    } else {
      selected =
        structures.filter {
          manufacturingSystem(for: $0) != nil
            && $0.supportsActivity(.manufacturing)
        }.sorted {
          let lhsMaterial = $0.materialBonusPercent(for: category)
          let rhsMaterial = $1.materialBonusPercent(for: category)
          if lhsMaterial != rhsMaterial { return lhsMaterial > rhsMaterial }
          let lhsTime = $0.timeBonusPercent(for: category)
          let rhsTime = $1.timeBonusPercent(for: category)
          if lhsTime != rhsTime { return lhsTime > rhsTime }
          return $0.name.localizedCaseInsensitiveCompare($1.name)
            == .orderedAscending
        }.first
      manual = false
    }
    guard let selected else { return nil }
    let material = selected.materialBonusPercent(for: category)
    let time = selected.timeBonusPercent(for: category)
    let system = manufacturingSystem(for: selected)
    return ProductionFacilitySelection(
      category: category,
      structureID: selected.id,
      structureName: selected.displayName,
      solarSystemID: system?.solarSystemID,
      solarSystemName: system?.solarSystemName,
      materialBonusPercent: material,
      timeBonusPercent: time,
      materialMultiplier: selected.materialMultiplier(for: category),
      timeMultiplier: selected.timeMultiplier(for: category),
      isManualAssignment: manual,
      needsReview:
        selected.needsReview || !selected.supportsActivity(.manufacturing),
      explanation:
        manual
        ? "Manual assignment for \(category.displayName)."
        : "Automatically selected by highest material bonus, then time bonus."
    )
  }

  public func structure(id: UUID?) -> ConfiguredIndustryStructure? {
    guard let id else { return nil }
    return structures.first { $0.id == id }
  }

  public mutating func refreshAutomaticReactionAssignment() {
    guard automaticStructureSelection else { return }
    reactionStructureID = automaticReactionStructure?.id
  }

  public mutating func refreshAutomaticFacilityAssignments() {
    guard automaticStructureSelection else { return }
    refreshAutomaticReactionAssignment()
    for activity in IndustryActivitySystem.allCases
    where activity.isScienceActivity {
      if let structure = automaticScienceStructure(for: activity) {
        scienceAssignments[activity] = structure.id
      } else {
        scienceAssignments.removeValue(forKey: activity)
      }
    }
  }

  public var reactionSelection: ReactionFacilitySelection? {
    let selected: ConfiguredIndustryStructure?
    let manual: Bool
    if automaticStructureSelection {
      selected = automaticReactionStructure
      manual = false
    } else {
      selected = structure(id: reactionStructureID)
      manual = true
    }
    guard let selected else { return nil }
    return ReactionFacilitySelection(
      structureID: selected.id,
      structureName: selected.displayName,
      solarSystemID: reactionSystem.solarSystemID,
      solarSystemName: reactionSystem.solarSystemName,
      materialBonusPercent: (1 - selected.reactionMaterialMultiplier) * 100,
      timeBonusPercent: (1 - selected.reactionTimeMultiplier) * 100,
      materialMultiplier: selected.reactionMaterialMultiplier,
      timeMultiplier: selected.reactionTimeMultiplier,
      isManualAssignment: manual,
      needsReview: selected.needsReview || !selected.isReactionCapable,
      explanation:
        manual
        ? "Manual reaction-facility assignment."
        : "Automatically selected in the reaction system by material bonus, time bonus, job-cost multiplier and facility tax."
    )
  }

  private var automaticReactionStructure: ConfiguredIndustryStructure? {
    structures.filter {
      $0.solarSystemID == reactionSystem.solarSystemID
        && $0.isReactionCapable
    }.sorted {
      if $0.reactionMaterialMultiplier != $1.reactionMaterialMultiplier {
        return $0.reactionMaterialMultiplier < $1.reactionMaterialMultiplier
      }
      if $0.reactionTimeMultiplier != $1.reactionTimeMultiplier {
        return $0.reactionTimeMultiplier < $1.reactionTimeMultiplier
      }
      if $0.jobCostMultiplier != $1.jobCostMultiplier {
        return $0.jobCostMultiplier < $1.jobCostMultiplier
      }
      if $0.facilityTaxRate != $1.facilityTaxRate {
        return $0.facilityTaxRate < $1.facilityTaxRate
      }
      return $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
        == .orderedAscending
    }.first
  }

  public func scienceSelection(
    for activity: IndustryActivitySystem
  ) -> ScienceFacilitySelection? {
    guard activity.isScienceActivity,
      let system = systemConfiguration(for: activity),
      system.solarSystemID > 0
    else { return nil }
    let selected: ConfiguredIndustryStructure?
    let manual: Bool
    if automaticStructureSelection {
      selected = automaticScienceStructure(for: activity)
      manual = false
    } else {
      selected = structure(id: scienceAssignments[activity])
      manual = true
    }
    guard let selected else { return nil }
    let timeMultiplier = selected.scienceTimeMultiplier(for: activity)
    let jobCostMultiplier = selected.scienceJobCostMultiplier(for: activity)
    let rigJobCostMultiplier =
      selected.jobCostMultiplier > 0
      ? jobCostMultiplier / selected.jobCostMultiplier
      : 1
    let matchesSystem =
      selected.solarSystemID == system.solarSystemID
    return ScienceFacilitySelection(
      activity: activity,
      structureID: selected.id,
      structureName: selected.displayName,
      solarSystemID: system.solarSystemID,
      solarSystemName: system.solarSystemName,
      jobCostBonusPercent: max(0, (1 - rigJobCostMultiplier) * 100),
      timeBonusPercent: max(0, (1 - timeMultiplier) * 100),
      jobCostMultiplier: jobCostMultiplier,
      timeMultiplier: timeMultiplier,
      isManualAssignment: manual,
      needsReview:
        selected.needsReview
        || !selected.isScienceCapable(for: activity)
        || !matchesSystem,
      explanation:
        manual
        ? "Manual \(activity.displayName.lowercased()) facility assignment."
        : "Automatically selected in the configured system by job-cost multiplier, time multiplier and facility tax."
    )
  }

  private func automaticScienceStructure(
    for activity: IndustryActivitySystem
  ) -> ConfiguredIndustryStructure? {
    guard let system = systemConfiguration(for: activity),
      system.solarSystemID > 0
    else { return nil }
    return structures.filter {
      $0.solarSystemID == system.solarSystemID
        && $0.isScienceCapable(for: activity)
    }.sorted {
      let lhsCost = $0.scienceJobCostMultiplier(for: activity)
      let rhsCost = $1.scienceJobCostMultiplier(for: activity)
      if lhsCost != rhsCost { return lhsCost < rhsCost }
      let lhsTime = $0.scienceTimeMultiplier(for: activity)
      let rhsTime = $1.scienceTimeMultiplier(for: activity)
      if lhsTime != rhsTime { return lhsTime < rhsTime }
      if $0.facilityTaxRate != $1.facilityTaxRate {
        return $0.facilityTaxRate < $1.facilityTaxRate
      }
      return $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
        == .orderedAscending
    }.first
  }

  public var configuredReactionProfile: ReactionProfile? {
    guard let selection = reactionSelection,
      let structure = structure(id: selection.structureID)
    else {
      return nil
    }
    return ReactionProfile(
      name: "\(name) — Reactions",
      solarSystemID: reactionSystem.solarSystemID,
      securityBand: structure.securityBand,
      structureName: structure.displayName,
      facilityTaxRate: structure.facilityTaxRate,
      cloneState: cloneState,
      manualEffectiveMaterialMultiplier:
        structure.reactionMaterialMultiplier,
      manualEffectiveTimeMultiplier: structure.reactionTimeMultiplier,
      manualEffectiveJobCostMultiplier: structure.jobCostMultiplier,
      ruleVersion: ruleVersion
    )
  }
}
