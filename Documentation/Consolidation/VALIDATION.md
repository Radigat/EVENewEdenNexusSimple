# Organisatorische Konsolidierungsprüfung – Checkpoint 182f1a9

Historischer Nachweis vor der fachlichen Integration. Aktuell gilt [FUNCTIONAL_VALIDATION.md](FUNCTIONAL_VALIDATION.md).

Projekt: **EVE New Eden Nexus - Assets, Industry, Markets**. Standardmodell: **Astra Medium**.
Einziger aktiver Stamm: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.

## Ergebnis

| Prüfung | Tatsächliches Ergebnis |
| --- | --- |
| SwiftPM Hauptprojekt, Debug | Exit 0; 417 bestanden, 1 expliziter Real-SDE-Skip, 0 Fehler |
| Lokales EVEStaticDataKit | Exit 0; 7 bestanden, 1 expliziter Real-SDE-Skip, 0 Fehler |
| Nativer Xcode-Debugbuild | Exit 0; BUILD SUCCEEDED |
| Natives Xcode-Core-Testtarget | Exit 0; 385 bestanden, 1 Real-SDE-Skip, 0 Fehler; TEST SUCCEEDED |
| Vollständigkeit der aktiven Quellen | Keine fehlende Datei; alle Fach-/Test-/Kit-Quellen unverändert; nur App-Label geändert |
| Projekt-/Dateiverweise | Ein aktives Xcode-Projekt; 50 Core- und 23 App-Swiftquellen sowie alle 21 Core-Testdateien zugeordnet; keine fehlenden Dateireferenzen |
| Dokumentlinks/Symlinks | Keine defekten lokalen Markdown-Dateiziele und keine gebrochenen Symlinks |
| Archivierung | Hashes, Git-Status und HEAD beider verschobenen Arbeitsbäume verifiziert; Tar-Hashes stimmen mit Inventaren überein |
| Namensprüfung | Keine aktiven alten menschenlesbaren Projektnamen in den acht Steuerdateien; technische/historische Ausnahmen separat registriert |

Die SwiftPM-Anzahl setzt sich aus 385 Core-Swift-Testing-Tests, 21 App-Swift-Testing-Tests
und elf XCTest-Tests zusammen. Die Core-Runner-Anzeige nennt 386 einschließlich des
übersprungenen Tests. Das Kit meldet acht einschließlich eines Skips. Native und
SwiftPM-Core-Tests überschneiden sich und sind nicht als zusätzliche eindeutige Tests
zu addieren. Die neue Gesamtzahl gegenüber dem Nachweis vom 24.09. enthält den bereits
vor der Konsolidierung vorhandenen Fensterlayout-Regressionstest.

## Reproduzierbare Befehle

Werkzeuge: Xcode 27.0 (27A266a), Apple Swift 6.4, macOS arm64.
Vor dem Build wurden Targets, Schemes und Debug/Release-Konfigurationen mit
`xcodebuild -list -json -project EVENexusSimple.xcodeproj` ermittelt.

Hauptpaket vom finalen Projektpfad:

```sh
swift test --disable-sandbox \
  --scratch-path /private/tmp/eve-nexus-consolidation-20260925/swift-build \
  --cache-path /private/tmp/eve-nexus-consolidation-20260925/swift-cache \
  --config-path /private/tmp/eve-nexus-consolidation-20260925/swift-config \
  --security-path /private/tmp/eve-nexus-consolidation-20260925/swift-security
```

Das Kit wurde mit demselben Befehl in `Packages/EVEStaticDataKit`, eigenem
`kit-build`-Scratchpfad und `kit-modules`-Modulcache geprüft.

```sh
xcodebuild -project EVENexusSimple.xcodeproj -scheme EVENexusSimple \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/eve-nexus-consolidation-20260925/xcode-build \
  -clonedSourcePackagesDirPath /private/tmp/eve-nexus-consolidation-20260925/xcode-packages \
  build CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
```

Anschließend derselbe Xcode-Aufruf mit `test` und
`-resultBundlePath /private/tmp/eve-nexus-consolidation-20260925/xcode-tests.xcresult`.
Ergebniszahlen zusätzlich mit `xcresulttool get test-results summary` ausgelesen.

Alle Hauptpaket-/App-Prüfungen liefen mit separaten Modulcaches, CFFIXED_USER_HOME,
TMPDIR, `EVE_NEXUS_APPLICATION_SUPPORT_ROOT`, eigenem
`EVE_NEXUS_USER_DEFAULTS_SUITE` und `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1` unter
`/private/tmp/eve-nexus-consolidation-20260925`. Produktive App-Daten und Tokens
wurden nicht als Testbestand verwendet oder migriert.

## Artefakte und Warnungen

Gebautes Produkt:

`/private/tmp/eve-nexus-consolidation-20260925/xcode-build/Build/Products/Debug/EVE New Eden Nexus - Assets, Industry, Markets.app`

CFBundleName, CFBundleDisplayName und CFBundleExecutable tragen den neuen Namen;
CFBundleIdentifier bleibt `com.local.EVENexusSimple`. Das Xcode-Swiftmodul ist
explizit auf den vorherigen abgeleiteten Namen `EVE_Nexus_Simple` festgelegt.
Die bereits installierte Alt-App wurde nicht überschrieben oder neu gestartet.

Unverändert sichtbare Buildwarnungen: veraltete TaskLocal-Überladung in ESIClient,
symbolfreier SQLite-Shim, übersprungene AppIntents-Metadaten mangels entsprechender
Frameworkabhängigkeit. Keine Warnung durch Fachcodeänderung unterdrückt.
Der erste xcresulttool-Leseversuch scheiterte an dessen lokalem Report-Cachezugriff;
der anschließende autorisierte Aufruf war erfolgreich. Kein Testfehler.

Vollständige Logs: `/private/tmp/eve-nexus-consolidation-20260925/logs`.
Prüfsummen und strukturierte Ergebnisse: [validation-results.json](validation-results.json).
Schemes/Targets: [Xcode-Inventar](xcode-project-inventory.json).
Statische Ergebnisse: [static-checks.json](static-checks.json).

## Offene Konsolidierungsgrenzen

- Die organisatorische Zusammenführung ist durchgeführt. Eine vollständige funktionale
  Verschmelzung der verschiedenen Legacy-Datenmodelle ist nicht umgesetzt: insbesondere
  Nexus-Projektbudget, CSV-/manuelles Inventar, Projektreservierungen und bestätigte
  Chargen-/Wallet-Verkaufszuordnungen bleiben vollständig archivierte Quellkomponenten.
  Einbau wäre eine Logik-/Architekturänderung; siehe [Komponentenvergleich](COMPONENTS.md).
- Historischer Production-Tracker-Quellpfad ist nicht vorhanden. Kein Stand dieses
  Namens wurde erfunden oder als übernommen gewertet.
- ChatGPT-Projektanzeige ist weiterhin „EVE New Eden Nexus“. Der Codex-Oberflächenzugriff
  ist systemseitig gesperrt; das Projektwerkzeug bietet keine Umbenennung. Kein globales
  App-Modell wurde verändert. Astra Medium ist in AGENTS und MODEL_POLICY verbindlich.
- Live-SDE, SSO/ESI, visuelle Eigentümerabnahme, Signierung/Distribution und die
  historischen Nexus-Tests wurden in diesem Auftrag nicht ausgeführt. Alte Nexus-
  Testprobleme sind nicht als behoben ausgewiesen. Kein neues Feature geplant.
- XcodeGen ist lokal nicht installiert. Das vorhandene native Projekt wurde direkt
  geprüft; keine unvalidierte Regeneration der historischen Generatorvorlage.

## Git-Checkpoint

Branch: `consolidation/2026-09-25-single-source`.
Ein lokaler Konsolidierungscommit erfasst bewusst auch die vorbestehenden Nutzeränderungen.
Die große Differenz zum alten HEAD ist kein während dieser Konsolidierung neu entwickelter
Funktionsumfang; die Trennung belegen Quellarchive, Index-/Arbeitsbaum-Patches und
consolidation-changes.json. Checkpoint wird nach Abschlussprüfung erstellt, kein Push.
Der endgültige Commit-Hash und saubere Git-Status stehen im Abschlussbericht.
