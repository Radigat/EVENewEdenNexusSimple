import Foundation
import Security

public protocol RefreshTokenStoring: Sendable {
  func save(_ token: String, characterID: Int64) throws
  func load(characterID: Int64) throws -> String?
  func delete(characterID: Int64) throws
}

public struct KeychainRefreshTokenStore: RefreshTokenStoring, Sendable {
  private let service: String

  public init(service: String = "com.local.EVENexusSimple.refresh-token") {
    self.service = service
  }

  public func save(_ token: String, characterID: Int64) throws {
    do {
      try saveProtected(token, characterID: characterID)
    } catch AuthError.keychain(let status)
      where status == errSecMissingEntitlement
    {
      try saveLegacy(token, characterID: characterID)
    }
  }

  private func saveProtected(_ token: String, characterID: Int64) throws {
    let base = protectedBase(characterID: characterID)
    let data = Data(token.utf8)
    let update = SecItemUpdate(
      base as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if update == errSecItemNotFound {
      var addition = base
      addition[kSecValueData as String] = data
      addition[kSecAttrAccessible as String] =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let status = SecItemAdd(addition as CFDictionary, nil)
      guard status == errSecSuccess else {
        throw AuthError.keychain(status)
      }
    } else if update != errSecSuccess {
      throw AuthError.keychain(update)
    }
  }

  private func saveLegacy(_ token: String, characterID: Int64) throws {
    let base = legacyBase(characterID: characterID)
    let data = Data(token.utf8)
    let update = SecItemUpdate(
      base as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if update == errSecItemNotFound {
      var addition = base
      addition[kSecValueData as String] = data
      let status = SecItemAdd(addition as CFDictionary, nil)
      guard status == errSecSuccess else {
        throw AuthError.keychain(status)
      }
    } else if update != errSecSuccess {
      throw AuthError.keychain(update)
    }
  }

  public func load(characterID: Int64) throws -> String? {
    do {
      if let token = try load(
        query: protectedBase(characterID: characterID)
      ) {
        return token
      }
    } catch AuthError.keychain(let status)
      where status == errSecMissingEntitlement
    {
      return try load(query: legacyBase(characterID: characterID))
    }

    // Releases before the data-protection migration used the legacy
    // file-based macOS keychain. Reading it once may show the existing macOS
    // access dialog; after migration all normal access uses the modern,
    // app-scoped data-protection keychain.
    let legacy = legacyBase(characterID: characterID)
    guard let token = try load(query: legacy) else { return nil }
    try save(token, characterID: characterID)
    let deletion = SecItemDelete(legacy as CFDictionary)
    guard deletion == errSecSuccess || deletion == errSecItemNotFound else {
      throw AuthError.keychain(deletion)
    }
    return token
  }

  private func load(query base: [String: Any]) throws -> String? {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw AuthError.keychain(status)
    }
    return String(data: data, encoding: .utf8)
  }

  public func delete(characterID: Int64) throws {
    let protectedStatus = SecItemDelete(
      protectedBase(characterID: characterID) as CFDictionary
    )
    guard
      protectedStatus == errSecSuccess
        || protectedStatus == errSecItemNotFound
        || protectedStatus == errSecMissingEntitlement
    else {
      throw AuthError.keychain(protectedStatus)
    }

    let legacyStatus = SecItemDelete(
      legacyBase(characterID: characterID) as CFDictionary
    )
    guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound
    else {
      throw AuthError.keychain(legacyStatus)
    }
  }

  private func protectedBase(characterID: Int64) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: String(characterID),
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  private func legacyBase(characterID: Int64) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: String(characterID),
    ]
  }
}
