import CoreGraphics
import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

struct PlannerFlowGuideTests {
  @Test
  func everyStepAndArrowIsDefinedExactlyOnce() {
    #expect(PlannerFlowGuide.nodes.map(\.id) .sorted { $0.rawValue < $1.rawValue }
      == PlannerFlowNodeID.allCases.sorted { $0.rawValue < $1.rawValue })
    #expect(PlannerFlowGuide.edges.map(\.id).sorted { $0.rawValue < $1.rawValue }
      == PlannerFlowEdgeID.allCases.sorted { $0.rawValue < $1.rawValue })
  }

  @Test
  func explanationsStayShort() {
    let explanations =
      PlannerFlowGuide.nodes.map(\.explanation) + PlannerFlowGuide.edges.map(\.explanation)
    for explanation in explanations {
      let sentences = explanation.split(separator: ".", omittingEmptySubsequences: true)
      #expect(sentences.count <= 3, "\(explanation)")
      #expect(explanation.count <= 180, "\(explanation)")
    }
  }

  @Test
  func everyTextIsTranslatedInBothLanguages() throws {
    for language in AppLanguage.allCases {
      let path = try #require(
        AppLocalization.resourceBundle.path(forResource: language.rawValue, ofType: "lproj")
      )
      let bundle = try #require(Bundle(path: path))
      for key in PlannerFlowGuide.allLocalizationKeys {
        let missing = "\u{0}missing"
        #expect(
          bundle.localizedString(forKey: key, value: missing, table: nil) != missing,
          "\(language.rawValue): \(key)"
        )
      }
    }
  }

  /// New warnings fail here until they use a translatable format in both languages.
  @Test
  func everyPlannerWarningIsTranslatedInBothLanguages() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let files = [
      "Sources/EVENexusCore/Industry/IndustryPlanner.swift",
      "Sources/EVENexusCore/Industry/ProductionTree.swift",
      "Sources/EVENexusCore/Industry/LogisticsCostCalculator.swift",
      "Sources/EVENexusCore/Industry/JumpFreighterLogistics.swift",
      "Sources/EVENexusCore/Industry/ProductionBasis.swift",
      "Sources/EVENexusSimpleApp/RuntimeState.swift",
      "Sources/EVENexusCore/Reactions/ReactionModels.swift",
      "Sources/EVENexusCore/Blueprints/BlueprintResearch.swift",
    ]
    let warning = try NSRegularExpression(
      pattern:
        #"DomainWarning\(\s*code:\s*"(?:[^"\\]|\\.)*",\s*(?:message|format):\s*(.*?),\s*(?:severity|arguments)"#,
      options: .dotMatchesLineSeparators
    )
    let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|lld)"#)
    var keys = [
      IndustryWarningText.courierItemTooLarge,
      IndustryWarningText.blueprintRunsShortFormat(missingRuns: 1),
      IndustryWarningText.blueprintRunsShortFormat(missingRuns: 2),
    ]
    func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
      regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    for file in files {
      let source = try String(
        contentsOf: root.appendingPathComponent(file),
        encoding: .utf8
      )
      for match in matches(warning, source) {
        let expression = String(source[try #require(Range(match.range(at: 1), in: source))])
        for found in matches(literal, expression) {
          let key = String(expression[try #require(Range(found.range(at: 1), in: expression))])
          #expect(!key.contains("\\("), "Interpolated warning in \(file): \(key)")
          keys.append(key)
        }
      }
    }
    #expect(keys.count > 80)
    for language in AppLanguage.allCases {
      let path = try #require(
        AppLocalization.resourceBundle.path(forResource: language.rawValue, ofType: "lproj")
      )
      let bundle = try #require(Bundle(path: path))
      for key in keys {
        let missing = "\u{0}missing"
        let text = bundle.localizedString(forKey: key, value: missing, table: nil)
        #expect(text != missing, "\(language.rawValue): \(key)")
        #expect(
          matches(specifier, text).count == matches(specifier, key).count,
          "\(language.rawValue): \(key)"
        )
      }
    }
  }

  @Test
  func everyCalculationPhaseHasAStep() {
    for phase in PlannerCalculationPhase.allCases {
      #expect(PlannerFlowGuide.nodes.contains { $0.id == PlannerFlowGuide.node(for: phase) })
    }
  }

  @Test
  func layoutPlacesEveryElementOnTheCanvas() {
    for size in [CGSize(width: 400, height: 300), CGSize(width: 1_600, height: 1_000)] {
      let layout = PlannerFlowLayout(canvas: size)
      #expect(layout.canvas.width >= PlannerFlowLayout.minimumCanvas.width)
      let bounds = CGRect(origin: .zero, size: layout.canvas)
      for id in PlannerFlowNodeID.allCases {
        let frame = layout.nodes[id]
        #expect(frame.map { bounds.contains($0) } == true, "\(id)")
        #expect((frame?.height ?? 0) >= 30, "\(id)")
      }
      for id in PlannerFlowEdgeID.allCases {
        let points = layout.edges[id] ?? []
        #expect(points.count >= 2, "\(id)")
        #expect(points.allSatisfy { bounds.insetBy(dx: -1, dy: -1).contains($0) }, "\(id)")
      }
    }
  }

  @Test
  func stepsDoNotOverlap() {
    let layout = PlannerFlowLayout(canvas: PlannerFlowLayout.minimumCanvas)
    let frames = PlannerFlowNodeID.allCases.compactMap { layout.nodes[$0] }
    for (index, frame) in frames.enumerated() {
      for other in frames[(index + 1)...] {
        #expect(!frame.intersects(other))
      }
    }
  }

  @Test
  func hitTestFindsArrowsWithinTheirZoneAndPrefersSteps() {
    let layout = PlannerFlowLayout(canvas: CGSize(width: 1_200, height: 800))
    let points = layout.edges[.loopBack]!
    let middle = CGPoint(x: points[1].x, y: (points[1].y + points[2].y) / 2)
    #expect(layout.element(at: middle) == .edge(.loopBack))
    #expect(layout.element(at: CGPoint(x: middle.x + 6, y: middle.y)) == .edge(.loopBack))
    #expect(layout.element(at: CGPoint(x: middle.x + 8, y: middle.y)) != .edge(.loopBack))
    let step = layout.nodes[.makeOrBuy]!
    #expect(layout.element(at: CGPoint(x: step.midX, y: step.midY)) == .node(.makeOrBuy))
  }

  @Test
  func cardKeepsItsWidthAndStaysVisibleInEveryCorner() {
    let visible = CGSize(width: 1_000, height: 600)
    #expect(PlannerFlowLayout.cardWidth(visibleWidth: 1_000) == 560)
    #expect(PlannerFlowLayout.cardWidth(visibleWidth: 800) == 480)
    #expect(PlannerFlowLayout.cardWidth(visibleWidth: 600) == 420)
    let size = CGSize(width: 560, height: 200)
    let bounds = CGRect(origin: .zero, size: visible)
    for pointer in [
      CGPoint(x: 0, y: 0), CGPoint(x: 1_000, y: 0), CGPoint(x: 0, y: 600), CGPoint(x: 1_000, y: 600),
    ] {
      let frame = PlannerFlowLayout.cardFrame(pointer: pointer, cardSize: size, visible: visible)
      #expect(bounds.contains(frame))
      #expect(frame.size == size)
    }
  }
}
