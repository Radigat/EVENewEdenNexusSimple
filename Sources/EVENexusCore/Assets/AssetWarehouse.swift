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
  public let ancestorTypeIDs: [Int64]

  public init(
    id: Int64,
    typeID: Int64,
    quantity: Int64,
    locationFlag: String,
    singleton: Bool,
    ancestorTypeIDs: [Int64] = []
  ) {
    self.id = id
    self.typeID = typeID
    self.quantity = quantity
    self.locationFlag = locationFlag
    self.singleton = singleton
    self.ancestorTypeIDs = ancestorTypeIDs
  }
}

public struct AssetWarehouseOwnerContentKey: Hashable, Sendable {
  public let locationID: Int64
  public let ownerID: Int64

  public init(locationID: Int64, ownerID: Int64) {
    self.locationID = locationID
    self.ownerID = ownerID
  }
}

public struct AssetWarehouseOwnerContentLine: Identifiable, Equatable,
  Sendable
{
  public var id: String { "\(typeID)|\(locationFlag)" }
  public let typeID: Int64
  public let locationFlag: String
  public let quantity: Int64

  public init(typeID: Int64, locationFlag: String, quantity: Int64) {
    self.typeID = typeID
    self.locationFlag = locationFlag
    self.quantity = quantity
  }
}

public enum AssetInventoryOrganization: String, Codable, CaseIterable,
  Identifiable, Sendable
{
  case alphabetical
  case group
  case mainGroup

  public var id: Self { self }
}

public struct AssetTypeGroupingMetadata: Equatable, Sendable {
  public let typeID: Int64
  public let typeName: String
  public let categoryName: String?
  public let groupName: String?

  public init(
    typeID: Int64,
    typeName: String,
    categoryName: String?,
    groupName: String?
  ) {
    self.typeID = typeID
    self.typeName = typeName
    self.categoryName = categoryName
    self.groupName = groupName
  }
}

public struct AssetWarehouseOwnerContentSection: Identifiable, Equatable,
  Sendable
{
  public var id: String { title ?? "all" }
  public let title: String?
  public let rows: [AssetWarehouseOwnerContentLine]

  public init(
    title: String?,
    rows: [AssetWarehouseOwnerContentLine]
  ) {
    self.title = title
    self.rows = rows
  }
}

public enum AssetWarehouseContentOrganizer {
  public static let unclassifiedTitle = "Unclassified"

  public static func sections(
    rows: [AssetWarehouseOwnerContentLine],
    metadata: [Int64: AssetTypeGroupingMetadata],
    organization: AssetInventoryOrganization
  ) -> [AssetWarehouseOwnerContentSection] {
    let sortedRows = rows.sorted {
      compareRows($0, $1, metadata: metadata)
    }
    guard organization != .alphabetical else {
      return [
        AssetWarehouseOwnerContentSection(
          title: nil,
          rows: sortedRows
        )
      ]
    }

    let grouped = Dictionary(grouping: sortedRows) { row in
      let value: String?
      switch organization {
      case .alphabetical:
        value = nil
      case .group:
        value = metadata[row.typeID]?.groupName
      case .mainGroup:
        value = metadata[row.typeID]?.categoryName
      }
      let accepted = value?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let accepted, !accepted.isEmpty else {
        return unclassifiedTitle
      }
      return accepted
    }
    return grouped.map { title, rows in
      AssetWarehouseOwnerContentSection(title: title, rows: rows)
    }
    .sorted { lhs, rhs in
      if lhs.title == unclassifiedTitle {
        return false
      }
      if rhs.title == unclassifiedTitle {
        return true
      }
      return (lhs.title ?? "").localizedCaseInsensitiveCompare(
        rhs.title ?? ""
      ) == .orderedAscending
    }
  }

  private static func compareRows(
    _ lhs: AssetWarehouseOwnerContentLine,
    _ rhs: AssetWarehouseOwnerContentLine,
    metadata: [Int64: AssetTypeGroupingMetadata]
  ) -> Bool {
    let lhsName = metadata[lhs.typeID]?.typeName ?? "Type \(lhs.typeID)"
    let rhsName = metadata[rhs.typeID]?.typeName ?? "Type \(rhs.typeID)"
    let comparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
    if comparison == .orderedSame {
      if lhs.typeID != rhs.typeID {
        return lhs.typeID < rhs.typeID
      }
      return lhs.locationFlag.localizedCaseInsensitiveCompare(
        rhs.locationFlag
      ) == .orderedAscending
    }
    return comparison == .orderedAscending
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
  public let resolvedName: String?
  public let resolvedTypeID: Int64?
  public let owners: [AssetWarehouseOwner]

  public init(
    id: Int64,
    kind: AssetLocationKind,
    resolvedName: String? = nil,
    resolvedTypeID: Int64? = nil,
    owners: [AssetWarehouseOwner]
  ) {
    self.id = id
    self.kind = kind
    self.resolvedName = resolvedName
    self.resolvedTypeID = resolvedTypeID
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
    var grouped: [AssetRootLocation: [Int64: [AssetWarehouseItem]]] = [:]
    var ownerDetails: [Int64: (name: String, state: DataFreshness, date: Date, id: UUID)] = [:]
    var snapshotIDs: [UUID] = []
    var sourceStates: [DataFreshness] = []
    var unresolved = Set<Int64>()
    var resolvedLocationNames: [Int64: (name: String, capturedAt: Date)] = [:]
    var resolvedStructureTypeIDs: [Int64: (typeID: Int64, capturedAt: Date)] = [:]

    for inventory in inventories.sorted(by: { $0.ownerID < $1.ownerID }) {
      sourceStates.append(inventory.assets.state)
      guard let snapshot = inventory.assets.value else { continue }
      snapshotIDs.append(snapshot.id)
      unresolved.formUnion(snapshot.unresolvedLocationIDs)
      for (locationID, name) in snapshot.resolvedLocationNames ?? [:] {
        if resolvedLocationNames[locationID]?.capturedAt ?? .distantPast
          <= snapshot.capturedAt
        {
          resolvedLocationNames[locationID] = (name, snapshot.capturedAt)
        }
      }
      for (locationID, typeID) in snapshot.resolvedStructureTypeIDs ?? [:] {
        if resolvedStructureTypeIDs[locationID]?.capturedAt ?? .distantPast
          <= snapshot.capturedAt
        {
          resolvedStructureTypeIDs[locationID] = (
            typeID,
            snapshot.capturedAt
          )
        }
      }
      ownerDetails[inventory.ownerID] = (
        inventory.ownerName,
        inventory.assets.state,
        snapshot.capturedAt,
        snapshot.id
      )
      for context in snapshot.itemsWithWarehouseContexts() {
        let item = context.item
        let resolvedLocation = context.location
        guard let location = resolvedLocation else {
          unresolved.insert(item.locationID)
          continue
        }
        grouped[location, default: [:]][
          inventory.ownerID,
          default: []
        ].append(
          AssetWarehouseItem(
            id: item.id,
            typeID: item.typeID,
            quantity: item.quantity,
            locationFlag: item.locationFlag,
            singleton: item.singleton,
            ancestorTypeIDs: context.ancestorTypeIDs
          )
        )
      }
    }

    locations = grouped.map { location, itemsByOwner in
      let owners =
        itemsByOwner
        .compactMap { ownerID, items -> AssetWarehouseOwner? in
          guard let detail = ownerDetails[ownerID] else { return nil }
          return AssetWarehouseOwner(
            ownerID: ownerID,
            ownerName: detail.name,
            state: detail.state,
            capturedAt: detail.date,
            snapshotID: detail.id,
            items: items.sorted {
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
        resolvedName: resolvedLocationNames[location.id]?.name,
        resolvedTypeID: resolvedStructureTypeIDs[location.id]?.typeID,
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

  private init(
    locations: [AssetWarehouseLocation],
    snapshotIDs: [UUID],
    sourceStates: [DataFreshness],
    unresolvedLocationIDs: Set<Int64>
  ) {
    self.locations = locations
    self.snapshotIDs = snapshotIDs
    self.sourceStates = sourceStates
    self.unresolvedLocationIDs = unresolvedLocationIDs
  }

  /// Returns a provenance-preserving view of the warehouse for exact asset
  /// locations. Excluded types are removed without changing the source state
  /// of the snapshots that supplied the remaining inventory.
  public func filtered(
    locationIDs: Set<Int64>,
    excludingTypeIDs: Set<Int64> = [],
    excludingContentsOfTypeIDs: Set<Int64> = []
  ) -> AssetWarehouse {
    let acceptedLocations = locations.compactMap { location -> AssetWarehouseLocation? in
      guard locationIDs.contains(location.id) else { return nil }
      let owners = location.owners.compactMap { owner -> AssetWarehouseOwner? in
        let items = owner.items.filter {
          !excludingTypeIDs.contains($0.typeID)
            && $0.ancestorTypeIDs.allSatisfy {
              !excludingContentsOfTypeIDs.contains($0)
            }
        }
        guard !items.isEmpty else { return nil }
        return AssetWarehouseOwner(
          ownerID: owner.ownerID,
          ownerName: owner.ownerName,
          state: owner.state,
          capturedAt: owner.capturedAt,
          snapshotID: owner.snapshotID,
          items: items
        )
      }
      guard !owners.isEmpty else { return nil }
      return AssetWarehouseLocation(
        id: location.id,
        kind: location.kind,
        resolvedName: location.resolvedName,
        resolvedTypeID: location.resolvedTypeID,
        owners: owners
      )
    }
    return AssetWarehouse(
      locations: acceptedLocations,
      snapshotIDs: snapshotIDs,
      sourceStates: sourceStates,
      unresolvedLocationIDs: unresolvedLocationIDs
    )
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

  public func groupedOwnerContents()
    -> [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentLine]]
  {
    struct GroupKey: Hashable {
      let typeID: Int64
      let flag: String
    }
    var result: [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentLine]] = [:]
    for location in locations {
      for owner in location.owners {
        let grouped = Dictionary(
          grouping: owner.items,
          by: { GroupKey(typeID: $0.typeID, flag: $0.locationFlag) }
        )
        result[
          AssetWarehouseOwnerContentKey(
            locationID: location.id,
            ownerID: owner.ownerID
          )
        ] = grouped.map { key, items in
          AssetWarehouseOwnerContentLine(
            typeID: key.typeID,
            locationFlag: key.flag,
            quantity: items.reduce(0) {
              Self.saturatedAdd($0, $1.quantity)
            }
          )
        }
        .sorted {
          if $0.typeID == $1.typeID {
            return $0.locationFlag < $1.locationFlag
          }
          return $0.typeID < $1.typeID
        }
      }
    }
    return result
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
