# EVE New Eden Nexus - Assets, Industry, Markets – Projektstatus

Stand: 08.11.2026. Modellvorgaben je Werkzeug: [MODEL_POLICY.md](MODEL_POLICY.md).
Es gibt nur einen aktiven Projektstand: `/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`.
Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Fachlicher Stand

Die organisatorische Basis `182f1a9` ist um die freigegebenen vorhandenen Fachabläufe ergänzt:
Preisprofile (seit 22.10.2026 entfernt), manuelle Lager/CSV (seit 30.10.2026 entfernt),
konkrete Wissenschaftsaufträge, Kosten-/Verkaufsbelege und lokale Sicherung/Wiederherstellung.
Die heutige Oberfläche und aktuelle Berechnungen bleiben Grundlage. V3 ergänzt die Datenhaltung;
bestehende Modelle, Nummern, historische Werte und technische Kennungen werden erhalten.
Fertigungsprojekte, Reservierungen sowie Einkaufsbudget und -fortschritt sind seit 19.10.2026 auf
Eigentümerentscheid entfernt; der Planner rechnet direkt aus Eingabe, ESI-Bestand und Handeingabe.
Manuelle Preisprofile sind seit 22.10.2026 entfernt (keine Berechnung las sie);
Sicherung/Wiederherstellung ist in die allgemeinen Einstellungen integriert. Die früheren gemeinsamen
Toolbar-Einstiege und der bereichsumschaltende Projektverwaltungsdialog sind entfernt.
Der seit 26.09.2026 nicht mehr eingebundene Market Browser ist seit 07.11.2026 entfernt.

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

## Offene Punkte (Stand 08.11.2026)

Sammelstelle für alles, was nicht erledigt ist. Einzelheiten stehen in den
verlinkten Plänen und im [dev-diary.md](dev-diary.md); offene Abnahmen je
Vorhaben in [ROADMAP.md](ROADMAP.md), „Umgesetzt, Abnahme offen“.

- **CI rot seit 03.11.2026; dritte Korrektur gepusht, CI-Nachweis offen:** Job
  „Swift package tests“ (`macos-15`, Swift 6.1.2).
  - Übersetzung, behoben mit `abc1b10`: Ab `c36c27e` (A1–A3) meldete der
    Compiler in `PlaceholderViews.swift` beim Erzeugen von
    `PlannerCalculationPipeline` (`resolveBasis`, `calculate`) „converting
    non-sendable function value … may introduce data races“. Die
    Pipeline erhält jetzt Closure-Literale statt der lokalen Funktionen. Im
    CI-Lauf `42528721333` übersetzt Swift 6.1 den Stand, alle 933
    Swift-Testing-Tests sind grün.
  - Leerzustände, behoben mit `178920d`: `AppUnavailableView` setzte auch bei
    „Standard“ feste Schriften (Titel `title3` fett, Beschreibung `title3`),
    die nur unter macOS 27.2 dem Systemleerzustand gleichen; unter macOS 15
    scheiterte `testUnavailableViewMatchesTheSystemViewAtStandardSize`. Nach
    Wahl des Eigentümers bleiben bei „Standard“ jetzt die Systemschriften
    unberührt (`appFontKeepingSystemDefault`); die übrigen Stufen skalieren
    `title3` wie bisher. Im CI-Lauf `42529888263` ist dieser Pixelvergleich
    unter macOS 15 grün.
  - Rot seit `178920d`: `testUnavailableViewGrowsWithTheTextSize`. Unter
    macOS 15 sind zwei der fünf Stufen gleich hoch (vier verschiedene Höhen
    statt fünf); die Reihenfolge stimmt. Welche zwei Stufen, zeigt das Log
    nicht. Ursache ist die gewählte Lösung: „Standard“ nutzt unter macOS 15
    andere Schriften als die skalierten Stufen. Unter macOS 27.2 grün.
    Am 08.11.2026 nach Wahl des Eigentümers den Test angepasst, committet und
    nach `origin/main` gepusht:
    Die vier skalierten Stufen müssen weiter jeweils höher werden, „Standard“
    muss nur zwischen „Kompakt“ und „Groß“ liegen und darf so hoch sein wie
    eine der beiden. Lokal grün; ob der Test unter macOS 15 hält, zeigt der
    CI-Lauf zu diesem Push.
- **Eigentümerentscheidungen:**
  - P-L5: Zykluserkennung in der Automatik mit Wahl des günstigsten Zustands
    ([Analyse](Documentation/ANALYSE_2026-11-02.md), Abschnitt 6);
  - H-L1: JF-Treibstoff im Handel aus einem frischen Snapshot statt aus dem
    Hub-Scan;
  - Planner-Kosten auf Abruf in der Hub-Chancen-Ansicht: braucht eine
    Herauslösung der Planner-Endrechnung aus dem Planner-Fenster (dev-diary
    24.10.2026).
- **Vorbereitete Prompts:** A6b, A7, A8; zurückgestellt A5 und G9
  ([ROADMAP.md](ROADMAP.md), „Geplant“).
- **Messungen und ungeklärte Ursachen:**
  - G10 (Home und Coalition gleichzeitig) bei normaler ESI-Lage messen; bei
    erneutem Scheitern zurück zur Reihenfolge;
  - Startdauer mit abgelaufenem Cache (79 s), Ursache nicht belegt;
  - rund 50 Fehlerantworten beim automatischen LP-Store-Abruf je Start,
    Ursache nicht belegt;
  - Messlücke: ESI-Zusammenfassung beim Startende fehlt;
  - Marktbestand: Dateigröße nach 7 Tagen Live-Betrieb, echte Schreibdauer;
  - Hub-Chancen: Größe des gespeicherten Scans und Scandauer mit der
    Rekursion der Zwischenprodukte.
- **Befunde ohne Auftrag:**
  - SEC-OPEN-07: Jitter beim Backoff fehlt;
  - Regionsnamen in den Öffentlichen Verträgen (Picker, Metadatenzeile der
    Ergebniskarten) sind nicht per Klick kopierbar (Regel „Copyable EVE
    names“ in `AGENTS.md`);
  - englische Beschriftungen in der deutschen Oberfläche: „Update“
    (Main-Hub-Chancen) und „Refresh“ (Kaufanalysen);
    `IndustryPlannerError.invalidInput` fügt englische Texte ein, die App
    erreicht diesen Fehler aber nicht;
  - Schriftgröße: Fenstertitel, Menüs, Tooltips, Spaltenköpfe nativer
    Tabellen und die Bauplansuche (`ContentUnavailableView.search`) skalieren
    nicht;
  - Etappenwahl: Selbstspringen zum oder vom Main Hub (Planer, Hub-Chancen,
    Reaktionen) und selbstspringende Capitals bei Kurier oder JF-Service auf
    Home → Coalition fehlen;
  - Kachel „Kosten pro Item“: Gebühren für Preisänderungen und
    Weitertransport sind nicht enthalten;
  - Farbschema griff in einer von drei HUD-Aufnahmen beim Start verzögert
    (`AppAppearanceApplier`), nicht untersucht;
  - der Hinweis im Vertragsspeicher nennt den „Erstimport“ auch bei späteren
    Aktualisierungen;
  - Seitenkopf der Baupläne ohne Daten steht mittig (Altbestand);
  - die nicht mehr gelesene Datei `market/hub-top-opportunities.json` bleibt
    im Datenordner liegen;
  - die isolierte Debug-App teilt Fenster- und Seitenleisten-Autosave mit der
    echten App (gleiche Bundle-ID);
  - ein einmaliger Abbruch von `EVENexusCoreTests` (DB5) ist nicht
    untersucht.
- **Sicherheitsaudit:** In
  [SECURITY_AUDIT_2026-07-30.md](Documentation/SECURITY_AUDIT_2026-07-30.md)
  stehen SEC-OPEN-01 bis -12 weiter als offen; nur -07 hat einen
  Statusvermerk. Die Liste ist nicht gepflegt: -04 ist überholt, im
  Projektstamm liegt nur noch `EVENexusSimple.xcodeproj`. Ein Abgleich der
  übrigen Punkte steht aus.

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

## Git-Stand (08.11.2026)

- `main` und `origin/main` stehen nach dem Push vom 08.11.2026 auf dem
  Commit mit der CI-Korrektur (Planer-Pipeline für Swift 6.1) und diesem
  Nachtrag von ROADMAP und PROJECT_STATE. Mit ihm gingen `f63dc83`
  (Erstimport-Hinweis der Öffentlichen Verträge), `69f285f` (Planer ohne
  Umschalter Einzel-/Sammelproduktion) und der Sammel-Commit `0b7fb5c` (A6,
  HUD D1–D8, Dashboard DB1–DB7, Market Browser entfernt, Item-Verlauf,
  Schriftgröße, Eingabefehler im Planer, Vertragssuche nach Preis und Region)
  nach `origin/main`; vorher lag `origin/main` auf `85749de` (A5b,
  05.11.2026).
- Beim Schreiben dieses Stands uncommittet (parallele Sitzung): die
  Doku-Nachträge zu DB7, die Änderungen aus DB8 und der Abnahmevermerk des
  Dashboards.
- Letzter Sicherungs-Tag ist `stand-2026-10-19` (auch auf GitHub). Der
  Konsolidierungsbranch ist am 19.10.2026 in `main` aufgegangen; gearbeitet
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
  - Dashboard-Karte „Top-Chancen“ (am 26.10.2026 auf Eigentümerauftrag
    wieder entfernt);
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
  - Erste Kachel „Top 20“ je gewählter Marktgruppe, Rangfolge nach Gewinn/m³
    oder ROI (Diff % als Rangfolge entfernt, Abschnitt K), nur Items mit
    positivem Gewinn und positivem Wert, eigene Sortierung.
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

### Nachtrag 24.10.2026: Handelsvolumen aus der ESI-Markthistorie

Auftrag und Eigentümerentscheidungen: [HANDEL_PLAN.md, Abschnitt L](Documentation/HANDEL_PLAN.md).

- **Implementiert:** gehandeltes Gesamtvolumen je Item in der Region des
  Zielhubs für 1/2/5/7/30 Tage (Spalte „Gehandelt N T“, Tooltip mit allen
  Zeiträumen), Ø gehandelt/Tag (Details) und Gewinn/Tag als Obergrenze.
  Alle drei sind sortierbar. Abruf je Item über
  `/markets/{region_id}/history/` mit höchstens vier parallelen Anfragen; der
  ESI-Antwortcache gilt bis `Expires`. Keine Trennung nach Kauf- und
  Verkaufsseite. Top-20-Rangfolge, Bedarfsspalten und Rechenregeln sind
  unverändert. Kein neues Schema, keine Migration.
- **Automatisch geprüft (24.10.2026):** `swift test` (586 Tests in 40 Suites
  plus 70 in 3 Suites), `xcodebuild … test` unsigniert (`TEST SUCCEEDED`),
  `EVEStaticDataKit` (12 Tests), `git diff --check`.
- **Nicht geprüft:** GUI-Sichtprüfung (die isolierte Debug-Instanz öffnete aus
  der Agentenumgebung kein Fenster), Live-Abruf gegen ESI und damit die
  Ankerregel mit echtem `Last-Modified`.
- **Offen:** Live-Abnahme (opt-in) und Eigentümerabnahme. Committet als
  `8a366e7`, nicht gepusht.
- **Region aller Handelsorte (24.10.2026):** Spielerstrukturen speichern bei
  der Auswahl jetzt die Region (über das Sonnensystem). Bereits gespeicherte
  Orte ohne Region werden beim Start nachgetragen und zurückgeschrieben.
  Automatisch geprüft (587 + 70 Tests, Xcode `TEST SUCCEEDED`), in der App
  noch nicht bestätigt. Committet als `20beb2f`, nicht gepusht.
- **Volumen am Zielhub (24.10.2026, [Abschnitt M](Documentation/HANDEL_PLAN.md)):**
  neue Spalte „Zielhub N T“ aus dem Bedarfsledger des Zielhubs (Summe der
  erfassten Tage, Abdeckung sichtbar); Regionswerte heißen „Region N T“,
  „Gewinn/Tag (Region)“, „Ø Region/Tag“. Automatisch geprüft (591 + 70
  Tests, Xcode `TEST SUCCEEDED`), in der App noch nicht bestätigt. Auf
  Auftrag lokal auf `main` committet, nicht gepusht.
- **Einziger Markt der Region (24.10.2026, [Abschnitt N](Documentation/HANDEL_PLAN.md)):**
  Schalter je Handelsort in den Markteinstellungen; am Zielhub gesetzt, zeigt
  „Zielhub N T (Region)“ die Regionshistorie. Automatisch geprüft (593 + 70
  Tests, Xcode `TEST SUCCEEDED`), in der App noch nicht bestätigt. Auf
  Auftrag lokal auf `main` committet, nicht gepusht.

## Laufzeitoptimierung (23.10.2026)

Auf Auftrag des Eigentümers sind Berechnungs- und Abrufabläufe auf
Geschwindigkeit geprüft. Details und Befunde: [dev-diary.md](dev-diary.md).

- **Implementiert:** `RuntimeState` mit Swift Observation (Ansichten zeichnen
  nur bei gelesenen Werten neu), LP-Store-Typmenge einmal je Katalog,
  gecachte Markt-Kontextkennung und Vermögensverlauf, einmalige
  Zeilenprojektion vor dem Sortieren der Hub-Chancen, begrenzt parallele
  ESI-Seiten und private Vertragsitems in fester Reihenfolge, kein
  unnötiges Dekodieren alter Snapshots nach dem Charakterabgleich.
  Rechenregeln, Schema und Migrationskette unverändert.
- **Automatisch geprüft (23.10.2026):** `swift test` 525 + 70 Tests,
  `EVEStaticDataKit` 11 Tests, `xcodebuild test` `TEST SUCCEEDED` (525),
  `git diff --check` fehlerfrei.
- **Offen:** Messung in der laufenden App mit echten Daten, Live-ESI-Laufzeit,
  Eigentümerabnahme.

## ESI-Regelprüfung (23.10.2026)

Abgleich mit CCPs aktueller ESI-Dokumentation und OpenAPI-Spezifikation;
Befund, Quellen und Nachweise im [dev-diary.md](dev-diary.md).

- **Implementiert:** globale Durchsetzung von Fehlerlimit, 420/429 und
  Token-Budgets in der ESI-Warteschlange; gleicher `Last-Modified`-Stand über
  alle Seiten mit einmaligem Neulesen; Warten auf eine unmittelbar
  bevorstehende Aktualisierung; gezielte Cache-Freigabe nach Hub-Scans.
- **Automatisch geprüft (23.10.2026):** `swift test` 535 + 70,
  `EVEStaticDataKit` 11, `xcodebuild test` `TEST SUCCEEDED`.
- **Offen:** Live-ESI-Prüfung, Jitter beim Backoff (SEC-OPEN-07),
  Eigentümerabnahme.

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
  - Neustart der Debug-App um 10:17 Uhr;
  - Messung in der laufenden App (siehe „Dauerhafter ESI-Antwortcache“).
- **Vom Eigentümer abgenommen (23.10.2026).**

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
- **Live geprüft und vom Eigentümer abgenommen (23.10.2026):** siehe
  „Dauerhafter ESI-Antwortcache“.

## Dauerhafter ESI-Antwortcache (23.10.2026)

ESI-Antworten überstehen App-Neustarts, damit nichts vor `Expires` erneut
abgerufen wird. Entscheidungen: [DECISIONS.md](Documentation/Consolidation/DECISIONS.md),
Verhalten: [PRODUCT.md](PRODUCT.md), Nachweise: [dev-diary.md](dev-diary.md).

- **Implementiert:**
  - `ESIResponseDiskCache` als zweite Stufe hinter dem Speicher-Cache;
  - öffentliche und private Antworten, ohne Massenabrufe;
  - 512 MB, nicht in der Datensicherung.
- **Automatisch geprüft (23.10.2026):** `swift test` 564 + 70,
  `EVEStaticDataKit` 12, `xcodebuild test` `TEST SUCCEEDED` (564).
- **Live geprüft (23.10.2026, echte Daten):**
  - Start 26,9 s mit leerem, 18,2 s mit gefülltem Cache (780 Antworten von
    der Platte);
  - Main-Hub-Scan 24,5 s, Volumen ohne ESI-Abruf;
  - keine 420/429, Header vollständig.
  - Details im [dev-diary.md](dev-diary.md).
- **Vom Eigentümer abgenommen (23.10.2026)** anhand der Abnahmeliste
  (Industrieprofile, Hub-Chancen, Planner-Volumen, Charakterdaten,
  Geschwindigkeit).
- **Offen (Folgeaufträge):**
  - Befund: 51 wiederholte 403/404 bei Strukturen je Start. Behoben am
    23.10.2026: 403/404 werden je Charakter 24 Stunden gemerkt; automatisch
    geprüft mit `swift test` 570 + 70 und `xcodebuild test`. Live bestätigt
    am 23.10.2026: `4xx=0` beim Folgestart, niedrigstes Fehlerbudget 89 von
    100. Offen ist die Abnahme.
  - Befund: frühe Strukturmarkt- und Strukturdetail-Abrufe. Aufgeklärt:
    dieselbe URL für verschiedene Charaktere mit eigenem Cache-Eintrag.
    Umgesetzt am 24.10.2026: Strukturdetails und -bücher gelten für alle
    Charaktere; „early“ zählt je Charakter. Automatisch geprüft (577 + 70),
    live offen;
  - Startdauer mit abgelaufenem Cache (79 s) untersucht. Die Ursache ist nicht
    belegt; vorgeschlagen sind weitere Messpunkte (siehe dev-diary);
  - Behoben am 23.10.2026: gleichzeitige Token-Erneuerung desselben
    Charakters (Meldung „Autorisierung fehlt“ bei Donna Aumer). Automatisch
    geprüft (572 + 70, `xcodebuild test`). Live bestätigt am 23.10.2026:
    Nach einem Neubau wurden alle 15 Charaktere ohne Meldung synchronisiert;
  - Messlücke: ESI-Zusammenfassung beim Startende fehlt.

## Nachträge zu Handel, Hub-Chancen und Planner (24.–30.10.2026)

Einzelheiten und Prüfungen je Eintrag: [dev-diary.md](dev-diary.md)
(Einträge vom 24. bis 30.10.2026 am Dateianfang).

- **Implementiert:**
  - Hub-Chancen: Zwischenprodukte als Eigenbau, Kosten-Erklärung und
    Multibuy-Einkaufsliste; ruhiges Laden, Favoriten oben, „Zum Planner
    hinzufügen“.
  - Handel: Gewinnpotenzial je Zeitraum für Zielhub und Region; Routen
    Home → Main und Coalition → Main; Transportart je Etappe, auch in Planer,
    Hub-Chancen und Reaktionen; gekoppelte Pfeilschwellen; Kachelbreite nach
    Fensterbreite; Item-Suche über alle Marktgruppen; Handelslogbuch mit
    Verwendung Produktion und Verbrauch.
  - Planner: Kachel „Kosten pro Item“ mit Mindestverkaufspreis inklusive
    Gebühren; Auftragsaufteilung je Stufe abschaltbar, Slots nur aus
    Charakteren; Bauauftragsliste ohne zersplitterte Endproduktaufträge;
    gekaufte BPO ohne Umlage über den BPC-Vertragspreis.
  - Allgemein: Zahleneingaben mit Tausenderpunkten; Hub-Scans warten auf die
    ESI-Cachezeit; Dashboard mit geringerem Ressourcenverbrauch, Karte
    „Top-Chancen“ entfernt; CI-Korrekturen für Swift 6.1 (nach den
    Korrekturen vom 24. und 30.10.2026 war die CI bis 02.11.2026 grün).
- **Automatisch geprüft:** je Eintrag `swift test` und natives
  `xcodebuild test`, bei Katalogänderungen auch `EVEStaticDataKit`.
- **Offen:** Sichtprüfung in der App und Eigentümerabnahme; Punkte ohne
  Auftrag unter „Offene Punkte“.
- Commits vom 24. bis 30.10.2026 bis einschließlich `aaec2e5`, gepusht.

## Lagerverkauf-Abgleich (25./26.10.2026)

Plan und Owner-Leitfaden: [LAGERVERKAUF_PLAN.md](Documentation/LAGERVERKAUF_PLAN.md).

- **Implementiert:** Abgleich je Hub mit eingefügten Items (englische und
  deutsche Namen, Katalogadapter 7), Neuproduktionskosten aus der
  Hub-Chancen-Rechnung, Mindestpreise für Sell-Order und Direktverkauf,
  Empfehlung. Nachträge am 26.10.2026: Einfügen aus der Asset-Liste,
  Tabellenbreite, Detailschalter, nur aktuelle Fehler.
- **Automatisch geprüft:** `swift test`, `xcodebuild test` unsigniert
  `TEST SUCCEEDED`.
- **Offen:** einmaliger „Neuimport des aktuellen Katalogs“ für die deutschen
  Namen; Sichtprüfung; Live- und Eigentümerabnahme nach Abschnitt E des Plans.
- Commit `a229503`, Nachträge in `1b23ba5`, gepusht.

## Marktbestand (29./30.10.2026)

Plan und Owner-Leitfaden: [MARKTBESTAND_PLAN.md](Documentation/MARKTBESTAND_PLAN.md),
Nachweise: [ACCEPTANCE.md](Documentation/ACCEPTANCE.md).

- **Implementiert (P1–P8):** Bestandshistorie je Item für Main, Home und
  Coalition Hub aus den Hub-Scans; feste Termine 06:00/13:00, kein Hub-Scan
  vor ESI-`Expires`; Hintergrundbetrieb mit Menüleiste und Login-Start; eigene
  SQLite-Datei (7 Tage Einzelpunkte, 90 Tage Tageswerte); Handel-Spalten,
  Item-Graph und Ansicht „Marktbestand“.
- **Automatisch geprüft:** zuletzt in P7 `swift test` 656 + 81,
  `xcodebuild test` `TEST SUCCEEDED`.
- **Offen (Live und Eigentümer):** erster gespeicherter Punkt und echte
  Schreibdauer; ESI-Sperre; Login-Start, Fenster schließen, Ruhezustand;
  Strukturmärkte ohne Zugang; Handel-Spalten, Graph und Ansicht mit echten
  Daten; Dateigröße nach 7 Tagen.
- Commits `1b23ba5` und `4d742d0` (Y-Achse), gepusht.

## Planer-Ausbau (30.10.–01.11.2026)

Einzelheiten: [dev-diary.md](dev-diary.md), Abnahmepunkte:
[ACCEPTANCE.md](Documentation/ACCEPTANCE.md), Entscheidungen:
[DECISIONS.md](Documentation/Consolidation/DECISIONS.md).

- **Implementiert:**
  - Manuelle Lager und CSV-Import entfernt; die Planner-Handeingabe
    „Manueller Lagerbestand“ bleibt.
  - Reaktionen und Planer-Empfehlung mit der günstigsten Kette bis zu den
    Ursprungsmaterialien (Regeländerung auf Auftrag).
  - Prompts 1–4: feste Blueprint-Quelle, mehrere Einkaufsorte, Automatik,
    Oberfläche; Start nur über „Berechnen“.
  - Gekaufte Reaktionsformeln aus der günstigsten NPC-Order der Region;
    eigene Formel am Produktionsort oder Main Hub ohne Kosten.
  - Lagerbewertung mit Referenzlauf ohne Lager; Kosten, Zielmarkt und
    Verkauf je Produkt; Info-Panel „So rechnet der Planer“.
  - Schrittplaner mit acht Schritten, Prüfung „Rentabel?“ und
    Materialprüfung; manueller Bestand ersetzt das Lager im ganzen Ablauf;
    „Berechnung gestoppt“ mit Zeile und Namen; rund 90 übersetzte Warnungen;
    Multibuy-Gesamtliste je Hub.
  - Jobdauer mit Skills und Implantaten; Charaktere und Implantate je
    Standort und Tätigkeit; Planer zurücksetzen; Vergleichsmärkte als
    Einkaufsorte.
- **Automatisch geprüft:** zuletzt `swift test` 767 + 94, `EVEStaticDataKit`
  13, `xcodebuild test` `TEST SUCCEEDED` (767), `check_planner_guide.py
  --self-test`.
- **Live geprüft:** Der Ark-Plan zeigt nach „Berechnen“ wieder Gewinne
  (Eigentümerrückmeldung 31.10.2026). Jobkosten gegen Screenshots des
  EVE-Jobfensters für Ark, Nomad und Rhea: Abweichung je 0,0343 %. Ein Test
  rechnet die Jobdauer der Ark aus dem Jobfenster auf die Sekunde nach.
- **Offen:** Eigentümerabnahme mit echten Plänen (Ark, Nomad, Rhea);
  Sichtprüfung der Einstellungen zu Charakteren und Implantaten; Jobdauer von
  Kopieren, Forschung, Invention und Reaktionen gegen das Jobfenster.
- Commits `40c145f` bis `f1d6c6c`, gepusht.

## App-Analyse und Geschwindigkeit A1–A6 (02.–05.11.2026)

Bericht, Messwerte und Prompt-Reihe: [ANALYSE_2026-11-02.md](Documentation/ANALYSE_2026-11-02.md).

- **Implementiert:**
  - A1: Messpunkte und Golden-Master für den Planer;
  - A2: DOTLAN-Cache, Cache-Kürzung je Klick, Vergleichsmärkte parallel,
    Logbuch-Abgleich im Hintergrund;
  - A3: Planer-Pipeline im Core mit Datensitzung je Klick;
  - A4: Zeilen-Cache im Handel;
  - A5b: höchstens zwölf gleichzeitige ESI-Anfragen, automatische weiter
    höchstens zwei;
  - A6: Home- und Coalition-Analyse gleichzeitig (G10); 5xx und
    Transportfehler im Messprotokoll.

  Rechenregeln unverändert, Golden-Master byte-identisch. Zurückgestellt:
  A5 (G5, G11) und G9.
- **Automatisch geprüft:** zuletzt (A6) `swift test` 785 + 104,
  `EVEStaticDataKit` 13, `xcodebuild test` `TEST SUCCEEDED` (785).
- **Live gemessen (Eigentümer, Xcode-Debug, derselbe Plan):** Planer-Klick
  nach Neustart 30,8 s (A2) → 12,8 s (A3); mit zwölf parallelen Anfragen
  erster Klick 11,4 s statt 19,7 s am Vortag (A5b). Handel:
  Hauptthread-Anteil der Zeilenberechnung 21 % (A1) → 0,09 % (A4). Die
  A6-Messung war wegen gestörtem ESI nicht aussagekräftig.
- **Offen:** Sichtprüfung von A4; Messung von A6 bei normaler ESI-Lage;
  A6b–A8; Eigentümerabnahme.
- Commits `1195e18` bis `85749de` gepusht; A6 im Sammel-Commit `0b7fb5c`,
  gepusht am 08.11.2026. Die CI scheiterte ab `c36c27e` an der Übersetzung;
  seit `abc1b10` übersetzt sie wieder, ein Test in `AppTextSizeTests` ist rot;
  seit `178920d` ist dieser grün und ein anderer rot, angepasst und
  gepusht, Nachweis offen (siehe „Offene Punkte“).

## Oberflächenstil „New Eden HUD“ D1–D8 (07.11.2026)

Plan und Abnahme-Checkliste: [DESIGN_HUD_2026-11-07.md](Documentation/DESIGN_HUD_2026-11-07.md).

- **Implementiert:** Umschalter „Klassisch“ / „New Eden HUD“ (Standard
  „Klassisch“), gemeinsame Bausteine in `InterfaceStyleComponents.swift`,
  Seitenleiste in Gruppen, Rastergrund, Bereichszeile, HUD-Fassung aller
  Bereiche. Das Farbschema läuft über `NSApp.appearance`; damit ist ein
  älterer Fehler behoben, bei dem die App bis zum Neustart dunkel blieb.
- **Automatisch geprüft:** zuletzt (D8) `swift test` 785 + 104 und 38
  XCTest-Fälle, `EVEStaticDataKit` 13, `xcodebuild build` und `test` grün.
- **Sichtgeprüft:** isolierte Debug-App ohne Nutzerdaten, 18 Ansichten und
  6 Einstellungsseiten je Stil; „Klassisch“ per Pixelvergleich unverändert.
- **Offen:** Eigentümerabnahme mit echten Daten nach Abschnitt 7 des Plans;
  Menüleisten-Ansicht und Hinweisfenster im App-Farbschema nicht in der App
  geprüft.
- Im Sammel-Commit `0b7fb5c`, gepusht am 08.11.2026.

## Einzelkorrekturen (07./08.11.2026)

- **Implementiert:**
  - Market Browser vollständig entfernt (Ansicht, Service, Modelle, nur dort
    genutzte Texte und Tests).
  - Öffentliche Verträge: Der Erstimport-Hinweis bläht das Fenster nicht mehr
    auf; Sortierung nach Preis und Filter nach Region.
  - Item-Verlauf: engere Werteachse und Mouse-over je Hub.
  - Die Schriftgröße wirkt in der ganzen App (`AppFont`).
  - Planer: Umschalter Einzel-/Sammelproduktion entfernt; Eingabefehler in
    Schritt 2 übersetzt.
- **Automatisch geprüft:** je Eintrag `swift test` und `xcodebuild test`
  grün, zuletzt 785 + 148 Tests und 49 XCTest-Fälle.
- **Offen:** Sichtprüfung mit echten Daten (Vertragshinweis, Mouse-over,
  Schriftgrößen in Ansichten mit Daten, Berechnung mit mehreren Produkten)
  und Eigentümerabnahme. CI-Befund vom 08.11.2026: Leerzustände
  (`AppUnavailableView`) sahen bei „Standard“ unter macOS 14 und 15 anders
  aus als der Systemleerzustand; mit `178920d` korrigiert. Unter macOS 15
  sind seitdem zwei Schriftstufen im Leerzustand gleich hoch; das ist nach
  Wahl des Eigentümers zulässig (siehe „Offene Punkte“).
- Commits `f63dc83`, `69f285f` und `0b7fb5c`, gepusht am 08.11.2026.

## Dashboard nach Board DB1–DB8 (07./08.11.2026)

Plan und Abnahme-Checkliste: [DASHBOARD_BOARD_2026-11-07.md](Documentation/DASHBOARD_BOARD_2026-11-07.md).

- **Implementiert:**
  - DB1–DB5: Grundgerüst, Main-Hub-Chancen · Top 5, Nettowert-Zeitraum und
    Veränderung, Kennzahlenreihe, Seitenkopf mit ESI-Status und „Alles
    aktualisieren“;
  - DB6: Durchsicht und Abnahme-Checkliste;
  - DB7: Nacharbeiten B1–B10 (Sprache der Popover und Formate, Kennungen,
    Leerzustände, Begriffe);
  - DB8: deutscher Kacheltitel „Wissenschafts-Slots“.
- **Automatisch geprüft:** zuletzt (DB8) `swift test` 785 + 148 und 49
  XCTest-Fälle, `EVEStaticDataKit` 13, `xcodebuild build` und `test`
  (785) grün.
- **Sichtgeprüft:** isolierte Debug-App mit synthetischen Testdaten, beide
  Stile und Sprachen, breit und schmal.
- **Vom Eigentümer abgenommen (08.11.2026):** insgesamt als „i. O.“ erklärt,
  ohne Einzelmarkierungen in Abschnitt 7. Für die nur mit echten Daten
  prüfbaren Punkte (7.2, E1–E13) liegen keine Ergebnisse je Punkt vor;
  Kopieren per Klick ist nicht einzeln belegt, die Laufzeit mit echten Daten
  nicht gemessen.
- DB1–DB7 im Sammel-Commit `0b7fb5c`, gepusht am 08.11.2026; DB8, die
  DB7-Nachträge und der Abnahmevermerk sind beim Schreiben dieses Stands
  uncommittet.
