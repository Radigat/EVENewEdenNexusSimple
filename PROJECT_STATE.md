# EVE New Eden Nexus - Assets, Industry, Markets – Projektstatus

Stand: 29.09.2026. Modellvorgaben je Werkzeug: [MODEL_POLICY.md](MODEL_POLICY.md).
Es gibt nur einen aktiven Projektstand: `/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`.
Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Fachlicher Stand

Die organisatorische Basis `182f1a9` ist um die freigegebenen vorhandenen Fachabläufe ergänzt:
Fertigungsprojekte, manuelle Lager/CSV, dauerhafte Reservierungen, Preisprofile/Einkauf,
konkrete Wissenschaftsaufträge, Kosten-/Verkaufsbelege und lokale Sicherung/Wiederherstellung.
Die heutige Oberfläche und aktuelle Berechnungen bleiben Grundlage. V3 ergänzt die Datenhaltung;
bestehende Modelle, Nummern, historische Werte und technische Kennungen werden erhalten.
Projektwahl und -einstellungen, Reservierungen sowie Einkaufsbudget und -fortschritt sind in die
passenden Planner-Abschnitte integriert. Preisprofile sind in die Markteinstellungen,
Sicherung/Wiederherstellung in die allgemeinen Einstellungen integriert. Die früheren gemeinsamen
Toolbar-Einstiege und der bereichsumschaltende Projektverwaltungsdialog sind entfernt.

Maßgeblich: [Funktionsvertrag](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md),
[Feature-Zuordnung](Documentation/Consolidation/FEATURE_COVERAGE.md) und
[aktuelle Verifikation](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md).

## Grenzen

- Keine Migration alter Nexus-Datenbanken; vorhandene aktuelle Nutzerdaten werden additiv migriert.
- Zurückgezogene Finanzansichten und nur geplante Vorhaben bleiben ausgeschlossen.
- Tests verwenden ausschließlich synthetische Bestände. Reale SDE-/ESI-/SSO-Abnahme und
  vollständige Eigentümer-/VoiceOver-Abnahme werden nicht behauptet.
- Die bereits installierte Alt-App und die ChatGPT-Projektanzeige sind separate Oberflächen.
  Dieser Auftrag ersetzt keine produktive Installation und ändert keine globalen Modelleinstellungen.
- Der historisch genannte Production-Tracker-Ordner liegt weiterhin nicht als eigener Quellstand vor.

Die Konsolidierungsphase ist abgeschlossen. Seit 19.10.2026 ist die Weiterentwicklung
auf ausdrücklichen Benutzerauftrag freigegeben (siehe unten).

## Fehlerkorrekturen vom 02.10.2026

Auf ausdrücklichen Nutzerauftrag sind die unterbrochene Legacy-Übernahme,
doppelt angesetzte Zwischenproduktkosten und die Bewertung von Blueprint-Kopien
korrigiert. Eine zusätzlich freigegebene vollständige Wiederherstellung des
alten SwiftData-Bestands sichert beide Datenstände, prüft bekannte V1/V2/V3-Modelle
und ihre Inhalte und aktiviert erst nach bewusster Bestätigung; neuere Daten
bleiben in der Sicherung und werden nicht zusammengeführt. Fremde Nexus-Modelle
werden dadurch nicht migriert. Technische Kennungen und V3-Migrationskette bleiben
erhalten.

Der lokale Stand besteht 477 SwiftPM-Tests (ein vorgesehener Real-SDE-Skip),
das separate Kit mit 8 Fällen (ein Skip) und den nativen Debug-/Testlauf mit
431 Fällen (ein Skip). Der isolierte native Start und Prüfprozess sind erfolgreich.
Quelle und verbleibende Abnahmegrenzen:
[Vertrag und Prüfnachweis](Documentation/REVIEW_FIXES_2026-10-02.md).
Keine produktive Installation, Live-ESI- oder vollständige Eigentümerabnahme
ist damit verbunden. Die vom Nutzer ausdrücklich gewählten Modelle dieser
Aufgabe sind GPT-6.1 Sol High für die regulären Arbeiten und GPT-Astra High
für komplexe Wiederherstellungslogik und ihre unabhängige Sicherheitsprüfung;
globale Modellvorgaben werden dadurch nicht geändert.

## Übergabe an Claude und neuer Projektordner (19.10.2026)

Der Projektordner wurde aus dem iCloud-synchronisierten `~/Documents` nach
`/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`
verschoben, weil iCloud Quell- und `.git`-Dateien ausgelagert hatte. Die
Entwicklung wird mit Claude fortgesetzt (Einstieg `CLAUDE.md`, bindet
`AGENTS.md` ein); Codex bleibt mit seiner Konfiguration nutzbar. Die Sperre
gegen neue Funktionen ist aufgehoben. Der Arbeitsbaum enthält weiterhin die
uncommitteten Codex-Änderungen vom 02.–17.10.2026 (29 geänderte, 4 neue
Dateien); sie sind unverändert erhalten. Am 19.10.2026 wurden sie im neuen
Ordner erneut automatisch verifiziert: SwiftPM 485 Fälle (427 Core-, 39 App-
Swift-Testing-, 19 XCTest-Fälle; ein Real-SDE-Skip), separates Kit 8 Fälle (ein
Skip), nativer unsignierter Debug-Build und Tests `TEST SUCCEEDED` (434 bestanden,
ein Skip). Noch nicht committet; Live-ESI-/SSO- und Eigentümerabnahme bleiben offen.
