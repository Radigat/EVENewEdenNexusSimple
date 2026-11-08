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
  Pläne anderer Projekte mindern den Bestand nicht mehr. Manuelle Lager fließen nicht ein (seit
  30.10.2026 ganz entfernt). Die übrigen Rechenregeln sind unverändert.
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

## 30.10.2026 – Manuelle Lager entfernt

- **Anlass:** Eigentümerauftrag. Manuelle Lager flossen seit 19.10.2026 in keine Berechnung ein.
- **Entfernt:** Schaltfläche **Manuelle Lager** im Lager, Dialog und Bestandsbearbeitung,
  CSV-Import samt Parser und Dateileser, zusätzliche Warnschwellen, Abschnitt **Letzte Importberichte**
  in den allgemeinen Einstellungen und die zugehörigen Vorschauzeilen.
- **Nicht betroffen:** die Planner-Handeingabe **Manueller Lagerbestand** (fließt weiterhin in die
  Planberechnung ein), Mindestbestände und Alarme im Lager sowie synchronisierte Bestände.
- **Altdaten:** `warehouses`, `imports`, `warningThresholds` und `ManualWarehouse` bleiben im
  `ConsolidationWorkspace` und werden unverändert dekodiert und wieder gespeichert, aber nicht mehr
  validiert. Format (`formatVersion` 1), SwiftData-Schema, Migrationskette und Sicherungen sind
  unverändert. Die Diagnose zählt manuelle Lager unter den Altdaten.

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

## 30.10.2026 – Gekaufte BPO ohne Umlage über BPC-Verträge bewerten

- **Anlass:** Planer „Ark 1 3 2“: Radar-FTL Interlink Communicator und Capital
  Core Temperature Regulator liefen über eine noch zu kaufende Markt-BPO
  (1,59 bzw. 1,50 Mrd. ISK) ohne eingetragene Umlage. Damit blieben BPC/BPO,
  Produktionszwischensumme, Kosten pro Item und alle Gewinne „nicht verfügbar“.
- **Entscheidung (Eigentümer):** Den Preis aus den BPC-Verträgen ableiten; bei
  einer gewählten BPO prüfen, ob sie bereits in Benutzung ist, dann keine
  Kosten ansetzen.
  - Noch zu kaufende BPO (Markt oder Vertrag) ohne Umlage: genutzte Runs ×
    günstigster Preis pro Run eines gleich- oder besserwertigen öffentlichen
    Einzel-BPC-Vertrags am Main Hub.
  - Eigene BPO (bereits vorhanden) ohne Umlage: weiterhin 0 ISK.
  - Eingetragene Umlage hat Vorrang; ohne passenden BPC-Vertrag bleibt die
    Quelle ungeklärt. Der BPO-Kaufpreis bleibt als Kapitalbedarf sichtbar.
- **Ersetzt:** die Regel, dass ein BPO-Kauf immer eine eingetragene Umlage
  benötigt.

## 30.10.2026 – Feste Blueprint-Quelle im Planer

- **Anlass:** Der Planer soll möglichst automatisch den kostengünstigsten Weg
  wählen. Bisher galt BPC am Ort vor BPO und danach eigene Blueprints an anderen
  Orten.
- **Entscheidung (Eigentümer):** Feste Reihenfolge: eigene BPO am Produktionsort,
  eigene BPC am Produktionsort mit Rest aus BPC-Verträgen, BPC-Vertrag mit den
  niedrigsten Material- plus Vertragskosten, dann BPO-Vertrag, Markt-BPO, Loyalty
  Store, manuelle externe BPC. Eigene Blueprints an anderen Orten bleiben nur
  manuell wählbar.
- **Umsetzungsregel:** Fehlt für einen Vertragsvergleich ein Materialwert, bleibt
  die Quelle ungeklärt. Der Vergleich rechnet Materialien ab Anlage, also
  einschließlich Transportanteil.
- **Ersetzt:** die bisherige Prioritätskette der Blueprint-Empfehlung.
- **Noch offen:** Einkaufsorte, automatische Übernahme und neue Oberfläche
  folgen in den Prompts 2 bis 4 der Reihe.

## 30.10.2026 – Einkaufsorte im Planer

- **Entscheidung (Eigentümer):** Mehrfachauswahl im Planer vor der Berechnung; zur
  Wahl stehen nur Märkte mit konfigurierter Strecke (Main, Home, Coalition). Je
  Material gewinnt der billigste Ort einschließlich Transport, bei fehlender
  Tiefe wird aufgeteilt. Unbekannte Strecke: Ort entfällt mit Hinweis. Home Hub:
  Transport 0 mit Hinweis.
- **Ersetzt:** „Plankosten nur am Main Hub“.
- **Umsetzungsregeln:** Ohne Wahl gilt der Main Hub. Komprimiertes Erz bleibt am
  Main Hub und entfällt, wenn er abgewählt ist. Eine Strecke mit eigenem Jump
  Freighter hat keine Kurierpreise und gilt als unbekannt. Das Feld
  `purchaseLocation` der Materialwahl steuert den Einkauf nicht mehr; maßgeblich
  sind die `purchaseAllocations` des Plans.

## 30.10.2026 – Automatik im Planer

- **Entscheidung (Eigentümer):** Der Planer rechnet bei Änderungen selbst und
  übernimmt Bauen oder Kaufen und Blueprints. Manuelle Eingriffe bleiben und sind
  zurücksetzbar. Ein gespeicherter Plan wird beim Öffnen nicht neu gerechnet.
- **Ersetzt:** „Baubar heißt Bauen ohne Übernahme“ im Planer. Handel und Chancen
  behalten ihre Regeln (`automaticSupply` nur im Planer).
- **Umsetzungsregeln:** Neue Entwurfswerte `planner.manual-decisions.draft.v1` und
  `planner.blueprint-supply-draft.v3`. Der neue Schlüssel enthält nur echte Übergaben;
  der alte v2-Entwurf mischte sie mit automatischen Quellen und wird nicht mehr
  gelesen. Eine dort noch offene Übergabe muss neu angestoßen werden.

## 30.10.2026 – Oberfläche des Planers

- **Entscheidung (Eigentümer):** Aufbau Einkaufsorte, Item, Ergebnis, Einkaufsliste je
  Ort, Aufträge, aufklappbare Details. „Berechnen“ als Pflichtschritt und die
  Übernahmeknöpfe entfallen.
- **Umsetzungsregeln:** „Jetzt neu berechnen“ bleibt für frische Preise. Zielmarkt und
  Warnungen bleiben außerhalb der Details, weil sie das Ergebnis erklären.
- **Abweichung:** Der Hinweis nennt nur SDE-Katalog und Main Hub. Eine fehlende Anlage
  gibt es nicht, weil die Produktionsbasis immer eine Standardanlage anlegt.

## 31.10.2026 – Planer rechnet nur auf Klick

- **Entscheidung (Eigentümer):** Der Planer rechnet erst, wenn „Berechnen“ angeklickt
  wird. Bauen oder Kaufen und Blueprints wählt die Rechnung weiter selbst.
- **Ersetzt:** „Rechnet bei jeder Änderung neu“ und „Berechnen entfällt als Pflichtschritt“
  aus den Einträgen vom 30.10.2026.

## 31.10.2026 – Gekaufte Reaktionsformeln

- **Auftrag (Eigentümer):** Fehlende Formeln ermitteln und die Automatik danach bauen.
- **Befund:** Gekaufte BPOs wurden nur über ersetzte BPC-Runs bewertet. Formeln haben
  keine BPC-Verträge, sie blieben daher ohne Kosten und hielten Gesamtkosten und Gewinn
  offen. NPC-Orders liegen außerhalb von Jita 4-4, dort wurde nur der Hub gelesen.
- **Entscheidung (Eigentümer):** Formelkosten kommen nur aus der NPC-Sell-Order und sind
  einmalig; ist die Formel vorhanden, kommen keine weiteren Kosten dazu.
- **Umsetzungsregeln:** NPC-Order heißt 365 Tage Laufzeit (ESI nennt keinen Verkäufer).
  „Vorhanden“ heißt am Produktionsort oder am Main Hub, weil die Formel von dort mit den
  Materialien mitgeht (Eigentümer). Dafür gibt es einen Listenhinweis und Transportkosten
  nach Volumen und Collateral; als Collateral dient der NPC-Preis, sonst der
  ESI-Durchschnittspreis (31.10.2026: bei 19 Formeln 10 bzw. 15 Mio. ISK wie die NPC-Orders);
  ohne beide bleibt der Transport mit Warnung außerhalb der Kosten. Formeln an anderen Orten zählen nicht
  automatisch. Ohne NPC-Order wird das Produkt gekauft.

## 31.10.2026: Lagerbewertung und Verkauf je Produkt

Entscheidungen des Eigentümers:

1. Das Lager wird voll verbraucht. Reicht die Markttiefe nicht, wird der Verbrauch mit den günstigsten Orders von Main und Home Hub zusammen bewertet.
2. Reichen beide nicht, gilt die günstigere Produktion aus Rohstoffen oder der Kauf von Zwischenprodukten.
3. Mit und ohne Lager kostet ein Auftrag gleich viel: Lagerwert = Kosten ohne Lager − noch anfallende Kosten. Das ist eine reguläre Bewertung und darf als Zielmarkt vorgeschlagen werden. Der Einzelwert aus Marktpreis und Versorgungskette bleibt Gewichtung und Rückfall. Das ersetzt zwei zuvor am selben Tag getroffene Regeln (Kettenwert nur als Schätzung, günstigerer Wert je Material); Anlass waren der Vergleich mit Ravworks und die 196 Mio. ISK Abweichung der Ark zwischen beiden Rechnungen.
4. Verkaufsort und Allianzpreis gelten je Produkt, dazu kommt eine Gesamtsumme.
5. Gemeinsame Kosten werden nach Verursachung verteilt.
6. In einem Plan mit mehreren Produkten zeigt ein Produkt ohne Zielmarkt in der Produktionsübersicht keinen Vorschlagspreis und keinen erwarteten Gewinn.
7. Der Haken „Vollständig verkauft“ setzt bei einer Teilabnahme der Allianz die abgenommene Menge; das Feld „Verkauft“ bleibt bis zur produzierten Menge frei.

Im freigegebenen Plan festgelegt: Der Einkauf folgt weiter den gewählten Einkaufsorten, und bereits erfasste Zeilen der Produktionsübersicht bleiben unverändert.

## 31.10.2026: Planer in Schritten, Rentabilität und Sammelproduktion

Entscheidungen des Eigentümers (Skizze und Rückfragen):

1. Der Planer ist in Schritte mit Schrittleiste geteilt, sichtbar ist nur der aktuelle Schritt: Einstellungen, Produkte, Lager, Kosten, Anpassen, Einkauf, Bauaufträge, Verkauf.
2. Die Rentabilität wird schon im Kostenschritt gegen die Verkaufsszenarien geprüft. Ist ein Plan nicht rentabel, warnt der Planer und der Benutzer entscheidet.
3. Mehrere verschiedene Produkte laufen als **Sammelproduktion** mit gemeinsamer Rechnung und einer Tabelle je Produkt; unrentable Produkte lassen sich entfernen.
4. Verkauf auswählen und dann in der Produktionsübersicht vermerken.

Im freigegebenen Plan festgelegt: Rentabel heißt endgültiger Gewinn über 0; ohne endgültigen Wert ist das Ergebnis „nicht prüfbar“ und verlangt ebenfalls eine Entscheidung. Die Entscheidung gilt nur für die jeweilige Berechnung. Lager = Nein rechnet ohne jeden Bestand. Vermerken ist gesperrt, solange der Plan veraltet ist oder ein Zielmarkt fehlt. Historische Pläne behalten die Gesamtansicht. Rechenregeln bleiben unverändert.

Entscheidung des Eigentümers zum manuellen Bestand: Eine manuelle Liste ersetzt das normale Lager, der Produktionsablauf bleibt derselbe wie beim Planen mit Lager. Bisher rechnete die Blueprint-Auflösung trotz Liste mit dem echten Lager; sie nutzt jetzt ebenfalls die Liste. Eigene BPO/BPC bleiben nutzbar, weil die Liste nur Mengen enthält (bestätigt vom Eigentümer). Im Auftrag festgelegt: Mengenziele des Lagers gelten für die Liste nicht.

## 31.10.2026: Verkaufswahl je Produkt im Kostenschritt

Entscheidungen des Eigentümers nach seinem ersten Test des Schrittplaners:

1. Die Tabelle in Schritt 4 zeigt je Produkt eine Zeile mit Kosten und bestem Verkauf; schlechtere Szenarien stehen nur im Auswahlmenü.
2. Produktionszwischensumme, Produktionskosten inklusive Lieferung und Kosten pro Item gelten bei mehreren Produkten je Produkt. Materialbeschaffung, Lagerverbrauch, BPC/BPO, Installation und Lieferung bleiben Gesamtwerte.
3. Der beste Verkauf ist als Vorschlag vorgewählt und änderbar.
4. Die Rentabilitätswarnung hängt am gewählten Verkauf. Das ändert die Regel vom selben Tag, die auf den besten möglichen Verkauf abstellte.
5. Schritt 8 bleibt Übersicht mit Szenario-Details und derselben, dort ebenfalls änderbaren Wahl.
6. Eigene Blueprints mit freien Runs müssen genutzt werden; die Warnung zu fehlenden Runs darf nur bei wirklich fehlenden Runs erscheinen.

Da der Eigentümer bei der Frage keine Präferenz angab, festgelegt: Gewählt wird Markt und Szenario, weil sonst der angezeigte Verkauf von dem abweichen könnte, was die Produktionsübersicht vermerkt. Eine Wahl ohne Szenario, also alle bestehenden Pläne und Zeilen, bleibt beim eingestellten Verkauf. „Trotzdem produzieren“ gilt für die Berechnung und die gesehenen Verkäufe samt Gewinn. Eingaben werden nie automatisch korrigiert; ein unbekannter Name wird nur gemeldet.

## 01.11.2026: Schritt 4 entscheidet, Schritt 8 schließt ab

Entscheidungen des Eigentümers nach dem Lauf mit Ark, Nomad und Rhea:

1. Schritt 8 ist nur noch der Abschluss: Zusammenfassung und Erfassen. Das ersetzt Punkt 5 der Entscheidung vom 31.10.2026. Die Details aller Verkaufswege stehen zugeklappt in Schritt 4.
2. Die Allianzeingabe wird eine Tabelle mit einer Zeile je Produkt, immer für alle Produkte. **Übernehmen** wählt den Allianzmarkt.
3. Einheiten sind mit der produzierten Menge vorausgefüllt, haben einen Zähler mit Pfeilen und können nicht größer als geplant eingegeben werden. Die Gebühr ist mit 2 % als überschreibbare Annahme vorausgefüllt.
4. Das Verkaufsmenü nennt geschlossen nur den Verkauf; der Gewinn steht in der Tabelle und im geöffneten Menü.
5. Warnungen stehen auf Deutsch, Fach- und EVE-Begriffe bleiben englisch. Die Warnungen zum Public-Contracts-Index und zu großen Produkten für Kurieraufträge erscheinen nur, wenn ein gewählter Verkauf betroffen ist.
6. Schritt 6 bekommt eine Gesamtliste aus fehlenden Items und Lagerverbrauch, ein Multibuy je Hub mit den dort günstigen Items. Die Wiederauffüllliste zieht von Schritt 5 nach Schritt 6.

Vom Eigentümer beauftragte Werteprüfung am gespeicherten Plan, nur lesend: Gesamtsummen stimmen; der EIV entspricht auf den ISK genau der Formel aus SDE und CCP-Adjusted-Prices. Das belegt die Rechnung, nicht die Gleichheit mit dem Marktwert: Die Adjusted Prices der Capital-Komponenten weichen stark vom Markt ab (etwa Faktor 0,03 bis 3,4), daher unterscheiden sich die Jobkosten der drei Schiffe viel stärker als ihr Materialwert. Der Abgleich mit dem EVE-Jobfenster durch den Eigentümer bestätigt die Jobkosten bis auf 0,0343 % (siehe `Documentation/ACCEPTANCE.md`). Korrigiert, ohne Änderung der Plansummen:

- Automatisch ermittelte Blueprint-Kosten trugen eine zufällige `requestID` und fielen deshalb auf den Materialanteil zurück. Sie folgen nun der gebauten Menge. Die dokumentierte Regel „beim nutzenden Produkt“ gilt damit erstmals tatsächlich.
- Die Lieferung wurde auch auf am Home Hub gekaufte Items verteilt. Sie folgt nun der Fracht der Kurierverträge.
- Kosten und Mindestpreis der Tabelle enthalten nun den Transport des gewählten Verkaufs.

Von Claude festgelegt, weil eine neutrale Verteilung die Rechenregel ändern würde: Lagerbestand geht weiter zuerst an die obere Produktzeile. Die Summe bleibt gleich, die Aufteilung hängt von der Reihenfolge ab, und Schritt 4 weist darauf hin. Das Allianzfeld des Einzelplans verliert das automatische Übernehmen beim Tippen zugunsten der einen Tabelle.

## 01.11.2026: Jobdauer mit Produktionscharakter und Implantaten

Entscheidungen des Eigentümers: Die Jobdauer berücksichtigt Charakter-Skills und Implantate. Der Charakter wird vor dem Berechnen in Schritt 3 gewählt, die Implantate werden manuell je Charakter eingestellt und nicht aus ESI gelesen.

Die Faktoren stammen aus den SDE-Effekten der Skills und Implantate. Für Ark, Nomad und Rhea ergeben Basiszeit, TE, Anlage, Industry V, Advanced Industry V und die zwei Science-Skills auf V genau die 861.105 Sekunden des EVE-Jobfensters.

Von Claude festgelegt: Ein Charakter gilt für alle Tätigkeiten des Plans, also auch dann, wenn der Zeitplan Slots mehrerer Charaktere nutzt. Eine Zuordnung je Slot wäre genauer, wurde aber nicht gewählt, weil der Eigentümer einen Charakter für die Produktion auswählen will. Vorbelegt ist der erste für Industrie aktivierte Charakter.

## 01.11.2026: Charakter je Produkt und Produzenten je Standort

Entscheidungen des Eigentümers, sie ersetzen den einen Produktionscharakter vom selben Tag:

1. Schritt 3 zeigt eine Tabelle der Produkte mit dem Charakter je Produkt, die Wahl wird gemerkt.
2. In den Industrieeinstellungen legt man je Struktur die Produzenten fest, ähnlich wie beim Refiner. Nur sie stehen im Plan zur Wahl.
3. Zwischenprodukte folgen dem Endprodukt, wenn dessen Charakter am jeweiligen Standort produziert, sonst gilt der erste Produzent des Standorts. Bei gemeinsamen Bauteilen zählt die oberste Zeile.

Von Claude festgelegt: Mehrere Zeilen desselben Produkts haben eine Tabellenzeile, weil der Planer sie zu einem Auftrag zusammenfasst. Erster Produzent heißt alphabetisch erster. Ohne Produzenten-Auswahl stehen alle Charaktere zur Wahl. Die gemerkte Wahl bleibt beim Zurücksetzen erhalten. Die Slot-Verteilung im Zeitplan bleibt unverändert.

## 01.11.2026: Charaktere und Implantate je Standort und Tätigkeit

Entscheidungen des Eigentümers, sie ersetzen die Produzentenliste je Struktur, die Implantate je Charakter und die unveränderte Slot-Verteilung vom selben Tag:

1. Implantate gelten je Standort, wie beim Refiner. Die Auswahl bei den Industrie-Charakteren entfällt.
2. Jeder Standort hat eine eigene Liste je Tätigkeit: Fertigung, Reaktionen sowie Kopieren und Forschung, jeweils nur wenn er das kann.
3. Bei Reaktionen steht ein Hinweis statt einer Auswahl, weil die SDE kein Implantat enthält, das sie verkürzt (geprüft in SDE-Build 3632936).
4. Der Zeitplan nutzt nur die Slots der am Standort festgelegten Charaktere. Ohne Festlegung gilt die bisherige Regel.

Von Claude festgelegt: Ein Haken allein schaltet keine Slots frei, die bleiben bei „Für Industrie verwenden“; ein festgelegter, nicht aktivierter Charakter wird in den Einstellungen markiert, und fehlen dem Standort dadurch alle Slots, warnt der Plan. Vorhandene Implantate werden beim Laden an jeden Standort kopiert, an dem der Charakter die passende Tätigkeit ausführen darf, ohne dortige Werte zu überschreiben. Eine alte Produzentenliste gilt für Fertigung, bei einem reinen Reaktionsstandort für Reaktionen. Auch die Aufteilung in Teilaufträge zählt nur die Slots der Festgelegten.

## 01.11.2026: Vergleichsmärkte als Einkaufsorte mit eigenem Transportweg

Entscheidungen des Eigentümers, sie erweitern die Einkaufsorte vom 30.10.2026:

1. Zur Wahl stehen die Hubs und die Vergleichsmärkte, nicht alle eingetragenen Märkte.
2. Der Transportweg jedes Vergleichsmarkts zum Home Hub wird in den Einstellungen festgelegt und berechnet.
3. Die Märkte gelten nur für den Einkauf, nicht als Verkaufsweg.

Von Claude festgelegt: Der Weg steht in den Logistik-Einstellungen und bietet Profile Courier oder Jump Freighter Service. Ein eigener Jump Freighter fehlt, weil Einkäufe bisher auch auf Hub-Strecken nicht mit ihm rechnen. Standard ist „Nicht festgelegt“, kein stiller Courier-Preis: Der Markt entfällt dann wie jeder Ort ohne Preis mit sichtbarer Warnung. Schritt 1 zeigt den fehlenden Weg mit Sprung in die Logistik. Ein Vergleichsmarkt am Ort eines Hubs erscheint nicht doppelt.

## 02.11.2026: Eigene Sell-Order – Planer zum besten Sell, Handel einen Preisschritt darunter

Entscheidung des Eigentümers aus der [App-Analyse](../ANALYSE_2026-11-02.md) (P-L4): Der Unterschied bleibt bewusst bestehen.

1. Planer und Hub-Chancen setzen den eingestellten Verkauf (eigene Sell-Order) zum niedrigsten aktiven Sell-Preis ohne Preisschritt an (Planer: `MarketPriceEngine`, Szenario `listedSale`; Hub-Chancen: bester Sell der Chancenrechnung).
2. Handel, die Vorbefüllung des Handelslogbuchs und der Lagerverkauf-Abgleich setzen die eigene Sell-Order einen gültigen Preisschritt unter den besten Sell (`MarketPriceTick.nextBelow`).
3. Dasselbe Item am selben Hub kann deshalb im Planer einen etwas höheren Verkaufserlös zeigen als im Handel. Rechenregeln ändern sich durch diese Entscheidung nicht.

## 04.11.2026: ESI-Parallelität – zwölf gleichzeitige Anfragen, automatische bleiben bei zwei

Entscheidung des Eigentümers aus der [App-Analyse](../ANALYSE_2026-11-02.md) (Prompt A5b).

1. Der gemeinsame `ESIRequestCoordinator` lässt höchstens zwölf HTTP-Anfragen gleichzeitig zu (vorher sechs). Automatische Arbeit belegt davon weiter höchstens zwei.
2. Die engeren Grenzen einzelner Dienste bleiben unverändert, etwa sechs Typabfragen je Marktabzug (`TradeHubMarketService`) und vier Seiten je mehrseitigem Abruf.
3. Grundlage: CCP nennt keine Höchstzahl gleichzeitiger Anfragen. Die Zahl der Anfragen ändert sich nicht, nur ihr zeitlicher Abstand. Fehlerlimit, Bucket-Limits, 420/429-Pausen und Cache-Regeln gelten unverändert.
4. Steigen in der Messung 420-, 429- oder 5xx-Antworten, wird auf sechs zurückgestellt. Messergebnis: [App-Analyse, Abschnitt 14](../ANALYSE_2026-11-02.md).
5. Gemessen am 05.11.2026: Das erste Laden im ersten Planer-Klick dauerte 5,0 s statt 14,3 s mit sechs am Vortag (8,4 s in A3); keine 4xx, 420 oder 429 im Klick. Die Grenze bleibt bei zwölf.

## 05.11.2026: Home- und Coalition-Hub-Scan laufen gleichzeitig

Entscheidung des Eigentümers aus der [App-Analyse](../ANALYSE_2026-11-02.md) (Prompt A6, G10).

1. Im Main-Hub-Scan starten Home- und Coalition-Analyse nach der Main-Analyse gleichzeitig (`SecondaryHubScan`), statt Coalition erst nach Home.
2. Grundlage: Jede Rolle hat eigenen Zustand, eigene Nachfrage-, Snapshot- und Bestandsdateien. Coalition braucht vom Home Hub nur dessen Konfiguration als Transport-Startpunkt. Der frühere Grund für die Reihenfolge, die Token-Erneuerung ohne Single-Flight, ist seit dem 23.10.2026 behoben.
3. Ein Abbruch beendet beide. Automatische Scans teilen sich weiter höchstens zwei automatische ESI-Anfragen.
4. Einzige sichtbare Abweichung: Schlägt das Speichern eines Bestandspunkts fehl, zeigt die gemeinsame Bestandsmeldung den Stand der zuletzt fertigen Rolle; vorher überschrieb Coalition stets Home.

## 07.11.2026: Oberflächenstil „New Eden HUD“ neben „Klassisch“

Entscheidungen des Eigentümers, Plan: [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md) (Prompt D1).

1. „Klassisch“ bleibt als gleichwertige Alternative vollständig erhalten. Die Auswahl „Oberflächenstil“ steht in den Allgemeinen Einstellungen (Panel „Farben“, über dem Farbschema) unter dem neuen Schlüssel `app.appearance.interface-style`. Standard ist „Klassisch“, bis D8 abgenommen ist; bestehende Einstellungen bleiben in jedem Fall erhalten.
2. „New Eden HUD“ läuft immer dunkel. Die Farbschema-Auswahl bleibt sichtbar, ist bei HUD gesperrt und zeigt den Hinweis „New Eden HUD ist immer dunkel“. Der gespeicherte Farbschema-Wert bleibt unverändert und gilt wieder in „Klassisch“.
3. Der gemeinsame Panel-Baustein deckt genau zwei heutige Varianten ab: A, das gemeinsame `Panel` mit Schatten, und B, handgebaute Panels mit gleicher Fläche und gleichem Rahmen ohne Schatten. Kleine Karten (Radius 6), Unterkarten auf `elevated`, Sonderformen (Handel mit Verlaufsleiste, schwebendes Planer-Info-Panel, Warnkarte) sowie Tabellenköpfe und -zellen bleiben in beiden Stilen unverändert, bis ein späterer D-Schritt sie ausdrücklich behandelt.
4. Im HUD bleiben Fläche, Rahmen, Radius und Schatten je Variante wie heute; hinzu kommen nur Eckwinkel und Titel-Raute.
5. Das bestehende `Panel` nutzt den Baustein schon ab D1. Ansichtsdateien bleiben dafür unberührt, „Klassisch“ zeichnet unverändert.

Von Claude festgelegt: Unter der Auswahl steht ein kurzer Satz zu beiden Stilen; der HUD-Hinweis nennt zusätzlich, dass das gewählte Farbschema gespeichert bleibt. Die Platzierung im Panel „Farben“ hat der Eigentümer nicht ausdrücklich bestätigt.

## 07.11.2026: HUD-Rahmen – Seitenkopf als Bereichszeile, macOS-Auswahl bleibt

Entscheidungen des Eigentümers zu Prompt D2 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Der Seitenkopf im HUD ist wie auf den Boards eine Bereichszeile mit 6-pt-Raute direkt über dem vorhandenen Titel (z. B. „◆ ÜBERSICHT“ über „Dashboard“), keine eigene Kopfzeile „Bereich › Ansicht“. In „Klassisch“ erscheint sie nicht.
2. Die Bereichszeile kommt schon in D2 in alle Ansichten. Alle 19 Bereiche haben heute einen Titel; Daten & Einstellungen zeigt sie über dem Titel jeder Unterseite.
3. Die Auswahl in der Seitenleiste behält die macOS-Markierung. Die cyanfarbene Markierung der Boards wird nicht übernommen.
4. Farbschema-Fehler sofort beheben: Nach HUD → „Klassisch“ und schon vorher nach Dunkel → System blieb die App bis zum Neustart dunkel, weil SwiftUIs `preferredColorScheme` auf macOS eine erzwungene Darstellung bei `nil` nicht zurücksetzt. Das Farbschema wird deshalb über `NSApp.appearance` gesetzt (`AppAppearanceApplier`): Hell → Aqua, Dunkel und HUD → Dark Aqua, System → keine Vorgabe.

Von Claude festgelegt: Die Gruppen und ihre Reihenfolge stehen in `NavigationGroup` (`ContentView.swift`); innerhalb einer Gruppe gilt die bisherige Reihenfolge, sie entspricht dem Plan. Die Symbole bleiben SF Symbols statt der Board-Linienicons. Gruppentitel nutzen den Stil der Panel-Titel ohne Raute; Einzug und Abstände der Gruppentitel bestimmt die macOS-Seitenleiste.

## 07.11.2026: HUD-Übersicht – App-Anordnung und App-Texte bleiben

Entscheidungen des Eigentümers zu Prompt D3 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Dashboard: Die Anordnung des Boards `Main.dc.html` (Kennzahlenreihe, Jobliste, Wallets, Nettowert-Verlauf, Main-Hub-Chancen Top 5, „ESI aktuell“ und Aktualisieren im Kopf) wird nicht übernommen. Abschnitte, Panels, Reihenfolge und Texte der App bleiben.
2. Nettowert: Die App-Texte „Bekannter Nettowert“ bzw. „Gesamtnettowert“ und die Änderung ohne Zusatz bleiben; „· heute“ und „ggü. gestern“ aus dem Board entfallen, weil die vorherige Momentaufnahme nicht von gestern sein muss.
3. Nettowert: „EVE-Typen ohne Preis“ wird kein eigener Block in der Summenkarte; Hinweis in der Bestandteil-Karte und Popover bleiben.

Von Claude festgelegt: Die Raute vor Panel-Titel und Bereichszeile sitzt als Overlay vor dem Text, damit Grundlinien-Ausrichtungen neben dem Titel im HUD erhalten bleiben (optisch wie zuvor).

## 07.11.2026: HUD-Planer – App-Aufbau bleibt, Info-Panel mit Eckwinkeln

Entscheidungen des Eigentümers zu Prompt D4 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Der Aufbau des Boards `Planer.dc.html` (Auftrag, Ergebnis, Produktionsbaum, Verkaufswege, Titel „Planer“, Preisstatus und „In Produktionsübersicht übernehmen“ im Kopf) wird nicht übernommen. Assistent mit Schritten 1–8, Texte und Knöpfe der App bleiben.
2. Das Info-Panel „So rechnet der Planer“ (Sonderform) bekommt im HUD die Eckwinkel; Fläche, Rahmen und Schatten bleiben. Erklärkarte mit Amber-Rahmen und Schrittkästchen bleiben unverändert. In „Klassisch“ ändert sich nichts.

## 07.11.2026: HUD-Industrie und Chancen – App-Anordnung bleibt, Eckwinkel an Sonderflächen

Entscheidungen des Eigentümers zu Prompt D5 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Die Anordnung der Boards `Reaktionen.dc.html`, `Bauplaene.dc.html`, `Produktion.dc.html` und `Chancen.dc.html` wird nicht übernommen. Anordnung, Spalten und Texte der App bleiben, auch die Kennzahlkarten der Reaktionen, die Hinweiszeilen der Produktionsübersicht sowie Filterdeck, Analysegrundlage und Rechner der Hub-Chancen.
2. Hub-Chancen (eine Ansicht für Main, Home und Coalition Hub): Filterdeck und Analysegrundlage (kleine Karten, Radius 6) und der Rechner (Radius 2, Akzent-Kopfleiste) behalten Form, Radius und Kopfleiste. Im HUD kommen Eckwinkel dazu, die dem jeweiligen Radius folgen.
3. Baupläne: Suche, BPO/BPC-Filter und Liste bleiben ohne Panel; die Geometrie ist in beiden Stilen gleich.
4. Produktionsübersicht: Der mit der Akzentfarbe gefüllte Tabellenkopf bleibt in beiden Stilen; nur der Tabellenrahmen nutzt den Baustein.

Von Claude festgelegt: Die Kennzahlkarten der Reaktionen und der Tabellenrahmen der Produktionsübersicht (Variante B) zeichnen über `nexusPanelSurface(.flat)`. Die Ergebniszeilen der Reaktionen (Unterkarten auf `elevated`) bleiben wie im Board ohne Eckwinkel.

## 07.11.2026: HUD-Markt I – App-Anordnung bleibt, Eckwinkel an Handelskacheln

Entscheidungen des Eigentümers zu Prompt D6 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Die Anordnung der Boards `Handel.dc.html`, `Logbuch.dc.html`, `Marktbestand.dc.html` und `Lagerverkauf.dc.html` wird nicht übernommen. Anordnung, Sheets (Item-Verlauf des Marktbestands, Logbuch-Editor), Spalten, Texte, sortierbare Tabellenköpfe und der Zeilen-Cache aus A4 bleiben.
2. Handel: Die Handelskacheln (Sonderform: Panel-Fläche mit Radius 10 ohne Rahmen und Schatten, oben 3-pt-Verlauf) behalten Fläche, Verlaufsbalken und Titel. Im HUD kommen Eckwinkel dazu.
3. Marktbestand: Hub-Auswahl, Suche, Marktgruppe, Tabelle und das Item-Verlauf-Sheet bleiben ohne Panels; die Geometrie ist in beiden Stilen gleich.

Von Claude festgelegt: Handelslogbuch und Lagerverkauf-Abgleich nutzten bereits ausschließlich `Panel` und bleiben unverändert; der Logbuch-Editor bleibt ein natives Formular-Sheet.

## 07.11.2026: HUD-Markt II und Assets – App-Anordnung bleibt, Listenkarten ohne Eckwinkel, Export unverändert

Entscheidungen des Eigentümers zu Prompt D7 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Die Anordnung der Boards `Vertraege.dc.html`, `Moonkauf.dc.html`, `Mineralkauf.dc.html`, `Gegenstaende.dc.html` und `Lager.dc.html` wird nicht übernommen. Anordnung, Dialoge (macOS-Sichern-Dialog statt Board-Exportdialog), Spalten, Texte und Sortierung der App bleiben.
2. Karten in Listen – Ergebniskarten der öffentlichen Verträge und Standortkarten in Alle Gegenstände/Lager – bleiben in beiden Stilen wie bisher und bekommen keine Eckwinkel. Eckwinkel tragen nur Panels.
3. Das aufklappbare Panel „ESI-sichere Synchronisierung“ nutzt den Baustein und den Panel-Titel; im HUD stehen Eckwinkel und, wie bei allen Panel-Titeln, eine Raute (das Board zeigt dort keine).
4. Der PNG-Export der Moon-/Mineralien-Kaufanalyse liefert in beiden Stilen und jedem Farbschema dasselbe dunkle Bild im heutigen Aussehen, ohne HUD-Elemente.

Von Claude festgelegt: Die Warnkarte zum Erstimport der Verträge (Sonderform mit rotem Rahmen) bleibt wie im Board ohne Eckwinkel. Der Export rendert über `MaterialPurchaseImageExportRenderer` und setzt dort ausdrücklich den Stil „Klassisch“.

## 07.11.2026: HUD-Abschluss – Einstellungen unverändert, „Klassisch“ bleibt Standard

Entscheidungen des Eigentümers zu Prompt D8 aus [DESIGN_HUD_2026-11-07.md](../DESIGN_HUD_2026-11-07.md).

1. Daten & Einstellungen: Alle sechs Unterseiten nutzen bereits den Panel-Baustein. Navigationsleiste, Unterkarten (Transportstrecken, Routen, Aktivitätssysteme, Strukturen) und kleine Karten (Servicemodule, Rigs) bleiben in beiden Stilen gleich.
2. „Klassisch“ bleibt Standard für neue Installationen. Keine Migration; über den Standard wird nach der Abnahme mit echten Daten neu entschieden.

## 07.11.2026: Market Browser vollständig entfernt

Entscheidung des Eigentümers nach der Nutzungsprüfung vom 07.11.2026 (Stufe A und B).

1. App: `MarketBrowserView` war seit dem 26.09.2026 (`4020a14`) nirgends mehr eingebunden. Ansicht, Sortierspalten `MarketOrderSortColumn`, die zugehörigen `RuntimeState`-Teile (Browser-Zustand, Abruf, Strukturnamen-Auflösung, `searchMarketTypes`) und 47 nur dort genutzte Übersetzungsschlüssel je Sprache sind entfernt.
2. Core: `MarketBrowserService` sowie `MarketBrowserOrder`, `MarketBrowserRegionFailure`, `MarketBrowserSummary`, `MarketBrowserSnapshot` und `MarketBrowserFilter` sind entfernt. Damit entfällt die nur dort genutzte Rechenregel `eve-tycoon-five-percent-2026-08-01`; vier Tests, die nur diese Teile prüften, sind entfernt.
3. Bleibt: `MarketSecurityBand` nur noch als Hülle für `eveDisplayStatus` (genutzt in den Profilen) mit dessen Rundungstest; die nur vom Filter genutzte Einteilung `resolved` samt Fällen ist entfernt (Nachtrag auf Eigentümerwunsch). `ManufacturingOpportunitiesView` in derselben Datei ist unverändert.

## 07.11.2026: Planer ohne Umschalter Einzel-/Sammelproduktion

Entscheidung des Eigentümers: Die Unterscheidung ist überflüssig, weil Ablauf und Rechnung für ein und für mehrere Produkte gleich sind. Das ersetzt den Umschalter aus Punkt 3 der Entscheidung „Planer in Schritten, Rentabilität und Sammelproduktion“ vom 31.10.2026. Gemeinsame Rechnung, Tabelle je Produkt und Entfernen bleiben.

1. Befund: `PlannerProductionMode` sperrte nur in Schritt 2 „Weiter“, wenn bei Einzelproduktion mehrere Produkte eingegeben waren. Die Rechnung erhielt nur den Eingabetext; Schritt 4 bis 8 richten sich nach der Zahl der Produkte im Plan.
2. Schritt 2 nimmt ein oder mehrere Produkte an. Umschalter, Hinweis „Zur Sammelproduktion wechseln“, das Enum und sein Test sind entfernt. Rechenregeln unverändert.
3. Von Claude festgelegt: Der UserDefaults-Schlüssel `planner.production-mode` wird nicht mehr gelesen, aber weder gelöscht noch umbenannt. Ein gespeicherter Wert bleibt wirkungslos liegen.

## 07.11.2026: Dashboard nach Board „Main.dc.html“ – ersetzt D3 Nr. 1

Entscheidungen des Eigentümers, Plan: [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md).

1. Das Board `Main.dc.html` wird die grundlegende Anordnung des Dashboards, in „Klassisch“ und „New Eden HUD“; HUD-Akzente nur im HUD. Das ersetzt Nr. 1 der Entscheidung „HUD-Übersicht – App-Anordnung und App-Texte bleiben“ (D3). Nr. 2 und 3 dort (Nettowert-Ansicht) gelten weiter. „Klassisch“ bleibt Standard.
2. Alle heutigen Dashboard-Funktionen bleiben. App-Panels ohne Board-Gegenstück kommen ins Board-Raster, Reihenfolge „Industrie zuerst“: Top 5 nach Materialwert | negative Reaktionen, Mineralpreise, Moon- | Mineralien-Kauf. Die Kapazität je Aktivität wird aufklappbar unter der Kennzahlenreihe (DB4).
3. „Bereit zur Auslieferung“ und „Nächste 48 Stunden“ werden die Liste „Industriejobs · bereit und bevorstehend“: erst bereite Jobs nach Endzeit, dann laufende mit Ende in 48 Stunden nach Endzeit; fünf Zeilen plus „Alle anzeigen“; Zeileninhalt wie bisher.
4. Board-Panels tragen Board-Titel, der Untertitel kommt aus dem Board; übrige Panels und Hinweise behalten App-Texte. Die drei Abschnittsüberschriften entfallen.
5. Neu aus dem Board: Kennzahlenreihe; Seitenkopf mit ESI-Status über Charakter-Sync, Wallets, Nettowert sowie Moon-, Mineralien- und Reaktionsanalyse und „Alles aktualisieren“, das auch diese drei Analysen aktualisiert; Main-Hub-Chancen · Top 5 nach ROI mit den gespeicherten Filtern und der Kostenrechnung der Chancen-Ansicht (Spalten Produkt, ROI, Gewinn); Nettowert-Zeitraum 7/30/90/Alle (Start 30 T, Sitzung), Veränderung = letzter minus erster bekannter Gesamtwert im Zeitraum.

Von Claude festgelegt (DB1): Panels einer Rasterzeile werden gleich hoch gezogen wie im CSS-Raster des Boards. Die Kachel „Charaktere“ der Wallets zeigt „einbezogen von gesamt“, damit die bisherige Angabe erhalten bleibt. Bis DB2 nimmt der Nettowert-Verlauf seine Zeile allein ein; bis DB4 steht „Industriekapazität“ über dem Raster.

## 07.11.2026: Dashboard DB2 – Main-Hub-Chancen · Top 5

Entscheidungen des Eigentümers zu Prompt DB2 aus [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md).

1. Das Dashboard rechnet die Top 5 selbst, mit denselben Funktionen wie die Main-Hub-Chancen: gespeicherte Filter, Lager, Mindestbestände, Planreservierungen, Vertrags-, LP-Store- und Erfindungsangaben, Kostenblatt. Runs, ME und TE, die man in der Ansicht je Zeile nur für die Sitzung ändert, werden nicht gespeichert und gelten im Dashboard nicht; dort gelten die Scanwerte.
2. Leerzustände: ohne Scan „Noch kein Main-Hub-Scan“ wie in der Ansicht; schließen die Filter alles aus, „Keine Chance passt zu den Filtern der Main-Hub-Chancen.“ Keine eigene Veraltet-Regel, weil die App keine kennt; die Zeit des Marktstands steht im Panel.
3. Unter dem Titel stehen Hub-Name (kopierbar) und „Aktualisiert …“ mit Datum und Uhrzeit des Marktstands, wie im Kopf der Ansicht.
4. „Gewinn“ ist die Spalte „Gewinn“ der Ansicht (Erlös minus Verkaufssteuer, Maklergebühr und Gesamtkosten), auf der auch der ROI beruht.

Von Claude festgelegt: Bleiben nach den Filtern Zeilen, aber keine mit ROI, steht „Keine sichtbare Chance hat einen verfügbaren ROI.“ statt des Filtersatzes. Die Spaltenköpfe sortieren die fünf Zeilen (Start ROI absteigend); fehlende Werte stehen aufsteigend hinten, absteigend vorn, letzter Schlüssel ist die Type-ID. Werte erscheinen im Format der Ansicht („—“ für fehlend). Die Speicherschlüssel der Filter stehen jetzt als Konstanten in `ManufacturingOpportunitySettingKey`; Werte und Schlüssel bleiben gleich.

## 07.11.2026: Dashboard DB3 – Nettowert-Zeitraum und Veränderung

Entscheidungen des Eigentümers zu Prompt DB3 aus [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md).

1. Die Verlaufslinien je Charakter im Dashboard folgen dem gewählten Zeitraum wie das Hauptdiagramm.
2. Ist der erste oder letzte verglichene Stand unvollständig bewertet, wird die Veränderung aus den bekannten Gesamtwerten gerechnet und gelb mit „aus bekannten Bestandteilen“ gekennzeichnet.
3. Die Veränderung steht dauerhaft im Panel „Nettowert · Verlauf“; ab DB4 zeigt sie zusätzlich die Kennzahl „Nettowert“.
4. Die Stufen der gemeinsamen Zeitraumwahl werden übersetzt: Deutsch „7 T“, „30 T“, „90 T“, „Alle“, Englisch „7D“, „30D“, „90D“, „All“. Das gilt auch in der Nettowert-Ansicht.

Von Claude festgelegt: „Unvollständig“ heißt `isComplete == false` des Stands, wie bei der Kennzeichnung „Bekannte Bestandteile“ im Dashboard. Die Prozentangabe entfällt, wenn der Ausgangswert nicht positiv ist; dann steht nur der ISK-Betrag. Eine Veränderung von genau 0 erscheint grün mit Pfeil nach oben, wie die Tagesänderung der Nettowert-Ansicht. Zeitraumwahl und Veränderung stehen in einer Zeile über der Serienwahl und rücken bei Platzmangel untereinander.

## 07.11.2026: Dashboard DB4 – Kennzahlenreihe

Entscheidungen des Eigentümers zu Prompt DB4 aus [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md).

1. In den Karten „Fertigungs-Slots“ und „Gemeinsame Science-Slots“ belegen laufende (auch pausierte) und fertige, noch nicht ausgelieferte Jobs einen Slot. Hauptzahl = belegt / Kapazität, darunter „N bereit · M frei“ mit frei = Kapazität − belegt. Das Aktivitätsraster bleibt bei laufenden Jobs.
2. Der Info-Knopf der Karte „Nettowert“ zeigt den vorhandenen Text „Bewertungsdetails“ als Popover; der aufklappbare Bereich im Panel bleibt.
3. Der Aufklappzustand von „Kapazität je Aktivität“ wird unter dem neuen Schlüssel `dashboard.capacity-by-activity-expanded` gespeichert, anfangs zugeklappt.
4. Die Gesamtzeile „X von Y verfügbaren Job-Slots aktiv“ mit „Unvollständig“ steht im Kopf von „Kapazität je Aktivität“, auch zugeklappt.

Von Claude festgelegt: Der Balken erscheint nur bei vollständig bekannter, positiver Kapazität; bei Teilkapazität stehen Kapazität und frei mit „≥“, ohne Kapazität „—“; frei wird nie negativ. Die Nettowert-Karte zeigt die Veränderung kurz als Prozent (ohne positiven Ausgangswert in ISK) mit „im Zeitraum“ und demselben gelben Kennzeichen wie das Panel. Die Karten heißen „Nettowert“, „Wallet“, „Fertigungs-Slots“ (vorhandene App-Texte) und „Gemeinsame Science-Slots“ (Board-Text, neuer Schlüssel, weil „Shared science slots“ in den Aktivitätskarten anders übersetzt ist). Nur die Slot-Karten und der Kapazitätsbereich folgen dem Minutentakt. Der nicht mehr genutzte Schlüssel „Industry capacity“ ist entfernt.

## 08.11.2026: Dashboard DB5 – Seitenkopf mit ESI-Status und „Alles aktualisieren“

Entscheidungen des Eigentümers zu Prompt DB5 aus [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md).

1. Die Zeit am ESI-Status ist die der ältesten der sechs Quellen (Charakter-Sync, Wallets, Nettowert, Moon-, Mineralien-, Reaktionsanalyse).
2. Die Erfolgs- und Fehlermeldungen der Aktualisierung stehen in einer Zeile unter dem Seitenkopf, nicht mehr im Wallet-Panel.
3. „Alles aktualisieren“ startet nach Charakter-Sync und Nettowert-Bewertung die drei Analysen gleichzeitig.
4. Ein Klick auf den Status öffnet ein Popover mit den Einzelzuständen der sechs Quellen.

Von Claude festgelegt: Der Gesamtstatus ist „Wird aktualisiert“, sobald eine Quelle läuft; sonst gilt `StartupDataStatusProjector.combined`. Eine Quelle, die noch nie geladen wurde („Wartet“), zählt dabei als fehlend; nur wenn alle warten, heißt der Status „Wartet“. Ein fehlgeschlagener neuerer Nettowert bei sichtbarer älterer Bewertung gilt als „Veraltet“. Je Quelle zählt ihre älteste Zeit: ältester Charakter- bzw. Wallet-Sync, Zeitpunkt der Bewertung, Stand der Analysen. Für den Charakterzustand gilt das Ergebnis der letzten Aktualisierung im Dashboard, sonst das des Programmstarts. Der Knopf ist zusätzlich ohne Charaktere gesperrt (bisher war er dann nicht erreichbar). Die Analysen laufen wie die Aktualisieren-Knöpfe ihrer Panels ohne Konfigurationsprüfung. Der nicht mehr genutzte Schlüssel „Refresh dashboard“ ist entfernt.

## 08.11.2026: Dashboard DB6 – Gesamtdurchsicht und Abnahme-Checkliste

Prompt DB6 aus [DASHBOARD_BOARD_2026-11-07.md](../DASHBOARD_BOARD_2026-11-07.md); keine Änderung an Code oder Rechenregeln.

Von Claude festgelegt:

1. Befunde der Durchsicht werden in DB6 nicht behoben, sondern im Plan, Abschnitt 7.3, mit Herkunft („neu“ durch DB1–DB6 oder „alt“ vor DB1) und Vorschlag festgehalten; DB7 setzt nur um, was der Eigentümer freigibt.
2. Die synthetischen Testdaten entstehen mit den Codable-Typen von `EVENexusCore` als SQL für einen frischen isolierten Speicher (zwei erfundene Piloten, keine Tokens, kein SDE); die isolierte App läuft ohne Netzzugang, damit keine Live-Abfrage an ESI geht.
3. Kopierbare Namen werden nur über die Bedienungshilfen gelesen, nicht angeklickt, damit die Zwischenablage des Eigentümers unverändert bleibt. Das Kopieren per Klick steht in der Checkliste als Eigentümerprüfung.

Entscheidungen des Eigentümers (08.11.2026) zu DB7:

1. DB7 setzt alle Befunde B1 bis B10 aus Abschnitt 7.3 um.
2. B9: Im Dashboard heißt es einheitlich „Wissenschafts-Slots“, wie im Planer.
3. B8: Das Aktualisieren-Symbol steht in den Panels Mineralienpreise, Moon-Kauf und Mineralien-Kauf hinter „Einkaufsanalyse öffnen“.
4. B5: ISK-Beträge folgen dem Standardformat der App-Sprache wie in den Marktansichten (Englisch „ISK 2,097,354,121“, Deutsch „2.097.354.121 ISK“).
