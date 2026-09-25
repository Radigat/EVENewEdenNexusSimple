# EVE Nexus Simple – Neustart abgeschlossen

24.09.2026

## Ergebnis

Die App startet wieder normal. Ein neuer lokaler EVE-Datenspeicher wurde angelegt;
der vorherige fehlerhafte Bestand bleibt erhalten. Das Projekt wurde weiterverwendet,
das Vollbackup nicht verändert.

- Installierte App: `/Users/svenstolze/Applications/EVE Nexus Simple.app`
- Aktive Daten: `/Users/svenstolze/Library/Application Support/com.local.EVENexusSimple`
- Sicherung vor Neustart: `/Users/svenstolze/Library/Application Support/com.local.EVENexusSimple.vor-Neustart-20260924-223323`
- SDE: offizieller CCP-Build **3542233**, Katalogadapter v4.
- Katalog: **53.060 Typen**, **5.082 Blueprints**, **19.138 Aktivitäten**.
- Dashboard und Daten-Seiten sind erreichbar. Die SDE-Updateprüfung in der App
  bestätigt den installierten Katalog als aktuell.
- Die App steht auf **Daten & Einstellungen → ESI** bereit.

## Was noch vom Nutzer einzurichten ist

1. **Charakter autorisieren oder hinzufügen** wählen und die EVE-Anmeldung selbst durchführen.
2. Weitere persönliche Charaktere bei Bedarf hinzufügen und synchronisieren.
3. Produktionsanlagen, Marktstandorte und Logistikprofile passend zum eigenen Betrieb einrichten.

Frühere lokale Pläne und Einstellungen wurden nicht aus dem Quellbackup wiederhergestellt.
Die vorgefundenen Anzeigepräferenzen wurden erhalten; die App läuft auf Deutsch.
Automatische Vertrags- und Main-Hub-Scans waren beim Sichttest pausiert.

## Sicherung und Datenwechsel

Der bisherige Store war zwar als SQLite lesbar, enthielt aber das fremde leere Modell
`APIRequestModel`. Der neue Store wurde vor seiner Aktivierung in einem isolierten
Application-Support-Verzeichnis mit der geprüften App erzeugt und geöffnet.
Der alte App-Datenordner wurde anschließend unverändert unter dem oben genannten
Sicherungsnamen erhalten. Die Dateihashes stimmen weiterhin. Die globale
`~/Library/Application Support/default.store` wurde nicht verändert oder erneut importiert.

Der SDE-Download lief über den vorhandenen offiziellen Importpfad mit Quellenprüfung,
Staging, SQLite-Validierung und Aktivierung. Es gab keinen vorher aktiven SDE-Katalog;
`backup_created=false` bezieht sich ausschließlich auf diesen fehlenden SDE-Vorgänger.
Die separate Sicherung des alten App-Datenordners ist vorhanden.
21 unaufgelöste Typreferenzen bleiben als SDE-Quelldatenbefund sichtbar.

Offizielle Grundlage: [CCP-Dokumentation zum Static Data Export](https://developers.eveonline.com/docs/services/static-data/).
Die abgefragte aktuelle Build-Metadatei nennt 3542233 vom 24.09.2026.
Die jüngsten Schemaänderungen sind additive Felder bzw. zusätzliche Datensätze;
der Importer konnte den tatsächlichen aktuellen Datensatz erfolgreich verarbeiten.

## Verifikation

- Zuvor geprüfte unveränderte Codebasis: 416 SwiftPM-Tests, 383 native Xcode-Tests
  und sieben StaticDataKit-Tests bestanden. Die Real-SDE-Tests waren dabei mangels
  Paket zunächst übersprungen.
- Jetzt zusätzlich mit dem heruntergeladenen echten SDE-Paket bestanden:
  - `validatesAndActivatesOptInCurrentRealSDEInAnIsolatedSQLiteStore`, 1 Test;
  - `mapsOptInCurrentRealSDEPackage`, 1 Test.
- Frischer Store startet erfolgreich; die native App zeigt das Dashboard ohne
  die vorherige Wiederherstellungsfehlermeldung.
- Lokale ad-hoc-Signierung der installierten App einschließlich eingebetteter
  Frameworks; tiefe strikte Signaturprüfung bestanden. Keine öffentliche Distribution.
- Quellcode, Paketmanifest und Xcode-Projekt sind unverändert. Aktualisiert wurden
  ausschließlich `dokumentation.md` und `dev-diary.md`; Diff-Whitespace-Prüfung bestanden.
- Persönliche SSO-/ESI-Verbindungen und fachliche Abnahme eigener Produktionsfälle
  stehen noch aus.

## Rückweg bei Bedarf

Zuerst die App vollständig beenden. Den dann aktuellen neuen Datenordner separat sichern.
Erst anschließend kann die Sicherung vor Neustart wieder an den kanonischen Pfad gesetzt
werden. Diese Sicherung enthält den zuvor fehlerhaften Zustand und ist keine Quelle
für verlorene EVE-Produktionspläne; sie dient dem Erhalt und der Nachvollziehbarkeit.
Schlüsselbund-Tokens wurden nicht exportiert oder verändert.
