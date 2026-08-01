import Foundation
import Testing

@testable import EVENexusCore

@Suite("Combined asset warehouse")
struct AssetWarehouseTests {
  @Test
  func classifiesESIOtherAndLargeStationIDsAsPlayerStructures() {
    #expect(AssetLocationKind(esiValue: "other") == .structure)
    #expect(
      AssetLocationKind(
        esiValue: "station",
        locationID: 1_000_000_000_001
      ) == .structure
    )
    #expect(
      AssetLocationKind(
        esiValue: "station",
        locationID: 60_003_760
      ) == .station
    )
  }

  @Test
  func includesNamedPlayerStructureAssetsInAllocatableWarehouse() {
    let structureID: Int64 = 1_000_000_000_001
    let assets = Sourced(
      state: .fresh,
      value: AssetSnapshot(
        characterID: 11,
        state: .fresh,
        items: [
          asset(
            id: 100,
            typeID: 34,
            quantity: 250,
            locationID: structureID,
            kind: .structure
          )
        ],
        resolvedLocationNames: [structureID: "Low-sec Industry Hub"],
        resolvedStructureTypeIDs: [structureID: 35_826]
      ),
      source: SourceIdentity(provider: "ESI", version: "fixture")
    )

    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: assets
        )
      ]
    )

    #expect(warehouse.locations.map(\.id) == [structureID])
    #expect(warehouse.locations.first?.kind == .structure)
    #expect(
      warehouse.locations.first?.resolvedName == "Low-sec Industry Hub"
    )
    #expect(warehouse.locations.first?.resolvedTypeID == 35_826)
    #expect(warehouse.factualQuantities[34] == 250)
  }

  @Test
  func productionWarehouseKeepsOnlyLooseAndContainerStock() {
    let productionLocation: Int64 = 1_000_000_000_001
    let otherLocation: Int64 = 60_003_760
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
                quantity: 250,
                locationID: productionLocation,
                kind: .structure
              ),
              asset(
                id: 101,
                typeID: 587,
                quantity: 1,
                locationID: productionLocation,
                kind: .structure
              ),
              asset(
                id: 102,
                typeID: 35,
                quantity: 50,
                locationID: otherLocation,
                kind: .station
              ),
              asset(
                id: 103,
                typeID: 2_048,
                quantity: 4,
                locationID: 101,
                kind: .item,
                locationFlag: "HiSlot0"
              ),
              asset(
                id: 104,
                typeID: 23,
                quantity: 1,
                locationID: productionLocation,
                kind: .structure
              ),
              asset(
                id: 105,
                typeID: 35,
                quantity: 75,
                locationID: 104,
                kind: .item,
                locationFlag: "Unlocked"
              ),
              asset(
                id: 106,
                typeID: 23,
                quantity: 1,
                locationID: 101,
                kind: .item,
                locationFlag: "Cargo"
              ),
              asset(
                id: 107,
                typeID: 36,
                quantity: 500,
                locationID: 106,
                kind: .item,
                locationFlag: "Unlocked"
              ),
            ]
          )
        )
      ]
    )

    let productionWarehouse = warehouse.filtered(
      locationIDs: [productionLocation],
      excludingTypeIDs: [587],
      excludingContentsOfTypeIDs: [587]
    )

    #expect(productionWarehouse.locations.map(\.id) == [productionLocation])
    #expect(
      productionWarehouse.factualQuantities
        == [23: 1, 34: 250, 35: 75]
    )
    #expect(productionWarehouse.snapshotIDs == warehouse.snapshotIDs)
    #expect(productionWarehouse.sourceStates == warehouse.sourceStates)
  }

  @Test
  func groupsOwnerContentsOnceByTypeAndInventoryFlag() {
    let locationID: Int64 = 60_003_760
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
                locationID: locationID,
                kind: .station
              ),
              asset(
                id: 101,
                typeID: 34,
                quantity: 15,
                locationID: locationID,
                kind: .station
              ),
              asset(
                id: 102,
                typeID: 34,
                quantity: 2,
                locationID: locationID,
                kind: .station,
                locationFlag: "AutoFit"
              ),
            ]
          )
        )
      ]
    )

    let rows = warehouse.groupedOwnerContents()[
      AssetWarehouseOwnerContentKey(locationID: locationID, ownerID: 11)
    ]

    #expect(
      rows == [
        AssetWarehouseOwnerContentLine(
          typeID: 34,
          locationFlag: "AutoFit",
          quantity: 2
        ),
        AssetWarehouseOwnerContentLine(
          typeID: 34,
          locationFlag: "Hangar",
          quantity: 25
        ),
      ]
    )
  }

  @Test
  func organizesOwnerContentsAlphabeticallyAndBySDEHierarchy() {
    let rows = [
      AssetWarehouseOwnerContentLine(
        typeID: 3,
        locationFlag: "Hangar",
        quantity: 7
      ),
      AssetWarehouseOwnerContentLine(
        typeID: 1,
        locationFlag: "Hangar",
        quantity: 5
      ),
      AssetWarehouseOwnerContentLine(
        typeID: 2,
        locationFlag: "Hangar",
        quantity: 6
      ),
      AssetWarehouseOwnerContentLine(
        typeID: 4,
        locationFlag: "Hangar",
        quantity: 8
      ),
    ]
    let metadata: [Int64: AssetTypeGroupingMetadata] = [
      1: AssetTypeGroupingMetadata(
        typeID: 1,
        typeName: "Zydrine",
        categoryName: "Material",
        groupName: "Mineral"
      ),
      2: AssetTypeGroupingMetadata(
        typeID: 2,
        typeName: "Antimatter Charge S",
        categoryName: "Charge",
        groupName: "Hybrid Charge"
      ),
      3: AssetTypeGroupingMetadata(
        typeID: 3,
        typeName: "Mexallon",
        categoryName: "Material",
        groupName: "Mineral"
      ),
    ]

    let alphabetical = AssetWarehouseContentOrganizer.sections(
      rows: rows,
      metadata: metadata,
      organization: .alphabetical
    )
    #expect(alphabetical.count == 1)
    #expect(alphabetical[0].title == nil)
    #expect(alphabetical[0].rows.map(\.typeID) == [2, 3, 4, 1])

    let groups = AssetWarehouseContentOrganizer.sections(
      rows: rows,
      metadata: metadata,
      organization: .group
    )
    #expect(
      groups.compactMap(\.title) == [
        "Hybrid Charge", "Mineral", "Unclassified",
      ]
    )
    #expect(groups[1].rows.map(\.typeID) == [3, 1])
    #expect(groups[2].rows.map(\.typeID) == [4])

    let mainGroups = AssetWarehouseContentOrganizer.sections(
      rows: rows,
      metadata: metadata,
      organization: .mainGroup
    )
    #expect(
      mainGroups.compactMap(\.title) == [
        "Charge", "Material", "Unclassified",
      ]
    )
    #expect(mainGroups[1].rows.map(\.typeID) == [3, 1])
  }

  @Test
  func promotesLargeOrphanItemParentsToStructureRoots() {
    let structureID: Int64 = 1_000_000_000_001
    let rawItems = [
      asset(
        id: 100,
        typeID: 34,
        quantity: 250,
        locationID: structureID,
        kind: .item
      ),
      asset(
        id: 101,
        typeID: 35,
        quantity: 50,
        locationID: 100,
        kind: .item
      ),
    ]

    let candidates = AssetLocationClassifier.structureCandidateIDs(
      in: rawItems
    )
    let normalized = AssetLocationClassifier.applyingStructureRoots(
      to: rawItems,
      candidateIDs: candidates
    )
    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: sourcedAssets(ownerID: 11, items: normalized)
        )
      ]
    )

    #expect(candidates == [structureID])
    #expect(normalized[0].locationKind == .structure)
    #expect(normalized[1].locationKind == .item)
    #expect(warehouse.locations.map(\.id) == [structureID])
    #expect(warehouse.factualQuantities[34] == 250)
    #expect(warehouse.factualQuantities[35] == 50)
  }

  @Test
  func keepsLargeMatchingItemParentsAsContainers() {
    let containerID: Int64 = 1_000_000_000_001
    let items = [
      asset(
        id: containerID,
        typeID: 1_000,
        quantity: 1,
        locationID: 60_003_760,
        kind: .station
      ),
      asset(
        id: 101,
        typeID: 34,
        quantity: 50,
        locationID: containerID,
        kind: .item
      ),
    ]

    #expect(
      AssetLocationClassifier.structureCandidateIDs(in: items).isEmpty
    )
  }

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

  @Test
  func resolvesLargeSnapshotsWithoutRebuildingTheItemIndexPerAsset() {
    let stationID: Int64 = 60_003_760
    let containerID: Int64 = 900_000
    let itemCount = 10_000
    var items = [
      asset(
        id: containerID,
        typeID: 1_000,
        quantity: 1,
        locationID: stationID,
        kind: .station
      )
    ]
    items.append(
      contentsOf: (0..<itemCount).map { offset in
        asset(
          id: Int64(offset + 1),
          typeID: 34,
          quantity: 1,
          locationID: containerID,
          kind: .item
        )
      }
    )

    let warehouse = AssetWarehouse(
      inventories: [
        AssetOwnerInventory(
          ownerID: 11,
          ownerName: "Alpha",
          assets: sourcedAssets(ownerID: 11, items: items)
        )
      ]
    )

    #expect(warehouse.locations.count == 1)
    #expect(warehouse.locations[0].id == stationID)
    #expect(warehouse.locations[0].owners[0].items.count == itemCount + 1)
    #expect(warehouse.factualQuantities[34] == Int64(itemCount))
    let displayRows = warehouse.groupedOwnerContents()[
      AssetWarehouseOwnerContentKey(locationID: stationID, ownerID: 11)
    ]
    #expect(displayRows?.count == 2)
    #expect(
      displayRows?.first(where: { $0.typeID == 34 })?.quantity
        == Int64(itemCount)
    )
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
    kind: AssetLocationKind,
    locationFlag: String = "Hangar"
  ) -> AssetItem {
    AssetItem(
      id: id,
      typeID: typeID,
      quantity: quantity,
      locationID: locationID,
      locationKind: kind,
      locationFlag: locationFlag,
      singleton: false
    )
  }
}
