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
  @Published private(set) var mainHubMarketState: Sourced<MarketOrderSummarySnapshot>?
  @Published private(set) var mainHubMarketAutomaticUpdatesEnabled = true
  @Published private(set) var mainHubMarketNextAutomaticRunAt: Date?
  @Published private(set) var isAutomaticallyRefreshingMainHubMarket = false
  @Published private(set) var mineralPriceTickerState: Sourced<[MineralPriceTrend]>?
  @Published private(set) var isRefreshingMineralPrices = false
  @Published private(set) var dashboardWealthSnapshot: DashboardWealthSnapshot?
  @Published private(set) var dashboardWealthError: String?
  @Published private(set) var isRefreshingDashboardWealth = false
  @Published private(set) var manufacturingOpportunityAnalysis: ManufacturingOpportunitySnapshot?
  @Published private(set) var manufacturingOpportunityProgress =
    ManufacturingOpportunityScanProgress()
  @Published private(set) var isAnalyzingManufacturingOpportunities = false
  @Published private(set) var manufacturingOpportunityError: String?
  @Published private(set) var manufacturingOpportunitySnapshotError: String?
  @Published private(set) var manufacturingOpportunityDemand:
    ManufacturingOpportunityDemandSnapshot?
  @Published private(set) var manufacturingOpportunityDemandError: String?
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
  @Published private(set) var publicContractProgress = PublicContractSyncProgress()
  @Published private(set) var publicContractResults: [PublicContractSearchResult] = []
  @Published private(set) var publicContractCategories: [PublicContractFacet] = []
  @Published private(set) var publicContractGroups: [PublicContractFacet] = []
  @Published private(set) var publicContractError: String?
  @Published private(set) var isSynchronizingPublicContracts = false
  @Published private(set) var publicContractAutomaticUpdatesEnabled = false
  @Published private(set) var publicContractNextAutomaticRunAt: Date?

  private let esi: ESIClient
  private let eveOnlineStatusClient = EVEOnlineStatusClient()
  private let solarSystemSearch: SolarSystemSearchService
  private let playerStructureSearch: PlayerStructureSearchService
  private let tradingLocationSearch: TradingLocationSearchService
  private let universeNameService: UniverseNameService
  private let catalog: SQLiteStaticCatalog
  private let publicContractIndexer: PublicContractIndexer?
  private let assetWarehouseProjectionCache =
    StoredAssetWarehouseProjectionCache()
  private let manufacturingOpportunityDemandStore: ManufacturingOpportunityDemandStore
  private let manufacturingOpportunitySnapshotStore: ManufacturingOpportunitySnapshotStore
  private let dataRoot: URL
  private let ccpUserAgentOwnerContact: String?
  private var authServices: [String: EVESSOService] = [:]
  private var hasLoadedProfileReferenceData = false
  private var profileReferenceRefreshTask: Task<Void, Never>?
  private var lastEVEOnlineStatusCheckAt: Date?
  private var moonMaterialRefreshIdentity: String?
  private var publicContractSyncTask: Task<Void, Never>?
  private var publicContractAutomationTask: Task<Void, Never>?
  private var hasPreparedPublicContractAutomation = false
  private var mainHubMarketAutomationTask: Task<Void, Never>?
  private var preparedMainHubMarketIdentity: String?

  private static let moonMaterialMinimumRefreshInterval: TimeInterval = 5 * 60
  private static let mainHubMarketAutomationEnabledKey =
    "market.main-hub.automatic-updates-enabled"
  private static let mainHubMarketAutomationConsentVersionKey =
    "market.main-hub.automatic-updates-consent-version"
  private static let mainHubMarketAutomationConsentVersion = 1

  init(
    dataRoot providedDataRoot: URL? = nil,
    ccpUserAgentOwnerContact: String? = nil,
    startBackgroundServices: Bool = true
  ) {
    self.ccpUserAgentOwnerContact =
      CCPUserAgentConfiguration.normalizedOwnerContact(
        ccpUserAgentOwnerContact
      )
    let userAgent = CCPUserAgentConfiguration.value(
      ownerContact: self.ccpUserAgentOwnerContact
    )
    let esi = ESIClient(userAgent: userAgent)
    self.esi = esi
    self.solarSystemSearch = SolarSystemSearchService(esi: esi)
    self.playerStructureSearch = PlayerStructureSearchService(esi: esi)
    self.tradingLocationSearch = TradingLocationSearchService(esi: esi)
    self.universeNameService = UniverseNameService(esi: esi)
    let resolvedDataRoot = providedDataRoot ?? Self.fallbackDataRoot()
    dataRoot = resolvedDataRoot
    manufacturingOpportunityDemandStore = ManufacturingOpportunityDemandStore(
      fileURL:
        resolvedDataRoot
        .appendingPathComponent("market", isDirectory: true)
        .appendingPathComponent("main-hub-demand.json")
    )
    manufacturingOpportunitySnapshotStore = ManufacturingOpportunitySnapshotStore(
      fileURL:
        resolvedDataRoot
        .appendingPathComponent("market", isDirectory: true)
        .appendingPathComponent("main-hub-opportunities.json")
    )
    let catalog = SQLiteStaticCatalog(
      rootURL:
        resolvedDataRoot
        .appendingPathComponent("sde", isDirectory: true)
        .appendingPathComponent("catalog-store", isDirectory: true)
    )
    self.catalog = catalog
    let contractStoreURL =
      resolvedDataRoot
      .appendingPathComponent("contracts", isDirectory: true)
      .appendingPathComponent("public-contracts.sqlite")
    if startBackgroundServices,
      let store = try? PublicContractStore(url: contractStoreURL)
    {
      publicContractIndexer = PublicContractIndexer(
        remote: ESIPublicContractRemote(
          esi: esi,
          universeNames: universeNameService
        ),
        catalog: catalog,
        store: store
      )
    } else if startBackgroundServices {
      publicContractIndexer = nil
      publicContractProgress = PublicContractSyncProgress(
        phase: .failed,
        message: "esi.public-contracts.store-unavailable"
      )
      publicContractError =
        "The local Public Contracts index could not be opened."
    } else {
      // If SwiftData could not be opened safely, keep the whole runtime inert.
      // The recovery-only screen must not migrate secondary stores or start
      // background ESI work while the owner is deciding how to recover data.
      publicContractIndexer = nil
    }
    let defaults = AppDefaults.store
    if startBackgroundServices,
      defaults.integer(
        forKey: Self.mainHubMarketAutomationConsentVersionKey
      ) < Self.mainHubMarketAutomationConsentVersion
    {
      // Earlier builds silently enabled this catalog-wide scan. Pause it once
      // so the expensive background work only resumes after an explicit choice.
      defaults.set(
        false,
        forKey: Self.mainHubMarketAutomationEnabledKey
      )
      defaults.set(
        Self.mainHubMarketAutomationConsentVersion,
        forKey: Self.mainHubMarketAutomationConsentVersionKey
      )
    }
    mainHubMarketAutomaticUpdatesEnabled =
      startBackgroundServices
      && defaults.bool(forKey: Self.mainHubMarketAutomationEnabledKey)
    guard startBackgroundServices else { return }
    Task {
      async let activeBuild: Void = refreshActiveBuild()
      async let serviceStatus: Void = refreshEVEOnlineServiceStatus()
      async let demand: Void = loadManufacturingOpportunityDemand()
      async let opportunities: Void = loadManufacturingOpportunityAnalysis()
      async let contracts: Void = preparePublicContractAutomation()
      _ = await (
        activeBuild,
        serviceStatus,
        demand,
        opportunities,
        contracts
      )
    }
  }

  func loadManufacturingOpportunityDemand() async {
    do {
      manufacturingOpportunityDemand =
        try await manufacturingOpportunityDemandStore.currentDemand()
      manufacturingOpportunityDemandError = nil
    } catch {
      manufacturingOpportunityDemandError =
        "The stored Main Hub demand observations could not be read. Existing data was not replaced."
    }
  }

  func loadManufacturingOpportunityAnalysis() async {
    guard manufacturingOpportunityAnalysis == nil else { return }
    do {
      let stored = try await manufacturingOpportunitySnapshotStore.load()
      guard manufacturingOpportunityAnalysis == nil else { return }
      manufacturingOpportunityAnalysis = stored
      manufacturingOpportunitySnapshotError = nil
    } catch {
      manufacturingOpportunitySnapshotError =
        "The last saved Main Hub item list could not be read. Existing data was not replaced."
    }
  }

  func shouldAutomaticallyRefreshManufacturingOpportunities(
    now: Date = .now
  ) -> Bool {
    ManufacturingOpportunityAutomaticRefreshPolicy.shouldRefresh(
      lastObservedAt: manufacturingOpportunityDemand?.lastObservedAt,
      now: now
    )
  }

  func prepareMainHubMarketAutomation() {
    guard isPlannerConfigurationReady,
      let mainHub = productionBasis.mainTradingLocation?.location,
      mainHub.kind == .npcTradeHub,
      let regionID = mainHub.regionID,
      let locationID = mainHub.locationID
    else {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketNextAutomaticRunAt = nil
      preparedMainHubMarketIdentity = nil
      return
    }
    let identity = "\(regionID):\(locationID)"
    if preparedMainHubMarketIdentity != identity {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketNextAutomaticRunAt = nil
      mainHubMarketState = nil
      manufacturingOpportunityProgress = ManufacturingOpportunityScanProgress()
      manufacturingOpportunityError = nil
      preparedMainHubMarketIdentity = identity
    }
    scheduleAutomaticMainHubMarketRefresh()
  }

  func setMainHubMarketAutomaticUpdatesEnabled(_ enabled: Bool) {
    AppDefaults.store.set(
      enabled,
      forKey: Self.mainHubMarketAutomationEnabledKey
    )
    AppDefaults.store.set(
      Self.mainHubMarketAutomationConsentVersion,
      forKey: Self.mainHubMarketAutomationConsentVersionKey
    )
    mainHubMarketAutomaticUpdatesEnabled = enabled
    if enabled {
      prepareMainHubMarketAutomation()
    } else {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketNextAutomaticRunAt = nil
      isAutomaticallyRefreshingMainHubMarket = false
    }
  }

  private func scheduleAutomaticMainHubMarketRefresh(
    retryAfter: TimeInterval? = nil
  ) {
    guard mainHubMarketAutomaticUpdatesEnabled,
      preparedMainHubMarketIdentity != nil,
      mainHubMarketAutomationTask == nil
    else { return }
    let now = Date()
    let lastObservedAt = matchingMainHubLastObservedAt
    let scheduledAt =
      retryAfter.map { now.addingTimeInterval($0) }
      ?? ManufacturingOpportunityAutomaticRefreshPolicy.nextAutomaticRunAt(
        lastObservedAt: lastObservedAt,
        now: now
      )
    mainHubMarketNextAutomaticRunAt = scheduledAt
    mainHubMarketAutomationTask = Task { [weak self] in
      do {
        try await Task.sleep(
          for: .seconds(max(0, scheduledAt.timeIntervalSinceNow))
        )
      } catch {
        return
      }
      guard let self,
        self.mainHubMarketAutomaticUpdatesEnabled
      else { return }
      if !self.shouldAutomaticallyRefreshManufacturingOpportunities() {
        self.mainHubMarketAutomationTask = nil
        self.mainHubMarketNextAutomaticRunAt = nil
        self.scheduleAutomaticMainHubMarketRefresh()
        return
      }
      if self.isAnalyzingManufacturingOpportunities {
        self.mainHubMarketAutomationTask = nil
        self.mainHubMarketNextAutomaticRunAt = nil
        self.scheduleAutomaticMainHubMarketRefresh(retryAfter: 60)
        return
      }
      self.mainHubMarketNextAutomaticRunAt = nil
      self.isAutomaticallyRefreshingMainHubMarket = true
      await self.analyzeManufacturingOpportunities(
        settings:
          self.manufacturingOpportunityAnalysis?.settings
          ?? ManufacturingOpportunitySettings(),
        isAutomatic: true
      )
      self.isAutomaticallyRefreshingMainHubMarket = false
      self.mainHubMarketAutomationTask = nil
      self.scheduleAutomaticMainHubMarketRefresh(
        retryAfter: self.manufacturingOpportunityError == nil
          ? nil : 30 * 60
      )
    }
  }

  private var matchingMainHubLastObservedAt: Date? {
    guard let mainHub = productionBasis.mainTradingLocation?.location,
      let regionID = mainHub.regionID,
      let locationID = mainHub.locationID
    else { return nil }
    let marketObservedAt = mainHubMarketState?.value.flatMap { market in
      market.regionID == regionID && market.locationID == locationID
        ? market.capturedAt : nil
    }
    let demandObservedAt = manufacturingOpportunityDemand.flatMap { demand in
      demand.regionID == regionID && demand.locationID == locationID
        ? demand.lastObservedAt : nil
    }
    return [marketObservedAt, demandObservedAt].compactMap { $0 }.max()
  }

  func loadPublicContractBrowser() async {
    guard let publicContractIndexer else { return }
    do {
      if !isSynchronizingPublicContracts {
        publicContractProgress = try await publicContractIndexer.localProgress()
      }
      let facets = try await publicContractIndexer.facets()
      publicContractCategories = facets.categories
      publicContractGroups = facets.groups
      let automation = try await publicContractIndexer.automationState(
        regularRefreshInterval:
          PublicContractAutomationPolicy.regularRefreshInterval
      )
      publicContractAutomaticUpdatesEnabled = automation.isEnabled
      if automation.isEnabled,
        publicContractAutomationTask == nil,
        publicContractSyncTask == nil
      {
        await scheduleAutomaticPublicContractSynchronization(
          state: automation
        )
      }
      publicContractError = nil
    } catch {
      publicContractError =
        "The local Public Contracts index could not be read. Existing data was not replaced."
    }
  }

  func searchPublicContracts(_ filter: PublicContractSearchFilter) async {
    guard let publicContractIndexer else { return }
    do {
      publicContractResults = try await publicContractIndexer.search(filter)
      publicContractError = nil
    } catch is CancellationError {
      return
    } catch {
      publicContractError =
        "Public Contracts could not be searched. Existing results were not replaced."
    }
  }

  func refreshPublicContractFacets() async {
    guard let publicContractIndexer else { return }
    do {
      let facets = try await publicContractIndexer.facets()
      publicContractCategories = facets.categories
      publicContractGroups = facets.groups
    } catch {
      publicContractError =
        "The Public Contracts filters could not be refreshed."
    }
  }

  func startPublicContractSynchronization() {
    beginPublicContractSynchronization(manualStart: true)
  }

  func cancelPublicContractSynchronization() {
    publicContractAutomaticUpdatesEnabled = false
    publicContractNextAutomaticRunAt = nil
    publicContractAutomationTask?.cancel()
    publicContractAutomationTask = nil
    publicContractSyncTask?.cancel()
    guard let publicContractIndexer else { return }
    Task {
      try? await publicContractIndexer.setAutomaticUpdatesEnabled(false)
      try? await publicContractIndexer.setAutomaticSafetyNotBefore(nil)
    }
  }

  private func preparePublicContractAutomation() async {
    guard !hasPreparedPublicContractAutomation,
      let publicContractIndexer
    else { return }
    hasPreparedPublicContractAutomation = true
    do {
      publicContractProgress = try await publicContractIndexer.localProgress()
      let automation = try await publicContractIndexer.automationState(
        regularRefreshInterval:
          PublicContractAutomationPolicy.regularRefreshInterval
      )
      publicContractAutomaticUpdatesEnabled = automation.isEnabled
      if automation.isEnabled {
        await scheduleAutomaticPublicContractSynchronization(
          state: automation
        )
      }
    } catch {
      publicContractError =
        "The automatic Public Contracts schedule could not be loaded. No automatic request was started."
    }
  }

  private func beginPublicContractSynchronization(manualStart: Bool) {
    guard publicContractSyncTask == nil,
      let publicContractIndexer
    else { return }
    publicContractAutomationTask?.cancel()
    publicContractAutomationTask = nil
    publicContractNextAutomaticRunAt = nil
    if manualStart {
      publicContractAutomaticUpdatesEnabled = true
    }
    isSynchronizingPublicContracts = true
    publicContractError = nil
    publicContractSyncTask = Task { [weak self] in
      guard let self else { return }
      do {
        if manualStart {
          try await publicContractIndexer.setAutomaticUpdatesEnabled(true)
        }
        let automation = try await publicContractIndexer.automationState(
          regularRefreshInterval:
            PublicContractAutomationPolicy.regularRefreshInterval
        )
        self.publicContractAutomaticUpdatesEnabled = automation.isEnabled
        if PublicContractAutomationPolicy.shouldDeferStart(
          manualStart: manualStart,
          safetyNotBefore: automation.safetyNotBefore,
          now: Date()
        ) {
          self.isSynchronizingPublicContracts = false
          self.publicContractSyncTask = nil
          await self.scheduleAutomaticPublicContractSynchronization(
            state: automation
          )
          return
        }
        let result = try await publicContractIndexer.synchronizeAll { progress in
          self.publicContractProgress = progress
        }
        let safetyNotBefore = PublicContractAutomationPolicy.safetyNotBefore(
          after: result,
          now: Date()
        )
        try await publicContractIndexer.setAutomaticSafetyNotBefore(
          safetyNotBefore
        )
        await self.refreshPublicContractFacets()
      } catch {
        if !Task.isCancelled {
          self.publicContractError =
            "Public Contracts synchronization stopped safely. The local partial index was preserved."
          try? await publicContractIndexer.setAutomaticSafetyNotBefore(
            Date().addingTimeInterval(30 * 60)
          )
        }
      }
      self.isSynchronizingPublicContracts = false
      self.publicContractSyncTask = nil
      guard self.publicContractAutomaticUpdatesEnabled else { return }
      let nextState = try? await publicContractIndexer.automationState(
        regularRefreshInterval:
          PublicContractAutomationPolicy.regularRefreshInterval
      )
      await self.scheduleAutomaticPublicContractSynchronization(
        state: nextState
      )
    }
  }

  private func scheduleAutomaticPublicContractSynchronization(
    state suppliedState: PublicContractAutomationState? = nil
  ) async {
    guard publicContractSyncTask == nil,
      publicContractAutomationTask == nil,
      publicContractAutomaticUpdatesEnabled,
      let publicContractIndexer
    else { return }
    let state: PublicContractAutomationState
    do {
      if let suppliedState {
        state = suppliedState
      } else {
        state = try await publicContractIndexer.automationState(
          regularRefreshInterval:
            PublicContractAutomationPolicy.regularRefreshInterval
        )
      }
    } catch {
      publicContractError =
        "The next automatic Public Contracts update could not be scheduled. Existing data remains available."
      return
    }
    guard state.isEnabled else {
      publicContractAutomaticUpdatesEnabled = false
      publicContractNextAutomaticRunAt = nil
      return
    }
    let earliest = Date().addingTimeInterval(
      PublicContractAutomationPolicy.startupDelay
    )
    let scheduledAt = max(state.nextAutomaticRunAt ?? earliest, earliest)
    publicContractNextAutomaticRunAt = scheduledAt
    publicContractAutomationTask = Task { [weak self] in
      do {
        try await Task.sleep(
          for: .seconds(max(0, scheduledAt.timeIntervalSinceNow))
        )
      } catch {
        return
      }
      guard let self,
        self.publicContractAutomaticUpdatesEnabled
      else { return }
      self.publicContractAutomationTask = nil
      self.publicContractNextAutomaticRunAt = nil
      self.beginPublicContractSynchronization(manualStart: false)
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

  func preparePlannerConfiguration(
    encodedBasis: Data?,
    capabilities: [CharacterCapabilitySnapshot] = []
  ) async {
    isPlannerConfigurationReady = false
    if let encodedBasis {
      do {
        productionBasis = try JSONDecoder().decode(
          ProductionBasis.self,
          from: encodedBasis
        )
        productionBasis.refreshResolvableMarketFees(
          capabilities: capabilities
        )
      } catch {
        errorMessage =
          "The saved production configuration could not be loaded."
      }
    }
    await refreshProfileReferenceData()
    isPlannerConfigurationReady = true
    prepareMainHubMarketAutomation()
  }

  func calculate(
    input: String,
    manualStockInput: String = "",
    existingReservations: [StockAllocation] = [],
    assetWarehouse: AssetWarehouse? = nil,
    stockTargets: [Int64: Int64] = [:],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    defaultPurchaseLocation: ProcurementLocation? = nil,
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = ""
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
      guard let configuredMainHub = productionBasis.mainTradingLocation,
        configuredMainHub.location.kind == .npcTradeHub,
        let mainRegionID = configuredMainHub.location.regionID,
        let mainLocationID = configuredMainHub.location.locationID
      else {
        throw ESIError.notFound
      }
      let mainPurchaseLocation =
        defaultPurchaseLocation ?? configuredMainHub.location
      let configuredHomeHub = productionBasis.homeTradingLocation
      let marketService = JitaMarketService(esi: esi)
      async let market = marketService.orderSnapshot(
        typeIDs: typeIDs,
        regionID: mainRegionID,
        locationID: mainLocationID
      )
      async let adjusted = marketService.adjustedPrices()
      async let systems = marketService.industrySystems()
      let values = try await (market, adjusted, systems)
      var homeMarket: MarketOrderSnapshot?
      var homeMarketWarnings: [DomainWarning] = []
      if let configuredHomeHub {
        if configuredMainHub.location.representsSameLocation(
          as: configuredHomeHub.location
        ) {
          homeMarket = values.0
        } else {
          do {
            homeMarket = try await plannerMarketSnapshot(
              typeIDs: typeIDs,
              location: configuredHomeHub.location,
              preferredTraderCharacterID:
                configuredHomeHub.marketTaxes.traderCharacterID,
              authorizations: authorizations,
              clientID: clientID
            )
          } catch is CancellationError {
            throw CancellationError()
          } catch ESIError.cancelled {
            throw CancellationError()
          } catch {
            homeMarketWarnings.append(
              DomainWarning(
                code: "planner.home-market-unavailable",
                message:
                  "The Home Hub market could not be loaded. Home Hub sale scenarios remain unavailable; the Main Hub plan was preserved.",
                severity: .warning
              )
            )
          }
        }
      } else {
        homeMarketWarnings.append(
          DomainWarning(
            code: "planner.home-hub-not-configured",
            message:
              "No Home Hub is configured. Home Hub sale scenarios remain unavailable.",
            severity: .warning
          )
        )
      }
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
          purchaseLocation: mainPurchaseLocation,
          usesAvailableStockFirst: preference.usesAvailableStockFirst
        )
      }
      let context = IndustryPlanningContext(
        manufacturingProfile: manufacturingProfile,
        reactionProfile: configuredReaction,
        productionBasis: productionBasis,
        catalog: planningCatalog,
        market: values.0,
        homeMarket: homeMarket,
        adjustedPrices: values.1,
        systemIndices: values.2,
        availableStock: availableStock,
        procurementPreferences: acceptedProcurementPreferences,
        defaultPurchaseLocation: mainPurchaseLocation,
        assetSource: assetSource,
        sdeBuild: active.buildNumber,
        snapshotIDs: snapshotIDs,
        inputWarnings: inputWarnings,
        homeMarketWarnings: homeMarketWarnings,
        salesTaxRate: configuredMainHub.marketTaxes.effectiveSalesTaxRate,
        brokerFeeRate: configuredMainHub.marketTaxes.effectiveBrokerFeeRate,
        homeSalesTaxRate:
          configuredHomeHub?.marketTaxes.effectiveSalesTaxRate,
        homeBrokerFeeRate:
          configuredHomeHub?.marketTaxes.effectiveBrokerFeeRate
      )
      plan = try await planner.plan(input: input, context: context)
    }
  }

  private func plannerMarketSnapshot(
    typeIDs: Set<Int64>,
    location: ProcurementLocation,
    preferredTraderCharacterID: Int64?,
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async throws -> MarketOrderSnapshot {
    let marketService = TradeHubMarketService(esi: esi)
    switch location.kind {
    case .npcTradeHub:
      guard let regionID = location.regionID,
        let locationID = location.locationID
      else { throw ESIError.notFound }
      return try await marketService.orderSnapshot(
        typeIDs: typeIDs,
        regionID: regionID,
        locationID: locationID
      )
    case .playerStructure:
      guard let structureID = location.locationID,
        let systemID = location.solarSystemID
      else { throw ESIError.notFound }
      let authorization = await moonMaterialStructureAuthorization(
        authorizations: authorizations,
        clientID: clientID
      )
      guard case .available(let leasesByCharacterID) = authorization else {
        switch authorization {
        case .missingScope:
          throw ESIError.missingScope(
            TradeHubMarketService.structureMarketScope
          )
        case .authorizationRequired, .unavailable, .available:
          throw ESIError.authorizationRequired
        }
      }
      let system = try await solarSystemSearch.details(systemID: systemID)
      let leases = leasesByCharacterID.values.sorted {
        if $0.characterID == preferredTraderCharacterID { return true }
        if $1.characterID == preferredTraderCharacterID { return false }
        return $0.characterID < $1.characterID
      }
      var lastError: Error = ESIError.authorizationRequired
      for lease in leases {
        do {
          return try await marketService.structureOrderSnapshot(
            typeIDs: typeIDs,
            regionID: system.regionID,
            systemID: systemID,
            structureID: structureID,
            lease: lease
          )
        } catch is CancellationError {
          throw CancellationError()
        } catch ESIError.cancelled {
          throw CancellationError()
        } catch {
          lastError = error
        }
      }
      throw lastError
    case .legacy:
      throw ESIError.notFound
    }
  }

  func manufacturingProductionTree(
    productName: String,
    targetQuantity: Int64,
    materialEfficiency: Int,
    timeEfficiency: Int,
    assetWarehouse: AssetWarehouse,
    warehouseHasSnapshot: Bool,
    stockTargets: [Int64: Int64] = [:],
    existingReservations: [StockAllocation] = [],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    blueprintInventories: [OwnedBlueprintInventory] = []
  ) async throws -> ManufacturingProductionTreeSnapshot {
    guard targetQuantity > 0,
      (0...10).contains(materialEfficiency),
      (0...20).contains(timeEfficiency)
    else { throw ManufacturingOpportunityError.invalidSettings }
    guard let active = try await catalog.activeSDEVersion() else {
      throw StaticCatalogError.noActiveCatalog
    }
    guard let configuredMainHub = productionBasis.mainTradingLocation,
      configuredMainHub.location.kind == .npcTradeHub,
      let mainRegionID = configuredMainHub.location.regionID,
      let mainLocationID = configuredMainHub.location.locationID
    else { throw ESIError.notFound }

    let request = ProductionRequestLine(
      lineNumber: 1,
      productName: productName,
      wantedQuantity: Int(targetQuantity),
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency
    )
    let input = ProductionInputFormatter.format([request])
    let planner = IndustryPlanner()
    let planningCatalog = MemoizedIndustryCatalog(base: catalog)
    let typeIDs = try await planner.requiredMarketTypeIDs(
      input: input,
      catalog: planningCatalog
    )
    let market = try await TradeHubMarketService(esi: esi).orderSnapshot(
      typeIDs: typeIDs,
      regionID: mainRegionID,
      locationID: mainLocationID
    )
    let marketService = TradeHubMarketService(esi: esi)
    async let adjustedValue = marketService.adjustedPrices()
    async let systemsValue = marketService.industrySystems()
    let (adjusted, systems) = try await (adjustedValue, systemsValue)

    var allocatableStock: [Int64: Int64] = [:]
    var snapshotIDs: [UUID] = []
    var inputWarnings: [DomainWarning] = []
    let warehouseSource: StockSource?
    if warehouseHasSnapshot {
      let availability = assetWarehouse.availability(
        targetQuantities: stockTargets
      )
      allocatableStock = availability.allocatableQuantities
      snapshotIDs = assetWarehouse.snapshotIDs
      warehouseSource = StockSource(
        kind: .warehouse,
        reference: "production-activity-locations"
      )
      if assetWarehouse.sourceStates.contains(where: { $0 != .fresh }) {
        inputWarnings.append(
          DomainWarning(
            code: "production-tree.warehouse-not-fresh",
            message:
              "At least one production-warehouse source is not fresh. Its retained quantities remain visible with provenance.",
            severity: .warning
          )
        )
      }
    } else {
      warehouseSource = nil
      inputWarnings.append(
        DomainWarning(
          code: "production-tree.warehouse-unavailable",
          message:
            "Production-warehouse coverage is unavailable and is not treated as zero stock.",
          severity: .warning
        )
      )
    }
    if warehouseSource != nil {
      for allocation in existingReservations
      where allocation.source.kind == .warehouse
        || allocation.source.kind == .assetSnapshot
      {
        allocatableStock[allocation.typeID] = max(
          0,
          allocatableStock[allocation.typeID, default: 0]
            - allocation.quantity
        )
      }
    }

    var calculatorBasis = productionBasis
    calculatorBasis.logistics.isEnabled = true
    calculatorBasis.logistics.homeTradeHub = configuredMainHub.location
    calculatorBasis.logistics.marketLocationName = configuredMainHub.location.name
    calculatorBasis.logistics.includeInboundMaterials = true
    calculatorBasis.logistics.includeOutboundProducts = true
    let configuredReaction =
      calculatorBasis.configuredReactionProfile ?? reactionProfile
    func context(
      availableStock: [Int64: Int64],
      preferences: [Int64: MaterialProcurementPreference],
      warnings: [DomainWarning]
    ) -> IndustryPlanningContext {
      IndustryPlanningContext(
        manufacturingProfile: manufacturingProfile,
        reactionProfile: configuredReaction,
        productionBasis: calculatorBasis,
        catalog: planningCatalog,
        market: market,
        adjustedPrices: adjusted,
        systemIndices: systems,
        availableStock: availableStock,
        procurementPreferences: preferences,
        defaultPurchaseLocation: configuredMainHub.location,
        assetSource: warehouseSource,
        sdeBuild: active.buildNumber,
        snapshotIDs: snapshotIDs,
        inputWarnings: warnings,
        salesTaxRate: configuredMainHub.marketTaxes.effectiveSalesTaxRate,
        brokerFeeRate: configuredMainHub.marketTaxes.effectiveBrokerFeeRate
      )
    }

    let referencePlan = try await planner.plan(
      input: input,
      context: context(
        availableStock: [:],
        preferences: [:],
        warnings: inputWarnings
      )
    )
    let recommendations = MakeOrBuyRecommendationApplication(
      materials: referencePlan.materials,
      existingPreferences: [:],
      mainHub: configuredMainHub.location
    )
    var selectedPreferences = recommendations.preferences
    for typeID in typeIDs {
      var preference =
        procurementPreferences[typeID]
        ?? selectedPreferences[typeID]
        ?? MaterialProcurementPreference(
          supplyMode: .buy,
          purchaseLocation: configuredMainHub.location
        )
      preference.purchaseLocation = configuredMainHub.location
      preference.usesAvailableStockFirst = true
      selectedPreferences[typeID] = preference
    }
    let selectedPlan = try await planner.plan(
      input: input,
      context: context(
        availableStock: allocatableStock,
        preferences: selectedPreferences,
        warnings: inputWarnings
      )
    )

    let blueprintTypeIDs = Set(
      referencePlan.nodes.compactMap(\.blueprintTypeID)
    )
    let blueprintNames = try await catalog.typeNames(ids: blueprintTypeIDs)
    var inventionDefinitions: [Int64: BlueprintDefinition] = [:]
    for blueprintTypeID in blueprintTypeIDs {
      if let definition = try await catalog.productionDefinition(
        productTypeID: blueprintTypeID
      ), definition.activity.kind == .invention {
        inventionDefinitions[blueprintTypeID] = definition
      }
    }
    var contractOffers: [Int64: [PublicContractSearchResult]] = [:]
    var publicContractCoverageComplete = false
    if let publicContractIndexer {
      do {
        let snapshot = try await publicContractIndexer.includedOfferSnapshot(
          typeIDs: blueprintTypeIDs,
          limitPerType: 100
        )
        contractOffers = snapshot.offers
        publicContractCoverageComplete =
          snapshot.progress.hasCompleteSearchCoverage
      } catch {
        if error is CancellationError {
          throw error
        }
      }
    }
    return ManufacturingProductionTreeProjector.project(
      targetQuantity: targetQuantity,
      mainHub: configuredMainHub.location,
      referencePlan: referencePlan,
      selectedPlan: selectedPlan,
      warehouse: assetWarehouse,
      warehouseHasSnapshot: warehouseHasSnapshot,
      protectedQuantities: stockTargets,
      reservedQuantities: Dictionary(
        grouping: existingReservations,
        by: \.typeID
      ).mapValues { values in
        values.reduce(0) {
          AssetWarehouse.saturatedAdd($0, max(0, $1.quantity))
        }
      },
      preferences: selectedPreferences,
      blueprintPortfolio: BlueprintPortfolio(
        inventories: blueprintInventories
      ),
      blueprintNames: blueprintNames,
      blueprintContractOffers: contractOffers,
      publicContractCoverageComplete: publicContractCoverageComplete,
      inventionDefinitions: inventionDefinitions,
      productionScope: calculatorBasis.productionWarehouseScope
    )
  }

  func analyzeReactions(
    runs requestedRuns: Int,
    marketHub: MarketHubConfigurationSnapshot,
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = ""
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
      async let packagedVolumesValue = catalog.packagedVolumes(typeIDs: typeIDs)
      let marketValue: MarketOrderSnapshot
      if marketHub.location.kind == .playerStructure {
        guard let structureID = marketHub.location.locationID,
          let systemID = marketHub.location.solarSystemID
        else { throw ESIError.notFound }
        let authorization = await moonMaterialStructureAuthorization(
          authorizations: authorizations,
          clientID: clientID
        )
        guard case .available(let leases) = authorization else {
          switch authorization {
          case .missingScope:
            throw ESIError.missingScope(
              TradeHubMarketService.structureMarketScope
            )
          case .authorizationRequired, .unavailable:
            throw ESIError.authorizationRequired
          case .available:
            throw ESIError.authorizationRequired
          }
        }
        let system = try await solarSystemSearch.details(systemID: systemID)
        let regionID = system.regionID
        var loaded: MarketOrderSnapshot?
        var lastError: Error = ESIError.authorizationRequired
        for lease in leases.values.sorted(by: {
          $0.characterID < $1.characterID
        }) {
          do {
            loaded = try await marketService.structureOrderSnapshot(
              typeIDs: typeIDs,
              regionID: regionID,
              systemID: systemID,
              structureID: structureID,
              lease: lease
            )
            break
          } catch { lastError = error }
        }
        guard let loaded else { throw lastError }
        marketValue = loaded
      } else {
        guard marketHub.location.kind == .npcTradeHub,
          let regionID = marketHub.location.regionID,
          let locationID = marketHub.location.locationID
        else { throw ESIError.notFound }
        marketValue = try await marketService.orderSnapshot(
          typeIDs: typeIDs,
          regionID: regionID,
          locationID: locationID
        )
      }
      async let adjustedValue = marketService.adjustedPrices()
      async let systemsValue = marketService.industrySystems()
      let (names, classifications, packagedVolumes, adjusted, systems) = try await (
        namesValue,
        classificationsValue,
        packagedVolumesValue,
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
        marketLocation: marketHub.location,
        market: marketValue,
        adjustedPrices: adjusted,
        facility: facility,
        logistics: reactionLogisticsCostContext(
          origin: marketHub.location,
          packagedVolumes: packagedVolumes
        )
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

  func analyzeManufacturingOpportunities(
    settings: ManufacturingOpportunitySettings,
    isAutomatic: Bool = false
  ) async {
    guard !isAnalyzingManufacturingOpportunities else { return }
    if !isAutomatic {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketNextAutomaticRunAt = nil
    }
    isAnalyzingManufacturingOpportunities = true
    manufacturingOpportunityError = nil
    manufacturingOpportunityProgress = ManufacturingOpportunityScanProgress()
    defer {
      isAnalyzingManufacturingOpportunities = false
      if !isAutomatic {
        scheduleAutomaticMainHubMarketRefresh(
          retryAfter: manufacturingOpportunityError == nil
            ? nil : 30 * 60
        )
      }
    }
    do {
      guard try await catalog.activeSDEVersion() != nil else {
        throw StaticCatalogError.noActiveCatalog
      }
      guard let configuredMainHub = productionBasis.mainTradingLocation,
        configuredMainHub.location.kind == .npcTradeHub,
        let regionID = configuredMainHub.location.regionID,
        let locationID = configuredMainHub.location.locationID
      else { throw ESIError.notFound }

      let service = TradeHubMarketService(esi: esi)
      async let definitionsValue = catalog.manufacturingDefinitions()
      async let marketValue = service.locationOrderSnapshot(
        regionID: regionID,
        locationID: locationID
      ) { [weak self] completed, total in
        await MainActor.run {
          self?.manufacturingOpportunityProgress =
            ManufacturingOpportunityScanProgress(
              completedPages: completed,
              totalPages: total
            )
        }
      }
      async let adjustedValue = service.adjustedPrices()
      async let systemsValue = service.industrySystems()
      let (definitions, market, adjusted, systems) = try await (
        definitionsValue, marketValue, adjustedValue, systemsValue
      )
      try Task.checkCancellation()
      await esi.removeCachedPublicResponses(
        pathPrefix: "/markets/\(regionID)/orders/"
      )
      let marketSummary = MarketOrderSummarySnapshot(snapshot: market)
      let latestMainHubMarket = Sourced(
        state: market.state,
        value: marketSummary,
        source: market.source
      )
      mainHubMarketState = latestMainHubMarket.retainingLastKnownValue(
        from: mainHubMarketState
      )
      let demand: ManufacturingOpportunityDemandSnapshot?
      do {
        demand = try await manufacturingOpportunityDemandStore.observe(market)
        manufacturingOpportunityDemand = demand
        manufacturingOpportunityDemandError = nil
      } catch {
        demand = nil
        manufacturingOpportunityDemandError =
          "The Main Hub scan completed, but its demand observation could not be stored. Existing observations were not replaced."
      }
      let productTypeIDs = Set(definitions.map(\.productTypeID))
      let allTypeIDs = Set(
        definitions.flatMap {
          [$0.productTypeID] + $0.activity.materials.map(\.typeID)
        }
      )
      async let namesValue = catalog.typeNames(ids: allTypeIDs)
      async let classificationsValue = catalog.industryClassifications(
        typeIDs: productTypeIDs
      )
      async let volumesValue = catalog.packagedVolumes(typeIDs: allTypeIDs)
      let (names, classifications, volumes) = try await (
        namesValue, classificationsValue, volumesValue
      )
      let facilities = manufacturingOpportunityFacilities(
        systemIndices: systems
      )
      let productionWarehouseScope = productionBasis.productionWarehouseScope
      let logisticsConfiguration = productionBasis.logistics
      let mainHub = configuredMainHub.location
      let salesTaxRate = configuredMainHub.marketTaxes.effectiveSalesTaxRate
      let brokerFeeRate = configuredMainHub.marketTaxes.effectiveBrokerFeeRate
      let analysisTask = Task.detached(
        priority: isAutomatic ? .utility : .userInitiated
      ) {
        try ManufacturingOpportunityAnalyzer.analyze(
          definitions: definitions,
          typeNames: names,
          classifications: classifications,
          packagedVolumes: volumes,
          settings: settings,
          mainHub: mainHub,
          productionWarehouseScope: productionWarehouseScope,
          logisticsConfiguration: logisticsConfiguration,
          market: market,
          demand: demand,
          adjustedPrices: adjusted,
          facilities: facilities,
          salesTaxRate: salesTaxRate,
          brokerFeeRate: brokerFeeRate
        )
      }
      let analysis = try await withTaskCancellationHandler {
        try await analysisTask.value
      } onCancel: {
        analysisTask.cancel()
      }
      manufacturingOpportunityAnalysis = analysis
      do {
        try await manufacturingOpportunitySnapshotStore.save(analysis)
        manufacturingOpportunitySnapshotError = nil
      } catch {
        manufacturingOpportunitySnapshotError =
          "The current Main Hub item list is visible, but it could not be saved for the next app start. Existing saved data was not replaced."
      }
    } catch is CancellationError {
      return
    } catch ESIError.cancelled {
      return
    } catch StaticCatalogError.noActiveCatalog {
      manufacturingOpportunityError =
        "No active SDE catalog is installed. Install or activate static data first."
    } catch ManufacturingOpportunityError.noManufacturingDefinitions {
      manufacturingOpportunityError =
        "The active SDE catalog contains no complete published manufacturing definitions."
    } catch {
      manufacturingOpportunityError =
        "The Main Hub opportunity scan could not be completed. \(error.localizedDescription)"
    }
  }

  private func manufacturingOpportunityFacilities(
    systemIndices: [IndustrySystemIndex]
  ) -> [ManufacturingCategory: ManufacturingOpportunityFacilityContext] {
    var result: [ManufacturingCategory: ManufacturingOpportunityFacilityContext] = [:]
    for category in ManufacturingCategory.allCases {
      guard let selection = productionBasis.selection(for: category),
        let structure = productionBasis.structure(id: selection.structureID),
        let system = productionBasis.manufacturingSystem(for: structure)
      else { continue }
      guard
        let index = system.costIndexOverride
          ?? systemIndices.first(where: {
            $0.solarSystemID == system.solarSystemID
              && $0.activity == .manufacturing
          })?.costIndex
      else { continue }
      result[category] = ManufacturingOpportunityFacilityContext(
        name: "\(selection.structureName) · \(system.solarSystemName)",
        materialMultiplier: selection.materialMultiplier,
        timeMultiplier: selection.timeMultiplier,
        jobCostMultiplier: structure.jobCostMultiplier,
        facilityTaxRate: structure.facilityTaxRate,
        systemCostIndex: index,
        sccSurchargeRate: IndustryRuleSet.current.manufacturingSCCRate,
        alphaSurchargeRate:
          productionBasis.cloneState == .alpha
          ? IndustryRuleSet.current.alphaSurchargeRate : 0,
        needsReview: selection.needsReview || structure.needsReview
      )
    }
    return result
  }

  func refreshMoonMaterialAnalysis(
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = ""
  ) async {
    guard !isRefreshingMoonMaterialAnalysis else { return }
    let hubs = productionBasis.marketHubSnapshots
    let refreshIdentity = moonMaterialAnalysisRefreshIdentity(
      hubs: hubs,
      authorizations: authorizations,
      clientID: clientID
    )
    if let analysis = moonMaterialAnalysis,
      moonMaterialRefreshIdentity == refreshIdentity
    {
      let age = Date().timeIntervalSince(analysis.refreshedAt)
      if age >= 0 && age < Self.moonMaterialMinimumRefreshInterval {
        moonMaterialAnalysisError = nil
        return
      }
    }
    isRefreshingMoonMaterialAnalysis = true
    moonMaterialAnalysisError = nil
    defer { isRefreshingMoonMaterialAnalysis = false }

    do {
      let materialCatalog = try await catalog.moonMaterials()
      let typeIDs = Set(materialCatalog.materials.map(\.id))
      let marketService = TradeHubMarketService(esi: esi)
      let preferredTraderIDs = Dictionary(
        uniqueKeysWithValues: productionBasis.tradingLocations.map {
          (
            $0.id,
            $0.marketTaxes.traderCharacterID
          )
        }
      )
      let structureAuthorization =
        await moonMaterialStructureAuthorization(
          authorizations: authorizations,
          clientID: clientID
        )
      try Task.checkCancellation()
      let attempts = await withTaskGroup(
        of: MoonMaterialMarketRefreshResult?.self,
        returning: [
          UUID: Sourced<MarketOrderSnapshot>
        ].self
      ) { group in
        for hub in hubs {
          group.addTask {
            do {
              let snapshot: MarketOrderSnapshot
              if hub.location.kind == .playerStructure {
                guard let structureID = hub.location.locationID,
                  let systemID = hub.location.solarSystemID
                else {
                  throw ESIError.notFound
                }
                switch structureAuthorization {
                case .authorizationRequired:
                  throw ESIError.authorizationRequired
                case .missingScope:
                  throw ESIError.missingScope(
                    TradeHubMarketService.structureMarketScope
                  )
                case .unavailable:
                  throw ESIError.http(401)
                case .available(let leasesByCharacterID):
                  let preferredCharacterID = preferredTraderIDs[hub.id] ?? nil
                  let orderedLeases = leasesByCharacterID.values.sorted {
                    if $0.characterID == preferredCharacterID { return true }
                    if $1.characterID == preferredCharacterID { return false }
                    return $0.characterID < $1.characterID
                  }
                  var lastError: Error = ESIError.authorizationRequired
                  var loadedSnapshot: MarketOrderSnapshot?
                  let system = try await self.solarSystemSearch.details(
                    systemID: systemID
                  )
                  let regionID = system.regionID
                  for lease in orderedLeases {
                    do {
                      loadedSnapshot =
                        try await marketService
                        .structureOrderSnapshot(
                          typeIDs: typeIDs,
                          regionID: regionID,
                          systemID: systemID,
                          structureID: structureID,
                          lease: lease
                        )
                      break
                    } catch is CancellationError {
                      throw CancellationError()
                    } catch ESIError.cancelled {
                      throw CancellationError()
                    } catch {
                      lastError = error
                    }
                  }
                  guard let loadedSnapshot else { throw lastError }
                  snapshot = loadedSnapshot
                }
              } else {
                guard hub.location.kind == .npcTradeHub,
                  let regionID = hub.location.regionID,
                  let locationID = hub.location.locationID
                else {
                  throw ESIError.notFound
                }
                snapshot = try await marketService.sellOrderSnapshot(
                  typeIDs: typeIDs,
                  regionID: regionID,
                  locationID: locationID
                )
              }
              return MoonMaterialMarketRefreshResult(
                hubID: hub.id,
                result: Sourced(
                  state: .fresh,
                  value: snapshot,
                  source: snapshot.source
                )
              )
            } catch is CancellationError {
              return nil
            } catch ESIError.cancelled {
              return nil
            } catch {
              let failure = Self.moonMaterialMarketFailure(error)
              return MoonMaterialMarketRefreshResult(
                hubID: hub.id,
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
        var values: [UUID: Sourced<MarketOrderSnapshot>] = [:]
        for await attempt in group {
          guard let attempt else { continue }
          values[attempt.hubID] = attempt.result
        }
        return values
      }
      guard !Task.isCancelled else { return }

      let canRetainPreviousMarkets =
        moonMaterialAnalysis?.materialCatalog.source.version
        == materialCatalog.source.version
      var markets: [UUID: Sourced<MarketOrderSnapshot>] = [:]
      for hub in hubs {
        guard let attempt = attempts[hub.id] else { continue }
        let previous =
          canRetainPreviousMarkets
          ? moonMaterialAnalysis?.configuredMarkets[hub.id] : nil
        let retainablePrevious: Sourced<MarketOrderSnapshot>?
        if hub.location.kind == .playerStructure {
          retainablePrevious =
            previous?.source.provider
              == TradeHubMarketService.structureMarketProvider
              && previous?.value?.locationID == hub.location.locationID
            ? previous : nil
        } else {
          retainablePrevious = previous
        }
        markets[hub.id] = attempt.retainingLastKnownValue(
          from: retainablePrevious
        )
      }
      moonMaterialAnalysis = MoonMaterialPurchaseAnalysisSnapshot(
        materialCatalog: materialCatalog,
        configuredHubs: hubs,
        configuredMarkets: markets,
        refreshedAt: .now
      )
      moonMaterialRefreshIdentity = refreshIdentity
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

  private func moonMaterialAnalysisRefreshIdentity(
    hubs: [MarketHubConfigurationSnapshot],
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) -> String {
    let marketIdentity = hubs.map { hub in
      let roles = hub.roles.map(\.rawValue).sorted().joined(separator: ",")
      let traderID = productionBasis.tradingLocations.first {
        $0.id == hub.id
      }?.marketTaxes.traderCharacterID
      return [
        hub.id.uuidString,
        hub.location.id,
        hub.location.locationID.map(String.init) ?? "",
        hub.location.regionID.map(String.init) ?? "",
        roles,
        traderID.map(String.init) ?? "",
      ].joined(separator: ":")
    }.joined(separator: "|")
    let authorizationIdentity = authorizations.map {
      [
        $0.id.uuidString,
        String($0.characterID),
        String($0.authorizedAt.timeIntervalSince1970),
        $0.scopes.sorted().joined(separator: ","),
      ].joined(separator: ":")
    }.sorted().joined(separator: "|")
    return [
      String(activeSDEBuild ?? -1),
      clientID.trimmingCharacters(in: .whitespacesAndNewlines),
      marketIdentity,
      authorizationIdentity,
    ].joined(separator: "#")
  }

  private func moonMaterialStructureAuthorization(
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async -> MoonMaterialStructureAuthorization {
    let normalizedClientID = clientID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalizedClientID.isEmpty, !authorizations.isEmpty else {
      return .authorizationRequired
    }
    let eligibleAuthorizations = authorizations.filter {
      $0.scopes.contains(TradeHubMarketService.structureMarketScope)
    }
    guard !eligibleAuthorizations.isEmpty else { return .missingScope }

    var leasesByCharacterID: [Int64: AccessTokenLease] = [:]
    for authorization in eligibleAuthorizations.sorted(by: {
      $0.characterID < $1.characterID
    }) {
      do {
        let lease = try await authService(
          clientID: normalizedClientID
        ).accessTokenLease(characterID: authorization.characterID)
        leasesByCharacterID[lease.characterID] = lease
      } catch is CancellationError {
        return .unavailable
      } catch {
        continue
      }
    }
    return leasesByCharacterID.isEmpty
      ? .unavailable : .available(leasesByCharacterID)
  }

  func refreshMarketBrowser(
    typeID: Int64,
    itemName: String,
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = ""
  ) async {
    guard !isRefreshingMarketBrowser else { return }
    isRefreshingMarketBrowser = true
    marketBrowserError = nil
    defer { isRefreshingMarketBrowser = false }

    do {
      let publicSnapshot = try await MarketBrowserService(
        esi: esi,
        universeNames: universeNameService,
        systemSecurity: solarSystemSearch
      ).snapshot(
        typeID: typeID,
        itemName: itemName
      )
      let latest = await resolvingMarketBrowserStructureNames(
        in: publicSnapshot,
        authorizations: authorizations,
        clientID: clientID
      )
      guard !Task.isCancelled else { return }
      let previous: Sourced<MarketBrowserSnapshot>? = marketBrowserState.flatMap {
        state in
        guard state.value?.typeID == typeID else { return nil }
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

  private func resolvingMarketBrowserStructureNames(
    in sourced: Sourced<MarketBrowserSnapshot>,
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async -> Sourced<MarketBrowserSnapshot> {
    guard let snapshot = sourced.value else { return sourced }
    let structureIDs = Set(
      snapshot.orders.lazy
        .filter(\.isPlayerStructure)
        .map(\.locationID)
    )
    guard !structureIDs.isEmpty else { return sourced }

    let normalizedClientID = clientID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let eligibleAuthorizations = authorizations.filter {
      $0.scopes.contains(PlayerStructureSearchService.detailScope)
    }.sorted { $0.characterID < $1.characterID }
    guard !normalizedClientID.isEmpty, !eligibleAuthorizations.isEmpty else {
      return marketBrowserStructureResult(
        sourced: sourced,
        snapshot: snapshot,
        names: [:],
        unresolvedCount: structureIDs.count,
        diagnostic: "esi.market-browser.structure-authorization-required"
      )
    }

    var unresolved = structureIDs
    var names: [Int64: String] = [:]
    for authorization in eligibleAuthorizations where !unresolved.isEmpty {
      do {
        let lease = try await authService(
          clientID: normalizedClientID
        ).accessTokenLease(characterID: authorization.characterID)
        let resolved = await playerStructureSearch.resolveKnownStructures(
          structureIDs: unresolved,
          lease: lease
        )
        for option in resolved.value ?? [] {
          names[option.id] = option.name
          unresolved.remove(option.id)
        }
      } catch is CancellationError {
        return sourced
      } catch {
        continue
      }
    }
    return marketBrowserStructureResult(
      sourced: sourced,
      snapshot: snapshot,
      names: names,
      unresolvedCount: unresolved.count,
      diagnostic: "esi.market-browser.structure-name-unavailable"
    )
  }

  private func marketBrowserStructureResult(
    sourced: Sourced<MarketBrowserSnapshot>,
    snapshot: MarketBrowserSnapshot,
    names: [Int64: String],
    unresolvedCount: Int,
    diagnostic: String
  ) -> Sourced<MarketBrowserSnapshot> {
    var diagnostics = sourced.diagnostics
    if unresolvedCount > 0 {
      diagnostics.append("\(diagnostic):\(unresolvedCount)")
    }
    diagnostics = Array(Set(diagnostics)).sorted()
    return Sourced(
      state:
        sourced.state == .fresh && unresolvedCount > 0
        ? .partial : sourced.state,
      value: snapshot.resolvingStructureNames(names),
      source: sourced.source,
      diagnostics: diagnostics
    )
  }

  nonisolated private static func moonMaterialMarketFailure(
    _ error: Error
  ) -> (state: DataFreshness, diagnostic: String) {
    guard let esiError = error as? ESIError else {
      return (.unavailable, "esi.moon-market.unavailable")
    }
    switch esiError {
    case .authorizationRequired:
      return (
        .forbidden,
        "esi.moon-market.structure-authorization-required"
      )
    case .missingScope:
      return (.forbidden, "esi.moon-market.structure-scope-missing")
    case .forbidden:
      return (.forbidden, "esi.moon-market.structure-access-forbidden")
    case .notFound:
      return (.unavailable, "esi.moon-market.structure-not-found")
    case .rateLimited:
      return (.unavailable, "esi.moon-market.rate-limited")
    case .http(401):
      return (.forbidden, "esi.moon-market.structure-token-unavailable")
    default:
      return (.unavailable, "esi.moon-market.unavailable")
    }
  }

  private func reactionFacilityCostContext(
    systemIndices: [IndustrySystemIndex]
  ) -> ReactionFacilityCostContext? {
    guard let selection = productionBasis.reactionSelection,
      !selection.needsReview,
      let profile = productionBasis.configuredReactionProfile,
      let structure = productionBasis.structure(id: selection.structureID),
      let system = productionBasis.systemConfiguration(
        for: .reaction,
        structure: structure
      )
    else { return nil }
    let systemIndex =
      system.costIndexOverride
      ?? systemIndices.first {
        $0.solarSystemID == profile.solarSystemID
          && $0.activity == .reaction
      }?.costIndex
    guard let systemIndex else { return nil }
    return ReactionFacilityCostContext(
      name: "\(profile.structureName) · \(system.solarSystemName)",
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

  private func reactionLogisticsCostContext(
    origin: ProcurementLocation,
    packagedVolumes: [Int64: Double]
  ) -> ReactionLogisticsCostContext {
    let selectedStructure = productionBasis.structure(
      id: productionBasis.reactionStructureID
    )
    return ReactionLogisticsCostContext(
      configuration: productionBasis.logistics,
      origin: origin,
      destinationName:
        selectedStructure?.name
        ?? productionBasis.configuredReactionProfile?.structureName
        ?? productionBasis.logistics.productionLocationName,
      destinationLocationID: selectedStructure?.structureID,
      packagedVolumes: packagedVolumes
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

  func refreshMineralPriceTicker() async {
    guard !isRefreshingMineralPrices else { return }
    isRefreshingMineralPrices = true
    defer { isRefreshingMineralPrices = false }

    let previous = mineralPriceTickerState
    let regionID =
      productionBasis.mainTradingLocation?.location.regionID
      ?? EVEConstants.theForgeRegionID
    var rows: [MineralPriceTrend] = []
    var diagnostics: [String] = []
    var source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )

    for mineral in MineralPriceTrendProjector.minerals {
      guard !Task.isCancelled else { return }
      do {
        let response = try await esi.get(
          [ESIMarketHistoryDTO].self,
          endpoint: ESIEndpoint(
            path: "/markets/\(regionID)/history/",
            query: [
              URLQueryItem(
                name: "type_id",
                value: String(mineral.typeID)
              )
            ]
          )
        )
        source = response.source
        if let row = MineralPriceTrendProjector.project(
          typeID: mineral.typeID,
          name: mineral.name,
          history: response.value
        ) {
          rows.append(row)
        } else {
          diagnostics.append("market.history.empty:\(mineral.typeID)")
        }
      } catch {
        diagnostics.append("market.history.failed:\(mineral.typeID)")
      }
    }

    let state: DataFreshness =
      rows.isEmpty
      ? .unavailable
      : diagnostics.isEmpty ? .fresh : .partial
    let current = Sourced(
      state: state,
      value: rows.isEmpty ? nil : rows,
      source: source,
      diagnostics: Array(diagnostics.prefix(32))
    )
    mineralPriceTickerState = current.retainingLastKnownValue(from: previous)
  }

  func refreshDashboardWealth(
    inputs: [DashboardWealthCharacterInput]
  ) async {
    guard !isRefreshingDashboardWealth, !inputs.isEmpty else { return }
    isRefreshingDashboardWealth = true
    dashboardWealthError = nil
    defer { isRefreshingDashboardWealth = false }
    do {
      let prices = try await JitaMarketService(esi: esi)
        .adjustedPriceSnapshot()
      let typeIDs = Set(
        inputs.flatMap { input in
          let assetTypeIDs = input.assets.value?.items.map(\.typeID) ?? []
          let corporationTypeIDs =
            input.corporationAssets?.value?.items.map(\.typeID) ?? []
          let contractTypeIDs =
            input.privateContracts?.value?.itemContracts.flatMap {
              $0.items.map(\.typeID)
            } ?? []
          return assetTypeIDs + corporationTypeIDs + contractTypeIDs
        }
      )
      let typeNames =
        (try? await catalog.typeNames(ids: typeIDs)) ?? [:]
      dashboardWealthSnapshot = DashboardWealthProjector.project(
        inputs: inputs,
        prices: prices,
        typeNames: typeNames
      )
    } catch {
      dashboardWealthError =
        "The current ESI reference prices could not be loaded."
    }
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
    let locationIDs = productionBasis.productionWarehouseScope.locationIDs
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

  func loadNPCStations(
    in solarSystemID: Int64,
    force: Bool = false
  ) async throws -> Sourced<[TradingLocationSearchOption]> {
    try await tradingLocationSearch.stations(
      inSolarSystemID: solarSystemID,
      force: force
    )
  }

  func loadAccessibleStructures(
    in solarSystemID: Int64,
    systemName: String,
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async -> Sourced<[PlayerStructureOption]> {
    let source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    guard solarSystemID > 0 else {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: source,
        diagnostics: ["esi.system-structures.invalid-system"]
      )
    }
    guard !clientID.isEmpty else {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: source,
        diagnostics: ["esi.system-structures.client-id-missing"]
      )
    }
    let capableAuthorizations = authorizations.filter {
      $0.scopes.contains(PlayerStructureSearchService.searchScope)
        && $0.scopes.contains(PlayerStructureSearchService.detailScope)
    }
    guard !capableAuthorizations.isEmpty else {
      return Sourced(
        state: .forbidden,
        value: nil,
        source: source,
        diagnostics: ["esi.system-structures.scopes-missing"]
      )
    }

    var optionsByID: [Int64: PlayerStructureOption] = [:]
    var diagnostics: [String] = []
    var successfulCharacters = 0
    var latestSource = source
    for authorization in capableAuthorizations {
      do {
        let auth = authService(clientID: clientID)
        let lease = try await auth.accessTokenLease(
          characterID: authorization.characterID
        )
        let snapshot = try await playerStructureSearch.search(
          query: systemName,
          solarSystemID: solarSystemID,
          characterID: authorization.characterID,
          lease: lease
        )
        successfulCharacters += 1
        if snapshot.source.capturedAt > latestSource.capturedAt {
          latestSource = snapshot.source
        }
        for option in snapshot.value ?? [] {
          optionsByID[option.id] = option
        }
        diagnostics.append(contentsOf: snapshot.diagnostics)
      } catch ESIError.missingScope {
        diagnostics.append(
          "esi.system-structures.character-scope-missing:\(authorization.characterID)"
        )
      } catch ESIError.forbidden {
        diagnostics.append(
          "esi.system-structures.character-forbidden:\(authorization.characterID)"
        )
      } catch {
        diagnostics.append(
          "esi.system-structures.character-unavailable:\(authorization.characterID)"
        )
      }
    }
    let values = optionsByID.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    guard successfulCharacters > 0 else {
      return Sourced(
        state: .unavailable,
        value: nil,
        source: latestSource,
        diagnostics: Array(diagnostics.prefix(32))
      )
    }
    return Sourced(
      state: diagnostics.isEmpty ? .fresh : .partial,
      value: values,
      source: latestSource,
      diagnostics: Array(diagnostics.prefix(32))
    )
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

  func checkSDE() async {
    await perform("Checking current SDE metadata") {
      let service = try makeSDELifecycle()
      updatePreview = try await service.check()
      sdeLastCheckedAt = .now
    }
  }

  func installSDE(
    schemaReviewConfirmed: Bool
  ) async {
    guard let updatePreview else { return }
    await perform("Installing static data update") {
      let service = try makeSDELifecycle()
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

  func connectCharacter(
    clientID: String,
    expectedCharacterID: Int64? = nil
  ) async throws
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
      pending: pending,
      expectedCharacterID: expectedCharacterID
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

  private func makeSDELifecycle() throws
    -> SDELifecycleService
  {
    try SDELifecycleService(
      rootURL: dataRoot.appendingPathComponent("sde", isDirectory: true),
      ownerContact: ccpUserAgentOwnerContact
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
  let hubID: UUID
  let result: Sourced<MarketOrderSnapshot>
}

private enum MoonMaterialStructureAuthorization: Sendable {
  case available([Int64: AccessTokenLease])
  case missingScope
  case authorizationRequired
  case unavailable
}

private enum ManufacturingOpportunityDemandStoreError: Error {
  case unsupportedVersion
  case unreadable
}

private actor ManufacturingOpportunityDemandStore {
  private let fileURL: URL
  private var loadedLedger: ManufacturingOpportunityDemandLedger?

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func currentDemand() throws -> ManufacturingOpportunityDemandSnapshot? {
    let current = try ledger().demand
    loadedLedger = nil
    return current
  }

  func observe(
    _ market: MarketOrderSnapshot
  ) throws -> ManufacturingOpportunityDemandSnapshot {
    var updated = try ledger()
    let demand = updated.observe(market)
    let encoded: Data
    do {
      encoded = try JSONEncoder().encode(updated)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try encoded.write(to: fileURL, options: .atomic)
    } catch {
      throw ManufacturingOpportunityDemandStoreError.unreadable
    }
    loadedLedger = nil
    return demand
  }

  private func ledger() throws -> ManufacturingOpportunityDemandLedger {
    if let loadedLedger { return loadedLedger }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let empty = ManufacturingOpportunityDemandLedger()
      loadedLedger = empty
      return empty
    }
    do {
      let data = try Data(contentsOf: fileURL)
      let decoded = try JSONDecoder().decode(
        ManufacturingOpportunityDemandLedger.self,
        from: data
      )
      guard
        decoded.version == ManufacturingOpportunityDemandLedger.schemaVersion
      else {
        throw ManufacturingOpportunityDemandStoreError.unsupportedVersion
      }
      loadedLedger = decoded
      return decoded
    } catch let error as ManufacturingOpportunityDemandStoreError {
      throw error
    } catch {
      throw ManufacturingOpportunityDemandStoreError.unreadable
    }
  }
}
