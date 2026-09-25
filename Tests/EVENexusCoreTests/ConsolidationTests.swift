import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Functional consolidation contracts")
struct ConsolidationTests {
  private func workspace() throws -> ConsolidationWorkspace {
    var w = ConsolidationWorkspace()
    try w.createProject(name: "Alpha")
    return w
  }
  @Test func duplicationNeverCopiesReservationsOrSnapshots() throws {
    var w = try workspace()
    let original = try #require(w.selectedProjectID)
    w.projects[0].planSnapshot = Data([1])
    w.projects[0].logisticsOverrideCents = 100
    try w.reserve(projectID: original, quantities: [34: 20], esi: [34: 30], expires: nil)
    try w.createProject(name: "Beta", duplicate: original)
    #expect(w.selectedProjectID != original)
    #expect(w.selectedProject?.planSnapshot == nil)
    #expect(w.selectedProject?.logisticsOverrideCents == nil)
    #expect(w.reservations.allSatisfy { $0.projectID == original })
  }
  @Test func archiveRequiresReleasedReservationsAndNamesRemainUnique() throws {
    var w = try workspace()
    let id = try #require(w.selectedProjectID)
    try w.reserve(projectID: id, quantities: [34: 5], esi: [34: 10], expires: nil)
    var project = w.projects[0]
    project.status = .archived
    #expect(throws: (any Error).self) { try w.updateProject(project) }
    try w.changeReservation(id: w.reservations[0].id, quantity: 5, consume: false)
    try w.updateProject(project)
    #expect(throws: (any Error).self) { try w.createProject(name: " alpha ") }
  }
  @Test func sharedReservationsSubtractExactlyOnceAndDoNotMutateInventory() throws {
    var w = try workspace()
    let a = try #require(w.selectedProjectID)
    try w.createWarehouse(name: "Stock")
    let warehouse = w.warehouses[0].id
    w.warehouses[0].stock = [34: 10]
    w.projects[0].warehouseIDs = [warehouse]
    try w.reserve(projectID: a, quantities: [34: 15], esi: [34: 10], expires: nil)
    #expect(try w.availableStock(projectID: a, esi: [34: 10])[34] == 20)
    try w.createProject(name: "Beta")
    let b = try #require(w.selectedProjectID)
    w.projects[1].warehouseIDs = [warehouse]
    #expect(try w.availableStock(projectID: b, esi: [34: 10])[34] == 5)
    #expect(w.warehouses[0].stock[34] == 10)
    #expect(throws: (any Error).self) {
      try w.reserve(projectID: b, quantities: [34: 6], esi: [34: 10], expires: nil)
    }
    #expect(w.reservations.allSatisfy { $0.projectID == a })
  }
  @Test func limitsAreAppliedOnceAcrossSourcesAndExclusionsWin() throws {
    var w = try workspace()
    let id = try #require(w.selectedProjectID)
    try w.createWarehouse(name: "Stock")
    w.warehouses[0].stock = [34: 50, 35: 20]
    w.projects[0].warehouseIDs = [w.warehouses[0].id]
    w.projects[0].quantityCaps = [34: 7]
    w.projects[0].excludedTypes = [35]
    let quantities = try w.availableStock(projectID: id, esi: [34: 100, 35: 100])
    #expect(quantities[34] == 7)
    #expect(quantities[35] == 0)
  }
  @Test func partialConsumptionAndReleaseRetainAuditAndExpiredReservations() throws {
    var w = try workspace()
    let id = try #require(w.selectedProjectID)
    try w.reserve(projectID: id, quantities: [34: 10], esi: [34: 10], expires: .distantPast)
    let reservationID = w.reservations[0].id
    try w.changeReservation(id: reservationID, quantity: 3, consume: true)
    #expect(w.reservations[0].status == "partiallyConsumed")
    #expect(w.reservations[0].remaining == 7)
    try w.changeReservation(id: reservationID, quantity: 7, consume: false)
    #expect(w.reservations[0].remaining == 0)
    #expect(w.reservations[0].consumed == 3)
    #expect(throws: (any Error).self) {
      try w.changeReservation(id: reservationID, quantity: 1, consume: true)
    }
  }
  @Test func conflictProposalHonorsPriorityAndDoesNotApplyItself() throws {
    var w = try workspace()
    let a = try #require(w.selectedProjectID)
    w.projects[0].priority = 3
    try w.reserve(projectID: a, quantities: [34: 6], esi: [34: 10], expires: nil)
    try w.createProject(name: "Beta")
    let b = try #require(w.selectedProjectID)
    w.projects[1].priority = 1
    try w.reserve(projectID: b, quantities: [34: 4], esi: [34: 10], expires: nil)
    let preview = try ConsolidationPreview(base: w, summary: []) {
      _ = try $0.resolveStockConflicts(esi: [34: 5])
    }
    #expect(w.reservations[0].remaining == 6)
    let applied = try preview.applying(to: w)
    #expect(applied.reservations.filter { $0.projectID == b }.reduce(0) { $0 + $1.remaining } == 4)
    #expect(applied.reservations.filter { $0.projectID == a }.reduce(0) { $0 + $1.remaining } == 1)
  }
  @Test func previewShowsFrozenAmountsSourcesAndBudgetOverrides() throws {
    var w = try workspace()
    try w.createWarehouse(name: "Manual A")
    w.warehouses[0].stock = [34: 9]
    let preview = try ConsolidationPreview(base: w, summary: []) { candidate in
      candidate.projects[0].warehouseIDs = [candidate.warehouses[0].id]
      candidate.projects[0].logisticsOverrideCents = 12050
      candidate.projects[0].quantityCaps = [34: 8]
      try candidate.reserve(
        projectID: candidate.projects[0].id, quantities: [34: 7], esi: [:], expires: nil)
    }
    let text = preview.summary.joined(separator: "\n")
    #expect(text.contains("120.50 ISK"))
    #expect(text.contains("Typ 34: 8"))
    #expect(text.contains("Manual A: reserviert 0 → 7"))
    w.projects[0].logisticsOverrideCents = 999
    #expect(preview.summary.joined().contains("120.50 ISK"))
    #expect(preview.proposed.projects[0].logisticsOverrideCents == 12050)
  }
  @Test func staleAndReplayedPreviewsAreRejected() throws {
    let w = try workspace()
    let preview = try ConsolidationPreview(base: w, summary: []) {
      try $0.createWarehouse(name: "A")
    }
    let applied = try preview.applying(to: w)
    #expect(throws: ConsolidationError.stalePreview) { try preview.applying(to: applied) }
  }
  @Test func csvIsAtomicAndDuplicateTypesDoNotSum() throws {
    var w = try workspace()
    try w.createWarehouse(name: "A")
    let id = w.warehouses[0].id
    let csv = InventoryCSVImportSource(
      displayName: "file.csv", data: Data("type_id,quantity\n34,8\n34,9".utf8),
      sha256: String(repeating: "a", count: 64))
    #expect(throws: (any Error).self) {
      try ConsolidationImports.preview(
        base: w, source: csv, kind: .warehouse(id), conflict: .replace,
        catalogNames: [34: "Tritanium"])
    }
    #expect(w.warehouses[0].stock.isEmpty)
    #expect(w.imports.isEmpty)
  }
  @Test func csvReplaceSkipAndImportReportCommitTogether() throws {
    var w = try workspace()
    try w.createWarehouse(name: "A")
    let id = w.warehouses[0].id
    w.warehouses[0].stock[34] = 10
    let source = InventoryCSVImportSource(
      displayName: "/private/secret/stock.csv", data: Data("type_id;quantity\n34;8\n35;9".utf8),
      sha256: String(repeating: "b", count: 64))
    let preview = try ConsolidationImports.preview(
      base: w, source: source, kind: .warehouse(id), conflict: .skip,
      catalogNames: [34: "Tritanium", 35: "Pyerite"])
    let accepted = try preview.applying(to: w)
    #expect(accepted.warehouses[0].stock == [34: 10, 35: 9])
    #expect(accepted.imports[0].filename == "stock.csv")
    #expect(accepted.imports[0].outcomes.count == 2)
    let replaced = try ConsolidationImports.preview(
      base: accepted, source: source, kind: .warehouse(id), conflict: .replace,
      catalogNames: [34: "Tritanium", 35: "Pyerite"]
    ).applying(to: accepted)
    #expect(replaced.warehouses[0].stock[34] == 8)
  }
  @Test(arguments: ["0", "-1", "9223372036854775808", "1.5", "1,000"])
  func invalidInventoryValuesAreRejected(_ amount: String) throws {
    var w = try workspace()
    try w.createWarehouse(name: "A")
    let source = InventoryCSVImportSource(
      displayName: "bad.csv", data: Data("type_id;quantity\n34;\(amount)".utf8), sha256: "a")
    #expect(throws: (any Error).self) {
      try ConsolidationImports.preview(
        base: w, source: source, kind: .warehouse(w.warehouses[0].id), conflict: .replace,
        catalogNames: [34: "Tritanium"])
    }
  }
  @Test func moneyIsExactAndValidityEndIsExclusive() throws {
    #expect(try ISKAmount.parse("123,45").hundredths == 12345)
    for invalid in ["", "0", "-1", "1.234", "1,234.50", "1 000", "92233720368547759"] {
      #expect(throws: (any Error).self) { try ISKAmount.parse(invalid) }
    }
    var p = ManualPriceProfile(name: "P", validFrom: Date(timeIntervalSince1970: 100))
    p.validUntil = Date(timeIntervalSince1970: 200)
    p.prices[34] = try ISKAmount.parse("0.01")
    #expect(p.price(34, at: Date(timeIntervalSince1970: 100)) != nil)
    #expect(p.price(34, at: Date(timeIntervalSince1970: 200)) == nil)
  }
  @Test func purchasesNeverCreateStockAndExportsAggregateRemainingPerProject() throws {
    var w = try workspace()
    let a = try #require(w.selectedProjectID)
    w.purchases = [ProjectPurchase(projectID: a, typeID: 34, name: "Tritanium", planned: 10)]
    try w.updatePurchase(projectID: a, typeID: 34, override: 7, purchased: 9)
    try w.createProject(name: "Beta")
    let b = try #require(w.selectedProjectID)
    w.purchases.append(ProjectPurchase(projectID: b, typeID: 34, name: "Tritanium", planned: 3))
    #expect(try w.purchasingCSV().contains("34,\"Tritanium\",10,9,3,2"))
    #expect(w.warehouses.isEmpty)
  }
  @Test func budgetMissingPricesStayMissingAndOverridesReplace() throws {
    var w = try workspace()
    let id = try #require(w.selectedProjectID)
    w.purchases = [ProjectPurchase(projectID: id, typeID: 34, name: "Tritanium", planned: 3)]
    try w.createPriceProfile(name: "P", from: .distantPast, until: nil)
    w.projects[0].priceProfileID = w.priceProfiles[0].id
    #expect(try w.budget(projectID: id, logistics: 10, production: 20).total == nil)
    w.priceProfiles[0].prices[34] = try ISKAmount.parse("0.10")
    w.projects[0].logisticsOverrideCents = 100
    #expect(try w.budget(projectID: id, logistics: 10, production: 20).total == 21.3)
  }
  @Test func receiptAllocationPreventsDoubleUseAndOversaleAndKeepsCosts() throws {
    var w = try workspace()
    let row = UUID()
    w.costs = [
      ImmutableProductionCost(
        id: row, typeID: 34, units: 10, sourceSnapshot: Data([1, 2]), material: 7.123,
        installation: nil, blueprint: 0, logistics: 5, historicalManualSoldUnits: 10,
        historicalManualSalePrice: 2, recordedAt: .now)
    ]
    let receipt = ProductionSaleEvidence(
      id: "1:transaction:1", typeID: 34, quantity: 8, unitPrice: try ISKAmount.parse("1.23"),
      recordedAt: .now, source: "Wallet")
    try w.addEvidence(receipt)
    try w.addEvidence(receipt)
    #expect(w.evidence.count == 1)
    #expect(throws: (any Error).self) {
      try w.allocateSale(rowID: row, evidenceID: receipt.id, quantity: 4, switchToEvidence: false)
    }
    try w.allocateSale(rowID: row, evidenceID: receipt.id, quantity: 4, switchToEvidence: true)
    #expect(w.sales[0].grossCents == 492)
    #expect(w.costs[0].historicalManualSoldUnits == 10)
    #expect(w.costs[0].material == 7.123)
    #expect(w.costs[0].installation == nil)
    #expect(throws: (any Error).self) {
      try w.allocateSale(rowID: row, evidenceID: receipt.id, quantity: 5, switchToEvidence: true)
    }
    let roundTrip = try JSONDecoder().decode(
      ConsolidationWorkspace.self, from: JSONEncoder().encode(w))
    #expect(roundTrip.sales[0].grossCents == 492)
    #expect(roundTrip.costs[0].sourceSnapshot == Data([1, 2]))
  }
  @Test func overflowFailsInsteadOfSaturatingFinancialEvidence() throws {
    #expect(throws: ConsolidationError.overflow) {
      try ConsolidationWorkspace.multiply(Int64.max, 2)
    }
    #expect(throws: ConsolidationError.overflow) { try ConsolidationWorkspace.add(Int64.max, 1) }
  }

  @Test func copyingSupplyUsesConcreteRunsAndKeepsExistingMath() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let activity = BlueprintScienceActivityDefinition(
      kind: .copying, durationSeconds: 10, materials: [], products: [], requiredSkills: [],
      source: source)
    let copy = try BlueprintSciencePlanner.copyPlan(
      sourceBPO: .ownedBPO(itemID: 99), blueprintTypeID: 100,
      activity: activity, copyCount: 2, runsPerCopy: 5, maximumRunsPerCopy: 10,
      materialEfficiency: 10, timeEfficiency: 20, installationCost: 10)
    let recipe = BlueprintDefinition(
      blueprintTypeID: 100, productTypeID: 101, maxProductionLimit: 10,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing, durationSeconds: 10, materials: [],
        products: [BlueprintProduct(typeID: 101, quantity: 2, probability: nil)]), source: source)
    let supply = try ConsolidationScience.supply(
      job: .copying(copy), definition: recipe, requiredRuns: 7, name: "Product", ownerID: 1,
      ownerName: "Character", locationID: 2, materialCost: 4, sourceIDs: [source.snapshotID])
    #expect(copy.durationSeconds == 100)
    #expect(supply.batchAllocationCost == 14)
    #expect(supply.manufacturingJobs[0].outputQuantity == 14)
    #expect(supply.manufacturingJobs[0].allocation.remainingRuns == 3)
    #expect(supply.manufacturingJobs[0].allocation.materialEfficiency == 10)
    #expect(throws: (any Error).self) {
      try ConsolidationScience.supply(
        job: .copying(copy), definition: recipe,
        requiredRuns: 11, name: "Product", ownerID: 1, ownerName: "Character", locationID: 2,
        materialCost: 4, sourceIDs: [])
    }
  }
  @Test func journalTotalsDistributeRemainderWithoutInventingUnitPrices() throws {
    var w = try workspace()
    let row = UUID()
    w.costs = [
      ImmutableProductionCost(
        id: row, typeID: 34, units: 3, sourceSnapshot: Data(), material: 0,
        installation: 0, blueprint: 0, logistics: 0, historicalManualSoldUnits: 0,
        historicalManualSalePrice: nil, recordedAt: .now)
    ]
    try w.addEvidence(
      ProductionSaleEvidence(
        id: "1:journal:2", typeID: 34, quantity: 3, unitPrice: nil,
        recordedAt: .now, source: "Confirmed journal", totalCents: 100))
    for _ in 0..<3 {
      try w.allocateSale(rowID: row, evidenceID: "1:journal:2", quantity: 1, switchToEvidence: true)
    }
    #expect(w.sales.map(\.grossCents) == [33, 33, 34])
    try w.validate()
    #expect(w.evidence[0].unitPrice == nil)
    #expect(throws: (any Error).self) {
      try w.allocateSale(rowID: row, evidenceID: "1:journal:2", quantity: 1, switchToEvidence: true)
    }
  }
  @Test func invalidRowsRequireExplicitSkippingAndBothDuplicatesAreExcluded() throws {
    var w = try workspace()
    try w.createWarehouse(name: "A")
    let source = InventoryCSVImportSource(
      displayName: "stock.csv", data: Data("type_id;quantity\n34;3\n34;4\n35;9\n36;-1".utf8),
      sha256: "fixture")
    let preview = try ConsolidationImports.preview(
      base: w, source: source, kind: .warehouse(w.warehouses[0].id),
      conflict: .replace, skipInvalidRows: true,
      catalogNames: [34: "Tritanium", 35: "Pyerite", 36: "Mexallon"])
    let accepted = try preview.applying(to: w)
    #expect(accepted.warehouses[0].stock == [35: 9])
    #expect(accepted.imports[0].outcomes.count == 4)
  }
  @Test func researchSuppliesFutureEfficiencyAndRetainsOriginalIdentity() throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let recipe = BlueprintDefinition(
      blueprintTypeID: 100, productTypeID: 101, maxProductionLimit: 10,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing, durationSeconds: 10, materials: [],
        products: [BlueprintProduct(typeID: 101, quantity: 1, probability: nil)]), source: source)
    let research = BlueprintResearchPlan(
      sourceBPO: .ownedBPO(itemID: 99), blueprintTypeID: 100,
      activity: .timeEfficiency, currentLevel: 2, targetLevel: 5, materials: [],
      durationSeconds: 500, installationCost: 10)
    let supply = try ConsolidationScience.supply(
      job: .research(research), definition: recipe, requiredRuns: 4,
      name: "Product", ownerID: 1, ownerName: "Owner", locationID: 2, materialCost: 0,
      sourceIDs: [], originalME: 3, originalTE: 4)
    #expect(supply.manufacturingJobs[0].allocation.source == .ownedBPO(itemID: 99))
    #expect(supply.manufacturingJobs[0].allocation.materialEfficiency == 3)
    #expect(supply.manufacturingJobs[0].allocation.timeEfficiency == 10)
    #expect(supply.batchAllocationCost == 10)
  }
  @Test func plannerAddsConcreteScienceTimeWithoutChangingManufacturingMath() async throws {
    let source = SourceIdentity(provider: "fixture", version: "1")
    let recipe = BlueprintDefinition(
      blueprintTypeID: 100, productTypeID: 101, maxProductionLimit: 10,
      activity: BlueprintActivityDefinition(
        kind: .manufacturing, durationSeconds: 100, materials: [],
        products: [BlueprintProduct(typeID: 101, quantity: 1, probability: nil)]), source: source)
    let copy = BlueprintCopyPlan(
      sourceBPO: .ownedBPO(itemID: 99), blueprintTypeID: 100, copyCount: 1,
      runsPerCopy: 2, maximumRunsPerCopy: 10, materialEfficiency: 0, timeEfficiency: 0,
      materials: [], durationSeconds: 40, installationCost: 10)
    let supplied = try ConsolidationScience.supply(
      job: .copying(copy), definition: recipe, requiredRuns: 2,
      name: "Product", ownerID: 1, ownerName: "Owner", locationID: 2, materialCost: 0, sourceIDs: []
    )
    let before = BlueprintSupplyPlan(
      blueprintTypeID: 100, productTypeID: 101, productName: "Product", requiredRuns: 2,
      manufacturingJobs: supplied.manufacturingJobs, batchAllocationCost: 10)
    let market = MarketOrderSnapshot(
      id: UUID(), regionID: 1, locationID: 2, capturedAt: .now, state: .fresh, ordersByType: [:],
      source: source)
    func context(_ supply: BlueprintSupplyPlan) -> IndustryPlanningContext {
      IndustryPlanningContext(
        manufacturingProfile: ManufacturingProfile(),
        catalog: ConsolidationFixtureCatalog(definition: recipe),
        market: market, adjustedPrices: [:], systemIndices: [], availableStock: [:], sdeBuild: 1,
        blueprintSupplyPlans: [100: supply])
    }
    let baseline = try await IndustryPlanner().plan(
      input: "Product 2 0 0", context: context(before))
    let after = try await IndustryPlanner().plan(input: "Product 2 0 0", context: context(supplied))
    #expect(after.totalJobSeconds == baseline.totalJobSeconds + 40)
    #expect(after.makespanSeconds == baseline.makespanSeconds + 40)
    #expect(after.materialCost == baseline.materialCost)
    #expect(after.installationCost == baseline.installationCost)
    #expect(after.jobs.map(\.durationSeconds) == baseline.jobs.map(\.durationSeconds))
  }
}

@Suite("Verified local backups")
struct ConsolidationBackupTests {
  @Test func walSnapshotTamperingForeignFamilyAndRestore() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "eve-backup-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppDataPaths.resolve(applicationSupportRoot: root, fileExists: { _ in false })
    try paths.prepareDirectories()
    var db: OpaquePointer?
    #expect(sqlite3_open(paths.swiftDataStoreURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(
      sqlite3_exec(
        db,
        "PRAGMA journal_mode=WAL; CREATE TABLE fixture (n INTEGER); INSERT INTO fixture VALUES (42);",
        nil, nil, nil) == SQLITE_OK)
    let prefs = try PropertyListSerialization.data(
      fromPropertyList: ["planner.test": true], format: .binary, options: 0)
    let target = root.appendingPathComponent("test.nexusbackup")
    try ConsolidationBackup.create(
      dataRoot: paths.dataRoot, destination: target, defaults: prefs, schema: 2)
    #expect(try ConsolidationBackup.verify(target).schema == 2)
    var backupDB: OpaquePointer?
    let file = target.appendingPathComponent("data/ApplicationData/EVENexusSimple.store")
    #expect(sqlite3_open(file.path, &backupDB) == SQLITE_OK)
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(backupDB, "SELECT n FROM fixture", -1, &statement, nil) == SQLITE_OK)
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 42)
    sqlite3_finalize(statement)
    sqlite3_close(backupDB)
    try ConsolidationBackup.scheduleRestore(target, paths: paths)
    sqlite3_close(db)
    db = nil
    let restored = try ConsolidationBackup.applyPendingRestore(
      paths: paths, defaults: prefs, schema: 3)
    #expect(restored == prefs)
    #expect(
      try ConsolidationBackup.applyPendingRestore(paths: paths, defaults: prefs, schema: 3) == nil)
    let manifestURL = target.appendingPathComponent("manifest.json")
    let originalManifest = try Data(contentsOf: manifestURL)
    var json = try #require(JSONSerialization.jsonObject(with: originalManifest) as? [String: Any])
    json["dataFamily"] = "NewEdenNexus"
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
    #expect(throws: (any Error).self) { try ConsolidationBackup.verify(target) }
    try originalManifest.write(to: manifestURL)
    try Data("corrupt".utf8).write(to: file)
    #expect(throws: (any Error).self) { try ConsolidationBackup.verify(target) }
  }
}

private struct ConsolidationFixtureCatalog: IndustryCatalogQuerying {
  let definition: BlueprintDefinition
  func typeID(named name: String) async throws -> Int64? {
    name == "Product" ? definition.productTypeID : nil
  }
  func typeName(id: Int64) async throws -> String? {
    id == definition.productTypeID ? "Product" : nil
  }
  func productionDefinition(productTypeID: Int64) async throws -> BlueprintDefinition? {
    productTypeID == definition.productTypeID ? definition : nil
  }
}
