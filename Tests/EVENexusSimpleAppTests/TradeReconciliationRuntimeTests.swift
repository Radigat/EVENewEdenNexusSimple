@testable import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

/// G8 (ANALYSE_2026-11-02): the wallet matching runs off the main thread.
/// The runtime path from stored wallet data to logbook entries must give the
/// same result as before; the normalized result is a golden master that the
/// unchanged code produced as well.
@MainActor
@Suite("Trade reconciliation in the runtime", .serialized)
struct TradeReconciliationRuntimeTests {
  @Test
  func storedWalletDataBecomesTheSameLogbookEntries() async throws {
    let fixture = try await GoldenPlannerFixture.make()
    defer { fixture.remove() }
    let runtime = fixture.runtime
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let transactions = try Self.decode(
      [ESIWalletTransactionDTO].self,
      """
      [
        {"client_id": 1, "date": "2026-10-01T10:00:00Z", "is_buy": true,
         "quantity": 10000, "transaction_id": 501, "type_id": 34,
         "unit_price": 4.0, "location_id": 60003760, "journal_ref_id": 9501,
         "is_personal": true},
        {"client_id": 2, "date": "2026-10-03T12:00:00Z", "is_buy": false,
         "quantity": 4000, "transaction_id": 502, "type_id": 34,
         "unit_price": 5.5, "location_id": 60008494, "journal_ref_id": 9502,
         "is_personal": true},
        {"client_id": 3, "date": "2026-10-02T09:00:00Z", "is_buy": true,
         "quantity": 2, "transaction_id": 503, "type_id": 1004,
         "unit_price": 70000, "location_id": 60003760, "journal_ref_id": 9503,
         "is_personal": true}
      ]
      """
    )
    let journal = try Self.decode(
      [ESIWalletJournalDTO].self,
      """
      [
        {"id": 9601, "date": "2026-10-03T12:00:00Z", "ref_type": "transaction_tax",
         "amount": -990, "context_id": 502,
         "context_id_type": "market_transaction_id"}
      ]
      """
    )
    await runtime.setTradeWalletImportStart(
      try #require(ISO8601DateFormatter().date(from: "2026-09-30T00:00:00Z"))
    )
    await runtime.recordTradeWallet(
      characterID: 91,
      characterName: "Golden Trader",
      transactions: Sourced(state: .fresh, value: transactions, source: source),
      journal: Sourced(state: .fresh, value: journal, source: source)
    )
    #expect(runtime.tradeWalletError == nil)

    await runtime.reconcileTradeLogbook(manufacturingTypeIDs: [GoldenType.module])

    #expect(runtime.tradeWalletError == nil)
    #expect(!runtime.isReconcilingTradeLogbook)
    let entries = runtime.tradeLogbookEntries.sorted {
      ($0.walletLink?.transactionID ?? 0) < ($1.walletLink?.transactionID ?? 0)
    }
    #expect(entries.compactMap(\.walletLink?.transactionID) == [501, 503])
    try GoldenMaster.verify(
      ReconciliationOutcome(
        entries: entries,
        unassignedSales: runtime.tradeUnassignedSales,
        unresolvedTypePurchases: runtime.tradeUnresolvedPurchaseCount
      ),
      named: "trade-reconciliation"
    )
  }

  private struct ReconciliationOutcome {
    let entries: [TradeLogbookEntry]
    let unassignedSales: [TradeUnassignedSale]
    let unresolvedTypePurchases: Int
  }

  private static func decode<Value: Decodable>(
    _ type: Value.Type,
    _ json: String
  ) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(json.utf8))
  }
}
