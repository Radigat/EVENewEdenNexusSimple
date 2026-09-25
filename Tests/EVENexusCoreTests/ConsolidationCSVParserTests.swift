// Adapted from the archived EVE Nexus parser regression suite.
import CryptoKit
import Foundation
import XCTest

@testable import EVENexusCore

final class InventoryCSVParserTests: XCTestCase {
  private let parser = DelimitedInventoryCSVParser()

  func testParsesVersionedSemicolonFixtureWithAutomaticFormat() throws {
    let data = Data("type_id;quantity;item_name\n34;1500;Tritanium\n36;25;Mexallon\n".utf8)

    let document = try parser.parse(
      source: source(data: data),
      options: .init()
    )

    XCTAssertEqual(
      document.headers,
      ["type_id", "quantity", "item_name"]
    )
    XCTAssertEqual(document.encoding, .utf8)
    XCTAssertEqual(document.delimiter, .semicolon)
    XCTAssertEqual(document.rows.map(\.rowNumber), [2, 3])
    XCTAssertEqual(document.rows[0].fields, ["34", "1500", "Tritanium"])
  }

  func testParsesQuotesEscapesAndMultilineCRLF() throws {
    let csv =
      "type_id\tquantity\titem_name\r\n"
      + "34\t10\t\"Tritanium \"\"Prime\"\"\"\r\n"
      + "36\t20\t\"Mexal\r\nlon\"\r\n"

    let document = try parser.parse(
      source: source(data: Data(csv.utf8)),
      options: .init()
    )

    XCTAssertEqual(document.encoding, .utf8)
    XCTAssertEqual(document.delimiter, .tab)
    XCTAssertEqual(document.rows.count, 2)
    XCTAssertEqual(document.rows[0].fields[2], "Tritanium \"Prime\"")
    XCTAssertEqual(document.rows[1].rowNumber, 3)
    XCTAssertEqual(document.rows[1].fields[2], "Mexal\r\nlon")
  }

  func testDetectsUTF16LittleEndianBOM() throws {
    let csv = "type_id;quantity\r\n34;10\r\n"
    var data = Data([0xFF, 0xFE])
    data.append(
      try XCTUnwrap(csv.data(using: .utf16LittleEndian))
    )

    let document = try parser.parse(
      source: source(data: data),
      options: .init()
    )

    XCTAssertEqual(document.encoding, .utf16LittleEndian)
    XCTAssertEqual(document.delimiter, .semicolon)
    XCTAssertEqual(document.rows.first?.fields, ["34", "10"])
  }

  func testSupportsWindows1252AndManualDelimiter() throws {
    let text = "type_id;quantity;item_name\n34;1;Café\n"
    let data = try XCTUnwrap(
      text.data(using: .windowsCP1252, allowLossyConversion: false)
    )

    let document = try parser.parse(
      source: source(data: data),
      options: .init(
        encoding: .windows1252,
        delimiter: .semicolon
      )
    )

    XCTAssertEqual(document.encoding, .windows1252)
    XCTAssertEqual(document.rows.first?.fields.last, "Café")

    let automatic = try parser.parse(
      source: source(data: data),
      options: .init()
    )
    XCTAssertEqual(automatic.encoding, .windows1252)
  }

  func testDetectsUTF16BigEndianBOM() throws {
    let csv = "type_id,quantity\n34,10\n"
    var data = Data([0xFE, 0xFF])
    data.append(
      try XCTUnwrap(csv.data(using: .utf16BigEndian))
    )

    let document = try parser.parse(
      source: source(data: data),
      options: .init()
    )

    XCTAssertEqual(document.encoding, .utf16BigEndian)
    XCTAssertEqual(document.rows.first?.fields, ["34", "10"])
  }

  func testRejectsAmbiguousDelimiterMalformedQuoteAndDuplicateHeader() {
    assertParserError(
      "type_id\n34\n",
      expected: .ambiguousDelimiter
    )
    assertParserError(
      "type_id,quantity\n34,\"10\n",
      expected: .malformedQuotedField(line: 3)
    )
    assertParserError(
      "type_id,TYPE_ID\n34,10\n",
      expected: .duplicateHeader("TYPE_ID")
    )
    assertParserError(
      "type_id,quantity\0\n34,10\n",
      expected: .containsNullByte
    )
  }

  func testRejectsRowsAndFilesAboveDocumentedLimits() {
    let acceptedRows = Array(
      repeating: "34,1",
      count: 10_000
    ).joined(separator: "\n")
    XCTAssertEqual(
      try parser.parse(
        source: source(
          data: Data(
            "type_id,quantity\n\(acceptedRows)\n".utf8
          )
        ),
        options: .init()
      ).rows.count,
      10_000
    )

    let rows = Array(
      repeating: "34,1",
      count: DelimitedInventoryCSVParser.maximumRows + 1
    ).joined(separator: "\n")
    assertParserError(
      "type_id,quantity\n\(rows)\n",
      expected: .tooManyRows(
        maximum: DelimitedInventoryCSVParser.maximumRows
      )
    )

    let oversized = Data(
      repeating: 0x31,
      count: DelimitedInventoryCSVParser.maximumFileSize + 1
    )
    XCTAssertThrowsError(
      try parser.parse(
        source: source(data: oversized),
        options: .init()
      )
    ) {
      XCTAssertEqual(
        $0 as? InventoryCSVImportError,
        .fileTooLarge(
          maximumBytes: DelimitedInventoryCSVParser.maximumFileSize
        )
      )
    }
  }

  func testLocalFileReaderAcceptsRegularFileAndRejectsDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "EVE-Consolidation-CSV-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("bestand.csv")
    let data = Data("type_id,quantity\n34,1\n".utf8)
    try data.write(to: url, options: .atomic)

    let loaded = try LocalInventoryCSVFileReader().read(url: url)

    XCTAssertEqual(loaded.displayName, "bestand.csv")
    XCTAssertEqual(loaded.data, data)
    XCTAssertEqual(
      loaded.sha256,
      SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined()
    )
    XCTAssertThrowsError(
      try LocalInventoryCSVFileReader().read(url: directory)
    ) {
      XCTAssertEqual(
        $0 as? InventoryCSVImportError,
        .notRegularFile
      )
    }
  }

  private func assertParserError(
    _ text: String,
    expected: InventoryCSVImportError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try parser.parse(
        source: source(data: Data(text.utf8)),
        options: .init()
      ),
      file: file,
      line: line
    ) {
      XCTAssertEqual(
        $0 as? InventoryCSVImportError,
        expected,
        file: file,
        line: line
      )
    }
  }

  private func source(data: Data) -> InventoryCSVImportSource {
    InventoryCSVImportSource(
      displayName: "bestand.csv",
      data: data,
      sha256: String(repeating: "a", count: 64)
    )
  }
}
