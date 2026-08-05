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
    #expect(basis.priceSourceTradingLocation?.location == .jita)
    #expect(basis.homeTradingLocation == nil)
    #expect(basis.mainTradingLocation?.location == basis.logistics.homeTradeHub)
  }

  @Test
  func managesTradingLocationsHomeHubAndPerLocationTraders() {
    var basis = ProductionBasis(
      marketTaxes: MarketTaxConfiguration(traderCharacterID: 7),
      logistics: LogisticsConfiguration(homeTradeHub: .amarr)
    )

    #expect(
      basis.configuredProcurementLocations.map(\.id)
        == [ProcurementLocation.amarr.id]
    )
    #expect(basis.priceSourceTradingLocation?.traderCharacterID == 7)
    #expect(basis.mainTradingLocation?.location == .amarr)
    #expect(basis.homeTradingLocation == nil)
    #expect(basis.mainTradeHub == .amarr)

    let addedDodixie = basis.addTradingLocation(.dodixie)
    let addedDodixieAgain = basis.addTradingLocation(.dodixie)
    #expect(addedDodixie)
    #expect(!addedDodixieAgain)
    let dodixieID = basis.tradingLocations.first {
      $0.location == .dodixie
    }!.id
    basis.selectTrader(
      characterID: 42,
      forTradingLocationID: dodixieID
    )
    basis.setMainTradingLocation(id: dodixieID)

    let home = ProcurementLocation(
      id: "structure:1",
      name: "UALX-3 - Marva Ship Bellicos",
      locationID: 1_000_000_000_001,
      kind: .playerStructure,
      solarSystemID: 30_004_807
    )
    let addedHome = basis.addTradingLocation(home)
    #expect(addedHome)
    let homeID = basis.tradingLocations.first { $0.location == home }!.id
    basis.setHomeTradingLocation(id: homeID)

    #expect(
      basis.tradingLocations.first { $0.id == dodixieID }?
        .traderCharacterID == 42
    )
    #expect(basis.homeTradingLocation?.location == home)
    #expect(basis.logistics.homeTradeHub == .dodixie)
    #expect(basis.mainTradeHub == .dodixie)
    let removedHome = basis.removeTradingLocation(id: homeID)
    let mainID = basis.priceSourceTradingLocation!.id
    #expect(!removedHome)
    let removedMain = basis.removeTradingLocation(id: mainID)
    #expect(!removedMain)

    let amarrID = basis.tradingLocations.first {
      $0.location == .amarr
    }!.id
    basis.setMainTradingLocation(id: amarrID)
    let removedDodixie = basis.removeTradingLocation(id: dodixieID)
    #expect(removedDodixie)
    #expect(!basis.configuredProcurementLocations.contains(.dodixie))
    #expect(
      basis.areTraderSelectionsValid(connectedCharacterIDs: [7])
    )
  }

  @Test
  func addingESIStructureRepairsLegacyHomeHubInPlace() throws {
    let structureID: Int64 = 1_046_664_001_931
    let systemID: Int64 = 30_004_807
    let legacyHome = ProcurementLocation(
      id: "legacy:ualx-home",
      name: "UALX-3 - Mothership Bellicose",
      kind: .legacy
    )
    let main = TradingLocationConfiguration(location: .jita)
    let home = TradingLocationConfiguration(
      location: legacyHome,
      traderCharacterID: 77
    )
    var basis = ProductionBasis(
      tradingLocations: [main, home],
      mainTradingLocationID: main.id,
      homeTradingLocationID: home.id
    )
    let esiHome = ProcurementLocation(
      id: "structure:\(structureID)",
      name: legacyHome.name,
      locationID: structureID,
      kind: .playerStructure,
      solarSystemID: systemID
    )

    let repaired = basis.addTradingLocation(esiHome)
    #expect(repaired)

    let resolvedHome = try #require(basis.homeTradingLocation)
    #expect(resolvedHome.id == home.id)
    #expect(resolvedHome.location == esiHome)
    #expect(resolvedHome.traderCharacterID == 77)
    #expect(
      basis.marketHubSnapshots.first { $0.id == home.id }?.roles == [.home]
    )
  }

  @Test
  func explicitlyReplacingLegacyHomeHubKeepsRoleTraderAndConfigurationID() throws {
    let structureID: Int64 = 1_046_664_001_931
    let systemID: Int64 = 30_004_807
    let legacyHome = ProcurementLocation(
      id: "legacy:ualx-home",
      name: "UALX-3 - Former Structure Name",
      kind: .legacy
    )
    let main = TradingLocationConfiguration(location: .jita)
    let home = TradingLocationConfiguration(
      location: legacyHome,
      traderCharacterID: 77
    )
    let esiHome = ProcurementLocation(
      id: "structure:\(structureID)",
      name: "UALX-3 - Mothership Bellicose",
      locationID: structureID,
      kind: .playerStructure,
      solarSystemID: systemID
    )
    let duplicate = TradingLocationConfiguration(
      location: esiHome,
      traderCharacterID: 88
    )
    var basis = ProductionBasis(
      tradingLocations: [main, home, duplicate],
      mainTradingLocationID: main.id,
      homeTradingLocationID: home.id
    )

    let replaced = basis.replaceTradingLocation(
      id: home.id,
      with: esiHome
    )

    #expect(replaced)
    #expect(basis.tradingLocations.count == 2)
    let resolvedHome = try #require(basis.homeTradingLocation)
    #expect(resolvedHome.id == home.id)
    #expect(resolvedHome.location == esiHome)
    #expect(resolvedHome.traderCharacterID == 77)
    #expect(
      basis.marketHubSnapshots.first { $0.id == home.id }?.roles == [.home]
    )
  }

  @Test
  func tradingLocationConfigurationSurvivesRoundTrip() throws {
    var original = ProductionBasis(
      logistics: LogisticsConfiguration(homeTradeHub: .jita)
    )
    original.addTradingLocation(.hek)
    let hekID = try #require(
      original.tradingLocations.first { $0.location == .hek }?.id
    )
    original.selectTrader(characterID: 99, forTradingLocationID: hekID)
    original.setMainTradingLocation(id: hekID)
    original.setHomeTradingLocation(id: hekID)

    let decoded = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(original)
    )

    #expect(decoded.priceSourceTradingLocation?.location == .hek)
    #expect(decoded.homeTradingLocation?.location == .hek)
    #expect(decoded.logistics.homeTradeHub == .hek)
    #expect(decoded.mainTradeHub == .hek)
    #expect(
      decoded.homeTradingLocation?.traderCharacterID == 99
    )
  }

  @Test
  func migratesFormerHomeFieldToMainHubAndLegacyTraderField() throws {
    let locationID = UUID()
    let locationObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ProcurementLocation.amarr)
      ) as? [String: Any]
    )
    let data = try JSONSerialization.data(
      withJSONObject: [
        "marketTaxes": ["traderCharacterID": 7],
        "tradingLocations": [
          [
            "id": locationID.uuidString,
            "location": locationObject,
            "traderCharacterID": 7,
          ]
        ],
        "homeTradingLocationID": locationID.uuidString,
        "logistics": [
          "homeTradeHub": locationObject,
          "productionLocationName": "Production",
        ],
      ]
    )

    let basis = try JSONDecoder().decode(ProductionBasis.self, from: data)

    #expect(basis.mainTradingLocationID == locationID)
    #expect(basis.mainTradingLocation?.location == .amarr)
    #expect(basis.mainTradingLocation?.traderCharacterID == 7)
    #expect(basis.homeTradingLocationID == nil)
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
  func manualActivitySelectionOverridesModulesAndPreservesESILocation() throws {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let reactionService = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_888,
        name: "Standup Composite Reactor I",
        activities: [.reaction],
        source: source
      )
    )
    var tatara = ConfiguredIndustryStructure(
      name: "Shared Tatara",
      kind: .tatara,
      solarSystemID: 30_004_807,
      solarSystemName: "UALX-3",
      securityStatus: -0.19,
      serviceModules: [reactionService]
    )
    tatara.structureID = 1_049_588_174_021
    tatara.eveStructureName = "UALX-3 - Shared Tatara"

    #expect(tatara.enabledActivities == [.reaction])

    tatara.setActivityAssignmentMode(.manual)
    tatara.setActivity(.manufacturing, enabled: true)

    #expect(tatara.enabledActivities == [.manufacturing, .reaction])
    #expect(tatara.supportsActivity(.manufacturing))
    #expect(tatara.supportsActivity(.reaction))
    #expect(!tatara.activityCapabilityNeedsReview)

    let decoded = try JSONDecoder().decode(
      ConfiguredIndustryStructure.self,
      from: JSONEncoder().encode(tatara)
    )

    #expect(decoded.effectiveActivityAssignmentMode == .manual)
    #expect(decoded.enabledActivities == [.manufacturing, .reaction])
    #expect(decoded.structureID == 1_049_588_174_021)
    #expect(decoded.eveStructureName == "UALX-3 - Shared Tatara")
    #expect(decoded.solarSystemID == 30_004_807)
    #expect(decoded.solarSystemName == "UALX-3")
  }

  @Test
  func roundTripPreservesScienceOnlyStructureLocationAndAssignments() throws {
    let source = SourceIdentity(provider: "CCP SDE", version: "fixture")
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_002_110,
      solarSystemName: "B9E-H6",
      securityStatus: -0.37
    )
    let inventionSystem = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_004_807,
      solarSystemName: "UALX-3",
      securityStatus: -0.19
    )
    let copyingSystem = ActivitySystemConfiguration(
      activity: .copying,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName,
      securityStatus: inventionSystem.securityStatus
    )
    let materialResearchSystem = ActivitySystemConfiguration(
      activity: .materialResearch,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName,
      securityStatus: inventionSystem.securityStatus
    )
    let timeResearchSystem = ActivitySystemConfiguration(
      activity: .timeResearch,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName,
      securityStatus: inventionSystem.securityStatus
    )
    let inventionLab = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_886,
        name: "Standup Invention Lab I",
        activities: [.invention],
        source: source
      )
    )
    let researchLab = IndustryServiceModuleConfiguration(
      definition: IndustryServiceModuleDefinition(
        typeID: 35_891,
        name: "Standup Research Lab I",
        activities: [.copying, .materialResearch, .timeResearch],
        source: source
      )
    )
    let researchSotiyo = ConfiguredIndustryStructure(
      name: "Research Sotiyo",
      kind: .sotiyo,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName,
      securityStatus: inventionSystem.securityStatus,
      serviceModules: [inventionLab, researchLab]
    )
    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      inventionSystem: inventionSystem,
      copyingSystem: copyingSystem,
      materialResearchSystem: materialResearchSystem,
      timeResearchSystem: timeResearchSystem,
      structures: [researchSotiyo]
    )

    let data = try JSONEncoder().encode(basis)
    let decoded = try JSONDecoder().decode(ProductionBasis.self, from: data)

    #expect(decoded.structures[0].solarSystemID == 30_004_807)
    #expect(decoded.structures[0].solarSystemName == "UALX-3")
    #expect(decoded.structures[0].manufacturingSystemID == nil)
    for activity in IndustryActivitySystem.allCases
    where activity.isScienceActivity {
      #expect(
        decoded.scienceSelection(for: activity)?.structureID
          == researchSotiyo.id
      )
    }
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
  func marketFeesRemainBoundToTraderAndTradingLocation() {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
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
        value: [500_002: -1, 1_000_004: 2],
        source: source
      )
    )
    let station = ProcurementLocation(
      id: "npc:1",
      name: "Fixture NPC Station",
      locationID: 60_000_001,
      kind: .npcTradeHub,
      solarSystemID: 30_000_001,
      ownerCorporationID: 1_000_004,
      ownerFactionID: 500_002
    )
    var taxes = MarketTaxConfiguration(traderCharacterID: 42)

    taxes.apply(capability: capability, at: station)

    #expect(abs((taxes.effectiveBrokerFeeRate ?? 0) - 0.0179) < 0.000_001)
    #expect(taxes.calculation?.locationID == station.locationID)
    #expect(taxes.calculation?.locationName == station.name)
    #expect(taxes.calculation?.brokerFeeSource == .npcStation)

    let structure = ProcurementLocation(
      id: "structure:1",
      name: "Fixture Player Structure",
      locationID: 1_000_000_000_001,
      kind: .playerStructure
    )
    taxes.apply(capability: capability, at: structure)

    #expect(taxes.effectiveSalesTaxRate != nil)
    #expect(taxes.effectiveBrokerFeeRate == nil)
    #expect(
      taxes.calculation?.brokerFeeSource
        == .playerStructureNotExposedByESI
    )
    #expect(
      taxes.calculation?.warnings.contains {
        $0.contains("not exposed by ESI")
      } == true
    )
  }

  @Test
  func manualBrokerFeeFallbackPersistsAndYieldsToAutomaticNPCFee() throws {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
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
        value: [:],
        source: source
      )
    )
    let structure = ProcurementLocation(
      id: "structure:1",
      name: "Fixture Player Structure",
      locationID: 1_000_000_000_001,
      kind: .playerStructure
    )
    let updatedAt = Date(timeIntervalSince1970: 123)
    var taxes = MarketTaxConfiguration(traderCharacterID: 42)
    taxes.setManualBrokerFeeRate(0.025, updatedAt: updatedAt)

    taxes.apply(capability: capability, at: structure)

    #expect(taxes.automaticBrokerFeeRate == nil)
    #expect(taxes.effectiveBrokerFeeRate == 0.025)
    #expect(taxes.effectiveBrokerFeeSource == .manualFallback)
    #expect(taxes.isManualBrokerFeeFallbackActive)
    #expect(taxes.manualBrokerFeeUpdatedAt == updatedAt)

    let restored = try JSONDecoder().decode(
      MarketTaxConfiguration.self,
      from: JSONEncoder().encode(taxes)
    )
    #expect(restored.effectiveBrokerFeeRate == 0.025)
    #expect(restored.manualBrokerFeeUpdatedAt == updatedAt)

    taxes.apply(capability: capability, at: .amarr)

    #expect(abs((taxes.automaticBrokerFeeRate ?? 0) - 0.018) < 0.000_001)
    #expect(abs((taxes.effectiveBrokerFeeRate ?? 0) - 0.018) < 0.000_001)
    #expect(taxes.effectiveBrokerFeeSource == .npcStation)
    #expect(!taxes.isManualBrokerFeeFallbackActive)
    #expect(taxes.manualBrokerFeeRate == 0.025)
  }

  @Test
  func invalidManualBrokerFeeDoesNotReplaceKnownFallbackWithZero() {
    let updatedAt = Date(timeIntervalSince1970: 123)
    var taxes = MarketTaxConfiguration()
    taxes.setManualBrokerFeeRate(0.02, updatedAt: updatedAt)

    taxes.setManualBrokerFeeRate(-1)
    taxes.setManualBrokerFeeRate(.infinity)
    taxes.setManualBrokerFeeRate(1)

    #expect(taxes.manualBrokerFeeRate == 0.02)
    #expect(taxes.manualBrokerFeeUpdatedAt == updatedAt)
  }

  @Test
  func marketProfitabilityMarginsPersistAndRemainReadyForFiltering() throws {
    let parameters = MarketProfitabilityConfiguration(
      minimumSalesMarginRate: 0.1,
      targetSalesMarginRate: 0.2
    )
    let basis = ProductionBasis(marketProfitability: parameters)

    let restored = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(basis)
    )

    #expect(restored.marketProfitability.minimumSalesMarginRate == 0.1)
    #expect(restored.marketProfitability.targetSalesMarginRate == 0.2)
    #expect(restored.marketProfitability.isValid)
    #expect(restored.marketProfitability.assessment(for: 0.05) == .belowMinimum)
    #expect(restored.marketProfitability.assessment(for: 0.15) == .meetsMinimum)
    #expect(restored.marketProfitability.assessment(for: 0.25) == .meetsTarget)
    #expect(restored.marketProfitability.assessment(for: nil) == nil)

    var legacyObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(basis)
      ) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "marketProfitability")
    let migrated = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONSerialization.data(withJSONObject: legacyObject)
    )
    #expect(migrated.marketProfitability.minimumSalesMarginRate == nil)
    #expect(migrated.marketProfitability.targetSalesMarginRate == nil)
  }

  @Test
  func marketProfitabilityRejectsInventedAndMisorderedThresholds() {
    var parameters = MarketProfitabilityConfiguration()

    parameters.setMinimumSalesMarginRate(-0.1)
    parameters.setTargetSalesMarginRate(.infinity)

    #expect(parameters.minimumSalesMarginRate == nil)
    #expect(parameters.targetSalesMarginRate == nil)
    #expect(parameters.assessment(for: 0.5) == nil)

    parameters.setMinimumSalesMarginRate(0.2)
    parameters.setTargetSalesMarginRate(0.1)

    #expect(!parameters.isValid)
    #expect(parameters.assessment(for: 0.5) == nil)
  }

  @Test
  func standardAmarrContextContainsBrokerFeeOwnershipFallback() {
    #expect(ProcurementLocation.amarr.ownerCorporationID == 1_000_086)
    #expect(ProcurementLocation.amarr.ownerFactionID == 500_003)
    #expect(ProcurementLocation.dodixie.ownerCorporationID == 1_000_120)
    #expect(ProcurementLocation.dodixie.ownerFactionID == 500_004)
    #expect(ProcurementLocation.rens.ownerCorporationID == 1_000_049)
    #expect(ProcurementLocation.rens.ownerFactionID == 500_002)
    #expect(ProcurementLocation.hek.ownerCorporationID == 1_000_057)
    #expect(ProcurementLocation.hek.ownerFactionID == 500_002)
  }

  @Test
  func mainHubManualBrokerFeeFlowsIntoEffectivePlanningConfiguration() {
    let main = ProcurementLocation(
      id: "npc:fixture",
      name: "Fixture NPC Market",
      locationID: 60_000_001,
      kind: .npcTradeHub,
      solarSystemID: 30_000_001,
      regionID: 10_000_001
    )
    let configuration = TradingLocationConfiguration(location: main)
    let updatedAt = Date(timeIntervalSince1970: 123)
    var basis = ProductionBasis(
      tradingLocations: [configuration],
      mainTradingLocationID: configuration.id
    )

    basis.setManualBrokerFeeRate(
      0.03,
      forTradingLocationID: configuration.id,
      updatedAt: updatedAt
    )

    #expect(basis.marketTaxes.effectiveBrokerFeeRate == 0.03)
    #expect(basis.marketTaxes.effectiveBrokerFeeSource == .manualFallback)
    #expect(
      basis.mainTradingLocation?.marketTaxes.effectiveBrokerFeeRate == 0.03
    )
    #expect(basis.marketTaxes.manualBrokerFeeUpdatedAt == updatedAt)
  }

  @Test
  func incompleteRefreshPreservesKnownOwnershipForTheSameTradingLocation() {
    let configuration = TradingLocationConfiguration(location: .jita)
    var basis = ProductionBasis(
      tradingLocations: [configuration],
      mainTradingLocationID: configuration.id
    )
    let incompleteRefresh = ProcurementLocation(
      id: ProcurementLocation.jita.id,
      name: ProcurementLocation.jita.name,
      locationID: ProcurementLocation.jita.locationID,
      kind: .npcTradeHub,
      solarSystemID: ProcurementLocation.jita.solarSystemID,
      ownerCorporationID: ProcurementLocation.jita.ownerCorporationID,
      ownerFactionID: nil
    )

    basis.updateTradingLocation(
      id: configuration.id,
      location: incompleteRefresh
    )

    #expect(
      basis.mainTradingLocation?.location.ownerFactionID
        == ProcurementLocation.jita.ownerFactionID
    )
    #expect(
      basis.logistics.homeTradeHub.ownerFactionID
        == ProcurementLocation.jita.ownerFactionID
    )
  }

  @Test
  func normalizationRepairsMissingOwnershipForAKnownTradeHub() {
    let incompleteJita = ProcurementLocation(
      id: ProcurementLocation.jita.id,
      name: ProcurementLocation.jita.name,
      locationID: ProcurementLocation.jita.locationID,
      kind: .npcTradeHub,
      solarSystemID: ProcurementLocation.jita.solarSystemID,
      ownerCorporationID: ProcurementLocation.jita.ownerCorporationID,
      ownerFactionID: nil
    )
    let configuration = TradingLocationConfiguration(
      location: incompleteJita
    )

    let basis = ProductionBasis(
      tradingLocations: [configuration],
      mainTradingLocationID: configuration.id
    )

    #expect(
      basis.mainTradingLocation?.location.ownerFactionID
        == ProcurementLocation.jita.ownerFactionID
    )
  }

  @Test
  func repairedJitaContextRecalculatesMissingBrokerFromStoredCapabilities() {
    let incompleteJita = ProcurementLocation(
      id: ProcurementLocation.jita.id,
      name: ProcurementLocation.jita.name,
      locationID: ProcurementLocation.jita.locationID,
      kind: .npcTradeHub,
      solarSystemID: ProcurementLocation.jita.solarSystemID,
      ownerCorporationID: ProcurementLocation.jita.ownerCorporationID,
      ownerFactionID: nil
    )
    let configuration = TradingLocationConfiguration(
      location: incompleteJita,
      traderCharacterID: 42
    )
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let capability = CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: 42, name: "Trader"),
      cloneState: .omega,
      skills: Sourced(
        state: .fresh,
        value: [
          TrainedSkill(
            skillID: EVEConstants.accountingSkillTypeID,
            trainedLevel: 4,
            activeLevel: 4,
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
        value: [:],
        source: source
      )
    )
    var basis = ProductionBasis(
      tradingLocations: [configuration],
      mainTradingLocationID: configuration.id
    )

    basis.refreshResolvableMarketFees(capabilities: [capability])

    #expect(
      abs((basis.marketTaxes.effectiveSalesTaxRate ?? 0) - 0.042)
        < 0.000_001
    )
    #expect(
      abs((basis.marketTaxes.effectiveBrokerFeeRate ?? 0) - 0.018)
        < 0.000_001
    )
    #expect(basis.marketTaxes.calculation?.brokerFeeSource == .npcStation)
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

  @Test
  func marketRolesAcceptCustomNPCMainAndAuthenticatedCoalitionStructure()
    throws
  {
    let customStation = ProcurementLocation(
      id: "npc:60000001",
      name: "Custom NPC Station",
      locationID: 60_000_001,
      kind: .npcTradeHub,
      solarSystemID: 30_000_001,
      regionID: 10_000_001
    )
    let coalition = ProcurementLocation(
      id: "structure:1040000000001",
      name: "Coalition Keepstar",
      locationID: 1_040_000_000_001,
      kind: .playerStructure,
      solarSystemID: 30_000_002,
      regionID: 10_000_001,
      ownerCorporationID: 98_000_001
    )
    var basis = ProductionBasis()
    let addedCustom = basis.addTradingLocation(customStation)
    let addedCoalition = basis.addTradingLocation(coalition)
    #expect(addedCustom)
    #expect(addedCoalition)
    let customID = try #require(
      basis.tradingLocations.first { $0.location.id == customStation.id }?.id
    )
    let coalitionID = try #require(
      basis.tradingLocations.first { $0.location.id == coalition.id }?.id
    )

    basis.setMainTradingLocation(id: customID)
    basis.setHomeTradingLocation(id: customID)
    basis.setCoalitionTradingLocation(id: coalitionID)

    #expect(basis.mainTradingLocationID == customID)
    #expect(basis.homeTradingLocationID == customID)
    #expect(basis.coalitionTradingLocationID == coalitionID)
    #expect(basis.mainAndHomeAreIdentical)
    #expect(basis.logistics.productionLocationName == customStation.name)
    #expect(
      basis.marketHubSnapshots.first { $0.id == customID }?.roles
        == [.main, .home]
    )
    #expect(
      basis.marketHubSnapshots.first { $0.id == coalitionID }?.roles
        == [.coalition]
    )
    #expect(basis.marketHubSnapshots.count == 2)
    #expect(
      !basis.marketHubSnapshots.contains {
        $0.location.locationID == ProcurementLocation.jita.locationID
      }
    )

    let restored = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(basis)
    )
    #expect(restored.mainTradingLocation?.location == customStation)
    #expect(restored.coalitionTradingLocation?.location == coalition)
  }

  @Test
  func addedLocationsBecomeComparisonMarketsAndCoalitionRejectsNPCStations()
    throws
  {
    var basis = ProductionBasis()
    let addedAmarr = basis.addTradingLocation(.amarr)
    #expect(addedAmarr)
    let amarrID = try #require(
      basis.tradingLocations.first { $0.location.id == ProcurementLocation.amarr.id }?.id
    )

    basis.setCoalitionTradingLocation(id: amarrID)

    #expect(basis.coalitionTradingLocationID == nil)
    #expect(basis.comparisonTradingLocationIDs.contains(amarrID))
    #expect(
      basis.marketHubSnapshots.first { $0.id == amarrID }?.roles
        == [.comparison]
    )
    basis.setComparisonTradingLocation(id: amarrID, isSelected: false)
    #expect(!basis.marketHubSnapshots.contains { $0.id == amarrID })
    basis.setComparisonTradingLocation(id: amarrID, isSelected: true)
    let removedAmarr = basis.removeTradingLocation(id: amarrID)
    #expect(removedAmarr)
    #expect(!basis.comparisonTradingLocationIDs.contains(amarrID))
  }

  @Test
  func migratesResolvedUnassignedTradingLocationsToComparisonMarkets() throws {
    let main = TradingLocationConfiguration(location: .jita)
    let amarr = TradingLocationConfiguration(location: .amarr)
    let current = ProductionBasis(
      tradingLocations: [main, amarr],
      mainTradingLocationID: main.id,
      comparisonTradingLocationIDs: []
    )
    var legacyObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(current)
      ) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "comparisonTradingLocationIDs")

    let migrated = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONSerialization.data(withJSONObject: legacyObject)
    )

    #expect(migrated.comparisonTradingLocationIDs == [amarr.id])
    #expect(
      migrated.marketHubSnapshots.first { $0.id == amarr.id }?.roles
        == [.comparison]
    )

    var optedOut = migrated
    optedOut.setComparisonTradingLocation(id: amarr.id, isSelected: false)
    let restored = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(optedOut)
    )
    #expect(restored.comparisonTradingLocationIDs.isEmpty)
    #expect(!restored.marketHubSnapshots.contains { $0.id == amarr.id })
  }

  @Test
  func productionWarehouseCombinesOnlyAssignedExactFacilityLocations() throws {
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_000_001,
      solarSystemName: "Manufacturing System"
    )
    let reactionSystem = ActivitySystemConfiguration(
      activity: .reaction,
      solarSystemID: 30_000_002,
      solarSystemName: "Reaction System"
    )
    let inventionSystem = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_000_003,
      solarSystemName: "Science System"
    )
    let copyingSystem = ActivitySystemConfiguration(
      activity: .copying,
      solarSystemID: 30_000_003,
      solarSystemName: "Science System"
    )

    var manufacturing = ConfiguredIndustryStructure(
      name: "Manufacturing Sotiyo",
      kind: .sotiyo,
      manufacturingSystemID: manufacturingSystem.id,
      solarSystemID: manufacturingSystem.solarSystemID,
      solarSystemName: manufacturingSystem.solarSystemName
    )
    manufacturing.structureID = 1_000_000_000_001
    var reaction = ConfiguredIndustryStructure(
      name: "Reaction Tatara",
      kind: .tatara,
      solarSystemID: reactionSystem.solarSystemID,
      solarSystemName: reactionSystem.solarSystemName,
      securityBand: .nullSecurity
    )
    reaction.structureID = 1_000_000_000_002
    var science = ConfiguredIndustryStructure(
      name: "Science Sotiyo",
      kind: .sotiyo,
      solarSystemID: inventionSystem.solarSystemID,
      solarSystemName: inventionSystem.solarSystemName
    )
    science.structureID = 1_000_000_000_003
    var unused = ConfiguredIndustryStructure(
      name: "Unused Azbel",
      kind: .azbel,
      manufacturingSystemID: manufacturingSystem.id,
      solarSystemID: manufacturingSystem.solarSystemID,
      solarSystemName: manufacturingSystem.solarSystemName
    )
    unused.structureID = 1_000_000_000_004

    let manufacturingAssignments = Dictionary(
      uniqueKeysWithValues: ManufacturingCategory.allCases.map {
        ($0, manufacturing.id)
      }
    )
    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      reactionSystem: reactionSystem,
      inventionSystem: inventionSystem,
      copyingSystem: copyingSystem,
      structures: [manufacturing, reaction, science, unused],
      automaticStructureSelection: false,
      manufacturingAssignments: manufacturingAssignments,
      reactionStructureID: reaction.id,
      scienceAssignments: [
        .invention: science.id,
        .copying: science.id,
      ]
    )

    let scope = basis.productionWarehouseScope

    #expect(
      scope.locationIDs == [
        1_000_000_000_001,
        1_000_000_000_002,
        1_000_000_000_003,
      ]
    )
    #expect(!scope.locationIDs.contains(1_000_000_000_004))
    #expect(scope.unresolvedActivities.isEmpty)
    #expect(
      try #require(
        scope.locations.first { $0.locationID == 1_000_000_000_001 }
      ).activities == [.manufacturing]
    )
    #expect(
      try #require(
        scope.locations.first { $0.locationID == 1_000_000_000_002 }
      ).activities == [.reaction]
    )
    #expect(
      try #require(
        scope.locations.first { $0.locationID == 1_000_000_000_003 }
      ).activities == [.invention, .copying]
    )
  }

  @Test
  func productionWarehouseRejectsAFacilityOutsideItsActivitySystem() {
    let manufacturingSystem = ActivitySystemConfiguration(
      activity: .manufacturing,
      solarSystemID: 30_000_001,
      solarSystemName: "Manufacturing System"
    )
    let reactionSystem = ActivitySystemConfiguration(
      activity: .reaction,
      solarSystemID: 30_000_002,
      solarSystemName: "Reaction System"
    )
    var wrongSystemFacility = ConfiguredIndustryStructure(
      name: "Wrong-system Tatara",
      kind: .tatara,
      manufacturingSystemID: manufacturingSystem.id,
      solarSystemID: manufacturingSystem.solarSystemID,
      solarSystemName: manufacturingSystem.solarSystemName,
      securityBand: .nullSecurity
    )
    wrongSystemFacility.structureID = 1_000_000_000_001
    let manufacturingAssignments = Dictionary(
      uniqueKeysWithValues: ManufacturingCategory.allCases.map {
        ($0, wrongSystemFacility.id)
      }
    )
    let basis = ProductionBasis(
      manufacturingSystems: [manufacturingSystem],
      reactionSystem: reactionSystem,
      structures: [wrongSystemFacility],
      automaticStructureSelection: false,
      manufacturingAssignments: manufacturingAssignments,
      reactionStructureID: wrongSystemFacility.id
    )

    let scope = basis.productionWarehouseScope

    #expect(scope.locationIDs == [1_000_000_000_001])
    #expect(scope.locations.first?.activities == [.manufacturing])
    #expect(scope.unresolvedActivities == [.reaction])
  }

  @Test
  func multipleActivitySystemsPersistAndDriveFacilitySelection() throws {
    let reactionA = ActivitySystemConfiguration(
      activity: .reaction,
      solarSystemID: 30_000_101,
      solarSystemName: "Reaction A",
      securityStatus: -0.2
    )
    let reactionB = ActivitySystemConfiguration(
      activity: .reaction,
      solarSystemID: 30_000_102,
      solarSystemName: "Reaction B",
      securityStatus: -0.4
    )
    let inventionA = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_000_201,
      solarSystemName: "Invention A"
    )
    let inventionB = ActivitySystemConfiguration(
      activity: .invention,
      solarSystemID: 30_000_202,
      solarSystemName: "Invention B"
    )
    let basicRefinery = ConfiguredIndustryStructure(
      name: "Basic Refinery",
      kind: .athanor,
      manufacturingSystemID: reactionA.id,
      solarSystemID: reactionA.solarSystemID,
      solarSystemName: reactionA.solarSystemName,
      securityStatus: reactionA.securityStatus
    )
    let optimizedRefinery = ConfiguredIndustryStructure(
      name: "Optimized Refinery",
      kind: .tatara,
      manufacturingSystemID: reactionB.id,
      solarSystemID: reactionB.solarSystemID,
      solarSystemName: reactionB.solarSystemName,
      securityStatus: reactionB.securityStatus,
      rigs: [
        IndustryRigConfiguration(
          kind: .compositeReactionII,
          securityBand: .nullSecurity
        )
      ]
    )

    let basis = ProductionBasis(
      reactionSystems: [reactionA, reactionB],
      inventionSystems: [inventionA, inventionB],
      structures: [basicRefinery, optimizedRefinery]
    )

    #expect(basis.reactionSystems.count == 2)
    #expect(basis.inventionSystems.count == 2)
    #expect(basis.reactionSelection?.structureID == optimizedRefinery.id)
    #expect(basis.reactionSelection?.solarSystemName == "Reaction B")
    #expect(
      basis.systemConfiguration(
        for: .invention,
        structure: ConfiguredIndustryStructure(
          manufacturingSystemID: inventionB.id,
          solarSystemID: inventionB.solarSystemID,
          solarSystemName: inventionB.solarSystemName
        )
      )?.id == inventionB.id
    )

    let restored = try JSONDecoder().decode(
      ProductionBasis.self,
      from: JSONEncoder().encode(basis)
    )
    #expect(restored.reactionSystems.map(\.id) == [reactionA.id, reactionB.id])
    #expect(
      restored.inventionSystems.map(\.id) == [inventionA.id, inventionB.id]
    )
    #expect(restored.reactionSystem.id == reactionA.id)
    #expect(restored.inventionSystem.id == inventionA.id)
  }
}
