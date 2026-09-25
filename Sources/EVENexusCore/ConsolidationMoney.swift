import Foundation

public enum ISKAmountValidationError: Error, Equatable, Sendable {
  case empty
  case invalidCharacters
  case invalidFractionDigits
  case notPositive
  case overflow
}

public struct ISKAmount:
  Hashable,
  Comparable,
  Codable,
  Sendable
{
  public static let scale: Int64 = 100

  public let hundredths: Int64

  public init(hundredths: Int64) throws {
    guard hundredths > 0 else {
      throw ISKAmountValidationError.notPositive
    }
    self.hundredths = hundredths
  }

  private enum CodingKeys: String, CodingKey { case hundredths }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(hundredths: values.decode(Int64.self, forKey: .hundredths))
  }
  public static func parse(_ text: String) throws -> ISKAmount {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw ISKAmountValidationError.empty
    }
    guard !value.contains(".") || !value.contains(",") else {
      throw ISKAmountValidationError.invalidCharacters
    }
    let separator: Character? = value.contains(",") ? "," : (value.contains(".") ? "." : nil)
    let parts: [Substring]
    if let separator {
      parts = value.split(
        separator: separator,
        omittingEmptySubsequences: false
      )
    } else {
      parts = [Substring(value)]
    }
    guard parts.count <= 2,
      let wholeText = parts.first,
      !wholeText.isEmpty,
      wholeText.allSatisfy(\.isNumber)
    else {
      throw ISKAmountValidationError.invalidCharacters
    }
    let fractionText = parts.count == 2 ? parts[1] : Substring()
    guard
      parts.count == 1
        || (!fractionText.isEmpty && fractionText.count <= 2)
    else {
      throw ISKAmountValidationError.invalidFractionDigits
    }
    guard fractionText.allSatisfy(\.isNumber) else {
      throw ISKAmountValidationError.invalidCharacters
    }
    guard let whole = Int64(wholeText) else {
      throw ISKAmountValidationError.overflow
    }
    let (scaledWhole, didOverflow) = whole.multipliedReportingOverflow(
      by: Self.scale
    )
    guard !didOverflow else {
      throw ISKAmountValidationError.overflow
    }
    let fraction: Int64
    switch fractionText.count {
    case 0:
      fraction = 0
    case 1:
      guard let digit = Int64(fractionText) else {
        throw ISKAmountValidationError.invalidCharacters
      }
      fraction = digit * 10
    default:
      guard let digits = Int64(fractionText) else {
        throw ISKAmountValidationError.invalidCharacters
      }
      fraction = digits
    }
    let (amount, additionOverflow) = scaledWhole.addingReportingOverflow(
      fraction
    )
    guard !additionOverflow else {
      throw ISKAmountValidationError.overflow
    }
    return try ISKAmount(hundredths: amount)
  }

  public var displayText: String {
    let whole = hundredths / Self.scale
    let fraction = hundredths % Self.scale
    return "\(whole).\(String(format: "%02lld", fraction))"
  }

  public static func < (lhs: ISKAmount, rhs: ISKAmount) -> Bool {
    lhs.hundredths < rhs.hundredths
  }
}
