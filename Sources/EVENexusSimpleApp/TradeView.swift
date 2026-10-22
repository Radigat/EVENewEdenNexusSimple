import EVENexusCore
import SwiftUI

/// The five separately presented trade views (HANDEL_PLAN.md, P4).
enum TradeModeOption: String, CaseIterable, Identifiable {
  case importHome
  case importCoalition
  case stationMain
  case stationHome
  case stationCoalition

  var id: Self { self }

  var mode: TradeMode {
    switch self {
    case .importHome: .importRoute(.home)
    case .importCoalition: .importRoute(.coalition)
    case .stationMain: .stationTrading(.main)
    case .stationHome: .stationTrading(.home)
    case .stationCoalition: .stationTrading(.coalition)
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .importHome: "Main → Home"
    case .importCoalition: "Main → Coalition"
    case .stationMain: "Station trading Main"
    case .stationHome: "Station trading Home"
    case .stationCoalition: "Station trading Coalition"
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
    case "jump-freighter.isotope-price-unavailable":
      AppLocalization.text("A Main Hub isotope price is missing, so the Jump Freighter fuel cost is unavailable.")
    default:
      AppLocalization.text("The Jump Freighter route from the Home Hub to the Coalition Hub is unavailable.")
    }
  }
}

struct TradeView: View {
  var onOpenMarketSettings: () -> Void = {}
  var onOpenLogistics: () -> Void = {}
  var onOpenSDESettings: () -> Void = {}

  @EnvironmentObject private var runtime: RuntimeState
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

  @State private var marketGroups: MarketGroupCatalogSnapshot?
  @State private var marketGroupsFailed = false
  @State private var tiles: [TradeTile] = []
  @State private var isLoadingTiles = false
  @State private var loadError: String?
  @State private var searchText = ""
  @State private var sourceSides: [Int64: TradeQuoteSide] = [:]
  @State private var targetSides: [Int64: TradeQuoteSide] = [:]
  @State private var sort = AppTableSortDescriptor(
    column: TradeSortColumn.name,
    direction: .ascending
  )
  @State private var logbookRequest: TradeLogbookEditorRequest?

  private var option: TradeModeOption {
    TradeModeOption(rawValue: modeRawValue) ?? .importHome
  }

  private var mode: TradeMode { option.mode }

  private var selectedNode: MarketGroupDefinition? {
    guard selectedMarketGroupID != 0 else { return nil }
    return marketGroups?.groups.first { $0.id == Int64(selectedMarketGroupID) }
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
    .task(id: transportKey) {
      guard case .importRoute(let target) = mode else { return }
      await runtime.refreshTradeTransportBasis(for: target)
    }
    .task {
      if runtime.tradeLogbookState == .notLoaded {
        await runtime.loadTradeLogbook()
      }
    }
    .sheet(item: $logbookRequest) { request in
      TradeLogbookEditor(request: request)
        .environmentObject(runtime)
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
    .disabled(isScanningHubs)
    .help(AppLocalization.text("Runs the Main, Home and Coalition Hub scan that also updates the Hub opportunities."))
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
    if case .importRoute = mode, runtime.tradeDataRole(for: mode.targetRole) == .main {
      messages.append(
        AppLocalization.format(
          "The %@ equals the Main Hub, so there is no import route.",
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
    if case .importRoute(let target) = mode {
      if let basis = runtime.tradeTransportBases[target] {
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
      AppLocalization.format(
        "Courier %@ → %@: %@ ISK per m³, at least %@ of the collateral, per unit without contract rounding.",
        courier.origin,
        courier.destination,
        formatNumber(courier.iskPerCubicMeter),
        formatPercent(courier.collateralRate)
      )
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

  private var indicatorSettings: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      Stepper(value: $increasePercent, in: 1...1_000) {
        Label(
          AppLocalization.format("Arrow from %lld %%", Int64(increasePercent)),
          systemImage: "chevron.up"
        )
      }
      .accessibilityIdentifier("trade.indicator.increase")
      Stepper(value: $strongIncreasePercent, in: 1...1_000) {
        Label(
          AppLocalization.format("Double arrow from %lld %%", Int64(strongIncreasePercent)),
          systemImage: "chevron.up.2"
        )
      }
      .accessibilityIdentifier("trade.indicator.strong-increase")
      Spacer()
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
      Panel(title: "Market group") {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          breadcrumb(groups: marketGroups.groups)
          TextField("Search market group", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
            .accessibilityIdentifier("trade.market-group-search")
          if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            groupList(searchResults(in: marketGroups.groups), groups: marketGroups.groups)
          } else if selectedNode == nil {
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
        LazyVGrid(
          columns: showsDetails
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.adaptive(minimum: 560), alignment: .top)],
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

  private func tileView(_ tile: TradeTile) -> some View {
    let sourceSide = sourceSides[tile.id] ?? .minSell
    let targetSide = targetSides[tile.id] ?? .minSell
    let rows = displayRows(for: tile, sourceSide: sourceSide, targetSide: targetSide)
    return VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
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
        Text(AppLocalization.format("Items: %lld", Int64(tile.items.count)))
          .font(.caption)
          .padding(.horizontal, DesignTokens.spacingSM)
          .padding(.vertical, DesignTokens.spacingXS)
          .overlay(Capsule().stroke(DesignTokens.border))
      }
      HStack(spacing: DesignTokens.spacingMD) {
        sidePicker(
          title: "Source side",
          selection: Binding(
            get: { sourceSides[tile.id] ?? .minSell },
            set: { sourceSides[tile.id] = $0 }
          ),
          identifier: "trade.tile.\(tile.id).source-side"
        )
        sidePicker(
          title: "Target side",
          selection: Binding(
            get: { targetSides[tile.id] ?? .minSell },
            set: { targetSides[tile.id] = $0 }
          ),
          identifier: "trade.tile.\(tile.id).target-side"
        )
      }
      if showsDetails {
        // The detail columns are wider than the window; they scroll inside
        // the tile instead of pushing the layout under the sidebar.
        ScrollView(.horizontal) {
          table(rows: rows, sourceSide: sourceSide, targetSide: targetSide)
        }
      } else {
        table(rows: rows, sourceSide: sourceSide, targetSide: targetSide)
      }
    }
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
    .accessibilityIdentifier("trade.tile.\(tile.id)")
  }

  private func table(
    rows: [TradeDisplayRow],
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      tableHeader(sourceSide: sourceSide, targetSide: targetSide)
      Divider()
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(rows) { row in
          tableRow(row, sourceSide: sourceSide, targetSide: targetSide)
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
    let source = runtime.tradeMarketState(for: mode.sourceRole)?.value
    let target = runtime.tradeMarketState(for: mode.targetRole)?.value
    let demand = runtime.tradeDemand(for: mode.targetRole)
    let openQuantities = TradeLogbookSummary.openQuantities(
      runtime.tradeLogbookEntries,
      targetRole: mode.targetRole
    )
    let transport: TradeTransportBasis =
      switch mode {
      case .importRoute(let importTarget):
        runtime.tradeTransportBases[importTarget] ?? .none
      case .stationTrading:
        .none
      }
    let inputs = tile.items.map { item in
      TradeItemInput(
        typeID: item.id,
        name: item.name,
        packagedVolume: item.packagedVolume,
        source: source?.pricesByType[item.id],
        target: target?.pricesByType[item.id]
      )
    }
    let rows = TradeCalculator.rows(
      items: inputs,
      mode: mode,
      sourceSide: sourceSide,
      targetSide: targetSide,
      sourceFees: runtime.tradeHubFees(for: mode.sourceRole),
      targetFees: runtime.tradeHubFees(for: mode.targetRole),
      transport: transport
    ).map { row in
      let summary = demand?.dailySummary(for: row.typeID)
      return TradeDisplayRow(
        row: row,
        currentDailyDemand: summary?.currentUnits,
        averageDailyDemand: summary?.averageUnits,
        openLogbookQuantity: openQuantities[row.typeID] ?? 0
      )
    }
    return TradeRowSorter.sorted(
      rows,
      by: sort.column,
      ascending: sort.direction == .ascending
    )
  }

  // MARK: Table

  private let nameMinimumWidth: CGFloat = 200
  private let numberWidth: CGFloat = 96

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
      (.averageDailyDemand, "Ø demand/day"),
      (.currentDailyDemand, "Demand today"),
      (.targetDepth, "Depth"),
      (.openLogbookQuantity, "Logbook open"),
    ]
    return columns
  }

  private func tableHeader(
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
  ) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      SortableTableHeader(title: "Name", column: TradeSortColumn.name, sort: $sort)
        .frame(minWidth: nameMinimumWidth, maxWidth: .infinity, alignment: .leading)
      numberHeader(
        LocalizedStringKey(
          "\(TradeHubText.roleName(mode.sourceRole)) \(TradeHubText.sideName(sourceSide))"
        ),
        column: .sourcePrice,
        tint: DesignTokens.highlight
      )
      numberHeader(
        LocalizedStringKey(
          "\(TradeHubText.roleName(mode.targetRole)) \(TradeHubText.sideName(targetSide))"
        ),
        column: .targetPrice,
        tint: DesignTokens.accent
      )
      numberHeader("Diff %", column: .difference, tint: DesignTokens.accent)
      if showsDetails {
        ForEach(detailColumns, id: \.0) { column, title in
          numberHeader(title, column: column, tint: DesignTokens.textSecondary)
        }
      }
    }
    .font(.caption.weight(.semibold))
  }

  private func numberHeader(
    _ title: LocalizedStringKey,
    column: TradeSortColumn,
    tint: Color
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      defaultDirection: .descending,
      alignment: .trailing
    )
    .foregroundStyle(tint)
    .frame(width: numberWidth, alignment: .trailing)
  }

  private func tableRow(
    _ display: TradeDisplayRow,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide
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
        .accessibilityIdentifier("trade.row.\(row.typeID).add-to-logbook")
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
      if showsDetails {
        ForEach(detailColumns, id: \.0) { column, _ in
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
    case .averageDailyDemand: numberCell(formatInteger(display.averageDailyDemand))
    case .currentDailyDemand: numberCell(formatInteger(display.currentDailyDemand))
    case .targetDepth: numberCell(formatInteger(row.targetVolumeAtPrice))
    case .openLogbookQuantity:
      numberCell(formatInteger(display.openLogbookQuantity))
    default: numberCell("—")
    }
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
      increaseThreshold: Double(increasePercent) / 100,
      strongIncreaseThreshold: Double(strongIncreasePercent) / 100
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
    let transport: TradeTransportBasis =
      switch mode {
      case .importRoute(let target): runtime.tradeTransportBases[target] ?? .none
      case .stationTrading: .none
      }
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
