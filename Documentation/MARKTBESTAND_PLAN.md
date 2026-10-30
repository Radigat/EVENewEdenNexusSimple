# Plan: Marktbestand und Bestandshistorie je Hub

Stand: 30.10.2026 · Status: **P1 bis P8 implementiert und automatisch
geprüft.** Offen sind die Live-Prüfungen und die Eigentümerabnahme nach
Abschnitt I.

Der Eigentümer möchte für den Handel ein echtes Abbild der Märkte am Main,
Home und Coalition Hub. Je Item soll sichtbar sein, wie viel vor Ort gelistet
ist und wie sich dieser Bestand Tag für Tag verändert (Zugang, Abgang, Netto).
Daraus entstehen eine Historie, ein Graph über 30 Tage je Item und eine
Gesamtübersicht. Die bisherige Ableitung aus dem Bedarfsledger ist dem
Eigentümer zu ungenau.

## A. Entscheidungen des Eigentümers (29.10.2026)

| Thema | Entscheidung |
|---|---|
| Hintergrundbetrieb | Die App startet beim Mac-Login unsichtbar mit Menüleisten-Symbol und läuft nach dem Schließen des Fensters weiter. Sie nutzt die vorhandenen Logins. Ist der Mac im Ruhezustand, werden verpasste Abrufe nachgeholt. Kein separater Hintergrunddienst. |
| Takt | Jeder ohnehin laufende Hub-Scan schreibt einen Bestandspunkt, ohne zusätzliche ESI-Last. Zusätzlich gibt es zwei feste Termine täglich, **06:00 und 13:00** (nach der Downtime). Tageswert ist der letzte Stand des Tages. |
| Aufbewahrung | 90 Tage |
| Detailtiefe | Jeder Bestandspunkt bleibt **7 Tage** einzeln erhalten, danach nur ein **Tageswert** (letzter Stand, Tagessummen Zu-/Abgang, Min/Max) bis 90 Tage. Geschätzt 150–300 MB für alle drei Hubs; wird in P2 gemessen. |
| Werte je Item | Sell-Bestand (Stück), Buy-Nachfrage (Stück), Anzahl Sell- und Buy-Orders, bester Sell- und Buy-Preis |
| Delta | Netto-Änderung plus getrennt **Zugang** (neue Orders, Aufstockungen) und **Abgang**. Abgang aufgeteilt in **Teilverkäufe** (noch gelistete Orders mit weniger Stück) und **verschwundene Orders** (verkauft, storniert oder abgelaufen, nicht unterscheidbar). |
| Umfang | Alle Items mit mindestens einer Order am jeweiligen Hub |
| Anzeige | (1) Spalten im Handel, (2) Item-Detail mit Graph, (3) eigene Ansicht „Marktbestand“ |
| Altwert | „Zielhub N T“ aus dem Bedarfsledger wird im Handel **ersetzt**. Der Bedarfsledger bleibt vorerst nur für die Hub-Chancen. |
| Volumen im Handel | Hauptwert sind die **Teilverkäufe** (sicher gehandelt, Untergrenze). Der Tooltip nennt den **Gesamtabgang** inklusive verschwundener Orders als Obergrenze. Das gilt auch für „Gewinnpot. Zielhub N T“. |
| Lückengrenze (P1) | Delta unbekannt ab mehr als 72 Stunden Abstand |
| Tagesgrenze (P2) | UTC-Tag |
| Kurzer Abstand (P2) | Ein Punkt weniger als 30 Minuten nach dem letzten Punkt desselben Hubs wird verworfen; der nächste Vergleich läuft vom älteren Punkt aus |
| Termin nach kurz vorherigem Scan (P3) | Ein Termin entfällt, wenn ein Hub-Scan höchstens 3 Stunden vorher erfolgreich war |
| Pause (P3) | „Main-Hub-Updates pausieren“ pausiert auch die festen Termine |
| Standardwerte (P4) | „Nach dem Schließen im Hintergrund weiterlaufen“ an, „Beim Anmelden starten“ aus |
| Dock-Symbol (P4) | ohne Fenster ausgeblendet, nur Menüleisten-Symbol |
| Menüleisten-Symbol (P4) | nur sichtbar, solange „Weiterlaufen“ an ist |
| Ø Bedarf/Tag (P5) | Teilverkäufe des gewählten Zeitraums je erfasstem Tag |
| Nachfrage heute (P5) | Teilverkäufe des laufenden UTC-Tags |
| Spalten (P5) | Bestand Ziel und Netto Ziel N T immer sichtbar, Bestand Quelle nur in den Details |
| Bestand (P5) | Sell-Stück; Tooltip mit Sell-Orders, Buy-Stück, Buy-Orders und Zeitpunkt |
| Reihenfolge P6/P7 (29.10.2026) | Erst P6, dann P7; „Marktbestand“ steht in der Seitenleiste nach dem Handelslogbuch |
| Dateigröße (P2) | Gemessene Größe so akzeptiert; die echte Größe wird ab P3 protokolliert und nach 7 Tagen Live-Betrieb neu bewertet |
| ESI und Ressourcen | Die ESI-Regeln von CCP werden eingehalten. Die Speicherlast während der Abrufe bleibt möglichst gering (Abschnitt C6 und C7). |

## B. Ist-Stand (geprüft am 29.10.2026)

- Die Hub-Scans laden das vollständige Orderbuch des exakten Hubs (Main als
  NPC-Station, Home und Coalition als Struktur-Markt mit Charakter-Zugang).
  Automatisch laufen sie frühestens alle 6 Stunden
  (`ManufacturingOpportunityAutomaticRefreshPolicy`) und nur bei geöffneter App.
- Gespeichert wird nur der Bedarfsledger
  (`ManufacturingOpportunityDemandLedger`, `market/*-hub-demand.json`). Er
  vergleicht noch gelistete Orders und schätzt daraus eine 24-Stunden-Rate.
  Verschwundene Orders zählen nicht, einen Bestand je Item gibt es nicht.
  Er hält höchstens 30 Tageswerte.
- Das Orderbuch selbst wird nicht gespeichert.
- Für eigene Sidecar-Datenbanken gibt es SQLite-Vorbilder
  (`TradeLogbookStore`, `PublicContractStore`, `ESIResponseDiskCache`).
- Die App hat nur ein `WindowGroup`: kein App-Delegate, kein Login-Item, kein
  Menüleisten-Symbol. Swift Charts wird noch nicht verwendet.

## C. Fachregeln

### C1. Bestandspunkt

Ein Bestandspunkt entsteht aus einem vollständig geladenen Orderbuch eines
Hubs. Er hat Hub-Rolle, exakte Location-ID, Zeitpunkt, Quell-Snapshot und
Auslöser (fester Termin, automatischer Scan, manueller Scan).

Je Item mit mindestens einer Order speichert er:

- Sell-Stück (Summe `volume_remaining`) und Anzahl Sell-Orders,
- Buy-Stück und Anzahl Buy-Orders,
- günstigsten Sell- und höchsten Buy-Preis.

Ein unvollständiges oder fehlgeschlagenes Orderbuch (partial, stale, forbidden,
unavailable) erzeugt **keinen** Punkt. Der Zustand wird mit Grund protokolliert.
Ein Item ohne Order hat im Punkt keine Zeile. Sein Bestand ist dann bekannt 0,
weil das Orderbuch vollständig ist.

### C2. Delta zwischen zwei Punkten

Verglichen wird je Seite (Sell, Buy) auf Order-Ebene mit dem vorigen Punkt
desselben Hubs:

- **Zugang:** Volumen neuer Order-IDs. Steigt das Volumen einer Order, zählt
  der Anstieg ebenfalls; in EVE kommt das praktisch nicht vor.
- **Teilverkauf:** Rückgang des Volumens einer weiter gelisteten Order.
- **Verschwunden:** Restvolumen einer Order, die nicht mehr gelistet ist.
- **Abgang** = Teilverkauf + Verschwunden.
- **Netto** = Bestand neu − Bestand alt = Zugang − Abgang. Die Gleichung wird
  getestet.

Ein Delta ist **unbekannt** (nicht 0), wenn:

- kein vorheriger Punkt existiert,
- sich Hub oder Location geändert haben oder
- der Abstand größer als **72 Stunden** ist (Eigentümerentscheid 29.10.2026).

### C3. Tageswert

Ein Tag ist ein **UTC-Tag** (Eigentümerentscheid 29.10.2026). Der Tageswert
ist der letzte Punkt des Tages. Dazu kommen die Tagessummen von
Zugang, Teilverkauf und Verschwunden aller Deltas mit Ende an diesem Tag
sowie Minimum und Maximum des Sell-Bestands. Ein Tag ohne Punkt ist
**unbekannt** und wird nicht als 0 gezählt; Zeiträume mit Lücken erscheinen in
Warnfarbe, wie heute bei „Zielhub N T“.

- Ein Item, das an einem Tag mit Punkten nicht gelistet ist, hat einen
  bekannten Bestand von 0.
- Erscheint ein Item erst im Laufe des Tages, ist sein Minimum 0.
- Die Tagessummen enthalten nur bekannte Deltas. Ein Tag mit einem
  unbekannten Delta (erster Punkt, Lücke) zählt als nur teilweise erfasst.

### C4. Handelswerte (ersetzt den Bedarfsledger im Handel)

- **Zielhub N T** = Summe der Teilverkäufe (Sell-Seite) der N Tage. Der
  Tooltip nennt den Gesamtabgang (Obergrenze), die erfassten Tage von N und
  die Ø je erfasstem Tag.
- **Gewinnpot. Zielhub N T** nutzt denselben Hauptwert, der Tooltip die
  Obergrenze.
- **Ø Bedarf/Tag** und **Nachfrage heute** rechnen aus derselben Historie.
- „Einziger Markt der Region“ und **Region N T** (ESI-Historie) bleiben
  unverändert.

### C5. Termine und Hintergrund

- **Feste Termine:** 06:00 und 13:00, jeweils der gemeinsame Main-, Home- und
  Coalition-Scan.
- **Nachholen:** Nach Start, Login oder Aufwachen läuft höchstens ein
  verpasster Termin nach. Mehrere verpasste Termine erzeugen keinen Stapel.
- **Andere Scans:** Jeder weitere erfolgreiche Hub-Scan schreibt zusätzlich
  einen Punkt.
- **Termin erfüllt:** Ein Termin gilt als erledigt, wenn ein Hub-Scan
  höchstens 3 Stunden vor ihm oder danach erfolgreich war (Eigentümerentscheid
  29.10.2026).
- **Pause:** „Main-Hub-Updates pausieren“ pausiert auch die Termine.
- **Doppelte Punkte:** Ein Punkt weniger als 30 Minuten nach dem letzten
  Punkt desselben Hubs wird verworfen, ebenso ein nicht neuerer Punkt
  (Eigentümerentscheid 29.10.2026). Der nächste Vergleich läuft vom älteren
  Punkt aus. Umgesetzt im Speicher (P2).
- **Ohne Login:** Fehlt der Zugang zu Home- oder Coalition-Struktur, bleibt
  dieser Hub mit Grund unverfügbar. Der Main Hub läuft trotzdem.
- **Ruhezustand:** Die App weckt den Mac nicht. Ein ruhender Mac verpasst den
  Termin, der Abruf wird nachgeholt.

### C6. ESI-Regeln von CCP

Die Bestandshistorie erzeugt **keine eigenen ESI-Anfragen**. Sie wertet nur
das Orderbuch aus, das der Hub-Scan ohnehin lädt. Alle Abrufe laufen über den
vorhandenen `ESIClient` mit `ESIRequestCoordinator`. Dort gilt heute schon
(ARCHITECTURE.md, ESI-Abschnitt):

- `User-Agent` mit Kontakt und `X-Compatibility-Date` bei jeder Anfrage,
- kein erneuter Abruf vor `Expires`; danach bedingt mit `ETag`/`If-None-Match`
  (304),
- Sperre bei `X-ESI-Error-Limit-Remain` ≤ 20 oder 420 bis zum Reset,
- Rate-Limit-Buckets je `X-Ratelimit-Group` mit Abbremsen und Sperre bei 429
  (`Retry-After`),
- höchstens 6 gleichzeitige Anfragen, davon höchstens 2 automatische;
  Seitenabrufe des Orderbuchs in der vorhandenen Reihenfolge.

Zusätzlich gilt für diese Funktion:

- **Termine nutzen keine Sonderwege.** Feste Termine, Nachholen und der
  Menüleisten-Knopf starten den normalen Hub-Scan als automatische Arbeit.
  Er tritt hinter interaktive Arbeit zurück und bekommt keine eigene
  Parallelität.
- **Kein Scan in der Downtime.** Fällt ein Termin in die tägliche Downtime
  (11:00 UTC) oder meldet der vorhandene ESI-Dienststatus eine Störung, wartet
  der Termin, bis ESI wieder verfügbar ist. Er wird dann einmal ausgeführt.
- **Keine Wiederholungsschleifen.** Ein fehlgeschlagener Termin wird erst beim
  nächsten Termin, Start oder Aufwachen erneut versucht. Ausnahme ist der
  vorhandene, begrenzte GET-Retry.
- **Nur nötige Struktur-Märkte.** Struktur-Märkte werden nur mit vorhandenem
  Zugang abgefragt. Ein 403 wird wie heute gemerkt, damit kein Charakter
  wiederholt Fehler erzeugt.
- **Messbar.** `MeasuringESITransport` und `PerformanceLog` weisen nach, dass
  ein Termin nicht mehr Anfragen erzeugt als ein normaler Hub-Scan
  (Prüfung in P3).
- **Kein Hub-Scan vor `Expires` (Nachtrag 29.10.2026):** Der Live-Lauf am
  29.10.2026 zeigte bei schnell wiederholten manuellen Scans 388 bis 404
  Orderbuch-Seiten, die vor ihrem `Expires` erneut geladen wurden. Ursache:
  Der Scan wirft die Seiten aus dem Zwischenspeicher. Seitdem:
  - Die App liest das späteste `Expires` der regionalen Orderbuch-Seiten
    ohne `type_id` aus `MeasuringESITransport.latestExpiry`.
  - Bis dahin startet kein Hub-Scan: manuelle Knöpfe sind gesperrt, Automatik
    und Termine verschieben sich.
  - Der Menüleisten-Knopf ist zusätzlich gesperrt, solange kein neuer Punkt
    gespeichert würde (unter 30 Minuten nach dem letzten Punkt jedes Hubs).

### C7. Ressourcen während des Abrufs

Ziel ist eine möglichst geringe Speicherlast, sowohl im Arbeitsspeicher
während des Abrufs als auch beim Schreiben auf die Festplatte:

- **Ein Durchlauf, keine Kopie.** Der Bestandspunkt entsteht in einem einzigen
  Durchlauf über das schon auf den exakten Hub gefilterte Orderbuch.
  Gespeichert werden nur Summen je Item und eine kompakte Order-Baseline
  (Order-ID, Item, Seite, Volumen als feste Ganzzahlen). Das vollständige
  Orderbuch wird weder kopiert noch gespeichert.
- **Freigabe vor dem Schreiben.** Nach der Berechnung werden keine Orderdaten
  mehr festgehalten. Geschrieben wird in einem Hintergrund-Task, nicht auf dem
  Main Actor.
- **Kleine Pakete.** SQLite schreibt in einer Transaktion mit vorbereiteten
  Statements in Paketen (zum Beispiel 1.000 Zeilen), ohne große
  Zwischen-Arrays.
- **Delta direkt aus der Datenbank.** Die vorige Baseline wird zum Vergleich
  aus SQLite gelesen und nicht dauerhaft im Speicher gehalten.
- **Verdichtung getrennt.** Verdichtung und Löschung laufen nach dem Schreiben,
  höchstens einmal je Tag und paketweise.
- **Sparsame Abfragen.** Abfragen der Ansichten lesen nur die nötigen
  Zeilen. Die 30-Tage-Graphen und Summen kommen aus den Tageswerten, nicht
  aus allen Einzelpunkten.
- **Messung.** Zusätzlicher Spitzenspeicher und Dauer von Berechnung und
  Schreiben werden je Hub in `PerformanceLog` gemessen (P1 bis P3).
  Vorschlag für den Zielwert: höchstens 50 MB zusätzlich zum heutigen Scan
  und unter 5 Sekunden Schreibdauer für den Main Hub. Liegt ein Messwert
  darüber, wird vor dem Weitermachen nachgefragt.
- **Gemessen in P1 (synthetisch, Debug-Build):**
  - Testfall: 180.000 Orders (15.000 Items × 12) in zwei Orderbüchern.
  - Laufzeit: Beide Auswertungen und der Vergleich brauchen zusammen 0,42 bis
    0,47 s.
  - Arbeitsspeicher je Auswertung: rechnerisch 14,4 MB (gesammelte Orders,
    Preise, Sortierreihenfolge, sortierte Baseline). Hinzu kommen die
    Summen je Item.
  - Baseline: 5,8 MB.
  - Der tatsächliche Prozess-Spitzenspeicher wird im echten Scan in P3
    gemessen.
- **Gemessen in P2 (synthetisch, Debug-Build):**
  - Testfall: drei Hubs in Jita-Größe; jedes Item ändert sich bei jedem
    Punkt (ungünstigster Fall), 501 Punkte.
  - Schreibdauer je Punkt: Mittel 0,20 s, höchstens 0,23 s.
  - Spitzenspeicher: 53 MB Zuwachs, davon 42 MB für die künstlichen
    Testmärkte; dem Speicher zuzurechnen sind etwa 11 MB.
- **Live-Lauf 29.10.2026, 21:20–21:31 (sechs Scans, alle Punkte wegen
  30-Minuten-Abstand verworfen):**
  - Größe: Main 18.990 Items und 326.796 Orders, Home 4.645 und 18.857,
    Coalition 7.832 und 52.295.
  - Auswertung: Main 0,41–0,57 s, Home und Coalition 0,02–0,16 s.
  - Speicher: Die Erfassung hebt den Footprint um etwa 5–7 MB; die App liegt
    insgesamt bei 0,8–1 GB.
  - Datei: 12,6 MB.
  - Offen: die Schreibdauer eines echten, gespeicherten Punkts.
- **P3 (implementiert):** Jede Erfassung schreibt das
  Ereignis `market-stock` in `PerformanceLog`:
  - Hub und Auslöser, Ergebnis,
  - Items und Orders,
  - Dauer von Auswertung, Speichern und Verdichtung,
  - Speicher-Footprint vorher und nachher, Lebensdauer-Spitze,
  - Dateigröße.

  Der Scan-Abschluss `main-hub-scan` nennt den Auslöser und die ESI-Zählung.
  Ein Termin ruft denselben Scan auf wie die 6-Stunden-Automatik, daher
  erzeugt er dieselben Anfragen. Der Live-Nachweis aus dem Protokoll steht
  aus:
  `log stream --predicate 'subsystem == "com.local.EVENexusSimple" AND category == "performance"'`.
- **Bedarfsledger.** Der heutige Ledger hält eine eigene Order-Baseline als
  JSON. Ob er später auf die neue Baseline umgestellt werden kann, damit nicht
  zwei Baselines entstehen, wird nach P5 mit dem Eigentümer geklärt.

## D. Speicher

Gespeichert wird in einer eigenen SQLite-Datei
`market/market-stock-history.sqlite` im Application-Support-Ordner, im
WAL-Modus. Es gibt keine SwiftData-Schemaänderung.

| Tabelle | Inhalt | Aufbewahrung |
|---|---|---|
| `stock_series` | Hub-Rolle, Region und exakte Location; ein neuer Ort bekommt eine eigene Reihe | dauerhaft |
| `stock_points` | Punkt-Kopf (Reihe, Zeit, UTC-Tag, Quelle, Auslöser, Delta-Status) | 7 Tage |
| `stock_point_values` | Werte und Deltas je Punkt und Item (Deltas `NULL`, wenn unbekannt) | 7 Tage |
| `stock_daily_values` | Tageswert je Reihe, Tag und Item, mit jedem Punkt fortgeschrieben | 90 Tage |
| `stock_days` | je Reihe und Tag: Anzahl Punkte, bekannte und unbekannte Deltas | 90 Tage |
| `stock_baselines` | letzte Orderliste je Reihe als Binärblock (25 Byte je Order) | nur jüngster Stand |
| `stock_meta` | Tag der letzten Verdichtung; Schemaversion über `PRAGMA user_version` | – |

Umsetzung: `MarketStockHistoryStore` (`Sources/EVENexusCore/Market/MarketStockHistoryStore.swift`).

- Ein Punkt wird mit Werten, Tageswerten, Tageszähler und neuer Baseline in
  **einer** Transaktion geschrieben. Die vorbereiteten Statements werden je
  Zeile wiederverwendet.
- Verdichtung (`compactIfDue`) läuft höchstens einmal je UTC-Tag, getrennt vom
  Schreiben, mit einer kleinen Transaktion je Punkt bzw. Tag.
- Gelöschte Seiten werden wiederverwendet; die Datei schrumpft nicht von
  selbst.
- **Sicherung:** Die vorhandene Sicherung nimmt jede SQLite-Datei des
  Datenordners über die Online-Backup-API auf, auch bei offenem WAL. Ein Test
  weist das für diese Datei nach; die Wiederherstellung ersetzt den ganzen
  Datenordner.
- Testdaten sind synthetisch, keine produktiven Benutzerdaten.

**Gemessene Größe (P2, synthetisch, ungünstigster Fall: 3 Hubs in Jita-Größe,
jedes Item ändert sich bei jedem Punkt, tägliche Verdichtung):**

| Zeitraum | Datei | Anteile |
|---|---|---|
| 7 Tage mit 6 Punkten/Tag | 151 MB | – |
| 90 Tage (Dauerzustand) | 423 MB | Tageswerte 292 MB (4,05 Mio. Zeilen, ca. 72 Byte), Einzelpunkte 114 MB (1,9 Mio. Zeilen, ca. 60 Byte), Baselines 14 MB |

Realistische Schätzung: etwa 180 MB nach 90 Tagen. Grundlage ist der Main Hub
in Jita-Größe; Home und Coalition haben laut den vorhandenen
Bedarfsledger-Dateien etwa 8 % bzw. 19 % der Orders des Main Hubs. Die
Abnahme steht aus: Der Eigentümer hat die Größe am 29.10.2026 akzeptiert,
die echte Größe wird ab P3 protokolliert und nach 7 Tagen Live-Betrieb neu
bewertet.

Messung wiederholen mit:
`MARKET_STOCK_MEASURE=1 swift test --filter measureNinetyDays`.

## E. Anzeige

1. **Handel:**
   - neue Spalten **Bestand Quelle** und **Bestand Ziel** (Sell-Stück jetzt)
     sowie **Netto Ziel N T**,
   - „Zielhub N T“ nach C4,
   - alle Spalten sortierbar, unbekannt bleibt „—“.
2. **Item-Detail:**
   - Klick auf ein Item (eigenes Symbol, getrennt vom Kopier-Klick) öffnet
     einen Verlauf über 30 Tage.
   - Graph mit Swift Charts für Main, Home und Coalition. Umschaltbar sind
     Sell-Bestand, Buy-Nachfrage und Preis.
   - Lücken werden als Lücke gezeichnet, nicht als 0.
   - Darunter eine Tagestabelle mit Datum, Bestand, Zugang, Teilverkauf,
     Verschwunden und Netto, positiv grün und negativ rot.
3. **Ansicht „Marktbestand“:**
   - eigener Seitenleisten-Eintrag mit Hub-Auswahl,
   - alle Items des Hubs mit Bestand, Orders, Preisen, Netto und Abgang
     1/7/30 T,
   - Suche und Marktgruppen-Filter,
   - Klick öffnet das Item-Detail.
4. **Seitenleiste „Automatische Daten“:** Zeile **Marktbestand** mit letztem
   Punkt je Hub und nächstem festem Termin.
5. **Einstellungen** (umgesetzt in P4 unter Daten & Einstellungen →
   Allgemein → Hintergrundbetrieb; Ablauf beim Login-Start: verborgenes
   Fenster bis zum Ende des Startablaufs, danach geschlossen, weil der
   Startablauf an der Hauptansicht hängt):
   - Schalter „Beim Anmelden starten“ und „Nach Schließen im Hintergrund
     weiterlaufen“,
   - Anzeige des Login-Item-Status (zum Beispiel „Freigabe in den
     Systemeinstellungen nötig“).

## F. Checkliste

- [x] P1 Core: Bestandspunkt und Order-Delta (29.10.2026, `MarketStockHistoryCalculator`)
- [x] P2 SQLite-Speicher, Verdichtung, Aufbewahrung, Größenmessung (29.10.2026, `MarketStockHistoryStore`)
- [x] P3 Erfassung bei jedem Hub-Scan, feste Termine 06:00/13:00, Nachholen, Status (29.10.2026; Live-Messung offen)
- [x] P4 Hintergrundbetrieb: Login-Item, Weiterlaufen, Menüleiste (29.10.2026; Login-Start, Ruhezustand und Fensterverhalten live offen)
- [x] P5 Handel: Spalten und Ersatz von „Zielhub N T“ (29.10.2026; mit echten Daten live offen)
- [x] P6 Item-Detail mit Graph und Tagestabelle (29.10.2026; mit echten Daten live offen)
- [x] P7 Ansicht „Marktbestand“ (29.10.2026; mit echten Daten live offen)
- [x] P8 Abschluss: Doku, Acceptance, Owner-Testleitfaden (30.10.2026)
- [ ] Live-Prüfung (Login-Start, Ruhezustand, echte Struktur-Märkte, Speichergröße nach 7 Tagen)
- [ ] Eigentümerabnahme

## G. Reihenfolge

```
P1 Core ──► P2 Speicher ──► P3 Erfassung/Takt ──► P5 Handel-Spalten
                                     │                 └─► P6 Item-Detail ──► P7 Marktbestand
                                     └─► P4 Hintergrundbetrieb
P5 + P6 + P7 + P4 ──► P8 Abschluss
```

Feste Reihenfolge: P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → Ende.

Für jeden Schritt gilt:

- kleiner Diff mit eigenen Tests,
- Prüfung mit SwiftPM und Xcode-Debug,
- PRODUCT.md und dev-diary.md im selben Schritt.

Commits gibt es nur auf ausdrücklichen Auftrag.

## H. Prompts (einzeln kopierbar)

### Gemeinsamer Vorspann (jedem Prompt voranstellen)

> Arbeite nach AGENTS.md/CLAUDE.md. Lies vorher `git status --short --branch`
> und den vorhandenen Diff; fremde Änderungen bleiben erhalten. Maßgeblich ist
> `Documentation/MARKTBESTAND_PLAN.md`. Ändere bestehende Rechenregeln nur, wenn
> der Prompt es ausdrücklich sagt. Fehlende Daten bleiben ausdrücklich
> unverfügbar und werden nie zu 0. EVE-Namen sind über `EVEEntityText`
> kopierbar, Tabellen über den gemeinsamen Header sortierbar. ESI-Abrufe nur
> über den vorhandenen `ESIClient` und `ESIRequestCoordinator` nach Abschnitt
> C6; keine eigenen Anfragen, keine eigenen Retry- oder Parallelitätswege.
> Speicherlast nach Abschnitt C7 gering halten und messen. Keine produktiven
> Benutzerdaten als Testdaten. Pflege PRODUCT.md und dev-diary.md im selben
> Schritt. Prüfe mit `swift test` und `xcodebuild … test` (Debug). Bei
> Unsicherheiten oder Unklarheiten nachfragen, statt selbst zu entscheiden.
> Danach stoppen und berichten; geplant, implementiert, automatisch geprüft und
> live geprüft getrennt ausweisen. Kein Commit. Hake den erledigten Punkt in
> Abschnitt F ab und gib am Ende den nächsten Prompt laut Abschnitt G
> vollständig und kopierfertig aus, einschließlich dieses Vorspanns.

### P1 – Core: Bestandspunkt und Order-Delta

> Implementiere in `EVENexusCore` (neue Datei unter `Sources/EVENexusCore/Market/`,
> im Xcode-Projekt eintragen) einen reinen Rechenkern nach Abschnitt C1 und C2:
>
> - `MarketStockPoint` aus einem vollständigen `MarketOrderSnapshot` (je Item:
>   Sell-/Buy-Stück, Anzahl Orders, bester Preis);
> - `MarketStockOrderBaseline` (kompakte Orderliste);
> - den Vergleich zweier Punkte je Seite mit Zugang, Teilverkauf, Verschwunden,
>   Abgang und Netto.
>
> Ein unvollständiges Orderbuch erzeugt keinen Punkt. Ein unbekanntes Delta
> bleibt `nil`. Kläre vorher die Lückengrenze (Vorschlag 36 Stunden).
>
> Rechne nach C7 in einem Durchlauf ohne Kopie des Orderbuchs. Die Baseline
> besteht nur aus festen Ganzzahlen.
>
> Tests: Netto = Zugang − Abgang, neue/verschwundene/teilverkaufte Orders,
> Ortswechsel, zu große Lücke, Item verschwindet ganz (bekannt 0). Dazu ein
> synthetisches Orderbuch in Jita-Größe mit Messung von Laufzeit und
> zusätzlichem Spitzenspeicher. Noch kein Speicher, keine UI, keine
> ESI-Anfrage.

→ Nächster Prompt: P2

### P2 – SQLite-Speicher mit Verdichtung

> Implementiere `MarketStockHistoryStore` als Sidecar-SQLite nach Abschnitt D,
> nach dem Vorbild von `TradeLogbookStore`:
>
> - Schreiben eines Punkts samt Baseline in einer Transaktion,
> - Tageswerte nach C3,
> - Verdichtung der Einzelpunkte nach 7 Tagen, Löschen nach 90 Tagen,
> - Abfragen je Hub und Item (Zeitreihe 30 Tage, Einzelpunkte 7 Tage) und je
>   Hub für alle Items (letzter Stand, Summen 1/7/30 T).
>
> Schreibe nach C7: eine Transaktion, vorbereitete Statements, Pakete, vorige
> Baseline aus SQLite gelesen statt im Speicher gehalten, Verdichtung getrennt
> und paketweise.
>
> Nimm die Datei in Sicherung und Wiederherstellung der Sidecar-Datenbanken auf.
> Miss mit synthetischen Daten in Größe eines Jita-Orderbuchs (etwa 15.000
> Items, 6 Punkte/Tag, 3 Hubs) für 7 und 90 Tage:
>
> - Dateigröße,
> - Schreibdauer je Punkt,
> - zusätzlichen Spitzenspeicher.
>
> Trage die Werte in Abschnitt D ein. Liegt die Größe deutlich über 300 MB
> oder ein Wert über dem Zielwert aus C7, nachfragen, bevor du weitermachst.

→ Nächster Prompt: P3

### P3 – Erfassung, feste Termine und Status

> Schreibe nach jedem erfolgreichen Main-, Home- und Coalition-Scan in
> `RuntimeState` einen Punkt in den `MarketStockHistoryStore`, ohne den
> Bedarfsledger zu verändern. Füge einen Terminplaner nach C5 hinzu:
>
> - 06:00 und 13:00 Ortszeit starten den gemeinsamen Hub-Scan,
> - verpasste Termine nach Start, Login oder Aufwachen höchstens einmal
>   nachholen (`NSWorkspace.didWakeNotification`),
> - während des Scans App Nap verhindern (`ProcessInfo.beginActivity`).
>
> Bestehende Grenzen bleiben: Transportlimits, Planner-Vorrang,
> 6-Stunden-Regel, Recovery-Modus startet nichts. Termine laufen nach C6 als
> automatische Arbeit über den normalen Scan, warten Downtime und
> ESI-Störungen ab und wiederholen sich nicht in Schleifen. UTC-Tag und das
> Verwerfen von Punkten unter 30 Minuten Abstand sind entschieden und im
> Speicher umgesetzt. Rufe nach dem Schreiben `compactIfDue` auf und
> protokolliere die Dateigröße der Bestandsdatenbank in `PerformanceLog`.
>
> Zeige in „Automatische Daten“ die Zeile **Marktbestand**. Tests für
> Terminberechnung, Nachholen ohne Stapel, Downtime-Wartezeit und
> Deduplizierung. Weise mit `MeasuringESITransport` und `PerformanceLog` nach,
> dass ein Termin nicht mehr Anfragen erzeugt als ein normaler Hub-Scan.
> Miss je Hub zusätzlichen Spitzenspeicher und Schreibdauer nach C7.

→ Nächster Prompt: P4

### P4 – Hintergrundbetrieb

> Ergänze einen App-Delegate. Die App läuft nach dem Schließen des letzten
> Fensters weiter, wenn der Schalter an ist, und bekommt ein
> Menüleisten-Symbol (`MenuBarExtra`) mit:
>
> - Fenster öffnen,
> - „Marktbestand jetzt abrufen“,
> - letzter und nächster Abruf,
> - Beenden.
>
> Registriere die App über `SMAppService.mainApp` als Login-Item. Beim
> Login-Start öffnet sie kein Fenster. Zeige den Status in den Einstellungen,
> auch wenn eine Freigabe in den Systemeinstellungen nötig ist.
>
> Ohne Fenster laufen keine zusätzlichen Abrufe. Es gelten nur die Termine aus
> P3, der normale 6-Stunden-Scan und der Menüleisten-Knopf, alle über
> denselben Scan nach C6. Ohne Fenster werden keine Ansichtsdaten im Speicher
> gehalten.
>
> Bundle-ID, Keychain-Dienste und Datenbankpfade bleiben unverändert. Login-Start
> und Ruhezustand sind Live-Prüfungen und als offen auszuweisen.

→ Nächster Prompt: P5

### P5 – Handel: Bestandsspalten und Ersatz von „Zielhub N T“

> Stelle im Handel „Zielhub N T“, „Gewinnpot. Zielhub N T“, „Ø Bedarf/Tag“ und
> „Nachfrage heute“ nach C4 auf die Bestandshistorie um: Hauptwert
> Teilverkäufe, Tooltip mit Gesamtabgang und erfassten Tagen.
>
> Füge die Spalten **Bestand Quelle**, **Bestand Ziel** und **Netto Ziel N T**
> hinzu. Alle Spalten sind sortierbar nach dem typisierten Wert, unbekannte
> Werte stehen am Ende.
>
> „Einziger Markt der Region“ und Region N T bleiben unverändert. Aktualisiere
> `Documentation/HANDEL_PLAN.md` (Abschnitte L bis O). Die Hub-Chancen behalten
> den Bedarfsledger.

→ Nächster Prompt: P6

### P6 – Item-Detail mit Graph

> Füge im Handel ein eigenes Verlaufssymbol je Item hinzu, getrennt vom
> Kopier-Klick und vom Logbuch-Plus. Es öffnet ein Item-Detail nach Abschnitt
> E2:
>
> - Swift-Charts-Graph über 30 Tage für Main, Home und Coalition,
> - umschaltbar zwischen Sell-Bestand, Buy-Nachfrage und Preis,
> - Lücken als Lücke,
> - Einzelpunkte der letzten 7 Tage, ältere Tage als Tageswert,
> - sortierbare Tagestabelle mit Datum, Bestand, Zugang, Teilverkauf,
>   Verschwunden und Netto (positiv grün, negativ rot).
>
> Der Itemname ist kopierbar.

→ Nächster Prompt: P7

### P7 – Ansicht „Marktbestand“

> Füge den Seitenleisten-Eintrag **Marktbestand** hinzu. Kläre vorher die
> Position in der Seitenleiste.
>
> Die Ansicht hat eine Hub-Auswahl (Main/Home/Coalition) und eine Tabelle
> aller Items des letzten Punkts mit:
>
> - Sell-/Buy-Bestand, Anzahl Orders, beste Preise,
> - Netto und Abgang 1/7/30 T,
> - Zeitpunkt des letzten Punkts.
>
> Dazu kommen Suche und ein Marktgruppen-Filter. Ein Klick auf das
> Verlaufssymbol öffnet das Item-Detail aus P6. Die Tabelle ist nativ
> sortierbar, die gewählte Sortierung bleibt bei Aktualisierungen erhalten.

→ Nächster Prompt: P8

### P8 – Abschluss

> Aktualisiere PRODUCT.md, ARCHITECTURE.md, ROADMAP.md,
> `Documentation/ACCEPTANCE.md` und diesen Plan (Status, Checkliste, gemessene
> Speichergröße). Ergänze hier einen Owner-Testleitfaden:
>
> - Login-Start,
> - Fenster schließen,
> - Ruhezustand über 06:00,
> - Struktur-Märkte ohne Zugang,
> - Graph und Tabelle eines bekannten Items über mehrere Tage,
> - Speichergröße nach 7 Tagen.
>
> Keine Codeänderung außer kleinen Korrekturen aus der Prüfung.

→ Ende. Danach nur ein Abschlussbericht mit den offenen Live- und
Owner-Abnahmen.

## I. Owner-Testleitfaden

Voraussetzung: die aktuelle Version gebaut und gestartet. Mitlesen im
Terminal:

`log stream --predicate 'subsystem == "com.local.EVENexusSimple" AND category == "performance" AND (eventMessage CONTAINS "market-stock" OR eventMessage CONTAINS "main-hub-scan")'`

1. **Erster gespeicherter Punkt:** Mehr als 30 Minuten nach dem letzten
   Punkt einen Hub-Scan auslösen (Handel → „Hub-Märkte aktualisieren“).
   - Erwartung: drei Zeilen `market-stock … outcome=recorded…` (Main, Home,
     Coalition), `record=` unter 5 s.
   - Die Zeile `main-hub-scan total` zeigt `early=0`.
   - In „Automatische Daten“ zeigt die Zeile **Marktbestand** den neuen
     Stand.
2. **ESI-Sperre:** Direkt danach erneut „Hub-Märkte aktualisieren“ versuchen.
   - Erwartung: Der Knopf ist gesperrt, der Tooltip nennt „ab HH:MM:SS“.
   - Nach Ablauf wird er von selbst wieder frei.
3. **Login-Start:** Unter Daten & Einstellungen → Allgemein →
   Hintergrundbetrieb „Beim Anmelden starten“ einschalten; falls macOS
   fragt, unter Systemeinstellungen → Anmeldeobjekte freigeben. Ab- und
   wieder anmelden.
   - Erwartung: kein Fenster und kein Dock-Symbol, nur das
     Menüleisten-Symbol.
   - Im Protokoll erscheint `startup.finished`.
4. **Fenster schließen:** Das Fenster schließen.
   - Erwartung: Die App läuft mit Menüleisten-Symbol weiter, das
     Dock-Symbol verschwindet.
   - „Fenster öffnen“ im Menü bringt Fenster und Dock-Symbol zurück.
5. **Ruhezustand über 06:00:** Den Mac vor 06:00 in den Ruhezustand
   versetzen und danach wecken.
   - Erwartung: Der verpasste Termin läuft einmal nach (`trigger=scheduled`),
     nicht mehrfach.
6. **Struktur-Märkte ohne Zugang:** Einen Charakter ohne Strukturzugang
   allein lassen oder die Berechtigung entziehen.
   - Erwartung: Home oder Coalition bleibt mit Grund unverfügbar.
   - Main schreibt weiter Punkte.
   - Keine Wiederholungsschleife im Protokoll.
7. **Handel:** Nach mindestens zwei gespeicherten Punkten eine Marktgruppe
   öffnen.
   - Erwartung: „Zielhub N T“, „Bestand Ziel“ und „Netto Ziel N T“ zeigen
     Werte.
   - Unvollständige Zeiträume stehen in Warnfarbe.
   - Tooltips nennen Obergrenze und erfasste Tage.
8. **Item-Verlauf über mehrere Tage:** Für ein bekanntes Item (zum Beispiel
   eines, das du selbst handelst) das Verlaufssymbol öffnen.
   - Erwartung: Graph mit Punkten je Hub, Lücken an Tagen ohne Punkt.
   - Die Tagestabelle lässt sich sortieren; Netto ist grün oder rot.
9. **Ansicht Marktbestand:** Hub wechseln, suchen, Marktgruppe filtern und
   nach „Abgang 7 T“ sortieren.
   - Erwartung: flüssige Darstellung auch mit rund 19.000 Main-Items.
   - Die Sortierung bleibt nach dem nächsten Scan erhalten.
10. **Speichergröße nach 7 Tagen:** Den Wert `fileBytes=` im Protokoll oder
    die Größe von `market/market-stock-history.sqlite` notieren.
    - Erwartung (Schätzung): deutlich unter 300 MB.
    - Liegt sie darüber, gibt es drei Optionen zum Nachsteuern: nur
      geänderte Tage speichern, Spalten verschlanken oder Tageswerte kürzer
      aufbewahren.

