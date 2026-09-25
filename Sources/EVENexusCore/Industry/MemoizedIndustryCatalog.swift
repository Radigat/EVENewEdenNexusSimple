import Foundation

/// A calculation-scoped catalog view that avoids repeating identical SDE
/// lookups while an industry plan is being discovered and calculated.
public actor MemoizedIndustryCatalog: IndustryCatalogQuerying {
  private enum CacheEntry<Value: Sendable>: Sendable {
    case value(Value?)
  }

  private let base: any IndustryCatalogQuerying
  private var typeIDsByName: [String: CacheEntry<Int64>] = [:]
  private var typeNamesByID: [Int64: CacheEntry<String>] = [:]
  private var definitionsByProductID: [Int64: CacheEntry<BlueprintDefinition>] = [:]
  private var scienceActivitiesByBlueprintID: [Int64: [BlueprintScienceActivityDefinition]] = [:]
  private var cachedDecryptors: [BlueprintDecryptorDefinition]?
  private var classificationsByProductID: [Int64: CacheEntry<IndustryItemClassification>] = [:]
  private var packagedVolumesByTypeID: [Int64: CacheEntry<Double>] = [:]
  private var compressedOreOptionsByMineralIDs: [Set<Int64>: [CompressedOreOption]] = [:]

  public init(base: any IndustryCatalogQuerying) {
    self.base = base
  }

  public func typeID(named name: String) async throws -> Int64? {
    if case .value(let value) = typeIDsByName[name] {
      return value
    }
    let value = try await base.typeID(named: name)
    typeIDsByName[name] = .value(value)
    return value
  }

  public func typeName(id: Int64) async throws -> String? {
    if case .value(let value) = typeNamesByID[id] {
      return value
    }
    let value = try await base.typeName(id: id)
    typeNamesByID[id] = .value(value)
    return value
  }

  public func typeNames(ids: Set<Int64>) async throws -> [Int64: String] {
    var result: [Int64: String] = [:]
    var missing = Set<Int64>()
    result.reserveCapacity(ids.count)
    missing.reserveCapacity(ids.count)
    for typeID in ids {
      if case .value(let value) = typeNamesByID[typeID] {
        if let value { result[typeID] = value }
      } else {
        missing.insert(typeID)
      }
    }
    guard !missing.isEmpty else { return result }
    let loaded = try await base.typeNames(ids: missing)
    for typeID in missing {
      let value = loaded[typeID]
      typeNamesByID[typeID] = .value(value)
      if let value { result[typeID] = value }
    }
    return result
  }

  public func productionDefinition(productTypeID: Int64) async throws
    -> BlueprintDefinition?
  {
    if case .value(let value) = definitionsByProductID[productTypeID] {
      return value
    }
    let value = try await base.productionDefinition(
      productTypeID: productTypeID
    )
    definitionsByProductID[productTypeID] = .value(value)
    return value
  }

  public func blueprintScienceActivities(blueprintTypeID: Int64) async throws
    -> [BlueprintScienceActivityDefinition]
  {
    if let value = scienceActivitiesByBlueprintID[blueprintTypeID] {
      return value
    }
    let value = try await base.blueprintScienceActivities(
      blueprintTypeID: blueprintTypeID
    )
    scienceActivitiesByBlueprintID[blueprintTypeID] = value
    return value
  }

  public func decryptorDefinitions() async throws
    -> [BlueprintDecryptorDefinition]
  {
    if let cachedDecryptors { return cachedDecryptors }
    let value = try await base.decryptorDefinitions()
    cachedDecryptors = value
    return value
  }

  public func industryClassification(productTypeID: Int64) async throws
    -> IndustryItemClassification?
  {
    if case .value(let value) = classificationsByProductID[productTypeID] {
      return value
    }
    let value = try await base.industryClassification(
      productTypeID: productTypeID
    )
    classificationsByProductID[productTypeID] = .value(value)
    return value
  }

  public func industryClassifications(typeIDs: Set<Int64>) async throws
    -> [Int64: IndustryItemClassification]
  {
    var result: [Int64: IndustryItemClassification] = [:]
    var missing = Set<Int64>()
    result.reserveCapacity(typeIDs.count)
    missing.reserveCapacity(typeIDs.count)
    for typeID in typeIDs {
      if case .value(let value) = classificationsByProductID[typeID] {
        if let value { result[typeID] = value }
      } else {
        missing.insert(typeID)
      }
    }
    guard !missing.isEmpty else { return result }
    let loaded = try await base.industryClassifications(typeIDs: missing)
    for typeID in missing {
      let value = loaded[typeID]
      classificationsByProductID[typeID] = .value(value)
      if let value { result[typeID] = value }
    }
    return result
  }

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    if case .value(let value) = packagedVolumesByTypeID[typeID] {
      return value
    }
    let value = try await base.packagedVolume(typeID: typeID)
    packagedVolumesByTypeID[typeID] = .value(value)
    return value
  }

  public func packagedVolumes(typeIDs: Set<Int64>) async throws
    -> [Int64: Double]
  {
    var result: [Int64: Double] = [:]
    var missing = Set<Int64>()
    result.reserveCapacity(typeIDs.count)
    missing.reserveCapacity(typeIDs.count)
    for typeID in typeIDs {
      if case .value(let value) = packagedVolumesByTypeID[typeID] {
        if let value { result[typeID] = value }
      } else {
        missing.insert(typeID)
      }
    }
    guard !missing.isEmpty else { return result }
    let loaded = try await base.packagedVolumes(typeIDs: missing)
    for typeID in missing {
      let value = loaded[typeID]
      packagedVolumesByTypeID[typeID] = .value(value)
      if let value { result[typeID] = value }
    }
    return result
  }

  public func compressedOreOptions(
    producing materialTypeIDs: Set<Int64>
  ) async throws -> [CompressedOreOption] {
    if let value = compressedOreOptionsByMineralIDs[materialTypeIDs] {
      return value
    }
    let value = try await base.compressedOreOptions(
      producing: materialTypeIDs
    )
    compressedOreOptionsByMineralIDs[materialTypeIDs] = value
    return value
  }
}
