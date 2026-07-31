import Foundation

public enum AssetLocationKind: String, Codable, Sendable {
  case station
  case structure
  case solarSystem
  case item
  case unresolved

  public init(esiValue: String) {
    switch esiValue {
    case "station": self = .station
    case "structure": self = .structure
    case "solar_system": self = .solarSystem
    case "item": self = .item
    default: self = .unresolved
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
}

public struct AssetRootLocation: Codable, Hashable, Sendable {
  public let id: Int64
  public let kind: AssetLocationKind

  public init(id: Int64, kind: AssetLocationKind) {
    self.id = id
    self.kind = kind
  }
}

public struct AssetSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let characterID: Int64
  public let capturedAt: Date
  public let state: DataFreshness
  public let items: [AssetItem]
  public let unresolvedLocationIDs: Set<Int64>

  public init(
    id: UUID = UUID(),
    characterID: Int64,
    capturedAt: Date = .now,
    state: DataFreshness,
    items: [AssetItem],
    unresolvedLocationIDs: Set<Int64> = []
  ) {
    self.id = id
    self.characterID = characterID
    self.capturedAt = capturedAt
    self.state = state
    self.items = items
    self.unresolvedLocationIDs = unresolvedLocationIDs
  }

  public func quantities(at locationID: Int64) -> [Int64: Int64] {
    let itemsByID = items.reduce(into: [Int64: AssetItem]()) {
      $0[$1.id] = $0[$1.id] ?? $1
    }
    return
      items.lazy
      .filter {
        resolvedRootLocation(for: $0, itemsByID: itemsByID)?.id == locationID
      }
      .reduce(into: [:]) { result, item in
        result[item.typeID] = Self.saturatedAdd(
          result[item.typeID, default: 0],
          item.quantity
        )
      }
  }

  public func rootLocation(for item: AssetItem) -> AssetRootLocation? {
    let itemsByID = items.reduce(into: [Int64: AssetItem]()) {
      $0[$1.id] = $0[$1.id] ?? $1
    }
    return resolvedRootLocation(for: item, itemsByID: itemsByID)
  }

  private func resolvedRootLocation(
    for item: AssetItem,
    itemsByID: [Int64: AssetItem]
  ) -> AssetRootLocation? {
    var locationID = item.locationID
    var kind = item.locationKind
    var visited = Set<Int64>()
    while kind == .item {
      guard visited.insert(locationID).inserted,
        let container = itemsByID[locationID]
      else { return nil }
      locationID = container.locationID
      kind = container.locationKind
    }
    guard kind != .unresolved else { return nil }
    return AssetRootLocation(id: locationID, kind: kind)
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
