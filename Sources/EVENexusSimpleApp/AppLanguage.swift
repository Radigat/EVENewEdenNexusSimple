import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
  case german = "de"
  case english = "en"

  static let storageKey = "app.interface-language"

  static var defaultLanguage: AppLanguage {
    Locale.preferredLanguages.first?.hasPrefix("de") == true
      ? .german
      : .english
  }

  var id: Self { self }

  var locale: Locale {
    Locale(identifier: rawValue)
  }

  var title: LocalizedStringKey {
    switch self {
    case .german: "Deutsch"
    case .english: "English"
    }
  }

  func localized(_ key: String) -> String {
    guard
      let path = AppLocalization.resourceBundle.path(
        forResource: rawValue,
        ofType: "lproj"
      ),
      let languageBundle = Bundle(path: path)
    else {
      return key
    }
    return languageBundle.localizedString(
      forKey: key,
      value: key,
      table: nil
    )
  }
}

enum AppLocalization {
  static var currentLanguage: AppLanguage {
    guard
      let stored = UserDefaults.standard.string(
        forKey: AppLanguage.storageKey
      ),
      let language = AppLanguage(rawValue: stored)
    else {
      return AppLanguage.defaultLanguage
    }
    return language
  }

  static func text(_ key: String) -> String {
    currentLanguage.localized(key)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: text(key),
      locale: currentLanguage.locale,
      arguments: arguments
    )
  }

  #if SWIFT_PACKAGE
    static let resourceBundle = Bundle.module
  #else
    static let resourceBundle = Bundle.main
  #endif
}

extension String {
  var localizedUI: String {
    AppLocalization.text(self)
  }
}
