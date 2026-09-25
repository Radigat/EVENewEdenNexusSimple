# Optimierungsplan

Ziel: Stabilität und Reaktionsgeschwindigkeit verbessern, ohne fachliche
Berechnungen, Quellzustände oder gespeicherte Fakten zu verändern.

## Arbeitsregel

- Die Punkte werden in der angegebenen Reihenfolge und einzeln umgesetzt.
- Nach jedem Punkt folgen fokussierte Tests, Gesamttest und Dokumentation.
- Live-/Owner-Abnahme bleibt von automatischen Tests getrennt.
- Kein Staging, Commit, Push oder Löschen ohne ausdrückliche Freigabe.

## Reihenfolge

| Nr. | Status | Maßnahme | Abnahme |
| --- | --- | --- | --- |
| 1 | umgesetzt; automatisch und im befüllten Prozess geprüft | Public-Contracts-Datenbank und transaktionalen Typindex-Backfill außerhalb des Main Actors öffnen; Vorbereiten, Fehler und Wiederholen sichtbar machen | 19 Contract-Tests sowie vollständiger SwiftPM-/Xcode-Lauf grün; Produktionsdatenbank nach bereits erfolgter Migration mit 10.934 Typen und `quick_check = ok`; CPU/RSS-A/B durchgeführt, einmalige Migrationsspitze und Langzeitlauf bleiben offen |
| 1a | umgesetzt; Release-gemessen | Dashboard-Mineralticker einmal aufbauen und per Core Animation statt durch kontinuierliche SwiftUI-Neuberechnung bewegen; bei inaktiver App pausieren | sichtbarer Release-Ticker geprüft; CPU von dauerhaften rund 38 % in der verworfenen SwiftUI-Variante auf rund 0,2 % gesenkt; finaler sauberer Lauf 0,07 CPU-Sekunden in 34 Sekunden bei stabilen 193–194 MiB RSS; 269 Tests und Release-Build grün |
| 2 | umgesetzt; automatisch geprüft | Planer über einen eigenen beobachtbaren Feature-Kanal an `RuntimeState` anbinden, damit Contract-, Markt-, Dashboard- und Installationsmeldungen den großen Planerbaum nicht neu zeichnen; Koordinator und fachliche Zustände bleiben unverändert | drei gezielte Zustands-/Hosting-Tests beweisen getrennte Invalidierung; 272 Tests in 23 Suites und universeller Release-Build grün; befüllter Release-Planer war bereits CPU-idle, Lastlauf während echter Hintergrundsynchronisation bleibt offen |
| 3 | umgesetzt; automatisch geprüft | Planner-Persistenz und Historie begrenzen: nur benötigte aktive Daten laden, alte inaktive Pläne seitenweise/lazy darstellen und unveränderliche Historienwerte teilen | keine Schema-/Datenmigration nötig; vorhandenes V2-Backup und Read-only-Vorschau geprüft; fünf aktuelle Zeilen im Planner, 100 Zeilen je Historienseite, direkte Einzelabfragen, geteilte Snapshot-Dekodierung sowie identische Reservierungen und Gesamtsummen durch sechs Tests belegt; vollständiger Test/Release-Build grün, befüllte Owner-Abnahme offen |
| 4 | umgesetzt; automatisch geprüft | Main-Hub-Demand-Ledger kompakt/streamend verarbeiten und schwere automatische Scans während einer interaktiven Planner-Berechnung koordinieren | V1 wird erst beim nächsten erfolgreichen Scan verlustfrei in kompakte V2-Zeilen überführt; Order-ID-/Tagessemantik bleibt unverändert; Abbruch, Wiederaufnahme und überlappende Planner-Läufe sind getestet; vollständige SwiftPM-/Xcode-/Release-Prüfung grün, Live-Lastlauf offen |
| 5 | umgesetzt; automatisch und synthetisch lastgemessen | ESI-Arbeit global begrenzen und priorisieren; Caches nach Nutzung und bei Speicherdruck gezielt freigeben | gemeinsame Grenze von sechs Transportanfragen und engeres Zwei-Anfragen-Limit für Automatik; interaktive Priorität, Abbruch, Retry-Freigabe, Header und LRU-Trimmung getestet; 120-Anfragen-Lauf in 0,203 Sekunden mit rund 65,8 MiB Testprozess-RSS und ohne Swap; 289 SwiftPM- sowie 278 native Xcode-Tests und universeller Release-Build grün, mehrstündiger Live-Lauf offen |
| 5a | umgesetzt; automatisch und synthetisch lastgemessen | Public-Contracts-SQLite-Statements pro Verbindung wiederverwenden, Ergebniszeilen günstiger dekodieren und ausschließlich nachweislich unerreichbaren Code entfernen | identischer 10.000-Verträge-Lauf von 0,13946 auf 0,05902 Sekunden verkürzt; vollständiger SwiftPM-Lauf mit 313 Tests, separates EVEStaticDataKit mit 6 Tests und unsigned Xcode mit 299 Core-Tests grün; Live-ESI-, Langzeit-CPU/RSS- und visuelle Abnahme offen |
| 6 | offen | SDE-Speicher auf aktiven Stand plus einen geprüften Rollback-Stand begrenzen; Speicherplatz vor Updates prüfen | nur Vorschau vor Bereinigung; Aktivierung/Rollback getestet; Löschung erst nach Freigabe |

## Tokensparende Prompts

Einmalig als Grundsatz verwenden:

> Lies `AGENTS.md` und `Optimierung.md`. Bearbeite nur den genannten Punkt.
> Fachlogik und Quellzustände bleiben unverändert. Aktualisiere Tests und
> Dokumentation. Nichts committen oder pushen.

Danach genügt jeweils eine Zeile:

1. `Prüfe Punkt 1 aus Optimierung.md vollständig und schließe offene Tests ab.`
2. `Führe Punkt 2 aus Optimierung.md vollständig aus.`
3. `Führe Punkt 3 aus Optimierung.md vollständig aus.`
4. `Führe Punkt 4 aus Optimierung.md vollständig aus.`
5. `Führe Punkt 5 aus Optimierung.md vollständig aus.`
6. `Führe Punkt 6 aus Optimierung.md nur bis zur Bereinigungsvorschau aus; vor jeder Löschung Freigabe einholen.`

Für den nächsten Schritt reicht daher künftig zum Beispiel: `Führe Punkt 2 aus.`
