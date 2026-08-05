import Foundation

public enum DashboardIndustryActivity: String, Codable, CaseIterable,
  Identifiable, Sendable
{
  case manufacturing
  case reaction
  case copying
  case invention
  case materialResearch
  case timeResearch

  public var id: Self { self }

  public init?(esiActivityID: Int) {
    switch esiActivityID {
    case 1: self = .manufacturing
    case 3: self = .timeResearch
    case 4: self = .materialResearch
    case 5: self = .copying
    case 8: self = .invention
    // ESI character industry jobs report reactions as activity 9. Activity 11
    // is retained as an accepted legacy/alternate reaction identifier so a
    // previously cached snapshot never regresses to an unknown activity.
    case 9, 11: self = .reaction
    default: return nil
    }
  }

  public var usesSharedScienceSlots: Bool {
    switch self {
    case .copying, .invention, .materialResearch, .timeResearch: true
    case .manufacturing, .reaction: false
    }
  }
}

public enum IndustrySlotCapacityRules {
  public static let massProductionSkillTypeID: Int64 = 3_387
  public static let advancedMassProductionSkillTypeID: Int64 = 24_625
  public static let laboratoryOperationSkillTypeID: Int64 = 3_406
  public static let advancedLaboratoryOperationSkillTypeID: Int64 = 24_624
  public static let massReactionsSkillTypeID: Int64 = 45_748
  public static let advancedMassReactionsSkillTypeID: Int64 = 45_749

  public static func capacity(
    for activity: DashboardIndustryActivity,
    skills: Sourced<[TrainedSkill]>
  ) -> Int? {
    guard let values = skills.value,
      skills.state != .forbidden,
      skills.state != .unavailable
    else { return nil }
    let levels = Dictionary(
      values.map { ($0.skillID, max(0, min(5, $0.activeLevel))) },
      uniquingKeysWith: max
    )
    switch activity {
    case .manufacturing:
      return 1
        + (levels[massProductionSkillTypeID] ?? 0)
        + (levels[advancedMassProductionSkillTypeID] ?? 0)
    case .reaction:
      return (levels[massReactionsSkillTypeID] ?? 0)
        + (levels[advancedMassReactionsSkillTypeID] ?? 0)
    case .copying, .invention, .materialResearch, .timeResearch:
      return 1
        + (levels[laboratoryOperationSkillTypeID] ?? 0)
        + (levels[advancedLaboratoryOperationSkillTypeID] ?? 0)
    }
  }
}

extension ESIIndustryJobDTO {
  public var dashboardActivity: DashboardIndustryActivity? {
    DashboardIndustryActivity(esiActivityID: activityID)
  }

  public func isRunning(at date: Date) -> Bool {
    let normalized = status.lowercased()
    return normalized == "paused" || (normalized == "active" && endDate > date)
  }

  public var isReadyForDelivery: Bool {
    status.caseInsensitiveCompare("ready") == .orderedSame
  }

  /// ESI snapshots are cached. A job whose last snapshot still says active is
  /// nevertheless ready once its authoritative end date has passed. Paused
  /// jobs remain paused because their progress may be suspended with a facility.
  public func isReadyForDelivery(at date: Date) -> Bool {
    isReadyForDelivery
      || (status.caseInsensitiveCompare("active") == .orderedSame
        && endDate <= date)
  }

  public var isDelivered: Bool {
    status.caseInsensitiveCompare("delivered") == .orderedSame
  }

  public var isCancelledOrReverted: Bool {
    ["cancelled", "reverted"].contains(status.lowercased())
  }
}

public enum PlanAction: String, Codable, CaseIterable, Sendable {
  case produce
  case buy
  case useStock
}

public enum MaterialSupplyMode: String, Codable, CaseIterable, Sendable {
  case produce
  case buy
  case warehouse

  public var displayName: String {
    switch self {
    case .produce: "Produce"
    case .buy: "Buy"
    case .warehouse: "Use warehouse"
    }
  }
}

public enum ProcurementLocationKind: String, Codable, Sendable {
  case npcTradeHub
  case playerStructure
  case legacy
}

public struct ProcurementLocation: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let locationID: Int64?
  public let kind: ProcurementLocationKind
  public let solarSystemID: Int64?
  public let regionID: Int64?
  public let ownerCorporationID: Int64?
  public let ownerFactionID: Int64?

  public init(
    id: String,
    name: String,
    locationID: Int64? = nil,
    kind: ProcurementLocationKind,
    solarSystemID: Int64? = nil,
    regionID: Int64? = nil,
    ownerCorporationID: Int64? = nil,
    ownerFactionID: Int64? = nil
  ) {
    self.id = id
    self.name = name
    self.locationID = locationID
    self.kind = kind
    self.solarSystemID = solarSystemID
    self.regionID = regionID
    self.ownerCorporationID = ownerCorporationID
    self.ownerFactionID = ownerFactionID
  }

  /// Compares the stable ESI location identity when it is available. The
  /// fallback keeps legacy, unresolved locations deterministic without
  /// treating two merely similar display names as the same place.
  public func representsSameLocation(as other: ProcurementLocation) -> Bool {
    if let locationID, let otherLocationID = other.locationID {
      return locationID == otherLocationID
    }
    return kind == other.kind && id == other.id
  }

  public static let jita = ProcurementLocation(
    id: "npc:60003760",
    name: "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
    locationID: 60_003_760,
    kind: .npcTradeHub,
    solarSystemID: 30_000_142,
    regionID: 10_000_002,
    ownerCorporationID: 1_000_035,
    ownerFactionID: 500_001
  )
  public static let amarr = ProcurementLocation(
    id: "npc:60008494",
    name: "Amarr VIII (Oris) - Emperor Family Academy",
    locationID: 60_008_494,
    kind: .npcTradeHub,
    solarSystemID: 30_002_187,
    regionID: 10_000_043,
    ownerCorporationID: 1_000_086,
    ownerFactionID: 500_003
  )
  public static let dodixie = ProcurementLocation(
    id: "npc:60011866",
    name: "Dodixie IX - Moon 20 - Federation Navy Assembly Plant",
    locationID: 60_011_866,
    kind: .npcTradeHub,
    solarSystemID: 30_002_659,
    regionID: 10_000_032,
    ownerCorporationID: 1_000_120,
    ownerFactionID: 500_004
  )
  public static let rens = ProcurementLocation(
    id: "npc:60004588",
    name: "Rens VI - Moon 8 - Brutor Tribe Treasury",
    locationID: 60_004_588,
    kind: .npcTradeHub,
    solarSystemID: 30_002_510,
    regionID: 10_000_030,
    ownerCorporationID: 1_000_049,
    ownerFactionID: 500_002
  )
  public static let hek = ProcurementLocation(
    id: "npc:60005686",
    name: "Hek VIII - Moon 12 - Boundless Creation Factory",
    locationID: 60_005_686,
    kind: .npcTradeHub,
    solarSystemID: 30_002_053,
    regionID: 10_000_042,
    ownerCorporationID: 1_000_057,
    ownerFactionID: 500_002
  )

  public static let standardTradeHubs: [ProcurementLocation] = [
    .jita, .amarr, .dodixie, .rens, .hek,
  ]

  public static func legacy(name: String) -> ProcurementLocation {
    ProcurementLocation(
      id: "legacy:\(name.lowercased())",
      name: name,
      kind: .legacy
    )
  }
}

public struct MaterialProcurementPreference: Codable, Equatable, Sendable {
  public var supplyMode: MaterialSupplyMode
  public var purchaseLocation: ProcurementLocation
  /// When enabled, factual allocatable production-warehouse stock is consumed
  /// before the selected build or buy fallback is applied to the shortfall.
  public var usesAvailableStockFirst: Bool

  public init(
    supplyMode: MaterialSupplyMode = .buy,
    purchaseLocation: ProcurementLocation = .jita,
    usesAvailableStockFirst: Bool = false
  ) {
    self.supplyMode = supplyMode
    self.purchaseLocation = purchaseLocation
    self.usesAvailableStockFirst = usesAvailableStockFirst
  }

  private enum CodingKeys: String, CodingKey {
    case supplyMode, purchaseLocation, usesAvailableStockFirst
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    supplyMode = try container.decode(
      MaterialSupplyMode.self,
      forKey: .supplyMode
    )
    purchaseLocation = try container.decode(
      ProcurementLocation.self,
      forKey: .purchaseLocation
    )
    usesAvailableStockFirst =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .usesAvailableStockFirst
      ) ?? false
  }
}

public enum MakeOrBuyRecommendation: String, Codable, Sendable {
  case produce
  case buy
  case unavailable
}

public struct MaterialMakeOrBuyAnalysis: Codable, Sendable {
  public let requiredQuantity: Int64
  public let productionRuns: Int
  public let producedQuantity: Int64
  public let mainHub: ProcurementLocation
  public let purchaseQuote: PriceQuote
  public let purchaseLogisticsCost: Double?
  public let purchaseTotalCost: Double?
  public let buildMaterialCost: Double?
  public let buildInstallationCost: Double?
  public let buildLogisticsCost: Double?
  public let buildTotalCost: Double?
  public let recommendation: MakeOrBuyRecommendation
  public let savings: Double?
  public let warnings: [DomainWarning]

  public init(
    requiredQuantity: Int64,
    productionRuns: Int,
    producedQuantity: Int64,
    mainHub: ProcurementLocation,
    purchaseQuote: PriceQuote,
    purchaseLogisticsCost: Double?,
    purchaseTotalCost: Double?,
    buildMaterialCost: Double?,
    buildInstallationCost: Double?,
    buildLogisticsCost: Double?,
    buildTotalCost: Double?,
    recommendation: MakeOrBuyRecommendation,
    savings: Double?,
    warnings: [DomainWarning]
  ) {
    self.requiredQuantity = requiredQuantity
    self.productionRuns = productionRuns
    self.producedQuantity = producedQuantity
    self.mainHub = mainHub
    self.purchaseQuote = purchaseQuote
    self.purchaseLogisticsCost = purchaseLogisticsCost
    self.purchaseTotalCost = purchaseTotalCost
    self.buildMaterialCost = buildMaterialCost
    self.buildInstallationCost = buildInstallationCost
    self.buildLogisticsCost = buildLogisticsCost
    self.buildTotalCost = buildTotalCost
    self.recommendation = recommendation
    self.savings = savings
    self.warnings = warnings
  }
}

public struct MakeOrBuyRecommendationApplication: Sendable {
  public let preferences: [Int64: MaterialProcurementPreference]
  public let produceCount: Int
  public let buyCount: Int
  public let unavailableCount: Int

  public var appliedCount: Int {
    produceCount + buyCount
  }

  public var hasApplicableRecommendations: Bool {
    appliedCount > 0
  }

  public init(
    materials: [MaterialRequirement],
    existingPreferences: [Int64: MaterialProcurementPreference],
    mainHub: ProcurementLocation
  ) {
    var resolved = existingPreferences
    var produceCount = 0
    var buyCount = 0
    var unavailableCount = 0

    for material in materials {
      if resolved[material.typeID] == nil,
        let procurement = material.procurement
      {
        resolved[material.typeID] = procurement
      }
      guard material.canProduce else { continue }
      guard let analysis = material.makeOrBuyAnalysis else {
        unavailableCount += 1
        continue
      }

      var preference =
        resolved[material.typeID]
        ?? MaterialProcurementPreference(
          supplyMode: .produce,
          purchaseLocation: mainHub
        )
      preference.purchaseLocation = mainHub
      switch analysis.recommendation {
      case .produce:
        preference.supplyMode = .produce
        produceCount += 1
      case .buy:
        preference.supplyMode = .buy
        buyCount += 1
      case .unavailable:
        unavailableCount += 1
        continue
      }
      resolved[material.typeID] = preference
    }

    self.preferences = resolved
    self.produceCount = produceCount
    self.buyCount = buyCount
    self.unavailableCount = unavailableCount
  }
}

public enum ManualBlueprintKind: String, Codable, CaseIterable, Sendable {
  case bpc = "BPC"
  case bpo = "BPO"

  public var costTreatment: String {
    switch self {
    case .bpc:
      "Consumed copy acquisition cost"
    case .bpo:
      "Owner-entered BPO cost allocation"
    }
  }
}

public struct PlanNode: Identifiable, Codable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let name: String
  /// Quantity requested by the parent. This differs from `requiredQuantity`
  /// when a recipe produces more than one unit per run or rounds up runs.
  public let requestedQuantity: Int64?
  public let requiredQuantity: Int64
  public let action: PlanAction
  public let activity: BlueprintActivityDefinition.Kind?
  public let runs: Int?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let blueprintTypeID: Int64?
  public let facilityName: String?
  public let manufacturingCategory: ManufacturingCategory?
  public let children: [UUID]
  public let topLevelRequestID: UUID?

  public init(
    id: UUID,
    typeID: Int64,
    name: String,
    requestedQuantity: Int64? = nil,
    requiredQuantity: Int64,
    action: PlanAction,
    activity: BlueprintActivityDefinition.Kind?,
    runs: Int?,
    materialEfficiency: Int?,
    timeEfficiency: Int?,
    blueprintTypeID: Int64? = nil,
    facilityName: String? = nil,
    manufacturingCategory: ManufacturingCategory? = nil,
    children: [UUID],
    topLevelRequestID: UUID?
  ) {
    self.id = id
    self.typeID = typeID
    self.name = name
    self.requestedQuantity = requestedQuantity
    self.requiredQuantity = requiredQuantity
    self.action = action
    self.activity = activity
    self.runs = runs
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.blueprintTypeID = blueprintTypeID
    self.facilityName = facilityName
    self.manufacturingCategory = manufacturingCategory
    self.children = children
    self.topLevelRequestID = topLevelRequestID
  }
}

public struct MaterialRequirement: Identifiable, Codable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let required: Int64
  public let fromStock: Int64
  public let toBuy: Int64
  public let toProduce: Int64
  public let quote: PriceQuote?
  public let stockQuote: PriceQuote?
  public let replacementQuote: PriceQuote?
  public let procurement: MaterialProcurementPreference?
  public let sourceCategory: String?
  public let sourceGroup: String?
  public let productionActivity: BlueprintActivityDefinition.Kind?
  public let productionAllowed: Bool?
  public let makeOrBuyAnalysis: MaterialMakeOrBuyAnalysis?

  public init(
    typeID: Int64,
    name: String,
    required: Int64,
    fromStock: Int64,
    toBuy: Int64,
    toProduce: Int64,
    quote: PriceQuote?,
    stockQuote: PriceQuote? = nil,
    replacementQuote: PriceQuote? = nil,
    procurement: MaterialProcurementPreference? = nil,
    sourceCategory: String? = nil,
    sourceGroup: String? = nil,
    productionActivity: BlueprintActivityDefinition.Kind? = nil,
    productionAllowed: Bool? = nil,
    makeOrBuyAnalysis: MaterialMakeOrBuyAnalysis? = nil
  ) {
    self.typeID = typeID
    self.name = name
    self.required = required
    self.fromStock = fromStock
    self.toBuy = toBuy
    self.toProduce = toProduce
    self.quote = quote
    self.stockQuote = stockQuote
    self.replacementQuote = replacementQuote
    self.procurement = procurement
    self.sourceCategory = sourceCategory
    self.sourceGroup = sourceGroup
    self.productionActivity = productionActivity
    self.productionAllowed = productionAllowed
    self.makeOrBuyAnalysis = makeOrBuyAnalysis
  }

  public var isProducedMaterial: Bool {
    productionActivity != nil || toProduce > 0
  }

  public var canProduce: Bool {
    productionAllowed ?? (productionActivity != nil)
  }

  public var warehouseConsumptionValue: Double? {
    guard fromStock > 0 else { return 0 }
    guard let unitPrice = replacementQuote?.weightedUnitPrice,
      unitPrice.isFinite,
      unitPrice >= 0
    else {
      return nil
    }
    let value = Double(fromStock) * unitPrice
    return value.isFinite && value >= 0 ? value : nil
  }
}

public struct IndustryJobCost: Identifiable, Codable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let productName: String?
  public let activity: BlueprintActivityDefinition.Kind
  public let runs: Int?
  public let outputQuantity: Int64?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let isTopLevel: Bool?
  public let estimatedItemValue: Double
  public let systemCostIndex: Double
  public let bonusMultiplier: Double
  public let facilityTax: Double
  public let sccSurcharge: Double
  public let alphaSurcharge: Double
  public let total: Double
  public let facilityName: String?
  public let manufacturingCategory: ManufacturingCategory?

  public init(
    id: UUID,
    typeID: Int64,
    productName: String? = nil,
    activity: BlueprintActivityDefinition.Kind,
    runs: Int? = nil,
    outputQuantity: Int64? = nil,
    materialEfficiency: Int? = nil,
    timeEfficiency: Int? = nil,
    isTopLevel: Bool? = nil,
    estimatedItemValue: Double,
    systemCostIndex: Double,
    bonusMultiplier: Double,
    facilityTax: Double,
    sccSurcharge: Double,
    alphaSurcharge: Double,
    total: Double,
    facilityName: String? = nil,
    manufacturingCategory: ManufacturingCategory? = nil
  ) {
    self.id = id
    self.typeID = typeID
    self.productName = productName
    self.activity = activity
    self.runs = runs
    self.outputQuantity = outputQuantity
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.isTopLevel = isTopLevel
    self.estimatedItemValue = estimatedItemValue
    self.systemCostIndex = systemCostIndex
    self.bonusMultiplier = bonusMultiplier
    self.facilityTax = facilityTax
    self.sccSurcharge = sccSurcharge
    self.alphaSurcharge = alphaSurcharge
    self.total = total
    self.facilityName = facilityName
    self.manufacturingCategory = manufacturingCategory
  }
}

public enum LogisticsLegKind: String, Codable, CaseIterable, Sendable {
  case inboundMaterials
  case outboundProducts

  public var displayName: String {
    switch self {
    case .inboundMaterials: "Purchased materials"
    case .outboundProducts: "Finished products"
    }
  }
}

public enum LogisticsChargeBasis: String, Codable, Sendable {
  case volume
  case collateral
}

public struct LogisticsCostLeg: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let kind: LogisticsLegKind
  public let origin: String
  public let destination: String
  public let contractNumber: Int?
  public let contractCount: Int?
  public let cargoVolumeM3: Double
  public let collateral: Double
  public let volumeCharge: Double
  public let collateralCharge: Double
  public let chargedBy: LogisticsChargeBasis
  public let unroundedCharge: Double
  public let roundedCharge: Double

  public init(
    id: UUID = UUID(),
    kind: LogisticsLegKind,
    origin: String,
    destination: String,
    contractNumber: Int = 1,
    contractCount: Int = 1,
    cargoVolumeM3: Double,
    collateral: Double,
    volumeCharge: Double,
    collateralCharge: Double,
    chargedBy: LogisticsChargeBasis,
    unroundedCharge: Double,
    roundedCharge: Double
  ) {
    self.id = id
    self.kind = kind
    self.origin = origin
    self.destination = destination
    self.contractNumber = contractNumber
    self.contractCount = contractCount
    self.cargoVolumeM3 = cargoVolumeM3
    self.collateral = collateral
    self.volumeCharge = volumeCharge
    self.collateralCharge = collateralCharge
    self.chargedBy = chargedBy
    self.unroundedCharge = unroundedCharge
    self.roundedCharge = roundedCharge
  }
}

public struct BlueprintCostEntry: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID { requestID }
  public let requestID: UUID
  public let productName: String
  public let kind: ManualBlueprintKind
  public let amount: Double
  public let treatment: String
}

public struct BlueprintCostBreakdown: Codable, Equatable, Sendable {
  public let entries: [BlueprintCostEntry]
  public let requestsWithoutEnteredCost: [UUID]
  public let total: Double
}

public struct LogisticsCostBreakdown: Codable, Equatable, Sendable {
  public let ruleVersion: String
  public let iskPerCubicMeter: Double
  public let collateralRate: Double
  public let maximumContractVolumeM3: Double
  public let roundingIncrement: Double
  public let legs: [LogisticsCostLeg]
  public let total: Double
}

public struct IndustryCostBreakdown: Codable, Equatable, Sendable {
  public let materialCost: Double?
  public let purchasedMaterialCost: Double?
  public let stockMaterialCost: Double?
  public let blueprintCosts: BlueprintCostBreakdown?
  public let systemIndexCost: Double?
  public let facilityTax: Double?
  public let sccSurcharge: Double?
  public let alphaSurcharge: Double?
  public let installationCost: Double?
  public let logistics: LogisticsCostBreakdown?
  public let logisticsCost: Double?
  public let totalProductionCost: Double?

  public var effectiveLogisticsCost: Double? {
    logisticsCost
      ?? logistics?.total
      ?? (totalProductionCost == nil ? nil : 0)
  }

  public var recomputedTotalProductionCost: Double? {
    Self.total(
      materialCost: materialCost,
      blueprintCost: blueprintCosts?.total,
      installationCost: installationCost,
      logisticsCost: effectiveLogisticsCost
    )
  }

  public var hasConsistentTotal: Bool {
    switch (recomputedTotalProductionCost, totalProductionCost) {
    case (nil, nil):
      return true
    case (.some(let recomputed), .some(let recorded)):
      let tolerance = max(0.01, abs(recorded) * 1e-12)
      return abs(recomputed - recorded) <= tolerance
    default:
      return false
    }
  }

  public static func total(
    materialCost: Double?,
    blueprintCost: Double?,
    installationCost: Double?,
    logisticsCost: Double?
  ) -> Double? {
    guard let materialCost,
      let blueprintCost,
      let installationCost,
      let logisticsCost
    else { return nil }
    let values = [
      materialCost,
      blueprintCost,
      installationCost,
      logisticsCost,
    ]
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      return nil
    }
    let total = values.reduce(0, +)
    return total.isFinite && total >= 0 ? total : nil
  }
}

public struct SaleScenarioResult: Codable, Sendable {
  public let scenario: PriceScenario
  public let marketLocation: ProcurementLocation?
  public let grossRevenue: Double?
  public let salesTax: Double?
  public let brokerFee: Double?
  public let outboundLogistics: LogisticsCostBreakdown?
  public let outboundLogisticsCost: Double?
  public let totalCost: Double?
  public let grossOrNetRevenue: Double?
  public let profit: Double?
  public let margin: Double?
  public let roi: Double?
  public let quotes: [PriceQuote]

  public init(
    scenario: PriceScenario,
    marketLocation: ProcurementLocation? = nil,
    grossRevenue: Double? = nil,
    salesTax: Double? = nil,
    brokerFee: Double? = nil,
    outboundLogistics: LogisticsCostBreakdown? = nil,
    outboundLogisticsCost: Double? = nil,
    totalCost: Double? = nil,
    grossOrNetRevenue: Double?,
    profit: Double?,
    margin: Double?,
    roi: Double?,
    quotes: [PriceQuote]
  ) {
    self.scenario = scenario
    self.marketLocation = marketLocation
    self.grossRevenue = grossRevenue
    self.salesTax = salesTax
    self.brokerFee = brokerFee
    self.outboundLogistics = outboundLogistics
    self.outboundLogisticsCost = outboundLogisticsCost
    self.totalCost = totalCost
    self.grossOrNetRevenue = grossOrNetRevenue
    self.profit = profit
    self.margin = margin
    self.roi = roi
    self.quotes = quotes
  }
}

public struct ExplanationEdge: Identifiable, Codable, Sendable {
  public let id: UUID
  public let fromNodeID: UUID?
  public let toNodeID: UUID?
  public let rule: String
  public let explanation: String
  public let source: SourceIdentity?
}

public struct PlanProvenance: Codable, Sendable {
  public let sdeBuild: Int
  public let esiCompatibilityDate: String
  public let snapshotIDs: [UUID]
  public let priceTimestamp: Date
  public let ruleVersion: String
}

public struct IndustryPlanSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let createdAt: Date
  public let requests: [ProductionRequestLine]
  public let nodes: [PlanNode]
  public let materials: [MaterialRequirement]
  public let stockAllocations: [StockAllocation]
  public let jobs: [IndustryJobCost]
  public let materialCost: Double?
  public let installationCost: Double?
  public let costBreakdown: IndustryCostBreakdown?
  public let immediateSale: SaleScenarioResult
  public let listedSale: SaleScenarioResult
  public let homeImmediateSale: SaleScenarioResult?
  public let homeListedSale: SaleScenarioResult?
  public let totalJobSeconds: Int64
  public let makespanSeconds: Int64
  public let warnings: [DomainWarning]
  public let explanations: [ExplanationEdge]
  public let provenance: PlanProvenance

  public var warehouseConsumptionValue: Double? {
    var total = 0.0
    for material in materials where material.fromStock > 0 {
      guard let value = material.warehouseConsumptionValue else {
        return nil
      }
      let updated = total + value
      guard updated.isFinite, updated >= 0 else { return nil }
      total = updated
    }
    return total
  }

  public var plannedOutputUnits: Int64? {
    var total: Int64 = 0
    for request in requests {
      guard
        let node = nodes.last(where: {
          $0.topLevelRequestID == request.id && $0.action == .produce
        }),
        node.requiredQuantity > 0
      else { return nil }
      let addition = total.addingReportingOverflow(node.requiredQuantity)
      guard !addition.overflow else { return nil }
      total = addition.partialValue
    }
    return total > 0 ? total : nil
  }

  public var productionCostPerOutputUnit: Double? {
    guard let totalCost = costBreakdown?.totalProductionCost,
      totalCost.isFinite,
      totalCost >= 0,
      let plannedOutputUnits
    else { return nil }
    let value = totalCost / Double(plannedOutputUnits)
    return value.isFinite && value >= 0 ? value : nil
  }
}

public protocol IndustryCatalogQuerying: Sendable {
  func typeID(named name: String) async throws -> Int64?
  func typeName(id: Int64) async throws -> String?
  func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  func manufacturingDefinitions() async throws -> [BlueprintDefinition]
  func reactionDefinitions() async throws -> [BlueprintDefinition]
  func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  func packagedVolume(typeID: Int64) async throws -> Double?
}

extension IndustryCatalogQuerying {
  public func manufacturingDefinitions() async throws -> [BlueprintDefinition] {
    []
  }

  public func reactionDefinitions() async throws -> [BlueprintDefinition] {
    []
  }

  public func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    nil
  }

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    nil
  }
}
