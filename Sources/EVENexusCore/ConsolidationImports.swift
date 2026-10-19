import Foundation

public enum ConsolidationImportKind: Sendable {
  case warehouse(UUID)
  case prices(UUID)
}
public enum ConsolidationImportConflict: String, CaseIterable, Sendable { case replace, skip }

public enum ConsolidationImports {
  public static func preview(
    base: ConsolidationWorkspace, source: InventoryCSVImportSource,
    options: InventoryCSVParserOptions = .init(), kind: ConsolidationImportKind,
    conflict: ConsolidationImportConflict, decisions: [Int64: ConsolidationImportConflict] = [:],
    skipInvalidRows: Bool = false, catalogNames: [Int64: String],
    typeColumn: String = "type_id", valueColumn: String? = nil
  ) throws -> ConsolidationPreview {
    let document = try DelimitedInventoryCSVParser().parse(source: source, options: options)
    let headers = document.headers.map { $0.lowercased().replacingOccurrences(of: "_", with: "") }
    let expectedValue =
      valueColumn
      ?? {
        if case .warehouse = kind { return "quantity" }
        return "price"
      }()
    guard
      let typeIndex = headers.firstIndex(
        of: typeColumn.lowercased().replacingOccurrences(of: "_", with: "")),
      let valueIndex = headers.firstIndex(
        of: expectedValue.lowercased().replacingOccurrences(of: "_", with: ""))
    else {
      throw ConsolidationError.invalid(
        "Die CSV benötigt Spalten \(typeColumn) und \(expectedValue).")
    }
    var rows: [(Int, Int64, String)] = []
    var skipped: [String] = []
    let typeCounts = Dictionary(
      grouping: document.rows.compactMap { row in
        row.fields.indices.contains(typeIndex)
          ? Int64(row.fields[typeIndex].trimmingCharacters(in: .whitespaces)) : nil
      }, by: { $0 }
    ).mapValues(\.count)
    for row in document.rows {
      guard row.fields.count == document.headers.count,
        let type = Int64(row.fields[typeIndex].trimmingCharacters(in: .whitespaces)), type > 0,
        let name = catalogNames[type], !name.isEmpty
      else {
        if skipInvalidRows {
          skipped.append("Zeile \(row.rowNumber): ungültiger Typ/Spaltenzahl, ausgelassen.")
          continue
        }
        throw ConsolidationError.invalid(
          "Zeile \(row.rowNumber): unbekannter oder unveröffentlichter Typ bzw. falsche Spaltenzahl."
        )
      }
      guard typeCounts[type] == 1 else {
        if skipInvalidRows {
          skipped.append("Zeile \(row.rowNumber): doppelter Typ \(type), ausgelassen.")
          continue
        }
        throw ConsolidationError.invalid(
          "Zeile \(row.rowNumber): Typ \(type) ist doppelt vorhanden.")
      }
      rows.append(
        (row.rowNumber, type, row.fields[valueIndex].trimmingCharacters(in: .whitespaces)))
    }
    guard !rows.isEmpty else {
      throw ConsolidationError.invalid("Die CSV enthält keine Datenzeilen.")
    }
    var candidate = base
    var outcomes: [String] = skipped
    switch kind {
    case .warehouse(let id):
      guard let i = candidate.warehouses.firstIndex(where: { $0.id == id && !$0.archived }) else {
        throw ConsolidationError.stalePreview
      }
      for (line, type, text) in rows {
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let quantity = Int64(text),
          quantity > 0
        else {
          if skipInvalidRows {
            outcomes.append("Zeile \(line): ungültige Menge, ausgelassen.")
            continue
          }
          throw ConsolidationError.invalid(
            "Zeile \(line): erwartet wird eine positive ganze Menge ohne Tausendertrennzeichen.")
        }
        let skip =
          candidate.warehouses[i].stock[type] != nil && (decisions[type] ?? conflict) == .skip
        if !skip {
          candidate.warehouses[i].stock[type] = quantity
          candidate.warehouses[i].names[type] = catalogNames[type]
        }
        outcomes.append(
          "Zeile \(line), Typ \(type): \(skip ? "übersprungen" : "setzen auf \(quantity)").")
      }
    case .prices(let id):
      guard let i = candidate.priceProfiles.firstIndex(where: { $0.id == id }) else {
        throw ConsolidationError.stalePreview
      }
      for (line, type, text) in rows {
        let amount: ISKAmount
        do { amount = try ISKAmount.parse(text) } catch {
          if skipInvalidRows {
            outcomes.append("Zeile \(line): ungültiger Preis, ausgelassen.")
            continue
          }
          throw ConsolidationError.invalid(
            "Zeile \(line): ungültiger positiver ISK-Preis (maximal zwei Dezimalstellen).")
        }
        let skip =
          candidate.priceProfiles[i].prices[type] != nil && (decisions[type] ?? conflict) == .skip
        if !skip {
          candidate.priceProfiles[i].prices[type] = amount
          candidate.priceProfiles[i].names[type] = catalogNames[type]
        }
        outcomes.append(
          "Zeile \(line), Typ \(type): \(skip ? "übersprungen" : amount.displayText + " ISK").")
      }
      candidate.priceProfiles[i].source =
        "CSV: \(URL(fileURLWithPath: source.displayName).lastPathComponent) / \(source.sha256)"
    }
    candidate.imports.append(
      ConsolidationImportReport(
        filename: URL(fileURLWithPath: URL(fileURLWithPath: source.displayName).lastPathComponent)
          .lastPathComponent,
        sha256: source.sha256, encoding: document.encoding.rawValue,
        delimiter: document.delimiter.rawValue, outcomes: outcomes))
    return try ConsolidationPreview(base: base, summary: outcomes) { $0 = candidate }
  }
}
