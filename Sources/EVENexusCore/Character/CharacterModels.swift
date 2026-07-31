import Foundation

public struct CharacterIdentity: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public var name: String
  public var corporationID: Int64?

  public init(id: Int64, name: String, corporationID: Int64? = nil) {
    self.id = id
    self.name = name
    self.corporationID = corporationID
  }
}

public enum CloneState: String, Codable, CaseIterable, Sendable {
  case alpha
  case omega
  case unknown
}

public struct TrainedSkill: Codable, Hashable, Sendable {
  public let skillID: Int64
  public let trainedLevel: Int
  public let activeLevel: Int
  public let skillpoints: Int64
}

public struct ScienceSkillDefinition: Identifiable, Codable, Hashable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let source: SourceIdentity

  public init(typeID: Int64, name: String, source: SourceIdentity) {
    self.typeID = typeID
    self.name = name
    self.source = source
  }

  public var isInventionRelevant: Bool {
    name.contains("Encryption Methods")
      || name.contains("Engineering")
      || name.contains("Physics")
      || name.hasSuffix("Technology")
  }
}

public struct CharacterCapabilitySnapshot: Identifiable, Codable, Sendable {
  public let id: UUID
  public let character: CharacterIdentity
  public let cloneState: CloneState
  public let skills: Sourced<[TrainedSkill]>
  public let standings: Sourced<[Int64: Double]>

  public init(
    id: UUID = UUID(),
    character: CharacterIdentity,
    cloneState: CloneState,
    skills: Sourced<[TrainedSkill]>,
    standings: Sourced<[Int64: Double]>
  ) {
    self.id = id
    self.character = character
    self.cloneState = cloneState
    self.skills = skills
    self.standings = standings
  }

  public func skillLevel(_ typeID: Int64) -> Int? {
    guard skills.state != .forbidden,
      skills.state != .unavailable,
      let values = skills.value
    else { return nil }
    return values.first(where: { $0.skillID == typeID })?.activeLevel
  }
}

public struct CharacterWalletBalance: Identifiable, Codable, Sendable {
  public var id: Int64 { character.id }
  public let character: CharacterIdentity
  public let balance: Sourced<Double>

  public init(
    character: CharacterIdentity,
    balance: Sourced<Double>
  ) {
    self.character = character
    self.balance = balance
  }
}

public struct WalletPortfolioSnapshot: Sendable {
  public let balances: [CharacterWalletBalance]

  public init(balances: [CharacterWalletBalance]) {
    self.balances = balances.sorted {
      $0.character.name.localizedCaseInsensitiveCompare($1.character.name)
        == .orderedAscending
    }
  }

  public var totalBalance: Double {
    includedBalances.compactMap(\.balance.value).reduce(0, +)
  }

  public var includedCharacterCount: Int {
    includedBalances.count
  }

  public var totalCharacterCount: Int {
    balances.count
  }

  public var freshness: DataFreshness {
    guard !balances.isEmpty else { return .unavailable }
    let included = includedBalances
    guard !included.isEmpty else {
      return balances.allSatisfy { $0.balance.state == .forbidden }
        ? .forbidden
        : .unavailable
    }
    guard included.count == balances.count,
      !included.contains(where: { $0.balance.state == .partial })
    else { return .partial }
    if included.contains(where: { $0.balance.state == .stale }) {
      return .stale
    }
    return .fresh
  }

  private var includedBalances: [CharacterWalletBalance] {
    balances.filter {
      $0.balance.value != nil
        && [.fresh, .partial, .stale].contains($0.balance.state)
    }
  }
}
