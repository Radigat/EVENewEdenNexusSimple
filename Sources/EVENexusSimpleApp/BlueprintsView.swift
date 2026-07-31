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
  @State private var typeNames: [Int64: String] = [:]
  @State private var locationNames: [Int64: String] = [:]
  @State private var quote: BlueprintResearchCostQuote?
  @State private var quoteError: String?
  @State private var isLoadingQuote = false
  @State private var isResolvingNames = false

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      if inventories.isEmpty {
        ContentUnavailableView {
          Label("No stored blueprints", systemImage: "doc.on.doc")
        } description: {
          Text(
            "Open Characters and run Sync all. Blueprint lists are stored per character for offline use after the next synchronization."
          )
        }
      } else {
        sourceNotice
        HSplitView {
          blueprintList
            .frame(minWidth: 330, idealWidth: 390, maxWidth: 470)
          detail
            .frame(minWidth: 650, maxWidth: .infinity)
        }
      }
    }
    .padding(DesignTokens.spacingLG)
    .navigationTitle(AppLocalization.text("Blueprints"))
    .task(id: portfolioIdentity) {
      await resolveNames()
      selectFirstVisibleBlueprintIfNeeded()
    }
    .task(id: quoteIdentity) {
      await loadQuote()
    }
    .onChange(of: filter) {
      selectFirstVisibleBlueprintIfNeeded()
    }
    .onChange(of: searchText) {
      selectFirstVisibleBlueprintIfNeeded()
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
      } else if filteredEntries.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        List(filteredEntries, selection: $selectedBlueprintID) { entry in
          blueprintRow(entry)
            .tag(entry.id)
            .accessibilityIdentifier("blueprints.row.\(entry.id)")
        }
        .listStyle(.inset)
      }
    }
  }

  private func blueprintRow(_ entry: BlueprintPortfolioEntry) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(typeName(entry.instance.blueprintTypeID))
          .font(.headline)
          .lineLimit(1)
        Spacer()
        kindBadge(entry.instance.kind)
        freshnessBadge(entry.sourceState)
      }
      HStack(spacing: DesignTokens.spacingMD) {
        Label(entry.ownerName, systemImage: "person.fill")
        Label(
          locationName(entry.instance.locationID),
          systemImage: "mappin.and.ellipse"
        )
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
          Text(typeName(entry.instance.blueprintTypeID))
            .font(.title2.bold())
          Text(
            "\(entry.ownerName) · \(locationName(entry.instance.locationID))"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        kindBadge(entry.instance.kind)
      }
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
        GridRow {
          technicalValue("Item ID", value: entry.instance.id.formatted())
          technicalValue(
            "Type ID",
            value: entry.instance.blueprintTypeID.formatted()
          )
          technicalValue(
            "Source",
            value:
              "\(entry.instance.source.provider) \(entry.instance.source.version)"
          )
        }
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
          "Rule \(quote.ruleVersion) · SDE \(quote.definitionSource.version) · adjusted prices \(quote.adjustedPriceSource.capturedAt.formatted())"
        )
        .font(.caption.monospaced())
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

  private func technicalValue(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value)
        .font(.caption.monospaced())
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

  private var inventories: [OwnedBlueprintInventory] {
    characters.compactMap { character in
      guard let data = character.blueprintSnapshot,
        let blueprints = try? JSONDecoder().decode(
          Sourced<[OwnedBlueprintInstance]>.self,
          from: data
        )
      else { return nil }
      return OwnedBlueprintInventory(
        ownerID: character.characterID,
        ownerName: character.characterName,
        blueprints: blueprints
      )
    }
  }

  private var portfolio: BlueprintPortfolio {
    BlueprintPortfolio(inventories: inventories)
  }

  private var filteredEntries: [BlueprintPortfolioEntry] {
    let acceptedSearch = searchText.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return portfolio.entries.filter { entry in
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
    .sorted {
      let nameComparison = typeName($0.instance.blueprintTypeID)
        .localizedCaseInsensitiveCompare(
          typeName($1.instance.blueprintTypeID)
        )
      if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
      }
      if $0.ownerName != $1.ownerName {
        return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
          == .orderedAscending
      }
      return $0.id < $1.id
    }
  }

  private var selectedEntry: BlueprintPortfolioEntry? {
    guard let selectedBlueprintID else { return nil }
    return portfolio.entries.first { $0.id == selectedBlueprintID }
  }

  private var portfolioIdentity: String {
    portfolio.snapshotIDs.map(\.uuidString).sorted().joined(separator: ",")
      + "|"
      + characters.map {
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

  private func resolveNames() async {
    isResolvingNames = true
    defer { isResolvingNames = false }
    let typeIDs = Set(portfolio.entries.map(\.instance.blueprintTypeID))
    let locationIDs = Set(
      portfolio.entries.lazy
        .map(\.instance.locationID)
        .filter { $0 < 1_000_000_000_000 }
    )
    async let resolvedTypes = runtime.resolveAssetTypeNames(typeIDs)
    async let resolvedLocations = runtime.resolveAssetLocationNames(
      locationIDs
    )
    typeNames = await resolvedTypes
    locationNames = await resolvedLocations.value ?? [:]
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
      filteredEntries.contains(where: { $0.id == selectedBlueprintID })
    {
      return
    }
    selectedBlueprintID = filteredEntries.first?.id
  }

  private func typeName(_ typeID: Int64) -> String {
    typeNames[typeID] ?? "Type \(typeID)"
  }

  private func locationName(_ locationID: Int64) -> String {
    if let configured = runtime.productionBasis.structures.first(where: {
      $0.structureID == locationID
    }) {
      return configured.displayName
    }
    return locationNames[locationID] ?? "Location \(locationID)"
  }

  private func isk(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Unavailable" }
    return
      value.formatted(
        .number.grouping(.automatic).precision(.fractionLength(0))
      )
      + " ISK"
  }
}
