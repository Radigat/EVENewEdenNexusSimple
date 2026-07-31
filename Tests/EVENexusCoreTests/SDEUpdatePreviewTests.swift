import Foundation
import Testing

@testable import EVENexusCore

@Suite("SDE update preview")
struct SDEUpdatePreviewTests {
  @Test
  func currentBuildExplainsThatNoNewerSchemaBoundaryNeedsReview() {
    let preview = makePreview(
      activeBuild: 3_451_778,
      officialBuild: 3_451_778,
      schemaHighestAfterBuild: 3_407_448
    )

    #expect(preview.availability == .current)
    #expect(!preview.requiresUpdate)
    #expect(!preview.requiresSchemaReview)
  }

  @Test
  func newerOfficialBuildIsAnUpdateEvenWithoutANewSchemaBoundary() {
    let preview = makePreview(
      activeBuild: 3_448_696,
      officialBuild: 3_451_778,
      schemaHighestAfterBuild: 3_407_448
    )

    #expect(preview.availability == .updateAvailable)
    #expect(preview.requiresUpdate)
    #expect(!preview.requiresSchemaReview)
  }

  @Test
  func olderOfficialMetadataNeverOffersADowngrade() {
    let preview = makePreview(
      activeBuild: 3_451_778,
      officialBuild: 3_448_696,
      schemaHighestAfterBuild: 3_407_448
    )

    #expect(preview.availability == .localBuildAhead)
    #expect(!preview.requiresUpdate)
  }

  @Test
  func schemaBoundaryAfterInstalledBuildRequiresExplicitReview() {
    let preview = makePreview(
      activeBuild: 3_448_696,
      officialBuild: 3_451_778,
      schemaHighestAfterBuild: 3_450_000
    )

    #expect(preview.requiresSchemaReview)
  }

  private func makePreview(
    activeBuild: Int?,
    officialBuild: Int,
    schemaHighestAfterBuild: Int
  ) -> SDEUpdatePreview {
    SDEUpdatePreview(
      activeBuild: activeBuild,
      officialBuild: officialBuild,
      releasedAt: Date(timeIntervalSince1970: 1_700_000_000),
      schemaHighestAfterBuild: schemaHighestAfterBuild,
      schemaEntryCount: 15
    )
  }
}
