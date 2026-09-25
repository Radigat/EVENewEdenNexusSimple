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

public struct LoyaltyStoreCatalogSnapshot: Codable, Equatable, Sendable {
  public let id: UUID
  public let fetchedAt: Date
  public let expiresAt: Date?
  public let corporationCount: Int
  public let successfulCorporationCount: Int
  public let failedCorporationCount: Int
  public let offeredTypeIDs: [Int64]

  public init(
    id: UUID = UUID(),
    fetchedAt: Date,
    expiresAt: Date?,
    corporationCount: Int,
    successfulCorporationCount: Int,
    failedCorporationCount: Int,
    offeredTypeIDs: [Int64]
  ) {
    self.id = id
    self.fetchedAt = fetchedAt
    self.expiresAt = expiresAt
    self.corporationCount = corporationCount
    self.successfulCorporationCount = successfulCorporationCount
    self.failedCorporationCount = failedCorporationCount
    self.offeredTypeIDs = Array(Set(offeredTypeIDs.filter { $0 > 0 })).sorted()
  }

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

  public func refresh() async throws -> LoyaltyStoreCatalogSnapshot {
    let corporations = try await esi.get(
      [Int64].self,
      endpoint: ESIEndpoint(path: "/corporations/npccorps")
    )
    let corporationIDs = Array(
      Set(corporations.value.filter { $0 > 0 })
    ).sorted().prefix(500)
    var offeredTypeIDs = Set<Int64>()
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
      offeredTypeIDs: Array(offeredTypeIDs)
    )
  }
}
