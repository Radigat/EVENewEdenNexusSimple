import Foundation
import Testing

@testable import EVENexusCore

@Suite("Production sale detection")
struct ProductionSaleDetectorTests {
  private let rhea: Int64 = 28844
  private let ark: Int64 = 28850
  private let owner: Int64 = 91
  private let alt: Int64 = 92

  private func day(_ offset: Double) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + offset * 86_400)
  }

  private func row(
    _ number: Int, type: Int64, units: Int64 = 1, day offset: Double = 0,
    id: UUID = UUID()
  ) -> ProductionSaleRow {
    ProductionSaleRow(
      id: id, sequenceNumber: number, recordedAt: day(offset), typeID: type, units: units)
  }

  private func sale(
    _ id: Int64, type: Int64, quantity: Int64 = 1, price: Double = 100, day offset: Double = 1
  ) -> TradeWalletTransaction {
    TradeWalletTransaction(
      characterID: owner, transactionID: id, date: day(offset), typeID: type,
      quantity: quantity, unitPrice: price, isBuy: false, clientID: 1, locationID: 1,
      journalRefID: nil, isPersonal: true)
  }

  private func journal(
    _ id: Int64, refType: String, amount: Double, contract: Int64? = nil,
    sender: Int64? = nil, description: String? = nil, day offset: Double = 2
  ) -> TradeWalletJournalEntry {
    TradeWalletJournalEntry(
      characterID: owner, journalID: id, date: day(offset), refType: refType,
      amount: amount, contextID: contract,
      contextIDType: contract == nil ? nil : "contract_id", tax: nil,
      description: description, firstPartyID: sender, secondPartyID: owner)
  }

  private func item(
    contract: Int64, record: Int64 = 1, type: Int64, quantity: Int64 = 1,
    included: Bool = true
  ) -> TradeWalletContractItem {
    TradeWalletContractItem(
      characterID: owner, contractID: contract, recordID: record, typeID: type,
      quantity: quantity, isIncluded: included)
  }

  private func detect(
    rows: [ProductionSaleRow],
    workspace: ConsolidationWorkspace = ConsolidationWorkspace(),
    transactions: [TradeWalletTransaction] = [],
    journal: [TradeWalletJournalEntry] = [],
    items: [TradeWalletContractItem] = [],
    tradeAssigned: [TradeWalletLink: Int64] = [:]
  ) -> [DetectedProductionSale] {
    ProductionSaleDetector.detect(
      ProductionSaleDetector.Input(
        rows: rows, workspace: workspace, transactions: transactions, journal: journal,
        contractItems: items, tradeAssigned: tradeAssigned,
        ownCharacters: [owner: "Owner", alt: "Alt Pilot"]))
  }

  @Test func contractWithOneItemTypeIsSuggestedForItsProduction() throws {
    let production = row(2, type: rhea)
    let result = detect(
      rows: [row(1, type: ark), production],
      journal: [journal(7, refType: "contract_price", amount: 6_200_000_000, contract: 55)],
      items: [item(contract: 55, type: rhea)])
    let sale = try #require(result.first)
    #expect(result.count == 1)
    #expect(sale.id == "91:journal:7")
    #expect(sale.source == .contract && sale.issue == nil)
    #expect(sale.typeID == rhea && sale.quantity == 1 && sale.remainingQuantity == 1)
    #expect(sale.suggestedRowID == production.id && sale.suggestedQuantity == 1)
    let receipt = try sale.evidence()
    #expect(receipt.totalCents == 620_000_000_000 && receipt.unitPrice == nil)
    #expect(receipt.typeID == rhea && receipt.quantity == 1)
  }

  @Test func contractWithoutUsableContentNamesNoItem() throws {
    let rows = [row(1, type: ark), row(2, type: rhea)]
    let result = detect(
      rows: rows,
      journal: [
        journal(1, refType: "contract_price", amount: 10, contract: 1),
        journal(2, refType: "contract_price", amount: 20, contract: 2),
        journal(3, refType: "contract_price", amount: 30, contract: 3),
      ],
      items: [
        item(contract: 2, record: 1, type: rhea), item(contract: 2, record: 2, type: ark),
        item(contract: 3, record: 1, type: rhea),
        item(contract: 3, record: 2, type: 34, included: false),
      ])
    #expect(
      result.map(\.issue) == [
        .contractItemsUnavailable, .contractHasSeveralItems, .contractHasSeveralItems,
      ])
    #expect(result.allSatisfy { $0.typeID == nil && $0.suggestedRowID == nil })
    // Every production with free units is a candidate, oldest first.
    #expect(result[0].candidateRowIDs == rows.map(\.id))
    // The chosen production supplies type and quantity; nothing is guessed.
    #expect(throws: (any Error).self) { try result[0].evidence() }
    let receipt = try result[0].evidence(typeID: ark, quantity: 1)
    #expect(receipt.typeID == ark && receipt.totalCents == 1_000)
  }

  @Test func transfersFromOwnCharactersAreLeftOut() {
    let result = detect(
      rows: [row(1, type: rhea)],
      journal: [
        journal(1, refType: "player_donation", amount: 5, sender: alt),
        journal(2, refType: "player_donation", amount: 6, sender: 777),
        journal(
          3, refType: "player_donation", amount: 7,
          description: "Alt Pilot deposited cash into Owner's account"),
        journal(
          4, refType: "player_donation", amount: 8,
          description: "Stranger deposited cash into Owner's account"),
        journal(5, refType: "player_donation", amount: 9),
        journal(6, refType: "bounty_prizes", amount: 10),
        journal(7, refType: "player_donation", amount: -11, sender: 777),
      ])
    #expect(result.map(\.referenceID) == [2, 4, 5])
    #expect(result.allSatisfy { $0.source == .transfer && $0.issue == .transferHasNoItem })
    #expect(result.map(\.senderKnown) == [true, true, false])
  }

  @Test func marketSalesFollowFirstInFirstOutAndSkipUsedUnits() throws {
    let old = row(1, type: rhea, units: 2, day: 0)
    let new = row(2, type: rhea, units: 5, day: 1)
    let linked = TradeWalletLink(characterID: owner, transactionID: 3)
    let result = detect(
      rows: [new, old],
      transactions: [
        sale(1, type: rhea, quantity: 3, day: 2),
        sale(2, type: rhea, quantity: 1, day: 3),
        sale(3, type: rhea, quantity: 4, day: 4),
        sale(4, type: rhea, quantity: 2, day: 5),
        sale(5, type: 999, quantity: 1, day: 6),
        TradeWalletTransaction(
          characterID: owner, transactionID: 6, date: day(7), typeID: rhea, quantity: 1,
          unitPrice: 1, isBuy: true, clientID: 1, locationID: nil, journalRefID: nil,
          isPersonal: nil),
      ],
      tradeAssigned: [linked: 4])
    // The fully trade-assigned sale, the unknown type and the purchase are gone.
    #expect(result.map(\.referenceID) == [1, 2, 4])
    // Oldest production first; a sale never exceeds the free units of its row.
    #expect(result.map(\.suggestedRowID) == [old.id, new.id, new.id])
    #expect(result.map(\.suggestedQuantity) == [2, 1, 2])
    #expect(result[0].candidateRowIDs == [old.id, new.id])
    let receipt = try result[0].evidence()
    #expect(receipt.id == "91:transaction:1" && receipt.quantity == 3)
    #expect(receipt.unitPrice?.hundredths == 10_000)
  }

  @Test func assignedUnitsAndStoredReceiptsAreRespected() throws {
    let production = row(1, type: rhea, units: 3)
    var workspace = ConsolidationWorkspace()
    workspace.costs = [
      ImmutableProductionCost(
        id: production.id, typeID: rhea, units: 3, sourceSnapshot: Data(), material: nil,
        installation: nil, blueprint: nil, logistics: nil, historicalManualSoldUnits: 0,
        historicalManualSalePrice: nil, recordedAt: day(0))
    ]
    let transactions = [sale(1, type: rhea, quantity: 2, price: 50)]
    let first = try #require(detect(rows: [production], transactions: transactions).first)
    try workspace.addEvidence(first.evidence())
    try workspace.allocateSale(
      rowID: production.id, evidenceID: first.id, quantity: 1, switchToEvidence: true)
    // A manual receipt and a confirmed transfer stay assignable.
    try workspace.addEvidence(
      ProductionSaleEvidence(
        id: "manual:1", typeID: rhea, quantity: 1, unitPrice: try ISKAmount.parse("9"),
        recordedAt: day(3), source: "Manueller Beleg"))
    try workspace.addEvidence(
      ProductionSaleEvidence(
        id: "91:journal:8", typeID: rhea, quantity: 2, unitPrice: nil, recordedAt: day(2),
        source: "Überweisung · 8", totalCents: 700))

    let result = detect(
      rows: [production], workspace: workspace, transactions: transactions,
      journal: [journal(8, refType: "player_donation", amount: 7, sender: 777)])
    #expect(result.map(\.id) == ["91:transaction:1", "91:journal:8", "manual:1"])
    #expect(result.map(\.remainingQuantity) == [1, 2, 1])
    #expect(result.map(\.source) == [.market, .transfer, .manual])
    // Two units are free; the third sale finds no free production any more.
    #expect(result.map(\.suggestedQuantity) == [1, 1, 0])
    #expect(result[2].suggestedRowID == nil)
    // The confirmed transfer keeps its stored type and is reused unchanged.
    #expect(result[1].issue == nil && result[1].typeID == rhea)
    #expect(try result[1].evidence().totalCents == 700)
    #expect(
      ProductionSaleDetector.walletSaleQuantities(in: workspace)
        == [TradeWalletLink(characterID: owner, transactionID: 1): 1])

    // With every unit covered by receipts nothing of the type is offered.
    try workspace.allocateSale(
      rowID: production.id, evidenceID: "91:journal:8", quantity: 2, switchToEvidence: true)
    #expect(detect(rows: [production], workspace: workspace, transactions: transactions).isEmpty)
  }
}
