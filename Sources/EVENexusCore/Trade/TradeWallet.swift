import Foundation

/// A personal wallet transaction kept in the trade logbook beyond the ESI
/// 30-day window (HANDEL_PLAN P6). Fields ESI did not deliver stay `nil`.
public struct TradeWalletTransaction: Identifiable, Equatable, Sendable {
  public var id: String { "\(characterID):\(transactionID)" }
  public let characterID: Int64
  public let transactionID: Int64
  public let date: Date
  public let typeID: Int64
  public let quantity: Int64
  public let unitPrice: Double
  public let isBuy: Bool
  public let clientID: Int64
  public let locationID: Int64?
  public let journalRefID: Int64?
  public let isPersonal: Bool?

  public init(
    characterID: Int64,
    transactionID: Int64,
    date: Date,
    typeID: Int64,
    quantity: Int64,
    unitPrice: Double,
    isBuy: Bool,
    clientID: Int64,
    locationID: Int64?,
    journalRefID: Int64?,
    isPersonal: Bool?
  ) {
    self.characterID = characterID
    self.transactionID = transactionID
    self.date = date
    self.typeID = typeID
    self.quantity = quantity
    self.unitPrice = unitPrice
    self.isBuy = isBuy
    self.clientID = clientID
    self.locationID = locationID
    self.journalRefID = journalRefID
    self.isPersonal = isPersonal
  }
}

public struct TradeWalletJournalEntry: Identifiable, Equatable, Sendable {
  public var id: String { "\(characterID):\(journalID)" }
  public let characterID: Int64
  public let journalID: Int64
  public let date: Date
  public let refType: String
  public let amount: Double?
  public let contextID: Int64?
  public let contextIDType: String?
  public let tax: Double?
  public let description: String?

  public init(
    characterID: Int64,
    journalID: Int64,
    date: Date,
    refType: String,
    amount: Double?,
    contextID: Int64?,
    contextIDType: String?,
    tax: Double?,
    description: String?
  ) {
    self.characterID = characterID
    self.journalID = journalID
    self.date = date
    self.refType = refType
    self.amount = amount
    self.contextID = contextID
    self.contextIDType = contextIDType
    self.tax = tax
    self.description = description
  }
}

/// Last wallet hand-over of one character into the logbook.
public struct TradeWalletSyncStatus: Identifiable, Equatable, Sendable {
  public var id: Int64 { characterID }
  public let characterID: Int64
  public let characterName: String
  public let attemptedAt: Date
  public let transactionsState: DataFreshness
  public let journalState: DataFreshness
  /// Last hand-over that delivered transactions; `nil` if none ever did.
  public let transactionsSyncedAt: Date?
  public let journalSyncedAt: Date?
  public let storedTransactionCount: Int
  public let storedJournalCount: Int
  public let diagnostics: [String]
  /// Order data last delivered for order-type detection; `nil` if never.
  public let ordersSyncedAt: Date?

  public init(
    characterID: Int64,
    characterName: String,
    attemptedAt: Date,
    transactionsState: DataFreshness,
    journalState: DataFreshness,
    transactionsSyncedAt: Date?,
    journalSyncedAt: Date?,
    storedTransactionCount: Int,
    storedJournalCount: Int,
    diagnostics: [String],
    ordersSyncedAt: Date? = nil
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.attemptedAt = attemptedAt
    self.transactionsState = transactionsState
    self.journalState = journalState
    self.transactionsSyncedAt = transactionsSyncedAt
    self.journalSyncedAt = journalSyncedAt
    self.storedTransactionCount = storedTransactionCount
    self.storedJournalCount = storedJournalCount
    self.diagnostics = diagnostics
    self.ordersSyncedAt = ordersSyncedAt
  }
}

/// An own market order (open or historic) used to tell an own-order trade
/// from an instant purchase or a direct sale.
public struct TradeWalletOrder: Equatable, Sendable {
  public let characterID: Int64
  public let orderID: Int64
  public let typeID: Int64
  public let locationID: Int64
  public let isBuy: Bool
  public let price: Double
  public let issued: Date?
  /// Duration in days; 0 for an immediate order.
  public let duration: Int?

  public init(
    characterID: Int64,
    orderID: Int64,
    typeID: Int64,
    locationID: Int64,
    isBuy: Bool,
    price: Double,
    issued: Date?,
    duration: Int?
  ) {
    self.characterID = characterID
    self.orderID = orderID
    self.typeID = typeID
    self.locationID = locationID
    self.isBuy = isBuy
    self.price = price
    self.issued = issued
    self.duration = duration
  }
}

/// New rows of one hand-over; repeated hand-overs of the same data add none.
public struct TradeWalletRecordResult: Equatable, Sendable {
  public let newTransactions: Int
  public let newJournalEntries: Int
  public let skippedInvalidTransactions: Int

  public init(
    newTransactions: Int,
    newJournalEntries: Int,
    skippedInvalidTransactions: Int
  ) {
    self.newTransactions = newTransactions
    self.newJournalEntries = newJournalEntries
    self.skippedInvalidTransactions = skippedInvalidTransactions
  }
}
