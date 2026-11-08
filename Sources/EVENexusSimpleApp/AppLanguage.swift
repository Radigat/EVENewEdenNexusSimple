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

  /// Factor on the macOS text-style point sizes. macOS ignores
  /// `dynamicTypeSize` for SwiftUI text styles (measured 07.11.2026 on
  /// macOS 27.2: every size rendered identically), so the app scales the
  /// point size itself through `AppFont`.
  var scale: CGFloat {
    switch self {
    case .compact: 0.9
    case .standard: 1
    case .large: 1.15
    case .extraLarge: 1.3
    case .accessibility: 1.5
    }
  }

  /// Native controls (bordered buttons, segmented and menu pickers) keep
  /// their AppKit font whatever `.font` says and grow only with the control
  /// size (measured 07.11.2026).
  var controlSize: ControlSize {
    switch self {
    case .compact: .small
    case .standard: .regular
    case .large, .extraLarge: .large
    case .accessibility: .extraLarge
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

private struct AppTextSizeKey: EnvironmentKey {
  static let defaultValue = AppTextSize.standard
}

extension EnvironmentValues {
  /// The text size of the current window, set once at the scene root.
  var appTextSize: AppTextSize {
    get { self[AppTextSizeKey.self] }
    set { self[AppTextSizeKey.self] = newValue }
  }
}

/// A font that follows the text-size setting. It mirrors the SwiftUI text
/// styles and font modifiers the app uses; `.appFont(_:)` resolves it
/// against `\.appTextSize`. At `.standard` a text style resolves to exactly
/// the SwiftUI text style, so the default look stays unchanged.
struct AppFont: Equatable {
  enum Base: Equatable {
    case textStyle(Font.TextStyle)
    case system(size: CGFloat, weight: Font.Weight?, design: Font.Design?)
  }

  enum Modifier: Equatable {
    case bold
    case weight(Font.Weight)
    case monospacedDigit
    case monospaced
    case italic
  }

  let base: Base
  private(set) var modifiers: [Modifier] = []

  init(_ base: Base) {
    self.base = base
  }

  static var largeTitle: AppFont { AppFont(.textStyle(.largeTitle)) }
  static var title: AppFont { AppFont(.textStyle(.title)) }
  static var title2: AppFont { AppFont(.textStyle(.title2)) }
  static var title3: AppFont { AppFont(.textStyle(.title3)) }
  static var headline: AppFont { AppFont(.textStyle(.headline)) }
  static var subheadline: AppFont { AppFont(.textStyle(.subheadline)) }
  static var body: AppFont { AppFont(.textStyle(.body)) }
  static var callout: AppFont { AppFont(.textStyle(.callout)) }
  static var footnote: AppFont { AppFont(.textStyle(.footnote)) }
  static var caption: AppFont { AppFont(.textStyle(.caption)) }
  static var caption2: AppFont { AppFont(.textStyle(.caption2)) }

  /// A fixed point size at standard text size; scales like the text styles.
  static func system(
    size: CGFloat,
    weight: Font.Weight? = nil,
    design: Font.Design? = nil
  ) -> AppFont {
    AppFont(.system(size: size, weight: weight, design: design))
  }

  func bold() -> AppFont { adding(.bold) }
  func weight(_ weight: Font.Weight) -> AppFont { adding(.weight(weight)) }
  func monospacedDigit() -> AppFont { adding(.monospacedDigit) }
  func monospaced() -> AppFont { adding(.monospaced) }
  func italic() -> AppFont { adding(.italic) }

  func font(for textSize: AppTextSize) -> Font {
    let font: Font
    switch base {
    case .textStyle(let style):
      font =
        textSize == .standard
        ? .system(style)
        : Self.scaledSystemFont(for: style, scale: textSize.scale)
    case .system(let size, let weight, let design):
      font = .system(
        size: size * textSize.scale,
        weight: weight,
        design: design
      )
    }
    return modifiers.reduce(font) { font, modifier in
      switch modifier {
      case .bold: font.bold()
      case .weight(let weight): font.weight(weight)
      case .monospacedDigit: font.monospacedDigit()
      case .monospaced: font.monospaced()
      case .italic: font.italic()
      }
    }
  }

  /// The system font that matches a text style at `scale` 1. Point sizes
  /// and weights are the macOS values of `NSFont.preferredFont`
  /// (headline bold, caption2 medium); a test keeps them in sync.
  static func scaledSystemFont(
    for style: Font.TextStyle,
    scale: CGFloat
  ) -> Font {
    let metrics = baseMetrics(for: style)
    return .system(size: metrics.pointSize * scale, weight: metrics.weight)
  }

  static func baseMetrics(
    for style: Font.TextStyle
  ) -> (pointSize: CGFloat, weight: Font.Weight) {
    switch style {
    case .largeTitle: (26, .regular)
    case .title: (22, .regular)
    case .title2: (17, .regular)
    case .title3: (15, .regular)
    case .headline: (13, .bold)
    case .subheadline: (11, .regular)
    case .body: (13, .regular)
    case .callout: (12, .regular)
    case .footnote: (10, .regular)
    case .caption: (10, .regular)
    case .caption2: (10, .medium)
    @unknown default: (13, .regular)
    }
  }

  private func adding(_ modifier: Modifier) -> AppFont {
    var copy = self
    copy.modifiers.append(modifier)
    return copy
  }
}

private struct AppFontModifier: ViewModifier {
  let font: AppFont
  @Environment(\.appTextSize) private var textSize

  func body(content: Content) -> some View {
    content.font(font.font(for: textSize))
  }
}

extension View {
  /// Use instead of `.font(_:)`: the font follows the text-size setting.
  func appFont(_ font: AppFont) -> some View {
    modifier(AppFontModifier(font: font))
  }

  /// For views whose system font is not a text style, such as sidebar rows:
  /// at standard size the system font stays untouched, every other size
  /// uses `font` scaled.
  func appFontKeepingSystemDefault(_ font: AppFont) -> some View {
    modifier(AppFontKeepingSystemDefaultModifier(font: font))
  }

  /// Sets the text size of a window. Every `appFont` below follows it; text
  /// without its own font uses the scaled body size and native controls the
  /// matching control size. At standard size font and control size stay
  /// untouched, so the established look remains unchanged.
  func appTextSize(_ textSize: AppTextSize) -> some View {
    environment(\.appTextSize, textSize)
      .transformEnvironment(\.font) { font in
        guard textSize != .standard else { return }
        font = AppFont.body.font(for: textSize)
      }
      .transformEnvironment(\.controlSize) { controlSize in
        guard textSize != .standard else { return }
        controlSize = textSize.controlSize
      }
  }
}

private struct AppFontKeepingSystemDefaultModifier: ViewModifier {
  let font: AppFont
  @Environment(\.appTextSize) private var textSize

  func body(content: Content) -> some View {
    content.transformEnvironment(\.font) { font in
      guard textSize != .standard else { return }
      font = self.font.font(for: textSize)
    }
  }
}

/// `ContentUnavailableView` whose title and description follow the
/// text-size setting. The system view keeps fixed fonts on macOS, and they
/// differ between macOS versions (macOS 27.2: title `title3` bold,
/// description `title3`; macOS 15 renders differently). At standard size
/// this view therefore leaves the system fonts untouched and renders
/// identically on every version; every other size scales `title3`.
struct AppUnavailableView<Title: View, Description: View, Actions: View>: View {
  private let title: Title
  private let description: Description
  private let actions: Actions

  init(
    @ViewBuilder label: () -> Title,
    @ViewBuilder description: () -> Description,
    @ViewBuilder actions: () -> Actions
  ) {
    title = label()
    self.description = description()
    self.actions = actions()
  }

  var body: some View {
    ContentUnavailableView {
      title.appFontKeepingSystemDefault(.title3.bold())
    } description: {
      description.appFontKeepingSystemDefault(.title3)
    } actions: {
      actions
    }
  }
}

extension AppUnavailableView where Actions == EmptyView {
  init(
    @ViewBuilder label: () -> Title,
    @ViewBuilder description: () -> Description
  ) {
    self.init(label: label, description: description) { EmptyView() }
  }
}

extension AppUnavailableView
where Title == Label<Text, Image>, Description == Text?, Actions == EmptyView {
  init(
    _ titleKey: LocalizedStringKey,
    systemImage: String,
    description: Text? = nil
  ) {
    self.init {
      Label(titleKey, systemImage: systemImage)
    } description: {
      description
    }
  }

  @_disfavoredOverload
  init<S: StringProtocol>(
    _ title: S,
    systemImage: String,
    description: Text? = nil
  ) {
    self.init {
      Label(title, systemImage: systemImage)
    } description: {
      description
    }
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

/// Visual interface style. "Classic" is the established look; "New Eden HUD"
/// adds HUD details to the shared building blocks and always runs dark
/// (owner decision 07.11.2026). Both styles show the same contents and use
/// the same calculation rules.
enum AppInterfaceStyle: String, CaseIterable, Identifiable {
  case classic
  case hud

  static let storageKey = "app.appearance.interface-style"
  /// Stays `classic` until the HUD rollout (prompt D8) is accepted.
  static let defaultStyle = AppInterfaceStyle.classic

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .classic: "Classic"
    case .hud: "New Eden HUD"
    }
  }

  /// Resolves a stored raw value; a missing or unknown value falls back to
  /// the default style.
  init(storedValue: String?) {
    self = storedValue.flatMap(Self.init(rawValue:)) ?? Self.defaultStyle
  }

  static func stored(in defaults: UserDefaults) -> AppInterfaceStyle {
    AppInterfaceStyle(storedValue: defaults.string(forKey: storageKey))
  }

  /// HUD always runs dark. The stored color scheme stays untouched and
  /// applies again as soon as Classic is selected.
  var locksColorScheme: Bool {
    self == .hud
  }

  func preferredColorScheme(
    for appearance: AppAppearanceStyle
  ) -> ColorScheme? {
    switch self {
    case .classic: appearance.preferredColorScheme
    case .hud: .dark
    }
  }
}

private struct AppInterfaceStyleKey: EnvironmentKey {
  static let defaultValue = AppInterfaceStyle.defaultStyle
}

extension EnvironmentValues {
  /// The interface style of the current window, set once at the scene root.
  var interfaceStyle: AppInterfaceStyle {
    get { self[AppInterfaceStyleKey.self] }
    set { self[AppInterfaceStyleKey.self] = newValue }
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

extension View {
  /// Applies the app language to separately hosted content such as popover
  /// bodies, which otherwise resolve their texts in the system language
  /// (plan DB7, finding B1).
  func appLanguageLocale() -> some View {
    environment(\.locale, AppLocalization.currentLanguage.locale)
  }
}
