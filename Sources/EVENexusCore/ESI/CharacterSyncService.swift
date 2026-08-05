import Foundation

public struct PrivateContractItems: Codable, Sendable {
  public let contract: ESIPrivateContractDTO
  public let items: [ESIPrivateContractItemDTO]

  public init(
    contract: ESIPrivateContractDTO,
    items: [ESIPrivateContractItemDTO]
  ) {
    self.contract = contract
    self.items = items
  }
}

public struct PrivateContractSnapshot: Codable, Sendable {
  public let characterID: Int64
  public let itemContracts: [PrivateContractItems]
  public let inTransitCouriers: [ESIPrivateContractDTO]
  public let failedItemContractIDs: [Int64]
  public let omittedItemContractCount: Int

  public init(
    characterID: Int64,
    itemContracts: [PrivateContractItems],
    inTransitCouriers: [ESIPrivateContractDTO],
    failedItemContractIDs: [Int64] = [],
    omittedItemContractCount: Int = 0
  ) {
    self.characterID = characterID
    self.itemContracts = itemContracts
    self.inTransitCouriers = inTransitCouriers
    self.failedItemContractIDs = failedItemContractIDs
    self.omittedItemContractCount = omittedItemContractCount
  }
}

public struct CorporationWalletSnapshot: Codable, Sendable {
  public let actingCharacterID: Int64
  public let corporationID: Int64
  public let divisions: [ESICorporationWalletDTO]

  public init(
    actingCharacterID: Int64,
    corporationID: Int64,
    divisions: [ESICorporationWalletDTO]
  ) {
    self.actingCharacterID = actingCharacterID
    self.corporationID = corporationID
    self.divisions = divisions
  }
}

public struct CharacterSyncSnapshot: Identifiable, Sendable {
  public let id: UUID
  public let authorization: AuthorizationSnapshot
  public let capabilities: CharacterCapabilitySnapshot
  public let assets: Sourced<AssetSnapshot>
  public let corporationAssets: Sourced<AssetSnapshot>
  public let blueprints: Sourced<[OwnedBlueprintInstance]>
  public let jobs: Sourced<[ESIIndustryJobDTO]>
  public let openOrders: Sourced<[ESICharacterOrderDTO]>
  public let orderHistory: Sourced<[ESICharacterOrderDTO]>
  public let privateContracts: Sourced<PrivateContractSnapshot>
  public let walletBalance: Sourced<Double>
  public let walletJournal: Sourced<[ESIWalletJournalDTO]>
  public let walletTransactions: Sourced<[ESIWalletTransactionDTO]>
  public let corporationWallet: Sourced<CorporationWalletSnapshot>
}

public enum CharacterSyncStatusAssessment {
  public static func isRoleNotApplicable(
    domain: String,
    diagnostics: [String]
  ) -> Bool {
    switch domain {
    case "corporation-assets":
      diagnostics.contains("esi.corporation-assets.director-required")
    case "corporation-wallet":
      diagnostics.contains("esi.corporation-wallet.accountant-required")
    default:
      false
    }
  }

  public static func actionableIssueCount(
    in snapshot: CharacterSyncSnapshot
  ) -> Int {
    let personalStates = [
      snapshot.capabilities.skills.state,
      snapshot.capabilities.standings.state,
      snapshot.assets.state,
      snapshot.blueprints.state,
      snapshot.jobs.state,
      snapshot.openOrders.state,
      snapshot.orderHistory.state,
      snapshot.privateContracts.state,
      snapshot.walletBalance.state,
      snapshot.walletJournal.state,
      snapshot.walletTransactions.state,
    ]
    var count = personalStates.filter { $0 != .fresh }.count
    let corporationDomains = [
      (
        "corporation-assets",
        snapshot.corporationAssets.state,
        snapshot.corporationAssets.diagnostics
      ),
      (
        "corporation-wallet",
        snapshot.corporationWallet.state,
        snapshot.corporationWallet.diagnostics
      ),
    ]
    count +=
      corporationDomains.filter { domain, state, diagnostics in
        state != .fresh
          && !isRoleNotApplicable(
            domain: domain,
            diagnostics: diagnostics
          )
      }.count
    return count
  }
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
    async let privateContractValue = PrivateContractSyncService(esi: esi)
      .synchronize(
        authorization: authorization,
        lease: lease
      )

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
    async let corporationAssetValue = CorporationAssetSyncService(esi: esi)
      .synchronize(
        corporationID: publicDTO?.corporationID,
        authorization: authorization,
        lease: lease
      )
    async let corporationWalletValue = CorporationWalletSyncService(esi: esi)
      .synchronize(
        corporationID: publicDTO?.corporationID,
        authorization: authorization,
        lease: lease
      )

    let assetsRaw = await assetsResult
    let assetValue: Sourced<AssetSnapshot>
    if let assetResponse = assetsRaw.value {
      let rawItems = assetResponse.value.map {
        AssetItem(
          id: $0.itemID,
          typeID: $0.typeID,
          quantity: $0.quantity,
          locationID: $0.locationID,
          locationKind: AssetLocationKind(
            esiValue: $0.locationType,
            locationID: $0.locationID
          ),
          locationFlag: $0.locationFlag,
          singleton: $0.singleton
        )
      }
      let structureIDs = AssetLocationClassifier.structureCandidateIDs(
        in: rawItems
      )
      let items = AssetLocationClassifier.applyingStructureRoots(
        to: rawItems,
        candidateIDs: structureIDs
      )
      let resolvedStructures = await PlayerStructureSearchService(esi: esi)
        .resolveKnownStructures(
          structureIDs: structureIDs,
          lease: lease
        )
      let resolvedNames = Dictionary(
        uniqueKeysWithValues: (resolvedStructures.value ?? []).map {
          ($0.id, $0.name)
        }
      )
      let resolvedTypeIDs = Dictionary(
        uniqueKeysWithValues: (resolvedStructures.value ?? [])
          .compactMap { structure in
            structure.typeID.map { (structure.id, $0) }
          }
      )
      let unresolvedNameIDs = structureIDs.subtracting(resolvedNames.keys)
      let assetState: DataFreshness =
        unresolvedNameIDs.isEmpty ? .fresh : .partial
      var assetDiagnostics = resolvedStructures.diagnostics
      if !unresolvedNameIDs.isEmpty {
        assetDiagnostics.append(
          "esi.character-assets.unresolved-structure-names:\(unresolvedNameIDs.count)"
        )
      }
      assetValue = Sourced(
        state: assetState,
        value: AssetSnapshot(
          characterID: authorization.characterID,
          state: assetState,
          items: items,
          resolvedLocationNames: resolvedNames,
          unresolvedLocationNameIDs: unresolvedNameIDs,
          resolvedStructureTypeIDs: resolvedTypeIDs
        ),
        source: assetResponse.source,
        diagnostics: assetDiagnostics
      )
    } else {
      assetValue = sourceValue(
        assetsRaw,
        transform: { _ in
          AssetSnapshot(
            characterID: authorization.characterID,
            state: .unavailable,
            items: []
          )
        },
        fallbackSource: source
      )
    }
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

    let resolvedJobs = await resolvedIndustryJobs(
      await jobsResult,
      lease: lease,
      fallbackSource: source
    )

    return CharacterSyncSnapshot(
      id: UUID(),
      authorization: authorization,
      capabilities: capability,
      assets: assetValue,
      corporationAssets: await corporationAssetValue,
      blueprints: blueprintValue,
      jobs: resolvedJobs,
      openOrders: sourceValue(await openOrdersResult, transform: { $0 }, fallbackSource: source),
      orderHistory: sourceValue(await historyResult, transform: { $0 }, fallbackSource: source),
      privateContracts: await privateContractValue,
      walletBalance: sourceValue(await balanceResult, transform: { $0 }, fallbackSource: source),
      walletJournal: sourceValue(await journalResult, transform: { $0 }, fallbackSource: source),
      walletTransactions: sourceValue(
        await transactionsResult, transform: { $0 }, fallbackSource: source),
      corporationWallet: await corporationWalletValue
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

  private func resolvedIndustryJobs(
    _ result: CapturedESI<[ESIIndustryJobDTO]>,
    lease: AccessTokenLease,
    fallbackSource: SourceIdentity
  ) async -> Sourced<[ESIIndustryJobDTO]> {
    guard let response = result.value else {
      return sourceValue(result, transform: { $0 }, fallbackSource: fallbackSource)
    }
    let structureIDs = Set(
      response.value.compactMap { job in
        job.facilityID >= AssetLocationKind.minimumPlayerStructureID
          ? job.facilityID : nil
      }
    )
    let stationIDs = Set(
      response.value.compactMap { job in
        if let stationID = job.stationID,
          stationID < AssetLocationKind.minimumPlayerStructureID
        {
          return stationID
        }
        return job.facilityID < AssetLocationKind.minimumPlayerStructureID
          ? job.facilityID : nil
      }
    )
    async let structures = PlayerStructureSearchService(esi: esi)
      .resolveKnownStructures(structureIDs: structureIDs, lease: lease)
    async let stations = UniverseNameService(esi: esi).names(for: stationIDs)
    let (structureSnapshot, stationSnapshot) = await (structures, stations)
    var names = stationSnapshot.value ?? [:]
    for structure in structureSnapshot.value ?? [] {
      names[structure.id] = structure.name
    }
    let jobs = response.value.map { job in
      job.withFacilityName(
        names[job.facilityID]
          ?? job.stationID.flatMap { names[$0] }
      )
    }
    let unresolved = jobs.filter { $0.facilityName == nil }.count
    var diagnostics = structureSnapshot.diagnostics + stationSnapshot.diagnostics
    if unresolved > 0 {
      diagnostics.append("esi.character-industry-jobs.unresolved-facilities:\(unresolved)")
    }
    return Sourced(
      state: diagnostics.isEmpty ? .fresh : .partial,
      value: jobs,
      source: response.source,
      diagnostics: diagnostics
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

public struct PrivateContractSyncService: Sendable {
  public static let requiredScope =
    "esi-contracts.read_character_contracts.v1"
  public static let maximumValuedItemContracts = 500

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronize(
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease,
    now: Date = .now
  ) async -> Sourced<PrivateContractSnapshot> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard authorization.characterID == lease.characterID else {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.private-contracts.authorization-character-mismatch"
      )
    }
    guard lease.scopes.contains(Self.requiredScope) else {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.private-contracts.scope-missing:\(Self.requiredScope)"
      )
    }

    let contracts = await capture {
      try await esi.getAllPages(
        [ESIPrivateContractDTO].self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/contracts/",
          requiresAuthorization: true,
          requiredScope: Self.requiredScope
        ),
        lease: lease
      )
    }
    guard let contractResponse = contracts.value else {
      return unavailable(
        state: sourceState(for: contracts.error),
        source: source,
        diagnostic: "esi.private-contracts.list:\(String(describing: contracts.error))"
      )
    }

    let ownContracts = contractResponse.value.filter {
      $0.issuerID == authorization.characterID && !$0.forCorporation
    }
    let activeItemContracts = ownContracts.filter {
      ["item_exchange", "auction"].contains($0.type)
        && $0.status == "outstanding"
        && $0.dateExpired > now
    }.sorted { $0.contractID < $1.contractID }
    let valuedContracts = Array(
      activeItemContracts.prefix(Self.maximumValuedItemContracts)
    )
    let couriers = ownContracts.filter {
      $0.type == "courier" && $0.status == "in_progress"
    }.sorted { $0.contractID < $1.contractID }
    let omittedCount = max(0, activeItemContracts.count - valuedContracts.count)
    var itemContracts: [PrivateContractItems] = []
    var failedItemContractIDs: [Int64] = []

    for contract in valuedContracts {
      guard !Task.isCancelled else {
        return Sourced(
          state: .partial,
          value: PrivateContractSnapshot(
            characterID: authorization.characterID,
            itemContracts: itemContracts,
            inTransitCouriers: couriers,
            failedItemContractIDs: failedItemContractIDs,
            omittedItemContractCount: omittedCount
          ),
          source: contractResponse.source,
          diagnostics: ["esi.private-contracts.cancelled"]
        )
      }
      let items = await capture {
        try await esi.get(
          [ESIPrivateContractItemDTO].self,
          endpoint: ESIEndpoint(
            path:
              "/characters/\(authorization.characterID)/contracts/\(contract.contractID)/items/",
            requiresAuthorization: true,
            requiredScope: Self.requiredScope
          ),
          lease: lease
        )
      }
      if let response = items.value {
        itemContracts.append(
          PrivateContractItems(contract: contract, items: response.value)
        )
      } else {
        failedItemContractIDs.append(contract.contractID)
      }
    }

    var diagnostics: [String] = []
    if !failedItemContractIDs.isEmpty {
      diagnostics.append(
        "esi.private-contracts.items-unavailable:\(failedItemContractIDs.count)"
      )
    }
    if omittedCount > 0 {
      diagnostics.append("esi.private-contracts.limit:\(omittedCount)")
    }
    return Sourced(
      state: diagnostics.isEmpty ? .fresh : .partial,
      value: PrivateContractSnapshot(
        characterID: authorization.characterID,
        itemContracts: itemContracts,
        inTransitCouriers: couriers,
        failedItemContractIDs: failedItemContractIDs,
        omittedItemContractCount: omittedCount
      ),
      source: contractResponse.source,
      diagnostics: diagnostics
    )
  }

  private func unavailable(
    state: DataFreshness,
    source: SourceIdentity,
    diagnostic: String
  ) -> Sourced<PrivateContractSnapshot> {
    Sourced(
      state: state,
      value: nil,
      source: source,
      diagnostics: [diagnostic]
    )
  }

  private func sourceState(for error: ESIError?) -> DataFreshness {
    switch error {
    case .forbidden, .missingScope:
      .forbidden
    default:
      .unavailable
    }
  }
}

public struct CorporationWalletSyncService: Sendable {
  public static let walletScope =
    "esi-wallet.read_corporation_wallets.v1"
  public static let rolesScope =
    "esi-characters.read_corporation_roles.v1"
  public static let requiredScopes: Set<String> = [walletScope, rolesScope]
  private static let permittedRoles: Set<String> = [
    "Accountant", "Junior_Accountant",
  ]

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronize(
    corporationID: Int64?,
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease
  ) async -> Sourced<CorporationWalletSnapshot> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard authorization.characterID == lease.characterID else {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.corporation-wallet.authorization-character-mismatch"
      )
    }
    guard let corporationID else {
      return unavailable(
        state: .unavailable,
        source: source,
        diagnostic: "esi.corporation-wallet.corporation-identity-unavailable"
      )
    }
    for scope in Self.requiredScopes where !lease.scopes.contains(scope) {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.corporation-wallet.scope-missing:\(scope)"
      )
    }

    let roles = await capture {
      try await esi.get(
        ESICharacterRolesDTO.self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/roles",
          requiresAuthorization: true,
          requiredScope: Self.rolesScope
        ),
        lease: lease
      )
    }
    guard let roleResponse = roles.value else {
      return unavailable(
        state: sourceState(for: roles.error),
        source: source,
        diagnostic: "esi.corporation-wallet.roles:\(String(describing: roles.error))"
      )
    }
    let observedRoles = Set(roleResponse.value.roles ?? [])
    guard !observedRoles.isDisjoint(with: Self.permittedRoles) else {
      return unavailable(
        state: .forbidden,
        source: roleResponse.source,
        diagnostic: "esi.corporation-wallet.accountant-required"
      )
    }

    let wallets = await capture {
      try await esi.get(
        [ESICorporationWalletDTO].self,
        endpoint: ESIEndpoint(
          path: "/corporations/\(corporationID)/wallets/",
          requiresAuthorization: true,
          requiredScope: Self.walletScope
        ),
        lease: lease
      )
    }
    guard let walletResponse = wallets.value else {
      return unavailable(
        state: sourceState(for: wallets.error),
        source: source,
        diagnostic: "esi.corporation-wallet.wallets:\(String(describing: wallets.error))"
      )
    }
    return Sourced(
      state: .fresh,
      value: CorporationWalletSnapshot(
        actingCharacterID: authorization.characterID,
        corporationID: corporationID,
        divisions: walletResponse.value
      ),
      source: walletResponse.source
    )
  }

  private func unavailable(
    state: DataFreshness,
    source: SourceIdentity,
    diagnostic: String
  ) -> Sourced<CorporationWalletSnapshot> {
    Sourced(
      state: state,
      value: nil,
      source: source,
      diagnostics: [diagnostic]
    )
  }

  private func sourceState(for error: ESIError?) -> DataFreshness {
    switch error {
    case .forbidden, .missingScope:
      .forbidden
    default:
      .unavailable
    }
  }
}

public struct CorporationAssetSyncService: Sendable {
  public static let assetScope =
    "esi-assets.read_corporation_assets.v1"
  public static let rolesScope =
    "esi-characters.read_corporation_roles.v1"
  public static let divisionsScope =
    "esi-corporations.read_divisions.v1"
  public static let requiredScopes: Set<String> = [
    assetScope,
    rolesScope,
    divisionsScope,
  ]

  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronize(
    corporationID: Int64?,
    authorization: AuthorizationSnapshot,
    lease: AccessTokenLease
  ) async -> Sourced<AssetSnapshot> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard authorization.characterID == lease.characterID else {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.corporation-assets.authorization-character-mismatch"
      )
    }
    guard let corporationID else {
      return unavailable(
        state: .unavailable,
        source: source,
        diagnostic: "esi.corporation-assets.corporation-identity-unavailable"
      )
    }
    for scope in [Self.assetScope, Self.rolesScope]
    where !lease.scopes.contains(scope) {
      return unavailable(
        state: .forbidden,
        source: source,
        diagnostic: "esi.corporation-assets.scope-missing:\(scope)"
      )
    }

    let roles = await capture {
      try await esi.get(
        ESICharacterRolesDTO.self,
        endpoint: ESIEndpoint(
          path: "/characters/\(authorization.characterID)/roles",
          requiresAuthorization: true,
          requiredScope: Self.rolesScope
        ),
        lease: lease
      )
    }
    guard let roleResponse = roles.value else {
      return unavailable(
        state: sourceState(for: roles.error),
        source: source,
        diagnostic: "esi.corporation-assets.roles:\(String(describing: roles.error))"
      )
    }
    guard roleResponse.value.roles?.contains("Director") == true else {
      return unavailable(
        state: .forbidden,
        source: roleResponse.source,
        diagnostic: "esi.corporation-assets.director-required"
      )
    }

    async let assetsResult = capture {
      try await esi.getAllPages(
        [ESIAssetDTO].self,
        endpoint: ESIEndpoint(
          path: "/corporations/\(corporationID)/assets",
          requiresAuthorization: true,
          requiredScope: Self.assetScope
        ),
        lease: lease
      )
    }
    async let publicResult = capture {
      try await esi.get(
        ESICorporationPublicDTO.self,
        endpoint: ESIEndpoint(
          path: "/corporations/\(corporationID)"
        )
      )
    }
    let hasDivisionScope = lease.scopes.contains(Self.divisionsScope)
    async let divisionsResult: CapturedESI<ESICorporationDivisionsDTO> =
      hasDivisionScope
      ? capture {
        try await esi.get(
          ESICorporationDivisionsDTO.self,
          endpoint: ESIEndpoint(
            path: "/corporations/\(corporationID)/divisions",
            requiresAuthorization: true,
            requiredScope: Self.divisionsScope
          ),
          lease: lease
        )
      }
      : CapturedESI(value: nil, error: .missingScope(Self.divisionsScope))

    let assets = await assetsResult
    guard let assetResponse = assets.value else {
      return unavailable(
        state: sourceState(for: assets.error),
        source: source,
        diagnostic: "esi.corporation-assets.assets:\(String(describing: assets.error))"
      )
    }
    let corporation = await publicResult
    let divisions = await divisionsResult
    let rawItems = assetResponse.value.map {
      AssetItem(
        id: $0.itemID,
        typeID: $0.typeID,
        quantity: $0.quantity,
        locationID: $0.locationID,
        locationKind: AssetLocationKind(
          esiValue: $0.locationType,
          locationID: $0.locationID
        ),
        locationFlag: $0.locationFlag,
        singleton: $0.singleton
      )
    }
    let structureIDs = AssetLocationClassifier.structureCandidateIDs(
      in: rawItems
    )
    let items = AssetLocationClassifier.applyingStructureRoots(
      to: rawItems,
      candidateIDs: structureIDs
    )
    let resolvedStructures = await PlayerStructureSearchService(esi: esi)
      .resolveKnownStructures(
        structureIDs: structureIDs,
        lease: lease
      )
    let resolvedNames = Dictionary(
      uniqueKeysWithValues: (resolvedStructures.value ?? []).map {
        ($0.id, $0.name)
      }
    )
    let resolvedTypeIDs = Dictionary(
      uniqueKeysWithValues: (resolvedStructures.value ?? [])
        .compactMap { structure in
          structure.typeID.map { (structure.id, $0) }
        }
    )
    let unresolvedNameIDs = structureIDs.subtracting(resolvedNames.keys)
    let divisionNamePairs: [(Int, String)] =
      (divisions.value?.value.hangar ?? []).compactMap {
        guard let division = $0.division,
          let name = $0.name?.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.isEmpty
        else { return nil }
        return (division, name)
      }
    let divisionNames = Dictionary(uniqueKeysWithValues: divisionNamePairs)
    var diagnostics = resolvedStructures.diagnostics
    if corporation.value == nil {
      diagnostics.append("esi.corporation-assets.name-unavailable")
    }
    if divisions.value == nil {
      diagnostics.append(
        "esi.corporation-assets.divisions:\(String(describing: divisions.error))"
      )
    }
    let state: DataFreshness =
      unresolvedNameIDs.isEmpty && diagnostics.isEmpty ? .fresh : .partial
    return Sourced(
      state: state,
      value: AssetSnapshot(
        characterID: authorization.characterID,
        corporationID: corporationID,
        corporationName: corporation.value?.value.name,
        corporationDivisionNames: divisionNames,
        state: state,
        items: items,
        resolvedLocationNames: resolvedNames,
        unresolvedLocationNameIDs: unresolvedNameIDs,
        resolvedStructureTypeIDs: resolvedTypeIDs
      ),
      source: assetResponse.source,
      diagnostics: diagnostics
    )
  }

  private func unavailable(
    state: DataFreshness,
    source: SourceIdentity,
    diagnostic: String
  ) -> Sourced<AssetSnapshot> {
    Sourced(
      state: state,
      value: nil,
      source: source,
      diagnostics: [diagnostic]
    )
  }

  private func sourceState(for error: ESIError?) -> DataFreshness {
    switch error {
    case .forbidden, .missingScope:
      .forbidden
    default:
      .unavailable
    }
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
