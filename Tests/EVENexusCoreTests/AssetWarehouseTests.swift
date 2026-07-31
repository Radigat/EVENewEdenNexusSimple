import Foundation
import Testing

@testable import EVENexusCore

@Suite("Combined asset warehouse")
struct AssetWarehouseTests {
  @Test
  func groupsStationFirstThenOwnerAndResolvesNestedContents() {
    let first = sourcedAssets(
      ownerID: 11,
      items: [
        asset(
          id: 100,
          typeID: 1_000,
          quantity: 1,
          locationID: 60_003_760,
          kind: .station
        ),
        asset(
          id: 101,
          typeID: 34,
          quantity: 100,
          locationID: 100,
          kind: .item
        ),
      ]
    )
    let second = sourcedAssets(
      ownerID: 22,
      items: [
        asset(
          id: 200,
          typeID: 34,
          quantity: 50,
          locationID: 60_003_760,
          kind: .station
        ),
        asset(
          id: 201,
          typeID: 35,
          quantity: 20,
          locationID: 60_008_044,
          kind: .station
        ),
      ]
    )

    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: first
        ),
        AssetOwnerInventory(
          ownerID: 22,
          ownerName: "Beta",
          assets: second
        ),
      ]
    )

    #expect(warehouse.locations.map(\.id) == [60_003_760, 60_008_044])
    #expect(warehouse.locations[0].owners.map(\.ownerName) == ["Alpha", "Beta"])
    #expect(warehouse.factualQuantities[34] == 150)
    #expect(
      warehouse.locations[0].owners[0].items.contains {
        $0.id == 101 && $0.quantity == 100
      }
    )
  }

  @Test
  func protectsTargetsAndReportsExistingTargetShortfalls() {
    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: sourcedAssets(
            ownerID: 11,
            items: [
              asset(
                id: 100,
                typeID: 34,
                quantity: 150,
                locationID: 60_003_760,
                kind: .station
              )
            ]
          )
        )
      ]
    )

    let availability = warehouse.availability(
      targetQuantities: [34: 120, 35: 5]
    )
    let tritanium = availability.lines.first { $0.typeID == 34 }
    let pyerite = availability.lines.first { $0.typeID == 35 }

    #expect(tritanium?.factualQuantity == 150)
    #expect(tritanium?.allocatableQuantity == 30)
    #expect(tritanium?.missingToTarget == 0)
    #expect(pyerite?.allocatableQuantity == 0)
    #expect(pyerite?.missingToTarget == 5)
  }

  @Test
  func excludesContainerCyclesFromAllocatableStock() {
    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: sourcedAssets(
            ownerID: 11,
            items: [
              asset(
                id: 100,
                typeID: 34,
                quantity: 10,
                locationID: 101,
                kind: .item
              ),
              asset(
                id: 101,
                typeID: 35,
                quantity: 20,
                locationID: 100,
                kind: .item
              ),
            ]
          )
        )
      ]
    )

    #expect(warehouse.locations.isEmpty)
    #expect(warehouse.factualQuantities.isEmpty)
    #expect(warehouse.unresolvedLocationIDs == [100, 101])
  }

  private func sourcedAssets(
    ownerID: Int64,
    items: [AssetItem]
  ) -> Sourced<AssetSnapshot> {
    Sourced(
      state: .fresh,
      value: AssetSnapshot(
        id: UUID(
          uuidString:
            ownerID == 11
            ? "00000000-0000-0000-0000-000000000011"
            : "00000000-0000-0000-0000-000000000022"
        )!,
        characterID: ownerID,
        capturedAt: Date(timeIntervalSince1970: 1_000),
        state: .fresh,
        items: items
      ),
      source: SourceIdentity(
        provider: "ESI",
        version: EVEConstants.esiCompatibilityDate,
        capturedAt: Date(timeIntervalSince1970: 1_000),
        snapshotID: UUID(
          uuidString:
            ownerID == 11
            ? "10000000-0000-0000-0000-000000000011"
            : "10000000-0000-0000-0000-000000000022"
        )!
      )
    )
  }

  private func asset(
    id: Int64,
    typeID: Int64,
    quantity: Int64,
    locationID: Int64,
    kind: AssetLocationKind
  ) -> AssetItem {
    AssetItem(
      id: id,
      typeID: typeID,
      quantity: quantity,
      locationID: locationID,
      locationKind: kind,
      locationFlag: "Hangar",
      singleton: false
    )
  }
}
