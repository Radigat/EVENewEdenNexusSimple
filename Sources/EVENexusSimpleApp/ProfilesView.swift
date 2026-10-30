import EVENexusCore
import SwiftData
import SwiftUI

struct ProfilesView: View {
  @Environment(RuntimeState.self) private var runtime
  /// Editable bindings into the shared Profile basis.
  private var bindableRuntime: Bindable<RuntimeState> { Bindable(runtime) }
  @EnvironmentObject private var profileNavigationGuard: ProfileNavigationGuard
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @State private var didLoad = false
  @State private var showResetConfirmation = false
  @State private var statusMessage: LocalizedStringKey?
  @State private var showScienceSkillMatrix = false
  @State private var isRefreshingCharacterSkills = false
  @State private var characterSkillMessage: String?
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
        .adaptive(minimum: DesignTokens.profileColumnMinimum),
        spacing: DesignTokens.spacingMD,
        alignment: .top
      )
    ]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        systemAndCostConfiguration
        structureConfiguration
        productionMatrix
        marketAndBlueprintConfiguration
        schedulingConfiguration
        characterIndustryConfiguration
        blacklistAndInvention
        inventionSkillsOverview
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text("Industry Settings"))
    .task {
      loadStoredBasisOnce()
      await runtime.refreshProfileReferenceData()
      applyStoredTraderFeesIfNeeded()
      savedBasis = runtime.productionBasis
      profileNavigationGuard.updateDirtyState(false)
    }
    .onChange(of: runtime.productionBasis) { _, newValue in
      var normalized = newValue
      normalized.normalizeTradingLocations()
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

  private var systemAndCostConfiguration: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      Panel(title: "Manufacturing Systems") {
        Text(
          "Add every manufacturing system you use. A structure is assigned to one physical location and automatically becomes eligible for every matching activity enabled by its service modules."
        )
        .foregroundStyle(DesignTokens.textSecondary)
        ActivitySystemCollectionEditor(
          rowTitle: "Manufacturing System",
          addTitle: "Add Manufacturing System",
          activity: .manufacturing,
          configurations: bindableRuntime.productionBasis.manufacturingSystems
        )
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
          ActivitySystemCollectionEditor(
            rowTitle: "Reaction System",
            addTitle: "Add Reaction System",
            activity: .reaction,
            configurations: bindableRuntime.productionBasis.reactionSystems
          )
          ActivitySystemCollectionEditor(
            rowTitle: "Invention System",
            addTitle: "Add Invention System",
            activity: .invention,
            configurations: bindableRuntime.productionBasis.inventionSystems
          )
          ActivitySystemCollectionEditor(
            rowTitle: "Blueprint Copying System",
            addTitle: "Add Blueprint Copying System",
            activity: .copying,
            configurations: bindableRuntime.productionBasis.copyingSystems
          )
          ActivitySystemCollectionEditor(
            rowTitle: "Material Research System",
            addTitle: "Add Material Research System",
            activity: .materialResearch,
            configurations: bindableRuntime.productionBasis.materialResearchSystems
          )
          ActivitySystemCollectionEditor(
            rowTitle: "Time Research System",
            addTitle: "Add Time Research System",
            activity: .timeResearch,
            configurations: bindableRuntime.productionBasis.timeResearchSystems
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
      FullWidthDisclosure(isExpanded: $showSchedulingConfiguration) {
        Text("Scheduling and slot settings")
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Picker("Clone state", selection: basisBinding(\.cloneState)) {
            ForEach(CloneState.allCases, id: \.self) { state in
              Text(LocalizedStringKey(state.rawValue.capitalized)).tag(state)
            }
          }
          Text(
            "Slots come from the characters enabled for industry below, limited by their skills. Without an enabled character, one slot per activity is used."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
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
          LabeledContent("Reaction runs per job") {
            HStack(spacing: DesignTokens.spacingSM) {
              TextField(
                "Runs",
                value: Binding(
                  get: { runtime.productionBasis.scheduling.reactionRunsPerJob },
                  set: {
                    runtime.productionBasis.scheduling.reactionRunsPerJob =
                      max(0, $0)
                  }
                ),
                format: .number
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
              Text("runs").foregroundStyle(DesignTokens.textSecondary)
            }
          }
          Text(
            "Job splitting for the production job list and the estimated job time: manufacturing jobs up to the minimum stay whole; longer jobs are split so that no job exceeds the maximum and free slots are used, while every piece keeps at least the minimum length. A single run longer than the maximum stays one longer job. Reactions run in batches of at least the configured runs (default 100, about 5–6 days); a remainder makes batches longer instead of adding a short batch. 0 runs uses the day window for reactions too. Jobs bound to a selected BPO or BPC stay whole; materials are rounded per job."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          Toggle(
            "Always use default mode",
            isOn: basisBinding(\.scheduling.alwaysUseDefaultMode)
          )
        }
      }
    }
  }

  private var characterIndustryConfiguration: some View {
    let resolution = runtime.productionBasis.scheduling.resolvedSlotGroups(
      capabilities: capabilitySnapshots
    )
    return Panel(title: "Industry Characters") {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text(
          "Choose which characters may run industry jobs, which activities they may take and how many slots they may use. Empty limits use the skill maximum. Without an enabled character, one slot per activity is used."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        if characters.isEmpty {
          Text("Connect a character under Data & Settings to assign industry slots.")
            .foregroundStyle(DesignTokens.textSecondary)
        } else {
          ForEach(characters, id: \.characterID) { character in
            CharacterIndustryAssignmentRow(
              characterName: character.characterName,
              limits: IndustrySkillSlotLimits(
                snapshot: capabilitySnapshots.first {
                  $0.character.id == character.characterID
                }
              ),
              assignment: characterAssignmentBinding(
                characterID: character.characterID,
                characterName: character.characterName
              )
            )
            Divider()
          }
        }
        LabeledContent("Effective slots") {
          Text(
            AppLocalization.format(
              "Manufacturing %lld · Reactions %lld · Science %lld",
              Int64(resolution.slotCount(for: .manufacturing)),
              Int64(resolution.slotCount(for: .reaction)),
              Int64(resolution.slotCount(for: .science))
            )
          )
          .monospacedDigit()
        }
        Text(
          resolution.source == .characters
            ? "Source: enabled characters."
            : "Source: manual slot counts (no character enabled)."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        ForEach(resolution.warnings) { warning in
          Label(warning.message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
      }
    }
  }

  private func characterAssignmentBinding(
    characterID: Int64,
    characterName: String
  ) -> Binding<CharacterIndustryAssignment> {
    Binding(
      get: {
        runtime.productionBasis.scheduling.assignment(for: characterID)
          ?? CharacterIndustryAssignment(
            characterID: characterID,
            characterName: characterName
          )
      },
      set: { newValue in
        var value = newValue
        value.characterName = characterName
        runtime.productionBasis.scheduling.setAssignment(value)
      }
    )
  }

  private var marketAndBlueprintConfiguration: some View {
    LazyVGrid(columns: columns, spacing: DesignTokens.spacingMD) {
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

      Panel(title: "Compressed Ore Refining") {
        Toggle(
          "Compare compressed ore for mineral transport",
          isOn: basisBinding(\.compressedOreRefining.isEnabled)
        )
        Text(
          "For uncovered mineral demand, the Planner compares direct Main Hub mineral purchase and transport with compressed-ore purchase, transport to a configured Reprocessing facility, skill-dependent yield and the confirmed Reprocessing tax. It keeps the direct route unless the complete alternative is cheaper."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        let readyFacilities = runtime.productionBasis.structures.filter(
          \.isReprocessingCapable
        )
        let relevantFacilities = runtime.productionBasis.structures.filter {
          $0.hasReprocessingService
            || $0.reprocessingTaxRate != nil
            || !$0.reprocessingReadinessIssues.contains(.missingOreYield)
        }
        LabeledContent("Ready facilities") {
          Text(readyFacilities.count.formatted())
            .font(.body.monospacedDigit())
        }
        if runtime.productionBasis.compressedOreRefining.isEnabled {
          ForEach(relevantFacilities) { facility in
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              HStack(alignment: .firstTextBaseline) {
                EVEEntityText(
                  value: facility.displayName,
                  font: .body,
                  lineLimit: 2,
                  accessibilityIdentifier:
                    "settings.refining.facility.\(facility.id.uuidString).copy"
                )
                Spacer(minLength: DesignTokens.spacingSM)
                Label(
                  facility.isReprocessingCapable
                    ? "Ready for compressed-ore comparison"
                    : "Incomplete",
                  systemImage: facility.isReprocessingCapable
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                  facility.isReprocessingCapable
                    ? DesignTokens.positive : DesignTokens.caution
                )
              }
              if !facility.reprocessingReadinessIssues.isEmpty {
                Text(
                  facility.reprocessingReadinessIssues.map(
                    reprocessingReadinessIssueText
                  ).joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(DesignTokens.caution)
              }
            }
            .padding(DesignTokens.spacingSM)
            .background(DesignTokens.elevated)
            .clipShape(
              RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
            )
          }
        }
        if runtime.productionBasis.compressedOreRefining.isEnabled,
          readyFacilities.isEmpty
        {
          Label(
            "Configure a Reprocessing service, an ore-yield source and a confirmed Reprocessing tax in at least one structure below.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        }
        Text(runtime.productionBasis.compressedOreRefining.ruleVersion)
          .font(.caption2.monospaced())
          .foregroundStyle(DesignTokens.textSecondary)
        Text(
          "Refining setting changes are used by the next Planner calculation."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  private func reprocessingReadinessIssueText(
    _ issue: ReprocessingReadinessIssue
  ) -> String {
    switch issue {
    case .missingService:
      AppLocalization.text("Reprocessing service missing")
    case .missingOreYield:
      AppLocalization.text("Ore yield source missing")
    case .unconfirmedTax:
      AppLocalization.text("Reprocessing fee unconfirmed")
    }
  }

  private var structureConfiguration: some View {
    Panel(title: "Structures, Stations, Services & Rigs") {
      Text(
        "Add every structure or station you use, assign its system, then record its Manufacturing Plant, Reactor, Laboratory or Reprocessing Facility and rigs."
      )
      .foregroundStyle(DesignTokens.textSecondary)

      ForEach(bindableRuntime.productionBasis.structures) { $structure in
        StructureEditor(
          structure: $structure,
          configuredSystems:
            runtime.productionBasis.configuredActivitySystems,
          authorizations: authorizationSnapshots,
          capabilities: capabilitySnapshots,
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
          if let structureName = reactionSelection?.structureName {
            EVEEntityText(value: structureName)
          } else {
            Text("Not configured")
          }
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
        if let solarSystemName = reactionSelection?.solarSystemName {
          EVEEntityText(value: solarSystemName)
        } else {
          Text("Not assigned")
        }
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
        if let structureName = selection?.structureName {
          EVEEntityText(value: structureName)
        } else {
          Text("Not configured")
        }
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
      if let solarSystemName = selection?.solarSystemName {
        EVEEntityText(value: solarSystemName)
      } else {
        Text("Not assigned")
          .foregroundStyle(DesignTokens.caution)
      }
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
        if let structureName = selection?.structureName {
          EVEEntityText(value: structureName)
        } else {
          Text("Not configured")
        }
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
      if let solarSystemName = selection?.solarSystemName {
        EVEEntityText(value: solarSystemName)
      } else {
        Text("Not assigned")
          .foregroundStyle(DesignTokens.caution)
      }
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

      FullWidthDisclosureButton(
        isExpanded: showScienceSkillMatrix,
        action: { showScienceSkillMatrix.toggle() }
      ) {
        let count = runtime.scienceSkillDefinitions?.value?.count ?? 0
        Text("Science skill matrix (\(count) skills)")
          .font(.headline)
      }
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
                EVEItemText(
                  value: row.skill.name,
                  typeID: row.skill.typeID,
                  font: .body,
                  iconSize: 18
                )
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
    EVEConstants.ssoClientID
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
      runtime.productionBasis.systemConfiguration(
        for: .reaction,
        structure: $0
      ) != nil && $0.isReactionCapable
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
    return runtime.productionBasis.structures.filter {
      runtime.productionBasis.systemConfiguration(
        for: activity,
        structure: $0
      ) != nil && $0.isScienceCapable(for: activity)
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
    runtime.productionBasis.refreshResolvableMarketFees(
      capabilities: capabilitySnapshots
    )
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
    runtime.productionBasis.normalizeTradingLocations()
    let connectedCharacterIDs = Set(characters.map(\.characterID))
    guard
      runtime.productionBasis.areTraderSelectionsValid(
        connectedCharacterIDs: connectedCharacterIDs
      )
    else {
      statusMessage =
        "A trader selected for a Trading Location is no longer connected."
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

}

struct LogisticsSettingsView: View {
  @Environment(RuntimeState.self) private var runtime
  @EnvironmentObject private var profileNavigationGuard: ProfileNavigationGuard
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]
  @State private var logistics = LogisticsConfiguration()
  @State private var savedLogistics: LogisticsConfiguration?
  @State private var didLoad = false
  @State private var showResetConfirmation = false
  @State private var statusMessage: LocalizedStringKey?
  @State private var isPreparingRouteSearch = false
  @State private var routeSearchMessage: LocalizedStringKey?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        courierConfiguration
        jumpConfiguration
        HubTransportLegEditor(
          configuration: $logistics.hubTransport,
          jumpFreighter: logistics.jumpFreighter
        )
      }
      .frame(maxWidth: 1_040, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle(AppLocalization.text("Logistics"))
    .task {
      loadStoredLogisticsOnce()
      await prepareRouteSearch()
    }
    .onChange(of: logistics) { _, newValue in
      guard let savedLogistics else { return }
      profileNavigationGuard.updateDirtyState(newValue != savedLogistics)
    }
    .onChange(of: profileNavigationGuard.saveRequestID) {
      saveLogistics()
    }
    .onChange(of: profileNavigationGuard.discardRequestID) {
      guard let savedLogistics else {
        profileNavigationGuard.completeDiscard()
        return
      }
      logistics = savedLogistics
      statusMessage = "Unsaved changes discarded."
      profileNavigationGuard.completeDiscard()
    }
    .confirmationDialog(
      "Reset the logistics configuration?",
      isPresented: $showResetConfirmation
    ) {
      Button("Reset", role: .destructive) {
        logistics = LogisticsConfiguration()
        statusMessage = "Unsaved defaults restored."
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The saved configuration remains unchanged until you save again.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Logistics")
        .font(.largeTitle.bold())
      Text(
        "Configure courier contracts, Jump Freighter transport and fixed capital routes here under Data & Settings."
      )
      .foregroundStyle(DesignTokens.textSecondary)
      HStack {
        Button("Reset") {
          showResetConfirmation = true
        }
        Button("Save Configuration") {
          saveLogistics()
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

  private var courierConfiguration: some View {
    Panel(title: "Courier logistics · Main Hub → Home Hub") {
      if runtime.productionBasis.mainAndHomeAreIdentical {
        Label(
          "Main Hub and Home Hub are identical; no hub-to-home logistics cost is applied.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(DesignTokens.positive)
      }
      Toggle(
        "Include courier costs in every calculation",
        isOn: $logistics.isEnabled
      )
      if logistics.isEnabled {
        Toggle(
          "Main Hub → Home Hub",
          isOn: $logistics.includeInboundMaterials
        )
        locationContent(
          title: "Main Hub",
          location: runtime.productionBasis.mainTradingLocation?.location,
          accessibilityIdentifier: "settings.logistics.main-hub.copy"
        )
        locationContent(
          title: "Home Hub",
          location: runtime.productionBasis.homeTradingLocation?.location,
          accessibilityIdentifier: "settings.logistics.home-hub.copy"
        )
        Text(
          "Purchased items and make-or-buy input materials are transported from the Main Hub to the Home Hub. Identical locations create no route and no cost."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        LabeledContent("Standard rate") {
          HStack(spacing: DesignTokens.spacingSM) {
            TextField(
              "ISK per m³",
              value: $logistics.iskPerCubicMeter,
              format: .number.locale(AppLocalization.currentLanguage.locale)
            )
            .multilineTextAlignment(.trailing)
            .frame(width: DesignTokens.compactNumberWidth)
            Text("ISK / m³")
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        if logistics.effectiveISKPerCubicMeter == nil {
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
              value: $logistics.maximumContractVolumeM3,
              format: .number.locale(AppLocalization.currentLanguage.locale)
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
        Text(logistics.effectiveRuleVersion)
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

  private var jumpConfiguration: some View {
    Panel(title: "Jump logistics · Home Hub → Coalition Hub") {
      Toggle(
        "Calculate Coalition Hub transport from jump fuel",
        isOn: $logistics.jumpFreighter.isEnabled
      )
      Text(
        "Normal products travel as cargo in the selected Jump Freighter. Every produced jump-capable capital, including a produced Jump Freighter or Capital Industrial Ship, is removed from that cargo and receives its own DOTLAN self-jump route. Fuel is valued with the arithmetic mean of all four current racial-isotope sell prices at the Main Hub. Missing routes, skills or prices remain unavailable and never become 0 ISK."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      if logistics.jumpFreighter.isEnabled {
        locationContent(
          title: "Home Hub",
          location: runtime.productionBasis.homeTradingLocation?.location,
          accessibilityIdentifier: "settings.jump-freighter.home-hub.copy"
        )
        locationContent(
          title: "Coalition Hub",
          location: runtime.productionBasis.coalitionTradingLocation?.location,
          accessibilityIdentifier:
            "settings.jump-freighter.coalition-hub.copy"
        )
        Picker(
          "Jump Freighter",
          selection: $logistics.jumpFreighter.hull
        ) {
          ForEach(JumpFreighterHull.allCases) { hull in
            Text(hull.name).tag(hull)
          }
        }
        LabeledContent("Selected hull") {
          EVEEntityText(
            value: logistics.jumpFreighter.hull.name,
            accessibilityIdentifier: "settings.jump-freighter.hull.copy"
          )
        }
        Picker(
          "Jump pilot",
          selection: $logistics.jumpFreighter.pilotCharacterID
        ) {
          Text("Automatically best eligible character")
            .tag(nil as Int64?)
          ForEach(capabilitySnapshots, id: \.character.id) { capability in
            Text(capability.character.name)
              .tag(Optional(capability.character.id))
          }
        }
        if let selectedID = logistics.jumpFreighter.pilotCharacterID,
          let selected = capabilitySnapshots.first(where: {
            $0.character.id == selectedID
          })
        {
          LabeledContent("Selected pilot") {
            EVEEntityText(
              value: selected.character.name,
              accessibilityIdentifier: "settings.jump-freighter.pilot.copy"
            )
          }
        } else {
          Text(
            "Automatic selection uses the best fresh synchronized navigation profile separately for Jump Freighter cargo and capital self-jumps. A produced Jump Freighter flying itself uses Jump Drive Calibration, Jump Fuel Conservation and Jump Freighters; other capitals use the two jump-drive skills. The Planner does not yet confirm that the selected character may command every produced capital hull; verify that in EVE."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
        LabeledContent("Usable cargo per flight") {
          HStack(spacing: DesignTokens.spacingSM) {
            TextField(
              "m³",
              value: $logistics.jumpFreighter.usableCargoCapacityM3,
              format: .number.locale(AppLocalization.currentLanguage.locale)
            )
            .multilineTextAlignment(.trailing)
            .frame(width: DesignTokens.compactNumberWidth)
            Text("m³")
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        Text(
          "The default 350,000 m³ is an explicit planning assumption for normal cargo only. Enter the usable capacity of the actual fit; the Planner splits those products into one-way flights. Produced jump-capable capitals never consume this cargo capacity and are charged one self-jump per completed hull. Return flights are not included."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        if isPreparingRouteSearch {
          ProgressView("Preparing solar-system search…")
            .controlSize(.small)
        } else if let routeSearchMessage {
          Label(routeSearchMessage, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
        }
        JumpRouteProfileConfigurationEditor(
          configuration: $logistics.jumpFreighter
        )
        Link(
          "Open DOTLAN Jump Planner",
          destination: URL(string: "https://evemaps.dotlan.net/jump")!
        )
        Text(JumpFreighterLogisticsConfiguration.ruleVersion)
          .font(.caption2.monospaced())
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
  }

  @ViewBuilder
  private func locationContent(
    title: LocalizedStringKey,
    location: ProcurementLocation?,
    accessibilityIdentifier: String
  ) -> some View {
    LabeledContent(title) {
      if let location {
        EVEEntityText(
          value: location.name,
          accessibilityIdentifier: accessibilityIdentifier
        )
      } else {
        Text("Not configured")
          .foregroundStyle(DesignTokens.caution)
      }
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

  private func loadStoredLogisticsOnce() {
    guard !didLoad else { return }
    didLoad = true
    if let stored = storedBases.first(where: {
      $0.id == runtime.productionBasis.id
    }),
      let basis = try? JSONDecoder().decode(
        ProductionBasis.self,
        from: stored.encodedBasis
      )
    {
      logistics = basis.logistics
      statusMessage = "Loaded \(stored.updatedAt.formatted())."
    } else {
      logistics = runtime.productionBasis.logistics
    }
    savedLogistics = logistics
    profileNavigationGuard.updateDirtyState(false)
  }

  private func prepareRouteSearch() async {
    isPreparingRouteSearch = true
    routeSearchMessage = nil
    do {
      _ = try await runtime.prepareSolarSystemSearchIndex()
      guard !Task.isCancelled else { return }
      isPreparingRouteSearch = false
    } catch is CancellationError {
      return
    } catch ESIError.cancelled {
      return
    } catch {
      isPreparingRouteSearch = false
      routeSearchMessage =
        "Solar-system search could not be prepared. Existing route data was preserved; retry by typing a system name."
    }
  }

  private func saveLogistics() {
    var basis = runtime.productionBasis
    basis.logistics = logistics
    guard let data = try? JSONEncoder().encode(basis) else {
      statusMessage = "Configuration could not be encoded."
      profileNavigationGuard.completeSave(success: false)
      return
    }
    let stored = storedBases.first(where: { $0.id == basis.id })
    let previousStoredValues = stored.map {
      (name: $0.name, encodedBasis: $0.encodedBasis, updatedAt: $0.updatedAt)
    }
    var insertedBasis: StoredProductionBasis?
    if let stored {
      stored.name = basis.name
      stored.encodedBasis = data
      stored.updatedAt = .now
    } else {
      let inserted = StoredProductionBasis(
        id: basis.id,
        name: basis.name,
        encodedBasis: data
      )
      insertedBasis = inserted
      modelContext.insert(inserted)
    }
    do {
      try modelContext.save()
      runtime.productionBasis = basis
      savedLogistics = logistics
      profileNavigationGuard.updateDirtyState(false)
      statusMessage = "Saved \(Date.now.formatted())."
      profileNavigationGuard.completeSave(success: true)
    } catch {
      if let stored, let previousStoredValues {
        stored.name = previousStoredValues.name
        stored.encodedBasis = previousStoredValues.encodedBasis
        stored.updatedAt = previousStoredValues.updatedAt
      }
      if let insertedBasis {
        modelContext.delete(insertedBasis)
      }
      statusMessage = "Save failed."
      profileNavigationGuard.completeSave(success: false)
    }
  }
}

/// Transport method per directed hub leg for Trade, Planner, Hub
/// opportunities and Reactions (owner request 27.10.2026).
private struct HubTransportLegEditor: View {
  @Binding var configuration: HubTransportConfiguration
  let jumpFreighter: JumpFreighterLogisticsConfiguration

  var body: some View {
    Panel(title: "Trade transport per leg") {
      Text(
        "Choose per directed leg whether the Profile courier, your own Jump Freighter or a Jump Freighter service carries the goods. Trade, Planner, Hub opportunities and Reactions use this choice; outside Trade the switch above still turns all courier and service costs on or off. A self-jump to or from the Main Hub is calculated only in Trade. Missing prices, routes or pilots keep a leg unavailable and never become 0 ISK."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      Picker("Main → Coalition", selection: $configuration.mainToCoalitionRouting) {
        routingOptions
      }
      Picker("Coalition → Main", selection: $configuration.coalitionToMainRouting) {
        routingOptions
      }
      ForEach(HubTransportLeg.allCases) { leg in
        legEditor(leg)
      }
    }
  }

  @ViewBuilder
  private var routingOptions: some View {
    Text("Via Home Hub (two legs)").tag(HubTransportRouting.viaHome)
    Text("Direct (one leg)").tag(HubTransportRouting.direct)
  }

  private func legEditor(_ leg: HubTransportLeg) -> some View {
    let setting = settingBinding(for: leg)
    return VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Picker(Self.title(leg), selection: setting.method) {
        Text("Profile courier").tag(HubTransportMethod.profileCourier)
        Text("Own Jump Freighter").tag(HubTransportMethod.selfJump)
        Text("Jump Freighter service").tag(HubTransportMethod.jumpFreighterService)
      }
      .font(.headline)
      if !isUsed(leg) {
        Text("This leg is not used by the current Main ↔ Coalition routing.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
      switch setting.wrappedValue.method {
      case .profileCourier:
        Text("Uses the Profile courier rate above in this direction.")
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      case .selfJump:
        selfJumpContent(leg, setting: setting)
      case .jumpFreighterService:
        serviceContent(setting: setting.service)
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

  @ViewBuilder
  private func selfJumpContent(
    _ leg: HubTransportLeg,
    setting: Binding<HubTransportLegSetting>
  ) -> some View {
    Picker("Jump-route profile", selection: setting.jumpRouteProfileID) {
      Text(
        leg.touchesMain
          ? "No profile" : "Jump Freighter class profile or automatic DOTLAN route"
      )
      .tag(nil as UUID?)
      ForEach(jumpFreighter.routeProfiles) { profile in
        Text(profile.name).tag(Optional(profile.id))
      }
    }
    if leg.touchesMain {
      Text(
        "A Jump Freighter cannot jump into the high-security Main Hub. The profile's system nearest the Main Hub (last waypoint towards Main, first waypoint from Main) is the jump endpoint; the rest is flown by gate without fuel cost."
      )
      .font(.caption)
      .foregroundStyle(
        setting.wrappedValue.jumpRouteProfileID == nil
          ? DesignTokens.caution : DesignTokens.textSecondary
      )
    }
    if !jumpFreighter.isEnabled {
      Text(
        "Jump logistics above is switched off, so hull, pilot, cargo and route profiles cannot be edited there. Its last saved values are still used for this leg."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.caution)
    }
    Text(
      "Hull, pilot and usable cargo come from the jump logistics above; fuel is the average Main-Hub sell price of the four racial isotopes."
    )
    .font(.caption)
    .foregroundStyle(DesignTokens.textSecondary)
  }

  @ViewBuilder
  private func serviceContent(
    setting: Binding<JumpFreighterServiceRate>
  ) -> some View {
    LabeledContent("Volume price") {
      HStack(spacing: DesignTokens.spacingSM) {
        TextField(
          "ISK per m³",
          value: setting.iskPerCubicMeter,
          format: .number.locale(AppLocalization.currentLanguage.locale)
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        Text("ISK / m³")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    LabeledContent("Collateral charge") {
      HStack(spacing: DesignTokens.spacingSM) {
        TextField(
          "Percent",
          value: percentBinding(setting.collateralRate),
          format: .number.locale(AppLocalization.currentLanguage.locale)
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        Text(verbatim: "%")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    LabeledContent("Contract volume limit") {
      HStack(spacing: DesignTokens.spacingSM) {
        TextField(
          "Maximum m³",
          value: setting.maximumContractVolumeM3,
          format: .number.locale(AppLocalization.currentLanguage.locale)
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        Text("m³")
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    Text(
      setting.wrappedValue.isComplete
        ? "Each contract costs volume × rate plus collateral × percentage, without rounding."
        : "Enter volume price and collateral percentage of the service; until then this leg stays unavailable."
    )
    .font(.caption)
    .foregroundStyle(
      setting.wrappedValue.isComplete
        ? DesignTokens.textSecondary : DesignTokens.caution
    )
  }

  private func isUsed(_ leg: HubTransportLeg) -> Bool {
    TradeMode.allCases.contains {
      configuration.legs(for: $0.route).contains(leg)
    }
  }

  private func settingBinding(
    for leg: HubTransportLeg
  ) -> Binding<HubTransportLegSetting> {
    Binding(
      get: {
        configuration.setting(
          for: leg,
          jumpFreighterEnabled: jumpFreighter.isEnabled
        )
      },
      set: { configuration.set($0) }
    )
  }

  private func percentBinding(_ fraction: Binding<Double?>) -> Binding<Double?> {
    Binding(
      get: { fraction.wrappedValue.map { $0 * 100 } },
      set: { fraction.wrappedValue = $0.map { $0 / 100 } }
    )
  }

  static func title(_ leg: HubTransportLeg) -> LocalizedStringKey {
    switch leg {
    case .mainToHome: "Main → Home"
    case .homeToMain: "Home → Main"
    case .homeToCoalition: "Home → Coalition"
    case .coalitionToHome: "Coalition → Home"
    case .mainToCoalition: "Main → Coalition (direct)"
    case .coalitionToMain: "Coalition → Main (direct)"
    }
  }
}

private struct JumpRouteProfileConfigurationEditor: View {
  @Binding var configuration: JumpFreighterLogisticsConfiguration
  @State private var pendingProfileDeletionID: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
      Divider()
      Text("Fixed jump-route profiles")
        .font(.headline)
      Text(
        "A profile fixes the ordered solar systems between the configured Home Hub and Coalition Hub. It may contain only intermediate systems or the complete route including both endpoints; matching endpoints are normalized. DOTLAN is then used only to verify every consecutive direct jump and its fuel, not to choose another path. You may assign the same profile to several ship classes deliberately."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      ForEach(JumpRouteClass.allCases) { routeClass in
        Picker(
          routeClass.displayName,
          selection: assignmentBinding(for: routeClass)
        ) {
          Text("Automatic DOTLAN route").tag(nil as UUID?)
          ForEach(configuration.routeProfiles) { profile in
            Text(profile.name).tag(Optional(profile.id))
          }
        }
      }

      if configuration.routeProfiles.isEmpty {
        Text(
          "No fixed route profile is configured. Every class currently uses automatic DOTLAN routing."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      ForEach($configuration.routeProfiles) { $profile in
        routeProfileEditor(profile: $profile)
      }

      Button {
        configuration.routeProfiles.append(
          JumpRouteProfile(
            name: AppLocalization.format(
              "Jump route %lld",
              Int64(configuration.routeProfiles.count + 1)
            ),
            waypoints: [JumpRouteWaypoint()]
          )
        )
      } label: {
        Label("Add jump-route profile", systemImage: "plus")
      }
    }
    .confirmationDialog(
      "Delete this jump-route profile?",
      isPresented: Binding(
        get: { pendingProfileDeletionID != nil },
        set: { isPresented in
          if !isPresented { pendingProfileDeletionID = nil }
        }
      )
    ) {
      Button("Delete route profile", role: .destructive) {
        guard let pendingProfileDeletionID else { return }
        configuration.removeRouteProfile(id: pendingProfileDeletionID)
        self.pendingProfileDeletionID = nil
      }
      Button("Cancel", role: .cancel) {
        pendingProfileDeletionID = nil
      }
    } message: {
      Text(
        "All class assignments that use this profile will return to automatic DOTLAN routing. The saved configuration changes only after you save the Production Basis."
      )
    }
  }

  private func routeProfileEditor(
    profile: Binding<JumpRouteProfile>
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        TextField("Route profile name", text: profile.name)
          .textFieldStyle(.roundedBorder)
        Button(role: .destructive) {
          pendingProfileDeletionID = profile.wrappedValue.id
        } label: {
          Label("Delete route profile", systemImage: "trash")
        }
        .labelStyle(.iconOnly)
      }

      if profile.wrappedValue.waypoints.isEmpty {
        Text(
          "This is a fixed direct route with no intermediate waypoint. It is valid only when DOTLAN verifies the Home-to-Coalition leg as one direct jump for the selected hull and pilot."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      ForEach(profile.waypoints) { waypoint in
        waypointEditor(
          waypoint: waypoint,
          profile: profile
        )
      }

      Button {
        profile.wrappedValue.waypoints.append(JumpRouteWaypoint())
      } label: {
        Label("Add route waypoint", systemImage: "plus.circle")
      }

      Text(
        profile.wrappedValue.isResolved
          ? "Profile systems are resolved. Each leg is validated for the actual ship and pilot during calculation."
          : "The profile is incomplete. A class assigned to it remains unavailable until every waypoint is selected from ESI and the profile has a name."
      )
      .font(.caption)
      .foregroundStyle(
        profile.wrappedValue.isResolved
          ? DesignTokens.positive : DesignTokens.caution
      )
    }
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }

  private func waypointEditor(
    waypoint: Binding<JumpRouteWaypoint>,
    profile: Binding<JumpRouteProfile>
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          SolarSystemPicker(
            selectedName: waypoint.wrappedValue.solarSystemName,
            selectedID: waypoint.wrappedValue.solarSystemID
          ) { option in
            waypoint.wrappedValue.solarSystemID = option.id
            waypoint.wrappedValue.solarSystemName = option.name
          }
          TextField(
            "Cyno structure or operational location (optional)",
            text: waypoint.structureName
          )
          .textFieldStyle(.roundedBorder)
          if !waypoint.wrappedValue.structureName.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty {
            EVEEntityText(
              value: waypoint.wrappedValue.structureName,
              font: .caption,
              accessibilityIdentifier:
                "settings.jump-route.\(profile.wrappedValue.id).waypoint.\(waypoint.wrappedValue.id).structure.copy"
            )
          }
        }
        Button(role: .destructive) {
          profile.wrappedValue.waypoints.removeAll {
            $0.id == waypoint.wrappedValue.id
          }
        } label: {
          Label("Remove route waypoint", systemImage: "minus.circle")
        }
        .labelStyle(.iconOnly)
      }
    }
  }

  private func assignmentBinding(
    for routeClass: JumpRouteClass
  ) -> Binding<UUID?> {
    Binding(
      get: { configuration.assignedProfileID(for: routeClass) },
      set: { configuration.assign(profileID: $0, to: routeClass) }
    )
  }
}

private struct EVESecurityStatusText: View {
  let securityStatus: Double
  let securityBand: SecurityBand

  private var displayStatus: Double {
    MarketSecurityBand.eveDisplayStatus(securityStatus) ?? securityStatus
  }

  var body: some View {
    HStack(spacing: DesignTokens.spacingXS) {
      Text(securityBand.displayName.localizedUI + " ·")
      Text(
        displayStatus.formatted(
          .number
            .locale(AppLocalization.currentLanguage.locale)
            .precision(.fractionLength(1))
        )
      )
      .foregroundStyle(eveColor)
      .fontWeight(.semibold)
    }
    .font(.body.monospacedDigit())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      securityBand.displayName.localizedUI
        + " "
        + displayStatus.formatted(
          .number
            .locale(AppLocalization.currentLanguage.locale)
            .precision(.fractionLength(1))
        )
    )
  }

  private var eveColor: Color {
    switch displayStatus {
    case 1...: Color(red: 44 / 255, green: 117 / 255, blue: 225 / 255)
    case 0.9...: Color(red: 57 / 255, green: 154 / 255, blue: 235 / 255)
    case 0.8...: Color(red: 78 / 255, green: 206 / 255, blue: 248 / 255)
    case 0.7...: Color(red: 96 / 255, green: 219 / 255, blue: 163 / 255)
    case 0.6...: Color(red: 113 / 255, green: 231 / 255, blue: 84 / 255)
    case 0.5...: Color(red: 245 / 255, green: 255 / 255, blue: 131 / 255)
    case 0.4...: Color(red: 220 / 255, green: 108 / 255, blue: 6 / 255)
    case 0.3...: Color(red: 206 / 255, green: 68 / 255, blue: 15 / 255)
    case 0.2...: Color(red: 187 / 255, green: 17 / 255, blue: 22 / 255)
    case 0.1...: Color(red: 115 / 255, green: 31 / 255, blue: 31 / 255)
    default: Color(red: 141 / 255, green: 49 / 255, blue: 99 / 255)
    }
  }
}

private struct ActivitySystemCollectionEditor: View {
  let rowTitle: LocalizedStringKey
  let addTitle: LocalizedStringKey
  let activity: IndustryActivitySystem
  @Binding var configurations: [ActivitySystemConfiguration]

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      ForEach($configurations) { $configuration in
        ActivitySystemRow(
          title: rowTitle,
          configuration: $configuration,
          canDelete: configurations.count > 1,
          onDelete: { remove(configuration.id) }
        )
      }
      Button {
        configurations.append(
          ActivitySystemConfiguration(
            activity: activity,
            solarSystemID: 0,
            solarSystemName: ""
          )
        )
      } label: {
        Label(addTitle, systemImage: "plus")
      }
    }
  }

  private func remove(_ id: UUID) {
    guard configurations.count > 1 else { return }
    configurations.removeAll { $0.id == id }
  }
}

private struct ActivitySystemRow: View {
  @Environment(RuntimeState.self) private var runtime
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
          EVESecurityStatusText(
            securityStatus: securityStatus,
            securityBand: configuration.securityBand
          )
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
  @Environment(RuntimeState.self) private var runtime
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
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(DesignTokens.positive)
          EVEEntityText(value: selectedName)
        } else {
          Label(
            query.count < 3
              ? "Enter at least 3 letters"
              : "Select a result from the ESI list",
            systemImage: "magnifyingglass"
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }
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
      }
      if let searchMessage {
        Label(searchMessage, systemImage: "info.circle")
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if !results.isEmpty {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            ForEach(results) { option in
              Button {
                onSelect(option)
                query = ""
                isShowingResults = false
              } label: {
                Text(option.name)
                  .frame(maxWidth: .infinity, alignment: .leading)
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
      width: 560,
      height: 400,
      alignment: .topLeading
    )
  }

  private func scheduleSearch(_ value: String) {
    searchTask?.cancel()
    searchMessage = nil
    let accepted = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted.count >= 3 else {
      results = []
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
  @Environment(RuntimeState.self) private var runtime
  @Binding var structure: ConfiguredIndustryStructure
  let configuredSystems: [ActivitySystemConfiguration]
  let authorizations: [AuthorizationSnapshot]
  let capabilities: [CharacterCapabilitySnapshot]
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

  private var enabledActivities: [IndustryActivitySystem] {
    IndustryActivitySystem.allCases.filter {
      structure.enabledActivities.contains($0)
    }
  }

  private var activityAssignmentModeBinding: Binding<IndustryStructureActivityAssignmentMode> {
    Binding(
      get: { structure.effectiveActivityAssignmentMode },
      set: { structure.setActivityAssignmentMode($0) }
    )
  }

  private var structureKindBinding: Binding<IndustryStructureKind> {
    Binding(
      get: { structure.kind },
      set: { kind in
        guard structure.kind != kind else { return }
        structure.kind = kind
        applyStructureKind(kind)
      }
    )
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
        if structure.solarSystemID != system.solarSystemID {
          structure.structureID = nil
          structure.eveStructureName = nil
          structure.ownerCorporationID = nil
        }
        structure.manufacturingSystemID = system.id
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

      Picker(
        "Physical solar system",
        selection: locationBinding
      ) {
        Text("Not assigned").tag(UUID?.none)
        ForEach(configuredLocations) { system in
          Text(
            (system.solarSystemName.isEmpty
              ? "Select system" : system.solarSystemName)
              + " · " + String(system.solarSystemID)
          )
          .tag(Optional(system.id))
        }
      }

      SystemFacilityPicker(
        authorizations: authorizations,
        clientID: clientID,
        solarSystemID: structure.solarSystemID,
        solarSystemName: structure.solarSystemName,
        onSelectStation: applyNPCStation,
        onSelectStructure: applyPlayerStructure
      )

      if let eveName = structure.eveStructureName,
        let structureID = structure.structureID
      {
        LabeledContent("Linked ESI location") {
          VStack(alignment: .trailing, spacing: DesignTokens.spacingXS) {
            EVEEntityText(value: eveName)
            Text(String(structureID))
              .font(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
        Text(
          "The linked ESI location belongs to the selected physical solar system. Its EVE name and location ID remain stored with the profile."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }

      if structure.structureID == nil {
        Label(
          "This entry defines a structure type and solar system, but it is not yet linked to an exact EVE station or Player Structure. Link the matching ESI result above so Warehouse can match asset locations.",
          systemImage: "link.badge.plus"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
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
          Picker("Structure / station type", selection: structureKindBinding) {
            ForEach(IndustryStructureKind.selectableCases) { kind in
              Text(LocalizedStringKey(kind.displayName)).tag(kind)
            }
          }
          LabeledContent("Security") {
            if let status = structure.securityStatus {
              EVESecurityStatusText(
                securityStatus: status,
                securityBand: structure.securityBand
              )
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
              structure.kind.defaultFacilityTaxRate.map {
                AppLocalization.format(
                  "Standard %@",
                  $0.formatted(.percent)
                )
              } ?? AppLocalization.text("Facility tax"),
              value: $structure.enteredFacilityTaxRate,
              format: .percent
            )
            .multilineTextAlignment(.trailing)
            .frame(width: DesignTokens.compactNumberWidth)
          }
          if structure.kind.defaultFacilityTaxRate != nil {
            Text(
              AppLocalization.text(
                "Leave the facility tax empty to use the structure standard of 1% for Manufacturing, Reactions and Science."
              )
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          }
          if structure.hasReprocessingService {
            LabeledContent("Structure Reprocessing bonus") {
              Text(
                formatPercent(
                  structure.reprocessingEfficiencyBonusPercent
                    ?? structure.kind
                    .defaultReprocessingEfficiencyBonusPercent
                )
              )
              .font(.body.monospacedDigit())
            }
            LabeledContent("Reprocessing tax") {
              TextField(
                structure.kind.defaultReprocessingTaxRate.map {
                  AppLocalization.format(
                    "Standard %@",
                    $0.formatted(.percent)
                  )
                } ?? AppLocalization.text("Unknown"),
                value: $structure.reprocessingTaxRate,
                format: .percent
              )
              .multilineTextAlignment(.trailing)
              .frame(width: DesignTokens.compactNumberWidth)
            }
            Text(
              AppLocalization.text(
                structure.kind.defaultReprocessingTaxRate == nil
                  ? "Enter the tax shown by EVE. Leave it empty when unknown; enter 0% only for a confirmed fee-free facility."
                  : "Enter the tax shown by EVE. Leave it empty to use the structure standard of 1%; enter 0% only for a confirmed fee-free facility."
              )
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
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

      if structure.hasReprocessingService {
        Divider()
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          Text("Planned refiner").font(.headline)
          Label(
            "The selected implant is only a planning assumption for this facility. It is not read from the character's current clone and does not need to be installed while planning.",
            systemImage: "brain.head.profile"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          Button {
            structure.reprocessingCharacterID = nil
          } label: {
            Label(
              "Automatically choose planned refiner per ore",
              systemImage:
                structure.reprocessingCharacterID == nil
                ? "checkmark.circle.fill" : "circle"
            )
          }
          .buttonStyle(.plain)
          if structure.reprocessingCharacterID == nil {
            Text(
              "In automatic mode, every character is compared using the planned implant shown next to that character."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.leading, 28)
          }
          ForEach(
            capabilities.sorted {
              $0.character.name.localizedCaseInsensitiveCompare(
                $1.character.name
              ) == .orderedAscending
            }
          ) { capability in
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              HStack(spacing: DesignTokens.spacingSM) {
                Button {
                  structure.reprocessingCharacterID = capability.character.id
                } label: {
                  Image(
                    systemName:
                      structure.reprocessingCharacterID
                      == capability.character.id
                      ? "checkmark.circle.fill" : "circle"
                  )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                  AppLocalization.format(
                    "Select %@ for Reprocessing",
                    capability.character.name
                  )
                )
                EVEEntityText(value: capability.character.name)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                  Text("Planned implant")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                  Picker(
                    "Planned implant",
                    selection: implantBinding(
                      for: capability.character.id
                    )
                  ) {
                    ForEach(OreRefiningImplant.allCases) { implant in
                      Text(implantPickerLabel(implant)).tag(implant)
                    }
                  }
                  .labelsHidden()
                  .frame(width: 120)
                  .accessibilityHint(
                    "This is a planning assumption and is not read from the character's current clone."
                  )
                }
                Text(
                  AppLocalization.text(capability.skills.state.rawValue)
                    .capitalized
                )
                .font(.caption)
                .foregroundStyle(
                  capability.skills.state == .fresh
                    ? DesignTokens.positive : DesignTokens.caution
                )
              }
              let implant = structure.reprocessingImplant(
                for: capability.character.id
              )
              if let typeID = implant.typeID {
                HStack(spacing: DesignTokens.spacingSM) {
                  EVEItemText(
                    value: implant.name,
                    typeID: typeID,
                    font: .caption
                  )
                  Spacer()
                  Text(
                    AppLocalization.format(
                      "+%@ Reprocessing yield",
                      implant.yieldBonusPercent.formatted(
                        .number.precision(.fractionLength(0))
                      ) + "%"
                    )
                  )
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(DesignTokens.positive)
                }
                .padding(.leading, 28)
              }
            }
          }
          if capabilities.isEmpty {
            Label(
              "No connected character skill snapshots are available.",
              systemImage: "person.crop.circle.badge.questionmark"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
          }
          let normalYieldBasis = structure.reprocessingYieldBasis(
            for: .asteroidOre
          )
          LabeledContent("Configured Reprocessing source") {
            if let normalYieldBasis,
              let sourceTypeID = normalYieldBasis.sourceTypeID
            {
              EVEItemText(
                value: normalYieldBasis.sourceName,
                typeID: sourceTypeID,
                font: .body,
                lineLimit: 2,
                accessibilityIdentifier:
                  "settings.refining.source.\(structure.id).copy"
              )
            } else if let normalYieldBasis {
              EVEEntityText(
                value: normalYieldBasis.sourceName,
                font: .body,
                lineLimit: 2,
                accessibilityIdentifier:
                  "settings.refining.source.\(structure.id).copy"
              )
            } else {
              Text("Unavailable")
                .foregroundStyle(DesignTokens.caution)
            }
          }
          LabeledContent("Equipment yield after security-space bonus") {
            Text(
              normalYieldBasis?.equipmentYieldMultiplier.formatted(
                .percent.precision(.fractionLength(0...2))
              ) ?? "Unavailable".localizedUI
            )
            .font(.body.monospacedDigit())
          }
          LabeledContent("Structure Reprocessing bonus") {
            Text(
              normalYieldBasis?.structureBonusPercent.formatted(
                .percent.scale(1).precision(.fractionLength(0...2))
              ) ?? "Unavailable".localizedUI
            )
            .font(.body.monospacedDigit())
          }
          LabeledContent("Facility base yield before character") {
            Text(
              normalYieldBasis?.effectiveYieldMultiplier.formatted(
                .percent.precision(.fractionLength(0...2))
              ) ?? "Unavailable".localizedUI
            )
            .font(.body.monospacedDigit())
          }
          if normalYieldBasis?.sourceKind == .serviceModule,
            structure.kind == .tatara
          {
            Label {
              VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text(
                  "No configured compatible Reprocessing rig improves this Tatara. The calculation therefore uses the Reprocessing service plus the Tatara hull bonus."
                )
                HStack(spacing: DesignTokens.spacingXS) {
                  Text(
                    "For the approximately 90.6% case, verify whether the structure actually has"
                  )
                  EVEItemText(
                    value: "Standup L-Set Reprocessing Monitor II",
                    typeID: 46_640,
                    font: .caption,
                    lineLimit: 2,
                    accessibilityIdentifier:
                      "settings.refining.recommended-rig.\(structure.id).copy"
                  )
                  Text("fitted and add that exact rig below.")
                }
              }
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.caution)
          }
          Text(
            "Automatic mode uses the connected character with the highest complete result from Reprocessing, Reprocessing Efficiency, ore-specific Processing and the selected implant. A fixed character remains fixed even when another character would yield more."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }
      }

      Divider()
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        Text("Use structure for").font(.headline)
        Picker(
          "Activity assignment",
          selection: activityAssignmentModeBinding
        ) {
          ForEach(IndustryStructureActivityAssignmentMode.allCases) { mode in
            Text(LocalizedStringKey(mode.displayName)).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: DesignTokens.efficiencyLabelMinimum),
              spacing: DesignTokens.spacingSM
            )
          ],
          alignment: .leading,
          spacing: DesignTokens.spacingXS
        ) {
          ForEach(IndustryActivitySystem.allCases) { activity in
            Toggle(
              LocalizedStringKey(activity.displayName),
              isOn: activityBinding(for: activity)
            )
            .disabled(
              structure.effectiveActivityAssignmentMode
                == .automaticFromServiceModules
            )
          }
        }

        if structure.effectiveActivityAssignmentMode
          == .automaticFromServiceModules
        {
          Text(
            "The installed service modules below determine the enabled activities automatically. Switch to Manual selection when the module evidence is unavailable or you need an explicit override."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        } else {
          Text(
            "Manual selection is stored explicitly and may enable several uses for the same physical structure. Service modules remain visible as supporting evidence."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        }

        if enabledActivities.isEmpty {
          Label(
            "Select at least one activity for this structure.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
        } else {
          LabeledContent("Enabled activities") {
            Text(
              enabledActivities.map { $0.displayName.localizedUI }
                .joined(separator: ", ")
            )
            .multilineTextAlignment(.trailing)
          }
        }

        let eligible = Set(eligibleActivities)
        let missingSystemActivities = structure.enabledActivities.subtracting(
          eligible
        )
        if !missingSystemActivities.isEmpty {
          Label(
            AppLocalization.text(
              "Not eligible for facility selection; check system, structure type and security: "
            )
              + missingSystemActivities.sorted { $0.rawValue < $1.rawValue }
              .map { $0.displayName.localizedUI }
              .joined(separator: ", "),
            systemImage: "location.slash"
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
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
      structure.manufacturingSystemID = matchingSystem.id
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

  private func applyNPCStation(_ option: TradingLocationSearchOption) {
    guard option.solarSystemID == structure.solarSystemID else { return }
    structure.structureID = option.id
    structure.eveStructureName = option.name
    structure.ownerCorporationID = option.ownerCorporationID
    structure.kind = .npcStation
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
    if structure.name.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty {
      structure.name = option.name
    }
  }

  private func activityBinding(
    for activity: IndustryActivitySystem
  ) -> Binding<Bool> {
    Binding(
      get: { structure.enabledActivities.contains(activity) },
      set: { structure.setActivity(activity, enabled: $0) }
    )
  }

  private func implantBinding(
    for characterID: Int64
  ) -> Binding<OreRefiningImplant> {
    Binding(
      get: { structure.reprocessingImplant(for: characterID) },
      set: { structure.setReprocessingImplant($0, for: characterID) }
    )
  }

  private func implantPickerLabel(_ implant: OreRefiningImplant) -> String {
    guard implant != .none else { return "No implant".localizedUI }
    return AppLocalization.format(
      "+%@ yield",
      implant.yieldBonusPercent.formatted(
        .number.precision(.fractionLength(0))
      ) + "%"
    )
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
            HStack(spacing: DesignTokens.spacingXS) {
              EVEItemIcon(typeID: definition.typeID, size: 18)
              Text(definition.name)
            }
            .tag(Optional(definition.typeID))
          }
        }
        .frame(maxWidth: .infinity)
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
            HStack(spacing: DesignTokens.spacingXS) {
              EVEItemIcon(typeID: definition.typeID, size: 18)
              Text(definition.name)
            }
            .tag(Optional(definition.typeID))
          }
        }
        .frame(maxWidth: .infinity)
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "minus.circle")
        }
        .accessibilityLabel("Remove rig")
      }
      HStack(spacing: DesignTokens.spacingLG) {
        if let asteroidYield = rig.reprocessingYieldMultiplier(
          for: .asteroidOre,
          in: securityBand
        ) {
          LabeledContent("Asteroid ore yield") {
            Text(
              asteroidYield.formatted(
                .percent.precision(.fractionLength(0...2))
              )
            )
            .font(.body.monospacedDigit())
          }
        }
        if let moonYield = rig.reprocessingYieldMultiplier(
          for: .moonOre,
          in: securityBand
        ) {
          LabeledContent("Moon ore yield") {
            Text(
              moonYield.formatted(
                .percent.precision(.fractionLength(0...2))
              )
            )
            .font(.body.monospacedDigit())
          }
        }
        if let iceYield = rig.reprocessingYieldMultiplier(
          for: .ice,
          in: securityBand
        ) {
          LabeledContent("Ice yield") {
            Text(
              iceYield.formatted(
                .percent.precision(.fractionLength(0...2))
              )
            )
            .font(.body.monospacedDigit())
          }
        }
        if rig.normalOreYieldMultiplier == nil,
          rig.moonOreYieldMultiplier == nil,
          rig.iceYieldMultiplier == nil
        {
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

struct MarketSettingsView: View {
  @Environment(RuntimeState.self) private var runtime
  @EnvironmentObject private var profileNavigationGuard: ProfileNavigationGuard
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredProductionBasis.updatedAt, order: .reverse)
  private var storedBases: [StoredProductionBasis]
  @Query(sort: \StoredCharacter.characterName)
  private var characters: [StoredCharacter]

  @State private var didLoad = false
  @State private var savedBasis: ProductionBasis?
  @State private var statusMessage: String?
  @State private var refreshingFeeLocationID: UUID?
  @State private var feeMessages: [UUID: String] = [:]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        header
        roleConfiguration
        addMarketConfiguration
        configuredMarkets
        PublicContractRegionSettingsPanel()
        profitabilityConfiguration
      }
      .padding(DesignTokens.spacingLG)
    }
    .navigationTitle("Market Settings")
    .task {
      loadStoredBasisOnce()
      runtime.productionBasis.refreshResolvableMarketFees(
        capabilities: capabilitySnapshots
      )
      savedBasis = runtime.productionBasis
      profileNavigationGuard.updateDirtyState(false)
    }
    .onChange(of: runtime.productionBasis) { _, value in
      guard let savedBasis else { return }
      profileNavigationGuard.updateDirtyState(value != savedBasis)
    }
    .onChange(of: profileNavigationGuard.saveRequestID) { save() }
    .onChange(of: profileNavigationGuard.discardRequestID) {
      if let savedBasis { runtime.productionBasis = savedBasis }
      profileNavigationGuard.completeDiscard()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text("Market Settings")
        .font(.largeTitle.bold())
      Text(
        "One shared market configuration for Planner, Moon and mineral purchase analysis, reactions and every other price comparison. The selected Main, Home and Coalition Hubs plus every selected comparison market are loaded."
      )
      .foregroundStyle(DesignTokens.textSecondary)
      HStack {
        Button("Save Market Settings") { save() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut("s", modifiers: .command)
        if profileNavigationGuard.hasUnsavedChanges {
          Label("Unsaved changes", systemImage: "exclamationmark.triangle.fill")
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

  private var roleConfiguration: some View {
    Panel(title: "Hub Roles") {
      Picker("Main Hub", selection: mainBinding) {
        ForEach(npcMarkets) { market in
          Text(market.location.name).tag(market.id)
        }
      }
      Text(
        "The Main Hub is the default price and purchase market. Jita, Amarr, Rens and Hek are built in; every ESI-resolved NPC station you add also becomes selectable."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Picker("Home Hub", selection: homeBinding) {
        Text("Not configured").tag(UUID?.none)
        ForEach(runtime.productionBasis.tradingLocations) { market in
          Text(market.location.name).tag(Optional(market.id))
        }
      }

      Picker("Coalition Hub", selection: coalitionBinding) {
        Text("Not configured").tag(UUID?.none)
        ForEach(playerStructureMarkets) { market in
          Text(market.location.name).tag(Optional(market.id))
        }
      }
      Text(
        "A Coalition Hub must be an authenticated ESI Player Structure. Search visibility confirms that ESI can resolve it; market access is still reported from the actual structure-market request."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      if runtime.productionBasis.mainAndHomeAreIdentical {
        Label(
          "Main Hub and Home Hub are identical. Hub-to-home logistics costs are disabled.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(DesignTokens.positive)
      }

      Divider()
      Text("Additional comparison markets")
        .font(.headline)
      Text(
        "Select every additional market that should be loaded alongside the assigned hub roles. Markets already assigned as Main, Home or Coalition Hub are included automatically."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      ForEach(comparisonMarketCandidates) { market in
        Toggle(isOn: comparisonBinding(market.id)) {
          HStack(spacing: DesignTokens.spacingSM) {
            EVEEntityLabel(
              value: market.location.name,
              font: .body
            )
            Spacer()
            if hasAssignedHubRole(market.id) {
              Text("Included through hub role")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
          }
        }
        .disabled(hasAssignedHubRole(market.id))
        .accessibilityIdentifier(
          "market-settings.comparison.\(market.id.uuidString)"
        )
      }
    }
  }

  private var addMarketConfiguration: some View {
    Panel(title: "Add Markets") {
      Text("Built-in Main Hub stations")
        .font(.headline)
      HStack {
        ForEach(MarketTradeHub.defaultMainHubChoices) { hub in
          Button {
            _ = runtime.productionBasis.addTradingLocation(
              hub.procurementLocation
            )
          } label: {
            Label(hub.rawValue.capitalized, systemImage: "plus.circle")
          }
          .disabled(
            runtime.productionBasis.tradingLocations.contains {
              $0.location.locationID == hub.stationID
            }
          )
        }
      }

      Divider()
      TradingLocationESIPicker(
        authorizations: authorizationSnapshots,
        clientID: clientID,
        title: "Add NPC Station or Player Structure",
        explanation:
          "NPC stations are public ESI results. Player Structures require a connected character with structure-search and structure-detail scopes."
      ) { location in
        if runtime.productionBasis.addTradingLocation(location) {
          statusMessage = "Added \(location.name). Save Market Settings to keep it."
        }
      }
    }
  }

  private var configuredMarkets: some View {
    Panel(title: "Available Hub Locations") {
      ForEach(runtime.productionBasis.tradingLocations) { market in
        marketCard(market)
      }
    }
  }

  private var profitabilityConfiguration: some View {
    Panel(title: "Market Parameters") {
      Text(
        "Define optional profitability thresholds for sales. They are stored with this Production Basis so Planner comparisons and future market filters can use the same values."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      LabeledContent("Minimum sales margin") {
        TextField(
          "Not configured",
          value: minimumSalesMarginBinding,
          format: .percent.precision(.fractionLength(0...2))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        .accessibilityIdentifier("market-settings.minimum-sales-margin")
      }
      LabeledContent("Target sales margin") {
        TextField(
          "Not configured",
          value: targetSalesMarginBinding,
          format: .percent.precision(.fractionLength(0...2))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        .accessibilityIdentifier("market-settings.target-sales-margin")
      }

      if !runtime.productionBasis.marketProfitability.isValid {
        Label(
          "The target sales margin must be at least as high as the minimum sales margin.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
      Text(
        "Sales margin means profit divided by net sale revenue after Sales Tax and Broker Fee. Leave a value empty when no threshold should be applied; an empty value is not treated as 0%."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func marketCard(
    _ configuration: TradingLocationConfiguration
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          EVEEntityText(value: configuration.location.name)
          Text(locationKindText(configuration.location.kind))
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        ForEach(
          roles(for: configuration).sorted { $0.rawValue < $1.rawValue },
          id: \.self
        ) { role in
          Text(role.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(roleColor(role).opacity(0.18))
            .foregroundStyle(roleColor(role))
            .clipShape(Capsule())
        }
        if !hasAssignedHubRole(configuration.id) {
          Button(role: .destructive) {
            _ = runtime.productionBasis.removeTradingLocation(
              id: configuration.id
            )
          } label: {
            Label("Remove", systemImage: "minus.circle")
          }
          .buttonStyle(.borderless)
        }
      }

      if configuration.location.kind == .legacy
        || configuration.location.locationID == nil
      {
        Label(
          "This migrated location must be resolved and replaced here.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
        TradingLocationESIPicker(
          authorizations: authorizationSnapshots,
          clientID: clientID,
          title: "Resolve this location through ESI",
          explanation:
            "Select the matching ESI location. Roles, trader and stored fee context are retained.",
          initialQuery: searchQuery(for: configuration.location.name),
          showsNPCStationSearch: true,
          selectionConfirmationKey: "Replaced with %@."
        ) { location in
          _ = runtime.productionBasis.replaceTradingLocation(
            id: configuration.id,
            with: location
          )
        }
        .id(configuration.id)
      }

      Toggle(
        "Only market in its region",
        isOn: onlyMarketInRegionBinding(configuration.id)
      )
      .accessibilityIdentifier(
        "market-settings.only-market-in-region.\(configuration.id.uuidString)"
      )
      Text(
        "Turn this on only when no other station or structure in this region has a market. The Trade area then shows the regional ESI market history as this hub's traded volume, marked “(region)”. ESI offers no market history per station or structure."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      Picker("Trader", selection: traderBinding(configuration.id)) {
        Text("No trader selected").tag(Int64?.none)
        ForEach(characters) { character in
          Text(character.characterName).tag(Optional(character.characterID))
        }
      }
      LabeledContent("Sales Tax") {
        Text(rateText(configuration.marketTaxes.effectiveSalesTaxRate))
      }
      LabeledContent("Broker Fee used in calculations") {
        Text(rateText(configuration.marketTaxes.effectiveBrokerFeeRate))
      }
      LabeledContent("Automatic broker fee") {
        Text(rateText(configuration.marketTaxes.automaticBrokerFeeRate))
      }
      LabeledContent("Manual broker fee fallback") {
        TextField(
          "Enter broker fee",
          value: manualBrokerFeeBinding(configuration.id),
          format: .percent.precision(.fractionLength(0...3))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
      }
      brokerFeeFallbackStatus(configuration.marketTaxes)
      if let updatedAt = configuration.marketTaxes.manualBrokerFeeUpdatedAt {
        LabeledContent("Manual value updated") {
          Text(updatedAt.formatted())
            .font(.caption.monospacedDigit())
        }
      }
      Divider()
      LabeledContent("Public-contract fee rate") {
        TextField(
          "Not configured",
          value: publicContractFeeBinding(configuration.id),
          format: .percent.precision(.fractionLength(0...3))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: DesignTokens.compactNumberWidth)
        .accessibilityIdentifier(
          "market-settings.public-contract-fee.\(configuration.id.uuidString)"
        )
      }
      Text(
        "Enter the combined non-refundable fee rate shown by EVE for a public Item Exchange sale. CCP documents the contract workflow, but does not publish the personal creation-fee formula, and ESI provides no fee preview for a hypothetical contract. The Planner deducts this value only from Contract Sale; a refundable deposit is not counted as cost. Leave it empty when the current fee is not known."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      if let evidence = configuration.observedPublicContractFee,
        let rate = evidence.effectiveRate,
        let fee = evidence.totalNonRefundableFee
      {
        LabeledContent("Latest observed public-contract fee") {
          Text(rateText(rate))
            .monospacedDigit()
        }
        Text(
          "Observed from one completed public Item Exchange at this exact location: \(iskText(evidence.contractPrice)) contract price, \(iskText(evidence.brokerFee)) broker fee plus \(iskText(evidence.salesTax)) contract sales tax, \(iskText(fee)) total. Observed \(evidence.observedAt.formatted()). This is historical evidence, not an ESI quote for a new contract."
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
        Button("Use observed rate for planning") {
          _ = runtime.productionBasis.confirmObservedPublicContractFee(
            forTradingLocationID: configuration.id
          )
        }
        .disabled(configuration.publicContractFeeRate == rate)
        .accessibilityIdentifier(
          "market-settings.use-observed-public-contract-fee.\(configuration.id.uuidString)"
        )
      }
      Button {
        Task { await refreshFees(configuration.id) }
      } label: {
        if refreshingFeeLocationID == configuration.id {
          ProgressView()
        } else {
          Label("Refresh trader fees from ESI", systemImage: "arrow.clockwise")
        }
      }
      .disabled(
        refreshingFeeLocationID != nil
          || configuration.traderCharacterID == nil
      )
      if let message = feeMessages[configuration.id] {
        Text(message).font(.caption).foregroundStyle(DesignTokens.textSecondary)
      }
      Divider()
    }
  }

  private var npcMarkets: [TradingLocationConfiguration] {
    runtime.productionBasis.tradingLocations.filter {
      $0.location.kind == .npcTradeHub
        && $0.location.locationID != nil
        && $0.location.solarSystemID != nil
        && $0.location.regionID != nil
    }
  }

  private var playerStructureMarkets: [TradingLocationConfiguration] {
    runtime.productionBasis.tradingLocations.filter {
      $0.location.kind == .playerStructure && $0.location.locationID != nil
    }
  }

  private var comparisonMarketCandidates: [TradingLocationConfiguration] {
    runtime.productionBasis.tradingLocations.filter {
      switch $0.location.kind {
      case .npcTradeHub:
        $0.location.locationID != nil
          && $0.location.solarSystemID != nil
          && $0.location.regionID != nil
      case .playerStructure:
        $0.location.locationID != nil && $0.location.solarSystemID != nil
      case .legacy:
        false
      }
    }
  }

  private var mainBinding: Binding<UUID> {
    Binding(
      get: {
        runtime.productionBasis.mainTradingLocationID
          ?? npcMarkets.first?.id
          ?? UUID()
      },
      set: { runtime.productionBasis.setMainTradingLocation(id: $0) }
    )
  }

  private var homeBinding: Binding<UUID?> {
    Binding(
      get: { runtime.productionBasis.homeTradingLocationID },
      set: { runtime.productionBasis.setHomeTradingLocation(id: $0) }
    )
  }

  private var coalitionBinding: Binding<UUID?> {
    Binding(
      get: { runtime.productionBasis.coalitionTradingLocationID },
      set: { runtime.productionBasis.setCoalitionTradingLocation(id: $0) }
    )
  }

  private func comparisonBinding(_ id: UUID) -> Binding<Bool> {
    Binding(
      get: {
        hasAssignedHubRole(id)
          || runtime.productionBasis.comparisonTradingLocationIDs.contains(id)
      },
      set: { isSelected in
        runtime.productionBasis.setComparisonTradingLocation(
          id: id,
          isSelected: isSelected
        )
      }
    )
  }

  private func hasAssignedHubRole(_ id: UUID) -> Bool {
    id == runtime.productionBasis.mainTradingLocationID
      || id == runtime.productionBasis.homeTradingLocationID
      || id == runtime.productionBasis.coalitionTradingLocationID
  }

  private func roles(
    for configuration: TradingLocationConfiguration
  ) -> Set<MarketHubRole> {
    runtime.productionBasis.marketHubSnapshots.first {
      $0.id == configuration.id
    }?.roles ?? []
  }

  private func roleColor(_ role: MarketHubRole) -> Color {
    switch role {
    case .main: DesignTokens.positive
    case .home: DesignTokens.highlight
    case .coalition: DesignTokens.accent
    case .comparison: DesignTokens.caution
    }
  }

  private func locationKindText(_ kind: ProcurementLocationKind) -> String {
    switch kind {
    case .npcTradeHub: "NPC station"
    case .playerStructure: "ESI Player Structure"
    case .legacy: "Unresolved migrated location"
    }
  }

  private func rateText(_ rate: Double?) -> String {
    guard let rate else { return "Unavailable" }
    return rate.formatted(.percent.precision(.fractionLength(0...3)))
  }

  private func iskText(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(AppLocalization.currentLanguage.locale)
        .grouping(.automatic)
        .precision(.fractionLength(0...2))
    ) + " ISK"
  }

  private var minimumSalesMarginBinding: Binding<Double?> {
    Binding(
      get: {
        runtime.productionBasis.marketProfitability.minimumSalesMarginRate
      },
      set: { rate in
        runtime.productionBasis.marketProfitability
          .setMinimumSalesMarginRate(rate)
      }
    )
  }

  private var targetSalesMarginBinding: Binding<Double?> {
    Binding(
      get: {
        runtime.productionBasis.marketProfitability.targetSalesMarginRate
      },
      set: { rate in
        runtime.productionBasis.marketProfitability
          .setTargetSalesMarginRate(rate)
      }
    )
  }

  private func searchQuery(for name: String) -> String {
    let system =
      name.components(separatedBy: " - ").first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? name
    return system.count >= 3 ? system : name
  }

  private func onlyMarketInRegionBinding(_ id: UUID) -> Binding<Bool> {
    Binding(
      get: {
        runtime.productionBasis.tradingLocations.first { $0.id == id }?
          .isOnlyMarketInRegion ?? false
      },
      set: {
        runtime.productionBasis.setOnlyMarketInRegion($0, forTradingLocationID: id)
      }
    )
  }

  private func traderBinding(_ id: UUID) -> Binding<Int64?> {
    Binding(
      get: {
        runtime.productionBasis.tradingLocations.first { $0.id == id }?
          .traderCharacterID
      },
      set: { characterID in
        let capability = capabilitySnapshots.first {
          $0.character.id == characterID
        }
        runtime.productionBasis.selectTrader(
          characterID: characterID,
          forTradingLocationID: id,
          capability: capability
        )
      }
    )
  }

  private func manualBrokerFeeBinding(_ id: UUID) -> Binding<Double?> {
    Binding(
      get: {
        runtime.productionBasis.tradingLocations.first { $0.id == id }?
          .marketTaxes.manualBrokerFeeRate
      },
      set: { rate in
        runtime.productionBasis.setManualBrokerFeeRate(
          rate,
          forTradingLocationID: id
        )
      }
    )
  }

  private func publicContractFeeBinding(_ id: UUID) -> Binding<Double?> {
    Binding(
      get: {
        runtime.productionBasis.tradingLocations.first { $0.id == id }?
          .publicContractFeeRate
      },
      set: { rate in
        runtime.productionBasis.setPublicContractFeeRate(
          rate,
          forTradingLocationID: id
        )
      }
    )
  }

  @ViewBuilder
  private func brokerFeeFallbackStatus(
    _ taxes: MarketTaxConfiguration
  ) -> some View {
    if taxes.automaticBrokerFeeRate != nil {
      Text(
        "The calculated NPC-station broker fee is active. A saved manual fallback is not used while this value is available."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    } else if taxes.isManualBrokerFeeFallbackActive {
      Label(
        "Manual fallback is active and is included in all calculations for this market.",
        systemImage: "pencil.circle.fill"
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.caution)
    } else {
      Text(
        "Enter the broker fee shown in EVE when ESI cannot provide or derive it. Unknown remains unavailable."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.caution)
    }
  }

  private var clientID: String {
    EVEConstants.ssoClientID
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
    characters.compactMap { character in
      character.capabilitySnapshot.flatMap {
        try? JSONDecoder().decode(CharacterCapabilitySnapshot.self, from: $0)
      }
    }
  }

  private func refreshFees(_ id: UUID) async {
    guard
      let market = runtime.productionBasis.tradingLocations.first(
        where: { $0.id == id }
      ), let characterID = market.traderCharacterID,
      let storedCharacter = characters.first(where: {
        $0.characterID == characterID
      }), !clientID.isEmpty
    else {
      feeMessages[id] = "Select a connected trader and configure the EVE client ID first."
      return
    }
    refreshingFeeLocationID = id
    defer { refreshingFeeLocationID = nil }
    do {
      let authorization = try JSONDecoder().decode(
        AuthorizationSnapshot.self,
        from: storedCharacter.authorizationSnapshot
      )
      let capability = try await runtime.syncCharacterCapabilities(
        authorization: authorization,
        clientID: clientID
      )
      let contractFeeEvidence = try? await runtime.syncPublicContractFeeEvidence(
        authorization: authorization,
        clientID: clientID
      )
      storedCharacter.capabilitySnapshot = try JSONEncoder().encode(capability)
      storedCharacter.lastSyncAt = .now
      try modelContext.save()
      if market.location.kind == .npcTradeHub {
        if let resolved = try? await runtime.resolveNPCTradingLocation(
          market.location
        ) {
          runtime.productionBasis.updateTradingLocation(
            id: id,
            location: resolved
          )
        }
      }
      runtime.productionBasis.applyMarketFees(
        capability: capability,
        forTradingLocationID: id
      )
      let refreshedMarket = runtime.productionBasis.tradingLocations.first {
        $0.id == id
      }
      var messages: [String] = []
      if refreshedMarket?.marketTaxes.automaticBrokerFeeRate != nil {
        messages.append(
          "Trader skills, standings and NPC-station broker fee refreshed from ESI."
        )
      } else if refreshedMarket?.marketTaxes.isManualBrokerFeeFallbackActive == true {
        messages.append(
          "The automatic broker fee remains unavailable; the saved manual fallback is active."
        )
      } else if market.location.kind == .playerStructure {
        messages.append(
          "ESI does not expose the owner-defined Player Structure broker fee. Enter it manually."
        )
      } else {
        messages.append(
          "The broker fee could not be derived from the available ESI data. Enter it manually."
        )
      }
      if let contractFeeEvidence,
        let locationID = refreshedMarket?.location.locationID,
        let observed = contractFeeEvidence.value?
          .latestCompleteObservation(at: locationID),
        runtime.productionBasis.setObservedPublicContractFee(
          observed,
          forTradingLocationID: id
        )
      {
        messages.append(
          String(
            localized:
              "A complete recent public-contract fee was observed. Review it before applying the rate to planning."
          )
        )
      } else if contractFeeEvidence?.state == .forbidden {
        messages.append(
          String(
            localized:
              "Public-contract fee evidence needs both the character-contract and character-wallet ESI scopes. The saved value was not replaced."
          )
        )
      } else if contractFeeEvidence?.state == .partial {
        messages.append(
          String(
            localized:
              "Recent contract data was incomplete or contained an unsupported combined deposit/tax entry. The saved value was not replaced."
          )
        )
      } else {
        messages.append(
          String(
            localized:
              "No complete matching public Item Exchange fee was found in the recent ESI history. The saved value was not replaced."
          )
        )
      }
      feeMessages[id] = messages.joined(separator: " ")
    } catch {
      feeMessages[id] = String(
        localized: "Fee refresh unavailable. Check authorization and retry."
      )
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
  }

  private func save() {
    runtime.productionBasis.normalizeTradingLocations()
    guard runtime.productionBasis.marketProfitability.isValid else {
      statusMessage =
        "The target sales margin must be at least as high as the minimum sales margin."
      profileNavigationGuard.completeSave(success: false)
      return
    }
    let connectedIDs = Set(characters.map(\.characterID))
    guard
      runtime.productionBasis.areTraderSelectionsValid(
        connectedCharacterIDs: connectedIDs
      )
    else {
      statusMessage = "A selected trader is no longer connected."
      profileNavigationGuard.completeSave(success: false)
      return
    }
    do {
      let data = try JSONEncoder().encode(runtime.productionBasis)
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
      try modelContext.save()
      savedBasis = runtime.productionBasis
      profileNavigationGuard.updateDirtyState(false)
      profileNavigationGuard.completeSave(success: true)
      statusMessage = "Saved \(Date.now.formatted())."
    } catch {
      statusMessage = "Market settings could not be saved."
      profileNavigationGuard.completeSave(success: false)
    }
  }
}

private struct TradingLocationESIPicker: View {
  @Environment(RuntimeState.self) private var runtime
  let authorizations: [AuthorizationSnapshot]
  let clientID: String
  let title: String
  let explanation: String
  let showsNPCStationSearch: Bool
  let selectionConfirmationKey: String
  let onSelect: (ProcurementLocation) -> Void

  @State private var selectedCharacterID: Int64?
  @State private var query = ""
  @State private var stationResults: [TradingLocationSearchOption] = []
  @State private var structureResults: [PlayerStructureOption] = []
  @State private var isSearching = false
  @State private var message: String?

  init(
    authorizations: [AuthorizationSnapshot],
    clientID: String,
    title: String = "Add a Trading Location from ESI",
    explanation: String =
      "Search public NPC stations directly. For an ACL-visible Player Structure, select a connected character whose ESI authorization can search and resolve structures. Type at least three characters.",
    initialQuery: String = "",
    showsNPCStationSearch: Bool = true,
    selectionConfirmationKey: String = "Added %@.",
    onSelect: @escaping (ProcurementLocation) -> Void
  ) {
    self.authorizations = authorizations
    self.clientID = clientID
    self.title = title
    self.explanation = explanation
    self.showsNPCStationSearch = showsNPCStationSearch
    self.selectionConfirmationKey = selectionConfirmationKey
    self.onSelect = onSelect
    let preferredAuthorization =
      authorizations.first {
        $0.scopes.contains(PlayerStructureSearchService.searchScope)
          && $0.scopes.contains(PlayerStructureSearchService.detailScope)
      } ?? authorizations.first
    _selectedCharacterID = State(
      initialValue: preferredAuthorization?.characterID
    )
    _query = State(initialValue: initialQuery)
  }

  private var authorization: AuthorizationSnapshot? {
    authorizations.first { $0.characterID == selectedCharacterID }
  }

  private var canSearchStructures: Bool {
    guard let authorization else { return false }
    return authorization.scopes.contains(
      PlayerStructureSearchService.searchScope
    )
      && authorization.scopes.contains(
        PlayerStructureSearchService.detailScope
      )
  }

  private var acceptedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text(AppLocalization.text(title))
        .font(.headline)
      Text(AppLocalization.text(explanation))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

      TextField(
        AppLocalization.text("Station or Player Structure name"),
        text: $query
      )
      .textFieldStyle(.roundedBorder)
      HStack(spacing: DesignTokens.spacingSM) {
        if showsNPCStationSearch {
          Button {
            Task { await searchStations() }
          } label: {
            Label(
              AppLocalization.text("Search NPC stations"),
              systemImage: "building.columns"
            )
          }
          .disabled(isSearching || acceptedQuery.count < 3)
        }

        Picker(
          AppLocalization.text("Character for Player Structure search"),
          selection: $selectedCharacterID
        ) {
          Text(AppLocalization.text("Select character")).tag(Int64?.none)
          ForEach(authorizations) { authorization in
            Text(authorization.characterName)
              .tag(Optional(authorization.characterID))
          }
        }

        Button {
          Task { await searchStructures() }
        } label: {
          Label(
            AppLocalization.text("Search Player Structures"),
            systemImage: "building.2"
          )
        }
        .disabled(
          isSearching || acceptedQuery.count < 3 || !canSearchStructures
            || clientID.isEmpty
        )
      }

      if authorizations.isEmpty {
        Label(
          AppLocalization.text(
            "Connect and authorize a character before searching Player Structures."
          ),
          systemImage: "person.badge.key"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      } else if !canSearchStructures {
        Label(
          AppLocalization.text(
            "Reauthorize the selected character for structure search and structure details."
          ),
          systemImage: "person.badge.key.fill"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }

      if isSearching {
        ProgressView(AppLocalization.text("Searching ESI…"))
          .controlSize(.small)
      }
      if !stationResults.isEmpty {
        Menu {
          ForEach(stationResults) { option in
            Button(option.name) {
              onSelect(option.procurementLocation)
              message = AppLocalization.format(
                selectionConfirmationKey,
                option.name
              )
            }
          }
        } label: {
          Label(
            AppLocalization.format(
              "Select one of %lld NPC stations",
              Int64(stationResults.count)
            ),
            systemImage: "building.columns"
          )
        }
      }
      if !structureResults.isEmpty {
        Menu {
          ForEach(structureResults) { option in
            Button(option.name) {
              onSelect(
                ProcurementLocation(
                  id: "structure:\(option.id)",
                  name: option.name,
                  locationID: option.id,
                  kind: .playerStructure,
                  solarSystemID: option.solarSystemID,
                  regionID: option.regionID,
                  ownerCorporationID: option.ownerCorporationID
                )
              )
              message = AppLocalization.format(
                selectionConfirmationKey,
                option.name
              )
            }
          }
        } label: {
          Label(
            AppLocalization.format(
              "Select one of %lld Player Structures",
              Int64(structureResults.count)
            ),
            systemImage: "building.2"
          )
        }
      }
      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .onChange(of: query) { _, _ in
      stationResults = []
      structureResults = []
      message = nil
    }
  }

  private func searchStations() async {
    isSearching = true
    stationResults = []
    structureResults = []
    message = nil
    defer { isSearching = false }
    do {
      let snapshot = try await runtime.searchNPCTradingLocations(
        matching: acceptedQuery
      )
      stationResults = snapshot.value ?? []
      message =
        stationResults.isEmpty
        ? "No matching NPC station was found."
        : snapshot.state == .partial
          ? "Some matching NPC stations could not be resolved."
          : nil
    } catch {
      message = "ESI station search is currently unavailable."
    }
  }

  private func searchStructures() async {
    guard let authorization else {
      message = "Select a connected character first."
      return
    }
    guard canSearchStructures else {
      message =
        "Reauthorize this character for structure search and structure details."
      return
    }
    isSearching = true
    stationResults = []
    structureResults = []
    message = nil
    defer { isSearching = false }
    do {
      let snapshot = try await runtime.searchAccessibleStructures(
        matching: acceptedQuery,
        authorization: authorization,
        clientID: clientID
      )
      structureResults = snapshot.value ?? []
      message =
        structureResults.isEmpty
        ? "No accessible matching Player Structure was found."
        : snapshot.state == .partial
          ? "Some matching Player Structures were inaccessible."
          : nil
    } catch ESIError.missingScope {
      message = "Reauthorize this character with the current structure scopes."
    } catch {
      message = "ESI Player Structure search is currently unavailable."
    }
  }
}

private struct SystemFacilityPicker: View {
  @Environment(RuntimeState.self) private var runtime
  let authorizations: [AuthorizationSnapshot]
  let clientID: String
  let solarSystemID: Int64
  let solarSystemName: String
  let onSelectStation: (TradingLocationSearchOption) -> Void
  let onSelectStructure: (PlayerStructureOption) -> Void

  @State private var stationResults: [TradingLocationSearchOption] = []
  @State private var structureResults: [PlayerStructureOption] = []
  @State private var isLoading = false
  @State private var message: String?

  private struct LoadKey: Equatable {
    let solarSystemID: Int64
    let solarSystemName: String
    let characterIDs: [Int64]
    let clientID: String
  }

  private var loadKey: LoadKey {
    LoadKey(
      solarSystemID: solarSystemID,
      solarSystemName: solarSystemName,
      characterIDs: authorizations.map(\.characterID).sorted(),
      clientID: clientID
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack {
        Text("Stations & Structures in Selected System")
          .font(.headline)
        Spacer()
        Button {
          Task { await load(force: true) }
        } label: {
          Label("Reload system locations", systemImage: "arrow.clockwise")
        }
        .labelStyle(.iconOnly)
        .disabled(isLoading || solarSystemID <= 0)
      }
      Text(
        "NPC stations are loaded directly from the selected solar system. Player Structures are searched with the already connected authorizations and then strictly filtered to this system; ESI does not provide a complete system-wide list of every docking permission."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      if solarSystemID <= 0 {
        Label(
          "Select one of the configured systems first.",
          systemImage: "location"
        )
        .foregroundStyle(DesignTokens.caution)
      } else if isLoading {
        ProgressView("Loading locations in selected system…")
          .controlSize(.small)
      } else {
        HStack(spacing: DesignTokens.spacingSM) {
          Menu {
            ForEach(stationResults) { option in
              Button(option.name) { onSelectStation(option) }
            }
          } label: {
            Label(
              "NPC stations (\(stationResults.count))",
              systemImage: "building.columns"
            )
          }
          .disabled(stationResults.isEmpty)

          Menu {
            ForEach(structureResults) { option in
              Button(option.name) { onSelectStructure(option) }
            }
          } label: {
            Label(
              "Player Structures (\(structureResults.count))",
              systemImage: "building.2"
            )
          }
          .disabled(structureResults.isEmpty)
        }
      }
      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
      }
    }
    .task(id: loadKey) {
      await load(force: false)
    }
  }

  private func load(force: Bool) async {
    guard solarSystemID > 0 else {
      stationResults = []
      structureResults = []
      message = nil
      return
    }
    isLoading = true
    message = nil
    defer { isLoading = false }

    async let stationsAttempt = try? runtime.loadNPCStations(
      in: solarSystemID,
      force: force
    )
    async let structuresAttempt = runtime.loadAccessibleStructures(
      in: solarSystemID,
      systemName: solarSystemName,
      authorizations: authorizations,
      clientID: clientID
    )
    let (stations, structures) = await (
      stationsAttempt,
      structuresAttempt
    )
    guard !Task.isCancelled else { return }
    stationResults = stations?.value ?? []
    structureResults = structures.value ?? []

    var notes: [String] = []
    if stations == nil || stations?.state == .unavailable {
      notes.append("NPC stations are currently unavailable.")
    } else if stations?.state == .partial {
      notes.append("Some NPC stations could not be resolved.")
    }
    switch structures.state {
    case .forbidden:
      notes.append(
        "Player Structures require a connected character with structure-search and structure-detail access."
      )
    case .unavailable:
      notes.append("Player Structure search is currently unavailable.")
    case .partial:
      notes.append(
        "Player Structure results are partial because at least one connected authorization or result was inaccessible."
      )
    case .fresh, .stale:
      if structureResults.isEmpty {
        notes.append(
          "No accessible Player Structure matching the system name was returned."
        )
      }
    }
    if stationResults.isEmpty && structureResults.isEmpty && notes.isEmpty {
      notes.append("No selectable station or structure was found in this system.")
    }
    message = notes.isEmpty ? nil : notes.joined(separator: " ")
  }
}

private struct CharacterIndustryAssignmentRow: View {
  let characterName: String
  let limits: IndustrySkillSlotLimits
  @Binding var assignment: CharacterIndustryAssignment

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        EVEEntityText(value: characterName, lineLimit: 1)
        Spacer()
        Toggle("Use for industry", isOn: $assignment.isEnabled)
          .toggleStyle(.switch)
      }
      if assignment.isEnabled {
        HStack(spacing: DesignTokens.spacingMD) {
          ForEach(IndustrySlotActivity.allCases) { activity in
            Toggle(activity.displayName, isOn: activityBinding(activity))
              .toggleStyle(.checkbox)
          }
        }
        ForEach(IndustrySlotPool.allCases) { pool in
          if assignment.allowedActivities.contains(where: { $0.pool == pool }) {
            LabeledContent(pool.displayName) {
              HStack(spacing: DesignTokens.spacingSM) {
                Text(skillMaximumText(pool))
                  .foregroundStyle(DesignTokens.textSecondary)
                  .monospacedDigit()
                TextField(
                  "Skill maximum",
                  value: limitBinding(pool),
                  format: .number
                )
                .multilineTextAlignment(.trailing)
                .frame(width: DesignTokens.compactNumberWidth)
                .accessibilityLabel(
                  Text(
                    AppLocalization.format(
                      "Slot limit for %@",
                      pool.displayName
                    )
                  )
                )
              }
            }
          }
        }
      }
    }
  }

  private func skillMaximumText(_ pool: IndustrySlotPool) -> String {
    guard let maximum = limits.slots(for: pool) else {
      return AppLocalization.text("Skills unavailable")
    }
    return AppLocalization.format("Skill maximum %lld", Int64(maximum))
  }

  private func activityBinding(
    _ activity: IndustrySlotActivity
  ) -> Binding<Bool> {
    Binding(
      get: { assignment.allowedActivities.contains(activity) },
      set: { isAllowed in
        if isAllowed {
          assignment.allowedActivities.insert(activity)
        } else {
          assignment.allowedActivities.remove(activity)
        }
      }
    )
  }

  private func limitBinding(_ pool: IndustrySlotPool) -> Binding<Int?> {
    Binding(
      get: { assignment.slotLimit(for: pool) },
      set: { assignment.setSlotLimit($0, for: pool) }
    )
  }
}

extension IndustrySlotActivity {
  fileprivate var displayName: String {
    switch self {
    case .manufacturing: "Manufacturing".localizedUI
    case .reaction: "Reactions".localizedUI
    case .copying: "Copying".localizedUI
    case .research: "Research".localizedUI
    case .invention: "Invention".localizedUI
    }
  }
}

extension IndustrySlotPool {
  fileprivate var displayName: String {
    switch self {
    case .manufacturing: "Manufacturing slots".localizedUI
    case .reaction: "Reaction slots".localizedUI
    case .science: "Science slots".localizedUI
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
