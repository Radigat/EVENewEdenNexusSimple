import Foundation
import SwiftData

/// Transitional schema for the short-lived store that was created after the
/// character model changed while its version identifier was still 1.0.0.
/// It is used only to read the protected recovery copy and is never activated.
private enum EVENexusRecoveredCurrentSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  static let models = EVENexusSchemaV2.models
}

enum PersistenceRecovery {
  static let importDirectoryName = "recovery-import"
  static let sourceFileName = "current.store"
  static let completionFileName = "merge-v1.complete.json"

  @MainActor
  static func mergeIfPending(
    into container: ModelContainer,
    dataRoot: URL,
    fileManager: FileManager = .default
  ) throws {
    let directory = dataRoot.appendingPathComponent(
      importDirectoryName,
      isDirectory: true
    )
    let source = directory.appendingPathComponent(sourceFileName)
    let completion = directory.appendingPathComponent(completionFileName)
    guard fileManager.fileExists(atPath: source.path),
      !fileManager.fileExists(atPath: completion.path)
    else { return }

    let temporary = fileManager.temporaryDirectory.appendingPathComponent(
      "eve-nexus-recovery-\(UUID().uuidString).store"
    )
    try fileManager.copyItem(at: source, to: temporary)
    defer {
      try? fileManager.removeItem(at: temporary)
      try? fileManager.removeItem(
        at: URL(fileURLWithPath: temporary.path + "-wal")
      )
      try? fileManager.removeItem(
        at: URL(fileURLWithPath: temporary.path + "-shm")
      )
    }

    let sourceSchema = Schema(
      versionedSchema: EVENexusRecoveredCurrentSchemaV1.self
    )
    let sourceConfiguration = ModelConfiguration(
      "EVENexusRecoverySource",
      schema: sourceSchema,
      url: temporary,
      cloudKitDatabase: .none
    )
    let sourceContainer = try ModelContainer(
      for: sourceSchema,
      configurations: [sourceConfiguration]
    )
    let sourceContext = ModelContext(sourceContainer)
    let destinationContext = container.mainContext

    let sourceCharacters = try sourceContext.fetch(
      FetchDescriptor<StoredCharacter>()
    )
    let destinationCharacters = try destinationContext.fetch(
      FetchDescriptor<StoredCharacter>()
    )
    var destinationByID = Dictionary(
      uniqueKeysWithValues: destinationCharacters.map {
        ($0.characterID, $0)
      }
    )
    var insertedCharacters = 0
    var updatedCharacters = 0

    for sourceCharacter in sourceCharacters {
      if let destination = destinationByID[sourceCharacter.characterID] {
        guard isNewer(sourceCharacter, than: destination) else { continue }
        copy(sourceCharacter, to: destination)
        updatedCharacters += 1
      } else {
        let inserted = StoredCharacter(
          characterID: sourceCharacter.characterID,
          characterName: sourceCharacter.characterName,
          authorizationSnapshot: sourceCharacter.authorizationSnapshot,
          capabilitySnapshot: sourceCharacter.capabilitySnapshot,
          assetSnapshot: sourceCharacter.assetSnapshot,
          corporationID: sourceCharacter.corporationID,
          corporationName: sourceCharacter.corporationName,
          corporationAssetSnapshot: sourceCharacter.corporationAssetSnapshot,
          blueprintSnapshot: sourceCharacter.blueprintSnapshot,
          walletBalanceSnapshot: sourceCharacter.walletBalanceSnapshot,
          lastSyncAt: sourceCharacter.lastSyncAt,
          walletLastSyncAt: sourceCharacter.walletLastSyncAt
        )
        destinationContext.insert(inserted)
        destinationByID[inserted.characterID] = inserted
        insertedCharacters += 1
      }
    }

    let sourceMetadata = try sourceContext.fetch(
      FetchDescriptor<StoredESISnapshotMetadata>()
    )
    var mergedMetadata = 0
    for metadata in sourceMetadata {
      let characterID = metadata.characterID
      let domain = metadata.domain
      let descriptor = FetchDescriptor<StoredESISnapshotMetadata>(
        predicate: #Predicate {
          $0.characterID == characterID && $0.domain == domain
        },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
      )
      let existing = try destinationContext.fetch(descriptor).first
      guard existing.map({ metadata.capturedAt > $0.capturedAt }) ?? true else {
        continue
      }
      try destinationContext.upsertESISnapshotMetadata(
        characterID: characterID,
        domain: domain,
        freshness: metadata.freshness,
        provider: metadata.provider,
        sourceVersion: metadata.sourceVersion,
        sourceSnapshotID: metadata.sourceSnapshotID,
        capturedAt: metadata.capturedAt,
        diagnostics: metadata.diagnostics
      )
      mergedMetadata += 1
    }

    let sourceSettings = try sourceContext.fetch(FetchDescriptor<AppSetting>())
    for setting in sourceSettings {
      try destinationContext.upsertAppSetting(
        key: setting.key,
        value: setting.value
      )
    }

    try destinationContext.save()
    let report = PersistenceRecoveryReport(
      completedAt: .now,
      sourceCharacterCount: sourceCharacters.count,
      insertedCharacterCount: insertedCharacters,
      updatedCharacterCount: updatedCharacters,
      mergedMetadataCount: mergedMetadata,
      mergedSettingCount: sourceSettings.count
    )
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(report).write(to: completion, options: .atomic)
  }

  private static func isNewer(
    _ source: StoredCharacter,
    than destination: StoredCharacter
  ) -> Bool {
    let sourceDate = source.lastSyncAt ?? source.walletLastSyncAt ?? .distantPast
    let destinationDate =
      destination.lastSyncAt ?? destination.walletLastSyncAt ?? .distantPast
    return sourceDate > destinationDate
  }

  private static func copy(
    _ source: StoredCharacter,
    to destination: StoredCharacter
  ) {
    destination.characterName = source.characterName
    destination.authorizationSnapshot = source.authorizationSnapshot
    destination.capabilitySnapshot = source.capabilitySnapshot
    destination.assetSnapshot = source.assetSnapshot
    destination.corporationID = source.corporationID
    destination.corporationName = source.corporationName
    destination.corporationAssetSnapshot = source.corporationAssetSnapshot
    destination.blueprintSnapshot = source.blueprintSnapshot
    destination.walletBalanceSnapshot = source.walletBalanceSnapshot
    destination.lastSyncAt = source.lastSyncAt
    destination.walletLastSyncAt = source.walletLastSyncAt
  }
}

private struct PersistenceRecoveryReport: Codable {
  let completedAt: Date
  let sourceCharacterCount: Int
  let insertedCharacterCount: Int
  let updatedCharacterCount: Int
  let mergedMetadataCount: Int
  let mergedSettingCount: Int
}
