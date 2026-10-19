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
- Tests verwenden ausschließlich synthetische Bestände. Reale SDE-Abnahme und
  vollständige Eigentümerabnahme werden nicht behauptet. SSO und ESI hat der
  Eigentümer am 19.10.2026 mit dem signierten Debug-Build live geprüft.
- VoiceOver wird nicht unterstützt und ist kein Abnahmeschritt (Entscheidung des
  Eigentümers vom 19.10.2026); vorhandene Beschriftungen bleiben im Code.
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
gegen neue Funktionen ist aufgehoben. Die Codex-Änderungen vom 02.–17.10.2026
und die Übergabe-Dokumente sind lokal als `90b4cc4` committet (dev-diary-Nachtrag
`81d258b`). Auf HEAD `81d258b` wurden sie am 19.10.2026 erneut isoliert
automatisch verifiziert: SwiftPM 485 Fälle (427 Core-, 39 App-Swift-Testing-,
19 XCTest-Fälle; ein Real-SDE-Skip), separates Kit 8 Fälle (ein Skip), nativer
unsignierter Debug-Build `BUILD SUCCEEDED` und Tests `TEST SUCCEEDED` (434
bestanden, ein Skip), `git diff --check` fehlerfrei. Logs:
`/private/tmp/eve-nexus-claude-handover-20261019/`. Kein Push; Live-ESI-/SSO-,
visuelle und Eigentümerabnahme bleiben offen.

## Eigentümerprüfung und Blueprint-Standorte (19.10.2026)

Mit dem signierten Debug-Build (Stand `8961e00`) hat der Eigentümer live geprüft:
SSO und ESI funktionieren; Dashboard, Märkte, Kosten und Blueprint-Kopien sind
visuell in Ordnung. Gefunden: BPO-/BPC-Standorte erschienen in der
Blueprint-Übersicht immer als „Unbekannter Ort“. Korrigiert: die
Übersicht löst Behälter wie Assets und Produktionsplanung über den Asset-Bestand
zum Wurzelstandort auf. Automatisch verifiziert: SwiftPM 428 Core-, 39 App-,
19 XCTest-Fälle (ein Skip), Kit 8 (ein Skip), nativ `TEST SUCCEEDED` mit 435
bestanden (ein Skip); Logs `/private/tmp/eve-nexus-claude-bplocations-20261019/`.
Der Eigentümer hat die Korrektur am 19.10.2026 mit dem signierten Build
`~/Developer/EVE New Eden Nexus Builds/2026-10-19-debug-8961e00-bplocations/`
live geprüft: Die Standorte werden korrekt angezeigt.

## Git-Stand (19.10.2026)

`main` und `origin/main` stehen auf `ce5eb0b` (Fast-Forward-Push auf Auftrag des
Eigentümers); Sicherungs-Tag `stand-2026-10-19` liegt auch auf GitHub. Der
Konsolidierungsbranch ist in `main` aufgegangen und lokal gelöscht; gearbeitet
wird auf `main`.
