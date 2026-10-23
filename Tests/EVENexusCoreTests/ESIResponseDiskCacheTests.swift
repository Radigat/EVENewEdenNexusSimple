import Foundation
import Testing

@testable import EVENexusCore

@Suite("Durable ESI response cache")
struct ESIResponseDiskCacheTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private let pricesKey = "public|https://esi.evetech.net/markets/prices/"

  @Test
  func restartServesAFreshResponseFromDiskWithoutANetworkRequest() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("caches/esi-responses.sqlite")
    let firstTransport = ScriptedTransport([
      .init(status: 200, body: "[1,2]", expires: start.addingTimeInterval(3_600), etag: "\"a\"")
    ])
    let first = client(firstTransport, store: ESIResponseDiskCache(url: url), at: start)
    #expect(try await first.get([Int].self, endpoint: prices).value == [1, 2])

    let restartedTransport = ScriptedTransport([])
    let restarted = client(
      restartedTransport,
      store: ESIResponseDiskCache(url: url),
      at: start.addingTimeInterval(600)
    )
    let response = try await restarted.get([Int].self, endpoint: prices)

    #expect(response.value == [1, 2])
    #expect(response.etag == "\"a\"")
    #expect(await restartedTransport.requests.isEmpty)
  }

  @Test
  func restartRevalidatesAnExpiredDiskEntryWithItsValidator() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("caches/esi-responses.sqlite")
    _ = try await client(
      ScriptedTransport([
        .init(status: 200, body: "[1,2]", expires: start.addingTimeInterval(300), etag: "\"a\"")
      ]),
      store: ESIResponseDiskCache(url: url),
      at: start
    ).get([Int].self, endpoint: prices)

    let later = start.addingTimeInterval(7_200)
    let transport = ScriptedTransport([
      .init(status: 304, body: "", expires: later.addingTimeInterval(300), etag: "\"a\"")
    ])
    let response = try await client(
      transport,
      store: ESIResponseDiskCache(url: url),
      at: later
    ).get([Int].self, endpoint: prices)

    #expect(response.value == [1, 2])
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests.first?.value(forHTTPHeaderField: "If-None-Match") == "\"a\"")
    // The 304 renewed the durable expiry: a further restart stays local.
    let idle = ScriptedTransport([])
    _ = try await client(
      idle,
      store: ESIResponseDiskCache(url: url),
      at: later.addingTimeInterval(60)
    ).get([Int].self, endpoint: prices)
    #expect(await idle.requests.isEmpty)
  }

  @Test
  func bulkReadsStayInMemoryWhileStructureBooksAndTypeQuotesPersist() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("caches/esi-responses.sqlite")
    let fresh = ScriptedTransport.Reply(
      status: 200,
      body: "[]",
      expires: start.addingTimeInterval(300),
      etag: "\"x\""
    )
    let esi = client(
      ScriptedTransport(Array(repeating: fresh, count: 5)),
      store: ESIResponseDiskCache(url: url),
      at: start
    )
    for endpoint in [
      ESIEndpoint(
        path: "/markets/10000002/orders/",
        query: [URLQueryItem(name: "order_type", value: "all")]
      ),
      ESIEndpoint(path: "/contracts/public/10000002/"),
      ESIEndpoint(path: "/contracts/public/items/123/"),
      ESIEndpoint(
        path: "/markets/10000002/orders/",
        query: [
          URLQueryItem(name: "order_type", value: "all"),
          URLQueryItem(name: "type_id", value: "34"),
        ]
      ),
      ESIEndpoint(path: "/markets/structures/1035466617946/"),
    ] {
      _ = try await esi.get([Int].self, endpoint: endpoint)
    }

    #expect(await ESIResponseDiskCache(url: url).usage().entries == 2)
    #expect(
      ESIClient.persistsDurably(
        path: "/markets/10000002/orders/",
        query: [],
        partition: "public"
      ) == false
    )
    #expect(
      ESIClient.persistsDurably(
        path: "/markets/structures/1/",
        query: [],
        partition: "character:9"
      )
    )
  }

  @Test
  func disconnectingACharacterRemovesOnlyItsDurableResponses() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ESIResponseDiskCache(
      url: directory.appendingPathComponent("esi-responses.sqlite")
    )
    for key in [
      "character:1|https://esi.evetech.net/characters/1/assets/",
      "character:2|https://esi.evetech.net/characters/2/assets/",
      pricesKey,
    ] {
      await store.store(storedResponse("[1]"), forKey: key)
    }
    let esi = client(ScriptedTransport([]), store: store, at: start)

    await esi.removeCachedResponses(forCharacterID: 1)

    #expect(await store.usage().entries == 2)
    #expect(
      await store.response(
        forKey: "character:1|https://esi.evetech.net/characters/1/assets/"
      ) == nil
    )
    #expect(
      await store.response(
        forKey: "character:2|https://esi.evetech.net/characters/2/assets/"
      ) != nil
    )
  }

  @Test
  func sizeLimitEvictsTheLeastRecentlyUsedResponses() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = MutableClock(start)
    let store = ESIResponseDiskCache(
      url: directory.appendingPathComponent("esi-responses.sqlite"),
      maximumBytes: 1_300,
      now: { clock.now }
    )
    let body = String(repeating: "1", count: 400)
    for key in ["a", "b", "c"] {
      clock.now = clock.now.addingTimeInterval(1)
      await store.store(storedResponse(body), forKey: "public|\(key)")
    }
    clock.now = clock.now.addingTimeInterval(1)
    #expect(await store.response(forKey: "public|a") != nil)

    clock.now = clock.now.addingTimeInterval(1)
    await store.store(storedResponse(body), forKey: "public|d")

    // 1,600 bytes > 1,300: evict to at most 1,170 bytes, oldest access first.
    #expect(await store.response(forKey: "public|b") == nil)
    #expect(await store.response(forKey: "public|c") == nil)
    #expect(await store.response(forKey: "public|a") != nil)
    #expect(await store.response(forKey: "public|d") != nil)
    #expect(await store.usage().bytes == 800)
  }

  @Test
  func responsesOfAnotherCompatibilityDateAreDiscarded() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("esi-responses.sqlite")
    await ESIResponseDiskCache(url: url, compatibilityDate: "2025-01-01")
      .store(storedResponse("[1]"), forKey: pricesKey)

    let current = ESIResponseDiskCache(url: url)

    #expect(await current.response(forKey: pricesKey) == nil)
    #expect(await current.usage().entries == 0)
  }

  @Test
  func anUndecodableDurableBodyIsReplacedFromTheNetwork() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ESIResponseDiskCache(
      url: directory.appendingPathComponent("esi-responses.sqlite")
    )
    await store.store(storedResponse("not json"), forKey: pricesKey)
    let transport = ScriptedTransport([
      .init(status: 200, body: "[7]", expires: start.addingTimeInterval(300), etag: "\"b\"")
    ])

    let response = try await client(transport, store: store, at: start)
      .get([Int].self, endpoint: prices)

    #expect(response.value == [7])
    #expect(await transport.requests.count == 1)
    #expect(await store.response(forKey: pricesKey)?.data == Data("[7]".utf8))
  }

  @Test
  func anUnusableStoreLeavesRequestsWorking() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocker = directory.appendingPathComponent("blocker")
    try Data("file".utf8).write(to: blocker)
    let store = ESIResponseDiskCache(
      url: blocker.appendingPathComponent("esi-responses.sqlite")
    )
    let transport = ScriptedTransport([
      .init(status: 200, body: "[3]", expires: start.addingTimeInterval(300), etag: nil)
    ])

    let response = try await client(transport, store: store, at: start)
      .get([Int].self, endpoint: prices)

    #expect(response.value == [3])
    #expect(await store.usage().entries == 0)
  }

  @Test
  func pagesOfAnotherSnapshotAreRemovedDurably() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ESIResponseDiskCache(
      url: directory.appendingPathComponent("esi-responses.sqlite")
    )
    await store.store(storedResponse("[1]", lastModified: "new"), forKey: "public|p1")
    await store.store(storedResponse("[2]", lastModified: "old"), forKey: "public|p2")

    await store.removeResponses(
      forKeys: ["public|p1", "public|p2", "public|missing"],
      exceptLastModified: "new"
    )

    #expect(await store.response(forKey: "public|p1") != nil)
    #expect(await store.response(forKey: "public|p2") == nil)
  }

  private var prices: ESIEndpoint { ESIEndpoint(path: "/markets/prices/") }

  private func client(
    _ transport: ScriptedTransport,
    store: ESIResponseDiskCache,
    at date: Date
  ) -> ESIClient {
    ESIClient(transport: transport, responseStore: store, now: { date })
  }

  private func storedResponse(
    _ body: String,
    lastModified: String? = nil
  ) -> ESIStoredResponse {
    ESIStoredResponse(
      etag: "\"s\"",
      lastModified: lastModified,
      data: Data(body.utf8),
      expiresAt: start.addingTimeInterval(3_600),
      pages: nil,
      statusCode: 200,
      source: SourceIdentity(provider: "ESI", version: "2025-12-16", capturedAt: start)
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-esi-disk-cache-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    return url
  }
}

private final class MutableClock: @unchecked Sendable {
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

private actor ScriptedTransport: ESIHTTPTransporting {
  struct Reply: Sendable {
    let status: Int
    let body: String
    let expires: Date
    let etag: String?
  }

  private var replies: [Reply]
  private(set) var requests: [URLRequest] = []

  init(_ replies: [Reply]) {
    self.replies = replies
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
    let reply = replies.removeFirst()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    var headers = ["Expires": formatter.string(from: reply.expires)]
    if let etag = reply.etag { headers["ETag"] = etag }
    return (
      Data(reply.body.utf8),
      HTTPURLResponse(
        url: request.url!,
        statusCode: reply.status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
    )
  }
}
