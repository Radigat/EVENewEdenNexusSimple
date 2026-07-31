import Foundation

public enum BlueprintCopyKind: String, Codable, Sendable {
  case original
  case copy
  case unknown
}

public struct BlueprintMaterial: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let quantity: Int64
}

public struct BlueprintProduct: Codable, Hashable, Sendable {
  public let typeID: Int64
  public let quantity: Int64
  public let probability: Double?
}

public struct BlueprintActivityDefinition: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case manufacturing
    case reaction
    case invention
  }

  public let kind: Kind
  public let durationSeconds: Int64
  public let materials: [BlueprintMaterial]
  public let products: [BlueprintProduct]
}

public struct BlueprintDefinition: Identifiable, Codable, Hashable, Sendable {
  public var id: Int64 { blueprintTypeID }
  public let blueprintTypeID: Int64
  public let productTypeID: Int64
  public let maxProductionLimit: Int64?
  public let activity: BlueprintActivityDefinition
  public let source: SourceIdentity
}

public struct OwnedBlueprintInstance: Identifiable, Codable, Hashable, Sendable {
  public let id: Int64
  public let blueprintTypeID: Int64
  public let locationID: Int64
  public let quantity: Int64
  public let runs: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let kind: BlueprintCopyKind
  public let source: SourceIdentity

  public init(
    id: Int64,
    blueprintTypeID: Int64,
    locationID: Int64,
    quantity: Int64,
    runs: Int,
    materialEfficiency: Int,
    timeEfficiency: Int,
    source: SourceIdentity
  ) {
    self.id = id
    self.blueprintTypeID = blueprintTypeID
    self.locationID = locationID
    self.quantity = quantity
    self.runs = runs
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    if quantity == -1 {
      self.kind = .original
    } else if quantity == -2 {
      self.kind = .copy
    } else {
      self.kind = .unknown
    }
    self.source = source
  }
}

public struct BlueprintActivityCandidate: Identifiable, Codable, Sendable {
  public let id: UUID
  public let definition: BlueprintDefinition
  public let ownedInstance: OwnedBlueprintInstance?
  public let runs: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let warnings: [DomainWarning]
}
