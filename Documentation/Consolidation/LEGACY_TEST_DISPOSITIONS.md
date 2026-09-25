# Einzelbewertung der historischen Tests

Quelle: unverändertes Archiv `EVE Nexus`, HEAD `058d4942d01782ad22a223ba6cd499d984ebe978`
einschließlich des inventarisierten damaligen Arbeitsbaums. Auswertung am 25.09.2026.

## Reproduktion und Grenze

Eine temporäre Kopie unter `/private/tmp/eve-functional/legacy-test-fixture` wurde separat gebaut.
Der unveränderte Build scheitert unter Swift 6.4 am zu komplexen SwiftUI-Ausdruck in
`Sources/NewEdenNexus/AccountsView.swift:73`. Vereinfachungen einzelner Beschriftungen verlagerten
lediglich diese Compilergrenze und wurden wieder verworfen.

Für die reine historische Testauswertung enthält nur diese temporäre Datei schließlich einen
bedingten `EVE_LEGACY_TEST_ONLY`-Ersatz der großen `body`-Darstellung durch `EmptyView`. Der vollständige
Originaltext bleibt im anderen Compilerzweig erhalten. Alle ViewModels, Fachmodelle, Dienste,
Persistenz- und Testdateien sind unverändert. Das ist ausdrücklich **kein Build-/UI-Nachweis der alten App**.
Weder der Archivbestand noch der aktive App-Quelltext enthalten diese Testhilfskonstruktion.

Ergebnis dieses begrenzten Laufs: **715 Testfälle bestanden; ein Testfall mit sieben fehlgeschlagenen
Assertions**. Keine weiteren Testfehler. Die vormals pauschal genannte Zahl „zehn Fehler“ wird durch
diesen Lauf nicht bestätigt und deshalb nicht als aktuelle Fehlerzahl fortgeschrieben.

Befehl (nur die temporäre Kopie):

```sh
CFFIXED_USER_HOME=/private/tmp/eve-functional/legacy-preferences \
swift test --disable-sandbox \
  --package-path /private/tmp/eve-functional/legacy-test-fixture \
  --scratch-path /private/tmp/eve-functional/legacy-test-build \
  -Xswiftc -DEVE_LEGACY_TEST_ONLY
```

Protokolle: `/private/tmp/eve-functional/legacy-tests.log` (unveränderter Buildversuch),
`/private/tmp/eve-functional/legacy-tests-adapted.log` (begrenzte Testauswertung).

## Sieben einzelne Befunde

Alle sieben stammen aus
`NewEdenNexusArchitectureTests/AppSourceArchitectureTests.testP51WalletViewShowsPlanAndActualSideBySide`,
Zeile 427. Der Test sucht Zeichenketten im alten `WalletFinanceView.swift`; er prüft keine Berechnung.

| Fehlende alte Erwartung | Entscheidung und heutiger Nachweis |
| --- | --- |
| `Plan und Ist des ausgewählten Projekts` | Die entfernte Projektfinanzansicht bleibt laut Benutzerentscheidung entfernt. Bestehender Planner und Produktionsbuch bilden die aktiven Oberflächen. |
| `Bestätigtes Ist` | Kein Wiederaufbau der Ansicht. Bestätigte Verkaufszuordnungen, Teilmengen und Belegmodus sind im aktuellen Produktionsbuch erreichbar und in ConsolidationTests geprüft. |
| `economicTotalCost` | Alte UI-/Modellkopplung wird nicht übernommen. Aktuelle Kostenprojektion und unveränderliche Quell-/Kostenstände bleiben maßgeblich; bestehende Kosten- und neue Migrationstests bestehen. |
| `expectedRevenue` | Die vorhandenen aktuellen Verkaufsszenarien bleiben maßgeblich. Kein zweiter Erwartungswert-Rechner und keine alte Finanzansicht. Vorhandene Planer-/Markttests bestehen. |
| `expectedProfit` | Die aktuelle Gewinnrechnung bleibt erhalten. Historische abweichende Finanzformeln werden nicht eingeführt; keine zusätzlichen Finanzdiagramme. |
| `outdatedSource` | Der alte View-Bezeichner entfällt. Fachliche Aktualitätsregeln bleiben: Revisionen, SDE-/Bestandsprüfung und aktuelle Vorschau vor Bestätigung; entsprechende aktive Tests bestehen. |
| `überschreiben keine Planwerte` | Der Grundsatz ist übernommen, der alte Bildschirm nicht: Originale Snapshot-Bytes, historische Kosten und manuelle Verkaufswerte bleiben erhalten; V2→V3- und Wiederherstellungstests prüfen dies. |

Der ebenfalls gesuchte Text `Archivierte Projekte sind` ist im Legacy-Quelltext vorhanden und verursacht
keinen Fehler. Die sieben Assertions werden somit nicht als sieben unabhängige fachliche Defekte gezählt.
Der alte Test wird weder abgeschwächt noch gelöscht; er bleibt im Archiv dokumentiert.

Die ausgeführte aktive Suite ist vollständig erfolgreich. Die portierten Parserfälle und die an die
aktive Architektur angepassten Lebenszyklus-, Betrags-, Import-, Reservierungs-, Beleg- und Migrationsfälle
stehen in den drei Konsolidierungstestsuiten. Nachweis: [FUNCTIONAL_VALIDATION.md](FUNCTIONAL_VALIDATION.md).
