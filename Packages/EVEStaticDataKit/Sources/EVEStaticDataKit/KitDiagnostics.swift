import Foundation

public enum NexusFailureCategory: String, Sendable {
    case staticData = "static_data"
}

public enum NexusOperation: String, Sendable {
    case sdeMetadataCheck = "sde_metadata_check"
}

public enum NexusFailureCode: String, Sendable {
    case sdeMetadataCheckFailed = "EVE-SDE-006"
}

public enum DiagnosticLevel: String, Sendable {
    case info
    case warning
    case error
}

public enum DiagnosticValue: Equatable, Sendable {
    case publicValue(String)
    case privateValue(String)

    fileprivate var redacted: String {
        switch self {
        case .publicValue(let value):
            value
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        case .privateValue:
            "<redacted>"
        }
    }
}

public struct DiagnosticEvent: Equatable, Sendable {
    public let level: DiagnosticLevel
    public let category: NexusFailureCategory
    public let name: String
    public let code: String
    public let operation: NexusOperation
    public let correlationID: UUID
    public let metadata: [String: DiagnosticValue]

    public init(
        level: DiagnosticLevel,
        category: NexusFailureCategory,
        name: String,
        code: String,
        operation: NexusOperation,
        correlationID: UUID,
        metadata: [String: DiagnosticValue] = [:]
    ) {
        self.level = level
        self.category = category
        self.name = name
        self.code = code
        self.operation = operation
        self.correlationID = correlationID
        self.metadata = metadata
    }

    public var redactedDescription: String {
        let fixed = [
            "category=\(category.rawValue)",
            "code=\(code)",
            "correlation_id=\(correlationID.uuidString)",
            "event=\(name)",
            "level=\(level.rawValue)",
            "operation=\(operation.rawValue)"
        ]
        let values = metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key]?.redacted ?? "<redacted>")"
        }
        return (fixed + values).joined(separator: " ")
    }
}

public protocol DiagnosticLogging: Sendable {
    func log(_ event: DiagnosticEvent)
}

public struct NoOpDiagnosticLogger: DiagnosticLogging {
    public init() {}

    public func log(_ event: DiagnosticEvent) {}
}
