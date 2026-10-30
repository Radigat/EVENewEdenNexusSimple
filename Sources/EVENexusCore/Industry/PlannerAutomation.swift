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
