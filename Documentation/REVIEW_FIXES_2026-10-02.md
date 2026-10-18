# Fehlerkorrekturen und vollständige Datenwiederherstellung – 02.10.2026

Dieser Vertrag beschreibt die drei auf Nutzerauftrag korrigierten Fehler und die
zusätzlich freigegebene vollständige Wiederherstellung eines alten App-Datenstands.
Grundlage ist der einzige aktive Projektstand einschließlich seiner V3-Modelle.
Historische Daten werden nicht nachträglich mit aktuellen Marktpreisen umgerechnet.

## Übernahme alter SwiftData-Daten

Ein Legacy-Store wird vor der Veröffentlichung als konsistenter SQLite-Snapshot
bereitgestellt. Festgeschriebene Daten im WAL gehören zum Snapshot. Die Prüfung
und das dauerhafte Schreiben erfolgen vor der atomaren Veröffentlichung unter
dem kanonischen Dateinamen. Ein bereits vorhandener Zielstand oder verwaiste
Zielbegleitdateien werden nicht überschrieben. Fehler vor der Veröffentlichung
lassen einen erneuten Versuch zu. Die ursprünglichen Dateien bleiben erhalten.

Die vollständige Wiederherstellung akzeptiert ausschließlich die bekannten
App-Modelle V1, V2 und V3. Ihre Metadaten werden vor dem SwiftData-Öffnen gelesen;
eine fremde SQLite-Datei darf nicht als leerer App-Bestand initialisiert werden.
Auch ein leerer, aber gültiger App-Store bleibt zulässig.

Frühere unvollständige Übernahmen sind nicht zuverlässig automatisch erkennbar.
Ein erfolgreicher Integritätstest allein beweist nicht, dass alle Datensätze aus
dem alten WAL übernommen wurden.

## Bewusste vollständige Wiederherstellung

Die Wiederherstellung ist im normalen App-Betrieb und bei einem fehlgeschlagenen
Datenbankstart erreichbar. Sie wird erst nach Beenden und erneutem Öffnen in
einem exklusiven Wiederherstellungsmodus ausgeführt. Dieser öffnet keine aktive
SwiftData-Datenbank und startet keine Hintergrunddienste.

Vor der Auswahl werden beide Datenstände vollständig gesichert. Ein lesbarer
SQLite-Stand erhält zusätzlich einen konsistenten Snapshot; ein beschädigter
aktueller Stand bleibt als Dateipaket erhalten. Die alte Arbeitskopie wird mit
der aktuellen Migrationskette geprüft, ohne automatische Wiederherstellungsimporte
auszuführen. Die Vorschau zeigt Quelle, Datensatzanzahlen und Sicherungsort.

Nach ausdrücklicher Bestätigung ersetzt der geprüfte alte Stand die aktuelle
SwiftData-Datenbank vollständig. Neuere Datensätze bleiben ausschließlich in der
Sicherung erhalten; die Datenstände werden nicht zusammengeführt. Schlüsselbund,
Einstellungen, SDE sowie separate Markt- und Vertragsspeicher werden nicht ersetzt.
Ausstehende automatische Wiederherstellungsimporte werden gesondert verwahrt.

Ein dauerhaftes Vorgangsprotokoll mit Dateifingerprints schützt den Austausch.
Der kurzlebige Prüfprozess hält die geerbte Datensperre auch dann, wenn sein
übergeordneter App-Prozess endet. Erkannte JSON-Inhalte einschließlich bekannter
Base64-Snapshots in App-Einstellungen werden typisiert decodiert; unbekannte
oder einfache Einstellungen bleiben erhalten. Vor dem Abschluss führen
Fehler oder ein unterbrochener Prozess zur Wiederherstellung des bisherigen Stands.
Mehrdeutige Dateizustände oder eine fehlgeschlagene Rücknahme blockieren den normalen
Start und erhalten alle Kopien. Ein bereits abgeschlossener Vorgang löst keine
spätere automatische Rücknahme neuer Änderungen aus.

Die Datensperre schützt teilnehmende App-Instanzen. Vor einer Wiederherstellung
müssen ältere Installationen ohne diese Sperre ebenfalls beendet sein. Sicherungen
werden nicht automatisch entfernt.

## Produktionskosten

Für jeden Materialtyp bleibt die vollständige Bedarfsquote mit ihrem gewichteten
Stückpreis und ihren Warnungen erhalten. Der Materialkostenbeitrag beträgt:

`(gekaufte Menge + aus Lagerbestand verbrauchte Menge) × gewichteter Stückpreis`.

Hergestellte Zwischenprodukte werden durch ihre Zutatenkosten erfasst. Ihr
vollständiger Wiederbeschaffungswert wird nicht zusätzlich addiert. Kaufbetrag
und Lagerverbrauch bleiben getrennte Teilwerte. Unvollständige Quoten oder
ungültige Zahlen führen weiterhin zu nicht verfügbaren Gesamtkosten.

Plan, Produktionsübersicht und neu gespeicherte Produktionsaufzeichnungen müssen
übereinstimmen. Der Regressionstest mit einer gelagerten und einer hergestellten
Zwischenprodukteinheit ergibt 15 ISK Lagerwert plus 8 ISK Zutaten, also 23 ISK.
Die vollständige Zwischenproduktquote bleibt 30 ISK bei 15 ISK Stückpreis.
Details: [Produktionsvertrag](PRODUCTION_BASIS.md).

## Blueprint-Kopien im Nettovermögen

Das ESI-Asset-Kennzeichen `is_blueprint_copy` bleibt beim Decodieren, Synchronisieren,
Klassifizieren und Speichern erhalten. Persönliche und Corporation-Assets verwenden
dieselben Bewertungsregeln:

- Bekannte Kopien werden ausgeschlossen und gezählt.
- Bestätigte Originale und gewöhnliche Assets werden nach der bestehenden
  Referenzpreispolitik bewertet.
- Fehlende Kennzeichen alter Daten ergeben einen unbekannten Status. Eindeutige
  historische Blueprint-Mengenkennzeichen bleiben auswertbar; sonst bestätigt
  ausschließlich die vorhandene SDE-Klassifikation einen gewöhnlichen Asset-Typ.
- Unbekannte Blueprint- oder Klassifikationszustände bleiben unbewertet und
  sichtbar unvollständig. Sie werden nicht als Nullwert oder vollständig
  bewerteter Bestand dargestellt.

Neue Zähler sind beim Lesen älterer JSON-Aufzeichnungen rückwärtskompatibel.
Neue Vermögensaufzeichnungen verwenden die korrigierte Bewertungsrichtlinie;
historische Aggregate behalten ihren ursprünglichen Wert und Regelstand.

## Verifikation und Grenzen

Die Implementierung ist lokal im aktiven Projekt vorhanden. Am 02.10.2026 wurden
folgende Prüfungen mit ausschließlich synthetischen Daten abgeschlossen:

| Prüfung | Tatsächliches Ergebnis |
| --- | --- |
| Vollständiges SwiftPM-Hauptprojekt | 477 Tests: 476 bestanden, 1 vorgesehener Real-SDE-Skip; 0 Fehler |
| Separates EVEStaticDataKit | 8 Tests: 7 bestanden, 1 vorgesehener Real-SDE-Skip; 0 Fehler |
| Nativer unsignierter Debug-Build und Tests | `TEST SUCCEEDED`; 431 Tests: 430 bestanden, 1 Real-SDE-Skip |
| Nativer Start mit isoliertem Datenordner | Acceptance-Exit 0; Hintergrunddienste ausgeschaltet |
| Separater nativer Prüfprozess | Gültiger isolierter V3-Stand geöffnet; alle 13 Modellarten geprüft; fremde SQLite-Datei mit Exit 3 abgewiesen und unverändert erhalten |
| Projekt, DE-/EN-Kataloge, Dateizuordnung und Dokumentlinks | Gültig; keine doppelten Katalogschlüssel oder fehlenden Quellen |

Die SwiftPM-Summe besteht aus 423 Core-Swift-Testing-Fällen, 35 App-Swift-Testing-
Fällen und 19 XCTest-Fällen. Die nativen Tests wiederholen die Core-Nachweise;
beide Läufe sind keine zusätzlichen unabhängigen Fachtests.

Gezielt geprüft wurden WAL-only-Transaktionen, wiederholte Übernahme, Zielkonflikte,
Abbruch und Rücknahme an den Austauschgrenzen, dauerhaft abgeschlossene Vorgänge,
veränderte Originale, fehlgeschlagene Sicherung/Prüfung, fehlende Zusammenführung,
Sperrerhalt durch einen echten Unterprozess, V1/V2→V3 und alle Modellarten,
ungültige Nutzdaten, fremde SQLite-Dateien sowie die deutsche/englische Bestätigung.
Produktionskosten wurden für keinen/vollständigen/teilweisen Lagerbestand und
mehrere Aufträge gegen Historie und Übersicht geprüft. Blueprint-Kennzeichen
wurden durch persönliche/Corporation-Synchronisierung, Standortverarbeitung,
JSON-Speicherung und beide Bewertungswege geprüft; alte Historien bleiben lesbar.

Reproduzierbare Hauptprüfung: `swift test --disable-sandbox` mit getrenntem
Scratch-/Cache-/Konfigurations-/Security-Verzeichnis unter
`/private/tmp/eve-review-fixes-20261002/`, eigenem Application-Support-Root,
eigener Preferences-Suite und `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1`.
Die native Prüfung verwendet das bestehende Projekt/Scheme `EVENexusSimple`,
Debug, macOS arm64, getrenntes DerivedData und `CODE_SIGNING_ALLOWED=NO test`.
Ergebnisbundle: `/private/tmp/eve-review-fixes-20261002/native-tests-final.xcresult`.

Keine produktiven Nutzerdaten, Live-ESI-Abrufe oder installierten Apps wurden
für diese Tests verändert. Fehler an Austauschgrenzen wurden injiziert;
ein tatsächlicher Stromausfall ist kein behaupteter Testnachweis. Die
Live-, visuelle und vollständige VoiceOver-/Eigentümerabnahme bleibt offen.

Eine unabhängige, gezielte Abschlussprüfung bestätigt die korrigierte
Unterprozess-Sperre, die typisierte Prüfung bekannter Einstellungssnapshots und
die Modellzugehörigkeitsprüfung; innerhalb dieses Umfangs wurde kein weiterer
konkret belegter Fehler gemeldet. Sie ersetzt keinen weiteren Testlauf.
