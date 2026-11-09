import AppKit
import Combine
import EVENexusCore
import SwiftData
import SwiftUI

enum NavigationSection: String, CaseIterable, Identifiable {
  case dashboard
  case planner
  case manufacturingOpportunities
  case homeHubOpportunities
  case coalitionHubOpportunities
  case trade
  case tradeLogbook
  case marketStock
  case stockSaleComparison
  case publicContracts
  case reactions
  case moonMaterialAnalysis
  case mineralPurchaseAnalysis
  case items
  case warehouse
  case blueprints
  case productionBook
  case netWorth
  case data

  var id: Self { self }

  static var establishedCases: [Self] {
    allCases
  }

  var title: LocalizedStringKey {
    switch self {
    case .dashboard: "Dashboard"
    case .planner: "Planner"
    case .manufacturingOpportunities: "Main Hub Opportunities"
    case .homeHubOpportunities: "Home Hub Opportunities"
    case .coalitionHubOpportunities: "Coalition Hub Opportunities"
    case .trade: "Trade"
    case .tradeLogbook: "Trade logbook"
    case .marketStock: "Market stock"
    case .stockSaleComparison: "Stock sale comparison"
    case .publicContracts: "Public Contracts"
    case .reactions: "Reactions"
    case .moonMaterialAnalysis: "Moon purchase analysis"
    case .mineralPurchaseAnalysis: "Mineral purchase analysis"
    case .items: "All items"
    case .warehouse: "Warehouse"
    case .blueprints: "Blueprints"
    case .productionBook: "Production Overview"
    case .netWorth: "Net Worth"
    case .data: "Data & Settings"
    }
  }

  var icon: String {
    switch self {
    case .dashboard: "gauge.with.dots.needle.67percent"
    case .planner: "hammer.fill"
    case .manufacturingOpportunities: "chart.line.uptrend.xyaxis"
    case .homeHubOpportunities: "house.fill"
    case .coalitionHubOpportunities: "flag.fill"
    case .trade: "arrow.left.arrow.right"
    case .tradeLogbook: "book.closed.fill"
    case .marketStock: "chart.bar.xaxis"
    case .stockSaleComparison: "scalemass.fill"
    case .publicContracts: "doc.text.magnifyingglass"
    case .reactions: "atom"
    case .moonMaterialAnalysis: "chart.xyaxis.line"
    case .mineralPurchaseAnalysis: "circle.grid.3x3.fill"
    case .items: "square.grid.2x2.fill"
    case .warehouse: "shippingbox.fill"
    case .blueprints: "doc.on.doc.fill"
    case .productionBook: "books.vertical.fill"
    case .netWorth: "chart.line.uptrend.xyaxis"
    case .data: "externaldrive.fill"
    }
  }

  /// Sidebar group in the New Eden HUD style (plan D2, section 4 of
  /// `Documentation/DESIGN_HUD_2026-11-07.md`).
  var group: NavigationGroup {
    switch self {
    case .dashboard, .netWorth: .overview
    case .planner, .reactions, .blueprints, .productionBook: .industry
    case .manufacturingOpportunities, .homeHubOpportunities,
      .coalitionHubOpportunities:
      .opportunities
    case .trade, .tradeLogbook, .marketStock, .stockSaleComparison,
      .publicContracts, .moonMaterialAnalysis, .mineralPurchaseAnalysis:
      .market
    case .items, .warehouse: .assets
    case .data: .system
    }
  }
}

/// Groups of the HUD sidebar. Classic keeps the flat list "Established
/// workflows" in the order of `NavigationSection.establishedCases`.
enum NavigationGroup: String, CaseIterable, Identifiable {
  case overview
  case industry
  case opportunities
  case market
  case assets
  case system

  var id: Self { self }

  var titleKey: String {
    switch self {
    case .overview: "Overview"
    case .industry: "Industry"
    case .opportunities: "Opportunities"
    case .market: "Market"
    case .assets: "Assets"
    case .system: "System"
    }
  }

  var title: LocalizedStringKey {
    LocalizedStringKey(titleKey)
  }

  /// Entries of the group in their established relative order.
  var sections: [NavigationSection] {
    NavigationSection.establishedCases.filter { $0.group == self }
  }
}

struct DashboardNavigationRequest {
  let section: NavigationSection
  var negativeReactionsOnly = false
}

enum DataSettingsSection: String, CaseIterable, Identifiable {
  case general
  case sde
  case esi
  case industrySettings
  case logistics
  case marketSettings

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .general: "General"
    case .sde: "SDE"
    case .esi: "ESI"
    case .industrySettings: "Industry Settings"
    case .logistics: "Logistics"
    case .marketSettings: "Market Settings"
    }
  }

  var icon: String {
    switch self {
    case .general: "gearshape.fill"
    case .sde: "externaldrive.fill"
    case .esi: "network"
    case .industrySettings: "slider.horizontal.3"
    case .logistics: "truck.box.fill"
    case .marketSettings: "building.columns.fill"
    }
  }
}

struct HistoricalPlannerRequest: Equatable {
  let id: UUID
  let productionOverviewRowID: UUID

  init(productionOverviewRowID: UUID) {
    id = UUID()
    self.productionOverviewRowID = productionOverviewRowID
  }
}

struct PlannerLaunchRequest: Equatable {
  let id: UUID
  let productTypeID: Int64
  let productName: String
  let requestedRuns: Int
  let wantedQuantity: Int
  let materialEfficiency: Int
  let timeEfficiency: Int
  let blueprintSupplyPlanData: Data?
  let sourceSnapshotIDs: [UUID]
  /// Sale hub chosen in a hub-opportunity view; the Planner uses it from P10.
  let targetMarket: OpportunityHubRole?

  init(
    id: UUID = UUID(),
    productTypeID: Int64,
    productName: String,
    requestedRuns: Int,
    wantedQuantity: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    blueprintSupplyPlans: [BlueprintSupplyPlan] = [],
    sourceSnapshotIDs: [UUID] = [],
    targetMarket: OpportunityHubRole? = nil
  ) {
    self.id = id
    self.targetMarket = targetMarket
    self.productTypeID = productTypeID
    self.productName = productName
    self.requestedRuns = min(
      ManufacturingOpportunitySettings.maximumRequestedRuns,
      max(1, requestedRuns)
    )
    self.wantedQuantity = min(
      ProductionInputParser.maximumWantedQuantity,
      max(1, wantedQuantity)
    )
    self.materialEfficiency = min(10, max(0, materialEfficiency))
    self.timeEfficiency = min(20, max(0, timeEfficiency))
    self.blueprintSupplyPlanData =
      blueprintSupplyPlans.isEmpty
      ? nil : try? JSONEncoder().encode(blueprintSupplyPlans)
    self.sourceSnapshotIDs = Array(Set(sourceSnapshotIDs)).sorted {
      $0.uuidString < $1.uuidString
    }
  }

  var blueprintSupplyPlans: [BlueprintSupplyPlan] {
    guard let blueprintSupplyPlanData else { return [] }
    return
      (try? JSONDecoder().decode(
        [BlueprintSupplyPlan].self,
        from: blueprintSupplyPlanData
      )) ?? []
  }

  var inputLine: String {
    ProductionInputFormatter.format([
      ProductionRequestLine(
        lineNumber: 1,
        productName: productName,
        wantedQuantity: wantedQuantity,
        materialEfficiency: materialEfficiency,
        timeEfficiency: timeEfficiency
      )
    ])
  }
}

enum PlannerLaunchApplicationMode {
  case replace
  case append
}

enum PlannerLaunchInputPolicy {
  /// A handoff appends to an existing draft or result and replaces only an
  /// empty Planner.
  static func mode(
    currentInput: String,
    hasCalculatedPlan: Bool
  ) -> PlannerLaunchApplicationMode {
    hasCalculatedPlan
      || !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .append : .replace
  }

  static func applying(
    _ request: PlannerLaunchRequest,
    to currentInput: String,
    mode: PlannerLaunchApplicationMode
  ) -> String {
    switch mode {
    case .replace:
      request.inputLine
    case .append:
      ProductionInputFormatter.appending(request.inputLine, to: currentInput)
    }
  }
}

enum MainHubOpportunityPlannerHandoff {
  static func request(
    productTypeID: Int64,
    productName: String,
    requestedRuns: Int,
    wantedQuantity: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    targetMarket: OpportunityHubRole? = nil
  ) -> PlannerLaunchRequest {
    PlannerLaunchRequest(
      productTypeID: productTypeID,
      productName: productName,
      requestedRuns: requestedRuns,
      wantedQuantity: wantedQuantity,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency,
      targetMarket: targetMarket
    )
  }
}

/// Shared character synchronization for the startup load and the Dashboard.
@MainActor
enum CharacterBatchSynchronizer {
  static func synchronize(
    characters: [StoredCharacter],
    runtime: RuntimeState,
    modelContext: ModelContext,
    clientID: String = EVEConstants.ssoClientID
  ) async -> CharacterBatchSyncResult {
    let orderedCharacters = characters.sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    var synchronizedCount = 0
    var failures: [CharacterSyncFailure] = []
    for character in orderedCharacters {
      guard !Task.isCancelled else { break }
      func fail(_ reason: String) {
        modelContext.rollback()
        failures.append(
          CharacterSyncFailure(
            characterName: character.characterName,
            reason: reason
          )
        )
      }
      guard
        let authorization = try? JSONDecoder().decode(
          AuthorizationSnapshot.self,
          from: character.authorizationSnapshot
        )
      else {
        fail(
          AppLocalization.text(
            "The stored authorization could not be read. Authorize this character again."
          )
        )
        continue
      }
      do {
        try await runtime.syncCharacter(
          authorization: authorization,
          clientID: clientID
        )
      } catch {
        fail(EVEConnectionErrorText.message(for: error))
        continue
      }
      guard let latest = runtime.lastCharacterSync,
        latest.authorization.characterID == character.characterID
      else {
        fail(
          AppLocalization.text(
            "The synchronization result belonged to another character and was discarded."
          )
        )
        continue
      }
      do {
        try CharacterSyncPersistence.apply(
          latest,
          to: character,
          in: modelContext
        )
        try modelContext.save()
        synchronizedCount += 1
      } catch {
        fail(
          AppLocalization.text(
            "The synchronized data could not be saved locally; the previous data was kept."
          )
        )
      }
    }
    // Fresh wallet data is matched with the trade logbook (HANDEL_PLAN P7).
    await runtime.reconcileTradeLogbook(
      manufacturingTypeIDs: TradePlannerMaterials.typeIDs(in: modelContext)
    )
    return CharacterBatchSyncResult(
      synchronizedCount: synchronizedCount,
      totalCount: orderedCharacters.count,
      failedCharacterNames: failures.map(\.characterName),
      failures: failures
    )
  }
}

struct ContentView: View {
  @EnvironmentObject private var consolidation: ConsolidationController
  @Environment(\.modelContext) private var modelContext
  @State private var consolidationArea: ConsolidationArea?
  let runtime: RuntimeState
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var storedCharacters: [StoredCharacter]
  @State private var selection: NavigationSection? = .dashboard
  @State private var opensNegativeReactions = false
  @State private var dataSettingsSelection: DataSettingsSection = .general
  @State private var historicalPlannerRequest: HistoricalPlannerRequest?
  @State private var plannerLaunchRequest: PlannerLaunchRequest?
  /// Build link (hammer) clicks from every area except the Planner.
  @State private var plannerBuildRouter = PlannerBuildRouter()
  @State private var plannerBuildRequest: PlannerBuildRequest?
  @State private var didPreparePlannerConfiguration = false
  @StateObject private var profileNavigationGuard =
    ProfileNavigationGuard()
  @Environment(\.interfaceStyle) private var interfaceStyle

  var body: some View {
    NavigationSplitView {
      List(selection: guardedSelection) {
        if interfaceStyle == .hud {
          ForEach(NavigationGroup.allCases) { group in
            Section {
              ForEach(group.sections) { item in
                navigationRow(item)
              }
            } header: {
              Text(group.title)
                .nexusCaptionTitle()
                .accessibilityIdentifier("navigation.group.\(group.rawValue)")
            }
          }
        } else {
          Section("Established workflows") {
            ForEach(NavigationSection.establishedCases) { item in
              navigationRow(item)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(DesignTokens.sidebar)
      .navigationSplitViewColumnWidth(
        min: DesignTokens.sidebarMinimum,
        ideal: DesignTokens.sidebarIdeal
      )
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 0) {
          SidebarAutomaticDataStatus(runtime: runtime)
          PublicContractSidebarStatus(runtime: runtime)
          Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: 124)
            .accessibilityLabel("EVE New Eden Nexus - Assets, Industry, Markets")
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.vertical, DesignTokens.spacingSM)
        }
        .background(DesignTokens.sidebarElevated)
        .overlay(alignment: .top) {
          Rectangle()
            .fill(DesignTokens.border)
            .frame(height: 1)
        }
      }
    } detail: {
      VStack(spacing: 0) {
        EVEOnlineServiceBanner()
        Group {
          switch selection ?? .dashboard {
          case .dashboard:
            DashboardView { request in
              opensNegativeReactions = request.negativeReactionsOnly
              guardedSelection.wrappedValue = request.section
            }
          case .planner:
            PlannerView(
              historicalPlannerRequest: $historicalPlannerRequest,
              launchRequest: $plannerLaunchRequest,
              buildRequest: $plannerBuildRequest,
              runtime: runtime,
              onOpenDataSettings: { section in
                guardedDataSettingsSelection.wrappedValue = section
                guardedSelection.wrappedValue = .data
              }
            )
          case .manufacturingOpportunities:
            ManufacturingOpportunitiesView { request in
              historicalPlannerRequest = nil
              plannerLaunchRequest = request
              selection = .planner
            }
          case .homeHubOpportunities:
            ManufacturingOpportunitiesView(
              hubRole: .home,
              onOpenMarketSettings: {
                guardedDataSettingsSelection.wrappedValue = .marketSettings
                guardedSelection.wrappedValue = .data
              },
              onOpenMainHubOpportunities: {
                guardedSelection.wrappedValue = .manufacturingOpportunities
              }
            ) { request in
              historicalPlannerRequest = nil
              plannerLaunchRequest = request
              selection = .planner
            }
          case .coalitionHubOpportunities:
            ManufacturingOpportunitiesView(
              hubRole: .coalition,
              onOpenMarketSettings: {
                guardedDataSettingsSelection.wrappedValue = .marketSettings
                guardedSelection.wrappedValue = .data
              },
              onOpenMainHubOpportunities: {
                guardedSelection.wrappedValue = .manufacturingOpportunities
              },
              onOpenHomeHubOpportunities: {
                guardedSelection.wrappedValue = .homeHubOpportunities
              }
            ) { request in
              historicalPlannerRequest = nil
              plannerLaunchRequest = request
              selection = .planner
            }
          case .trade:
            TradeView(
              onOpenMarketSettings: {
                guardedDataSettingsSelection.wrappedValue = .marketSettings
                guardedSelection.wrappedValue = .data
              },
              onOpenLogistics: {
                guardedDataSettingsSelection.wrappedValue = .logistics
                guardedSelection.wrappedValue = .data
              },
              onOpenSDESettings: {
                guardedDataSettingsSelection.wrappedValue = .sde
                guardedSelection.wrappedValue = .data
              }
            )
          case .tradeLogbook:
            TradeLogbookView()
          case .marketStock:
            MarketStockView()
          case .stockSaleComparison:
            StockSaleComparisonView(
              onOpenMarketSettings: {
                guardedDataSettingsSelection.wrappedValue = .marketSettings
                guardedSelection.wrappedValue = .data
              }
            )
          case .publicContracts:
            PublicContractsView()
          case .reactions:
            ReactionsView(initialNegativeFilter: $opensNegativeReactions)
          case .moonMaterialAnalysis:
            MoonMaterialPurchaseAnalysisView()
          case .mineralPurchaseAnalysis:
            MineralPurchaseAnalysisView()
          case .items:
            AssetsWarehouseView(mode: .allItems)
          case .warehouse:
            AssetsWarehouseView(mode: .productionWarehouse)
          case .blueprints:
            BlueprintsView()
          case .productionBook:
            ProductionBookView(
              onOpenHistoricalPlan: openHistoricalPlan
            )
          case .netWorth:
            NetWorthView()
          case .data:
            DataSettingsWorkspace(
              selection: guardedDataSettingsSelection
            )
          }
        }
        .environment(\.navigationGroup, (selection ?? .dashboard).group)
        .nexusCanvasBackground()
      }
    }
    .toolbar {
      if selection != .planner {
        if selection == .blueprints {
          Button("Wissenschaftsaufträge") { consolidationArea = .science }
        }
        if selection == .productionBook { Button("Verkaufsbelege") { consolidationArea = .sales } }
      }
    }
    .sheet(item: $consolidationArea) { area in
      ConsolidationWorkbenchView(area: area)
        .marketStockHistoryHost()
    }
    .marketStockHistoryHost()
    // Outside the history host, so its sheets see the router too; no router
    // while the Planner is shown (owner rule 09.11.2026).
    .environment(
      \.plannerBuildRouter,
      selection == .planner ? nil : plannerBuildRouter
    )
    .onChange(of: plannerBuildRouter.request) { _, request in
      guard let request else { return }
      plannerBuildRouter.request = nil
      openPlannerBuild(request)
    }
    .onChange(of: runtime.plannerBuildTargetIndex, initial: true) { _, targets in
      plannerBuildRouter.targets = targets
    }
    .task {
      if runtime.plannerBuildTargetIndex == nil {
        await runtime.refreshPlannerBuildTargetIndex()
      }
    }
    .navigationSplitViewStyle(.balanced)
    .tint(DesignTokens.accent)
    .frame(minWidth: 640, minHeight: 480)
    .environmentObject(profileNavigationGuard)
    .task {
      guard !didPreparePlannerConfiguration else { return }
      didPreparePlannerConfiguration = true
      let steps = startupDataLoadSteps()
      guard runtime.startsBackgroundServices else {
        await steps.prepareConfiguration()
        return
      }
      await runtime.startupDataLoad.run(steps)
    }
    .task {
      while !Task.isCancelled {
        await runtime.refreshEVEOnlineServiceStatus()
        do {
          try await Task.sleep(for: .seconds(300))
        } catch {
          break
        }
      }
    }
    .confirmationDialog(
      "Unsaved configuration changes",
      isPresented: $profileNavigationGuard.isPresentingWarning,
      titleVisibility: .visible
    ) {
      Button("Save and Continue") {
        profileNavigationGuard.requestSaveAndContinue()
      }
      Button("Discard Changes", role: .destructive) {
        profileNavigationGuard.requestDiscardAndContinue()
      }
      Button("Cancel", role: .cancel) {
        profileNavigationGuard.cancelNavigation()
      }
    } message: {
      Text(
        "Your changes have not been saved. Save them before leaving this page so your configuration is not lost."
      )
    }
  }

  private var guardedSelection: Binding<NavigationSection?> {
    Binding(
      get: { selection },
      set: { destination in
        guard let destination else { return }
        guard selection != destination else { return }
        if profileNavigationGuard.hasUnsavedChanges {
          profileNavigationGuard.attemptNavigation {
            selection = destination
          }
        } else {
          selection = destination
        }
      }
    )
  }

  private var guardedDataSettingsSelection: Binding<DataSettingsSection> {
    Binding(
      get: { dataSettingsSelection },
      set: { destination in
        guard dataSettingsSelection != destination else { return }
        if profileNavigationGuard.hasUnsavedChanges {
          profileNavigationGuard.attemptNavigation {
            dataSettingsSelection = destination
          }
        } else {
          dataSettingsSelection = destination
        }
      }
    )
  }

  /// Writes regions resolved at startup into the stored configuration only;
  /// every other field of the stored record stays exactly as saved.
  private static func storeLocationRegions(
    _ regions: [Int64: Int64],
    in stored: StoredProductionBasis?,
    modelContext: ModelContext
  ) {
    guard !regions.isEmpty, let stored,
      var basis = try? JSONDecoder().decode(
        ProductionBasis.self,
        from: stored.encodedBasis
      ),
      basis.applyLocationRegions(regions),
      let data = try? JSONEncoder().encode(basis)
    else { return }
    stored.encodedBasis = data
    try? modelContext.save()
  }

  /// Startup order (owner decision 2026-10-20): characters and planner
  /// configuration, then market analyses and the automatic background scans.
  private func startupDataLoadSteps() -> StartupDataLoad.Steps {
    let runtime = runtime
    let modelContext = modelContext
    let characters = storedCharacters
    let storedBasis = storedBases.first
    let encodedBasis = storedBasis?.encodedBasis
    let capabilities = storedCharacters.compactMap { character in
      character.capabilitySnapshot.flatMap {
        try? JSONDecoder().decode(
          CharacterCapabilitySnapshot.self,
          from: $0
        )
      }
    }
    return StartupDataLoad.Steps(
      prepareConfiguration: {
        await runtime.preparePlannerConfiguration(
          encodedBasis: encodedBasis,
          capabilities: capabilities
        )
        Self.storeLocationRegions(
          runtime.resolvedLocationRegions,
          in: storedBasis,
          modelContext: modelContext
        )
      },
      synchronizeCharacters: {
        await CharacterBatchSynchronizer.synchronize(
          characters: characters,
          runtime: runtime,
          modelContext: modelContext
        )
      },
      refreshMarketAnalyses: {
        let authorizations = characters.compactMap {
          try? JSONDecoder().decode(
            AuthorizationSnapshot.self,
            from: $0.authorizationSnapshot
          )
        }
        runtime.rememberMarketAuthorizations(
          authorizations,
          clientID: EVEConstants.ssoClientID,
          capabilities: characters.compactMap { character in
            character.capabilitySnapshot.flatMap {
              try? JSONDecoder().decode(
                CharacterCapabilitySnapshot.self,
                from: $0
              )
            }
          }
        )
        async let moon: Void = runtime.refreshMoonMaterialAnalysis(
          authorizations: authorizations, clientID: EVEConstants.ssoClientID)
        async let minerals: Void = runtime.refreshMineralPurchaseAnalysis(
          authorizations: authorizations, clientID: EVEConstants.ssoClientID)
        async let reactions: Void = runtime.refreshConfiguredReactions(
          authorizations: authorizations, clientID: EVEConstants.ssoClientID)
        _ = await (moon, minerals, reactions)
      },
      releaseAutomaticScans: {
        await runtime.releaseStartupAutomaticScans()
      }
    )
  }

  private func navigationRow(_ item: NavigationSection) -> some View {
    // The sidebar list style sets its own row font on the label; only a
    // font on the title and icon themselves follows the text size.
    Label {
      Text(item.title).appFontKeepingSystemDefault(.body)
    } icon: {
      Image(systemName: item.icon).appFontKeepingSystemDefault(.body)
    }
    .tag(item)
    .accessibilityIdentifier("navigation.\(item.rawValue)")
  }

  private func openHistoricalPlan(_ row: StoredProductionOverviewRow) {
    historicalPlannerRequest = HistoricalPlannerRequest(
      productionOverviewRowID: row.id
    )
    selection = .planner
  }

  /// A build link click: unsaved settings keep their warning, and a
  /// cancelled navigation drops the request instead of applying it later.
  private func openPlannerBuild(_ request: PlannerBuildRequest) {
    profileNavigationGuard.attemptNavigation {
      // The consolidation sheet belongs to the window and would stay open.
      consolidationArea = nil
      historicalPlannerRequest = nil
      plannerBuildRequest = request
      selection = .planner
    }
  }
}

enum PublicContractBackgroundPhase: Equatable {
  case disabled
  case preparing
  case failed
  case stopping
  case synchronizing
  case incomplete
  case partial
  case syncFailed
  case scheduled
  case current
}

struct PublicContractBackgroundPresentation: Equatable {
  let phase: PublicContractBackgroundPhase
  let progressFraction: Double?

  init(
    storeState: PublicContractStoreState,
    progress: PublicContractSyncProgress,
    isSynchronizing: Bool,
    isCancelling: Bool,
    automaticUpdatesEnabled: Bool
  ) {
    let hasIncompleteInitialImport =
      progress.regionCount == 0
      || progress.remainingInitialRegions > 0
      || progress.pendingItemContracts > 0
    let hasPartialIndex =
      progress.phase == .partial
      || progress.failedRegions > 0
      || progress.failedItemContracts > 0
    switch storeState {
    case .disabled:
      phase = .disabled
    case .preparing:
      phase = .preparing
    case .failed:
      phase = .failed
    case .ready where isCancelling:
      phase = .stopping
    case .ready where isSynchronizing:
      phase = .synchronizing
    case .ready where hasIncompleteInitialImport:
      phase = .incomplete
    case .ready where hasPartialIndex:
      phase = .partial
    case .ready where progress.phase == .failed:
      phase = .syncFailed
    case .ready where automaticUpdatesEnabled:
      phase = .scheduled
    case .ready:
      phase = .current
    }

    guard isSynchronizing else {
      progressFraction = nil
      return
    }
    switch progress.phase {
    case .loadingRegions:
      progressFraction = 0.01
    case .loadingContracts:
      guard progress.regionCount > 0 else {
        progressFraction = 0.05
        return
      }
      progressFraction = min(
        0.4,
        0.05 + 0.35 * Double(progress.completedRegions)
          / Double(progress.regionCount)
      )
    case .loadingItems:
      guard progress.indexedContracts > 0 else {
        progressFraction = 0.4
        return
      }
      progressFraction = min(
        1,
        0.4 + 0.6
          * Double(progress.indexedContracts - progress.pendingItemContracts)
          / Double(progress.indexedContracts)
      )
    case .completed:
      progressFraction = 1
    default:
      progressFraction = nil
    }
  }
}

/// Sidebar card "Automatic data": startup loads plus the recurring contract
/// and hub market refreshes, placed directly above the contract import.
struct SidebarAutomaticDataStatus: View {
  let runtime: RuntimeState
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query private var esiSnapshotMetadata: [StoredESISnapshotMetadata]
  @AppStorage("sidebar.automatic-data-expanded", store: AppDefaults.store)
  private var isExpanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingXS) {
        FullWidthDisclosureButton(
          isExpanded: isExpanded,
          action: { isExpanded.toggle() }
        ) {
          HStack(spacing: DesignTokens.spacingXS) {
            Label("Automatic data", systemImage: "arrow.triangle.2.circlepath")
              .appFont(.caption.weight(.semibold))
              .foregroundStyle(DesignTokens.textPrimary)
            if isUpdatingMarketsOrContracts {
              ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Updating")
            }
          }
        }
        optionsMenu
      }
      if isExpanded {
        StartupDataStatusSection(
          startupLoad: runtime.startupDataLoad,
          inputs: startupDataStatusInputs
        )
        Divider()
        automaticStatusRow(
          title: "Contracts",
          detail: contractAutomaticStatus,
          systemImage: "doc.text.magnifyingglass",
          color: contractAutomaticStatusColor,
          progress: contractAutomaticProgress
        )
        automaticStatusRow(
          title: "Main Hub market",
          detail: mainHubAutomaticStatus,
          systemImage: "building.columns",
          color: mainHubAutomaticStatusColor,
          progress: mainHubAutomaticProgress
        )
        automaticStatusRow(
          title: "Home Hub market",
          detail: secondaryHubAutomaticStatus(.home),
          systemImage: "house",
          color: secondaryHubAutomaticStatusColor(.home),
          progress: secondaryHubAutomaticProgress(.home)
        )
        automaticStatusRow(
          title: "Coalition Hub market",
          detail: secondaryHubAutomaticStatus(.coalition),
          systemImage: "flag",
          color: secondaryHubAutomaticStatusColor(.coalition),
          progress: secondaryHubAutomaticProgress(.coalition)
        )
        automaticStatusRow(
          title: "Market stock",
          detail: marketStockAutomaticStatus,
          systemImage: "chart.bar.xaxis",
          color: marketStockAutomaticStatusColor,
          progress: nil
        )
        .help(marketStockAutomaticHelp)
        automaticStatusRow(
          title: "Loyalty Stores",
          detail: loyaltyStoreAutomaticStatus,
          systemImage: "rosette",
          color: loyaltyStoreAutomaticStatusColor,
          progress: nil
        )
      }
    }
    .padding(.horizontal, DesignTokens.spacingMD)
    .padding(.vertical, DesignTokens.spacingSM)
    // Same bounded wrapping width as the contract import status below.
    .frame(
      minWidth: DesignTokens.sidebarMinimum,
      maxWidth: .infinity,
      alignment: .leading
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("navigation.automatic-data-status")
  }

  private var isUpdatingMarketsOrContracts: Bool {
    runtime.isSynchronizingPublicContracts
      || runtime.isAnalyzingManufacturingOpportunities
      || runtime.opportunityState(for: .home).isAnalyzing
      || runtime.opportunityState(for: .coalition).isAnalyzing
      || runtime.isRefreshingLoyaltyStoreCatalog
  }

  private var optionsMenu: some View {
    Menu {
      if runtime.mainHubMarketAutomaticUpdatesEnabled {
        Button {
          runtime.setMainHubMarketAutomaticUpdatesEnabled(false)
        } label: {
          Label("Pause Main Hub updates", systemImage: "pause.circle")
        }
      } else {
        Button {
          runtime.setMainHubMarketAutomaticUpdatesEnabled(true)
        } label: {
          Label("Resume Main Hub updates", systemImage: "play.circle")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Automatic data options")
    .accessibilityLabel("Automatic data options")
  }

  private func automaticStatusRow(
    title: LocalizedStringKey,
    detail: String,
    systemImage: String,
    color: Color,
    progress: Double?
  ) -> some View {
    AutomaticStatusRow(
      title: title,
      detail: detail,
      systemImage: systemImage,
      color: color,
      progress: progress
    )
  }

  private var startupDataStatusInputs: StartupDataStatusSection.Inputs {
    let characterIDs = Set(characters.map(\.characterID))
    let observations = esiSnapshotMetadata.compactMap {
      metadata -> StartupDataStatusProjector.SourceObservation? in
      guard characterIDs.contains(metadata.characterID),
        metadata.domain == "assets" || metadata.domain == "blueprints",
        let freshness = DataFreshness(rawValue: metadata.freshness)
      else { return nil }
      return StartupDataStatusProjector.SourceObservation(
        freshness: freshness,
        capturedAt: metadata.capturedAt
      )
    }
    return StartupDataStatusSection.Inputs(
      lastSyncDates: characters.map(\.lastSyncAt),
      warehouseObservations: observations,
      isAnalyzingReactions: runtime.isAnalyzingReactions,
      reactionMarketStates: runtime.reactionAnalysis.map { _ in [.fresh] },
      reactionHasError: runtime.reactionAnalysisError != nil,
      reactionTimestamp: runtime.reactionAnalysis?.createdAt,
      isRefreshingMoon: runtime.isRefreshingMoonMaterialAnalysis,
      moonMarketStates: runtime.moonMaterialAnalysis.map {
        $0.configuredMarkets.values.map(\.state)
      },
      moonHasError: runtime.moonMaterialAnalysisError != nil,
      moonTimestamp: runtime.moonMaterialAnalysis?.refreshedAt,
      isRefreshingMinerals: runtime.isRefreshingMineralPurchaseAnalysis,
      mineralMarketStates: runtime.mineralPurchaseAnalysis.map {
        $0.configuredMarkets.values.map(\.state)
      },
      mineralHasError: runtime.mineralPurchaseAnalysisError != nil,
      mineralTimestamp: runtime.mineralPurchaseAnalysis?.refreshedAt
    )
  }

  private var contractAutomaticProgress: Double? {
    guard runtime.isSynchronizingPublicContracts,
      runtime.publicContractProgress.regionCount > 0
    else { return nil }
    let completed =
      runtime.publicContractProgress.remainingInitialRegions > 0
      ? runtime.publicContractProgress.completedRegions
      : runtime.publicContractProgress.freshRegions
    return min(
      1,
      max(
        0,
        Double(completed)
          / Double(runtime.publicContractProgress.regionCount)
      )
    )
  }

  private var contractAutomaticStatus: String {
    let progress = runtime.publicContractProgress
    if runtime.isSynchronizingPublicContracts {
      if let activeRegionName = progress.activeRegionName {
        return AppLocalization.format("Updating · %@", activeRegionName)
      }
      return AppLocalization.format(
        "Updating · %lld/%lld regions",
        Int64(progress.completedRegions),
        Int64(progress.regionCount)
      )
    }
    if progress.phase == .failed || runtime.publicContractError != nil {
      return AppLocalization.text("Update failed")
    }
    if progress.phase == .partial || progress.failedRegions > 0 {
      return AppLocalization.text("Partial index retained")
    }
    if let next = runtime.publicContractNextAutomaticRunAt {
      return AppLocalization.format(
        "Next %@",
        next.formatted(date: .omitted, time: .shortened)
      )
    }
    if let completed = progress.lastCompletedAt {
      return AppLocalization.format(
        "Updated %@",
        completed.formatted(date: .omitted, time: .shortened)
      )
    }
    return runtime.publicContractAutomaticUpdatesEnabled
      ? AppLocalization.text("Preparing")
      : AppLocalization.text("Paused")
  }

  private var contractAutomaticStatusColor: Color {
    if runtime.isSynchronizingPublicContracts { return DesignTokens.accent }
    if runtime.publicContractProgress.phase == .failed
      || runtime.publicContractError != nil
    {
      return DesignTokens.negative
    }
    if runtime.publicContractProgress.phase == .partial
      || runtime.publicContractProgress.failedRegions > 0
    {
      return DesignTokens.caution
    }
    return runtime.publicContractAutomaticUpdatesEnabled
      ? DesignTokens.positive : DesignTokens.textSecondary
  }

  private var mainHubAutomaticProgress: Double? {
    guard runtime.isAnalyzingManufacturingOpportunities else { return nil }
    return runtime.manufacturingOpportunityProgress.fractionCompleted
  }

  private var mainHubAutomaticStatus: String {
    if runtime.isAnalyzingManufacturingOpportunities {
      let progress = runtime.manufacturingOpportunityProgress
      if progress.totalPages > 0 {
        return AppLocalization.format(
          "Updating · page %lld/%lld",
          Int64(progress.completedPages),
          Int64(progress.totalPages)
        )
      }
      return AppLocalization.text("Preparing market pages")
    }
    guard let location = runtime.productionBasis.mainTradingLocation?.location,
      location.kind == .npcTradeHub
    else { return AppLocalization.text("Main Hub not configured") }
    if runtime.manufacturingOpportunityError != nil {
      return AppLocalization.text("Update failed")
    }
    guard runtime.mainHubMarketAutomaticUpdatesEnabled else {
      return AppLocalization.text("Paused")
    }
    if let next = runtime.mainHubMarketNextAutomaticRunAt {
      return AppLocalization.format(
        "Next %@",
        next.formatted(date: .omitted, time: .shortened)
      )
    }
    if let capturedAt = matchingMainHubMarketCapturedAt {
      return AppLocalization.format(
        "Updated %@",
        capturedAt.formatted(date: .omitted, time: .shortened)
      )
    }
    return AppLocalization.text("Preparing")
  }

  /// Market stock history (MARKTBESTAND_PLAN P3): latest Main-Hub point and
  /// the next fixed term; the help lists every hub.
  private var marketStockAutomaticStatus: String {
    if runtime.marketStockError != nil {
      return AppLocalization.text("Saving failed")
    }
    guard runtime.mainHubMarketAutomaticUpdatesEnabled else {
      return AppLocalization.text("Paused")
    }
    if runtime.isMarketStockWaitingForESI {
      return AppLocalization.text("Waiting for ESI")
    }
    let latest = runtime.marketStockLatestPointAt.values.max()
    switch (latest, runtime.marketStockNextTermAt) {
    case (let latest?, let next?):
      return AppLocalization.format(
        "Point %@ · next %@",
        Self.marketStockTime(latest),
        Self.marketStockTime(next)
      )
    case (nil, let next?):
      return AppLocalization.format("Next %@", Self.marketStockTime(next))
    case (let latest?, nil):
      return AppLocalization.format("Updated %@", Self.marketStockTime(latest))
    case (nil, nil):
      return AppLocalization.text("Preparing")
    }
  }

  private var marketStockAutomaticStatusColor: Color {
    if runtime.marketStockError != nil { return DesignTokens.negative }
    if runtime.isMarketStockWaitingForESI { return DesignTokens.caution }
    return runtime.mainHubMarketAutomaticUpdatesEnabled
      ? DesignTokens.positive : DesignTokens.textSecondary
  }

  private var marketStockAutomaticHelp: String {
    let hubs: [(OpportunityHubRole, String)] = [
      (.main, AppLocalization.text("Main Hub")),
      (.home, AppLocalization.text("Home Hub")),
      (.coalition, AppLocalization.text("Coalition Hub")),
    ]
    var lines = hubs.map { role, name in
      AppLocalization.format(
        "%@: last point %@",
        name,
        runtime.marketStockLatestPointAt[role].map(Self.marketStockTime) ?? "—"
      )
    }
    lines.append(
      AppLocalization.text(
        "Fixed terms 06:00 and 13:00; a successful hub scan up to 3 hours earlier counts for the term."
      )
    )
    if let error = runtime.marketStockError {
      lines.append(AppLocalization.text(error))
    }
    return lines.joined(separator: "\n")
  }

  private static func marketStockTime(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(.dateTime.day().month(.twoDigits).hour().minute())
  }

  /// Daily Loyalty Store catalog plus the LP known per character.
  private var loyaltyStoreAutomaticStatus: String {
    var parts: [String] = []
    if runtime.isRefreshingLoyaltyStoreCatalog {
      parts.append(AppLocalization.text("Updating"))
    } else if let error = runtime.loyaltyStoreCatalogError {
      parts.append(AppLocalization.text(error))
    } else if let catalog = runtime.loyaltyStoreCatalog,
      let offers = catalog.offers
    {
      parts.append(
        AppLocalization.format(
          "%lld offers · %@",
          Int64(offers.count),
          catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        )
      )
    } else {
      parts.append(AppLocalization.text("Not loaded yet"))
    }
    let knownCharacters = runtime.characterLoyaltyPoints?.characters.count ?? 0
    parts.append(
      AppLocalization.format("LP known for %lld character(s)", Int64(knownCharacters))
    )
    if !runtime.loyaltyPointsMissingScopeCharacters.isEmpty {
      parts.append(
        AppLocalization.format(
          "LP scope missing: %@",
          runtime.loyaltyPointsMissingScopeCharacters.sorted()
            .joined(separator: ", ")
        )
      )
    }
    return parts.joined(separator: " · ")
  }

  private var loyaltyStoreAutomaticStatusColor: Color {
    if runtime.isRefreshingLoyaltyStoreCatalog { return DesignTokens.accent }
    if runtime.loyaltyStoreCatalogError != nil { return DesignTokens.negative }
    if runtime.loyaltyStoreCatalog?.hasOfferDetails != true
      || !runtime.loyaltyPointsMissingScopeCharacters.isEmpty
    {
      return DesignTokens.caution
    }
    return DesignTokens.positive
  }

  private var mainHubAutomaticStatusColor: Color {
    if runtime.isAnalyzingManufacturingOpportunities {
      return DesignTokens.accent
    }
    if runtime.manufacturingOpportunityError != nil {
      return DesignTokens.negative
    }
    guard
      runtime.productionBasis.mainTradingLocation?.location.kind
        == .npcTradeHub
    else { return DesignTokens.caution }
    return runtime.mainHubMarketAutomaticUpdatesEnabled
      ? DesignTokens.positive : DesignTokens.textSecondary
  }

  private func secondaryHubAutomaticProgress(
    _ role: OpportunityHubRole
  ) -> Double? {
    let state = runtime.opportunityState(for: role)
    guard state.isAnalyzing else { return nil }
    return state.progress.fractionCompleted
  }

  private func secondaryHubAutomaticStatus(
    _ role: OpportunityHubRole
  ) -> String {
    let coalition = role == .coalition
    switch runtime.opportunityScanTarget(for: role) {
    case .notConfigured:
      return AppLocalization.text(
        coalition ? "Coalition Hub not configured" : "Home Hub not configured"
      )
    case .sharesMainHub:
      return AppLocalization.text("Uses Main Hub data")
    case .sharesHomeHub:
      return AppLocalization.text("Uses Home Hub data")
    case .unresolved:
      return AppLocalization.text(
        coalition
          ? "Coalition Hub location incomplete" : "Home Hub location incomplete"
      )
    case .npcStation, .playerStructure:
      break
    }
    let state = runtime.opportunityState(for: role)
    if state.isAnalyzing {
      if state.progress.totalPages > 0 {
        return AppLocalization.format(
          "Updating · page %lld/%lld",
          Int64(state.progress.completedPages),
          Int64(state.progress.totalPages)
        )
      }
      return AppLocalization.text("Preparing market pages")
    }
    if state.error != nil {
      if state.marketState?.state == .forbidden {
        return StartupDataStatusSection.freshnessText(.forbidden)
      }
      return AppLocalization.text("Update failed")
    }
    guard runtime.mainHubMarketAutomaticUpdatesEnabled else {
      return AppLocalization.text("Paused")
    }
    if let capturedAt = matchingSecondaryHubCapturedAt(role) {
      return AppLocalization.format(
        "Updated %@",
        capturedAt.formatted(date: .omitted, time: .shortened)
      )
    }
    if let next = runtime.mainHubMarketNextAutomaticRunAt {
      return AppLocalization.format(
        "Next %@",
        next.formatted(date: .omitted, time: .shortened)
      )
    }
    return AppLocalization.text("Preparing")
  }

  private func secondaryHubAutomaticStatusColor(
    _ role: OpportunityHubRole
  ) -> Color {
    switch runtime.opportunityScanTarget(for: role) {
    case .notConfigured, .sharesMainHub, .sharesHomeHub:
      return DesignTokens.textSecondary
    case .unresolved:
      return DesignTokens.caution
    case .npcStation, .playerStructure:
      break
    }
    let state = runtime.opportunityState(for: role)
    if state.isAnalyzing { return DesignTokens.accent }
    if state.error != nil { return DesignTokens.negative }
    if state.marketState?.state == .stale { return DesignTokens.caution }
    return runtime.mainHubMarketAutomaticUpdatesEnabled
      ? DesignTokens.positive : DesignTokens.textSecondary
  }

  /// Only a capture of the currently configured exact hub counts.
  private func matchingSecondaryHubCapturedAt(
    _ role: OpportunityHubRole
  ) -> Date? {
    let configured =
      role == .coalition
      ? runtime.productionBasis.coalitionTradingLocation
      : runtime.productionBasis.homeTradingLocation
    guard let locationID = configured?.location.locationID else { return nil }
    let state = runtime.opportunityState(for: role)
    if let market = state.marketState?.value, market.locationID == locationID {
      return market.capturedAt
    }
    guard let analysis = state.analysis,
      analysis.resolvedSaleHub.locationID == locationID
    else { return nil }
    return analysis.createdAt
  }

  private var matchingMainHubMarketCapturedAt: Date? {
    if let capturedAt = runtime.mainHubMarketState?.source.capturedAt {
      return capturedAt
    }
    guard
      let configuredLocationID =
        runtime.productionBasis.mainTradingLocation?.location.locationID,
      let analysis = runtime.manufacturingOpportunityAnalysis,
      analysis.mainHub.locationID == configuredLocationID
    else { return nil }
    return analysis.createdAt
  }
}

struct PublicContractSidebarStatus: View {
  let runtime: RuntimeState

  private var presentation: PublicContractBackgroundPresentation {
    PublicContractBackgroundPresentation(
      storeState: runtime.publicContractStoreState,
      progress: runtime.publicContractProgress,
      isSynchronizing: runtime.isSynchronizingPublicContracts,
      isCancelling: runtime.isCancellingPublicContracts,
      automaticUpdatesEnabled: runtime.publicContractAutomaticUpdatesEnabled
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Label("Contract import", systemImage: statusIcon)
        .appFont(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
      Text(statusText)
        .appFont(.caption2)
        .foregroundStyle(statusDetailColor)
        .fixedSize(horizontal: false, vertical: true)
      if let progressFraction = presentation.progressFraction {
        ProgressView(value: progressFraction)
          .tint(DesignTokens.accent)
          .controlSize(.mini)
      }
      Text(progressText)
        .appFont(.caption2.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      action
        .appFont(.caption)
        .controlSize(.small)
    }
    .padding(.horizontal, DesignTokens.spacingMD)
    .padding(.vertical, DesignTokens.spacingSM)
    // SwiftUI also measures the sidebar at zero width to derive its minimum
    // window size. Bound the wrapping width so fixed-height status text does
    // not force the entire split view taller than the screen.
    .frame(
      minWidth: DesignTokens.sidebarMinimum,
      maxWidth: .infinity,
      alignment: .leading
    )
    .background(
      presentation.phase == .incomplete
        ? DesignTokens.negative.opacity(0.08) : Color.clear
    )
    .overlay(alignment: .top) {
      Rectangle()
        .fill(DesignTokens.border)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("navigation.public-contract-background-status")
  }

  private var statusText: String {
    switch presentation.phase {
    case .disabled:
      return "Public Contracts background services are disabled".localizedUI
    case .preparing:
      return "Preparing the local index in the background. The menu remains available."
        .localizedUI
    case .failed:
      return "The local index could not be prepared. Existing data was not replaced."
        .localizedUI
    case .stopping:
      return "Stopping safely; partial progress remains stored.".localizedUI
    case .synchronizing:
      return "The import runs in the background. You can switch sections at any time."
        .localizedUI
    case .incomplete:
      return
        ("First import: allow two to three days. Start or continue it here without opening the contract list.")
        .localizedUI
    case .partial:
      return "A partial index was preserved. Continue the background import when convenient."
        .localizedUI
    case .syncFailed:
      return "The background import stopped with an error. Existing data was preserved."
        .localizedUI
    case .scheduled:
      return "Automatic continuation is scheduled in the background.".localizedUI
    case .current:
      return "The local Public Contracts index is current.".localizedUI
    }
  }

  private var progressText: String {
    AppLocalization.format(
      "%lld/%lld regions · %lld details pending",
      Int64(runtime.publicContractProgress.completedRegions),
      Int64(runtime.publicContractProgress.regionCount),
      Int64(runtime.publicContractProgress.pendingItemContracts)
    )
  }

  @ViewBuilder private var action: some View {
    switch presentation.phase {
    case .preparing, .disabled:
      EmptyView()
    case .failed:
      Button("Retry preparation") {
        runtime.retryPublicContractStorePreparation()
      }
      .accessibilityIdentifier("navigation.public-contract-retry")
    case .stopping:
      Button("Stopping …") {}
        .disabled(true)
    case .synchronizing:
      Button("Pause background import", role: .cancel) {
        runtime.cancelPublicContractSynchronization()
      }
      .accessibilityIdentifier("navigation.public-contract-pause")
    case .incomplete, .partial, .syncFailed:
      Button("Start or continue in background") {
        runtime.startPublicContractSynchronization()
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("navigation.public-contract-start")
    case .scheduled:
      HStack(spacing: DesignTokens.spacingXS) {
        Button("Update now") {
          runtime.startPublicContractSynchronization()
        }
        Button("Pause") {
          runtime.cancelPublicContractSynchronization()
        }
      }
    case .current:
      Button("Update in background") {
        runtime.startPublicContractSynchronization()
      }
    }
  }

  private var statusIcon: String {
    switch presentation.phase {
    case .preparing, .stopping: "hourglass"
    case .failed, .syncFailed: "exclamationmark.triangle.fill"
    case .synchronizing: "arrow.triangle.2.circlepath"
    case .incomplete: "exclamationmark.octagon.fill"
    case .partial: "exclamationmark.triangle.fill"
    case .scheduled: "clock.arrow.circlepath"
    case .current: "checkmark.circle.fill"
    case .disabled: "pause.circle"
    }
  }

  private var statusColor: Color {
    switch presentation.phase {
    case .failed, .incomplete, .syncFailed: DesignTokens.negative
    case .partial: DesignTokens.caution
    case .synchronizing: DesignTokens.accent
    case .current, .scheduled: DesignTokens.positive
    case .preparing, .stopping, .disabled: DesignTokens.textSecondary
    }
  }

  private var statusDetailColor: Color {
    switch presentation.phase {
    case .failed, .incomplete, .syncFailed: DesignTokens.negative
    case .partial: DesignTokens.caution
    default: DesignTokens.textSecondary
    }
  }
}

private struct DashboardIndustryRefreshIdentity: Hashable {
  let inputHash: Int
  let activeSDEBuild: Int?
}

enum DashboardWealthSeries: String, CaseIterable, Identifiable {
  case total
  case wallet
  case assets
  case industryInProgress

  var id: Self { self }

  /// Localization key of `title`, for formatted texts.
  var titleKey: String {
    switch self {
    case .total: "Total"
    case .wallet: "Wallet"
    case .assets: "Assets"
    case .industryInProgress: "In production"
    }
  }

  var title: LocalizedStringKey { LocalizedStringKey(titleKey) }

  /// Chart points of this series in the given history; empty when no
  /// snapshot has a value for it (plan DB7, finding B6).
  func samples(in history: [DashboardWealthSnapshot]) -> [DashboardWealthChartSample] {
    history.compactMap { snapshot in
      value(in: snapshot).map {
        DashboardWealthChartSample(date: snapshot.capturedAt, value: $0)
      }
    }
  }

  var color: Color {
    switch self {
    case .total: DesignTokens.highlight
    case .wallet: DesignTokens.accent
    case .assets: DesignTokens.positive
    case .industryInProgress: DesignTokens.caution
    }
  }

  func value(in snapshot: DashboardWealthSnapshot) -> Double? {
    switch self {
    case .total: snapshot.knownTotalValue
    case .wallet: snapshot.walletTotal
    case .assets: snapshot.assetTotal
    case .industryInProgress: snapshot.industryInProgressTotal
    }
  }
}

/// Stacks cards when their minimum widths cannot fit; otherwise preserves ratios.
/// With `equalizesHeights`, cards side by side share the row height like the
/// CSS grid rows of the Dashboard board (`Main.dc.html`).
struct DashboardCardLayout: Layout {
  let weights: [CGFloat]
  let minimumWidths: [CGFloat]
  var spacing: CGFloat = DesignTokens.spacingMD
  var equalizesHeights = false

  func widths(for width: CGFloat) -> [CGFloat] {
    guard !weights.isEmpty else { return [] }
    let available = max(0, width - spacing * CGFloat(weights.count - 1))
    guard width >= minimumWidths.reduce(0, +) + spacing * CGFloat(weights.count - 1)
    else { return Array(repeating: max(0, width), count: weights.count) }
    return weights.map { available * $0 / weights.reduce(0, +) }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = max(0, proposal.width ?? minimumWidths.reduce(0, +) + spacing * CGFloat(max(0, weights.count - 1)))
    let sizes = measured(width: width, subviews: subviews)
    let stacked = widths(for: width).first == width
    let height = stacked
      ? sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
      : sizes.map(\.height).max() ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let widths = widths(for: bounds.width)
    let sizes = measured(width: bounds.width, subviews: subviews)
    let stacked = widths.first == bounds.width
    let rowHeight = sizes.map(\.height).max() ?? 0
    var origin = bounds.origin
    for index in subviews.indices {
      let height = !stacked && equalizesHeights ? rowHeight : sizes[index].height
      subviews[index].place(at: origin, anchor: .topLeading,
        proposal: ProposedViewSize(width: widths[index], height: height))
      if stacked { origin.y += sizes[index].height + spacing }
      else { origin.x += widths[index] + spacing }
    }
  }

  private func measured(width: CGFloat, subviews: Subviews) -> [CGSize] {
    let widths = widths(for: width)
    return subviews.indices.map {
      subviews[$0].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil))
    }
  }
}

struct DashboardPreviewList<Row: Identifiable, RowContent: View>: View {
  let rows: [Row]
  /// Thin lines between rows like the lists of the Dashboard board.
  var showsSeparators = false
  @ViewBuilder var content: (Row) -> RowContent
  @State private var expanded = false

  var body: some View {
    VStack(
      alignment: .leading,
      spacing: showsSeparators ? 0 : DesignTokens.spacingSM
    ) {
      Text(AppLocalization.format("%lld items", Int64(rows.count)))
        .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
        .padding(.bottom, showsSeparators ? DesignTokens.spacingXS : 0)
      ForEach(Array(rows.prefix(expanded ? rows.count : 5))) { row in
        if showsSeparators {
          content(row)
            .padding(.vertical, DesignTokens.spacingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
              Rectangle()
                .fill(DesignTokens.border.opacity(0.4))
                .frame(height: 1)
                .accessibilityHidden(true)
            }
        } else {
          content(row)
        }
      }
      if rows.count > 5 {
        Button {
          expanded.toggle()
        } label: {
          Label {
            Text(expanded ? "Show less".localizedUI : "Show all".localizedUI)
          } icon: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
          }
        }
        .buttonStyle(.borderless)
        .accessibilityValue(expanded ? "Expanded".localizedUI : "Collapsed".localizedUI)
        .padding(.top, showsSeparators ? DesignTokens.spacingXS : 0)
      }
    }
  }
}

/// Rows of the Dashboard panel "Industry jobs · ready and upcoming" (plan DB1,
/// `Documentation/DASHBOARD_BOARD_2026-11-07.md`): every job ready for
/// delivery first, then running jobs ending within 48 hours; each group by end
/// date with the job identity as the final tie-breaker.
enum DashboardReadyAndUpcomingJobs {
  static let upcomingWindow: TimeInterval = 48 * 60 * 60

  struct Row: Identifiable {
    let owned: DashboardIndustryOwnedJob
    let isReady: Bool

    var id: String { owned.id }
  }

  static func rows(
    jobs: [DashboardIndustryOwnedJob],
    now: Date
  ) -> [Row] {
    func byEndDate(
      _ lhs: DashboardIndustryOwnedJob,
      _ rhs: DashboardIndustryOwnedJob
    ) -> Bool {
      if lhs.job.endDate != rhs.job.endDate {
        return lhs.job.endDate < rhs.job.endDate
      }
      return lhs.id < rhs.id
    }
    let cutoff = now.addingTimeInterval(upcomingWindow)
    let ready = jobs.filter { $0.job.isReadyForDelivery(at: now) }
      .sorted(by: byEndDate)
    let upcoming = jobs.filter {
      $0.job.isRunning(at: now) && $0.job.endDate <= cutoff
    }
    .sorted(by: byEndDate)
    return ready.map { Row(owned: $0, isReady: true) }
      + upcoming.map { Row(owned: $0, isReady: false) }
  }
}

/// One slot pool of the Dashboard key figures (plan DB4). Running (including
/// paused) and ready, not yet delivered jobs occupy a slot until delivery.
struct DashboardSlotFigure: Equatable {
  let running: Int
  let ready: Int
  let capacity: DashboardIndustryCapacitySummary

  var occupied: Int { running + ready }

  /// Free slots, never negative; a lower bound while the capacity is
  /// partial, `nil` without any known capacity.
  var free: Int? {
    capacity.value.map { max(0, $0 - occupied) }
  }

  /// Occupied share for the bar, only for a complete, positive capacity.
  var fillFraction: Double? {
    guard capacity.isComplete, let value = capacity.value, value > 0 else {
      return nil
    }
    return min(1, Double(occupied) / Double(value))
  }

  static func figure(
    jobs: [DashboardIndustryOwnedJob],
    activities: Set<DashboardIndustryActivity>,
    capacity: DashboardIndustryCapacitySummary,
    now: Date
  ) -> Self {
    let pool = jobs.filter {
      $0.job.dashboardActivity.map(activities.contains) == true
    }
    return Self(
      running: pool.filter { $0.job.isRunning(at: now) }.count,
      ready: pool.filter { $0.job.isReadyForDelivery(at: now) }.count,
      capacity: capacity
    )
  }
}

/// Areas of the app-start data load shown on the Dashboard (P2).
enum StartupDataArea: String, CaseIterable, Identifiable, Sendable {
  case characters
  case warehouseAndBlueprints
  case reactions
  case moonMaterials
  case minerals

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .characters: "Characters"
    case .warehouseAndBlueprints: "Warehouse & Blueprints"
    case .reactions: "Reactions"
    case .moonMaterials: "Moon materials"
    case .minerals: "Minerals"
    }
  }

  var systemImage: String {
    switch self {
    case .characters: "person.2"
    case .warehouseAndBlueprints: "shippingbox"
    case .reactions: "flask"
    case .moonMaterials: "moon"
    case .minerals: "cube"
    }
  }
}

enum StartupDataStatus: Equatable, Sendable {
  /// The startup load has not reached this area and no earlier data exists.
  case waiting
  case running
  case known(DataFreshness)
}

struct StartupDataStatusRow: Identifiable, Equatable, Sendable {
  let area: StartupDataArea
  let status: StartupDataStatus
  let timestamp: Date?

  var id: StartupDataArea { area }
}

/// Pure projection of existing runtime and persisted source states. It starts
/// no work and never turns missing data into a fresh or zero state.
enum StartupDataStatusProjector {
  struct SourceObservation: Equatable, Sendable {
    let freshness: DataFreshness
    let capturedAt: Date
  }

  /// Equal states keep their value. Usable (fresh/stale/partial) mixed with
  /// unusable (forbidden/unavailable) is `partial`. Otherwise the worse value
  /// wins: fresh < stale < partial, forbidden < unavailable.
  static func combined(_ states: [DataFreshness]) -> DataFreshness? {
    guard let first = states.first else { return nil }
    if states.allSatisfy({ $0 == first }) { return first }
    let usable = states.filter { [.fresh, .stale, .partial].contains($0) }
    if !usable.isEmpty, usable.count < states.count { return .partial }
    if usable.isEmpty { return .unavailable }
    if usable.contains(.partial) { return .partial }
    return usable.contains(.stale) ? .stale : .fresh
  }

  static func characters(
    phase: StartupDataLoad.Phase,
    result: CharacterBatchSyncResult?,
    lastSyncDates: [Date?]
  ) -> StartupDataStatusRow {
    let latest = lastSyncDates.compactMap { $0 }.max()
    let status: StartupDataStatus
    if phase == .loadingCharactersAndConfiguration {
      status = .running
    } else if let result {
      if result.totalCount == 0 {
        status = .known(.unavailable)
      } else if result.failedCharacterNames.isEmpty {
        status = .known(.fresh)
      } else if result.synchronizedCount == 0 {
        status = .known(.unavailable)
      } else {
        status = .known(.partial)
      }
    } else if lastSyncDates.isEmpty {
      status = .known(.unavailable)
    } else {
      status = latest == nil ? .waiting : .known(.stale)
    }
    return StartupDataStatusRow(
      area: .characters,
      status: status,
      timestamp: latest
    )
  }

  static func warehouseAndBlueprints(
    phase: StartupDataLoad.Phase,
    characterCount: Int,
    observations: [SourceObservation]
  ) -> StartupDataStatusRow {
    let latest = observations.map(\.capturedAt).max()
    if phase == .loadingCharactersAndConfiguration {
      return StartupDataStatusRow(
        area: .warehouseAndBlueprints,
        status: .running,
        timestamp: latest
      )
    }
    guard characterCount > 0,
      let state = combined(observations.map(\.freshness))
    else {
      return StartupDataStatusRow(
        area: .warehouseAndBlueprints,
        status: characterCount == 0 ? .known(.unavailable) : .waiting,
        timestamp: latest
      )
    }
    // Every character needs both an asset and a blueprint observation.
    let complete = observations.count >= characterCount * 2
    return StartupDataStatusRow(
      area: .warehouseAndBlueprints,
      status: .known(complete || state != .fresh ? state : .partial),
      timestamp: latest
    )
  }

  static func analysis(
    area: StartupDataArea,
    phase: StartupDataLoad.Phase,
    isRefreshing: Bool,
    marketStates: [DataFreshness]?,
    hasError: Bool,
    timestamp: Date?
  ) -> StartupDataStatusRow {
    let status: StartupDataStatus
    if isRefreshing {
      status = .running
    } else if let marketStates {
      let state = combined(marketStates) ?? .unavailable
      status = .known(hasError && state == .fresh ? .stale : state)
    } else if hasError {
      status = .known(.unavailable)
    } else if phase == .idle || phase == .loadingCharactersAndConfiguration {
      status = .waiting
    } else {
      status = .known(.unavailable)
    }
    return StartupDataStatusRow(area: area, status: status, timestamp: timestamp)
  }
}

/// Sources combined in the Dashboard header status (plan DB5).
enum DashboardSourceArea: String, CaseIterable, Identifiable, Sendable {
  case characters
  case wallets
  case netWorth
  case reactions
  case moonMaterials
  case minerals

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .characters: "Characters"
    case .wallets: "Wallets"
    case .netWorth: "Net Worth"
    case .reactions: "Reactions"
    case .moonMaterials: "Moon materials"
    case .minerals: "Minerals"
    }
  }

  var systemImage: String {
    switch self {
    case .characters: "person.2"
    case .wallets: "creditcard"
    case .netWorth: "chart.line.uptrend.xyaxis"
    case .reactions: "flask"
    case .moonMaterials: "moon"
    case .minerals: "cube"
    }
  }
}

struct DashboardSourceStatus: Identifiable, Equatable, Sendable {
  let area: DashboardSourceArea
  let status: StartupDataStatus
  /// Age of the area's data: its oldest relevant capture time.
  let timestamp: Date?

  var id: DashboardSourceArea { area }
}

struct DashboardStatusSummary: Equatable, Sendable {
  let status: StartupDataStatus
  /// Capture time of the oldest source with a known time.
  let oldestTimestamp: Date?
  let sources: [DashboardSourceStatus]
}

/// Content state of a Dashboard purchase panel (plan DB7, finding B7): no
/// analysis yet is not the same as an analysis made for older settings.
enum DashboardPurchasePanelState: Equatable {
  case current
  case noAnalysis
  case settingsChanged

  static func state(hasAnalysis: Bool, isCurrent: Bool) -> Self {
    if isCurrent { return .current }
    return hasAnalysis ? .settingsChanged : .noAnalysis
  }
}

/// Message under a character's wallet after a failed refresh (plan DB7,
/// finding B4). EVE errors use the same localized texts as the character
/// sync; anything else is a local failure. Never shows a raw error name.
@MainActor
enum DashboardWalletRefreshMessage {
  static func text(characterName: String, error: Error) -> String {
    let reason: String
    switch error {
    case is AuthError, is ESIError, is URLError:
      reason = EVEConnectionErrorText.message(for: error)
    default:
      reason = AppLocalization.text(
        "The wallet balance could not be updated locally."
      )
    }
    return "\(characterName): \(reason)"
  }
}

/// Pure projection of the Dashboard header status. It starts no work and
/// never turns missing data into a fresh state.
enum DashboardStatusProjector {
  /// Any running source makes the summary running. Otherwise known states
  /// combine with `StartupDataStatusProjector.combined`; a waiting source has
  /// no data yet and counts as unavailable unless every source waits.
  static func summary(_ sources: [DashboardSourceStatus]) -> DashboardStatusSummary {
    let status: StartupDataStatus
    if sources.contains(where: { $0.status == .running }) {
      status = .running
    } else if sources.isEmpty || sources.allSatisfy({ $0.status == .waiting }) {
      status = .waiting
    } else {
      let states: [DataFreshness] = sources.map {
        if case .known(let freshness) = $0.status { return freshness }
        return .unavailable
      }
      status = .known(StartupDataStatusProjector.combined(states) ?? .unavailable)
    }
    return DashboardStatusSummary(
      status: status,
      oldestTimestamp: sources.compactMap(\.timestamp).min(),
      sources: sources
    )
  }

  static func characters(
    phase: StartupDataLoad.Phase,
    isRefreshing: Bool,
    result: CharacterBatchSyncResult?,
    lastSyncDates: [Date?]
  ) -> DashboardSourceStatus {
    let row = StartupDataStatusProjector.characters(
      phase: phase,
      result: result,
      lastSyncDates: lastSyncDates
    )
    return DashboardSourceStatus(
      area: .characters,
      status: isRefreshing ? .running : row.status,
      timestamp: lastSyncDates.compactMap { $0 }.min()
    )
  }

  static func wallets(
    freshness: DataFreshness,
    characterCount: Int,
    isRefreshing: Bool,
    lastSyncDates: [Date?]
  ) -> DashboardSourceStatus {
    DashboardSourceStatus(
      area: .wallets,
      status: isRefreshing
        ? .running : .known(characterCount == 0 ? .unavailable : freshness),
      timestamp: lastSyncDates.compactMap { $0 }.min()
    )
  }

  /// A failed newer valuation keeps the previous one visible, so it is stale.
  static func netWorth(
    snapshot: DashboardWealthSnapshot?,
    isRefreshing: Bool,
    hasError: Bool
  ) -> DashboardSourceStatus {
    let status: StartupDataStatus
    if isRefreshing {
      status = .running
    } else if let snapshot {
      status = .known(
        hasError ? .stale : snapshot.isComplete ? snapshot.freshness : .partial
      )
    } else {
      status = .known(.unavailable)
    }
    return DashboardSourceStatus(
      area: .netWorth,
      status: status,
      timestamp: snapshot?.capturedAt
    )
  }

  static func analysis(_ row: StartupDataStatusRow) -> DashboardSourceStatus? {
    let area: DashboardSourceArea
    switch row.area {
    case .reactions: area = .reactions
    case .moonMaterials: area = .moonMaterials
    case .minerals: area = .minerals
    case .characters, .warehouseAndBlueprints: return nil
    }
    return DashboardSourceStatus(area: area, status: row.status, timestamp: row.timestamp)
  }
}

struct DashboardView: View {
  var onNavigate: (DashboardNavigationRequest) -> Void = { _ in }
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  // Only the Dashboard's own rows (industry jobs, wealth history): unrelated
  // settings writes neither reload their values nor re-render the view.
  @Query(
    filter: #Predicate<AppSetting> { $0.key.starts(with: "dashboard.") },
    sort: \AppSetting.key
  )
  private var settings: [AppSetting]
  @State private var blueprintNames: [Int64: String] = [:]
  @State private var industrySnapshot = DashboardIndustrySnapshot.empty
  @State private var wealthPersistenceError: String?
  @State private var isRefreshingDashboardData = false
  @State private var dashboardDataRefreshMessage: String?
  @State private var dashboardDataRefreshError: String?
  @State private var hasFinishedDashboardStartupRefresh = false
  @State private var refreshingWalletCharacterIDs: Set<Int64> = []
  @State private var walletRefreshErrors: [Int64: String] = [:]
  @State private var selectedDashboardWealthSeries: DashboardWealthSeries = .total
  /// History range of the net-worth panel for this view lifetime (plan DB3).
  @State private var selectedWealthRange: NetWorthHistoryRange = .thirty
  @State private var showsValuationDetailsPopover = false
  /// "Refresh all" in the header (plan DB5) and the last manual result.
  @State private var isRefreshingAll = false
  @State private var lastCharacterSyncResult: CharacterBatchSyncResult?
  @AppStorage("dashboard.capacity-by-activity-expanded", store: AppDefaults.store)
  private var capacityByActivityExpanded = false
  @State private var authorizationCache = DashboardAuthorizationCache()
  // Inputs and result of "Main Hub opportunities · Top 5" (plan DB2).
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]
  @Query(filter: #Predicate<StoredPlan> { $0.isActive })
  private var activePlans: [StoredPlan]
  @State private var mainHubTopFive: MainHubOpportunityTopFive?
  @State private var mainHubTopFiveSort = AppTableSortDescriptor<MainHubOpportunityTopColumn>(
    column: .returnOnInvestment,
    direction: .descending
  )
  @AppStorage("reactions.analysis-runs", store: AppDefaults.store)
  private var sharedReactionRuns = 100
  @AppStorage("reactions.market-hub-id", store: AppDefaults.store)
  private var sharedReactionHubID = ""
  private var wealthHistoryCache: DashboardWealthHistoryCache { .shared }
  var body: some View {
    ScrollView {
      // Arrangement of the Dashboard board `Main.dc.html` (plan DB1,
      // `Documentation/DASHBOARD_BOARD_2026-11-07.md`, section 4).
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
          .padding(.bottom, DesignTokens.spacingSM)
        // Only the job panels depend on the clock; the minute tick must not
        // re-render the finance and market panels.
        keyFigureRow
        TimelineView(.periodic(from: .now, by: 60)) { context in
          capacityByActivityPanel(now: context.date)
        }
        dashboardRow {
          TimelineView(.periodic(from: .now, by: 60)) { context in
            readyAndUpcomingJobsPanel(now: context.date)
          }
          walletPanel
        }
        dashboardRow {
          netWorthPanel
          mainHubOpportunitiesPanel
        }
        dashboardRow {
          TimelineView(.periodic(from: .now, by: 60)) { context in
            largestJobsPanel(now: context.date)
          }
          reactionOpportunityPanel
        }
        mineralTickerPanel
        dashboardRow {
          purchasePanel(kind: .moonMaterials)
          purchasePanel(kind: .minerals)
        }
      }
      .frame(maxWidth: 1_440, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text("Dashboard"))
    .task(id: dashboardIndustryRefreshIdentity) {
      let identity = dashboardIndustryRefreshIdentity
      let cache = DashboardIndustrySnapshotCache.shared
      // Returning to the Dashboard reuses the snapshot prepared for the same
      // inputs instead of decoding every job snapshot again.
      if let cached = cache.entry(for: identity) {
        industrySnapshot = cached.snapshot
        blueprintNames = cached.blueprintNames
        return
      }
      let inputs = dashboardIndustryInputs
      let prepared = await Task.detached(priority: .utility) {
        DashboardIndustrySnapshotBuilder.build(inputs: inputs)
      }.value
      guard !Task.isCancelled else { return }
      industrySnapshot = prepared
      let names = await runtime.resolveAssetTypeNames(prepared.jobTypeIDs)
      guard !Task.isCancelled else { return }
      blueprintNames = names
      cache.store(identity: identity, snapshot: prepared, blueprintNames: names)
    }
    .task(id: wealthInputIdentity) {
      guard hasFinishedDashboardStartupRefresh else { return }
      // A running full refresh values the portfolio itself once all
      // characters are synchronized, and a running valuation would discard
      // these inputs anyway; skip decoding every snapshot for nothing.
      guard !isRefreshingDashboardData, !runtime.isRefreshingDashboardWealth
      else { return }
      await runtime.refreshDashboardWealth(inputs: await loadWealthInputs())
      if runtime.dashboardWealthError == nil,
        let snapshot = runtime.dashboardWealthSnapshot
      {
        persistWealthSnapshot(snapshot)
      }
    }
    .task(id: mainHubAutomationIdentity) {
      runtime.prepareMainHubMarketAutomation()
    }
    // Same contract, Loyalty Store and invention inputs the Main-Hub
    // opportunity view loads for its costs (plan DB2).
    .task(id: mainHubReferenceTrigger) {
      guard let analysis = runtime.manufacturingOpportunityAnalysis else { return }
      await OpportunityAcquisitionInputs.loadContractReferences(
        runtime: runtime,
        analysis: analysis
      )
      guard !Task.isCancelled else { return }
      await OpportunityAcquisitionInputs.loadInventionEstimates(
        runtime: runtime,
        analysis: analysis
      )
    }
    .task(id: mainHubTopFiveTrigger) {
      let trigger = mainHubTopFiveTrigger
      guard let analysis = runtime.manufacturingOpportunityAnalysis else {
        mainHubTopFive = nil
        return
      }
      let cache = MainHubOpportunityTopFiveCache.shared
      if let cached = cache.result(for: trigger) {
        mainHubTopFive = cached
        return
      }
      guard
        let result = await MainHubOpportunityTopFiveProjection.prepare(
          runtime: runtime,
          snapshot: analysis,
          characters: characters,
          stockTargets: stockTargets,
          activePlans: activePlans,
          settings: trigger.settings
        ),
        !Task.isCancelled
      else { return }
      mainHubTopFive = result
      cache.store(result, for: trigger)
    }
    .task(id: marketRefreshIdentity) {
      runtime.rememberMarketAuthorizations(
        authorizationSnapshots,
        clientID: EVEConstants.ssoClientID
      )
      guard runtime.isPlannerConfigurationReady else { return }
      async let moon: Void = runtime.refreshMoonMaterialAnalysis(
        authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID)
      async let minerals: Void = runtime.refreshMineralPurchaseAnalysis(
        authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID)
      async let reactions: Void = runtime.refreshConfiguredReactions(
        authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID)
      _ = await (moon, minerals, reactions)
    }
    .task(id: dashboardStartupCharacterIdentity) {
      guard !characters.isEmpty else { return }
      guard runtime.reserveDashboardStartupRefresh() else {
        hasFinishedDashboardStartupRefresh = true
        return
      }
      await refreshDashboardData(isStartup: true)
      hasFinishedDashboardStartupRefresh = true
    }
  }

  /// One row of the board grid: two equal columns of at least 360 pt that
  /// share the row height and stack on narrow windows.
  private func dashboardRow<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    DashboardCardLayout(
      weights: [1, 1],
      minimumWidths: [360, 360],
      equalizesHeights: true
    ) {
      content()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .bottom, spacing: DesignTokens.spacingMD) {
          headerTitle
          Spacer(minLength: DesignTokens.spacingMD)
          headerControls
        }
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          headerTitle
          headerControls
        }
      }
      refreshMessages
    }
  }

  private var headerTitle: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Dashboard")
        .appFont(.largeTitle.bold())
        .nexusPageTitle()
      Text("Jobs, wallets, wealth and market at a glance.")
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  /// ESI status and "Refresh all" on the right of the header (plan DB5).
  private var headerControls: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      DashboardHeaderStatusButton(
        startupLoad: runtime.startupDataLoad,
        inputs: headerStatusInputs
      )
      Button {
        Task { await refreshAll() }
      } label: {
        HStack(spacing: DesignTokens.spacingXS) {
          if isRefreshingAll || isRefreshingDashboardData {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
          Text(isRefreshingAll || isRefreshingDashboardData ? "Updating…" : "Refresh all")
        }
      }
      .buttonStyle(.bordered)
      .disabled(
        isRefreshingAll
          || isRefreshingDashboardData
          || !refreshingWalletCharacterIDs.isEmpty
          || clientID.isEmpty
          || characters.isEmpty
      )
      .accessibilityIdentifier("dashboard.refresh")
    }
  }

  @ViewBuilder private var refreshMessages: some View {
    if let dashboardDataRefreshMessage {
      Label(dashboardDataRefreshMessage, systemImage: "checkmark.circle.fill")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.positive)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("dashboard.refresh.message")
    }
    if let dashboardDataRefreshError {
      Label(dashboardDataRefreshError, systemImage: "exclamationmark.triangle.fill")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.caution)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("dashboard.refresh.error")
    }
  }

  private var headerStatusInputs: DashboardHeaderStatusButton.Inputs {
    DashboardHeaderStatusButton.Inputs(
      isRefreshingCharacters: isRefreshingDashboardData,
      characterResult: lastCharacterSyncResult,
      lastSyncDates: characters.map(\.lastSyncAt),
      walletFreshness: walletPortfolio.freshness,
      characterCount: characters.count,
      isRefreshingWallets: isRefreshingDashboardData || !refreshingWalletCharacterIDs.isEmpty,
      walletSyncDates: characters.map(\.walletLastSyncAt),
      wealthSnapshot: runtime.dashboardWealthSnapshot,
      isRefreshingWealth: runtime.isRefreshingDashboardWealth,
      wealthHasError: runtime.dashboardWealthError != nil,
      isAnalyzingReactions: runtime.isAnalyzingReactions,
      reactionMarketStates: runtime.reactionAnalysis.map { _ in [.fresh] },
      reactionHasError: runtime.reactionAnalysisError != nil,
      reactionTimestamp: runtime.reactionAnalysis?.createdAt,
      isRefreshingMoon: runtime.isRefreshingMoonMaterialAnalysis,
      moonMarketStates: runtime.moonMaterialAnalysis.map {
        $0.configuredMarkets.values.map(\.state)
      },
      moonHasError: runtime.moonMaterialAnalysisError != nil,
      moonTimestamp: runtime.moonMaterialAnalysis?.refreshedAt,
      isRefreshingMinerals: runtime.isRefreshingMineralPurchaseAnalysis,
      mineralMarketStates: runtime.mineralPurchaseAnalysis.map {
        $0.configuredMarkets.values.map(\.state)
      },
      mineralHasError: runtime.mineralPurchaseAnalysisError != nil,
      mineralTimestamp: runtime.mineralPurchaseAnalysis?.refreshedAt
    )
  }

  /// The former Dashboard refresh, then the Moon, Mineral and Reaction
  /// analyses together, as the Dashboard starts them on appearance.
  private func refreshAll() async {
    guard !isRefreshingAll else { return }
    isRefreshingAll = true
    defer { isRefreshingAll = false }
    await refreshDashboardData(isStartup: false)
    guard !Task.isCancelled else { return }
    let authorizations = authorizationSnapshots
    async let moon: Void = runtime.refreshMoonMaterialAnalysis(
      authorizations: authorizations, clientID: EVEConstants.ssoClientID)
    async let minerals: Void = runtime.refreshMineralPurchaseAnalysis(
      authorizations: authorizations, clientID: EVEConstants.ssoClientID)
    async let reactions: Void = runtime.refreshConfiguredReactions(
      authorizations: authorizations, clientID: EVEConstants.ssoClientID)
    _ = await (moon, minerals, reactions)
  }

  private var mineralTickerPanel: some View {
    Panel(title: "Mineral prices") {
      HStack {
        Text("Purchase prices from the mineral analysis")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if runtime.isRefreshingMineralPurchaseAnalysis {
          ProgressView().controlSize(.small)
        }
        // Same order as the purchase panels: open, then refresh (DB7, B8).
        Button("Open purchase analysis") {
          onNavigate(DashboardNavigationRequest(section: .mineralPurchaseAnalysis))
        }.buttonStyle(.borderless)
        Button {
          Task { await runtime.refreshMineralPurchaseAnalysis(
            authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID) }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(runtime.isRefreshingMineralPurchaseAnalysis)
        .help("Refresh mineral prices")
        .accessibilityLabel("Refresh mineral prices")
      }
      if runtime.hasCurrentMineralPurchaseAnalysis, !runtime.mineralPurchaseRecommendations.isEmpty {
        DashboardMineralTicker(rows: runtime.mineralPurchaseRecommendations)
          .frame(height: 62)
        if runtime.mineralPurchaseRecommendations.contains(where: { !$0.hasCompleteMarketCoverage }) {
          Text("Some configured markets are unavailable or stale; the comparison is incomplete.")
            .appFont(.caption).foregroundStyle(DesignTokens.caution)
        }
      } else {
        Label(
          "No current mineral purchase analysis is available.",
          systemImage: "chart.line.downtrend.xyaxis"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      if let error = runtime.mineralPurchaseAnalysisError {
        Text(error.localizedUI).appFont(.caption).foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private var marketRefreshIdentity: String {
    let authorizations = authorizationSnapshots.map {
      "\($0.id):\($0.authorizedAt.timeIntervalSince1970):\($0.scopes.sorted().joined(separator: ","))"
    }.sorted().joined(separator: "|")
    return runtime.marketAnalysisContextIdentity + "#\(runtime.isPlannerConfigurationReady)#\(sharedReactionRuns)#\(sharedReactionHubID)#" + authorizations
  }

  private var mainHubReferenceTrigger: [String] {
    [
      runtime.manufacturingOpportunityAnalysis?.id.uuidString ?? "none",
      (runtime.publicContractRegionScope?.sorted() ?? []).map(String.init)
        .joined(separator: ","),
      runtime.loyaltyStoreCatalog?.id.uuidString ?? "none",
    ]
  }

  private var mainHubTopFiveTrigger: MainHubOpportunityTopFiveTrigger {
    MainHubOpportunityTopFiveTrigger.current(
      runtime: runtime,
      characters: characters,
      stockTargets: stockTargets,
      activePlans: activePlans,
      settings: .mainHub(from: AppDefaults.store)
    )
  }

  private var mainHubOpportunitiesPanel: some View {
    let analysis = runtime.manufacturingOpportunityAnalysis
    let result = mainHubTopFive.flatMap {
      $0.analysisID == analysis?.id ? $0 : nil
    }
    return Panel(title: "Main Hub opportunities · Top 5", fillsAvailableHeight: true) {
      HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingXS) {
        if let analysis {
          Image(systemName: "building.columns")
            .foregroundStyle(DesignTokens.textSecondary)
            .accessibilityHidden(true)
          EVEEntityText(value: analysis.mainHub.name, font: .caption, lineLimit: 1)
          Text(
            AppLocalization.format(
              "Updated %@",
              analysis.marketSource.capturedAt.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLocalization.currentLanguage.locale)
              )
            )
          )
          .monospacedDigit()
          .foregroundStyle(DesignTokens.textSecondary)
          .lineLimit(1)
        }
        Spacer(minLength: DesignTokens.spacingSM)
        Button {
          onNavigate(DashboardNavigationRequest(section: .manufacturingOpportunities))
        } label: {
          HStack(spacing: 2) {
            Text("All opportunities")
            Image(systemName: "chevron.right").appFont(.caption2.bold())
          }
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("dashboard.main-hub-opportunities.open")
      }
      .appFont(.caption)
      if analysis == nil {
        Label("No Main Hub scan yet", systemImage: "chart.line.uptrend.xyaxis")
          .foregroundStyle(DesignTokens.textSecondary)
        if let error = runtime.manufacturingOpportunitySnapshotError {
          Text(error.localizedUI).appFont(.caption).foregroundStyle(DesignTokens.caution)
        }
      } else if let result {
        if result.rows.isEmpty {
          Label(
            result.visibleCount == 0
              ? "No opportunity matches the filters of the Main Hub opportunities."
              : "No visible opportunity has an available ROI.",
            systemImage: "line.3.horizontal.decrease.circle"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        } else {
          mainHubOpportunityTable(result.rows)
        }
      } else {
        Label("Preparing", systemImage: "hourglass")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func mainHubOpportunityTable(
    _ rows: [MainHubOpportunityTopRow]
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: DesignTokens.spacingSM) {
        SortableTableHeader(
          title: "Product",
          column: MainHubOpportunityTopColumn.product,
          sort: $mainHubTopFiveSort
        )
        SortableTableHeader(
          title: "ROI",
          column: .returnOnInvestment,
          sort: $mainHubTopFiveSort,
          defaultDirection: .descending,
          alignment: .trailing
        )
        .frame(width: 72)
        SortableTableHeader(
          title: "Profit",
          column: .profit,
          sort: $mainHubTopFiveSort,
          defaultDirection: .descending,
          alignment: .trailing
        )
        .frame(width: 150)
      }
      .appFont(.caption.weight(.semibold))
      .foregroundStyle(DesignTokens.textSecondary)
      .padding(.bottom, DesignTokens.spacingXS)
      .overlay(alignment: .bottom) {
        Rectangle().fill(DesignTokens.border).frame(height: 1)
      }
      ForEach(MainHubOpportunityTopSelection.sorted(rows, by: mainHubTopFiveSort)) { row in
        HStack(spacing: DesignTokens.spacingSM) {
          EVEItemText(
            value: row.productName,
            typeID: row.productTypeID,
            font: .callout.weight(.semibold),
            lineLimit: 1
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          Text(OpportunityValueFormat.percent(row.returnOnInvestment))
            .monospacedDigit()
            .frame(width: 72, alignment: .trailing)
          Text(OpportunityValueFormat.isk(row.profit))
            .appFont(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(
              row.profit == nil ? DesignTokens.textSecondary : DesignTokens.highlight
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.spacingSM)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(DesignTokens.border.opacity(0.4))
            .frame(height: 1)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
      }
    }
    .accessibilityIdentifier("dashboard.main-hub-opportunities.table")
  }

  private func purchasePanel(kind: MaterialPurchaseAnalysisKind) -> some View {
    let moon = kind == .moonMaterials
    let current = moon ? runtime.hasCurrentMoonMaterialAnalysis : runtime.hasCurrentMineralPurchaseAnalysis
    let rows = moon ? runtime.moonMaterialRecommendations : runtime.mineralPurchaseRecommendations
    let refreshing = moon ? runtime.isRefreshingMoonMaterialAnalysis : runtime.isRefreshingMineralPurchaseAnalysis
    let error = moon ? runtime.moonMaterialAnalysisError : runtime.mineralPurchaseAnalysisError
    return Panel(title: kind.title, fillsAvailableHeight: true) {
      HStack {
        if refreshing { ProgressView().controlSize(.small) }
        Spacer()
        Button("Open purchase analysis") {
          onNavigate(DashboardNavigationRequest(section: moon ? .moonMaterialAnalysis : .mineralPurchaseAnalysis))
        }.buttonStyle(.borderless)
        Button {
          Task {
            if moon {
              await runtime.refreshMoonMaterialAnalysis(authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID)
            } else {
              await runtime.refreshMineralPurchaseAnalysis(authorizations: authorizationSnapshots, clientID: EVEConstants.ssoClientID)
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }.buttonStyle(.borderless).disabled(refreshing)
          .help("Refresh purchase analysis")
          .accessibilityLabel("Refresh purchase analysis")
      }
      let hasAnalysis =
        moon ? runtime.moonMaterialAnalysis != nil : runtime.mineralPurchaseAnalysis != nil
      switch DashboardPurchasePanelState.state(hasAnalysis: hasAnalysis, isCurrent: current) {
      case .current:
        MaterialPurchaseRecommendationContent(recommendations: rows)
      case .noAnalysis:
        Text(
          moon
            ? LocalizedStringKey("No Moon purchase analysis yet")
            : LocalizedStringKey("No mineral purchase analysis yet")
        )
        .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
      case .settingsChanged:
        Text("Settings changed. Refresh to update purchase locations.")
          .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
      }
      if let error {
        Text(error.localizedUI).appFont(.caption).foregroundStyle(DesignTokens.caution)
      }
    }
  }

  // MARK: Key figures (plan DB4)

  /// Four key-figure cards like the board; two per row, then one per row,
  /// when the window is narrow.
  private var keyFigureRow: some View {
    ViewThatFits(in: .horizontal) {
      DashboardCardLayout(
        weights: [1, 1, 1, 1],
        minimumWidths: [230, 230, 230, 230],
        equalizesHeights: true
      ) {
        netWorthKeyFigure
        walletKeyFigure
        manufacturingSlotKeyFigure
        scienceSlotKeyFigure
      }
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        DashboardCardLayout(
          weights: [1, 1],
          minimumWidths: [230, 230],
          equalizesHeights: true
        ) {
          netWorthKeyFigure
          walletKeyFigure
        }
        DashboardCardLayout(
          weights: [1, 1],
          minimumWidths: [230, 230],
          equalizesHeights: true
        ) {
          manufacturingSlotKeyFigure
          scienceSlotKeyFigure
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.key-figures")
  }

  private func keyFigureValue(
    _ value: String,
    color: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(value)
      .appFont(.title3.weight(.bold).monospacedDigit())
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  }

  private var netWorthKeyFigure: some View {
    let hasTotal = runtime.dashboardWealthSnapshot?.knownTotalValue != nil
    let change = NetWorthRangeChange.change(
      in: selectedWealthRange.filter(wealthHistory)
    )
    return Panel(title: "Net Worth", fillsAvailableHeight: true) {
      keyFigureValue(
        wealthTotalText,
        color: hasTotal ? DesignTokens.highlight : DesignTokens.textSecondary
      )
      if let change {
        let amount =
          change.relative.map(NetWorthValueFormat.signedPercent)
          ?? NetWorthValueFormat.signedISK(change.absolute)
        Label(
          AppLocalization.format("%@ in range", amount),
          systemImage: change.absolute >= 0 ? "arrow.up.right" : "arrow.down.right"
        )
        .appFont(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(
          change.absolute >= 0 ? DesignTokens.positive : DesignTokens.negative
        )
        if change.comparesKnownComponentsOnly {
          Text("from known components")
            .appFont(.caption2)
            .foregroundStyle(DesignTokens.caution)
        }
      } else {
        Text("Change in range unavailable")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .overlay(alignment: .topTrailing) {
      Button {
        showsValuationDetailsPopover.toggle()
      } label: {
        Image(systemName: "info.circle")
      }
      .buttonStyle(.borderless)
      .help("How net worth is calculated")
      .accessibilityLabel("How net worth is calculated")
      .accessibilityIdentifier("dashboard.key-figure.net-worth.info")
      .padding(DesignTokens.spacingMD)
      .popover(isPresented: $showsValuationDetailsPopover, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Text("Valuation details").appFont(.headline)
          valuationDetailsText
        }
        .padding(DesignTokens.spacingMD)
        .frame(width: 380)
        .appLanguageLocale()
      }
    }
    // Keep inner elements (such as the info button) addressable (DB7, B2).
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.key-figure.net-worth")
  }

  private var walletKeyFigure: some View {
    let portfolio = walletPortfolio
    let hasBalance = portfolio.includedCharacterCount > 0
    return Panel(title: "Wallet", fillsAvailableHeight: true) {
      keyFigureValue(
        hasBalance
          ? formatISK(portfolio.totalBalance) : AppLocalization.text("Unavailable"),
        color: hasBalance ? DesignTokens.highlight : DesignTokens.textSecondary
      )
      if characters.isEmpty {
        Text("No connected characters")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        HStack(spacing: DesignTokens.spacingXS) {
          freshnessPill(portfolio.freshness)
          Text(
            AppLocalization.format(
              "%lld of %lld characters included",
              Int64(portfolio.includedCharacterCount),
              Int64(portfolio.totalCharacterCount)
            )
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          .lineLimit(2)
          // Wrap instead of truncating in narrow windows (DB7, B9).
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.key-figure.wallet")
  }

  /// Only the slot cards follow the minute tick; the finance cards do not.
  private var manufacturingSlotKeyFigure: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      manufacturingSlotKeyFigure(now: context.date)
    }
  }

  private var scienceSlotKeyFigure: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      scienceSlotKeyFigure(now: context.date)
    }
  }

  private func manufacturingSlotKeyFigure(now: Date) -> some View {
    let figure = DashboardSlotFigure.figure(
      jobs: industrySnapshot.jobs,
      activities: [.manufacturing],
      capacity: industrySnapshot.capacity(for: .manufacturing),
      now: now
    )
    return Panel(title: "Manufacturing slots", fillsAvailableHeight: true) {
      slotFigureContent(figure)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.key-figure.manufacturing-slots")
  }

  private func scienceSlotKeyFigure(now: Date) -> some View {
    let science = DashboardSlotFigure.figure(
      jobs: industrySnapshot.jobs,
      activities: Set(DashboardIndustryActivity.allCases.filter(\.usesSharedScienceSlots)),
      capacity: industrySnapshot.capacity(for: .copying),
      now: now
    )
    let reactions = DashboardSlotFigure.figure(
      jobs: industrySnapshot.jobs,
      activities: [.reaction],
      capacity: industrySnapshot.capacity(for: .reaction),
      now: now
    )
    return Panel(title: "Science slots (shared)", fillsAvailableHeight: true) {
      slotFigureContent(science)
      Text(
        AppLocalization.format(
          "Reactions %@ / %@",
          String(reactions.occupied),
          capacityText(reactions.capacity)
        )
      )
      .appFont(.caption.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.key-figure.science-slots")
  }

  @ViewBuilder private func slotFigureContent(
    _ figure: DashboardSlotFigure
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      keyFigureValue(String(figure.occupied))
      Text(verbatim: "/ \(capacityText(figure.capacity))")
        .appFont(.callout.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
    }
    if let fraction = figure.fillFraction {
      ProgressView(value: fraction)
        .tint(DesignTokens.accent)
        .accessibilityHidden(true)
    }
    Text(
      AppLocalization.format(
        "%lld ready · %@ free",
        Int64(figure.ready),
        figure.free.map {
          figure.capacity.isComplete ? String($0) : "≥\($0)"
        } ?? "—"
      )
    )
    .appFont(.caption.monospacedDigit())
    .foregroundStyle(DesignTokens.textSecondary)
  }

  /// Per-activity capacity grid below the key figures; its header keeps the
  /// overall "X of Y available job slots active" line (plan DB4).
  private func capacityByActivityPanel(now: Date) -> some View {
    let running = industrySnapshot.jobs.filter { $0.job.isRunning(at: now) }
    let overall = industrySnapshot.overallCapacity
    return VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      FullWidthDisclosureButton(
        isExpanded: capacityByActivityExpanded,
        action: { capacityByActivityExpanded.toggle() }
      ) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingSM) {
            NexusPanelTitle("Capacity by activity")
            Spacer(minLength: DesignTokens.spacingSM)
            capacityOverallLine(running: running.count, overall: overall)
          }
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            NexusPanelTitle("Capacity by activity")
            capacityOverallLine(running: running.count, overall: overall)
          }
        }
      }
      .accessibilityIdentifier("dashboard.capacity-by-activity")
      if capacityByActivityExpanded {
        ViewThatFits(in: .horizontal) {
          industryCapacityGrid(running: running, columnCount: 3)
            .frame(minWidth: 744)
          industryCapacityGrid(running: running, columnCount: 2)
            .frame(minWidth: 496)
          industryCapacityGrid(running: running, columnCount: 1)
        }
        jobDataNotice
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(DesignTokens.spacingMD)
    .nexusPanelSurface(.standard)
  }

  private func capacityOverallLine(
    running: Int,
    overall: DashboardIndustryCapacitySummary
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingXS) {
      Text(verbatim: String(running))
        .appFont(.callout.bold().monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
      Text("of")
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: capacityText(overall))
        .appFont(.callout.bold().monospacedDigit())
      Text("available job slots active")
        .foregroundStyle(DesignTokens.textSecondary)
      if !overall.isComplete {
        freshnessPill(.partial, text: "Partial")
      }
    }
    .appFont(.callout)
  }

  private func industryCapacityGrid(
    running: [DashboardIndustryOwnedJob],
    columnCount: Int
  ) -> some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(
          .flexible(minimum: 240),
          spacing: DesignTokens.spacingSM,
          alignment: .top
        ),
        count: columnCount
      ),
      spacing: DesignTokens.spacingSM
    ) {
      ForEach(DashboardIndustryActivity.allCases) { activity in
        let activityRunning = running.filter {
          $0.job.dashboardActivity == activity
        }.count
        let capacity = industrySnapshot.capacity(for: activity)
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Label(activityTitle(activity), systemImage: activityIcon(activity))
            .appFont(.caption.weight(.semibold))
            .lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(activityRunning)")
              .appFont(.title2.bold().monospacedDigit())
            Text("/ \(capacityText(capacity))")
              .appFont(.callout.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
          if activity.usesSharedScienceSlots {
            Text("Shared science slots")
              .appFont(.caption2)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .padding(DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
      }
    }
  }

  private var walletPanel: some View {
    let walletPortfolio = walletPortfolio
    return Panel(title: "Wallets", fillsAvailableHeight: true) {
      if characters.isEmpty {
        AppUnavailableView(
          "No connected characters",
          systemImage: "creditcard",
          description: Text(
            "Add a character under Characters before refreshing wallet balances."
          )
        )
      } else {
        // Three tiles like the board; they stack when the panel is narrow.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: DesignTokens.spacingSM) {
            walletTiles(walletPortfolio)
          }
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            walletTiles(walletPortfolio)
          }
        }
        DisclosureGroup("Character balances") {
            ForEach(walletPortfolio.balances) { row in
              dashboardWalletRow(row)
            }
        }
        if clientID.isEmpty {
          Label(
            "Save the EVE application client ID in Data & Settings before refreshing.",
            systemImage: "exclamationmark.triangle"
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        if walletPortfolio.includedCharacterCount < walletPortfolio.totalCharacterCount {
          Text("Missing or forbidden balances are not treated as zero.")
            .appFont(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  @ViewBuilder private func walletTiles(
    _ portfolio: WalletPortfolioSnapshot
  ) -> some View {
    let hasBalance = portfolio.includedCharacterCount > 0
    walletTile(title: "Available total") {
      Text(
        hasBalance
          ? formatISK(portfolio.totalBalance)
          : AppLocalization.text("Unavailable")
      )
      .appFont(.callout.weight(.bold).monospacedDigit())
      .lineLimit(1)
      .foregroundStyle(
        hasBalance ? DesignTokens.highlight : DesignTokens.textSecondary
      )
    }
    walletTile(title: "Characters") {
      Text(
        verbatim:
          "\(portfolio.includedCharacterCount) / \(portfolio.totalCharacterCount)"
      )
      .appFont(.callout.weight(.bold).monospacedDigit())
      .accessibilityLabel(
        AppLocalization.format(
          "%lld of %lld characters included",
          Int64(portfolio.includedCharacterCount),
          Int64(portfolio.totalCharacterCount)
        )
      )
    }
    walletTile(title: "Source state") {
      freshnessPill(portfolio.freshness)
    }
  }

  private func walletTile<Value: View>(
    title: LocalizedStringKey,
    @ViewBuilder value: () -> Value
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .appFont(.caption2.weight(.semibold))
        .foregroundStyle(DesignTokens.textSecondary)
        .lineLimit(1)
      value()
    }
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    .accessibilityElement(children: .combine)
  }

  private func dashboardWalletRow(
    _ row: CharacterWalletBalance
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      HStack(spacing: DesignTokens.spacingSM) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          EVEEntityText(
            value: row.character.name,
            font: .callout.weight(.semibold)
          )
          if let updatedAt = lastWalletSync(for: row.id) {
            Text("Updated \(updatedAt.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: AppLocalization.currentLanguage.locale)))")
              .appFont(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          } else {
            Text("Not synchronized")
              .appFont(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        Spacer()
        VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
          Text(
            row.balance.value.map(formatISK)
              ?? AppLocalization.text("Unavailable")
          )
          .appFont(.callout.weight(.semibold).monospacedDigit())
          .foregroundStyle(
            row.balance.value == nil
              ? DesignTokens.textSecondary : DesignTokens.textPrimary
          )
          freshnessPill(row.balance.state)
        }
        Button {
          guard
            let character = characters.first(
              where: { $0.characterID == row.id }
            )
          else { return }
          Task { await refreshWallet(for: character) }
        } label: {
          if refreshingWalletCharacterIDs.contains(row.id) {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .buttonStyle(.bordered)
        .disabled(
          clientID.isEmpty
            || isRefreshingDashboardData
            || refreshingWalletCharacterIDs.contains(row.id)
        )
        .help("Refresh \(row.character.name)'s wallet")
        .accessibilityLabel("Refresh \(row.character.name)'s wallet")
        .accessibilityIdentifier("dashboard.wallet.refresh.\(row.id)")
      }
      if let message = walletRefreshErrors[row.id] {
        Label(message, systemImage: "xmark.octagon.fill")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.wallet.character.\(row.id)")
  }

  private func readyAndUpcomingJobsPanel(now: Date) -> some View {
    let rows = DashboardReadyAndUpcomingJobs.rows(
      jobs: industrySnapshot.jobs,
      now: now
    )
    return Panel(
      title: "Industry jobs · ready and upcoming",
      fillsAvailableHeight: true
    ) {
      if isPreparingIndustrySnapshot {
        Label("Preparing", systemImage: "hourglass")
          .foregroundStyle(DesignTokens.textSecondary)
      } else if !industrySnapshot.hasAnyJobSnapshot {
        Label(
          "Synchronize characters to load industry jobs.",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else if rows.isEmpty {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Label(
            "No jobs are currently ready for delivery.",
            systemImage: "checkmark.circle"
          )
          Label(
            "No running jobs finish within the next 48 hours.",
            systemImage: "clock"
          )
        }
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        DashboardPreviewList(rows: rows, showsSeparators: true) { row in
          dashboardJobRow(row.owned, isReady: row.isReady)
        }
      }
    }
  }

  private func largestJobsPanel(now: Date) -> some View {
    let currentIDs = Set(industrySnapshot.jobs.filter {
      !$0.job.isDelivered && !$0.job.isCancelledOrReverted
        && ($0.job.dashboardActivity == .manufacturing || $0.job.dashboardActivity == .reaction)
    }.map(\.id))
    let values = runtime.dashboardIndustryJobValues.filter { currentIDs.contains($0.id) }
    let ranked = DashboardInProgressIndustryProjector.rankedJobs(values)
    let missingCount = currentIDs.count - ranked.count
    return Panel(title: "Top 5 by material value", fillsAvailableHeight: true) {
      if runtime.isRefreshingDashboardWealth {
        ProgressView().controlSize(.small)
      }
      ForEach(Array(ranked.prefix(5))) { row in
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          if let productID = row.ownedJob.job.productTypeID,
            let name = runtime.dashboardIndustryProductNames[productID]
          {
            EVEItemText(value: name, typeID: productID, font: .callout.weight(.semibold))
          } else {
            Text("Product name unavailable").foregroundStyle(DesignTokens.textSecondary)
          }
          EVEEntityText(value: row.ownedJob.characterName, font: .caption)
          HStack {
            Text((row.ownedJob.job.isReadyForDelivery(at: now) ? "Ready" :
              row.ownedJob.job.isRunning(at: now) ? "Running" : "Paused").localizedUI)
            Spacer()
            Text(row.materialValue.map(formatISK) ?? AppLocalization.text("Unavailable"))
              .monospacedDigit()
          }.appFont(.caption)
          if row.freshness != .fresh { freshnessPill(row.freshness) }
        }
      }
      if missingCount > 0 {
        Text(AppLocalization.format("Incomplete ranking · %lld jobs without full material valuation", Int64(missingCount)))
          .appFont(.caption).foregroundStyle(DesignTokens.caution)
      } else if ranked.isEmpty {
        Text(industrySnapshot.hasAnyJobSnapshot
          ? "No open production jobs.".localizedUI
          : "Synchronize characters to load industry jobs.".localizedUI)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if industrySnapshot.incompleteJobSourceCount > 0 {
        Text("Some character job data is incomplete; ranking may omit jobs.")
          .appFont(.caption).foregroundStyle(DesignTokens.caution)
      }
      if !ranked.isEmpty {
        Text("Estimated material value · ESI average / adjusted prices")
          .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
      }
      if let error = runtime.dashboardWealthError {
        Text(error.localizedUI).appFont(.caption).foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private var reactionOpportunityPanel: some View {
    let filteredNegativeReactions = filteredNegativeReactions
    return Panel(
      title: "Reactions with negative value creation",
      fillsAvailableHeight: true
    ) {
      HStack {
        Text("Negative value creation means buying is cheaper than reacting.")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        Button("Open reactions") {
          onNavigate(DashboardNavigationRequest(section: .reactions, negativeReactionsOnly: true))
        }.buttonStyle(.borderless)
      }
      if runtime.isAnalyzingReactions {
        HStack {
          ProgressView().controlSize(.small)
          Text("Analyzing all reactions…")
        }
      }
      if let error = runtime.reactionAnalysisError {
        Text(error.localizedUI).appFont(.caption).foregroundStyle(DesignTokens.caution)
      }
      if runtime.reactionAnalysis == nil || !runtime.isReactionAnalysisCurrent {
        Label(
          runtime.reactionAnalysis == nil ? "No reaction analysis is loaded.".localizedUI : "Settings changed. Refresh to update reactions.".localizedUI,
          systemImage: "atom"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Button("Analyze all reactions") {
          Task {
            await runtime.refreshConfiguredReactions(
              authorizations: authorizationSnapshots,
              clientID: EVEConstants.ssoClientID
            )
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(runtime.isAnalyzingReactions)
      } else if filteredNegativeReactions.isEmpty {
        Label(
          "No reactions have negative value creation.",
          systemImage: "checkmark.circle"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        if let analysis = runtime.reactionAnalysis {
          HStack {
            Text("Purchase market")
            EVEEntityText(value: analysis.marketLocation.name, font: .caption)
            Image(systemName: "arrow.right")
            if let destination = runtime.reactionAnalysisDestinationName,
              !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
              EVEEntityText(value: destination, font: .caption)
            } else {
              Text("Production destination unavailable")
            }
          }.appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
          Text(AppLocalization.format("%lld runs · %@", Int64(analysis.runs), analysis.createdAt.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: AppLocalization.currentLanguage.locale))))
            .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
          if analysis.basis == .materialOnlyBaseline {
            Text("Material-only baseline").appFont(.caption).foregroundStyle(DesignTokens.caution)
          }
        }
        DashboardPreviewList(
          rows: filteredNegativeReactions,
          showsSeparators: true
        ) { row in
          HStack {
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              EVEItemText(
                value: row.productName,
                typeID: row.productTypeID,
                font: .callout.weight(.semibold)
              )
              Text(row.groupName)
                .appFont(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
              Text("Buy opportunity")
                .appFont(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.positive)
              Text(
                row.valueCreation.map(formatISK)
                  ?? AppLocalization.text("Unavailable")
              )
              .appFont(.callout.monospacedDigit())
            }
          }
        }
      }
    }
  }

  private var netWorthPanel: some View {
    let rangeHistory = selectedWealthRange.filter(wealthHistory)
    return Panel(title: "Net worth · history", fillsAvailableHeight: true) {
      HStack(alignment: .firstTextBaseline) {
        Text(wealthTotalText)
          .appFont(.title2.weight(.semibold).monospacedDigit())
          .foregroundStyle(DesignTokens.highlight)
        Spacer()
        if runtime.isRefreshingDashboardWealth {
          ProgressView().controlSize(.small)
        } else if let snapshot = runtime.dashboardWealthSnapshot {
          freshnessPill(
            snapshot.isComplete ? snapshot.freshness : .partial,
            text: snapshot.isComplete && snapshot.freshness == .fresh
              ? "Complete" : snapshot.isComplete ? nil : "Known components"
          )
        }
      }
      if !wealthHistory.isEmpty {
        let change = NetWorthRangeChange.change(in: rangeHistory)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingSM) {
            wealthRangeChangeLabel(change)
            Spacer(minLength: DesignTokens.spacingSM)
            wealthRangePicker
          }
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            wealthRangeChangeLabel(change)
            wealthRangePicker
          }
        }
        ViewThatFits(in: .horizontal) {
          wealthSeriesPicker.menuStyle(.borderlessButton).pickerStyle(.segmented).frame(minWidth: 480)
          wealthSeriesPicker.pickerStyle(.menu)
        }
        let seriesSamples = selectedDashboardWealthSeries.samples(in: rangeHistory)
        let seriesTitle = AppLocalization.text(selectedDashboardWealthSeries.titleKey)
        if seriesSamples.isEmpty {
          // An explicit state instead of an empty chart (DB7, B6).
          Label(
            AppLocalization.format("No values for “%@” in the selected range.", seriesTitle),
            systemImage: "chart.line.flattrend.xyaxis"
          )
          .appFont(.callout)
          .foregroundStyle(DesignTokens.textSecondary)
          .frame(maxWidth: .infinity, minHeight: 280)
          .accessibilityIdentifier("dashboard.wealth-series.empty")
        } else {
          DashboardWealthChart(
            samples: seriesSamples,
            color: selectedDashboardWealthSeries.color,
            showsAxes: true
          )
          .frame(height: 280)
          .accessibilityLabel(AppLocalization.format("Net-worth history: %@", seriesTitle))
        }
      } else {
        Label("Long-term history starts with the current valuation.", systemImage: "clock.arrow.circlepath")
          .appFont(.caption).foregroundStyle(DesignTokens.textSecondary)
      }
      netWorthDetails
    }
  }

  private var wealthRangePicker: some View {
    Picker("History range", selection: $selectedWealthRange) {
      ForEach(NetWorthHistoryRange.allCases) { range in
        Text(range.title).tag(range)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
    .accessibilityIdentifier("dashboard.wealth-range")
  }

  /// Change of the known total inside the selected range (plan DB3).
  @ViewBuilder private func wealthRangeChangeLabel(
    _ change: NetWorthRangeChange?
  ) -> some View {
    if let change {
      let amount = NetWorthValueFormat.signedISK(change.absolute)
      VStack(alignment: .leading, spacing: 2) {
        Label(
          change.relative.map {
            AppLocalization.format(
              "%@ · %@ in range",
              amount,
              NetWorthValueFormat.signedPercent($0)
            )
          } ?? AppLocalization.format("%@ in range", amount),
          systemImage: change.absolute >= 0 ? "arrow.up.right" : "arrow.down.right"
        )
        .appFont(.callout.weight(.semibold).monospacedDigit())
        .foregroundStyle(
          change.absolute >= 0 ? DesignTokens.positive : DesignTokens.negative
        )
        if change.comparesKnownComponentsOnly {
          Text("from known components")
            .appFont(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("dashboard.wealth-range-change")
    } else {
      Text("Change in range unavailable")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .accessibilityIdentifier("dashboard.wealth-range-change")
    }
  }

  private var wealthSeriesPicker: some View {
        Picker("Displayed history", selection: $selectedDashboardWealthSeries) {
          ForEach(DashboardWealthSeries.allCases) { series in
            Text(series.title).tag(series)
          }
        }
        .accessibilityIdentifier("dashboard.wealth-series")
  }

  @ViewBuilder private var netWorthDetails: some View {
      if let snapshot = runtime.dashboardWealthSnapshot {
        let characterSamples = characterWealthSamples(
          in: selectedWealthRange.filter(wealthHistory)
        )
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 128))],
          alignment: .leading,
          spacing: DesignTokens.spacingXS
        ) {
          dashboardWealthComponent(
            title: "Wallet",
            value: snapshot.walletTotal,
            color: DesignTokens.accent
          )
          dashboardWealthComponent(
            title: "Assets",
            value: snapshot.assetTotal,
            color: DesignTokens.positive
          )
          dashboardWealthComponent(
            title: "In production",
            value: snapshot.industryInProgressTotal,
            color: DesignTokens.caution
          )
        }
        DisclosureGroup("Character net worth") {
        ForEach(snapshot.characters) { character in
          HStack {
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              EVEEntityText(
                value: character.characterName,
                font: .callout.weight(.semibold)
              )
              if character.unvaluedAssetTypeCount > 0 {
                Text(
                  AppLocalization.format(
                    "%lld asset types have no reference price",
                    Int64(character.unvaluedAssetTypeCount)
                  )
                )
                .appFont(.caption)
                .foregroundStyle(DesignTokens.caution)
              }
              if character.excludedBlueprintCopyCount > 0 {
                Text(
                  AppLocalization.format(
                    "%lld BPC stacks without contract price",
                    Int64(character.excludedBlueprintCopyCount)
                  )
                )
                .appFont(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
              }
              if character.unvaluedOrderCount > 0
                || character.missingEscrowOrderCount > 0
              {
                Text("Some active order value is unavailable")
                  .appFont(.caption)
                  .foregroundStyle(DesignTokens.caution)
              }
              if character.contractsValue == nil
                || character.courierValue == nil
                || character.unvaluedContractItemTypeCount > 0
                || character.unavailableContractCount > 0
                || character.invalidCourierCollateralCount > 0
              {
                Text("Some private contract value is unavailable")
                  .appFont(.caption)
                  .foregroundStyle(DesignTokens.caution)
              }
            }
            Spacer()
            DashboardWealthChart(
              samples: characterSamples[character.characterID] ?? [],
              color: DesignTokens.accent
            )
            .frame(width: 92, height: 28)
            Text(wealthText(character))
              .appFont(.callout.weight(.semibold).monospacedDigit())
              .frame(minWidth: 128, alignment: .trailing)
          }
        }
        }
        DisclosureGroup("Valuation details") {
          valuationDetailsText
        }
        if let error = runtime.dashboardWealthError {
          Label {
            Text(
              AppLocalization.format(
                "%@ Showing the previous valuation.",
                AppLocalization.text(error)
              )
            )
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
          .appFont(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
      } else if let error = runtime.dashboardWealthError {
        Label {
          Text(AppLocalization.text(error))
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(DesignTokens.caution)
      } else if characters.isEmpty {
        Text("Connect a character to start the net-worth history.")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if let wealthPersistenceError {
        Label(wealthPersistenceError, systemImage: "externaldrive.badge.xmark")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
  }

  private var valuationDetailsText: some View {
    Text(
      "Assets and own outstanding contract items use ESI average prices with adjusted prices as the visible fallback. Consumed Manufacturing and Reaction materials remain under In production until delivery; missing facility or rig modifiers make that component an explicit estimate. Blueprint copies are excluded; courier collateral is an estimate. Missing personal or accessible corporation values remain partial and are never treated as zero."
    )
    .appFont(.caption)
    .foregroundStyle(DesignTokens.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func dashboardWealthComponent(
    title: LocalizedStringKey,
    value: Double?,
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      HStack(spacing: DesignTokens.spacingXS) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text(title)
          .appFont(.caption.weight(.semibold))
      }
      Text(value.map(formatISK) ?? AppLocalization.text("Unavailable"))
        .appFont(.caption.monospacedDigit())
        .foregroundStyle(
          value == nil ? DesignTokens.textSecondary : DesignTokens.textPrimary
        )
    }
    .padding(DesignTokens.spacingXS)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func dashboardJobRow(
    _ owned: DashboardIndustryOwnedJob,
    isReady: Bool
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      // Activity symbol in a small tile like the board's job list.
      Image(systemName: activityIcon(owned.job.dashboardActivity))
        .appFont(.caption)
        .foregroundStyle(DesignTokens.accent)
        .frame(width: 22, height: 22)
        .background(DesignTokens.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
          RoundedRectangle(cornerRadius: 4)
            .stroke(DesignTokens.border.opacity(0.7), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        EVEItemText(
          value: blueprintNames[owned.job.blueprintTypeID]
            ?? AppLocalization.format("Blueprint #%lld", owned.job.blueprintTypeID),
          typeID: owned.job.blueprintTypeID,
          font: .callout.weight(.semibold),
          lineLimit: 1
        )
        EVEEntityText(
          value: owned.characterName,
          font: .caption,
          lineLimit: 1
        )
      }
      Spacer()
      if isReady {
        Label("Ready", systemImage: "checkmark.circle.fill")
          .appFont(.caption.weight(.semibold))
          .foregroundStyle(DesignTokens.positive)
      } else {
        Label(
          owned.job.endDate.formatted(
            .relative(presentation: .named)
              .locale(AppLocalization.currentLanguage.locale)
          ),
          systemImage: "clock"
        )
        .appFont(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    // Both names stay separate copy targets for accessibility (DB7, B10).
    .accessibilityElement(children: .contain)
  }

  private var dashboardIndustryRefreshIdentity: DashboardIndustryRefreshIdentity {
    var hasher = Hasher()
    let jobSettings = jobSettingsByCharacterID
    for character in characters {
      hasher.combine(character.characterID)
      hasher.combine(character.characterName)
      hasher.combine(character.capabilitySnapshot)
      hasher.combine(jobSettings[character.characterID])
    }
    return DashboardIndustryRefreshIdentity(
      inputHash: hasher.finalize(),
      activeSDEBuild: runtime.activeSDEBuild
    )
  }

  private var dashboardIndustryInputs: [DashboardIndustryCharacterInput] {
    let jobSettings = jobSettingsByCharacterID
    return characters.map { character in
      DashboardIndustryCharacterInput(
        characterID: character.characterID,
        characterName: character.characterName,
        capabilitySnapshot: character.capabilitySnapshot,
        jobSnapshot: jobSettings[character.characterID].flatMap {
          Data(base64Encoded: $0)
        }
      )
    }
  }

  private var jobSettingsByCharacterID: [Int64: String] {
    let settingsByKey = Dictionary(
      settings.map { ($0.key, $0.value) },
      uniquingKeysWith: { _, latest in latest }
    )
    return Dictionary(
      uniqueKeysWithValues: characters.compactMap { character in
        let key = AppSettingKey.industryJobs(
          characterID: character.characterID
        )
        return settingsByKey[key].map { (character.characterID, $0) }
      }
    )
  }

  private var mainHubAutomationIdentity: String {
    guard let location = runtime.productionBasis.mainTradingLocation?.location
    else { return "unconfigured:\(runtime.isPlannerConfigurationReady)" }
    return [
      String(runtime.isPlannerConfigurationReady),
      location.kind.rawValue,
      String(location.regionID ?? 0),
      String(location.locationID ?? 0),
    ].joined(separator: ":")
  }

  private func capacityText(
    _ summary: DashboardIndustryCapacitySummary
  ) -> String {
    guard let value = summary.value else { return "—" }
    return summary.isComplete ? String(value) : "≥\(value)"
  }

  private var isPreparingIndustrySnapshot: Bool {
    industrySnapshot.characterCount != characters.count
  }

  private var jobDataNotice: some View {
    let incomplete = industrySnapshot.incompleteJobSourceCount
    return Group {
      if isPreparingIndustrySnapshot {
        Text("Preparing")
      } else if characters.isEmpty {
        Text(
          "Connect a character under Data & Settings to load jobs and skills."
        )
      } else if incomplete > 0 {
        Text(
          "Some job or skill sources are missing, stale, partial or forbidden; known values remain visible and are marked partial."
        )
      } else {
        Text("Job activity comes from the last synchronized ESI snapshots.")
      }
    }
    .appFont(.caption)
    .foregroundStyle(DesignTokens.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var walletPortfolio: WalletPortfolioSnapshot {
    WalletPortfolioSnapshot(
      balances: characters.map { character in
        CharacterWalletBalance(
          character: CharacterIdentity(
            id: character.characterID,
            name: character.characterName
          ),
          balance: storedWalletBalance(character)
        )
      }
    )
  }

  private var clientID: String {
    EVEConstants.ssoClientID
  }

  private func lastWalletSync(for characterID: Int64) -> Date? {
    characters.first(where: { $0.characterID == characterID })?
      .walletLastSyncAt
  }

  /// Captures the persisted sources on the main actor and decodes the large
  /// asset, blueprint and job snapshots on a background task.
  private func loadWealthInputs() async -> [DashboardWealthCharacterInput] {
    let rawInputs = characters.map { character in
      DashboardWealthRawInput(
        character: CharacterIdentity(
          id: character.characterID,
          name: character.characterName,
          corporationID: character.corporationID
        ),
        lastSyncAt: character.lastSyncAt,
        walletLastSyncAt: character.walletLastSyncAt,
        wallet: character.walletBalanceSnapshot,
        assets: character.assetSnapshot,
        corporationAssets: character.corporationAssetSnapshot,
        blueprints: character.blueprintSnapshot,
        openOrders: storedSettingValue(
          key: AppSettingKey.openOrders(characterID: character.characterID)
        ),
        privateContracts: storedSettingValue(
          key: AppSettingKey.privateContracts(
            characterID: character.characterID
          )
        ),
        corporationWallet: storedSettingValue(
          key: AppSettingKey.corporationWallet(
            characterID: character.characterID
          )
        ),
        industryJobs: storedSettingValue(
          key: AppSettingKey.industryJobs(characterID: character.characterID)
        )
      )
    }
    return await Task.detached(priority: .userInitiated) {
      rawInputs.map(\.decoded)
    }.value
  }

  private var wealthInputIdentity: String {
    characters.map {
      "\($0.characterID):\($0.lastSyncAt?.timeIntervalSince1970 ?? -1):\($0.walletLastSyncAt?.timeIntervalSince1970 ?? -1)"
    }.joined(separator: "|")
  }

  private var dashboardStartupCharacterIdentity: String {
    characters.map { String($0.characterID) }.joined(separator: ",")
  }

  private var wealthHistory: [DashboardWealthSnapshot] {
    wealthHistoryCache.history(
      encoded: settings.first(where: {
        $0.key == AppSettingKey.dashboardWealthHistory
      })?.value
    )
  }

  /// Per-character sparkline samples in one pass over the history; the
  /// first matching row of each snapshot counts, as before.
  private func characterWealthSamples(
    in rangeHistory: [DashboardWealthSnapshot]
  ) -> [Int64: [DashboardWealthChartSample]] {
    var samples: [Int64: [DashboardWealthChartSample]] = [:]
    for history in rangeHistory {
      var seen = Set<Int64>()
      for row in history.characters where seen.insert(row.characterID).inserted {
        if let value = row.knownValue {
          samples[row.characterID, default: []].append(
            DashboardWealthChartSample(date: history.capturedAt, value: value)
          )
        }
      }
    }
    return samples
  }

  private var wealthTotalText: String {
    guard let snapshot = runtime.dashboardWealthSnapshot,
      let value = snapshot.knownTotalValue
    else { return AppLocalization.text("Unavailable") }
    return snapshot.isComplete
      ? formatISK(value)
      : AppLocalization.format("Known: %@", formatISK(value))
  }

  private func wealthText(_ row: DashboardWealthCharacterValue) -> String {
    guard let value = row.knownValue else {
      return AppLocalization.text("Unavailable")
    }
    return row.isComplete
      ? formatISK(value)
      : AppLocalization.format("Known: %@", formatISK(value))
  }

  private func persistWealthSnapshot(_ snapshot: DashboardWealthSnapshot) {
    wealthPersistenceError = nil
    var history = wealthHistory
    let calendar = Calendar(identifier: .gregorian)
    if let index = history.lastIndex(where: {
      calendar.isDate($0.capturedAt, inSameDayAs: snapshot.capturedAt)
    }) {
      history[index] = snapshot
    } else {
      history.append(snapshot)
    }
    history = Array(
      history.sorted { $0.capturedAt < $1.capturedAt }.suffix(365)
    )
    do {
      let data = try JSONEncoder().encode(history)
      try modelContext.upsertAppSetting(
        key: AppSettingKey.dashboardWealthHistory,
        value: data.base64EncodedString()
      )
      try modelContext.save()
    } catch {
      modelContext.rollback()
      wealthPersistenceError = AppLocalization.text(
        "The net-worth history could not be saved."
      )
    }
  }

  @MainActor
  private func refreshDashboardData(isStartup: Bool) async {
    guard !isRefreshingDashboardData, !characters.isEmpty else { return }
    isRefreshingDashboardData = true
    dashboardDataRefreshMessage = nil
    dashboardDataRefreshError = nil
    defer { isRefreshingDashboardData = false }

    // At app start the Dashboard joins the runtime-owned startup load instead
    // of synchronizing every character a second time.
    let startupResult =
      isStartup
      ? await runtime.startupDataLoad.characterSynchronizationResult()
      : nil
    let result: CharacterBatchSyncResult
    if let startupResult {
      result = startupResult
    } else {
      result = await CharacterBatchSynchronizer.synchronize(
        characters: characters,
        runtime: runtime,
        modelContext: modelContext
      )
    }
    guard !Task.isCancelled else { return }
    lastCharacterSyncResult = result
    let synchronizedCount = result.synchronizedCount
    let failures = result.failedCharacterNames

    if !runtime.isRefreshingDashboardWealth {
      await runtime.refreshDashboardWealth(inputs: await loadWealthInputs())
      if runtime.dashboardWealthError == nil,
        let snapshot = runtime.dashboardWealthSnapshot
      {
        persistWealthSnapshot(snapshot)
      }
    }

    if failures.isEmpty {
      dashboardDataRefreshMessage =
        isStartup
        ? AppLocalization.format(
          "Dashboard updated at app start for %lld characters.",
          Int64(synchronizedCount)
        )
        : AppLocalization.format(
          "Dashboard updated for %lld characters.",
          Int64(synchronizedCount)
        )
    } else {
      let reasons = result.failureGroups.map {
        "\($0.reason) (\($0.characterNames.joined(separator: ", ")))"
      }
      dashboardDataRefreshError = AppLocalization.format(
        "%lld of %lld characters updated; unavailable characters kept their previous data: %@",
        Int64(synchronizedCount),
        Int64(result.totalCount),
        failures.joined(separator: ", ")
      ) + (reasons.isEmpty ? "" : " " + reasons.joined(separator: " "))
    }
  }

  @MainActor
  private func refreshWallet(for character: StoredCharacter) async {
    walletRefreshErrors[character.characterID] = nil
    refreshingWalletCharacterIDs.insert(character.characterID)
    defer { refreshingWalletCharacterIDs.remove(character.characterID) }
    do {
      let authorization = try JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: character.authorizationSnapshot
      )
      let balance = try await runtime.syncWallet(
        authorization: authorization,
        clientID: clientID
      )
      let previous = character.walletBalanceSnapshot.flatMap {
        try? JSONDecoder().decode(Sourced<Double>.self, from: $0)
      }
      let retained = balance.retainingLastKnownValue(from: previous)
      character.walletBalanceSnapshot = try JSONEncoder().encode(retained)
      if balance.value != nil {
        character.walletLastSyncAt = balance.source.capturedAt
      }
      try modelContext.upsertESISnapshotMetadata(
        characterID: character.characterID,
        domain: "wallet-balance",
        freshness: balance.state.rawValue,
        provider: balance.source.provider,
        sourceVersion: balance.source.version,
        sourceSnapshotID: balance.source.snapshotID,
        capturedAt: balance.source.capturedAt,
        diagnostics: balance.diagnostics
      )
      try modelContext.save()
    } catch {
      modelContext.rollback()
      walletRefreshErrors[character.characterID] =
        DashboardWalletRefreshMessage.text(
          characterName: character.characterName,
          error: error
        )
    }
  }

  private func storedWalletBalance(_ character: StoredCharacter) -> Sourced<Double> {
    DashboardWealthRawInput.walletBalance(
      character.walletBalanceSnapshot,
      walletLastSyncAt: character.walletLastSyncAt
    )
  }

  private func storedSettingValue(key: String) -> String? {
    (try? modelContext.appSettingValue(for: key))
      ?? settings.first(where: { $0.key == key })?.value
  }

  private var filteredNegativeReactions: [ReactionAnalysisRow] {
    guard let rows = runtime.reactionAnalysis?.rows else { return [] }
    return rows.filter {
      guard let value = $0.valueCreation, value.isFinite, value < 0 else {
        return false
      }
      return true
    }.sorted {
      if $0.valueCreation != $1.valueCreation {
        return ($0.valueCreation ?? 0) < ($1.valueCreation ?? 0)
      }
      return $0.id < $1.id
    }
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    authorizationCache.snapshots(characters.map(\.authorizationSnapshot))
  }

  private func activityTitle(
    _ activity: DashboardIndustryActivity
  ) -> LocalizedStringKey {
    switch activity {
    case .manufacturing: "Manufacturing"
    case .reaction: "Reactions"
    case .copying: "Copying"
    case .invention: "Invention"
    case .materialResearch: "ME research"
    case .timeResearch: "TE research"
    }
  }

  private func activityIcon(
    _ activity: DashboardIndustryActivity?
  ) -> String {
    switch activity {
    case .manufacturing: "hammer.fill"
    case .reaction: "atom"
    case .copying: "doc.on.doc.fill"
    case .invention: "lightbulb.fill"
    case .materialResearch: "cube.transparent.fill"
    case .timeResearch: "clock.badge.checkmark.fill"
    case nil: "questionmark.circle"
    }
  }

  private func sourceStateLine(_ state: DataFreshness?) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      if let state { freshnessPill(state) }
      Text("Change compares the latest two available regional market days.")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func freshnessPill(
    _ state: DataFreshness,
    text: LocalizedStringKey? = nil
  ) -> some View {
    let color: Color =
      switch state {
      case .fresh: DesignTokens.positive
      case .partial, .stale: DesignTokens.caution
      case .forbidden, .unavailable: DesignTokens.negative
      }
    return Text(text ?? LocalizedStringKey(state.rawValue.uppercased()))
      .appFont(.caption2.bold())
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .foregroundStyle(color)
      .background(color.opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func formatISK(_ value: Double) -> String {
    NetWorthValueFormat.isk(value)
  }
}

struct DashboardWealthChartSample {
  let date: Date
  let value: Double
}

/// Persisted Dashboard valuation sources as raw bytes. They are captured on
/// the main actor and decoded on a background task, because asset, blueprint
/// and job snapshots of all characters amount to several megabytes of JSON.
/// Missing or undecodable sources stay explicitly unavailable.
struct DashboardWealthRawInput: Sendable {
  let character: CharacterIdentity
  let lastSyncAt: Date?
  let walletLastSyncAt: Date?
  let wallet: Data?
  let assets: Data?
  let corporationAssets: Data?
  let blueprints: Data?
  /// Base64-encoded `AppSetting` values.
  let openOrders: String?
  let privateContracts: String?
  let corporationWallet: String?
  let industryJobs: String?

  var decoded: DashboardWealthCharacterInput {
    DashboardWealthCharacterInput(
      character: character,
      wallet: Self.walletBalance(wallet, walletLastSyncAt: walletLastSyncAt),
      assets: Self.decode(
        assets,
        capturedAt: lastSyncAt,
        diagnostic: "assets.not-synchronized"
      ),
      openOrders: Self.decode(
        base64: openOrders,
        capturedAt: lastSyncAt,
        diagnostic: "orders.not-synchronized"
      ),
      privateContracts: Self.decode(
        base64: privateContracts,
        capturedAt: lastSyncAt,
        diagnostic: "private-contracts.not-synchronized"
      ),
      corporationAssets: Self.decode(
        corporationAssets,
        capturedAt: lastSyncAt,
        diagnostic: "corporation-assets.not-synchronized"
      ),
      corporationWallet: Self.decode(
        base64: corporationWallet,
        capturedAt: lastSyncAt,
        diagnostic: "corporation-wallet.not-synchronized"
      ),
      industryJobs: Self.decode(
        base64: industryJobs,
        capturedAt: lastSyncAt,
        diagnostic: "industry-jobs.not-synchronized"
      ),
      blueprints: Self.decode(
        blueprints,
        capturedAt: lastSyncAt,
        diagnostic: "blueprints.not-synchronized"
      )
    )
  }

  static func walletBalance(
    _ data: Data?,
    walletLastSyncAt: Date?
  ) -> Sourced<Double> {
    decode(
      data,
      capturedAt: walletLastSyncAt,
      diagnostic: "wallet.not-synchronized"
    )
  }

  private static func decode<Value: Codable & Sendable>(
    base64 encoded: String?,
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    decode(
      encoded.flatMap { Data(base64Encoded: $0) },
      capturedAt: capturedAt,
      diagnostic: diagnostic
    )
  }

  private static func decode<Value: Codable & Sendable>(
    _ data: Data?,
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    if let data,
      let value = try? JSONDecoder().decode(Sourced<Value>.self, from: data)
    {
      return value
    }
    return Sourced(
      state: .unavailable,
      value: nil,
      source: SourceIdentity(
        provider: "Local",
        version: "not-synchronized",
        capturedAt: capturedAt ?? .distantPast
      ),
      diagnostics: [diagnostic]
    )
  }
}

/// Decodes each character's stored authorization once per stored value
/// instead of on every Dashboard evaluation. Not observed, like
/// `DashboardWealthHistoryCache`.
@MainActor
final class DashboardAuthorizationCache {
  private var decoded: [Data: AuthorizationSnapshot] = [:]

  func snapshots(_ encoded: [Data]) -> [AuthorizationSnapshot] {
    var next: [Data: AuthorizationSnapshot] = [:]
    let result = encoded.compactMap { data -> AuthorizationSnapshot? in
      if let snapshot = next[data] ?? decoded[data] {
        next[data] = snapshot
        return snapshot
      }
      guard
        let snapshot = try? JSONDecoder().decode(
          AuthorizationSnapshot.self,
          from: data
        )
      else { return nil }
      next[data] = snapshot
      return snapshot
    }
    decoded = next
    return result
  }
}

/// Keeps the last prepared industry snapshot for its exact inputs, so a
/// return to the Dashboard shows it at once instead of rebuilding it.
@MainActor
private final class DashboardIndustrySnapshotCache {
  static let shared = DashboardIndustrySnapshotCache()

  struct Entry {
    let identity: DashboardIndustryRefreshIdentity
    let snapshot: DashboardIndustrySnapshot
    let blueprintNames: [Int64: String]
  }

  private var entry: Entry?

  func entry(for identity: DashboardIndustryRefreshIdentity) -> Entry? {
    entry?.identity == identity ? entry : nil
  }

  func store(
    identity: DashboardIndustryRefreshIdentity,
    snapshot: DashboardIndustrySnapshot,
    blueprintNames: [Int64: String]
  ) {
    entry = Entry(
      identity: identity,
      snapshot: snapshot,
      blueprintNames: blueprintNames
    )
  }
}

/// Decodes the persisted net-worth history once per stored value instead of
/// on every read during view evaluation. The cache is not observed; views
/// keep one instance in `@State` and stay driven by their settings query.
/// One instance is shared by Dashboard and Net worth, so returning to either
/// view does not decode the year-long history again.
@MainActor
final class DashboardWealthHistoryCache {
  static let shared = DashboardWealthHistoryCache()
  private var encodedHistory: String?
  private var history: [DashboardWealthSnapshot] = []

  func history(encoded: String?) -> [DashboardWealthSnapshot] {
    if encoded == encodedHistory { return history }
    encodedHistory = encoded
    guard let encoded,
      let data = Data(base64Encoded: encoded),
      let decoded = try? JSONDecoder().decode(
        [DashboardWealthSnapshot].self,
        from: data
      )
    else {
      history = []
      return history
    }
    history = decoded.sorted { $0.capturedAt < $1.capturedAt }
    return history
  }
}

struct DashboardWealthChart: View {
  let samples: [DashboardWealthChartSample]
  let color: Color
  var showsAxes = false

  var body: some View {
    GeometryReader { proxy in
      let valid = samples.filter { $0.value.isFinite }.sorted {
        $0.date < $1.date
      }
      if !valid.isEmpty {
        let values = valid.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        let rawRange = maximum - minimum
        let padding = max(rawRange * 0.12, max(abs(maximum) * 0.005, 1))
        let lower = minimum < 0 ? minimum - padding : max(0, minimum - padding)
        let upper = max(lower + 1, maximum + padding)
        let range = upper - lower
        let firstDate = valid[0].date
        let lastDate = valid[valid.count - 1].date
        let duration = max(lastDate.timeIntervalSince(firstDate), 1)
        let plot = CGRect(x: showsAxes ? 66 : 3, y: 8,
          width: max(1, proxy.size.width - (showsAxes ? 80 : 6)),
          height: max(1, proxy.size.height - (showsAxes ? 42 : 24)))
        ZStack(alignment: .bottom) {
          Path { path in
            for (index, sample) in valid.enumerated() {
              let x =
                plot.minX + plot.width
                * CGFloat(sample.date.timeIntervalSince(firstDate) / duration)
              let normalized = (sample.value - lower) / range
              let y = plot.minY + plot.height * (1 - CGFloat(normalized))
              if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
              } else {
                path.addLine(to: CGPoint(x: x, y: y))
              }
            }
          }
          .stroke(
            color,
            style: StrokeStyle(
              lineWidth: 2,
              lineCap: .round,
              lineJoin: .round
            )
          )
          if valid.count == 1 {
            Circle().fill(color).frame(width: 6, height: 6)
              .position(x: plot.minX,
                y: plot.minY + plot.height * (1 - CGFloat((valid[0].value - lower) / range)))
          }
          if showsAxes {
            ForEach(0..<3) { step in
              let fraction = Double(step) / 2
              Text((upper - range * fraction).formatted(.number.notation(.compactName).precision(.fractionLength(1)).locale(AppLocalization.currentLanguage.locale)))
                .appFont(.caption2.monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 58, alignment: .trailing)
                .position(x: 29, y: plot.minY + plot.height * CGFloat(fraction))
            }
          }
          HStack {
            Text(firstDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLocalization.currentLanguage.locale)))
            Spacer()
            Text(lastDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLocalization.currentLanguage.locale)))
          }
          .appFont(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
          .padding(.leading, plot.minX)
          .padding(.trailing, 10)
        }
      } else {
        Rectangle().fill(Color.clear)
      }
    }
  }
}

private struct DashboardMineralTicker: View {
  let rows: [MaterialPurchaseRecommendation]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private let itemWidth: CGFloat = 340
  private let animationDuration: TimeInterval = 32

  var body: some View {
    if reduceMotion {
      ScrollView(.horizontal) {
        DashboardMineralTickerContent(
          rows: rows,
          repetitions: 1,
          itemWidth: itemWidth
        )
      }
      .scrollIndicators(.hidden)
    } else {
      DashboardMineralTickerMarquee(
        rows: rows,
        itemWidth: itemWidth,
        animationDuration: animationDuration,
        isActive: scenePhase == .active
      )
      .clipped()
    }
  }
}

private struct DashboardMineralTickerMarquee: NSViewRepresentable {
  let rows: [MaterialPurchaseRecommendation]
  let itemWidth: CGFloat
  let animationDuration: TimeInterval
  let isActive: Bool

  func makeNSView(context: Context) -> DashboardMineralTickerMarqueeView {
    let view = DashboardMineralTickerMarqueeView()
    view.update(
      rows: rows,
      itemWidth: itemWidth,
      animationDuration: animationDuration,
      isActive: isActive
    )
    return view
  }

  func updateNSView(
    _ nsView: DashboardMineralTickerMarqueeView,
    context: Context
  ) {
    nsView.update(
      rows: rows,
      itemWidth: itemWidth,
      animationDuration: animationDuration,
      isActive: isActive
    )
  }
}

@MainActor
private final class DashboardMineralTickerMarqueeView: NSView {
  private var hostingView: NSHostingView<DashboardMineralTickerContent>?
  private var rows: [MaterialPurchaseRecommendation] = []
  private var itemWidth: CGFloat = 340
  private var animationDuration: TimeInterval = 32
  private var isAnimationActive = false
  private var lastLayoutSize: CGSize = .zero

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  func update(
    rows: [MaterialPurchaseRecommendation],
    itemWidth: CGFloat,
    animationDuration: TimeInterval,
    isActive: Bool
  ) {
    let contentChanged = self.rows != rows || self.itemWidth != itemWidth
    let timingChanged = self.animationDuration != animationDuration
    self.rows = rows
    self.itemWidth = itemWidth
    self.animationDuration = animationDuration
    isAnimationActive = isActive && !rows.isEmpty

    let content = DashboardMineralTickerContent(
      rows: rows,
      repetitions: 2,
      itemWidth: itemWidth
    )
    if let hostingView {
      if contentChanged {
        hostingView.rootView = content
      }
    } else {
      let hostingView = NSHostingView(rootView: content)
      hostingView.wantsLayer = true
      hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
      addSubview(hostingView)
      self.hostingView = hostingView
    }

    needsLayout = true
    layoutSubtreeIfNeeded()
    updateAnimation(restart: contentChanged || timingChanged)
  }

  override func layout() {
    super.layout()
    guard let hostingView else { return }
    let contentWidth = max(itemWidth, CGFloat(rows.count) * itemWidth)
    let newSize = CGSize(
      width: max(bounds.width, contentWidth * 2),
      height: bounds.height
    )
    hostingView.frame = CGRect(origin: .zero, size: newSize)
    if newSize != lastLayoutSize {
      lastLayoutSize = newSize
      updateAnimation(restart: true)
    }
  }

  private func updateAnimation(restart: Bool) {
    guard let contentLayer = hostingView?.layer else { return }
    if !isAnimationActive {
      contentLayer.removeAnimation(forKey: "mineral-marquee")
      return
    }
    guard restart || contentLayer.animation(forKey: "mineral-marquee") == nil
    else { return }

    let contentWidth = max(itemWidth, CGFloat(rows.count) * itemWidth)
    let animation = CABasicAnimation(keyPath: "transform.translation.x")
    animation.fromValue = 0
    animation.toValue = -contentWidth
    animation.duration = animationDuration
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    animation.isRemovedOnCompletion = false
    contentLayer.add(animation, forKey: "mineral-marquee")
  }
}

private struct DashboardMineralTickerContent: View {
  let rows: [MaterialPurchaseRecommendation]
  let repetitions: Int
  let itemWidth: CGFloat

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<(rows.count * repetitions), id: \.self) { index in
        let row = rows[index % rows.count]
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: DesignTokens.spacingSM) {
            EVEItemText(value: row.material.name, typeID: row.material.id, iconSize: 20)
              .appFont(.callout.weight(.semibold))
            Text(row.unitPrice.map {
              $0.formatted(.currency(code: "ISK").precision(.fractionLength(2)).locale(AppLocalization.currentLanguage.locale))
            } ?? AppLocalization.text("Unavailable"))
              .appFont(.callout.monospacedDigit())
          }
          if let location = row.location {
            EVEEntityText(value: location.name, font: .caption, lineLimit: 1)
          } else {
            Text("No fresh sell offer available").appFont(.caption)
          }
        }
        .frame(width: itemWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
      }
    }
  }

  private func trend(_ value: Double?) -> some View {
    let color: Color = {
      guard let value else { return DesignTokens.textSecondary }
      if value > 0 { return DesignTokens.positive }
      if value < 0 { return DesignTokens.negative }
      return DesignTokens.textSecondary
    }()
    let icon: String = {
      guard let value else { return "minus" }
      if value > 0 { return "arrow.up.right" }
      if value < 0 { return "arrow.down.right" }
      return "minus"
    }()
    return Label {
      Text(
        value?.formatted(
          .percent.precision(.fractionLength(1)).sign(strategy: .always())
            .locale(AppLocalization.currentLanguage.locale)
        ) ?? "—"
      )
    } icon: {
      Image(systemName: icon)
    }
    .appFont(.caption.monospacedDigit())
    .foregroundStyle(color)
  }

  private func trendAccessibility(_ value: Double?) -> String {
    guard let value else { return AppLocalization.text("Change unavailable") }
    if value > 0 { return AppLocalization.text("Price increased") }
    if value < 0 { return AppLocalization.text("Price decreased") }
    return AppLocalization.text("Price unchanged")
  }
}

private struct DataSettingsWorkspace: View {
  @Binding var selection: DataSettingsSection

  var body: some View {
    SettingsWorkspaceLayout {
      DataSettingsNavigationBar(selection: $selection)
    } content: {
      switch selection {
      case .general:
        GeneralSettingsView()
      case .sde:
        DataSettingsView()
      case .esi:
        CharactersView()
      case .industrySettings:
        ProfilesView()
      case .logistics:
        LogisticsSettingsView()
      case .marketSettings:
        MarketSettingsView()
      }
    }
  }
}

/// Reserve the navigation bar inside the native safe area. A sibling VStack
/// can let an inner scroll view consume the title-bar inset on its own. The
/// geometry proxy also prevents an intrinsically wide page from widening the
/// inset beyond the NavigationSplitView detail column.
struct SettingsWorkspaceLayout<Navigation: View, Content: View>: View {
  let navigation: Navigation
  let content: Content

  init(
    @ViewBuilder navigation: () -> Navigation,
    @ViewBuilder content: () -> Content
  ) {
    self.navigation = navigation()
    self.content = content()
  }

  var body: some View {
    GeometryReader { geometry in
      content
        .frame(width: geometry.size.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .safeAreaInset(edge: .top, spacing: 0) {
          VStack(spacing: 0) {
            navigation
            Divider()
          }
          .frame(width: geometry.size.width)
        }
    }
  }
}

struct DataSettingsNavigationBar: View {
  @Binding var selection: DataSettingsSection

  var body: some View {
    ViewThatFits(in: .horizontal) {
      settingsPicker
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)

      HStack(spacing: DesignTokens.spacingSM) {
        Label(selection.title, systemImage: selection.icon)
          .appFont(.headline)
        Spacer(minLength: DesignTokens.spacingSM)
        settingsPicker
          .pickerStyle(.menu)
          .labelsHidden()
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, DesignTokens.spacingLG)
    .padding(.vertical, DesignTokens.spacingSM)
    .frame(maxWidth: .infinity)
    .background(DesignTokens.panel)
    .accessibilityIdentifier("data-settings.navigation")

  }

  private var settingsPicker: some View {
    Picker("Data & Settings", selection: $selection) {
      ForEach(DataSettingsSection.allCases) { section in
        Label(section.title, systemImage: section.icon)
          .tag(section)
          .accessibilityIdentifier(
            "data-settings.navigation.\(section.rawValue)"
          )
      }
    }
  }
}

private struct GeneralSettingsView: View {
  @AppStorage(AppLanguage.storageKey, store: AppDefaults.store)
  private var storedLanguage = AppLanguage.defaultLanguage.rawValue
  @AppStorage(AppTextSize.storageKey, store: AppDefaults.store)
  private var storedTextSize = AppTextSize.standard.rawValue
  @AppStorage(AppAppearanceStyle.storageKey, store: AppDefaults.store)
  private var storedAppearance = AppAppearanceStyle.system.rawValue
  @AppStorage(AppInterfaceStyle.storageKey, store: AppDefaults.store)
  private var storedInterfaceStyle = AppInterfaceStyle.defaultStyle.rawValue
  @AppStorage(
    EVEEntityAppearance.colorStorageKey,
    store: AppDefaults.store
  )
  private var entityTextColorHex = EVEEntityAppearance.defaultColorHex

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("General Settings")
          .appFont(.largeTitle.bold())
          .nexusPageTitle()

        Panel(title: "Language & Terminology") {
          Picker("Language", selection: languageBinding) {
            ForEach(AppLanguage.allCases) { language in
              Text(language.title).tag(language.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 360)
          .accessibilityIdentifier("general.language")

          Text(
            "Explanations and EVE industry terminology follow this selection immediately. EVE item names, character names, locations, ESI, SDE, ME and TE remain unchanged so they still match the EVE client and imported data."
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }

        Panel(title: "Window & text") {
          Picker("Text Size", selection: $storedTextSize) {
            ForEach(AppTextSize.allCases) { size in
              Text(size.title).tag(size.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("appearance.text-size")

          Text(
            "The selected size applies immediately throughout the app and is restored the next time it starts. You can also use Command-Plus, Command-Minus and Command-0."
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)

          Label(
            "Panels switch to fewer columns when space is limited. Wide data tables remain horizontally scrollable instead of shrinking values beyond recognition.",
            systemImage: "rectangle.split.3x1"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }

        Panel(title: "Colors") {
          Picker("Interface style", selection: $storedInterfaceStyle) {
            ForEach(AppInterfaceStyle.allCases) { style in
              Text(style.title).tag(style.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 440)
          .accessibilityIdentifier("appearance.interface-style")

          Text(
            "Classic keeps the established look. New Eden HUD shows the interface in the style of an EVE HUD and always runs dark. Contents, sorting and calculations are the same in both styles."
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)

          Picker("Color scheme", selection: $storedAppearance) {
            ForEach(AppAppearanceStyle.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 440)
          .disabled(interfaceStyle.locksColorScheme)
          .accessibilityIdentifier("appearance.color-scheme")

          if interfaceStyle.locksColorScheme {
            Label(
              "New Eden HUD is always dark. The selected color scheme is kept and applies again in Classic.",
              systemImage: "moon.fill"
            )
            .appFont(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            .accessibilityIdentifier("appearance.color-scheme.hud-hint")
          }

          Text(
            "System follows the current macOS appearance. Light uses cool titanium surfaces with EVE-inspired cyan accents; Dark keeps the graphite command-console look. Status colors retain their meaning in both modes."
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }

        Panel(title: "EVE names and data") {
          Text(
            "Items, reactions, regions, systems, stations and structures use a shared emphasized text style. Click a displayed EVE name to copy it; the app confirms whether copying succeeded."
          )
          .foregroundStyle(DesignTokens.textSecondary)
          ColorPicker(
            "Text color",
            selection: entityTextColorBinding,
            supportsOpacity: false
          )
          .accessibilityIdentifier("appearance.entity-text-color")

          ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.spacingMD) {
              appearancePreview
              Spacer(minLength: DesignTokens.spacingSM)
              resetEntityColorButton
            }

            VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
              appearancePreview
              resetEntityColorButton
            }
          }
        }

        BackgroundOperationPanel()

        ConsolidationBackupView()
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: 1_600, alignment: .leading)
    }
    .navigationTitle(AppLocalization.text("General Settings"))
  }

  private var interfaceStyle: AppInterfaceStyle {
    AppInterfaceStyle(storedValue: storedInterfaceStyle)
  }

  private var languageBinding: Binding<String> {
    Binding(
      get: { storedLanguage },
      set: { language in
        AppDefaults.store.set(
          language,
          forKey: AppLanguage.storageKey
        )
        storedLanguage = language
      }
    )
  }

  private var appearancePreview: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      Text("Example")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      EVEItemText(value: "Tritanium", typeID: 34)
      EVEEntityText(value: "Jita IV-4")
      EVEEntityText(value: "The Forge")
    }
  }

  private var resetEntityColorButton: some View {
    Button("Reset color") {
      entityTextColorHex = EVEEntityAppearance.defaultColorHex
    }
  }

  private var entityTextColorBinding: Binding<Color> {
    Binding(
      get: { EVEEntityAppearance.selectionColor(from: entityTextColorHex) },
      set: { entityTextColorHex = EVEEntityAppearance.hex(from: $0) }
    )
  }
}

struct EVEOnlineServiceBanner: View {
  @Environment(RuntimeState.self) private var runtime

  private struct Notice {
    let title: String
    let message: String
    let systemImage: String
    let color: Color
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      if let notice = notice(at: context.date) {
        HStack(alignment: .top, spacing: DesignTokens.spacingSM) {
          Image(systemName: notice.systemImage)
            .foregroundStyle(notice.color)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(AppLocalization.text(notice.title))
              .appFont(.subheadline.bold())
            Text(AppLocalization.text(notice.message))
              .appFont(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer(minLength: DesignTokens.spacingSM)
          Link(
            AppLocalization.text("Open CCP status"),
            destination: URL(string: "https://status.eveonline.com/")!
          )
          .appFont(.caption)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.color.opacity(0.12))
        .overlay(alignment: .bottom) {
          Divider()
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func notice(at date: Date) -> Notice? {
    let status = recentStatus(at: date)
    if status?.hasLoginIssue == true && status?.hasESIIssue == true {
      return Notice(
        title: "EVE services affected",
        message:
          "CCP currently reports problems with both EVE Login (SSO) and ESI. Authorization and data synchronization can fail; locally stored data remains available.",
        systemImage: "network.slash",
        color: DesignTokens.negative
      )
    }
    if status?.hasLoginIssue == true {
      return Notice(
        title: "EVE SSO affected",
        message:
          "CCP currently reports a problem with EVE Login (SSO). New authorization or token renewal can fail; this is separate from an ESI data error.",
        systemImage: "person.crop.circle.badge.exclamationmark",
        color: DesignTokens.negative
      )
    }
    if status?.hasESIIssue == true {
      return Notice(
        title: "EVE ESI affected",
        message:
          "CCP currently reports a problem with ESI. SSO can still work while character, asset, blueprint, market or wallet data cannot be refreshed.",
        systemImage: "arrow.triangle.2.circlepath.circle.fill",
        color: DesignTokens.negative
      )
    }
    if status?.isGameServerUnderMaintenance == true {
      let confirmsLoginAndESI =
        status?.login == .operational && status?.esi == .operational
      return Notice(
        title: "EVE downtime",
        message:
          confirmsLoginAndESI
          ? "Tranquility is in maintenance. CCP currently reports Login (SSO) and ESI as operational, but data synchronization can still be slow or incomplete. Wait a few minutes and try again."
          : "Tranquility is in maintenance. Authorization and data synchronization may be temporarily delayed. Wait a few minutes and try again.",
        systemImage: "wrench.and.screwdriver.fill",
        color: DesignTokens.caution
      )
    }
    if EVEOnlineDailyDowntime.isExpected(at: date) {
      return Notice(
        title: "Expected EVE downtime",
        message:
          "The daily Tranquility restart begins at 11:00 UTC and usually lasts only a few minutes. SSO and ESI are separate services, but synchronization can still be temporarily slow or incomplete.",
        systemImage: "clock.badge.exclamationmark.fill",
        color: DesignTokens.caution
      )
    }
    if status?.hasGameServerIssue == true {
      return Notice(
        title: "EVE game server affected",
        message:
          "CCP currently reports a Tranquility problem. Login and ESI have separate status, so the app keeps their errors distinct.",
        systemImage: "exclamationmark.triangle.fill",
        color: DesignTokens.caution
      )
    }
    return nil
  }

  private func recentStatus(
    at date: Date
  ) -> EVEOnlineServiceStatusSnapshot? {
    guard let status = runtime.eveOnlineServiceStatus,
      abs(date.timeIntervalSince(status.fetchedAt)) < 15 * 60
    else {
      return nil
    }
    return status
  }
}

@MainActor
final class ProfileNavigationGuard: ObservableObject {
  @Published var hasUnsavedChanges = false
  @Published var isPresentingWarning = false
  @Published private(set) var saveRequestID = 0
  @Published private(set) var discardRequestID = 0

  private var pendingNavigation: (@MainActor () -> Void)?

  func attemptNavigation(
    _ navigation: @escaping @MainActor () -> Void
  ) {
    guard hasUnsavedChanges else {
      navigation()
      return
    }
    pendingNavigation = navigation
    isPresentingWarning = true
  }

  func updateDirtyState(_ isDirty: Bool) {
    hasUnsavedChanges = isDirty
  }

  func requestSaveAndContinue() {
    isPresentingWarning = false
    saveRequestID += 1
  }

  func requestDiscardAndContinue() {
    isPresentingWarning = false
    discardRequestID += 1
  }

  func completeSave(success: Bool) {
    guard success else {
      pendingNavigation = nil
      return
    }
    completePendingNavigation()
  }

  func completeDiscard() {
    completePendingNavigation()
  }

  func cancelNavigation() {
    isPresentingWarning = false
    pendingNavigation = nil
  }

  private func completePendingNavigation() {
    hasUnsavedChanges = false
    let navigation = pendingNavigation
    pendingNavigation = nil
    navigation?()
  }
}

enum DesignTokens {
  // The light palette uses cool titanium surfaces instead of plain macOS
  // white. The dark values intentionally stay close to the existing EVE-like
  // graphite appearance so both modes share the same visual hierarchy.
  static let canvas = adaptiveColor(
    light: NSColor(srgbRed: 0.90, green: 0.93, blue: 0.94, alpha: 1),
    dark: NSColor(srgbRed: 0.075, green: 0.095, blue: 0.11, alpha: 1)
  )
  static let panel = adaptiveColor(
    light: NSColor(srgbRed: 0.975, green: 0.985, blue: 0.988, alpha: 1),
    dark: NSColor(srgbRed: 0.115, green: 0.14, blue: 0.155, alpha: 1)
  )
  static let elevated = adaptiveColor(
    light: NSColor(srgbRed: 0.84, green: 0.88, blue: 0.895, alpha: 1),
    dark: NSColor(srgbRed: 0.15, green: 0.18, blue: 0.195, alpha: 1)
  )
  static let sidebar = adaptiveColor(
    light: NSColor(srgbRed: 0.82, green: 0.865, blue: 0.885, alpha: 1),
    dark: NSColor(srgbRed: 0.095, green: 0.12, blue: 0.135, alpha: 1)
  )
  static let sidebarElevated = adaptiveColor(
    light: NSColor(srgbRed: 0.86, green: 0.90, blue: 0.915, alpha: 0.98),
    dark: NSColor(srgbRed: 0.12, green: 0.145, blue: 0.16, alpha: 0.98)
  )
  static let border = adaptiveColor(
    light: NSColor(srgbRed: 0.54, green: 0.62, blue: 0.65, alpha: 0.72),
    dark: NSColor(srgbRed: 0.28, green: 0.35, blue: 0.38, alpha: 0.9)
  )
  static let panelShadow = adaptiveColor(
    light: NSColor(srgbRed: 0.10, green: 0.18, blue: 0.21, alpha: 0.16),
    dark: NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.2)
  )
  static let textPrimary = Color.primary
  static let textSecondary = Color.secondary
  static let textDisabled = Color(nsColor: .disabledControlTextColor)
  static let accent = adaptiveColor(
    light: NSColor(srgbRed: 0.02, green: 0.39, blue: 0.55, alpha: 1),
    dark: NSColor(srgbRed: 0.21, green: 0.78, blue: 0.91, alpha: 1)
  )
  static let accentSoft = accent.opacity(0.2)
  static let highlight = adaptiveColor(
    light: NSColor(srgbRed: 0.55, green: 0.31, blue: 0.00, alpha: 1),
    dark: NSColor(srgbRed: 0.96, green: 0.73, blue: 0.26, alpha: 1)
  )
  static let positive = adaptiveColor(
    light: NSColor(srgbRed: 0.00, green: 0.42, blue: 0.27, alpha: 1),
    dark: NSColor(srgbRed: 0.24, green: 0.86, blue: 0.59, alpha: 1)
  )
  static let caution = adaptiveColor(
    light: NSColor(srgbRed: 0.62, green: 0.32, blue: 0.00, alpha: 1),
    dark: NSColor(srgbRed: 0.96, green: 0.65, blue: 0.14, alpha: 1)
  )
  static let negative = adaptiveColor(
    light: NSColor(srgbRed: 0.72, green: 0.12, blue: 0.10, alpha: 1),
    dark: NSColor(srgbRed: 0.94, green: 0.33, blue: 0.31, alpha: 1)
  )
  static let information = adaptiveColor(
    light: NSColor(srgbRed: 0.22, green: 0.29, blue: 0.70, alpha: 1),
    dark: NSColor(srgbRed: 0.48, green: 0.55, blue: 1.00, alpha: 1)
  )

  static let spacingXS: CGFloat = 4
  static let spacingSM: CGFloat = 8
  static let spacingMD: CGFloat = 16
  static let spacingLG: CGFloat = 24
  static let cardRadius: CGFloat = 10
  static let badgeRadius: CGFloat = 6
  static let panelShadowRadius: CGFloat = 7
  static let panelShadowOffset: CGFloat = 2
  static let sidebarMinimum: CGFloat = 180
  static let sidebarIdeal: CGFloat = 220
  static let plannerInputMinimumHeight: CGFloat = 152
  static let stockInputMinimumHeight: CGFloat = 72
  static let profileColumnMinimum: CGFloat = 340
  static let systemNameMinimum: CGFloat = 150
  static let systemIDWidth: CGFloat = 132
  static let compactNumberWidth: CGFloat = 92
  static let structureEditorMinimum: CGFloat = 320
  static let efficiencyLabelMinimum: CGFloat = 148

  private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          ? dark
          : light
      }
    )
  }
}

enum EVEEntityAppearance {
  static let colorStorageKey = "eve.presentation.entity-text-color"
  static let defaultColorHex = "#35C7E8"

  static func color(from hex: String) -> Color {
    let normalized = normalizedHex(hex)
    if normalized.caseInsensitiveCompare(
      normalizedHex(defaultColorHex)
    ) == .orderedSame {
      return DesignTokens.accent
    }
    guard let components = rgbComponents(from: normalized) else {
      return DesignTokens.accent
    }
    let selectedColor = NSColor(
      srgbRed: components.red,
      green: components.green,
      blue: components.blue,
      alpha: 1
    )
    let lightColor = accessibleLightColor(components)
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          ? selectedColor
          : lightColor
      }
    )
  }

  static func selectionColor(from hex: String) -> Color {
    guard let components = rgbComponents(from: normalizedHex(hex)) else {
      return selectionColor(from: defaultColorHex)
    }
    return Color(
      red: components.red,
      green: components.green,
      blue: components.blue
    )
  }

  static func hex(from color: Color) -> String {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
      return defaultColorHex
    }
    return String(
      format: "#%02X%02X%02X",
      Int((rgb.redComponent * 255).rounded()),
      Int((rgb.greenComponent * 255).rounded()),
      Int((rgb.blueComponent * 255).rounded())
    )
  }

  private static func normalizedHex(_ hex: String) -> String {
    hex.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
  }

  private static func rgbComponents(
    from normalizedHex: String
  ) -> (red: Double, green: Double, blue: Double)? {
    guard normalizedHex.count == 6,
      let value = UInt64(normalizedHex, radix: 16)
    else { return nil }
    return (
      Double((value >> 16) & 0xff) / 255,
      Double((value >> 8) & 0xff) / 255,
      Double(value & 0xff) / 255
    )
  }

  private static func accessibleLightColor(
    _ color: (red: Double, green: Double, blue: Double)
  ) -> NSColor {
    let background = (red: 0.975, green: 0.985, blue: 0.988)
    guard contrastRatio(color, background) < 4.5 else {
      return NSColor(
        srgbRed: color.red,
        green: color.green,
        blue: color.blue,
        alpha: 1
      )
    }

    var readableScale = 0.0
    var unreadableScale = 1.0
    for _ in 0..<14 {
      let candidateScale = (readableScale + unreadableScale) / 2
      let candidate = (
        red: color.red * candidateScale,
        green: color.green * candidateScale,
        blue: color.blue * candidateScale
      )
      if contrastRatio(candidate, background) >= 4.5 {
        readableScale = candidateScale
      } else {
        unreadableScale = candidateScale
      }
    }
    return NSColor(
      srgbRed: color.red * readableScale,
      green: color.green * readableScale,
      blue: color.blue * readableScale,
      alpha: 1
    )
  }

  private static func contrastRatio(
    _ foreground: (red: Double, green: Double, blue: Double),
    _ background: (red: Double, green: Double, blue: Double)
  ) -> Double {
    let lighter = max(
      relativeLuminance(foreground),
      relativeLuminance(background)
    )
    let darker = min(
      relativeLuminance(foreground),
      relativeLuminance(background)
    )
    return (lighter + 0.05) / (darker + 0.05)
  }

  private static func relativeLuminance(
    _ color: (red: Double, green: Double, blue: Double)
  ) -> Double {
    func linearized(_ component: Double) -> Double {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearized(color.red)
      + 0.7152 * linearized(color.green)
      + 0.0722 * linearized(color.blue)
  }
}

struct EVEEntityLabel: View {
  let value: String
  var font: AppFont = .body.weight(.semibold)
  var lineLimit: Int? = nil

  @AppStorage(
    EVEEntityAppearance.colorStorageKey,
    store: AppDefaults.store
  )
  private var colorHex = EVEEntityAppearance.defaultColorHex

  var body: some View {
    Text(verbatim: value)
      .appFont(font)
      .foregroundStyle(EVEEntityAppearance.color(from: colorHex))
      .lineLimit(lineLimit)
  }
}

enum EVETypeImageURL {
  static func icon(typeID: Int64) -> URL? {
    guard typeID > 0 else { return nil }
    return URL(
      string:
        "https://images.evetech.net/types/\(typeID)/icon?size=64&tenant=tranquility"
    )
  }

  static func render(typeID: Int64) -> URL? {
    guard typeID > 0 else { return nil }
    return URL(
      string:
        "https://images.evetech.net/types/\(typeID)/render?size=64&tenant=tranquility"
    )
  }
}

enum EVETypeImageKind {
  case icon
  case render
}

struct EVEItemIcon: View {
  let typeID: Int64
  var size: CGFloat = 22
  var imageKind: EVETypeImageKind = .icon

  var body: some View {
    Group {
      if imageKind == .render,
        let renderURL = EVETypeImageURL.render(typeID: typeID)
      {
        remoteImage(
          url: renderURL,
          fallbackURL: EVETypeImageURL.icon(typeID: typeID)
        )
      } else if let iconURL = EVETypeImageURL.icon(typeID: typeID) {
        remoteImage(url: iconURL, fallbackURL: nil)
      } else {
        fallbackIcon(systemName: "photo.badge.exclamationmark")
      }
    }
    .frame(width: size, height: size)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.18)))
    .overlay {
      RoundedRectangle(cornerRadius: max(3, size * 0.18))
        .stroke(DesignTokens.border.opacity(0.7), lineWidth: 0.5)
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func remoteImage(url: URL, fallbackURL: URL?) -> some View {
    AsyncImage(url: url) { phase in
      switch phase {
      case .success(let image):
        image
          .resizable()
          .scaledToFit()
      case .failure:
        if let fallbackURL {
          AsyncImage(url: fallbackURL) { fallbackPhase in
            switch fallbackPhase {
            case .success(let fallbackImage):
              fallbackImage
                .resizable()
                .scaledToFit()
            case .failure:
              fallbackIcon(systemName: "photo.badge.exclamationmark")
            case .empty:
              fallbackIcon(systemName: "shippingbox")
            @unknown default:
              fallbackIcon(systemName: "shippingbox")
            }
          }
        } else {
          fallbackIcon(systemName: "photo.badge.exclamationmark")
        }
      case .empty:
        fallbackIcon(systemName: "shippingbox")
      @unknown default:
        fallbackIcon(systemName: "shippingbox")
      }
    }
  }

  private func fallbackIcon(systemName: String) -> some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .padding(size * 0.2)
      .foregroundStyle(DesignTokens.textSecondary)
  }
}

struct EVEItemText: View {
  let value: String
  let typeID: Int64
  var font: AppFont = .body.weight(.semibold)
  var lineLimit: Int? = nil
  var iconSize: CGFloat = 22
  var imageKind: EVETypeImageKind = .icon
  var accessibilityIdentifier: String? = nil
  /// The stock history link beside the name (owner rule 09.11.2026). Off
  /// only where an enclosing control owns the click (search results), in
  /// the history itself, or where the screen places the shared button itself.
  var showsMarketStockHistory = true
  /// The build link (hammer) after the history link (owner rule
  /// 09.11.2026); it appears only for types the Planner can build and never
  /// inside the Planner. Off where an enclosing control owns the click
  /// (search results) or where the screen places the shared button itself.
  var showsPlannerBuild = true

  var body: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      EVEItemIcon(typeID: typeID, size: iconSize, imageKind: imageKind)
      EVEEntityText(
        value: value,
        font: font,
        lineLimit: lineLimit,
        accessibilityIdentifier: accessibilityIdentifier
      )
      if showsMarketStockHistory {
        MarketStockHistoryButton(typeID: typeID, name: value)
      }
      if showsPlannerBuild {
        PlannerBuildButton(typeID: typeID, name: value)
      }
    }
  }
}

enum AppTableSortDirection: String, Sendable {
  case ascending
  case descending

  var toggled: Self { self == .ascending ? .descending : .ascending }

  var symbolName: String {
    self == .ascending ? "chevron.up" : "chevron.down"
  }

  var accessibilityValue: LocalizedStringKey {
    self == .ascending ? "Ascending" : "Descending"
  }

  func orders<Value: Comparable>(_ lhs: Value, before rhs: Value) -> Bool {
    self == .ascending ? lhs < rhs : lhs > rhs
  }
}

struct AppTableSortDescriptor<Column: Hashable>: Equatable {
  var column: Column
  var direction: AppTableSortDirection

  mutating func activate(
    _ selectedColumn: Column,
    defaultDirection: AppTableSortDirection = .ascending
  ) {
    if column == selectedColumn {
      direction = direction.toggled
    } else {
      column = selectedColumn
      direction = defaultDirection
    }
  }
}

struct SortableTableHeader<Column: Hashable>: View {
  let title: LocalizedStringKey
  let column: Column
  @Binding var sort: AppTableSortDescriptor<Column>
  var defaultDirection: AppTableSortDirection = .ascending
  var alignment: Alignment = .leading

  var body: some View {
    Button {
      sort.activate(column, defaultDirection: defaultDirection)
    } label: {
      HStack(spacing: 3) {
        Text(title)
        if sort.column == column {
          Image(systemName: sort.direction.symbolName)
            .appFont(.caption2)
        }
      }
      .frame(maxWidth: .infinity, alignment: alignment)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityHint("Sort this table column. Activate again to reverse the order.")
    .accessibilityValue(
      sort.column == column
        ? Text(sort.direction.accessibilityValue)
        : Text("Not sorted")
    )
  }
}

struct EVEEntityText: View {
  let value: String
  var font: AppFont = .body.weight(.semibold)
  var lineLimit: Int? = nil
  var showsTransparentLabel = false
  var accessibilityIdentifier: String? = nil
  /// Non-name copy targets (for example a Slack offer) keep the shared copy
  /// feedback but describe what is copied.
  var copyAccessibilityLabel: LocalizedStringKey = "Copy EVE name"
  var copyAccessibilityHint: LocalizedStringKey =
    "Copies the displayed EVE name to the clipboard."

  @State private var copySucceeded: Bool?
  @State private var feedbackTask: Task<Void, Never>?

  var body: some View {
    Button(action: copyValue) {
      if showsTransparentLabel {
        Text(verbatim: value)
          .appFont(font)
          .foregroundStyle(Color.clear)
          .lineLimit(lineLimit)
          .contentShape(Rectangle())
      } else {
        EVEEntityLabel(value: value, font: font, lineLimit: lineLimit)
          .contentShape(Rectangle())
      }
    }
    .buttonStyle(.plain)
    .help(AppLocalization.format("Click to copy %@.", value))
    .accessibilityLabel(copyAccessibilityLabel)
    .accessibilityValue(Text(verbatim: value))
    .accessibilityHint(copyAccessibilityHint)
    .accessibilityIdentifier(accessibilityIdentifier ?? "eve-entity.copy")
    .popover(isPresented: feedbackBinding, arrowEdge: .bottom) {
      Label(
        copySucceeded == true
          ? "Copied to clipboard."
          : "Could not copy to clipboard.",
        systemImage: copySucceeded == true
          ? "checkmark.circle.fill" : "xmark.circle.fill"
      )
      .foregroundStyle(
        copySucceeded == true ? DesignTokens.positive : DesignTokens.negative
      )
      .padding(DesignTokens.spacingMD)
      .fixedSize()
      .accessibilityIdentifier("eve-entity.copy.feedback")
      .appLanguageLocale()
    }
    .onDisappear {
      feedbackTask?.cancel()
      feedbackTask = nil
    }
  }

  private var feedbackBinding: Binding<Bool> {
    Binding(
      get: { copySucceeded != nil },
      set: { isPresented in
        guard !isPresented else { return }
        copySucceeded = nil
        feedbackTask?.cancel()
        feedbackTask = nil
      }
    )
  }

  private func copyValue() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    copySucceeded = pasteboard.setString(value, forType: .string)
    feedbackTask?.cancel()
    feedbackTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.8))
      guard !Task.isCancelled else { return }
      copySucceeded = nil
      feedbackTask = nil
    }
  }
}

struct Panel<Content: View>: View {
  let title: LocalizedStringKey
  let fillsAvailableHeight: Bool
  @ViewBuilder var content: Content

  init(
    title: LocalizedStringKey,
    fillsAvailableHeight: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.fillsAvailableHeight = fillsAvailableHeight
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      NexusPanelTitle(title)
      content
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: fillsAvailableHeight ? .infinity : nil,
      alignment: .topLeading
    )
    .padding(DesignTokens.spacingMD)
    .nexusPanelSurface(.standard)
  }
}

struct FullWidthDisclosureButton<Label: View>: View {
  let isExpanded: Bool
  let action: () -> Void
  var fillsAvailableHeight = false
  @ViewBuilder let label: Label

  var body: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.18), action)
    } label: {
      HStack(spacing: DesignTokens.spacingSM) {
        label
        Spacer(minLength: DesignTokens.spacingSM)
        Image(systemName: "chevron.right")
          .appFont(.caption.bold())
          .foregroundStyle(DesignTokens.textSecondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(
      maxWidth: .infinity,
      maxHeight: fillsAvailableHeight ? .infinity : nil,
      alignment: .topLeading
    )
    .contentShape(Rectangle())
    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
  }
}

struct FullWidthDisclosure<Label: View, Content: View>: View {
  @Binding var isExpanded: Bool
  @ViewBuilder let label: Label
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      FullWidthDisclosureButton(
        isExpanded: isExpanded,
        action: { isExpanded.toggle() }
      ) {
        label
      }
      if isExpanded {
        content
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

/// One compact row of the sidebar card "Automatic data". In the narrow
/// sidebar the detail moves below the title instead of being truncated.
struct AutomaticStatusRow: View {
  let title: LocalizedStringKey
  let detail: String
  let systemImage: String
  let color: Color
  let progress: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: DesignTokens.spacingSM) {
          icon
          titleText
          Spacer(minLength: DesignTokens.spacingXS)
          detailText
        }
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingSM) {
          icon
          VStack(alignment: .leading, spacing: 1) {
            titleText
            detailText
          }
        }
      }
      if let progress {
        ProgressView(value: progress)
          .tint(color)
          .controlSize(.mini)
      }
    }
  }

  private var icon: some View {
    Image(systemName: systemImage)
      .foregroundStyle(color)
      .frame(width: 16)
  }

  private var titleText: some View {
    Text(title)
      .appFont(.caption.weight(.semibold))
      .lineLimit(1)
  }

  private var detailText: some View {
    Text(detail.localizedUI)
      .appFont(.caption.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
      .lineLimit(1)
  }
}

/// Startup-load rows of the sidebar card "Automatic data". Observes the
/// runtime-owned load so phase changes refresh only this section.
/// Combined ESI status of the Dashboard header with the single sources in a
/// popover (plan DB5). It observes the startup load like the sidebar status.
struct DashboardHeaderStatusButton: View {
  struct Inputs {
    let isRefreshingCharacters: Bool
    let characterResult: CharacterBatchSyncResult?
    let lastSyncDates: [Date?]
    let walletFreshness: DataFreshness
    let characterCount: Int
    let isRefreshingWallets: Bool
    let walletSyncDates: [Date?]
    let wealthSnapshot: DashboardWealthSnapshot?
    let isRefreshingWealth: Bool
    let wealthHasError: Bool
    let isAnalyzingReactions: Bool
    let reactionMarketStates: [DataFreshness]?
    let reactionHasError: Bool
    let reactionTimestamp: Date?
    let isRefreshingMoon: Bool
    let moonMarketStates: [DataFreshness]?
    let moonHasError: Bool
    let moonTimestamp: Date?
    let isRefreshingMinerals: Bool
    let mineralMarketStates: [DataFreshness]?
    let mineralHasError: Bool
    let mineralTimestamp: Date?
  }

  @ObservedObject var startupLoad: StartupDataLoad
  let inputs: Inputs
  @State private var showsSources = false

  var summary: DashboardStatusSummary {
    let phase = startupLoad.phase
    let analyses = [
      StartupDataStatusProjector.analysis(
        area: .reactions,
        phase: phase,
        isRefreshing: inputs.isAnalyzingReactions,
        marketStates: inputs.reactionMarketStates,
        hasError: inputs.reactionHasError,
        timestamp: inputs.reactionTimestamp
      ),
      StartupDataStatusProjector.analysis(
        area: .moonMaterials,
        phase: phase,
        isRefreshing: inputs.isRefreshingMoon,
        marketStates: inputs.moonMarketStates,
        hasError: inputs.moonHasError,
        timestamp: inputs.moonTimestamp
      ),
      StartupDataStatusProjector.analysis(
        area: .minerals,
        phase: phase,
        isRefreshing: inputs.isRefreshingMinerals,
        marketStates: inputs.mineralMarketStates,
        hasError: inputs.mineralHasError,
        timestamp: inputs.mineralTimestamp
      ),
    ].compactMap(DashboardStatusProjector.analysis)
    return DashboardStatusProjector.summary(
      [
        DashboardStatusProjector.characters(
          phase: phase,
          isRefreshing: inputs.isRefreshingCharacters,
          result: inputs.characterResult ?? startupLoad.characterResult,
          lastSyncDates: inputs.lastSyncDates
        ),
        DashboardStatusProjector.wallets(
          freshness: inputs.walletFreshness,
          characterCount: inputs.characterCount,
          isRefreshing: inputs.isRefreshingWallets,
          lastSyncDates: inputs.walletSyncDates
        ),
        DashboardStatusProjector.netWorth(
          snapshot: inputs.wealthSnapshot,
          isRefreshing: inputs.isRefreshingWealth,
          hasError: inputs.wealthHasError
        ),
      ] + analyses
    )
  }

  var body: some View {
    let summary = summary
    let color = StartupDataStatusSection.color(for: summary.status)
    Button {
      showsSources.toggle()
    } label: {
      HStack(spacing: DesignTokens.spacingXS) {
        Image(systemName: Self.symbol(for: summary.status))
          .foregroundStyle(color)
        Text(verbatim: "ESI")
          .fontWeight(.semibold)
          .foregroundStyle(color)
        Text(Self.stateText(summary.status))
          .fontWeight(.semibold)
          .foregroundStyle(color)
        if let timestamp = summary.oldestTimestamp {
          Text(AppLocalization.format("As of %@", Self.timeText(timestamp)))
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .appFont(.caption)
      .padding(.horizontal, 10)
      .frame(minHeight: 28)
      .background(DesignTokens.panel)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
      .overlay {
        RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
          .stroke(DesignTokens.border)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Show the state of every data source.")
    .accessibilityLabel(
      Text(verbatim: "ESI \(Self.stateText(summary.status))")
    )
    .accessibilityHint("Show the state of every data source.")
    .accessibilityIdentifier("dashboard.esi-status")
    .popover(isPresented: $showsSources, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text("Data sources").appFont(.headline)
        ForEach(summary.sources) { source in
          AutomaticStatusRow(
            title: source.area.title,
            detail: Self.detail(for: source),
            systemImage: source.area.systemImage,
            color: StartupDataStatusSection.color(for: source.status),
            progress: nil
          )
        }
        Text("The status combines these sources; its time is the oldest source.")
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(DesignTokens.spacingMD)
      .frame(width: 340)
      .accessibilityIdentifier("dashboard.esi-status.sources")
      .appLanguageLocale()
    }
  }

  static func stateText(_ status: StartupDataStatus) -> String {
    switch status {
    case .waiting: AppLocalization.text("Waiting")
    case .running: AppLocalization.text("Updating")
    case .known(let freshness): StartupDataStatusSection.freshnessText(freshness)
    }
  }

  static func symbol(for status: StartupDataStatus) -> String {
    switch status {
    case .waiting: "clock"
    case .running: "arrow.triangle.2.circlepath"
    case .known(.fresh): "checkmark.circle.fill"
    case .known(.partial), .known(.stale): "exclamationmark.triangle.fill"
    case .known(.forbidden), .known(.unavailable): "xmark.octagon.fill"
    }
  }

  /// Time only for today, otherwise date and time, in the app language.
  static func timeText(
    _ date: Date,
    locale: Locale = AppLocalization.currentLanguage.locale
  ) -> String {
    Calendar.current.isDateInToday(date)
      ? date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
      : date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
  }

  static func detail(for source: DashboardSourceStatus) -> String {
    let state = stateText(source.status)
    guard let timestamp = source.timestamp else { return state }
    return AppLocalization.format("%@ · %@", state, timeText(timestamp))
  }
}

struct StartupDataStatusSection: View {
  struct Inputs {
    let lastSyncDates: [Date?]
    let warehouseObservations: [StartupDataStatusProjector.SourceObservation]
    let isAnalyzingReactions: Bool
    let reactionMarketStates: [DataFreshness]?
    let reactionHasError: Bool
    let reactionTimestamp: Date?
    let isRefreshingMoon: Bool
    let moonMarketStates: [DataFreshness]?
    let moonHasError: Bool
    let moonTimestamp: Date?
    let isRefreshingMinerals: Bool
    let mineralMarketStates: [DataFreshness]?
    let mineralHasError: Bool
    let mineralTimestamp: Date?
  }

  @ObservedObject var startupLoad: StartupDataLoad
  let inputs: Inputs

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("App start")
        .appFont(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
      ForEach(rows) { row in
        AutomaticStatusRow(
          title: row.area.title,
          detail: Self.detail(for: row),
          systemImage: row.area.systemImage,
          color: Self.color(for: row.status),
          progress: nil
        )
        if row.area == .characters,
          let groups = startupLoad.characterResult?.failureGroups,
          !groups.isEmpty
        {
          characterFailureReasons(groups)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.startup-data-status")
  }

  var rows: [StartupDataStatusRow] {
    let phase = startupLoad.phase
    return [
      StartupDataStatusProjector.characters(
        phase: phase,
        result: startupLoad.characterResult,
        lastSyncDates: inputs.lastSyncDates
      ),
      StartupDataStatusProjector.warehouseAndBlueprints(
        phase: phase,
        characterCount: inputs.lastSyncDates.count,
        observations: inputs.warehouseObservations
      ),
      StartupDataStatusProjector.analysis(
        area: .reactions,
        phase: phase,
        isRefreshing: inputs.isAnalyzingReactions,
        marketStates: inputs.reactionMarketStates,
        hasError: inputs.reactionHasError,
        timestamp: inputs.reactionTimestamp
      ),
      StartupDataStatusProjector.analysis(
        area: .moonMaterials,
        phase: phase,
        isRefreshing: inputs.isRefreshingMoon,
        marketStates: inputs.moonMarketStates,
        hasError: inputs.moonHasError,
        timestamp: inputs.moonTimestamp
      ),
      StartupDataStatusProjector.analysis(
        area: .minerals,
        phase: phase,
        isRefreshing: inputs.isRefreshingMinerals,
        marketStates: inputs.mineralMarketStates,
        hasError: inputs.mineralHasError,
        timestamp: inputs.mineralTimestamp
      ),
    ]
  }

  /// Why characters failed at app start, grouped by identical reason.
  private func characterFailureReasons(
    _ groups: [(reason: String, characterNames: [String])]
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
        VStack(alignment: .leading, spacing: 1) {
          Text(group.reason)
            .foregroundStyle(DesignTokens.negative)
          LazyVGrid(
            columns: [
              GridItem(
                .adaptive(minimum: 90),
                spacing: DesignTokens.spacingXS,
                alignment: .leading
              )
            ],
            alignment: .leading,
            spacing: 1
          ) {
            ForEach(group.characterNames, id: \.self) { name in
              EVEEntityText(value: name, font: .caption2, lineLimit: 1)
            }
          }
        }
      }
    }
    .appFont(.caption2)
    .padding(.leading, 24)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("dashboard.startup-data-status.character-failures")
  }

  static func detail(for row: StartupDataStatusRow) -> String {
    let state: String
    switch row.status {
    case .waiting: state = AppLocalization.text("Waiting")
    case .running: state = AppLocalization.text("Running")
    case .known(let freshness): state = freshnessText(freshness)
    }
    guard let timestamp = row.timestamp else { return state }
    return AppLocalization.format(
      "%@ · %@",
      state,
      timestamp.formatted(date: .omitted, time: .shortened)
    )
  }

  static func freshnessText(_ freshness: DataFreshness) -> String {
    switch freshness {
    case .fresh: AppLocalization.text("Fresh")
    case .partial: AppLocalization.text("Partial")
    case .stale: AppLocalization.text("Stale")
    case .forbidden: AppLocalization.text("Forbidden")
    case .unavailable: AppLocalization.text("Unavailable")
    }
  }

  static func color(for status: StartupDataStatus) -> Color {
    switch status {
    case .waiting: DesignTokens.textSecondary
    case .running: DesignTokens.accent
    case .known(.fresh): DesignTokens.positive
    case .known(.partial), .known(.stale): DesignTokens.caution
    case .known(.forbidden), .known(.unavailable): DesignTokens.negative
    }
  }
}
