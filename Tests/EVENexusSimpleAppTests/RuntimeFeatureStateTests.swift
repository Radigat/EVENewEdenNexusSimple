import AppKit
import EVENexusCore
import SwiftUI
import Testing

@testable import EVENexusSimpleApp

@MainActor
struct RuntimeFeatureStateTests {
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
  func primaryNavigationKeepsPlannerAndMovesLogisticsIntoSettings() {
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
