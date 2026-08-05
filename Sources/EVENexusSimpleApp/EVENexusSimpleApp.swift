import AppKit
import Darwin
import EVENexusCore
import SwiftData
import SwiftUI

@main
struct EVENexusSimpleApp: App {
  @StateObject private var runtime: RuntimeState
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
    _runtime = StateObject(
      wrappedValue: RuntimeState(
        dataRoot: paths?.dataRoot,
        ccpUserAgentOwnerContact: ownerContact,
        startBackgroundServices: startsBackgroundServices
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
      if let modelContainer {
        ContentView()
          .environmentObject(runtime)
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
    .windowStyle(.titleBar)
    .defaultSize(width: 1_180, height: 760)
    .commands {
      TextSizeCommands()
    }
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
