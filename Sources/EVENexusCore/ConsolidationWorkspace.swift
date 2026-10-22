import Foundation

/// Additive operational records. Existing IndustryPlanSnapshot math is deliberately not duplicated here.
public enum ConsolidationError: Error, LocalizedError, Equatable {
  case invalid(String)
  case stalePreview
  case unavailable(String)
  case overflow
  public var errorDescription: String? {
    switch self {
    case .invalid(let reason), .unavailable(let reason): reason
    case .stalePreview: "Die Ausgangsdaten wurden geändert. Bitte eine neue Vorschau erstellen."
    case .overflow: "Der Betrag oder die Menge überschreitet den unterstützten Zahlenbereich."
    }
  }
}

/// Legacy production-project records. Projects were removed from the planner on 2026-10-19;
/// these types only keep previously stored workspace payloads decodable and unchanged.
public enum ProductionProjectStatus: String, Codable, CaseIterable, Sendable {
  case planning, procurement, ready, inProduction, completed, archived
}

public struct ConsolidatedProject: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var status: ProductionProjectStatus = .planning
  public var previousStatus: ProductionProjectStatus = .planning
  public var input = ""
  public var manualStockInput = ""
  public var planSnapshot: Data?
  public var blueprintSupplyData: Data?
  public var warehouseIDs: Set<UUID> = []
  public var excludedTypes: Set<Int64> = []
  public var quantityCaps: [Int64: Int64] = [:]
  public var priceProfileID: UUID?
  public var logisticsOverrideCents: Int64?
  public var productionOverrideCents: Int64?
  public var priority = 2
  public var updatedAt = Date()
  public init(name: String) { self.name = name }
}

public struct ManualWarehouse: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var kind = "manual"
  public var notes = ""
  public var archived = false
  public var stock: [Int64: Int64] = [:]
  public var names: [Int64: String] = [:]
  public init(name: String) { self.name = name }
}

public struct ProjectStockReservation: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var projectID: UUID
  public var typeID: Int64
  /// "esi" or the UUID of an explicitly selected manual warehouse.
  public var source: String
  public var quantity: Int64
  public var consumed: Int64 = 0
  public var released: Int64 = 0
  public var expiresAt: Date?
  public init(
    projectID: UUID, typeID: Int64, source: String, quantity: Int64, expiresAt: Date? = nil
  ) {
    self.projectID = projectID
    self.typeID = typeID
    self.source = source
    self.quantity = quantity
    self.expiresAt = expiresAt
  }
  public var remaining: Int64 { max(0, quantity - consumed - released) }
  public var status: String {
    if remaining > 0 { return consumed > 0 ? "partiallyConsumed" : "reserved" }
    return consumed > 0 ? "consumed" : "released"
  }
}

public struct ManualPriceProfile: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var validFrom: Date
  public var validUntil: Date?
  public var prices: [Int64: ISKAmount] = [:]
  public var names: [Int64: String] = [:]
  public var source = "manual"
  public init(name: String, validFrom: Date = .now) {
    self.name = name
    self.validFrom = validFrom
  }
}

public struct ProjectPurchase: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var projectID: UUID
  public var typeID: Int64
  public var name: String
  public var planned: Int64
  public var override: Int64?
  public var purchased: Int64 = 0
  public var target: Int64 { override ?? planned }
  public var remaining: Int64 { max(0, target - purchased) }
}

public struct ProductionSaleEvidence: Codable, Identifiable, Sendable {
  /// Owner + source kind + CCP ID; manually entered evidence uses a fresh UUID.
  public var id: String
  public var typeID: Int64
  public var quantity: Int64
  public var unitPrice: ISKAmount?
  public var totalCents: Int64?
  public var recordedAt: Date
  public var source: String
  public init(
    id: String, typeID: Int64, quantity: Int64, unitPrice: ISKAmount?, recordedAt: Date,
    source: String, totalCents: Int64? = nil
  ) {
    self.id = id
    self.typeID = typeID
    self.quantity = quantity
    self.unitPrice = unitPrice
    self.totalCents = totalCents
    self.recordedAt = recordedAt
    self.source = source
  }
  public func amountCents() throws -> Int64 {
    if let totalCents, totalCents > 0 { return totalCents }
    guard let unitPrice else { throw ConsolidationError.invalid("Belegbetrag fehlt.") }
    return try ConsolidationWorkspace.multiply(quantity, unitPrice.hundredths)
  }
  public func cumulativeCents(for units: Int64) throws -> Int64 {
    guard quantity > 0, units >= 0, units <= quantity else {
      throw ConsolidationError.invalid("Ungültige Belegmenge.")
    }
    let total = try amountCents()
    let product = UInt64(total).multipliedFullWidth(by: UInt64(units))
    return Int64(UInt64(quantity).dividingFullWidth(product).quotient)
  }

}

public struct ProductionSaleAllocation: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var rowID: UUID
  public var evidenceID: String
  public var quantity: Int64
  public var grossCents: Int64
}

public struct ImmutableProductionCost: Codable, Identifiable, Sendable {
  public var id: UUID  // Existing production-book row identity.
  public var typeID: Int64
  public var units: Int64
  public var sourceSnapshot: Data
  public var material: Double?
  public var installation: Double?
  public var blueprint: Double?
  public var logistics: Double?
  public var historicalManualSoldUnits: Int64
  public var historicalManualSalePrice: Double?
  public var evidenceMode = false
  public var recordedAt: Date
  public init(
    id: UUID, typeID: Int64, units: Int64, sourceSnapshot: Data,
    material: Double?, installation: Double?, blueprint: Double?, logistics: Double?,
    historicalManualSoldUnits: Int64, historicalManualSalePrice: Double?, recordedAt: Date
  ) {
    self.id = id
    self.typeID = typeID
    self.units = units
    self.sourceSnapshot = sourceSnapshot
    self.material = material
    self.installation = installation
    self.blueprint = blueprint
    self.logistics = logistics
    self.historicalManualSoldUnits = historicalManualSoldUnits
    self.historicalManualSalePrice = historicalManualSalePrice
    self.recordedAt = recordedAt
  }
}

public struct ConsolidationImportReport: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var date = Date()
  public var filename: String
  public var sha256: String
  public var encoding: String
  public var delimiter: String
  public var outcomes: [String]
}

public struct SavedScienceJob: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var archived = false
  /// Legacy project assignment; science jobs are global since 2026-10-19 and new jobs store nil.
  public var projectID: UUID?
  public var blueprintTypeID: Int64
  public var name: String
  public var job: BlueprintScienceJob
  public var facilityName: String
  public var solarSystemID: Int64
  public var sourceIDs: [UUID]
  public var createdAt = Date()
  public var supplyPlan: BlueprintSupplyPlan?
  public init(
    projectID: UUID? = nil, blueprintTypeID: Int64, name: String, job: BlueprintScienceJob,
    facilityName: String, solarSystemID: Int64, sourceIDs: [UUID], supplyPlan: BlueprintSupplyPlan?
  ) {
    self.projectID = projectID
    self.blueprintTypeID = blueprintTypeID
    self.name = name
    self.job = job
    self.facilityName = facilityName
    self.solarSystemID = solarSystemID
    self.sourceIDs = sourceIDs
    self.supplyPlan = supplyPlan
  }
}

public struct ConsolidationWorkspace: Codable, Sendable {
  public var formatVersion = 1
  public var revision: Int64 = 0
  /// Legacy, read-only: production projects were removed on 2026-10-19. Stored values are
  /// decoded and re-encoded unchanged so existing data and backups stay complete.
  public var selectedProjectID: UUID?
  /// Legacy, read-only (see `selectedProjectID`).
  public var projects: [ConsolidatedProject] = []
  public var warehouses: [ManualWarehouse] = []
  /// Legacy, read-only (see `selectedProjectID`).
  public var reservations: [ProjectStockReservation] = []
  /// Legacy, read-only: manual price profiles were removed on 2026-10-22 because no calculation
  /// read them. Stored values are decoded and re-encoded unchanged.
  public var priceProfiles: [ManualPriceProfile] = []
  /// Legacy, read-only (see `selectedProjectID`).
  public var purchases: [ProjectPurchase] = []
  public var evidence: [ProductionSaleEvidence] = []
  public var sales: [ProductionSaleAllocation] = []
  public var costs: [ImmutableProductionCost] = []
  public var science: [SavedScienceJob] = []
  public var imports: [ConsolidationImportReport] = []
  public var warningThresholds: [Int64: Int64] = [:]
  public init() {}

  public static func normalized(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX"))
  }
  private func uniqueName(_ name: String, among names: [String]) throws {
    let normalized = Self.normalized(name)
    guard !normalized.isEmpty, !names.contains(where: { Self.normalized($0) == normalized }) else {
      throw ConsolidationError.invalid("Der Name ist leer oder bereits vergeben, auch im Archiv.")
    }
  }
  public mutating func createWarehouse(name: String) throws {
    try uniqueName(name, among: warehouses.map(\.name))
    warehouses.append(ManualWarehouse(name: name))
  }
  public mutating func updateWarehouse(_ warehouse: ManualWarehouse) throws {
    guard let index = warehouses.firstIndex(where: { $0.id == warehouse.id }) else {
      throw ConsolidationError.stalePreview
    }
    try uniqueName(warehouse.name, among: warehouses.filter { $0.id != warehouse.id }.map(\.name))
    guard warehouse.stock.allSatisfy({ $0.key > 0 && $0.value > 0 }) else {
      throw ConsolidationError.invalid("Bestände benötigen positive Typ-IDs und Mengen.")
    }
    warehouses[index] = warehouse
  }
  public mutating func addEvidence(_ receipt: ProductionSaleEvidence) throws {
    guard !receipt.id.isEmpty, receipt.typeID > 0, receipt.quantity > 0 else {
      throw ConsolidationError.invalid("Ungültiger Verkaufsbeleg.")
    }
    if let existing = evidence.first(where: { $0.id == receipt.id }) {
      guard
        existing.typeID == receipt.typeID && existing.quantity == receipt.quantity
          && existing.unitPrice == receipt.unitPrice && existing.totalCents == receipt.totalCents
      else {
        throw ConsolidationError.invalid("Widersprüchliche Daten für einen vorhandenen Beleg.")
      }
      return
    }
    _ = try receipt.amountCents()
    evidence.append(receipt)
  }
  public mutating func allocateSale(
    rowID: UUID, evidenceID: String, quantity: Int64, switchToEvidence: Bool
  ) throws {
    guard let costIndex = costs.firstIndex(where: { $0.id == rowID }),
      let receipt = evidence.first(where: { $0.id == evidenceID }),
      quantity > 0, receipt.typeID == costs[costIndex].typeID
    else { throw ConsolidationError.invalid("Beleg und Produktion passen nicht zusammen.") }
    guard costs[costIndex].evidenceMode || switchToEvidence else {
      throw ConsolidationError.invalid(
        "Den Wechsel von manuellen Angaben zu Belegzuordnungen ausdrücklich bestätigen.")
    }
    let sourceUsed = try sales.filter { $0.evidenceID == evidenceID }.reduce(Int64(0)) {
      try Self.add($0, $1.quantity)
    }
    let rowUsed = try sales.filter { $0.rowID == rowID }.reduce(Int64(0)) {
      try Self.add($0, $1.quantity)
    }
    guard quantity <= receipt.quantity - sourceUsed, quantity <= costs[costIndex].units - rowUsed
    else {
      throw ConsolidationError.invalid(
        "Der Beleg oder die Produktion ist bereits vollständig zugeordnet.")
    }
    let previouslyAllocated = try sales.filter { $0.evidenceID == evidenceID }.reduce(Int64(0)) {
      try Self.add($0, $1.grossCents)
    }
    let gross = try receipt.cumulativeCents(for: sourceUsed + quantity) - previouslyAllocated
    costs[costIndex].evidenceMode = true
    sales.append(
      ProductionSaleAllocation(
        rowID: rowID, evidenceID: evidenceID, quantity: quantity, grossCents: gross))
  }
  public func scienceRunReservations() -> [BlueprintRunReservation] {
    science.compactMap { saved in
      guard !saved.archived, case .invention(let job) = saved.job,
        case .ownedBPC(let itemID) = job.inputBPC
      else { return nil }
      return BlueprintRunReservation(
        planID: saved.id, blueprintItemID: itemID, runs: job.confidenceInputBPCRuns)
    }
  }

  public func validate() throws {
    // Legacy project, reservation, purchase and price profile records are kept as stored and not
    // validated.
    guard formatVersion == 1, revision >= 0,
      Set(warehouses.map(\.id)).count == warehouses.count,
      Set(evidence.map(\.id)).count == evidence.count,
      Set(costs.map(\.id)).count == costs.count, Set(sales.map(\.id)).count == sales.count
    else { throw ConsolidationError.invalid("Widersprüchliche Identitäten in den Arbeitsdaten.") }
    for w in warehouses {
      guard w.stock.allSatisfy({ $0.key > 0 && $0.value > 0 }) else {
        throw ConsolidationError.invalid("Ungültige Lagermengen.")
      }
    }
    for e in evidence {
      guard e.quantity > 0, try e.amountCents() > 0, e.typeID > 0 else {
        throw ConsolidationError.invalid("Ungültiger Beleg.")
      }
    }
    for sale in sales {
      guard sale.quantity > 0, let e = evidence.first(where: { $0.id == sale.evidenceID }),
        let c = costs.first(where: { $0.id == sale.rowID }), c.evidenceMode, c.typeID == e.typeID,
        sale.grossCents >= 0
      else { throw ConsolidationError.invalid("Ungültige Verkaufszuordnung.") }
    }
    for e in evidence {
      let used = try sales.filter { $0.evidenceID == e.id }.reduce(Int64(0)) {
        try Self.add($0, $1.quantity)
      }
      let gross = try sales.filter { $0.evidenceID == e.id }.reduce(Int64(0)) {
        try Self.add($0, $1.grossCents)
      }
      guard used <= e.quantity, gross == (try e.cumulativeCents(for: used)) else {
        throw ConsolidationError.invalid(
          "Beleg mehrfach oder mit widersprüchlichem Betrag zugeordnet.")
      }
    }
    for cost in costs {
      let used = try sales.filter { $0.rowID == cost.id }.reduce(Int64(0)) {
        try Self.add($0, $1.quantity)
      }
      guard cost.units >= 0, used <= cost.units else {
        throw ConsolidationError.invalid("Produktion überverkauft.")
      }
    }
  }

  public static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
    let (value, overflow) = a.addingReportingOverflow(b)
    guard !overflow else { throw ConsolidationError.overflow }
    return value
  }
  public static func multiply(_ a: Int64, _ b: Int64) throws -> Int64 {
    let (value, overflow) = a.multipliedReportingOverflow(by: b)
    guard !overflow else { throw ConsolidationError.overflow }
    return value
  }
}

public struct ConsolidationPreview: Sendable {
  public let id = UUID()
  public let baseRevision: Int64
  public let summary: [String]
  public let proposed: ConsolidationWorkspace
  public init(
    base: ConsolidationWorkspace, summary: [String],
    change: (inout ConsolidationWorkspace) throws -> Void
  ) throws {
    baseRevision = base.revision
    var candidate = base
    try change(&candidate)
    candidate.revision = try ConsolidationWorkspace.add(base.revision, 1)
    try candidate.validate()
    self.summary = summary + Self.details(base: base, proposed: candidate)
    proposed = candidate
  }
  public func applying(to current: ConsolidationWorkspace) throws -> ConsolidationWorkspace {
    guard current.revision == baseRevision else { throw ConsolidationError.stalePreview }
    return proposed
  }
}

extension ConsolidationPreview {
  /// Describe the frozen candidate, never the editable form or a later live snapshot.
  private static func details(base: ConsolidationWorkspace, proposed: ConsolidationWorkspace)
    -> [String]
  {
    var lines: [String] = []
    func money(_ cents: Int64?) -> String {
      guard let cents else { return "Planwert" }
      return "\(cents / 100).\(String(format: "%02lld", cents % 100)) ISK"
    }
    for warehouse in proposed.warehouses {
      let old = base.warehouses.first { $0.id == warehouse.id }
      if old?.name != warehouse.name || old?.notes != warehouse.notes
        || old?.archived != warehouse.archived
      {
        lines.append(
          "Lager \(warehouse.name): \(warehouse.archived ? "archiviert" : "aktiv"); Notizen: \(warehouse.notes)."
        )
      }
      for type in Set(warehouse.stock.keys).union(old?.stock.keys.map { $0 } ?? []).sorted() {
        let before = old?.stock[type] ?? 0
        let after = warehouse.stock[type] ?? 0
        if before != after {
          lines.append("Lager \(warehouse.name), Typ \(type): \(before) → \(after) Einheiten.")
        }
      }
    }
    for evidence in proposed.evidence where !base.evidence.contains(where: { $0.id == evidence.id })
    {
      lines.append(
        "Beleg \(evidence.id), Typ \(evidence.typeID): \(evidence.quantity) Einheiten, insgesamt \(money(try? evidence.amountCents())), Datum \(evidence.recordedAt.formatted(.iso8601))."
      )
    }
    for sale in proposed.sales where !base.sales.contains(where: { $0.id == sale.id }) {
      lines.append(
        "Produktion \(sale.rowID), Beleg \(sale.evidenceID): \(sale.quantity) Einheiten, \(money(sale.grossCents)) Bruttoerlös."
      )
    }
    for cost in proposed.costs
    where cost.evidenceMode && base.costs.first(where: { $0.id == cost.id })?.evidenceMode != true {
      lines.append(
        "Produktion \(cost.id): Belegmodus ersetzt bisherige manuelle Verkaufsmenge \(cost.historicalManualSoldUnits); diese bleibt als Historie erhalten und wird nicht addiert."
      )
    }
    for type in proposed.warningThresholds.keys.sorted()
    where base.warningThresholds[type] != proposed.warningThresholds[type] {
      lines.append(
        "Typ \(type): Warnschwelle \(base.warningThresholds[type].map(String.init) ?? "nicht festgelegt") → \(proposed.warningThresholds[type]!)."
      )
    }
    return lines
  }
}
