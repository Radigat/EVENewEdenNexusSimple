import Foundation

public struct ProductionJournalMetrics: Equatable, Sendable {
  public let requestedUnits: Int64
  public let purchasedUnits: Int64
  public let stockUnits: Int64
  public let intermediateUnits: Int64
  public let materialCost: Double?
  public let blueprintCost: Double?
  public let installationCost: Double?
  public let logisticsCost: Double?
  public let totalCost: Double?
  public let netRevenue: Double?
  public let profit: Double?
  public let margin: Double?
  public let roi: Double?

  public init(plan: IndustryPlanSnapshot) {
    requestedUnits = plan.requests.reduce(0) {
      $0 + Int64($1.wantedQuantity)
    }
    purchasedUnits = plan.materials.reduce(0) { $0 + $1.toBuy }
    stockUnits = plan.materials.reduce(0) { $0 + $1.fromStock }
    intermediateUnits = plan.materials.reduce(0) { $0 + $1.toProduce }
    materialCost = plan.materialCost
    blueprintCost = plan.costBreakdown?.blueprintCosts?.total
    installationCost = plan.installationCost
    logisticsCost = plan.costBreakdown.flatMap {
      $0.logistics?.total ?? ($0.totalProductionCost == nil ? nil : 0)
    }
    totalCost =
      plan.costBreakdown?.totalProductionCost
      ?? plan.materialCost.flatMap { materials in
        plan.installationCost.map { materials + $0 }
      }
    netRevenue = plan.listedSale.grossOrNetRevenue
    profit = plan.listedSale.profit
    margin = plan.listedSale.margin
    roi = plan.listedSale.roi
  }
}

extension IndustryPlanSnapshot {
  public var journalMetrics: ProductionJournalMetrics {
    ProductionJournalMetrics(plan: self)
  }
}
