import Foundation

public struct MineralPriceTrend: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let averagePrice: Double
  public let changeFraction: Double?
  public let marketDate: String

  public init(
    typeID: Int64,
    name: String,
    averagePrice: Double,
    changeFraction: Double?,
    marketDate: String
  ) {
    self.typeID = typeID
    self.name = name
    self.averagePrice = averagePrice
    self.changeFraction = changeFraction
    self.marketDate = marketDate
  }
}

public enum MineralPriceTrendProjector {
  public static let minerals: [(typeID: Int64, name: String)] = [
    (34, "Tritanium"),
    (35, "Pyerite"),
    (36, "Mexallon"),
    (37, "Isogen"),
    (38, "Nocxium"),
    (39, "Zydrine"),
    (40, "Megacyte"),
    (11_399, "Morphite"),
  ]

  public static func project(
    typeID: Int64,
    name: String,
    history: [ESIMarketHistoryDTO]
  ) -> MineralPriceTrend? {
    let valid = history.filter {
      $0.average.isFinite && $0.average > 0 && !$0.date.isEmpty
    }.sorted { $0.date < $1.date }
    guard let latest = valid.last else { return nil }
    let previous = valid.dropLast().last
    let change: Double?
    if let previous, previous.average.isFinite, previous.average > 0 {
      let value = (latest.average - previous.average) / previous.average
      change = value.isFinite ? value : nil
    } else {
      change = nil
    }
    return MineralPriceTrend(
      typeID: typeID,
      name: name,
      averagePrice: latest.average,
      changeFraction: change,
      marketDate: latest.date
    )
  }
}

public struct DashboardWealthCharacterInput: Sendable {
  public let character: CharacterIdentity
  public let wallet: Sourced<Double>
  public let assets: Sourced<AssetSnapshot>
  public let openOrders: Sourced<[ESICharacterOrderDTO]>?
  public let privateContracts: Sourced<PrivateContractSnapshot>?
  public let corporationAssets: Sourced<AssetSnapshot>?
  public let corporationWallet: Sourced<CorporationWalletSnapshot>?
  public let industryJobs: Sourced<[ESIIndustryJobDTO]>?
  public let blueprints: Sourced<[OwnedBlueprintInstance]>?

  public init(
    character: CharacterIdentity,
    wallet: Sourced<Double>,
    assets: Sourced<AssetSnapshot>,
    openOrders: Sourced<[ESICharacterOrderDTO]>? = nil,
    privateContracts: Sourced<PrivateContractSnapshot>? = nil,
    corporationAssets: Sourced<AssetSnapshot>? = nil,
    corporationWallet: Sourced<CorporationWalletSnapshot>? = nil,
    industryJobs: Sourced<[ESIIndustryJobDTO]>? = nil,
    blueprints: Sourced<[OwnedBlueprintInstance]>? = nil
  ) {
    self.character = character
    self.wallet = wallet
    self.assets = assets
    self.openOrders = openOrders
    self.privateContracts = privateContracts
    self.corporationAssets = corporationAssets
    self.corporationWallet = corporationWallet
    self.industryJobs = industryJobs
    self.blueprints = blueprints
  }
}

public struct DashboardWealthInProgressIndustryValue: Codable, Equatable,
  Sendable
{
  public let characterID: Int64
  public let value: Double?
  public let jobCount: Int
  public let unresolvedJobCount: Int
  public let unvaluedMaterialTypeCount: Int
  public let estimatedJobCount: Int
  public let isComplete: Bool
  public let freshness: DataFreshness

  public init(
    characterID: Int64,
    value: Double?,
    jobCount: Int,
    unresolvedJobCount: Int,
    unvaluedMaterialTypeCount: Int,
    estimatedJobCount: Int,
    isComplete: Bool,
    freshness: DataFreshness
  ) {
    self.characterID = characterID
    self.value = value
    self.jobCount = jobCount
    self.unresolvedJobCount = unresolvedJobCount
    self.unvaluedMaterialTypeCount = unvaluedMaterialTypeCount
    self.estimatedJobCount = estimatedJobCount
    self.isComplete = isComplete
    self.freshness = freshness
  }
}

public struct DashboardIndustryJobValue: Identifiable, Sendable {
  public let ownedJob: DashboardIndustryOwnedJob
  public let knownValue: Double?
  public let unvaluedMaterialTypeIDs: Set<Int64>
  public let isResolved: Bool
  public let freshness: DataFreshness
  public var id: String { ownedJob.id }
  public var materialValue: Double? {
    isResolved && unvaluedMaterialTypeIDs.isEmpty ? knownValue : nil
  }
}

public enum DashboardInProgressIndustryProjector {
  public static let valuationPolicy = "sde-job-material-reference-recursive-v2"

  /// - Parameter fallbackUnitValues: unit values for inputs without an ESI
  ///   reference price, resolved recursively from their own SDE inputs
  ///   (see `DashboardRecursiveMaterialValuator`).
  public static func projectJobs(
    inputs: [DashboardWealthCharacterInput],
    prices: [Int64: AdjustedPrice],
    definitionsByProductTypeID: [Int64: BlueprintDefinition],
    fallbackUnitValues: [Int64: Double] = [:]
  ) -> [DashboardIndustryJobValue] {
    inputs.flatMap { input in
      guard let source = input.industryJobs,
        let jobs = usableValue(source)
      else { return [DashboardIndustryJobValue]() }
      let blueprints = Dictionary(
        (input.blueprints.flatMap(usableValue) ?? []).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
      )
      return jobs.filter { job in
        let activity = job.dashboardActivity
        return (activity == .manufacturing || activity == .reaction)
          && !job.isDelivered && !job.isCancelledOrReverted
      }.map { job in
        let owned = DashboardIndustryOwnedJob(
          characterID: input.character.id,
          characterName: input.character.name,
          job: job
        )
        guard job.runs > 0, let productID = job.productTypeID,
          let definition = definitionsByProductTypeID[productID]
        else {
          return DashboardIndustryJobValue(
            ownedJob: owned, knownValue: nil, unvaluedMaterialTypeIDs: [],
            isResolved: false, freshness: source.state
          )
        }
        var total = 0.0
        var hasValue = definition.activity.materials.isEmpty
        var missing = Set<Int64>()
        let blueprintME = blueprints[job.blueprintID]?.materialEfficiency ?? 0
        for material in definition.activity.materials {
          let quantity = definition.activity.kind == .reaction
            ? saturatedMultiply(Int64(job.runs), material.quantity)
            : IndustryPlanner.manufacturingMaterialQuantity(
              baseQuantity: material.quantity, runs: job.runs,
              materialEfficiency: blueprintME, facilityMultiplier: 1
            )
          let referencePrice = prices[material.typeID].flatMap {
            $0.averagePrice ?? $0.adjustedPrice
          }
          guard quantity > 0,
            let price = referencePrice ?? fallbackUnitValues[material.typeID],
            price.isFinite, price >= 0,
            (Double(quantity) * price).isFinite
          else {
            missing.insert(material.typeID)
            continue
          }
          total += Double(quantity) * price
          hasValue = true
        }
        return DashboardIndustryJobValue(
          ownedJob: owned,
          knownValue: hasValue && total.isFinite ? total : nil,
          unvaluedMaterialTypeIDs: missing, isResolved: true,
          freshness: source.state
        )
      }
    }
  }

  public static func rankedJobs(
    _ values: [DashboardIndustryJobValue]
  ) -> [DashboardIndustryJobValue] {
    values.filter { $0.materialValue != nil }.sorted {
      if $0.materialValue != $1.materialValue {
        return ($0.materialValue ?? 0) > ($1.materialValue ?? 0)
      }
      return $0.id < $1.id
    }
  }

  public static func project(
    inputs: [DashboardWealthCharacterInput],
    prices: [Int64: AdjustedPrice],
    definitionsByProductTypeID: [Int64: BlueprintDefinition],
    fallbackUnitValues: [Int64: Double] = [:],
    jobValues: [DashboardIndustryJobValue]? = nil
  ) -> [Int64: DashboardWealthInProgressIndustryValue] {
    let values = jobValues ?? projectJobs(
      inputs: inputs, prices: prices,
      definitionsByProductTypeID: definitionsByProductTypeID,
      fallbackUnitValues: fallbackUnitValues
    )
    let byCharacter = Dictionary(grouping: values, by: { $0.ownedJob.characterID })
    return Dictionary(
      uniqueKeysWithValues: inputs.map { input in
        (
          input.character.id,
          project(
            input: input,
            values: byCharacter[input.character.id] ?? []
          )
        )
      }
    )
  }

  private static func project(
    input: DashboardWealthCharacterInput,
    values: [DashboardIndustryJobValue]
  ) -> DashboardWealthInProgressIndustryValue {
    guard let sourcedJobs = input.industryJobs else {
      return unavailableIndustryValue(characterID: input.character.id)
    }
    guard let jobs = usableValue(sourcedJobs) else {
      return DashboardWealthInProgressIndustryValue(
        characterID: input.character.id,
        value: nil,
        jobCount: 0,
        unresolvedJobCount: 0,
        unvaluedMaterialTypeCount: 0,
        estimatedJobCount: 0,
        isComplete: false,
        freshness: sourcedJobs.state
      )
    }

    let relevantJobs = jobs.filter {
      guard let activity = $0.dashboardActivity else { return false }
      return (activity == .manufacturing || activity == .reaction)
        && !$0.isDelivered
        && !$0.isCancelledOrReverted
    }
    var knownValue = 0.0
    var hasKnownValue = relevantJobs.isEmpty
    var unresolvedJobCount = 0
    var unvaluedMaterialTypeIDs = Set<Int64>()
    var estimatedJobCount = 0

    for row in values {
      guard row.isResolved else {
        unresolvedJobCount += 1
        continue
      }
      // ESI does not expose the installed job's facility/rig material modifier.
      // Use the known Blueprint ME when the installed instance is still present;
      // otherwise retain a visible neutral-ME estimate rather than dropping the
      // consumed materials from net worth entirely.
      estimatedJobCount += 1
      unvaluedMaterialTypeIDs.formUnion(row.unvaluedMaterialTypeIDs)
      if let value = row.knownValue {
        hasKnownValue = true
        knownValue += value
      }
    }

    let hasIncompleteCoverage =
      unresolvedJobCount > 0
      || !unvaluedMaterialTypeIDs.isEmpty
      || estimatedJobCount > 0
      || sourcedJobs.state != .fresh
    return DashboardWealthInProgressIndustryValue(
      characterID: input.character.id,
      value: hasKnownValue && knownValue.isFinite ? knownValue : nil,
      jobCount: relevantJobs.count,
      unresolvedJobCount: unresolvedJobCount,
      unvaluedMaterialTypeCount: unvaluedMaterialTypeIDs.count,
      estimatedJobCount: estimatedJobCount,
      isComplete: !hasIncompleteCoverage,
      freshness: hasIncompleteCoverage ? .partial : .fresh
    )
  }

  private static func usableValue<Value: Codable & Sendable>(
    _ sourced: Sourced<Value>
  ) -> Value? {
    switch sourced.state {
    case .fresh, .partial, .stale: sourced.value
    case .forbidden, .unavailable: nil
    }
  }

  private static func saturatedMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    if overflow { return lhs.signum() == rhs.signum() ? .max : .min }
    return value
  }

  private static func unavailableIndustryValue(
    characterID: Int64
  ) -> DashboardWealthInProgressIndustryValue {
    DashboardWealthInProgressIndustryValue(
      characterID: characterID,
      value: nil,
      jobCount: 0,
      unresolvedJobCount: 0,
      unvaluedMaterialTypeCount: 0,
      estimatedJobCount: 0,
      isComplete: false,
      freshness: .unavailable
    )
  }
}

public struct DashboardWealthUnpricedType: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String

  public init(typeID: Int64, name: String) {
    self.typeID = typeID
    self.name = name
  }
}

public struct DashboardWealthCorporationCoverage: Codable, Equatable, Sendable {
  public let corporationCount: Int
  public let includedCorporationCount: Int
  public let roleMissingCorporationCount: Int
  public let unavailableCorporationCount: Int
  public let unvaluedAssetTypeCount: Int
  public let excludedBlueprintCopyCount: Int
  public let unknownBlueprintStatusCount: Int

  private enum CodingKeys: String, CodingKey {
    case corporationCount, includedCorporationCount
    case roleMissingCorporationCount, unavailableCorporationCount
    case unvaluedAssetTypeCount, excludedBlueprintCopyCount
    case unknownBlueprintStatusCount
  }

  public init(
    corporationCount: Int,
    includedCorporationCount: Int,
    roleMissingCorporationCount: Int,
    unavailableCorporationCount: Int,
    unvaluedAssetTypeCount: Int = 0,
    excludedBlueprintCopyCount: Int = 0,
    unknownBlueprintStatusCount: Int = 0
  ) {
    self.corporationCount = corporationCount
    self.includedCorporationCount = includedCorporationCount
    self.roleMissingCorporationCount = roleMissingCorporationCount
    self.unavailableCorporationCount = unavailableCorporationCount
    self.unvaluedAssetTypeCount = unvaluedAssetTypeCount
    self.excludedBlueprintCopyCount = excludedBlueprintCopyCount
    self.unknownBlueprintStatusCount = unknownBlueprintStatusCount
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    corporationCount = try values.decode(Int.self, forKey: .corporationCount)
    includedCorporationCount = try values.decode(Int.self, forKey: .includedCorporationCount)
    roleMissingCorporationCount = try values.decode(Int.self, forKey: .roleMissingCorporationCount)
    unavailableCorporationCount = try values.decode(Int.self, forKey: .unavailableCorporationCount)
    unvaluedAssetTypeCount =
      try values.decodeIfPresent(Int.self, forKey: .unvaluedAssetTypeCount) ?? 0
    excludedBlueprintCopyCount =
      try values.decodeIfPresent(Int.self, forKey: .excludedBlueprintCopyCount) ?? 0
    unknownBlueprintStatusCount =
      try values.decodeIfPresent(Int.self, forKey: .unknownBlueprintStatusCount) ?? 0
  }
}

public struct DashboardWealthCharacterValue: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { characterID }
  public let characterID: Int64
  public let characterName: String
  public let walletValue: Double?
  public let assetValue: Double?
  public let ordersValue: Double?
  public let escrowValue: Double?
  public let contractsValue: Double?
  public let courierValue: Double?
  public let industryInProgressValue: Double?
  public let knownValue: Double?
  public let unvaluedAssetTypeCount: Int
  public let unvaluedAssetTypes: [DashboardWealthUnpricedType]
  public let excludedBlueprintCopyCount: Int
  public let unknownBlueprintStatusCount: Int
  public let unvaluedOrderCount: Int
  public let missingEscrowOrderCount: Int
  public let unvaluedContractItemTypeCount: Int
  public let unvaluedContractItemTypes: [DashboardWealthUnpricedType]
  public let excludedContractBlueprintCopyCount: Int
  public let unavailableContractCount: Int
  public let invalidCourierCollateralCount: Int
  public let inProgressIndustryJobCount: Int
  public let unresolvedIndustryJobCount: Int
  public let unvaluedIndustryMaterialTypeCount: Int
  public let estimatedIndustryJobCount: Int
  /// Value of owned originals (BPO) included in `assetValue`.
  public let blueprintOriginalValue: Double?
  public let blueprintOriginalCount: Int
  /// Originals valued only at the SDE base price because the research share
  /// could not be priced.
  public let estimatedBlueprintOriginalCount: Int
  /// Value of owned copies (BPC) included in `assetValue`.
  public let blueprintCopyValue: Double?
  public let valuedBlueprintCopyCount: Int
  public let isComplete: Bool
  public let freshness: DataFreshness

  private enum CodingKeys: String, CodingKey {
    case characterID
    case characterName
    case walletValue
    case assetValue
    case ordersValue
    case escrowValue
    case contractsValue
    case courierValue
    case industryInProgressValue
    case knownValue
    case unvaluedAssetTypeCount
    case unvaluedAssetTypes
    case excludedBlueprintCopyCount
    case unknownBlueprintStatusCount
    case unvaluedOrderCount
    case missingEscrowOrderCount
    case unvaluedContractItemTypeCount
    case unvaluedContractItemTypes
    case excludedContractBlueprintCopyCount
    case unavailableContractCount
    case invalidCourierCollateralCount
    case inProgressIndustryJobCount
    case unresolvedIndustryJobCount
    case unvaluedIndustryMaterialTypeCount
    case estimatedIndustryJobCount
    case blueprintOriginalValue
    case blueprintOriginalCount
    case estimatedBlueprintOriginalCount
    case blueprintCopyValue
    case valuedBlueprintCopyCount
    case isComplete
    case freshness
  }

  public init(
    characterID: Int64,
    characterName: String,
    walletValue: Double?,
    assetValue: Double?,
    ordersValue: Double? = nil,
    escrowValue: Double? = nil,
    contractsValue: Double? = nil,
    courierValue: Double? = nil,
    industryInProgressValue: Double? = nil,
    knownValue: Double?,
    unvaluedAssetTypeCount: Int,
    unvaluedAssetTypes: [DashboardWealthUnpricedType] = [],
    excludedBlueprintCopyCount: Int = 0,
    unknownBlueprintStatusCount: Int = 0,
    unvaluedOrderCount: Int = 0,
    missingEscrowOrderCount: Int = 0,
    unvaluedContractItemTypeCount: Int = 0,
    unvaluedContractItemTypes: [DashboardWealthUnpricedType] = [],
    excludedContractBlueprintCopyCount: Int = 0,
    unavailableContractCount: Int = 0,
    invalidCourierCollateralCount: Int = 0,
    inProgressIndustryJobCount: Int = 0,
    unresolvedIndustryJobCount: Int = 0,
    unvaluedIndustryMaterialTypeCount: Int = 0,
    estimatedIndustryJobCount: Int = 0,
    blueprintOriginalValue: Double? = nil,
    blueprintOriginalCount: Int = 0,
    estimatedBlueprintOriginalCount: Int = 0,
    blueprintCopyValue: Double? = nil,
    valuedBlueprintCopyCount: Int = 0,
    isComplete: Bool,
    freshness: DataFreshness
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.walletValue = walletValue
    self.assetValue = assetValue
    self.ordersValue = ordersValue
    self.escrowValue = escrowValue
    self.contractsValue = contractsValue
    self.courierValue = courierValue
    self.industryInProgressValue = industryInProgressValue
    self.knownValue = knownValue
    self.unvaluedAssetTypeCount = unvaluedAssetTypeCount
    self.unvaluedAssetTypes = unvaluedAssetTypes
    self.excludedBlueprintCopyCount = excludedBlueprintCopyCount
    self.unknownBlueprintStatusCount = unknownBlueprintStatusCount
    self.unvaluedOrderCount = unvaluedOrderCount
    self.missingEscrowOrderCount = missingEscrowOrderCount
    self.unvaluedContractItemTypeCount = unvaluedContractItemTypeCount
    self.unvaluedContractItemTypes = unvaluedContractItemTypes
    self.excludedContractBlueprintCopyCount =
      excludedContractBlueprintCopyCount
    self.unavailableContractCount = unavailableContractCount
    self.invalidCourierCollateralCount = invalidCourierCollateralCount
    self.inProgressIndustryJobCount = inProgressIndustryJobCount
    self.unresolvedIndustryJobCount = unresolvedIndustryJobCount
    self.unvaluedIndustryMaterialTypeCount =
      unvaluedIndustryMaterialTypeCount
    self.estimatedIndustryJobCount = estimatedIndustryJobCount
    self.blueprintOriginalValue = blueprintOriginalValue
    self.blueprintOriginalCount = blueprintOriginalCount
    self.estimatedBlueprintOriginalCount = estimatedBlueprintOriginalCount
    self.blueprintCopyValue = blueprintCopyValue
    self.valuedBlueprintCopyCount = valuedBlueprintCopyCount
    self.isComplete = isComplete
    self.freshness = freshness
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    characterID = try values.decode(Int64.self, forKey: .characterID)
    characterName = try values.decode(String.self, forKey: .characterName)
    walletValue = try values.decodeIfPresent(Double.self, forKey: .walletValue)
    assetValue = try values.decodeIfPresent(Double.self, forKey: .assetValue)
    ordersValue = try values.decodeIfPresent(Double.self, forKey: .ordersValue)
    escrowValue = try values.decodeIfPresent(Double.self, forKey: .escrowValue)
    contractsValue = try values.decodeIfPresent(
      Double.self,
      forKey: .contractsValue
    )
    courierValue = try values.decodeIfPresent(
      Double.self,
      forKey: .courierValue
    )
    industryInProgressValue = try values.decodeIfPresent(
      Double.self,
      forKey: .industryInProgressValue
    )
    knownValue = try values.decodeIfPresent(Double.self, forKey: .knownValue)
    unvaluedAssetTypeCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unvaluedAssetTypeCount
      ) ?? 0
    unvaluedAssetTypes =
      try values.decodeIfPresent(
        [DashboardWealthUnpricedType].self,
        forKey: .unvaluedAssetTypes
      ) ?? []
    excludedBlueprintCopyCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .excludedBlueprintCopyCount
      ) ?? 0
    unknownBlueprintStatusCount =
      try values.decodeIfPresent(Int.self, forKey: .unknownBlueprintStatusCount) ?? 0
    unvaluedOrderCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unvaluedOrderCount
      ) ?? 0
    missingEscrowOrderCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .missingEscrowOrderCount
      ) ?? 0
    unvaluedContractItemTypeCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unvaluedContractItemTypeCount
      ) ?? 0
    unvaluedContractItemTypes =
      try values.decodeIfPresent(
        [DashboardWealthUnpricedType].self,
        forKey: .unvaluedContractItemTypes
      ) ?? []
    excludedContractBlueprintCopyCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .excludedContractBlueprintCopyCount
      ) ?? 0
    unavailableContractCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unavailableContractCount
      ) ?? 0
    invalidCourierCollateralCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .invalidCourierCollateralCount
      ) ?? 0
    inProgressIndustryJobCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .inProgressIndustryJobCount
      ) ?? 0
    unresolvedIndustryJobCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unresolvedIndustryJobCount
      ) ?? 0
    unvaluedIndustryMaterialTypeCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .unvaluedIndustryMaterialTypeCount
      ) ?? 0
    estimatedIndustryJobCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .estimatedIndustryJobCount
      ) ?? 0
    blueprintOriginalValue = try values.decodeIfPresent(
      Double.self,
      forKey: .blueprintOriginalValue
    )
    blueprintOriginalCount =
      try values.decodeIfPresent(Int.self, forKey: .blueprintOriginalCount) ?? 0
    estimatedBlueprintOriginalCount =
      try values.decodeIfPresent(
        Int.self,
        forKey: .estimatedBlueprintOriginalCount
      ) ?? 0
    blueprintCopyValue = try values.decodeIfPresent(
      Double.self,
      forKey: .blueprintCopyValue
    )
    valuedBlueprintCopyCount =
      try values.decodeIfPresent(Int.self, forKey: .valuedBlueprintCopyCount) ?? 0
    isComplete = try values.decode(Bool.self, forKey: .isComplete)
    freshness = try values.decode(DataFreshness.self, forKey: .freshness)
  }
}

public struct DashboardWealthSnapshot: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public let capturedAt: Date
  public let valuationPolicy: String
  public let characters: [DashboardWealthCharacterValue]
  public let knownTotalValue: Double?
  public let walletTotal: Double?
  public let assetTotal: Double?
  public let ordersTotal: Double?
  public let escrowTotal: Double?
  public let contractsTotal: Double?
  public let courierTotal: Double?
  public let corporationWalletTotal: Double?
  public let corporationAssetTotal: Double?
  public let industryInProgressTotal: Double?
  public let contractsFreshness: DataFreshness?
  public let courierFreshness: DataFreshness?
  public let corporationWalletFreshness: DataFreshness?
  public let corporationAssetFreshness: DataFreshness?
  public let industryInProgressFreshness: DataFreshness?
  public let corporationWalletCoverage: DashboardWealthCorporationCoverage?
  public let corporationAssetCoverage: DashboardWealthCorporationCoverage?
  public let isComplete: Bool
  public let freshness: DataFreshness
  public let priceSource: SourceIdentity

  public init(
    id: UUID = UUID(),
    capturedAt: Date,
    valuationPolicy: String,
    characters: [DashboardWealthCharacterValue],
    knownTotalValue: Double?,
    walletTotal: Double? = nil,
    assetTotal: Double? = nil,
    ordersTotal: Double? = nil,
    escrowTotal: Double? = nil,
    contractsTotal: Double? = nil,
    courierTotal: Double? = nil,
    corporationWalletTotal: Double? = nil,
    corporationAssetTotal: Double? = nil,
    industryInProgressTotal: Double? = nil,
    contractsFreshness: DataFreshness? = nil,
    courierFreshness: DataFreshness? = nil,
    corporationWalletFreshness: DataFreshness? = nil,
    corporationAssetFreshness: DataFreshness? = nil,
    industryInProgressFreshness: DataFreshness? = nil,
    corporationWalletCoverage: DashboardWealthCorporationCoverage? = nil,
    corporationAssetCoverage: DashboardWealthCorporationCoverage? = nil,
    isComplete: Bool,
    freshness: DataFreshness,
    priceSource: SourceIdentity
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.valuationPolicy = valuationPolicy
    self.characters = characters
    self.knownTotalValue = knownTotalValue
    self.walletTotal = walletTotal
    self.assetTotal = assetTotal
    self.ordersTotal = ordersTotal
    self.escrowTotal = escrowTotal
    self.contractsTotal = contractsTotal
    self.courierTotal = courierTotal
    self.corporationWalletTotal = corporationWalletTotal
    self.corporationAssetTotal = corporationAssetTotal
    self.industryInProgressTotal = industryInProgressTotal
    self.contractsFreshness = contractsFreshness
    self.courierFreshness = courierFreshness
    self.corporationWalletFreshness = corporationWalletFreshness
    self.corporationAssetFreshness = corporationAssetFreshness
    self.industryInProgressFreshness = industryInProgressFreshness
    self.corporationWalletCoverage = corporationWalletCoverage
    self.corporationAssetCoverage = corporationAssetCoverage
    self.isComplete = isComplete
    self.freshness = freshness
    self.priceSource = priceSource
  }
}

public enum DashboardWealthProjector {
  public static let valuationPolicy =
    "esi-average-then-adjusted-plus-sde-job-materials-bpo-research-bpc-contracts-v4"

  public static func project(
    inputs: [DashboardWealthCharacterInput],
    prices: ReferencePriceSnapshot,
    typeNames: [Int64: String] = [:],
    assetClassifications: [Int64: IndustryItemClassification] = [:],
    inProgressIndustryValues:
      [Int64: DashboardWealthInProgressIndustryValue] = [:],
    blueprintValuation: DashboardWealthBlueprintValuation = .empty
  ) -> DashboardWealthSnapshot {
    let rows = inputs.map { input in
      project(
        input: input,
        prices: prices.prices,
        typeNames: typeNames,
        assetClassifications: assetClassifications,
        inProgressIndustry: inProgressIndustryValues[input.character.id],
        blueprintValuation: blueprintValuation
      )
    }.sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    let knownValues = rows.compactMap(\.knownValue)
    let corporationAssets = corporationAssetProjection(
      inputs: inputs,
      prices: prices.prices,
      assetClassifications: assetClassifications,
      blueprintValuation: blueprintValuation
    )
    let corporationWallet = corporationWalletProjection(inputs: inputs)
    let corporationValues = [
      corporationAssets.value,
      corporationWallet.value,
    ].compactMap { $0 }
    let allKnownValues = knownValues + corporationValues
    return DashboardWealthSnapshot(
      capturedAt: prices.capturedAt,
      valuationPolicy: valuationPolicy,
      characters: rows,
      knownTotalValue:
        allKnownValues.isEmpty ? nil : allKnownValues.reduce(0, +),
      walletTotal: componentTotal(rows.map(\.walletValue)),
      assetTotal: componentTotal(rows.map(\.assetValue)),
      ordersTotal: componentTotal(rows.map(\.ordersValue)),
      escrowTotal: componentTotal(rows.map(\.escrowValue)),
      contractsTotal: componentTotal(rows.map(\.contractsValue)),
      courierTotal: componentTotal(rows.map(\.courierValue)),
      corporationWalletTotal: corporationWallet.value,
      corporationAssetTotal: corporationAssets.value,
      industryInProgressTotal: componentTotal(
        rows.map(\.industryInProgressValue)
      ),
      contractsFreshness: valuedComponentFreshness(
        values: rows.map(\.contractsValue),
        states: inputs.map { $0.privateContracts?.state ?? .unavailable },
        hasIncompleteValuation: rows.contains {
          $0.unvaluedContractItemTypeCount > 0
            || $0.unavailableContractCount > 0
        }
      ),
      courierFreshness: valuedComponentFreshness(
        values: rows.map(\.courierValue),
        states: inputs.map { $0.privateContracts?.state ?? .unavailable },
        hasIncompleteValuation: rows.contains {
          $0.invalidCourierCollateralCount > 0
        }
      ),
      corporationWalletFreshness: corporationWallet.freshness,
      corporationAssetFreshness: corporationAssets.freshness,
      industryInProgressFreshness: valuedComponentFreshness(
        values: rows.map(\.industryInProgressValue),
        states: rows.map { row in
          inProgressIndustryValues[row.characterID]?.freshness
            ?? .unavailable
        },
        hasIncompleteValuation: rows.contains {
          $0.unresolvedIndustryJobCount > 0
            || $0.unvaluedIndustryMaterialTypeCount > 0
            || $0.estimatedIndustryJobCount > 0
        }
      ),
      corporationWalletCoverage: corporationWallet.coverage,
      corporationAssetCoverage: corporationAssets.coverage,
      isComplete: !rows.isEmpty && rows.allSatisfy(\.isComplete)
        && (corporationAssets.coverage?.unknownBlueprintStatusCount ?? 0) == 0
        && (corporationAssets.coverage?.unvaluedAssetTypeCount ?? 0) == 0,
      freshness: combinedFreshness(rows.map(\.freshness)),
      priceSource: prices.source
    )
  }

  private static func project(
    input: DashboardWealthCharacterInput,
    prices: [Int64: AdjustedPrice],
    typeNames: [Int64: String],
    assetClassifications: [Int64: IndustryItemClassification],
    inProgressIndustry: DashboardWealthInProgressIndustryValue?,
    blueprintValuation: DashboardWealthBlueprintValuation
  ) -> DashboardWealthCharacterValue {
    let walletValue = usableValue(input.wallet)
    let assetSnapshot = usableValue(input.assets)
    let openOrders = input.openOrders.flatMap(usableValue)
    let privateContracts = input.privateContracts.flatMap(usableValue)
    let blueprintRecords = Dictionary(
      (input.blueprints.flatMap(usableValue) ?? []).map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let assetProjection = assetSnapshot.map {
      valueAssets(
        $0.items,
        prices: prices,
        classifications: assetClassifications,
        blueprints: blueprintRecords,
        valuation: blueprintValuation
      )
    }
    let assetValue = assetProjection?.value
    let unvaluedTypeIDs = assetProjection?.unpricedTypeIDs ?? []
    let excludedBlueprintCopyCount = assetProjection?.excludedCopyCount ?? 0
    let unknownBlueprintStatusCount = assetProjection?.unknownStatusCount ?? 0
    var ordersValue: Double?
    var escrowValue: Double?
    var unvaluedOrderCount = 0
    var missingEscrowOrderCount = 0
    if let openOrders {
      var sellOrderTotal = 0.0
      var buyOrderEscrowTotal = 0.0
      for order in openOrders where order.volumeRemain > 0 {
        if order.isBuyOrder {
          guard let escrow = order.escrow,
            escrow.isFinite,
            escrow >= 0
          else {
            missingEscrowOrderCount += 1
            continue
          }
          buyOrderEscrowTotal += escrow
        } else {
          let value = order.price * Double(order.volumeRemain)
          guard order.price.isFinite,
            order.price >= 0,
            value.isFinite
          else {
            unvaluedOrderCount += 1
            continue
          }
          sellOrderTotal += value
        }
      }
      ordersValue = unvaluedOrderCount == 0 ? sellOrderTotal : nil
      escrowValue =
        missingEscrowOrderCount == 0 ? buyOrderEscrowTotal : nil
    }
    var contractsValue: Double?
    var courierValue: Double?
    var unvaluedContractItemTypeIDs = Set<Int64>()
    var excludedContractBlueprintCopyCount = 0
    var unavailableContractCount = 0
    var invalidCourierCollateralCount = 0
    if let privateContracts {
      var contractTotal = 0.0
      for itemContract in privateContracts.itemContracts {
        for item in itemContract.items where item.isIncluded {
          if item.rawQuantity == -2 {
            excludedContractBlueprintCopyCount += 1
            continue
          }
          let quantity = item.rawQuantity == -1 ? 1 : item.quantity
          guard quantity > 0 else { continue }
          guard let reference = prices[item.typeID],
            let unitPrice = reference.averagePrice ?? reference.adjustedPrice,
            unitPrice.isFinite,
            unitPrice >= 0
          else {
            unvaluedContractItemTypeIDs.insert(item.typeID)
            continue
          }
          let value = Double(quantity) * unitPrice
          guard value.isFinite else {
            unvaluedContractItemTypeIDs.insert(item.typeID)
            continue
          }
          contractTotal += value
        }
      }
      contractsValue = contractTotal.isFinite ? contractTotal : nil
      unavailableContractCount =
        privateContracts.failedItemContractIDs.count
        + privateContracts.omittedItemContractCount

      var courierTotal = 0.0
      for contract in privateContracts.inTransitCouriers {
        guard let collateral = contract.collateral,
          collateral.isFinite,
          collateral >= 0
        else {
          invalidCourierCollateralCount += 1
          continue
        }
        courierTotal += collateral
      }
      courierValue = courierTotal.isFinite ? courierTotal : nil
    }
    let knownParts = [
      walletValue, assetValue, ordersValue, escrowValue, contractsValue,
      courierValue, inProgressIndustry?.value,
    ].compactMap { $0 }
    let knownValue = knownParts.isEmpty ? nil : knownParts.reduce(0, +)
    return DashboardWealthCharacterValue(
      characterID: input.character.id,
      characterName: input.character.name,
      walletValue: walletValue,
      assetValue: assetValue,
      ordersValue: ordersValue,
      escrowValue: escrowValue,
      contractsValue: contractsValue,
      courierValue: courierValue,
      industryInProgressValue: inProgressIndustry?.value,
      knownValue: knownValue,
      unvaluedAssetTypeCount: unvaluedTypeIDs.count,
      unvaluedAssetTypes: unpricedTypes(
        ids: unvaluedTypeIDs,
        typeNames: typeNames
      ),
      excludedBlueprintCopyCount: excludedBlueprintCopyCount,
      unknownBlueprintStatusCount: unknownBlueprintStatusCount,
      unvaluedOrderCount: unvaluedOrderCount,
      missingEscrowOrderCount: missingEscrowOrderCount,
      unvaluedContractItemTypeCount: unvaluedContractItemTypeIDs.count,
      unvaluedContractItemTypes: unpricedTypes(
        ids: unvaluedContractItemTypeIDs,
        typeNames: typeNames
      ),
      excludedContractBlueprintCopyCount:
        excludedContractBlueprintCopyCount,
      unavailableContractCount: unavailableContractCount,
      invalidCourierCollateralCount: invalidCourierCollateralCount,
      inProgressIndustryJobCount: inProgressIndustry?.jobCount ?? 0,
      unresolvedIndustryJobCount: inProgressIndustry?.unresolvedJobCount ?? 0,
      unvaluedIndustryMaterialTypeCount:
        inProgressIndustry?.unvaluedMaterialTypeCount ?? 0,
      estimatedIndustryJobCount: inProgressIndustry?.estimatedJobCount ?? 0,
      blueprintOriginalValue: assetProjection.map { $0.blueprints.originalValue },
      blueprintOriginalCount: assetProjection?.blueprints.originalCount ?? 0,
      estimatedBlueprintOriginalCount:
        assetProjection?.blueprints.estimatedOriginalCount ?? 0,
      blueprintCopyValue: assetProjection.map { $0.blueprints.copyValue },
      valuedBlueprintCopyCount: assetProjection?.blueprints.valuedCopyCount ?? 0,
      isComplete: walletValue != nil && assetValue != nil
        && ordersValue != nil && escrowValue != nil
        && contractsValue != nil && courierValue != nil
        && unvaluedTypeIDs.isEmpty && unknownBlueprintStatusCount == 0
        && (assetProjection?.blueprints.estimatedOriginalCount ?? 0) == 0
        && unvaluedOrderCount == 0
        && missingEscrowOrderCount == 0
        && unvaluedContractItemTypeIDs.isEmpty
        && unavailableContractCount == 0
        && invalidCourierCollateralCount == 0
        && (inProgressIndustry?.isComplete ?? true),
      freshness: combinedFreshness(
        [
          input.wallet.state,
          adjustedFreshness(
            assetValuationFreshness(input.assets),
            incomplete: !unvaluedTypeIDs.isEmpty || unknownBlueprintStatusCount > 0
              || (assetProjection?.blueprints.estimatedOriginalCount ?? 0) > 0
          ),
          input.openOrders?.state ?? .unavailable,
          input.privateContracts?.state ?? .unavailable,
        ] + (inProgressIndustry.map { [$0.freshness] } ?? []))
    )
  }

  private struct CorporationProjection {
    let value: Double?
    let freshness: DataFreshness?
    let coverage: DashboardWealthCorporationCoverage?
  }

  private struct SelectedCorporationSource<Value: Codable & Sendable> {
    let corporationID: Int64
    let sourced: Sourced<Value>
  }

  private static func corporationAssetProjection(
    inputs: [DashboardWealthCharacterInput],
    prices: [Int64: AdjustedPrice],
    assetClassifications: [Int64: IndustryItemClassification],
    blueprintValuation: DashboardWealthBlueprintValuation
  ) -> CorporationProjection {
    let selected = selectedCorporationSources(
      inputs: inputs,
      source: \.corporationAssets,
      valueCorporationID: { $0.corporationID }
    )
    guard !selected.isEmpty else {
      return CorporationProjection(value: nil, freshness: nil, coverage: nil)
    }
    var total = 0.0
    var hasValue = false
    var unvaluedTypeIDs = Set<Int64>()
    var excludedBlueprintCopyCount = 0
    var unknownBlueprintStatusCount = 0
    for entry in selected {
      guard let snapshot = usableValue(entry.sourced) else { continue }
      let projection = valueAssets(
        snapshot.items,
        prices: prices,
        classifications: assetClassifications,
        blueprints: [:],
        valuation: blueprintValuation
      )
      if let value = projection.value {
        hasValue = true
        total += value
      }
      unvaluedTypeIDs.formUnion(projection.unpricedTypeIDs)
      excludedBlueprintCopyCount += projection.excludedCopyCount
      unknownBlueprintStatusCount += projection.unknownStatusCount
    }
    return CorporationProjection(
      value: hasValue && total.isFinite ? total : nil,
      freshness: adjustedFreshness(
        combinedFreshness(
          selected.map {
            assetValuationFreshness($0.sourced)
          }),
        incomplete: !unvaluedTypeIDs.isEmpty || unknownBlueprintStatusCount > 0
      ),
      coverage: corporationCoverage(
        selected: selected,
        roleDiagnostic: "esi.corporation-assets.director-required",
        unvaluedAssetTypeCount: unvaluedTypeIDs.count,
        excludedBlueprintCopyCount: excludedBlueprintCopyCount,
        unknownBlueprintStatusCount: unknownBlueprintStatusCount
      )
    )
  }

  private static func corporationWalletProjection(
    inputs: [DashboardWealthCharacterInput]
  ) -> CorporationProjection {
    let selected = selectedCorporationSources(
      inputs: inputs,
      source: \.corporationWallet,
      valueCorporationID: { $0.corporationID }
    )
    guard !selected.isEmpty else {
      return CorporationProjection(value: nil, freshness: nil, coverage: nil)
    }
    var total = 0.0
    var hasValue = false
    var hasInvalidBalance = false
    for entry in selected {
      let sourced = entry.sourced
      guard let snapshot = usableValue(sourced) else { continue }
      hasValue = true
      for division in snapshot.divisions {
        guard division.balance.isFinite else {
          hasInvalidBalance = true
          continue
        }
        total += division.balance
      }
    }
    return CorporationProjection(
      value: hasValue && total.isFinite ? total : nil,
      freshness: adjustedFreshness(
        combinedFreshness(selected.map(\.sourced.state)),
        incomplete: hasInvalidBalance
      ),
      coverage: corporationCoverage(
        selected: selected,
        roleDiagnostic: "esi.corporation-wallet.accountant-required"
      )
    )
  }

  private static func selectedCorporationSources<Value: Codable & Sendable>(
    inputs: [DashboardWealthCharacterInput],
    source: KeyPath<DashboardWealthCharacterInput, Sourced<Value>?>,
    valueCorporationID: (Value) -> Int64?
  ) -> [SelectedCorporationSource<Value>] {
    var selected: [Int64: Sourced<Value>] = [:]
    for input in inputs {
      guard let sourced = input[keyPath: source] else { continue }
      let id =
        sourced.value.flatMap(valueCorporationID)
        ?? input.character.corporationID
      guard let id else {
        continue
      }
      guard let current = selected[id] else {
        selected[id] = sourced
        continue
      }
      if freshnessRank(sourced.state) > freshnessRank(current.state)
        || (freshnessRank(sourced.state) == freshnessRank(current.state)
          && sourced.source.capturedAt > current.source.capturedAt)
      {
        selected[id] = sourced
      }
    }
    return selected.keys.sorted().compactMap { corporationID in
      selected[corporationID].map {
        SelectedCorporationSource(
          corporationID: corporationID,
          sourced: $0
        )
      }
    }
  }

  private static func corporationCoverage<Value: Codable & Sendable>(
    selected: [SelectedCorporationSource<Value>],
    roleDiagnostic: String,
    unvaluedAssetTypeCount: Int = 0,
    excludedBlueprintCopyCount: Int = 0,
    unknownBlueprintStatusCount: Int = 0
  ) -> DashboardWealthCorporationCoverage {
    DashboardWealthCorporationCoverage(
      corporationCount: selected.count,
      includedCorporationCount: selected.filter {
        usableValue($0.sourced) != nil
      }.count,
      roleMissingCorporationCount: selected.filter {
        $0.sourced.diagnostics.contains(roleDiagnostic)
      }.count,
      unavailableCorporationCount: selected.filter {
        $0.sourced.state == .unavailable
      }.count,
      unvaluedAssetTypeCount: unvaluedAssetTypeCount,
      excludedBlueprintCopyCount: excludedBlueprintCopyCount,
      unknownBlueprintStatusCount: unknownBlueprintStatusCount
    )
  }

  struct BlueprintAssetTotals {
    var originalValue = 0.0
    var originalCount = 0
    var estimatedOriginalCount = 0
    var copyValue = 0.0
    var valuedCopyCount = 0
  }

  private enum AssetBlueprintKind {
    case notBlueprint
    case original
    case copy
    case unknown
  }

  private static func valueAssets(
    _ items: [AssetItem],
    prices: [Int64: AdjustedPrice],
    classifications: [Int64: IndustryItemClassification],
    blueprints: [Int64: OwnedBlueprintInstance],
    valuation: DashboardWealthBlueprintValuation
  ) -> (
    value: Double?, unpricedTypeIDs: Set<Int64>, excludedCopyCount: Int,
    unknownStatusCount: Int, blueprints: BlueprintAssetTotals
  ) {
    var total = 0.0
    var unpricedTypeIDs = Set<Int64>()
    var excludedCopyCount = 0
    var unknownStatusCount = 0
    var blueprintTotals = BlueprintAssetTotals()
    for item in items {
      let quantity = item.quantity < 0 ? 1 : item.quantity
      guard quantity > 0 else { continue }
      switch blueprintKind(
        item: item,
        record: blueprints[item.id],
        classification: classifications[item.typeID]
      ) {
      case .unknown:
        unknownStatusCount += 1
        continue
      case .copy:
        // A copy is valued at the lowest public Contract price per run for
        // the same blueprint type. Without runs or a Contract price the copy
        // stays explicitly unvalued instead of borrowing the original price.
        guard let runs = blueprints[item.id]?.runs, runs > 0,
          let runPrice = valuation.copyRunPricesByTypeID[item.typeID]
        else {
          excludedCopyCount += 1
          continue
        }
        let value = runPrice * Double(runs) * Double(quantity)
        guard value.isFinite, value >= 0 else {
          excludedCopyCount += 1
          continue
        }
        total += value
        blueprintTotals.copyValue += value
        blueprintTotals.valuedCopyCount += 1
        continue
      case .original:
        if let researched = valuation.originalValuesByItemID[item.id] {
          let value = researched.value * Double(quantity)
          if value.isFinite {
            total += value
            blueprintTotals.originalValue += value
            blueprintTotals.originalCount += 1
            if researched.isLowerBound {
              blueprintTotals.estimatedOriginalCount += 1
            }
            continue
          }
        }
        let record = blueprints[item.id]
        let isUnresearched =
          record == nil
          || (record?.materialEfficiency == 0 && record?.timeEfficiency == 0)
        if let base = valuation.originalBaseValuesByTypeID[item.typeID] {
          let value = base * Double(quantity)
          if value.isFinite {
            total += value
            blueprintTotals.originalValue += value
            blueprintTotals.originalCount += 1
            if !isUnresearched {
              blueprintTotals.estimatedOriginalCount += 1
            }
            continue
          }
        }
      case .notBlueprint:
        break
      }
      guard let reference = prices[item.typeID],
        let unitPrice = reference.averagePrice ?? reference.adjustedPrice,
        unitPrice.isFinite, unitPrice >= 0
      else {
        unpricedTypeIDs.insert(item.typeID)
        continue
      }
      let value = Double(quantity) * unitPrice
      guard value.isFinite else {
        unpricedTypeIDs.insert(item.typeID)
        continue
      }
      total += value
    }
    return (
      total.isFinite ? total : nil, unpricedTypeIDs, excludedCopyCount,
      unknownStatusCount, blueprintTotals
    )
  }

  /// The ESI blueprint record (same item ID) is authoritative. Otherwise the
  /// asset flag decides: copies are always single items with
  /// `is_blueprint_copy`, so a stacked blueprint is an original. A single
  /// blueprint without a record or flag keeps the explicit unknown state.
  private static func blueprintKind(
    item: AssetItem,
    record: OwnedBlueprintInstance?,
    classification: IndustryItemClassification?
  ) -> AssetBlueprintKind {
    if let record {
      switch record.kind {
      case .original: return .original
      case .copy: return .copy
      case .unknown: break
      }
    }
    if item.isBlueprintCopy == true
      || (item.isBlueprintCopy == nil && item.quantity == -2)
    {
      return .copy
    }
    if item.quantity == -1 { return .original }
    let category = classification?.categoryName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let category, !category.isEmpty else {
      return item.isBlueprintCopy == nil ? .unknown : .notBlueprint
    }
    guard category.caseInsensitiveCompare("Blueprint") == .orderedSame else {
      return .notBlueprint
    }
    if item.isBlueprintCopy == false || !item.singleton || item.quantity > 1 {
      return .original
    }
    return .unknown
  }

  private static func assetValuationFreshness<Value: Codable & Sendable>(
    _ sourced: Sourced<Value>
  ) -> DataFreshness {
    // Asset sync can be partial solely because private structure or division
    // names could not be resolved. The inventory itself is still complete for
    // valuation, so presentation metadata must not downgrade net worth.
    let presentationOnlyPrefixes = [
      "esi.structure-resolution.",
      "esi.character-assets.unresolved-structure-names:",
      "esi.corporation-assets.name-unavailable",
      "esi.corporation-assets.divisions:",
    ]
    if sourced.state == .partial,
      sourced.value != nil,
      !sourced.diagnostics.isEmpty,
      sourced.diagnostics.allSatisfy({ diagnostic in
        presentationOnlyPrefixes.contains { diagnostic.hasPrefix($0) }
      })
    {
      return .fresh
    }
    return sourced.state
  }

  private static func unpricedTypes(
    ids: Set<Int64>,
    typeNames: [Int64: String]
  ) -> [DashboardWealthUnpricedType] {
    ids.map {
      DashboardWealthUnpricedType(
        typeID: $0,
        name: typeNames[$0] ?? "Unknown EVE type"
      )
    }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private static func freshnessRank(_ state: DataFreshness) -> Int {
    switch state {
    case .fresh: 4
    case .partial: 3
    case .stale: 2
    case .forbidden: 1
    case .unavailable: 0
    }
  }

  private static func valuedComponentFreshness(
    values: [Double?],
    states: [DataFreshness],
    hasIncompleteValuation: Bool
  ) -> DataFreshness {
    guard values.contains(where: { $0 != nil }) else {
      return combinedFreshness(states)
    }
    return adjustedFreshness(
      combinedFreshness(states),
      incomplete: hasIncompleteValuation
    )
  }

  private static func adjustedFreshness(
    _ freshness: DataFreshness,
    incomplete: Bool
  ) -> DataFreshness {
    guard incomplete, freshness == .fresh else { return freshness }
    return .partial
  }

  private static func componentTotal(_ values: [Double?]) -> Double? {
    let included = values.compactMap { $0 }
    return included.isEmpty ? nil : included.reduce(0, +)
  }

  private static func combinedFreshness(
    _ states: [DataFreshness]
  ) -> DataFreshness {
    guard !states.isEmpty else { return .unavailable }
    if states.allSatisfy({ $0 == .forbidden }) { return .forbidden }
    if states.allSatisfy({
      $0 == .forbidden || $0 == .unavailable
    }) {
      return .unavailable
    }
    if states.contains(where: {
      $0 == .partial || $0 == .forbidden || $0 == .unavailable
    }) {
      return .partial
    }
    if states.contains(.stale) { return .stale }
    return .fresh
  }

  private static func usableValue<Value: Codable & Sendable>(
    _ sourced: Sourced<Value>
  ) -> Value? {
    guard [.fresh, .partial, .stale].contains(sourced.state) else {
      return nil
    }
    return sourced.value
  }
}

public enum MarketOrderSide: String, Codable, Sendable {
  case buy
  case sell
}

public enum MarketTradeHub: String, CaseIterable, Codable, Identifiable,
  Sendable
{
  case jita
  case amarr
  case dodixie
  case rens
  case hek

  public var id: String { rawValue }

  /// The built-in choices shown when a Main Hub is configured. Dodixie is
  /// retained as a known market for migrated profiles and can be added via ESI.
  public static let defaultMainHubChoices: [MarketTradeHub] = [
    .jita, .amarr, .rens, .hek,
  ]

  public var name: String {
    switch self {
    case .jita: "Jita IV - Moon 4 - Caldari Navy Assembly Plant"
    case .amarr: "Amarr VIII (Oris) - Emperor Family Academy"
    case .dodixie: "Dodixie IX - Moon 20 - Federation Navy Assembly Plant"
    case .rens: "Rens VI - Moon 8 - Brutor Tribe Treasury"
    case .hek: "Hek VIII - Moon 12 - Boundless Creation Factory"
    }
  }

  public var regionID: Int64 {
    switch self {
    case .jita: 10_000_002
    case .amarr: 10_000_043
    case .dodixie: 10_000_032
    case .rens: 10_000_030
    case .hek: 10_000_042
    }
  }

  public var systemID: Int64 {
    switch self {
    case .jita: 30_000_142
    case .amarr: 30_002_187
    case .dodixie: 30_002_659
    case .rens: 30_002_510
    case .hek: 30_002_053
    }
  }

  public var stationID: Int64 {
    switch self {
    case .jita: 60_003_760
    case .amarr: 60_008_494
    case .dodixie: 60_011_866
    case .rens: 60_004_588
    case .hek: 60_005_686
    }
  }

  public static func matching(stationID: Int64) -> MarketTradeHub? {
    allCases.first { $0.stationID == stationID }
  }

  public var procurementLocation: ProcurementLocation {
    ProcurementLocation.standardTradeHubs.first {
      $0.locationID == stationID
    } ?? .jita
  }
}

public enum MarketHubRole: String, CaseIterable, Codable, Hashable, Sendable {
  case main
  case home
  case coalition
  case comparison
}

public struct MarketHubConfigurationSnapshot: Identifiable, Codable,
  Equatable, Sendable
{
  public let id: UUID
  public let location: ProcurementLocation
  public let roles: Set<MarketHubRole>

  public init(
    id: UUID,
    location: ProcurementLocation,
    roles: Set<MarketHubRole>
  ) {
    self.id = id
    self.location = location
    self.roles = roles
  }
}

public enum MaterialPurchaseCatalogKind: String, Codable, CaseIterable,
  Sendable
{
  case moonMaterials = "Moon Materials"
  case minerals = "Mineral"

  public var missingCatalogDiagnostic: String {
    switch self {
    case .moonMaterials: "missing-moon-materials"
    case .minerals: "missing-minerals"
    }
  }

  /// Restricts the SDE group to the types that matter for regular trading. The SDE group
  /// Mineral also contains rare event and special minerals (for example Crystalline Kangite,
  /// Eleutrium or Chromodynamic Tricarboxyls) that play no role in normal production
  /// (owner decision 2026-10-19). `nil` keeps the complete published group.
  public var includedTypeIDs: Set<Int64>? {
    switch self {
    case .moonMaterials: nil
    case .minerals: Self.standardMineralTypeIDs
    }
  }

  /// Tritanium, Pyerite, Mexallon, Isogen, Nocxium, Zydrine, Megacyte and Morphite.
  public static let standardMineralTypeIDs: Set<Int64> = [
    34, 35, 36, 37, 38, 39, 40, 11_399,
  ]
}

public struct MaterialPurchaseItem: Identifiable, Codable, Equatable,
  Sendable
{
  public let id: Int64
  public let name: String

  public init(id: Int64, name: String) {
    self.id = id
    self.name = name
  }
}

public struct MaterialPurchaseCatalogSnapshot: Codable, Sendable {
  public let materials: [MaterialPurchaseItem]
  public let source: SourceIdentity

  public init(materials: [MaterialPurchaseItem], source: SourceIdentity) {
    self.materials = materials
    self.source = source
  }
}

public protocol MaterialPurchaseCatalogQuerying: Sendable {
  func materialPurchaseCatalog(
    for kind: MaterialPurchaseCatalogKind
  ) async throws -> MaterialPurchaseCatalogSnapshot
}

public protocol MoonMaterialCatalogQuerying: Sendable {
  func moonMaterials() async throws -> MoonMaterialCatalogSnapshot
}

public protocol MineralMaterialCatalogQuerying: Sendable {
  func minerals() async throws -> MaterialPurchaseCatalogSnapshot
}

public struct MaterialPurchasePriceBand: Codable, Equatable, Sendable {
  public let lowestSellPrice: Double
  public let maximumBandPrice: Double
  public let availableQuantity: Int64
  public let orderCount: Int

  public init(
    lowestSellPrice: Double,
    maximumBandPrice: Double,
    availableQuantity: Int64,
    orderCount: Int
  ) {
    self.lowestSellPrice = lowestSellPrice
    self.maximumBandPrice = maximumBandPrice
    self.availableQuantity = availableQuantity
    self.orderCount = orderCount
  }
}

public enum MaterialPurchaseMarketPriceRank: Int, Codable, Equatable,
  Sendable
{
  case cheapest = 1
  case secondCheapest = 2
  case thirdCheapest = 3
}

public struct MaterialPurchaseAnalysisSnapshot: Codable, Sendable {
  public let materialCatalog: MaterialPurchaseCatalogSnapshot
  public let configuredHubs: [MarketHubConfigurationSnapshot]
  public let configuredMarkets: [UUID: Sourced<MarketOrderSnapshot>]
  public let refreshedAt: Date

  public init(
    materialCatalog: MaterialPurchaseCatalogSnapshot,
    configuredHubs: [MarketHubConfigurationSnapshot] = [],
    configuredMarkets: [UUID: Sourced<MarketOrderSnapshot>] = [:],
    refreshedAt: Date
  ) {
    self.materialCatalog = materialCatalog
    self.configuredHubs = configuredHubs
    self.configuredMarkets = configuredMarkets
    self.refreshedAt = refreshedAt
  }
}

public struct MaterialPurchaseRecommendation: Identifiable, Equatable, Sendable {
  public let material: MaterialPurchaseItem
  public let location: ProcurementLocation?
  public let unitPrice: Double?
  public let hasCompleteMarketCoverage: Bool
  public var id: Int64 { material.id }
}

public enum MaterialPurchaseRecommendationProjector {
  public static func project(
    _ analysis: MaterialPurchaseAnalysisSnapshot
  ) -> [MaterialPurchaseRecommendation] {
    let freshMarkets = analysis.configuredHubs.compactMap { hub -> (ProcurementLocation, MarketOrderSnapshot)? in
      guard let sourced = analysis.configuredMarkets[hub.id],
        sourced.state == .fresh, let market = sourced.value,
        market.state == .fresh, market.locationID == hub.location.locationID
      else { return nil }
      return (hub.location, market)
    }
    let complete = !analysis.configuredHubs.isEmpty
      && freshMarkets.count == analysis.configuredHubs.count
    return analysis.materialCatalog.materials.map { material in
      var best: (location: ProcurementLocation, price: Double)?
      for (location, market) in freshMarkets {
        guard let band = MaterialPurchasePriceBandAnalyzer.analyze(
          typeID: material.id, snapshot: market
        ) else { continue }
        if best == nil || band.lowestSellPrice < best!.price {
          best = (location, band.lowestSellPrice)
        }
      }
      return MaterialPurchaseRecommendation(
        material: material, location: best?.location, unitPrice: best?.price,
        hasCompleteMarketCoverage: complete
      )
    }.sorted {
      let order = $0.material.name.localizedCaseInsensitiveCompare($1.material.name)
      return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
    }
  }
}

/// Rarity class of the 20 raw Moon materials (R4 to R64), keyed by SDE type ID.
/// The SDE group `Moon Materials` carries no class attribute, so the mapping is fixed.
public enum MoonMaterialRarityClass: Int, CaseIterable, Comparable, Sendable {
  case r4 = 4, r8 = 8, r16 = 16, r32 = 32, r64 = 64

  public var title: String { "R\(rawValue)" }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  private static let classByTypeID: [Int64: MoonMaterialRarityClass] = [
    16633: .r4, 16634: .r4, 16635: .r4, 16636: .r4,
    16637: .r8, 16638: .r8, 16639: .r8, 16640: .r8,
    16641: .r16, 16642: .r16, 16643: .r16, 16644: .r16,
    16646: .r32, 16647: .r32, 16648: .r32, 16649: .r32,
    16650: .r64, 16651: .r64, 16652: .r64, 16653: .r64,
  ]

  public static func of(typeID: Int64) -> MoonMaterialRarityClass? {
    classByTypeID[typeID]
  }
}

public struct MoonMaterialRecommendationGroup: Identifiable, Equatable, Sendable {
  /// `nil` collects materials without a known class; such a group is placed last.
  public let rarity: MoonMaterialRarityClass?
  public let recommendations: [MaterialPurchaseRecommendation]
  public var id: Int { rarity?.rawValue ?? Int.max }

  /// Groups recommendations by rarity class in ascending order and keeps the
  /// incoming (alphabetical) order inside each class.
  public static func group(
    _ recommendations: [MaterialPurchaseRecommendation]
  ) -> [MoonMaterialRecommendationGroup] {
    let grouped = Dictionary(grouping: recommendations) {
      MoonMaterialRarityClass.of(typeID: $0.material.id)
    }
    let known = MoonMaterialRarityClass.allCases.compactMap { rarity in
      grouped[rarity].map { MoonMaterialRecommendationGroup(rarity: rarity, recommendations: $0) }
    }
    let unknown = grouped[nil].map { [MoonMaterialRecommendationGroup(rarity: nil, recommendations: $0)] } ?? []
    return known + unknown
  }
}

public typealias MoonMaterial = MaterialPurchaseItem
public typealias MoonMaterialCatalogSnapshot = MaterialPurchaseCatalogSnapshot
public typealias MoonMaterialPriceBand = MaterialPurchasePriceBand
public typealias MoonMaterialMarketPriceRank = MaterialPurchaseMarketPriceRank
public typealias MoonMaterialPurchaseAnalysisSnapshot =
  MaterialPurchaseAnalysisSnapshot

public struct MarketOrder: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let locationID: Int64
  public let systemID: Int64
  public let side: MarketOrderSide
  public let price: Double
  public let volumeRemaining: Int64
  public let minimumVolume: Int64
  public let issued: Date
}

public struct MarketOrderSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let regionID: Int64
  public let locationID: Int64
  public let capturedAt: Date
  public let state: DataFreshness
  public let ordersByType: [Int64: [MarketOrder]]
  public let source: SourceIdentity

  /// The same snapshot identity and provenance, restricted to `typeIDs`.
  public func restricted(to typeIDs: Set<Int64>) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: id,
      regionID: regionID,
      locationID: locationID,
      capturedAt: capturedAt,
      state: state,
      ordersByType: ordersByType.filter { typeIDs.contains($0.key) },
      source: source
    )
  }
}

public struct MarketOrderTypeSummary: Codable, Equatable, Sendable {
  public let bestSellPrice: Double?
  public let bestBuyPrice: Double?
  /// Units remaining across all valid orders at exactly the best price. `nil`
  /// when no such order exists or the summary predates this field.
  public let bestSellVolume: Int64?
  public let bestBuyVolume: Int64?

  public init(
    bestSellPrice: Double?,
    bestBuyPrice: Double?,
    bestSellVolume: Int64? = nil,
    bestBuyVolume: Int64? = nil
  ) {
    self.bestSellPrice = bestSellPrice
    self.bestBuyPrice = bestBuyPrice
    self.bestSellVolume = bestSellVolume
    self.bestBuyVolume = bestBuyVolume
  }
}

/// A compact, long-lived projection of a potentially very large station order
/// book. Full depth remains scoped to the calculation that requested it.
public struct MarketOrderSummarySnapshot: Codable, Sendable {
  public let regionID: Int64
  public let locationID: Int64
  public let capturedAt: Date
  public let state: DataFreshness
  public let pricesByType: [Int64: MarketOrderTypeSummary]
  public let source: SourceIdentity

  public init(snapshot: MarketOrderSnapshot) {
    regionID = snapshot.regionID
    locationID = snapshot.locationID
    capturedAt = snapshot.capturedAt
    state = snapshot.state
    source = snapshot.source
    pricesByType = snapshot.ordersByType.reduce(into: [:]) { result, entry in
      let valid = entry.value.filter {
        $0.locationID == snapshot.locationID
          && $0.price.isFinite
          && $0.price > 0
          && $0.volumeRemaining > 0
          && $0.minimumVolume > 0
      }
      guard !valid.isEmpty else { return }
      let bestSell = valid.lazy.filter { $0.side == .sell }.map(\.price).min()
      let bestBuy = valid.lazy.filter { $0.side == .buy }.map(\.price).max()
      result[entry.key] = MarketOrderTypeSummary(
        bestSellPrice: bestSell,
        bestBuyPrice: bestBuy,
        bestSellVolume: bestSell.flatMap { price in
          Self.volume(in: valid, side: .sell, price: price)
        },
        bestBuyVolume: bestBuy.flatMap { price in
          Self.volume(in: valid, side: .buy, price: price)
        }
      )
    }
  }

  private static func volume(
    in orders: [MarketOrder],
    side: MarketOrderSide,
    price: Double
  ) -> Int64? {
    var total: Int64 = 0
    for order in orders where order.side == side && order.price == price {
      let (sum, overflow) = total.addingReportingOverflow(order.volumeRemaining)
      guard !overflow else { return nil }
      total = sum
    }
    return total > 0 ? total : nil
  }
}

public enum PriceScenario: String, Codable, CaseIterable, Sendable {
  case materialBuy
  case immediateSale
  case listedSale
  case contractSale
}

public struct PriceQuote: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let quantity: Int64
  public let scenario: PriceScenario
  public let total: Double?
  public let weightedUnitPrice: Double?
  public let filledQuantity: Int64
  public let capturedAt: Date
  public let source: SourceIdentity
  public let warnings: [DomainWarning]

  public var isComplete: Bool {
    total != nil && filledQuantity == quantity
  }
}

public struct AdjustedPrice: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let adjustedPrice: Double?
  public let averagePrice: Double?
}

public struct ReferencePriceSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let capturedAt: Date
  public let prices: [Int64: AdjustedPrice]
  public let source: SourceIdentity

  public init(
    id: UUID = UUID(),
    capturedAt: Date,
    prices: [Int64: AdjustedPrice],
    source: SourceIdentity
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.prices = prices
    self.source = source
  }
}

public struct IndustrySystemIndex: Codable, Hashable, Sendable {
  public let solarSystemID: Int64
  public let activity: BlueprintActivityDefinition.Kind
  public let costIndex: Double
}

/// A calculation-scoped projection that validates and sorts each market type
/// once. Quote semantics stay owned by `MarketPriceEngine`; only the repeated
/// order-book preparation is removed from planner hot paths.
public struct PreparedMarketOrderBook: Sendable {
  private let snapshot: MarketOrderSnapshot
  private let sellOrdersByType: [Int64: [MarketOrder]]
  private let buyOrdersByType: [Int64: [MarketOrder]]

  public init(snapshot: MarketOrderSnapshot) {
    self.snapshot = snapshot
    var sells: [Int64: [MarketOrder]] = [:]
    var buys: [Int64: [MarketOrder]] = [:]
    sells.reserveCapacity(snapshot.ordersByType.count)
    buys.reserveCapacity(snapshot.ordersByType.count)
    for (typeID, orders) in snapshot.ordersByType {
      let relevant = orders.filter {
        $0.locationID == snapshot.locationID
          && $0.price.isFinite
          && $0.price > 0
          && $0.volumeRemaining > 0
          && $0.minimumVolume > 0
      }
      let sellOrders = relevant.filter { $0.side == .sell }
        .sorted { $0.price < $1.price }
      let buyOrders = relevant.filter { $0.side == .buy }
        .sorted { $0.price > $1.price }
      if !sellOrders.isEmpty {
        sells[typeID] = sellOrders
      }
      if !buyOrders.isEmpty {
        buys[typeID] = buyOrders
      }
    }
    sellOrdersByType = sells
    buyOrdersByType = buys
  }

  public func quote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil
  ) -> PriceQuote {
    let orders =
      switch scenario {
      case .materialBuy, .listedSale, .contractSale:
        sellOrdersByType[typeID] ?? []
      case .immediateSale:
        buyOrdersByType[typeID] ?? []
      }
    return MarketPriceEngine.quote(
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      snapshot: snapshot,
      sortedOrders: orders,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate
    )
  }
}

public enum MarketPriceEngine {
  public static func quote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    snapshot: MarketOrderSnapshot,
    salesTaxRate: Double? = nil,
    brokerFeeRate: Double? = nil
  ) -> PriceQuote {
    let sorted = sortedOrders(
      typeID: typeID,
      scenario: scenario,
      snapshot: snapshot
    )
    return quote(
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      snapshot: snapshot,
      sortedOrders: sorted,
      salesTaxRate: salesTaxRate,
      brokerFeeRate: brokerFeeRate
    )
  }

  /// Usable orders of one type in the order a quote fills them. Callers that
  /// quote the same type repeatedly prepare this once.
  static func sortedOrders(
    typeID: Int64,
    scenario: PriceScenario,
    snapshot: MarketOrderSnapshot
  ) -> [MarketOrder] {
    let relevant = (snapshot.ordersByType[typeID] ?? []).filter {
      $0.locationID == snapshot.locationID
        && $0.price.isFinite
        && $0.price > 0
        && $0.volumeRemaining > 0
        && $0.minimumVolume > 0
    }
    switch scenario {
    case .materialBuy, .listedSale, .contractSale:
      return relevant.filter { $0.side == .sell }
        .sorted { $0.price < $1.price }
    case .immediateSale:
      return relevant.filter { $0.side == .buy }
        .sorted { $0.price > $1.price }
    }
  }

  static func quote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    snapshot: MarketOrderSnapshot,
    sortedOrders: [MarketOrder],
    salesTaxRate: Double?,
    brokerFeeRate: Double?
  ) -> PriceQuote {
    let source = snapshot.source
    guard quantity > 0 else {
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: 0,
        weightedUnitPrice: 0,
        filledQuantity: 0,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: []
      )
    }

    guard !sortedOrders.isEmpty else {
      return missingQuote(
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        source: source,
        capturedAt: snapshot.capturedAt,
        code: "market.no-orders"
      )
    }

    if scenario == .listedSale {
      guard let salesTaxRate, let brokerFeeRate,
        salesTaxRate.isFinite,
        brokerFeeRate.isFinite,
        salesTaxRate >= 0,
        brokerFeeRate >= 0,
        salesTaxRate + brokerFeeRate < 1
      else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.missing-sales-fees"
        )
      }
      let price = sortedOrders[0].price
      let gross = price * Double(quantity)
      let net = gross * (1 - salesTaxRate - brokerFeeRate)
      guard gross.isFinite, net.isFinite else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.invalid-price"
        )
      }
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: net,
        weightedUnitPrice: net / Double(quantity),
        filledQuantity: quantity,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: []
      )
    }

    if scenario == .contractSale {
      return missingQuote(
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        source: source,
        capturedAt: snapshot.capturedAt,
        code: "market.contract-sale-requires-public-contracts"
      )
    }

    var remaining = quantity
    var filled: Int64 = 0
    var total = 0.0
    for order in sortedOrders where remaining > 0 {
      if order.minimumVolume > 1,
        remaining < order.minimumVolume
      {
        continue
      }
      let take = min(remaining, order.volumeRemaining)
      guard take > 0 else { continue }
      total += Double(take) * order.price
      guard total.isFinite else {
        return missingQuote(
          typeID: typeID,
          quantity: quantity,
          scenario: scenario,
          source: source,
          capturedAt: snapshot.capturedAt,
          code: "market.invalid-price"
        )
      }
      remaining -= take
      filled += take
    }

    guard remaining == 0 else {
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: nil,
        weightedUnitPrice: nil,
        filledQuantity: filled,
        capturedAt: snapshot.capturedAt,
        source: source,
        warnings: [
          DomainWarning(
            code: "market.insufficient-depth",
            message:
              "Only \(filled) of \(quantity) units are available at the selected trade hub.",
            severity: .blocking,
            source: source
          )
        ]
      )
    }

    return PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: total,
      weightedUnitPrice: total / Double(quantity),
      filledQuantity: filled,
      capturedAt: snapshot.capturedAt,
      source: source,
      warnings: []
    )
  }

  private static func missingQuote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario,
    source: SourceIdentity,
    capturedAt: Date,
    code: String
  ) -> PriceQuote {
    PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: nil,
      weightedUnitPrice: nil,
      filledQuantity: 0,
      capturedAt: capturedAt,
      source: source,
      warnings: [
        DomainWarning(
          code: code,
          message: "No usable market orders are available at the selected trade hub.",
          severity: .blocking,
          source: source
        )
      ]
    )
  }
}

public enum MaterialPurchasePriceBandAnalyzer {
  public static let defaultMarkup = 0.10

  public static func analyze(
    typeID: Int64,
    snapshot: MarketOrderSnapshot,
    markup: Double = defaultMarkup
  ) -> MaterialPurchasePriceBand? {
    guard markup.isFinite, markup >= 0 else { return nil }
    let sellOrders = (snapshot.ordersByType[typeID] ?? []).filter {
      $0.locationID == snapshot.locationID
        && $0.side == .sell
        && $0.price.isFinite
        && $0.price > 0
        && $0.volumeRemaining > 0
        && $0.minimumVolume > 0
    }
    guard let lowestSellPrice = sellOrders.map(\.price).min() else {
      return nil
    }
    let maximumBandPrice = lowestSellPrice * (1 + markup)
    guard maximumBandPrice.isFinite else { return nil }
    let eligibleOrders = sellOrders.filter {
      $0.price <= maximumBandPrice
    }
    var availableQuantity: Int64 = 0
    for order in eligibleOrders {
      let (sum, overflow) = availableQuantity.addingReportingOverflow(
        order.volumeRemaining
      )
      availableQuantity = overflow ? .max : sum
    }
    return MaterialPurchasePriceBand(
      lowestSellPrice: lowestSellPrice,
      maximumBandPrice: maximumBandPrice,
      availableQuantity: availableQuantity,
      orderCount: eligibleOrders.count
    )
  }
}

public enum MaterialPurchaseMarketPriceRankAnalyzer {
  public static func ranks<Key: Hashable>(
    typeID: Int64,
    markets: [Key: Sourced<MarketOrderSnapshot>]
  ) -> [Key: MaterialPurchaseMarketPriceRank] {
    let observations: [(location: Key, price: Double)] = markets.compactMap {
      entry in
      let (location, sourced) = entry
      guard sourced.state == .fresh,
        let snapshot = sourced.value,
        let band = MaterialPurchasePriceBandAnalyzer.analyze(
          typeID: typeID,
          snapshot: snapshot
        )
      else { return nil }
      return (location: location, price: band.lowestSellPrice)
    }
    let rankedPrices = observations.map(\.price).sorted().reduce(
      into: [Double]()
    ) { distinctPrices, price in
      guard distinctPrices.last != price else { return }
      distinctPrices.append(price)
    }
    .prefix(3)

    var result: [Key: MaterialPurchaseMarketPriceRank] = [:]
    for observation in observations {
      guard let index = rankedPrices.firstIndex(of: observation.price),
        let rank = MaterialPurchaseMarketPriceRank(rawValue: index + 1)
      else { continue }
      result[observation.location] = rank
    }
    return result
  }
}

public typealias MoonMaterialPriceBandAnalyzer =
  MaterialPurchasePriceBandAnalyzer
public typealias MoonMaterialMarketPriceRankAnalyzer =
  MaterialPurchaseMarketPriceRankAnalyzer

public typealias JitaPriceEngine = MarketPriceEngine

/// Blueprint valuation inputs for the net-worth projection.
///
/// Originals (BPO) use the current replacement estimate of the Blueprints
/// screen: SDE base price plus the research cost to the current ME/TE level.
/// Copies (BPC) use the lowest price per run of attributable public BPC
/// Contracts for the same blueprint type multiplied by the remaining runs.
public struct DashboardWealthBlueprintValuation: Sendable {
  public struct OriginalValue: Equatable, Sendable {
    public let value: Double
    /// `true` when the research share could not be priced and only the SDE
    /// base price (a factual lower bound) is available.
    public let isLowerBound: Bool

    public init(value: Double, isLowerBound: Bool) {
      self.value = value
      self.isLowerBound = isLowerBound
    }
  }

  /// Personal originals keyed by ESI item ID.
  public let originalValuesByItemID: [Int64: OriginalValue]
  /// Unresearched replacement value (SDE base price) keyed by blueprint type.
  /// Used for originals without an ESI blueprint record, for example packaged
  /// stacks or corporation assets.
  public let originalBaseValuesByTypeID: [Int64: Double]
  /// Lowest public Contract price per run keyed by blueprint type.
  public let copyRunPricesByTypeID: [Int64: Double]

  public init(
    originalValuesByItemID: [Int64: OriginalValue] = [:],
    originalBaseValuesByTypeID: [Int64: Double] = [:],
    copyRunPricesByTypeID: [Int64: Double] = [:]
  ) {
    self.originalValuesByItemID = originalValuesByItemID
    self.originalBaseValuesByTypeID = originalBaseValuesByTypeID
    self.copyRunPricesByTypeID = copyRunPricesByTypeID
  }

  public static let empty = DashboardWealthBlueprintValuation()
}

public enum DashboardBlueprintValuationBuilder {
  public static func build(
    inputs: [DashboardWealthCharacterInput],
    definitions: [Int64: BlueprintResearchDefinition],
    pricing: BlueprintResearchPricingInput,
    copyOffers: [Int64: [PublicContractSearchResult]] = [:]
  ) -> DashboardWealthBlueprintValuation {
    var originals: [Int64: DashboardWealthBlueprintValuation.OriginalValue] = [:]
    for input in inputs {
      guard let sourced = input.blueprints,
        [.fresh, .partial, .stale].contains(sourced.state),
        let instances = sourced.value
      else { continue }
      for instance in instances where instance.kind == .original {
        guard let definition = definitions[instance.blueprintTypeID],
          let value = originalValue(
            instance: instance,
            definition: definition,
            pricing: pricing
          )
        else { continue }
        originals[instance.id] = value
      }
    }
    var baseValues: [Int64: Double] = [:]
    for (typeID, definition) in definitions {
      guard let basePrice = definition.basePrice,
        basePrice.isFinite, basePrice >= 0
      else { continue }
      baseValues[typeID] = basePrice
    }
    var runPrices: [Int64: Double] = [:]
    for (typeID, offers) in copyOffers {
      if let price = lowestCopyRunPrice(offers.filter { $0.typeID == typeID }) {
        runPrices[typeID] = price
      }
    }
    return DashboardWealthBlueprintValuation(
      originalValuesByItemID: originals,
      originalBaseValuesByTypeID: baseValues,
      copyRunPricesByTypeID: runPrices
    )
  }

  public static func originalValue(
    instance: OwnedBlueprintInstance,
    definition: BlueprintResearchDefinition,
    pricing: BlueprintResearchPricingInput
  ) -> DashboardWealthBlueprintValuation.OriginalValue? {
    let quote = BlueprintResearchCostCalculator.quote(
      instance: instance,
      definition: definition,
      pricing: pricing
    )
    if let value = quote.estimatedReplacementValue, value.isFinite, value >= 0 {
      return .init(value: value, isLowerBound: false)
    }
    guard let basePrice = definition.basePrice,
      basePrice.isFinite, basePrice >= 0
    else { return nil }
    return .init(value: basePrice, isLowerBound: true)
  }

  /// Lowest price per run among attributable single-BPC item-exchange offers.
  public static func lowestCopyRunPrice(
    _ offers: [PublicContractSearchResult]
  ) -> Double? {
    offers.compactMap { offer -> Double? in
      guard offer.isAttributableBlueprintOffer,
        offer.isBlueprintCopy == true,
        let runs = offer.runs, runs > 0,
        let price = offer.effectiveContractPrice
      else { return nil }
      let perRun = price / Double(runs)
      return perRun.isFinite && perRun > 0 ? perRun : nil
    }.min()
  }
}

/// Resolves a unit value for industry inputs that have no ESI reference price
/// by recursively valuing their own SDE production inputs.
public enum DashboardRecursiveMaterialValuator {
  public static let maximumDepth = 4

  public static func unitValues(
    for typeIDs: Set<Int64>,
    prices: [Int64: AdjustedPrice],
    definitionsByProductTypeID: [Int64: BlueprintDefinition]
  ) -> [Int64: Double] {
    var memo: [Int64: Double?] = [:]
    var result: [Int64: Double] = [:]
    for typeID in typeIDs.sorted() {
      var visiting = Set<Int64>()
      if let value = unitValue(
        typeID: typeID,
        depth: 0,
        prices: prices,
        definitions: definitionsByProductTypeID,
        memo: &memo,
        visiting: &visiting
      ) {
        result[typeID] = value
      }
    }
    return result
  }

  private static func unitValue(
    typeID: Int64,
    depth: Int,
    prices: [Int64: AdjustedPrice],
    definitions: [Int64: BlueprintDefinition],
    memo: inout [Int64: Double?],
    visiting: inout Set<Int64>
  ) -> Double? {
    if let reference = prices[typeID],
      let price = reference.averagePrice ?? reference.adjustedPrice,
      price.isFinite, price >= 0
    {
      return price
    }
    if let cached = memo[typeID] { return cached }
    guard depth < maximumDepth,
      !visiting.contains(typeID),
      let definition = definitions[typeID],
      !definition.activity.materials.isEmpty,
      let output = definition.activity.products.first(where: {
        $0.typeID == typeID
      })?.quantity ?? definition.activity.products.first?.quantity,
      output > 0
    else {
      memo[typeID] = .some(nil)
      return nil
    }
    visiting.insert(typeID)
    defer { visiting.remove(typeID) }
    var total = 0.0
    for material in definition.activity.materials {
      guard material.quantity > 0,
        let unit = unitValue(
          typeID: material.typeID,
          depth: depth + 1,
          prices: prices,
          definitions: definitions,
          memo: &memo,
          visiting: &visiting
        )
      else {
        memo[typeID] = .some(nil)
        return nil
      }
      total += unit * Double(material.quantity)
    }
    let value = total / Double(output)
    let accepted = value.isFinite && value >= 0 ? value : nil
    memo[typeID] = .some(accepted)
    return accepted
  }
}
