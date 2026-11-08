import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB4 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
struct DashboardKeyFigureTests {
  private let now = Date(timeIntervalSince1970: 1_790_000_000)

  private func job(
    _ id: Int64,
    activity: Int,
    status: String = "active",
    endsIn hours: Double = 5
  ) -> DashboardIndustryOwnedJob {
    DashboardIndustryOwnedJob(
      characterID: 1,
      characterName: "Fixture",
      job: ESIIndustryJobDTO(
        activityID: activity,
        blueprintID: 700,
        blueprintTypeID: 701,
        endDate: now.addingTimeInterval(hours * 3_600),
        facilityID: 800,
        jobID: id,
        runs: 1,
        status: status
      )
    )
  }

  private var jobs: [DashboardIndustryOwnedJob] {
    [
      job(1, activity: 1),
      job(2, activity: 1, status: "paused"),
      job(3, activity: 1, endsIn: -1),
      job(4, activity: 1, status: "ready", endsIn: -3),
      job(5, activity: 1, status: "delivered", endsIn: -9),
      job(6, activity: 9),
      job(7, activity: 5),
      job(8, activity: 8, endsIn: -2),
      job(9, activity: 3),
      job(10, activity: 4, status: "cancelled"),
    ]
  }

  @Test
  func readyJobsOccupyTheirSlotUntilDelivery() {
    let manufacturing = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.manufacturing],
      capacity: DashboardIndustryCapacitySummary(value: 10, isComplete: true),
      now: now
    )
    #expect(manufacturing.running == 2)
    #expect(manufacturing.ready == 2)
    #expect(manufacturing.occupied == 4)
    #expect(manufacturing.free == 6)
    #expect(manufacturing.fillFraction == 0.4)
  }

  @Test
  func sciencePoolCountsCopyingInventionAndResearch() {
    let science = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.copying, .invention, .materialResearch, .timeResearch],
      capacity: DashboardIndustryCapacitySummary(value: 5, isComplete: true),
      now: now
    )
    #expect(science.running == 2)
    #expect(science.ready == 1)
    #expect(science.free == 2)
    let reactions = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.reaction],
      capacity: DashboardIndustryCapacitySummary(value: 3, isComplete: true),
      now: now
    )
    #expect(reactions.occupied == 1)
  }

  @Test
  func partialOrMissingCapacityKeepsExplicitStates() {
    let partial = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.manufacturing],
      capacity: DashboardIndustryCapacitySummary(value: 3, isComplete: false),
      now: now
    )
    // A lower-bound capacity gives a lower-bound free count and no bar.
    #expect(partial.free == 0)
    #expect(partial.fillFraction == nil)
    let missing = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.manufacturing],
      capacity: DashboardIndustryCapacitySummary(value: nil, isComplete: false),
      now: now
    )
    #expect(missing.free == nil)
    #expect(missing.fillFraction == nil)
    let zero = DashboardSlotFigure.figure(
      jobs: [],
      activities: [.manufacturing],
      capacity: DashboardIndustryCapacitySummary(value: 0, isComplete: true),
      now: now
    )
    #expect(zero.free == 0)
    #expect(zero.fillFraction == nil)
  }

  @Test
  func overbookedCompleteCapacityFillsTheBarAndHasNoFreeSlot() {
    let figure = DashboardSlotFigure.figure(
      jobs: jobs,
      activities: [.manufacturing],
      capacity: DashboardIndustryCapacitySummary(value: 2, isComplete: true),
      now: now
    )
    #expect(figure.free == 0)
    #expect(figure.fillFraction == 1)
  }
}
