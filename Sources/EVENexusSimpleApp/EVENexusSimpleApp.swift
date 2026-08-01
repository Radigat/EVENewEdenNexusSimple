import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

@main
struct EVENexusSimpleApp: App {
  @StateObject private var runtime: RuntimeState
  @AppStorage(AppLanguage.storageKey)
  private var storedLanguage = AppLanguage.defaultLanguage.rawValue
  private let modelContainer: ModelContainer?
  private let persistenceFolderURL: URL?

  init() {
    let paths = try? AppDataPaths.live()
    persistenceFolderURL = paths?.swiftDataStoreURL.deletingLastPathComponent()
    _runtime = StateObject(
      wrappedValue: RuntimeState(dataRoot: paths?.dataRoot)
    )
    modelContainer = paths.flatMap { try? AppPersistence.open(paths: $0) }
  }

  private var appLanguage: AppLanguage {
    AppLanguage(rawValue: storedLanguage) ?? .english
  }

  var body: some Scene {
    WindowGroup {
      if let modelContainer {
        ContentView()
          .environmentObject(runtime)
          .environment(\.locale, appLanguage.locale)
          .preferredColorScheme(.dark)
          .modelContainer(modelContainer)
      } else {
        PersistenceUnavailableView(folderURL: persistenceFolderURL)
          .environment(\.locale, appLanguage.locale)
          .preferredColorScheme(.dark)
      }
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 1_280, height: 820)
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
    .frame(minWidth: 620, maxWidth: 760, alignment: .leading)
  }
}
