import Foundation
import Security

public struct PendingAuthorization: Sendable {
  public let authorizationURL: URL
  public let state: String
  public let verifier: String
}

public struct SSOTokenResponse: Decodable, Sendable {
  public let accessToken: String
  public let expiresIn: Int
  public let refreshToken: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
  }
}

public protocol TokenExchanging: Sendable {
  func exchange(
    code: String,
    verifier: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse

  func refresh(
    refreshToken: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse
}

public struct VerifiedEVEIdentity: Sendable {
  public let characterID: Int64
  public let characterName: String
  public let scopes: Set<String>
  public let expiresAt: Date
}

public protocol EVEIdentityVerifying: Sendable {
  func verify(accessToken: String) async throws -> VerifiedEVEIdentity
}

public struct LiveEVEIdentityVerifier: EVEIdentityVerifying, Sendable {
  private static let maximumIdentityResponseBytes = 1 * 1_024 * 1_024
  private static let maximumTokenBytes = 32 * 1_024

  private let clientID: String
  private let session: URLSession

  public init(
    clientID: String,
    session: URLSession? = nil
  ) {
    self.clientID = clientID
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 30
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      self.session = URLSession(configuration: configuration)
    }
  }

  public func verify(accessToken: String) async throws -> VerifiedEVEIdentity {
    guard !accessToken.isEmpty,
      accessToken.utf8.count <= Self.maximumTokenBytes
    else { throw AuthError.invalidIdentityToken }
    let components = accessToken.split(separator: ".")
    guard components.count == 3,
      let headerData = Data(base64URLEncoded: String(components[0])),
      let claimsData = Data(base64URLEncoded: String(components[1])),
      let signature = Data(base64URLEncoded: String(components[2])),
      headerData.count <= 8 * 1_024,
      claimsData.count <= 24 * 1_024,
      signature.count <= 8 * 1_024,
      let signingInput = "\(components[0]).\(components[1])".data(using: .utf8)
    else { throw AuthError.invalidIdentityToken }

    let decoder = JSONDecoder()
    guard
      let header = try? decoder.decode(JWTHeader.self, from: headerData),
      ["RS256", "ES256"].contains(header.algorithm),
      !header.keyID.isEmpty,
      header.keyID.utf8.count <= 256,
      let claims = try? decoder.decode(JWTClaims.self, from: claimsData)
    else { throw AuthError.invalidIdentityToken }

    let metadata: SSOMetadata = try await fetch(
      URL(
        string:
          "https://login.eveonline.com/.well-known/oauth-authorization-server"
      )!
    )
    let keySet: JSONWebKeySet = try await fetch(metadata.jwksURI)
    guard
      let webKey = keySet.keys.first(where: {
        $0.keyID == header.keyID && $0.algorithm == header.algorithm
      }),
      webKey.verifies(message: signingInput, signature: signature)
    else { throw AuthError.invalidIdentityToken }

    let acceptedIssuers: Set<String> = [
      "https://login.eveonline.com/",
      "https://login.eveonline.com",
      "login.eveonline.com",
    ]
    guard acceptedIssuers.contains(claims.issuer),
      claims.audiences.contains("EVE Online"),
      claims.audiences.contains(clientID),
      claims.expiration > Date().timeIntervalSince1970,
      claims.subject.hasPrefix("CHARACTER:EVE:"),
      let characterID = Int64(
        claims.subject.dropFirst("CHARACTER:EVE:".count)
      ),
      characterID > 0,
      !claims.name.isEmpty,
      claims.name.utf8.count <= 256,
      claims.scopes.count <= 128,
      claims.scopes.allSatisfy({
        !$0.isEmpty && $0.utf8.count <= 256
      })
    else { throw AuthError.invalidIdentityToken }

    return VerifiedEVEIdentity(
      characterID: characterID,
      characterName: claims.name,
      scopes: Set(claims.scopes),
      expiresAt: Date(timeIntervalSince1970: claims.expiration)
    )
  }

  private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
    guard Self.isAllowedIdentityServiceURL(url) else {
      throw AuthError.invalidIdentityToken
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode),
      let responseURL = http.url,
      Self.isAllowedIdentityServiceURL(responseURL),
      data.count <= Self.maximumIdentityResponseBytes
    else { throw AuthError.invalidIdentityToken }
    if let rawLength = http.value(forHTTPHeaderField: "Content-Length") {
      guard let length = Int64(rawLength),
        length >= 0,
        length <= Int64(Self.maximumIdentityResponseBytes)
      else { throw AuthError.invalidIdentityToken }
    }
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw AuthError.invalidIdentityToken
    }
  }

  private static func isAllowedIdentityServiceURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && url.host?.lowercased() == "login.eveonline.com"
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
  }
}

private struct SSOMetadata: Decodable {
  let jwksURI: URL

  enum CodingKeys: String, CodingKey {
    case jwksURI = "jwks_uri"
  }
}

struct JSONWebKeySet: Decodable {
  let keys: [JSONWebKey]
}

struct JSONWebKey: Decodable {
  let keyType: String
  let keyID: String
  let use: String?
  let algorithm: String
  let modulus: String?
  let exponent: String?
  let curve: String?
  let xCoordinate: String?
  let yCoordinate: String?

  enum CodingKeys: String, CodingKey {
    case keyType = "kty"
    case keyID = "kid"
    case use
    case algorithm = "alg"
    case modulus = "n"
    case exponent = "e"
    case curve = "crv"
    case xCoordinate = "x"
    case yCoordinate = "y"
  }

  func verifies(message: Data, signature: Data) -> Bool {
    guard use == nil || use == "sig" else { return false }
    switch algorithm {
    case "RS256":
      guard let key = rsaSecurityKey else { return false }
      return SecKeyVerifySignature(
        key,
        .rsaSignatureMessagePKCS1v15SHA256,
        message as CFData,
        signature as CFData,
        nil
      )
    case "ES256":
      guard let key = ecSecurityKey,
        let derSignature = ASN1.ecdsaSignature(fromJOSE: signature)
      else { return false }
      return SecKeyVerifySignature(
        key,
        .ecdsaSignatureMessageX962SHA256,
        message as CFData,
        derSignature as CFData,
        nil
      )
    default:
      return false
    }
  }

  private var rsaSecurityKey: SecKey? {
    guard keyType == "RSA",
      let modulus,
      let exponent,
      let modulusData = Data(base64URLEncoded: modulus),
      let exponentData = Data(base64URLEncoded: exponent)
    else { return nil }
    let keyData = ASN1.sequence(
      ASN1.integer(modulusData) + ASN1.integer(exponentData)
    )
    return SecKeyCreateWithData(
      keyData as CFData,
      [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: modulusData.count * 8,
      ] as CFDictionary,
      nil
    )
  }

  private var ecSecurityKey: SecKey? {
    guard keyType == "EC",
      curve == "P-256",
      let xCoordinate,
      let yCoordinate,
      let x = Data(base64URLEncoded: xCoordinate),
      let y = Data(base64URLEncoded: yCoordinate),
      x.count == 32,
      y.count == 32
    else { return nil }
    let keyData = Data([0x04]) + x + y
    return SecKeyCreateWithData(
      keyData as CFData,
      [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: 256,
      ] as CFDictionary,
      nil
    )
  }
}

private struct JWTHeader: Decodable {
  let keyID: String
  let algorithm: String

  enum CodingKeys: String, CodingKey {
    case keyID = "kid"
    case algorithm = "alg"
  }
}

private struct JWTClaims: Decodable {
  let issuer: String
  let audiences: [String]
  let expiration: TimeInterval
  let subject: String
  let name: String
  let scopes: [String]

  enum CodingKeys: String, CodingKey {
    case issuer = "iss"
    case audiences = "aud"
    case expiration = "exp"
    case subject = "sub"
    case name
    case scopes = "scp"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    issuer = try values.decode(String.self, forKey: .issuer)
    expiration = try values.decode(TimeInterval.self, forKey: .expiration)
    subject = try values.decode(String.self, forKey: .subject)
    name = try values.decode(String.self, forKey: .name)
    if let list = try? values.decode([String].self, forKey: .audiences) {
      audiences = list
    } else {
      audiences = [
        try values.decode(String.self, forKey: .audiences)
      ]
    }
    if let list = try? values.decode([String].self, forKey: .scopes) {
      scopes = list
    } else {
      scopes = try values.decode(String.self, forKey: .scopes)
        .split(separator: " ")
        .map(String.init)
    }
  }
}

private enum ASN1 {
  static func sequence(_ contents: Data) -> Data {
    Data([0x30]) + length(contents.count) + contents
  }

  static func integer(_ bytes: Data) -> Data {
    var normalized = Data(bytes.drop(while: { $0 == 0 }))
    if normalized.isEmpty { normalized = Data([0]) }
    if normalized.first.map({ $0 & 0x80 != 0 }) == true {
      normalized.insert(0, at: 0)
    }
    return Data([0x02]) + length(normalized.count) + normalized
  }

  static func ecdsaSignature(fromJOSE signature: Data) -> Data? {
    guard signature.count == 64 else { return nil }
    let midpoint = signature.index(signature.startIndex, offsetBy: 32)
    let r = Data(signature[..<midpoint])
    let s = Data(signature[midpoint...])
    return sequence(integer(r) + integer(s))
  }

  private static func length(_ count: Int) -> Data {
    if count < 0x80 { return Data([UInt8(count)]) }
    var value = count
    var bytes: [UInt8] = []
    while value > 0 {
      bytes.insert(UInt8(value & 0xff), at: 0)
      value >>= 8
    }
    return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
  }
}

extension Data {
  fileprivate init?(base64URLEncoded value: String) {
    var base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    self.init(base64Encoded: base64)
  }
}

public struct LiveTokenExchange: TokenExchanging, Sendable {
  private let session: URLSession

  public init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 30
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      self.session = URLSession(configuration: configuration)
    }
  }

  public func exchange(
    code: String,
    verifier: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    try await request(
      fields: [
        "grant_type": "authorization_code",
        "code": code,
        "client_id": configuration.clientID,
        "code_verifier": verifier,
      ]
    )
  }

  public func refresh(
    refreshToken: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    try await request(
      fields: [
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": configuration.clientID,
      ]
    )
  }

  private func request(fields: [String: String]) async throws
    -> SSOTokenResponse
  {
    var request = URLRequest(
      url: URL(string: "https://login.eveonline.com/v2/oauth/token")!
    )
    request.timeoutInterval = 30
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody =
      fields
      .sorted(by: { $0.key < $1.key })
      .map {
        "\($0.key.urlQueryEncoded)=\($0.value.urlQueryEncoded)"
      }
      .joined(separator: "&")
      .data(using: .utf8)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AuthError.invalidTokenResponse
    }
    guard data.count <= 1 * 1_024 * 1_024 else {
      throw AuthError.invalidTokenResponse
    }
    if let rawLength = http.value(forHTTPHeaderField: "Content-Length") {
      guard let length = Int64(rawLength),
        length >= 0,
        length <= 1 * 1_024 * 1_024
      else { throw AuthError.invalidTokenResponse }
    }
    guard (200..<300).contains(http.statusCode) else {
      throw AuthError.tokenExchangeFailed(http.statusCode)
    }
    do {
      return try JSONDecoder().decode(SSOTokenResponse.self, from: data)
    } catch {
      throw AuthError.invalidTokenResponse
    }
  }
}

public actor EVESSOService {
  private struct AuthorizationAttempt: Sendable {
    let verifier: String
    let expiresAt: Date
  }

  private static let authorizationLifetime: TimeInterval = 5 * 60
  private static let maximumPendingAuthorizations = 8
  private static let maximumCredentialLength = 32 * 1_024

  private let configuration: SSOConfiguration
  private let tokenStore: any RefreshTokenStoring
  private let exchange: any TokenExchanging
  private let identityVerifier: any EVEIdentityVerifying
  private let now: @Sendable () -> Date
  private var leases: [Int64: AccessTokenLease] = [:]
  private var authorizationAttempts: [String: AuthorizationAttempt] = [:]

  public init(
    configuration: SSOConfiguration,
    tokenStore: any RefreshTokenStoring = KeychainRefreshTokenStore(),
    exchange: any TokenExchanging = LiveTokenExchange(),
    identityVerifier: (any EVEIdentityVerifying)? = nil,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.configuration = configuration
    self.tokenStore = tokenStore
    self.exchange = exchange
    self.now = now
    self.identityVerifier =
      identityVerifier
      ?? LiveEVEIdentityVerifier(clientID: configuration.clientID)
  }

  public func beginAuthorization() throws -> PendingAuthorization {
    let clientID = configuration.clientID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !clientID.isEmpty else {
      throw AuthError.missingClientID
    }
    guard clientID == configuration.clientID,
      clientID.utf8.count <= 256,
      clientID.unicodeScalars.allSatisfy({
        $0.value >= 0x21 && $0.value <= 0x7e
      })
    else {
      throw AuthError.invalidClientID
    }
    guard configuration.callbackURL == EVEConstants.callbackURL else {
      throw AuthError.invalidCallback
    }
    let currentDate = now()
    authorizationAttempts = authorizationAttempts.filter {
      $0.value.expiresAt > currentDate
    }
    if authorizationAttempts.count >= Self.maximumPendingAuthorizations,
      let oldest = authorizationAttempts.min(by: {
        $0.value.expiresAt < $1.value.expiresAt
      })
    {
      authorizationAttempts.removeValue(forKey: oldest.key)
    }
    let pkce = try PKCEChallenge.generate()
    let state = try PKCEChallenge.generate().verifier
    var components = URLComponents(
      string: "https://login.eveonline.com/v2/oauth/authorize"
    )!
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: configuration.callbackURL.absoluteString),
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "scope", value: configuration.scopes.sorted().joined(separator: " ")),
      URLQueryItem(name: "code_challenge", value: pkce.challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state),
    ]
    guard let url = components.url else { throw AuthError.invalidCallback }
    authorizationAttempts[state] = AuthorizationAttempt(
      verifier: pkce.verifier,
      expiresAt: currentDate.addingTimeInterval(
        Self.authorizationLifetime
      )
    )
    return PendingAuthorization(
      authorizationURL: url,
      state: state,
      verifier: pkce.verifier
    )
  }

  public func completeAuthorization(
    callbackURL: URL,
    pending: PendingAuthorization,
    expectedCharacterID: Int64? = nil
  ) async throws -> (AuthorizationSnapshot, AccessTokenLease) {
    guard
      let components = URLComponents(
        url: callbackURL,
        resolvingAgainstBaseURL: false
      ),
      callbackMatchesConfiguration(components)
    else { throw AuthError.invalidCallback }
    let fields = try callbackFields(components.queryItems ?? [])
    guard fields["state"] == pending.state else {
      throw AuthError.stateMismatch
    }
    let currentDate = now()
    guard
      let attempt = authorizationAttempts.removeValue(
        forKey: pending.state
      ),
      attempt.verifier == pending.verifier,
      attempt.expiresAt > currentDate
    else {
      throw AuthError.invalidAuthorizationAttempt
    }
    if let error = fields["error"] {
      guard error.utf8.count <= 64,
        !error.isEmpty,
        error.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0)
            || "_-.".unicodeScalars.contains($0)
        })
      else { throw AuthError.invalidCallback }
      throw AuthError.callbackDenied(error)
    }
    guard let code = fields["code"] else {
      throw AuthError.missingAuthorizationCode
    }
    let response = try await exchange.exchange(
      code: code,
      verifier: pending.verifier,
      configuration: configuration
    )
    try validate(response)
    let identity = try await identityVerifier.verify(
      accessToken: response.accessToken
    )
    guard identity.scopes.isSubset(of: configuration.scopes) else {
      throw AuthError.invalidIdentityToken
    }
    if let expectedCharacterID,
      identity.characterID != expectedCharacterID
    {
      throw AuthError.unexpectedCharacter(
        expected: expectedCharacterID,
        received: identity.characterID
      )
    }
    try tokenStore.save(
      response.refreshToken,
      characterID: identity.characterID
    )
    let lease = AccessTokenLease(
      characterID: identity.characterID,
      accessToken: response.accessToken,
      expiresAt: min(
        identity.expiresAt,
        currentDate.addingTimeInterval(TimeInterval(response.expiresIn))
      ),
      scopes: identity.scopes
    )
    leases[identity.characterID] = lease
    return (
      AuthorizationSnapshot(
        characterID: identity.characterID,
        characterName: identity.characterName,
        scopes: identity.scopes,
        authorizedAt: currentDate
      ),
      lease
    )
  }

  public func accessTokenLease(characterID: Int64) async throws
    -> AccessTokenLease
  {
    if let lease = leases[characterID], lease.isUsable {
      return lease
    }
    guard let refreshToken = try tokenStore.load(characterID: characterID)
    else { throw AuthError.noStoredAuthorization }
    let response = try await exchange.refresh(
      refreshToken: refreshToken,
      configuration: configuration
    )
    try validate(response)
    let identity = try await identityVerifier.verify(
      accessToken: response.accessToken
    )
    guard identity.characterID == characterID,
      identity.scopes.isSubset(of: configuration.scopes)
    else {
      throw AuthError.invalidIdentityToken
    }
    try tokenStore.save(response.refreshToken, characterID: characterID)
    let lease = AccessTokenLease(
      characterID: characterID,
      accessToken: response.accessToken,
      expiresAt: min(
        identity.expiresAt,
        now().addingTimeInterval(TimeInterval(response.expiresIn))
      ),
      scopes: identity.scopes
    )
    leases[characterID] = lease
    return lease
  }

  public func revokeLocalAuthorization(characterID: Int64) throws {
    leases.removeValue(forKey: characterID)
    try tokenStore.delete(characterID: characterID)
  }

  private func callbackMatchesConfiguration(
    _ components: URLComponents
  ) -> Bool {
    let expected = URLComponents(
      url: configuration.callbackURL,
      resolvingAgainstBaseURL: false
    )
    return components.scheme?.lowercased() == expected?.scheme?.lowercased()
      && components.host?.lowercased() == expected?.host?.lowercased()
      && components.port == expected?.port
      && components.path == expected?.path
      && components.user == nil
      && components.password == nil
      && components.fragment == nil
  }

  private func callbackFields(
    _ queryItems: [URLQueryItem]
  ) throws -> [String: String] {
    var fields: [String: String] = [:]
    for item in queryItems {
      guard let value = item.value,
        value.utf8.count <= 4_096,
        fields[item.name] == nil
      else {
        throw AuthError.invalidCallback
      }
      fields[item.name] = value
    }
    guard fields["state"] != nil,
      !((fields["code"] != nil) && (fields["error"] != nil))
    else {
      throw AuthError.invalidCallback
    }
    return fields
  }

  private func validate(_ response: SSOTokenResponse) throws {
    guard response.expiresIn > 0,
      response.expiresIn <= 86_400,
      !response.accessToken.isEmpty,
      !response.refreshToken.isEmpty,
      response.accessToken.utf8.count <= Self.maximumCredentialLength,
      response.refreshToken.utf8.count <= Self.maximumCredentialLength
    else {
      throw AuthError.invalidTokenResponse
    }
  }

}

extension String {
  fileprivate var urlQueryEncoded: String {
    addingPercentEncoding(
      withAllowedCharacters: .alphanumerics
    ) ?? self
  }
}
