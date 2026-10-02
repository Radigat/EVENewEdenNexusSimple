# EVE Nexus Simple – Entwicklungstagebuch

Dieses Tagebuch dokumentiert die Entwicklungsschritte in zeitlicher Reihenfolge.
Es ist keine zweite Spezifikation: Das aktuell gültige Verhalten steht in
[`dokumentation.md`](dokumentation.md), die detaillierten Prüfbelege in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md).

Die Einträge bis zum 1. August stützen sich auf die Git-Historie. Die danach
aufgeführten Schritte sind aus den datierten Architektur-, Handoff- und
Acceptance-Nachweisen des aktuellen lokalen Arbeitsstands rekonstruiert. Da
dieser Arbeitsstand noch nicht vollständig eingecheckt ist, beschreibt die
Reihenfolge Themenblöcke und nicht zwingend einzelne Commits.

## 5. August 2026 – Deutlicher Laufzeithinweis beim Contract-Erstimport

Ziel: Die praktisch beobachtete Belastung durch den Erstimport öffentlicher
Verträge vor und während des lang laufenden Vorgangs unmissverständlich machen.

Entwicklung:

- den bisherigen einklappbaren und zu optimistischen Zeithinweis durch einen
  dauerhaft sichtbaren, fett und rot gestalteten Warnkasten ersetzt;
- erwartete Laufzeit von zwei bis drei Tagen für alle zu Importbeginn noch
  bestehenden Verträge sowie Fortsetzung im Hintergrund und nach App-Neustart
  benannt;
- deutliche Verlangsamung und nur eingeschränkte Nutzbarkeit während des
  Erstimports sowie die fortlaufende Optimierung ausdrücklich dokumentiert;
- deutsche und englische Lokalisierung ergänzt.

Ergebnis: Der Warnhinweis bleibt sichtbar, solange Regions- oder
Vertragsdetail-Erstimport noch unvollständig sind. Er enthält keine Behauptung,
dass die Anwendung währenddessen normal schnell oder uneingeschränkt nutzbar
sei.

Prüfung: `swift format lint --strict` für die geänderte Swift-Datei und
`plutil -lint` für beide Lokalisierungskataloge bestanden. Der isolierte
SwiftPM-Lauf baute die vollständige App und bestand 260 Tests in 21 Suites. Der
erste Lauf erreichte wegen des bekannten nicht beschreibbaren globalen
Clang-Modulcaches noch keinen Build; die Wiederholung mit Cache- und
Scratch-Pfaden unter `/private/tmp` war erfolgreich.

Offen: Visuelle Prüfung in heller und dunkler Darstellung sowie Owner-Abnahme
des Warntextes in der laufenden App; weitere Laufzeit-, CPU-, Speicher- und
Bandbreitenoptimierung des Erstimports.

## 30. Juli 2026 – Projektvorbereitung und Sicherheitsrahmen

Ziel: Eine prüfbare Grundlage für die native EVE-Anwendung schaffen.

Entwicklung:

- erster Testplatzhalter im Repository;
- Sicherheits- und Robustheitsprüfung für lokale Daten, Tokens, Netzwerkgrenzen
  und Fehlerbehandlung;
- Trennung der Nachweise in Spezifikation, Implementierung, automatische Tests,
  Live-EVE-Prüfung und Owner-Abnahme.

Ergebnis: Der Sicherheitsrahmen und die später verwendete Acceptance-Struktur
waren definiert. Offene Punkte wie stabile Signierung, Notarisierung und
visuelle Abnahme blieben ausdrücklich getrennt.

Nachweis: Git-Commit `64f7202` und
[`Documentation/SECURITY_AUDIT_2026-07-30.md`](Documentation/SECURITY_AUDIT_2026-07-30.md).

## 31. Juli 2026 – Native Basis und modulare Datenwege

Ziel: Eine lauffähige Swift-6-/SwiftUI-Anwendung mit klaren EVE-Domänengrenzen
aufbauen.

Entwicklung:

- Swift Package mit `EVENexusCore`, App-Target und Live-Acceptance-Target;
- lokale native Architektur für SDE, Auth, ESI, Charaktere, Assets,
  Blueprints, Markt, Reaktionen und Industrie;
- EVE SSO mit PKCE und Refresh-Token-Speicherung im Schlüsselbund;
- paginierter ESI-Transport mit Cache-, Fehler- und Provenienzmodell;
- SDE-Download, Validierung, SQLite-Aktivierung und Abfrage über das lokale
  `EVEStaticDataKit`;
- erste Planungs-, Synchronisations- und UI-Abläufe.

Ergebnis: Die Anwendung konnte Domänendaten getrennt beziehen und für Planung
und Darstellung zusammensetzen. Fehlende oder verbotene Daten wurden als
Zustand modelliert und nicht als Nullwert ausgegeben.

Nachweis: Git-Commits `8e5dafc` und `bee9a6a`,
[`Documentation/ADR-001-local-native-modular.md`](Documentation/ADR-001-local-native-modular.md)
und [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md).

## 1. August 2026 – Produktionsgrundlage, Persistenz und Bestände

Ziel: Die Industrieplanung von einer Eingabemaske zu einem nachvollziehbaren,
persistierten Arbeitsablauf erweitern.

Entwicklung:

- Produktionsbasis mit Anlagen, Systemindizes, Steuern, Zuschlägen und
  Logistikparametern;
- persistierter Planner-Entwurf und unveränderliche berechnete Pläne;
- Produktionsübersicht mit Kosten-, Mengen-, Verkaufs- und Profiterfassung;
- persönlicher Asset-Bestand, Warehouse-Projektion, Schutzbestände und
  Reservierungen;
- Blueprints mit BPO/BPC-, ME/TE- und Forschungswert-Semantik;
- belastbarere App-Datenpfade, Sicherung und Wiederherstellung.

Ergebnis: Planner, Warehouse und Produktionshistorie teilten einen
quellenbewussten Datenvertrag. Faktischer Bestand, geschützter Bestand und
planbare Verfügbarkeit blieben unterscheidbar.

Nachweis: Git-Commit `c50e005`,
[`Documentation/PRODUCTION_BASIS.md`](Documentation/PRODUCTION_BASIS.md) und
die datierten Einträge in der Acceptance-Matrix.

## 2. August 2026 – Marktrollen, Analysen und Corporation-Daten

Ziel: Markt- und Produktionsentscheidungen auf exakte Orte, vollständige Mengen
und explizite Berechtigungen stützen.

Entwicklung:

- Trennung von Main Hub, Home Hub und Coalition Hub;
- ortsgebundene Trader-, Steuer- und Brokergebühren-Nachweise;
- Mondmaterial-Kaufanalyse einschließlich vollständigem PNG-Tabellenexport;
- Main-Hub-Fertigungschancen und rekursiver Produktionsbaum;
- Corporation-Assets mit Director-/Scope-Prüfung, Divisionen und
  Deduplizierung je Corporation;
- vollständige Reaktionsanalyse mit Installation, Inbound-Logistik,
  Batch-Mengen und Make-or-Buy;
- öffentlicher Contract-Index mit resumierbarer Synchronisation, Teilstatus,
  Rate-Limit-Beachtung und sicherem Stopp.

Ergebnis: Markt- und Produktionsvergleiche verwendeten vollständige Mengen und
behielten unvollständige Markttiefe, fehlende Rollen und fehlende
Structure-Zugriffe als Blocker. Ein unbekannter Wert wurde nicht zu einer
scheinbar sicheren Null.

Prüfung: Deterministische Fachtests und native Builds sind in den Abschnitten
vom 2. August in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md) protokolliert.

Offen: Live-Abgleich von Corporation-Hangars und privaten Structure-Märkten,
vollständiger Contract-Erstimport sowie visuelle und barrierearme Owner-Abnahme.

## 3. August 2026 – Gemeinsame EVE-Interaktion und breitere Marktoberfläche

Ziel: Wiederkehrende UI-Regeln appweit vereinheitlichen und die Analyseflächen
ausbauen.

Entwicklung:

- gemeinsame `EVEEntityText`-/`EVEEntityLabel`-Darstellung für direkt
  kopierbare EVE-Namen mit lokalisierter Rückmeldung;
- Schutz vor unbeabsichtigter Zeilenauswahl, Disclosure- oder
  Doppelklick-Auslösung beim Kopieren;
- sortierbare Tabellenköpfe mit typisierter Sortierung, stabiler Tie-Breaker-
  Regel und expliziter Anordnung fehlender Werte;
- regionsübergreifender Market Browser mit Käufer-/Verkäuferansichten,
  Standort- und Security-Auflösung sowie Teilquellenstatus;
- Dashboard-Struktur und verbesserte Navigation;
- technische Metadaten aus der Normalansicht entfernt, ohne ihre
  Datenherkunft oder Fehlerzustände zu verlieren.

Ergebnis: EVE-Namen und Datentabellen erhielten appweit konsistente
Interaktionsverträge. Markt- und Herkunftsdaten blieben trotz kompakterer UI
prüfbar.

Prüfung und offene Owner-Schritte:
[`Documentation/HANDOFFS.md`](Documentation/HANDOFFS.md), Abschnitte „Shared
EVE entity presentation“ und „Dashboard“, sowie die zugehörige
Acceptance-Matrix.

## 4. August 2026 – Dashboard, Jobs, Net Worth und Hintergrundarbeit

Ziel: Den laufenden Betrieb und die finanzielle Gesamtsicht transparenter und
ressourcenschonender machen.

Entwicklung:

- Dashboard-Gruppen für Industrie/Jobs, Finanzen und Markt/Chancen;
- Industry-Jobs mit gespeicherten Aktivitäts-, Status-, Zeit- und
  Anlageninformationen;
- Net-Worth-Historie mit persönlichen und zugänglichen Corporation-Anteilen,
  Orders, Contracts, Escrow und expliziten Preis- oder Rechte-Lücken;
- getrennte Main-/Home-Hub-Verkaufsszenarien einschließlich Hin- und
  Rücklogistik;
- explizites Opt-in, Zeitplanung, Fortschritt und Pause/Fortsetzung für
  automatische Markt- und Contract-Aktualisierungen;
- Speicher- und Request-Begrenzungen für große öffentliche Contract- und
  Marktdatenmengen.

Ergebnis: Hintergrundarbeit wurde sichtbar und steuerbar. Finanzwerte wurden
in Komponenten zerlegt; Blueprint Copies, unbewertete Typen, fehlende Rollen
und Teilimporte blieben vom bekannten Teilwert getrennt.

Prüfung: Datierte Dashboard-, Net-Worth- und Dual-Hub-Nachweise in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md).

Offen: reale Mehrtageshistorie, Langzeit-CPU/RSS, aktuelle private ESI-Daten,
Tastatur/VoiceOver und finale Layout-Abnahme.

## 5. August 2026 – Kanonische Persistenz und Dokumentationspflege

Ziel: Bestehende Nutzerdaten bei unterschiedlichen Startwegen und
Schemaänderungen schützen und die Projektkenntnis zentral auffindbar machen.

Entwicklung:

- stabiler, von SwiftPM-/Xcode-Startnamen unabhängiger SwiftData-Pfad;
- explizite V1-zu-V2-Migration, Sicherung des Legacy-Stores und geschützte
  einmalige Zusammenführung neuerer Teildaten;
- stabiler `UserDefaults`-Bereich mit einmaliger Übernahme alter App-Werte;
- privater, in den Build integrierter CCP-Operator-Kontakt mit lokaler
  Entwicklungsüberschreibung statt normalem UI-Feld;
- zentrale deutschsprachige [`dokumentation.md`](dokumentation.md);
- dieses Entwicklungstagebuch;
- verbindliche Regel zur stetigen Dokumentationspflege in [`AGENTS.md`](AGENTS.md).

Ergebnis: Die Wiederherstellungs- und Migrationsgrenze ist dokumentiert, ohne
Keychain-Tokens mit SwiftData zu vermischen. Aktueller Betrieb, historische
Entwicklung und Prüfnachweise besitzen nun getrennte, verlinkte Einstiegspunkte.

Dokumentierter Prüfstand vor dieser Doku-Änderung: Eine geschützte Kopie und der
aktivierte kanonische Store bestanden die SQLite-Integritätsprüfung; SwiftPM
bestand 260 Tests und der unsigned native Xcode-Build war erfolgreich. Diese
Nachweise gelten für den in der Acceptance-Matrix bezeichneten Stand und nicht
automatisch für spätere lokale Änderungen.

Offen: Normalstart der bevölkerten App mit visueller Prüfung aller erwarteten
Charakter-, Markt-, SDE- und Einstellungsdaten; Signierung, Notarisierung und
Release-Abnahme.

## 5. August 2026 – Öffentliche Projekt-Kontaktadresse

Ziel: Den zuvor privaten CCP-Operator-Kontakt durch eine ausdrücklich zur
Veröffentlichung freigegebene Projektadresse ersetzen.

Entwicklung:

- eingebauten ESI-/SDE-User-Agent-Fallback auf `projekt-st@gmx.de` geändert;
- Architektur-, Betriebs- und Übergabedokumentation vom privaten auf den
  öffentlichen Kontaktvertrag aktualisiert;
- lokale Umgebungsüberschreibung und versteckten Legacy-Fallback unverändert
  beibehalten.

Ergebnis: Die Projektadresse darf im öffentlichen Repository und als
User-Agent-Kontakt sichtbar sein. Sie bleibt von SSO, Tokens und sonstigen
Anmeldeinformationen getrennt.

Prüfung: Der isolierte SwiftPM-Lauf baute die App einschließlich
`AppOperatorConfiguration.swift`; 58 fokussierte ESI-, Wallet- und
Dashboard-Tests in drei Suites bestanden. `git diff --check` und die Prüfung
auf verbliebene aktuelle Vorkommen der ersetzten Adresse ergänzen diesen
Nachweis.

Offen: Das Projektpostfach muss dauerhaft erreichbar und überwacht bleiben.

## 5. August 2026 – Swift-6.1-Kompatibilität der GitHub-CI

Ziel: Den fehlgeschlagenen öffentlichen GitHub-Actions-Check auf derselben
Swift-Werkzeugkette reproduzierbar kompilierbar machen, ohne Fachverhalten oder
Persistenzschema zu ändern.

Entwicklung:

- die CI-Diagnosen des Laufs `30987413552` gegen den lokal grünen Stand
  abgegrenzt: GitHub verwendete Swift 6.1.2, lokal lief Swift 6.3.3;
- gespeicherte statische SwiftData-Schemametadaten in berechnete statische
  Werte mit unveränderten V1-/V2-Kennungen und unveränderter Migrationsfolge
  überführt;
- vier für Swift 6.1 zu komplexe SwiftUI-Identitäts- und Triggerausdrücke in
  explizit typisierte Teilwerte zerlegt, ohne Felder, Reihenfolge oder Trenner
  zu verändern;
- nach dem dadurch erstmals vollständigen CI-Build die zwei verbleibenden
  Statusseiten-Tests abgegrenzt: Foundation unter Swift 6.1 verwarf den
  offiziellen ISO-8601-Zeitstempel mit Sekundenbruchteilen;
- den Statusseiten-Decoder auf eine explizite Strategie für Zeitstempel mit und
  ohne Sekundenbruchteile umgestellt und beide Formen durch Fixtures belegt;
- Architektur-, Betriebs- und Acceptance-Dokumentation um die öffentliche
  CI-Kompatibilitätsgrenze ergänzt.

Ergebnis: Die bekannten Fehler sind als Compiler-/SDK-Kompatibilitätsprobleme
behoben. Die Persistenz- und UI-Refaktorierungen führen weder eine neue
Migration noch neue UI- oder Domänenlogik ein; der Statusseiten-Decoder bildet
die beiden gültigen Zeitstempelformen jetzt unabhängig von der Toolchain ab.

Prüfung: `git diff --check` und striktes `swift-format` bestanden. Die
isolierten SwiftPM- und unsigned nativen Xcode-Läufe bauten die Anwendung und
bestanden auf dem korrigierten Stand jeweils 261 Tests in 21 Suites. Der erste
Ersatzlauf `30989387141` auf GitHub baute unter Swift 6.1.2 vollständig und
startete alle damals 260 Tests; nur die zwei anschließend behobenen
Zeitstempel-Decodierungen schlugen fehl.

Offen: Der neue öffentliche GitHub-Actions-Lauf wird nach dem Push dieses
dokumentierten Stands erneut ausgeführt.

## Vorlage für neue Einträge

```markdown
## JJJJ-MM-TT – Kurzer Titel

Ziel: Welches Problem oder welcher Nutzerablauf wurde bearbeitet?

Entwicklung:

- konkrete Änderung und betroffene Module;
- geänderte Daten-, Sicherheits- oder Migrationsgrenzen;
- aktualisierte Verträge und Dokumente.

Ergebnis: Was ist jetzt implementiert oder entschieden?

Prüfung: Exakter Test-, Build-, Live- oder Owner-Nachweis. Nicht ausgeführte
Ebenen ausdrücklich offen lassen.

Offen: Restarbeit, Risiken, Migration, Live-Abgleich und Owner-Abnahme.
```
