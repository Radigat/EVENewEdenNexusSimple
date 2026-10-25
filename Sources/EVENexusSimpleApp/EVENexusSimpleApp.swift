import AppKit
import Darwin
import EVENexusCore
import SwiftData
import SwiftUI

@main
@MainActor
enum EVENexusApplicationEntry {
  private static var persistenceLock: PersistenceProcessLock?
  static func main() {
    if FullStoreRecovery.handleValidatorInvocation() { return }
    do {
      try DevelopmentAppBootstrap.configurePaths()
      let paths = try AppDataPaths.live()
      persistenceLock = try PersistenceProcessLock(paths: paths)
      FullStoreRecovery.processLock = persistenceLock
      try StoreFullRestore.recoverInterrupted(paths: paths)
      if try FullStoreRecovery.runPending(paths: paths) { exit(0) }
      try DevelopmentAppBootstrap.prepare()
    } catch {
      if ProcessInfo.processInfo.environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1" {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      } else {
        let alert = NSAlert()
        alert.messageText = "EVE New Eden Nexus - Assets, Industry, Markets – DEV"
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
      exit(1)
    }
    EVENexusSimpleApp.main()
  }
}

struct EVENexusSimpleApp: App {
  @StateObject private var consolidation = ConsolidationController()
  @StateObject private var runtimeOwner: RuntimeStateOwner
  @AppStorage(AppLanguage.storageKey, store: AppDefaults.store)
  private var storedLanguage = AppLanguage.defaultLanguage.rawValue
  @AppStorage(AppTextSize.storageKey, store: AppDefaults.store)
  private var storedTextSize = AppTextSize.standard.rawValue
  @AppStorage(AppAppearanceStyle.storageKey, store: AppDefaults.store)
  private var storedAppearance = AppAppearanceStyle.system.rawValue
  private let modelContainer: ModelContainer?
  private let persistenceFolderURL: URL?

  init() {
    AppDefaults.migrateLegacyDomainsIfNeeded()
    let paths = try? AppDataPaths.live()
    persistenceFolderURL = paths?.swiftDataStoreURL.deletingLastPathComponent()
    let openedModelContainer = paths.flatMap {
      try? AppPersistence.open(paths: $0)
    }
    modelContainer = openedModelContainer
    let legacyOwnerContact = openedModelContainer.flatMap {
      Self.ccpUserAgentOwnerContact(in: $0)
    }
    let ownerContact = AppOperatorConfiguration.ccpUserAgentContact(
      legacyLocalValue: legacyOwnerContact
    )
    let environment = ProcessInfo.processInfo.environment
    let startsBackgroundServices =
      openedModelContainer != nil
      && environment["EVE_NEXUS_DISABLE_BACKGROUND_SERVICES"] != "1"
    _runtimeOwner = StateObject(
      wrappedValue: RuntimeStateOwner(
        runtime: RuntimeState(
          dataRoot: paths?.dataRoot,
          ccpUserAgentOwnerContact: ownerContact,
          startBackgroundServices: startsBackgroundServices
        )
      )
    )
    if environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1" {
      exit(openedModelContainer == nil ? 2 : 0)
    }
  }

  private static func ccpUserAgentOwnerContact(
    in modelContainer: ModelContainer
  ) -> String? {
    let key = AppSettingKey.ccpUserAgentOwnerContact
    let descriptor = FetchDescriptor<AppSetting>(
      predicate: #Predicate { $0.key == key }
    )
    return try? modelContainer.mainContext.fetch(descriptor).first?.value
  }

  private var appLanguage: AppLanguage {
    AppLanguage(rawValue: storedLanguage) ?? .english
  }

  private var appTextSize: AppTextSize {
    AppTextSize(rawValue: storedTextSize) ?? .standard
  }

  private var appAppearance: AppAppearanceStyle {
    AppAppearanceStyle(rawValue: storedAppearance) ?? .system
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if let modelContainer {
          ContentView(runtime: runtimeOwner.runtime)
            .environmentObject(consolidation)
            .task {
              do { try consolidation.start(container: modelContainer) } catch {
                consolidation.error = error.localizedDescription
              }
            }
            .environment(runtimeOwner.runtime)
            .environment(\.locale, appLanguage.locale)
            .environment(\.dynamicTypeSize, appTextSize.dynamicTypeSize)
            .preferredColorScheme(appAppearance.preferredColorScheme)
            .defaultAppStorage(AppDefaults.store)
            .modelContainer(modelContainer)
        } else {
          PersistenceUnavailableView(folderURL: persistenceFolderURL)
            .environment(\.locale, appLanguage.locale)
            .environment(\.dynamicTypeSize, appTextSize.dynamicTypeSize)
            .preferredColorScheme(appAppearance.preferredColorScheme)
            .defaultAppStorage(AppDefaults.store)
        }
      }
      .background(InitialWindowMaximizer())
      .background(InactiveWindowToolTips())
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 1_180, height: 760)
    .commands {
      TextSizeCommands()
      CommandMenu(AppLocalization.text("Data recovery")) {
        Button(AppLocalization.text("Fully restore earlier data…")) {
          FullStoreRecovery.requestAndQuit(paths: try? AppDataPaths.live(), context: modelContainer?.mainContext)
        }
      }
    }
  }
}

/// Expands each newly created app window once, while leaving later user-driven
/// resizing untouched.
struct InitialWindowMaximizer: NSViewRepresentable {
  func makeNSView(context: Context) -> InitialWindowMaximizerView {
    InitialWindowMaximizerView()
  }

  func updateNSView(
    _ nsView: InitialWindowMaximizerView,
    context: Context
  ) {}
}

@MainActor
final class InitialWindowMaximizerView: NSView {
  private var maximization = InitialWindowMaximization()

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }

    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window else { return }
      self.maximization.apply(to: window)
    }
  }
}

/// Shows help tooltips while another app is active. AppKit otherwise shows
/// them only in the active app, so hovering the window next to another app
/// never revealed any explanation.
struct InactiveWindowToolTips: NSViewRepresentable {
  func makeNSView(context: Context) -> InactiveWindowToolTipsView {
    InactiveWindowToolTipsView()
  }

  func updateNSView(
    _ nsView: InactiveWindowToolTipsView,
    context: Context
  ) {}
}

@MainActor
final class InactiveWindowToolTipsView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.allowsToolTipsWhenApplicationIsInactive = true
  }
}

@MainActor
struct InitialWindowMaximization {
  private(set) var hasApplied = false

  mutating func apply(to window: NSWindow) {
    guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
      return
    }
    apply(to: window, visibleFrame: visibleFrame)
  }

  mutating func apply(to window: NSWindow, visibleFrame: NSRect) {
    guard !hasApplied else { return }
    hasApplied = true
    window.setFrame(visibleFrame, display: true)
  }
}

/// Owns the runtime for the app's lifetime without subscribing the scene to
/// it. RuntimeState uses Observation, so a view is invalidated only by the
/// runtime properties its body actually reads.
@MainActor
private final class RuntimeStateOwner: ObservableObject {
  let runtime: RuntimeState

  init(runtime: RuntimeState) {
    self.runtime = runtime
  }
}

private struct PersistenceUnavailableView: View {
  let folderURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        "Stored data could not be opened safely",
        systemImage: "externaldrive.badge.exclamationmark"
      )
      .font(.title2.bold())
      Text(
        "The app did not create an empty replacement database and did not delete existing data. Quit the app and back up the data folder before attempting a repair or migration."
      )
      .fixedSize(horizontal: false, vertical: true)
      Button(AppLocalization.text("Fully restore earlier data…")) {
        FullStoreRecovery.requestAndQuit(paths: try? AppDataPaths.live(), context: nil)
      }
      if let folderURL {
        Text(folderURL.path)
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Button("Show data folder in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        }
      }
    }
    .padding(32)
    .frame(minWidth: 420, maxWidth: 760, alignment: .leading)
  }
}
