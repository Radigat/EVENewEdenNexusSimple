import EVENexusCore
import SwiftData
import SwiftUI

struct RecentProductionsView: View {
  @Environment(\.modelContext) private var modelContext
  let rows: [StoredProductionOverviewRow]
  let onOpenHistoricalPlan: (StoredProductionOverviewRow) -> Void
  @State private var deletionCandidate: StoredProductionOverviewRow?
  @State private var isConfirmingDeletion = false
  @State private var persistenceError: String?

  var body: some View {
    Panel(title: "Last five productions") {
      GeometryReader { geometry in
        ProductionOverviewGrid(
          rows: rows,
          isEditable: true,
          availableWidth: geometry.size.width,
          onSave: save,
          onRequestDelete: requestDeletion,
          onOpenHistoricalPlan: onOpenHistoricalPlan
        )
        .frame(maxHeight: .infinity, alignment: .top)
      }
      .frame(height: ProductionOverviewGrid.requiredHeight(for: rows.count))

      if let persistenceError {
        Label(persistenceError, systemImage: "externaldrive.badge.xmark")
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }

      if !rows.isEmpty {
        Text(
          "Double-click a production to open its saved historical values in the Planner."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

        Text(
          "Gerundete Beträge zeigen beim Darüberfahren mit der Maus den genauen ISK-Wert."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

        Text(
          "Sale price and sold units can be changed here or in Production Overview. Use the checkbox for not sold or fully sold; enter a quantity for a partial sale."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

        Text(
          "Production costs include material, installation, BPO/BPC and logistics. Sales tax and broker fee reduce sale revenue separately."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Text(
          "Calculate a plan and choose Record production in the Planner."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .confirmationDialog(
      "Produktionseintrag löschen?",
      isPresented: $isConfirmingDeletion,
      titleVisibility: .visible
    ) {
      Button("Eintrag löschen", role: .destructive) {
        confirmDeletion()
      }
      Button("Abbrechen", role: .cancel) {
        deletionCandidate = nil
      }
    } message: {
      Text(deletionConfirmationMessage)
    }
  }

  private var deletionConfirmationMessage: String {
    guard let deletionCandidate else {
      return "Dieser Produktionseintrag wird dauerhaft gelöscht."
    }
    return
      "„\(deletionCandidate.productName)“ (Nr. \(deletionCandidate.sequenceNumber)) wird aus dem Produktionsplaner und der Produktionsübersicht gelöscht. Dies kann nicht rückgängig gemacht werden."
  }

  private func requestDeletion(_ row: StoredProductionOverviewRow) {
    deletionCandidate = row
    isConfirmingDeletion = true
  }

  private func save() {
    do {
      try modelContext.save()
      persistenceError = nil
    } catch {
      modelContext.rollback()
      persistenceError =
        "Der Produktionseintrag konnte nicht gespeichert werden: \(error.localizedDescription)"
    }
  }

  private func confirmDeletion() {
    guard let deletionCandidate else { return }
    do {
      try deleteProductionOverviewRow(
        deletionCandidate,
        in: modelContext
      )
      persistenceError = nil
    } catch {
      persistenceError =
        "Der Produktionseintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
    }
    self.deletionCandidate = nil
  }
}

struct ProductionBookView: View {
  @Environment(\.modelContext) private var modelContext
  let onOpenHistoricalPlan: (StoredProductionOverviewRow) -> Void
  @Query(sort: \StoredProductionOverviewRow.sequenceNumber)
  private var rows: [StoredProductionOverviewRow]
  @State private var saveError: String?
  @State private var deletionCandidate: StoredProductionOverviewRow?
  @State private var isConfirmingDeletion = false

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Production Overview")
          .font(.largeTitle.bold())
        Text(
          "One row per produced item, following the Produktionsübersicht in EVE-indu- Delve.xlsx."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: 150),
            spacing: DesignTokens.spacingMD,
            alignment: .top
          )
        ],
        spacing: DesignTokens.spacingMD
      ) {
        summaryPanel(
          title: "Productions",
          value: rows.count.formatted()
        )
        summaryPanel(
          title: "Units",
          value: rows.reduce(0) { $0 + $1.units }.formatted()
        )
        summaryPanel(
          title: "Prog. Gewinn",
          value: compactISK(completeProjectedProfit, includesCurrency: true),
          exactValue: completeProjectedProfit
        )
        summaryPanel(
          title: "Realer Gewinn",
          value: compactISK(completeRealProfit, includesCurrency: true),
          exactValue: completeRealProfit
        )
      }

      if let saveError {
        Label(saveError, systemImage: "externaldrive.badge.xmark")
          .foregroundStyle(DesignTokens.negative)
      }

      Text(
        "Beträge sind platzsparend gerundet. Der genaue ISK-Wert erscheint beim Darüberfahren mit der Maus."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "Sale price and sold units can be changed here or in Production Overview. Use the checkbox for not sold or fully sold; enter a quantity for a partial sale."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "Double-click a production to open its saved historical values in the Planner."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "Production costs include material, installation, BPO/BPC and logistics. Sales tax and broker fee reduce sale revenue separately."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      GeometryReader { geometry in
        ScrollView(.vertical) {
          ProductionOverviewGrid(
            rows: rows,
            isEditable: true,
            availableWidth: geometry.size.width,
            onSave: save,
            onRequestDelete: requestDeletion,
            onOpenHistoricalPlan: onOpenHistoricalPlan
          )
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .defaultScrollAnchor(.top)
      }
      .background(DesignTokens.panel)
      .clipShape(
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.border)
      }
    }
    .padding(DesignTokens.spacingLG)
    .navigationTitle(AppLocalization.text("Production Overview"))
    .confirmationDialog(
      "Produktionseintrag löschen?",
      isPresented: $isConfirmingDeletion,
      titleVisibility: .visible
    ) {
      Button("Eintrag löschen", role: .destructive) {
        confirmDeletion()
      }
      Button("Abbrechen", role: .cancel) {
        deletionCandidate = nil
      }
    } message: {
      Text(deletionConfirmationMessage)
    }
  }

  private var completeProjectedProfit: Double? {
    let values = rows.map { calculation(for: $0).projectedProfit }
    guard values.allSatisfy({ $0 != nil }) else { return nil }
    return values.compactMap { $0 }.reduce(0, +)
  }

  private var completeRealProfit: Double? {
    let values = rows.map { calculation(for: $0).realProfit }
    guard values.allSatisfy({ $0 != nil }) else { return nil }
    return values.compactMap { $0 }.reduce(0, +)
  }

  private func summaryPanel(
    title: String,
    value: String,
    exactValue: Double? = nil
  ) -> some View {
    Panel(title: LocalizedStringKey(title)) {
      Text(value)
        .font(.title3.monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .help(exactValue.map(exactISK) ?? value)
    }
  }

  private func save() {
    do {
      try modelContext.save()
      saveError = nil
    } catch {
      modelContext.rollback()
      saveError =
        "Der Produktionseintrag konnte nicht gespeichert werden: \(error.localizedDescription)"
    }
  }

  private var deletionConfirmationMessage: String {
    guard let deletionCandidate else {
      return "Dieser Produktionseintrag wird dauerhaft gelöscht."
    }
    return
      "„\(deletionCandidate.productName)“ (Nr. \(deletionCandidate.sequenceNumber)) wird aus dem Produktionsplaner und der Produktionsübersicht gelöscht. Dies kann nicht rückgängig gemacht werden."
  }

  private func requestDeletion(_ row: StoredProductionOverviewRow) {
    deletionCandidate = row
    isConfirmingDeletion = true
  }

  private func confirmDeletion() {
    guard let deletionCandidate else { return }
    do {
      try deleteProductionOverviewRow(
        deletionCandidate,
        in: modelContext
      )
      saveError = nil
    } catch {
      saveError =
        "Der Produktionseintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
    }
    self.deletionCandidate = nil
  }
}

private struct ProductionOverviewGrid: View {
  let rows: [StoredProductionOverviewRow]
  let isEditable: Bool
  let availableWidth: CGFloat
  var onSave: () -> Void = {}
  var onRequestDelete: (StoredProductionOverviewRow) -> Void = { _ in }
  var onOpenHistoricalPlan: (StoredProductionOverviewRow) -> Void = { _ in }

  @State private var sort = AppTableSortDescriptor(
    column: ProductionOverviewSortColumn.sequence,
    direction: .ascending
  )

  private let headers: [(short: String, full: String)] = [
    ("Nr", "Nummer"),
    ("Datum", "Datum"),
    ("Produkt", "Produktionsitem"),
    ("Runs", "Runs"),
    ("ME", "Materialeffizienz"),
    ("TE", "Zeiteffizienz"),
    ("System", "System"),
    ("Units", "Units"),
    ("Material", "Materialkosten"),
    ("Install.", "Installationskosten inklusive Systemindex und Zuschlägen"),
    ("Logistik", "Logistikkosten"),
    ("BPO/BPC", "BPO/BPC-Kosten"),
    ("Tax", "Verkaufssteuer"),
    ("Broker", "Brokergebühr"),
    ("Prod.-kosten", "Produktionskosten"),
    ("Verkauf ges.", "Verkaufspreis gesamt"),
    ("Kosten/Unit", "Kosten per Unit"),
    ("Min. +10 %", "Mindestverkaufspreis per Unit (10 %)"),
    ("Verkauf/Unit", "Verkaufspreis per Unit"),
    ("Prog. Gewinn", "Prognostizierter Gewinn (gesamt)"),
    ("Margin", "Margin"),
    ("Verkauft", "Verkaufte Units"),
    ("Real Gewinn", "Realer Gewinn"),
  ]

  private let widthWeights: [CGFloat] = [
    28, 50, 88, 34, 24, 24, 52, 36, 48, 46, 44, 48, 42, 42, 52,
    54, 50, 54, 54, 54, 42, 52, 52,
  ]

  private let sortColumns = ProductionOverviewSortColumn.allCases

  private let cellHorizontalPadding: CGFloat = 3

  static func requiredHeight(for rowCount: Int) -> CGFloat {
    44 + CGFloat(max(1, rowCount)) * 28
  }

  private var widths: [CGFloat] {
    let paddingWidth =
      CGFloat(headers.count) * cellHorizontalPadding * 2
    let distributableWidth = max(1, availableWidth - paddingWidth)
    let totalWeight = widthWeights.reduce(0, +)
    return widthWeights.map { distributableWidth * $0 / totalWeight }
  }

  var body: some View {
    Grid(
      alignment: .leading,
      horizontalSpacing: 0,
      verticalSpacing: 0
    ) {
      GridRow {
        ForEach(headers.indices, id: \.self) { index in
          SortableTableHeader(
            title: LocalizedStringKey(headers[index].short),
            column: sortColumns[index],
            sort: $sort
          )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DesignTokens.canvas)
            .lineLimit(3)
            .minimumScaleFactor(0.65)
            .frame(
              width: widths[index],
              alignment: .leading
            )
            .frame(height: 44)
            .padding(.horizontal, cellHorizontalPadding)
            .background(DesignTokens.accent)
            .overlay(alignment: .trailing) {
              Rectangle()
                .fill(DesignTokens.canvas.opacity(0.35))
                .frame(width: 1)
            }
            .help(headers[index].full)
            .accessibilityLabel(headers[index].full)
        }
      }

      if rows.isEmpty {
        GridRow {
          Text("Noch keine Produktion erfasst")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, cellHorizontalPadding)
            .background(DesignTokens.panel)
            .overlay(cellBorder)
            .gridCellColumns(headers.count)
        }
      }

      ForEach(Array(sortedRows.enumerated()), id: \.element.id) { offset, row in
        let projection = productionProjection(for: row)
        let metrics = calculation(for: row, projection: projection)
        GridRow {
          textCell(row.sequenceNumber.formatted(), column: 0, row: offset)
          textCell(
            row.recordedAt.formatted(
              .dateTime.day().month().year(.twoDigits)
            ),
            column: 1,
            row: offset
          )
          entityCell(row.productName, column: 2, row: offset)
          numberCell(row.runs, column: 3, row: offset)
          numberCell(
            Int64(row.materialEfficiency),
            column: 4,
            row: offset
          )
          numberCell(
            Int64(row.timeEfficiency),
            column: 5,
            row: offset
          )
          entityCell(row.systemName, column: 6, row: offset)
          numberCell(row.units, column: 7, row: offset)
          moneyCell(row.materialCost, column: 8, row: offset)
          moneyCell(row.indexCost, column: 9, row: offset)
          moneyCell(projection?.logisticsCost, column: 10, row: offset)
          editableMoneyCell(
            row,
            keyPath: \.blueprintCost,
            column: 11,
            rowIndex: offset
          )
          moneyCell(metrics.salesTax, column: 12, row: offset)
          moneyCell(metrics.brokerFee, column: 13, row: offset)
          moneyCell(metrics.productionCost, column: 14, row: offset)
          moneyCell(metrics.saleTotal, column: 15, row: offset)
          moneyCell(metrics.costPerUnit, column: 16, row: offset)
          moneyCell(
            metrics.minimumSalePricePerUnit,
            column: 17,
            row: offset,
            emphasis: .minimumPrice
          )
          editableSalePriceCell(row, column: 18, rowIndex: offset)
          moneyCell(
            metrics.projectedProfit,
            column: 19,
            row: offset,
            emphasis: .profit
          )
          percentageCell(metrics.margin, column: 20, row: offset)
          editableSoldCell(row, column: 21, rowIndex: offset)
          moneyCell(
            metrics.realProfit,
            column: 22,
            row: offset,
            emphasis: .profit
          )
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
          onOpenHistoricalPlan(row)
        }
        .contextMenu {
          Button {
            onOpenHistoricalPlan(row)
          } label: {
            Label("Open historical plan", systemImage: "clock.arrow.circlepath")
          }
          Divider()
          Button(role: .destructive) {
            onRequestDelete(row)
          } label: {
            Label("Eintrag löschen…", systemImage: "trash")
          }
        }
        .accessibilityAction(named: "Eintrag löschen") {
          onRequestDelete(row)
        }
        .accessibilityAction(named: "Open historical plan") {
          onOpenHistoricalPlan(row)
        }
      }
    }
  }

  private var sortedRows: [StoredProductionOverviewRow] {
    let contexts = rows.map { row in
      let projection = productionProjection(for: row)
      return (
        row: row,
        projection: projection,
        metrics: calculation(for: row, projection: projection)
      )
    }
    return contexts.sorted { lhsContext, rhsContext in
      let lhs = lhsContext.row
      let rhs = rhsContext.row
      let lhsProjection = lhsContext.projection
      let rhsProjection = rhsContext.projection
      let lhsMetrics = lhsContext.metrics
      let rhsMetrics = rhsContext.metrics
      let ordered: Bool?
      switch sort.column {
      case .sequence:
        ordered = compare(lhs.sequenceNumber, rhs.sequenceNumber)
      case .date:
        ordered = compare(lhs.recordedAt, rhs.recordedAt)
      case .product:
        ordered = compare(lhs.productName, rhs.productName)
      case .runs:
        ordered = compare(lhs.runs, rhs.runs)
      case .materialEfficiency:
        ordered = compare(lhs.materialEfficiency, rhs.materialEfficiency)
      case .timeEfficiency:
        ordered = compare(lhs.timeEfficiency, rhs.timeEfficiency)
      case .system:
        ordered = compare(lhs.systemName, rhs.systemName)
      case .units:
        ordered = compare(lhs.units, rhs.units)
      case .materialCost:
        ordered = compareOptional(lhs.materialCost, rhs.materialCost)
      case .installationCost:
        ordered = compareOptional(lhs.indexCost, rhs.indexCost)
      case .logisticsCost:
        ordered = compareOptional(lhsProjection?.logisticsCost, rhsProjection?.logisticsCost)
      case .blueprintCost:
        ordered = compareOptional(lhs.blueprintCost, rhs.blueprintCost)
      case .salesTax:
        ordered = compareOptional(lhsMetrics.salesTax, rhsMetrics.salesTax)
      case .brokerFee:
        ordered = compareOptional(lhsMetrics.brokerFee, rhsMetrics.brokerFee)
      case .productionCost:
        ordered = compareOptional(lhsMetrics.productionCost, rhsMetrics.productionCost)
      case .saleTotal:
        ordered = compareOptional(lhsMetrics.saleTotal, rhsMetrics.saleTotal)
      case .costPerUnit:
        ordered = compareOptional(lhsMetrics.costPerUnit, rhsMetrics.costPerUnit)
      case .minimumSalePrice:
        ordered = compareOptional(
          lhsMetrics.minimumSalePricePerUnit,
          rhsMetrics.minimumSalePricePerUnit
        )
      case .salePrice:
        ordered = compareOptional(lhs.salePricePerUnit, rhs.salePricePerUnit)
      case .projectedProfit:
        ordered = compareOptional(lhsMetrics.projectedProfit, rhsMetrics.projectedProfit)
      case .margin:
        ordered = compareOptional(lhsMetrics.margin, rhsMetrics.margin)
      case .soldUnits:
        ordered = compare(lhs.soldUnits, rhs.soldUnits)
      case .realProfit:
        ordered = compareOptional(lhsMetrics.realProfit, rhsMetrics.realProfit)
      }
      return ordered ?? (lhs.id.uuidString < rhs.id.uuidString)
    }.map(\.row)
  }

  private func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> Bool? {
    guard lhs != rhs else { return nil }
    return sort.direction.orders(lhs, before: rhs)
  }

  private func compareOptional<Value: Comparable>(
    _ lhs: Value?,
    _ rhs: Value?
  ) -> Bool? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?): return compare(lhs, rhs)
    case (nil, nil): return nil
    case (nil, _): return sort.direction == .descending
    case (_, nil): return sort.direction == .ascending
    }
  }

  private func textCell(
    _ value: String,
    column: Int,
    row: Int
  ) -> some View {
    Text(value)
      .font(.caption)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .help(value)
      .frame(
        width: widths[column],
        alignment: .leading
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(rowBackground(row))
      .overlay(cellBorder)
  }

  private func entityCell(
    _ value: String,
    column: Int,
    row: Int
  ) -> some View {
    EVEEntityText(value: value, lineLimit: 1)
      .minimumScaleFactor(0.6)
      .help(value)
      .frame(width: widths[column], alignment: .leading)
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(rowBackground(row))
      .overlay(cellBorder)
  }

  private func numberCell(
    _ value: Int64,
    column: Int,
    row: Int
  ) -> some View {
    Text(compactCount(value))
      .font(.caption.monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .help(exactCount(value))
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(rowBackground(row))
      .overlay(cellBorder)
  }

  private func moneyCell(
    _ value: Double?,
    column: Int,
    row: Int,
    emphasis: CellEmphasis = .none
  ) -> some View {
    Text(compactISK(value))
      .font(.caption.monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.55)
      .foregroundStyle(valueColor(value, emphasis: emphasis))
      .help(value.map(exactISK) ?? "Wert nicht verfügbar")
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(cellBackground(row: row, emphasis: emphasis))
      .overlay(cellBorder)
  }

  private func percentageCell(
    _ value: Double?,
    column: Int,
    row: Int
  ) -> some View {
    Text(
      value?.formatted(
        .percent
          .locale(AppLocalization.currentLanguage.locale)
          .precision(.fractionLength(0...1))
      )
        ?? "—"
    )
    .font(.caption.monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .foregroundStyle(valueColor(value, emphasis: .profit))
    .help(
      value?.formatted(
        .percent
          .locale(AppLocalization.currentLanguage.locale)
          .precision(.fractionLength(0...4))
      ) ?? "Wert nicht verfügbar"
    )
    .frame(
      width: widths[column],
      alignment: .trailing
    )
    .frame(minHeight: 28)
    .padding(.horizontal, cellHorizontalPadding)
    .background(rowBackground(row))
    .overlay(cellBorder)
  }

  @ViewBuilder
  private func editableMoneyCell(
    _ row: StoredProductionOverviewRow,
    keyPath: ReferenceWritableKeyPath<StoredProductionOverviewRow, Double?>,
    column: Int,
    rowIndex: Int
  ) -> some View {
    if isEditable {
      TextField(
        "",
        value: Binding(
          get: { row[keyPath: keyPath] },
          set: {
            row[keyPath: keyPath] = sanitizedMoney($0)
            onSave()
          }
        ),
        format: .number.precision(.fractionLength(0...2))
      )
      .textFieldStyle(.plain)
      .font(.caption.monospacedDigit())
      .multilineTextAlignment(.trailing)
      .accessibilityLabel("BPO/BPC-Kosten bearbeiten")
      .accessibilityIdentifier(
        "production-overview.\(row.id).blueprint-cost"
      )
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(DesignTokens.accentSoft)
      .overlay(cellBorder)
      .help(row[keyPath: keyPath].map(exactISK) ?? "Wert nicht verfügbar")
    } else {
      moneyCell(
        row[keyPath: keyPath],
        column: column,
        row: rowIndex
      )
    }
  }

  @ViewBuilder
  private func editableSalePriceCell(
    _ row: StoredProductionOverviewRow,
    column: Int,
    rowIndex: Int
  ) -> some View {
    if isEditable {
      TextField(
        "",
        value: Binding(
          get: { row.salePricePerUnit },
          set: {
            row.salePricePerUnit = sanitizedMoney($0)
            row.marketTax = calculation(for: row).salesTax
            onSave()
          }
        ),
        format: .number.precision(.fractionLength(0...2))
      )
      .textFieldStyle(.plain)
      .font(.caption.monospacedDigit())
      .multilineTextAlignment(.trailing)
      .accessibilityLabel("Verkaufspreis pro Unit bearbeiten")
      .accessibilityIdentifier(
        "production-overview.\(row.id).sale-price"
      )
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(DesignTokens.accentSoft)
      .overlay(cellBorder)
      .help(row.salePricePerUnit.map(exactISK) ?? "Wert nicht verfügbar")
    } else {
      moneyCell(
        row.salePricePerUnit,
        column: column,
        row: rowIndex
      )
    }
  }

  @ViewBuilder
  private func editableSoldCell(
    _ row: StoredProductionOverviewRow,
    column: Int,
    rowIndex: Int
  ) -> some View {
    if isEditable {
      HStack(spacing: 2) {
        Button {
          row.soldUnits = row.soldUnits > 0 ? 0 : row.units
          onSave()
        } label: {
          Image(
            systemName:
              row.soldUnits > 0 ? "checkmark.square.fill" : "square"
          )
          .font(.caption)
          .foregroundStyle(
            row.soldUnits > 0
              ? DesignTokens.positive : DesignTokens.textSecondary
          )
        }
        .buttonStyle(.plain)
        .help(
          row.soldUnits > 0
            ? "Als nicht verkauft markieren"
            : "Als vollständig verkauft markieren"
        )
        .accessibilityLabel(
          row.soldUnits > 0
            ? "Als nicht verkauft markieren"
            : "Als vollständig verkauft markieren"
        )
        .accessibilityIdentifier(
          "production-overview.\(row.id).sold-toggle"
        )

        TextField(
          "",
          value: Binding(
            get: { row.soldUnits },
            set: {
              row.soldUnits = min(row.units, max(0, $0))
              onSave()
            }
          ),
          format: .number
        )
        .textFieldStyle(.plain)
        .font(.caption.monospacedDigit())
        .multilineTextAlignment(.trailing)
        .accessibilityLabel("Verkaufte Units bearbeiten")
        .accessibilityIdentifier(
          "production-overview.\(row.id).sold-units"
        )
      }
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(DesignTokens.positive.opacity(0.18))
      .overlay(cellBorder)
      .help(
        "\(exactCount(row.soldUnits)) von \(exactCount(row.units)) Units verkauft"
      )
    } else {
      numberCell(row.soldUnits, column: column, row: rowIndex)
    }
  }

  private func rowBackground(_ row: Int) -> Color {
    row.isMultiple(of: 2) ? DesignTokens.panel : DesignTokens.elevated
  }

  private func cellBackground(
    row: Int,
    emphasis: CellEmphasis
  ) -> Color {
    switch emphasis {
    case .minimumPrice:
      DesignTokens.positive.opacity(0.2)
    case .none, .profit:
      rowBackground(row)
    }
  }

  private func valueColor(
    _ value: Double?,
    emphasis: CellEmphasis
  ) -> Color {
    guard emphasis == .profit, let value else {
      return emphasis == .minimumPrice
        ? DesignTokens.positive : DesignTokens.textPrimary
    }
    return value < 0 ? DesignTokens.negative : DesignTokens.positive
  }

  private var cellBorder: some View {
    Rectangle()
      .stroke(DesignTokens.border, lineWidth: 0.5)
  }

  private enum CellEmphasis {
    case none
    case minimumPrice
    case profit
  }

}

private enum ProductionOverviewSortColumn: Int, CaseIterable, Hashable {
  case sequence
  case date
  case product
  case runs
  case materialEfficiency
  case timeEfficiency
  case system
  case units
  case materialCost
  case installationCost
  case logisticsCost
  case blueprintCost
  case salesTax
  case brokerFee
  case productionCost
  case saleTotal
  case costPerUnit
  case minimumSalePrice
  case salePrice
  case projectedProfit
  case margin
  case soldUnits
  case realProfit
}

private func productionProjection(
  for row: StoredProductionOverviewRow
) -> ProductionOverviewRequestProjection? {
  guard
    let plan = try? JSONDecoder().decode(
      IndustryPlanSnapshot.self,
      from: row.sourceSnapshot
    )
  else { return nil }
  return ProductionOverviewProjector.projection(
    for: row.requestID,
    in: plan
  )
}

private func calculation(
  for row: StoredProductionOverviewRow,
  projection: ProductionOverviewRequestProjection? = nil
) -> ProductionOverviewCalculation {
  let acceptedProjection = projection ?? productionProjection(for: row)
  return ProductionOverviewCalculation(
    units: row.units,
    materialCost: row.materialCost,
    installationCost: row.indexCost,
    blueprintCost: row.blueprintCost,
    logisticsCost: acceptedProjection?.logisticsCost,
    salesTaxRate: acceptedProjection?.salesTaxRate,
    brokerFeeRate: acceptedProjection?.brokerFeeRate,
    salePricePerUnit: row.salePricePerUnit,
    soldUnits: row.soldUnits
  )
}

@MainActor
private func deleteProductionOverviewRow(
  _ row: StoredProductionOverviewRow,
  in modelContext: ModelContext
) throws {
  modelContext.delete(row)
  do {
    try modelContext.save()
  } catch {
    modelContext.rollback()
    throw error
  }
}

private func compactISK(
  _ value: Double?,
  includesCurrency: Bool = false
) -> String {
  guard let value, value.isFinite else { return "—" }

  let units: [(threshold: Double, suffix: String)] = [
    (1_000_000_000_000, "Bio."),
    (1_000_000_000, "Mrd."),
    (1_000_000, "Mio."),
    (1_000, "Tsd."),
  ]
  let absoluteValue = abs(value)
  let unit = units.first { absoluteValue >= $0.threshold }
  let scaledValue = unit.map { value / $0.threshold } ?? value
  let number = scaledValue.formatted(
    .number
      .locale(AppLocalization.currentLanguage.locale)
      .precision(.fractionLength(0...4))
  )
  let suffix = unit.map { " \($0.suffix.localizedUI)" } ?? ""
  return number + suffix + (includesCurrency ? " ISK" : "")
}

private func exactISK(_ value: Double) -> String {
  guard value.isFinite else { return "—" }
  return value.formatted(
    .currency(code: "ISK")
      .locale(AppLocalization.currentLanguage.locale)
      .precision(.fractionLength(0...2))
  )
}

private func sanitizedMoney(_ value: Double?) -> Double? {
  guard let value, value.isFinite else { return nil }
  return min(1_000_000_000_000_000_000, max(0, value))
}

private func compactCount(_ value: Int64) -> String {
  let units: [(threshold: Double, suffix: String)] = [
    (1_000_000_000, "Mrd."),
    (1_000_000, "Mio."),
    (1_000, "Tsd."),
  ]
  let numericValue = Double(value)
  let unit = units.first { abs(numericValue) >= $0.threshold }
  guard let unit else { return exactCount(value) }
  return (numericValue / unit.threshold).formatted(
    .number
      .locale(AppLocalization.currentLanguage.locale)
      .precision(.fractionLength(0...2))
  ) + " " + unit.suffix.localizedUI
}

private func exactCount(_ value: Int64) -> String {
  value.formatted(
    .number.locale(AppLocalization.currentLanguage.locale)
  )
}
