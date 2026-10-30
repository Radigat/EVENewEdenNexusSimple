import EVENexusCore
import SwiftData
import SwiftUI

enum TradeLogbookText {
  static func status(_ status: TradeLogbookStatus) -> String {
    switch status {
    case .bought: AppLocalization.text("Bought")
    case .inTransit: AppLocalization.text("In transit")
    case .listed: AppLocalization.text("Listed")
    case .sold: AppLocalization.text("Sold")
    case .manufacturingIgnored: AppLocalization.text("Production")
    case .consumed: AppLocalization.text("Consumption")
    case .excluded: AppLocalization.text("Excluded")
    }
  }

  static func usage(_ usage: TradeLogbookUsage) -> String {
    switch usage {
    case .sale(let role):
      AppLocalization.format("Sale at %@", TradeHubText.roleName(role))
    case .production: AppLocalization.text("Production")
    case .consumption: AppLocalization.text("Consumption")
    }
  }

  static func buySide(_ side: TradeQuoteSide) -> String {
    switch side {
    case .minSell: AppLocalization.text("Instant buy (Min-Sell)")
    case .maxBuy: AppLocalization.text("Own buy order (Max-Buy)")
    }
  }

  static func saleKind(_ kind: TradeSaleKind) -> String {
    switch kind {
    case .listedSellOrder: AppLocalization.text("Own sell order")
    case .directToBuyOrder: AppLocalization.text("Direct sale to buy order")
    }
  }
}

/// Materials of active Planner plans; their wallet purchases are marked
/// "manufacturing, ignored" (HANDEL_PLAN U7).
@MainActor
enum TradePlannerMaterials {
  static func typeIDs(in modelContext: ModelContext) -> Set<Int64> {
    let descriptor = FetchDescriptor<StoredPlan>(
      predicate: #Predicate { $0.isActive }
    )
    let plans = (try? modelContext.fetch(descriptor)) ?? []
    return Set(
      plans.compactMap(PlannerPersistenceController.decodePlan)
        .flatMap { $0.materials.map(\.typeID) }
    )
  }
}

/// Locale-aware number input: empty text means unknown (`nil`), never zero.
enum TradeNumberText {
  static var locale: Locale { AppLocalization.currentLanguage.locale }

  static func parse(_ text: String) -> Double? {
    let trimmed = GroupedNumberText.ungrouped(text, locale: locale)
    guard !trimmed.isEmpty else { return nil }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    if let number = formatter.number(from: trimmed) {
      return number.doubleValue
    }
    return Double(trimmed.replacingOccurrences(of: ",", with: "."))
  }

  static func format(_ value: Double?, fractionDigits: Int = 2) -> String {
    value.map {
      $0.formatted(
        .number.precision(.fractionLength(0...fractionDigits)).locale(locale)
      )
    } ?? ""
  }

  static func percentText(_ rate: Double?) -> String {
    format(rate.map { $0 * 100 }, fractionDigits: 4)
  }

  static func rate(_ percentText: String) -> Double? {
    parse(percentText).map { $0 / 100 }
  }
}

/// Opens the editor; `transportForQuantity` recalculates the transport of
/// a prefilled Trade row for the entered quantity.
struct TradeLogbookEditorRequest: Identifiable {
  let id = UUID()
  let entry: TradeLogbookEntry
  let isNew: Bool
  var packagedVolume: Double? = nil
  var transportBasis: TradeTransportBasis? = nil
}

struct TradeLogbookView: View {
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var modelContext
  @Query private var characters: [StoredCharacter]
  @State private var isSyncingWallets = false
  @State private var walletSyncMessage: String?
  @AppStorage("trade-logbook.filter", store: AppDefaults.store)
  private var filterRawValue = "open"
  @State private var editorRequest: TradeLogbookEditorRequest?
  @State private var pendingDeletion: TradeLogbookEntry?
  @State private var sort = AppTableSortDescriptor(
    column: TradeLogbookSortColumn.purchasedAt,
    direction: .descending
  )

  private let numberWidth: CGFloat = 96

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        header
        if let error = runtime.tradeLogbookError {
          Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.negative)
        }
        walletPanel
        unassignedPanel
        content
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      if runtime.tradeLogbookState == .notLoaded {
        await runtime.loadTradeLogbook()
      }
      await runtime.reconcileTradeLogbook(
        manufacturingTypeIDs: TradePlannerMaterials.typeIDs(in: modelContext)
      )
    }
    .sheet(item: $editorRequest) { request in
      TradeLogbookEditor(request: request)
        .environment(runtime)
    }
    .confirmationDialog(
      "Delete logbook entry?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        guard let entry = pendingDeletion else { return }
        pendingDeletion = nil
        Task { await runtime.deleteTradeLogbookEntry(id: entry.id) }
      }
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("The purchase and all its recorded sales are removed from the logbook.")
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Trade logbook")
          .font(.largeTitle.bold())
          .foregroundStyle(DesignTokens.textPrimary)
        Text(
          "Logged purchases with planned and realized sale prices. Rates are frozen when an entry is created; unknown values stay empty."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
      Button {
        editorRequest = TradeLogbookEditorRequest(
          entry: newManualEntry(),
          isNew: true
        )
      } label: {
        Label("New entry", systemImage: "plus")
      }
      .disabled(runtime.tradeLogbookState == .loading)
      .accessibilityIdentifier("trade-logbook.new")
    }
  }

  @ViewBuilder
  private var content: some View {
    let isEmpty = runtime.tradeLogbookEntries.isEmpty
    // Before the first load, and while reloading an empty logbook.
    let isLoading =
      runtime.tradeLogbookState == .notLoaded
      || (runtime.tradeLogbookState == .loading && isEmpty)
    switch runtime.tradeLogbookState {
    case _ where isLoading:
      ProgressView("Loading logbook…")
        .frame(maxWidth: .infinity, minHeight: 160)
    case .failed where isEmpty:
      ContentUnavailableView(
        "Logbook unavailable",
        systemImage: "book.closed",
        description: Text("The logbook file could not be opened.")
      )
    default:
      if runtime.tradeLogbookEntries.isEmpty {
        ContentUnavailableView(
          "No logbook entries yet",
          systemImage: "book.closed",
          description: Text(
            "Add purchases with “Add to logbook” in the Trade area or with “New entry”."
          )
        )
        .frame(maxWidth: .infinity, minHeight: 240)
      } else {
        Panel(title: "Purchases") {
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            filterBar
            ScrollView(.horizontal) {
              VStack(alignment: .leading, spacing: 0) {
                tableHeader
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                  ForEach(visibleEntries) { entry in
                    row(entry)
                    Divider().opacity(0.4)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // MARK: Wallet data (HANDEL_PLAN P6)

  private struct WalletCharacterRow: Identifiable {
    let id: Int64
    let name: String
    let status: TradeWalletSyncStatus?
  }

  private var walletRows: [WalletCharacterRow] {
    var rows = Dictionary(
      uniqueKeysWithValues: runtime.tradeWalletStatuses.map {
        ($0.characterID, WalletCharacterRow(id: $0.characterID, name: $0.characterName, status: $0))
      }
    )
    for character in characters where rows[character.characterID] == nil {
      rows[character.characterID] = WalletCharacterRow(
        id: character.characterID,
        name: character.characterName,
        status: nil
      )
    }
    return rows.values.sorted {
      let order = $0.name.localizedCaseInsensitiveCompare($1.name)
      return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
    }
  }

  private var walletPanel: some View {
    Panel(title: "Wallet data") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(alignment: .top) {
          Text(
            "Personal wallet transactions, the wallet journal and own orders of every authorized character are stored after each character sync, beyond the 30-day ESI window."
          )
          .font(.callout)
          .foregroundStyle(DesignTokens.textSecondary)
          Spacer()
          Button {
            Task { await syncWallets() }
          } label: {
            if isSyncingWallets {
              ProgressView().controlSize(.small)
            } else {
              Label("Sync wallets", systemImage: "arrow.triangle.2.circlepath")
            }
          }
          .disabled(isSyncingWallets || characters.isEmpty)
          .accessibilityIdentifier("trade-logbook.sync-wallets")
        }
        HStack(spacing: DesignTokens.spacingSM) {
          DatePicker(
            "Import purchases from",
            selection: Binding(
              get: { runtime.tradeWalletImportStart ?? Date() },
              set: { date in Task { await runtime.setTradeWalletImportStart(date) } }
            ),
            displayedComponents: .date
          )
          .fixedSize()
          .accessibilityIdentifier("trade-logbook.import-start")
          if runtime.isReconcilingTradeLogbook {
            ProgressView().controlSize(.small)
          }
        }
        Text(
          "Purchases in the Main, Home and Coalition Hub from this date become logbook entries; sales are assigned first-in-first-out per item and target hub. An own order is detected from the order history; otherwise a purchase counts as instant and a sale as own sell order (assumed)."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        if runtime.tradeUnresolvedPurchaseCount > 0 {
          Label(
            AppLocalization.format(
              "%lld purchases were not imported because the static data catalog cannot name their item.",
              Int64(runtime.tradeUnresolvedPurchaseCount)
            ),
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(DesignTokens.caution)
        }
        if let walletSyncMessage {
          Text(walletSyncMessage).font(.callout)
        }
        if let error = runtime.tradeWalletError {
          Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.negative)
        }
        if walletRows.isEmpty {
          Text("No authorized characters. Add a character under Data & Settings.")
            .foregroundStyle(DesignTokens.textSecondary)
        }
        ForEach(walletRows) { row in
          walletStatusRow(row)
        }
      }
    }
  }

  private func walletStatusRow(_ row: WalletCharacterRow) -> some View {
    HStack(spacing: DesignTokens.spacingMD) {
      EVEEntityText(value: row.name, font: .callout, lineLimit: 1)
        .frame(width: 220, alignment: .leading)
      if let status = row.status {
        Label(
          walletStateText(status),
          systemImage: status.transactionsState == .fresh
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(
          status.transactionsState == .fresh ? DesignTokens.positive : DesignTokens.caution
        )
        .frame(width: 260, alignment: .leading)
        Text(
          status.transactionsSyncedAt.map {
            AppLocalization.format(
              "Stored up to %@",
              $0.formatted(date: .abbreviated, time: .shortened)
            )
          } ?? AppLocalization.text("No wallet data stored yet")
        )
        .frame(width: 220, alignment: .leading)
        Text(
          AppLocalization.format(
            "%lld transactions · %lld journal entries",
            Int64(status.storedTransactionCount),
            Int64(status.storedJournalCount)
          )
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Text("Not yet synchronized")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
    }
    .font(.callout)
  }

  private func walletStateText(_ status: TradeWalletSyncStatus) -> String {
    let state = status.transactionsState
    if state == .forbidden {
      return AppLocalization.text("Wallet permission missing")
    }
    return AppLocalization.format(
      "Last sync: %@",
      StartupDataStatusSection.freshnessText(state)
    )
  }

  private func syncWallets() async {
    guard !isSyncingWallets else { return }
    isSyncingWallets = true
    walletSyncMessage = nil
    defer { isSyncingWallets = false }
    let result = await CharacterBatchSynchronizer.synchronize(
      characters: characters,
      runtime: runtime,
      modelContext: modelContext
    )
    walletSyncMessage = AppLocalization.format(
      "%lld of %lld characters synchronized.",
      Int64(result.synchronizedCount),
      Int64(result.totalCount)
    )
  }

  // MARK: Unassigned sales (HANDEL_PLAN P7)

  @ViewBuilder
  private var unassignedPanel: some View {
    if !runtime.tradeUnassignedSales.isEmpty {
      Panel(title: "Unassigned sales") {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Text(
            "Sales of logged items that no open purchase with this target hub took. Assign them manually if they belong to a purchase."
          )
          .font(.callout)
          .foregroundStyle(DesignTokens.textSecondary)
          ForEach(runtime.tradeUnassignedSales) { sale in
            unassignedRow(sale)
          }
        }
      }
    }
  }

  private func unassignedRow(_ sale: TradeUnassignedSale) -> some View {
    let candidates = runtime.tradeLogbookEntries.filter {
      $0.typeID == sale.typeID && $0.openQuantity > 0
    }
    let name = runtime.tradeLogbookEntries.first { $0.typeID == sale.typeID }?.typeName
    return HStack(spacing: DesignTokens.spacingMD) {
      Text(sale.date.formatted(date: .abbreviated, time: .shortened))
        .frame(width: 130, alignment: .leading)
      Group {
        if let name {
          EVEItemText(value: name, typeID: sale.typeID, font: .callout, lineLimit: 1, iconSize: 18)
        } else {
          Text("Unresolved item").foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .frame(width: 220, alignment: .leading)
      Text(
        AppLocalization.format(
          "%@ of %@ × %@ ISK",
          TradeNumberText.format(Double(sale.remainingQuantity), fractionDigits: 0),
          TradeNumberText.format(Double(sale.totalQuantity), fractionDigits: 0),
          TradeNumberText.format(sale.unitPrice)
        )
      )
      .monospacedDigit()
      .frame(width: 200, alignment: .leading)
      Text(
        verbatim: sale.hubRoles.first.map(TradeHubText.roleName)
          ?? AppLocalization.text("Place outside the configured hubs")
      )
      .frame(width: 200, alignment: .leading)
      Text(verbatim: sourceLabel(TradeLogbookText.saleKind(sale.kind), sale.kindSource))
        .foregroundStyle(DesignTokens.textSecondary)
      Spacer()
      Menu("Assign") {
        ForEach(candidates) { entry in
          Button(
            AppLocalization.format(
              "%@ · %@ open · %@",
              entry.purchasedAt.formatted(date: .abbreviated, time: .omitted),
              TradeNumberText.format(Double(entry.openQuantity), fractionDigits: 0),
              TradeHubText.roleName(entry.targetRole)
            )
          ) {
            Task { await runtime.assignTradeSale(sale, to: entry.id) }
          }
        }
      }
      .disabled(candidates.isEmpty)
      .fixedSize()
      .accessibilityIdentifier("trade-logbook.unassigned.assign.\(sale.id)")
    }
    .font(.callout)
  }

  private func sourceLabel(_ text: String, _ source: TradeValueSource) -> String {
    switch source {
    case .manual: text
    case .detected: AppLocalization.format("%@ (detected)", text)
    case .assumed: AppLocalization.format("%@ (assumed)", text)
    }
  }

  // MARK: Filter

  private var filterBar: some View {
    let open = runtime.tradeLogbookEntries.filter { $0.openQuantity > 0 }
    let reached = open.filter {
      if case .reached = $0.reminder(currentBestSell: currentBestSell($0)) {
        return true
      }
      return false
    }
    return HStack(spacing: DesignTokens.spacingMD) {
      Picker("Show", selection: $filterRawValue) {
        Text("Open entries").tag("open")
        Text("All entries").tag("all")
        Divider()
        ForEach(TradeLogbookStatus.allCases, id: \.self) { status in
          Text(verbatim: TradeLogbookText.status(status)).tag(status.rawValue)
        }
      }
      .frame(maxWidth: 260)
      .accessibilityIdentifier("trade-logbook.filter")
      Text(
        AppLocalization.format(
          "%lld open entries · %lld at or above the planned sale price",
          Int64(open.count),
          Int64(reached.count)
        )
      )
      .font(.callout)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var visibleEntries: [TradeLogbookEntry] {
    let filtered = runtime.tradeLogbookEntries.filter { entry in
      switch filterRawValue {
      case "open": entry.openQuantity > 0
      case "all": true
      default: entry.status.rawValue == filterRawValue
      }
    }
    let prices = Dictionary(
      uniqueKeysWithValues: filtered.compactMap { entry in
        currentBestSell(entry).map { (entry.id, $0) }
      }
    )
    return TradeLogbookSorter.sorted(
      filtered,
      by: sort.column,
      ascending: sort.direction == .ascending,
      currentBestSell: prices
    )
  }

  private func currentBestSell(_ entry: TradeLogbookEntry) -> Double? {
    runtime.tradeMarketState(for: entry.targetRole)?.value?
      .pricesByType[entry.typeID]?.bestSellPrice
  }

  // MARK: Table

  private var tableHeader: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      Spacer().frame(width: 52)
      header("Purchased", .purchasedAt, width: 104, alignment: .leading)
      SortableTableHeader(title: "Item", column: TradeLogbookSortColumn.item, sort: $sort)
        .frame(width: 200, alignment: .leading)
      header("Quantity", .quantity)
      header("Open", .openQuantity)
      header("Buy price", .buyUnitPrice)
      header("Cost/unit", .costPerUnit)
      header("Target hub", .targetHub, width: 120, alignment: .leading)
      header("Planned sale", .plannedSellUnitPrice)
      header("Average sale", .averageSalePrice)
      header("Current best sell", .currentBestSell, width: 120)
      Text("Reminder").frame(width: 140, alignment: .leading)
      header("Planned profit", .plannedProfit, width: 120)
      header("Realized profit", .realizedProfit, width: 120)
      header("Status", .status, width: 140, alignment: .leading)
      Text("Notes").frame(width: 70, alignment: .leading)
    }
    .font(.caption.weight(.semibold))
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private func header(
    _ title: LocalizedStringKey,
    _ column: TradeLogbookSortColumn,
    width: CGFloat? = nil,
    alignment: Alignment = .trailing
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      defaultDirection: .descending,
      alignment: alignment
    )
    .frame(width: width ?? numberWidth, alignment: alignment)
  }

  private func row(_ entry: TradeLogbookEntry) -> some View {
    let current = currentBestSell(entry)
    let reminder = entry.reminder(currentBestSell: current)
    let highlight: Bool = {
      if case .reached = reminder, entry.openQuantity > 0 { return true }
      return false
    }()
    return HStack(spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingXS) {
        Button {
          editorRequest = TradeLogbookEditorRequest(entry: entry, isNew: false)
        } label: {
          Image(systemName: "pencil")
        }
        .help(AppLocalization.text("Edit entry"))
        .accessibilityLabel("Edit entry")
        .accessibilityIdentifier("trade-logbook.edit.\(entry.typeID)")
        Button {
          pendingDeletion = entry
        } label: {
          Image(systemName: "trash")
        }
        .help(AppLocalization.text("Delete entry"))
        .accessibilityLabel("Delete entry")
      }
      .buttonStyle(.borderless)
      .frame(width: 52)
      Text(entry.purchasedAt.formatted(date: .abbreviated, time: .shortened))
        .font(.callout)
        .frame(width: 104, alignment: .leading)
      EVEItemText(
        value: entry.typeName,
        typeID: entry.typeID,
        font: .callout,
        lineLimit: 1,
        iconSize: 18
      )
      .frame(width: 200, alignment: .leading)
      number(TradeNumberText.format(Double(entry.quantity), fractionDigits: 0))
      number(TradeNumberText.format(Double(entry.openQuantity), fractionDigits: 0))
      number(TradeNumberText.format(entry.buyUnitPrice))
      number(dash(TradeNumberText.format(entry.costPerUnit)))
      Group {
        if case .sale = entry.usage, let name = entry.targetLocationName {
          EVEEntityText(value: name, font: .callout, lineLimit: 1)
        } else if case .sale(let role) = entry.usage {
          Text(verbatim: TradeHubText.roleName(role)).font(.callout)
        } else {
          Text(verbatim: TradeLogbookText.usage(entry.usage))
            .font(.callout)
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .frame(width: 120, alignment: .leading)
      number(dash(TradeNumberText.format(entry.plannedSellUnitPrice)))
      number(
        dash(TradeNumberText.format(entry.averageSalePrice)),
        tint: (entry.saleDeviationFromPlan ?? 0) < 0
          ? DesignTokens.caution : DesignTokens.textPrimary
      )
      .help(
        entry.saleDeviationFromPlan.map {
          AppLocalization.format(
            "%@ compared with the planned sale price",
            $0.formatted(.percent.precision(.fractionLength(1)).locale(TradeNumberText.locale))
          )
        } ?? ""
      )
      number(dash(TradeNumberText.format(current)), width: 120)
      reminderCell(reminder, planned: entry.plannedSellUnitPrice)
      number(dash(TradeNumberText.format(entry.plannedProfit)), width: 120)
      number(
        dash(TradeNumberText.format(entry.realizedProfit)),
        width: 120,
        tint: entry.realizedProfit.map {
          $0 < 0 ? DesignTokens.negative : DesignTokens.positive
        } ?? DesignTokens.textPrimary
      )
      Text(verbatim: TradeLogbookText.status(entry.status))
        .font(.callout)
        .lineLimit(1)
        .frame(width: 140, alignment: .leading)
      markers(entry)
        .frame(width: 70, alignment: .leading)
    }
    .padding(.vertical, DesignTokens.spacingXS)
    .background(highlight ? DesignTokens.positive.opacity(0.1) : Color.clear)
    .accessibilityIdentifier("trade-logbook.row.\(entry.id.uuidString)")
  }

  /// Origin and estimate markers (HANDEL_PLAN P7).
  private func markers(_ entry: TradeLogbookEntry) -> some View {
    HStack(spacing: 4) {
      if entry.walletLink != nil {
        Image(systemName: "wallet.pass")
          .help(AppLocalization.text("Imported from the wallet"))
      }
      if entry.buySideSource == .assumed
        || entry.sales.contains(where: { $0.kindSource == .assumed })
      {
        Image(systemName: "questionmark.circle")
          .foregroundStyle(DesignTokens.caution)
          .help(
            AppLocalization.text(
              "Order type assumed: no own order data was available."
            )
          )
      }
      if entry.transportEstimated {
        Image(systemName: "shippingbox")
          .foregroundStyle(DesignTokens.caution)
          .help(AppLocalization.text("Transport estimated; replace it with the actual cost."))
      }
      if entry.sales.contains(where: { $0.salesTaxPaid != nil }) {
        Image(systemName: "checkmark.seal")
          .foregroundStyle(DesignTokens.positive)
          .help(
            AppLocalization.text(
              "Sales tax taken from the wallet journal; the broker fee is calculated, not recorded."
            )
          )
      }
    }
    .font(.caption)
  }

  private func reminderCell(
    _ reminder: TradeLogbookReminder,
    planned: Double?
  ) -> some View {
    Group {
      switch reminder {
      case .reached:
        Label("Target price reached", systemImage: "checkmark.circle.fill")
          .foregroundStyle(DesignTokens.positive)
      case .below(let current):
        Text(
          AppLocalization.format(
            "%@ below plan",
            ((current - (planned ?? current)) / (planned ?? current))
              .formatted(.percent.precision(.fractionLength(1)).locale(TradeNumberText.locale))
          )
        )
        .foregroundStyle(DesignTokens.caution)
      case .marketUnknown, .noPlannedPrice:
        Text(verbatim: "—").foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .font(.callout)
    .lineLimit(1)
    .frame(width: 140, alignment: .leading)
  }

  private func number(
    _ text: String,
    width: CGFloat? = nil,
    tint: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: text)
      .font(.callout.monospacedDigit())
      .foregroundStyle(tint)
      .lineLimit(1)
      .frame(width: width ?? numberWidth, alignment: .trailing)
  }

  private func dash(_ text: String) -> String {
    text.isEmpty ? "—" : text
  }

  private func newManualEntry() -> TradeLogbookEntry {
    let target: OpportunityHubRole =
      runtime.tradeDataRole(for: .home) == nil ? .main : .home
    let targetFees = runtime.tradeHubFees(for: target)
    return TradeLogbookEntry(
      typeID: 0,
      typeName: "",
      quantity: 1,
      buyUnitPrice: 0,
      buySide: .minSell,
      buyBrokerFeeRate: runtime.tradeHubFees(for: .main).brokerFeeRate,
      sourceRole: .main,
      sourceLocationName: runtime.tradeLocation(for: .main)?.name,
      targetRole: target,
      targetLocationName: runtime.tradeLocation(for: target)?.name,
      plannedSellUnitPrice: nil,
      transportCostTotal: nil,
      salesTaxRate: targetFees.salesTaxRate,
      sellBrokerFeeRate: targetFees.brokerFeeRate
    )
  }
}

struct TradeLogbookEditor: View {
  let request: TradeLogbookEditorRequest
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.dismiss) private var dismiss

  @State private var typeID: Int64 = 0
  @State private var typeName = ""
  @State private var searchText = ""
  @State private var searchResults: [ItemTypeSearchResult] = []
  @State private var purchasedAt = Date()
  @State private var quantityText = ""
  @State private var buyPriceText = ""
  @State private var buySide: TradeQuoteSide = .minSell
  @State private var buyBrokerText = ""
  @State private var sourceRole: OpportunityHubRole = .main
  @State private var targetRole: OpportunityHubRole = .home
  @State private var plannedText = ""
  @State private var transportText = ""
  @State private var transportEdited = false
  @State private var taxText = ""
  @State private var sellBrokerText = ""
  @State private var status: TradeLogbookStatus = .bought
  @State private var notes = ""
  @State private var sales: [TradeLogbookSale] = []
  @State private var saleDate = Date()
  @State private var saleQuantityText = ""
  @State private var salePriceText = ""
  @State private var saleKind: TradeSaleKind = .listedSellOrder
  @State private var validationMessage: String?
  @State private var isSaving = false
  @State private var didLoad = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(request.isNew ? "New logbook entry" : "Edit logbook entry")
        .font(.title2.bold())
        .padding(DesignTokens.spacingMD)
      Form {
        itemSection
        Section("Purchase") {
          DatePicker("Purchased", selection: $purchasedAt)
          TextField("Quantity", text: $quantityText)
            .groupedNumberInput($quantityText, allowsFraction: false)
            .accessibilityIdentifier("trade-logbook.editor.quantity")
          Picker("Purchase type", selection: $buySide) {
            ForEach(TradeQuoteSide.allCases, id: \.self) { side in
              Text(verbatim: TradeLogbookText.buySide(side)).tag(side)
            }
          }
          if request.entry.walletLink != nil {
            Text(walletOriginText)
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          TextField("Price per unit (ISK, without broker fee)", text: $buyPriceText)
            .groupedNumberInput($buyPriceText)
            .accessibilityIdentifier("trade-logbook.editor.buy-price")
          if buySide == .maxBuy {
            TextField("Broker fee at purchase (%)", text: $buyBrokerText)
          }
          rolePicker("Bought at", selection: $sourceRole)
        }
        Section(isSale ? LocalizedStringKey("Sale plan") : LocalizedStringKey("Usage")) {
          Picker("Usage", selection: usageBinding) {
            ForEach(TradeLogbookUsage.allCases, id: \.self) { usage in
              Text(verbatim: TradeLogbookText.usage(usage)).tag(usage)
            }
          }
          .accessibilityIdentifier("trade-logbook.editor.usage")
          if isSale {
            salePlanFields
          }
          TextField("Notes", text: $notes, axis: .vertical)
        }
        if isSale || !sales.isEmpty {
          salesSection
        }
      }
      .formStyle(.grouped)
      if let validationMessage {
        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(DesignTokens.negative)
          .padding(.horizontal, DesignTokens.spacingMD)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save") { Task { await save() } }
          .keyboardShortcut(.defaultAction)
          .disabled(isSaving)
          .accessibilityIdentifier("trade-logbook.editor.save")
      }
      .padding(DesignTokens.spacingMD)
    }
    .frame(minWidth: 560, minHeight: 640)
    .onAppear(perform: loadInitialValues)
    .onChange(of: quantityText) { _, _ in recalculateTransport() }
    .onChange(of: buyPriceText) { _, _ in recalculateTransport() }
    .onChange(of: buySide) { _, _ in recalculateTransport() }
    .task(id: searchText) { await search() }
  }

  private var isSale: Bool {
    if case .sale = usageBinding.wrappedValue { return true }
    return false
  }

  /// Usage as one choice: the hubs keep the sale plan, production and
  /// consumption close the whole entry (`TradeLogbookEntry.setUsage`).
  private var usageBinding: Binding<TradeLogbookUsage> {
    Binding(
      get: {
        var entry = request.entry
        entry.targetRole = targetRole
        entry.status = status
        return entry.usage
      },
      set: { usage in
        var entry = request.entry
        entry.targetRole = targetRole
        entry.status = status
        entry.setUsage(usage)
        targetRole = entry.targetRole
        status = entry.status
      }
    )
  }

  @ViewBuilder
  private var salePlanFields: some View {
    TextField("Planned sale price per unit (ISK)", text: $plannedText)
      .groupedNumberInput($plannedText)
    if request.entry.transportEstimated, !transportEdited {
      Text("Transport estimated for this quantity; replace it with the actual cost.")
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
    }
    // Only typing marks the transport as the user's own value.
    TextField(
      "Transport for the whole quantity (ISK)",
      text: Binding(
        get: { transportText },
        set: {
          transportText = $0
          transportEdited = true
        }
      )
    )
    .groupedNumberInput($transportText)
    TextField("Sales tax (%)", text: $taxText)
    TextField("Broker fee for the sell order (%)", text: $sellBrokerText)
    Picker("Status", selection: $status) {
      // Production and consumption are chosen as the usage above.
      ForEach(
        TradeLogbookStatus.allCases.filter { !$0.isUsage }, id: \.self
      ) { status in
        Text(verbatim: TradeLogbookText.status(status)).tag(status)
      }
    }
  }

  @ViewBuilder
  private var itemSection: some View {
    Section("Item") {
      if typeID > 0 {
        EVEItemText(value: typeName, typeID: typeID, font: .callout)
      } else {
        Text("No item selected").foregroundStyle(DesignTokens.textSecondary)
      }
      if request.isNew, request.entry.typeID == 0 {
        TextField("Search item (at least 3 characters)", text: $searchText)
          .accessibilityIdentifier("trade-logbook.editor.search")
        ForEach(searchResults) { result in
          HStack {
            EVEEntityText(value: result.name, font: .callout, lineLimit: 1)
            Spacer()
            Button("Select") {
              typeID = result.id
              typeName = result.name
              searchText = ""
              searchResults = []
            }
            .buttonStyle(.borderless)
          }
        }
      }
    }
  }

  private var salesSection: some View {
    Section("Sales") {
      ForEach(sales) { sale in
        HStack {
          Text(sale.soldAt.formatted(date: .abbreviated, time: .shortened))
          Spacer()
          Text(
            verbatim:
              "\(TradeNumberText.format(Double(sale.quantity), fractionDigits: 0)) × \(TradeNumberText.format(sale.unitPrice)) ISK"
          )
          .monospacedDigit()
          Text(verbatim: TradeLogbookText.saleKind(sale.kind))
            .foregroundStyle(DesignTokens.textSecondary)
          if let tax = sale.salesTaxPaid {
            Text(
              AppLocalization.format(
                "Tax paid %@ ISK", TradeNumberText.format(tax)
              )
            )
            .foregroundStyle(DesignTokens.positive)
          }
          if sale.walletLink != nil {
            Image(systemName: "wallet.pass")
              .help(AppLocalization.text("Imported from the wallet"))
          }
          Button {
            sales.removeAll { $0.id == sale.id }
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Remove sale")
        }
      }
      DatePicker("Sold", selection: $saleDate)
      TextField("Sold quantity", text: $saleQuantityText)
        .groupedNumberInput($saleQuantityText, allowsFraction: false)
      TextField("Sale price per unit (ISK)", text: $salePriceText)
        .groupedNumberInput($salePriceText)
      Picker("Sale type", selection: $saleKind) {
        ForEach(TradeSaleKind.allCases, id: \.self) { kind in
          Text(verbatim: TradeLogbookText.saleKind(kind)).tag(kind)
        }
      }
      Button("Add sale") { addSale() }
        .accessibilityIdentifier("trade-logbook.editor.add-sale")
    }
  }

  private var walletOriginText: String {
    let source =
      switch request.entry.buySideSource {
      case .manual: AppLocalization.text("set manually")
      case .detected: AppLocalization.text("detected from own orders")
      case .assumed: AppLocalization.text("assumed (no own order data)")
      }
    return AppLocalization.format(
      "Imported from a wallet transaction; purchase type %@.",
      source
    )
  }

  private func rolePicker(
    _ title: LocalizedStringKey,
    selection: Binding<OpportunityHubRole>
  ) -> some View {
    Picker(title, selection: selection) {
      ForEach(OpportunityHubRole.allCases, id: \.self) { role in
        Text(verbatim: TradeHubText.roleName(role)).tag(role)
      }
    }
  }

  private func loadInitialValues() {
    guard !didLoad else { return }
    didLoad = true
    let entry = request.entry
    typeID = entry.typeID
    typeName = entry.typeName
    purchasedAt = entry.purchasedAt
    quantityText = TradeNumberText.format(Double(entry.quantity), fractionDigits: 0)
    buyPriceText = entry.buyUnitPrice > 0 ? TradeNumberText.format(entry.buyUnitPrice) : ""
    buySide = entry.buySide
    buyBrokerText = TradeNumberText.percentText(entry.buyBrokerFeeRate)
    sourceRole = entry.sourceRole
    targetRole = entry.targetRole
    plannedText = TradeNumberText.format(entry.plannedSellUnitPrice)
    transportText = TradeNumberText.format(entry.transportCostTotal)
    taxText = TradeNumberText.percentText(entry.salesTaxRate)
    sellBrokerText = TradeNumberText.percentText(entry.sellBrokerFeeRate)
    status = entry.status
    notes = entry.notes
    sales = entry.sales
    recalculateTransport()
  }

  /// A prefilled Trade row recalculates the exact route cost for the entered
  /// quantity until the user types an own transport value.
  private func recalculateTransport() {
    guard request.isNew, !transportEdited,
      let basis = request.transportBasis,
      let parsed = TradeNumberText.parse(quantityText),
      parsed > 0, parsed < 1e15, parsed == parsed.rounded()
    else { return }
    let quantity = Int64(parsed)
    let unitCost = TradeNumberText.parse(buyPriceText).map { price in
      buySide == .maxBuy
        ? price * (1 + (TradeNumberText.rate(buyBrokerText) ?? 0)) : price
    }
    let total: Double?
    if basis.legs.isEmpty, sourceRole == targetRole {
      total = 0
    } else {
      total =
        TradeCalculator.transportQuote(
          typeID: typeID,
          name: typeName,
          quantity: quantity,
          packagedVolumePerUnit: request.packagedVolume,
          unitCollateral: unitCost,
          transport: basis
        ).total
    }
    transportText = TradeNumberText.format(total)
  }

  private func search() async {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard query.count >= 3 else {
      searchResults = []
      return
    }
    try? await Task.sleep(for: .milliseconds(250))
    guard !Task.isCancelled else { return }
    searchResults = Array(
      await runtime.tradeSearchItemTypes(matching: query).prefix(12)
    )
  }

  private func addSale() {
    guard let quantity = TradeNumberText.parse(saleQuantityText),
      quantity > 0, quantity == quantity.rounded(),
      let price = TradeNumberText.parse(salePriceText), price >= 0
    else {
      validationMessage = AppLocalization.text(
        "Enter the sold quantity and the sale price."
      )
      return
    }
    sales.append(
      TradeLogbookSale(
        soldAt: saleDate,
        quantity: Int64(quantity),
        unitPrice: price,
        kind: saleKind
      )
    )
    saleQuantityText = ""
    salePriceText = ""
    validationMessage = nil
  }

  private func save() async {
    guard let quantity = TradeNumberText.parse(quantityText),
      quantity == quantity.rounded(),
      quantity > 0, quantity < 1e15,
      let buyPrice = TradeNumberText.parse(buyPriceText)
    else {
      validationMessage = AppLocalization.text(
        "Enter an item, a whole quantity and the purchase price."
      )
      return
    }
    var entry = request.entry
    entry.typeID = typeID
    entry.typeName = typeName
    entry.purchasedAt = purchasedAt
    entry.quantity = Int64(quantity)
    entry.buyUnitPrice = buyPrice
    entry.buySide = buySide
    entry.buyBrokerFeeRate = TradeNumberText.rate(buyBrokerText)
    if entry.sourceRole != sourceRole {
      entry.sourceLocationName = runtime.tradeLocation(for: sourceRole)?.name
    }
    if entry.targetRole != targetRole {
      entry.targetLocationName = runtime.tradeLocation(for: targetRole)?.name
    }
    entry.sourceRole = sourceRole
    entry.targetRole = targetRole
    entry.plannedSellUnitPrice = TradeNumberText.parse(plannedText)
    entry.transportCostTotal = TradeNumberText.parse(transportText)
    entry.salesTaxRate = TradeNumberText.rate(taxText)
    entry.sellBrokerFeeRate = TradeNumberText.rate(sellBrokerText)
    entry.notes = notes
    entry.sales = sales
    if buySide != request.entry.buySide { entry.buySideSource = .manual }
    if transportEdited { entry.transportEstimated = false }
    // Recording the last open units closes an open entry.
    entry.status =
      status.isOpen && entry.soldQuantity >= entry.quantity ? .sold : status
    do {
      try entry.validate()
    } catch TradeLogbookValidationError.soldMoreThanBought {
      validationMessage = AppLocalization.text(
        "More units are recorded as sold than were bought."
      )
      return
    } catch {
      validationMessage = AppLocalization.text(
        "Enter an item, a whole quantity and the purchase price; rates must be below 100 %."
      )
      return
    }
    isSaving = true
    defer { isSaving = false }
    if await runtime.saveTradeLogbookEntry(entry) {
      dismiss()
    } else {
      validationMessage = runtime.tradeLogbookError?.localizedUI
    }
  }
}
