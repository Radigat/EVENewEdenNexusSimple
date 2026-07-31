import Foundation
import Testing

@testable import EVENexusCore

@Suite("Production basis")
struct ProductionBasisTests {
  @Test
  func resolvesStructureToItsAssignedManufacturingSystem() {
    let jita = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_000_142,
      solarSystemName: "Jita"
    )
    let amarr = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_002_187,
      solarSystemName: "Amarr"
    )
    let structure = ConfiguredIndustryStructure(
      manufacturingSystemID: amarr.id,
      solarSystemID: amarr.solarSystemID,
      solarSystemName: amarr.solarSystemName
    )
    let basis = ProductionBasis(
      manufacturingSystems: [jita, amarr],
      structures: [structure]
    )

    #expect(
      basis.manufacturingSystem(for: structure)?.solarSystemName == "Amarr"
    )
    #expect(
      basis.selection(for: .capital)?.solarSystemName == "Amarr"
    )
  }

  @Test
  func migratesLegacySingleSystemAndStructureAssociation() throws {
    let legacySystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_002_187,
      solarSystemName: "Amarr"
    )
    let legacyStructure = ConfiguredIndustryStructure(
      name: "Capital Azbel",
      solarSystemID: legacySystem.solarSystemID,
      solarSystemName: legacySystem.solarSystemName
    )
    var structureObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(legacyStructure)
      ) as? [String: Any]
    )
    structureObject.removeValue(forKey: "manufacturingSystemID")
    structureObject["cloneState"] = "alpha"
    let systemObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(legacySystem)
      ) as? [String: Any]
    )
    var legacySystemObject = systemObject
    legacySystemObject.removeValue(forKey: "productionLabels")
    let data = try JSONSerialization.data(
      withJSONObject: [
        "manufacturingSystem": legacySystemObject,
        "structures": [structureObject],
      ]
    )

    let basis = try JSONDecoder().decode(ProductionBasis.self, from: data)

    #expect(basis.manufacturingSystems.count == 1)
    #expect(basis.manufacturingSystems[0].solarSystemName == "Amarr")
    #expect(
      basis.structures[0].manufacturingSystemID
        == basis.manufacturingSystems[0].id
    )
    #expect(basis.cloneState == .unknown)
    #expect(basis.manufacturingSystems[0].productionLabels == [.all])
    #expect(basis.inventionSystem.activity == .invention)
    #expect(basis.copyingSystem.activity == .copying)
    #expect(basis.materialResearchSystem.activity == .materialResearch)
    #expect(basis.timeResearchSystem.activity == .timeResearch)
    #expect(basis.scienceAssignments.isEmpty)
    #expect(basis.structures[0].serviceModules == nil)
    #expect(basis.structures[0].serviceCapabilityNeedsReview)
    #expect(basis.logistics.isEnabled == false)
  }

  @Test
  func automaticSelectionPrioritizesMaterialThenTime() {
    let azbel = ConfiguredIndustryStructure(
      name: "Azbel",
      kind: .azbel
    )
    let materialWinner = ConfiguredIndustryStructure(
      name: "Large Rig",
      kind: .raitaru,
      rigs: [
        IndustryRigConfiguration(kind: .largeShipII)
      ]
    )
    let tieBreaker = ConfiguredIndustryStructure(
      name: "Time Winner",
      kind: .custom,
      structureMaterialBonusPercent: 3.4,
      structureTimeBonusPercent: 50,
      source: .manual
    )
    let basis = ProductionBasis(
      structures: [azbel, materialWinner, tieBreaker]
    )

    let selection = basis.selection(for: .large)

    #expect(selection?.structureName == "Time Winner")
    #expect(
      abs((selection?.materialBonusPercent ?? 0) - 3.4) < 0.000_001
    )
    #expect(abs((selection?.timeBonusPercent ?? 0) - 50) < 0.000_001)
    #expect(selection?.isManualAssignment == false)
  }

  @Test
  func manualAssignmentOverridesAutomaticRanking() {
    let manual = ConfiguredIndustryStructure(
      name: "Manual",
      kind: .sotiyo,
      serviceModules: []
    )
    let better = ConfiguredIndustryStructure(
      name: "Better",
      kind: .sotiyo,
      rigs: [IndustryRigConfiguration(kind: .capitalShipII)]
    )
    let basis = ProductionBasis(
      structures: [manual, better],
      automaticStructureSelection: false,
      manufacturingAssignments: [.capital: manual.id]
    )

    let selection = basis.selection(for: .capital)

    #expect(selection?.structureID == manual.id)
    #expect(selection?.isManualAssignment == true)
    #expect(selection?.needsReview == true)
  }

  @Test
  func automaticReactionSelectionUsesBestRefineryInReactionSystem() {
    let reactionSystem = ActivitySystemConfiguration(
      activity: .reaction,
      solarSystemID: 30_004_807,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: EVEConstants.jitaSystemID,
      solarSystemName: "Jita",
      securityStatus: 0.95
    )
    let athanor = ConfiguredIndustryStructure(
      name: "Athanor",
      kind: .athanor,
      manufacturingSystemID: reactionSystem.id,
      solarSystemID: reactionSystem.solarSystemID,
      solarSystemName: reactionSystem.solarSystemName,
      securityStatus: reactionSystem.securityStatus
    )
    let tatara = ConfiguredIndustryStructure(
      name: "Tatara II",
      kind: .tatara,
      manufacturingSystemID: reactionSystem.id,
      solarSystemID: reactionSystem.solarSystemID,
      solarSystemName: reactionSystem.solarSystemName,
      securityStatus: reactionSystem.securityStatus,
      rigs: [
        IndustryRigConfiguration(
          kind: .compositeReactionII,
          securityBand: .nullSecurity
        )
      ],
      jobCostMultiplier: 0.97
    )
    let invalidSotiyo = ConfiguredIndustryStructure(
      name: "Sotiyo with reaction rig",
      kind: .sotiyo,
      manufacturingSystemID: reactionSystem.id,
      solarSystemID: reactionSystem.solarSystemID,
      solarSystemName: reactionSystem.solarSystemName,
      securityStatus: reactionSystem.securityStatus,
      rigs: [
        IndustryRigConfiguration(
          kind: .compositeReactionII,
          securityBand: .nullSecurity
        )
      ]
    )

    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      reactionSystem: reactionSystem,
      structures: [athanor, tatara, invalidSotiyo]
    )

    #expect(basis.reactionStructureID == tatara.id)
    #expect(basis.reactionSelection?.structureName == "Tatara II")
    #expect(basis.reactionSelection?.solarSystemName == "B9E-H6")
    #expect(basis.reactionSelection?.isManualAssignment == false)
    #expect(basis.selection(for: .capital) == nil)
  }

  @Test
  func automaticScienceSelectionUsesMatchingSystemAndSDERigModifiers() {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let inventionSystem = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_004_807,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let otherSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: EVEConstants.jitaSystemID,
      solarSystemName: "Jita",
      securityStatus: 0.95
    )
    let azbelDefinition = IndustryStructureDefinition(
      typeID: 35_826,
      name: "Azbel",
      size: .large,
      rigSlots: 3,
      manufacturingMaterialBonusPercent: 1,
      manufacturingTimeBonusPercent: 20,
      jobCostMultiplier: 0.97,
      source: source
    )
    let inventionRig = IndustryRigDefinition(
      typeID: 43_722,
      name: "Standup L-Set Invention Optimization I",
      size: .large,
      manufacturingCategories: [],
      isReactionRig: false,
      materialBonusPercent: 0,
      timeBonusPercent: 20,
      lowSecurityMultiplier: 1.9,
      nullSecurityMultiplier: 2.1,
      source: source,
      scienceActivities: [.invention],
      jobCostBonusPercent: 10
    )
    var optimized = ConfiguredIndustryStructure(
      name: "Science Azbel",
      kind: .azbel,
      manufacturingSystemID: inventionSystem.id,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName,
      securityStatus: inventionSystem.securityStatus
    )
    optimized.apply(definition: azbelDefinition)
    optimized.rigs = [
      IndustryRigConfiguration(definition: inventionRig)
    ]
    let wrongSystem = ConfiguredIndustryStructure(
      name: "Wrong-system Azbel",
      kind: .azbel,
      manufacturingSystemID: otherSystem.id,
      solarSystemID: otherSystem.solarSystemID,
      solarSystemName: otherSystem.solarSystemName,
      securityStatus: otherSystem.securityStatus,
      jobCostMultiplier: 0.1
    )

    let basis = ProductionBasis(
      manufacturingSystems: [otherSystem],
      inventionSystem: inventionSystem,
      structures: [optimized, wrongSystem]
    )
    let selection = basis.scienceSelection(for: .invention)

    #expect(selection?.structureID == optimized.id)
    #expect(selection?.solarSystemName == "B9E-H6")
    #expect(abs((selection?.jobCostBonusPercent ?? 0) - 21) < 0.000_001)
    #expect(abs((selection?.timeBonusPercent ?? 0) - 42) < 0.000_001)
    #expect(selection?.isManualAssignment == false)
  }

  @Test
  func manualScienceAssignmentOverridesAutomaticRanking() {
    let copyingSystem = ActivitySystemConfiguration(
      activity: .copying,
      solarSystemID: 30_002_187,
      solarSystemName: "Amarr",
      securityStatus: 1
    )
    let manual = ConfiguredIndustryStructure(
      name: "Manual station",
      kind: .npcStation,
      manufacturingSystemID: copyingSystem.id,
      solarSystemID: copyingSystem.solarSystemID,
      solarSystemName: copyingSystem.solarSystemName,
      securityStatus: copyingSystem.securityStatus
    )
    let better = ConfiguredIndustryStructure(
      name: "Better Azbel",
      kind: .azbel,
      manufacturingSystemID: copyingSystem.id,
      solarSystemID: copyingSystem.solarSystemID,
      solarSystemName: copyingSystem.solarSystemName,
      securityStatus: copyingSystem.securityStatus,
      jobCostMultiplier: 0.5
    )
    let basis = ProductionBasis(
      copyingSystem: copyingSystem,
      structures: [manual, better],
      automaticStructureSelection: false,
      scienceAssignments: [.copying: manual.id]
    )

    #expect(basis.scienceSelection(for: .copying)?.structureID == manual.id)
    #expect(
      basis.scienceSelection(for: .copying)?.isManualAssignment == true
    )
  }

  @Test
  func automaticScienceSelectionRequiresTheMatchingServiceModule() {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let system = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_004_807,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let researchLab = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_891,
        name: "Standup Research Lab I",
        activities: [.copying, .materialResearch, .timeResearch],
        source: source
      )
    )
    let inventionLab = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_886,
        name: "Standup Invention Lab I",
        activities: [.invention],
        source: source
      )
    )
    let cheaperButWrong = ConfiguredIndustryStructure(
      name: "Research only",
      kind: .azbel,
      manufacturingSystemID: system.id,
      solarSystemID: system.solarSystemID,
      solarSystemName: system.solarSystemName,
      securityStatus: system.securityStatus,
      serviceModules: [researchLab],
      jobCostMultiplier: 0.1
    )
    let inventionFacility = ConfiguredIndustryStructure(
      name: "Invention",
      kind: .azbel,
      manufacturingSystemID: system.id,
      solarSystemID: system.solarSystemID,
      solarSystemName: system.solarSystemName,
      securityStatus: system.securityStatus,
      serviceModules: [inventionLab],
      jobCostMultiplier: 0.97
    )

    let basis = ProductionBasis(
      inventionSystem: system,
      structures: [cheaperButWrong, inventionFacility]
    )

    #expect(
      basis.scienceSelection(for: .invention)?.structureID
        == inventionFacility.id
    )
  }

  @Test
  func oneStructureIsAutomaticallyEligibleForMultipleActivities() {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let solarSystemID: Int64 = 30_004_807
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: solarSystemID,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let inventionSystem = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: solarSystemID,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let copyingSystem = ActivitySystemConfiguration(
      activity: .copying,
      solarSystemID: solarSystemID,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let manufacturingService = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_890,
        name: "Standup Manufacturing Plant I",
        activities: [.manufacturing],
        source: source
      )
    )
    let inventionService = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_886,
        name: "Standup Invention Lab I",
        activities: [.invention],
        source: source
      )
    )
    let researchService = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_891,
        name: "Standup Research Lab I",
        activities: [.copying, .materialResearch, .timeResearch],
        source: source
      )
    )
    let sotiyo = ConfiguredIndustryStructure(
      name: "Multi-purpose Sotiyo",
      kind: .sotiyo,
      manufacturingSystemID: manufacturingSystem.id,
      solarSystemID: solarSystemID,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37,
      serviceModules: [
        manufacturingService,
        inventionService,
        researchService,
      ]
    )

    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      inventionSystem: inventionSystem,
      copyingSystem: copyingSystem,
      structures: [sotiyo]
    )

    #expect(
      basis.eligibleActivities(for: sotiyo)
        == [.manufacturing, .invention, .copying]
    )
    #expect(basis.selection(for: .capital)?.structureID == sotiyo.id)
    #expect(
      basis.scienceSelection(for: .invention)?.structureID == sotiyo.id
    )
    #expect(
      basis.scienceSelection(for: .copying)?.structureID == sotiyo.id
    )
  }

  @Test
  func marketFeesAreDerivedFromTraderSkillsAndUnmodifiedJitaStandings() {
    let source = SourceIdentity(
      provider: "ESI",
      version: "fixture",
      capturedAt: Date(timeIntervalSince1970: 100)
    )
    let capability = CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: 42, name: "Trader"),
      cloneState: .omega,
      skills: Sourced(
        state: .fresh,
        value: [
          TrainedSkill(
            skillID: EVEConstants.accountingSkillTypeID,
            trainedLevel: 5,
            activeLevel: 5,
            skillpoints: 1
          ),
          TrainedSkill(
            skillID: EVEConstants.brokerRelationsSkillTypeID,
            trainedLevel: 4,
            activeLevel: 4,
            skillpoints: 1
          ),
        ],
        source: source
      ),
      standings: Sourced(
        state: .fresh,
        value: [
          EVEConstants.jitaIV4OwnerFactionID: 5,
          EVEConstants.jitaIV4OwnerCorporationID: 8,
        ],
        source: source
      )
    )
    var taxes = MarketTaxConfiguration()

    taxes.selectTrader(characterID: 42, capability: capability)

    #expect(abs((taxes.effectiveSalesTaxRate ?? 0) - 0.03375) < 0.000_001)
    #expect(abs((taxes.effectiveBrokerFeeRate ?? 0) - 0.0149) < 0.000_001)
    #expect(taxes.calculation?.accountingLevel == 5)
    #expect(taxes.calculation?.brokerRelationsLevel == 4)
    #expect(taxes.calculation?.freshness == .fresh)
  }

  @Test
  func unavailableTraderCapabilitiesNeverBecomeZeroFees() {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let capability = CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: 42, name: "Trader"),
      cloneState: .unknown,
      skills: Sourced(
        state: .forbidden,
        value: nil,
        source: source
      ),
      standings: Sourced(
        state: .unavailable,
        value: nil,
        source: source
      )
    )
    var taxes = MarketTaxConfiguration()

    taxes.selectTrader(characterID: 42, capability: capability)

    #expect(taxes.effectiveSalesTaxRate == nil)
    #expect(taxes.effectiveBrokerFeeRate == nil)
    #expect(taxes.calculation?.freshness == .forbidden)
  }

  @Test
  func traderSelectionIsOptionalUntilACharacterIsConnected() {
    var taxes = MarketTaxConfiguration()

    #expect(taxes.isTraderSelectionValid(connectedCharacterIDs: []))

    taxes.selectTrader(characterID: 42, capability: nil)

    #expect(!taxes.isTraderSelectionValid(connectedCharacterIDs: []))
    #expect(
      taxes.isTraderSelectionValid(connectedCharacterIDs: [7, 42])
    )
  }

  @Test
  func rigSecurityScalingIsExplicit() {
    let high = IndustryRigConfiguration(
      kind: .largeShipII,
      securityBand: .highSecurity
    )
    let low = IndustryRigConfiguration(
      kind: .largeShipII,
      securityBand: .lowSecurity
    )
    let null = IndustryRigConfiguration(
      kind: .largeShipII,
      securityBand: .nullSecurity
    )

    #expect(high.materialBonusPercent == 2.4)
    #expect(abs(low.materialBonusPercent - 4.56) < 0.000_001)
    #expect(abs(null.materialBonusPercent - 5.04) < 0.000_001)
  }

  @Test
  func sdeFacilityRulesControlSecurityRigsAndAutomaticSelection() {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let raitaru = IndustryStructureDefinition(
      typeID: 35_825,
      name: "Raitaru",
      size: .medium,
      rigSlots: 3,
      manufacturingMaterialBonusPercent: 1,
      manufacturingTimeBonusPercent: 15,
      jobCostMultiplier: 0.97,
      source: source
    )
    let azbel = IndustryStructureDefinition(
      typeID: 35_826,
      name: "Azbel",
      size: .large,
      rigSlots: 3,
      manufacturingMaterialBonusPercent: 1,
      manufacturingTimeBonusPercent: 20,
      jobCostMultiplier: 0.97,
      source: source
    )
    let mediumSmallShipRig = IndustryRigDefinition(
      typeID: 43_855,
      name:
        "Standup M-Set Advanced Small Ship Manufacturing Material Efficiency I",
      size: .medium,
      manufacturingCategories: [.small],
      isReactionRig: false,
      materialBonusPercent: 2,
      timeBonusPercent: 0,
      lowSecurityMultiplier: 1.9,
      nullSecurityMultiplier: 2.1,
      source: source
    )
    let reference = IndustryFacilityReferenceSnapshot(
      structures: [raitaru, azbel],
      rigs: [mediumSmallShipRig],
      source: source
    )
    let system = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_000_001,
      solarSystemName: "Low",
      securityStatus: 0.2
    )
    var basis = ProductionBasis(
      manufacturingSystems: [system],
      structures: [
        ConfiguredIndustryStructure(
          name: "Medium",
          kind: .raitaru,
          manufacturingSystemID: system.id,
          solarSystemID: system.solarSystemID
        ),
        ConfiguredIndustryStructure(
          name: "Large",
          kind: .azbel,
          manufacturingSystemID: system.id,
          solarSystemID: system.solarSystemID
        ),
      ]
    )

    basis.applyFacilityReferences(reference)
    basis.structures[0].securityStatus = 0.2
    basis.structures[0].securityBand = .lowSecurity
    basis.structures[0].rigs = [
      IndustryRigConfiguration(definition: mediumSmallShipRig)
    ]

    #expect(basis.structures[0].rigSize == .medium)
    #expect(basis.structures[0].maximumRigSlots == 3)
    #expect(reference.compatibleRigs(size: .large).isEmpty)
    #expect(
      abs(
        basis.structures[0].materialBonusPercent(for: .small) - 4.762
      ) < 0.000_001
    )
    #expect(
      abs(
        basis.structures[0].materialMultiplier(for: .small)
          - (0.99 * 0.962)
      ) < 0.000_001
    )
    #expect(basis.selection(for: .small)?.structureName == "Medium")
    #expect(basis.selection(for: .large)?.structureName == "Large")
    #expect(basis.structures[0].jobCostMultiplier == 0.97)
  }

  @Test
  func securityBandComesFromSystemStatusAndAnoikisID() {
    #expect(
      SecurityBand.resolved(
        solarSystemID: 30_000_142,
        securityStatus: 0.95
      ) == .highSecurity
    )
    #expect(
      SecurityBand.resolved(
        solarSystemID: 30_000_001,
        securityStatus: 0.2
      ) == .lowSecurity
    )
    #expect(
      SecurityBand.resolved(
        solarSystemID: 30_004_807,
        securityStatus: -0.1
      ) == .nullSecurity
    )
    #expect(
      SecurityBand.resolved(
        solarSystemID: 31_000_001,
        securityStatus: -0.99
      ) == .wormhole
    )
    #expect(
      SecurityBand.resolved(
        solarSystemID: 30_000_001,
        securityStatus: -0.99,
        regionID: 11_000_001
      ) == .wormhole
    )
  }

  @Test
  func newStructureInheritsResolvedSystemSecurity() {
    let nullSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_004_807,
      solarSystemName: "B9E-H6",
      regionID: 10_000_025,
      regionName: "Immensea",
      securityStatus: -0.37
    )

    let structure = ConfiguredIndustryStructure(
      manufacturingSystemID: nullSystem.id,
      solarSystemID: nullSystem.solarSystemID,
      solarSystemName: nullSystem.solarSystemName,
      securityStatus: nullSystem.securityStatus,
      regionID: nullSystem.regionID
    )

    #expect(nullSystem.securityBand == .nullSecurity)
    #expect(structure.securityBand == .nullSecurity)
    #expect(structure.securityStatus == -0.37)
  }

  @Test
  func resolvingAssignedSystemRefreshesExistingStructureSecurity() {
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: EVEConstants.jitaSystemID,
      solarSystemName: "Jita",
      securityStatus: 0.95
    )
    let staleStructure = ConfiguredIndustryStructure(
      manufacturingSystemID: manufacturingSystem.id,
      solarSystemID: EVEConstants.jitaSystemID,
      solarSystemName: "Jita",
      securityStatus: 0.95
    )
    var basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      structures: [staleStructure]
    )

    basis.manufacturingSystems[0].solarSystemID = 30_004_807
    basis.manufacturingSystems[0].solarSystemName = "B9E-H6"
    basis.manufacturingSystems[0].securityStatus = nil
    basis.applySystemDetails(
      SolarSystemDetails(
        id: 30_004_807,
        name: "B9E-H6",
        constellationID: 20_000_703,
        constellationName: "H-6HGD",
        regionID: 10_000_025,
        regionName: "Immensea",
        securityStatus: -0.37,
        securityClass: nil,
        stationIDs: [],
        source: SourceIdentity(provider: "fixture", version: "1")
      )
    )

    #expect(basis.structures[0].solarSystemID == 30_004_807)
    #expect(basis.structures[0].solarSystemName == "B9E-H6")
    #expect(basis.structures[0].securityStatus == -0.37)
    #expect(basis.structures[0].securityBand == .nullSecurity)
  }

  @Test
  func blacklistAndSlotSchedulingAreDeterministic() {
    let blacklist = ProductionBlacklistConfiguration(
      presets: [.fuelBlocks],
      typeNames: ["Never Build This"]
    )
    let fuel = IndustryItemClassification(
      categoryName: "Commodity",
      groupName: "Fuel Block",
      manufacturingCategory: .structures
    )

    #expect(blacklist.blocks(typeName: "Helium Fuel Block", classification: fuel))
    #expect(
      blacklist.blocks(typeName: "never build this", classification: nil)
    )
    #expect(
      IndustryPlanner.slotMakespan(
        durations: [10, 9, 8, 7],
        slots: 2
      ) == 17
    )
    #expect(
      IndustryPlanner.slotMakespan(
        durations: [10, 9, 8, 7],
        slots: 125
      ) == 10
    )
  }
}
