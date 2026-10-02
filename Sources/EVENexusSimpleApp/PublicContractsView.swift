import EVENexusCore
import SwiftUI

struct PublicContractsView: View {
  @EnvironmentObject private var runtime: RuntimeState

  @State private var itemQuery = ""
  @State private var selectedCategoryID: Int64?
  @State private var selectedGroupID: Int64?
  @State private var direction: PublicContractItemDirection = .included
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
      if isInitialImport {
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
    .task(id: searchIdentity) {
      do {
        try await Task.sleep(for: .milliseconds(250))
      } catch {
        return
      }
      await search()
    }
    .task(id: runtime.publicContractProgress.indexedItems / 250) {
      guard runtime.isSynchronizingPublicContracts else { return }
      await runtime.refreshPublicContractFacets()
      await search()
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
      if runtime.isSynchronizingPublicContracts {
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
        "Important: The first import of all contracts that are still active at that time can take two to three days. It continues in the background while the app is running and resumes after the next app launch. During this time, the app is significantly slower and can only be used to a limited extent. Import performance will continue to be optimized."
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
      }
    }
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
        EVEEntityText(value: result.typeName ?? "Unknown item".localizedUI)
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

  private func search() async {
    await runtime.searchPublicContracts(
      PublicContractSearchFilter(
        itemQuery: itemQuery,
        groupID: selectedGroupID,
        categoryID: selectedCategoryID,
        direction: direction
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
