import EVENexusCore
import SwiftData
import SwiftUI

private enum BlueprintListFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case originals = "BPO"
  case copies = "BPC"

  var id: Self { self }
}

struct BlueprintsView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]

  @State private var selectedBlueprintID: Int64?
  @State private var filter: BlueprintListFilter = .all
  @State private var searchText = ""
  @State private var portfolio = BlueprintPortfolio(inventories: [])
  @State private var entriesByID: [Int64: BlueprintPortfolioEntry] = [:]
  @State private var sortedEntries: [BlueprintPortfolioEntry] = []
  @State private var visibleEntries: [BlueprintPortfolioEntry] = []
  @State private var visibleEntryLimit = Self.entryPageSize
  @State private var typeNames: [Int64: String] = [:]
  @State private var locationNames: [Int64: String] = [:]
  @State private var quote: BlueprintResearchCostQuote?
  @State private var quoteError: String?
  @State private var isLoadingQuote = false
  @State private var isPreparingPortfolio = true
  @State private var isResolvingNames = false
  @State private var storedSourceCount = 0
  @State private var unreadableSourceCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      if isPreparingPortfolio {
        ContentUnavailableView {
          Label("Preparing blueprints…", systemImage: "doc.on.doc")
        } description: {
          Text(
            "Stored blueprint snapshots are being prepared outside the user interface."
          )
        }
        .overlay { ProgressView() }
      } else if storedSourceCount == 0 {
        ContentUnavailableView {
          Label("No stored blueprints", systemImage: "doc.on.doc")
        } description: {
          Text(
            "Open Characters and run Sync all. Blueprint lists are stored per character for offline use after the next synchronization."
          )
        }
      } else {
        sourceNotice
        GeometryReader { geometry in
          if geometry.size.width >= 860 {
            horizontalBlueprintLayout
          } else {
            verticalBlueprintLayout
          }
        }
      }
    }
    .padding(DesignTokens.spacingLG)
    .navigationTitle(AppLocalization.text("Blueprints"))
    .task(id: storedPortfolioIdentity) {
      await preparePortfolio()
    }
    .task(id: quoteIdentity) {
      await loadQuote()
    }
    .onChange(of: filter) {
      rebuildVisibleEntries()
      selectFirstVisibleBlueprintIfNeeded()
    }
    .onChange(of: searchText) {
      rebuildVisibleEntries()
      selectFirstVisibleBlueprintIfNeeded()
    }
  }

  private var horizontalBlueprintLayout: some View {
    HSplitView {
      blueprintList
        .frame(minWidth: 280, idealWidth: 360, maxWidth: 470)
      detail
        .frame(minWidth: 520, maxWidth: .infinity)
    }
  }

  private var verticalBlueprintLayout: some View {
    VStack(spacing: DesignTokens.spacingMD) {
      blueprintList
        .frame(minHeight: 220, idealHeight: 280, maxHeight: 340)
      Divider()
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Blueprints")
          .font(.largeTitle.bold())
        Text(
          "Owned originals and copies from every stored character, with current ME/TE replacement estimates."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer()
      if isResolvingNames || isLoadingQuote {
        ProgressView()
          .controlSize(.small)
      }
      Text("\(portfolio.entries.count) blueprints")
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  @ViewBuilder
  private var sourceNotice: some View {
    if unreadableSourceCount > 0 {
      Label(
        AppLocalization.format(
          "%d stored blueprint snapshot(s) could not be read. Synchronize the affected character again; other readable snapshots remain available.",
          unreadableSourceCount
        ),
        systemImage: "exclamationmark.octagon.fill"
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.negative)
    }
    if portfolio.sourceStates.contains(where: { $0 != .fresh }) {
      Label(
        "At least one character's blueprint source is partial, stale, forbidden or unavailable. Source state remains visible per blueprint.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.caution)
    }
  }

  private var blueprintList: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      TextField("Search blueprints or owners", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("blueprints.search")
      Picker("Blueprint kind", selection: $filter) {
        ForEach(BlueprintListFilter.allCases) {
          Text(LocalizedStringKey($0.rawValue)).tag($0)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("blueprints.filter")

      if portfolio.entries.isEmpty {
        ContentUnavailableView {
          Label("No blueprints found", systemImage: "doc.on.doc")
        } description: {
          Text(
            "The stored character snapshots are available, but they do not contain any owned blueprints."
          )
        }
      } else if visibleEntries.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        List(selection: $selectedBlueprintID) {
          ForEach(visibleEntries.prefix(visibleEntryLimit)) { entry in
            blueprintRow(entry)
              .tag(entry.id)
              .accessibilityIdentifier("blueprints.row.\(entry.id)")
          }
          if visibleEntries.count > visibleEntryLimit {
            Button {
              visibleEntryLimit += Self.entryPageSize
            } label: {
              Label(
                AppLocalization.format(
                  "Show %d more blueprints",
                  min(
                    Self.entryPageSize,
                    visibleEntries.count - visibleEntryLimit
                  )
                ),
                systemImage: "chevron.down.circle"
              )
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("blueprints.load-more")
          }
        }
        .listStyle(.inset)
      }
    }
  }

  private func blueprintRow(_ entry: BlueprintPortfolioEntry) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        EVEEntityText(
          value: typeName(entry.instance.blueprintTypeID),
          lineLimit: 1
        )
        Spacer()
        kindBadge(entry.instance.kind)
        freshnessBadge(entry.sourceState)
      }
      HStack(spacing: DesignTokens.spacingMD) {
        Label(entry.ownerName, systemImage: "person.fill")
        Image(systemName: "mappin.and.ellipse")
        EVEEntityText(value: locationName(entry.instance.locationID))
      }
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      HStack {
        Text("ME \(entry.instance.materialEfficiency)%")
        Text("TE \(entry.instance.timeEfficiency)%")
        if entry.instance.kind == .copy {
          Text("\(entry.instance.runs) runs")
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(DesignTokens.highlight)
    }
    .padding(.vertical, 3)
  }

  @ViewBuilder
  private var detail: some View {
    if let entry = selectedEntry {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          blueprintIdentity(entry)
          efficiencyStatus(entry)
          if entry.instance.kind == .original {
            valuation
            researchTable
            calculationBasis
          } else {
            Panel(title: "Research") {
              Label(
                "Blueprint copies cannot be researched. Their ME and TE values were inherited when the copy was created or invented.",
                systemImage: "lock.fill"
              )
              .foregroundStyle(DesignTokens.textSecondary)
            }
          }
        }
        .padding(.leading, DesignTokens.spacingMD)
      }
    } else {
      ContentUnavailableView(
        "Select a blueprint",
        systemImage: "doc.text.magnifyingglass"
      )
    }
  }

  private func blueprintIdentity(_ entry: BlueprintPortfolioEntry) -> some View {
    Panel(title: "Blueprint") {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          EVEEntityText(
            value: typeName(entry.instance.blueprintTypeID),
            font: .title2.bold()
          )
          HStack(spacing: DesignTokens.spacingXS) {
            Text(verbatim: entry.ownerName)
              .foregroundStyle(DesignTokens.textSecondary)
            Text(verbatim: "·")
              .foregroundStyle(DesignTokens.textSecondary)
            EVEEntityText(value: locationName(entry.instance.locationID))
          }
        }
        Spacer()
        kindBadge(entry.instance.kind)
      }
    }
  }

  private func efficiencyStatus(
    _ entry: BlueprintPortfolioEntry
  ) -> some View {
    Panel(title: "Current efficiency") {
      HStack(spacing: DesignTokens.spacingLG) {
        efficiencyMetric(
          "Material efficiency",
          value: entry.instance.materialEfficiency,
          maximum: 10,
          color: DesignTokens.positive
        )
        efficiencyMetric(
          "Time efficiency",
          value: entry.instance.timeEfficiency,
          maximum: 20,
          color: DesignTokens.information
        )
        if entry.instance.kind == .copy {
          summaryMetric(
            "Licensed runs",
            value: entry.instance.runs.formatted(),
            color: DesignTokens.highlight
          )
        }
      }
    }
  }

  @ViewBuilder
  private var valuation: some View {
    Panel(title: "Replacement estimate") {
      if isLoadingQuote {
        ProgressView("Calculating current research costs…")
      } else if let quoteError {
        Label(quoteError, systemImage: "xmark.octagon.fill")
          .foregroundStyle(DesignTokens.negative)
        Button("Retry") {
          Task { await loadQuote() }
        }
      } else if let quote {
        HStack(spacing: DesignTokens.spacingLG) {
          summaryMetric(
            "SDE base price",
            value: isk(quote.rawBlueprintBasePrice),
            color: DesignTokens.textPrimary
          )
          summaryMetric(
            "Research to current ME/TE",
            value: isk(quote.currentTotalResearchValue),
            color: DesignTokens.highlight
          )
          summaryMetric(
            "Current replacement estimate",
            value: isk(quote.estimatedReplacementValue),
            color: DesignTokens.positive
          )
          summaryMetric(
            "Still to ME 10 / TE 20",
            value: isk(quote.remainingTotalResearchCost),
            color: DesignTokens.information
          )
        }
        Text(
          "This is a current reproduction estimate, not the historical amount paid and not a guaranteed contract sale price."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        warningList(quote.warnings)
      } else {
        Text("Select a blueprint to calculate its replacement estimate.")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  @ViewBuilder
  private var researchTable: some View {
    Panel(title: "ME and TE research levels") {
      if let quote {
        ScrollView(.horizontal) {
          Grid(
            alignment: .leading,
            horizontalSpacing: 18,
            verticalSpacing: 8
          ) {
            GridRow {
              tableHeader("Level")
              tableHeader("ME target")
              tableHeader("ME level cost")
              tableHeader("ME cumulative")
              tableHeader("TE target")
              tableHeader("TE level cost")
              tableHeader("TE cumulative")
            }
            Divider()
            ForEach(quote.levels) { level in
              GridRow {
                Text(level.level.formatted())
                researchTargetCell(
                  level.materialEfficiencyTarget,
                  isResearched: quote.isMaterialLevelResearched(level.level),
                  color: DesignTokens.positive,
                  activityName: "ME"
                )
                costCell(level.materialStepCost)
                costCell(level.materialCumulativeCost)
                researchTargetCell(
                  level.timeEfficiencyTarget,
                  isResearched: quote.isTimeLevelResearched(level.level),
                  color: DesignTokens.information,
                  activityName: "TE"
                )
                costCell(level.timeStepCost)
                costCell(level.timeCumulativeCost)
              }
            }
          }
          .padding(.bottom, DesignTokens.spacingXS)
        }
      } else if isLoadingQuote {
        ProgressView()
      } else {
        Text("Research costs are unavailable.")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  @ViewBuilder
  private var calculationBasis: some View {
    if let quote {
      Panel(title: "Calculation basis") {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
          GridRow {
            Text("Manufacturing EIV basis")
            Text(isk(quote.manufacturingBaseCost))
              .font(.body.monospacedDigit())
          }
          if let facility = quote.materialFacility {
            facilityRow("ME", facility: facility)
          }
          if let facility = quote.timeFacility {
            facilityRow("TE", facility: facility)
          }
        }
        Text(
          AppLocalization.format(
            "Prices updated %@",
            quote.adjustedPriceSource.capturedAt.formatted()
          )
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func facilityRow(
    _ label: String,
    facility: BlueprintResearchFacilityContext
  ) -> some View {
    GridRow {
      Text("\(label) facility")
      Text(
        "\(facility.facilityName), \(facility.solarSystemName) · index \(facility.systemCostIndex.formatted(.number.precision(.fractionLength(4)))) · tax \((facility.facilityTaxRate * 100).formatted(.number.precision(.fractionLength(2))))%"
      )
      .font(.caption.monospacedDigit())
    }
  }

  @ViewBuilder
  private func warningList(_ warnings: [DomainWarning]) -> some View {
    ForEach(warnings) { warning in
      Label(
        warning.message,
        systemImage:
          warning.severity == .blocking
          ? "exclamationmark.octagon.fill"
          : "exclamationmark.triangle.fill"
      )
      .font(.caption)
      .foregroundStyle(
        warning.severity == .blocking
          ? DesignTokens.negative : DesignTokens.caution
      )
    }
  }

  private func tableHeader(_ text: String) -> some View {
    Text(text)
      .font(.caption.bold())
      .foregroundStyle(DesignTokens.textSecondary)
  }

  private func costCell(_ value: Double?) -> some View {
    Text(isk(value))
      .font(.body.monospacedDigit())
      .frame(minWidth: 126, alignment: .trailing)
  }

  private func researchTargetCell(
    _ target: Int,
    isResearched: Bool,
    color: Color,
    activityName: String
  ) -> some View {
    HStack(spacing: 5) {
      Text("\(target)%")
      if isResearched {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(color)
          .accessibilityLabel(
            "\(activityName) \(target) percent included in current value"
          )
      }
    }
  }

  private func efficiencyMetric(
    _ title: String,
    value: Int,
    maximum: Int,
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text("\(value)% / \(maximum)%")
        .font(.title2.bold().monospacedDigit())
        .foregroundStyle(color)
      ProgressView(value: Double(max(0, value)), total: Double(maximum))
        .tint(color)
        .frame(width: 190)
    }
  }

  private func summaryMetric(
    _ title: String,
    value: String,
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value)
        .font(.title3.bold().monospacedDigit())
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func kindBadge(_ kind: BlueprintCopyKind) -> some View {
    let text: String
    let color: Color
    switch kind {
    case .original:
      text = "BPO"
      color = DesignTokens.positive
    case .copy:
      text = "BPC"
      color = DesignTokens.information
    case .unknown:
      text = "UNKNOWN"
      color = DesignTokens.caution
    }
    return Text(text)
      .font(.caption2.bold())
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.18))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }

  private func freshnessBadge(_ state: DataFreshness) -> some View {
    Text(LocalizedStringKey(state.rawValue.uppercased()))
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(freshnessColor(state).opacity(0.18))
      .foregroundStyle(freshnessColor(state))
      .clipShape(Capsule())
  }

  private func freshnessColor(_ state: DataFreshness) -> Color {
    switch state {
    case .fresh: DesignTokens.positive
    case .partial, .stale: DesignTokens.caution
    case .forbidden, .unavailable: DesignTokens.negative
    }
  }

  private func rebuildVisibleEntries() {
    let acceptedSearch = searchText.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    visibleEntries = sortedEntries.filter { entry in
      let kindMatches: Bool
      switch filter {
      case .all:
        kindMatches = true
      case .originals:
        kindMatches = entry.instance.kind == .original
      case .copies:
        kindMatches = entry.instance.kind == .copy
      }
      guard kindMatches else { return false }
      guard !acceptedSearch.isEmpty else { return true }
      return typeName(entry.instance.blueprintTypeID)
        .localizedCaseInsensitiveContains(acceptedSearch)
        || entry.ownerName.localizedCaseInsensitiveContains(acceptedSearch)
    }
    visibleEntryLimit = Self.entryPageSize
  }

  private var selectedEntry: BlueprintPortfolioEntry? {
    guard let selectedBlueprintID else { return nil }
    return entriesByID[selectedBlueprintID]
  }

  private var storedPortfolioIdentity: String {
    characters.map {
      "\($0.characterID):\($0.characterName):\($0.lastSyncAt?.timeIntervalSince1970 ?? 0)"
    }.joined(separator: ",")
  }

  private var quoteIdentity: String {
    let selected = selectedEntry?.id ?? 0
    let indexSnapshot =
      runtime.industrySystemIndices?.source.snapshotID.uuidString ?? "none"
    let indexState =
      runtime.industrySystemIndices?.state.rawValue ?? "unavailable"
    return
      "\(selected)|\(researchBasisIdentity(.materialResearch))|\(researchBasisIdentity(.timeResearch))|\(runtime.productionBasis.cloneState.rawValue)|\(indexSnapshot)|\(indexState)|\(runtime.productionBasis.ruleVersion)"
  }

  private func researchBasisIdentity(
    _ activity: IndustryActivitySystem
  ) -> String {
    guard
      let system = runtime.productionBasis.systemConfiguration(for: activity)
    else { return "\(activity.rawValue):missing-system" }
    guard
      let selection = runtime.productionBasis.scienceSelection(for: activity),
      let structure = runtime.productionBasis.structure(id: selection.structureID)
    else {
      return
        "\(activity.rawValue):\(system.solarSystemID):\(system.costIndexOverride ?? -1):missing-facility"
    }
    return [
      activity.rawValue,
      String(system.solarSystemID),
      String(system.costIndexOverride ?? -1),
      selection.structureID.uuidString,
      String(selection.jobCostMultiplier),
      String(selection.needsReview),
      String(structure.facilityTaxRate),
    ].joined(separator: ":")
  }

  private func preparePortfolio() async {
    isPreparingPortfolio = true
    isResolvingNames = false
    quote = nil
    quoteError = nil

    let snapshots = characters.compactMap { character in
      character.blueprintSnapshot.map {
        StoredBlueprintSnapshot(
          ownerID: character.characterID,
          ownerName: character.characterName,
          data: $0
        )
      }
    }
    let prepared = await Task.detached(priority: .userInitiated) {
      PreparedBlueprintPortfolio(snapshots: snapshots)
    }.value
    guard !Task.isCancelled else { return }

    portfolio = prepared.portfolio
    entriesByID = prepared.entriesByID
    storedSourceCount = snapshots.count
    unreadableSourceCount = prepared.unreadableSourceCount
    isPreparingPortfolio = false
    isResolvingNames = !prepared.portfolio.entries.isEmpty
    guard !prepared.portfolio.entries.isEmpty else {
      sortedEntries = []
      visibleEntries = []
      selectedBlueprintID = nil
      return
    }

    let typeIDs = prepared.typeIDs
    let locationIDs = Set(
      prepared.portfolio.entries.lazy.map(\.instance.locationID)
        .filter { $0 < 1_000_000_000_000 }
    )
    async let resolvedTypes = runtime.resolveAssetTypeNames(typeIDs)
    async let resolvedLocations = runtime.resolveAssetLocationNames(
      locationIDs
    )
    let names = await resolvedTypes
    let locations = await resolvedLocations.value ?? [:]
    guard !Task.isCancelled else { return }

    let unknownItem = "Unknown item".localizedUI
    let orderedEntries = await Task.detached(priority: .userInitiated) {
      prepared.portfolio.entries.sorted { left, right in
        let leftName =
          names[left.instance.blueprintTypeID] ?? unknownItem
        let rightName =
          names[right.instance.blueprintTypeID] ?? unknownItem
        let nameComparison = leftName.localizedCaseInsensitiveCompare(
          rightName
        )
        if nameComparison != .orderedSame {
          return nameComparison == .orderedAscending
        }
        if left.ownerName != right.ownerName {
          return left.ownerName.localizedCaseInsensitiveCompare(
            right.ownerName
          ) == .orderedAscending
        }
        return left.id < right.id
      }
    }.value
    guard !Task.isCancelled else { return }

    typeNames = names
    locationNames = locations
    sortedEntries = orderedEntries
    isResolvingNames = false
    rebuildVisibleEntries()
    selectFirstVisibleBlueprintIfNeeded()
  }

  private func loadQuote() async {
    quote = nil
    quoteError = nil
    guard let entry = selectedEntry,
      entry.instance.kind == .original
    else {
      isLoadingQuote = false
      return
    }
    let requestedBlueprintID = entry.id
    isLoadingQuote = true
    do {
      let loadedQuote = try await runtime.blueprintResearchQuote(
        for: entry.instance
      )
      guard !Task.isCancelled,
        selectedEntry?.id == requestedBlueprintID
      else { return }
      quote = loadedQuote
      isLoadingQuote = false
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled,
        selectedEntry?.id == requestedBlueprintID
      else { return }
      quoteError = error.localizedDescription
      isLoadingQuote = false
    }
  }

  private func selectFirstVisibleBlueprintIfNeeded() {
    if let selectedBlueprintID,
      visibleEntries.prefix(visibleEntryLimit).contains(where: {
        $0.id == selectedBlueprintID
      })
    {
      return
    }
    selectedBlueprintID = visibleEntries.first?.id
  }

  private func typeName(_ typeID: Int64) -> String {
    typeNames[typeID] ?? "Unknown item".localizedUI
  }

  private func locationName(_ locationID: Int64) -> String {
    if let configured = runtime.productionBasis.structures.first(where: {
      $0.structureID == locationID
    }) {
      return configured.displayName
    }
    return locationNames[locationID] ?? "Unknown location".localizedUI
  }

  private func isk(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Unavailable" }
    return
      value.formatted(
        .number.grouping(.automatic).precision(.fractionLength(0))
      )
      + " ISK"
  }

  private static let entryPageSize = 300
}

private struct StoredBlueprintSnapshot: Sendable {
  let ownerID: Int64
  let ownerName: String
  let data: Data
}

private struct PreparedBlueprintPortfolio: Sendable {
  let portfolio: BlueprintPortfolio
  let entriesByID: [Int64: BlueprintPortfolioEntry]
  let typeIDs: Set<Int64>
  let unreadableSourceCount: Int

  init(snapshots: [StoredBlueprintSnapshot]) {
    var inventories: [OwnedBlueprintInventory] = []
    var unreadableSourceCount = 0
    inventories.reserveCapacity(snapshots.count)

    for snapshot in snapshots {
      guard
        let blueprints = try? JSONDecoder().decode(
          Sourced<[OwnedBlueprintInstance]>.self,
          from: snapshot.data
        )
      else {
        unreadableSourceCount += 1
        continue
      }
      inventories.append(
        OwnedBlueprintInventory(
          ownerID: snapshot.ownerID,
          ownerName: snapshot.ownerName,
          blueprints: blueprints
        )
      )
    }

    let portfolio = BlueprintPortfolio(inventories: inventories)
    self.portfolio = portfolio
    entriesByID = Dictionary(
      portfolio.entries.map { ($0.id, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    typeIDs = Set(portfolio.entries.map(\.instance.blueprintTypeID))
    self.unreadableSourceCount = unreadableSourceCount
  }
}
