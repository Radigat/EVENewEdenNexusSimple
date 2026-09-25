# Lokaler App-Export und DEV-Kopie

Aktives Quellprojekt: **EVE New Eden Nexus - Assets, Industry, Markets**.
Beide exportierten Apps verwenden denselben geprüften Release-Code für Apple Silicon und
macOS 14 oder neuer. `-DEV` kennzeichnet die isolierte Datenkopie, keine zusätzliche Fachfunktion.

## Dateien und Nutzung

- `dist/EVE New Eden Nexus - Assets, Industry, Markets.app`: normale App mit bestehenden Datenpfaden.
- `dist/EVE New Eden Nexus - Assets, Industry, Markets-DEV.app`: separate DEV-App mit eingebettetem
  Datenbestand zum Exportzeitpunkt (25.09.2026).
- `dist/BUILD_INFO.json` und `dist/DEV_BUILD_INFO.json`: Herkunft, Prüfergebnis und Build-Metadaten.

Die Apps können per Doppelklick gestartet oder nach Programme kopiert werden. DEV prüft beim
ersten Start jede eingebettete Datei und legt die Arbeitskopie unter
`~/Library/Application Support/com.local.EVENexusSimple.DEV/com.local.EVENexusSimple/` an.
Einstellungen liegen in der Domäne `com.local.EVENexusSimple.DEV`; Anmeldeschlüssel verwenden
`com.local.EVENexusSimple.DEV.refresh-token`. Änderungen an der DEV-Arbeitskopie bleiben bei
Neustarts erhalten. Ein weiterer Export ersetzt einen bereits bestehenden DEV-Bestand nicht.

Enthalten sind lokale Anwendungsdaten, Produktionshistorie, gespeicherte Charakter-/ESI-Daten,
Vertragsdaten, installierte SDE-Kataloge, vorhandene lokale Katalogpakete und Sicherungen sowie
Einstellungen. SQLite-Dateien werden über Online-Backups einschließlich bestätigter WAL-Inhalte
kopiert; flüchtige WAL-/SHM-Dateien sind deshalb kein separater Bestandteil. Es wird nur die
aktive kanonische Datenquelle kopiert, keine alte globale `default.store` zusätzlich importiert.
Der Schlüsselbund bleibt auf dem Mac. Für Live-Zugriffe in DEV erneut anmelden; wegen des
unveränderten lokalen SSO-Callbacks Anmeldungen in beiden Apps nacheinander durchführen.

## Nachweise vom 25.09.2026

- Release- und Xcode-Debug-Build erfolgreich; SwiftPM 452 bestanden / 1 opt-in Skip,
  EVEStaticDataKit 7 / 1, native Tests 416 / 1.
- Synthetisch geprüft: erster Start, reale DEV-Bundle-ID im gestarteten App-Prozess, getrennte
  Einstellungen und Datenpfade, unveränderter produktiver Pfad, erhaltener DEV-Bestand bei
  Neustart, vollständiger SQLite-WAL-Snapshot, Abbruch bei beschädigter eingebetteter Kopie
  oder bereits vorhandenem unvollständigem Datenziel.
- Finale Datenkopie: 29 Dateien, 437.424.810 Bytes, fünf konsistente SQLite-Snapshots.
  Quelldateien einschließlich WAL und Einstellungen nach Export unverändert geprüft.
- Beide Pakete lokal signiert und Signaturen geprüft. Nicht notarisiert.
- Produktive Daten wurden nur für den autorisierten Export gelesen; Funktionstests verwenden
  synthetische Daten. Live-Anmeldung und Nutzerabnahme sind nicht Teil dieses Nachweises.

## Erneute Prüfung und Erstellung

`Scripts/check_dev_export.py --base-app <signierte Release.app>` erzeugt ausschließlich
synthetische Daten, verpackt eine temporäre DEV-App und prüft Erststart sowie Fehlerfälle.

`Scripts/export_dev_app.py --base-app <signierte Release.app> --source-data <kanonischer Datenordner>
--preferences-file <exportierte Einstellungen.plist> --output <neue DEV.app>` erzeugt die
Datenkopie. Die Parameter gehören in einen gemeinsamen Aufruf. Die Einstellungen stammen aus
dem Export der kanonischen UserDefaults-Domäne. Der Exporter überschreibt kein vorhandenes Ziel,
verweigert symbolische Links und bricht bei erkannten Quelldatenänderungen während der Kopie ab.
`Scripts/DevAppLauncher.swift` wird ausschließlich als Starter des exportierten Pakets gebaut;
Xcode-Projekt, App-Target, fachliche Berechnungen und produktiver OAuth-Callback bleiben erhalten.

Alle Dateien unter `dist/` sind lokale Artefakte und von Git ausgeschlossen. Die DEV-App enthält
private Nutzdaten und ist kein öffentliches Distributionspaket.
