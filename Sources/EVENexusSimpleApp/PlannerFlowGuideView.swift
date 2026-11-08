import SwiftUI

/// Button beside the Planner's title that opens the info panel.
struct PlannerFlowGuideButton: View {
  @Binding var isPresented: Bool

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label(AppLocalization.text(PlannerFlowGuide.panelTitle), systemImage: "info.circle")
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("planner.flow-guide.open")
  }
}

/// Dims the work area and shows the panel at 80 % of its width and height.
struct PlannerFlowGuideOverlay: View {
  @Binding var isPresented: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.opacity(0.45)
          .contentShape(Rectangle())
          .onTapGesture { isPresented = false }
          .accessibilityHidden(true)
        PlannerFlowGuidePanel(isPresented: $isPresented)
          .frame(width: proxy.size.width * 0.8, height: proxy.size.height * 0.8)
      }
    }
  }
}

private struct PlannerFlowGuidePanel: View {
  @Binding var isPresented: Bool

  @State private var hovered: PlannerFlowElement?
  @State private var pinned: PlannerFlowElement?
  @State private var pointer = CGPoint.zero
  @State private var pinnedPointer = CGPoint.zero
  @State private var cardHeight: CGFloat = 120
  @FocusState private var focused: PlannerFlowElement?

  private static let viewport = "planner.flow-guide.viewport"

  private var active: PlannerFlowElement? { pinned ?? hovered ?? focused }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      header
      legend
      diagramViewport
    }
    .padding(DesignTokens.spacingMD)
    .background(
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius).fill(DesignTokens.panel)
    )
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    )
    .shadow(color: DesignTokens.panelShadow, radius: 18)
    .hudCornerBrackets()
    .background {
      // Esc first releases a pinned explanation, then closes the panel.
      Button("") {
        if pinned != nil {
          pinned = nil
        } else {
          isPresented = false
        }
      }
      .keyboardShortcut(.cancelAction)
      .opacity(0)
      .accessibilityHidden(true)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(AppLocalization.text(PlannerFlowGuide.panelTitle))
    .accessibilityIdentifier("planner.flow-guide.panel")
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingMD) {
      Text(AppLocalization.text(PlannerFlowGuide.panelTitle))
        .appFont(.title2.bold())
      Text(AppLocalization.text(PlannerFlowGuide.summary))
        .foregroundStyle(DesignTokens.textSecondary)
        .lineLimit(2)
      Spacer(minLength: DesignTokens.spacingSM)
      Button {
        isPresented = false
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .accessibilityLabel(AppLocalization.text("Close"))
    }
  }

  private var legend: some View {
    HStack(spacing: DesignTokens.spacingMD) {
      ForEach(PlannerFlowRole.allCases, id: \.self) { role in
        Label(AppLocalization.text(role.title), systemImage: role.symbol)
          .foregroundStyle(role.color)
          .appFont(.caption)
      }
    }
  }

  private var diagramViewport: some View {
    GeometryReader { proxy in
      let layout = PlannerFlowLayout(canvas: proxy.size)
      ZStack(alignment: .topLeading) {
        ScrollView([.horizontal, .vertical]) {
          diagram(layout)
        }
        .scrollIndicators(
          layout.canvas.width > proxy.size.width || layout.canvas.height > proxy.size.height
            ? .automatic : .hidden
        )
        if let active {
          explanationCard(for: active, layout: layout, visible: proxy.size)
        }
      }
      .coordinateSpace(name: Self.viewport)
    }
  }

  private func diagram(_ layout: PlannerFlowLayout) -> some View {
    ZStack(alignment: .topLeading) {
      columnBackgrounds(layout)
      edgeLayer(layout)
      nodeLayer(layout)
      accessibilityLayer(layout)
    }
    .frame(width: layout.canvas.width, height: layout.canvas.height, alignment: .topLeading)
    .contentShape(Rectangle())
    .onContinuousHover(coordinateSpace: .local) { phase in
      switch phase {
      case .active(let location): hovered = layout.element(at: location)
      case .ended: hovered = nil
      }
    }
    .onContinuousHover(coordinateSpace: .named(Self.viewport)) { phase in
      if case .active(let location) = phase { pointer = location }
    }
    .onTapGesture(coordinateSpace: .local) { location in
      togglePin(layout.element(at: location))
    }
  }

  private func togglePin(_ element: PlannerFlowElement?) {
    if pinned != nil {
      pinned = nil
    } else if let element {
      pinned = element
      pinnedPointer = pointer
    }
  }

  private func columnBackgrounds(_ layout: PlannerFlowLayout) -> some View {
    ForEach(PlannerFlowColumn.allCases, id: \.self) { column in
      if let frame = layout.columns[column] {
        let isBand = column == .interventions
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .fill(DesignTokens.elevated.opacity(0.35))
          .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
              .stroke(
                DesignTokens.border,
                style: StrokeStyle(lineWidth: 1, dash: isBand ? [5, 4] : [])
              )
          )
          .frame(width: frame.width, height: frame.height)
          .offset(x: frame.minX, y: frame.minY)
        Text(AppLocalization.text(column.title))
          .appFont(.headline)
          .lineLimit(1)
          .offset(x: frame.minX + 8, y: isBand ? frame.minY + 5 : frame.minY - 24)
      }
    }
    .accessibilityHidden(true)
  }

  private func edgeLayer(_ layout: PlannerFlowLayout) -> some View {
    ForEach(PlannerFlowGuide.edges) { edge in
      let isActive = active == .edge(edge.id)
      PlannerFlowArrow(points: layout.edges[edge.id] ?? [])
        .stroke(
          isActive
            ? DesignTokens.highlight
            : (edge.isIntervention ? PlannerFlowRole.intervention.color : DesignTokens.textSecondary),
          style: StrokeStyle(
            lineWidth: isActive ? 3 : 1.5,
            lineCap: .round,
            lineJoin: .round,
            dash: edge.isIntervention ? [6, 4] : []
          )
        )
        .allowsHitTesting(false)
    }
    .accessibilityHidden(true)
  }

  private func nodeLayer(_ layout: PlannerFlowLayout) -> some View {
    ForEach(PlannerFlowGuide.nodes) { node in
      if let frame = layout.nodes[node.id] {
        nodeView(node, isHighlighted: isHighlighted(node.id))
          .frame(width: frame.width, height: frame.height)
          .offset(x: frame.minX, y: frame.minY)
          .allowsHitTesting(false)
      }
    }
    .accessibilityHidden(true)
  }

  /// A step lights up when hovered itself or as an end of the active arrow.
  private func isHighlighted(_ id: PlannerFlowNodeID) -> Bool {
    switch active {
    case .node(let activeID):
      return activeID == id
    case .edge(let edgeID):
      guard let edge = PlannerFlowGuide.edges.first(where: { $0.id == edgeID }) else { return false }
      return edge.from == .node(id) || edge.to == .node(id)
    case nil:
      return false
    }
  }

  private func nodeView(_ node: PlannerFlowNode, isHighlighted: Bool) -> some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Image(systemName: node.role.symbol)
        .foregroundStyle(node.role.color)
      Text(AppLocalization.text(node.title))
        .appFont(.callout.weight(node.id == .calculate ? .bold : .medium))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .fill(isHighlighted ? DesignTokens.accentSoft : DesignTokens.panel)
    )
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
        .stroke(
          isHighlighted ? DesignTokens.highlight : node.role.color,
          style: StrokeStyle(
            lineWidth: isHighlighted ? 2.5 : 1,
            dash: node.role == .intervention ? [5, 3] : []
          )
        )
    )
  }

  /// Invisible stand-ins that give the drawn steps and arrows keyboard focus
  /// and a VoiceOver reading order. The mouse goes through them.
  private func accessibilityLayer(_ layout: PlannerFlowLayout) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(PlannerFlowGuide.nodes) { node in
        if let frame = layout.nodes[node.id] {
          accessibilityElement(.node(node.id), title: node.title, explanation: node.explanation)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        }
      }
      ForEach(PlannerFlowGuide.edges) { edge in
        let anchor = layout.anchor(of: .edge(edge.id))
        accessibilityElement(.edge(edge.id), title: edge.title, explanation: edge.explanation)
          .frame(width: 14, height: 14)
          .offset(x: anchor.x - 7, y: anchor.y - 7)
      }
    }
    .allowsHitTesting(false)
  }

  private func accessibilityElement(
    _ element: PlannerFlowElement,
    title: String,
    explanation: String
  ) -> some View {
    Color.clear
      .focusable()
      .focused($focused, equals: element)
      .onKeyPress(.return) {
        pinned = pinned == element ? nil : element
        return .handled
      }
      .accessibilityElement()
      .accessibilityLabel(AppLocalization.text(title))
      .accessibilityValue(AppLocalization.text(explanation))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { pinned = pinned == element ? nil : element }
  }

  private func content(of element: PlannerFlowElement) -> (title: String, explanation: String)? {
    switch element {
    case .node(let id):
      PlannerFlowGuide.nodes.first { $0.id == id }.map { ($0.title, $0.explanation) }
    case .edge(let id):
      PlannerFlowGuide.edges.first { $0.id == id }.map { ($0.title, $0.explanation) }
    }
  }

  @ViewBuilder
  private func explanationCard(
    for element: PlannerFlowElement,
    layout: PlannerFlowLayout,
    visible: CGSize
  ) -> some View {
    if let content = content(of: element) {
      let width = PlannerFlowLayout.cardWidth(visibleWidth: visible.width)
      let isPinned = pinned == element
      let anchor = cardAnchor(for: element, layout: layout, isPinned: isPinned)
      let frame = PlannerFlowLayout.cardFrame(
        pointer: anchor,
        cardSize: CGSize(width: width, height: cardHeight),
        visible: visible
      )
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack {
          Text(AppLocalization.text(content.title))
            .appFont(.title2.bold())
          Spacer(minLength: DesignTokens.spacingSM)
          if isPinned {
            Button {
              pinned = nil
            } label: {
              Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("Release explanation"))
          }
        }
        Text(AppLocalization.text(content.explanation))
          .appFont(.title3)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .padding(DesignTokens.spacingMD)
      .frame(width: width, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius).fill(DesignTokens.panel)
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
          .stroke(DesignTokens.highlight, lineWidth: isPinned ? 2 : 1)
      )
      .shadow(color: DesignTokens.panelShadow, radius: 10)
      .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardHeight = $0 }
      .offset(x: frame.minX, y: frame.minY)
      // Only a pinned card takes the mouse, so hovering stays continuous.
      .allowsHitTesting(isPinned)
      .accessibilityHidden(true)
    }
  }

  private func cardAnchor(
    for element: PlannerFlowElement,
    layout: PlannerFlowLayout,
    isPinned: Bool
  ) -> CGPoint {
    if isPinned { return pinnedPointer == .zero ? layout.anchor(of: element) : pinnedPointer }
    return hovered == element ? pointer : layout.anchor(of: element)
  }
}

private struct PlannerFlowArrow: Shape {
  let points: [CGPoint]

  func path(in _: CGRect) -> Path {
    var path = Path()
    guard let first = points.first, points.count > 1, let last = points.last else { return path }
    path.move(to: first)
    points.dropFirst().forEach { path.addLine(to: $0) }
    let previous = points[points.count - 2]
    let angle = atan2(last.y - previous.y, last.x - previous.x)
    for spread in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
      path.move(to: last)
      path.addLine(
        to: CGPoint(x: last.x + 9 * cos(angle + spread), y: last.y + 9 * sin(angle + spread))
      )
    }
    return path
  }
}

extension PlannerFlowRole {
  fileprivate var color: Color {
    switch self {
    case .input: DesignTokens.information
    case .automatic: DesignTokens.accent
    case .intervention: DesignTokens.caution
    case .result: DesignTokens.positive
    }
  }
}
