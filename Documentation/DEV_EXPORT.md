# Lokaler App-Export und DEV-Kopie

Aktives Quellprojekt: **EVE New Eden Nexus - Assets, Industry, Markets**.
Die exportierten Apps basieren auf geprüftem Release-Code für Apple Silicon und
macOS 14 oder neuer. Der jeweilige Quellstand steht in den Build-Metadaten. `-DEV` kennzeichnet die isolierte Datenkopie, keine zusätzliche Fachfunktion.

## Dateien und Nutzung

- `~/Downloads/EVE New Eden Nexus - Assets, Industry, Markets.app`: normale App mit bestehenden Datenpfaden.
- `~/Downloads/EVE New Eden Nexus - Assets, Industry, Markets-DEV.app`: separate DEV-App mit eingebettetem
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

## Startkorrektur vom 25.09.2026

Die erste Paketfassung scheiterte beim Öffnen der eigenen Einstellungsdomäne. Der Fehler wurde
mit synthetischen Daten reproduziert und korrigiert. Zusätzlich wurde der Hilfsstarter entfernt,
dessen Prozesswechsel die native Fensterzuordnung störte. Der tatsächliche App-Einstieg führt
jetzt die Datenübernahme vor allen App-Einstellungen und der Oberfläche aus.

Die aktualisierte DEV-App wurde über Finder geöffnet: Dashboard erreichbar und kopierte Daten
sichtbar. Die vorhandene DEV-Arbeitskopie wurde dabei beibehalten. Zehn synthetische Export- und
Startprüfungen bestehen, einschließlich eigener Bundle-Domäne, unterbrochenem Einstellungsimport
und anschließend erhaltener Einstellungsänderungen. Erneute Prüfungen: SwiftPM 452 / 1 Skip,
Kit 7 / 1, native Tests 416 / 1; Debug- und Release-Build erfolgreich.

## Erneute Prüfung und Erstellung

`Scripts/check_dev_export.py --base-app <signierte Release.app>` erzeugt ausschließlich
synthetische Daten, verpackt eine temporäre DEV-App und prüft Erststart sowie Fehlerfälle.

`Scripts/export_dev_app.py --base-app <signierte Release.app> --source-data <kanonischer Datenordner>
--preferences-file <exportierte Einstellungen.plist> --output <neue DEV.app>` erzeugt die
Datenkopie. Die Parameter gehören in einen gemeinsamen Aufruf. Die Einstellungen stammen aus
dem Export der kanonischen UserDefaults-Domäne. Der Exporter überschreibt kein vorhandenes Ziel,
verweigert symbolische Links und bricht bei erkannten Quelldatenänderungen während der Kopie ab.
Die Datenübernahme läuft über `DevelopmentAppBootstrap` vor dem Erzeugen der SwiftUI-App.
Das Paket startet direkt das im Info.plist deklarierte App-Executable; es gibt keinen
zusätzlichen Hilfsprozess oder `exec`-Übergang. Die eigene UserDefaults-Domäne verwendet
`.standard`, da macOS dieselbe Bundle-ID als zusätzliche Suite zurückweist. Bereits
angelegte DEV-Daten bleiben bei der Wiederaufnahme eines Einstellungsimports erhalten.
Xcode-Projekt, App-Target, fachliche Berechnungen und produktiver OAuth-Callback bleiben erhalten.

Die fertigen Apps liegen im lokalen Downloads-Ordner. Der File Provider des synchronisierten
Dokumente-Ordners ergänzte dort wiederholt Finder-Metadaten, die die strikte Signaturprüfung
störten. Außerhalb dieses Ordners bleiben die App-Signaturen unverändert prüfbar. Im Projekt
liegen unter `dist/` nur Build-Metadaten; keine App-Datenkopie und kein ZIP-Archiv. `dist/` bleibt
vorsorglich von Git ausgeschlossen. Die DEV-App enthält private Nutzdaten und ist kein
öffentliches Distributionspaket. Für weitere Exporte ebenfalls ein lokales, nicht synchronisiertes
Ziel verwenden.

## Korrektur der Einstellungsreiter vom 25.09.2026

Die DEV-App in Downloads enthält die korrigierte Reiterleiste: eigener Platz innerhalb
des sichtbaren Inhaltsbereichs unter der nativen Titelleiste, konstante Eigenhöhe und
vollbreiter Hintergrund. Allgemein, ESI und Industrieeinstellungen wurden direkt in
der laufenden DEV-App geprüft, einschließlich Seitenwechsel, Scrollen und Wechsel
zwischen maximiertem Fenster und einem Bildschirmviertel. Keine Überdeckung mehr
beobachtet. Auf anschließenden Benutzerauftrag wurde auch die normale exportierte App
auf diesen geprüften Quellstand aktualisiert (siehe Übertragungsnachweis unten).

SwiftPM: 454 bestanden / 1 optionaler Skip; EVEStaticDataKit: 7 / 1; native Tests:
416 / 1. Debug- und Release-Build erfolgreich. Zwei zusätzliche synthetische UI-Tests
prüfen die Eigenhöhe bei verschiedenen Breiten/Höhen und die Lage relativ zur nativen
Toolbar. Der ursprüngliche Fehler ließ sich im vereinfachten Testfenster nicht
reproduzieren; der Vorher-/Nachher-Nachweis stammt aus der laufenden DEV-App.

Nur Programmdateien und lokale Signatur wurden erneuert. Alle 30 Dateien im Seed
(einschließlich Manifest) sowie alle 38 vorhandenen DEV-Arbeitsdateien waren vor und
unmittelbar nach der Aktualisierung per SHA-256 identisch. Kein erneuter Datenexport,
keine Migration, keine neue Anmeldung. Die App-Signatur ist strikt geprüft.

## Übertragung auf die normale App vom 25.09.2026

Die normale App unter `~/Downloads/EVE New Eden Nexus - Assets, Industry, Markets.app`
verwendet jetzt ebenfalls den bereits geprüften Release-Build aus Quellstand
`8beff4ce2bd2b439b0c621a69e4f504a07e44b05`. Es wurde kein neuer Code geändert.
Das Paket wurde lokal signiert und strikt geprüft; Bundle-ID, Einstellungen,
Schlüsselbundzugriff und produktiver Datenpfad bleiben erhalten. Es enthält keinen DEV-Seed.

Die bisherige App wurde vor dem Austausch beendet und lokal zur Rücknahme gesichert:
`/private/tmp/eve-normal-build-before-layout-j520kqe9/EVE New Eden Nexus - Assets, Industry, Markets.app`.
Alle 38 vorhandenen Daten-/Einstellungsdateien waren direkt vor/nach Programmaustausch
per SHA-256 identisch. Die DEV-App wurde bei dieser Übertragung nicht verändert.

Regulärer Start der normalen App geprüft: Dashboard geöffnet, anschließend Allgemeine
Einstellungen mit vollständig sichtbarer Reiterleiste unterhalb der nativen Titelleiste.
Keine zusätzliche Fach- oder Live-Service-Abnahme. Die bereits dokumentierten erfolgreichen
Builds und Tests gehören zum unverändert übertragenen Build; kein erneuter Testlauf nötig.
Aktualisierte Paketmetadaten stehen in `dist/BUILD_INFO.json`.
