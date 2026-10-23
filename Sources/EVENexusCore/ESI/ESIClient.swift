import Foundation

public struct ESIEndpoint: Hashable, Sendable {
  public let path: String
  public var query: [URLQueryItem]
  public var requiresAuthorization: Bool
  public var requiredScope: String?
  /// When set, a 403 or 404 of this GET is remembered for this many seconds
  /// per authorization partition and answered locally instead of asking ESI
  /// again (CCP discourages repeated 4xx).
  public var rememberedFailureDuration: TimeInterval?

  public init(
    path: String,
    query: [URLQueryItem] = [],
    requiresAuthorization: Bool = false,
    requiredScope: String? = nil,
    rememberedFailureDuration: TimeInterval? = nil
  ) {
    self.path = path
    self.query = query
    self.requiresAuthorization = requiresAuthorization
    self.requiredScope = requiredScope
    self.rememberedFailureDuration = rememberedFailureDuration
  }
}

public struct ESIResponse<Value: Sendable>: Sendable {
  public let value: Value
  public let source: SourceIdentity
  public let statusCode: Int
  public let expiresAt: Date?
  public let etag: String?
  public let lastModified: String?
  public let pages: Int?
  public let errorLimitRemain: Int?
  public let errorLimitReset: Int?
  public let rateLimitGroup: String?
  public let rateLimit: String?
  public let rateLimitRemaining: Int?
  public let rateLimitUsed: Int?

  public init(
    value: Value,
    source: SourceIdentity,
    statusCode: Int,
    expiresAt: Date? = nil,
    etag: String? = nil,
    lastModified: String? = nil,
    pages: Int? = nil,
    errorLimitRemain: Int? = nil,
    errorLimitReset: Int? = nil,
    rateLimitGroup: String? = nil,
    rateLimit: String? = nil,
    rateLimitRemaining: Int? = nil,
    rateLimitUsed: Int? = nil
  ) {
    self.value = value
    self.source = source
    self.statusCode = statusCode
    self.expiresAt = expiresAt
    self.etag = etag
    self.lastModified = lastModified
    self.pages = pages
    self.errorLimitRemain = errorLimitRemain
    self.errorLimitReset = errorLimitReset
    self.rateLimitGroup = rateLimitGroup
    self.rateLimit = rateLimit
    self.rateLimitRemaining = rateLimitRemaining
    self.rateLimitUsed = rateLimitUsed
  }
}

public struct ESIResponseCacheUsage: Equatable, Sendable {
  public let entries: Int
  public let bytes: Int
  public let maximumEntries: Int
  public let maximumBytes: Int

  public init(
    entries: Int,
    bytes: Int,
    maximumEntries: Int,
    maximumBytes: Int
  ) {
    self.entries = entries
    self.bytes = bytes
    self.maximumEntries = maximumEntries
    self.maximumBytes = maximumBytes
  }
}

public enum ESIRequestPriority: Int, Comparable, Sendable {
  case automatic = 0
  case standard = 1
  case interactive = 2

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum ESIRequestContext {
  @TaskLocal public static var priority: ESIRequestPriority = .standard

  public static func withPriority<Result>(
    _ priority: ESIRequestPriority,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $priority.withValue(
      priority,
      operation: operation,
      isolation: isolation
    )
  }
}

public struct ESIRequestCoordinatorUsage: Equatable, Sendable {
  public let active: Int
  public let activeAutomatic: Int
  public let queued: Int
  public let maximumConcurrent: Int
  public let maximumAutomaticConcurrent: Int

  public init(
    active: Int,
    activeAutomatic: Int,
    queued: Int,
    maximumConcurrent: Int,
    maximumAutomaticConcurrent: Int
  ) {
    self.active = active
    self.activeAutomatic = activeAutomatic
    self.queued = queued
    self.maximumConcurrent = maximumConcurrent
    self.maximumAutomaticConcurrent = maximumAutomaticConcurrent
  }
}

/// The route family and rate-limit partition of one request. CCP keeps one
/// floating-window bucket per rate-limit group and user: the character for
/// authenticated routes, the source IP for public ones.
public struct ESIRequestRoute: Hashable, Sendable {
  public let family: String
  public let partition: String

  public init(path: String, partition: String) {
    // Identifiers do not change the route, so `/characters/1/assets/` and
    // `/characters/2/assets/` share the family `/characters/{}/assets/`.
    self.family = path.split(separator: "/", omittingEmptySubsequences: false)
      .map { segment in
        !segment.isEmpty && segment.allSatisfy(\.isNumber) ? "{}" : String(segment)
      }
      .joined(separator: "/")
    self.partition = partition
  }
}

/// The limit headers of one ESI response (CCP ESI rate limiting).
public struct ESIRateLimitObservation: Equatable, Sendable {
  public let statusCode: Int
  public let errorLimitRemain: Int?
  public let errorLimitReset: Int?
  public let rateLimitGroup: String?
  public let rateLimit: String?
  public let rateLimitRemaining: Int?
  public let retryAfter: Int?

  public init(
    statusCode: Int,
    errorLimitRemain: Int? = nil,
    errorLimitReset: Int? = nil,
    rateLimitGroup: String? = nil,
    rateLimit: String? = nil,
    rateLimitRemaining: Int? = nil,
    retryAfter: Int? = nil
  ) {
    self.statusCode = statusCode
    self.errorLimitRemain = errorLimitRemain
    self.errorLimitReset = errorLimitReset
    self.rateLimitGroup = rateLimitGroup
    self.rateLimit = rateLimit
    self.rateLimitRemaining = rateLimitRemaining
    self.retryAfter = retryAfter
  }

  public init(response: HTTPURLResponse) {
    func integer(_ name: String) -> Int? {
      response.value(forHTTPHeaderField: name).flatMap {
        Int($0.trimmingCharacters(in: .whitespaces))
      }
    }
    self.init(
      statusCode: response.statusCode,
      errorLimitRemain: integer("X-ESI-Error-Limit-Remain"),
      errorLimitReset: integer("X-ESI-Error-Limit-Reset"),
      rateLimitGroup: response.value(forHTTPHeaderField: "X-Ratelimit-Group"),
      rateLimit: response.value(forHTTPHeaderField: "X-Ratelimit-Limit"),
      rateLimitRemaining: integer("X-Ratelimit-Remaining"),
      retryAfter: integer("Retry-After")
    )
  }
}

/// A floating-window limit such as `150/15m` from `X-Ratelimit-Limit`.
public struct ESIRateLimitWindow: Equatable, Sendable {
  public let maximumTokens: Int
  public let windowSeconds: TimeInterval

  public init?(_ value: String?) {
    guard let parts = value?.split(separator: "/"), parts.count == 2,
      let tokens = Int(parts[0]), tokens > 0,
      let unit = parts[1].last,
      let amount = Double(parts[1].dropLast()), amount > 0
    else { return nil }
    let unitSeconds: TimeInterval
    switch unit {
    case "s": unitSeconds = 1
    case "m": unitSeconds = 60
    case "h": unitSeconds = 3_600
    default: return nil
    }
    maximumTokens = tokens
    windowSeconds = amount * unitSeconds
  }

  /// Below this many tokens a client should "start to slow down".
  public var lowTokenThreshold: Int { max(10, maximumTokens / 10) }

  /// The average time the window needs to return the two tokens a successful
  /// request costs.
  public var pacedRequestInterval: TimeInterval {
    windowSeconds / Double(maximumTokens) * 2
  }
}

/// One cancellation-aware admission queue for every HTTP request made by an
/// `ESIClient`. Endpoint services may keep their narrower domain limits, while
/// this coordinator prevents their overlapping task groups from multiplying
/// the process-wide transport load.
/// Loads `count` independent items with bounded concurrency and hands them to
/// `deliver` strictly in index order. At most `maximumConcurrent` items are in
/// flight or completed but not yet delivered, so one slow item cannot make
/// finished results pile up. The global `ESIRequestCoordinator` still bounds
/// the transports; this only removes the strictly sequential wait.
public enum ESIOrderedLoader {
  public static let defaultMaximumConcurrent = 4

  public static func load<Value: Sendable>(
    count: Int,
    maximumConcurrent: Int = defaultMaximumConcurrent,
    isolation: isolated (any Actor)? = #isolation,
    load: @escaping @Sendable (Int) async throws -> Value,
    deliver: (Int, Value) async throws -> Void
  ) async throws {
    guard count > 0 else { return }
    let window = max(1, maximumConcurrent)
    try await withThrowingTaskGroup(of: (Int, Value).self) { group in
      var nextRequested = 0
      var nextDelivered = 0
      var completed: [Int: Value] = [:]
      while nextRequested < count, nextRequested - nextDelivered < window {
        try Task.checkCancellation()
        let index = nextRequested
        group.addTask { (index, try await load(index)) }
        nextRequested += 1
      }
      while let (index, value) = try await group.next() {
        completed[index] = value
        while let ready = completed.removeValue(forKey: nextDelivered) {
          try await deliver(nextDelivered, ready)
          nextDelivered += 1
        }
        while nextRequested < count, nextRequested - nextDelivered < window {
          try Task.checkCancellation()
          let index = nextRequested
          group.addTask { (index, try await load(index)) }
          nextRequested += 1
        }
      }
    }
  }
}

public actor ESIRequestCoordinator {
  private struct Waiter {
    let id: UUID
    let priority: ESIRequestPriority
    let sequence: UInt64
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct RateLimitBucket {
    var blockedUntil: Date?
    var pacedInterval: TimeInterval?
    var nextPacedStart: Date?
  }

  /// New requests stop while ESI reports this many or fewer remaining errors
  /// in the current error window; at zero it answers every route with 420.
  public static let errorLimitFloor = 20

  private let maximumConcurrent: Int
  private let maximumAutomaticConcurrent: Int
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private var active = 0
  private var activeAutomatic = 0
  private var sequence: UInt64 = 0
  private var waiters: [Waiter] = []
  private var errorLimitBlockedUntil: Date?
  private var groupsByFamily: [String: String] = [:]
  private var buckets: [String: RateLimitBucket] = [:]

  public init(
    maximumConcurrent: Int = 6,
    maximumAutomaticConcurrent: Int = 2,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    let acceptedMaximum = min(32, max(1, maximumConcurrent))
    self.maximumConcurrent = acceptedMaximum
    self.maximumAutomaticConcurrent = min(
      acceptedMaximum,
      max(1, maximumAutomaticConcurrent)
    )
    self.now = now
    self.sleep = sleep
  }

  public func usage() -> ESIRequestCoordinatorUsage {
    ESIRequestCoordinatorUsage(
      active: active,
      activeAutomatic: activeAutomatic,
      queued: waiters.count,
      maximumConcurrent: maximumConcurrent,
      maximumAutomaticConcurrent: maximumAutomaticConcurrent
    )
  }

  public func perform<Result: Sendable>(
    priority: ESIRequestPriority,
    route: ESIRequestRoute? = nil,
    operation: @Sendable () async throws -> Result
  ) async throws -> Result {
    let id = UUID()
    try await awaitLimitClearance(for: route)
    try await acquire(id: id, priority: priority)
    do {
      try Task.checkCancellation()
      let result = try await operation()
      release(priority: priority)
      return result
    } catch {
      release(priority: priority)
      throw error
    }
  }

  /// Applies the limit headers of a response to every later request: the
  /// legacy error limit for all routes, the floating-window bucket for its
  /// rate-limit group and partition.
  public func record(
    _ observation: ESIRateLimitObservation,
    route: ESIRequestRoute?
  ) {
    let current = now()
    if observation.statusCode == 420 {
      blockAllRequests(
        for: observation.retryAfter ?? observation.errorLimitReset ?? 60,
        from: current
      )
    } else if let remain = observation.errorLimitRemain,
      remain <= Self.errorLimitFloor
    {
      blockAllRequests(for: observation.errorLimitReset ?? 60, from: current)
    }
    guard let route else { return }
    if let group = observation.rateLimitGroup, !group.isEmpty {
      groupsByFamily[route.family] = group
    }
    let key = bucketKey(for: route)
    if observation.statusCode == 429 {
      // Some routes answer 429 from deeper limiters without bucket headers;
      // the route family is then paused on its own.
      let resume = current.addingTimeInterval(
        TimeInterval(max(observation.retryAfter ?? 60, 1))
      )
      buckets[key, default: RateLimitBucket()].blockedUntil = max(
        buckets[key]?.blockedUntil ?? resume,
        resume
      )
      return
    }
    guard let remaining = observation.rateLimitRemaining,
      let window = ESIRateLimitWindow(observation.rateLimit)
    else { return }
    if remaining <= window.lowTokenThreshold {
      buckets[key, default: RateLimitBucket()].pacedInterval =
        window.pacedRequestInterval
    } else if buckets[key] != nil {
      buckets[key]?.pacedInterval = nil
      buckets[key]?.nextPacedStart = nil
    }
  }

  private func bucketKey(for route: ESIRequestRoute) -> String {
    let group =
      groupsByFamily[route.family].map { "group:\($0)" }
      ?? "route:\(route.family)"
    return "\(group)|\(route.partition)"
  }

  private func blockAllRequests(for seconds: Int, from current: Date) {
    // One second of margin for clock skew to the ESI window boundary.
    let resume = current.addingTimeInterval(TimeInterval(max(seconds, 0) + 1))
    errorLimitBlockedUntil = max(errorLimitBlockedUntil ?? resume, resume)
  }

  /// Waits without holding a transport permit while the error limit or the
  /// route's bucket is blocked, and spaces requests while a bucket is low.
  private func awaitLimitClearance(for route: ESIRequestRoute?) async throws {
    var hasPacedStart = false
    while true {
      try Task.checkCancellation()
      let current = now()
      var resume = errorLimitBlockedUntil.flatMap { $0 > current ? $0 : nil }
      let key = route.map(bucketKey)
      if let key, let blocked = buckets[key]?.blockedUntil, blocked > current {
        resume = max(resume ?? blocked, blocked)
      }
      if resume == nil, !hasPacedStart, let key,
        let interval = buckets[key]?.pacedInterval
      {
        hasPacedStart = true
        let start = max(buckets[key]?.nextPacedStart ?? current, current)
        buckets[key]?.nextPacedStart = start.addingTimeInterval(interval)
        if start > current { resume = start }
      }
      guard let resume else { return }
      try await sleep(resume.timeIntervalSince(current))
    }
  }

  private func acquire(
    id: UUID,
    priority: ESIRequestPriority
  ) async throws {
    try Task.checkCancellation()
    if canStart(priority) {
      markStarted(priority)
      return
    }
    sequence &+= 1
    let waiterSequence = sequence
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiters.append(
          Waiter(
            id: id,
            priority: priority,
            sequence: waiterSequence,
            continuation: continuation
          )
        )
      }
    } onCancel: {
      Task { await self.cancelWaiter(id: id) }
    }
    do {
      try Task.checkCancellation()
    } catch {
      release(priority: priority)
      throw error
    }
  }

  private func cancelWaiter(id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else {
      return
    }
    let waiter = waiters.remove(at: index)
    waiter.continuation.resume(throwing: CancellationError())
  }

  private func release(priority: ESIRequestPriority) {
    active = max(0, active - 1)
    if priority == .automatic {
      activeAutomatic = max(0, activeAutomatic - 1)
    }
    resumeEligibleWaiters()
  }

  private func resumeEligibleWaiters() {
    while active < maximumConcurrent {
      let eligibleIndices = waiters.indices.filter {
        canStart(waiters[$0].priority)
      }
      guard
        let index = eligibleIndices.min(by: { lhs, rhs in
          let left = waiters[lhs]
          let right = waiters[rhs]
          if left.priority != right.priority {
            return left.priority > right.priority
          }
          return left.sequence < right.sequence
        })
      else { return }
      let waiter = waiters.remove(at: index)
      markStarted(waiter.priority)
      waiter.continuation.resume()
    }
  }

  private func canStart(_ priority: ESIRequestPriority) -> Bool {
    active < maximumConcurrent
      && (priority != .automatic
        || activeAutomatic < maximumAutomaticConcurrent)
  }

  private func markStarted(_ priority: ESIRequestPriority) {
    active += 1
    if priority == .automatic {
      activeAutomatic += 1
    }
  }
}

public enum ESIError: Error, Equatable, Sendable {
  case invalidURL
  case authorizationRequired
  case missingScope(String)
  case forbidden
  case notFound
  case rateLimited(retryAfter: Int?)
  case server(Int)
  case http(Int)
  case responseTooLarge
  case invalidPagination
  case decoding
  case cancelled
}

public protocol ESIHTTPTransporting: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionESITransport: ESIHTTPTransporting, Sendable {
  private let session: URLSession

  public init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 30
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      self.session = URLSession(configuration: configuration)
    }
  }

  public func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ESIError.http(-1)
    }
    return (data, http)
  }
}

/// A page of a paginated resource carried another `Last-Modified` than page
/// 1, so ESI refreshed the resource during the read. CCP requires every page
/// of one read to share the same `Last-Modified`.
public struct ESIPageSnapshotChange: Error, Equatable, Sendable {
  public let pageCount: Int
  /// The newer of the two values, i.e. the snapshot ESI serves now.
  public let currentLastModified: String

  public static func check(
    _ lastModified: String?,
    firstPage: String?,
    pageCount: Int
  ) throws {
    guard let lastModified, let firstPage, lastModified != firstPage else {
      return
    }
    let pageDate = ESIClient.httpDate(lastModified) ?? .distantPast
    let firstDate = ESIClient.httpDate(firstPage) ?? .distantPast
    throw ESIPageSnapshotChange(
      pageCount: pageCount,
      currentLastModified: pageDate >= firstDate ? lastModified : firstPage
    )
  }
}

public actor ESIClient {
  private struct Validator: Sendable {
    let etag: String?
    let lastModified: String?
    let data: Data
    let expiresAt: Date?
    let pages: Int?
    let source: SourceIdentity
    let statusCode: Int
    var lastAccess: UInt64

    init(
      etag: String?,
      lastModified: String?,
      data: Data,
      expiresAt: Date?,
      pages: Int?,
      source: SourceIdentity,
      statusCode: Int,
      lastAccess: UInt64
    ) {
      self.etag = etag
      self.lastModified = lastModified
      self.data = data
      self.expiresAt = expiresAt
      self.pages = pages
      self.source = source
      self.statusCode = statusCode
      self.lastAccess = lastAccess
    }

    init(_ stored: ESIStoredResponse) {
      self.init(
        etag: stored.etag,
        lastModified: stored.lastModified,
        data: stored.data,
        expiresAt: stored.expiresAt,
        pages: stored.pages,
        source: stored.source,
        statusCode: stored.statusCode,
        lastAccess: 0
      )
    }

    var stored: ESIStoredResponse {
      ESIStoredResponse(
        etag: etag,
        lastModified: lastModified,
        data: data,
        expiresAt: expiresAt,
        pages: pages,
        statusCode: statusCode,
        source: source
      )
    }
  }

  private let transport: any ESIHTTPTransporting
  private let decoder: JSONDecoder
  private let maximumResponseBytes: Int
  private let maximumPageCount: Int
  private let maximumCachedResponses: Int
  private let maximumCachedBytes: Int
  private let requestCoordinator: ESIRequestCoordinator
  private let userAgent: String
  /// Durable second cache level; `nil` keeps responses in memory only.
  private let responseStore: (any ESIResponseStoring)?
  private let now: @Sendable () -> Date
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private var validators: [String: Validator] = [:]
  private var rememberedFailures: [String: ESIRememberedFailure] = [:]
  private var cachedResponseBytes = 0
  private var cacheAccessSequence: UInt64 = 0

  public init(
    transport: any ESIHTTPTransporting = URLSessionESITransport(),
    maximumResponseBytes: Int = 32 * 1_024 * 1_024,
    maximumPageCount: Int = 1_000,
    maximumCachedResponses: Int = 512,
    maximumCachedBytes: Int = 64 * 1_024 * 1_024,
    maximumConcurrentRequests: Int = 6,
    maximumAutomaticConcurrentRequests: Int = 2,
    userAgent: String = CCPUserAgentConfiguration.genericValue,
    responseStore: (any ESIResponseStoring)? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.transport = transport
    self.maximumResponseBytes = max(1_024, maximumResponseBytes)
    self.maximumPageCount = min(10_000, max(1, maximumPageCount))
    self.maximumCachedResponses = max(0, maximumCachedResponses)
    self.maximumCachedBytes = max(0, maximumCachedBytes)
    self.requestCoordinator = ESIRequestCoordinator(
      maximumConcurrent: maximumConcurrentRequests,
      maximumAutomaticConcurrent: maximumAutomaticConcurrentRequests,
      now: now,
      sleep: sleep
    )
    self.userAgent = userAgent
    self.responseStore = responseStore
    self.now = now
    self.sleep = sleep
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
  }

  public func cachedResponseUsage() -> ESIResponseCacheUsage {
    ESIResponseCacheUsage(
      entries: validators.count,
      bytes: cachedResponseBytes,
      maximumEntries: maximumCachedResponses,
      maximumBytes: maximumCachedBytes
    )
  }

  public func requestCoordinatorUsage() async -> ESIRequestCoordinatorUsage {
    await requestCoordinator.usage()
  }

  /// Retains the most recently used cached response bodies up to the supplied
  /// byte target. Removing a body also removes its validator so a later 304 can
  /// never be decoded against missing data. Only the in-memory level is
  /// trimmed; the durable store keeps its copies.
  @discardableResult
  public func trimCachedResponses(
    toMaximumBytes requestedMaximumBytes: Int
  ) -> ESIResponseCacheUsage {
    let target = min(max(0, requestedMaximumBytes), maximumCachedBytes)
    while cachedResponseBytes > target {
      guard
        let oldestKey = validators.min(by: {
          $0.value.lastAccess < $1.value.lastAccess
        })?.key
      else { break }
      removeCachedResponse(forKey: oldestKey)
    }
    return cachedResponseUsage()
  }

  /// Removes one character's responses from memory and from the durable
  /// store, e.g. when the character is disconnected.
  public func removeCachedResponses(forCharacterID characterID: Int64) async {
    let prefix = "character:\(characterID)|"
    removeCachedResponses { $0.hasPrefix(prefix) }
    rememberedFailures = rememberedFailures.filter { !$0.key.hasPrefix(prefix) }
    await responseStore?.removeResponses(inPartition: "character:\(characterID)")
  }

  /// Drops the in-memory level only (memory pressure); the durable store keeps
  /// its copies so later requests within `Expires` stay local.
  public func removeAllCachedResponses() {
    validators.removeAll(keepingCapacity: false)
    cachedResponseBytes = 0
  }

  /// Releases public cached bodies for one endpoint family after a bulk
  /// consumer has produced its durable or compact projection. Other public and
  /// all character-partitioned validators remain available.
  /// `sparingQueryItemNamed` keeps responses whose query has that item, e.g.
  /// per-type quotes (`type_id`) below a regional order book whose own cache
  /// window is still running.
  public func removeCachedPublicResponses(
    pathPrefix: String,
    sparingQueryItemNamed sparedName: String? = nil
  ) async {
    guard pathPrefix.hasPrefix("/"), !pathPrefix.contains("://") else { return }
    let prefix = "public|https://esi.evetech.net\(pathPrefix)"
    let matches: @Sendable (String) -> Bool = { key in
      guard key.hasPrefix(prefix) else { return false }
      guard let sparedName else { return true }
      let items =
        URLComponents(string: String(key.dropFirst("public|".count)))?
        .queryItems ?? []
      return !items.contains { $0.name == sparedName }
    }
    removeCachedResponses(where: matches)
    await responseStore?.removeResponses(withKeyPrefix: prefix, where: matches)
  }

  /// Bulk reads that are consumed once and released after their durable or
  /// compact projection stay in memory only (owner decision 2026-10-23): the
  /// public catalog-wide regional order book (no `type_id`) and public
  /// contracts. Everything else, including structure order books, is kept
  /// durably.
  static func persistsDurably(
    path: String,
    query: [URLQueryItem],
    partition: String
  ) -> Bool {
    if path.hasPrefix("/contracts/public/") { return false }
    let segments = path.split(separator: "/")
    let isRegionalOrderBook =
      segments.count == 3 && segments[0] == "markets"
      && segments[1].allSatisfy(\.isNumber) && segments[2] == "orders"
    if partition == "public", isRegionalOrderBook,
      !query.contains(where: { $0.name == "type_id" })
    {
      return false
    }
    return true
  }

  /// - Parameter revalidatingRememberedFailure: asks ESI even when a 403/404
  ///   of this endpoint is still remembered, e.g. for an explicit user search;
  ///   the new outcome replaces the remembered one.
  public func get<Value: Decodable & Sendable>(
    _ type: Value.Type,
    endpoint: ESIEndpoint,
    lease: AccessTokenLease? = nil,
    revalidatingRememberedFailure: Bool = false
  ) async throws -> ESIResponse<Value> {
    try Task.checkCancellation()
    if endpoint.requiresAuthorization && lease == nil {
      throw ESIError.authorizationRequired
    }
    if let requiredScope = endpoint.requiredScope,
      let lease,
      !lease.scopes.contains(requiredScope)
    {
      throw ESIError.missingScope(requiredScope)
    }
    let url = try makeURL(endpoint)
    // Private ESI validators and cached bodies are character-bound. Reusing a
    // 304 response across two access-token identities could otherwise expose
    // data that the second character is not allowed to see.
    let authorizationPartition =
      lease.map { "character:\($0.characterID)" } ?? "public"
    let cacheKey = "\(authorizationPartition)|\(url.absoluteString)"
    let durableStore =
      Self.persistsDurably(
        path: endpoint.path,
        query: endpoint.query,
        partition: authorizationPartition
      ) ? responseStore : nil
    let failureDuration = endpoint.rememberedFailureDuration
    if failureDuration != nil, !revalidatingRememberedFailure,
      let failure = await rememberedFailure(
        forKey: cacheKey,
        store: durableStore
      )
    {
      throw failure.statusCode == 403 ? ESIError.forbidden : ESIError.notFound
    }
    var cachedAtRequest = cachedValidator(for: cacheKey)
    var cachedFromDurableStore = false
    if cachedAtRequest == nil,
      let durableStore,
      let stored = await durableStore.response(forKey: cacheKey)
    {
      let restored = Validator(stored)
      storeCachedResponse(restored, forKey: cacheKey)
      cachedAtRequest = cachedValidator(for: cacheKey) ?? restored
      cachedFromDurableStore = true
    }
    if let cached = cachedAtRequest,
      let expiresAt = cached.expiresAt,
      expiresAt > now()
    {
      if let decoded = try? decoder.decode(Value.self, from: cached.data) {
        return ESIResponse(
          value: decoded,
          source: cached.source,
          statusCode: cached.statusCode,
          expiresAt: expiresAt,
          etag: cached.etag,
          lastModified: cached.lastModified,
          pages: cached.pages,
          errorLimitRemain: nil
        )
      }
      removeCachedResponse(forKey: cacheKey)
      // A durable body written by an older app build may no longer decode;
      // drop it and load the current representation instead of failing.
      guard cachedFromDurableStore else { throw ESIError.decoding }
      await durableStore?.removeResponse(forKey: cacheKey)
      cachedAtRequest = nil
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue(
      EVEConstants.esiCompatibilityDate,
      forHTTPHeaderField: "X-Compatibility-Date"
    )
    request.setValue("tranquility", forHTTPHeaderField: "X-Tenant")
    request.setValue(
      userAgent,
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let lease {
      request.setValue(
        "Bearer \(lease.accessToken)",
        forHTTPHeaderField: "Authorization"
      )
    }
    if let cached = cachedAtRequest {
      if let etag = cached.etag {
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
      }
      if let modified = cached.lastModified {
        request.setValue(
          modified,
          forHTTPHeaderField: "If-Modified-Since"
        )
      }
    }

    let transport = transport
    let transportRequest = request
    let requestPriority = ESIRequestContext.priority
    let route = ESIRequestRoute(
      path: endpoint.path,
      partition: authorizationPartition
    )
    let validatorAtRequest = cachedAtRequest
    var attempt = 0
    while true {
      do {
        let (data, response) = try await requestCoordinator.perform(
          priority: requestPriority,
          route: route
        ) {
          try await transport.data(for: transportRequest)
        }
        await requestCoordinator.record(
          ESIRateLimitObservation(response: response),
          route: route
        )
        try validateSize(data, response: response)
        let usableData: Data
        if response.statusCode == 304,
          let cached = validatorAtRequest
        {
          usableData = cached.data
        } else {
          try validate(response)
          usableData = data
        }
        guard usableData.count <= maximumResponseBytes else {
          throw ESIError.responseTooLarge
        }
        let decoded: Value
        do {
          let decodingData =
            response.statusCode == 204 && usableData.isEmpty
            ? Data("[]".utf8) : usableData
          decoded = try decoder.decode(Value.self, from: decodingData)
        } catch {
          if response.statusCode == 304, cachedFromDurableStore {
            removeCachedResponse(forKey: cacheKey)
            await durableStore?.removeResponse(forKey: cacheKey)
          }
          throw ESIError.decoding
        }
        let expires =
          Self.httpDate(
            response.value(forHTTPHeaderField: "Expires")
          ) ?? (response.statusCode == 304 ? validatorAtRequest?.expiresAt : nil)
        let etag =
          response.value(forHTTPHeaderField: "ETag")
          ?? (response.statusCode == 304 ? validatorAtRequest?.etag : nil)
        let modified =
          response.value(forHTTPHeaderField: "Last-Modified")
          ?? (response.statusCode == 304
            ? validatorAtRequest?.lastModified : nil)
        let pages = try pageCount(response)
        // A conditional 304 commonly omits representation headers such as
        // X-Pages. The cached body and its page count belong to the same
        // validated representation, so keep both together in the response
        // envelope. Otherwise a revalidated multi-page resource would look
        // like a one-page resource to its domain consumer.
        let effectivePages =
          pages ?? (response.statusCode == 304 ? validatorAtRequest?.pages : nil)
        let source = SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate,
          capturedAt: now()
        )
        if etag != nil || modified != nil || expires != nil {
          let validator = Validator(
            etag: etag,
            lastModified: modified,
            data: usableData,
            expiresAt: expires,
            pages: effectivePages,
            source: source,
            statusCode: response.statusCode,
            lastAccess: 0
          )
          storeCachedResponse(validator, forKey: cacheKey)
          await durableStore?.store(validator.stored, forKey: cacheKey)
        } else {
          removeCachedResponse(forKey: cacheKey)
          await durableStore?.removeResponse(forKey: cacheKey)
        }
        if failureDuration != nil,
          rememberedFailures.removeValue(forKey: cacheKey) != nil
            || revalidatingRememberedFailure
        {
          await durableStore?.forgetFailure(forKey: cacheKey)
        }
        return ESIResponse(
          value: decoded,
          source: source,
          statusCode: response.statusCode,
          expiresAt: expires,
          etag: etag,
          lastModified: modified,
          pages: effectivePages,
          errorLimitRemain: Int(
            response.value(
              forHTTPHeaderField: "X-ESI-Error-Limit-Remain"
            ) ?? ""
          ),
          errorLimitReset: Int(
            response.value(
              forHTTPHeaderField: "X-ESI-Error-Limit-Reset"
            ) ?? ""
          ),
          rateLimitGroup: response.value(
            forHTTPHeaderField: "X-Ratelimit-Group"
          ),
          rateLimit: response.value(forHTTPHeaderField: "X-Ratelimit-Limit"),
          rateLimitRemaining: Int(
            response.value(
              forHTTPHeaderField: "X-Ratelimit-Remaining"
            ) ?? ""
          ),
          rateLimitUsed: Int(
            response.value(forHTTPHeaderField: "X-Ratelimit-Used") ?? ""
          )
        )
      } catch is CancellationError {
        throw ESIError.cancelled
      } catch let error as ESIError {
        if case .server = error, attempt < 2 {
          attempt += 1
          try await Task.sleep(
            for: .milliseconds(250 * attempt)
          )
          continue
        }
        if case .rateLimited = error, attempt < 2 {
          // The coordinator recorded the 420/429 and holds this and every
          // other affected request until ESI's announced reset.
          attempt += 1
          continue
        }
        if let failureDuration {
          let statusCode: Int? =
            switch error {
            case .forbidden: 403
            case .notFound: 404
            default: nil
            }
          if let statusCode {
            let failure = ESIRememberedFailure(
              statusCode: statusCode,
              until: now().addingTimeInterval(failureDuration)
            )
            rememberedFailures[cacheKey] = failure
            await durableStore?.rememberFailure(failure, forKey: cacheKey)
          }
        }
        throw error
      }
    }
  }

  private func rememberedFailure(
    forKey key: String,
    store: (any ESIResponseStoring)?
  ) async -> ESIRememberedFailure? {
    if let failure = rememberedFailures[key] {
      if failure.until > now() { return failure }
      rememberedFailures.removeValue(forKey: key)
      return nil
    }
    guard let failure = await store?.rememberedFailure(forKey: key),
      failure.until > now()
    else { return nil }
    rememberedFailures[key] = failure
    return failure
  }

  private func cachedValidator(for key: String) -> Validator? {
    guard var cached = validators[key] else { return nil }
    cacheAccessSequence &+= 1
    cached.lastAccess = cacheAccessSequence
    validators[key] = cached
    return cached
  }

  private func storeCachedResponse(
    _ value: Validator,
    forKey key: String
  ) {
    guard maximumCachedResponses > 0,
      maximumCachedBytes > 0,
      value.data.count <= maximumCachedBytes
    else {
      removeCachedResponse(forKey: key)
      return
    }
    removeCachedResponse(forKey: key)
    var accepted = value
    cacheAccessSequence &+= 1
    accepted.lastAccess = cacheAccessSequence
    validators[key] = accepted
    cachedResponseBytes += accepted.data.count
    evictCachedResponsesIfNeeded()
  }

  private func evictCachedResponsesIfNeeded() {
    while validators.count > maximumCachedResponses
      || cachedResponseBytes > maximumCachedBytes
    {
      guard
        let oldestKey = validators.min(by: {
          $0.value.lastAccess < $1.value.lastAccess
        })?.key
      else { return }
      removeCachedResponse(forKey: oldestKey)
    }
  }

  private func removeCachedResponse(forKey key: String) {
    guard let removed = validators.removeValue(forKey: key) else { return }
    cachedResponseBytes = max(0, cachedResponseBytes - removed.data.count)
  }

  private func removeCachedResponses(
    where shouldRemove: (String) -> Bool
  ) {
    let keys = validators.keys.filter(shouldRemove)
    for key in keys {
      removeCachedResponse(forKey: key)
    }
  }

  public func post<Body: Encodable & Sendable, Value: Decodable & Sendable>(
    _ type: Value.Type,
    endpoint: ESIEndpoint,
    body: Body,
    lease: AccessTokenLease? = nil
  ) async throws -> ESIResponse<Value> {
    try Task.checkCancellation()
    if endpoint.requiresAuthorization && lease == nil {
      throw ESIError.authorizationRequired
    }
    if let requiredScope = endpoint.requiredScope,
      let lease,
      !lease.scopes.contains(requiredScope)
    {
      throw ESIError.missingScope(requiredScope)
    }
    let url = try makeURL(endpoint)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(body)
    request.timeoutInterval = 30
    request.setValue(
      EVEConstants.esiCompatibilityDate,
      forHTTPHeaderField: "X-Compatibility-Date"
    )
    request.setValue("tranquility", forHTTPHeaderField: "X-Tenant")
    request.setValue(
      userAgent,
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "application/json",
      forHTTPHeaderField: "Content-Type"
    )
    if let lease {
      request.setValue(
        "Bearer \(lease.accessToken)",
        forHTTPHeaderField: "Authorization"
      )
    }

    let transport = transport
    let transportRequest = request
    let requestPriority = ESIRequestContext.priority
    let route = ESIRequestRoute(
      path: endpoint.path,
      partition: lease.map { "character:\($0.characterID)" } ?? "public"
    )
    do {
      let (data, response) = try await requestCoordinator.perform(
        priority: requestPriority,
        route: route
      ) {
        try await transport.data(for: transportRequest)
      }
      await requestCoordinator.record(
        ESIRateLimitObservation(response: response),
        route: route
      )
      try validateSize(data, response: response)
      try validate(response)
      let decoded: Value
      do {
        decoded = try decoder.decode(Value.self, from: data)
      } catch {
        throw ESIError.decoding
      }
      return ESIResponse(
        value: decoded,
        source: SourceIdentity(
          provider: "ESI",
          version: EVEConstants.esiCompatibilityDate
        ),
        statusCode: response.statusCode,
        expiresAt: Self.httpDate(
          response.value(forHTTPHeaderField: "Expires")
        ),
        etag: response.value(forHTTPHeaderField: "ETag"),
        lastModified: response.value(
          forHTTPHeaderField: "Last-Modified"
        ),
        pages: nil,
        errorLimitRemain: Int(
          response.value(
            forHTTPHeaderField: "X-ESI-Error-Limit-Remain"
          ) ?? ""
        ),
        errorLimitReset: Int(
          response.value(
            forHTTPHeaderField: "X-ESI-Error-Limit-Reset"
          ) ?? ""
        ),
        rateLimitGroup: response.value(
          forHTTPHeaderField: "X-Ratelimit-Group"
        ),
        rateLimit: response.value(forHTTPHeaderField: "X-Ratelimit-Limit"),
        rateLimitRemaining: Int(
          response.value(
            forHTTPHeaderField: "X-Ratelimit-Remaining"
          ) ?? ""
        ),
        rateLimitUsed: Int(
          response.value(forHTTPHeaderField: "X-Ratelimit-Used") ?? ""
        )
      )
    } catch is CancellationError {
      throw ESIError.cancelled
    }
  }

  /// `endpoint` with its `page` query item set to `page`.
  public static func pageEndpoint(
    _ endpoint: ESIEndpoint,
    page: Int
  ) -> ESIEndpoint {
    var pageEndpoint = endpoint
    pageEndpoint.query.removeAll { $0.name == "page" }
    pageEndpoint.query.append(URLQueryItem(name: "page", value: String(page)))
    return pageEndpoint
  }

  /// Loads page 1 of a paginated resource. When its cached representation
  /// expires within a few seconds, waits for ESI's refresh first so the
  /// following pages come from the same snapshot (CCP X-Pages guidance).
  public func firstPage<Element: Decodable & Sendable>(
    _ type: [Element].Type,
    endpoint: ESIEndpoint,
    lease: AccessTokenLease? = nil
  ) async throws -> ESIResponse<[Element]> {
    let firstEndpoint = Self.pageEndpoint(endpoint, page: 1)
    let first = try await get([Element].self, endpoint: firstEndpoint, lease: lease)
    guard (first.pages ?? 1) > 1,
      let remaining = first.expiresAt?.timeIntervalSince(now()),
      remaining > 0, remaining <= Self.imminentPageRefresh
    else { return first }
    try await sleep(remaining + 1)
    return try await get([Element].self, endpoint: firstEndpoint, lease: lease)
  }

  /// Seconds before expiry within which a multi-page read waits for the
  /// refresh instead of straddling it.
  static let imminentPageRefresh: TimeInterval = 5

  /// Drops cached pages of `endpoint` that belong to another snapshot than
  /// `lastModified`. ESI has already refreshed them, so a re-read fetches
  /// only those pages again and reuses the current ones.
  public func removeCachedPages(
    of endpoint: ESIEndpoint,
    pageCount: Int,
    lease: AccessTokenLease? = nil,
    exceptLastModified lastModified: String
  ) async {
    let partition = lease.map { "character:\($0.characterID)" } ?? "public"
    var keys: [String] = []
    for page in 1...max(1, pageCount) {
      guard let url = try? makeURL(Self.pageEndpoint(endpoint, page: page))
      else { continue }
      let key = "\(partition)|\(url.absoluteString)"
      keys.append(key)
      if let cached = validators[key], cached.lastModified != lastModified {
        removeCachedResponse(forKey: key)
      }
    }
    await responseStore?.removeResponses(
      forKeys: keys,
      exceptLastModified: lastModified
    )
  }

  public func getAllPages<Element: Decodable & Sendable>(
    _ type: [Element].Type,
    endpoint: ESIEndpoint,
    lease: AccessTokenLease? = nil
  ) async throws -> ESIResponse<[Element]> {
    do {
      return try await readAllPages(type, endpoint: endpoint, lease: lease)
    } catch let change as ESIPageSnapshotChange {
      // ESI refreshed the resource during the read. Re-read once; the pages
      // that already belong to the new snapshot come from the cache.
      await removeCachedPages(
        of: endpoint,
        pageCount: change.pageCount,
        lease: lease,
        exceptLastModified: change.currentLastModified
      )
      do {
        return try await readAllPages(type, endpoint: endpoint, lease: lease)
      } catch is ESIPageSnapshotChange {
        throw ESIError.invalidPagination
      }
    }
  }

  private func readAllPages<Element: Decodable & Sendable>(
    _ type: [Element].Type,
    endpoint: ESIEndpoint,
    lease: AccessTokenLease?
  ) async throws -> ESIResponse<[Element]> {
    let first = try await firstPage([Element].self, endpoint: endpoint, lease: lease)
    let pageCount = max(first.pages ?? 1, 1)
    if pageCount == 1 { return first }

    var all = first.value
    // Pages 2…n load concurrently but are appended in page order.
    try await ESIOrderedLoader.load(
      count: pageCount - 1,
      load: { index in
        try await self.get(
          [Element].self,
          endpoint: Self.pageEndpoint(endpoint, page: index + 2),
          lease: lease
        )
      },
      deliver: { _, response in
        if let reportedPages = response.pages,
          reportedPages != pageCount
        {
          throw ESIError.invalidPagination
        }
        try ESIPageSnapshotChange.check(
          response.lastModified,
          firstPage: first.lastModified,
          pageCount: pageCount
        )
        all.append(contentsOf: response.value)
      }
    )
    return ESIResponse(
      value: all,
      source: first.source,
      statusCode: first.statusCode,
      expiresAt: first.expiresAt,
      etag: first.etag,
      lastModified: first.lastModified,
      pages: pageCount,
      errorLimitRemain: first.errorLimitRemain,
      errorLimitReset: first.errorLimitReset,
      rateLimitGroup: first.rateLimitGroup,
      rateLimit: first.rateLimit,
      rateLimitRemaining: first.rateLimitRemaining,
      rateLimitUsed: first.rateLimitUsed
    )
  }

  private func validate(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200..<300:
      return
    case 403:
      throw ESIError.forbidden
    case 404:
      throw ESIError.notFound
    case 420, 429:
      throw ESIError.rateLimited(
        retryAfter: Int(
          response.value(forHTTPHeaderField: "Retry-After") ?? ""
        )
          ?? Int(
            response.value(
              forHTTPHeaderField: "X-ESI-Error-Limit-Reset"
            ) ?? ""
          )
      )
    case 500...599:
      throw ESIError.server(response.statusCode)
    default:
      throw ESIError.http(response.statusCode)
    }
  }

  private func makeURL(_ endpoint: ESIEndpoint) throws -> URL {
    guard endpoint.path.hasPrefix("/"),
      endpoint.path.utf8.count <= 2_048,
      !endpoint.path.contains("://"),
      !endpoint.path.contains("\\"),
      endpoint.path.unicodeScalars.allSatisfy({
        $0.value >= 0x20 && $0.value != 0x7f
      }),
      endpoint.query.count <= 50,
      endpoint.query.allSatisfy({
        $0.name.utf8.count <= 256
          && ($0.value?.utf8.count ?? 0) <= 4_096
      }),
      var components = URLComponents(
        string: "https://esi.evetech.net\(endpoint.path)"
      )
    else { throw ESIError.invalidURL }
    components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
    guard let url = components.url,
      url.scheme == "https",
      url.host == "esi.evetech.net",
      url.user == nil,
      url.password == nil,
      url.fragment == nil
    else { throw ESIError.invalidURL }
    return url
  }

  private func validateSize(
    _ data: Data,
    response: HTTPURLResponse
  ) throws {
    if let rawLength = response.value(
      forHTTPHeaderField: "Content-Length"
    ) {
      guard let length = Int64(rawLength),
        length >= 0,
        length <= Int64(maximumResponseBytes)
      else {
        throw ESIError.responseTooLarge
      }
    }
    guard data.count <= maximumResponseBytes else {
      throw ESIError.responseTooLarge
    }
  }

  private func pageCount(_ response: HTTPURLResponse) throws -> Int? {
    guard let raw = response.value(forHTTPHeaderField: "X-Pages") else {
      return nil
    }
    guard let count = Int(raw),
      (1...maximumPageCount).contains(count)
    else {
      throw ESIError.invalidPagination
    }
    return count
  }

  static func httpDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }
}
