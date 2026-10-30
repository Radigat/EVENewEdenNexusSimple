import Foundation

/// Fixed market stock terms (MARKTBESTAND_PLAN.md, C5/C6). Pure decisions;
/// the app runs the normal joint hub scan as automatic work.
public enum MarketStockSchedule {
  /// Local times of the two daily terms (owner decision 29.10.2026).
  public static let terms: [(hour: Int, minute: Int)] = [(6, 0), (13, 0)]
  /// Owner decision 29.10.2026: a successful hub scan at most 3 hours
  /// before a term stands in for it, so the order books are not reloaded.
  public static let satisfiedWindow: TimeInterval = 3 * 60 * 60
  /// Re-check interval while ESI is down or under maintenance.
  public static let serviceRecheckInterval: TimeInterval = 5 * 60

  public enum Decision: Equatable, Sendable {
    /// Run the joint hub scan for this term now.
    case run(term: Date)
    /// Nothing is due; look again at this time (the next term).
    case wait(until: Date)
  }

  /// The latest term at or before `now`.
  public static func latestTerm(
    atOrBefore now: Date,
    calendar: Calendar = .current
  ) -> Date {
    let candidates = (0...2).flatMap { daysBack -> [Date] in
      guard
        let day = calendar.date(
          byAdding: .day,
          value: -daysBack,
          to: calendar.startOfDay(for: now)
        )
      else { return [] }
      return terms.compactMap {
        calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day)
      }
    }
    return candidates.filter { $0 <= now }.max() ?? now
  }

  /// The first term strictly after `now`.
  public static func nextTerm(
    after now: Date,
    calendar: Calendar = .current
  ) -> Date {
    let candidates = (0...2).flatMap { daysAhead -> [Date] in
      guard
        let day = calendar.date(
          byAdding: .day,
          value: daysAhead,
          to: calendar.startOfDay(for: now)
        )
      else { return [] }
      return terms.compactMap {
        calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day)
      }
    }
    return candidates.filter { $0 > now }.min() ?? now.addingTimeInterval(60 * 60)
  }

  /// A term counts as done when a hub scan succeeded at most 3 hours before
  /// it or any time after it.
  public static func isSatisfied(term: Date, lastSuccessfulScanAt: Date?) -> Bool {
    guard let lastSuccessfulScanAt else { return false }
    return lastSuccessfulScanAt >= term.addingTimeInterval(-satisfiedWindow)
  }

  /// Runs only the latest term, once: several missed terms never stack, and
  /// a term already attempted in this run of the app (`lastAttemptedTerm`)
  /// waits for the next term, a restart or a wake instead of looping.
  public static func decision(
    now: Date,
    lastSuccessfulScanAt: Date?,
    lastAttemptedTerm: Date?,
    calendar: Calendar = .current
  ) -> Decision {
    let term = latestTerm(atOrBefore: now, calendar: calendar)
    let next = nextTerm(after: now, calendar: calendar)
    if isSatisfied(term: term, lastSuccessfulScanAt: lastSuccessfulScanAt)
      || lastAttemptedTerm.map({ $0 >= term }) == true
    {
      return .wait(until: next)
    }
    return .run(term: term)
  }

  /// When a term must wait for ESI: during CCP's daily downtime window
  /// until it ends, and while the official status reports an ESI or game
  /// server problem for one re-check interval. `nil` means run now.
  public static func serviceDelay(
    now: Date,
    status: EVEOnlineServiceStatusSnapshot?
  ) -> Date? {
    if EVEOnlineDailyDowntime.isExpected(at: now) {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      return calendar.date(bySettingHour: 11, minute: 20, second: 0, of: now)
        ?? now.addingTimeInterval(serviceRecheckInterval)
    }
    if let status,
      status.hasESIIssue || status.isGameServerUnderMaintenance
    {
      return now.addingTimeInterval(serviceRecheckInterval)
    }
    return nil
  }
}
