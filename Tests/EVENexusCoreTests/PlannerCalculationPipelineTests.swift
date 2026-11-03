import Foundation
import Testing

@testable import EVENexusCore

/// Control flow of one Planner click without UI (ANALYSE_2026-11-02, A3).
/// The Blueprint basis and the calculation are scripted; the tests check the
/// order and inputs of the passes and when the click stops.
@MainActor
@Suite("Planner calculation pipeline")
struct PlannerCalculationPipelineTests {
  @Test
  func keepsTheTreesBuildStepsWithoutAControlPass() async {
    let built = Self.plan(produced: [Self.component])
    let script = Script(
      bases: [Basis(selectedPlan: built)],
      results: [.init(plan: built, failed: false)]
    )

    let outcome = await script.pipeline().run(startingFrom: nil)

    #expect(Self.completedPlanID(outcome) == built.id)
    #expect(script.basisRequests.map(\.automaticSupply) == [true])
    #expect(script.calculations.map(\.automaticSupply) == [true])
    #expect(script.calculations.allSatisfy { !$0.calculatesWithoutStock })
  }

  @Test
  func resolvesTheCalculatedBuildStepsAgainWithTheManualChoicesWinning() async {
    let manual = Self.preference(.produce)
    let treePlan = Self.plan(produced: [])
    let decided = Self.plan(
      produced: [Self.component],
      decisions: [Self.component.typeID: .produce, 34: .buy]
    )
    let final = Self.plan(produced: [Self.component])
    let script = Script(
      manual: [34: manual],
      bases: [Basis(selectedPlan: treePlan), Basis(selectedPlan: final)],
      results: [.init(plan: decided, failed: false), .init(plan: final, failed: false)]
    )

    let outcome = await script.pipeline().run(startingFrom: nil)

    #expect(Self.completedPlanID(outcome) == final.id)
    #expect(script.basisRequests.map(\.automaticSupply) == [true, false])
    let control = script.basisRequests[1].preferences
    #expect(control[34] == manual)
    #expect(control[Self.component.typeID]?.supplyMode == .produce)
    #expect(script.calculations.map(\.automaticSupply) == [true, false])
  }

  @Test
  func buysAReactionWithoutFormulaUnlessChosenOrOrdered() async {
    let reaction = Node(typeID: 16_000, name: "Reaction Output", activity: .reaction, blueprintTypeID: 26_000, runs: 1)
    let ordered = Node(typeID: 16_001, name: "Ordered Reaction", activity: .reaction, blueprintTypeID: 26_001, runs: 1)
    let decided = Self.plan(
      produced: [reaction, ordered],
      decisions: [reaction.typeID: .produce, ordered.typeID: .produce]
    )
    let script = Script(
      requested: ["Ordered Reaction"],
      bases: [
        Basis(selectedPlan: decided, allocated: []),
        Basis(selectedPlan: decided),
      ],
      results: [.init(plan: decided, failed: false), .init(plan: decided, failed: false)]
    )

    _ = await script.pipeline().run(startingFrom: nil)

    let control = script.basisRequests[1].preferences
    #expect(control[reaction.typeID]?.supplyMode == .buy)
    #expect(control[ordered.typeID]?.supplyMode == .produce)
    #expect(
      PlannerPassDecisions.unusableReactionTypeIDs(
        in: decided,
        allocatedBlueprintTypeIDs: [],
        manualTypeIDs: [reaction.typeID],
        requestedProductNames: []
      ) == [ordered.typeID]
    )
  }

  @Test
  func followsUpMissingBlueprintRunsAtMostTwice() async {
    let short = Self.plan(produced: [Self.component], reservedRuns: [Self.component.blueprintTypeID: 1])
    let script = Script(
      bases: Array(repeating: Basis(selectedPlan: short), count: 4),
      results: Array(repeating: .init(plan: short, failed: false), count: 4)
    )

    let outcome = await script.pipeline().run(startingFrom: nil)

    #expect(Self.completedPlanID(outcome) == short.id)
    #expect(script.calculations.count == 4)
    #expect(
      script.basisRequests.map(\.minimumBlueprintRuns)
        == [[:], [26_100: 3], [26_100: 3], [26_100: 3]]
    )
  }

  @Test
  func calculatesWithoutStockFirstAndPassesItsTotal() async {
    let withoutStock = Self.plan(produced: [Self.component], total: 1_234)
    let withStock = Self.plan(produced: [Self.component], total: 999)
    let script = Script(
      usesStock: true,
      bases: [Basis(selectedPlan: withoutStock), Basis(selectedPlan: withStock)],
      results: [.init(plan: withoutStock, failed: false), .init(plan: withStock, failed: false)]
    )

    let outcome = await script.pipeline().run(startingFrom: nil)

    #expect(Self.completedPlanID(outcome) == withStock.id)
    #expect(script.basisRequests.map(\.calculatesWithoutStock) == [true, false])
    #expect(script.calculations.map(\.calculatesWithoutStock) == [true, false])
    #expect(script.calculations.map(\.stockReferenceProductionCost) == [nil, 1_234])
  }

  @Test
  func stopsAfterAFailedCalculationOrBasis() async {
    let previous = Self.plan(produced: [])
    let failing = Script(
      bases: [Basis(selectedPlan: previous)],
      results: [.init(plan: nil, failed: true)]
    )
    #expect(Self.isStopped(await failing.pipeline().run(startingFrom: previous)))

    let noBasis = Script(bases: [], results: [])
    #expect(Self.isStopped(await noBasis.pipeline().run(startingFrom: previous)))
    #expect(noBasis.calculations.isEmpty)
  }

  @Test
  func stopsWhenTheClickIsCancelled() async {
    let built = Self.plan(produced: [Self.component])
    let script = Script(
      bases: [Basis(selectedPlan: built)],
      results: [.init(plan: built, failed: false)],
      cancelsDuringCalculation: true
    )
    let pipeline = script.pipeline()
    let task = Task { @MainActor in await pipeline.run(startingFrom: nil) }
    script.task = task

    #expect(Self.isStopped(await task.value))
  }

  // MARK: Fixtures

  struct Node {
    let typeID: Int64
    let name: String
    let activity: BlueprintActivityDefinition.Kind
    let blueprintTypeID: Int64
    let runs: Int
  }

  static let component = Node(
    typeID: 16_100,
    name: "Component",
    activity: .manufacturing,
    blueprintTypeID: 26_100,
    runs: 3
  )

  struct Basis: PlannerCalculationBasis {
    let selectedPlan: IndustryPlanSnapshot
    var allocatedBlueprintTypeIDs: Set<Int64>

    init(selectedPlan: IndustryPlanSnapshot, allocated: Set<Int64>? = nil) {
      self.selectedPlan = selectedPlan
      allocatedBlueprintTypeIDs =
        allocated ?? Set(selectedPlan.nodes.compactMap(\.blueprintTypeID))
    }
  }

  @MainActor
  final class Script {
    let manual: [Int64: MaterialProcurementPreference]
    let requested: Set<String>
    let usesStock: Bool
    var bases: [Basis]
    var results: [PlannerCalculationStepResult]
    let cancelsDuringCalculation: Bool
    var task: Task<PlannerCalculationPipeline<Basis>.Outcome, Never>?
    private(set) var basisRequests: [PlannerBasisRequest] = []
    private(set) var calculations: [PlannerCalculationRequest<Basis>] = []

    init(
      manual: [Int64: MaterialProcurementPreference] = [:],
      requested: Set<String> = [],
      usesStock: Bool = false,
      bases: [Basis],
      results: [PlannerCalculationStepResult],
      cancelsDuringCalculation: Bool = false
    ) {
      self.manual = manual
      self.requested = requested
      self.usesStock = usesStock
      self.bases = bases
      self.results = results
      self.cancelsDuringCalculation = cancelsDuringCalculation
    }

    func pipeline() -> PlannerCalculationPipeline<Basis> {
      PlannerCalculationPipeline(
        manualPreferences: manual,
        requestedProductNames: requested,
        usesStock: usesStock,
        resolveBasis: { [self] request in
          basisRequests.append(request)
          return bases.isEmpty ? nil : bases.removeFirst()
        },
        calculate: { [self] request in
          calculations.append(request)
          if cancelsDuringCalculation { task?.cancel() }
          return results.isEmpty
            ? PlannerCalculationStepResult(plan: nil, failed: true)
            : results.removeFirst()
        }
      )
    }
  }

  static func completedPlanID(
    _ outcome: PlannerCalculationPipeline<Basis>.Outcome
  ) -> UUID? {
    guard case .completed(let plan) = outcome else { return nil }
    return plan?.id
  }

  static func isStopped(_ outcome: PlannerCalculationPipeline<Basis>.Outcome) -> Bool {
    if case .stopped = outcome { return true }
    return false
  }

  static func preference(_ mode: MaterialSupplyMode) -> MaterialProcurementPreference {
    MaterialProcurementPreference(supplyMode: mode, purchaseLocation: .jita)
  }

  /// A plan that builds `produced`, chooses `decisions` and has reserved
  /// `reservedRuns` per Blueprint.
  static func plan(
    produced: [Node],
    decisions: [Int64: MaterialSupplyMode] = [:],
    reservedRuns: [Int64: Int]? = nil,
    total: Double? = nil
  ) -> IndustryPlanSnapshot {
    let materials =
      produced.map { node in
        MaterialRequirement(
          typeID: node.typeID, name: node.name, required: 1, fromStock: 0,
          toBuy: 0, toProduce: 1, quote: nil,
          procurement: decisions[node.typeID].map(preference)
        )
      }
      + decisions.keys.sorted().filter { typeID in
        !produced.contains { $0.typeID == typeID }
      }.map { typeID in
        MaterialRequirement(
          typeID: typeID, name: "Material \(typeID)", required: 1, fromStock: 0,
          toBuy: 1, toProduce: 0, quote: nil,
          procurement: decisions[typeID].map(preference)
        )
      }
    var snapshot = IndustryPlanSnapshot(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 100),
      requests: [],
      nodes: produced.map { node in
        PlanNode(
          id: UUID(), typeID: node.typeID, name: node.name,
          requiredQuantity: 1, action: .produce, activity: node.activity,
          runs: node.runs, materialEfficiency: 0, timeEfficiency: 0,
          blueprintTypeID: node.blueprintTypeID, children: [],
          topLevelRequestID: nil
        )
      },
      materials: materials,
      stockAllocations: [],
      jobs: [],
      materialCost: nil,
      installationCost: nil,
      costBreakdown: total.map { total in
        IndustryCostBreakdown(
          materialCost: total, purchasedMaterialCost: total, stockMaterialCost: 0,
          blueprintCosts: BlueprintCostBreakdown(
            entries: [], requestsWithoutEnteredCost: [], total: 0
          ),
          systemIndexCost: 0, facilityTax: 0, sccSurcharge: 0, alphaSurcharge: 0,
          installationCost: 0, logistics: nil, logisticsCost: 0,
          totalProductionCost: total
        )
      },
      immediateSale: emptySale(.immediateSale),
      listedSale: emptySale(.listedSale),
      mainContractSale: nil,
      homeImmediateSale: nil,
      homeListedSale: nil,
      homeContractSale: nil,
      coalitionImmediateSale: nil,
      coalitionListedSale: nil,
      coalitionContractSale: nil,
      totalJobSeconds: 1,
      makespanSeconds: 1,
      warnings: [],
      explanations: [],
      provenance: PlanProvenance(
        sdeBuild: 1,
        esiCompatibilityDate: "fixture",
        snapshotIDs: [],
        priceTimestamp: Date(timeIntervalSince1970: 100),
        ruleVersion: "fixture"
      )
    )
    if let reservedRuns {
      snapshot.blueprintSupplyPlans = reservedRuns.map { blueprintTypeID, runs in
        BlueprintSupplyPlan(
          blueprintTypeID: blueprintTypeID,
          productTypeID: 0,
          productName: "Fixture",
          requiredRuns: runs,
          manufacturingJobs: []
        )
      }
    }
    return snapshot
  }

  static func emptySale(_ scenario: PriceScenario) -> SaleScenarioResult {
    SaleScenarioResult(
      scenario: scenario,
      grossOrNetRevenue: nil,
      profit: nil,
      margin: nil,
      roi: nil,
      quotes: []
    )
  }
}

/// The data of one click is loaded once; failures are asked for again.
@Suite("Planner click data cache")
struct PlannerClickDataCacheTests {
  @Test
  func loadsEachKeyOnceAndRetriesAFailure() async throws {
    let cache = PlannerClickDataCache()
    let counter = LoadCounter()
    let load = PlannerClickLoad(key: "market") { await counter.next() }

    await cache.prefetch(load)
    let first = try await cache.value(load)
    let second = try await cache.value(load)
    #expect(first == 1)
    #expect(second == 1)

    let failing = PlannerClickLoad<Int>(key: "failing") {
      _ = await counter.next()
      throw ESIError.notFound
    }
    await #expect(throws: ESIError.self) { try await cache.value(failing) }
    await #expect(throws: ESIError.self) { try await cache.value(failing) }
    #expect(await counter.count == 3)

    await cache.forget("market")
    #expect(try await cache.value(load) == 4)
  }

  private actor LoadCounter {
    private(set) var count = 0
    func next() -> Int {
      count += 1
      return count
    }
  }
}
