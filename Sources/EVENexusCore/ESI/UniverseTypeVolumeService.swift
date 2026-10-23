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

/// Resolves repackaged cargo volumes. A real `packagedVolume` of the active
/// SDE is used first (owner decision 2026-10-23); only types without one are
/// requested from the public ESI universe-type endpoint. The assembled
/// `volume` must never be substituted for transport.
public actor UniverseTypeVolumeService {
  /// Returns only actually imported SDE `packagedVolume` values.
  public typealias StaticPackagedVolumes =
    @Sendable (Set<Int64>) async throws -> Sourced<[Int64: Double]>

  private static let esiProvider = "ESI universe types"

  private struct CachedVolume: Sendable {
    let volume: Double
    let source: SourceIdentity
    var isStatic = false
  }

  private enum FetchResult: Sendable {
    case loaded(typeID: Int64, volume: Double, source: SourceIdentity)
    case unavailable(typeID: Int64)
  }

  private let esi: ESIClient
  private let maximumConcurrentRequests: Int
  private let staticPackagedVolumes: StaticPackagedVolumes?
  private var cachedVolumes: [Int64: CachedVolume] = [:]

  public init(
    esi: ESIClient,
    maximumConcurrentRequests: Int = 4,
    staticPackagedVolumes: StaticPackagedVolumes? = nil
  ) {
    self.esi = esi
    self.maximumConcurrentRequests = min(
      8,
      max(1, maximumConcurrentRequests)
    )
    self.staticPackagedVolumes = staticPackagedVolumes
  }

  public func volumes(for typeIDs: Set<Int64>) async throws
    -> Sourced<[Int64: Double]>
  {
    let acceptedTypeIDs = typeIDs.filter { $0 > 0 }
    try await loadStaticVolumes(
      for: acceptedTypeIDs.filter { cachedVolumes[$0] == nil }
    )
    let missingTypeIDs = acceptedTypeIDs.filter {
      cachedVolumes[$0] == nil
    }.sorted()
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
    let used = acceptedTypeIDs.compactMap { cachedVolumes[$0] }
    let usedSources = used.map(\.source)
    let staticSources = used.filter(\.isStatic).map(\.source)
    var diagnostics: [String] = []
    if !staticSources.isEmpty {
      diagnostics.append("sde.packaged-volume:\(staticSources.count)")
    }
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
    return Sourced(
      state: state,
      value: values,
      source: Self.snapshotSource(
        used: usedSources,
        staticSources: staticSources
      ),
      diagnostics: diagnostics
    )
  }

  private func loadStaticVolumes(for typeIDs: Set<Int64>) async throws {
    guard let staticPackagedVolumes, !typeIDs.isEmpty else { return }
    let snapshot: Sourced<[Int64: Double]>
    do {
      snapshot = try await staticPackagedVolumes(typeIDs)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Without a readable SDE every type keeps the ESI path.
      return
    }
    for (typeID, volume) in snapshot.value ?? [:]
    where typeIDs.contains(typeID) && volume.isFinite && volume >= 0 {
      cachedVolumes[typeID] = CachedVolume(
        volume: volume,
        source: snapshot.source,
        isStatic: true
      )
    }
  }

  private static func snapshotSource(
    used: [SourceIdentity],
    staticSources: [SourceIdentity]
  ) -> SourceIdentity {
    let capturedAt = used.map(\.capturedAt).max() ?? .now
    guard let staticSource = staticSources.first else {
      return SourceIdentity(
        provider: esiProvider,
        version: EVEConstants.esiCompatibilityDate,
        capturedAt: capturedAt
      )
    }
    if staticSources.count == used.count {
      return SourceIdentity(
        provider: staticSource.provider,
        version: staticSource.version,
        capturedAt: capturedAt
      )
    }
    return SourceIdentity(
      provider: "\(staticSource.provider) + \(esiProvider)",
      version: "\(staticSource.version) + \(EVEConstants.esiCompatibilityDate)",
      capturedAt: capturedAt
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
