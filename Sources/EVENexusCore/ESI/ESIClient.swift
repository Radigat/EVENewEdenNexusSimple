import Foundation

public struct ESIEndpoint: Hashable, Sendable {
  public let path: String
  public var query: [URLQueryItem]
  public var requiresAuthorization: Bool
  public var requiredScope: String?

  public init(
    path: String,
    query: [URLQueryItem] = [],
    requiresAuthorization: Bool = false,
    requiredScope: String? = nil
  ) {
    self.path = path
    self.query = query
    self.requiresAuthorization = requiresAuthorization
    self.requiredScope = requiredScope
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

public actor ESIClient {
  private struct Validator: Sendable {
    let etag: String?
    let lastModified: String?
    let data: Data
    let expiresAt: Date?
  }

  private let transport: any ESIHTTPTransporting
  private let decoder: JSONDecoder
  private let maximumResponseBytes: Int
  private let maximumPageCount: Int
  private var validators: [String: Validator] = [:]

  public init(
    transport: any ESIHTTPTransporting = URLSessionESITransport(),
    maximumResponseBytes: Int = 32 * 1_024 * 1_024,
    maximumPageCount: Int = 1_000
  ) {
    self.transport = transport
    self.maximumResponseBytes = max(1_024, maximumResponseBytes)
    self.maximumPageCount = min(10_000, max(1, maximumPageCount))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder
  }

  public func get<Value: Decodable & Sendable>(
    _ type: Value.Type,
    endpoint: ESIEndpoint,
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
    // Private ESI validators and cached bodies are character-bound. Reusing a
    // 304 response across two access-token identities could otherwise expose
    // data that the second character is not allowed to see.
    let authorizationPartition =
      lease.map { "character:\($0.characterID)" } ?? "public"
    let cacheKey = "\(authorizationPartition)|\(url.absoluteString)"
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue(
      EVEConstants.esiCompatibilityDate,
      forHTTPHeaderField: "X-Compatibility-Date"
    )
    request.setValue("tranquility", forHTTPHeaderField: "X-Tenant")
    request.setValue(
      "EVE-Nexus-Simple/1.0 local-contact",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let lease {
      request.setValue(
        "Bearer \(lease.accessToken)",
        forHTTPHeaderField: "Authorization"
      )
    }
    if let cached = validators[cacheKey] {
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

    var attempt = 0
    while true {
      do {
        let (data, response) = try await transport.data(for: request)
        try validateSize(data, response: response)
        let usableData: Data
        if response.statusCode == 304,
          let cached = validators[cacheKey]
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
          decoded = try decoder.decode(Value.self, from: usableData)
        } catch {
          throw ESIError.decoding
        }
        let expires = Self.httpDate(
          response.value(forHTTPHeaderField: "Expires")
        )
        let etag = response.value(forHTTPHeaderField: "ETag")
        let modified = response.value(
          forHTTPHeaderField: "Last-Modified"
        )
        let pages = try pageCount(response)
        validators[cacheKey] = Validator(
          etag: etag,
          lastModified: modified,
          data: usableData,
          expiresAt: expires
        )
        return ESIResponse(
          value: decoded,
          source: SourceIdentity(
            provider: "ESI",
            version: EVEConstants.esiCompatibilityDate
          ),
          statusCode: response.statusCode,
          expiresAt: expires,
          etag: etag,
          lastModified: modified,
          pages: pages,
          errorLimitRemain: Int(
            response.value(
              forHTTPHeaderField: "X-ESI-Error-Limit-Remain"
            ) ?? ""
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
        if case .rateLimited(let retryAfter) = error,
          attempt < 2
        {
          attempt += 1
          try await Task.sleep(
            for: .seconds(min(retryAfter ?? 1, 10))
          )
          continue
        }
        throw error
      }
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
      "EVE-Nexus-Simple/1.0 local-contact",
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

    do {
      let (data, response) = try await transport.data(for: request)
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
        )
      )
    } catch is CancellationError {
      throw ESIError.cancelled
    }
  }

  public func getAllPages<Element: Decodable & Sendable>(
    _ type: [Element].Type,
    endpoint: ESIEndpoint,
    lease: AccessTokenLease? = nil
  ) async throws -> ESIResponse<[Element]> {
    var firstEndpoint = endpoint
    firstEndpoint.query.removeAll { $0.name == "page" }
    firstEndpoint.query.append(URLQueryItem(name: "page", value: "1"))
    let first = try await get(
      [Element].self,
      endpoint: firstEndpoint,
      lease: lease
    )
    let pageCount = max(first.pages ?? 1, 1)
    if pageCount == 1 { return first }

    var all = first.value
    for page in 2...pageCount {
      try Task.checkCancellation()
      var pageEndpoint = endpoint
      pageEndpoint.query.removeAll { $0.name == "page" }
      pageEndpoint.query.append(
        URLQueryItem(name: "page", value: String(page))
      )
      let response = try await get(
        [Element].self,
        endpoint: pageEndpoint,
        lease: lease
      )
      if let reportedPages = response.pages,
        reportedPages != pageCount
      {
        throw ESIError.invalidPagination
      }
      all.append(contentsOf: response.value)
    }
    return ESIResponse(
      value: all,
      source: first.source,
      statusCode: first.statusCode,
      expiresAt: first.expiresAt,
      etag: first.etag,
      lastModified: first.lastModified,
      pages: pageCount,
      errorLimitRemain: first.errorLimitRemain
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

  private static func httpDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }
}
