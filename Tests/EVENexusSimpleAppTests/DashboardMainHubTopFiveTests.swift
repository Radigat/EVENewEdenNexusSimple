import Foundation
import Testing

@testable import EVENexusCore
@testable import EVENexusSimpleApp

/// Plan DB2 of `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
@MainActor
struct DashboardMainHubTopFiveTests {
  private func row(
    _ id: Int64,
    _ name: String = "Item",
    roi: Double?,
    profit: Double? = 1
  ) -> MainHubOpportunityTopRow {
    MainHubOpportunityTopRow(
      productTypeID: id,
      productName: name,
      returnOnInvestment: roi,
      profit: profit
    )
  }

  private func costs(profit: Double?) -> ManufacturingOpportunityCostProjection {
    ManufacturingOpportunityCostProjection(
      materialCost: 100,
      installationCost: 1,
      blueprintAllocation: nil,
      logisticsCost: 0,
      totalCost: 101,
      grossRevenue: nil,
      salesTax: nil,
      brokerFee: nil,
      netRevenue: nil,
      profit: profit,
      returnOnInvestment: profit.map { $0 / 101 },
      iskPerHour: nil,
      iskPerCubicMeter: nil
    )
  }

  // MARK: Selection and rank

  @Test
  func topFiveKeepsTheHighestReturnOnInvestmentFirst() {
    let rows = [
      row(1, roi: 0.10), row(2, roi: 0.50), row(3, roi: 0.30),
      row(4, roi: 0.20), row(5, roi: 0.45), row(6, roi: 0.05),
      row(7, roi: 0.40),
    ]
    let top = MainHubOpportunityTopSelection.top(rows)
    #expect(top.map(\.productTypeID) == [2, 5, 7, 3, 4])
  }

  @Test
  func rowsWithoutFiniteReturnOnInvestmentAreLeftOut() {
    let rows = [
      row(1, roi: nil), row(2, roi: .infinity), row(3, roi: .nan),
      row(4, roi: -0.2), row(5, roi: 0.1),
    ]
    let top = MainHubOpportunityTopSelection.top(rows)
    #expect(top.map(\.productTypeID) == [5, 4])
    #expect(MainHubOpportunityTopSelection.top([row(1, roi: nil)]).isEmpty)
  }

  @Test
  func equalReturnOnInvestmentUsesTheProductTypeID() {
    let rows = [row(30, roi: 0.2), row(10, roi: 0.2), row(20, roi: 0.2)]
    #expect(MainHubOpportunityTopSelection.top(rows).map(\.productTypeID) == [10, 20, 30])
    #expect(MainHubOpportunityTopSelection.top(rows, limit: 2).count == 2)
  }

  // MARK: Header sorting of the five rows

  @Test
  func headersSortByTypedValuesWithMissingValuesLastAscending() {
    let rows = [
      row(1, "Hornet II", roi: 0.3, profit: nil),
      row(2, "antimatter Charge L", roi: 0.4, profit: 26),
      row(3, "Damage Control II", roi: 0.3, profit: 157_339),
    ]
    func ids(_ column: MainHubOpportunityTopColumn, _ direction: AppTableSortDirection) -> [Int64] {
      MainHubOpportunityTopSelection.sorted(
        rows,
        by: AppTableSortDescriptor(column: column, direction: direction)
      ).map(\.productTypeID)
    }
    #expect(ids(.product, .ascending) == [2, 3, 1])
    #expect(ids(.product, .descending) == [1, 3, 2])
    // Equal ROI falls back to the product type ID.
    #expect(ids(.returnOnInvestment, .ascending) == [1, 3, 2])
    #expect(ids(.returnOnInvestment, .descending) == [2, 1, 3])
    #expect(ids(.profit, .ascending) == [2, 3, 1])
    #expect(ids(.profit, .descending) == [1, 3, 2])
  }

  // MARK: Filters shared with the visible table

  @Test
  func visibilityFilterAppliesValueBudgetAndDemand() {
    func accepts(
      profit: Double? = 10,
      cash: Double? = 50,
      demand: Int64? = 20,
      value: ManufacturingOpportunityValueFilter = .all,
      budget: Double? = nil,
      minimumDemand: Int64 = 0
    ) -> Bool {
      ManufacturingOpportunityVisibilityFilter.accepts(
        costs: costs(profit: profit),
        purchaseCashRequirement: cash,
        averageDailyDemand: demand,
        valueFilter: value,
        maximumMaterialPurchaseISK: budget,
        minimumAverageDailyDemand: minimumDemand
      )
    }
    #expect(accepts())
    #expect(!accepts(profit: -5, value: .positive))
    #expect(accepts(profit: -5, value: .negative))
    #expect(accepts(profit: nil, value: .unavailable))
    #expect(!accepts(profit: 10, value: .unavailable))
    #expect(accepts(budget: 50))
    #expect(!accepts(budget: 49))
    #expect(!accepts(cash: nil, budget: 100))
    #expect(accepts(minimumDemand: 20))
    #expect(!accepts(minimumDemand: 21))
    #expect(!accepts(demand: nil, minimumDemand: 1))
  }

  // MARK: Stored settings of the Main-Hub view

  @Test
  func storedSettingsUseTheViewDefaultsWhenNothingIsStored() throws {
    let suite = "claude.tests.top-five.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    let settings = ManufacturingOpportunityStoredSettings.mainHub(from: store)
    #expect(settings == ManufacturingOpportunityStoredSettings())
    #expect(settings.buildsIntermediates)
    #expect(settings.productFamilies == Set(ManufacturingOpportunityProductFamily.allCases))
    #expect(settings.valueFilter == .all)
    #expect(settings.maximumMaterialPurchaseISK == nil)
  }

  @Test
  func storedSettingsReadTheSameKeysAsTheView() throws {
    typealias Key = ManufacturingOpportunitySettingKey
    let suite = "claude.tests.top-five.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    let family = try #require(ManufacturingOpportunityProductFamily.allCases.first)
    store.set(-4, forKey: Key.minimumAverageDailyDemand)
    store.set("[7,3]", forKey: Key.favoriteTypeIDs)
    store.set("[\"\(family.rawValue)\",\"unknown\"]", forKey: Key.productFamilies)
    store.set("[]", forKey: Key.productionClasses)
    store.set(false, forKey: Key.buildsIntermediates)
    store.set(true, forKey: Key.favoritesOnly)
    store.set("positive", forKey: Key.valueFilter)
    store.set("Ship", forKey: Key.category)
    store.set("Frigate", forKey: Key.group)
    store.set("hob", forKey: Key.searchText)
    let settings = ManufacturingOpportunityStoredSettings.mainHub(from: store)
    #expect(settings.minimumAverageDailyDemand == 0)
    #expect(settings.favoriteIDs == [3, 7])
    #expect(settings.productFamilies == [family])
    #expect(settings.productionClasses.isEmpty)
    #expect(!settings.buildsIntermediates)
    #expect(settings.favoritesOnly)
    #expect(settings.valueFilter == .positive)
    #expect(settings.selectedCategory == "Ship")
    #expect(settings.selectedGroup == "Frigate")
    #expect(settings.searchText == "hob")

    store.set("not a filter", forKey: Key.valueFilter)
    #expect(ManufacturingOpportunityStoredSettings.mainHub(from: store).valueFilter == .all)
  }

  @Test
  func storedCategoryMissingFromTheScanFiltersNothing() {
    let available: Set<String> = ["Ship", "Module"]
    #expect(ManufacturingOpportunityStoredSettings.effectiveCatalogChoice("Ship", available: available) == "Ship")
    #expect(ManufacturingOpportunityStoredSettings.effectiveCatalogChoice("Drone", available: available).isEmpty)
    #expect(ManufacturingOpportunityStoredSettings.effectiveCatalogChoice("", available: available).isEmpty)
  }
}
