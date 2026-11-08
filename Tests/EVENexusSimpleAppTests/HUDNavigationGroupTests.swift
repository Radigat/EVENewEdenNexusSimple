import SwiftUI
import XCTest

@testable import EVENexusSimpleApp

@MainActor
final class HUDNavigationGroupTests: XCTestCase {
  func testClassicKeepsTheEstablishedFlatOrder() {
    XCTAssertEqual(
      NavigationSection.establishedCases,
      [
        .dashboard, .planner, .manufacturingOpportunities,
        .homeHubOpportunities, .coalitionHubOpportunities, .trade,
        .tradeLogbook, .marketStock, .stockSaleComparison, .publicContracts,
        .reactions, .moonMaterialAnalysis, .mineralPurchaseAnalysis, .items,
        .warehouse, .blueprints, .productionBook, .netWorth, .data,
      ]
    )
  }

  func testHUDGroupsFollowThePlanOrder() {
    XCTAssertEqual(
      NavigationGroup.allCases,
      [.overview, .industry, .opportunities, .market, .assets, .system]
    )
    XCTAssertEqual(NavigationGroup.overview.sections, [.dashboard, .netWorth])
    XCTAssertEqual(
      NavigationGroup.industry.sections,
      [.planner, .reactions, .blueprints, .productionBook]
    )
    XCTAssertEqual(
      NavigationGroup.opportunities.sections,
      [
        .manufacturingOpportunities, .homeHubOpportunities,
        .coalitionHubOpportunities,
      ]
    )
    XCTAssertEqual(
      NavigationGroup.market.sections,
      [
        .trade, .tradeLogbook, .marketStock, .stockSaleComparison,
        .publicContracts, .moonMaterialAnalysis, .mineralPurchaseAnalysis,
      ]
    )
    XCTAssertEqual(NavigationGroup.assets.sections, [.items, .warehouse])
    XCTAssertEqual(NavigationGroup.system.sections, [.data])
  }

  func testEverySectionAppearsInExactlyOneGroup() {
    let grouped = NavigationGroup.allCases.flatMap(\.sections)
    XCTAssertEqual(grouped.count, NavigationSection.allCases.count)
    XCTAssertEqual(Set(grouped), Set(NavigationSection.allCases))
    for section in NavigationSection.allCases {
      XCTAssertTrue(section.group.sections.contains(section), "\(section)")
    }
  }

  func testGroupTitlesAreLocalizedInBothLanguages() {
    let expected: [NavigationGroup: (en: String, de: String)] = [
      .overview: ("Overview", "Übersicht"),
      .industry: ("Industry", "Industrie"),
      .opportunities: ("Opportunities", "Chancen"),
      .market: ("Market", "Markt"),
      .assets: ("Assets", "Assets"),
      .system: ("System", "System"),
    ]
    for group in NavigationGroup.allCases {
      let titles = try? XCTUnwrap(expected[group])
      XCTAssertEqual(AppLanguage.english.localized(group.titleKey), titles?.en)
      XCTAssertEqual(AppLanguage.german.localized(group.titleKey), titles?.de)
    }
  }

  func testNavigationGroupEnvironmentIsEmptyOutsideTheMainNavigation() {
    var environment = EnvironmentValues()
    XCTAssertNil(environment.navigationGroup)
    environment.navigationGroup = .market
    XCTAssertEqual(environment.navigationGroup, .market)
  }
}
