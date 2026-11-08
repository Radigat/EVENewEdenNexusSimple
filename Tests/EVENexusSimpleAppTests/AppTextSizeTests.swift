import AppKit
import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

/// The text-size setting must change the rendered text. macOS ignores
/// `dynamicTypeSize` for SwiftUI text styles, so the setting had no visible
/// effect before `AppFont` (fixed 07.11.2026).
@MainActor
final class AppTextSizeTests: XCTestCase {
  private let textStyles: [Font.TextStyle] = [
    .largeTitle, .title, .title2, .title3, .headline, .subheadline, .body,
    .callout, .footnote, .caption, .caption2,
  ]

  func testKeepsItsStorageKeyAndOrder() {
    XCTAssertEqual(AppTextSize.storageKey, "app.appearance.text-size")
    XCTAssertEqual(
      AppTextSize.allCases.map(\.rawValue),
      ["compact", "standard", "large", "extraLarge", "accessibility"]
    )
  }

  func testScaleIsOneAtStandardAndGrowsWithEachSize() {
    XCTAssertEqual(AppTextSize.standard.scale, 1)
    let scales = AppTextSize.allCases.map(\.scale)
    XCTAssertEqual(scales, scales.sorted())
    XCTAssertEqual(Set(scales).count, scales.count)
  }

  func testStandardResolvesToTheUnchangedSwiftUIFonts() {
    for style in textStyles {
      XCTAssertEqual(
        AppFont(.textStyle(style)).font(for: .standard),
        Font.system(style),
        "\(style)"
      )
    }
    XCTAssertEqual(AppFont.caption.font(for: .standard), Font.caption)
    XCTAssertEqual(
      AppFont.caption.monospacedDigit().font(for: .standard),
      Font.caption.monospacedDigit()
    )
    XCTAssertEqual(
      AppFont.title3.monospacedDigit().weight(.semibold).font(for: .standard),
      Font.title3.monospacedDigit().weight(.semibold)
    )
    XCTAssertEqual(
      AppFont.system(size: 34, weight: .bold, design: .rounded)
        .font(for: .standard),
      Font.system(size: 34, weight: .bold, design: .rounded)
    )
  }

  /// The scaled form must continue the text style seamlessly: at factor 1 it
  /// renders exactly like the macOS text style (size and weight).
  func testScaledFormMatchesTheMacOSTextStyleAtFactorOne() throws {
    for style in textStyles {
      let nsStyle = try XCTUnwrap(Self.nsTextStyle(for: style))
      XCTAssertEqual(
        AppFont.baseMetrics(for: style).pointSize,
        NSFont.preferredFont(forTextStyle: nsStyle).pointSize,
        "\(style)"
      )
      XCTAssertEqual(
        width(of: Text(sample).font(.system(style))),
        width(of: Text(sample).font(AppFont.scaledSystemFont(for: style, scale: 1))),
        "\(style)"
      )
    }
  }

  func testEveryLargerSizeRendersLargerStyledText() {
    for font in [AppFont.body, .caption, .headline, .caption.monospacedDigit()] {
      let widths = AppTextSize.allCases.map { size in
        width(
          of: Text(sample).appFont(font).environment(\.appTextSize, size)
        )
      }
      XCTAssertEqual(widths, widths.sorted(), "\(font)")
      XCTAssertEqual(Set(widths).count, widths.count, "\(font)")
    }
  }

  func testUnstyledTextFollowsTheWindowTextSize() {
    let unchanged = width(of: Text(sample))
    XCTAssertEqual(width(of: Text(sample).appTextSize(.standard)), unchanged)
    let widths = AppTextSize.allCases.map { size in
      width(of: Text(sample).appTextSize(size))
    }
    XCTAssertEqual(widths, widths.sorted())
    XCTAssertEqual(Set(widths).count, widths.count)
  }

  func testStandardSizeLeavesFontAndControlSizeUntouched() {
    XCTAssertEqual(
      width(of: Text(sample).font(.title).appTextSize(.standard)),
      width(of: Text(sample).font(.title))
    )
    XCTAssertEqual(
      width(of: Button(sample) {}.appTextSize(.standard)),
      width(of: Button(sample) {})
    )
    XCTAssertGreaterThan(
      width(of: Button(sample) {}.appTextSize(.accessibility)),
      width(of: Button(sample) {})
    )
    XCTAssertEqual(AppTextSize.standard.controlSize, .regular)
    XCTAssertEqual(AppTextSize.large.controlSize, .large)
    XCTAssertEqual(AppTextSize.compact.controlSize, .small)
    XCTAssertEqual(AppTextSize.accessibility.controlSize, .extraLarge)
  }

  /// Sidebar rows keep the system sidebar font at standard size.
  func testKeepingSystemDefaultChangesTheFontOnlyAwayFromStandard() {
    let systemDefault = width(of: Text(sample).font(.title))
    XCTAssertEqual(
      width(
        of: Text(sample).appFontKeepingSystemDefault(.body).font(.title)
          .environment(\.appTextSize, .standard)
      ),
      systemDefault
    )
    XCTAssertEqual(
      width(
        of: Text(sample).appFontKeepingSystemDefault(.body).font(.title)
          .environment(\.appTextSize, .large)
      ),
      width(of: Text(sample).font(AppFont.body.font(for: .large)))
    )
  }

  func testUnavailableViewMatchesTheSystemViewAtStandardSize() throws {
    let title = "No connected characters"
    let description = "Add a character under Characters before refreshing wallet balances."
    XCTAssertEqual(
      try render(
        ContentUnavailableView(
          title,
          systemImage: "creditcard",
          description: Text(description)
        )
      ),
      try render(
        AppUnavailableView(
          title,
          systemImage: "creditcard",
          description: Text(description)
        )
      )
    )
    XCTAssertEqual(
      try render(ContentUnavailableView(title, systemImage: "creditcard")),
      try render(AppUnavailableView(title, systemImage: "creditcard"))
    )
    XCTAssertEqual(
      try render(
        ContentUnavailableView {
          Label(title, systemImage: "creditcard")
        } description: {
          Text(description)
        } actions: {
          Button("Open settings") {}
        }
      ),
      try render(
        AppUnavailableView {
          Label(title, systemImage: "creditcard")
        } description: {
          Text(description)
        } actions: {
          Button("Open settings") {}
        }
      )
    )
  }

  func testUnavailableViewGrowsWithTheTextSize() {
    let heights = AppTextSize.allCases.map { size in
      NSHostingView(
        rootView: AppUnavailableView(
          "No connected characters",
          systemImage: "creditcard",
          description: Text("Add a character under Characters before refreshing wallet balances.")
        )
        .frame(width: 400)
        .fixedSize()
        .environment(\.appTextSize, size)
      ).fittingSize.height
    }
    XCTAssertEqual(heights, heights.sorted())
    XCTAssertEqual(Set(heights).count, heights.count)
  }

  /// SwiftUI text styles, fixed `.system(size:)` fonts and the system
  /// unavailable view ignore the setting on macOS. New app code fails here
  /// until it uses `appFont` and `AppUnavailableView`.
  func testAppSourcesUseAppFontInsteadOfFixedFonts() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/EVENexusSimpleApp")
    let fixedFont = try NSRegularExpression(
      pattern:
        #"\.font\(\s*(\.|Font\.)(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2|system)\b|:\s*Font\b(?!\.)|\bContentUnavailableView\s*[({]"#
    )
    let files = try FileManager.default.contentsOfDirectory(
      at: sources,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "AppLanguage.swift" }
    XCTAssertFalse(files.isEmpty)
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      let matches = fixedFont.matches(
        in: source,
        range: NSRange(source.startIndex..., in: source)
      )
      let lines = matches.map { match in
        source[..<Range(match.range, in: source)!.lowerBound]
          .split(separator: "\n", omittingEmptySubsequences: false).count
      }
      XCTAssertEqual(lines, [], "\(file.lastPathComponent): use .appFont(_:)")
    }
  }

  private let sample = "Tritanium Jita IV-4 1.234.567,89 ISK"

  private func width(of view: some View) -> CGFloat {
    NSHostingView(rootView: view.fixedSize()).fittingSize.width
  }

  private func render(_ view: some View) throws -> Data {
    let renderer = ImageRenderer(
      content: view.frame(width: 400).padding(10).background(Color.white)
    )
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.cgImage)
    return try XCTUnwrap(
      NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    )
  }

  private static func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle? {
    switch style {
    case .largeTitle: .largeTitle
    case .title: .title1
    case .title2: .title2
    case .title3: .title3
    case .headline: .headline
    case .subheadline: .subheadline
    case .body: .body
    case .callout: .callout
    case .footnote: .footnote
    case .caption: .caption1
    case .caption2: .caption2
    @unknown default: nil
    }
  }
}
