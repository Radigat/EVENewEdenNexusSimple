import Foundation

public struct SDEArchiveTransportRequest: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let timeout: TimeInterval

    public init(
        url: URL,
        headers: [String: String],
        timeout: TimeInterval
    ) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
    }
}
public struct SDEArchiveTransportResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let temporaryFileURL: URL
    public let finalURL: URL?

    public init(
        statusCode: Int,
        headers: [String: String],
        temporaryFileURL: URL,
        finalURL: URL?
    ) {
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { result, value in
            result[value.key.lowercased()] = value.value
        }
        self.temporaryFileURL = temporaryFileURL
        self.finalURL = finalURL
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol SDEArchiveHTTPTransport: Sendable {
    func download(_ request: SDEArchiveTransportRequest) async throws
        -> SDEArchiveTransportResponse
}

public final class URLSessionSDEArchiveHTTPTransport:
    SDEArchiveHTTPTransport,
    @unchecked Sendable {
    private let session: URLSession

    public init(
        connectionTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 30 * 60
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = connectionTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: SDEArchiveRedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func download(
        _ request: SDEArchiveTransportRequest
    ) async throws -> SDEArchiveTransportResponse {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = "GET"
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (temporaryURL, response) = try await session.download(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SDEInstallationError.transport
        }
        let headers = http.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, value in
            guard let name = value.key as? String else {
                return
            }
            result[name] = String(describing: value.value)
        }
        return SDEArchiveTransportResponse(
            statusCode: http.statusCode,
            headers: headers,
            temporaryFileURL: temporaryURL,
            finalURL: http.url
        )
    }
}

private final class SDEArchiveRedirectRejectingDelegate:
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

public protocol SDEAvailableCapacityReading: Sendable {
    func availableCapacity(at directoryURL: URL) throws -> Int64
}

public struct VolumeSDEAvailableCapacityReader: SDEAvailableCapacityReading {
    public init() {}

    public func availableCapacity(at directoryURL: URL) throws -> Int64 {
        let values = try directoryURL.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
        )
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        throw SDEInstallationError.insufficientDiskSpace
    }
}

public struct CCPSDEArchiveDownloaderConfiguration: Sendable {
    public let workingDirectoryURL: URL
    public let userAgent: SDEUserAgentConfiguration
    public let requestTimeout: TimeInterval
    public let maximumAttempts: Int
    public let initialBackoff: TimeInterval
    public let maximumArchiveBytes: Int64
    public let minimumFreeBytesBeforeDownload: Int64

    public init(
        workingDirectoryURL: URL,
        userAgent: SDEUserAgentConfiguration,
        requestTimeout: TimeInterval = 30 * 60,
        maximumAttempts: Int = 3,
        initialBackoff: TimeInterval = 1,
        maximumArchiveBytes: Int64 = 5 * 1_024 * 1_024 * 1_024,
        minimumFreeBytesBeforeDownload: Int64 = 1_024 * 1_024 * 1_024
    ) throws {
        guard userAgent.contact != nil else {
            throw SDEInstallationError.missingOwnerContact
        }
        guard requestTimeout > 0,
              maximumAttempts >= 1 && maximumAttempts <= 5,
              initialBackoff >= 0,
              maximumArchiveBytes > 0,
              minimumFreeBytesBeforeDownload > 0 else {
            throw SDEInstallationError.transport
        }
        self.workingDirectoryURL = workingDirectoryURL
        self.userAgent = userAgent
        self.requestTimeout = requestTimeout
        self.maximumAttempts = maximumAttempts
        self.initialBackoff = initialBackoff
        self.maximumArchiveBytes = maximumArchiveBytes
        self.minimumFreeBytesBeforeDownload = minimumFreeBytesBeforeDownload
    }
}

public actor CCPSDEArchiveDownloader: SDEArchiveDownloading {
    public static let baseURLString =
        "https://developers.eveonline.com/static-data/tranquility/"

    private let transport: any SDEArchiveHTTPTransport
    private let capacityReader: any SDEAvailableCapacityReading
    private let sleeper: any SDEBackoffSleeping
    private let jitter: any SDEJitterGenerating
    private let configuration: CCPSDEArchiveDownloaderConfiguration
    private let fileManager: FileManager

    public init(
        transport: any SDEArchiveHTTPTransport,
        capacityReader: any SDEAvailableCapacityReading =
            VolumeSDEAvailableCapacityReader(),
        sleeper: any SDEBackoffSleeping = TaskSDEBackoffSleeper(),
        jitter: any SDEJitterGenerating = SystemSDEJitterGenerator(),
        configuration: CCPSDEArchiveDownloaderConfiguration,
        fileManager: FileManager = .default
    ) {
        self.transport = transport
        self.capacityReader = capacityReader
        self.sleeper = sleeper
        self.jitter = jitter
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func download(
        _ request: SDEArchiveDownloadRequest
    ) async throws -> SDEArchiveDownload {
        guard request.buildNumber > 0 else {
            throw SDEInstallationError.invalidBuildNumber
        }
        let officialURL = try Self.officialURL(
            buildNumber: request.buildNumber
        )
        let operationDirectory = configuration.workingDirectoryURL
            .appendingPathComponent(
                request.operationID.uuidString,
                isDirectory: true
            )
        try preparePrivateDirectory(operationDirectory)
        do {
            let capacity = try capacityReader.availableCapacity(
                at: operationDirectory
            )
            guard capacity >= configuration.minimumFreeBytesBeforeDownload else {
                throw SDEInstallationError.insufficientDiskSpace
            }

            var headers = [
                "Accept": "application/zip, application/octet-stream",
                "User-Agent": configuration.userAgent.headerValue
            ]
            if let etag = request.validators.etag {
                guard Self.isSafeHeaderValue(etag) else {
                    throw SDEInstallationError.transport
                }
                headers["If-None-Match"] = etag
            }
            if let modified = request.validators.lastModified {
                guard Self.isSafeHeaderValue(modified) else {
                    throw SDEInstallationError.transport
                }
                headers["If-Modified-Since"] = modified
            }
            let transportRequest = SDEArchiveTransportRequest(
                url: officialURL,
                headers: headers,
                timeout: configuration.requestTimeout
            )

            var attempt = 1
            while true {
                try Task.checkCancellation()
                do {
                    let response = try await transport.download(
                        transportRequest
                    )
                    if retryable(response.statusCode),
                       attempt < configuration.maximumAttempts {
                        try await sleeper.sleep(
                            seconds: retryDelay(
                                response: response,
                                attempt: attempt
                            )
                        )
                        attempt += 1
                        continue
                    }
                    return try finish(
                        response: response,
                        request: request,
                        officialURL: officialURL,
                        operationDirectory: operationDirectory
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if attempt < configuration.maximumAttempts,
                       isRetryableTransport(error) {
                        try await sleeper.sleep(
                            seconds: backoff(attempt: attempt)
                        )
                        attempt += 1
                        continue
                    }
                    if error is URLError {
                        throw SDEInstallationError.transport
                    }
                    throw error
                }
            }
        } catch {
            try? removeOperationDirectory(operationDirectory)
            throw error
        }
    }

    public func cleanup(operationID: UUID) async throws {
        try removeOperationDirectory(
            configuration.workingDirectoryURL.appendingPathComponent(
                operationID.uuidString,
                isDirectory: true
            )
        )
    }

    public static func officialURL(buildNumber: Int) throws -> URL {
        guard buildNumber > 0,
              let url = URL(
                string: baseURLString
                    + "eve-online-static-data-\(buildNumber)-jsonl.zip"
              ),
              url.scheme == "https",
              url.host == "developers.eveonline.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            throw SDEInstallationError.invalidOfficialURL
        }
        return url
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 32 && scalar.value != 127
        }
    }

    private func finish(
        response: SDEArchiveTransportResponse,
        request: SDEArchiveDownloadRequest,
        officialURL: URL,
        operationDirectory: URL
    ) throws -> SDEArchiveDownload {
        guard response.statusCode == 200 else {
            throw SDEInstallationError.invalidHTTPStatus(response.statusCode)
        }
        guard response.finalURL == nil || response.finalURL == officialURL else {
            throw SDEInstallationError.redirectedDownload
        }
        let contentType = response.header("content-type")?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let contentType,
              ["application/zip", "application/octet-stream"]
                .contains(contentType) else {
            throw SDEInstallationError.invalidContentType
        }
        guard let rawLength = response.header("content-length"),
              let expectedLength = Int64(rawLength),
              expectedLength > 0 else {
            throw SDEInstallationError.invalidContentLength
        }
        guard expectedLength <= configuration.maximumArchiveBytes else {
            throw SDEInstallationError.downloadTooLarge
        }
        let values = try response.temporaryFileURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize.map(Int64.init) else {
            throw SDEInstallationError.transport
        }
        guard size == expectedLength else {
            throw SDEInstallationError.downloadedSizeMismatch
        }
        let remainingCapacity = try capacityReader.availableCapacity(
            at: operationDirectory
        )
        guard remainingCapacity >= size else {
            throw SDEInstallationError.insufficientDiskSpace
        }
        let archiveURL = operationDirectory.appendingPathComponent(
            "eve-online-static-data-\(request.buildNumber)-jsonl.zip"
        )
        try fileManager.moveItem(
            at: response.temporaryFileURL,
            to: archiveURL
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: archiveURL.path
        )
        return SDEArchiveDownload(
            operationID: request.operationID,
            buildNumber: request.buildNumber,
            officialURL: officialURL,
            archiveURL: archiveURL,
            byteCount: size,
            httpStatus: response.statusCode,
            validators: SDEHTTPValidators(
                etag: response.header("etag"),
                lastModified: response.header("last-modified")
            ),
            cacheDecision: .downloaded
        )
    }

    private func preparePrivateDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: configuration.workingDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw SDEInstallationError.transport
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func removeOperationDirectory(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let values = try directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SDEInstallationError.cleanupFailed
        }
        try fileManager.removeItem(at: directory)
    }

    private func retryable(_ status: Int) -> Bool {
        status == 408 || status == 429
            || [500, 502, 503, 504].contains(status)
    }

    private func retryDelay(
        response: SDEArchiveTransportResponse,
        attempt: Int
    ) -> TimeInterval {
        if response.statusCode == 429,
           let retryAfter = response.header("retry-after"),
           let seconds = TimeInterval(retryAfter),
           seconds >= 0 {
            return seconds
        }
        return backoff(attempt: attempt)
    }

    private func backoff(attempt: Int) -> TimeInterval {
        let base = configuration.initialBackoff
            * pow(2, Double(max(0, attempt - 1)))
        return base + base * min(1, max(0, jitter.unitInterval()))
    }

    private func isRetryableTransport(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet
        ].contains(urlError.code)
    }
}
