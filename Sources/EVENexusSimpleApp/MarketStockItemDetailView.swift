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

/// Item detail: 30-day chart for Main, Home and Coalition (single points of
/// the last 7 days, daily values before; gaps stay gaps) and a sortable
/// daily table of one hub.
struct MarketStockItemDetailView: View {
  let request: MarketStockItemRequest

  @Environment(RuntimeState.self) private var runtime
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @State private var histories: [MarketStockItemHubHistory]?
  @State private var metric: MarketStockChartMetric = .sellUnits
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
          .font(.caption.weight(.semibold))
          .foregroundStyle(DesignTokens.textSecondary)
        EVEItemText(
          value: request.name,
          typeID: request.typeID,
          font: .title2.weight(.semibold),
          lineLimit: 1,
          iconSize: 28,
          accessibilityIdentifier: "market-stock.detail.name.copy"
        )
      }
      Spacer()
      Button("Close") { dismiss() }
        .keyboardShortcut(.cancelAction)
    }
  }

  @ViewBuilder
  private func content(_ histories: [MarketStockItemHubHistory]) -> some View {
    // Label separat und beide Teile in Idealbreite: Der fett gesetzte
    // Segmenttext darf das Label beim Umschalten nicht zusammendrücken.
    HStack(spacing: DesignTokens.spacingSM) {
      Text("Show")
        .fixedSize()
      Picker("Show", selection: $metric) {
        Text("Sell stock").tag(MarketStockChartMetric.sellUnits)
        Text("Buy demand").tag(MarketStockChartMetric.buyUnits)
        Text("Lowest sell price").tag(MarketStockChartMetric.sellPrice)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .fixedSize()
      .accessibilityIdentifier("market-stock.detail.metric")
    }

    chart(histories)
      .frame(minHeight: 240)

    Text(
      "Last 7 days: every stored point. Before: one daily value per UTC day (its last point). A day without a point leaves a gap; it is never drawn as 0."
    )
    .font(.caption)
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
    let samples: [MarketStockChartSample]
  }

  private func chart(_ histories: [MarketStockItemHubHistory]) -> some View {
    let now = Date()
    let fineStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
    let series = histories.map { history in
      HubSeries(
        id: history.role,
        name: hubTitle(history),
        samples: MarketStockChartBuilder.samples(
          days: history.days,
          points: history.points,
          metric: metric,
          fineWindowStart: fineStart
        )
      )
    }
    let start = histories.first?.days.first?.day ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
    return Group {
      if series.allSatisfy({ $0.samples.isEmpty }) {
        Label(
          "No stored market stock point for this item yet.",
          systemImage: "chart.xyaxis.line"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 240)
      } else {
        Chart {
          ForEach(series) { hub in
            ForEach(Array(hub.samples.enumerated()), id: \.offset) { _, sample in
              LineMark(
                x: .value("Time", sample.date),
                y: .value(metricTitle, sample.value),
                series: .value("Segment", "\(hub.name)#\(sample.segment)")
              )
              .foregroundStyle(by: .value("Hub", hub.name))
              PointMark(
                x: .value("Time", sample.date),
                y: .value(metricTitle, sample.value)
              )
              .foregroundStyle(by: .value("Hub", hub.name))
              .symbolSize(sample.isDailyValue ? 30 : 12)
            }
          }
        }
        .chartForegroundStyleScale(
          domain: series.map(\.name),
          range: series.map { color(for: $0.id) }
        )
        .chartXScale(domain: start...now)
        .chartYAxisLabel(metricTitle)
        .accessibilityLabel(Text(metricTitle))
      }
    }
  }

  private var metricTitle: String {
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
      .font(.caption.weight(.semibold))
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
    .font(.callout.monospacedDigit())
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
