import AppKit
import Combine
import EVENexusCore
import ServiceManagement
import SwiftUI

/// Background operation (MARKTBESTAND_PLAN P4): keep running without a
/// window, a menu bar item and the optional start at login. Owner decisions
/// 29.10.2026: keep running is on and start at login off by default; without
/// a window the Dock icon is hidden; the menu bar item exists only while
/// keep running is on.
enum BackgroundOperation {
  static let keepRunningStorageKey = "background.keep-running"
  static let keepRunningDefault = true
  static let mainWindowID = "main"

  static var keepsRunning: Bool {
    AppDefaults.store.object(forKey: keepRunningStorageKey) as? Bool
      ?? keepRunningDefault
  }

  /// `.accessory` hides the Dock icon while only the menu bar item remains.
  static func activationPolicy(
    keepsRunning: Bool,
    hasVisibleMainWindow: Bool
  ) -> NSApplication.ActivationPolicy {
    keepsRunning && !hasVisibleMainWindow ? .accessory : .regular
  }

  /// macOS marks the launch event of a login item with
  /// `keyAELaunchedAsLogInItem`.
  static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event, event.eventID == AEEventID(kAEOpenApplication) else {
      return false
    }
    return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
      .enumCodeValue == OSType(keyAELaunchedAsLogInItem)
  }

  /// The app's standard windows; menu bar menus and panels do not count.
  @MainActor
  static var mainWindows: [NSWindow] {
    NSApp.windows.filter {
      $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.canBecomeMain
    }
  }

  /// Brings an existing main window back or opens a new one.
  @MainActor
  static func showMainWindow(openWindow: OpenWindowAction) {
    AppBackgroundDelegate.shared?.cancelLoginLaunchHiding()
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    if let window = mainWindows.first {
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: mainWindowID)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// Login item status as shown in the settings.
enum LoginItemPresentation: Equatable {
  case enabled
  case requiresApproval
  case disabled
  case unavailable

  init(_ status: SMAppService.Status) {
    switch status {
    case .enabled: self = .enabled
    case .requiresApproval: self = .requiresApproval
    case .notRegistered: self = .disabled
    case .notFound: self = .unavailable
    @unknown default: self = .unavailable
    }
  }

  var isOn: Bool { self == .enabled || self == .requiresApproval }

  var text: LocalizedStringKey {
    switch self {
    case .enabled: "The app starts hidden when you log in."
    case .requiresApproval:
      "Registered, but macOS still needs your approval in System Settings → General → Login Items."
    case .disabled: "The app does not start at login."
    case .unavailable:
      "macOS cannot register this copy of the app as a login item. Start it from the Applications folder and try again."
    }
  }
}

/// Window, Dock and termination behavior of the background operation.
@MainActor
final class AppBackgroundDelegate: NSObject, NSApplicationDelegate {
  static weak var shared: AppBackgroundDelegate?
  /// Set by the app before its scenes are created.
  static weak var runtime: RuntimeState?

  private var observers: [NSObjectProtocol] = []
  private var startupObservation: AnyCancellable?
  private var hidesWindowsForLoginLaunch = false

  override init() {
    super.init()
    Self.shared = self
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    hidesWindowsForLoginLaunch = BackgroundOperation.isLoginItemLaunch(
      NSAppleEventManager.shared().currentAppleEvent
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let center = NotificationCenter.default
    for name in [
      NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification,
      NSWindow.didMiniaturizeNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated {
            AppBackgroundDelegate.shared?.windowsChanged()
          }
        }
      )
    }
    guard hidesWindowsForLoginLaunch else { return }
    // Login launch: no visible window. The window exists hidden only until
    // the startup load (character sync, configuration, automatic scans) has
    // run, then it is closed so no view data stays in memory.
    NSApp.setActivationPolicy(.accessory)
    NSApp.hide(nil)
    BackgroundOperation.mainWindows.forEach { $0.orderOut(nil) }
    startupObservation = Self.runtime?.startupDataLoad.$phase
      .receive(on: RunLoop.main)
      .sink { phase in
        MainActor.assumeIsolated {
          AppBackgroundDelegate.shared?.startupPhaseChanged(phase)
        }
      }
  }

  func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    !BackgroundOperation.keepsRunning
  }

  /// The user opened the window during a login launch: keep it.
  func cancelLoginLaunchHiding() {
    hidesWindowsForLoginLaunch = false
    startupObservation = nil
  }

  private func startupPhaseChanged(_ phase: StartupDataLoad.Phase) {
    guard hidesWindowsForLoginLaunch,
      phase == .completed || phase == .cancelled
    else { return }
    cancelLoginLaunchHiding()
    // Without keep running, closing the last window would quit the app;
    // the hidden window then stays.
    guard BackgroundOperation.keepsRunning else { return }
    BackgroundOperation.mainWindows.forEach { $0.close() }
  }

  private func windowsChanged() {
    if hidesWindowsForLoginLaunch {
      // SwiftUI may show the window after launch; keep it hidden.
      BackgroundOperation.mainWindows.forEach { $0.orderOut(nil) }
      return
    }
    // A closing window is still listed; decide on the next run loop pass.
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        let hasVisibleMainWindow = BackgroundOperation.mainWindows.contains {
          $0.isVisible && !$0.isMiniaturized
        }
        let policy = BackgroundOperation.activationPolicy(
          keepsRunning: BackgroundOperation.keepsRunning,
          hasVisibleMainWindow: hasVisibleMainWindow
            || BackgroundOperation.mainWindows.contains(where: \.isMiniaturized)
        )
        if NSApp.activationPolicy() != policy {
          NSApp.setActivationPolicy(policy)
        }
      }
    }
  }
}

/// Menu bar item while keep running is on.
struct BackgroundMenuBarContent: View {
  let runtime: RuntimeState
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open window") {
      BackgroundOperation.showMainWindow(openWindow: openWindow)
    }
    Divider()
    Text(lastPointText)
    Text(nextTermText)
    Button("Fetch market stock now") {
      runtime.requestMarketStockScanNow()
    }
    // Only when a new point would be stored and the order books have
    // expired (owner request 29.10.2026).
    .disabled(
      runtime.isAnalyzingManufacturingOpportunities
        || runtime.marketStockScanAvailableAt != nil
    )
    if let availableAt = runtime.marketStockScanAvailableAt {
      Text(
        AppLocalization.format(
          "Fetching possible from %@",
          availableAt.formatted(date: .omitted, time: .shortened)
        )
      )
    }
    Divider()
    Button("Quit") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }

  private var lastPointText: String {
    if runtime.isAnalyzingManufacturingOpportunities {
      return AppLocalization.text("Hub markets are being updated")
    }
    guard let latest = runtime.marketStockLatestPointAt.values.max() else {
      return AppLocalization.text("No market stock point yet")
    }
    return AppLocalization.format(
      "Last market stock point %@",
      latest.formatted(date: .abbreviated, time: .shortened)
    )
  }

  private var nextTermText: String {
    guard runtime.mainHubMarketAutomaticUpdatesEnabled else {
      return AppLocalization.text("Automatic updates paused")
    }
    if runtime.isMarketStockWaitingForESI {
      return AppLocalization.text("Next term waits for ESI")
    }
    guard let next = runtime.marketStockNextTermAt else {
      return AppLocalization.text("No term planned")
    }
    return AppLocalization.format(
      "Next term %@",
      next.formatted(date: .abbreviated, time: .shortened)
    )
  }
}

/// Settings panel under Data & Settings → General.
struct BackgroundOperationPanel: View {
  @AppStorage(BackgroundOperation.keepRunningStorageKey, store: AppDefaults.store)
  private var keepsRunning = BackgroundOperation.keepRunningDefault
  @State private var loginItem = LoginItemPresentation(SMAppService.mainApp.status)
  @State private var loginItemError: String?

  var body: some View {
    Panel(title: "Background operation") {
      Toggle("Keep running after the window closes", isOn: $keepsRunning)
        .accessibilityIdentifier("general.background.keep-running")
      Text(
        "The app then stays in the menu bar without a Dock icon and keeps the fixed market stock terms (06:00 and 13:00) and the automatic hub scans running. When switched off, closing the window quits the app."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Toggle("Start at login", isOn: loginItemBinding)
        .accessibilityIdentifier("general.background.start-at-login")
      Label(loginItem.text, systemImage: loginItemSymbol)
        .font(.caption)
        .foregroundStyle(
          loginItem == .enabled || loginItem == .disabled
            ? DesignTokens.textSecondary : DesignTokens.caution
        )
      if loginItem == .requiresApproval {
        Button("Open Login Items settings") {
          SMAppService.openSystemSettingsLoginItems()
        }
      }
      if let loginItemError {
        Text(loginItemError)
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }
      Text(
        "A Mac in sleep misses a term; the app catches up once after waking. No term wakes the Mac."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
    .onAppear { refreshLoginItem() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      refreshLoginItem()
    }
  }

  private var loginItemSymbol: String {
    switch loginItem {
    case .enabled: "checkmark.circle"
    case .disabled: "circle"
    case .requiresApproval, .unavailable: "exclamationmark.triangle"
    }
  }

  private var loginItemBinding: Binding<Bool> {
    Binding(
      get: { loginItem.isOn },
      set: { enabled in
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          loginItemError = nil
        } catch {
          loginItemError = AppLocalization.format(
            "macOS refused the change: %@",
            error.localizedDescription
          )
        }
        refreshLoginItem()
      }
    )
  }

  private func refreshLoginItem() {
    loginItem = LoginItemPresentation(SMAppService.mainApp.status)
  }
}
