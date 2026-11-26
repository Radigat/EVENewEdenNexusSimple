import Foundation

// Doctrine stock (DOKTRIN_BEDARF_PLAN.md): reading the doctrine and ship
// pages of the wiki with the owner's signed-in session. Fetching is
// injected, so the run is testable without network or session.

public enum DoctrineWikiImportError: Error, Equatable, Sendable {
  /// The doctrine index is empty or no page could be read: the session is
  /// missing, expired or lacks access to the member area.
  case notSignedIn
  /// The wiki answered the doctrine index with this HTTP status.
  case httpStatus(Int)
}

public struct DoctrineWikiImportProgress: Equatable, Sendable {
  public let completed: Int
  public let total: Int

  public init(completed: Int, total: Int) {
    self.completed = completed
    self.total = total
  }
}

public struct DoctrineWikiImporter: Sendable {
  public typealias Fetch = @Sendable (URL) async throws -> (Data, URLResponse)
  public typealias Resolve =
    @Sendable ([String]) async throws -> [String: ItemTypeNameResolution]
  public typealias Progress = @Sendable (DoctrineWikiImportProgress) async -> Void

  public let configuration: DoctrineWikiConfiguration
  /// Pause between two page requests, to spare the wiki.
  public let pause: Duration
  private let fetch: Fetch
  private let resolve: Resolve

  public init(
    configuration: DoctrineWikiConfiguration = .braveCollective,
    pause: Duration = .milliseconds(80),
    fetch: @escaping Fetch,
    resolve: @escaping Resolve
  ) {
    self.configuration = configuration
    self.pause = pause
    self.fetch = fetch
    self.resolve = resolve
  }

  /// Reads both indexes, every doctrine and ship page, resolves the names
  /// against the SDE and builds the library. Pages that cannot be read are
  /// listed as issues; when none can be read the session is not valid.
  public func run(
    now: @Sendable () -> Date = Date.init,
    progress: Progress = { _ in }
  ) async throws -> DoctrineLibrary {
    let doctrineIDs = try await index(configuration.doctrineNamespace)
      .filter { $0 != configuration.doctrineNamespace + ":start" }
    guard !doctrineIDs.isEmpty else { throw DoctrineWikiImportError.notSignedIn }
    let shipIDs = try await index(configuration.shipNamespace)
      .filter { $0 != configuration.shipNamespace + ":start" }

    let pageIDs = doctrineIDs + shipIDs
    var pages: [String: DokuWikiPage] = [:]
    var unreadable: [String] = []
    await progress(DoctrineWikiImportProgress(completed: 0, total: pageIDs.count))
    for (offset, pageID) in pageIDs.enumerated() {
      try Task.checkCancellation()
      if offset > 0, pause > .zero { try await Task.sleep(for: pause) }
      if let raw = try await rawPage(pageID) {
        pages[pageID] = DokuWikiRawParser.parse(raw, pageID: pageID)
      } else {
        unreadable.append(pageID)
      }
      await progress(DoctrineWikiImportProgress(completed: offset + 1, total: pageIDs.count))
    }
    guard !pages.isEmpty else { throw DoctrineWikiImportError.notSignedIn }

    let doctrinePages = doctrineIDs.compactMap { pages[$0] }
    let shipPages = shipIDs.compactMap { pages[$0] }
    let names = DoctrineLibraryBuilder.itemNames(in: doctrinePages + shipPages)
    let resolutions = try await resolve(names.sorted())
    return DoctrineLibraryBuilder.build(
      configuration: configuration,
      doctrinePages: doctrinePages,
      shipPages: shipPages,
      resolutions: resolutions,
      unreadablePageIDs: unreadable,
      importedAt: now()
    )
  }

  private func index(_ namespace: String) async throws -> [String] {
    let (data, response) = try await fetch(configuration.indexURL(namespace: namespace))
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw DoctrineWikiImportError.httpStatus(http.statusCode)
    }
    return DokuWikiIndexParser.pageIDs(
      inNamespace: namespace,
      html: String(decoding: data, as: UTF8.self)
    )
  }

  /// Raw markup, or nil when the wiki does not deliver plain text (an
  /// error, a missing page or a login page instead of the export).
  private func rawPage(_ pageID: String) async throws -> String? {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await fetch(configuration.rawURL(pageID: pageID))
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return nil
    }
    if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
    guard response.mimeType?.lowercased() == "text/plain" else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}
