import Foundation
import Testing

@testable import EVENexusCore

@Suite("Reaction contract")
struct ReactionContractTests {
  @Test
  func reactionCandidateHasNoMEOrTEFields() {
    let definition = BlueprintDefinition(
      blueprintTypeID: 10,
      productTypeID: 11,
      maxProductionLimit: nil,
      activity: BlueprintActivityDefinition(
        kind: .reaction,
        durationSeconds: 180,
        materials: [BlueprintMaterial(typeID: 12, quantity: 100)],
        products: [BlueprintProduct(typeID: 11, quantity: 200, probability: nil)]
      ),
      source: SourceIdentity(provider: "fixture", version: "1")
    )
    let candidate = ReactionCandidate(
      recipe: definition,
      runs: 3,
      securityBand: .nullSecurity,
      readiness: .needsReview
    )

    #expect(candidate.recipe.activity.kind == .reaction)
    #expect(candidate.readiness == .needsReview)
    #expect(candidate.runs == 3)
  }
}
