import EVENexusCore
import SwiftUI

/// "Market stock" (MARKTBESTAND_PLAN P7): every item of a hub's latest
/// stock point with stock, orders, best prices and the sell-side net and
/// removed units of 1, 7 and 30 days.
struct MarketStockView: View {
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.locale) private var locale
  @AppStorage("market-stock.hub", store: AppDefaults.store)
  private var storedRole = OpportunityHubRole.main.rawValue
  @State private var searchText = ""
  @State private var marketGroups: MarketGroupCatalogSnapshot?
  @State private var selectedRootGroupID: Int64 = 0
  /// Items of the selected market group subtree; `nil` without a filter.
  @State private var groupTypeIDs: Set<Int64>?
  @State private var names: [Int64: String] = [:]
  @State private var allRows: [MarketStockOverviewRow] = []
  /// Kept while the view lives, also when new points arrive.
  @State private var sortOrder = [
    MarketStockOverviewComparator(column: .sellUnits, order: .reverse)
  ]
  @State private var detailRequest: MarketStockItemRequest?

  private static let consumer = "market-stock"
  private static let windows = [1, 7, 30]

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      if runtime.marketStockHubRoles.isEmpty {
        Label(
          "No hub with a known location is configured. Set the Main, Home or Coalition Hub in Market Settings.",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(DesignTokens.caution)
      } else {
        controls
        status
        content
      }
    }
    .padding(DesignTokens.spacingLG)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .navigationTitle(AppLocalization.text("Market stock"))
    .task(id: role) {
      await runtime.refreshMarketStockOverviews(for: [role], consumer: Self.consumer)
      await rebuildRows()
    }
    .task(id: overviewStamp) { await rebuildRows() }
    .task { await loadMarketGroups() }
    .task(id: selectedRootGroupID) { await loadGroupFilter() }
    .onDisappear { runtime.releaseMarketStockOverviews(consumer: Self.consumer) }
    .sheet(item: $detailRequest) { request in
      MarketStockItemDetailView(request: request)
        .environment(runtime)
    }
  }

  // MARK: Header and controls

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Market stock")
        .font(.largeTitle.bold())
      Text(
        "Every item listed at a hub at its latest market stock point, with the change of its sell stock. Partly sold units are surely traded; vanished orders were sold, cancelled or expired."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var role: OpportunityHubRole {
    let roles = runtime.marketStockHubRoles
    let stored = OpportunityHubRole(rawValue: storedRole) ?? .main
    return roles.contains(stored) ? stored : roles.first ?? .main
  }

  private var controls: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      Picker("Hub", selection: roleBinding) {
        ForEach(runtime.marketStockHubRoles, id: \.self) { role in
          Text(TradeHubText.roleName(role)).tag(role)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 420)
      .accessibilityIdentifier("market-stock.hub")
      TextField("Search item", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 260)
        .accessibilityIdentifier("market-stock.search")
      Picker("Market group", selection: $selectedRootGroupID) {
        Text("All market groups").tag(Int64(0))
        ForEach(rootGroups, id: \.id) { group in
          Text(group.name).tag(group.id)
        }
      }
      .frame(maxWidth: 300)
      .disabled(marketGroups?.availability != .available)
      .accessibilityIdentifier("market-stock.market-group")
    }
  }

  private var roleBinding: Binding<OpportunityHubRole> {
    Binding(get: { role }, set: { storedRole = $0.rawValue })
  }

  private var rootGroups: [MarketGroupDefinition] {
    (marketGroups?.groups ?? [])
      .filter { $0.parentID == nil }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private var overview: MarketStockHubOverview? {
    runtime.marketStockOverview(for: role)
  }

  @ViewBuilder
  private var status: some View {
    if let overview, let latest = overview.latestCapturedAt {
      let coverage = Self.windows.compactMap { days in
        overview.coverage.first { $0.days == days }.map { window in
          AppLocalization.format(
            "%lld d: %lld of %lld days recorded",
            Int64(days),
            Int64(window.daysWithKnownDelta),
            Int64(days)
          )
        }
      }
      Text(
        AppLocalization.format(
          "Latest point %@ · %lld items",
          latest.formatted(date: .abbreviated, time: .shortened),
          Int64(overview.itemsByType.count)
        ) + " · " + coverage.joined(separator: " · ")
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  @ViewBuilder
  private var content: some View {
    if overview == nil {
      ProgressView("Loading market stock…")
        .frame(maxWidth: .infinity, alignment: .center)
    } else if overview?.latestCapturedAt == nil {
      Label(
        "No market stock point for this hub yet. It is written by the next successful hub scan.",
        systemImage: "chart.bar.xaxis"
      )
      .foregroundStyle(DesignTokens.textSecondary)
    } else {
      table
    }
  }

  // MARK: Table

  private var displayedRows: [MarketStockOverviewRow] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return allRows.filter { row in
      if let groupTypeIDs, !groupTypeIDs.contains(row.typeID) { return false }
      guard !query.isEmpty else { return true }
      return row.name?.localizedCaseInsensitiveContains(query) ?? false
    }
    .sorted(using: sortOrder)
  }

  private var table: some View {
    Table(displayedRows, sortOrder: $sortOrder) {
      TableColumn("Name", sortUsing: MarketStockOverviewComparator(column: .name)) { row in
        nameCell(row)
      }
      .width(min: 220, ideal: 280)
      Group {
        numberColumn("Sell stock", .sellUnits) { formatInteger($0.current.sell.units) }
        numberColumn("Sell orders", .sellOrders) { formatInteger(Int64($0.current.sell.orderCount)) }
        numberColumn("Lowest sell", .bestSell) { formatPrice($0.current.sell.bestPrice) }
        numberColumn("Buy demand", .buyUnits) { formatInteger($0.current.buy.units) }
        numberColumn("Buy orders", .buyOrders) { formatInteger(Int64($0.current.buy.orderCount)) }
        numberColumn("Highest buy", .bestBuy) { formatPrice($0.current.buy.bestPrice) }
      }
      Group {
        changeColumn("Net 1 d", days: 1, net: true)
        changeColumn("Removed 1 d", days: 1, net: false)
        changeColumn("Net 7 d", days: 7, net: true)
        changeColumn("Removed 7 d", days: 7, net: false)
        changeColumn("Net 30 d", days: 30, net: true)
        changeColumn("Removed 30 d", days: 30, net: false)
      }
    }
    .accessibilityIdentifier("market-stock.table")
  }

  private func numberColumn(
    _ title: LocalizedStringKey,
    _ column: MarketStockOverviewRow.Column,
    text: @escaping (MarketStockOverviewRow) -> String
  ) -> some TableColumnContent<MarketStockOverviewRow, MarketStockOverviewComparator> {
    TableColumn(title, sortUsing: MarketStockOverviewComparator(column: column)) { row in
      Text(text(row))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .width(min: 80, ideal: 100)
  }

  private func changeColumn(
    _ title: LocalizedStringKey,
    days: Int,
    net: Bool
  ) -> some TableColumnContent<MarketStockOverviewRow, MarketStockOverviewComparator> {
    let column: MarketStockOverviewRow.Column =
      net ? .net(days: days) : .removed(days: days)
    let isComplete = overview?.coverage.first { $0.days == days }?.isComplete ?? false
    return TableColumn(title, sortUsing: MarketStockOverviewComparator(column: column)) { row in
      let value = net ? row.netByWindow[days] : row.removedByWindow[days]
      Text(value.map { net ? formatSigned($0) : formatInteger($0) } ?? "—")
        .monospacedDigit()
        .foregroundStyle(
          !isComplete && value != nil
            ? DesignTokens.caution
            : net
              ? value.map { $0 < 0 ? DesignTokens.negative : $0 > 0 ? DesignTokens.positive : DesignTokens.textPrimary }
                ?? DesignTokens.textPrimary
              : DesignTokens.textPrimary
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help(
          isComplete
            ? ""
            : AppLocalization.text(
              "Days of this window are missing or only partly recorded; the value covers only the recorded days."
            )
        )
    }
    .width(min: 80, ideal: 100)
  }

  private func nameCell(_ row: MarketStockOverviewRow) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      if let name = row.name {
        EVEItemText(value: name, typeID: row.typeID, font: .callout, lineLimit: 1, iconSize: 18)
      } else {
        Text(
          AppLocalization.format("Unresolved type (ID %lld)", row.typeID)
        )
        .foregroundStyle(DesignTokens.textSecondary)
        .help(AppLocalization.text("The active SDE has no name for this type."))
      }
      Spacer(minLength: DesignTokens.spacingXS)
      // Separate from the copy click (MARKTBESTAND_PLAN P6/P7).
      Button {
        detailRequest = MarketStockItemRequest(
          typeID: row.typeID,
          name: row.name
            ?? AppLocalization.format("Unresolved type (ID %lld)", row.typeID),
          preferredRole: role
        )
      } label: {
        Image(systemName: "chart.xyaxis.line")
      }
      .buttonStyle(.borderless)
      .help(AppLocalization.text("Market stock history"))
      .accessibilityLabel("Market stock history")
      .accessibilityIdentifier("market-stock.\(row.typeID).history")
    }
  }

  // MARK: Loading

  /// Changes whenever the overview or the resolved names change.
  private var overviewStamp: String {
    "\(role.rawValue)|\(overview?.latestCapturedAt?.timeIntervalSince1970 ?? 0)|\(overview?.itemsByType.count ?? -1)"
  }

  private func rebuildRows() async {
    guard let overview else {
      allRows = []
      return
    }
    let missing = Set(overview.itemsByType.keys).subtracting(names.keys)
    if !missing.isEmpty {
      let resolved = await runtime.marketStockTypeNames(ids: missing)
      names.merge(resolved) { current, _ in current }
    }
    allRows = MarketStockOverviewRow.rows(overview, names: names)
  }

  private func loadMarketGroups() async {
    guard marketGroups == nil else { return }
    marketGroups = try? await runtime.tradeMarketGroups()
  }

  private func loadGroupFilter() async {
    guard selectedRootGroupID != 0 else {
      groupTypeIDs = nil
      return
    }
    let subtree = try? await runtime.tradeItems(inMarketGroupSubtree: selectedRootGroupID)
    guard !Task.isCancelled else { return }
    groupTypeIDs = Set(subtree?.items.map(\.id) ?? [])
  }

  // MARK: Formatting

  private func formatInteger(_ value: Int64) -> String {
    value.formatted(.number.locale(locale))
  }

  private func formatSigned(_ value: Int64) -> String {
    value.formatted(.number.sign(strategy: .always(includingZero: false)).locale(locale))
  }

  private func formatPrice(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    } ?? "—"
  }
}
