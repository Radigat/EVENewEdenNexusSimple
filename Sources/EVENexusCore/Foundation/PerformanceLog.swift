import Darwin
import Foundation
import os

/// Durations and counts for measuring the running app, written to the unified
/// log (subsystem `com.local.EVENexusSimple`, category `performance`).
/// Messages carry only step names, durations and counts — never character,
/// structure or item identities and never credentials.
///
/// Read live:
/// `log stream --predicate 'subsystem == "com.local.EVENexusSimple" AND category == "performance"'`
public enum PerformanceLog {
  public static let subsystem = "com.local.EVENexusSimple"
  public static let category = "performance"

  private static let logger = Logger(subsystem: subsystem, category: category)

  /// Logs a point in time relative to the process start.
  public static func milestone(_ name: String, _ details: String = "") {
    write("\(name) at process \(processStartText())\(suffix(details))")
  }

  /// Logs a single observation without a duration.
  public static func event(_ name: String, _ details: String) {
    write("\(name)\(suffix(details))")
  }

  /// Time elapsed since the kernel started this process, or `nil` when the
  /// start time cannot be read.
  public static func sinceProcessStart(now: Date = Date()) -> TimeInterval? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else {
      return nil
    }
    let start = info.kp_proc.p_un.__p_starttime
    let started =
      TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000
    guard started > 0 else { return nil }
    return now.timeIntervalSince1970 - started
  }

  /// Current and lifetime-peak physical footprint of this process in bytes
  /// (`task_vm_info`); `nil` when the kernel does not answer.
  public static func memoryFootprint() -> (current: Int64, peak: Int64)? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else { return nil }
    return (Int64(info.phys_footprint), Int64(info.ledger_phys_footprint_peak))
  }

  static func milliseconds(_ duration: Duration) -> String {
    let components = duration.components
    let value =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.1f ms", value)
  }

  static func processStartText() -> String {
    sinceProcessStart().map { String(format: "+%.2f s", $0) } ?? "+? s"
  }

  static func write(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  private static func suffix(_ details: String) -> String {
    details.isEmpty ? "" : " \(details)"
  }
}

/// Measures one operation and, optionally, its consecutive phases.
public struct PerformanceStopwatch: Sendable {
  private let name: String
  private let started: ContinuousClock.Instant
  private var lastLap: ContinuousClock.Instant

  public init(_ name: String) {
    self.name = name
    started = ContinuousClock.now
    lastLap = started
  }

  /// Logs the time since the previous lap (or the start) for `phase`.
  public mutating func lap(_ phase: String, _ details: String = "") {
    let now = ContinuousClock.now
    PerformanceLog.write(
      "\(name) phase=\(phase) \(PerformanceLog.milliseconds(now - lastLap))"
        + " (total \(PerformanceLog.milliseconds(now - started)))"
        + (details.isEmpty ? "" : " \(details)")
    )
    lastLap = now
  }

  /// Logs the total duration since the start.
  public func finish(_ details: String = "") {
    PerformanceLog.write(
      "\(name) total \(PerformanceLog.milliseconds(ContinuousClock.now - started))"
        + " at process \(PerformanceLog.processStartText())"
        + (details.isEmpty ? "" : " \(details)")
    )
  }
}

/// Counts and phase durations of one interactive Planner calculation (one
/// click). The click binds an instance with `$current.withValue`; the planner,
/// market and route services count into it through the task. It only counts
/// and never changes a result.
public final class PlannerCalculationMetrics: @unchecked Sendable {
  @TaskLocal public static var current: PlannerCalculationMetrics?

  public enum Counter: String, CaseIterable, Sendable {
    case planPasses = "plan-passes"
    case productionTrees = "trees"
    case calculations = "calculations"
    case marketSnapshots = "market-snapshots"
    case marketTypeRequests = "market-type-requests"
    case jumpRoutes = "dotlan-routes"
    case jumpRouteCacheHits = "dotlan-cache-hits"
  }

  private struct Phase {
    var count = 0
    var duration: Duration = .zero
  }

  private let lock = NSLock()
  private var counts: [Counter: Int] = [:]
  private var phases: [String: Phase] = [:]
  private var phaseOrder: [String] = []

  public init() {}

  /// Adds `amount` to `counter` of the click bound to the current task.
  public static func count(_ counter: Counter, by amount: Int = 1) {
    current?.add(counter, by: amount)
  }

  public func add(_ counter: Counter, by amount: Int = 1) {
    lock.withLock { counts[counter, default: 0] += amount }
  }

  public func count(of counter: Counter) -> Int {
    lock.withLock { counts[counter, default: 0] }
  }

  /// Adds the time since `start` to `phase`, keeping the first-seen order.
  public func record(_ phase: String, since start: ContinuousClock.Instant) {
    let elapsed = ContinuousClock.now - start
    lock.withLock {
      if phases[phase] == nil { phaseOrder.append(phase) }
      phases[phase, default: Phase()].count += 1
      phases[phase, default: Phase()].duration += elapsed
    }
  }

  /// Counters in declaration order, then phases as `name=count×total`.
  public func summary() -> String {
    lock.withLock {
      let counters = Counter.allCases.map {
        "\($0.rawValue)=\(counts[$0, default: 0])"
      }
      let phaseTexts = phaseOrder.compactMap { name in
        phases[name].map {
          "\(name)=\($0.count)×\(PerformanceLog.milliseconds($0.duration))"
        }
      }
      return (counters + phaseTexts).joined(separator: " ")
    }
  }
}

/// Aggregates a frequently repeated operation, e.g. a computation in a view
/// body, and logs one line per window instead of one line per call.
public final class PerformanceAccumulator: @unchecked Sendable {
  private let name: String
  private let window: Duration
  private let lock = NSLock()
  private var windowStart: ContinuousClock.Instant?
  private var calls = 0
  private var units = 0
  private var total: Duration = .zero
  private var longest: Duration = .zero

  public init(_ name: String, window: Duration = .seconds(5)) {
    self.name = name
    self.window = window
  }

  /// Records one call that handled `units` items since `start`; writes the
  /// window's line once the window has passed.
  public func record(units: Int, since start: ContinuousClock.Instant) {
    let now = ContinuousClock.now
    let elapsed = now - start
    let line: String? = lock.withLock {
      let started = windowStart ?? start
      windowStart = started
      calls += 1
      self.units += units
      total += elapsed
      longest = max(longest, elapsed)
      guard now - started >= window else { return nil }
      let text =
        "\(name) calls=\(calls) units=\(self.units)"
        + " total \(PerformanceLog.milliseconds(total))"
        + " max \(PerformanceLog.milliseconds(longest))"
        + " window \(PerformanceLog.milliseconds(now - started))"
      windowStart = nil
      calls = 0
      self.units = 0
      total = .zero
      longest = .zero
      return text
    }
    if let line { PerformanceLog.write(line) }
  }
}
