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
