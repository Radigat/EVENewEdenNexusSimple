import AppKit
import EVENexusCore
import SwiftUI
import WebKit

/// The owner's Allumis session (DOKTRIN_BEDARF_PLAN.md, section G): a
/// persistent WebKit data store of its own, separate from the wiki store, so
/// signing out of one source keeps the other. Allumis sets its session
/// cookie for 12 hours, so the session also survives an app restart within
/// that time. The app never sees or stores the password; the EVE SSO login
/// runs in the web view.
@MainActor
final class DoctrineAllumisSession {
  static let shared = DoctrineAllumisSession()

  /// Fixed identifier of the persistent data store; changing it would drop
  /// every existing sign-in.
  static let dataStoreIdentifier = UUID(uuidString: "C4F7A2D9-5B3E-4E61-8A0C-2D9F6B1E7A44")!

  let configuration = AllumisConfiguration.braveDoctrineMarket
  private(set) lazy var dataStore = WKWebsiteDataStore(
    forIdentifier: Self.dataStoreIdentifier
  )

  /// Unexpired cookies of the Allumis API host in the session store.
  func allumisCookies() async -> [HTTPCookie] {
    let host = configuration.host.lowercased()
    let now = Date()
    let cookies = await dataStore.httpCookieStore.allCookies()
    return cookies.filter { cookie in
      let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      let matchesHost = host == domain || host.hasSuffix("." + domain)
      return matchesHost && (cookie.expiresDate.map { $0 > now } ?? true)
    }
  }

  /// Whether the store holds an unexpired Allumis cookie; it says nothing
  /// about whether Allumis still accepts the session.
  func hasStoredSession() async -> Bool {
    !(await allumisCookies().isEmpty)
  }

  /// Removes every cookie and website data of the Allumis store.
  func signOut() async {
    await dataStore.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
      modifiedSince: .distantPast
    )
  }

  /// An importer that sends the session cookies with its request. The
  /// cookies are read once per import and only go to the Allumis API host.
  func importer(resolve: @escaping AllumisImporter.Resolve) async -> AllumisImporter {
    let headers = HTTPCookie.requestHeaderFields(with: await allumisCookies())
    let host = configuration.host.lowercased()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.httpShouldSetCookies = false
    sessionConfiguration.httpCookieAcceptPolicy = .never
    sessionConfiguration.timeoutIntervalForRequest = 60
    // Without a session Allumis redirects to its start page on another
    // host; that redirect would carry the cookies and is not followed.
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: DoctrineWikiSameHostRedirects(host: host),
      delegateQueue: nil
    )
    return AllumisImporter(
      configuration: configuration,
      fetch: { url in
        guard url.host?.lowercased() == host else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
          request.setValue(value, forHTTPHeaderField: field)
        }
        return try await session.data(for: request)
      },
      resolve: resolve
    )
  }
}

/// Runs the Allumis import independently of the page, like the wiki import.
@MainActor
@Observable
final class DoctrineAllumisImportController {
  static let shared = DoctrineAllumisImportController()

  private(set) var status = DoctrineImportStatus.idle
  /// Snapshot of the last successful import; it is already saved.
  private(set) var importedSnapshot: AllumisDoctrineSnapshot?
  /// Counts finished runs, so the page can take over each result.
  private(set) var finishedRuns = 0
  @ObservationIgnored private var task: Task<Void, Never>?

  func start(
    resolve: @escaping AllumisImporter.Resolve,
    save: @escaping @MainActor (AllumisDoctrineSnapshot) throws -> Void
  ) {
    guard !status.isRunning else { return }
    status = .running(nil)
    task = Task {
      status = await Self.run(resolve: resolve, save: save) { [weak self] snapshot in
        self?.importedSnapshot = snapshot
      }
      task = nil
      finishedRuns += 1
    }
  }

  func cancel() {
    task?.cancel()
  }

  private static func run(
    resolve: @escaping AllumisImporter.Resolve,
    save: @MainActor (AllumisDoctrineSnapshot) throws -> Void,
    onSuccess: @MainActor (AllumisDoctrineSnapshot) -> Void
  ) async -> DoctrineImportStatus {
    let importer = await DoctrineAllumisSession.shared.importer(resolve: resolve)
    let snapshot: AllumisDoctrineSnapshot
    do {
      snapshot = try await importer.run()
    } catch is CancellationError {
      return .idle
    } catch let error as AllumisImportError {
      switch error {
      case .notSignedIn:
        return .failed(
          AppLocalization.text(
            "Allumis did not deliver the doctrine table. Sign in to Allumis again; the session may have expired."
          )
        )
      case .httpStatus(let status):
        return .failed(
          AppLocalization.format("Allumis answered with HTTP status %lld.", Int64(status))
        )
      case .unreadableResponse:
        return .failed(
          AppLocalization.text("Allumis delivered the doctrine table in an unknown format.")
        )
      case .noFits:
        return .failed(AppLocalization.text("Allumis delivered no fit."))
      }
    } catch let error as URLError where error.code == .cancelled {
      return .idle
    } catch {
      return .failed(
        AppLocalization.format(
          "The Allumis data could not be imported: %@",
          error.localizedDescription
        )
      )
    }
    do {
      try save(snapshot)
    } catch {
      return .failed(
        AppLocalization.format(
          "The Allumis data could not be saved: %@",
          error.localizedDescription
        )
      )
    }
    onSuccess(snapshot)
    return .succeeded
  }
}

/// Sheet with the EVE SSO login of Allumis in a web view of its store.
struct DoctrineAllumisLoginSheet: View {
  let onFinish: () -> Void

  @State private var isSignedIn = false
  @State private var isLoading = true

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        Text("Sign in to Allumis")
          .appFont(.headline)
        if isLoading {
          ProgressView().controlSize(.small)
        }
        Spacer()
        if isSignedIn {
          Label("Signed in", systemImage: "checkmark.seal.fill")
            .foregroundStyle(DesignTokens.positive)
        }
        Button(isSignedIn ? "Done" : "Close", action: onFinish)
          .keyboardShortcut(isSignedIn ? .defaultAction : .cancelAction)
      }
      Text(
        "Sign in with EVE SSO as a member of Brave Collective or Brave United. The app does not see your password; it keeps the Allumis session in its own web storage, Allumis ends it after 12 hours. If EVE SSO remembers your account, signing in again takes one click."
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      DoctrineWikiWebView(
        url: DoctrineAllumisSession.shared.configuration.loginURL,
        dataStore: DoctrineAllumisSession.shared.dataStore,
        signInCheck: .allumis(DoctrineAllumisSession.shared.configuration),
        isSignedIn: $isSignedIn,
        isLoading: $isLoading
      )
      .frame(minWidth: 720, minHeight: 560)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(DesignTokens.textSecondary.opacity(0.3))
      )
    }
    .padding(DesignTokens.spacingMD)
  }
}
