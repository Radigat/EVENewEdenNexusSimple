import Charts
import EVENexusCore
import SwiftUI

/// Opens the stock history of one item (MARKTBESTAND_PLAN P6).
struct MarketStockItemRequest: Identifiable, Equatable {
  let typeID: Int64
  let name: String
  /// Hub whose daily table is shown first, normally the route's target.
  let preferredRole: OpportunityHubRole

  var id: Int64 { typeID }
}

/// The one place that opens the stock history (owner rule 09.11.2026):
/// every item link in a window or sheet asks its nearest host, so all areas
/// show the same `MarketStockItemDetailView` with the same stored hub data.
@MainActor
@Observable
final class MarketStockHistoryRouter {
  var request: MarketStockItemRequest?

  func open(_ request: MarketStockItemRequest) {
    self.request = request
  }
}

private struct MarketStockHistoryRouterKey: EnvironmentKey {
  static let defaultValue: MarketStockHistoryRouter? = nil
}

extension EnvironmentValues {
  /// Nearest stock history host; `nil` outside a host, where the item link
  /// stays hidden instead of offering a click that cannot open anything.
  var marketStockHistoryRouter: MarketStockHistoryRouter? {
    get { self[MarketStockHistoryRouterKey.self] }
    set { self[MarketStockHistoryRouterKey.self] = newValue }
  }
}

/// Presents the stock history for its content. The main window installs one
/// host; a sheet that shows items installs its own, because a second sheet
/// can only be presented from inside the sheet that is already open.
private struct MarketStockHistoryHost: ViewModifier {
  @Environment(RuntimeState.self) private var runtime: RuntimeState?
  @State private var router = MarketStockHistoryRouter()

  func body(content: Content) -> some View {
    @Bindable var router = router
    content
      .environment(\.marketStockHistoryRouter, runtime == nil ? nil : router)
      .sheet(item: $router.request) { request in
        if let runtime {
          MarketStockItemDetailView(request: request)
            .environment(runtime)
        }
      }
  }
}

extension View {
  func marketStockHistoryHost() -> some View {
    modifier(MarketStockHistoryHost())
  }
}

/// The stock history link next to an item name: a separate control, so the
/// name keeps its copy click. Hidden without a host or a positive type ID.
struct MarketStockHistoryButton: View {
  let typeID: Int64
  let name: String
  /// Hub whose daily table is shown first; Home Hub outside Trade and
  /// Market stock (owner decision 09.11.2026).
  var preferredRole: OpportunityHubRole = .home
  var accessibilityIdentifier: String? = nil

  @Environment(\.marketStockHistoryRouter) private var router

  var body: some View {
    if let router, typeID > 0 {
      Button {
        router.open(
          MarketStockItemRequest(typeID: typeID, name: name, preferredRole: preferredRole)
        )
      } label: {
        Image(systemName: "chart.xyaxis.line")
      }
      .buttonStyle(.borderless)
      .help(AppLocalization.text("Market stock history"))
      .accessibilityLabel("Market stock history")
      .accessibilityValue(Text(verbatim: name))
      .accessibilityIdentifier(accessibilityIdentifier ?? "market-stock-history.\(typeID)")
    }
  }
}

/// Y-axis labels of the item chart: scaled units instead of scientific
/// notation. A value that rounds up to 1000 moves to the next unit.
enum MarketStockAxisFormat {
  static func label(_ value: Double, locale: Locale) -> String {
    let units: [(threshold: Double, suffix: String)] = [
      (1, ""),
      (1_000, "Tsd.".localizedUI),
      (1_000_000, "Mio.".localizedUI),
      (1_000_000_000, "B"),
      (1_000_000_000_000, "T"),
    ]
    var index = 0
    while index < units.count - 1,
      (abs(value) / units[index].threshold * 100).rounded() / 100 >= 1_000
    {
      index += 1
    }
    let unit = units[index]
    let number = (value / unit.threshold).formatted(
      .number.locale(locale).precision(.fractionLength(0...2))
    )
    return unit.suffix.isEmpty ? number : "\(number) \(unit.suffix)"
  }
}

/// What the chart area shows: one metric for every hub, or all three
/// metrics of a single hub.
enum MarketStockChartSelection: Hashable {
  case metric(MarketStockChartMetric)
  case hub(OpportunityHubRole)
}

/// Item detail: 30-day chart for Main, Home and Coalition (single points of
/// the last 7 days, daily values before; gaps stay gaps) and a sortable
/// daily table of one hub.
struct MarketStockItemDetailView: View {
  let request: MarketStockItemRequest

  @Environment(RuntimeState.self) private var runtime
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @State private var histories: [MarketStockItemHubHistory]?
  @State private var selection: MarketStockChartSelection = .metric(.sellUnits)
  /// Sample the pointer snapped to; drives rule, highlights and tooltip.
  @State private var hoverAnchor: MarketStockChartSample?
  @State private var tableRole: OpportunityHubRole?
  @State private var sort = AppTableSortDescriptor(
    column: MarketStockDayRow.Column.day,
    direction: .descending
  )

  private let numberWidth: CGFloat = 104

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      if let histories {
        if histories.isEmpty {
          Label(
            "No hub with a known location is configured.",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(DesignTokens.caution)
        } else {
          content(histories)
        }
      } else {
        ProgressView("Loading market stock history…")
          .frame(maxWidth: .infinity, alignment: .center)
      }
      Spacer(minLength: 0)
    }
    .padding(DesignTokens.spacingLG)
    .frame(minWidth: 780, minHeight: 640)
    // The build link in the header closes this sheet before the Planner
    // opens; the sheet would otherwise stay over the new area.
    .environment(\.plannerBuildClosesPresentation, dismiss)
    .task {
      let loaded = await runtime.marketStockItemHistory(typeID: request.typeID)
      histories = loaded
      let preferred = runtime.tradeDataRole(for: request.preferredRole)
      tableRole =
        loaded.first(where: { $0.role == preferred })?.role ?? loaded.first?.role
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Market stock history")
          .appFont(.caption.weight(.semibold))
          .foregroundStyle(DesignTokens.textSecondary)
        EVEItemText(
          value: request.name,
          typeID: request.typeID,
          font: .title2.weight(.semibold),
          lineLimit: 1,
          iconSize: 28,
          accessibilityIdentifier: "market-stock.detail.name.copy",
          showsMarketStockHistory: false
        )
      }
      Spacer()
      Button("Close") { dismiss() }
        .keyboardShortcut(.cancelAction)
    }
  }

  @ViewBuilder
  private func content(_ histories: [MarketStockItemHubHistory]) -> some View {
    // Zwei Zeilen mit derselben Auswahl: oben eine Kennzahl über alle Hubs,
    // unten ein Hub mit allen drei Kennzahlen. Genau ein Segment beider
    // Zeilen ist aktiv. Labels separat und Picker in Idealbreite: Der fett
    // gesetzte Segmenttext darf das Label nicht zusammendrücken.
    Grid(
      alignment: .leading,
      horizontalSpacing: DesignTokens.spacingSM,
      verticalSpacing: DesignTokens.spacingXS
    ) {
      GridRow {
        Text("All hubs")
          .fixedSize()
        Picker("All hubs", selection: $selection) {
          ForEach(MarketStockChartMetric.allCases) { metric in
            Text(metricTitle(metric)).tag(MarketStockChartSelection.metric(metric))
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("market-stock.detail.metric")
      }
      GridRow {
        Text("One hub")
          .fixedSize()
        Picker("One hub", selection: $selection) {
          ForEach(histories) { history in
            Text(hubTitle(history)).tag(MarketStockChartSelection.hub(history.role))
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("market-stock.detail.hub-view")
      }
    }

    Group {
      switch selection {
      case .metric(let metric):
        chart(series: hubSeries(histories, metric: metric), metric: metric, minHeight: 240)
      case .hub(let role):
        if let history = histories.first(where: { $0.role == role }) {
          hubCharts(history)
        }
      }
    }
    .onChange(of: selection) { hoverAnchor = nil }

    Text(
      "Last 7 days: every stored point. Before: one daily value per UTC day (its last point). A day without a point leaves a gap; it is never drawn as 0."
    )
    .appFont(.caption)
    .foregroundStyle(DesignTokens.textSecondary)

    Text(
      "The value axis covers only the plotted range and need not start at 0. Hover over a point: every hub shows its nearest point within 3 hours (daily values: same UTC day)."
    )
    .appFont(.caption)
    .foregroundStyle(DesignTokens.textSecondary)

    Divider()

    HStack(spacing: DesignTokens.spacingSM) {
      Text("Daily table")
        .fixedSize()
      Picker("Daily table", selection: tableRoleBinding(histories)) {
        ForEach(histories) { history in
          Text(hubTitle(history)).tag(history.role)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .fixedSize()
      .accessibilityIdentifier("market-stock.detail.table-hub")
    }

    if let history = histories.first(where: { $0.role == tableRole }) {
      dayTable(history)
    }
  }

  // MARK: Chart

  private struct HubSeries: Identifiable {
    let id: OpportunityHubRole
    let name: String
    /// First stored UTC day of the hub; left end of the time axis.
    let start: Date?
    let samples: [MarketStockChartSample]
  }

  private func hubSeries(
    _ histories: [MarketStockItemHubHistory],
    metric: MarketStockChartMetric
  ) -> [HubSeries] {
    let fineStart = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    return histories.map { history in
      HubSeries(
        id: history.role,
        name: hubTitle(history),
        start: history.days.first?.day,
        samples: MarketStockChartBuilder.samples(
          days: history.days,
          points: history.points,
          metric: metric,
          fineWindowStart: fineStart
        )
      )
    }
  }

  /// Hub view: one chart per metric for the selected hub only, stacked with
  /// a shared time axis; hovering marks the same moment in all three.
  private func hubCharts(_ history: MarketStockItemHubHistory) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      ForEach(MarketStockChartMetric.allCases) { metric in
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text(metricTitle(metric))
            .appFont(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.textSecondary)
          chart(
            series: hubSeries([history], metric: metric),
            metric: metric,
            minHeight: 120,
            showsLegend: false
          )
        }
      }
    }
    .accessibilityIdentifier("market-stock.detail.hub-charts")
  }

  private func chart(
    series: [HubSeries],
    metric: MarketStockChartMetric,
    minHeight: CGFloat,
    showsLegend: Bool = true
  ) -> some View {
    let now = Date()
    let title = metricTitle(metric)
    let start =
      series.compactMap(\.start).first ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
    return Group {
      if series.allSatisfy({ $0.samples.isEmpty }) {
        Label(
          "No stored market stock point for this item yet.",
          systemImage: "chart.xyaxis.line"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        .frame(maxWidth: .infinity, minHeight: minHeight)
      } else {
        Chart {
          ForEach(series) { hub in
            ForEach(Array(hub.samples.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.date),
                y: .value(title, sample.value),
                series: .value("Segment", "\(hub.name)#\(sample.segment)")
              )
              .foregroundStyle(by: .value("Hub", hub.name))
              PointMark(
                x: .value("Time", sample.date),
                y: .value(title, sample.value)
              )
              .foregroundStyle(by: .value("Hub", hub.name))
              .symbolSize(sample.isDailyValue ? 30 : 12)
            }
          }
          if let hoverAnchor {
            RuleMark(x: .value("Time", hoverAnchor.date))
              .foregroundStyle(DesignTokens.textSecondary.opacity(0.7))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(series) { hub in
              if let sample = MarketStockChartHover.sample(
                for: hoverAnchor.date, in: hub.samples)
              {
                PointMark(
                  x: .value("Time", sample.date),
                  y: .value(title, sample.value)
                )
                .foregroundStyle(by: .value("Hub", hub.name))
                .symbolSize(90)
              }
            }
          }
        }
        .chartForegroundStyleScale(
          domain: series.map(\.name),
          range: series.map { color(for: $0.id) }
        )
        .chartXScale(domain: start...now)
        .chartYScale(
          domain: MarketStockChartScale.valueDomain(
            series.flatMap { $0.samples.map(\.value) }) ?? 0...1
        )
        .chartOverlay { proxy in
          hoverOverlay(proxy: proxy, series: series, metric: metric)
        }
        .chartLegend(showsLegend ? .automatic : .hidden)
        .chartYAxisLabel(title)
        .chartYAxis {
          AxisMarks { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
              if let number = value.as(Double.self) {
                Text(MarketStockAxisFormat.label(number, locale: locale))
              }
            }
          }
        }
        .accessibilityLabel(Text(title))
        .frame(minHeight: minHeight)
      }
    }
  }

  /// Pointer distance (pt) within which the nearest sample is shown.
  private let hoverSnapDistance: CGFloat = 36

  private func hoverOverlay(
    proxy: ChartProxy,
    series: [HubSeries],
    metric: MarketStockChartMetric
  ) -> some View {
    GeometryReader { geometry in
      Rectangle()
        .fill(.clear)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case .active(let location):
            hoverAnchor = nearestSample(
              to: location, proxy: proxy, geometry: geometry, series: series)
          case .ended:
            hoverAnchor = nil
          }
        }
        .accessibilityHidden(true)
      if let hoverAnchor, let plotFrame = proxy.plotFrame,
        let anchorX = proxy.position(forX: hoverAnchor.date)
      {
        let origin = geometry[plotFrame].origin
        let ruleX = origin.x + anchorX
        let placeLeft = ruleX > geometry.size.width / 2
        let gap: CGFloat = 10
        hoverTooltip(anchor: hoverAnchor, series: series, metric: metric)
          .fixedSize()
          .frame(
            width: max(placeLeft ? ruleX - gap : geometry.size.width - ruleX - gap, 0),
            alignment: placeLeft ? .topTrailing : .topLeading
          )
          .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: placeLeft ? .topLeading : .topTrailing
          )
          .padding(.top, origin.y + 6)
          .allowsHitTesting(false)
      }
    }
  }

  /// Snaps to the nearest sample of any hub when it is close to the pointer.
  private func nearestSample(
    to location: CGPoint,
    proxy: ChartProxy,
    geometry: GeometryProxy,
    series: [HubSeries]
  ) -> MarketStockChartSample? {
    guard let plotFrame = proxy.plotFrame else { return nil }
    let frame = geometry[plotFrame]
    guard frame.contains(location) else { return nil }
    let x = location.x - frame.origin.x
    guard let date = proxy.value(atX: x, as: Date.self),
      let anchor = MarketStockChartHover.anchor(near: date, in: series.map(\.samples)),
      let anchorX = proxy.position(forX: anchor.date),
      abs(anchorX - x) <= hoverSnapDistance
    else { return nil }
    return anchor
  }

  private func hoverTooltip(
    anchor: MarketStockChartSample,
    series: [HubSeries],
    metric: MarketStockChartMetric
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(hoverHeader(anchor))
        .appFont(.caption.weight(.semibold))
        .foregroundStyle(DesignTokens.textSecondary)
      ForEach(series) { hub in
        let sample = MarketStockChartHover.sample(for: anchor.date, in: hub.samples)
        HStack(spacing: DesignTokens.spacingSM) {
          Circle()
            .fill(color(for: hub.id))
            .frame(width: 8, height: 8)
          Text(hub.name)
          Spacer(minLength: DesignTokens.spacingMD)
          if let sample {
            Text(hoverValue(sample.value, metric: metric))
              .appFont(.callout.monospacedDigit().weight(.semibold))
            if abs(sample.date.timeIntervalSince(anchor.date)) >= 60 {
              Text(hoverTime(sample.date, anchor: anchor.date))
                .appFont(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary)
            }
          } else {
            Text("no point")
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .appFont(.callout)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(DesignTokens.border.opacity(0.8), lineWidth: 1)
    )
    .accessibilityIdentifier("market-stock.detail.chart.tooltip")
  }

  private func hoverHeader(_ anchor: MarketStockChartSample) -> String {
    let time = anchor.date.formatted(
      Date.FormatStyle(date: .numeric, time: .shortened, timeZone: .gmt).locale(locale)
    )
    let header = "\(time) UTC"
    return anchor.isDailyValue
      ? "\(header) · \(AppLocalization.text("Daily value"))" : header
  }

  /// A hub's own measurement time when it differs from the snapped moment;
  /// with the date when it falls on another UTC day.
  private func hoverTime(_ date: Date, anchor: Date) -> String {
    let sameDay =
      MarketStockHistoryStore.utcDay(containing: date)
      == MarketStockHistoryStore.utcDay(containing: anchor)
    let style = Date.FormatStyle(
      date: sameDay ? .omitted : .numeric, time: .shortened, timeZone: .gmt
    ).locale(locale)
    return date.formatted(style)
  }

  private func hoverValue(_ value: Double, metric: MarketStockChartMetric) -> String {
    switch metric {
    case .sellPrice:
      "\(value.formatted(.number.locale(locale).precision(.fractionLength(0...2)))) ISK"
    case .sellUnits, .buyUnits:
      value.formatted(.number.locale(locale).precision(.fractionLength(0)))
    }
  }

  private func metricTitle(_ metric: MarketStockChartMetric) -> String {
    switch metric {
    case .sellUnits: AppLocalization.text("Sell stock")
    case .buyUnits: AppLocalization.text("Buy demand")
    case .sellPrice: AppLocalization.text("Lowest sell price")
    }
  }

  private func color(for role: OpportunityHubRole) -> Color {
    switch role {
    case .main: DesignTokens.highlight
    case .home: DesignTokens.accent
    case .coalition: DesignTokens.positive
    }
  }

  private func hubTitle(_ history: MarketStockItemHubHistory) -> String {
    ([history.role] + history.sharedRoles)
      .map(TradeHubText.roleName)
      .joined(separator: " = ")
  }

  // MARK: Daily table

  private func tableRoleBinding(
    _ histories: [MarketStockItemHubHistory]
  ) -> Binding<OpportunityHubRole> {
    Binding(
      get: { tableRole ?? histories.first?.role ?? .main },
      set: { tableRole = $0 }
    )
  }

  private func dayTable(_ history: MarketStockItemHubHistory) -> some View {
    let rows = MarketStockDayRow.sorted(
      history.days.map(MarketStockDayRow.init),
      by: sort.column,
      ascending: sort.direction == .ascending
    )
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: DesignTokens.spacingXS) {
        SortableTableHeader(
          title: "Date (UTC)",
          column: MarketStockDayRow.Column.day,
          sort: $sort,
          defaultDirection: .descending
        )
        .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
        numberHeader("Sell stock", .sellUnits)
        numberHeader("Added", .added)
        numberHeader("Partly sold", .partiallyFilled)
        numberHeader("Vanished", .vanished)
        numberHeader("Net", .net)
      }
      .appFont(.caption.weight(.semibold))
      .padding(.bottom, DesignTokens.spacingXS)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(rows) { row in
            dayRow(row)
            Divider()
          }
        }
      }
      .frame(minHeight: 200)
    }
    .accessibilityIdentifier("market-stock.detail.table")
  }

  private func numberHeader(
    _ title: LocalizedStringKey,
    _ column: MarketStockDayRow.Column
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      defaultDirection: .descending,
      alignment: .trailing
    )
    .frame(width: numberWidth, alignment: .trailing)
  }

  private func dayRow(_ row: MarketStockDayRow) -> some View {
    let deltaTint = row.isPartial ? DesignTokens.caution : DesignTokens.textPrimary
    return HStack(spacing: DesignTokens.spacingXS) {
      Text(
        row.day.formatted(
          Date.FormatStyle(date: .numeric, time: .omitted, timeZone: .gmt).locale(locale)
        )
      )
      .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
      numberCell(formatInteger(row.sellUnits))
      numberCell(formatInteger(row.added), tint: deltaTint)
      numberCell(formatInteger(row.partiallyFilled), tint: deltaTint)
      numberCell(formatInteger(row.vanished), tint: deltaTint)
      numberCell(
        row.net.map(formatSigned) ?? "—",
        tint: row.isPartial
          ? DesignTokens.caution
          : row.net.map { $0 < 0 ? DesignTokens.negative : $0 > 0 ? DesignTokens.positive : DesignTokens.textPrimary }
            ?? DesignTokens.textPrimary
      )
    }
    .appFont(.callout.monospacedDigit())
    .padding(.vertical, 3)
    .help(rowHelp(row))
  }

  private func rowHelp(_ row: MarketStockDayRow) -> String {
    if row.sellUnits == nil {
      return AppLocalization.text("No market stock point on this day: unknown, not 0.")
    }
    if row.net == nil {
      return AppLocalization.text(
        "Stock known, but no change to an earlier point is known for this day."
      )
    }
    if row.isPartial {
      return AppLocalization.text(
        "Only partly recorded: one point of this day has no known change to its predecessor."
      )
    }
    return AppLocalization.text(
      "Stock at the day's last point. Added: new orders; partly sold: surely traded; vanished: sold, cancelled or expired."
    )
  }

  private func numberCell(_ text: String, tint: Color = DesignTokens.textPrimary) -> some View {
    Text(text)
      .foregroundStyle(tint)
      .frame(width: numberWidth, alignment: .trailing)
  }

  private func formatInteger(_ value: Int64?) -> String {
    value.map { $0.formatted(.number.locale(locale)) } ?? "—"
  }

  private func formatSigned(_ value: Int64) -> String {
    value.formatted(.number.sign(strategy: .always(includingZero: false)).locale(locale))
  }
}
