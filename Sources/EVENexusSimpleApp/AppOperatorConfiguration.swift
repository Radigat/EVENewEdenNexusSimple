import EVENexusCore
import Foundation

enum AppOperatorConfiguration {
  private static let infoKey = "CCPUserAgentContact"
  private static let environmentKey = "EVE_NEXUS_CCP_USER_AGENT_CONTACT"
  private static let applicationOperatorContact = "projekt-st@gmx.de"

  static func ccpUserAgentContact(legacyLocalValue: String?) -> String? {
    let candidates = [
      Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
      ProcessInfo.processInfo.environment[environmentKey],
      applicationOperatorContact,
      legacyLocalValue,
    ]
    return candidates.lazy.compactMap {
      CCPUserAgentConfiguration.normalizedOwnerContact($0)
    }.first
  }
}
