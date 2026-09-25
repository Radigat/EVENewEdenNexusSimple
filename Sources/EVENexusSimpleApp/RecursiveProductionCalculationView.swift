import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

struct RecursiveProductionCalculationView: View {
  let runtime: RuntimeState

  @Environment(\.modelContext) private var modelContext

  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query(sort: \StoredStockTarget.typeName)
  private var stockTargets: [StoredStockTarget]
  @Query(filter: #Predicate<StoredPlan> { $0.isActive })
  private var activePlans: [StoredPlan]

  @AppStorage(
    "asset.inventory.include-corporation-hangars",
    store: AppDefaults.store
  )
  private var includeCorporationHangars = false
  @AppStorage(
    "recursive-calculation.logistics-route",
    store: AppDefaults.store
  )
  private var routeRawValue = RecursiveProductionLogisticsRoute
    .mainToHomeToMain.rawValue
  @AppStorage(
    "recursive-calculation.default-me",
    store: AppDefaults.store
  )
  private var defaultME = 0
  @AppStorage(
    "recursive-calculation.default-te",
    store: AppDefaults.store
  )
  private var defaultTE = 0
  @AppStorage(
    "recursive-calculation.assume-owned-reaction-formulas",
    store: AppDefaults.store
  )
  private var assumesOwnedReactionFormulas = true

  @State private var input = ""
  @State private var preparedWarehouse = PreparedAssetWarehouse.empty
  @State private var activeReservations: [StockAllocation] = []
  @State private var activeBlueprintReservations: [BlueprintRunReservation] = []
  @State private var invalidActivePlanCount = 0
  @State private var tree: ManufacturingProductionTreeSnapshot?
  @State private var blueprintActions: [Int64: ProductionTreeBlueprintAction] = [:]
  @State private var blueprintCostTexts: [Int64: String] = [:]
  @State private var productionEfficiencies: [Int64: IndustryProductionEfficiency] = [:]
  @State private var needsRecalculation = false
  @State private var isCalculating = false
  @State private var calculationError: String?
  @State private var calculationTask: Task<Void, Never>?
  @State private var calculationGeneration = 0
  @State private var isShowingProductionBookConfirmation = false
  @State private var recordedCalculationID: UUID?
  @State private var productionBookMessage: String?
  @State private var productionBookError: String?

  private var importResult: RecursiveProductionImportResult {
    RecursiveProductionImportParser.parse(input)
  }

  private var route: RecursiveProductionLogisticsRoute {
    RecursiveProductionLogisticsRoute(rawValue: routeRawValue)
      ?? .mainToHomeToMain
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        header
        inputPanel
        routePanel
        if let tree {
          blueprintPanel(tree)
          resultPanel(tree)
          productionBookPanel(tree)
          jobPanel(tree)
          warningPanel(tree)
        }
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(DesignTokens.canvas)
    .task(id: warehouseIdentity) {
      await prepareWarehouse(identity: warehouseIdentity)
    }
    .task(id: activePlanPayloads) {
      let projection = await RecursivePlanReservationProjection.prepare(
        payloads: activePlanPayloads
      )
      guard !Task.isCancelled else { return }
      activeReservations = projection.allocations
      activeBlueprintReservations = projection.blueprintReservations
      invalidActivePlanCount = projection.invalidSnapshotCount
    }
    .onChange(of: input) { _, _ in resetCalculation() }
    .onChange(of: defaultME) { _, _ in resetCalculation() }
    .onChange(of: defaultTE) { _, _ in resetCalculation() }
    .onChange(of: routeRawValue) { _, _ in
      isShowingProductionBookConfirmation = false
      productionBookMessage = nil
      productionBookError = nil
    }
    .confirmationDialog(
      "Create Production Overview entries?",
      isPresented: $isShowingProductionBookConfirmation,
      titleVisibility: .visible
    ) {
      Button("Create entries") {
        recordProductionOverview()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      if let tree {
        Text(
          AppLocalization.format(
            "%@ entries will be stored with current market prices and the selected logistics route. This does not recreate historical actual prices.",
            productionBookDrafts(for: tree).count.formatted()
          )
        )
      }
    }
    .onDisappear {
      calculationGeneration &+= 1
      calculationTask?.cancel()
      calculationTask = nil
      isCalculating = false
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text("Recursive production calculation")
        .font(.largeTitle.bold())
      Text(
        "Reconstruct an untracked production batch from finished items, then account for every recursive build step, Blueprint source and selected logistics route."
      )
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var inputPanel: some View {
    Panel(title: "1 · Paste finished items from EVE") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text(
          "Enter Item Quantity per line like the Ravworks planner, or paste complete EVE item rows. Item and quantity drive the calculation; group, volume and approximate ISK value are imported only as reference."
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)
        TextEditor(text: $input)
          .font(.body.monospaced())
          .frame(minHeight: 150)
          .padding(6)
          .background(DesignTokens.elevated)
          .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
              .stroke(DesignTokens.border)
          }
          .accessibilityIdentifier("recursive-calculation.input")
        Text(
          "Example: Arazu ⇥ 8 ⇥ Force Recon Ship ⇥ ⇥ ⇥ 80.000 m3 ⇥ 1.167.920.630,64 ISK"
        )
        .font(.caption.monospaced())
        .foregroundStyle(DesignTokens.textSecondary)

        Text(
          "ME and TE are assigned after the build steps are resolved: first per EVE group, then optionally per individual Blueprint."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

        if input.isEmpty {
          Text("Paste at least one EVE item row.")
            .foregroundStyle(DesignTokens.textSecondary)
        } else {
          importFeedback(importResult)
        }
      }
    }
  }

  @ViewBuilder
  private func importFeedback(_ result: RecursiveProductionImportResult) -> some View {
    if !result.errors.isEmpty {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        ForEach(result.errors) { error in
          Label(
            AppLocalization.format(
              "Line %lld: %@",
              Int64(error.lineNumber),
              error.message.localizedUI
            ),
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.negative)
        }
      }
    }
    if !result.lines.isEmpty {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text(
          AppLocalization.format(
            "%@ imported item rows",
            result.lines.count.formatted()
          )
        )
        .font(.headline)
        ForEach(result.lines) { line in
          importedLine(line)
        }
      }
    }
  }

  private func importedLine(_ line: RecursiveProductionImportLine) -> some View {
    HStack(alignment: .top, spacing: DesignTokens.spacingMD) {
      VStack(alignment: .leading, spacing: 3) {
        EVEEntityText(value: line.itemName)
        if let group = line.groupName {
          EVEEntityText(value: group, font: .caption)
        }
      }
      Spacer()
      referenceValue("Quantity", line.quantity.formatted())
      referenceValue("Volume", formatVolume(line.volumeM3))
      referenceValue("Approx. value", formatISK(line.estimatedValueISK))
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private var routePanel: some View {
    Panel(title: "2 · Select logistics and calculate") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Picker("Logistics route", selection: routeBinding) {
          Text("Main Hub → Home Hub")
            .tag(RecursiveProductionLogisticsRoute.mainToHome)
          Text("Main Hub → Home Hub → Main Hub")
            .tag(RecursiveProductionLogisticsRoute.mainToHomeToMain)
        }
        .pickerStyle(.segmented)

        HStack(spacing: DesignTokens.spacingSM) {
          Text("Main Hub")
            .foregroundStyle(DesignTokens.textSecondary)
          if let main = runtime.productionBasis.mainTradingLocation?.location {
            EVEEntityText(value: main.name, font: .body)
          } else {
            Text("Not configured")
              .foregroundStyle(DesignTokens.caution)
          }
          Image(systemName: "arrow.right")
          Text("Home Hub")
            .foregroundStyle(DesignTokens.textSecondary)
          if let home = runtime.productionBasis.homeTradingLocation?.location {
            EVEEntityText(value: home.name, font: .body)
          } else {
            Text("Not configured")
              .foregroundStyle(DesignTokens.caution)
          }
          if route.includesFinishedProductReturn {
            Image(systemName: "arrow.right")
            Text("Main Hub")
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }

        if invalidActivePlanCount > 0 {
          Label(
            "One or more active plans could not be read; their reservations remain unavailable.",
            systemImage: "externaldrive.badge.exclamationmark"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }

        HStack {
          Button {
            calculate()
          } label: {
            if isCalculating {
              ProgressView().controlSize(.small)
            } else {
              Label(
                tree == nil ? "Resolve recursive build steps" : "Recalculate",
                systemImage: "function"
              )
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!importResult.isValid || isCalculating)
          .accessibilityIdentifier("recursive-calculation.calculate")
          if isCalculating {
            Button("Cancel", role: .cancel) { cancelCalculation() }
          }
          if needsRecalculation, !isCalculating {
            Text("Selections changed; the displayed total is not current.")
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
          }
        }
        if let calculationError {
          Label(calculationError, systemImage: "xmark.octagon.fill")
            .foregroundStyle(DesignTokens.negative)
        }
      }
    }
  }

  private func blueprintPanel(
    _ tree: ManufacturingProductionTreeSnapshot
  ) -> some View {
    let steps = uniqueBlueprintSteps(in: tree)
    let groups = blueprintGroups(for: steps)
    return Panel(title: "3 · Blueprint source and cost for every build step") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Text(
          "Apply the usual Blueprint source and ME/TE once per EVE group. Every individual build step remains editable below. Reaction formulas are not researchable and therefore have no ME/TE."
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)

        Toggle(
          "Treat all reaction formulas as owned (0 ISK formula allocation)",
          isOn: Binding(
            get: { assumesOwnedReactionFormulas },
            set: {
              assumesOwnedReactionFormulas = $0
              for step in steps where step.node.activity == .reaction {
                blueprintActions[step.blueprintTypeID] = $0 ? nil : .unresolved
              }
              needsRecalculation = true
            }
          )
        )
        .help(
          "This is an explicit planning assumption. It does not infer formula ownership from Assets."
        )

        if steps.isEmpty {
          Text("No resolved Blueprint build step is available.")
            .foregroundStyle(DesignTokens.caution)
        } else {
          Text("Group defaults")
            .font(.headline)
          ForEach(groups) { group in
            blueprintGroupRow(group)
          }

          Divider()
          Text("Individual overrides")
            .font(.headline)
          ForEach(steps) { step in
            blueprintRow(step)
          }
        }
      }
    }
  }

  private func blueprintGroupRow(
    _ group: RecursiveBlueprintGroup
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          EVEEntityText(value: group.name)
          if let categoryName = group.categoryName,
            categoryName != group.name
          {
            EVEEntityText(value: categoryName, font: .caption)
          }
          Text(
            AppLocalization.format(
              "%@ build steps",
              group.steps.count.formatted()
            )
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        Picker(
          "Group Blueprint source",
          selection: groupActionBinding(group)
        ) {
          ForEach(groupActionChoices(group), id: \.self) { action in
            Text(blueprintActionTitle(action)).tag(action)
          }
        }
        .frame(width: 250)
      }

      if !group.isReaction {
        HStack(spacing: DesignTokens.spacingLG) {
          efficiencyStepper(
            title: "Group ME",
            value: groupEfficiencyBinding(
              group,
              keyPath: \.materialEfficiency
            ),
            range: 0...10
          )
          efficiencyStepper(
            title: "Group TE",
            value: groupEfficiencyBinding(
              group,
              keyPath: \.timeEfficiency
            ),
            range: 0...20
          )
        }
      } else {
        Text("Reaction formula · ME/TE not applicable")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.highlight.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func blueprintRow(
    _ step: RecursiveBlueprintStep
  ) -> some View {
    let blueprint = step.blueprint
    let action =
      blueprintActions[blueprint.blueprintTypeID]
      ?? (step.node.activity == .reaction && assumesOwnedReactionFormulas
        ? .useOwnedReactionFormula : blueprint.recommendation)
    return VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          EVEItemText(
            value: blueprint.blueprintName,
            typeID: blueprint.blueprintTypeID
          )
          Text(
            AppLocalization.format(
              "Required runs: %@",
              blueprint.requiredRuns.formatted()
            )
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        Picker(
          "Blueprint source",
          selection: blueprintActionBinding(
            blueprint,
            activity: step.node.activity
          )
        ) {
          ForEach(
            availableActions(
              for: blueprint,
              activity: step.node.activity
            ),
            id: \.self
          ) { choice in
            Text(blueprintActionTitle(choice)).tag(choice)
          }
        }
        .frame(width: 250)
      }

      if step.node.activity != .reaction {
        HStack(spacing: DesignTokens.spacingLG) {
          efficiencyStepper(
            title: "ME",
            value: efficiencyBinding(step, keyPath: \.materialEfficiency),
            range: 0...10
          )
          efficiencyStepper(
            title: "TE",
            value: efficiencyBinding(step, keyPath: \.timeEfficiency),
            range: 0...20
          )
        }
      }

      if action == .buyContractBPC,
        let price = blueprint.attributableBPCContractPrice
      {
        Label(
          AppLocalization.format("Included BPC cost: %@", formatISK(price)),
          systemImage: "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.positive)
      } else if requiresExplicitCost(action) {
        HStack {
          Text(
            actionUsesBPO(action)
              ? "BPO allocation for this batch" : "Consumed BPC/activity cost"
          )
          .font(.caption)
          TextField(
            "ISK",
            text: blueprintCostBinding(blueprint.blueprintTypeID)
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 190)
          if blueprintCostIsInvalid(blueprint.blueprintTypeID) {
            Text("Enter a non-negative ISK amount.")
              .font(.caption)
              .foregroundStyle(DesignTokens.negative)
          }
        }
      } else if action == .unavailable || action == .unresolved {
        Label(
          "Blueprint source unresolved; no cost was invented.",
          systemImage: "questionmark.diamond.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func resultPanel(
    _ tree: ManufacturingProductionTreeSnapshot
  ) -> some View {
    let plan = tree.selectedPlan
    let productionCost = plan.costBreakdown?.totalProductionCost
    let outboundCost = plan.immediateSale.outboundLogisticsCost
    let total =
      route.includesFinishedProductReturn
      ? plan.immediateSale.totalCost : productionCost
    return Panel(title: "4 · Reconstructed cost") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 170))],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          metric("Material", formatISK(plan.costBreakdown?.materialCost))
          metric(
            "Blueprints",
            formatISK(plan.costBreakdown?.blueprintCosts?.total)
          )
          metric("Installation", formatISK(plan.costBreakdown?.installationCost))
          metric(
            "Main → Home logistics",
            formatISK(plan.costBreakdown?.logisticsCost)
          )
          if route.includesFinishedProductReturn {
            metric("Home → Main logistics", formatISK(outboundCost))
          }
          metric("Reconstructed total", formatISK(total))
          metric("Pasted approximate value", formatISK(importResult.estimatedValueISK))
        }
        Text(
          "The pasted value is informational and is not substituted for SDE recipes, market depth, Blueprint costs or logistics."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func jobPanel(
    _ tree: ManufacturingProductionTreeSnapshot
  ) -> some View {
    Panel(title: "Recursive build jobs") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        if tree.selectedPlan.jobs.isEmpty {
          Text("No resolved production jobs are available.")
            .foregroundStyle(DesignTokens.caution)
        } else {
          ForEach(tree.selectedPlan.jobs) { job in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                if let productName = job.productName {
                  EVEItemText(value: productName, typeID: job.typeID)
                } else {
                  Text("Unknown item")
                    .foregroundStyle(DesignTokens.caution)
                }
                if let facility = job.facilityName {
                  EVEEntityText(value: facility, font: .caption)
                }
              }
              Spacer()
              referenceValue(
                "Runs",
                job.runs?.formatted() ?? "—"
              )
              referenceValue(
                "Output",
                job.outputQuantity?.formatted() ?? "—"
              )
            }
            .padding(DesignTokens.spacingSM)
            .background(DesignTokens.elevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
          }
        }
      }
    }
  }

  private func productionBookPanel(
    _ tree: ManufacturingProductionTreeSnapshot
  ) -> some View {
    let drafts = productionBookDrafts(for: tree)
    let isRecorded = recordedCalculationID == tree.selectedPlan.id
    return Panel(title: "5 · Add to Production Overview") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        Label(
          "Current-market reconstruction, not historical actual costs",
          systemImage: "clock.arrow.circlepath"
        )
        .font(.headline)
        Text(
          AppLocalization.format(
            "Prices and fees are frozen from the calculation snapshot of %@. Material, installation, Blueprint and logistics costs are allocated once across the imported finished products.",
            tree.selectedPlan.provenance.priceTimestamp.formatted(
              date: .abbreviated,
              time: .shortened
            )
          )
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.textSecondary)

        ForEach(drafts) { draft in
          productionBookDraftRow(draft)
        }

        HStack(spacing: DesignTokens.spacingSM) {
          Button {
            isShowingProductionBookConfirmation = true
          } label: {
            Label(
              "Create entries in Production Overview",
              systemImage: "books.vertical.fill"
            )
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            drafts.isEmpty || needsRecalculation || isCalculating || isRecorded
          )
          .accessibilityIdentifier("recursive-calculation.record-production")

          if needsRecalculation {
            Text("Recalculate before creating entries.")
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
          }
        }

        if let productionBookMessage {
          Label(productionBookMessage, systemImage: "checkmark.circle.fill")
            .foregroundStyle(DesignTokens.positive)
        }
        if let productionBookError {
          Label(productionBookError, systemImage: "xmark.octagon.fill")
            .foregroundStyle(DesignTokens.negative)
        }
      }
    }
  }

  private func productionBookDraftRow(
    _ draft: ProductionOverviewDraftRow
  ) -> some View {
    let calculation = draft.calculation
    return VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(alignment: .firstTextBaseline) {
        if let productTypeID = draft.productTypeID {
          EVEItemText(value: draft.productName, typeID: productTypeID)
        } else {
          EVEEntityText(value: draft.productName)
        }
        Spacer()
        Text(
          AppLocalization.format(
            "%@ units · %@ runs",
            draft.units.formatted(),
            draft.runs.formatted()
          )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 135))],
        alignment: .leading,
        spacing: DesignTokens.spacingSM
      ) {
        referenceValue("Material", formatISK(draft.materialCost))
        referenceValue("Installation", formatISK(draft.installationCost))
        referenceValue("Logistics", formatISK(draft.logisticsCost))
        referenceValue("Blueprints", formatISK(draft.blueprintCost))
        referenceValue("Sales tax", formatISK(calculation.salesTax))
        referenceValue("Broker fee", formatISK(calculation.brokerFee))
        referenceValue("Production cost", formatISK(calculation.productionCost))
        referenceValue("Sale price / unit", formatISK(draft.salePricePerUnit))
      }
      HStack(spacing: DesignTokens.spacingXS) {
        Text("Production system")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        if draft.systemName == "Nicht aufgelöst" {
          Text("Unresolved")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        } else {
          EVEEntityText(value: draft.systemName, font: .caption)
        }
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  @ViewBuilder
  private func warningPanel(
    _ tree: ManufacturingProductionTreeSnapshot
  ) -> some View {
    let warnings = tree.warnings + tree.selectedPlan.warnings
    if !warnings.isEmpty {
      Panel(title: "Warnings and unavailable data") {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          ForEach(Array(warnings.enumerated()), id: \.offset) { entry in
            Label(
              entry.element.message.localizedUI,
              systemImage: entry.element.severity == .blocking
                ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(
              entry.element.severity == .blocking
                ? DesignTokens.negative : DesignTokens.caution
            )
          }
        }
      }
    }
  }

  private func calculate() {
    let result = importResult
    guard result.isValid else { return }
    let requests = result.lines.map {
      $0.plannerRequest(
        materialEfficiency: defaultME,
        timeEfficiency: defaultTE
      )
    }
    calculationGeneration &+= 1
    let generation = calculationGeneration
    calculationTask?.cancel()
    isCalculating = true
    calculationError = nil
    productionBookMessage = nil
    productionBookError = nil
    let warehouse = preparedWarehouse.warehouse
    let warehouseHasSnapshot = self.warehouseHasSnapshot
    let targets = stockTargetMap
    let reservations = activeReservations
    let inventories = blueprintInventories
    let authorizations = authorizationSnapshots
    let actions = blueprintActions
    let costs = parsedBlueprintCosts
    let efficiencies = productionEfficiencies
    let ownsReactionFormulas = assumesOwnedReactionFormulas
    calculationTask = Task { @MainActor in
      defer {
        if generation == calculationGeneration {
          isCalculating = false
          calculationTask = nil
        }
      }
      do {
        let calculated = try await runtime.recursiveProductionTree(
          requests: requests,
          assetWarehouse: warehouse,
          warehouseHasSnapshot: warehouseHasSnapshot,
          stockTargets: targets,
          existingReservations: reservations,
          existingBlueprintReservations: activeBlueprintReservations,
          blueprintInventories: inventories,
          blueprintActions: actions,
          blueprintManualCosts: costs,
          productionEfficiencies: efficiencies,
          assumesOwnedReactionFormulas: ownsReactionFormulas,
          loyaltyStoreBlueprintTypeIDs: Set(
            runtime.loyaltyStoreCatalog?.offeredTypeIDs ?? []
          ),
          authorizations: authorizations,
          clientID: EVEConstants.ssoClientID
        )
        try Task.checkCancellation()
        guard generation == calculationGeneration else { return }
        tree = calculated
        for step in uniqueBlueprintSteps(in: calculated) {
          if productionEfficiencies[step.node.typeID] == nil,
            step.node.activity != .reaction,
            let me = step.node.materialEfficiency,
            let te = step.node.timeEfficiency
          {
            productionEfficiencies[step.node.typeID] =
              IndustryProductionEfficiency(
                materialEfficiency: me,
                timeEfficiency: te
              )
          }
          if blueprintActions[step.blueprintTypeID] == nil,
            !(step.node.activity == .reaction && assumesOwnedReactionFormulas)
          {
            blueprintActions[step.blueprintTypeID] = step.blueprint.recommendation
          }
        }
        needsRecalculation = false
      } catch is CancellationError {
        return
      } catch {
        guard generation == calculationGeneration else { return }
        calculationError = calculationErrorMessage(error)
      }
    }
  }

  private func cancelCalculation() {
    calculationGeneration &+= 1
    calculationTask?.cancel()
    calculationTask = nil
    isCalculating = false
  }

  private func resetCalculation() {
    cancelCalculation()
    tree = nil
    blueprintActions = [:]
    blueprintCostTexts = [:]
    productionEfficiencies = [:]
    needsRecalculation = false
    calculationError = nil
    recordedCalculationID = nil
    productionBookMessage = nil
    productionBookError = nil
  }

  private func productionBookPlan(
    for tree: ManufacturingProductionTreeSnapshot
  ) -> IndustryPlanSnapshot {
    ProductionOverviewProjector.reconstructedPlan(
      tree.selectedPlan,
      route: route
    )
  }

  private func productionBookDrafts(
    for tree: ManufacturingProductionTreeSnapshot
  ) -> [ProductionOverviewDraftRow] {
    PlannerPersistenceController.productionOverviewDrafts(
      for: productionBookPlan(for: tree),
      productionBasis: runtime.productionBasis
    )
  }

  private func recordProductionOverview() {
    guard let tree,
      !needsRecalculation,
      recordedCalculationID != tree.selectedPlan.id
    else { return }
    let plan = productionBookPlan(for: tree)
    do {
      let rows = try PlannerPersistenceController.recordProductionOverview(
        plan,
        productionBasis: runtime.productionBasis,
        in: modelContext
      )
      recordedCalculationID = tree.selectedPlan.id
      productionBookError = nil
      productionBookMessage = AppLocalization.format(
        "%@ Production Overview entries were created.",
        rows.count.formatted()
      )
    } catch {
      productionBookMessage = nil
      productionBookError = AppLocalization.format(
        "Production Overview entries could not be created. %@",
        error.localizedDescription
      )
    }
  }

  private var routeBinding: Binding<RecursiveProductionLogisticsRoute> {
    Binding(
      get: { route },
      set: { routeRawValue = $0.rawValue }
    )
  }

  private func blueprintActionBinding(
    _ blueprint: ProductionTreeBlueprintAssessment,
    activity: BlueprintActivityDefinition.Kind? = nil
  ) -> Binding<ProductionTreeBlueprintAction> {
    Binding(
      get: {
        blueprintActions[blueprint.blueprintTypeID]
          ?? (activity == .reaction && assumesOwnedReactionFormulas
            ? .useOwnedReactionFormula : blueprint.recommendation)
      },
      set: {
        blueprintActions[blueprint.blueprintTypeID] = $0
        needsRecalculation = true
      }
    )
  }

  private func blueprintCostBinding(_ blueprintTypeID: Int64) -> Binding<String> {
    Binding(
      get: { blueprintCostTexts[blueprintTypeID, default: ""] },
      set: {
        blueprintCostTexts[blueprintTypeID] = $0
        needsRecalculation = true
      }
    )
  }

  private func blueprintGroups(
    for steps: [RecursiveBlueprintStep]
  ) -> [RecursiveBlueprintGroup] {
    let grouped = Dictionary(grouping: steps) { step in
      let activity = step.node.activity?.rawValue ?? "unresolved"
      let category = step.node.sourceCategory ?? ""
      let group = step.node.sourceGroup ?? ""
      return "\(activity)|\(category)|\(group)"
    }
    return grouped.map { entry in
      let steps = entry.value.sorted {
        $0.blueprint.blueprintName.localizedCaseInsensitiveCompare(
          $1.blueprint.blueprintName
        ) == .orderedAscending
      }
      let first = steps[0].node
      let fallback =
        first.activity == .reaction
        ? "Reactions".localizedUI : "Unresolved EVE group".localizedUI
      return RecursiveBlueprintGroup(
        id: entry.key,
        name: first.sourceGroup ?? first.sourceCategory ?? fallback,
        categoryName: first.sourceCategory,
        isReaction: first.activity == .reaction,
        steps: steps
      )
    }.sorted {
      let categoryComparison = ($0.categoryName ?? "")
        .localizedCaseInsensitiveCompare($1.categoryName ?? "")
      if categoryComparison != .orderedSame {
        return categoryComparison == .orderedAscending
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name)
        == .orderedAscending
    }
  }

  private func groupActionChoices(
    _ group: RecursiveBlueprintGroup
  ) -> [ProductionTreeBlueprintAction] {
    group.isReaction
      ? [.useOwnedReactionFormula, .unresolved]
      : [.useOwnedBPO, .useOwnedBPC, .unresolved]
  }

  private func groupActionBinding(
    _ group: RecursiveBlueprintGroup
  ) -> Binding<ProductionTreeBlueprintAction> {
    Binding(
      get: {
        let actions = Set(
          group.steps.map { step in
            blueprintActions[step.blueprintTypeID]
              ?? (step.node.activity == .reaction
                && assumesOwnedReactionFormulas
                ? .useOwnedReactionFormula : step.blueprint.recommendation)
          }
        )
        return actions.count == 1 ? actions.first! : .unresolved
      },
      set: { action in
        for step in group.steps {
          blueprintActions[step.blueprintTypeID] = action
        }
        needsRecalculation = true
      }
    )
  }

  private func effectiveEfficiency(
    _ step: RecursiveBlueprintStep
  ) -> IndustryProductionEfficiency {
    productionEfficiencies[step.node.typeID]
      ?? IndustryProductionEfficiency(
        materialEfficiency: step.node.materialEfficiency ?? defaultME,
        timeEfficiency: step.node.timeEfficiency ?? defaultTE
      )
  }

  private func efficiencyBinding(
    _ step: RecursiveBlueprintStep,
    keyPath: KeyPath<IndustryProductionEfficiency, Int>
  ) -> Binding<Int> {
    Binding(
      get: { effectiveEfficiency(step)[keyPath: keyPath] },
      set: { value in
        setEfficiency(value, for: step, keyPath: keyPath)
      }
    )
  }

  private func groupEfficiencyBinding(
    _ group: RecursiveBlueprintGroup,
    keyPath: KeyPath<IndustryProductionEfficiency, Int>
  ) -> Binding<Int> {
    Binding(
      get: {
        let values = Set(
          group.steps.map {
            effectiveEfficiency($0)[keyPath: keyPath]
          }
        )
        if let value = values.first, values.count == 1 {
          return value
        }
        return keyPath == \IndustryProductionEfficiency.materialEfficiency
          ? defaultME : defaultTE
      },
      set: { value in
        for step in group.steps where step.node.activity != .reaction {
          setEfficiency(value, for: step, keyPath: keyPath)
        }
      }
    )
  }

  private func setEfficiency(
    _ value: Int,
    for step: RecursiveBlueprintStep,
    keyPath: KeyPath<IndustryProductionEfficiency, Int>
  ) {
    let current = effectiveEfficiency(step)
    productionEfficiencies[step.node.typeID] = IndustryProductionEfficiency(
      materialEfficiency:
        keyPath == \IndustryProductionEfficiency.materialEfficiency
        ? value : current.materialEfficiency,
      timeEfficiency:
        keyPath == \IndustryProductionEfficiency.timeEfficiency
        ? value : current.timeEfficiency
    )
    needsRecalculation = true
  }

  private func efficiencyStepper(
    title: LocalizedStringKey,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    HStack {
      Text(title)
      Text(value.wrappedValue.formatted()).monospacedDigit()
      Stepper(title, value: value, in: range)
        .labelsHidden()
    }
  }

  private var parsedBlueprintCosts: [Int64: Double] {
    blueprintCostTexts.reduce(into: [:]) { values, entry in
      if let value = RecursiveProductionImportParser.parseLocalizedNumber(
        entry.value
      ) {
        values[entry.key] = value
      }
    }
  }

  private func blueprintCostIsInvalid(_ blueprintTypeID: Int64) -> Bool {
    let text = blueprintCostTexts[blueprintTypeID, default: ""]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return !text.isEmpty && parsedBlueprintCosts[blueprintTypeID] == nil
  }

  private func availableActions(
    for blueprint: ProductionTreeBlueprintAssessment,
    activity: BlueprintActivityDefinition.Kind?
  ) -> [ProductionTreeBlueprintAction] {
    if activity == .reaction {
      return [.useOwnedReactionFormula, .unresolved]
    }
    var actions = blueprint.availableActions.union([blueprint.recommendation])
    actions.formUnion([.useOwnedBPC, .useOwnedBPO])
    return actions.sorted {
      blueprintActionTitle($0).localizedCaseInsensitiveCompare(
        blueprintActionTitle($1)
      ) == .orderedAscending
    }
  }

  private func uniqueBlueprintSteps(
    in tree: ManufacturingProductionTreeSnapshot
  ) -> [RecursiveBlueprintStep] {
    var seen = Set<Int64>()
    return tree.nodes.compactMap { node in
      guard let blueprint = node.blueprint,
        seen.insert(node.typeID).inserted
      else { return nil }
      return RecursiveBlueprintStep(node: node, blueprint: blueprint)
    }.sorted {
      $0.blueprint.blueprintName.localizedCaseInsensitiveCompare(
        $1.blueprint.blueprintName
      )
        == .orderedAscending
    }
  }

  private func requiresExplicitCost(
    _ action: ProductionTreeBlueprintAction
  ) -> Bool {
    switch action {
    case .useOwnedBPC, .useOwnedBPO, .copyOwnedBPO, .invent,
      .manualExternalBPC,
      .buyContractBPO, .buyMarketBPO, .buyLoyaltyStoreBPC:
      true
    case .buyContractBPC, .unavailable, .unresolved:
      false
    case .useOwnedReactionFormula:
      false
    }
  }

  private func actionUsesBPO(_ action: ProductionTreeBlueprintAction) -> Bool {
    switch action {
    case .useOwnedBPO, .copyOwnedBPO, .buyContractBPO, .buyMarketBPO: true
    default: false
    }
  }

  private func blueprintActionTitle(
    _ action: ProductionTreeBlueprintAction
  ) -> String {
    switch action {
    case .useOwnedBPC: "BPC used".localizedUI
    case .useOwnedBPO: "BPO used".localizedUI
    case .copyOwnedBPO: "Copy owned BPO".localizedUI
    case .invent: "Invent BPC".localizedUI
    case .manualExternalBPC: "External / manual BPC".localizedUI
    case .buyContractBPC: "Buy BPC contract".localizedUI
    case .buyContractBPO: "Buy BPO contract".localizedUI
    case .buyMarketBPO: "Buy market BPO".localizedUI
    case .buyLoyaltyStoreBPC: "Buy Loyalty Store BPC".localizedUI
    case .useOwnedReactionFormula: "Reaction formula owned".localizedUI
    case .unavailable: "Unavailable".localizedUI
    case .unresolved: "Status unresolved".localizedUI
    }
  }

  private var warehouseHasSnapshot: Bool {
    !runtime.productionBasis.productionWarehouseScope.locationIDs.isEmpty
      && preparedWarehouse.ownerStatuses.contains(where: \.hasSnapshot)
  }

  private var stockTargetMap: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    characters.compactMap {
      try? JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: $0.authorizationSnapshot
      )
    }
  }

  private var blueprintInventories: [OwnedBlueprintInventory] {
    characters.compactMap { character in
      guard let data = character.blueprintSnapshot,
        let sourced = try? JSONDecoder().decode(
          Sourced<[OwnedBlueprintInstance]>.self,
          from: data
        )
      else { return nil }
      return OwnedBlueprintInventory(
        ownerID: character.characterID,
        ownerName: character.characterName,
        blueprints: sourced
      )
    }
  }

  private var warehouseIdentity: String {
    let charactersIdentity = characters.map { character in
      [
        String(character.characterID),
        String(character.assetSnapshot?.count ?? 0),
        String(character.corporationID ?? 0),
        String(character.corporationAssetSnapshot?.count ?? 0),
        String(character.lastSyncAt?.timeIntervalSince1970 ?? 0),
      ].joined(separator: ":")
    }.joined(separator: "|")
    let scopeIdentity = runtime.productionBasis.productionWarehouseScope
      .locations.map { "\($0.locationID):\($0.activities.map(\.rawValue).sorted())" }
      .sorted().joined(separator: "|")
    return "\(includeCorporationHangars)|\(charactersIdentity)|\(scopeIdentity)"
  }

  private var activePlanPayloads: [RecursiveStoredPlanPayload] {
    activePlans.map {
      RecursiveStoredPlanPayload(id: $0.id, encodedSnapshot: $0.snapshot)
    }.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  @MainActor
  private func prepareWarehouse(identity: String) async {
    var payloads = characters.compactMap { character in
      character.assetSnapshot.map {
        StoredAssetSnapshotPayload(
          ownerID: character.characterID,
          ownerName: character.characterName,
          ownerKind: .character,
          encodedSnapshot: $0
        )
      }
    }
    if includeCorporationHangars {
      payloads.append(
        contentsOf: characters.compactMap { character in
          guard let corporationID = character.corporationID,
            let snapshot = character.corporationAssetSnapshot
          else { return nil }
          return StoredAssetSnapshotPayload(
            ownerID: corporationID,
            ownerName: character.corporationName
              ?? "Unknown corporation".localizedUI,
            ownerKind: .corporation,
            encodedSnapshot: snapshot
          )
        }
      )
    }
    let prepared = await runtime.prepareAssetWarehouse(
      identity: identity,
      payloads: payloads
    )
    guard !Task.isCancelled else { return }
    let productionWarehouse = await runtime.prepareProductionWarehouse(
      from: prepared
    )
    guard !Task.isCancelled, identity == warehouseIdentity else { return }
    preparedWarehouse = productionWarehouse
  }

  private func referenceValue(_ title: LocalizedStringKey, _ value: String) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value)
        .font(.caption.monospacedDigit())
    }
  }

  private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(verbatim: value)
        .font(.title3.weight(.semibold).monospacedDigit())
    }
    .padding(DesignTokens.spacingSM)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func formatISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(
      .currency(code: "ISK").precision(.fractionLength(0...2))
    )
  }

  private func formatVolume(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...2))) + " m³"
  }

  private func calculationErrorMessage(_ error: Error) -> String {
    switch error {
    case StaticCatalogError.noActiveCatalog:
      "No active SDE catalog is installed.".localizedUI
    case ESIError.notFound:
      "Configure a resolved Main Hub and Home Hub before calculating logistics."
        .localizedUI
    case ManufacturingOpportunityError.invalidSettings:
      "The imported rows or default ME/TE values are invalid.".localizedUI
    default:
      AppLocalization.format(
        "The recursive calculation could not be completed. %@",
        error.localizedDescription
      )
    }
  }
}

private struct RecursiveBlueprintStep: Identifiable {
  let node: ManufacturingProductionTreeNode
  let blueprint: ProductionTreeBlueprintAssessment

  var id: Int64 { node.typeID }
  var blueprintTypeID: Int64 { blueprint.blueprintTypeID }
}

private struct RecursiveBlueprintGroup: Identifiable {
  let id: String
  let name: String
  let categoryName: String?
  let isReaction: Bool
  let steps: [RecursiveBlueprintStep]
}

private struct RecursiveStoredPlanPayload: Hashable, Sendable {
  let id: UUID
  let encodedSnapshot: Data
}

private struct RecursivePlanReservationProjection: Sendable {
  let allocations: [StockAllocation]
  let blueprintReservations: [BlueprintRunReservation]
  let invalidSnapshotCount: Int

  static func prepare(
    payloads: [RecursiveStoredPlanPayload]
  ) async -> RecursivePlanReservationProjection {
    await Task.detached(priority: .userInitiated) {
      var allocations: [StockAllocation] = []
      var blueprintReservations: [BlueprintRunReservation] = []
      var invalidSnapshotCount = 0
      for payload in payloads {
        guard
          let plan = try? JSONDecoder().decode(
            IndustryPlanSnapshot.self,
            from: payload.encodedSnapshot
          )
        else {
          invalidSnapshotCount += 1
          continue
        }
        allocations.append(
          contentsOf: plan.stockAllocations.filter {
            $0.source.kind == .warehouse || $0.source.kind == .assetSnapshot
          }
        )
        blueprintReservations.append(
          contentsOf: plan.blueprintSupplyPlans?.flatMap(\.reservations) ?? []
        )
      }
      return RecursivePlanReservationProjection(
        allocations: allocations,
        blueprintReservations: blueprintReservations,
        invalidSnapshotCount: invalidSnapshotCount
      )
    }.value
  }
}
