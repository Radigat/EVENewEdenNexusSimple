# EVE New Eden Nexus - Assets, Industry, Markets – Projektstatus

Stand: 22.10.2026. Modellvorgaben je Werkzeug: [MODEL_POLICY.md](MODEL_POLICY.md).
Es gibt nur einen aktiven Projektstand: `/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`.
Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Fachlicher Stand

Die organisatorische Basis `182f1a9` ist um die freigegebenen vorhandenen Fachabläufe ergänzt:
manuelle Lager/CSV, Preisprofile,
konkrete Wissenschaftsaufträge, Kosten-/Verkaufsbelege und lokale Sicherung/Wiederherstellung.
Die heutige Oberfläche und aktuelle Berechnungen bleiben Grundlage. V3 ergänzt die Datenhaltung;
bestehende Modelle, Nummern, historische Werte und technische Kennungen werden erhalten.
Fertigungsprojekte, Reservierungen sowie Einkaufsbudget und -fortschritt sind seit 19.10.2026 auf
Eigentümerentscheid entfernt; der Planner rechnet direkt aus Eingabe, ESI-Bestand und Handeingabe.
Manuelle Preisprofile sind seit 22.10.2026 entfernt (keine Berechnung las sie);
Sicherung/Wiederherstellung ist in die allgemeinen Einstellungen integriert. Die früheren gemeinsamen
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

## Hub-Chancen-Ausbau (20./21.10.2026)

Auf Auftrag des Eigentümers ist das Ablaufdiagramm „Programmstart → ESI laden →
Hub-Chancen → Produktionsplanung“ in den Schritten P0–P13 umgesetzt. Plan,
Checkliste, Prompts und Owner-Testleitfaden:
[HUB_CHANCEN_PLAN.md](Documentation/HUB_CHANCEN_PLAN.md).

- **Implementiert:**
  - zentraler, vollautomatischer Startablauf mit Ladestatus auf dem Dashboard;
  - Home- und Coalition-Hub-Chancen mit eigenen Scans, Bedarfsledgern und
    Ansichten sowie Transport Home → Coalition;
  - Vertragspreise in allen Chancenansichten;
  - Dashboard-Karte „Top-Chancen“;
  - Zielmarkt im Planner und Allianzmarkt als manuelles zehntes Szenario;
  - Kaufort-Hinweis für Mineralien und Mondmaterialien mit Multibuy je
    Kaufort.

  Bestehende Rechenregeln und die neun Marktszenarien sind unverändert. Es gibt
  keine SwiftData-Schemaänderung. Regeländerung: Die Opt-ins für Main-Hub-Scan
  und Vertragsfortsetzung entfallen
  ([Entscheidung](Documentation/Consolidation/DECISIONS.md)).
- **Automatisch geprüft (21.10.2026):**
  - `swift test`: 461 Swift-Testing-Tests in 29 Suites plus 59 Tests in 3
    Suites;
  - `xcodebuild test` unsigniert: `TEST SUCCEEDED`;
  - `EVEStaticDataKit`: 8 Tests, ein vorgesehener Real-SDE-Skip;
  - `git diff --check` fehlerfrei.

  Nachweise: [ACCEPTANCE.md](Documentation/ACCEPTANCE.md).
- **Offen:**
  - Live-Prüfung mit echten Charakteren, Structure-Märkten, DOTLAN und
    vollständigem Vertragsindex;
  - visuelle und fachliche Eigentümerabnahme.

  Der Stand ist auf Auftrag des Eigentümers als `9000f3f` auf `main`
  committet und nach `origin/main` gepusht (Fast-Forward, kein Tag).

## Bereich Handel (22.10.2026)

Auf Auftrag des Eigentümers ist nach seinem Referenzbild ein Handelsbereich in
den Schritten P0–P8 umgesetzt. Plan, Entscheidungen, Formeln, Prompts und
Abnahme-Checkliste: [HANDEL_PLAN.md](Documentation/HANDEL_PLAN.md).

- **Implementiert:**
  - SDE-Marktgruppen (Datensatz `marketGroups`, Katalogadapter 5) als Kacheln.
  - Handelsrechner mit 4-Stellen-Preisschritt, Steuern, Broker und Transport
    (Kurier, Jump Freighter).
  - Volles Orderbuch für Home-/Coalition-Strukturscans samt Ordertiefe;
    Bedarfsledger und Hub-Chancen-Ergebnisse unverändert.
  - Bereich **Handel** mit vier Routen (Main → Home, Main → Coalition, Home →
    Coalition, Coalition → Home; Station Trading am 22.10.2026 entfernt),
    Tagesbedarf, Pfeilschwellen und „Ins Logbuch“.
  - **Handelslogbuch** in eigener SQLite-Datei
    `dataRoot/trade/trade-logbook.sqlite`, Schema 3. Es enthält Einkäufe,
    Verkäufe, Erinnerung, die Wallet-Daten aller Charaktere und den
    automatischen Abgleich (FIFO, belegte Steuer, berechneter Broker,
    erkannte Orderart).

  Bestehende Rechenregeln sind unverändert. SwiftData-Schema und
  Migrationskette sind unberührt. Bewusste Regeländerungen und Annahmen stehen
  in den [Entscheidungen](Documentation/Consolidation/DECISIONS.md).
- **Automatisch geprüft (22.10.2026):**
  - `swift test`: 521 Swift-Testing-Tests in 35 Suites plus 66 Tests in 3
    Suites;
  - `xcodebuild build` und `test` unsigniert: `BUILD SUCCEEDED`,
    `TEST SUCCEEDED` (521 Swift-Testing-Tests, 8 XCTest-Fälle);
  - `EVEStaticDataKit`: 11 Tests;
  - `git diff --check` fehlerfrei.

  Nachweise: [ACCEPTANCE.md](Documentation/ACCEPTANCE.md).
- **Visuell geprüft:** in einer isolierten Debug-App mit synthetischem Katalog
  und ohne Marktpreise, ohne Nutzerdaten.
- **Offen:**
  - SDE-Neuimport mit dem echten Archiv;
  - Live-Prüfung mit echten Hub-Märkten, Strukturen, DOTLAN, Wallets und
    Orders;
  - Eigentümerabnahme.

  Der Stand ist auf Auftrag des Eigentümers als `9d8f224` auf `main`
  committet und nach `origin` gepusht.

### Nachtrag 23.10.2026: Top-20-Kachel

Auftrag und Eigentümerentscheidungen: [HANDEL_PLAN.md, Abschnitt J](Documentation/HANDEL_PLAN.md).

- **Implementiert:**
  - Spalte Gewinn/m³ in allen Kacheln.
  - Erste Kachel „Top 20“ je gewählter Marktgruppe, Rangfolge nach Diff % oder
    Gewinn/m³, nur positive Werte, eigene Sortierung.
  - Rechenregeln unverändert.
- **Automatisch geprüft:**
  - `swift test`: 548 Tests in 35 Suites plus 70 Tests in 3 Suites;
  - `EVEStaticDataKit`: 11 Tests;
  - `xcodebuild test`: `TEST SUCCEEDED`, 548 Tests;
  - `git diff --check` fehlerfrei.

  Nachweise: [dev-diary.md](dev-diary.md).
- **Visuell geprüft:** isolierte Debug-App mit dem SDE-Katalog, ohne
  Marktpreise und ohne Nutzerdaten:
  - Kachel, Umschalter und Leerzustände;
  - Sortierung nach Gewinn/m³.
- **Offen:**
  - Prüfung mit echten Hub-Marktdaten, also Rangfolge, Werte und die Sortierung
    der Top-Kachel bei vorhandenen Zeilen;
  - Eigentümerabnahme.

  Der Stand ist auf Auftrag des Eigentümers als `9b4462f` auf `main`
  committet und nach `origin` gepusht.

## Statische Daten lokal (23.10.2026)

Eigentümerfrage nach vorab gespeicherten statischen EVE-Daten. Das SDE lag
bereits als SQLite-Katalog vor; geschlossen wurden die verbleibenden Lücken.
Details: [dev-diary.md](dev-diary.md), Entscheidung zur Volumenquelle:
[DECISIONS.md](Documentation/Consolidation/DECISIONS.md).

- **Implementiert:**
  - Verpacktes Volumen kommt zuerst aus dem SDE, ESI nur für Lücken; beim
    Main-Hub-Scan fallen damit 4.765 Einzelabrufe weg.
  - Vollständige Blueprint-Definitionen werden mit drei Abfragen geladen und
    für die Laufzeit gehalten.
  - Katalogadapter 6 bringt Facility-Dogma in der Tabelle `type_dogma` und
    zwei Blueprint-Indizes.
- **Automatisch geprüft (23.10.2026):**
  - `swift test` 548 + 70, `EVEStaticDataKit` 12, `xcodebuild test`
    `TEST SUCCEEDED`;
  - Opt-in gegen das reale SDE-Paket des Builds 3632936 bestanden.
  - Isoliert nur der committete Stand (`02b61a2`, ohne uncommittete
    Änderungen paralleler Sitzungen): `swift test` 535 + 66,
    `EVEStaticDataKit` 12, `xcodebuild test` `TEST SUCCEEDED`.
- **Erledigt (23.10.2026):**
  - Commit `3100021`;
  - „SDE → Neuimport des aktuellen Katalogs“ um 09:12–09:13 Uhr: aktiv ist
    `catalog-v6` mit 491 Dogma-Typen und beiden Indizes;
  - Neustart der Debug-App um 10:17 Uhr.
- **Offen:**
  - Messung in der laufenden App (Startzeit, Main-Hub-Scan, ESI-Last);
  - Eigentümerabnahme.

## Messprotokoll und CCP-Regelprüfung (23.10.2026)

Zeiten, Zähler und passive Prüfung der CCP-Vorgaben für ESI im
Systemprotokoll. Details und Benchmarkwerte: [dev-diary.md](dev-diary.md),
Lesart: [PRODUCT.md](PRODUCT.md), Abschnitt „Laufzeit und Hintergrundarbeit“.

- **Implementiert:**
  - `PerformanceLog` mit Startmeilensteinen, Profil-Referenzdaten,
    SDE-Ladezeiten und allen Main-Hub-Scan-Phasen;
  - `MeasuringESITransport`: ESI-Last je Routenfamilie und Zähler für
    fehlende Header, frühe Abrufe vor `Expires`, 420/429 und Mindestbudgets.
- **Automatisch geprüft (23.10.2026):**
  - `swift test` 555 + 70, `EVEStaticDataKit` 12, `xcodebuild test`
    `TEST SUCCEEDED` (555);
  - Offline-Benchmark auf SDE 3632936:
    - Dogma 529 → 58 ms;
    - Fertigungsdefinitionen 655 → 53 ms;
    - ESI-Volumenabrufe je Scan 4.765 → 0.
- **Offen, in dieser Reihenfolge:**
  1. ESI-Cache, der Neustarts übersteht, damit kein Abruf vor `Expires`
     erfolgt. Erst nach dem Commit der ESI-Sitzung.
  2. Live-Lauf mit Auswertung und Abnahmeliste; danach die Eigentümerabnahme.
