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

// MARK: - Data of one click (ANALYSE_2026-11-02, A3/G1)

/// One load of a Planner click: a key that names exactly what is loaded,
/// and the load itself.
public struct PlannerClickLoad<Value: Sendable>: Sendable {
  public let key: String
  public let load: @Sendable () async throws -> Value

  public init(key: String, load: @escaping @Sendable () async throws -> Value) {
    self.key = key
    self.load = load
  }
}

public enum PlannerClickDataError: Error, Equatable, Sendable {
  case unexpectedValue(key: String)
}

/// Loads each piece of data of one Planner click once, so that all passes
/// of the click see the same market state. A load can start early and is
/// awaited later. A failed or cancelled load is not kept: a later pass of the
/// same click asks again, as every pass did before.
public actor PlannerClickDataCache {
  private var tasks: [String: Task<any Sendable, any Error>] = [:]

  public init() {}

  /// Starts `load` unless the click already started it.
  public func prefetch<Value: Sendable>(_ load: PlannerClickLoad<Value>) {
    guard tasks[load.key] == nil else { return }
    let run = load.load
    tasks[load.key] = Task { try await run() as any Sendable }
  }

  /// The value of `load`, loading it unless the click already did.
  public func value<Value: Sendable>(_ load: PlannerClickLoad<Value>) async throws -> Value {
    prefetch(load)
    guard let task = tasks[load.key] else { throw CancellationError() }
    do {
      let value = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard let typed = value as? Value else {
        throw PlannerClickDataError.unexpectedValue(key: load.key)
      }
      return typed
    } catch {
      if tasks[load.key] == task { tasks[load.key] = nil }
      throw error
    }
  }

  /// Drops a kept value so that the next pass asks again, e.g. for a hub
  /// that was unavailable.
  public func forget(_ key: String) {
    tasks[key] = nil
  }

  /// Stops loads nobody waits for any more; called when the click ends.
  public func cancelAll() {
    for task in tasks.values { task.cancel() }
    tasks = [:]
  }
}

// MARK: - Control flow of one click (ANALYSE_2026-11-02, A3)

/// What the control flow needs from a resolved Blueprint basis.
public protocol PlannerCalculationBasis {
  /// Blueprints with a resolved cost allocation; a reaction outside this set
  /// has no formula source.
  var allocatedBlueprintTypeIDs: Set<Int64> { get }
  /// The plan of the Blueprint tree the basis was resolved for.
  var selectedPlan: IndustryPlanSnapshot { get }
}

/// One Blueprint basis that the click asks for.
public struct PlannerBasisRequest: Equatable, Sendable {
  public let preferences: [Int64: MaterialProcurementPreference]
  public let automaticSupply: Bool
  public let minimumBlueprintRuns: [Int64: Int]
  public let calculatesWithoutStock: Bool

  public init(
    preferences: [Int64: MaterialProcurementPreference],
    automaticSupply: Bool,
    minimumBlueprintRuns: [Int64: Int],
    calculatesWithoutStock: Bool
  ) {
    self.preferences = preferences
    self.automaticSupply = automaticSupply
    self.minimumBlueprintRuns = minimumBlueprintRuns
    self.calculatesWithoutStock = calculatesWithoutStock
  }
}

/// One calculation that the click asks for.
public struct PlannerCalculationRequest<Basis> {
  public let basis: Basis
  public let preferences: [Int64: MaterialProcurementPreference]
  public let automaticSupply: Bool
  public let calculatesWithoutStock: Bool
  /// The total of the calculation without stock; `nil` in that calculation.
  public let stockReferenceProductionCost: Double?

  public init(
    basis: Basis,
    preferences: [Int64: MaterialProcurementPreference],
    automaticSupply: Bool,
    calculatesWithoutStock: Bool,
    stockReferenceProductionCost: Double?
  ) {
    self.basis = basis
    self.preferences = preferences
    self.automaticSupply = automaticSupply
    self.calculatesWithoutStock = calculatesWithoutStock
    self.stockReferenceProductionCost = stockReferenceProductionCost
  }
}

/// Result of one calculation step.
public struct PlannerCalculationStepResult: Sendable {
  /// The calculated plan; `nil` when none was applied (stopped or superseded).
  public let plan: IndustryPlanSnapshot?
  /// The step reported an error.
  public let failed: Bool

  public init(plan: IndustryPlanSnapshot?, failed: Bool) {
    self.plan = plan
    self.failed = failed
  }
}

/// The decisions between the passes of one click.
public enum PlannerPassDecisions {
  /// Materials the plan builds.
  public static func producedTypeIDs(_ plan: IndustryPlanSnapshot) -> Set<Int64> {
    Set(plan.materials.filter { $0.toProduce > 0 }.map(\.typeID))
  }

  /// Reactions the plan builds without any formula source. They cannot run
  /// and are bought instead, unless the owner chose them or they are an
  /// ordered product.
  public static func unusableReactionTypeIDs(
    in plan: IndustryPlanSnapshot,
    allocatedBlueprintTypeIDs: Set<Int64>,
    manualTypeIDs: Set<Int64>,
    requestedProductNames: Set<String>
  ) -> Set<Int64> {
    Set(
      plan.nodes.compactMap { node -> Int64? in
        guard node.action == .produce, node.activity == .reaction,
          let blueprintTypeID = node.blueprintTypeID,
          !allocatedBlueprintTypeIDs.contains(blueprintTypeID),
          !manualTypeIDs.contains(node.typeID),
          !requestedProductNames.contains(node.name)
        else { return nil }
        return node.typeID
      }
    )
  }

  /// The plan's own build or buy choices, with the manual ones winning and
  /// unusable reactions bought.
  public static func decisions(
    manual: [Int64: MaterialProcurementPreference],
    decided plan: IndustryPlanSnapshot,
    buying unusableReactions: Set<Int64>
  ) -> [Int64: MaterialProcurementPreference] {
    var decisions = manual.merging(
      plan.materials.compactMap { material in
        material.procurement.map { (material.typeID, $0) }
      },
      uniquingKeysWith: { manual, _ in manual }
    )
    for typeID in unusableReactions {
      decisions[typeID]?.supplyMode = .buy
    }
    return decisions
  }
}

/// The control flow of one Planner click (owner decisions 30. and
/// 31.10.2026): first without stock when stock is used, then with it; each
/// time a Blueprint basis and a calculation, a control pass when the
/// calculated build steps differ from the tree, and up to two follow-up
/// passes for missing Blueprint runs. The Blueprint basis and the
/// calculation itself are steps of the caller.
@MainActor
public struct PlannerCalculationPipeline<Basis: PlannerCalculationBasis> {
  public enum Outcome: Sendable {
    /// The click finished; the plan to show and save.
    case completed(IndustryPlanSnapshot?)
    /// Stopped by a cancellation, a failed Blueprint basis or a failed
    /// calculation; the previous plan stays.
    case stopped
  }

  public let manualPreferences: [Int64: MaterialProcurementPreference]
  public let requestedProductNames: Set<String>
  public let usesStock: Bool
  public let resolveBasis: @MainActor (PlannerBasisRequest) async -> Basis?
  public let calculate:
    @MainActor (PlannerCalculationRequest<Basis>) async -> PlannerCalculationStepResult

  public init(
    manualPreferences: [Int64: MaterialProcurementPreference],
    requestedProductNames: Set<String>,
    usesStock: Bool,
    resolveBasis: @escaping @MainActor (PlannerBasisRequest) async -> Basis?,
    calculate:
      @escaping @MainActor (PlannerCalculationRequest<Basis>) async
      -> PlannerCalculationStepResult
  ) {
    self.manualPreferences = manualPreferences
    self.requestedProductNames = requestedProductNames
    self.usesStock = usesStock
    self.resolveBasis = resolveBasis
    self.calculate = calculate
  }

  /// Runs the click. `previousPlan` is the plan shown before; like the shown
  /// plan before, it stays the current one until a calculation applies a new
  /// plan.
  public func run(startingFrom previousPlan: IndustryPlanSnapshot?) async -> Outcome {
    var state = State(current: previousPlan)
    // Owner decision 2026-10-31: stock must not change what the order costs,
    // so the same order is calculated without stock first. Only the second
    // result is kept and saved.
    if usesStock {
      if await runCalculation(withoutStock: true, stockReference: nil, state: &state),
        !state.lastFailed
      {
        state.stockReference = state.current?.costBreakdown?.totalProductionCost
      }
      guard !Task.isCancelled else { return .stopped }
    }
    guard
      await runCalculation(
        withoutStock: false,
        stockReference: state.stockReference,
        state: &state
      ),
      !state.lastFailed
    else { return .stopped }
    return .completed(state.current)
  }

  private struct State {
    var current: IndustryPlanSnapshot?
    var lastFailed = false
    var stockReference: Double?
  }

  private func step(
    _ basis: Basis,
    preferences: [Int64: MaterialProcurementPreference],
    automaticSupply: Bool,
    withoutStock: Bool,
    stockReference: Double?,
    state: inout State
  ) async {
    let result = await calculate(
      PlannerCalculationRequest(
        basis: basis,
        preferences: preferences,
        automaticSupply: automaticSupply,
        calculatesWithoutStock: withoutStock,
        stockReferenceProductionCost: withoutStock ? nil : stockReference
      )
    )
    state.lastFailed = result.failed
    if let plan = result.plan { state.current = plan }
  }

  /// One complete calculation; `false` after a cancellation or a failed
  /// Blueprint basis.
  private func runCalculation(
    withoutStock: Bool,
    stockReference: Double?,
    state: inout State
  ) async -> Bool {
    var minimumRuns: [Int64: Int] = [:]
    func basis(
      _ preferences: [Int64: MaterialProcurementPreference],
      automaticSupply: Bool
    ) async -> Basis? {
      await resolveBasis(
        PlannerBasisRequest(
          preferences: preferences,
          automaticSupply: automaticSupply,
          minimumBlueprintRuns: minimumRuns,
          calculatesWithoutStock: withoutStock
        )
      )
    }
    guard let firstBasis = await basis(manualPreferences, automaticSupply: true)
    else { return false }
    await step(
      firstBasis,
      preferences: manualPreferences,
      automaticSupply: true,
      withoutStock: withoutStock,
      stockReference: stockReference,
      state: &state
    )
    guard !Task.isCancelled else { return false }
    // The tree decides at Main Hub prices, the calculation at the selected
    // purchase locations and with Blueprint costs. When they differ, the
    // Blueprints are resolved again for the calculated build steps and those
    // steps are kept, so costs and supply always describe the same graph.
    guard !state.lastFailed, let decided = state.current else { return true }
    let unusableReactions = PlannerPassDecisions.unusableReactionTypeIDs(
      in: decided,
      allocatedBlueprintTypeIDs: firstBasis.allocatedBlueprintTypeIDs,
      manualTypeIDs: Set(manualPreferences.keys),
      requestedProductNames: requestedProductNames
    )
    let uncoveredRuns = BlueprintSupplyPlanner.uncoveredRuns(in: decided)
    guard
      !unusableReactions.isEmpty || !uncoveredRuns.isEmpty
        || PlannerPassDecisions.producedTypeIDs(decided)
          != PlannerPassDecisions.producedTypeIDs(firstBasis.selectedPlan)
    else { return true }
    minimumRuns = uncoveredRuns
    let decisions = PlannerPassDecisions.decisions(
      manual: manualPreferences,
      decided: decided,
      buying: unusableReactions
    )
    guard let finalBasis = await basis(decisions, automaticSupply: false)
    else { return false }
    await step(
      finalBasis,
      preferences: decisions,
      automaticSupply: false,
      withoutStock: withoutStock,
      stockReference: stockReference,
      state: &state
    )
    guard !Task.isCancelled else { return false }
    // More runs can round the jobs differently; a true lack of Blueprints
    // stays a warning because the reservation then matches the plan.
    for _ in 0..<2 {
      guard !state.lastFailed, let plan = state.current else { break }
      let remaining = BlueprintSupplyPlanner.uncoveredRuns(in: plan)
      guard !remaining.isEmpty else { break }
      minimumRuns.merge(remaining, uniquingKeysWith: max)
      guard let nextBasis = await basis(decisions, automaticSupply: false)
      else { return false }
      await step(
        nextBasis,
        preferences: decisions,
        automaticSupply: false,
        withoutStock: withoutStock,
        stockReference: stockReference,
        state: &state
      )
      guard !Task.isCancelled else { return false }
    }
    return true
  }
}
