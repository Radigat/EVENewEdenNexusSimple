import Foundation

// Stock sale comparison (LAGERVERKAUF_PLAN.md, section C): owned items are
// compared with the cost of producing them anew for the chosen hub. The new
// production cost reuses the Hub Opportunities cost chain; the minimum prices
// invert the existing net-revenue rules for an own sell order and a direct
// sale into a buy order.

// MARK: Paste parsing

/// One interpretation of a pasted line: the item name and its quantity.
public struct StockSaleNameCandidate: Equatable, Sendable {
  public let name: String
  public let quantity: Int64

  public init(name: String, quantity: Int64) {
    self.name = name
    self.quantity = quantity
  }
}

/// A non-empty pasted line with its interpretations in priority order. The
/// first candidate whose name resolves in the SDE catalog wins.
public struct StockSalePasteLine: Equatable, Sendable {
  public let lineNumber: Int
  public let text: String
  public let candidates: [StockSaleNameCandidate]

  public init(lineNumber: Int, text: String, candidates: [StockSaleNameCandidate]) {
    self.lineNumber = lineNumber
    self.text = text
    self.candidates = candidates
  }
}

public enum StockSalePasteErrorReason: String, Codable, Equatable, Error, Sendable {
  case inputTooLarge
  case tooManyLines
  case missingName
  case nameTooLong
  case invalidQuantity
}

public struct StockSalePasteError: Equatable, Sendable {
  public let lineNumber: Int
  public let text: String
  public let reason: StockSalePasteErrorReason

  public init(lineNumber: Int, text: String, reason: StockSalePasteErrorReason) {
    self.lineNumber = lineNumber
    self.text = text
    self.reason = reason
  }
}

public struct StockSalePasteResult: Equatable, Sendable {
  public let lines: [StockSalePasteLine]
  public let errors: [StockSalePasteError]
}

/// Parses text copied from the EVE client together with item quantities.
///
/// - A line containing a tab (inventory list view) carries the name in the
///   first and the quantity in the second column; an empty quantity is 1.
/// - Any other line is first tried as a complete name with quantity 1, then
///   as `Name x Quantity` or `Name Quantity`.
/// - Quantities may contain the thousands separators `.`, `,`, spaces, NBSP
///   and apostrophes of English and German clients.
public enum StockSalePasteParser {
  public static let maximumInputBytes = ProductionInputParser.maximumInputBytes
  public static let maximumLineCount = ProductionInputParser.maximumJobCount
  public static let maximumNameBytes = ProductionInputParser.maximumProductNameBytes
  public static let maximumQuantity = Int64(ProductionInputParser.maximumWantedQuantity)

  public static func parse(_ text: String) -> StockSalePasteResult {
    guard text.utf8.count <= maximumInputBytes else {
      return StockSalePasteResult(
        lines: [],
        errors: [StockSalePasteError(lineNumber: 1, text: "", reason: .inputTooLarge)]
      )
    }
    var lines: [StockSalePasteLine] = []
    var errors: [StockSalePasteError] = []
    var acceptedLineCount = 0
    for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
      let lineNumber = offset + 1
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      acceptedLineCount += 1
      guard acceptedLineCount <= maximumLineCount else {
        errors.append(StockSalePasteError(lineNumber: lineNumber, text: "", reason: .tooManyLines))
        break
      }
      let safeText = String(trimmed.prefix(512))
      switch candidates(for: trimmed) {
      case .success(let candidates):
        lines.append(
          StockSalePasteLine(lineNumber: lineNumber, text: safeText, candidates: candidates)
        )
      case .failure(let reason):
        errors.append(StockSalePasteError(lineNumber: lineNumber, text: safeText, reason: reason))
      }
    }
    return StockSalePasteResult(lines: lines, errors: errors)
  }

  /// Integer quantity with English or German thousands separators.
  public static func parseQuantity(_ text: String) -> Int64? {
    let separators: Set<Character> = [".", ",", " ", "\u{00A0}", "\u{202F}", "'", "’"]
    let digits = text.trimmingCharacters(in: .whitespaces).filter { !separators.contains($0) }
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
      let value = Int64(digits), value > 0, value <= maximumQuantity
    else { return nil }
    return value
  }

  private static func candidates(
    for line: String
  ) -> Result<[StockSaleNameCandidate], StockSalePasteErrorReason> {
    if line.contains("\t") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
      let name = fields[0]
      guard !name.isEmpty else { return .failure(.missingName) }
      guard name.utf8.count <= maximumNameBytes else { return .failure(.nameTooLong) }
      let quantityText = fields.count > 1 ? fields[1] : ""
      if quantityText.isEmpty {
        return .success([StockSaleNameCandidate(name: name, quantity: 1)])
      }
      guard let quantity = parseQuantity(quantityText) else {
        return .failure(.invalidQuantity)
      }
      return .success([StockSaleNameCandidate(name: name, quantity: quantity)])
    }
    var result: [StockSaleNameCandidate] = []
    if line.utf8.count <= maximumNameBytes {
      result.append(StockSaleNameCandidate(name: line, quantity: 1))
    }
    if let split = trailingQuantity(in: line) {
      result.append(split)
    }
    guard !result.isEmpty else { return .failure(.nameTooLong) }
    return .success(result)
  }

  /// `Name x 12`, `Name x12`, `Name ×12` or `Name 12`.
  private static func trailingQuantity(in line: String) -> StockSaleNameCandidate? {
    let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard tokens.count >= 2 else { return nil }
    // Quantities may contain spaces as thousands separators, so take the
    // longest numeric tail.
    var tailStart = tokens.count
    while tailStart > 1, isQuantityToken(tokens[tailStart - 1]) {
      tailStart -= 1
    }
    var nameTokens = Array(tokens[..<tailStart])
    var quantityText = tokens[tailStart...].joined(separator: " ")
    if quantityText.isEmpty, let last = tokens.last,
      let marker = last.first, "xX×".contains(marker), last.count > 1
    {
      // `Name x12`
      quantityText = String(last.dropFirst())
      nameTokens = Array(tokens.dropLast())
    } else if let last = nameTokens.last, ["x", "X", "×"].contains(last) {
      nameTokens.removeLast()
    }
    let name = nameTokens.joined(separator: " ")
    guard !name.isEmpty, name.utf8.count <= maximumNameBytes,
      let quantity = parseQuantity(quantityText)
    else { return nil }
    return StockSaleNameCandidate(name: name, quantity: quantity)
  }

  private static func isQuantityToken(_ token: String) -> Bool {
    token.allSatisfy { ($0.isASCII && $0.isNumber) || ".,'’".contains($0) }
      && token.contains(where: { $0.isASCII && $0.isNumber })
  }
}

// MARK: Stored list

public enum StockSaleUnresolvedReason: String, Codable, Equatable, Sendable {
  case unknownName
  case ambiguousName
  case germanNamesUnavailable
  case invalidQuantity
}

/// One item of the comparison list. An entry without `typeID` is an explicit
/// unresolved pasted line and never receives a value.
public struct StockSaleEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var typeID: Int64?
  /// English SDE name of a resolved entry.
  public var resolvedName: String?
  /// Text as pasted; for German client names this differs from the SDE name.
  public var pastedName: String
  public var quantity: Int64
  public var materialEfficiency: Int?
  public var timeEfficiency: Int?
  public var unresolvedReason: StockSaleUnresolvedReason?

  public init(
    id: UUID = UUID(),
    typeID: Int64?,
    resolvedName: String?,
    pastedName: String,
    quantity: Int64,
    materialEfficiency: Int? = nil,
    timeEfficiency: Int? = nil,
    unresolvedReason: StockSaleUnresolvedReason? = nil
  ) {
    self.id = id
    self.typeID = typeID
    self.resolvedName = resolvedName
    self.pastedName = pastedName
    self.quantity = quantity
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.unresolvedReason = unresolvedReason
  }

  public var isResolved: Bool { typeID != nil && unresolvedReason == nil }

  /// The pasted text names the item differently, e.g. in German.
  public var hasDifferentPastedName: Bool {
    guard let resolvedName else { return false }
    return resolvedName.compare(pastedName, options: .caseInsensitive) != .orderedSame
  }
}

public enum StockSaleEntryList {
  /// Merges newly pasted entries into the list. Resolved entries of the same
  /// type are summed; a sum above the quantity limit keeps the previous
  /// quantity and adds an explicit invalid-quantity line instead.
  public static func merging(
    _ existing: [StockSaleEntry],
    with pasted: [StockSaleEntry],
    replacing: Bool
  ) -> [StockSaleEntry] {
    var result = replacing ? [] : existing
    for entry in pasted {
      if entry.isResolved, let typeID = entry.typeID,
        let index = result.firstIndex(where: { $0.isResolved && $0.typeID == typeID })
      {
        let (sum, overflow) = result[index].quantity.addingReportingOverflow(entry.quantity)
        if overflow || sum > StockSalePasteParser.maximumQuantity {
          var rejected = entry
          rejected.typeID = nil
          rejected.unresolvedReason = .invalidQuantity
          result.append(rejected)
        } else {
          result[index].quantity = sum
        }
      } else if !entry.isResolved,
        result.contains(where: {
          !$0.isResolved && $0.pastedName == entry.pastedName
            && $0.unresolvedReason == entry.unresolvedReason
        })
      {
        continue
      } else {
        result.append(entry)
      }
    }
    return result
  }

  public static func encode(_ entries: [StockSaleEntry]) throws -> Data {
    try JSONEncoder().encode(entries)
  }

  public static func decode(_ data: Data) throws -> [StockSaleEntry] {
    try JSONDecoder().decode([StockSaleEntry].self, from: data)
  }
}

// MARK: New production cost

/// Cost of producing the stock quantity anew for the scanned hub, per unit.
public struct StockSaleProductionCost: Equatable, Sendable {
  public let runs: Int
  public let producedQuantity: Int64
  /// `nil` for reactions, which have no ME/TE.
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let materialCostPerUnit: Double?
  public let installationCostPerUnit: Double?
  public let blueprintCostPerUnit: Double?
  public let logisticsCostPerUnit: Double?
  public let costPerUnit: Double?
  public let warnings: [DomainWarning]
}

public enum StockSaleProductionCostProjector {
  /// ME/TE assumed when the row has no own choice, as in Hub Opportunities.
  public static func defaultEfficiency(
    for row: ManufacturingOpportunityRow,
    loyaltyStoreBlueprintTypeIDs: Set<Int64>
  ) -> ManufacturingOpportunityEfficiencyAssumption {
    ManufacturingOpportunityEfficiencyDefaults.resolve(
      blueprintTypeID: row.blueprintTypeID,
      categoryName: row.categoryName,
      groupName: row.groupName,
      metaGroupID: row.metaGroupID,
      techLevel: row.techLevel,
      fallbackMaterialEfficiency: row.materialEfficiency,
      fallbackTimeEfficiency: row.timeEfficiency,
      loyaltyStoreBlueprintTypeIDs: loyaltyStoreBlueprintTypeIDs
    )
  }

  /// Hub Opportunities cost chain for `quantity` units. New production buys
  /// every material at the Main Hub: material stock is not credited, so
  /// material replacement and inbound logistics are always complete.
  public static func project(
    row scannedRow: ManufacturingOpportunityRow,
    quantity: Int64,
    materialEfficiency: Int,
    timeEfficiency: Int,
    buildsIntermediates: Bool,
    sheet: ManufacturingOpportunityCostSheet,
    contract: ManufacturingOpportunityContractContext,
    snapshot: ManufacturingOpportunitySnapshot
  ) -> StockSaleProductionCost? {
    guard quantity > 0, quantity <= StockSalePasteParser.maximumQuantity else { return nil }
    let applied = ManufacturingOpportunityComponentBuildPolicy.applying(
      scannedRow,
      buildsIntermediates: buildsIntermediates
    )
    let runs = IndustryPlanner.runsRequired(
      wantedQuantity: Int(quantity),
      outputPerRun: applied.outputPerRun
    )
    guard runs > 0,
      let row = ManufacturingOpportunityRunProjector.project(
        applied,
        requestedRuns: runs,
        materialEfficiency: materialEfficiency,
        timeEfficiency: timeEfficiency
      ),
      row.producedQuantity > 0
    else { return nil }
    let procurement = ManufacturingOpportunityScenarioProjector.procurement(
      for: row,
      factualWarehouseQuantities: [:],
      protectedQuantities: [:],
      reservedQuantities: [:]
    )
    let logistics = ManufacturingOpportunityScenarioProjector.logistics(
      for: row,
      procurement: procurement,
      configuration: snapshot.logisticsConfiguration,
      mainHub: snapshot.mainHub,
      warehouseIsAvailable: true,
      route: snapshot.saleRoute(for: row)
    )
    let costs = ManufacturingOpportunityScenarioProjector.costs(
      for: row,
      sheet: sheet,
      logistics: logistics,
      contract: contract
    )
    let produced = Double(row.producedQuantity)
    func perUnit(_ value: Double?) -> Double? {
      value.flatMap { $0.isFinite ? $0 / produced : nil }
    }
    return StockSaleProductionCost(
      runs: row.runs,
      producedQuantity: row.producedQuantity,
      materialEfficiency: row.displayedMaterialEfficiency,
      timeEfficiency: row.displayedTimeEfficiency,
      materialCostPerUnit: perUnit(costs.materialCost),
      installationCostPerUnit: perUnit(costs.installationCost),
      blueprintCostPerUnit: perUnit(costs.blueprintAllocation),
      logisticsCostPerUnit: perUnit(costs.logisticsCost),
      costPerUnit: perUnit(costs.totalCost),
      warnings: row.warnings + logistics.warnings
    )
  }
}

// MARK: Comparison

public enum StockSaleRecommendation: String, Codable, CaseIterable, Sendable {
  case listedSale
  case directSale
  case keep
}

public enum StockSaleDepthState: String, Equatable, Sendable {
  case sufficient
  case insufficient
  case unknown
}

public struct StockSaleComparisonRow: Identifiable, Equatable, Sendable {
  public let entryID: UUID
  public let typeID: Int64
  public let name: String
  public let pastedName: String
  public let quantity: Int64
  /// `nil` when the hub scan has no row for the item.
  public let cost: StockSaleProductionCost?
  public let salesTaxRate: Double?
  public let brokerFeeRate: Double?
  public let minimumListingPrice: Double?
  public let minimumDirectSalePrice: Double?
  public let bestSellPrice: Double?
  public let ownSellOrderPrice: Double?
  public let bestBuyPrice: Double?
  public let bestBuyVolume: Int64?
  public let listingProfitPerUnit: Double?
  public let listingProfitTotal: Double?
  public let directProfitPerUnit: Double?
  public let directProfitTotal: Double?
  public let directDepth: StockSaleDepthState
  public let recommendation: StockSaleRecommendation?
  /// Total profit of the recommended sale type, also for `keep`.
  public let recommendedProfitTotal: Double?

  public var id: Int64 { typeID }
  public var costPerUnit: Double? { cost?.costPerUnit }

  /// The own order reaches the break-even listing price.
  public var listingReachesMinimum: Bool? { listingProfitPerUnit.map { $0 >= 0 } }
  public var directReachesMinimum: Bool? { directProfitPerUnit.map { $0 >= 0 } }
}

public enum StockSaleComparisonCalculator {
  public static let ruleVersion = "stock-sale-2026-10-25"

  public static func row(
    entryID: UUID = UUID(),
    typeID: Int64,
    name: String,
    pastedName: String? = nil,
    quantity: Int64,
    cost: StockSaleProductionCost?,
    prices: MarketOrderTypeSummary?,
    fees: TradeHubFees
  ) -> StockSaleComparisonRow {
    let tax = validRate(fees.salesTaxRate)
    let broker = validRate(fees.brokerFeeRate)
    let listingKeep: Double? = tax.flatMap { t in
      broker.flatMap { b in t + b < 1 ? 1 - t - b : nil }
    }
    let directKeep: Double? = tax.flatMap { $0 < 1 ? 1 - $0 : nil }
    let unitCost = cost?.costPerUnit.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }

    let minimumListing = divide(unitCost, by: listingKeep)
    let minimumDirect = divide(unitCost, by: directKeep)

    let bestSell = validPrice(prices?.bestSellPrice)
    let bestBuy = validPrice(prices?.bestBuyPrice)
    let ownOrder = bestSell.flatMap(MarketPriceTick.nextBelow)

    let listingPerUnit = profit(price: ownOrder, keep: listingKeep, cost: unitCost)
    let directPerUnit = profit(price: bestBuy, keep: directKeep, cost: unitCost)
    let quantityValue = Double(quantity)
    let listingTotal = listingPerUnit.map { $0 * quantityValue }
    let directTotal = directPerUnit.map { $0 * quantityValue }

    let depth: StockSaleDepthState =
      if bestBuy == nil {
        .unknown
      } else if let volume = prices?.bestBuyVolume {
        volume >= quantity ? .sufficient : .insufficient
      } else {
        .unknown
      }

    let (recommendation, recommendedTotal) = recommend(
      listingTotal: listingTotal,
      directTotal: directTotal
    )
    return StockSaleComparisonRow(
      entryID: entryID,
      typeID: typeID,
      name: name,
      pastedName: pastedName ?? name,
      quantity: quantity,
      cost: cost,
      salesTaxRate: tax,
      brokerFeeRate: broker,
      minimumListingPrice: minimumListing,
      minimumDirectSalePrice: minimumDirect,
      bestSellPrice: bestSell,
      ownSellOrderPrice: ownOrder,
      bestBuyPrice: bestBuy,
      bestBuyVolume: prices?.bestBuyVolume,
      listingProfitPerUnit: listingPerUnit,
      listingProfitTotal: listingTotal,
      directProfitPerUnit: directPerUnit,
      directProfitTotal: directTotal,
      directDepth: depth,
      recommendation: recommendation,
      recommendedProfitTotal: recommendedTotal
    )
  }

  /// The higher known total wins when it is positive; a tie recommends the
  /// direct sale (owner decision 25.10.2026). Non-positive totals keep.
  public static func recommend(
    listingTotal: Double?,
    directTotal: Double?
  ) -> (StockSaleRecommendation?, Double?) {
    let best: (StockSaleRecommendation, Double)?
    switch (listingTotal, directTotal) {
    case (let listing?, let direct?):
      best = listing > direct ? (.listedSale, listing) : (.directSale, direct)
    case (let listing?, nil):
      best = (.listedSale, listing)
    case (nil, let direct?):
      best = (.directSale, direct)
    case (nil, nil):
      best = nil
    }
    guard let best else { return (nil, nil) }
    return best.1 > 0 ? (best.0, best.1) : (.keep, best.1)
  }

  private static func validRate(_ rate: Double?) -> Double? {
    rate.flatMap { $0.isFinite && $0 >= 0 && $0 < 1 ? $0 : nil }
  }

  private static func validPrice(_ price: Double?) -> Double? {
    price.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }

  private static func divide(_ value: Double?, by divisor: Double?) -> Double? {
    guard let value, let divisor, divisor > 0 else { return nil }
    let result = value / divisor
    return result.isFinite ? result : nil
  }

  private static func profit(price: Double?, keep: Double?, cost: Double?) -> Double? {
    guard let price, let keep, let cost else { return nil }
    let result = price * keep - cost
    return result.isFinite ? result : nil
  }
}

// MARK: Sorting

public enum StockSaleSortColumn: String, CaseIterable, Sendable {
  case name
  case quantity
  case materialEfficiency
  case timeEfficiency
  case materialCostPerUnit
  case installationCostPerUnit
  case blueprintCostPerUnit
  case logisticsCostPerUnit
  case costPerUnit
  case minimumListingPrice
  case minimumDirectSalePrice
  case bestSellPrice
  case ownSellOrderPrice
  case bestBuyPrice
  case bestBuyVolume
  case listingProfitPerUnit
  case listingProfitTotal
  case directProfitPerUnit
  case directProfitTotal
  /// Sorted by the total profit of the recommended sale type.
  case recommendation
}

/// Sorts by the typed value of a column. On this screen unknown values stay
/// after known values in both directions (owner decision 25.10.2026), so the
/// rows that can be valued always lead; the type ID is the final tie-breaker.
public enum StockSaleRowSorter {
  public static func sorted(
    _ rows: [StockSaleComparisonRow],
    by column: StockSaleSortColumn,
    ascending: Bool
  ) -> [StockSaleComparisonRow] {
    rows.sorted { lhs, rhs in
      if column == .name {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if order != .orderedSame {
          return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.typeID < rhs.typeID
      }
      switch (value(lhs, column), value(rhs, column)) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return true
      case (nil, .some):
        return false
      case (nil, nil):
        break
      }
      return lhs.typeID < rhs.typeID
    }
  }

  static func value(_ row: StockSaleComparisonRow, _ column: StockSaleSortColumn) -> Double? {
    switch column {
    case .name: nil
    case .quantity: Double(row.quantity)
    case .materialEfficiency: row.cost?.materialEfficiency.map(Double.init)
    case .timeEfficiency: row.cost?.timeEfficiency.map(Double.init)
    case .materialCostPerUnit: row.cost?.materialCostPerUnit
    case .installationCostPerUnit: row.cost?.installationCostPerUnit
    case .blueprintCostPerUnit: row.cost?.blueprintCostPerUnit
    case .logisticsCostPerUnit: row.cost?.logisticsCostPerUnit
    case .costPerUnit: row.costPerUnit
    case .minimumListingPrice: row.minimumListingPrice
    case .minimumDirectSalePrice: row.minimumDirectSalePrice
    case .bestSellPrice: row.bestSellPrice
    case .ownSellOrderPrice: row.ownSellOrderPrice
    case .bestBuyPrice: row.bestBuyPrice
    case .bestBuyVolume: row.bestBuyVolume.map(Double.init)
    case .listingProfitPerUnit: row.listingProfitPerUnit
    case .listingProfitTotal: row.listingProfitTotal
    case .directProfitPerUnit: row.directProfitPerUnit
    case .directProfitTotal: row.directProfitTotal
    case .recommendation: row.recommendedProfitTotal
    }
  }
}
