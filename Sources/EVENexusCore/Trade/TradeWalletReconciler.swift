import Foundation

/// Inputs of one reconciliation run (HANDEL_PLAN P7).
public struct TradeReconciliationContext: Sendable {
  /// Purchases before this time are never imported.
  public let startDate: Date
  /// Exact station or structure of each configured hub role.
  public let hubLocations: [OpportunityHubRole: Int64]
  public let hubNames: [OpportunityHubRole: String]
  public let fees: [OpportunityHubRole: TradeHubFees]
  /// Materials of active Planner plans; their purchases are not trade.
  public let manufacturingTypeIDs: Set<Int64>
  public let transportBases: [TradeRoute: TradeTransportBasis]
  public let packagedVolumes: [Int64: Double]
  public let typeNames: [Int64: String]
  /// Characters whose own open orders and order history were delivered.
  public let charactersWithOrders: Set<Int64>
  public let now: Date

  public init(
    startDate: Date,
    hubLocations: [OpportunityHubRole: Int64],
    hubNames: [OpportunityHubRole: String] = [:],
    fees: [OpportunityHubRole: TradeHubFees],
    manufacturingTypeIDs: Set<Int64>,
    transportBases: [TradeRoute: TradeTransportBasis],
    packagedVolumes: [Int64: Double],
    typeNames: [Int64: String],
    charactersWithOrders: Set<Int64>,
    now: Date = .now
  ) {
    self.startDate = startDate
    self.hubLocations = hubLocations
    self.hubNames = hubNames
    self.fees = fees
    self.manufacturingTypeIDs = manufacturingTypeIDs
    self.transportBases = transportBases
    self.packagedVolumes = packagedVolumes
    self.typeNames = typeNames
    self.charactersWithOrders = charactersWithOrders
    self.now = now
  }
}

/// Units of a sale transaction that no open logbook purchase took.
public struct TradeUnassignedSale: Identifiable, Equatable, Sendable {
  public var id: String { "\(link.characterID):\(link.transactionID)" }
  public let link: TradeWalletLink
  public let date: Date
  public let typeID: Int64
  public let remainingQuantity: Int64
  public let totalQuantity: Int64
  public let unitPrice: Double
  public let locationID: Int64?
  /// Hub roles of the sale location; empty outside the configured hubs.
  public let hubRoles: [OpportunityHubRole]
  public let kind: TradeSaleKind
  public let kindSource: TradeValueSource
  /// Paid sales tax of the whole transaction from the journal.
  public let salesTaxPaid: Double?

  public init(
    link: TradeWalletLink,
    date: Date,
    typeID: Int64,
    remainingQuantity: Int64,
    totalQuantity: Int64,
    unitPrice: Double,
    locationID: Int64?,
    hubRoles: [OpportunityHubRole],
    kind: TradeSaleKind,
    kindSource: TradeValueSource,
    salesTaxPaid: Double?
  ) {
    self.link = link
    self.date = date
    self.typeID = typeID
    self.remainingQuantity = remainingQuantity
    self.totalQuantity = totalQuantity
    self.unitPrice = unitPrice
    self.locationID = locationID
    self.hubRoles = hubRoles
    self.kind = kind
    self.kindSource = kindSource
    self.salesTaxPaid = salesTaxPaid
  }
}

public struct TradeReconciliationResult: Equatable, Sendable {
  /// New and changed entries; unchanged entries are not repeated.
  public let changedEntries: [TradeLogbookEntry]
  public let unassignedSales: [TradeUnassignedSale]
  /// Purchases skipped because the catalog could not name their type.
  public let unresolvedTypePurchases: Int

  public init(
    changedEntries: [TradeLogbookEntry],
    unassignedSales: [TradeUnassignedSale],
    unresolvedTypePurchases: Int
  ) {
    self.changedEntries = changedEntries
    self.unassignedSales = unassignedSales
    self.unresolvedTypePurchases = unresolvedTypePurchases
  }
}

/// Pure wallet-to-logbook reconciliation (HANDEL_PLAN P7, U6–U8):
/// - every purchase in a configured hub from the start date becomes one
///   entry, keyed by character and transaction so a rerun adds nothing;
/// - target hub: Main → Home, Home → Coalition and Coalition → Home when the
///   other hub is a separate place, otherwise the purchase hub (owner
///   decision 22.10.2026, no station trading);
/// - purchases of active-plan materials become "manufacturing, ignored";
/// - transport is estimated for the quantity and marked as estimated;
/// - sales are assigned first-in-first-out per item and target hub; the
///   rest of a sale of a logged item stays unassigned;
/// - paid sales tax comes from the journal (`transaction_tax`), the broker
///   fee is calculated from the frozen rate;
/// - an own order is detected from the character's orders; without order
///   data a purchase counts as instant and a sale as own sell order
///   ("assumed").
public enum TradeWalletReconciler {
  public static func reconcile(
    entries: [TradeLogbookEntry],
    transactions: [TradeWalletTransaction],
    journal: [TradeWalletJournalEntry],
    orders: [TradeWalletOrder],
    context: TradeReconciliationContext
  ) -> TradeReconciliationResult {
    var working = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    var changed = Set<UUID>()
    var order: [UUID] = entries.map(\.id)
    let linkedPurchases = Set(entries.compactMap(\.walletLink))
    let rolesByLocation = Self.rolesByLocation(context.hubLocations)
    let taxByTransaction = Self.paidTax(journal)
    let ordersByKey = Dictionary(grouping: orders) {
      OrderKey(
        characterID: $0.characterID,
        typeID: $0.typeID,
        locationID: $0.locationID,
        isBuy: $0.isBuy
      )
    }
    func isSeparate(_ role: OpportunityHubRole, from other: OpportunityHubRole) -> Bool {
      context.hubLocations[role] != nil
        && context.hubLocations[role] != context.hubLocations[other]
    }
    let sorted = transactions.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.characterID != $1.characterID { return $0.characterID < $1.characterID }
      return $0.transactionID < $1.transactionID
    }
    var unresolved = 0

    for transaction in sorted where transaction.isBuy {
      let link = TradeWalletLink(
        characterID: transaction.characterID,
        transactionID: transaction.transactionID
      )
      guard transaction.date >= context.startDate,
        !linkedPurchases.contains(link),
        let location = transaction.locationID,
        let source = rolesByLocation[location]?.first
      else { continue }
      guard let name = context.typeNames[transaction.typeID] else {
        unresolved += 1
        continue
      }
      let preferredTarget: OpportunityHubRole =
        switch source {
        case .main, .coalition: .home
        case .home: .coalition
        }
      let target =
        isSeparate(preferredTarget, from: source) ? preferredTarget : source
      let detection = ownOrder(transaction, ordersByKey, context)
      let buySide: TradeQuoteSide = detection.isOwnOrder ? .maxBuy : .minSell
      let brokerRate =
        buySide == .maxBuy ? context.fees[source]?.brokerFeeRate : nil
      let unitCost: Double? =
        buySide == .maxBuy
        ? brokerRate.map { transaction.unitPrice * (1 + $0) }
        : transaction.unitPrice
      let transport: Double?
      let estimated: Bool
      if source == target {
        transport = 0
        estimated = false
      } else {
        transport = context.transportBases[
          TradeRoute(source: source, target: target)
        ].flatMap { basis in
          TradeCalculator.transportQuote(
            typeID: transaction.typeID,
            name: name,
            quantity: transaction.quantity,
            packagedVolumePerUnit: context.packagedVolumes[transaction.typeID],
            unitCollateral: unitCost,
            transport: basis
          ).total
        }
        estimated = true
      }
      let targetFees = context.fees[target]
      let entry = TradeLogbookEntry(
        createdAt: context.now,
        updatedAt: context.now,
        purchasedAt: transaction.date,
        typeID: transaction.typeID,
        typeName: name,
        quantity: transaction.quantity,
        buyUnitPrice: transaction.unitPrice,
        buySide: buySide,
        buyBrokerFeeRate: brokerRate,
        sourceRole: source,
        sourceLocationName: context.hubNames[source],
        targetRole: target,
        targetLocationName: context.hubNames[target],
        plannedSellUnitPrice: nil,
        transportCostTotal: transport,
        salesTaxRate: targetFees?.salesTaxRate,
        sellBrokerFeeRate: targetFees?.brokerFeeRate,
        status: context.manufacturingTypeIDs.contains(transaction.typeID)
          ? .manufacturingIgnored : .bought,
        walletLink: link,
        buySideSource: detection.source,
        transportEstimated: estimated
      )
      working[entry.id] = entry
      order.append(entry.id)
      changed.insert(entry.id)
    }

    var assignedBySale: [TradeWalletLink: Int64] = [:]
    for entry in working.values {
      for sale in entry.sales {
        if let link = sale.walletLink {
          assignedBySale[link, default: 0] += sale.quantity
        }
      }
    }
    let loggedTypeIDs = Set(working.values.map(\.typeID))
    var unassigned: [TradeUnassignedSale] = []

    for transaction in sorted where !transaction.isBuy {
      guard transaction.date >= context.startDate else { continue }
      let link = TradeWalletLink(
        characterID: transaction.characterID,
        transactionID: transaction.transactionID
      )
      var remaining = transaction.quantity - assignedBySale[link, default: 0]
      guard remaining > 0 else { continue }
      let roles = transaction.locationID.flatMap { rolesByLocation[$0] } ?? []
      let detection = ownOrder(transaction, ordersByKey, context)
      let kind: TradeSaleKind =
        detection.isOwnOrder ? .listedSellOrder : .directToBuyOrder
      let tax = taxByTransaction[link]
      let candidates = working.values.filter {
        $0.typeID == transaction.typeID
          && roles.contains($0.targetRole)
          && $0.openQuantity > 0
          && $0.purchasedAt <= transaction.date
      }.sorted {
        $0.purchasedAt != $1.purchasedAt
          ? $0.purchasedAt < $1.purchasedAt
          : $0.id.uuidString < $1.id.uuidString
      }
      for candidate in candidates where remaining > 0 {
        guard var entry = working[candidate.id] else { continue }
        let take = min(remaining, entry.openQuantity)
        guard take > 0 else { continue }
        entry.sales.append(
          TradeLogbookSale(
            soldAt: transaction.date,
            quantity: take,
            unitPrice: transaction.unitPrice,
            kind: kind,
            kindSource: detection.source,
            salesTaxPaid: tax.map { $0 * Double(take) / Double(transaction.quantity) },
            walletLink: link
          )
        )
        if entry.soldQuantity >= entry.quantity { entry.status = .sold }
        entry.updatedAt = context.now
        working[entry.id] = entry
        changed.insert(entry.id)
        remaining -= take
      }
      if remaining > 0, loggedTypeIDs.contains(transaction.typeID) {
        unassigned.append(
          TradeUnassignedSale(
            link: link,
            date: transaction.date,
            typeID: transaction.typeID,
            remainingQuantity: remaining,
            totalQuantity: transaction.quantity,
            unitPrice: transaction.unitPrice,
            locationID: transaction.locationID,
            hubRoles: roles,
            kind: kind,
            kindSource: detection.source,
            salesTaxPaid: tax
          )
        )
      }
    }

    return TradeReconciliationResult(
      changedEntries: order.filter(changed.contains).compactMap { working[$0] },
      unassignedSales: unassigned,
      unresolvedTypePurchases: unresolved
    )
  }

  /// Manual assignment of an unassigned sale to one entry; takes as many
  /// units as both still have. `nil` when nothing can be assigned.
  public static func assign(
    _ sale: TradeUnassignedSale,
    to entry: TradeLogbookEntry,
    now: Date = .now
  ) -> TradeLogbookEntry? {
    guard entry.typeID == sale.typeID else { return nil }
    let take = min(sale.remainingQuantity, entry.openQuantity)
    guard take > 0 else { return nil }
    var updated = entry
    updated.sales.append(
      TradeLogbookSale(
        soldAt: sale.date,
        quantity: take,
        unitPrice: sale.unitPrice,
        kind: sale.kind,
        kindSource: sale.kindSource,
        salesTaxPaid: sale.salesTaxPaid.map {
          $0 * Double(take) / Double(sale.totalQuantity)
        },
        walletLink: sale.link
      )
    )
    if updated.soldQuantity >= updated.quantity { updated.status = .sold }
    updated.updatedAt = now
    return updated
  }

  private struct OrderKey: Hashable {
    let characterID: Int64
    let typeID: Int64
    let locationID: Int64
    let isBuy: Bool
  }

  private static func rolesByLocation(
    _ hubs: [OpportunityHubRole: Int64]
  ) -> [Int64: [OpportunityHubRole]] {
    var result: [Int64: [OpportunityHubRole]] = [:]
    for role in OpportunityHubRole.allCases {
      if let location = hubs[role] { result[location, default: []].append(role) }
    }
    return result
  }

  /// Paid sales tax per sale transaction (positive ISK).
  private static func paidTax(
    _ journal: [TradeWalletJournalEntry]
  ) -> [TradeWalletLink: Double] {
    var result: [TradeWalletLink: Double] = [:]
    for entry in journal
    where entry.refType == "transaction_tax"
      && entry.contextIDType == "market_transaction_id"
    {
      guard let transactionID = entry.contextID,
        let amount = entry.amount, amount.isFinite
      else { continue }
      result[
        TradeWalletLink(characterID: entry.characterID, transactionID: transactionID),
        default: 0
      ] += abs(amount)
    }
    return result
  }

  /// An own order of the same character, item, place and side that was
  /// active at the trade time.
  private static func ownOrder(
    _ transaction: TradeWalletTransaction,
    _ ordersByKey: [OrderKey: [TradeWalletOrder]],
    _ context: TradeReconciliationContext
  ) -> (isOwnOrder: Bool, source: TradeValueSource) {
    let assumedOwnOrder = !transaction.isBuy
    guard context.charactersWithOrders.contains(transaction.characterID),
      let location = transaction.locationID
    else { return (assumedOwnOrder, .assumed) }
    let key = OrderKey(
      characterID: transaction.characterID,
      typeID: transaction.typeID,
      locationID: location,
      isBuy: transaction.isBuy
    )
    let matches = (ordersByKey[key] ?? []).contains { order in
      guard let issued = order.issued else { return true }
      guard issued <= transaction.date else { return false }
      // A duration of 0 is an immediate order, i.e. an instant trade.
      guard let duration = order.duration else { return true }
      guard duration > 0 else { return false }
      let end = issued.addingTimeInterval(Double(duration + 1) * 86_400)
      return transaction.date <= end
    }
    return (matches, .detected)
  }
}
