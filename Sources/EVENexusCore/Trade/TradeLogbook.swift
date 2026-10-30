import Foundation

/// Life cycle of a logged purchase. `manufacturingIgnored` (shown as
/// production), `consumed` and `excluded` keep the record but take it out of
/// open quantities (HANDEL_PLAN P5/P7). The raw value `manufacturingIgnored`
/// stays for stored rows.
public enum TradeLogbookStatus: String, Codable, CaseIterable, Sendable {
  case bought
  case inTransit
  case listed
  case sold
  case manufacturingIgnored
  case consumed
  case excluded

  /// Units of an open entry still wait for their sale.
  public var isOpen: Bool {
    switch self {
    case .bought, .inTransit, .listed: true
    case .sold, .manufacturingIgnored, .consumed, .excluded: false
    }
  }

  /// Statuses that state the use instead of a sale life cycle.
  public var isUsage: Bool {
    self == .manufacturingIgnored || self == .consumed
  }

  /// Documented sort rank: the order of the life cycle above.
  public var sortRank: Int {
    Self.allCases.firstIndex(of: self) ?? Self.allCases.count
  }
}

/// What a whole logged purchase is for: a sale at one hub, own production or
/// consumption. Production and consumption close the entry.
public enum TradeLogbookUsage: Hashable, Sendable {
  case sale(OpportunityHubRole)
  case production
  case consumption

  public static var allCases: [TradeLogbookUsage] {
    OpportunityHubRole.allCases.map(Self.sale) + [.production, .consumption]
  }

  /// Documented rank: the hubs Main, Home, Coalition, then production and
  /// consumption.
  public var sortRank: Int {
    Self.allCases.firstIndex(of: self) ?? Self.allCases.count
  }
}

public enum TradeSaleKind: String, Codable, CaseIterable, Sendable {
  /// Own sell order: sales tax and broker fee.
  case listedSellOrder
  /// Sale into a buy order: sales tax only.
  case directToBuyOrder
}

/// How a value was obtained (HANDEL_PLAN P7): typed by the user, detected
/// from wallet and order data, or assumed by the documented default.
public enum TradeValueSource: String, Codable, CaseIterable, Sendable {
  case manual
  case detected
  case assumed
}

/// The wallet transaction a logbook row was created from.
public struct TradeWalletLink: Hashable, Codable, Sendable {
  public let characterID: Int64
  public let transactionID: Int64

  public init(characterID: Int64, transactionID: Int64) {
    self.characterID = characterID
    self.transactionID = transactionID
  }
}

public struct TradeLogbookSale: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var soldAt: Date
  public var quantity: Int64
  public var unitPrice: Double
  public var kind: TradeSaleKind
  public var kindSource: TradeValueSource
  /// Sales tax actually paid for these units, taken from the wallet journal
  /// (positive ISK). `nil` falls back to the frozen tax rate.
  public var salesTaxPaid: Double?
  public var walletLink: TradeWalletLink?

  public init(
    id: UUID = UUID(),
    soldAt: Date,
    quantity: Int64,
    unitPrice: Double,
    kind: TradeSaleKind,
    kindSource: TradeValueSource = .manual,
    salesTaxPaid: Double? = nil,
    walletLink: TradeWalletLink? = nil
  ) {
    self.id = id
    self.soldAt = soldAt
    self.quantity = quantity
    self.unitPrice = unitPrice
    self.kind = kind
    self.kindSource = kindSource
    self.salesTaxPaid = salesTaxPaid
    self.walletLink = walletLink
  }
}

/// Where the market currently stands relative to the planned sale price.
public enum TradeLogbookReminder: Equatable, Sendable {
  case noPlannedPrice
  case marketUnknown
  /// The best sell price at the target hub is at or above the plan.
  case reached(currentBestSell: Double)
  /// The best sell price at the target hub is below the plan.
  case below(currentBestSell: Double)
}

public enum TradeLogbookValidationError: Error, Equatable, Sendable {
  case invalidField(String)
  case soldMoreThanBought
}

/// One logged purchase with its sales. Rates are frozen when the entry is
/// created so later fee changes never rewrite history. Unknown values stay
/// `nil`, never zero.
public struct TradeLogbookEntry: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var createdAt: Date
  public var updatedAt: Date
  public var purchasedAt: Date
  public var typeID: Int64
  public var typeName: String
  public var quantity: Int64
  /// Price paid per unit, without the buy-order broker fee.
  public var buyUnitPrice: Double
  public var buySide: TradeQuoteSide
  public var buyBrokerFeeRate: Double?
  public var sourceRole: OpportunityHubRole
  public var sourceLocationName: String?
  public var targetRole: OpportunityHubRole
  public var targetLocationName: String?
  public var plannedSellUnitPrice: Double?
  /// Transport for the whole quantity; zero for station trading, `nil` when
  /// unknown.
  public var transportCostTotal: Double?
  public var salesTaxRate: Double?
  public var sellBrokerFeeRate: Double?
  public var status: TradeLogbookStatus
  public var notes: String
  public var sales: [TradeLogbookSale]
  public var walletLink: TradeWalletLink?
  public var buySideSource: TradeValueSource
  /// The transport was estimated from the transport basis, not entered.
  public var transportEstimated: Bool

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    updatedAt: Date = .now,
    purchasedAt: Date = .now,
    typeID: Int64,
    typeName: String,
    quantity: Int64,
    buyUnitPrice: Double,
    buySide: TradeQuoteSide,
    buyBrokerFeeRate: Double?,
    sourceRole: OpportunityHubRole,
    sourceLocationName: String?,
    targetRole: OpportunityHubRole,
    targetLocationName: String?,
    plannedSellUnitPrice: Double?,
    transportCostTotal: Double?,
    salesTaxRate: Double?,
    sellBrokerFeeRate: Double?,
    status: TradeLogbookStatus = .bought,
    notes: String = "",
    sales: [TradeLogbookSale] = [],
    walletLink: TradeWalletLink? = nil,
    buySideSource: TradeValueSource = .manual,
    transportEstimated: Bool = false
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.purchasedAt = purchasedAt
    self.typeID = typeID
    self.typeName = typeName
    self.quantity = quantity
    self.buyUnitPrice = buyUnitPrice
    self.buySide = buySide
    self.buyBrokerFeeRate = buyBrokerFeeRate
    self.sourceRole = sourceRole
    self.sourceLocationName = sourceLocationName
    self.targetRole = targetRole
    self.targetLocationName = targetLocationName
    self.plannedSellUnitPrice = plannedSellUnitPrice
    self.transportCostTotal = transportCostTotal
    self.salesTaxRate = salesTaxRate
    self.sellBrokerFeeRate = sellBrokerFeeRate
    self.status = status
    self.notes = notes
    self.sales = sales
    self.walletLink = walletLink
    self.buySideSource = buySideSource
    self.transportEstimated = transportEstimated
  }

  public var usage: TradeLogbookUsage {
    switch status {
    case .manufacturingIgnored: .production
    case .consumed: .consumption
    default: .sale(targetRole)
    }
  }

  /// Sets the use of the whole entry. Returning to a sale reopens a
  /// production or consumption entry as bought; the target hub of such an
  /// entry stays unchanged.
  public mutating func setUsage(_ usage: TradeLogbookUsage) {
    switch usage {
    case .sale(let role):
      targetRole = role
      if status.isUsage { status = .bought }
    case .production:
      status = .manufacturingIgnored
    case .consumption:
      status = .consumed
    }
  }

  public var soldQuantity: Int64 {
    sales.reduce(0) { $0 + $1.quantity }
  }

  /// Units still waiting for their sale; closed statuses count zero.
  public var openQuantity: Int64 {
    status.isOpen ? max(0, quantity - soldQuantity) : 0
  }

  /// Purchase cost per unit including the buy-order broker fee.
  public var purchaseCostPerUnit: Double? {
    switch buySide {
    case .minSell:
      return buyUnitPrice
    case .maxBuy:
      return buyBrokerFeeRate.map { buyUnitPrice * (1 + $0) }
    }
  }

  public var transportCostPerUnit: Double? {
    guard quantity > 0 else { return nil }
    return transportCostTotal.map { $0 / Double(quantity) }
  }

  public var costPerUnit: Double? {
    guard let purchase = purchaseCostPerUnit,
      let transport = transportCostPerUnit
    else { return nil }
    return purchase + transport
  }

  /// Planned net sale per unit through an own sell order.
  public var plannedNetSalePerUnit: Double? {
    guard let price = plannedSellUnitPrice,
      let keep = keepFraction(for: .listedSellOrder)
    else { return nil }
    return price * keep
  }

  public var plannedProfit: Double? {
    guard let net = plannedNetSalePerUnit, let cost = costPerUnit else {
      return nil
    }
    return (net - cost) * Double(quantity)
  }

  /// Result of the recorded sales: net revenue minus the cost of exactly the
  /// sold units. Paid sales tax from the journal replaces the frozen tax
  /// rate; the broker fee of an own sell order is always calculated.
  /// `nil` until something is sold or while a needed rate is unknown.
  public var realizedProfit: Double? {
    guard !sales.isEmpty, let cost = costPerUnit else { return nil }
    var revenue = 0.0
    for sale in sales {
      guard let net = netRevenue(of: sale) else { return nil }
      revenue += net
    }
    let result = revenue - Double(soldQuantity) * cost
    return result.isFinite ? result : nil
  }

  /// Quantity-weighted average sale price; `nil` without sales.
  public var averageSalePrice: Double? {
    let quantity = soldQuantity
    guard quantity > 0 else { return nil }
    let gross = sales.reduce(0.0) { $0 + Double($1.quantity) * $1.unitPrice }
    return gross / Double(quantity)
  }

  /// `(average sale − planned) ÷ planned`; negative means below plan.
  public var saleDeviationFromPlan: Double? {
    guard let average = averageSalePrice,
      let planned = plannedSellUnitPrice, planned > 0
    else { return nil }
    return (average - planned) / planned
  }

  public func netRevenue(of sale: TradeLogbookSale) -> Double? {
    let gross = Double(sale.quantity) * sale.unitPrice
    let broker: Double
    switch sale.kind {
    case .directToBuyOrder:
      broker = 0
    case .listedSellOrder:
      guard let rate = sellBrokerFeeRate else { return nil }
      broker = gross * rate
    }
    if let paid = sale.salesTaxPaid {
      return gross - paid - broker
    }
    guard let tax = salesTaxRate else { return nil }
    return gross - gross * tax - broker
  }

  public func reminder(currentBestSell: Double?) -> TradeLogbookReminder {
    guard let planned = plannedSellUnitPrice else { return .noPlannedPrice }
    guard let current = currentBestSell, current.isFinite, current > 0 else {
      return .marketUnknown
    }
    return current >= planned
      ? .reached(currentBestSell: current) : .below(currentBestSell: current)
  }

  public func validate() throws {
    guard !typeName.trimmingCharacters(in: .whitespaces).isEmpty, typeID > 0
    else { throw TradeLogbookValidationError.invalidField("type") }
    guard quantity > 0 else {
      throw TradeLogbookValidationError.invalidField("quantity")
    }
    guard buyUnitPrice.isFinite, buyUnitPrice >= 0 else {
      throw TradeLogbookValidationError.invalidField("buyUnitPrice")
    }
    for (name, rate) in [
      ("buyBrokerFeeRate", buyBrokerFeeRate),
      ("salesTaxRate", salesTaxRate),
      ("sellBrokerFeeRate", sellBrokerFeeRate),
    ] {
      if let rate, !(rate.isFinite && rate >= 0 && rate < 1) {
        throw TradeLogbookValidationError.invalidField(name)
      }
    }
    for (name, amount) in [
      ("plannedSellUnitPrice", plannedSellUnitPrice),
      ("transportCostTotal", transportCostTotal),
    ] {
      if let amount, !(amount.isFinite && amount >= 0) {
        throw TradeLogbookValidationError.invalidField(name)
      }
    }
    for sale in sales {
      guard sale.quantity > 0 else {
        throw TradeLogbookValidationError.invalidField("sale.quantity")
      }
      guard sale.unitPrice.isFinite, sale.unitPrice >= 0 else {
        throw TradeLogbookValidationError.invalidField("sale.unitPrice")
      }
    }
    guard soldQuantity <= quantity else {
      throw TradeLogbookValidationError.soldMoreThanBought
    }
  }

  private func keepFraction(for kind: TradeSaleKind) -> Double? {
    guard let tax = salesTaxRate else { return nil }
    switch kind {
    case .directToBuyOrder:
      return tax < 1 ? 1 - tax : nil
    case .listedSellOrder:
      guard let broker = sellBrokerFeeRate, tax + broker < 1 else { return nil }
      return 1 - tax - broker
    }
  }
}

public enum TradeLogbookSummary {
  /// Open units per type for one target hub.
  public static func openQuantities(
    _ entries: [TradeLogbookEntry],
    targetRole: OpportunityHubRole
  ) -> [Int64: Int64] {
    entries.reduce(into: [:]) { result, entry in
      guard entry.targetRole == targetRole, entry.openQuantity > 0 else {
        return
      }
      result[entry.typeID, default: 0] += entry.openQuantity
    }
  }
}

public enum TradeLogbookSortColumn: String, CaseIterable, Hashable, Sendable {
  case purchasedAt
  case item
  case quantity
  case openQuantity
  case buyUnitPrice
  case costPerUnit
  case targetHub
  case plannedSellUnitPrice
  case averageSalePrice
  case currentBestSell
  case plannedProfit
  case realizedProfit
  case status
}

/// Typed logbook sorting: unknown values follow known ones ascending and
/// precede them descending; the entry ID is the final tie-breaker. The target
/// column sorts by the usage rank (Main, Home, Coalition, production,
/// consumption); statuses by their documented life-cycle rank.
public enum TradeLogbookSorter {
  public static func sorted(
    _ entries: [TradeLogbookEntry],
    by column: TradeLogbookSortColumn,
    ascending: Bool,
    currentBestSell: [UUID: Double] = [:]
  ) -> [TradeLogbookEntry] {
    entries.sorted { lhs, rhs in
      if column == .item {
        let order = lhs.typeName.localizedCaseInsensitiveCompare(rhs.typeName)
        if order != .orderedSame {
          return ascending
            ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      let left = value(lhs, column, currentBestSell)
      let right = value(rhs, column, currentBestSell)
      switch (left, right) {
      case (let left?, let right?):
        if left != right { return ascending ? left < right : left > right }
      case (.some, nil):
        return ascending
      case (nil, .some):
        return !ascending
      case (nil, nil):
        break
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private static func value(
    _ entry: TradeLogbookEntry,
    _ column: TradeLogbookSortColumn,
    _ currentBestSell: [UUID: Double]
  ) -> Double? {
    switch column {
    case .item: nil
    case .purchasedAt: entry.purchasedAt.timeIntervalSince1970
    case .quantity: Double(entry.quantity)
    case .openQuantity: Double(entry.openQuantity)
    case .buyUnitPrice: entry.buyUnitPrice
    case .costPerUnit: entry.costPerUnit
    case .targetHub: Double(entry.usage.sortRank)
    case .plannedSellUnitPrice: entry.plannedSellUnitPrice
    case .averageSalePrice: entry.averageSalePrice
    case .currentBestSell: currentBestSell[entry.id]
    case .plannedProfit: entry.plannedProfit
    case .realizedProfit: entry.realizedProfit
    case .status: Double(entry.status.sortRank)
    }
  }
}
