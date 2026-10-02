import Foundation
import Security

protocol KeychainSecItemOperating: Sendable {
  func update(
    query: [String: Any],
    attributes: [String: Any]
  ) -> OSStatus
  func add(attributes: [String: Any]) -> OSStatus
  func copy(query: [String: Any]) -> (OSStatus, Data?)
  func delete(query: [String: Any]) -> OSStatus
}

private struct SystemKeychainSecItemClient: KeychainSecItemOperating {
  func update(
    query: [String: Any],
    attributes: [String: Any]
  ) -> OSStatus {
    SecItemUpdate(
      query as CFDictionary,
      attributes as CFDictionary
    )
  }

  func add(attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func copy(query: [String: Any]) -> (OSStatus, Data?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result as? Data)
  }

  func delete(query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

public protocol RefreshTokenStoring: Sendable {
  func save(_ token: String, characterID: Int64) throws
  func load(characterID: Int64) throws -> String?
  func delete(characterID: Int64) throws
}

public struct KeychainRefreshTokenStore: RefreshTokenStoring, Sendable {
  private let service: String
  private let client: any KeychainSecItemOperating

  public init(service: String = "com.local.EVENexusSimple.refresh-token") {
    self.service = service
    self.client = SystemKeychainSecItemClient()
  }

  init(
    service: String = "com.local.EVENexusSimple.refresh-token",
    client: any KeychainSecItemOperating
  ) {
    self.service = service
    self.client = client
  }

  public func save(_ token: String, characterID: Int64) throws {
    do {
      try saveProtected(token, characterID: characterID)
    } catch AuthError.keychain(let status)
      where status == errSecMissingEntitlement
    {
      do {
        try saveLegacy(token, characterID: characterID)
      } catch AuthError.keychain(let legacyStatus) {
        throw AuthError.keychainFallback(
          protected: status,
          legacy: legacyStatus
        )
      }
    }
  }

  private func saveProtected(_ token: String, characterID: Int64) throws {
    let base = protectedBase(characterID: characterID)
    let data = Data(token.utf8)
    let update = client.update(
      query: base,
      attributes: [kSecValueData as String: data]
    )
    if update == errSecItemNotFound {
      var addition = base
      addition[kSecValueData as String] = data
      addition[kSecAttrAccessible as String] =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let status = client.add(attributes: addition)
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
    let update = client.update(
      query: base,
      attributes: [kSecValueData as String: data]
    )
    if update == errSecItemNotFound {
      var addition = base
      addition[kSecValueData as String] = data
      var status = client.add(attributes: addition)
      if status == errSecDuplicateItem {
        // An earlier ad-hoc build can leave a legacy item that this build is
        // not allowed to read or update, while the keychain still considers
        // its service/account pair a duplicate. Reaching this branch means
        // EVE SSO already issued a fresh replacement token. Delete only that
        // exact inaccessible item and retry the secure add once.
        let deletion = client.delete(query: base)
        guard deletion == errSecSuccess || deletion == errSecItemNotFound
        else {
          throw AuthError.keychain(deletion)
        }
        status = client.add(attributes: addition)
      }
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
    let deletion = client.delete(query: legacy)
    guard deletion == errSecSuccess || deletion == errSecItemNotFound else {
      throw AuthError.keychain(deletion)
    }
    return token
  }

  private func load(query base: [String: Any]) throws -> String? {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, data) = client.copy(query: query)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data else {
      throw AuthError.keychain(status)
    }
    return String(data: data, encoding: .utf8)
  }

  public func delete(characterID: Int64) throws {
    let protectedStatus = client.delete(
      query: protectedBase(characterID: characterID)
    )
    guard
      protectedStatus == errSecSuccess
        || protectedStatus == errSecItemNotFound
        || protectedStatus == errSecMissingEntitlement
    else {
      throw AuthError.keychain(protectedStatus)
    }

    let legacyStatus = client.delete(
      query: legacyBase(characterID: characterID)
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
