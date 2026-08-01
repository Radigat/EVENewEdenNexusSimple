import Foundation

public enum MarketBrowserRouteState: String, Codable, Sendable {
  case reachable
  case unreachable
  case notChecked
}

public struct MarketBrowserOrder: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let typeID: Int64
  public let regionID: Int64
  public let regionName: String
  public let locationID: Int64
  public let locationName: String?
  public let systemID: Int64
  public let systemName: String?
  public let side: MarketOrderSide
  public let price: Double
  public let volumeRemaining: Int64
  public let volumeTotal: Int64
  public let minimumVolume: Int64
  public let range: String
  public let issuedAt: Date
  public let expiresAt: Date
  public let esiLastModifiedAt: Date?
  public let observedAt: Date
  public let jumps: Int?
  public let routeState: MarketBrowserRouteState

  public var isPlayerStructure: Bool {
    locationID >= 1_000_000_000_000
  }

  public init(
    id: Int64,
    typeID: Int64,
    regionID: Int64,
    regionName: String,
    locationID: Int64,
    locationName: String?,
    systemID: Int64,
    systemName: String?,
    side: MarketOrderSide,
    price: Double,
    volumeRemaining: Int64,
    volumeTotal: Int64,
    minimumVolume: Int64,
    range: String,
    issuedAt: Date,
    expiresAt: Date,
    esiLastModifiedAt: Date?,
    observedAt: Date,
    jumps: Int?,
    routeState: MarketBrowserRouteState
  ) {
    self.id = id
    self.typeID = typeID
    self.regionID = regionID
    self.regionName = regionName
    self.locationID = locationID
    self.locationName = locationName
    self.systemID = systemID
    self.systemName = systemName
    self.side = side
    self.price = price
    self.volumeRemaining = volumeRemaining
    self.volumeTotal = volumeTotal
    self.minimumVolume = minimumVolume
    self.range = range
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.esiLastModifiedAt = esiLastModifiedAt
    self.observedAt = observedAt
    self.jumps = jumps
    self.routeState = routeState
  }
}

public struct MarketBrowserRegionFailure: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: Int64 { regionID }
  public let regionID: Int64
  public let regionName: String
  public let diagnostic: String

  public init(regionID: Int64, regionName: String, diagnostic: String) {
    self.regionID = regionID
    self.regionName = regionName
    self.diagnostic = diagnostic
  }
}

public struct MarketBrowserSummary: Codable, Equatable, Sendable {
  public let bestSellPrice: Double?
  public let bestBuyPrice: Double?
  public let weightedAverageSellPrice: Double?
  public let activeSellVolume: Int64
  public let activeBuyVolume: Int64
  public let sellOrderCount: Int
  public let buyOrderCount: Int
  public let representedRegionCount: Int

  public var spread: Double? {
    guard let bestSellPrice, let bestBuyPrice else { return nil }
    return bestSellPrice - bestBuyPrice
  }

  public static func calculate(
    orders: [MarketBrowserOrder]
  ) -> MarketBrowserSummary {
    let valid = orders.filter {
      $0.price.isFinite && $0.price > 0 && $0.volumeRemaining > 0
    }
    let sells = valid.filter { $0.side == .sell }
    let buys = valid.filter { $0.side == .buy }
    let sellVolume = sells.reduce(Int64(0)) {
      $0.addingReportingOverflow($1.volumeRemaining).overflow
        ? Int64.max : $0 + $1.volumeRemaining
    }
    let buyVolume = buys.reduce(Int64(0)) {
      $0.addingReportingOverflow($1.volumeRemaining).overflow
        ? Int64.max : $0 + $1.volumeRemaining
    }
    let weightedTotal = sells.reduce(0.0) {
      $0 + ($1.price * Double($1.volumeRemaining))
    }
    return MarketBrowserSummary(
      bestSellPrice: sells.map(\.price).min(),
      bestBuyPrice: buys.map(\.price).max(),
      weightedAverageSellPrice:
        sellVolume > 0 && weightedTotal.isFinite
        ? weightedTotal / Double(sellVolume) : nil,
      activeSellVolume: sellVolume,
      activeBuyVolume: buyVolume,
      sellOrderCount: sells.count,
      buyOrderCount: buys.count,
      representedRegionCount: Set(valid.map(\.regionID)).count
    )
  }
}

public struct MarketBrowserSnapshot: Codable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let itemName: String
  public let originSystemID: Int64?
  public let originSystemName: String?
  public let capturedAt: Date
  public let regionCount: Int
  public let loadedRegionCount: Int
  public let orders: [MarketBrowserOrder]
  public let regionFailures: [MarketBrowserRegionFailure]
  public let summary: MarketBrowserSummary
  public let source: SourceIdentity

  public init(
    id: UUID = UUID(),
    typeID: Int64,
    itemName: String,
    originSystemID: Int64?,
    originSystemName: String?,
    capturedAt: Date,
    regionCount: Int,
    loadedRegionCount: Int,
    orders: [MarketBrowserOrder],
    regionFailures: [MarketBrowserRegionFailure],
    source: SourceIdentity
  ) {
    self.id = id
    self.typeID = typeID
    self.itemName = itemName
    self.originSystemID = originSystemID
    self.originSystemName = originSystemName
    self.capturedAt = capturedAt
    self.regionCount = regionCount
    self.loadedRegionCount = loadedRegionCount
    self.orders = orders
    self.regionFailures = regionFailures
    summary = MarketBrowserSummary.calculate(orders: orders)
    self.source = source
  }
}

public struct MarketBrowserFilter: Equatable, Sendable {
  public var regionQuery = ""
  public var locationQuery = ""
  public var minimumPrice: Double?
  public var maximumPrice: Double?
  public var minimumQuantity: Int64?
  public var maximumJumps: Int?
  public var includesNPCStations = true
  public var includesPlayerStructures = true
  public var marketHubsOnly = false
  public var includesUncheckedRoutes = true

  public init() {}

  public func accepts(_ order: MarketBrowserOrder) -> Bool {
    if !regionQuery.isEmpty,
      !order.regionName.localizedCaseInsensitiveContains(regionQuery)
    {
      return false
    }
    if !locationQuery.isEmpty {
      let location = order.locationName ?? String(order.locationID)
      let system = order.systemName ?? String(order.systemID)
      if !location.localizedCaseInsensitiveContains(locationQuery)
        && !system.localizedCaseInsensitiveContains(locationQuery)
      {
        return false
      }
    }
    if let minimumPrice, order.price < minimumPrice { return false }
    if let maximumPrice, order.price > maximumPrice { return false }
    if let minimumQuantity, order.volumeRemaining < minimumQuantity {
      return false
    }
    if order.isPlayerStructure {
      if !includesPlayerStructures { return false }
    } else if !includesNPCStations {
      return false
    }
    if marketHubsOnly,
      !MarketTradeHub.allCases.contains(where: {
        $0.stationID == order.locationID
      })
    {
      return false
    }
    if let maximumJumps {
      if let jumps = order.jumps {
        if jumps > maximumJumps { return false }
      } else if !includesUncheckedRoutes {
        return false
      }
    }
    return true
  }
}
