import AppKit
import EVENexusCore
import SwiftData
import SwiftUI

enum ConsolidationArea: String, CaseIterable, Identifiable {
  case science = "Wissenschaftsaufträge"
  case sales = "Verkaufsbelege"
  var id: Self { self }
}

struct ConsolidationWorkbenchView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @Environment(\.dismiss) private var dismiss
  let area: ConsolidationArea

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(area.rawValue).font(.title2.bold())
        Spacer()
        Button("Schließen") {
          controller.error = nil
          controller.preview = nil
          dismiss()
        }.keyboardShortcut(.cancelAction)
      }
      ConsolidationChangeStatusView()
      Group {
        switch area {
        case .science: ConsolidationScienceView()
        case .sales: ConsolidationSalesView()
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(20).frame(minWidth: 660, idealWidth: 920, minHeight: 560, idealHeight: 760)
    .onDisappear {
      controller.error = nil
      controller.preview = nil
    }
  }
}

struct ConsolidationChangeStatusView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @Environment(RuntimeState.self) private var runtime

  var body: some View {
    if let error = controller.error {
      Text(error)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
    if let preview = controller.preview {
      GroupBox("Vorschau – noch nicht gespeichert") {
        VStack(alignment: .leading) {
          ScrollView {
            Text(
              (Array(preview.summary.prefix(200))
                + (preview.summary.count > 200
                  ? [
                    "Weitere Zeilen: \(preview.summary.count - 200). Vollständige Vorschau exportieren."
                  ] : []))
                .joined(separator: "\n")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
          }
          .frame(maxHeight: 150)
          HStack {
            Button("Bestätigen und speichern") {
              controller.confirm(catalogBuild: runtime.activeSDEBuild)
            }
            .buttonStyle(.borderedProminent)
            Button("Vorschau exportieren") {
              let panel = NSSavePanel()
              panel.nameFieldStringValue = "Vorschau.txt"
              if panel.runModal() == .OK, let url = panel.url {
                do {
                  try preview.summary.joined(separator: "\n").write(
                    to: url,
                    atomically: true,
                    encoding: .utf8
                  )
                } catch {
                  controller.error = error.localizedDescription
                }
              }
            }
            Button("Verwerfen") { controller.preview = nil }
          }
        }
      }
    }
  }
}

func optionalCents(_ text: String) throws -> Int64? {
  let value = text.trimmingCharacters(in: .whitespaces)
  if value.isEmpty { return nil }
  if ["0", "0.00", "0,00"].contains(value) { return 0 }
  return try ISKAmount.parse(GroupedNumberText.ungrouped(value)).hundredths
}

private struct ConsolidationSalesView: View {
  @EnvironmentObject private var controller: ConsolidationController
  @Environment(RuntimeState.self) private var runtime
  @Environment(\.modelContext) private var context
  @Query(sort: \StoredProductionOverviewRow.recordedAt, order: .reverse) private var rows:
    [StoredProductionOverviewRow]
  @State private var rowID: UUID?
  @State private var evidenceID: String?
  @State private var journalID: Int64?
  @State private var quantity = ""
  @State private var price = ""
  @State private var date = Date()
  @State private var switchMode = false
  var body: some View {
    Form {
      Picker("Produktion", selection: $rowID) {
        Text("Auswählen").tag(Optional<UUID>.none)
        ForEach(rows) {
          Text("\($0.sequenceNumber) · \($0.productName) · \($0.units)").tag(Optional($0.id))
        }
      }
      Text(
        "Kosten und frühere manuelle Verkaufswerte werden beim ersten Beleg unveränderlich gesichert. Belegte Erlöse werden separat ausgewiesen; die bisherige manuelle Angabe wird im Belegmodus nicht zusätzlich gezählt."
      ).font(.caption)
      Button("Verkäufe aus letzter Wallet-Synchronisierung prüfen") { importWallet() }
      TextField("Menge", text: $quantity)
        .groupedNumberInput($quantity, allowsFraction: false)
      TextField("Manueller Einzelpreis in ISK", text: $price)
        .groupedNumberInput($price)
      DatePicker("Belegdatum", selection: $date)
      Button("Manuellen Verkaufsbeleg prüfen") { manualReceipt() }
      Picker("Journalbeleg (Typ und Menge aus ausgewählter Produktion)", selection: $journalID) {
        Text("Auswählen").tag(Optional<Int64>.none)
        ForEach(
          runtime.lastCharacterSync?.walletJournal.value?.filter {
            ($0.amount ?? 0) > 0 && $0.refType != "market_transaction"
          } ?? []
        ) { entry in
          Text(
            "\(entry.journalID) · \(entry.refType) · \(entry.amount.map { String(format: "%.2f", $0) } ?? "unbekannt") ISK"
          ).tag(Optional(entry.journalID))
        }
      }
      Button("Journalbetrag ausdrücklich als Verkauf prüfen") { journalReceipt() }
      Text(
        "Journalbuchungen enthalten keine verlässliche Artikelmenge. Typ und Menge werden hier ausdrücklich bestätigt. Market-Transaction-Journalzeilen sind ausgeschlossen, damit derselbe Marktverkauf nicht zweimal importiert wird."
      ).font(.caption)

      Picker("Verkaufsbeleg", selection: $evidenceID) {
        Text("Auswählen").tag(Optional<String>.none)
        ForEach(controller.workspace.evidence) {
          Text(
            "\($0.source) · Typ \($0.typeID) · \($0.quantity) Einheiten · \($0.unitPrice.map { $0.displayText + " ISK je Einheit" } ?? "Gesamtbetrag " + ($0.totalCents.flatMap { try? ISKAmount(hundredths: $0).displayText }.map { $0 + " ISK" } ?? "nicht verfügbar"))"
          ).tag(Optional($0.id))
        }
      }
      Toggle("Für diese Produktion ausdrücklich zu Belegzuordnungen wechseln", isOn: $switchMode)
      Button("Zuordnung prüfen") { allocate() }
      if let rowID, let cost = controller.workspace.costs.first(where: { $0.id == rowID }) {
        Text(cost.evidenceMode ? "Belegmodus aktiv" : "Manuelle historische Angaben aktiv")
        Text("Gesicherte manuelle Verkaufsmenge: \(cost.historicalManualSoldUnits)").font(.caption)
        let allocations = controller.workspace.sales.filter { $0.rowID == rowID }
        Text(
          "Belegt verkauft: \(allocations.reduce(Int64(0)) { $0 + $1.quantity }) / \(cost.units)")
        Text(
          "Belegter Bruttoerlös: \(NSDecimalNumber(decimal: allocations.reduce(Decimal.zero) { $0 + Decimal($1.grossCents) } / 100).stringValue) ISK"
        )
        Text("Bruttoerlös vor Verkaufsgebühren. Vorhandene Planwerte bleiben unverändert.").font(
          .caption)
      }
    }.formStyle(.grouped)
  }
  private func ensureCost() throws -> ImmutableProductionCost {
    guard let row = rows.first(where: { $0.id == rowID }),
      let plan = PlannerPersistenceController.decodePlan(row)
    else { throw ConsolidationError.invalid("Eine lesbare Produktion auswählen.") }
    try controller.registerProduction(row, plan: plan)
    guard let cost = controller.workspace.costs.first(where: { $0.id == row.id }) else {
      throw ConsolidationError.invalid("Produkttyp nicht aufgelöst.")
    }
    return cost
  }
  private func importWallet() {
    guard let sync = runtime.lastCharacterSync, let transactions = sync.walletTransactions.value,
      sync.walletTransactions.state == .fresh
    else {
      controller.error =
        "Zuerst den Charakter mit Wallet-Berechtigung synchronisieren. Es liegen keine frischen Verkaufsbelege vor."
      return
    }
    controller.propose([
      "\(transactions.filter { !$0.isBuy }.count) Verkaufsbelege aus der letzten Wallet-Synchronisierung übernehmen; bestehende Beleg-IDs werden nicht dupliziert."
    ]) { w in
      for t in transactions where !t.isBuy {
        guard t.unitPrice.isFinite, t.unitPrice > 0, t.unitPrice * 100 < Double(Int64.max) else {
          throw ConsolidationError.invalid("Ungültiger Wallet-Preis.")
        }
        let amount = try ISKAmount(hundredths: Int64((t.unitPrice * 100).rounded()))
        try w.addEvidence(
          ProductionSaleEvidence(
            id: "\(sync.authorization.characterID):transaction:\(t.transactionID)",
            typeID: t.typeID,
            quantity: t.quantity, unitPrice: amount, recordedAt: t.date,
            source: "Wallet · \(sync.authorization.characterID) · \(t.transactionID)"))
      }
    }
  }
  private func journalReceipt() {
    do {
      let cost = try ensureCost()
      guard let sync = runtime.lastCharacterSync, sync.walletJournal.state == .fresh,
        let entry = sync.walletJournal.value?.first(where: { $0.journalID == journalID }),
        entry.refType != "market_transaction",
        let amount = entry.amount, amount.isFinite, amount > 0, amount * 100 < Double(Int64.max),
        let qty = Int64(GroupedNumberText.ungrouped(quantity)), qty > 0
      else {
        throw ConsolidationError.invalid(
          "Frischen positiven Journalbeleg und Artikelmenge auswählen.")
      }
      let receipt = ProductionSaleEvidence(
        id: "\(sync.authorization.characterID):journal:\(entry.journalID)", typeID: cost.typeID,
        quantity: qty, unitPrice: nil, recordedAt: entry.date,
        source: "Bestätigter Journalverkauf · \(entry.journalID)",
        totalCents: Int64((amount * 100).rounded()))
      controller.propose([
        "Journalbuchung \(entry.journalID) (\(entry.refType)) ausdrücklich als Verkauf von \(qty) Einheiten zuordnen.",
        "Der Gesamtbetrag wird centgenau auf Teilverkäufe verteilt; kein erfundener Einzelpreis.",
      ]) { try $0.addEvidence(receipt) }
    } catch { controller.error = error.localizedDescription }
  }
  private func manualReceipt() {
    do {
      let cost = try ensureCost()
      guard let qty = Int64(GroupedNumberText.ungrouped(quantity)) else { throw ConsolidationError.invalid("Ungültige Menge.") }
      let receipt = ProductionSaleEvidence(
        id: "manual:\(UUID())", typeID: cost.typeID, quantity: qty,
        unitPrice: try ISKAmount.parse(GroupedNumberText.ungrouped(price)), recordedAt: date, source: "Manueller Beleg")
      controller.propose([
        "Manueller Beleg: \(qty) × \(receipt.unitPrice?.displayText ?? "nicht verfügbar") ISK."
      ]) { try $0.addEvidence(receipt) }
    } catch { controller.error = error.localizedDescription }
  }
  private func allocate() {
    do {
      let cost = try ensureCost()
      let oldRow = rows.first { $0.id == cost.id }
      let oldSold = oldRow?.soldUnits ?? cost.historicalManualSoldUnits
      let oldPrice = oldRow?.salePricePerUnit
      controller.propose([
        "\(quantity) Einheiten der Produktion dem ausgewählten Verkaufsbeleg zuordnen.",
        "Im Belegmodus ersetzen bestätigte Zuordnungen die manuelle Verkaufsschätzung; historische Werte bleiben gesichert.",
      ]) { w in
        guard let evidenceID, let qty = Int64(GroupedNumberText.ungrouped(quantity)) else {
          throw ConsolidationError.invalid("Beleg und Menge auswählen.")
        }
        if let i = w.costs.firstIndex(where: { $0.id == cost.id }), !w.costs[i].evidenceMode {
          w.costs[i].historicalManualSoldUnits = oldSold
          w.costs[i].historicalManualSalePrice = oldPrice
        }
        try w.allocateSale(
          rowID: cost.id, evidenceID: evidenceID, quantity: qty, switchToEvidence: switchMode)
      }
    } catch { controller.error = error.localizedDescription }
  }
}
