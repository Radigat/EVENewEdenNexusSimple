import Foundation

public struct InventionSkillCell: Codable, Equatable, Sendable {
  public let characterID: Int64
  public let level: Int?

  public init(characterID: Int64, level: Int?) {
    self.characterID = characterID
    self.level = level
  }
}

public struct InventionSkillRow: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { skill.typeID }
  public let skill: ScienceSkillDefinition
  public let levels: [InventionSkillCell]

  public init(
    skill: ScienceSkillDefinition,
    levels: [InventionSkillCell]
  ) {
    self.skill = skill
    self.levels = levels
  }
}

public struct InventionCharacterReadiness: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { characterID }
  public let characterID: Int64
  public let characterName: String
  public let skillState: DataFreshness
  public let knownRelevantSkills: Int
  public let trainedRelevantSkills: Int
  public let averageRelevantLevel: Double?
  public let levelFiveRelevantSkills: Int

  public init(
    characterID: Int64,
    characterName: String,
    skillState: DataFreshness,
    knownRelevantSkills: Int,
    trainedRelevantSkills: Int,
    averageRelevantLevel: Double?,
    levelFiveRelevantSkills: Int
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.skillState = skillState
    self.knownRelevantSkills = knownRelevantSkills
    self.trainedRelevantSkills = trainedRelevantSkills
    self.averageRelevantLevel = averageRelevantLevel
    self.levelFiveRelevantSkills = levelFiveRelevantSkills
  }
}

public struct InventionReadinessMatrix: Codable, Equatable, Sendable {
  public let rows: [InventionSkillRow]
  public let characters: [InventionCharacterReadiness]
  public let bestCharacterID: Int64?
  public let conclusion: String

  public init(
    skills: [ScienceSkillDefinition],
    characters expectedCharacters: [CharacterIdentity] = [],
    capabilities: [CharacterCapabilitySnapshot]
  ) {
    let orderedSkills = skills.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let capabilityByCharacterID = Dictionary(
      uniqueKeysWithValues: capabilities.map { ($0.character.id, $0) }
    )
    var characterByID = Dictionary(
      uniqueKeysWithValues: expectedCharacters.map { ($0.id, $0) }
    )
    for capability in capabilities {
      characterByID[capability.character.id] = capability.character
    }
    let orderedCharacters = characterByID.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name)
        == .orderedAscending
    }
    rows = orderedSkills.map { skill in
      InventionSkillRow(
        skill: skill,
        levels: orderedCharacters.map {
          InventionSkillCell(
            characterID: $0.id,
            level: capabilityByCharacterID[$0.id].flatMap {
              Self.level(for: skill.typeID, in: $0.skills)
            }
          )
        }
      )
    }
    let relevant = orderedSkills.filter(\.isInventionRelevant)
    characters = orderedCharacters.map { character in
      guard let capability = capabilityByCharacterID[character.id] else {
        return InventionCharacterReadiness(
          characterID: character.id,
          characterName: character.name,
          skillState: .unavailable,
          knownRelevantSkills: 0,
          trainedRelevantSkills: 0,
          averageRelevantLevel: nil,
          levelFiveRelevantSkills: 0
        )
      }
      let levels = relevant.compactMap {
        Self.level(for: $0.typeID, in: capability.skills)
      }
      return InventionCharacterReadiness(
        characterID: capability.character.id,
        characterName: capability.character.name,
        skillState: capability.skills.state,
        knownRelevantSkills: levels.count,
        trainedRelevantSkills: levels.filter { $0 > 0 }.count,
        averageRelevantLevel:
          levels.isEmpty
          ? nil : Double(levels.reduce(0, +)) / Double(levels.count),
        levelFiveRelevantSkills: levels.filter { $0 == 5 }.count
      )
    }
    let best =
      characters
      .filter {
        $0.skillState == .fresh && $0.averageRelevantLevel != nil
      }
      .sorted {
        if $0.averageRelevantLevel != $1.averageRelevantLevel {
          return ($0.averageRelevantLevel ?? -1)
            > ($1.averageRelevantLevel ?? -1)
        }
        if $0.trainedRelevantSkills != $1.trainedRelevantSkills {
          return $0.trainedRelevantSkills > $1.trainedRelevantSkills
        }
        return $0.characterName.localizedCaseInsensitiveCompare(
          $1.characterName
        ) == .orderedAscending
      }
      .first
    bestCharacterID = best?.characterID
    if let best, let average = best.averageRelevantLevel {
      conclusion =
        "\(best.characterName) currently has the broadest invention readiness "
        + "(\(best.trainedRelevantSkills)/\(best.knownRelevantSkills) relevant "
        + "skills trained, average level "
        + average.formatted(.number.precision(.fractionLength(2))) + "). "
        + "The exact invention chance still depends on the blueprint's three "
        + "required skills, base probability and any decryptor."
    } else {
      conclusion =
        "No complete character skill snapshot is available. Unknown or "
        + "unavailable skill data is not treated as level 0."
    }
  }

  private static func level(
    for typeID: Int64,
    in sourced: Sourced<[TrainedSkill]>
  ) -> Int? {
    switch sourced.state {
    case .fresh:
      guard let values = sourced.value else { return nil }
      return values.first { $0.skillID == typeID }?.activeLevel ?? 0
    case .partial, .stale:
      return sourced.value?.first { $0.skillID == typeID }?.activeLevel
    case .forbidden, .unavailable:
      return nil
    }
  }
}
