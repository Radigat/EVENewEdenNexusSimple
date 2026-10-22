import CSQLite
import Foundation

public enum TradeLogbookStoreError: Error, Equatable, Sendable {
  case database(String)
  case invalidRow
  /// The file was written by a newer app version; it is left untouched.
  case unsupportedSchemaVersion(Int)
}

/// Purchase logbook of the Trade area in its own SQLite file
/// (`dataRoot/trade/trade-logbook.sqlite`, HANDEL_PLAN P5). It never touches
/// the SwiftData store or its migration chain.
public actor TradeLogbookStore {
  public static let schemaVersion = 3

  private let database: TradeLogbookSQLiteDatabase

  public nonisolated static func open(url: URL) async throws
    -> TradeLogbookStore
  {
    let task = Task.detached(priority: .utility) {
      try TradeLogbookStore(url: url)
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  public init(url: URL, fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    database = try TradeLogbookSQLiteDatabase(url: url)
    try database.execute("PRAGMA journal_mode=WAL")
    try database.execute("PRAGMA synchronous=NORMAL")
    try database.execute("PRAGMA foreign_keys=ON")
    try Self.migrate(database)
  }

  public func close() {
    database.close()
  }

  public func entries() throws -> [TradeLogbookEntry] {
    var salesByPurchase: [String: [TradeLogbookSale]] = [:]
    for row in try database.query(
      "SELECT * FROM trade_sales ORDER BY sold_at, id"
    ) {
      guard let purchaseID = row.string("purchase_id"),
        let id = row.string("id").flatMap(UUID.init(uuidString:)),
        let soldAt = row.double("sold_at"),
        let quantity = row.int64("quantity"),
        let unitPrice = row.double("unit_price"),
        let kind = row.string("kind").flatMap(TradeSaleKind.init(rawValue:))
      else { throw TradeLogbookStoreError.invalidRow }
      salesByPurchase[purchaseID, default: []].append(
        TradeLogbookSale(
          id: id,
          soldAt: Date(timeIntervalSince1970: soldAt),
          quantity: quantity,
          unitPrice: unitPrice,
          kind: kind,
          kindSource: row.string("kind_source")
            .flatMap(TradeValueSource.init(rawValue:)) ?? .manual,
          salesTaxPaid: row.double("sales_tax_paid"),
          walletLink: Self.walletLink(row)
        )
      )
    }
    return try database.query(
      "SELECT * FROM trade_purchases ORDER BY purchased_at DESC, id"
    ).map { row in
      guard let rawID = row.string("id"),
        let id = UUID(uuidString: rawID),
        let createdAt = row.double("created_at"),
        let updatedAt = row.double("updated_at"),
        let purchasedAt = row.double("purchased_at"),
        let typeID = row.int64("type_id"),
        let typeName = row.string("type_name"),
        let quantity = row.int64("quantity"),
        let buyUnitPrice = row.double("buy_unit_price"),
        let buySide = row.string("buy_side").flatMap(TradeQuoteSide.init(rawValue:)),
        let sourceRole = row.string("source_role")
          .flatMap(OpportunityHubRole.init(rawValue:)),
        let targetRole = row.string("target_role")
          .flatMap(OpportunityHubRole.init(rawValue:)),
        let status = row.string("status")
          .flatMap(TradeLogbookStatus.init(rawValue:))
      else { throw TradeLogbookStoreError.invalidRow }
      return TradeLogbookEntry(
        id: id,
        createdAt: Date(timeIntervalSince1970: createdAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        purchasedAt: Date(timeIntervalSince1970: purchasedAt),
        typeID: typeID,
        typeName: typeName,
        quantity: quantity,
        buyUnitPrice: buyUnitPrice,
        buySide: buySide,
        buyBrokerFeeRate: row.double("buy_broker_fee_rate"),
        sourceRole: sourceRole,
        sourceLocationName: row.string("source_location_name"),
        targetRole: targetRole,
        targetLocationName: row.string("target_location_name"),
        plannedSellUnitPrice: row.double("planned_sell_unit_price"),
        transportCostTotal: row.double("transport_cost_total"),
        salesTaxRate: row.double("sales_tax_rate"),
        sellBrokerFeeRate: row.double("sell_broker_fee_rate"),
        status: status,
        notes: row.string("notes") ?? "",
        sales: salesByPurchase[rawID] ?? [],
        walletLink: Self.walletLink(row),
        buySideSource: row.string("buy_side_source")
          .flatMap(TradeValueSource.init(rawValue:)) ?? .manual,
        transportEstimated: (row.int64("transport_estimated") ?? 0) != 0
      )
    }
  }

  /// Inserts or replaces one entry together with its complete sale list.
  public func save(_ entry: TradeLogbookEntry) throws {
    try entry.validate()
    try database.transaction { try write(entry) }
  }

  /// Saves several entries in one transaction; nothing is written when one
  /// of them is invalid.
  public func save(_ entries: [TradeLogbookEntry]) throws {
    for entry in entries { try entry.validate() }
    try database.transaction {
      for entry in entries { try write(entry) }
    }
  }

  private func write(_ entry: TradeLogbookEntry) throws {
    do {
      try database.run(
        """
        INSERT INTO trade_purchases (
          id, created_at, updated_at, purchased_at, type_id, type_name,
          quantity, buy_unit_price, buy_side, buy_broker_fee_rate,
          source_role, source_location_name, target_role,
          target_location_name, planned_sell_unit_price,
          transport_cost_total, sales_tax_rate, sell_broker_fee_rate,
          status, notes, wallet_character_id, wallet_transaction_id,
          buy_side_source, transport_estimated
        ) VALUES (
          ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
        ON CONFLICT(id) DO UPDATE SET
          updated_at = excluded.updated_at,
          purchased_at = excluded.purchased_at,
          type_id = excluded.type_id,
          type_name = excluded.type_name,
          quantity = excluded.quantity,
          buy_unit_price = excluded.buy_unit_price,
          buy_side = excluded.buy_side,
          buy_broker_fee_rate = excluded.buy_broker_fee_rate,
          source_role = excluded.source_role,
          source_location_name = excluded.source_location_name,
          target_role = excluded.target_role,
          target_location_name = excluded.target_location_name,
          planned_sell_unit_price = excluded.planned_sell_unit_price,
          transport_cost_total = excluded.transport_cost_total,
          sales_tax_rate = excluded.sales_tax_rate,
          sell_broker_fee_rate = excluded.sell_broker_fee_rate,
          status = excluded.status,
          notes = excluded.notes,
          wallet_character_id = excluded.wallet_character_id,
          wallet_transaction_id = excluded.wallet_transaction_id,
          buy_side_source = excluded.buy_side_source,
          transport_estimated = excluded.transport_estimated
        """,
        [
          .text(entry.id.uuidString),
          .real(entry.createdAt.timeIntervalSince1970),
          .real(entry.updatedAt.timeIntervalSince1970),
          .real(entry.purchasedAt.timeIntervalSince1970),
          .integer(entry.typeID),
          .text(entry.typeName),
          .integer(entry.quantity),
          .real(entry.buyUnitPrice),
          .text(entry.buySide.rawValue),
          .optional(entry.buyBrokerFeeRate),
          .text(entry.sourceRole.rawValue),
          .optionalText(entry.sourceLocationName),
          .text(entry.targetRole.rawValue),
          .optionalText(entry.targetLocationName),
          .optional(entry.plannedSellUnitPrice),
          .optional(entry.transportCostTotal),
          .optional(entry.salesTaxRate),
          .optional(entry.sellBrokerFeeRate),
          .text(entry.status.rawValue),
          .text(entry.notes),
          entry.walletLink.map { .integer($0.characterID) } ?? .null,
          entry.walletLink.map { .integer($0.transactionID) } ?? .null,
          .text(entry.buySideSource.rawValue),
          .integer(entry.transportEstimated ? 1 : 0),
        ]
      )
      try database.run(
        "DELETE FROM trade_sales WHERE purchase_id = ?",
        [.text(entry.id.uuidString)]
      )
      for sale in entry.sales {
        try database.run(
          """
          INSERT INTO trade_sales (
            id, purchase_id, sold_at, quantity, unit_price, kind,
            kind_source, sales_tax_paid, wallet_character_id,
            wallet_transaction_id
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
          [
            .text(sale.id.uuidString),
            .text(entry.id.uuidString),
            .real(sale.soldAt.timeIntervalSince1970),
            .integer(sale.quantity),
            .real(sale.unitPrice),
            .text(sale.kind.rawValue),
            .text(sale.kindSource.rawValue),
            .optional(sale.salesTaxPaid),
            sale.walletLink.map { .integer($0.characterID) } ?? .null,
            sale.walletLink.map { .integer($0.transactionID) } ?? .null,
          ]
        )
      }
    }
  }

  private static func walletLink(_ row: TradeLogbookSQLiteRow) -> TradeWalletLink? {
    guard let character = row.int64("wallet_character_id"),
      let transaction = row.int64("wallet_transaction_id")
    else { return nil }
    return TradeWalletLink(characterID: character, transactionID: transaction)
  }

  public func setting(_ key: String) throws -> String? {
    try database.query(
      "SELECT value FROM trade_settings WHERE key = ?",
      [.text(key)]
    ).first?.string("value")
  }

  public func setSetting(_ key: String, value: String?) throws {
    if let value {
      try database.run(
        """
        INSERT INTO trade_settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        [.text(key), .text(value)]
      )
    } else {
      try database.run("DELETE FROM trade_settings WHERE key = ?", [.text(key)])
    }
  }

  /// Removes an entry and its sales; only on an explicit user action.
  public func delete(entryID: UUID) throws {
    try database.run(
      "DELETE FROM trade_purchases WHERE id = ?",
      [.text(entryID.uuidString)]
    )
  }

  static func migrate(_ database: TradeLogbookSQLiteDatabase) throws {
    let version = Int(
      try database.query("PRAGMA user_version").first?.int64("user_version")
        ?? 0
    )
    guard version <= schemaVersion else {
      throw TradeLogbookStoreError.unsupportedSchemaVersion(version)
    }
    if version < 1 {
      try database.transaction {
        try database.execute(
          """
          CREATE TABLE IF NOT EXISTS trade_purchases (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            purchased_at REAL NOT NULL,
            type_id INTEGER NOT NULL,
            type_name TEXT NOT NULL,
            quantity INTEGER NOT NULL CHECK (quantity > 0),
            buy_unit_price REAL NOT NULL,
            buy_side TEXT NOT NULL,
            buy_broker_fee_rate REAL,
            source_role TEXT NOT NULL,
            source_location_name TEXT,
            target_role TEXT NOT NULL,
            target_location_name TEXT,
            planned_sell_unit_price REAL,
            transport_cost_total REAL,
            sales_tax_rate REAL,
            sell_broker_fee_rate REAL,
            status TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT ''
          );
          CREATE TABLE IF NOT EXISTS trade_sales (
            id TEXT PRIMARY KEY,
            purchase_id TEXT NOT NULL
              REFERENCES trade_purchases(id) ON DELETE CASCADE,
            sold_at REAL NOT NULL,
            quantity INTEGER NOT NULL CHECK (quantity > 0),
            unit_price REAL NOT NULL,
            kind TEXT NOT NULL
          );
          CREATE INDEX IF NOT EXISTS idx_trade_sales_purchase
            ON trade_sales(purchase_id);
          CREATE INDEX IF NOT EXISTS idx_trade_purchases_type
            ON trade_purchases(type_id, target_role);
          PRAGMA user_version = 1;
          """
        )
      }
    }
    if version < 2 {
      // HANDEL_PLAN P6: personal wallet data, kept beyond the ESI window.
      try database.transaction {
        try database.execute(
          """
          CREATE TABLE IF NOT EXISTS wallet_transactions (
            character_id INTEGER NOT NULL,
            transaction_id INTEGER NOT NULL,
            date REAL NOT NULL,
            type_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            is_buy INTEGER NOT NULL,
            client_id INTEGER NOT NULL,
            location_id INTEGER,
            journal_ref_id INTEGER,
            is_personal INTEGER,
            first_seen_at REAL NOT NULL,
            PRIMARY KEY (character_id, transaction_id)
          );
          CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type
            ON wallet_transactions(type_id, is_buy, date);
          CREATE TABLE IF NOT EXISTS wallet_journal (
            character_id INTEGER NOT NULL,
            journal_id INTEGER NOT NULL,
            date REAL NOT NULL,
            ref_type TEXT NOT NULL,
            amount REAL,
            context_id INTEGER,
            context_id_type TEXT,
            tax REAL,
            description TEXT,
            first_seen_at REAL NOT NULL,
            PRIMARY KEY (character_id, journal_id)
          );
          CREATE INDEX IF NOT EXISTS idx_wallet_journal_context
            ON wallet_journal(context_id_type, context_id);
          CREATE TABLE IF NOT EXISTS wallet_sync_status (
            character_id INTEGER PRIMARY KEY,
            character_name TEXT NOT NULL,
            attempted_at REAL NOT NULL,
            transactions_state TEXT NOT NULL,
            journal_state TEXT NOT NULL,
            transactions_synced_at REAL,
            journal_synced_at REAL,
            diagnostics TEXT NOT NULL DEFAULT ''
          );
          PRAGMA user_version = 2;
          """
        )
      }
    }
    if version < 3 {
      // HANDEL_PLAN P7: order data, wallet links and reconciliation settings.
      try database.transaction {
        try database.execute(
          """
          CREATE TABLE IF NOT EXISTS wallet_orders (
            character_id INTEGER NOT NULL,
            order_id INTEGER NOT NULL,
            type_id INTEGER NOT NULL,
            location_id INTEGER NOT NULL,
            is_buy INTEGER NOT NULL,
            price REAL NOT NULL,
            issued REAL,
            duration INTEGER,
            first_seen_at REAL NOT NULL,
            PRIMARY KEY (character_id, order_id)
          );
          CREATE INDEX IF NOT EXISTS idx_wallet_orders_match
            ON wallet_orders(character_id, type_id, location_id, is_buy);
          ALTER TABLE wallet_sync_status ADD COLUMN orders_synced_at REAL;
          ALTER TABLE trade_purchases ADD COLUMN wallet_character_id INTEGER;
          ALTER TABLE trade_purchases ADD COLUMN wallet_transaction_id INTEGER;
          ALTER TABLE trade_purchases
            ADD COLUMN buy_side_source TEXT NOT NULL DEFAULT 'manual';
          ALTER TABLE trade_purchases
            ADD COLUMN transport_estimated INTEGER NOT NULL DEFAULT 0;
          CREATE UNIQUE INDEX IF NOT EXISTS idx_trade_purchases_wallet
            ON trade_purchases(wallet_character_id, wallet_transaction_id)
            WHERE wallet_transaction_id IS NOT NULL;
          ALTER TABLE trade_sales ADD COLUMN wallet_character_id INTEGER;
          ALTER TABLE trade_sales ADD COLUMN wallet_transaction_id INTEGER;
          ALTER TABLE trade_sales
            ADD COLUMN kind_source TEXT NOT NULL DEFAULT 'manual';
          ALTER TABLE trade_sales ADD COLUMN sales_tax_paid REAL;
          CREATE INDEX IF NOT EXISTS idx_trade_sales_wallet
            ON trade_sales(wallet_character_id, wallet_transaction_id);
          CREATE TABLE IF NOT EXISTS trade_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );
          PRAGMA user_version = 3;
          """
        )
      }
    }
  }
}

// MARK: Wallet data (HANDEL_PLAN P6)

extension TradeLogbookStore {
  /// Stores one character's wallet hand-over idempotently: rows are keyed
  /// by character and ESI ID, so a repeated sync adds nothing. The status is
  /// recorded even when ESI delivered no data (missing scope, error).
  @discardableResult
  public func recordWallet(
    characterID: Int64,
    characterName: String,
    transactions: Sourced<[ESIWalletTransactionDTO]>,
    journal: Sourced<[ESIWalletJournalDTO]>,
    orders: [Sourced<[ESICharacterOrderDTO]>] = [],
    at now: Date = .now
  ) throws -> TradeWalletRecordResult {
    let transactionsBefore = try count("wallet_transactions", characterID)
    let journalBefore = try count("wallet_journal", characterID)
    var skipped = 0
    let deliversTransactions =
      transactions.value != nil
      && (transactions.state == .fresh || transactions.state == .partial)
    let deliversJournal =
      journal.value != nil
      && (journal.state == .fresh || journal.state == .partial)
    // Open orders and order history only count when both arrived.
    let deliversOrders =
      !orders.isEmpty
      && orders.allSatisfy {
        $0.value != nil && ($0.state == .fresh || $0.state == .partial)
      }
    try database.transaction {
      for order in orders.compactMap(\.value).joined() {
        guard order.price.isFinite else { continue }
        try database.run(
          """
          INSERT INTO wallet_orders (
            character_id, order_id, type_id, location_id, is_buy, price,
            issued, duration, first_seen_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(character_id, order_id) DO UPDATE SET
            price = excluded.price,
            issued = COALESCE(excluded.issued, issued),
            duration = COALESCE(excluded.duration, duration)
          """,
          [
            .integer(characterID),
            .integer(order.orderID),
            .integer(order.typeID),
            .integer(order.locationID),
            .integer(order.isBuyOrder ? 1 : 0),
            .real(order.price),
            .optional(order.issued?.timeIntervalSince1970),
            order.duration.map { .integer(Int64($0)) } ?? .null,
            .real(now.timeIntervalSince1970),
          ]
        )
      }
      for transaction in transactions.value ?? [] {
        guard transaction.quantity > 0,
          transaction.unitPrice.isFinite,
          transaction.unitPrice >= 0
        else {
          skipped += 1
          continue
        }
        try database.run(
          """
          INSERT INTO wallet_transactions (
            character_id, transaction_id, date, type_id, quantity,
            unit_price, is_buy, client_id, location_id, journal_ref_id,
            is_personal, first_seen_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(character_id, transaction_id) DO UPDATE SET
            location_id = COALESCE(excluded.location_id, location_id),
            journal_ref_id = COALESCE(excluded.journal_ref_id, journal_ref_id),
            is_personal = COALESCE(excluded.is_personal, is_personal)
          """,
          [
            .integer(characterID),
            .integer(transaction.transactionID),
            .real(transaction.date.timeIntervalSince1970),
            .integer(transaction.typeID),
            .integer(transaction.quantity),
            .real(transaction.unitPrice),
            .integer(transaction.isBuy ? 1 : 0),
            .integer(transaction.clientID),
            transaction.locationID.map { .integer($0) } ?? .null,
            transaction.journalRefID.map { .integer($0) } ?? .null,
            transaction.isPersonal.map { .integer($0 ? 1 : 0) } ?? .null,
            .real(now.timeIntervalSince1970),
          ]
        )
      }
      for entry in journal.value ?? [] {
        try database.run(
          """
          INSERT INTO wallet_journal (
            character_id, journal_id, date, ref_type, amount, context_id,
            context_id_type, tax, description, first_seen_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(character_id, journal_id) DO NOTHING
          """,
          [
            .integer(characterID),
            .integer(entry.journalID),
            .real(entry.date.timeIntervalSince1970),
            .text(entry.refType),
            .optional(entry.amount.flatMap { $0.isFinite ? $0 : nil }),
            entry.contextID.map { .integer($0) } ?? .null,
            .optionalText(entry.contextIDType),
            .optional(entry.tax.flatMap { $0.isFinite ? $0 : nil }),
            .optionalText(entry.description),
            .real(now.timeIntervalSince1970),
          ]
        )
      }
      try database.run(
        """
        INSERT INTO wallet_sync_status (
          character_id, character_name, attempted_at, transactions_state,
          journal_state, transactions_synced_at, journal_synced_at,
          diagnostics, orders_synced_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(character_id) DO UPDATE SET
          orders_synced_at = COALESCE(
            excluded.orders_synced_at, orders_synced_at),
          character_name = excluded.character_name,
          attempted_at = excluded.attempted_at,
          transactions_state = excluded.transactions_state,
          journal_state = excluded.journal_state,
          transactions_synced_at = COALESCE(
            excluded.transactions_synced_at, transactions_synced_at),
          journal_synced_at = COALESCE(
            excluded.journal_synced_at, journal_synced_at),
          diagnostics = excluded.diagnostics
        """,
        [
          .integer(characterID),
          .text(characterName),
          .real(now.timeIntervalSince1970),
          .text(transactions.state.rawValue),
          .text(journal.state.rawValue),
          deliversTransactions ? .real(now.timeIntervalSince1970) : .null,
          deliversJournal ? .real(now.timeIntervalSince1970) : .null,
          .text((transactions.diagnostics + journal.diagnostics).joined(separator: "\n")),
          deliversOrders ? .real(now.timeIntervalSince1970) : .null,
        ]
      )
    }
    return TradeWalletRecordResult(
      newTransactions: try count("wallet_transactions", characterID)
        - transactionsBefore,
      newJournalEntries: try count("wallet_journal", characterID) - journalBefore,
      skippedInvalidTransactions: skipped
    )
  }

  public func walletSyncStatuses() throws -> [TradeWalletSyncStatus] {
    try database.query(
      """
      SELECT s.*,
        (SELECT COUNT(*) FROM wallet_transactions t
          WHERE t.character_id = s.character_id) AS transaction_count,
        (SELECT COUNT(*) FROM wallet_journal j
          WHERE j.character_id = s.character_id) AS journal_count
      FROM wallet_sync_status s
      ORDER BY s.character_name COLLATE NOCASE, s.character_id
      """
    ).map { row in
      guard let characterID = row.int64("character_id"),
        let name = row.string("character_name"),
        let attemptedAt = row.double("attempted_at"),
        let transactionsState = row.string("transactions_state")
          .flatMap(DataFreshness.init(rawValue:)),
        let journalState = row.string("journal_state")
          .flatMap(DataFreshness.init(rawValue:))
      else { throw TradeLogbookStoreError.invalidRow }
      return TradeWalletSyncStatus(
        characterID: characterID,
        characterName: name,
        attemptedAt: Date(timeIntervalSince1970: attemptedAt),
        transactionsState: transactionsState,
        journalState: journalState,
        transactionsSyncedAt: row.double("transactions_synced_at")
          .map(Date.init(timeIntervalSince1970:)),
        journalSyncedAt: row.double("journal_synced_at")
          .map(Date.init(timeIntervalSince1970:)),
        storedTransactionCount: Int(row.int64("transaction_count") ?? 0),
        storedJournalCount: Int(row.int64("journal_count") ?? 0),
        diagnostics: (row.string("diagnostics") ?? "")
          .split(separator: "\n").map(String.init),
        ordersSyncedAt: row.double("orders_synced_at")
          .map(Date.init(timeIntervalSince1970:))
      )
    }
  }

  public func walletTransactions(
    characterID: Int64? = nil
  ) throws -> [TradeWalletTransaction] {
    let filter = characterID == nil ? "" : "WHERE character_id = ?"
    return try database.query(
      "SELECT * FROM wallet_transactions \(filter) ORDER BY date, character_id, transaction_id",
      characterID.map { [.integer($0)] } ?? []
    ).map { row in
      guard let character = row.int64("character_id"),
        let transactionID = row.int64("transaction_id"),
        let date = row.double("date"),
        let typeID = row.int64("type_id"),
        let quantity = row.int64("quantity"),
        let unitPrice = row.double("unit_price"),
        let isBuy = row.int64("is_buy"),
        let clientID = row.int64("client_id")
      else { throw TradeLogbookStoreError.invalidRow }
      return TradeWalletTransaction(
        characterID: character,
        transactionID: transactionID,
        date: Date(timeIntervalSince1970: date),
        typeID: typeID,
        quantity: quantity,
        unitPrice: unitPrice,
        isBuy: isBuy != 0,
        clientID: clientID,
        locationID: row.int64("location_id"),
        journalRefID: row.int64("journal_ref_id"),
        isPersonal: row.int64("is_personal").map { $0 != 0 }
      )
    }
  }

  public func walletJournal(
    characterID: Int64? = nil
  ) throws -> [TradeWalletJournalEntry] {
    let filter = characterID == nil ? "" : "WHERE character_id = ?"
    return try database.query(
      "SELECT * FROM wallet_journal \(filter) ORDER BY date, character_id, journal_id",
      characterID.map { [.integer($0)] } ?? []
    ).map { row in
      guard let character = row.int64("character_id"),
        let journalID = row.int64("journal_id"),
        let date = row.double("date"),
        let refType = row.string("ref_type")
      else { throw TradeLogbookStoreError.invalidRow }
      return TradeWalletJournalEntry(
        characterID: character,
        journalID: journalID,
        date: Date(timeIntervalSince1970: date),
        refType: refType,
        amount: row.double("amount"),
        contextID: row.int64("context_id"),
        contextIDType: row.string("context_id_type"),
        tax: row.double("tax"),
        description: row.string("description")
      )
    }
  }

  public func walletOrders() throws -> [TradeWalletOrder] {
    try database.query(
      "SELECT * FROM wallet_orders ORDER BY character_id, order_id"
    ).map { row in
      guard let character = row.int64("character_id"),
        let orderID = row.int64("order_id"),
        let typeID = row.int64("type_id"),
        let locationID = row.int64("location_id"),
        let isBuy = row.int64("is_buy"),
        let price = row.double("price")
      else { throw TradeLogbookStoreError.invalidRow }
      return TradeWalletOrder(
        characterID: character,
        orderID: orderID,
        typeID: typeID,
        locationID: locationID,
        isBuy: isBuy != 0,
        price: price,
        issued: row.double("issued").map(Date.init(timeIntervalSince1970:)),
        duration: row.int64("duration").map(Int.init)
      )
    }
  }

  private func count(_ table: String, _ characterID: Int64) throws -> Int {
    Int(
      try database.query(
        "SELECT COUNT(*) AS n FROM \(table) WHERE character_id = ?",
        [.integer(characterID)]
      ).first?.int64("n") ?? 0
    )
  }
}

enum TradeLogbookSQLiteValue: Sendable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)

  static func optional(_ value: Double?) -> Self {
    value.map { .real($0) } ?? .null
  }

  static func optionalText(_ value: String?) -> Self {
    value.map { .text($0) } ?? .null
  }
}

struct TradeLogbookSQLiteRow: Sendable {
  let values: [String: TradeLogbookSQLiteValue]

  func string(_ key: String) -> String? {
    if case .text(let value) = values[key] { return value }
    return nil
  }

  func int64(_ key: String) -> Int64? {
    switch values[key] {
    case .integer(let value): value
    case .real(let value): Int64(exactly: value)
    default: nil
    }
  }

  func double(_ key: String) -> Double? {
    switch values[key] {
    case .real(let value): value
    case .integer(let value): Double(value)
    default: nil
    }
  }
}

final class TradeLogbookSQLiteDatabase: @unchecked Sendable {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    let status = sqlite3_open_v2(
      url.path,
      &handle,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard status == SQLITE_OK else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
      sqlite3_close(handle)
      throw TradeLogbookStoreError.database(message)
    }
    sqlite3_busy_timeout(handle, 5_000)
  }

  deinit { close() }

  func close() {
    guard let handle else { return }
    sqlite3_close_v2(handle)
    self.handle = nil
  }

  func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try body()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func execute(_ sql: String) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
    guard status == SQLITE_OK else {
      let message =
        errorPointer.map { String(cString: $0) }
        ?? handle.map { String(cString: sqlite3_errmsg($0)) } ?? "execute"
      sqlite3_free(errorPointer)
      throw TradeLogbookStoreError.database(message)
    }
  }

  func run(_ sql: String, _ values: [TradeLogbookSQLiteValue] = []) throws {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw databaseError("step")
    }
  }

  func query(
    _ sql: String,
    _ values: [TradeLogbookSQLiteValue] = []
  ) throws -> [TradeLogbookSQLiteRow] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    let columns = (0..<sqlite3_column_count(statement)).compactMap { index in
      sqlite3_column_name(statement, index).map { (index, String(cString: $0)) }
    }
    var rows: [TradeLogbookSQLiteRow] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw databaseError("query") }
      var row: [String: TradeLogbookSQLiteValue] = [:]
      for (index, name) in columns {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
          row[name] = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
          row[name] = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
          if let text = sqlite3_column_text(statement, index) {
            row[name] = .text(String(cString: text))
          }
        default:
          row[name] = .null
        }
      }
      rows.append(TradeLogbookSQLiteRow(values: row))
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
    else { throw databaseError("prepare") }
    return statement
  }

  private func bind(
    _ values: [TradeLogbookSQLiteValue],
    to statement: OpaquePointer?
  ) throws {
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case .null:
        status = sqlite3_bind_null(statement, index)
      case .integer(let value):
        status = sqlite3_bind_int64(statement, index, value)
      case .real(let value):
        status = sqlite3_bind_double(statement, index, value)
      case .text(let value):
        status = sqlite3_bind_text(
          statement,
          index,
          value,
          -1,
          unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
      }
      guard status == SQLITE_OK else { throw databaseError("bind") }
    }
  }

  private func databaseError(_ operation: String) -> TradeLogbookStoreError {
    .database(
      handle.map { "\(operation): \(String(cString: sqlite3_errmsg($0)))" }
        ?? operation
    )
  }
}
