import AppKit
import EVENexusCore
import XCTest

@testable import EVENexusSimpleApp

/// The PNG export of the Moon material and mineral purchase analyses renders
/// the dark Classic table in every interface style and color scheme (owner
/// decision D7, 07.11.2026).
@MainActor
final class MaterialPurchaseImageExportTests: XCTestCase {
  /// Text edges may differ by one color step depending on earlier rendering
  /// in the same process. A light or HUD look would change surfaces and text
  /// by far more (canvas light vs. dark: about 210 steps).
  private let antialiasingTolerance = 2

  func testExportIsTheSameDarkImageForEveryAppAppearance() throws {
    for kind in [MaterialPurchaseAnalysisKind.moonMaterials, .minerals] {
      // Classic light runs with Aqua; Classic dark and New Eden HUD run with
      // Dark Aqua. The export view gets its own environment either way.
      let light = try export(kind, appAppearance: .aqua)
      let dark = try export(kind, appAppearance: .darkAqua)
      XCTAssertEqual(light.width, dark.width, "width \(kind)")
      XCTAssertEqual(light.height, dark.height, "height \(kind)")
      let delta = light.maximumChannelDelta(dark)
      XCTAssertLessThanOrEqual(
        delta,
        antialiasingTolerance,
        "maximum channel delta \(kind)"
      )

      // The dark canvas fills the outer padding of the export.
      let canvas = try XCTUnwrap(
        NSColor(srgbRed: 0.075, green: 0.095, blue: 0.11, alpha: 1)
          .usingColorSpace(.sRGB)
      )
      for (pixel, appearance) in [
        (light.pixel(x: 4, y: 4), "aqua"), (dark.pixel(x: 4, y: 4), "darkAqua"),
      ] {
        XCTAssertEqual(
          Int(pixel.red), Int((canvas.redComponent * 255).rounded()),
          accuracy: antialiasingTolerance, "red \(kind) \(appearance)")
        XCTAssertEqual(
          Int(pixel.green), Int((canvas.greenComponent * 255).rounded()),
          accuracy: antialiasingTolerance, "green \(kind) \(appearance)")
        XCTAssertEqual(
          Int(pixel.blue), Int((canvas.blueComponent * 255).rounded()),
          accuracy: antialiasingTolerance, "blue \(kind) \(appearance)")
      }
    }
  }

  private let exportedAt = Date(timeIntervalSince1970: 1_794_000_000)

  private var analysis: MaterialPurchaseAnalysisSnapshot {
    let hub = MarketHubConfigurationSnapshot(
      id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D7")!,
      location: .jita,
      roles: [.main]
    )
    return MaterialPurchaseAnalysisSnapshot(
      materialCatalog: MaterialPurchaseCatalogSnapshot(
        materials: [
          MaterialPurchaseItem(id: 34, name: "Tritanium"),
          MaterialPurchaseItem(id: 35, name: "Pyerite"),
        ],
        source: SourceIdentity(provider: "fixture", version: "1")
      ),
      configuredHubs: [hub],
      refreshedAt: exportedAt
    )
  }

  private func export(
    _ kind: MaterialPurchaseAnalysisKind,
    appAppearance: NSAppearance.Name
  ) throws -> Bitmap {
    let previous = NSAppearance.current
    NSAppearance.current = NSAppearance(named: appAppearance)
    defer { NSAppearance.current = previous }
    let png = try XCTUnwrap(
      MaterialPurchaseImageExportRenderer.pngData(
        kind: kind,
        analysis: analysis,
        materials: analysis.materialCatalog.materials,
        exportedAt: exportedAt
      )
    )
    return try Bitmap(png: png)
  }

  private struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(png: Data) throws {
      let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
      let image = try XCTUnwrap(rep.cgImage)
      width = image.width
      height = image.height
      var buffer = [UInt8](repeating: 0, count: width * height * 4)
      let context = try XCTUnwrap(
        CGContext(
          data: &buffer,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      )
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      bytes = buffer
    }

    func maximumChannelDelta(_ other: Bitmap) -> Int {
      guard bytes.count == other.bytes.count else { return Int.max }
      var maximum = 0
      for index in bytes.indices where index % 4 != 3 {
        maximum = max(maximum, abs(Int(bytes[index]) - Int(other.bytes[index])))
      }
      return maximum
    }

    func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
      let index = (y * width + x) * 4
      return (bytes[index], bytes[index + 1], bytes[index + 2])
    }
  }
}
