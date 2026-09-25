import Foundation

public struct ProductionRequestLine: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let lineNumber: Int
  public let productName: String
  public let wantedQuantity: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let blueprintKind: ManualBlueprintKind?
  public let blueprintCostISK: Double?

  public init(
    id: UUID = UUID(),
    lineNumber: Int,
    productName: String,
    wantedQuantity: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    blueprintKind: ManualBlueprintKind? = nil,
    blueprintCostISK: Double? = nil
  ) {
    self.id = id
    self.lineNumber = lineNumber
    self.productName = productName
    self.wantedQuantity = wantedQuantity
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.blueprintKind = blueprintKind
    self.blueprintCostISK = blueprintCostISK
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case lineNumber
    case productName
    case wantedQuantity
    case runs
    case materialEfficiency
    case timeEfficiency
    case blueprintKind
    case blueprintCostISK
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    lineNumber = try container.decode(Int.self, forKey: .lineNumber)
    productName = try container.decode(String.self, forKey: .productName)
    wantedQuantity =
      try container.decodeIfPresent(Int.self, forKey: .wantedQuantity)
      ?? container.decode(Int.self, forKey: .runs)
    materialEfficiency = try container.decode(
      Int.self,
      forKey: .materialEfficiency
    )
    timeEfficiency = try container.decode(Int.self, forKey: .timeEfficiency)
    blueprintKind = try container.decodeIfPresent(
      ManualBlueprintKind.self,
      forKey: .blueprintKind
    )
    blueprintCostISK = try container.decodeIfPresent(
      Double.self,
      forKey: .blueprintCostISK
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(lineNumber, forKey: .lineNumber)
    try container.encode(productName, forKey: .productName)
    try container.encode(wantedQuantity, forKey: .wantedQuantity)
    try container.encode(materialEfficiency, forKey: .materialEfficiency)
    try container.encode(timeEfficiency, forKey: .timeEfficiency)
    try container.encodeIfPresent(blueprintKind, forKey: .blueprintKind)
    try container.encodeIfPresent(blueprintCostISK, forKey: .blueprintCostISK)
  }
}

public struct ProductionInputError: Identifiable, Error, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public let lineNumber: Int
  public let input: String
  public let message: String

  public init(
    id: UUID = UUID(),
    lineNumber: Int,
    input: String,
    message: String
  ) {
    self.id = id
    self.lineNumber = lineNumber
    self.input = input
    self.message = message
  }
}

public struct ProductionParseResult: Codable, Equatable, Sendable {
  public let requests: [ProductionRequestLine]
  public let errors: [ProductionInputError]

  public var isValid: Bool { errors.isEmpty && !requests.isEmpty }
}

public enum ProductionInputParser {
  public static let maximumInputBytes = 1 * 1_024 * 1_024
  public static let maximumJobCount = 1_000
  public static let maximumProductNameBytes = 256
  public static let maximumWantedQuantity = 1_000_000_000
  public static let maximumBlueprintCostISK = 1_000_000_000_000_000_000.0

  public static func parse(_ text: String) -> ProductionParseResult {
    var requests: [ProductionRequestLine] = []
    var errors: [ProductionInputError] = []
    guard text.utf8.count <= maximumInputBytes else {
      return ProductionParseResult(
        requests: [],
        errors: [
          ProductionInputError(
            lineNumber: 1,
            input: "",
            message:
              "The production input is too large. Use at most \(maximumInputBytes) UTF-8 bytes."
          )
        ]
      )
    }

    for (offset, rawLine) in text.components(separatedBy: .newlines)
      .enumerated()
    {
      let lineNumber = offset + 1
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      guard requests.count < maximumJobCount else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: "",
            message:
              "At most \(maximumJobCount) production jobs are accepted at once."
          )
        )
        break
      }
      var fields = trimmed.split(whereSeparator: \.isWhitespace)
      guard fields.count >= 4 else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message:
              "Expected Product Want ME TE, optionally followed by BPC/BPO and its total ISK cost."
          )
        )
        continue
      }
      var blueprintKind: ManualBlueprintKind?
      var blueprintCostISK: Double?
      if fields.count >= 2,
        let kind = ManualBlueprintKind(
          rawValue: fields[fields.count - 2].uppercased()
        )
      {
        guard let cost = Double(fields.last!), cost.isFinite, cost >= 0,
          cost <= maximumBlueprintCostISK
        else {
          errors.append(
            ProductionInputError(
              lineNumber: lineNumber,
              input: safeErrorInput(rawLine),
              message:
                "Blueprint cost must be a non-negative ISK amount no greater than \(maximumBlueprintCostISK.formatted()) after BPC or BPO."
            )
          )
          continue
        }
        blueprintKind = kind
        blueprintCostISK = cost
        fields.removeLast(2)
      } else if fields.last.map({
        ManualBlueprintKind(rawValue: $0.uppercased()) != nil
      }) == true {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message: "Enter the total ISK cost after BPC or BPO."
          )
        )
        continue
      }
      guard fields.count >= 4 else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message:
              "Expected Product Want ME TE before the optional blueprint cost."
          )
        )
        continue
      }
      let productFields = fields.dropLast(3)
      let productName = productFields.joined(separator: " ")
      guard !productName.isEmpty,
        let wantedQuantity = Int(fields[fields.count - 3]),
        let me = Int(fields[fields.count - 2]),
        let te = Int(fields[fields.count - 1])
      else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message: "Product is required; Want, ME and TE must be integers."
          )
        )
        continue
      }
      guard productName.utf8.count <= maximumProductNameBytes else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message:
              "The product name is too long. Use at most \(maximumProductNameBytes) UTF-8 bytes."
          )
        )
        continue
      }
      guard wantedQuantity > 0 else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message: "Want must be greater than zero."
          )
        )
        continue
      }
      guard wantedQuantity <= maximumWantedQuantity else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message:
              "Want must not exceed \(maximumWantedQuantity.formatted())."
          )
        )
        continue
      }
      guard (0...10).contains(me), (0...20).contains(te) else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            message: "Manufacturing ME must be 0…10 and TE must be 0…20."
          )
        )
        continue
      }
      requests.append(
        ProductionRequestLine(
          lineNumber: lineNumber,
          productName: productName,
          wantedQuantity: wantedQuantity,
          materialEfficiency: me,
          timeEfficiency: te,
          blueprintKind: blueprintKind,
          blueprintCostISK: blueprintCostISK
        )
      )
    }

    if requests.isEmpty && errors.isEmpty {
      errors.append(
        ProductionInputError(
          lineNumber: 1,
          input: "",
          message: "Enter at least one production job."
        )
      )
    }
    return ProductionParseResult(requests: requests, errors: errors)
  }

  private static func safeErrorInput(_ value: String) -> String {
    String(value.prefix(512))
  }
}

public enum ProductionInputFormatter {
  public static func format(_ requests: [ProductionRequestLine]) -> String {
    requests.map(format).joined(separator: "\n")
  }

  public static func appending(_ line: String, to input: String) -> String {
    guard !line.isEmpty else { return input }
    if input.isEmpty || input.hasSuffix("\n") {
      return input + line
    }
    return input + "\n" + line
  }

  public static func manufacturingLine(
    productName: String,
    runs: Int,
    outputPerRun: Int64,
    materialEfficiency: Int,
    timeEfficiency: Int
  ) throws -> String {
    guard let acceptedRuns = Int64(exactly: runs), acceptedRuns > 0,
      outputPerRun > 0
    else {
      throw ProductionInputFormattingError.invalidRunQuantity
    }
    let multiplication = acceptedRuns.multipliedReportingOverflow(
      by: outputPerRun
    )
    guard !multiplication.overflow,
      multiplication.partialValue
        <= Int64(ProductionInputParser.maximumWantedQuantity),
      let wantedQuantity = Int(exactly: multiplication.partialValue)
    else {
      throw ProductionInputFormattingError.quantityLimitExceeded
    }
    let request = ProductionRequestLine(
      lineNumber: 1,
      productName: productName,
      wantedQuantity: wantedQuantity,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency
    )
    let line = format(request)
    guard ProductionInputParser.parse(line).isValid else {
      throw ProductionInputFormattingError.invalidSelection
    }
    return line
  }

  private static func format(_ request: ProductionRequestLine) -> String {
    var fields = [
      request.productName,
      String(request.wantedQuantity),
      String(request.materialEfficiency),
      String(request.timeEfficiency),
    ]
    if let kind = request.blueprintKind,
      let cost = request.blueprintCostISK
    {
      fields.append(kind.rawValue)
      fields.append(String(cost))
    }
    return fields.joined(separator: " ")
  }
}

public enum ProductionInputFormattingError: Error, Equatable, Sendable {
  case invalidRunQuantity
  case quantityLimitExceeded
  case invalidSelection
}

public enum RecursiveProductionLogisticsRoute: String, CaseIterable, Codable,
  Identifiable, Sendable
{
  case mainToHome
  case mainToHomeToMain

  public var id: Self { self }

  public var includesFinishedProductReturn: Bool {
    self == .mainToHomeToMain
  }
}

public struct RecursiveProductionImportLine: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let lineNumber: Int
  public let itemName: String
  public let quantity: Int
  public let groupName: String?
  public let volumeM3: Double?
  public let estimatedValueISK: Double?

  public init(
    id: UUID = UUID(),
    lineNumber: Int,
    itemName: String,
    quantity: Int,
    groupName: String? = nil,
    volumeM3: Double? = nil,
    estimatedValueISK: Double? = nil
  ) {
    self.id = id
    self.lineNumber = lineNumber
    self.itemName = itemName
    self.quantity = quantity
    self.groupName = groupName
    self.volumeM3 = volumeM3
    self.estimatedValueISK = estimatedValueISK
  }

  public func plannerRequest(
    materialEfficiency: Int,
    timeEfficiency: Int
  ) -> ProductionRequestLine {
    ProductionRequestLine(
      lineNumber: lineNumber,
      productName: itemName,
      wantedQuantity: quantity,
      materialEfficiency: materialEfficiency,
      timeEfficiency: timeEfficiency
    )
  }
}

public struct RecursiveProductionImportResult: Equatable, Sendable {
  public let lines: [RecursiveProductionImportLine]
  public let errors: [ProductionInputError]

  public var isValid: Bool { !lines.isEmpty && errors.isEmpty }

  public var estimatedValueISK: Double? {
    guard !lines.isEmpty,
      lines.allSatisfy({ $0.estimatedValueISK != nil })
    else { return nil }
    return lines.compactMap(\.estimatedValueISK).reduce(0, +)
  }
}

/// Parses the tab-separated item rows copied from the EVE client. Extra
/// columns such as slot are retained only as ignored display metadata; recipe,
/// volume and price calculations continue to use the application's SDE and
/// market snapshots.
public enum RecursiveProductionImportParser {
  public static func parse(_ text: String) -> RecursiveProductionImportResult {
    guard text.utf8.count <= ProductionInputParser.maximumInputBytes else {
      return RecursiveProductionImportResult(
        lines: [],
        errors: [
          ProductionInputError(
            lineNumber: 1,
            input: "",
            message:
              "The production input is too large. Use at most \(ProductionInputParser.maximumInputBytes) UTF-8 bytes."
          )
        ]
      )
    }

    var lines: [RecursiveProductionImportLine] = []
    var errors: [ProductionInputError] = []
    for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
      let lineNumber = offset + 1
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      guard lines.count < ProductionInputParser.maximumJobCount else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: "",
            message:
              "At most \(ProductionInputParser.maximumJobCount) production items are accepted at once."
          )
        )
        break
      }

      let tabFields = rawLine.components(separatedBy: "\t")
      let itemName: String
      let quantityText: String
      if tabFields.count >= 2 {
        itemName = tabFields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        quantityText = tabFields[1].trimmingCharacters(
          in: .whitespacesAndNewlines
        )
      } else {
        let fields = trimmed.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else {
          errors.append(
            error(
              lineNumber: lineNumber,
              input: rawLine,
              message:
                "Expected item name followed by quantity, or a tab-separated EVE item row."
            )
          )
          continue
        }
        itemName = fields.dropLast().joined(separator: " ")
        quantityText = String(fields.last!)
      }
      guard !itemName.isEmpty,
        itemName.utf8.count <= ProductionInputParser.maximumProductNameBytes,
        let quantity = parseInteger(quantityText),
        (1...ProductionInputParser.maximumWantedQuantity).contains(quantity)
      else {
        errors.append(
          error(
            lineNumber: lineNumber,
            input: rawLine,
            message:
              "Item is required and quantity must be a positive whole number within the Planner limit."
          )
        )
        continue
      }

      let group = tabFields.dropFirst(2).first.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }.flatMap { $0.isEmpty ? nil : $0 }
      let volume = tabFields.first(where: {
        containsUnit($0, unit: "m3")
          || containsUnit($0, unit: "m³")
      }).flatMap(parseNumberFromField)
      let value = tabFields.first(where: { containsUnit($0, unit: "isk") })
        .flatMap(parseNumberFromField)
      lines.append(
        RecursiveProductionImportLine(
          lineNumber: lineNumber,
          itemName: itemName,
          quantity: quantity,
          groupName: group,
          volumeM3: volume,
          estimatedValueISK: value
        )
      )
    }

    if lines.isEmpty && errors.isEmpty {
      errors.append(
        ProductionInputError(
          lineNumber: 1,
          input: "",
          message: "Paste at least one EVE item row."
        )
      )
    }
    return RecursiveProductionImportResult(lines: lines, errors: errors)
  }

  public static func parseLocalizedNumber(_ text: String) -> Double? {
    let filtered = text.filter { $0.isNumber || $0 == "." || $0 == "," }
    guard !filtered.isEmpty else { return nil }
    let lastDot = filtered.lastIndex(of: ".")
    let lastComma = filtered.lastIndex(of: ",")
    let normalized: String
    if let lastDot, let lastComma {
      if lastComma > lastDot {
        normalized = filtered.replacingOccurrences(of: ".", with: "")
          .replacingOccurrences(of: ",", with: ".")
      } else {
        normalized = filtered.replacingOccurrences(of: ",", with: "")
      }
    } else if filtered.contains(",") {
      normalized = normalizeSingleSeparator(filtered, separator: ",")
    } else if filtered.contains(".") {
      normalized = normalizeSingleSeparator(filtered, separator: ".")
    } else {
      normalized = filtered
    }
    guard let value = Double(normalized), value.isFinite, value >= 0 else {
      return nil
    }
    return value
  }

  private static func parseInteger(_ text: String) -> Int? {
    guard let value = parseLocalizedNumber(text),
      value.rounded() == value,
      value <= Double(Int.max)
    else { return nil }
    return Int(value)
  }

  private static func containsUnit(_ text: String, unit: String) -> Bool {
    text.localizedCaseInsensitiveContains(unit)
  }

  private static func parseNumberFromField(_ text: String) -> Double? {
    let withoutUnit =
      text
      .replacingOccurrences(of: "ISK", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "m3", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "m³", with: "", options: .caseInsensitive)
    return parseLocalizedNumber(withoutUnit)
  }

  private static func normalizeSingleSeparator(
    _ text: String,
    separator: Character
  ) -> String {
    let parts = text.split(separator: separator, omittingEmptySubsequences: false)
    guard parts.count > 1 else { return text }
    if parts.count > 2 || parts.last?.count == 3 {
      return parts.joined()
    }
    return parts.joined(separator: ".")
  }

  private static func error(
    lineNumber: Int,
    input: String,
    message: String
  ) -> ProductionInputError {
    ProductionInputError(
      lineNumber: lineNumber,
      input: String(input.prefix(512)),
      message: message
    )
  }
}
