import CSQLite
import Foundation

// Market stock history storage (MARKTBESTAND_PLAN.md, D and C3/C7): own
// SQLite file `dataRoot/market/market-stock-history.sqlite`, never the
// SwiftData store. Single points are kept 7 days; daily values, updated with
// every point, are kept 90 days. Days are UTC days (owner decision
// 29.10.2026).

public enum MarketStockHistoryStoreError: Error, Equatable, Sendable {
  case database(String)
  case invalidRow
  case corruptBaseline
  /// The file was written by a newer app version; it is left untouched.
  case unsupportedSchemaVersion(Int)
}

public enum MarketStockTrigger: String, Codable, Equatable, Sendable {
  case scheduled
  case automaticScan
  case manualScan
}

/// Whether the delta of a point to its predecessor is known.
public enum MarketStockDeltaStatus: Equatable, Sendable {
  case compared(previousCapturedAt: Date)
  case unavailable(MarketStockDeltaUnavailableReason)
}

public enum MarketStockRecordOutcome: Equatable, Sendable {
  case recorded(pointID: Int64, delta: MarketStockDeltaStatus)
  /// Owner decision 29.10.2026: a point less than 30 minutes after the last
  /// point of the same hub is not stored; the next delta starts from the
  /// older point.
  case skippedTooClose(lastCapturedAt: Date)
  /// A point not newer than the last stored point is not stored.
  case skippedOutOfOrder(lastCapturedAt: Date)
}

public struct MarketStockCompactionResult: Equatable, Sendable {
  public let removedPoints: Int
  public let removedDays: Int
  /// `false` when compaction already ran on this UTC day.
  public let didRun: Bool
}

/// One day of one item. `nil` deltas mean no known delta ended that day.
public struct MarketStockDailyValue: Equatable, Sendable {
  public let value: MarketStockItemValue
  public let minimumSellUnits: Int64
  public let maximumSellUnits: Int64
  public let sell: MarketStockSideDelta?
  public let buy: MarketStockSideDelta?
  public let pointCount: Int
  /// Points of the day whose delta to the predecessor is unknown; the day
  /// sums then cover only part of the day.
  public let unknownDeltaCount: Int
  /// Time of the day's last point, the moment the daily value describes.
  public let lastPointAt: Date
}

public struct MarketStockDailyEntry: Equatable, Sendable {
  /// UTC midnight of the day.
  public let day: Date
  /// `nil`: no point that day, the stock is unknown (never 0).
  public let recorded: MarketStockDailyValue?
}

public struct MarketStockPointEntry: Equatable, Sendable {
  public let capturedAt: Date
  public let trigger: MarketStockTrigger
  public let value: MarketStockItemValue
  public let delta: MarketStockDeltaStatus
  /// `nil` when the delta is unknown.
  public let sell: MarketStockSideDelta?
  public let buy: MarketStockSideDelta?
}

public struct MarketStockWindowCoverage: Equatable, Sendable {
  public let days: Int
  public let daysWithPoint: Int
  public let daysWithKnownDelta: Int
  public let daysWithUnknownDelta: Int

  /// Every day of the window has a known delta and none is partial.
  public var isComplete: Bool {
    daysWithKnownDelta == days && daysWithUnknownDelta == 0
  }
}

public struct MarketStockWindowTotals: Equatable, Sendable {
  public let days: Int
  public let sell: MarketStockSideDelta
  public let buy: MarketStockSideDelta
}

public struct MarketStockItemOverview: Equatable, Sendable {
  public let typeID: Int64
  /// Stock of the latest point; a known 0 when the item is not listed.
  public let current: MarketStockItemValue
  /// Known-delta sums per requested window, in request order.
  public let totals: [MarketStockWindowTotals]
}

public struct MarketStockHubOverview: Equatable, Sendable {
  public let role: OpportunityHubRole
  public let locationID: Int64
  /// `nil` without any stored point: everything is unknown.
  public let latestCapturedAt: Date?
  public let coverage: [MarketStockWindowCoverage]
  /// Items listed at the latest point or with a delta inside the largest
  /// window.
  public let itemsByType: [Int64: MarketStockItemOverview]
}

public actor MarketStockHistoryStore {
  public static let schemaVersion = 1
  public static let fineRetention: TimeInterval = 7 * 24 * 60 * 60
  public static let dailyRetentionDays: Int64 = 90
  public static let minimumPointSpacing: TimeInterval = 30 * 60
  private static let secondsPerDay: Double = 24 * 60 * 60
  private static let baselineEntrySize = 25

  private let database: MarketStockSQLiteDatabase

  public nonisolated static func open(url: URL) async throws
    -> MarketStockHistoryStore
  {
    let task = Task.detached(priority: .utility) {
      try MarketStockHistoryStore(url: url)
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
    database = try MarketStockSQLiteDatabase(url: url)
    try database.execute("PRAGMA journal_mode=WAL")
    try database.execute("PRAGMA synchronous=NORMAL")
    try Self.migrate(database)
  }

  public func close() {
    database.close()
  }

  public nonisolated static func utcDay(containing date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 / secondsPerDay).rounded(.down))
  }

  public nonisolated static func startOfUTCDay(_ day: Int64) -> Date {
    Date(timeIntervalSince1970: Double(day) * secondsPerDay)
  }

  // MARK: Writing

  /// Stores one point, its values and deltas, updates the daily values and
  /// replaces the hub's baseline, all in one transaction (C7). The previous
  /// baseline is read from the file only for the comparison.
  public func record(
    _ observation: MarketStockObservation,
    role: OpportunityHubRole,
    trigger: MarketStockTrigger
  ) throws -> MarketStockRecordOutcome {
    let point = observation.point
    let seriesID = try series(
      role: role,
      regionID: point.regionID,
      locationID: point.locationID
    )
    if let last = try lastPointCapturedAt(seriesID: seriesID) {
      guard point.capturedAt > last else { return .skippedOutOfOrder(lastCapturedAt: last) }
      guard point.capturedAt.timeIntervalSince(last) >= Self.minimumPointSpacing
      else { return .skippedTooClose(lastCapturedAt: last) }
    }
    let previous = try baseline(seriesID: seriesID)
    let comparison = try MarketStockHistoryCalculator.compare(
      previous: previous,
      current: observation.baseline,
      cancellationCheck: { try Task.checkCancellation() }
    )
    let deltasByType: [Int64: MarketStockItemDelta]?
    let status: MarketStockDeltaStatus
    switch comparison {
    case .compared(let previousCapturedAt, let deltas):
      deltasByType = deltas
      status = .compared(previousCapturedAt: previousCapturedAt)
    case .unavailable(let reason):
      deltasByType = nil
      status = .unavailable(reason)
    }

    let day = Self.utcDay(containing: point.capturedAt)
    var pointID: Int64 = 0
    try database.transaction {
      let earlierPointsToday = try database.queryInt(
        "SELECT point_count FROM stock_days WHERE series_id = ? AND day = ?",
        [.integer(seriesID), .integer(day)]
      ) ?? 0
      pointID = try insertPoint(
        seriesID: seriesID,
        point: point,
        day: day,
        trigger: trigger,
        status: status
      )
      try writeValues(
        pointID: pointID,
        seriesID: seriesID,
        day: day,
        point: point,
        deltasByType: deltasByType,
        dayHadEarlierPoints: earlierPointsToday > 0
      )
      try database.run(
        """
        UPDATE stock_daily_values SET
          sell_units = 0, sell_orders = 0, sell_best = NULL,
          buy_units = 0, buy_orders = 0, buy_best = NULL,
          min_sell_units = 0
        WHERE series_id = ? AND day = ? AND NOT EXISTS (
          SELECT 1 FROM stock_point_values v
          WHERE v.point_id = ? AND v.type_id = stock_daily_values.type_id
        )
        """,
        [.integer(seriesID), .integer(day), .integer(pointID)]
      )
      let known = deltasByType == nil ? 0 : 1
      try database.run(
        """
        INSERT INTO stock_days (
          series_id, day, point_count, known_delta_count,
          unknown_delta_count, first_point_at, last_point_at
        ) VALUES (?, ?, 1, ?, ?, ?, ?)
        ON CONFLICT(series_id, day) DO UPDATE SET
          point_count = point_count + 1,
          known_delta_count = known_delta_count + excluded.known_delta_count,
          unknown_delta_count =
            unknown_delta_count + excluded.unknown_delta_count,
          last_point_at = excluded.last_point_at
        """,
        [
          .integer(seriesID), .integer(day), .integer(Int64(known)),
          .integer(Int64(1 - known)),
          .real(point.capturedAt.timeIntervalSince1970),
          .real(point.capturedAt.timeIntervalSince1970),
        ]
      )
      try writeBaseline(seriesID: seriesID, baseline: observation.baseline)
    }
    return .recorded(pointID: pointID, delta: status)
  }

  private func insertPoint(
    seriesID: Int64,
    point: MarketStockPoint,
    day: Int64,
    trigger: MarketStockTrigger,
    status: MarketStockDeltaStatus
  ) throws -> Int64 {
    let deltaStatus: String
    let previousAt: MarketStockSQLiteValue
    switch status {
    case .compared(let previousCapturedAt):
      deltaStatus = "compared"
      previousAt = .real(previousCapturedAt.timeIntervalSince1970)
    case .unavailable(let reason):
      deltaStatus = reason.rawValue
      previousAt = .null
    }
    try database.run(
      """
      INSERT INTO stock_points (
        series_id, captured_at, day, source_snapshot_id, trigger,
        delta_status, previous_captured_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .integer(seriesID), .real(point.capturedAt.timeIntervalSince1970),
        .integer(day), .text(point.sourceSnapshotID.uuidString),
        .text(trigger.rawValue), .text(deltaStatus), previousAt,
      ]
    )
    return database.lastInsertedRowID
  }

  /// Writes one row per listed item and per item with a delta, reusing two
  /// prepared statements; no intermediate row arrays (C7).
  private func writeValues(
    pointID: Int64,
    seriesID: Int64,
    day: Int64,
    point: MarketStockPoint,
    deltasByType: [Int64: MarketStockItemDelta]?,
    dayHadEarlierPoints: Bool
  ) throws {
    let valueStatement = try database.prepare(
      """
      INSERT INTO stock_point_values (
        point_id, type_id, sell_units, sell_orders, sell_best,
        buy_units, buy_orders, buy_best,
        sell_added, sell_partial, sell_vanished,
        buy_added, buy_partial, buy_vanished
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    )
    defer { valueStatement.finalize() }
    let dailyStatement = try database.prepare(
      """
      INSERT INTO stock_daily_values (
        series_id, day, type_id, sell_units, sell_orders, sell_best,
        buy_units, buy_orders, buy_best, min_sell_units, max_sell_units,
        sell_added, sell_partial, sell_vanished,
        buy_added, buy_partial, buy_vanished
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(series_id, day, type_id) DO UPDATE SET
        sell_units = excluded.sell_units,
        sell_orders = excluded.sell_orders,
        sell_best = excluded.sell_best,
        buy_units = excluded.buy_units,
        buy_orders = excluded.buy_orders,
        buy_best = excluded.buy_best,
        min_sell_units = MIN(min_sell_units, excluded.sell_units),
        max_sell_units = MAX(max_sell_units, excluded.sell_units),
        sell_added = sell_added + excluded.sell_added,
        sell_partial = sell_partial + excluded.sell_partial,
        sell_vanished = sell_vanished + excluded.sell_vanished,
        buy_added = buy_added + excluded.buy_added,
        buy_partial = buy_partial + excluded.buy_partial,
        buy_vanished = buy_vanished + excluded.buy_vanished
      """
    )
    defer { dailyStatement.finalize() }

    func write(_ typeID: Int64) throws {
      let value = point.value(for: typeID)
      let known = deltasByType != nil
      let delta = deltasByType?[typeID]
      let sell = delta?.sell ?? .zero
      let buy = delta?.buy ?? .zero
      func deltaValue(_ amount: Int64) -> MarketStockSQLiteValue {
        known ? .integer(amount) : .null
      }
      try valueStatement.execute([
        .integer(pointID), .integer(typeID),
        .integer(value.sell.units), .integer(Int64(value.sell.orderCount)),
        .optionalReal(value.sell.bestPrice),
        .integer(value.buy.units), .integer(Int64(value.buy.orderCount)),
        .optionalReal(value.buy.bestPrice),
        deltaValue(sell.added), deltaValue(sell.partiallyFilled),
        deltaValue(sell.vanished),
        deltaValue(buy.added), deltaValue(buy.partiallyFilled),
        deltaValue(buy.vanished),
      ])
      // An item new today had no stock at the day's earlier points.
      let minimum: Int64 = dayHadEarlierPoints ? 0 : value.sell.units
      try dailyStatement.execute([
        .integer(seriesID), .integer(day), .integer(typeID),
        .integer(value.sell.units), .integer(Int64(value.sell.orderCount)),
        .optionalReal(value.sell.bestPrice),
        .integer(value.buy.units), .integer(Int64(value.buy.orderCount)),
        .optionalReal(value.buy.bestPrice),
        .integer(minimum), .integer(value.sell.units),
        .integer(sell.added), .integer(sell.partiallyFilled),
        .integer(sell.vanished),
        .integer(buy.added), .integer(buy.partiallyFilled),
        .integer(buy.vanished),
      ])
    }

    var written = 0
    for typeID in point.itemsByType.keys {
      try write(typeID)
      written += 1
      if written.isMultiple(of: 1_000) { try Task.checkCancellation() }
    }
    for typeID in (deltasByType ?? [:]).keys where point.itemsByType[typeID] == nil {
      try write(typeID)
    }
  }

  // MARK: Baseline

  private func writeBaseline(
    seriesID: Int64,
    baseline: MarketStockOrderBaseline
  ) throws {
    var bytes = [UInt8]()
    bytes.reserveCapacity(baseline.entries.count * Self.baselineEntrySize)
    for entry in baseline.entries {
      Self.append(entry.orderID, to: &bytes)
      Self.append(entry.typeID, to: &bytes)
      Self.append(entry.volumeRemaining, to: &bytes)
      bytes.append(entry.isBuy ? 1 : 0)
    }
    let statement = try database.prepare(
      """
      INSERT INTO stock_baselines (
        series_id, captured_at, entry_count, entries
      ) VALUES (?, ?, ?, ?)
      ON CONFLICT(series_id) DO UPDATE SET
        captured_at = excluded.captured_at,
        entry_count = excluded.entry_count,
        entries = excluded.entries
      """
    )
    defer { statement.finalize() }
    try bytes.withUnsafeBytes { buffer in
      try statement.execute(
        [
          .integer(seriesID),
          .real(baseline.capturedAt.timeIntervalSince1970),
          .integer(Int64(baseline.entries.count)),
        ],
        blob: buffer
      )
    }
  }

  private func baseline(seriesID: Int64) throws -> MarketStockOrderBaseline? {
    let statement = try database.prepare(
      """
      SELECT b.captured_at, b.entry_count, b.entries, s.region_id,
        s.location_id
      FROM stock_baselines b JOIN stock_series s ON s.id = b.series_id
      WHERE b.series_id = ?
      """
    )
    defer { statement.finalize() }
    try statement.bind([.integer(seriesID)])
    guard try statement.step() else { return nil }
    let count = Int(statement.int64(1))
    let buffer = statement.blob(2)
    guard count >= 0, buffer.count == count * Self.baselineEntrySize else {
      throw MarketStockHistoryStoreError.corruptBaseline
    }
    var entries: [MarketStockOrderEntry] = []
    entries.reserveCapacity(count)
    var offset = 0
    for _ in 0..<count {
      let orderID = Self.read(buffer, at: offset)
      let typeID = Self.read(buffer, at: offset + 8)
      let volume = Self.read(buffer, at: offset + 16)
      let isBuy = buffer[offset + 24] != 0
      offset += Self.baselineEntrySize
      entries.append(
        MarketStockOrderEntry(
          orderID: orderID,
          typeID: typeID,
          volumeRemaining: volume,
          isBuy: isBuy
        )
      )
    }
    return MarketStockOrderBaseline(
      regionID: statement.int64(3),
      locationID: statement.int64(4),
      capturedAt: Date(timeIntervalSince1970: statement.double(0)),
      entries: entries
    )
  }

  private static func append(_ value: Int64, to bytes: inout [UInt8]) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  private static func read(_ buffer: UnsafeRawBufferPointer, at offset: Int) -> Int64 {
    Int64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: Int64.self))
  }

  // MARK: Compaction

  /// Removes single points older than 7 days and daily values older than 90
  /// days, at most once per UTC day, in small transactions (one point or
  /// one day each) so a large deletion never holds the file long (C7).
  public func compactIfDue(now: Date) throws -> MarketStockCompactionResult {
    let today = Self.utcDay(containing: now)
    let lastRun = try database.queryInt(
      "SELECT value FROM stock_meta WHERE key = 'last_compaction_day'"
    )
    guard lastRun != today else {
      return MarketStockCompactionResult(removedPoints: 0, removedDays: 0, didRun: false)
    }
    let pointCutoff = now.addingTimeInterval(-Self.fineRetention)
      .timeIntervalSince1970
    let pointIDs = try database.queryInts(
      "SELECT id FROM stock_points WHERE captured_at < ? ORDER BY id",
      [.real(pointCutoff)]
    )
    for pointID in pointIDs {
      try Task.checkCancellation()
      try database.transaction {
        try database.run(
          "DELETE FROM stock_point_values WHERE point_id = ?",
          [.integer(pointID)]
        )
        try database.run("DELETE FROM stock_points WHERE id = ?", [.integer(pointID)])
      }
    }
    let firstKeptDay = today - Self.dailyRetentionDays + 1
    let oldDays = try database.query(
      "SELECT series_id, day FROM stock_days WHERE day < ? ORDER BY day",
      [.integer(firstKeptDay)]
    )
    for row in oldDays {
      try Task.checkCancellation()
      let parameters: [MarketStockSQLiteValue] = [
        .integer(row.int64(0)), .integer(row.int64(1)),
      ]
      try database.transaction {
        try database.run(
          "DELETE FROM stock_daily_values WHERE series_id = ? AND day = ?",
          parameters
        )
        try database.run(
          "DELETE FROM stock_days WHERE series_id = ? AND day = ?",
          parameters
        )
      }
    }
    try database.run(
      """
      INSERT INTO stock_meta (key, value) VALUES ('last_compaction_day', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      """,
      [.integer(today)]
    )
    return MarketStockCompactionResult(
      removedPoints: pointIDs.count,
      removedDays: oldDays.count,
      didRun: true
    )
  }

  // MARK: Reading

  public func latestPointCapturedAt(
    role: OpportunityHubRole,
    locationID: Int64
  ) throws -> Date? {
    guard let seriesID = try existingSeries(role: role, locationID: locationID)
    else { return nil }
    return try lastPointCapturedAt(seriesID: seriesID)
  }

  /// Daily values of one item for the `days` UTC days up to `now`'s day,
  /// oldest first. A day without a point is unknown; a day with a point but
  /// without the item is a known 0.
  public func itemDays(
    role: OpportunityHubRole,
    locationID: Int64,
    typeID: Int64,
    days: Int = 30,
    now: Date
  ) throws -> [MarketStockDailyEntry] {
    let today = Self.utcDay(containing: now)
    let firstDay = today - Int64(max(days, 1)) + 1
    var recordedByDay: [Int64: MarketStockDailyValue] = [:]
    if let seriesID = try existingSeries(role: role, locationID: locationID) {
      let statement = try database.prepare(
        """
        SELECT d.day, d.point_count, d.known_delta_count,
          d.unknown_delta_count,
          v.sell_units, v.sell_orders, v.sell_best,
          v.buy_units, v.buy_orders, v.buy_best,
          v.min_sell_units, v.max_sell_units,
          v.sell_added, v.sell_partial, v.sell_vanished,
          v.buy_added, v.buy_partial, v.buy_vanished, d.last_point_at
        FROM stock_days d
        LEFT JOIN stock_daily_values v
          ON v.series_id = d.series_id AND v.day = d.day AND v.type_id = ?
        WHERE d.series_id = ? AND d.day BETWEEN ? AND ?
        """
      )
      defer { statement.finalize() }
      try statement.bind([
        .integer(typeID), .integer(seriesID), .integer(firstDay),
        .integer(today),
      ])
      while try statement.step() {
        let hasRow = !statement.isNull(4)
        let knownDeltas = statement.int64(2) > 0
        func side(_ first: Int32) -> MarketStockSideDelta? {
          guard knownDeltas else { return nil }
          guard hasRow else { return .zero }
          return MarketStockSideDelta(
            added: statement.int64(first),
            partiallyFilled: statement.int64(first + 1),
            vanished: statement.int64(first + 2)
          )
        }
        recordedByDay[statement.int64(0)] = MarketStockDailyValue(
          value: hasRow
            ? MarketStockItemValue(
              typeID: typeID,
              sell: MarketStockSideValue(
                units: statement.int64(4),
                orderCount: Int(statement.int64(5)),
                bestPrice: statement.optionalDouble(6)
              ),
              buy: MarketStockSideValue(
                units: statement.int64(7),
                orderCount: Int(statement.int64(8)),
                bestPrice: statement.optionalDouble(9)
              )
            )
            : MarketStockItemValue(typeID: typeID, sell: .empty, buy: .empty),
          minimumSellUnits: hasRow ? statement.int64(10) : 0,
          maximumSellUnits: hasRow ? statement.int64(11) : 0,
          sell: side(12),
          buy: side(15),
          pointCount: Int(statement.int64(1)),
          unknownDeltaCount: Int(statement.int64(3)),
          lastPointAt: Date(timeIntervalSince1970: statement.double(18))
        )
      }
    }
    return (firstDay...today).map { day in
      MarketStockDailyEntry(
        day: Self.startOfUTCDay(day),
        recorded: recordedByDay[day]
      )
    }
  }

  /// Single points of one item since `now` minus `days` days (at most the
  /// 7-day fine retention), oldest first.
  public func itemPoints(
    role: OpportunityHubRole,
    locationID: Int64,
    typeID: Int64,
    days: Int = 7,
    now: Date
  ) throws -> [MarketStockPointEntry] {
    guard let seriesID = try existingSeries(role: role, locationID: locationID)
    else { return [] }
    let since = now.addingTimeInterval(-Double(days) * Self.secondsPerDay)
    let statement = try database.prepare(
      """
      SELECT p.captured_at, p.trigger, p.delta_status, p.previous_captured_at,
        v.sell_units, v.sell_orders, v.sell_best,
        v.buy_units, v.buy_orders, v.buy_best,
        v.sell_added, v.sell_partial, v.sell_vanished,
        v.buy_added, v.buy_partial, v.buy_vanished
      FROM stock_points p
      LEFT JOIN stock_point_values v
        ON v.point_id = p.id AND v.type_id = ?
      WHERE p.series_id = ? AND p.captured_at >= ?
      ORDER BY p.captured_at
      """
    )
    defer { statement.finalize() }
    try statement.bind([
      .integer(typeID), .integer(seriesID),
      .real(since.timeIntervalSince1970),
    ])
    var result: [MarketStockPointEntry] = []
    while try statement.step() {
      guard let trigger = MarketStockTrigger(rawValue: statement.text(1)),
        let status = Self.deltaStatus(
          statement.text(2),
          previous: statement.optionalDouble(3)
        )
      else { throw MarketStockHistoryStoreError.invalidRow }
      let hasRow = !statement.isNull(4)
      let isKnown: Bool
      if case .compared = status { isKnown = true } else { isKnown = false }
      func side(_ first: Int32) -> MarketStockSideDelta? {
        guard isKnown else { return nil }
        guard hasRow else { return .zero }
        return MarketStockSideDelta(
          added: statement.int64(first),
          partiallyFilled: statement.int64(first + 1),
          vanished: statement.int64(first + 2)
        )
      }
      result.append(
        MarketStockPointEntry(
          capturedAt: Date(timeIntervalSince1970: statement.double(0)),
          trigger: trigger,
          value: hasRow
            ? MarketStockItemValue(
              typeID: typeID,
              sell: MarketStockSideValue(
                units: statement.int64(4),
                orderCount: Int(statement.int64(5)),
                bestPrice: statement.optionalDouble(6)
              ),
              buy: MarketStockSideValue(
                units: statement.int64(7),
                orderCount: Int(statement.int64(8)),
                bestPrice: statement.optionalDouble(9)
              )
            )
            : MarketStockItemValue(typeID: typeID, sell: .empty, buy: .empty),
          delta: status,
          sell: side(10),
          buy: side(13)
        )
      )
    }
    return result
  }

  /// Latest stock and known-delta sums per window (UTC days up to `now`'s
  /// day, for example 1, 7 and 30) for every item of one hub.
  public func hubOverview(
    role: OpportunityHubRole,
    locationID: Int64,
    windows: [Int] = [1, 7, 30],
    now: Date
  ) throws -> MarketStockHubOverview {
    let windows = windows.map { max($0, 1) }
    let today = Self.utcDay(containing: now)
    guard let seriesID = try existingSeries(role: role, locationID: locationID),
      let latest = try latestPoint(seriesID: seriesID)
    else {
      return MarketStockHubOverview(
        role: role,
        locationID: locationID,
        latestCapturedAt: nil,
        coverage: windows.map {
          MarketStockWindowCoverage(
            days: $0,
            daysWithPoint: 0,
            daysWithKnownDelta: 0,
            daysWithUnknownDelta: 0
          )
        },
        itemsByType: [:]
      )
    }
    let largest = windows.max() ?? 1
    let firstDay = today - Int64(largest) + 1

    var coverageDays: [(day: Int64, known: Bool, unknown: Bool)] = []
    for row in try database.query(
      """
      SELECT day, known_delta_count, unknown_delta_count FROM stock_days
      WHERE series_id = ? AND day BETWEEN ? AND ?
      """,
      [.integer(seriesID), .integer(firstDay), .integer(today)]
    ) {
      coverageDays.append((row.int64(0), row.int64(1) > 0, row.int64(2) > 0))
    }
    let coverage = windows.map { window in
      let start = today - Int64(window) + 1
      let inside = coverageDays.filter { $0.day >= start }
      return MarketStockWindowCoverage(
        days: window,
        daysWithPoint: inside.count,
        daysWithKnownDelta: inside.filter(\.known).count,
        daysWithUnknownDelta: inside.filter(\.unknown).count
      )
    }

    var current: [Int64: MarketStockItemValue] = [:]
    let currentStatement = try database.prepare(
      """
      SELECT type_id, sell_units, sell_orders, sell_best,
        buy_units, buy_orders, buy_best
      FROM stock_point_values WHERE point_id = ?
      """
    )
    defer { currentStatement.finalize() }
    try currentStatement.bind([.integer(latest.id)])
    while try currentStatement.step() {
      let typeID = currentStatement.int64(0)
      current[typeID] = MarketStockItemValue(
        typeID: typeID,
        sell: MarketStockSideValue(
          units: currentStatement.int64(1),
          orderCount: Int(currentStatement.int64(2)),
          bestPrice: currentStatement.optionalDouble(3)
        ),
        buy: MarketStockSideValue(
          units: currentStatement.int64(4),
          orderCount: Int(currentStatement.int64(5)),
          bestPrice: currentStatement.optionalDouble(6)
        )
      )
    }

    // One pass over the daily rows of the largest window; sums per window
    // are accumulated in place.
    var totals: [Int64: [(sell: MarketStockSideDelta, buy: MarketStockSideDelta)]] = [:]
    let totalsStatement = try database.prepare(
      """
      SELECT type_id, day, sell_added, sell_partial, sell_vanished,
        buy_added, buy_partial, buy_vanished
      FROM stock_daily_values
      WHERE series_id = ? AND day BETWEEN ? AND ?
      """
    )
    defer { totalsStatement.finalize() }
    try totalsStatement.bind([
      .integer(seriesID), .integer(firstDay), .integer(today),
    ])
    let emptyTotals = Array(
      repeating: (sell: MarketStockSideDelta.zero, buy: MarketStockSideDelta.zero),
      count: windows.count
    )
    while try totalsStatement.step() {
      let typeID = totalsStatement.int64(0)
      let day = totalsStatement.int64(1)
      let sell = MarketStockSideDelta(
        added: totalsStatement.int64(2),
        partiallyFilled: totalsStatement.int64(3),
        vanished: totalsStatement.int64(4)
      )
      let buy = MarketStockSideDelta(
        added: totalsStatement.int64(5),
        partiallyFilled: totalsStatement.int64(6),
        vanished: totalsStatement.int64(7)
      )
      var sums = totals[typeID] ?? emptyTotals
      for (index, window) in windows.enumerated()
      where day >= today - Int64(window) + 1 {
        sums[index] = (
          Self.sum(sums[index].sell, sell),
          Self.sum(sums[index].buy, buy)
        )
      }
      totals[typeID] = sums
    }

    var items: [Int64: MarketStockItemOverview] = [:]
    for typeID in Set(current.keys).union(totals.keys) {
      let sums = totals[typeID] ?? emptyTotals
      items[typeID] = MarketStockItemOverview(
        typeID: typeID,
        current: current[typeID]
          ?? MarketStockItemValue(typeID: typeID, sell: .empty, buy: .empty),
        totals: zip(windows, sums).map {
          MarketStockWindowTotals(days: $0, sell: $1.sell, buy: $1.buy)
        }
      )
    }
    return MarketStockHubOverview(
      role: role,
      locationID: locationID,
      latestCapturedAt: latest.capturedAt,
      coverage: coverage,
      itemsByType: items
    )
  }

  // MARK: Helpers

  private static func sum(
    _ lhs: MarketStockSideDelta,
    _ rhs: MarketStockSideDelta
  ) -> MarketStockSideDelta {
    MarketStockSideDelta(
      added: MarketStockMath.saturatedAdd(lhs.added, rhs.added),
      partiallyFilled: MarketStockMath.saturatedAdd(
        lhs.partiallyFilled,
        rhs.partiallyFilled
      ),
      vanished: MarketStockMath.saturatedAdd(lhs.vanished, rhs.vanished)
    )
  }

  private static func deltaStatus(
    _ raw: String,
    previous: Double?
  ) -> MarketStockDeltaStatus? {
    if raw == "compared" {
      return previous.map {
        .compared(previousCapturedAt: Date(timeIntervalSince1970: $0))
      }
    }
    return MarketStockDeltaUnavailableReason(rawValue: raw).map {
      .unavailable($0)
    }
  }

  private func series(
    role: OpportunityHubRole,
    regionID: Int64,
    locationID: Int64
  ) throws -> Int64 {
    if let existing = try existingSeries(role: role, locationID: locationID) {
      return existing
    }
    try database.run(
      "INSERT INTO stock_series (role, region_id, location_id) VALUES (?, ?, ?)",
      [.text(role.rawValue), .integer(regionID), .integer(locationID)]
    )
    return database.lastInsertedRowID
  }

  private func existingSeries(
    role: OpportunityHubRole,
    locationID: Int64
  ) throws -> Int64? {
    try database.queryInt(
      "SELECT id FROM stock_series WHERE role = ? AND location_id = ?",
      [.text(role.rawValue), .integer(locationID)]
    )
  }

  private func lastPointCapturedAt(seriesID: Int64) throws -> Date? {
    try latestPoint(seriesID: seriesID)?.capturedAt
  }

  private func latestPoint(
    seriesID: Int64
  ) throws -> (id: Int64, capturedAt: Date)? {
    guard
      let row = try database.query(
        """
        SELECT id, captured_at FROM stock_points WHERE series_id = ?
        ORDER BY captured_at DESC LIMIT 1
        """,
        [.integer(seriesID)]
      ).first
    else { return nil }
    return (row.int64(0), Date(timeIntervalSince1970: row.double(1)))
  }

  static func migrate(_ database: MarketStockSQLiteDatabase) throws {
    let version = Int(try database.queryInt("PRAGMA user_version") ?? 0)
    guard version <= schemaVersion else {
      throw MarketStockHistoryStoreError.unsupportedSchemaVersion(version)
    }
    guard version < 1 else { return }
    try database.transaction {
      try database.execute(
        """
        CREATE TABLE IF NOT EXISTS stock_series (
          id INTEGER PRIMARY KEY,
          role TEXT NOT NULL,
          region_id INTEGER NOT NULL,
          location_id INTEGER NOT NULL,
          UNIQUE (role, location_id)
        );
        CREATE TABLE IF NOT EXISTS stock_points (
          id INTEGER PRIMARY KEY,
          series_id INTEGER NOT NULL REFERENCES stock_series(id),
          captured_at REAL NOT NULL,
          day INTEGER NOT NULL,
          source_snapshot_id TEXT NOT NULL,
          trigger TEXT NOT NULL,
          delta_status TEXT NOT NULL,
          previous_captured_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_stock_points_series_time
          ON stock_points(series_id, captured_at);
        CREATE TABLE IF NOT EXISTS stock_point_values (
          point_id INTEGER NOT NULL,
          type_id INTEGER NOT NULL,
          sell_units INTEGER NOT NULL,
          sell_orders INTEGER NOT NULL,
          sell_best REAL,
          buy_units INTEGER NOT NULL,
          buy_orders INTEGER NOT NULL,
          buy_best REAL,
          sell_added INTEGER,
          sell_partial INTEGER,
          sell_vanished INTEGER,
          buy_added INTEGER,
          buy_partial INTEGER,
          buy_vanished INTEGER,
          PRIMARY KEY (point_id, type_id)
        ) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS stock_daily_values (
          series_id INTEGER NOT NULL,
          day INTEGER NOT NULL,
          type_id INTEGER NOT NULL,
          sell_units INTEGER NOT NULL,
          sell_orders INTEGER NOT NULL,
          sell_best REAL,
          buy_units INTEGER NOT NULL,
          buy_orders INTEGER NOT NULL,
          buy_best REAL,
          min_sell_units INTEGER NOT NULL,
          max_sell_units INTEGER NOT NULL,
          sell_added INTEGER NOT NULL,
          sell_partial INTEGER NOT NULL,
          sell_vanished INTEGER NOT NULL,
          buy_added INTEGER NOT NULL,
          buy_partial INTEGER NOT NULL,
          buy_vanished INTEGER NOT NULL,
          PRIMARY KEY (series_id, day, type_id)
        ) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS stock_days (
          series_id INTEGER NOT NULL,
          day INTEGER NOT NULL,
          point_count INTEGER NOT NULL,
          known_delta_count INTEGER NOT NULL,
          unknown_delta_count INTEGER NOT NULL,
          first_point_at REAL NOT NULL,
          last_point_at REAL NOT NULL,
          PRIMARY KEY (series_id, day)
        ) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS stock_baselines (
          series_id INTEGER PRIMARY KEY REFERENCES stock_series(id),
          captured_at REAL NOT NULL,
          entry_count INTEGER NOT NULL,
          entries BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS stock_meta (
          key TEXT PRIMARY KEY,
          value INTEGER NOT NULL
        );
        PRAGMA user_version = 1;
        """
      )
    }
  }
}

// MARK: SQLite access with reusable prepared statements

enum MarketStockSQLiteValue: Sendable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)

  static func optionalReal(_ value: Double?) -> Self {
    value.map { .real($0) } ?? .null
  }
}

struct MarketStockSQLiteRow: Sendable {
  let values: [MarketStockSQLiteValue]

  func int64(_ index: Int) -> Int64 {
    switch values[index] {
    case .integer(let value): value
    case .real(let value): Int64(value)
    default: 0
    }
  }

  func double(_ index: Int) -> Double {
    switch values[index] {
    case .real(let value): value
    case .integer(let value): Double(value)
    default: 0
    }
  }
}

final class MarketStockSQLiteStatement {
  private let handle: OpaquePointer
  private let database: MarketStockSQLiteDatabase
  private var finalized = false

  init(handle: OpaquePointer, database: MarketStockSQLiteDatabase) {
    self.handle = handle
    self.database = database
  }

  deinit { finalize() }

  func finalize() {
    guard !finalized else { return }
    sqlite3_finalize(handle)
    finalized = true
  }

  func bind(_ values: [MarketStockSQLiteValue]) throws {
    sqlite3_reset(handle)
    sqlite3_clear_bindings(handle)
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case .null:
        status = sqlite3_bind_null(handle, index)
      case .integer(let value):
        status = sqlite3_bind_int64(handle, index, value)
      case .real(let value):
        status = sqlite3_bind_double(handle, index, value)
      case .text(let value):
        status = sqlite3_bind_text(
          handle,
          index,
          value,
          -1,
          unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
      }
      guard status == SQLITE_OK else { throw database.error("bind") }
    }
  }

  /// Binds, runs to completion and resets for the next use.
  func execute(
    _ values: [MarketStockSQLiteValue],
    blob: UnsafeRawBufferPointer? = nil
  ) throws {
    try bind(values)
    if let blob {
      // SQLITE_STATIC: the buffer outlives the step below, so no copy.
      let status = sqlite3_bind_blob(
        handle,
        Int32(values.count + 1),
        blob.baseAddress,
        Int32(blob.count),
        nil
      )
      guard status == SQLITE_OK else { throw database.error("bind blob") }
    }
    defer { sqlite3_reset(handle) }
    guard sqlite3_step(handle) == SQLITE_DONE else {
      throw database.error("step")
    }
  }

  /// `true` while a row is available.
  func step() throws -> Bool {
    let status = sqlite3_step(handle)
    if status == SQLITE_ROW { return true }
    if status == SQLITE_DONE { return false }
    throw database.error("step")
  }

  var columnCount: Int32 { sqlite3_column_count(handle) }

  func isNull(_ column: Int32) -> Bool {
    sqlite3_column_type(handle, column) == SQLITE_NULL
  }

  func isInteger(_ column: Int32) -> Bool {
    sqlite3_column_type(handle, column) == SQLITE_INTEGER
  }

  func int64(_ column: Int32) -> Int64 {
    sqlite3_column_int64(handle, column)
  }

  func double(_ column: Int32) -> Double {
    sqlite3_column_double(handle, column)
  }

  func optionalDouble(_ column: Int32) -> Double? {
    isNull(column) ? nil : double(column)
  }

  func text(_ column: Int32) -> String {
    sqlite3_column_text(handle, column).map { String(cString: $0) } ?? ""
  }

  /// Valid until the next step, reset or finalize.
  func blob(_ column: Int32) -> UnsafeRawBufferPointer {
    let count = Int(sqlite3_column_bytes(handle, column))
    guard let pointer = sqlite3_column_blob(handle, column), count > 0 else {
      return UnsafeRawBufferPointer(start: nil, count: 0)
    }
    return UnsafeRawBufferPointer(start: pointer, count: count)
  }
}

final class MarketStockSQLiteDatabase: @unchecked Sendable {
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
      throw MarketStockHistoryStoreError.database(message)
    }
    sqlite3_busy_timeout(handle, 5_000)
  }

  deinit { close() }

  func close() {
    guard let handle else { return }
    sqlite3_close_v2(handle)
    self.handle = nil
  }

  var lastInsertedRowID: Int64 { sqlite3_last_insert_rowid(handle) }

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
      throw MarketStockHistoryStoreError.database(message)
    }
  }

  func prepare(_ sql: String) throws -> MarketStockSQLiteStatement {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else { throw error("prepare") }
    return MarketStockSQLiteStatement(handle: statement, database: self)
  }

  func run(_ sql: String, _ values: [MarketStockSQLiteValue] = []) throws {
    let statement = try prepare(sql)
    defer { statement.finalize() }
    try statement.execute(values)
  }

  func query(
    _ sql: String,
    _ values: [MarketStockSQLiteValue] = []
  ) throws -> [MarketStockSQLiteRow] {
    let statement = try prepare(sql)
    defer { statement.finalize() }
    try statement.bind(values)
    var rows: [MarketStockSQLiteRow] = []
    while try statement.step() {
      let count = statement.columnCount
      rows.append(
        MarketStockSQLiteRow(
          values: (0..<count).map { column in
            if statement.isNull(column) { return .null }
            return statement.isInteger(column)
              ? .integer(statement.int64(column))
              : .real(statement.double(column))
          }
        )
      )
    }
    return rows
  }

  func queryInt(
    _ sql: String,
    _ values: [MarketStockSQLiteValue] = []
  ) throws -> Int64? {
    let statement = try prepare(sql)
    defer { statement.finalize() }
    try statement.bind(values)
    guard try statement.step(), !statement.isNull(0) else { return nil }
    return statement.int64(0)
  }

  func queryInts(
    _ sql: String,
    _ values: [MarketStockSQLiteValue] = []
  ) throws -> [Int64] {
    let statement = try prepare(sql)
    defer { statement.finalize() }
    try statement.bind(values)
    var result: [Int64] = []
    while try statement.step() { result.append(statement.int64(0)) }
    return result
  }

  func error(_ operation: String) -> MarketStockHistoryStoreError {
    .database(
      handle.map { "\(operation): \(String(cString: sqlite3_errmsg($0)))" }
        ?? operation
    )
  }
}
