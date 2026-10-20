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

@Suite("Net worth blueprint valuation")
struct NetWorthBlueprintValuationTests {
  private let source = SourceIdentity(
    provider: "ESI",
    version: EVEConstants.esiCompatibilityDate,
    capturedAt: Date(timeIntervalSince1970: 1_000),
    snapshotID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  )

  private var blueprintClassification: IndustryItemClassification {
    IndustryItemClassification(
      categoryName: "Blueprint", groupName: "Ship Blueprint", manufacturingCategory: .module)
  }

  private func asset(
    id: Int64, typeID: Int64, quantity: Int64 = 1, singleton: Bool = true, flag: Bool? = nil
  ) -> AssetItem {
    AssetItem(
      id: id, typeID: typeID, quantity: quantity, locationID: 60_003_760,
      locationKind: .station, locationFlag: "Hangar", singleton: singleton,
      isBlueprintCopy: flag)
  }

  private func record(
    id: Int64, typeID: Int64, quantity: Int64, runs: Int, me: Int, te: Int
  ) -> OwnedBlueprintInstance {
    OwnedBlueprintInstance(
      id: id, blueprintTypeID: typeID, locationID: 60_003_760, quantity: quantity,
      runs: runs, materialEfficiency: me, timeEfficiency: te, source: source)
  }

  private func definition(typeID: Int64, basePrice: Double) -> BlueprintResearchDefinition {
    BlueprintResearchDefinition(
      blueprintTypeID: typeID, blueprintName: "Fixture Blueprint", basePrice: basePrice,
      manufacturingMaterials: [BlueprintMaterial(typeID: 34, quantity: 1_000)],
      materialResearchTimeSeconds: 60, timeResearchTimeSeconds: 60, source: source)
  }

  private func facility(_ activity: BlueprintResearchActivity) -> BlueprintResearchFacilityContext {
    BlueprintResearchFacilityContext(
      activity: activity, solarSystemID: 30_000_142, solarSystemName: "Jita",
      facilityName: "Fixture", systemCostIndex: 0.05, jobCostMultiplier: 1,
      facilityTaxRate: 0, sccSurchargeRate: 0.04, alphaSurchargeRate: 0,
      needsReview: false, source: source)
  }

  private func pricing(withFacilities: Bool) -> BlueprintResearchPricingInput {
    BlueprintResearchPricingInput(
      adjustedPrices: prices.prices, adjustedPriceSource: source,
      materialFacility: withFacilities ? facility(.materialEfficiency) : nil,
      timeFacility: withFacilities ? facility(.timeEfficiency) : nil)
  }

  private var prices: ReferencePriceSnapshot {
    ReferencePriceSnapshot(
      capturedAt: source.capturedAt,
      prices: [
        34: AdjustedPrice(typeID: 34, adjustedPrice: 4, averagePrice: 5),
        // The ESI price of a blueprint type is the original's price and must
        // never be used for copies.
        901: AdjustedPrice(typeID: 901, adjustedPrice: 9_000_000, averagePrice: 9_000_000),
      ], source: source)
  }

  private func offer(contractID: Int64, typeID: Int64, runs: Int, price: Double)
    -> PublicContractSearchResult
  {
    PublicContractSearchResult(
      contractID: contractID, recordID: contractID, regionID: 10_000_002,
      regionName: "The Forge", contractType: "item_exchange", price: price,
      dateIssued: source.capturedAt, dateExpired: source.capturedAt.addingTimeInterval(86_400),
      startLocationID: 60_003_760, typeID: typeID, isIncluded: true, quantity: 1,
      isBlueprintCopy: true, materialEfficiency: 10, timeEfficiency: 20, runs: runs,
      offeredLineCount: 1, requestedLineCount: 0)
  }

  private func input(items: [AssetItem], records: [OwnedBlueprintInstance])
    -> DashboardWealthCharacterInput
  {
    DashboardWealthCharacterInput(
      character: CharacterIdentity(id: 7, name: "Fixture", corporationID: 98_000_001),
      wallet: Sourced(state: .fresh, value: 0, source: source),
      assets: Sourced(
        state: .fresh, value: AssetSnapshot(characterID: 7, state: .fresh, items: items),
        source: source),
      openOrders: Sourced(state: .fresh, value: [], source: source),
      privateContracts: Sourced(
        state: .fresh,
        value: PrivateContractSnapshot(characterID: 7, itemContracts: [], inTransitCouriers: []),
        source: source),
      blueprints: Sourced(state: .fresh, value: records, source: source)
    )
  }

  private var fixtureItems: [AssetItem] {
    [
      asset(id: 1, typeID: 900),  // researched BPO with ESI record
      asset(id: 2, typeID: 901, flag: true),  // BPC with Contract offers
      asset(id: 3, typeID: 902, flag: true),  // BPC without Contract offer
      asset(id: 4, typeID: 903),  // single blueprint without record or flag
      asset(id: 5, typeID: 904, quantity: 3, singleton: false),  // packaged BPO stack
    ]
  }

  private var fixtureRecords: [OwnedBlueprintInstance] {
    [
      record(id: 1, typeID: 900, quantity: -1, runs: -1, me: 1, te: 2),
      record(id: 2, typeID: 901, quantity: -2, runs: 10, me: 10, te: 20),
      record(id: 3, typeID: 902, quantity: -2, runs: 5, me: 0, te: 0),
    ]
  }

  private func valuation(withFacilities: Bool) -> DashboardWealthBlueprintValuation {
    DashboardBlueprintValuationBuilder.build(
      inputs: [input(items: fixtureItems, records: fixtureRecords)],
      definitions: [
        900: definition(typeID: 900, basePrice: 1_000_000),
        904: definition(typeID: 904, basePrice: 2_000),
      ],
      pricing: pricing(withFacilities: withFacilities),
      copyOffers: [
        901: [
          offer(contractID: 11, typeID: 901, runs: 5, price: 500),
          offer(contractID: 12, typeID: 901, runs: 2, price: 150),
        ]
      ]
    )
  }

  private var classifications: [Int64: IndustryItemClassification] {
    [
      900: blueprintClassification, 901: blueprintClassification,
      902: blueprintClassification, 903: blueprintClassification,
      904: blueprintClassification,
    ]
  }

  @Test
  func originalsUseResearchReplacementAndCopiesUseLowestContractRunPrice() throws {
    let snapshot = DashboardWealthProjector.project(
      inputs: [input(items: fixtureItems, records: fixtureRecords)],
      prices: prices,
      assetClassifications: classifications,
      blueprintValuation: valuation(withFacilities: true)
    )
    let character = try #require(snapshot.characters.first)
    // Research base cost 1,000 × 4 ISK; one ME and one TE level at
    // 2 % × fee factor 0.09 each: 2 × 7.2 ISK.
    let researchedOriginal = 1_000_000 + 14.4
    let packagedOriginals = 3 * 2_000.0
    let copy = 10 * 75.0
    #expect(abs((character.blueprintOriginalValue ?? 0) - (researchedOriginal + packagedOriginals)) < 0.001)
    #expect(character.blueprintOriginalCount == 2)
    #expect(character.estimatedBlueprintOriginalCount == 0)
    #expect(character.blueprintCopyValue == copy)
    #expect(character.valuedBlueprintCopyCount == 1)
    #expect(character.excludedBlueprintCopyCount == 1)
    #expect(character.unknownBlueprintStatusCount == 1)
    #expect(character.unvaluedAssetTypeCount == 0)
    #expect(
      abs((character.assetValue ?? 0) - (researchedOriginal + packagedOriginals + copy)) < 0.001)
    // The unresolved single blueprint keeps the snapshot partial.
    #expect(!character.isComplete)
    #expect(snapshot.valuationPolicy.hasSuffix("v4"))
    let decoded = try JSONDecoder().decode(
      DashboardWealthSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded == snapshot)
  }

  @Test
  func originalWithoutResearchFacilityFallsBackToBasePriceAsVisibleEstimate() throws {
    let items = [asset(id: 1, typeID: 900)]
    let records = [record(id: 1, typeID: 900, quantity: -1, runs: -1, me: 1, te: 2)]
    let snapshot = DashboardWealthProjector.project(
      inputs: [input(items: items, records: records)],
      prices: prices,
      assetClassifications: classifications,
      blueprintValuation: valuation(withFacilities: false)
    )
    let character = try #require(snapshot.characters.first)
    #expect(character.assetValue == 1_000_000)
    #expect(character.estimatedBlueprintOriginalCount == 1)
    #expect(!character.isComplete)
    #expect(character.freshness == .partial)
  }

  @Test
  func unresearchedOriginalNeedsNoResearchFacility() throws {
    let items = [asset(id: 1, typeID: 900)]
    let records = [record(id: 1, typeID: 900, quantity: -1, runs: -1, me: 0, te: 0)]
    let snapshot = DashboardWealthProjector.project(
      inputs: [input(items: items, records: records)],
      prices: prices,
      assetClassifications: classifications,
      blueprintValuation: DashboardBlueprintValuationBuilder.build(
        inputs: [input(items: items, records: records)],
        definitions: [900: definition(typeID: 900, basePrice: 1_000_000)],
        pricing: pricing(withFacilities: false)
      )
    )
    let character = try #require(snapshot.characters.first)
    #expect(character.assetValue == 1_000_000)
    #expect(character.estimatedBlueprintOriginalCount == 0)
    #expect(character.isComplete)
  }

  @Test
  func lowestCopyRunPriceIgnoresOriginalsAndBundles() {
    var bundle = offer(contractID: 20, typeID: 901, runs: 100, price: 1)
    bundle = PublicContractSearchResult(
      contractID: bundle.contractID, recordID: bundle.recordID, regionID: bundle.regionID,
      regionName: bundle.regionName, contractType: "item_exchange", price: 1,
      dateIssued: bundle.dateIssued, dateExpired: bundle.dateExpired, typeID: 901,
      isIncluded: true, quantity: 1, isBlueprintCopy: true, materialEfficiency: 10,
      timeEfficiency: 20, runs: 100, offeredLineCount: 2, requestedLineCount: 0)
    let original = PublicContractSearchResult(
      contractID: 21, recordID: 21, regionID: 10_000_002, regionName: "The Forge",
      contractType: "item_exchange", price: 1, dateIssued: source.capturedAt,
      dateExpired: source.capturedAt, typeID: 901, isIncluded: true, quantity: 1,
      runs: -1, offeredLineCount: 1, requestedLineCount: 0)
    let price = DashboardBlueprintValuationBuilder.lowestCopyRunPrice([
      bundle, original, offer(contractID: 22, typeID: 901, runs: 4, price: 400),
    ])
    #expect(price == 100)
    #expect(DashboardBlueprintValuationBuilder.lowestCopyRunPrice([bundle, original]) == nil)
  }

  @Test
  func industryInputsWithoutReferencePriceAreValuedRecursively() {
    func production(product: Int64, material: Int64, quantity: Int64, output: Int64 = 1)
      -> BlueprintDefinition
    {
      BlueprintDefinition(
        blueprintTypeID: product + 10_000, productTypeID: product, maxProductionLimit: 100,
        activity: BlueprintActivityDefinition(
          kind: .manufacturing, durationSeconds: 60,
          materials: [BlueprintMaterial(typeID: material, quantity: quantity)],
          products: [BlueprintProduct(typeID: product, quantity: output, probability: nil)]),
        source: source)
    }
    let definitions = [
      Int64(600): production(product: 600, material: 601, quantity: 10),
      601: production(product: 601, material: 34, quantity: 4, output: 2),
      700: production(product: 700, material: 701, quantity: 1),
      701: production(product: 701, material: 700, quantity: 1),
    ]
    let values = DashboardRecursiveMaterialValuator.unitValues(
      for: [600, 700, 999], prices: prices.prices, definitionsByProductTypeID: definitions)
    // 601 = 4 × 5 ISK / 2 units = 10 ISK; 600 = 10 × 10 ISK.
    #expect(values[600] == 100)
    #expect(values[700] == nil)
    #expect(values[999] == nil)
  }
}
