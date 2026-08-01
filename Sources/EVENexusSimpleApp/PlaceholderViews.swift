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
  @AppStorage("planner.disclosure.manual-stock")
  private var isManualStockExpanded = false
  @State private var parseResult = ProductionInputParser.parse("")
  @AppStorage("planner.disclosure.warnings")
  private var areWarningsExpanded = false
  @State private var hasRestoredState = false
  @State private var persistenceMessage: String?
  @State private var persistenceError: String?
  @State private var shoppingListCopyStatus: ShoppingListCopyStatus?
  @State private var assetWarehouse = AssetWarehouse(inventories: [])
  @State private var warehouseFactualQuantities: [Int64: Int64] = [:]
  @State private var isPreparingAssetWarehouse = false
  @State private var calculationTask: Task<Void, Never>?
  @AppStorage("planner.disclosure.sale.immediate")
  private var isImmediateSaleDetailsExpanded = false
  @AppStorage("planner.disclosure.sale.listed")
  private var isListedSaleDetailsExpanded = false
  @AppStorage("planner.disclosure.logistics")
  private var expandedLogisticsDisclosureIDs = "[]"
  @AppStorage("planner.disclosure.blueprints")
  private var expandedBlueprintDisclosureIDs = "[]"
  @AppStorage("planner.disclosure.material-groups")
  private var expandedMaterialDisclosureIDs = "[]"
  @AppStorage("planner.disclosure.shopping-list-markets")
  private var expandedShoppingListMarketDisclosureIDs = "[]"
  @AppStorage("planner.disclosure.production-job-list")
  private var isProductionJobListExpanded = false
  @AppStorage("planner.disclosure.warehouse-replenishment-list")
  private var isWarehouseReplenishmentListExpanded = false
  @AppStorage("planner.disclosure.shopping-list")
  private var isShoppingListExpanded = false
  @State private var procurementPreferences: [Int64: MaterialProcurementPreference] = [:]
  @State private var recommendationApplicationMessage: String?

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
            Button("Calculate") {
              calculatePlan()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(
              !parseResult.isValid || runtime.isWorking
                || isPreparingAssetWarehouse
                || !runtime.isPlannerConfigurationReady
            )
            Spacer()
            if runtime.isWorking {
              ProgressView().controlSize(.small)
              Button("Cancel") {
                calculationTask?.cancel()
              }
              .buttonStyle(.bordered)
              .accessibilityIdentifier("planner.cancel")
            }
            Label(
              "\(parseResult.requests.count) valid products",
              systemImage:
                parseResult.errors.isEmpty
                ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.callout.monospacedDigit())
            .help("The input is checked automatically while typing.")
          }
          Toggle(
            "Use combined warehouse from all synchronized characters",
            isOn: $runtime.warehouseStockEnabled
          )
          .help(
            "Makes protected, unreserved warehouse quantities available. Stock is consumed only for raw materials that you explicitly set to Use warehouse."
          )
          if isPreparingAssetWarehouse {
            Label(
              "Preparing the combined warehouse once…",
              systemImage: "shippingbox.and.arrow.backward"
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          }
          FullWidthDisclosure(isExpanded: $isManualStockExpanded) {
            Text("Manual stock")
          } content: {
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
            .padding(.top, DesignTokens.spacingSM)
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
    .navigationTitle(AppLocalization.text("Planner"))
    .onAppear {
      restoreStateIfNeeded()
      parseResult = ProductionInputParser.parse(input)
    }
    .onDisappear {
      calculationTask?.cancel()
      persistDraft(reportErrors: false)
    }
    .onChange(of: input) {
      parseResult = ProductionInputParser.parse(input)
      persistenceMessage = nil
      shoppingListCopyStatus = nil
      recommendationApplicationMessage = nil
    }
    .task(id: assetProjectionIdentity) {
      await prepareAssetWarehouse()
    }
  }

  @ViewBuilder
  private func resultView(_ plan: IndustryPlanSnapshot) -> some View {
    LazyVGrid(
      columns: [
        GridItem(
          .adaptive(minimum: 320, maximum: 480),
          alignment: .top
        )
      ],
      alignment: .leading,
      spacing: DesignTokens.spacingMD
    ) {
      plannerCostsPanel(plan)
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        warehouseConsumptionPanel(plan)
        taxesAndFeesPanel(plan)
      }
      saleScenarioPanel(
        title: "Immediate sale",
        result: plan.immediateSale,
        totalCost: plan.costBreakdown?.totalProductionCost,
        plan: plan
      )
      saleScenarioPanel(
        title: "Listed sale",
        result: plan.listedSale,
        totalCost: plan.costBreakdown?.totalProductionCost,
        plan: plan
      )
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
        "Choose Buy or Use warehouse for every raw input. Every purchase is assigned to the Profile Main Hub.",
      sections: materialSections(
        for: plan.materials.filter { !$0.isProducedMaterial },
        fallback: "Other raw materials"
      ),
      allowsProcurement: true
    )
    materialPanel(
      title: "Produced materials & intermediates",
      description:
        "Every component and reaction intermediate compares building with buying the complete required quantity at the Profile Main Hub, including logistics. You can still override the recommended source.",
      sections: materialSections(
        for: plan.materials.filter(\.isProducedMaterial),
        fallback: "Other produced materials"
      ),
      allowsProcurement: true
    )
    makeOrBuyRecommendationPanel(plan)
    productionJobListPanel(plan)
    warehouseReplenishmentPanel(plan)
    shoppingListPanel(plan)
    Panel(title: "Jobs and provenance") {
      LabeledContent("Jobs", value: "\(plan.jobs.count)")
      ExplainedPlannerMetricRow(
        label: "Estimated job time",
        value: formatJobDuration(plan.makespanSeconds),
        explanation: AppLocalization.text(
          "Estimated elapsed time uses the configured manufacturing and reaction slot counts. Manufacturing and reaction work can run in parallel; within each activity, jobs are distributed across the available slots."
        ),
        highlightsValue: true
      )
      ExplainedPlannerMetricRow(
        label: "Total job workload",
        value: formatJobDuration(plan.totalJobSeconds),
        explanation: AppLocalization.text(
          "Total workload adds the effective duration of every selected job. Each duration uses SDE base time, runs, the selected facility time multiplier and manufacturing TE; reactions do not use TE."
        ),
        highlightsValue: false
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
        FullWidthDisclosure(isExpanded: $areWarningsExpanded) {
          Text(
            "\(plan.warnings.count) \(plan.warnings.count == 1 ? "warning" : "warnings")"
          )
        } content: {
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
        }
        .accessibilityIdentifier("planner.warnings.disclosure")
      }
    }
  }

  private func plannerCostsPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    Panel(title: "Costs") {
      costMetric(
        "Material replacement (Main Hub)",
        plan.materialCost,
        explanation:
          "Values every input that is not produced inside this plan at the current weighted Main Hub price for the full required quantity. Purchased and warehouse quantities are valued together so market depth is not reused."
      )
      costMetric(
        "BPC/BPO",
        plan.costBreakdown?.blueprintCosts?.total,
        explanation:
          "Adds the entered acquisition cost of consumed BPCs and the owner-entered cost allocation for reusable BPOs. Missing blueprint costs remain excluded and are reported separately."
      )
      costMetric(
        "Installation",
        plan.installationCost,
        explanation:
          "The sum of system-index cost, facility tax, SCC surcharge and any clone surcharge for every job selected for production in this plan."
      )
      Text(installationCostEquation(plan))
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      costMetric(
        "Logistics",
        plan.costBreakdown?.effectiveLogisticsCost,
        explanation:
          "The sum of the generated courier contracts. Each contract uses the higher of volume charge or collateral charge and is then rounded up according to the saved logistics rule."
      )
      Divider()
      costMetric(
        "Total",
        plan.costBreakdown?.totalProductionCost,
        explanation:
          "Material replacement plus BPC/BPO allocation, installation and logistics. The separately displayed warehouse-consumption value and installation components are already included and are not added twice."
      )
      Text(totalCostEquation(plan))
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "Material replacement covers every input that is not produced inside this plan at its current full-requirement Main Hub value. Installation contains its system-index, facility-tax, SCC and clone-surcharge components. Logistics is included whenever the saved logistics rule is enabled and complete."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func warehouseConsumptionPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    Panel(title: "Warehouse consumption") {
      costMetric(
        "Main Hub value of warehouse consumption",
        plan.warehouseConsumptionValue,
        explanation:
          "The current weighted Main Hub replacement value of materials consumed from the combined warehouse. It is already included in material replacement and is shown separately for information, so it is not added again."
      )
    }
  }

  private func taxesAndFeesPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    Panel(title: "Taxes & fees") {
      Text(
        "Installation components below are already included in Installation. Market fees reduce sale revenue and are not production costs."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      explainedMetric(
        "System cost index",
        plan.costBreakdown?.systemIndexCost,
        explanation:
          "The EIV of each selected production job multiplied by its system cost index and applicable job-cost modifier. This amount is already part of Installation."
      )
      explainedMetric(
        "Facility tax",
        plan.costBreakdown?.facilityTax,
        explanation:
          "The estimated item value of each selected production job multiplied by the configured facility tax. It is already part of Installation."
      )
      explainedMetric(
        "SCC surcharge",
        plan.costBreakdown?.sccSurcharge,
        explanation:
          "The estimated item value multiplied by the applicable SCC surcharge for each selected production job. It is already part of Installation."
      )
      explainedMetric(
        "Alpha surcharge",
        plan.costBreakdown?.alphaSurcharge,
        explanation:
          "The clone surcharge applied to eligible production jobs when the configured clone state is Alpha. It is already part of Installation."
      )
      Divider()
      explainedMetric(
        "Immediate sales tax",
        plan.immediateSale.salesTax,
        explanation:
          "Sales tax deducted from the gross immediate-sale value. It reduces revenue and is not added to production cost."
      )
      explainedMetric(
        "Immediate broker fee",
        plan.immediateSale.brokerFee,
        explanation:
          "An immediate sale normally uses existing buy orders and therefore has no listing broker fee. Any calculated value is deducted from revenue, not added to production cost."
      )
      explainedMetric(
        "Listed sales tax",
        plan.listedSale.salesTax,
        explanation:
          "Sales tax deducted from the gross listed-sale value. It reduces revenue and is not added to production cost."
      )
      explainedMetric(
        "Listed broker fee",
        plan.listedSale.brokerFee,
        explanation:
          "Broker fee for placing the listed sell order. It reduces listed-sale revenue and is not added to production cost."
      )
    }
  }

  private func totalCostEquation(_ plan: IndustryPlanSnapshot) -> String {
    AppLocalization.format(
      "%@ material replacement + %@ BPC/BPO + %@ installation + %@ logistics = %@ total production cost.",
      formatISK(plan.materialCost),
      formatISK(plan.costBreakdown?.blueprintCosts?.total),
      formatISK(plan.installationCost),
      formatISK(
        plan.costBreakdown?.effectiveLogisticsCost
      ),
      formatISK(plan.costBreakdown?.totalProductionCost)
    )
  }

  private func installationCostEquation(
    _ plan: IndustryPlanSnapshot
  ) -> String {
    AppLocalization.format(
      "%@ system cost index + %@ facility tax + %@ SCC surcharge + %@ Alpha surcharge = %@ installation.",
      formatISK(plan.costBreakdown?.systemIndexCost),
      formatISK(plan.costBreakdown?.facilityTax),
      formatISK(plan.costBreakdown?.sccSurcharge),
      formatISK(plan.costBreakdown?.alphaSurcharge),
      formatISK(plan.installationCost)
    )
  }

  private func metric(_ label: String, _ value: Double?) -> some View {
    LabeledContent {
      Text(formatISK(value))
        .font(.body.monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
    } label: {
      Text(LocalizedStringKey(label))
    }
  }

  private func costMetric(
    _ label: String,
    _ value: Double?,
    explanation: String
  ) -> some View {
    ExplainedPlannerMetricRow(
      label: label,
      value: formatISK(value),
      explanation: AppLocalization.text(explanation),
      highlightsValue: true
    )
  }

  private func saleScenarioPanel(
    title: String,
    result: SaleScenarioResult,
    totalCost: Double?,
    plan: IndustryPlanSnapshot
  ) -> some View {
    Panel(title: LocalizedStringKey(title)) {
      Text(scenarioSummary(result.scenario))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)

      explainedMetric(
        "Gross revenue",
        result.grossRevenue,
        explanation: grossRevenueExplanation(for: result.scenario)
      )
      explainedMetric(
        "Net revenue",
        result.grossOrNetRevenue,
        explanation:
          "Gross revenue minus sales tax and broker fee. This is the amount left from the sale before production costs."
      )
      explainedMetric(
        "Profit",
        result.profit,
        explanation:
          "Net revenue minus all production costs shown in the Costs panel. A negative value means the plan would make a loss."
      )
      explainedPercent(
        "Margin",
        result.margin,
        explanation:
          "Profit divided by net revenue. It shows how much of every ISK received after market fees remains as profit."
      )
      explainedPercent(
        "ROI",
        result.roi,
        explanation:
          "Profit divided by total production cost. It shows the estimated return on the ISK invested in this production plan."
      )

      FullWidthDisclosureButton(
        isExpanded: isSaleDetailsExpanded(result.scenario),
        action: { toggleSaleDetails(for: result.scenario) }
      ) {
        Text(
          isSaleDetailsExpanded(result.scenario)
            ? "Hide calculation details"
            : "Show calculation details"
        )
      }
      .accessibilityLabel(
        isSaleDetailsExpanded(result.scenario)
          ? "Hide calculation details"
          : "Show calculation details"
      )
      .accessibilityValue(
        isSaleDetailsExpanded(result.scenario) ? "Expanded" : "Collapsed"
      )
      .accessibilityIdentifier(
        "planner.sale.\(result.scenario.rawValue).details"
      )

      if isSaleDetailsExpanded(result.scenario) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
          calculationDetail(
            title: "Market valuation",
            text: marketValuationDetail(for: result)
          )
          calculationDetail(
            title: "Net revenue",
            text: netRevenueEquation(result)
          )
          calculationDetail(
            title: "Profit",
            text: profitEquation(result, totalCost: totalCost)
          )
          calculationDetail(
            title: "Margin",
            text: percentageEquation(
              numerator: result.profit,
              denominator: result.grossOrNetRevenue,
              result: result.margin
            )
          )
          calculationDetail(
            title: "ROI",
            text: percentageEquation(
              numerator: result.profit,
              denominator: totalCost,
              result: result.roi
            )
          )

          if !result.quotes.isEmpty {
            Divider()
            Text("Market inputs")
              .font(.caption.bold())
              .foregroundStyle(DesignTokens.textSecondary)
            ForEach(result.quotes) { quote in
              marketQuoteDetail(
                quote,
                scenario: result.scenario,
                result: result,
                productName: productName(for: quote.typeID, in: plan)
              )
            }
          }
        }
        .padding(.top, DesignTokens.spacingSM)
      }
    }
  }

  private func explainedMetric(
    _ label: String,
    _ value: Double?,
    explanation: String
  ) -> some View {
    ExplainedPlannerMetricRow(
      label: label,
      value: formatISK(value),
      explanation: AppLocalization.text(explanation),
      highlightsValue: true
    )
  }

  private func explainedPercent(
    _ label: String,
    _ value: Double?,
    explanation: String
  ) -> some View {
    ExplainedPlannerMetricRow(
      label: label,
      value: formatPercent(value),
      explanation: AppLocalization.text(explanation),
      highlightsValue: false
    )
  }

  private func isSaleDetailsExpanded(_ scenario: PriceScenario) -> Bool {
    switch scenario {
    case .immediateSale:
      isImmediateSaleDetailsExpanded
    case .listedSale:
      isListedSaleDetailsExpanded
    case .materialBuy:
      false
    }
  }

  private func toggleSaleDetails(for scenario: PriceScenario) {
    switch scenario {
    case .immediateSale:
      isImmediateSaleDetailsExpanded.toggle()
    case .listedSale:
      isListedSaleDetailsExpanded.toggle()
    case .materialBuy:
      break
    }
  }

  private func calculationDetail(
    title: String,
    text: String
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(LocalizedStringKey(title))
        .font(.caption.bold())
      Text(text)
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        .textSelection(.enabled)
    }
  }

  private func marketQuoteDetail(
    _ quote: PriceQuote,
    scenario: PriceScenario,
    result: SaleScenarioResult,
    productName: String
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(productName)
        .font(.caption.bold())
      Text(quoteDetail(quote, scenario: scenario, result: result))
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        .textSelection(.enabled)
    }
    .padding(.vertical, DesignTokens.spacingXS)
  }

  private func scenarioSummary(_ scenario: PriceScenario) -> String {
    let mainHubName = runtime.productionBasis.mainTradeHub.procurementLocation.name
    return switch scenario {
    case .immediateSale:
      AppLocalization.format(
        "Sells the planned output into current %@ buy orders, starting with the highest price. The full requested quantity must be covered.",
        mainHubName
      )
    case .listedSale:
      AppLocalization.format(
        "Estimates a sell order at the current lowest %@ sell price. It assumes the full quantity sells at that price; competition, price changes, relisting, and time to sale are not simulated.",
        mainHubName
      )
    case .materialBuy:
      AppLocalization.format(
        "Uses current %@ sell orders to estimate a material purchase.",
        mainHubName
      )
    }
  }

  private func grossRevenueExplanation(
    for scenario: PriceScenario
  ) -> String {
    let mainHubName = runtime.productionBasis.mainTradeHub.procurementLocation.name
    return switch scenario {
    case .immediateSale:
      AppLocalization.format(
        "The sum of planned product quantities multiplied by the current %@ buy orders that can fill them, from highest price downward.",
        mainHubName
      )
    case .listedSale:
      AppLocalization.format(
        "The planned product quantities multiplied by the current lowest %@ sell-order price for each product.",
        mainHubName
      )
    case .materialBuy:
      AppLocalization.format(
        "The material quantity multiplied by the current %@ sell-order prices needed to fill it.",
        mainHubName
      )
    }
  }

  private func marketValuationDetail(
    for result: SaleScenarioResult
  ) -> String {
    let mainHubName = runtime.productionBasis.mainTradeHub.procurementLocation.name
    let quotedProducts = result.quotes.count
    let quotedUnits = result.quotes.reduce(Int64(0)) {
      safeAdd($0, $1.quantity)
    }
    let filledUnits = result.quotes.reduce(Int64(0)) {
      safeAdd($0, $1.filledQuantity)
    }
    let productText = AppLocalization.format(
      quotedProducts == 1 ? "%lld product" : "%lld products",
      Int64(quotedProducts)
    )
    switch result.scenario {
    case .immediateSale:
      return AppLocalization.format(
        "%@, %@ planned units, %@ units matched against %@ buy orders. Gross revenue: %@.",
        productText,
        quotedUnits.formatted(),
        filledUnits.formatted(),
        mainHubName,
        formatISK(result.grossRevenue)
      )
    case .listedSale:
      return AppLocalization.format(
        "%@, %@ planned units, valued at the current lowest %@ sell-order price. Gross revenue: %@.",
        productText,
        quotedUnits.formatted(),
        mainHubName,
        formatISK(result.grossRevenue)
      )
    case .materialBuy:
      return AppLocalization.format(
        "%@, %@ units valued against %@ sell orders.",
        productText,
        quotedUnits.formatted(),
        mainHubName
      )
    }
  }

  private func netRevenueEquation(_ result: SaleScenarioResult) -> String {
    guard let gross = result.grossRevenue,
      let salesTax = result.salesTax,
      let brokerFee = result.brokerFee,
      let net = result.grossOrNetRevenue
    else {
      return AppLocalization.text(
        "Unavailable because at least one market or fee input is missing."
      )
    }
    let salesTaxRate = rate(amount: salesTax, base: gross)
    let brokerFeeRate = rate(amount: brokerFee, base: gross)
    return AppLocalization.format(
      "%@ gross − %@ sales tax (%@) − %@ broker fee (%@) = %@ net revenue.",
      formatISK(gross),
      formatISK(salesTax),
      formatPercent(salesTaxRate),
      formatISK(brokerFee),
      formatPercent(brokerFeeRate),
      formatISK(net)
    )
  }

  private func profitEquation(
    _ result: SaleScenarioResult,
    totalCost: Double?
  ) -> String {
    guard let net = result.grossOrNetRevenue,
      let totalCost,
      let profit = result.profit
    else {
      return AppLocalization.text(
        "Unavailable because net revenue or total production cost is missing."
      )
    }
    return AppLocalization.format(
      "%@ net revenue − %@ total production cost = %@ profit.",
      formatISK(net),
      formatISK(totalCost),
      formatISK(profit)
    )
  }

  private func percentageEquation(
    numerator: Double?,
    denominator: Double?,
    result: Double?
  ) -> String {
    guard let numerator, let denominator, let result else {
      return AppLocalization.text(
        "Unavailable because one of the required values is missing or zero."
      )
    }
    return AppLocalization.format(
      "%@ ÷ %@ × 100 = %@.",
      formatISK(numerator),
      formatISK(denominator),
      formatPercent(result)
    )
  }

  private func quoteDetail(
    _ quote: PriceQuote,
    scenario: PriceScenario,
    result: SaleScenarioResult
  ) -> String {
    let capturedAt = quote.capturedAt.formatted(
      date: .abbreviated,
      time: .shortened
    )
    guard quote.isComplete else {
      return AppLocalization.format(
        "%@ of %@ units covered · quote incomplete · market snapshot %@.",
        quote.filledQuantity.formatted(),
        quote.quantity.formatted(),
        capturedAt
      )
    }
    switch scenario {
    case .immediateSale, .materialBuy:
      return AppLocalization.format(
        "%@ units × %@ weighted market price = %@ · snapshot %@.",
        quote.quantity.formatted(),
        formatISK(quote.weightedUnitPrice),
        formatISK(quote.total),
        capturedAt
      )
    case .listedSale:
      let grossUnitPrice = listedGrossUnitPrice(
        quote: quote,
        result: result
      )
      return AppLocalization.format(
        "%@ units × %@ lowest sell-order price = %@ gross · snapshot %@.",
        quote.quantity.formatted(),
        formatISK(grossUnitPrice),
        formatISK(grossUnitPrice.map { $0 * Double(quote.quantity) }),
        capturedAt
      )
    }
  }

  private func listedGrossUnitPrice(
    quote: PriceQuote,
    result: SaleScenarioResult
  ) -> Double? {
    guard let weightedNetPrice = quote.weightedUnitPrice,
      let gross = result.grossRevenue,
      gross > 0,
      let salesTax = result.salesTax,
      let brokerFee = result.brokerFee
    else { return nil }
    let retainedShare = 1 - (salesTax + brokerFee) / gross
    guard retainedShare > 0 else { return nil }
    return weightedNetPrice / retainedShare
  }

  private func productName(
    for typeID: Int64,
    in plan: IndustryPlanSnapshot
  ) -> String {
    plan.nodes.first {
      $0.typeID == typeID && $0.action == .produce
        && $0.topLevelRequestID != nil
    }?.name ?? "Type \(typeID)"
  }

  private func rate(amount: Double, base: Double) -> Double? {
    guard base != 0 else { return nil }
    let value = amount / base
    return value.isFinite ? value : nil
  }

  private func safeAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int64.max : sum
  }

  private func formatPercent(_ value: Double?) -> String {
    value.map {
      $0.formatted(.percent.precision(.fractionLength(2)))
    } ?? AppLocalization.text("Unavailable")
  }

  private func logisticsPanel(
    _ logistics: LogisticsCostBreakdown
  ) -> some View {
    Panel(title: "Logistics breakdown") {
      ForEach(logistics.legs) { leg in
        FullWidthDisclosure(
          isExpanded: disclosureBinding(
            id: logisticsDisclosureID(leg),
            encodedIDs: $expandedLogisticsDisclosureIDs
          )
        ) {
          HStack(alignment: .center, spacing: DesignTokens.spacingMD) {
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              Text(
                AppLocalization.format(
                  "%@ · Contract %lld of %lld",
                  AppLocalization.text(leg.kind.displayName),
                  Int64(leg.contractNumber ?? 1),
                  Int64(leg.contractCount ?? 1)
                )
              )
              .font(.headline)
              Text("\(leg.origin) → \(leg.destination)")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer(minLength: DesignTokens.spacingMD)
            Text(formatISK(leg.roundedCharge))
              .font(.headline.monospacedDigit())
              .foregroundStyle(DesignTokens.highlight)
          }
        } content: {
          VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            LabeledContent {
              Text(
                leg.cargoVolumeM3.formatted(
                  .number.precision(.fractionLength(0...2))
                ) + " m³"
              )
              .font(.body.monospacedDigit())
            } label: {
              Text("Cargo volume")
            }
            metric("Accurate collateral", leg.collateral)
            metric("Volume charge", leg.volumeCharge)
            metric("0.5% collateral charge", leg.collateralCharge)
            LabeledContent {
              Text(
                LocalizedStringKey(
                  leg.chargedBy == .volume ? "Cargo volume" : "Collateral"
                )
              )
            } label: {
              Text("Charged by")
            }
            metric("Before rounding", leg.unroundedCharge)
            metric("Rounded contract", leg.roundedCharge)
          }
          .padding(.top, DesignTokens.spacingMD)
        }
        .padding(DesignTokens.spacingSM)
        .background(DesignTokens.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
      }
      metric("Total logistics", logistics.total)
      Text(
        AppLocalization.format(
          "Maximum %@ m³ per contract · oversized routes are split automatically · each contract is rounded up in %@ steps · %@",
          logistics.maximumContractVolumeM3.formatted(),
          formatISK(logistics.roundingIncrement),
          logistics.ruleVersion
        )
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
        FullWidthDisclosure(
          isExpanded: disclosureBinding(
            id: blueprintDisclosureID(entry),
            encodedIDs: $expandedBlueprintDisclosureIDs
          )
        ) {
          HStack(spacing: DesignTokens.spacingMD) {
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
              Text(entry.productName)
                .font(.headline)
              Text(LocalizedStringKey(entry.kind.rawValue))
                .font(.caption.bold())
                .foregroundStyle(DesignTokens.highlight)
            }
            Spacer(minLength: DesignTokens.spacingMD)
            Text(formatISK(entry.amount))
              .font(.headline.monospacedDigit())
              .foregroundStyle(DesignTokens.highlight)
          }
        } content: {
          Text(LocalizedStringKey(entry.treatment))
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.top, DesignTokens.spacingSM)
        }
        .padding(DesignTokens.spacingSM)
        .background(DesignTokens.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
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
          AppLocalization.format(
            "No blueprint cost entered for: %@. These costs are not included.",
            names
          ),
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
    sections: [PlannerMaterialSection],
    allowsProcurement: Bool = false
  ) -> some View {
    if !sections.isEmpty {
      Panel(title: LocalizedStringKey(title)) {
        Text(AppLocalization.text(description))
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
        ForEach(sections) { section in
          FullWidthDisclosure(
            isExpanded: disclosureBinding(
              id: "\(title):\(section.id)",
              encodedIDs: $expandedMaterialDisclosureIDs
            )
          ) {
            HStack(spacing: DesignTokens.spacingSM) {
              Text(section.name)
                .font(.headline)
              Text(
                AppLocalization.format(
                  "%lld items",
                  Int64(section.materials.count)
                )
              )
              .font(.caption.monospacedDigit())
              .foregroundStyle(DesignTokens.textSecondary)
            }
          } content: {
            materialGrid(
              section.materials,
              allowsProcurement: allowsProcurement
            )
            .padding(.top, DesignTokens.spacingMD)
          }
          .padding(DesignTokens.spacingSM)
          .background(DesignTokens.elevated)
          .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
        }
      }
    }
  }

  @ViewBuilder
  private func materialGrid(
    _ materials: [MaterialRequirement],
    allowsProcurement: Bool
  ) -> some View {
    let factualQuantities = warehouseFactualQuantities
    let targets = targetQuantities
    if allowsProcurement {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        ForEach(materials) { material in
          VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            HStack {
              Text(material.name).font(.headline)
              Spacer()
              Text("Required \(material.required.formatted())")
                .font(.body.monospacedDigit())
            }
            HStack(spacing: DesignTokens.spacingMD) {
              procurementQuantity(
                "Warehouse",
                factualQuantities[material.typeID, default: 0]
              )
              procurementQuantity(
                "Protected",
                targets[material.typeID, default: 0]
              )
              procurementQuantity("Used", material.fromStock)
              procurementQuantity("To buy", material.toBuy)
              if material.canProduce {
                procurementQuantity("To produce", material.toProduce)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 1) {
                Text("Full replacement")
                Text(formatISK(material.replacementQuote?.total))
                  .font(.caption.monospacedDigit())
              }
              .foregroundStyle(DesignTokens.highlight)
            }
            HStack(spacing: DesignTokens.spacingSM) {
              Picker(
                "Source",
                selection: supplyModeBinding(for: material)
              ) {
                ForEach(supplyModes(for: material), id: \.self) { mode in
                  Text(LocalizedStringKey(mode.displayName)).tag(mode)
                }
              }
              .labelsHidden()
              .pickerStyle(.segmented)
              .frame(width: material.canProduce ? 315 : 210)
              .disabled(runtime.isWorking)
              Label(
                preference(for: material).purchaseLocation.name,
                systemImage: "building.columns"
              )
              .font(.caption)
              .foregroundStyle(DesignTokens.textSecondary)
              .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let analysis = material.makeOrBuyAnalysis {
              makeOrBuyAnalysisView(analysis)
            }
          }
          Divider()
        }
        Label(
          "Changing a source immediately recalculates materials, costs, production jobs, Main Hub shopping lists and transport.",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      }
    } else {
      Grid(
        alignment: .leading,
        horizontalSpacing: 24,
        verticalSpacing: 8
      ) {
        GridRow {
          Text("Item")
          Text("Required")
          Text("Produced")
          Text("Activity")
        }
        .font(.caption.bold())
        .foregroundStyle(DesignTokens.textSecondary)
        Divider()
        ForEach(materials) { material in
          GridRow {
            Text(material.name)
            number(material.required)
            number(material.toProduce)
            Text(material.productionActivity?.rawValue ?? "—")
              .foregroundStyle(DesignTokens.textSecondary)
          }
        }
      }
    }
  }

  private func procurementQuantity(_ label: String, _ value: Int64)
    -> some View
  {
    VStack(alignment: .leading, spacing: 1) {
      Text(AppLocalization.text(label))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      number(value)
    }
  }

  private func makeOrBuyRecommendationPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    let application = MakeOrBuyRecommendationApplication(
      materials: plan.materials,
      existingPreferences: procurementPreferences,
      mainHub: runtime.productionBasis.mainTradeHub.procurementLocation
    )

    return Panel(title: "Apply make-or-buy analysis") {
      Text(
        "Applies every available build or buy recommendation, recalculates all costs, and then creates the matching production jobs and Main Hub shopping list. Raw-material and unavailable choices remain unchanged."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      if application.hasApplicableRecommendations {
        Text(
          AppLocalization.format(
            "Recommendations: %lld total · %lld build · %lld buy · %lld unavailable. Unavailable choices remain unchanged.",
            Int64(application.appliedCount),
            Int64(application.produceCount),
            Int64(application.buyCount),
            Int64(application.unavailableCount)
          )
        )
        .font(.callout.monospacedDigit())
      } else {
        Label(
          "No usable recommendation is available. Calculate the plan first or resolve its warnings.",
          systemImage: "exclamationmark.triangle"
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.caution)
      }

      Button {
        applyMakeOrBuyRecommendations(application)
      } label: {
        Label(
          "Apply recommendations and calculate",
          systemImage: "wand.and.stars"
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        !application.hasApplicableRecommendations
          || runtime.isWorking
          || !parseResult.isValid
          || isPreparingAssetWarehouse
          || !runtime.isPlannerConfigurationReady
      )
      .accessibilityIdentifier("planner.make-or-buy.apply")

      if let recommendationApplicationMessage {
        Label(
          recommendationApplicationMessage,
          systemImage: "checkmark.circle.fill"
        )
        .font(.callout)
        .foregroundStyle(DesignTokens.positive)
      }
    }
  }

  @ViewBuilder
  private func makeOrBuyAnalysisView(
    _ analysis: MaterialMakeOrBuyAnalysis
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      HStack(spacing: DesignTokens.spacingSM) {
        Label(
          makeOrBuyRecommendationText(analysis.recommendation),
          systemImage: makeOrBuyRecommendationIcon(analysis.recommendation)
        )
        .font(.headline)
        .foregroundStyle(makeOrBuyRecommendationColor(analysis.recommendation))
        Spacer()
        if let savings = analysis.savings {
          Text(
            AppLocalization.format(
              "Save %@ with the recommended option",
              formatISK(savings)
            )
          )
          .font(.headline.monospacedDigit())
          .foregroundStyle(DesignTokens.positive)
        }
      }

      Text(
        AppLocalization.format(
          "Main Hub: %@ · available %lld of %lld",
          analysis.mainHub.name,
          analysis.purchaseQuote.filledQuantity,
          analysis.requiredQuantity
        )
      )
      .font(.caption)
      .foregroundStyle(
        analysis.purchaseQuote.isComplete
          ? DesignTokens.textSecondary : DesignTokens.caution
      )

      Grid(
        alignment: .leading,
        horizontalSpacing: DesignTokens.spacingLG,
        verticalSpacing: DesignTokens.spacingXS
      ) {
        GridRow {
          Text("")
          Text("Buy at Main Hub")
          Text("Build")
        }
        .font(.caption.bold())
        .foregroundStyle(DesignTokens.textSecondary)
        GridRow {
          Text("Market / inputs")
          Text(formatISK(analysis.purchaseQuote.total))
          Text(formatISK(analysis.buildMaterialCost))
        }
        GridRow {
          Text("Installation")
          Text(formatISK(0))
          Text(formatISK(analysis.buildInstallationCost))
        }
        GridRow {
          Text("Logistics")
          Text(formatISK(analysis.purchaseLogisticsCost))
          Text(formatISK(analysis.buildLogisticsCost))
        }
        GridRow {
          Text("Total")
            .font(.body.bold())
          Text(formatISK(analysis.purchaseTotalCost))
          Text(formatISK(analysis.buildTotalCost))
        }
        .font(.body.monospacedDigit())
      }

      Text(
        AppLocalization.format(
          "Build quantity: %lld from %lld runs for %lld required units.",
          analysis.producedQuantity,
          Int64(analysis.productionRuns),
          analysis.requiredQuantity
        )
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      ForEach(analysis.warnings.filter { $0.severity != .information }) {
        warning in
        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(DesignTokens.caution)
      }
    }
    .padding(DesignTokens.spacingSM)
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
  }

  private func makeOrBuyRecommendationText(
    _ recommendation: MakeOrBuyRecommendation
  ) -> String {
    switch recommendation {
    case .produce: AppLocalization.text("Recommendation: Build")
    case .buy: AppLocalization.text("Recommendation: Buy")
    case .unavailable: AppLocalization.text("Recommendation unavailable")
    }
  }

  private func makeOrBuyRecommendationIcon(
    _ recommendation: MakeOrBuyRecommendation
  ) -> String {
    switch recommendation {
    case .produce: "hammer.fill"
    case .buy: "cart.fill"
    case .unavailable: "questionmark.diamond.fill"
    }
  }

  private func makeOrBuyRecommendationColor(
    _ recommendation: MakeOrBuyRecommendation
  ) -> Color {
    switch recommendation {
    case .produce: DesignTokens.positive
    case .buy: DesignTokens.highlight
    case .unavailable: DesignTokens.caution
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
    let groups = Dictionary(
      grouping: plan.materials.filter { $0.toBuy > 0 }
    ) {
      $0.procurement?.purchaseLocation ?? .jita
    }
    .map { (location: $0.key, materials: $0.value) }
    .sorted { $0.location.name < $1.location.name }
    let purchasedMaterials = groups.flatMap(\.materials)
    let totalQuantity = purchasedMaterials.reduce(Int64(0)) {
      safeAdd($0, $1.toBuy)
    }
    return Panel(title: "EVE shopping list") {
      FullWidthDisclosure(isExpanded: $isShoppingListExpanded) {
        Label {
          Text(
            AppLocalization.format(
              "%lld items · %lld units to buy",
              Int64(purchasedMaterials.count),
              totalQuantity
            )
          )
          .font(.headline.monospacedDigit())
        } icon: {
          Image(systemName: "cart")
        }
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          if groups.isEmpty {
            Label(
              "This plan has no materials to buy.",
              systemImage: "checkmark.circle"
            )
            .foregroundStyle(DesignTokens.textSecondary)
          } else {
            Text(
              "The EVE Multibuy list contains the complete uncovered quantity to buy at the Profile Main Hub."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
            ForEach(groups, id: \.location.id) { group in
              let shoppingList = EVEShoppingList.make(from: group.materials)
              let export = EVEMultibuyExport.make(from: group.materials)
              VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                FullWidthDisclosure(
                  isExpanded: disclosureBinding(
                    id: group.location.id,
                    encodedIDs: $expandedShoppingListMarketDisclosureIDs
                  )
                ) {
                  HStack(alignment: .center, spacing: DesignTokens.spacingMD) {
                    Label("Market", systemImage: "cart")
                      .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(group.location.name)
                      Text(
                        AppLocalization.format(
                          "%lld items · %lld units to buy",
                          Int64(shoppingList.items.count),
                          shoppingList.totalQuantity
                        )
                      )
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(DesignTokens.textSecondary)
                    }
                  }
                } content: {
                  shoppingListDetails(shoppingList)
                    .padding(.top, DesignTokens.spacingMD)
                }
                .accessibilityIdentifier(
                  "planner.shopping-list.market.\(group.location.id)"
                )
                HStack {
                  Text(
                    "Open Market to review every item before exporting it to EVE."
                  )
                  .font(.caption)
                  .foregroundStyle(DesignTokens.textSecondary)
                  Spacer()
                  Button {
                    copyShoppingList(export)
                  } label: {
                    Label("Copy Multibuy", systemImage: "doc.on.doc")
                  }
                  .buttonStyle(.borderedProminent)
                  .accessibilityIdentifier("planner.shopping-list.copy")
                }
              }
              .padding(DesignTokens.spacingMD)
              .background(DesignTokens.elevated)
              .clipShape(
                RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
              )
            }
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
        .padding(.top, DesignTokens.spacingMD)
      }
      .accessibilityIdentifier("planner.shopping-list.disclosure")
    }
  }

  private func shoppingListDetails(
    _ shoppingList: EVEShoppingList
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Grid(
        alignment: .leading,
        horizontalSpacing: DesignTokens.spacingLG,
        verticalSpacing: DesignTokens.spacingSM
      ) {
        GridRow {
          Text("Item")
          Text("Quantity")
          Text("Unit price")
          Text("Total")
          Text("Market coverage")
        }
        .font(.caption.bold())
        .foregroundStyle(DesignTokens.textSecondary)
        Divider()
        ForEach(shoppingList.items) { item in
          let quote = item.hasCompleteMarketCoverage ? item.marketQuote : nil
          GridRow {
            Text(item.name)
            Text(item.quantity.formatted())
              .monospacedDigit()
            Text(formatISK(quote?.weightedUnitPrice))
              .monospacedDigit()
            Text(formatISK(quote?.total))
              .monospacedDigit()
            Text(marketCoverageText(for: item))
              .foregroundStyle(
                item.hasCompleteMarketCoverage
                  ? DesignTokens.positive : DesignTokens.caution
              )
          }
        }
        Divider()
        GridRow {
          Text("Market purchase total")
            .fontWeight(.semibold)
          Text(shoppingList.totalQuantity.formatted())
            .fontWeight(.semibold)
            .monospacedDigit()
          Text("—")
            .foregroundStyle(DesignTokens.textSecondary)
          Text(formatISK(shoppingList.purchaseTotal))
            .fontWeight(.semibold)
            .monospacedDigit()
          Text(
            AppLocalization.text(
              shoppingList.purchaseTotal == nil
                ? "Incomplete market data" : "Complete"
            )
          )
          .foregroundStyle(
            shoppingList.purchaseTotal == nil
              ? DesignTokens.caution : DesignTokens.positive
          )
        }
      }
      Text(
        "Prices and totals are shown only when sell orders cover the complete quantity at the Profile Main Hub. Logistics remains separate in the logistics breakdown."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func marketCoverageText(
    for item: EVEShoppingListItem
  ) -> String {
    guard let quote = item.marketQuote else {
      return AppLocalization.text("Unavailable")
    }
    guard item.hasCompleteMarketCoverage else {
      return AppLocalization.format(
        "%lld of %lld units",
        quote.filledQuantity,
        item.quantity
      )
    }
    return AppLocalization.text("Complete")
  }

  private func productionJobListPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    let jobs = plan.jobs.sorted { lhs, rhs in
      if lhs.isTopLevel != rhs.isTopLevel {
        return lhs.isTopLevel == true
      }
      return (lhs.productName ?? "Type \(lhs.typeID)")
        .localizedCaseInsensitiveCompare(
          rhs.productName ?? "Type \(rhs.typeID)"
        ) == .orderedAscending
    }

    return Panel(title: "Production job list") {
      FullWidthDisclosure(isExpanded: $isProductionJobListExpanded) {
        Label {
          Text(
            AppLocalization.format(
              "%lld production jobs",
              Int64(jobs.count)
            )
          )
          .font(.headline.monospacedDigit())
        } icon: {
          Image(systemName: "hammer.fill")
        }
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          if jobs.isEmpty {
            Label(
              "This plan has no production jobs.",
              systemImage: "checkmark.circle"
            )
            .foregroundStyle(DesignTokens.textSecondary)
          } else {
            Text(
              "These are the production jobs from the recalculated plan. Purchased items are excluded and appear in the Main Hub shopping list instead."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)

            ForEach(jobs) { job in
              VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                HStack(alignment: .firstTextBaseline) {
                  Text(job.productName ?? "Type \(job.typeID)")
                    .font(.headline)
                  Text(
                    LocalizedStringKey(
                      job.isTopLevel == true
                        ? "Final product" : "Intermediate"
                    )
                  )
                  .font(.caption.bold())
                  .foregroundStyle(
                    job.isTopLevel == true
                      ? DesignTokens.highlight : DesignTokens.textSecondary
                  )
                  Spacer()
                  VStack(alignment: .trailing, spacing: 1) {
                    Text("Installation")
                      .font(.caption)
                      .foregroundStyle(DesignTokens.textSecondary)
                    Text(formatISK(job.total))
                      .font(.body.monospacedDigit())
                      .foregroundStyle(DesignTokens.highlight)
                  }
                }

                HStack(spacing: DesignTokens.spacingLG) {
                  Label {
                    Text(LocalizedStringKey(job.activity.rawValue.capitalized))
                  } icon: {
                    Image(
                      systemName:
                        job.activity == .reaction ? "atom" : "hammer.fill"
                    )
                  }
                  if let runs = job.runs,
                    let outputQuantity = job.outputQuantity
                  {
                    Text(
                      AppLocalization.format(
                        "%lld runs · %lld output units",
                        Int64(runs),
                        outputQuantity
                      )
                    )
                    .font(.body.monospacedDigit())
                  } else {
                    Text("Recalculate to resolve runs and output quantity.")
                      .foregroundStyle(DesignTokens.caution)
                  }
                  if let materialEfficiency = job.materialEfficiency,
                    let timeEfficiency = job.timeEfficiency
                  {
                    Text("ME \(materialEfficiency) · TE \(timeEfficiency)")
                      .font(.body.monospacedDigit())
                  }
                  Spacer()
                }
                .font(.callout)

                if let facilityName = job.facilityName?.nonEmpty {
                  Label(facilityName, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                }
              }
              .padding(.vertical, DesignTokens.spacingXS)
              Divider()
            }
          }
        }
        .padding(.top, DesignTokens.spacingMD)
      }
      .accessibilityIdentifier("planner.production-job-list.disclosure")
    }
  }

  private func warehouseReplenishmentPanel(
    _ plan: IndustryPlanSnapshot
  ) -> some View {
    let groups = warehouseReplenishmentGroups(plan.materials)
    let replenishmentMaterials = groups.flatMap(\.materials)
    let totalQuantity = replenishmentMaterials.reduce(Int64(0)) {
      safeAdd($0, $1.fromStock)
    }

    return Panel(title: "Warehouse replenishment list") {
      FullWidthDisclosure(isExpanded: $isWarehouseReplenishmentListExpanded) {
        Label {
          Text(
            AppLocalization.format(
              "%lld items · %lld units to replenish",
              Int64(replenishmentMaterials.count),
              totalQuantity
            )
          )
          .font(.headline.monospacedDigit())
        } icon: {
          Image(systemName: "shippingbox.and.arrow.backward")
        }
      } content: {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
          if groups.isEmpty {
            Label(
              "This plan consumes no warehouse materials.",
              systemImage: "checkmark.circle"
            )
            .foregroundStyle(DesignTokens.textSecondary)
          } else {
            Text(
              "These quantities were consumed from warehouse stock and must be bought back to restore it. This is a separate future replenishment list; it is not added to the immediate shopping list or charged twice. Unit prices and values use the current Main Hub replacement quote."
            )
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)

            ForEach(groups, id: \.location.id) { group in
              let export = EVEMultibuyExport.makeWarehouseReplenishment(
                from: group.materials
              )
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(group.location.name).font(.headline)
                  Text("Planned replacement hub")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Button {
                  copyShoppingList(export)
                } label: {
                  Label(
                    "Copy replenishment Multibuy",
                    systemImage: "doc.on.doc"
                  )
                }
                .buttonStyle(.bordered)
              }

              Grid(
                alignment: .leading,
                horizontalSpacing: 20,
                verticalSpacing: 7
              ) {
                GridRow {
                  Text("Item")
                  Text("Quantity")
                  Text("Main Hub unit price")
                  Text("Replacement value")
                }
                .font(.caption.bold())
                .foregroundStyle(DesignTokens.textSecondary)
                Divider()
                ForEach(group.materials) { material in
                  GridRow {
                    Text(material.name)
                    Text(material.fromStock.formatted())
                      .font(.body.monospacedDigit())
                    Text(
                      formatISK(
                        material.replacementQuote?.weightedUnitPrice
                      )
                    )
                    .font(.body.monospacedDigit())
                    Text(formatISK(material.warehouseConsumptionValue))
                      .font(.body.monospacedDigit())
                      .foregroundStyle(DesignTokens.highlight)
                  }
                }
              }
            }
          }
        }
        .padding(.top, DesignTokens.spacingMD)
      }
      .accessibilityIdentifier(
        "planner.warehouse-replenishment-list.disclosure"
      )
    }
  }

  private func warehouseReplenishmentGroups(
    _ materials: [MaterialRequirement]
  ) -> [PlannerWarehouseReplenishmentGroup] {
    let consumed = materials.filter { $0.fromStock > 0 }
    let grouped: [ProcurementLocation: [MaterialRequirement]] = Dictionary(
      grouping: consumed,
      by: { $0.procurement?.purchaseLocation ?? .jita }
    )
    return grouped.map { location, groupedMaterials in
      PlannerWarehouseReplenishmentGroup(
        location: location,
        materials: groupedMaterials.sorted {
          $0.name.localizedCaseInsensitiveCompare($1.name)
            == .orderedAscending
        }
      )
    }
    .sorted { $0.location.name < $1.location.name }
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
    guard let value else { return AppLocalization.text("Unavailable") }
    return value.formatted(
      .currency(code: "ISK").precision(.fractionLength(0))
    )
  }

  private func formatJobDuration(_ seconds: Int64) -> String {
    guard seconds >= 0, seconds < Int64.max else {
      return AppLocalization.text("Unavailable")
    }
    let wholeMinutes = seconds / 60
    let roundedMinutes = wholeMinutes + (seconds % 60 == 0 ? 0 : 1)
    let days = roundedMinutes / (24 * 60)
    let hours = (roundedMinutes % (24 * 60)) / 60
    let minutes = roundedMinutes % 60
    if days > 0 {
      return AppLocalization.format(
        "%lld d %lld h %lld min",
        days,
        hours,
        minutes
      )
    }
    if hours > 0 {
      return AppLocalization.format("%lld h %lld min", hours, minutes)
    }
    return AppLocalization.format("%lld min", minutes)
  }

  private func disclosureBinding(
    id: String,
    encodedIDs: Binding<String>
  ) -> Binding<Bool> {
    Binding(
      get: { PlannerDisclosureStorage.contains(id, in: encodedIDs.wrappedValue) },
      set: { isExpanded in
        encodedIDs.wrappedValue = PlannerDisclosureStorage.updating(
          encodedIDs.wrappedValue,
          id: id,
          isExpanded: isExpanded
        )
      }
    )
  }

  private func logisticsDisclosureID(_ leg: LogisticsCostLeg) -> String {
    [
      leg.kind.rawValue,
      leg.origin,
      leg.destination,
      String(leg.contractNumber ?? 1),
    ].joined(separator: "|")
  }

  private func blueprintDisclosureID(_ entry: BlueprintCostEntry) -> String {
    "\(entry.productName)|\(entry.kind.rawValue)"
  }

  private func materialCost(
    for quantity: Int64,
    quote: PriceQuote?
  ) -> Double? {
    quantity == 0 ? 0 : quote?.total
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
    if let plan = restored.plan {
      procurementPreferences = Dictionary(
        uniqueKeysWithValues: plan.materials.compactMap { material in
          material.procurement.map { (material.typeID, $0) }
        }
      )
    }
  }

  private var procurementLocations: [ProcurementLocation] {
    let locations = runtime.productionBasis.configuredProcurementLocations
    return (locations.isEmpty ? [.jita] : locations)
      .sorted { $0.name < $1.name }
  }

  private func preference(for material: MaterialRequirement)
    -> MaterialProcurementPreference
  {
    var candidate =
      procurementPreferences[material.typeID]
      ?? material.procurement
      ?? MaterialProcurementPreference(
        supplyMode:
          material.canProduce && material.toProduce > 0 ? .produce : .buy
      )
    if candidate.supplyMode == .produce, !material.canProduce {
      candidate.supplyMode = .buy
    }
    candidate.purchaseLocation =
      runtime.productionBasis.mainTradeHub.procurementLocation
    return candidate
  }

  private func supplyModeBinding(for material: MaterialRequirement)
    -> Binding<MaterialSupplyMode>
  {
    Binding(
      get: { preference(for: material).supplyMode },
      set: { value in
        var updated = preference(for: material)
        guard updated.supplyMode != value else { return }
        updated.supplyMode = value
        var requestedPreferences = procurementPreferences
        requestedPreferences[material.typeID] = updated
        procurementPreferences = requestedPreferences
        recommendationApplicationMessage = nil
        calculatePlan(preferences: requestedPreferences)
      }
    )
  }

  private func supplyModes(for material: MaterialRequirement)
    -> [MaterialSupplyMode]
  {
    material.canProduce ? [.produce, .buy, .warehouse] : [.buy, .warehouse]
  }

  private func purchaseLocationBinding(for material: MaterialRequirement)
    -> Binding<ProcurementLocation>
  {
    Binding(
      get: { preference(for: material).purchaseLocation },
      set: { value in
        var updated = preference(for: material)
        updated.purchaseLocation = value
        procurementPreferences[material.typeID] = updated
      }
    )
  }

  private func applyMakeOrBuyRecommendations(
    _ application: MakeOrBuyRecommendationApplication
  ) {
    guard application.hasApplicableRecommendations else { return }
    procurementPreferences = application.preferences
    recommendationApplicationMessage = nil
    let successMessage = AppLocalization.format(
      "Applied %lld recommendations (%lld build, %lld buy). Costs, production jobs and the Main Hub shopping list were recalculated. Unavailable choices left unchanged: %lld.",
      Int64(application.appliedCount),
      Int64(application.produceCount),
      Int64(application.buyCount),
      Int64(application.unavailableCount)
    )
    calculatePlan(
      preferences: application.preferences,
      recommendationSuccessMessage: successMessage
    )
  }

  private func calculatePlan(
    preferences: [Int64: MaterialProcurementPreference]? = nil,
    recommendationSuccessMessage: String? = nil
  ) {
    let requestedPreferences = preferences ?? procurementPreferences
    calculationTask = Task { @MainActor in
      defer { calculationTask = nil }
      guard runtime.isPlannerConfigurationReady else { return }
      persistDraft()
      await runtime.calculate(
        input: input,
        manualStockInput: manualStockInput,
        existingReservations: activeReservations,
        assetWarehouse: assetWarehouse,
        stockTargets: targetQuantities,
        procurementPreferences: requestedPreferences
      )
      guard !Task.isCancelled else { return }
      guard runtime.errorMessage == nil, let plan = runtime.plan else { return }
      procurementPreferences = Dictionary(
        uniqueKeysWithValues: plan.materials.compactMap { material in
          material.procurement.map { (material.typeID, $0) }
        }
      )
      saveActivePlan(plan)
      recommendationApplicationMessage = recommendationSuccessMessage
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

  private var targetQuantities: [Int64: Int64] {
    Dictionary(
      uniqueKeysWithValues: stockTargets.map {
        ($0.typeID, max(0, $0.targetQuantity))
      }
    )
  }

  private var assetProjectionIdentity: String {
    let characterPart = storedCharacters.map { character in
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
    return characterPart + "|production:" + productionPart
  }

  private func prepareAssetWarehouse() async {
    isPreparingAssetWarehouse = true
    defer { isPreparingAssetWarehouse = false }
    let payloads = storedCharacters.compactMap { character in
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
    let productionWarehouse = await runtime.prepareProductionWarehouse(
      from: prepared
    )
    guard !Task.isCancelled else { return }
    assetWarehouse = productionWarehouse.warehouse
    warehouseFactualQuantities = productionWarehouse.factualQuantities
  }
}

private enum PlannerDisclosureStorage {
  static func contains(_ id: String, in encodedIDs: String) -> Bool {
    decoded(encodedIDs).contains(id)
  }

  static func updating(
    _ encodedIDs: String,
    id: String,
    isExpanded: Bool
  ) -> String {
    var ids = decoded(encodedIDs)
    if isExpanded {
      ids.insert(id)
    } else {
      ids.remove(id)
    }
    guard
      let data = try? JSONEncoder().encode(ids.sorted()),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return encodedIDs
    }
    return encoded
  }

  private static func decoded(_ encodedIDs: String) -> Set<String> {
    guard let data = encodedIDs.data(using: .utf8),
      let ids = try? JSONDecoder().decode([String].self, from: data)
    else {
      return []
    }
    return Set(ids)
  }
}

private struct ExplainedPlannerMetricRow: View {
  let label: String
  let value: String
  let explanation: String
  let highlightsValue: Bool

  @State private var isExplanationPresented = false

  var body: some View {
    let localizedLabel = AppLocalization.text(label)
    Button {
      isExplanationPresented.toggle()
    } label: {
      VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
        HStack(spacing: DesignTokens.spacingXS) {
          Text(LocalizedStringKey(label))
          Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(DesignTokens.information)
            .accessibilityHidden(true)
          Spacer(minLength: DesignTokens.spacingSM)
        }
        Text(value)
          .font(.body.monospacedDigit())
          .foregroundStyle(
            highlightsValue
              ? DesignTokens.highlight : DesignTokens.textPrimary
          )
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .help(
      AppLocalization.format(
        "Click for an explanation of %@.",
        localizedLabel
      )
    )
    .popover(
      isPresented: $isExplanationPresented,
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .bottom
    ) {
      VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
        HStack {
          Text(LocalizedStringKey(label))
            .font(.headline)
          Spacer()
          Button {
            isExplanationPresented = false
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close explanation")
        }
        Text(explanation)
          .foregroundStyle(DesignTokens.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .padding(DesignTokens.spacingMD)
      .frame(width: 460)
    }
    .accessibilityLabel("\(localizedLabel), \(value)")
    .accessibilityHint(
      AppLocalization.text("Shows an explanation of this value.")
    )
  }
}

private struct PlannerMaterialSection: Identifiable {
  var id: String { name }
  let name: String
  let materials: [MaterialRequirement]
}

private struct PlannerWarehouseReplenishmentGroup: Identifiable {
  var id: String { location.id }
  let location: ProcurementLocation
  let materials: [MaterialRequirement]
}

struct ReactionsView: View {
  @EnvironmentObject private var runtime: RuntimeState
  @AppStorage("reactions.analysis-runs") private var runs = 100
  @AppStorage("reactions.trade-hub") private var tradeHubRaw =
    MarketTradeHub.jita.rawValue
  @State private var searchText = ""
  @State private var valueFilter = ReactionValueFilter.all
  @State private var selectedGroup = ReactionGroupFilter.all
  @State private var sortOrder = ReactionAnalysisSortOrder.valueCreationDescending
  @State private var expandedReactionIDs = Set<Int64>()
  @State private var analysisTask: Task<Void, Never>?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text("Reaction profitability")
            .font(.largeTitle.bold())
          Text(
            "Compares every complete published SDE reaction against live order depth at the selected trade hub. Inputs are bought from sell orders; outputs are valued both as a replacement purchase and as an immediate sale to buy orders."
          )
          .foregroundStyle(DesignTokens.textSecondary)
        }

        controls

        if runtime.isAnalyzingReactions {
          Panel(title: "Market analysis") {
            HStack(spacing: DesignTokens.spacingMD) {
              ProgressView()
              VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text("Analyzing all reactions…")
                  .font(.headline)
                Text(
                  "The app is loading every required input and output order book. The previous complete result remains visible while prices refresh."
                )
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
              }
            }
          }
        }

        if let error = runtime.reactionAnalysisError {
          Panel(title: "Analysis unavailable") {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(DesignTokens.negative)
            Button("Try again") { startAnalysis() }
              .buttonStyle(.borderedProminent)
          }
        }

        if let snapshot = runtime.reactionAnalysis {
          basisPanel(snapshot)
          summary(snapshot)
          results(snapshot)
        } else if !runtime.isAnalyzingReactions,
          runtime.reactionAnalysisError == nil
        {
          Panel(title: "No analysis yet") {
            Text(
              "Start the analysis to evaluate all reactions from the active SDE catalog."
            )
            .foregroundStyle(DesignTokens.textSecondary)
          }
        }
      }
      .padding(DesignTokens.spacingLG)
      .frame(maxWidth: 1_500, alignment: .leading)
    }
    .searchable(text: $searchText, prompt: "Search reactions or materials")
    .task(id: runtime.isPlannerConfigurationReady) {
      guard runtime.isPlannerConfigurationReady,
        runtime.reactionAnalysis == nil,
        !runtime.isAnalyzingReactions
      else { return }
      runs = sanitizedRuns
      await runtime.analyzeReactions(
        runs: sanitizedRuns,
        tradeHub: selectedTradeHub
      )
    }
    .onDisappear { analysisTask?.cancel() }
  }

  private var controls: some View {
    Panel(title: "Calculation settings") {
      HStack(alignment: .bottom, spacing: DesignTokens.spacingMD) {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text("Trade hub")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          Picker("Trade hub", selection: $tradeHubRaw) {
            ForEach(MarketTradeHub.allCases) { hub in
              Text(hub.name).tag(hub.rawValue)
            }
          }
          .labelsHidden()
          .frame(minWidth: 330)
          .accessibilityIdentifier("reactions.trade-hub")
        }
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
          Text("Runs")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          HStack(spacing: DesignTokens.spacingSM) {
            TextField("Runs", value: $runs, format: .number)
              .frame(width: 110)
              .textFieldStyle(.roundedBorder)
              .accessibilityIdentifier("reactions.runs")
            Stepper("", value: $runs, in: 1...maximumSelectableRuns)
              .labelsHidden()
          }
        }
        Button {
          startAnalysis()
        } label: {
          Label("Analyze all reactions", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .disabled(runtime.isAnalyzingReactions)
        .accessibilityIdentifier("reactions.analyze")
        Spacer()
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(
          "100 runs are preconfigured. CCP does not define one global reaction-run maximum: the 30-day job limit is calculated per formula from its SDE duration and the current time basis. If one run already exceeds 30 days, that single run remains allowed."
        )
        HStack(spacing: 3) {
          Text("Current analysis range")
          Text(verbatim: "1–\(maximumSelectableRuns.formatted())")
          Text("runs")
          Text(
            "The per-formula job limit and required job count are shown in every result."
          )
        }
      }
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)

      if let snapshot = runtime.reactionAnalysis,
        snapshot.runs != sanitizedRuns
          || snapshot.tradeHub != selectedTradeHub
      {
        Label(
          "Settings changed. Analyze again to replace the displayed snapshot.",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption)
        .foregroundStyle(DesignTokens.caution)
      }
    }
  }

  private func basisPanel(_ snapshot: ReactionAnalysisSnapshot) -> some View {
    Panel(title: "Calculation basis") {
      HStack(alignment: .firstTextBaseline) {
        Label(
          snapshot.basis == .configuredFacility
            ? "Configured reaction facility"
            : "SDE material baseline",
          systemImage:
            snapshot.basis == .configuredFacility
            ? "building.2.fill" : "doc.text.magnifyingglass"
        )
        .font(.headline)
        Spacer()
        if snapshot.basis == .configuredFacility {
          Text(verbatim: snapshot.basisName)
            .foregroundStyle(DesignTokens.highlight)
        }
      }
      if snapshot.basis == .configuredFacility {
        Text(
          "Material multipliers, reaction time, system cost index, facility tax, SCC surcharge and clone surcharge are included from the verified Profile configuration."
        )
      } else {
        Text(
          "Value creation and make-or-buy use unmodified SDE material quantities only. Installation, structure, rig and clone costs are unavailable and are not treated as zero. Configure a valid reaction refinery and system in Profile for a complete facility comparison."
        )
      }
      Text(
        "Positive value creation means buying the produced output from sell orders costs more than the evaluated reaction cost. The immediate-sale spread is shown separately and uses current buy orders before character-specific sales tax."
      )
      .font(.caption)
      .foregroundStyle(DesignTokens.textSecondary)
      ForEach(snapshot.warnings) { warning in
        Label(
          localizedWarning(warning),
          systemImage: warning.severity == .blocking
            ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(
          warning.severity == .blocking
            ? DesignTokens.negative : DesignTokens.caution
        )
      }
      Divider()
      HStack {
        Text("SDE build")
        Text(verbatim: snapshot.sdeSource.version)
        Text("•")
        Text("Market")
        Text(verbatim: snapshot.tradeHub.name)
        Text("•")
        Text(snapshot.marketSource.capturedAt.formatted(date: .abbreviated, time: .shortened))
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(DesignTokens.textSecondary)
    }
  }

  private func summary(_ snapshot: ReactionAnalysisSnapshot) -> some View {
    let rows = snapshot.rows
    let positive = rows.filter { $0.valueStatus == .positive }.count
    let negative = rows.filter { $0.valueStatus == .negative }.count
    let unavailable = rows.filter { $0.valueStatus == .unavailable }.count
    let cheaperToMake = rows.filter { $0.makeIsCheaperThanBuy == true }.count
    return LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 180, maximum: 280))],
      alignment: .leading,
      spacing: DesignTokens.spacingMD
    ) {
      summaryCard("All reactions", rows.count, DesignTokens.information)
      summaryCard("Positive value", positive, DesignTokens.positive)
      summaryCard("Negative value", negative, DesignTokens.negative)
      summaryCard("Cheaper to make", cheaperToMake, DesignTokens.highlight)
      if unavailable > 0 {
        summaryCard("Price unavailable", unavailable, DesignTokens.caution)
      }
    }
  }

  private func summaryCard(
    _ title: String,
    _ value: Int,
    _ color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value.formatted())
        .font(.title2.bold().monospacedDigit())
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DesignTokens.spacingMD)
    .background(DesignTokens.panel)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }

  private func results(_ snapshot: ReactionAnalysisSnapshot) -> some View {
    let rows = filteredRows(snapshot.rows)
    return Panel(title: "All reaction results") {
      HStack(spacing: DesignTokens.spacingMD) {
        Picker("Value", selection: $valueFilter) {
          ForEach(ReactionValueFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .frame(width: 180)
        Picker("Reaction type", selection: $selectedGroup) {
          Text("All reaction types").tag(ReactionGroupFilter.all)
          ForEach(groupNames(snapshot.rows), id: \.self) { group in
            Text(group).tag(ReactionGroupFilter.named(group))
          }
        }
        .frame(minWidth: 260)
        Picker("Sort", selection: $sortOrder) {
          ForEach(ReactionAnalysisSortOrder.allCases, id: \.self) { order in
            Text(order.title).tag(order)
          }
        }
        .frame(width: 220)
        Spacer()
        Text("\(rows.count) / \(snapshot.rows.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(DesignTokens.textSecondary)
      }
      if rows.isEmpty {
        Text("No reactions match the current filters.")
          .foregroundStyle(DesignTokens.textSecondary)
          .padding(.vertical, DesignTokens.spacingLG)
      } else {
        LazyVStack(spacing: DesignTokens.spacingSM) {
          ForEach(rows) { row in
            reactionRow(row)
          }
        }
      }
    }
  }

  private func reactionRow(_ row: ReactionAnalysisRow) -> some View {
    FullWidthDisclosure(isExpanded: reactionExpansionBinding(row.id)) {
      HStack(spacing: DesignTokens.spacingMD) {
        VStack(alignment: .leading, spacing: 2) {
          Text(row.productName).font(.headline)
          Text(row.groupName)
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("Value creation")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          Text(formatSignedISK(row.valueCreation))
            .font(.body.bold().monospacedDigit())
            .foregroundStyle(statusColor(row.valueStatus))
        }
        .frame(minWidth: 145, alignment: .trailing)
        VStack(alignment: .trailing, spacing: 2) {
          Text("Value margin")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          Text(formatPercent(row.valueCreationMargin))
            .font(.body.bold().monospacedDigit())
            .foregroundStyle(statusColor(row.valueStatus))
        }
        .frame(minWidth: 105, alignment: .trailing)
        VStack(alignment: .trailing, spacing: 2) {
          Text("Make or buy")
            .font(.caption)
            .foregroundStyle(DesignTokens.textSecondary)
          Text(makeOrBuyLabel(row))
            .font(.body.weight(.semibold))
            .foregroundStyle(
              row.makeIsCheaperThanBuy == nil
                ? DesignTokens.textDisabled
                : row.makeIsCheaperThanBuy == true
                  ? DesignTokens.positive : DesignTokens.negative
            )
        }
        .frame(minWidth: 130, alignment: .trailing)
      }
      .padding(DesignTokens.spacingMD)
    } content: {
      VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180, maximum: 280))],
          alignment: .leading,
          spacing: DesignTokens.spacingSM
        ) {
          reactionMetric("Input purchase", row.materialCost)
          reactionMetric("Installation", row.installationCost)
          reactionMetric("Evaluated reaction cost", row.evaluatedCost)
          reactionMetric("Buy produced output", row.outputBuyCost)
          reactionMetric("Immediate-sale revenue", row.immediateSaleRevenue)
          reactionMetric("Immediate-sale spread", row.immediateSaleSpread)
          reactionMetric("Make-or-buy savings", row.makeOrBuySavings)
          reactionMetric("Value creation", row.valueCreation)
          reactionMetricPercent("Value margin", row.valueCreationMargin)
        }
        Divider()
        HStack(alignment: .top, spacing: DesignTokens.spacingLG) {
          materialList("Inputs", row.inputs)
          materialList("Outputs", row.outputs)
        }
        HStack {
          Label("\(row.runs.formatted()) runs", systemImage: "repeat")
          Label(formatDuration(row.durationSeconds), systemImage: "clock")
          Label(
            "Max. \(row.maximumRunsPerJob.formatted()) runs per job",
            systemImage: "calendar.badge.clock"
          )
          if row.requiredJobCount > 1 {
            Label(
              "\(row.requiredJobCount.formatted()) jobs required",
              systemImage: "square.stack.3d.up"
            )
          }
          Text("Formula")
          Text(row.blueprintTypeID.formatted())
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(DesignTokens.textSecondary)
        if !row.warnings.isEmpty {
          Divider()
          ForEach(row.warnings) { warning in
            Label(
              localizedWarning(warning),
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(
              warning.severity == .blocking
                ? DesignTokens.negative : DesignTokens.caution
            )
          }
        }
      }
      .padding(.horizontal, DesignTokens.spacingMD)
      .padding(.bottom, DesignTokens.spacingMD)
    }
    .background(DesignTokens.elevated)
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
        .stroke(DesignTokens.border)
    }
  }

  private func reactionMetric(_ title: String, _ value: Double?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(formatISK(value))
        .font(.body.monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
    }
  }

  private func reactionMetricPercent(
    _ title: String,
    _ value: Double?
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(DesignTokens.textSecondary)
      Text(value?.formatted(.percent.precision(.fractionLength(1))) ?? "—")
        .font(.body.monospacedDigit())
        .foregroundStyle(DesignTokens.highlight)
    }
  }

  private func materialList(
    _ title: String,
    _ materials: [ReactionMaterialValuation]
  ) -> some View {
    VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
      Text(LocalizedStringKey(title)).font(.headline)
      ForEach(materials) { material in
        HStack {
          VStack(alignment: .leading, spacing: 1) {
            Text(material.name)
            HStack(spacing: 3) {
              Text(material.quantity.formatted())
              Text("units")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(DesignTokens.textSecondary)
          }
          Spacer()
          Text(formatISK(material.quote.total))
            .font(.body.monospacedDigit())
            .foregroundStyle(DesignTokens.highlight)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func filteredRows(
    _ rows: [ReactionAnalysisRow]
  ) -> [ReactionAnalysisRow] {
    let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = rows.filter { row in
      let matchesSearch =
        needle.isEmpty
        || row.productName.localizedCaseInsensitiveContains(needle)
        || row.groupName.localizedCaseInsensitiveContains(needle)
        || row.inputs.contains {
          $0.name.localizedCaseInsensitiveContains(needle)
        }
        || row.outputs.contains {
          $0.name.localizedCaseInsensitiveContains(needle)
        }
      let matchesValue = valueFilter.matches(row.valueStatus)
      let matchesGroup: Bool
      switch selectedGroup {
      case .all: matchesGroup = true
      case .named(let group): matchesGroup = row.groupName == group
      }
      return matchesSearch && matchesValue && matchesGroup
    }
    return sortOrder.sorted(filtered)
  }

  private func groupNames(_ rows: [ReactionAnalysisRow]) -> [String] {
    Array(Set(rows.map(\.groupName))).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
  }

  private var selectedTradeHub: MarketTradeHub {
    MarketTradeHub(rawValue: tradeHubRaw) ?? .jita
  }

  private var sanitizedRuns: Int {
    min(max(1, runs), maximumSelectableRuns)
  }

  private var maximumSelectableRuns: Int {
    max(
      1,
      runtime.reactionAnalysis?.maximumSelectableRuns
        ?? ReactionJobRules.neutralMaximumSelectableRuns
    )
  }

  private func reactionExpansionBinding(_ id: Int64) -> Binding<Bool> {
    Binding(
      get: { expandedReactionIDs.contains(id) },
      set: { isExpanded in
        if isExpanded {
          expandedReactionIDs.insert(id)
        } else {
          expandedReactionIDs.remove(id)
        }
      }
    )
  }

  private func startAnalysis() {
    runs = sanitizedRuns
    analysisTask?.cancel()
    analysisTask = Task { @MainActor in
      defer { analysisTask = nil }
      await runtime.analyzeReactions(
        runs: sanitizedRuns,
        tradeHub: selectedTradeHub
      )
    }
  }

  private func makeOrBuyLabel(
    _ row: ReactionAnalysisRow
  ) -> LocalizedStringKey {
    guard let make = row.makeIsCheaperThanBuy else { return "Unavailable" }
    return make ? "Make" : "Buy"
  }

  private func statusColor(_ status: ReactionValueStatus) -> Color {
    switch status {
    case .positive: DesignTokens.positive
    case .negative: DesignTokens.negative
    case .neutral: DesignTokens.textSecondary
    case .unavailable: DesignTokens.caution
    }
  }

  private func localizedWarning(
    _ warning: DomainWarning
  ) -> LocalizedStringKey {
    switch warning.code {
    case "market.insufficient-depth":
      "The selected trade hub does not have enough order-book depth for the configured runs."
    default:
      LocalizedStringKey(warning.message)
    }
  }

  private func formatISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(
      .currency(code: "ISK")
        .precision(.fractionLength(0))
    )
  }

  private func formatSignedISK(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    let formatted = abs(value).formatted(
      .currency(code: "ISK").precision(.fractionLength(0))
    )
    if value > 0 { return "+\(formatted)" }
    if value < 0 { return "−\(formatted)" }
    return formatted
  }

  private func formatPercent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return value.formatted(.percent.precision(.fractionLength(1)))
  }

  private func formatDuration(_ seconds: Int64) -> String {
    guard seconds < Int64.max else { return "—" }
    return Duration.seconds(seconds).formatted(
      .units(allowed: [.days, .hours, .minutes], width: .abbreviated)
    )
  }
}

private enum ReactionValueFilter: String, CaseIterable, Identifiable {
  case all
  case positive
  case negative
  case neutral
  case unavailable

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .all: "All values"
    case .positive: "Positive"
    case .negative: "Negative"
    case .neutral: "Neutral"
    case .unavailable: "Unavailable"
    }
  }

  func matches(_ status: ReactionValueStatus) -> Bool {
    switch self {
    case .all: true
    case .positive: status == .positive
    case .negative: status == .negative
    case .neutral: status == .neutral
    case .unavailable: status == .unavailable
    }
  }
}

private enum ReactionGroupFilter: Hashable {
  case all
  case named(String)
}

extension ReactionAnalysisSortOrder {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .valueCreationDescending: "Value creation (highest first)"
    case .valueCreationAscending: "Value creation (lowest first)"
    case .makeSavingsDescending: "Make savings (highest first)"
    case .marginDescending: "Margin (highest first)"
    case .nameAscending: "Name"
    }
  }
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
                Text(LocalizedStringKey($0.rawValue)).tag($0)
              }
            }
            Picker(
              "Clone",
              selection: $runtime.manufacturingProfile.cloneState
            ) {
              ForEach(CloneState.allCases, id: \.self) {
                Text(LocalizedStringKey($0.rawValue)).tag($0)
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
                  Text(LocalizedStringKey($0.rawValue)).tag($0)
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
      .navigationTitle(AppLocalization.text("Profiles"))
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
                  FullWidthDisclosureButton(
                    isExpanded:
                      selectedScopeCharacterID == character.characterID,
                    action: { toggleScopeDetails(for: character) }
                  ) {
                    HStack(spacing: DesignTokens.spacingSM) {
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
                      Spacer()
                      Text(character.lastSyncAt?.formatted() ?? "Never synced")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignTokens.textSecondary)
                    }
                  }
                  .accessibilityLabel(
                    "Show loaded scopes for \(character.characterName)"
                  )
                  .accessibilityValue(
                    selectedScopeCharacterID == character.characterID
                      ? "Expanded" : "Collapsed"
                  )
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
              Text(AppLocalization.text(connectionPhaseText))
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
    .navigationTitle(AppLocalization.text("Characters"))
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

  private var connectionPhaseText: String {
    switch runtime.characterConnectionPhase {
    case .idle, .waitingForBrowser:
      "Waiting for secure browser callback…"
    case .completingSSO:
      "EVE SSO accepted the callback; verifying authorization…"
    case .synchronizingESI:
      "SSO connected; synchronizing character data from ESI…"
    }
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
      batchMessage = completionMessage(for: character.characterName)
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
    var incompleteCharacters = 0
    let ordered = characters.sorted {
      $0.characterName.localizedCaseInsensitiveCompare($1.characterName)
        == .orderedAscending
    }
    defer {
      isSyncingAll = false
      batchMessage =
        failures.isEmpty
        ? allCharactersCompletionMessage(
          total: ordered.count,
          incomplete: incompleteCharacters
        )
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
        if latestIncompleteDomainCount > 0 {
          incompleteCharacters += 1
        }
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
    guard let latest = runtime.lastCharacterSync else { return }
    let previousCapabilities = character.capabilitySnapshot.flatMap {
      try? JSONDecoder().decode(CharacterCapabilitySnapshot.self, from: $0)
    }
    let retainedCapabilities = CharacterCapabilitySnapshot(
      id: latest.capabilities.id,
      character: latest.capabilities.character,
      cloneState: latest.capabilities.cloneState,
      skills: latest.capabilities.skills.retainingLastKnownValue(
        from: previousCapabilities?.skills
      ),
      standings: latest.capabilities.standings.retainingLastKnownValue(
        from: previousCapabilities?.standings
      )
    )
    character.capabilitySnapshot = try JSONEncoder().encode(
      retainedCapabilities
    )
    character.assetSnapshot = try retainedSnapshotData(
      latest.assets,
      previousData: character.assetSnapshot
    )
    character.blueprintSnapshot = try retainedSnapshotData(
      latest.blueprints,
      previousData: character.blueprintSnapshot
    )
    character.walletBalanceSnapshot = try retainedSnapshotData(
      latest.walletBalance,
      previousData: character.walletBalanceSnapshot
    )
    character.lastSyncAt = .now
    if latest.walletBalance.value != nil {
      character.walletLastSyncAt = latest.walletBalance.source.capturedAt
    }
    try persistLatestSnapshotMetadata()
  }

  private func retainedSnapshotData<Value: Codable & Sendable>(
    _ latest: Sourced<Value>,
    previousData: Data?
  ) throws -> Data {
    let previous = previousData.flatMap {
      try? JSONDecoder().decode(Sourced<Value>.self, from: $0)
    }
    return try JSONEncoder().encode(
      latest.retainingLastKnownValue(from: previous)
    )
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
    if let authError = error as? AuthError {
      switch authError {
      case .missingClientID, .invalidClientID:
        return AppLocalization.text(
          "The EVE client ID is missing or invalid."
        )
      case .noStoredAuthorization:
        return AppLocalization.text(
          "The local EVE authorization is missing. Authorize this character again."
        )
      case .tokenExchangeFailed(let status):
        return String(
          format: AppLocalization.text(
            "EVE SSO rejected the token request (HTTP %lld)."
          ),
          Int64(status)
        )
      case .keychain(_):
        return AppLocalization.text(
          "The EVE refresh token could not be read from the macOS Keychain."
        )
      case .callbackDenied(_):
        return AppLocalization.text(
          "EVE SSO authorization was cancelled or denied."
        )
      case .invalidIdentityToken:
        return AppLocalization.text(
          "EVE SSO returned an identity token that could not be verified."
        )
      default:
        return AppLocalization.text(
          "EVE SSO authorization could not be completed."
        )
      }
    }
    if let esiError = error as? ESIError {
      switch esiError {
      case .rateLimited(_):
        return AppLocalization.text(
          "EVE ESI is rate-limiting requests. Wait briefly and try again."
        )
      case .server(_):
        return AppLocalization.text(
          "EVE ESI reported a temporary server error."
        )
      case .forbidden, .missingScope(_), .authorizationRequired:
        return AppLocalization.text(
          "EVE ESI rejected the authorization or a required permission is missing."
        )
      case .cancelled:
        return AppLocalization.text("Synchronization was cancelled.")
      default:
        return AppLocalization.text(
          "EVE ESI data could not be synchronized."
        )
      }
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .timedOut:
        return AppLocalization.text(
          "The EVE service did not respond in time. Check the CCP status and try again."
        )
      case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
        .networkConnectionLost:
        return AppLocalization.text(
          "The EVE service is currently unreachable. Check the network and CCP status."
        )
      default:
        break
      }
    }
    return AppLocalization.text(
      "The EVE connection failed for an unknown reason."
    )
  }

  private var latestIncompleteDomainCount: Int {
    guard let sync = runtime.lastCharacterSync else { return 0 }
    let states = [
      sync.capabilities.skills.state,
      sync.capabilities.standings.state,
      sync.assets.state,
      sync.blueprints.state,
      sync.jobs.state,
      sync.openOrders.state,
      sync.orderHistory.state,
      sync.walletBalance.state,
      sync.walletJournal.state,
      sync.walletTransactions.state,
    ]
    return states.filter { $0 != .fresh }.count
  }

  private func completionMessage(for characterName: String) -> String {
    let incomplete = latestIncompleteDomainCount
    guard incomplete > 0 else {
      return String(
        format: AppLocalization.text("%@ was synchronized completely."),
        characterName
      )
    }
    return String(
      format: AppLocalization.text(
        "%@ was synchronized; %lld data areas need attention."
      ),
      characterName,
      Int64(incomplete)
    )
  }

  private func allCharactersCompletionMessage(
    total: Int,
    incomplete: Int
  ) -> String {
    guard incomplete > 0 else {
      return String(
        format: AppLocalization.text(
          "All %lld characters were synchronized completely."
        ),
        Int64(total)
      )
    }
    return String(
      format: AppLocalization.text(
        "All %lld characters finished; %lld have incomplete or unavailable ESI data."
      ),
      Int64(total),
      Int64(incomplete)
    )
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
      Text(LocalizedStringKey(state.rawValue.uppercased()))
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
    .navigationTitle(AppLocalization.text("Wallet"))
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
      let previous = character.walletBalanceSnapshot.flatMap {
        try? JSONDecoder().decode(Sourced<Double>.self, from: $0)
      }
      let retained = balance.retainingLastKnownValue(from: previous)
      character.walletBalanceSnapshot = try JSONEncoder().encode(retained)
      if balance.value != nil {
        character.walletLastSyncAt = balance.source.capturedAt
      }
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
    Text(LocalizedStringKey(state.rawValue.uppercased()))
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
  @State private var ownerContactMessage: String?
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
          .onSubmit {
            _ = saveOwnerContact()
          }
          .onChange(of: ownerContact) {
            ownerContactMessage = nil
          }
          Text(
            "This contact is saved locally on this Mac and sent to CCP only as part of SDE requests."
          )
          .font(.caption)
          .foregroundStyle(DesignTokens.textSecondary)
          HStack {
            Button("Save contact") {
              _ = saveOwnerContact()
            }
            .disabled(normalizedOwnerContact.isEmpty || runtime.isWorking)
            Button("Check for SDE update") {
              checkSDEUpdate()
            }
            .disabled(normalizedOwnerContact.isEmpty || runtime.isWorking)
            if runtime.isWorking {
              ProgressView().controlSize(.small)
              Text(runtime.installationPhase ?? runtime.statusMessage)
                .font(.caption.monospaced())
            }
          }
          if let ownerContactMessage {
            Text(ownerContactMessage)
              .font(.caption)
              .foregroundStyle(DesignTokens.positive)
          }
          if let preview = runtime.updatePreview {
            Divider()
            if let checkedAt = runtime.sdeLastCheckedAt {
              LabeledContent(
                "Checked",
                value: checkedAt.formatted()
              )
            }
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
            LabeledContent(
              "Latest CCP schema boundary",
              value: String(preview.schemaHighestAfterBuild)
            )
            Label(
              updateAvailabilityMessage(preview),
              systemImage: preview.requiresUpdate
                ? "arrow.down.circle"
                : "checkmark.circle"
            )
            Label(
              preview.requiresSchemaReview
                ? "Schema review confirmation is required."
                : "No schema boundary newer than the installed build was reported by CCP.",
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
    .navigationTitle(AppLocalization.text("Data & Settings"))
    .onAppear {
      clientID =
        settings.first(where: { $0.key == "eve.clientID" })?
        .value ?? ""
      ownerContact =
        settings.first(
          where: { $0.key == "sde.ownerContact" }
        )?.value ?? ""
      Task { await reconcileSDEActivationPointer() }
    }
    .onDisappear {
      persistOwnerContactOnExit()
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

  private var normalizedOwnerContact: String {
    ownerContact.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isOwnerContactValid: Bool {
    let normalized = normalizedOwnerContact
    return !normalized.isEmpty
      && normalized.utf8.count <= 512
      && normalized.unicodeScalars.allSatisfy {
        $0.value >= 32 && $0.value <= 126
          && $0 != "(" && $0 != ")"
      }
  }

  @discardableResult
  private func saveOwnerContact(showMessage: Bool = true) -> Bool {
    let normalized = normalizedOwnerContact
    guard isOwnerContactValid else {
      if showMessage {
        ownerContactMessage = nil
        settingsError =
          "The CCP User-Agent contact must use visible ASCII characters, must not contain parentheses, and must be no longer than 512 bytes."
      }
      return false
    }
    do {
      try saveSetting(key: "sde.ownerContact", value: normalized)
      ownerContact = normalized
      settingsError = nil
      if showMessage {
        ownerContactMessage =
          "The CCP User-Agent contact was saved locally."
      }
      return true
    } catch {
      if showMessage {
        ownerContactMessage = nil
        settingsError =
          "The CCP User-Agent contact could not be saved. The previous value remains active."
      }
      return false
    }
  }

  private func persistOwnerContactOnExit() {
    let stored =
      settings.first(where: { $0.key == "sde.ownerContact" })?
      .value ?? ""
    guard !normalizedOwnerContact.isEmpty,
      normalizedOwnerContact != stored
    else { return }
    _ = saveOwnerContact(showMessage: false)
  }

  private func checkSDEUpdate() {
    guard saveOwnerContact() else { return }
    schemaReviewConfirmed = false
    Task { await runtime.checkSDE(ownerContact: ownerContact) }
  }

  private func updateAvailabilityMessage(
    _ preview: SDEUpdatePreview
  ) -> LocalizedStringKey {
    switch preview.availability {
    case .notInstalled:
      "No SDE catalog is installed yet."
    case .updateAvailable:
      "A newer official SDE build is available."
    case .current:
      "The installed SDE catalog matches the current official build."
    case .localBuildAhead:
      "The installed build is newer than the official metadata response. No downgrade will be offered."
    }
  }

  private func beginSDEInstallation() {
    guard saveOwnerContact(showMessage: false) else {
      settingsError =
        "The owner contact could not be saved, so the SDE installation was not started."
      return
    }
    settingsError = nil
    Task { await installSDEAndRecordActivation() }
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

  private func reconcileSDEActivationPointer() async {
    await runtime.refreshActiveBuild()
    guard let build = runtime.activeSDEBuild,
      let hash = runtime.activeSDEContentSHA256
    else { return }
    if let pointer = activationPointers.first(where: { $0.key == "active" }) {
      guard pointer.buildNumber != build || pointer.contentSHA256 != hash else {
        return
      }
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
      settingsError =
        "The active SDE catalog was found, but its local database pointer could not be reconciled. The catalog files were not changed."
    }
  }
}
