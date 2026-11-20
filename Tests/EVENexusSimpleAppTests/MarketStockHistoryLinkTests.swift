import EVENexusCore
import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

/// Owner rule of 09.11.2026: every item links to the one shared stock
/// history, which only a host opens.
@MainActor
final class MarketStockHistoryLinkTests: XCTestCase {
  func testRouterOpensTheRequestedItem() {
    let router = MarketStockHistoryRouter()
    XCTAssertNil(router.request)

    router.open(MarketStockItemRequest(typeID: 34, name: "Tritanium", preferredRole: .coalition))

    XCTAssertEqual(
      router.request,
      MarketStockItemRequest(typeID: 34, name: "Tritanium", preferredRole: .coalition)
    )
  }

  func testLinkStartsWithTheHomeHubOutsideTradeAndMarketStock() {
    XCTAssertEqual(MarketStockHistoryButton(typeID: 34, name: "Tritanium").preferredRole, .home)
    XCTAssertTrue(EVEItemText(value: "Tritanium", typeID: 34).showsMarketStockHistory)
  }

  func testItemTextShowsTheLinkOnlyInsideAHost() {
    let item = EVEItemText(value: "Tritanium", typeID: 34)
    let withoutHost = width(of: item)
    let withHost = width(
      of: item.environment(\.marketStockHistoryRouter, MarketStockHistoryRouter())
    )
    let switchedOff = width(
      of: EVEItemText(value: "Tritanium", typeID: 34, showsMarketStockHistory: false)
        .environment(\.marketStockHistoryRouter, MarketStockHistoryRouter())
    )
    let invalidType = width(
      of: EVEItemText(value: "Tritanium", typeID: 0)
        .environment(\.marketStockHistoryRouter, MarketStockHistoryRouter())
    )

    XCTAssertGreaterThan(withHost, withoutHost)
    XCTAssertEqual(switchedOff, withoutHost)
    XCTAssertEqual(invalidType, withoutHost)
  }

  /// One view, one place: no screen builds its own history sheet.
  func testOnlyTheHostPresentsTheHistoryView() throws {
    var presenters: [String] = []
    for (name, source) in try appSources() {
      let count = source.components(separatedBy: "MarketStockItemDetailView(request:").count - 1
      presenters += Array(repeating: name, count: count)
    }
    XCTAssertEqual(presenters, ["MarketStockItemDetailView.swift"])
  }

  /// A second sheet can only open from inside the sheet already shown, so
  /// every sheet installs its own host (the main window installs one too).
  func testEverySheetInstallsAHost() throws {
    for (name, source) in try appSources() {
      let lines = source.components(separatedBy: "\n")
      for (index, line) in lines.enumerated() where line.contains(".sheet(") {
        guard !line.contains("$router.request") else { continue }
        let block = lines[index..<min(index + 6, lines.count)].joined(separator: "\n")
        XCTAssertTrue(
          block.contains(".marketStockHistoryHost()"),
          "\(name):\(index + 1): sheet without stock history host"
        )
      }
    }
    let content = try XCTUnwrap(try appSources().first { $0.name == "ContentView.swift" })
    XCTAssertGreaterThanOrEqual(
      content.source.components(separatedBy: ".marketStockHistoryHost()").count - 1,
      2,
      "Main window and its consolidation sheet each need a host"
    )
  }

  /// The link symbol replaces a borderless button (GESCHWINDIGKEIT T19) and
  /// must keep its size and colour in both appearances.
  func testItemLinkSymbolLooksLikeABorderlessButton() throws {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let button = try strongestPixel(
        of: Button {
        } label: {
          Image(systemName: "hammer")
        }
        .buttonStyle(.borderless),
        appearance: appearance
      )
      let symbol = try strongestPixel(
        of: ItemLinkSymbol(systemName: "hammer") {},
        appearance: appearance
      )
      XCTAssertEqual(symbol.size, button.size, "\(appearance.rawValue)")
      XCTAssertEqual(symbol.white, button.white, accuracy: 0.05, "\(appearance.rawValue)")
      XCTAssertEqual(symbol.alpha, button.alpha, accuracy: 0.08, "\(appearance.rawValue)")
    }
  }

  /// Both links of 200 rows must stay well below the cost of the borderless
  /// buttons they replaced. Measured under macOS 27 about one sixth, so from
  /// macOS 26 on the loose bound of 0.6 applies. Under macOS 15 (CI) the
  /// ratio is about 0.6 to 0.7; there the links only have to be cheaper
  /// (owner decision 20.11.2026).
  func testItemLinksStayCheaperThanBorderlessButtons() {
    let history = MarketStockHistoryRouter()
    let build = PlannerBuildRouter(
      targets: Dictionary(uniqueKeysWithValues: (1...200).map { (Int64($0), Int64($0)) })
    )
    func milliseconds(@ViewBuilder _ links: @escaping (Int64) -> some View) -> Double {
      let runs = (0..<5).map { _ in
        let started = ContinuousClock.now
        let host = NSHostingView(
          rootView: VStack(spacing: 0) {
            ForEach(1...200, id: \.self) { index in
              HStack { links(Int64(index)) }
            }
          }
          .environment(\.marketStockHistoryRouter, history)
          .environment(\.plannerBuildRouter, build)
        )
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) * 1_000
          + Double(elapsed.components.attoseconds) / 1e15
      }
      return runs.sorted()[2]
    }
    _ = milliseconds { _ in EmptyView() }
    let borderless = milliseconds { _ in
      Button {
      } label: {
        Image(systemName: "chart.xyaxis.line")
      }
      .buttonStyle(.borderless)
      Button {
      } label: {
        Image(systemName: "hammer")
      }
      .buttonStyle(.borderless)
    }
    let links = milliseconds { typeID in
      MarketStockHistoryButton(typeID: typeID, name: "Fixture")
      PlannerBuildButton(typeID: typeID, name: "Fixture")
    }
    let bound = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 0.6 : 1.0
    XCTAssertLessThan(
      links,
      borderless * bound,
      "links \(links) ms, borderless \(borderless) ms, bound \(bound)"
    )
  }

  private func strongestPixel(
    of view: some View,
    appearance: NSAppearance.Name
  ) throws -> (size: CGSize, white: CGFloat, alpha: CGFloat) {
    let host = NSHostingView(rootView: view.padding(4))
    host.appearance = NSAppearance(named: appearance)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    var strongest: (white: CGFloat, alpha: CGFloat) = (0, 0)
    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y),
          color.alphaComponent > strongest.alpha
        else { continue }
        strongest = (
          (color.redComponent + color.greenComponent + color.blueComponent) / 3,
          color.alphaComponent
        )
      }
    }
    return (host.bounds.size, strongest.white, strongest.alpha)
  }

  private func width(of view: some View) -> CGFloat {
    NSHostingView(rootView: view.fixedSize()).fittingSize.width
  }

  private func appSources() throws -> [(name: String, source: String)] {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/EVENexusSimpleApp")
    let files = try FileManager.default.contentsOfDirectory(
      at: sources,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "swift" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    XCTAssertFalse(files.isEmpty)
    return try files.map {
      ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
    }
  }
}
