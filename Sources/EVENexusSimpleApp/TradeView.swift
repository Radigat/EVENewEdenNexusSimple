import EVENexusCore
import SwiftUI

/// The separately presented trade routes (HANDEL_PLAN.md, P4 and the
/// owner change of 22.10.2026: no station trading, Home ↔ Coalition added;
/// Home → Main and Coalition → Main added on 27.10.2026).
/// Raw values are stored; an unknown stored value falls back to Main → Home.
enum TradeModeOption: String, CaseIterable, Identifiable {
  case importHome
  case importCoalition
  case homeToCoalition
  case coalitionToHome
  case homeToMain
  case coalitionToMain

  var id: Self { self }

  var mode: TradeMode {
    switch self {
    case .importHome: .mainToHome
    case .importCoalition: .mainToCoalition
    case .homeToCoalition: .homeToCoalition
    case .coalitionToHome: .coalitionToHome
    case .homeToMain: .homeToMain
    case .coalitionToMain: .coalitionToMain
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .importHome: "Main → Home"
    case .importCoalition: "Main → Coalition"
    case .homeToCoalition: "Home → Coalition"
    case .coalitionToHome: "Coalition → Home"
    case .homeToMain: "Home → Main"
    case .coalitionToMain: "Coalition → Main"
    }
  }
}

enum TradeHubText {
  static func roleName(_ role: OpportunityHubRole) -> String {
    switch role {
    case .main: AppLocalization.text("Main Hub")
    case .home: AppLocalization.text("Home Hub")
    case .coalition: AppLocalization.text("Coalition Hub")
    }
  }

  static func sideName(_ side: TradeQuoteSide) -> String {
    switch side {
    case .minSell: "Min-Sell"
    case .maxBuy: "Max-Buy"
    }
  }

  static func issueText(_ issue: TradeRowIssue) -> String {
    switch issue {
    case .missingSourcePrice:
      AppLocalization.text("No usable price at the source hub.")
    case .missingTargetPrice:
      AppLocalization.text("No usable price at the target hub.")
    case .missingSourceBrokerFee:
      AppLocalization.text("The broker fee of the source hub is unknown.")
    case .missingTargetFees:
      AppLocalization.text("The sales tax or broker fee of the target hub is unknown.")
    case .missingPackagedVolume:
      AppLocalization.text("The packaged volume is unknown, so transport cannot be calculated.")
    case .transportUnavailable:
      AppLocalization.text("No usable transport for this route.")
    case .exceedsJumpFreighterCapacity:
      AppLocalization.text("One unit does not fit into the Jump Freighter.")
    case .noValidPriceStep:
      AppLocalization.text("No valid order price step exists for this price.")
    }
  }

  static func transportText(_ code: String) -> String {
    switch code {
    case "trade.logistics-disabled":
      AppLocalization.text("Profile logistics is disabled, so the courier cost of this route is unavailable.")
    case "logistics.missing-volume-rate":
      AppLocalization.text("The courier rate in ISK per m³ is missing in the logistics settings.")
    case "trade.home-hub-missing":
      AppLocalization.text("Main Hub and Home Hub must be configured for an import route.")
    case "trade.coalition-hub-missing":
      AppLocalization.text("No Coalition Hub is configured.")
    case "trade.route-hub-missing":
      AppLocalization.text("Home Hub and Coalition Hub must both be configured for this route.")
    case "jump-freighter.isotope-price-unavailable":
      AppLocalization.text("A Main Hub isotope price is missing, so the Jump Freighter fuel cost is unavailable.")
    case "trade.jf-service-rate-missing":
      AppLocalization.text("The Jump Freighter service prices of a leg are incomplete in the logistics settings.")
    case "trade.main-jump-profile-missing":
      AppLocalization.text("A self-jump to or from the Main Hub needs a jump-route profile ending in a jumpable system near the Main Hub.")
    case "trade.jump-profile-unavailable":
      AppLocalization.text("The jump-route profile chosen for a leg is missing or incomplete.")
    case "jump-freighter.pilot-unavailable":
      AppLocalization.text("No eligible Jump Freighter pilot with fresh skills is available.")
    default:
      AppLocalization.text("The Jump Freighter route of a leg is unavailable.")
    }
  }
}

struct TradeView: View {
  var onOpenMarketSettings: () -> Void = {}
  var onOpenLogistics: () -> Void = {}
  var onOpenSDESettings: () -> Void = {}

  @Environment(RuntimeState.self) private var runtime
  @AppStorage("trade.mode", store: AppDefaults.store)
  private var modeRawValue = TradeModeOption.importHome.rawValue
  /// The selected market-group node, shared by all modes (U4); 0 = none.
  @AppStorage("trade.market-group-id", store: AppDefaults.store)
  private var selectedMarketGroupID = 0
  @AppStorage("trade.indicator.increase-percent", store: AppDefaults.store)
  private var increasePercent = 25
  @AppStorage("trade.indicator.strong-increase-percent", store: AppDefaults.store)
  private var strongIncreasePercent = 30
  @AppStorage("trade.shows-details", store: AppDefaults.store)
  private var showsDetails = false
  /// Ranking metric of the Top-20 tile (HANDEL_PLAN.md, section J).
  @AppStorage("trade.top-ranking", store: AppDefaults.store)
  private var topRankingRawValue = TradeTopRankingMetric.profitPerCubicMeter.rawValue
  /// Window in days of the regional ESI market history columns.
  @AppStorage("trade.volume-window", store: AppDefaults.store)
  private var volumeWindowRawValue = MarketHistoryWindow.sevenDays.rawValue

  @State private var marketGroups: MarketGroupCatalogSnapshot?
  @State private var marketGroupsFailed = false
  @State private var tiles: [TradeTile] = []
  @State private var isLoadingTiles = false
  @State private var loadError: String?
  @State private var searchText = ""
  @State private var itemSearchText = ""
  /// Up to `itemSearchLimit + 1` matches; the extra one shows that more exist.
  @State private var itemSearchMatches: [TradeCatalogItem] = []
  @State private var isSearchingItems = false
  @State private var itemSearchFailed = false
  @State private var itemSearchSourceSide = TradeQuoteSide.minSell
  @State private var itemSearchTargetSide = TradeQuoteSide.minSell
  @State private var sourceSides: [Int64: TradeQuoteSide] = [:]
  @State private var targetSides: [Int64: TradeQuoteSide] = [:]
  @State private var sort = AppTableSortDescriptor(
    column: TradeSortColumn.name,
    direction: .ascending
  )
  @State private var logbookRequest: TradeLogbookEditorRequest?
  @State private var stockHistoryRequest: MarketStockItemRequest?
  @State private var topSourceSide = TradeQuoteSide.minSell
  @State private var topTargetSide = TradeQuoteSide.minSell
  /// The Top-20 tile's own sort; `nil` follows the metric, descending
  /// (owner decision 5, HANDEL_PLAN.md section J).
  @State private var topSort: AppTableSortDescriptor<TradeSortColumn>?

  private var option: TradeModeOption {
    TradeModeOption(rawValue: modeRawValue) ?? .importHome
  }

  private var mode: TradeMode { option.mode }

  private var selectedNode: MarketGroupDefinition? {
    guard selectedMarketGroupID != 0 else { return nil }
    return marketGroups?.groups.first { $0.id == Int64(selectedMarketGroupID) }
  }

  private var volumeWindow: MarketHistoryWindow {
    MarketHistoryWindow(rawValue: volumeWindowRawValue) ?? .sevenDays
  }

  private var topRanking: TradeTopRankingMetric {
    TradeTopRankingMetric(rawValue: topRankingRawValue) ?? .profitPerCubicMeter
  }

  /// Switching the metric restarts the Top-20 sort at that metric,
  /// descending; any other change keeps the chosen sort.
  private var topRankingSelection: Binding<TradeTopRankingMetric> {
    Binding(
      get: { topRanking },
      set: {
        topRankingRawValue = $0.rawValue
        topSort = nil
      }
    )
  }

  private var topSortSelection: Binding<AppTableSortDescriptor<TradeSortColumn>> {
    Binding(
      get: {
        topSort
          ?? AppTableSortDescriptor(column: topRanking.sortColumn, direction: .descending)
      },
      set: { topSort = $0 }
    )
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        header
        modePicker
        routeSummary
        marketGroupNavigation
        tileContent
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { await loadMarketGroups() }
    .task(id: selectedMarketGroupID) { await loadTiles() }
    .task(id: itemSearchQuery) { await searchItems() }
    .task(id: transportKey) {
      await runtime.refreshTradeTransportBasis(for: mode.route)
    }
    .task(id: volumeHistoryKey) { await loadVolumeHistory() }
    .task(id: marketStockKey) {
      await runtime.refreshMarketStockOverviews(
        for: [mode.sourceRole, mode.targetRole],
        consumer: "trade"
      )
    }
    .onDisappear { runtime.releaseMarketStockOverviews(consumer: "trade") }
    .task {
      if runtime.tradeLogbookState == .notLoaded {
        await runtime.loadTradeLogbook()
      }
    }
    .sheet(item: $logbookRequest) { request in
      TradeLogbookEditor(request: request)
        .environment(runtime)
    }
    .sheet(item: $stockHistoryRequest) { request in
      MarketStockItemDetailView(request: request)
        .environment(runtime)
    }
  }

  // MARK: Header and route

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Trade")
        .font(.largeTitle.bold())
        .foregroundStyle(DesignTokens.textPrimary)
      Text(
        "Compare market groups between hubs: what to buy at the source and at which price to sell at the target, after taxes, broker fees and transport."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var modePicker: some View {
    Picker("Trade mode", selection: $modeRawValue) {
      ForEach(TradeModeOption.allCases) { option in
        Text(option.title).tag(option.rawValue)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .accessibilityIdentifier("trade.mode")
  }

  private var routeSummary: some View {
    Panel(title: "Route and basis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          hubChip(role: mode.sourceRole, prefix: "Source:", tint: DesignTokens.highlight)
          Image(systemName: "arrow.right")
            .foregroundStyle(DesignTokens.textSecondary)
          hubChip(role: mode.targetRole, prefix: "Target:", tint: DesignTokens.accent)
          Spacer()
          refreshButton
        }
        ForEach(hubMessages, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.caution)
        }
        ForEach(marketMessages, id: \.self) { message in
          Label(message, systemImage: "clock.badge.exclamationmark")
            .foregroundStyle(DesignTokens.caution)
        }
        if !feeMessages.isEmpty {
          ForEach(feeMessages, id: \.self) { message in
            Label(message, systemImage: "percent")
              .foregroundStyle(DesignTokens.caution)
          }
          Button("Open Market Settings", action: onOpenMarketSettings)
            .accessibilityIdentifier("trade.open-market-settings")
        }
        transportStatus
        volumeHistoryStatus
        Text(
          "Own orders are placed one valid price step (four significant digits) better than the best order. Order modification and relist fees are not included."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        indicatorSettings
      }
    }
  }

  private var isScanningHubs: Bool {
    runtime.isAnalyzingManufacturingOpportunities
      || runtime.opportunityState(for: .home).isAnalyzing
      || runtime.opportunityState(for: .coalition).isAnalyzing
  }

  /// Hub market data lives in memory and is filled by the shared Hub
  /// opportunity scan, so the Trade area starts that same scan.
  private var refreshButton: some View {
    Button {
      Task {
        await runtime.analyzeManufacturingOpportunities(
          settings: runtime.manufacturingOpportunityAnalysis?.settings
            ?? ManufacturingOpportunitySettings()
        )
      }
    } label: {
      if isScanningHubs {
        ProgressView().controlSize(.small)
      } else {
        Label("Refresh hub markets", systemImage: "arrow.clockwise")
      }
    }
    .disabled(isScanningHubs || runtime.isHubScanBlockedByESICache)
    .help(
      runtime.hubScanBlockedText
        ?? AppLocalization.text(
          "Runs the Main, Home and Coalition Hub scan that also updates the Hub opportunities.")
    )
    .accessibilityIdentifier("trade.refresh-hub-markets")
  }

  private func hubChip(
    role: OpportunityHubRole,
    prefix: LocalizedStringKey,
    tint: Color
  ) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Text(prefix)
        .font(.caption.weight(.semibold))
      if let location = runtime.tradeLocation(for: role) {
        EVEEntityText(value: location.name, font: .caption, lineLimit: 1)
      } else {
        Text(verbatim: TradeHubText.roleName(role))
          .font(.caption)
      }
    }
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(tint.opacity(0.15), in: Capsule())
    .overlay(Capsule().stroke(tint.opacity(0.6)))
  }

  private var hubMessages: [String] {
    var messages: [String] = []
    for role in Set([mode.sourceRole, mode.targetRole]).sorted(by: { $0.rawValue < $1.rawValue }) {
      switch runtime.opportunityScanTarget(for: role) {
      case .notConfigured:
        messages.append(
          AppLocalization.format(
            "No %@ is configured. Select it in Market Settings.",
            TradeHubText.roleName(role)
          )
        )
      case .unresolved:
        messages.append(
          AppLocalization.format(
            "The %@ has no exact station or structure identifier. Select it again in Market Settings.",
            TradeHubText.roleName(role)
          )
        )
      default:
        break
      }
    }
    if let source = runtime.tradeDataRole(for: mode.sourceRole),
      source == runtime.tradeDataRole(for: mode.targetRole)
    {
      messages.append(
        AppLocalization.format(
          "The %@ and the %@ are the same place, so there is no trade route.",
          TradeHubText.roleName(mode.sourceRole),
          TradeHubText.roleName(mode.targetRole)
        )
      )
    }
    return messages
  }

  private var marketMessages: [String] {
    var messages: [String] = []
    for role in [mode.sourceRole, mode.targetRole] where runtime.tradeDataRole(for: role) != nil {
      let name = TradeHubText.roleName(role)
      guard let state = runtime.tradeMarketState(for: role), state.value != nil else {
        if !messages.contains(where: { $0.contains(name) }) {
          messages.append(
            AppLocalization.format(
              "No market data for the %@ in this session yet. Use “Refresh hub markets” or wait for the automatic Hub scan.",
              name
            )
          )
        }
        continue
      }
      if state.state != .fresh, !messages.contains(where: { $0.contains(name) }) {
        messages.append(
          AppLocalization.format(
            "Market data of the %@: %@.",
            name,
            StartupDataStatusSection.freshnessText(state.state)
          )
        )
      }
    }
    return messages
  }

  private var feeMessages: [String] {
    var messages: [String] = []
    let source = runtime.tradeHubFees(for: mode.sourceRole)
    let target = runtime.tradeHubFees(for: mode.targetRole)
    if source.brokerFeeRate == nil {
      messages.append(
        AppLocalization.format(
          "The broker fee of the %@ is unknown; Max-Buy purchase costs stay unavailable.",
          TradeHubText.roleName(mode.sourceRole)
        )
      )
    }
    if target.salesTaxRate == nil || target.brokerFeeRate == nil {
      messages.append(
        AppLocalization.format(
          "Sales tax or broker fee of the %@ is unknown; net sales stay unavailable.",
          TradeHubText.roleName(mode.targetRole)
        )
      )
    }
    return messages
  }

  @ViewBuilder
  private var transportStatus: some View {
    if mode.requiresTransport {
      if let basis = runtime.tradeTransportBases[mode.route] {
        let unavailable = basis.legs.compactMap { leg -> String? in
          if case .unavailable(let code) = leg { return code }
          return nil
        }
        if unavailable.isEmpty {
          ForEach(Array(basis.legs.enumerated()), id: \.offset) { _, leg in
            Label(transportDescription(leg), systemImage: "shippingbox")
              .font(.callout)
          }
        } else {
          ForEach(unavailable, id: \.self) { code in
            Label(TradeHubText.transportText(code), systemImage: "shippingbox.fill")
              .foregroundStyle(DesignTokens.caution)
          }
          Button("Open Logistics", action: onOpenLogistics)
            .accessibilityIdentifier("trade.open-logistics")
        }
      } else {
        Label("Resolving transport…", systemImage: "shippingbox")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func transportDescription(_ leg: TradeTransportLeg) -> String {
    switch leg {
    case .courier(let courier):
      switch courier.provider {
      case .profileCourier:
        AppLocalization.format(
          "Courier %@ → %@: %@ ISK per m³, at least %@ of the collateral, per unit without contract rounding.",
          courier.origin,
          courier.destination,
          formatNumber(courier.iskPerCubicMeter),
          formatPercent(courier.collateralRate)
        )
      case .jumpFreighterService:
        AppLocalization.format(
          "Jump Freighter service %@ → %@: %@ ISK per m³ plus %@ of the collateral, without rounding.",
          courier.origin,
          courier.destination,
          formatNumber(courier.iskPerCubicMeter),
          formatPercent(courier.collateralRate)
        )
      }
    case .jumpFreighter(let freighter):
      AppLocalization.format(
        "Jump Freighter %@ → %@: %@ ISK per flight for %@ m³; per unit assuming a full load.",
        freighter.origin,
        freighter.destination,
        formatNumber(freighter.costPerFlight),
        formatNumber(freighter.usableCargoCapacityM3)
      )
    case .unavailable(let code):
      TradeHubText.transportText(code)
    }
  }

  /// Load state of the regional ESI market history of the target hub.
  @ViewBuilder
  private var volumeHistoryStatus: some View {
    if let regionID = runtime.tradeRegionID(for: mode.targetRole) {
      if let progress = runtime.tradeVolumeHistoryProgress[regionID] {
        HStack(spacing: DesignTokens.spacingSM) {
          ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
            .frame(maxWidth: 160)
          Text(
            AppLocalization.format(
              "Loading market history: %lld of %lld items",
              Int64(progress.completed),
              Int64(progress.total)
            )
          )
        }
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trade.volume-history.progress")
      } else if let snapshot = runtime.tradeVolumeHistories[regionID],
        !snapshot.unavailableTypeIDs.isEmpty
      {
        Label(
          AppLocalization.format(
            "Market history unavailable for %lld items; their traded volume stays unknown.",
            Int64(snapshot.unavailableTypeIDs.count)
          ),
          systemImage: "chart.bar.xaxis"
        )
        .foregroundStyle(DesignTokens.caution)
      }
    } else if runtime.tradeDataRole(for: mode.targetRole) != nil {
      Label(
        AppLocalization.format(
          "The region of the %@ is unknown, so its traded volume is unavailable. Select the hub again in Market Settings.",
          TradeHubText.roleName(mode.targetRole)
        ),
        systemImage: "chart.bar.xaxis"
      )
      .foregroundStyle(DesignTokens.caution)
    }
  }

  private typealias Indicator = TradeDifferenceIndicator

  private var increasePercentRange: ClosedRange<Int> {
    Indicator.percentRange.lowerBound...(Indicator.percentRange.upperBound
      - Indicator.minimumPercentGap)
  }

  /// The double arrow can never be set below single arrow + 1 %.
  private var strongIncreasePercentRange: ClosedRange<Int> {
    (coupledPercents.increase + Indicator.minimumPercentGap)...Indicator.percentRange.upperBound
  }

  /// Stored values may predate the coupling, so every read is normalised.
  private var coupledPercents: (increase: Int, strongIncrease: Int) {
    Indicator.coupledPercents(increase: increasePercent, strongIncrease: strongIncreasePercent)
  }

  /// Raising the single arrow pushes the double arrow up with it.
  private var coupledIncreasePercent: Binding<Int> {
    Binding(
      get: { coupledPercents.increase },
      set: { newValue in
        let coupled = Indicator.coupledPercents(
          increase: newValue,
          strongIncrease: strongIncreasePercent
        )
        increasePercent = coupled.increase
        strongIncreasePercent = coupled.strongIncrease
      }
    )
  }

  private var coupledStrongIncreasePercent: Binding<Int> {
    Binding(
      get: { coupledPercents.strongIncrease },
      set: { newValue in
        let coupled = Indicator.coupledPercents(
          increase: increasePercent,
          strongIncrease: newValue
        )
        increasePercent = coupled.increase
        strongIncreasePercent = coupled.strongIncrease
      }
    )
  }

  private var indicatorSettings: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      Stepper(value: coupledIncreasePercent, in: increasePercentRange) {
        Label(
          AppLocalization.format("Arrow from %lld %%", Int64(coupledPercents.increase)),
          systemImage: "chevron.up"
        )
      }
      .accessibilityIdentifier("trade.indicator.increase")
      Stepper(value: coupledStrongIncreasePercent, in: strongIncreasePercentRange) {
        Label(
          AppLocalization.format(
            "Double arrow from %lld %%",
            Int64(coupledPercents.strongIncrease)
          ),
          systemImage: "chevron.up.2"
        )
      }
      .accessibilityIdentifier("trade.indicator.strong-increase")
      Spacer()
      HStack(spacing: DesignTokens.spacingXS) {
        Text("Traded volume").font(.caption.weight(.semibold))
        Picker("Traded volume", selection: $volumeWindowRawValue) {
          ForEach(MarketHistoryWindow.allCases) { window in
            Text(AppLocalization.format("%lld d", Int64(window.days))).tag(window.rawValue)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("trade.volume-window")
      }
      .help(AppLocalization.text("Days of the regional ESI market history shown in the traded-volume columns"))
      Toggle("Show details", isOn: $showsDetails)
        .toggleStyle(.switch)
        .accessibilityIdentifier("trade.show-details")
    }
    .font(.callout)
  }

  // MARK: Market groups

  @ViewBuilder
  private var marketGroupNavigation: some View {
    if let marketGroups, marketGroups.availability == .available {
      Panel(title: "Market group and item") {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          breadcrumb(groups: marketGroups.groups)
          HStack(spacing: DesignTokens.spacingSM) {
            TextField("Search market group", text: $searchText)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 360)
              .accessibilityIdentifier("trade.market-group-search")
            TextField("Search item", text: $itemSearchText)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 360)
              .accessibilityIdentifier("trade.item-search")
            if !itemSearchText.isEmpty {
              Button {
                itemSearchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.borderless)
              .help(AppLocalization.text("Clear item search"))
              .accessibilityLabel("Clear item search")
              .accessibilityIdentifier("trade.item-search.clear")
            }
          }
          if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            groupList(searchResults(in: marketGroups.groups), groups: marketGroups.groups)
          } else if selectedNode == nil, !isItemSearchActive {
            Text("Select a market group. Its subgroups become the tiles.")
              .foregroundStyle(DesignTokens.textSecondary)
            groupList(
              marketGroups.groups.filter { $0.parentID == nil },
              groups: marketGroups.groups
            )
          }
        }
      }
    }
  }

  private func breadcrumb(groups: [MarketGroupDefinition]) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Button {
        selectedMarketGroupID = 0
      } label: {
        Label("All market groups", systemImage: "square.grid.2x2")
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("trade.market-group.root")
      if let node = selectedNode {
        let path = TradeTileBuilder.path(to: node.id, groups: groups)
        ForEach(path) { group in
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(DesignTokens.textSecondary)
          EVEEntityText(value: group.name, font: .callout, lineLimit: 1)
          if group.id != node.id {
            Button {
              selectedMarketGroupID = Int(group.id)
            } label: {
              Image(systemName: "arrow.up.left.circle")
            }
            .buttonStyle(.borderless)
            .help(AppLocalization.text("Open this market group"))
            .accessibilityLabel("Open this market group")
          }
        }
      }
    }
  }

  private func searchResults(
    in groups: [MarketGroupDefinition]
  ) -> [MarketGroupDefinition] {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    return Array(
      groups.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(20)
    )
  }

  private func groupList(
    _ list: [MarketGroupDefinition],
    groups: [MarketGroupDefinition]
  ) -> some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)],
      alignment: .leading,
      spacing: DesignTokens.spacingXS
    ) {
      ForEach(list) { group in
        HStack(spacing: DesignTokens.spacingXS) {
          EVEEntityText(value: group.name, font: .callout, lineLimit: 1)
          Spacer(minLength: DesignTokens.spacingXS)
          Button {
            searchText = ""
            selectedMarketGroupID = Int(group.id)
          } label: {
            Image(systemName: "chevron.right.circle.fill")
          }
          .buttonStyle(.borderless)
          .help(AppLocalization.text("Open this market group"))
          .accessibilityLabel("Open this market group")
          .accessibilityIdentifier("trade.market-group.open.\(group.id)")
        }
        .padding(DesignTokens.spacingXS)
        .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 6))
      }
    }
  }

  // MARK: Tiles

  @ViewBuilder
  private var tileContent: some View {
    if let loadError, !marketGroupsFailed {
      Label(loadError, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.negative)
    }
    if marketGroups == nil, marketGroupsFailed {
      ContentUnavailableView {
        Label("No static data catalog", systemImage: "externaldrive.badge.exclamationmark")
      } description: {
        Text("Install or reimport the SDE in the SDE settings, then restart the app.")
      } actions: {
        Button("Open SDE settings", action: onOpenSDESettings)
      }
      .frame(maxWidth: .infinity, minHeight: 240)
    } else if marketGroups == nil {
      ProgressView("Loading market groups…")
        .frame(maxWidth: .infinity, minHeight: 160)
    } else if marketGroups?.availability == .requiresSDEReimport {
      ContentUnavailableView {
        Label("SDE reimport required", systemImage: "arrow.triangle.2.circlepath")
      } description: {
        Text(
          "The active static data catalog predates market groups. Run “Reimport current catalog” in the SDE settings and restart the app."
        )
      } actions: {
        Button("Open SDE settings", action: onOpenSDESettings)
          .accessibilityIdentifier("trade.open-sde-settings")
      }
      .frame(maxWidth: .infinity, minHeight: 240)
    } else if isItemSearchActive {
      itemSearchTile
    } else if selectedNode != nil {
      if isLoadingTiles {
        ProgressView("Loading items…")
          .frame(maxWidth: .infinity, minHeight: 160)
      } else if tiles.isEmpty {
        ContentUnavailableView(
          "No market items in this group",
          systemImage: "tray",
          description: Text("The selected market group lists no published items.")
        )
        .frame(maxWidth: .infinity, minHeight: 200)
      } else {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          topTile
          // Tiles sit side by side only when every tile fits its full
          // compact table; otherwise they stack in one column.
          LazyVGrid(
            columns: showsDetails
              ? [GridItem(.flexible(), alignment: .top)]
              : [GridItem(.adaptive(minimum: compactTileMinimumWidth), alignment: .top)],
            alignment: .leading,
            spacing: DesignTokens.spacingMD
          ) {
            ForEach(tiles) { tile in
              tileView(tile)
            }
          }
        }
      }
    }
  }

  /// Matches of the item search over the whole market tree. It replaces the
  /// group tiles while a query is active; the selected group stays stored.
  private var itemSearchTile: some View {
    let items = Array(itemSearchMatches.prefix(itemSearchLimit))
    let rows = TradeRowSorter.sorted(
      calculatedRows(
        items: items,
        sourceSide: itemSearchSourceSide,
        targetSide: itemSearchTargetSide
      ),
      by: sort.column,
      ascending: sort.direction == .ascending,
      volumeWindow: volumeWindow
    )
    return tileFrame(identifier: "trade.item-search-tile") {
      Text("Item search")
        .font(.title3.weight(.semibold))
      HStack(spacing: DesignTokens.spacingSM) {
        hubChip(role: mode.sourceRole, prefix: "Source:", tint: DesignTokens.highlight)
        hubChip(role: mode.targetRole, prefix: "Target:", tint: DesignTokens.accent)
        countChip(AppLocalization.format("Items: %lld", Int64(items.count)))
      }
      sidePickers(
        source: $itemSearchSourceSide,
        target: $itemSearchTargetSide,
        identifierPrefix: "trade.item-search-tile"
      )
      if itemSearchFailed {
        Label(
          "The item search of the active static data catalog failed.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(DesignTokens.negative)
      } else if rows.isEmpty {
        if isSearchingItems {
          ProgressView("Loading items…")
            .frame(maxWidth: .infinity, minHeight: 80)
        } else {
          Label(
            AppLocalization.format("No market item matches “%@”.", itemSearchQuery),
            systemImage: "tray"
          )
          .foregroundStyle(DesignTokens.textSecondary)
          .padding(.vertical, DesignTokens.spacingSM)
        }
      } else {
        tileTable(
          rows: rows,
          sourceSide: itemSearchSourceSide,
          targetSide: itemSearchTargetSide,
          sort: $sort,
          rowIdentifierPrefix: "trade.item-search-tile.row",
          showsReturnOnInvestment: true
        )
        if itemSearchMatches.count > itemSearchLimit {
          Text(
            AppLocalization.format(
              "Showing the first %lld matches. Refine the search to see the others.",
              Int64(itemSearchLimit)
            )
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  /// First tile over every item of the selected node (owner decisions
  /// 23.10.2026, HANDEL_PLAN.md section J). It is left out when it would only
  /// repeat a single tile.
  @ViewBuilder
  private var topTile: some View {
    let items = tiles.flatMap(\.items)
    if tiles.count > 1 || items.count > TradeTopRanking.limit {
      let result = TradeTopRanking.ranked(
        calculatedRows(items: items, sourceSide: topSourceSide, targetSide: topTargetSide),
        by: topRanking
      )
      let order = topSortSelection.wrappedValue
      let rows = TradeRowSorter.sorted(
        result.rows,
        by: order.column,
        ascending: order.direction == .ascending,
        volumeWindow: volumeWindow
      )
      tileFrame(identifier: "trade.top-tile") {
        HStack(spacing: DesignTokens.spacingSM) {
          Text(AppLocalization.format("Top %lld", Int64(TradeTopRanking.limit)))
            .font(.title3.weight(.semibold))
          Spacer()
          Text("Ranked by").font(.caption.weight(.semibold))
          Picker("Ranked by", selection: topRankingSelection) {
            Text("Profit/m³").tag(TradeTopRankingMetric.profitPerCubicMeter)
            Text("ROI").tag(TradeTopRankingMetric.returnOnInvestment)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          .accessibilityIdentifier("trade.top-tile.ranking")
        }
        HStack(spacing: DesignTokens.spacingSM) {
          hubChip(role: mode.sourceRole, prefix: "Source:", tint: DesignTokens.highlight)
          hubChip(role: mode.targetRole, prefix: "Target:", tint: DesignTokens.accent)
          countChip(
            AppLocalization.format(
              "Top %lld of %lld items",
              Int64(result.rows.count),
              Int64(result.candidateCount)
            )
          )
        }
        sidePickers(
          source: $topSourceSide,
          target: $topTargetSide,
          identifierPrefix: "trade.top-tile"
        )
        Text("Only items with a positive profit and a positive value are ranked.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        if rows.isEmpty {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Label("No item has a positive value for this ranking.", systemImage: "tray")
            switch topRanking {
            case .profitPerCubicMeter:
              Text("Profit/m³ needs prices, fees, transport and the packaged volume.")
                .font(.caption)
            case .returnOnInvestment:
              Text("ROI needs prices, fees and transport.")
                .font(.caption)
            }
          }
          .foregroundStyle(DesignTokens.textSecondary)
          .padding(.vertical, DesignTokens.spacingSM)
        } else {
          tileTable(
            rows: rows,
            sourceSide: topSourceSide,
            targetSide: topTargetSide,
            sort: topSortSelection,
            rowIdentifierPrefix: "trade.top-tile.row",
            showsReturnOnInvestment: topRanking == .returnOnInvestment
          )
        }
        let unranked = unrankedTexts(result)
        if !unranked.isEmpty {
          Text(
            AppLocalization.format("Not ranked: %@", unranked.joined(separator: " · "))
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  private func unrankedTexts(_ result: TradeTopRankingResult) -> [String] {
    var texts: [String] = []
    if result.unknownCount > 0 {
      texts.append(
        AppLocalization.format(
          "%lld items without a known value",
          Int64(result.unknownCount)
        )
      )
    }
    if result.nonPositiveCount > 0 {
      texts.append(
        AppLocalization.format(
          "%lld items without a positive profit or value",
          Int64(result.nonPositiveCount)
        )
      )
    }
    return texts
  }

  private func tileView(_ tile: TradeTile) -> some View {
    let sourceSide = sourceSides[tile.id] ?? .minSell
    let targetSide = targetSides[tile.id] ?? .minSell
    let rows = displayRows(for: tile, sourceSide: sourceSide, targetSide: targetSide)
    return tileFrame(identifier: "trade.tile.\(tile.id)") {
      HStack(spacing: DesignTokens.spacingSM) {
        EVEEntityText(value: tile.name, font: .title3.weight(.semibold), lineLimit: 1)
        if tile.hasSubgroups {
          Button {
            selectedMarketGroupID = Int(tile.marketGroupID)
          } label: {
            Image(systemName: "chevron.right.circle")
          }
          .buttonStyle(.borderless)
          .help(AppLocalization.text("Open this market group"))
          .accessibilityLabel("Open this market group")
          .accessibilityIdentifier("trade.tile.open.\(tile.marketGroupID)")
        }
        Spacer()
      }
      HStack(spacing: DesignTokens.spacingSM) {
        hubChip(role: mode.sourceRole, prefix: "Source:", tint: DesignTokens.highlight)
        hubChip(role: mode.targetRole, prefix: "Target:", tint: DesignTokens.accent)
        countChip(AppLocalization.format("Items: %lld", Int64(tile.items.count)))
      }
      sidePickers(
        source: Binding(
          get: { sourceSides[tile.id] ?? .minSell },
          set: { sourceSides[tile.id] = $0 }
        ),
        target: Binding(
          get: { targetSides[tile.id] ?? .minSell },
          set: { targetSides[tile.id] = $0 }
        ),
        identifierPrefix: "trade.tile.\(tile.id)"
      )
      tileTable(
        rows: rows,
        sourceSide: sourceSide,
        targetSide: targetSide,
        sort: $sort
      )
    }
  }

  /// Panel, padding and the source-to-target gradient of every tile.
  private func tileFrame<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel, in: RoundedRectangle(cornerRadius: 10))
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [DesignTokens.highlight, DesignTokens.accent],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 3)
      .clipShape(RoundedRectangle(cornerRadius: 2))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func countChip(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.caption)
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .overlay(Capsule().stroke(DesignTokens.border))
  }

  private func sidePickers(
    source: Binding<TradeQuoteSide>,
    target: Binding<TradeQuoteSide>,
    identifierPrefix: String
  ) -> some View {
    HStack(spacing: DesignTokens.spacingMD) {
      sidePicker(
        title: "Source side",
        selection: source,
        identifier: "\(identifierPrefix).source-side"
      )
      sidePicker(
        title: "Target side",
        selection: target,
        identifier: "\(identifierPrefix).target-side"
      )
    }
  }

  @ViewBuilder
  private func tileTable(
    rows: [TradeDisplayRow],
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    sort: Binding<AppTableSortDescriptor<TradeSortColumn>>,
    rowIdentifierPrefix: String = "trade.row",
    showsReturnOnInvestment: Bool = false
  ) -> some View {
    if showsDetails {
      // The detail columns are wider than the window; they scroll inside
      // the tile instead of pushing the layout under the sidebar.
      ScrollView(.horizontal) {
        table(
          rows: rows,
          sourceSide: sourceSide,
          targetSide: targetSide,
          sort: sort,
          rowIdentifierPrefix: rowIdentifierPrefix,
          showsReturnOnInvestment: showsReturnOnInvestment
        )
      }
    } else {
      // A window narrower than one compact table scrolls inside the tile
      // instead of clipping the right-hand columns.
      ViewThatFits(in: .horizontal) {
        table(
          rows: rows,
          sourceSide: sourceSide,
          targetSide: targetSide,
          sort: sort,
          rowIdentifierPrefix: rowIdentifierPrefix,
          showsReturnOnInvestment: showsReturnOnInvestment
        )
        ScrollView(.horizontal) {
          table(
            rows: rows,
            sourceSide: sourceSide,
            targetSide: targetSide,
            sort: sort,
            rowIdentifierPrefix: rowIdentifierPrefix,
            showsReturnOnInvestment: showsReturnOnInvestment
          )
        }
      }
    }
  }

  private func table(
    rows: [TradeDisplayRow],
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    sort: Binding<AppTableSortDescriptor<TradeSortColumn>>,
    rowIdentifierPrefix: String,
    showsReturnOnInvestment: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      tableHeader(
        sourceSide: sourceSide,
        targetSide: targetSide,
        sort: sort,
        showsReturnOnInvestment: showsReturnOnInvestment
      )
      Divider()
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          tableRow(
            row,
            sourceSide: sourceSide,
            targetSide: targetSide,
            identifierPrefix: rowIdentifierPrefix,
            showsReturnOnInvestment: showsReturnOnInvestment
          )
          Divider().opacity(0.4)
        }
      }
    }
  }

  private func sidePicker(
    title: LocalizedStringKey,
    selection: Binding<TradeQuoteSide>,
    identifier: String
  ) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Text(title).font(.caption.weight(.semibold))
      Picker(title, selection: selection) {
        ForEach(TradeQuoteSide.allCases, id: \.self) { side in
          Text(verbatim: TradeHubText.sideName(side)).tag(side)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier(identifier)
    }
  }

  private func displayRows(
    for tile: TradeTile,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
  ) -> [TradeDisplayRow] {
    TradeRowSorter.sorted(
      calculatedRows(items: tile.items, sourceSide: sourceSide, targetSide: targetSide),
      by: sort.column,
      ascending: sort.direction == .ascending,
      volumeWindow: volumeWindow
    )
  }

  /// Rows of `items` for the current route, unsorted.
  private func calculatedRows(
    items: [TradeCatalogItem],
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
  ) -> [TradeDisplayRow] {
    let source = runtime.tradeMarketState(for: mode.sourceRole)?.value
    let target = runtime.tradeMarketState(for: mode.targetRole)?.value
    let targetStock = runtime.marketStockOverview(for: mode.targetRole)
    let sourceStock = runtime.marketStockOverview(for: mode.sourceRole)
    let histories = runtime.tradeVolumeHistory(for: mode.targetRole)
    let hubUsesRegion = hubVolumeUsesRegion
    let selectedWindow = volumeWindow
    let openQuantities = TradeLogbookSummary.openQuantities(
      runtime.tradeLogbookEntries,
      targetRole: mode.targetRole
    )
    let transport = runtime.tradeTransportBases[mode.route] ?? .none
    let inputs = items.map { item in
      TradeItemInput(
        typeID: item.id,
        name: item.name,
        packagedVolume: item.packagedVolume,
        source: source?.pricesByType[item.id],
        target: target?.pricesByType[item.id]
      )
    }
    return TradeCalculator.rows(
      items: inputs,
      mode: mode,
      sourceSide: sourceSide,
      targetSide: targetSide,
      sourceFees: runtime.tradeHubFees(for: mode.sourceRole),
      targetFees: runtime.tradeHubFees(for: mode.targetRole),
      transport: transport
    ).map { row in
      let history = histories?.historiesByType[row.typeID]
      // MARKTBESTAND_PLAN C4: partial fills from the market stock history.
      var hubVolumes: [MarketHistoryWindow: HubTradedVolume] = [:]
      var netChanges: [MarketHistoryWindow: MarketStockNetChange] = [:]
      for window in MarketHistoryWindow.allCases {
        hubVolumes[window] =
          hubUsesRegion
          ? history.map { HubTradedVolume.regionHistory($0, window: window) }
          : targetStock?.hubTradedVolume(for: row.typeID, window: window)
        netChanges[window] = targetStock?.netChange(for: row.typeID, window: window)
      }
      let today = targetStock?.hubTradedVolume(for: row.typeID, window: .oneDay)
      let average = targetStock?.hubTradedVolume(for: row.typeID, window: selectedWindow)
      return TradeDisplayRow(
        row: row,
        currentDailyDemand: today?.units,
        averageDailyDemand: average.map { Int64($0.averagePerRecordedDay.rounded()) },
        openLogbookQuantity: openQuantities[row.typeID] ?? 0,
        volumeHistory: history,
        hubTradedVolumes: hubVolumes,
        sourceStock: sourceStock?.currentStock(for: row.typeID),
        targetStock: targetStock?.currentStock(for: row.typeID),
        targetNetChanges: netChanges
      )
    }
  }

  // MARK: Table

  private let nameMinimumWidth: CGFloat = 200
  private let numberWidth: CGFloat = 96
  /// Number columns of a compact group tile (without ROI and details).
  private let compactNumberColumnCount = 11

  /// Name, the compact number columns with their spacing and the tile padding.
  private var compactTileMinimumWidth: CGFloat {
    let columns = CGFloat(compactNumberColumnCount)
    return nameMinimumWidth + columns * (numberWidth + DesignTokens.spacingXS)
      + 2 * DesignTokens.spacingMD
  }

  private var detailColumns: [(TradeSortColumn, LocalizedStringKey)] {
    var columns: [(TradeSortColumn, LocalizedStringKey)] = [
      (.purchaseCost, "Purchase"),
    ]
    if mode.requiresTransport {
      columns.append((.transportCost, "Transport"))
    }
    columns += [
      (.netSale, "Net sale"),
      (.profit, "Profit"),
      (.margin, "Margin"),
      (.returnOnInvestment, "ROI"),
      (.averageDailyVolume, "Ø region/day"),
      (.averageDailyDemand, "Ø demand/day"),
      (.currentDailyDemand, "Demand today"),
      (.sourceStock, "Stock source"),
      (.targetDepth, "Depth"),
      (.openLogbookQuantity, "Logbook open"),
    ]
    return columns
  }

  /// Detail columns without the ones a table already shows up front.
  private func visibleDetailColumns(
    showsReturnOnInvestment: Bool
  ) -> [(TradeSortColumn, LocalizedStringKey)] {
    showsReturnOnInvestment
      ? detailColumns.filter { $0.0 != .returnOnInvestment } : detailColumns
  }

  private func tableHeader(
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    sort: Binding<AppTableSortDescriptor<TradeSortColumn>>,
    showsReturnOnInvestment: Bool
  ) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      SortableTableHeader(title: "Name", column: TradeSortColumn.name, sort: sort)
        .frame(minWidth: nameMinimumWidth, maxWidth: .infinity, alignment: .leading)
      numberHeader(
        LocalizedStringKey(
          "\(TradeHubText.roleName(mode.sourceRole)) \(TradeHubText.sideName(sourceSide))"
        ),
        column: .sourcePrice,
        tint: DesignTokens.highlight,
        sort: sort
      )
      numberHeader(
        LocalizedStringKey(
          "\(TradeHubText.roleName(mode.targetRole)) \(TradeHubText.sideName(targetSide))"
        ),
        column: .targetPrice,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader("Diff %", column: .difference, tint: DesignTokens.accent, sort: sort)
      numberHeader(
        "Profit/m³",
        column: .profitPerCubicMeter,
        tint: DesignTokens.accent,
        sort: sort
      )
      if showsReturnOnInvestment {
        numberHeader("ROI", column: .returnOnInvestment, tint: DesignTokens.accent, sort: sort)
      }
      numberHeader(
        LocalizedStringKey(
          AppLocalization.format(
            hubVolumeUsesRegion ? "Target hub %lld d (region)" : "Target hub %lld d",
            Int64(volumeWindow.days)
          )
        ),
        column: .hubTradedVolume,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader("Stock target", column: .targetStock, tint: DesignTokens.accent, sort: sort)
      numberHeader(
        LocalizedStringKey(
          AppLocalization.format("Net target %lld d", Int64(volumeWindow.days))
        ),
        column: .targetNetChange,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader(
        LocalizedStringKey(AppLocalization.format("Region %lld d", Int64(volumeWindow.days))),
        column: .tradedVolume,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader(
        "Profit/day (region)",
        column: .dailyProfitPotential,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader(
        LocalizedStringKey(
          AppLocalization.format(
            hubVolumeUsesRegion
              ? "Profit potential target hub %lld d (region)"
              : "Profit potential target hub %lld d",
            Int64(volumeWindow.days)
          )
        ),
        column: .hubProfitPotential,
        tint: DesignTokens.accent,
        sort: sort
      )
      numberHeader(
        LocalizedStringKey(
          AppLocalization.format("Profit potential region %lld d", Int64(volumeWindow.days))
        ),
        column: .regionProfitPotential,
        tint: DesignTokens.accent,
        sort: sort
      )
      if showsDetails {
        ForEach(visibleDetailColumns(showsReturnOnInvestment: showsReturnOnInvestment), id: \.0) {
          column, title in
          numberHeader(title, column: column, tint: DesignTokens.textSecondary, sort: sort)
        }
      }
    }
    .font(.caption.weight(.semibold))
  }

  private func numberHeader(
    _ title: LocalizedStringKey,
    column: TradeSortColumn,
    tint: Color,
    sort: Binding<AppTableSortDescriptor<TradeSortColumn>>
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: sort,
      defaultDirection: .descending,
      alignment: .trailing
    )
    .foregroundStyle(tint)
    .frame(width: numberWidth, alignment: .trailing)
  }

  private func tableRow(
    _ display: TradeDisplayRow,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    identifierPrefix: String,
    showsReturnOnInvestment: Bool
  ) -> some View {
    let row = display.row
    return HStack(spacing: DesignTokens.spacingXS) {
      HStack(spacing: DesignTokens.spacingXS) {
        EVEItemText(
          value: row.name,
          typeID: row.typeID,
          font: .callout,
          lineLimit: 1,
          iconSize: 18
        )
        if !showsDetails, display.openLogbookQuantity > 0 {
          Label(formatInteger(display.openLogbookQuantity), systemImage: "book.closed")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            .help(AppLocalization.text("Units of open logbook entries for this hub"))
        }
        // A separate control so the name keeps its copy click.
        Button {
          logbookRequest = logbookRequest(
            for: row,
            sourceSide: sourceSide,
            targetSide: targetSide
          )
        } label: {
          Image(systemName: "plus.circle")
        }
        .buttonStyle(.borderless)
        .help(AppLocalization.text("Add to logbook"))
        .accessibilityLabel("Add to logbook")
        .accessibilityIdentifier("\(identifierPrefix).\(row.typeID).add-to-logbook")
        // Stock history of the item (MARKTBESTAND_PLAN P6), also separate
        // from the copy click.
        Button {
          stockHistoryRequest = MarketStockItemRequest(
            typeID: row.typeID,
            name: row.name,
            preferredRole: mode.targetRole
          )
        } label: {
          Image(systemName: "chart.xyaxis.line")
        }
        .buttonStyle(.borderless)
        .help(AppLocalization.text("Market stock history"))
        .accessibilityLabel("Market stock history")
        .accessibilityIdentifier("\(identifierPrefix).\(row.typeID).stock-history")
        if !row.issues.isEmpty {
          Image(systemName: "info.circle")
            .foregroundStyle(DesignTokens.caution)
            .help(row.issues.map(TradeHubText.issueText).joined(separator: "\n"))
            .accessibilityLabel(
              Text(row.issues.map(TradeHubText.issueText).joined(separator: " "))
            )
        }
      }
      .frame(minWidth: nameMinimumWidth, maxWidth: .infinity, alignment: .leading)
      numberCell(formatNumber(row.sourcePrice), tint: DesignTokens.highlight)
      numberCell(formatNumber(row.targetPrice), tint: DesignTokens.accent)
      differenceCell(row.differenceFraction)
      numberCell(
        formatNumber(row.profitPerCubicMeter),
        tint: signTint(row.profitPerCubicMeter)
      )
      if showsReturnOnInvestment {
        detailCell(display, column: .returnOnInvestment)
      }
      hubTradedVolumeCell(display)
      stockCell(display.targetStock, role: mode.targetRole)
      netChangeCell(display)
      tradedVolumeCell(display)
      detailCell(display, column: .dailyProfitPotential)
      hubProfitPotentialCell(display)
      regionProfitPotentialCell(display)
      if showsDetails {
        ForEach(visibleDetailColumns(showsReturnOnInvestment: showsReturnOnInvestment), id: \.0) {
          column, _ in
          detailCell(display, column: column)
        }
      }
    }
    .padding(.vertical, DesignTokens.spacingXS)
  }

  @ViewBuilder
  private func detailCell(
    _ display: TradeDisplayRow,
    column: TradeSortColumn
  ) -> some View {
    let row = display.row
    switch column {
    case .purchaseCost: numberCell(formatNumber(row.purchaseCost))
    case .transportCost: numberCell(formatNumber(row.transportCost))
    case .netSale: numberCell(formatNumber(row.netSale))
    case .profit: numberCell(formatNumber(row.profit), tint: signTint(row.profit))
    case .margin: numberCell(formatPercent(row.margin), tint: signTint(row.margin))
    case .returnOnInvestment:
      numberCell(formatPercent(row.returnOnInvestment), tint: signTint(row.returnOnInvestment))
    case .averageDailyDemand:
      numberCell(formatInteger(display.averageDailyDemand))
        .help(
          AppLocalization.format(
            "Ø units surely traded per recorded day at the target hub in the last %lld days (partial fills from its market stock history).",
            Int64(volumeWindow.days)
          )
        )
    case .currentDailyDemand:
      numberCell(formatInteger(display.currentDailyDemand))
        .help(
          AppLocalization.text(
            "Units surely traded at the target hub today since 00:00 UTC (partial fills from its market stock history)."
          )
        )
    case .sourceStock:
      stockCell(display.sourceStock, role: mode.sourceRole)
    case .targetDepth: numberCell(formatInteger(row.targetVolumeAtPrice))
    case .openLogbookQuantity:
      numberCell(formatInteger(display.openLogbookQuantity))
    case .averageDailyVolume:
      numberCell(formatNumber(display.averageDailyVolume(volumeWindow)))
    case .dailyProfitPotential:
      let value = display.dailyProfitPotential(volumeWindow)
      numberCell(formatNumber(value), tint: signTint(value))
        .help(
          AppLocalization.text(
            "Profit per unit × average traded units per day in the target region. An upper bound: other traders share this volume."
          )
        )
    default: numberCell("—")
    }
  }

  /// Profit per unit × units traded at the target hub in the selected window.
  /// Shown in the caution colour while the hub window has days without a scan.
  private func hubProfitPotentialCell(_ display: TradeDisplayRow) -> some View {
    let value = display.hubProfitPotential(volumeWindow)
    let incomplete = display.hubTradedVolume(volumeWindow).map { !$0.isComplete } ?? false
    return numberCell(
      formatWholeNumber(value),
      tint: incomplete && value != nil ? DesignTokens.caution : signTint(value)
    )
    .help(
      AppLocalization.text(
        hubVolumeUsesRegion
          ? "Profit per unit × units traded at the target hub in the selected window, taken from the regional ESI market history because the target hub is the only market of its region. An upper bound: other traders share this volume."
          : "Profit per unit × units surely traded at the target hub in the selected window (partial fills from its market stock history). Days without a known change are not counted; other traders share this volume."
      )
    )
  }

  /// Profit per unit × units traded in the target region in the selected window.
  private func regionProfitPotentialCell(_ display: TradeDisplayRow) -> some View {
    let value = display.regionProfitPotential(volumeWindow)
    return numberCell(formatWholeNumber(value), tint: signTint(value))
      .help(
        AppLocalization.text(
          "Profit per unit × units traded in the target region in the selected window. An upper bound: other traders share this volume."
        )
      )
  }

  /// Units traded in the selected window; the help lists every window or
  /// why the value is unknown.
  private func tradedVolumeCell(_ display: TradeDisplayRow) -> some View {
    let text: String
    if let history = display.volumeHistory {
      let windows = MarketHistoryWindow.allCases.map { window in
        AppLocalization.format(
          "%lld d: %@ units (Ø %@/day)",
          Int64(window.days),
          formatInteger(history.tradedVolume(window)),
          formatNumber(history.averageDailyVolume(window))
        )
      }
      text =
        AppLocalization.format(
          "ESI market history of the target hub's region, up to %@ (UTC). Buy and sell side are not separated.",
          history.anchorDay.formatted(
            Date.FormatStyle(date: .numeric, time: .omitted, timeZone: .gmt).locale(locale)
          )
        ) + "\n" + windows.joined(separator: "\n")
    } else {
      text = volumeHistoryUnknownText(typeID: display.id)
    }
    return numberCell(formatInteger(display.tradedVolume(volumeWindow)))
      .help(text)
      .accessibilityLabel(
        Text(
          AppLocalization.format(
            "Region %lld d: %@",
            Int64(volumeWindow.days),
            formatInteger(display.tradedVolume(volumeWindow))
          )
        )
      )
      .accessibilityHint(Text(text))
  }

  /// Units traded at the exact target hub in the selected window from its
  /// demand ledger. A window with days without a scan is shown in the
  /// caution colour; the help lists every window with its covered days.
  private func hubTradedVolumeCell(_ display: TradeDisplayRow) -> some View {
    let volume = display.hubTradedVolume(volumeWindow)
    let windows = MarketHistoryWindow.allCases.map { window in
      guard let value = display.hubTradedVolume(window) else {
        return AppLocalization.format("%lld d: no recorded day", Int64(window.days))
      }
      let line = AppLocalization.format(
        "%lld d: %@ units from %lld of %lld days (Ø %@ per recorded day)",
        Int64(window.days),
        formatInteger(value.units),
        Int64(value.recordedDays),
        Int64(value.windowDays),
        formatNumber(value.averagePerRecordedDay)
      )
      guard let upperBound = value.upperBoundUnits else { return line }
      var details = line + " · " + AppLocalization.format(
        "at most %@ incl. vanished orders",
        formatInteger(upperBound)
      )
      if value.partialDays > 0 {
        details += " · " + AppLocalization.format(
          "%lld days only partly recorded",
          Int64(value.partialDays)
        )
      }
      return details
    }
    let explanation =
      hubVolumeUsesRegion
      ? AppLocalization.text(
        "Regional ESI market history used as the target hub's volume, because the target hub is marked as the only market of its region in Market Settings. Up to yesterday (UTC); buy and sell side are not separated."
      )
      : AppLocalization.text(
        "Surely traded at the target hub itself: units by which still listed sell orders shrank between two market stock points (partial fills), summed per UTC day. The upper bound also counts orders that vanished completely (sold, cancelled or expired). Days without a known change are unknown and not counted."
      )
    let text = explanation + "\n" + windows.joined(separator: "\n")
    let valueText = formatInteger(volume?.units)
    return numberCell(
      valueText,
      tint: volume.map { $0.isComplete ? DesignTokens.textPrimary : DesignTokens.caution }
        ?? DesignTokens.textPrimary
    )
    .help(text)
    .accessibilityLabel(
      Text(
        volume.map {
          AppLocalization.format(
            "Target hub %lld d: %@ units from %lld of %lld days",
            Int64(volumeWindow.days),
            valueText,
            Int64($0.recordedDays),
            Int64($0.windowDays)
          )
        }
          ?? AppLocalization.format(
            "Target hub %lld d: %@",
            Int64(volumeWindow.days),
            valueText
          )
      )
    )
    .accessibilityHint(Text(text))
  }

  /// Sell units listed at a hub at its latest market stock point; the help
  /// adds orders, buy side and time (owner decision 29.10.2026).
  private func stockCell(
    _ stock: MarketStockItemValue?,
    role: OpportunityHubRole
  ) -> some View {
    let hub = TradeHubText.roleName(role)
    let text: String
    if let stock {
      text = AppLocalization.format(
        "%@: %@ units in %lld sell orders, %@ units in %lld buy orders at the latest market stock point (%@).",
        hub,
        formatInteger(stock.sell.units),
        Int64(stock.sell.orderCount),
        formatInteger(stock.buy.units),
        Int64(stock.buy.orderCount),
        runtime.marketStockOverview(for: role)?.latestCapturedAt.map {
          $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "—"
      )
    } else {
      text = AppLocalization.format(
        "%@: no market stock point yet. It is written by the next successful hub scan.",
        hub
      )
    }
    return numberCell(formatInteger(stock?.sell.units))
      .help(text)
      .accessibilityLabel(Text(text))
  }

  /// Sell-side added minus removed units at the target hub in the selected
  /// window; caution colour while days are missing or partial.
  private func netChangeCell(_ display: TradeDisplayRow) -> some View {
    let change = display.targetNetChange(volumeWindow)
    let windows = MarketHistoryWindow.allCases.map { window in
      guard let value = display.targetNetChange(window) else {
        return AppLocalization.format("%lld d: no known change", Int64(window.days))
      }
      return AppLocalization.format(
        "%lld d: added %@, partly sold %@, vanished %@, net %@ (%lld of %lld days)",
        Int64(window.days),
        formatInteger(value.sell.added),
        formatInteger(value.sell.partiallyFilled),
        formatInteger(value.sell.vanished),
        formatSignedInteger(value.net),
        Int64(value.recordedDays),
        Int64(value.windowDays)
      )
    }
    let text =
      AppLocalization.text(
        "Change of the sell units listed at the target hub: new orders minus partial fills and vanished orders (sold, cancelled or expired). Days without a known change are not counted."
      ) + "\n" + windows.joined(separator: "\n")
    let tint: Color =
      change.map {
        $0.isComplete ? signTint(Double($0.net)) : DesignTokens.caution
      } ?? DesignTokens.textPrimary
    return numberCell(change.map { formatSignedInteger($0.net) } ?? "—", tint: tint)
      .help(text)
      .accessibilityLabel(
        Text(
          AppLocalization.format(
            "Net target %lld d: %@",
            Int64(volumeWindow.days),
            change.map { formatSignedInteger($0.net) } ?? "—"
          )
        )
      )
      .accessibilityHint(Text(text))
  }

  private func formatSignedInteger(_ value: Int64) -> String {
    value.formatted(.number.sign(strategy: .always(includingZero: false)).locale(locale))
  }

  private struct MarketStockKey: Equatable {
    let mode: TradeMode
    let locations: [Int64?]
  }

  private var marketStockKey: MarketStockKey {
    MarketStockKey(
      mode: mode,
      locations: [mode.sourceRole, mode.targetRole].map {
        runtime.tradeLocation(for: $0)?.locationID
      }
    )
  }

  /// The target hub is marked as the only market of its region.
  private var hubVolumeUsesRegion: Bool {
    runtime.tradeHubIsOnlyMarketInRegion(mode.targetRole)
  }

  private func volumeHistoryUnknownText(typeID: Int64) -> String {
    guard let regionID = runtime.tradeRegionID(for: mode.targetRole) else {
      return AppLocalization.text("The region of the target hub is unknown.")
    }
    if runtime.tradeVolumeHistoryProgress[regionID] != nil {
      return AppLocalization.text("The market history is loading.")
    }
    if runtime.tradeVolumeHistories[regionID]?.unavailableTypeIDs.contains(typeID) == true {
      return AppLocalization.text("ESI did not provide a market history for this item.")
    }
    return AppLocalization.text("The market history has not been loaded yet.")
  }

  private func numberCell(
    _ text: String,
    tint: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: text)
      .font(.callout.monospacedDigit())
      .foregroundStyle(tint)
      .lineLimit(1)
      .frame(width: numberWidth, alignment: .trailing)
  }

  /// Arrows and colours follow the owner's reference image: a strong
  /// increase is red with a double arrow, an increase yellow, a decrease
  /// green.
  private func differenceCell(_ fraction: Double?) -> some View {
    let indicator = TradeDifferenceIndicator.classify(
      fraction,
      increaseThreshold: Double(coupledPercents.increase) / 100,
      strongIncreaseThreshold: Double(coupledPercents.strongIncrease) / 100
    )
    let (symbol, tint): (String?, Color) =
      switch indicator {
      case .strongIncrease: ("chevron.up.2", DesignTokens.negative)
      case .increase: ("chevron.up", DesignTokens.caution)
      case .decrease: ("chevron.down", DesignTokens.positive)
      case .neutral, nil: (nil, DesignTokens.textPrimary)
      }
    return HStack(spacing: 3) {
      if let symbol {
        Image(systemName: symbol).font(.caption2.bold())
      }
      Text(verbatim: formatPercent(fraction))
        .font(.callout.monospacedDigit())
    }
    .foregroundStyle(tint)
    .frame(width: numberWidth, alignment: .trailing)
  }

  private func signTint(_ value: Double?) -> Color {
    guard let value else { return DesignTokens.textPrimary }
    return value < 0 ? DesignTokens.negative : DesignTokens.positive
  }

  /// Prefills a logbook entry with the row's own order prices and frozen
  /// fees; the editor recalculates the exact transport for the quantity.
  private func logbookRequest(
    for row: TradeRow,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
  ) -> TradeLogbookEditorRequest {
    let sourceFees = runtime.tradeHubFees(for: mode.sourceRole)
    let targetFees = runtime.tradeHubFees(for: mode.targetRole)
    let buyPrice =
      sourceSide == .minSell
      ? row.sourcePrice : row.sourcePrice.flatMap(MarketPriceTick.nextAbove)
    let plannedPrice =
      targetSide == .minSell
      ? row.targetPrice.flatMap(MarketPriceTick.nextBelow) : row.targetPrice
    let transport = runtime.tradeTransportBases[mode.route] ?? .none
    return TradeLogbookEditorRequest(
      entry: TradeLogbookEntry(
        typeID: row.typeID,
        typeName: row.name,
        quantity: 1,
        buyUnitPrice: buyPrice ?? 0,
        buySide: sourceSide,
        buyBrokerFeeRate: sourceSide == .maxBuy ? sourceFees.brokerFeeRate : nil,
        sourceRole: mode.sourceRole,
        sourceLocationName: runtime.tradeLocation(for: mode.sourceRole)?.name,
        targetRole: mode.targetRole,
        targetLocationName: runtime.tradeLocation(for: mode.targetRole)?.name,
        plannedSellUnitPrice: plannedPrice,
        transportCostTotal: mode.requiresTransport ? nil : 0,
        salesTaxRate: targetFees.salesTaxRate,
        sellBrokerFeeRate: targetFees.brokerFeeRate
      ),
      isNew: true,
      packagedVolume: row.packagedVolume,
      transportBasis: transport
    )
  }

  // MARK: Formatting

  private var locale: Locale { AppLocalization.currentLanguage.locale }

  private func formatNumber(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    } ?? "—"
  }

  private func formatWholeNumber(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0)).locale(locale))
    } ?? "—"
  }

  private func formatInteger(_ value: Int64?) -> String {
    value.map { $0.formatted(.number.locale(locale)) } ?? "—"
  }

  private func formatPercent(_ fraction: Double?) -> String {
    fraction.map {
      $0.formatted(.percent.precision(.fractionLength(2)).locale(locale))
    } ?? "—"
  }

  // MARK: Loading

  private struct TransportKey: Equatable {
    let mode: TradeMode
    let logistics: LogisticsConfiguration
    let hubs: [ProcurementLocation?]
    let mainMarketCapturedAt: Date?
  }

  private var transportKey: TransportKey {
    TransportKey(
      mode: mode,
      logistics: runtime.productionBasis.logistics,
      hubs: [
        runtime.tradeLocation(for: .main),
        runtime.tradeLocation(for: .home),
        runtime.tradeLocation(for: .coalition),
      ],
      mainMarketCapturedAt: runtime.mainHubMarketState?.value?.capturedAt
    )
  }

  private struct VolumeHistoryKey: Equatable {
    let regionID: Int64?
    let typeIDs: Set<Int64>
  }

  private var volumeHistoryKey: VolumeHistoryKey {
    VolumeHistoryKey(
      regionID: runtime.tradeRegionID(for: mode.targetRole),
      typeIDs: Set(tiles.flatMap(\.items).map(\.id))
        .union(itemSearchMatches.prefix(itemSearchLimit).map(\.id))
    )
  }

  /// Queues the target region's market history for every item of the shown
  /// tiles; items already loaded today are not requested again.
  private func loadVolumeHistory() async {
    let key = volumeHistoryKey
    guard let regionID = key.regionID, !key.typeIDs.isEmpty else { return }
    await runtime.refreshTradeVolumeHistory(typeIDs: key.typeIDs, regionID: regionID)
  }

  private let itemSearchLimit = 50

  private var itemSearchQuery: String {
    itemSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Matches the catalog's minimum query length.
  private var isItemSearchActive: Bool { itemSearchQuery.count >= 2 }

  /// Waits briefly while typing; a newer query cancels this one.
  private func searchItems() async {
    guard isItemSearchActive else {
      itemSearchMatches = []
      itemSearchFailed = false
      isSearchingItems = false
      return
    }
    isSearchingItems = true
    try? await Task.sleep(for: .milliseconds(200))
    guard !Task.isCancelled else { return }
    do {
      let matches = try await runtime.searchTradeItems(
        matching: itemSearchQuery,
        limit: itemSearchLimit + 1
      )
      guard !Task.isCancelled else { return }
      itemSearchMatches = matches
      itemSearchFailed = false
    } catch {
      guard !Task.isCancelled else { return }
      itemSearchMatches = []
      itemSearchFailed = true
    }
    isSearchingItems = false
  }

  private func loadMarketGroups() async {
    guard marketGroups == nil else { return }
    do {
      marketGroups = try await runtime.tradeMarketGroups()
      marketGroupsFailed = false
      loadError = nil
    } catch {
      marketGroupsFailed = true
      loadError = AppLocalization.text(
        "The market groups of the active static data catalog could not be read."
      )
    }
  }

  private func loadTiles() async {
    guard selectedMarketGroupID != 0 else {
      tiles = []
      return
    }
    if marketGroups == nil { await loadMarketGroups() }
    guard let marketGroups, let node = selectedNode else {
      tiles = []
      return
    }
    isLoadingTiles = true
    defer { isLoadingTiles = false }
    do {
      let subtree = try await runtime.tradeItems(inMarketGroupSubtree: node.id)
      guard !Task.isCancelled else { return }
      tiles = TradeTileBuilder.tiles(
        node: node,
        groups: marketGroups.groups,
        subtreeItems: subtree.items
      )
      loadError = nil
    } catch {
      tiles = []
      loadError = AppLocalization.text(
        "The items of the selected market group could not be read."
      )
    }
  }
}
