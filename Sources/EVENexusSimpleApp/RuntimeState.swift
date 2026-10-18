import AppKit
import EVENexusCore
import Foundation

enum CharacterConnectionPhase: Equatable {
  case idle
  case waitingForBrowser
  case completingSSO
  case synchronizingESI
}

enum PublicContractStoreState: Equatable {
  case disabled
  case preparing
  case ready
  case failed
}

enum AutomaticBackgroundWork: Hashable, Sendable {
  case mainHubMarket
  case publicContracts
}

struct InteractivePlannerWorkCoordinator: Sendable {
  private var activePlannerCalculations: Set<Int> = []
  private var activeAutomaticWork: Set<AutomaticBackgroundWork> = []

  var hasActivePlannerCalculation: Bool {
    !activePlannerCalculations.isEmpty
  }

  func canSchedule(_ work: AutomaticBackgroundWork) -> Bool {
    activePlannerCalculations.isEmpty && !activeAutomaticWork.contains(work)
  }

  mutating func beginPlannerCalculation(
    id: Int
  ) -> Set<AutomaticBackgroundWork> {
    activePlannerCalculations.insert(id)
    return activeAutomaticWork
  }

  @discardableResult
  mutating func finishPlannerCalculation(id: Int) -> Bool {
    activePlannerCalculations.remove(id)
    return activePlannerCalculations.isEmpty
  }

  mutating func beginAutomaticWork(
    _ work: AutomaticBackgroundWork
  ) -> Bool {
    guard canSchedule(work) else { return false }
    activeAutomaticWork.insert(work)
    return true
  }

  @discardableResult
  mutating func finishAutomaticWork(
    _ work: AutomaticBackgroundWork
  ) -> Bool {
    activeAutomaticWork.remove(work)
    return activePlannerCalculations.isEmpty
  }
}

private struct PlannerJumpFreighterRouteLoad: Sendable {
  let route: Sourced<JumpRouteSnapshot>?
  let warnings: [DomainWarning]
  let capitalRoutes: [Int64: Sourced<CapitalJumpRouteSnapshot>]
  let capitalWarnings: [DomainWarning]

  static let notRequired = PlannerJumpFreighterRouteLoad(
    route: nil,
    warnings: [],
    capitalRoutes: [:],
    capitalWarnings: []
  )
}

private struct PlannerInputPreparationCacheKey: Equatable {
  let sdeBuild: Int
  let sdeContentSHA256: String
  let input: String
  let includesCompressedOreOptions: Bool
  let includesJumpFuelIsotopes: Bool
}

private struct PlannerInputPreparationCacheEntry {
  let key: PlannerInputPreparationCacheKey
  let catalog: MemoizedIndustryCatalog
  let preparation: IndustryPlannerInputPreparation
}

/// A narrow observation channel for one feature. Views subscribe to this
/// channel instead of the complete runtime coordinator and still read the
/// runtime as the single source of truth.
@MainActor
final class RuntimeFeatureState: ObservableObject {
  @Published private(set) var revision: UInt64 = 0

  func invalidate() {
    revision &+= 1
  }
}

/// A caller leaving a screen does not cancel an analysis shared by other screens.
@MainActor
final class SharedAnalysisRefresh {
  private var inFlight: (identity: String, token: UUID, task: Task<Void, Never>)?

  func run(identity: String, operation: @escaping @MainActor () async -> Void) async {
    while let pending = inFlight {
      await pending.task.value
      if inFlight?.token == pending.token { inFlight = nil }
      if pending.identity == identity { return }
    }
    let task = Task { await operation() }
    let token = UUID()
    inFlight = (identity, token, task)
    await task.value
    if inFlight?.token == token { inFlight = nil }
  }
}

@MainActor
final class RuntimeState: ObservableObject {
  let plannerFeatureState = RuntimeFeatureState()

  @Published var productionBasis = ProductionBasis() {
    didSet { plannerFeatureState.invalidate() }
  }
  @Published var manufacturingProfile = ManufacturingProfile()
  @Published var reactionProfile: ReactionProfile?
  @Published var plan: IndustryPlanSnapshot? {
    didSet { plannerFeatureState.invalidate() }
  }
  @Published private(set) var reactionAnalysis: ReactionAnalysisSnapshot?
  @Published private(set) var isAnalyzingReactions = false
  @Published private(set) var reactionAnalysisError: String?
  @Published private(set) var reactionAnalysisDestinationName: String?
  @Published private(set) var moonMaterialAnalysis: MoonMaterialPurchaseAnalysisSnapshot? {
    didSet {
      moonMaterialRecommendations = moonMaterialAnalysis.map(MaterialPurchaseRecommendationProjector.project) ?? []
    }
  }
  @Published private(set) var moonMaterialRecommendations: [MaterialPurchaseRecommendation] = []
  @Published private(set) var isRefreshingMoonMaterialAnalysis = false
  @Published private(set) var moonMaterialAnalysisError: String?
  @Published private(set) var mineralPurchaseAnalysis: MaterialPurchaseAnalysisSnapshot? {
    didSet {
      mineralPurchaseRecommendations = mineralPurchaseAnalysis.map(MaterialPurchaseRecommendationProjector.project) ?? []
    }
  }
  @Published private(set) var mineralPurchaseRecommendations: [MaterialPurchaseRecommendation] = []
  private let sharedMoonRefresh = SharedAnalysisRefresh()
  private let sharedMineralRefresh = SharedAnalysisRefresh()
  private let sharedReactionRefresh = SharedAnalysisRefresh()
  private var reactionRefreshIdentity: String?
  private var reactionResultContext: String?
  private var moonMaterialResultContext: String?
  private var mineralPurchaseResultContext: String?

  var hasCurrentMoonMaterialAnalysis: Bool {
    moonMaterialAnalysis != nil && moonMaterialResultContext == marketAnalysisContextIdentity
  }

  var hasCurrentMineralPurchaseAnalysis: Bool {
    mineralPurchaseAnalysis != nil && mineralPurchaseResultContext == marketAnalysisContextIdentity
  }
  @Published private(set) var isRefreshingMineralPurchaseAnalysis = false
  @Published private(set) var mineralPurchaseAnalysisError: String?
  @Published private(set) var marketBrowserState: Sourced<MarketBrowserSnapshot>?
  @Published private(set) var isRefreshingMarketBrowser = false
  @Published private(set) var marketBrowserError: String?
  @Published private(set) var mainHubMarketState: Sourced<MarketOrderSummarySnapshot>?
  @Published private(set) var mainHubMarketAutomaticUpdatesEnabled = true
  @Published private(set) var mainHubMarketNextAutomaticRunAt: Date?
  @Published private(set) var isAutomaticallyRefreshingMainHubMarket = false
  @Published private(set) var dashboardWealthSnapshot: DashboardWealthSnapshot?
  @Published private(set) var dashboardWealthError: String?
  @Published private(set) var dashboardIndustryJobValues: [DashboardIndustryJobValue] = []
  @Published private(set) var dashboardIndustryProductNames: [Int64: String] = [:]
  @Published private(set) var isRefreshingDashboardWealth = false
  private var hasReservedDashboardStartupRefresh = false
  @Published private(set) var manufacturingOpportunityAnalysis: ManufacturingOpportunitySnapshot?
  @Published private(set) var manufacturingOpportunityProgress =
    ManufacturingOpportunityScanProgress()
  @Published private(set) var isAnalyzingManufacturingOpportunities = false
  @Published private(set) var manufacturingOpportunityError: String?
  @Published private(set) var manufacturingOpportunitySnapshotError: String?
  @Published private(set) var manufacturingOpportunityDemand:
    ManufacturingOpportunityDemandSnapshot?
  @Published private(set) var manufacturingOpportunityDemandError: String?
  @Published private(set) var loyaltyStoreCatalog: LoyaltyStoreCatalogSnapshot?
  @Published private(set) var isRefreshingLoyaltyStoreCatalog = false
  @Published private(set) var loyaltyStoreCatalogError: String?
  @Published var isWorking = false {
    didSet { plannerFeatureState.invalidate() }
  }
  @Published var statusMessage = "Ready"
  @Published var errorMessage: String? {
    didSet { plannerFeatureState.invalidate() }
  }
  @Published var updatePreview: SDEUpdatePreview?
  @Published private(set) var sdeLastCheckedAt: Date?
  @Published var activeSDEBuild: Int?
  @Published var activeSDEContentSHA256: String?
  @Published var installationPhase: String?
  @Published var lastCharacterSync: CharacterSyncSnapshot?
  @Published var selectedAssetLocationID: Int64?
  @Published var warehouseStockEnabled = true {
    didSet { plannerFeatureState.invalidate() }
  }
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
  @Published private(set) var isPlannerConfigurationReady = false {
    didSet { plannerFeatureState.invalidate() }
  }
  @Published private(set) var eveOnlineServiceStatus: EVEOnlineServiceStatusSnapshot?
  @Published private(set) var eveOnlineStatusCheckFailed = false
  @Published private(set) var characterConnectionPhase: CharacterConnectionPhase = .idle
  @Published private(set) var publicContractProgress = PublicContractSyncProgress()
  @Published private(set) var publicContractResults: [PublicContractSearchResult] = []
  @Published private(set) var publicContractCategories: [PublicContractFacet] = []
  @Published private(set) var publicContractGroups: [PublicContractFacet] = []
  @Published private(set) var publicContractError: String?
  @Published private(set) var isSynchronizingPublicContracts = false
  @Published private(set) var isCancellingPublicContracts = false
  @Published private(set) var publicContractAutomaticUpdatesEnabled = false
  @Published private(set) var publicContractNextAutomaticRunAt: Date?
  @Published private(set) var publicContractStoreState: PublicContractStoreState =
    .disabled

  private let esi: ESIClient
  private let eveOnlineStatusClient = EVEOnlineStatusClient()
  private let solarSystemSearch: SolarSystemSearchService
  private let playerStructureSearch: PlayerStructureSearchService
  private let tradingLocationSearch: TradingLocationSearchService
  private let universeNameService: UniverseNameService
  private let universeTypeVolumeService: UniverseTypeVolumeService
  private let dotlanJumpRouteService: DOTLANJumpRouteService
  private let catalog: SQLiteStaticCatalog
  private var publicContractIndexer: PublicContractIndexer?
  private let assetWarehouseProjectionCache =
    StoredAssetWarehouseProjectionCache()
  private let manufacturingOpportunityDemandStore: ManufacturingOpportunityDemandStore
  private let manufacturingOpportunitySnapshotStore: ManufacturingOpportunitySnapshotStore
  private let loyaltyStoreCatalogStore: LoyaltyStoreCatalogStore
  private let loyaltyStoreCatalogService: LoyaltyStoreCatalogService
  private let dataRoot: URL
  private let ccpUserAgentOwnerContact: String?
  private var authServices: [String: EVESSOService] = [:]
  private var hasLoadedProfileReferenceData = false
  private var profileReferenceRefreshTask: Task<Void, Never>?
  private var lastEVEOnlineStatusCheckAt: Date?
  private var moonMaterialRefreshIdentity: String?
  private var mineralPurchaseRefreshIdentity: String?
  private var publicContractSyncTask: Task<Void, Never>?
  private var publicContractAutomationTask: Task<Void, Never>?
  private var hasPreparedPublicContractAutomation = false
  private var hasLoadedPublicContractBrowser = false
  private var hasRequestedPublicContractBrowser = false
  private var publicContractSearchGeneration = 0
  private var plannerCalculationGeneration = 0
  private var plannerInputPreparationCache: PlannerInputPreparationCacheEntry?
  private var operationGeneration = 0
  private var activeOperationCount = 0
  private var interactivePlannerWorkCoordinator =
    InteractivePlannerWorkCoordinator()
  private var mainHubMarketAutomationTask: Task<Void, Never>?
  private var mainHubMarketAutomaticScanTask: Task<Void, Never>?
  private var automaticMainHubScanNeedsResume = false
  private var preparedMainHubMarketIdentity: String?
  private var manufacturingOpportunityProgressThrottle =
    ProgressPublicationThrottle(minimumInterval: 2)
  private var publicContractProgressThrottle =
    ProgressPublicationThrottle(minimumInterval: 2)
  private var esiMemoryPressureSource: DispatchSourceMemoryPressure?

  private static let materialPurchaseMinimumRefreshInterval: TimeInterval =
    5 * 60
  private static let plannerESICacheRetainedBytes = 32 * 1_024 * 1_024
  private static let warningESICacheRetainedBytes = 16 * 1_024 * 1_024
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
    self.universeTypeVolumeService = UniverseTypeVolumeService(esi: esi)
    self.dotlanJumpRouteService = DOTLANJumpRouteService()
    self.loyaltyStoreCatalogService = LoyaltyStoreCatalogService(esi: esi)
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
    loyaltyStoreCatalogStore = LoyaltyStoreCatalogStore(
      fileURL:
        resolvedDataRoot
        .appendingPathComponent("market", isDirectory: true)
        .appendingPathComponent("loyalty-store-catalog.json")
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
    publicContractIndexer = nil
    publicContractStoreState = startBackgroundServices ? .preparing : .disabled
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
    startESIMemoryPressureMonitoring()
    Task(priority: .utility) {
      async let activeBuild: Void = refreshActiveBuild()
      async let serviceStatus: Void = refreshEVEOnlineServiceStatus()
      async let demand: Void = loadManufacturingOpportunityDemand()
      async let opportunities: Void = loadManufacturingOpportunityAnalysis()
      async let loyaltyStores: Void = loadLoyaltyStoreCatalog()
      async let contracts: Void = preparePublicContractStore(
        at: contractStoreURL
      )
      _ = await (
        activeBuild,
        serviceStatus,
        demand,
        opportunities,
        contracts,
        loyaltyStores
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
      await manufacturingOpportunitySnapshotStore.releaseCachedSnapshot()
      guard manufacturingOpportunityAnalysis == nil else { return }
      manufacturingOpportunityAnalysis = stored
      manufacturingOpportunitySnapshotError = nil
    } catch {
      manufacturingOpportunitySnapshotError =
        "The last saved Main Hub item list could not be read. Existing data was not replaced."
    }
  }

  func loadLoyaltyStoreCatalog() async {
    do {
      loyaltyStoreCatalog = try await loyaltyStoreCatalogStore.load()
      loyaltyStoreCatalogError = nil
    } catch {
      loyaltyStoreCatalogError =
        "The saved Loyalty Store catalog could not be read. It was not treated as an empty catalog."
    }
  }

  func refreshLoyaltyStoreCatalog() async {
    guard !isRefreshingLoyaltyStoreCatalog else { return }
    isRefreshingLoyaltyStoreCatalog = true
    loyaltyStoreCatalogError = nil
    defer { isRefreshingLoyaltyStoreCatalog = false }
    do {
      let snapshot = try await loyaltyStoreCatalogService.refresh()
      try await loyaltyStoreCatalogStore.save(snapshot)
      loyaltyStoreCatalog = snapshot
    } catch is CancellationError {
      return
    } catch {
      loyaltyStoreCatalogError =
        "The Loyalty Store catalog could not be refreshed. The previous snapshot was preserved."
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
      mainHubMarketAutomaticScanTask?.cancel()
      automaticMainHubScanNeedsResume = false
      mainHubMarketNextAutomaticRunAt = nil
      preparedMainHubMarketIdentity = nil
      return
    }
    let identity = "\(regionID):\(locationID)"
    if preparedMainHubMarketIdentity != identity {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketAutomaticScanTask?.cancel()
      automaticMainHubScanNeedsResume = false
      mainHubMarketNextAutomaticRunAt = nil
      mainHubMarketState = nil
      resetManufacturingOpportunityProgress()
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
      mainHubMarketAutomaticScanTask?.cancel()
      automaticMainHubScanNeedsResume = false
      mainHubMarketNextAutomaticRunAt = nil
      isAutomaticallyRefreshingMainHubMarket = false
    }
  }

  private func scheduleAutomaticMainHubMarketRefresh(
    retryAfter: TimeInterval? = nil
  ) {
    guard mainHubMarketAutomaticUpdatesEnabled,
      preparedMainHubMarketIdentity != nil,
      mainHubMarketAutomationTask == nil,
      mainHubMarketAutomaticScanTask == nil,
      interactivePlannerWorkCoordinator.canSchedule(.mainHubMarket)
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
    mainHubMarketAutomationTask = Task(priority: .utility) { [weak self] in
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
      self.mainHubMarketAutomationTask = nil
      if !self.shouldAutomaticallyRefreshManufacturingOpportunities() {
        self.mainHubMarketNextAutomaticRunAt = nil
        self.scheduleAutomaticMainHubMarketRefresh()
        return
      }
      if self.isAnalyzingManufacturingOpportunities {
        self.mainHubMarketNextAutomaticRunAt = nil
        self.scheduleAutomaticMainHubMarketRefresh(retryAfter: 60)
        return
      }
      guard
        self.interactivePlannerWorkCoordinator.beginAutomaticWork(
          .mainHubMarket
        )
      else {
        self.mainHubMarketNextAutomaticRunAt = nil
        return
      }
      self.mainHubMarketNextAutomaticRunAt = nil
      self.isAutomaticallyRefreshingMainHubMarket = true
      self.mainHubMarketAutomaticScanTask = Task(priority: .utility) {
        [weak self] in
        guard let self else { return }
        await self.analyzeManufacturingOpportunities(
          settings:
            self.manufacturingOpportunityAnalysis?.settings
            ?? ManufacturingOpportunitySettings(),
          isAutomatic: true
        )
        self.finishAutomaticMainHubMarketScan()
      }
    }
  }

  private func finishAutomaticMainHubMarketScan() {
    interactivePlannerWorkCoordinator.finishAutomaticWork(.mainHubMarket)
    mainHubMarketAutomaticScanTask = nil
    isAutomaticallyRefreshingMainHubMarket = false
    guard mainHubMarketAutomaticUpdatesEnabled else { return }
    if interactivePlannerWorkCoordinator.hasActivePlannerCalculation {
      return
    }
    let retryAfter: TimeInterval? =
      automaticMainHubScanNeedsResume
      ? ManufacturingOpportunityAutomaticRefreshPolicy.startupDelay
      : manufacturingOpportunityError == nil ? nil : 30 * 60
    automaticMainHubScanNeedsResume = false
    scheduleAutomaticMainHubMarketRefresh(retryAfter: retryAfter)
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
    hasRequestedPublicContractBrowser = true
    guard publicContractStoreState == .ready,
      let publicContractIndexer
    else { return }
    do {
      if !isSynchronizingPublicContracts {
        publishPublicContractProgress(
          try await publicContractIndexer.localProgress(),
          force: true
        )
      }
      if !hasLoadedPublicContractBrowser {
        let facets = try await publicContractIndexer.facets()
        publicContractCategories = facets.categories
        publicContractGroups = facets.groups
        hasLoadedPublicContractBrowser = true
      }
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
    publicContractSearchGeneration &+= 1
    let generation = publicContractSearchGeneration
    do {
      let results = try await publicContractIndexer.search(filter)
      guard !Task.isCancelled,
        generation == publicContractSearchGeneration
      else { return }
      publicContractResults = results
      publicContractError = nil
    } catch is CancellationError {
      return
    } catch {
      guard generation == publicContractSearchGeneration else { return }
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
      hasLoadedPublicContractBrowser = true
    } catch {
      publicContractError =
        "The Public Contracts filters could not be refreshed."
    }
  }

  func startPublicContractSynchronization() {
    guard publicContractStoreState == .ready else { return }
    beginPublicContractSynchronization(manualStart: true)
  }

  func retryPublicContractStorePreparation() {
    guard publicContractStoreState == .failed else { return }
    publicContractStoreState = .preparing
    publicContractError = nil
    Task(priority: .utility) {
      await preparePublicContractStore(at: publicContractStoreURL)
    }
  }

  func cancelPublicContractSynchronization() {
    publicContractAutomaticUpdatesEnabled = false
    publicContractNextAutomaticRunAt = nil
    publicContractAutomationTask?.cancel()
    publicContractAutomationTask = nil
    isCancellingPublicContracts = publicContractSyncTask != nil
    publicContractSyncTask?.cancel()
    guard let publicContractIndexer else { return }
    Task(priority: .utility) {
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
      publishPublicContractProgress(
        try await publicContractIndexer.localProgress(),
        force: true
      )
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

  private var publicContractStoreURL: URL {
    dataRoot
      .appendingPathComponent("contracts", isDirectory: true)
      .appendingPathComponent("public-contracts.sqlite")
  }

  private func preparePublicContractStore(at storeURL: URL) async {
    guard publicContractStoreState == .preparing,
      publicContractIndexer == nil
    else { return }
    do {
      let store = try await PublicContractStore.open(url: storeURL)
      guard !Task.isCancelled else {
        await store.close()
        return
      }
      publicContractIndexer = PublicContractIndexer(
        remote: ESIPublicContractRemote(
          esi: esi,
          universeNames: universeNameService
        ),
        catalog: catalog,
        store: store
      )
      publicContractStoreState = .ready
      publicContractError = nil
      await preparePublicContractAutomation()
      if hasRequestedPublicContractBrowser {
        await loadPublicContractBrowser()
      }
    } catch is CancellationError {
      return
    } catch {
      publicContractStoreState = .failed
      publicContractProgress = PublicContractSyncProgress(
        phase: .failed,
        message: "esi.public-contracts.store-unavailable"
      )
      publicContractError =
        "The local Public Contracts index could not be opened or prepared. Existing data was not replaced."
    }
  }

  private func beginPublicContractSynchronization(manualStart: Bool) {
    guard publicContractSyncTask == nil,
      let publicContractIndexer
    else { return }
    if !manualStart,
      !interactivePlannerWorkCoordinator.beginAutomaticWork(.publicContracts)
    {
      return
    }
    publicContractAutomationTask?.cancel()
    publicContractAutomationTask = nil
    publicContractNextAutomaticRunAt = nil
    if manualStart {
      publicContractAutomaticUpdatesEnabled = true
    }
    isCancellingPublicContracts = false
    isSynchronizingPublicContracts = true
    publicContractError = nil
    publicContractSyncTask = Task(priority: .background) { [weak self] in
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
          await self.finishPublicContractSynchronization(
            manualStart: manualStart,
            suppliedState: automation
          )
          return
        }
        let result = try await ESIRequestContext.withPriority(.automatic) {
          try await publicContractIndexer.synchronizeAll { progress in
            self.publishPublicContractProgress(progress)
          }
        }
        self.publishPublicContractProgress(result, force: true)
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
      await self.finishPublicContractSynchronization(
        manualStart: manualStart
      )
    }
  }

  private func finishPublicContractSynchronization(
    manualStart: Bool,
    suppliedState: PublicContractAutomationState? = nil
  ) async {
    isCancellingPublicContracts = false
    isSynchronizingPublicContracts = false
    publicContractSyncTask = nil
    if !manualStart {
      interactivePlannerWorkCoordinator.finishAutomaticWork(.publicContracts)
    }
    guard publicContractAutomaticUpdatesEnabled,
      !interactivePlannerWorkCoordinator.hasActivePlannerCalculation,
      let publicContractIndexer
    else { return }
    let nextState: PublicContractAutomationState?
    if let suppliedState {
      nextState = suppliedState
    } else {
      nextState = try? await publicContractIndexer.automationState(
        regularRefreshInterval:
          PublicContractAutomationPolicy.regularRefreshInterval
      )
    }
    await scheduleAutomaticPublicContractSynchronization(
      state: nextState
    )
  }

  private func scheduleAutomaticPublicContractSynchronization(
    state suppliedState: PublicContractAutomationState? = nil
  ) async {
    guard publicContractSyncTask == nil,
      publicContractAutomationTask == nil,
      publicContractAutomaticUpdatesEnabled,
      interactivePlannerWorkCoordinator.canSchedule(.publicContracts),
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
    publicContractAutomationTask = Task(priority: .utility) { [weak self] in
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

  private func startESIMemoryPressureMonitoring() {
    guard esiMemoryPressureSource == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor [weak self] in
        guard let self,
          let event = self.esiMemoryPressureSource?.data
        else { return }
        if event.contains(.critical) {
          await self.esi.removeAllCachedResponses()
        } else if event.contains(.warning) {
          await self.esi.trimCachedResponses(
            toMaximumBytes: Self.warningESICacheRetainedBytes
          )
        }
        await self.manufacturingOpportunitySnapshotStore
          .releaseCachedSnapshot()
      }
    }
    esiMemoryPressureSource = source
    source.activate()
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
    availableStockOverride: [Int64: Int64]? = nil,
    existingReservations: [StockAllocation] = [],
    assetWarehouse: AssetWarehouse? = nil,
    stockTargets: [Int64: Int64] = [:],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    defaultPurchaseLocation: ProcurementLocation? = nil,
    blueprintCostAllocations: [Int64: IndustryBlueprintCostAllocation] = [:],
    requiresCompleteBlueprintCosts: Bool = false,
    productionEfficiencies: [Int64: IndustryProductionEfficiency] = [:],
    blueprintSupplyPlans: [Int64: BlueprintSupplyPlan] = [:],
    blueprintSourceSnapshotIDs: [UUID] = [],
    authorizations: [AuthorizationSnapshot] = [],
    capabilities: [CharacterCapabilitySnapshot] = [],
    clientID: String = ""
  ) async {
    plannerCalculationGeneration &+= 1
    let calculationGeneration = plannerCalculationGeneration
    beginInteractivePlannerCalculation(id: calculationGeneration)
    defer {
      finishInteractivePlannerCalculation(id: calculationGeneration)
    }
    await ESIRequestContext.withPriority(.interactive) {
      await perform("Calculating production plan") {
        try Task.checkCancellation()
        guard let active = try await catalog.activeSDEVersion() else {
          throw StaticCatalogError.noActiveCatalog
        }
        let planner = IndustryPlanner()
        let preparedInput = try await plannerInputPreparation(
          input: input,
          sdeBuild: active.buildNumber,
          sdeContentSHA256: active.contentSHA256,
          includeCompressedOreOptions:
            productionBasis.compressedOreRefining.isEnabled,
          includeJumpFuelIsotopes:
            productionBasis.logistics.jumpFreighter.isEnabled
            && productionBasis.coalitionTradingLocation != nil,
          calculationGeneration: calculationGeneration
        )
        let planningCatalog = preparedInput.catalog
        let preparation = preparedInput.preparation
        let typeIDs = preparation.marketTypeIDs
        let requestedProductTypeIDs = preparation.requestedProductTypeIDs
        let requestedSelfJumpCapitals = preparation.requestedSelfJumpCapitals
        try Task.checkCancellation()
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
        let configuredCoalitionHub = productionBasis.coalitionTradingLocation
        async let jumpFreighterRouteLoad = plannerJumpFreighterRouteLoad(
          configuration: productionBasis.logistics.jumpFreighter,
          homeHub: configuredHomeHub?.location,
          coalitionHub: configuredCoalitionHub?.location,
          capabilities: capabilities,
          capitalProducts: requestedSelfJumpCapitals
        )
        let marketService = JitaMarketService(esi: esi)
        async let homeMarketLoad = plannerSecondaryMarketLoad(
          typeIDs: typeIDs,
          mainHub: configuredMainHub,
          targetHub: configuredHomeHub,
          authorizations: authorizations,
          clientID: clientID
        )
        async let coalitionMarketLoad = plannerSecondaryMarketLoad(
          typeIDs: typeIDs,
          mainHub: configuredMainHub,
          targetHub: configuredCoalitionHub,
          authorizations: authorizations,
          clientID: clientID
        )
        async let contractReferenceLoad = plannerContractReferenceLoad(
          typeIDs: requestedProductTypeIDs,
          targetHub: configuredMainHub
        )
        async let packagedVolumeLoad = universeTypeVolumeService.volumes(
          for: typeIDs
        )
        async let market = marketService.orderSnapshot(
          typeIDs: typeIDs,
          regionID: mainRegionID,
          locationID: mainLocationID
        )
        async let adjusted = marketService.adjustedPrices()
        async let systems = marketService.industrySystems()
        let values = try await (
          market,
          adjusted,
          systems,
          homeMarketLoad,
          coalitionMarketLoad,
          contractReferenceLoad,
          packagedVolumeLoad
        )
        let loadedJumpFreighterRoute = await jumpFreighterRouteLoad
        try Task.checkCancellation()
        var homeMarket: MarketOrderSnapshot?
        var homeMarketWarnings: [DomainWarning] = []
        switch values.3 {
        case .reuseMain:
          homeMarket = values.0
        case .loaded(let snapshot):
          homeMarket = snapshot
        case .unavailable:
          homeMarketWarnings.append(
            DomainWarning(
              code: "planner.home-market-unavailable",
              message:
                "The Home Hub market could not be loaded. Home Hub sale scenarios remain unavailable; the Main Hub plan was preserved.",
              severity: .warning
            )
          )
        case .notConfigured:
          homeMarketWarnings.append(
            DomainWarning(
              code: "planner.home-hub-not-configured",
              message:
                "No Home Hub is configured. Home Hub sale scenarios remain unavailable.",
              severity: .warning
            )
          )
        case .cancelled:
          throw CancellationError()
        }
        var coalitionMarket: MarketOrderSnapshot?
        var coalitionMarketWarnings: [DomainWarning] = []
        switch values.4 {
        case .reuseMain:
          coalitionMarket = values.0
        case .loaded(let snapshot):
          coalitionMarket = snapshot
        case .unavailable:
          coalitionMarketWarnings.append(
            DomainWarning(
              code: "planner.coalition-market-unavailable",
              message:
                "The Coalition Hub market could not be loaded. Coalition Hub sale strategies remain unavailable; the Main and Home Hub plan was preserved.",
              severity: .warning
            )
          )
        case .notConfigured:
          coalitionMarketWarnings.append(
            DomainWarning(
              code: "planner.coalition-hub-not-configured",
              message:
                "No Coalition Hub is configured. Coalition Hub sale strategies remain unavailable.",
              severity: .warning
            )
          )
        case .cancelled:
          throw CancellationError()
        }
        var universeContractReferences: PublicContractReferenceSnapshot?
        var contractReferenceWarnings: [DomainWarning] = []
        switch values.5 {
        case .loaded(let snapshot):
          universeContractReferences = snapshot
          if !snapshot.hasCompleteSearchCoverage {
            contractReferenceWarnings.append(
              DomainWarning(
                code: "planner.contract-reference-partial",
                message:
                  "The universe-wide Public Contracts index is incomplete. Contract Sale uses already observed comparable offers as provisional estimates; product types without an observed offer remain unavailable.",
                severity: .warning
              )
            )
          }
        case .notConfigured:
          break
        case .unavailable:
          contractReferenceWarnings.append(
            DomainWarning(
              code: "planner.contract-reference-unavailable",
              message:
                "A complete universe-wide Public Contracts reference could not be loaded. Market sale strategies remain independent.",
              severity: .warning
            )
          )
        case .cancelled:
          throw CancellationError()
        }
        var availableStock: [Int64: Int64]
        var assetSource: StockSource?
        let packagedVolumeSnapshot = values.6
        var snapshotIDs: [UUID] = [
          packagedVolumeSnapshot.source.snapshotID
        ]
        snapshotIDs.append(contentsOf: blueprintSourceSnapshotIDs)
        snapshotIDs.append(
          contentsOf: blueprintSupplyPlans.values.flatMap(\.sourceSnapshotIDs)
        )
        snapshotIDs = Array(Set(snapshotIDs)).sorted {
          $0.uuidString < $1.uuidString
        }
        var inputWarnings = packagedVolumeWarnings(packagedVolumeSnapshot)
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
        if let assetSource, availableStockOverride == nil {
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
        if let availableStockOverride, manualStock.isEmpty {
          availableStock = availableStockOverride
          if assetSource == nil && !availableStockOverride.isEmpty {
            assetSource = StockSource(kind: .manual, reference: "explicit-project-warehouses")
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
        let calculationCatalog = MemoizedIndustryCatalog(
          base: PackagedVolumeSnapshotCatalog(
            base: planningCatalog,
            packagedVolumes: packagedVolumeSnapshot.value ?? [:]
          )
        )
        let context = IndustryPlanningContext(
          manufacturingProfile: manufacturingProfile,
          reactionProfile: configuredReaction,
          productionBasis: productionBasis,
          catalog: calculationCatalog,
          market: values.0,
          homeMarket: homeMarket,
          coalitionMarket: coalitionMarket,
          mainContractReferences: universeContractReferences,
          homeContractReferences:
            configuredHomeHub == nil ? nil : universeContractReferences,
          coalitionContractReferences:
            configuredCoalitionHub == nil ? nil : universeContractReferences,
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
          coalitionMarketWarnings: coalitionMarketWarnings,
          contractReferenceWarnings: contractReferenceWarnings,
          salesTaxRate: configuredMainHub.marketTaxes.effectiveSalesTaxRate,
          brokerFeeRate: configuredMainHub.marketTaxes.effectiveBrokerFeeRate,
          homeSalesTaxRate:
            configuredHomeHub?.marketTaxes.effectiveSalesTaxRate,
          homeBrokerFeeRate:
            configuredHomeHub?.marketTaxes.effectiveBrokerFeeRate,
          coalitionSalesTaxRate:
            configuredCoalitionHub?.marketTaxes.effectiveSalesTaxRate,
          coalitionBrokerFeeRate:
            configuredCoalitionHub?.marketTaxes.effectiveBrokerFeeRate,
          blueprintCostAllocations: blueprintCostAllocations,
          requiresCompleteBlueprintCosts: requiresCompleteBlueprintCosts,
          productionEfficiencies: productionEfficiencies,
          blueprintSupplyPlans: blueprintSupplyPlans,
          planID: blueprintSupplyPlans.values.compactMap(\.planID).first,
          characterCapabilities: capabilities,
          jumpFreighterRoute: loadedJumpFreighterRoute.route,
          jumpFreighterRouteWarnings: loadedJumpFreighterRoute.warnings,
          capitalJumpRoutes: loadedJumpFreighterRoute.capitalRoutes,
          capitalJumpRouteWarnings: loadedJumpFreighterRoute.capitalWarnings
        )
        let calculatedPlan = try await planner.plan(
          preparation: preparation,
          context: context
        )
        try Task.checkCancellation()
        guard calculationGeneration == plannerCalculationGeneration else {
          return
        }
        plan = calculatedPlan
      }
    }
    await esi.trimCachedResponses(
      toMaximumBytes: Self.plannerESICacheRetainedBytes
    )
  }

  private func plannerInputPreparation(
    input: String,
    sdeBuild: Int,
    sdeContentSHA256: String,
    includeCompressedOreOptions: Bool,
    includeJumpFuelIsotopes: Bool,
    calculationGeneration: Int
  ) async throws -> PlannerInputPreparationCacheEntry {
    let key = PlannerInputPreparationCacheKey(
      sdeBuild: sdeBuild,
      sdeContentSHA256: sdeContentSHA256,
      input: input,
      includesCompressedOreOptions: includeCompressedOreOptions,
      includesJumpFuelIsotopes: includeJumpFuelIsotopes
    )
    if let cached = plannerInputPreparationCache, cached.key == key {
      return cached
    }

    let memoizedCatalog = MemoizedIndustryCatalog(base: catalog)
    let preparation = try await IndustryPlanner().prepare(
      input: input,
      catalog: memoizedCatalog,
      includeCompressedOreOptions: includeCompressedOreOptions,
      includeJumpFuelIsotopes: includeJumpFuelIsotopes
    )
    let entry = PlannerInputPreparationCacheEntry(
      key: key,
      catalog: memoizedCatalog,
      preparation: preparation
    )
    if calculationGeneration == plannerCalculationGeneration {
      plannerInputPreparationCache = entry
    }
    return entry
  }

  private func plannerJumpFreighterRouteLoad(
    configuration: JumpFreighterLogisticsConfiguration,
    homeHub: ProcurementLocation?,
    coalitionHub: ProcurementLocation?,
    capabilities: [CharacterCapabilitySnapshot],
    capitalProducts: [CapitalSelfJumpProduct]
  ) async -> PlannerJumpFreighterRouteLoad {
    guard configuration.isEnabled else { return .notRequired }
    guard let homeHub, let coalitionHub else {
      return jumpFreighterRouteUnavailable(
        code: "jump-freighter.hubs-not-configured",
        message:
          "Home Hub and Coalition Hub must both be configured before a Jump Freighter route can be calculated."
      )
    }
    guard !homeHub.representsSameLocation(as: coalitionHub) else {
      return .notRequired
    }
    guard let originSystemID = homeHub.solarSystemID,
      let destinationSystemID = coalitionHub.solarSystemID
    else {
      return jumpFreighterRouteUnavailable(
        code: "jump-freighter.system-unresolved",
        message:
          "The solar system of the Home Hub or Coalition Hub is unresolved. DOTLAN routing was not attempted."
      )
    }
    do {
      async let origin = solarSystemSearch.details(systemID: originSystemID)
      async let destination = solarSystemSearch.details(
        systemID: destinationSystemID
      )
      let systems = try await (origin, destination)
      var jumpFreighterRoute: Sourced<JumpRouteSnapshot>?
      var jumpFreighterWarnings: [DomainWarning] = []
      if let pilot = JumpFreighterPilotSelector.select(
        configuration: configuration,
        capabilities: capabilities
      ) {
        do {
          let request = JumpRouteRequest(
            originSystemName: systems.0.name,
            destinationSystemName: systems.1.name,
            hull: configuration.hull,
            pilot: pilot
          )
          let route: JumpRouteSnapshot
          if let profileID = configuration.assignedProfileID(
            for: .jumpFreighter
          ) {
            guard
              let profile = configuration.routeProfiles.first(where: {
                $0.id == profileID
              })
            else { throw DOTLANJumpRouteError.invalidFixedRoute }
            route = try await dotlanJumpRouteService.route(
              for: request,
              via: profile
            )
          } else {
            route = try await dotlanJumpRouteService.route(for: request)
          }
          jumpFreighterRoute = Sourced(
            state: .fresh,
            value: route,
            source: route.source,
            diagnostics: []
          )
        } catch {
          let unavailable = jumpFreighterRouteUnavailable(
            code: "jump-freighter.dotlan-unavailable",
            message:
              configuration.assignedProfileID(for: .jumpFreighter) == nil
              ? "DOTLAN did not return a verifiable Jump Freighter route. Coalition Hub transport remains unavailable rather than being treated as 0 ISK."
              : "The selected fixed Jump Freighter route could not be verified as direct consecutive jumps for this hull and pilot. It remains unavailable and does not fall back to an automatic route."
          )
          jumpFreighterRoute = unavailable.route
          jumpFreighterWarnings = unavailable.warnings
        }
      } else {
        let unavailable = jumpFreighterRouteUnavailable(
          code: "jump-freighter.pilot-unavailable",
          message:
            configuration.pilotCharacterID == nil
            ? "No eligible character with a fresh synchronized Jump Freighter skill snapshot is available."
            : "The selected Jump Freighter pilot is missing, stale or not eligible."
        )
        jumpFreighterRoute = unavailable.route
        jumpFreighterWarnings = unavailable.warnings
      }

      var capitalRoutes: [Int64: Sourced<CapitalJumpRouteSnapshot>] = [:]
      var capitalWarnings: [DomainWarning] = []
      if !capitalProducts.isEmpty {
        if let capitalPilot = CapitalJumpPilotSelector.select(
          configuration: configuration,
          capabilities: capabilities
        ) {
          for product in capitalProducts {
            do {
              guard let routeClass = product.routeClass else {
                throw DOTLANJumpRouteError.invalidFixedRoute
              }
              let request = CapitalJumpRouteRequest(
                originSystemName: systems.0.name,
                destinationSystemName: systems.1.name,
                capitalTypeID: product.typeID,
                capitalName: product.name,
                pilot: capitalPilot
              )
              let route: CapitalJumpRouteSnapshot
              if let profileID = configuration.assignedProfileID(
                for: routeClass
              ) {
                guard
                  let profile = configuration.routeProfiles.first(where: {
                    $0.id == profileID
                  })
                else { throw DOTLANJumpRouteError.invalidFixedRoute }
                route = try await dotlanJumpRouteService.route(
                  for: request,
                  via: profile
                )
              } else {
                route = try await dotlanJumpRouteService.route(for: request)
              }
              capitalRoutes[product.typeID] = Sourced(
                state: .fresh,
                value: route,
                source: route.source,
                diagnostics: []
              )
            } catch {
              let source = SourceIdentity(
                provider: "DOTLAN EveMaps",
                version: CapitalJumpRouteSnapshot.providerVersion
              )
              capitalRoutes[product.typeID] = Sourced(
                state: .unavailable,
                value: nil,
                source: source,
                diagnostics: ["capital-self-jump.dotlan-unavailable"]
              )
              capitalWarnings.append(
                DomainWarning(
                  code:
                    "capital-self-jump.dotlan-unavailable.\(product.typeID)",
                  message:
                    product.routeClass.flatMap {
                      configuration.assignedProfileID(for: $0)
                    } == nil
                    ? "DOTLAN did not return a verifiable self-jump route for one produced capital. The hull remains excluded from Jump Freighter cargo and its Coalition Hub transport cost remains unavailable."
                    : "The selected fixed route for one produced capital could not be verified as direct consecutive jumps for this hull and pilot. The hull remains excluded from cargo, the cost remains unavailable and no automatic route is substituted.",
                  severity: .blocking,
                  source: source
                )
              )
            }
          }
        } else {
          capitalWarnings.append(
            DomainWarning(
              code: "capital-self-jump.pilot-unavailable",
              message:
                configuration.pilotCharacterID == nil
                ? "No character with fresh synchronized jump-range skills is available for the produced capital self-jumps."
                : "The selected jump pilot is missing, stale or has no synchronized jump-range skill.",
              severity: .blocking
            )
          )
        }
      }
      return PlannerJumpFreighterRouteLoad(
        route: jumpFreighterRoute,
        warnings: jumpFreighterWarnings,
        capitalRoutes: capitalRoutes,
        capitalWarnings: capitalWarnings
      )
    } catch {
      return jumpFreighterRouteUnavailable(
        code: "jump-freighter.dotlan-unavailable",
        message:
          "DOTLAN did not return a verifiable Jump Freighter route. Coalition Hub transport remains unavailable rather than being treated as 0 ISK."
      )
    }
  }

  private func jumpFreighterRouteUnavailable(
    code: String,
    message: String
  ) -> PlannerJumpFreighterRouteLoad {
    let source = SourceIdentity(
      provider: "DOTLAN EveMaps",
      version: JumpRouteSnapshot.providerVersion
    )
    return PlannerJumpFreighterRouteLoad(
      route: Sourced(
        state: .unavailable,
        value: nil,
        source: source,
        diagnostics: [code]
      ),
      warnings: [
        DomainWarning(
          code: code,
          message: message,
          severity: .blocking,
          source: source
        )
      ],
      capitalRoutes: [:],
      capitalWarnings: []
    )
  }

  private func beginInteractivePlannerCalculation(id: Int) {
    let automaticWork =
      interactivePlannerWorkCoordinator.beginPlannerCalculation(id: id)

    mainHubMarketAutomationTask?.cancel()
    mainHubMarketAutomationTask = nil
    mainHubMarketNextAutomaticRunAt = nil
    if automaticWork.contains(.mainHubMarket) {
      automaticMainHubScanNeedsResume = true
      mainHubMarketAutomaticScanTask?.cancel()
    }

    publicContractAutomationTask?.cancel()
    publicContractAutomationTask = nil
    publicContractNextAutomaticRunAt = nil
    if automaticWork.contains(.publicContracts) {
      publicContractSyncTask?.cancel()
    }
  }

  /// Covers Planner preparation that happens before `calculate` enters its
  /// own nested operation. Keeping this session active prevents automatic
  /// market and contract refreshes from competing with BPO/BPC resolution.
  func beginInteractivePlannerPreparation() -> Int {
    plannerCalculationGeneration &+= 1
    let id = plannerCalculationGeneration
    beginInteractivePlannerCalculation(id: id)
    return id
  }

  func finishInteractivePlannerPreparation(id: Int) {
    finishInteractivePlannerCalculation(id: id)
  }

  private func finishInteractivePlannerCalculation(id: Int) {
    guard
      interactivePlannerWorkCoordinator.finishPlannerCalculation(id: id)
    else { return }

    if automaticMainHubScanNeedsResume,
      interactivePlannerWorkCoordinator.canSchedule(.mainHubMarket)
    {
      automaticMainHubScanNeedsResume = false
      scheduleAutomaticMainHubMarketRefresh(
        retryAfter: ManufacturingOpportunityAutomaticRefreshPolicy.startupDelay
      )
    } else {
      scheduleAutomaticMainHubMarketRefresh()
    }

    guard publicContractAutomaticUpdatesEnabled else { return }
    Task(priority: .utility) { [weak self] in
      await self?.scheduleAutomaticPublicContractSynchronization()
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
      let authorization = await marketStructureAuthorization(
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

  private func plannerSecondaryMarketLoad(
    typeIDs: Set<Int64>,
    mainHub: TradingLocationConfiguration,
    targetHub: TradingLocationConfiguration?,
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async -> PlannerSecondaryMarketLoad {
    guard let targetHub else { return .notConfigured }
    if mainHub.location.representsSameLocation(as: targetHub.location) {
      return .reuseMain
    }
    do {
      return .loaded(
        try await plannerMarketSnapshot(
          typeIDs: typeIDs,
          location: targetHub.location,
          preferredTraderCharacterID: targetHub.marketTaxes.traderCharacterID,
          authorizations: authorizations,
          clientID: clientID
        )
      )
    } catch is CancellationError {
      return .cancelled
    } catch ESIError.cancelled {
      return .cancelled
    } catch {
      return .unavailable
    }
  }

  private func plannerContractReferenceLoad(
    typeIDs: Set<Int64>,
    targetHub: TradingLocationConfiguration?
  ) async -> PlannerContractReferenceLoad {
    guard let targetHub else { return .notConfigured }
    guard publicContractStoreState == .ready,
      let publicContractIndexer
    else { return .unavailable }
    _ = targetHub
    do {
      let limitPerType = 500
      let snapshot = try await publicContractIndexer.includedOfferSnapshot(
        typeIDs: typeIDs,
        limitPerType: limitPerType
      )
      return .loaded(
        PublicContractReferenceSnapshot.projectUniverseWide(
          offers: snapshot.offers,
          progress: snapshot.progress,
          limitPerType: limitPerType,
          allowedRegionIDs: nil
        )
      )
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .unavailable
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
    existingBlueprintReservations: [BlueprintRunReservation] = [],
    procurementPreferences: [Int64: MaterialProcurementPreference] = [:],
    blueprintInventories: [OwnedBlueprintInventory] = [],
    blueprintActions: [Int64: ProductionTreeBlueprintAction] = [:],
    blueprintManualCosts: [Int64: Double] = [:],
    productionEfficiencies: [Int64: IndustryProductionEfficiency] = [:],
    preferredBlueprintSources: [Int64: [BlueprintSourceReference]] = [:],
    loyaltyStoreBlueprintTypeIDs: Set<Int64> = [],
    plannerInputOverride: String? = nil,
    requiresCompleteBlueprintCostsInSelectedPlan: Bool = true,
    availableStockOverride: [Int64: Int64]? = nil
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

    let input: String
    if let plannerInputOverride {
      let parsed = ProductionInputParser.parse(plannerInputOverride)
      guard parsed.isValid else {
        throw ManufacturingOpportunityError.invalidSettings
      }
      input = ProductionInputFormatter.format(parsed.requests)
    } else {
      guard let wantedQuantity = Int(exactly: targetQuantity) else {
        throw ManufacturingOpportunityError.invalidSettings
      }
      let request = ProductionRequestLine(
        lineNumber: 1,
        productName: productName,
        wantedQuantity: wantedQuantity,
        materialEfficiency: materialEfficiency,
        timeEfficiency: timeEfficiency
      )
      input = ProductionInputFormatter.format([request])
    }
    let planner = IndustryPlanner()
    let preparedInput = try await plannerInputPreparation(
      input: input,
      sdeBuild: active.buildNumber,
      sdeContentSHA256: active.contentSHA256,
      includeCompressedOreOptions:
        productionBasis.compressedOreRefining.isEnabled,
      includeJumpFuelIsotopes:
        productionBasis.logistics.jumpFreighter.isEnabled
        && productionBasis.coalitionTradingLocation != nil,
      calculationGeneration: plannerCalculationGeneration
    )
    let planningCatalog = preparedInput.catalog
    let preparation = preparedInput.preparation
    let typeIDs = preparation.marketTypeIDs
    let marketService = TradeHubMarketService(esi: esi)
    async let marketValue = marketService.orderSnapshot(
      typeIDs: typeIDs,
      regionID: mainRegionID,
      locationID: mainLocationID
    )
    async let adjustedValue = marketService.adjustedPrices()
    async let systemsValue = marketService.industrySystems()
    async let packagedVolumeValue = universeTypeVolumeService.volumes(
      for: typeIDs
    )
    let (market, adjusted, systems, packagedVolumeSnapshot) =
      try await (
        marketValue,
        adjustedValue,
        systemsValue,
        packagedVolumeValue
      )

    var allocatableStock: [Int64: Int64] = [:]
    var snapshotIDs: [UUID] = [
      packagedVolumeSnapshot.source.snapshotID
    ]
    var inputWarnings = packagedVolumeWarnings(packagedVolumeSnapshot)
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

    if let availableStockOverride { allocatableStock = availableStockOverride }

    var calculatorBasis = productionBasis
    calculatorBasis.logistics.isEnabled = true
    calculatorBasis.logistics.homeTradeHub = configuredMainHub.location
    calculatorBasis.logistics.marketLocationName =
      configuredMainHub.location.name
    calculatorBasis.logistics.includeInboundMaterials = true
    calculatorBasis.logistics.includeOutboundProducts = true
    let configuredReaction =
      calculatorBasis.configuredReactionProfile ?? reactionProfile
    let calculationCatalog = MemoizedIndustryCatalog(
      base: PackagedVolumeSnapshotCatalog(
        base: planningCatalog,
        packagedVolumes: packagedVolumeSnapshot.value ?? [:]
      )
    )
    func context(
      availableStock: [Int64: Int64],
      preferences: [Int64: MaterialProcurementPreference],
      warnings: [DomainWarning],
      blueprintCosts: [Int64: IndustryBlueprintCostAllocation] = [:],
      requiresCompleteBlueprintCosts: Bool = false,
      blueprintSupplyPlans: [Int64: BlueprintSupplyPlan] = [:],
      planID: UUID? = nil
    ) -> IndustryPlanningContext {
      IndustryPlanningContext(
        manufacturingProfile: manufacturingProfile,
        reactionProfile: configuredReaction,
        productionBasis: calculatorBasis,
        catalog: calculationCatalog,
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
        brokerFeeRate: configuredMainHub.marketTaxes.effectiveBrokerFeeRate,
        blueprintCostAllocations: blueprintCosts,
        requiresCompleteBlueprintCosts: requiresCompleteBlueprintCosts,
        productionEfficiencies: productionEfficiencies,
        blueprintSupplyPlans: blueprintSupplyPlans,
        planID: planID
      )
    }

    let referencePlan = try await planner.plan(
      preparation: preparation,
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
    let blueprintTypeIDs = Set(
      referencePlan.nodes.compactMap(\.blueprintTypeID)
    )
    let blueprintNames = try await catalog.typeNames(ids: blueprintTypeIDs)
    let blueprintMarket = try await marketService.orderSnapshot(
      typeIDs: blueprintTypeIDs,
      regionID: mainRegionID,
      locationID: mainLocationID
    )
    snapshotIDs.append(blueprintMarket.source.snapshotID)
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
          startLocationID: mainLocationID,
          limitPerType: 500
        )
        contractOffers = snapshot.offers
        publicContractCoverageComplete =
          snapshot.progress.hasCompleteSearchCoverage
          && !snapshot.offers.values.contains { $0.count >= 500 }
      } catch {
        if error is CancellationError {
          throw error
        }
      }
    }
    var requiredRunsByBlueprintTypeID: [Int64: Int] = [:]
    var productNameByBlueprintTypeID: [Int64: String] = [:]
    for node in referencePlan.nodes where node.action == .produce {
      guard let blueprintTypeID = node.blueprintTypeID else { continue }
      requiredRunsByBlueprintTypeID[blueprintTypeID, default: 0] += max(
        0,
        node.runs ?? 0
      )
      productNameByBlueprintTypeID[blueprintTypeID] = node.name
    }
    let blueprintPortfolio = BlueprintPortfolio(
      inventories: blueprintInventories
    )
    let reservedQuantities = Dictionary(
      grouping: existingReservations,
      by: \.typeID
    ).mapValues { values in
      values.reduce(0) {
        AssetWarehouse.saturatedAdd($0, max(0, $1.quantity))
      }
    }
    let preflightPlan = try await planner.plan(
      preparation: preparation,
      context: context(
        availableStock: allocatableStock,
        preferences: selectedPreferences,
        warnings: inputWarnings
      ),
      reusingMakeOrBuyAnalysesFrom: referencePlan
    )
    let preflightTree = ManufacturingProductionTreeProjector.project(
      targetQuantity: targetQuantity,
      mainHub: configuredMainHub.location,
      referencePlan: referencePlan,
      selectedPlan: preflightPlan,
      warehouse: assetWarehouse,
      warehouseHasSnapshot: warehouseHasSnapshot,
      protectedQuantities: stockTargets,
      reservedQuantities: reservedQuantities,
      preferences: selectedPreferences,
      blueprintPortfolio: blueprintPortfolio,
      blueprintNames: blueprintNames,
      blueprintContractOffers: contractOffers,
      blueprintMarketOrders: blueprintMarket.ordersByType,
      blueprintMarketSource: blueprintMarket.source,
      blueprintMarketState: blueprintMarket.state,
      publicContractCoverageComplete: publicContractCoverageComplete,
      loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprintTypeIDs,
      inventionDefinitions: inventionDefinitions,
      productionScope: calculatorBasis.productionWarehouseScope
    )
    let selectedPlanID = UUID()
    let blueprintSupplyPlans = BlueprintSupplyPlanner.plans(
      referencePlan: preflightPlan,
      assessments: preflightTree.nodes.compactMap(\.blueprint),
      actions: blueprintActions,
      manualCosts: blueprintManualCosts,
      preferredEfficiencies: productionEfficiencies,
      planID: selectedPlanID,
      existingReservations: existingBlueprintReservations,
      preferredSources: preferredBlueprintSources
    )
    var blueprintCosts: [Int64: IndustryBlueprintCostAllocation] = [:]
    for (blueprintTypeID, action) in blueprintActions {
      let productName =
        productNameByBlueprintTypeID[blueprintTypeID]
        ?? blueprintNames[blueprintTypeID]
        ?? "Blueprint type \(blueprintTypeID)"
      let manualAmount = blueprintManualCosts[blueprintTypeID].flatMap {
        $0.isFinite && $0 >= 0 ? $0 : nil
      }
      switch action {
      case .buyContractBPC:
        if let supply = blueprintSupplyPlans[blueprintTypeID],
          let totalPrice = supply.batchAllocationCost
        {
          blueprintCosts[blueprintTypeID] = IndustryBlueprintCostAllocation(
            blueprintTypeID: blueprintTypeID,
            productName: productName,
            kind: .bpc,
            amount: totalPrice,
            source:
              "\(supply.manufacturingJobs.count) concrete Main Hub BPC Contract(s), \(supply.requiredRuns) allocated runs"
          )
        }
      case .useOwnedBPC, .invent, .buyLoyaltyStoreBPC, .manualExternalBPC:
        if let manualAmount {
          blueprintCosts[blueprintTypeID] = IndustryBlueprintCostAllocation(
            blueprintTypeID: blueprintTypeID,
            productName: productName,
            kind: .bpc,
            amount: manualAmount,
            source:
              action == .buyLoyaltyStoreBPC
              ? "Configured Loyalty Store BPC ISK equivalent"
              : "Explicit BPC acquisition or activity cost"
          )
        }
      case .useOwnedBPO, .copyOwnedBPO, .buyContractBPO, .buyMarketBPO:
        if let manualAmount {
          blueprintCosts[blueprintTypeID] = IndustryBlueprintCostAllocation(
            blueprintTypeID: blueprintTypeID,
            productName: productName,
            kind: .bpo,
            amount: manualAmount,
            source: "Explicit BPO allocation for this production plan"
          )
        }
      case .useOwnedReactionFormula:
        blueprintCosts[blueprintTypeID] = IndustryBlueprintCostAllocation(
          blueprintTypeID: blueprintTypeID,
          productName: productName,
          kind: .formula,
          amount: manualAmount ?? 0,
          source: "Explicitly selected owned reaction formula"
        )
      case .unavailable, .unresolved:
        blueprintCosts.removeValue(forKey: blueprintTypeID)
        break
      }
    }
    let selectedPlan = try await planner.plan(
      preparation: preparation,
      context: context(
        availableStock: allocatableStock,
        preferences: selectedPreferences,
        warnings: inputWarnings,
        blueprintCosts: blueprintCosts,
        requiresCompleteBlueprintCosts:
          requiresCompleteBlueprintCostsInSelectedPlan,
        blueprintSupplyPlans: blueprintSupplyPlans,
        planID: selectedPlanID
      ),
      reusingMakeOrBuyAnalysesFrom: referencePlan
    )
    return ManufacturingProductionTreeProjector.project(
      targetQuantity: targetQuantity,
      mainHub: configuredMainHub.location,
      referencePlan: referencePlan,
      selectedPlan: selectedPlan,
      warehouse: assetWarehouse,
      warehouseHasSnapshot: warehouseHasSnapshot,
      protectedQuantities: stockTargets,
      reservedQuantities: reservedQuantities,
      preferences: selectedPreferences,
      blueprintPortfolio: blueprintPortfolio,
      blueprintNames: blueprintNames,
      blueprintContractOffers: contractOffers,
      blueprintMarketOrders: blueprintMarket.ordersByType,
      blueprintMarketSource: blueprintMarket.source,
      blueprintMarketState: blueprintMarket.state,
      publicContractCoverageComplete: publicContractCoverageComplete,
      loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprintTypeIDs,
      inventionDefinitions: inventionDefinitions,
      productionScope: calculatorBasis.productionWarehouseScope
    )
  }

  var marketAnalysisContextIdentity: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let basis = (try? encoder.encode(productionBasis)) ?? Data()
    return "\(activeSDEBuild ?? -1):\(basis.base64EncodedString())"
  }

  var configuredReactionMarketHub: MarketHubConfigurationSnapshot? {
    let saved = AppDefaults.store.string(forKey: "reactions.market-hub-id") ?? ""
    let hubs = productionBasis.marketHubSnapshots
    return hubs.first { $0.id.uuidString == saved }
      ?? hubs.first { $0.roles.contains(.main) }
      ?? hubs.first
  }

  var configuredReactionRuns: Int {
    let saved = AppDefaults.store.integer(forKey: "reactions.analysis-runs")
    return min(max(1, saved == 0 ? 100 : saved),
      reactionAnalysis?.maximumSelectableRuns ?? ReactionJobRules.neutralMaximumSelectableRuns)
  }

  var isReactionAnalysisCurrent: Bool {
    guard let analysis = reactionAnalysis,
      let hub = configuredReactionMarketHub
    else { return false }
    return reactionResultContext == marketAnalysisContextIdentity
      && analysis.marketLocation.id == hub.location.id
      && analysis.runs == configuredReactionRuns
  }

  func refreshConfiguredReactions(
    authorizations: [AuthorizationSnapshot], clientID: String
  ) async {
    guard let hub = configuredReactionMarketHub else {
      reactionAnalysisError = "No configured purchase market is available."
      return
    }
    await analyzeReactions(
      runs: configuredReactionRuns, marketHub: hub,
      authorizations: authorizations, clientID: clientID
    )
  }

  func analyzeReactions(
    runs requestedRuns: Int,
    marketHub: MarketHubConfigurationSnapshot,
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = "",
    forceRefresh: Bool = false
  ) async {
    let identity = materialPurchaseAnalysisRefreshIdentity(
      kind: .moonMaterials, hubs: [marketHub],
      authorizations: authorizations, clientID: clientID
    ) + "#\(requestedRuns)#" + marketAnalysisContextIdentity
    await sharedReactionRefresh.run(identity: identity) { [self] in
      if !forceRefresh, reactionRefreshIdentity == identity,
        let analysis = reactionAnalysis,
        (0..<Self.materialPurchaseMinimumRefreshInterval).contains(Date().timeIntervalSince(analysis.createdAt))
      { return }
      let previousID = reactionAnalysis?.id
      let context = marketAnalysisContextIdentity
      await performReactionAnalysis(
        runs: requestedRuns, marketHub: marketHub,
        authorizations: authorizations, clientID: clientID
      )
      if context == marketAnalysisContextIdentity,
        reactionAnalysis?.id != previousID, reactionAnalysisError == nil
      {
        reactionRefreshIdentity = identity
        reactionResultContext = context
      }
    }
  }

  private func performReactionAnalysis(
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
    let configurationContext = marketAnalysisContextIdentity
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
      async let packagedVolumesValue = universeTypeVolumeService.volumes(
        for: typeIDs
      )
      let marketValue: MarketOrderSnapshot
      if marketHub.location.kind == .playerStructure {
        guard let structureID = marketHub.location.locationID,
          let systemID = marketHub.location.solarSystemID
        else { throw ESIError.notFound }
        let authorization = await marketStructureAuthorization(
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
      let (names, classifications, packagedVolumeSnapshot, adjusted, systems) = try await (
        namesValue,
        classificationsValue,
        packagedVolumesValue,
        adjustedValue,
        systemsValue
      )
      try Task.checkCancellation()
      let facility = reactionFacilityCostContext(systemIndices: systems)
      let logistics = reactionLogisticsCostContext(
        origin: marketHub.location,
        packagedVolumes: packagedVolumeSnapshot.value ?? [:]
      )
      let analysis = try ReactionProfitabilityAnalyzer.analyze(
        definitions: definitions,
        typeNames: names,
        classifications: classifications,
        runs: runs,
        marketLocation: marketHub.location,
        market: marketValue,
        adjustedPrices: adjusted,
        facility: facility,
        logistics: logistics
      )
      guard configurationContext == marketAnalysisContextIdentity else { return }
      reactionAnalysis = analysis
      reactionAnalysisDestinationName = logistics.destinationName
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
    await ESIRequestContext.withPriority(
      isAutomatic ? .automatic : .interactive
    ) {
      await performManufacturingOpportunityAnalysis(
        settings: settings,
        isAutomatic: isAutomatic
      )
    }
  }

  private func performManufacturingOpportunityAnalysis(
    settings: ManufacturingOpportunitySettings,
    isAutomatic: Bool
  ) async {
    let opportunitySettings = settings.mainHubOpportunityBaseline
    guard !isAnalyzingManufacturingOpportunities else { return }
    if !isAutomatic {
      mainHubMarketAutomationTask?.cancel()
      mainHubMarketAutomationTask = nil
      mainHubMarketNextAutomaticRunAt = nil
    }
    isAnalyzingManufacturingOpportunities = true
    manufacturingOpportunityError = nil
    resetManufacturingOpportunityProgress()
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
      async let manufacturingDefinitionsValue = catalog.manufacturingDefinitions()
      async let reactionDefinitionsValue = catalog.reactionDefinitions()
      async let marketValue = service.locationOrderSnapshot(
        regionID: regionID,
        locationID: locationID
      ) { [weak self] completed, total in
        await MainActor.run {
          self?.publishManufacturingOpportunityProgress(
            ManufacturingOpportunityScanProgress(
              completedPages: completed,
              totalPages: total
            )
          )
        }
      }
      async let adjustedValue = service.adjustedPrices()
      async let systemsValue = service.industrySystems()
      let (manufacturingDefinitions, reactionDefinitions, market, adjusted, systems) =
        try await (
          manufacturingDefinitionsValue,
          reactionDefinitionsValue,
          marketValue,
          adjustedValue,
          systemsValue
        )
      let definitions = manufacturingDefinitions + reactionDefinitions
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
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        demand = nil
        manufacturingOpportunityDemandError =
          "The Main Hub scan completed, but its demand observation could not be stored. Existing observations were not replaced."
      }
      let productTypeIDs = Set(definitions.map(\.productTypeID))
      let allTypeIDs = Set(
        definitions.flatMap {
          [$0.productTypeID]
            + $0.activity.materials.map(\.typeID)
            + $0.activity.products.map(\.typeID)
        }
      )
      async let namesValue = catalog.typeNames(ids: allTypeIDs)
      async let classificationsValue = catalog.industryClassifications(
        typeIDs: productTypeIDs
      )
      async let volumesValue = universeTypeVolumeService.volumes(
        for: allTypeIDs
      )
      let (names, classifications, packagedVolumeSnapshot) = try await (
        namesValue, classificationsValue, volumesValue
      )
      let facilities = manufacturingOpportunityFacilities(
        systemIndices: systems
      )
      let reactionFacility = reactionFacilityCostContext(systemIndices: systems)
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
          packagedVolumes: packagedVolumeSnapshot.value ?? [:],
          settings: opportunitySettings,
          mainHub: mainHub,
          productionWarehouseScope: productionWarehouseScope,
          logisticsConfiguration: logisticsConfiguration,
          market: market,
          demand: demand,
          adjustedPrices: adjusted,
          facilities: facilities,
          reactionFacility: reactionFacility,
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
        await manufacturingOpportunitySnapshotStore.releaseCachedSnapshot()
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
        "The active SDE catalog contains no complete published manufacturing or reaction definitions."
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
    let identity = materialPurchaseAnalysisRefreshIdentity(
      kind: .moonMaterials, hubs: productionBasis.marketHubSnapshots,
      authorizations: authorizations, clientID: clientID
    )
    await sharedMoonRefresh.run(identity: identity) { [self] in
      await performMoonMaterialRefresh(authorizations: authorizations, clientID: clientID)
    }
  }

  private func performMoonMaterialRefresh(
    authorizations: [AuthorizationSnapshot], clientID: String
  ) async {
    guard !isRefreshingMoonMaterialAnalysis else { return }
    let hubs = productionBasis.marketHubSnapshots
    let context = marketAnalysisContextIdentity
    let refreshIdentity = materialPurchaseAnalysisRefreshIdentity(
      kind: .moonMaterials,
      hubs: hubs,
      authorizations: authorizations,
      clientID: clientID
    )
    if let analysis = moonMaterialAnalysis,
      moonMaterialRefreshIdentity == refreshIdentity
    {
      let age = Date().timeIntervalSince(analysis.refreshedAt)
      if age >= 0 && age < Self.materialPurchaseMinimumRefreshInterval {
        moonMaterialAnalysisError = nil
        return
      }
    }
    isRefreshingMoonMaterialAnalysis = true
    moonMaterialAnalysisError = nil
    defer { isRefreshingMoonMaterialAnalysis = false }

    do {
      let materialCatalog = try await catalog.materialPurchaseCatalog(
        for: .moonMaterials
      )
      let analysis = try await loadMaterialPurchaseAnalysis(
        materialCatalog: materialCatalog,
        hubs: hubs,
        authorizations: authorizations,
        clientID: clientID,
        previous: moonMaterialAnalysis
      )
      guard refreshIdentity == materialPurchaseAnalysisRefreshIdentity(
        kind: .moonMaterials, hubs: productionBasis.marketHubSnapshots,
        authorizations: authorizations, clientID: clientID
      ) else { return }
      guard context == marketAnalysisContextIdentity else { return }
      moonMaterialAnalysis = analysis
      moonMaterialResultContext = context
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

  func refreshMineralPurchaseAnalysis(
    authorizations: [AuthorizationSnapshot] = [],
    clientID: String = ""
  ) async {
    let identity = materialPurchaseAnalysisRefreshIdentity(
      kind: .minerals, hubs: productionBasis.marketHubSnapshots,
      authorizations: authorizations, clientID: clientID
    )
    await sharedMineralRefresh.run(identity: identity) { [self] in
      await performMineralPurchaseRefresh(authorizations: authorizations, clientID: clientID)
    }
  }

  private func performMineralPurchaseRefresh(
    authorizations: [AuthorizationSnapshot], clientID: String
  ) async {
    guard !isRefreshingMineralPurchaseAnalysis else { return }
    let hubs = productionBasis.marketHubSnapshots
    let context = marketAnalysisContextIdentity
    let refreshIdentity = materialPurchaseAnalysisRefreshIdentity(
      kind: .minerals,
      hubs: hubs,
      authorizations: authorizations,
      clientID: clientID
    )
    if let analysis = mineralPurchaseAnalysis,
      mineralPurchaseRefreshIdentity == refreshIdentity
    {
      let age = Date().timeIntervalSince(analysis.refreshedAt)
      if age >= 0 && age < Self.materialPurchaseMinimumRefreshInterval {
        mineralPurchaseAnalysisError = nil
        return
      }
    }
    isRefreshingMineralPurchaseAnalysis = true
    mineralPurchaseAnalysisError = nil
    defer { isRefreshingMineralPurchaseAnalysis = false }

    do {
      let materialCatalog = try await catalog.materialPurchaseCatalog(
        for: .minerals
      )
      let analysis = try await loadMaterialPurchaseAnalysis(
        materialCatalog: materialCatalog,
        hubs: hubs,
        authorizations: authorizations,
        clientID: clientID,
        previous: mineralPurchaseAnalysis
      )
      guard refreshIdentity == materialPurchaseAnalysisRefreshIdentity(
        kind: .minerals, hubs: productionBasis.marketHubSnapshots,
        authorizations: authorizations, clientID: clientID
      ) else { return }
      guard context == marketAnalysisContextIdentity else { return }
      mineralPurchaseAnalysis = analysis
      mineralPurchaseResultContext = context
      mineralPurchaseRefreshIdentity = refreshIdentity
    } catch is CancellationError {
      return
    } catch StaticCatalogError.noActiveCatalog {
      mineralPurchaseAnalysisError =
        "No active SDE catalog is installed. Install or activate static data first."
    } catch {
      mineralPurchaseAnalysisError =
        "Minerals could not be loaded from the active SDE catalog."
    }
  }

  private func loadMaterialPurchaseAnalysis(
    materialCatalog: MaterialPurchaseCatalogSnapshot,
    hubs: [MarketHubConfigurationSnapshot],
    authorizations: [AuthorizationSnapshot],
    clientID: String,
    previous: MaterialPurchaseAnalysisSnapshot?
  ) async throws -> MaterialPurchaseAnalysisSnapshot {
    let typeIDs = Set(materialCatalog.materials.map(\.id))
    let marketService = TradeHubMarketService(esi: esi)
    let preferredTraderIDs = Dictionary(
      uniqueKeysWithValues: productionBasis.tradingLocations.map {
        ($0.id, $0.marketTaxes.traderCharacterID)
      }
    )
    let structureAuthorization = await marketStructureAuthorization(
      authorizations: authorizations,
      clientID: clientID
    )
    try Task.checkCancellation()
    let attempts = await withTaskGroup(
      of: MaterialPurchaseMarketRefreshResult?.self,
      returning: [UUID: Sourced<MarketOrderSnapshot>].self
    ) { group in
      for hub in hubs {
        group.addTask {
          do {
            let snapshot: MarketOrderSnapshot
            if hub.location.kind == .playerStructure {
              guard let structureID = hub.location.locationID,
                let systemID = hub.location.solarSystemID
              else { throw ESIError.notFound }
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
                for lease in orderedLeases {
                  do {
                    loadedSnapshot =
                      try await marketService.structureOrderSnapshot(
                        typeIDs: typeIDs,
                        regionID: system.regionID,
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
              else { throw ESIError.notFound }
              snapshot = try await marketService.sellOrderSnapshot(
                typeIDs: typeIDs,
                regionID: regionID,
                locationID: locationID
              )
            }
            return MaterialPurchaseMarketRefreshResult(
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
            let failure = Self.materialPurchaseMarketFailure(error)
            return MaterialPurchaseMarketRefreshResult(
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
    try Task.checkCancellation()

    let canRetainPreviousMarkets =
      previous?.materialCatalog.source.version
      == materialCatalog.source.version
    var markets: [UUID: Sourced<MarketOrderSnapshot>] = [:]
    for hub in hubs {
      guard let attempt = attempts[hub.id] else { continue }
      let previousMarket =
        canRetainPreviousMarkets ? previous?.configuredMarkets[hub.id] : nil
      let retainablePrevious: Sourced<MarketOrderSnapshot>?
      let previousMatchesLocation =
        previousMarket?.value?.locationID == hub.location.locationID
      if hub.location.kind == .playerStructure {
        retainablePrevious =
          previousMarket?.source.provider
            == TradeHubMarketService.structureMarketProvider
            && previousMatchesLocation
          ? previousMarket : nil
      } else {
        retainablePrevious =
          previousMarket?.source.provider
            != TradeHubMarketService.structureMarketProvider
            && previousMatchesLocation
          ? previousMarket : nil
      }
      markets[hub.id] = attempt.retainingLastKnownValue(
        from: retainablePrevious
      )
    }
    return MaterialPurchaseAnalysisSnapshot(
      materialCatalog: materialCatalog,
      configuredHubs: hubs,
      configuredMarkets: markets,
      refreshedAt: .now
    )
  }

  private func materialPurchaseAnalysisRefreshIdentity(
    kind: MaterialPurchaseCatalogKind,
    hubs: [MarketHubConfigurationSnapshot],
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) -> String {
    let marketIdentity = hubs.map { hub in
      let roles = hub.roles.map(\.rawValue).sorted().joined(separator: ",")
      let traderID = productionBasis.tradingLocations.first {
        $0.id == hub.id
      }?.marketTaxes.traderCharacterID
      let locationID = hub.location.locationID.map(String.init) ?? ""
      let solarSystemID = hub.location.solarSystemID.map(String.init) ?? ""
      let regionID = hub.location.regionID.map(String.init) ?? ""
      let traderCharacterID = traderID.map(String.init) ?? ""
      return [
        hub.id.uuidString,
        hub.location.id,
        hub.location.kind.rawValue,
        locationID,
        solarSystemID,
        regionID,
        roles,
        traderCharacterID,
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
      kind.rawValue,
      marketAnalysisContextIdentity,
      String(activeSDEBuild ?? -1),
      clientID.trimmingCharacters(in: .whitespacesAndNewlines),
      marketIdentity,
      authorizationIdentity,
    ].joined(separator: "#")
  }

  private func marketStructureAuthorization(
    authorizations: [AuthorizationSnapshot],
    clientID: String
  ) async -> MarketStructureAuthorization {
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

  nonisolated private static func materialPurchaseMarketFailure(
    _ error: Error
  ) -> (state: DataFreshness, diagnostic: String) {
    guard let esiError = error as? ESIError else {
      return (.unavailable, "esi.material-market.unavailable")
    }
    switch esiError {
    case .authorizationRequired:
      return (
        .forbidden,
        "esi.material-market.structure-authorization-required"
      )
    case .missingScope:
      return (.forbidden, "esi.material-market.structure-scope-missing")
    case .forbidden:
      return (.forbidden, "esi.material-market.structure-access-forbidden")
    case .notFound:
      return (.unavailable, "esi.material-market.structure-not-found")
    case .rateLimited:
      return (.unavailable, "esi.material-market.rate-limited")
    case .http(401):
      return (
        .forbidden,
        "esi.material-market.structure-token-unavailable"
      )
    default:
      return (.unavailable, "esi.material-market.unavailable")
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

  private func packagedVolumeWarnings(
    _ snapshot: Sourced<[Int64: Double]>
  ) -> [DomainWarning] {
    switch snapshot.state {
    case .fresh:
      return []
    case .partial:
      return [
        DomainWarning(
          code: "logistics.packaged-volume-partial",
          message:
            "Some authoritative packaged volumes could not be loaded from public ESI. Affected transport calculations remain unavailable; assembled SDE volume is not substituted.",
          severity: .warning,
          source: snapshot.source
        )
      ]
    case .stale:
      return [
        DomainWarning(
          code: "logistics.packaged-volume-stale",
          message:
            "The packaged-volume snapshot is stale. Transport calculations keep the retained value visibly sourced.",
          severity: .warning,
          source: snapshot.source
        )
      ]
    case .forbidden, .unavailable:
      return [
        DomainWarning(
          code: "logistics.packaged-volume-unavailable",
          message:
            "Authoritative packaged volumes are unavailable from public ESI. Transport calculations remain unavailable; assembled SDE volume is not substituted.",
          severity: .warning,
          source: snapshot.source
        )
      ]
    }
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
      async let typeNamesValue = catalog.typeNames(ids: typeIDs)
      async let assetClassificationsValue = catalog.industryClassifications(typeIDs: typeIDs)
      let typeNames = (try? await typeNamesValue) ?? [:]
      let assetClassifications = (try? await assetClassificationsValue) ?? [:]
      var definitionsByProductTypeID: [Int64: BlueprintDefinition] = [:]
      let inProgressProductTypeIDs = Set(
        inputs.flatMap { input in
          guard let jobs = input.industryJobs,
            [.fresh, .partial, .stale].contains(jobs.state)
          else { return [Int64]() }
          return (jobs.value ?? []).compactMap { job in
            guard let activity = job.dashboardActivity,
              activity == .manufacturing || activity == .reaction,
              !job.isDelivered,
              !job.isCancelledOrReverted
            else { return nil }
            return job.productTypeID
          }
        }
      )
      for productTypeID in inProgressProductTypeIDs.sorted() {
        guard !Task.isCancelled else { return }
        if let definition = try? await catalog.productionDefinition(
          productTypeID: productTypeID
        ) {
          definitionsByProductTypeID[productTypeID] = definition
        }
      }
      let jobValues = DashboardInProgressIndustryProjector.projectJobs(
        inputs: inputs, prices: prices.prices,
        definitionsByProductTypeID: definitionsByProductTypeID
      )
      let productIDs = Set(jobValues.compactMap { $0.ownedJob.job.productTypeID })
      dashboardIndustryProductNames = (try? await catalog.typeNames(ids: productIDs)) ?? [:]
      dashboardIndustryJobValues = jobValues
      let inProgressIndustryValues =
        DashboardInProgressIndustryProjector.project(
          inputs: inputs,
          prices: prices.prices,
          definitionsByProductTypeID: definitionsByProductTypeID,
          jobValues: jobValues
        )
      dashboardWealthSnapshot = DashboardWealthProjector.project(
        inputs: inputs,
        prices: prices,
        typeNames: typeNames,
        assetClassifications: assetClassifications,
        inProgressIndustryValues: inProgressIndustryValues
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

  func searchPlannerManufacturingProducts(matching query: String) async throws
    -> [ManufacturingProductSearchResult]
  {
    try await catalog.searchManufacturingProducts(
      matching: query,
      limit: 80
    )
  }

  func consolidationCatalogNames(_ ids: Set<Int64>) async throws -> [Int64: String] {
    guard activeSDEBuild != nil else {
      throw ConsolidationError.unavailable("Zuerst unter Daten & Einstellungen einen geprüften SDE-Datenkatalog installieren.")
    }
    return try await catalog.consolidationPublishedNames(ids)
  }
  func consolidationScienceDefinitions(_ blueprintID: Int64) async throws -> ([BlueprintScienceActivityDefinition], [BlueprintDecryptorDefinition]) {
    async let activities = catalog.blueprintScienceActivities(blueprintTypeID: blueprintID)
    async let decryptors = catalog.decryptorDefinitions()
    return try await (activities, decryptors)
  }
  func consolidationManufacturingDefinition(_ blueprintID: Int64) async throws -> BlueprintDefinition? {
    try await catalog.consolidationManufacturingDefinition(blueprintID)
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
    try await solarSystemSearch.search(
      query: query,
      limit: SolarSystemSearchService.maximumInteractiveSearchResults
    )
  }

  func prepareSolarSystemSearchIndex() async throws -> Int {
    try await solarSystemSearch.prepareSearchIndex()
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

  func syncPublicContractFeeEvidence(
    authorization: AuthorizationSnapshot,
    clientID: String
  ) async throws -> Sourced<PublicContractFeeEvidenceSnapshot> {
    let auth = authService(clientID: clientID)
    let lease = try await auth.accessTokenLease(
      characterID: authorization.characterID
    )
    return await PublicContractFeeSyncService(esi: esi).synchronize(
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

  func reimportCurrentSDE(
    schemaReviewConfirmed: Bool
  ) async {
    guard let updatePreview else { return }
    await perform("Reimporting current static data catalog") {
      let service = try makeSDELifecycle()
      let freshPreview = try await service.check()
      guard freshPreview == updatePreview else {
        throw SDELifecycleError.confirmationDoesNotMatchPreview
      }
      _ = try await service.reimportCurrentConfirmed(
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

  func reserveDashboardStartupRefresh() -> Bool {
    guard !hasReservedDashboardStartupRefresh else { return false }
    hasReservedDashboardStartupRefresh = true
    return true
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

  private func resetManufacturingOpportunityProgress() {
    manufacturingOpportunityProgressThrottle.reset()
    publishManufacturingOpportunityProgress(
      ManufacturingOpportunityScanProgress(),
      force: true
    )
  }

  private func publishManufacturingOpportunityProgress(
    _ progress: ManufacturingOpportunityScanProgress,
    force: Bool = false,
    now: Date = .now
  ) {
    guard progress != manufacturingOpportunityProgress else { return }
    let reachedBoundary =
      progress.totalPages > 0
      && progress.completedPages >= progress.totalPages
    guard
      manufacturingOpportunityProgressThrottle.shouldPublish(
        at: now,
        force: force || reachedBoundary
      )
    else { return }
    manufacturingOpportunityProgress = progress
  }

  private func publishPublicContractProgress(
    _ progress: PublicContractSyncProgress,
    force: Bool = false,
    now: Date = .now
  ) {
    guard progress != publicContractProgress else { return }
    let phaseChanged = progress.phase != publicContractProgress.phase
    let reachedBoundary =
      switch progress.phase {
      case .completed, .partial, .cancelled, .throttled, .failed:
        true
      case .idle, .loadingRegions, .loadingContracts, .loadingItems:
        false
      }
    guard
      publicContractProgressThrottle.shouldPublish(
        at: now,
        force: force || phaseChanged || reachedBoundary
      )
    else { return }
    publicContractProgress = progress
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
    operationGeneration &+= 1
    let generation = operationGeneration
    activeOperationCount += 1
    isWorking = true
    errorMessage = nil
    statusMessage = status
    defer {
      activeOperationCount = max(0, activeOperationCount - 1)
      isWorking = activeOperationCount > 0
      if generation == operationGeneration,
        errorMessage == nil,
        statusMessage == status
      {
        statusMessage = "Ready"
      }
    }
    do {
      try await operation()
    } catch is CancellationError {
      if generation == operationGeneration {
        statusMessage = "Cancelled"
      }
    } catch ESIError.cancelled {
      if generation == operationGeneration {
        statusMessage = "Cancelled"
      }
    } catch {
      if generation == operationGeneration {
        errorMessage = operationErrorMessage(error)
        statusMessage = "Failed"
      }
    }
  }

  private func operationErrorMessage(_ error: Error) -> String {
    if error as? StaticCatalogError == .invalidPointer {
      return AppLocalization.text(
        "The active SDE catalog reference is invalid or incompatible. Existing catalog files were preserved. Restart the app and try the safe SDE reimport again."
      )
    }
    return String(describing: error)
  }
}

private struct MaterialPurchaseMarketRefreshResult: Sendable {
  let hubID: UUID
  let result: Sourced<MarketOrderSnapshot>
}

private enum PlannerSecondaryMarketLoad: Sendable {
  case notConfigured
  case reuseMain
  case loaded(MarketOrderSnapshot)
  case unavailable
  case cancelled
}

private enum PlannerContractReferenceLoad: Sendable {
  case notConfigured
  case loaded(PublicContractReferenceSnapshot)
  case unavailable
  case cancelled
}

private enum MarketStructureAuthorization: Sendable {
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
  private let summaryFileURL: URL
  private var loadedLedger: ManufacturingOpportunityDemandLedger?

  init(fileURL: URL) {
    self.fileURL = fileURL
    summaryFileURL =
      fileURL
      .deletingPathExtension()
      .appendingPathExtension("summary.json")
  }

  func currentDemand() throws -> ManufacturingOpportunityDemandSnapshot? {
    if FileManager.default.fileExists(atPath: summaryFileURL.path),
      let data = try? Data(contentsOf: summaryFileURL),
      let summary = try? JSONDecoder().decode(
        ManufacturingOpportunityDemandSnapshot.self,
        from: data
      )
    {
      return summary
    }
    let current = try ledger().demand
    if let current { try? persistSummary(current) }
    loadedLedger = nil
    return current
  }

  func observe(
    _ market: MarketOrderSnapshot
  ) throws -> ManufacturingOpportunityDemandSnapshot {
    var updated = try ledger()
    let demand = try updated.observe(market) {
      try Task.checkCancellation()
    }
    let encoded: Data
    do {
      encoded = try JSONEncoder().encode(updated)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: summaryFileURL.path) {
        try FileManager.default.removeItem(at: summaryFileURL)
      }
      try encoded.write(to: fileURL, options: .atomic)
      // This derived summary keeps normal app starts from decoding the complete
      // order baseline. The ledger remains authoritative if this cache write
      // fails or is interrupted.
      try? persistSummary(demand)
    } catch is CancellationError {
      throw CancellationError()
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

  private func persistSummary(
    _ demand: ManufacturingOpportunityDemandSnapshot
  ) throws {
    let data = try JSONEncoder().encode(demand)
    try FileManager.default.createDirectory(
      at: summaryFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: summaryFileURL, options: .atomic)
  }
}
