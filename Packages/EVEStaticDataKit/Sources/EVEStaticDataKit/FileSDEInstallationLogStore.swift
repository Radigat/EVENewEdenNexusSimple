import Foundation

public actor FileSDEInstallationLogStore:
    SDEInstallationLogStoring {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ log: SDEInstallationLog) async throws {
        try prepareDirectory()
        let url = logURL(operationID: log.operationID)
        do {
            let data = try encoder.encode(log)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw SDEInstallationError.logPersistenceFailed
        }
    }

    public func incompleteLogs() async throws -> [SDEInstallationLog] {
        try readLogs().filter {
            !$0.isTerminal || $0.cleanupSucceeded == false
        }.sorted {
            ($0.events.first?.occurredAt ?? .distantPast)
                < ($1.events.first?.occurredAt ?? .distantPast)
        }
    }

    public func allLogs() async throws -> [SDEInstallationLog] {
        try readLogs().sorted {
            ($0.events.first?.occurredAt ?? .distantPast)
                > ($1.events.first?.occurredAt ?? .distantPast)
        }
    }

    private func readLogs() throws -> [SDEInstallationLog] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }
        try validateDirectory()
        do {
            return try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "json" }
            .map { url in
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    throw SDEInstallationError.logPersistenceFailed
                }
                let log = try decoder.decode(
                    SDEInstallationLog.self,
                    from: Data(contentsOf: url)
                )
                guard url.deletingPathExtension().lastPathComponent
                        == log.operationID.uuidString else {
                    throw SDEInstallationError.logPersistenceFailed
                }
                return log
            }
        } catch let error as SDEInstallationError {
            throw error
        } catch {
            throw SDEInstallationError.logPersistenceFailed
        }
    }

    private func prepareDirectory() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try validateDirectory()
            return
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw SDEInstallationError.logPersistenceFailed
        }
    }

    private func validateDirectory() throws {
        let values = try directoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw SDEInstallationError.logPersistenceFailed
        }
    }

    private func logURL(operationID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(operationID.uuidString)
            .appendingPathExtension("json")
    }
}
