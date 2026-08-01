import EVENexusCore
import SwiftUI

struct MoonMaterialPurchaseAnalysisView: View {
  @EnvironmentObject private var runtime: RuntimeState

  private let materialColumnWidth: CGFloat = 190
  private let marketColumnWidth: CGFloat = 190
  private let rowMinimumHeight: CGFloat = 72

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
      header
      explanation

      if let error = runtime.moonMaterialAnalysisError {
        Label(error.localizedUI, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(DesignTokens.negative)
      }

      if let analysis = runtime.moonMaterialAnalysis {
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
    .task {
      guard runtime.moonMaterialAnalysis == nil else { return }
      await runtime.refreshMoonMaterialAnalysis()
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
        Task { await runtime.refreshMoonMaterialAnalysis() }
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
          "The active SDE group Moon Materials defines the item list. UALX-3 and C-J6MT use the matching player structure configured in Profile when available, otherwise the known location ID. A location without matching public sell orders stays explicitly empty. If a player structure was replaced, update its ID in Profile."
        )
        .foregroundStyle(DesignTokens.textSecondary)
      }
      .font(.callout)
    }
  }

  private func sourceStatus(
    _ analysis: MoonMaterialPurchaseAnalysisSnapshot
  ) -> some View {
    let freshCount = analysis.markets.values.filter {
      $0.state == .fresh
    }.count
    let staleCount = analysis.markets.values.filter {
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
          Int64(MoonMaterialMarketLocation.allCases.count)
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
          "SDE build %@ · refreshed %@",
          analysis.materialCatalog.source.version,
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
        gridHeader
        ForEach(analysis.materialCatalog.materials) { material in
          let ranks = MoonMaterialMarketPriceRankAnalyzer.ranks(
            typeID: material.id,
            markets: analysis.markets
          )
          HStack(spacing: 1) {
            Text(verbatim: material.name)
              .font(.callout.weight(.semibold))
              .foregroundStyle(DesignTokens.textPrimary)
              .frame(width: materialColumnWidth, alignment: .leading)
              .frame(minHeight: rowMinimumHeight, alignment: .leading)
              .padding(.horizontal, DesignTokens.spacingSM)
              .background(DesignTokens.panel)

            ForEach(MoonMaterialMarketLocation.allCases) { location in
              marketCell(
                material: material,
                location: location,
                sourced: analysis.markets[location],
                priceRank: ranks[location]
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

  private var gridHeader: some View {
    HStack(spacing: 1) {
      Text("Moon material")
        .font(.caption.bold())
        .textCase(.uppercase)
        .tracking(0.8)
        .frame(width: materialColumnWidth, alignment: .leading)
        .frame(minHeight: 58, alignment: .leading)
        .padding(.horizontal, DesignTokens.spacingSM)
        .background(DesignTokens.elevated)

      ForEach(MoonMaterialMarketLocation.allCases) { location in
        VStack(spacing: DesignTokens.spacingXS) {
          if location == .ualx3 {
            Text("Main Hub")
              .font(.caption2.bold())
              .foregroundStyle(DesignTokens.highlight)
          }
          Text(verbatim: location.shortName)
            .font(.caption.bold())
          if location.isPlayerStructure {
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

  @ViewBuilder
  private func marketCell(
    material: MoonMaterial,
    location: MoonMaterialMarketLocation,
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
      } else {
        Text(sourceStateLabel(sourced?.state))
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
      "\(material.name), \(location.shortName)"
    )
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
