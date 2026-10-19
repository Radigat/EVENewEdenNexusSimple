# Fachlicher Konsolidierungs-Checkpoint – 25.09.2026

Projekt: **EVE New Eden Nexus - Assets, Industry, Markets**. Standardmodell: **Astra Medium**.
Genau ein aktiver Projektordner: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.
Branch: `consolidation/2026-09-25-single-source`; Ausgangs-HEAD `182f1a936950632bc84641904150c4c3e7782a55`.
Dieser Nachweis gehört zum anschließenden lokalen fachlichen Checkpoint. Dessen endgültige ID steht
im Git-Protokoll und im Abschlussbericht; es wird kein Push und keine Historienumschreibung durchgeführt.

> Hinweis 19.10.2026: Fertigungsprojekte, Reservierungen und Einkaufsbudget/-fortschritt wurden auf
> Eigentümerentscheid entfernt. Die zugehörigen Nachweise unten sind Historie dieses Checkpoints, kein
> aktueller Funktionsumfang ([DECISIONS.md](DECISIONS.md)).

## Prüfergebnis des aktiven Stands

| Prüfung | Ergebnis |
| --- | --- |
| SwiftPM Hauptprojekt | **451 bestanden**, 1 optionaler Real-SDE-Test übersprungen, 0 Fehler |
| Separates EVEStaticDataKit | **7 bestanden**, 1 optionaler Real-SDE-Test übersprungen, 0 Fehler |
| Nativer Xcode-Debugbuild | Erfolgreich; anschließend auch im abschließenden Test-Aufruf vollständig gebaut |
| Native Core-Tests | **415 bestanden**, 1 optionaler Real-SDE-Test übersprungen, 0 Fehler |
| Neue Konsolidierungstests | 22 Kernverträge, 8 direkt adaptierte CSV-Parser-Tests, 4 App-/Migrationstests |
| Quelldateizuordnung | 56/56 Core-, 27/27 App- und 23/23 Core-Testquellen im bestehenden Xcode-Projekt |
| Projektstruktur | Ein App-Target, ein aktives Xcode-Projekt; vorhandene SwiftPM-Module und lokales Kit erhalten |
| Dateiverweise | Keine fehlenden Xcode-Dateien; lokale Dokumentlinks und aktive Symlinks geprüft |
| Archive | Alle inventarisierten 158 + 158 + 733 Dateien unverändert; SHA256 gegen ursprüngliches Inventar geprüft |
| Git | Änderungen auf dem bestehenden Konsolidierungsbranch; `git diff --check` fehlerfrei |

SwiftPM: 407 ausgeführte Core-Swift-Testing-Fälle + 25 App-Swift-Testing-Fälle + 19 XCTest-Fälle.
Der Core-Runner zählt 408 einschließlich des übersprungenen Real-SDE-Falls. Native Tests sind dieselben
407 Core-Fälle plus acht Parser-XCTest-Fälle; nicht nochmals als zusätzliche eindeutige Tests addieren.
Ein parametrisierter Test hat fünf Ausführungen; Xcode nennt deshalb auf Geräteebene vier Ausführungen
mehr als in seiner maßgeblichen Testfall-Gesamtsumme. Gegenüber der organisatorischen Baseline sind
34 zusätzliche Testfälle vorhanden. Das Kit wurde unverändert separat geprüft.

## Gezielte Nachweise

- Bestehende Fachrechner und Regressionen laufen weiterhin. Konkrete Copying-Voraussetzungen erhöhen
  nur ihre zusätzlichen Zeiten; bestehende Material- und Fertigungswerte bleiben im Vergleich identisch.
- Projektidentitäten, unabhängige Entwürfe, Duplikate ohne Reservierungen, Archivsperre und Wiederherstellung;
  neue Initialisierung ist wiederholbar ohne Doppelanlage.
- Echte synthetische SwiftData-V2-Datei wird nach V3 geöffnet. Produktionsnummer, UUID, Zeitangaben,
  Snapshot-Bytes, präzise historische Beträge, fehlende Werte und manuelle Verkäufe bleiben erhalten.
- Wiederherstellung eines verifizierten V2-Backups nach absichtlich unvollständigem V3-Arbeitsdatenpayload;
  anschließend erfolgreiche erneute Migration/Initialisierung. Vorheriger Zustand und zusätzliche Sicherung
  bleiben erhalten. Das ist ein gezielter Unterbrechungsfall, keine Behauptung über jeden Hardwarefehler.
- SQLite-Sicherung mit WAL, vollständiger Prüfsummenvergleich, vorbereitete Wiederherstellung,
  manipulierte Sicherung und fremde Datenfamilie.
- CSV-Encoding/Trennzeichen/Quotes, ungültige und doppelte Zeilen, Überlauf, Ersetzen/Überspringen,
  ausdrücklich ausgelassene Fehler, Importbericht und abgelaufene Vorschau.
- Projektübergreifende Reservierungen, Schutzmengenadapter, Mengenlimits, Prioritätskonflikte,
  Teilverbrauch/Freigabe ohne Lageränderung und unveränderte Daten bei veralteter Vorschau.
  Ohne ESI gerechnete Pläne bleiben bei manuellen Quellen; neue ESI-Reservierungen verlangen frische Bestände.
- Preisgültigkeit, fehlende Preise, Budget-Ersatzwerte, Einkaufsfortschritt und Export.
- Konkrete Copying- und Forschungsversorgung, bestehende Invention-Wahrscheinlichkeits-/Konfidenztests
  sowie blockierte unvollständige Wissenschaftseingaben.
- Teilverkäufe, Mengenobergrenzen, doppelte Belege, exakte Beträge; ein Journalbetrag von 100 Cent über
  drei Einheiten wird auf 33, 33 und 34 Cent verteilt. Belege sind unabhängig von Charakterdatensätzen gespeichert.
- Vorschautexte stammen aus dem eingefrorenen, geprüften Zielstand und zeigen konkrete Lager, Limits,
  Beträge, Preise, Kauf-/Reservierungsmengen und Belegzuordnungen.

Testquellen: [Kernverträge](../../Tests/EVENexusCoreTests/ConsolidationTests.swift),
[Parserfälle](../../Tests/EVENexusCoreTests/ConsolidationCSVParserTests.swift),
[Migration und Speicherung](../../Tests/EVENexusSimpleAppTests/ConsolidationPersistenceTests.swift).

## Isolierte Bedienprüfung

Der native Build wurde über macOS mit `EVE_NEXUS_APPLICATION_SUPPORT_ROOT=/private/tmp/eve-functional/ui-data`,
eigener Preferences-Suite und `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1` geöffnet.
Kein produktiver Store wurde migriert oder als Testbestand genutzt; die installierte Alt-App blieb erhalten.
Geprüft wurden:

- damalige Navigation und Planner-Einstieg **Projekte & Einkauf**;
- Anlegen eines Testprojekts und manuellen Lagers sowie deren Erhalt nach Neustart;
- konkrete Vorschau mit Lagerauswahl, Mengenlimit und 120,50 ISK Kostenersatz, Bestätigung und Rückkehr;
- blockierte Bestandserfassung ohne installierten SDE-Katalog und blockierter Wissenschaftsauftrag ohne Voraussetzungen;
- vorhandenes Produktionsbuch und erreichbare Verkaufsbeleg-Eingaben;
- Sicherungsdialog: Testbestand als `.nexusbackup` erstellt und vollständig geprüft;
- kompakte Dialogdarstellung, scrollbare Formulare und vorhandene sortierbare Tabellenköpfe.

Die Prüfung des damaligen Sicherungsdialogs und des Einstiegs **Projekte & Einkauf** ist historische
Evidenz für die Funktionen. Der aktuelle Planner enthält Projektwahl und -einstellungen direkt,
Reservierungen bei der Lagerverwendung sowie Einkaufsbudget und -fortschritt bei der Einkaufsliste.
Sicherung liegt unter **Daten & Einstellungen → Allgemein**, Preisprofile unter
**Daten & Einstellungen → Markteinstellungen**. Für diese Verlagerungen wird keine erneute visuelle
Eigentümerabnahme behauptet.

Beim Sichttest gefundene zu allgemeine Vorschautexte und die technische Meldung bei fehlendem Katalog wurden
korrigiert. Bereichswechsel verwerfen die vorige ungespeicherte Vorschau und entfernen veraltete Fehlermeldungen.
Das ist ein Bedien-Smoketest, keine vollständige Eigentümer-, VoiceOver- oder Live-Abnahme mit echten Beständen.
Der direkte Start unter zusätzlicher Netzwerksperre wurde von der UI-Automation nicht erkannt; die
Bedienprüfung erfolgte anschließend über den regulären macOS-Start mit isolierten Daten. Automatische
Hintergrunddienste blieben abgeschaltet; bestehende öffentliche Statusanzeigen sind kein Live-Abnahmenachweis.

## Reproduzierbare Prüfungen und lokale Belege

Werkzeuge: Xcode 27.0 (27A266a), Swift 6.4, macOS arm64. Hauptpaket:

```sh
EVE_NEXUS_APPLICATION_SUPPORT_ROOT=/private/tmp/eve-functional/test-data \
EVE_NEXUS_USER_DEFAULTS_SUITE=com.local.EVENexusSimple.consolidation-tests-20260925 \
EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1 \
swift test --disable-sandbox --scratch-path /private/tmp/eve-functional/build
```

Kit separat mit `swift test --disable-sandbox --package-path Packages/EVEStaticDataKit
--scratch-path /private/tmp/eve-functional/kit-build`.

```sh
xcodebuild -project EVENexusSimple.xcodeproj -scheme EVENexusSimple \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/eve-functional/native \
  -resultBundlePath /private/tmp/eve-functional/verified-checkpoint.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

Bei Wiederholung einen neuen Ergebnisordner wählen. Protokolle liegen lokal unter
`/private/tmp/eve-functional/tests-final.log`, `kit-tests.log`, `native-build.log` und
`checkpoint-tests.log`; natives Ergebnis `verified-checkpoint.xcresult`.
Die App liegt unter `/private/tmp/eve-functional/native/Build/Products/Debug/EVE New Eden Nexus - Assets, Industry, Markets.app`.
Diese temporären Belege sind keine zweite aktive Projektquelle und keine produktive Installation.

Ein zwischenzeitlicher unisolierter SwiftPM-Aufruf scheiterte an macOS-Metadaten im vorhandenen `.build`
beim Signieren eines Ressourcenbundles. Der dokumentierte getrennte Scratch-Pfad vermeidet dieses
Umgebungsproblem; der vollständige finale Lauf ist erfolgreich. Xcode meldet lediglich die ausgelassene
AppIntents-Metadatenextraktion, da das Projekt diese Funktion nicht verwendet.

## Herkunft, Dubletten und Dateiumfang

[Funktionsvertrag](FUNCTIONAL_CONSOLIDATION.md), [Feature-Zuordnung](FEATURE_COVERAGE.md),
[ursprüngliche Entscheidungen](DECISIONS.md), [Archivpfade](archive-locations.json) und
[Dubletteninventar](duplicate-inventory.json) dokumentieren die Übernahmen.
Die alten Simple-/Nexus-Arbeitsordner sowie das Vollbackup vom 23.09.2026 bleiben unverändert archiviert.
153 Backup-Dateien waren identisch; fünf Varianten wurden begründet zugunsten der vollständigen
aktuellen Basis aufgelöst. Die zusätzliche Simple-Projektdatei und neun nummerierte Nexus-Projekte
bleiben Archivmaterial. Der aktive Dateiumfang steht in [FUNCTIONAL_FILES.json](FUNCTIONAL_FILES.json).

Alle acht Steuerdokumente, Komponenten-/Konfliktzuordnung und Entwicklungstagebuch wurden aktualisiert.
Zuletzt wurden auch alte sichtbare Produktnamen in den deutschen und englischen Berechtigungserklärungen
vereinheitlicht. Unverändert bleiben technische Module, Bundle-ID, Datenpfade, Keychain und Callback.
Begründete Ausnahmen: [LEGACY_NAMES.md](LEGACY_NAMES.md).

## Offene Grenzen

Keine offenen Fehler aus Build, aktiven Tests, Dateizuordnung oder dem beschriebenen Bedien-Smoketest.
Die optionale Live-Abnahme, die vollständige Bedienabnahme durch den Eigentümer und ein Austausch der
produktiven Installation wurden nicht durchgeführt. Die ChatGPT-Projektanzeige und die installierte
Alt-App sind separate, unveränderte Oberflächen; globale Modelleinstellungen wurden nicht geändert.
Historische Testfehler und die Grenzen ihrer Reproduktion werden separat in
[LEGACY_TEST_DISPOSITIONS.md](LEGACY_TEST_DISPOSITIONS.md) eingeordnet.
Nach lokalem Checkpoint endet diese Umsetzung ohne weitere Funktionsplanung.
