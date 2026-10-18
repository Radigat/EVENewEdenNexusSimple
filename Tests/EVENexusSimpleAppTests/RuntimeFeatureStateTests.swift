import AppKit
import EVENexusCore
import SwiftUI
import Testing

@testable import EVENexusSimpleApp

@MainActor
struct RuntimeFeatureStateTests {
  @Test
  func dashboardCardWidthsKeepRatiosAndStackOnNarrowWindows() {
    let finance = DashboardCardLayout(weights: [1, 2], minimumWidths: [280, 560])
    let wide = finance.widths(for: 1200)
    #expect(abs(wide[1] - 2 * wide[0]) < 0.01)
    #expect(finance.widths(for: 600) == [600, 600])
    let jobs = DashboardCardLayout(weights: [1, 1, 1], minimumWidths: [340, 340, 340])
    #expect(jobs.widths(for: 900) == [900, 900, 900])
    let three = jobs.widths(for: 1440)
    #expect(three.count == 3)
    #expect(three.allSatisfy { $0 >= 340 })
  }

  @Test
  func sharedAnalysisRefreshJoinsIdenticalRequestsAndSerializesChangedContexts() async {
    let refresh = SharedAnalysisRefresh()
    let gate = AnalysisRefreshTestGate()
    var calls: [String] = []
    let first = Task {
      await refresh.run(identity: "first") {
        calls.append("first")
        await gate.wait()
      }
    }
    while !gate.isWaiting { await Task.yield() }
    let same = Task { await refresh.run(identity: "first") { calls.append("duplicate") } }
    let changed = Task { await refresh.run(identity: "changed") { calls.append("changed") } }
    for _ in 0..<10 { await Task.yield() }
    #expect(calls == ["first"])
    gate.release()
    await first.value
    await same.value
    await changed.value
    #expect(calls == ["first", "changed"])
  }

  @Test
  func marketConfigurationIdentityIsStableAndChangesWithTheProfile() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let original = runtime.marketAnalysisContextIdentity
    for _ in 0..<20 { #expect(runtime.marketAnalysisContextIdentity == original) }
    runtime.productionBasis.cloneState = runtime.productionBasis.cloneState == .alpha ? .omega : .alpha
    #expect(runtime.marketAnalysisContextIdentity != original)
  }

  @Test
  func dashboardComponentsRenderWithEmptyShortAndLongLists() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("eve-dashboard-20261017/visual-checks")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for width: CGFloat in [600, 1000, 1440] {
      var shortHeight: CGFloat = 0
      for count in [0, 5, 50] {
        let controller = NSHostingController(rootView:
          DashboardRenderingFixture(count: count)
            .environment(\.locale, Locale(identifier: "de"))
            .frame(width: width))
        let size = controller.sizeThatFits(in: CGSize(width: width, height: 8000))
        #expect(size.width <= width + 1)
        #expect(size.height.isFinite && size.height > 280 && size.height < 4000)
        if count == 5 { shortHeight = size.height }
        // At narrow widths all three cards add their own disclosure control.
        if count == 50 { #expect(size.height <= shortHeight + 96) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        let view = controller.view
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("dashboard-\(Int(width))-\(count).png"))
        window.close()
      }
    }
  }

  @Test
  func initialWindowMaximizationUsesVisibleScreenAreaOnlyOnce() {
    let initialFrame = NSRect(x: 40, y: 50, width: 600, height: 420)
    let visibleFrame = NSRect(x: 0, y: 25, width: 1_440, height: 875)
    let manuallyResizedFrame = NSRect(x: 80, y: 90, width: 900, height: 640)
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    var maximization = InitialWindowMaximization()

    maximization.apply(to: window, visibleFrame: visibleFrame)
    #expect(window.frame == visibleFrame)
    #expect(maximization.hasApplied)

    window.setFrame(manuallyResizedFrame, display: false)
    maximization.apply(to: window, visibleFrame: visibleFrame)
    #expect(window.frame == manuallyResizedFrame)
  }

  @Test
  func sidebarStatusMinimumMeasurementDoesNotInflateWindowHeight() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let controller = NSHostingController(
      rootView: PublicContractSidebarStatus(runtime: runtime)
        .environment(\.locale, Locale(identifier: "de"))
    )
    // NavigationSplitView probes zero width when deriving its minimum size.
    // The multiline footer must remain as short as at the narrowest sidebar.
    let minimum = controller.sizeThatFits(in: .zero)
    let narrow = controller.sizeThatFits(
      in: CGSize(width: DesignTokens.sidebarMinimum, height: 480)
    )
    #expect(minimum.height <= narrow.height + 1)
    #expect(minimum.height < 240)
  }

  @Test
  func settingsNavigationKeepsItsIntrinsicHeight() {
    let controller = NSHostingController(
      rootView: DataSettingsNavigationBar(selection: .constant(.esi))
        .environment(\.locale, Locale(identifier: "de"))
    )
    for width: CGFloat in [420, 900, 2300] {
      let short = controller.sizeThatFits(in: CGSize(width: width, height: 80))
      let tall = controller.sizeThatFits(in: CGSize(width: width, height: 1300))
      #expect(abs(short.height - tall.height) <= 1)
      #expect(tall.height <= 80)
    }
  }

  @Test
  func settingsNavigationWidthDoesNotFollowOversizedPageContent() {
    for windowSize in [
      NSSize(width: 900, height: 540),
      NSSize(width: 2_555, height: 1_300),
    ] {
      var navigationFrames: [NSRect] = []

      for pageWidth: CGFloat in [320, 4_000] {
        let marker = NSView()
        let controller = NSHostingController(
          rootView: NavigationSplitView {
            Text("Navigation").navigationSplitViewColumnWidth(220)
          } detail: {
            SettingsWorkspaceLayout {
              DataSettingsNavigationBar(selection: .constant(.esi))
                .background(SettingsNavigationFrameProbe(view: marker))
            } content: {
              ScrollView {
                Color.clear
                  .frame(width: pageWidth, height: 1_000)
              }
            }
          }
          .toolbar { Button("Settings action") {} }
          .environment(\.locale, Locale(identifier: "de"))
        )
        let window = NSWindow(
          contentRect: NSRect(origin: .zero, size: windowSize),
          styleMask: [.titled, .resizable, .fullSizeContentView],
          backing: .buffered,
          defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.toolbarStyle = .unified
        window.setContentSize(windowSize)
        defer { window.close() }

        controller.view.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        controller.view.layoutSubtreeIfNeeded()

        let navigationFrame = marker.convert(marker.bounds, to: nil)
        navigationFrames.append(navigationFrame)
        #expect(marker.window === window)
        #expect(navigationFrame.minX >= 219)
        #expect(navigationFrame.maxX <= window.contentLayoutRect.maxX + 1)
      }

      #expect(navigationFrames.count == 2)
      #expect(abs(navigationFrames[0].minX - navigationFrames[1].minX) <= 1)
      #expect(abs(navigationFrames[0].width - navigationFrames[1].width) <= 1)
    }
  }

  @Test
  func settingsNavigationStaysBelowNativeToolbar() {
    let marker = NSView()
    let controller = NSHostingController(
      rootView: NavigationSplitView {
        Text("Navigation").navigationSplitViewColumnWidth(220)
      } detail: {
        VStack(spacing: 0) {
          EVEOnlineServiceBanner()
          SettingsWorkspaceLayout {
            DataSettingsNavigationBar(selection: .constant(.esi))
              .background(SettingsNavigationFrameProbe(view: marker))
          } content: {
            ScrollView {
              Text("Synthetic settings content").frame(minHeight: 1000)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("ESI")
          }.background(DesignTokens.canvas)
        }
      }
      .environmentObject(RuntimeState(startBackgroundServices: false))
      .toolbar { Button("Settings action") {} }
      .environment(\.locale, Locale(identifier: "de"))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
      styleMask: [.titled, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.toolbarStyle = .unified
    defer { window.close() }
    for size in [NSSize(width: 2555, height: 1300), NSSize(width: 900, height: 540)] {
      window.setContentSize(size)
      controller.view.layoutSubtreeIfNeeded()
      drainMainRunLoop()
      controller.view.layoutSubtreeIfNeeded()
      let header = marker.convert(marker.bounds, to: nil)
      print("HEADER frame=\(header) layout=\(window.contentLayoutRect) window=\(window.frame)")
      #expect(marker.window === window)
      #expect(header.height >= 24)
      #expect(header.maxY <= window.contentLayoutRect.maxY + 1)
    }
  }

  @Test
  func primaryNavigationKeepsPlannerAndIntegratesSupportingTools() {
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains("marketBrowser")
    )
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains(
        "recursiveProductionCalculation"
      )
    )
    #expect(
      !NavigationSection.allCases.map(\.rawValue).contains("industryJobs")
    )
    #expect(!NavigationSection.allCases.map(\.rawValue).contains("wallet"))
    #expect(NavigationSection.establishedCases.contains(.planner))
    #expect(NavigationSection.allCases.contains(.planner))
    #expect(
      NavigationSection.establishedCases.contains(.mineralPurchaseAnalysis)
    )
    #expect(DataSettingsSection.allCases.contains(.logistics))
    #expect(DataSettingsSection.allCases.contains(.general))
    #expect(DataSettingsSection.allCases.contains(.marketSettings))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Preisprofile"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Sicherung"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Projekte"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Reservierungen"))
    #expect(!ConsolidationArea.allCases.map(\.rawValue).contains("Einkauf"))
    #expect(ConsolidationArea.allCases == [.warehouses, .science, .sales])
  }

  @Test
  func mineralPurchaseAnalysisKeepsIndependentRuntimeAndExportIdentity() {
    let runtime = RuntimeState(startBackgroundServices: false)

    #expect(runtime.moonMaterialAnalysis == nil)
    #expect(runtime.mineralPurchaseAnalysis == nil)
    #expect(!runtime.isRefreshingMoonMaterialAnalysis)
    #expect(!runtime.isRefreshingMineralPurchaseAnalysis)

    let fileName = MaterialPurchaseImageExportNaming.fileName(
      kind: .minerals,
      at: Date(timeIntervalSince1970: 0)
    )
    #expect(fileName.hasPrefix("Mineralien-Kaufanalyse_"))
    #expect(fileName.hasSuffix(".png"))
  }

  @Test
  func unrelatedRuntimeChangesDoNotInvalidatePlannerFeature() {
    let runtime = RuntimeState(startBackgroundServices: false)

    runtime.statusMessage = "Public contracts are synchronizing"
    runtime.activeSDEBuild = 123
    runtime.installationPhase = "Preparing"
    runtime.cancelPublicContractSynchronization()

    #expect(runtime.plannerFeatureState.revision == 0)
  }

  @Test
  func plannerStateChangesInvalidateOnlyItsFeatureChannel() {
    let runtime = RuntimeState(startBackgroundServices: false)

    runtime.warehouseStockEnabled.toggle()
    #expect(runtime.plannerFeatureState.revision == 1)

    runtime.productionBasis = ProductionBasis()
    #expect(runtime.plannerFeatureState.revision == 2)

    runtime.plan = nil
    #expect(runtime.plannerFeatureState.revision == 3)
  }

  @Test
  func dashboardStartupRefreshCanBeReservedOnlyOncePerAppRuntime() {
    let runtime = RuntimeState(startBackgroundServices: false)

    #expect(runtime.reserveDashboardStartupRefresh())
    #expect(!runtime.reserveDashboardStartupRefresh())
  }

  @Test
  func netWorthHistoryUsesCalendarDistanceAndChangeFocusedScaling() {
    let first = Date(timeIntervalSince1970: 0)
    let secondDay = first.addingTimeInterval(24 * 60 * 60)
    let tenthDay = first.addingTimeInterval(9 * 24 * 60 * 60)

    #expect(
      abs(
        NetWorthHistoryGeometry.xFraction(
          date: secondDay,
          first: first,
          last: tenthDay
        ) - (1.0 / 9.0)
      ) < 0.000_001
    )
    let domain = NetWorthHistoryGeometry.valueDomain(
      values: [1_000_000_000, 1_010_000_000]
    )
    #expect(domain.lowerBound > 900_000_000)
    #expect(domain.upperBound > 1_010_000_000)
  }

  @Test
  func hostedPlannerSubscriberIgnoresUnrelatedRuntimePublication() {
    let runtime = RuntimeState(startBackgroundServices: false)
    let counter = RenderCounter()
    let hostingView = NSHostingView(
      rootView: PlannerObservationProbe(runtime: runtime, counter: counter)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
    hostingView.layoutSubtreeIfNeeded()
    drainMainRunLoop()
    let initialRenderCount = counter.value

    runtime.statusMessage = "Public Contracts progress"
    drainMainRunLoop()
    hostingView.layoutSubtreeIfNeeded()
    #expect(counter.value == initialRenderCount)

    runtime.warehouseStockEnabled.toggle()
    drainMainRunLoop()
    hostingView.layoutSubtreeIfNeeded()
    #expect(counter.value > initialRenderCount)
  }

  @Test
  func plannerInterruptsBothAutomaticScansUntilItFinishes() {
    var coordinator = InteractivePlannerWorkCoordinator()

    let startedMainHub = coordinator.beginAutomaticWork(.mainHubMarket)
    let startedContracts = coordinator.beginAutomaticWork(.publicContracts)
    #expect(startedMainHub)
    #expect(startedContracts)

    let interrupted = coordinator.beginPlannerCalculation(id: 1)
    #expect(interrupted == [.mainHubMarket, .publicContracts])
    #expect(!coordinator.canSchedule(.mainHubMarket))
    #expect(!coordinator.canSchedule(.publicContracts))

    let mainHubFinishedWhilePlanning =
      coordinator.finishAutomaticWork(.mainHubMarket)
    let contractsFinishedWhilePlanning =
      coordinator.finishAutomaticWork(.publicContracts)
    let lastPlannerFinished = coordinator.finishPlannerCalculation(id: 1)
    #expect(!mainHubFinishedWhilePlanning)
    #expect(!contractsFinishedWhilePlanning)
    #expect(lastPlannerFinished)
    #expect(coordinator.canSchedule(.mainHubMarket))
    #expect(coordinator.canSchedule(.publicContracts))
  }

  @Test
  func overlappingPlannerCalculationsResumeAutomationOnlyAfterTheLastOne() {
    var coordinator = InteractivePlannerWorkCoordinator()

    _ = coordinator.beginPlannerCalculation(id: 1)
    _ = coordinator.beginPlannerCalculation(id: 2)

    let firstPlannerFinished = coordinator.finishPlannerCalculation(id: 1)
    #expect(!firstPlannerFinished)
    #expect(!coordinator.canSchedule(.mainHubMarket))
    #expect(!coordinator.canSchedule(.publicContracts))

    let secondPlannerFinished = coordinator.finishPlannerCalculation(id: 2)
    #expect(secondPlannerFinished)
    #expect(coordinator.canSchedule(.mainHubMarket))
    #expect(coordinator.canSchedule(.publicContracts))
  }

  @Test
  func publicContractBackgroundPresentationKeepsLongImportControllable() {
    let incomplete = PublicContractSyncProgress(
      phase: .idle,
      regionCount: 100,
      completedRegions: 75,
      remainingInitialRegions: 25,
      indexedContracts: 1_000,
      pendingItemContracts: 250
    )
    let waiting = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: incomplete,
      isSynchronizing: false,
      isCancelling: false,
      automaticUpdatesEnabled: false
    )
    #expect(waiting.phase == .incomplete)
    #expect(waiting.progressFraction == nil)

    let running = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: PublicContractSyncProgress(
        phase: .loadingItems,
        regionCount: 100,
        completedRegions: 100,
        indexedContracts: 1_000,
        pendingItemContracts: 250
      ),
      isSynchronizing: true,
      isCancelling: false,
      automaticUpdatesEnabled: true
    )
    #expect(running.phase == .synchronizing)
    #expect(abs((running.progressFraction ?? 0) - 0.85) < 0.000_001)

    let stopping = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: incomplete,
      isSynchronizing: true,
      isCancelling: true,
      automaticUpdatesEnabled: false
    )
    #expect(stopping.phase == .stopping)

    let partial = PublicContractBackgroundPresentation(
      storeState: .ready,
      progress: PublicContractSyncProgress(
        phase: .partial,
        regionCount: 100,
        completedRegions: 100,
        freshRegions: 99,
        failedRegions: 1
      ),
      isSynchronizing: false,
      isCancelling: false,
      automaticUpdatesEnabled: false
    )
    #expect(partial.phase == .partial)
  }

  @Test
  func publicContractTypingWaitsButReturnSearchesImmediately() {
    #expect(
      PublicContractSearchPolicy.delay(isExplicitSubmission: false)
        == .milliseconds(700)
    )
    #expect(
      PublicContractSearchPolicy.delay(isExplicitSubmission: true) == nil
    )
  }

  private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
  }
}

@MainActor
private final class RenderCounter {
  private(set) var value = 0

  func record() {
    value += 1
  }
}

@MainActor
private final class AnalysisRefreshTestGate {
  private var continuation: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { continuation != nil }
  func wait() async {
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private struct PlannerObservationProbe: View {
  let runtime: RuntimeState
  let counter: RenderCounter
  @ObservedObject private var featureState: RuntimeFeatureState

  init(runtime: RuntimeState, counter: RenderCounter) {
    self.runtime = runtime
    self.counter = counter
    _featureState = ObservedObject(wrappedValue: runtime.plannerFeatureState)
  }

  var body: some View {
    counter.record()
    return Text("Planner revision \(featureState.revision)")
  }
}

private struct SettingsNavigationFrameProbe: NSViewRepresentable {
  let view: NSView
  func makeNSView(context: Context) -> NSView { view }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct DashboardRenderRow: Identifiable {
  let id: Int
}

private struct DashboardRenderingFixture: View {
  let count: Int
  private var rows: [DashboardRenderRow] { (0..<count).map { DashboardRenderRow(id: $0) } }
  private var samples: [DashboardWealthChartSample] {
    if count == 0 {
      return [DashboardWealthChartSample(date: Date(timeIntervalSince1970: 1_780_000_000), value: 0)]
    }
    return (0..<8).map {
      DashboardWealthChartSample(date: Date(timeIntervalSince1970: 1_780_000_000 + Double($0) * 86_400),
        value: 987_000_000_000 + Double($0 % 3) * 2_000_000_000)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      DashboardCardLayout(weights: [1, 1, 1], minimumWidths: [340, 340, 340]) {
        jobs(title: "Ready for delivery")
        jobs(title: "Next 48 hours")
        jobs(title: "Top 5 by material value")
      }
      DashboardCardLayout(weights: [1, 2], minimumWidths: [280, 560]) {
        Panel(title: "Wallet") {
          Text("987.654.321.098 ISK").font(.title).lineLimit(1).minimumScaleFactor(0.6)
          Text("3 Charaktere").font(.caption)
          DisclosureGroup("Character balances") { Text("Synthetic details") }
        }
        Panel(title: "Net worth over time") {
          Text("987.654.321.098 ISK").font(.title2)
          DashboardWealthChart(samples: samples, color: DesignTokens.accent, showsAxes: true)
            .frame(height: 280)
          DisclosureGroup("Character net worth") { Text("Synthetic details") }
        }
      }
    }
    .padding(DesignTokens.spacingLG)
    .background(DesignTokens.canvas)
  }

  private func jobs(title: LocalizedStringKey) -> some View {
    Panel(title: title) {
      DashboardPreviewList(rows: rows) { row in
        VStack(alignment: .leading) {
          EVEEntityText(value: "Synthetischer langer Produktname mit mehreren Bestandteilen \(row.id + 1)", font: .callout, lineLimit: 2)
          Text("987.654.321.098 ISK · 3 Charaktere").font(.caption).monospacedDigit()
        }
      }
    }
  }
}
