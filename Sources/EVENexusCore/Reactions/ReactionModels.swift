import Foundation

public enum CandidateReadiness: String, Codable, Sendable {
  case ready
  case needsReview
  case unsupported
}

public struct ReactionCandidate: Identifiable, Codable, Sendable {
  public let id: UUID
  public let recipe: BlueprintDefinition
  public let runs: Int
  public let securityBand: SecurityBand
  public let readiness: CandidateReadiness
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    recipe: BlueprintDefinition,
    runs: Int,
    securityBand: SecurityBand,
    readiness: CandidateReadiness,
    warnings: [DomainWarning] = []
  ) {
    self.id = id
    self.recipe = recipe
    self.runs = runs
    self.securityBand = securityBand
    self.readiness = readiness
    self.warnings = warnings
  }
}
