import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

enum ConsolidationPreferences {
  static var domain: String {
    ProcessInfo.processInfo.environment["EVE_NEXUS_USER_DEFAULTS_SUITE"]
      ?? AppDataPaths.applicationIdentifier
  }
  static func encoded() throws -> Data {
    let values = AppDefaults.store.persistentDomain(forName: domain) ?? [:]
    return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
  }
  @MainActor static func applyPending(paths: AppDataPaths) throws {
    guard
      NSRunningApplication.runningApplications(
        withBundleIdentifier: AppDataPaths.applicationIdentifier
      ).count <= 1
    else {
      // Opening the existing app is fine; only replacing an open store is forbidden.
      if FileManager.default.fileExists(
        atPath: paths.applicationSupportRoot.appendingPathComponent(".eve-restore-request").path)
      {
        throw ConsolidationError.invalid(
          "Vor der Wiederherstellung alle anderen Instanzen dieser App schließen.")
      }
      return
    }
    if let data = try ConsolidationBackup.applyPendingRestore(
      paths: paths, defaults: encoded(), schema: AppPersistence.schemaVersion),
      let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as? [String: Any]
    {
      AppDefaults.store.setPersistentDomain(values, forName: domain)
    }
  }
}

struct ConsolidationBackupView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var context
  @State private var busy = false
  @State private var message: String?
  @State private var restoreURL: URL?
  @State private var confirmRestore = false
  var body: some View {
    Panel(title: "Sicherung & Wiederherstellung") {
      Text(
        "Die Sicherung enthält lokale Anwendungsdaten, Einstellungen und installierte Datenkataloge. Anmeldeschlüssel verbleiben im macOS-Schlüsselbund."
      )
      Button("Vollständige lokale Sicherung erstellen") { create() }.disabled(busy)
      Button("Sicherung prüfen") { verify(restore: false) }.disabled(busy)
      Button("Wiederherstellung vorbereiten") { verify(restore: true) }.disabled(busy)
      Text(
        "Eine bestätigte Wiederherstellung wird beim nächsten App-Start durchgeführt. Zuvor wird der aktuelle Bestand zusätzlich gesichert. Alte Nexus-Datenbanken werden nicht importiert."
      ).font(.caption)
      Button("Anonymisierte Diagnose exportieren") { diagnostics() }
      if busy { ProgressView("Dateien werden geprüft…") }
      if let message { Text(message).textSelection(.enabled) }
      if let error = controller.error {
        Text(error)
          .foregroundStyle(DesignTokens.negative)
          .textSelection(.enabled)
      }
      Divider()
      Text("Letzte Importberichte")
        .font(.headline)
      if controller.workspace.imports.isEmpty {
        Text("Keine Importberichte vorhanden.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ForEach(controller.workspace.imports.suffix(10).reversed()) { report in
          DisclosureGroup("\(report.filename) · \(report.outcomes.count) Zeilen") {
            Text("SHA256: \(report.sha256)\n\(report.encoding), \(report.delimiter)").font(.caption)
              .textSelection(.enabled)
            Text(report.outcomes.joined(separator: "\n")).font(.caption).textSelection(.enabled)
          }
        }
      }
    }
    .accessibilityIdentifier("general.backup-recovery")
    .confirmationDialog(
      "Geprüfte Sicherung beim nächsten Start wiederherstellen?", isPresented: $confirmRestore
    ) {
      Button("Wiederherstellung vormerken") {
        guard let restoreURL else { return }
        busy = true
        Task {
          defer { busy = false }
          do {
            let paths = try AppDataPaths.live()
            try await Task.detached(priority: .utility) {
              try ConsolidationBackup.scheduleRestore(restoreURL, paths: paths)
            }.value
            message =
              "Wiederherstellung vorbereitet. Die App vollständig beenden und erneut öffnen. Vorherige Daten werden aufbewahrt."
          } catch { controller.error = error.localizedDescription }
        }
      }
      Button("Abbrechen", role: .cancel) {}
    }
  }
  private func create() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "EVE-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")).nexusbackup"
    guard panel.runModal() == .OK, let target = panel.url else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        try context.save()
        let paths = try AppDataPaths.live()
        let preferences = try ConsolidationPreferences.encoded()
        let schema = AppPersistence.schemaVersion
        try await Task.detached(priority: .utility) {
          try ConsolidationBackup.create(
            dataRoot: paths.dataRoot, destination: target, defaults: preferences, schema: schema)
        }.value
        message = "Sicherung erstellt und vollständig geprüft: \(target.lastPathComponent)"
      } catch { controller.error = error.localizedDescription }
    }
  }
  private func verify(restore: Bool) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.treatsFilePackagesAsDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        let manifest = try await Task.detached(priority: .utility) {
          try ConsolidationBackup.verify(url)
        }.value
        message =
          "Geprüft: \(manifest.files.count) Dateien, Schema \(manifest.schema), erstellt \(manifest.createdAt.formatted())."
        if restore {
          restoreURL = url
          confirmRestore = true
        }
      } catch { controller.error = error.localizedDescription }
    }
  }
  private func diagnostics() {
    let p = NSSavePanel()
    p.nameFieldStringValue = "EVE-Diagnose.txt"
    guard p.runModal() == .OK, let url = p.url else { return }
    let w = controller.workspace
    let report = """
      EVE New Eden Nexus - Assets, Industry, Markets
      Schema: \(AppPersistence.schemaVersion)
      macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
      SDE-Build: \(runtime.activeSDEBuild.map(String.init) ?? "nicht verfügbar")
      Arbeitsdatenformat: \(w.formatVersion), Revision: \(w.revision)
      Projekte: \(w.projects.count), Lager: \(w.warehouses.count)
      Reservierungen: \(w.reservations.count), Preisprofile: \(w.priceProfiles.count)
      Einkaufspositionen: \(w.purchases.count), Belege: \(w.evidence.count)
      Verkaufszuordnungen: \(w.sales.count), Wissenschaftsaufträge: \(w.science.count)
      Keine Namen, Account-IDs, Dateipfade, Belegdaten oder Anmeldeschlüssel enthalten.
      """
    do {
      try report.write(to: url, atomically: true, encoding: .utf8)
      message = "Diagnose exportiert."
    } catch { controller.error = error.localizedDescription }
  }
}
