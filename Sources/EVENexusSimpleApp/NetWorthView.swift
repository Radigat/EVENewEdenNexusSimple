import EVENexusCore
import Foundation
import SwiftData
import SwiftUI

private struct NetWorthComponentDelta: Identifiable {
  let component: NetWorthComponent
  let value: Double

  var id: NetWorthComponent { component }
}

private enum NetWorthHistoryRange: Int, CaseIterable, Identifiable {
  case seven = 7
  case thirty = 30
  case ninety = 90
  case all = 0

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .seven: "7D"
    case .thirty: "30D"
    case .ninety: "90D"
    case .all: AppLocalization.text("All")
    }
  }
}

private enum NetWorthHistoryMode: String, CaseIterable, Identifiable {
  case combined
  case character

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .combined: "Combined"
    case .character: "Per Character"
    }
  }
}

private enum NetWorthComponent: String, CaseIterable, Identifiable {
  case wallet
  case assets
  case orders
  case escrow
  case contracts
  case courier
  case corporationWallet
  case corporationAssets

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .wallet: "Wallet"
    case .assets: "Assets"
    case .orders: "Sell orders"
    case .escrow: "Buy-order escrow"
    case .contracts: "Contracts"
    case .courier: "In transit"
    case .corporationWallet: "Corp Wallet"
    case .corporationAssets: "Corp Assets"
    }
  }

  var icon: String {
    switch self {
    case .wallet: "creditcard.fill"
    case .assets: "shippingbox.fill"
    case .orders: "chart.bar.doc.horizontal.fill"
    case .escrow: "lock.fill"
    case .contracts: "doc.text.fill"
    case .courier: "truck.box.fill"
    case .corporationWallet: "building.columns.fill"
    case .corporationAssets: "building.2.fill"
    }
  }

  var color: Color {
    switch self {
    case .wallet: Color(red: 0.29, green: 0.62, blue: 1)
    case .assets: DesignTokens.positive
    case .orders: DesignTokens.highlight
    case .escrow: Color(red: 0.98, green: 0.45, blue: 0.09)
    case .contracts: Color(red: 0.91, green: 0.47, blue: 0.90)
    case .courier: Color(red: 0.18, green: 0.78, blue: 0.72)
    case .corporationWallet: Color(red: 0.65, green: 0.55, blue: 0.98)
    case .corporationAssets: Color(red: 0.55, green: 0.36, blue: 0.96)
    }
  }

  func value(in snapshot: DashboardWealthSnapshot) -> Double? {
    switch self {
    case .wallet:
      snapshot.walletTotal
        ?? componentTotal(
          snapshot.characters.map(\.walletValue)
        )
    case .assets:
      snapshot.assetTotal
        ?? componentTotal(
          snapshot.characters.map(\.assetValue)
        )
    case .orders:
      snapshot.ordersTotal
        ?? componentTotal(
          snapshot.characters.map(\.ordersValue)
        )
    case .escrow:
      snapshot.escrowTotal
        ?? componentTotal(
          snapshot.characters.map(\.escrowValue)
        )
    case .contracts: snapshot.contractsTotal
    case .courier: snapshot.courierTotal
    case .corporationWallet: snapshot.corporationWalletTotal
    case .corporationAssets: snapshot.corporationAssetTotal
    }
  }

  func value(in character: DashboardWealthCharacterValue) -> Double? {
    switch self {
    case .wallet: character.walletValue
    case .assets: character.assetValue
    case .orders: character.ordersValue
    case .escrow: character.escrowValue
    case .contracts: character.contractsValue
    case .courier: character.courierValue
    case .corporationWallet, .corporationAssets: nil
    }
  }

  private func componentTotal(_ values: [Double?]) -> Double? {
    let known = values.compactMap { $0 }
    return known.isEmpty ? nil : known.reduce(0, +)
  }
}

struct NetWorthView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \AppSetting.key)
  private var settings: [AppSetting]

  @State private var selectedRange: NetWorthHistoryRange = .thirty
  @State private var selectedMode: NetWorthHistoryMode = .combined
  @State private var selectedSnapshotID: UUID?
  @State private var pendingDeletion: DashboardWealthSnapshot?
  @State private var isCapturing = false
  @State private var captureMessage: String?
  @State private var localError: String?
  @State private var unpricedDetails: DashboardWealthCharacterValue?
  @State private var characterSort = AppTableSortDescriptor(
    column: NetWorthCharacterSortColumn.character,
    direction: .ascending
  )

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        if characters.isEmpty {
          emptyState
        } else {
          summary
          historyPanel
          characterBreakdown
          snapshotList
          calculationBasis
        }
      }
      .frame(maxWidth: 1_440, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text("Net Worth"))
    .popover(item: $unpricedDetails) { character in
      unpricedDetailsPanel(character)
    }
    .task(id: wealthInputIdentity) {
      await captureCurrentSnapshot(isManual: false)
    }
    .confirmationDialog(
      "Delete net-worth snapshot?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete Snapshot", role: .destructive) {
        deletePendingSnapshot()
      }
      Button("Cancel", role: .cancel) {
        pendingDeletion = nil
      }
    } message: {
      Text(
        "This removes the selected local history point for all characters. Current ESI data is not deleted."
      )
    }
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
        heading
        Spacer(minLength: DesignTokens.spacingMD)
        rangeAndCaptureControls
      }
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        heading
        rangeAndCaptureControls
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Net Worth History")
        .font(.largeTitle.bold())
      Text(
        "Daily snapshots of personal and accessible corporation value, including contracts and courier collateral."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var rangeAndCaptureControls: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      Picker("History range", selection: $selectedRange) {
        ForEach(NetWorthHistoryRange.allCases) { range in
          Text(range.title).tag(range)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 260)
      .accessibilityIdentifier("net-worth.range")

      Button {
        Task { await captureCurrentSnapshot(isManual: true) }
      } label: {
        if isCapturing {
          ProgressView().controlSize(.small)
        } else {
          Label("Take Snapshot Now", systemImage: "camera.metering.center.weighted")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(isCapturing)
      .accessibilityIdentifier("net-worth.capture")
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No characters connected", systemImage: "person.crop.circle.badge.plus")
    } description: {
      Text("Connect and synchronize at least one character to start the net-worth history.")
    }
  }

  @ViewBuilder
  private var summary: some View {
    if let snapshot = currentSnapshot {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(isDisplayComplete(snapshot) ? "Total net worth" : "Known net worth")
              .font(.caption.weight(.semibold))
              .textCase(.uppercase)
              .tracking(1.1)
              .foregroundStyle(DesignTokens.textSecondary)
            Text(
              snapshot.knownTotalValue.map(formatISK)
                ?? AppLocalization.text("Unavailable")
            )
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(DesignTokens.highlight)
            if let change = latestChange {
              Label(
                signedISK(change),
                systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right"
              )
              .font(.callout.weight(.semibold).monospacedDigit())
              .foregroundStyle(
                change >= 0 ? DesignTokens.positive : DesignTokens.negative
              )
            }
          }
          Spacer()
          freshnessPill(
            isDisplayComplete(snapshot) ? snapshot.freshness : .partial,
            text: isDisplayComplete(snapshot) ? "Complete" : "Known components"
          )
        }
        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 178), spacing: DesignTokens.spacingSM)
          ],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          ForEach(NetWorthComponent.allCases) { component in
            componentCard(component, snapshot: snapshot)
          }
        }
        if !isDisplayComplete(snapshot) {
          Label(
            "The total is partial. Unavailable components are not treated as zero.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
      }
      .padding(DesignTokens.spacingMD)
      .background(DesignTokens.panel)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
      .overlay {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.border)
      }
    }
    if let captureMessage {
      Label(captureMessage, systemImage: "checkmark.circle.fill")
        .font(.caption)
        .foregroundStyle(DesignTokens.positive)
    }
    if let localError {
      Label(localError, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(DesignTokens.negative)
    }
  }

  private func componentCard(
    _ component: NetWorthComponent,
    snapshot: DashboardWealthSnapshot
  ) -> some View {
    let value = component.value(in: snapshot)
    let complete = componentIsComplete(component, snapshot: snapshot)
    return VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      HStack {
        Label {
          Text(component.title)
        } icon: {
          Image(systemName: component.icon)
            .foregroundStyle(component.color)
        }
        .font(.caption.weight(.semibold))
        Spacer()
        Circle()
          .fill(complete ? DesignTokens.positive : DesignTokens.caution)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
      }
      Text(value.map(formatISK) ?? AppLocalization.text("Unavailable"))
        .font(.callout.weight(.semibold).monospacedDigit())
        .foregroundStyle(
          value == nil ? DesignTokens.textSecondary : DesignTokens.textPrimary
        )
      Text(componentStatus(component, snapshot: snapshot))
        .font(.caption2)
        .foregroundStyle(
          complete ? DesignTokens.textSecondary : DesignTokens.caution
        )
        .lineLimit(2)
    }
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
    .accessibilityElement(children: .combine)
  }

  private var historyPanel: some View {
    Panel(title: "Net worth over time") {
      ViewThatFits(in: .horizontal) {
        HStack {
          modePicker
          Spacer()
          chartLegend
        }
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          modePicker
          chartLegend
        }
      }

      if filteredHistory.isEmpty {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Label(
            "No net-worth snapshots have been captured yet.",
            systemImage: "chart.xyaxis.line"
          )
          .foregroundStyle(DesignTokens.textSecondary)
          Button("Take First Snapshot") {
            Task { await captureCurrentSnapshot(isManual: true) }
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
      } else {
        NetWorthHistoryChart(
          snapshots: filteredHistory,
          mode: selectedMode,
          selectedSnapshotID: $selectedSnapshotID
        )
        .frame(minHeight: 390)
        .accessibilityIdentifier("net-worth.chart")

        if hasChangingCoverage {
          Label(
            "Component coverage changes inside this range. The total line shows the known value on each day; unavailable components remain gaps, not zero.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }

        if let selectedChartSnapshot {
          selectedSnapshotDetails(selectedChartSnapshot)
        }
      }
    }
  }

  private var modePicker: some View {
    Picker("Chart mode", selection: $selectedMode) {
      ForEach(NetWorthHistoryMode.allCases) { mode in
        Text(mode.title).tag(mode)
      }
    }
    .pickerStyle(.segmented)
    .frame(width: 270)
    .accessibilityIdentifier("net-worth.mode")
  }

  @ViewBuilder
  private var chartLegend: some View {
    if selectedMode == .combined {
      HStack(spacing: DesignTokens.spacingSM) {
        ForEach(visibleComponents) { component in
          Label {
            Text(component.title)
          } icon: {
            Circle().fill(component.color).frame(width: 7, height: 7)
          }
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Label("Total", systemImage: "minus")
          .font(.caption2)
          .foregroundStyle(DesignTokens.textPrimary)
      }
    } else {
      Text("One line per character")
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func selectedSnapshotDetails(
    _ snapshot: DashboardWealthSnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Divider()
      HStack(alignment: .firstTextBaseline) {
        Text(snapshot.capturedAt.formatted(date: .long, time: .shortened))
          .font(.headline)
        Spacer()
        Text(
          snapshot.knownTotalValue.map(formatISK)
            ?? AppLocalization.text("Unavailable")
        )
        .font(.headline.monospacedDigit())
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 170))],
        alignment: .leading,
        spacing: DesignTokens.spacingSM
      ) {
        ForEach(NetWorthComponent.allCases) { component in
          if let value = component.value(in: snapshot) {
            HStack {
              Circle().fill(component.color).frame(width: 7, height: 7)
              Text(component.title)
                .foregroundStyle(DesignTokens.textSecondary)
              Spacer()
              Text(formatISK(value)).monospacedDigit()
            }
            .font(.caption)
          }
        }
      }
      let deltas = componentDeltas(for: snapshot)
      if !deltas.isEmpty {
        Text("Change by component")
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1)
          .foregroundStyle(DesignTokens.textSecondary)
        ForEach(deltas) { delta in
          HStack {
            Text(delta.component.title)
            Spacer()
            Text(signedISK(delta.value))
              .monospacedDigit()
              .foregroundStyle(
                delta.value >= 0 ? DesignTokens.positive : DesignTokens.negative
              )
          }
          .font(.caption)
        }
      }
    }
  }

  private var characterBreakdown: some View {
    Panel(title: "Per character") {
      if let snapshot = currentSnapshot {
        ScrollView(.horizontal) {
          VStack(spacing: 0) {
            characterHeader
            Divider()
            let sortedCharacters = sortedCharacters(snapshot.characters)
            ForEach(sortedCharacters) { character in
              characterRow(character)
              if character.id != sortedCharacters.last?.id {
                Divider()
              }
            }
          }
          .frame(minWidth: 1_210)
        }
      } else {
        Text("No current valuation is available.")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var characterHeader: some View {
    HStack(spacing: DesignTokens.spacingSM) {
      characterSortHeader("Character", column: .character)
        .frame(minWidth: 190, alignment: .leading)
      characterSortHeader("Wallet", column: .wallet)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("Assets", column: .assets)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("Sell orders", column: .orders)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("Escrow", column: .escrow)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("Contracts", column: .contracts)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("In transit", column: .courier)
        .frame(width: 130, alignment: .trailing)
      characterSortHeader("Total", column: .total)
        .frame(width: 145, alignment: .trailing)
      characterSortHeader("State", column: .state)
        .frame(width: 95, alignment: .trailing)
    }
    .font(.caption.weight(.semibold))
    .textCase(.uppercase)
    .tracking(0.8)
    .foregroundStyle(DesignTokens.textSecondary)
    .padding(.vertical, DesignTokens.spacingSM)
  }

  private func characterSortHeader(
    _ title: LocalizedStringKey,
    column: NetWorthCharacterSortColumn
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $characterSort,
      alignment: column == .character ? .leading : .trailing
    )
  }

  private func sortedCharacters(
    _ characters: [DashboardWealthCharacterValue]
  ) -> [DashboardWealthCharacterValue] {
    characters.sorted { lhs, rhs in
      let ordered: Bool?
      switch characterSort.column {
      case .character:
        ordered = compareCharacterValues(lhs.characterName, rhs.characterName)
      case .wallet:
        ordered = compareOptionalCharacterValues(lhs.walletValue, rhs.walletValue)
      case .assets:
        ordered = compareOptionalCharacterValues(lhs.assetValue, rhs.assetValue)
      case .orders:
        ordered = compareOptionalCharacterValues(lhs.ordersValue, rhs.ordersValue)
      case .escrow:
        ordered = compareOptionalCharacterValues(lhs.escrowValue, rhs.escrowValue)
      case .contracts:
        ordered = compareOptionalCharacterValues(lhs.contractsValue, rhs.contractsValue)
      case .courier:
        ordered = compareOptionalCharacterValues(lhs.courierValue, rhs.courierValue)
      case .total:
        ordered = compareOptionalCharacterValues(lhs.knownValue, rhs.knownValue)
      case .state:
        ordered = compareCharacterValues(
          lhs.isComplete ? 0 : 1,
          rhs.isComplete ? 0 : 1
        )
      }
      return ordered ?? (lhs.id < rhs.id)
    }
  }

  private func compareCharacterValues<Value: Comparable>(
    _ lhs: Value,
    _ rhs: Value
  ) -> Bool? {
    guard lhs != rhs else { return nil }
    return characterSort.direction.orders(lhs, before: rhs)
  }

  private func compareOptionalCharacterValues<Value: Comparable>(
    _ lhs: Value?,
    _ rhs: Value?
  ) -> Bool? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?): return compareCharacterValues(lhs, rhs)
    case (nil, nil): return nil
    case (nil, _): return characterSort.direction == .descending
    case (_, nil): return characterSort.direction == .ascending
    }
  }

  private func characterRow(
    _ character: DashboardWealthCharacterValue
  ) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        EVEEntityText(
          value: character.characterName,
          font: .callout.weight(.semibold),
          lineLimit: 1
        )
        let warnings = characterWarnings(character)
        if !warnings.isEmpty {
          HStack(spacing: DesignTokens.spacingXS) {
            Text(warnings.joined(separator: " · "))
              .font(.caption2)
              .foregroundStyle(DesignTokens.caution)
              .lineLimit(2)
            if character.unvaluedAssetTypeCount > 0
              || character.unvaluedContractItemTypeCount > 0
            {
              Button {
                unpricedDetails = character
              } label: {
                Image(systemName: "info.circle")
              }
              .buttonStyle(.borderless)
              .help("Show unpriced EVE types")
              .accessibilityLabel("Show unpriced EVE types")
            }
          }
        }
      }
      .frame(minWidth: 190, alignment: .leading)
      characterValue(character.walletValue, width: 130)
      characterValue(character.assetValue, width: 130)
      characterValue(character.ordersValue, width: 130)
      characterValue(character.escrowValue, width: 130)
      characterValue(character.contractsValue, width: 130)
      characterValue(character.courierValue, width: 130)
      characterValue(character.knownValue, width: 145, emphasized: true)
      freshnessPill(
        character.isComplete ? character.freshness : .partial,
        text: character.isComplete ? "Complete" : "Partial"
      )
      .frame(width: 95, alignment: .trailing)
    }
    .padding(.vertical, DesignTokens.spacingSM)
    .accessibilityElement(children: .combine)
  }

  private func characterValue(
    _ value: Double?,
    width: CGFloat,
    emphasized: Bool = false
  ) -> some View {
    Text(value.map(formatISK) ?? AppLocalization.text("Unavailable"))
      .font(
        emphasized
          ? .callout.weight(.semibold).monospacedDigit()
          : .callout.monospacedDigit()
      )
      .foregroundStyle(
        value == nil ? DesignTokens.textSecondary : DesignTokens.textPrimary
      )
      .frame(width: width, alignment: .trailing)
  }

  private var snapshotList: some View {
    Panel(title: "Snapshots") {
      if filteredHistory.isEmpty {
        Text("No snapshots in the selected range.")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ForEach(Array(filteredHistory.reversed())) { snapshot in
          HStack(spacing: DesignTokens.spacingSM) {
            Button {
              selectedSnapshotID = snapshot.id
            } label: {
              HStack(spacing: DesignTokens.spacingSM) {
                Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .omitted))
                  .frame(minWidth: 105, alignment: .leading)
                if !isDisplayComplete(snapshot) {
                  Text("PARTIAL")
                    .font(.caption2.bold())
                    .foregroundStyle(DesignTokens.caution)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.caution.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(
              snapshot.knownTotalValue.map(formatISK)
                ?? AppLocalization.text("Unavailable")
            )
            .font(.callout.weight(.semibold).monospacedDigit())
            .frame(minWidth: 150, alignment: .trailing)
            if let delta = delta(for: snapshot) {
              Text(signedISK(delta))
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                  delta >= 0 ? DesignTokens.positive : DesignTokens.negative
                )
                .frame(minWidth: 112, alignment: .trailing)
            } else {
              Text("—")
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(minWidth: 112, alignment: .trailing)
            }
            Button {
              pendingDeletion = snapshot
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this snapshot")
            .accessibilityLabel("Delete snapshot")
          }
          if snapshot.id != filteredHistory.first?.id {
            Divider()
          }
        }
      }
    }
  }

  private var calculationBasis: some View {
    Panel(title: "Calculation basis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Label(
          "Assets use ESI average prices, with adjusted prices only as the declared fallback. Blueprint copies are excluded.",
          systemImage: "chart.line.uptrend.xyaxis"
        )
        Label(
          "Reference prices are public ESI data and need no SSO scope. If ESI temporarily omits a type, its value remains unknown until a later snapshot.",
          systemImage: "network"
        )
        Label(
          "Active sell orders use remaining quantity × order price. Buy-order escrow is included only when ESI supplies the escrow amount.",
          systemImage: "list.bullet.rectangle"
        )
        Label(
          "Own outstanding item and auction contracts use included items at the same reference-price policy. Requested items and blueprint copies are excluded.",
          systemImage: "doc.text.magnifyingglass"
        )
        Label(
          "In transit is the collateral of own personal courier contracts currently in progress; it is an estimate because ESI does not expose the cargo value.",
          systemImage: "truck.box"
        )
        Label(
          "Corporation assets and wallet divisions are included once per accessible corporation. Director is required for assets; Accountant or Junior Accountant is required for wallet balances.",
          systemImage: "building.2"
        )
        Label(
          "One local history point is retained per calendar day while the app runs with current data. Manual capture replaces that day's point.",
          systemImage: "clock.arrow.circlepath"
        )
      }
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var currentSnapshot: DashboardWealthSnapshot? {
    runtime.dashboardWealthSnapshot ?? wealthHistory.last
  }

  private var wealthHistory: [DashboardWealthSnapshot] {
    guard
      let encoded = settings.first(where: {
        $0.key == AppSettingKey.dashboardWealthHistory
      })?.value,
      let data = Data(base64Encoded: encoded),
      let history = try? JSONDecoder().decode(
        [DashboardWealthSnapshot].self,
        from: data
      )
    else { return [] }
    return history.sorted { $0.capturedAt < $1.capturedAt }
  }

  private var filteredHistory: [DashboardWealthSnapshot] {
    guard selectedRange != .all,
      let end = wealthHistory.last?.capturedAt,
      let start = Calendar.current.date(
        byAdding: .day,
        value: -(selectedRange.rawValue - 1),
        to: end
      )
    else { return wealthHistory }
    return wealthHistory.filter { $0.capturedAt >= start }
  }

  private var selectedChartSnapshot: DashboardWealthSnapshot? {
    if let selectedSnapshotID,
      let selected = filteredHistory.first(where: { $0.id == selectedSnapshotID })
    {
      return selected
    }
    return filteredHistory.last
  }

  private var visibleComponents: [NetWorthComponent] {
    NetWorthComponent.allCases.filter { component in
      filteredHistory.contains { component.value(in: $0) != nil }
    }
  }

  private var hasChangingCoverage: Bool {
    let signatures = Set(
      filteredHistory.map { snapshot in
        NetWorthComponent.allCases.map {
          $0.value(in: snapshot) == nil ? "0" : "1"
        }.joined()
      })
    return signatures.count > 1
  }

  private var latestChange: Double? {
    guard wealthHistory.count > 1,
      let latest = wealthHistory.last?.knownTotalValue,
      let previous = wealthHistory.dropLast().last?.knownTotalValue
    else { return nil }
    return latest - previous
  }

  private var wealthInputs: [DashboardWealthCharacterInput] {
    characters.map { character in
      DashboardWealthCharacterInput(
        character: CharacterIdentity(
          id: character.characterID,
          name: character.characterName,
          corporationID: character.corporationID
        ),
        wallet: storedWalletBalance(character),
        assets: storedAssetSnapshot(character),
        openOrders: storedOpenOrders(character),
        privateContracts: storedPrivateContracts(character),
        corporationAssets: storedCorporationAssetSnapshot(character),
        corporationWallet: storedCorporationWallet(character)
      )
    }
  }

  private var wealthInputIdentity: String {
    characters.map {
      "\($0.characterID):\($0.lastSyncAt?.timeIntervalSince1970 ?? -1):\($0.walletLastSyncAt?.timeIntervalSince1970 ?? -1)"
    }.joined(separator: "|")
  }

  private func storedWalletBalance(
    _ character: StoredCharacter
  ) -> Sourced<Double> {
    if let data = character.walletBalanceSnapshot,
      let value = try? JSONDecoder().decode(Sourced<Double>.self, from: data)
    {
      return value
    }
    return unavailableSource(
      capturedAt: character.walletLastSyncAt,
      diagnostic: "wallet.not-synchronized"
    )
  }

  private func storedAssetSnapshot(
    _ character: StoredCharacter
  ) -> Sourced<AssetSnapshot> {
    if let data = character.assetSnapshot,
      let value = try? JSONDecoder().decode(
        Sourced<AssetSnapshot>.self,
        from: data
      )
    {
      return value
    }
    return unavailableSource(
      capturedAt: character.lastSyncAt,
      diagnostic: "assets.not-synchronized"
    )
  }

  private func storedOpenOrders(
    _ character: StoredCharacter
  ) -> Sourced<[ESICharacterOrderDTO]> {
    guard
      let encoded = settings.first(where: {
        $0.key == AppSettingKey.openOrders(characterID: character.characterID)
      })?.value,
      let data = Data(base64Encoded: encoded),
      let value = try? JSONDecoder().decode(
        Sourced<[ESICharacterOrderDTO]>.self,
        from: data
      )
    else {
      return unavailableSource(
        capturedAt: character.lastSyncAt,
        diagnostic: "orders.not-synchronized"
      )
    }
    return value
  }

  private func storedPrivateContracts(
    _ character: StoredCharacter
  ) -> Sourced<PrivateContractSnapshot> {
    storedSettingSnapshot(
      key: AppSettingKey.privateContracts(
        characterID: character.characterID
      ),
      capturedAt: character.lastSyncAt,
      diagnostic: "private-contracts.not-synchronized"
    )
  }

  private func storedCorporationWallet(
    _ character: StoredCharacter
  ) -> Sourced<CorporationWalletSnapshot> {
    storedSettingSnapshot(
      key: AppSettingKey.corporationWallet(
        characterID: character.characterID
      ),
      capturedAt: character.lastSyncAt,
      diagnostic: "corporation-wallet.not-synchronized"
    )
  }

  private func storedCorporationAssetSnapshot(
    _ character: StoredCharacter
  ) -> Sourced<AssetSnapshot> {
    if let data = character.corporationAssetSnapshot,
      let value = try? JSONDecoder().decode(
        Sourced<AssetSnapshot>.self,
        from: data
      )
    {
      return value
    }
    return unavailableSource(
      capturedAt: character.lastSyncAt,
      diagnostic: "corporation-assets.not-synchronized"
    )
  }

  private func storedSettingSnapshot<Value: Codable & Sendable>(
    key: String,
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    guard
      let encoded = settings.first(where: { $0.key == key })?.value,
      let data = Data(base64Encoded: encoded),
      let value = try? JSONDecoder().decode(Sourced<Value>.self, from: data)
    else {
      return unavailableSource(
        capturedAt: capturedAt,
        diagnostic: diagnostic
      )
    }
    return value
  }

  private func unavailableSource<Value: Codable & Sendable>(
    capturedAt: Date?,
    diagnostic: String
  ) -> Sourced<Value> {
    Sourced(
      state: .unavailable,
      value: nil,
      source: SourceIdentity(
        provider: "Local",
        version: "not-synchronized",
        capturedAt: capturedAt ?? .distantPast
      ),
      diagnostics: [diagnostic]
    )
  }

  private func captureCurrentSnapshot(isManual: Bool) async {
    guard !isCapturing, !wealthInputs.isEmpty else { return }
    isCapturing = true
    localError = nil
    if isManual { captureMessage = nil }
    defer { isCapturing = false }

    await runtime.refreshDashboardWealth(inputs: wealthInputs)
    guard let snapshot = runtime.dashboardWealthSnapshot else {
      localError =
        runtime.dashboardWealthError.map(AppLocalization.text)
        ?? AppLocalization.text("The current net worth is unavailable.")
      return
    }
    do {
      try persist(snapshot)
      selectedSnapshotID = snapshot.id
      if isManual {
        captureMessage = AppLocalization.text(
          "The current values were captured for today."
        )
      }
    } catch {
      modelContext.rollback()
      localError = AppLocalization.text(
        "The net-worth history could not be saved. Existing history was not replaced."
      )
    }
  }

  private func persist(_ snapshot: DashboardWealthSnapshot) throws {
    var history = wealthHistory
    let calendar = Calendar(identifier: .gregorian)
    if let index = history.lastIndex(where: {
      calendar.isDate($0.capturedAt, inSameDayAs: snapshot.capturedAt)
    }) {
      history[index] = snapshot
    } else {
      history.append(snapshot)
    }
    history = Array(
      history.sorted { $0.capturedAt < $1.capturedAt }.suffix(365)
    )
    let data = try JSONEncoder().encode(history)
    try modelContext.upsertAppSetting(
      key: AppSettingKey.dashboardWealthHistory,
      value: data.base64EncodedString()
    )
    try modelContext.save()
  }

  private func deletePendingSnapshot() {
    guard let pendingDeletion else { return }
    localError = nil
    do {
      let retained = wealthHistory.filter { $0.id != pendingDeletion.id }
      let data = try JSONEncoder().encode(retained)
      try modelContext.upsertAppSetting(
        key: AppSettingKey.dashboardWealthHistory,
        value: data.base64EncodedString()
      )
      try modelContext.save()
      if selectedSnapshotID == pendingDeletion.id {
        selectedSnapshotID = retained.last?.id
      }
      self.pendingDeletion = nil
    } catch {
      modelContext.rollback()
      localError = AppLocalization.text(
        "The selected snapshot could not be deleted."
      )
    }
  }

  private func componentIsComplete(
    _ component: NetWorthComponent,
    snapshot: DashboardWealthSnapshot
  ) -> Bool {
    guard !snapshot.characters.isEmpty else { return false }
    switch component {
    case .wallet:
      return snapshot.characters.allSatisfy { component.value(in: $0) != nil }
    case .assets:
      return snapshot.characters.allSatisfy {
        $0.assetValue != nil && $0.unvaluedAssetTypeCount == 0
      }
    case .orders:
      return snapshot.characters.allSatisfy {
        $0.ordersValue != nil && $0.unvaluedOrderCount == 0
      }
    case .escrow:
      return snapshot.characters.allSatisfy {
        $0.escrowValue != nil && $0.missingEscrowOrderCount == 0
      }
    case .contracts, .courier:
      return snapshot.characters.allSatisfy { component.value(in: $0) != nil }
        && componentFreshness(component, snapshot: snapshot) == .fresh
    case .corporationWallet, .corporationAssets:
      return component.value(in: snapshot) != nil
        && componentFreshness(component, snapshot: snapshot) == .fresh
    }
  }

  private func componentStatus(
    _ component: NetWorthComponent,
    snapshot: DashboardWealthSnapshot
  ) -> String {
    if componentIsComplete(component, snapshot: snapshot) {
      if component == .corporationWallet || component == .corporationAssets {
        return AppLocalization.text("Accessible corporations included")
      }
      return AppLocalization.text("All characters included")
    }
    if component == .corporationWallet,
      let coverage = snapshot.corporationWalletCoverage
    {
      return corporationCoverageStatus(
        coverage,
        requiredRole: "Accountant or Junior Accountant"
      )
    }
    if component == .corporationAssets,
      let coverage = snapshot.corporationAssetCoverage
    {
      return corporationCoverageStatus(
        coverage,
        requiredRole: "Director"
      )
    }
    if component.value(in: snapshot) != nil {
      if component == .assets {
        let missing = snapshot.characters.reduce(0) {
          $0 + $1.unvaluedAssetTypeCount
        }
        if missing > 0 {
          return AppLocalization.format(
            "%lld unpriced asset type entries; no SSO scope required",
            Int64(missing)
          )
        }
      }
      switch componentFreshness(component, snapshot: snapshot) {
      case .stale:
        return AppLocalization.text("Last-known value; refresh required")
      case .partial:
        return AppLocalization.text("Known value; coverage incomplete")
      case .forbidden:
        return AppLocalization.text("Permission or corporation role missing")
      case .unavailable:
        return AppLocalization.text("Value currently unavailable")
      case .fresh, nil:
        break
      }
    }
    let included = snapshot.characters.filter {
      component.value(in: $0) != nil
    }.count
    if included > 0 {
      return AppLocalization.format(
        "%lld of %lld characters included",
        Int64(included),
        Int64(snapshot.characters.count)
      )
    }
    switch component {
    case .contracts, .courier:
      return AppLocalization.text("Private contracts not synchronized")
    case .corporationWallet, .corporationAssets:
      return AppLocalization.text("Corporation value not synchronized")
    default:
      return AppLocalization.text("Synchronize or reauthorize characters")
    }
  }

  private func characterWarnings(
    _ character: DashboardWealthCharacterValue
  ) -> [String] {
    var warnings: [String] = []
    if character.unvaluedAssetTypeCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld asset types unpriced",
          Int64(character.unvaluedAssetTypeCount)
        )
      )
    }
    if character.excludedBlueprintCopyCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld BPC stacks excluded",
          Int64(character.excludedBlueprintCopyCount)
        )
      )
    }
    if character.unvaluedOrderCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld sell orders invalid",
          Int64(character.unvaluedOrderCount)
        )
      )
    }
    if character.missingEscrowOrderCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld buy orders without escrow",
          Int64(character.missingEscrowOrderCount)
        )
      )
    }
    if character.unvaluedContractItemTypeCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld contract item types unpriced",
          Int64(character.unvaluedContractItemTypeCount)
        )
      )
    }
    if character.excludedContractBlueprintCopyCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld contract BPC stacks excluded",
          Int64(character.excludedContractBlueprintCopyCount)
        )
      )
    }
    if character.unavailableContractCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld contracts not fully read",
          Int64(character.unavailableContractCount)
        )
      )
    }
    if character.invalidCourierCollateralCount > 0 {
      warnings.append(
        AppLocalization.format(
          "%lld courier contracts without valid collateral",
          Int64(character.invalidCourierCollateralCount)
        )
      )
    }
    return warnings
  }

  private func corporationCoverageStatus(
    _ coverage: DashboardWealthCorporationCoverage,
    requiredRole: String
  ) -> String {
    if coverage.roleMissingCorporationCount > 0 {
      return AppLocalization.format(
        "%lld of %lld corporations included; %@ role missing for %lld",
        Int64(coverage.includedCorporationCount),
        Int64(coverage.corporationCount),
        AppLocalization.text(requiredRole),
        Int64(coverage.roleMissingCorporationCount)
      )
    }
    if coverage.unvaluedAssetTypeCount > 0 {
      return AppLocalization.format(
        "%lld corporation asset types unpriced",
        Int64(coverage.unvaluedAssetTypeCount)
      )
    }
    return AppLocalization.format(
      "%lld of %lld corporations included",
      Int64(coverage.includedCorporationCount),
      Int64(coverage.corporationCount)
    )
  }

  private func unpricedDetailsPanel(
    _ character: DashboardWealthCharacterValue
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Unpriced EVE types")
        .font(.headline)
      Text(character.characterName)
        .font(.subheadline)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(
        "These types were absent from the public ESI reference-price response when this snapshot was created. No additional SSO scope can provide them."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      if character.unvaluedAssetTypes.isEmpty
        && character.unvaluedContractItemTypes.isEmpty
      {
        Text(
          "Type names are not stored in this older snapshot. Take a new snapshot to capture the detailed list."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            if !character.unvaluedAssetTypes.isEmpty {
              Text("Assets")
                .font(.caption.weight(.semibold))
              ForEach(character.unvaluedAssetTypes) { type in
                EVEEntityText(value: type.name, font: .caption)
              }
            }
            if !character.unvaluedContractItemTypes.isEmpty {
              Text("Contract items")
                .font(.caption.weight(.semibold))
                .padding(.top, DesignTokens.spacingXS)
              ForEach(character.unvaluedContractItemTypes) { type in
                EVEEntityText(value: type.name, font: .caption)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
      }
    }
    .padding(DesignTokens.spacingMD)
    .frame(width: 420, alignment: .leading)
  }

  private func componentFreshness(
    _ component: NetWorthComponent,
    snapshot: DashboardWealthSnapshot
  ) -> DataFreshness? {
    switch component {
    case .contracts: snapshot.contractsFreshness
    case .courier: snapshot.courierFreshness
    case .corporationWallet: snapshot.corporationWalletFreshness
    case .corporationAssets: snapshot.corporationAssetFreshness
    case .wallet, .assets, .orders, .escrow: nil
    }
  }

  private func componentDeltas(
    for snapshot: DashboardWealthSnapshot
  ) -> [NetWorthComponentDelta] {
    guard let index = filteredHistory.firstIndex(where: { $0.id == snapshot.id }),
      index > filteredHistory.startIndex
    else { return [] }
    let previous = filteredHistory[filteredHistory.index(before: index)]
    return NetWorthComponent.allCases.compactMap { component in
      guard let currentValue = component.value(in: snapshot),
        let previousValue = component.value(in: previous),
        currentValue != previousValue
      else { return nil }
      return NetWorthComponentDelta(
        component: component,
        value: currentValue - previousValue
      )
    }.sorted { abs($0.value) > abs($1.value) }
  }

  private func delta(for snapshot: DashboardWealthSnapshot) -> Double? {
    guard let index = wealthHistory.firstIndex(where: { $0.id == snapshot.id }),
      index > wealthHistory.startIndex,
      let current = snapshot.knownTotalValue,
      let previous = wealthHistory[
        wealthHistory.index(before: index)
      ].knownTotalValue
    else { return nil }
    return current - previous
  }

  private func freshnessPill(
    _ state: DataFreshness,
    text: LocalizedStringKey
  ) -> some View {
    let color: Color =
      switch state {
      case .fresh: DesignTokens.positive
      case .partial, .stale: DesignTokens.caution
      case .forbidden, .unavailable: DesignTokens.negative
      }
    return Text(text)
      .font(.caption2.bold())
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .foregroundStyle(color)
      .background(color.opacity(0.14))
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func formatISK(_ value: Double) -> String {
    value.formatted(.currency(code: "ISK").precision(.fractionLength(0)))
  }

  private func signedISK(_ value: Double) -> String {
    let formatted = formatISK(abs(value))
    return "\(value >= 0 ? "+" : "−")\(formatted)"
  }

  private func isDisplayComplete(_ snapshot: DashboardWealthSnapshot) -> Bool {
    snapshot.isComplete
      && snapshot.freshness == .fresh
      && snapshot.contractsFreshness == .fresh
      && snapshot.courierFreshness == .fresh
      && (snapshot.corporationWalletFreshness == nil
        || snapshot.corporationWalletFreshness == .fresh)
      && (snapshot.corporationAssetFreshness == nil
        || snapshot.corporationAssetFreshness == .fresh)
  }
}

private enum NetWorthCharacterSortColumn: Hashable {
  case character
  case wallet
  case assets
  case orders
  case escrow
  case contracts
  case courier
  case total
  case state
}

private struct NetWorthHistoryChart: View {
  let snapshots: [DashboardWealthSnapshot]
  let mode: NetWorthHistoryMode
  @Binding var selectedSnapshotID: UUID?

  private let characterColors: [Color] = [
    Color(red: 0.29, green: 0.62, blue: 1),
    DesignTokens.positive,
    DesignTokens.highlight,
    DesignTokens.negative,
    Color(red: 0.65, green: 0.55, blue: 0.98),
    Color(red: 0.18, green: 0.78, blue: 0.72),
    Color(red: 0.98, green: 0.45, blue: 0.09),
  ]

  var body: some View {
    GeometryReader { proxy in
      let plot = CGRect(
        x: 58,
        y: 14,
        width: max(1, proxy.size.width - 76),
        height: max(1, proxy.size.height - 52)
      )
      ZStack {
        Canvas { context, _ in
          drawGrid(context: &context, plot: plot)
          if mode == .combined {
            drawCombined(context: &context, plot: plot)
          } else {
            drawCharacters(context: &context, plot: plot)
          }
          drawSelection(context: &context, plot: plot)
        }
        chartLabels(plot: plot)
      }
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          selectNearest(to: location.x, plot: plot)
        case .ended:
          break
        }
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            selectNearest(to: value.location.x, plot: plot)
          }
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Net-worth history chart")
    .accessibilityValue(accessibilitySummary)
  }

  private func drawGrid(
    context: inout GraphicsContext,
    plot: CGRect
  ) {
    for step in 0...4 {
      let y = plot.minY + plot.height * CGFloat(step) / 4
      var line = Path()
      line.move(to: CGPoint(x: plot.minX, y: y))
      line.addLine(to: CGPoint(x: plot.maxX, y: y))
      context.stroke(
        line,
        with: .color(DesignTokens.border.opacity(0.45)),
        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
      )
    }
  }

  private func drawCombined(
    context: inout GraphicsContext,
    plot: CGRect
  ) {
    let completeComponents = NetWorthComponent.allCases.filter { component in
      snapshots.allSatisfy { component.value(in: $0) != nil }
    }
    let scale = maximumValue
    var lower = Array(repeating: 0.0, count: snapshots.count)
    for component in completeComponents {
      let upper = snapshots.enumerated().map { index, snapshot in
        lower[index] + (component.value(in: snapshot) ?? 0)
      }
      guard upper.contains(where: { $0 > 0 }) else {
        lower = upper
        continue
      }
      let upperPoints = upper.enumerated().map { index, value in
        point(index: index, value: value, scale: scale, plot: plot)
      }
      let lowerPoints = lower.enumerated().map { index, value in
        point(index: index, value: value, scale: scale, plot: plot)
      }
      var area = Path()
      if let first = upperPoints.first {
        area.move(to: first)
        for point in upperPoints.dropFirst() { area.addLine(to: point) }
        for point in lowerPoints.reversed() { area.addLine(to: point) }
        area.closeSubpath()
        context.fill(area, with: .color(component.color.opacity(0.22)))
      }
      var edge = Path()
      for (offset, point) in upperPoints.enumerated() {
        if offset == 0 { edge.move(to: point) } else { edge.addLine(to: point) }
      }
      context.stroke(
        edge,
        with: .color(component.color.opacity(0.8)),
        lineWidth: 1.4
      )
      lower = upper
    }

    drawLine(
      context: &context,
      values: snapshots.map(\.knownTotalValue),
      color: DesignTokens.textPrimary,
      width: 2.4,
      scale: scale,
      plot: plot
    )
  }

  private func drawCharacters(
    context: inout GraphicsContext,
    plot: CGRect
  ) {
    let identities = Dictionary(
      grouping: snapshots.flatMap(\.characters),
      by: \.characterID
    ).values.compactMap(\.first).sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    for (offset, identity) in identities.enumerated() {
      let values = snapshots.map { snapshot in
        snapshot.characters.first {
          $0.characterID == identity.characterID
        }?.knownValue
      }
      drawLine(
        context: &context,
        values: values,
        color: characterColors[offset % characterColors.count],
        width: 2,
        scale: maximumValue,
        plot: plot
      )
    }
  }

  private func drawLine(
    context: inout GraphicsContext,
    values: [Double?],
    color: Color,
    width: CGFloat,
    scale: Double,
    plot: CGRect
  ) {
    var path = Path()
    var hasCurrentSegment = false
    for (index, value) in values.enumerated() {
      guard let value, value.isFinite else {
        hasCurrentSegment = false
        continue
      }
      let point = point(index: index, value: value, scale: scale, plot: plot)
      if hasCurrentSegment {
        path.addLine(to: point)
      } else {
        path.move(to: point)
        hasCurrentSegment = true
      }
    }
    context.stroke(
      path,
      with: .color(color),
      style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    )
  }

  private func drawSelection(
    context: inout GraphicsContext,
    plot: CGRect
  ) {
    guard let selectedSnapshotID,
      let index = snapshots.firstIndex(where: { $0.id == selectedSnapshotID })
    else { return }
    let x = xPosition(index: index, plot: plot)
    var line = Path()
    line.move(to: CGPoint(x: x, y: plot.minY))
    line.addLine(to: CGPoint(x: x, y: plot.maxY))
    context.stroke(
      line,
      with: .color(DesignTokens.accent.opacity(0.9)),
      style: StrokeStyle(lineWidth: 1, dash: [3, 3])
    )
  }

  @ViewBuilder
  private func chartLabels(plot: CGRect) -> some View {
    let firstDate = snapshots.first?.capturedAt
    let lastDate = snapshots.last?.capturedAt
    Text(compactISK(maximumValue))
      .font(.caption2.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
      .position(x: 26, y: plot.minY + 6)
    Text("0")
      .font(.caption2.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
      .position(x: 42, y: plot.maxY - 4)
    if let firstDate {
      Text(firstDate.formatted(date: .abbreviated, time: .omitted))
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
        .position(x: plot.minX + 38, y: plot.maxY + 24)
    }
    if let lastDate {
      Text(lastDate.formatted(date: .abbreviated, time: .omitted))
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
        .position(x: plot.maxX - 38, y: plot.maxY + 24)
    }
  }

  private var maximumValue: Double {
    let combined = snapshots.compactMap(\.knownTotalValue)
    let perCharacter = snapshots.flatMap(\.characters).compactMap(\.knownValue)
    let values = mode == .combined ? combined : perCharacter
    return max((values.max() ?? 0) * 1.08, 1)
  }

  private func point(
    index: Int,
    value: Double,
    scale: Double,
    plot: CGRect
  ) -> CGPoint {
    CGPoint(
      x: xPosition(index: index, plot: plot),
      y: plot.maxY - plot.height * CGFloat(max(0, value) / scale)
    )
  }

  private func xPosition(index: Int, plot: CGRect) -> CGFloat {
    guard snapshots.count > 1 else { return plot.midX }
    return plot.minX
      + plot.width * CGFloat(index) / CGFloat(snapshots.count - 1)
  }

  private func selectNearest(to x: CGFloat, plot: CGRect) {
    guard !snapshots.isEmpty else { return }
    let ratio = min(max((x - plot.minX) / plot.width, 0), 1)
    let index = Int(
      (ratio * CGFloat(max(0, snapshots.count - 1))).rounded()
    )
    selectedSnapshotID = snapshots[index].id
  }

  private func compactISK(_ value: Double) -> String {
    let magnitude = abs(value)
    if magnitude >= 1_000_000_000_000 {
      return String(format: "%.1fT", value / 1_000_000_000_000)
    }
    if magnitude >= 1_000_000_000 {
      return String(format: "%.1fB", value / 1_000_000_000)
    }
    if magnitude >= 1_000_000 {
      return String(format: "%.1fM", value / 1_000_000)
    }
    return value.formatted(.number.precision(.fractionLength(0)))
  }

  private var accessibilitySummary: String {
    guard let latest = snapshots.last,
      let value = latest.knownTotalValue
    else { return AppLocalization.text("No values") }
    return AppLocalization.format(
      "%lld snapshots, latest %@",
      Int64(snapshots.count),
      value.formatted(.currency(code: "ISK").precision(.fractionLength(0)))
    )
  }
}
