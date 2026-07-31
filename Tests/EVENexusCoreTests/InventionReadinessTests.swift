import Foundation
import Testing

@testable import EVENexusCore

@Suite("Invention readiness")
struct InventionReadinessTests {
  @Test
  func comparesFreshCharactersWithoutTurningUnavailableDataIntoZero() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let skills = [
      ScienceSkillDefinition(
        typeID: 1,
        name: "Fixture Encryption Methods",
        source: source
      ),
      ScienceSkillDefinition(
        typeID: 2,
        name: "Mechanical Engineering",
        source: source
      ),
      ScienceSkillDefinition(
        typeID: 3,
        name: "Laboratory Operation",
        source: source
      ),
    ]
    let broad = capability(
      id: 10,
      name: "Broad",
      state: .fresh,
      skills: [
        TrainedSkill(
          skillID: 1,
          trainedLevel: 5,
          activeLevel: 5,
          skillpoints: 1
        ),
        TrainedSkill(
          skillID: 2,
          trainedLevel: 4,
          activeLevel: 4,
          skillpoints: 1
        ),
      ],
      source: source
    )
    let specialist = capability(
      id: 20,
      name: "Specialist",
      state: .fresh,
      skills: [
        TrainedSkill(
          skillID: 1,
          trainedLevel: 3,
          activeLevel: 3,
          skillpoints: 1
        )
      ],
      source: source
    )
    let unavailable = capability(
      id: 30,
      name: "Unavailable",
      state: .unavailable,
      skills: nil,
      source: source
    )

    let matrix = InventionReadinessMatrix(
      skills: skills,
      capabilities: [broad, specialist, unavailable]
    )

    #expect(matrix.bestCharacterID == 10)
    #expect(
      matrix.rows.first { $0.skill.typeID == 2 }?.levels.first {
        $0.characterID == 20
      }?.level == 0
    )
    #expect(
      matrix.rows.first?.levels.first {
        $0.characterID == 30
      }?.level == nil
    )
    #expect(matrix.conclusion.contains("blueprint"))
  }

  @Test
  func includesEveryConnectedCharacterWithoutInventingSkillLevels() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let skill = ScienceSkillDefinition(
      typeID: 1,
      name: "Fixture Encryption Methods",
      source: source
    )
    let available = capability(
      id: 10,
      name: "Available",
      state: .fresh,
      skills: [
        TrainedSkill(
          skillID: 1,
          trainedLevel: 4,
          activeLevel: 4,
          skillpoints: 1
        )
      ],
      source: source
    )

    let matrix = InventionReadinessMatrix(
      skills: [skill],
      characters: [
        CharacterIdentity(id: 10, name: "Available"),
        CharacterIdentity(id: 20, name: "Missing Snapshot"),
        CharacterIdentity(id: 30, name: "Also Missing"),
      ],
      capabilities: [available]
    )

    #expect(matrix.characters.count == 3)
    #expect(
      matrix.rows[0].levels.first { $0.characterID == 10 }?.level == 4
    )
    #expect(
      matrix.rows[0].levels.first { $0.characterID == 20 }?.level == nil
    )
    #expect(
      matrix.characters.first { $0.characterID == 30 }?.skillState
        == .unavailable
    )
  }

  private func capability(
    id: Int64,
    name: String,
    state: DataFreshness,
    skills: [TrainedSkill]?,
    source: SourceIdentity
  ) -> CharacterCapabilitySnapshot {
    CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: id, name: name),
      cloneState: .unknown,
      skills: Sourced(
        state: state,
        value: skills,
        source: source
      ),
      standings: Sourced(
        state: .fresh,
        value: [:],
        source: source
      )
    )
  }
}
