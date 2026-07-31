import EVENexusCore
import SwiftData
import SwiftUI

struct ProfilesView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @EnvironmentObject private var profileNavigationGuard: ProfileNavigationGuard
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @Query private var settings: [AppSetting]
  @AppStorage(AppLanguage.storageKey)
  private var storedLanguage = AppLanguage.defaultLanguage.rawValue
  @State private var didLoad = false
  @State private var showResetConfirmation = false
  @State private var statusMessage: LocalizedStringKey?
  @State private var showScienceSkillMatrix = false
  @State private var isRefreshingCharacterSkills = false
  @State private var characterSkillMessage: String?
  @State private var isRefreshingTraderFees = false
  @State private var traderFeeMessage: String?
  @State private var savedBasis: ProductionBasis?
  @State private var showSchedulingConfiguration = false

  private var columns: [GridItem] {
    [
      GridItem(
        .adaptive(minimum: DesignTokens.profileColumnMinimum),
        spacing: DesignTokens.spacingMD,
        alignment: .top
      )
    ]
  }

  private var activitySystemColumns: [GridItem] {
    [
      GridItem(
        .adaptive(minimum: 420),
        spacing: DesignTokens.spacingMD,
        alignment: .top
      )
    ]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        languageConfiguration
        systemAndCostConfiguration
        structureConfiguration
        productionMatrix
        marketAndBlueprintConfiguration
        schedulingConfiguration
        blacklistAndInvention
        inventionSkillsOverview
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text("Profile"))
    .task {
      loadStoredBasisOnce()
      await runtime.refreshProfileReferenceData()
      applyStoredTraderFeesIfNeeded()
      savedBasis = runtime.productionBasis
      profileNavigationGuard.updateDirtyState(false)
    }
    .onChange(of: runtime.productionBasis) { _, newValue in
      var normalized = newValue
      normalized.refreshAutomaticFacilityAssignments()
      if normalized != newValue {
        runtime.productionBasis = normalized
        return
      }
      guard let savedBasis else { return }
      profileNavigationGuard.updateDirtyState(newValue != savedBasis)
    }
    .onChange(of: profileNavigationGuard.saveRequestID) {
      saveBasis()
    }
    .onChange(of: profileNavigationGuard.discardRequestID) {
      guard let savedBasis else {
        profileNavigationGuard.completeDiscard()
        return
      }
      runtime.productionBasis = savedBasis
      statusMessage = "Unsaved changes discarded."
      profileNavigationGuard.completeDiscard()
    }
    .confirmationDialog(
      "Reset the production basis?",
      isPresented: $showResetConfirmation
    ) {
      Button("Reset", role: .destructive) {
        runtime.productionBasis = ProductionBasis()
        statusMessage = "Unsaved defaults restored."
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The saved configuration remains unchanged until you save again.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Production Basis")
        .font(.largeTitle.bold())
      Text(
        "Systems, structures, service modules, rigs, taxes and automatic facility selection for every plan."
      )
      .foregroundStyle(DesignTokens.textSecondary)
      HStack {
        Button("Reset") {
          showResetConfirmation = true
        }
        Button("Save Configuration") {
          saveBasis()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("s", modifiers: .command)
        if profileNavigationGuard.hasUnsavedChanges {
          Label(
            "Unsaved changes",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(DesignTokens.caution)
        }
        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  private var languageConfiguration: some View {
    Panel(title: "Language & Terminology") {
      Picker("Language", selection: languageBinding) {
        ForEach(AppLanguage.allCases) { language in
          Text(language.title).tag(language.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 360)
      .accessibilityIdentifier("profiles.language")

      Text(
        "Explanations and EVE industry terminology follow this selection immediately. EVE item names, character names, locations, ESI, SDE, ME and TE remain unchanged so they still match the EVE client and imported data."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private var languageBinding: Binding<String> {
    Binding(
      get: { storedLanguage },
      set: { language in
        UserDefaults.standard.set(
          language,
          forKey: AppLanguage.storageKey
        )
        storedLanguage = language
      }
    )
  }

  private var systemAndCostConfiguration: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      Panel(title: "Manufacturing Systems") {
        Text(
          "Add every manufacturing system you use. A structure is assigned to one physical location and automatically becomes eligible for every matching activity enabled by its service modules."
        )
        .foregroundStyle(DesignTokens.textSecondary)
        ForEach($runtime.productionBasis.manufacturingSystems) {
          $configuration in
          ActivitySystemRow(
            title: "Manufacturing System",
            configuration: $configuration,
            canDelete:
              runtime.productionBasis.manufacturingSystems.count > 1,
            onDelete: { removeManufacturingSystem(configuration.id) }
          )
        }
        Button {
          runtime.productionBasis.manufacturingSystems.append(
            ActivitySystemConfiguration(
              activity: .manufacturing,
              solarSystemID: 0,
              solarSystemName: ""
            )
          )
        } label: {
          Label("Add Manufacturing System", systemImage: "plus")
        }
        Text(
          "Type at least three letters; ESI supplies the matching solar systems."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      Panel(title: "Reaction & Blueprint Systems") {
        LazyVGrid(
          columns: activitySystemColumns,
          spacing: DesignTokens.spacingMD
        ) {
          ActivitySystemRow(
            title: "Reaction System",
            configuration: basisBinding(\.reactionSystem)
          )
          ActivitySystemRow(
            title: "Invention System",
            configuration: basisBinding(\.inventionSystem)
          )
          ActivitySystemRow(
            title: "Blueprint Copying System",
            configuration: basisBinding(\.copyingSystem)
          )
          ActivitySystemRow(
            title: "Material Research System",
            configuration: basisBinding(\.materialResearchSystem)
          )
          ActivitySystemRow(
            title: "Time Research System",
            configuration: basisBinding(\.timeResearchSystem)
          )
        }
        Text(
          "Every activity uses the same full system editor. Cost-index overrides are intended for unavailable locations such as wormhole space; otherwise the current ESI index is used."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private var schedulingConfiguration: some View {
    Panel(title: "Job Mode, Slots & Account") {
      DisclosureGroup(
        "Scheduling and slot settings",
        isExpanded: $showSchedulingConfiguration
      ) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Picker("Clone state", selection: basisBinding(\.cloneState)) {
            ForEach(CloneState.allCases, id: \.self) { state in
              Text(LocalizedStringKey(state.rawValue.capitalized)).tag(state)
            }
          }
          SlotCountField(
            title: "Manufacturing slots",
            value: basisBinding(\.scheduling.manufacturingSlots)
          )
          SlotCountField(
            title: "Reaction slots",
            value: basisBinding(\.scheduling.reactionSlots)
          )
          LabeledContent("Don't split jobs shorter than") {
            HStack(spacing: DesignTokens.spacingSM) {
              TextField(
                "Days",
                value: basisBinding(
                  \.scheduling.doNotSplitShorterThanDays
                ),
                format: .number
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
              Text("days").foregroundStyle(DesignTokens.textSecondary)
            }
          }
          LabeledContent("No jobs longer than") {
            HStack(spacing: DesignTokens.spacingSM) {
              TextField(
                "Days",
                value: basisBinding(\.scheduling.maximumJobDays),
                format: .number
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
              Text("days").foregroundStyle(DesignTokens.textSecondary)
            }
          }
          Toggle(
            "Always use default mode",
            isOn: basisBinding(\.scheduling.alwaysUseDefaultMode)
          )
        }
      }
    }
  }

  private var marketAndBlueprintConfiguration: some View {
    LazyVGrid(columns: columns, spacing: DesignTokens.spacingMD) {
      Panel(title: "Market Taxes") {
        Picker("Trader", selection: traderCharacterBinding) {
          Text("Select a connected character").tag(Int64?.none)
          ForEach(characters) { character in
            Text(character.characterName)
              .tag(Optional(character.characterID))
          }
        }
        .accessibilityIdentifier("profiles.market-trader")

        LabeledContent("Market location") {
          Text("Jita IV-4")
        }
        LabeledContent("Sales Tax") {
          Text(formatRate(runtime.productionBasis.marketTaxes.salesTaxRate))
            .font(.body.monospacedDigit())
        }
        LabeledContent("Broker Fee") {
          Text(formatRate(runtime.productionBasis.marketTaxes.brokerFeeRate))
            .font(.body.monospacedDigit())
        }

        if let calculation = runtime.productionBasis.marketTaxes.calculation {
          LabeledContent("Accounting") {
            Text(skillLevelText(calculation.accountingLevel))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Broker Relations") {
            Text(skillLevelText(calculation.brokerRelationsLevel))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Caldari State standing") {
            Text(standingText(calculation.factionStanding))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Caldari Navy standing") {
            Text(standingText(calculation.corporationStanding))
              .font(.body.monospacedDigit())
          }
          Label(
            feeFreshnessText(calculation.freshness),
            systemImage:
              calculation.freshness == .fresh
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(
            calculation.freshness == .fresh
              ? DesignTokens.positive : DesignTokens.caution
          )
          Text(
            "Calculated \(calculation.calculatedAt.formatted()) · \(calculation.ruleVersion)"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          ForEach(calculation.warnings, id: \.self) { warning in
            Text(warning)
              .font(.caption)
              .foregroundStyle(DesignTokens.caution)
          }
        } else {
          Text(
            "Choose a connected character. Sales tax is derived from Accounting; the Jita IV-4 broker fee also uses Broker Relations and unmodified Caldari State/Caldari Navy standings."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }

        Button {
          Task { await refreshTraderFees() }
        } label: {
          if isRefreshingTraderFees {
            ProgressView()
          } else {
            Label("Refresh Trader Fees from ESI", systemImage: "arrow.clockwise")
          }
        }
        .disabled(
          isRefreshingTraderFees
            || runtime.productionBasis.marketTaxes.traderCharacterID == nil
        )
        if let traderFeeMessage {
          Text(traderFeeMessage)
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
      }

      Panel(title: "Blueprint Defaults") {
        Stepper(
          "Recursive intermediate ME: \(runtime.productionBasis.defaultIntermediateME)",
          value: basisBinding(\.defaultIntermediateME),
          in: 0...10
        )
        Stepper(
          "Recursive intermediate TE: \(runtime.productionBasis.defaultIntermediateTE)",
          value: basisBinding(\.defaultIntermediateTE),
          in: 0...20,
          step: 2
        )
        Text(
          "Top-level ME and TE still come from each Planner input row. Reactions never receive ME or TE."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      Panel(title: "Logistics") {
        Toggle(
          "Include courier costs in every calculation",
          isOn: basisBinding(\.logistics.isEnabled)
        )
        if runtime.productionBasis.logistics.isEnabled {
          Toggle(
            "Jita purchases → production location",
            isOn: basisBinding(\.logistics.includeInboundMaterials)
          )
          Toggle(
            "Finished products → Jita",
            isOn: basisBinding(\.logistics.includeOutboundProducts)
          )
          TextField(
            "Production location",
            text: basisBinding(\.logistics.productionLocationName)
          )
          TextField(
            "Market delivery location",
            text: basisBinding(\.logistics.marketLocationName)
          )
          LabeledContent("Standard rate") {
            HStack(spacing: DesignTokens.spacingSM) {
              TextField(
                "ISK per m³",
                value: basisBinding(\.logistics.iskPerCubicMeter),
                format: .number
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
              Text("ISK / m³")
                .foregroundStyle(DesignTokens.textSecondary)
            }
          }
          if runtime.productionBasis.logistics.effectiveISKPerCubicMeter == nil {
            Label(
              "Enter the provider's current m³ calculator rate. The screenshot does not state this value, so the app never guesses it.",
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
          }
          LabeledContent("Collateral charge") {
            Text(
              LogisticsConfiguration.collateralRate.formatted(
                .percent.precision(.fractionLength(1))
              )
            )
            .font(.body.monospacedDigit())
          }
          LabeledContent("Contract volume limit") {
            HStack(spacing: DesignTokens.spacingSM) {
              TextField(
                "Maximum m³",
                value: basisBinding(
                  \.logistics.maximumContractVolumeM3
                ),
                format: .number
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
              Text("m³")
                .foregroundStyle(DesignTokens.textSecondary)
            }
          }
          LabeledContent("Rounding") {
            Text("Up to the next 1,000,000 ISK")
              .font(.body.monospacedDigit())
          }
          Text(
            "Each selected route is split automatically into contracts that fit the configured volume limit. Every contract is charged and rounded separately by whichever is greater: volume × rate or 0.5% of accurate collateral. The reference default is 350,000 m³; increase it only when one indivisible item has a provider-confirmed exception. Containers are not supported."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          Text(runtime.productionBasis.logistics.effectiveRuleVersion)
            .font(.caption2.monospaced())
            .foregroundStyle(DesignTokens.textSecondary)
        } else {
          Text(
            "Enable logistics after entering the current provider rate. Disabled logistics contributes 0 ISK and is identified separately from an unavailable calculation."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
  }

  private var structureConfiguration: some View {
    Panel(title: "Structures, Stations, Services & Rigs") {
      Text(
        "Add every structure or station you use, assign its system, then record its Manufacturing Plant, Reactor, Laboratory or Reprocessing Facility and rigs."
      )
      .foregroundStyle(DesignTokens.textSecondary)

      ForEach($runtime.productionBasis.structures) { $structure in
        StructureEditor(
          structure: $structure,
          configuredSystems:
            runtime.productionBasis.configuredActivitySystems,
          authorizations: authorizationSnapshots,
          clientID: clientID,
          canDelete: runtime.productionBasis.structures.count > 1,
          onDelete: {
            removeStructure(structure.id)
          }
        )
      }

      Button {
        addStructure()
      } label: {
        Label("Add Structure or Station", systemImage: "plus")
      }
      .accessibilityIdentifier("profiles.add-structure")
    }
  }

  private var productionMatrix: some View {
    Panel(title: "Automatic Production Basis") {
      Toggle(
        "Automatically select the best structure",
        isOn: basisBinding(\.automaticStructureSelection)
      )
      Text(
        "Manufacturing prioritizes material and then time. Blueprint activities prioritize effective job cost, then time and facility tax. Disable automatic mode to assign facilities manually."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      ScrollView(.horizontal) {
        Grid(
          alignment: .leading,
          horizontalSpacing: DesignTokens.spacingMD,
          verticalSpacing: DesignTokens.spacingSM
        ) {
          GridRow {
            Text("Category").font(.caption.bold())
            Text("Build in").font(.caption.bold())
            Text("System").font(.caption.bold())
            Text("ME bonus").font(.caption.bold())
            Text("TE bonus").font(.caption.bold())
            Text("State").font(.caption.bold())
          }
          Divider().gridCellColumns(6)
          ForEach(ManufacturingCategory.allCases) { category in
            productionMatrixRow(category)
          }
        }
      }

      Divider()
      let reactionSelection = runtime.productionBasis.reactionSelection
      LabeledContent("Reaction structure") {
        if runtime.productionBasis.automaticStructureSelection {
          Text(reactionSelection?.structureName ?? "Not configured")
        } else {
          Picker(
            "Reaction structure",
            selection: optionalStructureBinding(\.reactionStructureID)
          ) {
            Text("Not configured").tag(UUID?.none)
            ForEach(reactionStructures) { structure in
              Text(structure.displayName).tag(Optional(structure.id))
            }
          }
          .labelsHidden()
          .frame(minWidth: DesignTokens.systemNameMinimum)
        }
      }
      LabeledContent("Reaction system") {
        Text(reactionSelection?.solarSystemName ?? "Not assigned")
      }
      LabeledContent("Reaction material bonus") {
        Text(
          reactionSelection.map { formatBonus($0.materialBonusPercent) } ?? "—"
        )
        .font(.body.monospacedDigit())
      }
      LabeledContent("Reaction time bonus") {
        Text(
          reactionSelection.map { formatBonus($0.timeBonusPercent) } ?? "—"
        )
        .font(.body.monospacedDigit())
      }
      Text(
        "Automatic selection considers reaction-capable refineries in the selected reaction system and prioritizes material, time, job-cost and facility-tax modifiers. Reactions have no ME/TE."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Divider()
      Text("Blueprint Activities")
        .font(.headline)
      ScrollView(.horizontal) {
        Grid(
          alignment: .leading,
          horizontalSpacing: DesignTokens.spacingMD,
          verticalSpacing: DesignTokens.spacingSM
        ) {
          GridRow {
            Text("Activity").font(.caption.bold())
            Text("Facility").font(.caption.bold())
            Text("System").font(.caption.bold())
            Text("Job cost bonus").font(.caption.bold())
            Text("Time bonus").font(.caption.bold())
            Text("State").font(.caption.bold())
          }
          Divider().gridCellColumns(6)
          ForEach(
            IndustryActivitySystem.allCases.filter(\.isScienceActivity)
          ) { activity in
            scienceFacilityRow(activity)
          }
        }
      }
      Text(
        "Selections use current SDE rig modifiers and the configured activity system. They configure the production basis; concrete invention, copying and research job planning remains a separate blueprint-planner capability."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  @ViewBuilder
  private func productionMatrixRow(_ category: ManufacturingCategory)
    -> some View
  {
    let selection = runtime.productionBasis.selection(for: category)
    GridRow {
      Text(LocalizedStringKey(category.displayName))
        .frame(
          minWidth: DesignTokens.efficiencyLabelMinimum,
          alignment: .leading
        )
      if runtime.productionBasis.automaticStructureSelection {
        Text(selection?.structureName ?? "Not configured")
      } else {
        Picker(
          category.displayName,
          selection: assignmentBinding(for: category)
        ) {
          Text("Not configured").tag(UUID?.none)
          ForEach(manufacturingStructures) { structure in
            Text(structure.displayName).tag(Optional(structure.id))
          }
        }
        .labelsHidden()
      }
      Text(selection?.solarSystemName ?? "Not assigned")
        .foregroundStyle(
          selection?.solarSystemName == nil
            ? DesignTokens.caution : DesignTokens.textPrimary
        )
      Text(
        selection.map { formatBonus($0.materialBonusPercent) } ?? "—"
      )
      .font(.body.monospacedDigit())
      Text(selection.map { formatBonus($0.timeBonusPercent) } ?? "—")
        .font(.body.monospacedDigit())
      Label(
        selection?.needsReview == true ? "Review" : "Ready",
        systemImage:
          selection?.needsReview == true
          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
      )
      .font(.caption)
      .foregroundStyle(
        selection?.needsReview == true
          ? DesignTokens.caution : DesignTokens.positive
      )
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func scienceFacilityRow(_ activity: IndustryActivitySystem)
    -> some View
  {
    let selection = runtime.productionBasis.scienceSelection(for: activity)
    GridRow {
      Text(LocalizedStringKey(activity.displayName))
        .frame(
          minWidth: DesignTokens.efficiencyLabelMinimum,
          alignment: .leading
        )
      if runtime.productionBasis.automaticStructureSelection {
        Text(selection?.structureName ?? "Not configured")
      } else {
        Picker(
          activity.displayName,
          selection: scienceAssignmentBinding(for: activity)
        ) {
          Text("Not configured").tag(UUID?.none)
          ForEach(scienceStructures(for: activity)) { structure in
            Text(structure.displayName).tag(Optional(structure.id))
          }
        }
        .labelsHidden()
      }
      Text(selection?.solarSystemName ?? "Not assigned")
        .foregroundStyle(
          selection == nil
            ? DesignTokens.caution : DesignTokens.textPrimary
        )
      Text(selection.map { formatBonus($0.jobCostBonusPercent) } ?? "—")
        .font(.body.monospacedDigit())
      Text(selection.map { formatBonus($0.timeBonusPercent) } ?? "—")
        .font(.body.monospacedDigit())
      Label(
        selection == nil
          ? "Missing" : (selection?.needsReview == true ? "Review" : "Ready"),
        systemImage:
          selection == nil || selection?.needsReview == true
          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
      )
      .font(.caption)
      .foregroundStyle(
        selection == nil || selection?.needsReview == true
          ? DesignTokens.caution : DesignTokens.positive
      )
    }
    .accessibilityElement(children: .combine)
  }

  private var blacklistAndInvention: some View {
    LazyVGrid(columns: columns, spacing: DesignTokens.spacingMD) {
      Panel(title: "Production Blacklist") {
        Text("Select materials that must be bought instead of produced.")
          .foregroundStyle(DesignTokens.textSecondary)
        ForEach(ProductionBlacklistPreset.allCases) { preset in
          Toggle(
            preset.displayName,
            isOn: blacklistBinding(for: preset)
          )
        }
        Text("Additional item names — one per line")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        TextEditor(text: customBlacklistBinding)
          .font(.body.monospaced())
          .frame(minHeight: DesignTokens.stockInputMinimumHeight)
          .scrollContentBackground(.hidden)
          .padding(DesignTokens.spacingSM)
          .background(DesignTokens.elevated)
          .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
          )
      }

      Panel(title: "Invention") {
        LabeledContent("Invention job cost reduction") {
          TextField(
            "Reduction",
            value: basisBinding(\.invention.jobCostReductionRate),
            format: .percent
          )
          .multilineTextAlignment(.trailing)
          .frame(width: DesignTokens.compactNumberWidth)
        }
        Label(
          "The complete SDE Science skill list and character comparison are shown below. Exact invention planning remains outside version 1.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.information)
      }
    }
  }

  private var inventionSkillsOverview: some View {
    Panel(title: "Invention Science Skills & Characters") {
      HStack {
        Text(
          "Compare every SDE Science skill across the connected character skill snapshots."
        )
        .foregroundStyle(DesignTokens.textSecondary)
        Spacer()
        Button {
          Task { await refreshCharacterSkills() }
        } label: {
          Label("Refresh Character Skills", systemImage: "arrow.clockwise")
        }
        .disabled(
          isRefreshingCharacterSkills || clientID.isEmpty
            || characters.isEmpty
        )
        if isRefreshingCharacterSkills {
          ProgressView().controlSize(.small)
        }
      }
      if let characterSkillMessage {
        Text(characterSkillMessage)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }

      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          showScienceSkillMatrix.toggle()
        }
      } label: {
        let count = runtime.scienceSkillDefinitions?.value?.count ?? 0
        HStack(spacing: DesignTokens.spacingSM) {
          Image(
            systemName:
              showScienceSkillMatrix
              ? "chevron.down" : "chevron.right"
          )
          Text("Science skill matrix (\(count) skills)")
            .font(.headline)
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Science skill matrix")
      .accessibilityValue(showScienceSkillMatrix ? "Expanded" : "Collapsed")

      if showScienceSkillMatrix {
        scienceSkillMatrix
          .padding(.top, DesignTokens.spacingSM)
      }
    }
  }

  @ViewBuilder
  private var scienceSkillMatrix: some View {
    if runtime.isLoadingProfileReferenceData {
      ProgressView("Loading SDE skills and ESI indices…")
    } else if runtime.scienceSkillDefinitions?.state != .fresh {
      Label(
        "Science skill definitions are unavailable. Check the active SDE catalog.",
        systemImage: "exclamationmark.triangle"
      )
      .foregroundStyle(DesignTokens.caution)
    } else if characters.isEmpty {
      Label(
        "No connected characters are stored.",
        systemImage: "person.crop.circle.badge.questionmark"
      )
      .foregroundStyle(DesignTokens.caution)
    } else {
      let matrix = InventionReadinessMatrix(
        skills: runtime.scienceSkillDefinitions?.value ?? [],
        characters: matrixCharacters,
        capabilities: capabilitySnapshots
      )
      if capabilitySnapshots.count < matrixCharacters.count {
        Label(
          "Characters without a current skill snapshot remain visible as Unknown.",
          systemImage: "person.crop.circle.badge.questionmark"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
      ScrollView(.horizontal) {
        Grid(
          alignment: .leading,
          horizontalSpacing: DesignTokens.spacingMD,
          verticalSpacing: DesignTokens.spacingXS
        ) {
          GridRow {
            Text("Science skill").font(.caption.bold())
              .frame(minWidth: 240, alignment: .leading)
            ForEach(matrix.characters) { character in
              Text(character.characterName)
                .font(.caption.bold())
                .frame(minWidth: 110, alignment: .center)
            }
          }
          Divider().gridCellColumns(max(matrix.characters.count + 1, 1))
          ForEach(matrix.rows) { row in
            GridRow {
              HStack(spacing: DesignTokens.spacingXS) {
                Text(row.skill.name)
                if row.skill.isInventionRelevant {
                  Image(systemName: "wand.and.stars")
                    .foregroundStyle(DesignTokens.highlight)
                    .accessibilityLabel("Relevant to invention readiness")
                }
              }
              .frame(minWidth: 240, alignment: .leading)
              ForEach(matrix.characters) { character in
                let level = row.levels.first {
                  $0.characterID == character.characterID
                }?.level
                Text(level.map { "Level \($0)" } ?? "Unknown")
                  .font(.body.monospacedDigit())
                  .foregroundStyle(
                    level == nil
                      ? DesignTokens.caution
                      : level == 5
                        ? DesignTokens.positive
                        : DesignTokens.textPrimary
                  )
                  .frame(minWidth: 110, alignment: .center)
              }
            }
          }
        }
      }

      Divider()
      ForEach(matrix.characters) { character in
        LabeledContent(character.characterName) {
          if let average = character.averageRelevantLevel {
            Text(
              "\(character.skillState.rawValue.uppercased()) · \(character.trainedRelevantSkills)/\(character.knownRelevantSkills) trained · Ø \(average.formatted(.number.locale(AppLocalization.currentLanguage.locale).precision(.fractionLength(2)))) · \(character.levelFiveRelevantSkills) at V"
            )
            .font(.body.monospacedDigit())
          } else {
            Text("Skill state unavailable")
              .foregroundStyle(DesignTokens.caution)
          }
        }
      }
      Label(matrix.conclusion, systemImage: "lightbulb.max.fill")
        .foregroundStyle(DesignTokens.information)
      Text(
        "The highlighted skills form the broad readiness comparison. Exact invention chance requires the selected blueprint, its base probability, the three required skills and any decryptor."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func basisBinding<Value>(
    _ keyPath: WritableKeyPath<ProductionBasis, Value>
  ) -> Binding<Value> {
    Binding(
      get: { runtime.productionBasis[keyPath: keyPath] },
      set: { runtime.productionBasis[keyPath: keyPath] = $0 }
    )
  }

  private func optionalStructureBinding(
    _ keyPath: WritableKeyPath<ProductionBasis, UUID?>
  ) -> Binding<UUID?> {
    basisBinding(keyPath)
  }

  private func assignmentBinding(
    for category: ManufacturingCategory
  ) -> Binding<UUID?> {
    Binding(
      get: { runtime.productionBasis.manufacturingAssignments[category] },
      set: { runtime.productionBasis.manufacturingAssignments[category] = $0 }
    )
  }

  private func scienceAssignmentBinding(
    for activity: IndustryActivitySystem
  ) -> Binding<UUID?> {
    Binding(
      get: { runtime.productionBasis.scienceAssignments[activity] },
      set: { structureID in
        if let structureID {
          runtime.productionBasis.scienceAssignments[activity] = structureID
        } else {
          runtime.productionBasis.scienceAssignments.removeValue(
            forKey: activity
          )
        }
      }
    )
  }

  private var traderCharacterBinding: Binding<Int64?> {
    Binding(
      get: { runtime.productionBasis.marketTaxes.traderCharacterID },
      set: { characterID in
        let capability = capabilitySnapshots.first {
          $0.character.id == characterID
        }
        runtime.productionBasis.marketTaxes.selectTrader(
          characterID: characterID,
          capability: capability
        )
        traderFeeMessage =
          capability == nil && characterID != nil
          ? "No usable skill snapshot is stored yet. Refresh the trader fees."
          : nil
      }
    )
  }

  private func blacklistBinding(
    for preset: ProductionBlacklistPreset
  ) -> Binding<Bool> {
    Binding(
      get: { runtime.productionBasis.blacklist.presets.contains(preset) },
      set: { enabled in
        if enabled {
          runtime.productionBasis.blacklist.presets.insert(preset)
        } else {
          runtime.productionBasis.blacklist.presets.remove(preset)
        }
      }
    )
  }

  private var customBlacklistBinding: Binding<String> {
    Binding(
      get: {
        runtime.productionBasis.blacklist.typeNames.joined(separator: "\n")
      },
      set: { text in
        runtime.productionBasis.blacklist.typeNames =
          text.components(separatedBy: .newlines)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      }
    )
  }

  private var clientID: String {
    settings.first(where: { $0.key == "eve.clientID" })?.value ?? ""
  }

  private var authorizationSnapshots: [AuthorizationSnapshot] {
    characters.compactMap {
      try? JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: $0.authorizationSnapshot
      )
    }
  }

  private var capabilitySnapshots: [CharacterCapabilitySnapshot] {
    var snapshots = characters.compactMap { character in
      character.capabilitySnapshot.flatMap {
        try? JSONDecoder().decode(
          CharacterCapabilitySnapshot.self,
          from: $0
        )
      }
    }
    if let latest = runtime.lastCharacterSync?.capabilities {
      snapshots.removeAll { $0.character.id == latest.character.id }
      snapshots.append(latest)
    }
    return snapshots
  }

  private var reactionStructures: [ConfiguredIndustryStructure] {
    runtime.productionBasis.structures.filter {
      $0.solarSystemID == runtime.productionBasis.reactionSystem.solarSystemID
        && $0.isReactionCapable
    }
  }

  private var manufacturingStructures: [ConfiguredIndustryStructure] {
    runtime.productionBasis.structures.filter {
      runtime.productionBasis.manufacturingSystem(for: $0) != nil
        && $0.supportsActivity(.manufacturing)
    }
  }

  private func scienceStructures(
    for activity: IndustryActivitySystem
  ) -> [ConfiguredIndustryStructure] {
    guard
      let system = runtime.productionBasis.systemConfiguration(
        for: activity
      )
    else { return [] }
    return runtime.productionBasis.structures.filter {
      runtime.productionBasis.configuredSystem(for: $0)?.solarSystemID
        == system.solarSystemID
        && $0.isScienceCapable(for: activity)
    }
  }

  private var matrixCharacters: [CharacterIdentity] {
    characters.map {
      CharacterIdentity(id: $0.characterID, name: $0.characterName)
    }
  }

  private func refreshCharacterSkills() async {
    guard !clientID.isEmpty else {
      characterSkillMessage =
        "Save the EVE application client ID in Data & Settings first."
      return
    }
    isRefreshingCharacterSkills = true
    characterSkillMessage = nil
    defer { isRefreshingCharacterSkills = false }
    var refreshed = 0
    var failed = 0
    for character in characters {
      do {
        let authorization = try JSONDecoder().decode(
          AuthorizationSnapshot.self,
          from: character.authorizationSnapshot
        )
        let capability = try await runtime.syncCharacterCapabilities(
          authorization: authorization,
          clientID: clientID
        )
        character.capabilitySnapshot = try JSONEncoder().encode(capability)
        character.lastSyncAt = .now
        refreshed += 1
      } catch {
        failed += 1
      }
    }
    do {
      try modelContext.save()
      characterSkillMessage =
        failed == 0
        ? "Updated skill snapshots for \(refreshed) characters."
        : "Updated \(refreshed) characters; \(failed) require reauthorization or retry."
    } catch {
      characterSkillMessage = "Skill snapshots could not be saved."
    }
  }

  private func applyStoredTraderFeesIfNeeded() {
    let taxes = runtime.productionBasis.marketTaxes
    guard taxes.calculation == nil, let characterID = taxes.traderCharacterID,
      let capability = capabilitySnapshots.first(where: {
        $0.character.id == characterID
      })
    else { return }
    runtime.productionBasis.marketTaxes.apply(capability: capability)
  }

  private func refreshTraderFees() async {
    guard
      let characterID =
        runtime.productionBasis.marketTaxes.traderCharacterID,
      let character = characters.first(where: {
        $0.characterID == characterID
      })
    else {
      traderFeeMessage = "Select a connected trader first."
      return
    }
    guard !clientID.isEmpty else {
      traderFeeMessage =
        "Save the EVE application client ID in Data & Settings first."
      return
    }
    isRefreshingTraderFees = true
    traderFeeMessage = nil
    defer { isRefreshingTraderFees = false }
    do {
      let authorization = try JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: character.authorizationSnapshot
      )
      let capability = try await runtime.syncCharacterCapabilities(
        authorization: authorization,
        clientID: clientID
      )
      character.capabilitySnapshot = try JSONEncoder().encode(capability)
      character.lastSyncAt = .now
      try modelContext.save()
      runtime.productionBasis.marketTaxes.apply(capability: capability)
      traderFeeMessage =
        "Trader skills and standings refreshed from ESI."
    } catch {
      traderFeeMessage =
        "Trader fees could not be refreshed. Check scopes and reauthorize this character."
    }
  }

  private func addStructure() {
    guard let system = runtime.productionBasis.defaultManufacturingSystem else {
      return
    }
    runtime.productionBasis.structures.append(
      ConfiguredIndustryStructure(
        manufacturingSystemID: system.id,
        solarSystemID: system.solarSystemID,
        solarSystemName: system.solarSystemName,
        securityStatus: system.securityStatus,
        regionID: system.regionID,
        serviceModules: []
      )
    )
  }

  private func removeManufacturingSystem(_ id: UUID) {
    guard runtime.productionBasis.manufacturingSystems.count > 1 else {
      return
    }
    runtime.productionBasis.manufacturingSystems.removeAll { $0.id == id }
    guard let fallback = runtime.productionBasis.defaultManufacturingSystem
    else { return }
    for index in runtime.productionBasis.structures.indices
    where runtime.productionBasis.structures[index].manufacturingSystemID == id {
      runtime.productionBasis.structures[index].manufacturingSystemID =
        fallback.id
      runtime.productionBasis.structures[index].solarSystemID =
        fallback.solarSystemID
      runtime.productionBasis.structures[index].solarSystemName =
        fallback.solarSystemName
      runtime.productionBasis.structures[index].securityStatus =
        fallback.securityStatus
      runtime.productionBasis.structures[index].securityBand =
        fallback.securityBand
    }
  }

  private func removeStructure(_ id: UUID) {
    runtime.productionBasis.structures.removeAll { $0.id == id }
    runtime.productionBasis.manufacturingAssignments =
      runtime.productionBasis.manufacturingAssignments.filter {
        $0.value != id
      }
    if runtime.productionBasis.reactionStructureID == id {
      runtime.productionBasis.reactionStructureID = nil
    }
    runtime.productionBasis.scienceAssignments =
      runtime.productionBasis.scienceAssignments.filter {
        $0.value != id
      }
  }

  private func loadStoredBasisOnce() {
    guard !didLoad else { return }
    didLoad = true
    guard let stored = storedBases.first,
      let basis = try? JSONDecoder().decode(
        ProductionBasis.self,
        from: stored.encodedBasis
      )
    else { return }
    runtime.productionBasis = basis
    statusMessage = "Loaded \(stored.updatedAt.formatted())."
  }

  private func saveBasis() {
    let connectedCharacterIDs = Set(characters.map(\.characterID))
    guard
      runtime.productionBasis.marketTaxes.isTraderSelectionValid(
        connectedCharacterIDs: connectedCharacterIDs
      )
    else {
      statusMessage =
        "The selected market trader is no longer connected."
      profileNavigationGuard.completeSave(success: false)
      return
    }
    guard let data = try? JSONEncoder().encode(runtime.productionBasis) else {
      statusMessage = "Configuration could not be encoded."
      profileNavigationGuard.completeSave(success: false)
      return
    }
    if let stored = storedBases.first(where: {
      $0.id == runtime.productionBasis.id
    }) {
      stored.name = runtime.productionBasis.name
      stored.encodedBasis = data
      stored.updatedAt = .now
    } else {
      modelContext.insert(
        StoredProductionBasis(
          id: runtime.productionBasis.id,
          name: runtime.productionBasis.name,
          encodedBasis: data
        )
      )
    }
    do {
      try modelContext.save()
      savedBasis = runtime.productionBasis
      profileNavigationGuard.updateDirtyState(false)
      statusMessage = "Saved \(Date.now.formatted())."
      profileNavigationGuard.completeSave(success: true)
    } catch {
      statusMessage = "Save failed."
      profileNavigationGuard.completeSave(success: false)
    }
  }

  private func formatBonus(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(0...2))
    ) + "%"
  }

  private func formatRate(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return value.formatted(
      .percent
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(2...3))
    )
  }

  private func skillLevelText(_ level: Int?) -> String {
    level.map { "Level \($0)" } ?? "Unavailable"
  }

  private func standingText(_ standing: Double?) -> String {
    standing?.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(2))
    ) ?? "Unavailable"
  }

  private func feeFreshnessText(_ freshness: DataFreshness) -> String {
    switch freshness {
    case .fresh: "Fresh ESI skill and standing data"
    case .partial: "Partial ESI skill or standing data"
    case .stale: "Stale ESI skill or standing data"
    case .forbidden: "Required ESI scope is missing"
    case .unavailable: "ESI skill or standing data is unavailable"
    }
  }
}

private struct ActivitySystemRow: View {
  @EnvironmentObject private var runtime: RuntimeState
  let title: LocalizedStringKey
  @Binding var configuration: ActivitySystemConfiguration
  var canDelete = false
  var onDelete: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        Text(title).font(.headline)
        Spacer()
        if let onDelete {
          Button(role: .destructive, action: onDelete) {
            Label("Remove system", systemImage: "minus.circle")
          }
          .labelStyle(.iconOnly)
          .disabled(!canDelete)
        }
      }
      SolarSystemPicker(
        selectedName: configuration.solarSystemName,
        selectedID: configuration.solarSystemID
      ) { option in
        configuration.solarSystemName = option.name
        configuration.solarSystemID = option.id
        configuration.constellationID = nil
        configuration.constellationName = nil
        configuration.regionID = nil
        configuration.regionName = nil
        configuration.securityStatus = nil
        configuration.securityClass = nil
        Task {
          guard
            let details = try? await runtime.resolveSolarSystem(option.id),
            configuration.solarSystemID == details.id
          else { return }
          configuration.solarSystemName = details.name
          configuration.constellationID = details.constellationID
          configuration.constellationName = details.constellationName
          configuration.regionID = details.regionID
          configuration.regionName = details.regionName
          configuration.securityStatus = details.securityStatus
          configuration.securityClass = details.securityClass
          runtime.productionBasis.applySystemDetails(details)
        }
      }
      if let regionName = configuration.regionName {
        LabeledContent("Region") {
          Text(
            "\(regionName) · "
              + String(configuration.regionID ?? 0)
          )
          .font(.body.monospacedDigit())
        }
      }
      if let securityStatus = configuration.securityStatus {
        LabeledContent("Security") {
          Text(
            "\(configuration.securityBand.displayName.localizedUI) · "
              + securityStatus.formatted(
                .number
                  .locale(AppLocalization.currentLanguage.locale)
                  .precision(.fractionLength(2))
              )
          )
          .font(.body.monospacedDigit())
        }
      }
      IndustryIndexSummary(solarSystemID: configuration.solarSystemID)
      if configuration.activity == .manufacturing {
        ProductionLabelPicker(configuration: $configuration)
      }
      LabeledContent("Cost index override") {
        TextField(
          "Cost index override",
          value: $configuration.costIndexOverride,
          format: .percent
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
      }
    }
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }
}

private struct SolarSystemPicker: View {
  @EnvironmentObject private var runtime: RuntimeState
  let selectedName: String
  let selectedID: Int64
  let onSelect: (SolarSystemOption) -> Void

  @State private var query: String
  @State private var results: [SolarSystemOption] = []
  @State private var isSearching = false
  @State private var isShowingResults = false
  @State private var searchMessage: String?
  @State private var searchTask: Task<Void, Never>?

  init(
    selectedName: String,
    selectedID: Int64,
    onSelect: @escaping (SolarSystemOption) -> Void
  ) {
    self.selectedName = selectedName
    self.selectedID = selectedID
    self.onSelect = onSelect
    _query = State(initialValue: "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      TextField("Search solar system", text: $query)
        .textFieldStyle(.roundedBorder)
        .onChange(of: query) { _, value in
          scheduleSearch(value)
        }
        .popover(
          isPresented: $isShowingResults,
          arrowEdge: .bottom
        ) {
          searchResults
        }
      HStack {
        if selectedID > 0, !selectedName.isEmpty {
          Label(
            "\(selectedName) · \(selectedID)",
            systemImage: "checkmark.circle.fill"
          )
          .foregroundStyle(DesignTokens.positive)
        } else {
          Label(
            query.count < 3
              ? "Enter at least 3 letters"
              : "Select a result from the ESI list",
            systemImage: "magnifyingglass"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        Text("Source: ESI")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      .font(.caption)
    }
    .onDisappear {
      searchTask?.cancel()
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      if isSearching {
        ProgressView("Searching ESI…")
      } else if let searchMessage {
        Label(searchMessage, systemImage: "info.circle")
          .foregroundStyle(DesignTokens.textSecondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            ForEach(results) { option in
              Button {
                onSelect(option)
                query = ""
                isShowingResults = false
              } label: {
                HStack {
                  Text(option.name)
                  Spacer()
                  Text(String(option.id))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                }
              }
              .buttonStyle(.plain)
              .padding(.vertical, DesignTokens.spacingXS)
            }
          }
        }
      }
    }
    .padding(DesignTokens.spacingMD)
    .frame(
      minWidth: 320,
      idealWidth: 380,
      maxHeight: 320,
      alignment: .topLeading
    )
  }

  private func scheduleSearch(_ value: String) {
    searchTask?.cancel()
    results = []
    searchMessage = nil
    let accepted = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else {
      isSearching = false
      isShowingResults = false
      return
    }
    isSearching = true
    isShowingResults = true
    searchTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(300))
        let found = try await runtime.searchSolarSystems(matching: accepted)
        try Task.checkCancellation()
        results = found
        isSearching = false
        searchMessage = found.isEmpty ? "No matching solar systems." : nil
      } catch is CancellationError {
        return
      } catch ESIError.cancelled {
        return
      } catch {
        isSearching = false
        searchMessage = "ESI system search is currently unavailable."
      }
    }
  }
}

private struct StructureEditor: View {
  @EnvironmentObject private var runtime: RuntimeState
  @Binding var structure: ConfiguredIndustryStructure
  let configuredSystems: [ActivitySystemConfiguration]
  let authorizations: [AuthorizationSnapshot]
  let clientID: String
  let canDelete: Bool
  let onDelete: () -> Void

  private var reference: IndustryFacilityReferenceSnapshot? {
    runtime.industryFacilityReferences?.value
  }

  private var maximumRigSlots: Int {
    min(3, max(0, structure.maximumRigSlots ?? 0))
  }

  private var configuredLocations: [ActivitySystemConfiguration] {
    var seenSystemIDs = Set<Int64>()
    return configuredSystems.filter {
      $0.solarSystemID > 0
        && seenSystemIDs.insert($0.solarSystemID).inserted
    }
  }

  private var eligibleActivities: [IndustryActivitySystem] {
    runtime.productionBasis.eligibleActivities(for: structure)
  }

  private var locationBinding: Binding<UUID?> {
    Binding(
      get: {
        configuredLocations.first {
          $0.solarSystemID == structure.solarSystemID
        }?.id
      },
      set: { id in
        guard
          let id,
          let system = configuredLocations.first(where: { $0.id == id })
        else {
          structure.manufacturingSystemID = nil
          return
        }
        structure.manufacturingSystemID =
          system.activity == .manufacturing ? system.id : nil
        structure.solarSystemID = system.solarSystemID
        structure.solarSystemName = system.solarSystemName
        structure.securityStatus = system.securityStatus
        structure.securityBand = system.securityBand
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text("Internal structure / station name")
            .font(.caption.bold())
          TextField(
            "e.g. Corp Azbel – Capital",
            text: $structure.name
          )
          .font(.headline)
          Text("Your own label; it does not have to match the EVE name.")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        Button(role: .destructive, action: onDelete) {
          Label("Delete", systemImage: "trash")
        }
        .disabled(!canDelete)
      }

      AccessibleStructurePicker(
        authorizations: authorizations,
        clientID: clientID,
        solarSystemID: structure.solarSystemID,
        solarSystemName: structure.solarSystemName
      ) { option in
        applyPlayerStructure(option)
      }

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: DesignTokens.structureEditorMinimum),
            spacing: DesignTokens.spacingMD
          )
        ],
        spacing: DesignTokens.spacingMD
      ) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Picker("Structure / station type", selection: $structure.kind) {
            ForEach(IndustryStructureKind.selectableCases) { kind in
              Text(LocalizedStringKey(kind.displayName)).tag(kind)
            }
          }
          .onChange(of: structure.kind) { _, kind in
            applyStructureKind(kind)
          }
          Picker(
            "Structure location",
            selection: locationBinding
          ) {
            Text("Not assigned").tag(UUID?.none)
            ForEach(configuredLocations) { system in
              Text(
                (system.solarSystemName.isEmpty
                  ? "Select system" : system.solarSystemName)
                  + " · "
                  + activitiesConfigured(
                    in: system.solarSystemID
                  ).map { $0.displayName.localizedUI }
                  .joined(separator: ", ")
              )
              .tag(Optional(system.id))
            }
          }
          LabeledContent("Automatic activities") {
            if eligibleActivities.isEmpty {
              Text("No matching enabled activity")
                .foregroundStyle(DesignTokens.caution)
            } else {
              Text(
                eligibleActivities.map {
                  $0.displayName.localizedUI
                }.joined(separator: ", ")
              )
              .multilineTextAlignment(.trailing)
            }
          }
          Text(
            "The best eligible structure is selected separately for each activity. One structure can therefore be used for Manufacturing, Invention, Blueprint Copying and research at the same time."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          LabeledContent("Security") {
            if let status = structure.securityStatus {
              Text(
                "\(structure.securityBand.displayName.localizedUI) · "
                  + status.formatted(
                    .number
                      .locale(AppLocalization.currentLanguage.locale)
                      .precision(.fractionLength(2))
                  )
              )
              .font(.body.monospacedDigit())
            } else {
              Label(
                "Resolve the assigned system",
                systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(DesignTokens.caution)
            }
          }
          LabeledContent("Structure size") {
            Text(
              LocalizedStringKey(
                structure.rigSize?.displayName.localizedUI
                  ?? "No structure rigs".localizedUI
              )
            )
          }
          if let eveName = structure.eveStructureName,
            let structureID = structure.structureID
          {
            Label(
              "\(eveName) · \(structureID)",
              systemImage: "link.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.positive)
          }
        }

        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          LabeledContent("Structure ME bonus") {
            Text(formatPercent(structure.structureMaterialBonusPercent))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Structure TE bonus") {
            Text(formatPercent(structure.structureTimeBonusPercent))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Facility tax") {
            TextField(
              "Facility tax",
              value: $structure.facilityTaxRate,
              format: .percent
            )
            .multilineTextAlignment(.trailing)
            .frame(width: DesignTokens.compactNumberWidth)
          }
          LabeledContent("Job cost multiplier") {
            Text(
              structure.jobCostMultiplier.formatted(
                .number
                  .locale(AppLocalization.currentLanguage.locale)
                  .precision(.fractionLength(2...4))
              )
            )
            .font(.body.monospacedDigit())
          }
          Text(
            "Source: \(structure.source.displayName.localizedUI)"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }

      Divider()
      HStack {
        Text("Service Modules").font(.headline)
        Spacer()
        if structure.kind != .npcStation {
          Text(
            "\(structure.serviceModules?.count ?? 0) "
              + "installed".localizedUI
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
      if structure.kind == .npcStation {
        Label(
          "NPC-station services are not published by the structure endpoint. The station remains usable with a Review state.",
          systemImage: "building.columns"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      } else {
        if structure.serviceModules == nil {
          Label(
            "This is a migrated structure. Review and confirm its installed service modules before relying on automatic assignments.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
          Button("Review Installed Modules") {
            structure.serviceModules = []
          }
        } else {
          ForEach(serviceModulesBinding) { $serviceModule in
            ServiceModuleEditor(
              serviceModule: $serviceModule,
              structure: structure,
              definitions: availableServiceDefinitions(
                current: serviceModule.typeID
              )
            ) {
              structure.serviceModules?.removeAll {
                $0.id == serviceModule.id
              }
            }
          }
          Button {
            var modules = structure.serviceModules ?? []
            modules.append(IndustryServiceModuleConfiguration())
            structure.serviceModules = modules
          } label: {
            Label("Add Service Module", systemImage: "plus")
          }
          .disabled(
            reference == nil
              || availableServiceDefinitions(current: nil).isEmpty
          )
        }
      }

      Divider()
      HStack {
        Text("Rigs").font(.headline)
        Spacer()
        Text("\(structure.rigs.count) / \(maximumRigSlots)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
      }
      ForEach($structure.rigs) { $rig in
        RigEditor(
          rig: $rig,
          securityBand: structure.securityBand,
          definitions: availableRigDefinitions(current: rig.typeID)
        ) {
          structure.rigs.removeAll { $0.id == rig.id }
        }
      }
      Button {
        structure.rigs.append(
          IndustryRigConfiguration(
            kind: .none,
            securityBand: structure.securityBand,
            source: .unresolved
          )
        )
      } label: {
        Label("Add Rig", systemImage: "plus")
      }
      .disabled(
        maximumRigSlots == 0 || structure.rigs.count >= maximumRigSlots
      )
      if reference == nil {
        Label(
          "The active SDE rig reference is unavailable.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      } else if maximumRigSlots == 0 {
        Text("NPC stations do not accept structure rigs.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }

  private func applyStructureKind(_ kind: IndustryStructureKind) {
    structure.structureID = nil
    structure.eveStructureName = nil
    structure.ownerCorporationID = nil
    if kind == .npcStation {
      structure.structureTypeID = nil
      structure.structureGroupID = nil
      structure.rigSize = nil
      structure.maximumRigSlots = 0
      structure.structureMaterialBonusPercent = 0
      structure.structureTimeBonusPercent = 0
      structure.jobCostMultiplier = 1
      structure.rigs = []
      structure.serviceModules = []
      structure.source = .staticData
      return
    }
    guard
      let definition = reference?.structure(typeID: kind.typeID)
    else {
      structure.structureTypeID = kind.typeID
      structure.source = .unresolved
      return
    }
    structure.apply(definition: definition)
  }

  private func applyPlayerStructure(_ option: PlayerStructureOption) {
    structure.structureID = option.id
    structure.eveStructureName = option.name
    structure.ownerCorporationID = option.ownerCorporationID
    structure.structureTypeID = option.typeID
    structure.solarSystemID = option.solarSystemID
    if let matchingSystem = configuredLocations.first(where: {
      $0.solarSystemID == option.solarSystemID
    }) {
      structure.manufacturingSystemID =
        matchingSystem.activity == .manufacturing
        ? matchingSystem.id : nil
      structure.solarSystemName = matchingSystem.solarSystemName
      structure.securityStatus = matchingSystem.securityStatus
      structure.securityBand = matchingSystem.securityBand
    } else {
      structure.manufacturingSystemID = nil
    }
    if structure.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty {
      structure.name = option.name
    }
    guard
      let typeID = option.typeID,
      let kind = IndustryStructureKind(typeID: typeID),
      let definition = reference?.structure(typeID: typeID)
    else {
      structure.source = .unresolved
      return
    }
    structure.kind = kind
    structure.apply(definition: definition)
  }

  private func activitiesConfigured(
    in solarSystemID: Int64
  ) -> [IndustryActivitySystem] {
    var seenActivities = Set<IndustryActivitySystem>()
    return configuredSystems.compactMap { system in
      guard system.solarSystemID == solarSystemID,
        seenActivities.insert(system.activity).inserted
      else { return nil }
      return system.activity
    }
  }

  private func availableRigDefinitions(
    current typeID: Int64?
  ) -> [IndustryRigDefinition] {
    let used = Set(structure.rigs.compactMap(\.typeID))
    return reference?.compatibleRigs(size: structure.rigSize).filter {
      $0.typeID == typeID || !used.contains($0.typeID)
    } ?? []
  }

  private var serviceModulesBinding: Binding<[IndustryServiceModuleConfiguration]> {
    Binding(
      get: { structure.serviceModules ?? [] },
      set: { structure.serviceModules = $0 }
    )
  }

  private func availableServiceDefinitions(
    current typeID: Int64?
  ) -> [IndustryServiceModuleDefinition] {
    let used = Set(structure.serviceModules?.compactMap(\.typeID) ?? [])
    return reference?.compatibleServiceModules(
      structureTypeID: structure.structureTypeID,
      structureGroupID: structure.structureGroupID
    ).filter {
      $0.typeID == typeID || !used.contains($0.typeID)
    } ?? []
  }

  private func formatPercent(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(0...2))
    ) + "%"
  }
}

private struct ServiceModuleEditor: View {
  @Binding var serviceModule: IndustryServiceModuleConfiguration
  let structure: ConfiguredIndustryStructure
  let definitions: [IndustryServiceModuleDefinition]
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        Picker(
          "Service module",
          selection: Binding(
            get: { serviceModule.typeID },
            set: { selectedTypeID in
              guard
                let definition = definitions.first(where: {
                  $0.typeID == selectedTypeID
                })
              else {
                serviceModule = IndustryServiceModuleConfiguration(
                  id: serviceModule.id
                )
                return
              }
              serviceModule = IndustryServiceModuleConfiguration(
                id: serviceModule.id,
                definition: definition
              )
            }
          )
        ) {
          Text("Select a compatible service module").tag(Int64?.none)
          ForEach(definitions) { definition in
            Text(definition.name).tag(Optional(definition.typeID))
          }
        }
        .frame(minWidth: 420)
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "minus.circle")
        }
        .accessibilityLabel("Remove service module")
      }

      if serviceModule.source == .unresolved {
        Label(
          "Select a current SDE service module.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      } else {
        Text(
          "Enables: ".localizedUI
            + serviceModule.activities.map { $0.displayName.localizedUI }
            .joined(separator: ", ")
        )
        .font(.caption.weight(.semibold))
        ForEach(serviceModule.activities) { activity in
          LabeledContent(activity.displayName.localizedUI) {
            Text(bonusSummary(for: activity))
              .font(.caption.monospacedDigit())
          }
        }
        Text("SDE service module · bonuses remain source-bound")
          .font(.caption2)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.panel)
    .clipShape(
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
    )
  }

  private func bonusSummary(
    for activity: IndustryFacilityServiceActivity
  ) -> String {
    switch activity {
    case .manufacturing:
      return
        "Base ME".localizedUI
        + " \(formatPercent(structure.structureMaterialBonusPercent)) · "
        + "Base TE".localizedUI
        + " \(formatPercent(structure.structureTimeBonusPercent))"
    case .reaction:
      return
        "Material".localizedUI
        + " \(formatPercent((1 - structure.reactionMaterialMultiplier) * 100)) · "
        + "Time".localizedUI
        + " \(formatPercent((1 - structure.reactionTimeMultiplier) * 100))"
    case .invention, .copying, .materialResearch, .timeResearch:
      guard let industryActivity = activity.industryActivity else {
        return "Enabled"
      }
      let jobCost =
        structure.jobCostMultiplier > 0
        ? 1
          - structure.scienceJobCostMultiplier(for: industryActivity)
          / structure.jobCostMultiplier
        : 0
      let time =
        1 - structure.scienceTimeMultiplier(for: industryActivity)
      return
        "Job cost".localizedUI
        + " \(formatPercent(max(0, jobCost) * 100)) · "
        + "Time".localizedUI
        + " \(formatPercent(max(0, time) * 100))"
    case .reprocessing:
      let values = [
        serviceModule.normalOreYieldMultiplier.map {
          "Ore".localizedUI + " \(formatMultiplier($0))"
        },
        serviceModule.moonOreYieldMultiplier.map {
          "Moon".localizedUI + " \(formatMultiplier($0))"
        },
        serviceModule.iceYieldMultiplier.map {
          "Ice".localizedUI + " \(formatMultiplier($0))"
        },
        serviceModule.gasYieldMultiplier.map {
          "Gas".localizedUI + " \(formatMultiplier($0))"
        },
      ].compactMap { $0 }
      return values.isEmpty
        ? "Enabled · yield unavailable".localizedUI
        : values.joined(separator: " · ")
    }
  }

  private func formatPercent(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(0...2))
    ) + "%"
  }

  private func formatMultiplier(_ value: Double) -> String {
    value.formatted(
      .percent
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(0...2))
    )
  }
}

private struct RigEditor: View {
  @Binding var rig: IndustryRigConfiguration
  let securityBand: SecurityBand
  let definitions: [IndustryRigDefinition]
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        Picker(
          "Rig",
          selection: Binding(
            get: { rig.typeID },
            set: { selectedTypeID in
              guard
                let definition = definitions.first(where: {
                  $0.typeID == selectedTypeID
                })
              else {
                rig = IndustryRigConfiguration(
                  id: rig.id,
                  kind: .none,
                  securityBand: securityBand,
                  source: .unresolved
                )
                return
              }
              rig = IndustryRigConfiguration(
                id: rig.id,
                definition: definition
              )
            }
          )
        ) {
          Text("Select a compatible rig").tag(Int64?.none)
          ForEach(definitions) { definition in
            Text(definition.name).tag(Optional(definition.typeID))
          }
        }
        .frame(minWidth: 420)
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "minus.circle")
        }
        .accessibilityLabel("Remove rig")
      }
      HStack(spacing: DesignTokens.spacingLG) {
        if rig.scienceActivities?.isEmpty == false {
          LabeledContent("Job cost") {
            Text(formatPercent(rig.jobCostBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Time") {
            Text(formatPercent(rig.timeBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
        } else if rig.isReactionRig {
          LabeledContent("Material") {
            Text(formatPercent(rig.materialBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
          LabeledContent("Time") {
            Text(formatPercent(rig.timeBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
        } else {
          LabeledContent("ME") {
            Text(formatPercent(rig.materialBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
          LabeledContent("TE") {
            Text(formatPercent(rig.timeBonus(in: securityBand)))
              .font(.body.monospacedDigit())
          }
        }
        if rig.source == .unresolved {
          Label(
            "Select a current SDE rig",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        } else {
          Text(
            "SDE · \(rig.compatibleStructureSize?.displayName.localizedUI ?? "—")"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.panel)
    .clipShape(
      RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
    )
  }

  private func formatPercent(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .precision(.fractionLength(0...2))
    ) + "%"
  }
}

private struct AccessibleStructurePicker: View {
  @EnvironmentObject private var runtime: RuntimeState
  let authorizations: [AuthorizationSnapshot]
  let clientID: String
  let solarSystemID: Int64
  let solarSystemName: String
  let onSelect: (PlayerStructureOption) -> Void

  @State private var selectedCharacterID: Int64?
  @State private var query = ""
  @State private var results: [PlayerStructureOption] = []
  @State private var isSearching = false
  @State private var message: String?

  init(
    authorizations: [AuthorizationSnapshot],
    clientID: String,
    solarSystemID: Int64,
    solarSystemName: String,
    onSelect: @escaping (PlayerStructureOption) -> Void
  ) {
    self.authorizations = authorizations
    self.clientID = clientID
    self.solarSystemID = solarSystemID
    self.solarSystemName = solarSystemName
    self.onSelect = onSelect
    _selectedCharacterID = State(
      initialValue: authorizations.first?.characterID
    )
  }

  private var authorization: AuthorizationSnapshot? {
    authorizations.first { $0.characterID == selectedCharacterID }
  }

  private var canSearchByName: Bool {
    guard let authorization else { return false }
    return
      authorization.scopes.contains(
        PlayerStructureSearchService.searchScope
      )
      && authorization.scopes.contains(
        PlayerStructureSearchService.detailScope
      )
  }

  private var canDiscoverKnownLocations: Bool {
    guard let authorization,
      authorization.scopes.contains(
        PlayerStructureSearchService.detailScope
      )
    else { return false }
    return !authorization.scopes.isDisjoint(with: [
      PlayerStructureSearchService.assetScope,
      PlayerStructureSearchService.industryJobsScope,
      PlayerStructureSearchService.marketOrdersScope,
    ])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Link an accessible Player Structure")
        .font(.headline)
      Text(
        "ESI has no endpoint for every docking right. Discover structures from this character's assets, industry jobs, and market orders, or search an ACL-visible structure by at least three letters. Results are restricted to \(solarSystemName)."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      Picker("Character", selection: $selectedCharacterID) {
        Text("Select character").tag(Int64?.none)
        ForEach(authorizations) { authorization in
          Text(authorization.characterName)
            .tag(Optional(authorization.characterID))
        }
      }
      HStack(spacing: DesignTokens.spacingSM) {
        Button {
          Task { await performDiscovery() }
        } label: {
          if isSearching {
            ProgressView().controlSize(.small)
          } else {
            Label("Find used structures", systemImage: "building.2.crop.circle")
          }
        }
        .disabled(
          isSearching || solarSystemID <= 0 || !canDiscoverKnownLocations
        )
        Divider().frame(height: 22)
        TextField("EVE structure name", text: $query)
          .textFieldStyle(.roundedBorder)
        Button {
          Task { await performSearch() }
        } label: {
          if isSearching {
            ProgressView().controlSize(.small)
          } else {
            Label("Search ESI", systemImage: "magnifyingglass")
          }
        }
        .disabled(
          isSearching
            || query.trimmingCharacters(
              in: .whitespacesAndNewlines
            ).count < 3
            || solarSystemID <= 0
            || !canSearchByName
        )
      }
      if !results.isEmpty {
        Menu {
          ForEach(results) { option in
            Button {
              onSelect(option)
              message = "Linked \(option.name)."
            } label: {
              Text(option.name)
            }
          }
        } label: {
          Label(
            "Select one of \(results.count) matching structures",
            systemImage: "building.2"
          )
        }
      }
      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(
            canSearchByName || canDiscoverKnownLocations
              ? DesignTokens.textSecondary : DesignTokens.caution
          )
      }
    }
    .onChange(of: selectedCharacterID) { _, _ in
      results = []
      message = nil
    }
    .onChange(of: solarSystemID) { _, _ in
      results = []
      message = nil
    }
  }

  private func performSearch() async {
    guard let authorization else {
      message = "Connect a character first."
      return
    }
    guard canSearchByName else {
      message =
        "Reauthorize this character to grant structure search and structure detail access."
      return
    }
    guard !clientID.isEmpty else {
      message = "Save the EVE application client ID first."
      return
    }
    isSearching = true
    results = []
    defer { isSearching = false }
    do {
      let snapshot = try await runtime.searchAccessibleStructures(
        matching: query,
        in: solarSystemID,
        authorization: authorization,
        clientID: clientID
      )
      results = snapshot.value ?? []
      message =
        results.isEmpty
        ? "No accessible matching structures were found in this system."
        : snapshot.state == .partial
          ? "Some matching structures were not accessible."
          : nil
    } catch ESIError.missingScope {
      message = "Reauthorize this character with the new structure scopes."
    } catch ESIError.forbidden {
      message = "The selected character has no access to these structures."
    } catch {
      message = "ESI structure search is currently unavailable."
    }
  }

  private func performDiscovery() async {
    guard let authorization else {
      message = "Connect a character first."
      return
    }
    guard canDiscoverKnownLocations else {
      message =
        "Reauthorize this character to grant structure details plus assets, industry jobs, or market orders."
      return
    }
    guard !clientID.isEmpty else {
      message = "Save the EVE application client ID first."
      return
    }
    isSearching = true
    results = []
    defer { isSearching = false }
    do {
      let snapshot = try await runtime.discoverKnownAccessibleStructures(
        in: solarSystemID,
        authorization: authorization,
        clientID: clientID
      )
      results = snapshot.value ?? []
      if results.isEmpty {
        message =
          "No used Player Structure was found in this system. Try the name search for structures where this character has no assets, jobs, or orders."
      } else if snapshot.state == .partial {
        message =
          "Found \(results.count) structure(s). Some ESI location sources were unavailable."
      } else {
        message = "Found \(results.count) used structure(s)."
      }
    } catch ESIError.missingScope {
      message = "Reauthorize this character with the current structure scopes."
    } catch {
      message = "ESI structure discovery is currently unavailable."
    }
  }
}

private struct SlotCountField: View {
  let title: LocalizedStringKey
  @Binding var value: Int

  private var positiveValue: Binding<Int> {
    Binding(
      get: { max(1, value) },
      set: { value = max(1, $0) }
    )
  }

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: DesignTokens.spacingSM) {
        TextField(title, value: positiveValue, format: .number)
          .multilineTextAlignment(.trailing)
          .frame(width: DesignTokens.compactNumberWidth)
          .accessibilityLabel(Text(title))
        Stepper(value: positiveValue, step: 1) {
          EmptyView()
        }
        .labelsHidden()
        .accessibilityLabel(Text(title))
      }
    }
  }
}

private struct OptionalSkillStepper: View {
  let title: LocalizedStringKey
  @Binding var level: Int?

  var body: some View {
    HStack {
      Toggle(
        title,
        isOn: Binding(
          get: { level != nil },
          set: { level = $0 ? 0 : nil }
        )
      )
      Spacer()
      if level != nil {
        Stepper(
          "Level \(level ?? 0)",
          value: Binding(
            get: { level ?? 0 },
            set: { level = $0 }
          ),
          in: 0...5
        )
      } else {
        Text("Unknown")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }
}

extension SecurityBand {
  fileprivate var displayName: String {
    switch self {
    case .highSecurity: "High Security".localizedUI
    case .lowSecurity: "Low Security".localizedUI
    case .nullSecurity: "Null Security".localizedUI
    case .wormhole: "Wormhole".localizedUI
    case .unknown: "Unknown".localizedUI
    }
  }
}

extension IndustryModifierSource {
  fileprivate var displayName: String {
    switch self {
    case .ravworksReference:
      "Ravworks reference (2026-07-30)".localizedUI
    case .manual: "Manual".localizedUI
    case .staticData: "CCP SDE"
    case .unresolved: "Unresolved".localizedUI
    }
  }
}
