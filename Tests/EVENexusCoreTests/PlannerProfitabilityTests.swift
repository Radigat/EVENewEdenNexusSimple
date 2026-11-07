import Foundation
import Testing

@testable import EVENexusCore

@Suite("Planner profitability and steps")
struct PlannerProfitabilityTests {
  private func request(_ name: String = "Ark", line: Int = 1) -> ProductionRequestLine {
    ProductionRequestLine(
      lineNumber: line,
      productName: name,
      wantedQuantity: 1,
      materialEfficiency: 0,
      timeEfficiency: 0
    )
  }

  private func scenario(
    _ market: PlannerTargetMarket = .mainHub,
    profit: Double?,
    revenue: Double? = 100,
    cost: Double? = 80,
    isProvisional: Bool = false
  ) -> PlannerProfitabilityScenario {
    PlannerProfitabilityScenario(
      market: market,
      scenario: market == .allianceMarket ? nil : .listedSale,
      netRevenue: revenue,
      totalCost: cost,
      profit: profit,
      roi: nil,
      isProvisional: isProvisional
    )
  }

  @Test
  func anyFinalProfitAnswersYesAndNamesTheBestOption() {
    let product = PlannerProductProfitability(
      request: request(),
      scenarios: [
        scenario(.mainHub, profit: -5),
        scenario(.homeHub, profit: 20),
        scenario(.coalitionHub, profit: 20),
      ]
    )
    #expect(product.verdict == .profitable)
    #expect(product.best?.market == .homeHub)
  }

  @Test
  func lossAndExactlyZeroAreNotProfitable() {
    for profit in [-1.0, 0.0] {
      let product = PlannerProductProfitability(
        request: request(),
        scenarios: [scenario(profit: profit)]
      )
      #expect(product.verdict == .unprofitable)
    }
  }

  @Test
  func missingPricesAreNotCheckableAndNeverZero() {
    let empty = PlannerProductProfitability(request: request(), scenarios: [])
    #expect(empty.verdict == .notCheckable)
    #expect(empty.best == nil)
    let unknown = PlannerProductProfitability(
      request: request(),
      scenarios: [scenario(profit: nil), scenario(.homeHub, profit: .infinity)]
    )
    #expect(unknown.verdict == .notCheckable)
    #expect(unknown.best == nil)
  }

  @Test
  func provisionalProfitIsNeverAFinalAnswer() {
    let onlyProvisional = PlannerProductProfitability(
      request: request(),
      scenarios: [scenario(profit: 50, isProvisional: true)]
    )
    #expect(onlyProvisional.verdict == .notCheckable)
    let finalLoss = PlannerProductProfitability(
      request: request(),
      scenarios: [
        scenario(.mainHub, profit: 50, isProvisional: true),
        scenario(.homeHub, profit: -1),
      ]
    )
    #expect(finalLoss.verdict == .unprofitable)
    #expect(finalLoss.best?.market == .homeHub)
  }

  @Test
  func allianceCountsAsSaleOption() {
    let product = PlannerProductProfitability(
      request: request(),
      scenarios: [scenario(.mainHub, profit: -10), scenario(.allianceMarket, profit: 30)]
    )
    #expect(product.verdict == .profitable)
    #expect(product.best?.market == .allianceMarket)
    #expect(product.best?.scenario == nil)
  }

  @Test
  func collectivePlanFlagsEachProductAndAddsUpKnownValues() {
    let good = PlannerProductProfitability(
      request: request("Ark"),
      scenarios: [scenario(profit: 20, revenue: 100, cost: 80)]
    )
    let bad = PlannerProductProfitability(
      request: request("Rhea", line: 2),
      scenarios: [scenario(profit: -5, revenue: 95, cost: 100)]
    )
    let unknown = PlannerProductProfitability(
      request: request("Nomad", line: 3),
      scenarios: [scenario(profit: nil)]
    )
    let mixed = PlannerProfitability(products: [good, bad])
    #expect(mixed.verdict == .unprofitable)
    #expect(mixed.needsDecision)
    #expect(mixed.totalProfit == 15)
    #expect(mixed.totalCost == 180)
    #expect(mixed.totalRevenue == 195)

    let incomplete = PlannerProfitability(products: [good, unknown])
    #expect(incomplete.verdict == .notCheckable)
    #expect(incomplete.totalProfit == nil)
    #expect(PlannerProfitability(products: [bad, unknown]).verdict == .unprofitable)
    #expect(PlannerProfitability(products: [good]).needsDecision == false)
  }

  @Test
  func saleFiguresIncludeTheTransportOfTheSelectedSale() {
    let costs = PlannerProductCosts(
      requestID: UUID(),
      typeID: 1,
      productName: "Ark",
      units: 2,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 30,
      inboundLogisticsCost: 50,
      outboundShare: 1
    )
    func sale(cost: Double?, fee: Double?, sold: Int64? = nil) -> PlannerProfitabilityScenario {
      PlannerProfitabilityScenario(
        market: .coalitionHub,
        scenario: .listedSale,
        netRevenue: 400,
        totalCost: cost,
        profit: cost.map { 400 - $0 },
        roi: nil,
        isProvisional: false,
        feeRate: fee,
        soldQuantity: sold
      )
    }
    let transported = PlannerSaleFigures(
      costs: costs,
      units: 2,
      sale: sale(cost: 240, fee: 0.5)
    )
    #expect(transported.cost == 240)
    #expect(transported.costPerItem == 120)
    #expect(transported.minimumPrice == 240)
    // Revenue minus the shown cost is the shown profit.
    #expect(400 - (transported.cost ?? 0) == 160)

    let partial = PlannerSaleFigures(
      costs: costs,
      units: 2,
      sale: sale(cost: 200, fee: 0.5, sold: 1)
    )
    #expect(partial.costPerItem == 100)
    #expect(partial.minimumPrice == 400)

    let withoutSale = PlannerSaleFigures(costs: costs, units: 2, sale: nil)
    #expect(withoutSale.cost == 200)
    #expect(withoutSale.minimumPrice == nil)
    #expect(
      PlannerSaleFigures(costs: costs, units: 2, sale: sale(cost: 200, fee: nil)).minimumPrice
        == nil
    )
    #expect(
      PlannerSaleFigures(costs: costs, units: 2, sale: sale(cost: 200, fee: 1)).minimumPrice
        == nil
    )
    #expect(PlannerSaleFigures(costs: nil, units: nil, sale: nil).cost == nil)
  }

  @Test
  func warningTextKeepsTheEnglishMessageAndReadsOlderPlans() throws {
    let warning = DomainWarning(
      code: "logistics.single-item-volume-exceeded",
      format: IndustryWarningText.courierItemTooLarge,
      arguments: ["Ark", "1.300.000", "350.000"],
      severity: .warning
    )
    #expect(
      warning.message
        == "Ark is too large for a courier contract: 1.300.000 m³ packaged exceeds the configured 350.000 m³ contract limit. Transfer it manually."
    )
    #expect(warning.text?.arguments.first == "Ark")
    let decoded = try JSONDecoder().decode(
      DomainWarning.self,
      from: JSONEncoder().encode(warning)
    )
    #expect(decoded == warning)
    let older = """
      {"id":"\(UUID().uuidString)","code":"a","message":"b","severity":"warning"}
      """
    let old = try JSONDecoder().decode(DomainWarning.self, from: Data(older.utf8))
    #expect(old.text == nil)
    #expect(old.message == "b")
  }

  private func capability(
    id: Int64 = 7,
    skills: [Int64: Int]?
  ) -> CharacterCapabilitySnapshot {
    let source = SourceIdentity(provider: "fixture", version: "1")
    return CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: id, name: "Pilot"),
      cloneState: .omega,
      skills: Sourced(
        state: skills == nil ? .unavailable : .fresh,
        value: skills.map { levels in
          levels.map {
            TrainedSkill(skillID: $0.key, trainedLevel: $0.value, activeLevel: $0.value, skillpoints: 0)
          }
        },
        source: source
      ),
      standings: Sourced(state: .fresh, value: [:], source: source)
    )
  }

  /// The Ark job from the EVE job window: base 3.600.000 s, TE 4, facility 0,406.
  @Test
  func jobDurationMatchesTheEVEJobWindow() {
    let profile = IndustryJobTimeProfile(
      characterID: 7,
      characterName: "Pilot",
      snapshot: capability(skills: [3380: 5, 3388: 5, 11444: 5, 11529: 5, 22242: 5]),
      implants: []
    )
    let factor = profile.multiplier(
      for: .manufacturing,
      requiredSkillTypeIDs: [11444, 11529, 22242, 3380]
    )
    let seconds: Double = (3_600_000.0 * 0.406 * 0.96 * factor).rounded(.up)
    // 9 d 23:11:45 in the job window.
    let jobWindow: Double = 861_105
    #expect(seconds == jobWindow)
  }

  @Test
  func timeProfileAppliesEachBonusOnlyToItsActivity() {
    func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 1e-9 }
    let profile = IndustryJobTimeProfile(
      characterID: 7,
      characterName: "Pilot",
      snapshot: capability(
        skills: [3380: 5, 3388: 5, 45746: 5, 3402: 4, 3403: 3, 3409: 2, 81896: 1]
      ),
      implants: [.industryBX804, .researchRR605, .metallurgyMY703]
    )
    #expect(close(profile.multiplier(for: .manufacturing), 0.8 * 0.85 * 0.96))
    // A science skill counts only when the blueprint requires it; Mutagenic counts 2 %.
    #expect(
      close(
        profile.multiplier(for: .manufacturing, requiredSkillTypeIDs: [81896, 3380]),
        0.8 * 0.85 * 0.96 * 0.98
      )
    )
    #expect(close(profile.multiplier(for: .reaction), 0.8))
    #expect(close(profile.multiplier(for: .copying), 0.8 * 0.85))
    #expect(close(profile.multiplier(for: .timeResearch), 0.85 * 0.85 * 0.95))
    #expect(close(profile.multiplier(for: .materialResearch), 0.9 * 0.85 * 0.97))
    #expect(close(profile.multiplier(for: .invention), 0.85))

    let withoutSkills = IndustryJobTimeProfile(
      characterID: 7,
      characterName: "Pilot",
      snapshot: capability(skills: nil),
      implants: [.industryBX804]
    )
    #expect(!withoutSkills.hasSkills)
    #expect(close(withoutSkills.multiplier(for: .manufacturing), 0.96))
  }

  @Test
  func implantSlotsHoldOneImplantPerCharacterAndLocation() {
    var crew = IndustryLocationCrew()
    crew.setTimeImplant(.scienceSC801, inSlot: 8, for: 7)
    crew.setTimeImplant(.researchRR601, inSlot: 6, for: 7)
    crew.setTimeImplant(.scienceSC805, inSlot: 8, for: 7)
    #expect(crew.timeImplant(inSlot: 8, for: 7) == .scienceSC805)
    #expect(crew.timeImplants(for: 7).count == 2)
    #expect(crew.timeImplants(for: 8).isEmpty)
    crew.setTimeImplant(nil, inSlot: 8, for: 7)
    crew.setTimeImplant(nil, inSlot: 6, for: 7)
    #expect(crew.timeImplantsByCharacterID.isEmpty)
    #expect(IndustryTimeImplant.industryBX804.shortName == "BX-804")
    #expect(IndustryTimeImplant.slots(for: .manufacturing) == [8])
    #expect(IndustryTimeImplant.slots(for: .science) == [6, 7, 8])
    // The SDE has no implant that shortens reactions.
    #expect(IndustryTimeImplant.slots(for: .reaction).isEmpty)
  }

  @Test
  func productCharacterKeepsTheChoiceAndFallsBackPredictably() {
    var scheduling = ProductionSchedulingConfiguration()
    scheduling.characterAssignments = [
      CharacterIndustryAssignment(characterID: 3, characterName: "C", isEnabled: true)
    ]
    func effective(_ saved: Int64?, _ ids: [Int64]) -> Int64? {
      IndustryJobTimeProfile.effectiveCharacterID(
        saved: saved,
        characterIDs: ids,
        scheduling: scheduling
      )
    }
    #expect(effective(2, [1, 2, 3]) == 2)
    #expect(effective(9, [1, 2, 3]) == 3)
    #expect(effective(nil, [1, 2, 3]) == 3)
    #expect(effective(nil, [2, 1]) == 2)
    #expect(effective(nil, []) == nil)
  }

  @Test
  func jobsFollowTheirProductCharacterWhereTheCrewIncludesThem() {
    var factory = ConfiguredIndustryStructure(name: "Factory", kind: .npcStation)
    factory.setCrewMember(true, characterID: 2, pool: .manufacturing)
    factory.setCrewMember(true, characterID: 1, pool: .manufacturing)
    factory.setCrewMember(true, characterID: 3, pool: .science)
    var open = ConfiguredIndustryStructure(name: "Open", kind: .npcStation)
    open.setCrewMember(true, characterID: 9, pool: .manufacturing)
    open.setCrewMember(false, characterID: 9, pool: .manufacturing)
    #expect(open.crew(for: .manufacturing).characterIDs.isEmpty)
    let assignment = IndustryJobCharacterAssignment(
      productCharacterIDs: [100: 2, 200: 3],
      characters: [
        CharacterIdentity(id: 1, name: "Berta"),
        CharacterIdentity(id: 2, name: "Anton"),
        CharacterIdentity(id: 3, name: "Carla"),
      ],
      capabilities: [],
      structures: [factory, open]
    )
    func name(
      _ owner: Int64?,
      _ structure: UUID?,
      _ pool: IndustrySlotPool = .manufacturing
    ) -> String? {
      assignment.profile(ownerProductTypeID: owner, pool: pool, structureID: structure)?
        .characterName
    }
    // The product's character where the crew includes that character.
    #expect(name(100, factory.id) == "Anton")
    // Not in the crew: the crew's first by name.
    #expect(name(200, factory.id) == "Anton")
    // Each kind of job has its own crew.
    #expect(name(200, factory.id, .science) == "Carla")
    #expect(name(100, factory.id, .science) == "Carla")
    // A location without a crew allows everyone.
    #expect(name(200, factory.id, .reaction) == "Carla")
    #expect(name(200, open.id) == "Carla")
    #expect(name(200, nil) == "Carla")
    // No owner: only a location with a crew can name someone.
    #expect(name(nil, factory.id) == "Anton")
    #expect(name(nil, open.id) == nil)
  }

  @Test
  func implantsCountOnlyAtTheirLocationAndForTheirKindOfJob() throws {
    var first = ConfiguredIndustryStructure(name: "First", kind: .npcStation)
    first.setTimeImplant(.industryBX804, inSlot: 8, characterID: 1, pool: .manufacturing)
    first.setTimeImplant(.scienceSC805, inSlot: 8, characterID: 1, pool: .science)
    let second = ConfiguredIndustryStructure(name: "Second", kind: .npcStation)
    let assignment = IndustryJobCharacterAssignment(
      productCharacterIDs: [100: 1],
      characters: [CharacterIdentity(id: 1, name: "Anton")],
      capabilities: [],
      structures: [first, second]
    )
    func factor(_ structure: UUID, _ pool: IndustrySlotPool, _ kind: BlueprintActivityDefinition.Kind)
      throws -> Double
    {
      try #require(
        assignment.profile(ownerProductTypeID: 100, pool: pool, structureID: structure)
      ).multiplier(for: kind)
    }
    #expect(try factor(first.id, .manufacturing, .manufacturing) == 0.96)
    #expect(try factor(first.id, .science, .copying) == 0.95)
    #expect(try factor(second.id, .manufacturing, .manufacturing) == 1)
  }

  @Test
  func locationsOfferOnlyTheKindsOfJobsTheyCanRun() {
    let tatara = ConfiguredIndustryStructure(
      name: "Tatara",
      kind: .tatara,
      securityStatus: -0.4,
      serviceModules: nil,
      activityAssignmentMode: .manual,
      manuallyEnabledActivities: [.reaction]
    )
    #expect(tatara.jobPools == [.reaction])
    let sotiyo = ConfiguredIndustryStructure(
      name: "Sotiyo",
      kind: .sotiyo,
      securityStatus: -0.4,
      activityAssignmentMode: .manual,
      manuallyEnabledActivities: [.manufacturing]
    )
    #expect(sotiyo.jobPools == [.manufacturing])
    let station = ConfiguredIndustryStructure(
      name: "Station",
      kind: .npcStation,
      securityStatus: 0.9
    )
    #expect(station.jobPools.contains(.manufacturing))
    #expect(station.jobPools.contains(.science))
    #expect(!station.jobPools.contains(.reaction))
  }

  @Test
  func crewsSurviveSavingAndOlderChoicesMoveToTheLocations() throws {
    var factory = ConfiguredIndustryStructure(
      name: "Factory",
      kind: .sotiyo,
      securityStatus: -0.4,
      activityAssignmentMode: .manual,
      manuallyEnabledActivities: [.manufacturing, .copying]
    )
    factory.productionCharacterIDs = [5]
    var reactor = ConfiguredIndustryStructure(
      name: "Reactor",
      kind: .tatara,
      securityStatus: -0.4,
      activityAssignmentMode: .manual,
      manuallyEnabledActivities: [.reaction]
    )
    reactor.productionCharacterIDs = [6]
    var open = ConfiguredIndustryStructure(
      name: "Open",
      kind: .sotiyo,
      securityStatus: -0.4,
      activityAssignmentMode: .manual,
      manuallyEnabledActivities: [.manufacturing]
    )
    open.setTimeImplant(.industryBX801, inSlot: 8, characterID: 7, pool: .manufacturing)
    var scheduling = ProductionSchedulingConfiguration()
    var worn = CharacterIndustryAssignment(characterID: 5, characterName: "Worn")
    worn.timeImplants = [.industryBX804, .scienceSC805]
    var outside = CharacterIndustryAssignment(characterID: 7, characterName: "Outside")
    outside.timeImplants = [.industryBX804]
    scheduling.setAssignment(worn)
    scheduling.setAssignment(outside)
    var basis = ProductionBasis(scheduling: scheduling)
    basis.manufacturingSystems[0].securityStatus = -0.4
    basis.manufacturingSystems[0].solarSystemID = 30_000_999
    basis.structures = [factory, reactor, open].map { structure in
      var structure = structure
      structure.solarSystemID = 30_000_999
      return structure
    }

    let decoded = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(basis)
    )
    let decodedFactory = try #require(decoded.structure(id: factory.id))
    let decodedReactor = try #require(decoded.structure(id: reactor.id))
    let decodedOpen = try #require(decoded.structure(id: open.id))
    // A list saved earlier means the job kind the location was ticked for.
    #expect(decodedFactory.crew(for: .manufacturing).characterIDs == [5])
    #expect(decodedFactory.productionCharacterIDs == nil)
    #expect(decodedReactor.crew(for: .reaction).characterIDs == [6])
    #expect(decodedReactor.crew(for: .manufacturing).characterIDs.isEmpty)
    // Implants go where the character may run that kind of job.
    #expect(decodedFactory.crew(for: .manufacturing).timeImplants(for: 5) == [.industryBX804])
    #expect(decodedFactory.crew(for: .science).timeImplants(for: 5) == [.scienceSC805])
    #expect(decodedOpen.crew(for: .manufacturing).timeImplants(for: 5) == [.industryBX804])
    // Not at a location whose crew excludes the character, and no overwriting.
    #expect(decodedFactory.crew(for: .manufacturing).timeImplants(for: 7).isEmpty)
    #expect(decodedOpen.crew(for: .manufacturing).timeImplants(for: 7) == [.industryBX801])
    #expect(decoded.scheduling.characterAssignments.allSatisfy { $0.timeImplants == nil })

    // Saving and loading again keeps the result, also after unticking everyone.
    var edited = decoded
    edited.structures[0].setCrewMember(false, characterID: 5, pool: .manufacturing)
    let again = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(edited)
    )
    #expect(again.structure(id: factory.id)?.crew(for: .manufacturing).characterIDs == [])
    #expect(again.structure(id: open.id)?.crew(for: .manufacturing).timeImplants(for: 5) == [.industryBX804])
  }

  @Test
  func schedulerUsesOnlyTheSlotsOfTheLocationsCrew() {
    func job(_ allowed: Set<Int64>?) -> IndustryScheduledJob {
      IndustryScheduledJob(
        activity: .manufacturing,
        durationSeconds: 10,
        allowedCharacterIDs: allowed
      )
    }
    func group(_ characterID: Int64?, count: Int) -> IndustrySlotGroup {
      IndustrySlotGroup(
        characterID: characterID,
        pool: .manufacturing,
        count: count,
        activities: [.manufacturing]
      )
    }
    let groups = [group(1, count: 5), group(2, count: 1)]
    func makespan(_ jobs: [IndustryScheduledJob], _ groups: [IndustrySlotGroup]) -> Int64? {
      IndustrySlotScheduler.schedule(jobs: jobs, groups: groups).makespanSeconds
    }
    #expect(makespan([job(nil), job(nil)], groups) == 10)
    #expect(makespan([job([2]), job([2])], groups) == 20)
    #expect(makespan([job([1]), job([2])], groups) == 10)
    let unplaceable = IndustrySlotScheduler.schedule(jobs: [job(nil), job([3])], groups: groups)
    #expect(unplaceable.makespanSeconds == nil)
    #expect(unplaceable.unschedulableActivities == [.manufacturing])
    // The fallback slot without any enabled character belongs to no one.
    #expect(makespan([job([3])], [group(nil, count: 1)]) == 10)
  }

  @Test
  func stepsOpenOnlyWithTheirPrerequisites() {
    let empty = PlannerStepAccess(
      isInputReady: false, hasPlan: false, isProfitabilityCleared: false
    )
    #expect(empty.isReachable(.settings) && empty.isReachable(.products))
    #expect(!empty.isReachable(.stock) && !empty.isReachable(.costs))
    #expect(empty.next(after: .products) == nil)

    let ready = PlannerStepAccess(
      isInputReady: true, hasPlan: false, isProfitabilityCleared: false
    )
    #expect(ready.next(after: .products) == .stock)
    #expect(ready.next(after: .stock) == nil)

    let uncleared = PlannerStepAccess(
      isInputReady: true, hasPlan: true, isProfitabilityCleared: false
    )
    #expect(uncleared.next(after: .stock) == .costs)
    #expect(uncleared.next(after: .costs) == nil)
    #expect(uncleared.clamped(.sale) == .costs)

    let cleared = PlannerStepAccess(
      isInputReady: false, hasPlan: true, isProfitabilityCleared: true
    )
    #expect(PlannerStep.allCases.filter { $0 > .stock }.allSatisfy(cleared.isReachable))
    #expect(cleared.previous(before: .costs) == .products)
    #expect(cleared.next(after: .sale) == nil)
  }

  @Test
  func startStepDependsOnASavedPlan() {
    #expect(PlannerStep.start(hasPlan: false) == .settings)
    #expect(PlannerStep.start(hasPlan: true) == .costs)
  }

  @Test
  func calculationLeadsToTheCostsUnlessItStartedLaterAndIsCleared() {
    let cleared = PlannerStepAccess(
      isInputReady: true, hasPlan: true, isProfitabilityCleared: true
    )
    #expect(cleared.step(afterCalculationFrom: .stock) == .costs)
    #expect(cleared.step(afterCalculationFrom: .jobs) == .jobs)
    let uncleared = PlannerStepAccess(
      isInputReady: true, hasPlan: true, isProfitabilityCleared: false
    )
    #expect(uncleared.step(afterCalculationFrom: .jobs) == .costs)
  }

  @Test
  func stockNoIgnoresTheManualListWithoutDeletingIt() {
    #expect(PlannerStockUse.manualStockInput("Tritanium | 5", usesStock: true) == "Tritanium | 5")
    #expect(PlannerStockUse.manualStockInput("Tritanium | 5", usesStock: false) == "")
  }

  @Test
  func unknownProductNamesLineAndNameInItsMessage() {
    let error = IndustryPlannerError.unknownProduct(line: 3, name: "Rheag")
    #expect(error.errorDescription?.contains("Line 3") == true)
    #expect(error.errorDescription?.contains("Rheag") == true)
    #expect(error.localizedDescription == error.errorDescription)
  }

  @Test
  func aStoppedCalculationIsNeverReportedAsOutdated() {
    #expect(
      PlannerCalculationStatus.resolve(
        isCalculating: false,
        hasError: true,
        hasPlan: true,
        startedThisSession: true,
        matchesCompletedCalculation: false,
        hasChangesSinceOpening: true
      ) == .failed
    )
  }

  @Test
  func theVerdictFollowsTheSelectedSaleAndTheBestIsOnlyTheSuggestion() {
    let scenarios = [scenario(.mainHub, profit: -5), scenario(.homeHub, profit: 20)]
    let suggested = PlannerProductProfitability(request: request(), scenarios: scenarios)
    #expect(suggested.isSuggestion)
    #expect(suggested.selected?.market == .homeHub)
    #expect(suggested.verdict == .profitable)

    let chosenLoss = PlannerProductProfitability(
      request: request(),
      scenarios: scenarios,
      choice: PlannerSaleChoice(market: .mainHub, scenario: .listedSale)
    )
    #expect(!chosenLoss.isSuggestion)
    #expect(chosenLoss.selected?.market == .mainHub)
    #expect(chosenLoss.best?.market == .homeHub)
    #expect(chosenLoss.verdict == .unprofitable)
  }

  @Test
  func aHubChoiceWithoutScenarioMeansTheListedSale() {
    let product = PlannerProductProfitability(
      request: request(),
      scenarios: [scenario(.mainHub, profit: 7)],
      choice: PlannerSaleChoice(market: .mainHub, scenario: nil)
    )
    #expect(!product.isSuggestion)
    #expect(product.selected?.profit == 7)
  }

  @Test
  func aChoiceTheNewCalculationNoLongerHasFallsBackToTheSuggestion() {
    let product = PlannerProductProfitability(
      request: request(),
      scenarios: [scenario(.mainHub, profit: 7)],
      choice: PlannerSaleChoice(market: .coalitionHub, scenario: .listedSale)
    )
    #expect(product.isSuggestion)
    #expect(product.selected?.market == .mainHub)
  }

  @Test
  func theAllianceSaleCanAlwaysBeChosenAndStaysUncheckableWithoutAPrice() {
    let scenarios = [scenario(.mainHub, profit: 7), scenario(.homeHub, profit: nil)]
    let unchosen = PlannerProductProfitability(request: request(), scenarios: scenarios)
    #expect(unchosen.options.map(\.market) == [.mainHub, .homeHub, .allianceMarket])

    let chosen = PlannerProductProfitability(
      request: request(),
      scenarios: scenarios,
      choice: PlannerSaleChoice(market: .allianceMarket, scenario: nil)
    )
    #expect(chosen.selected?.market == .allianceMarket)
    #expect(chosen.selected?.profit == nil)
    #expect(chosen.verdict == .notCheckable)
  }

  @Test
  func optionsListTheHighestProfitFirst() {
    let product = PlannerProductProfitability(
      request: request(),
      scenarios: [
        scenario(.mainHub, profit: 1),
        scenario(.homeHub, profit: 30),
        scenario(.coalitionHub, profit: 12),
        scenario(.allianceMarket, profit: 20),
      ]
    )
    #expect(
      product.options.map(\.market) == [.homeHub, .allianceMarket, .coalitionHub, .mainHub]
    )
  }

  @Test
  func productCostsGiveSubtotalCostPerItemAndMinimumPrice() {
    let costs = PlannerProductCosts(
      requestID: UUID(),
      typeID: 1,
      productName: "Ark",
      units: 2,
      materialCost: 100,
      installationCost: 20,
      blueprintCost: 30,
      inboundLogisticsCost: 50,
      outboundShare: 1
    )
    #expect(costs.productionSubtotal == 150)
    #expect(costs.totalCost == 200)
    #expect(costs.costPerUnit == 100)

    let unknown = PlannerProductCosts(
      requestID: UUID(),
      typeID: 1,
      productName: "Ark",
      units: 2,
      materialCost: nil,
      installationCost: 20,
      blueprintCost: 30,
      inboundLogisticsCost: 50,
      outboundShare: 1
    )
    #expect(unknown.productionSubtotal == nil)
    #expect(unknown.costPerUnit == nil)
  }

  @Test
  func manualStockReplacesTheWarehouseInTheBlueprintResolution() {
    let manual: [Int64: Int64] = [34: 5]
    #expect(
      PlannerStockUse.blueprintStockOverride(manualStock: manual, calculatesWithoutStock: false)
        == manual
    )
    #expect(
      PlannerStockUse.blueprintStockOverride(manualStock: manual, calculatesWithoutStock: true)
        == [:]
    )
  }

  @Test
  func withoutManualStockTheBlueprintResolutionKeepsTheWarehouse() {
    #expect(
      PlannerStockUse.blueprintStockOverride(manualStock: [:], calculatesWithoutStock: false) == nil
    )
    #expect(
      PlannerStockUse.blueprintStockOverride(manualStock: [:], calculatesWithoutStock: true) == nil
    )
    #expect(!PlannerStockUse.hasManualStock(" \n\t"))
    #expect(PlannerStockUse.hasManualStock("Tritanium | 5"))
  }

  @Test
  func removingTakesOutExactlyTheLineOfTheJob() throws {
    let input = "Ark 1 0 0\n\nRhea 2 10 20\nRhea 1 0 0\nNomad 1 0 0"
    let requests = ProductionInputParser.parse(input).requests
    let rhea = try #require(requests.first { $0.wantedQuantity == 1 && $0.productName == "Rhea" })
    let remaining = try #require(ProductionInputFormatter.removing(rhea, from: input))
    #expect(remaining == "Ark 1 0 0\n\nRhea 2 10 20\nNomad 1 0 0")
    // Line numbers shift after a removal; the next product is still found.
    let nomad = try #require(requests.last)
    #expect(ProductionInputFormatter.removing(nomad, from: remaining) == "Ark 1 0 0\n\nRhea 2 10 20")
    // Already gone: nothing to remove, the input stays untouched.
    #expect(ProductionInputFormatter.removing(rhea, from: remaining) == nil)
  }
}
