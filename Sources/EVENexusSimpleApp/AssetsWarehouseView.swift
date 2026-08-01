import EVENexusCore
import SwiftData
import SwiftUI

enum AssetInventoryViewMode: Equatable, Sendable {
  case allItems
  case productionWarehouse
}

struct AssetsWarehouseView: View {
  let mode: AssetInventoryViewMode

  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]

  @AppStorage("asset.inventory.organization")
  private var inventoryOrganizationRawValue =
    AssetInventoryOrganization.alphabetical.rawValue
  @State private var typeNames: [Int64: String] = [:]
  @State private var typeClassifications: [Int64: IndustryItemClassification] = [:]
  @State private var locationNames: [Int64: String] = [:]
  @State private var selectedTargetItem: ItemTypeSearchResult?
  @State private var inventoryFilter = ""
  @State private var targetQuantity: Int64 = 0
  @State private var targetError: String?
  @State private var isResolvingNames = false
  @State private var isPreparingWarehouse = false
  @State private var warehouse = AssetWarehouse(inventories: [])
  @State private var inventoryCount = 0
  @State private var factualQuantities: [Int64: Int64] = [:]
  @State private var totalUnits: Int64 = 0
  @State private var expandedLocationIDs = Set<Int64>()
  @State private var expandedOwnerKeys = Set<AssetWarehouseOwnerContentKey>()
  @State private var ownerRowsByKey:
    [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentLine]] = [:]
  @State private var ownerSectionsByKey:
    [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentSection]] = [:]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(viewTitle.localizedUI)
              .font(.largeTitle.bold())
            Text(viewDescription.localizedUI)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer()
          if isPreparingWarehouse || isResolvingNames {
            ProgressView()
              .controlSize(.small)
          }
        }

        warehouseSummary
        inventoryFilterPanel
        if mode == .productionWarehouse {
          targetStockPanel
        }
        warehouseLocations
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text(viewTitle))
    .task(id: assetProjectionIdentity) {
      await prepareWarehouse()
    }
    .task(id: nameResolutionIdentity) {
      await resolveNames()
    }
    .task(id: inventoryOrganizationRawValue) {
      await organizeOwnerRows()
    }
    .onChange(of: inventoryFilter) { _, _ in
      expandFilteredResults()
    }
  }

  private var inventoryFilterPanel: some View {
    Panel(title: "Display & filter") {
      HStack(alignment: .center, spacing: DesignTokens.spacingMD) {
        Text("Arrange items")
          .font(.subheadline.weight(.semibold))
        Picker(
          "Arrange items",
          selection: inventoryOrganizationBinding
        ) {
          ForEach(AssetInventoryOrganization.allCases) { organization in
            Text(organizationLabel(organization).localizedUI)
              .tag(organization)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
        .accessibilityIdentifier("warehouse.inventory-organization")
        Spacer()
      }
      Text(
        "Group and main group use the hierarchy from the active SDE catalog. Unresolved types remain visible under Unclassified."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Divider()

      HStack(spacing: DesignTokens.spacingSM) {
        TextField("Filter item name or type ID", text: $inventoryFilter)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("warehouse.inventory-filter")
        if !inventoryFilter.isEmpty {
          Button {
            inventoryFilter = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear item filter")
        }
      }
      Text(
        "Enter at least 3 letters or a type ID. Matching locations and characters open automatically."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var warehouseSummary: some View {
    Panel(title: mode == .allItems ? "All synchronized items" : "Production warehouse") {
      if inventoryCount == 0 {
        Label(
          emptyInventoryMessage.localizedUI,
          systemImage: "shippingbox"
        )
        .foregroundStyle(DesignTokens.caution)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 130, maximum: 220), alignment: .leading)],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          summaryMetric("Locations", value: warehouse.locations.count.formatted())
          summaryMetric("Characters", value: inventoryCount.formatted())
          summaryMetric("Item types", value: factualQuantities.count.formatted())
          summaryMetric("Units", value: totalUnits.formatted())
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
        Text(summaryExplanation.localizedUI)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if mode == .productionWarehouse {
        Label(
          "Corporation hangars are not synchronized yet. Their state is therefore unavailable, not empty; this view currently contains personal character assets only.",
          systemImage: "building.2.crop.circle"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
      DisclosureGroup {
        Text(
          "The storage position is the raw ESI location flag: it describes where EVE placed an item inside its parent inventory. It is not an access permission and does not change the counted quantity. Hangar means the personal item hangar; AutoFit normally marks an item inside a container; Unlocked or Locked describes the locking state inside an audit-log container. Other values identify cargo holds, fitting slots or specialized bays."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.top, DesignTokens.spacingXS)
      } label: {
        Label("What does storage position mean?", systemImage: "info.circle")
      }
    }
  }

  private var targetStockPanel: some View {
    Panel(title: "Minimum stock & alarms") {
      Text(
        "Set the minimum quantity that should remain across the configured production locations. The planner uses only stock above this minimum. A missing quantity is the active replenishment alarm."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      HStack(alignment: .top, spacing: DesignTokens.spacingSM) {
        WarehouseItemSearchField(selection: $selectedTargetItem)
          .accessibilityIdentifier("warehouse.target.item-search")
        TextField(
          "Target quantity",
          value: $targetQuantity,
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 150)
        .accessibilityIdentifier("warehouse.target.quantity")
        Button("Add or update") {
          saveSelectedTarget()
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedTargetItem == nil || targetQuantity < 0)
      }

      if let targetError {
        Label(targetError, systemImage: "xmark.octagon.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
      }

      if stockTargets.isEmpty {
        Text("No minimum quantities or stock alarms configured.")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        let alarmCount = stockTargets.filter {
          stockLine(typeID: $0.typeID).missingToTarget > 0
        }.count
        let alarmMessage =
          alarmCount == 0
          ? "All configured minimum quantities are covered.".localizedUI
          : AppLocalization.currentLanguage == .german
            ? "\(alarmCount) Mindestbestand-\(alarmCount == 1 ? "Alarm ist" : "Alarme sind") aktiv."
            : "\(alarmCount) minimum-stock \(alarmCount == 1 ? "alarm is" : "alarms are") active."
        Label(
          alarmMessage,
          systemImage: alarmCount == 0
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(
          alarmCount == 0 ? DesignTokens.positive : DesignTokens.caution
        )
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
              onCommit: { quantity in
                saveMinimum(
                  typeID: target.typeID,
                  typeName: target.typeName,
                  quantity: quantity
                )
              },
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
        if visibleLocations.isEmpty {
          Label(
            "No stored items match this filter.",
            systemImage: "magnifyingglass"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        } else {
          ForEach(visibleLocations) { location in
            warehouseLocation(location)
          }
        }
      }
    }
  }

  private func warehouseLocation(
    _ location: AssetWarehouseLocation
  ) -> some View {
    let isExpanded = expandedLocationIDs.contains(location.id)
    let displayedOwners = visibleOwners(in: location)
    return VStack(alignment: .leading, spacing: 0) {
      FullWidthDisclosureButton(
        isExpanded: isExpanded,
        action: {
          if isExpanded {
            expandedLocationIDs.remove(location.id)
          } else {
            expandedLocationIDs.insert(location.id)
          }
        }
      ) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
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
          ForEach(displayedOwners) { owner in
            FullWidthDisclosure(
              isExpanded: ownerExpansionBinding(
                locationID: location.id,
                ownerID: owner.ownerID
              )
            ) {
              HStack {
                Text(owner.ownerName)
                  .font(.subheadline.weight(.semibold))
                freshnessBadge(owner.state)
                Spacer()
                Text(
                  ownerSummary(
                    owner,
                    locationID: location.id
                  )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary)
              }
            } content: {
              ownerContents(owner, locationID: location.id)
                .padding(.top, DesignTokens.spacingSM)
            }
            .accessibilityIdentifier(
              "warehouse.location.\(location.id).owner.\(owner.ownerID)"
            )
            if owner.id != displayedOwners.last?.id {
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

  private func ownerExpansionBinding(
    locationID: Int64,
    ownerID: Int64
  ) -> Binding<Bool> {
    let key = ownerRowsKey(locationID: locationID, ownerID: ownerID)
    return Binding(
      get: { expandedOwnerKeys.contains(key) },
      set: { isExpanded in
        if isExpanded {
          expandedOwnerKeys.insert(key)
        } else {
          expandedOwnerKeys.remove(key)
        }
      }
    )
  }

  private func ownerContents(
    _ owner: AssetWarehouseOwner,
    locationID: Int64
  ) -> some View {
    let key = ownerRowsKey(
      locationID: locationID,
      ownerID: owner.ownerID
    )
    let sections = ownerSectionsByKey[key] ?? []
    let displayedSections: [AssetWarehouseOwnerContentSection] =
      sections.compactMap { section -> AssetWarehouseOwnerContentSection? in
        let rows =
          activeInventoryFilter == nil
          ? section.rows : section.rows.filter(rowMatchesInventoryFilter)
        guard !rows.isEmpty else { return nil }
        return AssetWarehouseOwnerContentSection(
          title: section.title,
          rows: rows
        )
      }
    let targets = targetQuantities
    return VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      ownerContentHeader
      ForEach(displayedSections) { section in
        if let title = section.title {
          HStack {
            Text(title.localizedUI)
              .font(.caption.weight(.semibold))
              .foregroundStyle(DesignTokens.accent)
            Spacer()
            Text(sectionSummary(section))
              .font(.caption2.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
          .padding(.top, DesignTokens.spacingXS)
        }
        ownerContentRows(section.rows, targets: targets)
      }
    }
    .font(.caption)
  }

  private var ownerContentHeader: some View {
    LazyVGrid(
      columns: ownerContentColumns,
      alignment: .leading,
      spacing: 7
    ) {
      Text("Item")
      Text("Quantity")
      Text("Storage position")
      if mode == .productionWarehouse {
        Text("Minimum")
      }
    }
    .font(.caption.bold())
    .foregroundStyle(DesignTokens.textSecondary)
  }

  private func ownerContentRows(
    _ rows: [AssetWarehouseOwnerContentLine],
    targets: [Int64: Int64]
  ) -> some View {
    LazyVGrid(
      columns: ownerContentColumns,
      alignment: .leading,
      spacing: 7
    ) {
      ForEach(rows) { row in
        Text(typeName(row.typeID))
          .lineLimit(2)
        Text(row.quantity.formatted())
          .font(.body.monospacedDigit())
        inventoryFlagView(row.locationFlag)
        if mode == .productionWarehouse {
          let resolvedName = typeNames[row.typeID]
          WarehouseMinimumEditor(
            currentValue: targets[row.typeID, default: 0]
          ) { quantity in
            guard let resolvedName else {
              targetError =
                "The item name is unavailable in the active SDE catalog."
              return
            }
            saveMinimum(
              typeID: row.typeID,
              typeName: resolvedName,
              quantity: quantity
            )
          }
          .id("\(row.typeID)-\(targets[row.typeID, default: 0])")
          .disabled(resolvedName == nil)
        }
      }
    }
  }

  private var ownerContentColumns: [GridItem] {
    var columns = [
      GridItem(.flexible(minimum: 180), alignment: .leading),
      GridItem(.fixed(90), alignment: .trailing),
      GridItem(.flexible(minimum: 145), alignment: .leading),
    ]
    if mode == .productionWarehouse {
      columns.append(GridItem(.fixed(105), alignment: .trailing))
    }
    return columns
  }

  private func inventoryFlagView(_ flag: String) -> some View {
    let displayName = inventoryFlagDisplayName(flag)
    return VStack(alignment: .leading, spacing: 1) {
      Text(displayName)
      if displayName != flag {
        Text(flag)
          .font(.caption2.monospaced())
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func inventoryFlagDisplayName(_ flag: String) -> String {
    switch flag {
    case "Hangar": "Personal hangar".localizedUI
    case "AutoFit": "Inside a container".localizedUI
    case "Unlocked": "Unlocked container contents".localizedUI
    case "Locked": "Locked container contents".localizedUI
    case "Cargo": "Cargo hold".localizedUI
    case "DroneBay": "Drone bay".localizedUI
    case "FleetHangar": "Fleet hangar".localizedUI
    case "Deliveries": "Deliveries".localizedUI
    default: flag
    }
  }

  private var inventoryOrganization: AssetInventoryOrganization {
    AssetInventoryOrganization(rawValue: inventoryOrganizationRawValue)
      ?? .alphabetical
  }

  private var inventoryOrganizationBinding: Binding<AssetInventoryOrganization> {
    Binding(
      get: { inventoryOrganization },
      set: { inventoryOrganizationRawValue = $0.rawValue }
    )
  }

  private func organizationLabel(
    _ organization: AssetInventoryOrganization
  ) -> String {
    switch organization {
    case .alphabetical: "Alphabetical"
    case .group: "Group"
    case .mainGroup: "Main group"
    }
  }

  private func sectionSummary(
    _ section: AssetWarehouseOwnerContentSection
  ) -> String {
    let typeCount = Set(section.rows.map(\.typeID)).count
    let units = section.rows.reduce(0) {
      AssetWarehouse.saturatedAdd($0, $1.quantity)
    }
    return
      "\(typeCount) \("types".localizedUI) · \(units.formatted()) \("items".localizedUI)"
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

  private var viewTitle: String {
    switch mode {
    case .allItems: "All items"
    case .productionWarehouse: "Warehouse"
    }
  }

  private var viewDescription: String {
    switch mode {
    case .allItems:
      "All synchronized personal assets at every known location. Click a location to show characters and contents."
    case .productionWarehouse:
      "Production materials from all synchronized characters at the exact facilities linked in Profile. Finished ships and everything fitted to or stored inside them are excluded."
    }
  }

  private var emptyInventoryMessage: String {
    switch mode {
    case .allItems:
      "No stored asset snapshots are available. Open Characters and synchronize the connected characters."
    case .productionWarehouse:
      if runtime.productionBasis.structures.compactMap(\.structureID).isEmpty {
        "No exact production facility is linked. Open Profile and select the station or player structure used for production."
      } else {
        "No personal production materials were found at the linked production facilities. Synchronize the connected characters to refresh this state."
      }
    }
  }

  private var summaryExplanation: String {
    switch mode {
    case .allItems:
      "This inventory is factual and includes every synchronized item, including finished ships. It is not used directly as planner stock."
    case .productionWarehouse:
      "The planner can allocate these factual quantities across all synchronized characters. Configured minimum quantities remain protected."
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
    if activeInventoryFilter == nil {
      let characters =
        location.owners.count == 1
        ? "character".localizedUI : "characters".localizedUI
      return
        "\(location.owners.count) \(characters) · \(location.totalUnits.formatted()) \("items".localizedUI)"
    }
    let displayedOwners = visibleOwners(in: location)
    let displayedRows = displayedOwners.flatMap {
      visibleRows(locationID: location.id, ownerID: $0.ownerID)
    }
    let characters =
      displayedOwners.count == 1
      ? "character".localizedUI : "characters".localizedUI
    return
      "\(displayedOwners.count) \(characters) · \(displayedRows.reduce(0) { AssetWarehouse.saturatedAdd($0, $1.quantity) }.formatted()) \("items".localizedUI)"
  }

  private func ownerSummary(
    _ owner: AssetWarehouseOwner,
    locationID: Int64
  ) -> String {
    if activeInventoryFilter == nil {
      return
        "\(Set(owner.items.map(\.typeID)).count) \("types".localizedUI) · \(owner.totalUnits.formatted()) \("items".localizedUI)"
    }
    let rows = visibleRows(locationID: locationID, ownerID: owner.ownerID)
    let units = rows.reduce(0) {
      AssetWarehouse.saturatedAdd($0, $1.quantity)
    }
    return
      "\(Set(rows.map(\.typeID)).count) \("types".localizedUI) · \(units.formatted()) \("items".localizedUI)"
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

  private func ownerRowsKey(
    locationID: Int64,
    ownerID: Int64
  ) -> AssetWarehouseOwnerContentKey {
    AssetWarehouseOwnerContentKey(
      locationID: locationID,
      ownerID: ownerID
    )
  }

  private var normalizedInventoryFilter: String {
    inventoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var activeInventoryFilter: String? {
    let accepted = normalizedInventoryFilter
    guard accepted.count >= 3 || Int64(accepted) != nil else { return nil }
    return accepted
  }

  private var visibleLocations: [AssetWarehouseLocation] {
    guard activeInventoryFilter != nil else {
      return warehouse.locations
    }
    return warehouse.locations.filter {
      !visibleOwners(in: $0).isEmpty
    }
  }

  private func visibleOwners(
    in location: AssetWarehouseLocation
  ) -> [AssetWarehouseOwner] {
    guard activeInventoryFilter != nil else {
      return location.owners
    }
    return location.owners.filter {
      !visibleRows(
        locationID: location.id,
        ownerID: $0.ownerID
      ).isEmpty
    }
  }

  private func visibleRows(
    locationID: Int64,
    ownerID: Int64
  ) -> [AssetWarehouseOwnerContentLine] {
    let rows = ownerRowsByKey[
      ownerRowsKey(locationID: locationID, ownerID: ownerID),
      default: []
    ]
    guard activeInventoryFilter != nil else { return rows }
    return rows.filter(rowMatchesInventoryFilter)
  }

  private func rowMatchesInventoryFilter(
    _ row: AssetWarehouseOwnerContentLine
  ) -> Bool {
    guard let accepted = activeInventoryFilter else { return true }
    if let typeID = Int64(accepted) {
      return row.typeID == typeID
    }
    return typeName(row.typeID).localizedCaseInsensitiveContains(accepted)
  }

  private func expandFilteredResults() {
    guard activeInventoryFilter != nil else { return }
    for location in visibleLocations {
      expandedLocationIDs.insert(location.id)
      for owner in visibleOwners(in: location) {
        expandedOwnerKeys.insert(
          ownerRowsKey(
            locationID: location.id,
            ownerID: owner.ownerID
          )
        )
      }
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
    let characterPart = characters.map { character in
      [
        String(character.characterID),
        character.characterName,
        String(character.assetSnapshot?.count ?? 0),
        String(character.lastSyncAt?.timeIntervalSince1970 ?? 0),
      ].joined(separator: ":")
    }
    .joined(separator: "|")
    let productionPart = runtime.productionBasis.structures.map {
      "\($0.id.uuidString):\($0.structureID ?? 0)"
    }.sorted().joined(separator: "|")
    return "\(mode)|\(characterPart)|\(productionPart)"
  }

  private var nameResolutionIdentity: String {
    let snapshotPart = warehouse.snapshotIDs.map(\.uuidString)
      .sorted()
      .joined(separator: ",")
    let targetPart = stockTargets.map(\.typeID).sorted()
      .map(String.init).joined(separator: ",")
    let typePart = factualQuantities.keys.sorted()
      .map(String.init).joined(separator: ",")
    return snapshotPart + "|" + targetPart + "|" + typePart
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
    let visible: PreparedAssetWarehouse
    switch mode {
    case .allItems:
      visible = prepared
    case .productionWarehouse:
      visible = await runtime.prepareProductionWarehouse(from: prepared)
    }
    guard !Task.isCancelled else { return }
    let visibleWarehouse = visible.warehouse
    let preparedRows = await Task.detached(priority: .userInitiated) {
      visibleWarehouse.groupedOwnerContents()
    }.value
    guard !Task.isCancelled else { return }
    warehouse = visible.warehouse
    inventoryCount = visible.inventoryCount
    factualQuantities = visible.factualQuantities
    totalUnits = visible.totalUnits
    ownerRowsByKey = preparedRows
    await organizeOwnerRows()
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
    async let resolvedClassifications =
      runtime.resolveAssetTypeClassifications(typeIDs)
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
    let acceptedTypeNames = await resolvedTypes
    typeNames = acceptedTypeNames
    typeClassifications = await resolvedClassifications
    locationNames = await resolvedLocations.value ?? [:]
    await organizeOwnerRows()
    expandFilteredResults()
  }

  private func organizeOwnerRows() async {
    let acceptedOrganization = inventoryOrganization
    let acceptedRows = ownerRowsByKey
    let acceptedMetadata = typeGroupingMetadata
    let organized = await OwnerContentRowProjection.organized(
      acceptedRows,
      metadata: acceptedMetadata,
      organization: acceptedOrganization
    )
    guard !Task.isCancelled,
      acceptedOrganization == inventoryOrganization,
      acceptedRows == ownerRowsByKey
    else { return }
    ownerSectionsByKey = organized
  }

  private var typeGroupingMetadata: [Int64: AssetTypeGroupingMetadata] {
    Dictionary(
      uniqueKeysWithValues: typeNames.map { typeID, typeName in
        let classification = typeClassifications[typeID]
        return (
          typeID,
          AssetTypeGroupingMetadata(
            typeID: typeID,
            typeName: typeName,
            categoryName: classification?.categoryName,
            groupName: classification?.groupName
          )
        )
      }
    )
  }

  private func saveSelectedTarget() {
    targetError = nil
    guard let selectedTargetItem else { return }
    guard targetQuantity >= 0 else {
      targetError = "The target quantity must not be negative."
      return
    }
    saveMinimum(
      typeID: selectedTargetItem.id,
      typeName: selectedTargetItem.name,
      quantity: targetQuantity
    )
    if targetError == nil {
      targetQuantity = 0
    }
  }

  private func saveMinimum(
    typeID: Int64,
    typeName: String,
    quantity: Int64
  ) {
    targetError = nil
    let acceptedQuantity = max(0, quantity)
    let existing = stockTargets.first { $0.typeID == typeID }
    if acceptedQuantity == 0 {
      if let existing {
        modelContext.delete(existing)
      } else {
        return
      }
    } else if let existing {
      existing.typeName = typeName
      existing.targetQuantity = acceptedQuantity
      existing.updatedAt = .now
    } else {
      modelContext.insert(
        StoredStockTarget(
          typeID: typeID,
          typeName: typeName,
          targetQuantity: acceptedQuantity
        )
      )
      typeNames[typeID] = typeName
    }
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
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

private enum OwnerContentRowProjection {
  static func organized(
    _ rowsByKey: [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentLine]],
    metadata: [Int64: AssetTypeGroupingMetadata],
    organization: AssetInventoryOrganization
  ) async -> [AssetWarehouseOwnerContentKey: [AssetWarehouseOwnerContentSection]] {
    await Task.detached(priority: .userInitiated) {
      rowsByKey.mapValues { rows in
        AssetWarehouseContentOrganizer.sections(
          rows: rows,
          metadata: metadata,
          organization: organization
        )
      }
    }.value
  }
}

private struct StockTargetEditorRow: View {
  let target: StoredStockTarget
  let stock: WarehouseStockLine
  let onCommit: (Int64) -> Void
  let onDelete: () -> Void

  var body: some View {
    GridRow {
      Text(target.typeName)
      Text(stock.factualQuantity.formatted())
        .font(.body.monospacedDigit())
      WarehouseMinimumEditor(
        currentValue: target.targetQuantity,
        onCommit: onCommit
      )
      .id("target-\(target.typeID)-\(target.targetQuantity)")
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

private struct WarehouseMinimumEditor: View {
  let currentValue: Int64
  let onCommit: (Int64) -> Void

  @State private var draftValue: Int64
  @FocusState private var isFocused: Bool

  init(
    currentValue: Int64,
    onCommit: @escaping (Int64) -> Void
  ) {
    self.currentValue = max(0, currentValue)
    self.onCommit = onCommit
    _draftValue = State(initialValue: max(0, currentValue))
  }

  var body: some View {
    TextField("Minimum", value: $draftValue, format: .number)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .frame(width: 105)
      .focused($isFocused)
      .onSubmit {
        isFocused = false
      }
      .onChange(of: isFocused) { wasFocused, isFocused in
        if wasFocused, !isFocused {
          commit()
        }
      }
      .onChange(of: currentValue) { _, value in
        if !isFocused {
          draftValue = max(0, value)
        }
      }
      .accessibilityHint(
        "Saved after pressing Return or leaving the field".localizedUI
      )
  }

  private func commit() {
    let accepted = max(0, draftValue)
    draftValue = accepted
    guard accepted != currentValue else { return }
    onCommit(accepted)
  }
}

private struct WarehouseItemSearchField: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Binding var selection: ItemTypeSearchResult?

  @State private var query = ""
  @State private var results: [ItemTypeSearchResult] = []
  @State private var isSearching = false
  @State private var isShowingResults = false
  @State private var searchMessage: String?
  @State private var searchTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      TextField("Search item name", text: $query)
        .textFieldStyle(.roundedBorder)
        .onChange(of: query) { _, value in
          if selection?.name != value {
            selection = nil
          }
          scheduleSearch(value)
        }
        .popover(isPresented: $isShowingResults, arrowEdge: .bottom) {
          searchResults
        }
      HStack {
        if let selection {
          Label(selection.name, systemImage: "checkmark.circle.fill")
            .foregroundStyle(DesignTokens.positive)
        } else {
          let hint =
            query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
            ? "Enter at least 3 letters"
            : "Select the exact item from the SDE results"
          Label(
            hint.localizedUI,
            systemImage: "magnifyingglass"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        Text("Source: active SDE")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .font(.caption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onDisappear {
      searchTask?.cancel()
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      if isSearching {
        ProgressView("Searching SDE…")
      } else if let searchMessage {
        Label(searchMessage.localizedUI, systemImage: "info.circle")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(results) { item in
              Button {
                selection = item
                query = item.name
                isShowingResults = false
              } label: {
                HStack {
                  Text(item.name)
                  Spacer()
                  Text(String(item.id))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignTokens.spacingSM)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              if item.id != results.last?.id {
                Divider()
              }
            }
          }
        }
      }
    }
    .padding(DesignTokens.spacingMD)
    .frame(
      width: 640,
      height: 460,
      alignment: .topLeading
    )
  }

  private func scheduleSearch(_ value: String) {
    searchTask?.cancel()
    results = []
    searchMessage = nil
    let accepted = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3, selection?.name != accepted else {
      isSearching = false
      isShowingResults = false
      return
    }
    isSearching = true
    isShowingResults = true
    searchTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(220))
        let found = try await runtime.searchAssetTypes(matching: accepted)
        try Task.checkCancellation()
        results = found
        isSearching = false
        searchMessage = found.isEmpty ? "No matching published items." : nil
      } catch is CancellationError {
        return
      } catch {
        isSearching = false
        searchMessage = "SDE item search is currently unavailable."
      }
    }
  }
}
