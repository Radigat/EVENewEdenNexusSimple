import EVENexusCore
import Foundation

struct StoredAssetSnapshotPayload: Sendable {
  let ownerID: Int64
  let ownerName: String
  let encodedSnapshot: Data
}

struct PreparedAssetWarehouse: Sendable {
  let warehouse: AssetWarehouse
  let inventoryCount: Int
  let factualQuantities: [Int64: Int64]
  let totalUnits: Int64

  static let empty = PreparedAssetWarehouse(
    warehouse: AssetWarehouse(inventories: []),
    inventoryCount: 0,
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
      factualQuantities: filteredQuantities,
      totalUnits: filteredQuantities.values.reduce(
        0,
        AssetWarehouse.saturatedAdd
      )
    )
  }
}

enum StoredAssetWarehouseProjection {
  static func prepare(
    payloads: [StoredAssetSnapshotPayload]
  ) async -> PreparedAssetWarehouse {
    await Task.detached(priority: .userInitiated) {
      let inventories: [AssetOwnerInventory] = payloads.compactMap { payload in
        guard
          let sourced = try? JSONDecoder().decode(
            Sourced<AssetSnapshot>.self,
            from: payload.encodedSnapshot
          )
        else { return nil }
        return AssetOwnerInventory(
          ownerID: payload.ownerID,
          ownerName: payload.ownerName,
          assets: sourced
        )
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
        factualQuantities: factualQuantities,
        totalUnits: totalUnits
      )
    }.value
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
