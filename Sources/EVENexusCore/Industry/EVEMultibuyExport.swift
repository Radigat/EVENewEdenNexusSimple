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
      items:
        materials
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

  public static func make(
    from materials: [MaterialRequirement],
    refiningPlan: CompressedOreRefiningPlan?
  ) -> EVEShoppingList {
    guard let refiningPlan else { return make(from: materials) }
    var items: [EVEShoppingListItem] = []
    for material in materials where material.toBuy > 0 {
      let quantity =
        refiningPlan.coveredMinerals[material.typeID] == nil
        ? material.toBuy
        : refiningPlan.remainingDirectMinerals[material.typeID, default: 0]
      guard quantity > 0 else { continue }
      items.append(
        EVEShoppingListItem(
          typeID: material.typeID,
          name: material.name,
          quantity: quantity,
          marketQuote:
            refiningPlan.remainingDirectQuotes[material.typeID]
            ?? material.quote
        )
      )
    }
    items.append(
      contentsOf: refiningPlan.purchases.map {
        EVEShoppingListItem(
          typeID: $0.oreTypeID,
          name: $0.oreName,
          quantity: $0.quantity,
          marketQuote: $0.purchaseQuote
        )
      }
    )
    return EVEShoppingList(
      items: items.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name)
          == .orderedAscending
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
    make(items: EVEShoppingList.make(from: materials).items)
  }

  /// The one Multibuy line format (`ItemName Quantity`) for any item list.
  public static func make(items: [EVEShoppingListItem]) -> EVEMultibuyExport {
    let purchaseLines = items.map { "\($0.name) \($0.quantity)" }
    return EVEMultibuyExport(
      text: purchaseLines.joined(separator: "\n"),
      itemCount: purchaseLines.count
    )
  }

  public static func make(
    from materials: [MaterialRequirement],
    refiningPlan: CompressedOreRefiningPlan?
  ) -> EVEMultibuyExport {
    make(
      items: EVEShoppingList.make(
        from: materials,
        refiningPlan: refiningPlan
      ).items
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

/// Purchase-location hint for one mineral or moon-material shopping line
/// (HUB_CHANCEN_PLAN P12). Decision aid only: plan costs stay Main-Hub based.
public struct MaterialPurchaseLocationHint: Identifiable, Sendable {
  public var id: Int64 { item.typeID }
  public let item: EVEShoppingListItem
  /// Cheapest fresh configured market; `nil` without a fresh offer.
  public let location: ProcurementLocation?
  public let unitPrice: Double?
  /// Weighted Main-Hub unit price of the plan's complete quote.
  public let mainHubUnitPrice: Double?

  public init(
    item: EVEShoppingListItem,
    location: ProcurementLocation?,
    unitPrice: Double?,
    mainHubUnitPrice: Double?
  ) {
    self.item = item
    self.location = location
    self.unitPrice = unitPrice
    self.mainHubUnitPrice = mainHubUnitPrice
  }

  /// Recommended minus Main-Hub price per unit; negative means cheaper.
  public var priceDifferencePerUnit: Double? {
    guard let unitPrice, let mainHubUnitPrice else { return nil }
    let value = unitPrice - mainHubUnitPrice
    return value.isFinite ? value : nil
  }
}

public enum MaterialPurchaseLocationHints {
  /// Joins shopping lines with the prepared analysis recommendations. Lines
  /// that are neither minerals nor moon materials are not part of the hint.
  public static func project(
    items: [EVEShoppingListItem],
    recommendations: [MaterialPurchaseRecommendation]
  ) -> [MaterialPurchaseLocationHint] {
    let byType = Dictionary(
      recommendations.map { ($0.material.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    return items.compactMap { item in
      guard let recommendation = byType[item.typeID] else { return nil }
      return MaterialPurchaseLocationHint(
        item: item,
        location: recommendation.location,
        unitPrice: recommendation.unitPrice,
        mainHubUnitPrice: item.hasCompleteMarketCoverage
          ? item.marketQuote?.weightedUnitPrice : nil
      )
    }
  }

  /// One Multibuy export per recommended location, sorted by location name;
  /// lines without a location are left out.
  public static func multibuyGroups(
    _ hints: [MaterialPurchaseLocationHint]
  ) -> [(location: ProcurementLocation, export: EVEMultibuyExport)] {
    let grouped = Dictionary(
      grouping: hints.filter { $0.location != nil }
    ) { $0.location!.id }
    return grouped.values.compactMap { group in
      guard let location = group.first?.location else { return nil }
      let items = group.map(\.item).sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return (location, EVEMultibuyExport.make(items: items))
    }
    .sorted {
      $0.location.name.localizedCaseInsensitiveCompare($1.location.name)
        == .orderedAscending
    }
  }
}
