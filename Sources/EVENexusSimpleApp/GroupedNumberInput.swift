import SwiftUI

/// Shared editing format for typed prices, ISK amounts and quantities: the
/// integer part carries the app locale's thousands separator (German
/// `1.250.000,5`, English `1,250,000.5`) while the user types.
enum GroupedNumberText {
  static var locale: Locale { AppLocalization.currentLanguage.locale }

  /// Regroups typed number text while editing: thousands get the locale's
  /// grouping separator, the locale's decimal separator is kept (also
  /// trailing, so a fraction can still be typed). Other characters are
  /// dropped; `allowsFraction == false` drops the fraction part.
  static func editingText(
    _ text: String,
    locale: Locale = Self.locale,
    allowsFraction: Bool = true
  ) -> String {
    let decimal = locale.decimalSeparator ?? "."
    let grouping = locale.groupingSeparator ?? ","
    var integerDigits = ""
    var fractionDigits = ""
    var hasDecimal = false
    for character in text {
      if character.isASCII, character.isNumber {
        if hasDecimal { fractionDigits.append(character) } else { integerDigits.append(character) }
      } else if String(character) == decimal, !hasDecimal {
        hasDecimal = true
      }
    }
    if !allowsFraction {
      hasDecimal = false
      fractionDigits = ""
    }
    if integerDigits.count > 1 {
      integerDigits = String(integerDigits.drop { $0 == "0" })
      if integerDigits.isEmpty { integerDigits = "0" }
    }
    if hasDecimal, integerDigits.isEmpty { integerDigits = "0" }
    var grouped = ""
    for (offset, character) in integerDigits.enumerated() {
      if offset > 0, (integerDigits.count - offset) % 3 == 0 {
        grouped.append(grouping)
      }
      grouped.append(character)
    }
    return hasDecimal ? grouped + decimal + fractionDigits : grouped
  }

  /// Removes the locale's grouping separator and spaces so plain parsers
  /// (`Int64`, `ISKAmount.parse`) read grouped text; the decimal separator
  /// stays.
  static func ungrouped(_ text: String, locale: Locale = Self.locale) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: locale.groupingSeparator ?? ",", with: "")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\u{00A0}", with: "")
      .replacingOccurrences(of: "\u{202F}", with: "")
  }
}

private struct GroupedNumberInputModifier: ViewModifier {
  @Binding var text: String
  let allowsFraction: Bool

  func body(content: Content) -> some View {
    content.onChange(of: text, initial: true) { _, newValue in
      let grouped = GroupedNumberText.editingText(
        newValue,
        allowsFraction: allowsFraction
      )
      if grouped != newValue { text = grouped }
    }
  }
}

extension View {
  /// Groups the thousands of a price, amount or quantity field while typing
  /// (`GroupedNumberText.editingText`). Quantities pass
  /// `allowsFraction: false`.
  func groupedNumberInput(
    _ text: Binding<String>,
    allowsFraction: Bool = true
  ) -> some View {
    modifier(GroupedNumberInputModifier(text: text, allowsFraction: allowsFraction))
  }
}
