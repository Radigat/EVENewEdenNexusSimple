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

  private func offer(
    corporationID: Int64,
    offerID: Int64,
    typeID: Int64,
    lp: Int,
    isk: Double,
    items: [LoyaltyStoreRequiredItemDTO] = []
  ) -> LoyaltyStoreOffer {
    LoyaltyStoreOffer(
      corporationID: corporationID,
      offerID: offerID,
      typeID: typeID,
      quantity: 1,
      lpCost: lp,
      iskCost: isk,
      requiredItems: items
    )
  }

  @Test
  func legacyCatalogWithoutOffersDecodesAndRequestsARefresh() throws {
    let data = Data(
      #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","fetchedAt":0,"expiresAt":null,"corporationCount":1,"successfulCorporationCount":1,"failedCorporationCount":0,"offeredTypeIDs":[1]}"#
        .utf8
    )
    let catalog = try JSONDecoder().decode(
      LoyaltyStoreCatalogSnapshot.self,
      from: data
    )
    #expect(catalog.offers == nil)
    #expect(!catalog.hasOfferDetails)
  }

  @Test
  func lpValueIsTheMedianOfTheFiveBestPricedOffers() {
    // Rates per LP: 10, 9, 8, 7, 6, 1; the item-requiring offer has no price
    // for its item and is ignored, the outlier 1 is outside the best five.
    var offers = (0..<6).map { index -> LoyaltyStoreOffer in
      offer(
        corporationID: 1,
        offerID: Int64(index),
        typeID: Int64(100 + index),
        lp: 1_000,
        isk: 0
      )
    }
    var prices = Dictionary(
      uniqueKeysWithValues: (0..<6).map {
        (Int64(100 + $0), [10.0, 9, 8, 7, 6, 1][$0] * 1_000)
      }
    )
    offers.append(
      offer(
        corporationID: 1,
        offerID: 99,
        typeID: 200,
        lp: 1,
        isk: 0,
        items: [LoyaltyStoreRequiredItemDTO(quantity: 1, typeID: 999)]
      )
    )
    prices[200] = 1_000_000
    let values = LoyaltyPointValuation.iskPerLP(
      offers: offers,
      averagePrices: prices
    )
    #expect(values[1] == 8)
    #expect(values[2] == nil)
  }

  @Test
  func blueprintOffersDistinguishUnknownFromZeroLoyaltyPoints() {
    let catalog = LoyaltyStoreCatalogSnapshot(
      fetchedAt: .now,
      expiresAt: nil,
      corporationCount: 1,
      successfulCorporationCount: 1,
      failedCorporationCount: 0,
      offeredTypeIDs: [900, 100],
      offers: [
        offer(corporationID: 1, offerID: 1, typeID: 900, lp: 5_000, isk: 1_000),
        offer(corporationID: 1, offerID: 2, typeID: 100, lp: 1_000, isk: 0),
      ],
      corporationNames: [1: "Federation Navy"],
      averagePrices: [100: 2_000]
    )
    let unknown = LoyaltyStoreBlueprintOfferBuilder.build(
      catalog: catalog,
      blueprintTypeIDs: [900],
      characterPoints: nil
    )[900]?.first
    #expect(unknown?.availableLP == nil)
    #expect(unknown?.iskPerLP == 2)
    #expect(unknown?.corporationName == "Federation Navy")

    let known = LoyaltyStoreBlueprintOfferBuilder.build(
      catalog: catalog,
      blueprintTypeIDs: [900],
      characterPoints: [
        CharacterLoyaltyPoints(
          characterID: 1, characterName: "A", corporationID: 1, points: 3_000),
        CharacterLoyaltyPoints(
          characterID: 2, characterName: "B", corporationID: 1, points: 7_000),
        CharacterLoyaltyPoints(
          characterID: 3, characterName: "C", corporationID: 2, points: 9_000),
      ],
      walletISKByCharacterName: ["B": 50_000]
    )[900]?.first
    #expect(known?.bestCharacterName == "B")
    #expect(known?.availableLP == 7_000)
    #expect(known?.availableISK == 50_000)

    let noLP = LoyaltyStoreBlueprintOfferBuilder.build(
      catalog: catalog,
      blueprintTypeIDs: [900],
      characterPoints: []
    )[900]?.first
    #expect(noLP?.availableLP == 0)
    #expect(noLP?.bestCharacterName == nil)
  }

  @Test
  func loyaltyPointsDecodeFromESI() throws {
    let data = Data(#"[{"corporation_id":1000120,"loyalty_points":42000}]"#.utf8)
    let points = try JSONDecoder().decode([ESILoyaltyPointsDTO].self, from: data)
    #expect(points.first?.corporationID == 1_000_120)
    #expect(points.first?.loyaltyPoints == 42_000)
  }

  @Test
  func lpStoreBPCRunsComeFromUnresearchedContractEvidence() {
    func contract(_ id: Int64, runs: Int, me: Int) -> PublicContractSearchResult {
      PublicContractSearchResult(
        contractID: id,
        recordID: id,
        regionID: 1,
        regionName: "R",
        contractType: "item_exchange",
        price: 1,
        dateIssued: .now,
        dateExpired: .now.addingTimeInterval(3_600),
        typeID: 900,
        isIncluded: true,
        quantity: 1,
        isBlueprintCopy: true,
        materialEfficiency: me,
        timeEfficiency: 0,
        runs: runs,
        offeredLineCount: 1,
        requestedLineCount: 0
      )
    }
    #expect(
      ManufacturingOpportunityBlueprintAcquisitionProjector.runsPerBlueprintCopy(
        offers: [
          contract(1, runs: 10, me: 0), contract(2, runs: 10, me: 0),
          contract(3, runs: 1, me: 0), contract(4, runs: 3, me: 10),
          contract(5, runs: 3, me: 10), contract(6, runs: 3, me: 10),
        ]
      ) == 10
    )
    #expect(
      ManufacturingOpportunityBlueprintAcquisitionProjector.runsPerBlueprintCopy(
        offers: []
      ) == 1
    )
  }
}
