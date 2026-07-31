import Foundation

public struct UniverseNameRecord: Codable, Equatable, Sendable {
  public let category: String
  public let id: Int64
  public let name: String

  public init(category: String, id: Int64, name: String) {
    self.category = category
    self.id = id
    self.name = name
  }
}

public actor UniverseNameService {
  private let esi: ESIClient
  private var cachedNames: [Int64: String] = [:]

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func names(for ids: Set<Int64>) async -> Sourced<[Int64: String]> {
    let acceptedIDs = ids.filter { $0 > 0 }
    let missing = acceptedIDs.filter { cachedNames[$0] == nil }.sorted()
    var diagnostics: [String] = []
    var latestSource = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )

    for start in stride(from: 0, to: missing.count, by: 1_000) {
      let end = min(start + 1_000, missing.count)
      do {
        let response = try await esi.post(
          [UniverseNameRecord].self,
          endpoint: ESIEndpoint(path: "/universe/names"),
          body: Array(missing[start..<end])
        )
        latestSource = response.source
        for value in response.value {
          cachedNames[value.id] = value.name
        }
      } catch {
        diagnostics.append("esi.universe-names.unavailable")
      }
    }

    let values = Dictionary(
      uniqueKeysWithValues: acceptedIDs.compactMap { id in
        cachedNames[id].map { (id, $0) }
      }
    )
    let unresolvedCount = acceptedIDs.count - values.count
    if unresolvedCount > 0 {
      diagnostics.append("esi.universe-names.unresolved:\(unresolvedCount)")
    }
    return Sourced(
      state: diagnostics.isEmpty ? .fresh : .partial,
      value: values,
      source: latestSource,
      diagnostics: diagnostics
    )
  }
}
