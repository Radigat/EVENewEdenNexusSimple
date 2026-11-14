# Reaktionsgeschwindigkeit: Dashboard, Hub-Chancen, gemeinsame Bausteine (13.11.2026)

Stand: HEAD `b57accd` auf `main`, Arbeitsbaum sauber.

Auftrag des Eigentümers: alle Abläufe möglichst beschleunigen, ohne Daten zu
verlieren. Zuerst das Dashboard, weil es am langsamsten ist und ruckelig
scrollt. Danach „Main-Hub-Chancen“ und „Home-Hub-Chancen“, die nach dem Klick
lange laden. Zu klären war, ob das an ESI liegt.

> **Belegstufe:** statische Durchsicht des Quellcodes. Nichts davon ist gebaut,
> in der laufenden App gemessen oder live geprüft. Effektangaben sind
> Schätzungen. Zeilenangaben gelten für `b57accd`. Die Messung ist Prompt O1.

Planer und Handel wurden bereits in der
[App-Analyse](ANALYSE_2026-11-02.md) (A1–A6) gemessen und beschleunigt. Das
Scrollen im Dashboard und das Öffnen der Hub-Chancen waren dort nicht Thema.
Die Dashboard-Optimierung vom 26.10.2026 (dev-diary) betraf das Dekodieren beim
Abgleich, nicht die Darstellung; ihre Messung blieb offen.

## 1. Antworten des Eigentümers (13.11.2026)

1. Das Dashboard ruckelt **immer, auch in Ruhe**, nicht nur beim Laden.
2. Messung: Der Eigentümer startet den Debug-Build mit seinen echten Daten,
   scrollt und klickt; die Sitzung zeichnet nur Zeiten und Proben dieses
   Prozesses auf und bedient die App nicht.
3. Freigegeben, falls die Messung es nahelegt: mehr Arbeitsspeicher, kleine
   Optik-Vereinfachungen, Runs/ME/TE in der Hub-Tabelle erst bei Klick als
   Eingabefeld, Datenbank-Schema als eigener, später Schritt.
4. Lieferform: diese Prompt-Reihe, je Prompt eine eigene Sitzung.

Fest steht in jedem Fall: Rechenergebnisse und Datenumfang bleiben gleich.

## 2. Liegt es an ESI?

**Beim Öffnen der Hub-Chancen: nein.** Die Ansicht lädt kein Orderbuch aus dem
Netz. Der letzte Scan wird beim Start geladen und bleibt im Speicher
(`RuntimeState.loadManufacturingOpportunityAnalysis`, `RuntimeState.swift:849`).
Die Wartezeit nach dem Klick entsteht lokal (Abschnitt 4). Einzige Ausnahme:
Die Inventionsschätzung kann beim Öffnen Marktabrufe für Datacores und
Decryptoren auslösen (`RuntimeState.swift:4917`, `:4970`, `:5132`).

**Beim Scan („Update“ oder Automatik): ja, zum Teil.** Im Code gesehen:

- Das regionale Gesamt-Orderbuch wird bei jedem Scan vollständig geladen; nach
  dem Scan werden seine Seiten aus dem Cache entfernt
  (`RuntimeState.swift:3733`).
- Höchstens 4 Seiten gleichzeitig (`ESIClient.swift:255`), insgesamt 12
  Anfragen, automatische Arbeit höchstens 2 (`:315-316`, Eigentümerentscheid
  04.11.2026).
- Läuft Seite 1 in höchstens 5 Sekunden ab, wartet der Abruf bis nach der
  Erneuerung (`ESIClient.firstPage`, `:1333-1350`).
- Home und Coalition starten erst nach der Main-Analyse.

Die Scandauer steht schon im Protokoll (`main-hub-scan`). Maßnahmen dazu
stehen in O9 und brauchen eine Eigentümerentscheidung.

## 3. Befunde Dashboard

Die Ansicht ist `DashboardView` (`ContentView.swift:2162-4177`): eine
`ScrollView` mit nicht-lazy `VStack` (`:2210-2243`), alle Panels bestehen
gleichzeitig. Im Leerlauf ändert sich der Zustand fast nie (sechs
`TimelineView` im Minutentakt). Ruckeln in Ruhe spricht deshalb für
Darstellungslast, nicht für Rechenarbeit.

**Darstellung (D):**

- **D1 Schatten über ganzen Panel-Inhalten.** `NexusPanelSurface`
  (`InterfaceStyleComponents.swift:30-57`) legt `.shadow` auf Inhalt plus
  Hintergrund. Das betrifft 14 Flächen: vier Kennzahlen, „Kapazität je
  Aktivität“ (`ContentView.swift:3001`) und neun `Panel`
  (`ContentView.swift:5662-5690`). Ein Schatten auf zusammengesetztem Inhalt
  braucht je Fläche einen eigenen Zeichendurchgang.
- **D2 HUD-Eckwinkel als Maske.** `HUDCornerBrackets`
  (`InterfaceStyleComponents.swift:190-208`) maskiert je Panel einen
  Rahmenstrich.
- **D3 Viele kleine abgeschnittene Flächen.** Kacheln, Pillen und Icon-Rahmen
  nutzen `.background(...)` plus `.clipShape(...)` (unter anderem
  `ContentView.swift:3064`, `:3161`, `:3693`, `:4170`, `:5421-5427`).
- **D4 Mineral-Laufband.** `DashboardMineralTickerMarqueeView`
  (`ContentView.swift:4518-4606`) ist eine `NSHostingView` mit doppelter
  Inhaltsbreite und endloser Core-Animation. Jede Aktualisierung erzwingt ein
  Layout (`:4567-4568`). Solange es läuft, setzt der Fensterserver das Fenster
  laufend neu zusammen.
- **D5 Viele Einzelteile je Name.** `EVEItemText` (`ContentView.swift:5475`)
  besteht aus Icon, Kopierknopf, Verlaufs- und Hammerknopf. `EVEEntityText`
  (`:5580-5660`) trägt je Instanz einen Tooltip, ein Popover und zwei
  `@State`; `EVEEntityLabel` (`:5359-5376`) ein eigenes `@AppStorage`. Auf dem
  Dashboard sind das grob 30–50 Namen. Ob Tooltips und Popover-Anker das
  Scrollen bremsen, ist eine Vermutung.

**Hauptthread (wirkt beim Start, bei Abgleich und Hintergrundarbeit):**

- **D6 Ein `body` für alles.** Alle Panels sind Funktionen desselben Structs.
  Jede gelesene `RuntimeState`-Eigenschaft, jede der vier `@Query` und jedes
  `@State` wertet das ganze Dashboard neu aus. `ContentView` übergibt eine
  Closure (`ContentView.swift:470`), deshalb läuft der `body` auch bei jeder
  Auswertung des Hauptfensters.
- **D7 Teure Identitäten je Durchlauf.** Die Argumente der sieben
  `.task(id:)` werden bei jedem `body` berechnet:
  - `dashboardIndustryRefreshIdentity` (`:3749-3762`) hasht die Job-Daten
    aller Charaktere; `jobSettingsByCharacterID` (`:3778-3791`) baut dafür
    zwei Dictionaries über alle Dashboard-Einstellungen.
  - `mainHubTopFiveTrigger` (`:2550-2558`,
    `MarketBrowserView.swift:6175-6204`) liest UserDefaults, dekodiert die
    Favoriten und je Charakter die Wallet.
  - `walletPortfolio` (`:3837-3849`) dekodiert die Wallets dreimal
    (`:2445`, `:2848`, `:3071`).
  - `wealthHistory` (`:3909-3915`) wird mindestens viermal gelesen; der Cache
    vergleicht jedes Mal den ganzen Verlaufs-String (`:4361`).
- **D8 Mehrfach gebaute Varianten.** `ViewThatFits` baut Kennzahlen, Kopf,
  Wallet-Kacheln und Picker doppelt (`:2367`, `:2743`, `:3083`, `:3444`);
  `DashboardCardLayout` misst ohne Cache (`:1659-1704`).

## 4. Befunde Hub-Chancen

Main, Home und Coalition nutzen `ManufacturingOpportunitiesView`
(`MarketBrowserView.swift:30`). Die Tabelle erscheint erst, wenn die
Kandidaten-Projektion fertig ist (`:464-516`).

- **H1 ME/TE-Annahmen werden auf dem Hauptthread nachgerechnet (stärkster
  Kandidat).** Der Scan speichert ME 0/TE 0
  (`MarketBrowserModels.swift:73-80`). Die Ansicht nimmt für T1-Module
  ME 10/TE 20 und für T2 ME 3/TE 2 an
  (`ManufacturingOpportunityEfficiencyDefaults.resolve`, `:170-206`). Für
  diese Zeilen greift der frühe Ausstieg in
  `candidateApplyingRequestedParameters` (`MarketBrowserView.swift:4371-4417`)
  nie: Runs, Beschaffung, Logistik und Kosten werden neu gerechnet. Das
  geschieht nach jeder Projektion (`:4457-4470`) und **bei jedem
  `body`-Durchlauf** über `visibleCandidates` (`:312-334`, Aufruf `:465`),
  also auch bei jedem Tastendruck in einem Feld.
- **H2 Mehrere Projektionen je Öffnen.** Der Trigger (`:3552-3600`) enthält
  Lager, Reservierungen, LP-Angebote, Vertragsreferenzen und
  Inventionsrevision. Sie treffen einzeln ein (Tasks `:525-584`) und starten
  die Projektion jeweils neu. Seit 24.10.2026 bleibt die Tabelle dabei
  stehen; die Rechenarbeit blieb.
- **H3 Nichts überlebt den Bereichswechsel.** `switch selection`
  (`ContentView.swift:468-574`) baut die Ansicht neu. Lager, Reservierungen
  (`:5260-5302`, JSON aller aktiven Pläne) und Projektion laufen bei jedem
  Besuch erneut. Nur das Dashboard-Top-5 hat einen Cache (`:6209-6222`), die
  Lagerprojektion einen einzelnen Platz
  (`StoredAssetWarehouseProjection.swift:155-185`);
  `prepareProductionWarehouse` (`RuntimeState.swift:4750-4772`) fragt die
  Klassifikationen jedes Mal neu ab.
- **H4 Ein Platz für Vertragsreferenzen aller Hubs.**
  `loadOpportunityContractReferences` (`RuntimeState.swift:5842-5897`) merkt
  sich nur die letzte Typmenge. Main, Home, Coalition und Dashboard haben
  verschiedene Mengen; jeder Wechsel liest den lokalen Vertragsindex neu und
  ändert die Referenz-ID, was überall eine Neuberechnung auslöst.
- **H5 Inventionsschätzung auf dem Hauptthread.**
  `estimateOpportunityInvention` (`RuntimeState.swift:5155-5196`) läuft über
  alle T2/T3-Blueprints mit je mehreren Katalogabfragen; das Ergebnis gilt
  eine Stunde (`:5135`).
- **H6 Arbeit je `body`.** `activePlanSnapshotPayloads` vergleicht die
  vollständigen Plan-Daten (`:456`, `:5815-5826`), `warehouseIdentity` fasst
  die Asset-Blobs an (`:5766-5789`), `categories`/`groups` sortieren alle
  Zeilen (`:3491`, `:3496`), `favoriteIDs` dekodiert je Zugriff (`:3507`).
- **H7 Schwere Tabellenzeilen.** `opportunityRow` (`:1388-1514`) ist eine
  Funktion der großen Ansicht mit rund 25 Zellen, drei `TextField` und sofort
  gebauten Erklärtexten (`costBreakdown`, `:1717`). Beim Scrollen der
  `LazyVStack` (`:1275-1299`) entsteht das für jede neue Zeile.
- **H8 Nachfrage wird bei jedem Öffnen neu gelesen**
  (`loadManufacturingOpportunityDemand`, `RuntimeState.swift:838`).

## 5. Befunde app-weit

- **G1 Lokalisierung ohne Cache.** `AppLocalization.text` und `.format`
  (`AppLanguage.swift:477-499`) lesen je Aufruf UserDefaults, suchen den
  Sprachordner und erzeugen ein `Bundle` (`:29-44`); `locale` erzeugt je
  Zugriff ein `Locale` (`:18-20`). Über 1.200 Aufrufstellen, viele je
  Tabellenzeile.
- **G2 Icons ohne Speicher-Cache.** `EVEItemIcon`
  (`ContentView.swift:5401-5473`) und `AssetsWarehouseView.swift:1017` nutzen
  nacktes `AsyncImage`. Vermutung: Icons laden beim Scrollen und beim
  Bereichswechsel neu und zeigen kurz den Platzhalter.
- **G3 Namensfarbe je Instanz** (`EVEEntityLabel`, `@AppStorage` und
  Farbumrechnung je `body`, `ContentView.swift:5223-5251`, `:5359-5376`).
- **G4 Formatter je Aufruf:** `MoonMaterialPurchaseAnalysisView.swift:918`,
  `:937`, `:1222`; `MarketBrowserView.swift:4734`; `TradeLogbookView.swift:65`;
  `ESIClient.swift:1545`; `EVEOnlineServiceStatus.swift:188`.
- **G5 `ConsolidationController` als `ObservableObject` an der Wurzel**
  (`ConsolidationPersistence.swift:33-39`, `EVENexusSimpleApp.swift:39`,
  `ContentView.swift:393`): Jede Änderung wertet App, Hauptfenster und Planer
  neu aus.
- **G6 Große Blobs in beobachteten Modellen.** `StoredCharacter` hält
  Assets, Corp-Assets und Blueprints ohne `.externalStorage`
  (`PersistenceModels.swift:165-177`), `AppSetting.value` Jobs, Orders,
  Verträge und den Nettowert-Verlauf als Base64 (`:454-456`). Rund 15 `@Query`
  laden sie, auch Hauptfenster (`ContentView.swift:397-400`) und
  Seitenleiste; ungefiltert in `NetWorthView.swift:236`. Vermutung: Jedes
  `save()` lädt mehrere Megabyte neu.
- **G7 Speichern und Dekodieren auf dem Hauptthread:**
  `CharacterSyncPersistence.apply` (`PersistenceModels.swift:551`),
  `retainedSnapshotData` (`PlaceholderViews.swift:9965`),
  `NetWorthView.wealthInputs` (`NetWorthView.swift:1056`).
- **G8 Sortieren und Filtern je `body`:** `sortedStockTargets` mit
  `targetQuantities` je Vergleich (`AssetsWarehouseView.swift:694`, `:1160`),
  `displayedRows` (`MarketStockView.swift:158`), `visibleEntries`
  (`TradeLogbookView.swift:523`), `sortedContexts`
  (`ProductionBookViews.swift:894`), `filteredHistory` je Zeile
  (`NetWorthView.swift:1019`).

**Nebenbefund ohne Auftrag (fachlich):** Das Dashboard-Top-5
(`MainHubOpportunityTopFiveProjection`, `MarketBrowserView.swift:6027-6134`)
rechnet mit der Scan-Basis ME 0/TE 0, die Tabelle mit den ME/TE-Annahmen aus
H1. ROI und Gewinn derselben Zeile können sich unterscheiden, obwohl
[DB2](DASHBOARD_BOARD_2026-11-07.md) „dieselbe Kostenrechnung wie die Ansicht“
festlegt. Im Code gesehen, nicht in der App nachgestellt.

## 6. Maßnahmen

Grundsatz: gleiche Daten, gleiche Regeln, gleiche Zahlen. „Pixelgleich“ heißt:
ein Rendertest vergleicht alt und neu.

| # | Maßnahme | Befund | Effekt (geschätzt) | Aufwand | Ergebnis / Optik |
|---|---|---|---|---|---|
| **T0** | Messpunkte und A/B-Schalter (nur Debug), Messung mit dem Eigentümer | alle | Grundlage | klein | unverändert |
| T1 | Schatten auf die Hintergrundform statt auf den Panel-Inhalt | D1 | groß beim Scrollen, in allen Bereichen | klein | pixelgleich zu prüfen |
| T2 | HUD-Eckwinkel als Pfad statt Maske | D2 | mittel im HUD-Stil | klein | pixelgleich zu prüfen |
| T3 | Farbflächen als Form-Hintergrund statt `clipShape` | D3 | klein bis mittel | klein | pixelgleich zu prüfen |
| T4 | Laufband nur animieren, wenn sichtbar und nicht gescrollt wird; kein erzwungenes Layout | D4 | mittel | klein | kleine Optikänderung, freigegeben |
| T5 | Tooltips und Kopier-Rückmeldung leichter anbinden | D5 | offen, nur nach Messung | mittel | unverändert |
| T6 | Dashboard-Panels als eigene Views mit schmalen Eingaben | D6 | mittel bei Start und Abgleich | mittel | unverändert |
| T7 | Identitäten, Wallet und Verlauf einmal je Änderung statt je `body` | D7 | mittel | klein | unverändert |
| T8 | Layout-Cache in `DashboardCardLayout`, weniger doppelte Varianten | D8 | klein | klein | unverändert |
| T9 | Sprach-Bundle, `Locale` und aktuelle Sprache cachen | G1 | mittel, überall | klein | identisch |
| T10 | Gemeinsamer Icon-Lader mit Speicher-Cache | G2 | mittel in Tabellen | mittel | identisch, weniger Platzhalter-Flackern |
| T11 | Namensfarbe einmal je Fenster über die Umgebung | G3 | klein bis mittel | klein | identisch |
| T12 | Formatter statisch halten | G4 | klein | klein | identisch |
| T13 | ME/TE-Annahmen und Zeilenwerte in der Hintergrund-Projektion rechnen; `visibleCandidates` merken | H1 | groß | mittel | identisch; Dashboard-Top-5 bleibt bis Entscheid 1 unverändert |
| T14 | Lager, Reservierungen und Kandidaten je Hub im Speicher halten, Schlüssel ist der vollständige Trigger | H3 | groß beim erneuten Öffnen | mittel | identisch, mehr Arbeitsspeicher |
| T15 | Eingaben sammeln, dann eine Projektion | H2 | mittel | mittel | identisch |
| T16 | Vertragsreferenzen je Typmenge; ID bleibt bei gleichem Inhalt | H4 | mittel | klein | identisch |
| T17 | Inventionsschätzung abseits des Hauptthreads | H5 | mittel | mittel | identisch |
| T18 | Eingaben je `body` merken (Plan-Payloads, Kategorien, Favoriten) | H6 | klein bis mittel | klein | identisch |
| T19 | Zeile als eigene View; Runs/ME/TE erst bei Klick als Feld; Erklärtexte erst beim Öffnen | H7 | groß beim Scrollen der Tabelle | mittel | Bedienänderung, freigegeben |
| T20 | Nachfrage im Speicher halten | H8 | klein | klein | identisch |
| T21 | Regionsbuch im selben Scan für Hubs derselben Region wiederverwenden; Wartezeit vor Seite 1 prüfen | Abschnitt 2 | offen | mittel | identisch; Entscheid 3 |
| T22 | `ConsolidationController` auf Observation umstellen oder enger einbinden | G5 | mittel im Planer | mittel | unverändert |
| T23 | Kodieren beim Abgleich abseits des Hauptthreads; Vorgänger nur im Fehlerfall dekodieren | G7 | mittel beim Start | mittel | identisch |
| T24 | Blobs: erst schlanke Abfragen, dann Auslagerung mit Migration | G6 | offen | groß | identisch; Entscheid 4 |
| T25 | Nettowert: Dekodieren im Hintergrund, gefilterte Abfrage, Verlauf einmal filtern | G7, G8 | mittel | klein | identisch |
| T26 | Sortierungen je `body` in Lager, Marktbestand, Logbuch, Produktionsübersicht merken | G8 | mittel je Bereich | mittel | identisch |

## 7. Offene Eigentümerentscheidungen

1. Soll das Dashboard-Top-5 dieselben ME/TE-Annahmen nutzen wie die Tabelle
   (Nebenbefund)? Bis dahin bleibt T13 auf die Ansicht begrenzt.
2. O2: Welche Vereinfachung, falls die pixelgleichen Maßnahmen nicht reichen:
   Laufband pausieren, schlichtere oder keine Schatten?
3. O9: Änderungen an ESI-Parallelität und Wartezeiten. Sonst gilt der
   Entscheid vom 04.11.2026 weiter.
4. O8: Schema-Migration ja oder nein, nach Messwerten.

## 8. Reihenfolge

Umsetzung nur auf ausdrücklichen Auftrag, je Schritt ein Prompt aus
Abschnitt 9. Nach O1 kann sich die Reihenfolge ändern.

| Prompt | Inhalt | Status |
|---|---|---|
| O1 | T0 Messung mit dem Eigentümer | erledigt (Abschnitt 10); A/B-Lauf `tooltips` nicht gemacht |
| O2 | T1–T5 Dashboard-Darstellung | erledigt: T1, T8, statisches Raster statt Laufband; vom Eigentümer am 14.11.2026 als passend bestätigt (Abschnitt 10). T2, T3, T5 nicht begonnen |
| O3 | T6–T8 Dashboard-Hauptthread | offen |
| O4 | T9–T12 gemeinsame Bausteine | T9 implementiert (Wirkung nicht belegt), T29 Umgebungs-Locale implementiert, Nachmessung offen (Abschnitt 10); T28 nur noch für abweichende App-Sprache; T10–T12 offen |
| O5 | T13–T16, T18, T20 Hub-Chancen öffnen | offen |
| O6 | T17, T19 Hub-Tabelle und Invention | T19 teilweise: Messschalter, A/B-Läufe, Eingabefelder erst beim Klick (14.11.2026, nicht nachgemessen); Links, erklärte Zellen und T17 offen |
| O7 | T22, T23, T25, T26 Zustand und Speichern | offen |
| O8 | T24 Blobs und Schema, nur nach Messung | offen |
| O9 | T21 Hub-Scan, nur nach Messung und Entscheid | offen |

## 9. Prompts (einzeln kopierbar)

### Gemeinsamer Vorspann (jedem Prompt voranstellen)

> Arbeite nach AGENTS.md/CLAUDE.md. Lies vorher `git status --short --branch`
> und den vorhandenen Diff; fremde Änderungen bleiben erhalten. Maßgeblich ist
> `Documentation/GESCHWINDIGKEIT_2026-11-13.md`. Ändere keine Rechenregel und
> keinen Datenumfang: Jede Maßnahme liefert dieselben Zahlen, Zeilen und
> Zustände wie vorher; fehlende Daten bleiben ausdrücklich unverfügbar. Der
> Golden-Master-Test des Planers bleibt unverändert grün. Die Optik bleibt
> pixelgleich, außer der Prompt nennt eine freigegebene Änderung. Prüfe die
> Zeilenangaben des Dokuments gegen den aktuellen Stand, bevor du änderst.
> Keine produktiven Benutzerdaten als Testdaten; die echte App des Eigentümers
> wird nie bedient, nur per PID beobachtet. Pflege PRODUCT.md und dev-diary.md
> im selben Schritt; betrifft die Änderung eine Planer-Quelle, prüfe
> `PlannerFlowGuide.swift`, beide `Localizable.strings` und
> `Scripts/check_planner_guide.py`. Prüfe mit `swift test`, `xcodebuild … test`
> (Debug, unsigniert) und `EVEStaticDataKit` separat. Miss vorher und nachher
> mit den Messpunkten aus O1 und nenne die Werte. Bei Unsicherheiten oder
> Unklarheiten nachfragen, statt selbst zu entscheiden. Danach stoppen und
> berichten; geplant, implementiert, automatisch geprüft, live gemessen und
> vom Eigentümer abgenommen getrennt ausweisen. Kein Commit. Trage die
> Ergebnisse in Abschnitt 10 ein, setze den Status in Abschnitt 8 und gib am
> Ende den nächsten Prompt vollständig und kopierfertig aus, einschließlich
> dieses Vorspanns.

### O1 – Messung mit dem Eigentümer (T0)

> Ändere kein Verhalten. Ergänze Messpunkte mit `PerformanceLog`,
> `PerformanceStopwatch` und `PerformanceAccumulator`
> (`Sources/EVENexusCore/Foundation/PerformanceLog.swift`), nur Namen, Dauern
> und Anzahlen:
>
> - `dashboard.body`: Zahl der Auswertungen und Dauer der Identitäten aus D7.
> - `hub.open` je Rolle: Phasen Analyse und Nachfrage, Lager,
>   Reservierungen, jede Projektion (Hintergrund- und Hauptthread-Anteil
>   getrennt), erste sichtbare Tabelle; dazu die Zahl der Projektionen.
> - `hub.visible-candidates`: Aufrufe, Zeilen, Gesamt- und Höchstdauer.
> - `hub.invention` und `hub.contract-references`: Dauer und Typzahl.
>
> Ergänze nur im Debug-Build einen Startschalter (Umgebungsvariable), der
> Panel-Schatten, Laufband und Tooltips der Namen einzeln abschaltet. Er dient
> allein dem A/B-Vergleich und ist im Release-Build nicht vorhanden. Kläre
> vorher den Namen der Variable.
>
> Messe dann mit dem Eigentümer: Er startet den Debug-Build normal mit seinen
> Daten. Zeichne für diese PID auf: `log stream` (Kategorie `performance`),
> `sample <PID>` und die CPU-Last von App und WindowServer. Ablauf, jeweils
> auf Zuruf: (1) Dashboard in Ruhe 15 Sekunden scrollen, (2) dasselbe je
> A/B-Schalter, (3) Main-Hub- und Home-Hub-Chancen je zweimal öffnen,
> (4) Hub-Tabelle scrollen, (5) Lager, Marktbestand und Nettowert je einmal
> öffnen. Frage nach dem Eindruck je Lauf.
>
> Berichte je Lauf die Werte, den Anteil des Hauptthreads und was der
> Eigentümer gesehen hat. Schlage danach die Reihenfolge für O2–O9 vor.

→ Nächster Prompt: O2, sofern die Messung nichts anderes ergibt

### O2 – Dashboard-Darstellung (T1–T5)

> - T1: `NexusPanelSurface` zeichnet den Schatten an der Hintergrundform.
>   Der vorhandene Vergleich in `NexusPanelSurfaceRenderingTests` gegen das
>   handgebaute Panel muss in Hell und Dunkel bestehen. Besteht er nicht
>   bitgleich, stoppe und frage.
> - T2: `HUDCornerBrackets` als Pfad ohne Maske; neuer Rendertest alt gegen
>   neu im HUD-Stil.
> - T3: Kacheln und Pillen des Dashboards als Form-Hintergrund; Rendertest je
>   Muster. Icons mit Bildinhalt behalten ihren Zuschnitt.
> - T4: Das Laufband läuft nur, wenn es sichtbar ist und nicht gescrollt
>   wird; `update` erzwingt kein Layout mehr. „Bewegung reduzieren“ bleibt
>   unverändert. Kläre vorher Entscheid 2.
> - T5 nur, wenn O1 Tooltips oder Popover als Last belegt.
>
> Miss mit den Läufen 1 und 2 aus O1. Die Sichtabnahme macht der Eigentümer.

→ Nächster Prompt: O3

### O3 – Dashboard-Hauptthread (T6–T8)

> - T6: Zerlege `DashboardView` in Panel-Views mit schmalen Eingaben; jede
>   liest nur ihre eigenen `RuntimeState`-Eigenschaften. Inhalt, Reihenfolge,
>   Texte und Accessibility-Kennungen bleiben gleich.
> - T7: Identitäten der `.task(id:)`, `walletPortfolio` und `wealthHistory`
>   werden je Eingabeänderung einmal bestimmt, nach dem Muster von
>   `DashboardAuthorizationCache` und `DashboardWealthHistoryCache`. Jede
>   Änderung der Eingaben muss weiter erkannt werden; Tests dafür.
> - T8: `DashboardCardLayout` nutzt den Layout-Cache.
>
> Tests: gleiche Auslösung der Tasks bei geänderten Eingaben, keine bei
> bloßem Neuzeichnen. Die Dashboard-Tests bleiben grün.

→ Nächster Prompt: O4

### O4 – Gemeinsame Bausteine (T9–T12)

> - T9: `AppLocalization` hält Sprach-Bundle und `Locale` je Sprache und
>   erkennt einen Sprachwechsel sofort. Tests: gleiche Texte in beiden
>   Sprachen, Wechsel zur Laufzeit.
> - T10: Ein gemeinsamer Icon-Lader mit begrenztem Speicher-Cache ersetzt
>   `AsyncImage` in `EVEItemIcon` und im Lager. Gleiche Adressen, gleiche
>   Ersatzreihenfolge, gleiche Platzhalter. Kläre vorher die Obergrenze.
> - T11: Die Namensfarbe wird einmal je Fenster gelesen und über die
>   Umgebung verteilt; eine Änderung in den Einstellungen wirkt sofort.
> - T12: Formatter aus G4 statisch halten.
>
> Regeln „Copyable EVE names“, Bestandsverlauf und Hammer bleiben unverändert;
> `MarketStockHistoryLinkTests` und `PlannerBuildLinkTests` bleiben grün.

→ Nächster Prompt: O5

### O5 – Hub-Chancen öffnen (T13–T16, T18, T20)

> - T13: Die Hintergrund-Projektion rechnet die Zeilenwerte mit den
>   ME/TE-Annahmen und den je Zeile eingegebenen Runs, ME und TE.
>   `visibleCandidates` wird je Projektion, Eingaben und Filter einmal
>   bestimmt, nach dem Muster des Zeilen-Caches im Handel
>   (`TradeView.swift:1159-1203`). Das Dashboard-Top-5 bleibt unverändert,
>   solange Entscheid 1 offen ist.
> - T14: Lager, Reservierungen und Kandidaten bleiben je Hub im Speicher,
>   Schlüssel ist der vollständige Trigger, nach dem Muster von
>   `MainHubOpportunityTopFiveCache`. Nenne den Speicherbedarf.
> - T15: Beim Öffnen eine Projektion statt mehrerer.
> - T16: Vertragsreferenzen je Typmenge; die ID bleibt bei gleichem Inhalt.
> - T18 und T20: Eingaben je `body` und die Nachfrage merken.
>
> Tests: gleiche Tabelle wie vorher für eine feste Eingabe, Neuberechnung bei
> jeder Eingangsänderung, keine bei bloßem Neuzeichnen. Miss mit Lauf 3.

→ Nächster Prompt: O6

### O6 – Hub-Tabelle und Invention (T17, T19)

> - T19: Die Tabellenzeile wird eine eigene View mit vergleichbaren Eingaben.
>   Runs, ME und TE sind Text und werden bei Klick oder Tastaturfokus zum
>   Feld; Aussehen, Tab-Reihenfolge und Accessibility klärst du vorher.
>   Erklärtexte entstehen erst beim Öffnen.
> - T17: Die Inventionsschätzung rechnet abseits des Hauptthreads; Werte und
>   Ablaufzeit bleiben gleich.
>
> Miss mit Lauf 4.

→ Nächster Prompt: O7

### O7 – Zustand und Speichern (T22, T23, T25, T26)

> - T22: `ConsolidationController` löst kein Neuzeichnen von App und
>   Hauptfenster mehr aus; Verhalten der Konsolidierung unverändert.
> - T23: JSON- und Base64-Kodierung des Abgleichs abseits des Hauptthreads;
>   gespeicherte Bytes bleiben gleich.
> - T25: Nettowert wie das Dashboard (Dekodieren im Hintergrund, gefilterte
>   Abfrage).
> - T26: Sortierungen aus G8 je Eingabeänderung einmal. Die Regeln „Sortable
>   data tables“ bleiben erhalten.
>
> Miss mit Lauf 5 und dem Start bis „Charaktere synchronisiert“.

→ Nächster Prompt: O8, nur wenn die Messung G6 belegt

### O8 – Blobs und Schema (T24)

> Miss zuerst, was ein `save()` und eine Abfrage auf `StoredCharacter`
> kosten. Stufe 1 ohne Schemaänderung: Hauptfenster und Seitenleiste fragen
> nur die Felder ab, die sie zeigen. Stufe 2 nur nach Entscheid 4:
> Auslagerung der Blobs mit eigener Migrationsstufe, vorheriger Sicherung und
> Test der Migrationskette. Bundle-ID, Pfade und bestehende Schemas bleiben
> sonst unberührt.

→ Nächster Prompt: O9, nur nach Entscheid 3

### O9 – Hub-Scan (T21)

> Werte zuerst `main-hub-scan` und `esi.summary` aus. Prüfe, ob Hubs
> derselben Region das Regionsbuch im selben Scan doppelt laden, und nutze es
> dann einmal. Parallelität und Wartezeiten nur nach Entscheid 3. Die
> CCP-Regeln aus der App-Analyse, Abschnitt 14, gelten weiter.

→ Ende der Reihe.

## 10. Ergebnisse

Jeder Prompt trägt hier Messwerte, Umfang, Prüfungen und offene Punkte ein.

### O1 (13.11.2026): Messpunkte und Schalter, Messung offen

**Implementiert, ohne Verhaltensänderung:**

- `dashboard.body`, `dashboard.identities`, `dashboard.wallet-portfolio`,
  `dashboard.wealth-history` (`PerformanceAccumulator`, je höchstens eine
  Zeile in fünf Sekunden). Ohne neue Auswertung des Dashboards erscheint
  keine Zeile.
- `hub.open` je Besuch und Rolle (`HubOpenMetrics` in
  `MarketBrowserView.swift`): Phasen `analysis-demand`, `warehouse`,
  `reservations`, jede `projection` mit Hintergrund- und Hauptthread-Dauer,
  `first-table`. Der Hauptthread-Anteil einer Projektion ist das
  Nachrechnen und Sortieren aus H1.
- `hub.visible-candidates`, `hub.invention`, `hub.contract-references`.
- Debug-Schalter `EVE_NEXUS_PERF_DISABLE=shadows,ticker,tooltips`
  (`PerformanceDebugSwitch` in `InterfaceStyleComponents.swift`). Der Name
  folgt den vorhandenen `EVE_NEXUS_…`-Variablen und wurde ohne Rückfrage
  gewählt.

**Automatisch geprüft:** `swift test` grün (801 Core-, 159 App-Tests und die
XCTest-Suiten, darunter die neun Rendertests samt neuem Schaltertest),
`EVEStaticDataKit` 13 Tests, natives `xcodebuild test` (Debug, unsigniert)
`TEST SUCCEEDED`. Die Rendertests belegen, dass ohne Variable jede Fläche
unverändert zeichnet.

**Nicht geprüft:** Die Messzeilen wurden noch in keiner laufenden App
gelesen. Die Schalter wurden nicht in der App angesehen.

**Offen:** der A/B-Vergleich (Lauf 2) und die Eindrücke des Eigentümers je
Lauf.

### O1, erste Messung (13.11.2026, 18:23–18:29 Uhr)

> Xcode-Debug-Build (PID 1597) mit den echten Daten des Eigentümers, rund 23
> Minuten nach dem Start, ohne A/B-Schalter. Der Eigentümer bediente die App;
> aufgezeichnet wurden das Messprotokoll, `sample` (je 8 Sekunden) und `top`
> für App und WindowServer. Ein Debug-Build rechnet langsamer als Release.
> Die Zuordnung der Proben zu den Schritten folgt den Zeitstempeln von
> `hub.open`.

**Dashboard:**

- Beim Scrollen ist der Hauptthread zu 89–99 % belegt. 44–63 % der Zeit
  stecken in `NSHostingView.layout()` → `minSize()` → `sizeThatFits` über
  den ganzen Seitenbaum; darin `DashboardCardLayout.measured` mit 18–20 % und
  die `ViewThatFits`-Varianten mit 17–20 %. Die Seite wird also beim Scrollen
  laufend vollständig neu vermessen. Das war in der Durchsicht nicht
  erkannt (D8 galt als klein).
- `dashboard.body` läuft dabei nicht: drei Auswertungen je Besuch, keine
  während des Scrollens. Die Kennungen kosten je Besuch 6–45 ms
  (`dashboard.identities`, 21 Aufrufe). D6 und D7 sind für das Ruckeln
  nicht die Ursache.
- Der WindowServer braucht 45–58 % CPU, solange das Dashboard sichtbar ist,
  auch in Ruhe bei 0 % App-Last; in den anderen Bereichen 6–25 %, mit
  einzelnen Spitzen bis 49 %. Was davon Schatten und was Laufband ist, zeigt
  erst Lauf 2.
- 3–4 % des Hauptthreads liest die Sprachdatei neu ein
  (`_CFPropertyListCreateWithData`); beim Öffnen der Hub-Chancen sind es bis
  11 %. G1 ist damit schwerer als angenommen: Die Übersetzungstabelle wird
  nicht nur gesucht, sondern wiederholt geparst.

**Hub-Chancen** (`hub.open`, Zeit seit dem Öffnen):

| Besuch | Reservierungen | Lager | 1. Projektion (Hintergrund / Hauptthread) | erste Tabelle | sichtbare Zeilen |
|---|---|---|---|---|---|
| Main, 1. | 1,6 s | 3,4 s | 1.192 ms / 25 ms | 4,7 s | 141 von 221 |
| Home, 1. | 1,3 s | 3,7 s | 221 ms / 96 ms | 4,2 s | 371 von 1.318 |
| Main, 2. | 1,3 s | 4,6 s | 136 ms / 29 ms | 4,9 s | 141 |
| Home, 2. | 7,8 s | 9,4 s | 126 ms / 81 ms | 9,7 s | 371 |

- Die Projektion selbst ist kurz. **H1 ist nicht die Hauptursache:**
  `visibleCandidates` kostet 26–116 ms je Aufruf, weil die Filter die
  4.172 Scanzeilen auf 221 bzw. 1.318 Kandidaten begrenzen.
- Die Wartezeit liegt davor: 1,3–1,6 s bis zum ersten Ergebnis überhaupt
  (einmal 7,8 s) und weitere 1,6–3,3 s bis das Lager bereit ist, obwohl
  dessen Projektion im Cache liegt. Der Hauptthread ist dabei zu 98–100 %
  belegt: Aufbau und Platzierung der Tabellenzeilen (`LazyStack`, 12–50 %),
  `NSHostingView.layout()`/`minSize()` (20–70 %) und in einer Probe 25 %
  `accessibilityHitTest`. Die Hintergrundschritte warten also vor allem auf
  den Hauptthread. Wer die Accessibility-Abfrage auslöst, ist nicht belegt.
- Beim ersten Besuch folgte eine zweite Projektion nach 13,9 s (Hintergrund
  4,2 s), ausgelöst durch die Vertragsreferenzen: `hub.contract-references`
  4,1 s für 6.075 Typen (H4).
- `hub.invention` brauchte beim Start 11,4 s für 999 Typen (H5).

**Eindruck des Eigentümers (13.11.2026):** Die Wartezeiten passen zu dem,
was er gesehen hat, auch die 9,7 s beim zweiten Öffnen der
Home-Hub-Chancen. Der Hub-Bereich ist insgesamt langsam, nicht nur beim
Öffnen. Zum Dashboard-Scrollen liegt aus diesem Lauf kein eigener Eindruck
vor.

**Hub-Scan (beim Start, automatisch):** 49,2 s, davon Orderbuch, Preise und
Indizes 22,4 s, Analyse 1,6 s, Home 5,0 s und Coalition 22,0 s
gleichzeitig; 482 Anfragen, 107 MB, keine Fehler.

**Nicht ausgewertet:** Lager, Marktbestand und Nettowert (Lauf 5) haben
keine eigenen Messpunkte; die Proben zeigen dort 20–83 % Hauptthread-Last,
wieder mit `NSHostingView.layout()` vorn.

### O1, A/B-Lauf ohne Laufband (13.11.2026, 18:42–18:44 Uhr)

> Neuer Prozess (PID 4956) mit `EVE_NEXUS_PERF_DISABLE=ticker`; im
> Protokoll `perf.switches disabled=ticker`. Je Variante ein Lauf. Als
> Scrollen gewertet ist der Abschnitt 18:43:17–18:43:43; der genaue Beginn
> ist nicht belegt.

| | mit Laufband (18:23) | ohne Laufband (18:43) |
|---|---|---|
| Hauptthread beim Scrollen | 89–99 % belegt | 14–31 % |
| davon `NSHostingView.layout()` | 44–63 % | 3–8 % |
| App-CPU beim Scrollen | 43–78 % | 10–17 % |
| WindowServer, Dashboard sichtbar | 45–58 % | 21–42 % |

**Eindruck des Eigentümers:** Ohne Laufband scrollt das Dashboard deutlich
flüssiger.

Das Laufband (D4) ist damit die Hauptursache des Ruckelns im Dashboard: Mit
ihm wird beim Scrollen die ganze Seite laufend neu vermessen, ohne es kaum.
Der Mechanismus ist nicht belegt; naheliegend ist `update` mit
`needsLayout = true` und `layoutSubtreeIfNeeded()`
(`DashboardMineralTickerMarqueeView`) zusammen mit dem `layout()`, das den
Rahmen der inneren `NSHostingView` setzt. Die Hub-Chancen haben kein
Laufband und waren trotzdem voll belegt; dort bremst etwas anderes.

### O1, A/B-Lauf ohne Schatten (13.11.2026, 18:47–18:49 Uhr)

> Neuer Prozess (PID 5268) mit `EVE_NEXUS_PERF_DISABLE=shadows`, Laufband
> aktiv. Ruhe 18:47:50–18:48:24, Scrollen ab etwa 18:48:30.

| | normal (18:23) | ohne Laufband | ohne Schatten |
|---|---|---|---|
| WindowServer in Ruhe, Dashboard sichtbar | 50–68 % (18:03) | 29–34 % (kurz) | 36–44 % |
| WindowServer beim Scrollen | 43–58 % | 21–42 % | 35–51 % |
| Hauptthread beim Scrollen | 89–99 % | 14–31 % | 53–95 % |
| davon `NSHostingView.layout()` | 44–63 % | 3–8 % | 22–38 % |

Die Schatten (D1) kosten im Bildaufbau grob 10–15 Prozentpunkte
WindowServer-Last und ändern am belegten Hauptthread wenig. Auch ohne
Schatten bleibt der WindowServer in Ruhe bei 36–44 %, solange das Laufband
läuft. Reihenfolge der Wirkung also: Laufband deutlich vor Schatten. Der
Eindruck des Eigentümers zu diesem Lauf fehlt.

**Vorschlag zur Reihenfolge nach O1:**

1. O2 mit T4 (Laufband) zuerst, dann T1 (Schatten, pixelgleich), T8 und
   weniger `ViewThatFits`-Varianten; T2, T3 und T5 nur, wenn danach noch
   Bedarf besteht.
2. O4 mit T9 (Lokalisierung) vorziehen, weil das wiederholte Parsen der
   Sprachdatei alle Bereiche trifft.
3. Hub-Chancen: zuerst eine Probe-Auswertung nur für die Tabelle (Aufbau der
   Zeilen, `NSHostingView.minSize()`, Accessibility), dann O6 (T19) vor O5;
   aus O5 zuerst T16 und T14, T13 zuletzt.
4. O3 (Dashboard-Hauptthread) rückt nach hinten: `dashboard.body` ist nicht
   die Ursache.

**Folgerung (Vorschlag, Stand nach dem Laufband-Lauf):** T4 rückt an die
erste Stelle und wird in O2 zuerst umgesetzt. Die folgende Einschätzung zu
T27 stammt aus der ersten Messung und gilt für das Dashboard nur noch
eingeschränkt; für die Hub-Chancen bleibt sie zu prüfen.

**Folgerung aus der ersten Messung:** Vor allen anderen Maßnahmen
steht eine neue: **T27**, das Fenster so begrenzen, dass `NSHostingView`
für seine Mindestgröße nicht den ganzen Inhalt vermisst (vollständig
bestimmter Rahmen an Fenster und Detailspalte; `ContentView.swift:616` setzt
heute nur Mindestwerte), dazu der Layout-Cache in `DashboardCardLayout` (T8)
und weniger `ViewThatFits`-Varianten. Das betrifft alle Bereiche. Danach
T9 (Lokalisierung), T19 (leichtere Tabellenzeilen) und T16; T13 rückt nach
hinten. Die Wirkung von T27 ist eine Annahme aus den Proben und muss in O2
zuerst mit einem Versuch belegt werden.

### O2 (13.11.2026): Laufband, Schatten, Layout-Cache; Nachmessung offen

**Implementiert:**

- **T4:** Die innere `NSHostingView` des Laufbands hat `sizingOptions = []`,
  `update` fordert ein Layout nur noch bei neuem Inhalt oder neuer
  Streifengröße an und erzwingt keines mehr, `layout()` setzt den Rahmen nur
  bei Änderung. Aussehen, Geschwindigkeit und „Bewegung reduzieren“ sind
  unverändert gewollt. Ob das die Ursache aus O1 behebt, ist eine Annahme;
  der Mechanismus wurde nicht nachgestellt.
- **T1:** `NexusPanelSurface` legt den Schatten an die Hintergrundform. Das
  ist **nicht bitgleich**: Bisher warf auch jede Schrift im Panel einen
  schwachen eigenen Schatten, und der Rand wurde minimal anders
  weichgezeichnet. Gemessene Abweichung höchstens 6 von 255 Farbstufen
  (hell) und 2 (dunkel). Der Eigentümer hat die Änderung am 13.11.2026 auf
  Rückfrage freigegeben. Nebenbefund: SwiftUI zeichnete den Schatten also je
  Inhaltselement, nicht für das zusammengesetzte Panel, wie D1 annahm.
- **T8:** `DashboardCardLayout` hält die Kartengrößen je Breite im
  Layout-Cache; Größe, Platzierung und Ausrichtung eines Durchlaufs messen
  nicht mehr jeweils neu.
- T2, T3 und T5 nicht begonnen.

**Automatisch geprüft:** `swift test` grün (801 Core-, 159 App-Tests,
XCTest-Suiten), `EVEStaticDataKit` 13 Tests, `xcodebuild test` (Debug,
unsigniert) `TEST SUCCEEDED`. Der Rendertest vergleicht das neue Panel mit
dem früheren und lässt höchstens 8 Farbstufen Abweichung zu; die
Dashboard-Layouttests sind unverändert grün.

**Nicht geprüft:** Laufband und Panels wurden nach der Änderung in keiner
laufenden App angesehen.

### O2, Nachmessung (13.11.2026, 18:58–19:00 Uhr)

> Neu gebauter Xcode-Debug-Build (PID 6777), kein Schalter, ein Lauf.

| | vor O2 (18:23) | nach O2 | ohne Laufband (O1) |
|---|---|---|---|
| Hauptthread beim Scrollen | 89–99 % | 56–84 % | 14–31 % |
| davon `NSHostingView.layout()` | 44–63 % | 29–32 % | 3–8 % |
| davon `DashboardCardLayout.measured` | 18–20 % | 0–5 % | – |
| WindowServer beim Scrollen | 43–58 % | 35–58 % | 21–42 % |

- **T8 wirkt:** Das mehrfache Vermessen der Karten ist aus den Proben fast
  verschwunden.
- **T4 behebt die Ursache nicht:** Auch ohne Größenbedingungen und ohne
  erzwungenes Layout wird beim Scrollen weiter die ganze Seite neu
  vermessen; es bleiben die `ViewThatFits`-Varianten (11–13 %) und der
  Durchlauf selbst. Die Annahme zum Mechanismus war falsch. Der Auslöser ist
  nicht belegt; die Proben nennen ihn nicht. Vermutung: Schon die
  eingebettete AppKit-Ansicht mit innerer `NSHostingView` in der ScrollView
  fordert je Scroll-Schritt ein Fenster-Layout an.
- **T1:** Am WindowServer ist in diesem einen Lauf keine klare Wirkung zu
  sehen (Ruhe 48–64 % in den ersten Sekunden, danach 35–44 % beim Scrollen).
  Nicht belegt.

**Offen:** Entscheid 2 (wie mit dem Laufband weiter), Eindruck und
Sichtabnahme des Eigentümers.

### O2, Laufband neu gebaut (13.11.2026), Nachmessung offen

Eigentümerentscheid zu Entscheid 2: Laufband als reines SwiftUI neu bauen,
bei fehlender Wirkung statische Zeile. **Implementiert:**
`DashboardMineralTickerMarquee` ist eine SwiftUI-Ansicht mit
`TimelineView(.animation)` und `offset`; `NSViewRepresentable` und
`DashboardMineralTickerMarqueeView` sind entfernt. Umlauf weiter 32
Sekunden, „Bewegung reduzieren“ unverändert. **Automatisch geprüft:**
`swift test` (801 Core-, 160 App-Tests, XCTest-Suiten), `EVEStaticDataKit`
13 Tests, `xcodebuild test` `TEST SUCCEEDED`; neuer Test für die Phase.
**Nicht geprüft:** nicht in der App angesehen, nicht gemessen. Offen:
Nachmessung, Sichtabnahme (Tempo, Aussehen, Klick auf Namen), Dauerlast des
Tickers in Ruhe.

### O2, Nachmessung des SwiftUI-Laufbands (13.11.2026, 23:10–23:12 Uhr)

> Xcode-Debug-Build (PID 7913), kein Schalter, ein Lauf: erst Ruhe, dann
> Scrollen. Ein Lauf um 23:02 Uhr ist verworfen (der Eigentümer hatte nicht
> gescrollt und die App beendet).

| | vor O2 | SwiftUI-Laufband | ohne Laufband (O1) |
|---|---|---|---|
| Hauptthread, Ruhe und Scrollen | 89–99 % nur beim Scrollen | 98–99 % durchgehend | 14–31 % beim Scrollen |
| App-CPU | 0–3 % in Ruhe, 43–78 % beim Scrollen | 47–76 % durchgehend | 10–17 % beim Scrollen |
| davon `NSHostingView.layout()` | 44–63 % | 21–40 % | 3–8 % |
| WindowServer | 45–58 % | 14–66 %, meist 25–50 % | 21–42 % |

**Eindruck des Eigentümers:** Das Scrollen fühlt sich flüssiger an, das
Laufband läuft wie gewohnt, die Namen darin lassen sich anklicken, die
Panels sehen aus wie vorher.

**Widerspruch zwischen Eindruck und Messung:** Gefühlt ist es besser,
gemessen belegt das SwiftUI-Laufband den Hauptthread jetzt dauerhaft, auch
in Ruhe, solange das Dashboard sichtbar und die App im Vordergrund ist. Jedes
Bild der Animation löst ein Fenster-Layout aus. Die frühere Fassung
kostete in Ruhe keine App-CPU. Warum es sich trotzdem flüssiger anfühlt, ist
nicht belegt.

**Erkenntnis:** Nicht die AppKit-Einbettung ist die Ursache, sondern dass
jede SwiftUI-Aktualisierung des Fensters `NSHostingView.layout()` mit dem
Vermessen der ganzen Seite auslöst. Das stützt T27 als eigentliche
Maßnahme, auch für die Hub-Chancen.

**Offen:** Entscheidung des Eigentümers, ob das SwiftUI-Laufband bleibt,
die statische Zeile kommt oder zuerst T27 versucht wird.

### T27, Versuch (13.11.2026): nicht bestätigt

Eigentümerentscheid: zuerst T27 versuchen. **Ergebnis: Die Maßnahme trägt
nicht.**

- Versuchsaufbau als temporärer Test (nicht im Repository): Fenster mit
  `NavigationSplitView`, ScrollView, `ViewThatFits`-Zeilen und einer
  `TimelineView`-Animation, sechs Rahmenvarianten an Fenster und
  Detailspalte sowie `sizingOptions = []`. Die Zeit im Fenster-Layout war in
  allen Varianten gleich (0,05–0,07 s in 2 s). Der Aufbau stellt das teure
  Vermessen der echten Seite nicht nach; ein Rahmen an der Wurzel ändert
  dort nichts.
- Die Probe der echten App mit dem SwiftUI-Laufband (23:11 Uhr) zeigt
  zudem, dass dort nicht die Mindestgröße kostet: Je Bild der Animation
  läuft ein vollständiger SwiftUI-Durchlauf des Fensters (Aktualisieren und
  Zeichnen 24 %), dazu das Erneuern der Mausbereiche mit Treffertests
  (17–20 %) und das Übertragen an den Bildaufbau. Bei 120 Bildern je
  Sekunde füllt das den Hauptthread.
- Das Vermessen über `minSize()` trat nur in der früheren
  Core-Animation-Fassung beim Scrollen auf; T8 hat den größten Anteil davon
  beseitigt.

**Folgerung:** Eine Animation in dieser großen, nicht-lazy Seite kostet je
Bild einen ganzen Fensterdurchlauf, gleich wie sie gebaut ist. Wege: das
Laufband seltener aktualisieren (zum Beispiel 30 statt 120 Bilder je
Sekunde; Wirkung nicht gemessen) oder die statische Zeile (gemessen). T27
entfällt.

### O2, Laufband entfernt (13.11.2026)

Eigentümerentscheid zu Entscheid 2: statische Preise ohne Bewegung und ohne
Scrollen; bei zu wenig Breite eine weitere Zeile. **Implementiert:**
`DashboardMineralTicker` ist ein festes, umbrechendes Raster (`LazyVGrid`,
adaptive Spalten ab 300 pt); Laufband, `TimelineView`, die Phase samt Test
und der Schalter `ticker` sind entfernt, die feste Höhe von 62 pt ebenfalls.
Inhalt je Mineral unverändert: Name mit Icon und Links, Stückpreis, Kaufort.
„Bewegung reduzieren“ hat keine eigene Fassung mehr. **Automatisch
geprüft:** `swift test` (801 Core-, 159 App-Tests, XCTest-Suiten),
`EVEStaticDataKit` 13 Tests, `xcodebuild test` (Debug, unsigniert)
`TEST SUCCEEDED`. **Nicht geprüft:** nicht in der App angesehen,
nicht gemessen. **Offen:** Nachmessung und Sichtabnahme (Umbruch bei
schmalem Fenster, Abstände).

### O2, Nachmessung des statischen Rasters (14.11.2026, 00:08–00:09 Uhr)

> Xcode-Debug-Build (PID 10791, Build 23:53 Uhr), kein Schalter, ein kurzer
> Lauf. Als Scrollen gewertet ist 00:08:50–00:09:03, als Ruhe
> 00:08:42–00:08:48; die Zuordnung folgt der CPU-Last und ist nicht belegt.

| | vor O2 | statisches Raster |
|---|---|---|
| Hauptthread beim Scrollen | 89–99 % | 17 % (eine Probe) |
| davon `NSHostingView.layout()` | 44–63 % | 3 % |
| App-CPU beim Scrollen | 43–78 % | 16–30 % |
| App-CPU in Ruhe | 0–3 % | 3–11 % (kurz) |
| WindowServer beim Scrollen | 43–58 % | 34–49 % |

Die ersten zwölf Sekunden (App 28–69 %, Hauptthread 77 %, davon Layout
52 %) passen zu einer Größenänderung des Fensters, nicht zum Scrollen; nicht
belegt. Der WindowServer bleibt hoch; was ihn außer der App belastet, ist
nicht untersucht.

**Eigentümer (14.11.2026):** „Passt“, Auftrag zum Commit. Einzelpunkte
(Umbruch, Kopieren der Namen) sind nicht einzeln bestätigt.

### O4, T9 Lokalisierung (14.11.2026), Nachmessung offen

**Implementiert:** `AppLanguage` hält je Sprache das Sprach-Bundle und die
`Locale` als statische Tabelle (`AppLanguage.swift`). Ursache des
wiederholten Parsens aus O1: Das je Aufruf erzeugte `Bundle` wurde wieder
freigegeben und mit ihm die eingelesene Übersetzungstabelle. Die aktuelle
Sprache wird weiter je Aufruf aus den Einstellungen gelesen, ein
Sprachwechsel wirkt also sofort. **Automatisch geprüft:** `swift test`
(801 Core-, 160 App-Tests, XCTest-Suiten), `EVEStaticDataKit` 13 Tests,
`xcodebuild test` (Debug, unsigniert) `TEST SUCCEEDED`; neuer Test für beide Sprachen, fehlende Schlüssel und die Locale.
**Nicht geprüft:** nicht in der App angesehen, kein Sprachwechsel in der
laufenden App, nicht gemessen. **Offen:** Nachmessung
(`_CFPropertyListCreateWithData` in den Proben, vorher 3–11 %).

### O4, T9 Nachmessung (14.11.2026, 09:19–09:21 Uhr): keine Wirkung belegt

> Xcode-Debug-Build (PID 15524, Build 09:18 Uhr mit T9), kein Schalter.
> Der Eigentümer öffnete die Hub-Chancen; Dashboard und Sprachwechsel
> entfielen.

- `_CFPropertyListCreateWithData` liegt in den fünf Proben weiter bei
  3–9 % des Hauptthreads (O1: 3–11 %). **T9 hat das wiederholte Einlesen
  nicht beseitigt.**
- **Ursache gefunden:** Das Einlesen kommt nicht aus `AppLocalization`,
  sondern aus SwiftUI selbst. Jeder `Text` mit Schlüssel wird über
  `-[NSBundle localizedAttributedStringForKey:value:table:localization:]`
  für die Sprache der Umgebung (`\.locale`) aufgelöst; dieser Weg liest die
  Übersetzungstabelle je Auflösung neu ein (`_copyStringTable` →
  `_loadStringsFromData`). Die Annahme zu G1 war damit nur zum Teil richtig.
  Ob der Weg nur dann so teuer ist, wenn die App-Sprache von der
  Systemsprache abweicht, ist nicht geprüft.
- T9 bleibt als unschädliche Vereinfachung im Code; ein Nutzen ist nicht
  gemessen.
- Hub-Chancen in diesem Lauf: Home, erste Tabelle nach 3,5 s (Lager 3,0 s,
  Projektion 191 ms Hintergrund, 95 ms Hauptthread); Hauptthread durchgehend
  89–100 % belegt, `NSHostingView.layout()` 26–71 %.

**Neue Maßnahme T28 (offen, braucht einen Eigentümerentscheid):** die
bevorzugte Sprache des App-Bundles an die App-Sprache binden (zum Beispiel
`AppleLanguages` beim Start), damit SwiftUI die zwischengespeicherte Tabelle
nutzt. Das wirkt erst nach einem Neustart und stellt auch Systemdialoge der
App auf die App-Sprache um; die Wirkung ist eine Annahme.

### Hub-Chancen und T29 Umgebungs-Locale (14.11.2026), Nachmessung offen

**Aufschlüsselung der Hub-Proben (09:20 Uhr):** Beim Scrollen der Tabelle
steckt der Hauptthread im Anlegen und Vermessen neuer Zeilen (`LazyStack`
27 %, `applyNodes` 22 %). Darin löst SwiftUI die übersetzten Texte der
Zeilen auf (`LocalizedStringKey.resolve`, 8–12 %) und liest dabei die
Sprachdatei neu ein. Dazu kommen rund 7 % `accessibilityHitTest`; der
Auslöser ist nicht belegt.

**Versuch (temporärer Test, nicht im Repository):** 300 `Text` mit
Schlüssel zeichnen.

| Umgebung | Dauer |
|---|---|
| keine `\.locale` gesetzt | 0,024 s |
| `\.locale` = Systemlocale (`de_DE`, auch `Locale.current`) | 0,023 s |
| `\.locale` = `de` | 1,07 s |
| `\.locale` = `en` | 0,81 s |
| Text bereits übersetzt (`AppLocalization`, verbatim) | 0,019 s |

Sobald die Umgebungs-Locale von der Systemlocale abweicht, kostet jeder
Text rund 3 ms statt 0,08 ms. Die App setzte bisher immer die reine
Sprach-Locale (`de`), auch bei deutschem System.

**Implementiert (T29):** `AppLanguage.environmentLocale` gibt die
Systemlocale zurück, wenn App-Sprache und Systemsprache übereinstimmen und
das Bundle diese Sprache bevorzugt; sonst wie bisher die Sprach-Locale.
Alle fünf Stellen, die `\.locale` setzen, nutzen sie. Die Texte bleiben
gleich; von SwiftUI selbst formatierte Werte folgen damit der Region des
Systems (`de_DE` statt `de`). Die App formatiert ihre Zahlen überwiegend mit
`AppLocalization.currentLanguage.locale`; das bleibt unverändert.

**Automatisch geprüft:** `swift test` (801 Core-, 161 App-Tests,
XCTest-Suiten), `EVEStaticDataKit` 13 Tests, `xcodebuild test` (Debug,
unsigniert) `TEST SUCCEEDED`; neuer Test für die Auswahl der Locale. **Nicht geprüft:** nicht in der App angesehen, nicht gemessen, kein
Sprachwechsel bedient. **Offen:** Nachmessung der Hub-Chancen; T28 bleibt
nur für den Fall, dass die App-Sprache von der Systemsprache abweicht.

### T29, Nachmessung (14.11.2026, 09:49–09:51 Uhr)

> Xcode-Debug-Build (PID 17003, Build 09:48 Uhr), App-Sprache Deutsch auf
> deutschem System (Angabe des Eigentümers), kein Schalter. Die
> Main-Hub-Chancen waren schon während des Hub-Scans offen; ein
> vergleichbarer Öffnen-Wert liegt nur für Home vor.

| Hauptthread, Hub-Chancen | vor T29 (09:20) | mit T29 |
|---|---|---|
| `LocalizedStringKey.resolve` | 8–12 % | 0 % |
| `_CFPropertyListCreateWithData` | 3–9 % | unter 2 %, in keiner Probe gelistet |
| belegt insgesamt | 89–100 % | 90–100 % |
| `NSHostingView.layout()` | 26–71 % | 26–54 % |
| Zeilen anlegen und platzieren | 22–27 % | 9–30 % |

- **T29 wirkt wie im Versuch:** Die Textauflösung mit erneutem Einlesen der
  Sprachdatei ist aus den Proben verschwunden.
- **Der Hub-Bereich bleibt ausgelastet:** Der Hauptthread ist beim Scrollen
  weiter zu 90–100 % belegt. Übrig sind das Anlegen und Vermessen der
  Tabellenzeilen und das Fenster-Layout; dazu 2–13 %
  `accessibilityHitTest` (Auslöser nicht belegt).
- Home-Hub: erste Tabelle nach 3,3 s (09:20 Uhr: 3,5 s); der Unterschied
  liegt in der Streuung.

**Eindruck des Eigentümers (14.11.2026):** Der Hub-Bereich ist unverändert
zäh.

**Offen:** nächste Maßnahme für die Hub-Tabelle (T19: leichtere Zeilen).

### T19, Vorbereitung (14.11.2026): Messschalter für die Hub-Zeilen

Die Proben nennen in der Hub-Tabelle keinen einzelnen Verursacher: 23 % der
Eigenzeit liegen in der Swift-Laufzeit (Typ-Metadaten und
Konformitätssuche), 16 % in SwiftUI, 14 % im Abhängigkeitsgraphen;
`NSTextField` taucht nicht auf. Jede erklärte Zelle trägt zudem einen
eigenen Schatten, vier je Zeile. Vor dem Umbau der Zeilen klärt deshalb ein
A/B-Vergleich, welcher Teil kostet. **Implementiert, nur im Debug-Build:**
`EVE_NEXUS_PERF_DISABLE` kennt zusätzlich `rowfields` (Runs/ME/TE als Text),
`rowexplain` (erklärte Zellen ohne Knopf, Schatten und Popover) und
`rowlinks` (Produktname ohne Verlaufs- und Hammer-Link). Ohne Variable ist
die Tabelle unverändert. **Automatisch geprüft:** `swift test` grün.
**Nachtrag 14.11.2026, 20:56 Uhr:** `EVEStaticDataKit` und `xcodebuild test`
(Debug, unsigniert) für diesen Stand grün.

### T19, A/B-Lauf mit allen drei Zeilen-Schaltern (14.11.2026, 15:48–15:50 Uhr)

> Xcode-Debug-Build (PID 19643, Build 12:05 Uhr), App-Sprache Deutsch,
> `EVE_NEXUS_PERF_DISABLE=rowfields,rowexplain,rowlinks`. Ein Lauf, zehn
> Proben zu je 8 s. Drei frühere Aufzeichnungen desselben Tages (12:07,
> 14:12, 15:25 Uhr) erfassten nur Leerlauf und sind verworfen. Der Eindruck
> des Eigentümers zu diesem Lauf liegt nicht vor.

| Hauptthread beim Scrollen, Main-Hub | ohne Schalter (09:49) | alle drei Schalter |
|---|---|---|
| belegt insgesamt | 90–100 % | 85–86 % |
| `NSHostingView.layout()` | 26–54 % | 15 % |
| Zeilen anlegen und platzieren | 9–30 % | 4–5 % |
| `CA::Transaction::commit()` | nicht ausgewiesen | 19–21 % |
| Abfrage „Element unter dem Mauszeiger“ (`CopyElementAtPosition`) | 2–13 % (`accessibilityHitTest`) | 6–17 % |
| Menüleisten-Symbol neu zeichnen (`NSStatusItem _updateReplicants`) | nicht ausgewiesen | 5–14 % |

- **Die Zeile ist leichter, der Hauptthread bleibt voll:** Ohne Felder,
  erklärte Zellen und Links sinken Zeilenaufbau und Fenster-Layout auf etwa
  ein Drittel. Die Gesamtbelegung fällt aber nur von 90–100 % auf rund
  85 %. Ein Umbau der Zeilen allein beseitigt die Last also nicht.
- **Herkunft von `accessibilityHitTest` belegt:** Die Abfrage kommt von
  außen über die Bedienungshilfen-Schnittstelle (`mshMIGPerform` →
  `_AXXMIGCopyElementAtPosition`). Ein anderes Programm fragt während des
  Scrollens laufend, welches Element unter dem Mauszeiger liegt; SwiftUI
  baut dafür jedes Mal den Bedienungshilfen-Baum der Ansicht auf
  (`ViewRendererHost.accessibilityNodes`). Welches Programm fragt, zeigt die
  Probe nicht. Zum Messzeitpunkt liefen unter anderem Logi Options+, Magnet
  und zwei Computer-Use-Dienste; keines davon ist als Auslöser belegt.
- **Neu: Menüleisten-Symbol.** Solange „im Hintergrund weiterlaufen“ aktiv
  ist, zeichnet AppKit das Symbol der App in der Menüleiste während des
  Scrollens immer wieder neu, samt Bildschirmkopie des Symbols. Auslöser
  nicht belegt; das Symbol selbst ist ein festes Bild.
- **Home-Hub:** Direkt nach dem Öffnen kostet die Höhenschätzung der
  Zeilenliste (`makeEstimatedAnchorTranslation` über 381 Zeilen) 25 % einer
  Probe. Während des Besuchs lief die Inventionsschätzung 31,2 s, davon
  4–11 % der Proben auf dem Hauptthread; sie löste nach 12,5 s eine zweite
  Projektion aus. Die Scroll-Werte für Home sind dadurch überlagert und
  nicht mit 09:49 Uhr vergleichbar.
- **Öffnen:** Main erste Tabelle nach 0,42 s, Home nach 0,68 s (Lager
  0,38 s). Der Wert von 09:49 Uhr (3,3 s, davon Lager 3,0 s) war der erste
  Besuch nach dem Start; der Unterschied ist deshalb nicht den Schaltern
  zuzuschreiben. Vertragsreferenzen 7,0 s, parallel zum Öffnen.
- CPU laut `top` beim Scrollen: App 50–60 %, Spitzen 90–138 %;
  WindowServer 7–15 %.

**Offen:** Eindruck des Eigentümers; welcher der drei Schalter den Gewinn
bringt (Einzelläufe); Auslöser der Bedienungshilfen-Abfrage und des
Menüleisten-Neuzeichnens; Inventionsschätzung abseits des Hauptthreads
(T17).

**Eindruck des Eigentümers (14.11.2026):** Mit den drei Zeilen-Schaltern
kaum ein Unterschied beim Scrollen.

**Nachtrag, Aufrufkette des Menüleisten-Symbols (aus der Probe 15:49:04):**
Ein verzögerter AppKit-Aufruf zeichnet die Kopien des Symbols neu
(`_updateReplicants`), setzt dabei das Erscheinungsbild der Schaltfläche,
SwiftUI beobachtet diese Änderung (`MenuBarExtraController.observeValue`)
und setzt daraufhin Bild und Titel der Schaltfläche erneut
(`updateButton` → `_adjustLength`). Die Kette liegt vollständig in AppKit
und SwiftUI; App-Code kommt darin nicht vor. In Ruhe tritt sie nicht auf
(Hauptthread 0–1 %). Was sie beim Scrollen anstößt, ist nicht belegt.

**Nächster Lauf (geplant):** dieselbe App-Instanz, „im Hintergrund
weiterlaufen“ aus und Logi Options+ beendet. Die Proben zeigen beide
Posten getrennt.

### T19, Lauf mit Mausrad und Rollbalken (14.11.2026, 21:20–21:21 Uhr)

> Dieselbe App-Instanz (PID 19643, weiter mit den drei Zeilen-Schaltern),
> Main-Hub-Chancen, Logi Options+ lief (ließ sich nicht beenden). Ein Lauf,
> fünf Proben zu je 8 s. Die Zuordnung der Phasen folgt der Reihenfolge der
> Anleitung (erst Mausrad, dann Rollbalken); der Eindruck des Eigentümers
> liegt nicht vor.

| Hauptthread, Main-Hub | 15:49 Uhr | Mausrad (21:20:07–21:20:36) | Rollbalken ziehen (21:20:39–21:20:57) |
|---|---|---|---|
| belegt insgesamt | 85–86 % | 56–64 % | 91–94 % |
| `CA::Transaction::commit()` | 19–21 % | 17–26 % | 53–54 % |
| `NSHostingView.layout()` | 15 % | 16–22 % | 45–46 % |
| Zeilen anlegen und platzieren | 4–5 % | 3–4 % | 8–11 % |
| Abfrage „Element unter dem Mauszeiger“ | 6–17 % | unter 2 % | unter 2 % |
| Menüleisten-Symbol neu zeichnen | 5–14 % | 3–5 % | 6–7 % |

- **Die Abfrage von außen fehlt in diesem Lauf**, mit dem Mausrad wie mit
  dem Rollbalken, obwohl Logi Options+ lief. Logi Options+ ist damit als
  Auslöser nicht bestätigt. Was am Nachmittag fragte, bleibt unbelegt; die
  Last ist nicht dauerhaft vorhanden.
- **Ohne die Abfrage ist der Hauptthread beim Mausrad nicht mehr voll:**
  56–64 % statt 85 %.
- **Rollbalken ziehen ist die teuerste Art:** Fenster-Layout 45 %,
  Gesamtbelegung über 90 %. Beim Ziehen springt die Liste über viele Zeilen
  und schätzt deren Höhen neu (`LazyHVStack.lengthAndSpacing`).
- **Menüleisten-Symbol weiter in den Proben** (3–7 %). Ob „im Hintergrund
  weiterlaufen“ in diesem Lauf ausgeschaltet war, ist nicht bestätigt.

**Offen:** Eindruck des Eigentümers; Stand der Einstellung „im Hintergrund
weiterlaufen“ in diesem Lauf; Vergleich ohne Zeilen-Schalter unter denselben
Bedingungen (ohne die Abfrage von außen).

**Eindruck des Eigentümers (14.11.2026, Lauf 21:20 Uhr):** Scrollen mit dem
Mausrad flüssiger als am Nachmittag.

### T19, Vergleichslauf mit normaler Tabelle (14.11.2026, 21:36–21:38 Uhr)

> Neu gestarteter Xcode-Debug-Build (PID 97422, 21:35 Uhr), kein Schalter,
> Main-Hub-Chancen, Mausrad. Die Ansicht wurde schon während des Hub-Scans
> geöffnet (Scan-Ende 21:36:58); gewertet sind die Proben danach.

| Hauptthread, Main-Hub, Mausrad | schlichte Zeilen (21:20) | normale Tabelle, Probe ohne Abfrage (21:37:41) | normale Tabelle, Proben mit Abfrage |
|---|---|---|---|
| belegt insgesamt | 56–64 % | 64 % | 58–100 % |
| `NSHostingView.layout()` | 16–22 % | 27 % | 11–32 % |
| Zeilen anlegen und platzieren | 3–4 % | 11 % | 4–14 % |
| Abfrage „Element unter dem Mauszeiger“ | unter 2 % | unter 2 % | 5–34 % |

- **Die Abfrage von außen war wieder da** und kostete in einzelnen Proben
  bis zu 34 % des Hauptthreads; mit ihr steigt die Belegung auf 97–100 %.
  Sie kommt und geht zwischen den Läufen, ohne dass an der App etwas
  geändert wurde.
- **Zeilen:** In der einen Probe ohne Abfrage kostet die normale Tabelle
  rund 8 Punkte mehr Zeilenaufbau und 5–11 Punkte mehr Layout als die
  schlichte. Das ist ein Einzelwert.
- **Eindruck des Eigentümers:** nicht so flüssig wie der Lauf von 21:20 Uhr.
  Der Unterschied lässt sich wegen der Abfrage nicht den Zeilen allein
  zuschreiben.

**Offen:** das fragende Programm benennen (Proben der in Frage kommenden
Programme während des Scrollens); danach ein sauberer Vergleich normale
gegen schlichte Zeilen.

### Auslöser der Bedienungshilfen-Abfrage: Magnet (14.11.2026, 21:39–21:41 Uhr)

> Parallel zur App (PID 97422, normale Tabelle, Mausrad in den
> Main-Hub-Chancen) wurden neun in Frage kommende Programme je 6 s
> beprobt: Logi Options+ (Agent und Updater), Magnet, Claude, ChatGPT,
> SkyComputerUseService, WindowManager, universalaccessd,
> AccessibilityUIServer. Nur beobachtet, nichts beendet oder verändert.

- **Live gemessen:** Nur Magnet (Fensterverwaltung) ruft
  `_AXUIElementCopyElementAtPositionIncludeIgnored` auf, aus einem
  entprellten Combine-Abonnement. In den Proben während des Scrollens
  (21:40:30–21:41:26) stehen 989–3013 von rund 6000 Stichproben eines
  Magnet-Threads in diesem Aufruf, in den Proben davor 2–42. In keinem
  anderen Kandidaten kommt der Aufruf als Anfragender vor.
- In denselben Sekunden zeigt die App die Gegenseite: 9–17 % des
  Hauptthreads in `CopyElementAtPosition` →
  `ViewRendererHost.accessibilityNodes`.
- **Einordnung:** Magnet fragt, welches Element unter dem Mauszeiger liegt;
  die App beantwortet jede Anfrage auf dem Hauptthread und baut dafür den
  Bedienungshilfen-Baum der großen Hub-Ansicht auf. Das erklärt die
  2–34 % in den Läufen des Tages. Warum Magnet im Lauf von 21:20 Uhr nicht
  fragte, ist nicht belegt.
- Die Ursache liegt außerhalb der App. Eine Gegenmaßnahme in der App ist
  nicht geplant; ob es eine gibt (billigerer Bedienungshilfen-Baum), ist
  nicht untersucht.

**Offen:** Gegenprobe des Eigentümers mit beendetem Magnet oder mit der App
auf Magnets Ausnahmeliste; danach sauberer Vergleich normale gegen
schlichte Zeilen.

### Gegenprobe ohne Magnet (14.11.2026, 21:43 Uhr)

> Dieselbe App-Instanz (PID 97422, normale Tabelle), Magnet beendet (vom
> Eigentümer; per Prozessliste bestätigt), Mausrad in den
> Main-Hub-Chancen. Nur eine Probe mit Scroll-Last (21:43:22–21:43:30);
> der Eindruck des Eigentümers liegt nicht vor.

| Hauptthread, normale Tabelle | mit Magnet (21:37–21:41) | ohne Magnet (eine Probe) |
|---|---|---|
| Abfrage „Element unter dem Mauszeiger“ | 5–34 % | 0 % (kein Aufruf in der Probe) |
| belegt insgesamt | 58–100 % | 95 % |
| `NSHostingView.layout()` | 9–32 % | 62 % |
| Zeilen anlegen und platzieren | 2–14 % | 18 % |
| Darstellung aufbauen (`render`) | 3–5 % | 14 % |

- **Magnet als Auslöser bestätigt:** Ohne Magnet kommt die Abfrage in der
  Probe nicht mehr vor.
- **Die Tabelle lastet den Hauptthread auch allein aus:** Die frei
  gewordene Zeit füllt das Fenster-Layout (62 %), darin 18 % für das
  Anlegen und Platzieren der Zeilen. Die Belegung hängt davon ab, wie
  schnell gescrollt wird; die Prozentwerte verschiedener Läufe sind deshalb
  nur grob vergleichbar. Ein Einzelwert.
- Folgerung für T19: Die Abfrage von außen war ein zusätzlicher Posten,
  nicht die Ursache. Der Umbau der Zeilen bleibt nötig; die schlichten
  Zeilen hatten Zeilenaufbau und Layout auf etwa ein Drittel gesenkt.

**Offen:** Eindruck des Eigentümers; Einzelläufe je Zeilen-Schalter ohne
Magnet.

**Eindruck des Eigentümers (14.11.2026, Gegenprobe 21:43 Uhr):** Ohne
Magnet scrollt die normale Tabelle flüssiger.

### T19, Einzellauf `rowexplain` (14.11.2026, 21:49–21:50 Uhr)

> Xcode-Debug-Build (PID 99234, 21:48 Uhr), `EVE_NEXUS_PERF_DISABLE=rowexplain`
> (im Protokoll bestätigt), Magnet beendet, Main-Hub-Chancen, Mausrad. Neun
> Proben mit Scroll-Last; der Eindruck des Eigentümers liegt nicht vor.

| Hauptthread, Main-Hub, Mausrad, ohne Abfrage von außen | normale Tabelle (1 Probe) | nur `rowexplain` (9 Proben) | alle drei Schalter (3 Proben, 21:20) |
|---|---|---|---|
| belegt insgesamt | 95 % | 28–93 %, Mitte 77 % | 56–64 % |
| `NSHostingView.layout()` | 62 % | 7–45 %, Mitte 32 % | 16–22 % |
| Zeilen anlegen und platzieren | 18 % | 3–29 %, Mitte 13 % | 3–4 % |

- **`rowexplain` allein bringt den Gewinn nicht:** Zeilenaufbau und Layout
  liegen nahe an der normalen Tabelle und deutlich über dem Lauf mit allen
  drei Schaltern. Der Hauptteil muss bei den Eingabefeldern (`rowfields`)
  oder den Links am Namen (`rowlinks`) liegen.
- Die Werte streuen stark mit der Scroll-Geschwindigkeit; verglichen wird
  deshalb die Größenordnung, nicht der einzelne Prozentwert.

**Offen:** Einzelläufe `rowfields` und `rowlinks`.

### T19, Einzellauf `rowfields` (14.11.2026, 21:56–21:58 Uhr)

> Xcode-Debug-Build (PID 99620, 21:52 Uhr), `EVE_NEXUS_PERF_DISABLE=rowfields`
> (in der Prozessumgebung bestätigt), Magnet beendet, Main-Hub-Chancen,
> Mausrad. Acht Proben mit Scroll-Last, davon vier mit über 50 %
> Belegung; der Eindruck des Eigentümers liegt nicht vor.

| Hauptthread, stärker belastete Proben | nur `rowexplain` | nur `rowfields` | alle drei Schalter |
|---|---|---|---|
| belegt insgesamt | 77–93 % | 60–80 % | 56–64 % |
| `NSHostingView.layout()` | 32–45 % | 18–25 % | 16–22 % |
| Zeilen anlegen und platzieren | 13–29 % | 7–10 % | 3–4 % |
| Menüleisten-Symbol neu zeichnen | 2–8 % | 4–14 % | 3–5 % |

- **Die Eingabefelder sind der größte der drei Posten:** Ohne sie fällt das
  Fenster-Layout fast auf den Wert des Laufs mit allen drei Schaltern, der
  Zeilenaufbau auf etwa die Hälfte.
- Der Rest des Zeilenaufbaus (7–10 % gegen 3–4 %) liegt bei den Links am
  Namen oder den erklärten Zellen.
- Das Menüleisten-Symbol kostet in diesem Lauf bis zu 14 %; es ist nach
  dem Wegfall der Abfrage von außen der größte Posten außerhalb der
  Tabelle.

**Offen:** Einzellauf `rowlinks`.

### T19, Einzellauf `rowlinks` und Zusammenfassung (14.11.2026, 22:08–22:10 Uhr)

> Xcode-Debug-Build (PID 201, 22:06 Uhr), `EVE_NEXUS_PERF_DISABLE=rowlinks`
> (in der Prozessumgebung bestätigt), Magnet beendet, Main-Hub-Chancen,
> Mausrad. Neun Proben mit Scroll-Last; der Eindruck des Eigentümers liegt
> nicht vor.

| Hauptthread, stärker belastete Proben, ohne Abfrage von außen | normal (1 Probe) | nur `rowexplain` | nur `rowfields` | nur `rowlinks` | alle drei |
|---|---|---|---|---|---|
| belegt insgesamt | 95 % | 77–93 % | 60–80 % | 60–73 %, einmal 93 % | 56–64 % |
| `NSHostingView.layout()` | 62 % | 32–45 % | 18–25 % | 17–33 % | 16–22 % |
| Zeilen anlegen und platzieren | 18 % | 13–29 % | 7–10 % | 5–10 % | 3–4 % |

- **Eingabefelder und Links am Namen bringen je etwa gleich viel**, die
  erklärten Zellen am wenigsten. Eine Rangfolge zwischen Feldern und Links
  geben die Läufe nicht her: Die Werte hängen von der Scroll-Geschwindigkeit
  ab, die zwischen den Läufen nicht gleich war.
- Belastbar ist die Größenordnung: Jeder der beiden Teile allein senkt den
  Zeilenaufbau auf etwa die Hälfte, beide zusammen mit den erklärten Zellen
  auf etwa ein Fünftel der normalen Tabelle.
- **Grenze der Methode:** Für eine genauere Aufteilung taugen weitere
  Läufe von Hand nicht. Dafür wäre ein automatischer Zeitvergleich nötig,
  der dieselben Zeilen in allen Varianten gleich oft aufbaut.

**Folgerung für T19 (geplant, nicht begonnen):** zuerst die Eingabefelder
(Runs, ME, TE erst beim Klick als Feld, Aussehen und Tabulator-Reihenfolge
unverändert), dann die Links am Namen leichter bauen, ohne dass Kurvensymbol
und Hammer wegfallen (Eigentümerregeln „Bestandsverlauf je Item“ und „Bauen
im Planer je Item“ bleiben). Die erklärten Zellen zuletzt.

### T19, Umsetzung Teil 1: Eingabefelder erst beim Klick (14.11.2026)

**Auftrag des Eigentümers:** „Ja, Felder umbauen“.

**Implementiert:** Runs, ME und TE der Hub-Tabelle sind umrandete Zahlen
(`ClickToEditNumberField`) und werden erst beim Anklicken zum `TextField`;
`MarketBrowserView.editingField` hält höchstens eine Zelle im
Eingabezustand. Tab und Umschalt-Tab wechseln über
`HubTableFieldNavigation` zur Nachbarzelle der sichtbaren Tabelle. Werte,
Bindungen, Prüfung, `onSubmit`, Tooltip, rote Markierung und
Bedienungshilfen-Beschriftung sind unverändert. Die Rechenregeln sind nicht
berührt.

**Bewusste Abweichungen:**

- Die Umrandung ist nachgebaut (Hintergrund `textBackgroundColor`, Rand
  `separatorColor`, Radius 5) und nicht pixelgleich zum nativen Feld. Die
  Höhe weicht je Schriftgröße um höchstens einen Punkt ab.
- Mit der Tabulatortaste von außerhalb der Tabelle erreicht man die Zellen
  nicht mehr; der Einstieg ist der Klick.
- Liegt die Nachbarzelle außerhalb des gezeichneten Bereichs, wird sie zum
  Feld, sobald sie in den Bereich scrollt; die Tabelle scrollt nicht von
  selbst mit.

**Automatisch geprüft:** Tab-Reihenfolge, gleiche Höhe in allen
Schriftgrößen, Fokus beim Start der Eingabe sowie Tab und Umschalt-Tab in
einem Testfenster (`EVEItemPresentationTests`).

**Offen:** Nachmessung und Sichtprüfung durch den Eigentümer; Links am
Namen; erklärte Zellen; T17.

### T19, Teil 1: Nachmessung der Eingabefelder (14.11.2026, 22:24–22:26 Uhr)

> Xcode-Debug-Build von 22:22 Uhr (PID 2781) mit dem Umbau, kein Schalter,
> Magnet beendet, Main-Hub-Chancen, Mausrad. Vier Proben mit Scroll-Last
> über 40 %; der Eindruck des Eigentümers liegt nicht vor.

| Hauptthread, stärker belastete Proben | Felder wie bisher (Lauf `rowexplain`) | Messschalter `rowfields` | Umbau, Felder erst beim Klick |
|---|---|---|---|
| belegt insgesamt | 77–93 % | 60–80 % | 44–85 % |
| `NSHostingView.layout()` | 32–45 % | 18–25 % | 22–34 % |
| Zeilen anlegen und platzieren | 13–29 % | 7–10 % | 9–12 % |

- **Der Umbau liegt zwischen dem alten Stand und dem Messschalter.** Der
  Zeilenaufbau ist niedriger als mit echten Feldern, erreicht aber den
  Wert des Schalters nicht ganz: Die Zelle trägt weiter Hintergrund, Rand,
  Klickziel und Bedienungshilfen-Angaben.
- Der Unterschied zum alten Stand liegt in der Größenordnung der Streuung
  durch die Scroll-Geschwindigkeit. Ein Gewinn ist wahrscheinlich, aber mit
  Handläufen nicht sicher belegt.
- Beim Bedienen der Felder (22:25–22:26 Uhr) war der Hauptthread zu
  20–45 % belegt; ein Klick löst einen Durchlauf der sichtbaren Zeilen aus
  (`visibleCandidates` 6 % einer Probe).

**Offen:** Eindruck des Eigentümers zu Scrollen, Aussehen und Bedienung der
Felder.

**Eindruck und Sichtprüfung des Eigentümers (14.11.2026, Lauf 22:24 Uhr):**
Scrollen flüssiger als mit der normalen Tabelle; Klick, Enter, Tab,
Umschalt-Tab und die rote Markierung funktionieren; am Aussehen der Zellen
stört nichts.
