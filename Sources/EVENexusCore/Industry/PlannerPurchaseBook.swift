import Foundation

/// How goods bought at a market reach the Home Hub.
public enum PlannerPurchaseRoute: Equatable, Sendable {
  case hub(HubTransportLeg)
  case market(id: UUID)
}

extension LogisticsConfiguration {
  func pricing(for route: PlannerPurchaseRoute) -> LogisticsLegPricing {
    switch route {
    case .hub(let leg): legPricing(for: leg)
    case .market(let id): marketRoutePricing(marketID: id)
    }
  }
}

/// One market the Planner may buy from, with the transport route to the Home Hub.
/// `route == nil` means the market is at the Home Hub (owner decision 30.10.2026:
/// no transport, with a visible hint when the facility is elsewhere).
public struct PlannerPurchaseMarket: Sendable {
  public let location: ProcurementLocation
  public let snapshot: MarketOrderSnapshot
  public let route: PlannerPurchaseRoute?

  public init(
    location: ProcurementLocation,
    snapshot: MarketOrderSnapshot,
    route: PlannerPurchaseRoute?
  ) {
    self.location = location
    self.snapshot = snapshot
    self.route = route
  }

  public init(
    location: ProcurementLocation,
    snapshot: MarketOrderSnapshot,
    leg: HubTransportLeg?
  ) {
    self.init(location: location, snapshot: snapshot, route: leg.map { .hub($0) })
  }
}

/// The part of a material's purchase that comes from one location.
public struct PurchaseLocationAllocation: Codable, Equatable, Sendable {
  public let location: ProcurementLocation
  public let quantity: Int64
  public let total: Double

  public init(location: ProcurementLocation, quantity: Int64, total: Double) {
    self.location = location
    self.quantity = quantity
    self.total = total
  }
}

/// Fills a material quantity from the selected markets, cheapest unit first
/// including its unrounded transport share. Contract rounding is applied later,
/// on the summed cargo per origin.
struct PlannerPurchaseBook: Sendable {
  enum Transport: Sendable {
    case free
    case contract(LogisticsContractPricing)
    case unavailable(DomainWarning)
  }

  struct Source: Sendable {
    let location: ProcurementLocation
    let book: PreparedMarketOrderBook
    let route: PlannerPurchaseRoute?
    let transport: Transport
  }

  let sources: [Source]
  private let fallbackSnapshot: MarketOrderSnapshot
  private let packagedVolumes: [Int64: Double]

  init(
    sources: [Source],
    fallbackSnapshot: MarketOrderSnapshot,
    packagedVolumes: [Int64: Double]
  ) {
    self.sources = sources
    self.fallbackSnapshot = fallbackSnapshot
    self.packagedVolumes = packagedVolumes
  }

  /// `nil` markets keep the single Main Hub path of every other caller.
  static func make(context: IndustryPlanningContext) async throws
    -> PlannerPurchaseBook
  {
    guard let markets = context.purchaseMarkets else {
      return PlannerPurchaseBook(
        sources: [
          Source(
            location: context.defaultPurchaseLocation,
            book: PreparedMarketOrderBook(snapshot: context.market),
            route: .hub(.mainToHome),
            transport: .free
          )
        ],
        fallbackSnapshot: context.market,
        packagedVolumes: [:]
      )
    }
    let logistics = context.productionBasis?.logistics
    let chargesInbound =
      logistics?.isEnabled == true && logistics?.includeInboundMaterials == true
    let sources = markets.map { market -> Source in
      let transport: Transport
      if let route = market.route, chargesInbound, let logistics {
        switch logistics.pricing(for: route) {
        case .contract(let pricing):
          transport = .contract(pricing)
        case .unavailable(let warning):
          transport = .unavailable(warning)
        case .selfJump:
          transport = .unavailable(
            DomainWarning(
              code: "logistics.self-jump-not-contract",
              message:
                "This leg is carried by an own Jump Freighter and has no courier contracts.",
              severity: .warning
            )
          )
        }
      } else {
        transport = .free
      }
      return Source(
        location: market.location,
        book: PreparedMarketOrderBook(snapshot: market.snapshot),
        route: market.route,
        transport: transport
      )
    }
    let typeIDs = Set(markets.flatMap { $0.snapshot.ordersByType.keys })
    return PlannerPurchaseBook(
      sources: sources,
      fallbackSnapshot: context.market,
      packagedVolumes:
        sources.count > 1
        ? try await context.catalog.packagedVolumes(typeIDs: typeIDs) : [:]
    )
  }

  /// Main Hub and Home Hub orders for valuing warehouse units, independent of
  /// the selected purchase locations. Nothing is bought through this book.
  static func stockValuation(context: IndustryPlanningContext)
    -> PlannerPurchaseBook
  {
    var sources = [
      Source(
        location: context.defaultPurchaseLocation,
        book: PreparedMarketOrderBook(snapshot: context.market),
        route: .hub(.mainToHome),
        transport: .free
      )
    ]
    if let home = context.homeMarket,
      let location = context.productionBasis?.homeTradingLocation?.location,
      !location.representsSameLocation(as: context.defaultPurchaseLocation)
    {
      sources.append(
        Source(
          location: location,
          book: PreparedMarketOrderBook(snapshot: home),
          route: nil,
          transport: .free
        )
      )
    }
    return PlannerPurchaseBook(
      sources: sources,
      fallbackSnapshot: context.market,
      packagedVolumes: [:]
    )
  }

  /// Units and value the visible orders can fill, even when they are too few.
  func visibleFill(typeID: Int64, quantity: Int64) -> (filled: Int64, total: Double) {
    let allocations = walk(typeID: typeID, quantity: quantity).allocations
    return (
      allocations.reduce(0) { $0 + $1.quantity },
      allocations.reduce(0) { $0 + $1.total }
    )
  }

  func contains(_ location: ProcurementLocation) -> Bool {
    sources.contains { $0.location.representsSameLocation(as: location) }
  }

  /// Why `source` cannot supply `typeID`; `nil` when it can. A lone market is
  /// never excluded here: its logistics result states the missing route.
  func exclusionReason(source: Source, typeID: Int64) -> String? {
    guard sources.count > 1 else { return nil }
    switch source.transport {
    case .free:
      return nil
    case .unavailable(let warning):
      return warning.message
    case .contract(let pricing):
      guard let volume = packagedVolumes[typeID], volume >= 0 else {
        return "The packaged volume is unknown."
      }
      return volume > pricing.maximumContractVolumeM3
        ? "The packaged item exceeds the transport limit." : nil
    }
  }

  func allocations(typeID: Int64, quantity: Int64) -> [PurchaseLocationAllocation] {
    guard quantity > 0 else { return [] }
    if sources.count == 1, let source = sources.first {
      let quote = quote(typeID: typeID, quantity: quantity, scenario: .materialBuy)
      guard quote.isComplete, let total = quote.total else { return [] }
      return [
        PurchaseLocationAllocation(
          location: source.location,
          quantity: quantity,
          total: total
        )
      ]
    }
    return walk(typeID: typeID, quantity: quantity).allocations
  }

  func quote(
    typeID: Int64,
    quantity: Int64,
    scenario: PriceScenario
  ) -> PriceQuote {
    if sources.count == 1, let source = sources.first {
      return source.book.quote(
        typeID: typeID,
        quantity: quantity,
        scenario: scenario
      )
    }
    let capturedAt = sources.map(\.book.capturedAt).min()
      ?? fallbackSnapshot.capturedAt
    let result = walk(typeID: typeID, quantity: quantity)
    let filled = result.allocations.reduce(Int64(0)) { $0 + $1.quantity }
    guard filled == quantity, quantity > 0 else {
      return PriceQuote(
        id: UUID(),
        typeID: typeID,
        quantity: quantity,
        scenario: scenario,
        total: nil,
        weightedUnitPrice: nil,
        filledQuantity: filled,
        capturedAt: capturedAt,
        source: fallbackSnapshot.source,
        warnings: [
          DomainWarning(
            code:
              sources.isEmpty
              ? "planner.no-purchase-location" : "market.insufficient-depth",
            message:
              sources.isEmpty
              ? "No purchase location is selected."
              : "Only \(filled) of \(quantity) units are available at the selected purchase locations.",
            severity: .blocking,
            source: fallbackSnapshot.source
          )
        ]
      )
    }
    let total = result.allocations.reduce(0) { $0 + $1.total }
    return PriceQuote(
      id: UUID(),
      typeID: typeID,
      quantity: quantity,
      scenario: scenario,
      total: total,
      weightedUnitPrice: total / Double(quantity),
      filledQuantity: filled,
      capturedAt: capturedAt,
      source: fallbackSnapshot.source,
      warnings: []
    )
  }

  private func walk(
    typeID: Int64,
    quantity: Int64
  ) -> (allocations: [PurchaseLocationAllocation], Void) {
    struct Entry {
      let effectivePrice: Double
      let sourceIndex: Int
      let order: MarketOrder
    }
    var entries: [Entry] = []
    for (index, source) in sources.enumerated()
    where exclusionReason(source: source, typeID: typeID) == nil {
      for order in source.book.sellOrders(typeID: typeID) {
        var surcharge = 0.0
        if case .contract(let pricing) = source.transport {
          surcharge =
            (packagedVolumes[typeID] ?? 0) * pricing.iskPerCubicMeter
            + order.price * pricing.collateralRate
        }
        entries.append(
          Entry(
            effectivePrice: order.price + surcharge,
            sourceIndex: index,
            order: order
          )
        )
      }
    }
    entries.sort {
      if $0.effectivePrice != $1.effectivePrice {
        return $0.effectivePrice < $1.effectivePrice
      }
      if $0.sourceIndex != $1.sourceIndex {
        return $0.sourceIndex < $1.sourceIndex
      }
      return $0.order.id < $1.order.id
    }
    var remaining = quantity
    var quantities: [Int: Int64] = [:]
    var totals: [Int: Double] = [:]
    for entry in entries where remaining > 0 {
      if entry.order.minimumVolume > 1, remaining < entry.order.minimumVolume {
        continue
      }
      let take = min(remaining, entry.order.volumeRemaining)
      guard take > 0 else { continue }
      quantities[entry.sourceIndex, default: 0] += take
      totals[entry.sourceIndex, default: 0] += Double(take) * entry.order.price
      remaining -= take
    }
    return (
      quantities.keys.sorted().map {
        PurchaseLocationAllocation(
          location: sources[$0].location,
          quantity: quantities[$0, default: 0],
          total: totals[$0, default: 0]
        )
      },
      ()
    )
  }
}

/// The shopping list and Multibuy text of one purchase location.
public struct EVEShoppingListLocationGroup: Identifiable, Sendable {
  public var id: String { location.id }
  public let location: ProcurementLocation
  public let shoppingList: EVEShoppingList
  public let export: EVEMultibuyExport
}

extension EVEShoppingList {
  /// Everything to buy to end with the stock the plan started with: the missing
  /// items plus the used warehouse stock, each at its cheapest location. What the
  /// markets cannot cover stays at the material's purchase location, so the lists
  /// always add up to the full quantity.
  public static func restockGroups(
    from materials: [MaterialRequirement],
    refiningPlan: CompressedOreRefiningPlan?,
    refiningLocation: ProcurementLocation,
    fallback: ProcurementLocation
  ) -> [EVEShoppingListLocationGroup] {
    var grouped: [ProcurementLocation: [Int64: EVEShoppingListItem]] = [:]
    func add(
      _ typeID: Int64,
      _ name: String,
      _ quantity: Int64,
      at location: ProcurementLocation
    ) {
      guard quantity > 0 else { return }
      let known = grouped[location]?[typeID]?.quantity ?? 0
      let (sum, overflow) = known.addingReportingOverflow(quantity)
      grouped[location, default: [:]][typeID] = EVEShoppingListItem(
        typeID: typeID,
        name: name,
        quantity: overflow ? Int64.max : sum,
        marketQuote: nil
      )
    }
    let stockTypeIDs = Set(materials.filter { $0.fromStock > 0 }.map(\.typeID))
    for group in locationGroups(
      from: materials,
      refiningPlan: refiningPlan,
      refiningLocation: refiningLocation,
      fallback: fallback
    ) {
      for item in group.shoppingList.items where !stockTypeIDs.contains(item.typeID) {
        add(item.typeID, item.name, item.quantity, at: group.location)
      }
    }
    let directQuantities = Dictionary(
      make(from: materials, refiningPlan: refiningPlan).items.map { ($0.typeID, $0.quantity) },
      uniquingKeysWith: { current, _ in current }
    )
    for material in materials where material.fromStock > 0 {
      var remaining = material.fromStock + directQuantities[material.typeID, default: 0]
      let cheapestFirst = (material.restockAllocations ?? []).sorted {
        $0.total / Double(max(1, $0.quantity))
          < $1.total / Double(max(1, $1.quantity))
      }
      for allocation in cheapestFirst where remaining > 0 {
        let quantity = min(remaining, allocation.quantity)
        remaining -= quantity
        add(material.typeID, material.name, quantity, at: allocation.location)
      }
      add(
        material.typeID,
        material.name,
        remaining,
        at: material.procurement?.purchaseLocation ?? fallback
      )
    }
    return grouped.map { location, itemsByType in
      let items = itemsByType.values.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return EVEShoppingListLocationGroup(
        location: location,
        shoppingList: EVEShoppingList(items: items),
        export: EVEMultibuyExport.make(items: items)
      )
    }.sorted { $0.location.name < $1.location.name }
  }

  /// Splits the list by where each line is bought. Plans without allocations
  /// keep their saved material location. Ore bought for refining comes from
  /// `refiningLocation`; a mineral partly replaced by ore keeps its cheapest
  /// allocations up to the remaining quantity.
  public static func locationGroups(
    from materials: [MaterialRequirement],
    refiningPlan: CompressedOreRefiningPlan?,
    refiningLocation: ProcurementLocation,
    fallback: ProcurementLocation
  ) -> [EVEShoppingListLocationGroup] {
    let lines = EVEShoppingList.make(from: materials, refiningPlan: refiningPlan)
      .items
    let byType = Dictionary(
      materials.map { ($0.typeID, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    let oreTypeIDs = Set(refiningPlan?.purchases.map(\.oreTypeID) ?? [])
    var grouped: [ProcurementLocation: [EVEShoppingListItem]] = [:]
    for line in lines {
      if oreTypeIDs.contains(line.typeID) {
        grouped[refiningLocation, default: []].append(line)
        continue
      }
      let material = byType[line.typeID]
      guard let allocations = material?.purchaseAllocations, !allocations.isEmpty
      else {
        let location =
          refiningPlan == nil
          ? material?.procurement?.purchaseLocation ?? fallback
          : refiningLocation
        grouped[location, default: []].append(line)
        continue
      }
      var remaining = line.quantity
      let cheapestFirst = allocations.sorted {
        $0.total / Double(max(1, $0.quantity))
          < $1.total / Double(max(1, $1.quantity))
      }
      for allocation in cheapestFirst where remaining > 0 {
        let quantity = min(remaining, allocation.quantity)
        remaining -= quantity
        let total =
          allocation.total * Double(quantity) / Double(max(1, allocation.quantity))
        grouped[allocation.location, default: []].append(
          EVEShoppingListItem(
            typeID: line.typeID,
            name: line.name,
            quantity: quantity,
            marketQuote: line.marketQuote.map {
              PriceQuote(
                id: UUID(),
                typeID: line.typeID,
                quantity: quantity,
                scenario: $0.scenario,
                total: total,
                weightedUnitPrice: total / Double(max(1, quantity)),
                filledQuantity: quantity,
                capturedAt: $0.capturedAt,
                source: $0.source,
                warnings: []
              )
            }
          )
        )
      }
    }
    return grouped.map { location, items in
      let sorted = items.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return EVEShoppingListLocationGroup(
        location: location,
        shoppingList: EVEShoppingList(items: sorted),
        export: EVEMultibuyExport.make(items: sorted)
      )
    }.sorted { $0.location.name < $1.location.name }
  }
}
