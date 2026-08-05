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
              Text(verbatim: item.name)
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
    clearLabel: LocalizedStringKey,
    clear: @escaping () -> Void
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      EVEEntityText(value: title)
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
  @EnvironmentObject private var runtime: RuntimeState
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]
  @Query(filter: #Predicate<StoredPlan> { $0.isActive })
  private var activePlans: [StoredPlan]

  @AppStorage(
    "market-opportunities.target-quantity",
    store: AppDefaults.store
  )
  private var targetQuantity = 1
  @AppStorage("market-opportunities.me", store: AppDefaults.store)
  private var materialEfficiency = 10
  @AppStorage("market-opportunities.te", store: AppDefaults.store)
  private var timeEfficiency = 20
  @AppStorage(
    "market-opportunities.favorite-type-ids",
    store: AppDefaults.store
  )
  private var encodedFavoriteIDs = "[]"
  @State private var selectedProductFamilies = Set(
    ManufacturingOpportunityProductFamily.allCases
  )
  @State private var includesPersonal = true
  @State private var includesCorporation = true
  @State private var includesNotOwned = true
  @State private var includesUnknownOwnership = true
  @State private var includesBPO = true
  @State private var includesBPC = true
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
  @State private var topTab = OpportunityTopTab.profile
  @State private var lowerTab = OpportunityLowerTab.shopping
  @State private var searchText = ""
  @State private var selectedCategory = ""
  @State private var selectedGroup = ""
  @State private var favoritesOnly = false
  @State private var valueFilter = ManufacturingOpportunityValueFilter.all
  @State private var tableSort: ManufacturingOpportunitySortDescriptor?
  @State private var selectedTypeID: Int64?
  @State private var analysisTask: Task<Void, Never>?
  @State private var preparedWarehouse = PreparedAssetWarehouse.empty
  @State private var preparedWarehouseIdentity: String?
  @State private var isPreparingWarehouse = false
  @State private var preparedPlanReservations = PreparedPlanReservations.empty
  @State private var preparedPlanReservationRevision = UUID()
  @State private var preparedCandidateProjection: PreparedManufacturingOpportunityCandidates?
  @State private var shoppingCopyStatus: String?
  @State private var expandedOpportunityTypeID: Int64?
  @State private var productionTree: ManufacturingProductionTreeSnapshot?
  @State private var productionTreeQuantity = 1
  @State private var productionTreeError: String?
  @State private var isLoadingProductionTree = false
  @State private var productionTreeTask: Task<Void, Never>?
  @State private var expandedProductionNodeIDs = Set<UUID>()
  @State private var treeProcurementPreferences: [Int64: MaterialProcurementPreference] = [:]
  @State private var treeBlueprintActions: [Int64: ProductionTreeBlueprintAction] = [:]

  var body: some View {
    let planPayloads = activePlanSnapshotPayloads
    let planReservationsAreCurrent =
      preparedPlanReservations.source == planPayloads
    let candidateTrigger = candidateProjectionTrigger
    let preparedCandidates =
      preparedCandidateProjection?.trigger == candidateTrigger
      ? preparedCandidateProjection?.candidates : nil
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      header
      filterDeck
      if let error = runtime.manufacturingOpportunityError {
        Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
      if runtime.isAnalyzingManufacturingOpportunities { scanProgress }
      if let snapshot = runtime.manufacturingOpportunityAnalysis {
        basis(snapshot)
      }
      if let snapshotError = runtime.manufacturingOpportunitySnapshotError {
        Label(
          snapshotError.localizedUI,
          systemImage: "externaldrive.badge.exclamationmark"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
      if planReservationsAreCurrent {
        if preparedPlanReservations.invalidSnapshotCount > 0 {
          Label(
            "One or more active production plans could not be read. Their Warehouse reservations remain unavailable.",
            systemImage: "externaldrive.badge.exclamationmark"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        calculatorWorkspace(
          runtime.manufacturingOpportunityAnalysis,
          candidates: preparedCandidates
        )
      } else {
        ProgressView("Preparing active plan reservations…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    .onAppear {
      materialEfficiency = min(10, max(0, materialEfficiency))
      timeEfficiency = min(20, max(0, timeEfficiency))
    }
    .task {
      await runtime.loadManufacturingOpportunityAnalysis()
      await runtime.loadManufacturingOpportunityDemand()
      runtime.prepareMainHubMarketAutomation()
    }
    .onChange(of: runtime.manufacturingOpportunityAnalysis?.id) { _, _ in
      selectedTypeID = nil
      shoppingCopyStatus = nil
      collapseProductionTree()
    }
    .onDisappear {
      analysisTask?.cancel()
      productionTreeTask?.cancel()
    }
  }

  private func calculatorWorkspace(
    _ snapshot: ManufacturingOpportunitySnapshot?,
    candidates: [ManufacturingOpportunityCandidate]?
  ) -> some View {
    VSplitView {
      Group {
        if let snapshot, let candidates {
          candidatePane(snapshot, candidates: candidates)
        } else if let snapshot {
          preparingCandidatePane(snapshot)
        } else {
          emptyCandidatePane
        }
      }
      .frame(minHeight: 300)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      workbench(snapshot)
        .frame(minHeight: 220, idealHeight: 270)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        "No Main Hub scan yet",
        systemImage: "chart.line.uptrend.xyaxis",
        description: Text(
          "Start the explicit scan to compare published manufacturing recipes against one current Main Hub order-book snapshot."
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
        Text("Industry Calculator · Main Hub")
          .font(.title2.bold())
        Text(
          "Main Hub market · Assigned production locations · Warehouse allocation · Shopping"
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
      Picker("Configuration", selection: $topTab) {
        ForEach(OpportunityTopTab.allCases) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 620)
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.top, DesignTokens.spacingSM)

      Rectangle()
        .fill(DesignTokens.accent)
        .frame(height: 2)
        .padding(.top, DesignTokens.spacingSM)

      Group {
        switch topTab {
        case .profile: profileFilters
        case .costSheet: costSheetControls
        case .advanced: advancedFilters
        }
      }
      .padding(DesignTokens.spacingSM)

      Divider()
      searchToolbar
        .padding(DesignTokens.spacingSM)
    }
    .background(DesignTokens.panel)
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border)
    }
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private var profileFilters: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
        filterColumn("Ownership") {
          compactToggle("Personal", isOn: $includesPersonal)
          compactToggle("Corporation", isOn: $includesCorporation)
          compactToggle("Not owned", isOn: $includesNotOwned)
          compactToggle("Unknown", isOn: $includesUnknownOwnership)
          disabledToggle("Loyalty Store")
          disabledToggle("App Store")
        }
        filterColumn("Blueprints") {
          compactToggle("BPOs", isOn: $includesBPO)
          compactToggle("BPCs", isOn: $includesBPC)
          compactToggle("Favorites", isOn: $favoritesOnly)
          compactToggle(
            "Corporation hangars",
            isOn: $includeCorporationHangars
          )
        }
        filterColumn("Products") {
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
        filterColumn("Scenario") {
          LabeledContent("Quantity") {
            TextField("Quantity", value: $targetQuantity, format: .number)
              .textFieldStyle(.roundedBorder)
              .frame(width: 90)
          }
          LabeledContent("ME") {
            Stepper(value: $materialEfficiency, in: 0...10) {
              Text(materialEfficiency.formatted()).monospacedDigit()
            }
            .frame(width: 105)
          }
          LabeledContent("TE") {
            Stepper(value: $timeEfficiency, in: 0...20) {
              Text(timeEfficiency.formatted()).monospacedDigit()
            }
            .frame(width: 105)
          }
          if settingsChanged {
            Label("Update required", systemImage: "arrow.triangle.2.circlepath")
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
          }
        }
      }
    }
  }

  private var costSheetControls: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
      filterColumn("Automatic calculation") {
        Label("Material replacement value", systemImage: "checkmark.circle.fill")
        Label("Installation cost", systemImage: "checkmark.circle.fill")
        Label("Sales tax and broker fee", systemImage: "checkmark.circle.fill")
        Label("Profile logistics", systemImage: "checkmark.circle.fill")
        Text(
          "Warehouse stock is valued at the Main Hub replacement price. Only the missing quantity is assigned to purchasing and inbound logistics."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .frame(maxWidth: 340, alignment: .leading)
      }
      filterColumn("Blueprint allocation") {
        compactToggle("Include blueprint allocation", isOn: $costIncludesBlueprint)
        TextField("ISK per run", text: $blueprintCostPerRunText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 150)
          .disabled(!costIncludesBlueprint)
        if costIncludesBlueprint, parsedBlueprintCost == nil {
          Label("Enter a valid ISK amount", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
        Label("Main Hub prices", systemImage: "building.columns")
        Label("Assigned production locations", systemImage: "hammer.fill")
        Text("Unavailable profile inputs remain unavailable, never zero.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var advancedFilters: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
      filterColumn("Catalog") {
        Picker("Category", selection: $selectedCategory) {
          Text("All categories").tag("")
          ForEach(categories, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 210)
        Picker("Group", selection: $selectedGroup) {
          Text("All groups").tag("")
          ForEach(groups, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 210)
      }
      filterColumn("Result") {
        Picker("Value", selection: $valueFilter) {
          ForEach(ManufacturingOpportunityValueFilter.allCases) {
            Text($0.title).tag($0)
          }
        }
        .frame(width: 210)
        Label("Sort via a table heading", systemImage: "arrow.up.arrow.down")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      filterColumn("Tech level") {
        disabledFilterLine("Tech I · Tech II · Tech III")
        disabledFilterLine("Faction · Storyline · Misc")
      }
      filterColumn("Size") {
        disabledFilterLine("S · M · L · XL · U")
        Text("Requires additional SDE metadata")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
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
      Button("Select all") { selectAllFamilies() }
        .buttonStyle(.bordered)
      Button("Uncheck all") { selectedProductFamilies = [] }
        .buttonStyle(.bordered)
      Spacer()
    }
  }

  private var scanProgress: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      if let fraction = runtime.manufacturingOpportunityProgress.fractionCompleted {
        ProgressView(value: fraction)
      } else {
        ProgressView()
      }
      HStack {
        Text("Loading the configured Main Hub order book")
        Spacer()
        if runtime.manufacturingOpportunityProgress.totalPages > 0 {
          Text(
            verbatim:
              "\(runtime.manufacturingOpportunityProgress.completedPages) / \(runtime.manufacturingOpportunityProgress.totalPages) pages"
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
      HStack {
        Label(snapshot.mainHub.name, systemImage: "building.columns")
        Text("→")
        Label {
          Text(verbatim: productionScopeLabel(snapshot.productionWarehouseScope))
        } icon: {
          Image(systemName: "hammer.fill")
        }
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
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 190, maximum: 320))],
        alignment: .leading,
        spacing: DesignTokens.spacingXS
      ) {
        Label(
          "Market-listed build candidates: \(snapshot.coverage.candidateCount)",
          systemImage: "shippingbox.and.arrow.backward"
        )
        Text(
          "Complete manufacturing definitions: \(snapshot.coverage.completeManufacturingDefinitionCount)"
        )
        Text(
          "With sell orders: \(snapshot.coverage.candidatesWithSellOrders)"
        )
        Text(
          "With buy orders: \(snapshot.coverage.candidatesWithBuyOrders)"
        )
        Text(
          "Main Hub active order types: \(snapshot.coverage.mainHubActiveOrderTypeCount)"
        )
        if let demand = snapshot.demand {
          Text("Demand observations today: \(demand.sampleCount)")
        } else {
          Text("Demand observations today: 0")
        }
      }
      .monospacedDigit()
      Text(
        "A candidate is a complete manufacturing product with at least one active buy or sell order at the exact Main Hub. Active orders are not completed sales."
      )
      .foregroundStyle(DesignTokens.textSecondary)
      if let demand = snapshot.demand, demand.sampleCount >= 2 {
        Text(
          "Demand today is the observed lower bound between \(formatUTCTime(demand.firstObservedAt)) and \(formatUTCTime(demand.lastObservedAt)). Only decreases in orders observed in consecutive snapshots are counted."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Text(
          "A second scan on the same UTC day is required before today's observed demand is available."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      if !snapshot.productionWarehouseScope.unresolvedActivities.isEmpty {
        Label(
          "Some production activities do not have an exact assigned asset location and are excluded from Warehouse allocation.",
          systemImage: "shippingbox.and.arrow.backward.fill"
        )
        .foregroundStyle(DesignTokens.caution)
      }
      if let demandError = runtime.manufacturingOpportunityDemandError {
        Label(demandError.localizedUI, systemImage: "externaldrive.badge.exclamationmark")
          .foregroundStyle(DesignTokens.caution)
      }
      ForEach(snapshot.warnings) { warning in
        Label(
          LocalizedStringKey(warning.message),
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
        Text(verbatim: "\(candidates.count) / \(snapshot.rows.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, 6)
      .background(DesignTokens.elevated)
      .overlay(alignment: .bottom) {
        Rectangle().fill(DesignTokens.accent).frame(height: 2)
      }
      ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            ForEach(candidates) { candidate in
              opportunityRow(
                candidate.row,
                costs: candidate.costs,
                isFavorite: favorites.contains(candidate.row.productTypeID)
              )
            }
          } header: {
            opportunityHeader
          }
        }
      }
      .defaultScrollAnchor(.topLeading)
      .accessibilityIdentifier("market-opportunities.table")
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
        Text(verbatim: "— / \(snapshot.rows.count)")
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
      headerCell("", width: 28)
      headerCell("", width: 32)
      sortableHeaderCell("Task", column: .task, width: 58, alignment: .leading)
      sortableHeaderCell("Item", column: .item, width: 240, alignment: .leading)
      sortableHeaderCell("Demand today", column: .demand, width: 100)
      sortableHeaderCell("Quantity", column: .quantity, width: 80)
      sortableHeaderCell("Runs", column: .runs, width: 55)
      sortableHeaderCell("Duration", column: .duration, width: 90)
      sortableHeaderCell("Cost", column: .cost, width: 110)
      sortableHeaderCell("Revenue", column: .revenue, width: 110)
      sortableHeaderCell("Sales tax", column: .salesTax, width: 95)
      sortableHeaderCell("Broker fee", column: .brokerFee, width: 95)
      sortableHeaderCell("Profit", column: .profit, width: 120)
      sortableHeaderCell("ROI", column: .roi, width: 75)
      sortableHeaderCell("ISK / h", column: .iskPerHour, width: 105)
      sortableHeaderCell("ISK / m³", column: .iskPerCubicMeter, width: 105)
      sortableHeaderCell("ME", column: .materialEfficiency, width: 55)
      sortableHeaderCell("TE", column: .timeEfficiency, width: 55)
      sortableHeaderCell("Group", column: .group, width: 180, alignment: .leading)
      sortableHeaderCell("Category", column: .category, width: 150, alignment: .leading)
    }
    .background(DesignTokens.panel)
  }

  private func opportunityRow(
    _ row: ManufacturingOpportunityRow,
    costs: ManufacturingOpportunityCostProjection,
    isFavorite: Bool
  ) -> some View {
    let isExpanded = expandedOpportunityTypeID == row.productTypeID
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Button {
          toggleProductionTree(row)
        } label: {
          Image(systemName: "chevron.right")
            .font(.caption2)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(width: 28, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          isExpanded ? "Collapse production tree" : "Expand production tree"
        )
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
        textCell("Build", width: 58, alignment: .leading)
        Button {
          toggleProductionTree(row)
        } label: {
          Text(verbatim: row.productName)
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .help(row.productName)
            .frame(width: 240, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.textPrimary)
        .accessibilityLabel(
          isExpanded ? "Collapse production tree" : "Expand production tree"
        )
        textCell(row.observedDailyDemand?.formatted() ?? "—", width: 100)
        textCell(row.producedQuantity.formatted(), width: 80)
        textCell(row.runs.formatted(), width: 55)
        textCell(formatDuration(row.durationSeconds), width: 90)
        textCell(formatISK(costs.totalCost), width: 110)
        textCell(formatISK(costs.grossRevenue), width: 110)
        textCell(formatISK(costs.salesTax), width: 95)
        textCell(formatISK(costs.brokerFee), width: 95)
        textCell(
          formatSignedISK(costs.profit),
          width: 120,
          color: costs.profit.map {
            $0 >= 0 ? DesignTokens.positive : DesignTokens.negative
          } ?? DesignTokens.caution
        )
        textCell(formatPercent(costs.returnOnInvestment), width: 75)
        textCell(formatISK(costs.iskPerHour), width: 105)
        textCell(formatISK(costs.iskPerCubicMeter), width: 105)
        textCell("\(row.materialEfficiency.formatted()) %", width: 55)
        textCell("\(row.timeEfficiency.formatted()) %", width: 55)
        textCell(row.groupName, width: 180, alignment: .leading)
        textCell(row.categoryName, width: 150, alignment: .leading)
      }
      .padding(.vertical, 5)
      .background(
        selectedTypeID == row.productTypeID
          ? DesignTokens.accentSoft : Color.clear
      )
      .contentShape(Rectangle())
      .onTapGesture { selectedTypeID = row.productTypeID }
      if isExpanded {
        productionTreePane(row)
      }
    }
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
    .help("Click to sort ascending; click again to sort descending.")
    .accessibilityLabel(title)
    .accessibilityValue(
      tableSort?.column == column
        ? (tableSort?.direction == .ascending ? "Ascending" : "Descending")
        : "Not sorted"
    )
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

  private func productionTreePane(
    _ opportunity: ManufacturingOpportunityRow
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: DesignTokens.spacingSM) {
        Label("Production tree", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.caption.bold())
        LabeledContent("Target quantity") {
          TextField(
            "Quantity",
            value: $productionTreeQuantity,
            format: .number
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 100)
          .onSubmit { reloadProductionTree(opportunity) }
        }
        Button("Recalculate") {
          reloadProductionTree(opportunity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
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
          "Blueprint source selections are recorded in this open tree. Contract bundle prices and copy or invention costs remain excluded until they can be attributed without guessing.",
          systemImage: "doc.on.doc"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.horizontal, DesignTokens.spacingSM)
        .padding(.bottom, DesignTokens.spacingSM)
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
            Button {
              if !node.children.isEmpty { toggleProductionNode(node.id) }
            } label: {
              VStack(alignment: .leading, spacing: 1) {
                EVEEntityText(value: node.name, lineLimit: 1)
                Text(verbatim: productionTreeSubtitle(node))
                  .font(.caption2)
                  .foregroundStyle(DesignTokens.textSecondary)
                  .lineLimit(1)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
              node: node
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
      text = "\(usable.formatted()) / \(node.totalRequiredQuantity.formatted())"
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
    node: ManufacturingProductionTreeNode
  ) -> some View {
    HStack(spacing: 4) {
      Picker(
        "Blueprint source",
        selection: treeBlueprintBinding(blueprint)
      ) {
        ForEach(
          blueprint.availableActions.sorted { $0.rawValue < $1.rawValue },
          id: \.self
        ) { action in
          Text(blueprintActionTitle(action)).tag(action)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .frame(maxWidth: 225, alignment: .leading)
      Text(verbatim: blueprintRecommendationLabel(blueprint.recommendation))
        .font(.caption2.bold())
        .foregroundStyle(blueprintActionColor(blueprint.recommendation))
        .lineLimit(1)
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
    Text(verbatim: dashForZero && value == 0 ? "—" : value.formatted())
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
      let columnWidth = max(320, (geometry.size.width - 8) / 2)
      HSplitView {
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
          minWidth: 320,
          idealWidth: columnWidth,
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: .topLeading
        )
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
          minWidth: 320,
          idealWidth: columnWidth,
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: .topLeading
        )
        .background(DesignTokens.canvas)
      }
      .frame(
        width: geometry.size.width,
        height: geometry.size.height,
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
                preparedWarehouse.inventoryCount.formatted(),
                preparedWarehouse.totalUnits.formatted()
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
                          warehouseLocation.distinctTypeCount.formatted(),
                          warehouseLocation.totalUnits.formatted()
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
                preparedWarehouse.inventoryCount.formatted(),
                preparedWarehouse.totalUnits.formatted()
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
                  entityLowerCell(line.name, width: 190)
                  lowerCell(line.requiredQuantity.formatted(), width: 76)
                  lowerCell(line.factualWarehouseQuantity.formatted(), width: 76)
                  lowerCell(line.protectedQuantity.formatted(), width: 70)
                  lowerCell(line.reservedQuantity.formatted(), width: 70)
                  lowerCell(line.usableWarehouseQuantity.formatted(), width: 76)
                  lowerCell(
                    line.fromWarehouse.formatted(),
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
              entityLowerCell(material.name, width: 220)
              lowerCell(material.quantity.formatted(), width: 85)
              lowerCell(
                "\(line.marketFilledQuantity.formatted()) / \(material.quantity.formatted())",
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
                entityLowerCell(line.name, width: 220)
                lowerCell(line.fromWarehouse.formatted(), width: 90)
                lowerCell(line.toBuy.formatted(), width: 85)
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
          Text("\(procurement.totalQuantityToBuy.formatted()) units")
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
    let logistics = logisticsProjection(for: row)
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: costSheet,
      logistics: logistics
    )
    return ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(alignment: .firstTextBaseline) {
          EVEEntityText(value: row.productName)
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
          detailMetric("Installation", formatISK(costs.installationCost))
          detailMetric("Blueprint allocation", formatISK(costs.blueprintAllocation))
          detailMetric("Logistics", formatISK(costs.logisticsCost))
          detailMetric("Total cost", formatISK(costs.totalCost))
          detailMetric("Gross revenue", formatISK(costs.grossRevenue))
          detailMetric("Sales tax", formatISK(costs.salesTax))
          detailMetric("Broker fee", formatISK(costs.brokerFee))
          detailMetric("Profit", formatSignedISK(costs.profit))
          detailMetric("ROI", formatPercent(costs.returnOnInvestment))
          detailMetric("ISK / h", formatISK(costs.iskPerHour))
          detailMetric("ISK / m³", formatISK(costs.iskPerCubicMeter))
        }
        if let facilityName = row.facilityName {
          Label(facilityName, systemImage: "hammer.fill")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        ForEach(logistics.warnings) { warning in
          Label(
            LocalizedStringKey(warning.message),
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
            LocalizedStringKey(warning.message),
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

  private func entityLowerCell(_ value: String, width: CGFloat) -> some View {
    EVEEntityText(value: value, lineLimit: 1)
      .help(value)
      .frame(width: width, alignment: .leading)
  }

  private func filterColumn<Content: View>(
    _ title: LocalizedStringKey,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(DesignTokens.accent)
      content()
    }
    .padding(.trailing, DesignTokens.spacingSM)
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

  private func disabledToggle(_ title: LocalizedStringKey) -> some View {
    Toggle(title, isOn: .constant(false))
      .toggleStyle(.checkbox)
      .controlSize(.small)
      .font(.caption)
      .disabled(true)
      .help("This source is not available in the current app data.")
  }

  private func disabledFilterLine(_ title: LocalizedStringKey) -> some View {
    Label(title, systemImage: "circle.dashed")
      .font(.caption)
      .foregroundStyle(DesignTokens.textDisabled)
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

  private func costProjection(
    for row: ManufacturingOpportunityRow
  ) -> ManufacturingOpportunityCostProjection {
    ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: costSheet,
      logistics: logisticsProjection(for: row)
    )
  }

  private func logisticsProjection(
    for row: ManufacturingOpportunityRow
  ) -> ManufacturingOpportunityLogisticsProjection {
    let snapshot = runtime.manufacturingOpportunityAnalysis
    return ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: procurementProjection(for: row),
      configuration: snapshot?.logisticsConfiguration,
      mainHub: snapshot?.mainHub
        ?? runtime.productionBasis.mainTradingLocation?.location
        ?? .jita,
      warehouseIsAvailable: warehouseHasSnapshot
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
    Array(Set(runtime.manufacturingOpportunityAnalysis?.rows.map(\.categoryName) ?? []))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var groups: [String] {
    Array(Set(runtime.manufacturingOpportunityAnalysis?.rows.map(\.groupName) ?? []))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
        column: .profit,
        direction: .descending
      )
  }

  private var candidateProjectionTrigger: ManufacturingOpportunityCandidateProjectionTrigger {
    let stockTargetIdentity: [String] = stockTargets.map { target in
      "\(target.typeID):\(target.targetQuantity):\(target.updatedAt.timeIntervalSince1970)"
    }.sorted()
    let ownershipIdentity: [String] = characters.map { character -> String in
      let components: [String] = [
        String(character.characterID),
        String(character.corporationID ?? 0),
        String(character.blueprintSnapshot?.count ?? 0),
        String(character.corporationAssetSnapshot?.count ?? 0),
        String(character.lastSyncAt?.timeIntervalSince1970 ?? 0),
      ]
      return components.joined(separator: ":")
    }.sorted()
    let sortedFavoriteIDs: [Int64] = favoriteIDs.sorted()
    let productFamilies: [String] =
      selectedProductFamilies.map(\.rawValue).sorted()
    let activeSort = activeCandidateSort

    return ManufacturingOpportunityCandidateProjectionTrigger(
      snapshotID: runtime.manufacturingOpportunityAnalysis?.id,
      requestedWarehouseIdentity: warehouseIdentity,
      preparedWarehouseIdentity: preparedWarehouseIdentity,
      reservationRevision: preparedPlanReservationRevision,
      stockTargetIdentity: stockTargetIdentity,
      ownershipIdentity: ownershipIdentity,
      searchText: searchText,
      selectedCategory: selectedCategory,
      selectedGroup: selectedGroup,
      favoritesOnly: favoritesOnly,
      favoriteIDs: sortedFavoriteIDs,
      productFamilies: productFamilies,
      valueFilter: valueFilter.rawValue,
      includesPersonal: includesPersonal,
      includesCorporation: includesCorporation,
      includesNotOwned: includesNotOwned,
      includesUnknownOwnership: includesUnknownOwnership,
      includesBPO: includesBPO,
      includesBPC: includesBPC,
      includesCorporationHangars: includeCorporationHangars,
      includesBlueprintCost: costIncludesBlueprint,
      blueprintCostText: blueprintCostPerRunText,
      sortColumn: activeSort.column.rawValue,
      sortDirection: activeSort.direction.rawValue
    )
  }

  private var candidateOwnershipPayloads: [ManufacturingOpportunityOwnershipPayload] {
    characters.map {
      ManufacturingOpportunityOwnershipPayload(
        characterID: $0.characterID,
        corporationID: $0.corporationID,
        blueprintSnapshot: $0.blueprintSnapshot,
        corporationAssetSnapshot: $0.corporationAssetSnapshot
      )
    }
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
    productionTreeQuantity = max(
      1,
      runtime.manufacturingOpportunityAnalysis.flatMap {
        Int(exactly: $0.settings.targetQuantity)
      }
        ?? targetQuantity
    )
    expandedProductionNodeIDs = []
    reloadProductionTree(opportunity)
  }

  private func collapseProductionTree() {
    productionTreeTask?.cancel()
    productionTreeTask = nil
    expandedOpportunityTypeID = nil
    productionTree = nil
    productionTreeError = nil
    isLoadingProductionTree = false
    expandedProductionNodeIDs = []
  }

  private func reloadProductionTree(
    _ opportunity: ManufacturingOpportunityRow
  ) {
    productionTreeQuantity = max(1, productionTreeQuantity)
    let requestedQuantity = Int64(productionTreeQuantity)
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
          procurementPreferences: preferences,
          blueprintInventories: inventories
        )
        try Task.checkCancellation()
        guard expandedOpportunityTypeID == opportunity.productTypeID else {
          return
        }
        productionTree = tree
        expandedProductionNodeIDs.formUnion(tree.rootIDs)
        for node in tree.nodes {
          guard let blueprint = node.blueprint,
            treeBlueprintActions[blueprint.blueprintTypeID] == nil
          else { continue }
          treeBlueprintActions[blueprint.blueprintTypeID] =
            blueprint.recommendation
        }
        productionTreeError = nil
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

  private func productionTreeErrorMessage(_ error: Error) -> String {
    switch error {
    case StaticCatalogError.noActiveCatalog:
      "No active SDE catalog is installed.".localizedUI
    case ESIError.notFound:
      "The configured Main Hub or a required production location is unresolved."
        .localizedUI
    case ManufacturingOpportunityError.invalidSettings:
      "Enter a positive target quantity with valid ME and TE values."
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
    _ blueprint: ProductionTreeBlueprintAssessment
  ) -> Binding<ProductionTreeBlueprintAction> {
    Binding(
      get: {
        treeBlueprintActions[blueprint.blueprintTypeID]
          ?? blueprint.recommendation
      },
      set: { treeBlueprintActions[blueprint.blueprintTypeID] = $0 }
    )
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
      case .manufacturing: "Manufacturing".localizedUI
      case .reaction: "Reaction".localizedUI
      case .invention: "Invention".localizedUI
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
      "Factual \(factual.formatted()) · protected target \(protected.formatted()) · reserved \(reserved.formatted()) · usable \(usable.formatted()) · total required \(node.totalRequiredQuantity.formatted())."
  }

  private func blueprintActionTitle(
    _ action: ProductionTreeBlueprintAction
  ) -> String {
    switch action {
    case .useOwnedBPC: "Use owned BPC".localizedUI
    case .useOwnedBPO: "Use owned BPO".localizedUI
    case .copyOwnedBPO: "Copy owned BPO".localizedUI
    case .invent: "Invent BPC".localizedUI
    case .buyContract: "Buy contract".localizedUI
    case .unavailable: "Unavailable".localizedUI
    case .unresolved: "Status unresolved".localizedUI
    }
  }

  private func blueprintRecommendationLabel(
    _ action: ProductionTreeBlueprintAction
  ) -> String {
    AppLocalization.format(
      "Recommended: %@",
      blueprintActionTitle(action)
    )
  }

  private func blueprintActionColor(
    _ action: ProductionTreeBlueprintAction
  ) -> Color {
    switch action {
    case .useOwnedBPC, .useOwnedBPO:
      DesignTokens.positive
    case .copyOwnedBPO, .invent:
      DesignTokens.information
    case .buyContract:
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
        blueprint.requiredRuns.formatted()
      ),
      AppLocalization.format(
        "At production location: %@ BPC, %@ BPO, %@ unknown",
        blueprint.exactLocationBPCCount.formatted(),
        blueprint.exactLocationBPOCount.formatted(),
        blueprint.exactLocationUnknownCount.formatted()
      ),
      AppLocalization.format(
        "At copying location: %@ BPO",
        blueprint.copyingLocationBPOCount.formatted()
      ),
      AppLocalization.format(
        "Usable invention sources: %@",
        blueprint.inventionSourceCount.formatted()
      ),
      AppLocalization.format(
        "At ME/TE research locations: %@ BPC, %@ BPO",
        blueprint.researchLocationBPCCount.formatted(),
        blueprint.researchLocationBPOCount.formatted()
      ),
      AppLocalization.format(
        "Other locations: %@",
        blueprint.otherLocationCount.formatted()
      ),
      AppLocalization.format(
        "Indexed public-contract offers: %@",
        blueprint.indexedContractOfferCount.formatted()
      ),
    ]
    if let price = blueprint.lowestWholeContractPrice {
      parts.append(
        AppLocalization.format(
          "Lowest whole-contract price: %@",
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
      targetQuantity: Int64(max(1, targetQuantity)),
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency
    )
  }

  private var settingsChanged: Bool {
    guard let snapshot = runtime.manufacturingOpportunityAnalysis else {
      return false
    }
    return snapshot.settings != currentSettings
  }

  private func startAnalysis() {
    targetQuantity = max(1, targetQuantity)
    materialEfficiency = min(10, max(0, materialEfficiency))
    timeEfficiency = min(20, max(0, timeEfficiency))
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
  }

  private func selectAllFamilies() {
    persistProductFamilies(Set(ManufacturingOpportunityProductFamily.allCases))
  }

  private func resetFilters() {
    searchText = ""
    selectedCategory = ""
    selectedGroup = ""
    favoritesOnly = false
    valueFilter = .all
    includesPersonal = true
    includesCorporation = true
    includesNotOwned = true
    includesUnknownOwnership = true
    includesBPO = true
    includesBPC = true
    selectAllFamilies()
  }

  private func parseNonnegativeISK(_ text: String) -> Double? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty,
      let value = Double(normalized),
      value.isFinite,
      value >= 0
    else { return nil }
    return value
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

  @MainActor
  private func prepareCandidates(
    trigger: ManufacturingOpportunityCandidateProjectionTrigger
  ) async {
    guard
      let snapshot = runtime.manufacturingOpportunityAnalysis,
      preparedWarehouseIdentity == warehouseIdentity,
      preparedPlanReservations.source == activePlanSnapshotPayloads
    else { return }
    let input = ManufacturingOpportunityCandidateProjectionInput(
      snapshot: snapshot,
      factualWarehouseQuantities: preparedWarehouse.factualQuantities,
      protectedQuantities: protectedQuantities,
      reservedQuantities: reservedQuantities,
      warehouseIsAvailable: warehouseHasSnapshot,
      ownershipPayloads: candidateOwnershipPayloads,
      includesCorporationHangars: includeCorporationHangars,
      favorites: favoriteIDs,
      productFamilies: selectedProductFamilies,
      includesPersonal: includesPersonal,
      includesCorporation: includesCorporation,
      includesNotOwned: includesNotOwned,
      includesUnknownOwnership: includesUnknownOwnership,
      includesBPO: includesBPO,
      includesBPC: includesBPC,
      searchText: searchText,
      selectedCategory: selectedCategory,
      selectedGroup: selectedGroup,
      favoritesOnly: favoritesOnly,
      valueFilter: valueFilter,
      costSheet: costSheet,
      sort: activeCandidateSort
    )
    let candidates = await ManufacturingOpportunityCandidateProjection.prepare(
      input: input
    )
    guard
      !Task.isCancelled,
      trigger == candidateProjectionTrigger
    else { return }
    preparedCandidateProjection = PreparedManufacturingOpportunityCandidates(
      trigger: trigger,
      candidates: candidates
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

  private func formatISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.currency(code: "ISK").precision(.fractionLength(0)))
  }

  private func formatSignedISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    let formatted = formatISK(abs(value))
    return value > 0 ? "+\(formatted)" : value < 0 ? "−\(formatted)" : formatted
  }

  private func formatPercent(_ value: Double?) -> String {
    value?.formatted(.percent.precision(.fractionLength(1))) ?? "—"
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

private struct StoredPlanSnapshotPayload: Hashable, Sendable {
  let id: UUID
  let encodedSnapshot: Data
}

private struct PreparedPlanReservations: Sendable {
  let source: [StoredPlanSnapshotPayload]
  let allocations: [StockAllocation]
  let quantities: [Int64: Int64]
  let invalidSnapshotCount: Int

  static let empty = PreparedPlanReservations(
    source: [],
    allocations: [],
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
  let ownershipIdentity: [String]
  let searchText: String
  let selectedCategory: String
  let selectedGroup: String
  let favoritesOnly: Bool
  let favoriteIDs: [Int64]
  let productFamilies: [String]
  let valueFilter: String
  let includesPersonal: Bool
  let includesCorporation: Bool
  let includesNotOwned: Bool
  let includesUnknownOwnership: Bool
  let includesBPO: Bool
  let includesBPC: Bool
  let includesCorporationHangars: Bool
  let includesBlueprintCost: Bool
  let blueprintCostText: String
  let sortColumn: String
  let sortDirection: String
}

private struct ManufacturingOpportunityOwnershipPayload: Sendable {
  let characterID: Int64
  let corporationID: Int64?
  let blueprintSnapshot: Data?
  let corporationAssetSnapshot: Data?
}

private struct ManufacturingOpportunityCandidateProjectionInput: Sendable {
  let snapshot: ManufacturingOpportunitySnapshot
  let factualWarehouseQuantities: [Int64: Int64]
  let protectedQuantities: [Int64: Int64]
  let reservedQuantities: [Int64: Int64]
  let warehouseIsAvailable: Bool
  let ownershipPayloads: [ManufacturingOpportunityOwnershipPayload]
  let includesCorporationHangars: Bool
  let favorites: Set<Int64>
  let productFamilies: Set<ManufacturingOpportunityProductFamily>
  let includesPersonal: Bool
  let includesCorporation: Bool
  let includesNotOwned: Bool
  let includesUnknownOwnership: Bool
  let includesBPO: Bool
  let includesBPC: Bool
  let searchText: String
  let selectedCategory: String
  let selectedGroup: String
  let favoritesOnly: Bool
  let valueFilter: ManufacturingOpportunityValueFilter
  let costSheet: ManufacturingOpportunityCostSheet
  let sort: ManufacturingOpportunitySortDescriptor
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
      let ownership = ownershipFilter(input: input)
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
          input.productFamilies.contains(
            ManufacturingOpportunityProductFamily.classify(
              categoryName: row.categoryName,
              groupName: row.groupName
            )
          ),
          ownership.accepts(row)
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
          warehouseIsAvailable: input.warehouseIsAvailable
        )
        let costs = ManufacturingOpportunityScenarioProjector.costs(
          for: row,
          sheet: input.costSheet,
          logistics: logistics
        )
        guard input.valueFilter.accepts(costs) else { continue }
        candidates.append(
          ManufacturingOpportunityCandidate(row: row, costs: costs)
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

  private static func ownershipFilter(
    input: ManufacturingOpportunityCandidateProjectionInput
  ) -> ManufacturingOpportunityOwnershipFilter {
    let personalSnapshots: [Sourced<[OwnedBlueprintInstance]>] =
      input.ownershipPayloads.compactMap { payload in
        guard let data = payload.blueprintSnapshot else { return nil }
        return try? JSONDecoder().decode(
          Sourced<[OwnedBlueprintInstance]>.self,
          from: data
        )
      }
    let personalKinds = personalSnapshots.reduce(into: [Int64: Set<String>]()) {
      result, sourced in
      for blueprint in sourced.value ?? [] {
        result[blueprint.blueprintTypeID, default: []]
          .insert(blueprint.kind.rawValue)
      }
    }
    let personalComplete =
      !input.ownershipPayloads.isEmpty
      && personalSnapshots.count == input.ownershipPayloads.count
      && personalSnapshots.allSatisfy {
        $0.state == .fresh && $0.value != nil
      }
    var seen = Set<Int64>()
    let corporationSnapshots: [Sourced<AssetSnapshot>] =
      input.includesCorporationHangars
      ? input.ownershipPayloads.compactMap { payload in
        guard let corporationID = payload.corporationID,
          seen.insert(corporationID).inserted,
          let data = payload.corporationAssetSnapshot
        else { return nil }
        return try? JSONDecoder().decode(Sourced<AssetSnapshot>.self, from: data)
      } : []
    let corporationTypeIDs = Set(
      corporationSnapshots.flatMap { sourced in
        (sourced.value?.items ?? []).map(\.typeID)
      }
    )
    let corporationIDs = Set(input.ownershipPayloads.compactMap(\.corporationID))
    let corporationComplete =
      !input.includesCorporationHangars
      || (!corporationIDs.isEmpty
        && corporationSnapshots.count == corporationIDs.count
        && corporationSnapshots.allSatisfy {
          $0.state == .fresh && $0.value != nil
        })
    return ManufacturingOpportunityOwnershipFilter(
      personalKinds: personalKinds,
      corporationTypeIDs: corporationTypeIDs,
      personalComplete: personalComplete,
      corporationComplete: corporationComplete,
      includesPersonal: input.includesPersonal,
      includesCorporation: input.includesCorporation,
      includesNotOwned: input.includesNotOwned,
      includesUnknown: input.includesUnknownOwnership,
      includesBPO: input.includesBPO,
      includesBPC: input.includesBPC
    )
  }
}

private struct ManufacturingOpportunityCandidate: Identifiable, Sendable {
  var id: Int64 { row.id }
  let row: ManufacturingOpportunityRow
  let costs: ManufacturingOpportunityCostProjection
}

private struct ManufacturingOpportunityOwnershipFilter: Sendable {
  let personalKinds: [Int64: Set<String>]
  let corporationTypeIDs: Set<Int64>
  let personalComplete: Bool
  let corporationComplete: Bool
  let includesPersonal: Bool
  let includesCorporation: Bool
  let includesNotOwned: Bool
  let includesUnknown: Bool
  let includesBPO: Bool
  let includesBPC: Bool

  func accepts(_ row: ManufacturingOpportunityRow) -> Bool {
    let kinds = personalKinds[row.blueprintTypeID] ?? []
    let personallyOwned = !kinds.isEmpty
    let corporationOwned = corporationTypeIDs.contains(row.blueprintTypeID)
    if includesPersonal, personallyOwned, personalKindFilterAccepts(kinds) {
      return true
    }
    if includesCorporation, corporationOwned { return true }
    guard !personallyOwned, !corporationOwned else { return false }
    return personalComplete && corporationComplete
      ? includesNotOwned : includesUnknown
  }

  private func personalKindFilterAccepts(_ kinds: Set<String>) -> Bool {
    if includesBPO, kinds.contains(BlueprintCopyKind.original.rawValue) {
      return true
    }
    if includesBPC, kinds.contains(BlueprintCopyKind.copy.rawValue) {
      return true
    }
    return includesBPO && includesBPC
      && kinds.contains(BlueprintCopyKind.unknown.rawValue)
  }
}

private enum OpportunityTopTab: String, CaseIterable, Identifiable {
  case profile
  case costSheet
  case advanced

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .profile: "Simple Profile"
    case .costSheet: "Cost Sheet"
    case .advanced: "Advanced Filters"
    }
  }
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
  fileprivate var title: LocalizedStringKey {
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
