import Foundation

public enum PlanAction: String, Codable, CaseIterable, Sendable {
  case produce
  case buy
  case useStock
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
  public let requiredQuantity: Int64
  public let action: PlanAction
  public let activity: BlueprintActivityDefinition.Kind?
  public let runs: Int?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let facilityName: String?
  public let manufacturingCategory: ManufacturingCategory?
  public let children: [UUID]
  public let topLevelRequestID: UUID?

  public init(
    id: UUID,
    typeID: Int64,
    name: String,
    requiredQuantity: Int64,
    action: PlanAction,
    activity: BlueprintActivityDefinition.Kind?,
    runs: Int?,
    materialEfficiency: Int?,
    timeEfficiency: Int?,
    facilityName: String? = nil,
    manufacturingCategory: ManufacturingCategory? = nil,
    children: [UUID],
    topLevelRequestID: UUID?
  ) {
    self.id = id
    self.typeID = typeID
    self.name = name
    self.requiredQuantity = requiredQuantity
    self.action = action
    self.activity = activity
    self.runs = runs
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
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
  public let sourceCategory: String?
  public let sourceGroup: String?
  public let productionActivity: BlueprintActivityDefinition.Kind?

  public init(
    typeID: Int64,
    name: String,
    required: Int64,
    fromStock: Int64,
    toBuy: Int64,
    toProduce: Int64,
    quote: PriceQuote?,
    stockQuote: PriceQuote? = nil,
    sourceCategory: String? = nil,
    sourceGroup: String? = nil,
    productionActivity: BlueprintActivityDefinition.Kind? = nil
  ) {
    self.typeID = typeID
    self.name = name
    self.required = required
    self.fromStock = fromStock
    self.toBuy = toBuy
    self.toProduce = toProduce
    self.quote = quote
    self.stockQuote = stockQuote
    self.sourceCategory = sourceCategory
    self.sourceGroup = sourceGroup
    self.productionActivity = productionActivity
  }

  public var isProducedMaterial: Bool {
    productionActivity != nil || toProduce > 0
  }
}

public struct IndustryJobCost: Identifiable, Codable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let activity: BlueprintActivityDefinition.Kind
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
    activity: BlueprintActivityDefinition.Kind,
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
    self.activity = activity
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
  public let totalProductionCost: Double?
}

public struct SaleScenarioResult: Codable, Sendable {
  public let scenario: PriceScenario
  public let grossRevenue: Double?
  public let salesTax: Double?
  public let brokerFee: Double?
  public let grossOrNetRevenue: Double?
  public let profit: Double?
  public let margin: Double?
  public let roi: Double?
  public let quotes: [PriceQuote]

  public init(
    scenario: PriceScenario,
    grossRevenue: Double? = nil,
    salesTax: Double? = nil,
    brokerFee: Double? = nil,
    grossOrNetRevenue: Double?,
    profit: Double?,
    margin: Double?,
    roi: Double?,
    quotes: [PriceQuote]
  ) {
    self.scenario = scenario
    self.grossRevenue = grossRevenue
    self.salesTax = salesTax
    self.brokerFee = brokerFee
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
  public let totalJobSeconds: Int64
  public let makespanSeconds: Int64
  public let warnings: [DomainWarning]
  public let explanations: [ExplanationEdge]
  public let provenance: PlanProvenance
}

public protocol IndustryCatalogQuerying: Sendable {
  func typeID(named name: String) async throws -> Int64?
  func typeName(id: Int64) async throws -> String?
  func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  func packagedVolume(typeID: Int64) async throws -> Double?
}

extension IndustryCatalogQuerying {
  public func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    nil
  }

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    nil
  }
}
