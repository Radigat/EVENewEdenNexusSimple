import Foundation
import Network

public actor LoopbackCallbackServer {
  private var listener: NWListener?

  public init() {}

  public func waitForCallback(
    expectedState: String,
    timeout: Duration = .seconds(180)
  ) async throws -> URL {
    guard !expectedState.isEmpty, expectedState.utf8.count <= 256 else {
      throw AuthError.invalidCallback
    }
    guard
      let port = NWEndpoint.Port(
        rawValue: EVEConstants.callbackPort
      )
    else {
      throw AuthError.invalidCallback
    }
    let listener = try NWListener(using: .tcp, on: port)
    self.listener = listener
    return try await receive(
      from: listener,
      expectedState: expectedState,
      timeout: timeout
    )
  }

  public func cancel() {
    listener?.cancel()
    listener = nil
  }

  private func receive(
    from listener: NWListener,
    expectedState: String,
    timeout: Duration
  ) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let gate = CallbackContinuationGate()
      listener.newConnectionHandler = { connection in
        guard Self.isLoopback(connection.endpoint) else {
          connection.cancel()
          return
        }
        connection.start(queue: .global(qos: .userInitiated))
        let receiver = LoopbackHTTPRequestReceiver()
        receiver.receive(from: connection) { result in
          guard
            case .success(let request) = result,
            let url = LoopbackCallbackRequestParser.parse(
              request,
              expectedState: expectedState
            )
          else {
            Self.send(
              status: "400 Bad Request",
              body: "Invalid authorization callback.",
              to: connection
            )
            return
          }
          guard gate.claim() else { return }
          Self.send(
            status: "200 OK",
            body: "Authorization received. You can close this window.",
            to: connection
          )
          continuation.resume(returning: url)
          listener.cancel()
        }
      }
      listener.stateUpdateHandler = { state in
        if case .failed(let error) = state, gate.claim() {
          listener.cancel()
          continuation.resume(throwing: error)
        }
      }
      listener.start(queue: .global(qos: .userInitiated))
      let timeoutSeconds = min(
        300,
        max(1, timeout.components.seconds)
      )
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + .seconds(Int(timeoutSeconds))
      ) {
        if gate.claim() {
          listener.cancel()
          continuation.resume(throwing: CancellationError())
        }
      }
    }
  }

  private nonisolated static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
    guard case .hostPort(let host, _) = endpoint else { return false }
    return ["127.0.0.1", "::1", "localhost"].contains(
      String(describing: host).lowercased()
    )
  }

  private nonisolated static func send(
    status: String,
    body: String,
    to connection: NWConnection
  ) {
    let response =
      "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { _ in connection.cancel() }
    )
  }
}

enum LoopbackCallbackRequestParser {
  static func parse(_ request: String, expectedState: String) -> URL? {
    guard request.utf8.count <= LoopbackHTTPRequestReceiver.maximumBytes,
      let firstLine = request.components(separatedBy: "\r\n").first
    else { return nil }
    let parts = firstLine.split(
      separator: " ",
      maxSplits: 2,
      omittingEmptySubsequences: true
    )
    guard parts.count == 3,
      parts[0] == "GET",
      parts[2].hasPrefix("HTTP/1."),
      parts[1].hasPrefix("/"),
      !parts[1].hasPrefix("//"),
      let url = URL(
        string:
          "http://localhost:\(EVEConstants.callbackPort)\(parts[1])"
      ),
      let components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
      ),
      components.scheme == "http",
      components.host?.lowercased() == "localhost",
      components.port == Int(EVEConstants.callbackPort),
      components.path == EVEConstants.callbackURL.path,
      components.user == nil,
      components.password == nil,
      components.fragment == nil
    else { return nil }

    var fields: [String: String] = [:]
    for item in components.queryItems ?? [] {
      guard let value = item.value,
        value.utf8.count <= 4_096,
        fields[item.name] == nil
      else { return nil }
      fields[item.name] = value
    }
    guard fields["state"] == expectedState,
      (fields["code"] != nil) != (fields["error"] != nil)
    else { return nil }
    return url
  }
}

private final class LoopbackHTTPRequestReceiver: @unchecked Sendable {
  static let maximumBytes = 16_384
  private var buffer = Data()

  func receive(
    from connection: NWConnection,
    completion: @escaping @Sendable (Result<String, Error>) -> Void
  ) {
    connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: 4_096
    ) { [self] data, _, isComplete, error in
      if let error {
        completion(.failure(error))
        return
      }
      if let data {
        buffer.append(data)
      }
      guard buffer.count <= Self.maximumBytes else {
        completion(.failure(AuthError.invalidCallback))
        return
      }
      if buffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
        guard let request = String(data: buffer, encoding: .utf8) else {
          completion(.failure(AuthError.invalidCallback))
          return
        }
        completion(.success(request))
        return
      }
      receive(from: connection, completion: completion)
    }
  }
}

private final class CallbackContinuationGate: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !completed else { return false }
    completed = true
    return true
  }
}
