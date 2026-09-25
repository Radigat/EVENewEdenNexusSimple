import Foundation

/// Composes immutable public-ESI packaged volumes with the static industry
/// catalog without allowing assembled SDE volumes to masquerade as cargo.
public struct PackagedVolumeSnapshotCatalog: IndustryCatalogQuerying {
  private let base: any IndustryCatalogQuerying
  private let packagedVolumes: [Int64: Double]

  public init(
    base: any IndustryCatalogQuerying,
    packagedVolumes: [Int64: Double]
  ) {
    self.base = base
    self.packagedVolumes = packagedVolumes
  }

  public func typeID(named name: String) async throws -> Int64? {
    try await base.typeID(named: name)
  }

  public func typeName(id: Int64) async throws -> String? {
    try await base.typeName(id: id)
  }

  public func typeNames(ids: Set<Int64>) async throws -> [Int64: String] {
    try await base.typeNames(ids: ids)
  }

  public func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    try await base.productionDefinition(productTypeID: productTypeID)
  }

  public func blueprintScienceActivities(blueprintTypeID: Int64) async throws
    -> [BlueprintScienceActivityDefinition]
  {
    try await base.blueprintScienceActivities(blueprintTypeID: blueprintTypeID)
  }

  public func decryptorDefinitions() async throws
    -> [BlueprintDecryptorDefinition]
  {
    try await base.decryptorDefinitions()
  }

  public func manufacturingDefinitions() async throws
    -> [BlueprintDefinition]
  {
    try await base.manufacturingDefinitions()
  }

  public func reactionDefinitions() async throws -> [BlueprintDefinition] {
    try await base.reactionDefinitions()
  }

  public func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    try await base.industryClassification(productTypeID: productTypeID)
  }

  public func industryClassifications(typeIDs: Set<Int64>) async throws
    -> [Int64: IndustryItemClassification]
  {
    try await base.industryClassifications(typeIDs: typeIDs)
  }

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    if let volume = packagedVolumes[typeID],
      volume.isFinite,
      volume >= 0
    {
      return volume
    }
    return try await base.packagedVolume(typeID: typeID)
  }

  public func packagedVolumes(typeIDs: Set<Int64>) async throws
    -> [Int64: Double]
  {
    var result: [Int64: Double] = [:]
    var unresolved = Set<Int64>()
    result.reserveCapacity(typeIDs.count)
    unresolved.reserveCapacity(typeIDs.count)
    for typeID in typeIDs {
      if let volume = packagedVolumes[typeID],
        volume.isFinite,
        volume >= 0
      {
        result[typeID] = volume
      } else {
        unresolved.insert(typeID)
      }
    }
    if !unresolved.isEmpty {
      result.merge(
        try await base.packagedVolumes(typeIDs: unresolved),
        uniquingKeysWith: { snapshot, _ in snapshot }
      )
    }
    return result
  }

  public func compressedOreOptions(
    producing materialTypeIDs: Set<Int64>
  ) async throws -> [CompressedOreOption] {
    try await base.compressedOreOptions(producing: materialTypeIDs).map {
      option in
      let snapshotVolume = packagedVolumes[option.typeID]
      let effectiveVolume =
        snapshotVolume?.isFinite == true && (snapshotVolume ?? -1) >= 0
        ? snapshotVolume
        : option.packagedVolume
      return CompressedOreOption(
        typeID: option.typeID,
        name: option.name,
        portionSize: option.portionSize,
        packagedVolume: effectiveVolume,
        reprocessingSkillTypeID: option.reprocessingSkillTypeID,
        kind: option.kind,
        outputs: option.outputs,
        source: option.source
      )
    }
  }
}
