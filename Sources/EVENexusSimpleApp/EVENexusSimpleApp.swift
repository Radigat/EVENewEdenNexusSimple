import EVENexusCore
import SwiftData
import SwiftUI

@main
struct EVENexusSimpleApp: App {
  @StateObject private var runtime = RuntimeState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(runtime)
        .preferredColorScheme(.dark)
    }
    .modelContainer(
      for: [
        StoredProductionBasis.self,
        StoredManufacturingProfile.self,
        StoredReactionProfile.self,
        StoredCharacter.self,
        StoredStockTarget.self,
        StoredPlan.self,
        StoredPlannerDraft.self,
        StoredProductionRecord.self,
        StoredProductionOverviewRow.self,
        StoredSDEActivationPointer.self,
        StoredESISnapshotMetadata.self,
        AppSetting.self,
      ]
    )
    .windowStyle(.titleBar)
    .defaultSize(width: 1_280, height: 820)
  }
}
