import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

/// Owner request of 22.11.2026: several logbook entries get their usage
/// (production, consumption or a sale hub) in one step.
@MainActor
@Suite("Trade logbook bulk usage")
struct TradeLogbookBulkUsageTests {
  private let ids = (0..<5).map { _ in UUID() }

  @Test
  func clickTogglesOneEntryAndShiftClickTheRangeFromTheAnchor() {
    let single = TradeLogbookSelection.toggled(
      ids[1], isOn: true, extendingRange: false, anchor: ids[4],
      orderedIDs: ids, selection: []
    )
    #expect(single == [ids[1]])

    // Upwards and downwards from the anchor, both ends included.
    let down = TradeLogbookSelection.toggled(
      ids[3], isOn: true, extendingRange: true, anchor: ids[1],
      orderedIDs: ids, selection: [ids[1]]
    )
    #expect(down == Set(ids[1...3]))
    let up = TradeLogbookSelection.toggled(
      ids[0], isOn: true, extendingRange: true, anchor: ids[2],
      orderedIDs: ids, selection: [ids[4]]
    )
    #expect(up == Set(ids[0...2]).union([ids[4]]))

    // Shift-click on a selected entry clears the range.
    let cleared = TradeLogbookSelection.toggled(
      ids[3], isOn: false, extendingRange: true, anchor: ids[1],
      orderedIDs: ids, selection: Set(ids)
    )
    #expect(cleared == [ids[0], ids[4]])

    // Without a visible anchor only the clicked entry changes.
    let hiddenAnchor = TradeLogbookSelection.toggled(
      ids[2], isOn: true, extendingRange: true, anchor: UUID(),
      orderedIDs: ids, selection: []
    )
    #expect(hiddenAnchor == [ids[2]])
  }

  @Test
  func runtimeSetsTheUsageOfTheGivenEntriesOnly() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("trade-logbook-bulk-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = RuntimeState(dataRoot: root, startBackgroundServices: false)
    await runtime.loadTradeLogbook()

    func entry(_ typeID: Int64, status: TradeLogbookStatus = .bought) -> TradeLogbookEntry {
      TradeLogbookEntry(
        typeID: typeID,
        typeName: "Fixture \(typeID)",
        quantity: 10,
        buyUnitPrice: 100,
        buySide: .minSell,
        buyBrokerFeeRate: nil,
        sourceRole: .main,
        sourceLocationName: nil,
        targetRole: .home,
        targetLocationName: nil,
        plannedSellUnitPrice: nil,
        transportCostTotal: nil,
        salesTaxRate: nil,
        sellBrokerFeeRate: nil,
        status: status
      )
    }
    let first = entry(34)
    let second = entry(35)
    let alreadyProduced = entry(36, status: .manufacturingIgnored)
    let untouched = entry(37)
    for value in [first, second, alreadyProduced, untouched] {
      #expect(await runtime.saveTradeLogbookEntry(value))
    }

    let changed = await runtime.setTradeLogbookUsage(
      .production,
      forEntryIDs: [first.id, second.id, alreadyProduced.id]
    )
    #expect(changed == 2)
    #expect(runtime.tradeLogbookError == nil)
    let byID = Dictionary(
      uniqueKeysWithValues: runtime.tradeLogbookEntries.map { ($0.id, $0) }
    )
    #expect(byID[first.id]?.usage == .production)
    #expect(byID[second.id]?.usage == .production)
    #expect(byID[alreadyProduced.id]?.usage == .production)
    #expect(byID[untouched.id]?.usage == .sale(.home))
    #expect(byID[untouched.id]?.openQuantity == 10)

    #expect(await runtime.setTradeLogbookUsage(.consumption, forEntryIDs: []) == 0)
    #expect(
      await runtime.setTradeLogbookUsage(.consumption, forEntryIDs: [first.id]) == 1
    )
    #expect(
      runtime.tradeLogbookEntries.first { $0.id == first.id }?.usage == .consumption
    )
  }
}
