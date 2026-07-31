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
            "contact": .privateValue("owner@example.test")
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
            "etag": #""fixture""#
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
