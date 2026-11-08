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

/// Why the parser rejected the input. Each reason has one English format key
/// that the app translates; `%@` takes the parser limit in `arguments`.
public enum ProductionInputErrorReason: String, CaseIterable, Codable, Sendable {
  case inputTooLarge
  case tooManyJobs
  case missingFields
  case invalidBlueprintCost
  case missingBlueprintCost
  case missingFieldsBeforeBlueprintCost
  case invalidNumbers
  case productNameTooLong
  case wantNotPositive
  case wantTooLarge
  case efficiencyOutOfRange
  case noJobs

  public var format: String {
    switch self {
    case .inputTooLarge:
      "The production input is too large. Use at most %@ UTF-8 bytes."
    case .tooManyJobs:
      "At most %@ production jobs are accepted at once."
    case .missingFields:
      "Expected Product Want ME TE, optionally followed by BPC/BPO and its total ISK cost."
    case .invalidBlueprintCost:
      "Blueprint cost must be a non-negative ISK amount no greater than %@ after BPC or BPO."
    case .missingBlueprintCost:
      "Enter the total ISK cost after BPC or BPO."
    case .missingFieldsBeforeBlueprintCost:
      "Expected Product Want ME TE before the optional blueprint cost."
    case .invalidNumbers:
      "Product is required; Want, ME and TE must be integers."
    case .productNameTooLong:
      "The product name is too long. Use at most %@ UTF-8 bytes."
    case .wantNotPositive:
      "Want must be greater than zero."
    case .wantTooLarge:
      "Want must not exceed %@."
    case .efficiencyOutOfRange:
      "Manufacturing ME must be 0…10 and TE must be 0…20."
    case .noJobs:
      "Enter at least one production job."
    }
  }

  /// The parser limits the message names, in the order of `format`.
  public var arguments: [Int64] {
    switch self {
    case .inputTooLarge: [Int64(ProductionInputParser.maximumInputBytes)]
    case .tooManyJobs: [Int64(ProductionInputParser.maximumJobCount)]
    case .invalidBlueprintCost:
      [Int64(ProductionInputParser.maximumBlueprintCostISK)]
    case .productNameTooLong:
      [Int64(ProductionInputParser.maximumProductNameBytes)]
    case .wantTooLarge: [Int64(ProductionInputParser.maximumWantedQuantity)]
    case .missingFields, .missingBlueprintCost,
      .missingFieldsBeforeBlueprintCost, .invalidNumbers, .wantNotPositive,
      .efficiencyOutOfRange, .noJobs:
      []
    }
  }

  /// `format`, or its translation, with the limits in `locale`'s number
  /// format.
  public func text(format: String, locale: Locale) -> String {
    String(
      format: format,
      locale: locale,
      arguments: arguments.map { $0.formatted(.number.locale(locale)) }
    )
  }
}

public struct ProductionInputError: Identifiable, Error, Codable, Equatable,
  Sendable
{
  public let id: UUID
  public let lineNumber: Int
  public let input: String
  public let reason: ProductionInputErrorReason

  /// The English sentence; the app translates `reason` instead.
  public var message: String {
    reason.text(format: reason.format, locale: Locale(identifier: "en"))
  }

  public init(
    id: UUID = UUID(),
    lineNumber: Int,
    input: String,
    reason: ProductionInputErrorReason
  ) {
    self.id = id
    self.lineNumber = lineNumber
    self.input = input
    self.reason = reason
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
            reason: .inputTooLarge
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
            reason: .tooManyJobs
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
            reason: .missingFields
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
              reason: .invalidBlueprintCost
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
            reason: .missingBlueprintCost
          )
        )
        continue
      }
      guard fields.count >= 4 else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            reason: .missingFieldsBeforeBlueprintCost
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
            reason: .invalidNumbers
          )
        )
        continue
      }
      guard productName.utf8.count <= maximumProductNameBytes else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            reason: .productNameTooLong
          )
        )
        continue
      }
      guard wantedQuantity > 0 else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            reason: .wantNotPositive
          )
        )
        continue
      }
      guard wantedQuantity <= maximumWantedQuantity else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            reason: .wantTooLarge
          )
        )
        continue
      }
      guard (0...10).contains(me), (0...20).contains(te) else {
        errors.append(
          ProductionInputError(
            lineNumber: lineNumber,
            input: safeErrorInput(rawLine),
            reason: .efficiencyOutOfRange
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
          reason: .noJobs
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

  /// Removes the first line that describes the same job. `nil` when no line
  /// does, for example because the input changed since the calculation.
  public static func removing(
    _ request: ProductionRequestLine,
    from input: String
  ) -> String? {
    let match = ProductionInputParser.parse(input).requests.first {
      $0.productName.caseInsensitiveCompare(request.productName) == .orderedSame
        && $0.wantedQuantity == request.wantedQuantity
        && $0.materialEfficiency == request.materialEfficiency
        && $0.timeEfficiency == request.timeEfficiency
        && $0.blueprintKind == request.blueprintKind
        && $0.blueprintCostISK == request.blueprintCostISK
    }
    guard let match else { return nil }
    var lines = input.components(separatedBy: .newlines)
    guard lines.indices.contains(match.lineNumber - 1) else { return nil }
    lines.remove(at: match.lineNumber - 1)
    return lines.joined(separator: "\n")
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

/// Parses a nonnegative number copied from a localized UI. This stays in the
/// shared core because the Planner's parameter editor accepts both German and
/// English decimal and thousands separators.
public enum LocalizedNumberParser {
  public static func parseNonnegative(_ text: String) -> Double? {
    guard !text.contains("-") else { return nil }
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
}
