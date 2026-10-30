import AppKit
import ServiceManagement
import Testing

@testable import EVENexusSimpleApp

@MainActor
struct BackgroundOperationTests {
  @Test
  func dockIconHidesOnlyWhileRunningWithoutWindow() {
    // Owner decision 29.10.2026: without a window only the menu bar item.
    #expect(
      BackgroundOperation.activationPolicy(keepsRunning: true, hasVisibleMainWindow: false)
        == .accessory
    )
    #expect(
      BackgroundOperation.activationPolicy(keepsRunning: true, hasVisibleMainWindow: true)
        == .regular
    )
    #expect(
      BackgroundOperation.activationPolicy(keepsRunning: false, hasVisibleMainWindow: false)
        == .regular
    )
    #expect(BackgroundOperation.keepRunningDefault)
  }

  @Test
  func loginItemLaunchIsRecognizedFromTheLaunchEvent() {
    func openEvent(loginItem: Bool?) -> NSAppleEventDescriptor {
      let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass),
        eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
      )
      if let loginItem {
        event.setParam(
          NSAppleEventDescriptor(
            enumCode: loginItem ? OSType(keyAELaunchedAsLogInItem) : OSType(0)
          ),
          forKeyword: AEKeyword(keyAEPropData)
        )
      }
      return event
    }
    #expect(BackgroundOperation.isLoginItemLaunch(openEvent(loginItem: true)))
    #expect(!BackgroundOperation.isLoginItemLaunch(openEvent(loginItem: false)))
    #expect(!BackgroundOperation.isLoginItemLaunch(openEvent(loginItem: nil)))
    #expect(!BackgroundOperation.isLoginItemLaunch(nil))
  }

  @Test
  func loginItemStatusKeepsApprovalVisible() {
    #expect(LoginItemPresentation(.enabled) == .enabled)
    #expect(LoginItemPresentation(.requiresApproval) == .requiresApproval)
    #expect(LoginItemPresentation(.notRegistered) == .disabled)
    #expect(LoginItemPresentation(.notFound) == .unavailable)
    // Registered but not yet approved still shows the switch as on.
    #expect(LoginItemPresentation.requiresApproval.isOn)
    #expect(!LoginItemPresentation.disabled.isOn)
  }

  @Test
  func onlyCatalogWideOrderBookPagesBlockAHubScan() {
    #expect(RuntimeState.isHubOrderBookURL(
      URL(string: "https://esi.evetech.net/markets/10000002/orders/?order_type=all&page=3")!))
    // Per-item Planner requests stay in the response cache and do not block.
    #expect(!RuntimeState.isHubOrderBookURL(
      URL(string: "https://esi.evetech.net/markets/10000002/orders/?type_id=34&page=1")!))
    #expect(!RuntimeState.isHubOrderBookURL(
      URL(string: "https://esi.evetech.net/markets/structures/1035466617946/?page=1")!))
    #expect(!RuntimeState.isHubOrderBookURL(
      URL(string: "https://esi.evetech.net/markets/prices/")!))
  }

  @Test
  func fetchNowWaitsUntilAPointWouldBeStored() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    // A hub without a point: a point would be stored right away.
    #expect(RuntimeState.marketStockStorableAt(latestPoints: [now, nil]) == nil)
    #expect(RuntimeState.marketStockStorableAt(latestPoints: []) == nil)
    // Otherwise 30 minutes after the oldest latest point of all hubs.
    #expect(
      RuntimeState.marketStockStorableAt(
        latestPoints: [now, now.addingTimeInterval(-600)]
      ) == now.addingTimeInterval(1_200)
    )
  }

  @Test
  func noHubScanIsBlockedBeforeAnyOrderBookWasLoaded() {
    let runtime = RuntimeState(startBackgroundServices: false)
    runtime.updateHubScanAvailability()
    #expect(runtime.hubScanAvailableAt == nil)
    #expect(!runtime.isHubScanBlockedByESICache)
    #expect(runtime.hubScanBlockedText == nil)
  }

  @Test
  func fetchNowDoesNothingWithoutBackgroundServices() {
    let runtime = RuntimeState(startBackgroundServices: false)
    runtime.requestMarketStockScanNow()
    #expect(!runtime.isAutomaticallyRefreshingMainHubMarket)
    #expect(!runtime.isAnalyzingManufacturingOpportunities)
  }
}
