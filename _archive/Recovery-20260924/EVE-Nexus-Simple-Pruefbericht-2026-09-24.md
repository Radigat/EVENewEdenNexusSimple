# EVE Nexus Simple – Buildprüfung und Datenrettung

Stand: 24.09.2026. Der aktuelle Projektordner bleibt die Arbeitsgrundlage; das Vollbackup bleibt unverändert.

## Ergebnis

- Swift-Package: Build erfolgreich; **416 Tests bestanden** (405 Swift Testing, 11 XCTest), **1 Real-SDE-Test übersprungen**.
- Natives Xcode-Projekt: Debug-Build und Tests erfolgreich (`TEST SUCCEEDED`, Exit 0); **383 Tests bestanden**, **1 Real-SDE-Test übersprungen**.
- Separates EVEStaticDataKit: **7 Tests bestanden**, **1 Real-SDE-Test übersprungen**.
- Die übersprungenen Tests benötigen ein vorbereitetes offizielles SDE-Paket. Es wurde keine Live-SSO-/ESI-/SDE-Abnahme durchgeführt.
- Isolierter App-Initialisierungstest mit leerem Datenspeicher: erfolgreich, Exit 0.
- Derselbe Test mit einer Kopie des derzeitigen Datenspeichers: gescheitert, Exit 2. Ursache: unbekanntes Datenmodell, Core Data 134504.
- **Die alten App-Daten sind noch nicht wiederhergestellt.**

## Isolation und unveränderter Bestand

Quellbasis: `/Users/svenstolze/Documents/EVE NEXUS SIMPLE`.

Prüfkopie und abgeleitete Dateien: `/private/tmp/eve-simple-validation-20260924`.

Es wurden 160 Projektdateien in die Prüfkopie übernommen; Git, Build-Caches, Finder-Dateien und der Xcode-Fensterzustand wurden nicht benötigt. Dateihashes und Git-Status des Originalprojekts sind nach der Prüfung unverändert. Auch die geprüften Original-Datenbankdateien einschließlich WAL/SHM sind unverändert. Das Vollbackup wurde nicht bearbeitet.

Die Tests nutzten getrennte Application-Support-, Preferences- und temporäre Pfade. Hintergrunddienste waren über die vorhandene App-Konfiguration abgeschaltet. Der Starttest verwendete den vorhandenen `EVE_NEXUS_PERSISTENCE_ACCEPTANCE_EXIT`-Pfad und beendet die App nach dem Öffnungsversuch; er ist kein visueller Oberflächentest.

Umgebung: Xcode 27.0 (27A266a), Apple Swift 6.4, macOS arm64. Native Builds waren unsigniert (`CODE_SIGNING_ALLOWED=NO`). Die Prüfung ist keine Signierungs- oder Distributionsabnahme.

## Buildnachweise und Grenzen

SwiftPM wurde mit `swift test --disable-sandbox` sowie getrennten Scratch-, Cache-, Config-, Security- und Modulcachepfaden ausgeführt, einmal am Hauptpaket und einmal an `Packages/EVEStaticDataKit`.

Native Prüfung: `xcodebuild -project EVENexusSimple.xcodeproj -scheme EVENexusSimple -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath <isolierter Pfad> test CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`.

Die ersten nativen Versuche scheiterten vor dem eigentlichen Build am gesperrten globalen Modulcache bzw. am verschachtelten Sandbox-Start. Der autorisierte Lauf mit getrennten Caches außerhalb der einschränkenden Sandbox bestand. Das Xcode-Scheme umfasst weiterhin nur das Core-Testtarget; die zusätzlichen App-Tests und LoyaltyStoreCatalogTests wurden über SwiftPM geprüft.

Verbleibende Warnungen: veraltete Swift-TaskLocal-Überladung in ESIClient, symbolfreier SQLite-Shim und übersprungene AppIntents-Metadatenextraktion. Beim isolierten SwiftData-Test erschienen Meldungen zur nicht verfügbaren Store-Change-Registrierung; die betroffenen Tests bestanden. Es wurden keine Warnungen durch Quelländerungen unterdrückt.

## Gefundene App-Daten

Geprüft wurden ausschließlich Kopien dieser drei Kandidaten:

1. `~/Library/Application Support/com.local.EVENexusSimple/ApplicationData/EVENexusSimple.store`
2. `~/Library/Application Support/default.store`
3. die vorhandene Migrationssicherung unter `com.local.EVENexusSimple/migration-backups/swiftdata/`

Alle drei Dateien bestehen den SQLite-Integritätstest. Sie besitzen jedoch ausschließlich das fremde Modell **APIRequestModel**, mit null fachlichen Datensätzen. Die erwarteten EVE-Entitäten für Charaktere, Pläne, Produktionsprofile und Bestände fehlen. Der lokale SDE-Ordner ist leer.

Die App enthält einen Legacy-Import, der eine vorhandene globale `default.store` ohne Prüfung der Modellzugehörigkeit in den App-Ordner kopiert. Dies ist eine plausible Erklärung für den gefundenen Fremdbestand; die tatsächliche Entstehung wurde nicht nachgewiesen. Es wurde nichts gelöscht, ersetzt oder als scheinbar erfolgreiche Wiederherstellung neu initialisiert.

## Weitere Sicherungen

Auf `/Volumes/t7 Shild - DAten/Codex/` wurde auch das ursprüngliche Vollbackup-Archiv samt `.sha256` gefunden. Die SHA-256-Prüfung stimmt. Das Archiv enthält keine `.store`-, SQLite- oder sonstigen App-Datenbankdateien; der dokumentierte Ausschluss der Laufzeitdaten ist damit bestätigt.

Das angeschlossene Time-Machine-Ziel heißt `/Volumes/Timemaschine`. Das Auflisten der Sicherungen wird von macOS mit dem Hinweis auf fehlenden Festplattenvollzugriff verweigert, auch beim autorisierten Aufruf außerhalb der Build-Sandbox. Die alten Sicherungsinhalte wurden daher noch nicht gelesen. Es wurde kein Zugriffsweg zur Umgehung dieser Sperre verwendet.

## Nächster Schritt zur Datenrettung

Benötigt wird aus einer Time-Machine-Sicherung **vor der Neuinstallation** der vollständige Benutzerordner:

`Library/Application Support/com.local.EVENexusSimple`

Bitte zunächst nur als Kopie in einen separaten Arbeitsordner bereitstellen; keinesfalls über den aktiven App-Datenordner zurückkopieren. Falls dieser Ordner im alten Backup fehlt, ist der damalige `Library/Application Support/default.store` einschließlich vorhandener `-wal`- und `-shm`-Dateien ein weiterer Kandidat, dessen Modellzugehörigkeit vor Import geprüft werden muss.

Sobald der alte Bestand lesbar vorliegt: Originalkopie sichern, Integrität und EVE-Modell prüfen, Datensätze inventarisieren, Migration und Neustart isoliert testen, erst danach den aktiven Speicher geschützt ersetzen. Schlüsselbund-Tokens gehören nicht in den Arbeitsordner; eine erneute EVE-SSO-Autorisierung kann erforderlich sein.
