import EVENexusCore
import SwiftData
import SwiftUI

struct RecentProductionsView: View {
  @Environment(\.modelContext) private var modelContext
  let rows: [StoredProductionOverviewRow]
  @Binding var isExpanded: Bool
  let onOpenHistoricalPlan: (StoredProductionOverviewRow) -> Void
  @State private var deletionCandidate: StoredProductionOverviewRow?
  @State private var isConfirmingDeletion = false
  @State private var persistenceError: String?

  var body: some View {
    Panel(title: "Last five productions") {
      FullWidthDisclosure(isExpanded: $isExpanded) {
        Text(
          AppLocalization.format(
            "%lld saved recent productions",
            Int64(rows.count)
          )
        )
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
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
          .frame(
            height: ProductionOverviewGrid.requiredHeight(for: rows.count)
          )

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
              "Historical rows keep the logistics and Refining result saved with that production; current settings do not rewrite them."
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

            Text(
              "For capitals that cannot be sold at the Highsec Main Hub, the broker fee remains not applicable. A known sales-tax rate still applies to an entered sale price, so minimum price and profit remain calculable."
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
        .padding(.top, DesignTokens.spacingSM)
      }
      .accessibilityIdentifier("planner.recent-productions.disclosure")
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
  @Environment(RuntimeState.self) private var runtime
  let onOpenHistoricalPlan: (StoredProductionOverviewRow) -> Void
  @State private var rows: [StoredProductionOverviewRow] = []
  @State private var summary: ProductionOverviewSummary?
  @State private var pageIndex = 0
  @State private var totalRowCount = 0
  @State private var isLoadingPage = false
  @State private var isLoadingSummary = false
  @State private var summaryRevision = 0
  @State private var saveError: String?
  @State private var deletionCandidate: StoredProductionOverviewRow?
  @State private var isConfirmingDeletion = false

  private let pageSize = 100

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
          value: summary?.rowCount.formatted() ?? "…"
        )
        summaryPanel(
          title: "Units",
          value: summary?.units.formatted() ?? "…"
        )
        summaryPanel(
          title: "Prog. Gewinn",
          value: compactISK(
            summary?.projectedProfit,
            includesCurrency: true
          ),
          exactValue: summary?.projectedProfit
        )
        summaryPanel(
          title: "Realer Gewinn",
          value: compactISK(summary?.realProfit, includesCurrency: true),
          exactValue: summary?.realProfit
        )
      }

      HStack(spacing: DesignTokens.spacingSM) {
        Button {
          pageIndex = max(0, pageIndex - 1)
          loadPage()
        } label: {
          Label("Previous page", systemImage: "chevron.left")
        }
        .disabled(pageIndex == 0 || isLoadingPage)

        Text(pageDescription)
          .font(.callout.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
          .frame(maxWidth: .infinity, alignment: .center)

        Button {
          pageIndex += 1
          loadPage()
        } label: {
          Label("Next page", systemImage: "chevron.right")
        }
        .disabled(!hasNextPage || isLoadingPage)
      }

      if isLoadingSummary {
        Label(
          "Calculating complete history totals…",
          systemImage: "sum"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      Text(
        "Only the current page is loaded and sorted in the table. The complete totals above always include the full production history."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

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
        "Historical rows keep the logistics and Refining result saved with that production; current settings do not rewrite them."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "Production costs include material, installation, BPO/BPC and logistics. Sales tax and broker fee reduce sale revenue separately."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "For capitals that cannot be sold at the Highsec Main Hub, the broker fee remains not applicable. A known sales-tax rate still applies to an entered sale price, so minimum price and profit remain calculable."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Text(
        "If a production did not record its sales-tax or broker-fee rate, the current Main Hub rate is used and shown in italics."
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
    .task {
      loadPage()
    }
    .task(id: summaryRevision) {
      await loadSummary(for: summaryRevision)
    }
    .onChange(of: runtime.productionBasis.productionOverviewFeeRates) {
      summaryRevision += 1
    }
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
      summaryRevision += 1
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
      loadPage()
      summaryRevision += 1
    } catch {
      saveError =
        "Der Produktionseintrag konnte nicht gelöscht werden: \(error.localizedDescription)"
    }
    self.deletionCandidate = nil
  }

  private var pageDescription: String {
    guard totalRowCount > 0 else {
      return AppLocalization.text("No production history")
    }
    let first = pageIndex * pageSize + 1
    let last = min(totalRowCount, first + max(0, rows.count - 1))
    return AppLocalization.format(
      "Page %lld · entries %lld–%lld of %lld",
      Int64(pageIndex + 1),
      Int64(first),
      Int64(last),
      Int64(totalRowCount)
    )
  }

  private var hasNextPage: Bool {
    (pageIndex + 1) * pageSize < totalRowCount
  }

  private func loadPage() {
    isLoadingPage = true
    defer { isLoadingPage = false }
    do {
      let page = try ProductionOverviewHistoryPager.load(
        requestedPageIndex: pageIndex,
        pageSize: pageSize,
        in: modelContext
      )
      totalRowCount = page.totalRowCount
      pageIndex = page.pageIndex
      rows = page.rows
      saveError = nil
    } catch {
      rows = []
      saveError = AppLocalization.format(
        "The production history page could not be loaded: %@",
        error.localizedDescription
      )
    }
  }

  private func loadSummary(for requestedRevision: Int) async {
    isLoadingSummary = true
    do {
      let reader = ProductionOverviewSummaryReader(
        modelContainer: modelContext.container
      )
      let loadedSummary = try await reader.load(
        currentFeeRates: runtime.productionBasis.productionOverviewFeeRates
      )
      guard !Task.isCancelled, summaryRevision == requestedRevision else {
        return
      }
      summary = loadedSummary
    } catch {
      guard !Task.isCancelled, summaryRevision == requestedRevision else {
        return
      }
      summary = nil
      saveError = AppLocalization.format(
        "The production history totals could not be loaded: %@",
        error.localizedDescription
      )
    }
    if summaryRevision == requestedRevision {
      isLoadingSummary = false
    }
  }
}

struct ProductionOverviewSummary: Sendable {
  let rowCount: Int
  let units: Int64
  let projectedProfit: Double?
  let realProfit: Double?
}

struct ProductionOverviewPage {
  let rows: [StoredProductionOverviewRow]
  let totalRowCount: Int
  let pageIndex: Int
}

@MainActor
enum ProductionOverviewHistoryPager {
  static func load(
    requestedPageIndex: Int,
    pageSize: Int,
    in modelContext: ModelContext
  ) throws -> ProductionOverviewPage {
    let acceptedPageSize = max(1, pageSize)
    let count = try modelContext.fetchCount(
      FetchDescriptor<StoredProductionOverviewRow>()
    )
    let lastPage = max(0, (count - 1) / acceptedPageSize)
    let acceptedPageIndex = min(max(0, requestedPageIndex), lastPage)
    var descriptor = FetchDescriptor<StoredProductionOverviewRow>(
      sortBy: [SortDescriptor(\.sequenceNumber), SortDescriptor(\.id)]
    )
    descriptor.fetchOffset = acceptedPageIndex * acceptedPageSize
    descriptor.fetchLimit = acceptedPageSize
    return ProductionOverviewPage(
      rows: try modelContext.fetch(descriptor),
      totalRowCount: count,
      pageIndex: acceptedPageIndex
    )
  }
}

@ModelActor
actor ProductionOverviewSummaryReader {
  func load(
    currentFeeRates: ProductionOverviewFeeRates? = nil
  ) throws -> ProductionOverviewSummary {
    let rows = try modelContext.fetch(
      FetchDescriptor<StoredProductionOverviewRow>()
    )
    let cache = ProductionOverviewProjectionCache(
      currentFeeRates: currentFeeRates
    )
    var units: Int64 = 0
    var projectedProfit: Double = 0
    var realProfit: Double = 0
    var hasCompleteProjectedProfit = true
    var hasCompleteRealProfit = true

    for row in rows {
      units += row.units
      let projection = cache.projection(for: row)
      let metrics = calculation(for: row, projection: projection)
      if let value = metrics.projectedProfit {
        projectedProfit += value
      } else {
        hasCompleteProjectedProfit = false
      }
      if let value = metrics.realProfit {
        realProfit += value
      } else {
        hasCompleteRealProfit = false
      }
    }

    return ProductionOverviewSummary(
      rowCount: rows.count,
      units: units,
      projectedProfit:
        hasCompleteProjectedProfit ? projectedProfit : nil,
      realProfit: hasCompleteRealProfit ? realProfit : nil
    )
  }
}

private struct ProductionOverviewRowContext {
  let row: StoredProductionOverviewRow
  let productTypeID: Int64?
  let projection: ProductionOverviewRequestProjection?
  let metrics: ProductionOverviewCalculation
  let targetMarket: PlannerTargetMarket?
}

final class ProductionOverviewProjectionCache {
  private struct Entry {
    let sourceSnapshot: Data
    let plan: IndustryPlanSnapshot?
    var projections: [UUID: ProductionOverviewRequestProjection]
    var missingRequestIDs: Set<UUID>
  }

  private var entries: [UUID: Entry] = [:]
  private(set) var decodedSnapshotCount = 0
  /// Current Main Hub rates that complete fee rates a stored plan did not
  /// record. Applied on read, so the cached plan projections stay unchanged.
  var currentFeeRates: ProductionOverviewFeeRates?

  init(currentFeeRates: ProductionOverviewFeeRates? = nil) {
    self.currentFeeRates = currentFeeRates
  }

  func retainSnapshots(for rows: [StoredProductionOverviewRow]) {
    let planIDs = Set(rows.map(\.planID))
    entries = entries.filter { planIDs.contains($0.key) }
  }

  func projection(
    for row: StoredProductionOverviewRow
  ) -> ProductionOverviewRequestProjection? {
    storedProjection(for: row)?.fillingMissingFeeRates(from: currentFeeRates)
  }

  private func storedProjection(
    for row: StoredProductionOverviewRow
  ) -> ProductionOverviewRequestProjection? {
    var entry: Entry
    if let cached = entries[row.planID],
      cached.sourceSnapshot == row.sourceSnapshot
    {
      entry = cached
    } else {
      decodedSnapshotCount += 1
      entry = Entry(
        sourceSnapshot: row.sourceSnapshot,
        plan: try? JSONDecoder().decode(
          IndustryPlanSnapshot.self,
          from: row.sourceSnapshot
        ),
        projections: [:],
        missingRequestIDs: []
      )
    }

    if let projection = entry.projections[row.requestID] {
      entries[row.planID] = entry
      return projection
    }
    guard !entry.missingRequestIDs.contains(row.requestID),
      let plan = entry.plan,
      let projection = ProductionOverviewProjector.projection(
        for: row.requestID,
        in: plan
      )
    else {
      entry.missingRequestIDs.insert(row.requestID)
      entries[row.planID] = entry
      return nil
    }
    entry.projections[row.requestID] = projection
    entries[row.planID] = entry
    return projection
  }

  func productTypeID(for row: StoredProductionOverviewRow) -> Int64? {
    _ = storedProjection(for: row)
    return entries[row.planID]?.plan?.topLevelProductNode(
      for: row.requestID
    )?.typeID
  }

  /// Target market recorded in the row's plan snapshot; `nil` for rows saved
  /// before P10 or without a choice.
  func targetMarket(for row: StoredProductionOverviewRow) -> PlannerTargetMarket? {
    _ = storedProjection(for: row)
    return entries[row.planID]?.plan?.targetMarket
  }
}

/// Grid text and documented sort rank of a target market (P10).
enum ProductionOverviewTargetMarketPresentation {
  static func text(_ market: PlannerTargetMarket?) -> String {
    switch market {
    case .mainHub: "Main Hub"
    case .homeHub: "Home Hub"
    case .coalitionHub: "Coalition Hub"
    case .allianceMarket: AppLocalization.text("Alliance market")
    case nil: AppLocalization.text("Not chosen")
    }
  }

  /// Main, Home, Coalition, Alliance; an unchosen market stays unknown (`nil`).
  static func rank(_ market: PlannerTargetMarket?) -> Int? {
    switch market {
    case .mainHub: 0
    case .homeHub: 1
    case .coalitionHub: 2
    case .allianceMarket: 3
    case nil: nil
    }
  }
}

private struct ProductionOverviewGrid: View {
  @EnvironmentObject private var consolidation: ConsolidationController
  @Environment(RuntimeState.self) private var runtime
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
  @State private var projectionCache = ProductionOverviewProjectionCache()

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
    ("Ziel", "Zielmarkt"),
  ]

  private let widthWeights: [CGFloat] = [
    28, 50, 88, 34, 24, 24, 52, 36, 48, 46, 44, 48, 42, 42, 52,
    54, 50, 54, 54, 54, 42, 52, 52, 48,
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

      ForEach(
        Array(sortedContexts.enumerated()),
        id: \.element.row.id
      ) { offset, context in
        let row = context.row
        let projection = context.projection
        let metrics = context.metrics
        GridRow {
          textCell(row.sequenceNumber.formatted(), column: 0, row: offset)
          textCell(
            row.recordedAt.formatted(
              .dateTime.day().month().year(.twoDigits)
            ),
            column: 1,
            row: offset
          )
          itemCell(
            row.productName,
            typeID: context.productTypeID,
            column: 2,
            row: offset
          )
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
          moneyCell(
            metrics.salesTax,
            column: 12,
            row: offset,
            isCurrentSetting: projection?.salesTaxRateIsCurrentSetting == true
          )
          moneyCell(
            metrics.brokerFee,
            column: 13,
            row: offset,
            isCurrentSetting: projection?.brokerFeeRateIsCurrentSetting == true
          )
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
          textCell(
            ProductionOverviewTargetMarketPresentation.text(context.targetMarket),
            column: 23,
            row: offset
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

  private var sortedContexts: [ProductionOverviewRowContext] {
    projectionCache.retainSnapshots(for: rows)
    projectionCache.currentFeeRates =
      runtime.productionBasis.productionOverviewFeeRates
    let contexts = rows.map { row in
      let projection = projectionCache.projection(for: row)
      return ProductionOverviewRowContext(
        row: row,
        productTypeID: projectionCache.productTypeID(for: row),
        projection: projection,
        metrics: calculation(for: row, projection: projection),
        targetMarket: projectionCache.targetMarket(for: row)
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
      case .targetMarket:
        ordered = compareOptional(
          ProductionOverviewTargetMarketPresentation.rank(lhsContext.targetMarket),
          ProductionOverviewTargetMarketPresentation.rank(rhsContext.targetMarket)
        )
      }
      return ordered ?? (lhs.id.uuidString < rhs.id.uuidString)
    }
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
    case (let lhs?, let rhs?): return compare(lhs, rhs)
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

  @ViewBuilder
  private func itemCell(
    _ value: String,
    typeID: Int64?,
    column: Int,
    row: Int
  ) -> some View {
    Group {
      if let typeID {
        EVEItemText(
          value: value,
          typeID: typeID,
          lineLimit: 1,
          iconSize: 18
        )
      } else {
        EVEEntityText(value: value, lineLimit: 1)
      }
    }
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
    emphasis: CellEmphasis = .none,
    isCurrentSetting: Bool = false
  ) -> some View {
    Text(compactISK(value))
      .font(.caption.monospacedDigit())
      .italic(isCurrentSetting && value != nil)
      .lineLimit(1)
      .minimumScaleFactor(0.55)
      .foregroundStyle(valueColor(value, emphasis: emphasis))
      .help(moneyHelp(value, isCurrentSetting: isCurrentSetting))
      .frame(
        width: widths[column],
        alignment: .trailing
      )
      .frame(minHeight: 28)
      .padding(.horizontal, cellHorizontalPadding)
      .background(cellBackground(row: row, emphasis: emphasis))
      .overlay(cellBorder)
  }

  private func moneyHelp(_ value: Double?, isCurrentSetting: Bool) -> String {
    guard let value else { return "Wert nicht verfügbar" }
    guard isCurrentSetting else { return exactISK(value) }
    return AppLocalization.format(
      "%@ · Rate from the current Main Hub settings; this production did not record it.",
      exactISK(value)
    )
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
    if isEditable && !consolidation.workspace.costs.contains(where: { $0.id == row.id }) {
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
    if isEditable && !consolidation.workspace.costs.contains(where: { $0.id == row.id && $0.evidenceMode }) {
      TextField(
        "",
        value: Binding(
          get: { row.salePricePerUnit },
          set: {
            row.salePricePerUnit = sanitizedMoney($0)
            row.marketTax =
              calculation(
                for: row,
                projection: projectionCache.projection(for: row)
              ).salesTax
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
    if isEditable && !consolidation.workspace.costs.contains(where: { $0.id == row.id && $0.evidenceMode }) {
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
  case targetMarket
}

private func calculation(
  for row: StoredProductionOverviewRow,
  projection: ProductionOverviewRequestProjection?
) -> ProductionOverviewCalculation {
  return ProductionOverviewCalculation(
    units: row.units,
    materialCost: row.materialCost,
    installationCost: row.indexCost,
    blueprintCost: row.blueprintCost,
    logisticsCost: projection?.logisticsCost,
    salesTaxRate: projection?.salesTaxRate,
    brokerFeeRate: projection?.brokerFeeRate,
    brokerFeeIsApplicable: projection?.brokerFeeIsApplicable ?? true,
    salePricePerUnit: row.salePricePerUnit,
    soldUnits: row.soldUnits
  )
}

@MainActor
private func deleteProductionOverviewRow(
  _ row: StoredProductionOverviewRow,
  in modelContext: ModelContext
) throws {
  if let stored = try modelContext.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).first {
    let workspace = try JSONDecoder().decode(ConsolidationWorkspace.self, from: stored.payload)
    guard !workspace.sales.contains(where: { $0.rowID == row.id }) else {
      throw ConsolidationError.invalid("Die Produktion besitzt bestätigte Verkaufsbelege und bleibt als Nachweis erhalten.")
    }
  }
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
