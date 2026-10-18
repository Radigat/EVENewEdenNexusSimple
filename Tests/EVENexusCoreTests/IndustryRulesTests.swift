import Foundation
import Testing

@testable import EVENexusCore

@Suite("Industry rules")
struct IndustryRulesTests {
  @Test
  func roundsManufacturingMaterialsUp() {
    let quantity = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: 7,
      runs: 3,
      materialEfficiency: 10,
      facilityMultiplier: 0.98
    )
    #expect(quantity == 19)
  }

  @Test
  func extremeIndustryArithmeticSaturatesInsteadOfCrashing() {
    let quantity = IndustryPlanner.manufacturingMaterialQuantity(
      baseQuantity: Int64.max,
      runs: Int.max,
      materialEfficiency: 0,
      facilityMultiplier: .greatestFiniteMagnitude
    )
    let makespan = IndustryPlanner.slotMakespan(
      durations: [Int64.max, Int64.max, -1],
      slots: 1
    )

    #expect(quantity == Int64.max)
    #expect(makespan == Int64.max)
  }

  @Test
  func dashboardIndustrySnapshotDecodesEachStoredInputOnce() throws {
    let source = SourceIdentity(
      provider: "Fixture",
      version: "1",
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let character = CharacterIdentity(id: 7, name: "Pilot")
    let capability = CharacterCapabilitySnapshot(
      character: character,
      cloneState: .omega,
      skills: Sourced(
        state: .fresh,
        value: [
          TrainedSkill(
            skillID: IndustrySlotCapacityRules.massProductionSkillTypeID,
            trainedLevel: 3,
            activeLevel: 3,
            skillpoints: 8_000
          ),
          TrainedSkill(
            skillID: IndustrySlotCapacityRules.advancedMassProductionSkillTypeID,
            trainedLevel: 2,
            activeLevel: 2,
            skillpoints: 16_000
          ),
          TrainedSkill(
            skillID: IndustrySlotCapacityRules.laboratoryOperationSkillTypeID,
            trainedLevel: 4,
            activeLevel: 4,
            skillpoints: 32_000
          ),
        ],
        source: source
      ),
      standings: Sourced(state: .fresh, value: [:], source: source)
    )
    let job = ESIIndustryJobDTO(
      activityID: 1,
      blueprintID: 8,
      blueprintTypeID: 9,
      endDate: Date(timeIntervalSince1970: 1_800_000_000),
      facilityID: 10,
      jobID: 11,
      runs: 1,
      status: "active"
    )
    let jobSnapshot = Sourced(
      state: .fresh,
      value: [job],
      source: source
    )

    let snapshot = DashboardIndustrySnapshotBuilder.build(
      inputs: [
        DashboardIndustryCharacterInput(
          characterID: character.id,
          characterName: character.name,
          capabilitySnapshot: try JSONEncoder().encode(capability),
          jobSnapshot: try JSONEncoder().encode(jobSnapshot)
        ),
        DashboardIndustryCharacterInput(
          characterID: 12,
          characterName: "Unavailable",
          capabilitySnapshot: nil,
          jobSnapshot: nil
        ),
      ]
    )

    #expect(snapshot.jobs.count == 1)
    #expect(snapshot.jobs.first?.job.blueprintTypeID == 9)
    #expect(snapshot.jobTypeIDs == [9])
    #expect(snapshot.decodedJobSnapshotCount == 1)
    #expect(snapshot.incompleteJobSourceCount == 1)
    #expect(snapshot.capacity(for: .manufacturing).value == 6)
    #expect(snapshot.capacity(for: .manufacturing).isComplete == false)
    #expect(snapshot.overallCapacity.value == 11)
    #expect(snapshot.overallCapacity.isComplete == false)
  }

  @Test
  func jobMaterialRankingIncludesReadyJobsAndExcludesIncompleteOrClosedJobs() {
    let source = SourceIdentity(provider: "fixture", version: "1")
    func job(_ id: Int64, runs: Int, status: String = "active", product: Int64 = 500, activity: Int = 1) -> ESIIndustryJobDTO {
      ESIIndustryJobDTO(activityID: activity, blueprintID: 700, blueprintTypeID: 701,
        endDate: .distantPast, facilityID: 800, jobID: id, productTypeID: product, runs: runs, status: status)
    }
    let jobs = [job(1, runs: 2), job(2, runs: 10, status: "ready"),
      job(3, runs: 4), job(4, runs: 3), job(5, runs: 1), job(6, runs: 5),
      job(7, runs: 100, status: "delivered"), job(8, runs: 100, status: "cancelled"),
      job(9, runs: 100, product: 501), job(10, runs: 100, status: "reverted"),
      job(11, runs: 2, product: 502, activity: 9)]
    let input = DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture"),
      wallet: Sourced(state: .fresh, value: 0, source: source),
      assets: Sourced(state: .fresh, value: AssetSnapshot(characterID: 7, state: .fresh, items: []), source: source),
      industryJobs: Sourced(state: .fresh, value: jobs, source: source))
    func definition(_ product: Int64, material: Int64, activity: BlueprintActivityDefinition.Kind = .manufacturing) -> BlueprintDefinition {
      BlueprintDefinition(blueprintTypeID: 701, productTypeID: product, maxProductionLimit: 100,
        activity: BlueprintActivityDefinition(kind: activity, durationSeconds: 60,
          materials: [BlueprintMaterial(typeID: material, quantity: 10)],
          products: [BlueprintProduct(typeID: product, quantity: 1, probability: nil)]), source: source)
    }
    let prices = [Int64(34): AdjustedPrice(typeID: 34, adjustedPrice: 2, averagePrice: nil)]
    let definitions = [Int64(500): definition(500, material: 34), 501: definition(501, material: 35), 502: definition(502, material: 34, activity: .reaction)]
    let values = DashboardInProgressIndustryProjector.projectJobs(inputs: [input], prices: prices, definitionsByProductTypeID: definitions)
    let ranked = DashboardInProgressIndustryProjector.rankedJobs(values)
    #expect(values.count == 8)
    #expect(ranked.prefix(5).map { $0.ownedJob.job.jobID } == [2, 6, 3, 4, 1])
    #expect(ranked.first?.materialValue == 200)
    #expect(values.first { $0.ownedJob.job.jobID == 9 }?.materialValue == nil)
    #expect(values.first { $0.ownedJob.job.jobID == 11 }?.materialValue == 40)
    let aggregate = DashboardInProgressIndustryProjector.project(inputs: [input], prices: prices, definitionsByProductTypeID: definitions, jobValues: values)
    #expect(aggregate[7]?.value == ranked.compactMap(\.materialValue).reduce(0, +))
    #expect(aggregate[7]?.unvaluedMaterialTypeCount == 1)
    #expect(aggregate[7]?.estimatedJobCount == 8)
    #expect(aggregate[7]?.isComplete == false)
  }

  @Test
  func reservationsCannotDoubleSpendStock() async throws {
    let ledger = ReservationLedger()
    let first = UUID()
    try await ledger.reserve(
      planID: first,
      requested: [34: 7],
      stock: [34: 10]
    )

    await #expect(throws: ReservationConflict.self) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: 4],
        stock: [34: 10]
      )
    }
  }

  @Test
  func reservationsRejectNegativeOrZeroQuantities() async {
    let ledger = ReservationLedger()

    await #expect(
      throws: ReservationLedgerError.invalidQuantity(
        typeID: 34,
        quantity: -1
      )
    ) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: -1],
        stock: [34: 100]
      )
    }
    await #expect(
      throws: ReservationLedgerError.invalidStock(
        typeID: 34,
        quantity: -1
      )
    ) {
      try await ledger.reserve(
        planID: UUID(),
        requested: [34: 1],
        stock: [34: -1]
      )
    }
  }
}

@Suite("Progress publication throttle")
struct ProgressPublicationThrottleTests {
  @Test
  func coalescesRapidUpdatesAndAlwaysAllowsBoundaries() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var throttle = ProgressPublicationThrottle(minimumInterval: 0.5)

    let initial = throttle.shouldPublish(at: start)
    let rapid = throttle.shouldPublish(at: start.addingTimeInterval(0.1))
    let intervalBoundary = throttle.shouldPublish(
      at: start.addingTimeInterval(0.5)
    )
    let forced = throttle.shouldPublish(
      at: start.addingTimeInterval(0.55),
      force: true
    )
    let afterForced = throttle.shouldPublish(
      at: start.addingTimeInterval(0.6)
    )

    #expect(initial)
    #expect(!rapid)
    #expect(intervalBoundary)
    #expect(forced)
    #expect(!afterForced)

    throttle.reset()
    let afterReset = throttle.shouldPublish(
      at: start.addingTimeInterval(0.61)
    )
    #expect(afterReset)
  }

  @Test
  func clockRollbackStartsANewPublicationWindow() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var throttle = ProgressPublicationThrottle(minimumInterval: 1)

    let initial = throttle.shouldPublish(at: start)
    let afterRollback = throttle.shouldPublish(
      at: start.addingTimeInterval(-1)
    )
    #expect(initial)
    #expect(afterRollback)
  }
}
