import AppKit
import EVENexusCore
import SwiftUI
import WebKit

/// The owner's alliance-wiki session (DOKTRIN_BEDARF_PLAN.md): a persistent
/// WebKit data store of its own, which keeps what the sites store like a
/// browser and which “Sign out” removes exactly. The wiki and Brave Core set
/// session cookies only, so the wiki session ends when the app quits; EVE SSO
/// can remember the account, then signing in again takes one click
/// (checked 26.11.2026). The app never sees or stores the password; the
/// wiki's login flow runs in the web view.
@MainActor
final class DoctrineWikiSession {
  static let shared = DoctrineWikiSession()

  /// Fixed identifier of the persistent data store; changing it would drop
  /// every existing sign-in.
  static let dataStoreIdentifier = UUID(uuidString: "6B1E7D52-3C1A-4C3E-9B0D-5D4A7E2F9A10")!

  let configuration = DoctrineWikiConfiguration.braveCollective
  private(set) lazy var dataStore = WKWebsiteDataStore(
    forIdentifier: Self.dataStoreIdentifier
  )

  /// Cookies of the wiki host in the session store.
  func wikiCookies() async -> [HTTPCookie] {
    let host = configuration.host.lowercased()
    let cookies = await dataStore.httpCookieStore.allCookies()
    return cookies.filter { cookie in
      let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      return host == domain || host.hasSuffix("." + domain)
    }
  }

  /// Whether the store holds any cookie of the wiki; it says nothing about
  /// whether the session is still valid.
  func hasStoredSession() async -> Bool {
    !(await wikiCookies().isEmpty)
  }

  /// Removes every cookie and website data of the session store.
  func signOut() async {
    await dataStore.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
      modifiedSince: .distantPast
    )
  }

  /// An importer that sends the session cookies with every request. The
  /// cookies are read once per import and only go to the wiki host.
  func importer(
    resolve: @escaping DoctrineWikiImporter.Resolve
  ) async -> DoctrineWikiImporter {
    let headers = HTTPCookie.requestHeaderFields(with: await wikiCookies())
    let host = configuration.host.lowercased()
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.httpShouldSetCookies = false
    sessionConfiguration.httpCookieAcceptPolicy = .never
    sessionConfiguration.timeoutIntervalForRequest = 30
    // A redirect keeps the request's headers, so one to another host would
    // carry the wiki cookies there; such a redirect is not followed.
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: DoctrineWikiSameHostRedirects(host: host),
      delegateQueue: nil
    )
    return DoctrineWikiImporter(
      configuration: configuration,
      fetch: { url in
        guard url.host?.lowercased() == host else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        for (field, value) in headers {
          request.setValue(value, forHTTPHeaderField: field)
        }
        return try await session.data(for: request)
      },
      resolve: resolve
    )
  }
}

/// Follows a redirect only within one host (wiki or Allumis). A refused
/// redirect hands the 3xx response to the importer, which treats it as an
/// unreadable page or a missing session.
final class DoctrineWikiSameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  let host: String

  init(host: String) {
    self.host = host
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    request.url?.host?.lowercased() == host ? request : nil
  }
}

/// Runs the wiki import independently of the page: leaving the page does not
/// stop it, only “Cancel” does. The page shows its status and takes over the
/// saved result.
@MainActor
@Observable
final class DoctrineWikiImportController {
  static let shared = DoctrineWikiImportController()

  private(set) var status = DoctrineImportStatus.idle
  /// Library of the last successful import; it is already saved.
  private(set) var importedLibrary: DoctrineLibrary?
  /// Counts finished runs, so the page can take over each result.
  private(set) var finishedRuns = 0
  @ObservationIgnored private var task: Task<Void, Never>?

  func start(
    resolve: @escaping DoctrineWikiImporter.Resolve,
    save: @escaping @MainActor (DoctrineLibrary) throws -> Void
  ) {
    guard !status.isRunning else { return }
    status = .running(nil)
    task = Task {
      status = await Self.run(resolve: resolve, save: save) { [weak self] progress in
        await self?.updateProgress(progress)
      } onSuccess: { [weak self] library in
        self?.importedLibrary = library
      }
      task = nil
      finishedRuns += 1
    }
  }

  func cancel() {
    task?.cancel()
  }

  private func updateProgress(_ progress: DoctrineWikiImportProgress) {
    guard status.isRunning else { return }
    status = .running(progress)
  }

  private static func run(
    resolve: @escaping DoctrineWikiImporter.Resolve,
    save: @MainActor (DoctrineLibrary) throws -> Void,
    progress: @escaping DoctrineWikiImporter.Progress,
    onSuccess: @MainActor (DoctrineLibrary) -> Void
  ) async -> DoctrineImportStatus {
    let importer = await DoctrineWikiSession.shared.importer(resolve: resolve)
    let library: DoctrineLibrary
    do {
      library = try await importer.run(progress: progress)
    } catch is CancellationError {
      return .idle
    } catch let error as DoctrineWikiImportError {
      switch error {
      case .notSignedIn:
        return .failed(
          AppLocalization.text(
            "The wiki did not deliver the doctrine pages. Sign in to the wiki again; the session may have expired."
          )
        )
      case .httpStatus(let status):
        return .failed(
          AppLocalization.format("The wiki answered with HTTP status %lld.", Int64(status))
        )
      }
    } catch let error as URLError where error.code == .cancelled {
      return .idle
    } catch {
      return .failed(
        AppLocalization.format(
          "The doctrines could not be imported: %@",
          error.localizedDescription
        )
      )
    }
    do {
      try save(library)
    } catch {
      return .failed(
        AppLocalization.format(
          "The imported doctrines could not be saved: %@",
          error.localizedDescription
        )
      )
    }
    onSuccess(library)
    return .succeeded
  }
}

/// Sheet with the wiki's own login page in a web view of the session store.
struct DoctrineWikiLoginSheet: View {
  let onFinish: () -> Void

  @State private var isSignedIn = false
  @State private var isLoading = true
  @State private var pageTitle = ""

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        Text("Sign in to the alliance wiki")
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
        "Sign in with the wiki's own login (Brave Core, EVE SSO). The app does not see your password; it keeps the wiki session in its own web storage until the app quits. If EVE SSO remembers your account, signing in again takes one click."
      )
      .appFont(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      DoctrineWikiWebView(
        url: DoctrineWikiSession.shared.configuration.loginURL,
        dataStore: DoctrineWikiSession.shared.dataStore,
        signInCheck: .dokuWiki(host: DoctrineWikiSession.shared.configuration.host),
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

/// How the login sheet recognizes a signed-in page.
enum DoctrineSignInCheck {
  /// DokuWiki marks a signed-in page with the body class `loggedIn`.
  case dokuWiki(host: String)
  /// Allumis shows member pages under `/user` only with a session.
  case allumis(AllumisConfiguration)
}

/// WKWebView of a session store. Links that open a new window load in the
/// same view, so the SSO redirects stay inside the sheet.
struct DoctrineWikiWebView: NSViewRepresentable {
  let url: URL
  let dataStore: WKWebsiteDataStore
  let signInCheck: DoctrineSignInCheck
  @Binding var isSignedIn: Bool
  @Binding var isLoading: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(signInCheck: signInCheck, isSignedIn: $isSignedIn, isLoading: $isLoading)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.uiDelegate = context.coordinator
    view.load(URLRequest(url: url))
    return view
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let signInCheck: DoctrineSignInCheck
    private var isSignedIn: Binding<Bool>
    private var isLoading: Binding<Bool>

    init(signInCheck: DoctrineSignInCheck, isSignedIn: Binding<Bool>, isLoading: Binding<Bool>) {
      self.signInCheck = signInCheck
      self.isSignedIn = isSignedIn
      self.isLoading = isLoading
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      isLoading.wrappedValue = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isLoading.wrappedValue = false
      let host: String
      switch signInCheck {
      case .allumis(let configuration):
        isSignedIn.wrappedValue = configuration.isSignedInPage(webView.url)
        return
      case .dokuWiki(let wikiHost):
        host = wikiHost.lowercased()
      }
      // DokuWiki marks a signed-in page with the body class `loggedIn`.
      guard webView.url?.host?.lowercased() == host else { return }
      webView.evaluateJavaScript(
        "document.body ? document.body.classList.contains('loggedIn') : false"
      ) { [weak self] result, _ in
        guard let self else { return }
        let signedIn = (result as? Bool) ?? false
        Task { @MainActor in self.isSignedIn.wrappedValue = signedIn }
      }
    }

    func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      isLoading.wrappedValue = false
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      isLoading.wrappedValue = false
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }
  }
}
