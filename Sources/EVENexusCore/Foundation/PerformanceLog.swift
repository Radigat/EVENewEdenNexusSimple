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
