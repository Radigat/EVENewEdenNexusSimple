import EVENexusCore
import Foundation

enum AppDefaults {
  nonisolated(unsafe) static let store: UserDefaults = {
    let environmentSuite =
      ProcessInfo.processInfo.environment["EVE_NEXUS_USER_DEFAULTS_SUITE"]
    if let environmentSuite {
      return UserDefaults(suiteName: environmentSuite) ?? .standard
    }
    if Bundle.main.bundleIdentifier == AppDataPaths.applicationIdentifier {
      return .standard
    }
    return UserDefaults(suiteName: AppDataPaths.applicationIdentifier)
      ?? .standard
  }()

  private static let migrationKey =
    "app.defaults.canonical-domain-migration-version"
  private static let migrationVersion = 2
  private static let legacyDomains = ["EVE Nexus Simple"]
  private static let ownedPrefixes = [
    "app.",
    "asset.",
    "contracts.",
    "dashboard.",
    "eve.",
    "market.",
    "market-opportunities.",
    "planner.",
    "reactions.",
  ]

  static func migrateLegacyDomainsIfNeeded() {
    guard store.integer(forKey: migrationKey) < migrationVersion else {
      return
    }
    for domain in legacyDomains {
      guard
        let values = UserDefaults.standard.persistentDomain(forName: domain)
      else { continue }
      for (key, value) in values
      where ownedPrefixes.contains(where: key.hasPrefix)
        && store.object(forKey: key) == nil
      {
        store.set(value, forKey: key)
      }
    }
    store.set(migrationVersion, forKey: migrationKey)
  }
}
