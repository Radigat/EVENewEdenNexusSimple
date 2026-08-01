import AppKit
import EVENexusCore
import Foundation

enum CharacterConnectionPhase: Equatable {
  case idle
  case waitingForBrowser
  case completingSSO
  case synchronizingESI
}

@MainActor
final class RuntimeState: ObservableObject {
  @Published var productionBasis = ProductionBasis()
  @Published var manufacturingProfile = ManufacturingProfile()
  @Published var reactionProfile: ReactionProfile?
  @Published var plan: IndustryPlanSnapshot?
  @Published private(set) var reactionAnalysis: ReactionAnalysisSnapshot?
  @Published private(set) var isAnalyzingReactions = false
  @Published private(set) var reactionAnalysisError: String?
  @Published private(set) var moonMaterialAnalysis: MoonMaterialPurchaseAnalysisSnapshot?
  @Published private(set) var isRefreshingMoonMaterialAnalysis = false
  @Published private(set) var moonMaterialAnalysisError: String?
  @Published private(set) var marketBrowserState: Sourced<MarketBrowserSnapshot>?
  @Published private(set) var isRefreshingMarketBrowser = false
  @Published private(set) var marketBrowserError: String?
  @Published var isWorking = false
  @Published var statusMessage = "Ready"
  @Published var errorMessage: String?
  @Published var updatePreview: SDEUpdatePreview?
  @Published private(set) var sdeLastCheckedAt: Date?
  @Published var activeSDEBuild: Int?
  @Published var activeSDEContentSHA256: String?
  @Published var installationPhase: String?
  @Published var lastCharacterSync: CharacterSyncSnapshot?
  @Published var selectedAssetLocationID: Int64?
  @Published var warehouseStockEnabled = true
  @Published var industrySystemIndices:
    Sourced<
      [IndustrySystemCostIndexSnapshot]
    >?
  @Published var scienceSkillDefinitions: Sourced<[ScienceSkillDefinition]>?
  @Published var industryFacilityReferences:
    Sourced<
      IndustryFacilityReferenceSnapshot
    >?
  @Published var isLoadingProfileReferenceData = false
  @Published private(set) var isPlannerConfigurationReady = false
  @Published private(set) var eveOnlineServiceStatus: EVEOnlineServiceStatusSnapshot?
  @Published private(set) var eveOnlineStatusCheckFailed = false
  @Published private(set) var characterConnectionPhase: CharacterConnectionPhase = .idle

  private let esi: ESIClient
  private let eveOnlineStatusClient = EVEOnlineStatusClient()
  private let solarSystemSearch: SolarSystemSearchService
  private let playerStructureSearch: PlayerStructureSearchService
  private let tradingLocationSearch: TradingLocationSearchService
  private let universeNameService: UniverseNameService
  private let catalog: SQLiteStaticCatalog
  private let assetWarehouseProjectionCache =
    StoredAssetWarehouseProjectionCache()
  private let dataRoot: URL
  private var authServices: [String: EVESSOService] = [:]
  private var hasLoadedProfileReferenceData = false
  private var profileReferenceRefreshTask: Task<Void, Never>?
  private var lastEVEOnlineStatusCheckAt: Date?

  init(dataRoot providedDataRoot: URL? = nil) {
    let esi = ESIClient()
    self.esi = esi
    self.solarSystemSearch = SolarSystemSearchService(esi: esi)
    self.playerStructureSearch = PlayerStructureSearchService(esi: esi)
    self.tradingLocationSearch = TradingLocationSearchService(esi: esi)
    self.universeNameService = UniverseNameService(esi: esi)
    let resolvedDataRoot = providedDataRoot ?? Self.fallbackDataRoot()
    dataRoot = resolvedDataRoot
    catalog = SQLiteStaticCatalog(
      rootURL:
        resolvedDataRoot
        .appendingPathComponent("sde", isDirectory: true)
        .appendingPathComponent("catalog-store", isDirectory: true)
    )
    Task {
      await refreshActiveBuild()
      await refreshEVEOnlineServiceStatus()
    }
  }

  private static func fallbackDataRoot() -> URL {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Application Support",
        isDirectory: true
      )
    return applicationSupport.appendingPathComponent(
      AppDataPaths.applicationIdentifier,
      isDirectory: true
    )
  }

  func preparePlannerConfiguration(encodedBasis: Data?) async {
    isPlannerConfigurationReady = false
    if let encodedBasis {
      do {
        productionBasis = try JSONDecoder().decode(
          ProductionBasis.self,
          from: encodedBasis
        )
      } catch {
        errorMessage =
          "The saved production configuration could not be loaded."
      }
    }
    await refreshProfileReferenceData()
    isPlannerConfigurationReady = true
  }

  func calculate(
    input: String,
    manualStockInput: String = "",
    existingReservations: [StockAllocation] = [],
    assetWarehouse: AssetWarehouse? = nil,
    stockTargets: [Int64: Int64] = [:],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    defaultPurchaseLocation: ProcurementLocation? = nil
  ) async {
    await perform("Calculating production plan") {
      guard let active = try await catalog.activeSDEVersion() else {
        throw StaticCatalogError.noActiveCatalog
      }
      let planner = IndustryPlanner()
      let planningCatalog = MemoizedIndustryCatalog(base: catalog)
      let typeIDs = try await planner.requiredMarketTypeIDs(
        input: input,
        catalog: planningCatalog
      )
      let mainTradeHub = productionBasis.mainTradeHub
      let mainPurchaseLocation =
        defaultPurchaseLocation ?? mainTradeHub.procurementLocation
      let marketService = JitaMarketService(esi: esi)
      async let market = marketService.orderSnapshot(
        typeIDs: typeIDs,
        tradeHub: mainTradeHub
      )
      async let adjusted = marketService.adjustedPrices()
      async let systems = marketService.industrySystems()
      let values = try await (market, adjusted, systems)
      var availableStock: [Int64: Int64]
      let assetSource: StockSource?
      var snapshotIDs: [UUID] = []
      var inputWarnings: [DomainWarning] = []
      let manualStock = try await parseManualStock(manualStockInput)
      if !manualStock.isEmpty {
        availableStock = manualStock
        assetSource = StockSource(kind: .manual, reference: "planner-input")
      } else if warehouseStockEnabled,
        let warehouse = assetWarehouse,
        !warehouse.snapshotIDs.isEmpty
      {
        let availability = warehouse.availability(
          targetQuantities: stockTargets
        )
        availableStock = availability.allocatableQuantities
        assetSource = StockSource(
          kind: .warehouse,
          reference: "production-location-personal-assets"
        )
        snapshotIDs.append(contentsOf: warehouse.snapshotIDs)
        let incompleteStates = Set(
          warehouse.sourceStates.filter { $0 != .fresh }
        )
        if !incompleteStates.isEmpty {
          inputWarnings.append(
            DomainWarning(
              code: "industry.warehouse-source-not-fresh",
              message:
                "The production warehouse contains non-fresh or unavailable character asset sources: \(incompleteStates.map(\.rawValue).sorted().joined(separator: ", ")).",
              severity: .warning
            )
          )
        }
        let targetsBelowMinimum = availability.lines.filter {
          $0.missingToTarget > 0
        }
        if !targetsBelowMinimum.isEmpty {
          inputWarnings.append(
            DomainWarning(
              code: "industry.warehouse-target-shortfall",
              message:
                "\(targetsBelowMinimum.count) warehouse target \(targetsBelowMinimum.count == 1 ? "is" : "are") already below the configured minimum and therefore unavailable for allocation.",
              severity: .information
            )
          )
        }
      } else {
        availableStock = [:]
        assetSource = nil
      }
      if let assetSource {
        for allocation in existingReservations
        where allocation.source == assetSource
          || assetSource.kind == .warehouse
            && allocation.source.kind == .assetSnapshot
        {
          availableStock[allocation.typeID] = max(
            0,
            availableStock[allocation.typeID, default: 0]
              - allocation.quantity
          )
        }
      }
      let configuredReaction =
        productionBasis.configuredReactionProfile ?? reactionProfile
      let acceptedProcurementPreferences = procurementPreferences.mapValues {
        preference in
        MaterialProcurementPreference(
          supplyMode: preference.supplyMode,
          purchaseLocation: mainPurchaseLocation
        )
      }
      let context = IndustryPlanningContext(
        manufacturingProfile: manufacturingProfile,
        reactionProfile: configuredReaction,
        productionBasis: productionBasis,
        catalog: planningCatalog,
        market: values.0,
        adjustedPrices: values.1,
        systemIndices: values.2,
        availableStock: availableStock,
        procurementPreferences: acceptedProcurementPreferences,
        defaultPurchaseLocation: mainPurchaseLocation,
        assetSource: assetSource,
        sdeBuild: active.buildNumber,
        snapshotIDs: snapshotIDs,
        inputWarnings: inputWarnings,
        salesTaxRate: productionBasis.marketTaxes.effectiveSalesTaxRate,
        brokerFeeRate: productionBasis.marketTaxes.effectiveBrokerFeeRate
      )
      plan = try await planner.plan(input: input, context: context)
    }
  }

  func analyzeReactions(
    runs requestedRuns: Int,
    tradeHub: MarketTradeHub
  ) async {
    let maximumRuns =
      reactionAnalysis?.maximumSelectableRuns
      ?? ReactionJobRules.neutralMaximumSelectableRuns
    let runs = min(max(1, requestedRuns), maximumRuns)
    isAnalyzingReactions = true
    reactionAnalysisError = nil
    defer { isAnalyzingReactions = false }
    do {
      guard try await catalog.activeSDEVersion() != nil else {
        throw StaticCatalogError.noActiveCatalog
      }
      let definitions = try await catalog.reactionDefinitions()
      try Task.checkCancellation()
      let typeIDs = Set(
        definitions.flatMap { definition in
          [definition.productTypeID]
            + definition.activity.materials.map(\.typeID)
            + definition.activity.products.map(\.typeID)
        }
      )
      let marketService = TradeHubMarketService(esi: esi)
      async let namesValue = catalog.typeNames(ids: typeIDs)
      async let classificationsValue = catalog.industryClassifications(
        typeIDs: Set(definitions.map(\.productTypeID))
      )
      async let marketValue = marketService.orderSnapshot(
        typeIDs: typeIDs,
        tradeHub: tradeHub
      )
      async let adjustedValue = marketService.adjustedPrices()
      async let systemsValue = marketService.industrySystems()
      let (names, classifications, market, adjusted, systems) = try await (
        namesValue,
        classificationsValue,
        marketValue,
        adjustedValue,
        systemsValue
      )
      try Task.checkCancellation()
      let facility = reactionFacilityCostContext(systemIndices: systems)
      reactionAnalysis = try ReactionProfitabilityAnalyzer.analyze(
        definitions: definitions,
        typeNames: names,
        classifications: classifications,
        runs: runs,
        tradeHub: tradeHub,
        market: market,
        adjustedPrices: adjusted,
        facility: facility
      )
    } catch is CancellationError {
      return
    } catch StaticCatalogError.noActiveCatalog {
      reactionAnalysisError =
        "No active SDE catalog is installed. Install or activate static data first."
    } catch ReactionAnalysisError.noReactionDefinitions {
      reactionAnalysisError =
        "The active SDE catalog contains no complete published reaction definitions."
    } catch {
      reactionAnalysisError =
        "The reaction analysis could not be completed. \(error.localizedDescription)"
    }
  }

  func refreshMoonMaterialAnalysis() async {
    guard !isRefreshingMoonMaterialAnalysis else { return }
    isRefreshingMoonMaterialAnalysis = true
    moonMaterialAnalysisError = nil
    defer { isRefreshingMoonMaterialAnalysis = false }

    do {
      let materialCatalog = try await catalog.moonMaterials()
      let typeIDs = Set(materialCatalog.materials.map(\.id))
      let marketService = TradeHubMarketService(esi: esi)
      let locationIDs = Dictionary(
        uniqueKeysWithValues: MoonMaterialMarketLocation.allCases.map {
          location in
          let configuredStructureID =
            location.isPlayerStructure
            ? productionBasis.structures.first {
              $0.solarSystemID == location.systemID && $0.structureID != nil
            }?.structureID : nil
          return (location, configuredStructureID ?? location.locationID)
        }
      )
      let attempts = await withTaskGroup(
        of: MoonMaterialMarketRefreshResult?.self,
        returning: [
          MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>
        ].self
      ) { group in
        for location in MoonMaterialMarketLocation.allCases {
          group.addTask {
            do {
              guard let locationID = locationIDs[location] else {
                return nil
              }
              let snapshot = try await marketService.orderSnapshot(
                typeIDs: typeIDs,
                regionID: location.regionID,
                locationID: locationID
              )
              return MoonMaterialMarketRefreshResult(
                location: location,
                result: Sourced(
                  state: .fresh,
                  value: snapshot,
                  source: snapshot.source
                )
              )
            } catch is CancellationError {
              return nil
            } catch {
              let failure = Self.moonMaterialMarketFailure(error)
              return MoonMaterialMarketRefreshResult(
                location: location,
                result: Sourced(
                  state: failure.state,
                  value: nil,
                  source: SourceIdentity(
                    provider: "ESI",
                    version: EVEConstants.esiCompatibilityDate
                  ),
                  diagnostics: [failure.diagnostic]
                )
              )
            }
          }
        }
        var values: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>] = [:]
        for await attempt in group {
          guard let attempt else { continue }
          values[attempt.location] = attempt.result
        }
        return values
      }
      guard !Task.isCancelled else { return }

      let canRetainPreviousMarkets =
        moonMaterialAnalysis?.materialCatalog.source.version
        == materialCatalog.source.version
      var markets: [MoonMaterialMarketLocation: Sourced<MarketOrderSnapshot>] = [:]
      for location in MoonMaterialMarketLocation.allCases {
        guard let attempt = attempts[location] else { continue }
        markets[location] = attempt.retainingLastKnownValue(
          from: canRetainPreviousMarkets
            ? moonMaterialAnalysis?.markets[location] : nil
        )
      }
      moonMaterialAnalysis = MoonMaterialPurchaseAnalysisSnapshot(
        materialCatalog: materialCatalog,
        markets: markets,
        refreshedAt: .now
      )
    } catch is CancellationError {
      return
    } catch StaticCatalogError.noActiveCatalog {
      moonMaterialAnalysisError =
        "No active SDE catalog is installed. Install or activate static data first."
    } catch {
      moonMaterialAnalysisError =
        "Moon materials could not be loaded from the active SDE catalog."
    }
  }

  func refreshMarketBrowser(
    typeID: Int64,
    itemName: String,
    originSystemID: Int64?,
    originSystemName: String?
  ) async {
    guard !isRefreshingMarketBrowser else { return }
    isRefreshingMarketBrowser = true
    marketBrowserError = nil
    defer { isRefreshingMarketBrowser = false }

    do {
      let latest = try await MarketBrowserService(
        esi: esi,
        universeNames: universeNameService
      ).snapshot(
        typeID: typeID,
        itemName: itemName,
        originSystemID: originSystemID,
        originSystemName: originSystemName
      )
      guard !Task.isCancelled else { return }
      let previous: Sourced<MarketBrowserSnapshot>? = marketBrowserState.flatMap {
        state in
        guard state.value?.typeID == typeID,
          state.value?.originSystemID == originSystemID
        else { return nil }
        return state
      }
      marketBrowserState = latest.retainingLastKnownValue(from: previous)
    } catch is CancellationError {
      return
    } catch ESIError.cancelled {
      return
    } catch StaticCatalogError.noActiveCatalog {
      marketBrowserError =
        "No active SDE catalog is installed. Install or activate static data first."
    } catch {
      marketBrowserError =
        "The cross-region market could not be refreshed. Existing market data was not replaced."
    }
  }

  nonisolated private static func moonMaterialMarketFailure(
    _ error: Error
  ) -> (state: DataFreshness, diagnostic: String) {
    guard let esiError = error as? ESIError else {
      return (.unavailable, "esi.moon-market.unavailable")
    }
    switch esiError {
    case .forbidden, .authorizationRequired, .missingScope:
      return (.forbidden, "esi.moon-market.forbidden")
    case .rateLimited:
      return (.unavailable, "esi.moon-market.rate-limited")
    default:
      return (.unavailable, "esi.moon-market.unavailable")
    }
  }

  private func reactionFacilityCostContext(
    systemIndices: [IndustrySystemIndex]
  ) -> ReactionFacilityCostContext? {
    guard let selection = productionBasis.reactionSelection,
      !selection.needsReview,
      let profile = productionBasis.configuredReactionProfile
    else { return nil }
    let systemIndex =
      productionBasis.reactionSystem.costIndexOverride
      ?? systemIndices.first {
        $0.solarSystemID == profile.solarSystemID
          && $0.activity == .reaction
      }?.costIndex
    guard let systemIndex else { return nil }
    return ReactionFacilityCostContext(
      name: "\(profile.structureName) · \(productionBasis.reactionSystem.solarSystemName)",
      materialMultiplier: profile.effectiveMaterialMultiplier,
      timeMultiplier: profile.effectiveTimeMultiplier,
      jobCostMultiplier: profile.effectiveJobCostMultiplier,
      facilityTaxRate: profile.facilityTaxRate,
      systemCostIndex: systemIndex,
      sccSurchargeRate: IndustryRuleSet.current.reactionSCCRate,
      alphaSurchargeRate:
        profile.cloneState == .alpha
        ? IndustryRuleSet.current.alphaSurchargeRate : 0,
      ruleVersion: profile.ruleVersion
    )
  }

  private func parseManualStock(_ input: String) async throws
    -> [Int64: Int64]
  {
    var result: [Int64: Int64] = [:]
    guard input.utf8.count <= ProductionInputParser.maximumInputBytes else {
      throw IndustryPlannerError.invalidStock(line: 1, value: "")
    }
    var acceptedLineCount = 0
    for (offset, rawLine) in input.components(separatedBy: .newlines)
      .enumerated()
    {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      acceptedLineCount += 1
      guard acceptedLineCount <= ProductionInputParser.maximumJobCount else {
        throw IndustryPlannerError.invalidStock(line: offset + 1, value: "")
      }
      let fields = line.split(
        separator: "|",
        omittingEmptySubsequences: false
      ).map { $0.trimmingCharacters(in: .whitespaces) }
      guard fields.count == 2,
        fields[0].utf8.count <= ProductionInputParser.maximumProductNameBytes,
        let quantity = Int64(fields[1]),
        quantity > 0,
        quantity <= Int64(ProductionInputParser.maximumWantedQuantity),
        let typeID = try await catalog.typeID(named: fields[0])
      else {
        throw IndustryPlannerError.invalidStock(
          line: offset + 1,
          value: rawLine
        )
      }
      let (sum, overflow) = result[typeID, default: 0]
        .addingReportingOverflow(quantity)
      guard !overflow,
        sum <= Int64(ProductionInputParser.maximumWantedQuantity)
      else {
        throw IndustryPlannerError.invalidStock(
          line: offset + 1,
          value: String(rawLine.prefix(512))
        )
      }
      result[typeID] = sum
    }
    return result
  }

  var availableAssetLocationIDs: [Int64] {
    guard let items = lastCharacterSync?.assets.value?.items else { return [] }
    return Array(Set(items.map(\.locationID))).sorted()
  }

  func resolveAssetTypeNames(_ typeIDs: Set<Int64>) async
    -> [Int64: String]
  {
    (try? await catalog.typeNames(ids: typeIDs)) ?? [:]
  }

  func resolveAssetTypeClassifications(_ typeIDs: Set<Int64>) async
    -> [Int64: IndustryItemClassification]
  {
    (try? await catalog.industryClassifications(typeIDs: typeIDs)) ?? [:]
  }

  func prepareAssetWarehouse(
    identity: String,
    payloads: [StoredAssetSnapshotPayload]
  ) async -> PreparedAssetWarehouse {
    await assetWarehouseProjectionCache.prepare(
      identity: identity,
      payloads: payloads
    )
  }

  func prepareProductionWarehouse(
    from prepared: PreparedAssetWarehouse
  ) async -> PreparedAssetWarehouse {
    let locationIDs = Set(
      productionBasis.structures.compactMap(\.structureID)
    )
    guard !locationIDs.isEmpty else {
      return prepared.filtered(locationIDs: [], excludingTypeIDs: [])
    }
    let classifications =
      (try? await catalog.industryClassifications(
        typeIDs: Set(prepared.factualQuantities.keys)
      )) ?? [:]
    let shipTypeIDs = Set(
      classifications.compactMap { typeID, classification in
        classification.categoryName.caseInsensitiveCompare("Ship")
          == .orderedSame ? typeID : nil
      }
    )
    return prepared.filtered(
      locationIDs: locationIDs,
      excludingTypeIDs: shipTypeIDs,
      excludingContentsOfTypeIDs: shipTypeIDs
    )
  }

  func resolveAssetLocationNames(_ locationIDs: Set<Int64>) async
    -> Sourced<[Int64: String]>
  {
    await universeNameService.names(for: locationIDs)
  }

  func resolveAssetTypeID(named name: String) async throws -> Int64? {
    try await catalog.typeID(named: name)
  }

  func searchAssetTypes(matching query: String) async throws
    -> [ItemTypeSearchResult]
  {
    try await catalog.searchItemTypes(matching: query, limit: 80)
  }

  func searchMarketTypes(matching query: String) async throws
    -> [ItemTypeSearchResult]
  {
    try await catalog.searchItemTypes(matching: query, limit: 50)
  }

  func blueprintResearchQuote(
    for instance: OwnedBlueprintInstance
  ) async throws -> BlueprintResearchCostQuote {
    async let definitionValue = catalog.blueprintResearchDefinition(
      blueprintTypeID: instance.blueprintTypeID
    )
    async let priceValue = JitaMarketService(esi: esi)
      .adjustedPriceSnapshot()
    let definition = try await definitionValue
    guard let definition else {
      throw BlueprintResearchError.definitionUnavailable(
        instance.blueprintTypeID
      )
    }
    let prices = try await priceValue
    if industrySystemIndices == nil {
      industrySystemIndices = await loadIndustrySystemIndices()
    }
    let pricing = BlueprintResearchPricingInput(
      adjustedPrices: prices.prices,
      adjustedPriceSource: prices.source,
      materialFacility: researchFacilityContext(
        activity: .materialEfficiency
      ),
      timeFacility: researchFacilityContext(
        activity: .timeEfficiency
      )
    )
    return BlueprintResearchCostCalculator.quote(
      instance: instance,
      definition: definition,
      pricing: pricing
    )
  }

  private func researchFacilityContext(
    activity: BlueprintResearchActivity
  ) -> BlueprintResearchFacilityContext? {
    let industryActivity = activity.industryActivity
    guard
      let system = productionBasis.systemConfiguration(
        for: industryActivity
      ),
      system.solarSystemID > 0,
      let selection = productionBasis.scienceSelection(
        for: industryActivity
      ),
      let structure = productionBasis.structure(id: selection.structureID)
    else { return nil }

    let index: Double
    let source: SourceIdentity
    let indexNeedsReview: Bool
    if let override = system.costIndexOverride,
      override.isFinite,
      override >= 0
    {
      index = override
      source = SourceIdentity(
        provider: "Production Basis",
        version: productionBasis.ruleVersion
      )
      indexNeedsReview = false
    } else {
      guard
        let sourcedIndices = industrySystemIndices,
        let systems = sourcedIndices.value,
        let systemIndices = systems.first(where: {
          $0.solarSystemID == system.solarSystemID
        }),
        let activityIndex = systemIndices.indices.first(where: {
          $0.activity == industryActivity.costActivity
        }),
        activityIndex.value.isFinite,
        activityIndex.value >= 0
      else { return nil }
      index = activityIndex.value
      source = sourcedIndices.source
      indexNeedsReview = sourcedIndices.state != .fresh
    }

    let alphaRate =
      productionBasis.cloneState == .alpha
      ? IndustryRuleSet.current.alphaSurchargeRate : 0
    return BlueprintResearchFacilityContext(
      activity: activity,
      solarSystemID: system.solarSystemID,
      solarSystemName: system.solarSystemName,
      facilityName: structure.displayName,
      systemCostIndex: index,
      jobCostMultiplier: selection.jobCostMultiplier,
      facilityTaxRate: structure.facilityTaxRate,
      sccSurchargeRate: IndustryRuleSet.current.researchSCCRate,
      alphaSurchargeRate: alphaRate,
      needsReview:
        selection.needsReview
        || indexNeedsReview,
      source: source
    )
  }

  func searchSolarSystems(matching query: String) async throws
    -> [SolarSystemOption]
  {
    try await solarSystemSearch.search(query: query)
  }

  func resolveSolarSystem(_ systemID: Int64) async throws
    -> SolarSystemDetails
  {
    try await solarSystemSearch.details(systemID: systemID)
  }

  func searchAccessibleStructures(
    matching query: String,
    in solarSystemID: Int64,
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> Sourced<[PlayerStructureOption]> {
    let auth = authService(clientID: clientID)
    let lease = try await auth.accessTokenLease(
      characterID: authorization.characterID
    )
    return try await playerStructureSearch.search(
      query: query,
      solarSystemID: solarSystemID,
      characterID: authorization.characterID,
      lease: lease
    )
  }

  func searchAccessibleStructures(
    matching query: String,
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> Sourced<[PlayerStructureOption]> {
    let auth = authService(clientID: clientID)
    let lease = try await auth.accessTokenLease(
      characterID: authorization.characterID
    )
    return try await playerStructureSearch.search(
      query: query,
      characterID: authorization.characterID,
      lease: lease
    )
  }

  func searchNPCTradingLocations(
    matching query: String
  ) async throws -> Sourced<[TradingLocationSearchOption]> {
    try await tradingLocationSearch.searchNPCStations(query: query)
  }

  func resolveNPCTradingLocation(
    _ location: ProcurementLocation
  ) async throws -> ProcurementLocation {
    guard let stationID = location.locationID else { return location }
    return try await tradingLocationSearch.resolveNPCStation(
      stationID: stationID
    ).procurementLocation
  }

  func discoverKnownAccessibleStructures(
    in solarSystemID: Int64,
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> Sourced<[PlayerStructureOption]> {
    let auth = authService(clientID: clientID)
    let lease = try await auth.accessTokenLease(
      characterID: authorization.characterID
    )
    return try await playerStructureSearch.discoverKnownStructures(
      solarSystemID: solarSystemID,
      characterID: authorization.characterID,
      lease: lease
    )
  }

  func refreshProfileReferenceData(force: Bool = false) async {
    if let profileReferenceRefreshTask {
      await profileReferenceRefreshTask.value
      return
    }
    guard force || !hasLoadedProfileReferenceData else { return }
    isLoadingProfileReferenceData = true
    let task = Task { @MainActor in
      async let indices = loadIndustrySystemIndices()
      async let skills = loadScienceSkillDefinitions()
      async let facilities = loadIndustryFacilityReferences()
      let values = await (indices, skills, facilities)
      industrySystemIndices = values.0
      scienceSkillDefinitions = values.1
      industryFacilityReferences = values.2
      if let reference = values.2.value {
        productionBasis.applyFacilityReferences(reference)
      }
      await refreshConfiguredSystemDetails()
      hasLoadedProfileReferenceData = true
      isLoadingProfileReferenceData = false
    }
    profileReferenceRefreshTask = task
    await task.value
    profileReferenceRefreshTask = nil
  }

  func syncCharacterCapabilities(
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> CharacterCapabilitySnapshot {
    let auth = authService(clientID: clientID)
    let lease = try await auth.accessTokenLease(
      characterID: authorization.characterID
    )
    return await CharacterSyncService(esi: esi).synchronizeCapabilities(
      authorization: authorization,
      lease: lease
    )
  }

  private func loadIndustrySystemIndices() async
    -> Sourced<[IndustrySystemCostIndexSnapshot]>
  {
    do {
      return try await IndustrySystemIndexService(esi: esi).synchronize()
    } catch {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate
        ),
        diagnostics: ["esi.industry-system-indices.unavailable"]
      )
    }
  }

  private func loadScienceSkillDefinitions() async
    -> Sourced<[ScienceSkillDefinition]>
  {
    do {
      let values = try await catalog.scienceSkills()
      let active = try await catalog.activeSDEVersion()
      return Sourced(
        state: .fresh,
        value: values,
        source: SourceIdentity(
          provider: "CCP SDE",
          version: String(active?.buildNumber ?? 0)
        )
      )
    } catch {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: SourceIdentity(provider: "CCP SDE", version: "unavailable"),
        diagnostics: ["sde.science-skills.unavailable"]
      )
    }
  }

  private func loadIndustryFacilityReferences() async
    -> Sourced<IndustryFacilityReferenceSnapshot>
  {
    do {
      let values = try await catalog.industryFacilityReferences()
      return Sourced(
        state: .fresh,
        value: values,
        source: values.source,
        diagnostics: [
          "sde.industry-facility-reference.thukker-rigs-needs-review"
        ]
      )
    } catch {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: SourceIdentity(provider: "CCP SDE", version: "unavailable"),
        diagnostics: ["sde.industry-facility-reference.unavailable"]
      )
    }
  }

  private func refreshConfiguredSystemDetails() async {
    let systemIDs = Set(
      productionBasis.configuredActivitySystems.map(\.solarSystemID)
    )
    let acceptedIDs = systemIDs.filter { $0 > 0 }.sorted()
    let details = await withTaskGroup(
      of: SolarSystemDetails?.self,
      returning: [SolarSystemDetails].self
    ) { group in
      for systemID in acceptedIDs {
        group.addTask { [solarSystemSearch] in
          try? await solarSystemSearch.details(systemID: systemID)
        }
      }
      var values: [SolarSystemDetails] = []
      for await details in group {
        if let details {
          values.append(details)
        }
      }
      return values.sorted { $0.id < $1.id }
    }
    for details in details {
      productionBasis.applySystemDetails(details)
    }
  }

  func checkSDE(ownerContact: String) async {
    await perform("Checking current SDE metadata") {
      let service = try makeSDELifecycle(ownerContact: ownerContact)
      updatePreview = try await service.check()
      sdeLastCheckedAt = .now
    }
  }

  func installSDE(
    ownerContact: String,
    schemaReviewConfirmed: Bool
  ) async {
    guard let updatePreview else { return }
    await perform("Installing SDE build \(updatePreview.officialBuild)") {
      let service = try makeSDELifecycle(ownerContact: ownerContact)
      let freshPreview = try await service.check()
      guard freshPreview == updatePreview else {
        throw SDELifecycleError.confirmationDoesNotMatchPreview
      }
      _ = try await service.installConfirmed(
        preview: freshPreview,
        schemaReviewConfirmed: schemaReviewConfirmed
      ) { [weak self] phase in
        Task { @MainActor in
          self?.installationPhase = phase.rawValue
        }
      }
      self.updatePreview = nil
      self.installationPhase = nil
      await refreshActiveBuild()
    }
  }

  func connectCharacter(clientID: String) async throws
    -> AuthorizationSnapshot
  {
    characterConnectionPhase = .waitingForBrowser
    defer { characterConnectionPhase = .idle }
    let service = authService(clientID: clientID)
    let pending = try await service.beginAuthorization()
    let server = LoopbackCallbackServer()
    guard NSWorkspace.shared.open(pending.authorizationURL) else {
      throw AuthError.invalidCallback
    }
    let callback = try await server.waitForCallback(
      expectedState: pending.state
    )
    characterConnectionPhase = .completingSSO
    let (authorization, lease) = try await service.completeAuthorization(
      callbackURL: callback,
      pending: pending
    )
    characterConnectionPhase = .synchronizingESI
    lastCharacterSync = await CharacterSyncService(esi: esi).synchronize(
      authorization: authorization,
      lease: lease
    )
    return authorization
  }

  func syncCharacter(
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws {
    let service = authService(clientID: clientID)
    let lease = try await service.accessTokenLease(
      characterID: authorization.characterID
    )
    lastCharacterSync = await CharacterSyncService(esi: esi).synchronize(
      authorization: authorization,
      lease: lease
    )
  }

  func disconnectCharacter(
    characterID: Int64,
    clientID: String
  ) async throws {
    let service = authService(clientID: clientID)
    try await service.revokeLocalAuthorization(characterID: characterID)
    await esi.removeCachedResponses(forCharacterID: characterID)
    if lastCharacterSync?.authorization.characterID == characterID {
      lastCharacterSync = nil
      selectedAssetLocationID = nil
    }
  }

  func syncWallet(
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> Sourced<Double> {
    let service = authService(clientID: clientID)
    let lease = try await service.accessTokenLease(
      characterID: authorization.characterID
    )
    return await CharacterWalletService(esi: esi).synchronizeBalance(
      authorization: authorization,
      lease: lease
    )
  }

  private func authService(clientID: String) -> EVESSOService {
    let normalizedClientID = clientID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if let existing = authServices[normalizedClientID] {
      return existing
    }
    let service = EVESSOService(
      configuration: SSOConfiguration(clientID: normalizedClientID)
    )
    authServices[normalizedClientID] = service
    return service
  }

  func refreshActiveBuild() async {
    let active = try? await catalog.activeSDEVersion()
    activeSDEBuild = active?.buildNumber
    activeSDEContentSHA256 = active?.contentSHA256
  }

  func refreshEVEOnlineServiceStatus(force: Bool = false) async {
    let now = Date()
    if !force,
      let lastEVEOnlineStatusCheckAt,
      now.timeIntervalSince(lastEVEOnlineStatusCheckAt) < 60
    {
      return
    }
    lastEVEOnlineStatusCheckAt = now
    do {
      eveOnlineServiceStatus = try await eveOnlineStatusClient.fetch()
      eveOnlineStatusCheckFailed = false
    } catch is CancellationError {
      return
    } catch {
      eveOnlineStatusCheckFailed = true
    }
  }

  private func makeSDELifecycle(ownerContact: String) throws
    -> SDELifecycleService
  {
    try SDELifecycleService(
      rootURL: dataRoot.appendingPathComponent("sde", isDirectory: true),
      ownerContact: ownerContact
    )
  }

  private func perform(
    _ status: String,
    operation: () async throws -> Void
  ) async {
    isWorking = true
    errorMessage = nil
    statusMessage = status
    defer {
      isWorking = false
      if errorMessage == nil, statusMessage == status {
        statusMessage = "Ready"
      }
    }
    do {
      try await operation()
    } catch is CancellationError {
      statusMessage = "Cancelled"
    } catch ESIError.cancelled {
      statusMessage = "Cancelled"
    } catch {
      errorMessage = String(describing: error)
      statusMessage = "Failed"
    }
  }
}

private struct MoonMaterialMarketRefreshResult: Sendable {
  let location: MoonMaterialMarketLocation
  let result: Sourced<MarketOrderSnapshot>
}
