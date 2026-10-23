# Konsolidierungsentscheidungen – 25.09.2026

Aktuell: Die folgenden nummerierten Entscheidungen beschreiben den organisatorischen
Checkpoint `182f1a9`. Die anschließend ausdrücklich freigegebene fachliche Integration
und deren Konfliktentscheidungen stehen in [FUNCTIONAL_CONSOLIDATION.md](FUNCTIONAL_CONSOLIDATION.md).

Projekt: EVE New Eden Nexus - Assets, Industry, Markets. Standardmodell: Astra Medium.

1. **Ein aktiver Stamm.** `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets` ist die alleinige Arbeitswurzel.
   Die beiden ehemaligen Arbeitsordner werden nach erfolgreicher Prüfung nach
   `/Users/svenstolze/Documents/_archive/EVE-Nexus-Konsolidierung-2026-09-25/`
   verschoben. Vorhandene Vollbackups bleiben unveränderte Legacy-Sicherungen.
2. **Keine Nutzerarbeit verwerfen.** Simple-HEAD e3bc7a9 plus vollständiger Arbeitsbaum
   bilden die Basis. 83 Statuszeilen einschließlich teilweise gestagter Dokumente
   sind im Quellinventar und in getrennten Index-/Arbeitsbaum-Patches nachvollziehbar.
   Nexus-HEAD 058d494 plus 266 Statuszeilen werden vollständig als Quellen erhalten.
3. **Backup-Dubletten.** 153 Dateien sind bytegleich. Fünf Dateien unterscheiden sich:
   ContentView enthält den erhaltenen Höhen-Fix der Sidebar, RuntimeFeatureStateTests
   dessen Regressionstest, die beiden Dokumente die jüngsten Nachweise; das aktuelle
   Xcode-Projekt enthält die gültigen Dateizuordnungen. Das Backup ersetzt diese
   Dateien nicht. Seine fünf Varianten sind separat archiviert.
4. **Xcode-Dubletten.** Das bereits gelöschte `EVENexusSimple 2.xcodeproj` wird aus
   HEAD recoverbar als Archiv gesichert. Die neun nummerierten Nexus-Projekte
   2–10 verbleiben im vollständigen Legacy-Quellarchiv. Nur ein Xcode-Projekt ist aktiv.
5. **Architekturkonflikt.** Simple und Nexus sind keine bloßen Namensvarianten.
   Ihre Fachmodelle, APIs, Keychain- und Migrationsverträge sind nicht austauschbar.
   Details und nicht integrierte exklusive Funktionen stehen in COMPONENTS.md.
6. **Dokumentationskanon.** dokumentation.md geht vollständig in PRODUCT.md auf;
   Documentation/ARCHITECTURE.md in ARCHITECTURE.md. Beide alten Pfade werden
   Verweise. README wird zum Einstieg; dessen bisheriger Volltext bleibt im Quellarchiv.
   AGENTS übernimmt bestehende Copy-/Sortierregeln und Datenintegritäts-/Git-Regeln.
   Alte Prompts und Optimierung.md werden archivierte Historie statt aktiver Roadmap.
7. **Namensänderung.** Produkt-/Anzeigename, SwiftPM-Produkt, Scheme-Produktverweise,
   Barrierefreiheitslabel und aktive Dokumentation erhalten den vereinbarten Namen.
   Technische Identitäten und Netzwerk-User-Agent bleiben kompatibel. Keine neue Grafik.
8. **Git.** Eigener Konsolidierungsbranch; lokal autorisierter Checkpoint inklusive
   übernommener Nutzeränderungen. Ursprüngliche Repositories samt Indizes/Historien
   bleiben im Archiv. Kein Push oder Remote-Rename.
9. **Quellenbegrenzung.** Der früher genannte Production-Tracker-Pfad existiert nicht.
   Verfügbar waren zwei lokale Codebasen, das Vollbackup und die Recovery-Berichte.
   Nicht vorhandene Quellen wurden nicht rekonstruiert oder als übernommen behauptet.

Maschinenlesbare Herkunft: [Inventar](source-inventory.json),
[Dubletten](duplicate-inventory.json). Quellarchive mit Prüfsummen:
[Archivregister](../../_archive/README.md).

## Ergebnis der Prüfung und Archivierung

- Beide alten Arbeitsordner sind vollständig verschoben. Quellhashes, ursprünglicher
  Git-Status, HEAD und Index-/Arbeitsbaum-Patches wurden vor dem Verschieben geprüft;
  Hashes, Status und HEAD danach erneut bestätigt. Zielpfade: archive-locations.json.
- Eine vorhandene Testdatei, LoyaltyStoreCatalogTests.swift, war nur über SwiftPM
  eingebunden. Ihre Xcode-Dateireferenz und Core-Testzuordnung sind ergänzt; keine
  Testlogik hinzugefügt oder geändert. Nun sind alle 21 Core-Testdateien enthalten.
- Alle Fachquellen, Tests und Kit-Dateien stimmen bytegenau mit dem übernommenen
  Arbeitsbaum überein. Einzige Quelltextabweichung der Konsolidierung ist das
  neue Barrierefreiheitslabel in ContentView.swift.
- Patchnachweise liegen platzsparend und bytegenau reversibel als .patch.gz vor.
- Der kopierte, bereits verwaiste temporäre CI-Worktree-Eintrag wird im aktiven Git
  bereinigt; die ursprüngliche Git-Metadatenkopie bleibt im Legacy-Ordner erhalten.
- Codex-Oberflächenzugriff ist systemseitig gesperrt. Kein verfügbares Projektwerkzeug
  kann die ChatGPT-Projektanzeige umbenennen. Die Sidebar ist deshalb nicht als
  vollständig vereinheitlicht ausgewiesen. Globale Modelleinstellungen unverändert.

## 19.10.2026 – Fertigungsprojekte entfernt

Eigentümerentscheid: Der Planner soll ohne Projektverwaltung arbeiten. Man trägt das Produkt ein und
lässt rechnen.

- **Entfernt:** Projektwahl, Projekteinstellungen (Status, Priorität, Lagerfreigaben, Ausschlüsse,
  Mengengrenzen, Preisprofil-Zuweisung, Logistik-/Installations-Ersatzwerte, Duplizieren, Archiv),
  Projektreservierungen samt Konfliktvorschlag, Einkaufsbudget, Einkaufsfortschritt und Einkaufsexport.
- **Berechnung:** ESI-Bestand nach der unveränderten Schutzmengenberechnung plus Planner-Handeingabe.
  Pläne anderer Projekte mindern den Bestand nicht mehr. Manuelle Lager fließen nicht ein, bleiben
  aber als eigene Verwaltung bestehen. Die übrigen Rechenregeln sind unverändert.
- **Wissenschaft:** Aufträge sind global. Alle nicht archivierten Aufträge liefern Versorgung und
  Input-BPC-Reservierungen. Neue Aufträge speichern keine Projekt-ID; alte Projekt-IDs bleiben erhalten.
  Aufträge, die früher zu archivierten Projekten gehörten, sind dadurch wieder wirksam, bis sie archiviert werden.
- **Preisprofile:** Sie bleiben pflegbar, sind aber reine Referenzpreise. Der Marktimport liest den
  aktuell berechneten Plan. (Am 22.10.2026 entfernt, siehe unten.)
- **Altdaten:** `projects`, `selectedProjectID`, `reservations` und `purchases` bleiben im
  `ConsolidationWorkspace` und werden unverändert dekodiert und wieder gespeichert, aber nicht mehr
  verwendet oder validiert. Format (`formatVersion` 1), SwiftData-Schema und Migrationskette sind
  unverändert, ebenso Sicherungen. Ein neuer Arbeitsdatenverbund legt kein Projekt mehr an.

## 20.10.2026 – Zentraler Startablauf, automatische Scans ohne Opt-in

Eigentümerentscheid: Beim Programmstart lädt die App alle ESI-Daten automatisch.
Grundlage ist das Ablaufdiagramm aus [HUB_CHANCEN_PLAN.md](../HUB_CHANCEN_PLAN.md),
Schritt P1.

- **Reihenfolge:** Zuerst laufen parallel die Synchronisierung aller verbundenen
  Charaktere und die Planner-Konfiguration. Danach starten Reaktionen,
  Mondmaterial- und Mineralien-Analyse sowie die Freigabe der automatischen
  Main-Hub- und Public-Contracts-Scans. Der Ablauf gehört dem `RuntimeState`
  (`StartupDataLoad`) und läuft einmal je App-Prozess.
- **Ersetzt:** Bisher lief der Charakter-Sync erst beim ersten Dashboard-Aufruf.
  Das Dashboard übernimmt jetzt das Ergebnis des Startablaufs und synchronisiert
  nicht ein zweites Mal.
- **Main-Hub-Scan:** Die Einwilligung (`market.main-hub.automatic-updates-*` in den
  App-Defaults) wird nicht mehr gelesen. Die gespeicherten Werte bleiben unverändert
  liegen. „Pausieren“ im Dashboard wirkt nur bis zum nächsten Start.
- **Public Contracts:** Ein ausgeschalteter Automatikschalter im Vertragsindex
  wird beim Start wieder eingeschaltet. Ein manueller Stopp pausiert den Import
  bis zum nächsten Start.
- **Unverändert:**
  - die Transportgrenze (6 Anfragen, davon höchstens 2 automatisch),
  - der Planner-Vorrang mit kooperativem Abbruch,
  - die 6-Stunden-Wiederverwendung und 15 Sekunden Startverzögerung der Scans,
  - das 5-Minuten-Fenster der Analysen.

  Im Recovery-Modus und mit `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1` startet
  nichts. Ohne Hintergrunddienste synchronisiert das Dashboard wie bisher selbst.

## 22.10.2026 – Manuelle Preisprofile entfernt

- **Anlass:** Eigentümerauftrag nach Prüfung. Profile wurden angelegt, mit Einzelpreisen, CSV oder
  Planpreisen gefüllt, angezeigt und gesichert, aber keine Berechnung, kein Filter und keine Ansicht
  las sie. `ConsolidatedProject.priceProfileID` wurde nie gesetzt.
- **Entfernt:** Panel **Preisprofile** in den Markteinstellungen, CSV-Importart `prices`,
  `createPriceProfile`, `ManualPriceProfile.price(_:at:)` und die Vorschauzeilen für Profiländerungen.
- **Altdaten:** `priceProfiles` und `ManualPriceProfile` bleiben im `ConsolidationWorkspace` und
  werden unverändert dekodiert und wieder gespeichert, aber nicht mehr validiert. Format
  (`formatVersion` 1), SwiftData-Schema, Migrationskette und Sicherungen sind unverändert. Die
  Diagnose zählt Profile unter den Altdaten.

## 22.10.2026 – Bereich Handel

- **Anlass:** Eigentümerauftrag mit Referenzbild. Plan und Rückfragen stehen im
  [Handel-Plan](../HANDEL_PLAN.md), Abschnitte A und E.
- **SDE:**
  - Neuer Pflichtdatensatz `marketGroups.jsonl` und Katalogadapter 5.
  - Der Inhalts-Hash eines Builds ändert sich dadurch. Bestehende Kataloge
    bleiben gültig und melden für Marktgruppen „SDE-Neuimport nötig“.
  - Annahme: Die Datei liegt im offiziellen JSONL-Archiv. Belegt ist das nur
    über das Community-Schema `sde.riftforeve.online`, Build 3632936. Fehlt sie
    im Archiv, scheitert ein SDE-Import, bis der Datensatz optional gemacht
    wird.
- **Regeländerung Hub-Scans:**
  - Home- und Coalition-Scans von Spielerstrukturen laden immer das volle
    Orderbuch statt nur der Fertigungsprodukte. Das macht sie länger und die
    Bedarfsdatei größer.
  - Die Chancenanalyse erhält weiterhin nur die Produkttypen.
  - Die bisherige Bedarfshistorie läuft weiter.
- **Handelsrechner:**
  - Die bestehende Kurier-Max-Regel bleibt; Collateral ist der Einkaufswert.
  - Main → Coalition: Kurier Main → Home plus Home → Coalition wie bei den
    Hub-Chancen.
  - Jump Freighter je Einheit bei voller Ladung, mit Menge je angefangenem
    Flug.
  - Eigene Orders liegen einen Preisschritt nach der 4-Stellen-Regel besser.
    Die Regel stammt aus dem Wissensstand des Assistenten und ist nicht gegen
    eine CCP-Quelle belegt.
  - Relist-Gebühren sind nicht enthalten.
- **Speicher:** Das Handelslogbuch nutzt eine eigene SQLite-Datei mit
  `user_version`-Migrationen und keine SwiftData-Schemaänderung. Die
  Datensicherung erfasst die Datei mit, weil sie den ganzen Datenordner
  sichert.
- **Wallet:**
  - Nur persönliche Charakter-Wallets, keine Corporation-Wallet.
  - Gespeichert wird nach jeder Charakter-Synchronisierung, idempotent über
    die 30 ESI-Tage hinaus.
  - Die DTOs von Transaktionen und Orders sind additiv erweitert (Ort,
    Journal-Referenz, Ausgabedatum, Laufzeit).
- **Abgleich:**
  - Ein Eintrag je Kauftransaktion ab einem Startdatum (Standard: Tag der
    Einrichtung).
  - Ziel Main → Home, sonst der Kauf-Hub.
  - Fertigungsmaterial = Materialien aktiver Planner-Pläne.
  - FIFO je Item und Ziel-Hub.
  - Steuer belegt aus dem Journal, Broker berechnet.
  - Die Orderart wird aus eigenen Orders erkannt (Charakter, Item, Ort, Seite,
    Laufzeitfenster, ohne Preis). Ohne Orderdaten gilt Sofortkauf bzw. eigene
    Sell-Order, markiert als angenommen. Diese Regel ist ohne Rückfrage
    abgeleitet aus „Direktverkauf ist selten“.
- **Unverändert:** Bundle-ID, Datenpfade bestehender Dateien, SwiftData-Kette,
  Hub-Chancen-Rechnung und alle bestehenden Marktszenarien.

## 22.10.2026 – Handel: Station Trading entfernt, Home ↔ Coalition ergänzt

- **Anlass:** Eigentümerauftrag nach Abschluss des Handel-Plans
  ([Abschnitt I](../HANDEL_PLAN.md)).
- **Entfernt:** die Modi Station Trading Main, Home und Coalition.
  Gespeicherte Auswahlwerte fallen auf Main → Home zurück.
- **Neu:** die Routen Home → Coalition und Coalition → Home mit der
  Home-↔-Coalition-Etappe, für Coalition → Home in umgekehrter Richtung.
  Annahme: gleiche Jump-Freighter-Treibstoffkosten in beiden Richtungen.
- **Geänderte Regel (Wallet-Abgleich):** Käufe im Home bzw. Coalition Hub
  bekommen jetzt den jeweils anderen Hub als Ziel statt Station Trading im
  Kauf-Hub. Bereits angelegte Logbuch-Einträge bleiben unverändert.

## 23.10.2026 – Verpacktes Volumen zuerst aus dem SDE

- **Anlass:** Eigentümerfrage, ob sich Last durch lokal gespeicherte statische
  EVE-Daten reduzieren lässt. Je Main-Hub-Scan fragte die App rund 5.700
  einzelne ESI-Typdetails nur für das verpackte Volumen ab, nach jedem
  Neustart erneut.
- **Entscheidung (Eigentümer):** Das verpackte Transportvolumen kommt zuerst aus
  dem tatsächlich importierten SDE-Feld `packagedVolume`. ESI wird nur noch für
  Typen ohne SDE-Wert abgefragt.
- **Begründung:** Die frühere Regel (Volumen nur aus ESI) stammte aus SDE-Build
  3458726, in dem alle veröffentlichten Typen `packaged_volume = NULL` hatten.
  Im aktiven Build 3632936 tragen 26.347 von 27.309 veröffentlichten Typen einen
  Wert; Stichproben stimmen mit ESI überein (Hulk 3.750, Ark 1.300.000,
  Rifter 2.500 m³).
- **Unverändert:** Das entpackte `volume` ersetzt nie ein fehlendes verpacktes
  Volumen. Fehlt der Wert in SDE und ESI, bleibt die Logistik unverfügbar.
- **Umfang:** Nur statische Daten. Lasten auf dem Hauptthread und in den
  Ansichten sind ein eigener späterer Auftrag.

## 23.10.2026 – Dauerhafter ESI-Antwortcache

- **Anlass:** CCP empfiehlt, Daten nicht vor `Expires` erneut abzurufen. Der
  ESI-Cache lag nur im Arbeitsspeicher, also lud jeder App-Start noch gültige
  Daten neu.
- **Entscheidungen (Eigentümer):**
  - Gespeichert werden öffentliche und private Antworten. Private Rohantworten
    liegen unverschlüsselt im Datenordner, ohne Tokens; beim Trennen eines
    Charakters werden sie gelöscht.
  - Massenabrufe bleiben nur im Arbeitsspeicher: das öffentliche
    Regions-Orderbuch ohne `type_id` und die Public-Contracts-Abrufe.
  - Strukturmarkt-Orderbücher werden dauerhaft gespeichert.
  - Obergrenze 512 MB auf der Platte.
  - Der Ordner `caches` gehört nicht zur Datensicherung.
- **Unverändert:** Rate- und Fehlerlimits, Warteschlange, Seitenkonsistenz und
  alle fachlichen Regeln.

## 23.10.2026 – Nicht zugängliche Strukturen merken

- **Anlass:** Im Live-Lauf kamen je Start 51 wiederholte 4xx-Antworten der
  Strukturdetails; das ESI-Fehlerbudget sank auf 49 von 100. CCP rät von
  wiederholten 4xx ab, sie kosten je 5 Tokens.
- **Entscheidungen (Eigentümer):**
  - 403 (keine Andockberechtigung) und 404 (Struktur nicht vorhanden) werden
    gemerkt.
  - Neu geprüft wird nach 24 Stunden, je Charakter und dauerhaft über
    Neustarts.
  - Eine ausdrücklich gestartete Struktursuche fragt immer neu bei ESI.

## 24.10.2026 – Strukturdaten für alle Charaktere teilen

- **Anlass:** Im Live-Lauf luden mehrere Charaktere dieselbe Struktur einzeln:
  210 Strukturdetail-Einträge für 71 Strukturen. Die vier Aufrufer der
  Strukturmärkte wählten verschiedene Charaktere für dasselbe Orderbuch.
- **Entscheidung (Eigentümer):**
  - Frisch geladene Strukturdetails und Strukturmarkt-Orderbücher gelten bis
    `Expires` für alle Charaktere.
  - Ein Charakter ohne Andockrecht sieht damit Daten, die ein anderer eigener
    Charakter geladen hat.
  - Die Charakterwahl der Aufrufer bleibt unverändert.
- **Außerdem:** Der Messzähler „early“ zählt je Charakter statt je URL.
