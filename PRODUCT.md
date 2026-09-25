# EVE New Eden Nexus - Assets, Industry, Markets – Dokumentation

> Konsolidiert am 25.09.2026. Verbindlicher Status: [PROJECT_STATE.md](PROJECT_STATE.md).
> Fachbeschreibung aus dem aktuellen lokalen Stand vollständig erhalten; historische
> Testzahlen sind datierte Nachweise, keine neue Gesamtabnahme.

Aktueller Konsolidierungsstand: 25. September 2026

## Zusammengeführte vorhandene Fachabläufe

Der Planner enthält **Projekte & Einkauf**; Warehouse öffnet **Manuelle Lager**, Blueprints
**Wissenschaftsaufträge**, die Produktionsübersicht **Verkaufsbelege** und Einstellungen
**Preisprofile & Sicherung**. Alle Einstiege verwenden denselben lokalen Datenbestand.
Fertigungsprojekte sind getrennte Planungsdatensätze innerhalb der einen aktiven App.

Projektstatus, eigene Entwürfe, Lagerfreigaben, Prioritäten, persistente Reservierungen,
kontrollierte CSV-Importe, Preisprofile, Einkaufsfortschritt und Exporte sind verbunden.
Copying, ME-/TE-Forschung und Invention erzeugen konkrete gespeicherte Versorgung und
übernehmen deren Effizienzen, Kosten und vorgeschaltete Zeiten in die aktuelle Fertigung.
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
| SDE | statische Typen, Blueprints, Aktivitäten, Dogma- und allgemeine Volumendaten | Live-Marktdaten, verpacktes Transportvolumen oder Anmeldung |
| öffentliches ESI-Typdetail | verpacktes Transportvolumen für die konkret benötigten Typen | Produktionsgraph oder Transportkostenentscheidung |
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
| Dashboard | verdichteter Überblick über Jobs, Finanzen, Markt und Automatisierungszustände; beim ersten Dashboard-Aufruf eines App-Laufs werden die verbundenen Charaktere einmal synchronisiert |
| Industry Jobs | gespeicherte Charakter-Jobs mit Aktivität, Status, Zeitpunkt und expliziten Quellenlücken |
| Planner | Produktionsgraph, Build/Buy/Warehouse-Auswahl, Installation, Logistik, Gebühren, Erlös, Profit und ROI |
| Daten & Einstellungen → Logistik | Pflege der Main-Hub-Kurierwerte, Jump-Freighter-Annahmen und festen Capital-Routen im horizontalen Einstellungsmenü; Änderungen werden erst beim Speichern in die gemeinsame Production Basis übernommen |
| Rekursive Kalkulation | sitzungsgebundene Nachkalkulation nicht erfasster Produktion aus EVE-Itemzeilen, mit vollständigem Baugraph, Blueprintquelle/-kosten je Stufe und wählbarer Main→Home- oder Main→Home→Main-Logistik |
| Market Browser | öffentliche Kauf- und Verkaufsorders über Regionen mit Quellen- und Ortsauflösung |
| Main Hub Opportunities | Fertigungskandidaten und sortierbare Chancenkennzahlen für den exakt konfigurierten Main Hub; **Bauen** übergibt die konkrete Charge an den Planner |
| Public Contracts | lokaler, resumierbarer Index öffentlicher ESI-Contracts mit sicherem Stopp und Teilstatus |
| Reactions | veröffentlichte Reaktionsrezepte, vollständige Batch-Kosten, Logistik und Make-or-Buy-Vergleich |
| Moon purchase analysis | Mengen- und Preisvergleich ausgewählter Marktrollen für Mondmaterialien; vollständiger Tabellenexport als PNG |
| Mineral purchase analysis | Mengen- und Preisvergleich der veröffentlichten SDE-Gruppe `Mineral` an allen ausgewählten Märkten; vollständiger Tabellenexport als PNG |
| All items | faktische persönliche und optional autorisierte Corporation-Bestände an allen bekannten Orten |
| Warehouse | nur planungsfähiger Bestand an exakt konfigurierten Produktionsorten, abzüglich Schutzbeständen und Reservierungen |
| Blueprints | persönliche BPO/BPC-Instanzen, Runs, ME/TE und belegte Forschungskostenschätzung |
| Production Overview | gespeicherte Produktionshistorie mit editierbaren Verkaufsdaten und explizit unbekannten Kosten |
| Wallet | persönliche Wallet-Salden je verbundenem Charakter |
| Net Worth | tägliche lokale Bewertung von Wallet, Assets, laufender Produktion, Orders, Contracts und zugänglichen Corporation-Anteilen |
| Data & Settings | allgemeine Darstellung, SDE, ESI, Industrie- und Marktkonfiguration |

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

Die Vertragsstatus-Fußleiste verwendet auch bei der Berechnung der minimalen
Fenstergröße die Mindestbreite der Seitenleiste (180 Punkte). Mehrzeilige
Statusmeldungen vergrößern dadurch nicht den gesamten Navigationsbereich über
die Fensterhöhe hinaus. Kopfmenüs, oberster Navigationseintrag und Logo bleiben
innerhalb des Fensters; bei kleiner Höhe scrollt die Navigationsliste.

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

Beim ersten Dashboard-Aufruf eines laufenden App-Prozesses synchronisiert die
App jeden verbundenen Charakter genau einmal über den bestehenden vollständigen
Charakter-Sync. Dazu gehoeren insbesondere Wallet, Assets, Industry Jobs,
Orders, private Contracts sowie zugängliche Corporation-Wallets und -Assets.
Einzelne Fehler behalten den letzten bekannten Quellstand und werden als
partiell gemeldet; sie ersetzen ihn nicht durch null. Die Wallet-Karte bietet
denselben Ablauf zusätzlich als sichtbare manuelle Aktualisierung an.

Nach einer erfolgreichen Aktualisierung der öffentlichen Referenzpreise wird
höchstens ein Vermögenspunkt pro lokalem Kalendertag gespeichert. Eine
weitere Aktualisierung am selben Tag ersetzt diesen Tagespunkt; Tage, an denen
die App keinen Punkt erfasst hat, werden nicht erfunden. Die Zeitachse verwendet
die wirklichen Datumsabstände. Die Wertachse passt sich dem sichtbaren Bereich
an, damit kleine Aenderungen nicht durch einen erzwungenen Nullpunkt
verschwinden. Gesamtwert, Wallet, Assets und **In Produktion** können getrennt
betrachtet werden; auf der Net-Worth-Seite sind Komponenten einzeln ein- und
ausblendbar.

**In Produktion** bewertet die bereits verbrauchten SDE-Materialmengen aktiver,
pausierter oder abholbereiter Manufacturing- und Reaction-Jobs mit ESI Average
Price und Adjusted Price als Fallback. Bekannte ME-Werte vorhandener
Blueprintinstanzen werden angewendet. Ausgelieferte, abgebrochene und
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

### Blueprints, Industrie und Reaktionen

BPO und BPC bleiben unterschiedliche Instanzen mit eigener Herkunft. Eine BPC
kann als verbrauchter Erwerbspreis, eine BPO nur mit einer expliziten lokalen
Kostenallokation in einen Plan eingehen. Jede verwendete BPC bleibt anhand ihrer
Item- oder Contract-Identität ein eigener Fertigungsjob mit eigenen Runs,
ME/TE, Materialrundungen und Rest-Runs. Unbekannte Blueprint- oder
Forschungskosten werden nicht zu null.

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
Erzausbeute und eine bestätigte Refining-Gebühr. Ein leeres Gebührenfeld
bedeutet unbekannt; 0 % gilt nur als ausdrücklich bestätigte gebührenfreie
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
Damit ist insbesondere eine vorhandene Tatara mit Reprocessing-Service und
bekannter Ausbeute, aber leerem Gebührenfeld ausdrücklich **unvollständig** und
nicht scheinbar unberücksichtigt. Änderungen an Anlage, Charakter oder Gebühr
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
Mineralausbeute und bestätigter Refining-Gebühr. Anschließend werden beide
vollständigen Wege nochmals mit der tatsächlichen Kurieraufteilung und
Millionenrundung bewertet. Nur ein positiver vollständiger Kostenvorteil
ersetzt Mineralien durch Erz. Andernfalls bleiben Mineralmenge, Logistik und
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

Das öffentliche ESI-`packaged_volume` wird dabei nicht nur für normale
Materialpositionen, sondern auch unmittelbar für jede geprüfte komprimierte
Erzoption verwendet. Das SDE bleibt für Chargengröße, Mineralausgabe und den
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
verwendet die je Produktklasse konfigurierte Fertigungsanlage; Reaktionen
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

Im Planner ist die Blueprintquelle jedes tatsächlich gebauten Knotens
kostenwirksam. Eine eigene BPC
benötigt ihren vollständigen Erwerbs- oder Aktivitätsbetrag, eine vorhandene
BPO eine ausdrücklich eingetragene Umlage für diesen Plan. Beim Kauf über
öffentliche Verträge werden nur aktive Item-Exchange-Verträge am exakten Main
Hub automatisch zugerechnet, wenn Preis, BPC-Kennung, Runs, ME und TE bekannt
sind und der Vertrag genau eine angebotene Blueprintposition ohne angeforderte
Gegenposition enthält. Mehrere eindeutig zurechenbare BPCs dürfen gemeinsam
alle benötigten Runs decken, erzeugen dabei jedoch immer getrennte Jobs. Ein
BPO-Kaufpreis wird vollständig angezeigt, aber nicht ohne
eingetragene Umlage einer einzelnen Produktion belastet. Bündel, Nullpreise und
alte Vertragszeilen ohne Runs/ME/TE bleiben ausdrücklich unkalkulierbar. Fehlt
bei irgendeinem produzierten Knoten eine Blueprintkostenquelle, bleiben
Gesamtkosten und Gewinn unverfügbar.

Die **Rekursive Kalkulation** rekonstruiert eine im Spiel nicht vollständig
erfasste Produktion aus einfachen `Gegenstand Menge`-Zeilen oder
tabulatorgetrennten EVE-Zeilen. Verbindlich übernommen
werden Gegenstandsname und positive Ganzzahlmenge; Gruppe, Volumen und der im
EVE-Export angezeigte ungefähre ISK-Wert bleiben sichtbare Referenz und ersetzen
weder SDE-Rezept noch Marktquote. Deutsche EVE-Zahlen mit Punkt als
Tausender- und Komma als Dezimaltrennzeichen werden erkannt. Jede importierte
Zeile wird in den bestehenden `Produkt Bedarf ME TE`-Vertrag überführt. Die
erste Auflösung verwendet nur interne Startwerte; anschließend werden ME und TE
anhand der von der SDE gelieferten EVE-Kategorie und -Gruppe gesammelt gesetzt.
Jeder normale Blueprint-Bauschritt kann diese Gruppenvorgabe einzeln
überschreiben. Die Werte gehen produktbezogen in die erneute rekursive Planung
ein und werden nicht aus dem ungefähren Exportwert geraten.

Der Nachkalkulationslauf erzwingt für alle herstellbaren Zwischenprodukte den
rekursiven Baupfad, verwendet aber weiterhin faktischen Warehouse-Bestand,
Schutzmengen und Reservierungen. Nach der ersten Auflösung muss für jeden
produzierten Blueprinttyp eine Quelle gewählt werden. Oberhalb der Einzelzeilen
kann die übliche Quelle gruppenweise als BPO oder BPC gesetzt werden. Reaktionen
verwenden Formeln und keine erforschbaren BPO/BPC-Werte; die standardmäßig
aktivierte, ausdrücklich sichtbare Annahme **alle Reaktionsformeln vorhanden**
ordnet ihnen 0 ISK Formelkosten zu und lässt ME/TE nicht anwendbar. Sie kann
abgeschaltet und jede Formel einzeln auf ungeklärt gesetzt werden. Diese
Annahme ist keine aus Assets abgeleitete Besitzbehauptung. Verbrauchte BPC-,
Kopier-, Erfindungs- und LP-BPC-Kosten werden als vollständiger Betrag
eingetragen; bei einer BPO ist nur eine ausdrückliche Umlage auf diese Produktion
kostenwirksam. Ein eindeutig zurechenbarer Main-Hub-BPC-Vertrag kann seinen
belegten Preis übernehmen. Fehlende Blueprint-, Markt-, Volumen-, Tarif- oder
Installationswerte halten die Gesamtsumme unverfügbar.

Die Route **Main Hub → Home Hub** enthält Materialtransport und Produktion; die
Route **Main Hub → Home Hub → Main Hub** addiert den Rücktransport der fertigen
Endprodukte. Beide verwenden die im Profil konfigurierten exakten Orte und
dieselben Vertragsaufteilungs-, Kollateral- und Rundungsregeln wie der Planner.
Die Kalkulation erzeugt keinen aktiven `StoredPlan`. Nach einer aktuellen
Berechnung zeigt sie jedoch eine ausdrückliche Vorschau für das Produktionsbuch
und kann nach Bestätigung je importiertem Endprodukt genau eine
Produktionsübersichtszeile anlegen. Material- und gemeinsame Blueprint-,
Installations- sowie Logistikkosten werden proportional zum bekannten
Materialwert verteilt; fehlt für alle Produkte ein positiver Materialwert,
erfolgt die Verteilung gleichmäßig. Dadurch wird die gemeinsame rekursive
Gesamtsumme nicht mehrfach angesetzt. Bei Main → Home stammen Verkaufsquote,
Verkaufssteuer und Brokergebühr aus dem Home-Hub-Szenario; bei Main → Home →
Main aus dem Main-Hub-Szenario, und die Rücklogistik wird den Produktionskosten
zugerechnet. Unbekannte Werte bleiben auch im Produktionsbuch unbekannt.

Diese Übernahme ist ausdrücklich eine **Rekonstruktion zum aktuellen
Marktstand**. Der gespeicherte unveränderliche Snapshot enthält SDE-Build,
ESI-Kompatibilitätsdatum, Preiszeitpunkt, Regelversion, Route und die aktuell
berechneten Gebühren. Er behauptet weder historische Einkaufspreise noch
damalige Systemindizes, Steuern oder Logistiktarife. Die Vorschau, ein zweiter
Bestätigungsdialog und eine Sperre gegen erneutes Speichern desselben
Sitzungslaufs schützen vor versehentlichen Doppeleinträgen.

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
optionaler Blueprint-Umlage und den erforderlichen Wegen der Profillogistik.
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

Der lokal gespeicherte Snapshot öffentlicher LP-Shop-Angebote bleibt für
die unterstützten Bauplanquellen verfügbar. Der
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

Für jede transportierte Einheit gilt ausschließlich das öffentliche
ESI-Typfeld `packaged_volume`. Die aktuelle clientbasierte CCP-SDE-Datei
`types` enthält bei Schiffen nur das entpackte `volume`; dieses darf deshalb
niemals als Ersatz dienen. Der Planner ermittelt zunächst die begrenzte Menge
aller für den Produktionsgraph benötigten Typen, lädt deren öffentliche
ESI-Typdetails mit begrenzter Parallelität und friert die Werte als eigenen
Quellensnapshot ein. Fehlt ein verpacktes Volumen, bleibt die betroffene
Logistik unverfügbar. Für die am 13. August 2026 live geprüfte Hulk liefert CCP
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
Steuersatz nur aus ihren eigenen belegten Home-/Coalition-Szenarien ableiten;
fehlt auch dieser Nachweis, bleibt er unverfügbar.

Reaktionen verwenden veröffentlichte SDE-Formeln; fehlende Markt-, Volumen-,
Kollateral- oder Tarifdaten machen den betroffenen Vergleich unverfügbar.

Der ausführliche Produktionsvertrag steht in
[`Documentation/PRODUCTION_BASIS.md`](Documentation/PRODUCTION_BASIS.md).

## Lokale Daten, Sicherheit und Wiederherstellung

- Refresh Tokens liegen ausschließlich im macOS-Schlüsselbund. Ein Client
  Secret wird nicht verwendet.
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
- Die primäre SwiftData-Datenbank besitzt einen stabilen Pfad unter der
  Anwendungskennung. Schemaänderungen werden versioniert migriert.
- Vor einer Migration wird eine Sicherheitskopie angelegt. Ein Legacy-Store
  wird nur dann kopiert, wenn noch kein kanonischer Store existiert, und nicht
  automatisch gelöscht.
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
- Der aktive SDE-Zeiger akzeptiert den historischen Legacy-Dateinamen und
  kanonische, bereits aktivierte `catalog-vN`-Dateien bis einschließlich der
  aktuellen Adapterversion. Dadurch bleibt ein gültiger Adapter-v2-Katalog
  nach der Einführung von Adapter 3 als installierter Build erkennbar und kann
  sicher neu importiert werden. Neue Aktivierungen schreiben weiterhin nur
  Adapter 3; fremde Pfade, nichtkanonische Versionsangaben und zukünftige
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
- Öffentliche Contract-Imports sind opt-in, zeigen Fortschritt und Teilstatus,
  können sicher gestoppt werden und bewahren einen letzten erfolgreichen Stand.
  Eine kompakte Steuerkarte bleibt dauerhaft in der Navigationsseitenleiste
  sichtbar. Dort lässt sich der Erstimport starten oder fortsetzen, ohne die
  Vertragsliste zu öffnen; laufende Arbeit kann dort sicher pausiert und eine
  fehlgeschlagene lokale Vorbereitung erneut angestoßen werden. Vorbereitung,
  Import, sicheres Anhalten, geplanter Lauf, unvollständiger und aktueller Stand
  bleiben getrennte sichtbare Zustände. Der Detailbereich kann jederzeit
  verlassen werden; der Import gehört dem gemeinsamen Runtime-State und läuft
  nicht als Lebenszyklusaufgabe der Vertragsansicht.
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
  Hintergrundspur; die Nutzerentscheidung aktiviert weiterhin die automatische
  Fortsetzung. Die bestehenden Seiten-, Worker-, Cache- und Abbruchbegrenzungen
  bleiben unverändert.
- Sämtliche GET- und POST-Transporte desselben App-ESI-Clients passieren eine
  gemeinsame, abbrechbare Warteschlange. Insgesamt laufen höchstens sechs
  HTTP-Anfragen gleichzeitig; automatische Arbeit darf davon höchstens zwei
  gleichzeitig belegen. Interaktive Planner-Anfragen werden vor bereits
  wartenden Contract- und anderen Automatikabrufen gestartet. Ein laufender
  Request wird nicht gewaltsam verdrängt, und Retry-Wartezeit belegt keinen
  Transportplatz.
- Nach einem Planner-Lauf wird der LRU-Antwortcache nur bei Bedarf auf höchstens
  32 MiB reduziert. Gespeicherte Contract-Regions- und Item-Seiten sowie die
  große Main-Hub-Region werden nach ihrer fachlichen Übernahme gezielt
  freigegeben. Bei macOS-Speicherwarnung bleiben höchstens 16 MiB der zuletzt
  genutzten ESI-Antworten erhalten; bei kritischem Speicherdruck wird dieser
  abgeleitete Cache vollständig verworfen. Persistierte Snapshots und explizite
  Teil-/Fehlerzustände bleiben bestehen und werden nicht als leer interpretiert.
- Fortschrittswerte lang laufender Contract- und Main-Hub-Importe werden für
  die Oberfläche auf höchstens eine Aktualisierung alle zwei Sekunden
  gebündelt.
  Start, Phasenwechsel, Fehler, Abbruch und Abschluss werden weiterhin sofort
  veröffentlicht; die fachliche Hintergrundarbeit selbst wird nicht gedrosselt.
- Die App-Szene und der Navigationscontainer besitzen den gemeinsamen
  `RuntimeState`, abonnieren aber nicht mehr pauschal jede seiner Änderungen.
  Dadurch zeichnet eine Fortschrittsmeldung nicht mehr die komplette
  Navigation neu; nur Ansichten mit einem ausdrücklichen Runtime-Abonnement
  werden invalidiert.
- Der Planer liest Befehle und fachliche Werte weiterhin aus demselben
  `RuntimeState`, beobachtet aber nur seinen schmalen Feature-Kanal. Dieser
  Kanal wird durch Produktionsbasis, Plan, Rechenstatus, Rechenfehler,
  Lagerfreigabe und Planer-Konfigurationsbereitschaft invalidiert. Änderungen
  an Public Contracts, Markt, Dashboard, SDE-Installation oder allgemeinem
  Status lösen deshalb keine Neuberechnung des großen Planer-View-Baums aus.
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
- Der Mineralpreisticker des Dashboards baut seine unveränderte doppelte
  Zeilenfolge einmal in einer `NSHostingView` auf. Eine lineare Core Animation
  verschiebt anschließend ausschließlich deren Layer, statt den vollständigen
  SwiftUI-/AppKit-Layoutbaum pro Frame neu zu berechnen. Bei inaktiver App wird
  die Animation entfernt. **Bewegung reduzieren** verwendet weiterhin eine
  statisch horizontal scrollbare einfache Zeilenfolge. Preise, Reihenfolge,
  32-Sekunden-Umlauf, Farben und zugängliche Beschriftungen bleiben gleich.

## Installation und Entwicklung

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
   Trader- und Gebührennachweise festlegen.
8. Bestände und Blueprints prüfen, Schutzbestände setzen und erst danach planen.
9. Für den etablierten, speicherbaren Ablauf im Planner Marktdeckung,
   Produktionszweige, Kostenbestandteile und Warnungen prüfen; Empfehlungen
   bleiben übersteuerbar.
10. Produktion nur nach erneuter Kontrolle im etablierten Planner als
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
- Signierung, Notarisierung, Langzeit-RSS/CPU, vollständige Tastatur- und
  VoiceOver-Prüfung sowie die visuelle Owner-Abnahme bleiben eigenständige
  Freigabeschritte, sofern die Acceptance-Matrix sie nicht ausdrücklich als
  abgeschlossen ausweist.

## Pflege dieser Dokumentation

`PROJECT_STATE.md` ist der aktuelle Status; `PRODUCT.md` beschreibt den vorhandenen Produktumfang. Jede
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
