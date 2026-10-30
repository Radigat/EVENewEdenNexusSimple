import Foundation
import Testing

@testable import EVENexusCore

@Suite("Market stock history")
struct MarketStockHistoryTests {
  private static let regionID: Int64 = 10_000_002
  private static let hubID: Int64 = 60_003_760
  private static let start = Date(timeIntervalSince1970: 1_793_000_000)

  @Test
  func pointSumsValidOrdersPerSideAndIgnoresOthers() throws {
    let market = snapshot(
      orders: [
        order(1, type: 34, sell: true, price: 10, volume: 100),
        order(2, type: 34, sell: true, price: 9, volume: 50),
        order(3, type: 34, sell: false, price: 8, volume: 30),
        order(4, type: 34, sell: false, price: 7.5, volume: 5),
        // Another station, invalid price and no remaining volume are ignored.
        order(5, type: 34, sell: true, price: 1, volume: 999, location: 1),
        order(6, type: 34, sell: true, price: 0, volume: 999),
        order(7, type: 34, sell: true, price: .nan, volume: 999),
        order(8, type: 34, sell: true, price: 5, volume: 0),
        // An ID repeated by overlapping ESI pages counts once.
        order(2, type: 34, sell: true, price: 9, volume: 50),
        order(9, type: 35, sell: false, price: 3, volume: 12),
      ]
    )
    let observation = try #require(MarketStockHistoryCalculator.observe(market))
    let point = observation.point
    #expect(point.locationID == Self.hubID)
    #expect(point.sourceSnapshotID == market.source.snapshotID)
    #expect(point.itemsByType.count == 2)
    let tritanium = point.value(for: 34)
    #expect(tritanium.sell == MarketStockSideValue(units: 150, orderCount: 2, bestPrice: 9))
    #expect(tritanium.buy == MarketStockSideValue(units: 35, orderCount: 2, bestPrice: 8))
    let buyOnly = point.value(for: 35)
    #expect(buyOnly.sell == .empty)
    #expect(buyOnly.buy.units == 12)
    // Not listed in a complete book: a known 0, not unknown.
    #expect(point.value(for: 99).sell == .empty)
    #expect(point.value(for: 99).buy == .empty)

    let ids = observation.baseline.entries.map(\.orderID)
    #expect(ids == [1, 2, 3, 4, 9])
  }

  @Test
  func incompleteBooksWriteNoPoint() {
    for state in DataFreshness.allCases where state != .fresh {
      let market = snapshot(
        orders: [order(1, type: 34, sell: true, price: 10, volume: 1)],
        state: state
      )
      #expect(MarketStockHistoryCalculator.observe(market) == nil)
    }
  }

  @Test
  func deltaSplitsAddedPartialFillsAndVanishedOrders() throws {
    let before = try observe(
      [
        order(1, type: 34, sell: true, price: 10, volume: 100),
        order(2, type: 34, sell: true, price: 11, volume: 50),
        order(3, type: 35, sell: true, price: 4, volume: 20),
        order(5, type: 34, sell: false, price: 8, volume: 30),
        order(7, type: 36, sell: true, price: 2, volume: 10),
      ],
      at: Self.start
    )
    let after = try observe(
      [
        order(1, type: 34, sell: true, price: 10, volume: 60),
        order(3, type: 35, sell: true, price: 4, volume: 20),
        order(4, type: 34, sell: true, price: 9.5, volume: 25),
        order(5, type: 34, sell: false, price: 8, volume: 10),
        order(6, type: 34, sell: false, price: 8.1, volume: 40),
      ],
      at: Self.start.addingTimeInterval(12 * 60 * 60)
    )
    let deltas = try compared(before, after)

    let sell = try #require(deltas[34]?.sell)
    #expect(sell == MarketStockSideDelta(added: 25, partiallyFilled: 40, vanished: 50))
    #expect(sell.removed == 90)
    #expect(sell.net == -65)
    let buy = try #require(deltas[34]?.buy)
    #expect(buy == MarketStockSideDelta(added: 40, partiallyFilled: 20, vanished: 0))
    #expect(buy.net == 20)
    // Unchanged item: no row, a known zero change.
    #expect(deltas[35] == nil)
    // Item gone completely: its stock is a known 0 and the rest vanished.
    #expect(after.point.value(for: 36).sell.units == 0)
    #expect(deltas[36]?.sell == MarketStockSideDelta(added: 0, partiallyFilled: 0, vanished: 10))

    expectNetMatchesStock(before: before.point, after: after.point, deltas: deltas)
  }

  @Test
  func changedItemOrSideOfAnOrderIDCountsAsReplacement() throws {
    let before = try observe(
      [order(1, type: 34, sell: true, price: 10, volume: 100)],
      at: Self.start
    )
    let after = try observe(
      [order(1, type: 35, sell: false, price: 10, volume: 70)],
      at: Self.start.addingTimeInterval(60)
    )
    let deltas = try compared(before, after)
    #expect(deltas[34]?.sell == MarketStockSideDelta(added: 0, partiallyFilled: 0, vanished: 100))
    #expect(deltas[35]?.buy == MarketStockSideDelta(added: 70, partiallyFilled: 0, vanished: 0))
    expectNetMatchesStock(before: before.point, after: after.point, deltas: deltas)
  }

  @Test
  func unknownDeltasKeepTheirReason() throws {
    let current = try observe(
      [order(1, type: 34, sell: true, price: 10, volume: 1)],
      at: Self.start
    )
    #expect(
      MarketStockHistoryCalculator.compare(previous: nil, current: current.baseline)
        == .unavailable(.noPreviousPoint)
    )
    let otherStation = MarketStockOrderBaseline(
      regionID: Self.regionID,
      locationID: Self.hubID + 1,
      capturedAt: Self.start.addingTimeInterval(-60),
      entries: []
    )
    #expect(
      MarketStockHistoryCalculator.compare(
        previous: otherStation,
        current: current.baseline
      ) == .unavailable(.locationChanged)
    )
    let otherRegion = MarketStockOrderBaseline(
      regionID: Self.regionID + 1,
      locationID: Self.hubID,
      capturedAt: Self.start.addingTimeInterval(-60),
      entries: []
    )
    #expect(
      MarketStockHistoryCalculator.compare(
        previous: otherRegion,
        current: current.baseline
      ) == .unavailable(.locationChanged)
    )
    #expect(
      MarketStockHistoryCalculator.compare(
        previous: current.baseline,
        current: current.baseline
      ) == .unavailable(.notChronological)
    )

    // Owner decision 29.10.2026: up to 72 hours compare, beyond is unknown.
    #expect(MarketStockHistoryCalculator.maximumComparisonGap == 72 * 60 * 60)
    let atLimit = baseline(at: Self.start.addingTimeInterval(-72 * 60 * 60))
    guard
      case .compared(let previousAt, _) = MarketStockHistoryCalculator.compare(
        previous: atLimit,
        current: current.baseline
      )
    else {
      Issue.record("A 72-hour gap must still be compared.")
      return
    }
    #expect(previousAt == atLimit.capturedAt)
    let beyond = baseline(at: Self.start.addingTimeInterval(-72 * 60 * 60 - 1))
    #expect(
      MarketStockHistoryCalculator.compare(previous: beyond, current: current.baseline)
        == .unavailable(.gapTooLarge)
    )
  }

  @Test
  func randomChangesAlwaysSatisfyNetEqualsAddedMinusRemoved() throws {
    var generator = SeededGenerator(seed: 0x5EED)
    var orders: [MarketOrder] = []
    var nextID: Int64 = 1
    for _ in 0..<2_000 {
      orders.append(randomOrder(id: nextID, using: &generator))
      nextID += 1
    }
    var previous = try observe(orders, at: Self.start)
    for round in 1...5 {
      var changed: [MarketOrder] = []
      for existing in orders {
        switch Int.random(in: 0..<10, using: &generator) {
        case 0, 1:
          continue  // vanished
        case 2, 3, 4:
          let remaining = Int64.random(
            in: 1...existing.volumeRemaining,
            using: &generator
          )
          changed.append(
            order(
              existing.id,
              type: existing.typeID,
              sell: existing.side == .sell,
              price: existing.price,
              volume: remaining
            )
          )
        default:
          changed.append(existing)
        }
      }
      for _ in 0..<300 {
        changed.append(randomOrder(id: nextID, using: &generator))
        nextID += 1
      }
      orders = changed.shuffled(using: &generator)
      let current = try observe(
        orders,
        at: Self.start.addingTimeInterval(Double(round) * 6 * 60 * 60)
      )
      let deltas = try compared(previous, current)
      expectNetMatchesStock(before: previous.point, after: current.point, deltas: deltas)
      previous = current
    }
  }

  /// Jita-sized synthetic book (C7 measurement): 15,000 items with 12 orders
  /// each, both sides. Reports runtime and the calculated working set.
  @Test
  func jitaSizedBookStaysWithinTheResourceBudget() throws {
    var generator = SeededGenerator(seed: 0x1717A)
    let typeCount = 15_000
    let ordersPerType = 12
    var orders: [MarketOrder] = []
    orders.reserveCapacity(typeCount * ordersPerType)
    var nextID: Int64 = 6_000_000_000
    for typeIndex in 0..<typeCount {
      for orderIndex in 0..<ordersPerType {
        orders.append(
          order(
            nextID,
            type: Int64(1_000 + typeIndex),
            sell: orderIndex < ordersPerType / 2,
            price: Double.random(in: 1...1_000_000, using: &generator),
            volume: Int64.random(in: 1...100_000, using: &generator)
          )
        )
        nextID += 1
      }
    }
    let first = snapshot(orders: orders, capturedAt: Self.start)
    // Second book: a quarter of the orders traded down, a tenth gone, new
    // orders for a tenth of the items.
    var changed: [MarketOrder] = []
    changed.reserveCapacity(orders.count)
    for (index, existing) in orders.enumerated() {
      if index.isMultiple(of: 10) { continue }
      if index.isMultiple(of: 4) {
        changed.append(
          order(
            existing.id,
            type: existing.typeID,
            sell: existing.side == .sell,
            price: existing.price,
            volume: max(1, existing.volumeRemaining / 2)
          )
        )
      } else {
        changed.append(existing)
      }
    }
    for typeIndex in stride(from: 0, to: typeCount, by: 10) {
      changed.append(
        order(nextID, type: Int64(1_000 + typeIndex), sell: true, price: 5, volume: 10)
      )
      nextID += 1
    }
    let second = snapshot(
      orders: changed,
      capturedAt: Self.start.addingTimeInterval(6 * 60 * 60)
    )

    let clock = ContinuousClock()
    var firstObservation: MarketStockObservation?
    var secondObservation: MarketStockObservation?
    var result: MarketStockDeltaResult?
    let duration = clock.measure {
      firstObservation = MarketStockHistoryCalculator.observe(first)
      secondObservation = MarketStockHistoryCalculator.observe(second)
      if let firstObservation, let secondObservation {
        result = MarketStockHistoryCalculator.compare(
          previous: firstObservation.baseline,
          current: secondObservation.baseline
        )
      }
    }
    let before = try #require(firstObservation)
    let after = try #require(secondObservation)
    #expect(before.baseline.entries.count == typeCount * ordersPerType)
    #expect(before.point.itemsByType.count == typeCount)
    guard case .compared(_, let deltas) = result else {
      Issue.record("The Jita-sized books must be comparable.")
      return
    }
    expectNetMatchesStock(before: before.point, after: after.point, deltas: deltas)

    // Working set of one observation: collected entries, prices, the sort
    // permutation and the sorted baseline, all fixed-size values.
    let orderCount = orders.count
    let workingBytes =
      orderCount
      * (2 * MemoryLayout<MarketStockOrderEntry>.stride
        + MemoryLayout<Double>.stride + MemoryLayout<Int>.stride)
    let baselineBytes = orderCount * MemoryLayout<MarketStockOrderEntry>.stride
    print(
      "market-stock jita-sized: orders=\(orderCount) items=\(typeCount) "
        + "observe+observe+compare=\(duration) "
        + "workingBytes=\(workingBytes) baselineBytes=\(baselineBytes)"
    )
    // C7 target: at most 50 MB in addition to the scan.
    #expect(workingBytes < 50 * 1_024 * 1_024)
    #expect(duration < .seconds(30))
  }

  // MARK: Helpers

  private func expectNetMatchesStock(
    before: MarketStockPoint,
    after: MarketStockPoint,
    deltas: [Int64: MarketStockItemDelta]
  ) {
    let typeIDs = Set(before.itemsByType.keys).union(after.itemsByType.keys)
    for typeID in typeIDs {
      let old = before.value(for: typeID)
      let new = after.value(for: typeID)
      let delta = deltas[typeID]
      #expect(new.sell.units - old.sell.units == (delta?.sell ?? .zero).net)
      #expect(new.buy.units - old.buy.units == (delta?.buy ?? .zero).net)
    }
  }

  private func compared(
    _ before: MarketStockObservation,
    _ after: MarketStockObservation
  ) throws -> [Int64: MarketStockItemDelta] {
    guard
      case .compared(_, let deltas) = MarketStockHistoryCalculator.compare(
        previous: before.baseline,
        current: after.baseline
      )
    else {
      Issue.record("Expected comparable points.")
      return [:]
    }
    return deltas
  }

  private func observe(
    _ orders: [MarketOrder],
    at capturedAt: Date
  ) throws -> MarketStockObservation {
    try #require(
      MarketStockHistoryCalculator.observe(
        snapshot(orders: orders, capturedAt: capturedAt)
      )
    )
  }

  private func baseline(at capturedAt: Date) -> MarketStockOrderBaseline {
    MarketStockOrderBaseline(
      regionID: Self.regionID,
      locationID: Self.hubID,
      capturedAt: capturedAt,
      entries: []
    )
  }

  private func snapshot(
    orders: [MarketOrder],
    state: DataFreshness = .fresh,
    capturedAt: Date = MarketStockHistoryTests.start
  ) -> MarketOrderSnapshot {
    MarketOrderSnapshot(
      id: UUID(),
      regionID: Self.regionID,
      locationID: Self.hubID,
      capturedAt: capturedAt,
      state: state,
      ordersByType: Dictionary(grouping: orders, by: \.typeID),
      source: SourceIdentity(
        provider: "fixture",
        version: "market-stock",
        capturedAt: capturedAt
      )
    )
  }

  private func order(
    _ id: Int64,
    type typeID: Int64,
    sell: Bool,
    price: Double,
    volume: Int64,
    location: Int64 = MarketStockHistoryTests.hubID
  ) -> MarketOrder {
    MarketOrder(
      id: id,
      typeID: typeID,
      locationID: location,
      systemID: 30_000_142,
      side: sell ? .sell : .buy,
      price: price,
      volumeRemaining: volume,
      minimumVolume: 1,
      issued: Self.start
    )
  }

  private func randomOrder(
    id: Int64,
    using generator: inout SeededGenerator
  ) -> MarketOrder {
    order(
      id,
      type: Int64.random(in: 34...60, using: &generator),
      sell: Bool.random(using: &generator),
      price: Double.random(in: 1...1_000, using: &generator),
      volume: Int64.random(in: 1...1_000, using: &generator)
    )
  }
}

/// Deterministic SplitMix64 so random tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
