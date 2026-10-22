import EVENexusCore
import SwiftUI

struct PublicContractsView: View {
  @EnvironmentObject private var runtime: RuntimeState

  @State private var itemQuery = ""
  @State private var selectedCategoryID: Int64?
  @State private var selectedGroupID: Int64?
  @State private var direction: PublicContractItemDirection = .included
  @State private var explicitSearchSequence = 0
  @State private var pendingExplicitSearchIdentity: SearchIdentity?
  @AppStorage("contracts.disclosure.esi-safe", store: AppDefaults.store)
  private var isSyncStatusExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      header
      if runtime.publicContractProgress.failedRegions > 0 {
        Label(
          regionFailureDescription,
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(DesignTokens.caution)
      }
      syncStatus
      if runtime.publicContractStoreState == .ready, isInitialImport {
        firstImportNotice
      }
      filters
      if let error = runtime.publicContractError {
        Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(DesignTokens.negative)
      }
      results
    }
    .padding(DesignTokens.spacingLG)
    .task {
      await runtime.loadPublicContractBrowser()
    }
    .task(id: searchTaskIdentity) {
      let request = searchIdentity
      let isExplicitSubmission = pendingExplicitSearchIdentity == request
      if isExplicitSubmission {
        pendingExplicitSearchIdentity = nil
      }
      if let delay = PublicContractSearchPolicy.delay(
        isExplicitSubmission: isExplicitSubmission
      ) {
        do {
          try await Task.sleep(for: delay)
        } catch {
          return
        }
      }
      await search(request)
    }
    .onChange(of: runtime.isSynchronizingPublicContracts) { wasRunning, isRunning in
      guard wasRunning, !isRunning else { return }
      let request = searchIdentity
      Task { await search(request) }
    }
    .onChange(of: selectedCategoryID) { _, categoryID in
      if let selectedGroupID,
        !runtime.publicContractGroups.contains(where: {
          $0.id == selectedGroupID
            && (categoryID == nil || $0.parentID == categoryID)
        })
      {
        self.selectedGroupID = nil
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Public Contracts")
          .font(.largeTitle.bold())
          .foregroundStyle(DesignTokens.textPrimary)
        Text(
          "Build a local, resumable index of public contracts from every ESI region, then search by item, group and category."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer(minLength: DesignTokens.spacingMD)
      if runtime.publicContractStoreState == .preparing {
        HStack(spacing: DesignTokens.spacingSM) {
          ProgressView().controlSize(.small)
          Text("Preparing local Public Contracts database")
            .font(.callout)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("public-contracts.store-preparing")
      } else if runtime.publicContractStoreState == .failed {
        Button {
          runtime.retryPublicContractStorePreparation()
        } label: {
          Label("Retry local index", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("public-contracts.store-retry")
      } else if runtime.isSynchronizingPublicContracts {
        Button(role: .cancel) {
          runtime.cancelPublicContractSynchronization()
        } label: {
          Label(
            "Stop and disable automatic updates",
            systemImage: "stop.circle"
          )
        }
      } else {
        HStack(spacing: DesignTokens.spacingSM) {
          if runtime.publicContractAutomaticUpdatesEnabled {
            Button(role: .cancel) {
              runtime.cancelPublicContractSynchronization()
            } label: {
              Label("Pause automatic updates", systemImage: "pause.circle")
            }
          }
          Button {
            runtime.startPublicContractSynchronization()
          } label: {
            Label(
              startButtonTitle,
              systemImage: "arrow.triangle.2.circlepath"
            )
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private var syncStatus: some View {
    DisclosurePanel(
      title: "ESI-safe synchronization",
      isExpanded: $isSyncStatusExpanded
    ) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 120),
              spacing: DesignTokens.spacingLG,
              alignment: .leading
            )
          ],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          statusMetric(
            "First import",
            "\(runtime.publicContractProgress.completedRegions)/\(runtime.publicContractProgress.regionCount)"
          )
          statusMetric(
            "Fresh regions",
            formatQuantity(runtime.publicContractProgress.freshRegions)
          )
          statusMetric(
            "Region errors",
            formatQuantity(runtime.publicContractProgress.failedRegions)
          )
          statusMetric(
            "Contracts",
            formatQuantity(runtime.publicContractProgress.indexedContracts)
          )
          statusMetric(
            "Indexed items",
            formatQuantity(runtime.publicContractProgress.indexedItems)
          )
          statusMetric(
            "Details pending",
            formatQuantity(runtime.publicContractProgress.pendingItemContracts)
          )
        }
        if runtime.isSynchronizingPublicContracts {
          ProgressView(value: progressValue)
          HStack {
            Label(
              progressLabel,
              systemImage: "hourglass"
            )
            Spacer()
            if let next = runtime.publicContractProgress.nextRequestAt {
              Text("Next allowed request: \(next.formatted(date: .omitted, time: .standard))")
            }
          }
          .font(.caption)
        } else {
          Label(statusLabel, systemImage: statusIcon)
            .foregroundStyle(statusColor)
        }
        if runtime.publicContractProgress.failedRegions > 0 {
          Label(
            regionFailureDescription,
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(DesignTokens.caution)
          if let next = runtime.publicContractProgress.failedRegionRetryAt {
            Label(
              AppLocalization.format(
                "Earliest failed-region retry: %@",
                next.formatted(date: .abbreviated, time: .shortened)
              ),
              systemImage: "clock.arrow.circlepath"
            )
            .font(.caption)
          }
        }
        if runtime.publicContractAutomaticUpdatesEnabled {
          if let scheduledAt = runtime.publicContractNextAutomaticRunAt {
            Label(
              "Automatic update scheduled for \(scheduledAt.formatted(date: .abbreviated, time: .shortened))",
              systemImage: "clock.badge.checkmark"
            )
          } else {
            Label(
              "Automatic continuation and six-hour updates are enabled",
              systemImage: "checkmark.circle"
            )
          }
        } else {
          Label(
            "Automatic continuation is disabled",
            systemImage: "pause.circle"
          )
        }
        Text(
          "After one manual start, unfinished work resumes automatically and a completed index is checked no more than every six hours. ESI expiry and rate-limit headers can postpone every run."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Label(
          "Public Contracts use public ESI endpoints and require no character, corporation role or Corporation Assets scope. A Corporation Assets authorization failure is reported separately and cannot block this importer.",
          systemImage: "lock.open"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var firstImportNotice: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      Image(systemName: "exclamationmark.octagon.fill")
        .font(.title2.weight(.bold))
        .accessibilityHidden(true)
      Text(
        "Important: The first import of all contracts that are still active at that time can take two to three days. It continues in the background while the app is running and resumes after the next app launch. You can leave this section at any time and control the import from the navigation sidebar. During this time, the app can be slower. Import performance will continue to be optimized."
      )
      .font(.headline.weight(.bold))
      .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(DesignTokens.negative)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.negative.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.negative, lineWidth: 2)
    }
    .accessibilityElement(children: .combine)
  }

  private var filters: some View {
    Panel(title: "Contract filters") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 180),
              spacing: DesignTokens.spacingMD,
              alignment: .leading
            )
          ],
          spacing: DesignTokens.spacingSM
        ) {
          TextField("Item name (3+ characters), e.g. Ark", text: $itemQuery)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              pendingExplicitSearchIdentity = searchIdentity
              explicitSearchSequence &+= 1
            }
          Picker("Category", selection: $selectedCategoryID) {
            Text("All categories").tag(Int64?.none)
            ForEach(runtime.publicContractCategories) { category in
              Text("\(category.name) (\(category.resultCount))")
                .tag(Optional(category.id))
            }
          }
          Picker("Group", selection: $selectedGroupID) {
            Text("All groups").tag(Int64?.none)
            ForEach(visibleGroups) { group in
              Text("\(group.name) (\(group.resultCount))")
                .tag(Optional(group.id))
            }
          }
        }
        Picker("Contract side", selection: $direction) {
          Text("Offered").tag(PublicContractItemDirection.included)
          Text("Requested").tag(PublicContractItemDirection.requested)
          Text("Both").tag(PublicContractItemDirection.both)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        Text(
          "Example: search for “Ark”, then select Category “Ship” and Group “Jump Freighter” to exclude Arkonor and unrelated matches."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Text(
          "The search starts after a short typing pause. Press Return to search immediately."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .disabled(runtime.publicContractStoreState != .ready)
  }

  @ViewBuilder private var results: some View {
    if itemQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 3,
      selectedCategoryID == nil,
      selectedGroupID == nil
    {
      Spacer()
      ContentUnavailableView(
        "Search the local contract index",
        systemImage: "doc.text.magnifyingglass",
        description: Text(
          "Enter at least three characters or select a group/category. You can search the already indexed portion while synchronization continues."
        )
      )
      Spacer()
    } else if runtime.publicContractResults.isEmpty {
      Spacer()
      ContentUnavailableView(
        "No indexed contracts found",
        systemImage: "doc.text.magnifyingglass",
        description: Text(
          runtime.publicContractProgress.pendingItemContracts > 0
            ? "Matching details may still be waiting in the safe indexing queue."
            : "Adjust the item, category, group or offered/requested filter."
        )
      )
      Spacer()
    } else {
      HStack {
        Text("Matching contracts").font(.title3.bold())
        Text("\(runtime.publicContractResults.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
      }
      GeometryReader { geometry in
        ScrollView {
          LazyVGrid(
            columns: resultColumns(for: geometry.size.width),
            spacing: DesignTokens.spacingSM
          ) {
            ForEach(runtime.publicContractResults) { result in
              resultRow(result)
            }
          }
        }
      }
    }
  }

  private func resultRow(_ result: PublicContractSearchResult) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingSM) {
        EVEItemText(
          value: result.typeName ?? "Unknown item".localizedUI,
          typeID: result.typeID
        )
        .lineLimit(2)
        Text(result.isIncluded ? "Offered" : "Requested")
          .font(.caption.bold())
          .padding(.horizontal, DesignTokens.spacingSM)
          .padding(.vertical, 3)
          .background(
            result.isIncluded ? DesignTokens.accentSoft : DesignTokens.caution.opacity(0.16)
          )
          .clipShape(Capsule())
        Text("× \(result.quantity)")
          .font(.callout.monospacedDigit())
        Spacer()
        Text(verbatim: formatPrice(result.price ?? result.buyout ?? result.reward))
          .font(.headline.monospacedDigit())
          .lineLimit(1)
          .layoutPriority(1)
      }
      Label {
        Text(verbatim: metadataLine(result))
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "map")
      }
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      if let title = result.title, !title.isEmpty {
        Text(verbatim: title)
          .font(.callout)
          .textSelection(.enabled)
      }
      if result.isBlueprintCopy != nil || result.runs != nil {
        HStack(spacing: DesignTokens.spacingSM) {
          Text(
            result.runs == -1
              ? "BPO"
              : result.isBlueprintCopy == true ? "BPC" : "Blueprint unresolved"
          )
          if let runs = result.runs, runs >= 0 {
            Text(AppLocalization.format("%@ runs", runs.formatted()))
          }
          if let me = result.materialEfficiency {
            Text(verbatim: "ME \(me)")
          }
          if let te = result.timeEfficiency {
            Text(verbatim: "TE \(te)")
          }
          if result.isAttributableBlueprintOffer {
            Label("Cost attributable", systemImage: "checkmark.seal.fill")
              .foregroundStyle(DesignTokens.positive)
          } else {
            Label("Bundle or incomplete", systemImage: "questionmark.diamond")
              .foregroundStyle(DesignTokens.caution)
          }
        }
        .font(.caption.monospacedDigit())
      }
    }
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var visibleGroups: [PublicContractFacet] {
    guard let selectedCategoryID else { return runtime.publicContractGroups }
    return runtime.publicContractGroups.filter {
      $0.parentID == selectedCategoryID
    }
  }

  private func resultColumns(for width: CGFloat) -> [GridItem] {
    let column = GridItem(
      .flexible(minimum: 0),
      spacing: DesignTokens.spacingSM,
      alignment: .top
    )
    return width >= 800 ? [column, column] : [column]
  }

  private var isInitialImport: Bool {
    let progress = runtime.publicContractProgress
    return progress.regionCount == 0
      || progress.pendingItemContracts > 0
      || progress.completedRegions < progress.regionCount
  }

  private var startButtonTitle: LocalizedStringKey {
    if runtime.publicContractProgress.indexedContracts == 0 {
      return "Start first import"
    }
    if runtime.publicContractAutomaticUpdatesEnabled {
      return "Refresh now"
    }
    return "Continue and enable automatic updates"
  }

  private var searchIdentity: SearchIdentity {
    SearchIdentity(
      query: itemQuery,
      categoryID: selectedCategoryID,
      groupID: selectedGroupID,
      direction: direction
    )
  }

  private var searchTaskIdentity: SearchTaskIdentity {
    SearchTaskIdentity(
      request: searchIdentity,
      explicitSearchSequence: explicitSearchSequence
    )
  }

  private func search(_ request: SearchIdentity) async {
    await runtime.searchPublicContracts(
      PublicContractSearchFilter(
        itemQuery: request.query,
        groupID: request.groupID,
        categoryID: request.categoryID,
        direction: request.direction
      )
    )
  }

  private var progressValue: Double {
    let progress = runtime.publicContractProgress
    switch progress.phase {
    case .loadingRegions:
      return 0.01
    case .loadingContracts:
      guard progress.regionCount > 0 else { return 0.05 }
      return 0.05 + 0.35 * Double(progress.completedRegions)
        / Double(progress.regionCount)
    case .loadingItems:
      let total = progress.indexedContracts
      guard total > 0 else { return 0.4 }
      return 0.4 + 0.6 * Double(total - progress.pendingItemContracts)
        / Double(total)
    case .completed:
      return 1
    default:
      return 0
    }
  }

  private var progressLabel: String {
    let progress = runtime.publicContractProgress
    if let region = progress.activeRegionName {
      return "Loading contracts: \(region)"
    }
    if progress.activeContractID != nil {
      return "Indexing item details"
    }
    return "Preparing Public Contracts index"
  }

  private var statusLabel: String {
    switch runtime.publicContractStoreState {
    case .preparing:
      return "Preparing local Public Contracts database".localizedUI
    case .failed:
      return "Local Public Contracts database unavailable".localizedUI
    case .disabled:
      return "Public Contracts background services are disabled".localizedUI
    case .ready:
      break
    }
    if runtime.publicContractProgress.failedRegions > 0,
      runtime.publicContractProgress.phase == .idle
    {
      return "Partial index preserved; failed regions will retry automatically"
        .localizedUI
    }
    return switch runtime.publicContractProgress.phase {
    case .completed:
      "Index is current according to ESI cache windows".localizedUI
    case .partial:
      "Partial index preserved; continue when convenient".localizedUI
    case .cancelled:
      "Stopped safely; progress is stored locally".localizedUI
    case .throttled:
      "ESI requested a pause; no further requests are being sent".localizedUI
    case .failed:
      "Index unavailable".localizedUI
    default:
      "Ready to build or continue the local index".localizedUI
    }
  }

  private var statusIcon: String {
    switch runtime.publicContractStoreState {
    case .preparing: return "hourglass"
    case .failed: return "externaldrive.badge.xmark"
    case .disabled: return "pause.circle"
    case .ready: break
    }
    if runtime.publicContractProgress.failedRegions > 0,
      runtime.publicContractProgress.phase == .idle
    {
      return "exclamationmark.triangle.fill"
    }
    return switch runtime.publicContractProgress.phase {
    case .completed: "checkmark.circle.fill"
    case .partial, .throttled: "exclamationmark.triangle.fill"
    case .failed: "xmark.octagon.fill"
    default: "pause.circle"
    }
  }

  private var statusColor: Color {
    switch runtime.publicContractStoreState {
    case .preparing, .disabled: return DesignTokens.textSecondary
    case .failed: return DesignTokens.negative
    case .ready: break
    }
    if runtime.publicContractProgress.failedRegions > 0,
      runtime.publicContractProgress.phase == .idle
    {
      return DesignTokens.caution
    }
    return switch runtime.publicContractProgress.phase {
    case .completed: DesignTokens.positive
    case .partial, .throttled: DesignTokens.caution
    case .failed: DesignTokens.negative
    default: DesignTokens.textSecondary
    }
  }

  private var regionFailureDescription: String {
    let count = runtime.publicContractProgress.failedRegions
    if runtime.publicContractProgress.regionErrorMessage
      == "esi.public-contracts.schema-mismatch"
    {
      return AppLocalization.format(
        "%lld regions could not be decoded. Existing data was preserved and the importer paused before repeating the error across every region.",
        Int64(count)
      )
    }
    return AppLocalization.format(
      "%lld regions are temporarily unavailable. Existing regional data was preserved.",
      Int64(count)
    )
  }

  private func statusMetric(_ title: LocalizedStringKey, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value)
        .font(.headline.monospacedDigit())
    }
  }

  private func hierarchy(_ result: PublicContractSearchResult) -> String {
    [result.categoryName, result.groupName]
      .compactMap { $0 }
      .joined(separator: " › ")
  }

  private func metadataLine(_ result: PublicContractSearchResult) -> String {
    [
      result.regionName,
      location(result),
      hierarchy(result),
      contractType(result.contractType),
      "\("Expires".localizedUI) \(result.dateExpired.formatted(date: .abbreviated, time: .shortened))",
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "  ›  ")
  }

  private func location(_ result: PublicContractSearchResult) -> String {
    let start = locationName(
      id: result.startLocationID,
      name: result.startLocationName
    )
    guard let endLocationID = result.endLocationID,
      endLocationID != result.startLocationID
    else { return start }
    let end = locationName(id: endLocationID, name: result.endLocationName)
    return "\(start) → \(end)"
  }

  private func locationName(id: Int64?, name: String?) -> String {
    if let name, !name.isEmpty { return name }
    guard let id else { return "Location unavailable".localizedUI }
    if id >= 1_000_000_000_000 {
      return "Player structure name unavailable".localizedUI
    }
    return "Location name unavailable".localizedUI
  }

  private func contractType(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func formatQuantity(_ value: Int) -> String {
    value.formatted(.number.grouping(.automatic))
  }

  private func formatPrice(_ value: Double?) -> String {
    guard let value else { return "Price unavailable" }
    return value.formatted(
      .currency(code: "ISK")
        .precision(.fractionLength(0...2))
    )
  }
}

private struct DisclosurePanel<Content: View>: View {
  let title: LocalizedStringKey
  @Binding var isExpanded: Bool
  @ViewBuilder let content: Content

  var body: some View {
    FullWidthDisclosure(isExpanded: $isExpanded) {
      Text(title)
        .textCase(.uppercase)
        .font(.caption.weight(.semibold))
        .tracking(1.1)
        .foregroundStyle(DesignTokens.textSecondary)
    } content: {
      content
        .padding(.top, DesignTokens.spacingMD)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }
}

private struct SearchIdentity: Hashable {
  let query: String
  let categoryID: Int64?
  let groupID: Int64?
  let direction: PublicContractItemDirection
}

private struct SearchTaskIdentity: Hashable {
  let request: SearchIdentity
  let explicitSearchSequence: Int
}

enum PublicContractSearchPolicy {
  static let typingPause: Duration = .milliseconds(700)

  static func delay(isExplicitSubmission: Bool) -> Duration? {
    isExplicitSubmission ? nil : typingPause
  }
}

/// Market Settings panel choosing the regions of the Public Contracts import:
/// the entire universe or an explicit selection. Configured hub roles,
/// production sites and the built-in trade hubs are marked and listed first.
struct PublicContractRegionSettingsPanel: View {
  @EnvironmentObject private var runtime: RuntimeState

  @State private var didLoad = false
  @State private var isLoading = false
  @State private var isApplying = false
  @State private var draftUsesUniverse = true
  @State private var draftSelection: Set<Int64> = []
  @State private var filterText = ""
  @State private var statusMessage: String?
  /// Regions of hub solar systems without a stored region (player
  /// structures), resolved through the cached ESI system lookup.
  @State private var systemRegions: [Int64: Int64] = [:]

  var body: some View {
    Panel(title: "Contract Regions") {
      Text(
        "Choose which regions the Public Contracts import fetches. Main, Home and Coalition Hub opportunities, the Planner Contract Sale and the contract search compare only offers from these regions."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      if runtime.publicContractStoreState != .ready {
        Label(
          "The local Public Contracts index is not ready. The region selection can be changed once it is available.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(DesignTokens.caution)
      } else {
        Picker("Import scope", selection: universeBinding) {
          Text("Entire universe").tag(true)
          Text("Selected regions").tag(false)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("market-settings.contract-regions.scope")

        if draftUsesUniverse {
          Text(
            "Every EVE region is imported and compared. The first complete import takes considerably longer than a regional selection."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        } else {
          regionSelection
        }

        HStack {
          Button("Apply Region Selection") { apply() }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
            .accessibilityIdentifier("market-settings.contract-regions.apply")
          if isApplying || isLoading {
            ProgressView().controlSize(.small)
          }
          if hasChanges {
            Label("Not applied yet", systemImage: "exclamationmark.triangle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(DesignTokens.caution)
          }
        }
        if !draftUsesUniverse, draftSelection.isEmpty {
          Text("Select at least one region or import the entire universe.")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
        if runtime.isSynchronizingPublicContracts {
          Text(
            "A running contract import finishes with its previous region list; the new selection applies from the next run."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        if let error = runtime.publicContractRegionError {
          Text(LocalizedStringKey(error))
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
      }
    }
    .task(id: runtime.publicContractStoreState == .ready) {
      await load()
    }
    .task(
      id: PublicContractRegionCatalog.unresolvedSolarSystemIDs(
        basis: runtime.productionBasis
      )
    ) {
      await resolveSystemRegions()
    }
  }

  @ViewBuilder
  private var regionSelection: some View {
    let options = PublicContractRegionCatalog.options(
      regions: runtime.publicContractKnownRegions,
      basis: runtime.productionBasis,
      systemRegions: systemRegions
    )
    let filtered = filteredOptions(options)
    HStack {
      TextField("Filter regions", text: $filterText)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 260)
      Button("Select hub and production regions") {
        draftSelection.formUnion(
          PublicContractRegionCatalog.suggestedRegionIDs(
            basis: runtime.productionBasis,
            systemRegions: systemRegions
          )
        )
      }
      Button("Clear selection") { draftSelection.removeAll() }
        .disabled(draftSelection.isEmpty)
      Spacer()
      Text("\(draftSelection.count) of \(options.count) regions selected")
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
    }
    if options.isEmpty {
      Text(
        isLoading
          ? "Loading the EVE region list…"
          : "The EVE region list is not available yet."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          let recommended = filtered.filter(\.isRecommended)
          let others = filtered.filter { !$0.isRecommended }
          if !recommended.isEmpty {
            Text("Recommended regions")
              .font(.headline)
            ForEach(recommended) { regionRow($0) }
          }
          if !others.isEmpty {
            Text("All other regions")
              .font(.headline)
              .padding(.top, recommended.isEmpty ? 0 : DesignTokens.spacingSM)
            ForEach(others) { regionRow($0) }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.spacingXS)
      }
      .frame(minHeight: 180, maxHeight: 360)
    }
  }

  private func regionRow(_ option: PublicContractRegionOption) -> some View {
    HStack(spacing: DesignTokens.spacingSM) {
      Toggle(isOn: selectionBinding(option.id)) {
        Text(verbatim: option.name)
      }
      .toggleStyle(.checkbox)
      .labelsHidden()
      .accessibilityLabel(Text(verbatim: option.name))
      EVEEntityText(value: option.name, font: .body)
      if let hint = Self.hint(for: option) {
        Text(verbatim: "(\(hint))")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .accessibilityIdentifier("market-settings.contract-regions.\(option.id)")
  }

  /// Localized role hints shown behind a region name, e.g.
  /// "Main Hub · Trade hub Jita".
  static func hint(for option: PublicContractRegionOption) -> String? {
    let labels = option.roles.map { role -> String in
      switch role {
      case .mainHub: AppLocalization.text("Main Hub")
      case .homeHub: AppLocalization.text("Home Hub")
      case .coalitionHub: AppLocalization.text("Coalition Hub")
      case .comparisonMarket: AppLocalization.text("Comparison market")
      case .productionSite: AppLocalization.text("Production site")
      case .tradeHub:
        AppLocalization.format(
          "Trade hub %@",
          option.tradeHubs.map { $0.rawValue.capitalized }
            .joined(separator: ", ")
        )
      }
    }
    return labels.isEmpty ? nil : labels.joined(separator: " · ")
  }

  private func filteredOptions(
    _ options: [PublicContractRegionOption]
  ) -> [PublicContractRegionOption] {
    let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return options }
    return options.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || (Self.hint(for: $0)?.localizedCaseInsensitiveContains(query)
          ?? false)
    }
  }

  private var draftScope: Set<Int64>? {
    draftUsesUniverse ? nil : draftSelection
  }

  private var hasChanges: Bool {
    draftScope != runtime.publicContractRegionScope
  }

  private var canApply: Bool {
    hasChanges && !isApplying
      && (draftUsesUniverse || !draftSelection.isEmpty)
  }

  private var universeBinding: Binding<Bool> {
    Binding {
      draftUsesUniverse
    } set: { usesUniverse in
      draftUsesUniverse = usesUniverse
      if !usesUniverse, draftSelection.isEmpty {
        draftSelection = PublicContractRegionCatalog.suggestedRegionIDs(
          basis: runtime.productionBasis,
          systemRegions: systemRegions
        )
      }
    }
  }

  private func selectionBinding(_ regionID: Int64) -> Binding<Bool> {
    Binding {
      draftSelection.contains(regionID)
    } set: { isSelected in
      if isSelected {
        draftSelection.insert(regionID)
      } else {
        draftSelection.remove(regionID)
      }
    }
  }

  private func resolveSystemRegions() async {
    let systemIDs = PublicContractRegionCatalog.unresolvedSolarSystemIDs(
      basis: runtime.productionBasis
    )
    for systemID in systemIDs.sorted() where systemRegions[systemID] == nil {
      guard
        let details = try? await runtime.resolveSolarSystem(systemID),
        !Task.isCancelled
      else { continue }
      systemRegions[systemID] = details.regionID
    }
  }

  private func load() async {
    guard runtime.publicContractStoreState == .ready else { return }
    isLoading = true
    await runtime.loadPublicContractRegions()
    isLoading = false
    guard !didLoad else { return }
    didLoad = true
    draftUsesUniverse = runtime.publicContractRegionScope == nil
    draftSelection = runtime.publicContractRegionScope ?? []
  }

  private func apply() {
    let scope = draftScope
    isApplying = true
    statusMessage = nil
    Task {
      await runtime.applyPublicContractRegionScope(scope)
      isApplying = false
      if runtime.publicContractRegionError == nil {
        statusMessage = AppLocalization.text(
          scope == nil
            ? "Contract import now covers the entire universe. Regions without a complete import are fetched with the next automatic update."
            : "Region selection saved. Newly selected regions are fetched with the next automatic update."
        )
      }
    }
  }
}
