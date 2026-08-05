import Foundation

public enum EVEOnlineComponentStatus: String, Codable, Equatable, Sendable {
  case operational
  case degradedPerformance = "degraded_performance"
  case partialOutage = "partial_outage"
  case majorOutage = "major_outage"
  case underMaintenance = "under_maintenance"
  case unknown

  public var isAffected: Bool {
    switch self {
    case .operational, .unknown:
      false
    case .degradedPerformance, .partialOutage, .majorOutage, .underMaintenance:
      true
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = Self(rawValue: rawValue) ?? .unknown
  }
}

public struct EVEOnlineServiceStatusSnapshot: Codable, Equatable, Sendable {
  public let fetchedAt: Date
  public let pageUpdatedAt: Date?
  public let gameServer: EVEOnlineComponentStatus?
  public let login: EVEOnlineComponentStatus?
  public let esi: EVEOnlineComponentStatus?

  public init(
    fetchedAt: Date,
    pageUpdatedAt: Date?,
    gameServer: EVEOnlineComponentStatus?,
    login: EVEOnlineComponentStatus?,
    esi: EVEOnlineComponentStatus?
  ) {
    self.fetchedAt = fetchedAt
    self.pageUpdatedAt = pageUpdatedAt
    self.gameServer = gameServer
    self.login = login
    self.esi = esi
  }

  public var isGameServerUnderMaintenance: Bool {
    gameServer == .underMaintenance
  }

  public var hasLoginIssue: Bool {
    login?.isAffected == true
  }

  public var hasESIIssue: Bool {
    esi?.isAffected == true
  }

  public var hasGameServerIssue: Bool {
    gameServer?.isAffected == true
  }
}

public enum EVEOnlineDailyDowntime {
  /// CCP starts the daily Tranquility restart at 11:00 UTC. The official
  /// status page extends the notice beyond this fallback window when needed.
  public static func isExpected(at date: Date) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = calendar.dateComponents([.hour, .minute], from: date)
    guard let hour = components.hour, let minute = components.minute else {
      return false
    }
    return hour == 11 && minute < 20
  }
}

public enum EVEOnlineStatusError: Error, Equatable, Sendable {
  case invalidResponse
  case responseTooLarge
  case http(Int)
  case decoding
}

public protocol EVEOnlineStatusTransporting: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionEVEOnlineStatusTransport:
  EVEOnlineStatusTransporting, Sendable
{
  private let session: URLSession

  public init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 10
      configuration.timeoutIntervalForResource = 10
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
      throw EVEOnlineStatusError.invalidResponse
    }
    return (data, http)
  }
}

public struct EVEOnlineStatusClient: Sendable {
  private struct StatusPage: Decodable {
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
      case updatedAt = "updated_at"
    }
  }

  private struct Component: Decodable {
    let name: String
    let status: EVEOnlineComponentStatus
  }

  private struct Summary: Decodable {
    let page: StatusPage
    let components: [Component]
  }

  private static let endpoint = URL(
    string: "https://status.eveonline.com/api/v2/summary.json"
  )!
  private static let maximumResponseBytes = 1 * 1_024 * 1_024

  private let transport: any EVEOnlineStatusTransporting
  private let now: @Sendable () -> Date

  public init(
    transport: any EVEOnlineStatusTransporting =
      URLSessionEVEOnlineStatusTransport(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.transport = transport
    self.now = now
  }

  public func fetch() async throws -> EVEOnlineServiceStatusSnapshot {
    var request = URLRequest(url: Self.endpoint)
    request.timeoutInterval = 10
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      CCPUserAgentConfiguration.genericValue,
      forHTTPHeaderField: "User-Agent"
    )
    let (data, response) = try await transport.data(for: request)
    guard response.url?.scheme == "https",
      response.url?.host == Self.endpoint.host
    else {
      throw EVEOnlineStatusError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw EVEOnlineStatusError.http(response.statusCode)
    }
    if let rawLength = response.value(forHTTPHeaderField: "Content-Length") {
      guard let length = Int64(rawLength),
        length >= 0,
        length <= Int64(Self.maximumResponseBytes)
      else {
        throw EVEOnlineStatusError.responseTooLarge
      }
    }
    guard data.count <= Self.maximumResponseBytes else {
      throw EVEOnlineStatusError.responseTooLarge
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let summary: Summary
    do {
      summary = try decoder.decode(Summary.self, from: data)
    } catch {
      throw EVEOnlineStatusError.decoding
    }
    let components = Dictionary(
      summary.components.map { ($0.name.lowercased(), $0.status) },
      uniquingKeysWith: { _, latest in latest }
    )
    return EVEOnlineServiceStatusSnapshot(
      fetchedAt: now(),
      pageUpdatedAt: summary.page.updatedAt,
      gameServer: components["game server"],
      login: components["login"],
      esi: components["eve swagger interface (esi)"]
    )
  }
}
