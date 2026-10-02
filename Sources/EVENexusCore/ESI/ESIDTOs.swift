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

public struct ESICharacterRolesDTO: Codable, Sendable {
  public let roles: [String]?
}

public struct ESICorporationPublicDTO: Codable, Sendable {
  public let name: String
}

public struct ESICorporationDivisionDTO: Codable, Sendable {
  // ESI's schema does not require either field on an individual division
  // entry. Keep malformed/default-name rows optional so one incomplete label
  // cannot make an otherwise complete corporation-asset snapshot fail.
  public let division: Int?
  public let name: String?
}

public struct ESICorporationDivisionsDTO: Codable, Sendable {
  public let hangar: [ESICorporationDivisionDTO]?
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
  public let blueprintLocationID: Int64?
  public let blueprintTypeID: Int64
  public let completedDate: Date?
  public let duration: Int64?
  public let endDate: Date
  public let facilityID: Int64
  public let facilityName: String?
  public let installerID: Int64?
  public let jobID: Int64
  public let outputLocationID: Int64?
  public let productTypeID: Int64?
  public let runs: Int
  public let startDate: Date?
  public let stationID: Int64?
  public let status: String
  public let successfulRuns: Int?

  enum CodingKeys: String, CodingKey {
    case activityID = "activity_id"
    case blueprintID = "blueprint_id"
    case blueprintLocationID = "blueprint_location_id"
    case blueprintTypeID = "blueprint_type_id"
    case completedDate = "completed_date"
    case duration
    case endDate = "end_date"
    case facilityID = "facility_id"
    case facilityName = "facility_name"
    case installerID = "installer_id"
    case jobID = "job_id"
    case outputLocationID = "output_location_id"
    case productTypeID = "product_type_id"
    case runs
    case startDate = "start_date"
    case stationID = "station_id"
    case status
    case successfulRuns = "successful_runs"
  }

  public init(
    activityID: Int,
    blueprintID: Int64,
    blueprintLocationID: Int64? = nil,
    blueprintTypeID: Int64,
    completedDate: Date? = nil,
    duration: Int64? = nil,
    endDate: Date,
    facilityID: Int64,
    facilityName: String? = nil,
    installerID: Int64? = nil,
    jobID: Int64,
    outputLocationID: Int64? = nil,
    productTypeID: Int64? = nil,
    runs: Int,
    startDate: Date? = nil,
    stationID: Int64? = nil,
    status: String,
    successfulRuns: Int? = nil
  ) {
    self.activityID = activityID
    self.blueprintID = blueprintID
    self.blueprintLocationID = blueprintLocationID
    self.blueprintTypeID = blueprintTypeID
    self.completedDate = completedDate
    self.duration = duration
    self.endDate = endDate
    self.facilityID = facilityID
    self.facilityName = facilityName
    self.installerID = installerID
    self.jobID = jobID
    self.outputLocationID = outputLocationID
    self.productTypeID = productTypeID
    self.runs = runs
    self.startDate = startDate
    self.stationID = stationID
    self.status = status
    self.successfulRuns = successfulRuns
  }

  public func withFacilityName(_ facilityName: String?) -> Self {
    Self(
      activityID: activityID,
      blueprintID: blueprintID,
      blueprintLocationID: blueprintLocationID,
      blueprintTypeID: blueprintTypeID,
      completedDate: completedDate,
      duration: duration,
      endDate: endDate,
      facilityID: facilityID,
      facilityName: facilityName,
      installerID: installerID,
      jobID: jobID,
      outputLocationID: outputLocationID,
      productTypeID: productTypeID,
      runs: runs,
      startDate: startDate,
      stationID: stationID,
      status: status,
      successfulRuns: successfulRuns
    )
  }
}

public struct ESIMarketHistoryDTO: Codable, Sendable {
  public let average: Double
  public let date: String
  public let highest: Double
  public let lowest: Double
  public let orderCount: Int64
  public let volume: Int64

  enum CodingKeys: String, CodingKey {
    case average, date, highest, lowest, volume
    case orderCount = "order_count"
  }
}

public struct ESICharacterOrderDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { orderID }
  public let escrow: Double?
  public let isBuyOrder: Bool
  public let locationID: Int64
  public let orderID: Int64
  public let price: Double
  public let typeID: Int64
  public let volumeRemain: Int64

  enum CodingKeys: String, CodingKey {
    case escrow
    case isBuyOrder = "is_buy_order"
    case locationID = "location_id"
    case orderID = "order_id"
    case price
    case typeID = "type_id"
    case volumeRemain = "volume_remain"
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    escrow = try values.decodeIfPresent(Double.self, forKey: .escrow)
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

public struct ESIPrivateContractDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { contractID }
  public let collateral: Double?
  public let contractID: Int64
  public let dateExpired: Date
  public let forCorporation: Bool
  public let issuerID: Int64
  public let status: String
  public let type: String

  enum CodingKeys: String, CodingKey {
    case collateral
    case contractID = "contract_id"
    case dateExpired = "date_expired"
    case forCorporation = "for_corporation"
    case issuerID = "issuer_id"
    case status, type
  }

  public init(
    collateral: Double?,
    contractID: Int64,
    dateExpired: Date,
    forCorporation: Bool,
    issuerID: Int64,
    status: String,
    type: String
  ) {
    self.collateral = collateral
    self.contractID = contractID
    self.dateExpired = dateExpired
    self.forCorporation = forCorporation
    self.issuerID = issuerID
    self.status = status
    self.type = type
  }
}

public struct ESIPrivateContractItemDTO: Codable, Identifiable, Sendable {
  public var id: Int64 { recordID }
  public let isIncluded: Bool
  public let quantity: Int64
  public let rawQuantity: Int64?
  public let recordID: Int64
  public let typeID: Int64

  enum CodingKeys: String, CodingKey {
    case isIncluded = "is_included"
    case quantity
    case rawQuantity = "raw_quantity"
    case recordID = "record_id"
    case typeID = "type_id"
  }

  public init(
    isIncluded: Bool,
    quantity: Int64,
    rawQuantity: Int64?,
    recordID: Int64,
    typeID: Int64
  ) {
    self.isIncluded = isIncluded
    self.quantity = quantity
    self.rawQuantity = rawQuantity
    self.recordID = recordID
    self.typeID = typeID
  }
}

public struct ESICorporationWalletDTO: Codable, Sendable {
  public let balance: Double
  public let division: Int

  public init(balance: Double, division: Int) {
    self.balance = balance
    self.division = division
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
