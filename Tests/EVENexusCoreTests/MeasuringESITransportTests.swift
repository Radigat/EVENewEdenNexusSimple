import Foundation
import Testing

@testable import EVENexusCore

@Suite("ESI measuring transport")
struct MeasuringESITransportTests {
  @Test
  func routeFamilyHidesIdentitiesAndQuery() {
    #expect(
      MeasuringESITransport.routeFamily(
        of: URL(
          string: "https://esi.evetech.net/characters/2112345678/assets/?page=2"
        )
      ) == "/characters/{id}/assets/"
    )
    #expect(
      MeasuringESITransport.routeFamily(
        of: URL(
          string:
            "https://esi.evetech.net/markets/10000002/orders/?order_type=all&type_id=34"
        )
      ) == "/markets/{id}/orders/"
    )
    #expect(MeasuringESITransport.routeFamily(of: nil) == "unknown")
  }

  @Test
  func passesRequestsResponsesAndErrorsThroughUnchanged() async throws {
    let base = RecordingTransport(
      responses: [
        .init(status: 200, body: "[1,2,3]"),
        .failure,
      ]
    )
    let transport = MeasuringESITransport(base: base, summaryInterval: nil)
    let request = esiRequest("/markets/prices/")

    let (data, response) = try await transport.data(for: request)

    #expect(data == Data("[1,2,3]".utf8))
    #expect(response.statusCode == 200)
    #expect(await base.requests == [request])
    await #expect(throws: URLError.self) {
      _ = try await transport.data(for: request)
    }
    #expect(await base.requests == [request, request])
    let snapshot = transport.snapshot()
    #expect(snapshot.routes["/markets/prices/"]?.requests == 2)
    #expect(snapshot.routes["/markets/prices/"]?.failures == 1)
    #expect(snapshot.routes["/markets/prices/"]?.bytes == 7)
  }

  @Test
  func countsStatusClassesPerRouteFamily() async throws {
    let base = RecordingTransport(
      responses: [
        .init(status: 200, body: "{}"),
        .init(status: 304, body: ""),
        .init(status: 404, body: ""),
        .init(status: 503, body: ""),
      ]
    )
    let transport = MeasuringESITransport(base: base, summaryInterval: nil)

    for path in [
      "/characters/1/wallet/", "/characters/2/wallet/",
      "/characters/3/wallet/", "/characters/4/wallet/",
    ] {
      _ = try await transport.data(for: esiRequest(path))
    }

    let wallet = try #require(
      transport.snapshot().routes["/characters/{id}/wallet/"]
    )
    #expect(wallet.requests == 4)
    #expect(wallet.success == 1)
    #expect(wallet.notModified == 1)
    #expect(wallet.clientErrors == 1)
    #expect(wallet.serverErrors == 1)
  }

  @Test
  func countsARequestSentAgainBeforeItsExpiresTime() async throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let expires = "Fri, 15 Jan 2027 08:05:00 GMT"
    let base = RecordingTransport(
      responses: Array(
        repeating: .init(status: 200, body: "{}", headers: ["Expires": expires]),
        count: 4
      )
    )
    let transport = MeasuringESITransport(
      base: base,
      now: { clock.now },
      summaryInterval: nil
    )
    // 1_800_000_000 is Fri, 15 Jan 2027 08:00:00 GMT.
    _ = try await transport.data(for: esiRequest("/markets/prices/"))
    clock.now = clock.now.addingTimeInterval(60)
    _ = try await transport.data(for: esiRequest("/markets/prices/"))
    clock.now = clock.now.addingTimeInterval(600)
    _ = try await transport.data(for: esiRequest("/markets/prices/"))
    var post = esiRequest("/universe/names/")
    post.httpMethod = "POST"
    _ = try await transport.data(for: post)

    let snapshot = transport.snapshot()
    #expect(snapshot.routes["/markets/prices/"]?.earlyRequests == 1)
    #expect(snapshot.earlyRequests == 1)
  }

  @Test
  func countsMissingHeadersAndFutureCompatibilityDates() async throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    let base = RecordingTransport(
      responses: Array(repeating: .init(status: 200, body: "{}"), count: 4)
    )
    let transport = MeasuringESITransport(
      base: base,
      now: { clock.now },
      summaryInterval: nil
    )
    var missingUserAgent = esiRequest("/status/")
    missingUserAgent.setValue(nil, forHTTPHeaderField: "User-Agent")
    var missingDate = esiRequest("/status/")
    missingDate.setValue(nil, forHTTPHeaderField: "X-Compatibility-Date")
    // At 08:00 UTC the latest valid date is still the previous day.
    var futureDate = esiRequest("/status/")
    futureDate.setValue("2027-01-15", forHTTPHeaderField: "X-Compatibility-Date")

    for request in [
      missingUserAgent, missingDate, futureDate, esiRequest("/status/"),
    ] {
      _ = try await transport.data(for: request)
    }

    let snapshot = transport.snapshot()
    #expect(snapshot.missingUserAgent == 1)
    #expect(snapshot.missingCompatibilityDate == 1)
    #expect(snapshot.futureCompatibilityDate == 1)
    #expect(
      MeasuringESITransport.latestValidCompatibilityDate(at: clock.now)
        == "2027-01-14"
    )
  }

  @Test
  func recordsLimitResponsesAndLowestRemainingBudgets() async throws {
    let base = RecordingTransport(
      responses: [
        .init(
          status: 200,
          body: "{}",
          headers: [
            "X-ESI-Error-Limit-Remain": "87",
            "X-Ratelimit-Group": "char-wallet",
            "X-Ratelimit-Remaining": "140",
          ]
        ),
        .init(
          status: 429,
          body: "",
          headers: [
            "X-Ratelimit-Group": "char-wallet",
            "X-Ratelimit-Remaining": "0",
          ]
        ),
        .init(
          status: 420,
          body: "",
          headers: ["X-ESI-Error-Limit-Remain": "0"]
        ),
      ]
    )
    let transport = MeasuringESITransport(base: base, summaryInterval: nil)
    let before = transport.snapshot()

    for _ in 0..<3 {
      _ = try await transport.data(for: esiRequest("/characters/9/wallet/"))
    }

    let snapshot = transport.snapshot()
    #expect(snapshot.rateLimited == 1)
    #expect(snapshot.errorLimited == 1)
    #expect(snapshot.lowestErrorLimitRemain == 0)
    #expect(snapshot.lowestRateLimitRemaining == ["char-wallet": 0])
    let delta = snapshot.subtracting(before)
    #expect(delta.requests == 3)
    #expect(delta.clientErrors == 2)
    let summary = delta.summary()
    #expect(summary.contains("429=1"))
    #expect(summary.contains("420=1"))
    #expect(summary.contains("/characters/{id}/wallet/=3"))
    #expect(!summary.contains("/9/"))
  }

  private func esiRequest(_ path: String) -> URLRequest {
    var request = URLRequest(
      url: URL(string: "https://esi.evetech.net\(path)")!
    )
    request.setValue("EVE Nexus Tests", forHTTPHeaderField: "User-Agent")
    request.setValue(
      EVEConstants.esiCompatibilityDate,
      forHTTPHeaderField: "X-Compatibility-Date"
    )
    return request
  }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) {
    self.value = value
  }

  var now: Date {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}

private actor RecordingTransport: ESIHTTPTransporting {
  enum Reply: Sendable {
    case response(status: Int, body: String, headers: [String: String])
    case failure

    init(status: Int, body: String, headers: [String: String] = [:]) {
      self = .response(status: status, body: body, headers: headers)
    }
  }

  private var replies: [Reply]
  private(set) var requests: [URLRequest] = []

  init(responses: [Reply]) {
    replies = responses
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let reply = replies.removeFirst()
    switch reply {
    case .failure:
      throw URLError(.timedOut)
    case .response(let status, let body, let headers):
      return (
        Data(body.utf8),
        HTTPURLResponse(
          url: request.url!,
          statusCode: status,
          httpVersion: "HTTP/1.1",
          headerFields: headers
        )!
      )
    }
  }
}
