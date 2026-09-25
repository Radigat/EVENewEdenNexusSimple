import Foundation
import Testing

@testable import EVENexusCore

@Suite("Loyalty Store catalog")
struct LoyaltyStoreCatalogTests {
  @Test
  func offerDecodingPreservesISKLPAndRequiredItems() throws {
    let data = Data(
      #"[{"isk_cost":5000000,"lp_cost":25000,"offer_id":42,"quantity":1,"required_items":[{"quantity":2,"type_id":34}],"type_id":9001}]"#
        .utf8
    )

    let offer = try #require(
      JSONDecoder().decode([LoyaltyStoreOfferDTO].self, from: data).first
    )

    #expect(offer.typeID == 9_001)
    #expect(offer.iskCost == 5_000_000)
    #expect(offer.lpCost == 25_000)
    #expect(
      offer.requiredItems == [
        LoyaltyStoreRequiredItemDTO(quantity: 2, typeID: 34)
      ])
  }

  @Test
  func snapshotStoreRetainsPartialStateAndDeduplicatesTypes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-loyalty-store-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LoyaltyStoreCatalogStore(
      fileURL: root.appendingPathComponent("catalog.json")
    )
    let snapshot = LoyaltyStoreCatalogSnapshot(
      fetchedAt: Date(timeIntervalSince1970: 1_000),
      expiresAt: Date(timeIntervalSince1970: 2_000),
      corporationCount: 3,
      successfulCorporationCount: 2,
      failedCorporationCount: 1,
      offeredTypeIDs: [9_002, 9_001, 9_002, -1]
    )

    try await store.save(snapshot)
    let loaded = try await store.load()

    #expect(loaded?.offeredTypeIDs == [9_001, 9_002])
    #expect(loaded?.failedCorporationCount == 1)
    #expect(loaded?.isComplete == false)
  }
}
