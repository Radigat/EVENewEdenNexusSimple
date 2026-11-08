import SwiftUI

// Shared building blocks for both interface styles (plan D1 in
// `Documentation/DESIGN_HUD_2026-11-07.md`, section 4). In Classic they draw
// exactly the established panels. New Eden HUD keeps surface, border, radius
// and shadow and only adds corner brackets, title diamonds and the grid
// background.

/// The panel variants the shared surface reproduces (owner decision
/// 07.11.2026). Small cards, elevated sub-cards, special forms and table
/// parts stay outside the building block in both styles.
enum NexusPanelVariant: CaseIterable {
  /// Variant A: the shared `Panel`, with its soft drop shadow.
  case standard
  /// Variant B: hand-built panels with the same surface and border but
  /// without a shadow.
  case flat

  var hasShadow: Bool {
    switch self {
    case .standard: true
    case .flat: false
    }
  }
}

/// Panel surface: `DesignTokens.panel`, `cardRadius`, 1 pt
/// `DesignTokens.border`, the shadow of the variant, and in the HUD style
/// corner brackets on the border.
struct NexusPanelSurface: ViewModifier {
  let variant: NexusPanelVariant

  func body(content: Content) -> some View {
    shadowed(
      content
        .background(DesignTokens.panel)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    )
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
    .hudCornerBrackets()
  }

  @ViewBuilder
  private func shadowed(_ view: some View) -> some View {
    if variant.hasShadow {
      view.shadow(
        color: DesignTokens.panelShadow,
        radius: DesignTokens.panelShadowRadius,
        y: DesignTokens.panelShadowOffset
      )
    } else {
      view
    }
  }
}

/// Uppercase panel title. The HUD style places an accent diamond in front of
/// it; Classic shows the established title only.
struct NexusPanelTitle: View {
  let title: LocalizedStringKey
  @Environment(\.interfaceStyle) private var interfaceStyle

  init(_ title: LocalizedStringKey) {
    self.title = title
  }

  var body: some View {
    if interfaceStyle == .hud {
      label.hudDiamondPrefix(size: HUDDiamond.panelTitleSize)
    } else {
      label
    }
  }

  private var label: some View {
    Text(title)
      .nexusCaptionTitle()
  }
}

/// Uppercase caption title shared by panel titles, HUD sidebar groups and the
/// HUD area label: 10 pt semibold (`.caption`), tracking 1.1,
/// `textSecondary`.
struct NexusCaptionTitleStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .textCase(.uppercase)
      .appFont(.caption.weight(.semibold))
      .tracking(1.1)
      .foregroundStyle(DesignTokens.textSecondary)
  }
}

private struct NavigationGroupKey: EnvironmentKey {
  static let defaultValue: NavigationGroup? = nil
}

extension EnvironmentValues {
  /// Sidebar group of the view shown in the detail area; `nil` outside the
  /// main navigation, for example in sheets of other windows.
  var navigationGroup: NavigationGroup? {
    get { self[NavigationGroupKey.self] }
    set { self[NavigationGroupKey.self] = newValue }
  }
}

/// HUD area label above a view title: 6 pt accent diamond and the group name
/// in caption style, as on the boards.
struct NexusPageAreaLabel: View {
  let group: NavigationGroup

  var body: some View {
    Text(group.title)
      .nexusCaptionTitle()
      .hudDiamondPrefix(size: HUDDiamond.pageHeaderSize)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("page.area-label")
  }
}

/// Puts the HUD area label above a view title. Classic and views outside the
/// main navigation show the title unchanged.
struct NexusPageTitle: ViewModifier {
  @Environment(\.interfaceStyle) private var interfaceStyle
  @Environment(\.navigationGroup) private var navigationGroup

  func body(content: Content) -> some View {
    if interfaceStyle == .hud, let navigationGroup {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        NexusPageAreaLabel(group: navigationGroup)
        content
      }
      // Controls aligned to the title's baseline stay on the title.
      .alignmentGuide(.firstTextBaseline) { $0[.lastTextBaseline] }
    } else {
      content
    }
  }
}

extension View {
  /// Places a HUD diamond 8 pt in front of a title. The diamond sits in an
  /// overlay, so the title keeps its own text baselines for surrounding
  /// baseline alignment.
  func hudDiamondPrefix(size: CGFloat) -> some View {
    padding(.leading, size + DesignTokens.spacingSM)
      .overlay(alignment: .leading) {
        HUDDiamond(size: size)
      }
  }
}

/// Accent diamond of the HUD style: a square rotated by 45°.
struct HUDDiamond: View {
  static let panelTitleSize: CGFloat = 5
  static let pageHeaderSize: CGFloat = 6

  let size: CGFloat

  var body: some View {
    Rectangle()
      .fill(DesignTokens.accent)
      .frame(width: size, height: size)
      .rotationEffect(.degrees(45))
      .accessibilityHidden(true)
  }
}

/// Adds HUD corner brackets on top of an existing rounded border, in the HUD
/// style only. Classic draws nothing extra.
struct HUDCornerBracketsOverlay: ViewModifier {
  let cornerRadius: CGFloat
  @Environment(\.interfaceStyle) private var interfaceStyle

  func body(content: Content) -> some View {
    content.overlay {
      if interfaceStyle == .hud {
        HUDCornerBrackets(cornerRadius: cornerRadius)
      }
    }
  }
}

/// HUD corner brackets at the top-left and bottom-right corner. They reuse
/// the border's own rounded rectangle, so they follow its radius and lie
/// exactly on the border line.
struct HUDCornerBrackets: View {
  static let armLength: CGFloat = 14
  static let lineWidth: CGFloat = 1

  var cornerRadius: CGFloat = DesignTokens.cardRadius

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .stroke(DesignTokens.accent, lineWidth: Self.lineWidth)
      .mask {
        HUDCornerBracketMask(
          armLength: Self.armLength,
          outset: Self.lineWidth
        )
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct HUDCornerBracketMask: View {
  let armLength: CGFloat
  /// Includes the outer half of the stroke, which lies outside the bounds.
  let outset: CGFloat

  var body: some View {
    ZStack {
      corner(alignment: .topLeading)
      corner(alignment: .bottomTrailing)
    }
    .padding(-outset)
  }

  private func corner(alignment: Alignment) -> some View {
    Rectangle()
      .frame(width: armLength + outset, height: armLength + outset)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }
}

/// HUD grid: 32 pt raster of 1 pt accent lines at 3.5 % opacity.
struct HUDGridBackground: View {
  static let spacing: CGFloat = 32
  static let lineWidth: CGFloat = 1
  static let lineOpacity = 0.035

  var body: some View {
    Canvas { context, size in
      var path = Path()
      var x: CGFloat = 0
      while x <= size.width {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        x += Self.spacing
      }
      var y: CGFloat = 0
      while y <= size.height {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        y += Self.spacing
      }
      context.stroke(
        path,
        with: .color(DesignTokens.accent.opacity(Self.lineOpacity)),
        lineWidth: Self.lineWidth
      )
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Window canvas: `DesignTokens.canvas` as today, with the grid on top of it
/// in the HUD style only.
struct NexusCanvasBackground: ViewModifier {
  @Environment(\.interfaceStyle) private var interfaceStyle

  func body(content: Content) -> some View {
    content
      .background {
        if interfaceStyle == .hud {
          HUDGridBackground()
            .ignoresSafeArea()
        }
      }
      .background(DesignTokens.canvas)
  }
}

extension View {
  /// Shared panel surface of both interface styles.
  func nexusPanelSurface(
    _ variant: NexusPanelVariant = .standard
  ) -> some View {
    modifier(NexusPanelSurface(variant: variant))
  }

  /// Window canvas; adds the grid in the HUD style only.
  func nexusCanvasBackground() -> some View {
    modifier(NexusCanvasBackground())
  }

  /// HUD corner brackets for surfaces outside the panel building block, such
  /// as the Planner's floating info panel or the small cards and calculator
  /// pane of the Hub opportunities; pass the surface's own corner radius.
  func hudCornerBrackets(
    cornerRadius: CGFloat = DesignTokens.cardRadius
  ) -> some View {
    modifier(HUDCornerBracketsOverlay(cornerRadius: cornerRadius))
  }

  /// Uppercase caption title style of both interface styles.
  func nexusCaptionTitle() -> some View {
    modifier(NexusCaptionTitleStyle())
  }

  /// View title; the HUD style adds the area label above it.
  func nexusPageTitle() -> some View {
    modifier(NexusPageTitle())
  }
}
