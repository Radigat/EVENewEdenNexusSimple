import Foundation
import Testing

@testable import EVENexusCore

@Suite("EVE Online service status")
struct EVEOnlineServiceStatusTests {
  @Test
  func officialSummaryKeepsGameMaintenanceSeparateFromLoginAndESI()
    async throws
  {
    let fetchedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-07-31T11:07:00Z")
    )
    let client = EVEOnlineStatusClient(
      transport: StatusSummaryTransport(),
      now: { fetchedAt }
    )

    let status = try await client.fetch()

    #expect(status.isGameServerUnderMaintenance)
    #expect(status.hasGameServerIssue)
    #expect(!status.hasLoginIssue)
    #expect(!status.hasESIIssue)
    #expect(status.fetchedAt == fetchedAt)
    #expect(status.pageUpdatedAt != nil)
  }

  @Test
  func dailyDowntimeFallbackUsesUTCIgnoringLocalTimezone() throws {
    let formatter = ISO8601DateFormatter()
    let before = try #require(
      formatter.date(from: "2026-07-31T10:59:59Z")
    )
    let during = try #require(
      formatter.date(from: "2026-07-31T11:07:00Z")
    )
    let after = try #require(
      formatter.date(from: "2026-07-31T11:20:00Z")
    )

    #expect(!EVEOnlineDailyDowntime.isExpected(at: before))
    #expect(EVEOnlineDailyDowntime.isExpected(at: during))
    #expect(!EVEOnlineDailyDowntime.isExpected(at: after))
  }

  @Test
  func unknownFutureComponentStateDoesNotCreateAFalseOutage() async throws {
    let status = try await EVEOnlineStatusClient(
      transport: StatusSummaryTransport(loginStatus: "new_future_state")
    ).fetch()

    #expect(status.login == .unknown)
    #expect(!status.hasLoginIssue)
  }

  @Test
  func officialSummaryAlsoAcceptsWholeSecondTimestamps() async throws {
    let status = try await EVEOnlineStatusClient(
      transport: StatusSummaryTransport(
        pageUpdatedAt: "2026-07-31T11:00:54Z"
      )
    ).fetch()

    #expect(status.pageUpdatedAt != nil)
  }
}

private struct StatusSummaryTransport: EVEOnlineStatusTransporting {
  let loginStatus: String
  let pageUpdatedAt: String

  init(
    loginStatus: String = "operational",
    pageUpdatedAt: String = "2026-07-31T11:00:54.322Z"
  ) {
    self.loginStatus = loginStatus
    self.pageUpdatedAt = pageUpdatedAt
  }

  func data(for request: URLRequest) async throws
    -> (Data, HTTPURLResponse)
  {
    let body = """
      {
        "page": {
          "updated_at": "\(pageUpdatedAt)"
        },
        "components": [
          {
            "name": "Game Server",
            "status": "under_maintenance"
          },
          {
            "name": "Login",
            "status": "\(loginStatus)"
          },
          {
            "name": "EVE Swagger Interface (ESI)",
            "status": "operational"
          }
        ]
      }
      """
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
      )!
    )
  }
}
