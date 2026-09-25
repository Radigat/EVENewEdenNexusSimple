import AppKit
import CryptoKit
import Darwin
import Foundation

// Packaging launcher only; the existing app executable and its domain logic stay intact.
struct SeedManifest: Codable {
  let format: Int
  let files: [String: String]
}

enum LaunchError: LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

func hash(_ url: URL) throws -> String {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var digest = SHA256()
  while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
    digest.update(data: data)
  }
  return digest.finalize().map { String(format: "%02x", $0) }.joined()
}

func verify(_ inputFolder: URL) throws -> SeedManifest {
  let folder = inputFolder.standardizedFileURL.resolvingSymlinksInPath()
  let fm = FileManager.default
  let manifest = try JSONDecoder().decode(
    SeedManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
  guard manifest.format == 1,
    manifest.files["data/ApplicationData/EVENexusSimple.store"] != nil,
    manifest.files["preferences.plist"] != nil
  else { throw LaunchError.invalid("Die DEV-Datenkopie ist unvollständig.") }
  guard
    let entries = fm.enumerator(
      at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
  else { throw LaunchError.invalid("Die DEV-Datenkopie ist nicht lesbar.") }
  var found = Set<String>()
  for case let file as URL in entries {
    let properties = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
    guard properties.isSymbolicLink != true else {
      throw LaunchError.invalid("Verknüpfung in der DEV-Datenkopie.")
    }
    guard properties.isRegularFile == true else { continue }
    let relative = String(
      file.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(folder.path.count + 1))
    if relative == "manifest.json" { continue }
    guard let expected = manifest.files[relative], try hash(file) == expected else {
      throw LaunchError.invalid("Die DEV-Datenkopie hat eine ungültige Prüfsumme.")
    }
    found.insert(relative)
  }
  guard found == Set(manifest.files.keys) else {
    throw LaunchError.invalid("In der DEV-Datenkopie fehlen Dateien.")
  }
  return manifest
}

func launch() throws {
  let fm = FileManager.default
  let identifier = "com.local.EVENexusSimple.DEV"
  guard Bundle.main.bundleIdentifier == identifier,
    let resources = Bundle.main.resourceURL,
    let executable = Bundle.main.object(forInfoDictionaryKey: "EVENexusOriginalExecutable")
      as? String,
    !executable.contains("/")
  else { throw LaunchError.invalid("Ungültiges DEV-App-Paket.") }

  // The optional override is only accepted during the isolated packaging smoke test.
  let environment = ProcessInfo.processInfo.environment
  let acceptance = environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1"
  let override = acceptance ? environment["EVE_NEXUS_DEV_ACCEPTANCE_ROOT"] : nil
  let support = try fm.url(
    for: .applicationSupportDirectory, in: .userDomainMask,
    appropriateFor: nil, create: true)
  let root =
    override.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? support.appendingPathComponent(identifier, isDirectory: true)
  let preferencesDomain =
    override == nil ? identifier : identifier + ".smoke." + root.lastPathComponent
  let marker = root.appendingPathComponent("dev-seed-complete.json")
  let dataRoot = root.appendingPathComponent("com.local.EVENexusSimple", isDirectory: true)

  if !fm.fileExists(atPath: root.path) {
    let seed = resources.appendingPathComponent("DevSeed", isDirectory: true)
    _ = try verify(seed)
    let stage = root.deletingLastPathComponent().appendingPathComponent(".eve-dev-seed-\(UUID())")
    defer { try? fm.removeItem(at: stage) }
    try fm.copyItem(at: seed, to: stage)
    _ = try verify(stage)
    try fm.moveItem(
      at: stage.appendingPathComponent("data"),
      to: stage.appendingPathComponent("com.local.EVENexusSimple"))
    try fm.moveItem(
      at: stage.appendingPathComponent("manifest.json"),
      to: stage.appendingPathComponent("dev-seed-complete.json"))
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stage.path)
    try fm.moveItem(at: stage, to: root)
  }

  guard fm.fileExists(atPath: marker.path),
    fm.fileExists(
      atPath: dataRoot.appendingPathComponent("ApplicationData/EVENexusSimple.store").path),
    try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
    try dataRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
  else {
    throw LaunchError.invalid(
      "Der DEV-Datenordner ist unvollständig. Bestehende Daten wurden nicht überschrieben.")
  }
  let preferencesMarker = root.appendingPathComponent("dev-preferences-imported")
  if !fm.fileExists(atPath: preferencesMarker.path) {
    let data = try Data(contentsOf: root.appendingPathComponent("preferences.plist"))
    guard
      let preferences = try PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any],
      let defaults = UserDefaults(suiteName: preferencesDomain)
    else { throw LaunchError.invalid("DEV-Einstellungen sind nicht lesbar.") }
    defaults.setPersistentDomain(preferences, forName: preferencesDomain)
    guard defaults.synchronize() else {
      throw LaunchError.invalid("DEV-Einstellungen konnten nicht gespeichert werden.")
    }
    try Data().write(to: preferencesMarker, options: .atomic)
  }

  // Always set both: inherited production paths must never leak into this variant.
  setenv("EVE_NEXUS_APPLICATION_SUPPORT_ROOT", root.path, 1)
  setenv("EVE_NEXUS_USER_DEFAULTS_SUITE", preferencesDomain, 1)
  let executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/" + executable)
  let arguments = [executableURL.path] + CommandLine.arguments.dropFirst()
  let pointers = arguments.map { strdup($0) } + [nil]
  defer { for pointer in pointers { free(pointer) } }
  pointers.withUnsafeBufferPointer { buffer in
    _ = execv(executableURL.path, buffer.baseAddress!)
  }
  throw LaunchError.invalid("Die DEV-App konnte nicht gestartet werden (\(errno)).")
}

do {
  try launch()
} catch {
  if ProcessInfo.processInfo.environment["EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT"] == "1" {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  } else {
    let alert = NSAlert()
    alert.messageText = "EVE New Eden Nexus – DEV"
    alert.informativeText = error.localizedDescription
    alert.runModal()
  }
  exit(1)
}
