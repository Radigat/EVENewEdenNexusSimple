import AppKit
import EVENexusCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MoonMaterialPurchaseAnalysisView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Query private var characters: [StoredCharacter]
  @State private var isExportingImage = false
  @State private var imageExportMessage: String?
  @State private var materialSort = AppTableSortDescriptor(
    column: MoonMaterialSortColumn.material,
    direction: .ascending
  )

  private let materialColumnWidth: CGFloat = 190
  private let marketColumnWidth: CGFloat = 190
  private let rowMinimumHeight: CGFloat = 72

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
      header
      if let imageExportMessage {
        Label(imageExportMessage, systemImage: "photo")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      explanation

      if let error = runtime.moonMaterialAnalysisError {
        Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(DesignTokens.negative)
      }

      if let analysis = runtime.moonMaterialAnalysis {
        configurationWarnings(analysis)
        sourceStatus(analysis)
        analysisGrid(analysis)
      } else if runtime.isRefreshingMoonMaterialAnalysis {
        Spacer()
        ProgressView("Loading Moon materials and market orders…")
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        Spacer()
        ContentUnavailableView(
          "No Moon purchase analysis yet",
          systemImage: "chart.xyaxis.line",
          description: Text(
            "Refresh to compare all Moon materials across the configured markets."
          )
        )
        Spacer()
      }
    }
    .padding(DesignTokens.spacingLG)
    .task(id: refreshContextID) {
      await refresh()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        Text("Moon material purchase analysis")
          .font(.largeTitle.bold())
          .foregroundStyle(DesignTokens.textPrimary)
        Text(
          "Compare the lowest sell price and the complete available quantity up to 10% above it."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Spacer(minLength: DesignTokens.spacingMD)
      Button {
        guard let analysis = runtime.moonMaterialAnalysis else { return }
        exportImage(analysis)
      } label: {
        if isExportingImage {
          ProgressView()
            .controlSize(.small)
        } else {
          Label("Export as image", systemImage: "photo.badge.arrow.down")
        }
      }
      .disabled(runtime.moonMaterialAnalysis == nil || isExportingImage)
      .accessibilityIdentifier("moon-material-analysis.export-image")
      Button {
        Task { await refresh() }
      } label: {
        if runtime.isRefreshingMoonMaterialAnalysis {
          ProgressView()
            .controlSize(.small)
        } else {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(runtime.isRefreshingMoonMaterialAnalysis)
      .accessibilityIdentifier("moon-material-analysis.refresh")
    }
  }

  private var explanation: some View {
    Panel(title: "Calculation basis") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text(
          "For each market, the first value is the current lowest valid sell-order price. The price in parentheses is exactly 10% higher. Availability is the sum of all remaining sell-order quantities at that location whose price is inside this range."
        )
        HStack(spacing: DesignTokens.spacingSM) {
          rankLegend(.cheapest)
          rankLegend(.secondCheapest)
          rankLegend(.thirdCheapest)
        }
        Text(
          "Only fresh markets with sell orders are ranked by their lowest price. Equal prices share the same rank."
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Text(
          "The active SDE group Moon Materials defines the item list. The selected Main, Home and Coalition Hubs plus additional comparison markets from Market Settings are compared. NPC stations use public station orders; Player Structures use their authenticated structure market. Missing access remains explicitly unavailable instead of becoming an empty market."
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Text(
          "ESI caches market orders for five minutes. Refreshes inside that window reuse the current result when the Profile and authorizations have not changed."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      .font(.callout)
    }
  }

  @ViewBuilder
  private func configurationWarnings(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> some View {
    if analysis.configuredHubs.contains(where: {
      $0.location.kind == .playerStructure
    })
      && !authorizationSnapshots.contains(where: {
        $0.scopes.contains(TradeHubMarketService.structureMarketScope)
      })
    {
      Label(
        "Reauthorize at least one character for Player Structure market orders.",
        systemImage: "person.badge.key.fill"
      )
      .foregroundStyle(DesignTokens.caution)
    }
    if analysis.configuredHubs.contains(where: {
      $0.location.kind == .legacy || $0.location.locationID == nil
    }) {
      Label(
        "At least one market location must be resolved in Market Settings.",
        systemImage: "building.2.crop.circle"
      )
      .foregroundStyle(DesignTokens.caution)
    }
  }

  private func sourceStatus(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> some View {
    let freshCount = analysis.configuredMarkets.values.filter {
      $0.state == .fresh
    }.count
    let staleCount = analysis.configuredMarkets.values.filter {
      $0.state == .stale
    }.count
    return HStack(spacing: DesignTokens.spacingMD) {
      Label(
        AppLocalization.format(
          "%lld Moon materials",
          Int64(analysis.materialCatalog.materials.count)
        ),
        systemImage: "circle.grid.3x3.fill"
      )
      Text(
        AppLocalization.format(
          "%lld of %lld markets fresh",
          Int64(freshCount),
          Int64(analysis.configuredHubs.count)
        )
      )
      if staleCount > 0 {
        Text(
          AppLocalization.format("%lld markets stale", Int64(staleCount))
        )
        .foregroundStyle(DesignTokens.caution)
      }
      Spacer()
      Text(
        AppLocalization.format(
          "Updated %@",
          analysis.refreshedAt.formatted(
            date: .abbreviated,
            time: .shortened
          )
        )
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
    .font(.caption)
  }

  private func analysisGrid(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> some View {
    ScrollView([.horizontal, .vertical]) {
      LazyVStack(spacing: 1) {
        gridHeader(analysis)
        ForEach(sortedMaterials(analysis)) { material in
          let ranks = MoonMaterialMarketPriceRankAnalyzer.ranks(
            typeID: material.id,
            markets: analysis.configuredMarkets
          )
          HStack(spacing: 1) {
            EVEEntityText(value: material.name)
              .frame(width: materialColumnWidth, alignment: .leading)
              .frame(minHeight: rowMinimumHeight, alignment: .leading)
              .padding(.horizontal, DesignTokens.spacingSM)
              .background(DesignTokens.panel)

            ForEach(analysis.configuredHubs) { hub in
              marketCell(
                material: material,
                hub: hub,
                sourced: analysis.configuredMarkets[hub.id],
                priceRank: ranks[hub.id]
              )
            }
          }
        }
      }
      .padding(1)
      .background(DesignTokens.border)
      .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }
  }

  private func gridHeader(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> some View {
    HStack(spacing: 1) {
      SortableTableHeader(
        title: "Moon material",
        column: MoonMaterialSortColumn.material,
        sort: $materialSort
      )
        .font(.caption.bold())
        .textCase(.uppercase)
        .tracking(0.8)
        .frame(width: materialColumnWidth, alignment: .leading)
        .frame(minHeight: 58, alignment: .leading)
        .padding(.horizontal, DesignTokens.spacingSM)
        .background(DesignTokens.elevated)

      ForEach(analysis.configuredHubs) { hub in
        VStack(spacing: DesignTokens.spacingXS) {
          SortableTableHeader(
            title: "Lowest price",
            column: MoonMaterialSortColumn.market(hub.id),
            sort: $materialSort
          )
          .font(.caption2.bold())
          ForEach(roleLabels(hub.roles), id: \.self) { role in
            Text(role)
              .font(.caption2.bold())
              .foregroundStyle(DesignTokens.highlight)
          }
          EVEEntityText(value: hub.location.name, lineLimit: 2)
          if hub.location.kind == .playerStructure {
            Text("Player structure")
              .font(.caption2)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .frame(width: marketColumnWidth, alignment: .center)
        .frame(minHeight: 58, alignment: .center)
        .padding(.horizontal, DesignTokens.spacingSM)
        .background(DesignTokens.elevated)
      }
    }
  }

  private func sortedMaterials(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> [MoonMaterial] {
    analysis.materialCatalog.materials.sorted { lhs, rhs in
      let ordered: Bool?
      switch materialSort.column {
      case .material:
        ordered = compareMaterialValues(lhs.name, rhs.name)
      case let .market(hubID):
        ordered = compareOptionalMaterialValues(
          lowestPrice(typeID: lhs.id, hubID: hubID, analysis: analysis),
          lowestPrice(typeID: rhs.id, hubID: hubID, analysis: analysis)
        )
      }
      return ordered ?? (lhs.id < rhs.id)
    }
  }

  private func lowestPrice(
    typeID: Int64,
    hubID: UUID,
    analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> Double? {
    guard let snapshot = analysis.configuredMarkets[hubID]?.value else {
      return nil
    }
    return MoonMaterialPriceBandAnalyzer.analyze(
      typeID: typeID,
      snapshot: snapshot
    )?.lowestSellPrice
  }

  private func compareMaterialValues<Value: Comparable>(
    _ lhs: Value,
    _ rhs: Value
  ) -> Bool? {
    guard lhs != rhs else { return nil }
    return materialSort.direction.orders(lhs, before: rhs)
  }

  private func compareOptionalMaterialValues<Value: Comparable>(
    _ lhs: Value?,
    _ rhs: Value?
  ) -> Bool? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?): return compareMaterialValues(lhs, rhs)
    case (nil, nil): return nil
    case (nil, _): return materialSort.direction == .descending
    case (_, nil): return materialSort.direction == .ascending
    }
  }

  @ViewBuilder
  private func marketCell(
    material: MoonMaterial,
    hub: MarketHubConfigurationSnapshot,
    sourced: Sourced<MarketOrderSnapshot>?,
    priceRank: MoonMaterialMarketPriceRank?
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      if let sourced, let snapshot = sourced.value {
        if let band = MoonMaterialPriceBandAnalyzer.analyze(
          typeID: material.id,
          snapshot: snapshot
        ) {
          Text(
            verbatim:
              "\(formatPrice(band.lowestSellPrice)) ISK (≤ \(formatPrice(band.maximumBandPrice)) ISK)"
          )
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(DesignTokens.textPrimary)
          Text(
            verbatim:
              "\(formatQuantity(band.availableQuantity)) \("units within +10%".localizedUI)"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          if let priceRank {
            rankBadge(priceRank)
          }
        } else {
          Text("No sell orders at this location")
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.textSecondary)
        }
        sourceBadge(sourced.state)
        if sourced.state != .fresh {
          Text(marketFailureLabel(sourced))
            .font(.caption2)
            .foregroundStyle(sourceStateColor(sourced.state))
        }
      } else {
        Text(marketFailureLabel(sourced))
          .font(.caption.weight(.semibold))
          .foregroundStyle(sourceStateColor(sourced?.state))
        Text("No market value was substituted")
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .frame(width: marketColumnWidth, alignment: .leading)
    .frame(minHeight: rowMinimumHeight, alignment: .leading)
    .padding(.horizontal, DesignTokens.spacingSM)
    .background(
      priceRank.map { rankColor($0).opacity(0.18) }
        ?? DesignTokens.panel
    )
    .overlay {
      if let priceRank {
        Rectangle()
          .stroke(rankColor(priceRank), lineWidth: 2)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(material.name), \(hub.location.name)"
    )
  }

  private func roleLabels(
    _ roles: Set<MarketHubRole>
  ) -> [String] {
    var labels: [String] = []
    if roles.contains(.main) {
      labels.append("Main Hub".localizedUI)
    }
    if roles.contains(.home) {
      labels.append("Home Hub".localizedUI)
    }
    if roles.contains(.coalition) {
      labels.append("Coalition Hub".localizedUI)
    }
    if roles.contains(.comparison) {
      labels.append("Comparison market".localizedUI)
    }
    return labels
  }

  private func marketFailureLabel(
    _ sourced: Sourced<MarketOrderSnapshot>?
  ) -> String {
    let diagnostics = sourced?.diagnostics ?? []
    if diagnostics.contains("esi.moon-market.structure-scope-missing") {
      return "Character reauthorization required".localizedUI
    }
    if diagnostics.contains(
      "esi.moon-market.structure-authorization-required"
    ) {
      return "Connect an authorized character".localizedUI
    }
    if diagnostics.contains("esi.moon-market.structure-access-forbidden") {
      return "Structure market is not accessible".localizedUI
    }
    if diagnostics.contains("esi.moon-market.structure-not-found") {
      return "Structure location is no longer valid".localizedUI
    }
    if diagnostics.contains("esi.moon-market.structure-token-unavailable") {
      return "Character authorization is unavailable".localizedUI
    }
    if diagnostics.contains("esi.moon-market.rate-limited") {
      return "ESI rate limit reached".localizedUI
    }
    return sourceStateLabel(sourced?.state)
  }

  private func refresh() async {
    await runtime.refreshMoonMaterialAnalysis(
      authorizations: authorizationSnapshots,
      clientID: clientID
    )
  }

  @MainActor
  private func exportImage(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) {
    guard !isExportingImage else { return }
    isExportingImage = true
    imageExportMessage = nil
    defer { isExportingImage = false }

    let exportedAt = Date()
    let content = MoonMaterialPurchaseAnalysisExportView(
      analysis: analysis,
      materials: sortedMaterials(analysis),
      exportedAt: exportedAt
    )
    .environment(\.locale, AppLocalization.currentLanguage.locale)
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else {
      imageExportMessage = "The table image could not be created.".localizedUI
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = MoonMaterialImageExportNaming.fileName(
      at: exportedAt
    )
    panel.title = "Export Moon material table as image".localizedUI

    guard panel.runModal() == .OK, let destination = panel.url else {
      imageExportMessage = "Image export cancelled.".localizedUI
      return
    }
    do {
      try png.write(to: destination, options: .atomic)
      imageExportMessage = AppLocalization.format(
        "Image saved as %@.",
        destination.lastPathComponent
      )
    } catch {
      imageExportMessage = "The image could not be saved.".localizedUI
    }
  }

  private var clientID: String {
    EVEConstants.ssoClientID
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    characters.compactMap {
      try? JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: $0.authorizationSnapshot
      )
    }
  }

  private var refreshContextID: String {
    let profile = runtime.productionBasis
    let locationIdentity = profile.tradingLocations.map {
      "\($0.id.uuidString):\($0.location.id):\($0.location.locationID ?? -1)"
    }.sorted().joined(separator: "|")
    let authorizationIdentity = authorizationSnapshots.map {
      "\($0.characterID):\($0.id.uuidString):\($0.authorizedAt.timeIntervalSince1970):\($0.scopes.contains(TradeHubMarketService.structureMarketScope))"
    }.sorted().joined(separator: "|")
    return [
      profile.mainTradingLocationID?.uuidString ?? "none",
      profile.homeTradingLocationID?.uuidString ?? "none",
      profile.coalitionTradingLocationID?.uuidString ?? "none",
      profile.comparisonTradingLocationIDs.map(\.uuidString).sorted()
        .joined(separator: ","),
      locationIdentity,
      authorizationIdentity,
      clientID,
    ].joined(separator: "#")
  }

  private func rankLegend(
    _ rank: MoonMaterialMarketPriceRank
  ) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Circle()
        .fill(rankColor(rank))
        .frame(width: 9, height: 9)
      Text(rankLabel(rank))
    }
    .font(.caption.bold())
  }

  private func rankBadge(
    _ rank: MoonMaterialMarketPriceRank
  ) -> some View {
    Text(rankLabel(rank))
      .font(.caption2.bold())
      .foregroundStyle(rankColor(rank))
  }

  private func rankLabel(_ rank: MoonMaterialMarketPriceRank) -> String {
    switch rank {
    case .cheapest: "Cheapest".localizedUI
    case .secondCheapest: "Second cheapest".localizedUI
    case .thirdCheapest: "Third cheapest".localizedUI
    }
  }

  private func rankColor(_ rank: MoonMaterialMarketPriceRank) -> Color {
    switch rank {
    case .cheapest: DesignTokens.positive
    case .secondCheapest: DesignTokens.caution
    case .thirdCheapest: DesignTokens.negative
    }
  }

  @ViewBuilder
  private func sourceBadge(_ state: DataFreshness) -> some View {
    if state != .fresh {
      Text(sourceStateLabel(state))
        .font(.caption2.bold())
        .foregroundStyle(sourceStateColor(state))
    }
  }

  private func sourceStateLabel(_ state: DataFreshness?) -> String {
    switch state {
    case .fresh: "Fresh".localizedUI
    case .partial: "Partial".localizedUI
    case .stale: "Stale".localizedUI
    case .forbidden: "Access forbidden".localizedUI
    case .unavailable: "Unavailable".localizedUI
    case nil: "Not loaded".localizedUI
    }
  }

  private func sourceStateColor(_ state: DataFreshness?) -> Color {
    switch state {
    case .fresh: DesignTokens.positive
    case .partial, .stale: DesignTokens.caution
    case .forbidden, .unavailable: DesignTokens.negative
    case nil: DesignTokens.textDisabled
    }
  }

  private func formatPrice(_ value: Double) -> String {
    numberFormatter(minimumFractionDigits: 2, maximumFractionDigits: 2)
      .string(from: NSNumber(value: value)) ?? "—"
  }

  private func formatQuantity(_ value: Int64) -> String {
    numberFormatter(minimumFractionDigits: 0, maximumFractionDigits: 0)
      .string(from: NSNumber(value: value)) ?? "—"
  }

  private func numberFormatter(
    minimumFractionDigits: Int,
    maximumFractionDigits: Int
  ) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.locale = AppLocalization.currentLanguage.locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter
  }
}

private enum MoonMaterialImageExportNaming {
  static func fileName(at date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return "Moon-Material-Kaufanalyse_\(formatter.string(from: date)).png"
  }
}

private struct MoonMaterialPurchaseAnalysisExportView: View {
  let analysis: MoonMaterialPurchaseAnalysisSnapshot
  let materials: [MoonMaterial]
  let exportedAt: Date

  private let materialColumnWidth: CGFloat = 230
  private let marketColumnWidth: CGFloat = 250
  private let rowHeight: CGFloat = 82
  private let contentPadding: CGFloat = 28

  private var contentWidth: CGFloat {
    materialColumnWidth
      + CGFloat(analysis.configuredHubs.count) * marketColumnWidth
      + contentPadding * 2
      + CGFloat(max(0, analysis.configuredHubs.count))
      + 2
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Moon material purchase analysis")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(DesignTokens.textPrimary)
        Text(exportTimestamp)
          .font(.system(size: 18, weight: .semibold).monospacedDigit())
          .foregroundStyle(DesignTokens.highlight)
        Text(
          "Lowest sell price, price limit +10% and complete quantity available within that range."
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      VStack(spacing: 1) {
        tableHeader
        ForEach(materials) { material in
          tableRow(material)
        }
      }
      .padding(1)
      .background(DesignTokens.border)

      Text(
        AppLocalization.format(
          "Market data updated %@",
          analysis.refreshedAt.formatted(
            date: .abbreviated,
            time: .standard
          )
        )
      )
      .font(.caption.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
    }
    .padding(contentPadding)
    .frame(width: contentWidth, alignment: .leading)
    .background(DesignTokens.canvas)
    .fixedSize(horizontal: true, vertical: true)
  }

  private var exportTimestamp: String {
    exportedAt.formatted(
      Date.FormatStyle(date: .long, time: .standard)
        .locale(AppLocalization.currentLanguage.locale)
    )
  }

  private var tableHeader: some View {
    HStack(spacing: 1) {
      Text("Moon material")
        .font(.caption.bold())
        .textCase(.uppercase)
        .tracking(0.8)
        .padding(.horizontal, 10)
        .frame(width: materialColumnWidth, alignment: .leading)
        .frame(height: 78, alignment: .leading)
        .background(DesignTokens.elevated)

      ForEach(analysis.configuredHubs) { hub in
        VStack(spacing: 4) {
          Text(roleText(hub.roles))
            .font(.caption2.bold())
            .foregroundStyle(DesignTokens.highlight)
          EVEEntityText(value: hub.location.name)
            .multilineTextAlignment(.center)
            .lineLimit(2)
          if hub.location.kind == .playerStructure {
            Text("Player structure")
              .font(.caption2)
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .padding(.horizontal, 10)
        .frame(width: marketColumnWidth)
        .frame(height: 78)
        .background(DesignTokens.elevated)
      }
    }
  }

  private func tableRow(_ material: MoonMaterial) -> some View {
    let ranks = MoonMaterialMarketPriceRankAnalyzer.ranks(
      typeID: material.id,
      markets: analysis.configuredMarkets
    )
    return HStack(spacing: 1) {
      EVEEntityText(value: material.name)
        .padding(.horizontal, 10)
        .frame(width: materialColumnWidth, alignment: .leading)
        .frame(height: rowHeight, alignment: .leading)
        .background(DesignTokens.panel)

      ForEach(analysis.configuredHubs) { hub in
        exportMarketCell(
          material: material,
          sourced: analysis.configuredMarkets[hub.id],
          rank: ranks[hub.id]
        )
      }
    }
  }

  private func exportMarketCell(
    material: MoonMaterial,
    sourced: Sourced<MarketOrderSnapshot>?,
    rank: MoonMaterialMarketPriceRank?
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let sourced, let snapshot = sourced.value,
        let band = MoonMaterialPriceBandAnalyzer.analyze(
          typeID: material.id,
          snapshot: snapshot
        )
      {
        Text(
          verbatim:
            "\(formatPrice(band.lowestSellPrice)) ISK (≤ \(formatPrice(band.maximumBandPrice)) ISK)"
        )
        .font(.caption.monospacedDigit().weight(.semibold))
        Text(
          verbatim:
            "\(formatQuantity(band.availableQuantity)) \("units within +10%".localizedUI)"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        if let rank {
          Text(rankLabel(rank))
            .font(.caption2.bold())
            .foregroundStyle(rankColor(rank))
        }
        if sourced.state != .fresh {
          Text(sourceStateLabel(sourced.state))
            .font(.caption2.bold())
            .foregroundStyle(sourceStateColor(sourced.state))
        }
      } else if let sourced, sourced.value != nil {
        Text("No sell orders at this location")
          .font(.caption.weight(.semibold))
          .foregroundStyle(DesignTokens.textSecondary)
        if sourced.state != .fresh {
          Text(sourceStateLabel(sourced.state))
            .font(.caption2.bold())
            .foregroundStyle(sourceStateColor(sourced.state))
        }
      } else {
        Text(sourceStateLabel(sourced?.state))
          .font(.caption.weight(.semibold))
          .foregroundStyle(sourceStateColor(sourced?.state))
        Text("No market value was substituted")
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .foregroundStyle(DesignTokens.textPrimary)
    .padding(.horizontal, 10)
    .frame(width: marketColumnWidth, alignment: .leading)
    .frame(height: rowHeight, alignment: .leading)
    .background(rank.map { rankColor($0).opacity(0.18) } ?? DesignTokens.panel)
    .overlay {
      if let rank {
        Rectangle().stroke(rankColor(rank), lineWidth: 2)
      }
    }
  }

  private func roleText(_ roles: Set<MarketHubRole>) -> String {
    var labels: [String] = []
    if roles.contains(.main) { labels.append("Main Hub".localizedUI) }
    if roles.contains(.home) { labels.append("Home Hub".localizedUI) }
    if roles.contains(.coalition) {
      labels.append("Coalition Hub".localizedUI)
    }
    if roles.contains(.comparison) {
      labels.append("Comparison market".localizedUI)
    }
    return labels.joined(separator: " · ")
  }

  private func rankLabel(_ rank: MoonMaterialMarketPriceRank) -> String {
    switch rank {
    case .cheapest: "Cheapest".localizedUI
    case .secondCheapest: "Second cheapest".localizedUI
    case .thirdCheapest: "Third cheapest".localizedUI
    }
  }

  private func rankColor(_ rank: MoonMaterialMarketPriceRank) -> Color {
    switch rank {
    case .cheapest: DesignTokens.positive
    case .secondCheapest: DesignTokens.caution
    case .thirdCheapest: DesignTokens.negative
    }
  }

  private func sourceStateLabel(_ state: DataFreshness?) -> String {
    switch state {
    case .fresh: "Fresh".localizedUI
    case .partial: "Partial".localizedUI
    case .stale: "Stale".localizedUI
    case .forbidden: "Access forbidden".localizedUI
    case .unavailable: "Unavailable".localizedUI
    case nil: "Not loaded".localizedUI
    }
  }

  private func sourceStateColor(_ state: DataFreshness?) -> Color {
    switch state {
    case .fresh: DesignTokens.positive
    case .partial, .stale: DesignTokens.caution
    case .forbidden, .unavailable: DesignTokens.negative
    case nil: DesignTokens.textDisabled
    }
  }

  private func formatPrice(_ value: Double) -> String {
    numberFormatter(minimum: 2, maximum: 2)
      .string(from: NSNumber(value: value)) ?? "—"
  }

  private func formatQuantity(_ value: Int64) -> String {
    numberFormatter(minimum: 0, maximum: 0)
      .string(from: NSNumber(value: value)) ?? "—"
  }

  private func numberFormatter(
    minimum: Int,
    maximum: Int
  ) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.locale = AppLocalization.currentLanguage.locale
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = minimum
    formatter.maximumFractionDigits = maximum
    return formatter
  }
}

private enum MoonMaterialSortColumn: Hashable {
  case material
  case market(UUID)
}
