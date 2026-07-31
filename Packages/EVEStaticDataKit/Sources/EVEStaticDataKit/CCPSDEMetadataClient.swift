import Foundation

private final class SDEURLSessionDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct CCPSDEMetadataClientConfiguration: Equatable, Sendable {
    public let userAgent: SDEUserAgentConfiguration
    public let requestTimeout: TimeInterval
    public let maximumAttempts: Int
    public let initialBackoff: TimeInterval
    public let maximumLatestResponseBytes: Int
    public let maximumSchemaResponseBytes: Int

    public init(
        userAgent: SDEUserAgentConfiguration,
        requestTimeout: TimeInterval = 15,
        maximumAttempts: Int = 3,
        initialBackoff: TimeInterval = 1,
        maximumLatestResponseBytes: Int = 1_048_576,
        maximumSchemaResponseBytes: Int = 5_242_880
    ) throws {
        guard requestTimeout > 0,
              maximumAttempts >= 1 && maximumAttempts <= 5,
              initialBackoff >= 0,
              maximumLatestResponseBytes > 0,
              maximumSchemaResponseBytes > 0 else {
            throw SDEMetadataCheckError.transport
        }
        self.userAgent = userAgent
        self.requestTimeout = requestTimeout
        self.maximumAttempts = maximumAttempts
        self.initialBackoff = initialBackoff
        self.maximumLatestResponseBytes = maximumLatestResponseBytes
        self.maximumSchemaResponseBytes = maximumSchemaResponseBytes
    }
}

public final class URLSessionSDEHTTPTransport:
    SDEHTTPTransport,
    @unchecked Sendable {
    private let session: URLSession

    public init(
        connectionTimeout: TimeInterval = 15,
        resourceTimeout: TimeInterval = 30
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = connectionTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: SDEURLSessionDelegate(),
            delegateQueue: nil
        )
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func execute(_ request: SDEHTTPRequest) async throws -> SDEHTTPResponse {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = "GET"
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDEMetadataCheckError.transport
        }
        let headers = httpResponse.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, element in
            guard let name = element.key as? String else {
                return
            }
            result[name.lowercased()] = String(describing: element.value)
        }
        return SDEHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: data,
            finalURL: httpResponse.url
        )
    }
}

public struct TaskSDEBackoffSleeper: SDEBackoffSleeping {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(for: .seconds(seconds))
    }
}

public struct SystemSDEJitterGenerator: SDEJitterGenerating {
    public init() {}

    public func unitInterval() -> Double {
        Double.random(in: 0...1)
    }
}

public struct CCPSDEMetadataClient: SDEReleaseChecking, Sendable {
    public static let latestBuildURLString =
        "https://developers.eveonline.com/static-data/tranquility/latest.jsonl"
    public static let schemaChangelogURLString =
        "https://developers.eveonline.com/static-data/tranquility/schema-changelog.yaml"
    public static let schemaParserVersion = 1

    private let transport: any SDEHTTPTransport
    private let sleeper: any SDEBackoffSleeping
    private let jitter: any SDEJitterGenerating
    private let configuration: CCPSDEMetadataClientConfiguration
    private let now: @Sendable () -> Date

    public init(
        transport: any SDEHTTPTransport,
        sleeper: any SDEBackoffSleeping = TaskSDEBackoffSleeper(),
        jitter: any SDEJitterGenerating = SystemSDEJitterGenerator(),
        configuration: CCPSDEMetadataClientConfiguration,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.sleeper = sleeper
        self.jitter = jitter
        self.configuration = configuration
        self.now = now
    }

    public func latestRelease(
        cache: SDEHTTPCacheMetadata?
    ) async throws -> SDEMetadataFetchResult<SDEReleaseMetadata> {
        let response = try await request(
            resource: .latestBuild,
            url: try Self.officialURL(for: .latestBuild),
            cache: cache,
            accept: "application/jsonlines+json, application/x-ndjson, application/jsonl, application/json, text/plain",
            maximumBytes: configuration.maximumLatestResponseBytes
        )
        let metadata = try responseMetadata(response, previousCache: cache)
        if response.statusCode == 304 {
            return .notModified(metadata)
        }
        try validateContentType(
            response,
            allowed: [
                "application/x-ndjson",
                "application/jsonl",
                "application/jsonlines+json",
                "application/json",
                "text/plain",
                "application/octet-stream"
            ]
        )
        return .modified(try parseLatestRelease(response.body), metadata)
    }

    public func schemaChangelog(
        cache: SDEHTTPCacheMetadata?
    ) async throws -> SDEMetadataFetchResult<SDESchemaChangelogSummary> {
        let response = try await request(
            resource: .schemaChangelog,
            url: try Self.officialURL(for: .schemaChangelog),
            cache: cache,
            accept: "text/vnd.yaml, application/yaml, application/x-yaml, text/yaml, text/plain",
            maximumBytes: configuration.maximumSchemaResponseBytes
        )
        let metadata = try responseMetadata(response, previousCache: cache)
        if response.statusCode == 304 {
            return .notModified(metadata)
        }
        try validateContentType(
            response,
            allowed: [
                "application/yaml",
                "application/x-yaml",
                "text/yaml",
                "text/vnd.yaml",
                "text/plain",
                "application/octet-stream"
            ]
        )
        return .modified(try parseSchemaChangelog(response.body), metadata)
    }

    private func request(
        resource: SDEHTTPResource,
        url: URL,
        cache: SDEHTTPCacheMetadata?,
        accept: String,
        maximumBytes: Int
    ) async throws -> SDEHTTPResponse {
        try validateOfficialURL(url, resource: resource)
        let headers = try requestHeaders(cache: cache, accept: accept)
        let request = SDEHTTPRequest(
            url: url,
            headers: headers,
            timeout: configuration.requestTimeout
        )

        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                let response = try await transport.execute(request)
                if let finalURL = response.finalURL {
                    try validateOfficialURL(finalURL, resource: resource)
                }
                if retryableStatus(response.statusCode),
                   attempt < configuration.maximumAttempts {
                    let delay = retryDelay(
                        response: response,
                        attempt: attempt
                    )
                    try await sleeper.sleep(seconds: delay)
                    attempt += 1
                    continue
                }
                guard response.statusCode == 200
                        || response.statusCode == 304 else {
                    throw SDEMetadataCheckError.httpStatus(
                        response.statusCode
                    )
                }
                guard response.body.count <= maximumBytes else {
                    throw SDEMetadataCheckError.responseTooLarge
                }
                return response
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let urlError = error as? URLError,
                   urlError.code == .cancelled {
                    throw CancellationError()
                }
                let mapped = mapTransportError(error)
                if retryableTransportError(mapped),
                   attempt < configuration.maximumAttempts {
                    try await sleeper.sleep(
                        seconds: exponentialBackoff(attempt: attempt)
                    )
                    attempt += 1
                    continue
                }
                throw mapped
            }
        }
    }

    private func requestHeaders(
        cache: SDEHTTPCacheMetadata?,
        accept: String
    ) throws -> [String: String] {
        var headers = [
            "Accept": accept,
            "User-Agent": configuration.userAgent.headerValue
        ]
        if let etag = cache?.validators.etag {
            guard Self.isSafeHeaderValue(etag) else {
                throw SDEMetadataCheckError.invalidValidators
            }
            headers["If-None-Match"] = etag
        }
        if let lastModified = cache?.validators.lastModified {
            guard Self.isSafeHeaderValue(lastModified) else {
                throw SDEMetadataCheckError.invalidValidators
            }
            headers["If-Modified-Since"] = lastModified
        }
        return headers
    }

    private func responseMetadata(
        _ response: SDEHTTPResponse,
        previousCache: SDEHTTPCacheMetadata?
    ) throws -> SDEHTTPResponseMetadata {
        let etag = response.header("etag") ?? previousCache?.validators.etag
        let lastModified = response.header("last-modified")
            ?? previousCache?.validators.lastModified
        if let etag, !Self.isSafeHeaderValue(etag) {
            throw SDEMetadataCheckError.invalidValidators
        }
        if let lastModified, !Self.isSafeHeaderValue(lastModified) {
            throw SDEMetadataCheckError.invalidValidators
        }

        let cacheLifetime = cacheLifetime(response)
        return SDEHTTPResponseMetadata(
            statusCode: response.statusCode,
            cache: SDEHTTPCacheMetadata(
                validators: SDEHTTPValidators(
                    etag: etag,
                    lastModified: lastModified
                ),
                freshUntil: cacheLifetime.map {
                    now().addingTimeInterval($0)
                }
            )
        )
    }

    private func parseLatestRelease(_ data: Data) throws -> SDEReleaseMetadata {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SDEMetadataCheckError.invalidLatestResponse
        }
        var records: [[String: Any]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.utf8.count <= 65_536,
                  let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(
                    with: lineData
                  ) as? [String: Any] else {
                throw SDEMetadataCheckError.invalidLatestResponse
            }
            records.append(object)
        }

        let sdeRecords = records.filter { ($0["_key"] as? String) == "sde" }
        guard sdeRecords.count == 1,
              let buildNumber = Self.buildNumber(in: sdeRecords[0]),
              buildNumber > 0,
              let releasedAt = Self.releaseDate(
                in: sdeRecords[0],
                allRecords: records
              ) else {
            throw SDEMetadataCheckError.invalidLatestResponse
        }
        do {
            return try SDEReleaseMetadata(
                buildNumber: buildNumber,
                releasedAt: releasedAt
            )
        } catch {
            throw SDEMetadataCheckError.invalidLatestResponse
        }
    }

    private func parseSchemaChangelog(
        _ data: Data
    ) throws -> SDESchemaChangelogSummary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SDEMetadataCheckError.invalidSchemaChangelog
        }
        var builds: [Int] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let range = line.range(of: "afterBuildNumber:") else {
                continue
            }
            let prefix = line[..<range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            guard prefix.isEmpty || prefix == "-" else {
                continue
            }
            let valueWithComment = line[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let value = valueWithComment
                .split(separator: "#", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !value.isEmpty,
                  value.allSatisfy(\.isNumber),
                  let build = Int(value),
                  build > 0 else {
                throw SDEMetadataCheckError.invalidSchemaChangelog
            }
            builds.append(build)
        }
        guard let highest = builds.max() else {
            throw SDEMetadataCheckError.invalidSchemaChangelog
        }
        do {
            return try SDESchemaChangelogSummary(
                highestAfterBuildNumber: highest,
                entryCount: builds.count,
                parserVersion: Self.schemaParserVersion
            )
        } catch {
            throw SDEMetadataCheckError.invalidSchemaChangelog
        }
    }

    private func validateOfficialURL(
        _ url: URL,
        resource: SDEHTTPResource
    ) throws {
        let expected = switch resource {
        case .latestBuild:
            Self.latestBuildURLString
        case .schemaChangelog:
            Self.schemaChangelogURLString
        }
        guard url.absoluteString == expected,
              url.scheme == "https",
              url.host == "developers.eveonline.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            throw SDEMetadataCheckError.invalidURL
        }
    }

    private static func officialURL(
        for resource: SDEHTTPResource
    ) throws -> URL {
        let value = switch resource {
        case .latestBuild:
            latestBuildURLString
        case .schemaChangelog:
            schemaChangelogURLString
        }
        guard let url = URL(string: value) else {
            throw SDEMetadataCheckError.invalidURL
        }
        return url
    }

    private func validateContentType(
        _ response: SDEHTTPResponse,
        allowed: Set<String>
    ) throws {
        guard let rawType = response.header("content-type") else {
            throw SDEMetadataCheckError.invalidContentType
        }
        let type = rawType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let type, allowed.contains(type) else {
            throw SDEMetadataCheckError.invalidContentType
        }
    }

    private func cacheLifetime(_ response: SDEHTTPResponse) -> TimeInterval? {
        guard let cacheControl = response.header("cache-control") else {
            return nil
        }
        let directives = cacheControl.split(separator: ",")
        guard let maximumAge = directives.compactMap({ directive -> Int? in
            let parts = directive
                .trimmingCharacters(in: .whitespaces)
                .split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].lowercased() == "max-age" else {
                return nil
            }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }).first else {
            return nil
        }
        let age = response.header("age").flatMap(Int.init) ?? 0
        return TimeInterval(max(0, maximumAge - max(0, age)))
    }

    private func retryableStatus(_ status: Int) -> Bool {
        status == 408 || status == 429
            || [500, 502, 503, 504].contains(status)
    }

    private func retryDelay(
        response: SDEHTTPResponse,
        attempt: Int
    ) -> TimeInterval {
        if response.statusCode == 429,
           let retryAfter = response.header("retry-after"),
           let delay = retryAfterDelay(retryAfter) {
            return delay
        }
        return exponentialBackoff(attempt: attempt)
    }

    private func retryAfterDelay(_ value: String) -> TimeInterval? {
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSince(now()))
    }

    private func exponentialBackoff(attempt: Int) -> TimeInterval {
        let base = configuration.initialBackoff
            * pow(2, Double(max(0, attempt - 1)))
        let jitterValue = min(1, max(0, jitter.unitInterval()))
        return base + (base * jitterValue)
    }

    private func mapTransportError(_ error: any Error) -> SDEMetadataCheckError {
        if let typed = error as? SDEMetadataCheckError {
            return typed
        }
        guard let urlError = error as? URLError else {
            return .transport
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .transport
        default:
            return .transport
        }
    }

    private func retryableTransportError(
        _ error: SDEMetadataCheckError
    ) -> Bool {
        error == .timedOut || error == .transport
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 && scalar.value != 127
        }
    }

    private static func buildNumber(in record: [String: Any]) -> Int? {
        if let build = integer(record["buildNumber"]) {
            return build
        }
        if let value = record["_value"] as? [String: Any] {
            return integer(value["buildNumber"]) ?? integer(value["build"])
        }
        return integer(record["_value"])
    }

    private static func releaseDate(
        in sdeRecord: [String: Any],
        allRecords: [[String: Any]]
    ) -> Date? {
        let keys = ["releaseDate", "releaseDateTime", "releasedAt", "date"]
        for key in keys {
            if let date = parsedDate(sdeRecord[key]) {
                return date
            }
        }
        if let value = sdeRecord["_value"] as? [String: Any] {
            for key in keys {
                if let date = parsedDate(value[key]) {
                    return date
                }
            }
        }
        for record in allRecords {
            guard let key = record["_key"] as? String,
                  ["releaseDate", "releaseDateTime", "releasedAt", "release"]
                    .contains(key) else {
                continue
            }
            if let date = parsedDate(record["_value"]) {
                return date
            }
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c" else {
            if let string = value as? String,
               string.allSatisfy(\.isNumber) {
                return Int(string)
            }
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private static func parsedDate(_ value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = withFractionalSeconds.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}
