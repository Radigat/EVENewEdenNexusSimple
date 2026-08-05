import EVENexusCore
import Foundation

struct StoredAssetSnapshotPayload: Sendable {
  let ownerID: Int64
  let ownerName: String
  let ownerKind: AssetOwnerKind
  let encodedSnapshot: Data
}

struct PreparedAssetOwnerStatus: Identifiable, Sendable {
  var id: String { "\(ownerKind.rawValue):\(ownerID)" }
  let ownerID: Int64
  let ownerName: String
  let ownerKind: AssetOwnerKind
  let state: DataFreshness
  let hasSnapshot: Bool
  let diagnostics: [String]
}

struct PreparedAssetWarehouse: Sendable {
  let warehouse: AssetWarehouse
  let inventoryCount: Int
  let ownerStatuses: [PreparedAssetOwnerStatus]
  let factualQuantities: [Int64: Int64]
  let totalUnits: Int64

  static let empty = PreparedAssetWarehouse(
    warehouse: AssetWarehouse(inventories: []),
    inventoryCount: 0,
    ownerStatuses: [],
    factualQuantities: [:],
    totalUnits: 0
  )

  func filtered(
    locationIDs: Set<Int64>,
    excludingTypeIDs: Set<Int64>,
    excludingContentsOfTypeIDs: Set<Int64> = []
  ) -> PreparedAssetWarehouse {
    let filteredWarehouse = warehouse.filtered(
      locationIDs: locationIDs,
      excludingTypeIDs: excludingTypeIDs,
      excludingContentsOfTypeIDs: excludingContentsOfTypeIDs
    )
    let filteredQuantities = filteredWarehouse.factualQuantities
    return PreparedAssetWarehouse(
      warehouse: filteredWarehouse,
      inventoryCount: Set(
        filteredWarehouse.locations.flatMap(\.owners).map(\.ownerID)
      ).count,
      ownerStatuses: ownerStatuses,
      factualQuantities: filteredQuantities,
      totalUnits: filteredQuantities.values.reduce(
        0,
        AssetWarehouse.saturatedAdd
      )
    )
  }
}

enum StoredAssetWarehouseProjection {
  private struct DecodedInventory: Sendable {
    let payload: StoredAssetSnapshotPayload
    let sourced: Sourced<AssetSnapshot>
  }

  private struct OwnerKey: Hashable {
    let ownerID: Int64
    let ownerKind: AssetOwnerKind
  }

  static func prepare(
    payloads: [StoredAssetSnapshotPayload]
  ) async -> PreparedAssetWarehouse {
    await Task.detached(priority: .userInitiated) {
      let decoded: [DecodedInventory] = payloads.compactMap { payload in
        guard
          let sourced = try? JSONDecoder().decode(
            Sourced<AssetSnapshot>.self,
            from: payload.encodedSnapshot
          )
        else { return nil }
        return DecodedInventory(payload: payload, sourced: sourced)
      }
      let selected = Dictionary(grouping: decoded) {
        OwnerKey(
          ownerID: $0.payload.ownerID,
          ownerKind: $0.payload.ownerKind
        )
      }.compactMap { _, candidates in
        candidates.max(by: isLessPreferred)
      }
      let inventories: [AssetOwnerInventory] = selected.map { decoded in
        return AssetOwnerInventory(
          ownerID: decoded.payload.ownerID,
          ownerName: decoded.payload.ownerName,
          ownerKind: decoded.payload.ownerKind,
          assets: decoded.sourced
        )
      }
      let ownerStatuses = selected.map { decoded in
        PreparedAssetOwnerStatus(
          ownerID: decoded.payload.ownerID,
          ownerName: decoded.payload.ownerName,
          ownerKind: decoded.payload.ownerKind,
          state: decoded.sourced.state,
          hasSnapshot: decoded.sourced.value != nil,
          diagnostics: decoded.sourced.diagnostics
        )
      }.sorted {
        $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
          == .orderedAscending
      }
      let warehouse = AssetWarehouse(inventories: inventories)
      let factualQuantities = warehouse.factualQuantities
      let totalUnits = factualQuantities.values.reduce(
        0,
        AssetWarehouse.saturatedAdd
      )
      return PreparedAssetWarehouse(
        warehouse: warehouse,
        inventoryCount: inventories.count,
        ownerStatuses: ownerStatuses,
        factualQuantities: factualQuantities,
        totalUnits: totalUnits
      )
    }.value
  }

  private static func isLessPreferred(
    _ lhs: DecodedInventory,
    _ rhs: DecodedInventory
  ) -> Bool {
    let lhsRank = stateRank(lhs.sourced.state, hasValue: lhs.sourced.value != nil)
    let rhsRank = stateRank(rhs.sourced.state, hasValue: rhs.sourced.value != nil)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    return lhs.sourced.source.capturedAt < rhs.sourced.source.capturedAt
  }

  private static func stateRank(
    _ state: DataFreshness,
    hasValue: Bool
  ) -> Int {
    guard hasValue else { return 0 }
    return switch state {
    case .fresh: 4
    case .partial: 3
    case .stale: 2
    case .forbidden, .unavailable: 1
    }
  }
}

actor StoredAssetWarehouseProjectionCache {
  private var cachedIdentity: String?
  private var cachedProjection = PreparedAssetWarehouse.empty
  private var inFlightIdentity: String?
  private var inFlightTask: Task<PreparedAssetWarehouse, Never>?

  func prepare(
    identity: String,
    payloads: [StoredAssetSnapshotPayload]
  ) async -> PreparedAssetWarehouse {
    if cachedIdentity == identity {
      return cachedProjection
    }
    if inFlightIdentity == identity, let inFlightTask {
      return await inFlightTask.value
    }

    let task = Task {
      await StoredAssetWarehouseProjection.prepare(payloads: payloads)
    }
    inFlightIdentity = identity
    inFlightTask = task
    let prepared = await task.value
    if inFlightIdentity == identity {
      cachedIdentity = identity
      cachedProjection = prepared
      inFlightIdentity = nil
      inFlightTask = nil
    }
    return prepared
  }
}
