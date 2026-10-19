import CSQLite
import Foundation
import Testing

@testable import EVENexusCore

@Suite("Functional consolidation contracts")
struct ConsolidationTests {
  private func workspace() throws -> ConsolidationWorkspace { ConsolidationWorkspace() }
  @Test func legacyProjectDataDecodesValidatesAndRoundTripsUnchanged() throws {
    // Payload shape written before production projects were removed (2026-10-19), including a
    // reservation and purchase whose project no longer resolves.
    var legacy = ConsolidationWorkspace()
    var project = ConsolidatedProject(name: "Alpha")
    project.input = "Rifter 1 0 0"
    project.planSnapshot = Data([1, 2, 3])
    project.quantityCaps = [34: 7]
    legacy.projects = [project]
    legacy.selectedProjectID = UUID()
    legacy.reservations = [
      ProjectStockReservation(projectID: UUID(), typeID: 34, source: "esi", quantity: 5)
    ]
    legacy.purchases = [ProjectPurchase(projectID: UUID(), typeID: 34, name: "Tritanium", planned: 3)]
    let payload = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(ConsolidationWorkspace.self, from: payload)
    try decoded.validate()
    let again = try JSONDecoder().decode(
      ConsolidationWorkspace.self, from: JSONEncoder().encode(decoded))
    #expect(again.projects.first?.input == "Rifter 1 0 0")
    #expect(again.projects.first?.planSnapshot == Data([1, 2, 3]))
    #expect(again.projects.first?.quantityCaps == [34: 7])
    #expect(again.selectedProjectID == legacy.selectedProjectID)
    #expect(again.reservations.first?.remaining == 5)
    #expect(again.purchases.first?.planned == 3)
  }
  @Test func scienceRunReservationsAreGlobalAndSkipArchivedJobs() throws {
    let activity = BlueprintScienceActivityDefinition(
      kind: .invention, durationSeconds: 1_000, materials: [],
      products: [BlueprintProduct(typeID: 200, quantity: 10, probability: 0.4)],
      requiredSkills: [
        BlueprintSkillRequirement(typeID: 1, level: 1),
        BlueprintSkillRequirement(typeID: 2, level: 1),
        BlueprintSkillRequirement(typeID: 3, level: 1),
      ], source: SourceIdentity(provider: "fixture", version: "1"))
    let invention = try BlueprintSciencePlanner.inventionPlan(
      inputBPC: .ownedBPC(itemID: 88), inputBlueprintTypeID: 100,
      selectedOutputBlueprintTypeID: 200, activity: activity, characterID: 42,
      characterName: "Fixture Pilot", trainedSkillLevels: [1: 5, 2: 5, 3: 5],
      attemptCost: 1_000, requiredSuccesses: 1)
    func job(legacyProject: UUID?) -> SavedScienceJob {
      SavedScienceJob(
        projectID: legacyProject, blueprintTypeID: 100, name: "Fixture", job: .invention(invention),
        facilityName: "Lab", solarSystemID: 1, sourceIDs: [], supplyPlan: nil)
    }
    var w = ConsolidationWorkspace()
    let global = job(legacyProject: nil)
    let legacy = job(legacyProject: UUID())
    var archived = job(legacyProject: nil)
    archived.archived = true
    w.science = [global, legacy, archived]
    let reservations = w.scienceRunReservations()
    #expect(Set(reservations.map(\.planID)) == [global.id, legacy.id])
    #expect(reservations.allSatisfy { $0.blueprintItemID == 88 })
  }
  @Test func previewShowsFrozenWarehouseAmounts() throws {
    var w = try workspace()
    try w.createWarehouse(name: "Manual A")
    let preview = try ConsolidationPreview(base: w, summary: []) { candidate in
      candidate.warehouses[0].stock = [34: 9]
    }
    w.warehouses[0].stock = [34: 1]
    let text = preview.summary.joined(separator: "\n")
    #expect(text.contains("Lager Manual A, Typ 34: 0 → 9 Einheiten."))
    #expect(preview.proposed.warehouses[0].stock[34] == 9)
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
