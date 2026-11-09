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
