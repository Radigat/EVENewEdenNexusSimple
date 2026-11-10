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
        Text(area.rawValue).appFont(.title2.bold())
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
    // The sale tables need the width of their eight columns.
    .padding(20).frame(
      minWidth: area == .sales ? 1120 : 660, idealWidth: area == .sales ? 1240 : 920,
      minHeight: 560, idealHeight: 760)
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
