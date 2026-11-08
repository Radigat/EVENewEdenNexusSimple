import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

@MainActor
final class AppInterfaceStyleTests: XCTestCase {
  func testUsesItsOwnStorageKeyBesideTheColorScheme() {
    XCTAssertEqual(
      AppInterfaceStyle.storageKey,
      "app.appearance.interface-style"
    )
    XCTAssertEqual(AppAppearanceStyle.storageKey, "app.appearance.color-scheme")
    XCTAssertEqual(AppInterfaceStyle.classic.rawValue, "classic")
    XCTAssertEqual(AppInterfaceStyle.hud.rawValue, "hud")
  }

  func testDefaultsToClassicWithoutStoredValue() throws {
    try withIsolatedDefaults { defaults in
      XCTAssertEqual(AppInterfaceStyle.defaultStyle, .classic)
      XCTAssertNil(defaults.object(forKey: AppInterfaceStyle.storageKey))
      XCTAssertEqual(AppInterfaceStyle.stored(in: defaults), .classic)
    }
  }

  func testUnknownOrEmptyStoredValueFallsBackToClassic() throws {
    try withIsolatedDefaults { defaults in
      defaults.set("neon", forKey: AppInterfaceStyle.storageKey)
      XCTAssertEqual(AppInterfaceStyle.stored(in: defaults), .classic)
    }
    XCTAssertEqual(AppInterfaceStyle(storedValue: nil), .classic)
    XCTAssertEqual(AppInterfaceStyle(storedValue: ""), .classic)
    XCTAssertEqual(AppInterfaceStyle(storedValue: "HUD"), .classic)
  }

  func testStoredSelectionIsRestored() throws {
    try withIsolatedDefaults { defaults in
      for style in AppInterfaceStyle.allCases {
        defaults.set(style.rawValue, forKey: AppInterfaceStyle.storageKey)
        XCTAssertEqual(AppInterfaceStyle.stored(in: defaults), style)
      }
    }
  }

  func testClassicFollowsTheStoredColorScheme() {
    XCTAssertNil(AppInterfaceStyle.classic.preferredColorScheme(for: .system))
    XCTAssertEqual(
      AppInterfaceStyle.classic.preferredColorScheme(for: .light),
      .light
    )
    XCTAssertEqual(
      AppInterfaceStyle.classic.preferredColorScheme(for: .dark),
      .dark
    )
    XCTAssertFalse(AppInterfaceStyle.classic.locksColorScheme)
  }

  func testHUDAlwaysRunsDarkAndLocksTheColorScheme() {
    for appearance in AppAppearanceStyle.allCases {
      XCTAssertEqual(
        AppInterfaceStyle.hud.preferredColorScheme(for: appearance),
        .dark,
        "\(appearance)"
      )
    }
    XCTAssertTrue(AppInterfaceStyle.hud.locksColorScheme)
  }

  func testStoredColorSchemeAppliesAgainAfterLeavingHUD() throws {
    try withIsolatedDefaults { defaults in
      defaults.set(
        AppAppearanceStyle.light.rawValue,
        forKey: AppAppearanceStyle.storageKey
      )
      defaults.set(
        AppInterfaceStyle.hud.rawValue,
        forKey: AppInterfaceStyle.storageKey
      )
      XCTAssertEqual(scheme(in: defaults), .dark)
      XCTAssertEqual(
        defaults.string(forKey: AppAppearanceStyle.storageKey),
        AppAppearanceStyle.light.rawValue
      )

      defaults.set(
        AppInterfaceStyle.classic.rawValue,
        forKey: AppInterfaceStyle.storageKey
      )
      XCTAssertEqual(scheme(in: defaults), .light)
    }
  }

  func testColorSchemeIsAppliedAsAppKitAppearance() {
    XCTAssertEqual(AppAppearanceApplier.appearanceName(for: .dark), .darkAqua)
    XCTAssertEqual(AppAppearanceApplier.appearanceName(for: .light), .aqua)
    // System: no forced appearance, so macOS decides again immediately.
    XCTAssertNil(AppAppearanceApplier.appearanceName(for: nil))
    XCTAssertEqual(
      AppAppearanceApplier.appearanceName(
        for: AppInterfaceStyle.hud.preferredColorScheme(for: .light)
      ),
      .darkAqua
    )
    XCTAssertNil(
      AppAppearanceApplier.appearanceName(
        for: AppInterfaceStyle.classic.preferredColorScheme(for: .system)
      )
    )
  }

  func testEnvironmentValueDefaultsToClassic() {
    var environment = EnvironmentValues()
    XCTAssertEqual(environment.interfaceStyle, .classic)
    environment.interfaceStyle = .hud
    XCTAssertEqual(environment.interfaceStyle, .hud)
  }

  func testPanelVariantsKeepTheEstablishedShadowRule() {
    XCTAssertEqual(NexusPanelVariant.allCases.count, 2)
    XCTAssertTrue(NexusPanelVariant.standard.hasShadow)
    XCTAssertFalse(NexusPanelVariant.flat.hasShadow)
  }

  func testHUDMeasurementsFollowThePlan() {
    XCTAssertEqual(HUDCornerBrackets.armLength, 14)
    XCTAssertEqual(HUDCornerBrackets.lineWidth, 1)
    XCTAssertEqual(HUDDiamond.panelTitleSize, 5)
    XCTAssertEqual(HUDDiamond.pageHeaderSize, 6)
    XCTAssertEqual(HUDGridBackground.spacing, 32)
    XCTAssertEqual(HUDGridBackground.lineWidth, 1)
    XCTAssertEqual(HUDGridBackground.lineOpacity, 0.035, accuracy: 0.000_1)
  }

  private func scheme(in defaults: UserDefaults) -> ColorScheme? {
    let appearance =
      defaults.string(forKey: AppAppearanceStyle.storageKey)
      .flatMap(AppAppearanceStyle.init(rawValue:)) ?? .system
    return AppInterfaceStyle.stored(in: defaults)
      .preferredColorScheme(for: appearance)
  }

  private func withIsolatedDefaults(
    _ body: (UserDefaults) throws -> Void
  ) throws {
    let suiteName = "AppInterfaceStyleTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
  }
}
