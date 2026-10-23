import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Remembered ESI 403/404 responses")
struct ESIRememberedFailureTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private let structureID: Int64 = 1_000_000_000_001

  @Test
  func aForbiddenStructureIsNotRequestedAgainWithinTheRecheckInterval() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([403, 200])
    let esi = client(transport, url: url, clock: clock)
    let service = PlayerStructureSearchService(esi: esi)

    let first = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )
    clock.now = start.addingTimeInterval(23 * 60 * 60)
    let second = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )

    #expect(first.diagnostics.contains("esi.structure-resolution.inaccessible:1"))
    #expect(second.diagnostics.contains("esi.structure-resolution.inaccessible:1"))
    #expect(await transport.requestCount == 1)

    // After 24 hours the structure is asked again and now resolves.
    clock.now = start.addingTimeInterval(24 * 60 * 60 + 1)
    let third = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )
    #expect(third.value?.map(\.id) == [structureID])
    #expect(await transport.requestCount == 2)
  }

  @Test
  func aRememberedNotFoundSurvivesARestartPerCharacter() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    _ = await PlayerStructureSearchService(
      esi: client(StatusTransport([404]), url: url, clock: clock)
    ).resolveKnownStructures(structureIDs: [structureID], lease: lease(91))

    let restarted = StatusTransport([403])
    let service = PlayerStructureSearchService(
      esi: client(restarted, url: url, clock: clock)
    )
    _ = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )
    #expect(await restarted.requestCount == 0)

    // Another character has its own access list and is asked.
    _ = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(92)
    )
    #expect(await restarted.requestCount == 1)
  }

  @Test
  func anExplicitSearchAsksAgainAndClearsTheMarkerOnSuccess() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([403, 200])
    let esi = client(transport, url: url, clock: clock)
    _ = await PlayerStructureSearchService(esi: esi)
      .resolveKnownStructures(structureIDs: [structureID], lease: lease(91))

    let response = try await esi.get(
      StructureType.self,
      endpoint: PlayerStructureSearchService.detailEndpoint(
        structureID: structureID
      ),
      lease: lease(91),
      revalidatingRememberedFailure: true
    )

    #expect(response.value.typeID == 35_825)
    #expect(await transport.requestCount == 2)
    let key =
      "character:91|https://esi.evetech.net/universe/structures/\(structureID)"
    #expect(await ESIResponseDiskCache(url: url).rememberedFailure(forKey: key) == nil)
  }

  @Test
  func otherClientErrorsAndPlainEndpointsAreNotRemembered() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let transport = StatusTransport([400, 400, 403, 403])
    let esi = client(transport, url: url, clock: Clock(start))
    let remembering = PlayerStructureSearchService.detailEndpoint(
      structureID: structureID
    )
    let plain = ESIEndpoint(
      path: "/universe/structures/\(structureID)",
      requiresAuthorization: true
    )

    for endpoint in [remembering, remembering, plain, plain] {
      _ = try? await esi.get(StructureType.self, endpoint: endpoint, lease: lease(91))
    }

    #expect(await transport.requestCount == 4)
  }

  @Test
  func disconnectingACharacterForgetsItsRememberedFailures() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([403, 403])
    let esi = client(transport, url: url, clock: clock)
    let service = PlayerStructureSearchService(esi: esi)
    _ = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )

    await esi.removeCachedResponses(forCharacterID: 91)
    _ = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )

    #expect(await transport.requestCount == 2)
  }

  @Test
  func aVersionOneCacheFileGainsTheFailureTable() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    #expect(
      sqlite3_exec(
        database,
        """
        CREATE TABLE esi_responses (
          cache_key TEXT PRIMARY KEY NOT NULL, partition TEXT NOT NULL,
          compatibility_date TEXT NOT NULL, etag TEXT, last_modified TEXT,
          expires_at REAL, pages INTEGER, status_code INTEGER NOT NULL,
          provider TEXT NOT NULL, version TEXT NOT NULL,
          captured_at REAL NOT NULL, snapshot_id TEXT NOT NULL,
          body BLOB NOT NULL, byte_count INTEGER NOT NULL,
          last_access REAL NOT NULL
        );
        PRAGMA user_version = 1;
        """,
        nil,
        nil,
        nil
      ) == SQLITE_OK
    )
    sqlite3_close(database)
    let store = ESIResponseDiskCache(url: url, now: { start })
    let failure = ESIRememberedFailure(
      statusCode: 403,
      until: start.addingTimeInterval(60)
    )

    await store.rememberFailure(failure, forKey: "character:1|x")

    #expect(await store.rememberedFailure(forKey: "character:1|x") == failure)
  }

  @Test
  func freshStructureDetailsLoadedByOneCharacterServeAllCharacters() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([200, 200], expires: start.addingTimeInterval(3_600))
    let service = PlayerStructureSearchService(esi: client(transport, url: url, clock: clock))

    let first = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(91)
    )
    let second = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(92)
    )

    #expect(first.value?.map(\.id) == [structureID])
    #expect(second.value?.map(\.id) == [structureID])
    #expect(await transport.requestCount == 1)

    // The shared copy survives a restart until it expires.
    let restarted = StatusTransport([])
    _ = await PlayerStructureSearchService(
      esi: client(restarted, url: url, clock: clock)
    ).resolveKnownStructures(structureIDs: [structureID], lease: lease(93))
    #expect(await restarted.requestCount == 0)

    // After expiry each character asks again with its own token.
    clock.now = start.addingTimeInterval(3_601)
    _ = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(92)
    )
    #expect(await transport.requestCount == 2)
  }

  @Test
  func aSharedCopyAlsoServesACharacterWithARememberedForbidden() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([403, 200], expires: start.addingTimeInterval(3_600))
    let service = PlayerStructureSearchService(esi: client(transport, url: url, clock: clock))
    _ = await service.resolveKnownStructures(structureIDs: [structureID], lease: lease(92))
    _ = await service.resolveKnownStructures(structureIDs: [structureID], lease: lease(91))

    let result = await service.resolveKnownStructures(
      structureIDs: [structureID],
      lease: lease(92)
    )

    #expect(result.value?.map(\.id) == [structureID])
    #expect(await transport.requestCount == 2)
  }

  @Test
  func pagesOfAnotherSnapshotAlsoDropTheSharedCopy() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    let clock = Clock(start)
    let transport = StatusTransport([200, 200], expires: start.addingTimeInterval(3_600))
    let esi = client(transport, url: url, clock: clock)
    let endpoint = PlayerStructureSearchService.detailEndpoint(structureID: structureID)
    let firstPage = ESIClient.pageEndpoint(endpoint, page: 1)
    _ = try await esi.get(StructureType.self, endpoint: firstPage, lease: lease(91))

    await esi.removeCachedPages(
      of: endpoint,
      pageCount: 1,
      lease: lease(92),
      exceptLastModified: "newer snapshot"
    )
    _ = try await esi.get(StructureType.self, endpoint: firstPage, lease: lease(92))

    #expect(await transport.requestCount == 2)
  }

  private func client(
    _ transport: StatusTransport,
    url: URL,
    clock: Clock
  ) -> ESIClient {
    ESIClient(
      transport: transport,
      responseStore: ESIResponseDiskCache(url: url, now: { clock.now }),
      now: { clock.now }
    )
  }

  private func lease(_ characterID: Int64) -> AccessTokenLease {
    AccessTokenLease(
      characterID: characterID,
      accessToken: "fixture-token",
      expiresAt: .distantFuture,
      scopes: [PlayerStructureSearchService.detailScope]
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-esi-remembered-failure-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }
}

private struct StructureType: Decodable, Sendable {
  let typeID: Int64

  private enum CodingKeys: String, CodingKey {
    case typeID = "type_id"
  }
}

private final class Clock: @unchecked Sendable {
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

/// Answers structure-detail requests with the scripted status codes in order.
private actor StatusTransport: ESIHTTPTransporting {
  private var statuses: [Int]
  private let expires: Date?
  private(set) var requestCount = 0

  init(_ statuses: [Int], expires: Date? = nil) {
    self.statuses = statuses
    self.expires = expires
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requestCount += 1
    let status = statuses.isEmpty ? 500 : statuses.removeFirst()
    let body =
      status == 200
      ? #"{"name":"Fixture Raitaru","owner_id":98000001,"solar_system_id":30000142,"type_id":35825}"#
      : #"{"error":"fixture"}"#
    return (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: expires.map { date in
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.timeZone = TimeZone(secondsFromGMT: 0)
          formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
          return ["Expires": formatter.string(from: date)]
        } ?? [:]
      )!
    )
  }
}
