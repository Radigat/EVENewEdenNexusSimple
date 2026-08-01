import EVENexusCore
import SwiftUI

struct MarketBrowserView: View {
  @EnvironmentObject private var runtime: RuntimeState

  @State private var itemQuery = ""
  @State private var itemResults: [ItemTypeSearchResult] = []
  @State private var selectedItem: ItemTypeSearchResult?
  @State private var itemSearchError: String?
  @State private var originQuery = ""
  @State private var originResults: [SolarSystemOption] = []
  @State private var selectedOrigin: SolarSystemOption?
  @State private var originSearchError: String?
  @State private var didAdoptProfileOrigin = false
  @State private var showsFilters = true
  @State private var filter = MarketBrowserFilter()
  @State private var minimumPriceText = ""
  @State private var maximumPriceText = ""
  @State private var minimumQuantityText = ""
  @State private var maximumJumpsText = ""
  @State private var sellerSort: MarketBrowserSort = .priceAscending
  @State private var buyerSort: MarketBrowserSort = .priceDescending

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      selectionPanel
      if showsFilters { filterPanel }

      if let error = runtime.marketBrowserError {
        Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(DesignTokens.negative)
      }

      if let sourced = runtime.marketBrowserState,
        let snapshot = sourced.value,
        snapshot.typeID == selectedItem?.id
      {
        summary(snapshot)
        sourceStatus(sourced, snapshot: snapshot)
        orderPanes(snapshot)
      } else if runtime.isRefreshingMarketBrowser {
        Spacer()
        ProgressView("Loading market orders from all ESI regions…")
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        Spacer()
        ContentUnavailableView(
          "Select an item",
          systemImage: "chart.bar.doc.horizontal",
          description: Text(
            "Search the active SDE catalog, then load public sell and buy orders across every ESI region."
          )
        )
        Spacer()
      }
    }
    .padding(DesignTokens.spacingLG)
    .task {
      adoptProfileOriginIfNeeded()
    }
    .task(id: itemQuery) {
      await updateItemResults()
    }
    .task(id: originQuery) {
      await updateOriginResults()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Market Browser")
          .font(.largeTitle.bold())
          .foregroundStyle(DesignTokens.textPrimary)
        Text(
          "Compare public sell and buy orders across New Eden without turning unavailable regions, locations, or routes into zero values."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer(minLength: DesignTokens.spacingMD)
      Button {
        showsFilters.toggle()
      } label: {
        Label(
          showsFilters ? "Hide filters" : "Show filters",
          systemImage: "line.3.horizontal.decrease.circle"
        )
      }
      Button {
        refresh()
      } label: {
        if runtime.isRefreshingMarketBrowser {
          ProgressView().controlSize(.small)
        } else {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(selectedItem == nil || runtime.isRefreshingMarketBrowser)
      .accessibilityIdentifier("market-browser.refresh")
    }
  }

  private var selectionPanel: some View {
    Panel(title: "Market selection") {
      HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
        searchColumn(
          title: "Item",
          placeholder: "Search item name (3+ characters)",
          query: $itemQuery,
          error: itemSearchError
        ) {
          itemResultList
        } selection: {
          if let selectedItem {
            selectionBadge(
              title: selectedItem.name,
              detail: "Type ID \(selectedItem.id)",
              clearLabel: "Clear item"
            ) {
              self.selectedItem = nil
              itemResults = []
            }
          } else {
            Text("No item selected")
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }

        Divider()

        searchColumn(
          title: "Route origin",
          placeholder: "Search solar system (3+ characters)",
          query: $originQuery,
          error: originSearchError
        ) {
          originResultList
        } selection: {
          if let selectedOrigin {
            selectionBadge(
              title: selectedOrigin.name,
              detail: "System ID \(selectedOrigin.id)",
              clearLabel: "Do not calculate jumps"
            ) {
              self.selectedOrigin = nil
              originResults = []
            }
          } else {
            Text("No origin: jumps stay not checked")
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
      }
    }
  }

  private func searchColumn<Results: View, Selection: View>(
    title: LocalizedStringKey,
    placeholder: LocalizedStringKey,
    query: Binding<String>,
    error: String?,
    @ViewBuilder results: () -> Results,
    @ViewBuilder selection: () -> Selection
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text(title).font(.subheadline.bold())
      TextField(placeholder, text: query)
        .textFieldStyle(.roundedBorder)
      selection()
      if let error {
        Text(error.localizedUI)
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
      results()
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  @ViewBuilder private var itemResultList: some View {
    if !itemResults.isEmpty {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(itemResults) { item in
            Button {
              selectedItem = item
              itemQuery = ""
              itemResults = []
              refresh()
            } label: {
              HStack {
                Text(verbatim: item.name)
                Spacer()
                Text(verbatim: String(item.id))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(DesignTokens.textSecondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.spacingSM)
            .padding(.vertical, DesignTokens.spacingXS)
          }
        }
      }
      .frame(maxHeight: 140)
      .background(DesignTokens.elevated)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    }
  }

  @ViewBuilder private var originResultList: some View {
    if !originResults.isEmpty {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(originResults) { system in
            Button {
              selectedOrigin = system
              originQuery = ""
              originResults = []
              if selectedItem != nil { refresh() }
            } label: {
              HStack {
                Text(verbatim: system.name)
                Spacer()
                Text(verbatim: String(system.id))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(DesignTokens.textSecondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.spacingSM)
            .padding(.vertical, DesignTokens.spacingXS)
          }
        }
      }
      .frame(maxHeight: 140)
      .background(DesignTokens.elevated)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    }
  }

  private func selectionBadge(
    title: String,
    detail: String,
    clearLabel: LocalizedStringKey,
    clear: @escaping () -> Void
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title).font(.callout.bold())
        Text(verbatim: detail)
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
      Button(clearLabel, action: clear)
        .buttonStyle(.borderless)
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.accentSoft)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private var filterPanel: some View {
    Panel(title: "Order filters") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingMD) {
          TextField("Region contains", text: $filter.regionQuery)
          TextField("Location or system contains", text: $filter.locationQuery)
          TextField("Minimum price", text: $minimumPriceText)
          TextField("Maximum price", text: $maximumPriceText)
          TextField("Minimum quantity", text: $minimumQuantityText)
          TextField("Maximum jumps", text: $maximumJumpsText)
        }
        .textFieldStyle(.roundedBorder)
        HStack(spacing: DesignTokens.spacingLG) {
          Toggle("NPC stations", isOn: $filter.includesNPCStations)
          Toggle("Player structures", isOn: $filter.includesPlayerStructures)
          Toggle("Market hubs only", isOn: $filter.marketHubsOnly)
          Toggle(
            "Keep routes not checked",
            isOn: $filter.includesUncheckedRoutes
          )
          Spacer()
          Button("Reset filters") {
            filter = MarketBrowserFilter()
            minimumPriceText = ""
            maximumPriceText = ""
            minimumQuantityText = ""
            maximumJumpsText = ""
          }
          .buttonStyle(.borderless)
        }
        .toggleStyle(.checkbox)
        Text(
          "Player-structure docking rights are not published with public market orders. A visible order therefore does not prove that your character can dock there."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private func summary(_ snapshot: MarketBrowserSnapshot) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      metric("Best sell", value: formatPrice(snapshot.summary.bestSellPrice))
      metric("Best buy", value: formatPrice(snapshot.summary.bestBuyPrice))
      metric(
        "Average active sell",
        value: formatPrice(snapshot.summary.weightedAverageSellPrice)
      )
      metric(
        "Active sell volume",
        value: formatQuantity(snapshot.summary.activeSellVolume)
      )
      metric(
        "Active buy volume",
        value: formatQuantity(snapshot.summary.activeBuyVolume)
      )
      metric(
        "Regions with orders",
        value: "\(snapshot.summary.representedRegionCount)"
      )
    }
  }

  private func metric(_ title: LocalizedStringKey, value: String) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border)
    }
  }

  private func sourceStatus(
    _ sourced: Sourced<MarketBrowserSnapshot>,
    snapshot: MarketBrowserSnapshot
  ) -> some View {
    HStack(spacing: DesignTokens.spacingMD) {
      Label(
        sourceStateLabel(sourced.state),
        systemImage:
          sourced.state == .fresh
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(
        sourced.state == .fresh ? DesignTokens.positive : DesignTokens.caution
      )
      Text(
        verbatim:
          "\(snapshot.loadedRegionCount)/\(snapshot.regionCount) regions · \(snapshot.orders.count) active orders"
      )
      if !snapshot.regionFailures.isEmpty {
        Text(
          verbatim: "\(snapshot.regionFailures.count) regions unavailable"
        )
        .foregroundStyle(DesignTokens.caution)
        .help(
          snapshot.regionFailures.prefix(20).map {
            "\($0.regionName): \($0.diagnostic)"
          }.joined(separator: "\n")
        )
      }
      Spacer()
      Text(
        verbatim:
          "ESI \(snapshot.source.version) · \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))"
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
    .font(.caption)
  }

  private func orderPanes(_ snapshot: MarketBrowserSnapshot) -> some View {
    VSplitView {
      orderTable(
        title: "Sellers",
        side: .sell,
        orders: sortedOrders(snapshot, side: .sell),
        sort: $sellerSort
      )
      .frame(minHeight: 190)
      orderTable(
        title: "Buyers",
        side: .buy,
        orders: sortedOrders(snapshot, side: .buy),
        sort: $buyerSort
      )
      .frame(minHeight: 190)
    }
  }

  private func orderTable(
    title: LocalizedStringKey,
    side: MarketOrderSide,
    orders: [MarketBrowserOrder],
    sort: Binding<MarketBrowserSort>
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        Text(title).font(.title3.bold())
        Text(verbatim: "\(orders.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
      }
      ScrollView(.horizontal) {
        VStack(spacing: 0) {
          orderHeader(side: side, sort: sort)
          Divider()
          ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
              ForEach(orders) { order in
                orderRow(order, side: side)
                Divider()
              }
            }
          }
        }
        .frame(minWidth: side == .sell ? 1_090 : 1_280)
      }
      .background(DesignTokens.panel)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
      .overlay {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.border)
      }
    }
  }

  private func orderHeader(
    side: MarketOrderSide,
    sort: Binding<MarketBrowserSort>
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      sortHeader("Region", width: 130, sort: .regionAscending, binding: sort)
      sortHeader("Quantity", width: 100, sort: .quantityDescending, binding: sort)
      sortHeader(
        "Price",
        width: 120,
        sort: side == .sell ? .priceAscending : .priceDescending,
        binding: sort
      )
      sortHeader("Location", width: 300, sort: .locationAscending, binding: sort)
      sortHeader("Jumps", width: 72, sort: .jumpsAscending, binding: sort)
      if side == .buy {
        plainHeader("Range", width: 90)
        plainHeader("Min volume", width: 92)
      }
      sortHeader("Expires in", width: 108, sort: .expiresAscending, binding: sort)
      sortHeader("ESI updated", width: 140, sort: .modifiedDescending, binding: sort)
    }
    .font(.caption.bold())
    .textCase(.uppercase)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
  }

  private func sortHeader(
    _ title: LocalizedStringKey,
    width: CGFloat,
    sort: MarketBrowserSort,
    binding: Binding<MarketBrowserSort>
  ) -> some View {
    Button {
      binding.wrappedValue = sort
    } label: {
      HStack(spacing: 3) {
        Text(title)
        if binding.wrappedValue == sort {
          Image(systemName: sort.isAscending ? "chevron.up" : "chevron.down")
            .font(.caption2)
        }
      }
      .frame(width: width, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func plainHeader(
    _ title: LocalizedStringKey,
    width: CGFloat
  ) -> some View {
    Text(title).frame(width: width, alignment: .leading)
  }

  private func orderRow(
    _ order: MarketBrowserOrder,
    side: MarketOrderSide
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      orderCell(order.regionName, width: 130)
      orderCell(formatQuantity(order.volumeRemaining), width: 100, numeric: true)
      orderCell(formatPrice(order.price), width: 120, numeric: true)
      orderCell(locationLabel(order), width: 300)
      orderCell(jumpsLabel(order), width: 72, numeric: true)
        .foregroundStyle(
          order.routeState == .unreachable
            ? DesignTokens.negative : DesignTokens.textPrimary
        )
      if side == .buy {
        orderCell(order.range, width: 90)
        orderCell(formatQuantity(order.minimumVolume), width: 92, numeric: true)
      }
      orderCell(relativeExpiry(order.expiresAt), width: 108)
      orderCell(
        (order.esiLastModifiedAt ?? order.observedAt).formatted(
          date: .abbreviated,
          time: .shortened
        ),
        width: 140
      )
      .help(
        "This is the ESI regional dataset timestamp, not a guaranteed per-order edit timestamp."
      )
    }
    .font(.caption)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, 6)
    .background(DesignTokens.panel)
  }

  private func orderCell(
    _ value: String,
    width: CGFloat,
    numeric: Bool = false
  ) -> some View {
    Text(verbatim: value)
      .font(numeric ? .caption.monospacedDigit() : .caption)
      .lineLimit(2)
      .frame(width: width, alignment: .leading)
  }

  private func sortedOrders(
    _ snapshot: MarketBrowserSnapshot,
    side: MarketOrderSide
  ) -> [MarketBrowserOrder] {
    let accepted = snapshot.orders.filter {
      $0.side == side && effectiveFilter.accepts($0)
    }
    let sort = side == .sell ? sellerSort : buyerSort
    return accepted.sorted { lhs, rhs in
      switch sort {
      case .priceAscending:
        lhs.price == rhs.price ? lhs.id < rhs.id : lhs.price < rhs.price
      case .priceDescending:
        lhs.price == rhs.price ? lhs.id < rhs.id : lhs.price > rhs.price
      case .quantityDescending:
        lhs.volumeRemaining == rhs.volumeRemaining
          ? lhs.id < rhs.id : lhs.volumeRemaining > rhs.volumeRemaining
      case .regionAscending:
        lhs.regionName == rhs.regionName
          ? lhs.id < rhs.id : lhs.regionName < rhs.regionName
      case .locationAscending:
        locationLabel(lhs) == locationLabel(rhs)
          ? lhs.id < rhs.id : locationLabel(lhs) < locationLabel(rhs)
      case .jumpsAscending:
        (lhs.jumps ?? Int.max) == (rhs.jumps ?? Int.max)
          ? lhs.id < rhs.id : (lhs.jumps ?? Int.max) < (rhs.jumps ?? Int.max)
      case .expiresAscending:
        lhs.expiresAt == rhs.expiresAt
          ? lhs.id < rhs.id : lhs.expiresAt < rhs.expiresAt
      case .modifiedDescending:
        (lhs.esiLastModifiedAt ?? lhs.observedAt)
          == (rhs.esiLastModifiedAt ?? rhs.observedAt)
          ? lhs.id < rhs.id
          : (lhs.esiLastModifiedAt ?? lhs.observedAt)
            > (rhs.esiLastModifiedAt ?? rhs.observedAt)
      }
    }
  }

  private var effectiveFilter: MarketBrowserFilter {
    var accepted = filter
    accepted.minimumPrice = parseDouble(minimumPriceText)
    accepted.maximumPrice = parseDouble(maximumPriceText)
    accepted.minimumQuantity = Int64(minimumQuantityText)
    accepted.maximumJumps = Int(maximumJumpsText)
    return accepted
  }

  private func updateItemResults() async {
    let accepted = itemQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else {
      itemResults = []
      itemSearchError = nil
      return
    }
    do {
      try await Task.sleep(for: .milliseconds(180))
      itemResults = try await runtime.searchMarketTypes(matching: accepted)
      itemSearchError = nil
    } catch is CancellationError {
      return
    } catch StaticCatalogError.noActiveCatalog {
      itemResults = []
      itemSearchError = "No active SDE catalog is installed."
    } catch {
      itemResults = []
      itemSearchError = "Item search is currently unavailable."
    }
  }

  private func updateOriginResults() async {
    let accepted = originQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else {
      originResults = []
      originSearchError = nil
      return
    }
    do {
      try await Task.sleep(for: .milliseconds(180))
      originResults = try await runtime.searchSolarSystems(matching: accepted)
      originSearchError = nil
    } catch is CancellationError {
      return
    } catch {
      originResults = []
      originSearchError = "Solar-system search is currently unavailable."
    }
  }

  private func adoptProfileOriginIfNeeded() {
    guard !didAdoptProfileOrigin else { return }
    didAdoptProfileOrigin = true
    guard let configured = runtime.productionBasis.defaultManufacturingSystem,
      configured.solarSystemID > 0
    else { return }
    selectedOrigin = SolarSystemOption(
      id: configured.solarSystemID,
      name: configured.solarSystemName,
      source: SourceIdentity(provider: "Profile", version: "local")
    )
  }

  private func refresh() {
    guard let selectedItem else { return }
    let selectedOrigin = selectedOrigin
    Task {
      await runtime.refreshMarketBrowser(
        typeID: selectedItem.id,
        itemName: selectedItem.name,
        originSystemID: selectedOrigin?.id,
        originSystemName: selectedOrigin?.name
      )
    }
  }

  private func parseDouble(_ value: String) -> Double? {
    let accepted = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    guard let parsed = Double(accepted), parsed.isFinite, parsed >= 0 else {
      return nil
    }
    return parsed
  }

  private func locationLabel(_ order: MarketBrowserOrder) -> String {
    let location =
      order.locationName
      ?? (order.isPlayerStructure
        ? "Structure \(order.locationID)" : "Station \(order.locationID)")
    let system = order.systemName ?? "System \(order.systemID)"
    return "\(location) · \(system)"
  }

  private func jumpsLabel(_ order: MarketBrowserOrder) -> String {
    switch order.routeState {
    case .reachable: order.jumps.map(String.init) ?? "Not checked"
    case .unreachable: "No route"
    case .notChecked: "Not checked"
    }
  }

  private func relativeExpiry(_ date: Date) -> String {
    if date <= .now { return "Expired" }
    return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
  }

  private func formatPrice(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Unavailable" }
    return value.formatted(
      .number.precision(.fractionLength(value < 100 ? 2 : 0))
    ) + " ISK"
  }

  private func formatPrice(_ value: Double) -> String {
    formatPrice(Optional(value))
  }

  private func formatQuantity(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic))
  }

  private func sourceStateLabel(_ state: DataFreshness) -> String {
    switch state {
    case .fresh: "Fresh"
    case .partial: "Partial"
    case .stale: "Stale"
    case .forbidden: "Forbidden"
    case .unavailable: "Unavailable"
    }
  }
}

private enum MarketBrowserSort: Sendable {
  case priceAscending
  case priceDescending
  case quantityDescending
  case regionAscending
  case locationAscending
  case jumpsAscending
  case expiresAscending
  case modifiedDescending

  var isAscending: Bool {
    switch self {
    case .priceAscending, .regionAscending, .locationAscending,
      .jumpsAscending, .expiresAscending:
      true
    case .priceDescending, .quantityDescending, .modifiedDescending:
      false
    }
  }
}
