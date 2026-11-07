import EVENexusCore

// Content of the Planner's info panel. Every change to the Planner's flow,
// inputs, interventions, rules or results updates this file in the same change
// (see AGENTS.md, "Planer-Info-Panel"). Titles and explanations are English
// keys of Localizable.strings and stay short: at most three brief sentences.

enum PlannerFlowRole: String, CaseIterable {
  case input
  case automatic
  case intervention
  case result

  var title: String {
    switch self {
    case .input: "Your input"
    case .automatic: "Automatic"
    case .intervention: "Your intervention"
    case .result: "Result"
    }
  }

  var symbol: String {
    switch self {
    case .input: "square.and.pencil"
    case .automatic: "gearshape"
    case .intervention: "hand.point.up.left"
    case .result: "checkmark.seal"
    }
  }
}

enum PlannerFlowNodeID: String, CaseIterable {
  case productList
  case purchaseLocations
  case stock
  case productionBasis
  case calculate

  case staticData
  case markets
  case pricesAndIndices
  case blueprintOffers
  case stockData

  case blueprintSource
  case billOfMaterials
  case makeOrBuy
  case purchaseSplit
  case automaticLoop
  case controlPass
  case savePlan

  case productionRoute
  case finance
  case profitability
  case targetMarket
  case shoppingList
  case jobs
  case warnings

  case resetChoices
  case blueprintChoice
  case jobSplit
  case supplyChoice
  case saleChoice
  case profitabilityDecision
}

enum PlannerFlowEdgeID: String, CaseIterable {
  case inputsToCalculate
  case calculateToData
  case dataToBlueprints
  case blueprintsToMaterials
  case materialsToMakeOrBuy
  case makeOrBuyToPurchase
  case purchaseToLoop
  case loopBack
  case loopToControl
  case controlBack
  case controlToSave
  case saveToResults
  case resultsToInterventions
  case interventionsToCalculate
  case blueprintChoiceToSource
  case jobSplitToMaterials
  case supplyChoiceToMakeOrBuy
  case saleChoiceToResults
}

enum PlannerFlowEdgeEndpoint: Equatable {
  case node(PlannerFlowNodeID)
  case column(PlannerFlowColumn)
}

enum PlannerFlowColumn: String, CaseIterable {
  case inputs
  case data
  case calculation
  case results
  case interventions

  var title: String {
    switch self {
    case .inputs: "Your input"
    case .data: "Load data"
    case .calculation: "Calculation"
    case .results: "Result"
    case .interventions: "Your interventions"
    }
  }
}

struct PlannerFlowNode: Equatable, Identifiable {
  let id: PlannerFlowNodeID
  let role: PlannerFlowRole
  let column: PlannerFlowColumn
  let title: String
  let explanation: String
}

struct PlannerFlowEdge: Equatable, Identifiable {
  let id: PlannerFlowEdgeID
  let from: PlannerFlowEdgeEndpoint
  let to: PlannerFlowEdgeEndpoint
  let isIntervention: Bool
  let title: String
  let explanation: String
}

enum PlannerFlowGuide {
  static let panelTitle = "How the Planner calculates"
  static let summary =
    "The Planner leads through eight steps and calculates only on click. Hover over a step or an arrow for its explanation."

  static let nodes: [PlannerFlowNode] = [
    PlannerFlowNode(
      id: .productList, role: .input, column: .inputs,
      title: "Product list",
      explanation:
        "One or more products. One line per job: product, quantity, ME and TE. A line can add a BPC or BPO with its cost."
    ),
    PlannerFlowNode(
      id: .purchaseLocations, role: .input, column: .inputs,
      title: "Purchase locations",
      explanation:
        "Choose from the hubs and comparison markets. Without a choice the Main Hub applies. Comparison markets need a transport route in the logistics settings."
    ),
    PlannerFlowNode(
      id: .stock, role: .input, column: .inputs,
      title: "Warehouse",
      explanation:
        "Yes or no. With yes, use the combined warehouse or enter stock by hand; manual stock replaces the warehouse. With no, the plan uses no stock."
    ),
    PlannerFlowNode(
      id: .productionBasis, role: .input, column: .inputs,
      title: "Production basis",
      explanation:
        "Structures, rigs, taxes and transport routes. They are maintained outside the Planner."
    ),
    PlannerFlowNode(
      id: .calculate, role: .input, column: .inputs,
      title: "Calculate",
      explanation:
        "In step 3 this button or ⌘↩ starts the calculation. After a change later steps show the plan as outdated and offer Recalculate."
    ),

    PlannerFlowNode(
      id: .staticData, role: .automatic, column: .data,
      title: "Static data",
      explanation: "Recipes, materials and durations come from the SDE."
    ),
    PlannerFlowNode(
      id: .markets, role: .automatic, column: .data,
      title: "Markets",
      explanation: "Loads the order books of the Main Hub and the selected locations."
    ),
    PlannerFlowNode(
      id: .pricesAndIndices, role: .automatic, column: .data,
      title: "Prices and indices",
      explanation: "Adjusted prices and system indices determine the installation cost."
    ),
    PlannerFlowNode(
      id: .blueprintOffers, role: .automatic, column: .data,
      title: "Blueprint offers",
      explanation: "Market orders, NPC formula orders and public contracts are possible sources."
    ),
    PlannerFlowNode(
      id: .stockData, role: .automatic, column: .data,
      title: "Stock",
      explanation: "With yes, stock is used first. A manual list replaces the warehouse in every calculation pass, including Blueprint runs. Step 4 shows what the market tops up."
    ),

    PlannerFlowNode(
      id: .blueprintSource, role: .automatic, column: .calculation,
      title: "Choose Blueprint source",
      explanation:
        "Fixed order: own BPO, own BPC, contracts, market, loyalty store. Reactions use a NPC formula if none is owned. Without a source it stays unresolved."
    ),
    PlannerFlowNode(
      id: .billOfMaterials, role: .automatic, column: .calculation,
      title: "Bill of materials",
      explanation:
        "Expands the recipe level by level. Runs and materials are rounded up per job, as in EVE."
    ),
    PlannerFlowNode(
      id: .makeOrBuy, role: .automatic, column: .calculation,
      title: "Build or buy",
      explanation:
        "Compares purchase and build including transport and Blueprint cost. On a tie it builds. A deeper chain wins only if its shopping list is really cheaper."
    ),
    PlannerFlowNode(
      id: .purchaseSplit, role: .automatic, column: .calculation,
      title: "Split purchases",
      explanation:
        "Each order is compared by unit price including its transport share. Quantities can split across locations."
    ),
    PlannerFlowNode(
      id: .automaticLoop, role: .automatic, column: .calculation,
      title: "Settle the choice",
      explanation:
        "Applies the recommendations and calculates again until the choice is stable, at most five passes. Manual choices stay locked."
    ),
    PlannerFlowNode(
      id: .controlPass, role: .automatic, column: .calculation,
      title: "Control pass",
      explanation:
        "If the built materials or the needed Blueprint runs changed, the Blueprints are resolved again without automation. A reaction without a formula is bought instead."
    ),
    PlannerFlowNode(
      id: .savePlan, role: .automatic, column: .calculation,
      title: "Save active plan",
      explanation:
        "Saves the result as the active plan. If science work changed meanwhile, the previous plan stays and a message appears."
    ),

    PlannerFlowNode(
      id: .productionRoute, role: .result, column: .results,
      title: "Production route",
      explanation: "Shows what is built, bought or taken from stock."
    ),
    PlannerFlowNode(
      id: .finance, role: .result, column: .results,
      title: "Finance overview",
      explanation: "Adds up all cost items. Stock does not change the total: it counts as its share of the cost without stock. An unknown cost never counts as zero."
    ),
    PlannerFlowNode(
      id: .profitability, role: .result, column: .results,
      title: "Profitable?",
      explanation: "Step 4 shows one row per product with costs and selected sale. The best final sale is preselected and changeable. A selected sale without a final profit triggers a warning."
    ),
    PlannerFlowNode(
      id: .targetMarket, role: .result, column: .results,
      title: "Target market and sale",
      explanation: "Step 8 only summarizes the choice from step 4 and records it. Production rows take the chosen market and scenario."
    ),
    PlannerFlowNode(
      id: .shoppingList, role: .result, column: .results,
      title: "Shopping list",
      explanation: "One Multibuy per location for missing items. A second list adds used stock, each at its cheapest hub."
    ),
    PlannerFlowNode(
      id: .jobs, role: .result, column: .results,
      title: "Jobs and schedule",
      explanation: "Shows the build jobs and schedule. Durations use the character from step 3 and the location's implants. Only that location's characters supply slots."
    ),
    PlannerFlowNode(
      id: .warnings, role: .result, column: .results,
      title: "Warnings",
      explanation: "Missing or stale data stays visible here, with blocking messages first. Contract index and courier warnings appear only if a selected sale depends on them."
    ),

    PlannerFlowNode(
      id: .resetChoices, role: .intervention, column: .interventions,
      title: "Back to automatic",
      explanation:
        "Releases one choice or, with “Reset manual interventions”, all of them. Handed-over Blueprints stay fixed. “Reset Planner” empties the whole plan after a safety question."
    ),
    PlannerFlowNode(
      id: .blueprintChoice, role: .intervention, column: .interventions,
      title: "Blueprint choice",
      explanation:
        "Sets source, instance, quality and cost. A manual cost takes precedence. ME and TE of own Blueprints cannot be overwritten."
    ),
    PlannerFlowNode(
      id: .jobSplit, role: .intervention, column: .interventions,
      title: "Job split",
      explanation: "Two switches decide whether target and intermediate products split into several jobs."
    ),
    PlannerFlowNode(
      id: .supplyChoice, role: .intervention, column: .interventions,
      title: "Build, buy or stock",
      explanation: "Locks the choice for one material. The automation leaves it unchanged."
    ),
    PlannerFlowNode(
      id: .saleChoice, role: .intervention, column: .interventions,
      title: "Target market and alliance sale",
      explanation: "In step 4 a menu and the alliance table record your sale per product. They do not change the plan. Recording needs a current plan and a target market."
    ),
    PlannerFlowNode(
      id: .profitabilityDecision, role: .intervention, column: .interventions,
      title: "Produce anyway",
      explanation: "Opens the later steps despite the warning, for this calculation and these sales only. With several products you can remove a product instead."
    ),
  ]

  static let edges: [PlannerFlowEdge] = [
    PlannerFlowEdge(
      id: .inputsToCalculate, from: .column(.inputs), to: .node(.calculate), isIntervention: false,
      title: "Inputs are read",
      explanation: "Your inputs are saved as a draft. They count only when you click Calculate."
    ),
    PlannerFlowEdge(
      id: .calculateToData, from: .node(.calculate), to: .column(.data), isIntervention: false,
      title: "Click starts loading",
      explanation: "A new click cancels a running calculation and uses your latest inputs."
    ),
    PlannerFlowEdge(
      id: .dataToBlueprints, from: .column(.data), to: .node(.blueprintSource), isIntervention: false,
      title: "Data reaches the calculation",
      explanation: "Missing data never becomes zero. It stays open and appears as a warning."
    ),
    PlannerFlowEdge(
      id: .blueprintsToMaterials, from: .node(.blueprintSource), to: .node(.billOfMaterials),
      isIntervention: false,
      title: "ME and TE are applied",
      explanation: "The ME and TE of the chosen source determine materials and duration."
    ),
    PlannerFlowEdge(
      id: .materialsToMakeOrBuy, from: .node(.billOfMaterials), to: .node(.makeOrBuy),
      isIntervention: false,
      title: "Every material is assessed",
      explanation: "Each producible material gets a build and a purchase value."
    ),
    PlannerFlowEdge(
      id: .makeOrBuyToPurchase, from: .node(.makeOrBuy), to: .node(.purchaseSplit),
      isIntervention: false,
      title: "Purchases go to the book",
      explanation: "Everything not built or covered by stock is purchased."
    ),
    PlannerFlowEdge(
      id: .purchaseToLoop, from: .node(.purchaseSplit), to: .node(.automaticLoop),
      isIntervention: false,
      title: "Recommendations are checked",
      explanation: "The pass delivers new recommendations for the choice."
    ),
    PlannerFlowEdge(
      id: .loopBack, from: .node(.automaticLoop), to: .node(.makeOrBuy), isIntervention: false,
      title: "Calculate again",
      explanation: "A bought parent hides its inputs and changes quantities, so another pass follows."
    ),
    PlannerFlowEdge(
      id: .loopToControl, from: .node(.automaticLoop), to: .node(.controlPass), isIntervention: false,
      title: "Choice is settled",
      explanation: "If five passes are not enough, the last choice stays and a note appears."
    ),
    PlannerFlowEdge(
      id: .controlBack, from: .node(.controlPass), to: .node(.blueprintSource), isIntervention: false,
      title: "Resolve Blueprints again",
      explanation: "The Blueprints were chosen with Main Hub prices. This pass aligns them with the calculated build steps."
    ),
    PlannerFlowEdge(
      id: .controlToSave, from: .node(.controlPass), to: .node(.savePlan), isIntervention: false,
      title: "Plan is complete",
      explanation: "Cost and supply now describe the same build steps."
    ),
    PlannerFlowEdge(
      id: .saveToResults, from: .node(.savePlan), to: .column(.results), isIntervention: false,
      title: "Results are shown",
      explanation: "All result areas show the saved plan with its price date."
    ),
    PlannerFlowEdge(
      id: .resultsToInterventions, from: .column(.results), to: .column(.interventions),
      isIntervention: true,
      title: "You review the plan",
      explanation: "The controls for your interventions appear within the result."
    ),
    PlannerFlowEdge(
      id: .interventionsToCalculate, from: .column(.interventions), to: .node(.calculate),
      isIntervention: true,
      title: "Effective on the next click",
      explanation: "Interventions are saved at once but change the plan only with the next calculation."
    ),
    PlannerFlowEdge(
      id: .blueprintChoiceToSource, from: .node(.blueprintChoice), to: .node(.blueprintSource),
      isIntervention: true,
      title: "Your source replaces the automatic one",
      explanation: "The automatic order no longer applies to this Blueprint."
    ),
    PlannerFlowEdge(
      id: .jobSplitToMaterials, from: .node(.jobSplit), to: .node(.billOfMaterials),
      isIntervention: true,
      title: "Split changes rounding",
      explanation: "Materials are rounded per job, so the split can change quantities."
    ),
    PlannerFlowEdge(
      id: .supplyChoiceToMakeOrBuy, from: .node(.supplyChoice), to: .node(.makeOrBuy),
      isIntervention: true,
      title: "Your choice stays locked",
      explanation: "The automation skips this material."
    ),
    PlannerFlowEdge(
      id: .saleChoiceToResults, from: .node(.saleChoice), to: .column(.results), isIntervention: true,
      title: "Sale decision",
      explanation: "It updates the sale display, not the build steps."
    ),
  ]

  static func nodes(in column: PlannerFlowColumn) -> [PlannerFlowNode] {
    nodes.filter { $0.column == column }
  }

  /// Exhaustive so that a new Blueprint stage does not compile until it has its place here.
  static func node(for stage: BlueprintSourceStage) -> PlannerFlowNodeID {
    switch stage {
    case .ownedBPO, .ownedBPC, .contractBPC, .otherSource, .reactionFormula, .none:
      .blueprintSource
    }
  }

  /// Exhaustive so that a new calculation phase does not compile until it has its place here.
  static func node(for phase: PlannerCalculationPhase) -> PlannerFlowNodeID {
    switch phase {
    case .preparing, .cancelling: .calculate
    case .resolvingBlueprints, .applyingBlueprintEfficiencies: .blueprintSource
    case .calculating: .billOfMaterials
    case .saving: .savePlan
    }
  }

  static var allLocalizationKeys: [String] {
    var keys = [panelTitle, summary, "Close", "Release explanation"]
    keys += PlannerFlowRole.allCases.map(\.title)
    keys += PlannerFlowColumn.allCases.map(\.title)
    keys += nodes.flatMap { [$0.title, $0.explanation] }
    keys += edges.flatMap { [$0.title, $0.explanation] }
    return Array(Set(keys)).sorted()
  }
}
