import Foundation

public enum ProductionTreeStockCoverage: String, Sendable {
  case full
  case partial
  case none
  case unavailable
}

public enum ProductionTreeBlueprintAction: String, CaseIterable, Sendable {
  case useOwnedBPC
  case useOwnedBPO
  case copyOwnedBPO
  case invent
  case buyContractBPC
  case buyContractBPO
  case buyMarketBPO
  case buyLoyaltyStoreBPC
  case manualExternalBPC
  case useOwnedReactionFormula
  case unavailable
  case unresolved
}

public struct ProductionTreeBlueprintCostChoice: Sendable {
  public let blueprintTypeID: Int64
  public let productName: String
  public let action: ProductionTreeBlueprintAction
  public let manualAmount: Double?
  public let attributableBPCContractPrice: Double?
  public let attributableBPCContractCount: Int
  public let attributableBPCContractRuns: Int?
  /// Runs and ME/TE the plan uses from a bought BPO. A bought BPO without an
  /// entered allocation is valued like the BPC runs it replaces.
  public let usedRuns: Int
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let contractOptions: [ProductionTreeContractBlueprintOption]

  public init(
    blueprintTypeID: Int64,
    productName: String,
    action: ProductionTreeBlueprintAction,
    manualAmount: Double? = nil,
    attributableBPCContractPrice: Double? = nil,
    attributableBPCContractCount: Int = 0,
    attributableBPCContractRuns: Int? = nil,
    usedRuns: Int = 0,
    materialEfficiency: Int = 0,
    timeEfficiency: Int = 0,
    contractOptions: [ProductionTreeContractBlueprintOption] = []
  ) {
    self.blueprintTypeID = blueprintTypeID
    self.productName = productName
    self.action = action
    self.manualAmount = manualAmount
    self.attributableBPCContractPrice = attributableBPCContractPrice
    self.attributableBPCContractCount = attributableBPCContractCount
    self.attributableBPCContractRuns = attributableBPCContractRuns
    self.usedRuns = usedRuns
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.contractOptions = contractOptions
  }
}

public enum ProductionTreeBlueprintCostProjector {
  /// Owner decision 2026-10-19: an owned BPO/BPC without an entered cost is counted as 0 ISK
  /// instead of keeping the total production cost unavailable. Copies, invention and purchases
  /// still need an explicit cost.
  public static let ownedWithoutEnteredCostSource =
    "Owned blueprint without entered cost (counted as 0 ISK)"
  /// Owner decision 2026-10-30: a BPO that still has to be bought (market or
  /// Contract) and has no entered allocation is charged with the BPC runs it
  /// replaces, at the cheapest equal-or-better public BPC Contract price per
  /// run. Without such a Contract it stays unresolved.
  public static let purchasedBPOValuedByBPCContractsSource =
    "Bought BPO valued at the cheapest public BPC Contract price per run"

  public static func allocations(
    for choices: [ProductionTreeBlueprintCostChoice]
  ) -> [Int64: IndustryBlueprintCostAllocation] {
    choices.sorted { $0.blueprintTypeID < $1.blueprintTypeID }.reduce(
      into: [:]
    ) { result, choice in
      guard choice.blueprintTypeID > 0 else { return }
      let manualAmount = choice.manualAmount.flatMap(validAmount)
      let allocation: IndustryBlueprintCostAllocation?
      switch choice.action {
      case .buyContractBPC:
        guard let price = choice.attributableBPCContractPrice.flatMap(validAmount)
        else { return }
        let runs = choice.attributableBPCContractRuns.map(String.init) ?? "—"
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpc,
          amount: price,
          source:
            "\(max(0, choice.attributableBPCContractCount)) exact Main Hub single-line BPC Contract(s), \(runs) runs"
        )
      case .useOwnedBPC where manualAmount == nil:
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpc,
          amount: 0,
          source: ownedWithoutEnteredCostSource
        )
      case .useOwnedBPO where manualAmount == nil:
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpo,
          amount: 0,
          source: ownedWithoutEnteredCostSource
        )
      case .useOwnedBPC, .invent, .buyLoyaltyStoreBPC, .manualExternalBPC:
        guard let manualAmount else { return }
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpc,
          amount: manualAmount,
          source:
            choice.action == .buyLoyaltyStoreBPC
            ? "Configured Loyalty Store BPC ISK equivalent"
            : "Explicit BPC acquisition or activity cost"
        )
      case .buyContractBPO where manualAmount == nil,
        .buyMarketBPO where manualAmount == nil:
        guard
          let value = OwnedBPCValuation.marketValue(
            usedRuns: choice.usedRuns,
            materialEfficiency: choice.materialEfficiency,
            timeEfficiency: choice.timeEfficiency,
            offers: choice.contractOptions
          )
        else { return }
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpo,
          amount: value,
          source: purchasedBPOValuedByBPCContractsSource
        )
      case .useOwnedBPO, .copyOwnedBPO, .buyContractBPO, .buyMarketBPO:
        guard let manualAmount else { return }
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .bpo,
          amount: manualAmount,
          source: "Explicit BPO allocation for this production plan"
        )
      case .useOwnedReactionFormula:
        allocation = IndustryBlueprintCostAllocation(
          blueprintTypeID: choice.blueprintTypeID,
          productName: choice.productName,
          kind: .formula,
          amount: manualAmount ?? 0,
          source: "Explicitly selected owned reaction formula"
        )
      case .unavailable, .unresolved:
        allocation = nil
      }
      if let allocation {
        result[choice.blueprintTypeID] = allocation
      }
    }
  }

  /// Allocations for Blueprint supply plans that are covered completely by
  /// concrete public BPC Contracts. Each Contract is charged at its full
  /// price, even when only part of its runs is used, because a Contract can
  /// only be bought as a whole. Plans with a run shortfall, another source
  /// kind or an unknown price stay unresolved.
  public static func contractBPCAllocations(
    supplyPlans: [Int64: BlueprintSupplyPlan]
  ) -> [Int64: IndustryBlueprintCostAllocation] {
    supplyPlans.reduce(into: [:]) { result, entry in
      let (blueprintTypeID, plan) = entry
      let jobs = plan.manufacturingJobs
      guard blueprintTypeID > 0,
        plan.requiredRuns > 0,
        !jobs.isEmpty,
        jobs.allSatisfy({
          if case .contractBPC = $0.allocation.source { return true }
          return false
        }),
        jobs.reduce(0, { $0 + max(0, $1.allocation.allocatedRuns) })
          >= plan.requiredRuns,
        let amount = plan.batchAllocationCost.flatMap(validAmount)
      else { return }
      let contractCount = Set(jobs.map(\.allocation.source)).count
      result[blueprintTypeID] = IndustryBlueprintCostAllocation(
        blueprintTypeID: blueprintTypeID,
        productName: plan.productName,
        kind: .bpc,
        amount: amount,
        source:
          "\(contractCount) concrete Main Hub BPC Contract(s), \(plan.requiredRuns) allocated runs"
      )
    }
  }

  private static func validAmount(_ amount: Double) -> Double? {
    amount.isFinite && amount >= 0 ? amount : nil
  }
}

public struct ProductionTreeBPCContractSelection: Sendable {
  public let offers: [PublicContractSearchResult]
  public let requiredRuns: Int
  public let coveredRuns: Int
  public let totalPrice: Double

  public var contractCount: Int { offers.count }

  public init(
    offers: [PublicContractSearchResult],
    requiredRuns: Int,
    coveredRuns: Int,
    totalPrice: Double
  ) {
    self.offers = offers
    self.requiredRuns = requiredRuns
    self.coveredRuns = coveredRuns
    self.totalPrice = totalPrice
  }
}

/// Selects a deterministic set of attributable BPC Contracts that covers the
/// requested runs. The policy prefers the lowest total price among a
/// price-per-run coverage and every valid offer used as an explicit anchor.
/// This remains bounded for a large public-Contract index and never divides a
/// bundle price across unrelated items.
public enum ProductionTreeBPCContractSelector {
  public static func select(
    requiredRuns: Int,
    from offers: [PublicContractSearchResult]
  ) -> ProductionTreeBPCContractSelection? {
    let required = max(0, requiredRuns)
    guard required > 0 else { return nil }
    let candidates = Dictionary(
      grouping: offers.filter {
        $0.isAttributableBlueprintOffer
          && $0.isBlueprintCopy == true
          && ($0.runs ?? 0) > 0
          && $0.effectiveContractPrice != nil
      },
      by: \.contractID
    ).compactMap { _, duplicates in
      duplicates.sorted(by: offerOrder).first
    }.sorted(by: runPriceOrder)
    guard !candidates.isEmpty else { return nil }

    var selections: [[PublicContractSearchResult]] = []
    if let greedy = greedyCoverage(requiredRuns: required, offers: candidates) {
      selections.append(greedy)
    }
    for anchor in candidates {
      let remaining = max(0, required - max(0, anchor.runs ?? 0))
      if remaining == 0 {
        selections.append([anchor])
      } else if let rest = greedyCoverage(
        requiredRuns: remaining,
        offers: candidates.filter { $0.contractID != anchor.contractID }
      ) {
        selections.append([anchor] + rest)
      }
    }

    return selections.compactMap {
      selection($0, requiredRuns: required)
    }.min(by: selectionOrder)
  }

  private static func greedyCoverage(
    requiredRuns: Int,
    offers: [PublicContractSearchResult]
  ) -> [PublicContractSearchResult]? {
    guard requiredRuns > 0 else { return [] }
    var covered = 0
    var selected: [PublicContractSearchResult] = []
    for offer in offers.sorted(by: runPriceOrder) where covered < requiredRuns {
      covered = saturatedAdd(covered, max(0, offer.runs ?? 0))
      selected.append(offer)
    }
    return covered >= requiredRuns ? selected : nil
  }

  private static func selection(
    _ offers: [PublicContractSearchResult],
    requiredRuns: Int
  ) -> ProductionTreeBPCContractSelection? {
    var runs = 0
    var price = 0.0
    for offer in offers {
      guard let offerPrice = offer.effectiveContractPrice else { return nil }
      runs = saturatedAdd(runs, max(0, offer.runs ?? 0))
      price += offerPrice
      guard price.isFinite else { return nil }
    }
    guard requiredRuns == 0 || runs >= requiredRuns else { return nil }
    return ProductionTreeBPCContractSelection(
      offers: offers.sorted(by: offerOrder),
      requiredRuns: requiredRuns,
      coveredRuns: runs,
      totalPrice: price
    )
  }

  private static func selectionOrder(
    _ lhs: ProductionTreeBPCContractSelection,
    _ rhs: ProductionTreeBPCContractSelection
  ) -> Bool {
    if lhs.totalPrice != rhs.totalPrice {
      return lhs.totalPrice < rhs.totalPrice
    }
    if lhs.coveredRuns != rhs.coveredRuns {
      return lhs.coveredRuns < rhs.coveredRuns
    }
    if lhs.contractCount != rhs.contractCount {
      return lhs.contractCount < rhs.contractCount
    }
    return lhs.offers.map(\.contractID).lexicographicallyPrecedes(
      rhs.offers.map(\.contractID)
    )
  }

  private static func runPriceOrder(
    _ lhs: PublicContractSearchResult,
    _ rhs: PublicContractSearchResult
  ) -> Bool {
    let lhsUnit =
      (lhs.effectiveContractPrice ?? .greatestFiniteMagnitude)
      / Double(max(1, lhs.runs ?? 0))
    let rhsUnit =
      (rhs.effectiveContractPrice ?? .greatestFiniteMagnitude)
      / Double(max(1, rhs.runs ?? 0))
    if lhsUnit != rhsUnit { return lhsUnit < rhsUnit }
    return offerOrder(lhs, rhs)
  }

  private static func offerOrder(
    _ lhs: PublicContractSearchResult,
    _ rhs: PublicContractSearchResult
  ) -> Bool {
    let lhsPrice = lhs.effectiveContractPrice ?? .greatestFiniteMagnitude
    let rhsPrice = rhs.effectiveContractPrice ?? .greatestFiniteMagnitude
    if lhsPrice != rhsPrice { return lhsPrice < rhsPrice }
    if lhs.contractID != rhs.contractID { return lhs.contractID < rhs.contractID }
    return lhs.recordID < rhs.recordID
  }

  private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
  }
}

public struct ProductionTreeOwnedBlueprintEfficiencyOption: Identifiable,
  Sendable
{
  public let id: String
  public let kind: BlueprintCopyKind
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  /// BPC runs available at the exact production location. BPOs have no finite
  /// run limit and therefore keep this value unavailable instead of inventing
  /// a number.
  public let availableRuns: Int?
  public let instanceCount: Int
  public let ownerNames: [String]
  public let sourceStates: [DataFreshness]

  public init(
    kind: BlueprintCopyKind,
    materialEfficiency: Int,
    timeEfficiency: Int,
    availableRuns: Int?,
    instanceCount: Int,
    ownerNames: [String],
    sourceStates: [DataFreshness]
  ) {
    self.id = [
      kind.rawValue,
      String(materialEfficiency),
      String(timeEfficiency),
    ].joined(separator: ":")
    self.kind = kind
    self.materialEfficiency = materialEfficiency
    self.timeEfficiency = timeEfficiency
    self.availableRuns = availableRuns
    self.instanceCount = instanceCount
    self.ownerNames = ownerNames
    self.sourceStates = sourceStates
  }
}

public struct ProductionTreeOwnedBlueprintInstanceOption: Identifiable,
  Sendable
{
  public var id: Int64 { itemID }
  public let itemID: Int64
  public let kind: BlueprintCopyKind
  public let runs: Int?
  public let materialEfficiency: Int
  public let timeEfficiency: Int
  public let ownerID: Int64
  public let ownerName: String
  public let locationID: Int64
  public let locationName: String?
  public let sourceState: DataFreshness
  public let sourceSnapshotID: UUID
}

public struct ProductionTreeContractBlueprintOption: Identifiable, Sendable {
  public var id: Int64 { recordID }
  public let recordID: Int64
  public let contractID: Int64
  public let kind: BlueprintCopyKind
  public let runs: Int?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let price: Double
  public let locationID: Int64
  public let locationName: String
}

public struct ProductionTreeMarketBPOOption: Identifiable, Sendable {
  public var id: Int64 { orderID }
  public let orderID: Int64
  public let price: Double
  public let locationID: Int64
  public let sourceState: DataFreshness
  public let sourceSnapshotID: UUID
}

public struct ProductionTreeBlueprintAssessment: Sendable {
  public let blueprintTypeID: Int64
  public let blueprintName: String
  public let requiredRuns: Int
  public let recommendation: ProductionTreeBlueprintAction
  public let availableActions: Set<ProductionTreeBlueprintAction>
  public let productionLocationIDs: [Int64]
  public let productionLocationNames: [String]
  public let exactLocationBPCRuns: Int
  public let exactLocationBPCRequiredCount: Int?
  public let exactLocationBPCOwnerNames: [String]
  public let exactLocationBPOOwnerNames: [String]
  public let exactLocationBPCSourceStates: [DataFreshness]
  public let exactLocationBPOSourceStates: [DataFreshness]
  public let exactLocationBPCCount: Int
  public let exactLocationBPOCount: Int
  /// Concrete ME/TE variants from owned BPCs and BPOs at the exact production
  /// location. The UI can select one factual variant instead of assigning a
  /// generic research level to every owned Blueprint.
  public let exactLocationEfficiencyOptions: [ProductionTreeOwnedBlueprintEfficiencyOption]
  public let exactLocationInstanceOptions: [ProductionTreeOwnedBlueprintInstanceOption]
  public let otherLocationInstanceOptions: [ProductionTreeOwnedBlueprintInstanceOption]
  public let copyingLocationBPOCount: Int
  public let inventionSourceCount: Int
  public let researchLocationBPCCount: Int
  public let researchLocationBPOCount: Int
  public let exactLocationUnknownCount: Int
  public let otherLocationCount: Int
  public let otherLocationBPCCount: Int
  public let otherLocationBPOCount: Int
  public let indexedContractOfferCount: Int
  public let attributableBPCContractCount: Int
  public let attributableBPOContractCount: Int
  public let attributableContractOptions: [ProductionTreeContractBlueprintOption]
  public let marketBPOOptions: [ProductionTreeMarketBPOOption]
  public let attributableBPCContractSelectionCount: Int
  public let attributableBPCContractRuns: Int?
  public let attributableBPCContractME: Int?
  public let attributableBPCContractTE: Int?
  /// Total price of the selected exact-Main-Hub single-line BPC Contracts that
  /// together cover the known required runs for this production node.
  public let attributableBPCContractPrice: Double?
  /// Full purchase price of the cheapest attributable BPO Contract. It is
  /// shown separately and never silently charged to one production batch.
  public let attributableBPOContractPrice: Double?
  /// Lowest complete Contract price of any exact type. This remains
  /// informational because a bundle cannot be allocated safely.
  public let lowestWholeContractPrice: Double?
  public let inventoryIsComplete: Bool
}

public enum BlueprintSupplyPlanner {
  public static func plans(
    referencePlan: IndustryPlanSnapshot,
    assessments: [ProductionTreeBlueprintAssessment],
    actions: [Int64: ProductionTreeBlueprintAction],
    manualCosts: [Int64: Double],
    preferredEfficiencies: [Int64: IndustryProductionEfficiency],
    planID: UUID,
    existingReservations: [BlueprintRunReservation],
    preferredSources: [Int64: [BlueprintSourceReference]] = [:]
  ) -> [Int64: BlueprintSupplyPlan] {
    // The production-tree projection attaches the same aggregated Blueprint
    // assessment to every recursive node that uses that Blueprint type. A
    // shared intermediate can therefore appear more than once here even
    // though its runs are intentionally combined below. Group those valid
    // projections instead of requiring globally unique type IDs.
    let assessmentsByTypeID = Dictionary(
      grouping: assessments,
      by: \.blueprintTypeID
    )
    let produced = Dictionary(
      grouping: referencePlan.nodes.filter {
        $0.action == .produce && $0.activity == .manufacturing
          && $0.blueprintTypeID != nil
      }
    ) { $0.blueprintTypeID! }
    let reservedByItemID = Dictionary(
      grouping: existingReservations.filter { $0.planID != planID },
      by: \.blueprintItemID
    ).mapValues { values in
      values.reduce(0) { $0 + max(0, $1.runs) }
    }
    var result: [Int64: BlueprintSupplyPlan] = [:]
    for (blueprintTypeID, nodes) in produced.sorted(by: { $0.key < $1.key }) {
      guard let assessment = assessmentsByTypeID[blueprintTypeID]?.first,
        let firstNode = nodes.first
      else { continue }
      let requiredRuns = nodes.reduce(0) {
        saturatedAdd($0, max(0, $1.runs ?? 0))
      }
      let action = actions[blueprintTypeID] ?? assessment.recommendation
      let preferred = preferredEfficiencies[firstNode.typeID]
      let preferredSourceOrder = Dictionary(
        preferredSources[blueprintTypeID, default: []]
          .enumerated().map { ($0.element.stableID, $0.offset) },
        uniquingKeysWith: { current, _ in current }
      )
      let totalProducedQuantity = nodes.reduce(Int64(0)) {
        AssetWarehouse.saturatedAdd($0, max(0, $1.requiredQuantity))
      }
      let outputPerRun = max(
        Int64(1),
        requiredRuns > 0 ? totalProducedQuantity / Int64(requiredRuns) : 1
      )
      let demandID = BlueprintDemandID(
        requestID: firstNode.topLevelRequestID ?? referencePlan.id,
        blueprintTypeID: blueprintTypeID,
        productTypeID: firstNode.typeID,
        nodePath: nodes.map(\.typeID).sorted()
      )
      var jobs: [BlueprintManufacturingJob] = []
      var reservations: [BlueprintRunReservation] = []
      var transfers: [BlueprintTransferRequirement] = []
      var warnings: [DomainWarning] = []
      var capitalPurchaseCost: Double?
      var batchAllocationCost = validCost(manualCosts[blueprintTypeID])

      func makeJob(
        allocation: BlueprintRunAllocation,
        runs: Int
      ) -> BlueprintManufacturingJob {
        BlueprintManufacturingJob(
          demandID: demandID,
          allocation: allocation,
          blueprintTypeID: blueprintTypeID,
          productTypeID: firstNode.typeID,
          runs: runs,
          outputQuantity: saturatedMultiply(
            Int64(runs),
            outputPerRun
          )
        )
      }

      switch action {
      case .useOwnedBPC:
        var remaining = requiredRuns
        let exactItemIDs = Set(
          assessment.exactLocationInstanceOptions.map(\.itemID)
        )
        let candidates =
          (assessment.exactLocationInstanceOptions
          + assessment.otherLocationInstanceOptions).filter {
            $0.kind == .copy
              && max(0, $0.runs ?? 0)
                > reservedByItemID[$0.itemID, default: 0]
          }.sorted { lhs, rhs in
            sourceOrder(
              .ownedBPC(itemID: lhs.itemID),
              .ownedBPC(itemID: rhs.itemID),
              preferredOrder: preferredSourceOrder
            )
              ?? ownedOrder(
                lhs,
                rhs,
                preferred: preferred,
                preferredLocationItemIDs: exactItemIDs
              )
          }
        for candidate in candidates where remaining > 0 {
          let available = max(
            0,
            (candidate.runs ?? 0)
              - reservedByItemID[candidate.itemID, default: 0]
          )
          let used = min(remaining, available)
          guard used > 0 else { continue }
          let allocation = BlueprintRunAllocation(
            source: .ownedBPC(itemID: candidate.itemID),
            provenance: .copiedFromOriginal,
            availableRuns: available,
            allocatedRuns: used,
            remainingRuns: available - used,
            materialEfficiency: candidate.materialEfficiency,
            timeEfficiency: candidate.timeEfficiency,
            ownerID: candidate.ownerID,
            ownerName: candidate.ownerName,
            locationID: candidate.locationID,
            locationName: candidate.locationName,
            sourceState: candidate.sourceState,
            sourceSnapshotID: candidate.sourceSnapshotID
          )
          jobs.append(makeJob(allocation: allocation, runs: used))
          appendTransferIfNeeded(
            allocation: allocation,
            assessment: assessment,
            transfers: &transfers,
            warnings: &warnings
          )
          reservations.append(
            BlueprintRunReservation(
              planID: planID,
              blueprintItemID: candidate.itemID,
              runs: used
            )
          )
          remaining -= used
        }
        appendShortfallWarning(
          remainingRuns: remaining,
          blueprintName: assessment.blueprintName,
          warnings: &warnings
        )
      case .useOwnedBPO:
        let exactItemIDs = Set(
          assessment.exactLocationInstanceOptions.map(\.itemID)
        )
        if let candidate =
          (assessment.exactLocationInstanceOptions
          + assessment.otherLocationInstanceOptions).filter({
            $0.kind == .original
          }).sorted(by: { lhs, rhs in
            sourceOrder(
              .ownedBPO(itemID: lhs.itemID),
              .ownedBPO(itemID: rhs.itemID),
              preferredOrder: preferredSourceOrder
            )
              ?? ownedOrder(
                lhs,
                rhs,
                preferred: preferred,
                preferredLocationItemIDs: exactItemIDs
              )
          }).first
        {
          let provenance: BlueprintPlanningProvenance =
            firstNode.sourceTechLevel == 2
            ? .legacyT2Original : .researchedOriginal
          let allocation = BlueprintRunAllocation(
            source: .ownedBPO(itemID: candidate.itemID),
            provenance: provenance,
            availableRuns: nil,
            allocatedRuns: requiredRuns,
            remainingRuns: nil,
            materialEfficiency: candidate.materialEfficiency,
            timeEfficiency: candidate.timeEfficiency,
            ownerID: candidate.ownerID,
            ownerName: candidate.ownerName,
            locationID: candidate.locationID,
            locationName: candidate.locationName,
            sourceState: candidate.sourceState,
            sourceSnapshotID: candidate.sourceSnapshotID
          )
          jobs.append(makeJob(allocation: allocation, runs: requiredRuns))
          appendTransferIfNeeded(
            allocation: allocation,
            assessment: assessment,
            transfers: &transfers,
            warnings: &warnings
          )
        } else {
          appendShortfallWarning(
            remainingRuns: requiredRuns,
            blueprintName: assessment.blueprintName,
            warnings: &warnings
          )
        }
      case .buyContractBPC:
        var remaining = requiredRuns
        var totalCost = 0.0
        let candidates = assessment.attributableContractOptions.filter {
          $0.kind == .copy && ($0.runs ?? 0) > 0
        }.sorted {
          if let preferred = sourceOrder(
            .contractBPC(recordID: $0.recordID),
            .contractBPC(recordID: $1.recordID),
            preferredOrder: preferredSourceOrder
          ) {
            return preferred
          }
          let lhs = $0.price / Double(max(1, $0.runs ?? 0))
          let rhs = $1.price / Double(max(1, $1.runs ?? 0))
          if lhs != rhs { return lhs < rhs }
          return $0.recordID < $1.recordID
        }
        for candidate in candidates where remaining > 0 {
          let available = max(0, candidate.runs ?? 0)
          let used = min(remaining, available)
          guard used > 0,
            let me = candidate.materialEfficiency,
            let te = candidate.timeEfficiency
          else { continue }
          totalCost += candidate.price
          let allocation = BlueprintRunAllocation(
            source: .contractBPC(recordID: candidate.recordID),
            provenance: .contractCopy,
            availableRuns: available,
            allocatedRuns: used,
            remainingRuns: available - used,
            materialEfficiency: me,
            timeEfficiency: te,
            locationID: candidate.locationID,
            locationName: candidate.locationName,
            sourceState: .fresh,
            acquisitionCost: candidate.price
          )
          jobs.append(makeJob(allocation: allocation, runs: used))
          appendTransferIfNeeded(
            allocation: allocation,
            assessment: assessment,
            transfers: &transfers,
            warnings: &warnings
          )
          remaining -= used
        }
        batchAllocationCost = totalCost.isFinite ? totalCost : nil
        appendShortfallWarning(
          remainingRuns: remaining,
          blueprintName: assessment.blueprintName,
          warnings: &warnings
        )
      case .buyContractBPO:
        if let candidate = assessment.attributableContractOptions.filter({
          $0.kind == .original
        }).min(by: {
          if let preferred = sourceOrder(
            .contractBPO(recordID: $0.recordID),
            .contractBPO(recordID: $1.recordID),
            preferredOrder: preferredSourceOrder
          ) {
            return preferred
          }
          if $0.price != $1.price { return $0.price < $1.price }
          return $0.recordID < $1.recordID
        }) {
          capitalPurchaseCost = candidate.price
          let allocation = BlueprintRunAllocation(
            source: .contractBPO(recordID: candidate.recordID),
            provenance:
              firstNode.sourceTechLevel == 2
              ? .legacyT2Original : .researchedOriginal,
            availableRuns: nil,
            allocatedRuns: requiredRuns,
            remainingRuns: nil,
            materialEfficiency: candidate.materialEfficiency ?? preferred?.materialEfficiency ?? 0,
            timeEfficiency: candidate.timeEfficiency ?? preferred?.timeEfficiency ?? 0,
            locationID: candidate.locationID,
            locationName: candidate.locationName,
            sourceState: .fresh
          )
          jobs.append(makeJob(allocation: allocation, runs: requiredRuns))
          appendTransferIfNeeded(
            allocation: allocation,
            assessment: assessment,
            transfers: &transfers,
            warnings: &warnings
          )
        }
      case .buyMarketBPO:
        if let candidate = assessment.marketBPOOptions.sorted(by: {
          if let preferred = sourceOrder(
            .marketBPO(orderID: $0.orderID),
            .marketBPO(orderID: $1.orderID),
            preferredOrder: preferredSourceOrder
          ) {
            return preferred
          }
          if $0.price != $1.price { return $0.price < $1.price }
          return $0.orderID < $1.orderID
        }).first {
          capitalPurchaseCost = candidate.price
          let allocation = BlueprintRunAllocation(
            source: .marketBPO(orderID: candidate.orderID),
            provenance: .marketOriginal,
            availableRuns: nil,
            allocatedRuns: requiredRuns,
            remainingRuns: nil,
            materialEfficiency: preferred?.materialEfficiency ?? 0,
            timeEfficiency: preferred?.timeEfficiency ?? 0,
            locationID: candidate.locationID,
            locationName: nil,
            sourceState: candidate.sourceState,
            sourceSnapshotID: candidate.sourceSnapshotID
          )
          jobs.append(makeJob(allocation: allocation, runs: requiredRuns))
          appendTransferIfNeeded(
            allocation: allocation,
            assessment: assessment,
            transfers: &transfers,
            warnings: &warnings
          )
        } else {
          appendShortfallWarning(
            remainingRuns: requiredRuns,
            blueprintName: assessment.blueprintName,
            warnings: &warnings
          )
        }
      case .buyLoyaltyStoreBPC, .manualExternalBPC:
        let source: BlueprintSourceReference =
          action == .buyLoyaltyStoreBPC
          ? .loyaltyStoreBPC(typeID: blueprintTypeID)
          : .manualExternalBPC(id: demandID.requestID)
        let allocation = BlueprintRunAllocation(
          source: source,
          provenance:
            action == .buyLoyaltyStoreBPC
            ? .loyaltyStoreCopy : .manualPlanningAssumption,
          availableRuns: requiredRuns,
          allocatedRuns: requiredRuns,
          remainingRuns: 0,
          materialEfficiency: preferred?.materialEfficiency ?? firstNode.materialEfficiency ?? 0,
          timeEfficiency: preferred?.timeEfficiency ?? firstNode.timeEfficiency ?? 0,
          sourceState: .unavailable,
          acquisitionCost: batchAllocationCost
        )
        jobs.append(makeJob(allocation: allocation, runs: requiredRuns))
      case .copyOwnedBPO, .invent:
        warnings.append(
          DomainWarning(
            code: "industry.blueprint-science-plan-required",
            message:
              "Copying and invention require a concrete Science job and cannot be represented by a manual activity amount.",
            severity: .blocking
          )
        )
      case .useOwnedReactionFormula:
        continue
      case .unavailable, .unresolved:
        appendShortfallWarning(
          remainingRuns: requiredRuns,
          blueprintName: assessment.blueprintName,
          warnings: &warnings
        )
      }
      let snapshotIDs = Array(
        Set(jobs.compactMap { $0.allocation.sourceSnapshotID })
      ).sorted { $0.uuidString < $1.uuidString }
      result[blueprintTypeID] = BlueprintSupplyPlan(
        planID: planID,
        blueprintTypeID: blueprintTypeID,
        productTypeID: firstNode.typeID,
        productName: firstNode.name,
        requiredRuns: requiredRuns,
        manufacturingJobs: jobs,
        transfers: transfers,
        reservations: reservations,
        capitalPurchaseCost: capitalPurchaseCost,
        batchAllocationCost: batchAllocationCost,
        warnings: warnings,
        sourceSnapshotIDs: snapshotIDs
      )
    }
    return result
  }

  private static func ownedOrder(
    _ lhs: ProductionTreeOwnedBlueprintInstanceOption,
    _ rhs: ProductionTreeOwnedBlueprintInstanceOption,
    preferred: IndustryProductionEfficiency?,
    preferredLocationItemIDs: Set<Int64> = []
  ) -> Bool {
    let lhsPreferredLocation = preferredLocationItemIDs.contains(lhs.itemID)
    let rhsPreferredLocation = preferredLocationItemIDs.contains(rhs.itemID)
    if lhsPreferredLocation != rhsPreferredLocation {
      return lhsPreferredLocation
    }
    let lhsPreferred =
      preferred.map {
        lhs.materialEfficiency == $0.materialEfficiency
          && lhs.timeEfficiency == $0.timeEfficiency
      } ?? false
    let rhsPreferred =
      preferred.map {
        rhs.materialEfficiency == $0.materialEfficiency
          && rhs.timeEfficiency == $0.timeEfficiency
      } ?? false
    if lhsPreferred != rhsPreferred { return lhsPreferred }
    if lhs.sourceState != rhs.sourceState {
      return freshnessRank(lhs.sourceState) > freshnessRank(rhs.sourceState)
    }
    if lhs.materialEfficiency != rhs.materialEfficiency {
      return lhs.materialEfficiency > rhs.materialEfficiency
    }
    if lhs.timeEfficiency != rhs.timeEfficiency {
      return lhs.timeEfficiency > rhs.timeEfficiency
    }
    if lhs.runs != rhs.runs {
      return (lhs.runs ?? Int.max) > (rhs.runs ?? Int.max)
    }
    return lhs.itemID < rhs.itemID
  }

  /// `nil` leaves factual quality/price ordering in control when neither
  /// candidate has an explicit position.
  private static func sourceOrder(
    _ lhs: BlueprintSourceReference,
    _ rhs: BlueprintSourceReference,
    preferredOrder: [String: Int]
  ) -> Bool? {
    let lhsIndex = preferredOrder[lhs.stableID]
    let rhsIndex = preferredOrder[rhs.stableID]
    switch (lhsIndex, rhsIndex) {
    case (.some(let lhs), .some(let rhs)): return lhs < rhs
    case (.some, .none): return true
    case (.none, .some): return false
    case (.none, .none): return nil
    }
  }

  private static func freshnessRank(_ state: DataFreshness) -> Int {
    switch state {
    case .fresh: 5
    case .partial: 4
    case .stale: 3
    case .forbidden: 2
    case .unavailable: 1
    }
  }

  private static func appendShortfallWarning(
    remainingRuns: Int,
    blueprintName: String,
    warnings: inout [DomainWarning]
  ) {
    guard remainingRuns > 0 else { return }
    warnings.append(
      DomainWarning(
        code: "industry.blueprint-supply-insufficient-runs",
        message: IndustryWarningText.blueprintRunsShort(
          blueprintName: blueprintName,
          missingRuns: remainingRuns
        ),
        severity: .blocking
      )
    )
  }

  private static func saturatedMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    return result.overflow ? Int64.max : max(0, result.partialValue)
  }

  private static func validCost(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func appendTransferIfNeeded(
    allocation: BlueprintRunAllocation,
    assessment: ProductionTreeBlueprintAssessment,
    transfers: inout [BlueprintTransferRequirement],
    warnings: inout [DomainWarning]
  ) {
    if let originID = allocation.locationID,
      assessment.productionLocationIDs.contains(originID)
    {
      return
    }
    let transfer = BlueprintTransferRequirement(
      source: allocation.source,
      originLocationID: allocation.locationID,
      originName: allocation.locationName,
      destinationLocationID:
        assessment.productionLocationIDs.count == 1
        ? assessment.productionLocationIDs[0] : nil,
      destinationName:
        assessment.productionLocationNames.count == 1
        ? assessment.productionLocationNames[0] : nil
    )
    transfers.append(transfer)
    if !transfer.isResolved {
      warnings.append(
        DomainWarning(
          code: "industry.blueprint-transfer-location-unresolved",
          message:
            "The selected Blueprint is outside the production facility, but its source or destination location is unresolved.",
          severity: .blocking
        )
      )
    }
  }

  private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    return result.overflow ? Int.max : result.partialValue
  }
}

public struct ManufacturingProductionTreeNode: Identifiable, Sendable {
  public let id: UUID
  public let typeID: Int64
  public let name: String
  public let requestedQuantity: Int64
  public let producedQuantity: Int64
  public let action: PlanAction
  public let activity: BlueprintActivityDefinition.Kind?
  public let runs: Int?
  public let materialEfficiency: Int?
  public let timeEfficiency: Int?
  public let facilityName: String?
  public let sourceCategory: String?
  public let sourceGroup: String?
  public let sourceTechLevel: Int?
  public let children: [UUID]
  public let canBuild: Bool
  public let selectedSupplyMode: MaterialSupplyMode
  public let recommendation: MakeOrBuyRecommendation?
  public let recommendationSavings: Double?
  public let totalRequiredQuantity: Int64
  public let factualWarehouseQuantity: Int64?
  public let protectedWarehouseQuantity: Int64?
  public let reservedWarehouseQuantity: Int64?
  public let usableWarehouseQuantity: Int64?
  public let stockCoverage: ProductionTreeStockCoverage
  public let blueprint: ProductionTreeBlueprintAssessment?
}

public struct ManufacturingProductionTreeSnapshot: Sendable {
  public let id: UUID
  public let createdAt: Date
  public let targetQuantity: Int64
  public let mainHub: ProcurementLocation
  public let referencePlan: IndustryPlanSnapshot
  public let selectedPlan: IndustryPlanSnapshot
  public let rootIDs: [UUID]
  public let nodes: [ManufacturingProductionTreeNode]
  public let warnings: [DomainWarning]

  public init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    targetQuantity: Int64,
    mainHub: ProcurementLocation,
    referencePlan: IndustryPlanSnapshot,
    selectedPlan: IndustryPlanSnapshot,
    rootIDs: [UUID],
    nodes: [ManufacturingProductionTreeNode],
    warnings: [DomainWarning]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.targetQuantity = targetQuantity
    self.mainHub = mainHub
    self.referencePlan = referencePlan
    self.selectedPlan = selectedPlan
    self.rootIDs = rootIDs
    self.nodes = nodes
    self.warnings = warnings
  }

  public var nodesByID: [UUID: ManufacturingProductionTreeNode] {
    Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
  }
}

public enum ManufacturingProductionTreeProjector {
  public static func project(
    targetQuantity: Int64,
    mainHub: ProcurementLocation,
    referencePlan: IndustryPlanSnapshot,
    selectedPlan: IndustryPlanSnapshot,
    warehouse: AssetWarehouse,
    warehouseHasSnapshot: Bool,
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64],
    preferences: [Int64: MaterialProcurementPreference],
    blueprintPortfolio: BlueprintPortfolio,
    blueprintNames: [Int64: String],
    blueprintContractOffers: [Int64: [PublicContractSearchResult]],
    blueprintMarketOrders: [Int64: [MarketOrder]] = [:],
    blueprintMarketSource: SourceIdentity? = nil,
    blueprintMarketState: DataFreshness = .unavailable,
    publicContractCoverageComplete: Bool,
    loyaltyStoreBlueprintTypeIDs: Set<Int64> = [],
    inventionDefinitions: [Int64: BlueprintDefinition],
    productionScope: ProductionWarehouseScope
  ) -> ManufacturingProductionTreeSnapshot {
    let referencedChildren = Set(referencePlan.nodes.flatMap(\.children))
    let rootIDs = referencePlan.nodes.filter {
      !referencedChildren.contains($0.id) && $0.action == .produce
    }.map(\.id)
    let materials = Dictionary(
      uniqueKeysWithValues: referencePlan.materials.map { ($0.typeID, $0) }
    )
    let rootSet = Set(rootIDs)
    let factual = warehouse.factualQuantities
    let inventoryComplete =
      !blueprintPortfolio.sourceStates.isEmpty
      && blueprintPortfolio.sourceStates.allSatisfy { $0 == .fresh }
    let requiredRunsByBlueprintTypeID = referencePlan.nodes.reduce(
      into: [Int64: Int]()
    ) { result, node in
      guard node.action == .produce, let blueprintTypeID = node.blueprintTypeID
      else { return }
      result[blueprintTypeID] = saturatedAdd(
        result[blueprintTypeID, default: 0],
        max(0, node.runs ?? 0)
      )
    }
    let nodes = referencePlan.nodes.map { node in
      let material = materials[node.typeID]
      let totalRequired = max(
        0,
        material?.required
          ?? node.requestedQuantity
          ?? node.requiredQuantity
      )
      let stock = stockState(
        typeID: node.typeID,
        requiredQuantity: totalRequired,
        warehouseHasSnapshot: warehouseHasSnapshot,
        factualQuantities: factual,
        protectedQuantities: protectedQuantities,
        reservedQuantities: reservedQuantities
      )
      let analysis = material?.makeOrBuyAnalysis
      let canBuild = node.activity != nil
      // A requested end product is always built: the planner never buys a
      // top-level request, so a market-type purchase preference for the same
      // type must not hide its Blueprint step and cost.
      let isRequestedRoot =
        rootSet.contains(node.id) && node.topLevelRequestID != nil
      let selectedMode: MaterialSupplyMode =
        isRequestedRoot && canBuild
        ? .produce
        : preferences[node.typeID]?.supplyMode
        ?? defaultSupplyMode(
          canBuild: canBuild,
          recommendation: analysis?.recommendation,
          action: node.action
        )
      let blueprint = node.blueprintTypeID.map { blueprintTypeID in
        blueprintAssessment(
          blueprintTypeID: blueprintTypeID,
          blueprintName:
            blueprintNames[blueprintTypeID]
            ?? "Blueprint type \(blueprintTypeID)",
          requiredRuns:
            requiredRunsByBlueprintTypeID[blueprintTypeID]
            ?? max(0, node.runs ?? 0),
          activity: node.activity,
          facilityName: node.facilityName,
          portfolio: blueprintPortfolio,
          warehouse: warehouse,
          warehouseHasSnapshot: warehouseHasSnapshot,
          inventoryComplete: inventoryComplete,
          contracts: blueprintContractOffers[blueprintTypeID] ?? [],
          marketOrders: blueprintMarketOrders[blueprintTypeID] ?? [],
          marketSource: blueprintMarketSource,
          marketState: blueprintMarketState,
          publicContractCoverageComplete: publicContractCoverageComplete,
          hasLoyaltyStoreOffer:
            loyaltyStoreBlueprintTypeIDs.contains(blueprintTypeID),
          inventionDefinition: inventionDefinitions[blueprintTypeID],
          productionScope: productionScope,
          mainHub: mainHub
        )
      }
      return ManufacturingProductionTreeNode(
        id: node.id,
        typeID: node.typeID,
        name: node.name,
        requestedQuantity:
          node.requestedQuantity ?? node.requiredQuantity,
        producedQuantity: node.requiredQuantity,
        action: node.action,
        activity: node.activity,
        runs: node.runs,
        materialEfficiency: node.materialEfficiency,
        timeEfficiency: node.timeEfficiency,
        facilityName: node.facilityName,
        sourceCategory: node.sourceCategory,
        sourceGroup: node.sourceGroup,
        sourceTechLevel: node.sourceTechLevel,
        children: node.children,
        canBuild: canBuild,
        selectedSupplyMode: selectedMode,
        recommendation: analysis?.recommendation,
        recommendationSavings: analysis?.savings,
        totalRequiredQuantity: totalRequired,
        factualWarehouseQuantity: stock.factual,
        protectedWarehouseQuantity: stock.protected,
        reservedWarehouseQuantity: stock.reserved,
        usableWarehouseQuantity: stock.usable,
        stockCoverage: stock.coverage,
        blueprint: blueprint
      )
    }
    var warnings = referencePlan.warnings + selectedPlan.warnings
    if blueprintContractOffers.values.joined().contains(where: {
      $0.price != nil || $0.buyout != nil
    }) {
      warnings.append(
        DomainWarning(
          code: "production-tree.blueprint-contract-bundle-price",
          message:
            "Blueprint contract prices are whole-contract prices and are not allocated per blueprint or per run.",
          severity: .information
        )
      )
    }
    if !publicContractCoverageComplete {
      warnings.append(
        DomainWarning(
          code: "production-tree.public-contract-coverage-incomplete",
          message:
            "The public Contract index is incomplete, stale, or unavailable. Missing blueprint offers therefore remain unresolved rather than being treated as absent.",
          severity: .warning
        )
      )
    }
    return ManufacturingProductionTreeSnapshot(
      targetQuantity: targetQuantity,
      mainHub: mainHub,
      referencePlan: referencePlan,
      selectedPlan: selectedPlan,
      rootIDs: rootIDs,
      nodes: nodes,
      warnings: deduplicated(warnings)
    )
  }

  private static func defaultSupplyMode(
    canBuild: Bool,
    recommendation: MakeOrBuyRecommendation?,
    action: PlanAction
  ) -> MaterialSupplyMode {
    guard canBuild else { return .buy }
    switch recommendation {
    case .produce: return .produce
    case .buy: return .buy
    case .unavailable, nil:
      return action == .produce ? .produce : .buy
    }
  }

  private static func stockState(
    typeID: Int64,
    requiredQuantity: Int64,
    warehouseHasSnapshot: Bool,
    factualQuantities: [Int64: Int64],
    protectedQuantities: [Int64: Int64],
    reservedQuantities: [Int64: Int64]
  ) -> (
    factual: Int64?, protected: Int64?, reserved: Int64?, usable: Int64?,
    coverage: ProductionTreeStockCoverage
  ) {
    guard warehouseHasSnapshot else {
      return (nil, nil, nil, nil, .unavailable)
    }
    let factual = max(0, factualQuantities[typeID, default: 0])
    let protected = max(0, protectedQuantities[typeID, default: 0])
    let reserved = max(0, reservedQuantities[typeID, default: 0])
    let unavailable = saturatedAdd(protected, reserved)
    let usable = max(0, factual - min(factual, unavailable))
    let coverage: ProductionTreeStockCoverage
    if requiredQuantity <= 0 || usable >= requiredQuantity {
      coverage = .full
    } else if usable > 0 {
      coverage = .partial
    } else {
      coverage = .none
    }
    return (factual, protected, reserved, usable, coverage)
  }

  private static func blueprintAssessment(
    blueprintTypeID: Int64,
    blueprintName: String,
    requiredRuns: Int,
    activity: BlueprintActivityDefinition.Kind?,
    facilityName: String?,
    portfolio: BlueprintPortfolio,
    warehouse: AssetWarehouse,
    warehouseHasSnapshot: Bool,
    inventoryComplete: Bool,
    contracts: [PublicContractSearchResult],
    marketOrders: [MarketOrder],
    marketSource: SourceIdentity?,
    marketState: DataFreshness,
    publicContractCoverageComplete: Bool,
    hasLoyaltyStoreOffer: Bool,
    inventionDefinition: BlueprintDefinition?,
    productionScope: ProductionWarehouseScope,
    mainHub: ProcurementLocation
  ) -> ProductionTreeBlueprintAssessment {
    let productionActivity: IndustryActivitySystem? =
      switch activity {
      case .copying: .copying
      case .manufacturing: .manufacturing
      case .reaction: .reaction
      case .invention: .invention
      case .materialResearch: .materialResearch
      case .timeResearch: .timeResearch
      case nil: nil
      }
    let activityLocations = productionScope.locations.filter {
      productionActivity.map($0.activities.contains) ?? false
    }
    let matchingLocations = activityLocations.filter {
      guard let facilityName else { return false }
      return $0.structureName.compare(
        facilityName,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) == .orderedSame
    }
    let productionLocations: [ProductionWarehouseLocation]
    if matchingLocations.count == 1 {
      productionLocations = matchingLocations
    } else if activityLocations.count == 1 {
      productionLocations = activityLocations
    } else {
      productionLocations = []
    }
    let productionLocationIDs = Set(productionLocations.map(\.locationID))
    let copyingLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.copying)
      }.map(\.locationID)
    )
    let inventionLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.invention)
      }.map(\.locationID)
    )
    let researchLocationIDs = Set(
      productionScope.locations.filter {
        $0.activities.contains(.materialResearch)
          || $0.activities.contains(.timeResearch)
      }.map(\.locationID)
    )
    let entries = portfolio.entries.filter {
      $0.instance.blueprintTypeID == blueprintTypeID
    }
    // A retained stale value or a partial snapshot is still factual evidence
    // for a concrete owned instance. It may be offered with an explicit
    // freshness warning, but it must not make the complete-inventory claim.
    let usableOwnedStates: Set<DataFreshness> = [.fresh, .partial, .stale]
    let selectableEntries = entries.filter {
      usableOwnedStates.contains($0.sourceState)
    }
    let rootLocationByItemID = warehouse.rootLocationsByItemID()
    func locationID(for entry: BlueprintPortfolioEntry) -> Int64 {
      rootLocationByItemID[entry.instance.id]?.id
        ?? entry.instance.locationID
    }
    let exactBPC = selectableEntries.filter {
      $0.instance.kind == .copy
        && productionLocationIDs.contains(locationID(for: $0))
        && $0.instance.runs > 0
    }
    let exactBPO = selectableEntries.filter {
      $0.instance.kind == .original
        && productionLocationIDs.contains(locationID(for: $0))
    }
    let copyingBPO = selectableEntries.filter {
      $0.instance.kind == .original
        && copyingLocationIDs.contains(locationID(for: $0))
    }
    let researchBPC = selectableEntries.filter {
      $0.instance.kind == .copy
        && researchLocationIDs.contains(locationID(for: $0))
    }
    let researchBPO = selectableEntries.filter {
      $0.instance.kind == .original
        && researchLocationIDs.contains(locationID(for: $0))
    }
    let knownItemIDs = Set(entries.map { $0.instance.id })
    let exactUnknownCount = warehouse.locations
      .filter { productionLocationIDs.contains($0.id) }
      .flatMap(\.owners).flatMap(\.items)
      .filter {
        $0.typeID == blueprintTypeID && !knownItemIDs.contains($0.id)
      }.count
    let inventionSources: [BlueprintPortfolioEntry]
    if let sourceTypeID = inventionDefinition?.blueprintTypeID {
      inventionSources = portfolio.entries.filter {
        $0.instance.blueprintTypeID == sourceTypeID
          && usableOwnedStates.contains($0.sourceState)
          && inventionLocationIDs.contains(locationID(for: $0))
          && ($0.instance.kind == .original
            || $0.instance.kind == .copy && $0.instance.runs > 0)
      }
    } else {
      inventionSources = []
    }
    let exactContracts = contracts.filter {
      $0.typeID == blueprintTypeID && $0.isIncluded
        && $0.startLocationID == mainHub.locationID
    }
    let attributableContracts = exactContracts.filter(
      \.isAttributableBlueprintOffer
    )
    let attributableBPCs = attributableContracts.filter {
      $0.isBlueprintCopy == true && ($0.runs ?? 0) > 0
    }
    let attributableBPOs = attributableContracts.filter { $0.runs == -1 }
    let exactBPCRuns = exactBPC.reduce(0) {
      saturatedAdd($0, max(0, $1.instance.runs))
    }
    let ownedEfficiencyOptions = ownedBlueprintEfficiencyOptions(
      bpcs: exactBPC,
      bpos: exactBPO
    )
    func ownedInstanceOption(
      _ entry: BlueprintPortfolioEntry
    ) -> ProductionTreeOwnedBlueprintInstanceOption {
      let resolvedLocationID = locationID(for: entry)
      return ProductionTreeOwnedBlueprintInstanceOption(
        itemID: entry.instance.id,
        kind: entry.instance.kind,
        runs:
          entry.instance.kind == .copy
          ? max(0, entry.instance.runs) : nil,
        materialEfficiency: entry.instance.materialEfficiency,
        timeEfficiency: entry.instance.timeEfficiency,
        ownerID: entry.ownerID,
        ownerName: entry.ownerName,
        locationID: resolvedLocationID,
        locationName: productionScope.locations.first {
          $0.locationID == resolvedLocationID
        }?.structureName
          ?? warehouse.locations.first {
            $0.id == resolvedLocationID
          }?.resolvedName,
        sourceState: entry.sourceState,
        sourceSnapshotID: entry.instance.source.snapshotID
      )
    }
    let ownedInstanceOptions = (exactBPC + exactBPO).map(
      ownedInstanceOption
    ).sorted {
      if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
      if $0.materialEfficiency != $1.materialEfficiency {
        return $0.materialEfficiency > $1.materialEfficiency
      }
      if $0.timeEfficiency != $1.timeEfficiency {
        return $0.timeEfficiency > $1.timeEfficiency
      }
      return $0.itemID < $1.itemID
    }
    let sortedOwnedBPCs = exactBPC.sorted {
      if $0.instance.materialEfficiency != $1.instance.materialEfficiency {
        return $0.instance.materialEfficiency > $1.instance.materialEfficiency
      }
      if $0.instance.timeEfficiency != $1.instance.timeEfficiency {
        return $0.instance.timeEfficiency > $1.instance.timeEfficiency
      }
      if $0.instance.runs != $1.instance.runs {
        return $0.instance.runs > $1.instance.runs
      }
      return $0.instance.id < $1.instance.id
    }
    var ownedCoveredRuns = 0
    var ownedRequiredCount = 0
    for entry in sortedOwnedBPCs where ownedCoveredRuns < requiredRuns {
      ownedCoveredRuns = saturatedAdd(
        ownedCoveredRuns,
        max(0, entry.instance.runs)
      )
      ownedRequiredCount += 1
    }
    // Mixed and equal BPC qualities may cover one demand together, but every
    // concrete copy remains a separate job with its own ME/TE and rounding.
    let ownedBPCCoversRuns = requiredRuns == 0 || exactBPCRuns >= requiredRuns
    let contractSelection = ProductionTreeBPCContractSelector.select(
      requiredRuns: requiredRuns,
      from: attributableBPCs
    )
    let cheapestBPO = attributableBPOs.min {
      ($0.effectiveContractPrice ?? .greatestFiniteMagnitude)
        < ($1.effectiveContractPrice ?? .greatestFiniteMagnitude)
    }
    let marketBPOOptions: [ProductionTreeMarketBPOOption] =
      marketOrders
      .filter {
        $0.side == .sell
          && $0.locationID == mainHub.locationID
          && $0.price.isFinite && $0.price > 0
          && $0.volumeRemaining > 0
          && $0.minimumVolume <= 1
      }.compactMap {
        guard let marketSource else { return nil }
        return ProductionTreeMarketBPOOption(
          orderID: $0.id,
          price: $0.price,
          locationID: $0.locationID,
          sourceState: marketState,
          sourceSnapshotID: marketSource.snapshotID
        )
      }.sorted {
        if $0.price != $1.price { return $0.price < $1.price }
        return $0.orderID < $1.orderID
      }
    let otherLocationEntries = selectableEntries.filter {
      !productionLocationIDs.contains(locationID(for: $0))
    }
    let otherLocationInstanceOptions = otherLocationEntries.map(
      ownedInstanceOption
    ).sorted {
      if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
      if $0.materialEfficiency != $1.materialEfficiency {
        return $0.materialEfficiency > $1.materialEfficiency
      }
      if $0.timeEfficiency != $1.timeEfficiency {
        return $0.timeEfficiency > $1.timeEfficiency
      }
      return $0.itemID < $1.itemID
    }
    let allOwnedBPCRuns = saturatedAdd(
      exactBPCRuns,
      otherLocationEntries.filter {
        $0.instance.kind == .copy && $0.instance.runs > 0
      }.reduce(0) { saturatedAdd($0, $1.instance.runs) }
    )
    let allOwnedBPCCoversRuns = requiredRuns == 0 || allOwnedBPCRuns >= requiredRuns
    let hasAnyOwnedBPO =
      !exactBPO.isEmpty
      || otherLocationEntries.contains {
        $0.instance.kind == .original
      }
    var actions: Set<ProductionTreeBlueprintAction> = []
    if allOwnedBPCCoversRuns && allOwnedBPCRuns > 0 {
      actions.insert(.useOwnedBPC)
    }
    if hasAnyOwnedBPO { actions.insert(.useOwnedBPO) }
    if contractSelection != nil { actions.insert(.buyContractBPC) }
    if cheapestBPO != nil { actions.insert(.buyContractBPO) }
    if !marketBPOOptions.isEmpty { actions.insert(.buyMarketBPO) }
    if hasLoyaltyStoreOffer { actions.insert(.buyLoyaltyStoreBPC) }
    if activity == .manufacturing { actions.insert(.manualExternalBPC) }
    let recommendation: ProductionTreeBlueprintAction
    if ownedBPCCoversRuns && !exactBPC.isEmpty {
      recommendation = .useOwnedBPC
    } else if !exactBPO.isEmpty {
      recommendation = .useOwnedBPO
    } else if allOwnedBPCCoversRuns && allOwnedBPCRuns > 0 {
      recommendation = .useOwnedBPC
    } else if hasAnyOwnedBPO {
      recommendation = .useOwnedBPO
    } else if contractSelection != nil {
      recommendation = .buyContractBPC
    } else if cheapestBPO != nil {
      recommendation = .buyContractBPO
    } else if !marketBPOOptions.isEmpty {
      recommendation = .buyMarketBPO
    } else if hasLoyaltyStoreOffer {
      recommendation = .buyLoyaltyStoreBPC
    } else if activity == .manufacturing {
      recommendation = .manualExternalBPC
    } else {
      recommendation =
        inventoryComplete && warehouseHasSnapshot
          && publicContractCoverageComplete
        ? .unavailable : .unresolved
      actions.insert(recommendation)
    }
    return ProductionTreeBlueprintAssessment(
      blueprintTypeID: blueprintTypeID,
      blueprintName: blueprintName,
      requiredRuns: requiredRuns,
      recommendation: recommendation,
      availableActions: actions,
      productionLocationIDs: productionLocations.map(\.locationID),
      productionLocationNames: productionLocations.map(\.structureName),
      exactLocationBPCRuns: exactBPCRuns,
      exactLocationBPCRequiredCount:
        ownedBPCCoversRuns && !exactBPC.isEmpty
        ? ownedRequiredCount : nil,
      exactLocationBPCOwnerNames: Array(Set(exactBPC.map(\.ownerName))).sorted(),
      exactLocationBPOOwnerNames: Array(Set(exactBPO.map(\.ownerName))).sorted(),
      exactLocationBPCSourceStates: Array(Set(exactBPC.map(\.sourceState)))
        .sorted { $0.rawValue < $1.rawValue },
      exactLocationBPOSourceStates: Array(Set(exactBPO.map(\.sourceState)))
        .sorted { $0.rawValue < $1.rawValue },
      exactLocationBPCCount: exactBPC.count,
      exactLocationBPOCount: exactBPO.count,
      exactLocationEfficiencyOptions: ownedEfficiencyOptions,
      exactLocationInstanceOptions: ownedInstanceOptions,
      otherLocationInstanceOptions: otherLocationInstanceOptions,
      copyingLocationBPOCount: copyingBPO.count,
      inventionSourceCount: inventionSources.count,
      researchLocationBPCCount: researchBPC.count,
      researchLocationBPOCount: researchBPO.count,
      exactLocationUnknownCount: exactUnknownCount,
      otherLocationCount: otherLocationEntries.count,
      otherLocationBPCCount: otherLocationEntries.filter {
        $0.instance.kind == .copy
      }.count,
      otherLocationBPOCount: otherLocationEntries.filter {
        $0.instance.kind == .original
      }.count,
      indexedContractOfferCount: exactContracts.count,
      attributableBPCContractCount: attributableBPCs.count,
      attributableBPOContractCount: attributableBPOs.count,
      attributableContractOptions: attributableContracts.compactMap {
        offer in
        guard let price = offer.effectiveContractPrice,
          let locationID = offer.startLocationID
        else { return nil }
        let kind: BlueprintCopyKind =
          offer.isBlueprintCopy == true || (offer.runs ?? 0) >= 0
          ? .copy : .original
        return ProductionTreeContractBlueprintOption(
          recordID: offer.recordID,
          contractID: offer.contractID,
          kind: kind,
          runs: kind == .copy ? offer.runs : nil,
          materialEfficiency: offer.materialEfficiency,
          timeEfficiency: offer.timeEfficiency,
          price: price,
          locationID: locationID,
          locationName: offer.startLocationName ?? mainHub.name
        )
      }.sorted {
        if $0.price != $1.price { return $0.price < $1.price }
        return $0.recordID < $1.recordID
      },
      marketBPOOptions: marketBPOOptions,
      attributableBPCContractSelectionCount:
        contractSelection?.contractCount ?? 0,
      attributableBPCContractRuns: contractSelection?.coveredRuns,
      attributableBPCContractME: commonValue(
        contractSelection?.offers.compactMap(\.materialEfficiency) ?? []
      ),
      attributableBPCContractTE: commonValue(
        contractSelection?.offers.compactMap(\.timeEfficiency) ?? []
      ),
      attributableBPCContractPrice: contractSelection?.totalPrice,
      attributableBPOContractPrice: cheapestBPO?.effectiveContractPrice,
      lowestWholeContractPrice: exactContracts.compactMap {
        $0.price ?? $0.buyout
      }.filter { $0.isFinite && $0 > 0 }.min(),
      inventoryIsComplete: inventoryComplete && warehouseHasSnapshot
    )
  }

  private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : sum
  }

  private struct OwnedEfficiencyKey: Hashable {
    let kind: BlueprintCopyKind
    let materialEfficiency: Int
    let timeEfficiency: Int
  }

  private static func ownedBlueprintEfficiencyOptions(
    bpcs: [BlueprintPortfolioEntry],
    bpos: [BlueprintPortfolioEntry]
  ) -> [ProductionTreeOwnedBlueprintEfficiencyOption] {
    let grouped = Dictionary(grouping: bpcs + bpos) {
      OwnedEfficiencyKey(
        kind: $0.instance.kind,
        materialEfficiency: $0.instance.materialEfficiency,
        timeEfficiency: $0.instance.timeEfficiency
      )
    }
    let options: [ProductionTreeOwnedBlueprintEfficiencyOption] = grouped.map {
      key, entries in
      ProductionTreeOwnedBlueprintEfficiencyOption(
        kind: key.kind,
        materialEfficiency: key.materialEfficiency,
        timeEfficiency: key.timeEfficiency,
        availableRuns:
          key.kind == .copy
          ? entries.reduce(0) {
            saturatedAdd($0, max(0, $1.instance.runs))
          } : nil,
        instanceCount: entries.count,
        ownerNames: Array(Set(entries.map(\.ownerName))).sorted(),
        sourceStates: Array(Set(entries.map(\.sourceState))).sorted {
          $0.rawValue < $1.rawValue
        }
      )
    }
    return options.sorted {
      if $0.kind != $1.kind {
        return $0.kind.rawValue < $1.kind.rawValue
      }
      if $0.materialEfficiency != $1.materialEfficiency {
        return $0.materialEfficiency > $1.materialEfficiency
      }
      if $0.timeEfficiency != $1.timeEfficiency {
        return $0.timeEfficiency > $1.timeEfficiency
      }
      let leftID = $0.id
      let rightID = $1.id
      return leftID < rightID
    }
  }

  private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
  }

  private static func commonValue<T: Equatable>(_ values: [T]) -> T? {
    guard let first = values.first, values.allSatisfy({ $0 == first }) else {
      return nil
    }
    return first
  }

  private static func deduplicated(
    _ warnings: [DomainWarning]
  ) -> [DomainWarning] {
    var seen = Set<String>()
    return warnings.filter {
      seen.insert($0.code + "|" + $0.message).inserted
    }
  }
}
