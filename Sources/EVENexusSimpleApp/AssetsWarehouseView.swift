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
  @State private var isPreparingWarehouse = false
  @State private var warehouse = AssetWarehouse(inventories: [])
  @State private var inventoryCount = 0
  @State private var factualQuantities: [Int64: Int64] = [:]
  @State private var totalUnits: Int64 = 0
  @State private var expandedLocationIDs = Set<Int64>()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text("Assets & Warehouse")
              .font(.largeTitle.bold())
            Text(
              "Stations and player structures are shown compactly. Click a location to show characters and contents."
            )
            .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer()
          if isPreparingWarehouse || isResolvingNames {
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
    .navigationTitle(AppLocalization.text("Assets & Warehouse"))
    .task(id: assetProjectionIdentity) {
      await prepareWarehouse()
    }
    .task(id: nameResolutionIdentity) {
      await resolveNames()
    }
  }

  private var warehouseSummary: some View {
    Panel(title: "Combined warehouse") {
      if inventoryCount == 0 {
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
              value: inventoryCount.formatted()
            )
            summaryMetric(
              "Item types",
              value: factualQuantities.count.formatted()
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
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        ForEach(warehouse.locations) { location in
          warehouseLocation(location)
        }
      }
    }
  }

  private func warehouseLocation(
    _ location: AssetWarehouseLocation
  ) -> some View {
    let isExpanded = expandedLocationIDs.contains(location.id)
    return VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.16)) {
          if isExpanded {
            expandedLocationIDs.remove(location.id)
          } else {
            expandedLocationIDs.insert(location.id)
          }
        }
      } label: {
        HStack(spacing: DesignTokens.spacingSM) {
          locationIcon(location)
          Text(locationTitle(location))
            .font(.headline)
            .foregroundStyle(DesignTokens.textPrimary)
            .lineLimit(1)
          Spacer(minLength: DesignTokens.spacingMD)
          Text(locationSummary(location))
            .font(.caption.monospacedDigit())
            .foregroundStyle(DesignTokens.textSecondary)
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(DesignTokens.textSecondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("warehouse.location.\(location.id)")
      .accessibilityLabel(
        "\(locationTitle(location)), \(locationSummary(location))"
      )
      .accessibilityValue(
        isExpanded ? "Expanded".localizedUI : "Collapsed".localizedUI
      )
      .accessibilityHint(
        "Show characters and contents at this location".localizedUI
      )

      if isExpanded {
        Divider()
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          ForEach(location.owners) { owner in
            DisclosureGroup {
              ownerContents(owner)
                .padding(.top, DesignTokens.spacingSM)
            } label: {
              HStack {
                Text(owner.ownerName)
                  .font(.subheadline.weight(.semibold))
                freshnessBadge(owner.state)
                Spacer()
                Text(ownerSummary(owner))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(DesignTokens.textSecondary)
              }
            }
            .accessibilityIdentifier(
              "warehouse.location.\(location.id).owner.\(owner.ownerID)"
            )
            if owner.id != location.owners.last?.id {
              Divider()
            }
          }
        }
        .padding(DesignTokens.spacingMD)
      }
    }
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
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
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value)
        .font(.title3.bold().monospacedDigit())
    }
  }

  private func freshnessBadge(_ state: DataFreshness) -> some View {
    Text(LocalizedStringKey(state.rawValue.uppercased()))
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
    if let resolvedName = location.resolvedName,
      !resolvedName.isEmpty
    {
      return resolvedName
    }
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
    case .station: "Station".localizedUI
    case .structure: "Player structure".localizedUI
    case .solarSystem: "Solar system".localizedUI
    case .item: "Container".localizedUI
    case .unresolved: "Unresolved location".localizedUI
    }
  }

  private func locationSummary(_ location: AssetWarehouseLocation) -> String {
    let characters =
      location.owners.count == 1
      ? "character".localizedUI : "characters".localizedUI
    return
      "\(location.owners.count) \(characters) · \(location.totalUnits.formatted()) \("items".localizedUI)"
  }

  private func ownerSummary(_ owner: AssetWarehouseOwner) -> String {
    "\(Set(owner.items.map(\.typeID)).count) \("types".localizedUI) · \(owner.totalUnits.formatted()) \("items".localizedUI)"
  }

  @ViewBuilder
  private func locationIcon(_ location: AssetWarehouseLocation) -> some View {
    if location.kind == .structure,
      let typeID = structureTypeID(for: location),
      let url = URL(
        string:
          "https://images.evetech.net/types/\(typeID)/icon?size=32&tenant=tranquility"
      )
    {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
        default:
          Image(systemName: "building.2.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(DesignTokens.accent)
        }
      }
      .frame(width: 24, height: 24)
      .help(typeName(typeID))
      .accessibilityHidden(true)
    } else {
      Image(systemName: locationSystemIcon(location.kind))
        .frame(width: 24, height: 24)
        .foregroundStyle(
          location.kind == .structure
            ? DesignTokens.accent : DesignTokens.textSecondary
        )
        .accessibilityHidden(true)
    }
  }

  private func locationSystemIcon(_ kind: AssetLocationKind) -> String {
    switch kind {
    case .station: "building.columns.fill"
    case .structure: "building.2.fill"
    case .solarSystem: "sparkles"
    case .item: "shippingbox.fill"
    case .unresolved: "questionmark.diamond.fill"
    }
  }

  private func structureTypeID(
    for location: AssetWarehouseLocation
  ) -> Int64? {
    location.resolvedTypeID
      ?? runtime.productionBasis.structures.first(where: {
        $0.structureID == location.id
      })?.structureTypeID
  }

  private func typeName(_ typeID: Int64) -> String {
    typeNames[typeID] ?? "Type \(typeID)"
  }

  private func stockLine(typeID: Int64) -> WarehouseStockLine {
    WarehouseStockLine(
      typeID: typeID,
      factualQuantity: factualQuantities[typeID, default: 0],
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

  private var targetQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var assetProjectionIdentity: String {
    characters.map { character in
      [
        String(character.characterID),
        character.characterName,
        String(character.assetSnapshot?.count ?? 0),
        String(character.lastSyncAt?.timeIntervalSince1970 ?? 0),
      ].joined(separator: ":")
    }
    .joined(separator: "|")
  }

  private var nameResolutionIdentity: String {
    let snapshotPart = warehouse.snapshotIDs.map(\.uuidString)
      .sorted()
      .joined(separator: ",")
    let targetPart = stockTargets.map {
      "\($0.typeID):\($0.targetQuantity):\($0.updatedAt.timeIntervalSince1970)"
    }.joined(separator: ",")
    return snapshotPart + "|" + targetPart
  }

  private func prepareWarehouse() async {
    isPreparingWarehouse = true
    defer { isPreparingWarehouse = false }
    let payloads = characters.compactMap { character in
      character.assetSnapshot.map {
        StoredAssetSnapshotPayload(
          ownerID: character.characterID,
          ownerName: character.characterName,
          encodedSnapshot: $0
        )
      }
    }
    let prepared = await runtime.prepareAssetWarehouse(
      identity: assetProjectionIdentity,
      payloads: payloads
    )
    guard !Task.isCancelled else { return }
    warehouse = prepared.warehouse
    inventoryCount = prepared.inventoryCount
    factualQuantities = prepared.factualQuantities
    totalUnits = prepared.totalUnits
  }

  private func resolveNames() async {
    isResolvingNames = true
    defer { isResolvingNames = false }
    let typeIDs = Set(factualQuantities.keys)
      .union(stockTargets.map(\.typeID))
      .union(warehouse.locations.compactMap(\.resolvedTypeID))
      .union(
        runtime.productionBasis.structures.compactMap(\.structureTypeID)
      )
    async let resolvedTypes = runtime.resolveAssetTypeNames(typeIDs)
    let publicLocationIDs = Set(
      warehouse.locations.lazy
        .filter {
          $0.kind != .structure
            && $0.id < AssetLocationKind.minimumPlayerStructureID
        }
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
