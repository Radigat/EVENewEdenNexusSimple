import CryptoKit
import Foundation
import Security

public struct PKCEChallenge: Equatable, Sendable {
  public let verifier: String
  public let challenge: String

  public static func generate() throws -> PKCEChallenge {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw AuthError.keychain(status)
    }
    let verifier = Data(bytes).base64URLEncodedString()
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return PKCEChallenge(
      verifier: verifier,
      challenge: Data(digest).base64URLEncodedString()
    )
  }
}

extension Data {
  public func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
