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
  aktuell berechneten Plan.
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
