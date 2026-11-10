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

/// One receipt and the units of it a production receives.
struct ProductionSaleAssignment {
  let evidence: ProductionSaleEvidence
  let rowID: UUID
  let quantity: Int64
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
    // Planner input and plans stay in StoredPlannerDraft/StoredPlan; no project is created.
    let initial = ConsolidationWorkspace()
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
      throw ConsolidationError.unavailable("Die Arbeitsdaten sind noch nicht geöffnet.")
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
    // A production whose last receipt assignment was taken back shows its
    // saved manual sale values again.
    for cost in proposed.costs
    where !cost.evidenceMode
      && workspace.costs.first(where: { $0.id == cost.id })?.evidenceMode == true
    {
      let id = cost.id
      guard
        let bookRow = try context.fetch(
          FetchDescriptor<StoredProductionOverviewRow>(predicate: #Predicate { $0.id == id })
        ).first
      else { continue }
      bookRow.soldUnits = cost.historicalManualSoldUnits
      bookRow.salePricePerUnit = cost.historicalManualSalePrice
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
  func registerProduction(_ row: StoredProductionOverviewRow, plan: IndustryPlanSnapshot) throws {
    guard !workspace.costs.contains(where: { $0.id == row.id }),
      let cost = Self.productionCost(for: row, plan: plan)
    else { return }
    try edit { $0.costs.append(cost) }
  }
  /// Frozen cost record of a production row; `nil` when the plan snapshot no
  /// longer names the product.
  static func productionCost(for row: StoredProductionOverviewRow, plan: IndustryPlanSnapshot)
    -> ImmutableProductionCost?
  {
    guard let node = plan.topLevelProductNode(for: row.requestID) else { return nil }
    let projection = ProductionOverviewProjector.projection(for: row.requestID, in: plan)
    return ImmutableProductionCost(
      id: row.id, typeID: node.typeID, units: row.units,
      sourceSnapshot: row.sourceSnapshot, material: row.materialCost,
      installation: row.indexCost,
      blueprint: row.blueprintCost, logistics: projection?.logisticsCost,
      historicalManualSoldUnits: row.soldUnits, historicalManualSalePrice: row.salePricePerUnit,
      recordedAt: row.recordedAt)
  }
  /// Assigns receipts to productions in one saved step: registers missing
  /// cost records, keeps the manual sale values of a production entering the
  /// receipt mode, stores each receipt and assigns its units.
  func assignSales(
    _ assignments: [ProductionSaleAssignment], rows: [StoredProductionOverviewRow]
  ) throws {
    guard !assignments.isEmpty else { return }
    var costs: [ImmutableProductionCost] = []
    var manual: [UUID: (sold: Int64, price: Double?)] = [:]
    for rowID in Set(assignments.map(\.rowID)) {
      guard let row = rows.first(where: { $0.id == rowID }) else {
        throw ConsolidationError.invalid("Die verknüpfte Produktion wurde entfernt.")
      }
      manual[rowID] = (row.soldUnits, row.salePricePerUnit)
      guard let plan = PlannerPersistenceController.decodePlan(row),
        let cost = Self.productionCost(for: row, plan: plan)
      else { throw ConsolidationError.invalid("Produkttyp nicht aufgelöst.") }
      costs.append(cost)
    }
    try edit { workspace in
      for cost in costs where !workspace.costs.contains(where: { $0.id == cost.id }) {
        workspace.costs.append(cost)
      }
      for assignment in assignments {
        guard let index = workspace.costs.firstIndex(where: { $0.id == assignment.rowID })
        else { throw ConsolidationError.invalid("Produkttyp nicht aufgelöst.") }
        if !workspace.costs[index].evidenceMode, let values = manual[assignment.rowID] {
          workspace.costs[index].historicalManualSoldUnits = values.sold
          workspace.costs[index].historicalManualSalePrice = values.price
        }
        try workspace.addEvidence(assignment.evidence)
        try workspace.allocateSale(
          rowID: assignment.rowID, evidenceID: assignment.evidence.id,
          quantity: assignment.quantity, switchToEvidence: true)
      }
    }
  }
  func removeSaleAllocation(_ id: UUID) throws {
    try edit { try $0.removeAllocation(id: id) }
  }
  func discardUnassignedReceipt(_ id: String) throws {
    try edit { try $0.removeUnassignedEvidence(id: id) }
  }
  func updateESIStock(_ stock: [Int64: Int64], known: Bool = true) {
    if stock != esiStock || known != esiAvailable {
      esiStock = stock
      esiAvailable = known
      stockRevision = UUID()
    }
  }
}
