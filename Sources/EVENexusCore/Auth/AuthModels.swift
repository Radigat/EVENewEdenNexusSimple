import Foundation

public struct AuthorizationSnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let characterID: Int64
  public let characterName: String
  public let scopes: Set<String>
  public let authorizedAt: Date
  public let issuer: String

  public init(
    id: UUID = UUID(),
    characterID: Int64,
    characterName: String,
    scopes: Set<String>,
    authorizedAt: Date = .now,
    issuer: String = "https://login.eveonline.com"
  ) {
    self.id = id
    self.characterID = characterID
    self.characterName = characterName
    self.scopes = scopes
    self.authorizedAt = authorizedAt
    self.issuer = issuer
  }

  public var sortedScopes: [String] {
    scopes.sorted()
  }
}

public struct AccessTokenLease: Sendable {
  public let characterID: Int64
  public let accessToken: String
  public let expiresAt: Date
  public let scopes: Set<String>

  public var isUsable: Bool {
    expiresAt.timeIntervalSinceNow > 60
  }
}

public enum EVEScope {
  public static let versionOne: Set<String> = [
    "esi-skills.read_skills.v1",
    "esi-characters.read_standings.v1",
    "esi-characters.read_corporation_roles.v1",
    "esi-characters.read_blueprints.v1",
    "esi-contracts.read_character_contracts.v1",
    "esi-assets.read_assets.v1",
    "esi-assets.read_corporation_assets.v1",
    "esi-corporations.read_divisions.v1",
    "esi-industry.read_character_jobs.v1",
    "esi-markets.read_character_orders.v1",
    "esi-markets.structure_markets.v1",
    "esi-wallet.read_character_wallet.v1",
    "esi-wallet.read_corporation_wallets.v1",
    "esi-search.search_structures.v1",
    "esi-universe.read_structures.v1",
  ]
}

public struct SSOConfiguration: Codable, Equatable, Sendable {
  public var clientID: String
  public var callbackURL: URL
  public var scopes: Set<String>

  public init(
    clientID: String,
    callbackURL: URL = EVEConstants.callbackURL,
    scopes: Set<String> = EVEScope.versionOne
  ) {
    self.clientID = clientID
    self.callbackURL = callbackURL
    self.scopes = scopes
  }
}

public enum AuthError: Error, Equatable, Sendable {
  case missingClientID
  case invalidClientID
  case invalidCallback
  case invalidAuthorizationAttempt
  case stateMismatch
  case callbackDenied(String)
  case missingAuthorizationCode
  case tokenExchangeFailed(Int)
  case invalidTokenResponse
  case invalidIdentityToken
  case unexpectedCharacter(expected: Int64, received: Int64)
  case keychain(Int32)
  case keychainFallback(protected: Int32, legacy: Int32)
  case noStoredAuthorization
}
