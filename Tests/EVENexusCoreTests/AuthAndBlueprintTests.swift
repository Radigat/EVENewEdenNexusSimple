import Foundation
import Testing

@testable import EVENexusCore

@Suite("Authentication and blueprint boundaries")
struct AuthAndBlueprintTests {
  @Test
  func pkceUsesS256SafeValues() throws {
    let value = try PKCEChallenge.generate()

    #expect(value.verifier.count >= 43)
    #expect(value.challenge.count == 43)
    #expect(!value.verifier.contains("+"))
    #expect(!value.challenge.contains("="))
  }

  @Test
  func simpleAppUsesItsOwnRegisteredLoopbackCallback() {
    #expect(
      EVEConstants.callbackURL.absoluteString
        == "http://localhost:52722/callback"
    )
    #expect(EVEConstants.callbackPort == 52_722)
  }

  @Test
  func authorizationSnapshotExposesOnlyItsOwnScopesInStableOrder() {
    let snapshot = AuthorizationSnapshot(
      characterID: 42,
      characterName: "Fixture Pilot",
      scopes: [
        "esi-wallet.read_character_wallet.v1",
        "esi-assets.read_assets.v1",
        "esi-skills.read_skills.v1",
      ]
    )

    #expect(
      snapshot.sortedScopes == [
        "esi-assets.read_assets.v1",
        "esi-skills.read_skills.v1",
        "esi-wallet.read_character_wallet.v1",
      ]
    )
  }

  @Test
  func reusableSSOSessionDoesNotReloadKeychainForUsableLease() async throws {
    let store = CountingRefreshTokenStore(token: "refresh-token")
    let exchange = CountingTokenExchange()
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: store,
      exchange: exchange,
      identityVerifier: FixtureIdentityVerifier()
    )

    let first = try await service.accessTokenLease(characterID: 42)
    let second = try await service.accessTokenLease(characterID: 42)
    let refreshCount = await exchange.refreshCount

    #expect(first.accessToken == "access-token")
    #expect(second.accessToken == first.accessToken)
    #expect(store.loadCount == 1)
    #expect(refreshCount == 1)
  }

  @Test
  func genericAuthorizationStoresTheVerifiedCharacterIdentity() async throws {
    let store = CountingRefreshTokenStore(token: nil)
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: store,
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    let callback = callbackURL(for: pending)

    let result = try await service.completeAuthorization(
      callbackURL: callback,
      pending: pending
    )

    #expect(result.0.characterID == 42)
    #expect(result.0.characterName == "Fixture Pilot")
    #expect(store.savedCharacterIDs == [42])
  }

  @Test
  func batchReauthorizationRejectsWrongCharacterBeforeSavingToken()
    async throws
  {
    let store = CountingRefreshTokenStore(token: nil)
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: store,
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    let callback = callbackURL(for: pending)

    await #expect(
      throws: AuthError.unexpectedCharacter(expected: 7, received: 42)
    ) {
      _ = try await service.completeAuthorization(
        callbackURL: callback,
        pending: pending,
        expectedCharacterID: 7
      )
    }
    #expect(store.saveCount == 0)
  }

  @Test
  func callbackRejectsDuplicateParametersWithoutCrashing() async throws {
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: CountingRefreshTokenStore(token: nil),
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    var components = URLComponents(
      url: callbackURL(for: pending),
      resolvingAgainstBaseURL: false
    )!
    components.queryItems?.append(
      URLQueryItem(name: "state", value: pending.state)
    )

    await #expect(throws: AuthError.invalidCallback) {
      _ = try await service.completeAuthorization(
        callbackURL: components.url!,
        pending: pending
      )
    }
  }

  @Test
  func callbackMustMatchRegisteredLoopbackURLExactly() async throws {
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: CountingRefreshTokenStore(token: nil),
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    var components = URLComponents(
      url: callbackURL(for: pending),
      resolvingAgainstBaseURL: false
    )!
    components.path = "/not-the-registered-callback"

    await #expect(throws: AuthError.invalidCallback) {
      _ = try await service.completeAuthorization(
        callbackURL: components.url!,
        pending: pending
      )
    }
  }

  @Test
  func authorizationAttemptCannotBeReplayed() async throws {
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: CountingRefreshTokenStore(token: nil),
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    let callback = callbackURL(for: pending)

    _ = try await service.completeAuthorization(
      callbackURL: callback,
      pending: pending
    )
    await #expect(throws: AuthError.invalidAuthorizationAttempt) {
      _ = try await service.completeAuthorization(
        callbackURL: callback,
        pending: pending
      )
    }
  }

  @Test
  func revokingLocalAuthorizationDeletesTokenAndCachedLease() async throws {
    let store = CountingRefreshTokenStore(token: "refresh-token")
    let exchange = CountingTokenExchange()
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: store,
      exchange: exchange,
      identityVerifier: FixtureIdentityVerifier()
    )

    _ = try await service.accessTokenLease(characterID: 42)
    try await service.revokeLocalAuthorization(characterID: 42)

    #expect(store.deleteCount == 1)
    await #expect(throws: AuthError.noStoredAuthorization) {
      _ = try await service.accessTokenLease(characterID: 42)
    }
  }

  @Test
  func callbackRejectsUntrustedErrorText() async throws {
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: "fixture-client"),
      tokenStore: CountingRefreshTokenStore(token: nil),
      exchange: SuccessfulTokenExchange(),
      identityVerifier: FixtureIdentityVerifier()
    )
    let pending = try await service.beginAuthorization()
    var components = URLComponents(
      url: EVEConstants.callbackURL,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "error", value: "<script>alert(1)</script>"),
      URLQueryItem(name: "state", value: pending.state),
    ]

    await #expect(throws: AuthError.invalidCallback) {
      _ = try await service.completeAuthorization(
        callbackURL: components.url!,
        pending: pending
      )
    }
  }

  @Test
  func loopbackParserRejectsWrongStateAndAcceptsFragmentedRequestShape() {
    let valid =
      "GET /callback?code=fixture&state=expected HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let wrongState =
      "GET /callback?code=fixture&state=attacker HTTP/1.1\r\nHost: localhost\r\n\r\n"
    let wrongPath =
      "GET /other?code=fixture&state=expected HTTP/1.1\r\nHost: localhost\r\n\r\n"

    #expect(
      LoopbackCallbackRequestParser.parse(
        valid,
        expectedState: "expected"
      )?.path == "/callback"
    )
    #expect(
      LoopbackCallbackRequestParser.parse(
        wrongState,
        expectedState: "expected"
      ) == nil
    )
    #expect(
      LoopbackCallbackRequestParser.parse(
        wrongPath,
        expectedState: "expected"
      ) == nil
    )
  }

  @Test
  func mixedRSAAndECKeySetDecodesWithoutDroppingAllKeys() throws {
    let fixture = Data(
      """
      {
        "keys": [
          {
            "kty": "RSA",
            "kid": "rsa",
            "use": "sig",
            "alg": "RS256",
            "n": "AQ",
            "e": "AQAB"
          },
          {
            "kty": "EC",
            "kid": "ec",
            "use": "sig",
            "alg": "ES256",
            "crv": "P-256",
            "x": "AQ",
            "y": "Ag"
          }
        ]
      }
      """.utf8
    )

    let keySet = try JSONDecoder().decode(
      JSONWebKeySet.self,
      from: fixture
    )

    #expect(keySet.keys.count == 2)
    #expect(keySet.keys.map(\.algorithm) == ["RS256", "ES256"])
  }

  @Test
  func blueprintKindComesFromBlueprintEndpointQuantity() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let original = OwnedBlueprintInstance(
      id: 1,
      blueprintTypeID: 2,
      locationID: 3,
      quantity: -1,
      runs: -1,
      materialEfficiency: 10,
      timeEfficiency: 20,
      source: source
    )
    let copy = OwnedBlueprintInstance(
      id: 2,
      blueprintTypeID: 2,
      locationID: 3,
      quantity: -2,
      runs: 4,
      materialEfficiency: 10,
      timeEfficiency: 20,
      source: source
    )

    #expect(original.kind == .original)
    #expect(copy.kind == .copy)
    #expect(copy.runs == 4)
  }

  @Test
  func researchCostUsesLevelMultipliersAndSeparateFacilityContexts() throws {
    let source = SourceIdentity(
      provider: "fixture",
      version: "1",
      capturedAt: .distantPast
    )
    let original = OwnedBlueprintInstance(
      id: 1,
      blueprintTypeID: 100,
      locationID: 3,
      quantity: -1,
      runs: -1,
      materialEfficiency: 2,
      timeEfficiency: 4,
      source: source
    )
    let definition = BlueprintResearchDefinition(
      blueprintTypeID: 100,
      blueprintName: "Fixture Blueprint",
      basePrice: 1_000,
      manufacturingMaterials: [
        BlueprintMaterial(typeID: 2, quantity: 7)
      ],
      materialResearchTimeSeconds: 60,
      timeResearchTimeSeconds: 60,
      source: source
    )
    let materialFacility = BlueprintResearchFacilityContext(
      activity: .materialEfficiency,
      solarSystemID: 30_000_142,
      solarSystemName: "Jita",
      facilityName: "Fixture Lab",
      systemCostIndex: 0.1,
      jobCostMultiplier: 0.9,
      facilityTaxRate: 0.01,
      sccSurchargeRate: 0.02,
      alphaSurchargeRate: 0,
      needsReview: false,
      source: source
    )
    let timeFacility = BlueprintResearchFacilityContext(
      activity: .timeEfficiency,
      solarSystemID: 30_000_142,
      solarSystemName: "Jita",
      facilityName: "Fixture Lab",
      systemCostIndex: 0.2,
      jobCostMultiplier: 1,
      facilityTaxRate: 0,
      sccSurchargeRate: 0.02,
      alphaSurchargeRate: 0,
      needsReview: false,
      source: source
    )
    let pricing = BlueprintResearchPricingInput(
      adjustedPrices: [
        2: AdjustedPrice(
          typeID: 2,
          adjustedPrice: 100,
          averagePrice: nil
        )
      ],
      adjustedPriceSource: source,
      materialFacility: materialFacility,
      timeFacility: timeFacility
    )
    let quote = BlueprintResearchCostCalculator.quote(
      instance: original,
      definition: definition,
      pricing: pricing,
      calculatedAt: .distantPast
    )

    #expect(quote.manufacturingBaseCost == 700)
    #expect(abs(try #require(quote.levels[0].materialStepCost) - 1.68) < 0.000_001)
    #expect(abs(try #require(quote.currentMaterialResearchValue) - 4) < 0.000_001)
    #expect(
      abs(try #require(quote.currentTimeResearchValue) - 7.333_333_333)
        < 0.000_001
    )
    #expect(
      abs(try #require(quote.estimatedReplacementValue) - 1_011.333_333_333)
        < 0.000_001
    )
    #expect(quote.ruleVersion == "ccp-blueprint-research-2026-07-v1")

    let asymmetricQuote = BlueprintResearchCostCalculator.quote(
      instance: OwnedBlueprintInstance(
        id: 2,
        blueprintTypeID: 100,
        locationID: 3,
        quantity: -1,
        runs: -1,
        materialEfficiency: 9,
        timeEfficiency: 14,
        source: source
      ),
      definition: definition,
      pricing: pricing,
      calculatedAt: .distantPast
    )
    #expect(asymmetricQuote.isMaterialLevelResearched(9))
    #expect(!asymmetricQuote.isMaterialLevelResearched(10))
    #expect(asymmetricQuote.isTimeLevelResearched(7))
    #expect(!asymmetricQuote.isTimeLevelResearched(8))
  }

  @Test
  func copiesAndUnverifiedResearchMaterialsNeverGainInventedValue() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let copy = OwnedBlueprintInstance(
      id: 2,
      blueprintTypeID: 100,
      locationID: 3,
      quantity: -2,
      runs: 4,
      materialEfficiency: 10,
      timeEfficiency: 20,
      source: source
    )
    let definition = BlueprintResearchDefinition(
      blueprintTypeID: 100,
      blueprintName: "Fixture Blueprint",
      basePrice: 1_000,
      manufacturingMaterials: [
        BlueprintMaterial(typeID: 2, quantity: 7)
      ],
      materialResearchMaterials: [
        BlueprintMaterial(typeID: 3, quantity: 1)
      ],
      materialResearchTimeSeconds: 60,
      timeResearchTimeSeconds: 60,
      source: source
    )
    let quote = BlueprintResearchCostCalculator.quote(
      instance: copy,
      definition: definition,
      pricing: BlueprintResearchPricingInput(
        adjustedPrices: [
          2: AdjustedPrice(
            typeID: 2,
            adjustedPrice: 100,
            averagePrice: nil
          )
        ],
        adjustedPriceSource: source,
        materialFacility: nil,
        timeFacility: nil
      )
    )

    #expect(!quote.isResearchable)
    #expect(quote.estimatedReplacementValue == nil)
    #expect(
      quote.warnings.contains {
        $0.code == "blueprint.copy-not-researchable"
      }
    )
    #expect(
      quote.warnings.contains {
        $0.code == "blueprint.research-additional-materials"
          && $0.severity == .blocking
      }
    )
  }

  @Test
  func blueprintPortfolioPreservesOwnerAndUnavailableSourceState() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let original = OwnedBlueprintInstance(
      id: 1,
      blueprintTypeID: 100,
      locationID: 3,
      quantity: -1,
      runs: -1,
      materialEfficiency: 0,
      timeEfficiency: 0,
      source: source
    )
    let portfolio = BlueprintPortfolio(
      inventories: [
        OwnedBlueprintInventory(
          ownerID: 2,
          ownerName: "Zulu",
          blueprints: Sourced(
            state: .unavailable,
            value: nil,
            source: source
          )
        ),
        OwnedBlueprintInventory(
          ownerID: 1,
          ownerName: "Alpha",
          blueprints: Sourced(
            state: .fresh,
            value: [original],
            source: source
          )
        ),
      ]
    )

    #expect(portfolio.entries.map(\.ownerName) == ["Alpha"])
    #expect(portfolio.sourceStates == [.fresh, .unavailable])
  }

  @Test
  func missingSkillsRemainUnknown() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let snapshot = CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: 1, name: "Pilot"),
      cloneState: .unknown,
      skills: Sourced(
        state: .forbidden,
        value: nil,
        source: source
      ),
      standings: Sourced(
        state: .fresh,
        value: [:],
        source: source
      )
    )

    #expect(snapshot.skillLevel(3380) == nil)
  }

  private func callbackURL(for pending: PendingAuthorization) -> URL {
    var components = URLComponents(
      url: EVEConstants.callbackURL,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "code", value: "fixture"),
      URLQueryItem(name: "state", value: pending.state),
    ]
    return components.url!
  }
}

private final class CountingRefreshTokenStore:
  RefreshTokenStoring, @unchecked Sendable
{
  private let lock = NSLock()
  private var token: String?
  private var recordedLoadCount = 0
  private var recordedSaveCount = 0
  private var recordedDeleteCount = 0
  private var recordedSavedCharacterIDs: [Int64] = []

  init(token: String?) {
    self.token = token
  }

  var loadCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return recordedLoadCount
  }

  var saveCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return recordedSaveCount
  }

  var savedCharacterIDs: [Int64] {
    lock.lock()
    defer { lock.unlock() }
    return recordedSavedCharacterIDs
  }

  var deleteCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return recordedDeleteCount
  }

  func save(_ token: String, characterID: Int64) throws {
    lock.lock()
    defer { lock.unlock() }
    recordedSaveCount += 1
    recordedSavedCharacterIDs.append(characterID)
    self.token = token
  }

  func load(characterID: Int64) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    recordedLoadCount += 1
    return token
  }

  func delete(characterID: Int64) throws {
    lock.lock()
    defer { lock.unlock() }
    recordedDeleteCount += 1
    token = nil
  }
}

private actor SuccessfulTokenExchange: TokenExchanging {
  func exchange(
    code: String,
    verifier: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    SSOTokenResponse(
      accessToken: "access-token",
      expiresIn: 3_600,
      refreshToken: "refresh-token"
    )
  }

  func refresh(
    refreshToken: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    throw AuthError.invalidTokenResponse
  }
}

private actor CountingTokenExchange: TokenExchanging {
  private(set) var refreshCount = 0

  func exchange(
    code: String,
    verifier: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    throw AuthError.invalidTokenResponse
  }

  func refresh(
    refreshToken: String,
    configuration: SSOConfiguration
  ) async throws -> SSOTokenResponse {
    refreshCount += 1
    return SSOTokenResponse(
      accessToken: "access-token",
      expiresIn: 3_600,
      refreshToken: "rotated-refresh-token"
    )
  }
}

private struct FixtureIdentityVerifier: EVEIdentityVerifying {
  func verify(accessToken: String) async throws -> VerifiedEVEIdentity {
    VerifiedEVEIdentity(
      characterID: 42,
      characterName: "Fixture Pilot",
      scopes: EVEScope.versionOne,
      expiresAt: Date().addingTimeInterval(3_600)
    )
  }
}
