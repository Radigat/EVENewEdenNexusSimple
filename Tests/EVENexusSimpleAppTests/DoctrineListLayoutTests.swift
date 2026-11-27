import Foundation
import Testing

@testable import EVENexusSimpleApp

/// Owner request 27.11.2026: the doctrine list of the page “Doctrine stock”
/// uses several columns instead of one long list.
@MainActor
@Suite("Doctrine list layout")
struct DoctrineListLayoutTests {
  @Test
  func columnCountFollowsTheWidthWithGapsAndALimit() {
    let withAllumis = DoctrineListLayout.columnMinimumWidth(showsAllumis: true)
    let withoutAllumis = DoctrineListLayout.columnMinimumWidth(showsAllumis: false)
    #expect(withAllumis == 408)
    #expect(withoutAllumis == 234)

    // Unknown width while the page lays out for the first time.
    #expect(DoctrineListLayout.columnCount(width: 0, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: .infinity, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: 300, columnMinimumWidth: withAllumis) == 1)
    // Two columns need 2 × 408 plus a line with 16 pt on each side.
    #expect(DoctrineListLayout.columnCount(width: 848, columnMinimumWidth: withAllumis) == 1)
    #expect(DoctrineListLayout.columnCount(width: 849, columnMinimumWidth: withAllumis) == 2)
    #expect(DoctrineListLayout.columnCount(width: 1_650, columnMinimumWidth: withAllumis) == 3)
    #expect(DoctrineListLayout.columnCount(width: 5_000, columnMinimumWidth: withoutAllumis) == 4)
  }

  @Test
  func rowsFillTheColumnsTopToBottomInTheirOrder() {
    let rows = Array(1...10)
    #expect(DoctrineListLayout.columns(rows, count: 3) == [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]])
    #expect(DoctrineListLayout.columns(rows, count: 1) == [rows])
    #expect(DoctrineListLayout.columns(Array(1...9), count: 3) == [[1, 2, 3], [4, 5, 6], [7, 8, 9]])
    // Fewer rows than columns give fewer columns, never empty ones.
    #expect(DoctrineListLayout.columns([1, 2], count: 4) == [[1], [2]])
    #expect(DoctrineListLayout.columns([1, 2, 3, 4, 5], count: 4) == [[1, 2], [3, 4], [5]])
    #expect(DoctrineListLayout.columns([Int](), count: 3).isEmpty)
    #expect(DoctrineListLayout.columns([1, 2], count: 0) == [[1, 2]])
  }
}
