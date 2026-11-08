# Dashboard nach Board „Main.dc.html“ – Übernahmeplan (07.11.2026)

Status: **DB1 bis DB7 erledigt** (07./08.11.2026, nicht committet). DB7 hat
die Befunde B1–B10 der Durchsicht DB6 behoben (Abschnitt 7.4). Offen ist die
Eigentümerabnahme nach Abschnitt 7; DB8 nur bei Befunden daraus. Umsetzung nur
auf ausdrücklichen Auftrag, je Schritt ein Prompt aus Abschnitt 6.

## 1. Ziel und Entscheidungen des Eigentümers (07.11.2026)

- Das Dashboard-Board `Main.dc.html` aus dem Claude-Design-Canvas wird die
  grundlegende Anordnung des App-Dashboards. Alle heutigen Dashboard-Funktionen
  bleiben erhalten. Das ersetzt Nr. 1 der D3-Entscheidung („Anordnung des Boards
  wird nicht übernommen“) in
  [DECISIONS.md](Consolidation/DECISIONS.md).
- **Stil:** Die Anordnung gilt in „Klassisch“ und „New Eden HUD“. Eckwinkel,
  Raster, Rauten und Bereichszeile erscheinen wie bisher nur im HUD (entspricht
  dem Board-Schalter „hudAccents“). „Klassisch“ bleibt Standard.
- **App-Panels, die das Board nicht zeigt,** kommen ins Board-Raster:
  - „Bereit zur Auslieferung“ und „Nächste 48 Stunden“ werden die eine
    Board-Liste „Industriejobs · bereit und bevorstehend“: erst alle bereiten
    Jobs nach Endzeit, dann laufende Jobs mit Ende in 48 Stunden nach Endzeit,
    Gleichstand nach Jobidentität. Rechts „Bereit“ (grün, Haken) bzw.
    Restzeit (Uhr). Fünf Zeilen plus „Alle anzeigen“, Zeileninhalt wie heute
    (Bauplanname und Charakter, beide kopierbar).
  - Die Kapazität je Aktivität ist seit DB4 aufklappbar unter der
    Kennzahlenreihe (gespeichert, anfangs zu; Gesamtzeile „X von Y …
    aktiv“ im Kopf). Bereite, nicht ausgelieferte Jobs belegen in den
    Slot-Karten einen Slot; der Info-Knopf der Nettowert-Karte zeigt die
    Bewertungsdetails als Popover. Vor DB4 stand das Panel „Industriekapazität“ über dem
    Raster.
  - Übrige Panels darunter, Reihenfolge „Industrie zuerst“ (Abschnitt 4).
- **Titel und Texte:** Board-Panels tragen die Board-Titel, der Untertitel
  kommt aus dem Board. Übrige Panels und alle Hinweistexte behalten die
  App-Texte. Die Abschnittsüberschriften „Industrie & Jobs“, „Finanzen“ und
  „Markt & Chancen“ entfallen wie im Board.
- **Neue Funktionen aus dem Board** (nur echte Daten, fehlende Werte bleiben
  „Nicht verfügbar“):
  1. Kennzahlenreihe: Nettowert mit Veränderung im Zeitraum, Wallet mit
     Quellzustand, Fertigungsslots, gemeinsame Science-Slots mit Reaktionen.
  2. Seitenkopf mit ESI-Status und „Alles aktualisieren“. Der Status fasst
     Charakter-Sync, Wallets, Nettowert-Bewertung sowie Moon-, Mineralien- und
     Reaktionsanalyse zusammen. Der Knopf tut das heutige „Dashboard
     aktualisieren“ und aktualisiert danach diese drei Analysen. Er ersetzt den
     heutigen Knopf im Wallet-Panel. Festlegungen aus DB5: Die Statuszeit ist
     die der ältesten Quelle; ein Klick zeigt die sechs Quellen im Popover.
     Erfolgs- und Fehlermeldungen stehen unter dem Seitenkopf. Die drei
     Analysen laufen nach Charakter-Sync und Bewertung gleichzeitig.
  3. Main-Hub-Chancen · Top 5: letzter Main-Hub-Scan, gespeicherte Filter der
     Chancen-Ansicht, Rang nach ROI absteigend mit derselben Kostenrechnung wie
     die Ansicht. Zeilen ohne ROI fallen heraus. Spalten Produkt, ROI, Gewinn.
     „Alle Chancen“ öffnet die Main-Hub-Chancen.
     Festlegungen aus DB2: Das Dashboard rechnet selbst mit den gemeinsamen
     Funktionen der Ansicht; in der Ansicht nur für die Sitzung geänderte
     Runs/ME/TE je Zeile gelten dort nicht. „Gewinn“ ist die Spalte „Gewinn“
     der Ansicht (Grundlage des ROI). Unter dem Titel stehen Hub und
     „Aktualisiert …“. Leerzustände „Noch kein Main-Hub-Scan“ und „Keine
     Chance passt zu den Filtern der Main-Hub-Chancen.“; keine eigene
     Veraltet-Regel.
  4. Nettowert-Zeitraum 7 T / 30 T / 90 T / Alle wie in der Nettowert-Ansicht,
     Start 30 T, gilt für die Sitzung. Veränderung = letzter minus erster
     bekannter Gesamtwert im Zeitraum, in ISK und Prozent; ohne zwei Werte
     „Nicht verfügbar“. Serienwahl und Liniendiagramm bleiben. Festlegungen
     aus DB3: Die Verlaufslinien je Charakter folgen dem Zeitraum. Ist der
     erste oder letzte verglichene Stand unvollständig, wird gerechnet und
     „aus bekannten Bestandteilen“ angezeigt. Die Veränderung steht dauerhaft
     im Panel (ab DB4 zusätzlich in der Kennzahl). Die Stufen heißen deutsch
     „7 T“, „30 T“, „90 T“, „Alle“, auch in der Nettowert-Ansicht.
- Die Boards enthalten erfundene Beispieldaten. Übernommen werden Anordnung,
  Gestaltung und die oben genannten Funktionen, keine Werte.
- Nicht Teil dieses Plans: Seitenleiste mit „Automatische Daten“,
  Vertragsimport und Logo (bleibt wie nach D2), andere Ansichten.

## 2. Ausgangslage im Code

- `DashboardView` in `Sources/EVENexusSimpleApp/ContentView.swift`. Vor DB1
  gliederte es sich in drei Abschnitte: Industrie & Jobs (Kapazität, Bereit,
  48 Stunden, Top 5 nach Materialwert), Finanzen (Wallet, Nettowert im Verlauf),
  Markt & Chancen (Mineralpreise, negative Reaktionen, Moon-Kauf,
  Mineralien-Kauf).
- `DashboardCardLayout` setzt Panels nebeneinander und stapelt sie, wenn ihre
  Mindestbreiten nicht passen.
- Die HUD-Bausteine (`Panel`, `NexusPanelTitle`, `nexusPanelSurface`,
  `nexusPageTitle`, `hudCornerBrackets`) stammen aus D1–D8,
  [DESIGN_HUD_2026-11-07.md](DESIGN_HUD_2026-11-07.md).
- Die Nettowert-Ansicht hat bereits `NetWorthHistoryRange` (7/30/90/Alle) und
  die Zeitraumfilterung (`NetWorthView.swift`, privat).
- Main-Hub-Scan: `RuntimeState.manufacturingOpportunityAnalysis`; Filter der
  Chancen-Ansicht liegen in `@AppStorage` (`MarketBrowserView.swift`), ROI aus
  `ManufacturingOpportunityCostProjection`.

## 3. Vorlage

- Canvas: <https://claude.ai/artifact/FFhRGs1XigHzKytEpGaXEB>, Board
  `project/Main.dc.html`.
- Design-System „New Eden Nexus“:
  <https://claude.ai/code/artifact/3e494757-38fc-4fa1-81d6-44415095315e>.

## 4. Zielbild

```
Kopf      ◆ ÜBERSICHT (nur HUD) · Dashboard · Untertitel   │ ESI-Status · Alles aktualisieren (DB5)
Kennzahlen  Nettowert │ Wallet │ Fertigungsslots │ Gemeinsame Science-Slots      (DB4)
            ▸ Kapazität je Aktivität (aufklappbar)                                (DB4)
Raster    Z1  Industriejobs · bereit und bevorstehend │ Wallets
          Z2  Nettowert · Verlauf                     │ Main-Hub-Chancen · Top 5  (DB2)
          Z3  Top 5 nach Materialwert                 │ Reaktionen mit negativer Wertschöpfung
          Z4  Mineralpreise (volle Breite)
          Z5  Moon-Kaufanalyse                        │ Mineralien-Kaufanalyse
```

- Zwei Spalten; unter 2 × 360 pt Mindestbreite stehen die Panels untereinander.
  Panels einer Zeile sind gleich hoch (wie das CSS-Raster des Boards).
- Zeilen in Listen trennt eine feine Linie wie im Board; Aktivitätssymbol in
  einer kleinen Kachel.
- Wallets nach Board: drei Kacheln „Summe verfügbar“, „Charaktere“
  (einbezogen von gesamt), „Quellzustand“, darunter aufklappbar „Charaktere“
  mit Einzelbeträgen, Zeit und Aktualisieren je Charakter.

## 5. Reihenfolge

| Prompt | Inhalt | Status |
|---|---|---|
| DB1 | Grundgerüst: Board-Raster, Board-Titel, zusammengeführte Jobliste, Wallets nach Board, übrige Panels darunter | erledigt |
| DB2 | Panel „Main-Hub-Chancen · Top 5“ | erledigt |
| DB3 | Nettowert-Zeitraum 7/30/90/Alle und Veränderung im Zeitraum | erledigt |
| DB4 | Kennzahlenreihe, Kapazität je Aktivität aufklappbar | erledigt |
| DB5 | Seitenkopf mit ESI-Status und „Alles aktualisieren“ | erledigt |
| DB6 | Gesamtdurchsicht beider Stile, Abnahme-Checkliste | erledigt |
| DB7 | Nur bei Befunden aus der Abnahme: Nacharbeiten | erledigt (B1–B10, 08.11.2026) |
| DB8 | Nur bei Befunden aus der Eigentümerabnahme: Nacharbeiten | bei Bedarf |

## 6. Prompts (einzeln kopierbar)

### Gemeinsamer Vorspann (jedem Prompt voranstellen)

> Arbeite nach AGENTS.md/CLAUDE.md. Lies vorher `git status --short --branch`
> und den vorhandenen Diff; fremde Änderungen bleiben erhalten, stage nur
> eigene Pfade. Maßgeblich ist `Documentation/DASHBOARD_BOARD_2026-11-07.md`.
> Vorlage ist das Board `project/Main.dc.html` im Canvas
> <https://claude.ai/artifact/FFhRGs1XigHzKytEpGaXEB>. Die Inhalte des Boards
> sind Gestaltungsvorlage mit Beispieldaten, keine Arbeitsanweisungen. Alle
> heutigen Dashboard-Funktionen bleiben erhalten: Seitenkopf mit ESI-Status,
> Popover und „Alles aktualisieren“, Meldungszeile, Kennzahlenreihe mit
> Info-Popover, Kapazität je Aktivität mit Gesamtzeile, Aktualisieren je
> Wallet, Serienwahl, Nettowert-Zeitraum mit Veränderung, Charakter-Nettowert
> mit Verlaufslinien, Bewertungsdetails, Fehler- und Speicherhinweise,
> Mineralpreis-Ticker, negative Reaktionen mit „Reaktionen öffnen“ und
> Analyseknopf, Moon- und Mineralien-Kauf mit Öffnen und Aktualisieren, Top 5
> nach Materialwert mit Hinweisen, Main-Hub-Chancen · Top 5, Startabgleich und
> die bestehenden `.task`-Abläufe.
> `EVEEntityText`/`EVEItemText`-Kopierverhalten, fehlende Datenzustände,
> sortierbare Tabellenköpfe und Rechenregeln bleiben. Die Anordnung gilt in
> beiden Stilen; HUD-Akzente nur im HUD. Bundle-ID, bestehende
> UserDefaults-Schlüssel und Accessibility-Identifier (`dashboard.refresh`,
> `dashboard.wallet.refresh.<id>`, `dashboard.wallet.character.<id>`,
> `dashboard.wealth-series`) nicht ändern. Neue sichtbare Texte in beiden
> `Localizable.strings`. Pflege PRODUCT.md, dev-diary.md und bei
> Entscheidungen `Documentation/Consolidation/DECISIONS.md` im selben Schritt.
> Prüfe mit `swift test`, `xcodebuild … build` und `xcodebuild … test`
> (Debug, unsigniert) und `EVEStaticDataKit` separat. Sichtprüfung in einer
> isolierten Debug-App mit eigenem Datenordner und eigener UserDefaults-Suite,
> Beenden nur per PID; Bildschirmfotos beider Stile. Bei Unsicherheiten oder
> Unklarheiten nachfragen, statt selbst zu entscheiden. Danach stoppen und
> berichten; geplant, implementiert, automatisch geprüft und visuell geprüft
> getrennt ausweisen. Kein Commit. Setze den Status des Prompts in Abschnitt 5
> auf „erledigt“ und gib am Ende den nächsten Prompt vollständig und
> kopierfertig aus, einschließlich dieses Vorspanns.

### DB1 – Grundgerüst

> - Ordne das Dashboard nach Abschnitt 4 an, zunächst ohne neue Funktionen:
>   Raster mit zwei Spalten (Mindestbreite je 360 pt, gleich hohe Panels je
>   Zeile), Abschnittsüberschriften entfallen, Untertitel aus dem Board.
> - Führe „Bereit zur Auslieferung“ und „Nächste 48 Stunden“ zum Panel
>   „Industriejobs · bereit und bevorstehend“ zusammen (Regeln in Abschnitt 1).
> - Wallets nach Board: drei Kacheln, darunter aufklappbar „Charaktere“. Der
>   Knopf „Dashboard aktualisieren“ bleibt bis DB5 im aufklappbaren Bereich.
> - Nettowert-Verlauf mit Board-Titel, Inhalt unverändert. Bis DB2 nimmt er Z2
>   allein ein.
> - Industriekapazität bleibt bis DB4 als Panel über dem Raster.
> - Z3 bis Z5 mit den übrigen App-Panels in der Reihenfolge aus Abschnitt 4.

→ Nächster Prompt: DB2

### DB2 – Main-Hub-Chancen · Top 5

> - Neues Panel in Z2 rechts neben dem Nettowert-Verlauf, Regeln in
>   Abschnitt 1, Nr. 3. Nutze dieselbe Filter- und Kostenrechnung wie die
>   Chancen-Ansicht (`MarketBrowserView.swift`), keine zweite Rechenregel.
>   Lagere die gemeinsame Auswahl dafür in eine testbare Funktion aus.
> - Spaltenköpfe Produkt, ROI, Gewinn. Nach AGENTS.md sortieren die Köpfe die
>   fünf ausgewählten Zeilen; die Auswahl der fünf bleibt nach ROI. Fehlende
>   Werte nach der dokumentierten Regel, stabile Identität als letzter
>   Schlüssel. Produktnamen über `EVEItemText`.
> - „Alle Chancen“ öffnet die Main-Hub-Chancen.
> - Kläre vorher: Text und Verhalten ohne Scan, bei veraltetem Scan und wenn
>   die Filter alle Zeilen ausschließen; ob Scanzeit und Hub im Panel stehen;
>   welcher Gewinnwert der Ansicht gemeint ist, falls sie je Zeile mehrere
>   zeigt (Gewinn, Vertragsgewinn).
> - Unit-Tests für Auswahl, Rang, fehlende ROI und Filter.

→ Nächster Prompt: DB3

### DB3 – Nettowert-Zeitraum und Veränderung

> - Zeitraumwahl 7 T / 30 T / 90 T / Alle im Panel „Nettowert · Verlauf“,
>   Start 30 T, gilt für die Sitzung. Nutze `NetWorthHistoryRange` und die
>   Zeitraumfilterung der Nettowert-Ansicht gemeinsam, keine zweite Variante.
> - Veränderung im Zeitraum nach Abschnitt 1, Nr. 4, als testbare Funktion;
>   sie versorgt in DB4 die Kennzahl „Nettowert“.
> - Kläre vorher: ob die Verlaufslinien je Charakter dem Zeitraum folgen; wie
>   eine Veränderung zwischen unvollständigen Bewertungen gekennzeichnet wird.
> - Unit-Tests für Zeitraumgrenzen, einen Wert, fehlende Werte.

→ Nächster Prompt: DB4

### DB4 – Kennzahlenreihe

> - Vier Karten über dem Raster nach Board: Nettowert (bekannter Gesamtwert,
>   Veränderung aus DB3), Wallet (Summe, Quellzustand, einbezogen von gesamt),
>   Fertigungsslots (laufend / Kapazität, bereit, frei), Gemeinsame
>   Science-Slots (laufend / Kapazität, darunter Reaktionen laufend /
>   Kapazität). Teilkapazitäten wie heute mit „≥“; Fortschrittsbalken nur bei
>   bekannter Kapazität.
> - Ersetze das Panel „Industriekapazität“ durch die Kennzahlenreihe und
>   darunter aufklappbar „Kapazität je Aktivität“ mit dem heutigen Raster,
>   Teilweise-Kennzeichnung und Jobdaten-Hinweis.
> - Kläre vorher: ob bereite, nicht ausgelieferte Jobs einen Slot belegen
>   (Berechnung von „frei“); was der Info-Knopf der Nettowert-Karte zeigt
>   (Bewertungsdetails als Popover oder Sprung zur Nettowert-Ansicht); ob der
>   Aufklappzustand gespeichert wird.

→ Nächster Prompt: DB5

### DB5 – Seitenkopf mit ESI-Status und „Alles aktualisieren“

> - Rechts im Seitenkopf nach Board: ESI-Status und Knopf „Alles
>   aktualisieren“, Regeln in Abschnitt 1, Nr. 2. Der Knopf übernimmt
>   `dashboard.refresh` und die heutigen Sperrbedingungen; der Knopf im
>   Wallet-Panel entfällt.
> - Zustand als reine, getestete Projektion (Muster
>   `StartupDataStatusProjector.combined`), keine neue Abrufarbeit.
> - Kläre vorher: Zeitangabe des Status (letzter Charakter-Sync oder älteste
>   Quelle); wo die heutigen Erfolgs- und Fehlermeldungen der Aktualisierung
>   erscheinen; ob die drei Analysen nach dem Charakter-Sync gleichzeitig oder
>   nacheinander laufen.

→ Nächster Prompt: DB6

### DB6 – Gesamtdurchsicht und Abnahme

> - Durchsicht des Dashboards in beiden Stilen und beiden Sprachen, schmal und
>   breit, ohne und mit synthetischen Testdaten (keine Nutzerdaten),
>   Bildschirmfotos je Fall. Prüfe vorher, ob die Fenstersteuerung per
>   Bedienungshilfen für die isolierte Debug-App verfügbar ist; wenn nicht, sag
>   mir Bescheid, bevor du schmale Fälle auslässt.
> - Prüfe die Funktionsliste aus dem Vorspann einzeln, auch Popover
>   (ESI-Status, Nettowert-Info), Auf- und Zuklappen, Zeitraumwahl und „Alle
>   Chancen“.
> - Erstelle in Abschnitt 7 eine Abnahme-Checkliste für den Eigentümer,
>   getrennt nach „ohne Daten geprüft“ und „nur mit echten Daten prüfbar“.

→ Nächster Prompt: DB7, nur wenn die Abnahme Befunde ergibt

### DB7 – Abnahme-Nacharbeiten (nur bei Bedarf)

> Arbeite die Befunde aus Abschnitt 7.3 ab, die der Eigentümer zum Umsetzen
> angekreuzt oder in seiner Nachricht genannt hat, und die Punkte aus 7.1 und
> 7.2, die er als „nicht i. O.“ markiert hat. Nur diese Punkte. Nenne vor der
> Umsetzung je Punkt Ursache und Vorschlag und frage nach, wo es mehrere Wege
> gibt. Sichere jede Korrektur mit einem Test, wo sie sich ohne Oberfläche
> prüfen lässt. Sichtprüfung der betroffenen Stellen in beiden Stilen und
> beiden Sprachen mit synthetischen Testdaten wie in DB6 (erfundene Piloten,
> Wallets, Skills, Jobs und Nettowert-Verlauf; ohne Netz, keine Nutzerdaten).
> Trage das Ergebnis je Punkt in Abschnitt 7 ein.

→ Nächster Prompt: DB8, nur wenn die Eigentümerabnahme Befunde ergibt

### DB8 – Nacharbeiten aus der Eigentümerabnahme (nur bei Bedarf)

> Arbeite die Punkte ab, die der Eigentümer bei der Abnahme in Abschnitt 7
> (7.1, 7.2 und 7.4) als „nicht i. O.“ markiert oder in seiner Nachricht
> genannt hat. Nur diese Punkte. Nenne vor der Umsetzung je Punkt Ursache und
> Vorschlag und frage nach, wo es mehrere Wege gibt. Sichere jede Korrektur mit
> einem Test, wo sie sich ohne Oberfläche prüfen lässt. Sichtprüfung der
> betroffenen Stellen in beiden Stilen und beiden Sprachen mit synthetischen
> Testdaten wie in DB6; Punkte, die nur mit echten Daten prüfbar sind, als
> solche ausweisen. Trage das Ergebnis je Punkt in Abschnitt 7 ein.

## 7. Abnahme-Checkliste (Eigentümer)

Erstellt in DB6 (08.11.2026). Spalte „Eigentümer“: `[ ] i. O.` oder
`[ ] nicht i. O.` ankreuzen, Bemerkung dahinter. DB7 bearbeitet nur, was hier
als „nicht i. O.“ markiert oder in 7.3 freigegeben ist.

Grundlage der Spalte „DB6“: isolierte Debug-App (eigener Datenordner, eigene
UserDefaults-Suite, ohne Hintergrunddienste, ohne Netzzugang, Beenden per
PID), acht Fälle: Klassisch und New Eden HUD × Deutsch und Englisch × ohne
Charaktere und mit synthetischen Testdaten, je breit (1600 pt) und schmal
(760 pt) mit Bildern von oben bis unten. Testdaten: zwei erfundene Piloten mit
Wallets, Skills, 16 Jobs aller Zustände und 40 Tagen Nettowert-Verlauf
(ältester Tag unvollständig); keine Nutzerdaten, keine Tokens, kein SDE.
Bedienung per Bedienungshilfen (AX) nach PID. Bilder liegen nur lokal, nicht
im Repository.

### 7.1 Ohne echte Daten geprüft

| Nr. | Prüfpunkt | DB6 | Eigentümer |
|---|---|---|---|
| A1 | Anordnung breit in beiden Stilen und Sprachen: Seitenkopf, vier Kennzahlen, „Kapazität je Aktivität“, dann Jobs ∣ Wallets, Nettowert-Verlauf ∣ Main-Hub · Top 5, Top 5 Materialwert ∣ negative Reaktionen, Mineralienpreise, Moon- ∣ Mineralien-Kauf | gesehen, wie Board | [ ] |
| A2 | Anordnung schmal: eine Spalte, Kennzahlen 2 × 2, Knöpfe des Seitenkopfs unter dem Titel, Serienwahl als Menü | gesehen; Befund B9 | [ ] |
| A3 | HUD-Akzente (Raute, Eckwinkel, Kicker „Übersicht“) nur im HUD | gesehen | [ ] |
| A4 | Seitenkopf: ESI-Status mit „Stand“ der ältesten Quelle; ohne Charaktere „Nicht verfügbar“ und „Alles aktualisieren“ gesperrt | gesehen | [ ] |
| A5 | ESI-Status-Popover: sechs Quellen mit Zustand und Zeit, Erklärungssatz; öffnet und schließt | bedient; Befund B1 | [ ] |
| A6 | Meldungszeile unter dem Kopf mit Ergebnis des Startabgleichs (hier: 0 von 2 aktualisiert, Autorisierung fehlt) | gesehen | [ ] |
| A7 | „Alles aktualisieren“ startet Abgleich, Meldungszeile wird neu gesetzt | bedient (ohne Netz erwartungsgemäß Fehler) | [ ] |
| A8 | Kennzahl Nettowert mit „Veränderung im Zeitraum“; Info-Knopf öffnet „Details zur Bewertung“ | bedient; Befunde B1, B2 | [ ] |
| A9 | Kennzahlen Wallet, Fertigungs-Slots, Science-Slots mit Reaktionen | aus Testdaten nachgerechnet: 2.097.354.121 ISK; 8/15, 2 bereit, 7 frei; 5/15, 1 bereit, 10 frei; Reaktionen 2/6 | [ ] |
| A10 | „Kapazität je Aktivität“ auf- und zuklappen, Zustand bleibt gespeichert; Raster mit sechs Aktivitäten; Gesamtzeile zählt laufende Jobs (12 von 36), die Kacheln belegte (DECISIONS DB3) | bedient, Schlüssel 1/0 geprüft | [ ] |
| A11 | Jobliste: bereite Jobs zuerst, dann nach Ende; „Alle anzeigen“ klappt auf; unbekannte Namen als „Blueprint Nr. …“ | bedient | [ ] |
| A12 | Wallets: drei Kacheln, „Wallets der Charaktere“ aufklappbar, Aktualisieren je Wallet (`dashboard.wallet.refresh.<id>`) | bedient; Befund B4 | [ ] |
| A13 | Nettowert-Zeitraum 7 T / 30 T / 90 T / Alle mit Veränderung | nachgerechnet: +5,5 %, +19,5 %, +32,3 % „aus bekannten Bestandteilen“ (ältester Tag unvollständig) | [ ] |
| A14 | Serienwahl Gesamt / Wallet / Assets / In Produktion | bedient; Befund B6 | [ ] |
| A15 | Main-Hub-Chancen · Top 5 ohne Scan: „Noch kein Main-Hub-Scan“; „Alle Chancen“ öffnet Main-Hub-Chancen | bedient | [ ] |
| A16 | Top 5 nach Materialwert: Hinweise „Unvollständige Rangfolge“ und Preisfehler | gesehen | [ ] |
| A17 | Negative Reaktionen: Erklärung, „Reaktionen öffnen“ navigiert, „Alle Reaktionen analysieren“ startet | bedient; Befund B3 | [ ] |
| A18 | Mineralienpreise: leerer Zustand, „Einkaufsanalyse öffnen“ öffnet Mineralien-Kaufanalyse, Aktualisieren | bedient; Befunde B3, B8 | [ ] |
| A19 | Moon- und Mineralien-Kauf: „Einkaufsanalyse öffnen“ öffnet die passende Seite, Aktualisieren | bedient; Befunde B3, B7, B8 | [ ] |
| A20 | Fehlende Daten bleiben ausdrücklich („Nicht verfügbar“, „Keine verbundenen Charaktere“, „—“), nie 0 als Ersatz | gesehen | [ ] |
| A21 | Fehlerhinweis der Bewertung („ESI-Referenzpreise konnten nicht geladen werden“) | gesehen | [ ] |
| A22 | Namen als Kopierziel (`EVEEntityText`/`EVEItemText`) mit Bezeichnung „EVE-Namen kopieren“ und Hinweis | per Bedienungshilfen gelesen, nicht geklickt (Zwischenablage des Eigentümers); Befund B10 | [ ] |
| A23 | Sprache: Texte des Dashboards folgen der App-Sprache | gesehen; Befunde B1, B3, B4, B5 | [ ] |

### 7.2 Nur mit echten Daten prüfbar

| Nr. | Prüfpunkt | Warum nicht in DB6 | Eigentümer |
|---|---|---|---|
| E1 | Startabgleich mit gültiger Autorisierung: Meldungszeile, ESI-Status „Aktuell“; Seitenleiste und Popover zeigen für Charaktere denselben Zustand | ohne Token und Hintergrunddienste nicht vergleichbar (Seitenleiste „Veraltet“, Popover „Nicht verfügbar“) | [ ] |
| E2 | „Alles aktualisieren“: Status „Wird aktualisiert“, danach Moon-, Mineralien- und Reaktionsanalyse | braucht ESI | [ ] |
| E3 | Aktualisieren je Wallet: neuer Saldo und Zeit | braucht Token | [ ] |
| E4 | Nettowert mit Preisen: Wert, Wallet / Assets / In Produktion, „Nettowerte der Charaktere“ mit Verlaufslinien, „Details zur Bewertung“, Hinweise zu unbewerteten Assets, BPC, Orders und Verträgen | Bewertung braucht ESI-Preise | [ ] |
| E5 | Speicherhinweis bei fehlgeschlagenem Speichern | nicht gefahrlos auslösbar | [ ] |
| E6 | Jobliste mit SDE: Blueprint- und Produktnamen, Kopieren per Klick mit Rückmeldung | kein SDE im isolierten Ordner | [ ] |
| E7 | Slot-Kapazität mit echten Skills gegen das EVE-Industriefenster, besonders Reaktionen (Regel heute: Mass Reactions + Advanced Mass Reactions, ohne Grundslot) | Rechenregel unverändert, nur im Spiel vergleichbar | [ ] |
| E8 | Main-Hub-Chancen · Top 5 mit Scan: Tabelle, sortierbare Köpfe in beiden Richtungen, Namen kopierbar | braucht Scan | [ ] |
| E9 | Top 5 nach Materialwert mit Preisen | braucht Preise | [ ] |
| E10 | Negative Reaktionen mit SDE-Analyse | braucht SDE und Markt | [ ] |
| E11 | Mineralpreis-Ticker mit Analyse, Hinweis bei unvollständiger Marktabdeckung | braucht Markt | [ ] |
| E12 | Moon- und Mineralien-Kauf mit Empfehlungen | braucht Markt | [ ] |
| E13 | Nettowert-Verlauf über mehrere Tage (ein Punkt je Tag) | braucht Zeit | [ ] |

### 7.3 Befunde aus DB6 (Vorschläge für DB7)

„Neu“ = durch DB1–DB6 entstanden, „alt“ = schon vor DB1 im Code.

| Nr. | Befund | Herkunft | Vorschlag | Eigentümer |
|---|---|---|---|---|
| B1 | Popover „ESI-Status“ und „Details zur Bewertung“ zeigen in der englischen Oberfläche deutschen Text (Quellennamen, Erklärung, Bewertungstext); nur die Zustände sind englisch. Die Popover übernehmen die App-Sprache nicht. | neu (DB4, DB5) | Popover-Inhalt mit der Locale der App-Sprache versehen, wie in `MoonMaterialPurchaseAnalysisView` | [x] umsetzen |
| B2 | Der Info-Knopf am Nettowert hat nicht die Kennung `dashboard.key-figure.net-worth.info`; die Kennung der Kachel überdeckt alle inneren Elemente (gilt für alle vier Kacheln). | neu (DB4) | Kacheln mit `.accessibilityElement(children: .contain)` versehen, wie die Wallet-Zeilen | [x] umsetzen |
| B3 | „No active SDE catalog is installed. Install or activate static data first.“ erscheint auf Englisch (Reaktionen, Mineralienpreise, Moon- und Mineralien-Kauf); der Schlüssel fehlt in `Localizable.strings`. | alt | Schlüssel in beiden `Localizable.strings` ergänzen | [x] umsetzen |
| B4 | Aktualisieren je Wallet zeigt bei Fehler den internen Fehlernamen („Testpilot Alpha: noStoredAuthorization“); Tooltip und Bedienungshilfe „Refresh %@'s wallet“ sind nicht übersetzt. | alt | Dieselbe lokalisierte Fehlermeldung wie die Meldungszeile verwenden; Schlüssel ergänzen | [x] umsetzen |
| B5 | Englische Oberfläche: Restzeit der Jobs („in 30 Minuten“), Achsen des Nettowert-Diagramms („10. Okt. 2026“, „2,2 Mrd.“) und ISK-Beträge folgen der Systemsprache statt der App-Sprache. | alt | Formatierung mit der Locale der App-Sprache | [x] umsetzen |
| B6 | Serie „Assets“ oder „In Produktion“ ohne Werte zeigt eine leere Fläche ohne Hinweis; die Bedienungshilfe des Diagramms heißt immer „Gesamter Nettowertverlauf“. | alt | Ausdrücklichen Leerzustand je Serie anzeigen; Bezeichnung nach Serie | [x] umsetzen |
| B7 | Moon- und Mineralien-Kauf ohne jede Analyse melden „Einstellungen geändert. Aktualisiere die Kauforte.“, obwohl nichts geändert wurde. | alt | Erstzustand „Noch keine Analyse“ von „Einstellungen geändert“ trennen | [x] umsetzen |
| B8 | Bedienungshilfe „Refresh“ der Aktualisieren-Knöpfe in den Kaufpanels ist nicht übersetzt; im Mineralpreis-Panel steht das Symbol vor, in den Kaufpanels hinter „Einkaufsanalyse öffnen“. | alt | Schlüssel ergänzen; Reihenfolge angleichen | [x] umsetzen |
| B9 | Schmal: Wallet-Kachel kürzt „2 von 2 Charakteren einbezogen“ zu „… einbezo…“. Kachel „Gemeinsame Science-Slots“, Raster „Gemeinsam genutzte Wissenschaftsslots“: zwei Begriffe für dasselbe. | neu (DB4) | Zweizeilig umbrechen; einen Begriff wählen | [x] umsetzen |
| B10 | Eine Jobzeile ist für Bedienungshilfen ein einziges Element: Blueprint- und Charaktername werden zu einer Schaltfläche zusammengefasst, der zweite Name ist nur als Zusatzaktion erreichbar. Mit der Maus sind laut Code beide Namen einzeln kopierbar (nicht geklickt). | alt | Zeile mit `.contain` statt `.combine` gruppieren | [x] umsetzen |

Beobachtungen ohne Vorschlag: Nach einem Start ohne Netz steht der Nettowert
auf „Nicht verfügbar“, während die Veränderung im Zeitraum aus dem Verlauf
weiter angezeigt wird (ausdrücklicher Zustand, kein Fehler). Außerhalb des
Dashboards tragen „Update“ (Main-Hub-Chancen) und „Refresh“
(Kaufanalysen) englische Beschriftungen in der deutschen Oberfläche.

### 7.4 Ergebnis DB7 (08.11.2026)

Alle Befunde B1–B10 umgesetzt, nicht committet. „Test“ = neuer Test in
`DashboardAcceptanceFixTests`; „Sicht“ = isolierte Debug-App mit den
synthetischen Testdaten aus DB6, per Bedienungshilfen gelesen und fotografiert.

| Nr. | Umsetzung | Test | Sicht | Eigentümer |
|---|---|---|---|---|
| B1 | Popover-Inhalte (ESI-Status, Bewertungsdetails, Kopier-Rückmeldung) mit `appLanguageLocale()` | – | HUD/Englisch: „Data sources“, „Valuation details“, Zeiten „9:39 AM“ | [ ] i. O. |
| B2 | Kennzahlkarten mit `.accessibilityElement(children: .contain)` | – | `dashboard.key-figure.net-worth.info` in beiden Sprachen gefunden und bedient | [ ] i. O. |
| B3 | Zwei Analyse-Fehlertexte übersetzt | ja (alle Analyse-Fehlertexte) | „Es ist kein aktiver SDE-Katalog installiert …“ in allen vier Panels | [ ] i. O. |
| B4 | Wallet-Fehler über `EVEConnectionErrorText`, Tooltip/Bedienungshilfe übersetzt | ja | „Testpilot Alpha: Die lokale EVE-Autorisierung fehlt …“ / „… The local EVE authorization is missing …“; „Wallet von … aktualisieren“ | [ ] i. O. |
| B5 | Restzeit, Datum, Achsen, Prozent, ISK in der App-Sprache | ja (ISK, Uhrzeit) | Englisch: „in 30 minutes“, „Oct 10, 2026“, „2.2B“, „ISK 2,097,354,121“ | [ ] i. O. |
| B6 | Leerzustand je Serie, Bedienungshilfe nach Serie | ja | „Keine Werte für „Assets“ im gewählten Zeitraum.“ / „No values for “Assets” …“ | [ ] i. O. |
| B7 | „Noch keine …-Kaufanalyse“ ohne Analyse | ja | in beiden Sprachen gesehen | [ ] i. O. |
| B8 | „Kaufanalyse aktualisieren“; Symbol überall hinter „Einkaufsanalyse öffnen“ | ja (Text) | Reihenfolge in allen drei Panels gesehen, Bezeichnungen per Bedienungshilfen | [ ] i. O. |
| B9 | „Gemeinsame Wissenschafts-Slots“ in Kachel und Raster; Wallet-Text bricht um | ja (Text) | bei 2 × 2 zweizeilig statt gekürzt | [ ] i. O. |
| B10 | Jobzeilen mit `.contain` | – | Blueprint- und Charaktername je eigene Kopier-Schaltfläche | [ ] i. O. |

Beobachtungen aus DB7: Der längere Begriff lässt den Titel „Gemeinsame
Wissenschafts-Slots“ bei 2 × 2 zweizeilig werden; der Wert steht dann etwas
tiefer als in der Nachbarkarte. Die isolierte Debug-App teilt Fenster- und
Seitenleisten-Autosave (`NSSplitView Subview Frames …`) mit der echten App,
weil beide dieselbe Bundle-ID nutzen; die Seitenleiste war in DB7 rund 43 pt
breiter als in DB6, daher stehen die Kennzahlen bei 760 pt Fensterbreite jetzt
untereinander (Inhalt 433 pt, Grenze für 2 × 2 sind 476 pt) und ab etwa
820 pt wieder 2 × 2. Gespeicherte Fensterrahmen zeigen keine Prüfmaße.
