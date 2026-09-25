import CryptoKit
// Ported from the archived EVE Nexus CSV reader/parser; wire formats retained.
import Foundation

public enum InventoryCSVEncodingOption: String, CaseIterable, Sendable {
  case automatic
  case utf8
  case windows1252
  case isoLatin1
}

public enum InventoryCSVDetectedEncoding: String, Codable, Sendable {
  case utf8
  case utf16LittleEndian
  case utf16BigEndian
  case windows1252
  case isoLatin1
}

public enum InventoryCSVDelimiterOption: String, CaseIterable, Sendable {
  case automatic
  case comma
  case semicolon
  case tab
}

public enum InventoryCSVDetectedDelimiter: String, Codable, Sendable {
  case comma
  case semicolon
  case tab
}

public enum InventoryCSVQuantityFormat: String, CaseIterable, Sendable {
  case integer
  case decimalComma
  case decimalPoint
}

public struct InventoryCSVParserOptions: Equatable, Sendable {
  public let encoding: InventoryCSVEncodingOption
  public let delimiter: InventoryCSVDelimiterOption

  public init(
    encoding: InventoryCSVEncodingOption = .automatic,
    delimiter: InventoryCSVDelimiterOption = .automatic
  ) {
    self.encoding = encoding
    self.delimiter = delimiter
  }
}

public struct InventoryCSVImportSource: Equatable, Sendable {
  public let displayName: String
  public let data: Data
  public let sha256: String

  public init(displayName: String, data: Data, sha256: String) {
    self.displayName =
      displayName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.data = data
    self.sha256 = sha256.lowercased()
  }
}

public struct InventoryCSVParsedRow: Equatable, Sendable {
  public let rowNumber: Int
  public let fields: [String]

  public init(rowNumber: Int, fields: [String]) {
    self.rowNumber = rowNumber
    self.fields = fields
  }
}

public struct InventoryCSVParsedDocument: Equatable, Sendable {
  public let headers: [String]
  public let rows: [InventoryCSVParsedRow]
  public let encoding: InventoryCSVDetectedEncoding
  public let delimiter: InventoryCSVDetectedDelimiter

  public init(
    headers: [String],
    rows: [InventoryCSVParsedRow],
    encoding: InventoryCSVDetectedEncoding,
    delimiter: InventoryCSVDetectedDelimiter
  ) {
    self.headers = headers
    self.rows = rows
    self.encoding = encoding
    self.delimiter = delimiter
  }
}

public protocol InventoryCSVParsing: Sendable {
  func parse(
    source: InventoryCSVImportSource,
    options: InventoryCSVParserOptions
  ) throws -> InventoryCSVParsedDocument
}

public protocol InventoryCSVFileReading: Sendable {
  func read(url: URL) throws -> InventoryCSVImportSource
}

public enum InventoryCSVImportError: Error, Equatable, Sendable {
  case invalidSourceName
  case invalidSourceHash
  case emptyFile
  case fileTooLarge(maximumBytes: Int)
  case notRegularFile
  case unreadableEncoding
  case containsNullByte
  case ambiguousDelimiter
  case malformedQuotedField(line: Int)
  case missingHeader
  case emptyHeader(column: Int)
  case duplicateHeader(String)
  case tooManyColumns(maximum: Int)
  case tooManyRows(maximum: Int)
  case invalidColumnMapping
  case inactiveLocation(UUID)
  case missingConflictDecision(row: Int)
  case noChangesSelected
  case confirmationRequired
  case stalePreview
  case invalidStoredImportReport(UUID)
}

public struct LocalInventoryCSVFileReader: InventoryCSVFileReading, Sendable {
  public static let maximumFileSize = 16 * 1_024 * 1_024

  public init() {}

  public func read(url: URL) throws -> InventoryCSVImportSource {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    let values = try url.resourceValues(
      forKeys: [.isRegularFileKey, .fileSizeKey]
    )
    guard values.isRegularFile == true else {
      throw InventoryCSVImportError.notRegularFile
    }
    if let fileSize = values.fileSize,
      fileSize > Self.maximumFileSize
    {
      throw InventoryCSVImportError.fileTooLarge(
        maximumBytes: Self.maximumFileSize
      )
    }
    let data = try Data(
      contentsOf: url,
      options: [.mappedIfSafe, .uncached]
    )
    guard data.count <= Self.maximumFileSize else {
      throw InventoryCSVImportError.fileTooLarge(
        maximumBytes: Self.maximumFileSize
      )
    }
    return InventoryCSVImportSource(
      displayName: url.lastPathComponent,
      data: data,
      sha256: SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined()
    )
  }
}

public struct DelimitedInventoryCSVParser: InventoryCSVParsing, Sendable {
  public static let maximumFileSize = 16 * 1_024 * 1_024
  public static let maximumRows = 100_000
  public static let maximumColumns = 64

  public init() {}

  public func parse(
    source: InventoryCSVImportSource,
    options: InventoryCSVParserOptions
  ) throws -> InventoryCSVParsedDocument {
    guard !source.data.isEmpty else {
      throw InventoryCSVImportError.emptyFile
    }
    guard source.data.count <= Self.maximumFileSize else {
      throw InventoryCSVImportError.fileTooLarge(
        maximumBytes: Self.maximumFileSize
      )
    }
    let decoded = try decode(source.data, choice: options.encoding)
    guard !decoded.text.contains("\0") else {
      throw InventoryCSVImportError.containsNullByte
    }
    let delimiter = try resolveDelimiter(
      in: decoded.text,
      choice: options.delimiter
    )
    let records = try parseRecords(
      decoded.text,
      delimiter: delimiter.character
    )
    guard let headerRecord = records.first else {
      throw InventoryCSVImportError.missingHeader
    }
    let headers = headerRecord.fields.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !headers.isEmpty else {
      throw InventoryCSVImportError.missingHeader
    }
    guard headers.count <= Self.maximumColumns else {
      throw InventoryCSVImportError.tooManyColumns(
        maximum: Self.maximumColumns
      )
    }
    for (index, header) in headers.enumerated() where header.isEmpty {
      throw InventoryCSVImportError.emptyHeader(column: index + 1)
    }
    var normalizedHeaders: Set<String> = []
    for header in headers {
      let normalized = header.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX"))
      guard normalizedHeaders.insert(normalized).inserted else {
        throw InventoryCSVImportError.duplicateHeader(header)
      }
    }
    let dataRecords = Array(records.dropFirst())
    guard dataRecords.count <= Self.maximumRows else {
      throw InventoryCSVImportError.tooManyRows(
        maximum: Self.maximumRows
      )
    }
    return InventoryCSVParsedDocument(
      headers: headers,
      rows: dataRecords.map {
        InventoryCSVParsedRow(
          rowNumber: $0.startLine,
          fields: $0.fields
        )
      },
      encoding: decoded.encoding,
      delimiter: delimiter
    )
  }

  private func decode(
    _ data: Data,
    choice: InventoryCSVEncodingOption
  ) throws -> (text: String, encoding: InventoryCSVDetectedEncoding) {
    let decoded: (String?, InventoryCSVDetectedEncoding)
    switch choice {
    case .utf8:
      decoded = (String(data: data, encoding: .utf8), .utf8)
    case .windows1252:
      decoded = (
        String(data: data, encoding: .windowsCP1252),
        .windows1252
      )
    case .isoLatin1:
      decoded = (String(data: data, encoding: .isoLatin1), .isoLatin1)
    case .automatic:
      if data.starts(with: [0xEF, 0xBB, 0xBF]) {
        decoded = (String(data: data, encoding: .utf8), .utf8)
      } else if data.starts(with: [0xFF, 0xFE]) {
        decoded = (
          String(data: data, encoding: .utf16LittleEndian),
          .utf16LittleEndian
        )
      } else if data.starts(with: [0xFE, 0xFF]) {
        decoded = (
          String(data: data, encoding: .utf16BigEndian),
          .utf16BigEndian
        )
      } else if let text = String(data: data, encoding: .utf8) {
        decoded = (text, .utf8)
      } else {
        decoded = (
          String(data: data, encoding: .windowsCP1252),
          .windows1252
        )
      }
    }
    guard var text = decoded.0 else {
      throw InventoryCSVImportError.unreadableEncoding
    }
    if text.first == "\u{FEFF}" {
      text.removeFirst()
    }
    return (text, decoded.1)
  }

  private func resolveDelimiter(
    in text: String,
    choice: InventoryCSVDelimiterOption
  ) throws -> InventoryCSVDetectedDelimiter {
    switch choice {
    case .comma:
      return .comma
    case .semicolon:
      return .semicolon
    case .tab:
      return .tab
    case .automatic:
      let counts = delimiterCounts(inFirstRecordOf: text)
      guard let maximum = counts.values.max(), maximum > 0 else {
        throw InventoryCSVImportError.ambiguousDelimiter
      }
      let matches = counts.filter { $0.value == maximum }.map(\.key)
      guard matches.count == 1, let result = matches.first else {
        throw InventoryCSVImportError.ambiguousDelimiter
      }
      return result
    }
  }

  private func delimiterCounts(
    inFirstRecordOf text: String
  ) -> [InventoryCSVDetectedDelimiter: Int] {
    var counts: [InventoryCSVDetectedDelimiter: Int] = [
      .comma: 0,
      .semicolon: 0,
      .tab: 0,
    ]
    var inQuotes = false
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      if character == "\"" {
        let next = text.index(after: index)
        if inQuotes, next < text.endIndex, text[next] == "\"" {
          index = text.index(after: next)
          continue
        }
        inQuotes.toggle()
      } else if !inQuotes {
        if isCSVLineBreak(character) {
          break
        }
        switch character {
        case ",":
          counts[.comma, default: 0] += 1
        case ";":
          counts[.semicolon, default: 0] += 1
        case "\t":
          counts[.tab, default: 0] += 1
        default:
          break
        }
      }
      index = text.index(after: index)
    }
    return counts
  }

  private func parseRecords(
    _ text: String,
    delimiter: Character
  ) throws -> [CSVRecord] {
    var records: [CSVRecord] = []
    var fields: [String] = []
    var field = ""
    var inQuotes = false
    var quoteClosed = false
    var line = 1
    var recordStartLine = 1
    var index = text.startIndex

    func isBlank(_ candidate: [String]) -> Bool {
      candidate.allSatisfy {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    }

    while index < text.endIndex {
      let character = text[index]
      let next = text.index(after: index)
      if inQuotes {
        if character == "\"" {
          if next < text.endIndex, text[next] == "\"" {
            field.append("\"")
            index = text.index(after: next)
            continue
          }
          inQuotes = false
          quoteClosed = true
        } else {
          field.append(character)
          if isCSVLineBreak(character) {
            line += 1
          }
        }
        index = next
        continue
      }

      if quoteClosed {
        if character == delimiter {
          fields.append(field)
          field = ""
          quoteClosed = false
        } else if isCSVLineBreak(character) {
          fields.append(field)
          if !isBlank(fields) {
            records.append(
              CSVRecord(
                startLine: recordStartLine,
                fields: fields
              )
            )
          }
          fields = []
          field = ""
          quoteClosed = false
          if character == "\r",
            next < text.endIndex,
            text[next] == "\n"
          {
            index = text.index(after: next)
          } else {
            index = next
          }
          line += 1
          recordStartLine = line
          continue
        } else if character == " " || character == "\t" {
          // Whitespace after a quoted field is ignored.
        } else {
          throw InventoryCSVImportError.malformedQuotedField(
            line: line
          )
        }
        index = next
        continue
      }

      if character == delimiter {
        fields.append(field)
        field = ""
      } else if character == "\"" {
        guard field.isEmpty else {
          throw InventoryCSVImportError.malformedQuotedField(
            line: line
          )
        }
        inQuotes = true
      } else if isCSVLineBreak(character) {
        fields.append(field)
        if !isBlank(fields) {
          records.append(
            CSVRecord(
              startLine: recordStartLine,
              fields: fields
            )
          )
        }
        fields = []
        field = ""
        if character == "\r",
          next < text.endIndex,
          text[next] == "\n"
        {
          index = text.index(after: next)
        } else {
          index = next
        }
        line += 1
        recordStartLine = line
        continue
      } else {
        field.append(character)
      }
      index = next
    }
    guard !inQuotes else {
      throw InventoryCSVImportError.malformedQuotedField(line: line)
    }
    fields.append(field)
    if !isBlank(fields) {
      records.append(
        CSVRecord(startLine: recordStartLine, fields: fields)
      )
    }
    return records
  }
}

private struct CSVRecord {
  let startLine: Int
  let fields: [String]
}

private func isCSVLineBreak(_ character: Character) -> Bool {
  character == "\n" || character == "\r" || character == "\r\n"
}

extension InventoryCSVDetectedDelimiter {
  fileprivate var character: Character {
    switch self {
    case .comma:
      ","
    case .semicolon:
      ";"
    case .tab:
      "\t"
    }
  }
}
