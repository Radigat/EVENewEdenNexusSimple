import EVENexusCore
import SwiftData
import SwiftUI

/// Stored wallet data of all characters as input of the sale detection.
struct ProductionSaleWalletData: Sendable {
  let transactions: [TradeWalletTransaction]
  let journal: [TradeWalletJournalEntry]
  let contractItems: [TradeWalletContractItem]
  /// Units of a wallet sale the trade logbook already assigned.
  let tradeAssigned: [TradeWalletLink: Int64]
  let statuses: [TradeWalletSyncStatus]
}

/// Bridges the production book and the pure sale detection.
@MainActor
enum ProductionSaleReceipts {
  private struct ProductKey: Hashable {
    let planID: UUID
    let requestID: UUID
  }

  /// Product type per recorded plan request. A plan snapshot never changes
  /// after recording, so the type is read once; `nil` marks a snapshot that
  /// no longer names the product.
  private static var productTypes: [ProductKey: Int64?] = [:]

  static func productTypeID(for row: StoredProductionOverviewRow) -> Int64? {
    let key = ProductKey(planID: row.planID, requestID: row.requestID)
    if let known = productTypes[key] { return known }
    let typeID = PlannerPersistenceController.decodePlan(row)?
      .topLevelProductNode(for: row.requestID)?.typeID
    productTypes[key] = typeID
    return typeID
  }

  /// Rows with a resolved product type; others cannot receive a receipt.
  static func saleRows(for rows: [StoredProductionOverviewRow]) -> [ProductionSaleRow] {
    rows.compactMap { row in
      guard let typeID = productTypeID(for: row) else { return nil }
      return ProductionSaleRow(
        id: row.id, sequenceNumber: row.sequenceNumber, recordedAt: row.recordedAt,
        typeID: typeID, units: row.units)
    }
  }

  static func detect(
    rows: [StoredProductionOverviewRow],
    workspace: ConsolidationWorkspace,
    data: ProductionSaleWalletData
  ) -> [DetectedProductionSale] {
    ProductionSaleDetector.detect(
      ProductionSaleDetector.Input(
        rows: saleRows(for: rows),
        workspace: workspace,
        transactions: data.transactions,
        journal: data.journal,
        contractItems: data.contractItems,
        tradeAssigned: data.tradeAssigned,
        ownCharacters: Dictionary(
          data.statuses.map { ($0.characterID, $0.characterName) },
          uniquingKeysWith: { first, _ in first })))
  }

  /// Units of wallet sales assigned to productions, read from the stored
  /// workspace so the trade logbook does not take the same sale again.
  static func walletSaleQuantities(in context: ModelContext) -> [TradeWalletLink: Int64] {
    guard
      let stored = try? context.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).first,
      let workspace = try? JSONDecoder().decode(
        ConsolidationWorkspace.self, from: stored.payload)
    else { return [:] }
    return ProductionSaleDetector.walletSaleQuantities(in: workspace)
  }

  /// Number of detected sales with a suggested production; `nil` while the
  /// wallet data cannot be read.
  static func openSuggestionCount(
    runtime: RuntimeState, workspace: ConsolidationWorkspace, context: ModelContext
  ) async -> Int? {
    guard let data = await runtime.productionSaleWalletData(),
      let rows = try? context.fetch(FetchDescriptor<StoredProductionOverviewRow>())
    else { return nil }
    return detect(rows: rows, workspace: workspace, data: data)
      .filter { $0.suggestedRowID != nil }.count
  }
}

/// Toolbar button of the production book; its title carries the number of
/// detected sales with a suggested production.
struct SaleReceiptsToolbarButton: View {
  @EnvironmentObject private var consolidation: ConsolidationController
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var modelContext
  @State private var count: Int?
  let action: () -> Void

  private struct Key: Hashable {
    let workspaceRevision: Int64
    let dataRevision: Int
  }

  var body: some View {
    Button(action: action) {
      Text(verbatim: (count ?? 0) > 0 ? "Verkaufsbelege (\(count ?? 0))" : "Verkaufsbelege")
    }
    .task(
      id: Key(
        workspaceRevision: consolidation.workspace.revision,
        dataRevision: runtime.productionSaleDataRevision)
    ) {
      count = await ProductionSaleReceipts.openSuggestionCount(
        runtime: runtime, workspace: consolidation.workspace, context: modelContext)
    }
  }
}

/// Sort key that keeps a missing value after every known value in ascending
/// and before every known value in descending order.
private struct MissingLast<Value: Comparable>: Comparable {
  let value: Value?
  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs.value, rhs.value) {
    case (let left?, let right?): left < right
    case (.some, .none): true
    default: false
    }
  }
}

private struct SaleLine: Identifiable {
  let sale: DetectedProductionSale
  let itemName: String?
  let characterName: String?
  let suggestedNumber: Int?

  var id: String { sale.id }
  var date: Date { sale.date }
  var nameKey: MissingLast<String> {
    MissingLast(value: itemName?.localizedLowercase)
  }
  var quantity: MissingLast<Int64> { MissingLast(value: sale.remainingQuantity) }
  /// Gross amount of the units still on offer.
  var offeredAmount: Double? {
    guard let gross = sale.grossAmount else { return nil }
    guard let quantity = sale.quantity, let remaining = sale.remainingQuantity,
      quantity > 0
    else { return gross }
    return gross * Double(remaining) / Double(quantity)
  }
  var amountKey: MissingLast<Double> { MissingLast(value: offeredAmount) }
  var sourceRank: Int { sale.source.rank }
  var characterKey: MissingLast<String> {
    MissingLast(value: characterName?.localizedLowercase)
  }
  var productionKey: MissingLast<Int> { MissingLast(value: suggestedNumber) }
  var issueRank: Int {
    switch sale.issue {
    case .contractItemsUnavailable: 0
    case .contractHasSeveralItems: 1
    case .transferHasNoItem: sale.senderKnown ? 2 : 3
    case nil: 4
    }
  }
}

private struct AssignedLine: Identifiable {
  let allocation: ProductionSaleAllocation
  let receipt: ProductionSaleEvidence?
  let number: Int?
  let itemName: String?
  let typeID: Int64?

  var id: UUID { allocation.id }
  var numberKey: MissingLast<Int> { MissingLast(value: number) }
  var nameKey: MissingLast<String> { MissingLast(value: itemName?.localizedLowercase) }
  var sourceKey: MissingLast<String> {
    MissingLast(value: receipt?.source.localizedLowercase)
  }
  var dateKey: MissingLast<Date> { MissingLast(value: receipt?.recordedAt) }
  var quantity: Int64 { allocation.quantity }
  var gross: Int64 { allocation.grossCents }
}

/// Sale receipts of the production book: sales detected in the stored
/// wallet data of all characters are assigned with one click.
struct ConsolidationSalesView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @Environment(RuntimeState.self) private var runtime
  @Query(sort: \StoredProductionOverviewRow.recordedAt) private var rows:
    [StoredProductionOverviewRow]

  @State private var data: ProductionSaleWalletData?
  @State private var isLoaded = false
  @State private var detected: [DetectedProductionSale] = []
  @State private var chosenRows: [String: UUID] = [:]
  @State private var chosenQuantities: [String: String] = [:]
  @State private var suggestedOrder = [KeyPathComparator(\SaleLine.date, order: .reverse)]
  @State private var unresolvedOrder = [KeyPathComparator(\SaleLine.date, order: .reverse)]
  @State private var assignedOrder = [
    KeyPathComparator(\AssignedLine.dateKey, order: .reverse)
  ]
  @State private var showsManual = false
  @State private var manualRowID: UUID?
  @State private var manualQuantity = ""
  @State private var manualPrice = ""
  @State private var manualDate = Date()

  private struct RefreshKey: Hashable {
    let dataRevision: Int
    let workspaceRevision: Int64
    let rows: [UUID]
    let units: [Int64]
  }

  private var refreshKey: RefreshKey {
    RefreshKey(
      dataRevision: runtime.productionSaleDataRevision,
      workspaceRevision: controller.workspace.revision,
      rows: rows.map(\.id), units: rows.map(\.units))
  }

  private var rowsByID: [UUID: StoredProductionOverviewRow] {
    Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  private var freeUnits: [UUID: Int64] {
    ProductionSaleDetector.freeUnits(
      in: controller.workspace, rows: ProductionSaleReceipts.saleRows(for: rows))
  }

  private var characterNames: [Int64: String] {
    Dictionary(
      (data?.statuses ?? []).map { ($0.characterID, $0.characterName) },
      uniquingKeysWith: { first, _ in first })
  }

  private func line(_ sale: DetectedProductionSale) -> SaleLine {
    let names = rowsByID
    let itemName = sale.typeID.flatMap { typeID in
      sale.candidateRowIDs.lazy.compactMap { names[$0]?.productName }.first
        ?? rows.first { ProductionSaleReceipts.productTypeID(for: $0) == typeID }?
        .productName
    }
    return SaleLine(
      sale: sale,
      itemName: itemName,
      characterName: sale.characterID.flatMap { characterNames[$0] },
      suggestedNumber: sale.suggestedRowID.flatMap { names[$0]?.sequenceNumber })
  }

  private var suggestedLines: [SaleLine] {
    detected.filter { $0.issue == nil }.map(line)
      .sorted(using: suggestedOrder + [KeyPathComparator(\SaleLine.id)])
  }

  private var unresolvedLines: [SaleLine] {
    detected.filter { $0.issue != nil }.map(line)
      .sorted(using: unresolvedOrder + [KeyPathComparator(\SaleLine.id)])
  }

  private var assignedLines: [AssignedLine] {
    let names = rowsByID
    let receipts = Dictionary(
      controller.workspace.evidence.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first })
    return controller.workspace.sales.map { allocation in
      let row = names[allocation.rowID]
      return AssignedLine(
        allocation: allocation,
        receipt: receipts[allocation.evidenceID],
        number: row?.sequenceNumber,
        itemName: row?.productName,
        typeID: row.flatMap { ProductionSaleReceipts.productTypeID(for: $0) })
    }
    .sorted(using: assignedOrder + [KeyPathComparator(\AssignedLine.id.uuidString)])
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        walletStatus
        suggestedSection
        unresolvedSection
        assignedSection
        manualSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: refreshKey) { await reload() }
  }

  // MARK: Sections

  @ViewBuilder
  private var walletStatus: some View {
    if !isLoaded {
      ProgressView().controlSize(.small)
    } else if let data {
      let missing = data.statuses.filter { $0.journalSyncedAt == nil }
      VStack(alignment: .leading, spacing: 2) {
        if data.statuses.isEmpty {
          Text(
            "No wallet data is stored yet. Synchronize the characters first; sales then appear here."
          )
          .foregroundStyle(DesignTokens.caution)
        } else {
          Text(
            AppLocalization.format(
              "Stored wallet data of %lld characters. Oldest journal status: %@.",
              Int64(data.statuses.count),
              data.statuses.compactMap(\.journalSyncedAt).min()
                .map { $0.formatted(date: .abbreviated, time: .shortened) }
                ?? AppLocalization.text("Unavailable"))
          )
          if !missing.isEmpty {
            Text(
              AppLocalization.format(
                "No wallet journal stored for: %@.",
                missing.map(\.characterName).joined(separator: ", "))
            )
            .foregroundStyle(DesignTokens.caution)
          }
        }
        Text(
          "Accepting a sale switches the production to receipts: sold units and sale price then come from the assigned receipts, the previous manual values are kept and return when the assignment is taken back."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      .appFont(.caption)
    } else {
      Text("The stored wallet data could not be read. Nothing was changed.")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.caution)
    }
  }

  @ViewBuilder
  private var suggestedSection: some View {
    let lines = suggestedLines
    let acceptable = lines.filter { assignment(for: $0) != nil }
    HStack {
      Text("Detected sales").appFont(.headline)
      Spacer()
      Button(
        AppLocalization.format("Accept all suggestions (%lld)", Int64(acceptable.count))
      ) { acceptAll(acceptable) }
      .buttonStyle(.borderedProminent)
      .disabled(acceptable.isEmpty)
      .accessibilityIdentifier("sale-receipts.accept-all")
    }
    if lines.isEmpty {
      Text(
        isLoaded
          ? "No unassigned sale of a produced item was found in the stored wallet data."
          : "Loading…"
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    } else {
      Table(lines, sortOrder: $suggestedOrder) {
        TableColumn("Date", value: \.date) { line in
          Text(line.date.formatted(date: .numeric, time: .shortened)).monospacedDigit()
        }
        .width(min: 105, ideal: 112)
        TableColumn("Item", value: \.nameKey) { line in
          itemCell(name: line.itemName, typeID: line.sale.typeID)
        }
        .width(min: 140, ideal: 165)
        TableColumn("Quantity", value: \.quantity) { line in
          Text((line.sale.remainingQuantity ?? 0).formatted()).monospacedDigit()
        }
        .width(min: 45, ideal: 52)
        TableColumn("Amount", value: \.amountKey) { line in
          amountCell(line.offeredAmount)
        }
        .width(min: 105, ideal: 122)
        TableColumn("Sale type", value: \.sourceRank) { line in
          Text(sourceText(line.sale))
        }
        .width(min: 75, ideal: 88)
        TableColumn("Character", value: \.characterKey) { line in
          characterCell(line)
        }
        .width(min: 95, ideal: 108)
        TableColumn("Production", value: \.productionKey) { line in
          productionPicker(line)
        }
        .width(min: 180, ideal: 195)
        TableColumn("Action") { line in
          HStack(spacing: DesignTokens.spacingXS) {
            Button("Accept") { accept(line) }
              .disabled(assignment(for: line) == nil)
              .accessibilityIdentifier("sale-receipts.accept.\(line.id)")
            if line.sale.source == .manual {
              Button("Discard") { discard(line) }
                .help("Deletes this unassigned manual receipt.")
            }
          }
        }
        .width(min: 105, ideal: 150)
      }
      .frame(height: tableHeight(lines.count))
    }
  }

  @ViewBuilder
  private var unresolvedSection: some View {
    let lines = unresolvedLines
    if !lines.isEmpty {
      Text("Item not recognized").appFont(.headline)
      Text(
        "These incomes name no item. Choose the production that was sold; the quantity is prefilled with its unsold units."
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      Table(lines, sortOrder: $unresolvedOrder) {
        TableColumn("Date", value: \.date) { line in
          Text(line.date.formatted(date: .numeric, time: .shortened)).monospacedDigit()
        }
        .width(min: 105, ideal: 112)
        TableColumn("Sale type", value: \.sourceRank) { line in
          Text(sourceText(line.sale))
        }
        .width(min: 80, ideal: 95)
        TableColumn("Amount", value: \.amountKey) { line in
          amountCell(line.offeredAmount)
        }
        .width(min: 105, ideal: 122)
        TableColumn("Character", value: \.characterKey) { line in
          characterCell(line)
        }
        .width(min: 95, ideal: 108)
        TableColumn("Reason", value: \.issueRank) { line in
          Text(issueText(line.sale)).lineLimit(2).help(issueText(line.sale))
        }
        .width(min: 140, ideal: 165)
        TableColumn("Production") { line in
          productionPicker(line)
        }
        .width(min: 180, ideal: 190)
        TableColumn("Quantity") { line in
          TextField("Quantity", text: quantityBinding(line))
            .groupedNumberInput(quantityBinding(line), allowsFraction: false)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
        }
        .width(min: 55, ideal: 62)
        TableColumn("Action") { line in
          Button("Accept") { accept(line) }
            .disabled(assignment(for: line) == nil)
        }
        .width(min: 80, ideal: 90)
      }
      .frame(height: tableHeight(lines.count))
    }
  }

  @ViewBuilder
  private var assignedSection: some View {
    let lines = assignedLines
    if !lines.isEmpty {
      Text("Assigned").appFont(.headline)
      Table(lines, sortOrder: $assignedOrder) {
        TableColumn("No.", value: \.numberKey) { line in
          Text(line.number.map { $0.formatted() } ?? "—").monospacedDigit()
        }
        .width(min: 36, ideal: 44)
        TableColumn("Item", value: \.nameKey) { line in
          itemCell(name: line.itemName, typeID: line.typeID)
        }
        .width(min: 150, ideal: 190)
        TableColumn("Receipt", value: \.sourceKey) { line in
          Text(line.receipt?.source ?? AppLocalization.text("Unavailable"))
            .lineLimit(1)
            .textSelection(.enabled)
        }
        .width(min: 150, ideal: 220)
        TableColumn("Date", value: \.dateKey) { line in
          Text(
            line.receipt?.recordedAt.formatted(date: .numeric, time: .shortened) ?? "—"
          )
          .monospacedDigit()
        }
        .width(min: 110, ideal: 120)
        TableColumn("Quantity", value: \.quantity) { line in
          Text(line.quantity.formatted()).monospacedDigit()
        }
        .width(min: 50, ideal: 60)
        TableColumn("Gross proceeds", value: \.gross) { line in
          amountCell(Double(line.gross) / 100)
        }
        .width(min: 110, ideal: 130)
        TableColumn("Action") { line in
          Button("Take back") { takeBack(line) }
            .accessibilityIdentifier("sale-receipts.take-back.\(line.id)")
        }
        .width(min: 100, ideal: 110)
      }
      .frame(height: tableHeight(lines.count))
      Text("Gross proceeds before sales fees.")
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  @ViewBuilder
  private var manualSection: some View {
    DisclosureGroup("Manual receipt", isExpanded: $showsManual) {
      Form {
        Picker("Production", selection: $manualRowID) {
          Text("Select").tag(Optional<UUID>.none)
          ForEach(openRows) { row in
            Text(productionLabel(row)).tag(Optional(row.id))
          }
        }
        TextField("Quantity", text: $manualQuantity)
          .groupedNumberInput($manualQuantity, allowsFraction: false)
        TextField("Unit price in ISK", text: $manualPrice)
          .groupedNumberInput($manualPrice)
        DatePicker("Receipt date", selection: $manualDate)
        Button("Create and assign") { createManual() }
          .disabled(manualRowID == nil)
      }
      .formStyle(.grouped)
    }
    .onChange(of: manualRowID) { _, rowID in
      if let rowID, let free = freeUnits[rowID] { manualQuantity = String(free) }
    }
  }

  // MARK: Cells

  @ViewBuilder
  private func itemCell(name: String?, typeID: Int64?) -> some View {
    if let name, let typeID {
      EVEItemText(value: name, typeID: typeID, lineLimit: 1, iconSize: 18)
    } else if let name {
      EVEEntityText(value: name, lineLimit: 1)
    } else {
      Text("Unresolved").foregroundStyle(DesignTokens.caution)
    }
  }

  @ViewBuilder
  private func characterCell(_ line: SaleLine) -> some View {
    if let name = line.characterName {
      EVEEntityText(value: name, font: .body, lineLimit: 1)
    } else if line.sale.characterID != nil {
      Text("Unresolved").foregroundStyle(DesignTokens.caution)
    } else {
      Text("—").foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func amountCell(_ value: Double?) -> some View {
    Text(PlannerProductFormat.isk(value))
      .monospacedDigit()
      .help(
        value.map {
          $0.formatted(
            .currency(code: "ISK")
              .locale(AppLocalization.currentLanguage.locale)
              .precision(.fractionLength(0...2)))
        } ?? AppLocalization.text("Unavailable"))
  }

  private func productionPicker(_ line: SaleLine) -> some View {
    let names = rowsByID
    let candidates = line.sale.candidateRowIDs.compactMap { names[$0] }
    return Picker(
      "Production",
      selection: Binding(
        get: { chosenRows[line.id] ?? line.sale.suggestedRowID },
        set: { rowID in
          chosenRows[line.id] = rowID
          if line.sale.typeID == nil, let rowID, let free = freeUnits[rowID] {
            chosenQuantities[line.id] = String(free)
          }
        })
    ) {
      Text("Select").tag(Optional<UUID>.none)
      ForEach(candidates) { row in
        Text(productionLabel(row)).tag(Optional(row.id))
      }
    }
    .labelsHidden()
  }

  private func quantityBinding(_ line: SaleLine) -> Binding<String> {
    Binding(
      get: { chosenQuantities[line.id] ?? "" },
      set: { chosenQuantities[line.id] = $0 })
  }

  // MARK: Texts

  private var openRows: [StoredProductionOverviewRow] {
    let free = freeUnits
    return rows.filter { free[$0.id, default: 0] > 0 }
  }

  private func productionLabel(_ row: StoredProductionOverviewRow) -> String {
    AppLocalization.format(
      "No. %lld · %@ · %lld free",
      Int64(row.sequenceNumber), row.productName, freeUnits[row.id, default: 0])
  }

  private func sourceText(_ sale: DetectedProductionSale) -> String {
    switch sale.source {
    case .market: AppLocalization.text("Market")
    case .contract: AppLocalization.text("Contract")
    case .transfer: AppLocalization.text("ISK transfer")
    case .manual: AppLocalization.text("Manual")
    }
  }

  private func issueText(_ sale: DetectedProductionSale) -> String {
    switch sale.issue {
    case .contractItemsUnavailable:
      AppLocalization.text("Contract content not available from ESI.")
    case .contractHasSeveralItems:
      AppLocalization.text("Contract holds several items; its price names no single item.")
    case .transferHasNoItem:
      sale.senderKnown
        ? AppLocalization.text("An ISK transfer names no item.")
        : AppLocalization.text("An ISK transfer names no item; sender unknown.")
    case nil: ""
    }
  }

  private func tableHeight(_ count: Int) -> CGFloat {
    CGFloat(min(max(count, 1), 8)) * 46 + 44
  }

  // MARK: Actions

  /// The assignment a click on "Accept" stores; `nil` while production or
  /// quantity are missing.
  private func assignment(for line: SaleLine) -> ProductionSaleAssignment? {
    guard let rowID = chosenRows[line.id] ?? line.sale.suggestedRowID,
      let row = rowsByID[rowID],
      let free = freeUnits[rowID], free > 0
    else { return nil }
    if let remaining = line.sale.remainingQuantity {
      let quantity =
        rowID == line.sale.suggestedRowID && chosenRows[line.id] == nil
        ? line.sale.suggestedQuantity : min(remaining, free)
      guard quantity > 0, let evidence = try? line.sale.evidence() else { return nil }
      return ProductionSaleAssignment(evidence: evidence, rowID: rowID, quantity: quantity)
    }
    guard let typeID = ProductionSaleReceipts.productTypeID(for: row),
      let quantity = Int64(GroupedNumberText.ungrouped(chosenQuantities[line.id] ?? "")),
      quantity > 0, quantity <= free,
      let evidence = try? line.sale.evidence(typeID: typeID, quantity: quantity)
    else { return nil }
    return ProductionSaleAssignment(evidence: evidence, rowID: rowID, quantity: quantity)
  }

  private func perform(_ change: () throws -> Void) {
    do {
      try change()
      controller.error = nil
    } catch {
      controller.error = error.localizedDescription
    }
  }

  private func accept(_ line: SaleLine) {
    guard let assignment = assignment(for: line) else { return }
    perform { try controller.assignSales([assignment], rows: rows) }
    chosenRows[line.id] = nil
    chosenQuantities[line.id] = nil
  }

  private func acceptAll(_ lines: [SaleLine]) {
    // Oldest sale first, so the first-in-first-out suggestion order holds.
    let assignments = lines.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
      .compactMap(assignment(for:))
    perform { try controller.assignSales(assignments, rows: rows) }
    chosenRows = [:]
  }

  private func discard(_ line: SaleLine) {
    perform { try controller.discardUnassignedReceipt(line.id) }
  }

  private func takeBack(_ line: AssignedLine) {
    perform { try controller.removeSaleAllocation(line.id) }
  }

  private func createManual() {
    perform {
      guard let rowID = manualRowID, let row = rowsByID[rowID],
        let typeID = ProductionSaleReceipts.productTypeID(for: row)
      else { throw ConsolidationError.invalid("Eine lesbare Produktion auswählen.") }
      guard let quantity = Int64(GroupedNumberText.ungrouped(manualQuantity)), quantity > 0
      else { throw ConsolidationError.invalid("Ungültige Menge.") }
      let receipt = ProductionSaleEvidence(
        id: "manual:\(UUID())", typeID: typeID, quantity: quantity,
        unitPrice: try ISKAmount.parse(GroupedNumberText.ungrouped(manualPrice)),
        recordedAt: manualDate, source: "Manueller Beleg")
      try controller.assignSales(
        [ProductionSaleAssignment(evidence: receipt, rowID: rowID, quantity: quantity)],
        rows: rows)
      manualRowID = nil
      manualQuantity = ""
      manualPrice = ""
    }
  }

  private func reload() async {
    let loaded = await runtime.productionSaleWalletData()
    data = loaded
    isLoaded = true
    detected =
      loaded.map {
        ProductionSaleReceipts.detect(
          rows: rows, workspace: controller.workspace, data: $0)
      } ?? []
  }
}
