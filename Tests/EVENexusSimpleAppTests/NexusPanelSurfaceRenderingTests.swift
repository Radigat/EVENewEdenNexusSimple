import AppKit
import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

/// Renders the shared building blocks offscreen and compares them with the
/// hand-built panels they replace. In Classic the bitmaps must be identical,
/// so replacing a hand-built panel never changes the Classic look.
@MainActor
final class NexusPanelSurfaceRenderingTests: XCTestCase {
  func testStandardSurfaceDrawsTheEstablishedSharedPanelInClassic() throws {
    for scheme in [ColorScheme.light, .dark] {
      let handBuilt = try render(
        sample
          .background(DesignTokens.panel)
          .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
          .shadow(
            color: DesignTokens.panelShadow,
            radius: DesignTokens.panelShadowRadius,
            y: DesignTokens.panelShadowOffset
          )
          .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
              .stroke(DesignTokens.border)
          },
        style: .classic,
        scheme: scheme
      )
      let surface = try render(
        sample.nexusPanelSurface(.standard),
        style: .classic,
        scheme: scheme
      )
      XCTAssertEqual(handBuilt, surface, "\(scheme)")
    }
  }

  func testFlatSurfaceDrawsTheHandBuiltPanelWithoutShadowInClassic() throws {
    for scheme in [ColorScheme.light, .dark] {
      let handBuilt = try render(
        sample
          .background(DesignTokens.panel)
          .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
          .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
              .stroke(DesignTokens.border)
          },
        style: .classic,
        scheme: scheme
      )
      let surface = try render(
        sample.nexusPanelSurface(.flat),
        style: .classic,
        scheme: scheme
      )
      XCTAssertEqual(handBuilt, surface, "\(scheme)")
    }
  }

  func testPanelTitleDrawsTheEstablishedCaptionTitleInClassic() throws {
    let handBuilt = try render(
      Text("Known net worth")
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .tracking(1.1)
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(4),
      style: .classic,
      scheme: .light
    )
    let title = try render(
      NexusPanelTitle("Known net worth").padding(4),
      style: .classic,
      scheme: .light
    )
    XCTAssertEqual(handBuilt, title)
  }

  func testRenderingDistinguishesTheShadowOfTheVariants() throws {
    // Counter-check: the comparison is sensitive enough to see the shadow.
    let standard = try render(
      sample.nexusPanelSurface(.standard), style: .classic, scheme: .light
    )
    let flat = try render(
      sample.nexusPanelSurface(.flat), style: .classic, scheme: .light
    )
    XCTAssertNotEqual(standard, flat)
  }

  func testCornerBracketsOnSpecialSurfacesOnlyAppearInHUD() throws {
    // Shaped like the Planner's floating info panel.
    func infoPanel(withBrackets: Bool) -> some View {
      sample
        .background(
          RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
            .fill(DesignTokens.panel)
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
            .stroke(DesignTokens.border)
        )
        .shadow(color: DesignTokens.panelShadow, radius: 18)
        .modifier(OptionalBrackets(isApplied: withBrackets))
    }
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertEqual(
        try render(infoPanel(withBrackets: false), style: .classic, scheme: scheme),
        try render(infoPanel(withBrackets: true), style: .classic, scheme: scheme),
        "\(scheme)"
      )
    }
    XCTAssertNotEqual(
      try render(infoPanel(withBrackets: false), style: .hud, scheme: .dark),
      try render(infoPanel(withBrackets: true), style: .hud, scheme: .dark)
    )
  }

  func testCornerBracketsFollowTheSmallRadiiOfHubOpportunitySurfaces() throws {
    // Filter deck and analysis basis: small cards with the border under the
    // clip. Calculator: canvas pane with a 2 pt rounded border.
    func card(withBrackets: Bool) -> some View {
      sample
        .background(DesignTokens.panel)
        .overlay {
          RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
            .stroke(DesignTokens.border)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
        .modifier(
          OptionalBrackets(
            isApplied: withBrackets,
            cornerRadius: DesignTokens.badgeRadius
          )
        )
    }
    func calculator(withBrackets: Bool) -> some View {
      sample
        .background(DesignTokens.canvas)
        .overlay {
          RoundedRectangle(cornerRadius: 2).stroke(DesignTokens.border)
        }
        .modifier(OptionalBrackets(isApplied: withBrackets, cornerRadius: 2))
    }
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertEqual(
        try render(card(withBrackets: false), style: .classic, scheme: scheme),
        try render(card(withBrackets: true), style: .classic, scheme: scheme),
        "card \(scheme)"
      )
      XCTAssertEqual(
        try render(calculator(withBrackets: false), style: .classic, scheme: scheme),
        try render(calculator(withBrackets: true), style: .classic, scheme: scheme),
        "calculator \(scheme)"
      )
    }
    XCTAssertNotEqual(
      try render(card(withBrackets: false), style: .hud, scheme: .dark),
      try render(card(withBrackets: true), style: .hud, scheme: .dark)
    )
    XCTAssertNotEqual(
      try render(calculator(withBrackets: false), style: .hud, scheme: .dark),
      try render(calculator(withBrackets: true), style: .hud, scheme: .dark)
    )
  }

  func testCornerBracketsOnBorderlessTradeTilesOnlyAppearInHUD() throws {
    // Shaped like a Trade tile: panel surface without border or shadow and
    // the source-to-target gradient bar on top.
    func tile(withBrackets: Bool) -> some View {
      sample
        .background(DesignTokens.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .top) {
          LinearGradient(
            colors: [DesignTokens.highlight, DesignTokens.accent],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(height: 3)
          .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .modifier(OptionalBrackets(isApplied: withBrackets, cornerRadius: 10))
    }
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertEqual(
        try render(tile(withBrackets: false), style: .classic, scheme: scheme),
        try render(tile(withBrackets: true), style: .classic, scheme: scheme),
        "\(scheme)"
      )
    }
    XCTAssertNotEqual(
      try render(tile(withBrackets: false), style: .hud, scheme: .dark),
      try render(tile(withBrackets: true), style: .hud, scheme: .dark)
    )
  }

  private struct OptionalBrackets: ViewModifier {
    let isApplied: Bool
    var cornerRadius: CGFloat = DesignTokens.cardRadius

    func body(content: Content) -> some View {
      if isApplied {
        content.hudCornerBrackets(cornerRadius: cornerRadius)
      } else {
        content
      }
    }
  }

  func testHUDAddsCornerBracketsAndDiamond() throws {
    let classicSurface = try render(
      sample.nexusPanelSurface(.flat), style: .classic, scheme: .dark
    )
    let hudSurface = try render(
      sample.nexusPanelSurface(.flat), style: .hud, scheme: .dark
    )
    XCTAssertNotEqual(classicSurface, hudSurface)

    let classicTitle = try render(
      NexusPanelTitle("Wallet").padding(4), style: .classic, scheme: .dark
    )
    let hudTitle = try render(
      NexusPanelTitle("Wallet").padding(4), style: .hud, scheme: .dark
    )
    XCTAssertNotEqual(classicTitle, hudTitle)
  }

  private var sample: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      Text("PANEL")
      Text("1.234.567,89 ISK")
    }
    .frame(width: 220, height: 90, alignment: .topLeading)
    .padding(DesignTokens.spacingMD)
  }

  private struct Bitmap: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]
  }

  private func render(
    _ view: some View,
    style: AppInterfaceStyle,
    scheme: ColorScheme
  ) throws -> Bitmap {
    let appearance = NSAppearance(
      named: scheme == .dark ? .darkAqua : .aqua
    )
    let previous = NSAppearance.current
    NSAppearance.current = appearance
    defer { NSAppearance.current = previous }

    let renderer = ImageRenderer(
      content: view
        .padding(20)
        .environment(\.interfaceStyle, style)
        .environment(\.colorScheme, scheme)
    )
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.cgImage)
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Bitmap(width: width, height: height, bytes: bytes)
  }
}
