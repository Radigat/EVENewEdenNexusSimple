import EVENexusCore
import SwiftData
import SwiftUI

/// Doctrine stock (DOKTRIN_BEDARF_PLAN.md): which doctrine items the Home
/// Hub needs, how fast they sell and whether building or importing them
/// from the Main Hub is cheaper.
struct DoctrineStockView: View {
  var onOpenMarketSettings: () -> Void = {}
  var onOpenLogistics: () -> Void = {}

  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]

  // The build cost follows the Hub opportunity settings, like the stock
  // sale comparison, so these keys are shared with that view.
  @AppStorage("market-opportunities.cost.blueprint.enabled", store: AppDefaults.store)
  private var costIncludesBlueprint = false
  @AppStorage("market-opportunities.cost.builds-intermediates", store: AppDefaults.store)
  private var buildsIntermediates = true
  @AppStorage("market-opportunities.cost.blueprint-per-run", store: AppDefaults.store)
  private var blueprintCostPerRunText = ""
  @AppStorage("market-opportunities.cost.blueprint.own-rights", store: AppDefaults.store)
  private var usesOwnBlueprintRights = false
  @AppStorage("doctrine-stock.kind", store: AppDefaults.store)
  private var kindFilterRawValue = DoctrineKindFilter.all.rawValue
  /// Doctrine ID of the table filter; empty shows every doctrine.
  @AppStorage("doctrine-stock.doctrine", store: AppDefaults.store)
  private var doctrineFilterID = ""

  @State private var library: DoctrineLibrary?
  @State private var allumis: AllumisDoctrineSnapshot?
  /// Wiki library joined with Allumis; rebuilt whenever one of them changes.
  @State private var sources: DoctrineAllumisMerge?
  @State private var hasLoadedStoredData = false
  @State private var persistenceError: String?
  @State private var loginSheet: DoctrineLoginSource?
  @State private var hasStoredSession: Bool?
  /// Whether the Allumis store holds an unexpired cookie.
  @State private var hasAllumisSession: Bool?
  /// `DoctrineAllumisSession.signInConfirmed` at the last refresh.
  @State private var allumisSignInConfirmed: Bool?
  @State private var confirmsSignOut = false
  @State private var confirmsAllumisSignOut = false
  @State private var sort = AppTableSortDescriptor(
    column: DoctrineStockSortColumn.shortfall,
    direction: .descending
  )
  @State private var doctrineSort = AppTableSortDescriptor(
    column: DoctrineListSortColumn.title,
    direction: .ascending
  )
  @State private var scanRowsByType: [Int64: ManufacturingOpportunityRow] = [:]
  @State private var scanRowsAnalysisID: UUID?
  @State private var loyaltyStoreBlueprintOffers: [Int64: [LoyaltyStoreBlueprintOffer]] = [:]
  @State private var metadata: DoctrineItemCatalogMetadata?
  @State private var displayRows: [DoctrineStockDisplayRow] = []
  /// Counts the row computations; part of each row's identity for redraws.
  @State private var rowsRevision = 0
  /// Doctrine list with its texts, rebuilt with the sources or the language.
  @State private var doctrineRows: [DoctrineListRowModel] = []
  /// Resolved SDE types of the merged library, rebuilt with the sources.
  @State private var libraryTypeIDs: Set<Int64> = []
  /// App language locale, read once instead of for every number; follows
  /// the environment locale, which changes with the app language.
  @State private var locale: Locale = AppLocalization.currentLanguage.locale
  @Environment(\.locale) private var environmentLocale
  @State private var availableTableWidth: CGFloat = 0
  /// Visible height of the page's scroll view, for the table's row area.
  @State private var pageViewportHeight: CGFloat = 0

  private let consumer = "doctrine-stock"
  private let nameMinimumWidth = DoctrineStockTableLayout.nameMinimumWidth
  private let numberWidth = DoctrineStockTableLayout.numberWidth
  private let recommendationWidth = DoctrineStockTableLayout.recommendationWidth
  private let doctrineColumnWidth = DoctrineStockTableLayout.doctrineColumnWidth
  private let allumisColumnWidth: CGFloat = 170
  /// Fits, target, in stock, shortfall, three sales rates, losses, reach,
  /// build, import, Home sell, Home ÷ Main and profit.
  private let numberColumnCount = 14

  private var importController: DoctrineWikiImportController { .shared }
  private var importStatus: DoctrineImportStatus { importController.status }
  private var allumisController: DoctrineAllumisImportController { .shared }
  private var allumisStatus: DoctrineImportStatus { allumisController.status }

  private var kindFilter: DoctrineKindFilter {
    DoctrineKindFilter(rawValue: kindFilterRawValue) ?? .all
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        header
        wikiPanel
        allumisPanel
        doctrinePanel
        hubPanel
        tablePanel
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
      pageViewportHeight = $0
    }
    .navigationTitle(AppLocalization.text("Doctrine stock"))
    .task {
      loadStoredData()
      await refreshSessionState()
      await runtime.loadManufacturingOpportunityAnalysis()
      await runtime.loadSecondaryHubOpportunityData(role: .home)
    }
    .task(id: transportKey) {
      await runtime.refreshTradeTransportBasis(for: TradeMode.mainToHome.route)
    }
    .task(id: stockKey) {
      await runtime.refreshMarketStockOverviews(for: [.home], consumer: consumer)
    }
    .onDisappear { runtime.releaseMarketStockOverviews(consumer: consumer) }
    .task(id: volumeHistoryKey) {
      guard let regionID = volumeHistoryKey.regionID, !volumeHistoryKey.typeIDs.isEmpty
      else { return }
      await runtime.refreshTradeVolumeHistory(
        typeIDs: volumeHistoryKey.typeIDs,
        regionID: regionID
      )
    }
    .task(id: libraryTypeIDs) {
      metadata = await runtime.doctrineItemCatalogMetadata(typeIDs: libraryTypeIDs)
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
    .task(id: rowsKey) {
      // Data of the page arrives in bursts while it opens; a short pause
      // lets a burst end before the whole table is computed again.
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      rowsRevision += 1
      displayRows = computeRows(revision: rowsRevision)
    }
    .onChange(of: environmentLocale) {
      locale = AppLocalization.currentLanguage.locale
      rebuildDoctrineRows()
    }
    .sheet(item: $loginSheet) { source in
      switch source {
      case .wiki:
        DoctrineWikiLoginSheet { loginSheet = nil }
          .marketStockHistoryHost()
      case .allumis:
        DoctrineAllumisLoginSheet { loginSheet = nil }
          .marketStockHistoryHost()
      }
    }
    .onChange(of: loginSheet) { _, shown in
      if shown == nil { Task { await refreshSessionState() } }
    }
    .confirmationDialog("Sign out of the alliance wiki?", isPresented: $confirmsSignOut) {
      Button("Sign out", role: .destructive) {
        Task {
          await DoctrineWikiSession.shared.signOut()
          await refreshSessionState()
        }
      }
    } message: {
      Text("The wiki session stored in the app is removed. The imported doctrines stay.")
    }
    .confirmationDialog("Sign out of Allumis?", isPresented: $confirmsAllumisSignOut) {
      Button("Sign out", role: .destructive) {
        Task {
          await DoctrineAllumisSession.shared.signOut()
          await refreshSessionState()
        }
      }
    } message: {
      Text("The Allumis session stored in the app is removed. The imported Allumis data stays.")
    }
    .onChange(of: importController.finishedRuns) {
      // The import runs on when the page is left; a page shown again
      // loads the saved result, this one takes it over directly.
      if let importedLibrary = importController.importedLibrary {
        library = importedLibrary
        rebuildSources()
      }
      Task { await refreshSessionState() }
    }
    .onChange(of: allumisController.finishedRuns) {
      if let importedSnapshot = allumisController.importedSnapshot {
        allumis = importedSnapshot
        rebuildSources()
      }
      Task { await refreshSessionState() }
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Doctrine stock")
        .appFont(.largeTitle.bold())
        .foregroundStyle(DesignTokens.textPrimary)
        .nexusPageTitle()
      Text(
        "Doctrine items for the Home Hub: the Allumis target, what is listed, what is still missing, how fast it sells, and whether building or importing from the Main Hub is cheaper."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  // MARK: Wiki

  private var wikiPanel: some View {
    Panel(title: "Alliance wiki") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          sessionChip
          Spacer()
          Button {
            loginSheet = .wiki
          } label: {
            Label("Sign in to wiki…", systemImage: "person.badge.key")
          }
          .accessibilityIdentifier("doctrine-stock.sign-in")
          Button {
            startImport()
          } label: {
            if importStatus.isRunning {
              ProgressView().controlSize(.small)
            } else {
              Label("Update from wiki", systemImage: "arrow.down.doc")
            }
          }
          .disabled(importStatus.isRunning)
          .help(
            AppLocalization.text(
              "Reads every doctrine and ship page of the wiki with your session (about 150 pages, with short pauses) and saves the result."
            )
          )
          .accessibilityIdentifier("doctrine-stock.import")
          if importStatus.isRunning {
            Button("Cancel") { importController.cancel() }
          }
          Button("Sign out", role: .destructive) { confirmsSignOut = true }
            .disabled(hasStoredSession != true || importStatus.isRunning)
            .accessibilityIdentifier("doctrine-stock.sign-out")
        }
        Text(
          AppLocalization.format(
            "Source: %@ (doctrine pages and their ship pages). The import only runs on request.",
            DoctrineWikiSession.shared.configuration.baseURL.absoluteString
          )
        )
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        importStatusView
        if let persistenceError {
          Label(persistenceError, systemImage: "externaldrive.badge.exclamationmark")
            .foregroundStyle(DesignTokens.negative)
        }
        if let library {
          Text(
            AppLocalization.format(
              "Imported %@ · %lld doctrines · %lld fits",
              library.importedAt.formatted(
                .dateTime.day().month().year().hour().minute().locale(locale)
              ),
              Int64(library.doctrines.count),
              Int64(library.fits.count)
            )
          )
          .appFont(.callout)
          if !library.issues.isEmpty {
            DisclosureGroup(
              AppLocalization.format("Import notes (%lld)", Int64(library.issues.count))
            ) {
              VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(library.issues.enumerated()), id: \.offset) { _, issue in
                  Text(verbatim: issueText(issue))
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .textSelection(.enabled)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appFont(.callout)
            .accessibilityIdentifier("doctrine-stock.issues")
          }
        }
      }
    }
  }

  private var sessionChip: some View {
    let (text, tint): (String, Color) =
      switch hasStoredSession {
      case true?: (AppLocalization.text("Wiki session active"), DesignTokens.positive)
      case false?: (AppLocalization.text("Not signed in to the wiki"), DesignTokens.caution)
      case nil: (AppLocalization.text("Checking wiki session…"), DesignTokens.textSecondary)
      }
    return Label(text, systemImage: hasStoredSession == true ? "person.fill.checkmark" : "person.fill.questionmark")
      .appFont(.caption)
      .foregroundStyle(tint)
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .background(tint.opacity(0.12), in: Capsule())
      .help(
        AppLocalization.text(
          "The wiki session lasts until the app quits; after a restart, sign in again. It can expire earlier; the next import tells."
        )
      )
  }

  @ViewBuilder
  private var importStatusView: some View {
    switch importStatus {
    case .idle:
      EmptyView()
    case .running(let progress):
      if let progress, progress.total > 0 {
        ProgressView(
          value: Double(progress.completed),
          total: Double(progress.total)
        ) {
          Text(
            AppLocalization.format(
              "Reading wiki pages: %lld of %lld",
              Int64(progress.completed),
              Int64(progress.total)
            )
          )
          .appFont(.caption)
        }
      } else {
        Text("Reading the doctrine index…").appFont(.caption)
      }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.negative)
    case .succeeded:
      Label("Doctrines updated from the wiki.", systemImage: "checkmark.circle.fill")
        .foregroundStyle(DesignTokens.positive)
    }
  }

  // MARK: Allumis

  private var allumisPanel: some View {
    Panel(title: "Allumis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          allumisSessionChip
          Spacer()
          Button {
            loginSheet = .allumis
          } label: {
            Label("Sign in to Allumis…", systemImage: "person.badge.key")
          }
          .accessibilityIdentifier("doctrine-stock.allumis.sign-in")
          Button {
            startAllumisImport()
          } label: {
            if allumisStatus.isRunning {
              ProgressView().controlSize(.small)
            } else {
              Label("Update from Allumis", systemImage: "arrow.down.doc")
            }
          }
          .disabled(allumisStatus.isRunning)
          .help(
            AppLocalization.text(
              "Reads the doctrine table of Allumis with your session (one request) and saves the result."
            )
          )
          .accessibilityIdentifier("doctrine-stock.allumis.import")
          if allumisStatus.isRunning {
            Button("Cancel") { allumisController.cancel() }
          }
          Button("Sign out", role: .destructive) { confirmsAllumisSignOut = true }
            .disabled(hasAllumisSession != true || allumisStatus.isRunning)
            .accessibilityIdentifier("doctrine-stock.allumis.sign-out")
        }
        Text(
          AppLocalization.format(
            "Source: %@ (Brave Doctrine Market Management): the supply officer's target per fit for the staging market, sales over 7 days and losses over 10 days. The import only runs on request.",
            DoctrineAllumisSession.shared.configuration.baseURL.absoluteString
          )
        )
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        allumisStatusView
        if let allumis {
          Text(
            AppLocalization.format(
              "Imported %@ · %lld fits · %lld paired with a wiki fit · %lld only at Allumis",
              allumis.importedAt.formatted(
                .dateTime.day().month().year().hour().minute().locale(locale)
              ),
              Int64(allumis.fits.count),
              Int64(sources?.matchedWikiFitCount ?? 0),
              Int64(sources?.onlyAtAllumisFitCount ?? 0)
            )
          )
          .appFont(.callout)
          let notes = allumisNotes
          if !notes.isEmpty {
            DisclosureGroup(
              AppLocalization.format("Allumis notes (%lld)", Int64(notes.count))
            ) {
              VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                  Text(verbatim: note)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .textSelection(.enabled)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appFont(.callout)
            .accessibilityIdentifier("doctrine-stock.allumis.issues")
          }
        }
      }
    }
  }

  private var allumisSessionChip: some View {
    // A stored cookie alone is no sign-in: Allumis also sets one for
    // visitors, so “active” needs a confirmation in this app run.
    let (text, tint, isActive): (String, Color, Bool) =
      switch (hasAllumisSession, allumisSignInConfirmed) {
      case (nil, _):
        (AppLocalization.text("Checking Allumis session…"), DesignTokens.textSecondary, false)
      case (false?, _), (true?, false?):
        (AppLocalization.text("Not signed in to Allumis"), DesignTokens.caution, false)
      case (true?, true?):
        (AppLocalization.text("Allumis session active"), DesignTokens.positive, true)
      case (true?, nil):
        (AppLocalization.text("Allumis session stored, not checked"), DesignTokens.textSecondary, false)
      }
    return Label(
      text,
      systemImage: isActive ? "person.fill.checkmark" : "person.fill.questionmark"
    )
    .appFont(.caption)
    .foregroundStyle(tint)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(tint.opacity(0.12), in: Capsule())
    .help(
      AppLocalization.text(
        "Allumis ends its session after 12 hours, also across app restarts; then sign in again. The next import tells whether the session is still valid."
      )
    )
  }

  @ViewBuilder
  private var allumisStatusView: some View {
    switch allumisStatus {
    case .idle:
      EmptyView()
    case .running:
      Text("Reading the Allumis doctrine table…").appFont(.caption)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.negative)
    case .succeeded:
      Label("Targets updated from Allumis.", systemImage: "checkmark.circle.fill")
        .foregroundStyle(DesignTokens.positive)
    }
  }

  /// Import issues of Allumis and wiki fits paired despite other content.
  private var allumisNotes: [String] {
    guard let allumis else { return [] }
    var notes = allumis.issues.map(allumisIssueText)
    if let sources {
      let names = sources.library.fits
        .filter { sources.contentDiffersFitIDs.contains($0.id) }
        .map { "\($0.hull.name) · \($0.fitName)" }
        .sorted()
      notes += names.map {
        AppLocalization.format(
          "%@: paired by hull and name; the items differ from the wiki fit.",
          $0
        )
      }
    }
    return notes
  }

  private func allumisIssueText(_ issue: AllumisImportIssue) -> String {
    switch issue.kind {
    case .unknownItemName:
      return AppLocalization.format("%@: item “%@” is not in the SDE.", issue.fitName, issue.detail)
    case .ambiguousItemName:
      return AppLocalization.format(
        "%@: item “%@” matches several SDE types.", issue.fitName, issue.detail)
    case .invalidEntry:
      return AppLocalization.format(
        "%@: entry “%@” could not be read and is left out.", issue.fitName, issue.detail)
    }
  }

  // MARK: Doctrines and targets

  @ViewBuilder
  private var doctrinePanel: some View {
    Panel(title: "Doctrines and targets") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        if allumis != nil {
          Text(
            "Target per fit = complete fits the supply officer wants at the Home Hub, according to Allumis; most frequent value first. The item table splits it onto the items: target × quantity in the fit, summed over every fit. Fits that Allumis does not know add no target; Allumis fits without a wiki fit form the group “Only at Allumis”."
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        } else {
          Label(
            "The target comes from Allumis. Without an Allumis import there is no target and no shortfall.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .appFont(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        if !doctrineRows.isEmpty {
          let rows = sortedDoctrineRows(doctrineRows)
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.spacingXS) {
              SortableTableHeader(
                title: "Doctrine",
                column: DoctrineListSortColumn.title,
                sort: $doctrineSort
              )
              .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
              SortableTableHeader(
                title: "Fits",
                column: DoctrineListSortColumn.fitCount,
                sort: $doctrineSort,
                defaultDirection: .descending,
                alignment: .trailing
              )
              .frame(width: 70, alignment: .trailing)
              if allumis != nil {
                SortableTableHeader(
                  title: "Target per fit",
                  column: DoctrineListSortColumn.allumis,
                  sort: $doctrineSort,
                  defaultDirection: .descending,
                  alignment: .trailing
                )
                .frame(width: allumisColumnWidth, alignment: .trailing)
              }
            }
            .appFont(.caption.weight(.semibold))
            .padding(.vertical, DesignTokens.spacingXS)
            Divider()
            ForEach(rows) { model in
              DoctrineListRowView(
                model: model,
                allumisColumnWidth: allumisColumnWidth
              )
              .equatable()
              Divider().opacity(0.4)
            }
          }
          .frame(maxWidth: allumis == nil ? 430 : 430 + allumisColumnWidth, alignment: .leading)
        } else {
          Text("No doctrines imported yet. Use “Update from wiki” or “Update from Allumis”.")
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  private func doctrineTitle(_ doctrine: DoctrineRecord) -> String {
    doctrine.id == DoctrineAllumisMerge.onlyAtAllumisDoctrineID
      ? AppLocalization.text("Only at Allumis") : doctrine.title
  }

  private func sortedDoctrineRows(_ rows: [DoctrineListRowModel]) -> [DoctrineListRowModel] {
    let ascending = doctrineSort.direction == .ascending
    return rows.sorted { lhs, rhs in
      switch doctrineSort.column {
      case .title:
        let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if order != .orderedSame {
          return ascending ? order == .orderedAscending : order == .orderedDescending
        }
      case .allumis:
        // Unknown after known values ascending, before them descending.
        switch (lhs.allumis?.mostFrequentTarget, rhs.allumis?.mostFrequentTarget) {
        case (let left?, let right?):
          if left != right { return ascending ? left < right : left > right }
        case (.some, nil):
          return ascending
        case (nil, .some):
          return !ascending
        case (nil, nil):
          break
        }
      case .fitCount:
        if lhs.fitCount != rhs.fitCount {
          return ascending ? lhs.fitCount < rhs.fitCount : lhs.fitCount > rhs.fitCount
        }
      }
      return lhs.id < rhs.id
    }
  }

  // MARK: Hub and basis

  private var hubPanel: some View {
    Panel(title: "Home Hub and basis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          locationChip(role: .home)
          Image(systemName: "arrow.left")
            .foregroundStyle(DesignTokens.textSecondary)
          locationChip(role: .main)
          feeChip
          Spacer()
          refreshButton
        }
        ForEach(hubMessages, id: \.self) { message in
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(DesignTokens.caution)
        }
        if !hubMessages.isEmpty || !transportMessages.isEmpty {
          HStack(spacing: DesignTokens.spacingSM) {
            Button("Open Market Settings", action: onOpenMarketSettings)
            if !transportMessages.isEmpty {
              Button("Open logistics settings", action: onOpenLogistics)
            }
          }
        }
        ForEach(transportMessages, id: \.self) { message in
          Label(message, systemImage: "shippingbox")
            .foregroundStyle(DesignTokens.caution)
        }
        DoctrineHistoryProgressLine()
        VStack(alignment: .leading, spacing: 2) {
          Text(
            "Build/unit: the Hub opportunity calculation of the Home Hub for the shortfall (at least one run) with its ME/TE defaults; materials bought at the Main Hub, including installation, Blueprint share and logistics to the Home Hub."
          )
          Text(
            "Import/unit: lowest sell order at the Main Hub plus transport per unit on the leg Main → Home, as in Trade."
          )
          Text(
            "Sold/day: Ø of 30 days of the ESI market history of the Home Hub's region (both order sides) and of the partial fills in the Home Hub stock history (a lower bound). Reach = listed ÷ region/day."
          )
          Text(
            "Profit/unit: own sell order one price step below the best Home Hub sell, after sales tax and broker fee, minus the cost of the recommended way. Order modification and relist fees are not included."
          )
          Text(verbatim: assumptionText)
        }
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  @ViewBuilder
  private func locationChip(role: OpportunityHubRole) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Text(verbatim: TradeHubText.roleName(role) + ":")
        .appFont(.caption)
      if let location = runtime.tradeLocation(for: role) {
        EVEEntityText(value: location.name, font: .caption, lineLimit: 1)
      } else {
        Text("Not configured").appFont(.caption)
      }
    }
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(DesignTokens.accent.opacity(0.15), in: Capsule())
    .overlay(Capsule().stroke(DesignTokens.accent.opacity(0.6)))
  }

  private var feeChip: some View {
    let fees = runtime.tradeHubFees(for: .home)
    return Text(
      verbatim: AppLocalization.format(
        "Sales tax %@ · Broker fee %@",
        formatPercent(fees.salesTaxRate),
        formatPercent(fees.brokerFeeRate)
      )
    )
    .appFont(.caption)
    .padding(.horizontal, DesignTokens.spacingSM)
    .padding(.vertical, DesignTokens.spacingXS)
    .background(DesignTokens.textSecondary.opacity(0.12), in: Capsule())
  }

  private var isScanningHubs: Bool {
    runtime.isAnalyzingManufacturingOpportunities
      || runtime.opportunityState(for: .home).isAnalyzing
      || runtime.opportunityState(for: .coalition).isAnalyzing
  }

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
    .disabled(isScanningHubs || runtime.isHubScanBlockedByESICache)
    .help(
      runtime.hubScanBlockedText
        ?? AppLocalization.text(
          "Runs the Main, Home and Coalition Hub scan that also updates the Hub opportunities.")
    )
    .accessibilityIdentifier("doctrine-stock.refresh-hub-markets")
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

  private var hubMessages: [String] {
    let home = TradeHubText.roleName(.home)
    switch runtime.opportunityScanTarget(for: .home) {
    case .notConfigured:
      return [AppLocalization.format("No %@ is configured. Select it in Market Settings.", home)]
    case .unresolved:
      return [
        AppLocalization.format(
          "The %@ has no exact station or structure identifier. Select it again in Market Settings.",
          home
        )
      ]
    default:
      break
    }
    var messages: [String] = []
    if runtime.tradeLocation(for: .main) == nil {
      messages.append(
        AppLocalization.format(
          "No %@ is configured. Select it in Market Settings.",
          TradeHubText.roleName(.main)
        )
      )
    }
    if analysis == nil {
      messages.append(
        AppLocalization.format(
          "No Hub opportunity scan for the %@ yet, so new production costs are unavailable. Use “Refresh hub markets”.",
          home
        )
      )
    }
    for role in [OpportunityHubRole.home, .main] {
      if let state = runtime.tradeMarketState(for: role), state.value != nil {
        if state.state != .fresh {
          messages.append(
            AppLocalization.format(
              "Market data of the %@: %@.",
              TradeHubText.roleName(role),
              StartupDataStatusSection.freshnessText(state.state)
            )
          )
        }
      } else if runtime.tradeLocation(for: role) != nil {
        messages.append(
          AppLocalization.format(
            "No market data for the %@ in this session yet. Use “Refresh hub markets” or wait for the automatic Hub scan.",
            TradeHubText.roleName(role)
          )
        )
      }
    }
    if runtime.tradeRegionID(for: .home) == nil, runtime.tradeLocation(for: .home) != nil {
      messages.append(
        AppLocalization.text(
          "The region of the Home Hub is unknown, so the regional sales history is unavailable. Select the Home Hub again in Market Settings."
        )
      )
    }
    if runtime.marketStockOverview(for: .home) == nil, runtime.tradeLocation(for: .home) != nil {
      messages.append(
        AppLocalization.text(
          "No stock history of the Home Hub yet, so listed stock and hub sales stay unknown."
        )
      )
    }
    return messages
  }

  private var transportMessages: [String] {
    guard !homeIsMainHub else { return [] }
    let basis = runtime.tradeTransportBases[TradeMode.mainToHome.route] ?? .none
    var messages: [String] = []
    for leg in basis.legs {
      if case .unavailable(let code) = leg {
        messages.append(TradeHubText.transportText(code))
      }
    }
    return Array(Set(messages)).sorted()
  }

  // MARK: Table

  @ViewBuilder
  private var tablePanel: some View {
    let rows = filteredRows
    Panel(title: "Doctrine items at the Home Hub") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack(spacing: DesignTokens.spacingSM) {
          Picker("Kind", selection: $kindFilterRawValue) {
            ForEach(DoctrineKindFilter.allCases, id: \.self) { filter in
              Text(filter.title).tag(filter.rawValue)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          .accessibilityIdentifier("doctrine-stock.kind")
          if !doctrineRows.isEmpty {
            Picker("Doctrine", selection: doctrineFilterBinding) {
              Text("All doctrines").tag("")
              Divider()
              ForEach(
                doctrineRows.sorted {
                  $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
              ) { doctrine in
                Text(verbatim: doctrine.title).tag(doctrine.id)
              }
            }
            .fixedSize()
            .help(AppLocalization.text("Shows only the items of one doctrine, for example to buy for it."))
            .accessibilityIdentifier("doctrine-stock.doctrine-filter")
          }
          Spacer()
          Text(verbatim: summaryText(rows))
            .appFont(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        if sources == nil {
          Text("No doctrines imported yet. Use “Update from wiki” or “Update from Allumis”.")
            .foregroundStyle(DesignTokens.textSecondary)
        } else if rows.isEmpty {
          Text("No doctrine item of this kind.")
            .foregroundStyle(DesignTokens.textSecondary)
        } else {
          // The rows get a vertical scroll view of their own with a fixed
          // height, like the Hub opportunity table: inside the horizontal
          // scroll view a LazyVStack sees no vertical viewport and builds
          // every row, which made the whole page slow (26.11.2026).
          ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
              tableHeader
              Divider()
              ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                  ForEach(rows) { row in
                    DoctrineStockRowView(display: row, format: numberFormat)
                      .equatable()
                    Divider().opacity(0.4)
                  }
                }
              }
              .defaultScrollAnchor(.top)
              .frame(height: tableRowsHeight(rowCount: rows.count))
            }
            .frame(width: max(availableTableWidth, minimumTableWidth), alignment: .leading)
          }
          .defaultScrollAnchor(.leading)
          .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            availableTableWidth = $0
          }
        }
        Text(
          "Largest shortfall first. Target comes from Allumis: target per fit × quantity in the fit, summed over every Allumis fit, hull once per fit, refits not counted; a fit used by several doctrines counts once. In stock = listed at the Home Hub; shortfall = target minus in stock, what still has to be built or imported. Doctrines lists the doctrines that use the item, those with a target first. Fits counts every fit of the wiki and of the group “Only at Allumis” that uses the item. A loaded charge (Module, Charge) counts once per module, because EFT does not state the loaded amount."
        )
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  /// Height of the scrolling row area: the page viewport minus room for the
  /// panel title, filters and table header, at least 240 pt; shorter when
  /// fewer rows need less (estimated row height 44 pt).
  private func tableRowsHeight(rowCount: Int) -> CGFloat {
    let viewport = max(240, pageViewportHeight - 150)
    return min(viewport, CGFloat(rowCount) * 44 + 4)
  }

  private var minimumTableWidth: CGFloat {
    nameMinimumWidth + doctrineColumnWidth + recommendationWidth
      + CGFloat(numberColumnCount) * numberWidth
      + CGFloat(numberColumnCount + 2) * DesignTokens.spacingXS
  }

  /// The stored doctrine filter, or every doctrine when it no longer exists.
  private var effectiveDoctrineFilterID: String {
    guard !doctrineFilterID.isEmpty,
      doctrineRows.contains(where: { $0.id == doctrineFilterID })
    else { return "" }
    return doctrineFilterID
  }

  private var doctrineFilterBinding: Binding<String> {
    Binding(
      get: { effectiveDoctrineFilterID },
      set: { doctrineFilterID = $0 }
    )
  }

  private var tableHeader: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      SortableTableHeader(title: "Item", column: DoctrineStockSortColumn.name, sort: $sort)
        .frame(minWidth: nameMinimumWidth, maxWidth: .infinity, alignment: .leading)
      SortableTableHeader(
        title: "Doctrines",
        column: DoctrineStockSortColumn.doctrines,
        sort: $sort,
        defaultDirection: .descending
      )
      .frame(width: doctrineColumnWidth, alignment: .leading)
      .help(AppLocalization.text("Doctrines whose fits use the item; sorted by their number."))
      numberHeader("Fits", .fitCount)
        .help(AppLocalization.text("How many fits of the wiki and of the group “Only at Allumis” use the item."))
      numberHeader("Target units", .requiredQuantity)
        .help(
          AppLocalization.text(
            "Σ Allumis target per fit × quantity in the fit over every Allumis fit, hull once per fit, refits not counted."
          ))
      numberHeader("Current stock", .listedQuantity)
        .help(AppLocalization.text("Sell units of every seller at the Home Hub at the latest stock point."))
      numberHeader("Shortfall", .shortfall)
        .help(AppLocalization.text("Target minus current stock, at least 0: what still has to be built or imported."))
      numberHeader("Sold/day region", .regionUnitsPerDay)
      numberHeader("Sold/day hub", .hubUnitsPerDay)
      numberHeader("Sold/day Allumis", .allumisAverageDailyVolume7Days)
        .help(AppLocalization.text("Ø units sold per day over 7 days at the staging market, according to Allumis."))
      numberHeader("Lost 10 days", .allumisLostLast10Days)
        .help(
          AppLocalization.text("Units destroyed and dropped in the last 10 days according to Allumis (killmails)."))
      numberHeader("Stock lasts", .coverage, defaultDirection: .ascending)
      numberHeader("Build/unit", .buildCostPerUnit, defaultDirection: .ascending)
      numberHeader("Import/unit", .importCostPerUnit, defaultDirection: .ascending)
      numberHeader("Home sell", .homeBestSellPrice)
      numberHeader("Home ÷ Main", .homeToMainPriceRatio)
        .help(AppLocalization.text("Best Home Hub sell as a percentage of the lowest Main Hub sell."))
      numberHeader("Recommendation", .recommendation, width: recommendationWidth)
        .help(AppLocalization.text("The cheaper way per unit; below it what it saves per unit."))
      numberHeader("Profit/unit", .profitPerUnit)
    }
    .appFont(.caption.weight(.semibold))
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private func numberHeader(
    _ title: LocalizedStringKey,
    _ column: DoctrineStockSortColumn,
    width: CGFloat? = nil,
    defaultDirection: AppTableSortDirection = .descending
  ) -> some View {
    SortableTableHeader(
      title: title,
      column: column,
      sort: $sort,
      defaultDirection: defaultDirection,
      alignment: .trailing
    )
    .frame(
      minWidth: width ?? numberWidth,
      maxWidth: width ?? .infinity,
      alignment: .trailing
    )
  }

  private var filteredRows: [DoctrineStockDisplayRow] {
    let filter = kindFilter
    let doctrineID = effectiveDoctrineFilterID
    let filtered = displayRows.filter {
      filter.includes($0.row.kind)
        && (doctrineID.isEmpty || $0.row.demand.doctrineIDs.contains(doctrineID))
    }
    let order = DoctrineStockRowSorter.sorted(
      filtered.map(\.row),
      by: sort.column,
      ascending: sort.direction == .ascending
    )
    let byType = Dictionary(
      filtered.map { ($0.row.typeID, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    return order.compactMap { byType[$0.typeID] }
  }

  private func summaryText(_ rows: [DoctrineStockDisplayRow]) -> String {
    let out = rows.filter { $0.row.coverage == .outOfStock }.count
    guard let allumis else {
      return AppLocalization.format(
        "%lld items · %lld out of stock · no target without an Allumis import",
        Int64(rows.count),
        Int64(out)
      )
    }
    let short = rows.filter { ($0.row.shortfall ?? 0) > 0 }.count
    let fitsWithTarget = allumis.fits.filter { $0.target > 0 }.count
    return AppLocalization.format(
      "%lld items · %lld out of stock · %lld with shortfall · target from %lld Allumis fits",
      Int64(rows.count),
      Int64(out),
      Int64(short),
      Int64(fitsWithTarget)
    )
  }

  // MARK: Rows

  private var analysis: ManufacturingOpportunitySnapshot? {
    switch runtime.tradeDataRole(for: .home) {
    case nil: nil
    case .main: runtime.manufacturingOpportunityAnalysis
    case let dataRole?: runtime.opportunityState(for: dataRole).analysis
    }
  }

  private var homeIsMainHub: Bool {
    guard let home = runtime.tradeLocation(for: .home),
      let main = runtime.tradeLocation(for: .main)
    else { return false }
    return home.representsSameLocation(as: main)
  }

  private var blueprintCostPerRun: Double? {
    OpportunityCostInputs.parseNonnegativeISK(blueprintCostPerRunText)
  }

  private var contractContext: ManufacturingOpportunityContractContext {
    ManufacturingOpportunityContractContext(
      references: runtime.opportunityContractReferences,
      contractFeeRate: runtime.publicContractFeeRate(for: .home),
      blueprintOffers: runtime.opportunityBlueprintOffers,
      loyaltyStoreBlueprintTypeIDs: runtime.loyaltyStoreOfferedTypeIDSet,
      loyaltyStoreBlueprintOffers: loyaltyStoreBlueprintOffers,
      inventionEstimates: runtime.opportunityInventionEstimates,
      usesOwnBlueprintRights: usesOwnBlueprintRights
    )
  }

  private var loyaltyOfferTrigger: DoctrineLoyaltyOfferTrigger {
    let loyaltyStoreBlueprints = runtime.loyaltyStoreOfferedTypeIDSet
    let typeIDs = libraryTypeIDs
    let blueprintTypeIDs = Set(
      typeIDs.compactMap { scanRowsByType[$0] }
        .filter {
          ManufacturingOpportunityBlueprintAcquisitionProjector.requiresBlueprintCopy(
            row: $0,
            loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprints
          )
        }
        .map(\.blueprintTypeID)
    )
    return DoctrineLoyaltyOfferTrigger(
      blueprintTypeIDs: blueprintTypeIDs,
      catalogID: runtime.loyaltyStoreCatalog?.id,
      loyaltyPoints: runtime.characterLoyaltyPoints,
      wallets: OpportunityCostInputs.walletISKByCharacterName(characters)
    )
  }

  private struct StockKey: Equatable {
    let home: Int64?
    let main: Int64?
  }

  private var stockKey: StockKey {
    StockKey(
      home: runtime.tradeLocation(for: .home)?.locationID,
      main: runtime.tradeLocation(for: .main)?.locationID
    )
  }

  private struct TransportKey: Equatable {
    let logistics: LogisticsConfiguration
    let hubs: [ProcurementLocation?]
    let mainMarketCapturedAt: Date?
  }

  private var transportKey: TransportKey {
    TransportKey(
      logistics: runtime.productionBasis.logistics,
      hubs: [runtime.tradeLocation(for: .main), runtime.tradeLocation(for: .home)],
      mainMarketCapturedAt: runtime.mainHubMarketState?.value?.capturedAt
    )
  }

  private struct VolumeHistoryKey: Equatable {
    let regionID: Int64?
    let typeIDs: Set<Int64>
  }

  private var volumeHistoryKey: VolumeHistoryKey {
    VolumeHistoryKey(regionID: runtime.tradeRegionID(for: .home), typeIDs: libraryTypeIDs)
  }

  /// Everything the rows depend on; they are recomputed only when it changes.
  private struct RowsKey: Equatable {
    let libraryImportedAt: Date?
    let libraryFitCount: Int
    let allumisImportedAt: Date?
    let language: String
    let analysisID: UUID?
    let scanRowsAnalysisID: UUID?
    let homeMarketCapturedAt: Date?
    let mainMarketCapturedAt: Date?
    let homeFees: TradeHubFees
    let mainFees: TradeHubFees
    let transport: TradeTransportBasis?
    let homeIsMainHub: Bool
    let stockRevision: Int
    let historyRevision: Int
    let metadata: DoctrineItemCatalogMetadata?
    let buildIndexCount: Int?
    let costIncludesBlueprint: Bool
    let buildsIntermediates: Bool
    let blueprintCostPerRunText: String
    let usesOwnBlueprintRights: Bool
    let contractReferencesID: UUID?
    let blueprintOfferCount: Int
    let inventionRevision: UUID
    let loyaltyOfferCount: Int
    let utcDay: Date
  }

  private var rowsKey: RowsKey {
    RowsKey(
      libraryImportedAt: library?.importedAt,
      libraryFitCount: sources?.library.fits.count ?? 0,
      allumisImportedAt: allumis?.importedAt,
      language: locale.identifier,
      analysisID: analysis?.id,
      scanRowsAnalysisID: scanRowsAnalysisID,
      homeMarketCapturedAt: runtime.tradeMarketState(for: .home)?.value?.capturedAt,
      mainMarketCapturedAt: runtime.tradeMarketState(for: .main)?.value?.capturedAt,
      homeFees: runtime.tradeHubFees(for: .home),
      mainFees: runtime.tradeHubFees(for: .main),
      transport: runtime.tradeTransportBases[TradeMode.mainToHome.route],
      homeIsMainHub: homeIsMainHub,
      stockRevision: runtime.marketStockOverviewsRevision,
      historyRevision: runtime.tradeVolumeHistoriesRevision,
      metadata: metadata,
      buildIndexCount: runtime.plannerBuildTargetIndex?.count,
      costIncludesBlueprint: costIncludesBlueprint,
      buildsIntermediates: buildsIntermediates,
      blueprintCostPerRunText: blueprintCostPerRunText,
      usesOwnBlueprintRights: usesOwnBlueprintRights,
      contractReferencesID: runtime.opportunityContractReferences?.id,
      blueprintOfferCount: runtime.opportunityBlueprintOffers.count,
      inventionRevision: runtime.opportunityInventionRevision,
      loyaltyOfferCount: loyaltyStoreBlueprintOffers.count,
      utcDay: MarketTypeVolumeHistory.utcDay(.now)
    )
  }

  private func computeRows(revision: Int) -> [DoctrineStockDisplayRow] {
    guard let sources else { return [] }
    let library = sources.library
    let demands = DoctrineDemandAggregator.demands(sources: sources)
    let allumisFigures = allumis.map(DoctrineAllumisItemAggregator.figures(snapshot:))
    let doctrinesByID = Dictionary(
      library.doctrines.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let snapshot = analysis
    let rowsByType = scanRowsAnalysisID == snapshot?.id ? scanRowsByType : [:]
    let sheet = OpportunityCostInputs.costSheet(
      includesBlueprint: costIncludesBlueprint,
      blueprintCostPerRun: blueprintCostPerRun
    )
    let contract = contractContext
    let homeFees = runtime.tradeHubFees(for: .home)
    let mainFees = runtime.tradeHubFees(for: .main)
    let homeMarket = runtime.tradeMarketState(for: .home)?.value
    let mainMarket = runtime.tradeMarketState(for: .main)?.value
    let stock = runtime.marketStockOverview(for: .home)
    let histories = runtime.tradeVolumeHistory(for: .home)
    let sameHub = homeIsMainHub
    let transport = runtime.tradeTransportBases[TradeMode.mainToHome.route] ?? .none
    let buildIndex = runtime.plannerBuildTargetIndex
    let loyaltyStoreBlueprints = runtime.loyaltyStoreOfferedTypeIDSet

    return demands.map { demand in
      let typeID = demand.typeID
      let kind =
        metadata?.categoryNames[typeID].map { DoctrineItemKind.kind(categoryName: $0) }
        ?? (demand.isHull ? .hull : .module)
      let listed = stock?.currentStock(for: typeID)?.sell.units
      let regionPerDay = histories?.historiesByType[typeID]?.averageDailyVolume(.thirtyDays)
      let hubVolume = stock?.hubTradedVolume(for: typeID, window: .thirtyDays)
      let buildability: DoctrineBuildability =
        buildIndex.map { $0[typeID] != nil ? .buildable : .notBuildable } ?? .unknown

      var issues: [String] = []
      var cost: StockSaleProductionCost?
      let scanRow = rowsByType[typeID]
      if buildability != .notBuildable {
        if let scanRow, let snapshot {
          let defaults = StockSaleProductionCostProjector.defaultEfficiency(
            for: scanRow,
            loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprints
          )
          let supports = scanRow.supportsBlueprintEfficiency
          let quantity = max(1, (demand.requiredQuantity ?? 0) - max(0, listed ?? 0))
          cost = StockSaleProductionCostProjector.project(
            row: scanRow,
            quantity: min(quantity, StockSalePasteParser.maximumQuantity),
            materialEfficiency: supports ? defaults.materialEfficiency : 0,
            timeEfficiency: supports ? defaults.timeEfficiency : 0,
            buildsIntermediates: buildsIntermediates,
            sheet: sheet,
            contract: contract,
            snapshot: snapshot
          )
          if cost?.costPerUnit == nil {
            let messages = (cost?.warnings ?? [])
              .filter { $0.severity != .information }
              .map { AppLocalization.text($0.message) }
            issues += messages.isEmpty
              ? [AppLocalization.text("Part of the new production cost is unknown.")]
              : Array(Set(messages)).sorted()
          }
        } else if snapshot == nil {
          issues.append(
            AppLocalization.text(
              "No Hub opportunity scan for this hub, so the new production cost is unknown."))
        } else {
          issues.append(
            AppLocalization.text(
              "No new production cost: the item is not in the Hub opportunity scan of this hub (not manufacturable, excluded or without complete data)."
            )
          )
        }
      }

      let trade = TradeCalculator.row(
        item: TradeItemInput(
          typeID: typeID,
          name: demand.name,
          packagedVolume: metadata?.packagedVolumes[typeID],
          source: mainMarket?.pricesByType[typeID],
          target: homeMarket?.pricesByType[typeID]
        ),
        mode: .mainToHome,
        sourceSide: .minSell,
        targetSide: .minSell,
        sourceFees: mainFees,
        targetFees: homeFees,
        transport: transport
      )
      let importHasNoSource =
        mainMarket != nil && mainMarket?.pricesByType[typeID]?.bestSellPrice == nil
      var tradeIssues = trade.issues
      if sameHub {
        tradeIssues.removeAll {
          $0 == .transportUnavailable || $0 == .missingPackagedVolume
            || $0 == .exceedsJumpFreighterCapacity
        }
      }
      issues += tradeIssues.map(TradeHubText.issueText)

      let input = DoctrineStockRowInput(
        kind: kind,
        listedQuantity: listed,
        regionUnitsPerDay: regionPerDay,
        hubUnitsPerDay: hubVolume?.averagePerRecordedDay,
        hubVolumeIsComplete: hubVolume?.isComplete,
        buildability: buildability,
        buildCostPerUnit: cost?.costPerUnit,
        importPurchasePerUnit: trade.purchaseCost,
        importTransportPerUnit: sameHub ? 0 : trade.transportCost,
        importHasNoSource: importHasNoSource,
        homeBestSellPrice: homeMarket?.pricesByType[typeID]?.bestSellPrice,
        homeNetSalePerUnit: trade.netSale,
        mainBestSellPrice: mainMarket?.pricesByType[typeID]?.bestSellPrice,
        allumis: allumisFigures.map { $0[typeID] ?? .notListed }
      )
      let row = DoctrineStockCalculator.row(demand: demand, input: input)
      let doctrines = demand.doctrineIDs.compactMap { doctrinesByID[$0] }
      let parts = demand.requiredQuantityByDoctrineID
      let withTarget = doctrines.filter { (parts[$0.id] ?? 0) > 0 }
      let others = doctrines.filter { (parts[$0.id] ?? 0) <= 0 }
      return DoctrineStockDisplayRow(
        revision: revision,
        row: row,
        issues: issues,
        buildHelp: buildHelp(cost),
        importHelp: importHelp(row),
        doctrinesWithTarget: withTarget.map(doctrineTitle),
        otherDoctrines: others.map(doctrineTitle),
        doctrinesHelp: (withTarget + others).map { doctrine in
          let part = parts[doctrine.id] ?? 0
          return part > 0
            ? AppLocalization.format("%@ (target %lld)", doctrineTitle(doctrine), part)
            : doctrineTitle(doctrine)
        }.joined(separator: "\n")
      )
    }
  }

  private func buildHelp(_ cost: StockSaleProductionCost?) -> String {
    guard let cost else { return "" }
    return AppLocalization.format(
      "%@ units in %@ runs, ME %@ / TE %@. Per unit: material %@ · installation %@ · Blueprint %@ · logistics %@.",
      formatInteger(cost.producedQuantity),
      formatInteger(Int64(cost.runs)),
      cost.materialEfficiency.map { String($0) } ?? "—",
      cost.timeEfficiency.map { String($0) } ?? "—",
      formatNumber(cost.materialCostPerUnit),
      formatNumber(cost.installationCostPerUnit),
      formatNumber(cost.blueprintCostPerUnit),
      formatNumber(cost.logisticsCostPerUnit)
    )
  }

  private func importHelp(_ row: DoctrineStockRow) -> String {
    AppLocalization.format(
      "Main Hub purchase %@ + transport %@ per unit.",
      formatNumber(row.input.importPurchasePerUnit),
      formatNumber(row.input.importTransportPerUnit)
    )
  }

  private func issueText(_ issue: DoctrineImportIssue) -> String {
    let page = issue.pageID.split(separator: ":").last.map(String.init) ?? issue.pageID
    switch issue.kind {
    case .linkedPageMissing:
      return AppLocalization.format("%@: linked ship page %@ does not exist.", page, issue.detail)
    case .linkedSectionMissing:
      return AppLocalization.format(
        "%@: section %@ no longer exists; every fit of that page counts.",
        page,
        issue.detail
      )
    case .doctrineWithoutFits:
      return AppLocalization.format("%@: no fit found.", page)
    case .unknownItemName:
      return AppLocalization.format("%@: item “%@” is not in the SDE.", page, issue.detail)
    case .ambiguousItemName:
      return AppLocalization.format("%@: item “%@” matches several SDE types.", page, issue.detail)
    case .pageUnreadable:
      return AppLocalization.format("%@: page could not be read.", page)
    }
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

  private func refreshSessionState() async {
    hasStoredSession = await DoctrineWikiSession.shared.hasStoredSession()
    hasAllumisSession = await DoctrineAllumisSession.shared.hasStoredSession()
    allumisSignInConfirmed = DoctrineAllumisSession.shared.signInConfirmed
  }

  private func rebuildSources() {
    sources = DoctrineAllumisMerger.merge(library: library, snapshot: allumis)
    libraryTypeIDs = sources?.allTypeIDs ?? []
    rebuildDoctrineRows()
  }

  /// Texts of the doctrine list for the current sources and language.
  private func rebuildDoctrineRows() {
    guard let sources else {
      doctrineRows = []
      return
    }
    let format = numberFormat
    let wikiHelp = AppLocalization.text("Opens the doctrine page in the browser.")
    let allumisHelp = AppLocalization.text("Opens the fit list of Allumis in the browser.")
    doctrineRows = sources.library.doctrines.map { doctrine in
      let isOnlyAtAllumis = doctrine.id == DoctrineAllumisMerge.onlyAtAllumisDoctrineID
      return DoctrineListRowModel(
        id: doctrine.id,
        title: doctrineTitle(doctrine),
        linkURL: isOnlyAtAllumis
          ? DoctrineAllumisSession.shared.configuration.fitListURL
          : DoctrineWikiSession.shared.configuration.pageURL(pageID: doctrine.id),
        linkHelp: isOnlyAtAllumis ? allumisHelp : wikiHelp,
        fitCount: doctrine.fitIDs.count,
        fitCountText: format.integer(Int64(doctrine.fitIDs.count)),
        allumis: allumis == nil
          ? nil : allumisCellModel(sources.allumisTargets(for: doctrine), format: format)
      )
    }
  }

  private func allumisCellModel(
    _ figures: DoctrineAllumisTargets,
    format: DoctrineNumberFormat
  ) -> DoctrineAllumisCellModel {
    let values = figures.targetCounts.map { format.integer(Int64($0.target)) }
    var lines = figures.targetCounts.map {
      AppLocalization.format(
        "Allumis target %lld for %lld fits",
        Int64($0.target),
        Int64($0.fitCount)
      )
    }
    let missing = figures.fitCount - figures.matchedFitCount
    if missing > 0 {
      lines.append(AppLocalization.format("%lld fits are not at Allumis.", Int64(missing)))
    }
    if figures.contentDiffersFitCount > 0 {
      lines.append(
        AppLocalization.format(
          "%lld fits paired by hull and name; their items differ from Allumis.",
          Int64(figures.contentDiffersFitCount)
        )
      )
    }
    return DoctrineAllumisCellModel(
      valuesText: values.isEmpty
        ? AppLocalization.text("not at Allumis") : values.joined(separator: " · "),
      hasValues: !values.isEmpty,
      caption: figures.matchedFitCount > 0
        ? AppLocalization.format(
          "%lld of %lld fits",
          Int64(figures.matchedFitCount),
          Int64(figures.fitCount)
        ) : nil,
      showsWarning: figures.contentDiffersFitCount > 0,
      mostFrequentTarget: figures.mostFrequentTarget,
      help: lines.joined(separator: "\n")
    )
  }

  private func startAllumisImport() {
    let resolve: AllumisImporter.Resolve = { [runtime] names in
      try await runtime.resolveItemTypeNames(names)
    }
    allumisController.start(resolve: resolve) { [modelContext] snapshot in
      try Self.saveAllumis(snapshot, in: modelContext)
    }
  }

  private func startImport() {
    let resolve: DoctrineWikiImporter.Resolve = { [runtime] names in
      try await runtime.resolveItemTypeNames(names)
    }
    importController.start(resolve: resolve) { [modelContext] library in
      try Self.saveLibrary(library, in: modelContext)
    }
  }

  /// Static, because the import may finish after the page was left; the
  /// import status reports a failure.
  private static func saveLibrary(
    _ library: DoctrineLibrary,
    in modelContext: ModelContext
  ) throws {
    let data = try DoctrineLibrary.encode(library)
    do {
      try modelContext.upsertAppSetting(
        key: AppSettingKey.doctrineStockLibrary,
        value: String(decoding: data, as: UTF8.self)
      )
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  /// Static, because the import may finish after the page was left.
  private static func saveAllumis(
    _ snapshot: AllumisDoctrineSnapshot,
    in modelContext: ModelContext
  ) throws {
    let data = try AllumisDoctrineSnapshot.encode(snapshot)
    do {
      try modelContext.upsertAppSetting(
        key: AppSettingKey.doctrineStockAllumis,
        value: String(decoding: data, as: UTF8.self)
      )
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  private func loadStoredData() {
    guard !hasLoadedStoredData else { return }
    hasLoadedStoredData = true
    defer { rebuildSources() }
    do {
      if let stored = try modelContext.appSettingValue(for: AppSettingKey.doctrineStockLibrary),
        let data = stored.data(using: .utf8)
      {
        library = try DoctrineLibrary.decode(data)
      }
    } catch {
      persistenceError = AppLocalization.format(
        "The saved doctrines could not be read: %@",
        error.localizedDescription
      )
    }
    do {
      if let stored = try modelContext.appSettingValue(for: AppSettingKey.doctrineStockAllumis),
        let data = stored.data(using: .utf8)
      {
        allumis = try AllumisDoctrineSnapshot.decode(data)
      }
    } catch {
      persistenceError = AppLocalization.format(
        "The saved Allumis data could not be read: %@",
        error.localizedDescription
      )
    }
    // The former targets per doctrine (`AppSettingKey.doctrineStockTargets`)
    // are no longer read since 27.11.2026; the target comes from Allumis.
  }

  // MARK: Formatting

  private var numberFormat: DoctrineNumberFormat { DoctrineNumberFormat(locale: locale) }

  private func formatNumber(_ value: Double?) -> String { numberFormat.number(value) }

  private func formatRate(_ value: Double?) -> String { numberFormat.rate(value) }

  private func formatInteger(_ value: Int64?) -> String { numberFormat.integer(value) }

  private func formatPercent(_ fraction: Double?) -> String { numberFormat.percent(fraction) }
}

// MARK: Supporting types

enum DoctrineKindFilter: String, CaseIterable {
  case all
  case hull
  case module
  case charge
  case drone

  var title: LocalizedStringKey {
    switch self {
    case .all: "All"
    case .hull: "Hulls"
    case .module: "Modules & other"
    case .charge: "Ammo & charges"
    case .drone: "Drones"
    }
  }

  func includes(_ kind: DoctrineItemKind) -> Bool {
    switch self {
    case .all: true
    case .hull: kind == .hull
    case .module: kind == .module
    case .charge: kind == .charge
    case .drone: kind == .drone
    }
  }
}

enum DoctrineListSortColumn: Hashable {
  case title
  case fitCount
  /// Most frequent Allumis target of the doctrine's fits.
  case allumis
}

enum DoctrineLoginSource: String, Identifiable {
  case wiki
  case allumis

  var id: String { rawValue }
}

enum DoctrineImportStatus: Equatable {
  case idle
  case running(DoctrineWikiImportProgress?)
  case failed(String)
  case succeeded

  var isRunning: Bool {
    if case .running = self { return true }
    return false
  }
}

struct DoctrineStockDisplayRow: Identifiable {
  /// The row computation that produced this row.
  let revision: Int
  let row: DoctrineStockRow
  let issues: [String]
  let buildHelp: String
  let importHelp: String
  /// Titles of the doctrines with a target that use the item.
  let doctrinesWithTarget: [String]
  /// Titles of the other doctrines that use the item.
  let otherDoctrines: [String]
  let doctrinesHelp: String

  var id: Int64 { row.typeID }
}

private struct DoctrineLoyaltyOfferTrigger: Equatable {
  let blueprintTypeIDs: Set<Int64>
  let catalogID: UUID?
  let loyaltyPoints: CharacterLoyaltyPointsSnapshot?
  let wallets: [String: Double]
}

/// One row of the doctrine item table. Equatable on the row's identity, the
/// revision of the computation that produced it and the locale, so a page
/// update that leaves the row unchanged does not build it again
/// (Geschwindigkeit 26.11.2026).
struct DoctrineStockRowView: View, Equatable {
  let display: DoctrineStockDisplayRow
  let format: DoctrineNumberFormat

  private var nameMinimumWidth: CGFloat { DoctrineStockTableLayout.nameMinimumWidth }
  private var numberWidth: CGFloat { DoctrineStockTableLayout.numberWidth }
  private var recommendationWidth: CGFloat { DoctrineStockTableLayout.recommendationWidth }
  private var doctrineColumnWidth: CGFloat { DoctrineStockTableLayout.doctrineColumnWidth }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.display.id == rhs.display.id && lhs.display.revision == rhs.display.revision
      && lhs.format == rhs.format
  }

  var body: some View {
    let row = display.row
    return HStack(spacing: DesignTokens.spacingXS) {
      HStack(spacing: DesignTokens.spacingXS) {
        EVEItemText(
          value: row.name,
          typeID: row.typeID,
          font: .callout,
          lineLimit: 1,
          iconSize: 18
        )
        if !display.issues.isEmpty {
          Image(systemName: "info.circle")
            .foregroundStyle(DesignTokens.caution)
            .help(display.issues.joined(separator: "\n"))
        }
      }
      .frame(minWidth: nameMinimumWidth, maxWidth: .infinity, alignment: .leading)
      doctrinesCell
      numberCell(format.integer(Int64(row.demand.fitCount)))
      targetCell(row.demand.requiredQuantity)
      numberCell(format.integer(row.input.listedQuantity))
      numberCell(
        format.integer(row.shortfall),
        tint: (row.shortfall ?? 0) > 0 ? DesignTokens.negative : DesignTokens.textPrimary
      )
      numberCell(format.rate(row.input.regionUnitsPerDay))
      numberCell(
        format.rate(row.input.hubUnitsPerDay),
        tint: row.input.hubVolumeIsComplete == false ? DesignTokens.caution : DesignTokens.textPrimary
      )
      .help(
        row.input.hubVolumeIsComplete == false
          ? AppLocalization.text("Not every day of the 30 days is fully recorded in the stock history.")
          : ""
      )
      numberCell(format.rate(row.input.allumis?.averageDailyVolume7Days))
      numberCell(format.integer(row.input.allumis?.lostLast10Days))
        .help(
          row.input.allumis.map {
            AppLocalization.format(
              "Destroyed %@ · dropped %@",
              format.integer($0.destroyed),
              format.integer($0.dropped)
            )
          } ?? ""
        )
      coverageCell(row.coverage)
      numberCell(
        row.input.buildability == .notBuildable
          ? AppLocalization.text("not buildable") : format.number(row.input.buildCostPerUnit),
        tint: row.recommendation == .build ? DesignTokens.positive : DesignTokens.textPrimary
      )
      .help(display.buildHelp)
      numberCell(
        format.number(row.importCostPerUnit),
        tint: row.recommendation == .importFromMainHub
          ? DesignTokens.positive : DesignTokens.textPrimary
      )
      .help(display.importHelp)
      numberCell(format.number(row.input.homeBestSellPrice))
      numberCell(format.ratio(row.homeToMainPriceRatio))
        .help(
          AppLocalization.format(
            "Home Hub %@ · Main Hub %@",
            format.number(row.input.homeBestSellPrice),
            format.number(row.input.mainBestSellPrice)
          )
        )
      recommendationCell(row)
      numberCell(format.number(row.profitPerUnit), tint: signTint(row.profitPerUnit))
    }
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private var doctrinesCell: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      if !display.doctrinesWithTarget.isEmpty {
        Text(verbatim: display.doctrinesWithTarget.joined(separator: ", "))
          .foregroundStyle(DesignTokens.textPrimary)
          .lineLimit(1)
          .layoutPriority(1)
      }
      if !display.otherDoctrines.isEmpty {
        Text(
          verbatim: display.doctrinesWithTarget.isEmpty
            ? display.otherDoctrines.joined(separator: ", ")
            : "+\(display.otherDoctrines.count)"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        .lineLimit(1)
      }
    }
    .appFont(.caption)
    .frame(width: doctrineColumnWidth, alignment: .leading)
    .help(display.doctrinesHelp)
  }

  /// “—” without an Allumis import (target unknown), “–” when no Allumis
  /// fit with a target uses the item.
  private func targetCell(_ target: Int64?) -> some View {
    guard let target else { return numberCell("—", tint: DesignTokens.textSecondary) }
    return target > 0
      ? numberCell(format.integer(target))
      : numberCell("–", tint: DesignTokens.textSecondary)
  }

  private func coverageCell(_ coverage: DoctrineStockCoverage) -> some View {
    let (text, tint): (String, Color) =
      switch coverage {
      case .outOfStock: (AppLocalization.text("out of stock"), DesignTokens.negative)
      case .noSales: (AppLocalization.text("no sales"), DesignTokens.textSecondary)
      case .unknown: ("—", DesignTokens.textSecondary)
      case .days(let days):
        (
          AppLocalization.format(
            "%@ days",
            days < 10
              ? days.formatted(.number.precision(.fractionLength(1)).locale(format.locale))
              : days.formatted(.number.precision(.fractionLength(0)).locale(format.locale))
          ),
          days < 3 ? DesignTokens.caution : DesignTokens.textPrimary
        )
      }
    return numberCell(text, tint: tint)
  }

  private func recommendationCell(_ row: DoctrineStockRow) -> some View {
    let (text, symbol, tint): (String, String, Color) =
      switch row.recommendation {
      case .build?: (AppLocalization.text("Build"), "hammer.fill", DesignTokens.positive)
      case .importFromMainHub?:
        (AppLocalization.text("Import"), "shippingbox.fill", DesignTokens.highlight)
      case nil: ("—", "questionmark", DesignTokens.textSecondary)
      }
    return VStack(alignment: .trailing, spacing: 0) {
      HStack(spacing: 4) {
        if row.recommendation != nil {
          Image(systemName: symbol)
        }
        Text(verbatim: text)
      }
      .appFont(.callout.weight(.semibold))
      .foregroundStyle(tint)
      if let savings = row.savingsPerUnit {
        Text(
          verbatim: AppLocalization.format(
            "saves %@/unit",
            format.number(savings)
          )
        )
        .appFont(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .frame(width: recommendationWidth, alignment: .trailing)
  }

  private func numberCell(
    _ text: String,
    tint: Color = DesignTokens.textPrimary
  ) -> some View {
    Text(verbatim: text)
      .appFont(.callout.monospacedDigit())
      .foregroundStyle(tint)
      .lineLimit(1)
      .frame(minWidth: numberWidth, maxWidth: .infinity, alignment: .trailing)
  }

  private func signTint(_ value: Double?) -> Color {
    guard let value else { return DesignTokens.textPrimary }
    return value < 0 ? DesignTokens.negative : DesignTokens.positive
  }
}

/// Column widths shared by the table header and its rows.
enum DoctrineStockTableLayout {
  static let nameMinimumWidth: CGFloat = 220
  static let numberWidth: CGFloat = 92
  static let recommendationWidth: CGFloat = 150
  static let doctrineColumnWidth: CGFloat = 200
}

/// Number formatting of the page with a locale read once, instead of the
/// app language from the user defaults for every number.
struct DoctrineNumberFormat: Equatable {
  let locale: Locale

  func number(_ value: Double?) -> String {
    value.map {
      $0.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    } ?? "—"
  }

  func rate(_ value: Double?) -> String {
    value.map {
      $0.formatted(
        .number.precision(.fractionLength($0 < 10 ? 1 : 0)).locale(locale)
      )
    } ?? "—"
  }

  func integer(_ value: Int64?) -> String {
    value.map { $0.formatted(.number.locale(locale)) } ?? "—"
  }

  func ratio(_ ratio: Double?) -> String {
    ratio.map {
      $0.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    } ?? "—"
  }

  func percent(_ fraction: Double?) -> String {
    fraction.map {
      $0.formatted(.percent.precision(.fractionLength(2)).locale(locale))
    } ?? "—"
  }
}

/// A doctrine of the list with every text computed once per import or
/// language, not on every page update.
struct DoctrineListRowModel: Equatable, Identifiable {
  let id: String
  let title: String
  let linkURL: URL
  let linkHelp: String
  let fitCount: Int
  let fitCountText: String
  /// Nil without an Allumis import.
  let allumis: DoctrineAllumisCellModel?
}

struct DoctrineAllumisCellModel: Equatable {
  /// Allumis targets, most frequent first, or “not at Allumis”.
  let valuesText: String
  let hasValues: Bool
  /// “x of y fits”, nil when no fit is at Allumis.
  let caption: String?
  let showsWarning: Bool
  /// Sort value of the column; nil when no fit is at Allumis.
  let mostFrequentTarget: Int?
  let help: String
}

/// One doctrine of the list; rebuilt only when its texts change.
struct DoctrineListRowView: View, Equatable {
  let model: DoctrineListRowModel
  let allumisColumnWidth: CGFloat

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.model == rhs.model && lhs.allumisColumnWidth == rhs.allumisColumnWidth
  }

  var body: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Link(destination: model.linkURL) {
        Text(verbatim: model.title).lineLimit(1)
      }
      .help(model.linkHelp)
      .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
      Text(verbatim: model.fitCountText)
        .appFont(.callout.monospacedDigit())
        .frame(width: 70, alignment: .trailing)
      if let allumis = model.allumis {
        allumisCell(allumis)
          .frame(width: allumisColumnWidth, alignment: .trailing)
      }
    }
    .padding(.vertical, 2)
  }

  private func allumisCell(_ allumis: DoctrineAllumisCellModel) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(verbatim: allumis.valuesText)
        .appFont(allumis.hasValues ? .callout.monospacedDigit() : .caption)
        .foregroundStyle(allumis.hasValues ? DesignTokens.textPrimary : DesignTokens.textSecondary)
        .lineLimit(1)
      if let caption = allumis.caption {
        HStack(spacing: 2) {
          if allumis.showsWarning {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(DesignTokens.caution)
          }
          Text(verbatim: caption)
        }
        .appFont(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .help(allumis.help)
  }
}

/// Progress of the regional history load. A view of its own, so the many
/// progress steps update only this line and not the whole page
/// (Geschwindigkeit 26.11.2026).
struct DoctrineHistoryProgressLine: View {
  @Environment(RuntimeState.self) private var runtime

  var body: some View {
    if let progress = runtime.tradeRegionID(for: .home).flatMap({ runtime.tradeVolumeHistoryProgress[$0] }) {
      Text(
        AppLocalization.format(
          "Loading the region's market history: %lld of %lld items",
          Int64(progress.completed),
          Int64(progress.total)
        )
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }
}
