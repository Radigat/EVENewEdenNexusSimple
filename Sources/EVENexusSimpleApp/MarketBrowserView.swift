import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

struct MarketBrowserView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Query private var characters: [StoredCharacter]

  @State private var itemQuery = ""
  @State private var itemResults: [ItemTypeSearchResult] = []
  @State private var selectedItem: ItemTypeSearchResult?
  @State private var itemSearchError: String?
  @State private var showsFilters = true
  @State private var filter = MarketBrowserFilter()
  @State private var minimumPriceText = ""
  @State private var maximumPriceText = ""
  @State private var minimumQuantityText = ""
  @State private var sellerSort = AppTableSortDescriptor(
    column: MarketOrderSortColumn.price,
    direction: .ascending
  )
  @State private var buyerSort = AppTableSortDescriptor(
    column: MarketOrderSortColumn.price,
    direction: .descending
  )

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
    .task(id: itemQuery) {
      await updateItemResults()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Market Browser")
          .font(.largeTitle.bold())
          .foregroundStyle(DesignTokens.textPrimary)
        Text(
          "Compare public sell and buy orders across New Eden without turning unavailable regions or locations into zero values."
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
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        searchColumn(
          title: "Item",
          placeholder: "Search item name (3+ characters)",
          query: $itemQuery,
          error: itemSearchError,
          showsResults: itemResultsPresented
        ) {
          itemResultList
        } selection: {
          if let selectedItem {
            selectionBadge(
              title: selectedItem.name,
              typeID: selectedItem.id,
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
        if let selectedItem {
          automaticMainHubPreview(for: selectedItem)
        }
      }
    }
    .frame(maxWidth: 520, alignment: .leading)
  }

  private func automaticMainHubPreview(
    for item: ItemTypeSearchResult
  ) -> some View {
    let prices = runtime.mainHubMarketState?.value?.pricesByType[item.id]
    return HStack(spacing: DesignTokens.spacingSM) {
      Image(systemName: "building.columns.fill")
        .foregroundStyle(
          runtime.mainHubMarketState?.state == .fresh
            ? DesignTokens.positive : DesignTokens.caution
        )
      VStack(alignment: .leading, spacing: 2) {
        Text("Automatic Main Hub snapshot")
          .font(.caption.weight(.semibold))
        Text(
          runtime.productionBasis.mainTradingLocation?.location.name
            ?? AppLocalization.text("Main Hub not configured")
        )
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
        .lineLimit(1)
      }
      Spacer()
      if runtime.mainHubMarketState?.value != nil {
        VStack(alignment: .trailing, spacing: 2) {
          Text(
            AppLocalization.format(
              "Sell %@ · Buy %@",
              formatPrice(prices?.bestSellPrice),
              formatPrice(prices?.bestBuyPrice)
            )
          )
          .font(.caption.monospacedDigit())
          Text(
            runtime.mainHubMarketState?.source.capturedAt.formatted(
              date: .omitted,
              time: .shortened
            ) ?? "—"
          )
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      } else {
        Text("Waiting for automatic update")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    .accessibilityElement(children: .combine)
  }

  private func searchColumn<Results: View, Selection: View>(
    title: LocalizedStringKey,
    placeholder: LocalizedStringKey,
    query: Binding<String>,
    error: String?,
    showsResults: Binding<Bool>,
    @ViewBuilder results: @escaping () -> Results,
    @ViewBuilder selection: () -> Selection
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text(title).font(.subheadline.bold())
      TextField(placeholder, text: query)
        .textFieldStyle(.roundedBorder)
        .popover(isPresented: showsResults, arrowEdge: .bottom) {
          results()
            .frame(width: 360)
            .padding(DesignTokens.spacingSM)
        }
      selection()
      if let error {
        Text(error.localizedUI)
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
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
              HStack(spacing: DesignTokens.spacingXS) {
                EVEItemIcon(typeID: item.id)
                Text(verbatim: item.name)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
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
    typeID: Int64,
    clearLabel: LocalizedStringKey,
    clear: @escaping () -> Void
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      EVEItemText(value: title, typeID: typeID)
      Spacer()
      Button(clearLabel, action: clear)
        .buttonStyle(.borderless)
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.accentSoft)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private var itemResultsPresented: Binding<Bool> {
    Binding(
      get: { !itemResults.isEmpty },
      set: { if !$0 { itemResults = [] } }
    )
  }

  private var filterPanel: some View {
    Panel(title: "Order filters") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 160),
              spacing: DesignTokens.spacingMD,
              alignment: .leading
            )
          ],
          spacing: DesignTokens.spacingSM
        ) {
          TextField("Region contains", text: $filter.regionQuery)
          TextField("Location or system contains", text: $filter.locationQuery)
          TextField("Minimum price", text: $minimumPriceText)
          TextField("Maximum price", text: $maximumPriceText)
          TextField("Minimum quantity", text: $minimumQuantityText)
        }
        .textFieldStyle(.roundedBorder)
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 130),
              spacing: DesignTokens.spacingMD,
              alignment: .leading
            )
          ],
          spacing: DesignTokens.spacingSM
        ) {
          Text("Security")
            .font(.caption.bold())
            .foregroundStyle(DesignTokens.textSecondary)
          Toggle("Highsec", isOn: $filter.includesHighSecurity)
          Toggle("Lowsec", isOn: $filter.includesLowSecurity)
          Toggle("Nullsec", isOn: $filter.includesNullSecurity)
          Toggle("Security unknown", isOn: $filter.includesUnknownSecurity)
        }
        .toggleStyle(.checkbox)
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 150),
              spacing: DesignTokens.spacingMD,
              alignment: .leading
            )
          ],
          spacing: DesignTokens.spacingSM
        ) {
          Toggle("NPC stations", isOn: $filter.includesNPCStations)
          Toggle("Player structures", isOn: $filter.includesPlayerStructures)
          Toggle("Market hubs only", isOn: $filter.marketHubsOnly)
          Button("Reset filters") {
            filter = MarketBrowserFilter()
            minimumPriceText = ""
            maximumPriceText = ""
            minimumQuantityText = ""
          }
          .buttonStyle(.borderless)
        }
        .toggleStyle(.checkbox)
        Text(
          "Player-structure docking rights are not published with public market orders. A visible order therefore does not prove that your character can dock there."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.horizontal, DesignTokens.spacingSM)
        .foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private func summary(_ snapshot: MarketBrowserSnapshot) -> some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(minimum: 180),
          spacing: DesignTokens.spacingSM
        )
      ],
      alignment: .leading,
      spacing: DesignTokens.spacingSM
    ) {
      metric("Best sell", value: formatPrice(snapshot.summary.bestSellPrice))
      metric("Best buy", value: formatPrice(snapshot.summary.bestBuyPrice))
      metric(
        "Average sell (5%)",
        value: formatPrice(snapshot.summary.averageSellFivePercent)
      )
      metric(
        "Average buy (5%)",
        value: formatPrice(snapshot.summary.averageBuyFivePercent)
      )
      metric(
        "Sell volume",
        value: formatQuantity(snapshot.summary.activeSellVolume)
      )
      metric(
        "Buy volume",
        value: formatQuantity(snapshot.summary.activeBuyVolume)
      )
      metric("Average margin", value: formatMargin(snapshot.summary))
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
        .help(value)
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
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
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
          AppLocalization.format(
            "Updated %@",
            snapshot.capturedAt.formatted(
              date: .abbreviated,
              time: .shortened
            )
          )
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      if let structureMessage = structureResolutionMessage(sourced.diagnostics) {
        Label(structureMessage, systemImage: "lock.trianglebadge.exclamationmark")
          .foregroundStyle(DesignTokens.caution)
      }
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
    sort: Binding<AppTableSortDescriptor<MarketOrderSortColumn>>
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        Text(title).font(.title3.bold())
        Text(verbatim: "\(orders.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
      }
      GeometryReader { geometry in
        let minimumWidth: CGFloat = side == .sell ? 1_010 : 1_200
        let tableWidth = max(minimumWidth, geometry.size.width)
        let locationWidth = 300 + max(0, tableWidth - minimumWidth)

        ScrollView(.horizontal) {
          VStack(spacing: 0) {
            orderHeader(
              side: side,
              sort: sort,
              locationWidth: locationWidth,
              tableWidth: tableWidth
            )
            Divider()
            ScrollView(.vertical) {
              LazyVStack(spacing: 0) {
                ForEach(orders) { order in
                  orderRow(
                    order,
                    side: side,
                    locationWidth: locationWidth,
                    tableWidth: tableWidth
                  )
                  Divider()
                }
              }
            }
          }
          .frame(width: tableWidth, alignment: .leading)
        }
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
    sort: Binding<AppTableSortDescriptor<MarketOrderSortColumn>>,
    locationWidth: CGFloat,
    tableWidth: CGFloat
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      sortHeader("Region", width: 130, column: .region, binding: sort)
      sortHeader(
        "Quantity",
        width: 100,
        column: .quantity,
        defaultDirection: .descending,
        binding: sort
      )
      sortHeader(
        "Price",
        width: 120,
        column: .price,
        defaultDirection: side == .sell ? .ascending : .descending,
        binding: sort
      )
      sortHeader(
        "Location",
        width: locationWidth,
        column: .location,
        binding: sort
      )
      if side == .buy {
        sortHeader("Range", width: 90, column: .range, binding: sort)
        sortHeader(
          "Min volume",
          width: 92,
          column: .minimumVolume,
          defaultDirection: .descending,
          binding: sort
        )
      }
      sortHeader("Expires in", width: 108, column: .expires, binding: sort)
      sortHeader(
        "ESI updated",
        width: 140,
        column: .modified,
        defaultDirection: .descending,
        binding: sort
      )
    }
    .font(.caption.bold())
    .textCase(.uppercase)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingSM)
    .frame(width: tableWidth, alignment: .leading)
    .background(DesignTokens.elevated)
  }

  private func sortHeader(
    _ title: LocalizedStringKey,
    width: CGFloat,
    column: MarketOrderSortColumn,
    defaultDirection: AppTableSortDirection = .ascending,
    binding: Binding<AppTableSortDescriptor<MarketOrderSortColumn>>
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: binding,
      defaultDirection: defaultDirection
    )
    .frame(width: width, alignment: .leading)
  }

  private func orderRow(
    _ order: MarketBrowserOrder,
    side: MarketOrderSide,
    locationWidth: CGFloat,
    tableWidth: CGFloat
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      entityOrderCell(order.regionName, width: 130)
      orderCell(formatQuantity(order.volumeRemaining), width: 100, numeric: true)
      orderCell(formatPrice(order.price), width: 120, numeric: true)
      locationCell(order, width: locationWidth)
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
    .frame(width: tableWidth, alignment: .leading)
    .background(DesignTokens.panel)
  }

  private func orderCell(
    _ value: String,
    width: CGFloat,
    numeric: Bool = false
  ) -> some View {
    Text(verbatim: value)
      .font(numeric ? .caption.monospacedDigit() : .caption)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(width: width, alignment: .leading)
      .help(value)
  }

  private func entityOrderCell(_ value: String, width: CGFloat) -> some View {
    EVEEntityText(value: value, lineLimit: 1)
      .truncationMode(.tail)
      .frame(width: width, alignment: .leading)
      .help(value)
  }

  private func locationCell(
    _ order: MarketBrowserOrder,
    width: CGFloat
  ) -> some View {
    HStack(spacing: 4) {
      if let securityStatus = order.eveDisplaySecurityStatus {
        Text(
          verbatim: securityStatus.formatted(
            .number.precision(.fractionLength(1))
          )
        )
        .fontWeight(.semibold)
        .foregroundStyle(eveSecurityColor(securityStatus))
      }
      EVEEntityText(value: locationName(order), lineLimit: 1)
    }
    .lineLimit(1)
    .truncationMode(.tail)
    .frame(width: width, alignment: .leading)
    .help(locationLabel(order))
    .accessibilityElement(children: .contain)
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
      let ordered: Bool?
      switch sort.column {
      case .price:
        ordered = compare(lhs.price, rhs.price, direction: sort.direction)
      case .quantity:
        ordered = compare(
          lhs.volumeRemaining,
          rhs.volumeRemaining,
          direction: sort.direction
        )
      case .region:
        ordered = compare(lhs.regionName, rhs.regionName, direction: sort.direction)
      case .location:
        ordered = compare(
          locationName(lhs),
          locationName(rhs),
          direction: sort.direction
        )
      case .range:
        ordered = compare(lhs.range, rhs.range, direction: sort.direction)
      case .minimumVolume:
        ordered = compare(
          lhs.minimumVolume,
          rhs.minimumVolume,
          direction: sort.direction
        )
      case .expires:
        ordered = compare(lhs.expiresAt, rhs.expiresAt, direction: sort.direction)
      case .modified:
        ordered = compare(
          lhs.esiLastModifiedAt ?? lhs.observedAt,
          rhs.esiLastModifiedAt ?? rhs.observedAt,
          direction: sort.direction
        )
      }
      return ordered ?? (lhs.id < rhs.id)
    }
  }

  private func compare<Value: Comparable>(
    _ lhs: Value,
    _ rhs: Value,
    direction: AppTableSortDirection
  ) -> Bool? {
    guard lhs != rhs else { return nil }
    return direction.orders(lhs, before: rhs)
  }

  private var effectiveFilter: MarketBrowserFilter {
    var accepted = filter
    accepted.minimumPrice = parseDouble(minimumPriceText)
    accepted.maximumPrice = parseDouble(maximumPriceText)
    accepted.minimumQuantity = Int64(minimumQuantityText)
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

  private func refresh() {
    guard let selectedItem else { return }
    Task {
      await runtime.refreshMarketBrowser(
        typeID: selectedItem.id,
        itemName: selectedItem.name,
        authorizations: authorizationSnapshots,
        clientID: clientID
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
    let security = order.eveDisplaySecurityStatus.map {
      $0.formatted(.number.precision(.fractionLength(1)))
    }
    return [security, locationName(order)]
      .compactMap { $0 }
      .joined(separator: " ")
  }

  private func locationName(_ order: MarketBrowserOrder) -> String {
    order.locationName
      ?? (order.isPlayerStructure
        ? "Structure name unavailable to connected characters".localizedUI
        : "Station name unavailable".localizedUI)
  }

  private func eveSecurityColor(_ securityStatus: Double) -> Color {
    switch securityStatus {
    case 1...: Color(red: 44 / 255, green: 117 / 255, blue: 225 / 255)
    case 0.9...: Color(red: 57 / 255, green: 154 / 255, blue: 235 / 255)
    case 0.8...: Color(red: 78 / 255, green: 206 / 255, blue: 248 / 255)
    case 0.7...: Color(red: 96 / 255, green: 219 / 255, blue: 163 / 255)
    case 0.6...: Color(red: 113 / 255, green: 231 / 255, blue: 84 / 255)
    case 0.5...: Color(red: 245 / 255, green: 255 / 255, blue: 131 / 255)
    case 0.4...: Color(red: 220 / 255, green: 108 / 255, blue: 6 / 255)
    case 0.3...: Color(red: 206 / 255, green: 68 / 255, blue: 15 / 255)
    case 0.2...: Color(red: 187 / 255, green: 17 / 255, blue: 22 / 255)
    case 0.1...: Color(red: 115 / 255, green: 31 / 255, blue: 31 / 255)
    default: Color(red: 141 / 255, green: 49 / 255, blue: 99 / 255)
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

  private func formatMargin(_ summary: MarketBrowserSummary) -> String {
    guard let margin = summary.averageMargin,
      let percentage = summary.averageMarginPercent
    else { return "Unavailable" }
    let amount = formatPrice(margin)
    let percent = percentage.formatted(
      .number.precision(.fractionLength(1))
    )
    return "\(amount) · \(percent)%"
  }

  private func structureResolutionMessage(
    _ diagnostics: [String]
  ) -> LocalizedStringKey? {
    if diagnostics.contains(where: {
      $0.hasPrefix("esi.market-browser.structure-authorization-required")
    }) {
      return "Connect or reauthorize a character to resolve player structure names."
    }
    if diagnostics.contains(where: {
      $0.hasPrefix("esi.market-browser.structure-name-unavailable")
    }) {
      return "Some player structure names are not accessible to the connected characters."
    }
    return nil
  }

  private var clientID: String {
    EVEConstants.ssoClientID
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    characters.compactMap {
      try? JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: $0.authorizationSnapshot
      )
    }
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

struct ManufacturingOpportunitiesView: View {
  let onBuildInPlanner: (PlannerLaunchRequest) -> Void
  /// `main` keeps the historical Main-Hub workspace; `home` shows the
  /// Home-Hub scan with its own persisted filters (HUB_CHANCEN_PLAN P5).
  let hubRole: OpportunityHubRole
  var onOpenMarketSettings: () -> Void = {}
  var onOpenMainHubOpportunities: () -> Void = {}
  var onOpenHomeHubOpportunities: () -> Void = {}

  @EnvironmentObject private var runtime: RuntimeState
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]
  @Query(filter: #Predicate<StoredPlan> { $0.isActive })
  private var activePlans: [StoredPlan]

  @AppStorage(
    "market-opportunities.minimum-average-daily-demand",
    store: AppDefaults.store
  )
  private var minimumAverageDailyDemand = 0
  @AppStorage(
    "market-opportunities.analysis-basis-expanded",
    store: AppDefaults.store
  )
  private var analysisBasisExpanded = true
  @AppStorage(
    "market-opportunities.favorite-type-ids",
    store: AppDefaults.store
  )
  private var encodedFavoriteIDs = "[]"
  @AppStorage(
    "market-opportunities.filter.product-families",
    store: AppDefaults.store
  )
  private var encodedProductFamilies = ""
  @AppStorage(
    "market-opportunities.filter.production-classes",
    store: AppDefaults.store
  )
  private var encodedProductionClasses = ""
  @State private var selectedProductFamilies = Set(
    ManufacturingOpportunityProductFamily.allCases
  )
  @State private var selectedProductionClasses = Set(
    ManufacturingOpportunityProductionClass.allCases
  )
  @AppStorage(
    "asset.inventory.include-corporation-hangars",
    store: AppDefaults.store
  )
  private var includeCorporationHangars = false
  @AppStorage(
    "market-opportunities.cost.blueprint.enabled",
    store: AppDefaults.store
  )
  private var costIncludesBlueprint = false
  @AppStorage(
    "market-opportunities.cost.blueprint-per-run",
    store: AppDefaults.store
  )
  private var blueprintCostPerRunText = ""
  @AppStorage(
    "manufacturing-opportunity.maximum-material-purchase-isk",
    store: AppDefaults.store
  )
  private var maximumMaterialPurchaseISKText = ""
  @AppStorage(
    "market-opportunities.filter.expanded",
    store: AppDefaults.store
  )
  private var filterDeckExpanded = true
  @State private var lowerTab = OpportunityLowerTab.shopping
  @AppStorage(
    "market-opportunities.filter.search-text",
    store: AppDefaults.store
  )
  private var searchText = ""
  @AppStorage(
    "market-opportunities.filter.category",
    store: AppDefaults.store
  )
  private var selectedCategory = ""
  @AppStorage(
    "market-opportunities.filter.group",
    store: AppDefaults.store
  )
  private var selectedGroup = ""
  @AppStorage(
    "market-opportunities.filter.favorites-only",
    store: AppDefaults.store
  )
  private var favoritesOnly = false
  @AppStorage(
    "market-opportunities.filter.value",
    store: AppDefaults.store
  )
  private var valueFilter = ManufacturingOpportunityValueFilter.all
  @State private var tableSort: ManufacturingOpportunitySortDescriptor?
  @State private var selectedTypeID: Int64?
  @State private var analysisTask: Task<Void, Never>?
  @State private var preparedWarehouse = PreparedAssetWarehouse.empty
  @State private var preparedWarehouseIdentity: String?
  @State private var isPreparingWarehouse = false
  @State private var preparedPlanReservations = PreparedPlanReservations.empty
  @State private var preparedPlanReservationRevision = UUID()
  @State private var preparedCandidateProjection: PreparedManufacturingOpportunityCandidates?
  @State private var requestedRunsByTypeID: [Int64: Int] = [:]
  @State private var requestedRunTextsByTypeID: [Int64: String] = [:]
  @State private var requestedMEByTypeID: [Int64: Int] = [:]
  @State private var requestedMETextsByTypeID: [Int64: String] = [:]
  @State private var requestedTEByTypeID: [Int64: Int] = [:]
  @State private var requestedTETextsByTypeID: [Int64: String] = [:]
  @State private var shoppingCopyStatus: String?
  @State private var expandedOpportunityTypeID: Int64?
  @State private var productionTree: ManufacturingProductionTreeSnapshot?
  @State private var productionTreeError: String?
  @State private var isLoadingProductionTree = false
  @State private var productionTreeTask: Task<Void, Never>?
  @State private var productionTreeRunSyncTask: Task<Void, Never>?
  @State private var expandedProductionNodeIDs = Set<UUID>()
  @State private var treeProcurementPreferences: [Int64: MaterialProcurementPreference] = [:]
  @State private var treeBlueprintActions: [Int64: ProductionTreeBlueprintAction] = [:]
  @State private var treePreferredBlueprintSources: [Int64: [BlueprintSourceReference]] = [:]
  @State private var treeBlueprintCostTexts: [Int64: String] = [:]

  init(
    hubRole: OpportunityHubRole = .main,
    onOpenMarketSettings: @escaping () -> Void = {},
    onOpenMainHubOpportunities: @escaping () -> Void = {},
    onOpenHomeHubOpportunities: @escaping () -> Void = {},
    onBuildInPlanner: @escaping (PlannerLaunchRequest) -> Void
  ) {
    self.hubRole = hubRole
    self.onOpenMarketSettings = onOpenMarketSettings
    self.onOpenMainHubOpportunities = onOpenMainHubOpportunities
    self.onOpenHomeHubOpportunities = onOpenHomeHubOpportunities
    self.onBuildInPlanner = onBuildInPlanner
    guard hubRole != .main else { return }
    // Filters are persisted per hub. Favorites, Blueprint cost and the
    // Corporation-hangar switch stay shared because they describe items.
    let store = AppDefaults.store
    func key(_ mainKey: String) -> String { hubRole.storageKey(mainKey) }
    _minimumAverageDailyDemand = AppStorage(
      wrappedValue: 0,
      key("market-opportunities.minimum-average-daily-demand"),
      store: store
    )
    _analysisBasisExpanded = AppStorage(
      wrappedValue: true,
      key("market-opportunities.analysis-basis-expanded"),
      store: store
    )
    _encodedProductFamilies = AppStorage(
      wrappedValue: "",
      key("market-opportunities.filter.product-families"),
      store: store
    )
    _encodedProductionClasses = AppStorage(
      wrappedValue: "",
      key("market-opportunities.filter.production-classes"),
      store: store
    )
    _maximumMaterialPurchaseISKText = AppStorage(
      wrappedValue: "",
      key("manufacturing-opportunity.maximum-material-purchase-isk"),
      store: store
    )
    _filterDeckExpanded = AppStorage(
      wrappedValue: true,
      key("market-opportunities.filter.expanded"),
      store: store
    )
    _searchText = AppStorage(
      wrappedValue: "",
      key("market-opportunities.filter.search-text"),
      store: store
    )
    _selectedCategory = AppStorage(
      wrappedValue: "",
      key("market-opportunities.filter.category"),
      store: store
    )
    _selectedGroup = AppStorage(
      wrappedValue: "",
      key("market-opportunities.filter.group"),
      store: store
    )
    _favoritesOnly = AppStorage(
      wrappedValue: false,
      key("market-opportunities.filter.favorites-only"),
      store: store
    )
    _valueFilter = AppStorage(
      wrappedValue: ManufacturingOpportunityValueFilter.all,
      key("market-opportunities.filter.value"),
      store: store
    )
  }

  // MARK: Role-dependent runtime state

  private var analysis: ManufacturingOpportunitySnapshot? {
    hubRole == .main
      ? runtime.manufacturingOpportunityAnalysis
      : runtime.opportunityState(for: hubRole).analysis
  }

  private var opportunityDemand: ManufacturingOpportunityDemandSnapshot? {
    hubRole == .main
      ? runtime.manufacturingOpportunityDemand
      : runtime.opportunityState(for: hubRole).demand
  }

  /// Home and Coalition scans depend on the Main-Hub scan, so both errors apply.
  private var opportunityError: String? {
    hubRole == .main
      ? runtime.manufacturingOpportunityError
      : runtime.opportunityState(for: hubRole).error
        ?? runtime.manufacturingOpportunityError
  }

  private var opportunitySnapshotError: String? {
    hubRole == .main ? runtime.manufacturingOpportunitySnapshotError : nil
  }

  private var opportunityDemandError: String? {
    hubRole == .main ? runtime.manufacturingOpportunityDemandError : nil
  }

  private var scanProgressValue: ManufacturingOpportunityScanProgress {
    let state = runtime.opportunityState(for: hubRole)
    return hubRole != .main && state.isAnalyzing
      ? state.progress
      : runtime.manufacturingOpportunityProgress
  }

  private var contractContext: ManufacturingOpportunityContractContext {
    ManufacturingOpportunityContractContext(
      references: runtime.opportunityContractReferences,
      contractFeeRate: runtime.publicContractFeeRate(for: hubRole)
    )
  }

  /// Localizes a Main-Hub text and names the shown hub instead.
  private func hubText(_ key: String) -> String {
    OpportunityHubText.adapt(AppLocalization.text(key), for: hubRole)
  }

  /// Sale-side warnings name the shown hub; material warnings keep "Main Hub"
  /// because materials are always bought there.
  private func presentedWarning(_ warning: DomainWarning) -> String {
    OpportunityHubText.saleWarningCodes.contains(warning.code)
      ? hubText(warning.message) : AppLocalization.text(warning.message)
  }

  var body: some View {
    if let unavailable = homeHubUnavailableState {
      unavailable
    } else {
      workspaceBody
    }
  }

  /// Hub missing, equal to another hub or incomplete: explain instead of
  /// scanning.
  private var homeHubUnavailableState: AnyView? {
    guard hubRole != .main else { return nil }
    let coalition = hubRole == .coalition
    switch runtime.opportunityScanTarget(for: hubRole) {
    case .notConfigured:
      return AnyView(
        ContentUnavailableView {
          Label(
            coalition ? "No Coalition Hub configured" : "No Home Hub configured",
            systemImage: coalition ? "flag" : "house"
          )
        } description: {
          Text(
            coalition
              ? "Select a Coalition Hub under Data & Settings → Market Settings. Its opportunities are scanned together with the Main Hub."
              : "Select a Home Hub under Data & Settings → Market Settings. Its opportunities are scanned together with the Main Hub."
          )
        } actions: {
          Button("Open Market Settings") { onOpenMarketSettings() }
        }
      )
    case .sharesMainHub:
      return AnyView(
        ContentUnavailableView {
          Label(
            coalition
              ? "Coalition Hub equals the Main Hub" : "Home Hub equals the Main Hub",
            systemImage: coalition ? "flag" : "house"
          )
        } description: {
          Text(
            coalition
              ? "No separate Coalition Hub scan runs. Use Main Hub Opportunities for this location."
              : "No separate Home Hub scan runs. Use Main Hub Opportunities for this location."
          )
        } actions: {
          Button("Open Main Hub Opportunities") { onOpenMainHubOpportunities() }
        }
      )
    case .sharesHomeHub:
      return AnyView(
        ContentUnavailableView {
          Label("Coalition Hub equals the Home Hub", systemImage: "flag")
        } description: {
          Text(
            "No separate Coalition Hub scan runs. Use Home Hub Opportunities for this location."
          )
        } actions: {
          Button("Open Home Hub Opportunities") { onOpenHomeHubOpportunities() }
        }
      )
    case .unresolved:
      return AnyView(
        ContentUnavailableView {
          Label(
            coalition
              ? "Coalition Hub location incomplete" : "Home Hub location incomplete",
            systemImage: coalition ? "flag" : "house"
          )
        } description: {
          Text(
            coalition
              ? "The Coalition Hub has no exact station, structure or solar-system identifier. Select it again in Market Settings."
              : "The Home Hub has no exact station, structure or solar-system identifier. Select it again in Market Settings."
          )
        } actions: {
          Button("Open Market Settings") { onOpenMarketSettings() }
        }
      )
    case .npcStation, .playerStructure:
      return nil
    }
  }

  /// Shown while a configured Home or Coalition Hub has no saved scan yet.
  private var homeHubPendingScanText: String {
    let coalition = hubRole == .coalition
    if let next = runtime.mainHubMarketNextAutomaticRunAt {
      return AppLocalization.format(
        coalition
          ? "The Coalition Hub is scanned together with the next Main Hub scan at %@. Update starts all scans now."
          : "The Home Hub is scanned together with the next Main Hub scan at %@. Update starts both now.",
        next.formatted(date: .omitted, time: .shortened)
      )
    }
    return AppLocalization.text(
      coalition
        ? "The Coalition Hub is scanned together with the Main Hub. Update starts all scans now."
        : "The Home Hub is scanned together with the Main Hub. Update starts both now."
    )
  }

  @ViewBuilder
  private var workspaceBody: some View {
    let planPayloads = activePlanSnapshotPayloads
    let planReservationsAreCurrent =
      preparedPlanReservations.source == planPayloads
    let candidateTrigger = candidateProjectionTrigger
    let allPreparedCandidates =
      preparedCandidateProjection?.trigger == candidateTrigger
      ? preparedCandidateProjection?.candidates : nil
    let preparedCandidates = allPreparedCandidates.map { candidates in
      candidates
        .map(candidateApplyingRequestedParameters)
        .filter { candidate in
          valueFilter.accepts(candidate.costs)
            && ManufacturingOpportunityBudgetFilter.accepts(
              maximumMaterialPurchaseISK: parsedMaximumMaterialPurchaseISK,
              purchaseCashRequirement: candidate.purchaseCashRequirement
            )
            && ManufacturingOpportunityAverageDemandFilter.accepts(
              minimumAverageDailyDemand: Int64(minimumAverageDailyDemand),
              averageDailyDemand: candidate.row.averageDailyDemand
            )
        }
    }
    GeometryReader { geometry in
      let upperControlsHeight =
        ManufacturingOpportunityPageLayout.upperControlsHeight(
          viewportHeight: geometry.size.height,
          filtersAreExpanded: filterDeckExpanded,
          basisIsExpanded: analysisBasisExpanded
        )
      VStack(alignment: .leading, spacing: 0) {
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            header
            filterDeck
            if let error = opportunityError {
              Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(DesignTokens.negative)
            }
            if runtime.isAnalyzingManufacturingOpportunities { scanProgress }
            if let snapshot = analysis {
              basis(snapshot)
            }
            if let snapshotError = opportunitySnapshotError {
              Label(
                snapshotError.localizedUI,
                systemImage: "externaldrive.badge.exclamationmark"
              )
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
            }
            if planReservationsAreCurrent,
              preparedPlanReservations.invalidSnapshotCount > 0
            {
              Label(
                "One or more active production plans could not be read. Their Warehouse reservations remain unavailable.",
                systemImage: "externaldrive.badge.exclamationmark"
              )
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
            }
          }
        }
        .frame(height: upperControlsHeight)

        if planReservationsAreCurrent {
          calculatorWorkspace(
            analysis,
            candidates: preparedCandidates
          )
        } else {
          ProgressView("Preparing active plan reservations…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .padding(DesignTokens.spacingMD)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: warehouseIdentity) {
      await prepareWarehouse(identity: warehouseIdentity)
    }
    .task(id: planPayloads) {
      let prepared = await StoredPlanReservationProjection.prepare(
        payloads: planPayloads
      )
      guard !Task.isCancelled else { return }
      preparedPlanReservations = prepared
      preparedPlanReservationRevision = UUID()
    }
    .task(id: candidateTrigger) {
      await prepareCandidates(trigger: candidateTrigger)
    }
    .task(id: analysis?.id) {
      guard let analysis else { return }
      await runtime.loadOpportunityContractReferences(
        typeIDs: Set(analysis.rows.map(\.productTypeID))
      )
    }
    .onAppear {
      restoreCatalogFilters()
      minimumAverageDailyDemand = max(0, minimumAverageDailyDemand)
      normalizeStoredISKFields()
    }
    .task {
      await runtime.loadManufacturingOpportunityAnalysis()
      await runtime.loadManufacturingOpportunityDemand()
      if hubRole != .main {
        await runtime.loadSecondaryHubOpportunityData(role: hubRole)
      }
      runtime.prepareMainHubMarketAutomation()
    }
    .onChange(of: analysis?.id) { _, _ in
      discardUnavailableStoredCatalogChoices()
      shoppingCopyStatus = nil
      requestedRunsByTypeID = [:]
      requestedRunTextsByTypeID = [:]
      requestedMEByTypeID = [:]
      requestedMETextsByTypeID = [:]
      requestedTEByTypeID = [:]
      requestedTETextsByTypeID = [:]
      collapseProductionTree()
    }
    .onChange(of: requestedRunsByTypeID) { _, _ in
      scheduleExpandedProductionTreeReload()
    }
    .onChange(of: requestedMEByTypeID) { _, _ in
      scheduleExpandedProductionTreeReload()
    }
    .onChange(of: requestedTEByTypeID) { _, _ in
      scheduleExpandedProductionTreeReload()
    }
    .onDisappear {
      analysisTask?.cancel()
      productionTreeTask?.cancel()
      productionTreeRunSyncTask?.cancel()
    }
  }

  private func calculatorWorkspace(
    _ snapshot: ManufacturingOpportunitySnapshot?,
    candidates: [ManufacturingOpportunityCandidate]?
  ) -> some View {
    Group {
      if let snapshot, let candidates {
        candidatePane(snapshot, candidates: candidates)
      } else if let snapshot {
        preparingCandidatePane(snapshot)
      } else {
        emptyCandidatePane
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var emptyCandidatePane: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("CALCULATOR")
          .font(.caption.bold())
          .tracking(1.1)
        Spacer()
        Text("No saved item list")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, 6)
      .background(DesignTokens.elevated)
      .overlay(alignment: .bottom) {
        Rectangle().fill(DesignTokens.accent).frame(height: 2)
      }
      ContentUnavailableView(
        hubText("No Main Hub scan yet"),
        systemImage: "chart.line.uptrend.xyaxis",
        description: Text(
          hubRole == .main
            ? AppLocalization.text(
              "Start the explicit scan to compare published manufacturing recipes against one current Main Hub order-book snapshot."
            )
            : homeHubPendingScanText
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DesignTokens.canvas)
    .overlay {
      RoundedRectangle(cornerRadius: 2).stroke(DesignTokens.border)
    }
  }

  private var header: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: 2) {
        Text(hubText("Market Opportunities · Main Hub"))
          .font(.title2.bold())
        Text(
          hubText(
            "Main Hub market · Production candidates · Ranking · Planner handoff"
          )
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
      Button {
        runtime.setMainHubMarketAutomaticUpdatesEnabled(
          !runtime.mainHubMarketAutomaticUpdatesEnabled
        )
      } label: {
        Label(
          runtime.mainHubMarketAutomaticUpdatesEnabled
            ? "Automatic updates active" : "Automatic updates paused",
          systemImage: runtime.mainHubMarketAutomaticUpdatesEnabled
            ? "clock.arrow.circlepath" : "pause.circle"
        )
      }
      .buttonStyle(.borderless)
      .font(.caption)
      .foregroundStyle(
        runtime.mainHubMarketAutomaticUpdatesEnabled
          ? DesignTokens.positive : DesignTokens.textSecondary
      )
      .help(
        runtime.mainHubMarketAutomaticUpdatesEnabled
          ? "Pause Main Hub updates" : "Resume Main Hub updates"
      )
      if runtime.isAnalyzingManufacturingOpportunities {
        Button("Stop safely", role: .cancel) { analysisTask?.cancel() }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("market-opportunities.cancel")
      } else {
        Button {
          startAnalysis()
        } label: {
          Label("Update", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("market-opportunities.scan")
      }
    }
  }

  private var filterDeck: some View {
    VStack(alignment: .leading, spacing: 0) {
      FullWidthDisclosure(isExpanded: $filterDeckExpanded) {
        HStack(spacing: DesignTokens.spacingSM) {
          Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            .font(.headline)
          Text(
            "Products, production classes, favorites, catalog, results and costs adapt to the available width."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          Spacer()
        }
        .padding(DesignTokens.spacingSM)
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          LazyVGrid(
            columns: [
              GridItem(
                .adaptive(minimum: 250, maximum: 380),
                spacing: DesignTokens.spacingSM,
                alignment: .top
              )
            ],
            alignment: .leading,
            spacing: DesignTokens.spacingSM
          ) {
            unifiedFilters
          }
          .padding(.vertical, DesignTokens.spacingSM)

          Divider()
          searchToolbar
        }
        .padding(.horizontal, DesignTokens.spacingSM)
        .padding(.bottom, DesignTokens.spacingSM)
      }
      .accessibilityIdentifier("market-opportunities.filters")
    }
    .background(DesignTokens.panel)
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border)
    }
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  @ViewBuilder
  private var unifiedFilters: some View {
    filterColumn(
      "Products",
      help:
        "Select broad product families. Multiple choices within this card are combined with OR; this card is combined with Production class, Catalog and Result by AND. Changes filter the saved scan locally and do not start ESI or SDE work. Other preserves complete recipes that cannot be classified into one listed family."
    ) {
      HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
        VStack(alignment: .leading, spacing: 3) {
          familyToggle(.ships)
          familyToggle(.modules)
          familyToggle(.charges)
          familyToggle(.drones)
          familyToggle(.rigs)
          familyToggle(.structures)
        }
        VStack(alignment: .leading, spacing: 3) {
          familyToggle(.reactions)
          familyToggle(.boosters)
          familyToggle(.implants)
          familyToggle(.components)
          familyToggle(.deployables)
          familyToggle(.other)
        }
      }
    }

    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      filterColumn(
        "Production class",
        help:
          "Uses factual SDE meta-group and tech-level metadata to limit results to Tech I, Tech II, Tech III, faction, storyline or other. Multiple choices inside this card use OR; other active filter cards use AND. Missing metadata stays Other or unclassified and is never guessed from the item name. If the warning appears, update the SDE and run the Main Hub scan again before expecting exact class filtering."
      ) {
        HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
          VStack(alignment: .leading, spacing: 3) {
            productionClassToggle(.techI)
            productionClassToggle(.techII)
            productionClassToggle(.techIII)
          }
          VStack(alignment: .leading, spacing: 3) {
            productionClassToggle(.faction)
            productionClassToggle(.storyline)
            productionClassToggle(.other)
          }
        }
        if !hasProductionClassMetadata {
          OpportunityExplanationButton(
            title: "Production-class filter is incomplete",
            explanation:
              "This saved scan does not contain the required SDE meta-group or tech-level fields for every candidate. The app keeps those rows under Other or unclassified instead of guessing from names. Update the SDE catalog and run the Main Hub analysis again to populate the factual classification.",
            systemImage: "exclamationmark.triangle",
            color: DesignTokens.caution,
            font: .caption
          )
          .frame(maxWidth: 300, alignment: .leading)
        }
      }

      filterColumn(
        "Favorites",
        help:
          "Favorites only keeps products that are marked with a star. The filter uses the saved candidate list locally and does not start a new Main Hub calculation."
      ) {
        compactToggle("Favorites only", isOn: $favoritesOnly)
        Text("Starred products remain available across local filter changes.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }

    filterColumn(
      "Catalog",
      help:
        "Select one exact SDE category and group from the saved Main Hub scan. Category and group use AND with each other and with Product, Production class and Result. Changing them is a local list filter and does not refresh market or SDE data. All categories or All groups disables only that respective restriction."
    ) {
      Picker("Category", selection: $selectedCategory) {
        Text("All categories").tag("")
        ForEach(categories, id: \.self) { Text($0).tag($0) }
      }
      .frame(maxWidth: .infinity)
      Picker("Group", selection: $selectedGroup) {
        Text("All groups").tag("")
        ForEach(groups, id: \.self) { Text($0).tag($0) }
      }
      .frame(maxWidth: .infinity)
    }

    filterColumn(
      "Result",
      help:
        "Value limits rows by their already calculated profit state. Minimum average daily demand uses the known multi-day average: zero disables the threshold and keeps unavailable averages; a positive number accepts only known averages at or above it. Sorting remains controlled by the clickable table headings and missing values stay distinct from zero."
    ) {
      Picker("Value", selection: $valueFilter) {
        ForEach(ManufacturingOpportunityValueFilter.allCases) {
          Text($0.title).tag($0)
        }
      }
      .frame(maxWidth: .infinity)
      Label("Sort via a table heading", systemImage: "arrow.up.arrow.down")
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text("Unavailable values stay after factual values in both directions.")
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      LabeledContent("Minimum average daily demand") {
        HStack(spacing: 4) {
          TextField(
            "Minimum average daily demand",
            value: minimumAverageDailyDemandBinding,
            format: groupedIntegerFormat
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 90)
          Stepper(
            "Minimum average daily demand",
            value: minimumAverageDailyDemandBinding,
            in: 0...1_000_000
          )
          .labelsHidden()
        }
      }
      .accessibilityHint(
        "Zero disables this filter. A positive value shows only rows whose known multi-day average daily demand reaches the threshold."
      )
      Text(
        (minimumAverageDailyDemand == 0
          ? "0 keeps known and unavailable averages visible."
          : "Only known averages at or above this value are shown.")
          .localizedUI
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }

    filterColumn(
      "Costs and budget",
      help:
        "Market material replacement value, installation, Profile logistics, sales tax and broker fee are applied automatically from the saved scan and Profile. Blueprint allocation is optional and affects every required manufacturing run only when enabled with a valid ISK amount; reactions have no Blueprint allocation. Maximum material purchases limits only new wallet cash for material shortfalls; Warehouse stock keeps its replacement value but does not consume this limit. Missing market, Warehouse, volume, fee or logistics data remains unavailable and is never replaced by zero."
    ) {
      Label("Automatic calculation", systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(DesignTokens.positive)
      Text(
        "Material replacement value, installation, sales tax, broker fee and Profile logistics are applied automatically."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      compactToggle("Include blueprint allocation", isOn: $costIncludesBlueprint)
      TextField(
        "ISK per run",
        text: groupedISKBinding($blueprintCostPerRunText)
      )
      .textFieldStyle(.roundedBorder)
      .disabled(!costIncludesBlueprint)
      if costIncludesBlueprint, parsedBlueprintCost == nil {
        OpportunityExplanationButton(
          title: "Enter a valid ISK amount",
          explanation:
            "Blueprint allocation is enabled, but the amount is empty or invalid. Enter the complete ISK allocation per required Blueprint run. Until then, cost, profit, ROI and ISK rates that depend on this allocation remain unavailable instead of treating the Blueprint as free.",
          systemImage: "exclamationmark.triangle",
          color: DesignTokens.caution,
          font: .caption
        )
      }
      TextField(
        "Maximum material purchases (ISK)",
        text: groupedISKBinding($maximumMaterialPurchaseISKText)
      )
      .textFieldStyle(.roundedBorder)
      .accessibilityHint(
        "Limits new wallet cash for material shortfalls; Warehouse stock keeps its replacement value but does not consume this budget."
      )
      if maximumMaterialPurchaseISKIsInvalid {
        OpportunityExplanationButton(
          title: "Enter a valid ISK amount",
          explanation:
            "The material-purchase limit must be empty or a non-negative ISK amount. It limits only new wallet cash for material shortfalls. Invalid input does not become zero and cannot silently exclude every candidate.",
          systemImage: "exclamationmark.triangle",
          color: DesignTokens.caution,
          font: .caption
        )
      } else if parsedMaximumMaterialPurchaseISK != nil {
        Text(
          "Rows with unknown purchase coverage are excluded while the budget is active."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var searchToolbar: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      TextField("Search item name (3+ characters)", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .accessibilityHint("Search starts after at least three characters.")
        .frame(minWidth: 260, idealWidth: 420, maxWidth: 540)
      Button("Clear filters") { resetFilters() }
        .buttonStyle(.bordered)
      Button("Select all") { selectAllCatalogFilters() }
        .buttonStyle(.bordered)
      Button("Uncheck all") { uncheckAllCatalogFilters() }
        .buttonStyle(.bordered)
      Spacer()
    }
  }

  private var scanProgress: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      if let fraction = scanProgressValue.fractionCompleted {
        ProgressView(value: fraction)
      } else {
        ProgressView()
      }
      HStack {
        Text(hubText("Loading the configured Main Hub order book"))
        Spacer()
        if scanProgressValue.totalPages > 0 {
          Text(
            AppLocalization.format(
              "%@ / %@ pages",
              formatInteger(
                scanProgressValue.completedPages
              ),
              formatInteger(scanProgressValue.totalPages)
            )
          )
          .monospacedDigit()
        }
      }
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func basis(_ snapshot: ManufacturingOpportunitySnapshot) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      FullWidthDisclosure(isExpanded: $analysisBasisExpanded) {
        HStack(spacing: DesignTokens.spacingSM) {
          Label("Data basis and explanations", systemImage: "info.circle")
            .font(.caption.bold())
          Spacer()
          Text(
            AppLocalization.format(
              "Updated %@",
              snapshot.marketSource.capturedAt.formatted(
                date: .abbreviated,
                time: .shortened
              )
            )
          )
          .monospacedDigit()
          .foregroundStyle(DesignTokens.textSecondary)
        }
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          HStack(spacing: DesignTokens.spacingXS) {
            Image(systemName: "building.columns")
              .foregroundStyle(DesignTokens.textSecondary)
            EVEEntityText(value: snapshot.mainHub.name, font: .caption)
            Text("→")
            Image(systemName: "hammer.fill")
              .foregroundStyle(DesignTokens.textSecondary)
            if snapshot.productionWarehouseScope.locations.count == 1,
              let location = snapshot.productionWarehouseScope.locations.first
            {
              EVEEntityText(value: location.structureName, font: .caption)
            } else {
              Text(
                verbatim: productionScopeLabel(
                  snapshot.productionWarehouseScope
                )
              )
            }
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190, maximum: 320))],
            alignment: .leading,
            spacing: DesignTokens.spacingXS
          ) {
            Label(
              AppLocalization.format(
                "Production candidates: %@",
                formatInteger(snapshot.coverage.candidateCount)
              ),
              systemImage: "shippingbox.and.arrow.backward"
            )
            Text(
              AppLocalization.format(
                "Complete manufacturing definitions: %@",
                formatInteger(
                  snapshot.coverage.completeManufacturingDefinitionCount
                )
              )
            )
            if let reactionCount =
              snapshot.coverage.completeReactionDefinitionCount
            {
              Text(
                AppLocalization.format(
                  "Complete reaction definitions: %@",
                  formatInteger(reactionCount)
                )
              )
            }
            Text(
              AppLocalization.format(
                "With sell orders: %@",
                formatInteger(snapshot.coverage.candidatesWithSellOrders)
              )
            )
            Text(
              AppLocalization.format(
                "With buy orders: %@",
                formatInteger(snapshot.coverage.candidatesWithBuyOrders)
              )
            )
            Text(
              OpportunityHubText.adapt(
                AppLocalization.format(
                  "Main Hub active order types: %@",
                  formatInteger(snapshot.coverage.mainHubActiveOrderTypeCount)
                ),
                for: hubRole
              )
            )
            if let demand = snapshot.demand {
              Text(
                AppLocalization.format(
                  "Rolling demand samples: %@",
                  formatInteger(demand.sampleCount)
                )
              )
              if let history = opportunityDemand,
                history.regionID == demand.regionID,
                history.locationID == demand.locationID
              {
                Text(
                  AppLocalization.format(
                    "Demand history: %@ UTC days",
                    formatInteger(history.dailyHistory?.count ?? 0)
                  )
                )
              } else {
                Text("Demand history unavailable")
              }
            } else {
              Text(
                AppLocalization.format(
                  "Rolling demand samples: %@",
                  formatInteger(0)
                )
              )
              Text("Demand history unavailable")
            }
          }
          .monospacedDigit()
          Text(
            "A candidate is a complete published manufacturing or reaction product. Products without an active Main-Hub sell order remain visible with unavailable revenue and profitability instead of disappearing. Active orders are not completed sales."
          )
          .foregroundStyle(DesignTokens.textSecondary)
          Text(
            "Build transfers this row's complete output and Runs to the Planner. Manufacturing rows also transfer ME and TE; reactions have neither. A like-for-like Main-Hub comparison also requires the same material sources, applicable Blueprint costs and market depth: this table screens the direct published recipe with captured prices, while the Planner can recursively build intermediates and refresh deeper order-book quantities."
          )
          .foregroundStyle(DesignTokens.textSecondary)
          if let demand = snapshot.demand,
            demand.sampleCount >= 2,
            demand.comparedOrderCountByType != nil,
            demand.observationDuration
              >= ManufacturingOpportunityDemandSnapshot
              .minimumRateObservationDuration
          {
            Text(
              OpportunityHubText.adapt(
                AppLocalization.format(
                  "Daily demand is normalized from the exact Main Hub lower bound observed between %@ and %@. Each item needs a surviving comparable order and at least 30 minutes of observation.",
                  formatUTCTime(demand.firstObservedAt),
                  formatUTCTime(demand.lastObservedAt)
                ),
                for: hubRole
              )
            )
            .foregroundStyle(DesignTokens.textSecondary)
          } else {
            Text(
              hubText(
                "A second exact Main Hub scan at least 30 minutes after the baseline is required before a daily demand rate can be calculated."
              )
            )
            .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .padding(.top, DesignTokens.spacingSM)
      }
      .accessibilityIdentifier("market-opportunities.analysis-basis")

      if !snapshot.productionWarehouseScope.unresolvedActivities.isEmpty {
        Label(
          "Some production activities do not have an exact assigned asset location and are excluded from Warehouse allocation.",
          systemImage: "shippingbox.and.arrow.backward.fill"
        )
        .foregroundStyle(DesignTokens.caution)
      }
      if let demandError = opportunityDemandError {
        Label(demandError.localizedUI, systemImage: "externaldrive.badge.exclamationmark")
          .foregroundStyle(DesignTokens.caution)
      }
      ForEach(snapshot.warnings) { warning in
        Label(
          presentedWarning(warning),
          systemImage: warning.severity == .blocking
            ? "xmark.octagon.fill" : "info.circle"
        )
        .foregroundStyle(
          warning.severity == .blocking
            ? DesignTokens.negative : DesignTokens.caution
        )
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.panel)
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border)
    }
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func candidatePane(
    _ snapshot: ManufacturingOpportunitySnapshot,
    candidates: [ManufacturingOpportunityCandidate]
  ) -> some View {
    let favorites = favoriteIDs
    return VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("CALCULATOR")
          .font(.caption.bold())
          .tracking(1.1)
        Spacer()
        Text(
          verbatim:
            "\(formatInteger(candidates.count)) / \(formatInteger(snapshot.rows.count))"
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      }
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, 6)
      .background(DesignTokens.elevated)
      .overlay(alignment: .bottom) {
        Rectangle().fill(DesignTokens.accent).frame(height: 2)
      }
      GeometryReader { geometry in
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: 0) {
            opportunityHeader
            ScrollView(.vertical) {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(candidates) { candidate in
                  opportunityRow(
                    candidate.row,
                    costs: candidate.costs,
                    isFavorite: favorites.contains(candidate.row.productTypeID)
                  )
                }
              }
            }
            .defaultScrollAnchor(.top)
          }
          .frame(
            height: ManufacturingOpportunityTableLayout.clampedViewportLength(
              geometry.size.height
            ),
            alignment: .topLeading
          )
          .fixedSize(horizontal: true, vertical: false)
        }
        .defaultScrollAnchor(.leading)
        .accessibilityIdentifier("market-opportunities.table")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DesignTokens.canvas)
    .overlay {
      RoundedRectangle(cornerRadius: 2).stroke(DesignTokens.border)
    }
  }

  private func preparingCandidatePane(
    _ snapshot: ManufacturingOpportunitySnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("CALCULATOR")
          .font(.caption.bold())
          .tracking(1.1)
        Spacer()
        Text(verbatim: "— / \(formatInteger(snapshot.rows.count))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, 6)
      .background(DesignTokens.elevated)
      .overlay(alignment: .bottom) {
        Rectangle().fill(DesignTokens.accent).frame(height: 2)
      }
      ProgressView("Preparing Market opportunities…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DesignTokens.canvas)
    .overlay {
      RoundedRectangle(cornerRadius: 2).stroke(DesignTokens.border)
    }
  }

  private var opportunityHeader: some View {
    HStack(spacing: 0) {
      headerCell("", width: 32)
      sortableHeaderCell("Task", column: .task, width: 52, alignment: .leading)
      sortableHeaderCell("Item", column: .item, width: 210, alignment: .leading)
      sortableHeaderCell("Daily demand", column: .demand, width: 155)
      sortableHeaderCell("Quantity", column: .quantity, width: 70)
      sortableHeaderCell("Runs", column: .runs, width: 68)
      sortableHeaderCell("ME", column: .materialEfficiency, width: 58)
      sortableHeaderCell("TE", column: .timeEfficiency, width: 58)
      sortableHeaderCell("Duration", column: .duration, width: 80)
      sortableHeaderCell("Cost", column: .cost, width: 100)
      sortableHeaderCell("Revenue", column: .revenue, width: 100)
      sortableHeaderCell("Sales tax", column: .salesTax, width: 85)
      sortableHeaderCell("Broker fee", column: .brokerFee, width: 85)
      sortableHeaderCell("Profit", column: .profit, width: 105)
      sortableHeaderCell(
        "Daily profit potential",
        column: .dailyProfitPotential,
        width: 125
      )
      sortableHeaderCell("Contract price", column: .contractPrice, width: 115)
      sortableHeaderCell("Contract profit", column: .contractProfit, width: 120)
      sortableHeaderCell("ROI", column: .roi, width: 65)
      sortableHeaderCell("ISK / h", column: .iskPerHour, width: 95)
      sortableHeaderCell("ISK / m³", column: .iskPerCubicMeter, width: 95)
        .padding(.leading, DesignTokens.spacingSM)
      if hubRole == .coalition {
        sortableHeaderCell(
          "Home → Coalition",
          column: .onwardTransport,
          width: 120
        )
        .padding(.leading, DesignTokens.spacingSM)
      }
      sortableHeaderCell("Group", column: .group, width: 145, alignment: .leading)
        .padding(.leading, DesignTokens.spacingSM)
      sortableHeaderCell("Category", column: .category, width: 125, alignment: .leading)
    }
    .background(DesignTokens.panel)
    .overlay(alignment: .bottom) {
      Rectangle().fill(DesignTokens.border).frame(height: 1)
    }
  }

  private func opportunityRow(
    _ row: ManufacturingOpportunityRow,
    costs: ManufacturingOpportunityCostProjection,
    isFavorite: Bool
  ) -> some View {
    HStack(spacing: 0) {
      Button {
        toggleFavorite(row.productTypeID)
      } label: {
        Image(
          systemName: isFavorite ? "star.fill" : "star"
        )
        .foregroundStyle(
          isFavorite ? DesignTokens.highlight : DesignTokens.textSecondary
        )
        .frame(width: 32)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Toggle favorite")
      Button("Build") {
        onBuildInPlanner(
          MainHubOpportunityPlannerHandoff.request(
            productTypeID: row.productTypeID,
            productName: row.productName,
            requestedRuns: row.runs,
            wantedQuantity: Int(clamping: row.producedQuantity),
            materialEfficiency: row.displayedMaterialEfficiency ?? 0,
            timeEfficiency: row.displayedTimeEfficiency ?? 0,
            targetMarket: hubRole
          )
        )
      }
      .buttonStyle(.plain)
      .font(.caption.monospacedDigit())
      .frame(width: 52, alignment: .leading)
      .accessibilityLabel("Build in Planner")
      .help(
        "Transfer this row's visible quantity, Runs, ME and TE directly to Planner. Concrete Blueprint sources are selected and verified there."
      )
      EVEItemText(
        value: row.productName,
        typeID: row.productTypeID,
        font: .caption.monospacedDigit(),
        lineLimit: 1,
        accessibilityIdentifier:
          "market-opportunities.product.copy.\(row.productTypeID)"
      )
      .help(row.productName)
      .frame(width: 210, alignment: .leading)
      dailyDemandCell(row)
      textCell(formatInteger(row.producedQuantity), width: 70)
      requestedRunsCell(row)
      requestedEfficiencyCell(row, kind: .material)
      requestedEfficiencyCell(row, kind: .time)
      textCell(formatDuration(row.durationSeconds), width: 80)
      textCell(formatISK(costs.totalCost), width: 100)
      textCell(formatISK(costs.grossRevenue), width: 100)
      textCell(formatISK(costs.salesTax), width: 85)
      textCell(formatISK(costs.brokerFee), width: 85)
      textCell(
        formatSignedISK(costs.profit),
        width: 105,
        color: costs.profit.map {
          $0 >= 0 ? DesignTokens.positive : DesignTokens.negative
        } ?? DesignTokens.caution
      )
      textCell(
        formatSignedISK(
          ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
            for: row,
            costs: costs
          )
        ),
        width: 125,
        color: costs.profit.map {
          $0 >= 0 ? DesignTokens.positive : DesignTokens.negative
        } ?? DesignTokens.caution
      )
      textCell(
        contractCellText(formatISK(costs.contract?.unitPrice), costs.contract),
        width: 115,
        color: contractCellColor(costs.contract, value: nil)
      )
      textCell(
        contractCellText(
          formatSignedISK(costs.contract?.profit),
          costs.contract
        ),
        width: 120,
        color: contractCellColor(costs.contract, value: costs.contract?.profit)
      )
      textCell(formatPercent(costs.returnOnInvestment), width: 65)
      textCell(formatISK(costs.iskPerHour), width: 95)
      textCell(formatISK(costs.iskPerCubicMeter), width: 95)
        .padding(.leading, DesignTokens.spacingSM)
      if hubRole == .coalition {
        textCell(
          formatISK(costs.onwardTransportCost),
          width: 120,
          color: costs.onwardTransportCost == nil
            ? DesignTokens.caution : DesignTokens.textPrimary
        )
        .padding(.leading, DesignTokens.spacingSM)
      }
      textCell(row.groupName, width: 145, alignment: .leading)
        .padding(.leading, DesignTokens.spacingSM)
      textCell(row.categoryName, width: 125, alignment: .leading)
    }
    .padding(.vertical, 5)
    .overlay(alignment: .bottom) { Divider() }
    .accessibilityElement(children: .contain)
  }

  private func headerCell(
    _ title: LocalizedStringKey,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Text(title)
      .font(.caption.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      .frame(width: width, alignment: alignment)
      .padding(.vertical, 6)
  }

  private func sortableHeaderCell(
    _ title: LocalizedStringKey,
    column: ManufacturingOpportunitySortColumn,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Button {
      if tableSort?.column == column {
        tableSort = ManufacturingOpportunitySortDescriptor(
          column: column,
          direction: tableSort?.direction.toggled ?? .ascending
        )
      } else {
        tableSort = ManufacturingOpportunitySortDescriptor(
          column: column,
          direction: .ascending
        )
      }
    } label: {
      HStack(spacing: 3) {
        Text(title)
          .lineLimit(1)
        if tableSort?.column == column {
          Image(
            systemName: tableSort?.direction == .ascending
              ? "chevron.up" : "chevron.down"
          )
          .font(.caption2)
        }
      }
      .font(.caption.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      .frame(width: width, alignment: alignment)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(Text(sortableColumnHelpText(column)))
    .accessibilityLabel(title)
    .accessibilityValue(
      tableSort?.column == column
        ? (tableSort?.direction == .ascending ? "Ascending" : "Descending")
        : "Not sorted"
    )
  }

  private func sortableColumnHelpText(
    _ column: ManufacturingOpportunitySortColumn
  ) -> String {
    if column == .contractPrice {
      return AppLocalization.text(
        "Contract price: lowest unit price of a comparable public Item Exchange contract in the local index for exactly this product, one offered line, no requested line and a positive price; bundles are excluded. The search covers the whole imported universe, as in the Planner. ≈ marks a provisional value while the index is incomplete. No offer stays unavailable. Click to sort."
      )
    }
    if column == .contractProfit {
      return AppLocalization.text(
        "Contract profit: contract price × produced units, minus the confirmed public-contract fee rate of this hub and the total cost. Market sales tax and broker fee do not apply. Without a confirmed rate the value is shown before the contract fee. Click to sort."
      )
    }
    if column == .onwardTransport {
      return AppLocalization.text(
        "Home → Coalition: onward transport of the complete output from the Home Hub to the Coalition Hub, by Jump Freighter when jump logistics is enabled and otherwise by Profile courier. It is part of Cost. Missing route, pilot or tariff keeps it unavailable. Click to sort."
      )
    }
    if hubRole == .coalition, column == .cost {
      return AppLocalization.text(
        "Total cost: material replacement value plus installation, optional Blueprint allocation, the inbound Profile logistics from the Main Hub and the Home → Coalition transport. No return leg to the Main Hub is included. Warehouse stock keeps its replacement value; only the shortfall consumes purchase cash. Click to sort."
      )
    }
    if hubRole != .main, column == .cost {
      return AppLocalization.text(
        "Total cost: material replacement value plus installation, optional Blueprint allocation and the required inbound Profile logistics from the Main Hub. Products are sold at this hub, so no return leg to the Main Hub is included. Warehouse stock keeps its replacement value; only the shortfall consumes purchase cash. Click to sort."
      )
    }
    switch column {
    case .revenue, .salesTax, .brokerFee:
      return hubText(sortableColumnHelp(column))
    default:
      return AppLocalization.text(sortableColumnHelp(column))
    }
  }

  private func sortableColumnHelp(
    _ column: ManufacturingOpportunitySortColumn
  ) -> String {
    switch column {
    case .cost:
      "Total cost: material replacement value plus installation, optional Blueprint allocation and both required Profile logistics legs. Warehouse stock keeps its replacement value; only the shortfall consumes purchase cash. Click to sort."
    case .revenue:
      "Gross revenue: lowest active sell-order price at the exact Main Hub multiplied by the complete scenario output. No tax or fee has been deducted yet. Click to sort."
    case .salesTax:
      "Sales tax: gross revenue multiplied by the effective trader sales-tax rate from the configured Main-Hub Profile. It is deducted from revenue. Click to sort."
    case .brokerFee:
      "Broker fee: gross revenue multiplied by the effective broker-fee rate from the configured Main-Hub Profile. It is deducted from revenue. Click to sort."
    case .profit:
      "Profit: gross revenue minus sales tax and broker fee, then minus total cost. If any required market, fee, Warehouse or logistics value is unavailable, profit remains unavailable. Click to sort."
    case .dailyProfitPotential:
      "Daily profit potential: scenario profit divided by produced units, multiplied by the lower of the selected batch quantity and currently observed daily demand. It cannot exceed this batch's profit and is not a sales guarantee. Click to sort."
    case .demand:
      "Daily demand shows the conservative current exact-hub rate, plus the previous UTC day and the average of known recorded days where available. Missing observations remain unavailable. Click to sort by current demand."
    case .runs:
      "Runs is editable for each item. A change recalculates only that row from the saved Main Hub scenario and captured weighted unit prices; use Update for fresh market depth. Click the heading to sort."
    case .materialEfficiency:
      "ME is editable for manufacturing items and changes material quantities with EVE rounding. Reactions have no ME and remain unavailable in this column. Tech I modules start at ME 10, Loyalty Store BPC products at ME 0 and Tech II candidates at ME 3 until a concrete Blueprint is selected in the Planner. Click the heading to sort."
    case .timeEfficiency:
      "TE is editable for manufacturing items and changes production duration. Reactions have no TE and remain unavailable in this column. Tech I modules start at TE 20, Loyalty Store BPC products at TE 0 and Tech II candidates at TE 2 until a concrete Blueprint is selected in the Planner. Click the heading to sort."
    case .roi:
      "ROI: profit divided by total scenario cost. Missing profit or cost remains unavailable. Click to sort."
    case .iskPerHour:
      "ISK per hour: scenario profit divided by the calculated production duration for the row's selected ME and TE. Click to sort."
    case .iskPerCubicMeter:
      "ISK per cubic metre: scenario profit divided by the packaged volume of the complete output. Missing volume remains unavailable. Click to sort."
    default:
      "Click to sort ascending; click again to sort descending."
    }
  }

  /// Provisional contract values carry a leading "≈".
  private func contractCellText(
    _ value: String,
    _ contract: ManufacturingOpportunityContractProjection?
  ) -> String {
    guard let contract, contract.unitPrice != nil else { return value }
    return contract.isProvisional ? "≈ \(value)" : value
  }

  private func contractCellColor(
    _ contract: ManufacturingOpportunityContractProjection?,
    value: Double?
  ) -> Color {
    guard let contract, contract.unitPrice != nil else {
      return DesignTokens.caution
    }
    if contract.isProvisional || contract.isBeforeContractFee {
      return DesignTokens.caution
    }
    guard let value else { return DesignTokens.textPrimary }
    return value >= 0 ? DesignTokens.positive : DesignTokens.negative
  }

  private func textCell(
    _ value: String,
    width: CGFloat,
    alignment: Alignment = .trailing,
    color: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: value)
      .font(.caption.monospacedDigit())
      .lineLimit(1)
      .help(value)
      .foregroundStyle(color)
      .frame(width: width, alignment: alignment)
  }

  private func requestedRunsCell(
    _ row: ManufacturingOpportunityRow
  ) -> some View {
    let text =
      requestedRunTextsByTypeID[row.productTypeID]
      ?? String(requestedRunsByTypeID[row.productTypeID] ?? row.runs)
    let isValid = requestedRuns(from: text) != nil
    let hasOverride = requestedRunsByTypeID[row.productTypeID] != nil
    return HStack(spacing: 3) {
      TextField(
        "Runs",
        text: requestedRunsBinding(for: row)
      )
      .textFieldStyle(.roundedBorder)
      .font(.caption.monospacedDigit())
      .multilineTextAlignment(.trailing)
      .frame(width: hasOverride ? 50 : 68)
      .overlay {
        if !isValid {
          RoundedRectangle(cornerRadius: 4).stroke(DesignTokens.negative)
        }
      }
      .onSubmit { normalizeRequestedRuns(for: row) }
      .accessibilityLabel(
        AppLocalization.format("Runs for %@", row.productName)
      )
      .accessibilityHint(
        "Changing this value recalculates only this item from the saved Main Hub scenario."
      )
      if hasOverride {
        Image(systemName: "info.circle")
          .font(.caption2)
          .foregroundStyle(DesignTokens.caution)
          .help(
            "This item-only estimate reuses the captured weighted Main Hub unit prices. Use Update for fresh market depth."
          )
          .accessibilityLabel("Item-only estimate")
          .accessibilityHint(
            "Uses captured weighted Main Hub unit prices; Update fetches fresh market depth."
          )
      }
    }
    .frame(width: 68, alignment: .trailing)
  }

  @ViewBuilder
  private func requestedEfficiencyCell(
    _ row: ManufacturingOpportunityRow,
    kind: OpportunityEfficiencyKind
  ) -> some View {
    if !row.supportsBlueprintEfficiency {
      textCell("—", width: 58)
        .help("Reactions use formula runs. ME and TE do not apply.")
        .accessibilityLabel(
          kind == .material
            ? "Material efficiency does not apply"
            : "Time efficiency does not apply"
        )
    } else {
      let text = requestedEfficiencyText(for: row, kind: kind)
      let isValid =
        requestedEfficiency(from: text, kind: kind, row: row) != nil
      TextField(
        kind == .material ? "ME" : "TE",
        text: requestedEfficiencyBinding(for: row, kind: kind)
      )
      .textFieldStyle(.roundedBorder)
      .font(.caption.monospacedDigit())
      .multilineTextAlignment(.trailing)
      .frame(width: 58)
      .overlay {
        if !isValid {
          RoundedRectangle(cornerRadius: 4).stroke(DesignTokens.negative)
        }
      }
      .onSubmit { normalizeRequestedEfficiency(for: row, kind: kind) }
      .help(
        kind == .material
          ? "Material efficiency for this candidate. Tech I modules start at ME 10, Loyalty Store BPC products at ME 0 and Tech II candidates at ME 3. The Planner verifies the concrete Blueprint value."
          : "Time efficiency for this candidate. Tech I modules start at TE 20, Loyalty Store BPC products at TE 0 and Tech II candidates at TE 2. The Planner verifies the concrete Blueprint value."
      )
      .accessibilityLabel(
        AppLocalization.format(
          "%@ for %@",
          kind == .material ? "ME" : "TE",
          row.productName
        )
      )
    }
  }

  private func dailyDemandCell(
    _ row: ManufacturingOpportunityRow
  ) -> some View {
    let previousAndAverage: String?
    if let previous = row.previousDayDemand,
      let average = row.averageDailyDemand
    {
      previousAndAverage = AppLocalization.format(
        "Previous day %@ · average %@ (%@ days)",
        formatInteger(previous),
        formatInteger(average),
        formatInteger(row.recordedDemandDayCount ?? 0)
      )
    } else if let previous = row.previousDayDemand {
      previousAndAverage = AppLocalization.format(
        "Previous day %@",
        formatInteger(previous)
      )
    } else if let average = row.averageDailyDemand {
      previousAndAverage = AppLocalization.format(
        "Average %@ (%@ days)",
        formatInteger(average),
        formatInteger(row.recordedDemandDayCount ?? 0)
      )
    } else {
      previousAndAverage = nil
    }
    let changeText = row.demandChangeFromPreviousDayPercent.map { change in
      let number = abs(change).formatted(
        .number
          .locale(AppLocalization.currentLanguage.locale)
          .grouping(.automatic)
          .precision(.fractionLength(1))
      )
      let signed = change > 0 ? "+\(number)%" : change < 0 ? "−\(number)%" : "0%"
      return AppLocalization.format("≈ %@ vs previous day", signed)
    }
    let help = [
      row.observedDailyDemand.map {
        AppLocalization.format("Current daily demand: %@", formatInteger($0))
      },
      previousAndAverage,
      changeText,
    ].compactMap { $0 }.joined(separator: "\n")

    return VStack(alignment: .trailing, spacing: 1) {
      Text(verbatim: row.observedDailyDemand.map(formatInteger) ?? "—")
        .font(.caption.monospacedDigit())
      if let previousAndAverage {
        Text(verbatim: previousAndAverage)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
          .lineLimit(1)
      }
      if let changeText {
        Text(verbatim: changeText)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(
            (row.demandChangeFromPreviousDayPercent ?? 0) >= 0
              ? DesignTokens.positive : DesignTokens.negative
          )
          .lineLimit(1)
      }
    }
    .help(help)
    .accessibilityElement(children: .combine)
    .frame(width: 155, alignment: .trailing)
  }

  private func productionTreePane(
    _ opportunity: ManufacturingOpportunityRow
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: DesignTokens.spacingSM) {
        Label("Production tree", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.caption.bold())
        Text(
          AppLocalization.format(
            "%@ runs · produces %@ units",
            formatInteger(opportunity.runs),
            formatInteger(opportunity.producedQuantity)
          )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if let plan = productionTree?.selectedPlan {
          treeSummaryMetric(
            "Production cost",
            formatISK(plan.costBreakdown?.totalProductionCost)
          )
          treeSummaryMetric(
            "Listed profit",
            formatSignedISK(plan.listedSale.profit)
          )
          treeSummaryMetric(
            "Logistics",
            formatISK(plan.costBreakdown?.effectiveLogisticsCost)
          )
        }
      }
      .padding(DesignTokens.spacingSM)
      .background(DesignTokens.elevated)

      HStack(spacing: 0) {
        treeHeaderCell("Step / item", width: 420, alignment: .leading)
        treeHeaderCell("Recommendation", width: 180, alignment: .leading)
        treeHeaderCell("Source", width: 120, alignment: .leading)
        treeHeaderCell("Required", width: 90)
        treeHeaderCell("Produced", width: 90)
        treeHeaderCell("Runs", width: 65)
        treeHeaderCell("Production stock", width: 175, alignment: .leading)
        treeHeaderCell("Blueprint / formula", width: 360, alignment: .leading)
      }
      .background(DesignTokens.panel)

      if isLoadingProductionTree {
        HStack(spacing: DesignTokens.spacingSM) {
          ProgressView().controlSize(.small)
          Text(
            "Calculating the complete recipe, Main Hub recommendation, exact-location stock and blueprint availability…"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.spacingMD)
      } else if let productionTreeError {
        Label(
          productionTreeError.localizedUI,
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.negative)
        .padding(DesignTokens.spacingMD)
      } else if let tree = productionTree {
        let nodes = tree.nodesByID
        VStack(alignment: .leading, spacing: 0) {
          ForEach(tree.rootIDs, id: \.self) { rootID in
            if let root = nodes[rootID] {
              productionTreeNode(
                root,
                depth: 0,
                isRoot: true,
                nodes: nodes,
                opportunity: opportunity
              )
            }
          }
        }
        if tree.selectedPlan.costBreakdown?.logistics == nil {
          Label(
            "Round-trip logistics could not be priced completely. Missing rates, volume, collateral or market depth remain unavailable rather than zero.",
            systemImage: "shippingbox.and.arrow.backward"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
          .padding(DesignTokens.spacingSM)
        }
        Label(
          "Blueprint source selections are recorded as concrete jobs in this open tree. Copying, research and invention remain disabled until their complete Science jobs are available.",
          systemImage: "doc.on.doc"
        )
        .font(.caption)
        if let supplyPlans = tree.selectedPlan.blueprintSupplyPlans,
          !supplyPlans.isEmpty
        {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(supplyPlans) { supply in
              HStack(spacing: DesignTokens.spacingSM) {
                EVEItemText(
                  value: supply.productName,
                  typeID: supply.productTypeID,
                  font: .caption
                )
                Text(
                  AppLocalization.format(
                    "%@ concrete Blueprint job(s) · %@ required runs",
                    supply.manufacturingJobs.count.formatted(),
                    supply.requiredRuns.formatted()
                  )
                )
                .font(.caption.monospacedDigit())
              }
              ForEach(supply.manufacturingJobs) { job in
                HStack(spacing: DesignTokens.spacingSM) {
                  Text(
                    AppLocalization.format(
                      "%@ runs · ME %@ · TE %@ · %@ remaining",
                      job.runs.formatted(),
                      job.allocation.materialEfficiency.formatted(),
                      job.allocation.timeEfficiency.formatted(),
                      job.allocation.remainingRuns?.formatted() ?? "unlimited"
                    )
                  )
                  .font(.caption.monospacedDigit())
                  if let owner = job.allocation.ownerName {
                    EVEEntityText(value: owner, font: .caption)
                  }
                  if let location = job.allocation.locationName {
                    EVEEntityText(value: location, font: .caption)
                  }
                }
                .padding(.leading, DesignTokens.spacingMD)
              }
            }
          }
          .padding(DesignTokens.spacingSM)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
    .frame(minWidth: 1_600, alignment: .leading)
    .background(DesignTokens.canvas)
    .overlay(alignment: .top) {
      Rectangle().fill(DesignTokens.accent).frame(height: 2)
    }
  }

  private func productionTreeNode(
    _ node: ManufacturingProductionTreeNode,
    depth: Int,
    isRoot: Bool,
    nodes: [UUID: ManufacturingProductionTreeNode],
    opportunity: ManufacturingOpportunityRow
  ) -> AnyView {
    let isExpanded = expandedProductionNodeIDs.contains(node.id)
    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
          HStack(spacing: 5) {
            if !node.children.isEmpty {
              Button {
                toggleProductionNode(node.id)
              } label: {
                Image(systemName: "chevron.right")
                  .font(.caption2)
                  .rotationEffect(.degrees(isExpanded ? 90 : 0))
                  .frame(width: 16, height: 18)
              }
              .buttonStyle(.plain)
            } else {
              Color.clear.frame(width: 16, height: 18)
            }
            Image(systemName: productionTreeIcon(node))
              .foregroundStyle(productionTreeActionColor(node.action))
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
              EVEItemText(
                value: node.name,
                typeID: node.typeID,
                lineLimit: 1,
                iconSize: 20
              )
              Text(verbatim: productionTreeSubtitle(node))
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.leading, CGFloat(depth) * 18 + 6)
          .frame(width: 420, alignment: .leading)

          recommendationView(node)
            .frame(width: 180, alignment: .leading)

          if node.canBuild && !isRoot {
            Picker(
              "Source",
              selection: treeSupplyBinding(
                for: node,
                opportunity: opportunity
              )
            ) {
              Text("Build").tag(MaterialSupplyMode.produce)
              Text("Buy").tag(MaterialSupplyMode.buy)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120, alignment: .leading)
          } else {
            Text(isRoot ? "Build" : productionTreeActionTitle(node.action))
              .font(.caption)
              .frame(width: 120, alignment: .leading)
          }

          treeNumberCell(node.requestedQuantity, width: 90)
          treeNumberCell(node.producedQuantity, width: 90)
          treeNumberCell(Int64(node.runs ?? 0), width: 65, dashForZero: true)

          if isRoot {
            Text("—")
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
              .frame(width: 175, alignment: .leading)
          } else {
            stockCoverageView(node)
              .frame(width: 175, alignment: .leading)
          }

          if let blueprint = node.blueprint {
            blueprintSourceView(
              blueprint,
              node: node,
              opportunity: opportunity
            )
            .frame(width: 360, alignment: .leading)
          } else {
            Text("—")
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
              .frame(width: 360, alignment: .leading)
          }
        }
        .padding(.vertical, 5)
        .background(depth.isMultiple(of: 2) ? Color.clear : DesignTokens.elevated.opacity(0.35))
        .overlay(alignment: .bottom) { Divider() }

        if isExpanded {
          ForEach(node.children, id: \.self) { childID in
            if let child = nodes[childID] {
              productionTreeNode(
                child,
                depth: depth + 1,
                isRoot: false,
                nodes: nodes,
                opportunity: opportunity
              )
            }
          }
        }
      }
    )
  }

  private func recommendationView(
    _ node: ManufacturingProductionTreeNode
  ) -> some View {
    let text: String
    let color: Color
    switch node.recommendation {
    case .produce:
      text = "Build".localizedUI + savingsSuffix(node.recommendationSavings)
      color = DesignTokens.positive
    case .buy:
      text = "Buy".localizedUI + savingsSuffix(node.recommendationSavings)
      color = DesignTokens.highlight
    case .unavailable:
      text = "Comparison unavailable".localizedUI
      color = DesignTokens.caution
    case nil:
      text =
        node.canBuild
        ? "Top-level build".localizedUI
        : "Raw material".localizedUI
      color = DesignTokens.textSecondary
    }
    return Text(verbatim: text)
      .font(.caption.bold())
      .foregroundStyle(color)
      .lineLimit(1)
      .help(
        "The recommendation compares the complete required quantity at the configured Main Hub, including configured inbound logistics and the production job."
      )
  }

  private func stockCoverageView(
    _ node: ManufacturingProductionTreeNode
  ) -> some View {
    let text: String
    if let usable = node.usableWarehouseQuantity {
      text =
        "\(formatInteger(usable)) / \(formatInteger(node.totalRequiredQuantity))"
    } else {
      text = "Stock unavailable".localizedUI
    }
    return Text(verbatim: text)
      .font(.caption.monospacedDigit().bold())
      .foregroundStyle(stockCoverageColor(node.stockCoverage))
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(stockCoverageColor(node.stockCoverage).opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .help(stockCoverageHelp(node))
  }

  private func blueprintSourceView(
    _ blueprint: ProductionTreeBlueprintAssessment,
    node: ManufacturingProductionTreeNode,
    opportunity: ManufacturingOpportunityRow
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      EVEItemText(
        value: blueprint.blueprintName,
        typeID: blueprint.blueprintTypeID,
        font: .caption2,
        lineLimit: 1,
        iconSize: 14
      )
      HStack(spacing: 4) {
        Picker(
          "Blueprint source",
          selection: treeBlueprintBinding(
            blueprint,
            opportunity: opportunity
          )
        ) {
          ForEach(
            blueprint.availableActions.sorted { $0.rawValue < $1.rawValue },
            id: \.self
          ) { action in
            Text(blueprintActionTitle(action, assessment: blueprint)).tag(action)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 225, alignment: .leading)
        Text(
          verbatim: blueprintRecommendationLabel(
            blueprint.recommendation,
            assessment: blueprint
          )
        )
        .font(.caption2.bold())
        .foregroundStyle(blueprintActionColor(blueprint.recommendation))
        .lineLimit(1)
      }
      let action =
        treeBlueprintActions[blueprint.blueprintTypeID]
        ?? blueprint.recommendation
      let concreteSources = treeConcreteBlueprintSources(
        blueprint,
        action: action
      )
      if !concreteSources.isEmpty {
        Picker(
          "Concrete Blueprint",
          selection: treeConcreteBlueprintSourceBinding(
            blueprint,
            opportunity: opportunity,
            choices: concreteSources
          )
        ) {
          Text("Automatic concrete allocation").tag(
            Optional<String>.none
          )
          ForEach(concreteSources) { choice in
            Text(verbatim: choice.title).tag(Optional(choice.id))
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 225, alignment: .leading)
      }
      if action == .useOwnedBPC || action == .useOwnedBPO {
        ForEach(blueprint.productionLocationNames, id: \.self) { name in
          EVEEntityText(value: name, font: .caption2, lineLimit: 1)
        }
        let owners =
          action == .useOwnedBPC
          ? blueprint.exactLocationBPCOwnerNames
          : blueprint.exactLocationBPOOwnerNames
        ForEach(owners, id: \.self) { owner in
          EVEEntityText(value: owner, font: .caption2, lineLimit: 1)
        }
        let sourceStates =
          action == .useOwnedBPC
          ? blueprint.exactLocationBPCSourceStates
          : blueprint.exactLocationBPOSourceStates
        if sourceStates.contains(where: { $0 != .fresh }) {
          Label(
            "Owned Blueprint evidence is retained but not fully fresh.",
            systemImage: "clock.badge.exclamationmark"
          )
          .font(.caption2)
          .foregroundStyle(DesignTokens.caution)
        }
      } else if blueprint.otherLocationBPOCount > 0
        || blueprint.otherLocationBPCCount > 0
      {
        Label(
          "An owned Blueprint exists at another location. Move it to the displayed production location and refresh Blueprints and Assets before selecting it.",
          systemImage: "shippingbox.and.arrow.backward"
        )
        .font(.caption2)
        .foregroundStyle(DesignTokens.caution)
      }
      if action == .buyContractBPC,
        let price = blueprint.attributableBPCContractPrice
      {
        Text(
          AppLocalization.format(
            "Included BPC cost: %@ · %@ contracts · %@ runs",
            formatISK(price),
            formatInteger(blueprint.attributableBPCContractSelectionCount),
            blueprint.attributableBPCContractRuns.map(formatInteger) ?? "—"
          )
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(DesignTokens.positive)
      } else if action.requiresExplicitCost {
        TextField(
          "Allocated ISK",
          text: treeBlueprintCostBinding(
            blueprintTypeID: blueprint.blueprintTypeID
          )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 150)
        .onSubmit { reloadProductionTree(opportunity) }
      }
    }
    .help(blueprintAssessmentHelp(blueprint, node: node))
  }

  private func treeSummaryMetric(
    _ label: LocalizedStringKey,
    _ value: String
  ) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value)
        .font(.caption.bold().monospacedDigit())
    }
  }

  private func treeHeaderCell(
    _ title: LocalizedStringKey,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Text(title)
      .font(.caption2.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      .frame(width: width, alignment: alignment)
      .padding(.vertical, 5)
  }

  private func treeNumberCell(
    _ value: Int64,
    width: CGFloat,
    dashForZero: Bool = false
  ) -> some View {
    Text(verbatim: dashForZero && value == 0 ? "—" : formatInteger(value))
      .font(.caption.monospacedDigit())
      .frame(width: width, alignment: .trailing)
  }

  private func workbench(_ snapshot: ManufacturingOpportunitySnapshot?) -> some View {
    let row = snapshot.flatMap { selectedRow(in: $0) }
    let procurement = row.map(procurementProjection(for:))
    let productionScope = runtime.productionBasis.productionWarehouseScope
    let mainHubName =
      snapshot?.mainHub.name
      ?? runtime.productionBasis.mainTradingLocation?.location.name
      ?? "Main Hub"

    return GeometryReader { geometry in
      let layout = ManufacturingOpportunityWorkbenchLayout(
        viewportSize: geometry.size
      )
      HStack(spacing: 0) {
        Group {
          if let row, let procurement {
            warehousePane(
              row,
              procurement: procurement,
              productionScope: productionScope
            )
          } else {
            warehouseOverviewPane(productionScope: productionScope)
          }
        }
        .frame(
          width: layout.columnWidth,
          height: layout.viewportHeight,
          alignment: .topLeading
        )
        if layout.dividerWidth > 0 {
          Divider().frame(width: layout.dividerWidth)
        }
        VStack(alignment: .leading, spacing: 0) {
          Picker("Details", selection: $lowerTab) {
            ForEach(OpportunityLowerTab.allCases) { tab in
              Text(tab.title).tag(tab)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .padding(DesignTokens.spacingSM)
          .background(DesignTokens.elevated)
          Rectangle().fill(DesignTokens.accent).frame(height: 2)
          if let row, let procurement, let snapshot {
            switch lowerTab {
            case .mainHub:
              mainHubPane(
                row,
                procurement: procurement,
                name: snapshot.mainHub.name
              )
            case .shopping:
              shoppingPane(procurement, mainHubName: snapshot.mainHub.name)
            case .costs:
              costDetailPane(row)
            }
          } else {
            unselectedDetailPane(mainHubName: mainHubName)
          }
        }
        .frame(
          width: layout.columnWidth,
          height: layout.viewportHeight,
          alignment: .topLeading
        )
        .background(DesignTokens.canvas)
      }
      .frame(
        width: layout.viewportWidth,
        height: layout.viewportHeight,
        alignment: .topLeading
      )
    }
  }

  private func warehouseOverviewPane(
    productionScope: ProductionWarehouseScope
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("WAREHOUSE").font(.caption.bold()).tracking(1.1)
        Text(verbatim: productionScopeLabel(productionScope))
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if isPreparingWarehouse {
          ProgressView().controlSize(.small)
        } else if warehouseHasSnapshot {
          Text(
            verbatim:
              String(
                format: "%@ owners · %@ units".localizedUI,
                formatInteger(preparedWarehouse.inventoryCount),
                formatInteger(preparedWarehouse.totalUnits)
              )
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .padding(DesignTokens.spacingSM)
      .background(DesignTokens.elevated)
      Rectangle().fill(DesignTokens.accent).frame(height: 2)

      if productionScope.locations.isEmpty {
        ContentUnavailableView(
          "Production locations unresolved",
          systemImage: "shippingbox.and.arrow.backward",
          description: Text(
            "Assign production, reaction, invention and copying locations before their stock can be combined here."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else if warehouseHasSnapshot {
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(productionScope.locations) { location in
              let warehouseLocation = preparedWarehouse.warehouse.locations.first {
                $0.id == location.locationID
              }
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    EVEEntityText(value: location.structureName)
                    EVEEntityText(value: location.solarSystemName)
                  }
                  Spacer()
                  if let warehouseLocation {
                    Text(
                      verbatim:
                        String(
                          format: "%@ types · %@ units".localizedUI,
                          formatInteger(warehouseLocation.distinctTypeCount),
                          formatInteger(warehouseLocation.totalUnits)
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                  } else {
                    Text("No location data in current snapshot")
                      .font(.caption)
                      .foregroundStyle(DesignTokens.caution)
                  }
                }
                Text(
                  verbatim: location.activities.map(\.displayName).sorted()
                    .joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
              }
              .padding(DesignTokens.spacingSM)
              .overlay(alignment: .bottom) { Divider() }
            }
          }
        }
        .defaultScrollAnchor(.topLeading)
        HStack {
          if preparedWarehouse.ownerStatuses.contains(where: {
            $0.state != .fresh
          }) {
            Label(
              "Warehouse snapshot is not fully fresh",
              systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(DesignTokens.caution)
          } else {
            Text(
              "Select an item to compare its required materials with this stock."
            )
          }
        }
        .font(.caption)
        .padding(DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.elevated)
      } else {
        ContentUnavailableView(
          "Warehouse unavailable",
          systemImage: "shippingbox",
          description: Text(
            "Synchronize character assets before stock can reduce the shopping list. Missing inventory is not treated as zero."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(DesignTokens.canvas)
  }

  private func unselectedDetailPane(mainHubName: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(lowerTab.title)
          .font(.caption.bold())
        if lowerTab == .mainHub {
          EVEEntityText(value: mainHubName)
        }
        Spacer()
      }
      .padding(DesignTokens.spacingSM)
      ContentUnavailableView(
        "Select an item",
        systemImage: "list.bullet.rectangle",
        description: Text(
          "The Warehouse and this menu stay available; item-specific values appear after you select a candidate above."
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func warehousePane(
    _ row: ManufacturingOpportunityRow,
    procurement: ManufacturingOpportunityProcurementProjection,
    productionScope: ProductionWarehouseScope
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("WAREHOUSE").font(.caption.bold()).tracking(1.1)
        Text(verbatim: productionScopeLabel(productionScope))
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        if isPreparingWarehouse {
          ProgressView().controlSize(.small)
        } else {
          Text(
            verbatim:
              String(
                format: "%@ owners · %@ units".localizedUI,
                formatInteger(preparedWarehouse.inventoryCount),
                formatInteger(preparedWarehouse.totalUnits)
              )
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .padding(DesignTokens.spacingSM)
      .background(DesignTokens.elevated)
      Rectangle().fill(DesignTokens.accent).frame(height: 2)
      if warehouseHasSnapshot {
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
              ForEach(procurement.lines) { line in
                HStack(spacing: 0) {
                  entityLowerCell(
                    line.name,
                    typeID: line.typeID,
                    width: 190
                  )
                  lowerCell(formatInteger(line.requiredQuantity), width: 76)
                  lowerCell(
                    formatInteger(line.factualWarehouseQuantity),
                    width: 76
                  )
                  lowerCell(formatInteger(line.protectedQuantity), width: 70)
                  lowerCell(formatInteger(line.reservedQuantity), width: 70)
                  lowerCell(
                    formatInteger(line.usableWarehouseQuantity),
                    width: 76
                  )
                  lowerCell(
                    formatInteger(line.fromWarehouse),
                    width: 76,
                    color: line.fromWarehouse > 0
                      ? DesignTokens.positive : DesignTokens.textSecondary
                  )
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Divider() }
              }
            } header: {
              HStack(spacing: 0) {
                lowerHeader("Material", width: 190, alignment: .leading)
                lowerHeader("Required", width: 76)
                lowerHeader("Factual", width: 76)
                lowerHeader("Target", width: 70)
                lowerHeader("Reserved", width: 70)
                lowerHeader("Usable", width: 76)
                lowerHeader("Use", width: 76)
              }
            }
          }
        }
        HStack {
          if preparedWarehouse.ownerStatuses.contains(where: {
            $0.state != .fresh
          }) {
            Label(
              "Warehouse snapshot is not fully fresh",
              systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(DesignTokens.caution)
          } else {
            Text("Warehouse replacement value")
          }
          Spacer()
          Text(formatISK(procurement.warehouseReplacementValue))
            .monospacedDigit()
        }
        .font(.caption.bold())
        .padding(DesignTokens.spacingSM)
        .background(DesignTokens.elevated)
      } else {
        ContentUnavailableView(
          "Warehouse unavailable",
          systemImage: "shippingbox",
          description: Text(
            "Synchronize character assets before stock can reduce the shopping list. Missing inventory is not treated as zero."
          )
        )
      }
    }
    .background(DesignTokens.canvas)
  }

  private func mainHubPane(
    _ row: ManufacturingOpportunityRow,
    procurement: ManufacturingOpportunityProcurementProjection,
    name: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label(name, systemImage: "building.columns")
        Spacer()
        Text("Complete required depth")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .font(.caption)
      .padding(DesignTokens.spacingSM)
      ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 0) {
            lowerHeader("Material", width: 220, alignment: .leading)
            lowerHeader("Required", width: 85)
            lowerHeader("Covered", width: 85)
            lowerHeader("Unit price", width: 115)
            lowerHeader("Full value", width: 125)
          }
          ForEach(Array(zip(row.materials, procurement.lines)), id: \.0.id) {
            material, line in
            HStack(spacing: 0) {
              entityLowerCell(
                material.name,
                typeID: material.typeID,
                width: 220
              )
              lowerCell(formatInteger(material.quantity), width: 85)
              lowerCell(
                "\(formatInteger(line.marketFilledQuantity)) / \(formatInteger(material.quantity))",
                width: 85,
                color: line.hasCompleteMarketCoverage
                  ? DesignTokens.positive : DesignTokens.caution
              )
              lowerCell(formatISK(line.weightedUnitPrice), width: 115)
              lowerCell(formatISK(material.quote.total), width: 125)
            }
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) { Divider() }
          }
        }
      }
    }
  }

  private func shoppingPane(
    _ procurement: ManufacturingOpportunityProcurementProjection,
    mainHubName: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("Shopping List", systemImage: "cart.fill")
          .font(.headline)
        EVEEntityText(value: mainHubName)
        Spacer()
        Button {
          copyShoppingList(procurement)
        } label: {
          Label("Copy Multibuy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!warehouseHasSnapshot || procurement.multibuyText.isEmpty)
      }
      .padding(DesignTokens.spacingSM)
      if warehouseHasSnapshot {
        ScrollView([.horizontal, .vertical]) {
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
              lowerHeader("Item", width: 220, alignment: .leading)
              lowerHeader("From stock", width: 90)
              lowerHeader("To buy", width: 85)
              lowerHeader("Unit price", width: 115)
              lowerHeader("Cash needed", width: 125)
            }
            ForEach(procurement.lines.filter { $0.toBuy > 0 }) { line in
              HStack(spacing: 0) {
                entityLowerCell(
                  line.name,
                  typeID: line.typeID,
                  width: 220
                )
                lowerCell(formatInteger(line.fromWarehouse), width: 90)
                lowerCell(formatInteger(line.toBuy), width: 85)
                lowerCell(formatISK(line.weightedUnitPrice), width: 115)
                lowerCell(formatISK(line.purchaseCashRequirement), width: 125)
              }
              .padding(.vertical, 5)
              .overlay(alignment: .bottom) { Divider() }
            }
          }
        }
        HStack {
          if let shoppingCopyStatus {
            Label(shoppingCopyStatus, systemImage: "checkmark.circle.fill")
              .foregroundStyle(DesignTokens.positive)
          }
          Spacer()
          Text(
            AppLocalization.format(
              "%@ units",
              formatInteger(procurement.totalQuantityToBuy)
            )
          )
          .foregroundStyle(DesignTokens.textSecondary)
          Text(formatISK(procurement.purchaseCashRequirement))
            .fontWeight(.semibold)
            .monospacedDigit()
        }
        .font(.caption)
        .padding(DesignTokens.spacingSM)
        .background(DesignTokens.elevated)
      } else {
        ContentUnavailableView(
          "Shopping list unavailable",
          systemImage: "cart.badge.questionmark",
          description: Text(
            "A factual snapshot at the assigned production locations is required before purchase quantities can be calculated."
          )
        )
      }
    }
  }

  private func costDetailPane(_ row: ManufacturingOpportunityRow) -> some View {
    let procurement = procurementProjection(for: row)
    let logistics = logisticsProjection(for: row)
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: costSheet,
      logistics: logistics,
      contract: contractContext
    )
    return ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(alignment: .firstTextBaseline) {
          EVEItemText(value: row.productName, typeID: row.productTypeID)
          Spacer()
          Text(verbatim: "\(row.groupName) · \(row.categoryName)")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 135, maximum: 210))],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          detailMetric("Material cost", formatISK(costs.materialCost))
          detailMetric(
            "Material purchase cash",
            formatISK(procurement.purchaseCashRequirement)
          )
          detailMetric("Installation", formatISK(costs.installationCost))
          detailMetric("Blueprint allocation", formatISK(costs.blueprintAllocation))
          detailMetric("Logistics", formatISK(costs.logisticsCost))
          detailMetric("Total cost", formatISK(costs.totalCost))
          detailMetric("Gross revenue", formatISK(costs.grossRevenue))
          detailMetric("Sales tax", formatISK(costs.salesTax))
          detailMetric("Broker fee", formatISK(costs.brokerFee))
          detailMetric("Profit", formatSignedISK(costs.profit))
          detailMetric(
            "Daily profit potential",
            formatSignedISK(
              ManufacturingOpportunityScenarioProjector.dailyProfitPotential(
                for: row,
                costs: costs
              )
            )
          )
          detailMetric(
            "Estimated sell-through",
            formatDays(
              ManufacturingOpportunityScenarioProjector
                .estimatedSellThroughDays(for: row)
            )
          )
          detailMetric("ROI", formatPercent(costs.returnOnInvestment))
          detailMetric("ISK / h", formatISK(costs.iskPerHour))
          detailMetric("ISK / m³", formatISK(costs.iskPerCubicMeter))
          detailMetric(
            "Contract price",
            contractCellText(formatISK(costs.contract?.unitPrice), costs.contract)
          )
          detailMetric(
            "Contract revenue",
            contractCellText(
              formatISK(costs.contract?.grossRevenue),
              costs.contract
            )
          )
          detailMetric(
            "Contract fee",
            costs.contract?.isBeforeContractFee == true
              ? AppLocalization.text("Before contract fee")
              : formatISK(costs.contract?.contractFee)
          )
          detailMetric(
            "Contract profit",
            contractCellText(
              formatSignedISK(costs.contract?.profit),
              costs.contract
            )
          )
          detailMetric(
            "Contract ROI",
            formatPercent(costs.contract?.returnOnInvestment)
          )
          if hubRole == .coalition {
            detailMetric(
              "Home → Coalition",
              formatISK(costs.onwardTransportCost)
            )
          }
        }
        if let facilityName = row.facilityName {
          Label(facilityName, systemImage: "hammer.fill")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        ForEach(logistics.legs) { leg in
          HStack(spacing: DesignTokens.spacingSM) {
            EVEEntityText(value: leg.origin, font: .caption)
            Image(systemName: "arrow.right")
              .foregroundStyle(DesignTokens.textSecondary)
            EVEEntityText(value: leg.destination, font: .caption)
            Spacer()
            Text(formatISK(leg.roundedCharge))
              .font(.caption.monospacedDigit())
          }
        }
        if let referenceError = runtime.opportunityContractReferenceError {
          Label(referenceError.localizedUI, systemImage: "doc.text.magnifyingglass")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        } else if let contract = costs.contract {
          if contract.unitPrice == nil {
            Label(
              "No comparable public contract offer was observed for this product. Contract values remain unavailable.",
              systemImage: "doc.text.magnifyingglass"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          } else if contract.isProvisional {
            Label(
              "The Public Contracts index is incomplete. The contract price is a provisional estimate from offers observed so far.",
              systemImage: "doc.text.magnifyingglass"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
          }
          if contract.unitPrice != nil, contract.isBeforeContractFee {
            Label(
              "No confirmed public-contract fee rate exists for this hub. Contract profit and ROI are shown before the contract fee; enter the rate in Market Settings.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
          }
        }
        // The concrete reason behind an unavailable Home → Coalition transport.
        ForEach(
          analysis?.coalitionTransport?.transport(for: row).warnings ?? []
        ) { warning in
          Label(
            AppLocalization.text(warning.message),
            systemImage: "flag"
          )
          .font(.caption)
          .foregroundStyle(
            warning.severity == .blocking
              ? DesignTokens.negative : DesignTokens.caution
          )
        }
        ForEach(logistics.warnings) { warning in
          Label(
            presentedWarning(warning),
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(
            warning.severity == .blocking
              ? DesignTokens.negative : DesignTokens.caution
          )
        }
        ForEach(row.warnings) { warning in
          Label(
            presentedWarning(warning),
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(
            warning.severity == .blocking
              ? DesignTokens.negative : DesignTokens.caution
          )
        }
      }
      .padding(DesignTokens.spacingSM)
    }
  }

  private func lowerHeader(
    _ title: LocalizedStringKey,
    width: CGFloat,
    alignment: Alignment = .trailing
  ) -> some View {
    Text(title)
      .font(.caption2.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      .frame(width: width, alignment: alignment)
      .padding(.vertical, 5)
      .background(DesignTokens.elevated)
  }

  private func lowerCell(
    _ value: String,
    width: CGFloat,
    alignment: Alignment = .trailing,
    color: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: value)
      .font(.caption.monospacedDigit())
      .lineLimit(1)
      .help(value)
      .foregroundStyle(color)
      .frame(width: width, alignment: alignment)
  }

  private func entityLowerCell(
    _ value: String,
    typeID: Int64,
    width: CGFloat
  ) -> some View {
    EVEItemText(
      value: value,
      typeID: typeID,
      lineLimit: 1,
      iconSize: 18
    )
    .help(value)
    .frame(width: width, alignment: .leading)
  }

  private func filterColumn<Content: View>(
    _ title: LocalizedStringKey,
    help: LocalizedStringKey,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      OpportunityExplanationButton(
        title: title,
        explanation: help,
        systemImage: "info.circle",
        color: DesignTokens.accent,
        font: .caption.bold()
      )
      content()
    }
    .help(Text(help))
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border)
    }
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func compactToggle(
    _ title: LocalizedStringKey,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(title, isOn: isOn)
      .toggleStyle(.checkbox)
      .controlSize(.small)
      .font(.caption)
  }

  private func familyToggle(
    _ family: ManufacturingOpportunityProductFamily
  ) -> some View {
    compactToggle(family.title, isOn: familyBinding(family))
  }

  private func familyBinding(
    _ family: ManufacturingOpportunityProductFamily
  ) -> Binding<Bool> {
    Binding(
      get: { selectedProductFamilies.contains(family) },
      set: { isSelected in
        var values = selectedProductFamilies
        if isSelected { values.insert(family) } else { values.remove(family) }
        persistProductFamilies(values)
      }
    )
  }

  private func productionClassToggle(
    _ productionClass: ManufacturingOpportunityProductionClass
  ) -> some View {
    compactToggle(
      productionClass.title,
      isOn: productionClassBinding(productionClass)
    )
  }

  private func productionClassBinding(
    _ productionClass: ManufacturingOpportunityProductionClass
  ) -> Binding<Bool> {
    Binding(
      get: { selectedProductionClasses.contains(productionClass) },
      set: { isSelected in
        var values = selectedProductionClasses
        if isSelected {
          values.insert(productionClass)
        } else {
          values.remove(productionClass)
        }
        persistProductionClasses(values)
      }
    )
  }

  private func logisticsProjection(
    for row: ManufacturingOpportunityRow
  ) -> ManufacturingOpportunityLogisticsProjection {
    let snapshot = analysis
    return ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: procurementProjection(for: row),
      configuration: snapshot?.logisticsConfiguration,
      mainHub: snapshot?.mainHub
        ?? runtime.productionBasis.mainTradingLocation?.location
        ?? .jita,
      warehouseIsAvailable: warehouseHasSnapshot,
      route: snapshot?.saleRoute(for: row) ?? .mainHubRoundTrip
    )
  }

  private func procurementProjection(
    for row: ManufacturingOpportunityRow
  ) -> ManufacturingOpportunityProcurementProjection {
    ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: preparedWarehouse.factualQuantities,
      protectedQuantities: protectedQuantities,
      reservedQuantities: reservedQuantities
    )
  }

  private func selectedRow(
    in snapshot: ManufacturingOpportunitySnapshot
  ) -> ManufacturingOpportunityRow? {
    snapshot.rows.first { $0.id == selectedTypeID }
  }

  private var categories: [String] {
    Array(Set(analysis?.rows.map(\.categoryName) ?? []))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var groups: [String] {
    Array(Set(analysis?.rows.map(\.groupName) ?? []))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var hasProductionClassMetadata: Bool {
    analysis?.rows.contains {
      $0.metaGroupID != nil || $0.techLevel != nil
    } == true
  }

  private var favoriteIDs: Set<Int64> {
    guard let data = encodedFavoriteIDs.data(using: .utf8),
      let values = try? JSONDecoder().decode([Int64].self, from: data)
    else { return [] }
    return Set(values)
  }

  private var costSheet: ManufacturingOpportunityCostSheet {
    ManufacturingOpportunityCostSheet(
      includesInstallation: true,
      includesSalesTax: true,
      includesBrokerFee: true,
      includesBlueprintAllocation: costIncludesBlueprint,
      blueprintAllocationPerRun: parsedBlueprintCost,
      includesHauling: false,
      haulingCostPerBatch: nil
    )
  }

  private var parsedBlueprintCost: Double? {
    parseNonnegativeISK(blueprintCostPerRunText)
  }

  private var parsedMaximumMaterialPurchaseISK: Double? {
    parseNonnegativeISK(maximumMaterialPurchaseISKText)
  }

  private var maximumMaterialPurchaseISKIsInvalid: Bool {
    !maximumMaterialPurchaseISKText.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty && parsedMaximumMaterialPurchaseISK == nil
  }

  private var protectedQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var reservedQuantities: [Int64: Int64] {
    preparedPlanReservations.quantities
  }

  private var activePlanSnapshotPayloads: [StoredPlanSnapshotPayload] {
    activePlans
      .map {
        StoredPlanSnapshotPayload(
          id: $0.id,
          encodedSnapshot: $0.snapshot
        )
      }
      .sorted { $0.id.uuidString < $1.id.uuidString }
  }

  private var activeCandidateSort: ManufacturingOpportunitySortDescriptor {
    tableSort
      ?? ManufacturingOpportunitySortDescriptor(
        column: .dailyProfitPotential,
        direction: .descending
      )
  }

  private var candidateProjectionTrigger: ManufacturingOpportunityCandidateProjectionTrigger {
    let stockTargetIdentity: [String] = stockTargets.map { target in
      "\(target.typeID):\(target.targetQuantity):\(target.updatedAt.timeIntervalSince1970)"
    }.sorted()
    let sortedFavoriteIDs: [Int64] = favoriteIDs.sorted()
    let productFamilies: [String] =
      selectedProductFamilies.map(\.rawValue).sorted()
    let productionClasses: [String] =
      selectedProductionClasses.map(\.rawValue).sorted()
    let activeSort = activeCandidateSort

    return ManufacturingOpportunityCandidateProjectionTrigger(
      snapshotID: analysis?.id,
      requestedWarehouseIdentity: warehouseIdentity,
      preparedWarehouseIdentity: preparedWarehouseIdentity,
      reservationRevision: preparedPlanReservationRevision,
      stockTargetIdentity: stockTargetIdentity,
      searchText: searchText,
      selectedCategory: selectedCategory,
      selectedGroup: selectedGroup,
      favoritesOnly: favoritesOnly,
      favoriteIDs: sortedFavoriteIDs,
      productFamilies: productFamilies,
      productionClasses: productionClasses,
      valueFilter: valueFilter.rawValue,
      includesCorporationHangars: includeCorporationHangars,
      includesBlueprintCost: costIncludesBlueprint,
      blueprintCostText: blueprintCostPerRunText,
      sortColumn: activeSort.column.rawValue,
      sortDirection: activeSort.direction.rawValue,
      contractReferenceID: runtime.opportunityContractReferences?.id,
      contractFeeRate: runtime.publicContractFeeRate(for: hubRole)
    )
  }

  private var warehouseHasSnapshot: Bool {
    !runtime.productionBasis.productionWarehouseScope.locationIDs.isEmpty
      && preparedWarehouse.ownerStatuses.contains(where: \.hasSnapshot)
  }

  private var warehouseIdentity: String {
    let charactersIdentity = characters.map { character -> String in
      let components: [String] = [
        String(character.characterID),
        character.characterName,
        String(character.assetSnapshot?.count ?? 0),
        String(character.corporationID ?? 0),
        String(character.corporationAssetSnapshot?.count ?? 0),
        String(character.lastSyncAt?.timeIntervalSince1970 ?? 0),
      ]
      return components.joined(separator: ":")
    }.joined(separator: "|")
    let scope = runtime.productionBasis.productionWarehouseScope
    let productionIdentity =
      scope.locations.map {
        "\($0.locationID):\($0.activities.map(\.rawValue).sorted().joined(separator: ","))"
      }.sorted().joined(separator: "|")
      + "|unresolved:"
      + scope.unresolvedActivities.map(\.rawValue).sorted().joined(separator: ",")
    return "\(includeCorporationHangars)|\(charactersIdentity)|\(productionIdentity)"
  }

  private func toggleProductionTree(
    _ opportunity: ManufacturingOpportunityRow
  ) {
    selectedTypeID = opportunity.productTypeID
    if expandedOpportunityTypeID == opportunity.productTypeID {
      collapseProductionTree()
      return
    }
    productionTreeTask?.cancel()
    expandedOpportunityTypeID = opportunity.productTypeID
    productionTree = nil
    productionTreeError = nil
    expandedProductionNodeIDs = []
    reloadProductionTree(opportunity)
  }

  private func collapseProductionTree() {
    productionTreeTask?.cancel()
    productionTreeRunSyncTask?.cancel()
    productionTreeTask = nil
    productionTreeRunSyncTask = nil
    expandedOpportunityTypeID = nil
    productionTree = nil
    productionTreeError = nil
    isLoadingProductionTree = false
    expandedProductionNodeIDs = []
  }

  private func reloadProductionTree(
    _ opportunity: ManufacturingOpportunityRow
  ) {
    let requestedQuantity = min(
      ManufacturingOpportunitySettings.maximumTargetQuantity,
      max(1, opportunity.producedQuantity)
    )
    let warehouse = preparedWarehouse.warehouse
    let hasWarehouseSnapshot = warehouseHasSnapshot
    let targets = protectedQuantities
    let reservations = activeStockAllocations
    let preferences = treeProcurementPreferences
    let inventories = blueprintInventories
    productionTreeTask?.cancel()
    isLoadingProductionTree = true
    productionTreeError = nil
    productionTreeTask = Task { @MainActor in
      do {
        let tree = try await runtime.manufacturingProductionTree(
          productName: opportunity.productName,
          targetQuantity: requestedQuantity,
          materialEfficiency: opportunity.materialEfficiency,
          timeEfficiency: opportunity.timeEfficiency,
          assetWarehouse: warehouse,
          warehouseHasSnapshot: hasWarehouseSnapshot,
          stockTargets: targets,
          existingReservations: reservations,
          existingBlueprintReservations: activeBlueprintReservations,
          procurementPreferences: preferences,
          blueprintInventories: inventories,
          blueprintActions: treeBlueprintActions,
          blueprintManualCosts: parsedTreeBlueprintCosts,
          preferredBlueprintSources: treePreferredBlueprintSources,
          loyaltyStoreBlueprintTypeIDs: Set(
            runtime.loyaltyStoreCatalog?.offeredTypeIDs ?? []
          )
        )
        try Task.checkCancellation()
        guard expandedOpportunityTypeID == opportunity.productTypeID else {
          return
        }
        productionTree = tree
        expandedProductionNodeIDs.formUnion(tree.rootIDs)
        var changedAutomaticSelection = false
        for node in tree.nodes {
          guard let blueprint = node.blueprint else { continue }
          let selected = treeBlueprintActions[blueprint.blueprintTypeID]
          if selected == nil
            || selected.map(blueprint.availableActions.contains) == false
          {
            treeBlueprintActions[blueprint.blueprintTypeID] =
              blueprint.recommendation
            changedAutomaticSelection = true
          }
        }
        productionTreeError = nil
        if changedAutomaticSelection {
          reloadProductionTree(opportunity)
          return
        }
      } catch is CancellationError {
        return
      } catch {
        productionTree = nil
        productionTreeError = productionTreeErrorMessage(error)
      }
      isLoadingProductionTree = false
      productionTreeTask = nil
    }
  }

  private func scheduleExpandedProductionTreeReload() {
    productionTreeRunSyncTask?.cancel()
    guard let typeID = expandedOpportunityTypeID,
      let base = preparedCandidateProjection?.candidates.first(where: {
        $0.row.productTypeID == typeID
      })
    else { return }
    let opportunity = candidateApplyingRequestedParameters(base).row
    productionTreeRunSyncTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .milliseconds(250))
        try Task.checkCancellation()
        guard expandedOpportunityTypeID == typeID else { return }
        reloadProductionTree(opportunity)
      } catch {
        return
      }
      productionTreeRunSyncTask = nil
    }
  }

  private func productionTreeErrorMessage(_ error: Error) -> String {
    switch error {
    case StaticCatalogError.noActiveCatalog:
      "No active SDE catalog is installed.".localizedUI
    case ESIError.notFound:
      "The configured Main Hub or a required production location is unresolved."
        .localizedUI
    case ManufacturingOpportunityError.invalidSettings:
      "Enter valid Runs with valid ME and TE values."
        .localizedUI
    default:
      AppLocalization.format(
        "The production tree could not be calculated. %@",
        error.localizedDescription
      )
    }
  }

  private func toggleProductionNode(_ id: UUID) {
    if expandedProductionNodeIDs.contains(id) {
      expandedProductionNodeIDs.remove(id)
    } else {
      expandedProductionNodeIDs.insert(id)
    }
  }

  private func treeSupplyBinding(
    for node: ManufacturingProductionTreeNode,
    opportunity: ManufacturingOpportunityRow
  ) -> Binding<MaterialSupplyMode> {
    Binding(
      get: {
        treeProcurementPreferences[node.typeID]?.supplyMode
          ?? node.selectedSupplyMode
      },
      set: { mode in
        guard mode == .produce || mode == .buy else { return }
        let hub =
          productionTree?.mainHub
          ?? runtime.productionBasis.mainTradingLocation?.location
          ?? .jita
        treeProcurementPreferences[node.typeID] =
          MaterialProcurementPreference(
            supplyMode: mode,
            purchaseLocation: hub,
            usesAvailableStockFirst: true
          )
        Task { @MainActor in reloadProductionTree(opportunity) }
      }
    )
  }

  private func treeBlueprintBinding(
    _ blueprint: ProductionTreeBlueprintAssessment,
    opportunity: ManufacturingOpportunityRow
  ) -> Binding<ProductionTreeBlueprintAction> {
    Binding(
      get: {
        treeBlueprintActions[blueprint.blueprintTypeID]
          ?? blueprint.recommendation
      },
      set: {
        treeBlueprintActions[blueprint.blueprintTypeID] = $0
        treePreferredBlueprintSources.removeValue(
          forKey: blueprint.blueprintTypeID
        )
        reloadProductionTree(opportunity)
      }
    )
  }

  private func treeConcreteBlueprintSources(
    _ blueprint: ProductionTreeBlueprintAssessment,
    action: ProductionTreeBlueprintAction
  ) -> [ConcreteBlueprintSourceChoice] {
    let candidates: [ConcreteBlueprintSourceCandidate]
    switch action {
    case .useOwnedBPC, .useOwnedBPO:
      let kind: BlueprintCopyKind = action == .useOwnedBPC ? .copy : .original
      let exact = blueprint.exactLocationInstanceOptions.filter { $0.kind == kind }
      let other = blueprint.otherLocationInstanceOptions.filter { $0.kind == kind }
      candidates =
        (exact.map { ($0, true) } + other.map { ($0, false) })
        .map { option, isExact in
          ConcreteBlueprintSourceCandidate(
            source: action == .useOwnedBPC
              ? .ownedBPC(itemID: option.itemID)
              : .ownedBPO(itemID: option.itemID),
            locationName: option.locationName,
            isAtProductionLocation: isExact,
            runs: option.runs,
            materialEfficiency: option.materialEfficiency,
            timeEfficiency: option.timeEfficiency,
            priceText: nil
          )
        }
    case .buyContractBPC, .buyContractBPO:
      let kind: BlueprintCopyKind =
        action == .buyContractBPC ? .copy : .original
      candidates = blueprint.attributableContractOptions.filter {
        $0.kind == kind
      }.map { option in
        ConcreteBlueprintSourceCandidate(
          source: action == .buyContractBPC
            ? .contractBPC(recordID: option.recordID)
            : .contractBPO(recordID: option.recordID),
          locationName: option.locationName,
          isAtProductionLocation: true,
          runs: option.runs,
          materialEfficiency: option.materialEfficiency,
          timeEfficiency: option.timeEfficiency,
          priceText: formatISK(option.price)
        )
      }
    case .buyMarketBPO:
      candidates = blueprint.marketBPOOptions.map { option in
        ConcreteBlueprintSourceCandidate(
          source: .marketBPO(orderID: option.orderID),
          locationName: nil,
          isAtProductionLocation: true,
          runs: nil,
          materialEfficiency: 0,
          timeEfficiency: 0,
          priceText: formatISK(option.price)
        )
      }
    default:
      candidates = []
    }
    return ConcreteBlueprintSourceMenu.choices(candidates)
  }

  private func treeConcreteBlueprintSourceBinding(
    _ blueprint: ProductionTreeBlueprintAssessment,
    opportunity: ManufacturingOpportunityRow,
    choices: [ConcreteBlueprintSourceChoice]
  ) -> Binding<String?> {
    let blueprintTypeID = blueprint.blueprintTypeID
    return Binding(
      get: {
        ConcreteBlueprintSourceMenu.selectedChoiceID(
          preferredSources: treePreferredBlueprintSources[blueprintTypeID],
          in: choices
        )
      },
      set: { choiceID in
        treePreferredBlueprintSources[blueprintTypeID] =
          choices.first { $0.id == choiceID }?.sources ?? []
        reloadProductionTree(opportunity)
      }
    )
  }

  private func treeBlueprintCostBinding(
    blueprintTypeID: Int64
  ) -> Binding<String> {
    Binding(
      get: { treeBlueprintCostTexts[blueprintTypeID, default: ""] },
      set: { treeBlueprintCostTexts[blueprintTypeID] = $0 }
    )
  }

  private var parsedTreeBlueprintCosts: [Int64: Double] {
    treeBlueprintCostTexts.reduce(into: [:]) { result, entry in
      if let value = parseNonnegativeISK(entry.value) {
        result[entry.key] = value
      }
    }
  }

  private var blueprintInventories: [OwnedBlueprintInventory] {
    characters.compactMap { character in
      guard let data = character.blueprintSnapshot,
        let sourced = try? JSONDecoder().decode(
          Sourced<[OwnedBlueprintInstance]>.self,
          from: data
        )
      else { return nil }
      return OwnedBlueprintInventory(
        ownerID: character.characterID,
        ownerName: character.characterName,
        blueprints: sourced
      )
    }
  }

  private var activeStockAllocations: [StockAllocation] {
    preparedPlanReservations.allocations
  }

  private var activeBlueprintReservations: [BlueprintRunReservation] {
    preparedPlanReservations.blueprintReservations
  }

  private func productionTreeIcon(
    _ node: ManufacturingProductionTreeNode
  ) -> String {
    switch node.action {
    case .produce:
      node.activity == .reaction ? "atom" : "hammer.fill"
    case .buy: "cart.fill"
    case .useStock: "shippingbox.fill"
    }
  }

  private func productionTreeActionColor(_ action: PlanAction) -> Color {
    switch action {
    case .produce: DesignTokens.positive
    case .buy: DesignTokens.highlight
    case .useStock: DesignTokens.information
    }
  }

  private func productionTreeActionTitle(_ action: PlanAction) -> String {
    switch action {
    case .produce: "Build".localizedUI
    case .buy: "Buy".localizedUI
    case .useStock: "Stock".localizedUI
    }
  }

  private func productionTreeSubtitle(
    _ node: ManufacturingProductionTreeNode
  ) -> String {
    let activity: String =
      switch node.activity {
      case .copying: "Copying".localizedUI
      case .manufacturing: "Manufacturing".localizedUI
      case .reaction: "Reaction".localizedUI
      case .invention: "Invention".localizedUI
      case .materialResearch: "ME Research".localizedUI
      case .timeResearch: "TE Research".localizedUI
      case nil: productionTreeActionTitle(node.action)
      }
    return [activity, node.facilityName]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  private func savingsSuffix(_ value: Double?) -> String {
    guard let value, value.isFinite, value > 0 else { return "" }
    return AppLocalization.format(" · saves %@", formatISK(value))
  }

  private func stockCoverageColor(
    _ coverage: ProductionTreeStockCoverage
  ) -> Color {
    switch coverage {
    case .full: DesignTokens.positive
    case .partial: DesignTokens.caution
    case .none: DesignTokens.negative
    case .unavailable: DesignTokens.textSecondary
    }
  }

  private func stockCoverageHelp(
    _ node: ManufacturingProductionTreeNode
  ) -> String {
    guard let factual = node.factualWarehouseQuantity,
      let protected = node.protectedWarehouseQuantity,
      let reserved = node.reservedWarehouseQuantity,
      let usable = node.usableWarehouseQuantity
    else {
      return
        "No factual asset snapshot is available for the exact configured production, reaction and science locations."
    }
    return
      "Factual \(formatInteger(factual)) · protected target \(formatInteger(protected)) · reserved \(formatInteger(reserved)) · usable \(formatInteger(usable)) · total required \(formatInteger(node.totalRequiredQuantity))."
  }

  private func blueprintActionTitle(
    _ action: ProductionTreeBlueprintAction,
    assessment: ProductionTreeBlueprintAssessment? = nil
  ) -> String {
    switch action {
    case .useOwnedBPC:
      if let assessment,
        let count = assessment.exactLocationBPCRequiredCount
      {
        return AppLocalization.format(
          "Use %@ owned BPCs (%@ runs available)",
          formatInteger(count),
          formatInteger(assessment.exactLocationBPCRuns)
        )
      }
      return "Use owned BPC".localizedUI
    case .useOwnedBPO:
      if let assessment {
        return AppLocalization.format(
          "Use owned BPO (%@ available)",
          formatInteger(assessment.exactLocationBPOCount)
        )
      }
      return "Use owned BPO".localizedUI
    case .copyOwnedBPO: return "Copy owned BPO".localizedUI
    case .invent: return "Invent BPC".localizedUI
    case .manualExternalBPC: return "External / manual BPC".localizedUI
    case .buyContractBPC:
      if let assessment {
        return AppLocalization.format(
          "Buy %@ BPC contracts (%@ runs)",
          formatInteger(assessment.attributableBPCContractSelectionCount),
          assessment.attributableBPCContractRuns.map(formatInteger) ?? "—"
        )
      }
      return "Buy BPC contract".localizedUI
    case .buyContractBPO: return "Buy BPO contract".localizedUI
    case .buyMarketBPO: return "Buy market BPO".localizedUI
    case .buyLoyaltyStoreBPC: return "Buy Loyalty Store BPC".localizedUI
    case .useOwnedReactionFormula:
      return "Use owned reaction formula".localizedUI
    case .unavailable, .unresolved:
      if let assessment, assessment.otherLocationBPOCount > 0 {
        return "Owned BPO at another location".localizedUI
      }
      if let assessment, assessment.otherLocationBPCCount > 0 {
        return "Owned BPC at another location".localizedUI
      }
      return
        action == .unavailable
        ? "Unavailable".localizedUI : "Status unresolved".localizedUI
    }
  }

  private func blueprintRecommendationLabel(
    _ action: ProductionTreeBlueprintAction,
    assessment: ProductionTreeBlueprintAssessment? = nil
  ) -> String {
    AppLocalization.format(
      "Recommended: %@",
      blueprintActionTitle(action, assessment: assessment)
    )
  }

  private func blueprintActionColor(
    _ action: ProductionTreeBlueprintAction
  ) -> Color {
    switch action {
    case .useOwnedBPC, .useOwnedBPO, .useOwnedReactionFormula:
      DesignTokens.positive
    case .copyOwnedBPO, .invent:
      DesignTokens.information
    case .buyContractBPC, .buyContractBPO, .buyMarketBPO, .buyLoyaltyStoreBPC,
      .manualExternalBPC:
      DesignTokens.highlight
    case .unavailable:
      DesignTokens.negative
    case .unresolved:
      DesignTokens.caution
    }
  }

  private func blueprintAssessmentHelp(
    _ blueprint: ProductionTreeBlueprintAssessment,
    node: ManufacturingProductionTreeNode
  ) -> String {
    var parts = [
      blueprint.blueprintName,
      AppLocalization.format(
        "Required runs: %@",
        formatInteger(blueprint.requiredRuns)
      ),
      AppLocalization.format(
        "At production location: %@ BPC with %@ runs, %@ BPO, %@ unknown",
        formatInteger(blueprint.exactLocationBPCCount),
        formatInteger(blueprint.exactLocationBPCRuns),
        formatInteger(blueprint.exactLocationBPOCount),
        formatInteger(blueprint.exactLocationUnknownCount)
      ),
      AppLocalization.format(
        "At copying location: %@ BPO",
        formatInteger(blueprint.copyingLocationBPOCount)
      ),
      AppLocalization.format(
        "Usable invention sources: %@",
        formatInteger(blueprint.inventionSourceCount)
      ),
      AppLocalization.format(
        "At ME/TE research locations: %@ BPC, %@ BPO",
        formatInteger(blueprint.researchLocationBPCCount),
        formatInteger(blueprint.researchLocationBPOCount)
      ),
      AppLocalization.format(
        "Other locations: %@ (%@ BPC, %@ BPO)",
        formatInteger(blueprint.otherLocationCount),
        formatInteger(blueprint.otherLocationBPCCount),
        formatInteger(blueprint.otherLocationBPOCount)
      ),
      AppLocalization.format(
        "Indexed public-contract offers: %@",
        formatInteger(blueprint.indexedContractOfferCount)
      ),
    ]
    if !blueprint.productionLocationNames.isEmpty {
      parts.insert(
        AppLocalization.format(
          "Production location: %@",
          blueprint.productionLocationNames.joined(separator: ", ")
        ),
        at: 1
      )
    } else {
      parts.insert(
        "The exact production location could not be matched unambiguously; owned Blueprints are not offered as available."
          .localizedUI,
        at: 1
      )
    }
    if !blueprint.exactLocationBPCOwnerNames.isEmpty {
      parts.append(
        AppLocalization.format(
          "Owned BPC characters: %@",
          blueprint.exactLocationBPCOwnerNames.joined(separator: ", ")
        )
      )
    }
    if !blueprint.exactLocationBPOOwnerNames.isEmpty {
      parts.append(
        AppLocalization.format(
          "Owned BPO characters: %@",
          blueprint.exactLocationBPOOwnerNames.joined(separator: ", ")
        )
      )
    }
    let nonFreshExactStates = Set(
      blueprint.exactLocationBPCSourceStates
        + blueprint.exactLocationBPOSourceStates
    ).filter { $0 != .fresh }
    if !nonFreshExactStates.isEmpty {
      parts.append(
        AppLocalization.format(
          "Owned Blueprint evidence at the production location is retained with source state: %@. It remains selectable, but the inventory is not reported as complete.",
          nonFreshExactStates.map(\.rawValue).sorted().joined(separator: ", ")
        )
      )
    }
    if blueprint.otherLocationBPOCount > 0
      || blueprint.otherLocationBPCCount > 0
    {
      parts.append(
        "Owned Blueprints at other locations cannot start this job. Move them to the displayed production location, then refresh Blueprints and Assets."
          .localizedUI
      )
    }
    if let price = blueprint.lowestWholeContractPrice {
      parts.append(
        AppLocalization.format(
          "Lowest whole-contract price: %@",
          formatISK(price)
        )
      )
    }
    if let price = blueprint.attributableBPCContractPrice {
      parts.append(
        AppLocalization.format(
          "Attributable Main Hub BPC coverage: %@ · %@ contracts · %@ runs · common ME %@ · common TE %@",
          formatISK(price),
          formatInteger(blueprint.attributableBPCContractSelectionCount),
          blueprint.attributableBPCContractRuns.map(formatInteger) ?? "—",
          blueprint.attributableBPCContractME.map(formatInteger) ?? "—",
          blueprint.attributableBPCContractTE.map(formatInteger) ?? "—"
        )
      )
    }
    if let price = blueprint.attributableBPOContractPrice {
      parts.append(
        AppLocalization.format(
          "Attributable Main Hub BPO purchase: %@; enter the allocation for this plan separately.",
          formatISK(price)
        )
      )
    }
    if !blueprint.inventoryIsComplete {
      parts.append(
        "At least one blueprint or asset source is unavailable, stale or partial."
          .localizedUI
      )
    }
    parts.append(
      "A whole contract can contain bundles; its price is not silently converted into a per-run blueprint cost."
        .localizedUI
    )
    if node.activity == .reaction {
      parts.append(
        "Reaction formula availability is checked at the configured reaction location."
          .localizedUI
      )
    }
    return parts.joined(separator: "\n")
  }

  private var currentSettings: ManufacturingOpportunitySettings {
    ManufacturingOpportunitySettings(
      targetQuantity: 1,
      requestedRuns: nil,
      materialEfficiency: 0,
      timeEfficiency: 0
    )
  }

  private func startAnalysis() {
    analysisTask?.cancel()
    shoppingCopyStatus = nil
    analysisTask = Task { @MainActor in
      await runtime.analyzeManufacturingOpportunities(
        settings: currentSettings
      )
      analysisTask = nil
    }
  }

  private func toggleFavorite(_ typeID: Int64) {
    var values = favoriteIDs
    if values.contains(typeID) { values.remove(typeID) } else { values.insert(typeID) }
    let sorted = values.sorted()
    guard let data = try? JSONEncoder().encode(sorted),
      let encoded = String(data: data, encoding: .utf8)
    else { return }
    encodedFavoriteIDs = encoded
  }

  private func persistProductFamilies(
    _ values: Set<ManufacturingOpportunityProductFamily>
  ) {
    selectedProductFamilies = values
    encodedProductFamilies = encodeRawValues(values.map(\.rawValue))
  }

  private func persistProductionClasses(
    _ values: Set<ManufacturingOpportunityProductionClass>
  ) {
    selectedProductionClasses = values
    encodedProductionClasses = encodeRawValues(values.map(\.rawValue))
  }

  private func restoreCatalogFilters() {
    if let rawValues = decodeRawValues(encodedProductFamilies) {
      selectedProductFamilies = Set(
        rawValues.compactMap(ManufacturingOpportunityProductFamily.init)
      )
    }
    if let rawValues = decodeRawValues(encodedProductionClasses) {
      selectedProductionClasses = Set(
        rawValues.compactMap(ManufacturingOpportunityProductionClass.init)
      )
    }
    discardUnavailableStoredCatalogChoices()
  }

  private func encodeRawValues(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values.sorted()),
      let encoded = String(data: data, encoding: .utf8)
    else { return "" }
    return encoded
  }

  private func decodeRawValues(_ encoded: String) -> [String]? {
    guard !encoded.isEmpty, let data = encoded.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode([String].self, from: data)
  }

  private func discardUnavailableStoredCatalogChoices() {
    guard analysis != nil else { return }
    if !selectedCategory.isEmpty, !categories.contains(selectedCategory) {
      selectedCategory = ""
    }
    if !selectedGroup.isEmpty, !groups.contains(selectedGroup) {
      selectedGroup = ""
    }
  }

  private func selectAllFamilies() {
    persistProductFamilies(Set(ManufacturingOpportunityProductFamily.allCases))
  }

  private func selectAllCatalogFilters() {
    selectAllFamilies()
    persistProductionClasses(
      Set(
        ManufacturingOpportunityProductionClass.allCases
      )
    )
  }

  private func uncheckAllCatalogFilters() {
    persistProductFamilies([])
    persistProductionClasses([])
  }

  private func resetFilters() {
    searchText = ""
    selectedCategory = ""
    selectedGroup = ""
    favoritesOnly = false
    valueFilter = .all
    minimumAverageDailyDemand = 0
    maximumMaterialPurchaseISKText = ""
    selectAllCatalogFilters()
  }

  private func parseNonnegativeISK(_ text: String) -> Double? {
    let locale = AppLocalization.currentLanguage.locale
    let groupingSeparator = locale.groupingSeparator ?? ","
    let decimalSeparator = locale.decimalSeparator ?? "."
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\u{00A0}", with: "")
      .replacingOccurrences(of: groupingSeparator, with: "")
      .replacingOccurrences(of: decimalSeparator, with: ".")
    guard !normalized.isEmpty,
      let value = Double(normalized),
      value.isFinite,
      value >= 0
    else { return nil }
    return value
  }

  private func groupedISKBinding(_ source: Binding<String>) -> Binding<String> {
    Binding(
      get: { source.wrappedValue },
      set: { proposed in
        let decimalSeparator =
          AppLocalization.currentLanguage.locale.decimalSeparator ?? "."
        if proposed.isEmpty || proposed.hasSuffix(decimalSeparator) {
          source.wrappedValue = proposed
        } else if let value = parseNonnegativeISK(proposed) {
          source.wrappedValue = formatEditableISK(value)
        } else {
          source.wrappedValue = proposed
        }
      }
    )
  }

  private func normalizeStoredISKFields() {
    if let value = parseNonnegativeISK(blueprintCostPerRunText) {
      blueprintCostPerRunText = formatEditableISK(value)
    }
    if let value = parseNonnegativeISK(maximumMaterialPurchaseISKText) {
      maximumMaterialPurchaseISKText = formatEditableISK(value)
    }
  }

  private func copyShoppingList(
    _ procurement: ManufacturingOpportunityProcurementProjection
  ) {
    guard !procurement.multibuyText.isEmpty else { return }
    NSPasteboard.general.clearContents()
    guard
      NSPasteboard.general.setString(
        procurement.multibuyText,
        forType: .string
      )
    else {
      shoppingCopyStatus = "Copy failed"
      return
    }
    shoppingCopyStatus = "Multibuy copied"
  }

  private func candidateApplyingRequestedParameters(
    _ candidate: ManufacturingOpportunityCandidate
  ) -> ManufacturingOpportunityCandidate {
    let row = candidate.row
    let requestedRuns = requestedRunsByTypeID[row.productTypeID] ?? row.runs
    let requestedME = requestedMEValue(for: row)
    let requestedTE = requestedTEValue(for: row)
    guard
      requestedRuns != row.runs
        || row.supportsBlueprintEfficiency
          && (requestedME != row.materialEfficiency
            || requestedTE != row.timeEfficiency)
    else { return candidate }
    guard let snapshot = analysis,
      let projectedRow = ManufacturingOpportunityRunProjector.project(
        row,
        requestedRuns: requestedRuns,
        materialEfficiency: requestedME,
        timeEfficiency: requestedTE
      )
    else { return candidate }
    let procurement = ManufacturingOpportunityScenarioProjector.procurement(
      for: projectedRow,
      factualWarehouseQuantities: preparedWarehouse.factualQuantities,
      protectedQuantities: protectedQuantities,
      reservedQuantities: reservedQuantities
    )
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: projectedRow,
      procurement: procurement,
      configuration: snapshot.logisticsConfiguration,
      mainHub: snapshot.mainHub,
      warehouseIsAvailable: warehouseHasSnapshot,
      route: snapshot.saleRoute(for: projectedRow)
    )
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: projectedRow,
      sheet: costSheet,
      logistics: logistics,
      contract: contractContext
    )
    return ManufacturingOpportunityCandidate(
      row: projectedRow,
      costs: costs,
      purchaseCashRequirement: procurement.purchaseCashRequirement
    )
  }

  @MainActor
  private func prepareCandidates(
    trigger: ManufacturingOpportunityCandidateProjectionTrigger
  ) async {
    guard
      let snapshot = analysis,
      preparedWarehouseIdentity == warehouseIdentity,
      preparedPlanReservations.source == activePlanSnapshotPayloads
    else { return }
    let input = ManufacturingOpportunityCandidateProjectionInput(
      snapshot: snapshot,
      factualWarehouseQuantities: preparedWarehouse.factualQuantities,
      protectedQuantities: protectedQuantities,
      reservedQuantities: reservedQuantities,
      warehouseIsAvailable: warehouseHasSnapshot,
      favorites: favoriteIDs,
      productFamilies: selectedProductFamilies,
      productionClasses: selectedProductionClasses,
      searchText: searchText,
      selectedCategory: selectedCategory,
      selectedGroup: selectedGroup,
      favoritesOnly: favoritesOnly,
      valueFilter: valueFilter,
      costSheet: costSheet,
      sort: activeCandidateSort,
      contract: contractContext
    )
    let candidates = await ManufacturingOpportunityCandidateProjection.prepare(
      input: input
    )
    guard
      !Task.isCancelled,
      trigger == candidateProjectionTrigger
    else { return }
    let sortedCandidates = candidates.sorted { lhs, rhs in
      let projectedLHS = candidateApplyingRequestedParameters(lhs)
      let projectedRHS = candidateApplyingRequestedParameters(rhs)
      return activeCandidateSort.orderedBefore(
        lhs: projectedLHS.row,
        lhsCosts: projectedLHS.costs,
        rhs: projectedRHS.row,
        rhsCosts: projectedRHS.costs
      )
    }
    preparedCandidateProjection = PreparedManufacturingOpportunityCandidates(
      trigger: trigger,
      candidates: sortedCandidates
    )
  }

  @MainActor
  private func prepareWarehouse(identity: String) async {
    isPreparingWarehouse = true
    defer { isPreparingWarehouse = false }
    var payloads = characters.compactMap { character in
      character.assetSnapshot.map {
        StoredAssetSnapshotPayload(
          ownerID: character.characterID,
          ownerName: character.characterName,
          ownerKind: .character,
          encodedSnapshot: $0
        )
      }
    }
    if includeCorporationHangars {
      payloads.append(
        contentsOf: characters.compactMap { character in
          guard let corporationID = character.corporationID,
            let snapshot = character.corporationAssetSnapshot
          else { return nil }
          return StoredAssetSnapshotPayload(
            ownerID: corporationID,
            ownerName: character.corporationName
              ?? "Unknown corporation".localizedUI,
            ownerKind: .corporation,
            encodedSnapshot: snapshot
          )
        }
      )
    }
    let prepared = await runtime.prepareAssetWarehouse(
      identity: identity,
      payloads: payloads
    )
    guard !Task.isCancelled else { return }
    let productionWarehouse = await runtime.prepareProductionWarehouse(
      from: prepared
    )
    guard !Task.isCancelled else { return }
    preparedWarehouse = productionWarehouse
    preparedWarehouseIdentity = identity
  }

  private func detailMetric(_ title: LocalizedStringKey, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption).foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value).monospacedDigit()
    }
  }

  private var groupedIntegerFormat: IntegerFormatStyle<Int> {
    .number
      .locale(AppLocalization.currentLanguage.locale)
      .grouping(.automatic)
  }

  private func requestedRunsBinding(
    for row: ManufacturingOpportunityRow
  ) -> Binding<String> {
    Binding(
      get: {
        requestedRunTextsByTypeID[row.productTypeID]
          ?? String(requestedRunsByTypeID[row.productTypeID] ?? row.runs)
      },
      set: { proposed in
        guard proposed.isEmpty || proposed.allSatisfy(\.isNumber),
          proposed.count <= 7
        else { return }
        requestedRunTextsByTypeID[row.productTypeID] = proposed
        guard let runs = requestedRuns(from: proposed) else { return }
        requestedRunsByTypeID[row.productTypeID] = runs
      }
    )
  }

  private func requestedRuns(from text: String) -> Int? {
    guard let runs = Int(text),
      (1...ManufacturingOpportunitySettings.maximumRequestedRuns).contains(runs)
    else { return nil }
    return runs
  }

  private func normalizeRequestedRuns(for row: ManufacturingOpportunityRow) {
    let typeID = row.productTypeID
    guard let text = requestedRunTextsByTypeID[typeID],
      let runs = requestedRuns(from: text)
    else {
      requestedRunTextsByTypeID[typeID] = String(
        requestedRunsByTypeID[typeID] ?? row.runs
      )
      return
    }
    requestedRunsByTypeID[typeID] = runs
    requestedRunTextsByTypeID[typeID] = String(runs)
  }

  private func requestedMEValue(for row: ManufacturingOpportunityRow) -> Int {
    guard row.supportsBlueprintEfficiency else { return 0 }
    return requestedMEByTypeID[row.productTypeID]
      ?? defaultEfficiencyAssumption(for: row).materialEfficiency
  }

  private func requestedTEValue(for row: ManufacturingOpportunityRow) -> Int {
    guard row.supportsBlueprintEfficiency else { return 0 }
    return requestedTEByTypeID[row.productTypeID]
      ?? defaultEfficiencyAssumption(for: row).timeEfficiency
  }

  private func defaultEfficiencyAssumption(
    for row: ManufacturingOpportunityRow
  ) -> ManufacturingOpportunityEfficiencyAssumption {
    ManufacturingOpportunityEfficiencyDefaults.resolve(
      blueprintTypeID: row.blueprintTypeID,
      categoryName: row.categoryName,
      groupName: row.groupName,
      metaGroupID: row.metaGroupID,
      techLevel: row.techLevel,
      fallbackMaterialEfficiency: row.materialEfficiency,
      fallbackTimeEfficiency: row.timeEfficiency,
      loyaltyStoreBlueprintTypeIDs: Set(
        runtime.loyaltyStoreCatalog?.offeredTypeIDs ?? []
      )
    )
  }

  private func requestedEfficiencyText(
    for row: ManufacturingOpportunityRow,
    kind: OpportunityEfficiencyKind
  ) -> String {
    switch kind {
    case .material:
      requestedMETextsByTypeID[row.productTypeID]
        ?? String(requestedMEValue(for: row))
    case .time:
      requestedTETextsByTypeID[row.productTypeID]
        ?? String(requestedTEValue(for: row))
    }
  }

  private func requestedEfficiencyBinding(
    for row: ManufacturingOpportunityRow,
    kind: OpportunityEfficiencyKind
  ) -> Binding<String> {
    Binding(
      get: { requestedEfficiencyText(for: row, kind: kind) },
      set: { proposed in
        guard proposed.isEmpty || proposed.allSatisfy(\.isNumber),
          proposed.count <= 2
        else { return }
        switch kind {
        case .material:
          requestedMETextsByTypeID[row.productTypeID] = proposed
        case .time:
          requestedTETextsByTypeID[row.productTypeID] = proposed
        }
        guard
          let value = requestedEfficiency(
            from: proposed,
            kind: kind,
            row: row
          )
        else { return }
        switch kind {
        case .material:
          requestedMEByTypeID[row.productTypeID] = value
        case .time:
          requestedTEByTypeID[row.productTypeID] = value
        }
      }
    )
  }

  private func requestedEfficiency(
    from text: String,
    kind: OpportunityEfficiencyKind,
    row: ManufacturingOpportunityRow
  ) -> Int? {
    guard let value = Int(text) else { return nil }
    let range =
      kind == .material
      ? 0...10
      : 0...20
    return range.contains(value) ? value : nil
  }

  private func normalizeRequestedEfficiency(
    for row: ManufacturingOpportunityRow,
    kind: OpportunityEfficiencyKind
  ) {
    let typeID = row.productTypeID
    let text = requestedEfficiencyText(for: row, kind: kind)
    guard
      let value = requestedEfficiency(
        from: text,
        kind: kind,
        row: row
      )
    else {
      switch kind {
      case .material:
        requestedMETextsByTypeID[typeID] = String(requestedMEValue(for: row))
      case .time:
        requestedTETextsByTypeID[typeID] = String(requestedTEValue(for: row))
      }
      return
    }
    switch kind {
    case .material:
      requestedMEByTypeID[typeID] = value
      requestedMETextsByTypeID[typeID] = String(value)
    case .time:
      requestedTEByTypeID[typeID] = value
      requestedTETextsByTypeID[typeID] = String(value)
    }
  }

  private var minimumAverageDailyDemandBinding: Binding<Int> {
    Binding(
      get: { minimumAverageDailyDemand },
      set: {
        minimumAverageDailyDemand = min(1_000_000, max(0, $0))
      }
    )
  }

  private func formatInteger(_ value: Int) -> String {
    value.formatted(groupedIntegerFormat)
  }

  private func formatInteger(_ value: Int64) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .grouping(.automatic)
    )
  }

  private func formatEditableISK(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .grouping(.automatic)
        .precision(.fractionLength(0...2))
    )
  }

  private func formatISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(
      .currency(code: "ISK")
        .locale(AppLocalization.currentLanguage.locale)
        .grouping(.automatic)
        .precision(.fractionLength(0))
    )
  }

  private func formatSignedISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    let formatted = formatISK(abs(value))
    return value > 0 ? "+\(formatted)" : value < 0 ? "−\(formatted)" : formatted
  }

  private func formatPercent(_ value: Double?) -> String {
    value?.formatted(
      .percent
        .locale(AppLocalization.currentLanguage.locale)
        .grouping(.automatic)
        .precision(.fractionLength(1))
    ) ?? "—"
  }

  private func formatDays(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return AppLocalization.format(
      "%@ days",
      value.formatted(
        .number
          .locale(AppLocalization.currentLanguage.locale)
          .grouping(.automatic)
          .precision(.fractionLength(1))
      )
    )
  }

  private func formatDuration(_ seconds: Int64) -> String {
    guard seconds > 0 else { return "—" }
    return Duration.seconds(seconds).formatted(
      .units(allowed: [.days, .hours, .minutes], width: .abbreviated)
    )
  }

  private func formatUTCTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "HH:mm 'UTC'"
    return formatter.string(from: date)
  }

  private func productionScopeLabel(
    _ scope: ProductionWarehouseScope
  ) -> String {
    switch scope.locations.count {
    case 0:
      return "Production locations unresolved".localizedUI
    case 1:
      return scope.locations[0].structureName
    default:
      return String(
        format: "%lld production locations".localizedUI,
        Int64(scope.locations.count)
      )
    }
  }
}

enum ManufacturingOpportunityPageLayout {
  static func upperControlsHeight(
    viewportHeight proposedHeight: CGFloat,
    filtersAreExpanded: Bool,
    basisIsExpanded: Bool
  ) -> CGFloat {
    let viewportHeight =
      ManufacturingOpportunityTableLayout.clampedViewportLength(proposedHeight)
    let requestedHeight: CGFloat =
      105
      + (filtersAreExpanded ? 280 : 0)
      + (basisIsExpanded ? 120 : 0)
    return min(requestedHeight, min(420, viewportHeight * 0.48))
  }
}

enum ManufacturingOpportunityTableLayout {
  static func clampedViewportLength(_ proposedLength: CGFloat) -> CGFloat {
    guard proposedLength.isFinite, proposedLength > 0 else { return 0 }
    return proposedLength
  }
}

struct ManufacturingOpportunityWorkspaceLayout: Equatable {
  let viewportHeight: CGFloat
  let candidateHeight: CGFloat
  let dividerHeight: CGFloat
  let workbenchHeight: CGFloat

  init(viewportHeight proposedHeight: CGFloat) {
    viewportHeight =
      ManufacturingOpportunityTableLayout.clampedViewportLength(proposedHeight)
    dividerHeight = viewportHeight > 0 ? 1 : 0
    let usableHeight = max(0, viewportHeight - dividerHeight)
    if usableHeight >= 520 {
      workbenchHeight = min(270, max(220, usableHeight * 0.35))
    } else {
      workbenchHeight = usableHeight * 0.4
    }
    candidateHeight = max(0, usableHeight - workbenchHeight)
  }
}

struct ManufacturingOpportunityWorkbenchLayout: Equatable {
  let viewportWidth: CGFloat
  let viewportHeight: CGFloat
  let columnWidth: CGFloat
  let dividerWidth: CGFloat

  init(viewportSize proposedSize: CGSize) {
    viewportWidth =
      ManufacturingOpportunityTableLayout.clampedViewportLength(
        proposedSize.width
      )
    viewportHeight =
      ManufacturingOpportunityTableLayout.clampedViewportLength(
        proposedSize.height
      )
    dividerWidth = viewportWidth > 0 ? 1 : 0
    columnWidth = max(0, (viewportWidth - dividerWidth) / 2)
  }
}

private struct OpportunityExplanationButton: View {
  let title: LocalizedStringKey
  let explanation: LocalizedStringKey
  let systemImage: String
  let color: Color
  let font: Font

  @State private var isExplanationPresented = false

  var body: some View {
    Button {
      isExplanationPresented.toggle()
    } label: {
      HStack(spacing: 4) {
        Text(title)
        Spacer(minLength: DesignTokens.spacingSM)
        Image(systemName: systemImage)
          .accessibilityHidden(true)
      }
      .font(font)
      .foregroundStyle(color)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Click for details")
    .popover(
      isPresented: $isExplanationPresented,
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .bottom
    ) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack {
          Text(title)
            .font(.headline)
          Spacer()
          Button {
            isExplanationPresented = false
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close explanation")
        }
        Text(explanation)
          .foregroundStyle(DesignTokens.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .padding(DesignTokens.spacingMD)
      .frame(width: 480)
    }
    .accessibilityLabel(Text(title))
    .accessibilityHint("Shows explanatory details.")
  }
}

private struct StoredPlanSnapshotPayload: Hashable, Sendable {
  let id: UUID
  let encodedSnapshot: Data
}

private struct PreparedPlanReservations: Sendable {
  let source: [StoredPlanSnapshotPayload]
  let allocations: [StockAllocation]
  let blueprintReservations: [BlueprintRunReservation]
  let quantities: [Int64: Int64]
  let invalidSnapshotCount: Int

  static let empty = PreparedPlanReservations(
    source: [],
    allocations: [],
    blueprintReservations: [],
    quantities: [:],
    invalidSnapshotCount: 0
  )
}

private enum StoredPlanReservationProjection {
  static func prepare(
    payloads: [StoredPlanSnapshotPayload]
  ) async -> PreparedPlanReservations {
    await Task.detached(priority: .userInitiated) {
      var allocations: [StockAllocation] = []
      var blueprintReservations: [BlueprintRunReservation] = []
      var invalidSnapshotCount = 0
      for payload in payloads {
        guard
          let plan = try? JSONDecoder().decode(
            IndustryPlanSnapshot.self,
            from: payload.encodedSnapshot
          )
        else {
          invalidSnapshotCount += 1
          continue
        }
        allocations.append(
          contentsOf: plan.stockAllocations.filter {
            $0.source.kind == .warehouse || $0.source.kind == .assetSnapshot
          }
        )
        blueprintReservations.append(
          contentsOf: plan.blueprintSupplyPlans?.flatMap(\.reservations) ?? []
        )
      }
      let quantities = allocations.reduce(into: [Int64: Int64]()) {
        result, allocation in
        result[allocation.typeID] = AssetWarehouse.saturatedAdd(
          result[allocation.typeID, default: 0],
          max(0, allocation.quantity)
        )
      }
      return PreparedPlanReservations(
        source: payloads,
        allocations: allocations,
        blueprintReservations: blueprintReservations,
        quantities: quantities,
        invalidSnapshotCount: invalidSnapshotCount
      )
    }.value
  }
}

private struct ManufacturingOpportunityCandidateProjectionTrigger: Hashable {
  let snapshotID: UUID?
  let requestedWarehouseIdentity: String
  let preparedWarehouseIdentity: String?
  let reservationRevision: UUID
  let stockTargetIdentity: [String]
  let searchText: String
  let selectedCategory: String
  let selectedGroup: String
  let favoritesOnly: Bool
  let favoriteIDs: [Int64]
  let productFamilies: [String]
  let productionClasses: [String]
  let valueFilter: String
  let includesCorporationHangars: Bool
  let includesBlueprintCost: Bool
  let blueprintCostText: String
  let sortColumn: String
  let sortDirection: String
  let contractReferenceID: UUID?
  let contractFeeRate: Double?
}

private struct ManufacturingOpportunityCandidateProjectionInput: Sendable {
  let snapshot: ManufacturingOpportunitySnapshot
  let factualWarehouseQuantities: [Int64: Int64]
  let protectedQuantities: [Int64: Int64]
  let reservedQuantities: [Int64: Int64]
  let warehouseIsAvailable: Bool
  let favorites: Set<Int64>
  let productFamilies: Set<ManufacturingOpportunityProductFamily>
  let productionClasses: Set<ManufacturingOpportunityProductionClass>
  let searchText: String
  let selectedCategory: String
  let selectedGroup: String
  let favoritesOnly: Bool
  let valueFilter: ManufacturingOpportunityValueFilter
  let costSheet: ManufacturingOpportunityCostSheet
  let sort: ManufacturingOpportunitySortDescriptor
  let contract: ManufacturingOpportunityContractContext
}

private struct PreparedManufacturingOpportunityCandidates {
  let trigger: ManufacturingOpportunityCandidateProjectionTrigger
  let candidates: [ManufacturingOpportunityCandidate]
}

private enum ManufacturingOpportunityCandidateProjection {
  static func prepare(
    input: ManufacturingOpportunityCandidateProjectionInput
  ) async -> [ManufacturingOpportunityCandidate] {
    let task: Task<[ManufacturingOpportunityCandidate], Never> = Task.detached(
      priority: .userInitiated
    ) {
      let searchQuery = ManufacturingOpportunitySearchPolicy.effectiveQuery(
        input.searchText
      )
      var candidates: [ManufacturingOpportunityCandidate] = []
      candidates.reserveCapacity(input.snapshot.rows.count)
      for row in input.snapshot.rows {
        guard !Task.isCancelled else { return [] }
        guard
          ManufacturingOpportunitySearchPolicy.accepts(
            effectiveQuery: searchQuery,
            productName: row.productName,
            groupName: row.groupName,
            categoryName: row.categoryName
          ),
          input.selectedCategory.isEmpty
            || row.categoryName == input.selectedCategory,
          input.selectedGroup.isEmpty || row.groupName == input.selectedGroup,
          !input.favoritesOnly || input.favorites.contains(row.productTypeID),
          ManufacturingOpportunityCatalogFilter.accepts(
            activityKind: row.effectiveActivityKind,
            categoryName: row.categoryName,
            groupName: row.groupName,
            metaGroupID: row.metaGroupID,
            techLevel: row.techLevel,
            productFamilies: input.productFamilies,
            productionClasses: input.productionClasses
          )
        else { continue }
        let procurement = ManufacturingOpportunityScenarioProjector.procurement(
          for: row,
          factualWarehouseQuantities: input.factualWarehouseQuantities,
          protectedQuantities: input.protectedQuantities,
          reservedQuantities: input.reservedQuantities
        )
        let logistics = ManufacturingOpportunityScenarioProjector.logistics(
          for: row,
          procurement: procurement,
          configuration: input.snapshot.logisticsConfiguration,
          mainHub: input.snapshot.mainHub,
          warehouseIsAvailable: input.warehouseIsAvailable,
          route: input.snapshot.saleRoute(for: row)
        )
        let costs = ManufacturingOpportunityScenarioProjector.costs(
          for: row,
          sheet: input.costSheet,
          logistics: logistics,
          contract: input.contract
        )
        guard input.valueFilter.accepts(costs) else { continue }
        candidates.append(
          ManufacturingOpportunityCandidate(
            row: row,
            costs: costs,
            purchaseCashRequirement: procurement.purchaseCashRequirement
          )
        )
      }
      return candidates.sorted {
        input.sort.orderedBefore(
          lhs: $0.row,
          lhsCosts: $0.costs,
          rhs: $1.row,
          rhsCosts: $1.costs
        )
      }
    }
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

}

private struct ManufacturingOpportunityCandidate: Identifiable, Sendable {
  var id: Int64 { row.id }
  let row: ManufacturingOpportunityRow
  let costs: ManufacturingOpportunityCostProjection
  let purchaseCashRequirement: Double?
}

private enum OpportunityEfficiencyKind {
  case material
  case time
}

private enum OpportunityLowerTab: String, CaseIterable, Identifiable {
  case mainHub
  case shopping
  case costs

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .mainHub: "Main Hub"
    case .shopping: "Shopping List"
    case .costs: "Cost details"
    }
  }
}

extension ManufacturingOpportunityProductFamily {
  var title: LocalizedStringKey {
    switch self {
    case .ships: "Ships"
    case .modules: "Modules"
    case .charges: "Charges"
    case .drones: "Drones"
    case .rigs: "Rigs"
    case .structures: "Structures"
    case .reactions: "Reactions"
    case .boosters: "Boosters"
    case .implants: "Implants"
    case .components: "Components"
    case .deployables: "Deployables"
    case .other: "Other"
    }
  }
}

extension ManufacturingOpportunityProductionClass {
  var title: LocalizedStringKey {
    switch self {
    case .techI: "Tech I"
    case .techII: "Tech II"
    case .techIII: "Tech III"
    case .faction: "Faction"
    case .storyline: "Storyline"
    case .other: "Other / unclassified"
    }
  }
}

extension ProductionTreeBlueprintAction {
  fileprivate var requiresExplicitCost: Bool {
    switch self {
    case .useOwnedBPC, .useOwnedBPO, .copyOwnedBPO, .invent,
      .manualExternalBPC,
      .buyContractBPO, .buyMarketBPO, .buyLoyaltyStoreBPC:
      true
    case .buyContractBPC, .useOwnedReactionFormula, .unavailable, .unresolved:
      false
    }
  }
}

private enum ManufacturingOpportunityValueFilter: String, CaseIterable,
  Identifiable, Sendable
{
  case all, positive, negative, unavailable
  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "All values"
    case .positive: "Positive"
    case .negative: "Negative"
    case .unavailable: "Unavailable"
    }
  }
  func accepts(_ costs: ManufacturingOpportunityCostProjection) -> Bool {
    switch self {
    case .all: true
    case .positive: costs.profit.map { $0 > 0 } == true
    case .negative: costs.profit.map { $0 < 0 } == true
    case .unavailable: costs.profit == nil
    }
  }
}

private enum MarketOrderSortColumn: Hashable, Sendable {
  case region
  case quantity
  case price
  case location
  case range
  case minimumVolume
  case expires
  case modified
}

/// Presents Main-Hub wording for another opportunity hub (P5). Only texts
/// about the sale market are adapted; material purchases stay at the Main Hub.
enum OpportunityHubText {
  static let saleWarningCodes: Set<String> = [
    "manufacturing-opportunity.product-sell-order-unavailable",
    "manufacturing-opportunity.observed-demand-lower-bound",
    "manufacturing-opportunity.observed-demand-needs-baseline",
  ]

  static func adapt(_ text: String, for role: OpportunityHubRole) -> String {
    let replacement: (spaced: String, hyphenated: String)
    switch role {
    case .main: return text
    case .home: replacement = ("Home Hub", "Home-Hub")
    case .coalition: replacement = ("Coalition Hub", "Coalition-Hub")
    }
    return
      text
      .replacingOccurrences(of: "Main Hub", with: replacement.spaced)
      .replacingOccurrences(of: "Main-Hub", with: replacement.hyphenated)
  }
}
