import AppKit
import Combine
import EVENexusCore
import SwiftData
import SwiftUI

enum NavigationSection: String, CaseIterable, Identifiable {
  case dashboard
  case planner
  case manufacturingOpportunities
  case publicContracts
  case reactions
  case moonMaterialAnalysis
  case mineralPurchaseAnalysis
  case items
  case warehouse
  case blueprints
  case productionBook
  case wallet
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
    case .publicContracts: "Public Contracts"
    case .reactions: "Reactions"
    case .moonMaterialAnalysis: "Moon purchase analysis"
    case .mineralPurchaseAnalysis: "Mineral purchase analysis"
    case .items: "All items"
    case .warehouse: "Warehouse"
    case .blueprints: "Blueprints"
    case .productionBook: "Production Overview"
    case .wallet: "Wallet"
    case .netWorth: "Net Worth"
    case .data: "Data & Settings"
    }
  }

  var icon: String {
    switch self {
    case .dashboard: "gauge.with.dots.needle.67percent"
    case .planner: "hammer.fill"
    case .manufacturingOpportunities: "chart.line.uptrend.xyaxis"
    case .publicContracts: "doc.text.magnifyingglass"
    case .reactions: "atom"
    case .moonMaterialAnalysis: "chart.xyaxis.line"
    case .mineralPurchaseAnalysis: "circle.grid.3x3.fill"
    case .items: "square.grid.2x2.fill"
    case .warehouse: "shippingbox.fill"
    case .blueprints: "doc.on.doc.fill"
    case .productionBook: "books.vertical.fill"
    case .wallet: "creditcard.fill"
    case .netWorth: "chart.line.uptrend.xyaxis"
    case .data: "externaldrive.fill"
    }
  }
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

  init(
    id: UUID = UUID(),
    productTypeID: Int64,
    productName: String,
    requestedRuns: Int,
    wantedQuantity: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    blueprintSupplyPlans: [BlueprintSupplyPlan] = [],
    sourceSnapshotIDs: [UUID] = []
  ) {
    self.id = id
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
  static func requiresExplicitChoice(
    currentInput: String,
    hasCalculatedPlan: Bool
  ) -> Bool {
    hasCalculatedPlan
      || !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    timeEfficiency: Int
  ) -> PlannerLaunchRequest {
    PlannerLaunchRequest(
      productTypeID: productTypeID,
      productName: productName,
      requestedRuns: requestedRuns,
      wantedQuantity: wantedQuantity,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency
    )
  }
}

struct ContentView: View {
  @EnvironmentObject private var consolidation: ConsolidationController
  @State private var consolidationArea: ConsolidationArea?
  let runtime: RuntimeState
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var storedCharacters: [StoredCharacter]
  @State private var selection: NavigationSection? = .dashboard
  @State private var dataSettingsSelection: DataSettingsSection = .general
  @State private var historicalPlannerRequest: HistoricalPlannerRequest?
  @State private var plannerLaunchRequest: PlannerLaunchRequest?
  @State private var didPreparePlannerConfiguration = false
  @StateObject private var profileNavigationGuard =
    ProfileNavigationGuard()

  var body: some View {
    NavigationSplitView {
      List(selection: guardedSelection) {
        Section("Established workflows") {
          ForEach(NavigationSection.establishedCases) { item in
            Label(item.title, systemImage: item.icon)
              .tag(item)
              .accessibilityIdentifier("navigation.\(item.rawValue)")
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
            DashboardView()
          case .planner:
            PlannerView(
              historicalPlannerRequest: $historicalPlannerRequest,
              launchRequest: $plannerLaunchRequest,
              runtime: runtime
            )
          case .manufacturingOpportunities:
            ManufacturingOpportunitiesView { request in
              historicalPlannerRequest = nil
              plannerLaunchRequest = request
              selection = .planner
            }
          case .publicContracts:
            PublicContractsView()
          case .reactions:
            ReactionsView()
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
          case .wallet:
            WalletView()
          case .netWorth:
            NetWorthView()
          case .data:
            DataSettingsWorkspace(
              selection: guardedDataSettingsSelection
            )
          }
        }
        .background(DesignTokens.canvas)
      }
    }
    .toolbar {
      if selection != .planner {
        if selection == .warehouse { Button("Manuelle Lager") { consolidationArea = .warehouses } }
        if selection == .blueprints {
          Button("Wissenschaftsaufträge") { consolidationArea = .science }
        }
        if selection == .productionBook { Button("Verkaufsbelege") { consolidationArea = .sales } }
      }
    }
    .sheet(item: $consolidationArea) { area in ConsolidationWorkbenchView(area: area) }
    .navigationSplitViewStyle(.balanced)
    .tint(DesignTokens.accent)
    .frame(minWidth: 640, minHeight: 480)
    .environmentObject(profileNavigationGuard)
    .task {
      guard !didPreparePlannerConfiguration else { return }
      didPreparePlannerConfiguration = true
      await runtime.preparePlannerConfiguration(
        encodedBasis: storedBases.first?.encodedBasis,
        capabilities: storedCharacters.compactMap { character in
          character.capabilitySnapshot.flatMap {
            try? JSONDecoder().decode(
              CharacterCapabilitySnapshot.self,
              from: $0
            )
          }
        }
      )
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

  private func openHistoricalPlan(_ row: StoredProductionOverviewRow) {
    historicalPlannerRequest = HistoricalPlannerRequest(
      productionOverviewRowID: row.id
    )
    selection = .planner
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

struct PublicContractSidebarStatus: View {
  @ObservedObject var runtime: RuntimeState

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
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
      Text(statusText)
        .font(.caption2)
        .foregroundStyle(statusDetailColor)
        .fixedSize(horizontal: false, vertical: true)
      if let progressFraction = presentation.progressFraction {
        ProgressView(value: progressFraction)
          .tint(DesignTokens.accent)
          .controlSize(.mini)
      }
      Text(progressText)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      action
        .font(.caption)
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

private enum DashboardWealthSeries: String, CaseIterable, Identifiable {
  case total
  case wallet
  case assets
  case industryInProgress

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .total: "Total"
    case .wallet: "Wallet"
    case .assets: "Assets"
    case .industryInProgress: "In production"
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

struct DashboardView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \AppSetting.key)
  private var settings: [AppSetting]
  @State private var blueprintNames: [Int64: String] = [:]
  @State private var industrySnapshot = DashboardIndustrySnapshot.empty
  @State private var wealthPersistenceError: String?
  @State private var isRefreshingDashboardData = false
  @State private var dashboardDataRefreshMessage: String?
  @State private var dashboardDataRefreshError: String?
  @State private var hasFinishedDashboardStartupRefresh = false
  @State private var selectedDashboardWealthSeries: DashboardWealthSeries = .total
  @AppStorage(
    "dashboard.reaction-opportunity-groups",
    store: AppDefaults.store
  )
  private var encodedReactionGroups = "[]"
  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          header
          dashboardSection(
            title: "Industry & jobs",
            systemImage: "hammer.fill"
          ) {
            jobCapacityPanel(now: context.date)
            dashboardPairedRow {
              readyJobsPanel(now: context.date)
              upcomingJobsPanel(now: context.date)
            }
          }
          dashboardSection(
            title: "Finances",
            systemImage: "creditcard.fill"
          ) {
            dashboardPairedRow {
              walletPanel
              netWorthPanel
            }
          }
          dashboardSection(
            title: "Market & opportunities",
            systemImage: "chart.line.uptrend.xyaxis"
          ) {
            mineralTickerPanel
            reactionOpportunityPanel
          }
        }
        .frame(maxWidth: 1_440, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(DesignTokens.spacingLG)
      }
    }
    .navigationTitle(AppLocalization.text("Dashboard"))
    .task(id: dashboardIndustryRefreshIdentity) {
      let inputs = dashboardIndustryInputs
      let prepared = await Task.detached(priority: .utility) {
        DashboardIndustrySnapshotBuilder.build(inputs: inputs)
      }.value
      guard !Task.isCancelled else { return }
      industrySnapshot = prepared
      blueprintNames = await runtime.resolveAssetTypeNames(prepared.jobTypeIDs)
      if runtime.mineralPriceTickerState == nil {
        await runtime.refreshMineralPriceTicker()
      }
    }
    .task(id: wealthInputIdentity) {
      guard hasFinishedDashboardStartupRefresh else { return }
      await runtime.refreshDashboardWealth(inputs: wealthInputs)
      if runtime.dashboardWealthError == nil,
        let snapshot = runtime.dashboardWealthSnapshot
      {
        persistWealthSnapshot(snapshot)
      }
    }
    .task(id: mainHubAutomationIdentity) {
      runtime.prepareMainHubMarketAutomation()
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

  private func dashboardSection<Content: View>(
    title: LocalizedStringKey,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Label(title, systemImage: systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(DesignTokens.textPrimary)
        .accessibilityAddTraits(.isHeader)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func dashboardPairedRow<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(minimum: 360),
          spacing: DesignTokens.spacingMD,
          alignment: .top
        )
      ],
      alignment: .leading,
      spacing: DesignTokens.spacingMD
    ) {
      content()
    }
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
        dashboardHeading
        Spacer(minLength: DesignTokens.spacingMD)
        automaticDataStatus
      }
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        dashboardHeading
        automaticDataStatus
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var dashboardHeading: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Dashboard")
        .font(.largeTitle.bold())
      Text("Operations, finances and market movement at a glance.")
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var automaticDataStatus: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        Text("Automatic data")
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1.1)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
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
        .help("Automatic data options")
        .accessibilityLabel("Automatic data options")
      }
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
      Text("Market analyses")
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(DesignTokens.spacingSM)
    .frame(
      minWidth: 260,
      idealWidth: 340,
      maxWidth: 340,
      alignment: .leading
    )
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .shadow(
      color: DesignTokens.panelShadow,
      radius: DesignTokens.panelShadowRadius,
      y: DesignTokens.panelShadowOffset
    )
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dashboard.automatic-data-status")
  }

  private func automaticStatusRow(
    title: LocalizedStringKey,
    detail: String,
    systemImage: String,
    color: Color,
    progress: Double?
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: DesignTokens.spacingSM) {
        Image(systemName: systemImage)
          .foregroundStyle(color)
          .frame(width: 16)
        Text(title)
          .font(.caption.weight(.semibold))
        Spacer()
        Text(detail.localizedUI)
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
          .lineLimit(1)
      }
      if let progress {
        ProgressView(value: progress)
          .tint(color)
          .controlSize(.mini)
      }
    }
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

  private var mineralTickerPanel: some View {
    Panel(title: "Mineral prices") {
      HStack {
        Text(
          AppLocalization.format(
            "Daily regional average · %@",
            mineralRegionName
          )
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if runtime.isRefreshingMineralPrices {
          ProgressView().controlSize(.small)
        }
        Button {
          Task { await runtime.refreshMineralPriceTicker() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(runtime.isRefreshingMineralPrices)
        .help("Refresh mineral prices")
        .accessibilityLabel("Refresh mineral prices")
      }
      if let rows = runtime.mineralPriceTickerState?.value, !rows.isEmpty {
        DashboardMineralTicker(rows: rows)
          .frame(height: 46)
        sourceStateLine(runtime.mineralPriceTickerState?.state)
      } else {
        Label(
          "No mineral market history is available.",
          systemImage: "chart.line.downtrend.xyaxis"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func jobCapacityPanel(now: Date) -> some View {
    let running = industrySnapshot.jobs.filter { $0.job.isRunning(at: now) }
    let overall = industrySnapshot.overallCapacity
    return Panel(title: "Industry capacity") {
      HStack(alignment: .firstTextBaseline) {
        Text("\(running.count)")
          .font(.largeTitle.bold().monospacedDigit())
          .foregroundStyle(DesignTokens.highlight)
        Text("of")
          .foregroundStyle(DesignTokens.textSecondary)
        Text(capacityText(overall))
          .font(.title2.bold().monospacedDigit())
        Text("available job slots active")
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if !overall.isComplete {
          freshnessPill(.partial, text: "Partial")
        }
      }
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
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(activityRunning)")
              .font(.title2.bold().monospacedDigit())
            Text("/ \(capacityText(capacity))")
              .font(.callout.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
          if activity.usesSharedScienceSlots {
            Text("Shared science slots")
              .font(.caption2)
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
    Panel(title: "Wallet", fillsAvailableHeight: true) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text(
            walletPortfolio.includedCharacterCount > 0
              ? formatISK(walletPortfolio.totalBalance)
              : AppLocalization.text("Unavailable")
          )
          .font(.largeTitle.weight(.semibold).monospacedDigit())
          .foregroundStyle(
            walletPortfolio.includedCharacterCount > 0
              ? DesignTokens.highlight : DesignTokens.textSecondary
          )
          Text(
            AppLocalization.format(
              "%lld of %lld characters included",
              Int64(walletPortfolio.includedCharacterCount),
              Int64(walletPortfolio.totalCharacterCount)
            )
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
          freshnessPill(walletPortfolio.freshness)
          Button {
            Task { await refreshDashboardData(isStartup: false) }
          } label: {
            if isRefreshingDashboardData {
              ProgressView().controlSize(.small)
            } else {
              Label("Refresh dashboard", systemImage: "arrow.clockwise")
            }
          }
          .buttonStyle(.bordered)
          .disabled(isRefreshingDashboardData || characters.isEmpty)
          .accessibilityIdentifier("dashboard.refresh")
        }
      }
      Divider()
      ForEach(walletPortfolio.balances) { row in
        HStack {
          EVEEntityText(
            value: row.character.name,
            font: .callout.weight(.semibold)
          )
          Spacer()
          Text(
            row.balance.value.map(formatISK)
              ?? AppLocalization.text("Unavailable")
          )
          .font(.callout.monospacedDigit())
          .foregroundStyle(
            row.balance.value == nil
              ? DesignTokens.textSecondary : DesignTokens.textPrimary
          )
        }
      }
      if walletPortfolio.includedCharacterCount < walletPortfolio.totalCharacterCount {
        Text("Missing or forbidden balances are not treated as zero.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if let dashboardDataRefreshMessage {
        Label(dashboardDataRefreshMessage, systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.positive)
      }
      if let dashboardDataRefreshError {
        Label(dashboardDataRefreshError, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private func readyJobsPanel(now: Date) -> some View {
    let ready = industrySnapshot.jobs.filter {
      $0.job.isReadyForDelivery(at: now)
    }
    .sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    return Panel(title: "Ready for delivery", fillsAvailableHeight: true) {
      if isPreparingIndustrySnapshot {
        Label("Preparing", systemImage: "hourglass")
          .foregroundStyle(DesignTokens.textSecondary)
      } else if ready.isEmpty {
        Label(
          industrySnapshot.hasAnyJobSnapshot
            ? "No jobs are currently ready for delivery."
            : "Synchronize characters to load industry jobs.",
          systemImage:
            industrySnapshot.hasAnyJobSnapshot
            ? "checkmark.circle" : "arrow.triangle.2.circlepath"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ForEach(ready.prefix(12)) { owned in
          dashboardJobRow(owned, trailing: AppLocalization.text("Ready"))
        }
      }
    }
  }

  private func upcomingJobsPanel(now: Date) -> some View {
    let cutoff = now.addingTimeInterval(48 * 60 * 60)
    let upcoming = industrySnapshot.jobs.filter {
      $0.job.isRunning(at: now) && $0.job.endDate <= cutoff
    }.sorted { $0.job.endDate < $1.job.endDate }
    return Panel(title: "Next 48 hours", fillsAvailableHeight: true) {
      if isPreparingIndustrySnapshot {
        Label("Preparing", systemImage: "hourglass")
          .foregroundStyle(DesignTokens.textSecondary)
      } else if upcoming.isEmpty {
        Label(
          industrySnapshot.hasAnyJobSnapshot
            ? "No running jobs finish within the next 48 hours."
            : "Synchronize characters to load the next completions.",
          systemImage: "clock"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ForEach(upcoming.prefix(12)) { owned in
          dashboardJobRow(
            owned,
            trailing: owned.job.endDate.formatted(.relative(presentation: .named))
          )
        }
      }
    }
  }

  private var reactionOpportunityPanel: some View {
    Panel(title: "Reaction buy opportunities") {
      HStack {
        Text("Negative value creation means buying is cheaper than reacting.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        reactionFilterMenu
      }
      if runtime.isAnalyzingReactions {
        HStack {
          ProgressView().controlSize(.small)
          Text("Analyzing all reactions…")
        }
      } else if runtime.reactionAnalysis == nil {
        Label(
          "No reaction analysis is loaded.",
          systemImage: "atom"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Button("Analyze all reactions") {
          Task {
            await runtime.analyzeReactions(
              runs: 100,
              marketHub: selectedMarketHub,
              authorizations: authorizationSnapshots,
              clientID: EVEConstants.ssoClientID
            )
          }
        }
        .buttonStyle(.borderedProminent)
      } else if filteredNegativeReactions.isEmpty {
        Label(
          "No negative reactions match the saved filter.",
          systemImage: "checkmark.circle"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ForEach(filteredNegativeReactions.prefix(8)) { row in
          HStack {
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              EVEItemText(
                value: row.productName,
                typeID: row.productTypeID,
                font: .callout.weight(.semibold)
              )
              Text(row.groupName)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
              Text("Buy opportunity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.positive)
              Text(
                row.valueCreation.map { formatISK(abs($0)) }
                  ?? AppLocalization.text("Unavailable")
              )
              .font(.callout.monospacedDigit())
            }
          }
        }
        Text("The selected reaction groups are retained after restart.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var netWorthPanel: some View {
    Panel(title: "Net worth over time", fillsAvailableHeight: true) {
      HStack(alignment: .firstTextBaseline) {
        Text(wealthTotalText)
          .font(.title2.weight(.semibold).monospacedDigit())
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
      if wealthHistory.count > 1 {
        Picker("Displayed history", selection: $selectedDashboardWealthSeries) {
          ForEach(DashboardWealthSeries.allCases) { series in
            Text(series.title).tag(series)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("dashboard.wealth-series")
        DashboardWealthChart(
          samples: wealthHistory.compactMap { snapshot in
            selectedDashboardWealthSeries.value(in: snapshot).map {
              DashboardWealthChartSample(
                date: snapshot.capturedAt,
                value: $0
              )
            }
          },
          color: selectedDashboardWealthSeries.color
        )
        .frame(height: 112)
        .accessibilityLabel("Total net-worth history")
      } else {
        Label(
          "Long-term history starts with the current valuation.",
          systemImage: "clock.arrow.circlepath"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
      if let snapshot = runtime.dashboardWealthSnapshot {
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
        Divider()
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
                .font(.caption)
                .foregroundStyle(DesignTokens.caution)
              }
              if character.excludedBlueprintCopyCount > 0 {
                Text(
                  AppLocalization.format(
                    "%lld BPC stacks are excluded",
                    Int64(character.excludedBlueprintCopyCount)
                  )
                )
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
              }
              if character.unvaluedOrderCount > 0
                || character.missingEscrowOrderCount > 0
              {
                Text("Some active order value is unavailable")
                  .font(.caption)
                  .foregroundStyle(DesignTokens.caution)
              }
              if character.contractsValue == nil
                || character.courierValue == nil
                || character.unvaluedContractItemTypeCount > 0
                || character.unavailableContractCount > 0
                || character.invalidCourierCollateralCount > 0
              {
                Text("Some private contract value is unavailable")
                  .font(.caption)
                  .foregroundStyle(DesignTokens.caution)
              }
            }
            Spacer()
            DashboardWealthChart(
              samples: wealthHistory.compactMap { history in
                history.characters.first {
                  $0.characterID == character.characterID
                }?.knownValue.map {
                  DashboardWealthChartSample(
                    date: history.capturedAt,
                    value: $0
                  )
                }
              },
              color: DesignTokens.accent
            )
            .frame(width: 92, height: 28)
            Text(wealthText(character))
              .font(.callout.weight(.semibold).monospacedDigit())
              .frame(minWidth: 128, alignment: .trailing)
          }
        }
        Text(
          "Assets and own outstanding contract items use ESI average prices with adjusted prices as the visible fallback. Consumed Manufacturing and Reaction materials remain under In production until delivery; missing facility or rig modifiers make that component an explicit estimate. Blueprint copies are excluded; courier collateral is an estimate. Missing personal or accessible corporation values remain partial and are never treated as zero."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
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
          .font(.caption)
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
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
    }
  }

  private var reactionFilterMenu: some View {
    Menu {
      Button("All reaction groups") {
        saveReactionGroups([])
      }
      Divider()
      ForEach(reactionGroups, id: \.self) { group in
        Button {
          toggleReactionGroup(group)
        } label: {
          Label(
            group,
            systemImage: selectedReactionGroups.contains(group)
              ? "checkmark" : "circle"
          )
        }
      }
    } label: {
      Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
    }
    .menuStyle(.borderlessButton)
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
          .font(.caption.weight(.semibold))
      }
      Text(value.map(formatISK) ?? AppLocalization.text("Unavailable"))
        .font(.caption.monospacedDigit())
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
    trailing: String
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      Image(systemName: activityIcon(owned.job.dashboardActivity))
        .foregroundStyle(DesignTokens.accent)
        .frame(width: 18)
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
      Text(trailing)
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
    }
    .accessibilityElement(children: .combine)
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
    .font(.caption)
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

  private var wealthInputs: [DashboardWealthCharacterInput] {
    characters.map { character in
      DashboardWealthCharacterInput(
        character: CharacterIdentity(
          id: character.characterID,
          name: character.characterName,
          corporationID: character.corporationID
        ),
        wallet: storedWalletBalance(character),
        assets: storedAssetSnapshot(character),
        openOrders: storedOpenOrders(character),
        privateContracts: storedPrivateContracts(character),
        corporationAssets: storedCorporationAssetSnapshot(character),
        corporationWallet: storedCorporationWallet(character),
        industryJobs: storedIndustryJobs(character),
        blueprints: storedBlueprintSnapshot(character)
      )
    }
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
    guard
      let encoded = settings.first(where: {
        $0.key == AppSettingKey.dashboardWealthHistory
      })?.value,
      let data = Data(base64Encoded: encoded),
      let history = try? JSONDecoder().decode(
        [DashboardWealthSnapshot].self,
        from: data
      )
    else { return [] }
    return history.sorted { $0.capturedAt < $1.capturedAt }
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

  private func storedAssetSnapshot(
    _ character: StoredCharacter
  ) -> Sourced<AssetSnapshot> {
    if let data = character.assetSnapshot,
      let value = try? JSONDecoder().decode(
        Sourced<AssetSnapshot>.self,
        from: data
      )
    {
      return value
    }
    return Sourced(
      state: .unavailable,
      value: nil,
      source: SourceIdentity(
        provider: "Local",
        version: "not-synchronized",
        capturedAt: character.lastSyncAt ?? .distantPast
      ),
      diagnostics: ["assets.not-synchronized"]
    )
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

    var synchronizedCount = 0
    var failures: [String] = []
    let orderedCharacters = characters.sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    for character in orderedCharacters {
      guard !Task.isCancelled else { return }
      do {
        let authorization = try JSONDecoder().decode(
          AuthorizationSnapshot.self,
          from: character.authorizationSnapshot
        )
        try await runtime.syncCharacter(
          authorization: authorization,
          clientID: EVEConstants.ssoClientID
        )
        guard let latest = runtime.lastCharacterSync,
          latest.authorization.characterID == character.characterID
        else {
          throw ESIError.notFound
        }
        try CharacterSyncPersistence.apply(
          latest,
          to: character,
          in: modelContext
        )
        try modelContext.save()
        synchronizedCount += 1
      } catch {
        modelContext.rollback()
        failures.append(character.characterName)
      }
    }

    if !runtime.isRefreshingDashboardWealth {
      await runtime.refreshDashboardWealth(inputs: wealthInputs)
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
      dashboardDataRefreshError = AppLocalization.format(
        "%lld of %lld characters updated; unavailable characters kept their previous data: %@",
        Int64(synchronizedCount),
        Int64(orderedCharacters.count),
        failures.joined(separator: ", ")
      )
    }
  }

  private func storedWalletBalance(_ character: StoredCharacter) -> Sourced<Double> {
    if let data = character.walletBalanceSnapshot,
      let value = try? JSONDecoder().decode(Sourced<Double>.self, from: data)
    {
      return value
    }
    return Sourced(
      state: .unavailable,
      value: nil,
      source: SourceIdentity(
        provider: "Local",
        version: "not-synchronized",
        capturedAt: character.walletLastSyncAt ?? .distantPast
      ),
      diagnostics: ["wallet.not-synchronized"]
    )
  }

  private func storedOpenOrders(
    _ character: StoredCharacter
  ) -> Sourced<[ESICharacterOrderDTO]> {
    storedSettingSnapshot(
      key: AppSettingKey.openOrders(characterID: character.characterID),
      capturedAt: character.lastSyncAt,
      diagnostic: "orders.not-synchronized"
    )
  }

  private func storedPrivateContracts(
    _ character: StoredCharacter
  ) -> Sourced<PrivateContractSnapshot> {
    storedSettingSnapshot(
      key: AppSettingKey.privateContracts(
        characterID: character.characterID
      ),
      capturedAt: character.lastSyncAt,
      diagnostic: "private-contracts.not-synchronized"
    )
  }

  private func storedIndustryJobs(
    _ character: StoredCharacter
  ) -> Sourced<[ESIIndustryJobDTO]> {
    storedSettingSnapshot(
      key: AppSettingKey.industryJobs(characterID: character.characterID),
      capturedAt: character.lastSyncAt,
      diagnostic: "industry-jobs.not-synchronized"
    )
  }

  private func storedBlueprintSnapshot(
    _ character: StoredCharacter
  ) -> Sourced<[OwnedBlueprintInstance]> {
    guard let data = character.blueprintSnapshot,
      let value = try? JSONDecoder().decode(
        Sourced<[OwnedBlueprintInstance]>.self,
        from: data
      )
    else {
      return unavailableStoredSource(
        capturedAt: character.lastSyncAt,
        diagnostic: "blueprints.not-synchronized"
      )
    }
    return value
  }

  private func storedCorporationWallet(
    _ character: StoredCharacter
  ) -> Sourced<CorporationWalletSnapshot> {
    storedSettingSnapshot(
      key: AppSettingKey.corporationWallet(
        characterID: character.characterID
      ),
      capturedAt: character.lastSyncAt,
      diagnostic: "corporation-wallet.not-synchronized"
    )
  }

  private func storedCorporationAssetSnapshot(
    _ character: StoredCharacter
  ) -> Sourced<AssetSnapshot> {
    if let data = character.corporationAssetSnapshot,
      let value = try? JSONDecoder().decode(
        Sourced<AssetSnapshot>.self,
        from: data
      )
    {
      return value
    }
    return unavailableStoredSource(
      capturedAt: character.lastSyncAt,
      diagnostic: "corporation-assets.not-synchronized"
    )
  }

  private func storedSettingSnapshot<Value: Codable & Sendable>(
    key: String,
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    let persistedValue: String?
    do {
      persistedValue = try modelContext.appSettingValue(for: key)
    } catch {
      persistedValue = nil
    }
    guard
      let encoded = persistedValue
        ?? settings.first(where: { $0.key == key })?.value,
      let data = Data(base64Encoded: encoded),
      let value = try? JSONDecoder().decode(Sourced<Value>.self, from: data)
    else {
      return unavailableStoredSource(
        capturedAt: capturedAt,
        diagnostic: diagnostic
      )
    }
    return value
  }

  private func unavailableStoredSource<Value: Codable & Sendable>(
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    Sourced(
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

  private var filteredNegativeReactions: [ReactionAnalysisRow] {
    guard let rows = runtime.reactionAnalysis?.rows else { return [] }
    let selected = selectedReactionGroups
    return rows.filter {
      guard let value = $0.valueCreation, value.isFinite, value < 0 else {
        return false
      }
      return selected.isEmpty || selected.contains($0.groupName)
    }.sorted {
      ($0.valueCreation ?? 0) < ($1.valueCreation ?? 0)
    }
  }

  private var reactionGroups: [String] {
    Array(Set(runtime.reactionAnalysis?.rows.map(\.groupName) ?? []))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var selectedReactionGroups: Set<String> {
    guard let data = encodedReactionGroups.data(using: .utf8),
      let values = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return Set(values)
  }

  private func toggleReactionGroup(_ group: String) {
    var selected = selectedReactionGroups
    if selected.contains(group) {
      selected.remove(group)
    } else {
      selected.insert(group)
    }
    saveReactionGroups(selected)
  }

  private func saveReactionGroups(_ groups: Set<String>) {
    let values = groups.sorted()
    guard let data = try? JSONEncoder().encode(values),
      let encoded = String(data: data, encoding: .utf8)
    else { return }
    encodedReactionGroups = encoded
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    characters.compactMap {
      try? JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: $0.authorizationSnapshot
      )
    }
  }

  private var selectedMarketHub: MarketHubConfigurationSnapshot {
    runtime.productionBasis.marketHubSnapshots.first {
      $0.roles.contains(.main)
    }
      ?? MarketHubConfigurationSnapshot(
        id: UUID(),
        location: .jita,
        roles: [.main]
      )
  }

  private var mineralRegionName: String {
    runtime.productionBasis.mainTradingLocation?.location.name
      ?? ProcurementLocation.jita.name
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
        .font(.caption)
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
      .font(.caption2.bold())
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .foregroundStyle(color)
      .background(color.opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func formatISK(_ value: Double) -> String {
    value.formatted(
      .currency(code: "ISK").precision(.fractionLength(0))
    )
  }
}

private struct DashboardWealthChartSample {
  let date: Date
  let value: Double
}

private struct DashboardWealthChart: View {
  let samples: [DashboardWealthChartSample]
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let valid = samples.filter { $0.value.isFinite }.sorted {
        $0.date < $1.date
      }
      if valid.count > 1 {
        let values = valid.map(\.value)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        let rawRange = maximum - minimum
        let padding = max(rawRange * 0.12, max(abs(maximum) * 0.005, 1))
        let lower = max(0, minimum - padding)
        let upper = max(lower + 1, maximum + padding)
        let range = upper - lower
        let firstDate = valid[0].date
        let lastDate = valid[valid.count - 1].date
        let duration = max(lastDate.timeIntervalSince(firstDate), 1)
        ZStack(alignment: .bottom) {
          Path { path in
            for (index, sample) in valid.enumerated() {
              let x =
                proxy.size.width
                * CGFloat(sample.date.timeIntervalSince(firstDate) / duration)
              let normalized = (sample.value - lower) / range
              let y = (proxy.size.height - 18) * (1 - CGFloat(normalized))
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
          HStack {
            Text(firstDate.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            Text(lastDate.formatted(date: .abbreviated, time: .omitted))
          }
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      } else if !valid.isEmpty {
        Circle()
          .fill(color)
          .frame(width: 6, height: 6)
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      } else {
        Rectangle().fill(Color.clear)
      }
    }
  }
}

private struct DashboardMineralTicker: View {
  let rows: [MineralPriceTrend]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private let itemWidth: CGFloat = 190
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
  let rows: [MineralPriceTrend]
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
  private var rows: [MineralPriceTrend] = []
  private var itemWidth: CGFloat = 190
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
    rows: [MineralPriceTrend],
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
  let rows: [MineralPriceTrend]
  let repetitions: Int
  let itemWidth: CGFloat

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<(rows.count * repetitions), id: \.self) { index in
        let row = rows[index % rows.count]
        HStack(spacing: DesignTokens.spacingSM) {
          EVEItemText(value: row.name, typeID: row.typeID, iconSize: 20)
            .font(.callout.weight(.semibold))
          Text(row.averagePrice.formatted(.number.precision(.fractionLength(2))))
            .font(.callout.monospacedDigit())
          trend(row.changeFraction)
        }
        .frame(width: itemWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "\(row.name), \(row.averagePrice), \(trendAccessibility(row.changeFraction))"
        )
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
        ) ?? "—"
      )
    } icon: {
      Image(systemName: icon)
    }
    .font(.caption.monospacedDigit())
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
/// can let an inner scroll view consume the title-bar inset on its own.
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
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 0) {
          navigation
          Divider()
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
          .font(.headline)
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
  @AppStorage(
    EVEEntityAppearance.colorStorageKey,
    store: AppDefaults.store
  )
  private var entityTextColorHex = EVEEntityAppearance.defaultColorHex

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("General Settings")
          .font(.largeTitle.bold())

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
          .font(.caption)
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
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)

          Label(
            "Panels switch to fewer columns when space is limited. Wide data tables remain horizontally scrollable instead of shrinking values beyond recognition.",
            systemImage: "rectangle.split.3x1"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }

        Panel(title: "Colors") {
          Picker("Color scheme", selection: $storedAppearance) {
            ForEach(AppAppearanceStyle.allCases) { appearance in
              Text(appearance.title).tag(appearance.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 440)
          .accessibilityIdentifier("appearance.color-scheme")

          Text(
            "System follows the current macOS appearance. Light uses cool titanium surfaces with EVE-inspired cyan accents; Dark keeps the graphite command-console look. Status colors retain their meaning in both modes."
          )
          .font(.caption)
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

        ConsolidationBackupView()
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: 1_600, alignment: .leading)
    }
    .navigationTitle(AppLocalization.text("General Settings"))
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
        .font(.caption)
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
  @EnvironmentObject private var runtime: RuntimeState

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
              .font(.subheadline.bold())
            Text(AppLocalization.text(notice.message))
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer(minLength: DesignTokens.spacingSM)
          Link(
            AppLocalization.text("Open CCP status"),
            destination: URL(string: "https://status.eveonline.com/")!
          )
          .font(.caption)
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
  var font: Font = .body.weight(.semibold)
  var lineLimit: Int? = nil

  @AppStorage(
    EVEEntityAppearance.colorStorageKey,
    store: AppDefaults.store
  )
  private var colorHex = EVEEntityAppearance.defaultColorHex

  var body: some View {
    Text(verbatim: value)
      .font(font)
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
  var font: Font = .body.weight(.semibold)
  var lineLimit: Int? = nil
  var iconSize: CGFloat = 22
  var imageKind: EVETypeImageKind = .icon
  var accessibilityIdentifier: String? = nil

  var body: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      EVEItemIcon(typeID: typeID, size: iconSize, imageKind: imageKind)
      EVEEntityText(
        value: value,
        font: font,
        lineLimit: lineLimit,
        accessibilityIdentifier: accessibilityIdentifier
      )
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
            .font(.caption2)
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
  var font: Font = .body.weight(.semibold)
  var lineLimit: Int? = nil
  var showsTransparentLabel = false
  var accessibilityIdentifier: String? = nil

  @State private var copySucceeded: Bool?
  @State private var feedbackTask: Task<Void, Never>?

  var body: some View {
    Button(action: copyValue) {
      if showsTransparentLabel {
        Text(verbatim: value)
          .font(font)
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
    .accessibilityLabel("Copy EVE name")
    .accessibilityValue(Text(verbatim: value))
    .accessibilityHint("Copies the displayed EVE name to the clipboard.")
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
      Text(title)
        .textCase(.uppercase)
        .font(.caption.weight(.semibold))
        .tracking(1.1)
        .foregroundStyle(DesignTokens.textSecondary)
      content
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: fillsAvailableHeight ? .infinity : nil,
      alignment: .topLeading
    )
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .shadow(
      color: DesignTokens.panelShadow,
      radius: DesignTokens.panelShadowRadius,
      y: DesignTokens.panelShadowOffset
    )
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
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
          .font(.caption.bold())
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
