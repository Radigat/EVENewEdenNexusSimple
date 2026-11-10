import Foundation

/// One production-book row as far as sale receipts need it.
public struct ProductionSaleRow: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let sequenceNumber: Int
  public let recordedAt: Date
  public let typeID: Int64
  public let units: Int64

  public init(
    id: UUID, sequenceNumber: Int, recordedAt: Date, typeID: Int64, units: Int64
  ) {
    self.id = id
    self.sequenceNumber = sequenceNumber
    self.recordedAt = recordedAt
    self.typeID = typeID
    self.units = units
  }
}

public enum ProductionSaleSource: String, Sendable {
  /// Market sale from the wallet transactions.
  case market
  /// `contract_price` income of an accepted contract.
  case contract
  /// Direct ISK transfer (`player_donation`).
  case transfer
  /// Receipt entered by hand and not yet (fully) assigned.
  case manual

  /// Documented sort rank: market, contract, transfer, manual.
  public var rank: Int {
    switch self {
    case .market: 0
    case .contract: 1
    case .transfer: 2
    case .manual: 3
    }
  }
}

/// Why a detected income names no item. The user then chooses the production.
public enum ProductionSaleItemIssue: String, Sendable {
  /// The item lines of the contract are not stored and ESI did not deliver them.
  case contractItemsUnavailable
  /// The contract holds several item types or requested items, so its price
  /// cannot be assigned to one item without guessing.
  case contractHasSeveralItems
  /// An ISK transfer never names an item.
  case transferHasNoItem
}

/// A sale found in the stored wallet data, with the production it is
/// suggested for. Nothing is changed until the user accepts it.
public struct DetectedProductionSale: Identifiable, Sendable {
  /// Receipt ID: `<character>:transaction:<id>` or `<character>:journal:<id>`.
  public let id: String
  public let source: ProductionSaleSource
  /// Character whose wallet holds the booking; `nil` for a manual receipt.
  public let characterID: Int64?
  public let date: Date
  /// Transaction ID or journal ID in the character's wallet.
  public let referenceID: Int64?
  public let contractID: Int64?
  /// The receipt as already stored; it is reused unchanged.
  public let storedEvidence: ProductionSaleEvidence?
  /// Sold type; `nil` while `issue` is set.
  public let typeID: Int64?
  /// Units of the whole receipt; `nil` while `issue` is set.
  public let quantity: Int64?
  /// Units neither assigned to a production nor taken by the trade logbook.
  public let remainingQuantity: Int64?
  /// Price per unit of a market sale.
  public let unitPrice: Double?
  /// Booked amount of a contract or transfer.
  public let totalAmount: Double?
  public let issue: ProductionSaleItemIssue?
  /// `false` when neither party ID nor booking text names the sender.
  public let senderKnown: Bool
  /// Oldest production of the type with free units; `nil` when the type is
  /// unknown or earlier sales of this list already fill every production.
  public let suggestedRowID: UUID?
  public let suggestedQuantity: Int64
  /// Productions the sale may be assigned to, oldest first.
  public let candidateRowIDs: [UUID]

  /// Gross amount of the receipt for display.
  public var grossAmount: Double? {
    if let totalAmount { return totalAmount }
    guard let unitPrice, let quantity else { return nil }
    return unitPrice * Double(quantity)
  }

  /// The receipt to store. A sale without item takes type and quantity from
  /// the chosen production; a resolved sale ignores both arguments.
  public func evidence(
    typeID chosenTypeID: Int64? = nil, quantity chosenQuantity: Int64? = nil
  ) throws -> ProductionSaleEvidence {
    if let storedEvidence { return storedEvidence }
    guard let characterID, let referenceID else {
      throw ConsolidationError.invalid("Ungültiger Verkaufsbeleg.")
    }
    guard let typeID = typeID ?? chosenTypeID,
      let quantity = quantity ?? chosenQuantity, quantity > 0
    else { throw ConsolidationError.invalid("Produktion und Menge auswählen.") }
    switch source {
    case .market:
      guard let unitPrice, unitPrice.isFinite, unitPrice > 0,
        unitPrice * 100 < Double(Int64.max)
      else { throw ConsolidationError.invalid("Ungültiger Wallet-Preis.") }
      return ProductionSaleEvidence(
        id: id, typeID: typeID, quantity: quantity,
        unitPrice: try ISKAmount(hundredths: Int64((unitPrice * 100).rounded())),
        recordedAt: date,
        source: "Wallet · \(characterID) · \(referenceID)")
    case .contract, .transfer, .manual:
      guard let totalAmount, totalAmount.isFinite, totalAmount > 0,
        totalAmount * 100 < Double(Int64.max)
      else { throw ConsolidationError.invalid("Belegbetrag fehlt.") }
      let label =
        source == .contract
        ? "Vertrag · \(contractID ?? referenceID)" : "Überweisung · \(referenceID)"
      return ProductionSaleEvidence(
        id: id, typeID: typeID, quantity: quantity, unitPrice: nil,
        recordedAt: date, source: label,
        totalCents: Int64((totalAmount * 100).rounded()))
    }
  }
}

/// Pure detection of production sales in the stored wallet data.
///
/// - Market sales and contracts with exactly one handed-over item type are
///   suggested for the oldest production of that type with free units
///   (first in, first out in sale order); sales of types without a production
///   are not listed.
/// - Contracts without stored item lines, contracts with several item types
///   or requested items and ISK transfers name no item; they are listed with
///   the reason and every production with free units as candidate.
/// - Transfers sent by an own character are left out.
/// - Units already assigned to a production or taken by the trade logbook are
///   not offered again.
/// - Stored receipts with free units that the wallet data does not explain
///   (entered by hand) are listed as manual receipts.
public enum ProductionSaleDetector {
  public struct Input: Sendable {
    public var rows: [ProductionSaleRow]
    public var workspace: ConsolidationWorkspace
    public var transactions: [TradeWalletTransaction]
    public var journal: [TradeWalletJournalEntry]
    public var contractItems: [TradeWalletContractItem]
    /// Units of a wallet sale the trade logbook already assigned.
    public var tradeAssigned: [TradeWalletLink: Int64]
    /// Own characters by ID with their names.
    public var ownCharacters: [Int64: String]

    public init(
      rows: [ProductionSaleRow],
      workspace: ConsolidationWorkspace,
      transactions: [TradeWalletTransaction],
      journal: [TradeWalletJournalEntry],
      contractItems: [TradeWalletContractItem] = [],
      tradeAssigned: [TradeWalletLink: Int64] = [:],
      ownCharacters: [Int64: String] = [:]
    ) {
      self.rows = rows
      self.workspace = workspace
      self.transactions = transactions
      self.journal = journal
      self.contractItems = contractItems
      self.tradeAssigned = tradeAssigned
      self.ownCharacters = ownCharacters
    }
  }

  public static func transactionEvidenceID(characterID: Int64, transactionID: Int64)
    -> String
  { "\(characterID):transaction:\(transactionID)" }

  public static func journalEvidenceID(characterID: Int64, journalID: Int64) -> String {
    "\(characterID):journal:\(journalID)"
  }

  /// Units of wallet sales assigned to productions, for the trade logbook so
  /// it does not take the same sale again.
  public static func walletSaleQuantities(in workspace: ConsolidationWorkspace)
    -> [TradeWalletLink: Int64]
  {
    var result: [TradeWalletLink: Int64] = [:]
    for sale in workspace.sales {
      let parts = sale.evidenceID.split(separator: ":")
      guard parts.count == 3, parts[1] == "transaction",
        let characterID = Int64(parts[0]), let transactionID = Int64(parts[2])
      else { continue }
      result[
        TradeWalletLink(characterID: characterID, transactionID: transactionID),
        default: 0] += sale.quantity
    }
    return result
  }

  /// Productions oldest first: recording date, number, identity.
  public static func ordered(_ rows: [ProductionSaleRow]) -> [ProductionSaleRow] {
    rows.sorted {
      if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
      if $0.sequenceNumber != $1.sequenceNumber {
        return $0.sequenceNumber < $1.sequenceNumber
      }
      return $0.id.uuidString < $1.id.uuidString
    }
  }

  /// Units of a production no receipt is assigned to. A manual sale entry
  /// does not count: accepting a receipt replaces it.
  public static func freeUnits(in workspace: ConsolidationWorkspace, rows: [ProductionSaleRow])
    -> [UUID: Int64]
  {
    var used: [UUID: Int64] = [:]
    for sale in workspace.sales { used[sale.rowID, default: 0] += sale.quantity }
    return Dictionary(
      uniqueKeysWithValues: rows.map { ($0.id, max(0, $0.units - used[$0.id, default: 0])) })
  }

  public static func detect(_ input: Input) -> [DetectedProductionSale] {
    let rows = ordered(input.rows)
    let free = freeUnits(in: input.workspace, rows: rows)
    let openRows = rows.filter { free[$0.id, default: 0] > 0 }
    let openByType = Dictionary(grouping: openRows, by: \.typeID)
    let knownTypes = Set(rows.map(\.typeID))
    var allocated: [String: Int64] = [:]
    for sale in input.workspace.sales {
      allocated[sale.evidenceID, default: 0] += sale.quantity
    }
    let storedEvidence = Dictionary(
      input.workspace.evidence.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let itemsByContract = Dictionary(grouping: input.contractItems) {
      ContractKey(characterID: $0.characterID, contractID: $0.contractID)
    }
    let ownNames = Set(input.ownCharacters.values)

    var pending: [Pending] = []
    for transaction in input.transactions where !transaction.isBuy {
      guard transaction.quantity > 0, transaction.unitPrice.isFinite,
        transaction.unitPrice > 0, knownTypes.contains(transaction.typeID)
      else { continue }
      let id = transactionEvidenceID(
        characterID: transaction.characterID, transactionID: transaction.transactionID)
      let link = TradeWalletLink(
        characterID: transaction.characterID, transactionID: transaction.transactionID)
      let remaining =
        transaction.quantity - allocated[id, default: 0]
        - input.tradeAssigned[link, default: 0]
      guard remaining > 0 else { continue }
      pending.append(
        Pending(
          id: id, source: .market, characterID: transaction.characterID,
          date: transaction.date, referenceID: transaction.transactionID,
          contractID: nil, stored: storedEvidence[id], typeID: transaction.typeID, quantity: transaction.quantity,
          remaining: remaining, unitPrice: transaction.unitPrice, totalAmount: nil,
          issue: nil, senderKnown: true))
    }
    for entry in input.journal {
      guard let amount = entry.amount, amount.isFinite, amount > 0 else { continue }
      let id = journalEvidenceID(characterID: entry.characterID, journalID: entry.journalID)
      var typeID: Int64?
      var quantity: Int64?
      var issue: ProductionSaleItemIssue?
      var senderKnown = true
      let source: ProductionSaleSource
      var contractID: Int64?
      switch entry.refType {
      case "contract_price":
        source = .contract
        if entry.contextIDType == "contract_id" { contractID = entry.contextID }
        let items =
          contractID.flatMap {
            itemsByContract[ContractKey(characterID: entry.characterID, contractID: $0)]
          } ?? []
        let types = Set(items.map(\.typeID))
        if items.isEmpty {
          issue = .contractItemsUnavailable
        } else if types.count != 1 || items.contains(where: { !$0.isIncluded }) {
          issue = .contractHasSeveralItems
        } else {
          typeID = types.first
          quantity = items.reduce(Int64(0)) { $0 + $1.quantity }
        }
      case "player_donation":
        source = .transfer
        issue = .transferHasNoItem
        let sender = Self.sender(of: entry)
        if let senderID = entry.firstPartyID {
          if input.ownCharacters[senderID] != nil { continue }
        } else if let sender {
          if ownNames.contains(sender) { continue }
        } else {
          senderKnown = false
        }
      default:
        continue
      }
      // A receipt confirmed earlier keeps its type and quantity.
      if let stored = storedEvidence[id] {
        typeID = stored.typeID
        quantity = stored.quantity
        issue = nil
      }
      var remaining: Int64?
      if let typeID, let quantity {
        let left = quantity - allocated[id, default: 0]
        guard left > 0, knownTypes.contains(typeID) else { continue }
        remaining = left
      } else if allocated[id, default: 0] > 0 {
        continue
      }
      pending.append(
        Pending(
          id: id, source: source, characterID: entry.characterID, date: entry.date,
          referenceID: entry.journalID, contractID: contractID,
          stored: storedEvidence[id], typeID: typeID,
          quantity: quantity, remaining: remaining, unitPrice: nil, totalAmount: amount,
          issue: issue, senderKnown: senderKnown))
    }
    // Stored receipts the wallet data no longer explains (entered by hand, or
    // imported from a wallet that is not stored) stay assignable.
    let detectedIDs = Set(pending.map(\.id))
    for stored in input.workspace.evidence where !detectedIDs.contains(stored.id) {
      let left = stored.quantity - allocated[stored.id, default: 0]
      guard left > 0, knownTypes.contains(stored.typeID) else { continue }
      pending.append(
        Pending(
          id: stored.id, source: .manual, characterID: nil, date: stored.recordedAt,
          referenceID: nil, contractID: nil, stored: stored, typeID: stored.typeID,
          quantity: stored.quantity, remaining: left,
          unitPrice: stored.unitPrice.map { Double($0.hundredths) / 100 },
          totalAmount: stored.totalCents.map { Double($0) / 100 }, issue: nil,
          senderKnown: true))
    }
    pending.sort {
      if $0.date != $1.date { return $0.date < $1.date }
      return $0.id < $1.id
    }

    var running = free
    var result: [DetectedProductionSale] = []
    for sale in pending {
      var suggestedRowID: UUID?
      var suggestedQuantity: Int64 = 0
      let candidates: [ProductionSaleRow]
      if let typeID = sale.typeID, let remaining = sale.remaining {
        candidates = openByType[typeID] ?? []
        // Every production of the type is already covered by receipts.
        guard !candidates.isEmpty else { continue }
        if let row = candidates.first(where: { running[$0.id, default: 0] > 0 }) {
          suggestedRowID = row.id
          suggestedQuantity = min(remaining, running[row.id, default: 0])
          running[row.id, default: 0] -= suggestedQuantity
        }
      } else {
        candidates = openRows
        guard !candidates.isEmpty else { continue }
      }
      result.append(
        DetectedProductionSale(
          id: sale.id, source: sale.source, characterID: sale.characterID,
          date: sale.date, referenceID: sale.referenceID, contractID: sale.contractID,
          storedEvidence: sale.stored, typeID: sale.typeID, quantity: sale.quantity,
          remainingQuantity: sale.remaining, unitPrice: sale.unitPrice,
          totalAmount: sale.totalAmount, issue: sale.issue,
          senderKnown: sale.senderKnown, suggestedRowID: suggestedRowID,
          suggestedQuantity: suggestedQuantity, candidateRowIDs: candidates.map(\.id)))
    }
    return result
  }

  /// Sender named by the ESI booking text of a transfer
  /// ("<sender> deposited cash into <receiver>'s account"); used only while
  /// the party ID is missing.
  static func sender(of entry: TradeWalletJournalEntry) -> String? {
    guard let description = entry.description,
      let range = description.range(of: " deposited cash into ")
    else { return nil }
    let name = description[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }

  private struct ContractKey: Hashable {
    let characterID: Int64
    let contractID: Int64
  }

  private struct Pending {
    let id: String
    let source: ProductionSaleSource
    let characterID: Int64?
    let date: Date
    let referenceID: Int64?
    let contractID: Int64?
    var stored: ProductionSaleEvidence? = nil
    let typeID: Int64?
    let quantity: Int64?
    let remaining: Int64?
    let unitPrice: Double?
    let totalAmount: Double?
    let issue: ProductionSaleItemIssue?
    let senderKnown: Bool
  }
}
