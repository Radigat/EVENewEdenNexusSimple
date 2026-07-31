import Foundation

public struct JitaMarketService: Sendable {
  private let esi: ESIClient

  public init(esi: ESIClient) {
    self.esi = esi
  }

  public func orderSnapshot(typeIDs: Set<Int64>) async throws
    -> MarketOrderSnapshot
  {
    var ordersByType: [Int64: [MarketOrder]] = [:]
    var source = SourceIdentity(
      provider: "ESI",
      version: EVEConstants.esiCompatibilityDate
    )
    for typeID in typeIDs.sorted() {
      let response = try await esi.getAllPages(
        [ESIMarketOrderDTO].self,
        endpoint: ESIEndpoint(
          path: "/markets/\(EVEConstants.theForgeRegionID)/orders/",
          query: [
            URLQueryItem(name: "order_type", value: "all"),
            URLQueryItem(name: "type_id", value: String(typeID)),
          ]
        )
      )
      source = response.source
      ordersByType[typeID] = response.value.map {
        MarketOrder(
          id: $0.orderID,
          typeID: $0.typeID,
          locationID: $0.locationID,
          systemID: $0.systemID,
          side: $0.isBuyOrder ? .buy : .sell,
          price: $0.price,
          volumeRemaining: $0.volumeRemain,
          minimumVolume: $0.minVolume,
          issued: $0.issued
        )
      }
    }
    return MarketOrderSnapshot(
      id: UUID(),
      regionID: EVEConstants.theForgeRegionID,
      locationID: EVEConstants.jitaIV4StationID,
      capturedAt: .now,
      state: .fresh,
      ordersByType: ordersByType,
      source: source
    )
  }

  public func adjustedPrices() async throws -> [Int64: AdjustedPrice] {
    let response = try await esi.get(
      [ESIAdjustedPriceDTO].self,
      endpoint: ESIEndpoint(path: "/markets/prices/")
    )
    return Dictionary(
      uniqueKeysWithValues: response.value.map {
        (
          $0.typeID,
          AdjustedPrice(
            typeID: $0.typeID,
            adjustedPrice: $0.adjustedPrice,
            averagePrice: $0.averagePrice
          )
        )
      })
  }

  public func industrySystems() async throws -> [IndustrySystemIndex] {
    let response = try await esi.get(
      [ESIIndustrySystemDTO].self,
      endpoint: ESIEndpoint(path: "/industry/systems/")
    )
    return response.value.flatMap { system in
      system.costIndices.compactMap { index in
        guard
          let activity =
            BlueprintActivityDefinition.Kind(
              rawValue: index.activity
            )
        else { return nil }
        return IndustrySystemIndex(
          solarSystemID: system.solarSystemID,
          activity: activity,
          costIndex: index.costIndex
        )
      }
    }
  }
}
