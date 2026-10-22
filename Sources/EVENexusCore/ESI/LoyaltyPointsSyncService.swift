import Foundation

public struct ESILoyaltyPointsDTO: Codable, Equatable, Sendable {
  public let corporationID: Int64
  public let loyaltyPoints: Int64

  private enum CodingKeys: String, CodingKey {
    case corporationID = "corporation_id"
    case loyaltyPoints = "loyalty_points"
  }
}

/// Saved Loyalty Points of every synchronized character. A character without
/// an entry has unknown LP, never zero.
public struct CharacterLoyaltyPointsSnapshot: Codable, Equatable, Sendable {
  public struct CharacterEntry: Codable, Equatable, Sendable {
    public let characterID: Int64
    public let characterName: String
    public let capturedAt: Date
    public let points: [Int64: Int64]

    public init(
      characterID: Int64,
      characterName: String,
      capturedAt: Date,
      points: [Int64: Int64]
    ) {
      self.characterID = characterID
      self.characterName = characterName
      self.capturedAt = capturedAt
      self.points = points
    }
  }

  public var characters: [Int64: CharacterEntry]

  public init(characters: [Int64: CharacterEntry] = [:]) {
    self.characters = characters
  }

  public var flattened: [CharacterLoyaltyPoints] {
    characters.values.flatMap { entry in
      entry.points.map {
        CharacterLoyaltyPoints(
          characterID: entry.characterID,
          characterName: entry.characterName,
          corporationID: $0.key,
          points: $0.value
        )
      }
    }
  }
}

public actor CharacterLoyaltyPointsStore {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> CharacterLoyaltyPointsSnapshot? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }
    return try JSONDecoder().decode(
      CharacterLoyaltyPointsSnapshot.self,
      from: Data(contentsOf: fileURL)
    )
  }

  public func save(_ snapshot: CharacterLoyaltyPointsSnapshot) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
  }
}

public struct LoyaltyPointsSyncService: Sendable {
  public static let requiredScope = "esi-characters.read_loyalty.v1"

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronize(
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> [Int64: Int64] {
    guard lease.scopes.contains(Self.requiredScope) else {
      throw ESIError.missingScope(Self.requiredScope)
    }
    let response = try await esi.get(
      [ESILoyaltyPointsDTO].self,
      endpoint: ESIEndpoint(
        path: "/characters/\(characterID)/loyalty/points/",
        requiresAuthorization: true,
        requiredScope: Self.requiredScope
      ),
      lease: lease
    )
    var points: [Int64: Int64] = [:]
    for entry in response.value where entry.corporationID > 0 {
      points[entry.corporationID] = max(0, entry.loyaltyPoints)
    }
    return points
  }
}
