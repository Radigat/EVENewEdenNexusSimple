import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry rules")
struct IndustryRulesTests {
  @Test
  func roundsManufacturingMaterialsUp() {
    let quantity = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: 7,
      runs: 3,
      materialEfficiency: 10,
      facilityMultiplier: 0.98
    )
    #expect(quantity == 19)
  }

  @Test
  func extremeIndustryArithmeticSaturatesInsteadOfCrashing() {
    let quantity = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: Int64.max,
      runs: Int.max,
      materialEfficiency: 0,
      facilityMultiplier: .greatestFiniteMagnitude
    )
    let makespan = IndustryPlanner.slotMakespan(
      durations: [Int64.max, Int64.max, -1],
      slots: 1
    )

    #expect(quantity == Int64.max)
    #expect(makespan == Int64.max)
  }

  @Test
  func reservationsCannotDoubleSpendStock() async throws {
    let ledger = ReservationLedger()
    let first = UUID()
    try await ledger.reserve(
      planID: first,
      requested: [34: 7],
      stock: [34: 10]
    )

    await #expect(throws: ReservationConflict.self) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: 4],
        stock: [34: 10]
      )
    }
  }

  @Test
  func reservationsRejectNegativeOrZeroQuantities() async {
    let ledger = ReservationLedger()

    await #expect(
      throws: ReservationLedgerError.invalidQuantity(
        typeID: 34,
        quantity: -1
      )
    ) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: -1],
        stock: [34: 100]
      )
    }
    await #expect(
      throws: ReservationLedgerError.invalidStock(
        typeID: 34,
        quantity: -1
      )
    ) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: 1],
        stock: [34: -1]
      )
    }
  }
}
