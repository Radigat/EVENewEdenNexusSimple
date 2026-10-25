import EVENexusCore
import SwiftData
import SwiftUI

/// Stock sale comparison (LAGERVERKAUF_PLAN.md): pasted owned items are
/// valued at the chosen hub against the cost of producing them anew there.
struct StockSaleComparisonView: View {
  var onOpenMarketSettings: () -> Void = {}

  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]

  @AppStorage("stock-sale.hub-role", store: AppDefaults.store)
  private var hubRoleRawValue = OpportunityHubRole.main.rawValue
  // New production follows the Hub opportunity settings (owner decision
  // 25.10.2026), so these keys are shared with that view.
  @AppStorage("market-opportunities.cost.blueprint.enabled", store: AppDefaults.store)
  private var costIncludesBlueprint = false
  @AppStorage("market-opportunities.cost.builds-intermediates", store: AppDefaults.store)
  private var buildsIntermediates = true
  @AppStorage("market-opportunities.cost.blueprint-per-run", store: AppDefaults.store)
  private var blueprintCostPerRunText = ""
  @AppStorage("market-opportunities.cost.blueprint.own-rights", store: AppDefaults.store)
  private var usesOwnBlueprintRights = false

  @State private var entries: [StockSaleEntry] = []
  @State private var hasLoadedEntries = false
  @State private var pasteText = ""
  @State private var isResolving = false
  @State private var pasteMessages: [String] = []
  @State private var persistenceError: String?
  @State private var confirmsClear = false
  @State private var sort = AppTableSortDescriptor(
    column: StockSaleSortColumn.recommendation,
    direction: .descending
  )
  @State private var scanRowsByType: [Int64: ManufacturingOpportunityRow] = [:]
  @State private var scanRowsAnalysisID: UUID?
  @State private var loyaltyStoreBlueprintOffers: [Int64: [LoyaltyStoreBlueprintOffer]] = [:]

  private let nameMinimumWidth: CGFloat = 220
  private let numberWidth: CGFloat = 112
  private let efficiencyWidth: CGFloat = 52

  private var hubRole: OpportunityHubRole {
    OpportunityHubRole(rawValue: hubRoleRawValue) ?? .main
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        header
        hubPanel
        pastePanel
        unresolvedPanel
        tablePanel
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      loadEntries()
      await runtime.loadManufacturingOpportunityAnalysis()
      if hubRole != .main {
        await runtime.loadSecondaryHubOpportunityData(role: hubRole)
      }
    }
    .task(id: hubRole) {
      if hubRole != .main {
        await runtime.loadSecondaryHubOpportunityData(role: hubRole)
      }
    }
    .task(id: analysis?.id) {
      prepareScanRows()
      guard let analysis else { return }
      // Same type sets as the Hub opportunities, so the shared runtime
      // caches are reused instead of replaced.
      let loyaltyStoreBlueprints = runtime.loyaltyStoreOfferedTypeIDSet
      await runtime.loadOpportunityContractReferences(
        typeIDs: Set(analysis.rows.map(\.productTypeID)),
        blueprintTypeIDs: Set(
          analysis.rows.filter {
            ManufacturingOpportunityBlueprintAcquisitionProjector.requiresAcquisition(
              row: $0,
              loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprints
            )
          }.map(\.blueprintTypeID)
        )
      )
      await runtime.loadOpportunityInventionEstimates(
        blueprintTypeIDs: Set(
          analysis.rows.filter(
            ManufacturingOpportunityBlueprintAcquisitionProjector.requiresInvention(row:)
          ).map(\.blueprintTypeID)
        )
      )
    }
    .task(id: loyaltyOfferTrigger) {
      let trigger = loyaltyOfferTrigger
      let catalog = runtime.loyaltyStoreCatalog
      let offers = await Task.detached(priority: .utility) {
        LoyaltyStoreBlueprintOfferBuilder.build(
          catalog: catalog,
          blueprintTypeIDs: trigger.blueprintTypeIDs,
          characterPoints: trigger.loyaltyPoints?.flattened,
          walletISKByCharacterName: trigger.wallets
        )
      }.value
      guard !Task.isCancelled else { return }
      loyaltyStoreBlueprintOffers = offers
    }
    .confirmationDialog(
      "Clear the stock sale list?",
      isPresented: $confirmsClear
    ) {
      Button("Clear list", role: .destructive) {
        updateEntries([])
      }
    } message: {
      Text("All pasted items and unrecognized lines are removed.")
    }
  }

  // MARK: Header and hub

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Stock sale comparison")
        .font(.largeTitle.bold())
        .foregroundStyle(DesignTokens.textPrimary)
      Text(
        "Paste items copied from the EVE client with their quantities and see per item the minimum price at the chosen hub that beats producing them anew, including all production costs and market fees."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var hubPanel: some View {
    Panel(title: "Hub and basis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          Picker("Hub", selection: $hubRoleRawValue) {
            ForEach(OpportunityHubRole.allCases, id: \.self) { role in
              Text(verbatim: TradeHubText.roleName(role)).tag(role.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          .accessibilityIdentifier("stock-sale.hub")
          hubChip
          feeChip
          Spacer()
          refreshButton
        }
        ForEach(hubMessages, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.caution)
        }
        if !feeMessages.isEmpty {
          ForEach(feeMessages, id: \.self) { message in
            Label(message, systemImage: "percent")
              .foregroundStyle(DesignTokens.caution)
          }
          Button("Open Market Settings", action: onOpenMarketSettings)
            .accessibilityIdentifier("stock-sale.open-market-settings")
        }
        Text(assumptionText)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        Text(
          "Minimum sell order = new production cost per unit ÷ (1 − sales tax − broker fee); minimum direct sale = cost ÷ (1 − sales tax). New production buys every material at the Main Hub and includes installation, Blueprint share and delivery to the chosen hub. Own orders are one valid price step below the best sell order. Order modification and relist fees are not included."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  @ViewBuilder
  private var hubChip: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      if let location = runtime.tradeLocation(for: hubRole) {
        EVEEntityText(value: location.name, font: .caption, lineLimit: 1)
      } else {
        Text("Not configured").font(.caption)
      }
    }
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(DesignTokens.accent.opacity(0.15), in: Capsule())
    .overlay(Capsule().stroke(DesignTokens.accent.opacity(0.6)))
  }

  private var feeChip: some View {
    let fees = runtime.tradeHubFees(for: hubRole)
    return Text(
      verbatim: AppLocalization.format(
        "Sales tax %@ · Broker fee %@",
        formatPercent(fees.salesTaxRate),
        formatPercent(fees.brokerFeeRate)
      )
    )
    .font(.caption)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(DesignTokens.textSecondary.opacity(0.12), in: Capsule())
  }

  private var isScanningHubs: Bool {
    runtime.isAnalyzingManufacturingOpportunities
      || runtime.opportunityState(for: .home).isAnalyzing
      || runtime.opportunityState(for: .coalition).isAnalyzing
  }

  /// Hub market data and production costs come from the shared Hub scan.
  private var refreshButton: some View {
    Button {
      Task {
        await runtime.analyzeManufacturingOpportunities(
          settings: runtime.manufacturingOpportunityAnalysis?.settings
            ?? ManufacturingOpportunitySettings()
        )
      }
    } label: {
      if isScanningHubs {
        ProgressView().controlSize(.small)
      } else {
        Label("Refresh hub markets", systemImage: "arrow.clockwise")
      }
    }
    .disabled(isScanningHubs)
    .help(
      AppLocalization.text(
        "Runs the Main, Home and Coalition Hub scan that also updates the Hub opportunities.")
    )
    .accessibilityIdentifier("stock-sale.refresh-hub-markets")
  }

  private var hubMessages: [String] {
    let name = TradeHubText.roleName(hubRole)
    switch runtime.opportunityScanTarget(for: hubRole) {
    case .notConfigured:
      return [AppLocalization.format("No %@ is configured. Select it in Market Settings.", name)]
    case .unresolved:
      return [
        AppLocalization.format(
          "The %@ has no exact station or structure identifier. Select it again in Market Settings.",
          name
        )
      ]
    default:
      break
    }
    var messages: [String] = []
    if let dataRole = runtime.tradeDataRole(for: hubRole), dataRole != hubRole {
      messages.append(
        AppLocalization.format(
          "The %@ is the same place as the %@ and uses its scan and market data.",
          name,
          TradeHubText.roleName(dataRole)
        )
      )
    }
    if analysis == nil {
      messages.append(
        AppLocalization.format(
          "No Hub opportunity scan for the %@ yet, so new production costs are unavailable. Use “Refresh hub markets”.",
          name
        )
      )
    }
    if let state = runtime.tradeMarketState(for: hubRole), state.value != nil {
      if state.state != .fresh {
        messages.append(
          AppLocalization.format(
            "Market data of the %@: %@.",
            name,
            StartupDataStatusSection.freshnessText(state.state)
          )
        )
      }
    } else {
      messages.append(
        AppLocalization.format(
          "No market data for the %@ in this session yet. Use “Refresh hub markets” or wait for the automatic Hub scan.",
          name
        )
      )
    }
    return messages
  }

  private var feeMessages: [String] {
    let fees = runtime.tradeHubFees(for: hubRole)
    var messages: [String] = []
    if fees.salesTaxRate == nil {
      messages.append(
        AppLocalization.format(
          "The sales tax of the %@ is unknown; minimum prices and profits stay unavailable.",
          TradeHubText.roleName(hubRole)
        )
      )
    } else if fees.brokerFeeRate == nil {
      messages.append(
        AppLocalization.format(
          "The broker fee of the %@ is unknown; sell-order values stay unavailable.",
          TradeHubText.roleName(hubRole)
        )
      )
    }
    return messages
  }

  private var assumptionText: String {
    AppLocalization.format(
      "Hub opportunity settings: build intermediates yourself %@ · own BPCs available %@ · Blueprint allocation %@.",
      AppLocalization.text(buildsIntermediates ? "on" : "off"),
      AppLocalization.text(usesOwnBlueprintRights ? "on" : "off"),
      costIncludesBlueprint
        ? (blueprintCostPerRun.map {
          AppLocalization.format("%@ ISK per run", formatNumber($0))
        } ?? AppLocalization.text("invalid"))
        : AppLocalization.text("off")
    )
  }

  // MARK: Paste

  private var pastePanel: some View {
    Panel(title: "Paste items") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text(
          "Select the items in the EVE inventory, copy them (Cmd+C) and paste them here. One item per line; English and German client names are recognized."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        TextEditor(text: $pasteText)
          .font(.callout.monospaced())
          .frame(minHeight: 90, maxHeight: 160)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(DesignTokens.textSecondary.opacity(0.3))
          )
          .accessibilityIdentifier("stock-sale.paste")
        HStack(spacing: DesignTokens.spacingSM) {
          Button("Replace list") {
            Task { await applyPaste(replacing: true) }
          }
          .accessibilityIdentifier("stock-sale.replace")
          Button("Add to list") {
            Task { await applyPaste(replacing: false) }
          }
          .accessibilityIdentifier("stock-sale.append")
          if isResolving {
            ProgressView().controlSize(.small)
          }
          Spacer()
          Button("Clear list", role: .destructive) {
            confirmsClear = true
          }
          .disabled(entries.isEmpty)
          .accessibilityIdentifier("stock-sale.clear")
        }
        .disabled(isResolving)
        ForEach(pasteMessages, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.caution)
        }
        if let persistenceError {
          Label(persistenceError, systemImage: "externaldrive.badge.exclamationmark")
            .foregroundStyle(DesignTokens.negative)
        }
      }
    }
  }

  @ViewBuilder
  private var unresolvedPanel: some View {
    let unresolved = entries.filter { !$0.isResolved }
    if !unresolved.isEmpty {
      Panel(title: "Unrecognized lines") {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          ForEach(unresolved) { entry in
            HStack(spacing: DesignTokens.spacingSM) {
              removeButton(entry)
              Text(verbatim: entry.pastedName)
                .font(.callout.monospaced())
                .lineLimit(1)
                .textSelection(.enabled)
              Text(verbatim: unresolvedText(entry.unresolvedReason))
                .font(.caption)
                .foregroundStyle(DesignTokens.caution)
            }
          }
        }
      }
    }
  }

  private func unresolvedText(_ reason: StockSaleUnresolvedReason?) -> String {
    switch reason {
    case .ambiguousName:
      AppLocalization.text("Several items carry this name.")
    case .germanNamesUnavailable:
      AppLocalization.text(
        "Not found. German names need a one-time SDE reimport of the current catalog (Data & Settings → SDE)."
      )
    case .invalidQuantity:
      AppLocalization.text("The quantity is invalid or exceeds 1,000,000,000.")
    case .unknownName, nil:
      AppLocalization.text("No item with this name in the SDE catalog.")
    }
  }

  // MARK: Table

  @ViewBuilder
  private var tablePanel: some View {
    let rows = displayRows
    Panel(title: "Comparison") {
      if rows.isEmpty {
        Text("No items yet. Paste items copied from the EVE client.")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: 0) {
            tableHeader
            Divider()
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(rows) { row in
                tableRow(row)
                Divider().opacity(0.4)
              }
            }
          }
        }
      }
    }
  }

  private var tableHeader: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Color.clear.frame(width: 22)
      SortableTableHeader(title: "Item", column: StockSaleSortColumn.name, sort: $sort)
        .frame(width: nameMinimumWidth, alignment: .leading)
      numberHeader("Quantity", .quantity)
      numberHeader("ME", .materialEfficiency, width: efficiencyWidth)
      numberHeader("TE", .timeEfficiency, width: efficiencyWidth)
      numberHeader("Material/unit", .materialCostPerUnit)
      numberHeader("Installation/unit", .installationCostPerUnit)
      numberHeader("Blueprint/unit", .blueprintCostPerUnit)
      numberHeader("Logistics/unit", .logisticsCostPerUnit)
      numberHeader("New production/unit", .costPerUnit)
      numberHeader("Min. price sell order", .minimumListingPrice)
      numberHeader("Min. price direct sale", .minimumDirectSalePrice)
      numberHeader("Best sell", .bestSellPrice)
      numberHeader("Own order", .ownSellOrderPrice)
      numberHeader("Best buy", .bestBuyPrice)
      numberHeader("Buy depth", .bestBuyVolume)
      numberHeader("Profit/unit sell order", .listingProfitPerUnit)
      numberHeader("Profit total sell order", .listingProfitTotal)
      numberHeader("Profit/unit direct sale", .directProfitPerUnit)
      numberHeader("Profit total direct sale", .directProfitTotal)
      numberHeader("Recommendation", .recommendation, width: 170)
    }
    .font(.caption.weight(.semibold))
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private func numberHeader(
    _ title: LocalizedStringKey,
    _ column: StockSaleSortColumn,
    width: CGFloat? = nil
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      defaultDirection: .descending,
      alignment: .trailing
    )
    .frame(width: width ?? numberWidth, alignment: .trailing)
  }

  private func tableRow(_ display: StockSaleDisplayRow) -> some View {
    let row = display.row
    return HStack(spacing: DesignTokens.spacingXS) {
      removeButton(display.entry)
      HStack(spacing: DesignTokens.spacingXS) {
        EVEItemText(
          value: row.name,
          typeID: row.typeID,
          font: .callout,
          lineLimit: 1,
          iconSize: 18
        )
        if display.entry.hasDifferentPastedName {
          Image(systemName: "character.bubble")
            .foregroundStyle(DesignTokens.textSecondary)
            .help(
              AppLocalization.format("Pasted as “%@”", display.entry.pastedName)
            )
            .accessibilityLabel(
              Text(AppLocalization.format("Pasted as “%@”", display.entry.pastedName))
            )
        }
        if !display.issues.isEmpty {
          Image(systemName: "info.circle")
            .foregroundStyle(DesignTokens.caution)
            .help(display.issues.joined(separator: "\n"))
            .accessibilityLabel(Text(display.issues.joined(separator: " ")))
        }
      }
      .frame(width: nameMinimumWidth, alignment: .leading)
      numberCell(formatInteger(row.quantity))
      efficiencyCell(display, kind: .material)
      efficiencyCell(display, kind: .time)
      numberCell(formatNumber(row.cost?.materialCostPerUnit))
      numberCell(formatNumber(row.cost?.installationCostPerUnit))
      numberCell(formatNumber(row.cost?.blueprintCostPerUnit))
      numberCell(formatNumber(row.cost?.logisticsCostPerUnit))
      numberCell(formatNumber(row.costPerUnit))
        .help(costHelp(row))
      numberCell(formatNumber(row.minimumListingPrice))
      numberCell(formatNumber(row.minimumDirectSalePrice))
      numberCell(formatNumber(row.bestSellPrice))
      numberCell(formatNumber(row.ownSellOrderPrice), tint: reachTint(row.listingReachesMinimum))
      numberCell(formatNumber(row.bestBuyPrice), tint: reachTint(row.directReachesMinimum))
      numberCell(
        formatInteger(row.bestBuyVolume),
        tint: row.directDepth == .insufficient ? DesignTokens.caution : DesignTokens.textPrimary
      )
      numberCell(formatNumber(row.listingProfitPerUnit), tint: signTint(row.listingProfitPerUnit))
      numberCell(formatWholeNumber(row.listingProfitTotal), tint: signTint(row.listingProfitTotal))
      numberCell(formatNumber(row.directProfitPerUnit), tint: signTint(row.directProfitPerUnit))
      directTotalCell(row)
      recommendationCell(row)
    }
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private func removeButton(_ entry: StockSaleEntry) -> some View {
    Button {
      updateEntries(entries.filter { $0.id != entry.id })
    } label: {
      Image(systemName: "minus.circle")
    }
    .buttonStyle(.borderless)
    .frame(width: 22)
    .help(AppLocalization.text("Remove from list"))
    .accessibilityLabel("Remove from list")
    .accessibilityIdentifier("stock-sale.remove.\(entry.id.uuidString)")
  }

  private enum EfficiencyKind { case material, time }

  @ViewBuilder
  private func efficiencyCell(_ display: StockSaleDisplayRow, kind: EfficiencyKind) -> some View {
    let current =
      kind == .material
      ? display.row.cost?.materialEfficiency : display.row.cost?.timeEfficiency
    if let current, display.supportsEfficiency {
      TextField(
        kind == .material ? "ME" : "TE",
        value: Binding(
          get: { current },
          set: { setEfficiency($0, kind: kind, entryID: display.entry.id) }
        ),
        format: .number
      )
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .font(.callout.monospacedDigit())
      .frame(width: efficiencyWidth)
      .help(
        AppLocalization.text(
          kind == .material
            ? "Material Efficiency of the new production, 0–10."
            : "Time Efficiency of the new production, 0–20."
        )
      )
      .accessibilityIdentifier(
        "stock-sale.\(kind == .material ? "me" : "te").\(display.row.typeID)"
      )
    } else {
      Text(verbatim: "—")
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)
        .frame(width: efficiencyWidth, alignment: .trailing)
    }
  }

  private func directTotalCell(_ row: StockSaleComparisonRow) -> some View {
    let tint =
      row.directDepth == .insufficient && row.directProfitTotal != nil
      ? DesignTokens.caution : signTint(row.directProfitTotal)
    return numberCell(formatWholeNumber(row.directProfitTotal), tint: tint)
      .help(
        row.directDepth == .insufficient
          ? AppLocalization.format(
            "Upper bound: the buy orders at the best price take only %@ of %@ units.",
            formatInteger(row.bestBuyVolume),
            formatInteger(row.quantity)
          )
          : ""
      )
  }

  private func recommendationCell(_ row: StockSaleComparisonRow) -> some View {
    let (text, tint): (String, Color) =
      switch row.recommendation {
      case .listedSale?: (AppLocalization.text("Sell order"), DesignTokens.positive)
      case .directSale?: (AppLocalization.text("Direct sale"), DesignTokens.positive)
      case .keep?: (AppLocalization.text("Keep"), DesignTokens.negative)
      case nil: ("—", DesignTokens.textSecondary)
      }
    return VStack(alignment: .trailing, spacing: 0) {
      Text(verbatim: text)
        .font(.callout.weight(.semibold))
        .foregroundStyle(tint)
      if row.recommendation != nil {
        Text(verbatim: formatWholeNumber(row.recommendedProfitTotal))
          .font(.caption.monospacedDigit())
          .foregroundStyle(signTint(row.recommendedProfitTotal))
      }
    }
    .frame(width: 170, alignment: .trailing)
  }

  private func numberCell(
    _ text: String,
    tint: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: text)
      .font(.callout.monospacedDigit())
      .foregroundStyle(tint)
      .lineLimit(1)
      .frame(width: numberWidth, alignment: .trailing)
  }

  private func reachTint(_ reaches: Bool?) -> Color {
    guard let reaches else { return DesignTokens.textPrimary }
    return reaches ? DesignTokens.positive : DesignTokens.negative
  }

  private func signTint(_ value: Double?) -> Color {
    guard let value else { return DesignTokens.textPrimary }
    return value < 0 ? DesignTokens.negative : DesignTokens.positive
  }

  private func costHelp(_ row: StockSaleComparisonRow) -> String {
    guard let cost = row.cost else { return "" }
    return AppLocalization.format(
      "New production of %@ units in %@ runs for %@ units requested.",
      formatInteger(cost.producedQuantity),
      formatInteger(Int64(cost.runs)),
      formatInteger(row.quantity)
    )
  }

  // MARK: Rows

  private var analysis: ManufacturingOpportunitySnapshot? {
    switch runtime.tradeDataRole(for: hubRole) {
    case nil: nil
    case .main: runtime.manufacturingOpportunityAnalysis
    case let dataRole?: runtime.opportunityState(for: dataRole).analysis
    }
  }

  private var blueprintCostPerRun: Double? {
    OpportunityCostInputs.parseNonnegativeISK(blueprintCostPerRunText)
  }

  private var contractContext: ManufacturingOpportunityContractContext {
    ManufacturingOpportunityContractContext(
      references: runtime.opportunityContractReferences,
      contractFeeRate: runtime.publicContractFeeRate(for: hubRole),
      blueprintOffers: runtime.opportunityBlueprintOffers,
      loyaltyStoreBlueprintTypeIDs: runtime.loyaltyStoreOfferedTypeIDSet,
      loyaltyStoreBlueprintOffers: loyaltyStoreBlueprintOffers,
      inventionEstimates: runtime.opportunityInventionEstimates,
      usesOwnBlueprintRights: usesOwnBlueprintRights
    )
  }

  private var loyaltyOfferTrigger: StockSaleLoyaltyOfferTrigger {
    let loyaltyStoreBlueprints = runtime.loyaltyStoreOfferedTypeIDSet
    let blueprintTypeIDs = Set(
      entries.compactMap { $0.typeID.flatMap { scanRowsByType[$0] } }
        .filter {
          ManufacturingOpportunityBlueprintAcquisitionProjector.requiresBlueprintCopy(
            row: $0,
            loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprints
          )
        }
        .map(\.blueprintTypeID)
    )
    return StockSaleLoyaltyOfferTrigger(
      blueprintTypeIDs: blueprintTypeIDs,
      catalogID: runtime.loyaltyStoreCatalog?.id,
      loyaltyPoints: runtime.characterLoyaltyPoints,
      wallets: OpportunityCostInputs.walletISKByCharacterName(characters)
    )
  }

  private var displayRows: [StockSaleDisplayRow] {
    let snapshot = analysis
    let rowsByType = scanRowsAnalysisID == snapshot?.id ? scanRowsByType : [:]
    let sheet = OpportunityCostInputs.costSheet(
      includesBlueprint: costIncludesBlueprint,
      blueprintCostPerRun: blueprintCostPerRun
    )
    let contract = contractContext
    let fees = runtime.tradeHubFees(for: hubRole)
    let prices = runtime.tradeMarketState(for: hubRole)?.value?.pricesByType ?? [:]
    let loyaltyStoreBlueprints = runtime.loyaltyStoreOfferedTypeIDSet
    var byEntryID: [UUID: StockSaleDisplayRow] = [:]
    var comparisonRows: [StockSaleComparisonRow] = []
    for entry in entries {
      guard entry.isResolved, let typeID = entry.typeID else { continue }
      let scanRow = rowsByType[typeID]
      var cost: StockSaleProductionCost?
      if let scanRow, let snapshot {
        let defaults = StockSaleProductionCostProjector.defaultEfficiency(
          for: scanRow,
          loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprints
        )
        let supports = scanRow.supportsBlueprintEfficiency
        cost = StockSaleProductionCostProjector.project(
          row: scanRow,
          quantity: entry.quantity,
          materialEfficiency: supports
            ? min(10, max(0, entry.materialEfficiency ?? defaults.materialEfficiency)) : 0,
          timeEfficiency: supports
            ? min(20, max(0, entry.timeEfficiency ?? defaults.timeEfficiency)) : 0,
          buildsIntermediates: buildsIntermediates,
          sheet: sheet,
          contract: contract,
          snapshot: snapshot
        )
      }
      let row = StockSaleComparisonCalculator.row(
        entryID: entry.id,
        typeID: typeID,
        name: entry.resolvedName ?? entry.pastedName,
        pastedName: entry.pastedName,
        quantity: entry.quantity,
        cost: cost,
        prices: prices[typeID],
        fees: fees
      )
      comparisonRows.append(row)
      byEntryID[entry.id] = StockSaleDisplayRow(
        entry: entry,
        row: row,
        supportsEfficiency: scanRow?.supportsBlueprintEfficiency ?? false,
        issues: issues(row: row, scanRow: scanRow, hasSnapshot: snapshot != nil)
      )
    }
    return StockSaleRowSorter.sorted(
      comparisonRows,
      by: sort.column,
      ascending: sort.direction == .ascending
    ).compactMap { byEntryID[$0.entryID] }
  }

  private func issues(
    row: StockSaleComparisonRow,
    scanRow: ManufacturingOpportunityRow?,
    hasSnapshot: Bool
  ) -> [String] {
    var result: [String] = []
    if !hasSnapshot {
      result.append(
        AppLocalization.text(
          "No Hub opportunity scan for this hub, so the new production cost is unknown."))
    } else if scanRow == nil {
      result.append(
        AppLocalization.text(
          "No new production cost: the item is not in the Hub opportunity scan of this hub (not manufacturable, excluded or without complete data)."
        )
      )
    } else if row.cost == nil {
      result.append(
        AppLocalization.text("The production cost could not be projected for this quantity."))
    } else if row.costPerUnit == nil {
      let messages = (row.cost?.warnings ?? [])
        .filter { $0.severity != .information }
        .map { AppLocalization.text($0.message) }
      result.append(
        contentsOf: messages.isEmpty
          ? [AppLocalization.text("Part of the new production cost is unknown.")]
          : Array(Set(messages)).sorted()
      )
    }
    if row.bestSellPrice == nil {
      result.append(
        AppLocalization.text("No sell order at the hub; the sell order cannot be valued."))
    }
    if row.bestBuyPrice == nil {
      result.append(
        AppLocalization.text("No buy order at the hub; the direct sale cannot be valued."))
    } else if row.directDepth == .unknown {
      result.append(AppLocalization.text("The depth of the best buy orders is unknown."))
    }
    return result
  }

  // MARK: Actions

  private func prepareScanRows() {
    guard let analysis else {
      scanRowsByType = [:]
      scanRowsAnalysisID = nil
      return
    }
    scanRowsByType = Dictionary(
      analysis.rows.map { ($0.productTypeID, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    scanRowsAnalysisID = analysis.id
  }

  private func setEfficiency(_ value: Int, kind: EfficiencyKind, entryID: UUID) {
    var updated = entries
    guard let index = updated.firstIndex(where: { $0.id == entryID }) else { return }
    switch kind {
    case .material: updated[index].materialEfficiency = min(10, max(0, value))
    case .time: updated[index].timeEfficiency = min(20, max(0, value))
    }
    updateEntries(updated)
  }

  private func applyPaste(replacing: Bool) async {
    let parsed = StockSalePasteParser.parse(pasteText)
    var messages: [String] = []
    var pasted: [StockSaleEntry] = []
    for error in parsed.errors {
      switch error.reason {
      case .inputTooLarge:
        messages.append(AppLocalization.text("The pasted text is too large. Paste at most 1 MiB."))
      case .tooManyLines:
        messages.append(
          AppLocalization.text("At most 1,000 lines are accepted at once; the rest was ignored."))
      case .missingName, .nameTooLong:
        messages.append(
          AppLocalization.format("Line %lld has no usable item name.", Int64(error.lineNumber))
        )
      case .invalidQuantity:
        pasted.append(
          StockSaleEntry(
            typeID: nil,
            resolvedName: nil,
            pastedName: error.text,
            quantity: 1,
            unresolvedReason: .invalidQuantity
          )
        )
      }
    }
    if !parsed.lines.isEmpty {
      isResolving = true
      defer { isResolving = false }
      let names = parsed.lines.flatMap { $0.candidates.map(\.name) }
      let resolutions: [String: ItemTypeNameResolution]
      do {
        resolutions = try await runtime.resolveItemTypeNames(names)
      } catch {
        pasteMessages = [
          AppLocalization.format(
            "Item names could not be checked against the SDE catalog: %@",
            error.localizedDescription
          )
        ]
        return
      }
      for line in parsed.lines {
        pasted.append(entry(for: line, resolutions: resolutions))
      }
    }
    if parsed.lines.isEmpty, parsed.errors.isEmpty {
      messages.append(AppLocalization.text("Paste at least one item line."))
    }
    pasteMessages = messages
    guard !pasted.isEmpty else { return }
    updateEntries(StockSaleEntryList.merging(entries, with: pasted, replacing: replacing))
    pasteText = ""
  }

  private func entry(
    for line: StockSalePasteLine,
    resolutions: [String: ItemTypeNameResolution]
  ) -> StockSaleEntry {
    var reason = StockSaleUnresolvedReason.unknownName
    for candidate in line.candidates {
      switch resolutions[candidate.name] {
      case .resolved(let typeID, let name, _)?:
        return StockSaleEntry(
          typeID: typeID,
          resolvedName: name,
          pastedName: candidate.name,
          quantity: candidate.quantity
        )
      case .ambiguous?:
        reason = .ambiguousName
      case .localizedNamesUnavailable?:
        if reason == .unknownName { reason = .germanNamesUnavailable }
      case .unknown?, nil:
        break
      }
    }
    return StockSaleEntry(
      typeID: nil,
      resolvedName: nil,
      pastedName: line.text,
      quantity: line.candidates.first?.quantity ?? 1,
      unresolvedReason: reason
    )
  }

  private func loadEntries() {
    guard !hasLoadedEntries else { return }
    hasLoadedEntries = true
    do {
      guard let stored = try modelContext.appSettingValue(for: AppSettingKey.stockSaleItems),
        let data = stored.data(using: .utf8)
      else { return }
      entries = try StockSaleEntryList.decode(data)
    } catch {
      persistenceError = AppLocalization.format(
        "The saved stock sale list could not be read: %@",
        error.localizedDescription
      )
    }
  }

  private func updateEntries(_ updated: [StockSaleEntry]) {
    entries = updated
    do {
      if updated.isEmpty {
        try modelContext.deleteAppSetting(key: AppSettingKey.stockSaleItems)
      } else {
        let data = try StockSaleEntryList.encode(updated)
        try modelContext.upsertAppSetting(
          key: AppSettingKey.stockSaleItems,
          value: String(decoding: data, as: UTF8.self)
        )
      }
      try modelContext.save()
      persistenceError = nil
    } catch {
      modelContext.rollback()
      persistenceError = AppLocalization.format(
        "The stock sale list could not be saved: %@",
        error.localizedDescription
      )
    }
  }

  // MARK: Formatting

  private var locale: Locale { AppLocalization.currentLanguage.locale }

  private func formatNumber(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    } ?? "—"
  }

  private func formatWholeNumber(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0)).locale(locale))
    } ?? "—"
  }

  private func formatInteger(_ value: Int64?) -> String {
    value.map { $0.formatted(.number.locale(locale)) } ?? "—"
  }

  private func formatPercent(_ fraction: Double?) -> String {
    fraction.map {
      $0.formatted(.percent.precision(.fractionLength(2)).locale(locale))
    } ?? "—"
  }
}

private struct StockSaleDisplayRow: Identifiable {
  let entry: StockSaleEntry
  let row: StockSaleComparisonRow
  let supportsEfficiency: Bool
  let issues: [String]

  var id: UUID { entry.id }
}

private struct StockSaleLoyaltyOfferTrigger: Equatable {
  let blueprintTypeIDs: Set<Int64>
  let catalogID: UUID?
  let loyaltyPoints: CharacterLoyaltyPointsSnapshot?
  let wallets: [String: Double]
}
