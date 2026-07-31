import Foundation

public enum DataFreshness: String, Codable, CaseIterable, Sendable {
  case fresh
  case partial
  case stale
  case forbidden
  case unavailable
}

public struct SourceIdentity: Codable, Equatable, Hashable, Sendable {
  public let provider: String
  public let version: String
  public let capturedAt: Date
  public let snapshotID: UUID

  public init(
    provider: String,
    version: String,
    capturedAt: Date = .now,
    snapshotID: UUID = UUID()
  ) {
    self.provider = provider
    self.version = version
    self.capturedAt = capturedAt
    self.snapshotID = snapshotID
  }
}

public struct Sourced<Value: Codable & Sendable>: Codable, Sendable {
  public let state: DataFreshness
  public let value: Value?
  public let source: SourceIdentity
  public let diagnostics: [String]

  public init(
    state: DataFreshness,
    value: Value?,
    source: SourceIdentity,
    diagnostics: [String] = []
  ) {
    self.state = state
    self.value = value
    self.source = source
    self.diagnostics = diagnostics
  }
}

public enum DomainWarningSeverity: String, Codable, Sendable {
  case information
  case warning
  case blocking
}

public struct DomainWarning: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let code: String
  public let message: String
  public let severity: DomainWarningSeverity
  public let source: SourceIdentity?

  public init(
    id: UUID = UUID(),
    code: String,
    message: String,
    severity: DomainWarningSeverity,
    source: SourceIdentity? = nil
  ) {
    self.id = id
    self.code = code
    self.message = message
    self.severity = severity
    self.source = source
  }
}

public enum EVEConstants {
  public static let theForgeRegionID: Int64 = 10_000_002
  public static let jitaSystemID: Int64 = 30_000_142
  public static let jitaIV4StationID: Int64 = 60_003_760
  public static let jitaIV4OwnerCorporationID: Int64 = 1_000_035
  public static let jitaIV4OwnerFactionID: Int64 = 500_001
  public static let accountingSkillTypeID: Int64 = 16_622
  public static let brokerRelationsSkillTypeID: Int64 = 3_446
  public static let esiCompatibilityDate = "2025-12-16"
  public static let callbackPort: UInt16 = 52_722
  public static let callbackURL = URL(
    string: "http://localhost:\(callbackPort)/callback"
  )!
}
