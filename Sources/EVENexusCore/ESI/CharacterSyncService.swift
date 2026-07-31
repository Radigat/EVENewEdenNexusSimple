import Foundation

public struct CharacterSyncSnapshot: Identifiable, Sendable {
  public let id: UUID
  public let authorization: AuthorizationSnapshot
  public let capabilities: CharacterCapabilitySnapshot
  public let assets: Sourced<AssetSnapshot>
  public let blueprints: Sourced<[OwnedBlueprintInstance]>
  public let jobs: Sourced<[ESIIndustryJobDTO]>
  public let openOrders: Sourced<[ESICharacterOrderDTO]>
  public let orderHistory: Sourced<[ESICharacterOrderDTO]>
  public let walletBalance: Sourced<Double>
  public let walletJournal: Sourced<[ESIWalletJournalDTO]>
  public let walletTransactions: Sourced<[ESIWalletTransactionDTO]>
}

public struct CharacterSyncService: Sendable {
  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronizeCapabilities(
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease
  ) async -> CharacterCapabilitySnapshot {
    async let skillsResult = capture {
      try await esi.get(
        ESISkillsDTO.self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "skills"
        ),
        lease: lease
      )
    }
    async let standingsResult = capture {
      try await esi.get(
        [ESIStandingDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "standings"
        ),
        lease: lease
      )
    }
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    return CharacterCapabilitySnapshot(
      character: CharacterIdentity(
        id: authorization.characterID,
        name: authorization.characterName
      ),
      cloneState: .unknown,
      skills: sourceValue(
        await skillsResult,
        transform: {
          $0.skills.map {
            TrainedSkill(
              skillID: $0.skillID,
              trainedLevel: $0.trainedSkillLevel,
              activeLevel: $0.activeSkillLevel,
              skillpoints: $0.skillpointsInSkill
            )
          }
        },
        fallbackSource: source
      ),
      standings: sourceValue(
        await standingsResult,
        transform: {
          Dictionary(uniqueKeysWithValues: $0.map { ($0.fromID, $0.standing) })
        },
        fallbackSource: source
      )
    )
  }

  public func synchronize(
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease
  ) async -> CharacterSyncSnapshot {
    async let publicResult = capture {
      try await esi.get(
        ESICharacterPublicDTO.self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/"
        )
      )
    }
    async let skillsResult = capture {
      try await esi.get(
        ESISkillsDTO.self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "skills"
        ),
        lease: lease
      )
    }
    async let standingsResult = capture {
      try await esi.get(
        [ESIStandingDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "standings"
        ),
        lease: lease
      )
    }
    async let assetsResult = capture {
      try await esi.getAllPages(
        [ESIAssetDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "assets"
        ),
        lease: lease
      )
    }
    async let blueprintsResult = capture {
      try await esi.getAllPages(
        [ESIBlueprintDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "blueprints"
        ),
        lease: lease
      )
    }
    async let jobsResult = capture {
      try await esi.getAllPages(
        [ESIIndustryJobDTO].self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/industry/jobs/",
          query: [
            URLQueryItem(name: "include_completed", value: "true")
          ],
          requiresAuthorization: true,
          requiredScope: "esi-industry.read_character_jobs.v1"
        ),
        lease: lease
      )
    }
    async let openOrdersResult = capture {
      try await esi.getAllPages(
        [ESICharacterOrderDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "orders"
        ),
        lease: lease
      )
    }
    async let historyResult = capture {
      try await esi.getAllPages(
        [ESICharacterOrderDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "orders/history"
        ),
        lease: lease
      )
    }
    async let balanceResult = capture {
      try await esi.get(
        Double.self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "wallet"
        ),
        lease: lease
      )
    }
    async let journalResult = capture {
      try await esi.getAllPages(
        [ESIWalletJournalDTO].self,
        endpoint: privateEndpoint(
          characterID: authorization.characterID,
          suffix: "wallet/journal"
        ),
        lease: lease
      )
    }
    async let transactionsResult = capture {
      try await walletTransactions(
        characterID: authorization.characterID,
        lease: lease
      )
    }

    let publicResponse = await publicResult
    let skillsResponse = await skillsResult
    let standingsResponse = await standingsResult
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    let publicDTO = publicResponse.value?.value
    let identity = CharacterIdentity(
      id: authorization.characterID,
      name: publicDTO?.name ?? authorization.characterName,
      corporationID: publicDTO?.corporationID
    )
    let skills = sourceValue(
      skillsResponse,
      transform: {
        $0.skills.map {
          TrainedSkill(
            skillID: $0.skillID,
            trainedLevel: $0.trainedSkillLevel,
            activeLevel: $0.activeSkillLevel,
            skillpoints: $0.skillpointsInSkill
          )
        }
      },
      fallbackSource: source
    )
    let standings = sourceValue(
      standingsResponse,
      transform: {
        Dictionary(
          uniqueKeysWithValues: $0.map {
            ($0.fromID, $0.standing)
          })
      },
      fallbackSource: source
    )
    let capability = CharacterCapabilitySnapshot(
      character: identity,
      cloneState: .unknown,
      skills: skills,
      standings: standings
    )

    let assetsRaw = await assetsResult
    let assetValue = sourceValue(
      assetsRaw,
      transform: { values in
        AssetSnapshot(
          characterID: authorization.characterID,
          state: .fresh,
          items: values.map {
            AssetItem(
              id: $0.itemID,
              typeID: $0.typeID,
              quantity: $0.quantity,
              locationID: $0.locationID,
              locationKind: AssetLocationKind(
                esiValue: $0.locationType
              ),
              locationFlag: $0.locationFlag,
              singleton: $0.singleton
            )
          }
        )
      },
      fallbackSource: source
    )
    let blueprintRaw = await blueprintsResult
    let blueprintValue = sourceValue(
      blueprintRaw,
      transform: { values in
        values.map {
          OwnedBlueprintInstance(
            id: $0.itemID,
            blueprintTypeID: $0.typeID,
            locationID: $0.locationID,
            quantity: $0.quantity,
            runs: $0.runs,
            materialEfficiency: $0.materialEfficiency,
            timeEfficiency: $0.timeEfficiency,
            source: source
          )
        }
      },
      fallbackSource: source
    )

    return CharacterSyncSnapshot(
      id: UUID(),
      authorization: authorization,
      capabilities: capability,
      assets: assetValue,
      blueprints: blueprintValue,
      jobs: sourceValue(await jobsResult, transform: { $0 }, fallbackSource: source),
      openOrders: sourceValue(await openOrdersResult, transform: { $0 }, fallbackSource: source),
      orderHistory: sourceValue(await historyResult, transform: { $0 }, fallbackSource: source),
      walletBalance: sourceValue(await balanceResult, transform: { $0 }, fallbackSource: source),
      walletJournal: sourceValue(await journalResult, transform: { $0 }, fallbackSource: source),
      walletTransactions: sourceValue(
        await transactionsResult, transform: { $0 }, fallbackSource: source)
    )
  }

  private func privateEndpoint(
    characterID: Int64,
    suffix: String
  ) -> ESIEndpoint {
    let scope: String?
    switch suffix {
    case "skills":
      scope = "esi-skills.read_skills.v1"
    case "standings":
      scope = "esi-characters.read_standings.v1"
    case "assets":
      scope = "esi-assets.read_assets.v1"
    case "blueprints":
      scope = "esi-characters.read_blueprints.v1"
    case "orders", "orders/history":
      scope = "esi-markets.read_character_orders.v1"
    case "wallet", "wallet/journal", "wallet/transactions":
      scope = "esi-wallet.read_character_wallet.v1"
    default:
      scope = nil
    }
    return ESIEndpoint(
      path: "/characters/\(characterID)/\(suffix)/",
      requiresAuthorization: true,
      requiredScope: scope
    )
  }

  private func walletTransactions(
    characterID: Int64,
    lease: AccessTokenLease
  ) async throws -> ESIResponse<[ESIWalletTransactionDTO]> {
    var values: [ESIWalletTransactionDTO] = []
    var cursor: Int64?
    var firstResponse: ESIResponse<[ESIWalletTransactionDTO]>?
    while true {
      var endpoint = privateEndpoint(
        characterID: characterID,
        suffix: "wallet/transactions"
      )
      if let cursor {
        endpoint.query = [
          URLQueryItem(name: "from_id", value: String(cursor))
        ]
      }
      let response = try await esi.get(
        [ESIWalletTransactionDTO].self,
        endpoint: endpoint,
        lease: lease
      )
      firstResponse = firstResponse ?? response
      guard !response.value.isEmpty else { break }
      values.append(contentsOf: response.value)
      guard response.value.count >= 2_500,
        let next = response.value.map(\.transactionID).min(),
        next != cursor
      else { break }
      cursor = next
    }
    guard let firstResponse else {
      throw ESIError.decoding
    }
    return ESIResponse(
      value: values,
      source: firstResponse.source,
      statusCode: firstResponse.statusCode,
      expiresAt: firstResponse.expiresAt,
      etag: firstResponse.etag,
      lastModified: firstResponse.lastModified,
      pages: nil,
      errorLimitRemain: firstResponse.errorLimitRemain
    )
  }
}

public struct CharacterWalletService: Sendable {
  public static let requiredScope =
    "esi-wallet.read_character_wallet.v1"

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronizeBalance(
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease
  ) async -> Sourced<Double> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard authorization.characterID == lease.characterID else {
      return Sourced(
        state: .forbidden,
        value: nil,
        source: source,
        diagnostics: ["wallet.authorization-character-mismatch"]
      )
    }
    do {
      let response = try await esi.get(
        Double.self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/wallet/",
          requiresAuthorization: true,
          requiredScope: Self.requiredScope
        ),
        lease: lease
      )
      return Sourced(
        state: .fresh,
        value: response.value,
        source: response.source
      )
    } catch let error as ESIError {
      let state: DataFreshness
      switch error {
      case .forbidden, .missingScope:
        state = .forbidden
      default:
        state = .unavailable
      }
      return Sourced(
        state: state,
        value: nil,
        source: source,
        diagnostics: ["wallet.\(String(describing: error))"]
      )
    } catch {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: source,
        diagnostics: ["wallet.unavailable"]
      )
    }
  }
}

private struct CapturedESI<Value: Sendable>: Sendable {
  let value: ESIResponse<Value>?
  let error: ESIError?
}

private func capture<Value: Sendable>(
  _ operation: @Sendable () async throws -> ESIResponse<Value>
) async -> CapturedESI<Value> {
  do {
    return CapturedESI(value: try await operation(), error: nil)
  } catch let error as ESIError {
    return CapturedESI(value: nil, error: error)
  } catch {
    return CapturedESI(value: nil, error: .http(-1))
  }
}

private func sourceValue<Input: Sendable, Output: Codable & Sendable>(
  _ result: CapturedESI<Input>,
  transform: (Input) -> Output,
  fallbackSource: SourceIdentity
) -> Sourced<Output> {
  if let response = result.value {
    return Sourced(
      state: .fresh,
      value: transform(response.value),
      source: response.source
    )
  }
  let state: DataFreshness
  switch result.error {
  case .forbidden, .missingScope:
    state = .forbidden
  case .some:
    state = .unavailable
  case nil:
    state = .unavailable
  }
  return Sourced(
    state: state,
    value: nil,
    source: fallbackSource,
    diagnostics: ["esi.\(String(describing: result.error))"]
  )
}
