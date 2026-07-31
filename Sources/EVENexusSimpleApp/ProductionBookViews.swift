import EVENexusCore
import SwiftData
import SwiftUI

struct RecentProductionsView: View {
  @Environment(\.modelContext) private var modelContext
  let rows: [StoredProductionOverviewRow]
  @State private var deletionCandidate: StoredProductionOverviewRow?
  @State private var isConfirmingDeletion = false
  @State private var deletionError: String?

  var body: some View {
    Panel(title: "Last five productions") {
      GeometryReader { geometry in
        ProductionOverviewGrid(
          rows: rows,
          isEditable: false,
          availableWidth: geometry.size.width,
          onRequestDelete: requestDeletion
        )
        .frame(maxHeight: .infinity, alignment: .top)
      }
      .frame(height: ProductionOverviewGrid.requiredHeight(for: rows.count))

      if let deletionError {
        Label(deletionError, systemImage: "trash.slash")
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }

      if !rows.isEmpty {
        Text(
          "Gerundete Beträge zeigen beim Darüberfahren mit der Maus den genauen ISK-Wert."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

        Text(
          "The complete table and editable sales fields are available under Production Overview."
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

  private func confirmDeletion() {
    guard let deletionCandidate else { return }
    do {
      try deleteProductionOverviewRow(
        deletionCandidate,
        in: modelContext
      )
      deletionError = nil
    } catch {
      deletionError =
        "Der Produktionseintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
    }
    self.deletionCandidate = nil
  }
}

struct ProductionBookView: View {
  @Environment(\.modelContext) private var modelContext
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

      HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
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

      GeometryReader { geometry in
        ScrollView(.vertical) {
          ProductionOverviewGrid(
            rows: rows,
            isEditable: true,
            availableWidth: geometry.size.width,
            onSave: save,
            onRequestDelete: requestDeletion
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
      saveError = error.localizedDescription
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
  @FocusState private var focusedField: EditableField?

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
    ("Index", "Indexkosten"),
    ("BPO/BPC", "BPO/BPC-Kosten"),
    ("Tax", "Markttax"),
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
    28, 50, 94, 36, 26, 26, 56, 40, 50, 46, 50, 42, 52, 54, 50,
    54, 54, 54, 42, 42, 52,
  ]

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
          Text(headers[index].short)
            .font(.system(size: 9, weight: .semibold))
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

      ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
        let metrics = calculation(for: row)
        GridRow {
          textCell(row.sequenceNumber.formatted(), column: 0, row: offset)
          textCell(
            row.recordedAt.formatted(
              .dateTime.day().month().year(.twoDigits)
            ),
            column: 1,
            row: offset
          )
          textCell(row.productName, column: 2, row: offset)
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
          textCell(row.systemName, column: 6, row: offset)
          numberCell(row.units, column: 7, row: offset)
          moneyCell(row.materialCost, column: 8, row: offset)
          moneyCell(row.indexCost, column: 9, row: offset)
          editableMoneyCell(
            row,
            keyPath: \.blueprintCost,
            column: 10,
            rowIndex: offset
          )
          moneyCell(row.marketTax, column: 11, row: offset)
          moneyCell(metrics.productionCost, column: 12, row: offset)
          moneyCell(metrics.saleTotal, column: 13, row: offset)
          moneyCell(metrics.costPerUnit, column: 14, row: offset)
          moneyCell(
            metrics.minimumSalePricePerUnit,
            column: 15,
            row: offset,
            emphasis: .minimumPrice
          )
          editableSalePriceCell(row, column: 16, rowIndex: offset)
          moneyCell(
            metrics.projectedProfit,
            column: 17,
            row: offset,
            emphasis: .profit
          )
          percentageCell(metrics.margin, column: 18, row: offset)
          editableSoldCell(row, column: 19, rowIndex: offset)
          moneyCell(
            metrics.realProfit,
            column: 20,
            row: offset,
            emphasis: .profit
          )
        }
        .contentShape(Rectangle())
        .contextMenu {
          Button(role: .destructive) {
            onRequestDelete(row)
          } label: {
            Label("Eintrag löschen…", systemImage: "trash")
          }
        }
        .accessibilityAction(named: "Eintrag löschen") {
          onRequestDelete(row)
        }
      }
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
      let field = EditableField.blueprintCost(row.id)
      Group {
        if focusedField == field {
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
          .focused($focusedField, equals: field)
          .onSubmit { focusedField = nil }
        } else {
          compactEditButton(
            value: compactISK(row[keyPath: keyPath]),
            field: field
          )
        }
      }
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
      let field = EditableField.salePrice(row.id)
      Group {
        if focusedField == field {
          TextField(
            "",
            value: Binding(
              get: { row.salePricePerUnit },
              set: {
                row.salePricePerUnit = sanitizedMoney($0)
                onSave()
              }
            ),
            format: .number.precision(.fractionLength(0...2))
          )
          .textFieldStyle(.plain)
          .font(.caption.monospacedDigit())
          .multilineTextAlignment(.trailing)
          .focused($focusedField, equals: field)
          .onSubmit { focusedField = nil }
        } else {
          compactEditButton(
            value: compactISK(row.salePricePerUnit),
            field: field
          )
        }
      }
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
      let field = EditableField.soldUnits(row.id)
      Group {
        if focusedField == field {
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
          .focused($focusedField, equals: field)
          .onSubmit { focusedField = nil }
        } else {
          compactEditButton(
            value: compactCount(row.soldUnits),
            field: field
          )
        }
      }
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(DesignTokens.positive.opacity(0.18))
      .overlay(cellBorder)
      .help(exactCount(row.soldUnits))
    } else {
      numberCell(row.soldUnits, column: column, row: rowIndex)
    }
  }

  private func compactEditButton(
    value: String,
    field: EditableField
  ) -> some View {
    Button {
      focusedField = field
    } label: {
      Text(value)
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Zum Bearbeiten aktivieren")
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

  private enum EditableField: Hashable {
    case blueprintCost(UUID)
    case salePrice(UUID)
    case soldUnits(UUID)
  }
}

private func calculation(
  for row: StoredProductionOverviewRow
) -> ProductionOverviewCalculation {
  ProductionOverviewCalculation(
    units: row.units,
    materialCost: row.materialCost,
    indexCost: row.indexCost,
    blueprintCost: row.blueprintCost,
    marketTax: row.marketTax,
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
