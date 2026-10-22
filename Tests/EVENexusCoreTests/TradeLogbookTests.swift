import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Trade logbook")
struct TradeLogbookTests {
  private func entry(
    quantity: Int64 = 100,
    buySide: TradeQuoteSide = .maxBuy,
    transport: Double? = 10_000,
    tax: Double? = 0.036,
    broker: Double? = 0.015,
    status: TradeLogbookStatus = .bought,
    target: OpportunityHubRole = .home,
    sales: [TradeLogbookSale] = []
  ) -> TradeLogbookEntry {
    // Whole seconds: dates are stored as seconds since 1970.
    TradeLogbookEntry(
      createdAt: Date(timeIntervalSince1970: 1_800_000_100),
      updatedAt: Date(timeIntervalSince1970: 1_800_000_200),
      purchasedAt: Date(timeIntervalSince1970: 1_800_000_000),
      typeID: 482,
      typeName: "Miner II",
      quantity: quantity,
      buyUnitPrice: 500_000,
      buySide: buySide,
      buyBrokerFeeRate: 0.01,
      sourceRole: .main,
      sourceLocationName: "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
      targetRole: target,
      targetLocationName: "Home",
      plannedSellUnitPrice: 690_000,
      transportCostTotal: transport,
      salesTaxRate: tax,
      sellBrokerFeeRate: broker,
      status: status,
      notes: "Fixture",
      sales: sales
    )
  }

  private func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("trade-logbook-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("trade", isDirectory: true)
      .appendingPathComponent("trade-logbook.sqlite")
  }

  @Test
  func entriesRoundTripAndUnknownValuesStayUnknown() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let sale = TradeLogbookSale(
      soldAt: Date(timeIntervalSince1970: 1_800_100_000),
      quantity: 40,
      unitPrice: 680_000,
      kind: .listedSellOrder
    )
    var stored = entry(sales: [sale])
    stored.plannedSellUnitPrice = nil
    var unknownTransport = entry(transport: nil)
    unknownTransport.purchasedAt = Date(timeIntervalSince1970: 1_700_000_000)

    let store = try await TradeLogbookStore.open(url: url)
    try await store.save(stored)
    try await store.save(unknownTransport)
    await store.close()

    // Reopening runs the migration again without touching the data.
    let reopened = try await TradeLogbookStore.open(url: url)
    let loaded = try await reopened.entries()
    #expect(loaded.count == 2)
    #expect(loaded.first == stored)
    #expect(loaded.first?.plannedSellUnitPrice == nil)
    #expect(loaded.last?.transportCostTotal == nil)
    #expect(loaded.last?.costPerUnit == nil)
    #expect(loaded.first?.sales == [sale])
    await reopened.close()
  }

  @Test
  func saveReplacesSalesAndDeleteRemovesThem() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let store = try await TradeLogbookStore.open(url: url)
    var value = entry(
      sales: [
        TradeLogbookSale(soldAt: .now, quantity: 10, unitPrice: 1, kind: .directToBuyOrder)
      ]
    )
    try await store.save(value)
    value.sales = []
    value.status = .listed
    try await store.save(value)
    #expect(try await store.entries().first?.sales.isEmpty == true)
    #expect(try await store.entries().first?.status == .listed)

    value.sales = [
      TradeLogbookSale(soldAt: .now, quantity: 5, unitPrice: 2, kind: .listedSellOrder)
    ]
    try await store.save(value)
    try await store.delete(entryID: value.id)
    #expect(try await store.entries().isEmpty)
    await store.close()
  }

  @Test
  func invalidEntriesAreRejectedBeforeWriting() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let store = try await TradeLogbookStore.open(url: url)
    await #expect(throws: TradeLogbookValidationError.soldMoreThanBought) {
      try await store.save(
        entry(
          quantity: 5,
          sales: [
            TradeLogbookSale(soldAt: .now, quantity: 6, unitPrice: 1, kind: .listedSellOrder)
          ]
        )
      )
    }
    await #expect(throws: TradeLogbookValidationError.invalidField("quantity")) {
      try await store.save(entry(quantity: 0))
    }
    await #expect(throws: TradeLogbookValidationError.invalidField("salesTaxRate")) {
      try await store.save(entry(tax: 1.2))
    }
    #expect(try await store.entries().isEmpty)
    await store.close()
  }

  @Test
  func aNewerSchemaVersionIsNotOpenedOrChanged() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "PRAGMA user_version = 7", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    await #expect(throws: TradeLogbookStoreError.unsupportedSchemaVersion(7)) {
      _ = try await TradeLogbookStore.open(url: url)
    }
  }

  @Test
  func profitsUseFrozenRatesAndOnlyTheSoldUnits() throws {
    let listed = entry(
      sales: [
        TradeLogbookSale(soldAt: .now, quantity: 40, unitPrice: 680_000, kind: .listedSellOrder),
        TradeLogbookSale(soldAt: .now, quantity: 10, unitPrice: 600_000, kind: .directToBuyOrder),
      ]
    )
    // 500,000 × 1.01 purchase + 10,000 ÷ 100 transport per unit.
    let cost = 500_000 * 1.01 + 100
    #expect(listed.costPerUnit == cost)
    #expect(listed.soldQuantity == 50)
    #expect(listed.openQuantity == 50)
    let listedRevenue: Double = 40 * 680_000 * (1 - 0.036 - 0.015)
    let directRevenue: Double = 10 * 600_000 * (1 - 0.036)
    let revenue = listedRevenue + directRevenue
    let profit = try #require(listed.realizedProfit)
    #expect(abs(profit - (revenue - 50 * cost)) < 1e-6)
    let planned = try #require(listed.plannedProfit)
    #expect(abs(planned - (690_000 * 0.949 - cost) * 100) < 1e-6)

    // Instant purchases carry no broker fee.
    #expect(entry(buySide: .minSell).purchaseCostPerUnit == 500_000)
    // A missing rate keeps the result unknown instead of zero.
    #expect(entry(broker: nil, sales: listed.sales).realizedProfit == nil)
    #expect(entry().realizedProfit == nil)
    // Closed statuses do not count as open quantity.
    #expect(entry(status: .manufacturingIgnored).openQuantity == 0)
    #expect(entry(status: .sold).openQuantity == 0)
  }

  @Test
  func reminderComparesThePlanWithTheCurrentTargetPrice() {
    let value = entry()
    #expect(value.reminder(currentBestSell: 700_000) == .reached(currentBestSell: 700_000))
    #expect(value.reminder(currentBestSell: 690_000) == .reached(currentBestSell: 690_000))
    #expect(value.reminder(currentBestSell: 650_000) == .below(currentBestSell: 650_000))
    #expect(value.reminder(currentBestSell: nil) == .marketUnknown)
    var noPlan = value
    noPlan.plannedSellUnitPrice = nil
    #expect(noPlan.reminder(currentBestSell: 700_000) == .noPlannedPrice)
  }

  @Test
  func openQuantitiesAreSummedPerTypeForOneTargetHub() {
    let entries = [
      entry(quantity: 100),
      entry(
        quantity: 20,
        sales: [TradeLogbookSale(soldAt: .now, quantity: 5, unitPrice: 1, kind: .listedSellOrder)]
      ),
      entry(quantity: 7, target: .coalition),
      entry(quantity: 9, status: .excluded),
    ]
    #expect(TradeLogbookSummary.openQuantities(entries, targetRole: .home) == [482: 115])
    #expect(TradeLogbookSummary.openQuantities(entries, targetRole: .coalition) == [482: 7])
    #expect(TradeLogbookStatus.bought.sortRank < TradeLogbookStatus.excluded.sortRank)
  }

  @Test
  func sortingUsesTypedValuesAndKeepsUnknownCostsLast() {
    var cheap = entry(quantity: 10)
    cheap.buyUnitPrice = 1
    var unknownCost = entry(quantity: 20, transport: nil)
    unknownCost.buyUnitPrice = 2
    let expensive = entry(quantity: 30)
    let entries = [unknownCost, expensive, cheap]

    #expect(
      TradeLogbookSorter.sorted(entries, by: .costPerUnit, ascending: true)
        .map(\.quantity) == [10, 30, 20]
    )
    #expect(
      TradeLogbookSorter.sorted(entries, by: .costPerUnit, ascending: false)
        .map(\.quantity) == [20, 30, 10]
    )
    #expect(
      TradeLogbookSorter.sorted(entries, by: .quantity, ascending: true)
        .map(\.quantity) == [10, 20, 30]
    )
    let prices = [expensive.id: 700_000.0]
    #expect(
      TradeLogbookSorter.sorted(
        entries, by: .currentBestSell, ascending: true, currentBestSell: prices
      ).first?.id == expensive.id
    )
  }

  private func transaction(
    _ id: Int64,
    isBuy: Bool = true,
    quantity: Int64 = 10,
    price: Double = 100,
    location: Int64? = 60_003_760
  ) -> ESIWalletTransactionDTO {
    ESIWalletTransactionDTO(
      clientID: 9_000,
      date: Date(timeIntervalSince1970: 1_800_000_000 + Double(id)),
      isBuy: isBuy,
      quantity: quantity,
      transactionID: id,
      typeID: 482,
      unitPrice: price,
      locationID: location,
      journalRefID: location == nil ? nil : 50_000 + id,
      isPersonal: location == nil ? nil : true
    )
  }

  private func sourced<Value>(
    _ value: Value?,
    _ state: DataFreshness = .fresh,
    diagnostics: [String] = []
  ) -> Sourced<Value> {
    Sourced(
      state: state,
      value: value,
      source: SourceIdentity(provider: "fixture", version: "1"),
      diagnostics: diagnostics
    )
  }

  @Test
  func walletHandOversAreIdempotentAndKeepOlderRows() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let store = try await TradeLogbookStore.open(url: url)
    let journal = [
      ESIWalletJournalDTO(
        amount: -36,
        contextID: 2,
        contextIDType: "market_transaction_id",
        date: Date(timeIntervalSince1970: 1_800_000_002),
        journalID: 77,
        refType: "transaction_tax",
        tax: nil
      )
    ]
    let first = try await store.recordWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: sourced([transaction(1), transaction(2, isBuy: false)]),
      journal: sourced(journal),
      at: Date(timeIntervalSince1970: 1_800_001_000)
    )
    #expect(first == TradeWalletRecordResult(
      newTransactions: 2, newJournalEntries: 1, skippedInvalidTransactions: 0
    ))

    // The next ESI window no longer contains transaction 1; it stays stored.
    let second = try await store.recordWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: sourced([
        transaction(2, isBuy: false),
        transaction(3),
        transaction(4, quantity: 0),
      ]),
      journal: sourced(journal),
      at: Date(timeIntervalSince1970: 1_800_002_000)
    )
    #expect(second == TradeWalletRecordResult(
      newTransactions: 1, newJournalEntries: 0, skippedInvalidTransactions: 1
    ))
    let stored = try await store.walletTransactions(characterID: 91)
    #expect(stored.map(\.transactionID) == [1, 2, 3])
    #expect(stored.first?.locationID == 60_003_760)
    #expect(stored.first?.isPersonal == true)
    #expect(try await store.walletJournal(characterID: 91).first?.refType == "transaction_tax")

    let status = try #require(try await store.walletSyncStatuses().first)
    #expect(status.characterName == "Trader")
    #expect(status.storedTransactionCount == 3)
    #expect(status.storedJournalCount == 1)
    #expect(status.transactionsSyncedAt == Date(timeIntervalSince1970: 1_800_002_000))
    await store.close()
  }

  @Test
  func missingScopeIsRecordedWithoutLosingTheLastSuccess() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let store = try await TradeLogbookStore.open(url: url)
    try await store.recordWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: sourced([transaction(1, location: nil)]),
      journal: sourced([]),
      at: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try await store.recordWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: sourced(nil, .forbidden, diagnostics: ["esi.missing-scope"]),
      journal: sourced(nil, .forbidden),
      at: Date(timeIntervalSince1970: 1_800_009_000)
    )

    let status = try #require(try await store.walletSyncStatuses().first)
    #expect(status.transactionsState == .forbidden)
    #expect(status.attemptedAt == Date(timeIntervalSince1970: 1_800_009_000))
    #expect(status.transactionsSyncedAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(status.diagnostics == ["esi.missing-scope"])
    #expect(status.storedTransactionCount == 1)
    // Fields an old snapshot lacked stay unknown.
    let stored = try #require(try await store.walletTransactions().first)
    #expect(stored.locationID == nil)
    #expect(stored.journalRefID == nil)
    #expect(stored.isPersonal == nil)
    await store.close()
  }

  @Test
  func aVersionOneLogbookIsMigratedWithoutLosingEntries() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // The exact schema written by P5 (version 1) with one purchase.
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    #expect(
      sqlite3_exec(
        database,
        """
        CREATE TABLE trade_purchases (
          id TEXT PRIMARY KEY, created_at REAL NOT NULL, updated_at REAL NOT NULL,
          purchased_at REAL NOT NULL, type_id INTEGER NOT NULL,
          type_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK (quantity > 0),
          buy_unit_price REAL NOT NULL, buy_side TEXT NOT NULL,
          buy_broker_fee_rate REAL, source_role TEXT NOT NULL,
          source_location_name TEXT, target_role TEXT NOT NULL,
          target_location_name TEXT, planned_sell_unit_price REAL,
          transport_cost_total REAL, sales_tax_rate REAL,
          sell_broker_fee_rate REAL, status TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE trade_sales (
          id TEXT PRIMARY KEY,
          purchase_id TEXT NOT NULL REFERENCES trade_purchases(id) ON DELETE CASCADE,
          sold_at REAL NOT NULL, quantity INTEGER NOT NULL CHECK (quantity > 0),
          unit_price REAL NOT NULL, kind TEXT NOT NULL
        );
        INSERT INTO trade_purchases VALUES (
          '00000000-0000-0000-0000-000000000001', 1, 2, 3, 482, 'Miner II', 4,
          500, 'minSell', NULL, 'main', NULL, 'home', NULL, 600, 10, 0.036,
          0.015, 'bought', ''
        );
        INSERT INTO trade_sales VALUES (
          '00000000-0000-0000-0000-000000000002',
          '00000000-0000-0000-0000-000000000001', 4, 1, 650, 'listedSellOrder'
        );
        PRAGMA user_version = 1;
        """,
        nil, nil, nil
      ) == SQLITE_OK
    )
    sqlite3_close(database)

    let migrated = try await TradeLogbookStore.open(url: url)
    let loaded = try await migrated.entries()
    #expect(loaded.count == 1)
    #expect(loaded.first?.buySideSource == .manual)
    #expect(loaded.first?.walletLink == nil)
    #expect(loaded.first?.transportEstimated == false)
    #expect(loaded.first?.sales.first?.kindSource == .manual)
    #expect(loaded.first?.sales.first?.salesTaxPaid == nil)
    #expect(try await migrated.walletSyncStatuses().isEmpty)
    try await migrated.recordWallet(
      characterID: 1,
      characterName: "A",
      transactions: sourced([transaction(1)]),
      journal: sourced([])
    )
    #expect(try await migrated.walletTransactions().count == 1)
    await migrated.close()
  }

  @Test
  func walletLinksOrdersAndSettingsArePersisted() async throws {
    let url = temporaryStoreURL()
    defer {
      try? FileManager.default.removeItem(
        at: url.deletingLastPathComponent().deletingLastPathComponent()
      )
    }
    let store = try await TradeLogbookStore.open(url: url)
    var linked = entry(
      sales: [
        TradeLogbookSale(
          soldAt: Date(timeIntervalSince1970: 1_800_100_000),
          quantity: 2,
          unitPrice: 700_000,
          kind: .directToBuyOrder,
          kindSource: .detected,
          salesTaxPaid: 50_400,
          walletLink: TradeWalletLink(characterID: 91, transactionID: 9)
        )
      ]
    )
    linked.walletLink = TradeWalletLink(characterID: 91, transactionID: 8)
    linked.buySideSource = .assumed
    linked.transportEstimated = true
    try await store.save([linked, entry(quantity: 3)])
    #expect(try await store.entries().first { $0.id == linked.id } == linked)

    // A second purchase entry for the same wallet transaction is refused.
    var duplicate = entry(quantity: 1)
    duplicate.walletLink = linked.walletLink
    await #expect(throws: TradeLogbookStoreError.self) {
      try await store.save(duplicate)
    }

    try await store.setSetting("wallet-import-start", value: "1800000000")
    #expect(try await store.setting("wallet-import-start") == "1800000000")
    try await store.setSetting("wallet-import-start", value: nil)
    #expect(try await store.setting("wallet-import-start") == nil)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let order = try decoder.decode(
      ESICharacterOrderDTO.self,
      from: Data(
        #"{"duration":90,"is_buy_order":true,"issued":"2026-10-22T10:00:00Z","location_id":60003760,"order_id":5,"price":99.5,"type_id":482,"volume_remain":3}"#
          .utf8
      )
    )
    try await store.recordWallet(
      characterID: 91,
      characterName: "Trader",
      transactions: sourced([]),
      journal: sourced([]),
      orders: [sourced([order]), sourced([])],
      at: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let stored = try #require(try await store.walletOrders().first)
    #expect(stored.isBuy)
    #expect(stored.duration == 90)
    #expect(stored.issued != nil)
    #expect(
      try await store.walletSyncStatuses().first?.ordersSyncedAt
        == Date(timeIntervalSince1970: 1_800_000_000)
    )
    await store.close()
  }

  @Test
  func walletTransactionsDecodeTheP6FieldsAndOldSnapshots() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let current = try decoder.decode(
      ESIWalletTransactionDTO.self,
      from: Data(
        #"{"client_id":1,"date":"2026-10-22T10:00:00Z","is_buy":true,"is_personal":true,"journal_ref_id":5,"location_id":60003760,"quantity":2,"transaction_id":3,"type_id":34,"unit_price":4.5}"#
          .utf8
      )
    )
    #expect(current.locationID == 60_003_760)
    #expect(current.journalRefID == 5)
    #expect(current.isPersonal == true)
    let legacy = try decoder.decode(
      ESIWalletTransactionDTO.self,
      from: Data(
        #"{"client_id":1,"date":"2026-10-22T10:00:00Z","is_buy":true,"quantity":2,"transaction_id":3,"type_id":34,"unit_price":4.5}"#
          .utf8
      )
    )
    #expect(legacy.locationID == nil)
    #expect(legacy.isPersonal == nil)
  }
}

@Suite("Trade wallet reconciliation")
struct TradeWalletReconcilerTests {
  private let jita: Int64 = 60_003_760
  private let home: Int64 = 1_000
  private let coalition: Int64 = 2_000
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func day(_ offset: Double) -> Date {
    start.addingTimeInterval(offset * 86_400)
  }

  private func transaction(
    _ id: Int64,
    character: Int64 = 91,
    type: Int64 = 482,
    isBuy: Bool,
    quantity: Int64,
    price: Double = 100,
    location: Int64?,
    date: Date
  ) -> TradeWalletTransaction {
    TradeWalletTransaction(
      characterID: character,
      transactionID: id,
      date: date,
      typeID: type,
      quantity: quantity,
      unitPrice: price,
      isBuy: isBuy,
      clientID: 1,
      locationID: location,
      journalRefID: nil,
      isPersonal: true
    )
  }

  private var context: TradeReconciliationContext {
    TradeReconciliationContext(
      startDate: start,
      hubLocations: [.main: jita, .home: home, .coalition: coalition],
      hubNames: [.main: "Jita", .home: "Home", .coalition: "Coalition"],
      fees: [
        .main: TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.01),
        .home: TradeHubFees(salesTaxRate: 0.036, brokerFeeRate: 0.015),
        .coalition: TradeHubFees(salesTaxRate: 0.04, brokerFeeRate: 0.02),
      ],
      manufacturingTypeIDs: [483],
      transportBases: [
        .home: TradeTransportBasis(
          legs: [.courier(TradeCourierLeg(origin: "Jita", destination: "Home", iskPerCubicMeter: 1_000))]
        )
      ],
      packagedVolumes: [482: 10, 483: 1],
      typeNames: [482: "Miner II", 483: "Tritanium"],
      charactersWithOrders: [91],
      now: day(10)
    )
  }

  private var orders: [TradeWalletOrder] {
    [
      TradeWalletOrder(
        characterID: 91, orderID: 1, typeID: 482, locationID: jita, isBuy: true,
        price: 100, issued: day(0), duration: 90
      ),
      TradeWalletOrder(
        characterID: 91, orderID: 2, typeID: 482, locationID: home, isBuy: false,
        price: 150, issued: day(2), duration: 90
      ),
    ]
  }

  private var transactions: [TradeWalletTransaction] {
    [
      transaction(1, isBuy: true, quantity: 10, location: jita, date: day(1)),
      transaction(2, character: 92, type: 483, isBuy: true, quantity: 1_000, price: 4, location: jita, date: day(1)),
      transaction(3, isBuy: true, quantity: 7, location: jita, date: day(-1)),
      transaction(4, isBuy: true, quantity: 7, location: 5_555, date: day(1)),
      transaction(5, isBuy: true, quantity: 5, location: home, date: day(2)),
      transaction(6, isBuy: false, quantity: 12, price: 150, location: home, date: day(3)),
      transaction(7, isBuy: false, quantity: 3, price: 160, location: coalition, date: day(4)),
      transaction(8, type: 999, isBuy: false, quantity: 1, location: home, date: day(4)),
      transaction(9, type: 777, isBuy: true, quantity: 1, location: jita, date: day(1)),
    ]
  }

  private var journal: [TradeWalletJournalEntry] {
    [
      TradeWalletJournalEntry(
        characterID: 91, journalID: 1, date: day(3), refType: "transaction_tax",
        amount: -54, contextID: 6, contextIDType: "market_transaction_id",
        tax: nil, description: nil
      )
    ]
  }

  @Test
  func purchasesBecomeEntriesWithDetectedOrAssumedOrderType() throws {
    let result = TradeWalletReconciler.reconcile(
      entries: [], transactions: transactions, journal: journal,
      orders: orders, context: context
    )
    let entries = result.changedEntries
    // Before the start date, outside the hubs and unnamed types are skipped.
    #expect(Set(entries.compactMap(\.walletLink?.transactionID)) == [1, 2, 5])
    #expect(result.unresolvedTypePurchases == 1)

    let imported = try #require(entries.first { $0.walletLink?.transactionID == 1 })
    #expect(imported.sourceRole == .main)
    #expect(imported.targetRole == .home)
    #expect(imported.buySide == .maxBuy)
    #expect(imported.buySideSource == .detected)
    #expect(imported.buyBrokerFeeRate == 0.01)
    #expect(imported.transportEstimated)
    // 100 m³ × 1,000 ISK = 100,000 → one contract rounded to 1,000,000.
    #expect(imported.transportCostTotal == 1_000_000)
    #expect(imported.salesTaxRate == 0.036)
    #expect(imported.sellBrokerFeeRate == 0.015)

    let material = try #require(entries.first { $0.walletLink?.transactionID == 2 })
    #expect(material.status == .manufacturingIgnored)
    #expect(material.buySide == .minSell)
    #expect(material.buySideSource == .assumed)

    let station = try #require(entries.first { $0.walletLink?.transactionID == 5 })
    #expect(station.sourceRole == .home)
    #expect(station.targetRole == .home)
    #expect(station.transportCostTotal == 0)
    #expect(!station.transportEstimated)
  }

  @Test
  func salesAreAssignedFirstInFirstOutPerItemAndTargetHub() throws {
    let result = TradeWalletReconciler.reconcile(
      entries: [], transactions: transactions, journal: journal,
      orders: orders, context: context
    )
    let imported = try #require(result.changedEntries.first { $0.walletLink?.transactionID == 1 })
    let station = try #require(result.changedEntries.first { $0.walletLink?.transactionID == 5 })
    #expect(imported.soldQuantity == 10)
    #expect(imported.status == .sold)
    #expect(station.soldQuantity == 2)
    #expect(station.status == .bought)

    let sale = try #require(imported.sales.first)
    #expect(sale.kind == .listedSellOrder)
    #expect(sale.kindSource == .detected)
    // 54 ISK tax for 12 units → 45 ISK for the 10 assigned units.
    #expect(sale.salesTaxPaid == 45)
    #expect(station.sales.first?.salesTaxPaid == 9)
    let profit = try #require(imported.realizedProfit)
    let revenue = 1_500.0 - 45 - 1_500 * 0.015
    let cost = 10 * (100 * 1.01 + 100_000)
    #expect(abs(profit - (revenue - cost)) < 1e-6)

    // The Coalition sale finds no purchase for that hub; the unknown item's
    // sale is not listed.
    #expect(result.unassignedSales.map(\.link.transactionID) == [7])
    #expect(result.unassignedSales.first?.hubRoles == [.coalition])
    #expect(result.unassignedSales.first?.remainingQuantity == 3)
  }

  @Test
  func aSecondRunAddsNothing() {
    let first = TradeWalletReconciler.reconcile(
      entries: [], transactions: transactions, journal: journal,
      orders: orders, context: context
    )
    let second = TradeWalletReconciler.reconcile(
      entries: first.changedEntries, transactions: transactions, journal: journal,
      orders: orders, context: context
    )
    #expect(second.changedEntries.isEmpty)
    #expect(second.unassignedSales == first.unassignedSales)
  }

  @Test
  func withoutOrderDataSalesAreAssumedOwnSellOrders() throws {
    let unknownOrders = TradeReconciliationContext(
      startDate: start,
      hubLocations: [.main: jita, .home: home],
      fees: [:],
      manufacturingTypeIDs: [],
      transportBases: [:],
      packagedVolumes: [:],
      typeNames: [482: "Miner II"],
      charactersWithOrders: [],
      now: day(10)
    )
    let result = TradeWalletReconciler.reconcile(
      entries: [],
      transactions: [
        transaction(1, isBuy: true, quantity: 2, location: home, date: day(1)),
        transaction(2, isBuy: false, quantity: 1, location: home, date: day(2)),
      ],
      journal: [], orders: [], context: unknownOrders
    )
    let entry = try #require(result.changedEntries.first)
    #expect(entry.buySide == .minSell)
    #expect(entry.buySideSource == .assumed)
    #expect(entry.sales.first?.kind == .listedSellOrder)
    #expect(entry.sales.first?.kindSource == .assumed)
    // Unknown fees keep the profit unknown instead of zero.
    #expect(entry.realizedProfit == nil)
  }

  @Test
  func unassignedSalesCanBeAssignedManually() throws {
    let first = TradeWalletReconciler.reconcile(
      entries: [], transactions: transactions, journal: journal,
      orders: orders, context: context
    )
    let station = try #require(first.changedEntries.first { $0.walletLink?.transactionID == 5 })
    let sale = try #require(first.unassignedSales.first)
    let assigned = try #require(TradeWalletReconciler.assign(sale, to: station, now: day(11)))
    #expect(assigned.soldQuantity == 5)
    #expect(assigned.status == .sold)
    #expect(assigned.sales.last?.walletLink == sale.link)

    let rerun = TradeWalletReconciler.reconcile(
      entries: first.changedEntries.map { $0.id == assigned.id ? assigned : $0 },
      transactions: transactions, journal: journal, orders: orders, context: context
    )
    #expect(rerun.unassignedSales.isEmpty)
    #expect(TradeWalletReconciler.assign(sale, to: assigned) == nil)
  }
}
