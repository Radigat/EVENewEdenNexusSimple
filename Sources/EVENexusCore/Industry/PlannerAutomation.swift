import Foundation

/// The owner's manual choices in the Planner draft. Everything else is decided
/// anew by each calculation (owner decision 30.10.2026).
public struct PlannerManualDecisions: Codable, Equatable, Sendable {
  public var procurement: [Int64: MaterialProcurementPreference]
  /// Raw values of `ProductionTreeBlueprintAction` by Blueprint type.
  public var blueprintActions: [Int64: String]
  public var blueprintSources: [Int64: [BlueprintSourceReference]]

  public init(
    procurement: [Int64: MaterialProcurementPreference] = [:],
    blueprintActions: [Int64: String] = [:],
    blueprintSources: [Int64: [BlueprintSourceReference]] = [:]
  ) {
    self.procurement = procurement
    self.blueprintActions = blueprintActions
    self.blueprintSources = blueprintSources
  }

  public var isEmpty: Bool {
    procurement.isEmpty && blueprintActions.isEmpty && blueprintSources.isEmpty
  }

  /// Drops the manual choices; Blueprints handed over from another area or
  /// bound to a science job stay, because they are concrete supplies.
  public func reset(keepingBlueprintTypeIDs kept: Set<Int64>) -> PlannerManualDecisions {
    PlannerManualDecisions(
      blueprintActions: blueprintActions.filter { kept.contains($0.key) },
      blueprintSources: blueprintSources.filter { kept.contains($0.key) }
    )
  }
}

/// Runs one Planner calculation at a time: requests within the debounce window
/// collapse into one run, and a request during a run cancels that run and
/// follows it with the latest wish.
@MainActor
public final class PlannerCalculationScheduler {
  public typealias Run = @MainActor () async -> Void

  private var debounceTask: Task<Void, Never>?
  private var runningTask: Task<Void, Never>?
  private var latestRun: Run?

  public init() {}

  public var isRunning: Bool { runningTask != nil }

  public func request(after delay: Duration? = nil, run: @escaping Run) {
    latestRun = run
    debounceTask?.cancel()
    debounceTask = nil
    guard let delay else {
      startLatest()
      return
    }
    debounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.debounceTask = nil
      self?.startLatest()
    }
  }

  /// Stops the waiting wish and the running calculation without a follow-up.
  public func cancelAll() {
    debounceTask?.cancel()
    debounceTask = nil
    latestRun = nil
    runningTask?.cancel()
  }

  private func startLatest() {
    if let runningTask {
      runningTask.cancel()
      return
    }
    guard let run = latestRun else { return }
    latestRun = nil
    runningTask = Task { @MainActor [weak self] in
      await run()
      self?.runningTask = nil
      self?.startLatest()
    }
  }
}

/// What the Planner's status line says about the visible plan.
public enum PlannerCalculationStatus: Equatable, Sendable {
  case calculating
  case failed
  case noPlan
  /// A saved plan, opened without a calculation in this session.
  case saved
  case current
  case outdated

  public static func resolve(
    isCalculating: Bool,
    hasError: Bool,
    hasPlan: Bool,
    startedThisSession: Bool,
    matchesCompletedCalculation: Bool,
    hasChangesSinceOpening: Bool
  ) -> PlannerCalculationStatus {
    if isCalculating { return .calculating }
    if hasError { return .failed }
    guard hasPlan else { return .noPlan }
    if matchesCompletedCalculation { return .current }
    return startedThisSession || hasChangesSinceOpening ? .outdated : .saved
  }
}

/// The way the plan supplies its materials, in one line.
public struct PlannerRouteSummary: Equatable, Sendable {
  public let builtMaterialCount: Int
  public let boughtMaterialCount: Int
  public let stockMaterialCount: Int
  public let purchaseLocationNames: [String]

  public init(plan: IndustryPlanSnapshot) {
    builtMaterialCount = plan.materials.filter { $0.toProduce > 0 }.count
    boughtMaterialCount = plan.materials.filter { $0.toBuy > 0 }.count
    stockMaterialCount = plan.materials.filter { $0.fromStock > 0 }.count
    purchaseLocationNames = Set(
      plan.materials.flatMap { $0.purchaseAllocations ?? [] }.map(\.location.name)
    ).sorted()
  }
}

/// The step of the fixed Blueprint order that a source belongs to.
public enum BlueprintSourceStage: Int, Equatable, Sendable {
  case ownedBPO = 1
  case ownedBPC
  case contractBPC
  case otherSource
  case reactionFormula
  case none

  public init(action: ProductionTreeBlueprintAction) {
    switch action {
    case .useOwnedBPO, .copyOwnedBPO: self = .ownedBPO
    case .useOwnedBPC, .useOwnedBPCWithContracts: self = .ownedBPC
    case .buyContractBPC: self = .contractBPC
    case .buyContractBPO, .buyMarketBPO, .buyLoyaltyStoreBPC, .manualExternalBPC, .invent:
      self = .otherSource
    case .useOwnedReactionFormula: self = .reactionFormula
    case .unavailable, .unresolved: self = .none
    }
  }
}

/// An owned reaction formula at the Main Hub that travels with the materials
/// to the facility (owner decision 2026-10-31).
public struct PlannerFormulaShipment: Codable, Hashable, Sendable {
  public let blueprintTypeID: Int64
  public let formulaName: String
  public let originName: String
  /// The courier collateral: cheapest NPC price, else ESI average price, else `nil`.
  public let collateral: Double?

  public init(
    blueprintTypeID: Int64,
    formulaName: String,
    originName: String,
    collateral: Double?
  ) {
    self.blueprintTypeID = blueprintTypeID
    self.formulaName = formulaName
    self.originName = originName
    self.collateral = collateral
  }

  /// The chosen formula of one reaction, when it has to leave the Main Hub.
  public static func shipment(
    for assessment: ProductionTreeBlueprintAssessment,
    action: ProductionTreeBlueprintAction,
    preferredSources: [BlueprintSourceReference],
    mainHub: ProcurementLocation
  ) -> PlannerFormulaShipment? {
    guard action == .useOwnedBPO, let hubID = mainHub.locationID,
      !assessment.productionLocationIDs.contains(hubID)
    else { return nil }
    let exact = assessment.exactLocationInstanceOptions.filter { $0.kind == .original }
    let options = exact + assessment.otherLocationInstanceOptions.filter { $0.kind == .original }
    let preferred = preferredSources.lazy.compactMap { source in
      options.first { .ownedBPO(itemID: $0.itemID) == source }
    }.first
    guard (preferred ?? exact.first)?.locationID == hubID else { return nil }
    return PlannerFormulaShipment(
      blueprintTypeID: assessment.blueprintTypeID,
      formulaName: assessment.blueprintName,
      originName: mainHub.name,
      collateral: assessment.marketBPOOptions.first?.price
    )
  }
}

/// A setting without which the Planner cannot calculate.
public enum PlannerSetupIssue: Equatable, Sendable {
  case staticDataMissing
  case mainHubMissing

  public static func issues(
    hasStaticData: Bool,
    basis: ProductionBasis
  ) -> [PlannerSetupIssue] {
    var issues: [PlannerSetupIssue] = []
    if !hasStaticData { issues.append(.staticDataMissing) }
    if basis.mainTradingLocation?.location.kind != .npcTradeHub {
      issues.append(.mainHubMissing)
    }
    return issues
  }
}
