import Foundation

/// Observes every ESI network request without changing it. The wrapped
/// transport receives the identical request, and the caller receives the
/// identical response or error; this type sends nothing itself and never
/// retries. Request limits stay with `ESIClient` and its coordinator.
///
/// Besides load per route family it counts deviations from CCP's ESI
/// guidance: missing `User-Agent` or `X-Compatibility-Date`, a compatibility
/// date in the future, a GET sent again before the `Expires` of its previous
/// response, 420/429 responses and the lowest remaining error and rate-limit
/// budgets. Only cache misses reach a transport, so cache hits are not counted.
public final class MeasuringESITransport: ESIHTTPTransporting,
  @unchecked Sendable
{
  public struct RouteStatistics: Equatable, Sendable {
    public var requests = 0
    public var bytes = 0
    public var success = 0
    public var notModified = 0
    public var clientErrors = 0
    public var serverErrors = 0
    public var failures = 0
    public var earlyRequests = 0

    public init() {}

    fileprivate func subtracting(_ earlier: RouteStatistics) -> RouteStatistics {
      var result = RouteStatistics()
      result.requests = requests - earlier.requests
      result.bytes = bytes - earlier.bytes
      result.success = success - earlier.success
      result.notModified = notModified - earlier.notModified
      result.clientErrors = clientErrors - earlier.clientErrors
      result.serverErrors = serverErrors - earlier.serverErrors
      result.failures = failures - earlier.failures
      result.earlyRequests = earlyRequests - earlier.earlyRequests
      return result
    }
  }

  public struct Snapshot: Equatable, Sendable {
    public var routes: [String: RouteStatistics] = [:]
    public var missingUserAgent = 0
    public var missingCompatibilityDate = 0
    public var futureCompatibilityDate = 0
    public var errorLimited = 0
    public var rateLimited = 0
    /// Lowest `X-ESI-Error-Limit-Remain` seen during this app run.
    public var lowestErrorLimitRemain: Int?
    /// Lowest `X-Ratelimit-Remaining` per `X-Ratelimit-Group` during this run.
    public var lowestRateLimitRemaining: [String: Int] = [:]

    public init() {}

    public var requests: Int { routes.values.reduce(0) { $0 + $1.requests } }
    public var bytes: Int { routes.values.reduce(0) { $0 + $1.bytes } }
    public var notModified: Int {
      routes.values.reduce(0) { $0 + $1.notModified }
    }
    public var clientErrors: Int {
      routes.values.reduce(0) { $0 + $1.clientErrors }
    }
    public var earlyRequests: Int {
      routes.values.reduce(0) { $0 + $1.earlyRequests }
    }

    /// Counters since `earlier`; the lowest budgets stay run-wide values.
    public func subtracting(_ earlier: Snapshot) -> Snapshot {
      var result = self
      result.routes = [:]
      for (route, statistics) in routes {
        let difference = statistics.subtracting(
          earlier.routes[route] ?? RouteStatistics()
        )
        if difference.requests > 0 || difference.failures > 0 {
          result.routes[route] = difference
        }
      }
      result.missingUserAgent = missingUserAgent - earlier.missingUserAgent
      result.missingCompatibilityDate =
        missingCompatibilityDate - earlier.missingCompatibilityDate
      result.futureCompatibilityDate =
        futureCompatibilityDate - earlier.futureCompatibilityDate
      result.errorLimited = errorLimited - earlier.errorLimited
      result.rateLimited = rateLimited - earlier.rateLimited
      return result
    }

    /// One log line: totals, CCP guidance counters and the busiest routes.
    public func summary(topRoutes: Int = 8) -> String {
      let busiest = routes.sorted {
        $0.value.requests == $1.value.requests
          ? $0.key < $1.key : $0.value.requests > $1.value.requests
      }.prefix(topRoutes).map { route, statistics in
        "\(route)=\(statistics.requests)"
          + (statistics.notModified > 0 ? "/304:\(statistics.notModified)" : "")
          + (statistics.earlyRequests > 0
            ? "/early:\(statistics.earlyRequests)" : "")
      }
      let lowestRate = lowestRateLimitRemaining.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
      }.prefix(3).map { "\($0.key):\($0.value)" }
      return [
        "requests=\(requests)",
        "kb=\(bytes / 1_024)",
        "304=\(notModified)",
        "4xx=\(clientErrors)",
        "early=\(earlyRequests)",
        "420=\(errorLimited)",
        "429=\(rateLimited)",
        "noUserAgent=\(missingUserAgent)",
        "noCompatibilityDate=\(missingCompatibilityDate)",
        "futureCompatibilityDate=\(futureCompatibilityDate)",
        "lowestErrorRemain=\(lowestErrorLimitRemain.map(String.init) ?? "-")",
        "lowestRateRemain=[\(lowestRate.joined(separator: ","))]",
        "routes=[\(busiest.joined(separator: ","))]",
      ].joined(separator: " ")
    }
  }

  private static let maximumTrackedExpiries = 50_000

  private let base: any ESIHTTPTransporting
  private let now: @Sendable () -> Date
  private let summaryInterval: TimeInterval?
  private let lock = NSLock()
  private var snapshotValue = Snapshot()
  private var expiresByURL: [String: Date] = [:]
  private var lastSummaryAt: Date?
  private var requestsAtLastSummary = 0
  private static let httpDateFormatter = formatter(
    "EEE, dd MMM yyyy HH:mm:ss zzz"
  )
  private static let dayFormatter = formatter("yyyy-MM-dd")

  /// - Parameter summaryInterval: seconds between automatic log summaries,
  ///   written after a response once the interval has passed; `nil` disables
  ///   them.
  public init(
    base: any ESIHTTPTransporting = URLSessionESITransport(),
    now: @escaping @Sendable () -> Date = { Date() },
    summaryInterval: TimeInterval? = 60
  ) {
    self.base = base
    self.now = now
    self.summaryInterval = summaryInterval
  }

  public func snapshot() -> Snapshot {
    lock.withLock { snapshotValue }
  }

  public func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let route = Self.routeFamily(of: request.url)
    let cacheKey = Self.isGET(request) ? request.url?.absoluteString : nil
    recordRequest(request, route: route, cacheKey: cacheKey)
    do {
      let (data, response) = try await base.data(for: request)
      let summary = recordResponse(
        response,
        bytes: data.count,
        route: route,
        cacheKey: cacheKey
      )
      if let summary {
        PerformanceLog.event("esi.summary", summary)
      }
      return (data, response)
    } catch {
      lock.withLock { snapshotValue.routes[route, default: .init()].failures += 1 }
      throw error
    }
  }

  /// Path with numeric segments replaced by `{id}` and without the query, so
  /// no character, structure or item identity is kept or logged.
  public static func routeFamily(of url: URL?) -> String {
    guard let url else { return "unknown" }
    let segments = url.path(percentEncoded: false)
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { segment in
        !segment.isEmpty && segment.allSatisfy(\.isNumber) ? "{id}" : String(segment)
      }
    let path = segments.joined(separator: "/")
    return path.isEmpty ? "/" : path
  }

  /// ESI changes its date at 11:00 UTC; a later compatibility date is invalid.
  static func latestValidCompatibilityDate(at date: Date) -> String {
    dayFormatter.string(from: date.addingTimeInterval(-11 * 60 * 60))
  }

  private static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }

  private static func isGET(_ request: URLRequest) -> Bool {
    (request.httpMethod ?? "GET").uppercased() == "GET"
  }

  private func recordRequest(
    _ request: URLRequest,
    route: String,
    cacheKey: String?
  ) {
    let current = now()
    let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
    let compatibilityDate =
      request.value(forHTTPHeaderField: "X-Compatibility-Date") ?? ""
    let latestValidDate = Self.latestValidCompatibilityDate(at: current)
    lock.withLock {
      snapshotValue.routes[route, default: .init()].requests += 1
      if userAgent.trimmingCharacters(in: .whitespaces).isEmpty {
        snapshotValue.missingUserAgent += 1
      }
      if compatibilityDate.isEmpty {
        snapshotValue.missingCompatibilityDate += 1
      } else if compatibilityDate > latestValidDate {
        snapshotValue.futureCompatibilityDate += 1
      }
      if let cacheKey, let expires = expiresByURL[cacheKey], current < expires {
        snapshotValue.routes[route, default: .init()].earlyRequests += 1
      }
    }
  }

  private func recordResponse(
    _ response: HTTPURLResponse,
    bytes: Int,
    route: String,
    cacheKey: String?
  ) -> String? {
    let current = now()
    let status = response.statusCode
    let expires = response.value(forHTTPHeaderField: "Expires")
    let errorRemain = response.value(forHTTPHeaderField: "X-ESI-Error-Limit-Remain")
      .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    let rateGroup = response.value(forHTTPHeaderField: "X-Ratelimit-Group")
    let rateRemaining = response.value(forHTTPHeaderField: "X-Ratelimit-Remaining")
      .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    return lock.withLock { () -> String? in
      var statistics = snapshotValue.routes[route, default: .init()]
      statistics.bytes += bytes
      switch status {
      case 304: statistics.notModified += 1
      case 200..<400: statistics.success += 1
      case 400..<500: statistics.clientErrors += 1
      default: statistics.serverErrors += 1
      }
      snapshotValue.routes[route] = statistics
      if status == 420 { snapshotValue.errorLimited += 1 }
      if status == 429 { snapshotValue.rateLimited += 1 }
      if let errorRemain {
        snapshotValue.lowestErrorLimitRemain = min(
          snapshotValue.lowestErrorLimitRemain ?? errorRemain,
          errorRemain
        )
      }
      if let rateGroup, let rateRemaining {
        snapshotValue.lowestRateLimitRemaining[rateGroup] = min(
          snapshotValue.lowestRateLimitRemaining[rateGroup] ?? rateRemaining,
          rateRemaining
        )
      }
      if let cacheKey,
        let expires,
        let expiresAt = Self.httpDateFormatter.date(from: expires)
      {
        expiresByURL[cacheKey] = expiresAt
        if expiresByURL.count > Self.maximumTrackedExpiries {
          expiresByURL = expiresByURL.filter { $0.value > current }
        }
      }
      guard let summaryInterval,
        snapshotValue.requests > requestsAtLastSummary
      else { return nil }
      guard let lastSummaryAt else {
        self.lastSummaryAt = current
        return nil
      }
      guard current.timeIntervalSince(lastSummaryAt) >= summaryInterval else {
        return nil
      }
      self.lastSummaryAt = current
      requestsAtLastSummary = snapshotValue.requests
      return snapshotValue.summary()
    }
  }
}
