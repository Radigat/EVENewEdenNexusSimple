import Foundation

public enum IndustryCostActivity: String, Codable, CaseIterable, Sendable {
  case copying
  case duplicating
  case invention
  case manufacturing
  case none
  case reaction
  case researchingMaterialEfficiency = "researching_material_efficiency"
  case researchingTechnology = "researching_technology"
  case researchingTimeEfficiency = "researching_time_efficiency"
  case reverseEngineering = "reverse_engineering"

  public var displayName: String {
    switch self {
    case .manufacturing: "Manufacturing"
    case .invention: "Invention"
    case .reaction: "Reaction"
    case .copying: "Blueprint copying"
    case .duplicating: "Duplicating"
    case .researchingMaterialEfficiency: "Material research"
    case .researchingTimeEfficiency: "Time research"
    case .researchingTechnology: "Technology research"
    case .reverseEngineering: "Reverse engineering"
    case .none: "None"
    }
  }

  public var displayOrder: Int {
    switch self {
    case .manufacturing: 0
    case .invention: 1
    case .reaction: 2
    case .copying: 3
    case .researchingMaterialEfficiency: 4
    case .researchingTimeEfficiency: 5
    case .researchingTechnology: 6
    case .reverseEngineering: 7
    case .duplicating: 8
    case .none: 9
    }
  }
}

public struct IndustryActivityCostIndex: Identifiable, Codable, Equatable,
  Sendable
{
  public var id: String { activityRawValue }
  public let activityRawValue: String
  public let value: Double

  public init(activity: IndustryCostActivity, value: Double) {
    self.activityRawValue = activity.rawValue
    self.value = value
  }

  public init(activityRawValue: String, value: Double) {
    self.activityRawValue = activityRawValue
    self.value = value
  }

  public var activity: IndustryCostActivity? {
    IndustryCostActivity(rawValue: activityRawValue)
  }

  public var displayName: String {
    activity?.displayName
      ?? activityRawValue.replacingOccurrences(of: "_", with: " ").capitalized
  }

  public var displayOrder: Int {
    activity?.displayOrder ?? Int.max
  }
}

public struct IndustrySystemCostIndexSnapshot: Identifiable, Codable,
  Equatable, Sendable
{
  public var id: Int64 { solarSystemID }
  public let solarSystemID: Int64
  public let indices: [IndustryActivityCostIndex]

  public init(
    solarSystemID: Int64,
    indices: [IndustryActivityCostIndex]
  ) {
    self.solarSystemID = solarSystemID
    self.indices = indices.sorted {
      if $0.displayOrder != $1.displayOrder {
        return $0.displayOrder < $1.displayOrder
      }
      return $0.activityRawValue < $1.activityRawValue
    }
  }
}
