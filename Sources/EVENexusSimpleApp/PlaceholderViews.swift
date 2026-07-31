import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

struct PlannerView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<StoredPlan> { $0.isActive })
  private var activePlans: [StoredPlan]
  @Query(
    filter: #Predicate<StoredPlannerDraft> {
      $0.key == "primary"
    })
  private var plannerDrafts: [StoredPlannerDraft]
  @Query(sort: \StoredProductionRecord.completedAt, order: .reverse)
  private var productionRecords: [StoredProductionRecord]
  @Query(sort: \StoredProductionOverviewRow.recordedAt, order: .reverse)
  private var productionOverviewRows: [StoredProductionOverviewRow]
  @Query(sort: \StoredCharacter.characterName)
  private var storedCharacters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]
  @State private var input = ""
  @State private var manualStockInput = ""
  @State private var parseResult = ProductionInputParser.parse("")
  @State private var areWarningsExpanded = false
  @State private var hasRestoredState = false
  @State private var persistenceMessage: String?
  @State private var persistenceError: String?
  @State private var shoppingListCopyStatus: ShoppingListCopyStatus?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("Production Planner")
          .font(.largeTitle.bold())
        Text(
          "One job per line: Product Want ME TE [BPC|BPO BlueprintCostISK]"
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Panel(title: "Produce") {
          TextEditor(text: $input)
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .frame(minHeight: DesignTokens.plannerInputMinimumHeight)
            .padding(DesignTokens.spacingSM)
            .background(DesignTokens.elevated)
            .clipShape(
              RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
            )
            .accessibilityLabel("Production jobs")
            .accessibilityIdentifier("planner.input")
          HStack {
            Button("Validate") {
              parseResult = ProductionInputParser.parse(input)
            }
            Button("Calculate") {
              Task {
                guard runtime.isPlannerConfigurationReady else { return }
                persistDraft()
                await runtime.calculate(
                  input: input,
                  manualStockInput: manualStockInput,
                  existingReservations: activeReservations,
                  assetInventories: assetInventories,
                  stockTargets: targetQuantities
                )
                guard runtime.errorMessage == nil, let plan = runtime.plan
                else { return }
                saveActivePlan(plan)
              }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(
              !parseResult.isValid || runtime.isWorking
                || !runtime.isPlannerConfigurationReady
            )
            Spacer()
            if runtime.isWorking {
              ProgressView().controlSize(.small)
            }
            Text("\(parseResult.requests.count) valid products")
              .font(.callout.monospacedDigit())
          }
          Toggle(
            "Use combined warehouse from all synchronized characters",
            isOn: $runtime.warehouseStockEnabled
          )
          .help(
            "Uses every stored character asset snapshot. Configured target quantities remain protected and are not allocated to this plan."
          )
          DisclosureGroup("Manual stock") {
            TextEditor(text: $manualStockInput)
              .font(.body.monospaced())
              .frame(minHeight: DesignTokens.stockInputMinimumHeight)
              .padding(DesignTokens.spacingSM)
              .background(DesignTokens.elevated)
              .clipShape(
                RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
              )
            Text(
              "One line per source-marked quantity: Item name | Quantity. Manual stock takes precedence over the combined warehouse."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        RecentProductionsView(
          rows: Array(productionOverviewRows.prefix(5))
        )
        if !parseResult.errors.isEmpty {
          Panel(title: "Input errors") {
            ForEach(parseResult.errors) { error in
              Label(
                "Line \(error.lineNumber): \(error.message)",
                systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(DesignTokens.negative)
            }
          }
        }
        if let error = runtime.errorMessage {
          Panel(title: "Calculation stopped") {
            Label(error, systemImage: "xmark.octagon.fill")
              .foregroundStyle(DesignTokens.negative)
          }
        }
        if let persistenceError {
          Panel(title: "Local storage stopped") {
            Label(persistenceError, systemImage: "externaldrive.badge.xmark")
              .foregroundStyle(DesignTokens.negative)
          }
        }
        if let persistenceMessage {
          Label(persistenceMessage, systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(DesignTokens.positive)
        }
        if let plan = runtime.plan {
          resultView(plan)
        } else {
          Panel(title: "Plan readiness") {
            Label(
              runtime.isPlannerConfigurationReady
                ? "Install an SDE catalog. Character assets are optional and are never included without an explicit character and location selection."
                : "Loading the saved production configuration and installation-cost inputs…",
              systemImage:
                runtime.isPlannerConfigurationReady
                ? "info.circle" : "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(DesignTokens.textSecondary)
          }
        }
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Planner")
    .onAppear {
      restoreStateIfNeeded()
      parseResult = ProductionInputParser.parse(input)
    }
    .onDisappear {
      persistDraft(reportErrors: false)
    }
    .onChange(of: input) {
      parseResult = ProductionInputParser.parse(input)
      persistenceMessage = nil
      shoppingListCopyStatus = nil
    }
  }

  @ViewBuilder
  private func resultView(_ plan: IndustryPlanSnapshot) -> some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(minimum: 270),
          alignment: .top
        )
      ],
      alignment: .leading,
      spacing: DesignTokens.spacingMD
    ) {
      Panel(title: "Costs") {
        metric("Materials", plan.materialCost)
        metric(
          "BPC/BPO",
          plan.costBreakdown?.blueprintCosts?.total
        )
        metric(
          "System cost index",
          plan.costBreakdown?.systemIndexCost
        )
        metric("Installation", plan.installationCost)
        metric(
          "Logistics",
          plan.costBreakdown.flatMap {
            $0.logistics?.total
              ?? ($0.totalProductionCost == nil ? nil : 0)
          }
        )
        Divider()
        metric(
          "Total",
          plan.costBreakdown?.totalProductionCost
            ?? plan.materialCost.flatMap { materialCost in
              plan.installationCost.map { materialCost + $0 }
            }
        )
        Text(
          "System-index cost is part of Installation. Sales taxes and broker fees reduce revenue and are shown separately."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
      Panel(title: "Taxes & fees") {
        metric("Facility tax", plan.costBreakdown?.facilityTax)
        metric("SCC surcharge", plan.costBreakdown?.sccSurcharge)
        metric("Alpha surcharge", plan.costBreakdown?.alphaSurcharge)
        Divider()
        metric("Immediate sales tax", plan.immediateSale.salesTax)
        metric("Immediate broker fee", plan.immediateSale.brokerFee)
        metric("Listed sales tax", plan.listedSale.salesTax)
        metric("Listed broker fee", plan.listedSale.brokerFee)
      }
      Panel(title: "Immediate sale") {
        metric("Gross revenue", plan.immediateSale.grossRevenue)
        metric("Net revenue", plan.immediateSale.grossOrNetRevenue)
        metric("Profit", plan.immediateSale.profit)
        percent("Margin", plan.immediateSale.margin)
        percent("ROI", plan.immediateSale.roi)
      }
      Panel(title: "Listed sale") {
        metric("Gross revenue", plan.listedSale.grossRevenue)
        metric("Net revenue", plan.listedSale.grossOrNetRevenue)
        metric("Profit", plan.listedSale.profit)
        percent("Margin", plan.listedSale.margin)
        percent("ROI", plan.listedSale.roi)
      }
    }
    if let logistics = plan.costBreakdown?.logistics {
      logisticsPanel(logistics)
    }
    if let blueprintCosts = plan.costBreakdown?.blueprintCosts {
      blueprintCostPanel(blueprintCosts, requests: plan.requests)
    }
    materialPanel(
      title: "Raw materials",
      description:
        "Only non-producible inputs are shown here, grouped by their SDE source category.",
      sections: materialSections(
        for: plan.materials.filter { !$0.isProducedMaterial },
        fallback: "Other raw materials"
      )
    )
    materialPanel(
      title: "Produced materials & intermediates",
      description:
        "Items with a manufacturing or reaction recipe are kept separate from raw materials.",
      sections: materialSections(
        for: plan.materials.filter(\.isProducedMaterial),
        fallback: "Other produced materials"
      )
    )
    shoppingListPanel(plan)
    Panel(title: "Jobs and provenance") {
      LabeledContent("Jobs", value: "\(plan.jobs.count)")
      LabeledContent(
        "Total job time",
        value: Duration.seconds(plan.totalJobSeconds).formatted()
      )
      LabeledContent(
        "SDE build",
        value: String(plan.provenance.sdeBuild)
      )
      LabeledContent(
        "ESI compatibility",
        value: plan.provenance.esiCompatibilityDate
      )
      LabeledContent("Rule version", value: plan.provenance.ruleVersion)
      Text(
        "Every successful calculation is saved automatically as the last active plan."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      Button {
        recordProduction(plan)
      } label: {
        Label("Record production", systemImage: "book.closed.fill")
      }
      .buttonStyle(.borderedProminent)
    }
    if !plan.warnings.isEmpty {
      Panel(title: "Warnings") {
        DisclosureGroup(isExpanded: $areWarningsExpanded) {
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            ForEach(plan.warnings) { warning in
              Label(warning.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(
                  warning.severity == .blocking
                    ? DesignTokens.negative
                    : DesignTokens.caution
                )
            }
          }
          .padding(.top, DesignTokens.spacingSM)
        } label: {
          Text(
            "\(plan.warnings.count) \(plan.warnings.count == 1 ? "warning" : "warnings")"
          )
        }
        .accessibilityIdentifier("planner.warnings.disclosure")
      }
    }
  }

  private func metric(_ label: String, _ value: Double?) -> some View {
    LabeledContent(label) {
      Text(formatISK(value))
        .font(.body.monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
    }
  }

  private func percent(_ label: String, _ value: Double?) -> some View {
    LabeledContent(
      label,
      value: value.map {
        $0.formatted(.percent.precision(.fractionLength(2)))
      } ?? "Unavailable"
    )
    .fontDesign(.monospaced)
  }

  private func logisticsPanel(
    _ logistics: LogisticsCostBreakdown
  ) -> some View {
    Panel(title: "Logistics breakdown") {
      ForEach(logistics.legs) { leg in
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Text(
            "\(leg.kind.displayName) · Contract \(leg.contractNumber ?? 1) of \(leg.contractCount ?? 1)"
          )
          .font(.headline)
          Text("\(leg.origin) → \(leg.destination)")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          LabeledContent("Cargo volume") {
            Text(
              leg.cargoVolumeM3.formatted(
                .number.precision(.fractionLength(0...2))
              ) + " m³"
            )
            .font(.body.monospacedDigit())
          }
          metric("Accurate collateral", leg.collateral)
          metric("Volume charge", leg.volumeCharge)
          metric("0.5% collateral charge", leg.collateralCharge)
          LabeledContent("Charged by") {
            Text(
              leg.chargedBy == .volume ? "Cargo volume" : "Collateral"
            )
          }
          metric("Before rounding", leg.unroundedCharge)
          metric("Rounded contract", leg.roundedCharge)
        }
        .padding(.vertical, DesignTokens.spacingSM)
        Divider()
      }
      metric("Total logistics", logistics.total)
      Text(
        "Maximum \(logistics.maximumContractVolumeM3.formatted()) m³ per contract · oversized routes are split automatically · each contract is rounded up in \(formatISK(logistics.roundingIncrement)) steps · \(logistics.ruleVersion)"
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func blueprintCostPanel(
    _ blueprintCosts: BlueprintCostBreakdown,
    requests: [ProductionRequestLine]
  ) -> some View {
    Panel(title: "BPC/BPO costs") {
      ForEach(blueprintCosts.entries) { entry in
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          HStack {
            Text(entry.productName)
              .font(.headline)
            Spacer()
            Text(entry.kind.rawValue)
              .font(.caption.bold())
              .foregroundStyle(DesignTokens.highlight)
          }
          metric("Entered cost", entry.amount)
          Text(entry.treatment)
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, DesignTokens.spacingXS)
        Divider()
      }
      if !blueprintCosts.requestsWithoutEnteredCost.isEmpty {
        let names =
          requests
          .filter {
            blueprintCosts.requestsWithoutEnteredCost.contains($0.id)
          }
          .map(\.productName)
          .joined(separator: ", ")
        Label(
          "No blueprint cost entered for: \(names). These costs are not included.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
      metric("Total BPC/BPO cost", blueprintCosts.total)
      Text(
        "BPC is treated as a consumed copy acquisition cost. For a reusable BPO, enter only the cost share you want to allocate to this production line."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func number(_ value: Int64) -> some View {
    Text(value.formatted())
      .font(.body.monospacedDigit())
  }

  @ViewBuilder
  private func materialPanel(
    title: String,
    description: String,
    sections: [PlannerMaterialSection]
  ) -> some View {
    if !sections.isEmpty {
      Panel(title: title) {
        Text(description)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        ForEach(sections) { section in
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text(section.name)
              .font(.headline)
            materialGrid(section.materials)
          }
          .padding(.top, DesignTokens.spacingSM)
        }
      }
    }
  }

  private func materialGrid(
    _ materials: [MaterialRequirement]
  ) -> some View {
    let factualQuantities = warehouseFactualQuantities
    let targets = targetQuantities
    return Grid(
      alignment: .leading,
      horizontalSpacing: 18,
      verticalSpacing: 8
    ) {
      GridRow {
        Text("Item")
        Text("Required")
        Text("Warehouse")
        Text("Target")
        Text("Used")
        Text("Still needed")
        Text("Produce")
        Text("Buy")
        Text("Jita cost")
      }
      .font(.caption.bold())
      .foregroundStyle(DesignTokens.textSecondary)
      Divider()
      ForEach(materials) { material in
        GridRow {
          Text(material.name)
          number(material.required)
          number(factualQuantities[material.typeID, default: 0])
          number(targets[material.typeID, default: 0])
          number(material.fromStock)
          number(max(0, material.required - material.fromStock))
          number(material.toProduce)
          number(material.toBuy)
          Text(formatISK(material.quote?.total))
            .font(.body.monospacedDigit())
            .foregroundStyle(DesignTokens.highlight)
        }
      }
    }
  }

  private func materialSections(
    for materials: [MaterialRequirement],
    fallback: String
  ) -> [PlannerMaterialSection] {
    Dictionary(grouping: materials) { material in
      material.sourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmpty
        ?? material.sourceCategory?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).nonEmpty
        ?? fallback
    }
    .map { name, materials in
      PlannerMaterialSection(
        name: name,
        materials: materials.sorted {
          $0.name.localizedCaseInsensitiveCompare($1.name)
            == .orderedAscending
        }
      )
    }
    .sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func shoppingListPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    let export = EVEMultibuyExport.make(from: plan.materials)
    return Panel(title: "EVE shopping list") {
      if export.itemCount == 0 {
        Label(
          "This plan has no materials to buy.",
          systemImage: "checkmark.circle"
        )
        .foregroundStyle(DesignTokens.textSecondary)
      } else {
        Text(
          "Copies \(export.itemCount) \(export.itemCount == 1 ? "item" : "items") in EVE Multibuy format. In EVE, open Multibuy and choose Import from Clipboard."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Button {
          copyShoppingList(export)
        } label: {
          Label("Copy for EVE Multibuy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("planner.shopping-list.copy")
      }
      if let shoppingListCopyStatus {
        Label(
          shoppingListCopyStatus.message,
          systemImage:
            shoppingListCopyStatus.isFailure
            ? "xmark.octagon.fill" : "checkmark.circle.fill"
        )
        .font(.callout)
        .foregroundStyle(
          shoppingListCopyStatus.isFailure
            ? DesignTokens.negative : DesignTokens.positive
        )
      }
    }
  }

  private func copyShoppingList(_ export: EVEMultibuyExport) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if pasteboard.setString(export.text, forType: .string) {
      shoppingListCopyStatus = .copied(itemCount: export.itemCount)
    } else {
      shoppingListCopyStatus = .failed
    }
  }

  private func formatISK(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return value.formatted(
      .currency(code: "ISK").precision(.fractionLength(0))
    )
  }

  private func restoreStateIfNeeded() {
    guard !hasRestoredState else { return }
    hasRestoredState = true
    let restored = PlannerPersistenceController.restore(
      draft: plannerDrafts.first,
      activePlans: activePlans,
      productionRecords: productionRecords
    )
    input = restored.input
    manualStockInput = restored.manualStockInput
    if runtime.plan == nil {
      runtime.plan = restored.plan
    }
  }

  private func persistDraft(reportErrors: Bool = true) {
    do {
      try PlannerPersistenceController.saveDraft(
        input: input,
        manualStockInput: manualStockInput,
        existingDraft: plannerDrafts.first,
        in: modelContext
      )
    } catch {
      if reportErrors {
        persistenceError = error.localizedDescription
      }
    }
  }

  private func saveActivePlan(_ plan: IndustryPlanSnapshot) {
    do {
      try PlannerPersistenceController.saveActivePlan(
        plan,
        input: input,
        activePlans: activePlans,
        in: modelContext
      )
      persistenceError = nil
    } catch {
      persistenceError = error.localizedDescription
    }
  }

  private func recordProduction(_ plan: IndustryPlanSnapshot) {
    do {
      persistDraft()
      let rows = try PlannerPersistenceController.recordProductionOverview(
        plan,
        productionBasis: runtime.productionBasis,
        existingRows: productionOverviewRows,
        in: modelContext
      )
      persistenceError = nil
      persistenceMessage =
        "\(rows.count) production \(rows.count == 1 ? "row" : "rows") recorded in the Production Overview."
    } catch {
      persistenceMessage = nil
      persistenceError = error.localizedDescription
    }
  }

  private var activeReservations: [StockAllocation] {
    activePlans.flatMap {
      (try? JSONDecoder().decode(
        IndustryPlanSnapshot.self,
        from: $0.snapshot
      ).stockAllocations) ?? []
    }
  }

  private var assetInventories: [AssetOwnerInventory] {
    storedCharacters.compactMap { character in
      guard let data = character.assetSnapshot,
        let sourced = try? JSONDecoder().decode(
          Sourced<AssetSnapshot>.self,
          from: data
        )
      else { return nil }
      return AssetOwnerInventory(
        ownerID: character.characterID,
        ownerName: character.characterName,
        assets: sourced
      )
    }
  }

  private var targetQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var warehouseFactualQuantities: [Int64: Int64] {
    AssetWarehouse(inventories: assetInventories).factualQuantities
  }
}

private struct PlannerMaterialSection: Identifiable {
  var id: String { name }
  let name: String
  let materials: [MaterialRequirement]
}

private enum ShoppingListCopyStatus {
  case copied(itemCount: Int)
  case failed

  var isFailure: Bool {
    if case .failed = self { return true }
    return false
  }

  var message: String {
    switch self {
    case .copied(let itemCount):
      "\(itemCount) \(itemCount == 1 ? "item" : "items") copied for EVE Multibuy."
    case .failed:
      "The shopping list could not be copied to the clipboard."
    }
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    isEmpty ? nil : self
  }
}

#if LEGACY_PROFILES
  private struct LegacyProfilesView: View {
    @EnvironmentObject private var runtime: RuntimeState
    @Environment(\.modelContext) private var modelContext
    @Query private var manufacturingProfiles: [StoredManufacturingProfile]
    @Query private var reactionProfiles: [StoredReactionProfile]

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          Text("Production Profiles").font(.largeTitle.bold())
          Panel(title: "Manufacturing") {
            TextField(
              "Profile name",
              text: $runtime.manufacturingProfile.name
            )
            TextField(
              "Structure",
              text: $runtime.manufacturingProfile.structureName
            )
            TextField(
              "Solar system ID",
              value: $runtime.manufacturingProfile.solarSystemID,
              format: .number
            )
            Picker(
              "Security",
              selection: $runtime.manufacturingProfile.securityBand
            ) {
              ForEach(SecurityBand.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
              }
            }
            Picker(
              "Clone",
              selection: $runtime.manufacturingProfile.cloneState
            ) {
              ForEach(CloneState.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
              }
            }
            HStack {
              Stepper(
                "Intermediate ME \(runtime.manufacturingProfile.defaultIntermediateME)",
                value: $runtime.manufacturingProfile.defaultIntermediateME,
                in: 0...10
              )
              Stepper(
                "TE \(runtime.manufacturingProfile.defaultIntermediateTE)",
                value: $runtime.manufacturingProfile.defaultIntermediateTE,
                in: 0...20
              )
            }
            TextField(
              "Facility tax",
              value: $runtime.manufacturingProfile.facilityTaxRate,
              format: .percent
            )
            TextField(
              "Effective material multiplier override",
              value: $runtime.manufacturingProfile
                .manualEffectiveMaterialMultiplier,
              format: .number
            )
            TextField(
              "Effective time multiplier override",
              value: $runtime.manufacturingProfile
                .manualEffectiveTimeMultiplier,
              format: .number
            )
            TextField(
              "Job cost multiplier override",
              value: $runtime.manufacturingProfile
                .manualEffectiveJobCostMultiplier,
              format: .number
            )
            TextField(
              "Effective sales tax",
              value: $runtime.manufacturingProfile.effectiveSalesTaxRate,
              format: .percent
            )
            TextField(
              "Effective broker fee",
              value: $runtime.manufacturingProfile.effectiveBrokerFeeRate,
              format: .percent
            )
            Button("Save manufacturing profile") {
              saveManufacturing()
            }
            Text("\(manufacturingProfiles.count) saved")
              .font(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
          Panel(title: "Reactions") {
            Toggle(
              "Enable reactions",
              isOn: Binding(
                get: { runtime.reactionProfile != nil },
                set: {
                  runtime.reactionProfile =
                    $0 ? ReactionProfile() : nil
                }
              )
            )
            if runtime.reactionProfile != nil {
              TextField(
                "Profile name",
                text: reactionBinding(\.name)
              )
              TextField(
                "Reactor",
                text: reactionBinding(\.structureName)
              )
              TextField(
                "Solar system ID",
                value: reactionBinding(\.solarSystemID),
                format: .number
              )
              Picker(
                "Security",
                selection: reactionBinding(\.securityBand)
              ) {
                ForEach(SecurityBand.allCases, id: \.self) {
                  Text($0.rawValue).tag($0)
                }
              }
              TextField(
                "Effective material multiplier override",
                value: reactionBinding(\.manualEffectiveMaterialMultiplier),
                format: .number
              )
              TextField(
                "Effective time multiplier override",
                value: reactionBinding(\.manualEffectiveTimeMultiplier),
                format: .number
              )
              TextField(
                "Job cost multiplier override",
                value: reactionBinding(\.manualEffectiveJobCostMultiplier),
                format: .number
              )
              Text(
                "Reaction ME/TE is intentionally unavailable. Unverified structure or rig modifiers block affected decisions."
              )
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
              Button("Save reaction profile") {
                saveReaction()
              }
            }
            Text("\(reactionProfiles.count) saved")
              .font(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        .padding(DesignTokens.spacingLG)
      }
      .navigationTitle("Profiles")
    }

    private func saveManufacturing() {
      let profile = runtime.manufacturingProfile
      guard let data = try? JSONEncoder().encode(profile) else { return }
      modelContext.insert(
        StoredManufacturingProfile(
          id: profile.id,
          name: profile.name,
          encodedProfile: data
        )
      )
      try? modelContext.save()
    }

    private func saveReaction() {
      guard let profile = runtime.reactionProfile,
        let data = try? JSONEncoder().encode(profile)
      else { return }
      modelContext.insert(
        StoredReactionProfile(
          id: profile.id,
          name: profile.name,
          encodedProfile: data
        )
      )
      try? modelContext.save()
    }

    private func reactionBinding<Value>(
      _ keyPath: WritableKeyPath<ReactionProfile, Value>
    ) -> Binding<Value> {
      Binding(
        get: { runtime.reactionProfile![keyPath: keyPath] },
        set: { runtime.reactionProfile![keyPath: keyPath] = $0 }
      )
    }
  }
#endif

extension DomainWarningSeverity {
  var color: Color {
    switch self {
    case .information: DesignTokens.information
    case .warning: DesignTokens.caution
    case .blocking: DesignTokens.negative
    }
  }
}

struct CharactersView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query private var characters: [StoredCharacter]
  @Query private var settings: [AppSetting]
  @State private var isConnecting = false
  @State private var isSyncingAll = false
  @State private var selectedScopeCharacterID: Int64?
  @State private var disconnectCharacterID: Int64?
  @State private var batchMessage: String?
  @State private var localError: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("Characters").font(.largeTitle.bold())
        Panel(title: "EVE SSO") {
          if characters.isEmpty {
            ContentUnavailableView(
              "No characters",
              systemImage: "person.crop.circle.badge.plus",
              description: Text(
                "Configure the EVE client ID, then authorize each personal character with PKCE."
              )
            )
          } else {
            ForEach(characters) { character in
              VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                HStack {
                  Button {
                    toggleScopeDetails(for: character)
                  } label: {
                    HStack(spacing: DesignTokens.spacingSM) {
                      Image(
                        systemName:
                          selectedScopeCharacterID == character.characterID
                          ? "chevron.down" : "chevron.right"
                      )
                      .font(.caption.bold())
                      .frame(width: 12)
                      Image(systemName: "person.crop.circle.fill")
                      VStack(alignment: .leading, spacing: 2) {
                        Text(character.characterName)
                        Text(scopeStatus(for: character))
                          .font(.caption)
                          .foregroundStyle(
                            missingScopeCount(for: character) == 0
                              ? DesignTokens.positive
                              : DesignTokens.caution
                          )
                      }
                    }
                  }
                  .buttonStyle(.plain)
                  .contentShape(Rectangle())
                  .accessibilityLabel(
                    "Show loaded scopes for \(character.characterName)"
                  )
                  .accessibilityValue(
                    selectedScopeCharacterID == character.characterID
                      ? "Expanded" : "Collapsed"
                  )
                  Spacer()
                  Text(character.lastSyncAt?.formatted() ?? "Never synced")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                  Button("Sync") {
                    Task {
                      await sync(character)
                    }
                  }
                  .disabled(clientID.isEmpty || isBusy)
                  Button(role: .destructive) {
                    disconnectCharacterID = character.characterID
                  } label: {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.minus")
                      .labelStyle(.iconOnly)
                  }
                  .disabled(clientID.isEmpty || isBusy)
                  .help(
                    "Delete this character's refresh token and locally stored character snapshots."
                  )
                }
                if selectedScopeCharacterID == character.characterID {
                  scopeDetails(for: character)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
              }
              .padding(.vertical, DesignTokens.spacingXS)
              Divider()
            }
          }
          Divider()
          HStack(spacing: DesignTokens.spacingSM) {
            Button("Authorize or add character") {
              Task { await connect() }
            }
            .disabled(clientID.isEmpty || isBusy)
            .help(
              "Select any EVE character. The verified character ID automatically updates an existing character or adds a new one."
            )
            if !characters.isEmpty {
              Button {
                Task { await syncAll() }
              } label: {
                Label("Sync all", systemImage: "arrow.triangle.2.circlepath")
              }
              .disabled(clientID.isEmpty || isBusy)
            }
            if isConnecting {
              ProgressView().controlSize(.small)
              Text("Waiting for secure browser callback…")
                .foregroundStyle(DesignTokens.textSecondary)
            }
          }
          if let batchMessage {
            Text(batchMessage)
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
          }
          if clientID.isEmpty {
            Label(
              "Save the EVE application client ID in Data & Settings first.",
              systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(DesignTokens.caution)
          }
          if let localError {
            Text(localError).foregroundStyle(DesignTokens.negative)
          }
        }
        if let sync = runtime.lastCharacterSync {
          Panel(title: "Latest domain states") {
            sourceState("Skills", sync.capabilities.skills.state)
            sourceState("Standings", sync.capabilities.standings.state)
            sourceState("Blueprints", sync.blueprints.state)
            sourceState("Assets", sync.assets.state)
            sourceState("Industry jobs", sync.jobs.state)
            sourceState("Orders", sync.openOrders.state)
            sourceState("Wallet", sync.walletBalance.state)
          }
        }
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Characters")
    .confirmationDialog(
      disconnectDialogTitle,
      isPresented: Binding(
        get: { disconnectCharacterID != nil },
        set: { if !$0 { disconnectCharacterID = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Disconnect and delete local data", role: .destructive) {
        guard let characterID = disconnectCharacterID else { return }
        disconnectCharacterID = nil
        Task { await disconnect(characterID: characterID) }
      }
      Button("Cancel", role: .cancel) {
        disconnectCharacterID = nil
      }
    } message: {
      Text(
        "This deletes the local refresh token, authorization, wallet/capability/asset snapshots, and ESI sync metadata for this character. It does not revoke access on the EVE Online website and does not delete production records."
      )
    }
  }

  private var clientID: String {
    settings.first(where: { $0.key == "eve.clientID" })?.value ?? ""
  }

  private var isBusy: Bool {
    isConnecting || isSyncingAll
  }

  private var disconnectDialogTitle: String {
    guard let characterID = disconnectCharacterID,
      let character = characters.first(where: {
        $0.characterID == characterID
      })
    else {
      return "Disconnect character?"
    }
    return "Disconnect \(character.characterName)?"
  }

  private func toggleScopeDetails(for character: StoredCharacter) {
    withAnimation(.easeInOut(duration: 0.18)) {
      selectedScopeCharacterID =
        selectedScopeCharacterID == character.characterID
        ? nil : character.characterID
    }
  }

  @ViewBuilder
  private func scopeDetails(for character: StoredCharacter) -> some View {
    if let authorization = authorization(for: character) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        HStack {
          Text("Loaded scopes")
            .font(.subheadline.bold())
          Spacer()
          Text("\(authorization.sortedScopes.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(DesignTokens.textSecondary)
        }
        if authorization.sortedScopes.isEmpty {
          Label(
            "No scopes are stored for this character.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        } else {
          ForEach(authorization.sortedScopes, id: \.self) { scope in
            Label {
              Text(scope)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.positive)
            }
          }
        }
        Text(
          "Granted by EVE SSO \(authorization.authorizedAt.formatted(date: .abbreviated, time: .shortened))."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
      .padding(DesignTokens.spacingSM)
      .background(DesignTokens.elevated)
      .clipShape(
        RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel(
        "Loaded scopes for \(character.characterName)"
      )
    } else {
      Label(
        "The stored authorization snapshot could not be read.",
        systemImage: "xmark.octagon.fill"
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.negative)
    }
  }

  private func authorization(
    for character: StoredCharacter
  ) -> AuthorizationSnapshot? {
    try? JSONDecoder().decode(
      AuthorizationSnapshot.self,
      from: character.authorizationSnapshot
    )
  }

  private func connect() async {
    isConnecting = true
    localError = nil
    defer { isConnecting = false }
    do {
      let authorization = try await runtime.connectCharacter(
        clientID: clientID
      )
      let wasStored = characters.contains {
        $0.characterID == authorization.characterID
      }
      try upsert(authorization)
      batchMessage =
        wasStored
        ? "\(authorization.characterName) was reauthorized."
        : "\(authorization.characterName) was added."
    } catch {
      localError = userMessage(for: error)
    }
  }

  private func sync(_ character: StoredCharacter) async {
    localError = nil
    do {
      try await synchronize(character)
    } catch {
      localError = userMessage(for: error)
    }
  }

  private func disconnect(characterID: Int64) async {
    localError = nil
    guard
      let character = characters.first(where: {
        $0.characterID == characterID
      })
    else {
      return
    }
    let characterName = character.characterName
    do {
      try await runtime.disconnectCharacter(
        characterID: characterID,
        clientID: clientID
      )
      try modelContext.deleteESISnapshotMetadata(characterID: characterID)
      modelContext.delete(character)
      try modelContext.save()
      if selectedScopeCharacterID == characterID {
        selectedScopeCharacterID = nil
      }
      batchMessage =
        "\(characterName) was disconnected and its local character data was deleted."
    } catch {
      modelContext.rollback()
      localError =
        "The character could not be disconnected. No local database records were deleted. \(userMessage(for: error))"
    }
  }

  private func syncAll() async {
    isSyncingAll = true
    localError = nil
    var failures: [String] = []
    let ordered = characters.sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    defer {
      isSyncingAll = false
      batchMessage =
        failures.isEmpty
        ? "All \(ordered.count) characters were synchronized."
        : "\(ordered.count - failures.count) of \(ordered.count) characters were synchronized."
      if !failures.isEmpty {
        localError = failures.joined(separator: "\n")
      }
    }
    for (index, character) in ordered.enumerated() {
      batchMessage =
        "Synchronizing \(character.characterName) (\(index + 1)/\(ordered.count))…"
      do {
        try await synchronize(character)
      } catch {
        failures.append(
          "\(character.characterName): \(userMessage(for: error))"
        )
      }
    }
  }

  private func synchronize(_ character: StoredCharacter) async throws {
    let authorization = try JSONDecoder().decode(
      AuthorizationSnapshot.self,
      from: character.authorizationSnapshot
    )
    try await runtime.syncCharacter(
      authorization: authorization,
      clientID: clientID
    )
    try applyLatestSync(to: character)
    try modelContext.save()
  }

  private func upsert(_ authorization: AuthorizationSnapshot) throws {
    if let existing = characters.first(where: {
      $0.characterID == authorization.characterID
    }) {
      try update(existing, authorization: authorization)
      return
    }
    let character = StoredCharacter(
      characterID: authorization.characterID,
      characterName: authorization.characterName,
      authorizationSnapshot: try JSONEncoder().encode(authorization)
    )
    modelContext.insert(character)
    try applyLatestSync(to: character)
    try modelContext.save()
  }

  private func update(
    _ character: StoredCharacter,
    authorization: AuthorizationSnapshot
  ) throws {
    character.characterName = authorization.characterName
    character.authorizationSnapshot = try JSONEncoder().encode(
      authorization
    )
    try applyLatestSync(to: character)
    try modelContext.save()
  }

  private func applyLatestSync(to character: StoredCharacter) throws {
    character.capabilitySnapshot = try runtime.lastCharacterSync.map {
      try JSONEncoder().encode($0.capabilities)
    }
    character.assetSnapshot = try runtime.lastCharacterSync.map {
      try JSONEncoder().encode($0.assets)
    }
    character.walletBalanceSnapshot = try runtime.lastCharacterSync.map {
      try JSONEncoder().encode($0.walletBalance)
    }
    character.lastSyncAt = .now
    character.walletLastSyncAt =
      runtime.lastCharacterSync?.walletBalance.value == nil ? nil : .now
    try persistLatestSnapshotMetadata()
  }

  private func missingScopeCount(for character: StoredCharacter) -> Int {
    guard let authorization = authorization(for: character)
    else { return EVEScope.versionOne.count }
    return EVEScope.versionOne.subtracting(authorization.scopes).count
  }

  private func scopeStatus(for character: StoredCharacter) -> String {
    let missing = missingScopeCount(for: character)
    return missing == 0
      ? "Permissions current"
      : "\(missing) permission\(missing == 1 ? "" : "s") missing"
  }

  private func userMessage(for error: Error) -> String {
    if case AuthError.unexpectedCharacter(
      let expected,
      let received
    ) = error {
      return
        "The wrong EVE character was selected (expected \(expected), received \(received)). No token was saved."
    }
    return String(describing: error)
  }

  private func persistLatestSnapshotMetadata() throws {
    guard let snapshot = runtime.lastCharacterSync else { return }
    try insertMetadata(
      domain: "skills",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.capabilities.skills
    )
    try insertMetadata(
      domain: "standings",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.capabilities.standings
    )
    try insertMetadata(
      domain: "blueprints",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.blueprints
    )
    try insertMetadata(
      domain: "assets",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.assets
    )
    try insertMetadata(
      domain: "industry-jobs",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.jobs
    )
    try insertMetadata(
      domain: "open-orders",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.openOrders
    )
    try insertMetadata(
      domain: "order-history",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.orderHistory
    )
    try insertMetadata(
      domain: "wallet-balance",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.walletBalance
    )
    try insertMetadata(
      domain: "wallet-journal",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.walletJournal
    )
    try insertMetadata(
      domain: "wallet-transactions",
      characterID: snapshot.authorization.characterID,
      sourced: snapshot.walletTransactions
    )
  }

  private func insertMetadata<Value: Codable & Sendable>(
    domain: String,
    characterID: Int64,
    sourced: Sourced<Value>
  ) throws {
    try modelContext.upsertESISnapshotMetadata(
      characterID: characterID,
      domain: domain,
      freshness: sourced.state.rawValue,
      provider: sourced.source.provider,
      sourceVersion: sourced.source.version,
      sourceSnapshotID: sourced.source.snapshotID,
      capturedAt: sourced.source.capturedAt,
      diagnostics: sourced.diagnostics
    )
  }

  private func sourceState(
    _ title: String,
    _ state: DataFreshness
  ) -> some View {
    LabeledContent(title) {
      Text(state.rawValue.uppercased())
        .font(.caption.bold())
        .foregroundStyle(
          state == .fresh
            ? DesignTokens.positive
            : state == .partial || state == .stale
              ? DesignTokens.caution
              : DesignTokens.negative
        )
    }
  }
}

struct WalletView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query private var settings: [AppSetting]
  @State private var refreshingCharacterIDs: Set<Int64> = []
  @State private var refreshErrors: [Int64: String] = [:]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("Wallet").font(.largeTitle.bold())
        Text(
          "Personal wallet balances across all connected characters."
        )
        .foregroundStyle(DesignTokens.textSecondary)

        if characters.isEmpty {
          Panel(title: "Wallet overview") {
            ContentUnavailableView(
              "No connected characters",
              systemImage: "creditcard",
              description: Text(
                "Add a character under Characters before refreshing wallet balances."
              )
            )
          }
        } else {
          totalPanel
          characterPanel
        }

        if clientID.isEmpty, !characters.isEmpty {
          Label(
            "Save the EVE application client ID in Data & Settings before refreshing.",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(DesignTokens.caution)
        }
        ForEach(refreshErrors.keys.sorted(), id: \.self) { characterID in
          if let message = refreshErrors[characterID] {
            Label(message, systemImage: "xmark.octagon.fill")
              .foregroundStyle(DesignTokens.negative)
          }
        }
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Wallet")
  }

  private var totalPanel: some View {
    Panel(title: "Total wallet") {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text(
            portfolio.includedCharacterCount
              == portfolio.totalCharacterCount
              ? "Total balance"
              : "Available balance"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          Text(totalText)
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(DesignTokens.highlight)
            .accessibilityIdentifier("wallet.total")
        }
        Spacer()
        freshnessBadge(portfolio.freshness)
      }
      HStack {
        Label(
          "\(portfolio.includedCharacterCount) of \(portfolio.totalCharacterCount) characters included",
          systemImage:
            portfolio.includedCharacterCount
            == portfolio.totalCharacterCount
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(
          portfolio.includedCharacterCount
            == portfolio.totalCharacterCount
            ? DesignTokens.positive
            : DesignTokens.caution
        )
        Spacer()
        Button("Refresh all wallets") {
          Task { await refreshAll() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(clientID.isEmpty || !refreshingCharacterIDs.isEmpty)
        .accessibilityIdentifier("wallet.refresh-all")
      }
      if portfolio.includedCharacterCount < portfolio.totalCharacterCount {
        Text(
          "The displayed sum includes only characters with a stored wallet balance. Missing or forbidden balances are never treated as zero."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var characterPanel: some View {
    Panel(title: "By character") {
      ForEach(Array(portfolio.balances.enumerated()), id: \.element.id) {
        index, row in
        if index > 0 {
          Divider()
        }
        HStack(spacing: DesignTokens.spacingMD) {
          Image(systemName: "person.crop.circle.fill")
            .font(.title2)
            .foregroundStyle(DesignTokens.accent)
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(row.character.name)
              .font(.headline)
            if let updatedAt = lastWalletSync(for: row.id) {
              Text("Updated \(updatedAt.formatted())")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.textSecondary)
            } else {
              Text("Not synchronized")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
          }
          Spacer()
          VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
            Text(
              row.balance.value.map(formatISK) ?? "Unavailable"
            )
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(
              row.balance.value == nil
                ? DesignTokens.textSecondary
                : DesignTokens.highlight
            )
            freshnessBadge(row.balance.state)
          }
          Button {
            guard
              let character = characters.first(
                where: { $0.characterID == row.id }
              )
            else { return }
            Task { await refresh(character) }
          } label: {
            if refreshingCharacterIDs.contains(row.id) {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .buttonStyle(.bordered)
          .disabled(
            clientID.isEmpty
              || refreshingCharacterIDs.contains(row.id)
          )
          .help("Refresh \(row.character.name)'s wallet")
          .accessibilityLabel("Refresh \(row.character.name)'s wallet")
          .accessibilityIdentifier("wallet.refresh.\(row.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.character.\(row.id)")
      }
    }
  }

  private var clientID: String {
    settings.first(where: { $0.key == "eve.clientID" })?.value ?? ""
  }

  private var portfolio: WalletPortfolioSnapshot {
    WalletPortfolioSnapshot(
      balances: characters.map { character in
        CharacterWalletBalance(
          character: CharacterIdentity(
            id: character.characterID,
            name: character.characterName
          ),
          balance: storedBalance(for: character)
        )
      }
    )
  }

  private var totalText: String {
    guard portfolio.includedCharacterCount > 0 else {
      return "Unavailable"
    }
    return formatISK(portfolio.totalBalance)
  }

  private func storedBalance(
    for character: StoredCharacter
  ) -> Sourced<Double> {
    if let data = character.walletBalanceSnapshot,
      let stored = try? JSONDecoder().decode(
        Sourced<Double>.self,
        from: data
      )
    {
      return stored
    }
    return Sourced(
      state: .unavailable,
      value: nil,
      source: SourceIdentity(
        provider: "Local",
        version: "not-synchronized",
        capturedAt: character.walletLastSyncAt ?? .distantPast
      ),
      diagnostics: ["wallet.not-synchronized"]
    )
  }

  private func lastWalletSync(for characterID: Int64) -> Date? {
    characters.first(where: { $0.characterID == characterID })?
      .walletLastSyncAt
  }

  private func refreshAll() async {
    refreshErrors.removeAll()
    for character in characters {
      await refresh(character)
    }
  }

  private func refresh(_ character: StoredCharacter) async {
    refreshErrors[character.characterID] = nil
    refreshingCharacterIDs.insert(character.characterID)
    defer { refreshingCharacterIDs.remove(character.characterID) }
    do {
      let authorization = try JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: character.authorizationSnapshot
      )
      let balance = try await runtime.syncWallet(
        authorization: authorization,
        clientID: clientID
      )
      character.walletBalanceSnapshot = try JSONEncoder().encode(balance)
      character.walletLastSyncAt = balance.source.capturedAt
      try modelContext.upsertESISnapshotMetadata(
        characterID: character.characterID,
        domain: "wallet-balance",
        freshness: balance.state.rawValue,
        provider: balance.source.provider,
        sourceVersion: balance.source.version,
        sourceSnapshotID: balance.source.snapshotID,
        capturedAt: balance.source.capturedAt,
        diagnostics: balance.diagnostics
      )
      try modelContext.save()
    } catch {
      refreshErrors[character.characterID] =
        "\(character.characterName): \(String(describing: error))"
    }
  }

  private func freshnessBadge(
    _ state: DataFreshness
  ) -> some View {
    Text(state.rawValue.uppercased())
      .font(.caption2.bold())
      .padding(.horizontal, DesignTokens.spacingSM)
      .padding(.vertical, DesignTokens.spacingXS)
      .foregroundStyle(stateColor(state))
      .background(stateColor(state).opacity(0.14))
      .clipShape(
        RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
      )
  }

  private func stateColor(_ state: DataFreshness) -> Color {
    switch state {
    case .fresh: DesignTokens.positive
    case .partial, .stale: DesignTokens.caution
    case .forbidden, .unavailable: DesignTokens.negative
    }
  }

  private func formatISK(_ value: Double) -> String {
    value.formatted(
      .currency(code: "ISK").precision(.fractionLength(2))
    )
  }
}

struct DataSettingsView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Query private var settings: [AppSetting]
  @Query private var activationPointers: [StoredSDEActivationPointer]
  @Environment(\.modelContext) private var modelContext
  @State private var clientID = ""
  @State private var ownerContact = ""
  @State private var showInstallConfirmation = false
  @State private var schemaReviewConfirmed = false
  @State private var settingsMessage: String?
  @State private var settingsError: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text("Data & Settings").font(.largeTitle.bold())
        Panel(title: "Static Data Export") {
          LabeledContent(
            "Active catalog",
            value: runtime.activeSDEBuild.map {
              "Build \($0)"
            } ?? "Not installed"
          )
          LabeledContent(
            "Lifecycle", value: "Preview → Confirm → Backup → Stage → Validate → Activate")
          TextField(
            "Owner contact for CCP User-Agent",
            text: $ownerContact
          )
          .textFieldStyle(.roundedBorder)
          HStack {
            Button("Check for SDE update") {
              schemaReviewConfirmed = false
              Task { await runtime.checkSDE(ownerContact: ownerContact) }
            }
            .disabled(ownerContact.isEmpty || runtime.isWorking)
            if runtime.isWorking {
              ProgressView().controlSize(.small)
              Text(runtime.installationPhase ?? runtime.statusMessage)
                .font(.caption.monospaced())
            }
          }
          if let preview = runtime.updatePreview {
            Divider()
            LabeledContent(
              "Official build",
              value: String(preview.officialBuild)
            )
            LabeledContent(
              "Released",
              value: preview.releasedAt.formatted()
            )
            LabeledContent(
              "Schema entries",
              value: String(preview.schemaEntryCount)
            )
            Label(
              preview.requiresSchemaReview
                ? "Schema review confirmation is required."
                : "No newer schema boundary was reported.",
              systemImage: preview.requiresSchemaReview
                ? "exclamationmark.shield"
                : "checkmark.shield"
            )
            if preview.requiresSchemaReview {
              Link(
                "Open CCP schema changelog",
                destination: URL(
                  string:
                    "https://developers.eveonline.com/static-data/tranquility/schema-changelog.yaml"
                )!
              )
              Toggle(
                "I reviewed the CCP schema changelog through build \(preview.officialBuild).",
                isOn: $schemaReviewConfirmed
              )
            }
            Button("Review and install…") {
              showInstallConfirmation = true
            }
            .disabled(
              !preview.requiresUpdate
                || (preview.requiresSchemaReview
                  && !schemaReviewConfirmed)
            )
          }
          if let error = runtime.errorMessage {
            Text(error).foregroundStyle(DesignTokens.negative)
          }
          if let settingsError {
            Text(settingsError).foregroundStyle(DesignTokens.negative)
          }
        }
        Panel(title: "ESI") {
          TextField("EVE application client ID", text: $clientID)
            .textFieldStyle(.roundedBorder)
          LabeledContent(
            "Callback",
            value: EVEConstants.callbackURL.absoluteString
          )
          LabeledContent(
            "Compatibility date",
            value: EVEConstants.esiCompatibilityDate
          )
          Button("Save client ID") {
            saveClientID()
          }
          .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
          if let settingsMessage {
            Text(settingsMessage)
              .font(.caption)
              .foregroundStyle(DesignTokens.positive)
          }
          Divider()
          LabeledContent(
            "Refresh-token storage",
            value: "macOS Keychain"
          )
          LabeledContent(
            "Runtime access",
            value: "Cached per character"
          )
          Text(
            "The app never stores EVE refresh tokens in SwiftData or plain files. It uses the modern Data Protection Keychain when the app has a stable signing identity and otherwise keeps the legacy Keychain compatibility path. Tokens are read once and reused during the running app session."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Panel(title: "Fixed market") {
          LabeledContent("Region", value: "The Forge • 10000002")
          LabeledContent("System", value: "Jita • 30000142")
          LabeledContent("Station", value: "Jita IV-4 • 60003760")
          Text(
            "Adjusted prices are used only for EIV and job fees, never as market quotes."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Data & Settings")
    .onAppear {
      clientID =
        settings.first(where: { $0.key == "eve.clientID" })?
        .value ?? ""
      ownerContact =
        settings.first(
          where: { $0.key == "sde.ownerContact" }
        )?.value ?? ""
    }
    .confirmationDialog(
      "Install current SDE build?",
      isPresented: $showInstallConfirmation,
      titleVisibility: .visible
    ) {
      Button("Confirm backup, staging and activation") {
        beginSDEInstallation()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The active catalog remains available during download and validation. Activation occurs only after a safety backup; failures keep the previous build active."
      )
    }
  }

  private func saveClientID() {
    let normalized = clientID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty,
      normalized.utf8.count <= 1_024,
      normalized.unicodeScalars.allSatisfy({
        $0.value >= 0x21 && $0.value <= 0x7e
      })
    else {
      settingsMessage = nil
      settingsError =
        "The EVE client ID must contain only visible ASCII characters and be no longer than 1,024 bytes."
      return
    }
    do {
      try saveSetting(key: "eve.clientID", value: normalized)
      clientID = normalized
      settingsError = nil
      settingsMessage = "The EVE client ID was saved locally."
    } catch {
      settingsMessage = nil
      settingsError =
        "The EVE client ID could not be saved. The previous value remains active."
    }
  }

  private func beginSDEInstallation() {
    do {
      try saveSetting(key: "sde.ownerContact", value: ownerContact)
      settingsError = nil
      Task { await installSDEAndRecordActivation() }
    } catch {
      settingsError =
        "The owner contact could not be saved, so the SDE installation was not started."
    }
  }

  private func installSDEAndRecordActivation() async {
    await runtime.installSDE(
      ownerContact: ownerContact,
      schemaReviewConfirmed: schemaReviewConfirmed
    )
    guard runtime.errorMessage == nil,
      let build = runtime.activeSDEBuild,
      let hash = runtime.activeSDEContentSHA256
    else { return }
    if let pointer = activationPointers.first(where: { $0.key == "active" }) {
      pointer.buildNumber = build
      pointer.contentSHA256 = hash
      pointer.activatedAt = .now
    } else {
      modelContext.insert(
        StoredSDEActivationPointer(
          buildNumber: build,
          contentSHA256: hash
        )
      )
    }
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      runtime.errorMessage =
        "The SDE was activated, but its local activation pointer could not be recorded. Recheck the active build before continuing."
    }
  }

  private func saveSetting(key: String, value: String) throws {
    if let existing = settings.first(where: { $0.key == key }) {
      existing.value = value
    } else {
      modelContext.insert(AppSetting(key: key, value: value))
    }
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}
