import EVENexusCore
import SwiftData
import SwiftUI

struct ConsolidationScienceView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @Environment(RuntimeState.self) private var runtime
  @Query(sort: \StoredCharacter.characterName) private var characters: [StoredCharacter]
  @State private var instanceID: Int64?
  @State private var plannedCopyID: UUID?
  @State private var characterID: Int64?
  @State private var activity: BlueprintActivityDefinition.Kind = .copying
  @State private var requiredRuns = 1
  @State private var runsPerCopy = 1
  @State private var targetLevel = 1
  @State private var outputBlueprintID: Int64?
  @State private var decryptorID: Int64?
  @State private var installation = ""
  @State private var materials = ""
  @State private var confidence = 0.95
  @State private var activities: [BlueprintScienceActivityDefinition] = []
  @State private var decryptors: [BlueprintDecryptorDefinition] = []
  @State private var names: [Int64: String] = [:]
  @State private var loading = false
  @State private var definitionBlueprintID: Int64?
  var entries: [BlueprintPortfolioEntry] {
    BlueprintPortfolio(
      inventories: characters.compactMap { character in
        guard let data = character.blueprintSnapshot,
          let snapshot = try? JSONDecoder().decode(
            Sourced<[OwnedBlueprintInstance]>.self, from: data)
        else { return nil }
        return OwnedBlueprintInventory(
          ownerID: character.characterID, ownerName: character.characterName, blueprints: snapshot)
      }
    ).entries
  }
  var entry: BlueprintPortfolioEntry? { entries.first { $0.instance.id == instanceID } }
  var plannedCopies: [SavedScienceJob] {
    controller.workspace.science.filter { job in
      guard !job.archived else { return false }
      if case .copying = job.job { return true }
      return false
    }
  }
  var plannedCopy: BlueprintCopyPlan? {
    guard let saved = plannedCopies.first(where: { $0.id == plannedCopyID }),
      case .copying(let copy) = saved.job
    else { return nil }
    return copy
  }

  var body: some View {
    Form {
      Picker("Blueprint-Instanz", selection: $instanceID) {
        Text("Auswählen").tag(Optional<Int64>.none)
        ForEach(entries) { e in
          Text(
            "\(names[e.instance.blueprintTypeID] ?? "Name wird aufgelöst") · \(e.ownerName) · \(e.instance.kind.rawValue) · \(e.instance.id)"
          ).tag(Optional(e.instance.id))
        }
      }
      if let entry {
        EVEEntityText(value: names[entry.instance.blueprintTypeID] ?? "Name nicht aufgelöst")
      }
      Picker("Aktivität", selection: $activity) {
        Text("Copying").tag(BlueprintActivityDefinition.Kind.copying)
        Text("ME-Forschung").tag(BlueprintActivityDefinition.Kind.materialResearch)
        Text("TE-Forschung").tag(BlueprintActivityDefinition.Kind.timeResearch)
        Text("Invention").tag(BlueprintActivityDefinition.Kind.invention)
      }
      Picker("Ausführender Charakter", selection: $characterID) {
        Text("Auswählen").tag(Optional<Int64>.none)
        ForEach(characters) { Text($0.characterName).tag(Optional($0.characterID)) }
      }
      TextField("Benötigte Fertigungs-Runs", value: $requiredRuns, format: .number)
      if activity == .copying { TextField("Runs je Kopie", value: $runsPerCopy, format: .number) }
      if activity == .materialResearch || activity == .timeResearch {
        Stepper(
          "Zielstufe \(targetLevel)\(activity == .timeResearch ? " (TE \(targetLevel * 2))" : "")",
          value: $targetLevel, in: 1...10)
      }
      if activity == .invention {
        Picker("Input-Kopie", selection: $plannedCopyID) {
          Text("Vorhandene BPC-Instanz").tag(Optional<UUID>.none)
          ForEach(plannedCopies) { Text("Geplant: \($0.name)").tag(Optional($0.id)) }
        }
        Picker("Ergebnis-Blueprint", selection: $outputBlueprintID) {
          Text("Auswählen").tag(Optional<Int64>.none)
          ForEach(activities.first(where: { $0.kind == .invention })?.products ?? [], id: \.typeID)
          { p in Text(names[p.typeID] ?? "Name nicht aufgelöst").tag(Optional(p.typeID)) }
        }
        Picker("Decryptor", selection: $decryptorID) {
          Text("Keiner").tag(Optional<Int64>.none)
          ForEach(decryptors, id: \.typeID) {
            Text(names[$0.typeID] ?? "Name nicht aufgelöst").tag(Optional($0.typeID))
          }
        }
        Slider(value: $confidence, in: 0.50...0.99, step: 0.01) { Text("Konfidenz") }
        Text("Konfidenz: \(Int((confidence * 100).rounded())) %")
      }
      if activity == .copying || activity == .invention {
        TextField(
          activity == .invention
            ? "Installationskosten je Versuch (ISK)" : "Installationskosten gesamt (ISK)",
          text: $installation)
        TextField(
          activity == .invention
            ? "Material, Decryptor und Input-BPC je Versuch (ISK)" : "Materialkosten gesamt (ISK)",
          text: $materials)
        Text(
          "Kosten ausdrücklich eintragen, auch wenn sie null sind. Die vorhandenen Fachrechner verwenden diese Beträge; fehlende Kosten werden nicht als null behandelt."
        ).font(.caption)
      }
      Button(loading ? "Auftrag wird geprüft…" : "Auftrag berechnen und prüfen") {
        Task { await prepare() }
      }.disabled(loading)
      ForEach(
        controller.workspace.science.filter { !$0.archived }
      ) { job in
        VStack(alignment: .leading) {
          EVEEntityText(value: job.name)
          EVEEntityText(value: job.facilityName, font: .caption)
          Text(scienceDescription(job.job)).font(.caption).textSelection(.enabled)
          if job.supplyPlan != nil {
            Text("Als konkrete Blueprint-Versorgung gespeichert. Planner neu berechnen.")
              .font(.caption)
          }
          Button("Planungsauftrag archivieren") {
            controller.propose([
              "Wissenschaftsauftrag archivieren und seine aktive Blueprint-Versorgung entfernen."
            ]) { w in
              if case .copying(let copy) = job.job,
                w.science.contains(where: { other in
                  guard !other.archived else { return false }
                  if case .invention(let invention) = other.job {
                    return invention.inputBPC == .plannedCopy(jobID: copy.id)
                  }
                  return false
                })
              {
                throw ConsolidationError.invalid("Zuerst abhängige Invention-Aufträge archivieren.")
              }
              guard let i = w.science.firstIndex(where: { $0.id == job.id }) else {
                throw ConsolidationError.stalePreview
              }
              w.science[i].archived = true
            }
          }

        }
      }
    }.formStyle(.grouped)
      .task {
        names = await runtime.resolveAssetTypeNames(
          Set(entries.map { $0.instance.blueprintTypeID }))
      }
      .task(id: instanceID) { await loadActivities() }
      .onChange(of: plannedCopyID) {
        if let copy = plannedCopy, case .ownedBPO(let id) = copy.sourceBPO { instanceID = id }
      }
  }
  private func loadActivities() async {
    guard let entry else {
      activities = []
      return
    }
    do {
      let data = try await runtime.consolidationScienceDefinitions(entry.instance.blueprintTypeID)
      guard entry.instance.id == instanceID, !Task.isCancelled else { return }
      definitionBlueprintID = entry.instance.blueprintTypeID
      activities = data.0
      decryptors = data.1
      let ids = Set(
        data.0.flatMap { $0.products.map(\.typeID) } + data.1.map(\.typeID) + [
          entry.instance.blueprintTypeID
        ])
      names.merge(await runtime.resolveAssetTypeNames(ids)) { _, new in new }
    } catch { controller.error = error.localizedDescription }
  }
  private func prepare() async {
    loading = true
    defer { loading = false }
    do {
      guard let entry,
        let character = characters.first(where: { $0.characterID == characterID }),
        let payload = character.capabilitySnapshot,
        let capabilities = try? JSONDecoder().decode(
          CharacterCapabilitySnapshot.self, from: payload),
        entry.sourceState == .fresh, capabilities.skills.state == .fresh,
        definitionBlueprintID == entry.instance.blueprintTypeID,
        let definition = activities.first(where: { $0.kind == activity })
      else {
        throw ConsolidationError.invalid(
          "Frische Blueprint-/Skilldaten, Charakter und eine verfügbare SDE-Aktivität auswählen."
        )
      }
      for skill in definition.requiredSkills {
        guard let level = capabilities.skillLevel(skill.typeID), level >= skill.level else {
          throw ConsolidationError.invalid(
            "Erforderlicher Skill \(skill.typeID) fehlt oder ist zu niedrig.")
        }
      }
      let facilityActivity: IndustryActivitySystem =
        switch activity {
        case .copying: .copying
        case .invention: .invention
        case .materialResearch: .materialResearch
        default: .timeResearch
        }
      guard let facility = runtime.productionBasis.scienceSelection(for: facilityActivity),
        !facility.needsReview,
        let structure = runtime.productionBasis.structure(id: facility.structureID),
        let location = structure.structureID, location == entry.instance.locationID
      else {
        throw ConsolidationError.invalid(
          "Eine geprüfte Wissenschaftsanlage am Standort des Blueprints konfigurieren. Erforderliche Transporte zuerst abschließen."
        )
      }
      guard requiredRuns > 0, requiredRuns <= 100_000, runsPerCopy > 0 else {
        throw ConsolidationError.invalid("Ungültige Runs.")
      }
      let baseRevision = controller.workspace.revision
      let build = runtime.activeSDEBuild
      let sourceRevision = controller.stockRevision
      let job: BlueprintScienceJob
      var supply: BlueprintSupplyPlan?
      var totalMaterials = 0.0
      let instance = entry.instance
      switch activity {
      case .copying:
        guard instance.kind == .original else {
          throw BlueprintSciencePlanningError.originalRequired
        }
        guard
          let recipe = try await runtime.consolidationManufacturingDefinition(
            instance.blueprintTypeID),
          let maxRuns = recipe.maxProductionLimit, runsPerCopy <= maxRuns
        else {
          throw ConsolidationError.invalid(
            "Runs je Kopie überschreiten die SDE-Grenze oder die Grenze ist unbekannt.")
        }
        guard let fee = try optionalCents(installation), let material = try optionalCents(materials)
        else { throw ConsolidationError.invalid("Alle Kosten ausdrücklich eintragen.") }
        totalMaterials = Double(material) / 100
        let copy = try BlueprintSciencePlanner.copyPlan(
          sourceBPO: .ownedBPO(itemID: instance.id), blueprintTypeID: instance.blueprintTypeID,
          activity: definition, copyCount: (requiredRuns + runsPerCopy - 1) / runsPerCopy,
          runsPerCopy: runsPerCopy,
          maximumRunsPerCopy: Int(clamping: maxRuns),
          materialEfficiency: instance.materialEfficiency,
          timeEfficiency: instance.timeEfficiency, durationMultiplier: facility.timeMultiplier,
          installationCost: Double(fee) / 100)
        job = .copying(copy)
        supply = try ConsolidationScience.supply(
          job: job, definition: recipe, requiredRuns: requiredRuns,
          name: (await runtime.resolveAssetTypeNames([recipe.productTypeID]))[recipe.productTypeID]
            ?? "Name nicht aufgelöst",
          ownerID: entry.ownerID, ownerName: entry.ownerName, locationID: location,
          materialCost: totalMaterials,
          sourceIDs: [instance.source.snapshotID, definition.source.snapshotID])
      case .invention:
        guard instance.kind == .copy || plannedCopy?.blueprintTypeID == instance.blueprintTypeID,
          let outputBlueprintID,
          let recipe = try await runtime.consolidationManufacturingDefinition(outputBlueprintID)
        else { throw BlueprintSciencePlanningError.copyRequired }
        guard let fee = try optionalCents(installation), let material = try optionalCents(materials)
        else { throw ConsolidationError.invalid("Alle Kosten je Versuch ausdrücklich eintragen.") }
        let cost = Double(try ConsolidationWorkspace.add(fee, material)) / 100
        let decryptor = decryptors.first { $0.typeID == decryptorID }
        let runOutput = max(
          1,
          Int(definition.products.first { $0.typeID == outputBlueprintID }?.quantity ?? 0)
            + (decryptor?.runModifier ?? 0))
        let inputSource: BlueprintSourceReference =
          plannedCopy.map { .plannedCopy(jobID: $0.id) } ?? .ownedBPC(itemID: instance.id)
        let invention = try BlueprintSciencePlanner.inventionPlan(
          inputBPC: inputSource, inputBlueprintTypeID: instance.blueprintTypeID,
          selectedOutputBlueprintTypeID: outputBlueprintID, activity: definition,
          characterID: character.characterID, characterName: character.characterName,
          trainedSkillLevels: Dictionary(
            uniqueKeysWithValues: definition.requiredSkills.compactMap { skill in
              capabilities.skillLevel(skill.typeID).map { (skill.typeID, $0) }
            }),
          decryptor: decryptor, attemptCost: cost,
          requiredSuccesses: (requiredRuns + runOutput - 1) / runOutput, confidence: confidence,
          durationMultiplier: facility.timeMultiplier)
        let otherRuns = controller.workspace.science.reduce(0) { count, saved in
          if !saved.archived, case .invention(let prior) = saved.job, prior.inputBPC == inputSource
          {
            return count + prior.confidenceInputBPCRuns
          }
          return count
        }
        guard
          invention.confidenceInputBPCRuns <= (plannedCopy?.totalLicensedRuns ?? instance.runs)
            - otherRuns
        else {
          throw ConsolidationError.invalid(
            "Die Input-BPC besitzt nicht genügend unzugeordnete Runs für den Konfidenzplan.")
        }
        job = .invention(invention)
        supply = try ConsolidationScience.supply(
          job: job, definition: recipe, requiredRuns: requiredRuns,
          name: (await runtime.resolveAssetTypeNames([recipe.productTypeID]))[recipe.productTypeID]
            ?? "Name nicht aufgelöst",
          ownerID: entry.ownerID, ownerName: entry.ownerName, locationID: location, materialCost: 0,
          sourceIDs: [instance.source.snapshotID, definition.source.snapshotID, capabilities.id],
          prerequisites: plannedCopy.map { [.copying($0)] } ?? [])
      case .materialResearch, .timeResearch:
        guard instance.kind == .original else {
          throw BlueprintSciencePlanningError.originalRequired
        }
        let current =
          activity == .materialResearch ? instance.materialEfficiency : instance.timeEfficiency / 2
        guard targetLevel > current else {
          throw ConsolidationError.invalid(
            "Die Zielstufe muss oberhalb der vorhandenen Stufe liegen.")
        }
        let quote = try await runtime.blueprintResearchQuote(for: instance)
        let steps = quote.levels.filter { $0.level > current && $0.level <= targetLevel }
        let values = steps.compactMap {
          activity == .materialResearch ? $0.materialStepCost : $0.timeStepCost
        }
        guard values.count == steps.count, !steps.isEmpty, definition.materials.isEmpty else {
          throw ConsolidationError.invalid(
            "Forschungskosten oder zusätzliche Materialkosten sind unvollständig.")
        }
        let duration =
          Double(definition.durationSeconds) * steps.reduce(0.0) { $0 + $1.researchMultiplier }
          * facility.timeMultiplier
        guard duration.isFinite, duration >= 0, duration < Double(Int64.max) else {
          throw ConsolidationError.overflow
        }
        job = .research(
          BlueprintResearchPlan(
            sourceBPO: .ownedBPO(itemID: instance.id), blueprintTypeID: instance.blueprintTypeID,
            activity: activity == .materialResearch ? .materialEfficiency : .timeEfficiency,
            currentLevel: current,
            targetLevel: targetLevel, materials: [], durationSeconds: Int64(ceil(duration)),
            installationCost: values.reduce(0, +)))
        guard
          let recipe = try await runtime.consolidationManufacturingDefinition(
            instance.blueprintTypeID)
        else { throw ConsolidationError.invalid("Fertigungsdefinition fehlt.") }
        supply = try ConsolidationScience.supply(
          job: job, definition: recipe, requiredRuns: requiredRuns,
          name: (await runtime.resolveAssetTypeNames([recipe.productTypeID]))[recipe.productTypeID]
            ?? "Name nicht aufgelöst",
          ownerID: entry.ownerID, ownerName: entry.ownerName, locationID: location, materialCost: 0,
          sourceIDs: [instance.source.snapshotID, definition.source.snapshotID],
          originalME: instance.materialEfficiency, originalTE: instance.timeEfficiency)

      default: throw BlueprintSciencePlanningError.wrongActivity
      }
      guard baseRevision == controller.workspace.revision, build == runtime.activeSDEBuild,
        sourceRevision == controller.stockRevision
      else { throw ConsolidationError.stalePreview }
      let saved = SavedScienceJob(
        blueprintTypeID: instance.blueprintTypeID,
        name: names[instance.blueprintTypeID] ?? "Name nicht aufgelöst", job: job,
        facilityName: facility.structureName,
        solarSystemID: facility.solarSystemID,
        sourceIDs: [instance.source.snapshotID, definition.source.snapshotID], supplyPlan: supply)
      controller.propose(
        [
          scienceDescription(job), "Anlage: \(facility.structureName).",
          "Nur lokal planen; es wird kein Auftrag in EVE gestartet.",
        ], catalogBuild: build
      ) { w in
        // The supply lives on the saved job; the planner reads all non-archived jobs.
        w.science.append(saved)
      }
    } catch { controller.error = error.localizedDescription }
  }
}

private func scienceDescription(_ job: BlueprintScienceJob) -> String {
  switch job {
  case .copying(let p):
    "Copying: \(p.copyCount) Kopien × \(p.runsPerCopy) Runs, ME \(p.materialEfficiency), TE \(p.timeEfficiency), \(p.durationSeconds.map(String.init) ?? "unbekannt") s, Installation \(p.installationCost.map { String(format: "%.2f", $0) } ?? "unbekannt") ISK."
  case .research(let p):
    "Forschung \(p.activity.rawValue): Stufe \(p.currentLevel) → \(p.targetLevel), \(p.durationSeconds.map(String.init) ?? "unbekannt") s, \(p.installationCost.map { String(format: "%.2f", $0) } ?? "unbekannt") ISK."
  case .invention(let p):
    "Invention: \(p.forecast.requiredSuccesses) Erfolge, \(p.outputRuns) Runs je Erfolg, ME \(p.outputMaterialEfficiency), TE \(p.outputTimeEfficiency). Chance \(p.successProbability), erwartete Versuche \(p.forecast.expectedAttempts), Konfidenzversuche \(p.forecast.attemptsForConfidence), \(p.durationSeconds.map(String.init) ?? "unbekannt") s. Erwartete Kosten \(p.forecast.expectedCost.map { String(format: "%.2f", $0) } ?? "unbekannt"), Konfidenzkosten \(p.forecast.confidencePlanCost.map { String(format: "%.2f", $0) } ?? "unbekannt") ISK."
  }
}
