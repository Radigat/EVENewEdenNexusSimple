import Foundation
import Testing

@testable import EVENexusCore

@Suite("Jump Freighter logistics")
struct JumpFreighterLogisticsTests {
  @Test
  func routeProfilesCanBeSharedAndAssignedIndependently() throws {
    let shared = JumpRouteProfile(
      name: "Shared capital route",
      waypoints: [
        JumpRouteWaypoint(
          solarSystemID: 30_004_777,
          solarSystemName: "EIH-IU",
          structureName: "Fixture cyno structure"
        )
      ]
    )
    let titan = JumpRouteProfile(name: "Titan route")
    var configuration = JumpFreighterLogisticsConfiguration(
      routeProfiles: [shared, titan]
    )

    configuration.assign(profileID: shared.id, to: .carrier)
    configuration.assign(profileID: shared.id, to: .forceAuxiliary)
    configuration.assign(profileID: titan.id, to: .titan)

    #expect(configuration.assignedProfile(for: .carrier)?.id == shared.id)
    #expect(
      configuration.assignedProfile(for: .forceAuxiliary)?.id == shared.id
    )
    #expect(configuration.assignedProfile(for: .titan)?.id == titan.id)
    #expect(configuration.assignedProfile(for: .supercarrier) == nil)

    configuration.removeRouteProfile(id: shared.id)
    #expect(configuration.assignedProfileID(for: .carrier) == nil)
    #expect(configuration.assignedProfileID(for: .forceAuxiliary) == nil)
    #expect(configuration.assignedProfile(for: .titan)?.id == titan.id)
  }

  @Test
  func legacyJumpConfigurationDecodesWithAutomaticRoutes() throws {
    let data = try #require(
      """
      {"isEnabled":true,"hull":"ark","usableCargoCapacityM3":350000,"ruleVersion":"legacy"}
      """.data(using: .utf8)
    )

    let configuration = try JSONDecoder().decode(
      JumpFreighterLogisticsConfiguration.self,
      from: data
    )

    #expect(configuration.routeProfiles.isEmpty)
    #expect(configuration.routeAssignments.isEmpty)
    #expect(configuration.assignedProfile(for: .jumpFreighter) == nil)
  }

  @Test
  func dotlanURLContainsHullSkillsAndSystems() throws {
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )

    let url = try DOTLANJumpRouteService.url(for: request)

    #expect(
      url.absoluteString
        == "https://evemaps.dotlan.net/jump/Ark,555/UALX-3:C-J6MT"
    )
  }

  @Test
  func parsesRetainedDotlanRouteAndFuel() throws {
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )
    let html = """
      <h2>Jump Route:</h2><table>
      <a class="igb link-5-30004807">UALX-3</a>
      <a class="igb link-5-30004777">EIH-IU</a>
      Distance: <b>9.536 ly</b> Fuel needed: <b>20,978</b>
      <a class="igb link-5-30004777">EIH-IU</a>
      <a class="igb link-5-30004759">5DE-QS</a>
      Distance: <b>5.478 ly</b> Fuel needed: <b>12,052</b>
      <a class="igb link-5-30004759">5DE-QS</a>
      <a class="igb link-5-30004714">C-J6MT</a>
      Distance: <b>5.3 ly</b> Fuel needed: <b>11,660</b>
      Total travel distance</td><td><b>20.314 lightyears</b>
      Total fuel consumption:</td><td><b>44,690 Helium Isotopes</b> (1,341 m&sup3;)
      </table>
      """

    let route = try DOTLANJumpRouteService.parse(
      html: html,
      request: request,
      sourceURL: try #require(
        URL(string: "https://evemaps.dotlan.net/jump/Ark,555/UALX-3:C-J6MT")
      ),
      capturedAt: Date(timeIntervalSince1970: 1)
    )

    #expect(route.legs.count == 3)
    #expect(route.legs.map(\.originSystemName) == ["UALX-3", "EIH-IU", "5DE-QS"])
    #expect(route.legs.last?.destinationSystemName == "C-J6MT")
    #expect(route.totalDistanceLightYears == 20.314)
    #expect(route.isotope == .helium)
    #expect(route.isotopeQuantityPerFlight == 44_690)
    #expect(route.isotopeVolumePerFlightM3 == 1_341)
  }

  @Test
  func fixedRouteCombinesOnlyTheExplicitDirectSegments() throws {
    let pilot = pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot
    )
    let profile = JumpRouteProfile(
      name: "EIH route",
      waypoints: [
        JumpRouteWaypoint(
          solarSystemID: 30_004_777,
          solarSystemName: "EIH-IU",
          structureName: "Fixture cyno"
        )
      ]
    )
    let first = directRoute(
      origin: "UALX-3",
      destination: "EIH-IU",
      fuel: 20_000,
      distance: 9,
      pilot: pilot
    )
    let second = directRoute(
      origin: "EIH-IU",
      destination: "C-J6MT",
      fuel: 30_000,
      distance: 10,
      pilot: pilot
    )

    let combined = try DOTLANJumpRouteService.combineFixedRoute(
      request: request,
      profile: profile,
      segments: [first, second]
    )

    #expect(combined.legs.map(\.originSystemName) == ["UALX-3", "EIH-IU"])
    #expect(combined.legs.last?.destinationSystemName == "C-J6MT")
    #expect(combined.isotopeQuantityPerFlight == 50_000)
    #expect(combined.routeProfile?.profileID == profile.id)
    #expect(combined.routeProfile?.waypoints.first?.structureName == "Fixture cyno")
    #expect(combined.segmentSourceURLs?.count == 2)
  }

  @Test
  func fixedRouteRejectsDiscontinuousSegments() throws {
    let pilot = pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot
    )
    let profile = JumpRouteProfile(name: "Broken route")

    #expect(throws: DOTLANJumpRouteError.invalidFixedRoute) {
      try DOTLANJumpRouteService.combineFixedRoute(
        request: request,
        profile: profile,
        segments: [
          directRoute(
            origin: "UALX-3",
            destination: "EIH-IU",
            fuel: 20_000,
            distance: 9,
            pilot: pilot
          ),
          directRoute(
            origin: "5DE-QS",
            destination: "C-J6MT",
            fuel: 30_000,
            distance: 10,
            pilot: pilot
          ),
        ]
      )
    }
  }

  @Test
  func rejectsContradictoryDotlanFuelEvidence() throws {
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )
    let sourceURL = try #require(
      URL(string: "https://evemaps.dotlan.net/jump/Ark,555/UALX-3:C-J6MT")
    )
    let baseHTML = retainedDotlanHTML()

    #expect(throws: DOTLANJumpRouteError.schemaChanged) {
      try DOTLANJumpRouteService.parse(
        html: baseHTML.replacingOccurrences(
          of: "Helium Isotopes",
          with: "Nitrogen Isotopes"
        ),
        request: request,
        sourceURL: sourceURL,
        capturedAt: Date(timeIntervalSince1970: 1)
      )
    }
    #expect(throws: DOTLANJumpRouteError.schemaChanged) {
      try DOTLANJumpRouteService.parse(
        html: baseHTML.replacingOccurrences(of: "44,690", with: "44,691"),
        request: request,
        sourceURL: sourceURL,
        capturedAt: Date(timeIntervalSince1970: 1)
      )
    }
  }

  @Test
  func automaticPilotSelectionPrefersRangeThenFuelEfficiency() throws {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let shortRange = capability(
      id: 1,
      name: "Short Range",
      jdc: 4,
      jfc: 5,
      jf: 5,
      source: source
    )
    let expensive = capability(
      id: 2,
      name: "Expensive",
      jdc: 5,
      jfc: 3,
      jf: 4,
      source: source
    )
    let efficient = capability(
      id: 3,
      name: "Efficient",
      jdc: 5,
      jfc: 5,
      jf: 5,
      source: source
    )

    let selected = JumpFreighterPilotSelector.select(
      configuration: .init(),
      capabilities: [shortRange, expensive, efficient]
    )

    #expect(selected?.characterID == 3)
  }

  @Test
  func calculatesFlightsAndFourIsotopeAverage() throws {
    let route = route(fuelPerFlight: 100)
    let market = PreparedMarketOrderBook(
      snapshot: market(prices: [10, 20, 30, 40])
    )
    let result = JumpFreighterLogisticsCalculator.calculate(
      configuration: .init(isEnabled: true, usableCargoCapacityM3: 10),
      route: route,
      cargo: [
        LogisticsCargoItem(
          typeID: 999,
          quantity: 2,
          collateral: nil,
          packagedVolumePerUnit: 6,
          name: "Test Cargo"
        )
      ],
      mainHubMarket: market
    )

    let breakdown = try #require(result.breakdown)
    #expect(result.status == .calculated)
    #expect(breakdown.flights.count == 2)
    #expect(breakdown.averageIsotopeUnitPrice == 25)
    #expect(breakdown.totalIsotopeQuantity == 200)
    #expect(breakdown.totalCost == 5_000)
  }

  @Test
  func oneMissingIsotopePriceKeepsCostUnavailable() {
    let result = JumpFreighterLogisticsCalculator.calculate(
      configuration: .init(isEnabled: true, usableCargoCapacityM3: 10),
      route: route(fuelPerFlight: 100),
      cargo: [
        LogisticsCargoItem(
          typeID: 999,
          quantity: 1,
          collateral: nil,
          packagedVolumePerUnit: 1,
          name: "Test Cargo"
        )
      ],
      mainHubMarket: PreparedMarketOrderBook(
        snapshot: market(prices: [10, 20, 30])
      )
    )

    #expect(result.status == .unavailable)
    #expect(result.breakdown == nil)
    #expect(
      result.warnings.contains {
        $0.code == "jump-freighter.isotope-price-unavailable"
          && $0.severity == .blocking
      }
    )
  }

  @Test
  func zeroPackagedVolumeKeepsCostUnavailable() {
    let result = JumpFreighterLogisticsCalculator.calculate(
      configuration: .init(isEnabled: true, usableCargoCapacityM3: 10),
      route: route(fuelPerFlight: 100),
      cargo: [
        LogisticsCargoItem(
          typeID: 999,
          quantity: 1,
          collateral: nil,
          packagedVolumePerUnit: 0,
          name: "Test Cargo"
        )
      ],
      mainHubMarket: PreparedMarketOrderBook(
        snapshot: market(prices: [10, 20, 30, 40])
      )
    )

    #expect(result.status == .unavailable)
    #expect(result.breakdown == nil)
    #expect(
      result.warnings.contains {
        $0.code == "jump-freighter.missing-packaged-volume"
          && $0.severity == .blocking
      }
    )
  }

  @Test
  func nonJumpFreighterCapitalRouteIgnoresJumpFreightersSkill() throws {
    let request = CapitalJumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      capitalTypeID: 28_352,
      capitalName: "Rorqual",
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )

    let url = try DOTLANJumpRouteService.url(for: request)

    #expect(
      url.absoluteString
        == "https://evemaps.dotlan.net/jump/Rorqual,550/UALX-3:C-J6MT"
    )
  }

  @Test
  func producedJumpFreighterSelfJumpUsesJumpFreightersSkill() throws {
    let request = CapitalJumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      capitalTypeID: JumpFreighterHull.ark.typeID,
      capitalName: JumpFreighterHull.ark.name,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )

    let url = try DOTLANJumpRouteService.url(for: request)

    #expect(
      url.absoluteString
        == "https://evemaps.dotlan.net/jump/Ark,555/UALX-3:C-J6MT"
    )
  }

  @Test
  func fixedRouteAcceptsCompleteRouteIncludingItsEndpoints() throws {
    let profile = JumpRouteProfile(
      name: "Saved complete route",
      waypoints: [
        JumpRouteWaypoint(
          solarSystemID: 30_004_807,
          solarSystemName: "UALX-3"
        ),
        JumpRouteWaypoint(
          solarSystemID: 30_004_900,
          solarSystemName: "B9E-H6"
        ),
        JumpRouteWaypoint(
          solarSystemID: 30_004_714,
          solarSystemName: "C-J6MT"
        ),
      ]
    )

    let pairs = try DOTLANJumpRouteService.fixedRoutePairs(
      origin: "UALX-3",
      destination: "C-J6MT",
      profile: profile
    )

    #expect(pairs.count == 2)
    #expect(pairs[0].origin == "UALX-3")
    #expect(pairs[0].destination == "B9E-H6")
    #expect(pairs[1].origin == "B9E-H6")
    #expect(pairs[1].destination == "C-J6MT")
  }

  @Test
  func fixedCapitalRouteRetainsItsAssignedProfile() throws {
    let pilot = pilot(name: "Capital Pilot", jdc: 5, jfc: 5, jf: 0)
    let request = CapitalJumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      capitalTypeID: 28_352,
      capitalName: "Rorqual",
      pilot: pilot
    )
    let profile = JumpRouteProfile(name: "Capital route")
    let segment = CapitalJumpRouteSnapshot(
      request: request,
      legs: [
        JumpRouteLeg(
          originSystemName: "UALX-3",
          destinationSystemName: "C-J6MT",
          distanceLightYears: 5,
          isotopeQuantity: 10_000
        )
      ],
      totalDistanceLightYears: 5,
      isotope: .oxygen,
      isotopeQuantityPerHull: 10_000,
      isotopeVolumePerHullM3: 300,
      sourceURL: URL(string: "https://evemaps.dotlan.net/jump")!,
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )

    let combined = try DOTLANJumpRouteService.combineFixedRoute(
      request: request,
      profile: profile,
      segments: [segment]
    )

    #expect(combined.routeProfile?.profileID == profile.id)
    #expect(combined.isotopeQuantityPerHull == 10_000)
  }

  @Test
  func parsesRetainedRorqualSelfJumpRoute() throws {
    let request = CapitalJumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      capitalTypeID: 28_352,
      capitalName: "Rorqual",
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 0)
    )
    let html = retainedDotlanHTML()
      .replacingOccurrences(of: "20,978", with: "19,071")
      .replacingOccurrences(of: "12,052", with: "10,956")
      .replacingOccurrences(of: "11,660", with: "10,600")
      .replacingOccurrences(of: "44,690", with: "40,627")
      .replacingOccurrences(of: "Helium Isotopes", with: "Oxygen Isotopes")
      .replacingOccurrences(of: "1,341", with: "1,219")

    let route = try DOTLANJumpRouteService.parse(
      html: html,
      request: request,
      sourceURL: try #require(
        URL(string: "https://evemaps.dotlan.net/jump/Rorqual,550/UALX-3:C-J6MT")
      ),
      capturedAt: Date(timeIntervalSince1970: 1)
    )

    #expect(route.isotope == .oxygen)
    #expect(route.isotopeQuantityPerHull == 40_627)
    #expect(route.legs.count == 3)
  }

  @Test
  func capitalPilotDoesNotRequireJumpFreightersSkill() throws {
    let source = SourceIdentity(provider: "ESI", version: "fixture")
    let selected = CapitalJumpPilotSelector.select(
      configuration: .init(),
      capabilities: [
        capability(
          id: 7,
          name: "Capital Pilot",
          jdc: 5,
          jfc: 4,
          jf: 0,
          source: source
        )
      ]
    )

    #expect(selected?.characterID == 7)
    #expect(selected?.jumpFreightersLevel == 0)
  }

  @Test
  func producedCapitalQuantityMultipliesSelfJumpFuel() throws {
    let product = CapitalSelfJumpProduct(
      typeID: 28_352,
      name: "Rorqual",
      groupName: "Capital Industrial Ship"
    )
    let request = CapitalJumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      capitalTypeID: product.typeID,
      capitalName: product.name,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 0)
    )
    let route = CapitalJumpRouteSnapshot(
      request: request,
      legs: [
        JumpRouteLeg(
          originSystemName: "UALX-3",
          destinationSystemName: "C-J6MT",
          distanceLightYears: 20.314,
          isotopeQuantity: 40_627
        )
      ],
      totalDistanceLightYears: 20.314,
      isotope: .oxygen,
      isotopeQuantityPerHull: 40_627,
      isotopeVolumePerHullM3: 1_219,
      sourceURL: URL(string: "https://evemaps.dotlan.net/jump")!,
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )
    let result = CapitalSelfJumpCalculator.calculate(
      products: [(product, 2)],
      routes: [
        product.typeID: Sourced(
          state: .fresh,
          value: route,
          source: route.source
        )
      ],
      routeWarnings: [],
      mainHubMarket: PreparedMarketOrderBook(
        snapshot: market(prices: [10, 20, 30, 40])
      )
    )

    let breakdown = try #require(result.breakdown)
    #expect(result.status == .calculated)
    #expect(breakdown.jumps.first?.quantity == 2)
    #expect(breakdown.totalIsotopeQuantity == 81_254)
    #expect(breakdown.totalCost == 2_031_350)
  }

  @Test
  func onlyJumpCapableCapitalGroupsSelfJump() {
    let rorqual = IndustryItemClassification(
      categoryName: "Ship",
      groupName: "Capital Industrial Ship",
      manufacturingCategory: .capital
    )
    let freighter = IndustryItemClassification(
      categoryName: "Ship",
      groupName: "Freighter",
      manufacturingCategory: .capital
    )

    #expect(
      CapitalSelfJumpPolicy.product(
        typeID: 28_352,
        name: "Rorqual",
        classification: rorqual
      ) != nil
    )
    #expect(
      CapitalSelfJumpPolicy.product(
        typeID: 20_160,
        name: "Providence",
        classification: freighter
      ) == nil
    )
    let jumpFreighterAsLargeShip = IndustryItemClassification(
      categoryName: "Ship",
      groupName: "Jump Freighter",
      manufacturingCategory: .large
    )
    #expect(
      CapitalSelfJumpPolicy.product(
        typeID: 28_850,
        name: "Ark",
        classification: jumpFreighterAsLargeShip
      ) != nil
    )
    #expect(JumpRouteClass(groupName: "Supercarrier") == .supercarrier)
    #expect(JumpRouteClass(groupName: "Carrier") == .carrier)
    #expect(
      JumpRouteClass(groupName: "Force Auxiliary") == .forceAuxiliary
    )
    #expect(
      JumpRouteClass(groupName: "Capital Industrial Ship")
        == .capitalIndustrial
    )
  }

  @Test
  func historicalRouteAssessmentWithoutJumpBreakdownStillDecodes() throws {
    let data = try #require(
      """
      {"status":"notRequired","origin":"Home","destination":"Coalition","cost":0}
      """.data(using: .utf8)
    )

    let assessment = try JSONDecoder().decode(
      LogisticsRouteAssessment.self,
      from: data
    )

    #expect(assessment.jumpFreighter == nil)
    #expect(assessment.selfJumpingCapitals == nil)
    #expect(assessment.cost == 0)
  }

  private func route(fuelPerFlight: Int64) -> JumpRouteSnapshot {
    let request = JumpRouteRequest(
      originSystemName: "UALX-3",
      destinationSystemName: "C-J6MT",
      hull: .ark,
      pilot: pilot(name: "Xanira", jdc: 5, jfc: 5, jf: 5)
    )
    return JumpRouteSnapshot(
      request: request,
      legs: [
        JumpRouteLeg(
          originSystemName: "UALX-3",
          destinationSystemName: "C-J6MT",
          distanceLightYears: 5,
          isotopeQuantity: fuelPerFlight
        )
      ],
      totalDistanceLightYears: 5,
      isotope: .helium,
      isotopeQuantityPerFlight: fuelPerFlight,
      isotopeVolumePerFlightM3: Double(fuelPerFlight) * 0.03,
      sourceURL: URL(string: "https://evemaps.dotlan.net/jump")!,
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )
  }

  private func directRoute(
    origin: String,
    destination: String,
    fuel: Int64,
    distance: Double,
    pilot: JumpFreighterPilot
  ) -> JumpRouteSnapshot {
    let request = JumpRouteRequest(
      originSystemName: origin,
      destinationSystemName: destination,
      hull: .ark,
      pilot: pilot
    )
    return JumpRouteSnapshot(
      request: request,
      legs: [
        JumpRouteLeg(
          originSystemName: origin,
          destinationSystemName: destination,
          distanceLightYears: distance,
          isotopeQuantity: fuel
        )
      ],
      totalDistanceLightYears: distance,
      isotope: .helium,
      isotopeQuantityPerFlight: fuel,
      isotopeVolumePerFlightM3: Double(fuel) * 0.03,
      sourceURL: URL(
        string:
          "https://evemaps.dotlan.net/jump/Ark,555/\(origin):\(destination)"
      )!,
      source: SourceIdentity(provider: "DOTLAN", version: "fixture")
    )
  }

  private func retainedDotlanHTML() -> String {
    """
    <h2>Jump Route:</h2><table>
    <a class="igb link-5-30004807">UALX-3</a>
    <a class="igb link-5-30004777">EIH-IU</a>
    Distance: <b>9.536 ly</b> Fuel needed: <b>20,978</b>
    <a class="igb link-5-30004777">EIH-IU</a>
    <a class="igb link-5-30004759">5DE-QS</a>
    Distance: <b>5.478 ly</b> Fuel needed: <b>12,052</b>
    <a class="igb link-5-30004759">5DE-QS</a>
    <a class="igb link-5-30004714">C-J6MT</a>
    Distance: <b>5.3 ly</b> Fuel needed: <b>11,660</b>
    Total travel distance</td><td><b>20.314 lightyears</b>
    Total fuel consumption:</td><td><b>44,690 Helium Isotopes</b> (1,341 m&sup3;)
    </table>
    """
  }

  private func market(prices: [Double]) -> MarketOrderSnapshot {
    var orders: [Int64: [MarketOrder]] = [:]
    for (index, isotope) in JumpFuelIsotope.allCases.enumerated()
    where index < prices.count {
      orders[isotope.typeID] = [
        MarketOrder(
          id: Int64(index + 1),
          typeID: isotope.typeID,
          locationID: ProcurementLocation.jita.locationID!,
          systemID: ProcurementLocation.jita.solarSystemID!,
          side: .sell,
          price: prices[index],
          volumeRemaining: 1_000_000,
          minimumVolume: 1,
          issued: .now
        )
      ]
    }
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: ProcurementLocation.jita.regionID!,
      locationID: ProcurementLocation.jita.locationID!,
      capturedAt: .now,
      state: .fresh,
      ordersByType: orders,
      source: SourceIdentity(provider: "ESI", version: "fixture")
    )
  }

  private func pilot(
    name: String,
    jdc: Int,
    jfc: Int,
    jf: Int
  ) -> JumpFreighterPilot {
    JumpFreighterPilot(
      characterID: 42,
      characterName: name,
      jumpDriveCalibrationLevel: jdc,
      jumpFuelConservationLevel: jfc,
      jumpFreightersLevel: jf,
      skillSource: SourceIdentity(provider: "ESI", version: "fixture")
    )
  }

  private func capability(
    id: Int64,
    name: String,
    jdc: Int,
    jfc: Int,
    jf: Int,
    source: SourceIdentity
  ) -> CharacterCapabilitySnapshot {
    CharacterCapabilitySnapshot(
      character: CharacterIdentity(id: id, name: name),
      cloneState: .omega,
      skills: Sourced(
        state: .fresh,
        value: [
          TrainedSkill(
            skillID: JumpFreighterPilot.jumpDriveCalibrationSkillTypeID,
            trainedLevel: jdc,
            activeLevel: jdc,
            skillpoints: 1
          ),
          TrainedSkill(
            skillID: JumpFreighterPilot.jumpFuelConservationSkillTypeID,
            trainedLevel: jfc,
            activeLevel: jfc,
            skillpoints: 1
          ),
          TrainedSkill(
            skillID: JumpFreighterPilot.jumpFreightersSkillTypeID,
            trainedLevel: jf,
            activeLevel: jf,
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
  }
}
