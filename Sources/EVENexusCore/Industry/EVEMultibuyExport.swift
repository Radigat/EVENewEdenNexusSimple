import Foundation

public struct EVEShoppingListItem: Identifiable, Equatable, Sendable {
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let quantity: Int64
  public let marketQuote: PriceQuote?

  public init(
    typeID: Int64,
    name: String,
    quantity: Int64,
    marketQuote: PriceQuote?
  ) {
    self.typeID = typeID
    self.name = name
    self.quantity = quantity
    self.marketQuote = marketQuote
  }

  public var hasCompleteMarketCoverage: Bool {
    marketQuote?.isComplete == true && marketQuote?.quantity == quantity
  }
}

public struct EVEShoppingList: Equatable, Sendable {
  public let items: [EVEShoppingListItem]

  public init(items: [EVEShoppingListItem]) {
    self.items = items
  }

  public static func make(
    from materials: [MaterialRequirement]
  ) -> EVEShoppingList {
    EVEShoppingList(
      items: materials
        .filter { $0.toBuy > 0 }
        .sorted {
          $0.name.localizedCaseInsensitiveCompare($1.name)
            == .orderedAscending
        }
        .map {
          EVEShoppingListItem(
            typeID: $0.typeID,
            name: $0.name,
            quantity: $0.toBuy,
            marketQuote: $0.quote
          )
        }
    )
  }

  public var totalQuantity: Int64 {
    items.reduce(0) { partialResult, item in
      let (sum, overflow) = partialResult.addingReportingOverflow(item.quantity)
      return overflow ? Int64.max : sum
    }
  }

  public var purchaseTotal: Double? {
    guard !items.isEmpty else { return 0 }
    var result = 0.0
    for item in items {
      guard item.hasCompleteMarketCoverage,
        let lineTotal = item.marketQuote?.total,
        lineTotal.isFinite,
        lineTotal >= 0
      else {
        return nil
      }
      result += lineTotal
      guard result.isFinite else { return nil }
    }
    return result
  }
}

public struct EVEMultibuyExport: Equatable, Sendable {
  public let text: String
  public let itemCount: Int

  public init(text: String, itemCount: Int) {
    self.text = text
    self.itemCount = itemCount
  }

  public static func make(
    from materials: [MaterialRequirement],
  ) -> EVEMultibuyExport {
    let purchaseLines = EVEShoppingList.make(from: materials).items
      .map { "\($0.name) \($0.quantity)" }

    return EVEMultibuyExport(
      text: purchaseLines.joined(separator: "\n"),
      itemCount: purchaseLines.count
    )
  }

  public static func makeWarehouseReplenishment(
    from materials: [MaterialRequirement]
  ) -> EVEMultibuyExport {
    let replacementLines =
      materials
      .filter { $0.fromStock > 0 }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name)
          == .orderedAscending
      }
      .map { "\($0.name) \($0.fromStock)" }

    return EVEMultibuyExport(
      text: replacementLines.joined(separator: "\n"),
      itemCount: replacementLines.count
    )
  }
}
