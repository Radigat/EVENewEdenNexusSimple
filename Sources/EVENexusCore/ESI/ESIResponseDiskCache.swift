import CSQLite
import Foundation

/// One cached ESI GET representation as `ESIClient` keeps it: body,
/// validators, expiry and the provenance of the original response.
public struct ESIStoredResponse: Equatable, Sendable {
  public let etag: String?
  public let lastModified: String?
  public let data: Data
  public let expiresAt: Date?
  public let pages: Int?
  public let statusCode: Int
  public let source: SourceIdentity

  public init(
    etag: String?,
    lastModified: String?,
    data: Data,
    expiresAt: Date?,
    pages: Int?,
    statusCode: Int,
    source: SourceIdentity
  ) {
    self.etag = etag
    self.lastModified = lastModified
    self.data = data
    self.expiresAt = expiresAt
    self.pages = pages
    self.statusCode = statusCode
    self.source = source
  }
}

/// Durable second level behind the in-memory ESI cache. Keys are
/// `ESIClient` cache keys (`partition|url`); a store never sees credentials.
public protocol ESIResponseStoring: Sendable {
  func response(forKey key: String) async -> ESIStoredResponse?
  func store(_ response: ESIStoredResponse, forKey key: String) async
  func removeResponse(forKey key: String) async
  /// Removes every response of one partition, e.g. `character:123`.
  func removeResponses(inPartition partition: String) async
  /// Removes responses whose key starts with `prefix` and satisfies `matches`.
  func removeResponses(
    withKeyPrefix prefix: String,
    where matches: @Sendable (String) -> Bool
  ) async
  /// Removes the given keys unless their stored `Last-Modified` equals
  /// `lastModified`.
  func removeResponses(forKeys keys: [String], exceptLastModified lastModified: String)
    async
}

/// SQLite file that keeps ESI responses across app restarts so the app does
/// not request data again before its `Expires` (CCP ESI best practices).
/// Expired entries stay for conditional revalidation until the size limit
/// evicts the least recently used ones. Entries of another compatibility date
/// are discarded on open. Any database failure disables the store for this run
/// instead of failing an ESI request.
public actor ESIResponseDiskCache: ESIResponseStoring {
  public static let schemaVersion = 1
  public static let defaultMaximumBytes = 512 * 1_024 * 1_024

  private let url: URL
  private let maximumBytes: Int
  private let compatibilityDate: String
  private let now: @Sendable () -> Date
  private var database: ESIResponseCacheDatabase?
  private var isUnavailable = false
  private var storedBytes = 0
  private var hits = 0
  private var stores = 0
  private var evictions = 0
  private var lastSummaryAt: Date?

  public init(
    url: URL,
    maximumBytes: Int = defaultMaximumBytes,
    compatibilityDate: String = EVEConstants.esiCompatibilityDate,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.url = url
    self.maximumBytes = max(0, maximumBytes)
    self.compatibilityDate = compatibilityDate
    self.now = now
  }

  public func response(forKey key: String) -> ESIStoredResponse? {
    guard let database = openDatabase() else { return nil }
    do {
      guard
        let row = try database.query(
          """
          SELECT etag, last_modified, body, expires_at, pages, status_code,
                 provider, version, captured_at, snapshot_id
          FROM esi_responses
          WHERE cache_key = ? AND compatibility_date = ?
          """,
          [.text(key), .text(compatibilityDate)]
        ).first,
        let body = row["body"]?.data,
        let statusCode = row["status_code"]?.integer,
        let provider = row["provider"]?.text,
        let version = row["version"]?.text,
        let capturedAt = row["captured_at"]?.real,
        let snapshotID = row["snapshot_id"]?.text.flatMap(UUID.init(uuidString:))
      else { return nil }
      try database.run(
        "UPDATE esi_responses SET last_access = ? WHERE cache_key = ?",
        [.real(now().timeIntervalSince1970), .text(key)]
      )
      hits += 1
      return ESIStoredResponse(
        etag: row["etag"]?.text,
        lastModified: row["last_modified"]?.text,
        data: body,
        expiresAt: row["expires_at"]?.real.map(Date.init(timeIntervalSince1970:)),
        pages: row["pages"]?.integer.map(Int.init),
        statusCode: Int(statusCode),
        source: SourceIdentity(
          provider: provider,
          version: version,
          capturedAt: Date(timeIntervalSince1970: capturedAt),
          snapshotID: snapshotID
        )
      )
    } catch {
      disable(after: error)
      return nil
    }
  }

  public func store(_ response: ESIStoredResponse, forKey key: String) {
    guard response.data.count <= maximumBytes,
      let database = openDatabase()
    else { return }
    do {
      let previous =
        try database.query(
          "SELECT byte_count FROM esi_responses WHERE cache_key = ?",
          [.text(key)]
        ).first?["byte_count"]?.integer ?? 0
      try database.run(
        """
        INSERT OR REPLACE INTO esi_responses (
          cache_key, partition, compatibility_date, etag, last_modified,
          expires_at, pages, status_code, provider, version, captured_at,
          snapshot_id, body, byte_count, last_access
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          .text(key),
          .text(Self.partition(ofKey: key)),
          .text(compatibilityDate),
          response.etag.map(ESIResponseCacheValue.text) ?? .null,
          response.lastModified.map(ESIResponseCacheValue.text) ?? .null,
          response.expiresAt.map { .real($0.timeIntervalSince1970) } ?? .null,
          response.pages.map { .integer(Int64($0)) } ?? .null,
          .integer(Int64(response.statusCode)),
          .text(response.source.provider),
          .text(response.source.version),
          .real(response.source.capturedAt.timeIntervalSince1970),
          .text(response.source.snapshotID.uuidString),
          .blob(response.data),
          .integer(Int64(response.data.count)),
          .real(now().timeIntervalSince1970),
        ]
      )
      storedBytes += response.data.count - Int(previous)
      stores += 1
      try evictIfNeeded(database)
      logSummaryIfDue()
    } catch {
      disable(after: error)
    }
  }

  public func removeResponse(forKey key: String) {
    removeKeys([key])
  }

  public func removeResponses(inPartition partition: String) {
    guard let database = openDatabase() else { return }
    do {
      try database.run(
        "DELETE FROM esi_responses WHERE partition = ?",
        [.text(partition)]
      )
      try refreshStoredBytes(database)
    } catch {
      disable(after: error)
    }
  }

  public func removeResponses(
    withKeyPrefix prefix: String,
    where matches: @Sendable (String) -> Bool
  ) {
    guard let database = openDatabase() else { return }
    do {
      let keys = try database.query(
        """
        SELECT cache_key FROM esi_responses
        WHERE substr(cache_key, 1, ?) = ?
        """,
        [.integer(Int64(prefix.utf8.count)), .text(prefix)]
      ).compactMap { $0["cache_key"]?.text }.filter(matches)
      removeKeys(keys)
    } catch {
      disable(after: error)
    }
  }

  public func removeResponses(
    forKeys keys: [String],
    exceptLastModified lastModified: String
  ) {
    guard !keys.isEmpty, let database = openDatabase() else { return }
    do {
      var stale: [String] = []
      for key in keys {
        guard
          let row = try database.query(
            "SELECT last_modified FROM esi_responses WHERE cache_key = ?",
            [.text(key)]
          ).first
        else { continue }
        if row["last_modified"]?.text != lastModified {
          stale.append(key)
        }
      }
      removeKeys(stale)
    } catch {
      disable(after: error)
    }
  }

  /// Entry count and stored body bytes, for diagnostics and tests.
  public func usage() -> (entries: Int, bytes: Int) {
    guard let database = openDatabase() else { return (0, 0) }
    let entries =
      (try? database.query("SELECT COUNT(*) AS count FROM esi_responses"))?
      .first?["count"]?.integer ?? 0
    return (Int(entries), storedBytes)
  }

  static func partition(ofKey key: String) -> String {
    key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
  }

  private func removeKeys(_ keys: [String]) {
    guard !keys.isEmpty, let database = openDatabase() else { return }
    do {
      try database.transaction {
        for key in keys {
          try database.run(
            "DELETE FROM esi_responses WHERE cache_key = ?",
            [.text(key)]
          )
        }
      }
      try refreshStoredBytes(database)
    } catch {
      disable(after: error)
    }
  }

  private func evictIfNeeded(_ database: ESIResponseCacheDatabase) throws {
    guard storedBytes > maximumBytes else { return }
    // Evict to 90 % so the next stores do not trigger eviction again at once.
    let target = maximumBytes / 10 * 9
    let candidates = try database.query(
      """
      SELECT cache_key, byte_count FROM esi_responses
      ORDER BY last_access, cache_key
      """
    )
    var remaining = storedBytes
    var victims: [String] = []
    for row in candidates where remaining > target {
      guard let key = row["cache_key"]?.text,
        let bytes = row["byte_count"]?.integer
      else { continue }
      victims.append(key)
      remaining -= Int(bytes)
    }
    try database.transaction {
      for key in victims {
        try database.run(
          "DELETE FROM esi_responses WHERE cache_key = ?",
          [.text(key)]
        )
      }
    }
    evictions += victims.count
    try refreshStoredBytes(database)
  }

  private func refreshStoredBytes(_ database: ESIResponseCacheDatabase) throws {
    storedBytes = Int(
      try database.query(
        "SELECT COALESCE(SUM(byte_count), 0) AS bytes FROM esi_responses"
      ).first?["bytes"]?.integer ?? 0
    )
  }

  private func openDatabase() -> ESIResponseCacheDatabase? {
    if let database { return database }
    guard !isUnavailable else { return nil }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let database = try ESIResponseCacheDatabase(url: url)
      try database.execute("PRAGMA journal_mode=WAL")
      try database.execute("PRAGMA synchronous=NORMAL")
      let version =
        try database.query("PRAGMA user_version").first?["user_version"]?
        .integer ?? 0
      guard version <= Int64(Self.schemaVersion) else {
        throw ESIResponseCacheError.unsupportedSchemaVersion(Int(version))
      }
      if version < 1 {
        try database.execute(
          """
          CREATE TABLE IF NOT EXISTS esi_responses (
            cache_key TEXT PRIMARY KEY NOT NULL,
            partition TEXT NOT NULL,
            compatibility_date TEXT NOT NULL,
            etag TEXT,
            last_modified TEXT,
            expires_at REAL,
            pages INTEGER,
            status_code INTEGER NOT NULL,
            provider TEXT NOT NULL,
            version TEXT NOT NULL,
            captured_at REAL NOT NULL,
            snapshot_id TEXT NOT NULL,
            body BLOB NOT NULL,
            byte_count INTEGER NOT NULL,
            last_access REAL NOT NULL
          );
          CREATE INDEX IF NOT EXISTS idx_esi_responses_partition
            ON esi_responses(partition);
          CREATE INDEX IF NOT EXISTS idx_esi_responses_last_access
            ON esi_responses(last_access);
          PRAGMA user_version = 1;
          """
        )
      }
      try database.run(
        "DELETE FROM esi_responses WHERE compatibility_date <> ?",
        [.text(compatibilityDate)]
      )
      self.database = database
      try refreshStoredBytes(database)
      let entries =
        try database.query("SELECT COUNT(*) AS count FROM esi_responses")
        .first?["count"]?.integer ?? 0
      PerformanceLog.event(
        "esi.disk-cache",
        "opened entries=\(entries) kb=\(storedBytes / 1_024)"
      )
      if storedBytes > maximumBytes {
        try evictIfNeeded(database)
      }
      return database
    } catch {
      disable(after: error)
      return nil
    }
  }

  private func disable(after error: Error) {
    database?.close()
    database = nil
    isUnavailable = true
    PerformanceLog.event("esi.disk-cache", "unavailable for this run")
  }

  private func logSummaryIfDue() {
    let current = now()
    if let lastSummaryAt, current.timeIntervalSince(lastSummaryAt) < 60 {
      return
    }
    lastSummaryAt = current
    PerformanceLog.event(
      "esi.disk-cache",
      "hits=\(hits) stores=\(stores) evictions=\(evictions)"
        + " kb=\(storedBytes / 1_024)"
    )
  }
}

public enum ESIResponseCacheError: Error, Equatable, Sendable {
  case database(String)
  /// The file was written by a newer app version; it is left untouched.
  case unsupportedSchemaVersion(Int)
}

enum ESIResponseCacheValue: Sendable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
  case blob(Data)

  var integer: Int64? {
    if case .integer(let value) = self { return value }
    return nil
  }

  var real: Double? {
    switch self {
    case .real(let value): value
    case .integer(let value): Double(value)
    default: nil
    }
  }

  var text: String? {
    if case .text(let value) = self { return value }
    return nil
  }

  var data: Data? {
    switch self {
    case .blob(let value): value
    case .text(let value): Data(value.utf8)
    default: nil
    }
  }
}

final class ESIResponseCacheDatabase: @unchecked Sendable {
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
      throw ESIResponseCacheError.database(message)
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
      throw ESIResponseCacheError.database(message)
    }
  }

  func run(_ sql: String, _ values: [ESIResponseCacheValue] = []) throws {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw databaseError("step")
    }
  }

  func query(
    _ sql: String,
    _ values: [ESIResponseCacheValue] = []
  ) throws -> [[String: ESIResponseCacheValue]] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    let columns = (0..<sqlite3_column_count(statement)).compactMap { index in
      sqlite3_column_name(statement, index).map { (index, String(cString: $0)) }
    }
    var rows: [[String: ESIResponseCacheValue]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw databaseError("query") }
      var row: [String: ESIResponseCacheValue] = [:]
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
        case SQLITE_BLOB:
          let count = Int(sqlite3_column_bytes(statement, index))
          if let bytes = sqlite3_column_blob(statement, index), count > 0 {
            row[name] = .blob(Data(bytes: bytes, count: count))
          } else {
            row[name] = .blob(Data())
          }
        default:
          row[name] = .null
        }
      }
      rows.append(row)
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK
    else { throw databaseError("prepare") }
    return statement
  }

  private func bind(
    _ values: [ESIResponseCacheValue],
    to statement: OpaquePointer?
  ) throws {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
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
        status = sqlite3_bind_text(statement, index, value, -1, transient)
      case .blob(let value) where value.isEmpty:
        // An empty body is a valid representation (e.g. 204), not NULL.
        status = sqlite3_bind_zeroblob(statement, index, 0)
      case .blob(let value):
        status = value.withUnsafeBytes { bytes in
          sqlite3_bind_blob(
            statement,
            index,
            bytes.baseAddress,
            Int32(bytes.count),
            transient
          )
        }
      }
      guard status == SQLITE_OK else { throw databaseError("bind") }
    }
  }

  private func databaseError(_ operation: String) -> ESIResponseCacheError {
    .database(
      handle.map { "\(operation): \(String(cString: sqlite3_errmsg($0)))" }
        ?? operation
    )
  }
}
