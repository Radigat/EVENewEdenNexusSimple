import Foundation

public struct EVEMultibuyExport: Equatable, Sendable {
  public let text: String
  public let itemCount: Int

  public init(text: String, itemCount: Int) {
    self.text = text
    self.itemCount = itemCount
  }

  public static func make(
    from materials: [MaterialRequirement],
  ) -> EVEMultibuyExport {
    let purchaseLines =
      materials
      .filter { $0.toBuy > 0 }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name)
          == .orderedAscending
      }
      .map { "\($0.name) \($0.toBuy)" }

    return EVEMultibuyExport(
      text: purchaseLines.joined(separator: "\n"),
      itemCount: purchaseLines.count
    )
  }
}
