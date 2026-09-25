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
  public func price(_ typeID: Int64, at date: Date) -> ISKAmount? {
    guard date >= validFrom, validUntil.map({ date < $0 }) ?? true else { return nil }
    return prices[typeID]
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
  public var projectID: UUID
  public var blueprintTypeID: Int64
  public var name: String
  public var job: BlueprintScienceJob
  public var facilityName: String
  public var solarSystemID: Int64
  public var sourceIDs: [UUID]
  public var createdAt = Date()
  public var supplyPlan: BlueprintSupplyPlan?
  public init(
    projectID: UUID, blueprintTypeID: Int64, name: String, job: BlueprintScienceJob,
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
  public var selectedProjectID: UUID?
  public var projects: [ConsolidatedProject] = []
  public var warehouses: [ManualWarehouse] = []
  public var reservations: [ProjectStockReservation] = []
  public var priceProfiles: [ManualPriceProfile] = []
  public var purchases: [ProjectPurchase] = []
  public var evidence: [ProductionSaleEvidence] = []
  public var sales: [ProductionSaleAllocation] = []
  public var costs: [ImmutableProductionCost] = []
  public var science: [SavedScienceJob] = []
  public var imports: [ConsolidationImportReport] = []
  public var warningThresholds: [Int64: Int64] = [:]
  public init() {}
  public var selectedProject: ConsolidatedProject? { projects.first { $0.id == selectedProjectID } }

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
  public mutating func createProject(name: String, duplicate id: UUID? = nil) throws {
    try uniqueName(name, among: projects.map(\.name))
    var project =
      id.flatMap { id in projects.first { $0.id == id } } ?? ConsolidatedProject(name: name)
    project.id = UUID()
    project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    project.status = .planning
    project.previousStatus = .planning
    project.updatedAt = .now
    project.planSnapshot = nil
    project.blueprintSupplyData = nil
    // Duplicates never inherit a reservation, shopping override, science job or receipt.
    project.logisticsOverrideCents = nil
    project.productionOverrideCents = nil
    projects.append(project)
    selectedProjectID = project.id
  }
  public mutating func updateProject(_ project: ConsolidatedProject) throws {
    guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
      throw ConsolidationError.stalePreview
    }
    try uniqueName(project.name, among: projects.filter { $0.id != project.id }.map(\.name))
    guard (1...3).contains(project.priority), project.quantityCaps.values.allSatisfy({ $0 >= 0 }),
      project.logisticsOverrideCents.map({ $0 >= 0 }) ?? true,
      project.productionOverrideCents.map({ $0 >= 0 }) ?? true
    else { throw ConsolidationError.invalid("Ungültige Projektwerte.") }
    if project.status == .archived,
      reservations.contains(where: { $0.projectID == project.id && $0.remaining > 0 })
    {
      throw ConsolidationError.invalid("Vor dem Archivieren alle aktiven Reservierungen freigeben.")
    }
    projects[index] = project
    if project.status == .archived && selectedProjectID == project.id {
      selectedProjectID = projects.first { $0.status != .archived }?.id
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
    if warehouse.archived,
      reservations.contains(where: { $0.source == warehouse.id.uuidString && $0.remaining > 0 })
    {
      throw ConsolidationError.invalid("Das Lager besitzt aktive Reservierungen.")
    }
    warehouses[index] = warehouse
  }
  public mutating func createPriceProfile(name: String, from: Date, until: Date?) throws {
    try uniqueName(name, among: priceProfiles.map(\.name))
    guard until.map({ $0 > from }) ?? true else {
      throw ConsolidationError.invalid("Das Gültigkeitsende muss nach dem Beginn liegen.")
    }
    var p = ManualPriceProfile(name: name, validFrom: from)
    p.validUntil = until
    priceProfiles.append(p)
  }

  /// Base stock is the existing ESI availability AFTER its established protection calculation.
  public func stockSources(projectID: UUID, esi: [Int64: Int64]) throws -> [String: [Int64: Int64]]
  {
    guard let project = projects.first(where: { $0.id == projectID }) else {
      throw ConsolidationError.stalePreview
    }
    var sources = ["esi": esi]
    for w in warehouses where !w.archived && project.warehouseIDs.contains(w.id) {
      sources[w.id.uuidString] = w.stock
    }
    for key in sources.keys.sorted() {
      for reservation in reservations
      where reservation.projectID != projectID && reservation.source == key {
        let before = sources[key]?[reservation.typeID] ?? 0
        sources[key]?[reservation.typeID] = max(0, before - reservation.remaining)
      }
      for type in project.excludedTypes { sources[key]?[type] = 0 }
    }
    // A cap applies to the total available quantity, not once per warehouse.
    for (type, cap) in project.quantityCaps {
      var left = cap
      for key in sources.keys.sorted() {
        let accepted = min(left, max(0, sources[key]?[type] ?? 0))
        sources[key]?[type] = accepted
        left -= accepted
      }
    }
    return sources
  }
  public func availableStock(projectID: UUID, esi: [Int64: Int64]) throws -> [Int64: Int64] {
    var result: [Int64: Int64] = [:]
    for stock in try stockSources(projectID: projectID, esi: esi).values {
      for (type, quantity) in stock {
        result[type] = try Self.add(result[type, default: 0], quantity)
      }
    }
    return result
  }
  public mutating func reserve(
    projectID: UUID, quantities: [Int64: Int64], esi: [Int64: Int64], expires: Date?
  ) throws {
    guard projects.contains(where: { $0.id == projectID && $0.status != .archived }),
      quantities.allSatisfy({ $0.key > 0 && $0.value >= 0 })
    else { throw ConsolidationError.invalid("Ungültige Reservierung.") }
    let sources = try stockSources(projectID: projectID, esi: esi)
    var replacements: [ProjectStockReservation] = []
    for (type, quantity) in quantities.sorted(by: { $0.key < $1.key }) {
      var remaining = quantity
      for source in sources.keys.sorted() {
        let amount = min(remaining, max(0, sources[source]?[type] ?? 0))
        if amount > 0 {
          replacements.append(
            ProjectStockReservation(
              projectID: projectID, typeID: type, source: source, quantity: amount,
              expiresAt: expires))
          remaining -= amount
        }
      }
      guard remaining == 0 else {
        throw ConsolidationError.invalid("Nicht genügend unreservierter Bestand für Typ \(type).")
      }
    }
    for index in reservations.indices where reservations[index].projectID == projectID {
      reservations[index].released += reservations[index].remaining
    }
    reservations.append(contentsOf: replacements)
  }
  public mutating func changeReservation(id: UUID, quantity: Int64, consume: Bool) throws {
    guard let i = reservations.firstIndex(where: { $0.id == id }), quantity > 0,
      quantity <= reservations[i].remaining
    else {
      throw ConsolidationError.invalid("Die Menge überschreitet die aktive Reservierung.")
    }
    if consume {
      reservations[i].consumed += quantity
    } else {
      reservations[i].released += quantity
    }
  }
  /// Deterministic proposal only. Callers must preview and explicitly confirm the resulting reductions.
  public mutating func resolveStockConflicts(esi: [Int64: Int64]) throws -> [String] {
    var remaining = ["esi": esi]
    for w in warehouses where !w.archived { remaining[w.id.uuidString] = w.stock }
    let ordered = reservations.indices.sorted {
      return reservations[$0].id.uuidString < reservations[$1].id.uuidString
    }
    let ranked = ordered.sorted { a, b in
      let left = projects.first { $0.id == reservations[a].projectID }?.priority ?? 3
      let right = projects.first { $0.id == reservations[b].projectID }?.priority ?? 3
      return left == right
        ? reservations[a].id.uuidString < reservations[b].id.uuidString : left < right
    }
    var report: [String] = []
    var remainingDemand: [String: Int64] = [:]
    for i in ranked where reservations[i].remaining > 0 {
      let r = reservations[i]
      let available = max(0, remaining[r.source]?[r.typeID] ?? 0)
      let project = projects.first { $0.id == r.projectID }
      let demandKey = "\(r.projectID):\(r.typeID)"
      if remainingDemand[demandKey] == nil {
        var demand = Int64.max
        if let data = project?.planSnapshot,
          let plan = try? JSONDecoder().decode(IndustryPlanSnapshot.self, from: data)
        {
          demand = try plan.stockAllocations.filter { $0.typeID == r.typeID }.reduce(Int64(0)) {
            try Self.add($0, $1.quantity)
          }
        }
        if let cap = project?.quantityCaps[r.typeID] { demand = min(demand, cap) }
        remainingDemand[demandKey] = demand
      }
      let eligible =
        project?.status != .archived && project?.excludedTypes.contains(r.typeID) != true
        && (r.source == "esi"
          || project?.warehouseIDs.contains(UUID(uuidString: r.source) ?? UUID()) == true)
      let kept = eligible ? min(available, r.remaining, remainingDemand[demandKey] ?? 0) : 0
      remainingDemand[demandKey] = max(0, (remainingDemand[demandKey] ?? 0) - kept)
      if kept < r.remaining {
        reservations[i].released += r.remaining - kept
        report.append("\(r.typeID): \(r.remaining - kept) freigeben (\(r.projectID)).")
      }
      remaining[r.source, default: [:]][r.typeID] = available - kept
    }
    return report
  }
  public mutating func updatePurchase(
    projectID: UUID, typeID: Int64, override: Int64?, purchased: Int64
  ) throws {
    guard let i = purchases.firstIndex(where: { $0.projectID == projectID && $0.typeID == typeID }),
      purchased >= 0, override.map({ $0 >= 0 }) ?? true
    else { throw ConsolidationError.invalid("Ungültige Einkaufsmenge.") }
    purchases[i].override = override
    purchases[i].purchased = purchased
  }
  public func purchasingCSV(projectID: UUID? = nil) throws -> String {
    let active = Set(projects.filter { $0.status != .archived }.map(\.id))
    let grouped = Dictionary(
      grouping: purchases.filter {
        active.contains($0.projectID) && (projectID == nil || $0.projectID == projectID)
      }, by: \.typeID)
    var lines = [
      "type_id,item_name,target_quantity,purchased_quantity,remaining_quantity,project_count"
    ]
    for (type, entries) in grouped.sorted(by: { $0.key < $1.key }) {
      let target = try entries.reduce(Int64(0)) { try Self.add($0, $1.target) }
      let bought = try entries.reduce(Int64(0)) { try Self.add($0, $1.purchased) }
      let remaining = try entries.reduce(Int64(0)) { try Self.add($0, $1.remaining) }
      let name = (entries.first?.name ?? "").replacingOccurrences(of: "\"", with: "\"\"")
      lines.append(
        "\(type),\"\(name)\",\(target),\(bought),\(remaining),\(Set(entries.map(\.projectID)).count)"
      )
    }
    return lines.joined(separator: "\n") + "\n"
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
    let active = Set(projects.filter { $0.status != .archived }.map(\.id))
    return science.compactMap { saved in
      guard !saved.archived, active.contains(saved.projectID), case .invention(let job) = saved.job,
        case .ownedBPC(let itemID) = job.inputBPC
      else { return nil }
      return BlueprintRunReservation(
        planID: saved.id, blueprintItemID: itemID, runs: job.confidenceInputBPCRuns)
    }
  }

  public func validate() throws {
    let projectIDs = Set(projects.map(\.id))
    let warehouseIDs = Set(warehouses.map(\.id))
    guard formatVersion == 1, revision >= 0, projectIDs.count == projects.count,
      warehouseIDs.count == warehouses.count,
      Set(priceProfiles.map(\.id)).count == priceProfiles.count,
      Set(reservations.map(\.id)).count == reservations.count,
      Set(evidence.map(\.id)).count == evidence.count,
      Set(costs.map(\.id)).count == costs.count, Set(sales.map(\.id)).count == sales.count,
      Set(purchases.map { "\($0.projectID):\($0.typeID)" }).count == purchases.count,
      selectedProjectID.map({ projectIDs.contains($0) }) ?? true
    else { throw ConsolidationError.invalid("Widersprüchliche Identitäten in den Projektdaten.") }
    for p in projects {
      guard !Self.normalized(p.name).isEmpty, (1...3).contains(p.priority),
        p.quantityCaps.values.allSatisfy({ $0 >= 0 }),
        p.warehouseIDs.isSubset(of: warehouseIDs)
      else { throw ConsolidationError.invalid("Ungültige Projekteinstellungen.") }
    }
    for w in warehouses {
      guard w.stock.allSatisfy({ $0.key > 0 && $0.value > 0 }) else {
        throw ConsolidationError.invalid("Ungültige Lagermengen.")
      }
    }
    for r in reservations {
      guard projectIDs.contains(r.projectID), r.typeID > 0, r.quantity > 0, r.consumed >= 0,
        r.released >= 0,
        r.consumed <= r.quantity, r.released <= r.quantity - r.consumed
      else { throw ConsolidationError.invalid("Ungültige Reservierung.") }
    }
    for p in purchases {
      guard projectIDs.contains(p.projectID), p.typeID > 0, p.planned >= 0, p.purchased >= 0,
        p.override.map({ $0 >= 0 }) ?? true
      else { throw ConsolidationError.invalid("Ungültige Einkaufsdaten.") }
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
    func projectName(_ id: UUID) -> String {
      proposed.projects.first { $0.id == id }?.name ?? "Projekt nicht verfügbar"
    }
    for p in proposed.projects {
      let old = base.projects.first { $0.id == p.id }
      if old?.name != p.name || old?.status != p.status || old?.priority != p.priority
        || old?.warehouseIDs != p.warehouseIDs || old?.excludedTypes != p.excludedTypes
        || old?.quantityCaps != p.quantityCaps || old?.priceProfileID != p.priceProfileID
        || old?.logisticsOverrideCents != p.logisticsOverrideCents
        || old?.productionOverrideCents != p.productionOverrideCents
      {
        lines.append("Projekt \(p.name): Status \(p.status.rawValue), Priorität \(p.priority).")
        let warehouses = proposed.warehouses.filter { p.warehouseIDs.contains($0.id) }.map(\.name)
          .sorted()
        lines.append(
          "Manuelle Lager: \(warehouses.isEmpty ? "keine" : warehouses.joined(separator: ", ")).")
        lines.append(
          "Ausgeschlossene Typen: \(p.excludedTypes.isEmpty ? "keine" : p.excludedTypes.sorted().map(String.init).joined(separator: ", "))."
        )
        let caps = p.quantityCaps.sorted { $0.key < $1.key }.map { "Typ \($0.key): \($0.value)" }
        lines.append("Mengengrenzen: \(caps.isEmpty ? "keine" : caps.joined(separator: ", ")).")
        lines.append(
          "Preisprofil: \(proposed.priceProfiles.first { $0.id == p.priceProfileID }?.name ?? "Aktuelle Planpreise"). Logistik: \(money(p.logisticsOverrideCents)); Installation: \(money(p.productionOverrideCents))."
        )
      }
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
    for r in proposed.reservations {
      let old = base.reservations.first { $0.id == r.id }
      if old?.quantity != r.quantity || old?.consumed != r.consumed || old?.released != r.released
        || old?.expiresAt != r.expiresAt
      {
        let source =
          r.source == "esi"
          ? "ESI"
          : (proposed.warehouses.first { $0.id.uuidString == r.source }?.name
            ?? "Lager nicht verfügbar")
        lines.append(
          "\(projectName(r.projectID)), Typ \(r.typeID), \(source): reserviert \(old?.remaining ?? 0) → \(r.remaining), verbraucht \(r.consumed), freigegeben \(r.released); Termin \(r.expiresAt?.formatted(.iso8601) ?? "keiner")."
        )
      }
    }
    for profile in proposed.priceProfiles {
      let old = base.priceProfiles.first { $0.id == profile.id }
      if old?.name != profile.name || old?.validFrom != profile.validFrom
        || old?.validUntil != profile.validUntil || old?.source != profile.source
      {
        lines.append(
          "Preisprofil \(profile.name): ab \(profile.validFrom.formatted(.iso8601)), bis \(profile.validUntil?.formatted(.iso8601) ?? "unbegrenzt"), Quelle \(profile.source)."
        )
      }
      for type in profile.prices.keys.sorted() where old?.prices[type] != profile.prices[type] {
        lines.append(
          "Preisprofil \(profile.name), Typ \(type): \(old?.prices[type]?.displayText ?? "fehlend") → \(profile.prices[type]!.displayText) ISK je Einheit."
        )
      }
    }
    for p in proposed.purchases {
      let old = base.purchases.first { $0.id == p.id }
      if old?.planned != p.planned || old?.override != p.override || old?.purchased != p.purchased {
        lines.append(
          "\(projectName(p.projectID)), Typ \(p.typeID): Planbedarf \(p.planned), Ziel \(old?.target ?? 0) → \(p.target), gekauft \(old?.purchased ?? 0) → \(p.purchased), offen \(p.remaining). Kein Lagerzugang."
        )
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
