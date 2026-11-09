import Testing

@testable import EVENexusCore

/// Owner decisions 09.11.2026: ME/TE preset of the Planner build link and
/// the product adder.
@Suite("Planner build ME/TE preset")
struct PlannerBuildPresetTests {
  @Test
  func presetValuesFollowTheProductionClass() {
    func values(_ basis: PlannerBuildEfficiencyPreset.Basis) -> [Int] {
      let preset = PlannerBuildEfficiencyPreset(basis: basis)
      return [preset.materialEfficiency, preset.timeEfficiency]
    }
    #expect(values(.techI) == [10, 20])
    #expect(values(.techII) == [3, 2])
    #expect(values(.techIII) == [3, 2])
    #expect(values(.faction) == [0, 0])
    #expect(values(.storyline) == [0, 0])
    #expect(values(.other) == [0, 0])
    #expect(values(.reaction) == [0, 0])
    #expect(
      PlannerBuildEfficiencyPreset.Basis.allCases.filter {
        PlannerBuildEfficiencyPreset(basis: $0).efficiencyLocked
      } == [.reaction]
    )
  }

  @Test
  func metaGroupsMapToTheirProductionClass() {
    let expected: [(Int64, PlannerBuildEfficiencyPreset.Basis)] = [
      (1, .techI), (54, .techI),
      (2, .techII), (53, .techII),
      (14, .techIII),
      (4, .faction), (52, .faction),
      (3, .storyline),
      (5, .other), (6, .other), (15, .other), (17, .other), (19, .other),
    ]
    for (metaGroupID, basis) in expected {
      // The meta group wins over the tech level.
      #expect(
        PlannerBuildEfficiencyPreset.basis(metaGroupID: metaGroupID, techLevel: 2)
          == basis,
        "meta group \(metaGroupID)"
      )
    }
  }

  @Test
  func missingMetaGroupFallsBackToTheTechLevel() {
    #expect(PlannerBuildEfficiencyPreset.basis(metaGroupID: nil, techLevel: 1) == .techI)
    #expect(PlannerBuildEfficiencyPreset.basis(metaGroupID: nil, techLevel: 2) == .techII)
    #expect(PlannerBuildEfficiencyPreset.basis(metaGroupID: nil, techLevel: 3) == .techIII)
    // Components, fuel blocks and Upwell structures carry neither value and
    // come from ordinary researchable BPOs.
    #expect(PlannerBuildEfficiencyPreset.basis(metaGroupID: nil, techLevel: nil) == .techI)
    #expect(PlannerBuildEfficiencyPreset.basis(metaGroupID: nil, techLevel: 5) == .other)
  }

  @Test
  func reactionsIgnoreTheProductionClass() {
    let preset = PlannerBuildEfficiencyPreset.resolve(
      activity: .reaction,
      metaGroupID: 2,
      techLevel: 2
    )
    #expect(preset.basis == .reaction)
    #expect(preset.efficiencyLocked)
    #expect(preset.materialEfficiency == 0)
    #expect(preset.timeEfficiency == 0)

    let manufacturing = PlannerBuildEfficiencyPreset.resolve(
      activity: .manufacturing,
      metaGroupID: 14,
      techLevel: 3
    )
    #expect(manufacturing == PlannerBuildEfficiencyPreset(basis: .techIII))
    #expect(!manufacturing.efficiencyLocked)
  }
}
