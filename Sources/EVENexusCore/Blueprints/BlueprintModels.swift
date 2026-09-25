import Foundation

public enum BlueprintCopyKind: String, Codable, Hashable, Sendable {
  case original
  case copy
  case unknown
}

public struct BlueprintMaterial: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let quantity: Int64
}

public struct BlueprintProduct: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let quantity: Int64
  public let probability: Double?
}

public struct BlueprintActivityDefinition: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case copying
    case manufacturing
    case reaction
    case invention
    case materialResearch
    case timeResearch
  }

  public let kind: Kind
  public let durationSeconds: Int64
  public let materials: [BlueprintMaterial]
  public let products: [BlueprintProduct]
}

public struct BlueprintDefinition: Identifiable, Codable, Hashable, Sendable {
  public var id: Int64 { blueprintTypeID }
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let maxProductionLimit: Int64?
  public let activity: BlueprintActivityDefinition
  public let source: SourceIdentity
}

public struct OwnedBlueprintInstance: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let blueprintTypeID: Int64
  public let locationID: Int64
  public let quantity: Int64
  public let runs: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let kind: BlueprintCopyKind
  public let source: SourceIdentity

  public init(
    id: Int64,
    blueprintTypeID: Int64,
    locationID: Int64,
    quantity: Int64,
    runs: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    source: SourceIdentity
  ) {
    self.id = id
    self.blueprintTypeID = blueprintTypeID
    self.locationID = locationID
    self.quantity = quantity
    self.runs = runs
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    if quantity == -1 {
      self.kind = .original
    } else if quantity == -2 {
      self.kind = .copy
    } else {
      self.kind = .unknown
    }
    self.source = source
  }
}

public struct BlueprintActivityCandidate: Identifiable, Codable, Sendable {
  public let id: UUID
  public let definition: BlueprintDefinition
  public let ownedInstance: OwnedBlueprintInstance?
  public let runs: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let warnings: [DomainWarning]
}

public enum BlueprintPlanningProvenance: String, Codable, Hashable, Sendable {
  case researchedOriginal
  case copiedFromOriginal
  case inventedCopy
  case legacyT2Original
  case contractCopy
  case marketOriginal
  case loyaltyStoreCopy
  case manualPlanningAssumption
  case unknown
}

public struct BlueprintDemandID: Identifiable, Codable, Hashable, Sendable {
  public let requestID: UUID
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let nodePath: [Int64]

  public var id: String {
    ([requestID.uuidString, String(blueprintTypeID), String(productTypeID)]
      + nodePath.map(String.init)).joined(separator: ":")
  }

  public init(
    requestID: UUID,
    blueprintTypeID: Int64,
    productTypeID: Int64,
    nodePath: [Int64]
  ) {
    self.requestID = requestID
    self.blueprintTypeID = blueprintTypeID
    self.productTypeID = productTypeID
    self.nodePath = nodePath
  }
}

public enum BlueprintSourceReference: Codable, Hashable, Sendable {
  case ownedBPO(itemID: Int64)
  case ownedBPC(itemID: Int64)
  case contractBPC(recordID: Int64)
  case contractBPO(recordID: Int64)
  case marketBPO(orderID: Int64)
  case loyaltyStoreBPC(typeID: Int64)
  case plannedCopy(jobID: UUID)
  case plannedInvention(jobID: UUID)
  case manualExternalBPC(id: UUID)

  public var stableID: String {
    switch self {
    case .ownedBPO(let itemID): "owned-bpo:\(itemID)"
    case .ownedBPC(let itemID): "owned-bpc:\(itemID)"
    case .contractBPC(let recordID): "contract-bpc:\(recordID)"
    case .contractBPO(let recordID): "contract-bpo:\(recordID)"
    case .marketBPO(let orderID): "market-bpo:\(orderID)"
    case .loyaltyStoreBPC(let typeID): "loyalty-bpc:\(typeID)"
    case .plannedCopy(let jobID): "planned-copy:\(jobID.uuidString)"
    case .plannedInvention(let jobID):
      "planned-invention:\(jobID.uuidString)"
    case .manualExternalBPC(let id): "manual-bpc:\(id.uuidString)"
    }
  }

  public var isOriginal: Bool {
    switch self {
    case .ownedBPO, .contractBPO, .marketBPO: true
    default: false
    }
  }
}

public struct BlueprintRunReservation: Identifiable, Codable, Hashable,
  Sendable
{
  public var id: String { "\(planID.uuidString):\(blueprintItemID)" }
  public let planID: UUID
  public let blueprintItemID: Int64
  public let runs: Int

  public init(planID: UUID, blueprintItemID: Int64, runs: Int) {
    self.planID = planID
    self.blueprintItemID = blueprintItemID
    self.runs = max(0, runs)
  }
}

public struct BlueprintRunAllocation: Identifiable, Codable, Hashable,
  Sendable
{
  public var id: String { source.stableID }
  public let source: BlueprintSourceReference
  public let provenance: BlueprintPlanningProvenance
  public let availableRuns: Int?
  public let allocatedRuns: Int
  public let remainingRuns: Int?
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let ownerID: Int64?
  public let ownerName: String?
  public let locationID: Int64?
  public let locationName: String?
  public let sourceState: DataFreshness
  public let acquisitionCost: Double?
  public let sourceSnapshotID: UUID?

  public init(
    source: BlueprintSourceReference,
    provenance: BlueprintPlanningProvenance,
    availableRuns: Int?,
    allocatedRuns: Int,
    remainingRuns: Int?,
    materialEfficiency: Int,
    timeEfficiency: Int,
    ownerID: Int64? = nil,
    ownerName: String? = nil,
    locationID: Int64? = nil,
    locationName: String? = nil,
    sourceState: DataFreshness,
    acquisitionCost: Double? = nil,
    sourceSnapshotID: UUID? = nil
  ) {
    self.source = source
    self.provenance = provenance
    self.availableRuns = availableRuns
    self.allocatedRuns = max(0, allocatedRuns)
    self.remainingRuns = remainingRuns.map { max(0, $0) }
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.ownerID = ownerID
    self.ownerName = ownerName
    self.locationID = locationID
    self.locationName = locationName
    self.sourceState = sourceState
    self.acquisitionCost = acquisitionCost
    self.sourceSnapshotID = sourceSnapshotID
  }
}

public struct BlueprintManufacturingJob: Identifiable, Codable, Hashable,
  Sendable
{
  public let id: UUID
  public let demandID: BlueprintDemandID
  public let allocation: BlueprintRunAllocation
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let runs: Int
  public let outputQuantity: Int64
  public let materials: [BlueprintMaterial]
  public let durationSeconds: Int64?
  public let installationCost: Double?

  public init(
    id: UUID = UUID(),
    demandID: BlueprintDemandID,
    allocation: BlueprintRunAllocation,
    blueprintTypeID: Int64,
    productTypeID: Int64,
    runs: Int,
    outputQuantity: Int64,
    materials: [BlueprintMaterial] = [],
    durationSeconds: Int64? = nil,
    installationCost: Double? = nil
  ) {
    self.id = id
    self.demandID = demandID
    self.allocation = allocation
    self.blueprintTypeID = blueprintTypeID
    self.productTypeID = productTypeID
    self.runs = max(0, runs)
    self.outputQuantity = max(0, outputQuantity)
    self.materials = materials
    self.durationSeconds = durationSeconds
    self.installationCost = installationCost
  }
}

public struct BlueprintTransferRequirement: Identifiable, Codable, Hashable,
  Sendable
{
  public let id: UUID
  public let source: BlueprintSourceReference
  public let originLocationID: Int64?
  public let originName: String?
  public let destinationLocationID: Int64?
  public let destinationName: String?
  public let isResolved: Bool

  public init(
    id: UUID = UUID(),
    source: BlueprintSourceReference,
    originLocationID: Int64?,
    originName: String?,
    destinationLocationID: Int64?,
    destinationName: String?
  ) {
    self.id = id
    self.source = source
    self.originLocationID = originLocationID
    self.originName = originName
    self.destinationLocationID = destinationLocationID
    self.destinationName = destinationName
    self.isResolved = originLocationID != nil && destinationLocationID != nil
  }
}

public struct BlueprintSkillRequirement: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let level: Int

  public init(typeID: Int64, level: Int) {
    self.typeID = typeID
    self.level = min(5, max(0, level))
  }
}

public struct BlueprintScienceActivityDefinition: Codable, Hashable, Sendable {
  public let kind: BlueprintActivityDefinition.Kind
  public let durationSeconds: Int64
  public let materials: [BlueprintMaterial]
  public let products: [BlueprintProduct]
  public let requiredSkills: [BlueprintSkillRequirement]
  public let source: SourceIdentity

  public init(
    kind: BlueprintActivityDefinition.Kind,
    durationSeconds: Int64,
    materials: [BlueprintMaterial],
    products: [BlueprintProduct],
    requiredSkills: [BlueprintSkillRequirement],
    source: SourceIdentity
  ) {
    self.kind = kind
    self.durationSeconds = max(0, durationSeconds)
    self.materials = materials
    self.products = products
    self.requiredSkills = requiredSkills
    self.source = source
  }
}

public struct BlueprintCopyPlan: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let sourceBPO: BlueprintSourceReference
  public let blueprintTypeID: Int64
  public let copyCount: Int
  public let runsPerCopy: Int
  public let maximumRunsPerCopy: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let materials: [BlueprintMaterial]
  public let durationSeconds: Int64?
  public let installationCost: Double?

  public var totalLicensedRuns: Int {
    let result = copyCount.multipliedReportingOverflow(by: runsPerCopy)
    return result.overflow ? Int.max : result.partialValue
  }

  public init(
    id: UUID = UUID(),
    sourceBPO: BlueprintSourceReference,
    blueprintTypeID: Int64,
    copyCount: Int,
    runsPerCopy: Int,
    maximumRunsPerCopy: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    materials: [BlueprintMaterial],
    durationSeconds: Int64?,
    installationCost: Double?
  ) {
    self.id = id
    self.sourceBPO = sourceBPO
    self.blueprintTypeID = blueprintTypeID
    self.copyCount = max(1, copyCount)
    self.maximumRunsPerCopy = max(1, maximumRunsPerCopy)
    self.runsPerCopy = min(
      self.maximumRunsPerCopy,
      max(1, runsPerCopy)
    )
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.materials = materials
    self.durationSeconds = durationSeconds
    self.installationCost = installationCost
  }
}

public struct BlueprintResearchPlan: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public let sourceBPO: BlueprintSourceReference
  public let blueprintTypeID: Int64
  public let activity: BlueprintResearchActivity
  public let currentLevel: Int
  public let targetLevel: Int
  public let materials: [BlueprintMaterial]
  public let durationSeconds: Int64?
  public let installationCost: Double?

  public init(
    id: UUID = UUID(),
    sourceBPO: BlueprintSourceReference,
    blueprintTypeID: Int64,
    activity: BlueprintResearchActivity,
    currentLevel: Int,
    targetLevel: Int,
    materials: [BlueprintMaterial],
    durationSeconds: Int64?,
    installationCost: Double?
  ) {
    self.id = id
    self.sourceBPO = sourceBPO
    self.blueprintTypeID = blueprintTypeID
    self.activity = activity
    self.currentLevel = min(10, max(0, currentLevel))
    self.targetLevel = min(10, max(self.currentLevel, targetLevel))
    self.materials = materials
    self.durationSeconds = durationSeconds
    self.installationCost = installationCost
  }
}

public struct BlueprintInventionForecast: Codable, Hashable, Sendable {
  public let requiredSuccesses: Int
  public let successProbability: Double
  public let expectedAttempts: Double
  public let confidence: Double
  public let attemptsForConfidence: Int
  public let expectedCost: Double?
  public let confidencePlanCost: Double?
}

public struct BlueprintInventionPlan: Identifiable, Codable, Hashable,
  Sendable
{
  public let id: UUID
  public let inputBPC: BlueprintSourceReference
  public let inputBlueprintTypeID: Int64
  public let outputBlueprintTypeID: Int64
  public let characterID: Int64
  public let characterName: String
  public let requiredSkills: [BlueprintSkillRequirement]
  public let datacores: [BlueprintMaterial]
  public let decryptorTypeID: Int64?
  public let successProbability: Double
  public let outputRuns: Int
  public let outputMaterialEfficiency: Int
  public let outputTimeEfficiency: Int
  public let attemptCost: Double?
  public let forecast: BlueprintInventionForecast
  public let durationSeconds: Int64?

  /// Every attempt consumes exactly one input-copy run, regardless of result.
  public var expectedInputBPCRuns: Double { forecast.expectedAttempts }
  public var confidenceInputBPCRuns: Int { forecast.attemptsForConfidence }

  public init(
    id: UUID = UUID(),
    inputBPC: BlueprintSourceReference,
    inputBlueprintTypeID: Int64,
    outputBlueprintTypeID: Int64,
    characterID: Int64,
    characterName: String,
    requiredSkills: [BlueprintSkillRequirement],
    datacores: [BlueprintMaterial],
    decryptorTypeID: Int64?,
    successProbability: Double,
    outputRuns: Int,
    outputMaterialEfficiency: Int,
    outputTimeEfficiency: Int,
    attemptCost: Double?,
    requiredSuccesses: Int,
    confidence: Double = 0.95,
    durationSeconds: Int64? = nil
  ) {
    self.id = id
    self.durationSeconds = durationSeconds
    self.inputBPC = inputBPC
    self.inputBlueprintTypeID = inputBlueprintTypeID
    self.outputBlueprintTypeID = outputBlueprintTypeID
    self.characterID = characterID
    self.characterName = characterName
    self.requiredSkills = requiredSkills
    self.datacores = datacores
    self.decryptorTypeID = decryptorTypeID
    self.successProbability = successProbability
    self.outputRuns = max(1, outputRuns)
    self.outputMaterialEfficiency = outputMaterialEfficiency
    self.outputTimeEfficiency = outputTimeEfficiency
    self.attemptCost = attemptCost
    self.forecast = BlueprintInventionRisk.forecast(
      requiredSuccesses: requiredSuccesses,
      successProbability: successProbability,
      attemptCost: attemptCost,
      confidence: confidence
    )
  }
}

public struct BlueprintDecryptorDefinition: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let probabilityMultiplier: Double
  public let runModifier: Int
  public let materialEfficiencyModifier: Int
  public let timeEfficiencyModifier: Int
  public let source: SourceIdentity

  public init(
    typeID: Int64,
    probabilityMultiplier: Double,
    runModifier: Int,
    materialEfficiencyModifier: Int,
    timeEfficiencyModifier: Int,
    source: SourceIdentity
  ) {
    self.typeID = typeID
    self.probabilityMultiplier = probabilityMultiplier
    self.runModifier = runModifier
    self.materialEfficiencyModifier = materialEfficiencyModifier
    self.timeEfficiencyModifier = timeEfficiencyModifier
    self.source = source
  }
}

public enum BlueprintSciencePlanningError: Error, Equatable, Sendable {
  case originalRequired
  case copyRequired
  case wrongActivity
  case outputUnavailable(Int64)
  case invalidSkillRequirements
  case missingSkill(Int64)
  case invalidProbability
  case reverseEngineeringUnsupported
}

public enum BlueprintInventionTechnology: String, Codable, Hashable, Sendable {
  case techII
  case techIIIReverseEngineering
}

public enum BlueprintSciencePlanner {
  public static func copyPlan(
    sourceBPO: BlueprintSourceReference,
    blueprintTypeID: Int64,
    activity: BlueprintScienceActivityDefinition,
    copyCount: Int,
    runsPerCopy: Int,
    maximumRunsPerCopy: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    durationMultiplier: Double = 1,
    installationCost: Double? = nil
  ) throws -> BlueprintCopyPlan {
    guard isOriginal(sourceBPO) else {
      throw BlueprintSciencePlanningError.originalRequired
    }
    guard activity.kind == .copying else {
      throw BlueprintSciencePlanningError.wrongActivity
    }
    let acceptedCopies = max(1, copyCount)
    let acceptedMaximum = max(1, maximumRunsPerCopy)
    let acceptedRuns = min(acceptedMaximum, max(1, runsPerCopy))
    let licensedRuns = saturatedMultiply(acceptedCopies, acceptedRuns)
    let duration = scaledDuration(
      activity.durationSeconds,
      units: licensedRuns,
      multiplier: durationMultiplier
    )
    return BlueprintCopyPlan(
      sourceBPO: sourceBPO,
      blueprintTypeID: blueprintTypeID,
      copyCount: acceptedCopies,
      runsPerCopy: acceptedRuns,
      maximumRunsPerCopy: acceptedMaximum,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency,
      materials: scaledMaterials(activity.materials, by: acceptedCopies),
      durationSeconds: duration,
      installationCost: validCost(installationCost)
    )
  }

  public static func researchPlan(
    sourceBPO: BlueprintSourceReference,
    blueprintTypeID: Int64,
    activity: BlueprintScienceActivityDefinition,
    currentLevel: Int,
    targetLevel: Int,
    durationMultiplier: Double = 1,
    installationCost: Double? = nil
  ) throws -> BlueprintResearchPlan {
    guard isOriginal(sourceBPO) else {
      throw BlueprintSciencePlanningError.originalRequired
    }
    let researchActivity: BlueprintResearchActivity
    switch activity.kind {
    case .materialResearch:
      researchActivity = .materialEfficiency
    case .timeResearch:
      researchActivity = .timeEfficiency
    default:
      throw BlueprintSciencePlanningError.wrongActivity
    }
    let acceptedCurrent = min(10, max(0, currentLevel))
    let acceptedTarget = min(10, max(acceptedCurrent, targetLevel))
    let steps = max(0, acceptedTarget - acceptedCurrent)
    return BlueprintResearchPlan(
      sourceBPO: sourceBPO,
      blueprintTypeID: blueprintTypeID,
      activity: researchActivity,
      currentLevel: acceptedCurrent,
      targetLevel: acceptedTarget,
      materials: scaledMaterials(activity.materials, by: steps),
      durationSeconds: scaledDuration(
        activity.durationSeconds,
        units: steps,
        multiplier: durationMultiplier
      ),
      installationCost: validCost(installationCost)
    )
  }

  public static func inventionPlan(
    inputBPC: BlueprintSourceReference,
    inputBlueprintTypeID: Int64,
    selectedOutputBlueprintTypeID: Int64,
    activity: BlueprintScienceActivityDefinition,
    characterID: Int64,
    characterName: String,
    trainedSkillLevels: [Int64: Int],
    technology: BlueprintInventionTechnology = .techII,
    decryptor: BlueprintDecryptorDefinition? = nil,
    attemptCost: Double?,
    requiredSuccesses: Int,
    confidence: Double = 0.95,
    durationMultiplier: Double = 1
  ) throws -> BlueprintInventionPlan {
    guard technology == .techII else {
      throw BlueprintSciencePlanningError.reverseEngineeringUnsupported
    }
    guard isCopy(inputBPC) else {
      throw BlueprintSciencePlanningError.copyRequired
    }
    guard activity.kind == .invention else {
      throw BlueprintSciencePlanningError.wrongActivity
    }
    guard activity.requiredSkills.count == 3 else {
      throw BlueprintSciencePlanningError.invalidSkillRequirements
    }
    let levels = try activity.requiredSkills.map { requirement -> Int in
      guard let level = trainedSkillLevels[requirement.typeID] else {
        throw BlueprintSciencePlanningError.missingSkill(requirement.typeID)
      }
      return min(5, max(0, level))
    }
    guard
      let product = activity.products.first(where: {
        $0.typeID == selectedOutputBlueprintTypeID
      })
    else {
      throw BlueprintSciencePlanningError.outputUnavailable(
        selectedOutputBlueprintTypeID
      )
    }
    guard let baseProbability = product.probability,
      baseProbability > 0,
      baseProbability <= 1
    else {
      throw BlueprintSciencePlanningError.invalidProbability
    }
    let skillMultiplier =
      1
      + Double(levels[0]) / 40
      + Double(levels[1] + levels[2]) / 30
    let probability = min(
      1,
      baseProbability * skillMultiplier
        * (decryptor?.probabilityMultiplier ?? 1)
    )
    return BlueprintInventionPlan(
      inputBPC: inputBPC,
      inputBlueprintTypeID: inputBlueprintTypeID,
      outputBlueprintTypeID: selectedOutputBlueprintTypeID,
      characterID: characterID,
      characterName: characterName,
      requiredSkills: activity.requiredSkills,
      datacores: activity.materials,
      decryptorTypeID: decryptor?.typeID,
      successProbability: probability,
      outputRuns: max(
        1,
        Int(clamping: product.quantity) + (decryptor?.runModifier ?? 0)
      ),
      outputMaterialEfficiency: 2
        + (decryptor?.materialEfficiencyModifier ?? 0),
      outputTimeEfficiency: 4
        + (decryptor?.timeEfficiencyModifier ?? 0),
      attemptCost: validCost(attemptCost),
      requiredSuccesses: requiredSuccesses,
      confidence: confidence,
      durationSeconds: scaledDuration(activity.durationSeconds,
        units: BlueprintInventionRisk.forecast(requiredSuccesses: requiredSuccesses, successProbability: probability,
          attemptCost: attemptCost, confidence: confidence).attemptsForConfidence,
        multiplier: durationMultiplier)
    )
  }

  private static func isOriginal(_ source: BlueprintSourceReference) -> Bool {
    switch source {
    case .ownedBPO, .contractBPO, .marketBPO: true
    default: false
    }
  }

  private static func isCopy(_ source: BlueprintSourceReference) -> Bool {
    switch source {
    case .ownedBPC, .contractBPC, .loyaltyStoreBPC, .plannedCopy,
      .manualExternalBPC:
      true
    default:
      false
    }
  }

  private static func scaledMaterials(
    _ materials: [BlueprintMaterial],
    by multiplier: Int
  ) -> [BlueprintMaterial] {
    materials.map {
      BlueprintMaterial(
        typeID: $0.typeID,
        quantity: saturatedMultiply($0.quantity, Int64(max(0, multiplier)))
      )
    }
  }

  private static func scaledDuration(
    _ seconds: Int64,
    units: Int,
    multiplier: Double
  ) -> Int64? {
    guard multiplier.isFinite, multiplier >= 0 else { return nil }
    let value = Double(max(0, seconds)) * Double(max(0, units)) * multiplier
    guard value.isFinite, value <= Double(Int64.max) else { return nil }
    return Int64(ceil(value))
  }

  private static func saturatedMultiply(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? Int.max : max(0, result.partialValue)
  }

  private static func saturatedMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? Int64.max : max(0, result.partialValue)
  }

  private static func validCost(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }
}

public enum BlueprintScienceJob: Codable, Hashable, Sendable {
  case copying(BlueprintCopyPlan)
  case research(BlueprintResearchPlan)
  case invention(BlueprintInventionPlan)
}

public struct BlueprintSupplyPlan: Identifiable, Codable, Sendable {
  public static let ruleVersion = "2026.08-blueprint-supply-v2"

  public let id: UUID
  /// Shared identity of the planner calculation that owns reservations and
  /// handoffs. It is optional only for decoding early v2 development data.
  public var planID: UUID? = nil
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let productName: String
  public let requiredRuns: Int
  public let manufacturingJobs: [BlueprintManufacturingJob]
  public let scienceJobs: [BlueprintScienceJob]
  public let transfers: [BlueprintTransferRequirement]
  public let reservations: [BlueprintRunReservation]
  public let capitalPurchaseCost: Double?
  public let batchAllocationCost: Double?
  public let expectedInventionCost: Double?
  public let confidencePlanCost: Double?
  public let warnings: [DomainWarning]
  public let sourceSnapshotIDs: [UUID]
  public let ruleVersion: String

  public init(
    id: UUID = UUID(),
    planID: UUID? = nil,
    blueprintTypeID: Int64,
    productTypeID: Int64,
    productName: String,
    requiredRuns: Int,
    manufacturingJobs: [BlueprintManufacturingJob],
    scienceJobs: [BlueprintScienceJob] = [],
    transfers: [BlueprintTransferRequirement] = [],
    reservations: [BlueprintRunReservation] = [],
    capitalPurchaseCost: Double? = nil,
    batchAllocationCost: Double? = nil,
    expectedInventionCost: Double? = nil,
    confidencePlanCost: Double? = nil,
    warnings: [DomainWarning] = [],
    sourceSnapshotIDs: [UUID] = [],
    ruleVersion: String = BlueprintSupplyPlan.ruleVersion
  ) {
    self.id = id
    self.planID = planID
    self.blueprintTypeID = blueprintTypeID
    self.productTypeID = productTypeID
    self.productName = productName
    self.requiredRuns = max(0, requiredRuns)
    self.manufacturingJobs = manufacturingJobs
    self.scienceJobs = scienceJobs
    self.transfers = transfers
    self.reservations = reservations
    self.capitalPurchaseCost = capitalPurchaseCost
    self.batchAllocationCost = batchAllocationCost
    self.expectedInventionCost = expectedInventionCost
    self.confidencePlanCost = confidencePlanCost
    self.warnings = warnings
    self.sourceSnapshotIDs = sourceSnapshotIDs
    self.ruleVersion = ruleVersion
  }
}

public enum BlueprintInventionRisk {
  public static func forecast(
    requiredSuccesses: Int,
    successProbability: Double,
    attemptCost: Double?,
    confidence: Double = 0.95
  ) -> BlueprintInventionForecast {
    let successes = max(0, requiredSuccesses)
    let probability = min(1, max(0, successProbability))
    let acceptedConfidence = min(1, max(0, confidence))
    let expectedAttempts =
      successes == 0
      ? 0
      : probability > 0
        ? Double(successes) / probability : .infinity
    let attempts =
      minimumAttempts(
        requiredSuccesses: successes,
        successProbability: probability,
        confidence: acceptedConfidence
      ) ?? Int.max
    let expectedCost = attemptCost.flatMap {
      let value = $0 * expectedAttempts
      return value.isFinite && value >= 0 ? value : nil
    }
    let confidenceCost: Double? = attemptCost.flatMap {
      guard attempts != Int.max else { return nil }
      let value = $0 * Double(attempts)
      return value.isFinite && value >= 0 ? value : nil
    }
    return BlueprintInventionForecast(
      requiredSuccesses: successes,
      successProbability: probability,
      expectedAttempts: expectedAttempts,
      confidence: acceptedConfidence,
      attemptsForConfidence: attempts,
      expectedCost: expectedCost,
      confidencePlanCost: confidenceCost
    )
  }

  public static func minimumAttempts(
    requiredSuccesses: Int,
    successProbability: Double,
    confidence: Double = 0.95,
    maximumAttempts: Int = 1_000_000
  ) -> Int? {
    let successes = max(0, requiredSuccesses)
    guard successes > 0 else { return 0 }
    guard successProbability > 0, successProbability <= 1,
      confidence > 0, confidence <= 1,
      maximumAttempts >= successes
    else { return nil }
    if successProbability == 1 { return successes }
    var lower = successes
    var upper = successes
    while upper < maximumAttempts,
      probabilityOfAtLeast(
        successes: successes,
        attempts: upper,
        successProbability: successProbability
      ) < confidence
    {
      lower = upper + 1
      let doubled = upper.multipliedReportingOverflow(by: 2)
      upper = min(
        maximumAttempts,
        doubled.overflow ? maximumAttempts : max(upper + 1, doubled.partialValue)
      )
    }
    guard
      probabilityOfAtLeast(
        successes: successes,
        attempts: upper,
        successProbability: successProbability
      ) >= confidence
    else { return nil }
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if probabilityOfAtLeast(
        successes: successes,
        attempts: middle,
        successProbability: successProbability
      ) >= confidence {
        upper = middle
      } else {
        lower = middle + 1
      }
    }
    return lower
  }

  private static func probabilityOfAtLeast(
    successes: Int,
    attempts: Int,
    successProbability: Double
  ) -> Double {
    guard attempts >= successes else { return 0 }
    guard successes > 0 else { return 1 }
    let failureProbability = 1 - successProbability
    var term = pow(failureProbability, Double(attempts))
    var belowTarget = term
    guard successes > 1 else { return min(1, max(0, 1 - belowTarget)) }
    for successCount in 1..<successes {
      term *= Double(attempts - successCount + 1) / Double(successCount)
      term *= successProbability / failureProbability
      belowTarget += term
      if !belowTarget.isFinite { return 0 }
    }
    return min(1, max(0, 1 - belowTarget))
  }
}

public actor BlueprintRunReservationLedger {
  private var reservations: [UUID: [Int64: Int]] = [:]

  public init() {}

  public func reserve(
    planID: UUID,
    requestedRuns: [Int64: Int],
    availableRuns: [Int64: Int]
  ) -> Bool {
    guard requestedRuns.allSatisfy({ $0.key > 0 && $0.value > 0 }) else {
      return false
    }
    for (itemID, runs) in requestedRuns {
      let reservedElsewhere = reservations.reduce(0) { partial, entry in
        entry.key == planID
          ? partial : partial + entry.value[itemID, default: 0]
      }
      guard availableRuns[itemID, default: 0] - reservedElsewhere >= runs else {
        return false
      }
    }
    reservations[planID] = requestedRuns
    return true
  }

  public func release(planID: UUID) {
    reservations.removeValue(forKey: planID)
  }

  public func reservedRuns(
    blueprintItemID: Int64,
    excluding planID: UUID? = nil
  ) -> Int {
    reservations.reduce(0) { partial, entry in
      entry.key == planID
        ? partial : partial + entry.value[blueprintItemID, default: 0]
    }
  }
}
