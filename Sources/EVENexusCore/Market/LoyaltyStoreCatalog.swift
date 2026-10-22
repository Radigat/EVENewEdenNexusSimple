import Foundation

public struct LoyaltyStoreRequiredItemDTO: Codable, Equatable, Sendable {
  public let quantity: Int
  public let typeID: Int64

  private enum CodingKeys: String, CodingKey {
    case quantity
    case typeID = "type_id"
  }
}

public struct LoyaltyStoreOfferDTO: Codable, Equatable, Sendable {
  public let iskCost: Double
  public let lpCost: Int
  public let offerID: Int64
  public let quantity: Int
  public let requiredItems: [LoyaltyStoreRequiredItemDTO]
  public let typeID: Int64

  private enum CodingKeys: String, CodingKey {
    case quantity
    case iskCost = "isk_cost"
    case lpCost = "lp_cost"
    case offerID = "offer_id"
    case requiredItems = "required_items"
    case typeID = "type_id"
  }
}

/// One offer of one NPC corporation's Loyalty Store.
public struct LoyaltyStoreOffer: Codable, Equatable, Sendable {
  public let corporationID: Int64
  public let offerID: Int64
  public let typeID: Int64
  public let quantity: Int
  public let lpCost: Int
  public let iskCost: Double
  public let requiredItems: [LoyaltyStoreRequiredItemDTO]

  public init(
    corporationID: Int64,
    offerID: Int64,
    typeID: Int64,
    quantity: Int,
    lpCost: Int,
    iskCost: Double,
    requiredItems: [LoyaltyStoreRequiredItemDTO]
  ) {
    self.corporationID = corporationID
    self.offerID = offerID
    self.typeID = typeID
    self.quantity = quantity
    self.lpCost = lpCost
    self.iskCost = iskCost
    self.requiredItems = requiredItems
  }

  public init(corporationID: Int64, dto: LoyaltyStoreOfferDTO) {
    self.init(
      corporationID: corporationID,
      offerID: dto.offerID,
      typeID: dto.typeID,
      quantity: dto.quantity,
      lpCost: dto.lpCost,
      iskCost: dto.iskCost,
      requiredItems: dto.requiredItems
    )
  }
}

public struct LoyaltyStoreCatalogSnapshot: Codable, Equatable, Sendable {
  public let id: UUID
  public let fetchedAt: Date
  public let expiresAt: Date?
  public let corporationCount: Int
  public let successfulCorporationCount: Int
  public let failedCorporationCount: Int
  public let offeredTypeIDs: [Int64]
  /// Complete offers with LP, ISK and required items; `nil` in catalogs
  /// saved before offers were retained.
  public let offers: [LoyaltyStoreOffer]?
  public let corporationNames: [Int64: String]?
  /// ESI average prices of offered products and required items captured
  /// with the catalog; the basis of the self-calculated LP value.
  public let averagePrices: [Int64: Double]?

  public init(
    id: UUID = UUID(),
    fetchedAt: Date,
    expiresAt: Date?,
    corporationCount: Int,
    successfulCorporationCount: Int,
    failedCorporationCount: Int,
    offeredTypeIDs: [Int64],
    offers: [LoyaltyStoreOffer]? = nil,
    corporationNames: [Int64: String]? = nil,
    averagePrices: [Int64: Double]? = nil
  ) {
    self.id = id
    self.fetchedAt = fetchedAt
    self.expiresAt = expiresAt
    self.corporationCount = corporationCount
    self.successfulCorporationCount = successfulCorporationCount
    self.failedCorporationCount = failedCorporationCount
    self.offeredTypeIDs = Array(Set(offeredTypeIDs.filter { $0 > 0 })).sorted()
    self.offers = offers
    self.corporationNames = corporationNames
    self.averagePrices = averagePrices
  }

  /// Offers saved before this field existed force a refresh, because the
  /// LP route cannot be priced without them.
  public var hasOfferDetails: Bool { offers != nil }

  public var isComplete: Bool {
    corporationCount > 0
      && successfulCorporationCount == corporationCount
      && failedCorporationCount == 0
  }
}

public actor LoyaltyStoreCatalogStore {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> LoyaltyStoreCatalogSnapshot? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }
    return try JSONDecoder().decode(
      LoyaltyStoreCatalogSnapshot.self,
      from: Data(contentsOf: fileURL)
    )
  }

  public func save(_ snapshot: LoyaltyStoreCatalogSnapshot) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: fileURL, options: .atomic)
  }
}

public struct LoyaltyStoreCatalogService: Sendable {
  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  /// Fetches every NPC Loyalty Store, the corporation names and the ESI
  /// average prices used for the LP value.
  public func refreshWithValuation() async throws -> LoyaltyStoreCatalogSnapshot {
    let catalog = try await refresh()
    let offers = catalog.offers ?? []
    let corporationIDs = Set(offers.map(\.corporationID))
    let names = await UniverseNameService(esi: esi).names(for: corporationIDs)
    var averagePrices: [Int64: Double] = [:]
    if let response = try? await esi.get(
      [ESIAdjustedPriceDTO].self,
      endpoint: ESIEndpoint(path: "/markets/prices/")
    ) {
      var neededTypeIDs = Set(offers.map(\.typeID))
      for offer in offers {
        neededTypeIDs.formUnion(offer.requiredItems.map(\.typeID))
      }
      for price in response.value where neededTypeIDs.contains(price.typeID) {
        if let average = price.averagePrice, average.isFinite, average > 0 {
          averagePrices[price.typeID] = average
        }
      }
    }
    return LoyaltyStoreCatalogSnapshot(
      id: catalog.id,
      fetchedAt: catalog.fetchedAt,
      expiresAt: catalog.expiresAt,
      corporationCount: catalog.corporationCount,
      successfulCorporationCount: catalog.successfulCorporationCount,
      failedCorporationCount: catalog.failedCorporationCount,
      offeredTypeIDs: catalog.offeredTypeIDs,
      offers: offers,
      corporationNames: names.value,
      averagePrices: averagePrices.isEmpty ? nil : averagePrices
    )
  }

  public func refresh() async throws -> LoyaltyStoreCatalogSnapshot {
    let corporations = try await esi.get(
      [Int64].self,
      endpoint: ESIEndpoint(path: "/corporations/npccorps")
    )
    let corporationIDs = Array(
      Set(corporations.value.filter { $0 > 0 })
    ).sorted().prefix(500)
    var offeredTypeIDs = Set<Int64>()
    var offers: [LoyaltyStoreOffer] = []
    var successful = 0
    var failed = 0
    var earliestExpiry = corporations.expiresAt
    for corporationID in corporationIDs {
      try Task.checkCancellation()
      do {
        let response = try await ESIRequestContext.withPriority(.automatic) {
          try await esi.get(
            [LoyaltyStoreOfferDTO].self,
            endpoint: ESIEndpoint(
              path: "/loyalty/stores/\(corporationID)/offers"
            )
          )
        }
        successful += 1
        offeredTypeIDs.formUnion(response.value.map(\.typeID))
        offers.append(
          contentsOf: response.value.map {
            LoyaltyStoreOffer(corporationID: corporationID, dto: $0)
          }
        )
        if let expiry = response.expiresAt {
          earliestExpiry = earliestExpiry.map { min($0, expiry) } ?? expiry
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch ESIError.cancelled {
        throw CancellationError()
      } catch {
        failed += 1
      }
    }
    guard successful > 0 else { throw ESIError.server(503) }
    return LoyaltyStoreCatalogSnapshot(
      fetchedAt: .now,
      expiresAt: earliestExpiry,
      corporationCount: corporationIDs.count,
      successfulCorporationCount: successful,
      failedCorporationCount: failed,
      offeredTypeIDs: Array(offeredTypeIDs),
      offers: offers
    )
  }
}
