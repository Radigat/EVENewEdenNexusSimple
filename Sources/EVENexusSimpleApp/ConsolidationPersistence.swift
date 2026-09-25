import Combine
import EVENexusCore
import Foundation
import SwiftData

@Model
final class StoredConsolidationWorkspace {
  @Attribute(.unique) var key: String
  var payload: Data
  var revision: Int64
  init(payload: Data, revision: Int64) {
    key = "workspace"
    self.payload = payload
    self.revision = revision
  }
}

enum EVENexusSchemaV3: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
  static var models: [any PersistentModel.Type] {
    EVENexusSchemaV2.models + [StoredConsolidationWorkspace.self]
  }
}

@MainActor
final class ConsolidationController: ObservableObject {
  @Published private(set) var workspace = ConsolidationWorkspace()
  @Published var error: String?
  @Published var preview: ConsolidationPreview?
  @Published var esiStock: [Int64: Int64] = [:]
  @Published var stockRevision = UUID()
  @Published private(set) var esiAvailable = false
  private var previewStockRevision: UUID?
  private var previewCatalogBuild: Int?
  private var context: ModelContext?

  func start(container: ModelContainer) throws {
    guard context == nil else { return }
    let context = ModelContext(container)
    context.autosaveEnabled = false
    self.context = context
    if let stored = try context.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).first {
      workspace = try JSONDecoder().decode(ConsolidationWorkspace.self, from: stored.payload)
      try workspace.validate()
      guard workspace.formatVersion == 1, workspace.revision == stored.revision else {
        throw ConsolidationError.invalid("Unbekanntes oder widersprüchliches Arbeitsdatenformat.")
      }
      return
    }
    let draft = try context.fetch(FetchDescriptor<StoredPlannerDraft>()).first {
      $0.key == "primary"
    }
    let active = try context.fetch(FetchDescriptor<StoredPlan>()).filter(\.isActive).max {
      $0.priceTimestamp < $1.priceTimestamp
    }
    let latest = try PlannerPersistenceController.fetchLatestProductionRecord(in: context)
    let restored = PlannerPersistenceController.restore(
      draft: draft, activePlans: active.map { [$0] } ?? [], latestProductionRecord: latest)
    var initial = ConsolidationWorkspace()
    try initial.createProject(
      name: active?.name.isEmpty == false ? active!.name : "Bestehende Produktionsplanung")
    initial.projects[0].input = restored.input
    initial.projects[0].manualStockInput = restored.manualStockInput
    initial.projects[0].planSnapshot = active?.snapshot ?? latest?.snapshot
    initial.projects[0].blueprintSupplyData = AppDefaults.store.data(
      forKey: "planner.blueprint-supply-draft.v2")
    if let plan = restored.plan {
      try initial.synchronizePurchases(projectID: initial.projects[0].id, plan: plan)
      for allocation in plan.stockAllocations
      where allocation.quantity > 0 && allocation.source.kind != .manual {
        initial.reservations.append(
          ProjectStockReservation(
            projectID: initial.projects[0].id,
            typeID: allocation.typeID, source: "esi", quantity: allocation.quantity))
      }
    }
    initial.projects[0].planSnapshot = active?.snapshot ?? latest?.snapshot
    let row = StoredConsolidationWorkspace(
      payload: try JSONEncoder().encode(initial), revision: initial.revision)
    context.insert(row)
    do {
      try context.save()
      workspace = initial
    } catch {
      context.rollback()
      self.context = nil
      throw error
    }
  }

  func refresh() throws {
    guard let context else {
      throw ConsolidationError.unavailable("Die Projektdaten sind noch nicht geöffnet.")
    }
    guard let row = try context.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).first else {
      throw ConsolidationError.stalePreview
    }
    workspace = try JSONDecoder().decode(ConsolidationWorkspace.self, from: row.payload)
    try workspace.validate()
  }

  func propose(
    _ summary: [String], catalogBuild: Int? = nil,
    change: (inout ConsolidationWorkspace) throws -> Void
  ) {
    do {
      try refresh()
      preview = try ConsolidationPreview(base: workspace, summary: summary, change: change)
      previewStockRevision = stockRevision
      previewCatalogBuild = catalogBuild
      error = nil
    } catch {
      preview = nil
      self.error = error.localizedDescription
    }
  }
  func setPreview(_ value: ConsolidationPreview, catalogBuild: Int?) {
    preview = value
    previewStockRevision = stockRevision
    previewCatalogBuild = catalogBuild
    error = nil
  }
  func confirm(catalogBuild: Int?) {
    do {
      guard let preview, previewStockRevision == stockRevision,
        previewCatalogBuild == nil || previewCatalogBuild == catalogBuild
      else { throw ConsolidationError.stalePreview }
      try commit(preview)
      self.preview = nil
      error = nil
    } catch {
      self.preview = nil
      self.error = error.localizedDescription
    }
  }
  func edit(_ change: (inout ConsolidationWorkspace) throws -> Void) throws {
    try refresh()
    try commit(ConsolidationPreview(base: workspace, summary: [], change: change))
  }
  private func commit(_ preview: ConsolidationPreview) throws {
    guard let context else { throw ConsolidationError.stalePreview }
    var committed = false
    defer { if !committed { context.rollback() } }
    try refresh()
    let proposed = try preview.applying(to: workspace)
    guard let row = try context.fetch(FetchDescriptor<StoredConsolidationWorkspace>()).first else {
      throw ConsolidationError.stalePreview
    }
    for cost in proposed.costs where cost.evidenceMode {
      let id = cost.id
      guard
        let bookRow = try context.fetch(
          FetchDescriptor<StoredProductionOverviewRow>(predicate: #Predicate { $0.id == id })
        ).first
      else {
        throw ConsolidationError.invalid("Die verknüpfte Produktion wurde entfernt.")
      }
      if workspace.costs.first(where: { $0.id == cost.id })?.evidenceMode != true {
        guard bookRow.soldUnits == cost.historicalManualSoldUnits,
          bookRow.salePricePerUnit == cost.historicalManualSalePrice
        else { throw ConsolidationError.stalePreview }
      }
      let allocations = proposed.sales.filter { $0.rowID == cost.id }
      let quantity = try allocations.reduce(Int64(0)) {
        try ConsolidationWorkspace.add($0, $1.quantity)
      }
      let gross = allocations.reduce(Decimal.zero) { $0 + Decimal($1.grossCents) }
      bookRow.soldUnits = quantity
      bookRow.salePricePerUnit =
        quantity > 0 ? NSDecimalNumber(decimal: gross / Decimal(quantity) / 100).doubleValue : nil
    }
    row.payload = try JSONEncoder().encode(proposed)
    row.revision = proposed.revision
    do {
      try context.save()
      workspace = proposed
      committed = true
    } catch {
      context.rollback()
      throw error
    }
  }
  func saveDraft(input: String, manualStockInput: String, supply: Data?) throws {
    guard let id = workspace.selectedProjectID else { return }
    guard let current = workspace.selectedProject,
      current.input != input || current.manualStockInput != manualStockInput
        || current.blueprintSupplyData != supply
    else { return }
    try edit { w in
      guard let i = w.projects.firstIndex(where: { $0.id == id }) else {
        throw ConsolidationError.stalePreview
      }
      w.projects[i].input = input
      w.projects[i].manualStockInput = manualStockInput
      w.projects[i].blueprintSupplyData = supply
      w.projects[i].updatedAt = .now
    }
  }
  func registerProduction(_ row: StoredProductionOverviewRow, plan: IndustryPlanSnapshot) throws {
    guard !workspace.costs.contains(where: { $0.id == row.id }),
      let node = plan.topLevelProductNode(for: row.requestID)
    else { return }
    let typeID = node.typeID
    let projection = ProductionOverviewProjector.projection(for: row.requestID, in: plan)
    try edit {
      $0.costs.append(
        ImmutableProductionCost(
          id: row.id, typeID: typeID, units: row.units,
          sourceSnapshot: row.sourceSnapshot, material: row.materialCost,
          installation: row.indexCost,
          blueprint: row.blueprintCost, logistics: projection?.logisticsCost,
          historicalManualSoldUnits: row.soldUnits, historicalManualSalePrice: row.salePricePerUnit,
          recordedAt: row.recordedAt))
    }
  }
  func updateESIStock(_ stock: [Int64: Int64], known: Bool = true) {
    if stock != esiStock || known != esiAvailable {
      esiStock = stock
      esiAvailable = known
      stockRevision = UUID()
    }
  }
}
