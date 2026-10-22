import Foundation

/// Self-calculated ISK value of one Loyalty Point per NPC corporation.
///
/// Every offer whose product and required items have an ESI average price
/// yields `(product value − ISK cost − required items) / LP`. The corporation
/// value is the median of its five best positive offers, so one illiquid
/// outlier cannot set the value alone. Offers without a complete price basis
/// are ignored; a corporation without any priced offer stays unavailable.
public enum LoyaltyPointValuation {
  public static let bestOfferSampleSize = 5

  public static func iskPerLP(
    offers: [LoyaltyStoreOffer],
    averagePrices: [Int64: Double],
    excludedTypeIDs: Set<Int64> = []
  ) -> [Int64: Double] {
    var ratesByCorporation: [Int64: [Double]] = [:]
    for offer in offers where !excludedTypeIDs.contains(offer.typeID) {
      guard let rate = rate(of: offer, averagePrices: averagePrices) else {
        continue
      }
      ratesByCorporation[offer.corporationID, default: []].append(rate)
    }
    return ratesByCorporation.compactMapValues { rates in
      let best = Array(rates.sorted(by: >).prefix(bestOfferSampleSize))
      guard !best.isEmpty else { return nil }
      return median(best)
    }
  }

  /// Market value of the required items of one offer; `nil` while any item
  /// has no ESI average price.
  public static func requiredItemsValue(
    of offer: LoyaltyStoreOffer,
    averagePrices: [Int64: Double]
  ) -> Double? {
    var total = 0.0
    for item in offer.requiredItems where item.quantity > 0 {
      guard let price = averagePrices[item.typeID], price.isFinite, price > 0
      else { return nil }
      total += price * Double(item.quantity)
    }
    return total.isFinite ? total : nil
  }

  static func rate(
    of offer: LoyaltyStoreOffer,
    averagePrices: [Int64: Double]
  ) -> Double? {
    guard offer.lpCost > 0, offer.quantity > 0,
      offer.iskCost.isFinite, offer.iskCost >= 0,
      let price = averagePrices[offer.typeID], price.isFinite, price > 0,
      let items = requiredItemsValue(of: offer, averagePrices: averagePrices)
    else { return nil }
    let value =
      (price * Double(offer.quantity) - offer.iskCost - items)
      / Double(offer.lpCost)
    return value.isFinite && value > 0 ? value : nil
  }

  private static func median(_ sortedDescending: [Double]) -> Double {
    let count = sortedDescending.count
    if count % 2 == 1 { return sortedDescending[count / 2] }
    return (sortedDescending[count / 2 - 1] + sortedDescending[count / 2]) / 2
  }
}

/// Loyalty Points of one character with one NPC corporation.
public struct CharacterLoyaltyPoints: Codable, Equatable, Sendable {
  public let characterID: Int64
  public let characterName: String
  public let corporationID: Int64
  public let points: Int64

  public init(
    characterID: Int64,
    characterName: String,
    corporationID: Int64,
    points: Int64
  ) {
    self.characterID = characterID
    self.characterName = characterName
    self.corporationID = corporationID
    self.points = points
  }
}

/// A Loyalty Store offer of a Blueprint, prepared for the opportunity cost.
public struct LoyaltyStoreBlueprintOffer: Equatable, Sendable {
  public let corporationID: Int64
  public let corporationName: String?
  public let blueprintTypeID: Int64
  public let lpCost: Int
  public let iskCost: Double
  /// BPCs handed out per purchase.
  public let quantity: Int
  public let requiredItemsValue: Double?
  /// Self-calculated LP value of this corporation; `nil` when unavailable.
  public let iskPerLP: Double?
  /// The character with the most LP at this corporation, `nil` while no LP
  /// data is known.
  public let bestCharacterName: String?
  public let availableLP: Int64?
  /// Wallet of `bestCharacterName`; `nil` while unknown.
  public let availableISK: Double?

  public init(
    corporationID: Int64,
    corporationName: String?,
    blueprintTypeID: Int64,
    lpCost: Int,
    iskCost: Double,
    quantity: Int,
    requiredItemsValue: Double?,
    iskPerLP: Double?,
    bestCharacterName: String?,
    availableLP: Int64?,
    availableISK: Double?
  ) {
    self.corporationID = corporationID
    self.corporationName = corporationName
    self.blueprintTypeID = blueprintTypeID
    self.lpCost = lpCost
    self.iskCost = iskCost
    self.quantity = quantity
    self.requiredItemsValue = requiredItemsValue
    self.iskPerLP = iskPerLP
    self.bestCharacterName = bestCharacterName
    self.availableLP = availableLP
    self.availableISK = availableISK
  }
}

public enum LoyaltyStoreBlueprintOfferBuilder {
  /// Builds the LP offers of the given Blueprint types. `characterPoints`
  /// `nil` means LP are unknown (missing scope or not synchronized), which
  /// differs from a known balance of zero.
  public static func build(
    catalog: LoyaltyStoreCatalogSnapshot?,
    blueprintTypeIDs: Set<Int64>,
    characterPoints: [CharacterLoyaltyPoints]?,
    walletISKByCharacterName: [String: Double] = [:]
  ) -> [Int64: [LoyaltyStoreBlueprintOffer]] {
    guard let catalog, let offers = catalog.offers, !blueprintTypeIDs.isEmpty
    else { return [:] }
    let prices = catalog.averagePrices ?? [:]
    let lpValues = LoyaltyPointValuation.iskPerLP(
      offers: offers,
      averagePrices: prices,
      excludedTypeIDs: blueprintTypeIDs
    )
    var bestByCorporation: [Int64: CharacterLoyaltyPoints] = [:]
    for entry in characterPoints ?? [] {
      if let current = bestByCorporation[entry.corporationID],
        current.points > entry.points
          || current.points == entry.points
            && current.characterID < entry.characterID
      {
        continue
      }
      bestByCorporation[entry.corporationID] = entry
    }
    var result: [Int64: [LoyaltyStoreBlueprintOffer]] = [:]
    for offer in offers
    where blueprintTypeIDs.contains(offer.typeID) && offer.quantity > 0
      && offer.lpCost >= 0
    {
      let best = bestByCorporation[offer.corporationID]
      result[offer.typeID, default: []].append(
        LoyaltyStoreBlueprintOffer(
          corporationID: offer.corporationID,
          corporationName: catalog.corporationNames?[offer.corporationID],
          blueprintTypeID: offer.typeID,
          lpCost: offer.lpCost,
          iskCost: offer.iskCost,
          quantity: offer.quantity,
          requiredItemsValue: LoyaltyPointValuation.requiredItemsValue(
            of: offer,
            averagePrices: prices
          ),
          iskPerLP: lpValues[offer.corporationID],
          bestCharacterName: best?.characterName,
          availableLP: characterPoints == nil ? nil : (best?.points ?? 0),
          availableISK: best.flatMap {
            walletISKByCharacterName[$0.characterName]
          }
        )
      )
    }
    return result.mapValues { offers in
      offers.sorted {
        if $0.lpCost != $1.lpCost { return $0.lpCost < $1.lpCost }
        return $0.corporationID < $1.corporationID
      }
    }
  }
}
