import Foundation

public struct ReservationConflict: Error, Equatable, Sendable {
  public let typeID: Int64
  public let requested: Int64
  public let available: Int64
}

public enum ReservationLedgerError: Error, Equatable, Sendable {
  case invalidTypeID(Int64)
  case invalidQuantity(typeID: Int64, quantity: Int64)
  case invalidStock(typeID: Int64, quantity: Int64)
  case arithmeticOverflow(typeID: Int64)
}

public actor ReservationLedger {
  private var reservations: [UUID: [Int64: Int64]] = [:]

  public init() {}

  public func reserve(
    planID: UUID,
    requested: [Int64: Int64],
    stock: [Int64: Int64]
  ) throws {
    for (typeID, quantity) in requested {
      guard typeID > 0 else {
        throw ReservationLedgerError.invalidTypeID(typeID)
      }
      guard quantity > 0 else {
        throw ReservationLedgerError.invalidQuantity(
          typeID: typeID,
          quantity: quantity
        )
      }
    }
    for (typeID, quantity) in stock {
      guard typeID > 0 else {
        throw ReservationLedgerError.invalidTypeID(typeID)
      }
      guard quantity >= 0 else {
        throw ReservationLedgerError.invalidStock(
          typeID: typeID,
          quantity: quantity
        )
      }
    }

    for (typeID, quantity) in requested {
      var usedElsewhere = Int64.zero
      for entry in reservations where entry.key != planID {
        let (sum, overflow) = usedElsewhere.addingReportingOverflow(
          entry.value[typeID] ?? 0
        )
        guard !overflow else {
          throw ReservationLedgerError.arithmeticOverflow(typeID: typeID)
        }
        usedElsewhere = sum
      }
      let stored = stock[typeID] ?? 0
      let (difference, overflow) = stored.subtractingReportingOverflow(
        usedElsewhere
      )
      guard !overflow else {
        throw ReservationLedgerError.arithmeticOverflow(typeID: typeID)
      }
      let available = max(0, difference)
      guard quantity <= available else {
        throw ReservationConflict(
          typeID: typeID,
          requested: quantity,
          available: available
        )
      }
    }
    reservations[planID] = requested
  }

  public func release(planID: UUID) {
    reservations.removeValue(forKey: planID)
  }

  public func reserved(typeID: Int64, excluding planID: UUID? = nil) -> Int64 {
    var total = Int64.zero
    for entry in reservations where entry.key != planID {
      let (sum, overflow) = total.addingReportingOverflow(
        entry.value[typeID] ?? 0
      )
      if overflow { return Int64.max }
      total = sum
    }
    return total
  }
}
