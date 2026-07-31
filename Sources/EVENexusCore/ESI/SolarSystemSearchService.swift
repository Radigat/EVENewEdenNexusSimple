import Foundation

public struct SolarSystemOption: Identifiable, Equatable, Sendable {
  public let id: Int64
  public let name: String
  public let source: SourceIdentity

  public init(id: Int64, name: String, source: SourceIdentity) {
    self.id = id
    self.name = name
    self.source = source
  }
}

public struct SolarSystemDetails: Identifiable, Codable, Equatable, Sendable {
  public let id: Int64
  public let name: String
  public let constellationID: Int64
  public let constellationName: String
  public let regionID: Int64
  public let regionName: String
  public let securityStatus: Double
  public let securityClass: String?
  public let stationIDs: [Int64]
  public let source: SourceIdentity

  public init(
    id: Int64,
    name: String,
    constellationID: Int64,
    constellationName: String,
    regionID: Int64,
    regionName: String,
    securityStatus: Double,
    securityClass: String?,
    stationIDs: [Int64],
    source: SourceIdentity
  ) {
    self.id = id
    self.name = name
    self.constellationID = constellationID
    self.constellationName = constellationName
    self.regionID = regionID
    self.regionName = regionName
    self.securityStatus = securityStatus
    self.securityClass = securityClass
    self.stationIDs = stationIDs
    self.source = source
  }
}

private struct ESIUniverseName: Decodable, Sendable {
  let category: String
  let id: Int64
  let name: String
}

private struct ESIUniverseSystemDetails: Decodable, Sendable {
  let constellationID: Int64
  let name: String
  let securityClass: String?
  let securityStatus: Double
  let stations: [Int64]?
  let systemID: Int64

  enum CodingKeys: String, CodingKey {
    case constellationID = "constellation_id"
    case name
    case securityClass = "security_class"
    case securityStatus = "security_status"
    case stations
    case systemID = "system_id"
  }
}

private struct ESIUniverseConstellationDetails: Decodable, Sendable {
  let constellationID: Int64
  let name: String
  let regionID: Int64

  enum CodingKeys: String, CodingKey {
    case constellationID = "constellation_id"
    case name
    case regionID = "region_id"
  }
}

private struct ESIUniverseRegionDetails: Decodable, Sendable {
  let name: String
  let regionID: Int64

  enum CodingKeys: String, CodingKey {
    case name
    case regionID = "region_id"
  }
}

public actor SolarSystemSearchService {
  public static let maximumConcurrentNameRequests = 4

  private let esi: ESIClient
  private var cachedSystems: [SolarSystemOption]?
  private var systemIndexTask: Task<[SolarSystemOption], Error>?
  private var cachedDetails: [Int64: SolarSystemDetails] = [:]

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func search(query: String) async throws -> [SolarSystemOption] {
    let acceptedQuery = query.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard acceptedQuery.count >= 3 else { return [] }
    let systems = try await allSystems()
    return systems.filter {
      $0.name.localizedCaseInsensitiveContains(acceptedQuery)
    }
  }

  public func details(systemID: Int64) async throws -> SolarSystemDetails {
    if let cached = cachedDetails[systemID] { return cached }
    let system = try await esi.get(
      ESIUniverseSystemDetails.self,
      endpoint: ESIEndpoint(path: "/universe/systems/\(systemID)")
    )
    let constellation = try await esi.get(
      ESIUniverseConstellationDetails.self,
      endpoint: ESIEndpoint(
        path:
          "/universe/constellations/\(system.value.constellationID)"
      )
    )
    let region = try await esi.get(
      ESIUniverseRegionDetails.self,
      endpoint: ESIEndpoint(
        path: "/universe/regions/\(constellation.value.regionID)"
      )
    )
    let details = SolarSystemDetails(
      id: system.value.systemID,
      name: system.value.name,
      constellationID: constellation.value.constellationID,
      constellationName: constellation.value.name,
      regionID: region.value.regionID,
      regionName: region.value.name,
      securityStatus: system.value.securityStatus,
      securityClass: system.value.securityClass,
      stationIDs: system.value.stations ?? [],
      source: system.source
    )
    cachedDetails[systemID] = details
    return details
  }

  private func allSystems() async throws -> [SolarSystemOption] {
    if let cachedSystems { return cachedSystems }
    if let systemIndexTask {
      return try await systemIndexTask.value
    }
    let esi = self.esi
    let task = Task {
      try await Self.buildSystemIndex(esi: esi)
    }
    systemIndexTask = task
    do {
      let options = try await task.value
      cachedSystems = options
      systemIndexTask = nil
      return options
    } catch {
      systemIndexTask = nil
      throw error
    }
  }

  private static func buildSystemIndex(
    esi: ESIClient
  ) async throws -> [SolarSystemOption] {
    let systemIDs = try await esi.get(
      [Int64].self,
      endpoint: ESIEndpoint(path: "/universe/systems")
    )
    let chunks = stride(from: 0, to: systemIDs.value.count, by: 1_000).map {
      start in
      Array(
        systemIDs.value[
          start..<min(start + 1_000, systemIDs.value.count)
        ]
      )
    }
    var namesByChunk = [[ESIUniverseName]?](
      repeating: nil,
      count: chunks.count
    )
    var source = systemIDs.source
    var nextChunk = 0
    try await withThrowingTaskGroup(
      of: (Int, [ESIUniverseName], SourceIdentity).self
    ) { group in
      func addNextChunk() {
        guard nextChunk < chunks.count else { return }
        let index = nextChunk
        let ids = chunks[index]
        nextChunk += 1
        group.addTask {
          let response = try await esi.post(
            [ESIUniverseName].self,
            endpoint: ESIEndpoint(path: "/universe/names"),
            body: ids
          )
          return (index, response.value, response.source)
        }
      }

      for _ in 0..<min(maximumConcurrentNameRequests, chunks.count) {
        addNextChunk()
      }
      while let (index, names, chunkSource) = try await group.next() {
        namesByChunk[index] = names
        source = chunkSource
        addNextChunk()
      }
    }
    let names = namesByChunk.compactMap { $0 }.flatMap { $0 }
    let acceptedIDs = Set(systemIDs.value)
    return
      names
      .filter {
        $0.category == "solar_system" && acceptedIDs.contains($0.id)
      }
      .map {
        SolarSystemOption(
          id: $0.id,
          name: $0.name,
          source: source
        )
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name)
          == .orderedAscending
      }
  }
}
