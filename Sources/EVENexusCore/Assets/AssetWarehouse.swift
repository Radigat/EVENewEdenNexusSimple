import Foundation

public struct AssetOwnerInventory: Codable, Sendable {
  public let ownerID: Int64
  public let ownerName: String
  public let assets: Sourced<AssetSnapshot>

  public init(
    ownerID: Int64,
    ownerName: String,
    assets: Sourced<AssetSnapshot>
  ) {
    self.ownerID = ownerID
    self.ownerName = ownerName
    self.assets = assets
  }
}

public struct AssetWarehouseItem: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let quantity: Int64
  public let locationFlag: String
  public let singleton: Bool

  public init(
    id: Int64,
    typeID: Int64,
    quantity: Int64,
    locationFlag: String,
    singleton: Bool
  ) {
    self.id = id
    self.typeID = typeID
    self.quantity = quantity
    self.locationFlag = locationFlag
    self.singleton = singleton
  }
}

public struct AssetWarehouseOwner: Identifiable, Codable, Sendable {
  public var id: Int64 { ownerID }
  public let ownerID: Int64
  public let ownerName: String
  public let state: DataFreshness
  public let capturedAt: Date
  public let snapshotID: UUID
  public let items: [AssetWarehouseItem]

  public init(
    ownerID: Int64,
    ownerName: String,
    state: DataFreshness,
    capturedAt: Date,
    snapshotID: UUID,
    items: [AssetWarehouseItem]
  ) {
    self.ownerID = ownerID
    self.ownerName = ownerName
    self.state = state
    self.capturedAt = capturedAt
    self.snapshotID = snapshotID
    self.items = items
  }

  public var totalUnits: Int64 {
    items.reduce(0) { AssetWarehouse.saturatedAdd($0, $1.quantity) }
  }
}

public struct AssetWarehouseLocation: Identifiable, Codable, Sendable {
  public let id: Int64
  public let kind: AssetLocationKind
  public let owners: [AssetWarehouseOwner]

  public init(
    id: Int64,
    kind: AssetLocationKind,
    owners: [AssetWarehouseOwner]
  ) {
    self.id = id
    self.kind = kind
    self.owners = owners
  }

  public var totalUnits: Int64 {
    owners.reduce(0) { AssetWarehouse.saturatedAdd($0, $1.totalUnits) }
  }

  public var distinctTypeCount: Int {
    Set(owners.flatMap(\.items).map(\.typeID)).count
  }
}

public struct WarehouseStockLine: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let factualQuantity: Int64
  public let targetQuantity: Int64
  public let allocatableQuantity: Int64
  public let missingToTarget: Int64

  public init(
    typeID: Int64,
    factualQuantity: Int64,
    targetQuantity: Int64
  ) {
    self.typeID = typeID
    self.factualQuantity = max(0, factualQuantity)
    self.targetQuantity = max(0, targetQuantity)
    self.allocatableQuantity = max(
      0,
      self.factualQuantity - self.targetQuantity
    )
    self.missingToTarget = max(
      0,
      self.targetQuantity - self.factualQuantity
    )
  }
}

public struct WarehouseAvailability: Codable, Equatable, Sendable {
  public let lines: [WarehouseStockLine]

  public init(lines: [WarehouseStockLine]) {
    self.lines = lines.sorted { $0.typeID < $1.typeID }
  }

  public var allocatableQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: lines.map {
        ($0.typeID, $0.allocatableQuantity)
      }
    )
  }

  public var factualQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: lines.map {
        ($0.typeID, $0.factualQuantity)
      }
    )
  }
}

public struct AssetWarehouse: Codable, Sendable {
  public let locations: [AssetWarehouseLocation]
  public let snapshotIDs: [UUID]
  public let sourceStates: [DataFreshness]
  public let unresolvedLocationIDs: Set<Int64>

  public init(inventories: [AssetOwnerInventory]) {
    struct LocationOwnerKey: Hashable {
      let location: AssetRootLocation
      let ownerID: Int64
    }

    var grouped: [LocationOwnerKey: [AssetWarehouseItem]] = [:]
    var ownerDetails: [Int64: (name: String, state: DataFreshness, date: Date, id: UUID)] = [:]
    var snapshotIDs: [UUID] = []
    var sourceStates: [DataFreshness] = []
    var unresolved = Set<Int64>()

    for inventory in inventories.sorted(by: { $0.ownerID < $1.ownerID }) {
      sourceStates.append(inventory.assets.state)
      guard let snapshot = inventory.assets.value else { continue }
      snapshotIDs.append(snapshot.id)
      unresolved.formUnion(snapshot.unresolvedLocationIDs)
      ownerDetails[inventory.ownerID] = (
        inventory.ownerName,
        inventory.assets.state,
        snapshot.capturedAt,
        snapshot.id
      )
      for item in snapshot.items {
        guard let location = snapshot.rootLocation(for: item) else {
          unresolved.insert(item.locationID)
          continue
        }
        let key = LocationOwnerKey(
          location: location,
          ownerID: inventory.ownerID
        )
        grouped[key, default: []].append(
          AssetWarehouseItem(
            id: item.id,
            typeID: item.typeID,
            quantity: item.quantity,
            locationFlag: item.locationFlag,
            singleton: item.singleton
          )
        )
      }
    }

    let locationKeys = Set(grouped.keys.map(\.location))
    locations = locationKeys.map { location in
      let owners = grouped.keys
        .filter { $0.location == location }
        .compactMap { key -> AssetWarehouseOwner? in
          guard let detail = ownerDetails[key.ownerID] else { return nil }
          return AssetWarehouseOwner(
            ownerID: key.ownerID,
            ownerName: detail.name,
            state: detail.state,
            capturedAt: detail.date,
            snapshotID: detail.id,
            items: grouped[key, default: []].sorted {
              if $0.typeID == $1.typeID { return $0.id < $1.id }
              return $0.typeID < $1.typeID
            }
          )
        }
        .sorted {
          $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
            == .orderedAscending
        }
      return AssetWarehouseLocation(
        id: location.id,
        kind: location.kind,
        owners: owners
      )
    }
    .sorted {
      if $0.kind == $1.kind { return $0.id < $1.id }
      return Self.locationSortOrder($0.kind)
        < Self.locationSortOrder($1.kind)
    }
    self.snapshotIDs = snapshotIDs
    self.sourceStates = sourceStates
    self.unresolvedLocationIDs = unresolved
  }

  public var factualQuantities: [Int64: Int64] {
    locations
      .flatMap(\.owners)
      .flatMap(\.items)
      .reduce(into: [Int64: Int64]()) { totals, item in
        totals[item.typeID] = Self.saturatedAdd(
          totals[item.typeID, default: 0],
          item.quantity
        )
      }
  }

  public func availability(
    targetQuantities: [Int64: Int64]
  ) -> WarehouseAvailability {
    let factual = factualQuantities
    let typeIDs = Set(factual.keys).union(targetQuantities.keys)
    return WarehouseAvailability(
      lines: typeIDs.map {
        WarehouseStockLine(
          typeID: $0,
          factualQuantity: factual[$0, default: 0],
          targetQuantity: targetQuantities[$0, default: 0]
        )
      }
    )
  }

  public static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow { return rhs >= 0 ? Int64.max : Int64.min }
    return result
  }

  private static func locationSortOrder(_ kind: AssetLocationKind) -> Int {
    switch kind {
    case .station: 0
    case .structure: 1
    case .solarSystem: 2
    case .item: 3
    case .unresolved: 4
    }
  }
}
