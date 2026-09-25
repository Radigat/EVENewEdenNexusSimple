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

public struct ProjectBudgetQuote: Sendable {
  public var materialPurchases: Double?
  public var logistics: Double?
  public var production: Double?
  public var missingPrices: [Int64]
  public var total: Double? {
    guard let materialPurchases, let logistics, let production else { return nil }
    let amount = materialPurchases + logistics + production
    return amount.isFinite && amount >= 0 ? amount : nil
  }
}

extension ConsolidationWorkspace {
  public mutating func synchronizePurchases(projectID: UUID, plan: IndustryPlanSnapshot) throws {
    guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
      throw ConsolidationError.stalePreview
    }
    projects[index].planSnapshot = try JSONEncoder().encode(plan)
    projects[index].updatedAt = .now
    let types = Set(plan.materials.map(\.typeID))
    for i in purchases.indices
    where purchases[i].projectID == projectID && !types.contains(purchases[i].typeID) {
      purchases[i].planned = 0
    }
    for material in plan.materials {
      if let i = purchases.firstIndex(where: {
        $0.projectID == projectID && $0.typeID == material.typeID
      }) {
        purchases[i].planned = material.toBuy
        purchases[i].name = material.name
      } else if material.toBuy > 0 {
        purchases.append(
          ProjectPurchase(
            projectID: projectID, typeID: material.typeID, name: material.name,
            planned: material.toBuy))
      }
    }
  }
  public func budget(projectID: UUID, logistics: Double?, production: Double?, at date: Date = .now)
    throws -> ProjectBudgetQuote
  {
    guard let p = projects.first(where: { $0.id == projectID }) else {
      throw ConsolidationError.stalePreview
    }
    let plan = p.planSnapshot.flatMap {
      try? JSONDecoder().decode(IndustryPlanSnapshot.self, from: $0)
    }
    let profile = priceProfiles.first { $0.id == p.priceProfileID }
    var total = 0.0
    var missing: [Int64] = []
    for row in purchases where row.projectID == projectID && row.remaining > 0 {
      if p.priceProfileID != nil {
        if let price = profile?.price(row.typeID, at: date) {
          total += Double(try Self.multiply(price.hundredths, row.remaining)) / 100
        } else {
          missing.append(row.typeID)
        }
      } else if let quote = plan?.materials.first(where: { $0.typeID == row.typeID })?.quote,
        let unitPrice = quote.weightedUnitPrice, unitPrice.isFinite, unitPrice >= 0
      {
        total += unitPrice * Double(row.remaining)
      } else {
        missing.append(row.typeID)
      }
    }
    return ProjectBudgetQuote(
      materialPurchases: missing.isEmpty && total.isFinite ? total : nil,
      logistics: p.logisticsOverrideCents.map { Double($0) / 100 } ?? logistics,
      production: p.productionOverrideCents.map { Double($0) / 100 } ?? production,
      missingPrices: missing.sorted())
  }
}
