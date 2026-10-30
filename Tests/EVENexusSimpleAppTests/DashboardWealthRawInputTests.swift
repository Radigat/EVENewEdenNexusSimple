import EVENexusCore
import Foundation
import Testing

@testable import EVENexusSimpleApp

struct DashboardWealthRawInputTests {
  private func rawInput(
    wallet: Data? = nil,
    openOrders: String? = nil,
    industryJobs: String? = nil
  ) -> DashboardWealthRawInput {
    DashboardWealthRawInput(
      character: CharacterIdentity(id: 7, name: "Test Pilot"),
      lastSyncAt: Date(timeIntervalSince1970: 1_000),
      walletLastSyncAt: Date(timeIntervalSince1970: 2_000),
      wallet: wallet,
      assets: nil,
      corporationAssets: nil,
      blueprints: nil,
      openOrders: openOrders,
      privateContracts: nil,
      corporationWallet: nil,
      industryJobs: industryJobs
    )
  }

  @Test
  func missingSourcesStayExplicitlyUnavailable() {
    let input = rawInput().decoded

    #expect(input.wallet.state == .unavailable)
    #expect(input.wallet.value == nil)
    #expect(input.wallet.diagnostics == ["wallet.not-synchronized"])
    #expect(
      input.wallet.source.capturedAt == Date(timeIntervalSince1970: 2_000)
    )
    #expect(input.assets.state == .unavailable)
    #expect(input.assets.diagnostics == ["assets.not-synchronized"])
    #expect(input.assets.source.capturedAt == Date(timeIntervalSince1970: 1_000))
    #expect(input.openOrders?.diagnostics == ["orders.not-synchronized"])
    #expect(
      input.privateContracts?.diagnostics
        == ["private-contracts.not-synchronized"]
    )
    #expect(
      input.corporationAssets?.diagnostics
        == ["corporation-assets.not-synchronized"]
    )
    #expect(
      input.corporationWallet?.diagnostics
        == ["corporation-wallet.not-synchronized"]
    )
    #expect(input.industryJobs?.diagnostics == ["industry-jobs.not-synchronized"])
    #expect(input.blueprints?.diagnostics == ["blueprints.not-synchronized"])
  }

  @Test
  func storedSourcesDecodeAndCorruptValuesStayUnavailable() throws {
    let balance = Sourced(
      state: .fresh,
      value: 1_234.5,
      source: SourceIdentity(
        provider: "ESI",
        version: "test",
        capturedAt: Date(timeIntervalSince1970: 3_000)
      )
    )
    let input = rawInput(
      wallet: try JSONEncoder().encode(balance),
      openOrders: "not base64",
      industryJobs: Data("{}".utf8).base64EncodedString()
    ).decoded

    #expect(input.wallet.state == .fresh)
    #expect(input.wallet.value == 1_234.5)
    #expect(input.openOrders?.state == .unavailable)
    #expect(input.openOrders?.value == nil)
    #expect(input.industryJobs?.state == .unavailable)
    #expect(input.industryJobs?.diagnostics == ["industry-jobs.not-synchronized"])
  }
}
