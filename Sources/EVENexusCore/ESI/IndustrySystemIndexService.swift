import Foundation

public struct IndustrySystemIndexService: Sendable {
  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func synchronize() async throws
    -> Sourced<[IndustrySystemCostIndexSnapshot]>
  {
    let response = try await esi.get(
      [ESIIndustrySystemDTO].self,
      endpoint: ESIEndpoint(path: "/industry/systems")
    )
    let snapshots = response.value.map { system in
      IndustrySystemCostIndexSnapshot(
        solarSystemID: system.solarSystemID,
        indices: system.costIndices.map { value in
          return IndustryActivityCostIndex(
            activityRawValue: value.activity,
            value: value.costIndex
          )
        }
      )
    }
    return Sourced(
      state: .fresh,
      value: snapshots,
      source: response.source
    )
  }
}
