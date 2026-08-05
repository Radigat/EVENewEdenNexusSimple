# EVE Nexus Simple – Dokumentation

Stand: 5. August 2026

## Zweck und Zielgruppe

EVE Nexus Simple ist eine lokale, native macOS-Anwendung zur Planung und
Bewertung von Industrie-, Markt- und Bestandsvorgängen in EVE Online. Die App
führt statische Spieldaten aus dem SDE, öffentliche und autorisierte ESI-Daten
sowie lokale Planungs- und Konfigurationsdaten zusammen.

Diese Dokumentation richtet sich an Anwenderinnen und Anwender, Entwickler und
Personen, die Builds oder Datenmigrationen prüfen. Sie beschreibt den aktuellen
Projektaufbau, den vorgesehenen Betrieb und die Grenzen der Anwendung. Die
chronologische Entwicklung steht im [Entwicklungstagebuch](dev-diary.md).
Verbindliche Detailverträge und Prüfnachweise liegen unter
[`Documentation/`](Documentation/).

## Projektstatus und Nachweise

Das Repository enthält eine ausführbare SwiftUI-App, eine wiederverwendbare
Core-Bibliothek, ein Live-Acceptance-Werkzeug und automatisierte Tests. Der
aktuelle lokale Arbeitsbaum enthält noch nicht abgeschlossene Änderungen. Ein
vorher dokumentierter erfolgreicher Build oder Testlauf belegt deshalb nicht
automatisch jede nachfolgende lokale Änderung.

Statusangaben werden in fünf Ebenen getrennt:

| Ebene | Bedeutung | Maßgebliche Quelle |
| --- | --- | --- |
| Spezifiziert | Verhalten oder Vertrag ist beschrieben | [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md) und Fachverträge |
| Implementiert | Quellcode oder Persistenzmodell ist vorhanden | `Sources/` und `Packages/` |
| Automatisch geprüft | Ein benannter Test- oder Buildlauf war erfolgreich | [`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md) |
| Live geprüft | Ein konkreter SDE-/ESI-Stand oder EVE-Vorgang wurde geprüft | datierter Eintrag in der Acceptance-Matrix |
| Vom Eigentümer abgenommen | Verhalten wurde in der laufenden App fachlich oder visuell bestätigt | ausdrücklich dokumentierter Owner-Nachweis |

Offene Felder bleiben offen. Automatische Tests ersetzen weder einen aktuellen
Live-ESI-Vergleich noch die visuelle, barrierearme und fachliche Abnahme in der
laufenden App.

## Technische Basis

- Swift 6 und Swift Package Manager
- SwiftUI für eine native macOS-Oberfläche ab macOS 14
- SwiftData für anwendungseigene Einstellungen, Snapshots, Pläne und Historien
- SQLite für aktivierte SDE-Kataloge und den öffentlichen Contract-Index
- lokales Paket `Packages/EVEStaticDataKit` für die SDE-Verarbeitung
- EVE SSO mit Authorization Code und PKCE; Refresh Tokens ausschließlich im
  macOS-Schlüsselbund
- ESI-Transport mit Pagination, Cache-, Fehlerbudget-, Retry- und
  Provenienzbehandlung
- deutsche und englische Lokalisierung

Das Swift-Paket stellt folgende Produkte bereit:

| Produkt | Aufgabe |
| --- | --- |
| `EVENexusCore` | Domänenmodelle und Dienste ohne SwiftUI-Abhängigkeit |
| `EVE Nexus Simple` | native macOS-Anwendung |
| `EVENexusLiveAcceptance` | bewusst getrennte Live-Prüfungen |

## Architektur

Die zentrale Trennung lautet:

| Schicht | Verantwortung | Darf nicht übernehmen |
| --- | --- | --- |
| SDE | statische Typen, Blueprints, Aktivitäten, Dogma- und Volumendaten | Live-Marktdaten oder Anmeldung |
| Auth | SSO, PKCE, Scopes, Token-Lebenszyklus und Keychain | ESI-Fachdaten |
| ESI | HTTP-Transport, Paging, Cache, Rate Limits und Antwortprovenienz | fachliche Persistenz oder UI |
| Domänen | Charaktere, Assets, Blueprints, Markt, Contracts, Reaktionen und Industrie | Token- oder Netzwerkimplementierung |
| Persistenz | versionierte lokale Snapshots, Pläne, Einstellungen und Wiederherstellung | Erfinden fehlender Quelldaten |
| App/UI | Navigation, Darstellung, Eingabe, Fortschritt und Abbruch | Netzwerk-, Token- oder Kalkulationslogik |
| Tests/Dokumentation | reproduzierbare Nachweise, Verträge und offene Abnahmen | Behauptung ungeprüfter Laufzeitwirkung |

Die vollständige Verantwortungsmatrix und die domänenübergreifenden Übergaben
stehen in [`Documentation/ARCHITECTURE.md`](Documentation/ARCHITECTURE.md) und
[`Documentation/HANDOFFS.md`](Documentation/HANDOFFS.md). Die grundlegende
Entscheidung für eine lokale, native und modulare App dokumentiert
[`Documentation/ADR-001-local-native-modular.md`](Documentation/ADR-001-local-native-modular.md).

### Datenzustände

Quellen können `fresh`, `partial`, `stale`, `forbidden` oder `unavailable`
sein. Unaufgelöste Namen, fehlende Markttiefe, fehlende Berechtigungen und
fehlende Preise bleiben eigene Zustände. Sie dürfen weder als Nullwert noch als
leere, aber vollständige Datenmenge ausgegeben oder berechnet werden.

Jeder domänenübergreifende Snapshot soll mindestens Quellidentität, Zeitpunkt,
Schema- oder Kompatibilitätsstand, Aktualität und mögliche Teilfehler bewahren.
SDE-Definitionen, ESI-Live-Daten und lokale Annahmen bleiben unterscheidbar.

## Funktionsbereiche

Die Navigation bildet die folgenden Arbeitsbereiche ab:

| Bereich | Zweck und wesentliche Grenze |
| --- | --- |
| Dashboard | verdichteter Überblick über Jobs, Finanzen, Markt und Automatisierungszustände |
| Industry Jobs | gespeicherte Charakter-Jobs mit Aktivität, Status, Zeitpunkt und expliziten Quellenlücken |
| Planner | Produktionsgraph, Build/Buy/Warehouse-Auswahl, Installation, Logistik, Gebühren, Erlös, Profit und ROI |
| Market Browser | öffentliche Kauf- und Verkaufsorders über Regionen mit Quellen- und Ortsauflösung |
| Main Hub Opportunities | Fertigungskandidaten und rekursiver Produktionsbaum für den exakt konfigurierten Main Hub |
| Public Contracts | lokaler, resumierbarer Index öffentlicher ESI-Contracts mit sicherem Stopp und Teilstatus |
| Reactions | veröffentlichte Reaktionsrezepte, vollständige Batch-Kosten, Logistik und Make-or-Buy-Vergleich |
| Moon purchase analysis | Mengen- und Preisvergleich ausgewählter Marktrollen für Mondmaterialien; vollständiger Tabellenexport als PNG |
| All items | faktische persönliche und optional autorisierte Corporation-Bestände an allen bekannten Orten |
| Warehouse | nur planungsfähiger Bestand an exakt konfigurierten Produktionsorten, abzüglich Schutzbeständen und Reservierungen |
| Blueprints | persönliche BPO/BPC-Instanzen, Runs, ME/TE und belegte Forschungskostenschätzung |
| Production Overview | gespeicherte Produktionshistorie mit editierbaren Verkaufsdaten und explizit unbekannten Kosten |
| Wallet | persönliche Wallet-Salden je verbundenem Charakter |
| Net Worth | tägliche lokale Bewertung von Wallet, Assets, Orders, Contracts und zugänglichen Corporation-Anteilen |
| Data & Settings | allgemeine Darstellung, SDE, ESI, Industrie- und Marktkonfiguration |

Die Benutzeroberfläche verwendet für sichtbare EVE-Namen die gemeinsame
Komponente `EVEEntityText` beziehungsweise die passende Label-Variante. Namen
sind direkt kopierbar, ohne gleichzeitig Zeilenwahl, Disclosure oder
Doppelklick-Aktionen auszulösen. Tabellarische Peer-Daten besitzen sortierbare
Spaltenköpfe mit stabiler Sortierung und expliziter Behandlung fehlender Werte.

## Zentrale Fachregeln

### Marktrollen und Preise

Main Hub, Home Hub und Coalition Hub sind getrennte Rollen. Der Main Hub ist
die Quelle für Planner-Käufe und Multibuy-Listen. Produktions- und
Verkaufslogistik richtet sich nach den exakten konfigurierten Ortskennungen.
Ein gleicher Start- und Zielort erzeugt keinen Transportweg. Player-Structure-
Märkte bleiben ohne passende Berechtigung oder Dockingzugriff unverfügbar.

Preisentscheidungen verwenden die benötigte Gesamtmenge und die verfügbare
Markttiefe. Einzelpreise, SDE-Basispreise oder ESI-Adjusted-Prices sind kein
Ersatz für eine unvollständige Marktquote. Kosten, Ersatzwert, unmittelbarer
Zahlungsbedarf, Logistik, Steuern/Gebühren, Erlös, Wertschöpfung, Profit, Marge
und ROI bleiben getrennt nachvollziehbar.

### Assets und Warehouse

`All items` zeigt faktischen Bestand. `Warehouse` ist eine Planungsprojektion
für exakt konfigurierte Produktionsorte. Schiffe und deren verschachtelte
Inhalte sind nicht als Produktionsmaterial verfügbar; normale Hangarcontainer
können verfügbar bleiben. Schutzbestände werden vom faktischen Bestand
abgezogen, aktive Reservierungen anschließend von der planbaren Menge.

Corporation-Bestände benötigen die vorgesehenen Scopes und Rollen und werden
je Corporation dedupliziert. Fehlende Rechte ergeben keinen scheinbar leeren
Hangar.

### Blueprints, Industrie und Reaktionen

BPO und BPC bleiben unterschiedliche Instanzen mit eigener Herkunft. Eine BPC
kann als verbrauchter Erwerbspreis, eine BPO nur mit einer expliziten lokalen
Kostenallokation in einen Plan eingehen. Unbekannte Blueprint- oder
Forschungskosten werden nicht zu null.

Der Planner friert eine berechnete Planung als unveränderlichen Snapshot ein.
Ein gekaufter oder aus dem Warehouse verwendeter Zwischenstoff entfernt seinen
Produktionszweig und den zugehörigen Job. Make-or-Buy vergleicht vollständige
Bedarfs- und Batchmengen einschließlich belegter Installation und Logistik.
Reaktionen verwenden veröffentlichte SDE-Formeln; fehlende Markt-, Volumen-,
Kollateral- oder Tarifdaten machen den betroffenen Vergleich unverfügbar.

Der ausführliche Produktionsvertrag steht in
[`Documentation/PRODUCTION_BASIS.md`](Documentation/PRODUCTION_BASIS.md).

## Lokale Daten, Sicherheit und Wiederherstellung

- Refresh Tokens liegen ausschließlich im macOS-Schlüsselbund. Ein Client
  Secret wird nicht verwendet.
- Der ESI-/SDE-User-Agent verwendet die ausdrücklich öffentliche
  Projekt-Kontaktadresse `projekt-st@gmx.de`. Sie ist keine Anmeldeinformation,
  wird im Build als Fallback mitgeführt und kann für lokale Entwicklung über
  `EVE_NEXUS_CCP_USER_AGENT_CONTACT` überschrieben werden.
- Die primäre SwiftData-Datenbank besitzt einen stabilen Pfad unter der
  Anwendungskennung. Schemaänderungen werden versioniert migriert.
- Vor einer Migration wird eine Sicherheitskopie angelegt. Ein Legacy-Store
  wird nur dann kopiert, wenn noch kein kanonischer Store existiert, und nicht
  automatisch gelöscht.
- SDE-Kandidaten werden validiert und erst nach einer bestätigten Vorschau
  atomar aktiviert. Ein älterer Metadatenstand darf kein Downgrade auslösen.
- Öffentliche Contract-Imports sind opt-in, zeigen Fortschritt und Teilstatus,
  können sicher gestoppt werden und bewahren einen letzten erfolgreichen Stand.
- Solange der Erstimport aller zu diesem Zeitpunkt noch bestehenden öffentlichen
  Verträge unvollständig ist, zeigt der Bereich **Public Contracts** einen nicht
  einklappbaren, fett und rot hervorgehobenen Warnhinweis. Der Hinweis nennt die
  derzeit zu erwartenden zwei bis drei Tage Laufzeit, die automatische
  Fortsetzung im Hintergrund und nach einem App-Neustart sowie die währenddessen
  deutlich eingeschränkte Nutzbarkeit. Die Importleistung wird weiter optimiert.
- Diagnoseausgaben und Dokumentation dürfen keine Tokens, Secrets oder private
  ESI-Nutzdaten enthalten.
- Löschen, Ersetzen, Migration, Token-Widerruf und andere schwer rückgängig zu
  machende Aktionen benötigen eine klar erkennbare Zielmenge und Bestätigung.

Die datierte Sicherheitsbewertung steht in
[`Documentation/SECURITY_AUDIT_2026-07-30.md`](Documentation/SECURITY_AUDIT_2026-07-30.md).

## Installation und Entwicklung

Voraussetzungen sind macOS 14 oder neuer, eine passende Xcode-Version mit
Swift 6 sowie `xcodegen` für die Erzeugung des nativen Projekts.

Projekt erzeugen und in Xcode öffnen:

```sh
xcodegen generate
open EVENexusSimple.xcodeproj
```

Deterministische SwiftPM-Tests:

```sh
swift test
```

Unsigned Xcode-Testlauf:

```sh
xcodebuild -project EVENexusSimple.xcodeproj \
  -scheme EVENexusSimple \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/EVENexusSimpleDerivedData \
  test CODE_SIGNING_ALLOWED=NO
```

Falls SwiftPM oder Clang wegen nicht beschreibbarer Cache-Verzeichnisse mit
`Operation not permitted` scheitert, müssen Scratch-, Module-Cache-,
DerivedData- und gegebenenfalls Paketverzeichnisse unter einen beschreibbaren,
isolierten Pfad wie `/private/tmp` gelegt werden. Ein Sandboxfehler ist getrennt
von einem Quellcode- oder Testfehler zu dokumentieren.

Live-SDE-/ESI-Prüfungen sind bewusst opt-in. Sie dürfen keine echten
Zugangsdaten in Fixtures übernehmen und zählen nicht zu den deterministischen
Standardtests.

## Konfiguration und typischer Arbeitsablauf

1. App bauen und starten.
2. Unter **Data & Settings → SDE** den installierten Katalog prüfen und ein
   Update nur nach Vorschau und Schemafreigabe aktivieren.
3. Unter **Data & Settings → ESI** einen Charakter per EVE SSO autorisieren.
   Jeder Charakter benötigt seine eigene Auswahl und Zustimmung im Browser.
4. Synchronisation ausführen und Teil-, Rechte- oder Fehlerzustände prüfen.
5. Unter **Industry Settings** Produktionsorte, Aktivitäten, Steuern,
   Zuschläge und Logistik konfigurieren.
6. Unter **Market Settings** Main, Home und gegebenenfalls Coalition Hub sowie
   Trader- und Gebührennachweise festlegen.
7. Bestände und Blueprints prüfen, Schutzbestände setzen und erst danach planen.
8. Im Planner Marktdeckung, Produktionszweige, Kostenbestandteile und
   Warnungen prüfen; Empfehlungen bleiben übersteuerbar.
9. Produktion nur nach erneuter Kontrolle als historischen Datensatz erfassen.

## Bekannte Grenzen

- Die App installiert keine Jobs im EVE-Client und verändert keine Ingame-
  Assets oder Orders.
- Science-Jobplanung für Invention, Copying und Forschung ist noch nicht als
  vollständiger ausführbarer Planer belegt.
- ESI liefert keine allgemeine Liste aller Player Structures mit Dockingrecht
  und keine vom Eigentümer festgelegte Structure-Brokergebühr.
- Öffentliche Marktorders sind keine abgeschlossene Verkaufshistorie.
- Preis-, Status-, Rollen- und Strukturzugriffe können sich ändern; datierte
  Live-Nachweise sind keine dauerhafte Garantie.
- Signierung, Notarisierung, Langzeit-RSS/CPU, vollständige Tastatur- und
  VoiceOver-Prüfung sowie die visuelle Owner-Abnahme bleiben eigenständige
  Freigabeschritte, sofern die Acceptance-Matrix sie nicht ausdrücklich als
  abgeschlossen ausweist.

## Pflege dieser Dokumentation

`dokumentation.md` ist die aktuelle, autoritative Einstiegssicht. Jede
Implementierung, Fehlerbehebung, Migration, Konfigurations- oder wesentliche
Verhaltensänderung aktualisiert sie im selben Arbeitsschritt. Historische oder
ersetzte Aussagen werden nicht als aktuelles Verhalten stehen gelassen, sondern
im [Entwicklungstagebuch](dev-diary.md) eingeordnet.

Ein Diary-Eintrag nennt Datum, Ziel, Änderung, Ergebnis, konkrete Prüfung und
offene Arbeit. Prüfergebnisse werden zusätzlich in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md) gepflegt; neue oder
geänderte Modulübergaben gehören nach
[`Documentation/HANDOFFS.md`](Documentation/HANDOFFS.md). Architekturänderungen
werden nicht still überschrieben, sondern durch ein neues oder ablösendes ADR
dokumentiert.

## Weiterführende Dokumente

- [README](README.md) – kompakte Start- und Funktionsbeschreibung
- [Architektur](Documentation/ARCHITECTURE.md) – Modulgrenzen und Fachverträge
- [Acceptance-Matrix](Documentation/ACCEPTANCE.md) – datierte automatisierte,
  Live- und Owner-Nachweise
- [Handoffs](Documentation/HANDOFFS.md) – Übergaben zwischen EVE-Domänen
- [ADR-001](Documentation/ADR-001-local-native-modular.md) – lokale native
  Architekturentscheidung
- [Production Basis](Documentation/PRODUCTION_BASIS.md) – verbindlicher
  Produktions-, Kosten- und Logistikvertrag
- [Invention Skill Matrix](Documentation/INVENTION_SKILL_MATRIX.md) –
  belegter Stand der Invention-Skill-Zuordnung
- [Security Audit](Documentation/SECURITY_AUDIT_2026-07-30.md) – datierte
  Sicherheits- und Robustheitsprüfung
