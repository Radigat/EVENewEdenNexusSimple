import CoreGraphics

enum PlannerFlowElement: Hashable {
  case node(PlannerFlowNodeID)
  case edge(PlannerFlowEdgeID)
}

/// Geometry of the diagram for one canvas size. It holds no view state, so hit
/// testing and card placement can be checked without rendering.
struct PlannerFlowLayout {
  static let minimumCanvas = CGSize(width: 1_040, height: 640)
  static let edgeHitDistance: CGFloat = 7
  static let minimumCardWidth: CGFloat = 420
  static let maximumCardWidth: CGFloat = 560

  private static let headerHeight: CGFloat = 26
  private static let bandHeight: CGFloat = 92
  private static let laneHeight: CGFloat = 62
  private static let groupPadding: CGFloat = 8

  let canvas: CGSize
  private(set) var columns: [PlannerFlowColumn: CGRect] = [:]
  private(set) var nodes: [PlannerFlowNodeID: CGRect] = [:]
  private(set) var edges: [PlannerFlowEdgeID: [CGPoint]] = [:]

  init(canvas requested: CGSize) {
    canvas = CGSize(
      width: max(requested.width, Self.minimumCanvas.width),
      height: max(requested.height, Self.minimumCanvas.height)
    )
    layoutColumns()
    layoutNodes()
    layoutEdges()
  }

  private mutating func layoutColumns() {
    let width = canvas.width
    let top = Self.headerHeight
    let bottom = canvas.height - Self.bandHeight - Self.laneHeight
    let height = bottom - top
    columns[.inputs] = CGRect(x: 0, y: top, width: width * 0.19, height: height)
    columns[.data] = CGRect(x: width * 0.235, y: top, width: width * 0.17, height: height)
    columns[.calculation] = CGRect(x: width * 0.475, y: top, width: width * 0.23, height: height)
    columns[.results] = CGRect(x: width * 0.81, y: top, width: width * 0.19, height: height)
    columns[.interventions] = CGRect(
      x: 0,
      y: canvas.height - Self.bandHeight,
      width: width,
      height: Self.bandHeight
    )
  }

  private mutating func layoutNodes() {
    for column in [PlannerFlowColumn.data, .calculation, .results] {
      stack(PlannerFlowGuide.nodes(in: column).map(\.id), in: columns[column]!)
    }
    // Calculate sits apart from the input group so that the group's single
    // arrow visibly leads into the button.
    let inputs = columns[.inputs]!
    let calculateHeight = min(64, inputs.height * 0.16)
    let calculateFrame = CGRect(
      x: inputs.minX,
      y: inputs.maxY - calculateHeight,
      width: inputs.width,
      height: calculateHeight
    )
    let group = CGRect(
      x: inputs.minX,
      y: inputs.minY,
      width: inputs.width,
      height: inputs.height - calculateHeight - 36
    )
    columns[.inputs] = group
    nodes[.calculate] = calculateFrame
    stack(
      PlannerFlowGuide.nodes(in: .inputs).map(\.id).filter { $0 != .calculate },
      in: group
    )

    let band = columns[.interventions]!.insetBy(dx: Self.groupPadding, dy: Self.groupPadding)
    let bandNodes = PlannerFlowGuide.nodes(in: .interventions).map(\.id)
    let gap: CGFloat = 8
    let nodeWidth = (band.width - gap * CGFloat(bandNodes.count - 1)) / CGFloat(bandNodes.count)
    for (index, id) in bandNodes.enumerated() {
      nodes[id] = CGRect(
        x: band.minX + CGFloat(index) * (nodeWidth + gap),
        y: band.minY + 22,
        width: nodeWidth,
        height: band.height - 22
      )
    }
  }

  private mutating func stack(_ ids: [PlannerFlowNodeID], in group: CGRect) {
    let inner = group.insetBy(dx: Self.groupPadding, dy: Self.groupPadding)
    let gap: CGFloat = 14
    let height = (inner.height - gap * CGFloat(ids.count - 1)) / CGFloat(ids.count)
    for (index, id) in ids.enumerated() {
      nodes[id] = CGRect(
        x: inner.minX,
        y: inner.minY + CGFloat(index) * (height + gap),
        width: inner.width,
        height: height
      )
    }
  }

  private mutating func layoutEdges() {
    let width = canvas.width
    let inputs = columns[.inputs]!
    let data = columns[.data]!
    let results = columns[.results]!
    let band = columns[.interventions]!
    let calculate = nodes[.calculate]!

    edges[.inputsToCalculate] = [
      CGPoint(x: inputs.midX, y: inputs.maxY),
      CGPoint(x: inputs.midX, y: calculate.minY),
    ]
    edges[.calculateToData] = [
      CGPoint(x: calculate.maxX, y: calculate.midY),
      CGPoint(x: data.minX, y: calculate.midY),
    ]
    let source = nodes[.blueprintSource]!
    edges[.dataToBlueprints] = [
      CGPoint(x: data.maxX, y: source.midY - 10),
      CGPoint(x: source.minX, y: source.midY - 10),
    ]

    for (id, from, to) in [
      (PlannerFlowEdgeID.blueprintsToMaterials, PlannerFlowNodeID.blueprintSource, PlannerFlowNodeID.billOfMaterials),
      (.materialsToMakeOrBuy, .billOfMaterials, .makeOrBuy),
      (.makeOrBuyToPurchase, .makeOrBuy, .purchaseSplit),
      (.purchaseToLoop, .purchaseSplit, .automaticLoop),
      (.loopToControl, .automaticLoop, .controlPass),
      (.controlToSave, .controlPass, .savePlan),
    ] {
      edges[id] = [
        CGPoint(x: nodes[from]!.midX, y: nodes[from]!.maxY),
        CGPoint(x: nodes[to]!.midX, y: nodes[to]!.minY),
      ]
    }

    let rightInner = nodes[.makeOrBuy]!.maxX + width * 0.025
    let rightOuter = nodes[.makeOrBuy]!.maxX + width * 0.055
    edges[.loopBack] = [
      CGPoint(x: nodes[.automaticLoop]!.maxX, y: nodes[.automaticLoop]!.midY),
      CGPoint(x: rightInner, y: nodes[.automaticLoop]!.midY),
      CGPoint(x: rightInner, y: nodes[.makeOrBuy]!.midY),
      CGPoint(x: nodes[.makeOrBuy]!.maxX, y: nodes[.makeOrBuy]!.midY),
    ]
    edges[.controlBack] = [
      CGPoint(x: nodes[.controlPass]!.maxX, y: nodes[.controlPass]!.midY),
      CGPoint(x: rightOuter, y: nodes[.controlPass]!.midY),
      CGPoint(x: rightOuter, y: source.midY),
      CGPoint(x: source.maxX, y: source.midY),
    ]
    edges[.saveToResults] = [
      CGPoint(x: nodes[.savePlan]!.maxX, y: nodes[.savePlan]!.midY),
      CGPoint(x: results.minX, y: nodes[.savePlan]!.midY),
    ]

    edges[.resultsToInterventions] = [
      CGPoint(x: results.minX + results.width * 0.25, y: results.maxY),
      CGPoint(x: results.minX + results.width * 0.25, y: band.minY),
    ]
    edges[.interventionsToCalculate] = [
      CGPoint(x: calculate.midX, y: band.minY),
      CGPoint(x: calculate.midX, y: calculate.maxY),
    ]
    edges[.saleChoiceToResults] = [
      CGPoint(x: results.minX + results.width * 0.75, y: nodes[.saleChoice]!.minY),
      CGPoint(x: results.minX + results.width * 0.75, y: results.maxY),
    ]

    // Interventions rise through the gutter left of the calculation. A later
    // target takes a gutter lane further right, so the routes never cross.
    let gutterRight = source.minX
    let gutterStep = width * 0.012
    interventionEdge(
      .blueprintChoiceToSource, from: .blueprintChoice, to: .blueprintSource,
      gutterX: gutterRight - gutterStep * 3, laneOffset: 42, entryOffset: 10
    )
    interventionEdge(
      .jobSplitToMaterials, from: .jobSplit, to: .billOfMaterials,
      gutterX: gutterRight - gutterStep * 2, laneOffset: 28, entryOffset: 0
    )
    interventionEdge(
      .supplyChoiceToMakeOrBuy, from: .supplyChoice, to: .makeOrBuy,
      gutterX: gutterRight - gutterStep, laneOffset: 14, entryOffset: 0
    )
  }

  private mutating func interventionEdge(
    _ id: PlannerFlowEdgeID,
    from: PlannerFlowNodeID,
    to: PlannerFlowNodeID,
    gutterX: CGFloat,
    laneOffset: CGFloat,
    entryOffset: CGFloat
  ) {
    let start = nodes[from]!
    let target = nodes[to]!
    let laneY = columns[.interventions]!.minY - laneOffset
    edges[id] = [
      CGPoint(x: start.midX, y: start.minY),
      CGPoint(x: start.midX, y: laneY),
      CGPoint(x: gutterX, y: laneY),
      CGPoint(x: gutterX, y: target.midY + entryOffset),
      CGPoint(x: target.minX, y: target.midY + entryOffset),
    ]
  }

  /// Steps take precedence over arrows; among arrows the nearest one wins.
  func element(at point: CGPoint) -> PlannerFlowElement? {
    if let node = PlannerFlowNodeID.allCases.first(where: { nodes[$0]?.contains(point) == true }) {
      return .node(node)
    }
    var nearest: (id: PlannerFlowEdgeID, distance: CGFloat)?
    for id in PlannerFlowEdgeID.allCases {
      guard let points = edges[id] else { continue }
      let distance = Self.distance(from: point, toPolyline: points)
      if distance <= Self.edgeHitDistance, distance < (nearest?.distance ?? .infinity) {
        nearest = (id, distance)
      }
    }
    return nearest.map { .edge($0.id) }
  }

  /// A point on the element, used as the card's anchor for keyboard focus.
  func anchor(of element: PlannerFlowElement) -> CGPoint {
    switch element {
    case .node(let id):
      let frame = nodes[id] ?? .zero
      return CGPoint(x: frame.midX, y: frame.midY)
    case .edge(let id):
      let points = edges[id] ?? []
      guard points.count > 1 else { return points.first ?? .zero }
      let middle = points.count / 2
      return CGPoint(
        x: (points[middle - 1].x + points[middle].x) / 2,
        y: (points[middle - 1].y + points[middle].y) / 2
      )
    }
  }

  static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return .infinity }
    return zip(points, points.dropFirst())
      .map { distance(from: point, toSegment: $0, $1) }
      .min() ?? .infinity
  }

  private static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
    let position = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
    return hypot(point.x - (start.x + position * dx), point.y - (start.y + position * dy))
  }

  /// The card adapts to the visible width but never falls below a readable
  /// width, unless the visible area itself is narrower.
  static func cardWidth(visibleWidth: CGFloat) -> CGFloat {
    let preferred = max(minimumCardWidth, min(maximumCardWidth, visibleWidth * 0.6))
    return min(preferred, max(visibleWidth - 16, 0))
  }

  /// Places the card beside the pointer, flips to the free side and keeps it
  /// inside the visible area.
  static func cardFrame(pointer: CGPoint, cardSize: CGSize, visible: CGSize) -> CGRect {
    let gap: CGFloat = 16
    let margin: CGFloat = 8
    var x = pointer.x + gap
    if x + cardSize.width + margin > visible.width {
      x = pointer.x - gap - cardSize.width
    }
    var y = pointer.y + gap
    if y + cardSize.height + margin > visible.height {
      y = pointer.y - gap - cardSize.height
    }
    x = max(margin, min(x, visible.width - cardSize.width - margin))
    y = max(margin, min(y, visible.height - cardSize.height - margin))
    return CGRect(origin: CGPoint(x: x, y: y), size: cardSize)
  }
}
