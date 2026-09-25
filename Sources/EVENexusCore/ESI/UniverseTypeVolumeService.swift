import Foundation

public struct ESIUniverseTypeVolumeDTO: Decodable, Equatable, Sendable {
  public let typeID: Int64
  public let packagedVolume: Double
  public let volume: Double?

  public init(
    typeID: Int64,
    packagedVolume: Double,
    volume: Double? = nil
  ) {
    self.typeID = typeID
    self.packagedVolume = packagedVolume
    self.volume = volume
  }

  private enum CodingKeys: String, CodingKey {
    case typeID = "type_id"
    case packagedVolume = "packaged_volume"
    case volume
  }
}

/// Resolves the authoritative repackaged cargo volume exposed by the public
/// ESI universe-type endpoint. The current client-driven SDE may contain only
/// the assembled `volume`, which must never be substituted for transport.
public actor UniverseTypeVolumeService {
  private struct CachedVolume: Sendable {
    let volume: Double
    let source: SourceIdentity
  }

  private enum FetchResult: Sendable {
    case loaded(typeID: Int64, volume: Double, source: SourceIdentity)
    case unavailable(typeID: Int64)
  }

  private let esi: ESIClient
  private let maximumConcurrentRequests: Int
  private var cachedVolumes: [Int64: CachedVolume] = [:]

  public init(
    esi: ESIClient,
    maximumConcurrentRequests: Int = 4
  ) {
    self.esi = esi
    self.maximumConcurrentRequests = min(
      8,
      max(1, maximumConcurrentRequests)
    )
  }

  public func volumes(for typeIDs: Set<Int64>) async throws
    -> Sourced<[Int64: Double]>
  {
    let acceptedTypeIDs = typeIDs.filter { $0 > 0 }
    let missingTypeIDs = acceptedTypeIDs.filter {
      cachedVolumes[$0] == nil
    }.sorted()
    var latestSource =
      acceptedTypeIDs.compactMap {
        cachedVolumes[$0]?.source
      }.max(by: { $0.capturedAt < $1.capturedAt })
      ?? SourceIdentity(
        provider: "ESI universe types",
        version: EVEConstants.esiCompatibilityDate
      )
    var failedTypeIDs: [Int64] = []

    try await withThrowingTaskGroup(of: FetchResult.self) { group in
      var nextIndex = 0
      let initialCount = min(maximumConcurrentRequests, missingTypeIDs.count)
      for _ in 0..<initialCount {
        let typeID = missingTypeIDs[nextIndex]
        nextIndex += 1
        group.addTask { [esi] in
          try await Self.fetch(typeID: typeID, esi: esi)
        }
      }

      while let result = try await group.next() {
        switch result {
        case .loaded(let typeID, let volume, let source):
          cachedVolumes[typeID] = CachedVolume(
            volume: volume,
            source: source
          )
          if source.capturedAt > latestSource.capturedAt {
            latestSource = source
          }
        case .unavailable(let typeID):
          failedTypeIDs.append(typeID)
        }
        if nextIndex < missingTypeIDs.count {
          let typeID = missingTypeIDs[nextIndex]
          nextIndex += 1
          group.addTask { [esi] in
            try await Self.fetch(typeID: typeID, esi: esi)
          }
        }
      }
    }

    let values = Dictionary(
      uniqueKeysWithValues: acceptedTypeIDs.compactMap { typeID in
        cachedVolumes[typeID].map { (typeID, $0.volume) }
      }
    )
    let unresolvedCount = acceptedTypeIDs.count - values.count
    let state: DataFreshness
    if acceptedTypeIDs.isEmpty || unresolvedCount == 0 {
      state = .fresh
    } else if values.isEmpty {
      state = .unavailable
    } else {
      state = .partial
    }
    var diagnostics: [String] = []
    if !failedTypeIDs.isEmpty {
      diagnostics.append(
        "esi.universe-type-volume.failed:\(failedTypeIDs.count)"
      )
    }
    if unresolvedCount > 0 {
      diagnostics.append(
        "esi.universe-type-volume.unresolved:\(unresolvedCount)"
      )
    }
    let snapshotSource = SourceIdentity(
      provider: "ESI universe types",
      version: EVEConstants.esiCompatibilityDate,
      capturedAt: latestSource.capturedAt
    )
    return Sourced(
      state: state,
      value: values,
      source: snapshotSource,
      diagnostics: diagnostics
    )
  }

  private static func fetch(
    typeID: Int64,
    esi: ESIClient
  ) async throws -> FetchResult {
    do {
      let response = try await esi.get(
        ESIUniverseTypeVolumeDTO.self,
        endpoint: ESIEndpoint(path: "/universe/types/\(typeID)/")
      )
      let value = response.value
      guard value.typeID == typeID,
        value.packagedVolume.isFinite,
        value.packagedVolume >= 0
      else { return .unavailable(typeID: typeID) }
      return .loaded(
        typeID: typeID,
        volume: value.packagedVolume,
        source: response.source
      )
    } catch ESIError.cancelled {
      throw CancellationError()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return .unavailable(typeID: typeID)
    }
  }
}
