import Foundation
import SwiftUI
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB1 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
@MainActor
struct DashboardBoardLayoutTests {
  private let now = Date(timeIntervalSince1970: 1_790_000_000)

  private func owned(
    _ jobID: Int64,
    character: Int64 = 1,
    status: String = "active",
    endsIn hours: Double
  ) -> DashboardIndustryOwnedJob {
    DashboardIndustryOwnedJob(
      characterID: character,
      characterName: "Fixture \(character)",
      job: ESIIndustryJobDTO(
        activityID: 1,
        blueprintID: 700,
        blueprintTypeID: 701,
        endDate: now.addingTimeInterval(hours * 3_600),
        facilityID: 800,
        jobID: jobID,
        runs: 1,
        status: status
      )
    )
  }

  @Test
  func readyJobsComeFirstThenUpcomingJobsEachByEndDate() {
    let jobs = [
      owned(1, endsIn: 5),
      owned(2, endsIn: -1),
      owned(3, status: "ready", endsIn: -10),
      owned(4, endsIn: 1),
      owned(5, endsIn: -3),
    ]
    let rows = DashboardReadyAndUpcomingJobs.rows(jobs: jobs, now: now)
    #expect(rows.map(\.owned.job.jobID) == [3, 5, 2, 4, 1])
    #expect(rows.map(\.isReady) == [true, true, true, false, false])
  }

  @Test
  func upcomingWindowEndsAfterFortyEightHoursAndClosedJobsStayOut() {
    let jobs = [
      owned(1, endsIn: 48),
      owned(2, endsIn: 48.01),
      owned(3, status: "paused", endsIn: 12),
      owned(4, status: "delivered", endsIn: -5),
      owned(5, status: "cancelled", endsIn: 3),
    ]
    let rows = DashboardReadyAndUpcomingJobs.rows(jobs: jobs, now: now)
    #expect(rows.map(\.owned.job.jobID) == [3, 1])
    #expect(rows.allSatisfy { !$0.isReady })
  }

  @Test
  func equalEndDatesUseTheJobIdentityAsTieBreaker() {
    let jobs = [
      owned(9, character: 2, endsIn: 2),
      owned(9, character: 1, endsIn: 2),
      owned(3, character: 2, endsIn: 2),
    ]
    let rows = DashboardReadyAndUpcomingJobs.rows(jobs: jobs, now: now)
    #expect(rows.map(\.id) == ["1:9", "2:3", "2:9"])
  }

  @Test
  func boardRowsShareTheRowHeightOnlyWhenSideBySide() {
    let row = DashboardCardLayout(
      weights: [1, 1],
      minimumWidths: [360, 360],
      equalizesHeights: true
    )
    #expect(row.widths(for: 1_000).allSatisfy { abs($0 - 492) < 0.01 })
    #expect(row.widths(for: 700) == [700, 700])
    #expect(DashboardCardLayout(weights: [1], minimumWidths: [1]).equalizesHeights == false)
  }

  @Test
  func boardRowRendersBothPanelsWithTheTallerHeight() {
    let wide = ImageRenderer(
      content: DashboardCardLayout(
        weights: [1, 1],
        minimumWidths: [360, 360],
        equalizesHeights: true
      ) {
        Color.red.frame(minHeight: 40, maxHeight: .infinity)
        Color.blue.frame(height: 120)
      }
      .frame(width: 1_000)
    )
    #expect(wide.nsImage.map { abs($0.size.height - 120) < 0.5 } == true)

    let narrow = ImageRenderer(
      content: DashboardCardLayout(
        weights: [1, 1],
        minimumWidths: [360, 360],
        equalizesHeights: true
      ) {
        Color.red.frame(minHeight: 40, maxHeight: .infinity)
        Color.blue.frame(height: 120)
      }
      .frame(width: 600)
    )
    // Stacked: each keeps its own height plus the row spacing.
    #expect(
      narrow.nsImage.map {
        abs($0.size.height - (40 + 120 + DesignTokens.spacingMD)) < 0.5
      } == true
    )
  }
}
