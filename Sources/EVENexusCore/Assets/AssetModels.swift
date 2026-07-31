import Foundation

public enum AssetLocationKind: String, Codable, Sendable {
  public static let minimumPlayerStructureID: Int64 = 1_000_000_000_000

  case station
  case structure
  case solarSystem
  case item
  case unresolved

  public init(esiValue: String) {
    switch esiValue {
    case "station": self = .station
    case "other", "structure": self = .structure
    case "solar_system": self = .solarSystem
    case "item": self = .item
    default: self = .unresolved
    }
  }

  public init(esiValue: String, locationID: Int64) {
    if esiValue == "other"
      || (esiValue == "station"
        && locationID >= Self.minimumPlayerStructureID)
    {
      self = .structure
    } else {
      self.init(esiValue: esiValue)
    }
  }
}

public struct AssetItem: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let quantity: Int64
  public let locationID: Int64
  public let locationKind: AssetLocationKind
  public let locationFlag: String
  public let singleton: Bool

  public init(
    id: Int64,
    typeID: Int64,
    quantity: Int64,
    locationID: Int64,
    locationKind: AssetLocationKind,
    locationFlag: String,
    singleton: Bool
  ) {
    self.id = id
    self.typeID = typeID
    self.quantity = quantity
    self.locationID = locationID
    self.locationKind = locationKind
    self.locationFlag = locationFlag
    self.singleton = singleton
  }
}

public enum AssetLocationClassifier {
  /// ESI may label an asset located directly in an Upwell structure as
  /// `item`, even though the large location ID is not another asset record.
  /// Such an orphan parent is a structure-location candidate, while a matching
  /// item ID remains an ordinary container.
  public static func structureCandidateIDs(
    in items: [AssetItem]
  ) -> Set<Int64> {
    let itemIDs = Set(items.map(\.id))
    return Set(
      items.compactMap { item in
        if item.locationKind == .structure {
          return item.locationID
        }
        guard item.locationKind == .item,
          item.locationID >= AssetLocationKind.minimumPlayerStructureID,
          !itemIDs.contains(item.locationID)
        else { return nil }
        return item.locationID
      }
    )
  }

  public static func applyingStructureRoots(
    to items: [AssetItem],
    candidateIDs: Set<Int64>
  ) -> [AssetItem] {
    guard !candidateIDs.isEmpty else { return items }
    return items.map { item in
      guard item.locationKind == .item,
        candidateIDs.contains(item.locationID)
      else { return item }
      return AssetItem(
        id: item.id,
        typeID: item.typeID,
        quantity: item.quantity,
        locationID: item.locationID,
        locationKind: .structure,
        locationFlag: item.locationFlag,
        singleton: item.singleton
      )
    }
  }
}

public struct AssetRootLocation: Codable, Hashable, Sendable {
  public let id: Int64
  public let kind: AssetLocationKind

  public init(id: Int64, kind: AssetLocationKind) {
    self.id = id
    self.kind = kind
  }
}

private enum CachedAssetRootLocation {
  case resolved(AssetRootLocation)
  case unresolved

  var value: AssetRootLocation? {
    switch self {
    case .resolved(let location): location
    case .unresolved: nil
    }
  }
}

private struct AssetRootLocationResolver {
  private let itemsByID: [Int64: AssetItem]
  private var cache: [Int64: CachedAssetRootLocation] = [:]

  init(items: [AssetItem]) {
    itemsByID = items.reduce(into: [Int64: AssetItem]()) {
      $0[$1.id] = $0[$1.id] ?? $1
    }
  }

  mutating func rootLocation(for item: AssetItem) -> AssetRootLocation? {
    var locationID = item.locationID
    var kind = item.locationKind
    guard kind == .item else {
      return kind == .unresolved
        ? nil
        : AssetRootLocation(id: locationID, kind: kind)
    }
    if let cached = cache[locationID] {
      return cached.value
    }
    var path: [Int64] = []
    var visited = Set<Int64>()

    while kind == .item {
      if let cached = cache[locationID] {
        cache(cached, for: path)
        return cached.value
      }
      guard visited.insert(locationID).inserted,
        let container = itemsByID[locationID]
      else {
        cache(.unresolved, for: path)
        return nil
      }
      path.append(locationID)
      locationID = container.locationID
      kind = container.locationKind
    }

    let result: CachedAssetRootLocation =
      kind == .unresolved
      ? .unresolved
      : .resolved(AssetRootLocation(id: locationID, kind: kind))
    cache(result, for: path)
    return result.value
  }

  private mutating func cache(
    _ result: CachedAssetRootLocation,
    for itemIDs: [Int64]
  ) {
    for itemID in itemIDs {
      cache[itemID] = result
    }
  }
}

public struct AssetSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let characterID: Int64
  public let capturedAt: Date
  public let state: DataFreshness
  public let items: [AssetItem]
  public let unresolvedLocationIDs: Set<Int64>
  public let resolvedLocationNames: [Int64: String]?
  public let unresolvedLocationNameIDs: Set<Int64>?
  public let resolvedStructureTypeIDs: [Int64: Int64]?

  public init(
    id: UUID = UUID(),
    characterID: Int64,
    capturedAt: Date = .now,
    state: DataFreshness,
    items: [AssetItem],
    unresolvedLocationIDs: Set<Int64> = [],
    resolvedLocationNames: [Int64: String]? = nil,
    unresolvedLocationNameIDs: Set<Int64>? = nil,
    resolvedStructureTypeIDs: [Int64: Int64]? = nil
  ) {
    self.id = id
    self.characterID = characterID
    self.capturedAt = capturedAt
    self.state = state
    self.items = items
    self.unresolvedLocationIDs = unresolvedLocationIDs
    self.resolvedLocationNames = resolvedLocationNames
    self.unresolvedLocationNameIDs = unresolvedLocationNameIDs
    self.resolvedStructureTypeIDs = resolvedStructureTypeIDs
  }

  public func quantities(at locationID: Int64) -> [Int64: Int64] {
    var resolver = AssetRootLocationResolver(items: items)
    return
      items.lazy
      .filter {
        resolver.rootLocation(for: $0)?.id == locationID
      }
      .reduce(into: [:]) { result, item in
        result[item.typeID] = Self.saturatedAdd(
          result[item.typeID, default: 0],
          item.quantity
        )
      }
  }

  public func rootLocation(for item: AssetItem) -> AssetRootLocation? {
    var resolver = AssetRootLocationResolver(items: items)
    return resolver.rootLocation(for: item)
  }

  func itemsWithRootLocations() -> [(item: AssetItem, location: AssetRootLocation?)] {
    var resolver = AssetRootLocationResolver(items: items)
    return items.map { item in
      (item, resolver.rootLocation(for: item))
    }
  }

  private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow { return rhs >= 0 ? Int64.max : Int64.min }
    return result
  }
}

public struct StockSource: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case assetSnapshot
    case warehouse
    case manual
  }

  public let kind: Kind
  public let reference: String

  public init(kind: Kind, reference: String) {
    self.kind = kind
    self.reference = reference
  }
}

public struct StockAllocation: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let quantity: Int64
  public let source: StockSource

  public init(
    id: UUID = UUID(),
    typeID: Int64,
    quantity: Int64,
    source: StockSource
  ) {
    self.id = id
    self.typeID = typeID
    self.quantity = quantity
    self.source = source
  }
}
