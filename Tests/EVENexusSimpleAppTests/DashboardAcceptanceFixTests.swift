import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB7 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`: fixes for the
/// findings of the acceptance review DB6 that can be checked without a UI.
@MainActor
struct DashboardAcceptanceFixTests {
  private let base = Date(timeIntervalSince1970: 1_793_556_000)

  private func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\u{202F}", with: " ")
  }

  // MARK: B3 – analysis errors are translated

  /// Every literal analysis error in `RuntimeState` needs a German text, so a
  /// new message cannot appear in English inside the German interface.
  @Test
  func everyLiteralAnalysisErrorHasAGermanText() throws {
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/EVENexusSimpleApp/RuntimeState.swift")
    let text = try String(contentsOf: source, encoding: .utf8)
    let pattern = try NSRegularExpression(
      pattern: #"(?:Analysis|Purchase|Material)\w*Error\s*=\s*"((?:[^"\\]|\\.)*)""#
    )
    let range = NSRange(text.startIndex..., in: text)
    let messages = pattern.matches(in: text, range: range).compactMap { match in
      Range(match.range(at: 1), in: text).map { String(text[$0]) }
    }
    .filter { !$0.contains("\\(") }
    #expect(messages.count >= 6)
    #expect(messages.contains("No active SDE catalog is installed. Install or activate static data first."))
    for message in Set(messages) {
      #expect(AppLanguage.german.localized(message) != message, "\(message)")
      #expect(AppLanguage.english.localized(message) == message, "\(message)")
    }
  }

  // MARK: B4 – wallet refresh errors

  @Test
  func walletRefreshUsesTheLocalizedConnectionText() {
    let message = DashboardWalletRefreshMessage.text(
      characterName: "Pilot A",
      error: AuthError.noStoredAuthorization
    )
    #expect(
      message
        == "Pilot A: \(EVEConnectionErrorText.message(for: AuthError.noStoredAuthorization))"
    )
    #expect(!message.contains("noStoredAuthorization"))
  }

  @Test
  func localWalletFailuresNameTheLocalUpdate() {
    let message = DashboardWalletRefreshMessage.text(
      characterName: "Pilot A",
      error: CocoaError(.fileWriteUnknown)
    )
    #expect(
      message
        == "Pilot A: \(AppLocalization.text("The wallet balance could not be updated locally."))"
    )
    #expect(
      AppLanguage.german.localized("The wallet balance could not be updated locally.")
        == "Der Wallet-Stand konnte lokal nicht aktualisiert werden."
    )
    #expect(
      AppLanguage.german.localized("Refresh %@'s wallet") == "Wallet von %@ aktualisieren"
    )
  }

  // MARK: B5 – formats follow the app language

  @Test
  func iskFollowsTheGivenAppLanguage() {
    let english = Locale(identifier: AppLanguage.english.rawValue)
    let german = Locale(identifier: AppLanguage.german.rawValue)
    #expect(normalized(NetWorthValueFormat.isk(2_097_354_121, locale: english)) == "ISK 2,097,354,121")
    #expect(normalized(NetWorthValueFormat.isk(2_097_354_121, locale: german)) == "2.097.354.121 ISK")
    #expect(normalized(NetWorthValueFormat.signedISK(-1_500, locale: german)) == "−1.500 ISK")
  }

  @Test
  func headerTimesFollowTheGivenAppLanguage() throws {
    let afternoon = try #require(
      Calendar.current.date(bySettingHour: 15, minute: 5, second: 0, of: Date())
    )
    let english = DashboardHeaderStatusButton.timeText(
      afternoon, locale: Locale(identifier: AppLanguage.english.rawValue)
    )
    let german = DashboardHeaderStatusButton.timeText(
      afternoon, locale: Locale(identifier: AppLanguage.german.rawValue)
    )
    #expect(normalized(english) == "3:05 PM")
    #expect(german == "15:05")
  }

  // MARK: B6 – a series without values is explicit

  @Test
  func seriesWithoutValuesHasNoChartSamples() {
    let history = (0..<3).map { day in
      DashboardWealthSnapshot(
        capturedAt: base.addingTimeInterval(Double(day) * 86_400),
        valuationPolicy: "fixture",
        characters: [],
        knownTotalValue: 100 + Double(day),
        walletTotal: 100 + Double(day),
        isComplete: true,
        freshness: .fresh,
        priceSource: SourceIdentity(provider: "Fixture", version: "1")
      )
    }
    #expect(DashboardWealthSeries.assets.samples(in: history).isEmpty)
    #expect(DashboardWealthSeries.industryInProgress.samples(in: history).isEmpty)
    #expect(DashboardWealthSeries.wallet.samples(in: history).map(\.value) == [100, 101, 102])
    #expect(DashboardWealthSeries.total.samples(in: history).count == 3)
    #expect(AppLanguage.german.localized(DashboardWealthSeries.total.titleKey) == "Gesamt")
    #expect(
      AppLanguage.german.localized(DashboardWealthSeries.industryInProgress.titleKey)
        == "In Produktion"
    )
    #expect(
      AppLanguage.german.localized("No values for “%@” in the selected range.")
        == "Keine Werte für „%@“ im gewählten Zeitraum."
    )
  }

  // MARK: B7 – purchase panels without an analysis

  @Test
  func purchasePanelSeparatesNoAnalysisFromChangedSettings() {
    #expect(DashboardPurchasePanelState.state(hasAnalysis: false, isCurrent: false) == .noAnalysis)
    #expect(DashboardPurchasePanelState.state(hasAnalysis: true, isCurrent: false) == .settingsChanged)
    #expect(DashboardPurchasePanelState.state(hasAnalysis: true, isCurrent: true) == .current)
  }

  // MARK: B8, B9 – labels and terms

  @Test
  func purchaseRefreshAndScienceSlotsUseOneGermanTerm() {
    #expect(AppLanguage.german.localized("Refresh purchase analysis") == "Kaufanalyse aktualisieren")
    // DB8: the card title is short like „Fertigungs-Slots“; the activity grid
    // keeps „Gemeinsame Wissenschafts-Slots“.
    #expect(AppLanguage.german.localized("Science slots (shared)") == "Wissenschafts-Slots")
    #expect(AppLanguage.german.localized("Manufacturing slots") == "Fertigungs-Slots")
    #expect(AppLanguage.german.localized("Shared science slots") == "Gemeinsame Wissenschafts-Slots")
  }
}
