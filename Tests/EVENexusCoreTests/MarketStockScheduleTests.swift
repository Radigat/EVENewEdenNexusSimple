import Foundation
import Testing

@testable import EVENexusCore

@Suite("Market stock schedule")
struct MarketStockScheduleTests {
  private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
  }()

  @Test
  func termsAreSixAndThirteenLocalTime() {
    let morning = local(2026, 10, 29, 5, 59)
    #expect(MarketStockSchedule.nextTerm(after: morning, calendar: berlin) == local(2026, 10, 29, 6, 0))
    #expect(MarketStockSchedule.latestTerm(atOrBefore: morning, calendar: berlin) == local(2026, 10, 28, 13, 0))
    let afternoon = local(2026, 10, 29, 13, 0)
    #expect(MarketStockSchedule.latestTerm(atOrBefore: afternoon, calendar: berlin) == afternoon)
    #expect(MarketStockSchedule.nextTerm(after: afternoon, calendar: berlin) == local(2026, 10, 30, 6, 0))
    // Across the end of daylight saving time the local times stay fixed.
    let beforeSwitch = local(2026, 10, 24, 20, 0)
    #expect(MarketStockSchedule.nextTerm(after: beforeSwitch, calendar: berlin) == local(2026, 10, 25, 6, 0))
  }

  @Test
  func aRecentSuccessfulScanStandsInForTheTerm() {
    let term = local(2026, 10, 29, 13, 0)
    // Owner decision 29.10.2026: up to 3 hours before the term.
    #expect(MarketStockSchedule.isSatisfied(term: term, lastSuccessfulScanAt: term.addingTimeInterval(-3 * 3_600)))
    #expect(!MarketStockSchedule.isSatisfied(term: term, lastSuccessfulScanAt: term.addingTimeInterval(-3 * 3_600 - 1)))
    #expect(MarketStockSchedule.isSatisfied(term: term, lastSuccessfulScanAt: term.addingTimeInterval(60)))
    #expect(!MarketStockSchedule.isSatisfied(term: term, lastSuccessfulScanAt: nil))
    #expect(
      MarketStockSchedule.decision(
        now: term.addingTimeInterval(5),
        lastSuccessfulScanAt: term.addingTimeInterval(-2 * 3_600),
        lastAttemptedTerm: nil,
        calendar: berlin
      ) == .wait(until: local(2026, 10, 30, 6, 0))
    )
  }

  @Test
  func missedTermsRunOnceWithoutStacking() {
    // The Mac slept from Tuesday evening to Thursday 10:00: four terms were
    // missed, only the latest (Thursday 06:00) runs, once.
    let lastScan = local(2026, 10, 27, 20, 0)
    let wake = local(2026, 10, 29, 10, 0)
    let latest = local(2026, 10, 29, 6, 0)
    #expect(
      MarketStockSchedule.decision(
        now: wake,
        lastSuccessfulScanAt: lastScan,
        lastAttemptedTerm: nil,
        calendar: berlin
      ) == .run(term: latest)
    )
    // A failed attempt is not repeated until the next term.
    #expect(
      MarketStockSchedule.decision(
        now: wake.addingTimeInterval(120),
        lastSuccessfulScanAt: lastScan,
        lastAttemptedTerm: latest,
        calendar: berlin
      ) == .wait(until: local(2026, 10, 29, 13, 0))
    )
    // At the next term it runs again.
    #expect(
      MarketStockSchedule.decision(
        now: local(2026, 10, 29, 13, 0),
        lastSuccessfulScanAt: lastScan,
        lastAttemptedTerm: latest,
        calendar: berlin
      ) == .run(term: local(2026, 10, 29, 13, 0))
    )
  }

  @Test
  func termsWaitForDowntimeAndServiceProblems() {
    // In summer 13:00 Berlin is 11:00 UTC, inside the daily downtime.
    let summerTerm = local(2026, 7, 15, 13, 0)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    #expect(
      MarketStockSchedule.serviceDelay(now: summerTerm, status: nil)
        == utc.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 11, minute: 20))
    )
    // In winter 13:00 Berlin is 12:00 UTC: no wait without a reported issue.
    let winterTerm = local(2026, 10, 29, 13, 0)
    #expect(MarketStockSchedule.serviceDelay(now: winterTerm, status: nil) == nil)
    #expect(MarketStockSchedule.serviceDelay(now: winterTerm, status: status(esi: .operational)) == nil)
    #expect(
      MarketStockSchedule.serviceDelay(now: winterTerm, status: status(esi: .majorOutage))
        == winterTerm.addingTimeInterval(5 * 60)
    )
    #expect(
      MarketStockSchedule.serviceDelay(
        now: winterTerm,
        status: status(esi: .operational, gameServer: .underMaintenance)
      ) == winterTerm.addingTimeInterval(5 * 60)
    )
  }

  private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    berlin.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
  }

  private func status(
    esi: EVEOnlineComponentStatus,
    gameServer: EVEOnlineComponentStatus = .operational
  ) -> EVEOnlineServiceStatusSnapshot {
    EVEOnlineServiceStatusSnapshot(
      fetchedAt: .now,
      pageUpdatedAt: nil,
      gameServer: gameServer,
      login: .operational,
      esi: esi
    )
  }
}
