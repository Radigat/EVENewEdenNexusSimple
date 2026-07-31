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
  private var classificationsByProductID: [Int64: CacheEntry<IndustryItemClassification>] = [:]
  private var packagedVolumesByTypeID: [Int64: CacheEntry<Double>] = [:]

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

  public func packagedVolume(typeID: Int64) async throws -> Double? {
    if case .value(let value) = packagedVolumesByTypeID[typeID] {
      return value
    }
    let value = try await base.packagedVolume(typeID: typeID)
    packagedVolumesByTypeID[typeID] = .value(value)
    return value
  }
}
