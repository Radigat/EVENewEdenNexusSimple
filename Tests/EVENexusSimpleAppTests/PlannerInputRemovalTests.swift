import EVENexusCore
import Testing

@testable import EVENexusSimpleApp

/// Removing a product in step 3 or 4 calculates again; the sale choices saved
/// per input line must follow the lines that move up.
struct PlannerInputRemovalTests {
  @Test
  func saleChoicesFollowTheirLineAfterARemoval() throws {
    let input = "Multispectrum Shield Hardener II 100 10 20\nProwler 10 3 2\nRhea 1 0 0"
    let requests = ProductionInputParser.parse(input).requests
    let drafts: [String: PlannerProductDecisionDraft] = Dictionary(
      uniqueKeysWithValues: requests.map { request in
        (
          PlannerProductDecisionDraft.key(for: request),
          PlannerProductDecisionDraft(
            targetMarket: nil,
            allianceInput: nil,
            saleScenario: request.productName == "Prowler" ? .immediateSale : .listedSale
          )
        )
      }
    )
    let hardener = try #require(requests.first)
    let removal = try #require(ProductionInputFormatter.requestRemoval(hardener, from: input))

    let moved = PlannerProductDecisionDraft.moving(drafts, after: removal)

    // The next calculation numbers the remaining lines anew; the keys match.
    let remaining = ProductionInputParser.parse(removal.input).requests
    #expect(Set(moved.keys) == Set(remaining.map(PlannerProductDecisionDraft.key(for:))))
    let prowler = try #require(remaining.first)
    #expect(prowler.productName == "Prowler")
    #expect(moved[PlannerProductDecisionDraft.key(for: prowler)]?.saleScenario == .immediateSale)
  }

  @Test
  func unknownDraftKeysStay() {
    let draft = PlannerProductDecisionDraft(
      targetMarket: nil,
      allianceInput: nil,
      saleScenario: nil
    )
    let removal = ProductionInputLineRemoval(input: "", removedLineNumbers: [1])
    let moved = PlannerProductDecisionDraft.moving(
      ["legacy": draft, "1:Ark": draft, "2:Name: with colon": draft],
      after: removal
    )
    #expect(moved == ["legacy": draft, "1:Name: with colon": draft])
  }
}
