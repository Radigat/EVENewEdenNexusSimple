# EVE New Eden Nexus - Assets, Industry, Markets – Workflow

Einzige Arbeitswurzel: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`. Standardmodell: GPT-5.6 Sol High.
Vor jedem Eingriff Status und Diff lesen. Bestehende lokale Änderungen erhalten.
Die ursprünglichen Arbeitsbäume und Git-Indizes werden als Legacy archiviert.

## Prüfung

1. `git status --short --branch`, `git diff`, `git diff --cached` prüfen.
2. Vorhandenes `EVENexusSimple.xcodeproj`, Scheme `EVENexusSimple`, Debug, macOS arm64 verwenden.
3. `swift test` im Projektstamm und separat in `Packages/EVEStaticDataKit` ausführen.
4. Natives `xcodebuild ... build` und `xcodebuild ... test` ausführen.
5. `git diff --check`, Namenssuche, lokale Dokumentlinks, Package-/Xcode-Dateiverweise prüfen.

Für isolierte Tests eigene Pfade für Scratch, Cache, Konfiguration, temporäre Daten
und DerivedData unter `/private/tmp` setzen. Die vorhandenen Schalter sind:

- `EVE_NEXUS_APPLICATION_SUPPORT_ROOT`: separater Test-Datenordner;
- `EVE_NEXUS_USER_DEFAULTS_SUITE`: separate Test-Preferences;
- `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1`: keine automatischen Dienste;
- `CLANG_MODULE_CACHE_PATH` und `SWIFTPM_MODULECACHE_OVERRIDE`: separate Modulcaches.

Die tatsächlichen Befehle und Ergebnisse stehen im
[aktuellen Prüfbericht](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md). `--disable-sandbox` betrifft
bei SwiftPM nur den Manifest-/Build-Prozess; bei macOS-Ausführungsbeschränkungen
den vorgesehenen Berechtigungsweg verwenden. Keine produktiven Stores als Fixtures.
Reale SDE-/SSO-/ESI-Abnahmen bleiben opt-in und werden nicht durch Unit-Tests ersetzt.

## Git und Checkpoint

Basis ist die vorhandene Simple-Git-Historie. Konsolidierungsbranch:
`consolidation/2026-09-25-single-source`.
Der Benutzerauftrag erlaubt einen lokalen Commit für den vollständigen übernommenen
Arbeitsstand einschließlich zuvor uncommitteter Dateien und Konsolidierung.
Vorherige HEADs, Indizes, Arbeitsbaum-Diffs und Hashinventare sind dokumentiert.
Kein Push, kein Merge fremder Historien und keine Änderung des Home-Repositories.
Historischer Remote-Repositoryname bleibt als technischer Herkunftsverweis erhalten.

## Dokumentation und Abschluss

Status in PROJECT_STATE, Produktbeschreibung in PRODUCT, Architektur in ARCHITECTURE;
datierte Nachweise in Documentation und dev-diary. Kompatibilitätsdateien sind keine
zweiten Quellen. Legacy-Prompts nicht automatisch ausführen.
Nach Checkpoint und Abschlussbericht stoppen; keine neuen Features planen.

## Additive Datenprüfung

Migrationen V2→V3 und wiederholte Initialisierung mit synthetischen Stores prüfen.
SQLite-Sicherungen müssen WAL-Daten enthalten; manipulierte und fremde Sicherungen müssen scheitern.
Niemals die produktive Installation oder Nutzerdaten für diese Tests verwenden.
Neue Kernquellen/-tests müssen sowohl in SwiftPM als auch im bestehenden Xcode-Projekt enthalten sein.
