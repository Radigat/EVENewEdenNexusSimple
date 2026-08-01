import Foundation

public struct ESICharacterPublicDTO: Codable, Sendable {
  public let name: String
  public let corporationID: Int64

  enum CodingKeys: String, CodingKey {
    case name
    case corporationID = "corporation_id"
  }
}

public struct ESISkillDTO: Codable, Sendable {
  public let activeSkillLevel: Int
  public let skillID: Int64
  public let skillpointsInSkill: Int64
  public let trainedSkillLevel: Int

  enum CodingKeys: String, CodingKey {
    case activeSkillLevel = "active_skill_level"
    case skillID = "skill_id"
    case skillpointsInSkill = "skillpoints_in_skill"
    case trainedSkillLevel = "trained_skill_level"
  }
}

public struct ESISkillsDTO: Codable, Sendable {
  public let skills: [ESISkillDTO]
}

public struct ESIStandingDTO: Codable, Sendable {
  public let fromID: Int64
  public let standing: Double

  enum CodingKeys: String, CodingKey {
    case fromID = "from_id"
    case standing
  }
}

public struct ESIAssetDTO: Codable, Sendable {
  public let itemID: Int64
  public let locationFlag: String
  public let locationID: Int64
  public let locationType: String
  public let quantity: Int64
  public let singleton: Bool
  public let typeID: Int64

  enum CodingKeys: String, CodingKey {
    case itemID = "item_id"
    case locationFlag = "location_flag"
    case locationID = "location_id"
    case locationType = "location_type"
    case quantity
    case singleton = "is_singleton"
    case typeID = "type_id"
  }
}

public struct ESIBlueprintDTO: Codable, Sendable {
  public let itemID: Int64
  public let locationID: Int64
  public let materialEfficiency: Int
  public let quantity: Int64
  public let runs: Int
  public let timeEfficiency: Int
  public let typeID: Int64

  enum CodingKeys: String, CodingKey {
    case itemID = "item_id"
    case locationID = "location_id"
    case materialEfficiency = "material_efficiency"
    case quantity, runs
    case timeEfficiency = "time_efficiency"
    case typeID = "type_id"
  }
}

public struct ESIIndustryJobDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { jobID }
  public let activityID: Int
  public let blueprintID: Int64
  public let blueprintTypeID: Int64
  public let endDate: Date
  public let facilityID: Int64
  public let jobID: Int64
  public let runs: Int
  public let status: String

  enum CodingKeys: String, CodingKey {
    case activityID = "activity_id"
    case blueprintID = "blueprint_id"
    case blueprintTypeID = "blueprint_type_id"
    case endDate = "end_date"
    case facilityID = "facility_id"
    case jobID = "job_id"
    case runs, status
  }
}

public struct ESICharacterOrderDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { orderID }
  public let isBuyOrder: Bool
  public let locationID: Int64
  public let orderID: Int64
  public let price: Double
  public let typeID: Int64
  public let volumeRemain: Int64

  enum CodingKeys: String, CodingKey {
    case isBuyOrder = "is_buy_order"
    case locationID = "location_id"
    case orderID = "order_id"
    case price
    case typeID = "type_id"
    case volumeRemain = "volume_remain"
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    isBuyOrder =
      try values.decodeIfPresent(Bool.self, forKey: .isBuyOrder)
      ?? false
    locationID = try values.decode(Int64.self, forKey: .locationID)
    orderID = try values.decode(Int64.self, forKey: .orderID)
    price = try values.decode(Double.self, forKey: .price)
    typeID = try values.decode(Int64.self, forKey: .typeID)
    volumeRemain = try values.decode(Int64.self, forKey: .volumeRemain)
  }
}

public struct ESIWalletJournalDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { journalID }
  public let amount: Double?
  public let balance: Double?
  public let date: Date
  public let journalID: Int64
  public let refType: String

  enum CodingKeys: String, CodingKey {
    case amount, balance, date
    case journalID = "id"
    case refType = "ref_type"
  }
}

public struct ESIWalletTransactionDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { transactionID }
  public let clientID: Int64
  public let date: Date
  public let isBuy: Bool
  public let quantity: Int64
  public let transactionID: Int64
  public let typeID: Int64
  public let unitPrice: Double

  enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
    case date
    case isBuy = "is_buy"
    case quantity
    case transactionID = "transaction_id"
    case typeID = "type_id"
    case unitPrice = "unit_price"
  }
}

public struct ESIMarketOrderDTO: Codable, Sendable {
  public let duration: Int
  public let isBuyOrder: Bool
  public let issued: Date
  public let locationID: Int64
  public let minVolume: Int64
  public let orderID: Int64
  public let price: Double
  public let range: String
  public let systemID: Int64
  public let typeID: Int64
  public let volumeRemain: Int64
  public let volumeTotal: Int64

  enum CodingKeys: String, CodingKey {
    case duration
    case isBuyOrder = "is_buy_order"
    case issued
    case locationID = "location_id"
    case minVolume = "min_volume"
    case orderID = "order_id"
    case price
    case range
    case systemID = "system_id"
    case typeID = "type_id"
    case volumeRemain = "volume_remain"
    case volumeTotal = "volume_total"
  }
}

public struct ESIAdjustedPriceDTO: Codable, Sendable {
  public let adjustedPrice: Double?
  public let averagePrice: Double?
  public let typeID: Int64

  enum CodingKeys: String, CodingKey {
    case adjustedPrice = "adjusted_price"
    case averagePrice = "average_price"
    case typeID = "type_id"
  }
}

public struct ESIIndustrySystemCostIndexDTO: Codable, Sendable {
  public let activity: String
  public let costIndex: Double

  enum CodingKeys: String, CodingKey {
    case activity
    case costIndex = "cost_index"
  }
}

public struct ESIIndustrySystemDTO: Codable, Sendable {
  public let costIndices: [ESIIndustrySystemCostIndexDTO]
  public let solarSystemID: Int64

  enum CodingKeys: String, CodingKey {
    case costIndices = "cost_indices"
    case solarSystemID = "solar_system_id"
  }
}
