import Foundation
import Testing

@testable import EVEStaticDataKit

@Test
func exposesPortableIdentity() {
  #expect(EVEStaticDataKit.version == "0.1.0")
  #expect(
    EVEStaticDataKit.stagingFormatIdentifier
      == "com.evestaticdatakit.sde-staging"
  )
  #expect(EVEStaticDataKit.stagingPackageExtension == "evesde")
}

@Test
func preservesTypeProductionClassificationMetadata() {
  let item = StaticItemTypeSnapshot(
    externalID: 1,
    groupExternalID: 2,
    categoryExternalID: 3,
    marketGroupExternalID: 4,
    name: "Fixture",
    description: nil,
    volume: 1,
    packagedVolume: 1,
    basePrice: nil,
    portionSize: 1,
    published: true,
    iconExternalID: nil,
    metaGroupExternalID: 14,
    techLevel: 3
  )

  #expect(item.metaGroupExternalID == 14)
  #expect(item.techLevel == 3)
}

@Test
func constructsStrictBuildSpecificArchiveURL() throws {
  let url = try CCPSDEArchiveDownloader.officialURL(buildNumber: 123)
  #expect(
    url.absoluteString
      == "https://developers.eveonline.com/static-data/tranquility/eve-online-static-data-123-jsonl.zip"
  )
  #expect(throws: SDEInstallationError.invalidOfficialURL) {
    _ = try CCPSDEArchiveDownloader.officialURL(buildNumber: 0)
  }
}

@Test
func createsRedactedUserAgentAndDiagnostics() throws {
  let configuration = try SDEUserAgentConfiguration(
    applicationName: "Example",
    applicationVersion: "1.2.3",
    contact: "owner@example.test"
  )
  #expect(
    configuration.headerValue
      == "Example/1.2.3 (SDE integration; contact: owner@example.test)"
  )

  let event = DiagnosticEvent(
    level: .info,
    category: .staticData,
    name: "test",
    code: "EVE-SDE-TEST",
    operation: .sdeMetadataCheck,
    correlationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    metadata: [
      "build": .publicValue("123"),
      "contact": .privateValue("owner@example.test"),
    ]
  )
  #expect(event.redactedDescription.contains("build=123"))
  #expect(event.redactedDescription.contains("contact=<redacted>"))
  #expect(!event.redactedDescription.contains("owner@example.test"))
}

@Test
func previewsSevenDatasetJSONLPackage() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    try? FileManager.default.removeItem(at: root)
  }

  for (index, dataset) in SDEDatasetKind.allCases.enumerated() {
    let line = #"{"_key":\#(index + 1)}"# + "\n"
    try Data(line.utf8).write(to: root.appendingPathComponent(dataset.fileName))
  }

  let service = JSONLinesSDEImportService()
  let preview = try await service.preview(
    sourceDirectoryURL: root,
    buildNumber: 123
  )

  #expect(preview.snapshot.buildNumber == 123)
  #expect(preview.snapshot.datasets.count == SDEDatasetKind.allCases.count)
  #expect(preview.snapshot.contentSHA256.count == 64)
}

private struct MetadataTransportStub: SDEHTTPTransport {
  let response: SDEHTTPResponse

  func execute(_ request: SDEHTTPRequest) async throws -> SDEHTTPResponse {
    response
  }
}

@Test
func parsesOfficialLatestBuildShape() async throws {
  let body = Data(
    #"{"_key":"sde","buildNumber":3444265,"releaseDate":"2026-07-23T11:06:22Z"}"#
      .utf8
  )
  let response = SDEHTTPResponse(
    statusCode: 200,
    headers: [
      "content-type": "application/jsonlines+json",
      "etag": #""fixture""#,
    ],
    body: body,
    finalURL: URL(string: CCPSDEMetadataClient.latestBuildURLString)
  )
  let configuration = try CCPSDEMetadataClientConfiguration(
    userAgent: SDEUserAgentConfiguration(
      applicationName: "Tests",
      applicationVersion: "1"
    )
  )
  let client = CCPSDEMetadataClient(
    transport: MetadataTransportStub(response: response),
    configuration: configuration
  )

  let result = try await client.latestRelease(cache: nil)
  guard case .modified(let release, _) = result else {
    Issue.record("Expected a modified response")
    return
  }
  #expect(release.buildNumber == 3_444_265)
}

@Test
func treatsOmittedTypeDogmaEffectsAsAnEmptyEffectList() async throws {
  let effects = try await JSONLinesSDECatalogMapper().mapDogmaEffectIDs(
    nil,
    dataset: .typeDogma,
    line: 1
  )

  #expect(effects.isEmpty)
}

@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment[
      "EVE_STATIC_DATA_KIT_REAL_PACKAGE"
    ] != nil,
    "Set EVE_STATIC_DATA_KIT_REAL_PACKAGE to a prepared public SDE package."
  )
)
func mapsOptInCurrentRealSDEPackage() async throws {
  guard
    let packagePath = ProcessInfo.processInfo.environment[
      "EVE_STATIC_DATA_KIT_REAL_PACKAGE"
    ]
  else {
    Issue.record("The opt-in real SDE package path is missing.")
    return
  }

  let collected = TypeDogmaBatchCollector()
  let result = try await JSONLinesSDECatalogMapper().streamStagingPackage(
    at: URL(fileURLWithPath: packagePath, isDirectory: true),
    batchSize: 500
  ) { batch in
    if case .typeDogma(let records) = batch {
      await collected.append(records)
    }
  }

  #expect(result.metadata.buildNumber > 0)
  #expect(result.counts.itemTypes > 0)
  #expect(result.counts.blueprints > 0)
  // Raitaru: structure size and rig slots for the Industry facility catalog.
  let raitaru = await collected.records.first { $0.itemTypeID == 35_825 }
  #expect(raitaru?.attributeValues[1_547] != nil)
  #expect(raitaru?.attributeValues[1_137] != nil)
}

private actor TypeDogmaBatchCollector {
  private(set) var records: [StaticTypeDogmaSnapshot] = []

  func append(_ batch: [StaticTypeDogmaSnapshot]) {
    records.append(contentsOf: batch)
  }
}

@Test
func facilityTypeDogmaKeepsOnlyRecordedTypesInTypeOrder() {
  let records = JSONLinesSDECatalogMapper.facilityTypeDogma(
    typeIDs: [35_891, 35_825, 99],
    values: [
      35_825: [1_547: 2, 1_137: 3],
      35_891: [:],
      12: [1: 1],
    ]
  )

  #expect(records.map(\.itemTypeID) == [35_825, 35_891])
  #expect(records[0].attributeValues == [1_547: 2, 1_137: 3])
  // An empty attribute list is a recorded type, not a missing one.
  #expect(records[1].attributeValues.isEmpty)
  #expect(JSONLinesSDECatalogMapper.facilityDogmaCategoryIDs == [65, 66])
}

@Test
func mapsMarketGroupsWithOptionalParent() async throws {
  let mapper = JSONLinesSDECatalogMapper()
  let child = try await mapper.mapMarketGroup(
    [
      "_key": NSNumber(value: 1_038),
      "parentGroupID": NSNumber(value: 1_031),
      "name": ["en": "Harvest Equipment", "de": "Abbauausrüstung"],
      "hasTypes": NSNumber(value: false),
    ],
    line: 1
  )
  let root = try await mapper.mapMarketGroup(
    [
      "_key": NSNumber(value: 9),
      "name": ["en": "Ship Equipment"],
      "hasTypes": NSNumber(value: true),
    ],
    line: 2
  )

  #expect(
    child
      == StaticMarketGroupSnapshot(
        externalID: 1_038,
        parentExternalID: 1_031,
        name: "Harvest Equipment",
        hasTypes: false
      )
  )
  #expect(root.parentExternalID == nil)
  #expect(root.hasTypes)
}

@Test
func rejectsMarketGroupsWithoutEnglishNameOrTypeFlag() async throws {
  let mapper = JSONLinesSDECatalogMapper()
  await #expect(
    throws: StaticDataMappingError.invalidField(
      dataset: .marketGroups,
      line: 3,
      field: "name.en"
    )
  ) {
    _ = try await mapper.mapMarketGroup(
      [
        "_key": NSNumber(value: 4),
        "name": ["de": "Nur Deutsch"],
        "hasTypes": NSNumber(value: true),
      ],
      line: 3
    )
  }
  await #expect(
    throws: StaticDataMappingError.invalidField(
      dataset: .marketGroups,
      line: 4,
      field: "hasTypes"
    )
  ) {
    _ = try await mapper.mapMarketGroup(
      ["_key": NSNumber(value: 5), "name": ["en": "No Flag"]],
      line: 4
    )
  }
}

@Test
func marketGroupsAreAnImportedDataset() {
  #expect(SDEDatasetKind.allCases.contains(.marketGroups))
  #expect(SDEDatasetKind.marketGroups.fileName == "marketGroups.jsonl")
}
