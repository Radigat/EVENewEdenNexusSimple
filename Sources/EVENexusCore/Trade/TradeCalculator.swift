import Foundation

/// EVE order prices carry at most four significant digits and at least
/// 0.01 ISK resolution. An own order is placed one valid price step better
/// than the current best order (owner decision 22.10.2026).
public enum MarketPriceTick {
  public static let significantDigits = 4

  /// Highest valid order price strictly below `price`; nil when none exists.
  public static func nextBelow(_ price: Double) -> Double? {
    guard let cents = cents(price), cents > 1 else { return nil }
    let candidate = cents - 1
    let step = stepInCents(candidate)
    return Double(candidate / step * step) / 100
  }

  /// Lowest valid order price strictly above `price`; nil when out of range.
  public static func nextAbove(_ price: Double) -> Double? {
    guard let cents = cents(price), cents < Int64.max / 10 else { return nil }
    let candidate = cents + 1
    let step = stepInCents(candidate)
    let rounded = (candidate + step - 1) / step * step
    return Double(rounded) / 100
  }

  private static func cents(_ price: Double) -> Int64? {
    guard price.isFinite, price > 0 else { return nil }
    let value = (price * 100).rounded()
    guard value >= 1, value < Double(Int64.max / 10) else { return nil }
    return Int64(value)
  }

  /// Step of the price magnitude of `cents`: 1 cent up to four digits,
  /// otherwise 10^(digits − 4) cents.
  private static func stepInCents(_ cents: Int64) -> Int64 {
    var digits = 0
    var remaining = cents
    while remaining > 0 {
      digits += 1
      remaining /= 10
    }
    var step: Int64 = 1
    for _ in 0..<max(0, digits - significantDigits) {
      step *= 10
    }
    return step
  }
}

/// Pure, deterministic trade valuation (HANDEL_PLAN.md, section C).
public enum TradeCalculator {
  public static let ruleVersion = "trade-2026-10-22"
  /// Relist and order-modification fees are deliberately not part of any
  /// result (owner decision 22.10.2026); the UI states this.
  public static let includesOrderModificationFees = false

  public static func rows(
    items: [TradeItemInput],
    mode: TradeMode,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    sourceFees: TradeHubFees,
    targetFees: TradeHubFees,
    transport: TradeTransportBasis
  ) -> [TradeRow] {
    items.map {
      row(
        item: $0,
        mode: mode,
        sourceSide: sourceSide,
        targetSide: targetSide,
        sourceFees: sourceFees,
        targetFees: targetFees,
        transport: transport
      )
    }
  }

  public static func row(
    item: TradeItemInput,
    mode: TradeMode,
    sourceSide: TradeQuoteSide,
    targetSide: TradeQuoteSide,
    sourceFees: TradeHubFees,
    targetFees: TradeHubFees,
    transport: TradeTransportBasis
  ) -> TradeRow {
    var issues: [TradeRowIssue] = []
    let sourceSell = validPrice(item.source?.bestSellPrice)
    let sourceBuy = validPrice(item.source?.bestBuyPrice)
    let targetSell = validPrice(item.target?.bestSellPrice)
    let targetBuy = validPrice(item.target?.bestBuyPrice)

    let sourcePrice = sourceSide == .minSell ? sourceSell : sourceBuy
    let targetPrice = targetSide == .minSell ? targetSell : targetBuy
    if sourcePrice == nil { issues.append(.missingSourcePrice) }
    if targetPrice == nil { issues.append(.missingTargetPrice) }
    let difference = sourcePrice.flatMap { source in
      targetPrice.flatMap { finite(($0 - source) / source) }
    }

    let purchaseCost: Double?
    switch sourceSide {
    case .minSell:
      purchaseCost = sourceSell
    case .maxBuy:
      let broker = validRate(sourceFees.brokerFeeRate)
      if sourceBuy != nil, broker == nil {
        issues.append(.missingSourceBrokerFee)
      }
      let bid = sourceBuy.flatMap(MarketPriceTick.nextAbove)
      if sourceBuy != nil, bid == nil { issues.append(.noValidPriceStep) }
      purchaseCost = bid.flatMap { bid in
        broker.flatMap { finite(bid * (1 + $0)) }
      }
    }

    let netSale: Double?
    let tax = validRate(targetFees.salesTaxRate)
    switch targetSide {
    case .minSell:
      let broker = validRate(targetFees.brokerFeeRate)
      let keep = tax.flatMap { tax in
        broker.flatMap { broker in
          tax + broker < 1 ? 1 - tax - broker : nil
        }
      }
      if targetSell != nil, keep == nil { issues.append(.missingTargetFees) }
      let ask = targetSell.flatMap(MarketPriceTick.nextBelow)
      if targetSell != nil, ask == nil { issues.append(.noValidPriceStep) }
      netSale = ask.flatMap { ask in keep.flatMap { finite(ask * $0) } }
    case .maxBuy:
      let keep = tax.flatMap { $0 < 1 ? 1 - $0 : nil }
      if targetBuy != nil, keep == nil { issues.append(.missingTargetFees) }
      netSale = targetBuy.flatMap { bid in keep.flatMap { finite(bid * $0) } }
    }

    let transportCost: Double?
    if mode.requiresTransport {
      let perUnit = transportPerUnit(
        packagedVolume: item.packagedVolume,
        collateral: purchaseCost,
        transport: transport
      )
      issues.append(contentsOf: perUnit.issues)
      transportCost = perUnit.cost
    } else {
      transportCost = 0
    }

    let profit = netSale.flatMap { net in
      purchaseCost.flatMap { cost in
        transportCost.flatMap { finite(net - cost - $0) }
      }
    }
    let margin = profit.flatMap { profit in
      netSale.flatMap { $0 > 0 ? finite(profit / $0) : nil }
    }
    let investment = purchaseCost.flatMap { cost in
      transportCost.map { cost + $0 }
    }
    let roi = profit.flatMap { profit in
      investment.flatMap { $0 > 0 ? finite(profit / $0) : nil }
    }
    let spread = targetSell.flatMap { sell in
      targetBuy.flatMap { finite((sell - $0) / $0) }
    }

    return TradeRow(
      typeID: item.typeID,
      name: item.name,
      packagedVolume: item.packagedVolume,
      sourcePrice: sourcePrice,
      targetPrice: targetPrice,
      sourceVolumeAtPrice: sourcePrice == nil
        ? nil
        : sourceSide == .minSell
          ? item.source?.bestSellVolume : item.source?.bestBuyVolume,
      targetVolumeAtPrice: targetPrice == nil
        ? nil
        : targetSide == .minSell
          ? item.target?.bestSellVolume : item.target?.bestBuyVolume,
      differenceFraction: difference,
      purchaseCost: purchaseCost,
      transportCost: transportCost,
      netSale: netSale,
      profit: profit,
      margin: margin,
      returnOnInvestment: roi,
      targetSpreadFraction: spread,
      issues: deduplicated(issues)
    )
  }

  /// Tile estimate per unit without a quantity: courier legs charge the
  /// higher of volume and collateral charge without contract rounding; Jump
  /// Freighter legs assume a full load.
  public static func transportPerUnit(
    packagedVolume: Double?,
    collateral: Double?,
    transport: TradeTransportBasis
  ) -> (cost: Double?, issues: [TradeRowIssue]) {
    guard !transport.legs.isEmpty else {
      return (nil, [.transportUnavailable])
    }
    var issues: [TradeRowIssue] = []
    var total: Double? = 0
    for leg in transport.legs {
      let legCost: Double?
      switch leg {
      case .unavailable:
        issues.append(.transportUnavailable)
        legCost = nil
      case .courier(let courier):
        guard validPositive(courier.iskPerCubicMeter) != nil,
          validRate(courier.collateralRate) != nil
        else {
          issues.append(.transportUnavailable)
          legCost = nil
          break
        }
        guard let volume = validVolume(packagedVolume) else {
          issues.append(.missingPackagedVolume)
          legCost = nil
          break
        }
        // A unit larger than one contract needs a manual transfer.
        guard volume <= courier.maximumContractVolumeM3 else {
          issues.append(.transportUnavailable)
          legCost = nil
          break
        }
        legCost = collateral.flatMap {
          finite(
            max(
              volume * courier.iskPerCubicMeter,
              $0 * courier.collateralRate
            )
          )
        }
      case .jumpFreighter(let freighter):
        guard let capacity = validPositive(freighter.usableCargoCapacityM3),
          let flight = validVolume(freighter.costPerFlight)
        else {
          issues.append(.transportUnavailable)
          legCost = nil
          break
        }
        guard let volume = validPositive(packagedVolume) else {
          issues.append(.missingPackagedVolume)
          legCost = nil
          break
        }
        guard volume <= capacity else {
          issues.append(.exceedsJumpFreighterCapacity)
          legCost = nil
          break
        }
        legCost = finite(flight / capacity * volume)
      }
      total = total.flatMap { sum in legCost.map { sum + $0 } }
    }
    return (total.flatMap(finite), deduplicated(issues))
  }

  /// Exact route cost for `quantity` units: courier legs use the shared
  /// contract calculator (per-contract maximum, 1M ISK rounding); Jump
  /// Freighter legs pay every started flight in full.
  public static func transportQuote(
    typeID: Int64,
    name: String?,
    quantity: Int64,
    packagedVolumePerUnit: Double?,
    unitCollateral: Double?,
    transport: TradeTransportBasis
  ) -> TradeTransportQuote {
    guard quantity > 0 else {
      return TradeTransportQuote(total: 0, perUnit: nil, issues: [], warnings: [])
    }
    guard !transport.legs.isEmpty else {
      return TradeTransportQuote(
        total: nil,
        perUnit: nil,
        issues: [.transportUnavailable],
        warnings: []
      )
    }
    var issues: [TradeRowIssue] = []
    var warnings: [DomainWarning] = []
    var total: Double? = 0
    for leg in transport.legs {
      let legCost: Double?
      switch leg {
      case .unavailable:
        issues.append(.transportUnavailable)
        legCost = nil
      case .courier(let courier):
        let collateral = unitCollateral.flatMap {
          finite($0 * Double(quantity))
        }
        let result = LogisticsCostCalculator.calculateLegs(
          kind: .inboundMaterials,
          origin: courier.origin,
          destination: courier.destination,
          cargo: [
            LogisticsCargoItem(
              typeID: typeID,
              quantity: quantity,
              collateral: collateral,
              packagedVolumePerUnit: packagedVolumePerUnit,
              name: name
            )
          ],
          iskPerCubicMeter: courier.iskPerCubicMeter,
          maximumContractVolumeM3: courier.maximumContractVolumeM3
        )
        warnings.append(contentsOf: result.warnings)
        if result.warnings.contains(where: {
          $0.code == "logistics.missing-packaged-volume"
        }) {
          issues.append(.missingPackagedVolume)
        }
        // An item larger than one contract is skipped by the calculator; it
        // must not turn into a free transport.
        if result.warnings.contains(where: {
          $0.severity == .blocking
            || $0.code == "logistics.single-item-volume-exceeded"
        }) {
          issues.append(.transportUnavailable)
          legCost = nil
        } else {
          legCost = finite(result.legs.reduce(0) { $0 + $1.roundedCharge })
        }
      case .jumpFreighter(let freighter):
        guard let capacity = validPositive(freighter.usableCargoCapacityM3),
          let flight = validVolume(freighter.costPerFlight)
        else {
          issues.append(.transportUnavailable)
          legCost = nil
          break
        }
        guard let volume = validPositive(packagedVolumePerUnit) else {
          issues.append(.missingPackagedVolume)
          legCost = nil
          break
        }
        guard volume <= capacity else {
          issues.append(.exceedsJumpFreighterCapacity)
          legCost = nil
          break
        }
        // Units are indivisible: a flight carries floor(capacity ÷ volume).
        let unitsPerFlight = max(1, Int64((capacity / volume).rounded(.down)))
        let flights = (quantity + unitsPerFlight - 1) / unitsPerFlight
        legCost = finite(Double(flights) * flight)
      }
      total = total.flatMap { sum in legCost.map { sum + $0 } }
    }
    let checkedTotal = total.flatMap(finite)
    return TradeTransportQuote(
      total: checkedTotal,
      perUnit: checkedTotal.flatMap { finite($0 / Double(quantity)) },
      issues: deduplicated(issues),
      warnings: warnings
    )
  }

  private static func validPrice(_ value: Double?) -> Double? {
    validPositive(value)
  }

  private static func validPositive(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  private static func validVolume(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func validRate(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0, value < 1 else { return nil }
    return value
  }

  private static func finite(_ value: Double) -> Double? {
    value.isFinite ? value : nil
  }

  private static func deduplicated(_ issues: [TradeRowIssue]) -> [TradeRowIssue] {
    var seen = Set<TradeRowIssue>()
    return issues.filter { seen.insert($0).inserted }
  }
}
