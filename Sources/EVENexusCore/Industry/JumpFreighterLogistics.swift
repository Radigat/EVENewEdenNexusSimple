import Foundation

public enum JumpFuelIsotope: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case helium
  case oxygen
  case nitrogen
  case hydrogen

  public var id: Int64 { typeID }

  public var typeID: Int64 {
    switch self {
    case .helium: 16_274
    case .oxygen: 17_887
    case .nitrogen: 17_888
    case .hydrogen: 17_889
    }
  }

  public var name: String {
    switch self {
    case .helium: "Helium Isotopes"
    case .oxygen: "Oxygen Isotopes"
    case .nitrogen: "Nitrogen Isotopes"
    case .hydrogen: "Hydrogen Isotopes"
    }
  }

  public static let marketTypeIDs = Set(allCases.map(\.typeID))
}

public enum JumpFreighterHull: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case rhea
  case nomad
  case anshar
  case ark

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .rhea: "Rhea"
    case .nomad: "Nomad"
    case .anshar: "Anshar"
    case .ark: "Ark"
    }
  }

  public var typeID: Int64 {
    switch self {
    case .rhea: 28_844
    case .nomad: 28_846
    case .anshar: 28_848
    case .ark: 28_850
    }
  }

  public var fuelIsotope: JumpFuelIsotope {
    switch self {
    case .rhea: .nitrogen
    case .nomad: .hydrogen
    case .anshar: .oxygen
    case .ark: .helium
    }
  }
}

public enum JumpRouteClass: String, Codable, CaseIterable, Identifiable,
  Sendable
{
  case jumpFreighter
  case carrier
  case dreadnought
  case forceAuxiliary
  case supercarrier
  case titan
  case capitalIndustrial

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .jumpFreighter: "Jump Freighter"
    case .carrier: "Carrier"
    case .dreadnought: "Dreadnought"
    case .forceAuxiliary: "Force Auxiliary"
    case .supercarrier: "Supercarrier"
    case .titan: "Titan"
    case .capitalIndustrial: "Capital Industrial Ship"
    }
  }

  public init?(groupName: String) {
    let group = groupName.lowercased()
    if group.contains("jump freighter") {
      self = .jumpFreighter
    } else if group.contains("supercarrier") {
      self = .supercarrier
    } else if group.contains("force auxiliary") {
      self = .forceAuxiliary
    } else if group.contains("dreadnought") {
      self = .dreadnought
    } else if group.contains("carrier") {
      self = .carrier
    } else if group.contains("titan") {
      self = .titan
    } else if group.contains("capital industrial") {
      self = .capitalIndustrial
    } else {
      return nil
    }
  }
}

public struct JumpRouteWaypoint: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var solarSystemID: Int64
  public var solarSystemName: String
  public var structureName: String

  public init(
    id: UUID = UUID(),
    solarSystemID: Int64 = 0,
    solarSystemName: String = "",
    structureName: String = ""
  ) {
    self.id = id
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.structureName = structureName
  }

  public var isResolved: Bool {
    solarSystemID > 0
      && !solarSystemName.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
  }
}

public struct JumpRouteProfile: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var waypoints: [JumpRouteWaypoint]

  public init(
    id: UUID = UUID(),
    name: String = "New jump route",
    waypoints: [JumpRouteWaypoint] = []
  ) {
    self.id = id
    self.name = name
    self.waypoints = waypoints
  }

  public var isResolved: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && waypoints.allSatisfy(\.isResolved)
  }
}

public struct JumpRouteAssignment: Codable, Equatable, Sendable {
  public let routeClass: JumpRouteClass
  public var profileID: UUID

  public init(routeClass: JumpRouteClass, profileID: UUID) {
    self.routeClass = routeClass
    self.profileID = profileID
  }
}

public struct JumpRouteProfileReference: Codable, Equatable, Sendable {
  public let profileID: UUID
  public let name: String
  public let waypoints: [JumpRouteWaypoint]

  public init(profile: JumpRouteProfile) {
    profileID = profile.id
    name = profile.name
    waypoints = profile.waypoints
  }
}

public struct JumpFreighterLogisticsConfiguration: Codable, Equatable,
  Sendable
{
  public static let ruleVersion = "dotlan-jump-freighter-average-isotopes-2026-08-15"
  public static let pricePolicy = "main-hub-lowest-sell-average-four-isotopes-v1"
  public static let defaultUsableCargoCapacityM3 = 350_000.0

  public var isEnabled: Bool
  public var hull: JumpFreighterHull
  /// `nil` means that the best currently synchronized eligible character is
  /// selected for each calculation.
  public var pilotCharacterID: Int64?
  public var usableCargoCapacityM3: Double
  public var routeProfiles: [JumpRouteProfile]
  public var routeAssignments: [JumpRouteAssignment]
  public var ruleVersion: String

  public init(
    isEnabled: Bool = false,
    hull: JumpFreighterHull = .ark,
    pilotCharacterID: Int64? = nil,
    usableCargoCapacityM3: Double = Self.defaultUsableCargoCapacityM3,
    routeProfiles: [JumpRouteProfile] = [],
    routeAssignments: [JumpRouteAssignment] = [],
    ruleVersion: String = Self.ruleVersion
  ) {
    self.isEnabled = isEnabled
    self.hull = hull
    self.pilotCharacterID = pilotCharacterID
    self.usableCargoCapacityM3 = usableCargoCapacityM3
    self.routeProfiles = routeProfiles
    self.routeAssignments = routeAssignments
    self.ruleVersion = ruleVersion
  }

  private enum CodingKeys: String, CodingKey {
    case isEnabled
    case hull
    case pilotCharacterID
    case usableCargoCapacityM3
    case routeProfiles
    case routeAssignments
    case ruleVersion
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    hull = try container.decodeIfPresent(JumpFreighterHull.self, forKey: .hull) ?? .ark
    pilotCharacterID = try container.decodeIfPresent(
      Int64.self,
      forKey: .pilotCharacterID
    )
    usableCargoCapacityM3 =
      try container.decodeIfPresent(
        Double.self,
        forKey: .usableCargoCapacityM3
      ) ?? Self.defaultUsableCargoCapacityM3
    routeProfiles =
      try container.decodeIfPresent(
        [JumpRouteProfile].self,
        forKey: .routeProfiles
      ) ?? []
    routeAssignments =
      try container.decodeIfPresent(
        [JumpRouteAssignment].self,
        forKey: .routeAssignments
      ) ?? []
    ruleVersion =
      try container.decodeIfPresent(String.self, forKey: .ruleVersion)
      ?? Self.ruleVersion
  }

  public var effectiveUsableCargoCapacityM3: Double? {
    guard usableCargoCapacityM3.isFinite, usableCargoCapacityM3 > 0 else {
      return nil
    }
    return usableCargoCapacityM3
  }

  public func assignedProfile(for routeClass: JumpRouteClass)
    -> JumpRouteProfile?
  {
    guard let profileID = assignedProfileID(for: routeClass) else { return nil }
    return routeProfiles.first { $0.id == profileID }
  }

  public func assignedProfileID(for routeClass: JumpRouteClass) -> UUID? {
    routeAssignments.last(where: {
      $0.routeClass == routeClass
    })?.profileID
  }

  public mutating func assign(
    profileID: UUID?,
    to routeClass: JumpRouteClass
  ) {
    routeAssignments.removeAll { $0.routeClass == routeClass }
    guard let profileID else { return }
    routeAssignments.append(
      JumpRouteAssignment(routeClass: routeClass, profileID: profileID)
    )
  }

  public mutating func removeRouteProfile(id: UUID) {
    routeProfiles.removeAll { $0.id == id }
    routeAssignments.removeAll { $0.profileID == id }
  }
}

public struct JumpFreighterPilot: Codable, Equatable, Sendable {
  public static let jumpFuelConservationSkillTypeID: Int64 = 21_610
  public static let jumpDriveCalibrationSkillTypeID: Int64 = 21_611
  public static let jumpFreightersSkillTypeID: Int64 = 29_029

  public let characterID: Int64
  public let characterName: String
  public let jumpDriveCalibrationLevel: Int
  public let jumpFuelConservationLevel: Int
  public let jumpFreightersLevel: Int
  public let skillSource: SourceIdentity

  public init(
    characterID: Int64,
    characterName: String,
    jumpDriveCalibrationLevel: Int,
    jumpFuelConservationLevel: Int,
    jumpFreightersLevel: Int,
    skillSource: SourceIdentity
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.jumpDriveCalibrationLevel = jumpDriveCalibrationLevel
    self.jumpFuelConservationLevel = jumpFuelConservationLevel
    self.jumpFreightersLevel = jumpFreightersLevel
    self.skillSource = skillSource
  }
}

public enum JumpFreighterPilotSelector {
  public static func select(
    configuration: JumpFreighterLogisticsConfiguration,
    capabilities: [CharacterCapabilitySnapshot]
  ) -> JumpFreighterPilot? {
    let candidates = capabilities.compactMap(eligiblePilot)
    if let fixedID = configuration.pilotCharacterID {
      return candidates.first { $0.characterID == fixedID }
    }
    return candidates.sorted { lhs, rhs in
      if lhs.jumpDriveCalibrationLevel != rhs.jumpDriveCalibrationLevel {
        return lhs.jumpDriveCalibrationLevel > rhs.jumpDriveCalibrationLevel
      }
      let lhsFuel = fuelMultiplier(lhs)
      let rhsFuel = fuelMultiplier(rhs)
      if lhsFuel != rhsFuel { return lhsFuel < rhsFuel }
      let comparison = lhs.characterName.localizedCaseInsensitiveCompare(
        rhs.characterName
      )
      if comparison != .orderedSame { return comparison == .orderedAscending }
      return lhs.characterID < rhs.characterID
    }.first
  }

  private static func eligiblePilot(
    _ capability: CharacterCapabilitySnapshot
  ) -> JumpFreighterPilot? {
    guard capability.skills.state == .fresh,
      let skills = capability.skills.value
    else { return nil }
    let levels = Dictionary(
      skills.map { ($0.skillID, $0.activeLevel) },
      uniquingKeysWith: max
    )
    let calibration = levels[JumpFreighterPilot.jumpDriveCalibrationSkillTypeID] ?? 0
    let conservation = levels[JumpFreighterPilot.jumpFuelConservationSkillTypeID] ?? 0
    let freighters = levels[JumpFreighterPilot.jumpFreightersSkillTypeID] ?? 0
    guard calibration > 0, freighters > 0 else { return nil }
    return JumpFreighterPilot(
      characterID: capability.character.id,
      characterName: capability.character.name,
      jumpDriveCalibrationLevel: calibration,
      jumpFuelConservationLevel: conservation,
      jumpFreightersLevel: freighters,
      skillSource: capability.skills.source
    )
  }

  private static func fuelMultiplier(_ pilot: JumpFreighterPilot) -> Double {
    (1 - 0.1 * Double(pilot.jumpFuelConservationLevel))
      * (1 - 0.1 * Double(pilot.jumpFreightersLevel))
  }
}

/// Selects the synchronized character used to estimate a self-propelled
/// capital route. The third DOTLAN skill digit remains zero because the
/// Jump Freighters skill does not reduce fuel for other capital hulls.
public enum CapitalJumpPilotSelector {
  public static func select(
    configuration: JumpFreighterLogisticsConfiguration,
    capabilities: [CharacterCapabilitySnapshot]
  ) -> JumpFreighterPilot? {
    let candidates = capabilities.compactMap(eligiblePilot)
    if let fixedID = configuration.pilotCharacterID {
      return candidates.first { $0.characterID == fixedID }
    }
    return candidates.sorted { lhs, rhs in
      if lhs.jumpDriveCalibrationLevel != rhs.jumpDriveCalibrationLevel {
        return lhs.jumpDriveCalibrationLevel > rhs.jumpDriveCalibrationLevel
      }
      if lhs.jumpFuelConservationLevel != rhs.jumpFuelConservationLevel {
        return lhs.jumpFuelConservationLevel > rhs.jumpFuelConservationLevel
      }
      let comparison = lhs.characterName.localizedCaseInsensitiveCompare(
        rhs.characterName
      )
      if comparison != .orderedSame { return comparison == .orderedAscending }
      return lhs.characterID < rhs.characterID
    }.first
  }

  private static func eligiblePilot(
    _ capability: CharacterCapabilitySnapshot
  ) -> JumpFreighterPilot? {
    guard capability.skills.state == .fresh,
      let skills = capability.skills.value
    else { return nil }
    let levels = Dictionary(
      skills.map { ($0.skillID, $0.activeLevel) },
      uniquingKeysWith: max
    )
    let calibration = levels[JumpFreighterPilot.jumpDriveCalibrationSkillTypeID] ?? 0
    let conservation = levels[JumpFreighterPilot.jumpFuelConservationSkillTypeID] ?? 0
    guard calibration > 0 else { return nil }
    return JumpFreighterPilot(
      characterID: capability.character.id,
      characterName: capability.character.name,
      jumpDriveCalibrationLevel: calibration,
      jumpFuelConservationLevel: conservation,
      jumpFreightersLevel:
        levels[JumpFreighterPilot.jumpFreightersSkillTypeID] ?? 0,
      skillSource: capability.skills.source
    )
  }
}

public struct JumpRouteRequest: Codable, Equatable, Sendable {
  public let originSystemName: String
  public let destinationSystemName: String
  public let hull: JumpFreighterHull
  public let pilot: JumpFreighterPilot

  public init(
    originSystemName: String,
    destinationSystemName: String,
    hull: JumpFreighterHull,
    pilot: JumpFreighterPilot
  ) {
    self.originSystemName = originSystemName
    self.destinationSystemName = destinationSystemName
    self.hull = hull
    self.pilot = pilot
  }
}

public struct CapitalJumpRouteRequest: Codable, Equatable, Sendable {
  public let originSystemName: String
  public let destinationSystemName: String
  public let capitalTypeID: Int64
  public let capitalName: String
  public let pilot: JumpFreighterPilot

  public init(
    originSystemName: String,
    destinationSystemName: String,
    capitalTypeID: Int64,
    capitalName: String,
    pilot: JumpFreighterPilot
  ) {
    self.originSystemName = originSystemName
    self.destinationSystemName = destinationSystemName
    self.capitalTypeID = capitalTypeID
    self.capitalName = capitalName
    self.pilot = pilot
  }
}

public struct JumpRouteLeg: Identifiable, Codable, Equatable, Sendable {
  public var id: String { "\(originSystemName)->\(destinationSystemName)" }
  public let originSystemName: String
  public let destinationSystemName: String
  public let distanceLightYears: Double
  public let isotopeQuantity: Int64

  public init(
    originSystemName: String,
    destinationSystemName: String,
    distanceLightYears: Double,
    isotopeQuantity: Int64
  ) {
    self.originSystemName = originSystemName
    self.destinationSystemName = destinationSystemName
    self.distanceLightYears = distanceLightYears
    self.isotopeQuantity = isotopeQuantity
  }
}

public struct JumpRouteSnapshot: Codable, Equatable, Sendable {
  public static let providerVersion = "dotlan-jump-planner-html-2026-08-15"

  public let request: JumpRouteRequest
  public let legs: [JumpRouteLeg]
  public let totalDistanceLightYears: Double
  public let isotope: JumpFuelIsotope
  public let isotopeQuantityPerFlight: Int64
  public let isotopeVolumePerFlightM3: Double
  public let sourceURL: URL
  public let segmentSourceURLs: [URL]?
  public let routeProfile: JumpRouteProfileReference?
  public let source: SourceIdentity

  public init(
    request: JumpRouteRequest,
    legs: [JumpRouteLeg],
    totalDistanceLightYears: Double,
    isotope: JumpFuelIsotope,
    isotopeQuantityPerFlight: Int64,
    isotopeVolumePerFlightM3: Double,
    sourceURL: URL,
    segmentSourceURLs: [URL]? = nil,
    routeProfile: JumpRouteProfileReference? = nil,
    source: SourceIdentity
  ) {
    self.request = request
    self.legs = legs
    self.totalDistanceLightYears = totalDistanceLightYears
    self.isotope = isotope
    self.isotopeQuantityPerFlight = isotopeQuantityPerFlight
    self.isotopeVolumePerFlightM3 = isotopeVolumePerFlightM3
    self.sourceURL = sourceURL
    self.segmentSourceURLs = segmentSourceURLs
    self.routeProfile = routeProfile
    self.source = source
  }
}

public struct CapitalJumpRouteSnapshot: Codable, Equatable, Sendable {
  public static let providerVersion = JumpRouteSnapshot.providerVersion

  public let request: CapitalJumpRouteRequest
  public let legs: [JumpRouteLeg]
  public let totalDistanceLightYears: Double
  public let isotope: JumpFuelIsotope
  public let isotopeQuantityPerHull: Int64
  public let isotopeVolumePerHullM3: Double
  public let sourceURL: URL
  public let segmentSourceURLs: [URL]?
  public let routeProfile: JumpRouteProfileReference?
  public let source: SourceIdentity

  public init(
    request: CapitalJumpRouteRequest,
    legs: [JumpRouteLeg],
    totalDistanceLightYears: Double,
    isotope: JumpFuelIsotope,
    isotopeQuantityPerHull: Int64,
    isotopeVolumePerHullM3: Double,
    sourceURL: URL,
    segmentSourceURLs: [URL]? = nil,
    routeProfile: JumpRouteProfileReference? = nil,
    source: SourceIdentity
  ) {
    self.request = request
    self.legs = legs
    self.totalDistanceLightYears = totalDistanceLightYears
    self.isotope = isotope
    self.isotopeQuantityPerHull = isotopeQuantityPerHull
    self.isotopeVolumePerHullM3 = isotopeVolumePerHullM3
    self.sourceURL = sourceURL
    self.segmentSourceURLs = segmentSourceURLs
    self.routeProfile = routeProfile
    self.source = source
  }
}

public enum DOTLANJumpRouteError: Error, Equatable {
  case invalidRequest
  case invalidResponse
  case routeUnavailable
  case schemaChanged
  case invalidFixedRoute
}

public actor DOTLANJumpRouteService {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func route(for request: JumpRouteRequest) async throws
    -> JumpRouteSnapshot
  {
    let url = try Self.url(for: request)
    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 30
    urlRequest.setValue(
      CCPUserAgentConfiguration.genericValue,
      forHTTPHeaderField: "User-Agent"
    )
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode)
    else { throw DOTLANJumpRouteError.invalidResponse }
    guard let html = String(data: data, encoding: .utf8) else {
      throw DOTLANJumpRouteError.invalidResponse
    }
    return try Self.parse(
      html: html,
      request: request,
      sourceURL: url,
      capturedAt: .now
    )
  }

  public func route(for request: CapitalJumpRouteRequest) async throws
    -> CapitalJumpRouteSnapshot
  {
    let url = try Self.url(for: request)
    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 30
    urlRequest.setValue(
      CCPUserAgentConfiguration.genericValue,
      forHTTPHeaderField: "User-Agent"
    )
    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode)
    else { throw DOTLANJumpRouteError.invalidResponse }
    guard let html = String(data: data, encoding: .utf8) else {
      throw DOTLANJumpRouteError.invalidResponse
    }
    return try Self.parse(
      html: html,
      request: request,
      sourceURL: url,
      capturedAt: .now
    )
  }

  public func route(
    for request: JumpRouteRequest,
    via profile: JumpRouteProfile
  ) async throws -> JumpRouteSnapshot {
    let pairs = try Self.fixedRoutePairs(
      origin: request.originSystemName,
      destination: request.destinationSystemName,
      profile: profile
    )
    var segments: [JumpRouteSnapshot] = []
    for pair in pairs {
      let segmentRequest = JumpRouteRequest(
        originSystemName: pair.origin,
        destinationSystemName: pair.destination,
        hull: request.hull,
        pilot: request.pilot
      )
      let segment = try await route(for: segmentRequest)
      guard
        segment.legs.count == 1,
        segment.legs.first?.originSystemName == pair.origin,
        segment.legs.first?.destinationSystemName == pair.destination
      else { throw DOTLANJumpRouteError.invalidFixedRoute }
      segments.append(segment)
    }
    return try Self.combineFixedRoute(
      request: request,
      profile: profile,
      segments: segments
    )
  }

  public func route(
    for request: CapitalJumpRouteRequest,
    via profile: JumpRouteProfile
  ) async throws -> CapitalJumpRouteSnapshot {
    let pairs = try Self.fixedRoutePairs(
      origin: request.originSystemName,
      destination: request.destinationSystemName,
      profile: profile
    )
    var segments: [CapitalJumpRouteSnapshot] = []
    for pair in pairs {
      let segmentRequest = CapitalJumpRouteRequest(
        originSystemName: pair.origin,
        destinationSystemName: pair.destination,
        capitalTypeID: request.capitalTypeID,
        capitalName: request.capitalName,
        pilot: request.pilot
      )
      let segment = try await route(for: segmentRequest)
      guard
        segment.legs.count == 1,
        segment.legs.first?.originSystemName == pair.origin,
        segment.legs.first?.destinationSystemName == pair.destination
      else { throw DOTLANJumpRouteError.invalidFixedRoute }
      segments.append(segment)
    }
    return try Self.combineFixedRoute(
      request: request,
      profile: profile,
      segments: segments
    )
  }

  static func combineFixedRoute(
    request: JumpRouteRequest,
    profile: JumpRouteProfile,
    segments: [JumpRouteSnapshot]
  ) throws -> JumpRouteSnapshot {
    guard
      !segments.isEmpty,
      segments.allSatisfy({
        $0.legs.count == 1 && $0.isotope == request.hull.fuelIsotope
      })
    else { throw DOTLANJumpRouteError.invalidFixedRoute }
    let totals = try fixedRouteTotals(
      legs: segments.flatMap(\.legs),
      volumes: segments.map(\.isotopeVolumePerFlightM3)
    )
    return JumpRouteSnapshot(
      request: request,
      legs: totals.legs,
      totalDistanceLightYears: totals.distance,
      isotope: request.hull.fuelIsotope,
      isotopeQuantityPerFlight: totals.fuel,
      isotopeVolumePerFlightM3: totals.volume,
      sourceURL: segments[0].sourceURL,
      segmentSourceURLs: segments.map(\.sourceURL),
      routeProfile: JumpRouteProfileReference(profile: profile),
      source: fixedRouteSource(segments.map(\.source))
    )
  }

  static func combineFixedRoute(
    request: CapitalJumpRouteRequest,
    profile: JumpRouteProfile,
    segments: [CapitalJumpRouteSnapshot]
  ) throws -> CapitalJumpRouteSnapshot {
    guard
      !segments.isEmpty,
      let isotope = segments.first?.isotope,
      segments.allSatisfy({ $0.legs.count == 1 && $0.isotope == isotope })
    else { throw DOTLANJumpRouteError.invalidFixedRoute }
    let totals = try fixedRouteTotals(
      legs: segments.flatMap(\.legs),
      volumes: segments.map(\.isotopeVolumePerHullM3)
    )
    return CapitalJumpRouteSnapshot(
      request: request,
      legs: totals.legs,
      totalDistanceLightYears: totals.distance,
      isotope: isotope,
      isotopeQuantityPerHull: totals.fuel,
      isotopeVolumePerHullM3: totals.volume,
      sourceURL: segments[0].sourceURL,
      segmentSourceURLs: segments.map(\.sourceURL),
      routeProfile: JumpRouteProfileReference(profile: profile),
      source: fixedRouteSource(segments.map(\.source))
    )
  }

  public static func url(for request: JumpRouteRequest) throws -> URL {
    let values = [
      request.originSystemName,
      request.destinationSystemName,
      request.hull.name,
    ]
    guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    else { throw DOTLANJumpRouteError.invalidRequest }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "evemaps.dotlan.net"
    let skills =
      "\(request.pilot.jumpDriveCalibrationLevel)\(request.pilot.jumpFuelConservationLevel)\(request.pilot.jumpFreightersLevel)"
    components.path =
      "/jump/\(request.hull.name),\(skills)/\(request.originSystemName):\(request.destinationSystemName)"
    guard let url = components.url else {
      throw DOTLANJumpRouteError.invalidRequest
    }
    return url
  }

  public static func url(for request: CapitalJumpRouteRequest) throws -> URL {
    let jumpFreightersLevel =
      JumpFreighterHull.allCases.contains {
        $0.typeID == request.capitalTypeID
      }
      ? request.pilot.jumpFreightersLevel : 0
    return try url(
      shipName: request.capitalName,
      skillDigits:
        "\(request.pilot.jumpDriveCalibrationLevel)\(request.pilot.jumpFuelConservationLevel)\(jumpFreightersLevel)",
      originSystemName: request.originSystemName,
      destinationSystemName: request.destinationSystemName
    )
  }

  public static func parse(
    html: String,
    request: JumpRouteRequest,
    sourceURL: URL,
    capturedAt: Date
  ) throws -> JumpRouteSnapshot {
    let evidence = try parseEvidence(
      html: html,
      originSystemName: request.originSystemName,
      destinationSystemName: request.destinationSystemName,
      expectedIsotope: request.hull.fuelIsotope
    )
    return JumpRouteSnapshot(
      request: request,
      legs: evidence.legs,
      totalDistanceLightYears: evidence.totalDistanceLightYears,
      isotope: evidence.isotope,
      isotopeQuantityPerFlight: evidence.isotopeQuantity,
      isotopeVolumePerFlightM3: evidence.isotopeVolumeM3,
      sourceURL: sourceURL,
      source: SourceIdentity(
        provider: "DOTLAN EveMaps",
        version: JumpRouteSnapshot.providerVersion,
        capturedAt: capturedAt
      )
    )
  }

  public static func parse(
    html: String,
    request: CapitalJumpRouteRequest,
    sourceURL: URL,
    capturedAt: Date
  ) throws -> CapitalJumpRouteSnapshot {
    let evidence = try parseEvidence(
      html: html,
      originSystemName: request.originSystemName,
      destinationSystemName: request.destinationSystemName,
      expectedIsotope: nil
    )
    return CapitalJumpRouteSnapshot(
      request: request,
      legs: evidence.legs,
      totalDistanceLightYears: evidence.totalDistanceLightYears,
      isotope: evidence.isotope,
      isotopeQuantityPerHull: evidence.isotopeQuantity,
      isotopeVolumePerHullM3: evidence.isotopeVolumeM3,
      sourceURL: sourceURL,
      source: SourceIdentity(
        provider: "DOTLAN EveMaps",
        version: CapitalJumpRouteSnapshot.providerVersion,
        capturedAt: capturedAt
      )
    )
  }

  private struct ParsedEvidence {
    let legs: [JumpRouteLeg]
    let totalDistanceLightYears: Double
    let isotope: JumpFuelIsotope
    let isotopeQuantity: Int64
    let isotopeVolumeM3: Double
  }

  static func fixedRoutePairs(
    origin: String,
    destination: String,
    profile: JumpRouteProfile
  ) throws -> [(origin: String, destination: String)] {
    guard profile.isResolved else {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }
    let canonicalOrigin = origin.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let canonicalDestination = destination.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !canonicalOrigin.isEmpty, !canonicalDestination.isEmpty else {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }

    // Profiles created before endpoint normalization may contain the complete
    // route, including Home Hub and Coalition Hub. Newer profiles can contain
    // only the intermediate systems. Normalize both representations so a
    // complete saved route never produces artificial A -> A endpoint legs.
    var waypointSystems = profile.waypoints.map {
      $0.solarSystemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if waypointSystems.first?.caseInsensitiveCompare(canonicalOrigin)
      == .orderedSame
    {
      waypointSystems.removeFirst()
    }
    if waypointSystems.last?.caseInsensitiveCompare(canonicalDestination)
      == .orderedSame
    {
      waypointSystems.removeLast()
    }
    let systems = [canonicalOrigin] + waypointSystems + [canonicalDestination]
    guard systems.count >= 2 else {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }
    let pairs = zip(systems, systems.dropFirst()).map {
      (origin: $0.0, destination: $0.1)
    }
    guard
      pairs.allSatisfy({
        !$0.origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !$0.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
          && $0.origin != $0.destination
      })
    else { throw DOTLANJumpRouteError.invalidFixedRoute }
    return pairs
  }

  private static func fixedRouteTotals(
    legs: [JumpRouteLeg],
    volumes: [Double]
  ) throws -> (
    legs: [JumpRouteLeg], distance: Double, fuel: Int64, volume: Double
  ) {
    guard !legs.isEmpty, legs.count == volumes.count else {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }
    for index in legs.indices.dropFirst()
    where
      legs[index - 1].destinationSystemName != legs[index].originSystemName
    {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }
    var fuel: Int64 = 0
    for leg in legs {
      let (sum, overflow) = fuel.addingReportingOverflow(leg.isotopeQuantity)
      guard !overflow, leg.isotopeQuantity > 0 else {
        throw DOTLANJumpRouteError.invalidFixedRoute
      }
      fuel = sum
    }
    let distance = legs.reduce(0) { $0 + $1.distanceLightYears }
    let volume = volumes.reduce(0, +)
    guard distance.isFinite, distance > 0, volume.isFinite, volume > 0 else {
      throw DOTLANJumpRouteError.invalidFixedRoute
    }
    return (legs, distance, fuel, volume)
  }

  private static func fixedRouteSource(
    _ sources: [SourceIdentity]
  ) -> SourceIdentity {
    SourceIdentity(
      provider: "DOTLAN EveMaps · fixed route profile",
      version: JumpRouteSnapshot.providerVersion,
      capturedAt: sources.map(\.capturedAt).max() ?? .now
    )
  }

  private static func parseEvidence(
    html: String,
    originSystemName: String,
    destinationSystemName: String,
    expectedIsotope: JumpFuelIsotope?
  ) throws -> ParsedEvidence {
    guard !html.localizedCaseInsensitiveContains("no route found") else {
      throw DOTLANJumpRouteError.routeUnavailable
    }
    guard
      let totalDistanceText = firstCapture(
        pattern: #"Total travel distance.*?<b>([0-9.,]+) lightyears</b>"#,
        in: html
      ),
      let totalDistance = parseDecimal(totalDistanceText),
      let totalFuelMatch = captures(
        pattern: #"Total fuel consumption.*?<b>([0-9,]+) ([A-Za-z]+ Isotopes)</b>"#,
        in: html,
        captureGroups: [1, 2]
      ).first,
      let totalFuel = parseInteger(totalFuelMatch[0]),
      let isotope = JumpFuelIsotope.allCases.first(where: {
        $0.name == decodeHTMLEntities(totalFuelMatch[1])
      }),
      let totalVolumeText = firstCapture(
        pattern: #"Total fuel consumption.*?</b> \(([0-9,]+) m(?:³|&sup3;)\)"#,
        in: html
      ),
      let totalVolume = parseDecimal(totalVolumeText),
      totalDistance.isFinite,
      totalDistance > 0,
      totalFuel > 0,
      totalVolume.isFinite,
      totalVolume > 0,
      expectedIsotope == nil || isotope == expectedIsotope
    else { throw DOTLANJumpRouteError.schemaChanged }

    let routeArea =
      substring(
        html,
        from: "<h2>Jump Route:",
        through: "Total fuel consumption"
      ) ?? html
    let systems = captures(
      pattern: #"class=\"igb link-5-[0-9]+\"[^>]*>([^<]+)</a>"#,
      in: routeArea
    ).map(decodeHTMLEntities)
    let deduplicatedSystems = systems.reduce(into: [String]()) { values, name in
      if values.last != name { values.append(name) }
    }
    let legMatches = captures(
      pattern: #"Distance: <b>([0-9.,]+) ly</b>.*?Fuel needed: <b>([0-9,]+)</b>"#,
      in: routeArea,
      captureGroups: [1, 2]
    )
    var legs: [JumpRouteLeg] = []
    if deduplicatedSystems.count >= 2,
      legMatches.count == deduplicatedSystems.count - 1
    {
      for index in legMatches.indices {
        guard let distance = parseDecimal(legMatches[index][0]),
          distance.isFinite,
          distance > 0,
          let fuel = parseInteger(legMatches[index][1]),
          fuel > 0
        else { throw DOTLANJumpRouteError.schemaChanged }
        legs.append(
          JumpRouteLeg(
            originSystemName: deduplicatedSystems[index],
            destinationSystemName: deduplicatedSystems[index + 1],
            distanceLightYears: distance,
            isotopeQuantity: fuel
          )
        )
      }
    }
    guard !legs.isEmpty,
      legs.first?.originSystemName == originSystemName,
      legs.last?.destinationSystemName == destinationSystemName
    else { throw DOTLANJumpRouteError.schemaChanged }
    var legFuelTotal: Int64 = 0
    for leg in legs {
      let (sum, overflow) = legFuelTotal.addingReportingOverflow(leg.isotopeQuantity)
      guard !overflow else { throw DOTLANJumpRouteError.schemaChanged }
      legFuelTotal = sum
    }
    let legDistanceTotal = legs.reduce(0) { $0 + $1.distanceLightYears }
    let distanceTolerance = max(0.01, Double(legs.count) * 0.001)
    guard legFuelTotal == totalFuel,
      abs(legDistanceTotal - totalDistance) <= distanceTolerance
    else { throw DOTLANJumpRouteError.schemaChanged }
    return ParsedEvidence(
      legs: legs,
      totalDistanceLightYears: totalDistance,
      isotope: isotope,
      isotopeQuantity: totalFuel,
      isotopeVolumeM3: totalVolume
    )
  }

  private static func url(
    shipName: String,
    skillDigits: String,
    originSystemName: String,
    destinationSystemName: String
  ) throws -> URL {
    let values = [originSystemName, destinationSystemName, shipName]
    guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    else { throw DOTLANJumpRouteError.invalidRequest }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "evemaps.dotlan.net"
    components.path =
      "/jump/\(shipName),\(skillDigits)/\(originSystemName):\(destinationSystemName)"
    guard let url = components.url else {
      throw DOTLANJumpRouteError.invalidRequest
    }
    return url
  }

  private static func substring(
    _ value: String,
    from start: String,
    through end: String
  ) -> String? {
    guard let lower = value.range(of: start),
      let upper = value.range(of: end, range: lower.upperBound..<value.endIndex)
    else { return nil }
    return String(value[lower.lowerBound..<upper.upperBound])
  }

  private static func firstCapture(pattern: String, in value: String) -> String? {
    captures(pattern: pattern, in: value).first
  }

  private static func captures(
    pattern: String,
    in value: String
  ) -> [String] {
    captures(pattern: pattern, in: value, captureGroups: [1]).compactMap(\.first)
  }

  private static func captures(
    pattern: String,
    in value: String,
    captureGroups: [Int]
  ) -> [[String]] {
    guard
      let expression = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
      )
    else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap { match in
      let groups = captureGroups.compactMap { index -> String? in
        guard index < match.numberOfRanges,
          let range = Range(match.range(at: index), in: value)
        else { return nil }
        return String(value[range])
      }
      return groups.count == captureGroups.count ? groups : nil
    }
  }

  private static func parseInteger(_ value: String) -> Int64? {
    Int64(value.replacingOccurrences(of: ",", with: ""))
  }

  private static func parseDecimal(_ value: String) -> Double? {
    Double(value.replacingOccurrences(of: ",", with: ""))
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    value.replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&#039;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"")
  }
}

public struct JumpFuelPriceEntry: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { isotope.typeID }
  public let isotope: JumpFuelIsotope
  public let unitPrice: Double
  public let capturedAt: Date
  public let source: SourceIdentity
}

public struct JumpFreighterCargoLine: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String?
  public let quantity: Int64
  public let volumeM3: Double
}

public struct JumpFreighterFlight: Identifiable, Codable, Equatable, Sendable {
  public var id: Int { number }
  public let number: Int
  public let count: Int
  public let cargoVolumeM3: Double
  public let cargo: [JumpFreighterCargoLine]
}

public struct JumpFreighterCostBreakdown: Codable, Equatable, Sendable {
  public let ruleVersion: String
  public let pricePolicy: String
  public let hull: JumpFreighterHull
  public let pilot: JumpFreighterPilot
  public let route: JumpRouteSnapshot
  public let isotopePrices: [JumpFuelPriceEntry]
  public let averageIsotopeUnitPrice: Double
  public let usableCargoCapacityM3: Double
  public let flights: [JumpFreighterFlight]
  public let isotopeQuantityPerFlight: Int64
  public let totalIsotopeQuantity: Int64
  public let totalCost: Double
}

public struct CapitalSelfJumpProduct: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { typeID }
  public let typeID: Int64
  public let name: String
  public let groupName: String

  public init(typeID: Int64, name: String, groupName: String) {
    self.typeID = typeID
    self.name = name
    self.groupName = groupName
  }

  public var routeClass: JumpRouteClass? {
    JumpRouteClass(groupName: groupName)
  }
}

public struct CapitalSelfJumpLine: Identifiable, Codable, Equatable, Sendable {
  public var id: Int64 { product.typeID }
  public let product: CapitalSelfJumpProduct
  public let quantity: Int64
  public let route: CapitalJumpRouteSnapshot
  public let isotopeQuantityPerHull: Int64
  public let totalIsotopeQuantity: Int64
  public let totalCost: Double
}

public struct CapitalSelfJumpCostBreakdown: Codable, Equatable, Sendable {
  public static let ruleVersion = "self-propelled-capital-dotlan-2026-08-15"

  public let ruleVersion: String
  public let pricePolicy: String
  public let isotopePrices: [JumpFuelPriceEntry]
  public let averageIsotopeUnitPrice: Double
  public let jumps: [CapitalSelfJumpLine]
  public let totalIsotopeQuantity: Int64
  public let totalCost: Double
}

public enum CapitalSelfJumpPolicy {
  public static let ruleVersion = "self-propelled-capital-groups-2026-08-15"

  public static func product(
    typeID: Int64,
    name: String,
    classification: IndustryItemClassification?
  ) -> CapitalSelfJumpProduct? {
    guard
      classification?.categoryName.localizedCaseInsensitiveCompare("Ship")
        == .orderedSame,
      classification?.manufacturingCategory == .capital,
      let groupName = classification?.groupName,
      isSelfPropelledGroup(groupName)
    else { return nil }
    return CapitalSelfJumpProduct(
      typeID: typeID,
      name: name,
      groupName: groupName
    )
  }

  public static func product(for node: PlanNode) -> CapitalSelfJumpProduct? {
    guard
      node.sourceCategory?.localizedCaseInsensitiveCompare("Ship")
        == .orderedSame,
      node.manufacturingCategory == .capital,
      let groupName = node.sourceGroup,
      isSelfPropelledGroup(groupName)
    else { return nil }
    return CapitalSelfJumpProduct(
      typeID: node.typeID,
      name: node.name,
      groupName: groupName
    )
  }

  private static func isSelfPropelledGroup(_ groupName: String) -> Bool {
    JumpRouteClass(groupName: groupName) != nil
  }
}

private enum JumpFuelPriceBasis {
  static func quote(
    mainHubMarket: PreparedMarketOrderBook,
    warningCode: String
  ) -> (
    prices: [JumpFuelPriceEntry]?,
    average: Double?,
    warnings: [DomainWarning]
  ) {
    var prices: [JumpFuelPriceEntry] = []
    var warnings: [DomainWarning] = []
    for isotope in JumpFuelIsotope.allCases {
      let quote = mainHubMarket.quote(
        typeID: isotope.typeID,
        quantity: 1,
        scenario: .materialBuy
      )
      guard quote.isComplete,
        let unitPrice = quote.weightedUnitPrice,
        unitPrice.isFinite,
        unitPrice > 0
      else {
        warnings.append(
          DomainWarning(
            code: warningCode,
            message:
              "One of the four current Main Hub racial-isotope sell prices is unavailable. The four-isotope average and Coalition Hub transport cost remain unavailable.",
            severity: .blocking,
            source: quote.source
          )
        )
        continue
      }
      prices.append(
        JumpFuelPriceEntry(
          isotope: isotope,
          unitPrice: unitPrice,
          capturedAt: quote.capturedAt,
          source: quote.source
        )
      )
    }
    guard prices.count == JumpFuelIsotope.allCases.count else {
      return (nil, nil, warnings)
    }
    return (
      prices,
      prices.reduce(0) { $0 + $1.unitPrice } / Double(prices.count),
      warnings
    )
  }
}

public enum JumpFreighterLogisticsCalculator {
  public static func calculate(
    configuration: JumpFreighterLogisticsConfiguration,
    route: JumpRouteSnapshot,
    cargo: [LogisticsCargoItem],
    mainHubMarket: PreparedMarketOrderBook
  ) -> (
    breakdown: JumpFreighterCostBreakdown?,
    status: LogisticsRouteStatus,
    warnings: [DomainWarning]
  ) {
    guard configuration.isEnabled else { return (nil, .unavailable, []) }
    guard route.request.hull == configuration.hull else {
      return unavailable(
        "The retained jump route was calculated for a different Jump Freighter hull.")
    }
    guard let capacity = configuration.effectiveUsableCargoCapacityM3 else {
      return unavailable("The usable Jump Freighter cargo capacity is missing or invalid.")
    }
    let allocation = allocate(cargo: cargo, capacity: capacity)
    guard !allocation.warnings.contains(where: { $0.severity == .blocking }) else {
      return (nil, .unavailable, allocation.warnings)
    }
    if allocation.warnings.contains(where: {
      $0.code == "jump-freighter.single-item-volume-exceeded"
    }) {
      return (nil, .manualTransferRequired, allocation.warnings)
    }
    guard !allocation.flights.isEmpty else {
      return (nil, .notRequired, allocation.warnings)
    }

    let priceBasis = JumpFuelPriceBasis.quote(
      mainHubMarket: mainHubMarket,
      warningCode: "jump-freighter.isotope-price-unavailable"
    )
    let warnings = allocation.warnings + priceBasis.warnings
    guard let prices = priceBasis.prices, let average = priceBasis.average else {
      return (nil, .unavailable, warnings)
    }
    let (totalFuel, overflow) = route.isotopeQuantityPerFlight
      .multipliedReportingOverflow(by: Int64(allocation.flights.count))
    guard !overflow, totalFuel >= 0 else {
      return unavailable("The Jump Freighter fuel quantity exceeded safe numeric limits.")
    }
    let totalCost = Double(totalFuel) * average
    guard totalCost.isFinite, totalCost >= 0 else {
      return unavailable("The Jump Freighter fuel cost exceeded safe numeric limits.")
    }
    return (
      JumpFreighterCostBreakdown(
        ruleVersion: JumpFreighterLogisticsConfiguration.ruleVersion,
        pricePolicy: JumpFreighterLogisticsConfiguration.pricePolicy,
        hull: configuration.hull,
        pilot: route.request.pilot,
        route: route,
        isotopePrices: prices,
        averageIsotopeUnitPrice: average,
        usableCargoCapacityM3: capacity,
        flights: allocation.flights,
        isotopeQuantityPerFlight: route.isotopeQuantityPerFlight,
        totalIsotopeQuantity: totalFuel,
        totalCost: totalCost
      ),
      .calculated,
      warnings
    )
  }

  private static func unavailable(_ message: String) -> (
    breakdown: JumpFreighterCostBreakdown?,
    status: LogisticsRouteStatus,
    warnings: [DomainWarning]
  ) {
    (
      nil,
      .unavailable,
      [
        DomainWarning(
          code: "jump-freighter.unavailable",
          message: message,
          severity: .blocking
        )
      ]
    )
  }

  private static func allocate(
    cargo: [LogisticsCargoItem],
    capacity: Double
  ) -> (flights: [JumpFreighterFlight], warnings: [DomainWarning]) {
    struct Accepted {
      let typeID: Int64
      let name: String?
      let quantity: Int64
      let unitVolume: Double
    }
    struct DraftLine {
      let typeID: Int64
      var name: String?
      var quantity: Int64
      var volume: Double
    }
    struct DraftFlight {
      var volume: Double
      var cargo: [Int64: DraftLine]
    }
    var accepted: [Accepted] = []
    var warnings: [DomainWarning] = []
    for item in cargo where item.quantity > 0 {
      guard let unitVolume = item.packagedVolumePerUnit,
        unitVolume.isFinite,
        unitVolume > 0
      else {
        warnings.append(
          DomainWarning(
            code: "jump-freighter.missing-packaged-volume",
            message:
              "A packaged SDE volume required for Jump Freighter transport is unavailable.",
            severity: .blocking
          )
        )
        continue
      }
      guard unitVolume <= capacity else {
        warnings.append(
          DomainWarning(
            code: "jump-freighter.single-item-volume-exceeded",
            message:
              "At least one complete packaged product cannot fit into the configured \(capacity.formatted()) m³ usable Jump Freighter capacity.",
            severity: .warning
          )
        )
        continue
      }
      accepted.append(
        Accepted(
          typeID: item.typeID,
          name: item.name,
          quantity: item.quantity,
          unitVolume: unitVolume
        )
      )
    }
    guard !warnings.contains(where: { $0.severity == .blocking }) else {
      return ([], warnings)
    }
    accepted.sort {
      if $0.unitVolume != $1.unitVolume { return $0.unitVolume > $1.unitVolume }
      return $0.typeID < $1.typeID
    }
    var flights: [DraftFlight] = []
    let tolerance = max(1, capacity) * 1e-12
    for item in accepted {
      var remaining = item.quantity
      while remaining > 0 {
        var selected: Int?
        var quantity: Int64 = 0
        for index in flights.indices {
          let available = capacity - flights[index].volume
          let fit = Int64(
            min(Double(remaining), floor(max(0, available + tolerance) / item.unitVolume))
          )
          if fit > 0 {
            selected = index
            quantity = fit
            break
          }
        }
        if selected == nil {
          guard flights.count < 100_000 else {
            warnings.append(
              DomainWarning(
                code: "jump-freighter.flight-count-limit",
                message: "The route would require more than 100,000 Jump Freighter flights.",
                severity: .blocking
              )
            )
            return ([], warnings)
          }
          flights.append(DraftFlight(volume: 0, cargo: [:]))
          selected = flights.index(before: flights.endIndex)
          quantity = min(
            remaining,
            max(1, Int64(floor((capacity + tolerance) / item.unitVolume)))
          )
        }
        guard let selected else { break }
        let volume = item.unitVolume * Double(quantity)
        flights[selected].volume += volume
        var line =
          flights[selected].cargo[item.typeID]
          ?? DraftLine(
            typeID: item.typeID,
            name: item.name,
            quantity: 0,
            volume: 0
          )
        line.name = line.name ?? item.name
        line.quantity += quantity
        line.volume += volume
        flights[selected].cargo[item.typeID] = line
        remaining -= quantity
      }
    }
    let count = flights.count
    return (
      flights.enumerated().map { offset, flight in
        JumpFreighterFlight(
          number: offset + 1,
          count: count,
          cargoVolumeM3: flight.volume,
          cargo: flight.cargo.values.sorted {
            if $0.name != $1.name { return ($0.name ?? "") < ($1.name ?? "") }
            return $0.typeID < $1.typeID
          }.map {
            JumpFreighterCargoLine(
              typeID: $0.typeID,
              name: $0.name,
              quantity: $0.quantity,
              volumeM3: $0.volume
            )
          }
        )
      },
      warnings
    )
  }
}

public enum CapitalSelfJumpCalculator {
  public static func calculate(
    products: [(product: CapitalSelfJumpProduct, quantity: Int64)],
    routes: [Int64: Sourced<CapitalJumpRouteSnapshot>],
    routeWarnings: [DomainWarning],
    mainHubMarket: PreparedMarketOrderBook
  ) -> (
    breakdown: CapitalSelfJumpCostBreakdown?,
    status: LogisticsRouteStatus,
    warnings: [DomainWarning]
  ) {
    let products = products.filter { $0.quantity > 0 }
    guard !products.isEmpty else { return (nil, .notRequired, []) }

    var warnings = routeWarnings
    var resolved: [(CapitalSelfJumpProduct, Int64, CapitalJumpRouteSnapshot)] = []
    for entry in products.sorted(by: { $0.product.typeID < $1.product.typeID }) {
      guard let sourced = routes[entry.product.typeID],
        sourced.state == .fresh,
        let route = sourced.value,
        route.request.capitalTypeID == entry.product.typeID
      else {
        let warningCode =
          "capital-self-jump.route-unavailable.\(entry.product.typeID)"
        if !warnings.contains(where: { $0.code == warningCode }) {
          warnings.append(
            DomainWarning(
              code: warningCode,
              message:
                "A retained DOTLAN self-jump route for a produced capital is unavailable. The hull is not treated as Jump Freighter cargo or as a free transfer.",
              severity: .blocking,
              source: routes[entry.product.typeID]?.source
            )
          )
        }
        continue
      }
      resolved.append((entry.product, entry.quantity, route))
    }
    guard resolved.count == products.count else {
      return (nil, .unavailable, warnings)
    }
    let priceBasis = JumpFuelPriceBasis.quote(
      mainHubMarket: mainHubMarket,
      warningCode: "capital-self-jump.isotope-price-unavailable"
    )
    warnings.append(contentsOf: priceBasis.warnings)
    guard let prices = priceBasis.prices, let average = priceBasis.average else {
      return (nil, .unavailable, warnings)
    }

    var lines: [CapitalSelfJumpLine] = []
    var totalFuel: Int64 = 0
    var totalCost = 0.0
    for (product, quantity, route) in resolved {
      let (fuel, overflow) = route.isotopeQuantityPerHull
        .multipliedReportingOverflow(by: quantity)
      guard !overflow, fuel > 0 else {
        return unavailable(
          "A produced capital self-jump fuel quantity exceeded safe numeric limits.",
          warnings: warnings
        )
      }
      let (newFuelTotal, fuelOverflow) = totalFuel.addingReportingOverflow(fuel)
      let cost = Double(fuel) * average
      guard !fuelOverflow, cost.isFinite, cost >= 0,
        (totalCost + cost).isFinite
      else {
        return unavailable(
          "The combined capital self-jump cost exceeded safe numeric limits.",
          warnings: warnings
        )
      }
      totalFuel = newFuelTotal
      totalCost += cost
      lines.append(
        CapitalSelfJumpLine(
          product: product,
          quantity: quantity,
          route: route,
          isotopeQuantityPerHull: route.isotopeQuantityPerHull,
          totalIsotopeQuantity: fuel,
          totalCost: cost
        )
      )
    }
    return (
      CapitalSelfJumpCostBreakdown(
        ruleVersion: CapitalSelfJumpCostBreakdown.ruleVersion,
        pricePolicy: JumpFreighterLogisticsConfiguration.pricePolicy,
        isotopePrices: prices,
        averageIsotopeUnitPrice: average,
        jumps: lines,
        totalIsotopeQuantity: totalFuel,
        totalCost: totalCost
      ),
      .calculated,
      warnings
    )
  }

  private static func unavailable(
    _ message: String,
    warnings: [DomainWarning]
  ) -> (
    breakdown: CapitalSelfJumpCostBreakdown?,
    status: LogisticsRouteStatus,
    warnings: [DomainWarning]
  ) {
    var warnings = warnings
    warnings.append(
      DomainWarning(
        code: "capital-self-jump.unavailable",
        message: message,
        severity: .blocking
      )
    )
    return (nil, .unavailable, warnings)
  }
}
