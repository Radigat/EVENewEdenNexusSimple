import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

/// New parser messages fail here until both languages translate them.
struct ProductionInputErrorLocalizationTests {
  @Test
  func everyParserMessageIsTranslatedInBothLanguages() throws {
    for language in AppLanguage.allCases {
      let path = try #require(
        AppLocalization.resourceBundle.path(forResource: language.rawValue, ofType: "lproj")
      )
      let bundle = try #require(Bundle(path: path))
      for reason in ProductionInputErrorReason.allCases {
        let missing = "\u{0}missing"
        let text = bundle.localizedString(forKey: reason.format, value: missing, table: nil)
        #expect(text != missing, "\(language.rawValue): \(reason.format)")
        #expect(
          text.components(separatedBy: "%@").count - 1 == reason.arguments.count,
          "\(language.rawValue): \(reason.format)"
        )
      }
    }
  }

  @Test
  func germanMessagesUseGermanTextAndNumbers() {
    for reason in ProductionInputErrorReason.allCases {
      let german = reason.localized(in: .german)
      #expect(german != reason.localized(in: .english), "\(reason)")
      #expect(!german.contains("%"), "\(reason)")
    }
    #expect(
      ProductionInputErrorReason.wantTooLarge.localized(in: .german)
        == "Der Bedarf darf höchstens 1.000.000.000 betragen."
    )
    #expect(
      ProductionInputErrorReason.wantTooLarge.localized(in: .english)
        == "Want must not exceed 1,000,000,000."
    )
  }

  @Test
  func inputErrorPanelLineReadsGerman() throws {
    let error = try #require(ProductionInputParser.parse("").errors.first)
    let line = String(
      format: AppLanguage.german.localized("Line %lld: %@"),
      locale: AppLanguage.german.locale,
      Int64(error.lineNumber),
      error.reason.localized(in: .german)
    )

    #expect(line == "Zeile 1: Gib mindestens einen Produktionsauftrag ein.")
  }
}
