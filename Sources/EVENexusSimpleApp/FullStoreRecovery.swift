import AppKit
import CoreData
import EVENexusCore
import Foundation
import SwiftData

@MainActor
enum FullStoreRecovery {
  static var processLock: PersistenceProcessLock?
  // The child process never runs bootstrap, seeding, backups, imports or background services.
  static func handleValidatorInvocation() -> Bool {
    let args = CommandLine.arguments
    guard args.count == 4, args[1] == "--validate-persistence" else { return false }
    do {
      let counts = try validateDirect(URL(fileURLWithPath: args[2]))
      try JSONEncoder().encode(counts).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
      exit(0)
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(3)
    }
  }

  static func validateDirect(_ store: URL) throws -> [String: Int] {
    guard FileManager.default.fileExists(atPath: store.path) else {
      throw ConsolidationError.invalid("Zu prüfender Datenbestand fehlt.")
    }
    // ModelContainer can initialize a healthy foreign SQLite file as an empty app store.
    // Inspect existing Core Data ownership read-only before allowing any migration writes.
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType, at: store, options: [NSReadOnlyPersistentStoreOption: true])
    let knownEntitySets = [
      Schema(versionedSchema: EVENexusSchemaV1.self),
      Schema(versionedSchema: EVENexusSchemaV2.self),
      Schema(versionedSchema: EVENexusSchemaV3.self),
    ].map { Set($0.entities.map(\.name)) }
    guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
      !hashes.isEmpty, knownEntitySets.contains(Set(hashes.keys)) else {
      throw ConsolidationError.invalid("Kein unterstützter EVE-Anwendungsdatenbestand. Die Quelldaten wurden nicht aktiviert.")
    }
    // Entity names establish ownership; the existing migration plan validates exact model hashes.
    let schema = Schema(versionedSchema: EVENexusSchemaV3.self)
    let configuration = ModelConfiguration("EVENexusSimple", schema: schema, url: store, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, migrationPlan: EVENexusMigrationPlan.self, configurations: [configuration])
    let context = ModelContext(container)
    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
      // Fetch objects as well as counts so every supported entity is readable.
      try context.fetch(FetchDescriptor<T>()).count
    }
    let result = try [
      "Production bases": count(StoredProductionBasis.self),
      "Manufacturing profiles": count(StoredManufacturingProfile.self),
      "Reaction profiles": count(StoredReactionProfile.self),
      "Characters": count(StoredCharacter.self),
      "Stock targets": count(StoredStockTarget.self),
      "Plans": count(StoredPlan.self),
      "Planner drafts": count(StoredPlannerDraft.self),
      "Production records": count(StoredProductionRecord.self),
      "Production overview rows": count(StoredProductionOverviewRow.self),
      "SDE pointers": count(StoredSDEActivationPointer.self),
      "ESI metadata": count(StoredESISnapshotMetadata.self),
      "App settings": count(AppSetting.self),
      "Consolidation workspaces": count(StoredConsolidationWorkspace.self),
    ]
    let decoder = JSONDecoder()
    for stored in try context.fetch(FetchDescriptor<StoredProductionBasis>()) {
      _ = try decoder.decode(ProductionBasis.self, from: stored.encodedBasis)
    }
    for stored in try context.fetch(FetchDescriptor<StoredManufacturingProfile>()) {
      _ = try decoder.decode(ManufacturingProfile.self, from: stored.encodedProfile)
    }
    for stored in try context.fetch(FetchDescriptor<StoredReactionProfile>()) {
      _ = try decoder.decode(ReactionProfile.self, from: stored.encodedProfile)
    }
    for stored in try context.fetch(FetchDescriptor<StoredPlan>()) {
      _ = try decoder.decode(IndustryPlanSnapshot.self, from: stored.snapshot)
    }
    for stored in try context.fetch(FetchDescriptor<StoredProductionRecord>()) {
      _ = try decoder.decode(IndustryPlanSnapshot.self, from: stored.snapshot)
    }
    for stored in try context.fetch(FetchDescriptor<StoredProductionOverviewRow>()) {
      _ = try decoder.decode(IndustryPlanSnapshot.self, from: stored.sourceSnapshot)
    }
    for stored in try context.fetch(FetchDescriptor<StoredCharacter>()) {
      _ = try decoder.decode(AuthorizationSnapshot.self, from: stored.authorizationSnapshot)
      if let data = stored.capabilitySnapshot { _ = try decoder.decode(CharacterCapabilitySnapshot.self, from: data) }
      if let data = stored.assetSnapshot { _ = try decoder.decode(Sourced<AssetSnapshot>.self, from: data) }
      if let data = stored.corporationAssetSnapshot { _ = try decoder.decode(Sourced<AssetSnapshot>.self, from: data) }
      if let data = stored.blueprintSnapshot { _ = try decoder.decode(Sourced<[OwnedBlueprintInstance]>.self, from: data) }
      if let data = stored.walletBalanceSnapshot { _ = try decoder.decode(Sourced<Double>.self, from: data) }
    }
    for stored in try context.fetch(FetchDescriptor<AppSetting>()) {
      let key = stored.key
      let recognized = key.hasPrefix(AppSettingKey.industryJobsPrefix)
        || key.hasPrefix(AppSettingKey.openOrdersPrefix)
        || key.hasPrefix(AppSettingKey.privateContractsPrefix)
        || key.hasPrefix(AppSettingKey.corporationWalletPrefix)
        || key == AppSettingKey.dashboardWealthHistory
      guard recognized else { continue } // Operator settings and unknown keys remain opaque strings.
      guard let data = Data(base64Encoded: stored.value) else { throw POSIXError(.EINVAL) }
      if key.hasPrefix(AppSettingKey.industryJobsPrefix) {
        _ = try decoder.decode(Sourced<[ESIIndustryJobDTO]>.self, from: data)
      } else if key.hasPrefix(AppSettingKey.openOrdersPrefix) {
        _ = try decoder.decode(Sourced<[ESICharacterOrderDTO]>.self, from: data)
      } else if key.hasPrefix(AppSettingKey.privateContractsPrefix) {
        _ = try decoder.decode(Sourced<PrivateContractSnapshot>.self, from: data)
      } else if key.hasPrefix(AppSettingKey.corporationWalletPrefix) {
        _ = try decoder.decode(Sourced<CorporationWalletSnapshot>.self, from: data)
      } else {
        _ = try decoder.decode([DashboardWealthSnapshot].self, from: data)
      }
    }
    for stored in try context.fetch(FetchDescriptor<StoredConsolidationWorkspace>()) {
      let workspace = try decoder.decode(ConsolidationWorkspace.self, from: stored.payload)
      try workspace.validate()
      guard workspace.revision == stored.revision else { throw ConsolidationError.stalePreview }
    }
    try context.save()
    return result
  }

  static func validateInChild(_ store: URL) throws -> [String: Int] {
    guard let executable = Bundle.main.executableURL else { throw ConsolidationError.unavailable("Prüfprogramm nicht verfügbar.") }
    let report = store.deletingLastPathComponent().appendingPathComponent(".validation-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: report) }
    let process = Process()
    process.executableURL = executable
    process.arguments = ["--validate-persistence", store.path, report.path]
    guard let processLock else { throw POSIXError(.EACCES) }
    let inheritedLock = try processLock.duplicateForChild()
    process.standardInput = inheritedLock
    defer { try? inheritedLock.close() }
    // Never pipe unbounded framework diagnostics into an unread pipe.
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    try inheritedLock.close()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw ConsolidationError.invalid("Datenbestand konnte nicht vollständig geprüft und auf Schema V3 migriert werden. Die bisherigen Daten bleiben erhalten.")
    }
    return try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: report))
  }

  static func confirmationText(
    source: URL,
    backupDirectory: URL,
    modelCounts: [String: Int],
    currentSnapshotAvailable: Bool,
    language: AppLanguage
  ) -> String {
    func format(_ key: String, _ value: String) -> String {
      String(format: language.localized(key), locale: language.locale, value)
    }
    let counts = modelCounts.sorted(by: { $0.key < $1.key }).map {
      "\(language.localized($0.key)): \($0.value)"
    }.joined(separator: "\n")
    var sections = [
      format("Source: %@", source.path),
      format("Backup of current and earlier data: %@", backupDirectory.path),
      counts,
      language.localized("All application records will be replaced by the earlier data. Newer records remain only in the backup. No records will be merged. Keep this backup. Keychain, app preferences, SDE, and additional databases are retained."),
      language.localized("Before restoring, quit every older version of this app. Older versions do not prevent simultaneous access to this data folder."),
    ]
    if !currentSnapshotAvailable {
      sections.append(language.localized("The current data is backed up only as an unchanged raw copy because a readable SQLite backup could not be created. Keep that raw backup for recovery."))
    }
    return sections.joined(separator: "\n\n")
  }

  /// Returns true when the exclusive recovery session should quit, including cancellation.
  static func runPending(paths: AppDataPaths) throws -> Bool {
    guard StoreFullRestore.isPending(paths: paths) else { return false }
    let preview: FullRestorePreview
    do { preview = try StoreFullRestore.prepare(paths: paths, validate: validateInChild) }
    catch {
      let alert = NSAlert()
      alert.messageText = AppLocalization.text("Full restoration paused")
      alert.informativeText = AppLocalization.text("The data could not be prepared for restoration.")
        + "\n\n" + error.localizedDescription + "\n\n"
        + AppLocalization.text("Reopen the app to try again, or cancel the request.")
      alert.addButton(withTitle: AppLocalization.text("Quit and retry later"))
      alert.addButton(withTitle: AppLocalization.text("Cancel request"))
      if alert.runModal() == .alertSecondButtonReturn { try StoreFullRestore.cancel(paths: paths) }
      return true
    }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = AppLocalization.text("Fully restore the earlier data?")
    alert.informativeText = confirmationText(
      source: preview.source,
      backupDirectory: preview.backupDirectory,
      modelCounts: preview.modelCounts,
      currentSnapshotAvailable: preview.currentSnapshotAvailable,
      language: AppLocalization.currentLanguage
    )
    alert.addButton(withTitle: AppLocalization.text("Cancel"))
    alert.addButton(withTitle: AppLocalization.text("Restore all data"))
    guard alert.runModal() == .alertSecondButtonReturn else {
      try StoreFullRestore.cancel(paths: paths)
      return true
    }
    do { try StoreFullRestore.activate(preview, paths: paths, validate: validateInChild) }
    catch {
      do { try StoreFullRestore.recoverInterrupted(paths: paths) }
      catch {
        throw NSError(domain: "FullStoreRecovery", code: 2, userInfo: [
          NSLocalizedDescriptionKey: AppLocalization.text("Full restoration could not be completed. Keep the backup and reopen the app to retry recovery.")
            + "\n\n" + error.localizedDescription,
          NSUnderlyingErrorKey: error,
        ])
      }
      throw NSError(domain: "FullStoreRecovery", code: 1, userInfo: [
        NSLocalizedDescriptionKey: AppLocalization.text("Full restoration could not be completed. Keep the backup and reopen the app to retry recovery.")
          + "\n\n" + error.localizedDescription,
        NSUnderlyingErrorKey: error,
      ])
    }
    let finished = NSAlert()
    finished.messageText = AppLocalization.text("Data restored")
    finished.informativeText = AppLocalization.format(
      "Reopen the app. The previous data remains backed up at:\n%@",
      preview.backupDirectory.path
    )
    finished.addButton(withTitle: AppLocalization.text("Quit"))
    finished.runModal()
    return true
  }

  static func requestAndQuit(paths: AppDataPaths?, context: ModelContext?) {
    do {
      guard let paths else {
        throw ConsolidationError.unavailable(AppLocalization.text("The data folder is unavailable."))
      }
      let alert = NSAlert()
      alert.messageText = AppLocalization.text("Check earlier data")
      alert.informativeText = AppLocalization.text("The app will save pending changes and quit. On the next launch, the current and earlier data will be backed up and checked. You will then explicitly confirm full restoration without merging.")
        + "\n\n"
        + AppLocalization.text("Before restoring, quit every older version of this app. Older versions do not prevent simultaneous access to this data folder.")
      alert.addButton(withTitle: AppLocalization.text("Cancel"))
      alert.addButton(withTitle: AppLocalization.text("Save and quit"))
      guard alert.runModal() == .alertSecondButtonReturn else { return }
      try context?.save()
      try StoreFullRestore.schedule(paths: paths)
      NSApplication.shared.terminate(nil)
    } catch {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = AppLocalization.text("Restoration could not be scheduled")
      alert.informativeText = AppLocalization.text("The app could not save the changes or schedule restoration. It will remain open.")
        + "\n\n" + error.localizedDescription
      alert.addButton(withTitle: AppLocalization.text("OK"))
      alert.runModal()
    }
  }
}
