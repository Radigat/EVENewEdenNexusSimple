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

enum AppTextSize: String, CaseIterable, Identifiable {
  case compact
  case standard
  case large
  case extraLarge
  case accessibility

  static let storageKey = "app.appearance.text-size"

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .compact: "Compact"
    case .standard: "Standard"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    case .accessibility: "Accessibility"
    }
  }

  var dynamicTypeSize: DynamicTypeSize {
    switch self {
    case .compact: .small
    case .standard: .large
    case .large: .xLarge
    case .extraLarge: .xxLarge
    case .accessibility: .accessibility1
    }
  }

  var smaller: AppTextSize {
    guard let index = Self.allCases.firstIndex(of: self), index > 0 else {
      return self
    }
    return Self.allCases[index - 1]
  }

  var larger: AppTextSize {
    guard let index = Self.allCases.firstIndex(of: self),
      index < Self.allCases.index(before: Self.allCases.endIndex)
    else {
      return self
    }
    return Self.allCases[index + 1]
  }
}

enum AppAppearanceStyle: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  static let storageKey = "app.appearance.color-scheme"

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var preferredColorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

struct TextSizeCommands: Commands {
  @AppStorage(AppTextSize.storageKey, store: AppDefaults.store)
  private var storedTextSize = AppTextSize.standard.rawValue

  private var textSize: AppTextSize {
    AppTextSize(rawValue: storedTextSize) ?? .standard
  }

  var body: some Commands {
    CommandMenu("Text Size") {
      Button("Increase Text Size") {
        storedTextSize = textSize.larger.rawValue
      }
      .keyboardShortcut("+", modifiers: .command)
      .disabled(textSize == .accessibility)

      Button("Decrease Text Size") {
        storedTextSize = textSize.smaller.rawValue
      }
      .keyboardShortcut("-", modifiers: .command)
      .disabled(textSize == .compact)

      Divider()

      Button("Reset Text Size") {
        storedTextSize = AppTextSize.standard.rawValue
      }
      .keyboardShortcut("0", modifiers: .command)
      .disabled(textSize == .standard)
    }
  }
}

enum AppLocalization {
  static var currentLanguage: AppLanguage {
    guard
      let stored = AppDefaults.store.string(
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
