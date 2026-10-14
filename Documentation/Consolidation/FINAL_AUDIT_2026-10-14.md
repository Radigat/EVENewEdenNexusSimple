# Abschlussprüfung der Projektkonsolidierung – 14.10.2026

Projekt: **EVE New Eden Nexus - Assets, Industry, Markets**.

Diese Prüfung betrifft ausschließlich Projektidentität, Xcode-Struktur,
Quellennachweis, Dokumentation und lokale Verifikation. Sie fügt keine Funktion
hinzu und ändert keine Berechnungs- oder Produktlogik.

## Ergebnis

- Der sichtbare Produktname ist in `project.yml`, `Package.swift`, der aktiven
  Xcode-Projektdatei, dem App-Barrierefreiheitslabel und dem DEV-Fehlerdialog
  vereinheitlicht.
- Die GitHub-Repositorybeschreibung lautet
  `EVE New Eden Nexus - Assets, Industry, Markets`. Der technische Repositoryname
  `Radigat/EVENewEdenNexusSimple` bleibt als stabile Adresse bestehen.
- Im aktiven Arbeitsbaum existiert genau ein Xcode-Projekt:
  `EVENexusSimple.xcodeproj`. Das frühere `EVENexusSimple 2.xcodeproj` wurde mit
  Checkpoint `182f1a9` entfernt und ist als
  `_archive/simple-duplicate-xcode-from-head.tar.gz` wiederherstellbar.
- `project.yml` beschreibt Namen, Targets und wesentliche Einstellungen der
  kanonischen Projektstruktur. Eine frische, reproduzierbare XcodeGen-Erzeugung
  wurde nicht bestätigt: XcodeGen ist lokal nicht installiert, und die aktive
  Projektdatei enthält historisch ergänzte Dateizuordnungen und Einstellungen.
  Deshalb darf `project.yml` nicht als alleiniger, bytegenau reproduzierbarer
  Ursprung der Projektdatei bezeichnet oder blind regeneriert werden. Kanonisch
  ist die vorhandene einzelne `EVENexusSimple.xcodeproj`.
- Der Branch `agent/publish-latest-local-state` war gegenüber GitHub-`main`
  vollständig enthalten (`ahead_by: 0`, `behind_by: 1`). Der Remote- und der
  lokale Branch-Verweis wurden danach entfernt. Es erfolgte kein Code-Push und
  keine Änderung an `main`.

## Legacy-Quellen und Funktionsaussage

Die verfügbaren Quellstände **EVE Nexus Simple** und **New Eden Nexus** sind in
`source-inventory.json`, den Quellarchiven und den getrennten Index-/Arbeitsbaum-
Patches erhalten. Die fachliche Zuordnung steht in `FEATURE_COVERAGE.md`; bewusste
Konflikt- und Ausschlussentscheidungen stehen in `FUNCTIONAL_CONSOLIDATION.md` und
`DECISIONS.md`.

Ein eigenständiger Quellordner **Production Tracker** war und ist nicht verfügbar.
Für diesen nicht vorliegenden Stand ist daher kein datei- oder funktionsgenauer
Vergleich möglich. Die pauschale Aussage
„keine Funktion aus Production Tracker / New Eden Nexus / EVE Nexus Simple
verloren“ wird ausdrücklich **nicht** getroffen. Belastbar ist nur: Die inventarisierten
Funktionen der tatsächlich vorhandenen Quellen sind zugeordnet, übernommen,
bewusst ausgeschlossen oder als offene Grenze dokumentiert.

## Bewusst erhaltene technische Namen

Swift-Module und Targets (`EVENexusCore`, `EVENexusSimpleApp`, `EVENexusSimple`),
Bundle-Identifier, SwiftData-/Preferences-Pfade, Keychain-Dienste, OAuth-Callback,
Netzwerk-User-Agent und vorhandene Branding-Dateinamen bleiben kompatibel. Ihre
Gründe sind in `LEGACY_NAMES.md` einzeln dokumentiert. Die einzige alte sichtbare
Laufzeitzeichenfolge aus der Abschlussprüfung ist die historische Preferences-
Domain `EVE Nexus Simple` in `AppDefaults`; sie ist eine Migrationsquelle und kein
aktiver Produktname.

## Namensprüfung

Eine repositoryweite Prüfung der aktiven Runtime-/Konfigurationspfade fand keine
alte sichtbare Projektidentität. Treffer in `LEGACY_NAMES.md`, `VALIDATION.md` und
`dev-diary.md` sind ausdrücklich historische Nachweise; Archive, Inventar-JSON,
Patches, technische Identifier und die Preferences-Migrationsdomain sind keine
zweite aktive Projektidentität.

Die aktuelle Governance verwendet gemäß verbindlicher `MODEL_POLICY.md`
**GPT-5.6 Sol High**. Datierte Hinweise auf Astra Medium dokumentieren den früheren
Konsolidierungscheckpoint und sind keine aktive Modellvorgabe.

## Lokale Verifikation

Die ersten SwiftPM-Versuche im synchronisierten Projektordner wurden vor der
Testausführung durch File-Provider-/Resource-Fork-Metadaten beim Codesigning
abgebrochen. Mit isolierten Build-Ausgaben unter
`/private/tmp/eve-final-consolidation-20261014/` sind alle relevanten Prüfungen
erfolgreich:

- `swift test`: 477 Fälle, kein Fehler, ein vorgesehener Live-SDE-Skip.
- `swift test --package-path Packages/EVEStaticDataKit`: 8 Fälle, kein Fehler,
  ein vorgesehener Opt-in-Skip.
- nativer Xcode-Debug-/Testlauf, arm64, ohne Codesigning: `TEST SUCCEEDED`,
  431 Fälle, kein Fehler, ein vorgesehener Live-SDE-Skip.

Reale ESI-/SSO-/SDE-Abnahmen, produktive Nutzerdaten, installierte Apps und eine
vollständige visuelle/VoiceOver-Eigentümerabnahme wurden nicht verwendet und
werden nicht als geprüft behauptet.
