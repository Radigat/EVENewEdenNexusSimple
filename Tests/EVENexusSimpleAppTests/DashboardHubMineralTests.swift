import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Dashboard tile "Minerals at the Home Hub" (owner decisions 25.11.2026).
@MainActor
struct DashboardHubMineralTests {
  private let english = Locale(identifier: AppLanguage.english.rawValue)
  private let german = Locale(identifier: AppLanguage.german.rawValue)

  private func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\u{202F}", with: " ")
      .replacingOccurrences(of: "\u{2212}", with: "-")
  }

  @Test
  func pricesUseTwoDecimalsBelowOneThousandAndWholeISKAbove() {
    #expect(DashboardHubMineralText.price(3.78, locale: english) == "3.78")
    #expect(DashboardHubMineralText.price(3.78, locale: german) == "3,78")
    #expect(DashboardHubMineralText.price(779.9, locale: english) == "779.90")
    #expect(DashboardHubMineralText.price(1_152.4, locale: english) == "1,152")
    #expect(DashboardHubMineralText.price(17_330, locale: german) == "17.330")
  }

  @Test
  func deviationHasOneDecimalASignAndNoSignForZero() {
    #expect(normalized(DashboardHubMineralText.deviation(-6.7, locale: english)) == "-6.7%")
    #expect(normalized(DashboardHubMineralText.deviation(33.7, locale: english)) == "+33.7%")
    #expect(normalized(DashboardHubMineralText.deviation(-6.7, locale: german)) == "-6,7 %")
    #expect(normalized(DashboardHubMineralText.deviation(0, locale: english)) == "0.0%")
    #expect(DashboardHubMineralText.deviation(nil, locale: english) == "—")
  }

  @Test
  func everyTileTextHasAGermanTranslation() {
    let keys = [
      "Minerals at the Home Hub",
      "Home Hub against Main Hub",
      "Home vs. Main",
      "No offer",
      "Home Hub market: %@",
      "Main Hub market: %@",
      "No Home Hub and no Main Hub are configured.",
      "No Home Hub is configured.",
      "No Main Hub is configured.",
      "Home Hub and Main Hub are the same location; there is nothing to compare.",
      "Prices at the 10% limit (1.10 × lowest sell order), ISK per unit. Green: cheaper at the Home Hub than at the Main Hub, before hauling.",
    ]
    for key in keys {
      #expect(AppLanguage.german.localized(key) != key || key == "Home vs. Main", "\(key)")
      #expect(AppLanguage.english.localized(key) == key, "\(key)")
    }
    #expect(AppLanguage.german.localized("Minerals at the Home Hub") == "Mineralien am Home Hub")
    #expect(AppLanguage.german.localized("Home vs. Main") == "Home vs. Main")
  }

  @Test
  func missingHubsAndMarketStatesAreNamed() {
    #expect(
      DashboardHubMineralText.missingHubs(home: true, main: false, language: .german)
        == "Kein Home Hub gewählt."
    )
    #expect(
      DashboardHubMineralText.missingHubs(home: false, main: true, language: .german)
        == "Kein Main Hub gewählt."
    )
    #expect(
      DashboardHubMineralText.missingHubs(home: true, main: true, language: .english)
        == "No Home Hub and no Main Hub are configured."
    )
    #expect(DashboardHubMineralText.marketState(.stale, language: .german) == "Veraltet")
    #expect(DashboardHubMineralText.marketState(nil, language: .german) == "Nicht geladen")
    #expect(
      DashboardHubMineralText.marketState(.forbidden, language: .english) == "Access forbidden"
    )
  }

  @Test
  func marketSettingsLinkCarriesTheSettingsPage() {
    let request = DashboardNavigationRequest(
      section: .data,
      dataSettingsSection: .marketSettings
    )
    #expect(request.section == .data)
    #expect(request.dataSettingsSection == .marketSettings)
    #expect(DashboardNavigationRequest(section: .mineralPurchaseAnalysis).dataSettingsSection == nil)
  }
}
