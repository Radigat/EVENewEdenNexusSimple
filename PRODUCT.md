# EVE New Eden Nexus - Assets, Industry, Markets – Dokumentation

> Konsolidiert am 25.09.2026. Verbindlicher Status: [PROJECT_STATE.md](PROJECT_STATE.md).
> Fachbeschreibung aus dem aktuellen lokalen Stand vollständig erhalten; historische
> Testzahlen sind datierte Nachweise, keine neue Gesamtabnahme.

Aktueller Konsolidierungsstand: 25. September 2026

## Zusammengeführte vorhandene Fachabläufe

Der Planner rechnet direkt: Produkt und Menge eintragen, berechnen. Grundlage sind der ESI-Bestand nach
der bestehenden Schutzmengenberechnung und die Planner-Handeingabe. Eingabe, Handbestand und aktiver Plan
werden im Planner-Entwurf gespeichert und beim Start wiederhergestellt. Fertigungsprojekte, Projektreservierungen
sowie Einkaufsbudget und -fortschritt gibt es nicht. Manuelle Lager fließen nicht in die Planberechnung ein.
Warehouse öffnet **Manuelle Lager**, Blueprints **Wissenschaftsaufträge** und die
Produktionsübersicht **Verkaufsbelege**. Die früheren gemeinsamen Einstiege **Projekte & Einkauf**
und **Preisprofile & Sicherung** samt Projektverwaltungsdialog sind entfernt; Sicherung,
Wiederherstellung und Diagnose liegen in **Daten & Einstellungen → Allgemein**. Manuelle
Preisprofile gibt es nicht mehr. Alle Arbeitsbereiche verwenden denselben lokalen
Datenbestand. Früher gespeicherte Projekt-, Reservierungs-, Einkaufs- und Preisprofildatensätze bleiben
als nicht mehr verwendete Altdaten unverändert erhalten ([Entscheidung](Documentation/Consolidation/DECISIONS.md)).

Manuelle Lager besitzen einen kontrollierten CSV-Import.
Copying, ME-/TE-Forschung und Invention sind global gespeicherte Wissenschaftsaufträge; jeder nicht
archivierte Auftrag liefert konkrete Versorgung und übernimmt deren Effizienzen, Kosten und
vorgeschaltete Zeiten in die aktuelle Fertigung.
Verkaufsbelege besitzen eine kontrollierte Teilzuordnung und ersetzen bei ausdrücklichem
Wechsel die manuelle Verkaufsschätzung. Kostenstände und ursprüngliche Werte bleiben erhalten.
Lokale Sicherungen werden geprüft und bei Wiederherstellung erst beim nächsten Start aktiviert.
Bestätigungsvorschauen zeigen die konkreten geprüften Zielwerte. Ein Bereichswechsel verwirft eine
noch ungespeicherte Vorschau; bereits gespeicherte Daten bleiben erhalten.

Der vollständige Bedien-, Daten- und Konfliktvertrag steht unter
[Fachliche Konsolidierung](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md).
Die heutige Gewinnrechnung, Produktionsnummerierung und Schutzmengenformel bleiben maßgeblich.
Die zurückgezogene Projektfinanzansicht wird nicht wieder eingeführt.

## Zweck und Zielgruppe

EVE New Eden Nexus - Assets, Industry, Markets ist eine lokale, native macOS-Anwendung zur Planung und
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
aktuelle fachliche Stand und seine Tests sind im
[aktuellen Konsolidierungsnachweis](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md) dokumentiert.
Historische Buildberichte bleiben datierte Nachweise ihres jeweiligen Stands.

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
  Provenienzbehandlung sowie gemeinsamer priorisierter Transportgrenze
- deutsche und englische Lokalisierung

Das Swift-Paket stellt folgende Produkte bereit:

| Produkt | Aufgabe |
| --- | --- |
| `EVENexusCore` | Domänenmodelle und Dienste ohne SwiftUI-Abhängigkeit |
| `EVE New Eden Nexus - Assets, Industry, Markets` | native macOS-Anwendung |
| `EVENexusLiveAcceptance` | bewusst getrennte Live-Prüfungen |

## Architektur

Die zentrale Trennung lautet:

| Schicht | Verantwortung | Darf nicht übernehmen |
| --- | --- | --- |
| SDE | statische Typen, Blueprints, Aktivitäten, Dogma- und Volumendaten einschließlich des tatsächlich importierten verpackten Transportvolumens | Live-Marktdaten oder Anmeldung; das entpackte Volumen ersetzt nie ein fehlendes verpacktes |
| öffentliches ESI-Typdetail | verpacktes Transportvolumen nur für benötigte Typen ohne SDE-Wert | Produktionsgraph oder Transportkostenentscheidung |
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
| Dashboard | verdichteter Überblick über Jobs, persönliche Wallet-Salden, Finanzen und Markt; übernimmt die Charakterdaten aus dem zentralen Startablauf |
| Planner | Produktionsgraph, Build/Buy/Warehouse-Auswahl, Installation, Logistik, Gebühren, Erlös, Profit und ROI |
| Daten & Einstellungen → Logistik | Pflege der Main-Hub-Kurierwerte, Jump-Freighter-Annahmen und festen Capital-Routen im horizontalen Einstellungsmenü; Änderungen werden erst beim Speichern in die gemeinsame Production Basis übernommen |
| Main Hub Opportunities | Fertigungskandidaten und sortierbare Chancenkennzahlen für den exakt konfigurierten Main Hub; **Bauen** übergibt die konkrete Charge an den Planner |
| Home Hub Opportunities | dieselbe Chancenansicht für Verkäufe am Home Hub (Material vom Main Hub, ohne Rückweg); eigene Filter, gemeinsamer Scan mit dem Main Hub |
| Coalition Hub Opportunities | Chancenansicht für Verkäufe am Coalition Hub inklusive sortierbarem Transport Home → Coalition (Jump Freighter oder Kurier); eigene Filter, gemeinsamer Scan |
| Public Contracts | lokaler, resumierbarer Index öffentlicher ESI-Contracts mit sicherem Stopp und Teilstatus |
| Reactions | veröffentlichte Reaktionsrezepte, vollständige Batch-Kosten, Logistik und Make-or-Buy-Vergleich |
| Moon purchase analysis | Mengen- und Preisvergleich ausgewählter Marktrollen für Mondmaterialien; vollständiger Tabellenexport als PNG |
| Mineral purchase analysis | Mengen- und Preisvergleich der acht Standardmineralien (Tritanium, Pyerite, Mexallon, Isogen, Nocxium, Zydrine, Megacyte, Morphite) aus der veröffentlichten SDE-Gruppe `Mineral` an allen ausgewählten Märkten; seltene Sondermineralien der Gruppe (z. B. Crystalline Kangite, Eleutrium, Chromodynamic Tricarboxyls) sind ausgeschlossen; vollständiger Tabellenexport als PNG |
| All items | faktische persönliche und optional autorisierte Corporation-Bestände an allen bekannten Orten |
| Warehouse | nur planungsfähiger Bestand an exakt konfigurierten Produktionsorten, abzüglich Schutzbeständen und Reservierungen |
| Blueprints | persönliche BPO/BPC-Instanzen, Runs, ME/TE und belegte Forschungskostenschätzung |
| Production Overview | gespeicherte Produktionshistorie mit editierbaren Verkaufsdaten und explizit unbekannten Kosten |
| Net Worth | tägliche lokale Bewertung von Wallet, Assets, laufender Produktion, Orders, Contracts und zugänglichen Corporation-Anteilen |
| Data & Settings | allgemeine Darstellung, SDE, ESI, Industrie- und Marktkonfiguration |

Der eigenständige regionsübergreifende Market Browser ist kein sichtbarer
Navigationsbereich mehr. Die von Planner, Main-Hub-Chancen sowie Moon- und
Mineralien-Kaufanalyse benötigten Markt-, Struktur- und Preisroutinen bleiben
unverändert in ihren jeweiligen Arbeitsabläufen aktiv.

Die eigenständige Rekursive Produktionskalkulation ist ebenfalls kein
Navigationsbereich mehr. Planner und Main-Hub-Chancen behalten den gemeinsamen
Produktionsgraphen sowie die benötigten Blueprint-, ME/TE-, Reaktions-, Lager-,
Markt- und Logistikfunktionen. Der nur für die separate Nachkalkulation
bestimmte EVE-Zeilenimport, die erzwungene Vollproduktion und ihre
Routen-/Produktionsbuchprojektion sind entfernt.

Der eigenständige Bereich Industriejobs ist ebenfalls entfernt. Die
Charaktersynchronisierung speichert Jobdaten und Quellzustände weiterhin. Das
Dashboard integriert daraus Slot-Auslastung, Aktivitätskapazitäten, bereite
und bevorstehende Jobs; der Nettowert verwendet aktive Fertigungs- und
Reaktionsjobs weiterhin für die ausdrücklich geschätzte laufende Produktion.
Die Tabellenfilter und die separate Standort-/Jobliste entfallen.

Wallet ist kein eigenständiger Navigationsbereich mehr. Das Dashboard zeigt
zunächst Gesamtsaldo, Charakteranzahl und Quellzustand. Einzelbeträge, letzte
Aktualisierungszeitpunkte und Aktualisierungsaktionen stehen im aufklappbaren
Charakterbereich. Die vollständige Dashboard-Aktualisierung synchronisiert
weiterhin alle Wallets; einzelne Wallets lassen sich dort gezielt aktualisieren.
Letzte bekannte Werte, explizite
Fehlerzustände und ESI-Snapshot-Metadaten bleiben dabei erhalten.

Die Benutzeroberfläche verwendet für sichtbare EVE-Namen die gemeinsame
Komponente `EVEEntityText` beziehungsweise die passende Label-Variante. Namen
sind direkt kopierbar, ohne gleichzeitig Zeilenwahl, Disclosure oder
Doppelklick-Aktionen auszulösen. Tabellarische Peer-Daten besitzen sortierbare
Spaltenköpfe mit stabiler Sortierung und expliziter Behandlung fehlender Werte.

Jedes neu erzeugte Hauptfenster startet einmalig maximiert auf dem sichtbaren
Arbeitsbereich des Bildschirms, auf dem macOS das Fenster anlegt. Menüleiste und
Dock werden nicht überdeckt; der native Vollbildmodus wird nicht aktiviert.
Danach greift die App nicht mehr in die Fenstergröße ein: Das Fenster bleibt
frei verschieb- und skalierbar, seine Mindestinhaltsgröße beträgt weiterhin
640 × 480 Punkte. Die bisherige Größe von 1180 × 760 Punkten bleibt als
SwiftUI-Ausgangsgröße erhalten, falls beim Anlegen noch kein Bildschirmrahmen
verfügbar ist.

Die Fußleiste der Navigationsseitenleiste zeigt von oben nach unten die Karte
**Automatic data** (Stand der automatischen Datenabrufe), den Vertragsimport und
das Logo. **Automatic data** lässt sich über die Kopfzeile ein- und ausklappen;
der Zustand bleibt gespeichert, im eingeklappten Zustand zeigt ein kleiner
Fortschrittsindikator laufende Vertrags- oder Hub-Markt-Abrufe. Das Menü der
Karte pausiert oder setzt die Main-Hub-Aktualisierungen fort. Ist die
Seitenleiste zu schmal, rückt der Zeilenstatus unter den Zeilentitel statt
abgeschnitten zu werden. Das Dashboard selbst zeigt oben nur noch Titel und
Untertitel.

Die Fußleiste verwendet auch bei der Berechnung der minimalen
Fenstergröße die Mindestbreite der Seitenleiste (180 Punkte). Mehrzeilige
Statusmeldungen vergrößern dadurch nicht den gesamten Navigationsbereich über
die Fensterhöhe hinaus. Kopfmenüs, oberster Navigationseintrag und Logo bleiben
innerhalb des Fensters; bei kleiner Höhe scrollt die Navigationsliste.

Die Bereichsauswahl unter „Daten & Einstellungen“ belegt einen eigenen Bereich
unterhalb der nativen Titelleiste. Ihre Höhe folgt den Bedienelementen und bleibt
von der Fensterhöhe und dem gewählten Seiteninhalt unabhängig. Auch ein breiter
Seiteninhalt verändert weder ihre horizontale Position noch ihre Breite; die
Auswahl bleibt vollständig innerhalb der Detailspalte. Der Seiteninhalt scrollt
darunter. Bei ausreichender Breite erscheinen Reiter; bei wenig Platz bleibt die
bestehende kompakte Menüauswahl verfügbar.

Aufgelöste EVE-Items mit positiver Type-ID verwenden zusätzlich die gemeinsame
Darstellung `EVEItemText`: Ein kleines, vom offiziellen EVE-Bilddienst geladenes
Type-Icon steht vor dem weiterhin direkt kopierbaren Namen. Während des Ladens
oder bei einem Bildfehler bleibt der Name sichtbar und ein neutraler lokaler
Platzhalter kennzeichnet den Bildzustand. Unaufgelöste historische oder
importierte Namen erhalten kein anhand des Texts geratenes Bild. Größen,
Netzwerkgrenze, Fehlerverhalten, Barrierefreiheit und aktuelle Abdeckung sind in
[`Documentation/ITEM_PRESENTATION.md`](Documentation/ITEM_PRESENTATION.md)
festgehalten. Im Produktionsbuch stammt das Icon aus dem produzierenden
Top-Level-Knoten der unveränderlichen historischen Anfrage. Derselbe gemeinsame
Resolver versorgt die BPC/BPO-Kostenzeile, die historische Planner-Darstellung,
Produktionsentwürfe und die Produktionsübersicht. Rekursiv vorangestellte
Material-, Kauf-, Lager- oder Zwischenproduktknoten werden nicht als
Fertigprodukt dargestellt; Blueprintzeilen behalten dagegen bewusst die
Type-ID des sichtbaren Blueprints.

### Dashboard und Vermögensverlauf

Unter der Kapazitätsübersicht stehen drei Jobkarten: abholbereit, Abschluss in
den nächsten 48 Stunden und die fünf offenen Produktionsjobs mit dem höchsten
gesamten Rohstoffwert. Abholbereite und bevorstehende Jobs beginnen mit fünf
Einträgen und Gesamtzahl; „Alle anzeigen“ öffnet die vollständige Liste.
Abholbereite Jobs sind nach ältestem Fertigstellungsdatum, kommende Jobs nach
nächstem Abschluss sortiert, jeweils mit stabiler Jobidentität bei Gleichstand.
Die Top 5 enthalten offene Manufacturing- und Reaction-Jobs einschließlich
abholbereiter Jobs. Ihre Bewertung entsteht aus denselben Einzeljobwerten wie
**In Produktion**. Fehlende Materialpreise schließen den Job aus der Rangfolge
aus und machen die Abdeckung ausdrücklich unvollständig; die übrigen Werte
bleiben als Schätzung gekennzeichnet.

Wallet und Nettowert stehen im Breitenverhältnis 1:2 nebeneinander. Die
Charakterdetails sind zunächst zugeklappt. Der Hauptgraph ist 280 Punkte hoch
und reserviert Innenraum für Zeit- und Wertbeschriftungen; die Serienauswahl
wechselt bei Platzmangel von Segmenten auf ein Menü. Job- und Finanzkarten
stehen bei schmalen Fenstern untereinander.

Der Marktbereich zeigt alle Reaktionen mit negativer Wertschöpfung aus dem
gemeinsamen Reaktionssnapshot, zunächst fünf und aufklappbar vollständig.
Negative Reaktionen, Mondmaterialkaufanalyse und Mineralienkaufanalyse stehen
unter dem Ticker in drei gleich breiten, oben ausgerichteten Karten direkt
nebeneinander. Reicht die Fensterbreite nicht aus, stehen die Karten untereinander.
Markt, Run-Zahl, Transportziel und Kostenbasis stammen aus derselben Analyse
wie im Reaktionsbereich. Der Detailknopf öffnet diesen mit einmalig aktivem
Negativfilter. Ein früher gespeicherter Dashboard-Gruppenfilter begrenzt die
Treffer nicht mehr. Nach Konfigurationsänderungen werden unpassende
Empfehlungen bis zur gemeinsamen Aktualisierung ausdrücklich zurückgehalten.

Unter den drei Marktkarten steht die Karte **Top-Chancen** mit je bis zu fünf
Einträgen für Main, Home und Coalition Hub.

- **Grundlage:** Die Karte rechnet nicht selbst. Jede Hub-Chancenansicht
  meldet nach jeder Berechnung ihre sichtbaren Zeilen, also mit denselben
  Filtern, Warehouse-Beständen, Planreservierungen, Kosteneinstellungen,
  Zeilen-Runs/ME/TE und derselben Vertrags- und LP-Store-Grundlage. Die
  Meldung wird lokal gespeichert (`market/hub-top-opportunities.json`) und
  überdauert einen Neustart. Die Karte startet keinen ESI-Abruf.
- **Aktualität:** Ein Hub aktualisiert seine Spalte, sobald er geöffnet ist.
  Gibt es einen neueren Scan als den gemeldeten, weist die Spalte darauf hin;
  ohne Meldung fordert sie zum einmaligen Öffnen des Hubs auf. Unter jeder
  Spalte steht der Berechnungszeitpunkt.
- **Rangfolge:** nach täglichem Gewinnpotenzial. Zeilen ohne verfügbares
  Gewinnpotenzial werden nicht gerankt; gleiche Werte folgen der Typ-ID.
- **Einträge:** Jeder Eintrag zeigt das Produkt mit Icon und kopierbarem Namen,
  das tägliche Gewinnpotenzial und den ROI.
- **Bedienung:** Ein Klick auf den Hub-Titel öffnet die Chancenansicht.
  **Bauen** übergibt die gespeicherte Charge mit Zielmarkt an den Planner.
- **Hinweise:** Ein nicht konfigurierter, gleicher oder unvollständiger Hub
  bekommt einen Hinweis, ebenso ein Hub ohne Scan.

Mondmaterialien und Mineralien erhalten je eine kompakte Einkaufsliste mit
Material, günstigstem konfiguriertem Kaufort und Stückpreis, ebenfalls mit
Fünfer-Vorschau und vollständiger Aufklappansicht. Die Fachansichten zeigen
dieselbe vorbereitete Empfehlung zusätzlich zu ihren vorhandenen
Vergleichstabellen, dort jedoch ohne Aufklappen als kompaktes Raster: je
Material eine kleine Zelle mit Name, Kaufort und Stückpreis untereinander, die
Zellen fließend nebeneinander. Mineralien stehen alphabetisch; Mondmaterialien
stehen in je einer Zeile pro Klasse R4, R8, R16, R32 und R64 und darin
alphabetisch. Die Klasse ergibt sich aus einer festen Zuordnung der 20
Typ-IDs, weil die SDE-Gruppe `Moon Materials` keine Klasse trägt; ein
unbekannter Typ erscheint ausdrücklich ohne Klasse am Ende. Nur frische, standortpassende Märkte mit gültigen
Verkaufsangeboten sind Kandidaten; Preisgleichstände folgen der Reihenfolge der
konfigurierten Märkte. Fehlen Vergleichsmärkte, lautet die Angabe
„Günstigster verfügbarer Markt“ mit sichtbarer Einschränkung. Ein Material ohne
frisches Angebot bleibt ausdrücklich ohne Kaufort und Preis.
In den beiden Fachansichten scrollt die ganze Seite senkrecht; die aufgeklappte
Einkaufsliste schiebt die Vergleichstabelle nach unten, statt Kopfbereich,
Berechnungsgrundlage oder Tabelle zu verdrängen. Die Vergleichstabelle scrollt
bei vielen Märkten nur noch waagerecht.

Der Mineralienticker übernimmt Mineral, Stückpreis und Kaufort direkt aus
derselben Mineralien-Einkaufsanalyse. Regionale Tagesdurchschnittspreise und
Tagesänderungen gehören nicht mehr zu diesem Ticker. Ansichtenwechsel teilen
laufende Aktualisierungen und nutzen passende vorhandene Ergebnisse innerhalb
des fünfminütigen Wiederverwendungsfensters. Aufklappen startet keine Analyse.

Beim Programmstart lädt die App alle Daten automatisch in einem zentralen
Ablauf (Eigentümerentscheid 20.10.2026, [Entscheidung](Documentation/Consolidation/DECISIONS.md)).

1. **Charaktere und Konfiguration:** Gleichzeitig laufen der vollständige
   Charakter-Sync (jeder verbundene Charakter genau einmal je App-Prozess) und
   das Laden der Planner-Konfiguration.
2. **Analysen:** Danach starten Reaktionen, Mondmaterial- und
   Mineralien-Analyse.
3. **Scans:** Gleichzeitig werden der automatische Main-Hub-Chancen-Scan und
   der Public-Contracts-Import freigegeben.

Der Ablauf gehört nicht zu einer Ansicht und läuft unabhängig vom gewählten
Bereich weiter. Das Dashboard wartet beim ersten Aufruf auf das Sync-Ergebnis
dieses Ablaufs und synchronisiert nicht ein zweites Mal; ohne Hintergrunddienste
synchronisiert es wie bisher selbst.

Die Seitenleisten-Karte **Automatic data** zeigt unter **Programmstart** den Stand
dieses Ablaufs. Es gibt je eine Zeile für Charaktere, Lager & Baupläne,
Reaktionen, Mondmaterialien und Mineralien; darunter folgen wie bisher die
Zeilen für Verträge und Main-Hub-Markt. Jede Zeile nennt einen Zustand (Wartet,
Laufend, Aktuell, Teilweise, Veraltet, Verboten, Nicht verfügbar) und, falls
bekannt, die Uhrzeit des letzten Datenstands.

- **Charaktere:** Grundlage ist das Sync-Ergebnis des Startablaufs. Scheitern
  einzelne Charaktere, gilt der Stand als Teilweise, scheitern alle, als Nicht
  verfügbar. Unter der Zeile steht dann der Grund je Charakter, gleiche Gründe
  zusammengefasst und die Namen kopierbar. Unterschieden werden: gespeicherte
  Autorisierung nicht lesbar, Fehler bei EVE SSO oder ESI (zum Beispiel
  Schlüsselbund nicht lesbar, fehlende Autorisierung, Berechtigung abgelehnt,
  Ratenlimit, Serverfehler, Dienst nicht erreichbar), Ergebnis eines anderen
  Charakters verworfen und lokales Speichern fehlgeschlagen. Der manuelle
  Dashboard-Abgleich nennt dieselben Gründe in seiner Fehlermeldung. Es werden
  keine Token-Inhalte angezeigt.
- **Lager & Baupläne:** Grundlage sind die gespeicherten ESI-Metadaten der
  Domänen `assets` und `blueprints`. Fehlt für einen Charakter eine davon, ist
  der Stand nicht Aktuell, sondern Teilweise.
- **Analysen:** Sie fassen die Marktzustände ihres Snapshots zusammen. Eine
  fehlgeschlagene Aktualisierung mit erhaltenem Snapshot gilt als Veraltet.

Die Anzeige startet keine Abrufe und macht aus fehlenden Daten weder einen
aktuellen Stand noch null.

Der Charakter-Sync verwendet den bestehenden vollständigen Ablauf. Dazu gehören insbesondere Wallet, Assets, Industriejobdaten,
Orders, private Contracts sowie zugängliche Corporation-Wallets und -Assets.
Einzelne Fehler behalten den letzten bekannten Quellstand und werden als
partiell gemeldet; sie ersetzen ihn nicht durch null. Die Wallet-Karte bietet
denselben Ablauf zusätzlich als sichtbare manuelle Aktualisierung an und kann
den Saldo eines einzelnen Charakters gezielt aktualisieren.

Nach einer erfolgreichen Aktualisierung der öffentlichen Referenzpreise wird
höchstens ein Vermögenspunkt pro lokalem Kalendertag gespeichert. Eine
weitere Aktualisierung am selben Tag ersetzt diesen Tagespunkt; Tage, an denen
die App keinen Punkt erfasst hat, werden nicht erfunden. Die Zeitachse verwendet
die wirklichen Datumsabstände. Die Wertachse passt sich dem sichtbaren Bereich
an, damit kleine Aenderungen nicht durch einen erzwungenen Nullpunkt
verschwinden. Gesamtwert, Wallet, Assets und **In Produktion** können getrennt
betrachtet werden; auf der Net-Worth-Seite sind Komponenten einzeln ein- und
ausblendbar.

Persönliche und Corporation-Assets erhalten das ESI-Kennzeichen
`is_blueprint_copy` durch Synchronisierung und Speicherung hindurch. Ob ein
Asset ein Original oder eine Kopie ist, entscheidet zuerst der gespeicherte
ESI-Blueprint-Datensatz mit derselben Item-ID, danach das Asset-Kennzeichen;
gestapelte Blueprints sind immer Originale. Einzelne Blueprints ohne Datensatz
und Kennzeichen sowie Assets ohne SDE-Klassifikation bleiben ausdrücklich
unbewertet und sichtbar unvollständig.

- **BPO** werden mit der Wiederbeschaffungsschätzung aus **Baupläne** bewertet:
  SDE-Basispreis plus Forschungskosten bis zum aktuellen ME/TE-Stand mit den
  Forschungsanlagen und Systemindizes des Profils. Unerforschte Originale
  (ME 0/TE 0, auch gestapelte) benötigen dafür keine Forschungsanlage. Fehlt sie
  bei erforschten Originalen, zählt nur der SDE-Basispreis als Untergrenze; die
  Assets gelten dann als Schätzung und unvollständig. Ohne SDE-Basispreis greift
  der ESI-Referenzpreis.
- **BPC** werden mit dem niedrigsten Preis je Durchlauf aus öffentlichen,
  eindeutig zurechenbaren Einzel-BPC-Verträgen (Item Exchange, ein angebotener
  Posten, keine Gegenposten) desselben Bauplantyps aus dem lokalen
  Vertragsindex bewertet, multipliziert mit den verbleibenden Runs des eigenen
  Datensatzes. Der ESI-Preis des Bauplantyps wird für Kopien nie verwendet.
  Kopien ohne Runs oder ohne solches Angebot bleiben unbewertet und erscheinen
  als „BPC-Stapel ohne Vertragspreis“; sie machen die Summe wie bisher nicht
  unvollständig.

Die Charaktertabelle zeigt BPO- und BPC-Anteil je Charakter unter dem Namen.
Ihre Spalten haben feste Breiten, damit Kopf und Zeilen unabhängig von der
Länge der Hinweiszeile bündig bleiben; Hinweise brechen um, statt die Spalte zu
verbreitern. Eine normale Aktualisierung ergänzt die verfügbaren Quelldaten. Historische Vermögenssummen behalten ihren
ursprünglichen Regelstand; neue Aufzeichnungen verwenden die korrigierte
Bewertungsrichtlinie. Details: [Fehlerkorrekturen und Wiederherstellung](Documentation/REVIEW_FIXES_2026-10-02.md).

**In Produktion** bewertet die bereits verbrauchten SDE-Materialmengen aktiver,
pausierter oder abholbereiter Manufacturing- und Reaction-Jobs mit ESI Average
Price und Adjusted Price als Fallback. Bekannte ME-Werte vorhandener
Blueprintinstanzen werden angewendet. Materialien ohne Referenzpreis werden
rekursiv über ihre eigenen SDE-Eingänge (bis zu vier Ebenen, je Ausgabeeinheit)
mit derselben Preisregel bewertet. Ausgelieferte, abgebrochene und
zurueckgesetzte Jobs zaehlen nicht. Da ESI fuer den installierten Job keine
vollständige Facility-/Rig-Materialmodifikation liefert, bleibt dieser Anteil
als Schätzung gekennzeichnet. Fehlende Job-, Blueprint-, SDE- oder Preisdaten
bleiben explizit unvollstaendig und werden weder als null noch als erfundener
Wert behandelt.

Die sechs Karten der Industriekapazität verwenden ein stabiles Raster: bei
ausreichender Breite drei Spalten und zwei Zeilen, bei mittlerer Breite zwei
Spalten und bei sehr schmaler Darstellung eine Spalte. Die Karten werden damit
nicht mehr als unausgewogene Fünf-plus-eins-Anordnung verteilt. Die fachliche
Reihenfolge und die getrennten unbekannten oder teilweisen Zustände bleiben bei
jedem Raster erhalten.

## Zentrale Fachregeln

### Marktrollen und Preise

Main Hub, Home Hub und Coalition Hub sind getrennte Rollen. Der Main Hub ist
die Quelle für Planner-Käufe und Multibuy-Listen. Produktions- und
Verkaufslogistik richtet sich nach den exakten konfigurierten Ortskennungen.
Ein gleicher Start- und Zielort erzeugt keinen Transportweg. Player-Structure-
Märkte bleiben ohne passende Berechtigung oder Dockingzugriff unverfügbar.

Die Mineralien-Kaufanalyse, ihre Kaufempfehlungen und der Dashboard-Ticker
umfassen nur die acht Standardmineralien (Typ-IDs 34–40 und 11399). Weitere
veröffentlichte Typen der SDE-Gruppe `Mineral` sind seltene Sondermineralien ohne
Rolle in der regulären Produktion und werden bewusst nicht angezeigt
(Eigentümerentscheid 19.10.2026).

Mondmaterial- und Mineralien-Kaufanalyse verwenden gemeinsam alle ausdrücklich
gewählten Main-, Home- und Coalition-Hubs sowie zusätzliche Vergleichsmärkte.
Ein Ort erscheint auch bei mehreren Rollen nur einmal. Für jeden Gegenstand und
Ort ist der niedrigste gültige Sell-Preis die Basis; die angezeigte
10-%-Preisgrenze liegt exakt beim 1,10-Fachen. Die zugehörige Menge ist die
Summe aller verbleibenden Sell-Order-Mengen bis einschließlich dieser Grenze.
Nur aktuelle Märkte erhalten einen Preisrang, Gleichstände teilen denselben
Rang. Die Analyse berücksichtigt weder Transport noch Steuern oder Gebühren.
Fehlende, gesperrte, teilweise oder veraltete Marktdaten bleiben sichtbar und
werden nicht als Preis oder Menge null ausgegeben.

Preisentscheidungen verwenden die benötigte Gesamtmenge und die verfügbare
Markttiefe. Einzelpreise, SDE-Basispreise oder ESI-Adjusted-Prices sind kein
Ersatz für eine unvollständige Marktquote. Kosten, Ersatzwert, unmittelbarer
Zahlungsbedarf, Logistik, Steuern/Gebühren, Erlös, Wertschöpfung, Profit, Marge
und ROI bleiben getrennt nachvollziehbar.

### Handel

Der Bereich **Handel** steht in der Seitenleiste direkt unter den
Coalition-Hub-Chancen. Er vergleicht Marktgruppen zwischen den Hubs nach dem
Referenzbild des Eigentümers. Die verbindlichen Formeln stehen im
[Handel-Plan, Abschnitt C](Documentation/HANDEL_PLAN.md).

- **Routen:** Main → Home, Main → Coalition, Home → Coalition und Coalition →
  Home. Die Routen sind getrennt, die zuletzt gewählte wird gespeichert.
  Station Trading innerhalb eines Hubs gibt es nicht (Eigentümerentscheid
  22.10.2026). Sind Quell- und Ziel-Hub derselbe Ort, weist die Ansicht darauf
  hin, dass es keine Handelsroute gibt.
- **Marktgruppen:**
  - Der Nutzer wählt einen Knoten im SDE-Marktgruppenbaum, über die Wurzelliste,
    die Suche oder die Pfadleiste.
  - Jede direkte Untergruppe wird zu einer Kachel mit allen Items ihres
    Teilbaums. Eigene Items des Knotens bilden eine Zusatzkachel.
  - Der gewählte Knoten wird gespeichert und gilt für alle Modi.
  - Ein Katalog ohne Marktgruppen (Adapter 1–4) zeigt „SDE-Neuimport nötig“.
    Ohne aktiven Katalog erscheint „Kein SDE-Katalog“. Beide Zustände verlinken
    die SDE-Einstellungen.
- **Kachel:**
  - Kopfzeile mit Chips für Quelle, Ziel und Anzahl der Items.
  - Umschalter Min-Sell/Max-Buy für Quelle und Ziel. Quelle Min-Sell bedeutet
    Sofortkauf, Max-Buy eine eigene Buy-Order. Ziel Min-Sell bedeutet eine
    eigene Sell-Order, Max-Buy einen Direktverkauf.
  - Tabelle mit Name, Quellpreis, Zielpreis, Diff % und Gewinn/m³, auch ohne
    Details. Gewinn/m³ setzt den Gewinn ins Verhältnis zum Packvolumen; die
    Formel steht im [Handel-Plan, Abschnitt C](Documentation/HANDEL_PLAN.md).
    Fehlen Gewinn oder Packvolumen, zeigt die Spalte „—“.
  - Pfeile: ab einstellbaren 25 % ein Pfeil nach oben (gelb), ab 30 % ein
    Doppelpfeil (rot), bei negativer Differenz ein Pfeil nach unten (grün).
  - **Details anzeigen** ergänzt die Spalten Einkauf, Transport,
    Netto-Verkauf, Gewinn, Marge, ROI, Ø Bedarf/Tag, Nachfrage heute und Tiefe
    (Stückzahl zum Zielpreis) und Offen (Logbuch). Die Detailtabelle scrollt
    innerhalb der Kachel horizontal.
  - Ohne Details zeigt ein Buch-Symbol neben dem Namen die offene
    Logbuch-Menge.
  - **Ins Logbuch** (Plus-Symbol neben dem Namen, getrennt vom Kopier-Klick)
    öffnet einen vorbefüllten Logbuch-Eintrag mit:
    - eigenem Orderpreis,
    - eingefrorenen Gebühren,
    - geplantem VK einen Preisschritt unter dem besten Sell bzw. dem besten Buy
      bei Direktverkauf,
    - exaktem Transport für die eingegebene Menge.
  - Alle Spalten sind sortierbar, die Sortierung gilt für alle Kacheln außer
    der Top-20-Kachel. Unbekannte Werte stehen aufsteigend hinten und absteigend
    vorn.
  - Item- und Ortsnamen sind per Klick kopierbar. Fehlende Werte zeigen „—“, ein
    Info-Symbol nennt den Grund.
- **Top-20-Kachel** (Regeln im [Handel-Plan, Abschnitt J](Documentation/HANDEL_PLAN.md)):
  - Sie steht als erste Kachel über den Untergruppen-Kacheln und umfasst alle
    Items der gewählten Marktgruppe.
  - Sie erscheint nur, wenn die Gruppe mehr als eine Kachel oder mehr als 20
    Items hat.
  - **Rangfolge nach** Diff % oder Gewinn/m³. Die Auswahl wird gespeichert.
  - Eigene Umschalter Min-Sell/Max-Buy für Quelle und Ziel.
  - Gerankt werden nur Items mit positivem Wert, höchstens 20. Gibt es weniger,
    ist die Liste kürzer; der Chip nennt „Top N von M Items“.
  - Eine Fußzeile nennt getrennt, wie viele Items ohne bekannten Wert und wie
    viele mit Wert ≤ 0 nicht gerankt sind.
  - Hat kein Item einen positiven Wert, sagt die Kachel das ausdrücklich. Bei
    Gewinn/m³ nennt sie die nötigen Daten: Preise, Gebühren, Transport und
    Packvolumen.
  - Eigene Sortierung: Beim Öffnen und bei jedem Wechsel der Kennzahl steht sie
    auf der Kennzahl absteigend. Klicks auf die Spaltenköpfe sortieren nur diese
    Kachel.
  - Spalten, Details, Kopier-Klick und **Ins Logbuch** wie in jeder Kachel; die
    Vorbefüllung nutzt die Umschalter der Top-20-Kachel.
- **Datenquellen:**
  - Preise und Tiefe: Main Hub aus dem Main-Hub-Scan, Home und Coalition aus
    der Marktübersicht der Hub-Chancen-Scans. Ein Hub, der einem anderen
    entspricht, nutzt dessen Daten.
  - Tagesbedarf: die Bedarfssnapshots der Hub-Chancen.
  - Gebühren: das Händlerprofil der jeweiligen Hub-Rolle.
- **Marktdaten nur im Speicher:** Sie entstehen mit den Hub-Scans und liegen
  nur im Arbeitsspeicher. Nach einem Neustart fehlen sie bis zum nächsten Scan;
  die App sagt das ausdrücklich. **Hub-Märkte aktualisieren** startet denselben
  Main-, Home- und Coalition-Scan wie die Hub-Chancen.
- **Transport:**
  - Main → Home ist eine Kurier-Etappe.
  - Main → Coalition besteht aus dieser Etappe plus Home → Coalition. Dafür
    nutzt die App den Jump Freighter, wenn er aktiviert ist (DOTLAN-Route,
    Ø Isotopenpreis im Main Hub), sonst den Profil-Kurier.
  - Home → Coalition und Coalition → Home nutzen nur diese Etappe, für
    Coalition → Home in umgekehrter Richtung. Die Treibstoffkosten je
    Jump-Freighter-Flug gelten in beiden Richtungen als gleich.
  - Die Etappen werden mit ihren Sätzen angezeigt; fehlende Angaben verlinken
    die Logistikeinstellungen.
- **Rechenregeln:**
  - Eigene Orders liegen einen zulässigen Preisschritt besser als die beste
    Order. Zulässig sind höchstens 4 signifikante Stellen und mindestens
    0,01 ISK. Diese Regel stammt aus dem Wissensstand des Assistenten und ist
    nicht gegen eine CCP-Quelle belegt.
  - Gebühren für Relist oder Orderänderung sind nicht enthalten.
  - Kurier je Einheit: der höhere Wert aus Volumen × ISK/m³ und
    Collateral × 0,5 %, ohne 1-Mio.-Rundung. Collateral ist der Einkaufswert.
  - Jump Freighter je Einheit: Kosten bei voller Ladung.
  - Fehlende Preise, Gebühren, Packvolumen oder Transportwege bleiben
    unbekannt und werden nie als 0 angesetzt.

### Handelslogbuch

Das **Handelslogbuch** steht in der Seitenleiste direkt unter „Handel“. Es
speichert Einkäufe in einer eigenen SQLite-Datei
`dataRoot/trade/trade-logbook.sqlite` (Migrationen über `user_version`). Die
SwiftData-Datenbank bleibt unberührt.
- Die App-Sicherung erfasst die Datei mit, weil sie den gesamten Datenordner
  einschließlich SQLite-Snapshots sichert.
- Eine Datei einer neueren App-Version wird nicht geöffnet und nicht
  verändert.

- **Eintrag:**
  - Gegenstand, Kaufzeitpunkt, Menge, Preis je Einheit (ohne Broker),
    Kaufart (Sofortkauf oder eigene Buy-Order) mit eingefrorener
    Broker-Gebühr, Kauf- und Ziel-Hub.
  - Geplanter VK, Transport für die gesamte Menge, eingefrorene Umsatzsteuer
    und Sell-Broker, Status und Notizen.
  - Leere Felder bleiben unbekannt, nie 0.
- **Status:** gekauft, im Transport, gelistet, verkauft, Fertigung ignoriert,
  ausgeschlossen. Nur die ersten drei zählen als offen.
- **Verkäufe:** Datum, Menge, Preis und Art (eigene Sell-Order oder
  Direktverkauf). Sind alle Einheiten verkauft, wechselt ein offener Eintrag
  beim Speichern auf „verkauft“.
- **Berechnung:**
  - Kosten je Einheit = Preis × (1 + Broker bei Buy-Order) + Transport ÷
    Menge.
  - Realisierter Gewinn = Σ verkaufte Menge × Preis × (1 − Steuer −
    Broker bei Sell-Order) − verkaufte Menge × Kosten je Einheit.
  - Fehlt ein Satz, bleibt das Ergebnis unbekannt.
- **Erinnerung (nur in der App):** Je Eintrag stehen der geplante VK und der
  aktuelle beste Sell-Preis am Ziel-Hub nebeneinander. Er kommt aus der
  Marktübersicht der laufenden Sitzung. Offene Einträge mit erreichtem
  Zielpreis werden grün hervorgehoben, sonst zeigt die Zeile die Abweichung
  in Prozent. Es gibt keine Systembenachrichtigung.
- **Tabelle:** Filter für offene Einträge, alle Einträge oder einen Status.
  Alle Spalten sind typisiert sortierbar; unbekannte Werte stehen aufsteigend
  hinten, Status nach Lebenszyklus, Hubs Main/Home/Coalition. Bearbeiten und
  Löschen sitzen vorn in jeder Zeile; Löschen nur nach Bestätigung.
- **Manueller Eintrag:** **Neuer Eintrag** mit Gegenstandssuche über den
  SDE-Katalog (mindestens 3 Zeichen).
- **Wallet-Daten:**
  - Nach jeder Charakter-Synchronisierung speichert die App die persönlichen
    Wallet-Transaktionen und das Wallet-Journal dieses Charakters in der
    Logbuch-Datei. Die Synchronisierung läuft beim Start für alle Charaktere,
    sonst über das Dashboard oder die Charaktereinstellungen.
  - Schlüssel sind Charakter und ESI-ID. Wiederholte Abgleiche fügen nichts
    doppelt hinzu, und ältere Daten bleiben über das 30-Tage-Fenster von ESI
    hinaus erhalten.
  - Ungültige Transaktionen (Menge ≤ 0, ungültiger Preis) werden nicht
    gespeichert.
  - Ort, Journal-Referenz und „persönlich“ sind neue, optionale Felder. Ältere
    gespeicherte Synchronisierungen ohne diese Angaben bleiben lesbar, die
    Felder sind dann unbekannt.
  - Corporation-Wallets werden bewusst nicht einbezogen
    (Eigentümerentscheid 22.10.2026).
  - Der Abschnitt **Wallet-Daten** im Handelslogbuch zeigt je Charakter:
    - den Zustand des letzten Abgleichs, etwa „Wallet-Berechtigung fehlt“ oder
      veraltet,
    - den letzten Abgleich, der Daten geliefert hat,
    - die Zahl der gespeicherten Transaktionen und Journal-Einträge.
  - Ein Fehlschlag überschreibt den letzten erfolgreichen Stand nicht.
  - **Wallets abgleichen** synchronisiert alle autorisierten Charaktere über
    die bestehende Charakter-Synchronisierung.
  - Gespeichert werden auch die offenen Orders und die Orderhistorie des
    Charakters (mit Ausgabedatum und Laufzeit), für die Erkennung der
    Orderart.
- **Automatischer Abgleich** (Handel-Plan P7). Er läuft nach jeder
  Sammel-Synchronisierung der Charaktere (Start, Dashboard, „Wallets
  abgleichen“) und beim Öffnen des Handelslogbuchs.
  - **Käufe:**
    - Kauftransaktionen ab dem Datum **Käufe übernehmen ab** werden zu je
      einem eigenen Eintrag, wenn sie in einem der drei Hubs liegen. Das
      Startdatum ist beim ersten Abgleich der Beginn des aktuellen UTC-Tags.
    - Gespeichert wird je Charakter und Transaktions-ID; ein erneuter Abgleich
      legt nichts doppelt an.
    - Ziel-Hub: Main → Home, Home → Coalition und Coalition → Home, jeweils
      wenn der andere Hub ein eigener Ort ist; sonst bleibt der Kauf-Hub das
      Ziel.
    - Käufe von Materialien aktiver Planner-Pläne erhalten „Fertigung,
      ignoriert“.
    - Der Transport wird für die Menge mit der aktuellen Transportbasis
      geschätzt und als geschätzt markiert. Bleibt das Ziel der Kauf-Hub, ist
      er 0.
    - Kann der SDE-Katalog einen Gegenstand nicht benennen, wird der Kauf
      nicht übernommen und gezählt, statt einen Namen zu erfinden.
  - **Orderart:** Eine eigene Order wird erkannt, wenn ein Order desselben
    Charakters, Gegenstands, Orts und derselben Seite zum Zeitpunkt aktiv war.
    - Treffer: Kauf per Buy-Order mit berechnetem Broker, Verkauf per
      Sell-Order.
    - Bekannte Orders ohne Treffer: Sofortkauf bzw. Direktverkauf.
    - Ohne Orderdaten: Sofortkauf bzw. eigene Sell-Order, markiert als
      angenommen.
  - **Verkäufe:** Verkaufstransaktionen werden nach FIFO je Gegenstand und
    Ziel-Hub den ältesten offenen Einkäufen zugeordnet. Sind alle Einheiten
    verkauft, wechselt der Eintrag auf „verkauft“.
  - **Steuer und Broker:** Die Umsatzsteuer gilt als belegt, aus dem Journal
    (`transaction_tax` zur Transaktion, anteilig je Menge). Die Broker-Gebühr
    bleibt berechnet.
  - **Nicht zugeordnet:** Verkäufe erfasster Gegenstände ohne passenden
    offenen Einkauf, auch an Orten außerhalb der Hubs, erscheinen im Abschnitt
    „Nicht zugeordnete Verkäufe“ und lassen sich per **Zuordnen** einem
    offenen Einkauf zuweisen.
- **Ist neben Plan:** Die Tabelle zeigt Ø Ist-VK neben dem geplanten VK. Ein
  Ist-Preis unter Plan wird gelb hervorgehoben, ein Tooltip zeigt die
  Abweichung. Plan-Gewinn steht neben dem realisierten Gewinn.
- **Hinweis-Symbole:** aus der Wallet übernommen, Orderart angenommen,
  Transport geschätzt, Steuer belegt. Eigene Änderungen an Kaufart oder
  Transport im Editor setzen die Herkunft auf manuell.

### Assets und Warehouse

`All items` zeigt faktischen Bestand. `Warehouse` ist eine Planungsprojektion
für exakt konfigurierte Produktionsorte. Schiffe und deren verschachtelte
Inhalte sind nicht als Produktionsmaterial verfügbar; normale Hangarcontainer
können verfügbar bleiben. Schutzbestände werden vom faktischen Bestand
abgezogen, aktive Reservierungen anschließend von der planbaren Menge.

Corporation-Bestände benötigen die vorgesehenen Scopes und Rollen und werden
je Corporation dedupliziert. Fehlende Rechte ergeben keinen scheinbar leeren
Hangar.

Kann ESI einzelne Player-Structure-Orte eines Asset-Snapshots nicht auflösen,
bleiben die betroffenen Assets erhalten und der Charakter wird ausdrücklich
als **Assets teilweise verfügbar** mit der Zahl der nicht erreichbaren Orte
angezeigt. Dieser Zustand ist von einer abgelaufenen SSO-Berechtigung getrennt;
er wird weder als fehlender Scope noch als leerer Bestand dargestellt.

Fehlen in einem Snapshot nur Struktur- oder Divisionsnamen, gelten seine Mengen
für Lager, Planner, Produktionsbaum und Projektbestand als vollständig. Die
Warnung „Some character assets in the production warehouse are not up to date“
erscheint nur noch, wenn ein Snapshot aus anderem Grund nicht frisch ist
(veraltet, teilweise geladen, verboten, nicht verfügbar). Items, die keinem Ort
zugeordnet werden können, erzeugen eine eigene Planner-Warnung und gehen nicht
in den Bestand ein. Fehlende Strukturnamen stehen in der Lageransicht als
Hinweis mit Charakter und Anzahl; im Planner sind sie nur ein ausgeblendeter
Informationshinweis.

### Blueprints, Industrie und Reaktionen

BPO und BPC bleiben unterschiedliche Instanzen mit eigener Herkunft. Die Art
folgt der ESI-Menge: `-1` Original, `-2` Kopie; eine positive Menge mit
`runs = -1` ist ein Stapel unbenutzter Originale (Kopien stapeln nie) und gilt
als Original, auch in bereits gespeicherten Snapshots. Eine BPC
kann als verbrauchter Erwerbspreis, eine BPO nur mit einer expliziten lokalen
Kostenallokation in einen Plan eingehen. Jede verwendete BPC bleibt anhand ihrer
Item- oder Contract-Identität ein eigener Fertigungsjob mit eigenen Runs,
ME/TE, Materialrundungen und Rest-Runs. Unbekannte Blueprint- oder
Forschungskosten werden nicht zu null.

Die Blueprint-Übersicht zeigt als Standort die Station, Struktur oder das
Sonnensystem, in dem der Blueprint tatsächlich liegt. ESI meldet bei Blueprints
in Containern, Schiffen oder Büros nur den direkten Behälter; dieser wird wie in
Assets und Produktionsplanung über den gespeicherten Asset-Bestand des
Charakters bis zum Wurzelstandort aufgelöst. Namensfolge: beim Asset-Sync
gespeicherter Struktur-/Stationsname, dann eingerichtete Produktionsstruktur,
dann öffentlicher ESI-Name. Ohne Asset-Snapshot oder bei nicht auflösbarer
Behälterkette bleibt der Standort ausdrücklich „Unbekannter Ort“.

Die fachliche Abgrenzung folgt den CCP-Verträgen
[Blaupausen](https://support.eveonline.com/hc/de/articles/203269951-Blaupausen),
[Kopieren](https://support.eveonline.com/hc/de/articles/203210602-Kopieren) und
[Erfindung](https://support.eveonline.com/hc/de/articles/203210642-Erfindung).
Die EVE-University-Seiten
[Blueprints](https://wiki.eveuniversity.org/Blueprints),
[Research](https://wiki.eveuniversity.org/Research) und
[Invention](https://wiki.eveuniversity.org/Invention) dienen als ergänzende
Spielmechanik-Referenz; bei Abweichungen bleiben CCP und das aktive SDE
maßgeblich.

Der Planner friert eine berechnete Planung als unveränderlichen Snapshot ein.
Ein gekaufter oder aus dem Warehouse verwendeter Zwischenstoff entfernt seinen
Produktionszweig und den zugehörigen Job. Make-or-Buy vergleicht vollständige
Bedarfs- und Batchmengen einschließlich belegter Installation und Logistik.
Passt ein Item verpackt nicht in das konfigurierte Transportlimit je Vertrag
(zum Beispiel ein Freighter-Rumpf bei 350.000 m³), ist der Kauf am Main Hub nicht
möglich: Kaufkosten und Kauflogistik bleiben nicht verfügbar, die Empfehlung lautet
**Bauen** an der Produktionsanlage, und „Empfehlungen übernehmen“ setzt es auf Bauen.
Liegt der Main Hub an derselben Station wie die Anlage, entfällt der Transport und
der Kauf bleibt vergleichbar.
Oberhalb der freien Planereingabe steht eine geführte Produktauswahl. Die Suche
startet ab drei Zeichen in einem großen Ergebnisfeld und zeigt ausschließlich
veröffentlichte, vollständig aufgelöste Manufacturing-Produkte des aktiven
SDE-Katalogs. Sie benötigt deshalb weder ESI-Login noch Charakterscopes. Nach
der Auswahl werden Runs, ME und TE eingegeben; der SDE-Output je Run wird
sichtbar ausgewiesen. Beim Hinzufügen rechnet die Domänenschicht Runs mal
Output je Run in den bestehenden `Produkt Bedarf ME TE`-Vertrag um und hängt
die neue Zeile unverändert ans Ende der Planereingabe. Dadurch bleibt die
Run-Anzahl auch bei Mehrfach-Outputs exakt. Der sichtbare Itemname ist über die
gemeinsame EVE-Namenskomponente unabhängig vom Auswahlknopf kopierbar.
Die freie Planereingabe wird weiterhin während des Tippens geprüft. Sobald eine
Zeile unvollständig oder ungültig ist, erscheint die zugehörige nummerierte
Fehlermeldung direkt unter **Berechnen** innerhalb derselben Eingabefläche und
nicht erst hinter der Liste der letzten Produktionen. Solange ein Eingabefehler
besteht, bleibt **Berechnen** deaktiviert.

Der erste gültige Klick auf **Berechnen** setzt sofort einen sichtbaren
Planner-Status und deaktiviert weitere Berechnungsstarts. Die Oberfläche nennt
getrennt die Vorbereitung, BPO-/BPC-Auflösung, Anwendung abweichender
Effizienzen, eigentliche Kalkulation und Speicherung. **Abbrechen** bleibt
währenddessen sichtbar; ein erneuter Klick auf **Berechnen** kann die laufende
Vorbereitung nicht mehr unbemerkt abbrechen und von vorn starten. Der zuletzt
erfolgreiche Plan bleibt sichtbar, bis ein neuer Plan vollständig berechnet und
gespeichert ist.

Für eine Berechnung löst der Planner die Eingabe, die gewünschten Produkttypen,
den rekursiven Materialbaum, mögliche komprimierte Erze und selbstspringende
Capital-Produkte gemeinsam auf. Derselbe vorbereitete Stand wird anschließend
für Markt- und Vertragsabrufe sowie die eigentliche Kalkulation verwendet. Die
Runtime behält höchstens die letzte Vorbereitung. Bleiben SDE-Build samt
Inhaltshash, Eingabetext und die beiden Zusatzoptionen für komprimiertes Erz und
Sprungtreibstoff unverändert, verwenden Folgeberechnungen nach Änderungen an
Lager- oder Beschaffungsentscheidungen diesen Stand erneut. Eine geänderte
Eingabe, ein anderer SDE-Inhalt oder eine geänderte Zusatzoption ersetzt ihn.
Marktpreise, ESI-Snapshots, Lagerstände und Kostenresultate werden dadurch nicht
eingefroren; unbekannte oder unvollständige Werte behalten ihre bisherigen
Zustände.

Die **Main Hub Opportunities** führen die Chargenannahmen direkt je
Kalkulatorzeile. `Produzierte Menge = Runs × SDE-Ausgabe je Run`; Runs, ME und
TE sind dort editierbar und besitzen sortierbare Spalten. Tech-I-Module starten
mit der Planungsannahme `ME 10` und `TE 20`. Belegt der gespeicherte öffentliche
LP-Katalog dagegen den Blueprinttyp als Loyalty-Store-BPC, hat `ME 0` und
`TE 0` Vorrang. Tech-II-Kandidaten starten weiterhin mit `ME 3` und `TE 2`.
Alle Werte bleiben innerhalb ME 0 bis 10 und TE 0 bis 20 editierbar. Der
gespeicherte katalogweite Basisscan bleibt neutral und enthält keine erfundene
konkrete Blaupause. Ein neuer Scan speichert
zusätzlich die SDE-Grundmengen und Anlagenmultiplikatoren, damit lokale
ME-/TE-Änderungen dieselbe Material- und Zeitrundung wie der Planner verwenden.
Bei einem älteren Snapshot wird eine notwendige Näherung sichtbar gewarnt und
**Aktualisieren** liefert die fehlende exakte Basis.

Die vollständige Charge skaliert Materialrundung, Installation,
Produktionszeit, Hintransport des tatsächlichen Einkaufs, Rücktransport des
Produkts, gelisteten Verkauf und Gesamtgewinn gemeinsam. Der Produktionsort
wird dabei aus dem ausdrücklich gespeicherten Produktionsort der
Logistikkonfiguration gelesen. Ein als Main Hub gespeicherter Handelsort darf
einen abweichenden Produktionsort nicht mehr fälschlich zu einer kostenlosen
Route machen. Fehlende oder deaktivierte notwendige Logistik hält Gewinn, ROI
und Raten unverfügbar; nur ein tatsächlich gleicher Produktions- und
Marktstandort erzeugt null Transportkosten.

Die Chancenzeile bleibt ein schneller Vergleich des direkten veröffentlichten
Rezepts mit den gewichteten Preisen des gespeicherten Marktsnapshots. Der
Planner ist die maßgebliche konkrete Rechnung und kann Zwischenprodukte
rekursiv bauen, andere Blueprintkosten wählen und für größere Mengen tiefere
oder neuere Marktdaten verwenden. Ein Zahlenvergleich ist daher nur bei
gleicher Charge, ME/TE, Materialquelle, Blueprintkosten, Markttiefe und Route
gleichartig. **Bauen** übergibt Runs, tatsächliche Ausgabemenge, ME und TE
unverändert und nennt diese Annahmen im Planner sichtbar.

Optional kann in **Data & Settings → Industrie** der Vergleich mit
komprimierten Erzen aktiviert werden. Dafür lassen sich mehrere Refining-
Strukturen in unterschiedlichen Systemen hinterlegen. Jede verwendbare Anlage
benötigt einen aufgelösten Refining-Service, eine vom aktiven SDE abgeleitete
Erzausbeute und eine bestätigte Refining-Gebühr. Für alle Spielerstrukturen
(Upwell-Strukturen und eigene Strukturtypen) gilt ein leeres Gebührenfeld als
Standard-Servicegebühr von 1 %. Das Feld zeigt dann „Standard 1 %“, und ein
eingetragener Wert hat immer Vorrang. Nur bei NPC-Stationen bedeutet ein leeres
Gebührenfeld unbekannt. 0 % gilt nur als ausdrücklich bestätigte gebührenfreie
Anlage. Pro Anlage kann ein Charakter fest zugeordnet werden. Ohne feste
Zuordnung verwendet der Planner für jedes Erz den verbundenen Charakter mit
der höchsten vollständigen Ausbeute aus **Reprocessing**, **Reprocessing
Efficiency**, dem erzspezifischen **Processing**-Skill und seinem in diesem
Anlagenprofil gewählten Refining-Implantat. Pro Charakter kann ausdrücklich
kein Implantat oder ein **Zainou 'Beancounter' Reprocessing RX-801**, **RX-802**
beziehungsweise **RX-804** mit 1 %, 2 % oder 4 % Ertragsbonus gewählt werden.
Die exakte Implantatbezeichnung bleibt als EVE-Gegenstandsname kopierbar.
Diese Auswahl ist ausdrücklich eine theoretische Planannahme für die jeweilige
Anlage. Sie wird nicht aus dem aktuell aktiven Klon über ESI übernommen und
kann vor einer geplanten Klonumstellung eingestellt werden, ohne einen Wechsel
in EVE durchzuführen. Im Einstellungsbildschirm steht sie direkt neben dem
jeweiligen vorgesehenen Refiner.
Ältere Anlagenprofile ohne diese Auswahl werden als **kein Implantat** gelesen.
Verbotene oder
nicht verfügbare Skilldaten werden nicht als Skillstufe 0 ausgegeben;
beibehaltene teilweise oder veraltete Snapshots bleiben sichtbar.

Die Industrieeinstellungen zeigen für jede grundsätzlich relevante Refining-
Anlage getrennt, ob Refining-Service, Erzausbeute oder bestätigte Gebühr fehlen.
Damit ist insbesondere eine NPC-Station mit bekannter Ausbeute, aber leerem
Gebührenfeld ausdrücklich **unvollständig** und nicht scheinbar
unberücksichtigt. Änderungen an Anlage, Charakter oder Gebühr
werden bei der nächsten Planner-Berechnung verwendet; ein bereits angezeigter
Plan wird nicht still im Hintergrund umgeschrieben.

Zusätzlich nennt die Anlage die tatsächlich gewählte Ertragsquelle, deren
Ausbeute nach Sicherheitsraum-Multiplikator, den separaten Strukturbonus und
die daraus entstehende Grundausbeute vor dem Charakter. Wird bei einer Tatara
nur der Reprocessing-Service wirksam, weist die Oberfläche ausdrücklich auf
das fehlende stärkere kompatible Reprocessing-Rig hin. Ein **Standup L-Set
Reprocessing Monitor II** wird nur gerechnet, wenn es im Anlagenprofil
tatsächlich hinterlegt ist; ESI liefert keinen verlässlichen Nachweis der
eingebauten Rigs einer fremden Player Structure.

Die Anlagenbasis folgt der Upwell-Reprocessing-Formel und den Einheiten des
aktiven CCP-SDE. Zuerst wird das bessere Ergebnis aus dem
Reprocessing-Service und einem zur Materialart und Strukturgröße passenden Rig
gebildet. Der Rig-Wert aus Dogma-Attribut 717 enthält dabei bereits die
vollständige Basis, beispielsweise 0,53 für ein T2-Rig. Nur ein passendes Rig
erhält zusätzlich den Sicherheitsraummultiplikator. Danach werden der
Strukturbonus aus Dogma-Attribut 2722 – aktuell 2 % für Athanor beziehungsweise
5,5 % für Tatara –, die drei Charakter-Skillfaktoren und das gewählte
theoretische Implantat jeweils multiplikativ angewendet. Die allgemeinen
L-Set- und XL-Set-Reprocessing-Monitore gelten für Asteroiderz, Monderz und Eis;
die spezialisierten M-Set-Rigs nur für ihre jeweilige Materialart. Fehlende
oder nicht passende Daten werden nicht durch angenommene Boni ersetzt.

Der Planner berechnet zuerst weiterhin den vollständigen Mineralbedarf. Für
dessen ungedeckten Einkauf prüft er veröffentlichte komprimierte Erze aus dem
aktiven SDE-`typeMaterials`-Katalog gegen die vollständige Markttiefe am Main
Hub. Verglichen werden der direkte Mineraleinkauf und -transport mit
Erzeinkauf, Transport zur gewählten Refining-Anlage, skillabhängiger
Mineralausbeute und bestätigter Refining-Gebühr. Den Transport bewertet der
Planner bereits bei der Auswahl jedes Erzes am gemeinsamen Lieferpaket
Main Hub → Home Hub: Maßgeblich ist, wie sich die Kurierkosten aller
verbleibenden Direktkäufe zusammen mit den bereits gewählten Erzen nach
Vertragsaufteilung und Millionenrundung ändern. Ein separat gerundeter
Einzeltransport je Erz wird nicht mehr angesetzt. Reicht die Markttiefe am
Main Hub für eine vollständige Deckung durch ein Erz nicht aus, kauft der
Planner die dort tatsächlich angebotenen ganzen Chargen. Den Rest decken
weitere Erze oder der direkte Mineralkauf. Der Hinweis
`refining.ore-depth-limited` nennt die betroffenen Erze. Anschließend werden
beide vollständigen Wege nochmals mit der tatsächlichen Kurieraufteilung und
Millionenrundung bewertet. Nur ein positiver vollständiger Kostenvorteil
ersetzt Mineralien durch Erz. Ist der Vergleich in **Data & Settings →
Industrie** ausgeschaltet, kommt aber ein komprimiertes Erz für die gelieferten
Mineralien in Frage, zeigt der Planner den Bereich **Compressed-Ore-Vergleich**
mit dem Hinweis, dass der Vergleich ausgeschaltet ist und die Mineralien direkt
geliefert werden (`refining.comparison-disabled`). Andernfalls bleiben Mineralmenge, Logistik und
Multibuy unverändert. Der Ergebnis-Snapshot weist Erz, Chargen, Anlage,
Sonnensystem, Refining-Charakter, Skillzustand, Ausbeute, Mineralausgabe,
Implantat, Gebühr, beide Gesamtwege und Ersparnis getrennt aus. Der
Implantatbonus multipliziert den bereits aus Anlage und Skills ermittelten
Ertrag. Im automatischen Modus kann deshalb ein Charakter mit besserer
Gesamtausbeute einschließlich Implantat gewinnen; eine feste Zuordnung bleibt
bewusst bestehen.
Der Refining-Bereich ist im Planner als kompakte Offenlegung standardmäßig
geschlossen. Seine Kopfzeile zeigt Anzahl der gewählten Erze und Ersparnis;
aufgeklappt trennt er die Anlagen-Grundausbeute von der Gesamtausbeute nach
Skills und geplantem Implantat.

Ergebnisse werden für den gemeinsam aufbereiteten Stapel abgerundet:
`floor(SDE-Ausgabe je Charge × ganze Chargen × Gesamtausbeute)`. Der Planner
wählt die kleinste ganze Chargenzahl, deren einmal gerundetes Gesamtergebnis den
Bedarf deckt. Er rundet nicht jede Charge einzeln ab. Die bestätigte
Refining-Gebühr wird auf den Adjusted-Price-Schätzwert aller tatsächlich
entstehenden Mineralien einschließlich unvermeidbarer Chargenüberschüsse
angewendet.

Jede konkrete Raffinerieausgabe speichert ihren aus dem aktiven SDE aufgelösten
EVE-Typnamen, die gesamte produzierte Menge, den in diesem Plan verwendeten
Anteil und den geplanten Lagerüberschuss. Dadurch bleiben auch Nebenprodukte
wie Scandium sichtbar und kopierbar, obwohl sie im ursprünglichen
Produktionsbedarf nicht vorkommen. Nur der benötigte Anteil deckt offene
Mineralpositionen. Der Rest wird als geplanter Lagerzugang ausgewiesen, verändert
aber weder den faktischen ESI-Lagerbestand noch andere Pläne. Er erzeugt keine
Wertgutschrift: Vollständiger Erzeinkauf, Transport und Refining-Gebühr bleiben
dem hergestellten Produkt zugeordnet. Kann der aktive SDE-Katalog einen
Ausgabetyp wider Erwarten nicht benennen, bleiben Type-ID und Menge mit einer
ausdrücklichen Warnung erhalten; sie werden nicht als null oder als erfundener
Name dargestellt.

Das verpackte Transportvolumen (SDE zuerst, öffentliches ESI-`packaged_volume`
für Lücken) wird dabei nicht nur für normale Materialpositionen, sondern auch
unmittelbar für jede geprüfte komprimierte Erzoption verwendet. Das SDE
bleibt für Chargengröße, Mineralausgabe und den
erzspezifischen Processing-Skill zuständig. Dadurch geht ein vorhandenes
autoritativeres Transportvolumen zwischen Marktladen und Ore-Vergleich nicht
verloren.

Die Funktion benötigt SDE-Katalogadapter 3. Ein zuvor aktivierter Katalog bleibt
für vorhandene Funktionen lesbar, enthält aber nicht automatisch die neue
`typeMaterials`-Tabelle. Vor dem ersten Refining-Vergleich ist deshalb der
sichere Neuimport desselben SDE-Builds oder die Installation eines neueren
Builds und anschließend der dokumentierte App-Neustart erforderlich.
Der Main-Hub-Chancen-Snapshot enthält alle vollständigen veröffentlichten
Manufacturing-Definitionen und Reaktionsformeln des aktiven SDE. Fertigung
verwendet die je Produktklasse konfigurierte Fertigungsanlage. Freighter und Jump
Freighter zählen dabei zu **Large** (Anlage und Rig-Boni wie Battleships); Capital
sind Carrier, Dreadnought, Force Auxiliary, Supercarrier, Titan und Capital
Industrial Ship. Ob ein gebautes Schiff selbst springt, entscheidet seine
Schiffsgruppe, nicht diese Produktklasse; ein gebauter Jump Freighter springt
weiterhin selbst. Reaktionen
verwenden ausschließlich die getrennt konfigurierte Reaktionsanlage, deren
Reaktions-Systemkostenindex sowie die gemeinsame Reaktionsrundung für Material,
Dauer und Installation. Der Produktfilter **Reaktionen** prüft die tatsächliche
SDE-Aktivität und nicht mehr den zufälligen Kategorie- oder Gruppennamen.

Reaktionen besitzen weder ME noch TE; beide Spalten zeigen deshalb **—** und
sind nicht editierbar. Eine optionale Blueprint-Umlage betrifft nur
Manufacturing-Runs und wird Reaktionsformeln nie zugerechnet. Fehlt eine aktive
Verkaufsorder am exakten Main Hub, bleibt das vollständige Produkt als
Kandidatenzeile sichtbar. Erlös, Gewinn und davon abhängige Kennzahlen bleiben
dann mit konkreter Ursache unverfügbar, statt dass das Produkt aus dem Katalog
verschwindet. Ältere gespeicherte Chancen-Snapshots ohne Aktivitätskennzeichen
bleiben lesbar und gelten wie ihr damaliger Inhalt ausschließlich als
Manufacturing.

Der Chancen-Kern kann neben dem Main Hub auch Verkäufe am Home oder Coalition Hub
bewerten. Material kommt dabei immer vom Main Hub; Verkaufsmarkt, Bedarf,
Gebühren und Route stammen vom jeweiligen Hub. Es gibt drei Routen:

- **Main Hub:** Hin- und Rücktransport, wie bisher.
- **Home Hub:** nur der Hintransport zur Produktion, plus ein Weg zum Home Hub,
  falls die Produktion woanders liegt.
- **Coalition Hub:** wie Home Hub, zusätzlich der getrennt berechnete Transport
  Home → Coalition. Ist dieser unbekannt, bleibt der Gewinn unverfügbar.

Jede Rolle hat eigene Dateien (`market/home-hub-*.json`,
`market/coalition-hub-*.json`); die Main-Hub-Dateien heißen unverändert
`market/main-hub-*.json`.

Der **Home-Hub-Scan** läuft direkt im Anschluss an jeden Main-Hub-Scan.

- **Gleiche Steuerung:** Er übernimmt damit dessen 6-Stunden-Wiederverwendung,
  die Freigabe nach dem Startablauf, die Abrufpriorität und den
  Planner-Vorrang. Ohne Main-Hub-Scan (kein Main Hub konfiguriert) gibt es
  auch keinen Home-Hub-Scan.
- **Marktdaten:**
  - NPC-Station: das öffentliche Regions-Orderbuch, gefiltert auf die exakte
    Station.
  - Player Structure: `/markets/structures/{id}/` mit dem Scope
    `esi-markets.structure_markets.v1`. Den Zugang liefern die beim Start
    oder vom Dashboard übergebenen Charakter-Autorisierungen; der
    Home-Hub-Händler hat Vorrang.
- **Bedarf:** Ein eigener Bedarfsledger zählt nur die exakte Home-Location.
- **Rechnung:** Material wird zu Main-Hub-Preisen bewertet, Verkauf und
  Gebühren kommen aus dem Home-Hub-Händlerprofil.
- **Speicherung:** `market/home-hub-*.json`.
- **Sonderfälle:**
  - Home = Main: Es läuft kein zweiter Scan, die Main-Hub-Daten gelten.
  - Fehlende Autorisierung, fehlender Scope, verweigerter ACL-Zugriff oder ein
    unvollständiger Ort bleiben sichtbar unverfügbar. Ein vorhandener Stand
    bleibt als veraltet erhalten.
  - Ein Home-Hub-Fehler verändert die Main-Hub-Ergebnisse nicht.

Die Seitenleisten-Karte **Automatic data** zeigt den Stand in der Zeile
**Home-Hub-Markt**.

Der Navigationsbereich **Home-Hub-Chancen** steht direkt unter den
Main-Hub-Chancen.

- **Oberfläche:** dieselbe wie bei den Main-Hub-Chancen, mit Filtern, Spalten,
  Runs/ME/TE, Favoriten und **Bauen**.
- **Daten:** der gespeicherte Home-Hub-Scan.
- **Logistik:** nur der Hintransport vom Main Hub zur Produktion, ohne Rückweg
  zum Main Hub.
- **Gespeicherte Filter:** eigene Schlüssel
  (`market-opportunities.home.…`, `manufacturing-opportunity.home.…`).
  Suche, Kategorie, Gruppe, Ergebniswert, Produktarten, Produktionsklassen,
  Mindest-Tagesbedarf, Materialbudget und Aufklappzustände sind dadurch vom
  Main Hub getrennt. Favoriten, Blueprint-Umlage und der
  Corporation-Hangar-Schalter gelten für beide Hubs gemeinsam.
- **Texte:** Kopfzeile, Leerzustand, Fortschritt, Markt- und
  Bedarfsgrundlage sowie Verkaufswarnungen nennen den Home Hub. Warnungen zu
  Materialkäufen nennen weiter den Main Hub, weil dort eingekauft wird.
- **Aktualisieren** startet den gemeinsamen Main- und Home-Hub-Scan.
- **Bauen** übergibt zusätzlich den Zielmarkt „Home Hub“ an den Planner. Der
  Planner wertet ihn erst ab P10 aus.
- **Leerzustände:**
  - Ohne Home Hub erscheint ein Hinweis mit Sprung in die Markteinstellungen.
  - Bei Home = Main erscheint ein Hinweis mit Sprung zu den Main-Hub-Chancen.
  - Bei unvollständigem Ort erscheint ein Hinweis auf erneute Auswahl.
  - Ohne bisherigen Scan nennt die Ansicht den nächsten automatischen Lauf.

Der **Coalition-Hub-Scan** läuft im selben Main-Hub-Scan nach dem Home Hub,
mit denselben Regeln.

- **Markt:** Structure-Markt mit Charakter-Lease; der Coalition-Händler hat
  Vorrang.
- **Bedarf und Speicher:** eigener Bedarfsledger und eigener Snapshot unter
  `market/coalition-hub-*.json`.
- **Rechnung:** Material zu Main-Hub-Preisen, Verkauf und Gebühren aus dem
  Coalition-Händlerprofil.
- **Kein eigener Scan:** Ist der Coalition Hub gleich dem Main oder dem Home
  Hub, läuft kein zweiter Scan.
- **Transport Home → Coalition:** Wie im Planner gilt für jede Zeile:
  - Ist die Sprunglogistik aktiv, rechnet die App einen Jump-Freighter-Frachtflug
    mit der DOTLAN-Route des konfigurierten Rumpfs und Piloten und den
    Isotopenpreisen des Main Hubs.
  - Sonst rechnet sie den Profil-Kurier (m³-Tarif, 0,5-%-Sicherheitsuntergrenze,
    Millionenrundung).
  - Die Grundlage wird im Snapshot gespeichert, die Kosten entstehen je Zeile aus
    Menge und Erlös.
- **Wann der Transport unverfügbar bleibt:**
  - kein Home Hub,
  - deaktivierte Logistik ohne Sprunglogistik,
  - fehlender Tarif,
  - fehlende DOTLAN-Route oder fehlender Pilot.

  Der Gewinn ist dann ebenfalls nicht verfügbar und wird nie 0.
- **Capitals:** Sie dürfen am Coalition Hub verkauft werden. Ein selbstspringendes
  Capital bleibt ohne Sprunglogistik blockiert. Mit Sprunglogistik wird es in der
  Chancenliste ausdrücklich nicht gerechnet, weil seine rumpfspezifische Route
  der Planner bestimmt.
- **Fehler:** Fehlender Scope oder ACL-Zugriff bleibt sichtbar unverfügbar und
  verändert weder Main- noch Home-Ergebnisse.
- **Strukturmärkte (Home und Coalition):** Ist der Hub eine Spielerstruktur,
  lädt jeder Scan, auch der automatische beim Start, das **vollständige**
  Orderbuch der Struktur.
  - Bedarfsledger und Marktübersicht erfassen damit alle dort gelisteten Items,
    nicht nur Fertigungsprodukte. Das ist die Grundlage für den
    Bereich Handel.
  - Die Chancenanalyse erhält das Orderbuch weiterhin auf die
    Fertigungsprodukte beschränkt; ihre Ergebnisse und Abdeckungszahlen bleiben
    unverändert.
  - Die bisherige Bedarfshistorie der Produkte läuft weiter. Neu erfasste Items
    starten ohne Historie und zeigen keinen Tagesbedarf, bis zwei Scans im
    Abstand von mindestens 30 Minuten vorliegen.
  - Der Scan dauert dadurch länger, und die Bedarfsdatei wird größer
    (Eigentümerentscheid 22.10.2026).
- **Marktübersicht:** Sie enthält je Item neben dem besten Sell- und Buy-Preis
  auch die Stückzahl, die genau zu diesem Bestpreis gelistet ist (Ordertiefe).
  Ältere gespeicherte Übersichten ohne diese Angabe bleiben lesbar; die Tiefe
  ist dort unbekannt, nicht 0.

Die Karte **Automatic data** zeigt dazu die Zeile **Coalition-Hub-Markt**.

Der Bereich **Coalition-Hub-Chancen** steht direkt unter den Home-Hub-Chancen.

- **Grundlage:** dieselbe Oberfläche und Filterlogik, mit eigenen Schlüsseln
  (`market-opportunities.coalition.…`, `manufacturing-opportunity.coalition.…`).
- **Zusätzliche Spalte „Home → Coalition“:** Sie ist sortierbar; unbekannte
  Werte stehen aufsteigend am Ende. Der Betrag ist in den Kosten enthalten und
  wird nach Runs-Änderungen je Zeile neu berechnet.
- **Details:** Die Zeilendetails nennen den Betrag und, falls er unverfügbar
  ist, den konkreten Grund (zum Beispiel fehlende DOTLAN-Route, deaktivierte
  Logistik oder selbstspringendes Capital).
- **Texte:** Kopf- und Verkaufstexte nennen den Coalition Hub.
- **Bauen** übergibt den Zielmarkt „Coalition Hub“.
- **Leerzustände:**
  - kein Coalition Hub,
  - gleich Main Hub (mit Sprung zu den Main-Hub-Chancen),
  - gleich Home Hub (mit Sprung zu den Home-Hub-Chancen),
  - unvollständiger Ort,
  - noch kein Scan.

Alle drei Chancenansichten zeigen zusätzlich die sortierbaren Spalten
**Vertragspreis** und **Vertragsgewinn**.

- **Vertragspreis:** der niedrigste Stückpreis eines vergleichbaren
  öffentlichen Item-Exchange-Vertrags im lokalen Index. Es gilt dieselbe Regel
  wie beim Vertragshandel im Planner: genau der Produkttyp, eine
  Angebotsposition, keine Gegenposition, positiver Preis, Bündel
  ausgeschlossen, gesucht im gesamten importierten Universum, höchstens 500
  Angebote je Typ.
- **Vertragsgewinn:** Vertragspreis × Ausgabe, abzüglich des bestätigten
  Vertragsgebührensatzes des angezeigten Hubs und der Gesamtkosten.
  Marktsteuer und Brokergebühr entfallen. Fehlt ein bestätigter Satz, gelten
  Gewinn und ROI ausdrücklich „vor Vertragsgebühr“.
- **Zeilendetails:** Sie zeigen Vertragspreis, -erlös, -gebühr, -gewinn und
  -ROI sowie Hinweise zu fehlendem Angebot, vorläufigem Index oder fehlendem
  Satz.
- **Vorläufige Werte:** Solange der Index unvollständig ist, sind die Werte
  vorläufig und mit „≈“ markiert. Die Farbe zeigt nur das Vorzeichen:
  Vertragsgewinn grün mit „+“ ist ein Gewinn, rot mit „−“ ein Verlust; der
  Vertragspreis ist neutral. Der Mouse-Over einer Zelle nennt Vorzeichen,
  vorläufigen Index und fehlenden Gebührensatz.
- **Kein Angebot:** Der Wert bleibt unverfügbar, nie 0.
- **Sortierung:** Unbekannte Werte stehen aufsteigend nach den bekannten.
- **Datenquelle:** nur der lokale Vertragsindex, ohne ESI-Abruf, begrenzt auf
  die gewählten **Vertragsregionen** (Standard: gesamtes Universum). Gelesen
  wird gebündelt für die Typen des angezeigten Scans; ein gleicher Typsatz wird
  bei unveränderter Regionsauswahl fünf Minuten wiederverwendet, eine geänderte
  Auswahl lädt die Vertragspreise sofort neu.

Der tägliche Chancenwert ist `Gewinn je Einheit × beobachteter Tagesbedarf`.
Damit sind beispielsweise 1.000 Einheiten pro Tag mit 1 Million ISK Gewinn je
Einheit wirtschaftlich gleichrangig zu einer Einheit pro Tag mit 1 Milliarde
ISK Gewinn. Der Wert ist eine Vergleichskennzahl und keine Verkaufsgarantie.
**Bauen** öffnet den etablierten Planner und hängt die konkrete
Chancencharge mit Produktname, tatsächlicher Ausgabemenge und Runs an dessen
Eingabe an. Manufacturing-Zeilen übergeben zusätzlich ME/TE; bei Reaktionen
sind diese Werte nicht anwendbar. Die Chancenansicht besitzt dafür keinen eigenen Produktionsbaum,
kein Lager-Unterfenster und keine Untermenüs für Main Hub, Einkaufsliste oder
Kostendetails mehr. Marktchancen bleiben Analyse und Ranking; konkrete
Build/Buy-, Lager-, Einkaufs- und Bauplanentscheidungen gehören zum Planner.

Die frühere Aufteilung in **Einfaches Profil**, **Kostenschema** und
**Erweiterte Filter** ist innerhalb dieses bestehenden Menübereichs durch eine
gemeinsame, standardmäßig geöffnete Fläche **Filter** ersetzt. Die sieben
Karten **Bauplanbesitz**, **Bauplantyp und -quelle**, **Produkte**,
**Produktionsklasse**, **Katalog**, **Ergebnis** sowie **Kosten und Budget**
stehen in genau einer horizontal scrollbaren Reihe. Die Zielstückzahl ist keine
separate Szenariokarte mehr, sondern ein kompaktes Feld direkt am Kalkulator.
Jede Kartenüberschrift einschließlich Informationssymbol ist eine anklickbare
Schaltfläche und öffnet eine ausführliche, markierbare Erklärung zu Datenquelle,
UND-/ODER-Verknüpfung, unbekannten Zuständen, lokaler Filterwirkung und
Kostenfolgen. Relevante gelbe Ausrufezeichen öffnen ebenfalls eine konkrete
Ursachen- und Handlungserklärung; Hoverhilfe bleibt nur ergänzend.

Die Fläche kann als Ganzes eingeklappt werden; Filterzustände, Favoriten,
Kostenwerte und die fachliche Berechnung bleiben unverändert erhalten. Die
Datengrundlage und der längere Erklärungstext unter der Gegenstandssuche bilden
eine eigene, persistent ein-/ausklappbare Gruppe. Unaufgelöste Standorte,
Nachfragefehler und andere fachliche Warnungen bleiben außerhalb dieser Gruppe
immer sichtbar. Die sortierbaren Kennzahlen erklären weiterhin ihre Quelle und
Formel, insbesondere Gesamtkosten, Bruttoerlös, Verkaufssteuer, Brokergebühr,
Gewinn, tägliches Gewinnpotenzial, ROI, ISK/h und ISK/m³.

**Auftragsdauer und Industrie-Charaktere.** Der Planner weist zwei Zeiten aus:
Der **Gesamte Auftragszeitaufwand** addiert die Dauer aller Aufträge. Die
**Voraussichtliche Auftragsdauer** teilt die Aufträge zunächst auf und verteilt
dann alle Teilaufträge gleichzeitig auf die verfügbaren Fertigungs-, Reaktions-
und Wissenschafts-Slots (Kopieren, Forschung, Invention). Reaktionen,
Forschung und Fertigung von Teilen mit gekauften oder gelagerten Materialien
laufen damit parallel ab Planbeginn.

Aufteilung (Industrieeinstellungen → **Job Mode, Slots & Account**):

- **Fertigung** nutzt das Tage-Fenster. Ein Auftrag bis „Don't split jobs
  shorter than“ (Standard 1 Tag) bleibt ganz. Ein längerer Auftrag wird so
  geteilt, dass kein Teil „No jobs longer than“ (Standard 3 Tage) überschreitet,
  und darüber hinaus auf freie passende Slots verteilt, solange jeder Teil
  mindestens die Mindestdauer behält. Ein einzelner Run, der länger als die
  Höchstdauer ist, bleibt ein längerer Auftrag. Widersprechen sich Minimum und
  Maximum, gilt das Maximum.
- **Reaktionen** laufen in Stapeln von mindestens „Reaktions-Runs je Auftrag“
  (Standard 100 Runs, etwa 5–6 Tage). Ein Rest verlängert die Stapel
  gleichmäßig, statt einen kurzen Stapel zu erzeugen (250 Runs → 2 × 125,
  120 Runs → 1 × 120). Mit 0 Runs gilt auch für Reaktionen das Tage-Fenster.
- **Wissenschaftsaufträge** werden nicht geteilt.
- Runs werden gleichmäßig verteilt, frühere Teile erhalten die Zusatz-Runs; je
  Auftrag höchstens 500 Teile.
- Aufträge, die an eine ausgewählte BPO oder BPC gebunden sind, bleiben ganz.
  Geteilt werden nur Aufträge ohne konkreten Bauplan; das setzt voraus, dass
  genügend Kopien vorhanden oder gekauft sind.

**Bauauftragsliste und Materialrundung.** Die Teilaufträge sind die echten
Aufträge des Plans. Nach dem Aufbau des Produktionsbaums bildet der Planner je
hergestelltem Produkt den Gesamtbedarf über alle Zweige, teilt den Auftrag nach
den obigen Regeln und rundet jeden Input je Teilauftrag, wie EVE es je
installiertem Job tut (Fertigung: ME und Struktur-Multiplikator, mindestens ein
Stück je Run; Reaktionen: Struktur-Multiplikator). Produkte werden nach allen
ihren Verbrauchern berechnet, sodass Rundungsänderungen an die Vorprodukte
weitergegeben werden. Lagerbestand, Einkaufsliste, Herstellungsmengen, Kosten,
Installationskosten und Bauauftragsliste verwenden diese Werte; die
Bauauftragsliste zeigt je Teil „Auftrag k von n“ und die Dauer. Der
Produktionsbaum zeigt weiter den Bedarf je Zweig. Die Materialkosten je
Planzeile in der Produktionsübersicht werden nach den Zweigwerten gewichtet und
auf die Materialkosten des Plans skaliert, sodass ihre Summe dem Planwert
entspricht.

Abhängigkeiten: EVE verbraucht Materialien beim Start. Ein Teilauftrag wartet
deshalb nur auf seinen **Anteil** an im Plan selbst hergestellten Vorprodukten:
Ein Teil, der den Anteil f der Runs seines Produkts abschließt, wartet auf die
Teile des Vorprodukts bis zum Anteil f von dessen Runs. Sobald die ersten
Reaktionsstapel fertig sind, kann so die erste Komponente beginnen. Jeder Teil
eines mit Kopie, Forschung oder Invention versorgten Fertigungsauftrags wartet
auf diese Wissenschaftsaufträge, die untereinander in ihrer Reihenfolge laufen.
Gekaufte und gelagerte Materialien sowie vorhandene oder gekaufte BPCs stehen
sofort bereit. Vergeben wird deterministisch nach frühestmöglichem Start, dann
nach längstem verbleibendem kritischem Pfad.

Unter der Dauer nennt der Planner Slot-Quelle, Slot-Zahlen und die verwendete
Aufteilung. Die Aufklappliste **Zeitplan** zeigt jeden eingeplanten Teilauftrag
mit Produkt, Tätigkeit, Runs, Teil, Start, Ende und Dauer (Abstände ab
Planbeginn); alle Spalten sind sortierbar, Standard ist der Start.

Die Slots kommen aus **Industrieeinstellungen → Industrie-Charaktere**. Für jeden
verbundenen Charakter wird festgelegt, ob er für die Industrie verwendet wird,
welche Tätigkeiten er übernehmen darf (Fertigung, Reaktionen, Kopieren,
Forschung, Invention) und optional eine Slot-Grenze je Slot-Art. Das
Skill-Maximum ergibt sich aus den synchronisierten aktiven Skillstufen:
Fertigung 1 + Mass Production + Advanced Mass Production, Wissenschaft
1 + Laboratory Operation + Advanced Laboratory Operation (gemeinsam für Kopieren,
Forschung und Invention), Reaktionen 1 + Mass Reactions + Advanced Mass
Reactions, ohne den Skill Reactions jedoch 0. Wirksam ist das Minimum aus
Skill-Maximum und Grenze; eine leere Grenze bedeutet Skill-Maximum. Sind die
Skills eines Charakters nicht verfügbar, zählt nur eine ausdrücklich
eingetragene Grenze (mit Warnung), sonst trägt er keine Slots bei. Solange kein
Charakter freigegeben ist, gelten die manuellen Slot-Zahlen für Fertigung,
Reaktionen und Wissenschaft unter **Job Mode, Slots & Account**. Darf kein
freigegebener Charakter eine benötigte Tätigkeit ausführen, bleibt die
Auftragsdauer ausdrücklich **Nicht verfügbar**. Pläne, die vor dieser Rechnung
gespeichert wurden, zeigen ihre damals berechnete Dauer unverändert und keinen
Zeitplan.

Die Warnungsliste des Planners zeigt nur entscheidende Meldungen: blockierende
Warnungen zuerst, danach Warnungen mit Einfluss auf Ergebnis oder Handlung.
Reine Informationshinweise (zum Beispiel nicht baubare Fuel Blocks aus der
Produktionssperrliste, die Makespan-Schätzung aus Slotzahlen oder eigene Blueprints
mit 0 ISK) werden dort nicht angezeigt; gleichlautende Meldungen mehrerer
Planungsstufen erscheinen einmal. Meldungen zu fehlenden Blueprint-Runs und zu
Items, die für einen Kurierauftrag zu groß sind, nennen den Blueprint- bzw.
Itemnamen statt einer Typ-ID; nur ein nicht auflösbarer Name bleibt ausdrücklich
als unaufgelöster Typ mit ID sichtbar. Die Meldungstexte sind englisch.

Im Planner ist die Blueprintquelle jedes tatsächlich gebauten Knotens
kostenwirksam. Eine vorhandene BPO, für die kein Betrag eingetragen ist, zählt
mit **0 ISK**; ein Hinweis nennt, wie viele Blueprints so eingerechnet sind.
Eine eigene BPC ohne eingetragenen Betrag wird je verbrauchtem Run bewertet
(Eigentümerentscheidung 20.10.2026):
1. günstigster Preis je Run öffentlicher Einzel-BPC-Verträge am Main Hub mit
   mindestens gleichem ME und TE,
2. sonst geschätzte Herstellungskosten: bei T1-Kopien die Kopierauftragskosten
   (geschätzter Itemwert des Produkts aus ME0-Materialien zu Adjusted Prices
   × 2 % × Gebührenfaktor der konfigurierten Kopieranlage), bei erfundenen
   Kopien die erwarteten Inventionskosten je Run: (Kopierkosten eines T1-Runs +
   Datacores + Decryptor zu Main-Hub-Kaufpreisen + Inventionsgebühr, Itemwert des
   T2-Produkts × 2 % × Gebührenfaktor der Inventionsanlage) ÷ (Erfolgschance ×
   Runs je Erfolg). Der Decryptor wird aus ME/TE (Basis ME 2/TE 4) und, bei
   unbenutzten Kopien, den Runs abgeleitet; passen mehrere Decryptoren (z. B.
Parity und Optimized Attainment nach verbrauchten Runs), gilt der Mittelwert
ihrer erwarteten Inventionskosten; die Erfolgschance nutzt die
   höchsten trainierten Skills aller synchronisierten Charaktere,
3. sonst 0 ISK.
Die Herkunft steht in den BPC/BPO-Details; Schätzungen sind als solche
gekennzeichnet. Ohne konfigurierte Kopier- bzw. Inventionsanlage, Itemwerte,
Skills oder Marktpreise ist keine Schätzung möglich. Der Faktor 2 % für die
Inventionsgebühr ist im EVE University Wiki nur für Kopieren belegt und für
Invention eine Annahme. Ein eingetragener Erwerbs-, Aktivitätsbetrag oder eine Umlage
ersetzt diese 0 ISK. Kopieren, Invention, Loyalty-Store- und manuell externe BPCs
sowie gekaufte BPOs benötigen weiterhin einen ausdrücklichen Betrag. Beim Kauf über
öffentliche Verträge werden nur aktive Item-Exchange-Verträge am exakten Main
Hub automatisch zugerechnet, wenn Preis, BPC-Kennung, Runs, ME und TE bekannt
sind und der Vertrag genau eine angebotene Blueprintposition ohne angeforderte
Gegenposition enthält. Mehrere eindeutig zurechenbare BPCs dürfen gemeinsam
alle benötigten Runs decken, erzeugen dabei jedoch immer getrennte Jobs. Als
BPC-Kosten gilt die konkrete Vertragsauswahl des Bauplan-Versorgungsplans, die
auch Runs und ME/TE der Jobs bestimmt: Jeder Vertrag zählt mit seinem vollen
Preis, auch wenn nur ein Teil seiner Runs gebraucht wird (Beispiel: 5 Runs aus
einer 3-Run-BPC und zwei von drei Runs einer weiteren 3-Run-BPC). Decken die
Verträge die benötigten Runs nicht vollständig, bleibt der Bauplan ungeklärt.
Ein angefragtes Endprodukt erscheint in der BPO/BPC-Auflösung immer als
Bauschritt, auch wenn für denselben Typ eine Kauf-Vorgabe besteht. Die
BPO/BPC-Auflösung des Planners verwendet genau die Bau-/Kaufvorgaben der
endgültigen Berechnung; Typen ohne eigene Vorgabe folgen der Planner-Regel
(bauen, wenn möglich, Blacklist beachtet), nicht der Kauf-/Bauempfehlung. Damit
stimmen Bauschritte und Run-Zahlen der Blueprint-Versorgung mit dem
berechneten Plan überein. Reicht ein vorab geplanter Versorgungsjob auf einem
Blueprint-Original (BPO) nicht für alle Runs, läuft der Rest auf demselben
Original weiter; nur endliche BPC-Runs können eine Fehlmenge erzeugen. Ein
BPO-Kaufpreis wird vollständig angezeigt, aber nicht ohne
eingetragene Umlage einer einzelnen Produktion belastet. Bündel, Nullpreise und
alte Vertragszeilen ohne Runs/ME/TE bleiben ausdrücklich unkalkulierbar. Fehlt
bei irgendeinem produzierten Knoten eine Blueprintkostenquelle (zum Beispiel
gar kein Blueprint vorhanden), bleiben Gesamtkosten und Gewinn unverfügbar.
In diesem Fall zeigen auch die BPC/BPO-Karte, die Produktionszwischensumme und
alle Verkaufsszenarien „nicht verfügbar“ statt 0 ISK; die BPC/BPO-Details nennen
die Zahl der ungeklärten Bauplanquellen.
**Produktionskosten pro Einheit** sind die Produktionskosten inklusive Lieferung
Main Hub → Home Hub geteilt durch die erzeugten Endprodukteinheiten; sind diese
Gesamtkosten nicht verfügbar, ist auch der Wert pro Einheit nicht verfügbar.

Der öffentliche Vertragsindex übernimmt für Blueprintpositionen die von ESI
gelieferten Werte **Runs**, **ME**, **TE** und **BPC/BPO**. Neue
Detailimporte speichern diese Felder direkt. Ältere, bereits fertig indizierte
Vertragszeilen ohne diese Felder bleiben ausdrücklich unbekannt und werden
nicht gesammelt erneut bei ESI angefordert. Die frühere v1-Bestandsnachpflege,
die alle erkannten Blueprintverträge auf einmal in die normale Warteschlange
gestellt hatte, wird beim Öffnen einmalig zurückgenommen: Nur unberührte
Nachpflegeeinträge ohne Fehler und ohne neue Blueprintdetails kehren zu ihrem
letzten durchsuchbaren Zustand zurück. Bereits erfolgreich aktualisierte oder
wirklich fehlgeschlagene Verträge behalten ihren jeweiligen Zustand.

Die Chancenfilter bestehen aus zwei gleichzeitig anwendbaren
Mehrfachauswahlen. Innerhalb der Produktionsklassen können **Tech I**, **Tech
II**, **Tech III**, **Faction**, **Storyline** und **Sonstige / nicht
klassifiziert** gemeinsam gewählt werden; unabhängig davon lassen sich
Produktarten wie **Schiffe**, **Module**, **Rigs**, **Komponenten** oder
**Drohnen** kombinieren. Innerhalb einer Gruppe gilt ODER, zwischen
Produktionsklasse und Produktart gilt UND. Die Einstufung verwendet
ausschließlich `metaGroupID` und `techLevel` des aktiven SDE-Typdatensatzes.
Ein alter Katalog oder gespeicherter Scan ohne diese Felder bleibt ausdrücklich
nicht klassifiziert und wird nicht aus dem Namen geraten.

Die Main-Hub-Ansicht filtert derzeit bewusst weder nach Bauplanbesitz noch nach
Bauplantyp oder Bauplanquelle. Die zugrunde liegenden Besitz- und LP-Katalogdaten
bleiben für andere Abläufe erhalten, beeinflussen diese Chancenliste aber nicht.
**Favoriten** stehen als eigene kleine Filterkarte direkt unter den
Produktionsklassen und sind nicht mehr Teil der Ergebnisbewertung. Die
verbleibenden Karten verwenden ein breitenadaptives Raster statt einer festen
horizontalen Kartenzeile.

Die lokale Main-Hub-Filterauswahl bleibt über App-Neustarts erhalten. Gespeichert
werden Suchtext, Produktarten, Produktionsklassen, Favoritenmodus, Kategorie,
Gruppe, Ergebniswert, Mindest-Tagesbedarf, Materialbudget und der Aufklappzustand
der Filter. **Filter löschen**, **Alle auswählen** und **Alle abwählen** schreiben
ihren neuen Zustand ebenfalls sofort. Existiert eine zuvor gewählte exakte
Kategorie oder Gruppe im neu geladenen Chancen-Snapshot nicht mehr, wird nur
diese ungültige Auswahl auf **Alle** zurückgesetzt; fehlende SDE-Werte werden
nicht erfunden.

In der gemeinsamen Karte **Kosten und Budget** begrenzt **Maximale
Materialeinkäufe (ISK)** das
neue Wallet-Geld für die nach Lager, Schutzbeständen und aktiven Reservierungen
verbleibende Materialfehlmenge. Bereits vorhandener Lagerbestand behält in der
Gewinnrechnung seinen Wiederbeschaffungswert, verbraucht dieses Geldlimit aber
nicht. Bei aktivem Limit werden Kandidaten mit unbekannter Einkaufsabdeckung
ausgeschlossen, nicht als kostenlos angenommen. Das Limit filtert die bereits
lokal vorbereiteten Chancen und löst weder einen ESI-Abruf noch eine erneute
vollständige Kostenprojektion aus.

**Mindestwert Ø Tagesbedarf** ist ein lokaler Schnellfilter auf den belegten
Durchschnitt der bekannten Bedarfstage. `0` deaktiviert ihn und lässt auch
unbekannte Durchschnitte sichtbar. Ab `1` werden nur Zeilen mit einem bekannten
Durchschnitt mindestens in der eingegebenen Höhe angezeigt; unbekannt wird
nicht als null behandelt. Der Filter löst weder ESI noch einen neuen Scan aus.

Gesamtkosten bestehen aus Material-Wiederbeschaffungswert, Installation,
Blueprint-Anteil und den erforderlichen Wegen der Profillogistik.

Blueprint-Anteil: Loyalty-Store-, Fraktions- und Storyline-Blaupausen gibt es
nur als BPC. Eine Manufacturing-Zeile braucht einen BPC-Kauf, wenn ihre
Blaupause im zuletzt geladenen LP-Store-Katalog angeboten wird oder ihr Produkt
Fraktion (Metagruppe 4) oder Storyline (Metagruppe 3) ist. Erste Route: Aus dem
lokalen Vertragsindex wählt die App die günstigste Abdeckung aus
zuordenbaren BPC-Verträgen (Item Exchange, genau eine BPC, Runs, ME und TE
bekannt) in den gewählten **Vertragsregionen**. Der Kostenanteil ist der
Kaufpreis mal genutzte Runs / gekaufte Runs; restliche Runs behalten ihren
Wert für eine spätere Charge.

Tech-II- und Tech-III-Zeilen (Metagruppe 2 bzw. 14) brauchen eine erfundene
BPC. Ihre Route ist die erwartete Erfindung ohne Decryptor, je Versuch:
Kopierjob der T1-Blaupause (EIV × 2 % × Gebührenfaktor der Kopieranlage),
Datacores zum Orderbuch des Main Hubs und Erfindungsjobgebühr (Gebührenfaktor
der Erfindungsanlage). Geteilt wird durch die Erfolgschance mit den besten
trainierten Skills über alle Charaktere und durch die Output-Runs. Das ergibt
Kosten je Run, die mit den Runs der Zeile multipliziert werden. Es ist dieselbe
Rechnung wie bei der Planner-Bewertung eigener T2-BPCs. Die Schätzungen werden
beim Öffnen eines Hubs für dessen T2/T3-Blaupausen berechnet und eine Stunde
wiederverwendet. Hat die Blaupause laut SDE keine Erfindungsquelle, gilt sie als
normale Blaupause. Reverse Engineering (Tech III) oder fehlende Preise,
Datacore-Orders oder Anlagen machen die Erfindungsroute unverfügbar. Bis eine
Schätzung vorliegt, ist sie ebenfalls unverfügbar, nie kostenlos.

Weitere Route ist der LP-Store. Kosten je Kauf: ISK-Kosten + Pflichtgegenstände
(ESI-Durchschnittspreis) + LP × LP-Wert der anbietenden Corporation. Der
LP-Wert wird selbst berechnet: Für jedes Angebot dieser Corporation mit
bepreistem Produkt und bepreisten Pflichtgegenständen gilt
`(Produktwert − ISK-Kosten − Pflichtgegenstände) / LP`; der LP-Wert ist der
Median der fünf besten positiven Angebote, Blaupausen-Angebote ausgenommen.
ESI nennt die Runs einer LP-Store-BPC nicht. Verwendet wird die häufigste
Run-Zahl unerforschter BPC-Verträge (ME 0, TE 0) desselben Typs; ohne Beleg
wird ein Run je BPC angenommen, was die Kosten höchstens überschätzt. Auch hier
wird anteilig je genutztem Run gerechnet.

Die LP-Route zählt nur, wenn ein Charakter bei der Corporation genug LP hat
(ESI-Scope `esi-characters.read_loyalty.v1`, abgerufen bei jeder
Charaktersynchronisierung, gespeichert in
`market/character-loyalty-points.json`). Unbekannte LP (Scope fehlt oder noch
nicht synchronisiert) sind kein Guthaben von null. Eingepreist wird die
günstigste nutzbare Route (Erfindung, Vertrag oder LP-Store); ohne nutzbare
Route bleiben Kosten, Gewinn und
davon abhängige Kennzahlen unverfügbar. Der BPC-Kauf ersetzt die manuelle
Blueprint-Umlage. Mit **Eigene BPCs vorhanden** unter Kosten und Budget wird
der Kauf nicht eingepreist; dann gilt die optionale Blueprint-Umlage.

Die Zeilendetails zeigen den Abschnitt **Blaupausenbeschaffung**: gewählte
Route, Erfindung mit Kosten je Versuch, Erfolgschance, Runs je Erfolg und
Gesamtbetrag, Vertragsroute, LP-Route mit Corporation, Käufen, Runs, LP, Store-Kosten,
Pflichtgegenständen, LP-Wert und Gesamtanteil sowie ob der Charakter mit den
meisten LP genug LP und genug Wallet-ISK für Store-Kosten und
Pflichtgegenstände hat. Der Mouse-Over der Kostenzelle fasst den BPC-Anteil
zusammen; die Kostenkennzahl heißt dann **BPC-Kauf**. Bei einem unvollständigen
Vertragsindex ist der Vertragspreis vorläufig. Alle übrigen Blaupausen nutzen
weiterhin die optionale Blueprint-Umlage.

Jeder Spaltenkopf der Chancentabelle erklärt seine Berechnung im Mouse-Over.
Der Bruttoerlös ist der niedrigste aktive Verkaufsorderpreis am exakten Main
Hub mal vollständiger Szenarioausgabe. Verkaufssteuer und Brokergebühr stammen
aus dem konfigurierten Main-Hub-Händlerprofil und werden vom Bruttoerlös
abgezogen. `Gewinn = Bruttoerlös − Verkaufssteuer − Brokergebühr −
Gesamtkosten`; das tägliche Gewinnpotenzial ist `Gewinn / produzierte Einheiten
× Minimum(produzierte Einheiten, aktuell beobachteter Tagesbedarf)`. Es
entspricht bei ausreichendem Tagesbedarf höchstens dem Gewinn der gewählten
Charge und sinkt bei geringerem Tagesbedarf proportional. Fehlende Eingaben oder Quelldaten bleiben
unverfügbar. Ganzzahlen und ISK-Werte verwenden in der deutschen Oberfläche
automatisch Punkte als Tausendertrennzeichen, auch in Runs-, Kosten- und
Budgeteingaben.

Eine globale Zielmenge für alle Chancen gibt es im Kalkulator nicht mehr. Die
Felder **Runs**, **ME** und **TE** sind je Gegenstand direkt in der
Tabellenzeile editierbar. Eine gültige Änderung projiziert nur diesen Kandidaten
neu: Ausgabe, gerundeter Materialbedarf, Dauer, Installation,
Lager-/Einkaufsaufteilung, Logistik, Gebühren, Kosten und Gewinn werden für
diese Zeile aktualisiert; alle anderen Kandidaten behalten ihre vorbereitete
Projektion. Dabei bleibt auch die aktuelle Zeilenreihenfolge unverändert, damit
das aktive Eingabefeld und die Scrollposition nicht durch eine automatische
Neusortierung verspringen. Erst ein ausdrücklicher Klick auf einen Spaltenkopf
sortiert erneut und verwendet dann die sichtbaren projizierten Werte. Die
schnelle Einzelprojektion verwendet die im gespeicherten
Main-Hub-Snapshot erfassten gewichteten Stückpreise und kennzeichnet diese
Grenze. Erst **Aktualisieren** lädt neue Markttiefe. Beim Wechsel auf einen
neuen Chancen-Snapshot werden die sitzungsgebundenen Runs-/ME-/TE-Änderungen
verworfen.

Die Aktion **Bauen** übergibt die aktuell sichtbare Ausgabemenge, Runs, ME und
TE mit einem Klick direkt an den etablierten Planner. Die kompakte
Chancenansicht besitzt keinen eigenen Produktionsbaum und erfindet deshalb
keine konkrete Blueprintquelle oder einen `BlueprintSupplyPlan`. Der Planner
löst dort den rekursiven Produktionsbaum sowie die konkreten BPO-/BPC-Quellen
auf. Ist der Planner leer und besitzt kein berechnetes Ergebnis, wird die neue
Zeile direkt als Entwurf übernommen. Bei einem vorhandenen Entwurf oder
Ergebnis zeigt er vor jeder Änderung den neuen Gegenstand und bietet
**Aktuelle Berechnung ersetzen**, **Zum aktuellen Entwurf hinzufügen** sowie
**Aktuelle Berechnung behalten** an. Ein ungültiger alter Entwurf blockiert
damit die gültige neue Zeile nicht mehr: Beim Ersetzen werden seine
sitzungsgebundenen Produktionsbaum-, Quellen- und Effizienzauswahlen entfernt.
Der gespeicherte bisher aktive Plan wird erst nach einer erfolgreichen neuen
Berechnung deaktiviert und nicht schon durch die Vorschau gelöscht. Die
übergebenen ME/TE-Werte bleiben bis zur Auswahl einer faktischen Quelle eine
gekennzeichnete Screening-Hypothese. Der normale Produktpicker innerhalb des
Planners fügt dagegen weiterhin bewusst eine weitere Zeile an.

Die BPO-/BPC-Auswahl des Planners verwendet dasselbe gespeicherte
persönliche Blueprint-Inventar wie der Blaupausenbereich. Eigene BPCs und BPOs
werden nur bei einem konkret gespeicherten Bestand und nur am eindeutig
passenden konfigurierten Produktionsort angeboten; Charaktername, Standort,
Anzahl und verfügbare BPC-Runs bleiben sichtbar. Ein frischer, teilweiser oder
ausdrücklich als veraltet beibehaltener Snapshot darf eine konkrete Instanz
belegen. Nicht-frische Evidenz wird sichtbar gewarnt und macht den Gesamtbestand
nie „vollständig“; verbotene oder unverfügbare Quellen ohne beibehaltenen Wert
werden nicht als Besitz ausgelegt. Der Standortabgleich verwendet über den
Asset-Baum den tatsächlichen Wurzelstandort, sodass eine Blaupause in einem
Container am Produktionsstandort korrekt erkannt wird. Liegt ein eigenes BPO
oder BPC an einem anderen bekannten Standort, bleibt die konkrete Instanz
auswählbar und erzeugt einen Transfer zur Produktionsanlage. Ein unbekannter
Quell- oder Zielort blockiert den Plan. Mehrere BPCs gleicher oder
unterschiedlicher ME-/TE-Qualität dürfen gemeinsam die benötigten Runs
abdecken; jede konkrete BPC bleibt dabei ein getrennter Fertigungsjob mit
eigener Rundung und wird nie zu einer fiktiven Kopie zusammengezogen.
Die Auswahl **Bevorzugter Bauplan** (Planner) bzw. **Konkreter Bauplan**
(Produktionsbaum) beschreibt jede Quelle über Standort, Runs, ME und TE, bei
Verträgen und Marktaufträgen zusätzlich über den Preis; Item-, Vertrags- und
Auftrags-IDs erscheinen dort nicht mehr. Eigene Baupläne außerhalb des
Produktionsorts tragen den Zusatz „anderer Ort“, ein unaufgelöster Standort
bleibt als „Ort ungeklärt“ sichtbar. Quellen mit identischem Standort,
Runs, ME, TE und Preis werden zu einem Eintrag wie „10× · Ort · 1 Durchlauf ·
ME 9 · TE 14“ zusammengefasst. Die Wahl eines zusammengefassten Eintrags übergibt
alle enthaltenen Instanzen als bevorzugte Reihenfolge an die Zuteilung; die
Fertigungsjobs bleiben je Instanz getrennt.
Enthält ein rekursiver Produktionsbaum denselben Blueprint-Typ an mehreren
Knoten, darf seine bereits typweit aggregierte Bewertung entsprechend mehrfach
im Baum erscheinen. Die Versorgungsplanung gruppiert diese Projektionen sicher
nach Blueprint-Typ, summiert die Runs über alle tatsächlich produzierten
Knoten genau einmal und verwendet den gemeinsamen konkreten Quellenbestand.
Eine leere erste oder eine andere vollständig leere Planner-Eingabezeile wird
ignoriert; sie erzeugt weder einen Auftrag noch einen Fehler und verändert die
Zeilennummern der folgenden Eingabe nicht.
Reichen sie nicht, kann der Planner mehrere eindeutig
zuordenbare Einzel-BPC-Verträge am exakten Main Hub zu einer Run-Abdeckung
zusammenstellen und deren vollständige Vertragspreise als BPC-Kosten der
Charge ansetzen. Bündelverträge, fehlende Blueprint-Details und unvollständige
Contract-Abdeckung werden nicht als billige oder nicht vorhandene Blaupause
interpretiert. Ein BPO-Kauf oder eine bereits besessene BPO benötigt weiterhin
eine ausdrücklich eingegebene Umlage für diesen Plan; unbekannte historische
Anschaffungskosten werden nicht zu null erfunden.

T1-BPOs aus tatsächlichen Sell Orders am Main Hub und BPO-Verträge sind
getrennte Quellen. Der Markt- oder Vertragspreis ist Kapitalbedarf; in die
Charge fließt ausschließlich die gewählte BPO-Umlage ein. Normale Marktorders
werden niemals als BPC interpretiert.

Das Tagesbedarf-Ledger bewahrt für den exakten Main Hub zusätzlich den letzten
gültigen Bedarfsstand jedes UTC-Tages für höchstens 30 Tage. Jede neue
vergleichbare Beobachtung ersetzt nur den Stand ihres UTC-Tages. In der Tabelle
werden – soweit belegt – aktueller Tagesbedarf, der exakt vorherige UTC-Tag,
die ungefähre Veränderung zum Vortag und der gerundete Durchschnitt aller
bekannten Tage angezeigt. Ein fehlender Vortag oder ein für einen Typ nicht
belegter Tag wird ausgelassen und niemals als null angenommen. Ein Wechsel von
Region oder exaktem Hub beginnt eine neue Historie. Bestehende alte Ledger
können frühere Tage nicht rückwirkend rekonstruieren; die Historie wächst ab
den folgenden gültigen Aktualisierungen. Die großen Chancen-Snapshots speichern
nur die abgeleiteten Zeilenwerte, nicht die vollständigen Tageswörterbücher.

Der LP-Store-Katalog wird beim Start automatisch geladen, wenn er fehlt,
noch keine Angebotsdetails enthält oder älter als ein Tag ist
(`market/loyalty-store-catalog.json`). Er speichert alle Angebote der
NPC-Corporations mit LP, ISK, Pflichtgegenständen und Menge, die
Corporation-Namen und die ESI-Durchschnittspreise der angebotenen Produkte und
Pflichtgegenstände. Die Seitenleiste zeigt unter **Automatische Daten** die
Zeile **LP-Stores** mit Angebotszahl, Stand, Anzahl der Charaktere mit
bekannten LP und Charakteren ohne LP-Scope. Der
Main-Hub-Chancenfilter **Loyalty-Store-BPCs** samt Aktualisierungsschaltfläche
ist derzeit ausgeblendet und schränkt die Main-Hub-Kandidaten nicht ein.

Der sortierbare Spaltenkopf der Opportunity-Tabelle bleibt beim vertikalen
Scrollen am oberen Tabellenrand angeheftet. So bleiben Aufgabe, Gegenstand,
Tagesbedarf und alle Kalkulationskennzahlen sichtbar. Zwischen **ISK/h**,
**ISK/m³** und **Gruppe** trennen zusätzliche Abstände die Werte eindeutig.
Die Tabelle verwendet getrennte horizontale und vertikale Scrollbereiche:
Der Kopf liegt außerhalb des vertikalen Zeilenscrollers, bewegt sich horizontal
aber gemeinsam mit den Spalten. Dadurch bleibt er sichtbar, ohne eine
zweiachsig angeheftete SwiftUI-Section zu verwenden; ungültige oder negative
Viewport-Geometrie wird in den dynamischen Chancen-Teilansichten vor der
Weiterverwendung verworfen. Filter und Datengrundlage liegen in einem eigenen
Scrollbereich, dessen Höhe aus Fenstergröße und tatsächlichem Aufklappzustand
abgeleitet und auf höchstens 48 Prozent der verfügbaren Seitenhöhe begrenzt
wird. Beim Einklappen eines oder beider Bereiche schrumpft dieser obere
Abschnitt sofort; der Kalkulator dockt an und übernimmt den frei werdenden
Platz. Die Chancenliste füllt die gesamte verbleibende Fläche; ein unterer
Lager-/Main-Hub-/Einkaufs-/Kosten-Arbeitsbereich wird nicht mehr dargestellt.

Mehrere Make-or-Buy-Änderungen werden weiterhin zunächst lokal gesammelt und
erst über eine gemeinsame Neuberechnung angewendet. Der Rechenkern löst Namen,
Klassifikationen und verpackte Transportvolumina für den gesamten begrenzten
Produktionsgraphen gebündelt auf. Der unmittelbar folgende ausgewählte
Szenariolauf darf einen Make-or-Buy-Vergleich aus seinem Referenzlauf nur bei
identischem SDE-Build, Regelstand, Marktsnapshot und identischer Bedarfsmenge
wiederverwenden; ein neuer Markt-Snapshot erzwingt eine neue Rechnung. Preise,
Markttiefe, Gebühren, Rundungen und Build/Buy-Regeln ändern sich dadurch nicht.
Während der interaktiven Berechnung pausiert die vorhandene Koordination
konkurrierende automatische Main-Hub- und Public-Contracts-Arbeit; der
ESI-Antwortcache wird anschließend wie beim etablierten Planner begrenzt.

Der etablierte Planner trennt die **Produktionskosten** von den
Verkaufsstrategien. Die Kostenkarte addiert den vollständigen
Main-Hub-Materialwiederbeschaffungswert einschließlich Lagerverbrauch, die
ausdrückliche BPC-/BPO-Umlage und Installation. Direkt darunter stehen einmalig
die Produktionskosten pro Endprodukteinheit, die vollständige Lieferung
**Main Hub → Home Hub** und die Produktionskosten einschließlich dieser
Lieferung. Die Lieferkarte verwendet bereits die nach einer wirtschaftlichen
Compressed-Ore-Substitution neu zusammengesetzte Fracht; ihre aufklappbaren
Verträge enthalten die konkreten Gegenstände und Mengen. Der
**Lagerverbrauch** steht als informativer Teilwert in einer eigenen Karte und
wird nicht ein zweites Mal addiert. Systemindex, Facility Tax, SCC- und
Alpha-Zuschlag bleiben über die Installationsgleichung nachvollziehbar.

Die Facility Tax (Anlagensteuer) für Fertigung, Reaktionen und Forschung
beträgt bei allen Spielerstrukturen standardmäßig 1 %, solange in den
Struktureinstellungen kein eigener Wert eingetragen ist. Das leere Feld zeigt
„Standard 1 %“. Ein eingetragener Wert hat Vorrang, auch ausdrücklich 0 %.
NPC-Stationen haben keinen solchen Standard und verwenden ihren gespeicherten
Wert. Gespeicherte Strukturen aus der Zeit vor diesem Standard enthalten den
früheren Vorgabewert 0 %. Eine solche gespeicherte 0 % wird als nicht
eingetragen gelesen und verwendet deshalb 1 %. Andere gespeicherte Werte gelten
als eingetragen. Eine wirklich gebührenfreie Struktur braucht daher einmal
ausdrücklich 0 %.

Bei teilweise gelagerten Zwischenprodukten werden nur die gekauften und aus
dem Lager verbrauchten Einheiten mit dem gewichteten Stückpreis der vollständigen
Bedarfsquote bewertet. Die zusätzlich hergestellte Menge verursacht ihre
rekursiven Zutatenkosten und keinen zweiten Zwischenproduktwert. Plan,
Produktionsübersicht und neue Produktionsaufzeichnungen verwenden denselben
Materialkostenbeitrag; bestehende historische Werte werden nicht umgerechnet.

Vor der endgültigen Berechnung löst die Planner-Fläche **BPO/BPC** jeden
tatsächlich gebauten Blueprinttyp gegen persönliche Besitz-Snapshots, den
exakten Produktionsort und eindeutig zurechenbare Main-Hub-Verträge auf. Eine
belegte eigene BPC benötigt ihren vollständigen Erwerbs- oder
Aktivitätsbetrag; eine wiederverwendbare BPO nur die ausdrücklich gewählte
Umlage dieser Produktion. Zurechenbare BPC-Verträge übernehmen ihre
vollständigen Vertragspreise automatisch. Ein manueller BPC-/BPO-Kostenwert in
der Eingabe bleibt gültig und wird nicht zusätzlich automatisch berechnet.
Zuordnungen für später auf **Kaufen** gestellte Zwischenprodukte werden nicht
belastet. Fehlende Kosten lassen Gesamtproduktion und abhängige Gewinne
ausdrücklich unverfügbar.

Die gesamte BPO/BPC-Fläche ist persistent ein- und ausklappbar. Ihre
Bauschritte werden nach Reaktionen, Komponenten und den übrigen belegten
SDE-Kategorien gruppiert; jede Gruppe kann eine Quelle auf alle dafür
geeigneten Schritte anwenden. Nicht geeignete Schritte bleiben unverändert und
werden gezählt, statt still eine unmögliche Quelle zu erhalten. Jede Zeile
besitzt weiterhin ihre eigene Quelle. Für manuelle BPO-Annahmen und externe
BPCs sind ME und TE einzeln einstellbar. Faktische ESI-, Contract- oder
Science-Quellen übernehmen ihre ME-/TE-Werte unverändert. Manuelle Annahmen
erlauben ME 0 bis 10 und TE 0 bis 20. Es gibt keine pauschale Tech-II-Grenze
ME 4: Eine erfundene T2-BPC startet regulär bei ME 2 und kann beispielsweise
mit einem Process Decryptor ME 5 erreichen. Historische T2-BPOs bleiben eine
eigene Provenienz.
Wird dagegen eine konkrete eigene BPO oder eine ausreichend laufstarke Gruppe
eigener BPCs am exakten Produktionsort gewählt, zeigt der Planner die
vorhandenen Qualitätsvarianten und übernimmt deren ME/TE schreibgeschützt in
Produktionsgraph, Materialbedarf, Dauer, Installation und Ergebnisrechnung.
Ein eindeutig zurechenbarer BPC-Vertrag übernimmt seine gemeinsamen ME/TE
ebenfalls automatisch. Reaktionen bleiben ohne ME/TE.

Über den Verkaufsszenarien wählt man im Planner den **Zielmarkt**: Main Hub,
Home Hub, Coalition Hub oder „Nicht gewählt“.

- **Vorschlag:** der Markt des Szenarios mit dem höchsten verfügbaren,
  endgültigen Gewinn unter den neun Karten. Unverfügbare und vorläufige
  Szenarien (ausstehende Transport- oder Vertragsgebühr) werden nie
  vorgeschlagen; bei Gleichstand gilt die Reihenfolge Main, Home, Coalition.
  **Vorschlag übernehmen** setzt ihn, jede manuelle Wahl hat Vorrang.
- **Vorauswahl durch Übergabe:** **Bauen** aus den Hub-Chancen oder der
  Dashboard-Karte setzt den Zielmarkt vor.
- **Hervorhebung:** Die drei Karten des gewählten Hubs sind umrandet.
- **Speicherung:**
  - im Entwurf über den Einstellungsschlüssel
    `planner.target-market.draft.v1`;
  - im Plan-Snapshot als optionales Feld `targetMarket`; neue Berechnungen
    übernehmen die Entwurfswahl;
  - in der Snapshot-Kopie der Produktionsübersicht.

  Eine SwiftData-Schemaänderung ist dafür nicht nötig.
- **Rechnung:** Der Zielmarkt ist eine Entscheidungsmarkierung und ändert
  keine Rechnung.
- **Ältere Pläne und Produktionszeilen** bleiben lesbar und zeigen „Nicht
  gewählt“.
- **Produktionsübersicht:** Die neue, sortierbare Spalte **Ziel** sortiert
  nach dem festen Rang Main, Home, Coalition, Allianzmarkt; „Nicht gewählt“
  steht aufsteigend am Ende. Historische Pläne zeigen den gespeicherten Zielmarkt nur lesend.

Als zehnte Karte steht **Allianzmarkt (manuell)** für Verkäufe an die Allianz,
etwa nach Absprache in Slack.

- **Eingaben:** Stückpreis (Pflicht), abgenommene Menge, Gebühr in Prozent und
  Lieferort (Produktionsort, Main, Home oder Coalition Hub).
  Die Karte rechnet sofort mit den aktuellen Feldwerten; gültige Eingaben
  werden kurz nach dem Tippen automatisch übernommen und gespeichert.
  **Allianzverkauf übernehmen** oder die Eingabetaste übernimmt sofort und
  meldet ungültige Felder.
  - Preis und Menge erhalten beim Tippen Tausenderpunkte der App-Sprache; der
    Preis erlaubt Nachkommastellen mit Dezimalkomma.
  - Die Menge ist mit der produzierten Stückzahl des Endprodukts vorbelegt
    („von N“) und lässt sich mit Stepper oder Pfeil hoch/runter im Feld
    zwischen 1 und der produzierten Menge ändern. Die volle Menge wird als
    „alles“ gespeichert und folgt damit einer neu berechneten Plan-Menge.
- **Rechnung:**
  - Erlös = Preis × verkaufte Menge, höchstens die produzierte Menge.
  - Davon geht die Gebühr ab: ein eingetragener Satz hat Vorrang; sonst gilt
    die bestätigte öffentliche Vertragsgebühr des Handelsorts des Lieferhubs
    (Daten & Einstellungen → Markteinstellungen), die das Feld als Platzhalter
    zeigt. Am Produktionsort oder ohne bestätigten Satz gilt 0 %, ausdrücklich
    als manuelle Annahme mit Hinweis.
  - Kosten = Produktionskosten inklusive Lieferung Main Hub → Home Hub, plus
    der vorhandene Ausgangstransport des Lieferhubs aus dem Plan.
  - Gewinn = Erlös − Gebühr − Kosten; ROI = Gewinn ÷ Kosten. Die Karte zeigt
    diese Rechnung mit Produktionskosten (Material, Blaupausen, Installation,
    Eingangslogistik) und Lieferung aufgeschlüsselt.
  - Nicht abgenommene Einheiten bleiben unverkauft; ihre Produktionskosten
    sind trotzdem enthalten.
- **Wann die Karte unverfügbar bleibt:** ohne Preis, mit mehreren Endprodukten,
  ohne Transport zum Lieferhub oder ohne Produktionskosten. Sie wird dann nie 0.
- **Vorläufig:** Ein Lieferweg mit ausstehendem manuellem Transport macht das
  Ergebnis vorläufig.
- **Zielmarkt:** **Allianzmarkt** ist als weiterer Zielmarkt wählbar und wird
  vorgeschlagen, wenn sein vollständiges Ergebnis den höchsten Gewinn hat; bei
  Gleichstand gewinnen die Marktszenarien.
- **Speicherung:** Die Eingaben stehen im Entwurf
  (`planner.alliance-sale.draft.v1`), das Ergebnis im Plan-Snapshot
  (`allianceSale`) und in dessen Kopie in der Produktionsübersicht. Neue
  Berechnungen übernehmen die Eingaben.
- **Slack-Text:** Ein Angebotstext („WTS Menge× Item @ Preis …“) ist über die
  gemeinsame Kopierrückmeldung kopierbar. Eine Slack-Anbindung gibt es nicht.

Die neun Marktszenarien und ihre Rechnung sind unverändert.

Die Verkaufsstrategien bestehen an Main Hub, Home Hub und Koalitions-Hub jeweils
aus Sofortverkauf in vorhandene Buy Orders, eingestelltem Verkauf über Sell
Orders und öffentlichem Vertragshandel. Einen getrennten Direkthandel zwischen
Spielern gibt es im Planner nicht mehr. Jeder konfigurierte Hub besitzt einen
eigenen ortsgebundenen Marktsnapshot und seinen eigenen
Händler-/Gebührennachweis. Die Ergebnisstufe zeigt diese neun Strategien nur
noch als kompakte Vorschaukarten mit **absolutem Gewinn** und **ROI**. Die
gemeinsamen Produktions- und Main-Hub→Home-Hub-Kosten werden nicht in jeder
Karte wiederholt. Beim Main-Hub-Verkauf enthält die Szenariosumme weiterhin den
Materialtransport vom Main Hub zur Produktion und den Rücktransport des
Fertigprodukts zum Main Hub. Home-Hub-Verkäufe enthalten nur den gemeinsamen
Hintransport; Verkäufe am Koalitions-Hub ergänzen den zutreffenden Transport
vom Produktionsort zum Koalitions-Hub. Diese Unterschiede bleiben vollständig
in Gewinn und ROI eingerechnet, auch wenn ihre Detailzeilen nicht mehr in jeder
Vorschau wiederholt werden. Ausstehender manueller Transport oder eine noch
unbekannte persönliche Vertragsgebühr wird als vorläufig gekennzeichnet und
niemals als 0 ISK behandelt. Verbotene Routen sowie unbekannte Volumen, Tarife
oder Marktdaten lassen die abhängigen Vorschauwerte ausdrücklich
**Nicht verfügbar**.

In der aufgeklappten **EVE shopping list** zeigt der Bereich
**Kaufort-Hinweis · Mineralien und Mondmaterialien** für jede Mineral- und
Mondmaterial-Position:

- den günstigsten konfigurierten Kaufort aus der bereits geladenen Mineralien-
  bzw. Mondmaterial-Kaufanalyse,
- den Stückpreis dort,
- den gewichteten Main-Hub-Stückpreis des Plans,
- die Differenz je Einheit (negativ heißt günstiger).

Weitere Eigenschaften:

- **Analyse-Stand:** Je Analyse steht der Zeitpunkt. „Veraltet“ erscheint, wenn
  die Analyse nicht mehr zur aktuellen Marktkonfiguration passt; ohne Analyse
  steht „Analyse nicht geladen“.
- **Fehlende Werte:** Ein Material ohne frisches Angebot bleibt ausdrücklich
  ohne Kaufort. Ohne vollständige Main-Hub-Markttiefe bleibt die Differenz
  unverfügbar.
- **Bedienung:** Die Tabelle ist sortierbar, unbekannte Werte stehen aufsteigend
  am Ende. Material- und Ortsnamen sind kopierbar.
- **Multibuy:** Je empfohlenem Kaufort gibt es einen Export
  **Multibuy kopieren · Ort** mit demselben Zeilenformat wie der
  Main-Hub-Export.
- **Rechnung:** Der Hinweis ist nur Entscheidungshilfe und startet keinen
  ESI-Abruf. Plankosten, Einkaufsliste und Main-Hub-Multibuy bleiben
  unverändert Main-Hub-basiert.

Für jede transportierte Einheit gilt ausschließlich das verpackte Volumen.
Quelle ist zuerst das tatsächlich importierte `packagedVolume` des aktiven SDE
(Eigentümerentscheidung vom 23.10.2026; im Build 3632936 vorhanden für 26.347
von 27.309 veröffentlichten Typen). Nur für Typen ohne SDE-Wert lädt der
Planner das öffentliche ESI-Typfeld `packaged_volume`, mit begrenzter
Parallelität. Das entpackte `volume` dient niemals als Ersatz. Der Planner
ermittelt die begrenzte Menge aller für den Produktionsgraph benötigten Typen
und friert die Werte als eigenen Quellensnapshot ein (`CCP SDE`,
`ESI universe types` oder beides). Fehlt ein verpacktes Volumen in beiden
Quellen, bleibt die betroffene Logistik unverfügbar. Für die am 13. August
2026 live geprüfte Hulk liefert CCP
3.750 m³ je verpacktem Schiff: zehn Hulks ergeben somit 37.500 m³ und passen in
einen 350.000-m³-Vertrag. Das entpackte Volumen von 150.000 m³ je Hulk wird
nicht mehr verwendet.

Jeder neu berechnete Kuriervertrag speichert außerdem seine tatsächlich
zugeteilten Frachtpositionen mit Gegenstand, Menge, Volumen und anteiliger
Sicherheitsleistung. Die aufgeklappte Logistikkarte zeigt diese Positionen;
aufgelöste Gegenstandsnamen sind über die gemeinsame EVE-Kopierfunktion direkt
kopierbar. Damit lässt sich der Main-Hub-Einkauf mit der Lieferung zum Home Hub
abgleichen und es ist sichtbar, ob direkte Mineralien oder komprimiertes Erz
transportiert werden. Ältere gespeicherte Pläne ohne diese Positionen bleiben
lesbar; fehlender historischer Inhalt wird nicht nachträglich erfunden.

Für die Vertragsanzahl wird zuerst der durch komprimiertes Erz gedeckte
Mineralbedarf aus den direkten Mineralpositionen entfernt. Erst danach werden
das Erz und alle verbleibenden Main-Hub-Einkäufe zu einer gemeinsamen Fracht
für die konfigurierte Route **Main Hub → Home Hub** zusammengeführt und nach
dem Vertragsvolumen geteilt. Die Refining-Struktur ist der betriebliche Ort der
Aufbereitung, erzeugt aber keinen zusätzlichen künstlichen Langstreckenvertrag;
eine lokale Verteilung innerhalb des Home-Hub-Systems gehört nicht zu dieser
konfigurierten Kurierstrecke.

Die gemeinsame Vertrags- und Positionsaufschlüsselung steht einmalig in der
Kostenkarte unter **Lieferung · Main Hub → Home Hub** bereit. Ihre Anzahl stammt
ausschließlich aus den tatsächlich nach der Erzentscheidung erzeugten
Vertragsabschnitten; dadurch kann dieselbe Route nicht mehr mit widersprüchlichen
Anzahlen in mehreren Szenariokarten erscheinen. Ist der Erzvergleich aktiviert,
aber noch nicht ausführbar, zeigt der aktuelle Plan den konkreten ersten
Sperrgrund und den Berechnungszeitpunkt. Nach einer Einstellungsänderung ist
**Berechnen** erneut auszuführen. Die eigenständige Logistikseite lädt bei
mehreren Production Bases ausschließlich die gespeicherte Konfiguration der
aktuell aktiven Basis; eine nur zeitlich jüngere fremde Basis darf deren Werte
nicht überschreiben.

Zeilen der Produktionshistorie behalten dagegen die beim damaligen Speichern
ermittelten Logistik- und Refiningwerte. Aktuelle Tarife, Anlagen oder
Erzentscheidungen schreiben diese historischen Nachweise nicht nachträglich um.

Für die Route **Home Hub → Coalition Hub** kann unter **Daten & Einstellungen →
Logistik** statt des Kurierpreises eine Sprungtreibstoff-Rechnung aktiviert
werden. Normale
Produkte werden als Fracht eines auswählbaren Jump Freighters transportiert;
wählbar sind Rhea, Nomad, Anshar und Ark. Ein selbst sprungfähiges, im Plan
gebautes Capital wird dagegen vor der Frachtaufteilung entfernt und erhält je
fertiggestellter Hülle einen eigenen Sprungplan. Das gilt insbesondere auch für
einen gebauten Jump Freighter und für die Rorqual. Ein normaler Freighter ist
nicht selbst sprungfähig und wird deshalb nicht durch diese Regel zu einem
Selbstspringer erklärt.

Für die Frachtstrecke priorisiert die automatische Pilotenwahl zuerst die
Reichweite aus Jump Drive Calibration und danach den günstigsten
Kraftstofffaktor aus Jump Fuel Conservation und Jump Freighters. Für andere
Capital-Selbstsprünge werden Jump Drive Calibration und Jump Fuel Conservation
verwendet; die dritte DOTLAN-Skillstelle bleibt 0, weil Jump Freighters deren
Treibstoff nicht reduziert. Ein **gebauter Jump Freighter**, der selbst zum
Koalitions-Hub springt, verwendet dagegen wie der Frachtflug alle drei Skills
und wird weiterhin nicht als eigene Fracht behandelt. Veraltete, gesperrte oder fehlende Skilldaten gelten
nicht als geeignet. Die konkrete Berechtigung, jede einzelne Capital-Hülle zu
fliegen, ist noch kein automatisch bestätigter Nachweis und bleibt vor dem
tatsächlichen Transport mit EVE abzugleichen.

Die App löst die Sonnensysteme der beiden Hubs über CCP ESI auf. Für
**Jump Freighter**, **Carrier**, **Dreadnought**, **Force Auxiliary**,
**Supercarrier**, **Titan** und **Capital Industrial** kann einzeln entweder
die automatische DOTLAN-Route oder ein festes Sprungroutenprofil gewählt
werden. Ein Profil enthält geordnete Zwischen-Sonnensysteme und optional je
Zwischenpunkt einen manuell gepflegten Cyno-Struktur- oder Einsatzortnamen.
Alternativ darf es die vollständige Route einschließlich Home Hub und
Koalitions-Hub enthalten. Stimmen der erste beziehungsweise letzte Profilpunkt
mit den konfigurierten Endpunkten überein, werden sie normalisiert und nicht als
künstliche Nullsprünge doppelt angefügt.
Mehrere Klassen dürfen bewusst dasselbe Profil verwenden. Die Auswahl bleibt
trotzdem je Klasse getrennt, sodass beispielsweise Carrier und Force Auxiliary
eine Route teilen, während Titan oder Jump Freighter ein anderes Profil nutzen.

Bei einer festen Route wählt DOTLAN keinen anderen Weg: Die App prüft jeden
aufeinanderfolgenden Abschnitt vom Home Hub über die festgelegten
Zwischensysteme zum Coalition Hub einzeln. Jeder Abschnitt muss für das
tatsächliche Schiff und den ausgewählten Piloten als genau ein direkter Sprung
zurückkommen. Reichweite und Treibstoff werden deshalb auch bei gemeinsam
genutzten Profilen je Hülle neu geprüft. Ein unvollständiges Profil, ein nicht
direkter Abschnitt oder eine Reichweitenüberschreitung blockiert diese
Berechnung ausdrücklich; es gibt keinen stillen Rückfall auf die automatische
Route, 0 ISK, Fracht oder Kurierkosten. Nur eine ausdrücklich auf
**Automatische DOTLAN-Route** gestellte Klasse verwendet die von DOTLAN
ermittelte Gesamtstrecke. Der optionale Cyno-Ortsname ist Betriebsdokumentation
und verändert weder Reichweite noch Treibstoff.

Der gespeicherte Nachweis enthält die gewählte automatische oder feste
Routenquelle, den Profilnamen samt Zwischenpunkten, sämtliche geprüften
Abschnitte und Quelllinks, Lichtjahre und die Isotopenmenge pro Flug oder pro
selbstspringender Hülle. Die
nutzbare Frachterkapazität ist eine sichtbare Planannahme mit 350.000 m³ als
änderbarem Ausgangswert. Daraus werden nur für normale Fracht die benötigten
Einwegflüge und deren konkrete Positionen berechnet. Capitals verbrauchen diese
Kapazität nicht; ihre eigene DOTLAN-Menge wird mit der gebauten Hüllenzahl
multipliziert. Ein Rückflug ist nicht enthalten.

Als Grundpreis dient wie vorgegeben das arithmetische Mittel der jeweils
niedrigsten aktuellen Main-Hub-Verkaufsorder für Helium, Oxygen, Nitrogen und
Hydrogen Isotopes. Die Strategiekarte zeigt alle vier Preise, den Mittelwert,
den tatsächlich von jedem Schiff verwendeten Isotopentyp, Menge je Flug oder
Hülle, Gesamtmenge und Gesamtkosten. Fehlt eine Route, ein geeigneter Pilot, ein
verpacktes Volumen oder auch nur einer der vier Preise, bleibt Route 2 und damit
die vollständige Coalition-Rentabilität ausdrücklich unverfügbar. Ein
DOTLAN-Formatwechsel darf weder 0 ISK noch den normalen Kurierpreis als
vermeintliches Ergebnis erzeugen. Ist die Sprunglogistik deaktiviert, blockiert
ein selbstspringendes Capital die Coalition-Berechnung ausdrücklich, statt
unbemerkt in einen gewöhnlichen Kuriervertrag zu fallen.

Jede Strategiekarte zeigt ihre Abzüge genau einmal: Ein Sofortverkauf verwendet
vollständig gedeckte Kauforders, zieht die orts- und händlerbezogene
Verkaufssteuer ab und hat 0 ISK Brokergebühr. Ein eingestellter Verkauf verwendet
den niedrigsten aktuellen Verkaufsorderpreis als Referenz und zieht
Verkaufssteuer plus Brokergebühr ab. Der Vertragshandel verwendet
nicht den Marktpreis, sondern den niedrigsten Stückpreis eines passenden
öffentlichen Item-Exchange-Vertrags. Passend bedeutet: genau der angebotene
Produkttyp, genau eine Angebotsposition, keine angeforderte Position und ein
positiver zuordenbarer Vertragspreis. Bündel und Tauschforderungen werden
ausgeschlossen. Bei vollständig frischem, nicht abgeschnittenem
Public-Contracts-Index ist dies der niedrigste belegte Stückpreis des
importierten Universums. Während ein Index aktualisiert wird oder noch
unvollständig ist, darf ein bereits beobachtetes passendes Angebot als
ausdrücklich **vorläufige Vertragsschätzung** verwendet werden. Die Karte
behauptet dann kein vollständiges universumsweites Minimum. Wurde für einen
Produkttyp noch kein passendes Angebot beobachtet, bleiben Vertragserlös und
abhängige Werte unverfügbar; ein fehlendes Angebot wird nie zu 0 ISK. Ein
optionales `allowedRegionIDs`-Feld hält die Projektion bereits für eine spätere
Auswahl erlaubter Preisregionen offen; die Oberfläche verwendet derzeit bewusst
das gesamte Universum. Der **Vertragshandel** modelliert einen
tatsächlich öffentlich eingestellten Vertrag. Er setzt die beiden Marktgebühren
auf 0 ISK und zieht stattdessen den im Marktprofil des Hubs bestätigten,
zusammengefassten nicht erstattbaren Vertragsgebührensatz ab. Der Satz kann
weiterhin manuell eingetragen werden. Zusätzlich kann **Tradergebühren aus ESI
aktualisieren** für den gewählten Händler dessen persönliche Verträge und
Wallet-Journal der jüngsten ESI-Historie (derzeit ungefähr 30 Tage) gemeinsam
auswerten. Die Zuordnung ist nur vollständig, wenn ein abgeschlossener eigener
öffentlicher Item-Exchange-Vertrag, seine positive Vertragssumme, der exakte
Handelsort und die Journalbuchungen über dieselbe `contract_id` zusammenpassen.
Als nicht erstattbare Gebühr zählt ausschließlich
`contract_brokers_fee + contract_sales_tax`; `contract_deposit` und
`contract_deposit_refund` werden getrennt nachgewiesen und nicht abgezogen. Eine
zusammengefasste `contract_deposit_sales_tax`-Buchung bleibt mangels eindeutiger
Trennung unvollständig. Dafür müssen die SSO-Scopes
`esi-contracts.read_character_contracts.v1` und
`esi-wallet.read_character_wallet.v1` vorliegen.

Eine vollständige Beobachtung wird mit Vertrags-ID, Händler, Ort, Zeitpunkt,
Vertragspreis und beiden Gebührenbestandteilen im Marktprofil hinterlegt, aber
nicht automatisch als Planungssatz aktiviert. Erst **Beobachteten Satz für die
Planung verwenden** bestätigt den daraus berechneten Quotienten
`(Brokergebühr + Vertragsverkaufssteuer) / Vertragspreis`. Ein anderer Händler
oder Handelsort verwirft den ortsgebundenen Nachweis und den zuvor bestätigten
Satz. Fehlende Scopes, kein passender Vertrag, unvollständige Buchungen oder ein
ESI-Fehler ersetzen weder einen gespeicherten manuellen Wert noch einen
bestätigten Satz und werden niemals als 0 % interpretiert. Die Beobachtung ist
ein historischer Nachweis, kein Angebot für einen hypothetischen neuen Vertrag.
Grundlage sind der offizielle CCP-Ablauf für
[Tauschverträge](https://support.eveonline.com/hc/de/articles/206758389-Tauschvertrag)
und die im offiziellen [ESI API Explorer](https://developers.eveonline.com/api-explorer)
veröffentlichten Vertrags- und Wallet-Journal-Felder.

Fehlt ein bestätigter Satz,
weist die Karte Erlös, Gewinn, Marge und ROI als vorläufige Werte **vor
öffentlicher Vertragsgebühr** aus und fordert zur Hinterlegung des von EVE
angezeigten persönlichen Satzes auf. ESI liefert den Preis öffentlicher
Verträge, aber kein persönliches Angebot für die Gebühr eines neu erstellten
Vertrags. Eine rückzahlbare Vertragseinlage wird nicht als Kosten behandelt.
CCP veröffentlicht in den aktuell geprüften Supportartikeln keine hinreichend
vollständige aktuelle Formel, deshalb wird keine historische Prozentregel
erfunden. Route 1 und eine gegebenenfalls zum Home- oder Koalitions-Hub nötige
Route 2 bleiben in beiden Fällen Bestandteil der Szenariokosten.

Beim Bruttowert nennt jede Karte die Preisquelle ausdrücklich:
**Bruttoerlös · Markt** oder **Bruttoerlös · Öffentliche Verträge**.
Fehlt in einem gespeicherten Altplan noch die ausdrückliche ausgehende
Routenbewertung, fordert die Karte eine Neuberechnung an; Transport wird nicht
als kostenlos ergänzt und Szenariogesamtkosten sowie Gewinn bleiben unbekannt.

Der Hauptplaner beginnt seine Ergebnisdarstellung mit einer kompakten
**Finanzübersicht**. Materialbeschaffung, Lagerverbrauch, BPC/BPO,
Installation, Lieferung vom Main Hub zum Home Hub, Produktionszwischensumme
und Produktionskosten inklusive Lieferung stehen als eigenständige adaptive
Karten nebeneinander und bei schmalerem Platz untereinander. Jede Karte ist
vollständig aufklappbar. Ihre Detailansicht zeigt die tatsächlich verwendeten
Teilbeträge, Gleichungen, BPC-/BPO-Zuordnungen beziehungsweise die vollständige
Logistikroute. Lagerverbrauch und Refining-Gebühr sind ausdrücklich als bereits
in der Materialbeschaffung enthalten markiert und werden nicht erneut addiert.
Unbekannte Teilwerte bleiben unbekannt.

Die neun kompakten Verkaufsszenarien zeigen zunächst nur absoluten Gewinn und
ROI. Ein Klick auf die jeweilige Karte öffnet wieder die vollständige
Szenariomaske mit kopierbarem Verkaufsort, Ausgangsroute, Szenariokosten,
Bruttoerlös, Steuer, Broker- oder Vertragsgebühr, Nettoerlös, Gewinn, Marge,
ROI, Rechengleichungen und den verwendeten Markt- oder Vertragsquotes. Jeder
Main-, Home- und Koalitions-Hub-Modus behält seinen eigenen Offenlegungszustand;
das Öffnen einer Karte verändert keine Kalkulation.
Im geschlossenen Zustand ist die gesamte verfügbare Kartenhöhe einschließlich
der zuvor leeren Restfläche anklickbar. Auch die übrigen aufklappbaren Bereiche
verwenden die gemeinsame vollbreite Offenlegungssteuerung; ein Klick auf eine
sichtbare EVE-Namens-Kopiersteuerung bleibt davon getrennt.
Auch **Letzte fünf Produktionen** ist standardmäßig geschlossen und lässt sich
über dieselbe vollständige Offenlegungszeile öffnen. Historische Werte werden
dabei weiterhin nur gelesen und nicht mit aktuellen Logistik- oder
Refining-Einstellungen neu berechnet.

Für Schiffe der SDE-Produktionsklasse **Capital** mit den Gruppen Carrier,
Dreadnought, Force Auxiliary, Supercarrier, Titan oder Capital Industrial wird
eine Rückführung und Marktverkaufsstrategie am Highsec-Main-Hub als **nicht
zulässig** behandelt. Sie erhält weder einen fiktiven Transportpreis noch eine
Gewinnberechnung. Home- und Koalitions-Hub bleiben nutzbar, wenn sie als
erreichbare Verkaufsorte konfiguriert sind. Freighter und Jump Freighter bleiben
als reguläre Highsec-Ausnahmen erlaubt. Diese Regel folgt CCPs dokumentierter
mechanischer Highsec-Beschränkung für die meisten Capitals; ein nicht erreichbarer
Hub wird nicht durch einen Vertrag künstlich erreichbar gemacht.

Für NPC-Stationen in Exordium (ESI-Region `10001004`) enthält die Gebühr des
eingestellten Verkaufs zusätzlich den CCP-Aufschlag von 5 % für nicht sofort
nicht. Sofortverkauf und Vertragshandel erhalten diesen Aufschlag
nicht. Maßgeblich ist die ortsgebundene Gebührenregel
`ccp-market-fees-2026-08-13`; fehlende Händler-, Standing- oder Ortsdaten
bleiben unverfügbar und werden nicht als 0 angenommen.

Für eine Berechnung werden gültige Kauf- und Verkaufsorders je Typ einmal
gefiltert und preislich sortiert; Kauf-, Lager-, Ersatzwert-, Make-or-Buy-,
Logistik- und Verkaufsszenarien verwenden danach dieselbe unveränderliche
Orderbuchprojektion. Systemkostenindizes werden ebenfalls einmal nach System
und Aktivität indiziert. Diese Vorbereitung verändert weder Markttiefe,
Rundung, Gebühren noch die Entscheidungsergebnisse. Ein abgelöster
Planner-Lauf wird abgebrochen und darf einen neueren Plan nicht überschreiben.
Main-, abweichender Home- und Koalitions-Hub werden parallel geladen; identische
Hubs teilen sich denselben Snapshot. Die universumsweite öffentliche
Vertragsreferenz wird einmal geladen und für die drei Vertragskarten gemeinsam
verwendet. JSON-Dekodierung bestehender Reservierungen und die
Kodierung des fertigen Plans laufen außerhalb des Main-Actors.
Beim Öffnen lädt der Planner nur aktive Pläne, den primären Entwurf, höchstens
die fünf neuesten Produktionszeilen und genau einen benötigten
Legacy-Fallback. Ein aus der Produktionsübersicht angeforderter historischer
Plan wird direkt über seine eindeutige ID gelesen; die vollständige Historie
wird dafür nicht in den Planner-Kontext geladen. Die nächste Produktionsnummer
wird aus genau dem höchsten gespeicherten Wert ermittelt.

Die Produktionsübersicht lädt die unveränderliche Historie in stabil nach
Produktionsnummer geordneten Seiten zu höchstens 100 Zeilen. Sortieren und
Bearbeiten gelten für die sichtbare Seite. Anzahl, Units, prognostizierter und
realer Gewinn werden separat außerhalb des UI-Kontexts über die vollständige
Historie gebildet; ein unbekannter Bestandteil bleibt deshalb auch in der
Gesamtsumme unbekannt und wird nicht zu null. Mehrere Zeilen desselben
unveränderlichen Plans teilen sich die dekodierte Snapshot- und
Request-Projektion. Beim Seitenwechsel wird dieser Cache auf die aktuell
benötigten Pläne begrenzt. Gespeicherte Snapshotdaten und Provenienz bleiben
unverändert; die Optimierung benötigt weder eine Schemaänderung noch eine
Datenumschreibung.

Neue Plansnapshots bewahren Verkaufssteuersatz, Brokergebührensatz und die
Anwendbarkeit der Brokergebühr auch dann getrennt, wenn keine verkaufbare
Main-Hub-Marktquote existiert. Für ein ausdrücklich vom Highsec-Main-Hub
ausgeschlossenes Capital bleibt die Broker-Spalte `—` als **nicht anwendbar**;
sie ist dabei kein angenommener unbekannter Nullwert. Ein bekannter
Verkaufssteuersatz wird weiterhin auf den manuell eingetragenen
Verkaufspreis angewendet. `Min. +10 %` ist in diesem Fall
`Produktionskosten je Unit × 1,10 ÷ (1 − Verkaufssteuersatz)`; prognostizierter
Gewinn und Marge verwenden `Bruttoerlös − Verkaufssteuer − Produktionskosten`.
Der reale Gewinn verwendet zusätzlich nur die tatsächlich verkaufte Menge.
Ohne Verkaufspreis bleiben Steuerbetrag und Verkaufsgewinn weiterhin
unbekannt. Bei einem grundsätzlich möglichen Market-Order-Verkauf blockiert
ein lediglich unbekannter Brokergebührensatz die Nettowerte weiterhin und wird
nicht zu null. Historische Snapshots ohne die neuen Satzfelder dürfen einen
Steuersatz zuerst aus ihren eigenen belegten Home-/Coalition-Szenarien ableiten.

Hat eine Produktion ihren Verkaufssteuer- oder Brokergebührensatz nicht
gespeichert (z. B. weil der Main Hub bei der Aufzeichnung noch keinen
Händlercharakter hatte), verwendet die Produktionsübersicht für genau diesen
fehlenden Satz den aktuell für den Main Hub wirksamen Satz. Gespeicherte Sätze
haben immer Vorrang, eine nicht anwendbare Brokergebühr bleibt nicht anwendbar.
Ergänzte Beträge erscheinen kursiv und nennen ihre Herkunft im Tooltip. Die
Ergänzung wird beim Anzeigen berechnet, nicht in den Snapshot geschrieben;
Zeilen, Seitensortierung und Gesamtsummen folgen einer Änderung der
Main-Hub-Sätze. Ist auch der aktuelle Satz unbekannt, bleibt der Wert
unverfügbar.

Reaktionen verwenden veröffentlichte SDE-Formeln; fehlende Markt-, Volumen-,
Kollateral- oder Tarifdaten machen den betroffenen Vergleich unverfügbar.

Der ausführliche Produktionsvertrag steht in
[`Documentation/PRODUCTION_BASIS.md`](Documentation/PRODUCTION_BASIS.md).

## Lokale Daten, Sicherheit und Wiederherstellung

- Refresh Tokens liegen ausschließlich im macOS-Schlüsselbund. Ein Client
  Secret wird nicht verwendet.
- Je Charakter läuft höchstens eine Token-Erneuerung gleichzeitig. Weitere
  Abrufe warten auf deren Ergebnis, statt den Token ein zweites Mal zu
  erneuern. So kann ein paralleler Abgleich keine scheinbar fehlende
  Autorisierung mehr melden.
  - Ein Widerruf oder eine neue Anmeldung während einer laufenden
    Erneuerung wird nicht mehr von deren Ergebnis überschrieben.
- Die native PKCE-Anmeldung verwendet durchgängig den festen Loopback-Callback
  `http://localhost:52722/callback`: Anzeige, Autorisierungsanfrage,
  Rückrufserver und Rückrufprüfung teilen dieselbe Konstante. Die URL muss im
  EVE-Developer-Portal einschließlich Port und Pfad exakt ebenso registriert
  sein. Ein teilweise aufgelöster Asset-Snapshot ist kein Beleg für einen
  falschen Callback-Port; eine abgelaufene oder falsche Registrierung wird als
  eigener SSO-Fehler behandelt.
- Der ESI-/SDE-User-Agent verwendet die ausdrücklich öffentliche
  Projekt-Kontaktadresse `projekt-st@gmx.de`. Sie ist keine Anmeldeinformation,
  wird im Build als Fallback mitgeführt und kann für lokale Entwicklung über
  `EVE_NEXUS_CCP_USER_AGENT_CONTACT` überschrieben werden.
- Der dauerhafte ESI-Antwortcache (`caches/esi-responses.sqlite`) enthält
  unverschlüsselte ESI-Rohantworten, auch private Charakterdaten wie Assets
  oder Wallet. Er enthält keine Tokens und keine Anmeldedaten. Als abgeleitete
  Daten gehört der Ordner `caches` nicht zur Datensicherung (`.nexusbackup`).
- Die primäre SwiftData-Datenbank besitzt einen stabilen Pfad unter der
  Anwendungskennung. Schemaänderungen werden versioniert migriert.
- Vor einer Migration wird eine Sicherheitskopie angelegt. Ein Legacy-Store
  wird nur übernommen, wenn noch kein kanonischer Store existiert. Ein geprüfter,
  konsistenter SQLite-Snapshot einschließlich festgeschriebener WAL-Daten wird
  zuerst vollständig vorbereitet und erst dann atomar veröffentlicht. Der alte
  Stand wird nicht gelöscht; vorhandene Zieldaten oder Begleitdateien werden
  nicht automatisch überschrieben.
- Für bereits unvollständig übernommene Daten gibt es eine ausdrücklich gewählte
  vollständige Wiederherstellung im App-Menü und auf dem Fehlerbildschirm. Nach
  Beenden und erneutem Öffnen werden beide Datenstände gesichert und die alte
  Arbeitskopie mit der aktuellen Migrationskette geprüft. Die bestätigte alte
  Datenbank ersetzt ausschließlich den SwiftData-Bestand. Neuere Datensätze
  bleiben in der Sicherung und werden nicht zusammengeführt. Eine exklusive
  Datensperre und ein Vorgangsprotokoll schützen Austausch und Rücknahme; ein
  mehrdeutiger Zustand verhindert den normalen Start. Die genaue Grenze und
  die Sicherungsregeln stehen im [Wiederherstellungsvertrag](Documentation/REVIEW_FIXES_2026-10-02.md).
- Ein gültiger SQLite-Integritätstest allein belegt keinen EVE-Datenbestand.
  Vor einer Wiederherstellung müssen auch die Modellzugehörigkeit und die
  enthaltenen EVE-Entitäten geprüft werden. Der bisherige Legacy-Import prüft
  diese Zugehörigkeit vor dem Kopieren der globalen `default.store` nicht.
- Für einen ausdrücklich freigegebenen Neustart wird ein neuer EVE-Store zuerst
  in einem isolierten Application-Support-Verzeichnis erzeugt und geprüft.
  Erst danach wird er am kanonischen App-Pfad aktiviert; der vorherige
  App-Datenordner bleibt unter einem separaten Sicherungsnamen erhalten.
  Die globale `default.store` wird dabei weder übernommen noch verändert.
  Ein solcher Neustart stellt keine früheren lokalen Produktionspläne wieder her.
- SDE-Kandidaten werden validiert und erst nach einer bestätigten Vorschau
  atomar aktiviert. Ein älterer Metadatenstand darf kein Downgrade auslösen.
- Der offizielle JSONL-Datensatz `typeDogma` lässt `dogmaEffects` bei Typen
  ohne Effekte vollständig aus. Der Mapper behandelt ausschließlich dieses
  fehlende Feld als leere Effektmenge. Ein vorhandener falscher Typ, eine
  ungültige Effekt-ID oder eine Dublette bleibt ein Importfehler. Fachlich
  vorgeschriebene Reaktionsskill- und Rig-Effekte werden anschließend weiterhin
  ausdrücklich geprüft und dürfen nicht fehlen.
- Der SDE-Import übernimmt zusätzlich den offiziellen Datensatz
  `marketGroups.jsonl`. Das ist der Marktgruppen-Baum mit englischem Namen,
  optionaler Elterngruppe und `hasTypes`.
  - Katalogadapter 5 speichert ihn in der Tabelle `market_groups`.
  - Die Kernabfrage `marketGroups()` liefert den Baum.
  - `tradeItems(inMarketGroupSubtree:)` liefert die veröffentlichten Items einer
    Gruppe und aller Untergruppen mit gepacktem Volumen. Ein fehlendes
    Packvolumen bleibt unbekannt; das zusammengebaute Volumen wird nicht
    ersatzweise verwendet.
  - Ein mit Adapter 1–4 aktivierter Katalog bleibt für alle übrigen Bereiche
    voll nutzbar. Für Marktgruppen meldet er ausdrücklich den Zustand „SDE-Neuimport
    nötig“ (`requiresSDEReimport`), statt leere Daten als Ergebnis
    auszugeben. Abhilfe ist der **Neuimport des aktuellen Katalogs**.
  - Durch den zusätzlichen Datensatz ändert sich der Inhalts-Hash eines Builds.
    Ein Neuimport erzeugt daher eine neue Katalogdatei.
  - Der Bereich **Handel** nutzt die Marktgruppen für seine Kacheln
    ([Handel-Plan](Documentation/HANDEL_PLAN.md)).
- Katalogadapter 6 legt beim Import zusätzlich ab:
  - die Dogma-Attribute aller Strukturen und Strukturmodule (Kategorien 65
    und 66) in der Tabelle `type_dogma`. Strukturen, Service-Module und Rigs
    der Industrieprofile werden beim Start daraus gelesen statt aus der rund
    28 MB großen Paketdatei `typeDogma.jsonl`;
  - Indizes für die Produkt- und Skillzeilen je Blueprint und Aktivität.
  - Ein mit Adapter 1–5 aktivierter Katalog funktioniert unverändert weiter
    und liest die Dogma-Werte dann wie bisher aus der Paketdatei. Die
    Beschleunigung greift erst nach einem **Neuimport des aktuellen Katalogs**
    und anschließendem Neustart der App. Der Inhalts-Hash des Builds ändert
    sich dadurch nicht; es entsteht eine neue Datei `catalog-v6`.
- Vollständige Fertigungs- und Reaktionsdefinitionen (Main-Hub-Chancen,
  Reaktionsanalyse) werden mit drei Katalogabfragen statt einer Abfragefolge je
  Produkt geladen und für den aktiven Katalog während der Laufzeit
  wiederverwendet. Die Auswahl des Blueprints je Produkt ist dieselbe wie bei
  der Einzelabfrage.
- Der aktive SDE-Zeiger akzeptiert den historischen Legacy-Dateinamen und
  kanonische, bereits aktivierte `catalog-vN`-Dateien bis einschließlich der
  aktuellen Adapterversion 6. Dadurch bleibt ein gültiger Katalog einer
  älteren Adapterversion als installierter Build erkennbar und kann sicher neu
  importiert werden. Neue Aktivierungen schreiben ausschließlich Adapter 6;
  fremde Pfade, nichtkanonische Versionsangaben und zukünftige
  Adapterversionen werden abgewiesen. Ein ungültiger Zeiger wird in der
  Oberfläche als verständlicher Wiederherstellungszustand statt als interner
  Fehlername angezeigt, und vorhandene Katalogdateien werden nicht gelöscht.
- Zeigt die Vorschau denselben offiziellen und aktiven Build, bietet die App
  einen getrennten, ausdrücklich zu bestätigenden **Neuimport des aktuellen
  Katalogs** an. Dieser Weg lädt denselben offiziellen JSONL-Build erneut und
  baut ihn mit dem aktuellen Katalogadapter auf. Der bisherige Katalog bleibt
  während Download, isolierter Bereitstellung und Prüfung aktiv; vor der
  atomaren Umschaltung wird eine Sicherheitssicherung erstellt. Versionierte
  Adapterdateien besitzen jeweils einen eigenen Dateinamen, damit ein alter
  Katalog desselben Builds nicht irrtümlich wiederverwendet wird. Der
  Legacy-Dateiname und kanonische ältere Adapterdateien bleiben als gültige,
  unveränderte Rückfallbasis lesbar.
  Die vor der Promotion gesicherte exakte Zeigeridentität wird im laufenden
  Installationsvorgang außerdem für die Fehlerrücksetzung gehalten; dadurch
  kann auch bei identischer Buildnummer gezielt die vorherige Datei reaktiviert
  werden.
- **Data & Settings → SDE** weist dauerhaft sowie in den Bestätigungsdialogen
  für Update und Neuimport darauf hin, dass die App nach erfolgreicher
  Aktivierung vollständig beendet und neu geöffnet werden muss. Erst danach
  sollen SDE-abhängige Bereiche verwendet und die Main-Hub-Analyse erneut
  ausgeführt werden. Der Hinweis beschreibt den derzeit notwendigen
  Betriebsablauf; er behauptet keine automatische Laufzeitumschaltung.
- Öffentliche Contract-Imports starten bzw. laufen nach jedem Programmstart
  automatisch weiter. Ein manueller Stopp pausiert sie bis zum nächsten Start.
  Sie zeigen Fortschritt und Teilstatus,
  können sicher gestoppt werden und bewahren einen letzten erfolgreichen Stand.
  Eine kompakte Steuerkarte bleibt dauerhaft in der Navigationsseitenleiste
  sichtbar. Dort lässt sich der Erstimport starten oder fortsetzen, ohne die
  Vertragsliste zu öffnen; laufende Arbeit kann dort sicher pausiert und eine
  fehlgeschlagene lokale Vorbereitung erneut angestoßen werden. Vorbereitung,
  Import, sicheres Anhalten, geplanter Lauf, unvollständiger und aktueller Stand
  bleiben getrennte sichtbare Zustände. Der Detailbereich kann jederzeit
  verlassen werden; der Import gehört dem gemeinsamen Runtime-State und läuft
  nicht als Lebenszyklusaufgabe der Vertragsansicht.
- **Vertragsregionen** (Daten & Einstellungen → Markteinstellungen) legen den
  Abrufumfang fest: **Gesamtes Universum** (Standard, bisheriges Verhalten)
  oder **Ausgewählte Regionen**. Die Liste stammt aus der ESI-Regionsliste des
  lokalen Index; ist noch keine Region bekannt, lädt die App sie einmalig.
  Hinter dem Namen stehen in Klammern Hinweise wie Main Hub, Home Hub,
  Koalitions-Hub, Vergleichsmarkt, Produktionsort (Region eines konfigurierten
  Aktivitätssystems) oder Trade-Hub Jita/Amarr/Dodixie/Rens/Hek. Kennt ein
  Hub-Ort (etwa eine Spielerstruktur als Coalition Hub) nur sein Sonnensystem,
  ermittelt die App die Region über die zwischengespeicherte ESI-Systemabfrage;
  schlägt sie fehl, bleibt die Region ohne Hinweis. Regionen mit
  Hinweis stehen unter **Empfohlene Regionen** oben (Reihenfolge: Main, Home,
  Koalition, Vergleichsmarkt, Produktionsort, Trade-Hub, dann Name), alle
  übrigen alphabetisch darunter. Beim Wechsel auf die Auswahl sind Hub- und
  Produktionsregionen vorausgewählt; eine leere Auswahl lässt sich nicht
  übernehmen. Die Auswahl wird erst mit **Regionsauswahl übernehmen** im
  lokalen Vertragsindex gespeichert (unabhängig vom Speichern der
  Markteinstellungen).
- Der gewählte Umfang gilt für Regionsabruf, Detailabruf, Fortschritt,
  Vollständigkeit, Suche, Kategorien/Gruppen und alle Angebotsabfragen. Damit
  vergleichen Main-, Home- und Coalition-Hub-Chancen, der Vertragsverkauf im
  Planner und die Bauplanangebote nur Verträge der gewählten Regionen. Verträge
  abgewählter Regionen bleiben gespeichert, werden aber weder aktualisiert
  noch angezeigt; nach erneuter Auswahl werden sie mit dem nächsten Abruf
  aufgefrischt. „Vollständig“ bezieht sich auf die gewählten Regionen. Ein
  bereits laufender Abruf endet mit seiner bisherigen Regionsliste; die
  automatische Planung wird nach dem Übernehmen sofort neu berechnet.
- Eine Schemaerweiterung darf keinen vollständigen Bestand bereits fertiger
  Contract-Details ungefragt erneut über ESI abrufen. Die zurückgenommene
  Blueprint-Nachpflege v1 repariert beim nächsten Store-Öffnen ausschließlich
  ihre unberührten Warteschlangeneinträge; unbekannte Runs/ME/TE bleiben
  unbekannt, statt durch einen CPU- und netzwerkintensiven Massenabruf ersetzt
  zu werden.
- Die lokale Contract-Suche hält neben den vollständigen Contract-Items einen
  kleinen abgeleiteten Typindex. Bestehende Datenbanken bauen ihn beim ersten
  Öffnen transaktional aus konsistenten gespeicherten Typzeilen auf. Öffnen,
  Schema-Prüfung und Backfill laufen mit Utility-Priorität außerhalb des
  Main Actors. Der Bereich zeigt währenddessen einen Vorbereitungszustand;
  bei einem lokalen Fehler bleiben vorhandene Daten unverändert und die
  Vorbereitung kann gezielt wiederholt werden. Spätere Detailimporte
  aktualisieren den Typindex zusammen mit den Items. Eine Namenssuche
  prüft dadurch die unterschiedlichen Typen und springt anschließend über den
  vorhandenen Typindex zu den Contract-Items, statt sämtliche Itemzeilen nach
  `%Suchtext%` zu durchsuchen. Der vollständige Contract- und Itemindex bleibt
  autoritativ.
- Die Namenseingabe startet die lokale Suche erst nach 700 Millisekunden ohne
  weiteren Tastendruck. Jeder neue Buchstabe bricht den noch wartenden älteren
  Auftrag ab; dadurch wird beim normalen Schreiben eines Wortes nur einmal
  gesucht. Die Eingabetaste überspringt die Wartezeit und sucht sofort.
  Ergebnisaufträge tragen weiterhin ihre vollständige Suchidentität, sodass
  eine ältere Suche niemals Treffer einer neueren Eingabe überschreiben darf.
- Wiederholte Contract-Schreiboperationen verwenden innerhalb einer geöffneten
  SQLite-Verbindung vorbereitete Statements erneut. Bindings werden nach jeder
  Ausführung zurückgesetzt; Transaktionsgrenzen, WAL-Modus, Fremdschlüssel und
  die gespeicherten Werte bleiben unverändert. Abfragespalten werden einmal je
  Statement statt erneut je Ergebniszeile aufgelöst. Diese Optimierung verkürzt
  die lokale Übernahme bereits geladener Regions- und Detaildaten; sie erhöht
  weder ESI-Parallelität noch umgeht sie Cache-, Retry- oder Fehlerbudgetregeln.
- Ein unveränderter Contract löst bei einem erneuten erfolgreichen Regionslauf
  kein SQLite-Zeilenupdate mehr aus. Liefert ESI für alle Seiten einer Region
  `304 Not Modified`, werden ausschließlich Versuch, Frische und nächster
  erlaubter Abruf der Region fortgeschrieben; bestehende Contract- und
  Itemzeilen bleiben unverändert. Fehlt bei einer 304-Antwort `X-Pages`, bleibt
  die zur validierten Cache-Repräsentation gehörende Seitenzahl erhalten.
  Echte Änderungen, entfernte Contracts sowie inkonsistente oder doppelte
  Seitensätze behalten ihre bisherigen Aktivierungsregeln.
- Die transaktionale Regionsübernahme prüft vor Beginn und danach alle 128
  Datensätze auf eine Abbruchanforderung. Ein sicherer Stopp rollt die offene
  Regionstransaktion zurück; er muss nicht erst den vollständigen Regionssatz
  fertigschreiben.
- Kategorien und Gruppen werden einmal je Runtime sowie nach Abschluss oder
  sicherem Stopp eines Imports neu aggregiert. Ein laufender Detailimport löst
  nicht mehr nach jeweils 250 neuen Items vollständige Facet- und Suchabfragen
  aus. Contract-Fortschritt wird höchstens alle zwei Sekunden veröffentlicht;
  Phasenwechsel und terminale Zustände bleiben unmittelbar sichtbar.
- Abgebrochene oder durch eine neuere Eingabe überholte Contract-Suchen prüfen
  die Task-Abbruchanforderung vor dem SQLite-Zugriff und dürfen anschließend
  keine älteren Ergebnisse oder Fehler mehr veröffentlichen.
- Solange der Erstimport aller zu diesem Zeitpunkt noch bestehenden öffentlichen
  Verträge unvollständig ist, zeigt der Bereich **Public Contracts** einen nicht
  einklappbaren, fett und rot hervorgehobenen Warnhinweis. Der Hinweis nennt die
  derzeit zu erwartenden zwei bis drei Tage Laufzeit, die automatische
  Fortsetzung im Hintergrund und nach einem App-Neustart sowie eine mögliche
  Verlangsamung. Er stellt außerdem klar, dass der Bereich jederzeit verlassen
  und der Import in der Navigationsseitenleiste gesteuert werden kann. Die
  Importleistung wird weiter optimiert.
- Diagnoseausgaben und Dokumentation dürfen keine Tokens, Secrets oder private
  ESI-Nutzdaten enthalten.
- Löschen, Ersetzen, Migration, Token-Widerruf und andere schwer rückgängig zu
  machende Aktionen benötigen eine klar erkennbare Zielmenge und Bestätigung.

Die datierte Sicherheitsbewertung steht in
[`Documentation/SECURITY_AUDIT_2026-07-30.md`](Documentation/SECURITY_AUDIT_2026-07-30.md).

## Laufzeit und Hintergrundarbeit

Die verbindliche Reihenfolge der nächsten Stabilitäts- und Laufzeitarbeiten
mit kurzen, wiederverwendbaren Prompts steht in
[`Optimierung.md`](Optimierung.md).

- Öffentliche Contract-Aktualisierungen laufen mit Background-Priorität;
  automatische Main-Hub-Aktualisierungen verwenden weiterhin Utility. Auch ein
  ausdrücklich in der Oberfläche gestarteter
  mehrtägiger Contract-Import verwendet nach dem Start die begrenzte
  Hintergrundspur. Die automatische Fortsetzung ist seit 20.10.2026 bei jedem
  Programmstart aktiv. Die bestehenden Seiten-, Worker-, Cache- und Abbruchbegrenzungen
  bleiben unverändert.
- Sämtliche GET- und POST-Transporte desselben App-ESI-Clients passieren eine
  gemeinsame, abbrechbare Warteschlange. Insgesamt laufen höchstens sechs
  HTTP-Anfragen gleichzeitig; automatische Arbeit darf davon höchstens zwei
  gleichzeitig belegen. Interaktive Planner-Anfragen werden vor bereits
  wartenden Contract- und anderen Automatikabrufen gestartet. Ein laufender
  Request wird nicht gewaltsam verdrängt, und Retry-Wartezeit belegt keinen
  Transportplatz.
- Dieselbe Warteschlange setzt CCPs ESI-Grenzen für alle Abrufe durch: Meldet
  ESI höchstens 20 verbleibende Fehler im aktuellen Fehlerfenster oder
  antwortet mit 420, startet bis zum gemeldeten Fensterende keine weitere
  Anfrage. Ein 429 sperrt nur das betroffene Token-Budget (Gruppe und
  Charakter bzw. öffentliche Abrufe) bis `Retry-After`. Wird ein Budget knapp
  (höchstens ein Zehntel, mindestens zehn Tokens übrig), werden dessen
  Anfragen auf die mittlere Rückgabegeschwindigkeit des Fensters verteilt,
  etwa alle 12 Sekunden bei 150 Tokens je 15 Minuten. Wartende Anfragen
  belegen keinen Transportplatz und lassen sich abbrechen.
- Nach einem Planner-Lauf wird der LRU-Antwortcache nur bei Bedarf auf höchstens
  32 MiB reduziert. Gespeicherte Contract-Regions- und Item-Seiten sowie die
  große Main-Hub-Region werden nach ihrer fachlichen Übernahme gezielt
  freigegeben. Bei macOS-Speicherwarnung bleiben höchstens 16 MiB der zuletzt
  genutzten ESI-Antworten erhalten; bei kritischem Speicherdruck wird dieser
  abgeleitete Cache vollständig verworfen. Persistierte Snapshots und explizite
  Teil-/Fehlerzustände bleiben bestehen und werden nicht als leer interpretiert.
- Hinter dem Arbeitsspeicher liegt ein dauerhafter ESI-Antwortcache
  (`<Datenordner>/caches/esi-responses.sqlite`, Eigentümerentscheidung vom
  23.10.2026). Er speichert je Antwort Inhalt, `Expires`, `ETag`,
  `Last-Modified`, Seitenzahl und Herkunft, getrennt nach öffentlichen Abrufen
  und je Charakter.
  - Nach einem App-Start, einer LRU-Verdrängung oder einer Speicherwarnung
    werden noch gültige Antworten von der Platte bedient statt erneut von ESI
    abgerufen (CCP-Vorgabe: nicht vor `Expires` aktualisieren).
  - Abgelaufene Einträge dienen als Validator für einen bedingten Abruf;
    ESI antwortet dann bei unveränderten Daten mit 304.
  - Nur im Arbeitsspeicher bleiben das öffentliche Regions-Orderbuch eines
    Hub-Scans (ohne `type_id`) und die Public-Contracts-Abrufe. Sie werden
    nach ihrer Übernahme ohnehin verworfen. Einzeltyp-Preise und
    Strukturmarkt-Orderbücher werden dauerhaft gespeichert.
  - Obergrenze 512 MB auf der Platte; darüber fallen die am längsten nicht
    genutzten Einträge heraus.
  - Einträge eines anderen `X-Compatibility-Date` werden beim Öffnen
    verworfen. Ein Inhalt, den eine neuere App-Version nicht mehr lesen kann,
    wird gelöscht und neu von ESI geladen.
  - Das Trennen eines Charakters löscht auch seine dauerhaften Einträge.
- Strukturen ohne Andockberechtigung (403) oder ohne vorhandene Struktur (404)
  merkt sich die App je Charakter 24 Stunden lang, auch über Neustarts. Der
  Charakterabgleich fragt sie in dieser Zeit nicht erneut bei ESI ab und
  zeigt sie weiter als nicht zugänglich. Danach wird einmal neu geprüft. Eine
  ausdrücklich gestartete Struktursuche fragt immer direkt bei ESI und
  aktualisiert den Merker; ein erfolgreicher Abruf löscht ihn
  (Eigentümerentscheidung vom 23.10.2026).
  - Ist die Datei nicht nutzbar, arbeitet die App für diesen Lauf ohne den
    dauerhaften Cache weiter.
- Fortschrittswerte lang laufender Contract- und Main-Hub-Importe werden für
  die Oberfläche auf höchstens eine Aktualisierung alle zwei Sekunden
  gebündelt.
  Start, Phasenwechsel, Fehler, Abbruch und Abschluss werden weiterhin sofort
  veröffentlicht; die fachliche Hintergrundarbeit selbst wird nicht gedrosselt.
- Der gemeinsame `RuntimeState` verwendet Swift Observation (`@Observable`).
  Eine Ansicht wird nur noch neu gezeichnet, wenn sich einer der
  Runtime-Werte ändert, die sie beim Zeichnen tatsächlich gelesen hat. Eine
  Fortschrittsmeldung der Contracts oder des Main-Hub-Scans zeichnet deshalb
  nur die Statusanzeigen neu, die diesen Fortschritt zeigen, nicht mehr
  Dashboard, Hub-Chancen, Handel oder andere offene Bereiche. App-Szene und
  Navigationscontainer besitzen den Runtime-Zustand weiterhin, ohne ihn
  pauschal zu beobachten.
- Der Planer liest Befehle und fachliche Werte weiterhin aus demselben
  `RuntimeState` und beobachtet zusätzlich seinen schmalen Feature-Kanal.
  Dieser Kanal wird durch Produktionsbasis, Plan, Rechenstatus, Rechenfehler,
  Lagerfreigabe und Planer-Konfigurationsbereitschaft invalidiert. Änderungen
  an Public Contracts, Markt, Dashboard, SDE-Installation oder allgemeinem
  Status lösen deshalb keine Neuberechnung des großen Planer-View-Baums aus.
- Abgeleitete Werte werden einmal je Quelländerung statt bei jedem Zeichnen
  berechnet: Die Markt-Kontextkennung (sortiertes JSON der Produktionsbasis)
  nur nach einer Basisänderung, die LP-Store-Typmenge einmal je geladenem
  Katalog statt für jede Chancenzeile, und der gespeicherte Vermögensverlauf
  im Dashboard und in **Net Worth** einmal je gespeichertem Stand.
- Die Hub-Chancen lesen Filtereinstellungen und Budgetgrenze einmal je
  Filterdurchlauf und projizieren angepasste Runs, ME und TE vor dem Sortieren
  einmal je Zeile statt in jedem Sortiervergleich. Ergebnis und Reihenfolge
  bleiben unverändert.
- Mehrseitige ESI-Abrufe (Assets, Blaupausen, Jobs, Orders, Wallet,
  Contracts, Strukturmärkte und das öffentliche Regions-Orderbuch der
  NPC-Hub-Scans) laden die Seiten ab Seite 2 mit höchstens vier gleichzeitig
  offenen Seiten und übernehmen sie streng in Seitenreihenfolge. Ebenso laden
  die Itemlisten privater Item-Exchange- und Auktionsverträge begrenzt
  parallel in Vertragsreihenfolge. Die gemeinsame Warteschlange bleibt die
  obere Grenze (sechs Transporte, davon höchstens zwei automatische);
  Seitenzahlprüfung, Fortschritt, Abbruch und Teilzustände bleiben erhalten.
  Alle Seiten eines Abrufs müssen denselben `Last-Modified`-Stand haben.
  Aktualisiert ESI die Daten während des Lesens, wird einmal neu gelesen;
  dabei kommen nur die veralteten Seiten erneut von ESI. Ein zweiter
  gemischter Stand wird als ungültige Seitenfolge abgelehnt. Läuft Seite 1
  innerhalb von fünf Sekunden ab, wartet der Abruf auf ESIs Aktualisierung.
  Nach einem Hub-Scan wird nur das vollständige Regions-Orderbuch aus dem
  Zwischenspeicher entfernt; Einzeltyp-Preise behalten ihr Cache-Fenster.
  Der Public-Contracts-Import behält seine bewusst gedrosselte Taktung.
- Nach einem Charakterabgleich wird der vorherige gespeicherte Snapshot
  eines Bereichs nur noch dekodiert, wenn der neue Abruf keinen Wert lieferte
  und der letzte bekannte Stand als veraltet weitergeführt werden muss.
  Erfolgreiche Abrufe ersetzen den Stand ohne diesen zusätzlichen
  Hauptthread-Aufwand.
- Das Dashboard dekodiert gespeicherte Industry-Job- und Skill-Snapshots nur
  noch dann neu, wenn sich diese Eingaben oder der aktive SDE-Build ändern. Die
  Dekodierung und Aggregation laufen außerhalb des Main-Actors; reine
  Fortschrittsmeldungen anderer Hintergrundarbeiten verwenden den vorbereiteten
  unveränderlichen Snapshot weiter.
- Fehlende, unlesbare, stale, partielle oder verbotene Job- und Skillquellen
  bleiben im vorbereiteten Dashboard-Snapshot unvollständig. Sie werden nicht
  als leere aktuelle Daten oder als Kapazität null dargestellt.
- Der vollständige Main-Hub-Nachfrage-Ledger bleibt die autoritative Grundlage
  für Vergleiche überlebender Order-IDs. V3 führt diese Vergleiche pro Typ in
  einem rollierenden 24-Stunden-Fenster über UTC-Mitternacht fort. Erst nach
  mindestens 30 Minuten und mindestens einer vergleichbaren Order des Typs wird
  die beobachtete Untergrenze auf eine Tagesrate normiert. Nicht beobachtete
  Typen bleiben unverfügbar und werden nicht als Bedarf null dargestellt.
  Zusätzlich wird eine kleine abgeleitete Zusammenfassung atomar gespeichert,
  damit ein normaler späterer App-Start nicht den vollständigen
  Order-Baseline-Ledger dekodieren muss.
- Der Ledger verarbeitet einen neuen exakten Hub-Snapshot in einem Durchlauf:
  Jede gültige Order wird zugleich mit der vorherigen Baseline verglichen und
  als nächste kompakte Baseline übernommen. Alle 2.048 Orders wird kooperativ
  auf Abbruch geprüft; ein abgebrochener Lauf veröffentlicht und persistiert
  weder eine teilweise Baseline noch teilweise Nachfrage. Das bisherige
  ausführliche V1-JSON und das kompakte V2-Format bleiben lesbar und werden erst
  mit einem nachfolgenden erfolgreichen Snapshot atomar als V3 mit kompakten
  Baseline-Zeilen und kleinen Nachfrageintervallen gespeichert.
- Eine interaktive Planner-Berechnung hat Vorrang vor schweren automatischen
  Main-Hub- und Public-Contracts-Scans. Bereits geplante Automatikstarts werden
  ausgesetzt, laufende automatische Arbeit wird kooperativ abgebrochen und nach
  dem letzten von gegebenenfalls mehreren überlappenden Planner-Läufen wieder
  geplant. Manuell gestartete Scans bleiben eine ausdrückliche Nutzeraktion und
  werden durch diese Regel nicht ungefragt beendet. Ein abgebrochener
  Contract-Lauf behält seinen fortsetzbaren Teilindex; ein abgebrochener
  Main-Hub-Lauf ersetzt nicht die letzte vollständige Chancenanalyse.
- Ein Sprachwechsel aktualisiert weiterhin die Locale und die lokalisierten
  Inhalte, ersetzt aber nicht mehr synchron den gesamten sichtbaren Detailbaum
  während der segmentierten Accessibility-Aktion.
- Der Mineralpreisticker des Dashboards baut seine doppelte
  Zeilenfolge einmal in einer `NSHostingView` auf. Eine lineare Core Animation
  verschiebt anschließend ausschließlich deren Layer, statt den vollständigen
  SwiftUI-/AppKit-Layoutbaum pro Frame neu zu berechnen. Bei inaktiver App wird
  die Animation entfernt. **Bewegung reduzieren** verwendet weiterhin eine
  statisch horizontal scrollbare einfache Zeilenfolge. Der Umlauf dauert
  weiterhin 32 Sekunden. Die Inhalte verwenden die gemeinsame
  Mineralien-Kaufempfehlung und direkt kopierbare Material- und Ortsnamen.
- Ein Messprotokoll schreibt Zeiten und Zähler ins macOS-Systemprotokoll
  (Subsystem `com.local.EVENexusSimple`, Kategorie `performance`). Es enthält
  nur Schrittnamen, Dauern und Anzahlen, keine Charakter-, Struktur- oder
  Itemkennungen und keine Tokens. Gelesen wird es mit
  `/usr/bin/log stream --predicate 'subsystem == "com.local.EVENexusSimple" AND category == "performance"'`
  oder nachträglich mit `/usr/bin/log show --last 1h --predicate …`. Erfasst
  werden:
  - Startmeilensteine relativ zum Prozessstart: Startladen begonnen,
    Charaktere synchronisiert, Konfiguration bereit, Analysen gestartet, Start
    beendet;
  - die Dauer der Profil-Referenzdaten sowie Quelle und Dauer der
    Facility-Dogma (`table` oder `package`) und der Blueprint-Definitionen
    (Cache-Treffer oder Neuladen);
  - beim Main-Hub-Scan die Dauer jeder Phase einschließlich Home- und
    Coalition-Hub, die Gesamtdauer, die Volumendiagnose und die ESI-Last des
    Scans.
- Die ESI-Last zählt ein rein beobachtender Transport unter dem ESI-Client.
  Er verändert keine Anfrage und keine Antwort und sendet selbst nichts; die
  Grenzen setzt weiter die gemeinsame Warteschlange durch.
  - Je Routenfamilie (Kennungen als `{id}`) zählt er Anfragen, Datenmenge,
    304-Antworten, 4xx/5xx und Fehler.
  - Dazu kommt eine passive Prüfung der CCP-Vorgaben:
    - fehlender `User-Agent` oder fehlendes `X-Compatibility-Date`;
    - ein Compatibility-Date in der Zukunft;
    - GET-Abrufe vor dem `Expires` der vorherigen Antwort („early“);
    - 420- und 429-Antworten;
    - die niedrigsten gemeldeten Fehler- und Token-Budgets.
  - Eine Zusammenfassung seit App-Start erscheint höchstens einmal je Minute,
    wenn es neue Abrufe gab.
  - Der dauerhafte ESI-Antwortcache (oben) verhindert Abrufe vor `Expires`
    auch über App-Neustarts hinweg. Der Zähler „early“ belegt das im
    laufenden Betrieb.

## Installation und Entwicklung

Die fertigen lokalen Release-Apps liegen unter `~/Downloads/` (Apple Silicon, macOS 14+,
lokale Ad-hoc-Signatur). Build-Nachweise liegen unter `dist/`.
Die aktualisierte Dashboard-App liegt zusätzlich als
`EVE New Eden Nexus - Assets, Industry, Markets-Dashboard-2026-10-17-v2.app`
in Downloads. Sie enthält Apple-Silicon- und Intel-Code, ist lokal ad-hoc-signiert
und verwendet als normale App den vorhandenen Datenstand. Vor dem Start eine
bereits laufende normale App beenden. Frühere App-Dateien bleiben erhalten.
Diese lokale Ausgabe ist nicht notarisiert; aktuelle Build- und Startnachweise
liegen unter `/private/tmp/eve-dashboard-market-layout-20261017.VpHSj3/`.
Die separat benannte `EVE New Eden Nexus - Assets, Industry, Markets-DEV.app` enthält eine
geprüfte Kopie der lokalen Daten, Kataloge und Einstellungen zum Exportzeitpunkt. Beim ersten
Start wird sie atomar nach `~/Library/Application Support/com.local.EVENexusSimple.DEV/`
übernommen. Weitere Starts erhalten die dortigen Änderungen. Ein neuer Export überschreibt
keinen bestehenden DEV-Bestand. Der aktive Quellprojektordner bleibt derselbe.

DEV verwendet die eigene Bundle-ID und Einstellungsdomäne `com.local.EVENexusSimple.DEV`
sowie den eigenen Schlüsselbunddienst `com.local.EVENexusSimple.DEV.refresh-token`.
Anmeldeschlüssel sind nicht enthalten; Live-Abfragen erfordern eine erneute Anmeldung in DEV.
Der bestehende lokale SSO-Callback bleibt erhalten; Anmeldungen deshalb nacheinander durchführen.
Normale App, produktive Datenpfade und deren technische Identitäten bleiben unverändert.
Die DEV-Datenübernahme läuft vor der Oberfläche im nativen App-Einstieg; ein zusätzlicher
Hilfsstarter ist nicht erforderlich. Die eigene Einstellungsdomäne wird über die Standard-
Einstellungen dieser DEV-App geöffnet. Ein unterbrochener Einstellungsimport wird beim
nächsten Start fortgesetzt, ohne die vorhandene DEV-Datenbank neu anzulegen. Der Exporter
unter `Scripts/` erzeugt das Paket desselben App-Targets. `dist/` bleibt vorsorglich von Git ausgeschlossen. Die DEV-App enthält private Daten und wird
ausschließlich lokal außerhalb synchronisierter Ordner aufbewahrt.
Normale App und DEV-App enthalten beide die Korrektur der Einstellungsreiter unterhalb
der nativen Titelleiste; ihre bestehenden getrennten Datenbestände bleiben erhalten.
Prüfnachweise und Exportablauf: [DEV_EXPORT.md](Documentation/DEV_EXPORT.md).


Voraussetzungen sind macOS 14 oder neuer, eine passende Xcode-Version mit
Swift 6 für das vorhandene native Projekt. `project.yml` bleibt eine Generatorvorlage;
Regeneration ist ein gesonderter Strukturabgleich, kein notwendiger Startschritt.

Vorhandenes, geprüftes Xcode-Projekt öffnen:

```sh
open EVENexusSimple.xcodeproj
```

Deterministische SwiftPM-Tests:

```sh
swift test
```

Der GitHub-Actions-Lauf **Swift package tests** bildet zusätzlich die
Kompatibilitätsgrenze des öffentlichen Repositories auf `macos-15` mit der dort
bereitgestellten Swift-6.1-Werkzeugkette ab. SwiftData-Schemametadaten werden
deshalb als berechnete statische Werte erzeugt; große SwiftUI-Identitäts- und
Triggerausdrücke sind in explizit typisierte Zwischenschritte zerlegt. Diese
Darstellung ändert weder Schema-Versionen noch die erzeugten Identitätswerte,
verhindert aber toolchainabhängige Sendable- und Type-Checker-Fehler. Der
Statusseiten-Decoder akzeptiert sowohl ISO-8601-Zeitstempel mit als auch ohne
Sekundenbruchteile explizit, weil die Foundation-Standardstrategie diese Formen
zwischen den eingesetzten Swift-Versionen unterschiedlich behandelt.

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

Für einen vorbereiteten öffentlichen SDE-Kandidaten kann der vollständige
Mapper- und SQLite-Reopen-Nachweis ohne Netzwerk und ohne produktive
Aktivierung mit der Umgebungsvariable
`EVE_STATIC_DATA_KIT_REAL_PACKAGE=/absoluter/pfad/zum/paket.evesde` gezielt
eingeschaltet werden. Ohne diese Variable bleiben die Real-SDE-Tests als
ausdrücklich übersprungene Live-Kompatibilitätsstufe vom deterministischen
Standardsatz getrennt.

## Konfiguration und typischer Arbeitsablauf

1. App bauen und starten.
2. Unter **Data & Settings → SDE** den installierten Katalog prüfen und ein
   Update nur nach Vorschau und Schemafreigabe aktivieren. Ist der offizielle
   Build bereits aktuell, kann **Aktuellen Katalog neu importieren …** genutzt
   werden, um ihn nach einer Adapter- oder Klassifikationserweiterung sicher neu
   aufzubauen. Nach erfolgreichem Update oder Neuimport die App vollständig
   beenden, neu öffnen und danach die Main-Hub-Analyse erneut ausführen.
3. Unter **Data & Settings → ESI** einen Charakter per EVE SSO autorisieren.
   Jeder Charakter benötigt seine eigene Auswahl und Zustimmung im Browser.
4. Synchronisation ausführen und Teil-, Rechte- oder Fehlerzustände prüfen.
5. Unter **Industry Settings** Produktionsorte, Aktivitäten, Steuern und
   Zuschläge konfigurieren.
6. Unter **Data & Settings → Logistik** Kurierwerte, Jump-Freighter-Annahmen und feste
   Capital-Routen konfigurieren. Die Sonnensystemsuche wird beim Öffnen im
   Hintergrund vorbereitet; bestehende Routen bleiben bei einem ESI-Fehler
   erhalten.
7. Unter **Market Settings** Main, Home und gegebenenfalls Coalition Hub sowie
   Trader- und Gebührennachweise (inklusive bestätigtem Vertragsgebührensatz)
   festlegen.
8. Nach jedem Start lädt die App Charaktere, Analysen und die Hub-Scans
   automatisch; den Stand zeigt die Seitenleisten-Karte **Automatic data**.
9. Auf dem Dashboard (**Top-Chancen**) oder in den Main-, Home- und
   Coalition-Hub-Chancen ein Produkt nach Gewinn, ROI, Bedarf oder eigener
   Entscheidung wählen und mit **Bauen** an den Planner übergeben.
10. Schutzbestände setzen und im Planner Bestände und Blueprints, Marktdeckung, Produktionszweige,
    Kostenbestandteile und Warnungen prüfen, den **Zielmarkt** (einschließlich
    Allianzmarkt) wählen und den Kaufort-Hinweis für Mineralien und
    Mondmaterialien beachten; Empfehlungen bleiben übersteuerbar.
11. Produktion nur nach erneuter Kontrolle im etablierten Planner als
    historischen Datensatz erfassen.

## Bekannte Grenzen

- Die App installiert keine Jobs im EVE-Client und verändert keine Ingame-
  Assets oder Orders.
- Der gemeinsame Science-Domänenkern und SDE-Katalog unterstützen Copying,
  ME-/TE-Forschung, Erfindungs-Skills, Decryptor-Modifikatoren sowie Erwartungs-
  und 95%-Plan. Die Planner-Quellen **Copying**, **Forschung** und **Erfindung**
  sind als konkrete lokale Planungsaufträge angebunden. Unvollständige Anlagen-,
  Kosten-, Skill- oder Run-Daten blockieren die Übernahme. Externe manuelle BPCs
  bleiben weiterhin nutzbar. Tech-III-Reverse-Engineering ist nicht unterstützt.
- ESI liefert keine allgemeine Liste aller Player Structures mit Dockingrecht
  und keine vom Eigentümer festgelegte Structure-Brokergebühr.
- Öffentliche Marktorders sind keine abgeschlossene Verkaufshistorie.
- Preis-, Status-, Rollen- und Strukturzugriffe können sich ändern; datierte
  Live-Nachweise sind keine dauerhafte Garantie.
- Signierung, Notarisierung, Langzeit-RSS/CPU, vollständige Tastaturprüfung
  sowie die visuelle Owner-Abnahme bleiben eigenständige Freigabeschritte,
  sofern die Acceptance-Matrix sie nicht ausdrücklich als abgeschlossen ausweist.
- VoiceOver wird nicht unterstützt und ist auf Entscheidung des Eigentümers
  (19.10.2026) kein Abnahmeschritt. Vorhandene Barrierefreiheitsbeschriftungen
  bleiben im Code erhalten; zuverlässig funktioniert VoiceOver nur im Hauptmenü.

## Pflege dieser Dokumentation

`PROJECT_STATE.md` ist der aktuelle Status; `PRODUCT.md` beschreibt den vorhandenen Produktumfang. Jede
Implementierung, Fehlerbehebung, Migration, Konfigurations- oder wesentliche
Verhaltensänderung aktualisiert sie im selben Arbeitsschritt. Historische oder
ersetzte Aussagen werden nicht als aktuelles Verhalten stehen gelassen, sondern
im [Entwicklungstagebuch](dev-diary.md) eingeordnet.

Für agentische Projektarbeit gilt [MODEL_POLICY.md](MODEL_POLICY.md): GPT-5.6 Sol
mit Reasoning-Stufe High ist der Standard. Ein anderes Modell oder eine andere
Reasoning-Stufe erfordert eine ausdrückliche Benutzeranweisung oder – falls der
Standard nicht ausreicht – eine vorherige Auswahl aus konkreten Vorschlägen.

Ein Diary-Eintrag nennt Datum, Ziel, Änderung, Ergebnis, konkrete Prüfung und
offene Arbeit. Prüfergebnisse werden zusätzlich in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md) gepflegt; neue oder
geänderte Modulübergaben gehören nach
[`Documentation/HANDOFFS.md`](Documentation/HANDOFFS.md). Architekturänderungen
werden nicht still überschrieben, sondern durch ein neues oder ablösendes ADR
dokumentiert.

## Weiterführende Dokumente

- [README](README.md) – kompakte Start- und Funktionsbeschreibung
- [Architektur](ARCHITECTURE.md) – Modulgrenzen und Fachverträge
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
