import AppKit
import SwiftUI
import Testing

@testable import EVENexusSimpleApp

/// Debug stack overflow in the Planner (09.11.2026): opening "All sale paths
/// in detail" for a single product crashed the Debug build with
/// `EXC_BAD_ACCESS` in `___chkstk_darwin`. `PlannerView.body` held every step
/// inline (117,880 bytes), and the unoptimised build kept several copies of
/// those values on the main-thread stack. `DeferredViewBody` moves the steps,
/// the historical plan and the sale scenario cards into body passes of their
/// own.
@MainActor
@Suite("Planner view stack budget")
struct PlannerViewStackBudgetTests {
  @Test
  func plannerBodyStaysSmallBecauseItsStepsBuildSeparately() {
    // 4,344 bytes after the fix; inline steps would push it past 100 KB again.
    #expect(MemoryLayout<PlannerView.Body>.size < 16 * 1024)
  }

  @Test
  func deferredBodyStoresOnlyItsClosure() {
    #expect(
      MemoryLayout<DeferredViewBody<Text>>.size
        == MemoryLayout<() -> Text>.size
    )
  }

  @Test
  func deferredMultiViewContentLaysOutLikeInlineContent() {
    let inline = height(
      VStack(alignment: .leading, spacing: 13) {
        Text(verbatim: "A")
        Text(verbatim: "B")
        Text(verbatim: "C")
      }
    )
    let deferred = height(
      VStack(alignment: .leading, spacing: 13) {
        Text(verbatim: "A")
        DeferredViewBody {
          Text(verbatim: "B")
          Text(verbatim: "C")
        }
      }
    )
    #expect(inline > 0)
    #expect(deferred == inline)
  }

  private func height(_ view: some View) -> CGFloat {
    NSHostingView(rootView: view.fixedSize()).fittingSize.height
  }
}
