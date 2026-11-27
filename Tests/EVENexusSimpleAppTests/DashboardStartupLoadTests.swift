import AppKit
import Foundation
import Observation
import SwiftUI
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Main-thread load of the Dashboard after app start
/// (`Documentation/GESCHWINDIGKEIT_2026-11-13.md`, 27.11.2026).
@MainActor
struct DashboardStartupLoadTests {
  /// After every update the detail column asks the scroll content for its
  /// minimum size with width 0. The card rows no longer measure their cards
  /// for it; measurements at the real width and the window's minimum size
  /// stay as they were.
  @Test
  func cardRowsAreNotMeasuredForTheZeroWidthMinimumSize() {
    let log = CardMeasurementLog()
    let model = CardTick()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: MinimumSizeFixture(model: model, log: log)
    )
    defer { window.close() }
    pump(window)
    log.widths.removeAll()

    for tick in 1...5 {
      model.value = tick
      pump(window)
    }

    #expect(!log.widths.isEmpty)
    #expect(log.widths.allSatisfy { ($0 ?? 0) > 0 })
    // The fixed 500 pt element plus the 24 pt padding on both sides decide
    // the detail's minimum width, as before: card rows report width 0.
    // Checked from macOS 26 on only: under macOS 15 (CI) this never shown
    // window sometimes keeps a minimum width of 0, even after waiting 10 s
    // (CI runs 46040711150 and 46045344012, 27.11.2026); macOS 27 always
    // takes it over (owner decision 27.11.2026).
    if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
      #expect(window.contentMinSize.width >= 548)
    }
  }

  @Test
  func walletPortfolioCacheMatchesADirectBuildAndFollowsChanges() throws {
    let cache = DashboardWalletPortfolioCache()
    let synced = Date(timeIntervalSince1970: 1_790_000_000)
    let inputs = [
      DashboardWalletPortfolioCache.Input(
        characterID: 2,
        characterName: "Zeta Fixture",
        wallet: try wallet(1_250.5, at: synced),
        walletLastSyncAt: synced
      ),
      DashboardWalletPortfolioCache.Input(
        characterID: 1,
        characterName: "alpha Fixture",
        wallet: nil,
        walletLastSyncAt: nil
      ),
    ]
    let first = cache.portfolio(inputs)
    let direct = WalletPortfolioSnapshot(
      balances: inputs.map {
        CharacterWalletBalance(
          character: CharacterIdentity(id: $0.characterID, name: $0.characterName),
          balance: DashboardWealthRawInput.walletBalance(
            $0.wallet,
            walletLastSyncAt: $0.walletLastSyncAt
          )
        )
      }
    )
    #expect(summary(first) == summary(direct))
    // A missing wallet stays unavailable and is not counted as zero.
    #expect(first.balances.map(\.id) == [1, 2])
    #expect(first.balances.first?.balance.value == nil)
    #expect(first.includedCharacterCount == 1)
    #expect(first.totalBalance == 1_250.5)

    #expect(summary(cache.portfolio(inputs)) == summary(first))

    var changed = inputs
    changed[1] = DashboardWalletPortfolioCache.Input(
      characterID: 1,
      characterName: "alpha Fixture",
      wallet: try wallet(10, at: synced),
      walletLastSyncAt: synced
    )
    let updated = cache.portfolio(changed)
    #expect(updated.includedCharacterCount == 2)
    #expect(updated.totalBalance == 1_260.5)
  }

  private func wallet(_ value: Double, at date: Date) throws -> Data {
    try JSONEncoder().encode(
      Sourced(
        state: .fresh,
        value: value,
        source: SourceIdentity(provider: "ESI", version: "fixture", capturedAt: date)
      )
    )
  }

  private func summary(_ portfolio: WalletPortfolioSnapshot) -> [String] {
    portfolio.balances.map {
      "\($0.id):\($0.character.name):\($0.balance.state):\($0.balance.value.map { String($0) } ?? "nil")"
    } + [
      "total:\(portfolio.totalBalance)",
      "included:\(portfolio.includedCharacterCount)",
      "freshness:\(portfolio.freshness)",
    ]
  }

  private func pump(_ window: NSWindow) {
    for _ in 0..<3 {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      window.updateConstraintsIfNeeded()
      window.layoutIfNeeded()
    }
  }
}

private final class CardMeasurementLog: @unchecked Sendable {
  var widths: [CGFloat?] = []
}

@MainActor
@Observable
private final class CardTick {
  var value = 0
}

/// Counts how often and at which width a card is measured.
private struct MeasuredCard: Layout {
  let log: CardMeasurementLog

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    log.widths.append(proposal.width)
    let width = proposal.width ?? 300
    let height = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }.reduce(0, +)
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for subview in subviews {
      let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
      subview.place(
        at: CGPoint(x: bounds.minX, y: y),
        proposal: ProposedViewSize(width: bounds.width, height: height)
      )
      y += height
    }
  }
}

/// Main window structure of the Dashboard: split view, scroll view, padded
/// page and a row of two cards.
private struct MinimumSizeFixture: View {
  let model: CardTick
  let log: CardMeasurementLog

  var body: some View {
    NavigationSplitView {
      List { Text(verbatim: "Sidebar") }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          HStack {
            Text(verbatim: "Header")
            Color.clear.frame(width: 500, height: 1)
          }
          DashboardCardLayout(
            weights: [1, 1],
            minimumWidths: [360, 360],
            equalizesHeights: true
          ) {
            card
            card
          }
        }
        .frame(maxWidth: 1_440, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(DesignTokens.spacingLG)
      }
    }
  }

  private var card: some View {
    MeasuredCard(log: log) {
      Text(verbatim: "Tick \(model.value)")
      ForEach(0..<6, id: \.self) { row in
        Text(verbatim: "Row \(row) with a longer text that may wrap")
      }
    }
  }
}
