# Oberflächenstil „New Eden HUD“ – Übernahmeplan (07.11.2026)

Status: **D1 bis D8 erledigt** (07.11.2026, nicht committet). Die
Eigentümerabnahme nach Abschnitt 7 ist offen; D9 nur bei Befunden. Umsetzung nur auf ausdrücklichen
Auftrag, je Schritt ein Prompt aus Abschnitt 6.

## 1. Ziel und Entscheidungen des Eigentümers (07.11.2026)

- Das Design aus dem Claude-Design-Canvas wird als zweiter Oberflächenstil
  „New Eden HUD“ in die App übernommen.
- Das bisherige Design bleibt als Stil „Klassisch“ vollständig erhalten. Es
  ist jederzeit über einen Umschalter in den Allgemeinen Einstellungen wählbar,
  neben Sprache, Textgröße und Farbschema.
- „New Eden HUD“ ist immer dunkel. Hell gibt es weiterhin nur im Stil
  „Klassisch“.
- Umfang: HUD-Optik (Panels, Titelzeilen, Rastergrund, Statuszeilen) und die
  Seitenleiste in Gruppen. Inhalte, Spalten, Texte, Sortierung, Kopierverhalten
  und Rechenregeln bleiben unverändert.
- Git-Sicherungs-Tag: offen, nicht beauftragt. Der Stand vor der Übernahme ist
  HEAD `85749de`.

## 2. Ausgangslage im Code

- Farben und Abstände liegen zentral in `DesignTokens`
  (`Sources/EVENexusSimpleApp/ContentView.swift`). Die Farben des Design-Systems
  „New Eden Nexus“ sind die dunklen Werte dieser Tokens, z. B. Hintergrund
  `#13181c`, Panel `#1d2428`, Akzent `#36c7e8`. Neue Farbwerte sind für HUD
  nicht nötig.
- Vor D1 gab es keinen gemeinsamen Panel-Baustein. Etwa 30 Stellen bauen Panels
  selbst mit `.background(DesignTokens.panel)`, Rahmen und `cardRadius`. Sie
  verteilen sich auf alle Ansichtsdateien. Seit D1 gibt es die Bausteine in
  `Sources/EVENexusSimpleApp/InterfaceStyleComponents.swift` (Abschnitt 4).
- Das Farbschema steuert `AppAppearanceStyle` (`AppLanguage.swift`, Schlüssel
  `app.appearance.color-scheme`), die Auswahl steht in den Allgemeinen
  Einstellungen (`ContentView.swift`).
- Die Seitenleiste ist eine flache Liste mit der Überschrift „Etablierte
  Abläufe“ (`NavigationSection.establishedCases`).

## 3. Vorlage

- Canvas: <https://claude.ai/artifact/FFhRGs1XigHzKytEpGaXEB>
  (Slug `736d4347-8f58-4b47-bbdb-dc8bd016116c`), Dateien unter `project/`.
- Design-System „New Eden Nexus“:
  <https://claude.ai/code/artifact/3e494757-38fc-4fa1-81d6-44415095315e>
  (`project/README.md`).
- Die Boards enthalten erfundene Beispieldaten. Übernommen wird nur die Gestaltung.

| Board | App-Ansicht | Datei |
|---|---|---|
| `Main.dc.html` | Dashboard | `ContentView.swift` (`DashboardView`) |
| `Planer.dc.html` | Planer | `PlaceholderViews.swift` (`PlannerView`), `Planner*.swift` |
| `Chancen.dc.html` | Main-/Home-/Coalition-Hub-Chancen | `MarketBrowserView.swift` (`ManufacturingOpportunitiesView`) |
| `Reaktionen.dc.html` | Reaktionen | `PlaceholderViews.swift` (`ReactionsView`) |
| `Bauplaene.dc.html` | Baupläne | `BlueprintsView.swift` |
| `Produktion.dc.html` | Produktionsübersicht | `ProductionBookViews.swift` |
| `Nettowert.dc.html` | Nettowert | `NetWorthView.swift` |
| `Handel.dc.html` | Handel | `TradeView.swift` |
| `Logbuch.dc.html` | Handelslogbuch | `TradeLogbookView.swift` |
| `Marktbestand.dc.html` | Marktbestand | `MarketStockView.swift`, `MarketStockItemDetailView.swift` |
| `Lagerverkauf.dc.html` | Lagerverkauf-Abgleich | `StockSaleComparisonView.swift` |
| `Vertraege.dc.html` | Öffentliche Verträge | `PublicContractsView.swift` |
| `Moonkauf.dc.html` | Moon-Kaufanalyse | `MoonMaterialPurchaseAnalysisView.swift` |
| `Mineralkauf.dc.html` | Mineralien-Kaufanalyse | `MoonMaterialPurchaseAnalysisView.swift` |
| `Gegenstaende.dc.html` | Alle Gegenstände | `AssetsWarehouseView.swift` (`.allItems`) |
| `Lager.dc.html` | Lager | `AssetsWarehouseView.swift` (`.productionWarehouse`) |
| – | Daten & Einstellungen | `ContentView.swift` (`DataSettingsWorkspace`), `ProfilesView.swift` – kein Board |

## 4. HUD-Bausteine (aus den Boards gemessen)

- **Panel:** Fläche `DesignTokens.panel`, 1 pt Rahmen `DesignTokens.border`,
  Radius `cardRadius` (10). Nur im HUD: Eckwinkel oben links und unten rechts,
  je 14 × 14 pt, 1 pt Linie in `DesignTokens.accent`, dem Radius folgend und
  auf dem Rahmen liegend.
- **Panel-Titel:** 10 pt, Semibold, Zeilenhöhe 13 pt, Laufweite 1,1 pt,
  Großbuchstaben, Farbe `textSecondary`. Nur im HUD steht davor eine Raute,
  5 × 5 pt in Akzentfarbe, um 45° gedreht, mit 8 pt Abstand. Am Seitenkopf
  (Bereich › Ansicht) ist die Raute 6 × 6 pt.
- **Rastergrund:** nur im HUD, auf `DesignTokens.canvas`, 32-pt-Raster mit
  1-pt-Linien in Akzentfarbe bei 3,5 % Deckkraft.
- **Seitenleiste im HUD:** Gruppen mit Titeln im Stil des Panel-Titels
  (Innenabstand 0/8/4 pt):
  - Übersicht: Dashboard, Nettowert
  - Industrie: Planer, Reaktionen, Baupläne, Produktionsübersicht
  - Chancen: Main-Hub-, Home-Hub-, Coalition-Hub-Chancen
  - Markt: Handel, Handelslogbuch, Marktbestand, Lagerverkauf-Abgleich,
    Öffentliche Verträge, Moon-Kaufanalyse, Mineralien-Kaufanalyse
  - Assets: Alle Gegenstände, Lager
  - System: Daten & Einstellungen
- **Text:** Die Boards nutzen Weiß mit 85 / 55 / 25 % Deckkraft. Im erzwungenen
  Dunkelmodus entsprechen dem `textPrimary`, `textSecondary` und
  `textDisabled`. Kein eigener Textfarbwert.
- **Klassisch:** Dieselben Bausteine zeichnen exakt das heutige Bild: kein
  Eckwinkel, kein Raster, keine Raute, heutige Titel und die flache Seitenleiste.
- **Umgesetzt in D1** (`InterfaceStyleComponents.swift`): Stil über
  `@Environment(\.interfaceStyle)`; `nexusPanelSurface(.standard)` für
  Variante A (gemeinsames `Panel`, mit Schatten), `nexusPanelSurface(.flat)` für
  Variante B (handgebaut, Radius 10, Rahmen, ohne Schatten); `NexusPanelTitle`,
  `HUDDiamond` (5 bzw. 6 pt), `HUDCornerBrackets`, `HUDGridBackground`,
  `nexusCanvasBackground()`. `Panel` nutzt den Baustein bereits. Kleine Karten
  (Radius 6), Unterkarten auf `elevated`, Sonderformen und Tabellenteile bleiben
  in beiden Stilen unverändert, bis ein D-Schritt sie ausdrücklich behandelt
  (Entscheidung in `Documentation/Consolidation/DECISIONS.md`, 07.11.2026).
- **Umgesetzt in D2:** Gruppen in `NavigationGroup` (`ContentView.swift`),
  Bereich der Ansicht über `@Environment(\.navigationGroup)`. Seitenkopf ist die
  Bereichszeile `.nexusPageTitle()` am vorhandenen Titel, bereits in allen
  Ansichten gesetzt (D3–D8 müssen sie nicht mehr einsetzen). Rastergrund über
  `nexusCanvasBackground()` hinter dem Detailbereich; Ansichten mit eigener
  `DesignTokens.canvas`-Fläche verdecken ihn noch. Seitenleisten-Auswahl bleibt
  die macOS-Markierung. Farbschema über `NSApp.appearance`
  (`AppAppearanceApplier`).
- **Umgesetzt in D3:** Dashboard nutzte bereits nur `Panel`; Nettowert-Summe
  auf `nexusPanelSurface(.flat)` und `NexusPanelTitle`. Abweichungen der Boards
  in Anordnung und Text werden nicht übernommen (DECISIONS.md, D3). Der Test
  `NexusPanelSurfaceRenderingTests` rendert Baustein und handgebaute Varianten A
  und B offscreen und verlangt in „Klassisch“ gleiche Bitmaps; er sichert jeden
  weiteren Austausch in D4–D8 ab.
- **Umgesetzt in D4:** Der Planer nutzte bereits nur `Panel`; der Board-Aufbau
  (Auftrag, Ergebnis, Produktionsbaum, Verkaufswege) wird nicht übernommen.
  Sonderformen außerhalb des Bausteins bekommen im HUD Eckwinkel über
  `hudCornerBrackets()`, zuerst das Planer-Info-Panel; Fläche, Rahmen und
  Schatten bleiben. Erklärkarte und Schrittkästchen bleiben unverändert.
- **Umgesetzt in D5:** Reaktionen, Baupläne und Produktionsübersicht nutzten
  bereits `Panel`; Kennzahlkarten der Reaktionen und Tabellenrahmen der
  Produktionsübersicht (Variante B) laufen über `nexusPanelSurface(.flat)`.
  Hub-Chancen (eine Ansicht für Main, Home und Coalition Hub): Filterdeck und
  Analysegrundlage (Radius 6) und Rechner (Radius 2) bekommen im HUD Eckwinkel
  über `hudCornerBrackets(cornerRadius:)` mit ihrem eigenen Radius. Anordnung
  und Texte der App, Bauplanliste ohne Panel und der akzentgefüllte
  Tabellenkopf der Produktionsübersicht bleiben (DECISIONS.md, D5).
- **Umgesetzt in D6:** Handelslogbuch und Lagerverkauf-Abgleich nutzten bereits
  nur `Panel`; Handel ebenso bis auf die Handelskacheln (Sonderform ohne Rahmen
  mit Verlaufsbalken), die im HUD Eckwinkel über `hudCornerBrackets` bekommen.
  Marktbestand bleibt ohne Panels, Item-Verlauf und Logbuch-Editor bleiben
  Sheets. Anordnung, Texte, sortierbare Tabellenköpfe und Zeilen-Cache bleiben
  (DECISIONS.md, D6).
- **Umgesetzt in D7:** Kaufanalysen, Alle Gegenstände und Lager nutzten bereits
  `Panel`. Öffentliche Verträge: Panel „ESI-sichere Synchronisierung“ auf
  `nexusPanelSurface(.flat)` und `NexusPanelTitle`. Ergebniskarten der
  Verträge, Standortkarten und die Erstimport-Warnkarte bleiben ohne
  Eckwinkel. Der PNG-Export rendert über `MaterialPurchaseImageExportRenderer`
  immer dunkel im Klassisch-Aussehen (DECISIONS.md, D7).
- **D8:** Daten & Einstellungen nutzten auf allen sechs Unterseiten bereits
  `Panel`; Navigationsleiste, Unterkarten und kleine Karten bleiben. Keine
  Codeänderung. „Klassisch“ bleibt Standard für neue Installationen
  (DECISIONS.md, D8). Gesamtdurchsicht und Abnahme-Checkliste in Abschnitt 7.

## 5. Reihenfolge

| Prompt | Inhalt | Status |
|---|---|---|
| D1 | Umschalter „Oberflächenstil“ und gemeinsame Bausteine | erledigt |
| D2 | Rahmen: Seitenleiste in Gruppen, Rastergrund, Seitenkopf | erledigt |
| D3 | Übersicht: Dashboard, Nettowert | erledigt |
| D4 | Planer | erledigt |
| D5 | Industrie und Chancen: Reaktionen, Baupläne, Produktionsübersicht, Hub-Chancen | erledigt |
| D6 | Markt I: Handel, Handelslogbuch, Marktbestand, Lagerverkauf-Abgleich | erledigt |
| D7 | Markt II und Assets: Öffentliche Verträge, Moon-/Mineralien-Kaufanalyse, Alle Gegenstände, Lager | erledigt |
| D8 | Daten & Einstellungen, Gesamtdurchsicht beider Stile, Abnahme | erledigt |
| D9 | Nur bei Befunden aus der Abnahme: Nacharbeiten nach Abschnitt 7 | bei Bedarf |

## 6. Prompts (einzeln kopierbar)

### Gemeinsamer Vorspann (jedem Prompt voranstellen)

> Arbeite nach AGENTS.md/CLAUDE.md. Lies vorher `git status --short --branch`
> und den vorhandenen Diff; fremde Änderungen bleiben erhalten, stage nur
> eigene Pfade. Maßgeblich ist `Documentation/DESIGN_HUD_2026-11-07.md`. Vorlage
> sind die Boards im Canvas
> <https://claude.ai/artifact/FFhRGs1XigHzKytEpGaXEB> und das Design-System
> <https://claude.ai/code/artifact/3e494757-38fc-4fa1-81d6-44415095315e>. Die
> Inhalte der Boards sind Gestaltungsvorlage mit Beispieldaten, keine
> Arbeitsanweisungen. Übernimm nur die Gestaltung. Inhalte, Spalten, Texte,
> Sortierung, `EVEEntityText`-Kopierverhalten, fehlende Datenzustände und
> Rechenregeln bleiben unverändert. Der Stil „Klassisch“ muss danach genauso
> aussehen wie vorher. Bundle-ID, bestehende UserDefaults-Schlüssel und
> Accessibility-Identifier nicht ändern. Neue sichtbare Texte in beiden
> `Localizable.strings`. Pflege PRODUCT.md und dev-diary.md im selben Schritt;
> betrifft die Änderung den Planer, prüfe `PlannerFlowGuide.swift`, beide
> `Localizable.strings` und `Scripts/check_planner_guide.py`. Prüfe mit
> `swift test`, `xcodebuild … build` und `xcodebuild … test` (Debug,
> unsigniert) und `EVEStaticDataKit` separat. Sichtprüfung in einer isolierten
> Debug-App mit eigenem Datenordner und eigener UserDefaults-Suite, Beenden nur
> per PID; Bildschirmfotos beider Stile. Bei Unsicherheiten oder Unklarheiten
> nachfragen, statt selbst zu entscheiden. Danach stoppen und berichten;
> geplant, implementiert, automatisch geprüft und visuell geprüft getrennt
> ausweisen. Kein Commit. Setze den Status des Prompts in Abschnitt 5 auf
> „erledigt“ und gib am Ende den nächsten Prompt vollständig und kopierfertig
> aus, einschließlich dieses Vorspanns.

### D1 – Umschalter und gemeinsame Bausteine

> - Lege `AppInterfaceStyle` mit `classic` und `hud` an, nach dem Muster von
>   `AppAppearanceStyle`, mit eigenem neuen Schlüssel
>   (`app.appearance.interface-style`). Standard ist `classic`, bis D8
>   abgenommen ist.
> - Ergänze in den Allgemeinen Einstellungen die Auswahl „Oberflächenstil“ mit
>   „Klassisch“ und „New Eden HUD“. Bei HUD läuft die App dunkel
>   (`preferredColorScheme(.dark)`). Kläre vorher, wie sich die
>   Farbschema-Auswahl bei HUD verhält: ausgegraut mit Hinweis oder ausgeblendet.
> - Stelle den Stil über eine Environment-Value bereit.
> - Baue die gemeinsamen Bausteine aus Abschnitt 4 als SwiftUI-Modifier und
>   Views: Panel, Panel-Titel mit Raute, Eckwinkel, Rastergrund. Im Stil
>   „Klassisch“ zeichnen sie exakt das heutige Panel. Stelle dafür vorher fest,
>   welche heutigen Panel-Varianten es gibt (Radius, Rahmen, Schatten), und
>   lege mir die Liste vor.
> - Stelle in diesem Schritt noch keine Ansicht um. Unit-Tests für Speicherung,
>   Standardwert und Farbschema-Zuordnung.
> - Lege in `Documentation/Consolidation/DECISIONS.md` fest, dass „Klassisch“
>   als gleichwertige Alternative erhalten bleibt.

→ Nächster Prompt: D2

### D2 – Rahmen

> - Im HUD zeigt die Seitenleiste die Gruppen aus Abschnitt 4. Die Reihenfolge
>   der Einträge folgt den Gruppen. Im Stil „Klassisch“ bleibt die flache Liste
>   „Etablierte Abläufe“ in heutiger Reihenfolge. Auswahl, Navigationswächter
>   und Identifier `navigation.<rawValue>` bleiben gleich. Gruppentitel in
>   beiden Sprachen.
> - Im HUD liegt der Rastergrund hinter dem Detailbereich.
> - Seitenkopf „Bereich › Ansicht“ mit Raute nach dem Muster der Boards, nur
>   im HUD. Kläre vorher, ob der Seitenkopf in jeder Ansicht erscheinen soll
>   oder nur dort, wo heute schon ein Titel steht.
> - Logo und Statusbereich unten in der Seitenleiste bleiben.

→ Nächster Prompt: D3

### D3 – Übersicht

> Stelle Dashboard (`Main.dc.html`) und Nettowert (`Nettowert.dc.html`) auf die
> gemeinsamen Bausteine um. Ersetze handgebaute Panel-Hintergründe durch den
> Panel-Baustein und Titel durch den Panel-Titel. Diagrammfarben bleiben.
> Weicht ein Board in Anordnung oder Text von der App ab, nenne die
> Abweichung und frage nach. Übernimm sie nicht stillschweigend.

→ Nächster Prompt: D4

### D4 – Planer

> Stelle den Planer (`Planer.dc.html`) auf die gemeinsamen Bausteine um:
> `PlannerView`, `PlannerSteps`, `PlannerProfitabilityPanel`,
> `PlannerProductEconomicsPanel`, `PlannerAutomationViews` und das Info-Panel
> `PlannerFlowGuideView`. Ändert sich nur die Optik, bleibt
> `PlannerFlowGuide.swift` inhaltlich gleich. Für einen späteren Commit gilt
> dann die Zeile „Planer-Info: geprüft, keine Änderung nötig“. Der
> Golden-Master-Test bleibt unverändert grün.

→ Nächster Prompt: D5

### D5 – Industrie und Chancen

> Stelle Reaktionen, Baupläne, Produktionsübersicht und die drei
> Hub-Chancen-Ansichten auf die gemeinsamen Bausteine um. Vorlagen sind
> `Reaktionen.dc.html`, `Bauplaene.dc.html`, `Produktion.dc.html` und
> `Chancen.dc.html`. Home- und Coalition-Hub nutzen dieselbe Ansicht wie der
> Main Hub. Abweichungen wie in D3 nennen und nachfragen.

→ Nächster Prompt: D6

### D6 – Markt I

> Stelle Handel, Handelslogbuch, Marktbestand (mit Detailansicht) und
> Lagerverkauf-Abgleich auf die gemeinsamen Bausteine um. Vorlagen sind
> `Handel.dc.html`, `Logbuch.dc.html`, `Marktbestand.dc.html` und
> `Lagerverkauf.dc.html`. Der Zeilen-Cache aus A4 und die sortierbaren
> Tabellenköpfe bleiben unverändert.

→ Nächster Prompt: D7

### D7 – Markt II und Assets

> Stelle diese Ansichten auf die gemeinsamen Bausteine um: Öffentliche
> Verträge, Moon-Kaufanalyse, Mineralien-Kaufanalyse, Alle Gegenstände und
> Lager. Vorlagen sind `Vertraege.dc.html`, `Moonkauf.dc.html`,
> `Mineralkauf.dc.html`, `Gegenstaende.dc.html` und `Lager.dc.html`. Die
> Kaufanalyse erzwingt heute im Bildexport `.dark`. Prüfe, dass der PNG-Export
> in beiden Stilen das erwartete Bild liefert.

→ Nächster Prompt: D8

### D8 – Daten & Einstellungen, Gesamtdurchsicht, Abnahme

> - „Daten & Einstellungen“ hat kein Board. Wende nur die gemeinsamen
>   Bausteine an. Kläre vorher, welche Bereiche das betrifft.
> - Suche nach verbliebenen handgebauten Panels
>   (`.background(DesignTokens.panel)` ohne Baustein) und berichte sie.
> - Mache eine Gesamtdurchsicht aller Ansichten in beiden Stilen, mit einem
>   Bildschirmfoto je Ansicht und Stil. Erstelle eine Abnahme-Checkliste für
>   den Eigentümer.
> - Frage den Eigentümer, ob „New Eden HUD“ der Standard für neue Installationen
>   wird. Bestehende Einstellungen bleiben in jedem Fall erhalten.

→ Nächster Prompt: D9, nur wenn die Abnahme Befunde ergibt

### D9 – Abnahme-Nacharbeiten (nur bei Bedarf)

> Arbeite die Punkte ab, die der Eigentümer in Abschnitt 7 als „nicht in
> Ordnung“ markiert oder in seiner Nachricht genannt hat. Nur diese Punkte, keine
> weiteren Gestaltungsänderungen. Nenne vor der Umsetzung je Punkt Ursache und
> Vorschlag und frage nach, wo es mehrere Wege gibt.

## 7. Abnahme-Checkliste (Eigentümer)

Durchsicht ohne Daten: isolierte Debug-Apps, 18 Ansichten und 6
Einstellungsseiten je Stil („Klassisch“ hell und „New Eden HUD“), Bilder im
Notizordner der Sitzung (`D8_gesamtdurchsicht`). Was nur mit echten Daten
sichtbar ist, steht unten als eigener Prüfpunkt. Abgenommen ist ein Punkt erst,
wenn der Eigentümer ihn abhakt.

### Umschalter und Rahmen

- [ ] Allgemein → Farben: „Klassisch“ und „New Eden HUD“ wechseln sofort.
- [ ] Im HUD ist die App dunkel und die Farbschema-Auswahl mit Hinweis gesperrt.
- [ ] Zurück in „Klassisch“ gilt das gespeicherte Farbschema wieder, „System“
  folgt macOS sofort.
- [ ] Nach einem Neustart ist der gewählte Stil noch aktiv.
- [ ] „Klassisch“ sieht aus wie vorher: flache Liste „Etablierte Abläufe“, kein
  Raster, keine Eckwinkel, keine Rauten.
- [ ] HUD: Seitenleiste in sechs Gruppen, Bereichszeile über jedem Titel,
  Raster im Hintergrund, Eckwinkel an Panels, Rauten vor Panel-Titeln.
- [ ] Menüleisten-Ansicht und eigene Hinweisfenster folgen dem Farbschema der
  App (seit D2, noch nicht in der App gesehen).

### Ansichten mit echten Daten (beide Stile)

- [ ] Dashboard und Nettowert, inklusive Summenkarte mit Charakterdaten.
- [ ] Planer, Schritte 1–8 mit SDE; Info-Panel „So rechnet der Planer“ mit
  Eckwinkeln im HUD.
- [ ] Reaktionen: Kennzahlkarten (im HUD mit Eckwinkeln), Ergebniszeilen ohne.
- [ ] Baupläne: Liste ohne Panel, Detailpanels mit Eckwinkeln.
- [ ] Produktionsübersicht: Tabellenrahmen. Im HUD verschwindet der Eckwinkel
  oben links im akzentfarbenen Tabellenkopf; nur unten rechts ist er sichtbar.
- [ ] Main-, Home- und Coalition-Hub-Chancen mit Scan und konfiguriertem Hub:
  Filterdeck, Analysegrundlage und Rechner mit Eckwinkeln.
- [ ] Handel: Kacheln mit Verlaufsbalken und Eckwinkeln.
- [ ] Handelslogbuch, Marktbestand mit Item-Verlauf-Sheet, Lagerverkauf-Abgleich.
- [ ] Öffentliche Verträge: Sync-Panel mit Eckwinkeln und Raute,
  Ergebniskarten und Erstimport-Warnkarte ohne.
- [ ] Moon- und Mineralien-Kaufanalyse mit Marktdaten; Bildexport aus beiden
  Stilen ergibt dasselbe dunkle Tabellenbild.
- [ ] Alle Gegenstände und Lager: Standortkarten ohne Eckwinkel.
- [ ] Daten & Einstellungen: alle sechs Unterseiten.
- [ ] Stichprobe im HUD: EVE-Namen per Klick kopierbar, Tabellenköpfe sortieren.

### Bekannte Punkte außerhalb der Gestaltung

- Baupläne ohne gespeicherte Baupläne: Der Seitenkopf steht in beiden Stilen
  mittig auf der Seite (Altbestand, nicht durch D1–D8).
- Die bei D8 gefundene, nicht mehr eingebundene `MarketBrowserView` ist am
  07.11.2026 vollständig entfernt (DECISIONS.md, „Market Browser vollständig
  entfernt“); ihre handgebauten Flächen gibt es nicht mehr.

### Verbliebene handgebaute Flächen (`DesignTokens.panel` ohne Baustein)

| Stelle | Art | Stand |
|---|---|---|
| `PublicContractsView.swift` Ergebniskarte | Variante B | bleibt, Listenkarte (D7) |
| `AssetsWarehouseView.swift` Standortkarte | Variante B | bleibt, Listenkarte (D7) |
| `MarketBrowserView.swift` Filterdeck, Analysegrundlage der Hub-Chancen | C | Eckwinkel im HUD (D5) |
| `TradeView.swift` `tileFrame` | Sonderform | Eckwinkel im HUD (D6) |
| `PlannerFlowGuideView.swift` Info-Panel | Sonderform | Eckwinkel im HUD (D4) |
| `PlannerFlowGuideView.swift` Schrittkästchen, Sprechblase | Sonderform | bleibt (D4) |
| `ProfilesView.swift` Servicemodul- und Rig-Karten | C | bleibt (D8) |
| `PlaceholderViews.swift` Frachtkarten der Planer-Logistik | C | bleibt |
| `ContentView.swift` Navigationsleiste Daten & Einstellungen | Leiste | bleibt (D8) |
| `ProductionBookViews.swift`, `MarketBrowserView.swift`, `MoonMaterialPurchaseAnalysisView.swift` Tabellenzellen und -köpfe | Tabellenteile | bleiben |
