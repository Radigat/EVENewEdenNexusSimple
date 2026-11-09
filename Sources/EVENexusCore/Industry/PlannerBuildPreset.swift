import Foundation

/// ME/TE preset the Planner build link (hammer beside an item name) and the
/// Planner's product adder suggest for one product (owner decision
/// 09.11.2026). The user can still change both values in the Planner; the
/// preset never changes a calculation rule.
public struct PlannerBuildEfficiencyPreset: Equatable, Sendable {
  /// Production class the preset was derived from.
  public enum Basis: String, CaseIterable, Equatable, Sendable {
    case techI
    case techII
    case techIII
    case faction
    case storyline
    case other
    /// Reactions use neither ME nor TE; the Planner ignores both values.
    case reaction
  }

  public let basis: Basis
  public let materialEfficiency: Int
  public let timeEfficiency: Int

  /// `true` for reactions: the adder locks both fields because the Planner
  /// does not apply ME or TE to a reaction job.
  public var efficiencyLocked: Bool { basis == .reaction }

  public init(basis: Basis) {
    self.basis = basis
    switch basis {
    case .techI:
      materialEfficiency = 10
      timeEfficiency = 20
    case .techII, .techIII:
      materialEfficiency = 3
      timeEfficiency = 2
    case .faction, .storyline, .other, .reaction:
      materialEfficiency = 0
      timeEfficiency = 0
    }
  }

  public static func resolve(
    activity: BlueprintActivityDefinition.Kind,
    metaGroupID: Int64?,
    techLevel: Int?
  ) -> Self {
    if activity == .reaction {
      return Self(basis: .reaction)
    }
    return Self(basis: basis(metaGroupID: metaGroupID, techLevel: techLevel))
  }

  /// SDE meta groups: 1 Tech I, 2 Tech II, 3 Storyline, 4 Faction,
  /// 14 Tech III, 52 Structure Faction, 53 Structure Tech II and
  /// 54 Structure Tech I. Structure groups follow their tech level, and a
  /// product without meta group and tech level (components, fuel blocks,
  /// Upwell structures, containers) counts as Tech I because it is built
  /// from an ordinary researchable BPO (owner decisions 09.11.2026). Other
  /// meta groups (Officer, Deadspace, mutaplasmids, limited editions) are
  /// built from BPCs and count as other.
  public static func basis(metaGroupID: Int64?, techLevel: Int?) -> Basis {
    switch metaGroupID {
    case 1, 54: return .techI
    case 2, 53: return .techII
    case 14: return .techIII
    case 4, 52: return .faction
    case 3: return .storyline
    case .some: return .other
    case nil:
      switch techLevel {
      case nil, 1: return .techI
      case 2: return .techII
      case 3: return .techIII
      default: return .other
      }
    }
  }
}

/// One product the build link can hand to the Planner: the exact English
/// SDE name the input line resolves, the output per run and the preset.
public struct PlannerBuildTarget: Equatable, Sendable {
  public let product: ManufacturingProductSearchResult
  public let activity: BlueprintActivityDefinition.Kind
  public let preset: PlannerBuildEfficiencyPreset

  public init(
    product: ManufacturingProductSearchResult,
    activity: BlueprintActivityDefinition.Kind
  ) {
    self.product = product
    self.activity = activity
    preset = PlannerBuildEfficiencyPreset.resolve(
      activity: activity,
      metaGroupID: product.metaGroupID,
      techLevel: product.techLevel
    )
  }
}
