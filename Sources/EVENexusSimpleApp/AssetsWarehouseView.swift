import EVENexusCore
import SwiftData
import SwiftUI

struct AssetsWarehouseView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]

  @State private var typeNames: [Int64: String] = [:]
  @State private var locationNames: [Int64: String] = [:]
  @State private var targetItemName = ""
  @State private var targetQuantity: Int64 = 0
  @State private var targetError: String?
  @State private var isResolvingNames = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text("Assets & Warehouse")
              .font(.largeTitle.bold())
            Text(
              "Stations first, then each character owner and the contents stored there."
            )
            .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer()
          if isResolvingNames {
            ProgressView()
              .controlSize(.small)
          }
        }

        warehouseSummary
        targetStockPanel
        warehouseLocations
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Assets & Warehouse")
    .task(id: warehouseIdentity) {
      await resolveNames()
    }
  }

  private var warehouseSummary: some View {
    Panel(title: "Combined warehouse") {
      if inventories.isEmpty {
        Label(
          "No stored asset snapshots are available. Open Characters and synchronize the connected characters.",
          systemImage: "shippingbox"
        )
        .foregroundStyle(DesignTokens.caution)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
          GridRow {
            summaryMetric(
              "Locations",
              value: warehouse.locations.count.formatted()
            )
            summaryMetric(
              "Characters",
              value: inventories.count.formatted()
            )
            summaryMetric(
              "Item types",
              value: warehouse.factualQuantities.count.formatted()
            )
            summaryMetric(
              "Units",
              value: totalUnits.formatted()
            )
          }
        }
        if warehouse.sourceStates.contains(where: { $0 != .fresh }) {
          Label(
            "At least one character snapshot is partial, stale, forbidden or unavailable. Its state remains visible under the owner.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        if !warehouse.unresolvedLocationIDs.isEmpty {
          Label(
            "\(warehouse.unresolvedLocationIDs.count) nested or unresolved location \(warehouse.unresolvedLocationIDs.count == 1 ? "reference is" : "references are") excluded from allocatable stock.",
            systemImage: "questionmark.diamond.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        Text(
          "The planner can use the combined factual quantities from every stored character. Target quantities below remain protected as minimum stock."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var targetStockPanel: some View {
    Panel(title: "Target stock") {
      Text(
        "Set the quantity that should remain in the combined warehouse. The planner uses only stock above this target."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacingSM) {
        TextField("Exact item name", text: $targetItemName)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("warehouse.target.item-name")
        TextField(
          "Target quantity",
          value: $targetQuantity,
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 150)
        .accessibilityIdentifier("warehouse.target.quantity")
        Button("Add or update") {
          Task { await saveTarget() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          targetItemName.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty || targetQuantity < 0
        )
      }

      if let targetError {
        Label(targetError, systemImage: "xmark.octagon.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }

      if stockTargets.isEmpty {
        Text("No protected target quantities configured.")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
          GridRow {
            Text("Item")
            Text("In warehouse")
            Text("Target")
            Text("Free above target")
            Text("Missing to target")
            Text("")
          }
          .font(.caption.bold())
          .foregroundStyle(DesignTokens.textSecondary)
          Divider()
          ForEach(stockTargets) { target in
            StockTargetEditorRow(
              target: target,
              stock: stockLine(typeID: target.typeID),
              onDelete: { deleteTarget(target) }
            )
          }
        }
      }
    }
  }

  @ViewBuilder
  private var warehouseLocations: some View {
    if !warehouse.locations.isEmpty {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        ForEach(warehouse.locations) { location in
          Panel(title: locationTitle(location)) {
            HStack {
              Label(
                locationKindLabel(location.kind),
                systemImage: locationIcon(location.kind)
              )
              Spacer()
              Text(
                "\(location.owners.count) \(location.owners.count == 1 ? "owner" : "owners") · \(location.distinctTypeCount) types · \(location.totalUnits.formatted()) units"
              )
              .font(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(location.owners) { owner in
              DisclosureGroup {
                ownerContents(owner)
                  .padding(.top, DesignTokens.spacingSM)
              } label: {
                HStack {
                  Text(owner.ownerName)
                    .font(.headline)
                  freshnessBadge(owner.state)
                  Spacer()
                  Text(
                    "\(Set(owner.items.map(\.typeID)).count) types · \(owner.totalUnits.formatted()) units"
                  )
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(DesignTokens.textSecondary)
                }
              }
              .accessibilityIdentifier(
                "warehouse.location.\(location.id).owner.\(owner.ownerID)"
              )
              Divider()
            }
          }
        }
      }
    }
  }

  private func ownerContents(_ owner: AssetWarehouseOwner) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
      GridRow {
        Text("Item")
        Text("Quantity")
        Text("Target")
        Text("Inventory flag")
      }
      .font(.caption.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      ForEach(ownerContentRows(owner)) { row in
        GridRow {
          Text(typeName(row.typeID))
          Text(row.quantity.formatted())
            .font(.body.monospacedDigit())
          Text(targetQuantities[row.typeID, default: 0].formatted())
            .font(.body.monospacedDigit())
          Text(row.locationFlag)
            .font(.caption.monospaced())
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  private func summaryMetric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value)
        .font(.title3.bold().monospacedDigit())
    }
  }

  private func freshnessBadge(_ state: DataFreshness) -> some View {
    Text(state.rawValue.uppercased())
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(freshnessColor(state).opacity(0.18))
      .foregroundStyle(freshnessColor(state))
      .clipShape(Capsule())
  }

  private func freshnessColor(_ state: DataFreshness) -> Color {
    switch state {
    case .fresh: DesignTokens.positive
    case .partial, .stale: DesignTokens.caution
    case .forbidden, .unavailable: DesignTokens.negative
    }
  }

  private func locationTitle(_ location: AssetWarehouseLocation) -> String {
    if let configured = runtime.productionBasis.structures.first(where: {
      $0.structureID == location.id
    }) {
      if let eveName = configured.eveStructureName,
        !eveName.isEmpty
      {
        return eveName
      }
      if !configured.name.isEmpty { return configured.name }
      return "Location \(location.id)"
    }
    return locationNames[location.id]
      ?? "\(locationKindLabel(location.kind)) \(location.id)"
  }

  private func locationKindLabel(_ kind: AssetLocationKind) -> String {
    switch kind {
    case .station: "Station"
    case .structure: "Player structure"
    case .solarSystem: "Solar system"
    case .item: "Container"
    case .unresolved: "Unresolved location"
    }
  }

  private func locationIcon(_ kind: AssetLocationKind) -> String {
    switch kind {
    case .station: "building.columns.fill"
    case .structure: "building.2.fill"
    case .solarSystem: "sparkles"
    case .item: "shippingbox.fill"
    case .unresolved: "questionmark.diamond.fill"
    }
  }

  private func typeName(_ typeID: Int64) -> String {
    typeNames[typeID] ?? "Type \(typeID)"
  }

  private func stockLine(typeID: Int64) -> WarehouseStockLine {
    availability.lines.first { $0.typeID == typeID }
      ?? WarehouseStockLine(
        typeID: typeID,
        factualQuantity: 0,
        targetQuantity: targetQuantities[typeID, default: 0]
      )
  }

  private func ownerContentRows(
    _ owner: AssetWarehouseOwner
  ) -> [OwnerContentRow] {
    struct Key: Hashable {
      let typeID: Int64
      let flag: String
    }
    let grouped = Dictionary(
      grouping: owner.items,
      by: { Key(typeID: $0.typeID, flag: $0.locationFlag) }
    )
    return grouped.map { key, items in
      OwnerContentRow(
        typeID: key.typeID,
        locationFlag: key.flag,
        quantity: items.reduce(0) {
          AssetWarehouse.saturatedAdd($0, $1.quantity)
        }
      )
    }
    .sorted {
      let comparison = typeName($0.typeID)
        .localizedCaseInsensitiveCompare(typeName($1.typeID))
      if comparison == .orderedSame {
        return $0.locationFlag < $1.locationFlag
      }
      return comparison == .orderedAscending
    }
  }

  private var inventories: [AssetOwnerInventory] {
    characters.compactMap { character in
      guard let data = character.assetSnapshot,
        let assets = try? JSONDecoder().decode(
          Sourced<AssetSnapshot>.self,
          from: data
        )
      else { return nil }
      return AssetOwnerInventory(
        ownerID: character.characterID,
        ownerName: character.characterName,
        assets: assets
      )
    }
  }

  private var warehouse: AssetWarehouse {
    AssetWarehouse(inventories: inventories)
  }

  private var targetQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var availability: WarehouseAvailability {
    warehouse.availability(targetQuantities: targetQuantities)
  }

  private var totalUnits: Int64 {
    warehouse.factualQuantities.values.reduce(
      0,
      AssetWarehouse.saturatedAdd
    )
  }

  private var warehouseIdentity: String {
    let snapshotPart = warehouse.snapshotIDs.map(\.uuidString)
      .sorted()
      .joined(separator: ",")
    let targetPart = stockTargets.map {
      "\($0.typeID):\($0.targetQuantity):\($0.updatedAt.timeIntervalSince1970)"
    }.joined(separator: ",")
    return snapshotPart + "|" + targetPart
  }

  private func resolveNames() async {
    isResolvingNames = true
    defer { isResolvingNames = false }
    let typeIDs = Set(warehouse.factualQuantities.keys)
      .union(stockTargets.map(\.typeID))
    async let resolvedTypes = runtime.resolveAssetTypeNames(typeIDs)
    let publicLocationIDs = Set(
      warehouse.locations.lazy
        .filter { $0.id < 1_000_000_000_000 }
        .map(\.id)
    )
    async let resolvedLocations = runtime.resolveAssetLocationNames(
      publicLocationIDs
    )
    typeNames = await resolvedTypes
    locationNames = await resolvedLocations.value ?? [:]
  }

  private func saveTarget() async {
    targetError = nil
    let acceptedName = targetItemName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard targetQuantity >= 0 else {
      targetError = "The target quantity must not be negative."
      return
    }
    do {
      guard
        let typeID = try await runtime.resolveAssetTypeID(
          named: acceptedName
        )
      else {
        targetError =
          "The item name was not found in the active SDE catalog."
        return
      }
      if let existing = stockTargets.first(where: {
        $0.typeID == typeID
      }) {
        existing.typeName = acceptedName
        existing.targetQuantity = targetQuantity
        existing.updatedAt = .now
      } else {
        modelContext.insert(
          StoredStockTarget(
            typeID: typeID,
            typeName: acceptedName,
            targetQuantity: targetQuantity
          )
        )
      }
      try modelContext.save()
      targetItemName = ""
      targetQuantity = 0
    } catch {
      targetError = error.localizedDescription
    }
  }

  private func deleteTarget(_ target: StoredStockTarget) {
    modelContext.delete(target)
    do {
      try modelContext.save()
    } catch {
      targetError = error.localizedDescription
    }
  }
}

private struct OwnerContentRow: Identifiable {
  var id: String { "\(typeID)|\(locationFlag)" }
  let typeID: Int64
  let locationFlag: String
  let quantity: Int64
}

private struct StockTargetEditorRow: View {
  @Bindable var target: StoredStockTarget
  @Environment(\.modelContext) private var modelContext
  let stock: WarehouseStockLine
  let onDelete: () -> Void

  var body: some View {
    GridRow {
      Text(target.typeName)
      Text(stock.factualQuantity.formatted())
        .font(.body.monospacedDigit())
      TextField(
        "Target",
        value: $target.targetQuantity,
        format: .number
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 120)
      .onChange(of: target.targetQuantity) {
        if target.targetQuantity < 0 {
          target.targetQuantity = 0
        }
        target.updatedAt = .now
        try? modelContext.save()
      }
      Text(stock.allocatableQuantity.formatted())
        .font(.body.monospacedDigit())
      Text(stock.missingToTarget.formatted())
        .font(.body.monospacedDigit())
        .foregroundStyle(
          stock.missingToTarget > 0
            ? DesignTokens.caution : DesignTokens.textSecondary
        )
      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
      }
      .buttonStyle(.plain)
      .help("Remove target quantity")
    }
  }
}
