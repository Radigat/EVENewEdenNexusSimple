# EVE New Eden Nexus - Assets, Industry, Markets – Entwicklungstagebuch

## 23. Oktober 2026 – Handel: Top-20-Kachel, Teil 4 (Gesamtprüfung)

Ziel: Gesamtprüfung der Teile 1–3 gegen die sechs Eigentümerentscheidungen in
[Handel-Plan, Abschnitt J](Documentation/HANDEL_PLAN.md) und gegen AGENTS.md.
Keine neuen Funktionen.

Durchsicht des Diffs (Core, Tests, `TradeView`, Lokalisierung, Dokumente):
- Gewinn/m³ = `P ÷ v`. Ohne Gewinn oder ohne positives, endliches Volumen ist
  der Wert `nil`, nie 0 oder unendlich.
- Gerankt werden nur positive Werte. Unbekannte Werte und Werte ≤ 0 werden
  getrennt gezählt und ausgewiesen.
- Die Top-Kachel hat eine eigene Sortierung:
  - Beim Start und beim Wechsel der Kennzahl gilt Kennzahl absteigend.
  - Sonst bleibt die gewählte Sortierung erhalten.
  - Die übrigen Kacheln teilen weiter `sort`.
- Die Spalte Gewinn/m³ ist in allen Kacheln immer sichtbar.
- Die Kachel erscheint nur bei mehr als einer Kachel oder mehr als 20 Items.
- Alle Spalten sind sortierbar. Unbekannte Werte stehen deterministisch, der
  Tie-Breaker ist die Type-ID.
- Item-Namen werden über `EVEItemText` kopiert, Hub-Namen über
  `EVEEntityText`. „Ins Logbuch“ bleibt ein getrenntes Bedienelement.
- Befund: keine Abweichung, keine Korrektur nötig.

Prüfung (automatisch, isoliert unter `/private/tmp/claude-501/…/scratchpad/full-check`):
- `swift test --disable-sandbox --scratch-path …/build` mit
  `EVE_NEXUS_APPLICATION_SUPPORT_ROOT`, eigener Preferences-Suite und
  `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1`:
  - Ergebnis: 548 Tests in 35 Suites plus 70 Tests in 3 Suites bestanden.
  - Der erste Lauf meldete 4 Fehler in „Build-specific SQLite SDE catalog“.
    Ursache: Eine parallele Sitzung änderte während des Laufs
    `SQLiteStaticCatalogTests.swift` (08:41:52, Laufbeginn 08:40:48).
  - Die Wiederholung auf dem aktuellen Stand war grün.
  - Die Handel-Dateien sind davon nicht betroffen.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden.
- `xcodebuild … -configuration Debug -destination 'platform=macOS,arch=arm64'
  CODE_SIGNING_ALLOWED=NO test`:
  - mit isolierten Daten, DerivedData und Modulcaches;
  - Ergebnis `** TEST SUCCEEDED **`, 548 Tests.
- `git diff --check` fehlerfrei. Die lokalen Dokumentlinks in PRODUCT.md,
  dev-diary.md und HANDEL_PLAN.md sind vorhanden.

Prüfung (visuell, isoliert):
- Aufbau: Debug-App aus dem Xcode-Testlauf mit eigenem Datenordner und eigener
  Preferences-Suite, ohne Hintergrunddienste.
- Datenbasis: nur der aktive SDE-Katalog (statische CCP-Daten) als Kopie, keine
  Nutzerdaten und keine Marktpreise.
- Bedienung ausschließlich über die PID der Debug-App:
  - Fenster über `CGWindowListCopyWindowInfo`, Aufnahme mit
    `screencapture -l`;
  - Bedienung über `AXUIElementCreateApplication(pid)`.
  - Eine parallel laufende andere Instanz blieb unberührt.
- Handel → Ships:
  - Die Kachel „Top 20“ steht vor Battlecruisers.
  - „Rangfolge nach“ schaltet zwischen Diff % und Gewinn/m³; gespeichert wird
    `profitPerCubicMeter`.
  - Leerzustand mit Hinweis und, bei Gewinn/m³, den nötigen Daten.
  - Fußzeile „Nicht gerankt: 421 Items ohne bekannten Wert“.
  - Die Spalte Gewinn/m³ steht in allen Kacheln.
  - Ein Klick auf „Gewinn/m³“ sortiert die Untergruppen-Kacheln gemeinsam
    absteigend; unbekannte Werte stehen nach Type-ID.
- Nicht prüfbar ohne Live-Marktdaten:
  - gerankte Zeilen, Werte und Farben;
  - die Spaltensortierung innerhalb der Top-Kachel.

Hinweis zur Darstellung: Ohne positive Werte zeigt der Chip „Top 0 von 421
Items“.

Offen:
- Prüfung mit echten Hub-Marktdaten.
- Eigentümerabnahme.

Commit:
- Auf Auftrag des Eigentümers ist die Reihe (Teile 1–4) als `9b4462f` auf
  `main` lokal committet, nicht gepusht.
- Gestagt wurden nur die eigenen Änderungen; Änderungen paralleler Sitzungen
  in denselben Dateien blieben ungestagt.
- Der gestagte Stand bestand für sich `swift test` mit 527 Tests in 35 Suites
  plus 66 App-Tests.

## 23. Oktober 2026 – Handel: Top-20-Kachel, Teil 3 (Kachel)

Ziel (Eigentümerentscheide 1, 2 und 4–6, [Handel-Plan, Abschnitt J](Documentation/HANDEL_PLAN.md)):
In einer gewählten Marktgruppe steht vor den Untergruppen-Kacheln die Kachel
„Top 20“ über alle Items des Teilbaums.

Änderung (`TradeView`):
- Zustand:
  - `trade.top-ranking` (AppStorage) speichert die Kennzahl; ein unbekannter
    Wert fällt auf Diff % zurück.
  - Eigene Umschalter für Quelle und Ziel (Standard Min-Sell).
  - Eigene Sortierung `topSort`. `nil` bedeutet: Kennzahl absteigend.
    - Der Wechsel der Kennzahl im Picker setzt sie zurück.
    - Andere Änderungen, etwa an den Seiten oder an den Marktdaten, erhalten
      sie.
- `displayRows` ist geteilt in `calculatedRows` (unsortiert) und die
  Sortierung. Die Untergruppen-Kacheln verhalten sich unverändert und teilen
  weiter `sort`.
- Gemeinsame Bausteine `tileFrame`, `countChip`, `sidePickers` und `tileTable`.
  Tabellenkopf und Zahlenköpfe bekommen die Sortierung als Binding.
- Die Zeilenkennung für „Ins Logbuch“ hat ein Präfix, damit Items in der
  Top-Kachel und in ihrer Untergruppe eindeutige Kennungen haben:
  `trade.row.<id>.add-to-logbook` bzw. `trade.top-tile.row.<id>.add-to-logbook`.
- Top-Kachel in voller Breite vor dem Kachelraster:
  - Bedingung: mehr als eine Kachel oder mehr als 20 Items;
  - Picker „Rangfolge nach“ (Diff % | Gewinn/m³);
  - Chips für Quelle und Ziel, Chip „Top N von M Items“;
  - Hinweis „Nur Items mit positivem Wert werden gerankt.“;
  - Leerzustand, bei Gewinn/m³ mit den nötigen Daten;
  - Fußzeile „Nicht gerankt: …“ mit getrennten Anzahlen;
  - Accessibility-IDs `trade.top-tile`, `.ranking`, `.source-side`,
    `.target-side`.
- Lokalisierung en/de für die neun neuen Texte.
- PRODUCT.md, Abschnitt Handel: Top-20-Kachel beschrieben.

Auslegung im Rahmen des Prompts:
- Der Chip nennt die tatsächlich gerankte Anzahl, also „Top 7 von 412 Items“,
  wenn nur 7 Items positiv sind. Im Normalfall lautet er „Top 20 von N Items“.
- Der Titel bleibt „Top 20“.

Rechenregeln unverändert.

Prüfung (automatisch):
- `swift build`: erfolgreich, keine Warnungen oder Fehler in `TradeView.swift`.
- `swift test --filter TradeTileTests`: 9 Tests in 1 Suite bestanden.
- Nativer Debug-Build (`xcodebuild … -configuration Debug -destination
  'platform=macOS,arch=arm64' build`) mit isoliertem DerivedData und
  Modulcaches unter `/private/tmp`: `** BUILD SUCCEEDED **`.
- `plutil -lint` für beide `Localizable.strings` in Ordnung.
- `git diff --check` fehlerfrei.
- Für die Ansicht gibt es keine eigenen Tests. Die Rangfolge selbst ist durch
  die Core-Tests aus Teil 1 abgedeckt.
- Nicht geprüft:
  - Sichtkontrolle in der laufenden App (Teil 4);
  - volles `swift test` und `xcodebuild … test`.

Offen:
- Teil 4: Gesamtprüfung mit Sichtprüfung.
- Eigentümerabnahme offen. Nicht committet.

## 23. Oktober 2026 – Handel: Top-20-Kachel, Teil 2 (Spalte Gewinn/m³)

Ziel (Eigentümerentscheid 3, [Handel-Plan, Abschnitt J](Documentation/HANDEL_PLAN.md)):
Die Spalte Gewinn/m³ steht in allen Kacheln, immer sichtbar, direkt nach
Diff %.

Änderung:
- `TradeView`:
  - Neue sortierbare Spalte „Gewinn/m³“ nach Diff %, in der kompakten Ansicht
    und mit Details.
  - Sie sortiert über die gemeinsame Sortierung aller Kacheln
    (`.profitPerCubicMeter`).
  - Die Zelle ist bei Gewinn grün, bei Verlust rot und zeigt „—“, wenn der Wert
    unbekannt ist.
- Kompakte Kachel-Mindestbreite von 560 auf 660 pt:
  - Name (200) + vier Zahlenspalten (4 × 96 + Abstände) + Innenabstand ergeben
    etwa 632 pt.
  - Damit bleibt die bisherige Reserve von rund 28 pt erhalten.
- Lokalisierung: „Profit/m³“ / „Gewinn/m³“.
- PRODUCT.md, Abschnitt Handel → Kachel: Spalte beschrieben, Formel per Link
  auf Abschnitt C.

Bestehende Rechenregeln und die übrigen Spalten sind unverändert.

Prüfung (automatisch):
- `swift build` erfolgreich, keine Warnungen oder Fehler in `TradeView.swift`.
- `swift test --filter TradeTileTests`: 9 Tests in 1 Suite bestanden.
- Nativer Debug-Build: `xcodebuild -project EVENexusSimple.xcodeproj -scheme
  EVENexusSimple -configuration Debug -destination 'platform=macOS,arch=arm64'
  build`. DerivedData und Modulcaches lagen isoliert unter `/private/tmp`;
  Ergebnis `** BUILD SUCCEEDED **`.
- `plutil -lint` für beide `Localizable.strings` in Ordnung.
- `git diff --check` fehlerfrei.
- Nicht geprüft:
  - Sichtkontrolle in der laufenden App, vorgesehen für Teil 4;
  - volles `swift test` und `xcodebuild … test`.

Offen:
- Teil 3: Top-20-Kachel.
- Teil 4: Gesamtprüfung mit Sichtprüfung.
- Eigentümerabnahme offen. Nicht committet.

## 23. Oktober 2026 – Handel: Top-20-Kachel, Teil 1 (Rechenkern)

Ziel (Eigentümerauftrag, [Handel-Plan, Abschnitt J](Documentation/HANDEL_PLAN.md)):
- In einer gewählten Marktgruppe steht vor den Untergruppen-Kacheln eine
  Kachel „Top 20“.
- Die Rangfolge ist umschaltbar zwischen Diff % und Gewinn/m³.
- Die Umsetzung ist in vier Teile geteilt. Teil 1 umfasst nur Rechenkern und
  Tests, ohne Änderung an der Oberfläche.

Entscheidungen auf Rückfrage: Abschnitt J, Punkte 1–6. Dazu gehören
Gewinn/m³ statt Rohdifferenz und das Ranken nur positiver Werte.

Änderung:
- `TradeModels`: berechnete Eigenschaft `TradeRow.profitPerCubicMeter`
  (`P ÷ v`). Ohne Gewinn oder ohne positives, endliches Packvolumen ist sie
  `nil`; ein nicht endliches Ergebnis ist ebenfalls `nil`.
- `TradeTiles`:
  - `TradeSortColumn.profitPerCubicMeter` mit Zuordnung im Sortierer.
  - `TradeTopRankingMetric` mit `difference` und `profitPerCubicMeter`; die
    Raw-Werte sind zum Speichern bestimmt.
  - `TradeTopRanking.ranked(_:by:limit:)` mit der Grenze 20. Gerankt werden nur
    bekannte Werte > 0, absteigend, bei Gleichstand nach Type-ID.
  - Unbekannte Werte und Werte ≤ 0 werden getrennt gezählt
    (`TradeTopRankingResult`).
  - `TradeRowSorter.value` ist dafür modulintern statt privat.
- Handel-Plan: Formelzeile Gewinn/m³ in Abschnitt C, neuer Abschnitt J.

Bestehende Rechenregeln, Kacheln und Ansicht sind unverändert. PRODUCT.md
bleibt unverändert, weil es noch kein sichtbares Verhalten gibt.

Prüfung (automatisch):
- `swift build`: erfolgreich, keine Warnungen in `TradeModels.swift` und
  `TradeTiles.swift`.
- `swift test --filter TradeTileTests`: 9 Tests in 1 Suite bestanden, davon 5
  neu:
  - Gewinn/m³ mit fehlendem Gewinn und mit fehlendem, 0, negativem oder
    unendlichem Volumen;
  - Rangfolge nach Diff % und nach Gewinn/m³ mit getrennten Zählern;
  - Grenze 20 und frei gewählte Grenze;
  - Sortierung nach Gewinn/m³ mit unbekannten Werten.
- `git diff --check` für die geänderten Dateien fehlerfrei.
- Nicht ausgeführt: volles `swift test`, `EVEStaticDataKit` und `xcodebuild`.
  Sie gehören zu Teil 4.

Offen:
- Teil 2: Spalte Gewinn/m³ in allen Kacheln.
- Teil 3: Top-20-Kachel.
- Teil 4: Gesamtprüfung mit Sichtprüfung.
- Eigentümerabnahme offen. Nicht committet.

## 22. Oktober 2026 – Handel: Routen statt Station Trading

Ziel (Eigentümerauftrag):
- Station Trading Main, Home und Coalition entfernen. Auf Rückfrage: alle drei.
- Handel zwischen Home und Coalition Hub in beide Richtungen ergänzen.

Entscheidung auf Rückfrage: Wallet-Käufe im Home bzw. Coalition Hub bekommen
den jeweils anderen Hub als Ziel.

Änderung:
- `TradeModels`:
  - `TradeMode` mit den Fällen `mainToHome`, `mainToCoalition`,
    `homeToCoalition` und `coalitionToHome`.
  - Neu `TradeRoute` (Quelle/Ziel).
  - `TradeImportTarget` entfällt.
- `RuntimeState`: Transportbasis je `TradeRoute`. Die Home-↔-Coalition-Etappe
  ist als `homeCoalitionLeg` herausgelöst; für Coalition → Home werden Start
  und Ziel getauscht. Der Abgleich löst alle Routen zwischen eingerichteten
  Hubs auf.
- `TradeWalletReconciler`:
  - Ziel Main → Home, Home → Coalition, Coalition → Home, sofern der andere Hub
    ein eigener Ort ist, sonst der Kauf-Hub.
  - Transport je Route.
- `TradeView`: Modusleiste mit vier Routen. Der generelle Hinweis „derselbe Ort,
  keine Handelsroute“ ersetzt den bisherigen Import-Hinweis.
- Lokalisierung: Station-Trading-Texte entfernt, neue Routen und Meldungen
  ergänzt.

Prüfung (automatisch):
- `swift test`: 522 Tests in 35 Suites plus 66 App-Tests bestanden.
- Neu bzw. angepasst:
  - Rechnertest Home → Coalition und Coalition → Home mit Etappe und ohne
    Etappe.
  - Abgleich: Home-Kauf mit Ziel Coalition, FIFO am Coalition Hub,
    nicht zugeordneter Rest am Home Hub, geteilter Ort bleibt im Kauf-Hub.
  - Moduszusammensetzung.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden.
- Natives `xcodebuild … test` mit `** TEST SUCCEEDED **`.
- `git diff --check` fehlerfrei.

Prüfung (visuell, isoliert): Die Modusleiste zeigt die vier Routen, Home →
Coalition mit Chips und Hinweisen.

Offen:
- Die Annahme symmetrischer Jump-Freighter-Kosten ist nicht live geprüft.
- Eigentümerabnahme offen.
- Nicht committet.

## 22. Oktober 2026 – Handel P8: Gesamtprüfung und Abnahme-Checkliste

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P8):
- Gesamtprüfung.
- Abgleich der Steuerdateien.
- Abnahme-Checkliste; die Live-Prüfung mit ESI bleibt opt-in.

Prüfung (automatisch):
- `git diff --check` fehlerfrei.
- `swift build` ohne Warnungen in den Handelsdateien. Dabei behoben: eine
  `where`-Warnung in `TradeLogbookView`.
- `swift test`: 521 Swift-Testing-Tests in 35 Suites plus 66 Tests in 3
  Suites bestanden.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden.
- `xcodebuild … -configuration Debug … build`: `BUILD SUCCEEDED`.
- `xcodebuild … test`: `TEST SUCCEEDED`, 521 Swift-Testing-Tests (darunter
  die Handels-Suites) und 8 XCTest-Fälle.
- Alle 11 neuen Quell- und Testdateien haben genau eine Datei- und eine
  Build-Referenz im Xcode-Projekt.
- Lokale Dokumentlinks in den geänderten Dateien sind gültig.

Dokumentation:
- `PROJECT_STATE.md` (Stand, neuer Abschnitt Handel).
- `DECISIONS.md` (Regeländerungen und Annahmen).
- `FEATURE_COVERAGE.md` (WAL-001, Ergänzungen der Weiterentwicklung).
- `ACCEPTANCE.md` (Nachweistabelle P1–P8).
- `ROADMAP.md`: von „Geplant“ nach „Umgesetzt, Abnahme offen“.
- `PRODUCT.md` und `ARCHITECTURE.md`: veraltete „geplant“-Formulierungen
  bereinigt.
- Handel-Plan Abschnitt H: Abnahme-Checkliste.

Live-Prüfung: nicht ausgeführt (opt-in, Eigentümer).

Offen:
- SDE-Neuimport mit dem echten Archiv; die Annahme `marketGroups.jsonl` im
  Archiv ist nur über das Community-Schema belegt.
- Live-Prüfung mit Märkten, Strukturen, DOTLAN, Wallets und Orders.
- 4-Stellen-Preisschritt ingame bestätigen.
- Eigentümerabnahme.
- Nichts committet.

## 22. Oktober 2026 – Handel P7: Automatischer Wallet-Abgleich

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P7):
Käufe aus den Wallets automatisch ins Logbuch übernehmen, Verkäufe nach FIFO
zuordnen, Steuer belegen und Broker berechnen, die Orderart erkennen, Ist- und
Planwerte gegenüberstellen.

Änderung:
- `ESICharacterOrderDTO`: optional `issued` und `duration` (additiv).
- `TradeLogbookStore` Schema 3:
  - Neu sind `wallet_orders` und `trade_settings` (Startdatum).
  - Einkäufe und Verkäufe bekommen Wallet-Verknüpfung und Herkunft
    (manuell, erkannt, angenommen); Einkäufe zusätzlich „Transport geschätzt“,
    Verkäufe die belegte Steuer.
  - Ein eindeutiger Index verhindert doppelte Übernahmen.
  - Neu `save([...])` als Stapel in einer Transaktion.
- `TradeLogbookEntry` und `TradeLogbookSale` um diese Felder erweitert. Der
  realisierte Gewinn nutzt die belegte Steuer vor dem Satz; neu sind Ø Ist-VK
  und Abweichung vom Plan.
- Neu `TradeWalletReconciler.swift`, eine reine Funktion für:
  - Import ab Startdatum, je Transaktion,
  - Ziel Main → Home,
  - Fertigung aus aktiven Plänen,
  - geschätzten Transport,
  - FIFO je Item und Ziel-Hub,
  - Journal-Steuer anteilig,
  - Orderart aus Orders,
  - nicht zugeordnete Verkäufe und manuelle Zuordnung.
- `RuntimeState`:
  - `reconcileTradeLogbook`, `setTradeWalletImportStart`, `assignTradeSale`.
  - Wallet-Übergabe inklusive offener Orders und Orderhistorie.
  - Ohne lesbaren Katalog werden Käufe gezählt statt benannt.
- `CharacterBatchSynchronizer` gleicht nach jeder Sammel-Synchronisierung mit
  den Materialien aktiver Pläne ab (`TradePlannerMaterials`).
- `TradeLogbookView`:
  - Startdatum und Erklärung, Abschnitt „Nicht zugeordnete Verkäufe“ mit
    „Zuordnen“.
  - Spalten Ø Ist-VK (mit Hervorhebung unter Plan) und Plan-Gewinn,
    Hinweis-Symbole.
  - Der Editor zeigt die Herkunft; eigene Änderungen setzen sie auf manuell.
- Lokalisierung en/de; `TradeWalletReconciler.swift` im Xcode-Projekt.

Prüfung (automatisch):
- `swift test`: 521 Tests in 35 Suites plus 66 App-Tests bestanden.
- Neue Abgleich-Tests:
  - Importregeln: Startdatum, Hub, unbenannter Typ, Fertigung, Station
    Trading.
  - Orderart erkannt bzw. angenommen.
  - FIFO über zwei Einkäufe mit anteiliger Steuer und Gewinnrechnung.
  - Nicht zugeordnet nur für erfasste Gegenstände.
  - Zweiter Lauf ohne Änderungen, manuelle Zuordnung.
- Neue Store-Tests:
  - Verknüpfungen, Herkunft und Steuer bleiben erhalten.
  - Doppelte Wallet-Verknüpfung wird abgewiesen.
  - Einstellungen und Orders werden gespeichert.
  - Echte Schema-1-Datei migriert auf Schema 3.
- App-Test: kein erfundener Name ohne Katalog, Startdatum bleibt erhalten.
- `swift test --package-path Packages/EVEStaticDataKit` bestanden.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.

Prüfung (visuell, isoliert): Das Logbuch zeigt Startdatum, Erklärung und die
neuen Spalten. Ein veralteter Satz („Zuordnung folgt später“) wurde ersetzt.

Offen:
- Live-Abgleich mit echten Wallets, Orders und Journal ist nicht ausgeführt.
- Die Erkennung der Orderart vergleicht nur Charakter, Gegenstand, Ort, Seite
  und Laufzeitfenster, nicht den Preis (Orders können umgepreist werden).
- Transport und Broker bleiben Schätzung bzw. Berechnung.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P6: Wallet-Daten aller Charaktere

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P6, U5
entschieden):
- Persönliche Wallet-Transaktionen und Journal aller Charaktere dauerhaft im
  Logbuch speichern.
- Knopf „Wallets abgleichen“ und Statuszeile je Charakter.
- Keine Corporation-Wallet.

Änderung:
- `ESIWalletTransactionDTO`: optional `locationID`, `journalRefID`,
  `isPersonal`. Ältere gespeicherte Snapshots dekodieren weiter.
- Neu `Sources/EVENexusCore/Trade/TradeWallet.swift`: Transaktion,
  Journal-Eintrag, Abgleichsstatus, Ergebnis eines Abgleichs.
- `TradeLogbookStore` Schema 2:
  - Tabellen `wallet_transactions`, `wallet_journal` und `wallet_sync_status`.
  - `recordWallet` ist idempotent über Charakter und ESI-ID, ergänzt fehlende
    Felder per COALESCE und überspringt ungültige Transaktionen.
  - Der Status wird auch ohne Daten gespeichert; die letzte erfolgreiche Zeit
    bleibt erhalten.
  - Lesemethoden: `walletSyncStatuses`, `walletTransactions`, `walletJournal`.
- `RuntimeState.syncCharacter` übergibt jede Synchronisierung an
  `recordTradeWallet`; ein Fehler bricht die Synchronisierung nicht ab.
- `TradeLogbookView`: Abschnitt „Wallet-Daten“ mit Knopf (über
  `CharacterBatchSynchronizer`) und Statuszeile je Charakter, auch für noch
  nicht abgeglichene Charaktere.
- Lokalisierung en/de; `TradeWallet.swift` im Xcode-Projekt eingetragen.

Prüfung (automatisch):
- `swift test`: 515 Tests in 34 Suites plus 65 App-Tests bestanden.
- Neue Store-Tests:
  - Idempotenz, ältere Zeilen bleiben, ungültige werden übersprungen.
  - Fehlender Scope ohne Verlust des letzten Erfolgs; unbekannte Felder
    bleiben `nil`.
  - Migration einer Schema-1-Datei ohne Datenverlust.
  - DTO-Dekodierung mit und ohne neue Felder.
- App-Test: Übernahme für zwei Charaktere (frisch und verboten); Status
  sortiert und nach dem Wiederöffnen lesbar.
- `swift test --package-path Packages/EVEStaticDataKit` bestanden.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.

Prüfung (visuell, isoliert):
- Die Logbuch-Datei aus P5 wurde beim Start auf Schema 2 migriert; der
  Eintrag blieb erhalten.
- Ohne Charaktere ist „Wallets abgleichen“ deaktiviert und ein Hinweis
  erscheint.

Offen:
- Live-Abgleich mit echten Charakteren und ESI: nicht ausgeführt, weil dafür
  keine produktiven Daten genutzt werden.
- Zuordnung zum Logbuch folgt mit P7.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P5: Handelslogbuch

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P5):
- Einkaufs-Logbuch in einer eigenen SQLite-Datei mit eigenem
  Seitenleisteneintrag.
- Erinnerung in der App (geplanter VK gegen aktuellen Zielpreis).
- „Ins Logbuch“ aus Kachelzeilen sowie manuelle Einträge.
- Spalte für die offene Logbuch-Menge im Handel.

Entscheidungen vor dem Start: Erinnerung nur in der App, keine
macOS-Mitteilung; eigener Seitenleisteneintrag „Handelslogbuch“.

Änderung:
- Neu `Sources/EVENexusCore/Trade/TradeLogbook.swift`:
  - Status mit Rang und `isOpen`, Verkaufsarten, `TradeLogbookEntry` mit
    eingefrorenen Sätzen.
  - Kosten, geplanter und realisierter Gewinn, offene Menge, Erinnerung und
    Validierung.
  - `TradeLogbookSummary.openQuantities` und `TradeLogbookSorter`.
- Neu `TradeLogbookStore.swift`:
  - Actor nach dem Muster von `PublicContractStore`, Tabellen
    `trade_purchases` und `trade_sales` (CASCADE).
  - `user_version` 1; eine neuere Version wird abgewiesen und nicht verändert.
- `RuntimeState`: `loadTradeLogbook`, `saveTradeLogbookEntry`,
  `deleteTradeLogbookEntry`, `tradeSearchItemTypes`; die Datei wird erst bei
  Bedarf geöffnet.
- Neu `TradeLogbookView.swift`:
  - Logbuch-Tabelle mit Filter, Sortierung, Erinnerung und Hervorhebung.
  - Bearbeiten- und Löschknöpfe vorn; Löschen nur nach Bestätigung.
  - Editor mit Gegenstandssuche, Verkäufen und Prozentfeldern für Sätze.
    Leere Felder bleiben unbekannt.
- `NavigationSection.tradeLogbook` nach `.trade`.
- Im Handel:
  - Plus-Knopf „Ins Logbuch“ je Zeile, vorbefüllt; der exakte Transport
    folgt der eingegebenen Menge.
  - Detailspalte „Offen (Logbuch)“ und Buch-Symbol in der Kompaktansicht.
- Lokalisierung en/de; Dateien im Xcode-Projekt eingetragen.

Prüfung (automatisch):
- `swift test`: 511 Tests in 34 Suites plus 64 App-Tests bestanden.
- Neu `TradeLogbookTests` (8 Tests):
  - Roundtrip mit Wiederöffnen; NULL bleibt unbekannt.
  - Upsert ersetzt Verkäufe, Löschen entfernt Einträge.
  - Validierung, Abweisung einer neueren Schemaversion.
  - Gewinnrechnung, Erinnerung, offene Mengen je Ziel-Hub, Sortierung.
- App-Test: Navigationsreihenfolge sowie Laden, Speichern, Abweisen und
  Löschen über RuntimeState in einem temporären Datenordner.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.
- `git diff --check` ohne Befund.

Prüfung (visuell, isoliert):
- Debug-App mit eigenem Datenordner, eigener Defaults-Suite und synthetischem
  Katalog.
- Geprüft: Editor aus der Zeile „Miner I“ geöffnet, Menge und Preis gesetzt,
  gespeichert. Der Eintrag erscheint im Handelslogbuch und überlebt einen
  Neustart; der Handel zeigt „Offen (Logbuch) 25“.
- Dabei korrigiert:
  - Logbuch-Tabelle zu breit (Aktionen außer Sicht, jetzt vorn).
  - Detailtabelle des Handels schob die Kachel unter die Seitenleiste (P4),
    jetzt scrollt sie innerhalb der Kachel.

Offen:
- Wallet-Abgleich folgt mit P6 und P7.
- Erinnerung nur mit Marktdaten der laufenden Sitzung.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P4: Handelsbereich in der App

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P4, U4
entschieden): ein Bereich Handel nach dem Referenzbild mit Modusleiste,
Knoten-Kacheln, einstellbaren Pfeilschwellen, Detailspalten, Tagesbedarf,
Tiefe und Transportbasis aus RuntimeState.

Änderung:
- Neu `Sources/EVENexusCore/Trade/TradeTiles.swift`:
  - `TradeTileBuilder` mit Kinder-Kacheln, Zusatzkachel für eigene Items und
    zyklenfestem Pfad.
  - `TradeDifferenceIndicator` mit den Schwellen 25 %/30 % und Abwärtspfeil.
  - `TradeDisplayRow` und `TradeRowSorter` mit typisierter Sortierung,
    unbekannten Werten nach der Regel und `typeID` als Tie-Breaker.
- `RuntimeState`, Abschnitt Trade:
  - Katalog-Durchreichungen sowie Marktdaten, Bedarf und Gebühren je Rolle.
    Geteilte Hubs nutzen die Daten des Haupt-Hubs.
  - `refreshTradeTransportBasis`: Kurier Main→Home, für Coalition zusätzlich
    Home→Coalition per Jump Freighter (Flugkosten = Isotope je Flug × Ø
    Isotopenpreis) oder Kurier.
- Neu `Sources/EVENexusSimpleApp/TradeView.swift` und
  `NavigationSection.trade` („Handel“, nach Coalition-Hub-Chancen). Die
  Einstellungen liegen in `AppDefaults.store` (`trade.*`).
  - Leerzustände: kein Katalog, SDE-Neuimport nötig, Hub fehlt oder ist
    identisch, keine Marktdaten, Gebühren oder Transport fehlen.
  - Der Knopf **Hub-Märkte aktualisieren** startet den bestehenden Hub-Scan.
    Grund: Marktübersichten liegen nur im Speicher und fehlen nach einem
    Neustart bis zum nächsten Scan, der innerhalb der 6-Stunden-Sperre nicht
    automatisch läuft.
- Lokalisierung en/de; neue Dateien im Xcode-Projekt eingetragen.

Prüfung (automatisch):
- `swift build` erfolgreich.
- `swift test`: 503 Tests in 33 Suites plus 63 App-Tests bestanden.
- Neue Tests:
  - Kachelbildung mit Untergruppen, eigenen Items und ohne leere Kacheln.
  - Pfad mit Zyklus.
  - Pfeilschwellen inklusive Grenzwerten.
  - Sortierung mit unbekannten Werten in beiden Richtungen.
  - Navigationsreihenfolge, die fünf Modi und keine erfundenen Daten ohne
    Hubs.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.
- `git diff --check` ohne Befund.

Prüfung (visuell, isoliert):
- Debug-App mit `EVE_NEXUS_APPLICATION_SUPPORT_ROOT`, eigener Defaults-Suite
  und `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1` gestartet.
- Synthetischer v5-Katalog mit Marktgruppen, keine Nutzerdaten.
- Geprüft wurden Seitenleiste, Modusleiste, Warnungen, Pfadleiste,
  Wurzelliste, Kachel „Harvest Equipment“ und Detailspalten.
- Ohne Marktdaten zeigt die Kachel durchgehend „—“.
- Dabei korrigiert:
  - Endloser Ladezustand ohne Katalog, jetzt „Kein SDE-Katalog“.
  - Doppelt belegte Übersetzungen der Umschalter („Bezug“, „Zielbestand“ →
    „Quelle“, „Ziel“).

Offen:
- Anzeige mit echten Hub-Preisen (Live-Scan) ist nicht geprüft; die
  Preisrechnung ist nur durch Unit-Tests belegt.
- Logbuch folgt mit P5 bis P7.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P3: Volles Strukturorderbuch, Bedarf und Ordertiefe

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P3, U3
entschieden):
- Home- und Coalition-Scans laden bei Spielerstrukturen immer das volle
  Orderbuch.
- Der Bedarfsledger wird damit weitergeführt.
- Die Marktübersicht erhält die Ordertiefe am Bestpreis.
- Die Hub-Chancen bleiben unverändert.

Änderung:
- `TradeHubMarketService.structureOrderSnapshot(typeIDs:)`: Der Parameter ist
  jetzt optional. `nil` behält alle Typen der Struktur; mit Typmenge bleibt das
  Verhalten unverändert (angefragte Typen ohne Orders als leere Liste).
- `RuntimeState`:
  - Der Home-/Coalition-Strukturscan lädt mit `typeIDs: nil`.
  - Bedarfsledger und `marketState` erhalten das volle Buch.
  - Die Analyse bekommt über `opportunityAnalysisMarket` das auf
    Produkttypen beschränkte Buch (NPC-Stationen unverändert, sie lieferten
    schon immer das volle Buch).
- `MarketOrderTypeSummary`: optional `bestSellVolume` / `bestBuyVolume`
  (Stückzahl genau zum Bestpreis). Ältere JSON-Daten bleiben dekodierbar.
- `TradeRow`: `sourceVolumeAtPrice` / `targetVolumeAtPrice` passend zu den
  Umschaltern.

Prüfung (automatisch):
- `swift build` erfolgreich.
- `swift test`: 499 Tests in 32 Suites plus 62 App-Tests bestanden.
- Neu:
  - Der Strukturabruf ohne Typfilter behält das ganze Buch.
  - Die Summary-Tiefe wird summiert, ungültige Orders sind ausgeschlossen,
    alte JSON-Daten bleiben lesbar.
  - Regressionstest: Chancenzeilen und Abdeckung sind mit dem eingeschränkten
    vollen Buch identisch zum bisherigen Produktbuch.
  - Der Produktbedarf im Ledger ist mit dem vollen Buch unverändert, und neue
    Items messen eigenen Bedarf.
  - Die Tiefe in `TradeRow` folgt den Umschaltern.
  - App-Test: Produkt-Scope nur bei Strukturen.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.
- In `RuntimeFeatureStateTests` ist der Import von `EVENexusCore` jetzt
  `@testable`, damit der Test `MarketOrder`-Fixtures bauen kann.

Offen:
- Live-Scan einer echten Struktur: Dauer und Größe der Bedarfsdatei sind noch
  nicht gemessen.
- Anzeige im Handel folgt mit P4.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P2: Handelsrechner

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P2): Ein
reiner Rechner mit allen Formeln aus Abschnitt C.

Entscheidungen vor dem Start:
- U1: Max-Regel, Collateral auf Basis des Einkaufswerts.
- U2: Eigene Orders liegen einen zulässigen Preisschritt nach der
  4-Stellen-Regel besser. Relist-Gebühren sind nicht enthalten.
- Nachfrage: Main→Coalition besteht aus zwei Etappen (Kurier Main→Home plus
  Home→Coalition wie bei den Hub-Chancen).
- Nachfrage: Der Jump Freighter je Einheit wird bei voller Ladung angesetzt.

Änderung:
- Neu `Sources/EVENexusCore/Trade/TradeModels.swift`:
  - `TradeMode` mit fünf Modi und `TradeQuoteSide` (Min-Sell/Max-Buy).
  - `TradeHubFees` (direkt aus `MarketTaxConfiguration`).
  - Transport-Etappen (Kurier, Jump Freighter, nicht verfügbar).
  - `TradeItemInput`, `TradeRow`, `TradeRowIssue`, `TradeTransportQuote`.
- Neu `TradeCalculator.swift`:
  - `MarketPriceTick` (`nextBelow` / `nextAbove`).
  - `TradeCalculator.row/rows` mit Diff %, Einkauf, Transport, Netto, Gewinn,
    Marge, ROI und Ziel-Spread.
  - `transportPerUnit` (Kachel-Richtwert) und `transportQuote` (Menge;
    Kurier über `LogisticsCostCalculator`).
- Neue Dateien und Tests in `EVENexusSimple.xcodeproj` eingetragen
  (Gruppe `Trade`).

Prüfung (automatisch):
- `swift build` erfolgreich; `swift test` mit 495 Tests in 32 Suites plus 61
  App-Tests bestanden.
- Neue `TradeCalculatorTests` (9 Tests) decken ab:
  - Preisschritte und Grenzfälle (Zehnerpotenzen, 0,01-Untergrenze).
  - Importroute mit Sofortkauf und Sell-Order.
  - Buy-Order und Direktverkauf.
  - Übereinstimmung mit `MarketPriceEngine` bei listedSale.
  - Station Trading.
  - Fehlende Werte: unbekannt statt 0.
  - Zwei-Etappen-Transport sowie Jump-Freighter- und Vertragslimit.
  - Mengenrechnung mit Vertragsrundung und angefangenen Flügen.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden.
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.

Offen:
- Die 4-Stellen-Preisregel ist nicht gegen eine CCP-Quelle belegt; die
  Live-Prüfung steht aus.
- Ordertiefe kommt mit P3.
- RuntimeState-Anbindung und Oberfläche kommen mit P4.
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Handel P1: SDE-Marktgruppen

Ziel (Eigentümerauftrag, [Handel-Plan](Documentation/HANDEL_PLAN.md) P1): Die
Marktgruppen aus dem SDE importieren. Sie sind die Grundlage für die
Handelskacheln nach dem Referenzbild.

Änderung:

- EVEStaticDataKit:
  - Neuer Datensatz `SDEDatasetKind.marketGroups` (`marketGroups.jsonl`, als
    letzter Fall angehängt, damit die Hash-Reihenfolge stabil bleibt).
  - Neuer Typ `StaticMarketGroupSnapshot`, Batch `.marketGroups` und Collector.
  - Mapper `mapMarketGroup`: `_key`, `name.en` und `hasTypes` sind Pflicht,
    `parentGroupID` ist optional.
  - Die Snapshot-Validierung weist doppelte Marktgruppen-IDs ab. Unbekannte
    Elterngruppen werden dagegen nicht erzwungen.
  - Feldnamen geprüft gegen das Community-Schema `sde.riftforeve.online`
    (Build 3632936). CCP veröffentlicht kein offizielles Schema;
    `types.marketGroupID` ist in der lokal vorhandenen `types.jsonl` belegt.
- `SQLiteStaticCatalog`:
  - Katalogadapter 5 mit der Tabelle `market_groups`, einem Index auf
    `parent_id` und `item_types.market_group_id`, in beiden Writern
    (Snapshot und Streaming).
  - Neues Protokoll `MarketGroupCatalogQuerying` mit `marketGroups()` und
    `tradeItems(inMarketGroupSubtree:)` (rekursives CTE). Beide prüfen, ob die
    Tabelle existiert, und melden sonst `requiresSDEReimport`.

Prüfung (automatisch):
- `swift build` erfolgreich; `swift test` bestanden (486 Tests in 31 Suites
  plus 61 App-Tests in 3 Suites).
- Neue Katalogtests: Baum und Teilbaum aus beiden Writern, unveröffentlichte
  Items ausgeschlossen, fehlendes Packvolumen bleibt `nil`, Altkatalog ohne
  Tabelle meldet Neuimport, doppelte IDs werden abgewiesen.
- `swift test --package-path Packages/EVEStaticDataKit`: 11 Tests bestanden
  (neu: Mapper-Pflicht- und Optionalfelder).
- Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`.

Hinweise:
- Der installierte Katalog bleibt bis zum ausdrücklichen Neuimport ein
  v4-Katalog.
- Ältere bereitgestellte SDE-Pakete mit acht Dateien lassen sich nicht erneut
  mappen. Der Neuimport lädt das offizielle Archiv ohnehin neu.

Offen:
- Neuimport mit dem echten Archiv; die Live-Prüfung, dass `marketGroups.jsonl`
  im offiziellen ZIP enthalten ist, steht noch aus.
- Keine Oberfläche (folgt mit P4).
- Eigentümerabnahme offen.

## 22. Oktober 2026 – Plan für den Bereich Handel (P0)

Ziel (Eigentümerauftrag): Ein Handelsbereich nach dem Referenzbild. Er vergleicht
Marktgruppen-Kacheln Main-Hub gegen Ziel-Hub, bietet Import Main→Home und
Main→Coalition sowie Station Trading getrennt je Hub. Steuern, Logistik und
Tagesbedarf fließen ein. Dazu kommt ein Einkaufs-Logbuch, das mit den
Wallet-Transaktionen der Charaktere abgeglichen wird.

Ergebnis: [Documentation/HANDEL_PLAN.md](Documentation/HANDEL_PLAN.md) enthält
die Entscheidungen, Code-Befunde, Formeln und die Prompts P1–P8. Die offenen
Punkte U1–U8 werden im jeweiligen Prompt erfragt. Ein Verweis steht in
`ROADMAP.md`.

Prüfung: nur Dokumentation, kein Code geändert. Deshalb kein Build und kein
Testlauf.

Offen: P1–P8 sind nicht implementiert. `PRODUCT.md` bleibt unverändert, weil
sich das Verhalten der App nicht geändert hat.

## 22. Oktober 2026 – Erfindungskosten in den Hub-Chancen

Ziel (Eigentümerauftrag): Prüfen, ob Erfindungskosten für T2-Gegenstände in
Main-, Home- und Coalition-Hub-Chancen enthalten sind, und sie andernfalls
einbeziehen.

Befund: Nicht enthalten. T2-Zeilen trugen nur die optionale, standardmäßig
ausgeschaltete manuelle Blueprint-Umlage; eine Erfindungsrechnung gab es nur
für die Bewertung eigener BPCs im Planner.

Änderung:

- `RuntimeState`: Erfindungsrechnung aus `ownedBPCValues` in
  `inventionCost(outputBlueprintTypeID:…)` mit `ScienceCostInputs`
  herausgelöst; beide Stellen nutzen dieselbe Rechnung. Das Main-Hub-Orderbuch
  wird jetzt einmal für alle Datacores und Decryptoren vorab geladen (vorher nur
  mit den Materialien des ersten Aufrufs).
- Neu `loadOpportunityInventionEstimates`: Schätzung ohne Decryptor je
  T2/T3-Blaupause eines Hubs, eine Stunde wiederverwendet; parallele
  Anforderungen werden gesammelt statt verworfen.
- Core: `ManufacturingOpportunityInventionEstimate`, Route `.invention` in der
  BPC-Beschaffung; die günstigste nutzbare Route aus Erfindung, Vertrag und
  LP-Store wird eingepreist. T2-BPC-Verträge werden dafür mitgeladen.
- Hub-Ansicht: Erfindungszeile in **Blaupausenbeschaffung**, Kosten-Tooltip,
  Spalten- und Schalterhilfe ergänzt.

Prüfung (automatisch): `swift build` erfolgreich; `swift test` 483 Tests in
31 Suites bestanden (neu `techIIRowsPriceTheExpectedInventionCostOrACheaperContract`).
Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`;
`swift test --package-path Packages/EVEStaticDataKit` 8 Tests bestanden.

Offen: Decryptoren werden für Chancen nicht optimiert (Basis ohne Decryptor).
Reverse Engineering (T3) bleibt unverfügbar, solange keine BPC-Verträge
vorliegen. Live-Prüfung und visuelle Eigentümerabnahme stehen aus.

## 22. Oktober 2026 – LP-Store-Route, Charakter-LP und Dashboard aus den Hubs

Ziel (Eigentümerauftrag, Fortsetzung): LP-Store-Kosten (LP, ISK,
Pflichtgegenstände) selbst einpreisen, LP und ISK der Charaktere abrufen und
die Bezahlbarkeit zeigen; die Dashboard-Topliste muss die Werte der drei
Hub-Chancenansichten verwenden statt eigener Annahmen.

Befund: Der LP-Store-Katalog wurde nie abgerufen (`refreshLoyaltyStoreCatalog`
ohne Aufrufer, keine Katalogdatei vorhanden). Damit wurden LP-Store-Blaupausen
bisher nur über die Fraktions-/Storyline-Klasse erkannt.

Änderung:

- `LoyaltyStoreCatalog`: speichert vollständige Angebote (`LoyaltyStoreOffer`),
  Corporation-Namen und ESI-Durchschnittspreise; Altkataloge ohne Angebote
  bleiben lesbar und lösen eine Aktualisierung aus. Automatisches Laden beim
  Start bei fehlendem, unvollständigem oder über einen Tag altem Katalog.
- Neu `LoyaltyStoreValuation.swift`: `LoyaltyPointValuation` (LP-Wert =
  Median der fünf besten Angebote je Corporation), `CharacterLoyaltyPoints`,
  `LoyaltyStoreBlueprintOffer(Builder)`.
- Neu `LoyaltyPointsSyncService.swift`: Scope `esi-characters.read_loyalty.v1`
  (in `EVEScope.versionOne`, Scope-Erklärung in den Einstellungen), Abruf bei
  jeder Charaktersynchronisierung, eigene JSON-Datei statt SwiftData-Schema.
- BPC-Beschaffung: zweite Route `loyaltyStore`; gewählt wird die günstigere
  nutzbare Route, die LP-Route nur mit genug LP eines bekannten Charakters.
  LP-BPC-Runs aus unerforschten Vertrags-BPCs, sonst 1 Run.
- Hub-Ansicht: Abschnitt **Blaupausenbeschaffung** in den Zeilendetails mit
  LP- und Wallet-Deckung; Schalter heißt jetzt **Eigene BPCs vorhanden**.
- Dashboard: `ManufacturingOpportunityTopRanking` (eigene Standardannahmen)
  entfernt. Die Hub-Ansichten melden ihre sichtbaren Zeilen als
  `HubTopOpportunityResult`; das Dashboard zeigt diese mit Stand und Hinweis
  auf neuere Scans.
- Seitenleiste: Zeile **LP-Stores** unter Automatische Daten.

Prüfung (automatisch): `swift build` erfolgreich; `swift test` 482 Tests in
31 Suites bestanden (neu u. a. `lpValueIsTheMedianOfTheFiveBestPricedOffers`,
`blueprintOffersDistinguishUnknownFromZeroLoyaltyPoints`,
`cheaperLoyaltyStoreRouteIsUsedOnlyWithEnoughLoyaltyPoints`,
`hubTopListRanksTheHubProjectionAndSkipsRowsWithoutPotential`).
Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`;
`swift test --package-path Packages/EVEStaticDataKit` 8 Tests bestanden.

Offen: Der neue LP-Scope erfordert eine erneute Anmeldung der Charaktere. Der
erste Katalogabruf (rund 500 NPC-Corporations) läuft einige Minuten im
Hintergrund. Die Dashboard-Spalte eines Hubs aktualisiert sich erst beim
Öffnen des Hubs. Der LP-Wert beruht auf ESI-Durchschnittspreisen, nicht auf
Hub-Orderbüchern. Live-Abruf und visuelle Eigentümerabnahme stehen aus.

## 22. Oktober 2026 – Hub-Chancen: Vertragsspalten, Tooltips, BPC-Kauf

Ziel (Eigentümerauftrag): In Main-, Home- und Coalition-Hub-Chancen das
Vorzeichen von Vertragspreis/-gewinn eindeutig machen, alle Spalten per
Mouse-Over erklären und den Kauf von LP-, Fraktions- und Storyline-BPCs in die
Kosten einrechnen.

Änderung:

- Vertragsspalten: Die Farbe zeigt nur noch das Vorzeichen (grün +, rot −).
  Vorher war ein vorläufiger Index orange wie eine Warnung. „≈“ bleibt, und ein
  Zell-Tooltip erklärt Vorzeichen, vorläufigen Index und fehlenden Gebührensatz.
- Spaltenköpfe Aufgabe, Gegenstand, Menge, Dauer, Gruppe und Kategorie
  erklären jetzt ihre Berechnung; der Kosten- und Vertragsgewinn-Tooltip wurde
  ergänzt.
- Core: `ManufacturingOpportunityBlueprintAcquisitionProjector` erkennt
  BPC-pflichtige Zeilen (LP-Store-Blaupause, Fraktion, Storyline) und bewertet
  den Kauf über `ProductionTreeBPCContractSelector`, anteilig je genutztem Run.
  `ManufacturingOpportunityContractContext` trägt BPC-Angebote,
  LP-Store-Blaupausen und den Schalter „Eigene LP oder BPCs vorhanden“.
- `RuntimeState.loadOpportunityContractReferences` liest die BPC-Angebote
  gebündelt mit den Produktpreisen aus dem lokalen Index, begrenzt auf die
  Vertragsregionen.
- Neuer Schalter unter Kosten und Budget (`market-opportunities.cost.blueprint.own-rights`).

Prüfung (automatisch): `swift build` erfolgreich; `swift test` 476 Tests in
31 Suites bestanden (neu:
`loyaltyStoreAndFactionBlueprintsPriceTheBPCPurchaseIntoTheCost`).
Natives `xcodebuild … -configuration Debug … test` mit `** TEST SUCCEEDED **`;
`swift test --package-path Packages/EVEStaticDataKit` 8 Tests bestanden.

Offen: LP-Store-Preise (LP + ISK + Pflichtgegenstände) werden nicht bewertet;
mit eigenen LP gilt die manuelle Blueprint-Umlage. Die Dashboard-Top-Liste
rechnet weiterhin ohne BPC-Kauf (am selben Tag behoben, siehe oben).
Visuelle Eigentümerabnahme.

## 22. Oktober 2026 – Manuelle Preisprofile entfernt

Ziel (Eigentümerauftrag): Prüfen, ob die Preisprofile in den Markteinstellungen
irgendwo verwendet werden, und sie andernfalls entfernen.

Befund: Keine Verwendung. Profile wurden nur geschrieben (Einzelpreis, CSV,
Planpreise), angezeigt, gesichert und in der Diagnose gezählt.
`ManualPriceProfile.price(_:at:)` rief nur ein Test auf;
`ConsolidatedProject.priceProfileID` wurde nie gesetzt.

Änderung:

- Markteinstellungen: Panel **Preisprofile** (`ConsolidationPricesView`,
  `ConsolidationPriceTable`) entfernt.
- `ConsolidationImports`: Importart `prices` entfernt; Wertspalte ohne Angabe
  ist `quantity`.
- `ConsolidationWorkspace`: `createPriceProfile`, Profil-Vorschauzeilen und
  ID-Prüfung entfernt; `priceProfiles` als Altdatenfeld dokumentiert.
  `ManualPriceProfile.price(_:at:)` entfernt, die Struktur bleibt für das
  unveränderte Dekodieren.
- Diagnoseexport zählt Preisprofile unter den Altdaten.
- Test `moneyIsExactAndValidityEndIsExclusive` → `moneyIsExact` (Gültigkeitsteil
  entfällt mit der Funktion).
- Doku: PRODUCT, ARCHITECTURE, PROJECT_STATE, DECISIONS, FEATURE_COVERAGE,
  FUNCTIONAL_CONSOLIDATION, FUNCTIONAL_VALIDATION, COMPONENTS.

Daten: Format, SwiftData-Schema, Migrationen und Sicherungen unverändert;
gespeicherte Profile bleiben erhalten.

Prüfung (automatisch): `swift build` erfolgreich; `swift test` 474 Tests in
31 Suites bestanden; natives `xcodebuild … -configuration Debug … test` mit
`** TEST SUCCEEDED **`. `EVEStaticDataKit` nicht berührt.

Offen: visuelle Eigentümerabnahme der Markteinstellungen.

## 22. Oktober 2026 – Regionsauswahl für den Vertragsimport

Ziel (Eigentümerauftrag): In den Einstellungen wählen, ob der Import
öffentlicher Verträge das gesamte Universum oder nur ausgewählte Regionen
abruft; Trade-Hub-, Hub-Rollen- und Produktionsregionen markiert und oben;
Hub-Chancen rechnen nur mit dem gewählten Umfang.

Änderung:

- `PublicContractStore`: neue Einstellung `region_scope` in
  `contract_settings` (fehlend = Universum, kein Schemawechsel).
  `regionSchedule`, `pendingContractIDs`, `automationState`, `progress`,
  `search`, `includedOffers` und `facets` filtern auf den Umfang. Zeilen
  abgewählter Regionen bleiben erhalten.
- `PublicContractIndexer`: `regionScope`, `setRegionScope`, `knownRegions`
  (lädt die ESI-Regionsliste einmalig, falls noch keine bekannt ist).
- Neu `PublicContractRegion`, `PublicContractRegionRole`,
  `PublicContractRegionOption`, `PublicContractRegionCatalog` in
  `PublicContractModels.swift` (Hinweise und Sortierung).
- `RuntimeState`: veröffentlichter Umfang, `loadPublicContractRegions`,
  `applyPublicContractRegionScope` (Cache der Chancen-Vertragspreise
  verworfen, Fortschritt/Facetten neu, Automatik neu geplant);
  `projectUniverseWide` erhält den Umfang als `allowedRegionIDs`.
- Markteinstellungen: neues Panel **Vertragsregionen**
  (`PublicContractRegionSettingsPanel` in `PublicContractsView.swift`) mit
  kopierbaren Regionsnamen (`EVEEntityText`), getrennter Checkbox, Filter,
  Schnellauswahl Hub-/Produktionsregionen. Hub-Chancen laden Vertragspreise
  bei Umfangsänderung neu.
- Neue Dateien bewusst vermieden, damit `project.pbxproj` unverändert bleibt.
- Nachbesserung nach Sichtprüfung: Der Coalition Hub (Spielerstruktur in
  C-J6MT) wurde keiner Region zugeordnet, weil der gespeicherte Ort nur das
  Sonnensystem kennt. `PublicContractRegionCatalog` nimmt jetzt eine
  Zuordnung System → Region entgegen (`unresolvedSolarSystemIDs`,
  `systemRegions`); das Panel löst sie über `resolveSolarSystem` (ESI,
  zwischengespeichert) auf. Dadurch steht Insmother als Koalitions-Hub oben.

Prüfung:

- `swift build`; vier neue Tests in `PublicContractTests` (Abruf nur
  gewählter Regionen, Filterung von Angeboten/Suche/Fortschritt/Facetten,
  Hinweise und Reihenfolge der Regionsoptionen, Coalition-Hub-Region über
  das Sonnensystem).
- `swift test`: 475 Swift-Testing-Tests in 31 Suites, 61 Tests in 3 Suites
  und 8 XCTest-Tests bestanden.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED`.
- `EVEStaticDataKit` nicht berührt, nicht erneut getestet.

Offen: Sichtprüfung des Panels und Live-Abruf mit Regionsauswahl durch den
Eigentümer.

## 22. Oktober 2026 – „Automatische Daten“ in die Seitenleiste verlegt

Ziel (Eigentümerauftrag): Dashboard grafisch entlasten; die Karte
„Automatische Daten“ links unten in der Navigation oberhalb des
Vertragsimports einordnen.

Änderung:

- Neue View `SidebarAutomaticDataStatus` in `ContentView.swift` mit den
  bisherigen Zeilen (Programmstart, Verträge, Main-/Home-/Coalition-Hub-Markt)
  und dem Menü zum Pausieren/Fortsetzen der Main-Hub-Aktualisierungen.
  Statusberechnung unverändert aus `DashboardView` übernommen.
- Einklappbar über die Kopfzeile (`sidebar.automatic-data-expanded`,
  Standard ausgeklappt); Mini-Fortschritt bei laufenden Abrufen.
- `AutomaticStatusRow` setzt den Status bei zu geringer Breite unter den
  Titel. Die bisherige Fußzeile „Marktanalysen“ entfällt.
- Dashboard-Kopf zeigt nur noch Titel und Untertitel; dadurch entfällt die
  große Leerfläche über „Industrie & Jobs“.

Prüfung:

- `swift build`, `swift test`: 471 Swift-Testing-Tests in 31 Suites, 61 Tests in 3 Suites und 8 XCTest-Tests bestanden.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED`.
- `EVEStaticDataKit` nicht berührt, nicht erneut getestet.

Offen: Sichtprüfung in der laufenden App (Höhe der Seitenleiste bei kleinen
Fenstern) durch den Eigentümer.

## 22. Oktober 2026 – Fehlergrund je Charakter im Startablauf

Anlass: Am 21.10. scheiterte beim Programmstart der Abgleich aller Charaktere
(„Charaktere: Nicht verfügbar“, authentifizierte Analysen „Unvollständig“),
ohne dass ein Grund sichtbar war; der Batch-Abgleich verwarf die Fehlermeldung.
Nach einem manuellen Abgleich lief wieder alles. Die Ursache ist nicht mehr
feststellbar; die Planner-Änderungen berühren diesen Ablauf nicht.

Änderung:

- `CharacterBatchSyncResult.failures` hält den Grund je Charakter;
  `failureGroups` fasst gleiche Gründe zusammen.
- `CharacterBatchSynchronizer` trennt die Schritte: Autorisierung lesen,
  SSO/ESI-Abgleich, Zuordnung des Ergebnisses, lokales Speichern.
- Die bisherigen Fehlertexte der Charakterverwaltung liegen gemeinsam in
  `EVEConnectionErrorText`.
- Dashboard „Automatische Daten“ zeigt die Gründe unter der Zeile
  Charaktere; der manuelle Dashboard-Abgleich nennt sie in der Fehlermeldung.

Prüfung (isolierte Pfade unter `/private/tmp/eve-functional/sync-reasons-20261022`):

- `swift test`: 471 Swift-Testing-Tests in 31 Suites, 61 Tests in 3 Suites
  (neu: `characterSyncFailuresAreGroupedByReasonWithReadableTexts`).
- `swift test` in `Packages/EVEStaticDataKit`: 8 Tests.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED`.

Offen: Sichtprüfung beim nächsten echten Fehlerfall.

## 21. Oktober 2026 – Teilaufträge in der Bauauftragsliste mit Rundung je Auftrag

Ziel (Eigentümerauftrag): Die Teilaufträge nicht nur für die Zeitschätzung,
sondern als echte Aufträge der Bauauftragsliste verwenden, mit korrekter
Materialrundung je Auftrag.

Änderung:

- **Planner:** Neuer Abgleich `reconcileJobPieces` nach dem Aufbau des
  Produktionsbaums. Je hergestelltem Produkt Gesamtbedarf über alle Zweige,
  Lageranteil, Runs, Bauplan-Zuordnung (`consumeBlueprintJobs`), Aufteilung
  nach `splitRuns` und Rundung jedes Inputs je Teilauftrag; Verarbeitung nach
  allen Verbrauchern (topologisch), damit Rundungsänderungen an Vorprodukte
  weitergehen. Bedarf, Lager, Einkauf, Herstellungsmengen und Aufträge kommen
  aus diesem Abgleich; die frühere Zusammenfassung gleicher Zwischenprodukte
  (`consolidateIntermediateJobs`) entfällt. An eine ausgewählte BPO/BPC
  gebundene Aufträge bleiben ganz. Der Produktionsbaum zeigt weiter den
  Zweigbedarf.
- **Modell:** `IndustryJobCost.piece`/`pieceCount` (optional, alte Pläne ohne).
- **Zeitplan:** arbeitet auf den echten Teilaufträgen (keine zweite
  Aufteilung); anteilige Abhängigkeiten je Produkt.
- **Produktionsübersicht:** Materialkosten je Planzeile werden nach Zweigwerten
  gewichtet und auf den Planwert skaliert (Summe exakt gleich).
- **UI:** Bauauftragsliste mit „Auftrag k von n“ und Dauer, Texte angepasst.

Geänderte Erwartungen: Zwei Planzeilen mit gemeinsamem Zwischenprodukt rechnen
jetzt einen 3-Run-Auftrag (ME 10: 11 statt 4 + 8 = 12 Rohstoffe); die Tests
`stockFirstSharedDemandAgreesWithEveryRequestProjection` und
`recordingStockFirstPlanPreservesPlannerAndRequestCosts` sind entsprechend
angepasst. Neu: `splitIntermediateJobsRoundMaterialsPerInstalledJob`.

Prüfung (isolierte Pfade unter `/private/tmp/eve-functional/job-pieces-20261021`):

- `swift test`: 471 Swift-Testing-Tests in 31 Suites, 60 Tests in 3 Suites.
- `swift test` in `Packages/EVEStaticDataKit`: 8 Tests.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED`.

Offen:

- Ein Produkt, das erst durch die Neurundung über den Lagerbestand hinaus
  benötigt wird und dessen Inputs im Baum nie besucht wurden, kauft diese
  Inputs ohne eigene Bezugswahl.
- Eigentümerabnahme mit der Rhea offen.

## 21. Oktober 2026 – Auftragsaufteilung, Reaktionsstapel und Zeitplan

Ziel: Die vorhandenen Einstellungen „Don't split jobs shorter than“ und „No jobs
longer than“ in der Auftragsdauer nutzen, Reaktionen standardmäßig in Stapeln zu
100 Runs rechnen und die Zeitlogik nachvollziehbar machen. Alles, was nicht
aufeinander wartet, soll gleichzeitig laufen.

Änderung:

- **Core:** `ProductionSchedulingConfiguration.reactionRunsPerJob` (Standard 100,
  alte Daten ebenfalls 100) und `splitRuns(...)`: Fertigung nach Tage-Fenster
  plus Verteilung auf freie Slots, Reaktionen in Stapeln von mindestens der
  Stapelgröße (ein Rest verlängert die Stapel), Wissenschaft ungeteilt.
- **Scheduler:** Der Planer baut Teilaufträge mit anteiligen Abhängigkeiten
  (ein Teil wartet nur auf seinen Anteil am Vorprodukt) und liefert Start/Ende
  je Teil. Der Plan speichert die Aufteilung und die Einträge im
  `slotSchedule`.
- **UI:** Feld „Reaktions-Runs je Auftrag“ mit Erklärung der Aufteilung; im
  Planner die Aufteilungsangabe unter der Dauer und die sortierbare
  Aufklappliste „Zeitplan“.
- Die Teilaufträge betreffen nur die Zeitschätzung; Materialien, Kosten und die
  Bauauftragsliste bleiben ungeteilt.

Prüfung (isolierte Pfade unter `/private/tmp/eve-functional/slots-split-20261021`):

- `swift test`: 470 Swift-Testing-Tests in 31 Suites, 60 Tests in 3 Suites
  (neu: 3 Tests zu Reaktionsstapeln, Tage-Fenster und anteiligen Abhängigkeiten).
- `swift test` in `Packages/EVEStaticDataKit`: 8 Tests.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED`.

Offen:

- Materialrundung je geteiltem Auftrag: im folgenden Eintrag umgesetzt.
- Eigentümerabnahme mit der Rhea und echten Charakteren offen.

## 21. Oktober 2026 – Slot-basierte Auftragsdauer und Industrie-Charaktere

Ziel: Die voraussichtliche Auftragsdauer des Planners aus den tatsächlich
verfügbaren Slots der Charaktere berechnen, statt aus einer pauschalen Slot-Zahl
ohne Abhängigkeiten; je Charakter festlegen, ob, wofür und mit wie vielen Slots
er eingesetzt wird.

Änderung:

- **Core:** `ProductionSchedulingConfiguration` um `scienceSlots` und
  `characterAssignments` (`CharacterIndustryAssignment`: Freigabe, erlaubte
  Tätigkeiten, optionale Grenze je Slot-Art) erweitert; ältere gespeicherte
  Konfigurationen dekodieren mit Standardwerten. `IndustrySkillSlotLimits`
  leitet das Skill-Maximum aus den aktiven Skillstufen ab (SDE-geprüfte IDs
  3387/24625, 45746/45748/45749, 3406/24624). `IndustrySlotScheduler` plant
  alle Aufträge deterministisch mit Abhängigkeiten (Vorprodukt vor Verbraucher,
  Kopie/Forschung/Invention vor dem versorgten Fertigungsauftrag).
  Wissenschaftsaufträge laufen nicht mehr pauschal nacheinander vor der
  gesamten Fertigung.
- **Plan:** `IndustryPlanSnapshot.slotSchedule` speichert Quelle und Slot-Zahlen;
  fehlt für eine benötigte Tätigkeit jeder Slot, ist die Dauer „Nicht
  verfügbar“ statt 0. Alte Pläne bleiben unverändert.
- **UI:** Neuer Bereich „Industrie-Charaktere“ in den Industrieeinstellungen;
  manuelles Feld „Wissenschafts-Slots“; der Planner nennt unter der Dauer Quelle
  und Slot-Zahlen.

Prüfung:

- `swift test`: 466 Swift-Testing-Tests in 30 Suites (5 neue Tests für
  Skill-Maxima, Slot-Auflösung, Scheduler, Legacy-Dekodierung und
  Planner-Abhängigkeit).
- `swift test` in `Packages/EVEStaticDataKit`: 8 Tests.
- `xcodebuild test` unsigniert, isolierte Pfade: `TEST SUCCEEDED`
  (466 Swift-Testing-Tests, 8 XCTest-Fälle).

Offen:

- Aufteilen langer Aufträge: im folgenden Eintrag umgesetzt.
- Industry-/Advanced-Industry-Zeitboni der Charaktere fließen weiterhin nicht
  in die Auftragsdauer ein.
- Visuelle und fachliche Eigentümerabnahme mit echten Charakteren offen.

## 21. Oktober 2026 – Commit und Push des Hub-Chancen-Ausbaus

Auf Auftrag des Eigentümers ist der Stand P0–P13 als `9000f3f` auf `main`
committet und nach `origin/main` gepusht (Fast-Forward von `b6e2547`, kein
Tag). Vorab geprüft: `origin/main` war unverändert, `git diff --check` war
fehlerfrei und der Diff enthielt keine Tokens. Dieser Nachtrag korrigiert die
Aussage in PROJECT_STATE.md, der Stand sei nicht committet.

## 21. Oktober 2026 – P13: Abschluss Hub-Chancen-Ausbau

Ziel: Die Dokumentation auf den Stand P0–P12 bringen, die Nachweise eintragen
und einen Owner-Testleitfaden bereitstellen. Keine neuen Funktionen.

Änderung:

- **ARCHITECTURE.md:** Version-1-Grenzen um den Hub-Vergleich ohne
  Aufteilungsoptimierung ergänzt; Scan-Auslösung und Wiederverwendung an die
  automatische Planung angepasst.
- **PRODUCT.md:** Typischer Arbeitsablauf um Startablauf, Top-Chancen,
  Hub-Chancen, Zielmarkt, Allianzmarkt und Kaufort-Hinweis ergänzt.
- **ACCEPTANCE.md:** Neuer Abschnitt mit den automatischen Nachweisen je
  Schritt; Live- und Owner-Abnahme getrennt als offen ausgewiesen.
- **HANDOFFS.md:** Neue Übergaben; die überholten Opt-in-Teile alter Zeilen sind
  als ersetzt markiert.
- **PROJECT_STATE, README, ROADMAP:** aktualisiert.
- **HUB_CHANCEN_PLAN.md:** Status „implementiert, automatisch geprüft“,
  Checkliste mit offenem Live-/Owner-Teil und Owner-Testleitfaden
  (Abschnitt E).
- **Leerzeichen:** Zwei Zeilen mit Leerzeichen am Zeilenende entfernt.

Prüfung:

- `swift test`: 461 Swift-Testing-Tests in 29 Suites plus 59 Tests in 3 Suites.
- `xcodebuild test` unsigniert: `TEST SUCCEEDED` (461 Swift-Testing-Tests,
  8 XCTest-Fälle).
- `swift test --package-path Packages/EVEStaticDataKit`: 8 Tests, ein
  vorgesehener Real-SDE-Skip.
- `git diff --check` fehlerfrei.

Offen:

- Live-Prüfung (Charaktere, Structure-Märkte, DOTLAN, vollständiger
  Vertragsindex).
- Visuelle und fachliche Eigentümerabnahme nach Leitfaden.

## 21. Oktober 2026 – P12: Kaufort-Hinweis für Mineralien und Mondmaterialien

Ziel: In der Planner-Einkaufsliste den günstigsten Kaufort je Mineral und
Mondmaterial aus den vorhandenen Analysen zeigen, mit Multibuy je Kaufort und
ohne Änderung der Plankosten.

Änderung:

- **Core:**
  - `EVEMultibuyExport.make(items:)` ist jetzt der gemeinsame Formatierer; die
    bestehenden Exporte nutzen ihn unverändert.
  - `MaterialPurchaseLocationHint` enthält die Main-Hub-Differenz nur bei
    vollständiger Markttiefe.
  - `MaterialPurchaseLocationHints` mit `project` und `multibuyGroups`.
- **Planner:** `PlannerPurchaseLocationHintPanel` in der Einkaufsliste mit
  Analyse-Stand (aktuell/veraltet/nicht geladen), sortierbarer Tabelle
  (`PurchaseLocationHintSorting`, gemeinsamer Header), kopierbaren Namen und
  Multibuy-Knöpfen je Kaufort.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.
- **Testdatei:** Die neue Test-Suite liegt in der bereits im Xcode-Projekt
  registrierten `MarketPricingTests.swift`; das Projekt selbst ist unverändert.

Prüfung:

- Zwei neue Tests: Zuordnung (nur analysierte Materialien, fehlendes Angebot,
  unvollständige Main-Hub-Tiefe), Gruppierung und gemeinsamer Formatierer;
  Sortierung mit unbekannten Werten am Ende.
- `swift test`: 461 Tests in 29 Suites und 59 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.

Offen: Visuelle Owner-Abnahme. Als Nächstes folgt P13 (Abschluss).

## 21. Oktober 2026 – P11: Allianzmarkt als manuelles Verkaufsziel

Ziel: Ein zehntes Planner-Szenario „Allianzmarkt (manuell)“ mit eigenem
Zielmarkt und kopierbarem Slack-Angebot einführen.

Änderung:

- **Core:**
  - Neu sind `PlannerAllianceSaleInput`, `PlannerAllianceSaleResult` und
    `PlannerAllianceSaleCalculator` (mit Angebotstext).
  - Die Kosten sind `totalProductionCost` plus der Ausgangstransport des
    Lieferhubs. Verkauft wird nur die abgenommene Menge; die Gebühr ist
    standardmäßig 0 % als Annahme.
  - Unverfügbar ohne Preis, Route, Kosten oder bei mehreren Produkten.
  - `PlannerTargetMarket.allianceMarket`, das optionale Feld
    `IndustryPlanSnapshot.allianceSale` und ein Vorschlag inklusive Allianz.
- **Planner:**
  - Karte mit Ergebnis, Hinweisen (manuelle Gebühr, unverkaufter Rest, Grund
    bei Unverfügbarkeit) und Eingabefeldern.
  - Der ortsabhängige Parser `PlannerAllianceInputParser` prüft die Eingaben.
  - Entwurf in `planner.alliance-sale.draft.v1`; neue Pläne übernehmen die
    Eingaben.
  - Die Karte ist umrandet, wenn der Allianzmarkt als Zielmarkt gewählt ist.
- **Kopieren:** `EVEEntityText` hat eine optionale eigene
  Barrierefreiheitsbeschriftung für den Slack-Text bekommen, mit derselben
  Kopierrückmeldung.
- **Produktionsübersicht:** Die Spalte „Ziel“ kennt den Rang 3 für
  Allianzmarkt.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung:

- Vier neue Tests:
  - volle Kosten bei Teilabnahme, Standardgebühr, Angebotstext;
  - Unverfügbarkeit ohne Preis, Route, Coalition-Szenario, Einzelprodukt oder
    Kosten sowie bei ungültiger Gebühr;
  - Vorschlag Allianz und Lesbarkeit älterer Snapshots;
  - Parser.
- `swift test`: 460 Tests in 28 Suites und 58 Tests in 3 Suites erfolgreich.
  Der eine längere Parallellauf trat wieder direkt nach dem Neubau auf.
- Xcode-Debug-Build erfolgreich.

Offen: Visuelle und fachliche Owner-Abnahme. Die Produktionsübersicht übernimmt
den Allianzpreis nicht automatisch als Verkaufspreis; der bleibt eine manuelle
Eingabe. Als Nächstes folgt P12.

## 21. Oktober 2026 – P10: Zielmarkt im Planner

Ziel: Im Planner einen Zielmarkt ausdrücklich wählen, vorschlagen, hervorheben
und speichern, ohne die Rechnung zu ändern.

Änderung:

- **Core:** `PlannerTargetMarket` mit Abbildung von `OpportunityHubRole`,
  `PlannerTargetMarketSuggestion` (höchster endgültiger Gewinn, vorläufige oder
  unverfügbare Szenarien ausgeschlossen, Gleichstand Main → Home → Coalition)
  und das optionale Feld `IndustryPlanSnapshot.targetMarket`.
- **Planner:**
  - Zielmarkt-Fläche mit Segmentauswahl, Vorschlag und „Vorschlag übernehmen“.
  - Die Karten des gewählten Hubs sind umrandet.
  - Die Entwurfswahl liegt in `AppSetting` (`planner.target-market.draft.v1`).
  - Eine Übergabe mit `targetMarket` setzt vor; die manuelle Wahl hat Vorrang.
  - Neue Pläne übernehmen die Wahl; eine Änderung beschriftet den aktiven Plan
    neu.
- **Produktionsübersicht:** Die sortierbare Spalte „Ziel“ ist hinten angehängt.
  Rang Main/Home/Coalition, „Nicht gewählt“ unbekannt.
- **Schema:** Keine SwiftData-Schemaänderung.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung:

- Drei neue Tests: Vorschlag (Maximum, vorläufig ausgeschlossen, Gleichstand,
  keiner), Speicherformat (alt ohne Feld lesbar, neu mit Feld, Rechnung
  unverändert) und Spaltenrang/Text.
- `swift test`: 457 Tests in 28 Suites und 57 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.

Offen: Visuelle Owner-Abnahme. Als Nächstes folgt P11 (Allianzmarkt als
manuelles Verkaufsziel); er erweitert `PlannerTargetMarket`.

## 21. Oktober 2026 – P9: Dashboard-Karte „Top-Chancen“

Ziel: Auf dem Dashboard je Hub die besten gespeicherten Chancen zeigen, mit
Sprung in die Chancenansicht und Übergabe an den Planner.

Änderung:

- **Rangfolge im Core:** `ManufacturingOpportunityTopRanking` bewertet nach
  täglichem Gewinnpotenzial mit Standardannahmen (`standardCostSheet`, kein
  Lager, Hub-Route). Zeilen ohne Wert fallen weg; die Reihenfolge ist stabil.
- **Dashboard:** `DashboardTopOpportunitiesPanel` zeigt bis zu 5 Einträge je
  Hub und berechnet die Rangfolge abseits des Main Actors. Hub-Titel springen in
  die Chancenansicht, „Bauen“ übergibt Charge und Zielmarkt über
  `DashboardNavigationRequest.plannerLaunch`.
- **Hinweise:** nicht konfiguriert, gleich anderem Hub, unvollständig, kein
  Scan.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung:

- Zwei neue Tests: Rangfolge (Grenze, ohne Wert ausgeschlossen, absteigend,
  Werte gleich der Standardprojektion, stabile Reihenfolge) und Übergabe der
  Charge mit Zielmarkt.
- `swift test`: 455 Tests in 28 Suites und 56 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.

Offen: Visuelle Owner-Abnahme der Karte. Als Nächstes folgt P10 (Zielmarkt im
Planner).

## 21. Oktober 2026 – P8: Öffentliche Verträge als Erlösquelle in den Hub-Chancen

Ziel: In allen Chancenansichten zusätzlich den Verkauf über einen öffentlichen
Vertrag zeigen, mit Vertragspreis, Gewinn und ROI.

Änderung:

- **Core:** Neu sind `ManufacturingOpportunityContractContext`,
  `ManufacturingOpportunityContractProjection` und
  `ManufacturingOpportunityContractProjector`. Die Projektion nutzt die
  universumsweite Referenz wie der Planner und zieht den bestätigten
  Vertragsgebührensatz ab. Ohne Satz wird „vor Vertragsgebühr“ markiert; ist der
  Index unvollständig, gilt der Wert als vorläufig.
- **Kosten und Sortierung:** `costs(…, contract:)` und die Sortierspalten
  `.contractPrice`/`.contractProfit`.
- **Runtime:** `loadOpportunityContractReferences` liest gebündelt nur den
  lokalen Index und nutzt einen gleichen Typsatz fünf Minuten wieder.
  `publicContractFeeRate(for:)` liefert den Satz je Rolle.
- **Ansicht:**
  - Spalten „Vertragspreis“ und „Vertragsgewinn“; „≈“ markiert vorläufige
    Werte.
  - Detailwerte mit Hinweisen.
  - Die Kandidatenprojektion rechnet neu, sobald Referenzen oder Satz
    wechseln.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung:

- Zwei neue Tests: bestätigte Gebühr, vor Gebühr, ungültiger Satz, vorläufig,
  kein Angebot, fehlende Kosten; Sortierung beider Spalten mit unbekannten
  Werten am Ende.
- `swift test`: 454 Tests in 28 Suites und 55 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.

Abweichung vom Prompt: Gelesen wird gebündelt für alle Typen des angezeigten
Scans, nicht nur für die gerade sichtbaren Zeilen. Wert- und Sortierfilter
brauchen die Vertragswerte vor der Sichtbarkeitsfilterung. Die
Fünf-Minuten-Wiederverwendung begrenzt die Last.

Offen: Laufzeitmessung der Indexabfrage mit vollständigem echtem Index,
Owner-Abnahme. Als Nächstes folgt P9.

## 20. Oktober 2026 – P7: Ansicht „Coalition-Hub-Chancen“

Ziel: Die Coalition-Hub-Chancen mit derselben Oberfläche zeigen, ergänzt um den
Transport Home → Coalition.

Änderung:

- **Navigation:** Neuer Bereich `coalitionHubOpportunities` nach den
  Home-Hub-Chancen.
- **Ansicht:** Daten, Fehler und Fortschritt kommen je Rolle aus
  `opportunityState(for:)`. Die Logistik läuft je Zeile über
  `saleRoute(for:)`, damit Runs-Änderungen den Weitertransport neu bepreisen.
- **Core:** `onwardTransportCost` in Logistik- und Kostenprojektion, neue
  Sortierspalte `.onwardTransport`.
- **Spalte und Details:** Neue Tabellenspalte „Home → Coalition“ mit Tooltip.
  Die Details zeigen Betrag und konkreten Unverfügbarkeitsgrund.
- **Leerzustände:** gleich Main, gleich Home (Sprung zu den Home-Hub-Chancen),
  unvollständig, kein Scan.
- **Texte:** Neue Texte deutsch und englisch, dazu die bisher unübersetzte
  Capital-Selbstsprung-Meldung.

Prüfung:

- Zwei neue Tests: aufgezeichneter Weitertransport mit sortierter Reihenfolge
  (unbekannt aufsteigend am Ende, absteigend am Anfang); Navigation, Texte und
  Schlüssel.
- `swift test`: 452 Tests in 28 Suites und 55 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.
- Einzelne langsame Parallelläufe direkt nach Neubauten waren nicht
  reproduzierbar; seriell und wiederholt dauert die Suite etwa 2,2 s.

Offen: Visuelle und fachliche Owner-Abnahme mit echtem Coalition Hub. Als
Nächstes folgt P8.

## 20. Oktober 2026 – P6: Coalition-Hub-Markt-Snapshot, Bedarf und Transport

Ziel: Für den Coalition Hub einen eigenen Markt-Snapshot, Bedarfsledger und eine
Chancenanalyse mit Transport Home → Coalition erzeugen. Der Eigentümer hat auf
Rückfrage entschieden: erst P6, danach P7.

Änderung:

- **Gemeinsamer Ablauf:** Der Home-Hub-Code aus P4 ist auf Rollen
  verallgemeinert. Neu sind `SecondaryHubOpportunityState`, die Stores je
  Rolle, `HubOpportunityScanTarget` (mit `sharesHomeHub`) und
  `analyzeSecondaryHubOpportunities`. Die bisherigen Home-Zugriffe bleiben als
  berechnete Properties.
- **Reihenfolge:** Der Main-Hub-Scan rechnet danach Home und dann Coalition.
- **Core:** `OpportunityCoalitionTransportBasis` (Kurier, Jump Freighter,
  unverfügbar) mit `transport(for:)`. Der Snapshot hat das Feld
  `coalitionTransport`, dazu kommen `saleRoute(for:)` und
  `MarketOrderSnapshot.restricted(to:)`.
- **Charakterdaten:** Die Charakter-Fähigkeiten für die Pilotenwahl übergeben
  Startablauf und Planner-Konfiguration.
- **Dashboard:** Neue Zeile „Coalition-Hub-Markt“; die Home-/Coalition-Zeilen
  nutzen jetzt eine gemeinsame Rollenfunktion.
- **Lokalisierung:** Neue Texte deutsch und englisch.

Prüfung:

- Zwei neue Tests:
  - Kurierpreis, blockiertes Capital, unverfügbare Grundlage, Zeilenroute mit
    Gesamtlogistik 2 Mio. ISK und Speicherformat;
  - Coalition-Zielauflösung inklusive gleich Main/Home.
- Die P4-/P5-Tests sind unverändert grün.
- `swift test`: 451 Tests in 28 Suites und 54 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich.

Offen:

- Live-Prüfung mit echtem Coalition Hub (Structure-ACL, DOTLAN) und
  Owner-Abnahme.
- Selbstspringende Capitals bleiben in der Chancenliste bewusst unverfügbar.
- P7 (Ansicht).

## 20. Oktober 2026 – P5: Ansicht „Home-Hub-Chancen“

Ziel: Die Home-Hub-Chancen mit derselben Oberfläche wie die Main-Hub-Chancen
zeigen.

Änderung:

- **Navigation:** Neuer Bereich `homeHubOpportunities` direkt nach den
  Main-Hub-Chancen.
- **Rolle in der Ansicht:** `ManufacturingOpportunitiesView` hat die Rolle
  `hubRole`. Daten, Fehler, Bedarf und Fortschritt kommen je Rolle aus der
  Runtime.
- **Logistik:** über `defaultSaleRoute`. Für Home gibt es keinen Rückweg zum
  Main Hub.
- **Filter:** Persistierte Filter haben eigene Schlüssel über
  `OpportunityHubRole.storageKey`; die Main-Schlüssel sind unverändert.
  Favoriten, Blueprint-Umlage und der Corporation-Hangar-Schalter bleiben
  gemeinsam.
- **Texte:** `OpportunityHubText` passt Kopf, Leerzustand, Fortschritt,
  Grundlage, Gesamtkosten-, Erlös- und Gebühren-Tooltips sowie
  Verkaufswarnungen an. Materialwarnungen bleiben „Main Hub“.
- **Leerzustände:** kein Home Hub, Home = Main, unvollständiger Ort, noch kein
  Scan.
- **Übergabe:** `PlannerLaunchRequest.targetMarket` übergibt „Home Hub“ beim
  Bauen.
- **Lokalisierung:** Neue Texte deutsch und englisch, darunter auch die
  P3-Logistikmeldungen.

Prüfung:

- Drei neue Tests: Schlüssel und Route, Textanpassung, Navigation und
  Zielmarkt-Übergabe.
- `swift test`: 450 Tests in 28 Suites und 53 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich; `plutil` OK.
- Visuelle Prüfung in der laufenden App steht aus.

Offen:

- Visuelle und fachliche Owner-Abnahme mit echtem Home Hub.
- Die Detail-Tooltips zu Runs/ME/TE nennen bewusst weiter die gewichteten
  Main-Hub-Materialpreise.
- P6.

## 20. Oktober 2026 – P4: Home-Hub-Markt-Snapshot und Bedarf

Ziel: Für den Home Hub einen eigenen Markt-Snapshot, einen eigenen
Bedarfsledger und eine Chancenanalyse erzeugen und speichern; noch ohne eigene
Ansicht.

Änderung:

- **Ablauf:** Der Home-Hub-Scan läuft am Ende jedes Main-Hub-Scans. Er nutzt
  dessen Katalog-, Material- und Anlagenkontext wieder und übernimmt damit die
  6-Stunden-Wiederverwendung, die Startfreigabe, die Priorität und den
  Planner-Vorrang.
- **Ziel und Marktdaten:** `HomeHubOpportunityScanTarget` bestimmt, woher der
  Markt kommt: NPC-Station (Regionsbuch) oder Player Structure (Structure-Markt
  mit Charakter-Lease, Home-Händler bevorzugt). Bei `sharesMainHub` läuft kein
  zweiter Scan; ein unvollständiger Ort wird gemeldet.
- **Speicher:** Eigene Stores unter `market/home-hub-*.json`. Gespeicherte
  Home-Daten werden beim Start geladen.
- **Autorisierungen:** Startablauf und Dashboard übergeben die
  Charakter-Autorisierungen mit `rememberMarketAuthorizations`.
- **Dashboard:** Neue Zeile „Home-Hub-Markt“ in der Karte „Automatic data“.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung:

- Zwei neue Tests: Zielauflösung (nicht konfiguriert, gleich Main, NPC,
  Struktur, unvollständig, Legacy) und leerer Grundzustand.
- Die Rollenrechnung selbst ist durch die P3-Tests abgedeckt.
- `swift test`: 449 Tests in 28 Suites und 51 Tests in 3 Suites erfolgreich.
- Xcode-Debug-Build erfolgreich; `plutil` für beide Sprachdateien OK.
- Ein echter ESI-Abruf (NPC-Region bzw. Structure-Markt) ist nicht live geprüft.

Offen:

- Live-Prüfung mit echtem Home Hub und Owner-Abnahme.
- Liegt ein Home Hub als NPC-Station in derselben Region wie der Main Hub, wird
  das Regionsbuch ein zweites Mal geladen.
- P5 (Ansicht).

## 20. Oktober 2026 – P2: Ladestatus des Startablaufs auf dem Dashboard

Ziel: Den Stand des P1-Startablaufs je Bereich mit Zustand und Zeitpunkt auf dem
Dashboard zeigen. Der Eigentümer hatte P2 zunächst übersprungen und es nach P3
ausdrücklich nachbeauftragt.

Änderung:

- **Startablauf beobachtbar:** `StartupDataLoad` ist jetzt ein
  `ObservableObject` (`phase`, `characterResult`).
- **Status-Projektor:** Der reine `StartupDataStatusProjector`
  (`ContentView.swift`) leitet die Zeilen für Charaktere, Lager & Baupläne,
  Reaktionen, Mondmaterialien und Mineralien ab. Die Quellen sind das
  Sync-Ergebnis, die ESI-Metadaten `assets`/`blueprints` und die
  Analyse-Snapshots samt Fehlerzuständen.
- **Anzeige:** `StartupDataStatusSection` steht in der vorhandenen Karte
  „Automatic data“ über den Zeilen für Verträge und Main-Hub-Markt. Die
  Zeilendarstellung ist als gemeinsame `AutomaticStatusRow` ausgelagert.
- **Texte:** Neue Texte sind deutsch und englisch lokalisiert.

Prüfung: Vier neue Tests decken ab:

- die Zusammenfassung der Zustände,
- Charaktere/Lager je Phase inklusive fehlender Bauplan-Metadaten,
- Analysefehler und Wartezustand,
- die Phasen-Veröffentlichung.

`swift test`: 449 Tests in 28 Suites und 49 Tests in 3 Suites erfolgreich.
Xcode-Debug-Build erfolgreich. Beide `Localizable.strings` sind mit `plutil`
geprüft.

Offen: Visuelle Prüfung in der laufenden App und Owner-Abnahme. Als Nächstes
folgt P4.

## 20. Oktober 2026 – P3: Chancen-Kern je Hub-Rolle

Ziel: Den Main-Hub-Chancen-Kern für Home- und Coalition-Hub nutzbar machen,
ohne das Main-Hub-Verhalten zu ändern. Umfang: nur Kern und Tests, keine UI.
P2 (Ladestatus) hat der Eigentümer übersprungen; es bleibt offen.

Änderung:

- **Hub-Rolle:** `OpportunityHubRole` (main/home/coalition) mit Dateinamen je
  Rolle. Die Main-Hub-Dateien heißen weiter `market/main-hub-*.json`.
- **Analyzer:** `ManufacturingOpportunityAnalyzer.analyze` hat optional
  `hubRole`, `saleHub` und `saleMarket`. Material wird weiter am Main-Hub-Markt
  bewertet, das Produkt am Verkaufsmarkt.
- **Snapshot:** `ManufacturingOpportunitySnapshot` hat die optionalen Felder
  `hubRole`/`saleHub`. Bei Main-Hub-Scans bleiben sie leer und werden nicht
  geschrieben.
- **Logistik:** `ManufacturingOpportunitySaleRoute` steuert die Route (Main
  Hin- und Rücktransport, Home ohne Rücktransport, Coalition mit
  eingespeisten Kosten Home → Coalition). Der Main-Pfad ist unverändert; neu
  ist nur `saleHubLogistics`.
- **Speicherpfade:** `RuntimeState` erzeugt sie über
  `opportunityDemandFileURL`/`opportunitySnapshotFileURL`.

Prüfung: Sechs neue Tests decken ab:

- identische Main-Hub-Ergebnisse und Dateischlüssel,
- Home-Verkauf mit Materialkauf am Main Hub,
- Abweisung fehlender oder falscher Verkaufsmärkte,
- die Routen,
- die Dateinamen,
- die Main-Hub-Pfade in der App.

Die bestehenden Main-Hub-Tests sind unverändert grün. `swift test`: 449 Tests
in 28 Suites und 45 Tests in 3 Suites erfolgreich. Xcode-Debug-Build erfolgreich.

Offen:

- P2 (vom Eigentümer übersprungen).
- P4 lädt Home-Hub-Marktdaten und speist sie ein.
- Die Warntexte nennen noch wörtlich „Main Hub“ und werden mit den Ansichten
  P5/P7 angepasst.
- Keine Live- oder Owner-Prüfung.

## 20. Oktober 2026 – P1: Zentraler Startablauf „ESI laden“

Ziel: Beim Programmstart alle Daten automatisch laden (Eigentümerentscheid,
[HUB_CHANCEN_PLAN.md](Documentation/HUB_CHANCEN_PLAN.md)).

Änderung:

- **Startablauf:** `StartupDataLoad` in `RuntimeState.swift` läuft einmal je
  Prozess. Er synchronisiert Charaktere und lädt die Planner-Konfiguration
  parallel. Danach startet er Mond-, Mineral- und Reaktionsanalyse und gibt mit
  `releaseStartupAutomaticScans` die automatischen Main-Hub- und
  Public-Contracts-Scans frei.
- **Sync-Logik:** Die Charakter-Synchronisierung aus dem Dashboard ist in
  `CharacterBatchSynchronizer` (`ContentView.swift`) ausgelagert. Das Dashboard
  übernimmt beim Start dieses Ergebnis und wartet bei Bedarf, bis der Ablauf
  gestartet ist.
- **Main-Hub-Einwilligung:** Die Einwilligung und ihre Versionsprüfung sind
  entfernt. Die Pause im Dashboard gilt nur noch für den laufenden App-Prozess.
- **Vertragsimport:** Der Automatikschalter des Vertragsindex wird beim Start
  wieder eingeschaltet.
- **Doppelte Planung:** Eine zusätzliche Prüfung nach dem Laden des Zustands
  verhindert, dass der Vertragsimport doppelt eingeplant wird.

Begründung in [DECISIONS.md](Documentation/Consolidation/DECISIONS.md); PRODUCT.md
und ARCHITECTURE.md sind angepasst.

Prüfung: Fünf neue Tests in `RuntimeFeatureStateTests` decken ab:

- Reihenfolge (Analysen und Scans erst nach Charakteren und Konfiguration),
- einmaliger Lauf mit Mitnutzung des Ergebnisses,
- frühes Warten des Dashboards,
- Abbruch ohne Folgeschritte,
- keine Scans ohne Hintergrunddienste.

`swift test`: 444 Tests in 28 Suites und 44 Tests in 3 Suites erfolgreich.
Xcode-Debug-Build (`CODE_SIGNING_ALLOWED=NO`) erfolgreich. `EVEStaticDataKit`
wurde nicht berührt und nicht separat getestet.

Offen: Live-Prüfung des Startablaufs mit echten Charakteren und die
Owner-Abnahme stehen aus. Als Nächstes folgt P2 (Ladestatus auf dem Dashboard).

## 20. Oktober 2026 – P0: Abgleichstabelle gegen den Code geprüft

Ziel: Die dokumentbasierte Abgleichstabelle in
[HUB_CHANCEN_PLAN.md](Documentation/HUB_CHANCEN_PLAN.md) gegen den Quellcode
prüfen (nur lesen).

Ergebnis: Alle 19 Statuswerte sind bestätigt, keiner musste korrigiert werden.
Belege:

- **Startpfad** (`EVENexusSimpleApp.swift`, `RuntimeState.init`): lädt SDE,
  Dienststatus, Bedarfsledger, Chancen-Snapshot, LP-Katalog und den
  Vertragsspeicher.
- **Main-Hub-Automatik und Vertragsautomatik**: beide nur nach Opt-in.
- **Charakter-Sync, Reaktionen, Mond und Mineral**: werden erst über `.task` des
  Dashboards angestoßen.
- **Chancen**: Speicherung fest in `market/main-hub-*.json`, ohne öffentliche
  Verträge.
- **Planner**: neun `SaleScenarioResult`-Felder, aber kein gespeicherter
  Zielmarkt und kein Allianzmarkt.
- **Kaufort-Empfehlung**: `MaterialPurchaseRecommendationProjector` ist nicht an
  den Planner angebunden.

Zusätzlich gefunden: Das Dashboard hat bereits eine Karte „Automatic data“; das
ist im Plan als Hinweis für P2 vermerkt.

Prüfung: Code nur gelesen, keine Codeänderung, deshalb kein Build und kein
Testlauf. PRODUCT.md ist unverändert.

Offen: P1–P13.

## 20. Oktober 2026 – Abgleich Ablaufdiagramm, Plan Home-/Coalition-Hub-Chancen

Ziel: Das Ablaufdiagramm des Eigentümers (Programmstart → ESI laden → Analysen,
Dashboard, Verträge und Hub-Chancen → Planer → Produktionsentscheidung) mit dem
aktuellen Stand abgleichen. Fehlende Punkte als Checkliste und in kleinen Prompts
planen.

Änderung: Neu ist [Documentation/HUB_CHANCEN_PLAN.md](Documentation/HUB_CHANCEN_PLAN.md)
mit Abgleichstabelle, Checkliste, Abhängigkeitsplan und den Prompts P0–P13. Jeder
Prompt nennt seinen Nachfolger. ROADMAP.md verweist unter „Geplant“ darauf.
Eigentümerentscheide: Allianzmarkt ist ein manuelles Verkaufsziel; beim
Programmstart wird alles automatisch geladen (ersetzt die bisherigen Opt-ins; die
Regeländerung wird erst in P1 umgesetzt und begründet).

Ergebnis und Prüfung: Es ist nur Dokumentation entstanden; Code und Verhalten
sind unverändert, ein Build war nicht nötig. Die Bewertung beruht auf PRODUCT.md
und ARCHITECTURE.md; eine Codeprüfung fand in diesem Schritt nicht statt.

Offen: P0 (Codeverifikation der Abgleichstabelle) bis P13.

## 29. September 2026 – Projektweite Modellvorgabe

Ziel: Alle neuen Codex-Aufgaben des Projekts standardmäßig mit GPT-5.6 Sol und
Reasoning-Stufe High ausführen, sofern der Benutzer für eine Aufgabe nichts
anderes vorgibt.

Änderung: Die lokale Projektkonfiguration setzt `model = "gpt-5.6-sol"` und
`model_reasoning_effort = "high"`. AGENTS, MODEL_POLICY und die aktiven
Steuerdokumente nennen denselben Standard. Ein automatischer Modellwechsel ist
ausgeschlossen. Wenn der Standard nicht ausreicht, muss der Agent vor einem
Wechsel zwei oder drei konkrete Optionen mit exaktem Modell, Reasoning-Stufe,
Empfehlung und kurzem Trade-off zur Auswahl vorlegen.

Ergebnis und Prüfung: Die TOML-Konfiguration ist syntaktisch geprüft; die aktiven
Steuerdateien enthalten keine widersprechende Standardmodell-Angabe. Bereits
laufende Sitzungen können ihre Startkonfiguration beibehalten; globale
App-Einstellungen wurden nicht verändert.

## 25. September 2026 – Projektkonsolidierung

Ein aktiver Projektstamm; Astra Medium als Standardmodell. Vollständiger lokaler
Arbeitsstand einschließlich Fensterkorrektur übernommen. Zwei Entwicklungslinien
und das Backup über Hashinventare verglichen, Altstände recoverbar erhalten.
Produktname und Dokumentationskanon vereinheitlicht; Fachlogik und Datenidentitäten
unverändert. Abweichende Legacy-Funktionen nicht heimlich integriert oder gelöscht.
Konkrete Auswahl, Prüfungen und Grenzen: [Konsolidierungsbericht](Documentation/Consolidation/VALIDATION.md).
Alle folgenden Einträge sind historische Nachweise mit ihren damaligen Namen.

Dieses Tagebuch dokumentiert die Entwicklungsschritte in zeitlicher Reihenfolge.
Es ist keine zweite Spezifikation: Das aktuell gültige Verhalten steht in
[`dokumentation.md`](dokumentation.md), die detaillierten Prüfbelege in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md).

Die Einträge bis zum 1. August stützen sich auf die Git-Historie. Die danach
aufgeführten Schritte sind aus den datierten Architektur-, Handoff- und
Acceptance-Nachweisen des aktuellen lokalen Arbeitsstands rekonstruiert. Da
dieser Arbeitsstand noch nicht vollständig eingecheckt ist, beschreibt die
Reihenfolge Themenblöcke und nicht zwingend einzelne Commits.

## 29. August 2026 – Mineralien-Kaufanalyse

Ziel: Neben der bestehenden Mond-Kaufanalyse einen gleichartigen, rein
lesenden Preis- und Mengenvergleich für alle veröffentlichten Mitglieder der
aktiven SDE-Gruppe `Mineral` bereitstellen. Main Hub, Home Hub, Coalition Hub
und ausdrücklich gewählte Vergleichsmärkte sollen den niedrigsten Sell-Preis,
die exakte 110-%-Grenze, die bis einschließlich dieser Grenze verfügbare Menge
und die drei günstigsten frischen Märkte zeigen.

Sicherung: Der umfangreich veränderte Arbeitsstand wurde vor dem ersten
Quellcodeeingriff als
`/private/tmp/EVE-NEXUS-SIMPLE-before-mineral-analysis-20260829-193854.tar.gz`
archiviert. `gzip -t` bestand, zentrale Quell-, Projekt- und
Dokumentationspfade waren im Archiv vorhanden. Die SHA-256-Prüfsumme lautet
`10773fc80f4ae8909c7923f94d84475e266aa1ba9065436aef9b1cf720ed6701`.
Vorhandene unabhängige Änderungen im Checkout blieben unangetastet.

Entwicklung:

- die mondspezifischen Katalog-, Preisband-, Ranking- und Snapshot-Verträge zu
  gemeinsam verwendbaren `MaterialPurchaseAnalysis`-Typen verallgemeinert;
  bestehende Moon-Namen bleiben als kompatible Typaliase erhalten;
- den aktiven SQLite-SDE-Katalog um die veröffentlichte Gruppe `Mineral`
  erweitert. Eine fehlende Gruppe bleibt ein ausdrücklicher Fehler; es gibt
  keine fest codierte Ersatzliste und keine erfundenen Namen oder Werte;
- den vorhandenen NPC-/Structure-Marktpfad in einen gemeinsamen Materiallader
  überführt. Mond und Mineralien behalten getrennte Snapshots, Fehler,
  Aktualisierungszustände und Cache-Identitäten; Main, Home, Coalition und
  Vergleichsmärkte stammen weiter aus dem zentralen gespeicherten Rollenmodell;
- eine gemeinsame SwiftUI-Analyseoberfläche für beide Katalogarten gebaut und
  die Mineralienseite direkt neben der Mondseite in die Navigation gesetzt.
  Gegenstands- und Ortsnamen verwenden die gemeinsamen kopierbaren
  EVE-Komponenten. Preisbasierte Hubsortierung, Freshness-Ranking, Diagnosen und
  der vollständige PNG-Export bleiben gemeinsam; Mineralexporte beginnen mit
  `Mineralien-Kaufanalyse_`;
- deutsche und englische Texte, Hauptdokumentation, Architektur und
  Acceptance-Nachweis auf den gemeinsamen Vertrag aktualisiert. Die Anzeige
  bleibt sitzungsgebunden; eine Datenbank- oder SwiftData-Migration war nicht
  erforderlich.

Prüfung: Die fokussierten Katalog-, Markt- und Runtime/App-Suiten bestehen. Der
vollständige isolierte SwiftPM-Lauf baut Core und App und besteht mit 406
Swift-Testing-Tests in 26 Suiten plus 11 App-XCTest-Fällen, insgesamt 417
Tests. Der unsignierte native Xcode-Debug-Build aus einer temporären Kopie des
aktuellen Arbeitsstands endet mit `BUILD SUCCEEDED`; die native Xcode-Testaktion
besteht mit 384 Tests in 23 Suiten und `TEST SUCCEEDED`. Der ausdrücklich
optionale Real-SDE-Test bleibt mangels vorbereitetem Paket in beiden Läufen
wie vorgesehen übersprungen. Striktes Swift-Formatting, beide
Lokalisierungskataloge, Dublettenprüfung und `git diff --check` bestehen.

Sichtprüfung: Die befüllte deutsche Debug-App wurde bei 1280 × 768 im
Dunkelmodus geöffnet. Sie zeigte 15 Mineralien aus dem aktiven SDE und vier
frische konfigurierte Märkte: Jita als Main Hub, UALX als Home-Structure,
C-J6MT als Coalition-Structure und Amarr als Vergleichsmarkt. Preis,
110-%-Grenze, aufsummierte Menge, Rang und ausdrückliche
„keine Sell Orders“-Zustände waren sichtbar; die vier Hubspalten passten in
das Standardfenster. Sortier- und Copy-Steuerungen waren im Accessibility-Baum
vorhanden. Die Prüfung deckte dort zugleich auf, dass eine Markt-Zelle zunächst
nur Mineral und Hub benannte. Ihr gemeinsames Accessibility-Label enthält nach
der Korrektur zusätzlich Preis, Grenze, Menge, Rang und Frische-/Fehlerzustand;
dieser letzte reine Accessibility-Schritt wurde erneut gebaut und automatisiert
getestet.

Offen: Mindestfenster, horizontaler Tabellenlauf, Hellmodus, tatsächliche
Tastatur-/VoiceOver-Bedienung, Kopierfeedback und ein gespeicherter,
vollständiger ungeclippter Mineral-PNG-Export bleiben Sicht-/Owner-Abnahme.
Ebenso offen ist der unabhängige Vergleich mindestens eines Minerals je
eingerichtetem Hub mit dem aktuellen EVE-Orderbuch; der erfolgreiche Live-Abruf
in der App und die automatisierten Fixtures sind dafür kein Ersatz.

## 16. August 2026 – Planner-Start, Vertragsreferenzen und Dropdown-Flächen

Ziel: Einen einzelnen Klick auf **Berechnen** sofort sichtbar bestätigen,
unbemerkte Mehrfachstarts verhindern, während einer laufenden
Public-Contracts-Aktualisierung bereits belegte Vertragsangebote wieder
nutzbar machen und aufklappbare Flächen vollständig anklickbar machen.

Diagnose: Der Planner setzte `isWorking` erst in der abschließenden
Kalkulation. Davor liefen bereits Eingabevorbereitung, Marktgrundlagen und bis
zu zwei Produktionsbaum-/BPO-/BPC-Auflösungen. Der Button blieb in dieser Zeit
aktiv; ein weiterer Klick stornierte die laufende Task und begann wieder von
vorn. Die Abschlussberechnung bereitete außerdem denselben Eingabegraphen noch
einmal vor. Bei Vertragsszenarien machte bereits ein einziger noch ausstehender
Vertragsdetailabruf den gesamten universumsweiten Index unvollständig und
verwarf dadurch auch vorhandene, positive, passende Einzelangebote. Die
adaptiven Verkaufskarten übernahmen die Höhe der größten Karte einer Gridzeile,
aber nur ihre kurze Kopfzeile war anklickbar. Drei verbliebene native
`DisclosureGroup`-Kontrollen verwendeten ebenfalls nicht die gemeinsame
vollbreite Steuerung.

Entwicklung:

- den vollständigen Quell-, Projekt-, Paket- und Git-Arbeitsstand vor der
  Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-source-backup-2026-08-16_18-24-15_CEST`
  gesichert. HEAD und SHA-256 des vollständigen Git-Status stimmen mit dem
  Checkout überein; beide enthalten 4.759 Dateien außerhalb der bewusst
  ausgelassenen, neu erzeugbaren `.build`-/DerivedData-Verzeichnisse;
- den lokalen Planner-Phasenstatus vor jede teure Arbeit gesetzt. Vorbereitung,
  BPO-/BPC-Auflösung, Effizienzanwendung, Kalkulation und Speicherung werden
  getrennt angezeigt. Weitere Starts sind bis zum Ende blockiert; Abbrechen
  bleibt ausdrücklich verfügbar;
- die komplette Planner-Vorbereitung als interaktive Sitzung gekennzeichnet,
  damit automatische Main-Hub- und Public-Contracts-Aktualisierungen nicht mit
  der Berechnung konkurrieren. Die abschließende Kalkulation verwendet den
  bereits passend vorbereiteten Eingabegraphen erneut;
- vorhandene passende öffentliche Item-Exchange-Einzelangebote bei
  unvollständigem Index als ausdrücklich vorläufige Referenz zugelassen. Diese
  Referenz behauptet kein universumsweites Minimum. Ohne beobachtetes Angebot
  bleibt der Vertragserlös unverfügbar; 0 ISK wird weiterhin nicht erfunden;
- die Vorläufigkeit in kompakter und aufgeklappter Verkaufskarte sichtbar
  gemacht. Marktsteuer und Brokergebühr bleiben beim Vertragshandel 0; eine
  unbekannte persönliche Vertragsgebühr bleibt weiterhin ein eigener
  ausstehender Wert;
- die gemeinsame Offenlegungssteuerung bis an die volle angebotene Breite und
  bei geschlossenen Verkaufskarten an die gesamte adaptive Kartenhöhe
  ausgedehnt. Die verbliebenen nativen Offenlegungen in Market-Chancen und
  Warehouse wurden migriert; sichtbare EVE-Namens-Kopieraktionen bleiben
  getrennt;
- deutsche und englische Texte, `dokumentation.md` sowie die Acceptance-Matrix
  an das aktuelle Verhalten angepasst.

Prüfung: 35 fokussierte Industry-Tests einschließlich des neuen
Teilindex-Vertragsfalls, 11 Runtime-Status-Tests und 6
Planner-Query-Effizienztests bestehen. Der vollständige isolierte SwiftPM-Lauf
baut Core und App und besteht mit 402 Swift-Testing-Tests in 26 Suiten plus 11
App-XCTest-Fällen, insgesamt 413 Tests; ein opt-in Test mit einem extern
vorbereiteten realen SDE-Paket bleibt erwartungsgemäß übersprungen. Das
verschachtelte EVEStaticDataKit besteht mit 8 Tests, davon derselbe opt-in
Real-SDE-Test übersprungen. Der unsignierte native Xcode-Debug-Build ist
erfolgreich. Striktes Swift-Formatting, beide Lokalisierungskataloge,
Dublettenprüfung, vollständige Entfernung nativer `DisclosureGroup`-Aufrufe im
App-Target und `git diff --check` bestehen.

Offen: Der betroffene große Plan muss im laufenden aktuellen Build einmal mit
einem einzelnen Klick, Abbruch, Tastatur und VoiceOver geprüft werden. Während
einer echten laufenden Public-Contracts-Aktualisierung ist ein angezeigtes
vorläufiges Angebot mit dem Ingame-Vertrag und nach Abschluss erneut zu
vergleichen. Layout, wahrgenommene Dauer, CPU/RSS und Owner-Abnahme sind durch
die automatischen Prüfungen nicht belegt.

## 16. August 2026 – Main-Hub-Übergabe ersetzt oder erweitert den Planner

Ziel: Eine neue Main-Hub-Chance auch dann berechenbar machen, wenn der Planner
einen alten, möglicherweise ungültigen Entwurf, ein berechnetes Ergebnis oder
alte BPO-/BPC-Auswahlen wiederhergestellt hat.

Diagnose: Die Übergabe hängte ihre gültige neue Eingabezeile bisher immer an
den vorhandenen Planner-Text an. Eine unvollständige alte Zeile blieb dadurch
ein Eingabefehler für den gesamten Entwurf und deaktivierte **Berechnen**. Für
ein vorhandenes Ergebnis existierte außerdem keine ausdrückliche
Ersetzen-Entscheidung.

Entwicklung:

- den gemischten Checkout vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-before-planner-handoff-replacement-2026-08-16-145145.tar.gz`
  gesichert, gzip-geprüft und mit SHA-256
  `67654ec8dc9f14d613b8fd5621770d341b048cad3d468dc8804b3a9287f00b48`
  bestätigt;
- bei vorhandenem Entwurf oder Ergebnis eine sichtbare Vorschau mit drei
  ausdrücklichen Aktionen ergänzt: **Aktuelle Berechnung ersetzen**, **Zum
  aktuellen Entwurf hinzufügen** und **Aktuelle Berechnung behalten**;
- beim Ersetzen alte sitzungsgebundene Produktionsbaum-, BPO-/BPC-Quellen-,
  ME-/TE- und Make-or-Buy-Auswahlen entfernt. Der neue Entwurf enthält genau die
  übergebene Zeile und ist wieder parsebar;
- den bisher aktiven Plan bei dieser Ersatzberechnung vorläufig aus dem
  Reservierungseingang ausgeschlossen. Er wird in der lokalen Speicherung erst
  nach einer erfolgreichen neuen Berechnung deaktiviert; ein fehlgeschlagener
  Versuch löscht weder seine gespeicherte Historie noch Ingame-Daten;
- den allgemeinen Planner-Produktpicker unverändert gelassen: Er fügt weiterhin
  bewusst eine weitere Zeile an und ersetzt keinen Entwurf;
- deutsche und englische Texte sowie Handoff- und Abnahmedokumentation
  aktualisiert.

Prüfung: Der fokussierte App-Test belegt die Ersetzen-Entscheidung aus einem
ungültigen wiederhergestellten Entwurf, die danach gültige einzelne neue Zeile,
die konfliktfreie Direktübernahme in einen leeren Planner und das weiterhin
verfügbare Anhängen. Der vollständige isolierte SwiftPM-Lauf baut Core und App
und besteht mit 399 Swift-Testing-Tests in 26 Suiten plus elf
App-XCTest-Fällen, insgesamt 410 Tests. Striktes Swift-Formatting und beide
Lokalisierungskataloge bestehen. Ein neuer nativer Xcode-Nachweis wurde nicht
als bestanden ausgeführt.

Offen: Die Auswahlkarte und anschließend **Berechnen** müssen mit dem
betroffenen befüllten Planner in der laufenden App visuell, per Tastatur und
VoiceOver sowie ausdrücklich durch den Owner abgenommen werden.

## 16. August 2026 – Planner-Absturz bei wiederholtem Blueprint-Typ

Ziel: Den reproduzierten Planner-Absturz nach einer Berechnung mit leerer
erster Eingabezeile beseitigen, ohne rekursive Blueprint-Bedarfe oder konkrete
BPC-Jobs zusammenzuziehen.

Diagnose: Der Xcode-Stack und die Konsole endeten übereinstimmend mit
`Swift/NativeDictionary.swift:792: Fatal error: Duplicate values for key:
'46178'` in `BlueprintSupplyPlanner.plans`. Der Produktionsbaum darf dieselbe
bereits typweit aggregierte Blueprint-Bewertung an mehreren rekursiven Knoten
tragen. Die Versorgungsschicht konstruierte daraus fälschlich ein Wörterbuch,
das eindeutige Blueprint-Type-IDs voraussetzte. Meldungen zu
`DetachedSignatures`, WAL-Checkpoint, fehlendem SF Symbol, TCP und ViewBridge
waren nicht die Absturzursache.

Entwicklung:

- den gemischten Checkout vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-before-duplicate-blueprint-crash-fix-2026-08-16-143446.tar.gz`
  gesichert, gzip-geprüft und mit SHA-256
  `339a140febf5c6559bfbab9339bd77873b7f08e83c8dbeb8188aaed03bf2f6a1`
  bestätigt;
- Blueprint-Bewertungen im Supply Planner nach Blueprint-Type-ID gruppiert.
  Wiederholte Projektionen verwenden dadurch einen gemeinsamen typweiten
  Quellnachweis, während benötigte Runs weiterhin über alle produzierten
  Knoten summiert und konkrete BPCs weiterhin als getrennte Jobs reserviert
  werden;
- auch eine versehentlich doppelte bevorzugte Quellenreferenz wird stabil nur
  einmal eingeordnet und kann keinen gleichartigen Dictionary-Absturz mehr
  auslösen;
- den vorhandenen BPC-Jobtest um eine absichtlich doppelte Bewertung erweitert
  und einen eigenen Parserfall für eine leere erste Eingabezeile ergänzt.

Prüfung: Beide fokussierten Regressionen bestehen. Der vollständige isolierte
SwiftPM-Lauf baut Core und App und besteht mit 399 Swift-Testing-Tests in 26
Suiten plus zehn App-XCTest-Fällen, insgesamt 409 Tests. Striktes Formatting
der geänderten Swift-Dateien besteht. Der erste fokussierte Versuch erreichte
wegen `sandbox_apply: Operation not permitted` nicht die Kompilierung; der
identische erlaubte Lauf mit isolierten Cache-/Buildpfaden bestand. Ein nativer
Xcode-Lauf wurde für diesen kleinen Core-Fix nicht erneut als Erfolg belegt.

Offen: Die konkrete befüllte Planner-Eingabe mit leerer erster Zeile und dem
betroffenen Produktionsbaum muss nach einem App-Neustart noch vom Owner
ausgeführt werden. Visuelle, Tastatur- und VoiceOver-Abnahme bleiben getrennt.

## 16. August 2026 – Stabile Chancenzeilen, T1-Standard und direkter Planner-Handoff

Ziel: Beim Ändern von Runs, ME oder TE die bearbeitete Main-Hub-Chancenzeile an
ihrer Position halten, Tech-I-Module mit der gewünschten Forschungsannahme
anzeigen und den wirkungslosen **Bauen**-Klick wieder direkt an den Planner
übergeben.

Entwicklung:

- den vollständigen gemischten Checkout vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-before-main-hub-edit-fixes-2026-08-16-140127.tar.gz`
  gesichert, gzip-geprüft und mit SHA-256
  `394e122dff413a310b05d4a033e2777d920c7e34ee029db71b0d1f747f98cfc8`
  bestätigt;
- die nach jeder lokalen Runs-/ME-/TE-Projektion ausgeführte automatische
  Neusortierung entfernt. Die bereits dargestellte typisierte Sortierung bleibt
  während der Eingabe eingefroren; erst ein bewusster Spaltenkopfklick sortiert
  erneut anhand der dann sichtbaren Werte;
- einen zentral getesteten Chancenstandard ergänzt: Tech-I-Module verwenden
  ME 10/TE 20, ein im gespeicherten öffentlichen LP-Katalog belegter
  Blueprinttyp hat als Loyalty-Store-BPC mit ME 0/TE 0 Vorrang, Tech-II bleibt
  bei der Planungsannahme ME 3/TE 2. Andere Produkte behalten ihren belegten
  Ausgangswert;
- den veralteten Build-Button-Vertrag entfernt, der auf einen zuvor aus der
  kompakten Chancenansicht entfernten Produktionsbaum wartete. **Bauen** erzeugt
  nun mit einem Klick die normale Planner-Eingabe aus sichtbarer Ausgabemenge,
  Runs, ME und TE und wechselt zum Planner. Da in der kompakten Tabelle keine
  konkrete Blueprintquelle gewählt wird, wird kein fiktiver Supply-Plan
  erzeugt; die Quellenwahl bleibt beim Planner;
- deutsche und englische Hilfetexte sowie aktuelles Verhalten, Handoff-Vertrag
  und Abnahmematrix berichtigt.

Prüfung: Der erste vollständige Lauf wurde verworfen, weil sich
`MarketBrowserTests.swift` während des Compilierens im gemeinsam genutzten
Arbeitsstand änderte. Der anschließende stabile isolierte SwiftPM-Lauf baute
Core und App und bestand mit 398 Swift-Testing-Tests in 26 Suiten plus zehn
App-XCTest-Fällen, insgesamt 408 Tests. Darin bestehen der neue T1-/LP-Fall und
der direkte Planner-Handoff. Striktes Swift-Formatting, beide
Lokalisierungskataloge und `git diff --check` bestehen. Drei unsigned
Xcode-Debug-Versuche blieben bereits vor der normalen Build-Ausgabe ohne
Diagnose stehen und wurden beendet; sie gelten weder als bestanden noch als
Compilerfehler.

Offen: Sichtprüfung in der befüllten App mit einer sortierten Liste, mehreren
Runs-/ME-/TE-Änderungen, Occult XL, einem Tech-I-Modul und einem
Loyalty-Store-BPC; außerdem nativer Xcode-Nachweis, Tastatur, VoiceOver und
ausdrückliche Owner-Abnahme.

## 16. August 2026 – Konkrete Blueprintversorgung v2

Ziel: Die BPO/BPC-Behandlung in Planner und Market-Chancen gegen die aktuellen
CCP-Regeln korrigieren, ohne den umfangreichen gemischten Arbeitsstand oder
unvollständige ESI-/Contract-Evidenz zu verlieren.

Entwicklung:

- vor den Änderungen den vollständigen Checkout als geprüftes Archiv
  `/private/tmp/EVE-NEXUS-SIMPLE-before-bpo-bpc-implementation-2026-08-16-124032.tar.gz`
  außerhalb des Checkouts gesichert; SHA-256
  `62e822ffc5d7a3a1db43cf64380a3299577d1227e34cca3573338a939b10b881`;
- `BlueprintDemandID`, konkrete Quellenreferenzen, Run-Zuordnungen,
  Fertigungs-/Science-Jobs, Transfers, Reservierungen und
  `BlueprintSupplyPlan` eingeführt; Regelversion auf
  `2026.08-blueprint-supply-v2` angehoben;
- jede eigene oder vertragliche BPC als einzelne Instanz und einzelnen
  Fertigungsjob erhalten. Gleiche und gemischte Qualitäten dürfen gemeinsam
  den Bedarf decken, behalten aber getrennte Materialrundung und Rest-Runs;
- persönliche BPC-Runs aktiver Pläne nach Plan- und Item-ID reserviert. Drafts,
  Handoff und aktive Snapshots speichern konkrete Quellen, Jobs, Transfers und
  Reservierungen; alte Snapshots bleiben optional decodierbar;
- BPO-Verträge und tatsächliche Main-Hub-BPO-Sell-Orders getrennt. Ihr Preis
  bleibt Kapitalbedarf, während nur die gewählte Chargenumlage kostenwirksam
  ist; normale Marktorders werden nie als BPC interpretiert;
- Quellen außerhalb der Produktionsanlage erzeugen einen expliziten Transfer;
  unbekannte Transferendpunkte blockieren;
- Market-Chancen rechnen nach konkreter Quellenwahl den vollständigen Baum neu
  und übergeben denselben Supply-Plan an den Planner;
- die pauschale Tech-II-ME-4-Grenze entfernt. Faktische Provenienzwerte bleiben
  erhalten; manuelle Annahmen verwenden ME 0...10/TE 0...20;
- SDE-Katalogadapter v4 um Science-Skills und Decryptor-Dogmawerte ergänzt.
  Der gemeinsame Science-Kern bildet Kopien × Runs je Kopie, BPO-Forschung,
  drei Erfindungs-Skills, Ergebniswahl, Verbrauch je Versuch, Decryptorwerte,
  Erwartungskosten und den kleinsten 95%-Binomialplan ab. Ein Process Decryptor
  erreicht aus ME 2 den gültigen Wert ME 5; Tech-III-Reverse-Engineering wird
  abgewiesen;
- Copying, Forschung und Erfindung im Planner weiterhin sichtbar, aber bis zur
  vollständigen Anlagen-/Kosten- und Persistenzoberfläche gesperrt. Die
  ausdrücklich manuelle externe BPC bleibt der Übergang, damit keine
  unvollständige Science-Rechnung als faktisch erscheint;
- Besitzer- und Ortsnamen im Blueprintbereich auf die gemeinsame kopierbare
  EVE-Namenskomponente vereinheitlicht.

Prüfung: Die fokussierten Blueprint-, Planner-, Market- und SQLite-SDE-Suiten
bestehen mit 109 Tests; der zusätzliche gezielte Transferfall besteht. Der
vollständige isolierte SwiftPM-Lauf baut Core und App und besteht mit 397
Swift-Testing-Tests in 26 Suiten plus zehn App-XCTest-Fällen, insgesamt 407
Tests. Das verschachtelte EVEStaticDataKit entdeckt acht Tests und besteht mit
den sieben deterministischen Fällen; der ausdrücklich optionale Real-SDE-Test
wird ohne bereitgestellten Paketpfad erwartungsgemäß übersprungen. Der unsigned
native Xcode-Debug-Build endet mit `BUILD SUCCEEDED`. Striktes Swift-Formatting,
beide Lokalisierungskataloge und die Diff-Whitespace-Prüfung bestehen.

Offen: Ein befüllter Livevergleich mit EVE für zwei gleiche und gemischte BPCs,
Contract-BPC, Markt-/Contract-BPO, Copying und T2-Erfindung; Science-UI-
Aktivierung, Corporation-Reservierung, visuelle/Tastatur-/VoiceOver- und
Owner-Abnahme.

## 16. August 2026 – ME/TE und gruppierte eigene Baupläne im Planner

Ziel: Die BPO/BPC-Bedienung des etablierten Planners einklappbar und nach
fachlichen Gruppen steuerbar machen, konkrete eigene Bauplanqualitäten am
Produktionsort verwenden und die widersprüchlichen Prospect-Werte zwischen
Main-Hub-Chancen und Planner nachvollziehbar korrigieren.

Entwicklung:

- den vollständigen gemischten Checkout vor dieser Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-Backup-2026-08-16_11-40-27_CEST.tar.gz`
  gesichert; das gzip-geprüfte Archiv enthält 12.544 Einträge, ist
  347.147.255 Byte groß und hat SHA-256
  `fbbb2f53a501e82ea605c31cfdf052798aa4c2c0f2e448bedfc71685af0e98c7`;
- die gesamte BPO/BPC-Fläche sowie ihre Reaktions-, Komponenten- und übrigen
  SDE-Kategoriegruppen einklappbar gemacht. Eine Gruppenquelle wird nur auf
  kompatible Bauschritte angewendet und weist unveränderte Schritte sichtbar
  aus; jede Zeile bleibt einzeln einstellbar;
- eigene BPOs und BPCs am exakten Produktionsort nach BPO/BPC, ME und TE
  gruppiert. Eine BPC-Qualität muss die benötigten Runs allein beziehungsweise
  gemeinsam mit weiteren BPCs gleicher Qualität abdecken; verschiedene
  Qualitäten werden nicht zu einem erfundenen gemeinsamen Wert vermischt.
  Besitzer, Quellenstatus, Anzahl und Runs bleiben sichtbar. Die gewählte
  Qualität übernimmt ME/TE schreibgeschützt in Vorprüfung und Endrechnung;
- für manuelle, Copy-, Invention- und sonstige Quellen ME/TE je Zeile ergänzt,
  das SDE-Techlevel durch den Produktionsgraphen geführt und Tech-II-ME auf 0
  bis 4 begrenzt. Reaktionen bleiben als nicht erforschbare Formeln ohne ME/TE;
- Main-Hub-Chancen um sortierbare Runs-, ME- und TE-Spalten ergänzt. Tech II
  startet als editierbare Planungsannahme mit 3/2. Ein neuer Scan speichert die
  SDE-Grundmengen und Anlagenmultiplikatoren für exakte EVE-Rundung; ältere
  Scans warnen bei einer ME-Änderung ausdrücklich vor der Näherung;
- **Bauen** übergibt Produkt, Runs, tatsächliche Ausgabemenge, ME und TE an den
  Planner. Der Hinweis erklärt, dass ein direkter gespeicherter Chancen-Scan
  und ein rekursiver Planner nur mit gleicher Charge, Quelle, Blueprintkosten,
  Markttiefe und Route unmittelbar vergleichbar sind;
- den falschen Nulltransport korrigiert: Ein mit Jita übereinstimmender
  Handelskontext darf den ausdrücklich abweichenden Produktionsort UALX-3
  nicht mehr als Main-Hub-Produktion behandeln. Beim anschließenden
  Regressionstest wurde zusätzlich eine Gleitkomma-Aufrundung beseitigt, die
  bei unveränderter TE aus exakt fünf Sekunden sechs machen konnte;
- deutsche und englische UI-Texte sowie Architektur-, Handoff-, aktuelle
  Funktions- und Abnahmedokumentation fortgeschrieben.

Diagnose der gelieferten Prospect-Bilder: Der gespeicherte Chancenwert nutzte
einen Run mit ME/TE 0/0 und ergab +3.949.795 ISK. Der aktive Planner nutzte zehn
Runs mit 3/2 und ergab -18.014.120 ISK einschließlich rekursiver
Zwischenprodukt-/Quellenbehandlung und Transport. Zusätzlich entfernte der
oben korrigierte Ortsvergleich im Chancenwert fälschlich den Transport. Die
beiden alten Screenshots waren daher weder dieselbe Charge noch dieselbe
Rechenbasis; die Übergabe hält diese Annahmen nun zusammen und benennt die
verbleibende Vergleichsgrenze.

Prüfung: Der vollständige isolierte SwiftPM-Lauf bestand 391
Swift-Testing-Tests in 26 Suites sowie zehn App-XCTest-Fälle, insgesamt 401
Tests. Der native unsignierte Xcode-Debug-Build endete mit `BUILD SUCCEEDED`;
die native Xcode-Testaktion bestand 370 Tests in 23 Suites mit
`TEST SUCCEEDED`. Der ausdrücklich opt-in-abhängige Real-SDE-Test wurde
planmäßig übersprungen. Striktes Swift-Format, beide Lokalisierungsdateien,
schlüsselweise Dublettenprüfung und `git diff --check` bestanden.

Offen: Es wurde keine Live-ESI- oder aktuelle Marktanfrage ausgeführt und die
befüllte App nicht gestartet. Der visuelle Vergleich nach einem neuen
Main-Hub-Scan, konkrete Besitzer-/BPC-Runs gegen EVE, Tastatur/VoiceOver,
laufende Planner-Latenz und RSS, Signierung/Notarisierung sowie ausdrückliche
Owner-Abnahme stehen noch aus.

## 16. August 2026 – Market-Chancen an Planner übergeben und BPO/BPC dort bündeln

Ziel: Market Opportunities wieder auf Kandidatensuche und Rangfolge begrenzen,
den früheren Lager-/Main-Hub-/Einkaufslisten-/Kosten-Arbeitsbereich entfernen
und jede konkrete Bauentscheidung einschließlich BPO/BPC-Behandlung im
etablierten Planner ausführen.

Entwicklung:

- den vollständigen gemischten Checkout einschließlich `.git`, nicht
  eingecheckter und unbeobachteter Dateien vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-Backup-2026-08-16_10-49-56_CEST.tar.gz`
  gesichert; das geprüfte Archiv enthält 12.514 Einträge, ist 346.532.805 Byte
  groß und hat SHA-256
  `9dafeec070a1949ddbef93b3c01028aaeb91a57583e9c0e2c04d5f77e52c7cda`;
- den unteren Market-Opportunities-Arbeitsbereich mit Lager, Main-Hub-Tiefe,
  Einkaufsliste, Kostendetails und inline Produktionsbaum aus dem sichtbaren
  Ablauf entfernt; die sortierbare Kandidatenliste nutzt den frei gewordenen
  Platz;
- **Bauen** übergibt Produkt, tatsächliche Ausgabemenge sowie ME/TE an den
  etablierten Planner und hängt dafür eine normale, erneut parsebare
  Planner-Eingabezeile an;
- im Planner eine eigene BPO/BPC-Fläche ergänzt. Sie übernimmt exakte
  Produktionsorte, Besitzer, Runs, Frische-/Teilevidenz, andere Standorte,
  eigene BPOs/BPCs, Copy/Invention/LP-Quellen und eindeutig zurechenbare
  Main-Hub-BPC-Verträge aus dem bisherigen Produktionsbaumvertrag;
- BPC-Vertragspreise werden vollständig zugerechnet, während eigene oder
  gekaufte BPOs weiterhin eine ausdrückliche Umlage verlangen. Eine manuelle
  BPO/BPC-Angabe der obersten Planner-Zeile bleibt maßgeblich; automatische
  Kosten einer schließlich gekauften statt gebauten Zwischenstufe werden nicht
  belastet. Fehlende oder unvollständige Blueprintkosten bleiben unverfügbar
  und werden nicht als null erfunden;
- deutsche und englische Oberflächentexte, Handoff-Vertrag, aktuelle
  Dokumentation und Abnahmematrix an den neuen alleinigen Planner-Ablauf
  angepasst.

Ergebnis: Market Opportunities analysiert und sortiert Chancen; die konkrete
Produktion wird ohne paralleles Untermenü im Planner fortgesetzt. Der Planner
zeigt und bewertet dort die für jeden tatsächlich gebauten Knoten belegbare
BPO/BPC-Quelle.

Prüfung: Die fokussierte Industry-Planner-Suite bestand 31 Tests. Die
vollständige isolierte SwiftPM-Aktion bestand 389 Swift-Testing-Tests in 26
Suites sowie zehn XCTest-Fälle, 399 Tests insgesamt. Der native, unsignierte
Xcode-Debug-Build endete mit `BUILD SUCCEEDED`; die native Xcode-Testaktion
bestand 368 Tests in 23 Suites mit `TEST SUCCEEDED`, während der ausdrücklich
opt-in-abhängige Real-SDE-Test planmäßig übersprungen wurde. Striktes
Swift-Format, beide Lokalisierungsdateien, schlüsselweise Dublettenprüfung und
`git diff --check` bestanden.

Offen: Keine Live-ESI- oder aktuelle Marktanfrage wurde ausgeführt. Visuelle
Prüfung im befüllten deutschen und englischen App-Fenster, Tastatur/VoiceOver,
laufende Planner-Latenz und RSS, Signierung/Notarisierung sowie ausdrückliche
Owner-Abnahme stehen noch aus.

## 16. August 2026 – Vertragsgebühr aus persönlicher ESI-Historie nachweisen

Ziel: Die öffentliche Vertragsgebühr ohne erfundene historische Formel aus
eigenen abgeschlossenen Verträgen ableiten und für den Planner kontrolliert
nutzbar machen.

Entwicklung:

- den vollständigen gemischten Checkout einschließlich `.git`, nicht
  eingecheckter und unbeobachteter Dateien vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-backup-2026-08-16T09-42-59.tar.gz` gesichert;
  das Archiv wurde erfolgreich gelesen, Größe 330 MB, SHA-256
  `7fc8b72dbfcbf0e8f28541813caaa98ae603a6df0a46abf1b742b0bb9d026e9c`;
- persönliche öffentliche Item-Exchange-Verträge und Wallet-Journal mit den
  beiden erforderlichen ESI-Scopes synchronisiert und strikt über
  `contract_id`, Händler und exakten Ort verbunden;
- nur Brokergebühr und Vertragsverkaufssteuer als nicht erstattbare Kosten
  zusammengeführt; Kaution und Rückzahlung bleiben getrennt, untrennbare
  Sammelbuchungen ausdrücklich unvollständig;
- den neuesten vollständigen Nachweis samt Quelle im Marktprofil gespeichert,
  ohne ihn automatisch zu aktivieren. Erst die sichtbare Bestätigung übernimmt
  den beobachteten Satz; Händler- oder Ortswechsel löscht den gebundenen
  Nachweis;
- manuelle Eingabe als Fallback beibehalten und fehlende, verbotene,
  unvollständige oder nicht passende ESI-Daten weiterhin nicht als null
  behandelt; deutsche und englische Oberflächentexte sowie die aktuelle
  Dokumentation ergänzt.

Ergebnis: Der Planner kann eine nachweislich beobachtete persönliche
Vertragsgebühr verwenden, ohne sie als aktuelle ESI-Preisvorschau auszugeben.
Ohne ausdrückliche Bestätigung bleibt die vorhandene Planung unverändert.

Prüfung: Die fünf fokussierten Swift-Testing-Tests für Scope-Prüfung,
Journalzuordnung, Kautionsausschluss, untrennbare Buchungen, Persistenz und
Bestätigung bestanden. Die vollständige isolierte SwiftPM-Aktion baute Core und
App und bestand 387 Swift-Testing-Tests in 26 Suites sowie neun XCTest-Fälle.
Der native, unsignierte Xcode-Test bestand 366 Tests in 23 Suites mit
`TEST SUCCEEDED`. Striktes Swift-Format, beide Lokalisierungsdateien und
`git diff --check` bestanden. Es wurden keine persönlichen Live-ESI-Daten
abgerufen.

Offen: Ein Live-Abgleich mit einem echten abgeschlossenen Vertrag, visuelle
Prüfung, Tastatur/VoiceOver und ausdrückliche Owner-Abnahme stehen noch aus.

## 16. August 2026 – Ark-Sprungrouten, Refining-Erklärung und Planner-Offenlegungen korrigiert

Ziel: Die unerwartet nicht verfügbaren Koalitions-Hub-Szenarien eines gebauten
Jump Freighters erklären und korrigieren, die tatsächlich enthaltene
Main-Hub-Eingangslogistik sichtbar einordnen und die langen Refining- und
Historienbereiche kompakt bedienbar machen.

Diagnose und Entwicklung:

- vor der Änderung die betroffenen Planner-, Refining-, UI-, Test- und
  Dokumentationsdateien außerhalb des Checkouts unter
  `/Users/svenstolze/Documents/EVE NEXUS SIMPLE Backups/2026-08-16-Planner-Routen-Refining-vor-Korrektur.tar.gz`
  gesichert;
- den aktiven lokalen Ark-Plan ausschließlich lesend geprüft. Seine
  Main-Hub-zu-Home-Hub-Fracht war nicht verschwunden: 54 Frachtzeilen mit
  225.308,41 m³ werden nach der Erzsubstitution in einem Vertrag für
  203.000.000 ISK befördert und sind in den bekannten Gesamtkosten von
  6.084.445.401,38 ISK enthalten;
- als Ursache der Koalitions-Hub-Sperre das gespeicherte vollständige
  Sprungprofil `UALX-3 → B9E-H6 → MN-Q26 → C-J6MT` gefunden. Die bisherige
  Auswertung setzte Start und Ziel zusätzlich davor beziehungsweise dahinter
  und erzeugte dadurch zwei künstliche Nullsprünge. Festprofile akzeptieren
  nun wahlweise nur Zwischenpunkte oder eine vollständige Route; passende
  Endpunkte werden vor der Paarbildung genau einmal normalisiert;
- für einen produzierten Jump Freighter die Eigenschaft `Jump Freighters`
  zusätzlich zu `Jump Drive Calibration` und `Jump Fuel Conservation` in den
  hull-spezifischen Selbstsprung übernommen. Andere Capitals verwenden
  weiterhin nur die für sie zutreffenden allgemeinen Sprungfertigkeiten;
- die angezeigten 76,33769 % für die aktuell gespeicherte Tatara-Konfiguration
  reproduziert: 50 % Standup Reprocessing Facility I, 5,5 % Tatara-Bonus,
  Skillfaktoren 1,15 × 1,10 × 1,10, geplantes RX-804 mit 1,04 und kein
  passendes Reprocessing-Rig. Mit 53 % Rig-Basis und dem
  Nullsicherheitsmultiplikator 1,12 aus dem aktuellen SDE-Wert des
  `Standup L-Set Reprocessing Monitor II` ergeben dieselben Eingaben
  90,628106 %. Die Anlage nennt nun die tatsächlich verwendete Yield-Quelle
  und warnt gezielt, wenn das passende Rig nicht hinterlegt ist; ein nicht
  bestätigtes Rig wird weiterhin niemals stillschweigend angenommen;
- sowohl die Refining-Auswahl für komprimierte Erze als auch „Letzte fünf
  Produktionen“ in dauerhaft gespeicherte, standardmäßig geschlossene
  Offenlegungsbereiche umgewandelt. Zusammenfassungen bleiben im
  geschlossenen Zustand sichtbar.

Prüfung:

- 67 fokussierte Jump-/Production-Basis-Tests bestehen, darunter vollständige
  Festprofile mit Endpunkten, Jump-Freighter-Skillübergabe sowie
  Service-gegen-Rig-Yield;
- der vollständige isolierte SwiftPM-Lauf baut Core und App und besteht 381
  Swift-Testing-Tests in 26 Suites sowie 9 XCTest-Fälle. Der ausdrücklich
  zuschaltbare Test mit einem echten öffentlichen SDE-Paket bleibt ohne
  gesetzten Paketpfad übersprungen;
- der frische unsignierte native Xcode-Debug-Build endet mit
  `BUILD SUCCEEDED`; strikte Swift-Formatierung der betroffenen Dateien, beide
  Lokalisierungskataloge, doppelte Lokalisierungsschlüssel und
  `git diff --check` bestehen;
- das Sicherungsarchiv ist lesbar, enthält 19 Einträge, ist 499 KiB groß und
  hat SHA-256
  `da20fb33e2b87492ae3c8fd6cc2a2f0356d283a8811dcd7f98e985f694c3c3b6`.

Offen bleiben eine neue Berechnung im laufenden befüllten Programm, der echte
DOTLAN-/Markt-/ESI-Vergleich, die Bestätigung des tatsächlich montierten
Tatara-Rigs in EVE, Tastatur/VoiceOver, visuelle Prüfung und ausdrückliche
Owner-Abnahme.

## 16. August 2026 – Planner-Finanzübersicht und Verkaufsszenarien wieder aufklappbar

Ziel: Die nach der Verdichtung nur noch passiv dargestellten Verkaufsszenarien
wieder prüfbar machen und gemeinsame Produktionskosten in derselben kompakten,
aber aufklappbaren Form darstellen.

Entwicklung:

- vor dem Umbau die betroffenen Planner-, Lokalisierungs-, Test- und
  Dokumentationsdateien außerhalb des Checkouts unter
  `/Users/svenstolze/Documents/EVE NEXUS SIMPLE Backups/2026-08-15-Planner-Finanzansicht-vor-Umbau.tar.gz`
  gesichert;
- die bereits erhaltenen neun Offenlegungszustände wieder mit den kompakten
  Verkaufskarten verbunden. Die gesamte Kartenüberschrift ist jetzt eine
  Schaltfläche und öffnet Verkaufsort, Ausgangsroute, Szenariokosten, Erlös,
  Gebühren, Gewinn, Marge, ROI, Rechengleichungen und Quote-Eingaben;
- eine adaptive Finanzübersicht mit eigenen Karten für Materialbeschaffung,
  Lagerverbrauch, BPC/BPO, Installation, Eingangslogistik,
  Produktionszwischensumme und Kosten inklusive Lieferung ergänzt;
- BPC-/BPO-Zuordnungen und Logistikfracht bleiben in den jeweiligen
  Detailkarten vollständig prüfbar. Lagerverbrauch und Refining-Gebühr sind als
  bereits enthalten gekennzeichnet und werden nicht doppelt addiert;
- deutsche und englische Bedien- und Erklärungstexte sowie den UI-Handoff und
  Acceptance-Vertrag aktualisiert.

Prüfung:

- die neue App-Regression bestätigt neun getrennte Hub-/Verkaufsarten und
  unabhängig gespeicherte Offenlegungszustände der sieben Finanzkarten;
- der vollständige isolierte SwiftPM-Lauf baut Core, App und App-Tests und
  besteht 379 Swift-Testing-Tests in 26 Suites sowie 9 XCTest-Fälle, insgesamt
  388 Tests. Der ausdrücklich zuschaltbare Test mit einem echten öffentlichen
  SDE-Paket bleibt ohne gesetzten Paketpfad übersprungen;
- der frische unsignierte native Xcode-Debug-Build endet mit
  `BUILD SUCCEEDED`; strikte Swift-Formatierung, beide Lokalisierungskataloge,
  die Prüfung auf doppelte Lokalisierungsschlüssel und `git diff --check`
  bestehen;
- das vorab erstellte Sicherungsarchiv ist lesbar, enthält elf Einträge, ist
  325.918 Byte groß und hat SHA-256
  `309655a796f64b128811e2cd1cb35a2c9237452be230229f27430a852df79662`.

Offen bleiben die Sichtprüfung mit einem befüllten Plan bei schmalem und
breitem Fenster, Tastatur- und VoiceOver-Bedienung, Live-ESI-/Marktvergleich
und die ausdrückliche Owner-Abnahme.

## 15. August 2026 – Upwell-Reprocessing gegen Quelle und aktuelles SDE abgeglichen

Ziel: Die Refining-Kalkulation mit der verlinkten EVE-University-Darstellung
der CCP-Regeln abgleichen und die tatsächlich verwendeten aktuellen Werte
gegen das installierte öffentliche SDE verifizieren.

Entwicklung:

- vor der materiellen Änderung die betroffenen Dateien außerhalb des Checkouts
  unter
  `/Users/svenstolze/Documents/EVE NEXUS SIMPLE Backups/2026-08-15-Refining-vor-CCP-Abgleich.tar.gz`
  gesichert; das lesbare Archiv hat 212.884 Byte und SHA-256
  `2aa95864687e35ae662427d879c3bb0fc7b57501f3d40d62fd86c06abc43d785`;
- die Upwell-Formel aus der EVE-University-Seite ausgewertet, ihre dort selbst
  ausgewiesene veraltete Skillbeschreibung nicht als aktuelle Autorität
  übernommen und Struktur-, Service-, Rig- und Sicherheitswerte gegen den
  installierten öffentlichen CCP-SDE-Build 3466501 geprüft;
- den SDE-Strukturvertrag um den Reprocessing-Bonus aus Dogma-Attribut 2722
  ergänzt. Athanor verwendet damit 2 %, Tatara 5,5 %; ältere Profile bleiben
  kompatibel und erhalten für bekannte Strukturtypen den dokumentierten
  Fallback, ohne unbekannte Strukturen zu erfinden;
- die Anlagenbasis auf die SDE-Einheiten präzisiert: Das bessere Ergebnis aus
  50-%-Service und passendem Rig-Gesamtwert wird gewählt, der
  Sicherheitsraummultiplikator gilt nur mit diesem kompatiblen Rig und der
  Strukturbonus wird danach multiplikativ angewendet. Anschließend folgen
  Reprocessing, Reprocessing Efficiency, erzspezifisches Processing und das
  im Profil gewählte theoretische Implantat;
- SDE-Import und Anlagenanzeige um Eis-Ausbeute sowie die allgemeinen L-Set-
  und XL-Set-Reprocessing-Monitore erweitert. Diese Monitore liefern ihren
  SDE-Wert für Asteroiderz, Monderz und Eis; unpassende Größen bleiben
  wirkungslos;
- die Chargenwahl korrigiert: Der Planner sucht die kleinste ganze
  Chargenzahl, deren gemeinsam abgerundete Gesamtausgabe den Bedarf deckt,
  statt jede Charge vor der Hochrechnung einzeln abzurunden. Die Gebühr bleibt
  auf dem Adjusted-Price-Schätzwert aller tatsächlich erzeugten Mineralien;
- Regelversion, Bedienbeschreibung, Production-Basis-Vertrag, Handoff und
  Acceptance-Nachweis aktualisiert.

Ergebnis: Eine Tatara mit Reprocessing-Service und ohne Rig startet für
Asteroiderz, Monderz und Eis bei 52,75 % Anlagenbasis statt 50 %. Ein passender
T2-Rig in Lowsec verwendet `0,53 × 1,06 × 1,055`; Skills und ein ausgewähltes
RX-Implantat werden erst danach multipliziert. Der normale Planner verwendet
dieselbe korrigierte Anlagenbasis, Batchmenge, Gebühr und endgültige
Compressed-Ore-Fracht für Kosten, Einkaufsliste und Vertragsaufteilung.

Prüfung: 47 Production-Basis-Tests, der fokussierte vollständige
Compressed-Ore-Plannertest und elf SQLite-Katalogtests bestanden. Der
Opt-in-Test importierte den installierten öffentlichen SDE-Build 3466501 in
eine isolierte temporäre Datenbank und bestand ebenfalls. Der vollständige
isolierte SwiftPM-Lauf baute Core und App und bestand 379 Swift-Testing-Tests
in 26 Suites sowie acht XCTest-Fälle, insgesamt 387 Tests. Der native
unsignierte Xcode-Debug-Build endete mit `BUILD SUCCEEDED`; striktes
Swift-Format bestand.

Offen: Es wurden keine privaten ESI-Daten oder produktiven App-Daten verändert.
Der Vergleich mit der konkreten in EVE gefitteten Tatara, realen Skills,
ausgewähltem Klonimplantat, angezeigter Gebühr, Main-Hub-Markttiefe und dem
resultierenden Kuriervertrag sowie visuelle Prüfung, Tastatur, VoiceOver und
ausdrückliche Owner-Abnahme bleiben getrennt offen.

## 15. August 2026 – Planner-Logistik geprüft und Ergebnis verdichtet

Ziel: Die nach dem Umbau gemeldete Main-Hub→Home-Hub-Logistik fachlich prüfen
und die wiederholten vollständigen Verkaufskarten auf die entscheidenden
Vergleichswerte reduzieren.

Entwicklung:

- den aktuellen aktiven Planner-Snapshot nur lesend kontrolliert: Die
  Compressed-Ore-Fracht enthält 217.079,39 m³, wird in genau einen Vertrag
  geteilt und kostet nach dem gespeicherten Tarif 196.000.000 ISK; dieser Wert
  ist bereits in der Produktionskostensumme und in den Verkaufsszenarien
  enthalten;
- die Produktionskosten pro Einheit, die aufklappbare Lieferung
  **Main Hub → Home Hub** mit Frachtpositionen und die Produktionskosten
  einschließlich Lieferung einmalig in die gemeinsame Kostenkarte verschoben;
- alle vorhandenen Strategien für Main Hub, Home Hub und Koalitions-Hub als
  kompakte Vorschaukarten mit absolutem Gewinn und ROI dargestellt; gemeinsame
  Kosten werden dort nicht mehr wiederholt, unbekannte oder vorläufige Werte
  bleiben ausdrücklich erkennbar;
- beim Öffnen der Logistikeinstellungen wird nun die gespeicherte Production
  Basis mit derselben ID wie die aktive Runtime-Basis gewählt. Eine andere,
  lediglich zuletzt aktualisierte Basis kann nicht mehr versehentlich ihre
  Logistikwerte liefern;
- deutsche und englische UI-Texte sowie aktuelle Bedien- und
  Acceptance-Dokumentation angepasst.

Sicherung: Die zentrale Planner-Ansicht sowie die betroffenen Test-,
Lokalisierungs- und Dokumentationsdateien wurden vorher unter
`/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-planner-logistics-summary` mit
SHA-256-Nachweisen gesichert.

Prüfung: Der fokussierte Lauf aller 29 Industry-Planner-Tests bestand. Darin
sind die vollständige Hin-/Rückwegkostenrechnung und die Regression enthalten,
die drei direkte Mineralverträge bei wirtschaftlicher Erzsubstitution durch
genau einen Compressed-Ore-Vertrag ersetzt. Core und App einschließlich der
neuen Planner-Ansicht wurden dabei erfolgreich gebaut. Der vollständige
isolierte Lauf bestand zusätzlich acht XCTest- und 377 Swift-Testing-Tests in
26 Suites; ein ausdrücklich opt-in-gebundener Real-SDE-Test blieb planmäßig
übersprungen. Der frische unsignierte native Xcode-Debug-Build endete mit
`BUILD SUCCEEDED`. Strikte Swift-Formatprüfung, beide
Lokalisierungskataloge, Whitespace-Prüfung und der modulübergreifende
Dokumentations-Linkcheck bestanden ebenfalls.

Offen: Visuelle Prüfung mit dem befüllten Owner-Plan, Fenstergrößen, Tastatur,
VoiceOver sowie ausdrückliche Owner-Abnahme bleiben getrennte Schritte.

## 15. August 2026 – Planer 2 entfernt und Logistik in Einstellungen verschoben

Ziel: Den nicht bewährten experimentellen Planer vollständig zurücknehmen und
die Logistikpflege aus der Hauptnavigation in den bestehenden horizontalen
Bereich **Daten & Einstellungen** verschieben.

Entwicklung:

- die experimentelle View, ihren Navigationsfall, die nur dafür vorhandenen
  Intent-/Szenariotypen, den Runtime-Einstieg, Tests, Projektverweise und
  Lokalisierungen entfernt;
- die etablierte Planner-Ansicht und sämtliche gemeinsame Industrie-,
  Refining-, Kurier- und Sprunglogik unverändert beibehalten;
- **Logistik** als eigenen horizontalen Reiter zwischen
  **Industrieeinstellungen** und **Markteinstellungen** ergänzt und denselben
  Speichern-/Verwerfen-Schutz wie die übrigen Einstellungen beibehalten;
- aktuelle Architektur-, Handoff-, Bedien- und Acceptance-Dokumentation auf
  den neuen Navigationsstand gebracht; ältere Prüfnachweise des Experiments als
  historisch und superseded markiert.

Sicherung: Die entfernte experimentelle Datei und alle direkt betroffenen
Integrationsdateien wurden vor der Änderung unter
`/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-remove-planner2-move-logistics`
mit SHA-256-Nachweisen gesichert.

Prüfung: Elf fokussierte Runtime-/Navigationstests, 18 fokussierte
Sprunglogistiktests und sieben fokussierte Industrieregeltests bestanden. Der
vollständige SwiftPM-Lauf bestand acht XCTest- sowie 377 Swift-Testing-Tests in
26 Suites. Der native unsignierte Debug-Xcode-Build der App einschließlich der
in eine eigene Datei getrennten rekursiven Kalkulation war erfolgreich. Siehe
den aktuellen Nachweis in
[`Documentation/ACCEPTANCE.md`](Documentation/ACCEPTANCE.md).

Offen: Die visuelle Prüfung des horizontalen Logistikreiters in der laufenden,
befüllten App, Tastatur und VoiceOver sowie die ausdrückliche Owner-Abnahme
bleiben getrennte Freigabeschritte.

## 15. August 2026 – Refining-Implantate, korrekte Erzfracht und geführter Planner

Ziel: Die Refining-Ausbeute vollständig pro Charakter modellieren, die nach
einer Erzsubstitution tatsächlich benötigte Vertragsanzahl verwenden und einen
weniger überfordernden Planner-Versuch bereitstellen, ohne den etablierten Weg
zu ersetzen.

Entwicklung:

- pro Refining-Anlage und Charakter die ausdrückliche Auswahl **kein
  Implantat**, RX-801, RX-802 oder RX-804 ergänzt; automatische
  Charakterauswahl und Refining-Snapshot berücksichtigen den jeweiligen
  Ertragsbonus;
- Implantatauswahl direkt neben dem vorgesehenen Refiner als theoretische
  Planannahme gekennzeichnet; sie wird bewusst nicht aus dem aktuell aktiven
  EVE-Klon synchronisiert und kann vor dem späteren Klonwechsel gesetzt werden;
- alte Anlagenprofile ohne Implantatfeld kompatibel als **kein Implantat**
  beibehalten;
- die Main-Hub-Fracht nach der wirtschaftlichen Erzentscheidung neu
  zusammengesetzt: gedeckte direkte Mineralien werden zuerst entfernt,
  anschließend werden komprimiertes Erz und verbleibende Einkäufe gemeinsam
  zum Home Hub auf Verträge verteilt;
- das **Geführte Produktionslabor** in die drei Schritte Produkt,
  Einstellungen und Ergebnis gegliedert; erweiterte Filter und Ergebnisdetails
  standardmäßig eingeklappt und zunächst acht Kandidaten mit einer
  ausdrücklichen Vollansicht gezeigt;
- sichtbare Implantat-, Produkt-, Charakter- und Ortsnamen weiterhin über die
  gemeinsame EVE-Kopierinteraktion dargestellt; der etablierte Planner bleibt
  unverändert verfügbar.

Ergebnis: Die Refining-Entscheidung enthält Anlage, Skills und das gewählte
Implantat. Die Vertragsanzahl entsteht aus der endgültigen Fracht statt aus
vorher getrennten Mineral- und Refining-Teilstrecken. Der experimentelle Weg
führt durch die Entscheidung, bleibt aber sitzungsgebunden und schreibt keinen
zweiten Planbestand.

Prüfung: Der fokussierte Logistiktest belegt den Wechsel von drei direkten
Mineralverträgen zu genau einem Vertrag mit komprimiertem Erz sowie den
Rückfall auf drei Verträge bei einer unwirtschaftlichen Erzoption. Die
vollständige isolierte SwiftPM-Prüfung bestand 379 Swift-Testing-Tests in 26
Suites und acht XCTest-Fälle, insgesamt 387 Tests. Der frische unsignierte
native Xcode-Debug-Build endete mit `BUILD SUCCEEDED`.

Sicherung: Der vorherige vollständige Stand liegt unter
`/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-planner-speed.tar.gz`; der
unmittelbare gemischte Arbeitsstand wurde zusätzlich als geprüfter Patch und
separates Archiv der unversionierten Dateien unter `/private/tmp` gesichert.

Offen: Vergleich der Implantat- und Tatara-Ausbeute mit dem laufenden EVE-
Client, reale Main-Hub-Markttiefe und Kurierpreise, visuelle Prüfung sowie
Keyboard-, VoiceOver-, Performance- und Owner-Abnahme beider Planner-Wege.

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
Zeitstempel-Decodierungen schlugen fehl. Der abschließende öffentliche Lauf
`30989905311`, Job `92253308844`, baute den korrigierten Stand und bestand alle
261 Tests.

Offen: Live-EVE-/ESI-Abgleich, visuelle und barrierearme Owner-Abnahme sowie
Signierung und Notarisierung bleiben von diesem CI-Nachweis getrennt.

## 5. August 2026 – Geführte Produktauswahl im Planer

Ziel: Produzierbare Items ohne manuelle Namens- und Mengenrechnung über eine
große Drei-Zeichen-Suche auswählen, Runs sowie ME/TE eingeben und als neue
Zeile am Ende der vorhandenen Planereingabe ergänzen.

Entwicklung:

- neuen aktiven-SDE-Suchvertrag für veröffentlichte, vollständig aufgelöste
  Manufacturing-Produkte samt Output je Run ergänzt;
- 680 × 480 Punkte großes Ergebnisfeld mit Start ab drei Zeichen,
  getrenntem Namenskopieren und Auswahlknopf umgesetzt;
- Runs, ME `0...10` und TE `0...20` als geführte Eingabe ergänzt und die
  Run-Zahl über den SDE-Output in den bestehenden `Product Want ME TE`-Vertrag
  überführt, ohne vorhandene Eingabezeilen zu ersetzen;
- deutsche und englische UI-Texte, Produktionsbasisvertrag, Handoff und
  Acceptance-Matrix aktualisiert.

Ergebnis: Ein ausgewähltes Manufacturing-Produkt kann mit exakter Run-Anzahl
als neue letzte Planerzeile ergänzt werden. Mehrfach-Outputs bleiben korrekt,
weil `Want = Runs × Output je Run` gilt. Die Auswahl ist bewusst SDE- und nicht
loginabhängig; ein unbekannter oder unvollständiger Blueprint wird nicht als
produzierbar angeboten.

Prüfung: Zehn fokussierte Production-Input-Tests und sechs fokussierte
SQLite-Katalogtests bestanden isoliert. Die vollständige isolierte
SwiftPM-Suite und der unsigned native Xcode-Testlauf bauten die App und
bestanden jeweils alle 264 Tests in 21 Suites. Lokalisierungs-, Link-, Format-
und Diff-Prüfungen bestanden ebenfalls und sind im Acceptance-Eintrag getrennt
festgehalten.

Offen: Visuelle Prüfung mit bevölkertem aktiven Katalog, schmalem Fenster,
deutscher und englischer Sprache sowie Tastatur und VoiceOver; keine
Live-ESI-Prüfung wird für diese statische Blueprintsuche beansprucht.

## 8. August 2026 – Crash- und Hintergrundlast-Diagnose

Ziel: Den gemeldeten Absturz sowie hohe CPU- und Speicherlast anhand realer
macOS-Diagnoseberichte abgrenzen und bestätigte wiederholte Hintergrundarbeit
reduzieren, ohne fehlende EVE-Daten als leer oder null umzudeuten.

Entwicklung:

- den einzigen vorhandenen App-Crashbericht vom 3. August ausgewertet: Der
  Prozess endete nach etwa 31 Sekunden mit `EXC_BREAKPOINT`/`SIGTRAP` in einem
  AppKit-/SwiftUI-Constraint-Update, während eine Accessibility-Aktion einen
  segmentierten Schalter auslöste; der vollständige sprachabhängige Detailbaum
  wird deshalb bei der Sprachwahl nicht mehr synchron über `.id(...)` ersetzt;
- drei macOS-CPU-Ressourcenberichte vom 3. und 4. August abgegrenzt. Sie weisen
  über 99 bis 177 Sekunden durchschnittlich 51 %, 91 % und 51 % CPU aus; die
  anwendungseigenen Samples zeigen wiederholtes Base64-/JSON-Decoding von
  Industry Jobs und Character Capabilities in mehreren Dashboard-Gettern;
- eine unveränderliche `DashboardIndustrySnapshot`-Projektion ergänzt. Sie
  dekodiert Jobs und Skills einmal je geänderter gespeicherter Eingabe außerhalb
  des Main-Actors, aggregiert Kapazität und Quellenvollständigkeit und wird bei
  fremden Runtime-Fortschrittsupdates wiederverwendet;
- automatische Contract- und Main-Hub-Tasks auf Utility-Priorität begrenzt,
  während ein manueller Contract-Start nutzerinitiiert bleibt;
- den globalen Runtime-Besitz von der Beobachtung getrennt: App-Szene und
  Navigationscontainer halten den Runtime-Zugriff, werden aber nicht mehr bei
  jeder fachlich unabhängigen `@Published`-Änderung neu ausgewertet;
- schnell aufeinanderfolgende Contract- und Main-Hub-Fortschrittsmeldungen mit
  einem deterministischen 500-ms-Publikationsfenster gebündelt. Start,
  Phasenwechsel und terminale Zustände umgehen die Bündelung; Netzwerk- und
  Importarbeit selbst bleiben unverändert;
- den etwa 27,7-MB-großen Main-Hub-Nachfrage-Ledger um eine kleine abgeleitete
  Startzusammenfassung ergänzt. Der Ledger bleibt autoritativ; eine fehlende
  oder unlesbare Zusammenfassung fällt sicher auf ihn zurück;
- den zeitnahen Jetsam-Bericht getrennt bewertet: Die App belegte dort etwa
  322 MiB resident und maximal etwa 414 MiB, wurde aber nicht als größter oder
  beendeter Prozess ausgewiesen; der größte Prozess war der Debugger
  `lldb-rpc-server`. Ein Speichermangel-Absturz der App ist damit nicht belegt.

Ergebnis: Der durch Systemberichte belegte Dashboard-Hotspot ist aus dem
normalen SwiftUI-Neuberechnungspfad entfernt, automatische Langläufer konkurrieren
mit geringerer Priorität um CPU-Zeit, Fortschrittsereignisse lösen höchstens
zwei UI-Aktualisierungen pro Sekunde aus, und spätere Starts können die kompakte
Nachfragezusammenfassung lesen. Der bekannte Accessibility-Layoutpfad ist
entschärft, aber noch nicht als live behoben abgenommen.

Prüfung: Der fokussierte isolierte SwiftPM-Lauf baute Core und App und bestand
5 Industry-Regeltests in einer Suite. Der neue Test belegt Jobprojektion,
partielle Quellenvollständigkeit und bekannte statt erfundener Kapazität. Die
vollständige isolierte SwiftPM-Suite und der unsigned native Xcode-Testlauf
bauten anschließend die App und bestanden nach der Interaktionslatenz-Ergänzung
jeweils 267 Tests in 22 Suites. Zwei deterministische Tests belegen das
500-ms-Fenster, sofortige Grenzzustände, Reset und einen rückwärts springenden
Testzeitgeber. `swift-format` wurde auf die geänderten Swift-Dateien angewendet;
`git diff --check` bestand. Ein zusätzlicher Testlauf mit macOS-`time -l`
bestand zwar alle Tests, dessen Wrapper endete aber wegen eines in der Sandbox
gesperrten `sysctl` mit Status 1 und lieferte deshalb keinen verwertbaren
Speichernachweis. Es wurden keine Live-ESI-Anfragen, kein Commit und kein Push
ausgeführt.

Offen: Wiederholter Sprachwechsel per Maus, Tastatur und VoiceOver;
mehrstündige laufende App mit
automatischem Public-Contract-Import und Main-Hub-Scan samt CPU-, RSS- und
Speicherdruckmessung. Der historische Bericht allein beweist weder einen
Speicherleck-Fix noch Owner-Abnahme.

## 8. August 2026 – Public-Contracts-CPU-Pfad

Ziel: Den gemeldeten Absturz bei 100 % CPU im Bereich **Public Contracts**
anhand des realen lokalen Datenvolumens eingrenzen und wiederholte SQLite- sowie
SwiftUI-Arbeit entfernen, ohne den fortsetzbaren Teilindex zu verändern.

Entwicklung:

- die lokale Produktionsdatenbank ausschließlich lesend geprüft: 114 Regionen,
  47.828 Contracts, 353.313 Contract-Items und 1.346 noch ausstehende
  Detail-Contracts; `PRAGMA quick_check` meldete `ok`;
- den Query-Plan der Namenssuche und Facets untersucht. Die bisherige
  `%Suchtext%`-Abfrage scannte alle Contract-Items; Kategorie und Gruppe bauten
  zusätzlich temporäre `GROUP BY`-, `COUNT(DISTINCT ...)`- und Sortierstrukturen
  über den vollständigen Itembestand auf;
- einen kleinen abgeleiteten `contract_item_types`-Index ergänzt. Eine Kopie der
  realen Daten enthielt 10.838 unterschiedliche Typen statt 353.313 Itemzeilen;
  die neue Namenssuche scannt diese Typmenge und verwendet anschließend den
  bestehenden indexierten Typ-Join. Bestehende Daten werden einmalig und
  transaktional aus einer konsistent gewählten Zeile pro Typ migriert. Auf der
  temporären Kopie dauerte Aufbau plus `quick_check` rund 0,71 Sekunden;
- die automatische vollständige Facet- und Ergebnisaktualisierung nach jeweils
  250 importierten Items entfernt. Facets werden je Runtime einmal sowie nach
  Importende aktualisiert; vorhandene Teilzustände und Ergebnisse bleiben
  währenddessen sichtbar;
- Contract-Fortschritt auf ein Zwei-Sekunden-Fenster begrenzt, wobei
  Phasenwechsel, Abbruch, Teilstatus, Ratenlimit, Fehler und Abschluss weiterhin
  sofort veröffentlicht werden;
- Such- und Facet-Tasks prüfen Cancellation vor und nach dem Actor-/SQLite-Pfad.
  Eine Runtime-Generation verhindert, dass eine ältere Suche nach einer neueren
  Eingabe Ergebnisse oder Fehler überschreibt.

Ergebnis: Der im realen Datenbestand bestätigte wiederholte Vollscan-Pfad ist
aus dem laufenden Import und aus der Namenssuche entfernt. Der ESI-Importer,
seine Seiten-/Ratenbegrenzungen, die lokale SQLite-WAL-Datenbank und alle
partiellen, fortsetzbaren oder fehlgeschlagenen Zustände bleiben erhalten.

Prüfung: 19 fokussierte Public-Contracts-Tests bestanden einschließlich
Legacy-Migration, Ark/Arkonor-Trennung, sicherem Stopp, Ratenlimit,
Teilfortsetzung und vollständiger Seitennutzung. Die vollständigen isolierten
SwiftPM- und unsigned nativen Xcode-Läufe bauten die App und bestanden jeweils
267 Tests in 22 Suites. Striktes Swift-Formatting und `git diff --check`
bestanden. Die reale Datenbank wurde nicht migriert oder beschrieben; Query- und
Migrationstests liefen auf einer temporären Kopie.

Offen: Die optimierte App muss mit der realen Datenbank gestartet werden, damit
die einmalige Typindex-Migration und ein längerer fortgesetzter Import unter
Activity Monitor oder Instruments als Owner-/Live-Nachweis gemessen werden.
Ohne neuen `.ips`- oder CPU-Ressourcenbericht ist der gemeldete Absturzpfad
diagnostisch plausibel und gezielt entschärft, aber noch nicht live reproduziert
oder als behoben abgenommen.

## 8. August 2026 – Planner-Laufzeit und Interaktionslatenz

Ziel: Den Planner deutlich flüssiger machen und seine CPU-Laufzeit reduzieren,
ohne Mengen-, ME/TE-, Markt-, Lager-, Gebühren-, Logistik-, Installations-,
Make-or-Buy- oder Rundungslogik inhaltlich zu verändern.

Entwicklung:

- den Marktquote-Pfad profiliert. Derselbe unveränderte Orderbestand wurde für
  Kauf, Lagerwert, vollständigen Ersatzwert, Make-or-Buy, Logistik sowie Main-
  und Home-Verkauf wiederholt gefiltert und sortiert;
- `PreparedMarketOrderBook` ergänzt. Es validiert und sortiert Kauf- und
  Verkaufsorders jedes Typs einmal je Standort-Snapshot und ruft danach
  weiterhin die gemeinsame `MarketPriceEngine`-Quoteformel auf;
- die lineare Suche durch sämtliche ESI-Systemindizes je Job und
  Make-or-Buy-Analyse durch einen einmaligen, die erste Fundstelle bewahrenden
  Index nach System und Aktivität ersetzt;
- Top-Level-Produktknoten einmal je Request indiziert, statt sie für Main- und
  Home-Verkauf wiederholt rückwärts im vollständigen Planknotenbestand zu
  suchen;
- einen abweichenden Home-Hub parallel zu Main-Hub, Adjusted Prices und
  Industry Systems gestartet. Ein identischer Main/Home-Ort verwendet weiter
  exakt denselben Snapshot und nun auch dieselbe vorbereitete Orderbuchsicht;
- Planner-Neuberechnungen auf Latest-Wins umgestellt: Eine neue Quellenwahl
  bricht den vorherigen UI-Task ab, ältere Generationen dürfen keinen Plan mehr
  veröffentlichen, und der globale Working-Zustand bleibt bei überlappenden
  Operationen korrekt aktiv;
- Dekodierung gespeicherter Planreservierungen und Berechtigungen sowie die
  JSON-Kodierung des fertigen Snapshots aus dem Main-Actor verlagert;
- Fortschrittsveröffentlichungen des parallelen Main-Hub-Hintergrundscans wie
  den Contract-Fortschritt auf ein Zwei-Sekunden-Fenster begrenzt. Abschluss
  und Grenzzustände bleiben unmittelbar sichtbar.

Ergebnis: Fachliche Eingaben und Ergebnisse bleiben unverändert, während
wiederholte Order-Sortierungen, lineare Systemindex-Suchen, veraltete parallele
Planner-Läufe und große JSON-Arbeit auf dem UI-Thread entfallen. Ein separater
Home-Markt verlängert die Main-Marktphase nicht mehr seriell.

Prüfung: Eine deterministische Fixture mit 180 Typen und 57.600 Orders verglich
Materialkauf, Immediate Sale und Listed Sale einschließlich Steuern und
Brokergebühr exakt zwischen direkter und vorbereiteter Quote. Vier Quote-Pässe
benötigten im isolierten Debug-Test rund 65 ms mit wiederholter Vorbereitung;
die einmalige Vorbereitung benötigte rund 19 ms und die vier vorbereiteten
Pässe rund 12 ms. Die fokussierten Planner-, Performance- und Markt-Fixtures
bestanden. Der vollständige isolierte SwiftPM-Lauf und der unsigned native
Xcode-Testlauf bauten die App und bestanden jeweils 269 Tests in 22 Suites.
Der erste Xcode-Versuch scheiterte ausschließlich am gesperrten SwiftPM-
Diagnosecache der Sandbox; die Wiederholung außerhalb dieser Beschränkung
bestand und erzeugte ein vollständiges `xcresult`-Bundle.

Offen: Ein synthetischer Debug-Test belegt weder Release-Laufzeit noch
Live-ESI- oder Owner-Akzeptanz. Die laufende App muss mit einem tiefen realen
Plan wiederholt berechnet und bei gleichzeitigem Contract-/Main-Hub-
Hintergrundbetrieb mit Instruments beziehungsweise Activity Monitor auf
Latenz, CPU und RSS geprüft werden.

## 8. August 2026 – Public-Contracts-Start entkoppelt

Ziel: Die einmalige Migration des großen lokalen Contract-Typindex darf beim
App-Start nicht mehr den Main Actor blockieren oder die Oberfläche einfrieren.

Entwicklung:

- einen asynchronen Store-Einstieg ergänzt, der Öffnen, Schema-Prüfung und den
  unveränderten transaktionalen Backfill in einem Utility-Task ausführt;
- `RuntimeState` startet ohne synchronen SQLite-Zugriff und veröffentlicht die
  Zustände deaktiviert, vorbereitend, bereit oder fehlgeschlagen;
- Public Contracts zeigt Vorbereitung und Fehler sichtbar an, sperrt nur die
  noch nicht nutzbaren Filter und bietet einen zugänglichen Wiederholungsbutton;
- `Optimierung.md` als schlanke, verbindliche Reihenfolge für die sechs
  ermittelten Optimierungspunkte mit kurzen Folge-Prompts angelegt.

Ergebnis: Der datenabhängige Backfill konkurriert nicht mehr mit SwiftUI auf
dem Main Actor. Migration, vorhandene Contract-/Itemdaten, unbekannte
`for_corporation`-Werte und explizite Fehler-/Teilzustände bleiben erhalten.

Prüfung: Der fokussierte isolierte SwiftPM-Lauf baute die App und bestand alle
19 `PublicContractTests`. Der Legacy-Migrationstest verwendet nun denselben
asynchronen Öffnungspfad wie die App und bestätigt Contract, Item und den
unbekannten Corporation-Zustand. Anschließend bestanden am 8. August 2026 die
vollständige isolierte SwiftPM-Suite und der unsigned native Xcode-Testlauf
jeweils 269 Tests in 22 Suites. Strict Swift-Format-Lint, beide
Lokalisierungskataloge, Suite-Link-Prüfung und `git diff --check` bestanden
ebenfalls.

Offen: Erste Migration der realen Produktionsdatenbank sowie laufende CPU-/RSS-,
VoiceOver- und Owner-Abnahme. Automatische Tests belegen noch nicht, dass der
gemeldete Langzeitlauf im befüllten App-Prozess visuell und unter Last abgenommen
ist.

## 8. August 2026 – CPU-/RSS-Messung im befüllten Prozess

Ziel: Die verbleibende Dauerlast nach den Contract- und Planner-Optimierungen
im real befüllten App-Prozess lokalisieren und CPU von Speicherindikatoren
trennen.

Messung:

- laufende Debug-App zunächst mit ihrem normalen Produktionsdatenbestand
  beobachtet. Public Contracts war in allen 114 Regionen frisch; der Typindex
  enthielt 10.934 Typen, keine unterschiedliche Item-Type-ID fehlte und SQLite
  meldete `quick_check = ok`. Der bereits erfolgte erste Backfill lag zeitlich
  vor der Messung und seine Lastspitze kann deshalb nicht nachträglich belegt
  werden;
- nach dem Zurücksetzen der durch eine Accessibility-Baumabfrage verursachten
  Zusatzarbeit denselben Prozess jeweils 30 Sekunden auf Dashboard und Planer
  gemessen. Das Dashboard verbrauchte aus der Prozesszeit berechnet rund
  31,8 % CPU im Mittel, erreichte auf der macOS-Mehrkernskala 121 % und lag bei
  277 bis 457 MiB RSS. Der Planer blieb im Vergleich bei 0 % CPU und stabil
  344 MiB RSS;
- der bereinigte Stack-Sample zeigte wiederholte SwiftUI-/AttributeGraph-Arbeit
  in `DashboardMineralTicker.body` und `tickerContent`. Der Ticker verwendet
  dauerhaft eine 30-Hz-`TimelineView` und erzeugt für die Endlosschleife bei
  jedem Aufbau eine verdoppelte, enumerierte Zeilenfolge;
- der Sample meldete rund 296 MiB physischen Footprint und einen bisherigen
  Prozesspeak von rund 829 MiB. Die abweichenden RSS-Schnappschüsse und der
  kurze Zeitraum reichen nicht als Nachweis eines Speicherlecks;
- zusätzlich eine unsigned Release-App gegen eine Copy-on-write-Kopie des
  Application-Support-Verzeichnisses gebaut. Der isolierte Prozess blieb bei
  0 % CPU und 70 MiB RSS, stellte aber keine vergleichbare sichtbare
  Dashboard-Arbeitslast her. Dieser Wert gilt deshalb nur als kalter
  Hintergrundwert und nicht als Release-Vergleich des Tickers.

Ergebnis: Die reproduzierbare Dauerlast hing in dieser Messung an der sichtbaren
Dashboard-Animation, nicht an einer laufenden Contract-Synchronisation oder
Planerberechnung. Der befüllte Planer war im Ruhezustand CPU-idle. Es wurde in
diesem Schritt bewusst keine Ticker-Implementierung verändert.

Prüfung: Prozesszeit und RSS wurden sekundengenau über `top` verglichen; ein
15-Sekunden-Stack-Sample lokalisierte den Hotspot bis auf
`ContentView.swift:1631` und `ContentView.swift:1651`. Die Bedienung über die
Accessibility-Schnittstelle wurde als Messstörung erkannt, zurückgesetzt und
die A/B-Reihe danach ohne weitere Baumabfragen wiederholt. Die Produktionsdaten
wurden nur gelesen; die temporäre Release-Instanz wurde beendet und ihre
Copy-on-write-Datenkopie entfernt. Die normale App blieb im CPU-idlen Planer
geöffnet.

Offen: Sichtbaren Release-Dashboard-A/B-Vergleich durchführen, den Ticker ohne
inhaltliche Änderung CPU-sparend umsetzen und anschließend dieselbe Reihe sowie
einen mehrstündigen Lauf unter Contract-/Main-Hub-Arbeit und Speicherdruck
wiederholen. Ein Crash wurde in dieser kurzen Messung nicht reproduziert.

## 8. August 2026 – Dashboard-Ticker in den Compositor verlagert

Ziel: Die gemessene CPU-Dauerlast des sichtbaren Mineralpreistickers beseitigen,
ohne Preise, Reihenfolge, Farben, 32-Sekunden-Umlauf, Accessibility oder
Reduced-Motion-Verhalten zu ändern.

Entwicklung:

- einen ersten Umbau auf eine gewöhnliche lineare SwiftUI-Offsetanimation im
  sichtbaren befüllten Release-Dashboard gemessen. Trotz stabiler Zeilenstruktur
  verbrauchte sie dauerhaft rund 38 % CPU, weil SwiftUI und AppKit weiterhin pro
  Frame Layoutzyklen ausführten; diese Variante wurde verworfen;
- die doppelte Mineralzeilenfolge stattdessen einmal in einer `NSHostingView`
  aufgebaut und nur deren Layer mit einer linearen `CABasicAnimation` bewegt;
- die Layeranimation bei inaktiver App entfernt. Die vorhandene statische,
  horizontal scrollbare Ansicht für **Bewegung reduzieren** bleibt getrennt;
- keine Markt-, Preis-, Aktualisierungs- oder Persistenzlogik verändert.

Ergebnis: Im sichtbaren isolierten Release-Dashboard sank die Prozessarbeit auf
0,07 CPU-Sekunden in rund 34 Sekunden, entsprechend etwa 0,2 % im Mittel. 33
von 35 Stichproben meldeten 0 %, die einzige materielle Spitze 5,7 %. In einem
frischen Abschlusslauf ohne vorherige Accessibility-Abfrage blieb RSS stabil
bei 193 bis 194 MiB und die Prozesszeit stieg ebenfalls nur um 0,07 Sekunden.
Der Release-Planer-Kontrolllauf benötigte 0,01 CPU-Sekunden in rund 24 Sekunden
bei stabilen 174 MiB RSS.

Prüfung: Zwei sichtbare Dashboard-Frames im Abstand von 1,8 Sekunden zeigten
die weiterlaufende Verschiebung bei identischen Mineralen, Werten und
Reihenfolge. Strict Swift-Format-Lint und `git diff --check` bestanden. Der
unsigned universelle Release-Build war erfolgreich; die vollständige
SwiftPM-Suite baute die App und bestand 269 Tests in 22 Suites. Mess-App und
Produktions-App verwendeten getrennte Daten- und Einstellungswurzeln; die
temporäre Messinstanz und alle dafür erzeugten Daten-, Build- und Sample-Dateien
wurden anschließend entfernt.

Offen: Mehrstündiger Lauf unter realer Contract-/Main-Hub-Arbeit und
Speicherdruck sowie Owner-Abnahme von Bewegung, Reduced Motion und VoiceOver.
Die kurzen stabilen RSS-Reihen beweisen allein noch nicht, dass kein
Langzeit-Speicherleck existiert. Punkt 2 des Optimierungsplans bleibt der nächste
größere Schritt.

## 8. August 2026 – Planer-Invalidierung vom Gesamtlaufzeitzustand getrennt

Ziel: Public-Contract-, Markt-, Dashboard- und sonstige Hintergrundmeldungen
dürfen den großen Planer-View-Baum nicht unnötig neu auswerten; Rechenbefehle,
Fachzustände und gespeicherte Fakten bleiben unverändert.

Entwicklung:

- einen schmalen beobachtbaren `RuntimeFeatureState` als
  Planer-Invalidierungskanal ergänzt. `RuntimeState` bleibt alleiniger
  Koordinator und fachliche Quelle;
- nur Änderungen an Produktionsbasis, Plan, globalem Rechenstatus/-fehler,
  Lagerfreigabe und Planer-Konfigurationsbereitschaft invalidieren diesen
  Kanal;
- `PlannerView` und die eingebettete Manufacturing-Produktsuche erhalten den
  Runtime-Koordinator explizit, beobachten ihn aber nicht mehr vollständig;
- einen eigenen SwiftPM-App-Testtarget ergänzt, damit die tatsächliche
  Runtime-/SwiftUI-Grenze ohne Live-ESI-Daten geprüft werden kann.

Ergebnis: Allgemeine Status-, SDE-Installations- und Public-Contract-
Publikationen ändern die Planer-Revision nicht. Ein echter `NSHostingView`-
Test zeigt außerdem, dass dessen beobachtender View-Körper dabei unverändert
bleibt und erst eine planerspezifische Veröffentlichung neu ausgewertet wird.
Die fachliche Planerlogik wurde nicht verändert.

Prüfung: Drei fokussierte Runtime-/Hosting-Tests bestanden. Die vollständige
isolierte SwiftPM-Suite bestand 272 Tests in 23 Suites. Strict Swift-Format-Lint
und `git diff --check` bestanden; der nicht signierte universelle native
Release-Build war erfolgreich. Der bereits zuvor gemessene befüllte
Release-Planer war im Ruhezustand mit 0,01 CPU-Sekunden in rund 24 Sekunden und
stabilen 174 MiB RSS CPU-idle.

Offen: Ein längerer sichtbarer Planer-Lauf während einer echten Contract- oder
Main-Hub-Hintergrundsynchronisation, ein Instruments-Vergleich der SwiftUI-
Updates, Speicherdruck und Owner-Abnahme. Die strukturelle Trennung und die
kurze Ruhemessung beweisen keinen mehrstündigen Speicherverlauf.

## 8. August 2026 – Planner-Persistenz und Historie begrenzt

Ziel: Punkt 3 des Optimierungsplans umsetzen, ohne aktive Reservierungen,
historische Werte, Summen, Provenienz oder gespeicherte Quelldaten zu ändern.

Entwicklung:

- die vollständigen `StoredProductionRecord`- und
  `StoredProductionOverviewRow`-Queries aus dem Planner entfernt. Der Planner
  hält nur noch fünf aktuelle Produktionszeilen; Legacy-Fallback und ein
  angeforderter Historieneintrag werden mit begrenzten Direktabfragen gelesen;
- die nächste Produktionsnummer über eine auf einen Datensatz begrenzte
  Maximalwertabfrage ermittelt, statt dafür alle Historienzeilen zu laden;
- die Produktionsübersicht auf stabil geordnete Seiten mit höchstens 100
  Zeilen umgestellt. Die sichtbare Seite bleibt vollständig editier- und über
  alle Spalten sortierbar;
- vollständige Anzahl-, Unit- und Gewinnsummen in einen eigenen SwiftData-
  Model-Actor verlagert. Unbekannte Teilwerte halten die jeweilige Summe weiter
  unverfügbar;
- Plan-Snapshots und Request-Projektionen je unveränderlichem Plan einmal
  dekodiert und zwischen seinen Produktionszeilen geteilt. Beim Seitenwechsel
  werden nicht mehr benötigte Cacheeinträge verworfen;
- deutsche und englische Paging-, Lade- und Fehlertexte ergänzt.

Migrationsvorschau: Das SwiftData-Schema bleibt unverändert bei Version 2; es
werden keine Zeilen, Snapshotbytes oder Provenienzfelder migriert, geleert oder
gelöscht. Die Produktionsdatenbank wurde ausschließlich lesend geprüft:
`quick_check = ok`, 87 gespeicherte Pläne (1 aktiv, 86 inaktiv), 10
Produktionszeilen und keine Legacy-Produktionsrecords. Die bestehenden
Plan-Snapshots belegen 38.871.606 Byte, die unveränderten Historien-Snapshots
3.569.858 Byte. Der kanonische V2-Backupmarker und eine vollständige
V2-Sicherheitskopie sind vorhanden; wegen der fehlenden Schemaänderung wurde
keine neue Migration ausgelöst.

Ergebnis: Der normale Planner hält nicht länger die vollständige
Produktionshistorie im beobachteten UI-Kontext. Eine geöffnete
Produktionsübersicht begrenzt ihre editierbaren Modelle auf eine Seite, während
die fachlich vollständigen Summen separat berechnet werden. Bestehende Daten
bleiben unverändert und lesbar.

Prüfung: Sechs deterministische App-Tests mit bis zu 205 Historienzeilen
bestätigen das Fünf-Zeilen-Limit, 100er-Seiten, stabile Reihenfolge, direkte
Fallback-/ID-Abfragen, die unveränderte aktive Warehouse-Reservierung, die
nächste Produktionsnummer, identische vollständige Gewinnsummen und genau eine
Snapshot-Dekodierung für zwei Zeilen desselben Plans. Der fokussierte Lauf
bestand. Strict Swift-Format-Lint, beide Lokalisierungsdateien und
`git diff --check` bestanden. Die vollständige isolierte SwiftPM-Suite bestand
278 Tests in 24 Suites. Der native unsigned Xcode-Lauf baute die App und
bestand 269 Core-Tests in 22 Suites; die sechs neuen App-Persistenztests sind
im SwiftPM-Lauf enthalten, weil das aktuelle native Projekt nur den
Core-Testtarget führt. Der unsigned universelle Release-Build war erfolgreich;
`lipo` bestätigte `arm64` und `x86_64`. Xcodes wiederholte Hinweise auf ein
gesperrtes angeschlossenes Mobilgerät betrafen nur die Geräteerkennung und
nicht den erfolgreichen macOS-Test oder Build.

Offen: Sichtbare Owner-Abnahme der Seitennavigation und Bearbeitung mit einer
Historie über 100 Zeilen sowie ein längerer CPU-/RSS-Lauf. Die bestehende
Produktionsdatenbank enthält derzeit nur zehn Historienzeilen und kann das
Paging deshalb nicht live auslösen.

## 8. August 2026 – Kompakter Demand-Ledger und Planner-Vorrang

Ziel: Punkt 4 des Optimierungsplans umsetzen: Den großen exakten Main-Hub-
Nachfrage-Ledger schneller und speicherschonender verarbeiten und schwere
automatische Scans während interaktiver Planner-Berechnungen aussetzen, ohne
Order-ID-, Hub-, Seiten- oder UTC-Tagessemantik zu ändern.

Entwicklung:

- das Ledger-Schema V2 ergänzt. Die vorherige Vergleichsbaseline wird nicht
  mehr als ausführliches Objekt je Order, sondern als kompakte Zeile aus
  Order-ID, Typ-ID, Standort-ID, Seite und Restmenge kodiert;
- den V1-Decoder beibehalten. Eine vorhandene Datei wird weder beim App-Start
  noch durch eine separate Migration verändert, sondern erst nach einem
  vollständigen neuen Snapshot atomar im V2-Format geschrieben;
- Vergleich und Aufbau der nächsten Baseline zu einem Durchlauf verbunden.
  Alle 2.048 Orders wird die Task-Abbruchanforderung geprüft; erst nach einem
  vollständigen Durchlauf werden Nachfrage und Baseline gemeinsam ersetzt;
- eine gemeinsame Planner-Koordination für automatische Main-Hub- und Public-
  Contracts-Arbeit ergänzt. Ein Planner-Lauf entfernt geplante Timer, bricht
  bereits laufende automatische Tasks kooperativ ab und stellt die Zeitpläne
  erst nach dem letzten überlappenden Planner-Lauf wieder her;
- manuelle Scans ausdrücklich aus dieser automatischen Unterbrechungsregel
  ausgenommen. Contract-Teilindex und letzte vollständige Main-Hub-Analyse
  bleiben bei einem Abbruch erhalten.

Read-only-Messung: Die unveränderte lokale V1-Produktionsdatei enthält 327.835
Baseline-Orders und belegt 27.749.835 Byte. Eine Projektion genau derselben
Daten in die neue kompakte JSON-Form ergab 10.793.617 Byte, also rund 61 %
weniger. Die Produktionsdatei blieb dabei unverändert und wird erst durch einen
späteren erfolgreichen App-Scan migriert.

Ergebnis: Die fachliche Nachfragesemantik bleibt gleich, der synchrone
Orderdurchlauf erzeugt keinen getrennten vollständigen aktuellen Zwischenindex
mehr, und interaktive Planner-Arbeit konkurriert nicht länger mit implizit
gestarteten Main-Hub- oder Contract-Scans. Abbruch veröffentlicht keine
teilweise Demand-Baseline; automatische Arbeit bleibt anschließend
wiederaufnehmbar.

Prüfung: 21 fokussierte Markt-/Ledger-Tests bestätigen V1-zu-V2-Migration,
identische überlebende Order-ID-Abnahme, UTC-Tagesreset, unverfügbare erste
Messung und unveränderten Ledger nach Abbruch. Fünf App-Koordinierungstests
bestätigen die Unterbrechung beider Automatikarten sowie die Wiederaufnahme erst
nach dem letzten parallelen Planner-Lauf. Die vollständige isolierte SwiftPM-
Suite baute Core und App und bestand 282 Tests in 24 Suites. Der unsigned native
Xcode-Lauf baute die App und bestand die dort eingebundenen 271 Core-Tests in 22
Suites; die zwei App-Koordinierungstests laufen im SwiftPM-App-Testtarget. Der
unsigned universelle Release-Build war erfolgreich, und `lipo` bestätigte
`arm64` sowie `x86_64`. Strict Swift-Format-Lint und `git diff --check`
bestanden. Es wurden keine Live-ESI-Anfragen, kein Commit und kein Push
ausgeführt.

Offen: Ein realer langer App-Lauf mit gleichzeitig aktiviertem Main-Hub- und
Contract-Automatismus sowie wiederholten tiefen Planner-Berechnungen muss CPU,
RSS, Abbruchfortschritt und Wiederaufnahme noch per Instruments beziehungsweise
Activity Monitor bestätigen. Automatische Tests sind keine Live-ESI- oder
Owner-Abnahme.

## 8. August 2026 – Globale ESI-Grenze und Cache-Speicherdruck

Ziel: Punkt 5 des Optimierungsplans umsetzen: Gleichzeitige ESI-Arbeit so
begrenzen und priorisieren, dass automatische Hintergrundimporte die
interaktive Arbeit nicht fluten, und große abgeleitete Antwort-Caches nach
Nutzung oder bei macOS-Speicherdruck freigeben. Paging, Rate-/Error-Limit,
Header, Retry und explizite Teilzustände sollten fachlich unverändert bleiben.

Entwicklung:

- einen gemeinsamen, abbruchfesten ESI-Anfragekoordinator in den vom App-
  Prozess geteilten `ESIClient` aufgenommen. Insgesamt dürfen sechs
  Transportanfragen laufen, automatische Arbeit höchstens zwei; innerhalb
  einer Priorität bleibt die Warteschlange stabil, interaktive Arbeit erhält
  vor noch nicht gestarteter Automatik Vorrang;
- die Zulassung auf einzelne Transportversuche gelegt. Cache-Treffer benötigen
  keinen Slot, und ein idempotenter GET-Retry hält während seiner Wartezeit
  keinen Slot. POST bleibt ohne generischen Retry;
- automatische Manufacturing-Opportunity-, Public-Contract- und Main-Hub-
  Arbeit als automatisch, manuell gestartete beziehungsweise Planner-Arbeit
  als interaktiv gekennzeichnet. Die bestehende Punkt-4-Koordination bleibt
  erhalten;
- den ESI-Antwortcache um gezieltes LRU-Trimming ergänzt. Nach Planner-Arbeit
  bleiben höchstens 32 MiB, bei macOS-Warnspeicherdruck 16 MiB und bei
  kritischem Druck keine abgeleiteten Antwortkörper. Regional- und Item-Seiten
  des Contract-Imports werden nach ihrer fachlichen Übernahme freigegeben;
- die große dekodierte Manufacturing-Opportunity-Kopie nach Speicherung oder
  Speicherdruck freigegeben. Der persistierte letzte gültige Snapshot bleibt
  unverändert und wird beim nächsten Zugriff erneut dekodiert;
- Architektur-, Handoff-, Akzeptanz- und Bedienungsdokumentation sowie den
  Optimierungsplan aktualisiert. Die aktuellen offiziellen ESI-Hinweise zu
  Cache-Nutzung, Bucket-/Error-Limit-Headern und `Retry-After` wurden geprüft.

Ergebnis: Unabhängige ESI-Konsumenten können die CPU- und Transportarbeit des
gemeinsam genutzten App-Clients nicht mehr unbegrenzt vervielfachen.
Interaktive Berechnungen werden vor wartender Automatik bedient, während
laufende Anfragen, Antwortsemantik, Paging, gespeicherte letzte gültige Daten
und sichtbare Teil-/Fehlerzustände erhalten bleiben. Abbruch und Retry geben
ihre Zulassung sauber frei.

Prüfung: 110 fokussierte ESI-, Public-Contract-, Market- und Runtime-Tests
bestanden. Die vollständige isolierte SwiftPM-Suite baute Core und App und
bestand 289 Tests in 24 Suites. Der unsigned native Xcode-Lauf baute die App
und bestand 278 Core-Tests in 22 Suites. Der unsigned universelle Release-Build
war erfolgreich; `lipo` bestätigte `arm64` und `x86_64`. Strict Swift-Format-
Lint und `git diff --check` bestanden. Ein synthetischer Lauf mit 120
gleichzeitigen eindeutigen ESI-Anfragen bestätigte die Grenze und lief in 0,203
Sekunden; `/usr/bin/time -l` meldete für den Testprozess maximal 69.042.176 Byte
RSS (rund 65,8 MiB) und keine Swaps. Es wurden keine Live-ESI-Anfragen, keine
Produktionsdatenänderung, kein Commit und kein Push ausgeführt.

Offen: Der synthetische Testprozess ersetzt keinen mehrstündigen Lauf der
befüllten signierten App. Noch zu messen sind RSS-Abfall unter echtem
macOS-Speicherdruck, UI-Reaktionszeit und Durchsatz bei gleichzeitigem
Contract-/Main-Hub-Automatismus und tiefen Planner-Läufen sowie Verhalten unter
realen aktuellen ESI-Bucket- und Fehlergrenzen. Automatische Nachweise sind
keine Live-ESI- oder Owner-Abnahme.

## 8. August 2026 – Geführtes Produktionslabor als getrennter Weg

Ziel: Den zuvor geprüften alternativen Weg der Produktions- und Gewinnplanung
als klar abgegrenztes Experiment einbauen, ohne den etablierten Planner oder
seine gespeicherten Daten zu ersetzen. Die spätere Entscheidung sollte alter
Weg, neuer Weg, beide Wege oder das Verwerfen des Experiments ausdrücklich
offenlassen.

Entwicklung:

- die Seitenleiste in etablierte und experimentelle Abläufe gegliedert und das
  **Geführte Produktionslabor** ausschließlich dem experimentellen Abschnitt
  zugeordnet; der bisherige Planner bleibt mit eigener Route erhalten;
- Produktauswahl aus dem gespeicherten Main-Hub-Chancen-Snapshot oder über die
  aktive lokale SDE-Manufacturing-Suche ergänzt. Produktname, Typ-ID,
  Zielmenge, ME/TE und Auswahlherkunft werden als sitzungsgebundene Absicht an
  die bestehende Planereingabe übergeben;
- dieselbe Industry-Planner-, Warehouse-, Reservierungs-, Blueprint-,
  Anlagen-, Gebühren- und Logistiklogik wiederverwendet. Der neue Weg lädt nur
  für sich die getrennten Main-/Home-Märkte und lässt Main/Home ×
  Sofortverkauf/Verkaufsorder bewusst auswählen, statt automatisch einen
  angeblich besten Weg festzulegen;
- mehrere Make-or-Buy-Änderungen lokal gesammelt und erst nach einer expliziten
  gemeinsamen Neuberechnung angewendet. Damit startet nicht jeder einzelne
  Auswahlklick den vollständigen Produktionsgraphen und die Marktberechnung;
- Einkaufsliste mit Multibuy-Kopie, Blueprint-Bereitschaft und explizite
  Warnungen für fehlende Daten dargestellt. Alle sichtbaren EVE-Produkt-,
  Material-, Blueprint- und Ortsnamen verwenden die gemeinsame kopierbare
  Namenskomponente;
- den neuen Ablauf ausdrücklich ohne `RuntimeState.plan`, `StoredPlan`,
  Planner-Entwurf, Produktionsübersichtszeile oder Schemaänderung umgesetzt.
  Interaktive Berechnungen nutzen die vorhandene Hintergrundarbeits-Pause und
  das anschließende ESI-Cache-Trimming.

Ergebnis: Beide Wege sind gleichzeitig vorhanden und technisch getrennt. Das
Produktionslabor führt von der Auswahl über lokale Eingaben und gebündelte
Bezugsentscheidungen bis zum Vergleich eines bewusst gewählten Verkaufswegs,
ohne bestehende Planner-Daten zu verändern. Es gibt noch keine Entscheidung,
welcher Weg dauerhaft Produktstandard wird.

Prüfung: Drei neue Core-Tests bestätigen die verlustfreie Eingabe- und
Provenienzübergabe, ungültige Grenzwerte und die eindeutige Auswahl der vier
Verkaufswege. Ein App-Test bestätigt die getrennte experimentelle Menügruppe
und die weiter vorhandene Planner-Route. Der vollständige isolierte SwiftPM-
Lauf baute Core und App und bestand 293 Tests in 24 Suites. Beide
Lokalisierungskataloge bestanden `plutil -lint`, enthalten keine doppelten
Schlüssel, und `git diff --check` bestand. Der unsigned native Xcode-Lauf baute
die App einschließlich des neuen expliziten Source-Eintrags und bestand 281
Core-Tests in 22 Suites; der Navigationstest liegt im SwiftPM-App-Testtarget.
Xcodes Hinweis auf ein gesperrtes angeschlossenes Mobilgerät betraf nur die
Geräteerkennung und nicht den erfolgreichen macOS-Test. Es wurden keine
Produktionsdaten geschrieben, keine Live-ESI-Abnahme durchgeführt und kein
Commit oder Push erstellt.

Offen: Ein befüllter laufender App-Vergleich muss Layout, Produktsuche,
Main-/Home-Hub-Ergebnisse, tatsächliche Latenz, CPU/RSS, Abbruch,
Tastaturbedienung und VoiceOver prüfen. Erst danach folgt die Owner-
Produktentscheidung, ob alter Weg, neuer Weg oder beide bleiben beziehungsweise
welcher Weg verworfen wird.

## 9. August 2026 – Main-Hub-Chancen: Tagesbedarf, Rundlauf und Runs

Ziel: Die Main-Hub-Chancenanalyse so korrigieren, dass Nachfrage und Gewinn
nicht mehr als voneinander getrennte Einzelwerte missverstanden werden. Der
vollständige wirtschaftliche Weg sollte Kauf am Main Hub, Transport zum Home
Hub, Produktion, Rücktransport und gelisteten Verkauf abbilden. Zusätzlich
sollte die Anzahl der Blueprint-Durchläufe direkt planbar sein.

Entwicklung:

- den Nachfrage-Ledger auf V3 erweitert. Vergleichsabdeckung wird nun pro
  Typ-ID geführt; nur fortbestehende identische Order-ID-/Typ-/Seiten-/Orts-
  Paare liefern eine beobachtete Untergrenze. Kleine Intervalle werden über UTC-
  Mitternacht in einem rollierenden 24-Stunden-Fenster gehalten und erst ab 30
  Minuten auf eine Tagesrate normiert. Nicht vergleichbare Typen bleiben
  unverfügbar statt fälschlich Bedarf null zu erhalten;
- das tägliche Gewinnpotenzial als `Gewinn je produzierte Einheit ×
  beobachteter Tagesbedarf` ergänzt und als Standardsortierung verwendet. Der
  Vergleich 1.000 Einheiten/Tag × 1 Mio. ISK und 1 Einheit/Tag × 1 Mrd. ISK
  ergibt in beiden Fällen 1 Mrd. ISK/Tag;
- die Chancenrechnung auf einen verpflichtenden vollständigen Rundlauf
  umgestellt. Unterschiedliche exakte Main-/Home-Identitäten benötigen
  aktivierte, vollständige Logistik. Eingekauft und inbound transportiert wird
  nur der nach Warehouse, Schutzbestand und Reservierungen verbleibende
  Materialbedarf; der vollständige Output wird zurück zum Main Hub
  transportiert. Fehlende Logistik macht Gewinn und ROI unverfügbar, identische
  Standort-IDs ergeben dagegen belegbar null Transportkosten;
- die Szenarioeingabe von einer mehrdeutigen Zielmenge auf Blueprint-Runs
  umgestellt. Runs skalieren SDE-Ausgabe, Materialrundung, Installation,
  Produktionszeit, beide Transporte und Verkaufserlös. Der aufgeklappte
  Produktionsbaum rechnet Runs × Output je Run in den bestehenden exakten
  Zielmengenvertrag um;
- Tagesbedarf, tägliches Gewinnpotenzial und geschätzte Verkaufsdauer in der
  sortierbaren Tabelle beziehungsweise Kostendetailansicht ergänzt. Beide
  Transportwege werden mit getrennt kopierbaren Ortsnamen gezeigt;
  Produktkopie, Chancenauswahl und Baumöffnung sind getrennte Aktionen.

Ergebnis: Die Main-Hub-Rangfolge kann hohe Stückzahl mit kleiner Marge und
niedrige Stückzahl mit großer Marge auf derselben täglichen ISK-Basis
vergleichen. Unbeobachtete Nachfrage, unvollständige Preise, Gebühren,
Warehouse- oder Logistikdaten bleiben ausdrücklich unverfügbar.

Prüfung: 27 fokussierte Markt-/Chancen-Tests bestanden, einschließlich
Nachfragenormierung, Mindestintervall, UTC-Mitternacht, Abbruch, V1→V3-
Migration, expliziter Runs, exakter Standort-IDs und Rundlauf. Der vollständige
SwiftPM-Lauf bestand 299 Tests in 24 Suites; der unsigned native Xcode-Lauf
bestand 287 Core-Tests ohne Fehler oder Überspringungen. Swift-Format,
Lokalisierungs-Plists, doppelte Schlüssel, Dokumentationslinks und
`git diff --check` wurden geprüft. Es wurden keine Live-ESI-Daten abgerufen,
keine Produktionsdatei migriert und kein Commit oder Push erstellt.

Offen: Für eine fachliche Owner-Abnahme sind zwei reale exakte Main-Hub-
Snapshots mit mindestens 30 Minuten Abstand, ein Vergleich der Tagesrate mit
sichtbarer Orderbewegung sowie Szenarien mit 1, 10 und 100 Runs gegen EVE,
SDE-Ausgabe, Produktionsjobs und Transportanbieter erforderlich. Vollständig
gefüllte, verschwundene, abgelaufene oder stornierte Orders bleiben absichtlich
nicht geraten; die Rate ist deshalb eine konservative Untergrenze.

## 9. August 2026 – Kombinierte Main-Hub-Produktfilter

Ziel: Die bereits vorhandene Mehrfachauswahl für Schiffe, Module, Rigs,
Komponenten und weitere Produktarten um belastbare Filter für Tech I, Tech II,
Tech III und Faction zu ergänzen. Beide Dimensionen sollten gleichzeitig
anklickbar und kombinierbar sein.

Entwicklung:

- das wiederverwendbare SDE-Typmodell um die bereits im offiziellen
  `types.jsonl` vorhandenen optionalen Felder `metaGroupID` und `techLevel`
  erweitert und beide im zielseitigen SQLite-Katalog gespeichert;
- die Industry-Klassifikation und gespeicherte Main-Hub-Chancen-Zeile um diese
  Rohmetadaten ergänzt. Die fachliche Einteilung umfasst Tech I, Tech II, Tech
  III, Faction, Storyline und Sonstige / nicht klassifiziert;
- die deaktivierten Platzhalter im erweiterten Filter durch zugängliche
  Mehrfachauswahl-Schalter ersetzt. Innerhalb einer Filtergruppe gilt ODER,
  zwischen Produktionsklasse und Produktart UND. **Alles auswählen**, **Alle
  abwählen** und **Filter löschen** wirken auf beide Gruppen;
- alte SQLite-Kataloge über eine Spalteninventur kompatibel gehalten. Fehlen
  die neuen Felder, bleiben Einträge nicht klassifiziert und die UI verlangt
  einen SDE-Update-/Neuanalyse-Schritt, statt Tech-Level aus Produktnamen zu
  raten.

Ergebnis: Kombinationen wie **Faction + Schiffe**, **Tech II + Module** oder
**Tech I + Tech II + Komponenten + Rigs** werden lokal über den unveränderlichen
Chancen-Snapshot gefiltert und lösen keine ESI-Anfrage oder Neuberechnung der
Gewinnlogik aus.

Prüfung: 33 fokussierte Market-/SQLite-Tests in zwei Suites, 6 Tests der
vendorten EVEStaticDataKit-Kopie, 299 vollständige SwiftPM-Tests in 24 Suites
und 287 unsigned native Xcode-Tests in 22 Suites bestanden. Swift-Format,
beide Lokalisierungs-Plists, doppelte Schlüssel, Dokumentationslinks und Diff-
Whitespace wurden geprüft. Die lokale aktive SDE-Paketdatei wurde nur
read-only auf die vorhandenen Felder untersucht; ein Live-SDE-Import und die
visuelle/VoiceOver-Owner-Abnahme wurden nicht durchgeführt. Es wurde nichts
committed oder gepusht.

Offen: Der bereits aktivierte lokale SQLite-Katalog wurde noch mit dem älteren
Adapter erzeugt und enthält die beiden Spalten nicht. Nach Aktivierung eines
neu importierten SDE-Katalogs und einer erneuten Main-Hub-Analyse müssen die
Kombinationen mit repräsentativen EVE-Typen visuell geprüft werden.

## 9. August 2026 – Sicherer Neuimport desselben SDE-Builds

Ziel: Einen bereits aktuellen offiziellen SDE-Build nach einer Erweiterung des
lokalen Katalogadapters erneut importieren können, ohne die Update-Regel zu
lockern oder den aktiven Legacy-Katalog vorzeitig zu ersetzen.

Entwicklung:

- in **Data & Settings → SDE** eine getrennte Aktion für den Neuimport des
  aktuellen Katalogs ergänzt. Sie erscheint ausschließlich, wenn aktiver und
  offizieller Build übereinstimmen, und besitzt einen eigenen
  Bestätigungsdialog mit Sicherungs-, Staging- und Aktivierungshinweis;
- normalen Update und Same-Build-Neuimport im Lifecycle als unterschiedliche
  bestätigte Befehle modelliert. Beide binden die Freigabe an eine unmittelbar
  erneut geladene, unveränderte Vorschau und dieselbe Schema-Prüfgrenze;
- den zielseitigen SQLite-Katalogadapter auf Dateiformat V2 gehoben. V2 nutzt
  für denselben Build und Hash einen eigenen Dateinamen, sodass die alte Datei
  weder überschrieben noch als vermeintlich fertiger Import wiederverwendet
  wird. Legacy-Zeiger bleiben streng validiert und lesbar; ein Rollback nach
  Build bevorzugt regulär den aktuellen Adapter. Während einer Installation
  hält der Katalog zusätzlich den exakt gesicherten vorherigen Zeiger, damit
  die Fehlerbehandlung auch bei identischer Buildnummer auf die Legacy-Datei
  zurücksetzen kann;
- deutsche und englische Bedienhinweise sowie Lifecycle-, Handoff- und
  Betriebsdokumentation ergänzt.

Ergebnis: Derselbe offizielle JSONL-Build kann jetzt bewusst durch die bereits
vorhandene Download-, isolierte Validierungs-, Sicherheitskopie- und atomare
Aktivierungskette laufen. Erst danach kann eine neue Main-Hub-Analyse die
ergänzten `metaGroupID`-/`techLevel`-Spalten faktisch verwenden.

Prüfung: Elf fokussierte Tests in zwei Suites bestanden. Der neue
Migrationsfixture startet mit einem gültigen Legacy-Zeiger, erstellt eine
Sicherheitssicherung, importiert denselben Build als Adapter V2 neu, behält die
Legacy-Datei, aktiviert erst danach V2 und setzt über denselben Build wieder
gezielt auf den gesicherten Legacy-Zeiger zurück. Die App und beide betroffenen
Targets kompilierten dabei. Der vollständige SwiftPM-Lauf bestand 300 Tests in
24 Suites; der unsigned native Xcode-Lauf bestand 288 Core-Tests in 22 Suites.
Swift-Format und beide Lokalisierungs-Plists sind fehlerfrei. Ein echter
SDE-Import wurde nicht ausgeführt und bleibt getrennt nachzuweisen.

Offen: Den Neuimport im laufenden, befüllten Programm ausführen, verfügbare
Platte und Laufzeit beobachten, anschließend die Main-Hub-Analyse neu starten
und Faction-/Tech-Kombinationen mit repräsentativen EVE-Typen visuell sowie mit
VoiceOver prüfen. Bis dahin ist die Funktion implementiert und automatisch,
nicht aber live oder durch den Owner abgenommen.

## 9. August 2026 – Sichtbarer Neustart-Hinweis nach SDE-Aktivierung

Ziel: Den aktuell notwendigen Betriebsablauf nach einem SDE-Update oder
Same-Build-Neuimport unmissverständlich in der App anzeigen.

Entwicklung:

- im SDE-Panel einen dauerhaft sichtbaren, lokalisierten Warnhinweis ergänzt;
- denselben Hinweis in die Bestätigungsdialoge für Update und Neuimport
  aufgenommen;
- ausdrücklich festgehalten, dass die App vollständig beendet und neu geöffnet
  und danach die Main-Hub-Analyse erneut ausgeführt werden muss;
- Betriebs-, Handoff- und Acceptance-Dokumentation aktualisiert.

Ergebnis: Der notwendige Neustart wird vor der Aktivierung und dauerhaft im
SDE-Bereich sichtbar. Es wurde keine automatische Laufzeitumschaltung und keine
automatische Main-Hub-Analyse behauptet oder eingebaut.

Prüfung: Der fokussierte SDE-Lauf baute Core und App und bestand vier Tests.
Striktes Swift-Format, beide Lokalisierungs-Plists, doppelte
Lokalisierungsschlüssel, Suite-Links und Diff-Whitespace wurden geprüft. Die
visuelle und VoiceOver-Abnahme im laufenden Programm bleibt Owner-Evidence.

## 9. August 2026 – Build-Spalten, Blueprintkosten und LP-BPC-Filter

Ziel: Den verschobenen Spaltenkopf beim Öffnen von Build korrigieren und
Blueprintquellen in der Produktions- und Gewinnrechnung ehrlich abbilden,
ohne Filterwechsel mit erneuten Netzwerkabrufen zu koppeln.

Entwicklung:

- laufende Main-Hub-Chancen-Oberfläche auf dem entsperrten Mac geprüft und den
  angehefteten äußeren Opportunity-Kopf über dem abweichenden Build-Raster als
  sichtbare Ursache bestätigt;
- das äußere Pinning entfernt, sodass Opportunity- und Produktionsbaumkopf mit
  ihrem jeweiligen Spaltenschema scrollen;
- Public-Contract-DTO, SQLite-Schema und transaktionale Migration um offizielle
  BPC-Kennung, Runs, ME und TE erweitert;
- eine strikte Zurechnung für positive, aktive, exakte Main-Hub-Verträge mit
  genau einer angebotenen Blueprintposition, keiner angeforderten Position und
  vollständigen Blueprintdaten ergänzt;
- BPC-Vertragskosten automatisch in den ausgewählten Produktionsplan
  übernommen; BPO-Kauf, eigene BPC/BPO, Kopieren, Erfinden und LP-BPC verlangen
  eine ausdrückliche Planumlage beziehungsweise vollständige Erwerbskosten;
- vollständige Blueprintkosten zur Voraussetzung für Gesamtproduktionskosten
  und Gewinn des Build-Baums gemacht;
- einen manuell aktualisierbaren, lokal atomar gespeicherten LP-Shop-Snapshot
  ergänzt. Der NPC-Corporation-Abruf läuft sequenziell mit automatischer
  ESI-Priorität; anschließende kombinierte LP-/Faction-/Tech-/Produktfilter sind
  reine lokale Set-Operationen;
- Vertragskarten zeigen BPC/BPO, Runs, ME, TE und die sichere
  Zurechenbarkeit; neue deutsche und englische UI-Texte ergänzt.

Ergebnis: Filterwechsel lösen weiterhin keinen Markt-, SDE-, Contract- oder
LP-Abruf aus. Ein fehlender oder nicht sicher zurechenbarer Blueprintpreis kann
keinen künstlich hohen Gewinn mehr erzeugen. Alte Vertragszeilen bleiben nach
der Schemaerweiterung erhalten und werden erst nach ihrem normalen Detailabruf
mit Runs/ME/TE kalkulierbar.

Prüfung: Die fokussierten Public-Contract-Tests einschließlich App-Build
bestanden zunächst mit 19 Tests. Der anschließende vollständige isolierte
SwiftPM-Lauf bestand 305 Tests in 25 Suites einschließlich Runs/ME/TE-Decoding,
Bundle-Ausschluss, strikter Blueprintkosten und LP-Snapshot. Striktes
Swift-Format, beide Lokalisierungsdateien, doppelte Lokalisierungsschlüssel und
Diff-Whitespace bestanden. Der native unsigned Xcode-Debug-Build war
erfolgreich. Im daraus gestarteten deutschen Build wurden der lokale
LP-BPC-Filter samt manuellem Katalogabruf sowie der geöffnete Produktionsbaum
geprüft: Sein eigener Kopf `Schritt / Gegenstand` bis `Blueprint / Formel`
steht direkt über den Baumzeilen; der abweichende Opportunity-Kopf liegt nicht
mehr darüber. Eine Live-LP-Aktualisierung, VoiceOver-Abnahme und ein
Langzeit-CPU-/RSS-Lauf wurden dabei nicht behauptet.

Offen: ESI liefert bei LP-Angeboten keine BPC-Runs, ME oder TE. Bis eine
separat belegte Zuordnung existiert, bleibt der vollständige LP-ISK-Gegenwert
eine explizite Nutzereingabe. Die automatische Kombination mehrerer kleiner
BPC-Verträge zur Deckung einer Run-Menge ist noch nicht implementiert.

## 9. August 2026 – Vollständige Chancenwahl, ISK-Limit und Blueprint-Nachpflege

Ziel: Main-Hub- und experimentelle Produktauswahl auf realistisch finanzierbare
Materialeinkäufe begrenzen, die vollständige Gewinnrangfolge erreichbar machen
und Runs/ME/TE bestehender Blueprintverträge nachpflegen.

Entwicklung:

- ein gemeinsames persistiertes Limit für neues Wallet-Geld ergänzt; es zählt
  ausschließlich die Materialfehlmenge nach Warehouse, Schutzbestand und
  aktiven Reservierungen, während Lagerbestand seinen Wiederbeschaffungswert
  behält;
- Main-Hub-Chancen filtern dieses Limit aus bereits vorbereiteten
  Beschaffungswerten, ohne Kosten, Logistik und Sortierung erneut zu
  projizieren;
- das Geführte Produktionslabor von der festen Top-10-Grenze auf die
  vollständige Gewinnrangfolge in einer virtualisierten Scrollliste umgestellt
  und für seine große Auswahl einen allokationsgleichen Cash-only-Pfad ergänzt;
- Public-Contract-DTO, Store und UI übernehmen die offiziellen BPC/BPO-, Runs-,
  ME- und TE-Felder. Eine einmalige transaktionale Migration stellt vorhandene
  fertige Blueprintverträge erneut in die begrenzte Detailwarteschlange, behält
  ihre Itemzeilen aber bis zum atomaren Ersatz durch den Importer;
- deutsche und englische Filter-, Status- und Kostenhinweise sowie Architektur,
  Handoffs und Acceptance-Evidence aktualisiert.

Ergebnis: Ein 100-Millionen-ISK-Test reduzierte die lokale Main-Hub-Auswahl von
3.969 auf 3.458 Chancen; dieselben 3.458 Möglichkeiten waren im experimentellen
Bereich vollständig scrollbar. Das Testlimit wurde anschließend gelöscht.
Runs/ME/TE werden bei neuen Vertragsdetails direkt gespeichert; 27.356 ältere
Blueprintverträge wurden ohne Datenverlust zur Nachpflege vorgemerkt.
Nach dem lokalen Cached-Filter-Umbau fiel die gemessene Computer-Use-Aktionszeit
für dasselbe Limit von ungefähr 30 auf 6,9 Sekunden; dieser Wert enthält die
Automations- und Accessibility-Wartezeit und ist kein reines Core-Benchmark.

Prüfung: Der vollständige Live-LP-Abruf erreichte 283 von 283 NPC-Corporations
ohne Fehler und speicherte 2.964 angebotene Itemtypen. Der gestartete aktuelle
Build behielt nach der fortgesetzten Regionensynchronisierung 366.109
Contract-Itemzeilen; eine begrenzte Live-Fortsetzung füllte bereits für 978
Verträge beziehungsweise 6.875 Itemzeilen offizielle Blueprintdetails. Die
fokussierten 29 Market-Tests bestanden einschließlich Cash-only-Äquivalenz. Der
vollständige isolierte SwiftPM-Lauf bestand 308 Tests in 25 Suites; der native
unsigned Xcode-Debug-Build war erfolgreich.

Offen: Die große bestehende Blueprint-Detailwarteschlange ist nicht als
vollständig abgearbeitet behauptet. Reale Langzeit-CPU/RSS-, VoiceOver- und
In-game-Vergleiche repräsentativer LP-/BPC-Angebote bleiben Owner-Evidence.

## 9. August 2026 – CPU-Rückfall der öffentlichen Verträge korrigiert

Ziel: Den nach der Blueprint-Nachpflege erneut auftretenden CPU-Rückfall im
öffentlichen Vertragsindex beseitigen, ohne bestehende Vertragsdaten, echte
Fehlerzustände oder bereits geladene Runs/ME/TE zu verlieren.

Entwicklung:

- aktuelle Crashdiagnosen, den seit der letzten Stabilisierung geänderten
  Store-/Indexer-Pfad und die befüllte Produktionsdatenbank read-only geprüft;
- als neue Lastquelle die v1-Migration bestätigt, die sämtliche erkannten
  älteren Blueprintverträge in die normale ESI-Detailwarteschlange gestellt
  hatte;
- den unbeschränkten Bestandsabruf entfernt und eine einmalige transaktionale
  Reparatur ergänzt: Nur unberührte v1-Einträge mit vorhandenem Blueprintitem,
  ohne Itemfehler und weiterhin ohne Runs/ME/TE werden wieder `ready`;
- bereits erfolgreich aktualisierte Verträge sowie echte `pending`-Fehlerfälle
  bleiben unverändert; unbekannte alte Blueprintdetails bleiben ehrlich
  unbekannt;
- fokussierte Migrationsregression und Dokumentations-/Handoff-/Acceptance-
  Nachweise ergänzt.

Ergebnis: Die 93-MiB-Produktionsdatenbank enthielt read-only 49.204 Verträge,
368.542 Itemzeilen und 15.133 wartende Verträge. 15.132 davon entsprachen exakt
den unberührten v1-Nachpflegekandidaten; nur ein wartender Vertrag trug einen
echten Fehler. Der korrigierte Store startet für bestehende Blueprintzeilen
keinen Massenabruf mehr und repariert diese Kandidaten beim nächsten Öffnen,
ohne die Datenbank während dieser Diagnose vorab zu verändern. Nach dem
3. August lag kein neuer App-`.ips`-Bericht vor; belegt ist daher der neue
Dauerlastpfad, nicht ein neuer Crash-Stack.

Prüfung: Striktes Swift-Format für Store und Public-Contract-Tests bestand. Der
isolierte fokussierte Lauf baute App und Tests und bestand 23 Public-Contract-
Tests einschließlich der Unterscheidung zwischen unberührtem v1-Kandidaten und
echtem wartendem Fehlerfall. Der vollständige isolierte SwiftPM-Lauf bestand
310 Tests in 25 Suites; die unsigned native Xcode-Aktion bestand 296 Core-Tests
in 22 Suites. Die exakte Reparatur auf einer temporären SQLite-Sicherung behielt
368.542 Itemzeilen, ließ nur den einen echten Fehlerfall `pending` und bestand
`PRAGMA quick_check`. Suite-Links und Diff-Whitespace bestanden ebenfalls.

Offen: Der korrigierte Build muss gegen die befüllte Datenbank neu gestartet
und bis zum Idle-Zustand mit realer CPU/RSS-Messung beobachtet werden. Ein neuer
`.ips`-Bericht wäre weiterhin getrennt von einem CPU-bedingten UI-Stall oder
erzwungenen Beenden auszuwerten. Alte Zeilen ohne Runs/ME/TE bleiben bis zu
einem regulären neuen Detailimport unkalkulierbar.

## 9. August 2026 – Kombinierte Filter im Geführten Produktionslabor

Ziel: Die bereits im Main-Hub-Chancenbereich vorhandenen Produktfilter auch im
getrennten experimentellen Planungsweg verfügbar machen, ohne Berechnungsregeln
oder den etablierten Planner zu verändern.

Entwicklung:

- das Geführte Produktionslabor um exakte Kategorie-/Gruppenfilter,
  Produktfamilien, Tech I/II/III, Faction, Storyline,
  sonstige/nicht klassifizierte Produktion und Loyalty-Store-BPC erweitert;
- dieselbe lokale Filterkomposition auf den gespeicherten Main-Hub-Chancen und
  auf den Ergebnissen der aktiven SDE-Fertigungssuche angewendet;
- SDE-Suchergebnisse um faktische Blueprint-, Kategorie-, Gruppen-, Meta- und
  Tech-Metadaten ergänzt; fehlende Klassifikation bleibt ausdrücklich
  unbekannt/sonstig und wird nicht aus dem Namen geraten;
- Filterwechsel vom Netzwerk getrennt. Nur die vorhandene ausdrückliche
  LP-Katalogaktualisierung ruft ESI auf;
- deutsche und englische Zustände sowie Architektur, Handoff und
  Acceptance-Evidence aktualisiert.

Ergebnis: Der experimentelle Planer kann seine vollständige Gewinnrangfolge
jetzt mit denselben kombinierbaren fachlichen Kriterien wie die
Main-Hub-Chancen eingrenzen. Auswahl, ISK-Limit, Runs sowie die vorhandenen
Produktions- und Gewinnberechnungen bleiben unverändert und sitzungsgebunden.

Prüfung: 37 fokussierte Market-/SQLite-Tests und der vollständige SwiftPM-Lauf
mit 310 Tests in 25 Suites bestanden. Der unsigned native Xcode-Debug-Build war
erfolgreich. Im gestarteten deutschen Build zeigte die ungefilterte Auswahl
3.970 Möglichkeiten, **Schiffe + Faction** 113 und zusätzlich
**Loyalty Store BPC** 87; die Filter wechselten lokal und wurden danach
zurückgesetzt.

Offen: Repräsentative Faction-/LP-BPC-Ergebnisse müssen noch mit EVE verglichen
werden. Langzeit-CPU/RSS, Tastaturbedienung, VoiceOver und Owner-Abnahme bleiben
separate Nachweise.

## 9. August 2026 – Gemeinsame Chancenfilter und Tagesbedarfshistorie

Ziel: Die drei voneinander getrennten Bedienflächen im Main-Hub-Chancenbereich
zusammenführen und belastbare Tagesbedarfswerte über mehrere Tage erhalten,
ohne Produktions-, Kosten- oder Gewinnlogik inhaltlich zu verändern.

Entwicklung:

- die Reiter Einfaches Profil, Kostenschema und Erweiterte Filter durch eine
  gemeinsame, standardmäßig geöffnete und als Ganzes einklappbare Fläche mit
  acht adaptiven Karten ersetzt;
- Besitz, Baupläne, Produkt- und Produktionsfilter, Katalog-/Ergebnisfilter,
  Runs/ME/TE, Blueprintumlage und Materialeinkaufsgrenze an ihre bestehenden
  Zustände und Projektionen gebunden;
- das exakte Main-Hub-Nachfrage-Ledger auf Schema v4 erweitert und pro UTC-Tag
  den letzten gültigen Stand für höchstens 30 Tage erhalten;
- Vortag, Durchschnitt bekannter Tage, Anzahl belegter Tage und ungefähre
  Veränderung als eingefrorene Zeilenwerte ergänzt; fehlende Tage und Typen
  bleiben unbekannt statt null;
- die vollständigen Tageswörterbücher auf das kompakte Nachfrage-Ledger
  begrenzt, damit der große Chancen-Snapshot sie nicht dupliziert;
- deutsche und englische Darstellung sowie Architektur, Handoffs und
  Acceptance-Evidence aktualisiert.

Ergebnis: Alle Einstellungen des Main-Hub-Chancenbereichs sind im unveränderten
Menüweg gemeinsam erreichbar. Neue gültige Aktualisierungen bauen eine
faktische Tageshistorie auf; die bestehende aktuelle Tagesbedarfs- und
Gewinnrangfolge bleibt unverändert und nutzt weiterhin die rollierende
konservative Untergrenze.

Prüfung: Der fokussierte Market-Lauf bestand 32 Tests und der vollständige
SwiftPM-Lauf 312 Tests in 25 Suites. Der unsigned native Xcode-Debug-Build war
erfolgreich. Der finale deutsche Build lud den bestehenden Snapshot mit
3.970/3.970 Chancen, zeigte alle acht Kartengruppen gemeinsam, ließ die Fläche
ohne Ergebnisverlust ein- und wieder ausklappen und wies die noch leere
v4-Historie korrekt als `0 UTC-Tage` aus. Die dabei gefundene
Abwärtskompatibilitätslücke für alte Chancenzeilen wurde behoben, durch einen
eigenen Fixture-Test abgesichert und anschließend live bestätigt. Striktes
Format, beide Lokalisierungen, doppelte Schlüssel, Dokumentationslinks und
Diff-Whitespace bestanden.

Offen: Alte Ledger enthalten keine rekonstruierbaren früheren Tagesstände; ein
realer Vortagsvergleich erscheint erst nach gültigen Beobachtungen an
aufeinanderfolgenden UTC-Tagen. Mehrtägiger Live-Abgleich, Langzeit-CPU/RSS,
Tastatur, VoiceOver und Owner-Abnahme bleiben offen.

## 9. August 2026 – Programmweiter Code- und Performance-Audit

Ziel: Core, UI, Persistenz, ESI, SDE, Assets, Markt, Planner und Tests erneut
auf sichere Verschlankung und messbare Laufzeitverbesserungen prüfen, ohne
Funktionsumfang, Datenzustände oder CCP-/ESI-Sicherheitsregeln zu verändern.

Entwicklung:

- vor jeder Änderung ein vollständiges Archiv einschließlich `.git`,
  uncommittierter und unversionierter Dateien außerhalb des Projekts angelegt;
  das 212.613.263-Byte-Archiv enthält 11.001 Einträge und besitzt SHA-256
  `085bb5dc98b7811ae245b40ebc53e76abd482931f14475ca8dacda90be8d2908`;
- 111 Swift-/SQL-Dateien mit rund 82.000 Swift-Zeilen über Zielzugehörigkeit,
  Sichtbarkeit, modulweiten Referenzgraph, Compiler, Tests sowie bekannte
  Main-Actor-, Datenbank-, ESI- und Markt-Hotpaths geprüft;
- ausschließlich private oder modulinterne Deklarationen entfernt, die im
  vollständigen Ziel samt Tests nur an ihrer eigenen Deklaration vorkamen:
  darunter der abgeschaltete und nie instanziierte `LegacyProfilesView`, zwei
  ersetzte UI-Helfertypen sowie verwaiste Asset-, Profil-, Markt-, Planner- und
  Runtime-Helfer; implizit von `Codable` verwendete `CodingKeys` blieben
  ausdrücklich erhalten;
- die lokale Public-Contracts-SQLite-Verbindung wiederverwendet vorbereitete
  Schreibstatements und setzt Bindings nach jeder Ausführung zurück;
  Abfragespaltennamen werden einmal je Statement statt für jede Ergebniszeile
  erneut dekodiert;
- den einzigen `try!`-Pfad des Markt-Nachfrage-Ledgers durch einen
  `rethrows`-Vertrag ersetzt, sodass der nicht abbrechbare Aufruf ohne
  erzwungenen Fehlerausstieg bleibt und der Hintergrundpfad weiterhin
  kooperativ abbrechbar ist;
- aktuelle Laufzeitbeschreibung und Optimierungsplan ergänzt. Die 201
  Kommentarzeilen in den Swift-Quellen wurden nicht pauschal entfernt, weil sie
  gemessen kein Mengen- oder Laufzeitproblem darstellen und überwiegend
  Sicherheits-, Migrations- und Zustandsinvarianten erklären.

Ergebnis: Der identische isolierte Import von 10.000 synthetischen Verträgen
sank von 0,139462833 auf 0,059020959 Sekunden, also um rund 57,7 Prozent. Die
Optimierung betrifft die lokale Übernahme und Suche; ESI-Parallelität,
Abstände, Pagination, Cache, Retry, Fehlerbudget, WAL, Transaktionen und
unbekannte/partielle Zustände bleiben unverändert. Die erneute Referenzprüfung
findet keine weitere nur einmal vorkommende private Deklaration; die einzige
Ausnahme ist das für `Codable` notwendige `CodingKeys`.

Prüfung: Der unveränderte Ausgangsstand bestand 312 Tests in 25 Suites. Nach
der Änderung bestanden der vollständige isolierte SwiftPM-Lauf mit 313 Tests
in 25 Suites, das getrennte EVEStaticDataKit mit 6 Tests und die unsigned native
Xcode-Aktion mit 299 Core-Tests in 22 Suites (`** TEST SUCCEEDED **`). Der
10.000-Verträge-Test prüft neben der Zeit alle gespeicherten Zeilen. Striktes
Swift-Format der geänderten Swift-Dateien, `git diff --check` sowie statische
Suchen nach `try!`, `fatalError`, synchronem Main-Queue-Warten und blockierenden
Waits bestanden.

Offen: Die Messung ist synthetisch und isoliert. Ein vollständiger Live-ESI-
Erstimport, ein mehrstündiger Lauf mit befüllter Produktionsdatenbank und
Vorher-/Nachher-CPU/RSS, laufende UI-Reaktionszeit, Tastatur, VoiceOver sowie
Owner-Abnahme wurden nicht durchgeführt. SDE-Retention und jede Löschung alter
lokaler Kataloge bleiben Punkt 6 und benötigen weiterhin eine separate
Vorschau und Bestätigung.

## 9. August 2026 – Main-Hub-Schnellfilter und Erklärhilfen

Ziel: Die Main-Hub-Chancenoberfläche auf die für den Vergleich nötige
Run-Eingabe reduzieren, Chancen nach dem durchschnittlichen Tagesbedarf
schnell eingrenzen und Herkunft sowie Lesbarkeit aller zentralen Kennzahlen
erklären.

Entwicklung:

- ME und TE aus Szenariokarte und Chancentabelle entfernt; jeder manuelle oder
  automatische neue Chancenlauf normalisiert alte Einstellungen auf eine
  neutrale 0/0-Basis ohne Forschungsbonus, während konkrete Produktion und
  gespeicherte Altmodelle ihre ME-/TE-Verträge behalten;
- einen persistenten lokalen Mindestfilter für den bekannten mehrtägigen
  durchschnittlichen Tagesbedarf ergänzt; `0` ist aus, positive Schwellen
  schließen unbekannte Werte ausdrücklich aus;
- Klartext-Hoverhilfen für Besitz, Baupläne, Produkte, Produktionsklasse,
  Katalog, Ergebnis, Szenario und Kosten/Budget sowie genaue Formelhilfen für
  Tagesbedarf, Kosten, Erlös, Verkaufssteuer, Brokergebühr, Gewinn, tägliches
  Gewinnpotenzial, ROI, ISK/h und ISK/m³ ergänzt;
- Ganzzahlen und ISK-Werte im Chancenbereich an die gewählte App-Sprache
  gebunden und gruppiert; deutsche Anzeigen und Eingaben verwenden damit
  automatisch Punkte als Tausendertrennzeichen;
- deutsche und englische Lokalisierung, Domänentests und die laufende
  Dokumentation erweitert.

Ergebnis: Die Main-Hub-Chancen zeigen keine missverständliche ME-/TE-Gruppe
mehr. Runs bleiben die einzige Szenariogröße; der Tagesbedarfsdurchschnitt ist
sofort lokal filterbar, Beträge sind gruppiert lesbar und die Herkunft jeder
zentralen Wirtschaftskennzahl ist per Hover zugänglich.

Prüfung: Der isolierte fokussierte Market-Lauf bestand 34 Tests in einer Suite;
der vollständige isolierte SwiftPM-Lauf bestand 316 Tests in 25 Suites. Die
native, unsignierte macOS-Xcode-Testaktion bestand weitere 301 Tests in 22
Suites mit `** TEST SUCCEEDED **`. Striktes Swift-Format, beide
Lokalisierungsdateien, die Prüfung auf doppelte Lokalisierungsschlüssel sowie
der abschließende Diff-Whitespace-Check bestanden ebenfalls.

Offen: Live-ESI-Kompatibilität wurde durch diese lokale UI-/Projektionsänderung
nicht erneut geprüft. Laufende App, Hover-Verzögerung, Tastatur, VoiceOver und
Owner-Abnahme bleiben getrennte Nachweise.

## 10. August 2026 – Main-Hub-Zielstückzahl statt Ein-Run-Szenario

Ziel: Chancen und den zugehörigen Produktionsbaum nicht auf einen einzelnen
Run beschränken, sondern eine frei erhöhte Stückzahl des fertigen Produkts
kosten- und gewinnwirksam planen.

Entwicklung:

- die persistente Main-Hub-Szenarioeingabe von Runs auf eine positive,
  sprachabhängig gruppierte Zielstückzahl bis zur bestehenden Planner-Grenze
  von einer Milliarde Stück umgestellt;
- pro Produkt die nötigen vollständigen Blueprint-Runs mit Aufrundung aus der
  SDE-Ausgabemenge je Run abgeleitet und Ziel, Runs sowie tatsächliche Ausgabe
  getrennt gehalten;
- den aufgeklappten Produktionsbaum ebenfalls auf eine direkte Zielstückzahl
  umgestellt; er zeigt vor der Neuberechnung abgeleitete Runs und tatsächliche
  Ausgabemenge;
- Legacy-Snapshots bleiben dekodierbar, aber jeder neue manuelle oder
  automatische Main-Hub-Lauf verwirft den alten Run-Override und verwendet die
  Zielstückzahl mit der neutralen ME-/TE-Basis;
- deutsche und englische Erläuterungen, Domänentests, Architektur-, Handoff-
  und Anwenderdokumentation aktualisiert.

Ergebnis: Eine Zielstückzahl von beispielsweise `3` bei einer SDE-Ausgabe von
`2` je Run plant `2` Runs und `4` tatsächlich produzierte Stück. Materialien,
Installation, Dauer, beide Logistikwege, Erlös und Gesamtgewinn beziehen sich
auf diese vollständige Charge.

Prüfung: Der fokussierte isolierte Market-Lauf bestand 34 Tests in einer Suite.
Der vollständige isolierte SwiftPM-Lauf bestand 331 Swift-Testing-Tests in 25
Suites sowie zwei XCTest-Fälle. Die native, unsignierte macOS-Xcode-Testaktion
bestand 313 Tests in 22 Suites mit `** TEST SUCCEEDED **`. Striktes
Swift-Format, beide Lokalisierungsdateien, die Prüfung auf doppelte
Lokalisierungsschlüssel sowie der Diff-Whitespace-Check bestanden ebenfalls.

Offen: Eine laufende visuelle Prüfung der gruppierten Mengeneingabe, der
Stepper, der Batch-Überschussanzeige, Tastatur und VoiceOver sowie die
Owner-Abnahme wurden noch nicht durchgeführt. Live-ESI-Daten waren für diese
lokale Szenarioänderung nicht erforderlich und wurden nicht abgerufen.

## 9. August 2026 – Öffentliche Verträge außerhalb der Liste steuerbar

Ziel: Die minutenlang als blockierend erlebte Navigation in den Bereich
**Öffentliche Verträge** vermeiden, den mehrtägigen Erstimport ohne Öffnen der
Liste starten können und Fortschritt sowie sicheres Pausieren bei einem
Bereichswechsel erreichbar halten.

Entwicklung:

- eine dauerhaft sichtbare Contract-Steuerkarte in der Navigationsseitenleiste
  ergänzt; sie trennt Vorbereitung, Fehler mit Wiederholung, unvollständigen
  Erstimport, laufenden Hintergrundimport, sicheres Anhalten, geplante
  Fortsetzung und aktuellen Stand;
- Start/Fortsetzung und Pause aus dem Lebenszyklus der Vertragsansicht gelöst;
  die gemeinsame Runtime hält den resumierbaren Task, sodass ein Bereichswechsel
  ihn nicht beendet;
- auch ausdrücklich manuell gestartete mehrtägige Contract-Läufe nach dem Start
  auf Utility-Task- und begrenzte ESI-Hintergrundpriorität gelegt; Paging,
  zwei Detailworker, Request-Abstände, Cache, Retry, Fehlerbudget und sichere
  Teilzustände bleiben unverändert;
- einen sichtbaren Zustand für kooperatives Anhalten ergänzt und den roten
  Erstimporthinweis um freie Navigation sowie die Steuerung in der Seitenleiste
  erweitert;
- deutsche und englische Texte, Acceptance- und Handoff-Verträge aktualisiert.

Ergebnis: Der Contract-Import kann jetzt aus der Seitenleiste gestartet oder
fortgesetzt werden, ohne die Ergebnisliste zu öffnen. Während er läuft, bleiben
Fortschritt und Pause außerhalb des Detailbereichs erreichbar; der Import nutzt
die niedrig priorisierte Hintergrundspur und bleibt nach Navigation erhalten.

Prüfung: Der produktive 93-MiB-Contract-Store wurde ausschließlich lesend
geprüft: `quick_check = ok`, 114 Regionen, 49.193 Verträge, 358.045 Items,
11.241 Typen und 667 ausstehende Detailverträge. Die beiden Facet-Abfragen
benötigten zusammen rund 2,16 Sekunden und erklären damit keine minutenlange
Main-Thread-Sperre. Striktes Swift-Format und beide Lokalisierungskataloge
bestanden. Ein erster fokussierter SwiftPM-Lauf wurde durch eine zeitgleiche,
fremde Änderung an `MarketBrowserTests.swift` abgebrochen; nach stabilem Stand
bestanden 24 Public-Contracts-Tests, sieben Runtime-/UI-Zustandstests und der
vollständige SwiftPM-Lauf mit 316 Tests in 25 Suites.

Offen: Ein mehrstündiger Lauf der gebauten App mit aktivem Import, gemessener
Menüreaktionszeit, CPU/RSS, Tastatur, VoiceOver, Hell/Dunkel und ausdrücklicher
Owner-Abnahme bleibt erforderlich. Die vorhandene Produktionsdatenbank wurde
nicht verändert und es wurde kein Live-ESI-Import gestartet.

## 9. August 2026 – Lokale Vertragsaktualisierung blockiert die Oberfläche

Ziel: Den nach der ersten UI-Entkopplung erneut beobachteten vollständigen
Bedienverlust während eines laufenden Public-Contracts-Imports anhand der
Laufzeitdaten eingrenzen und die lokale Schreiblast sowie Stopp-Latenz senken.

Entwicklung:

- das bereitgestellte Xcode-Bild ausgewertet: etwa 103 Prozent CPU,
  268,8 MiB Speicher, 33,6 MiB/s Datenträger und 0 KB/s Netzwerk; der zufällige
  Stopp in `CFStringAppendFormat` mit `SIGTERM` ist ohne neuen `.ips`-Bericht
  kein belegter Crash-Stack und wurde nicht als Quellursache interpretiert;
- den produktiven Store erneut ausschließlich lesend geprüft: alle 114 Regionen
  waren frisch, 49.196 Contracts und 362.688 Items lagen vor, nur sechs
  Detailverträge waren noch ausstehend; der blockierende Lauf hatte somit
  fachlich weitergearbeitet und vor allem lokale Arbeit erzeugt;
- Contract-Upserts um einen nullsicheren Vergleich aller fachlichen Felder
  ergänzt, sodass ein identischer Vertrag nicht allein wegen eines neuen
  Beobachtungszeitpunkts erneut in SQLite und das WAL geschrieben wird;
- einen Revalidierungspfad ergänzt: Nur wenn jede Regionsseite mit
  `304 Not Modified` bestätigt wurde, werden ausschließlich Regionsfrische und
  nächste Abrufzeit aktualisiert. Der ESI-Transport bewahrt dabei die gecachte
  Seitenzahl, wenn eine 304-Antwort `X-Pages` auslässt;
- die transaktionalen Mengenloops prüfen vor Beginn und alle 128 Zeilen auf
  Abbruch; die offene Region wird bei Stopp zurückgerollt. Der Runtime-Task
  verwendet nun Background- statt Utility-Priorität. Paging, Abstände,
  Parallelitätsgrenzen, Retry, Fehlerbudget und unbekannte/partielle Zustände
  bleiben erhalten;
- laufende Dokumentation, Architektur, Acceptance und Handoffs aktualisiert.

Ergebnis: Unveränderte regionsweite Aktualisierungen erzeugen nicht mehr für jede
bereits bekannte Vertragszeile einen SQLite-Update. Eine echte 304-Bestätigung
schreibt überhaupt keine Contract- oder Itemzeile. Echte Änderungen und
Löschungen bleiben transaktional, lassen sich aber deutlich früher sicher
stoppen; die Arbeit konkurriert mit geringerer Systempriorität um CPU und I/O.

Prüfung: Die aktuelle offizielle ESI-Dokumentation bestätigt, dass eine 304 bei
passendem ETag unveränderte Daten bedeutet, `X-Pages` die Seitenzahl trägt und
`Last-Modified` bei einer paginierten Repräsentation konsistent sein soll. 66
fokussierte ESI-/Transporttests in drei Suites und 26 Public-Contracts-Tests
bestanden. Darunter belegen neue Fixtures den erhaltenen Seitenzähler nach 304,
die reine Regionsrevalidierung und das ausbleibende Update eines identischen
Contract-Datensatzes. Der isolierte 10.000-Contracts-Test benötigte rund
0,08 Sekunden. Der vollständige isolierte SwiftPM-Lauf baute Core und App und
bestand 319 Tests in 25 Suites. Striktes Swift-Format und Diff-Whitespace
bestanden.

Offen: Die geänderte App wurde noch nicht mit dem gefüllten Produktionsstore
gestartet. Reale Menüreaktionszeit, CPU/RSS, Datenträgerlast, Stopp-Latenz,
Tastatur, VoiceOver und ausdrückliche Owner-Abnahme bleiben getrennte
Laufzeitnachweise. Die vorhandene Produktionsdatenbank wurde nicht verändert.

## 9. August 2026 – Vertragssuche wartet auf das fertig getippte Wort

Ziel: Verhindern, dass die lokale Suche der öffentlichen Verträge bei normaler
Worteingabe nach fast jedem Buchstaben eine vollständige SQLite-Abfrage startet.

Entwicklung:

- den vorhandenen SwiftUI-Suchpfad geprüft: Die Suchidentität brach ältere
  Tasks korrekt ab, die Wartezeit von nur 250 Millisekunden lief zwischen
  normalen Tastendrücken jedoch häufig bereits ab;
- die Tipp-Pause auf 700 Millisekunden erhöht. Jede Änderung an Suchtext,
  Kategorie, Gruppe oder Vertragsseite erzeugt weiterhin eine neue Identität
  und bricht den wartenden vorherigen Task ab;
- die Eingabetaste als ausdrücklichen Sofortstart ergänzt. Der Auftrag friert
  Suchtext, Kategorie, Gruppe und Vertragsseite ein, statt diese Werte erst
  später erneut aus der View zu lesen;
- einen lokalisierten Bedienhinweis, eine deterministische Policy-Regression
  sowie Hauptdokumentation, Acceptance und Handoff ergänzt.

Ergebnis: Beim normalen Schreiben eines Worts läuft erst 700 Millisekunden nach
dem letzten Tastendruck eine Suche. Return sucht ohne Wartezeit. Bereits
laufende ältere Abfragen behalten den vorhandenen Generationenschutz und dürfen
neuere Ergebnisse nicht überschreiben.

Prüfung: Der fokussierte App-Lauf baute die App und bestand acht Runtime-/UI-
Zustandstests. Der vollständige isolierte SwiftPM-Lauf baute Core und App und
bestand 320 Tests in 25 Suites. Striktes Swift-Format, beide
Lokalisierungskataloge und Diff-Whitespace bestanden.

Offen: Reales Tippgefühl, Return-Fokus, VoiceOver und Owner-Abnahme wurden in
der laufenden App noch nicht geprüft. Es wurden keine Produktionsdaten und
keine ESI-Regeln verändert.

## 10. August 2026 – Rekursive Nachkalkulation vergessener Produktion

Ziel: Eine nicht oder nur teilweise getrackte EVE-Produktion nachträglich aus
fertigen Gegenständen und Mengen vollständig kalkulierbar machen.

Entwicklung:

- einen Parser für einfache `Gegenstand Menge`-Zeilen und vollständige
  tabulatorgetrennte EVE-Gegenstandszeilen ergänzt; deutsche EVE-Zahlen werden
  erkannt, Gruppe, angezeigtes Volumen und ungefährer ISK-Wert bleiben
  nicht-authoritative Referenz;
- einen eigenen etablierten Navigationsbereich **Rekursive Kalkulation**
  ergänzt, ohne Planner-Entwurf, aktiven Plan oder Produktionsübersicht zu
  verändern;
- alle herstellbaren Zwischenprodukte für diese Rekonstruktion ausdrücklich
  auf Produktion gesetzt, während faktischer Warehouse-Bestand, Schutzmengen
  und aktive Reservierungen weiterhin zuerst berücksichtigt werden;
- nach der ersten Graphauflösung pro normalem Blueprint-Bauschritt die manuelle
  Auswahl **BPC verwendet** oder **BPO verwendet** sowie vorhandene belegte
  Besitz-, Kopier-, Erfindungs-, Contract- und LP-Quellen angeboten. Verbrauchte
  BPC-/Aktivitätskosten und BPO-Umlagen werden ausdrücklich eingegeben;
  Reaktionen erhalten keine erfundene BPO/BPC-Auswahl;
- die Routen Main Hub → Home Hub und Main Hub → Home Hub → Main Hub über die
  vorhandenen Planner-Logistikregeln getrennt ausgewiesen; fehlende Blueprint-,
  Markt-, Volumen-, Tarif- oder Installationswerte bleiben unverfügbar;
- deutsche/englische Lokalisierung, Architektur, Handoff, Acceptance und
  Hauptdokumentation aktualisiert.

Ergebnis: Mehrere importierte Endprodukte werden als ein gemeinsames rekursives
Szenario berechnet. Gemeinsame Zwischenprodukte, Warehouse-Zuordnung,
Blueprintkosten und Logistik werden deshalb nicht als voneinander unabhängige
Einzelkalkulationen doppelt geschätzt. Der eingefügte ungefähre EVE-Wert wird
nicht als Kostenersatz verwendet.

Prüfung: Der fokussierte Importlauf baute Core und App und bestand 15 Tests.
Der vollständige isolierte SwiftPM-Lauf baute Core und App und bestand 325 Tests
in 25 Suites. Der native unsigned Xcode-Lauf bestand 309 Core-Tests in 22
Suites. Striktes Swift-Format, beide Lokalisierungskataloge, doppelte
Lokalisierungsschlüssel und Diff-Whitespace wurden geprüft.

Offen: Kein Live-ESI-Abruf, keine Produktionsdatenänderung und keine visuelle
Abnahme wurden durchgeführt. Vergleich mit tatsächlich vergessenen EVE-Jobs,
Home-Structure-Zugriff, große Mehrproduktlisten, CPU/RSS, Tastatur, VoiceOver,
helle/dunkle Darstellung und Owner-Abnahme bleiben getrennte Laufzeitnachweise.

### Nachtrag: Gruppenregeln für Blueprintquelle sowie ME/TE

Nach dem ersten Betriebshinweis wurde die Einzelkonfiguration reduziert:

- jeder produzierte Knoten behält nun SDE-Kategorie und SDE-Gruppe;
- oberhalb der einzelnen Blueprintzeilen lassen sich BPO/BPC sowie ME/TE für
  eine vollständige EVE-Gruppe setzen;
- ME/TE werden als produktbezogene `IndustryProductionEfficiency` in die
  erneute rekursive Planung gegeben und bleiben pro Blueprint überschreibbar;
- Reaktionen werden korrekt als Formeln ohne ME/TE behandelt. Die sichtbare,
  standardmäßig aktive Annahme „alle Reaktionsformeln vorhanden“ erzeugt eine
  ausdrückliche 0-ISK-Formelkostenallokation, lässt sich abschalten und ist
  keine aus Assets abgeleitete Besitzbehauptung;
- deutsche und englische Bedienungstexte sowie Architektur-, Handoff- und
  Acceptance-Dokumentation wurden entsprechend aktualisiert.

Prüfung: 16 fokussierte Production-Input-Tests und 21 fokussierte
Industry-Planner-Tests bestanden. Der vollständige isolierte SwiftPM-Lauf baute
Core und App und bestand 328 Tests in 25 Suites. Der native unsignierte
Xcode-Lauf baute die App und bestand 312 Core-Tests in 22 Suites. Striktes
Swift-Format, beide Lokalisierungsdateien, doppelte Lokalisierungsschlüssel,
Suite-Links und Diff-Whitespace wurden geprüft. Visuelle Bedienung, VoiceOver
und Owner-Abnahme bleiben offen.

### Nachtrag: Kontrollierte Übernahme ins Produktionsbuch

Ziel: Aus derselben rekursiven Nachkalkulation die fehlenden Zeilen des
Produktionsbuchs ergänzen, ohne aktuelle Marktwerte als historische Ist-Werte
auszugeben oder gemeinsame Kosten mehrfach anzusetzen.

Entwicklung:

- nach der Kalkulation eine zeilenweise Vorschau je importiertem Endprodukt mit
  Units, Runs, Produktionssystem, Material, Installation, Logistik,
  Blueprintkosten, Verkaufssteuer, Brokergebühr, Produktionskosten und
  Verkaufspreis ergänzt;
- die Route in einen unveränderlichen Produktionsbuch-Snapshot eingefroren:
  Main → Home verwendet Home-Hub-Listed-Preis und dortige Gebühren, Main → Home
  → Main verwendet Main-Hub-Listed-Preis und addiert die Rücklogistik der
  Endprodukte;
- gemeinsame Installations-, Blueprint- und Logistikkosten proportional zu den
  bekannten Materialwerten, ersatzweise gleichmäßig, genau einmal über die
  Endproduktzeilen verteilt; fehlende Werte bleiben unverfügbar;
- einen ausdrücklichen Bestätigungsdialog und eine Sitzungssperre gegen
  versehentliches erneutes Speichern desselben Kalkulationslaufs ergänzt;
- die SwiftData-Zeilen als eine Charge gespeichert; ein Speicherfehler löst ein
  Rollback der gesamten Charge aus;
- Bedienung und Snapshot-Herkunft ausdrücklich als Rekonstruktion mit aktuellem
  Markt- und Gebührenstand gekennzeichnet, nicht als historische Ist-Kosten;
- Core-, UI-, Persistenz-, Handoff-, Acceptance- und Hauptdokumentation sowie
  deutsche und englische Lokalisierung aktualisiert.

Ergebnis: Die rekursive Kalkulation kann jetzt nach Vorschau und Bestätigung
pro eingegebenem fertigem Gegenstand einen Produktionsbucheintrag erzeugen.
Der aktive Planner bleibt unangetastet; die vollständige Kalkulations- und
Preisprovenienz wird mit jeder Zeile eingefroren.

Prüfung: Acht fokussierte Production-Overview-Tests und acht fokussierte
Planner-Persistenztests bestanden. Der vollständige isolierte SwiftPM-Lauf
baute Core und App und bestand 331 Tests in 25 Suites. Der native unsignierte
Xcode-Lauf baute die App und bestand 313 Core-Tests in 22 Suites.
Swift-Format, beide Lokalisierungskataloge, doppelte Schlüssel und
Diff-Whitespace wurden geprüft.

Offen: Es wurden weder Live-ESI/Marktdaten neu verifiziert noch echte
Produktionsbuchzeilen geschrieben. Visuelle Prüfung der Vorschau und des
Bestätigungsdialogs, VoiceOver, große reale Mehrproduktlisten, Vergleich mit
tatsächlich vergessenen EVE-Jobs und Owner-Abnahme bleiben offen.

## 10. August 2026 – Kleine EVE-Itembilder vor aufgelösten Namen

Ziel: Aufgelöste Items in den verschiedenen Arbeitsbereichen schneller visuell
erkennbar machen, ohne Kopierverhalten oder unbekannte Datenzustände zu
verfälschen.

Entwicklung:

- mit `EVEItemIcon` und `EVEItemText` eine gemeinsame SwiftUI-Darstellung aus
  offizieller Type-ID-basierter Bildquelle und dem vorhandenen kopierbaren
  `EVEEntityText` ergänzt;
- kompakte Größen für Tabellen und Ticker, eine normale Zeilengröße sowie eine
  etwas größere Detailgröße festgelegt; Lade- und Fehlerfälle zeigen lokale
  neutrale Platzhalter, während der Itemname sichtbar bleibt;
- aufgelöste Items in Dashboard, Assets/Warehouse, Blueprints, Industry Jobs,
  Planner, Guided Production, Market Browser und Main-Hub-Chancen, Public
  Contracts, Reaktionen, Moon-Analyse, Net Worth und Produktionshistorie auf
  die gemeinsame Darstellung umgestellt; SDE-Sucher, Service-Module und Rigs
  zeigen das gleiche Type-Icon in ihren Auswahlzeilen;
- historische und importierte Namen ohne faktisch verfügbare Type-ID bewusst
  ohne geratenes Bild belassen; Persistenz-, SDE-, ESI- und Kalkulationslogik
  nicht verändert;
- den Darstellungsvertrag unter
  [`Documentation/ITEM_PRESENTATION.md`](Documentation/ITEM_PRESENTATION.md)
  sowie die aktuelle Hauptdokumentation ergänzt.

Ergebnis: In den zentralen Itemlisten und Detailansichten steht nun ein kleines,
noch erkennbares EVE-Type-Icon vor dem Namen. Der Name bleibt über die bestehende
gemeinsame Komponente kopierbar. Bildfehler löschen oder ersetzen keine
Fachdaten und eine fehlende Type-ID wird nicht aus dem Namen erraten.

Prüfung: Der fokussierte SwiftPM-Lauf baute `EVEStaticDataKit`, Core, die
vollständige App und die App-Tests; beide neuen URL-Vertragstests bestanden.
Anschließend bestand der vollständige SwiftPM-Lauf 325 Tests in 25 Suites. Der
erste fokussierte Lauf innerhalb der eingeschränkten Sandbox erreichte wegen
`sandbox_apply: Operation not permitted` noch keinen Manifest-Build; die
freigegebene Wiederholung mit isoliertem Scratch- und Modulcache war
erfolgreich. Die verwendete Type-Icon-Route und die 64-Pixel-Größe wurden mit
der aktuellen offiziellen EVE-Image-Server-Dokumentation abgeglichen.

Eine isoliert gebaute App-Vorschau wurde im dunklen Erscheinungsbild mit den
vorhandenen Dashboard- und Main-Hub-Daten geprüft. Die unterschiedlichen
Itembilder wurden kompakt und erkennbar vor den Namen geladen; Kopier-Buttons,
Zeilenhöhen und Tabellenspalten blieben visuell intakt. Die Vorschau löste
keine manuelle Datenaktualisierung aus.

Offen: Langzeit-CDN-/Cache-Verhalten, Offline- und Fehlerfall, große scrollende
Listen, PNG-Export der Moon-Tabelle, das helle Erscheinungsbild, Tastatur,
VoiceOver und ausdrückliche Owner-Abnahme bleiben getrennte Nachweise.

## 10. August 2026 – Lesbare und angeheftete Main-Hub-Kalkulationsspalten

Ziel: Die optisch zusammenlaufenden Kennzahlen am rechten Rand der
Main-Hub-Kalkulation trennen und die Spaltenüberschriften beim vertikalen
Scrollen dauerhaft sichtbar halten.

Entwicklung:

- zwischen **ISK/h**, **ISK/m³** und **Gruppe** denselben zusätzlichen Abstand
  in Kopf und Datenzeilen ergänzt, sodass Spaltenausrichtung und Sortierziele
  erhalten bleiben;
- den sortierbaren Opportunity-Kopf als native angeheftete Section-Kopfzeile
  aktiviert und mit einem deckenden Hintergrund sowie einer unteren Trennlinie
  versehen;
- den abweichenden lokalen Spaltenkopf des aufgeklappten Build-Baums
  unverändert erhalten; Kalkulation, Sortierwerte, Persistenz und ESI-Verhalten
  wurden nicht geändert;
- die aktuelle Hauptdokumentation an das neue Scrollverhalten angepasst.

Ergebnis: Die drei zuvor schwer unterscheidbaren Spalten sind visuell getrennt.
Beim vertikalen Scrollen bleiben alle anklickbaren Kalkulationsüberschriften
sichtbar und behalten ihre auf-/absteigende Sortierung.

Prüfung: `swift format lint --strict` für die geänderte View und
`git diff --check` bestanden. Der isolierte SwiftPM-Lauf baute Core und die
vollständige App; zunächst bestanden zwei fokussierte App-Tests, anschließend
die vollständige Suite mit 325 Tests in 25 Suites.

Offen: Die visuelle Prüfung in der laufenden App, helle/dunkle Darstellung,
Tastatur, VoiceOver und ausdrückliche Owner-Abnahme bleiben getrennte
Laufzeitnachweise.

## 10. August 2026 – Falsche Produktbilder im Produktionsbuch korrigiert

Ziel: Die im Planner-Produktionsbuch sichtbaren Icons müssen zum gespeicherten
Fertigprodukt gehören und dürfen nicht von einem Material- oder
Zwischenzustandsknoten derselben Planung stammen.

Entwicklung:

- die Type-ID-Auflösung der historischen Zeile auf den letzten produzierenden
  Top-Level-Knoten der zugehörigen Anfrage eingeschränkt;
- die zuvor verwendete erste beliebige Knotenübereinstimmung entfernt, weil sie
  auch Kauf-, Lager- oder Materialknoten auswählen konnte;
- einen Regressionstest mit einem früheren Materialknoten und einem späteren
  produzierten Endprodukt ergänzt;
- Hauptdokumentation und Item-Darstellungsvertrag an die korrigierte fachliche
  Zuordnung angepasst.

Ergebnis: Das Produktionsbuch verwendet für das Bild dieselbe fachliche
Endproduktwahl wie Projektion und Aufzeichnung. Fehlt ein produzierender
Top-Level-Knoten, bleibt das Bild weiterhin bewusst aus, statt eine Type-ID zu
raten.

Prüfung: Der fokussierte Regressionstest bestand. Der vollständige isolierte
SwiftPM-Lauf baute Core und App und bestand 329 Tests in 25 Suites; der native
unsigned macOS-Xcode-Build war erfolgreich. Striktes Swift-Format und
Diff-Whitespace bestanden. Der erste Sandbox-Buildversuch scheiterte nur an
geschützten SwiftPM-/Xcode-Caches; die freigegebenen Wiederholungen mit
isolierten Caches waren erfolgreich.

Eine separat gebaute App-Vorschau wurde im dunklen Erscheinungsbild mit den
fünf vorhandenen historischen Zeilen Avalanche, Orca, salvation, Nomad und bane
geprüft. Alle fünf zeigten nun unterschiedliche, zum jeweiligen produzierten
Endprodukt gehörende Schiffsbilder; Namen, Zeilenhöhe und Tabellenspalten
blieben intakt. Es wurde keine manuelle Aktualisierung ausgelöst.

Offen: Weitere ältere Produktionsstände, das helle Erscheinungsbild, Tastatur,
VoiceOver und ausdrückliche Owner-Abnahme bleiben getrennte Nachweise.

## 11. August 2026 – Kompakte Main-Hub-Filter mit Klickerklärungen

Ziel: Den oberen Main-Hub-Chancenbereich platzsparend in einer Kartenreihe
ordnen, unklare Bauplanfilter erklären und den langen Text unter der
Gegenstandssuche einklappbar machen.

Entwicklung:

- die bisher adaptiv auf mehrere Zeilen umbrechenden Filterkarten durch sieben
  feste Karten in einer horizontal scrollbaren Reihe ersetzt;
- die separate Szenariokarte entfernt und ihre fachlich wirksame Zielmenge als
  kompaktes, erklärbares Feld direkt in den Kalkulatorkopf verschoben, damit
  keine unsichtbare Einstellung die Ergebnisse beeinflusst;
- **Besitz** in **Bauplanbesitz** und **Baupläne** in **Bauplantyp und -quelle**
  präzisiert; Corporation-Hangars dem Besitz und LP-BPCs der Quelle zugeordnet,
  Favoriten in den Ergebnisfilter verschoben;
- jede Kartenüberschrift samt Informationssymbol als vollständige Schaltfläche
  mit ausführlichem, markierbarem Popover umgesetzt. Persönlich, Corporation,
  Nicht im Besitz, Unbekannt, BPO/BPC-Grenzen, LP-Katalog, UND-/ODER-Verknüpfung,
  lokale Filterwirkung und Kostenfolgen werden ausdrücklich beschrieben;
- relevante gelbe Ausrufezeichen für fehlende Produktionsklassenmetadaten sowie
  ungültige Blueprint- oder Materialbudgetbeträge ebenfalls anklickbar gemacht;
- Datengrundlage und längere Erklärung unter der Gegenstandssuche in eine
  persistent ein-/ausklappbare Gruppe verschoben. Fachliche Fehler und
  Warnungen bleiben außerhalb immer sichtbar;
- Main-Hub- und einzelner Produktionsortname innerhalb der Datengrundlage auf
  die gemeinsame kopierbare EVE-Namensdarstellung umgestellt sowie deutsche und
  englische Lokalisierung und Hauptdokumentation aktualisiert.

Ergebnis: Die Filter benötigen nur noch eine Kartenzeile. Ihre Wirkung ist per
Klick statt nur per Hover nachvollziehbar, während die Kalkulationszielmenge am
inhaltlich passenden Ort bleibt und der lange Sucherklärungstext dauerhaft
weggeklappt werden kann.

Prüfung: Striktes Swift-Format, beide Lokalisierungs-Plists, doppelte
Lokalisierungsschlüssel und Diff-Whitespace bestanden. Der isolierte
SwiftPM-Lauf baute Core und die vollständige App; zwei fokussierte App-Tests
und anschließend alle 331 Swift-Testing-Tests in 25 Suites bestanden.

Offen: Horizontales Scrollgefühl, Popoverpositionen, schmale und breite
Fenstergrößen, helle/dunkle Darstellung, Tastatur, VoiceOver und ausdrückliche
Owner-Abnahme bleiben getrennte Laufzeitnachweise.

## 11. August 2026 – Leere Main-Hub-Ansicht nach Tabellenaufbau korrigiert

Ziel: Verhindern, dass der Main-Hub-Chancenbereich nach dem kurzen
Vorbereitungszustand vollständig leer gezeichnet wird, obwohl Daten und
Accessibility-Hierarchie weiterhin vorhanden sind.

Ursache und Entwicklung:

- der Fehler wurde mit dem produktiv gefüllten Snapshot reproduziert: Nach dem
  Aufbau von 2.443 sichtbaren Kandidaten blieb der vollständige Accessibility-
  Baum erhalten, während AppKit nur leere Split-View-Flächen zeichnete;
- die gleichzeitig sichtbaren `tcp_input`-Reset-Zeilen waren nicht ursächlich.
  Das Systemprotokoll zeigte danach erfolgreiche HTTP-200-Anfragen, aber auch
  AppKit-Faults für negative Breiten und Höhen;
- die tatsächliche Überlastung entstand, weil der aufgeklappte Filter- und
  Erklärbereich zusammen mit festen Mindesthöhen des nativen vertikalen
  Split Views mehr Höhe verlangte, als das Fenster bereitstellte. Der
  Kalkulator erhielt dadurch während des dynamischen Wechsels eine ungültige
  Restgeometrie;
- Filter, Status und Datengrundlage liegen jetzt in einem eigenen vertikalen
  Scrollbereich mit einer endlichen, aus der Fensterhöhe abgeleiteten
  Obergrenze. Der Kalkulator behält deshalb stets eine gültige Restfläche;
- Kalkulator und Workbench sowie die beiden unteren Workbench-Spalten werden
  ohne native Split Views anhand endlicher Viewport-Werte deterministisch
  geteilt. Unvereinbare Mindesthöhen und Mindestbreiten entfallen;
- den zweiachsigen Tabellen-`ScrollView` mit angeheftetem Lazy-Section-Kopf
  durch getrennte Achsen ersetzt: außen horizontal, innen vertikal. Der Kopf
  liegt außerhalb des vertikalen Zeilenscrollers und bleibt trotzdem
  horizontal spaltensynchron;
- vorgeschlagene nicht endliche oder negative Viewport-Längen werden auf null
  begrenzt, bevor AppKit sie erhält;
- die kleine horizontale Filterkartenzeile verwendet nun einen normal
  vermessenen, vertikal fest auf seinen Inhalt begrenzten `HStack` statt einer
  trägen, vertikal flexiblen Zeile.

Ergebnis: Der Main-Hub-Chancenbereich bleibt nach dem Aufbau des gefüllten
Snapshots sichtbar. Der Tabellenkopf bleibt beim vertikalen Scrollen sichtbar,
ohne die frühere Kombination aus zweiachsigem Scrollen, angehefteter Section
und unvereinbaren Split-View-Mindestgrößen. Fachwerte, Filterzustände,
Sortierung, gespeicherte Snapshots und ESI-Verhalten wurden nicht verändert.

Prüfung: Der isolierte SwiftPM-Lauf baute Core und die vollständige App. Sechs
fokussierte App-XCTest-Fälle einschließlich negativer, nicht endlicher, sehr
kleiner und gültiger Seiten-, Tabellen-, Workspace- und Workbench-Geometrien
sowie anschließend alle 331 Swift-Testing-Tests in 25 Suites bestanden. Das
isolierte native Xcode-Bundle baute erfolgreich. Mit dem vollständigen lokalen
Snapshot wurden 2.443 von 3.971 Kandidaten sichtbar gezeichnet; drei weitere
Wechsel Dashboard → Main-Hub-Chancen blieben sichtbar. Der Tabellenkopf war
am Anfang und nach `AXScrollToBottom` weiterhin vorhanden. Striktes
Swift-Format und `git diff --check` bestanden. Das System protokolliert während
des Navigationswechsels weiterhin kurz AppKit-Hinweise auf negative Geometrie,
der zuvor daran anschließende leere Renderzustand trat in diesen Läufen jedoch
nicht mehr auf; diese verbliebene Framework-Diagnostik wird deshalb nicht als
vollständig beseitigt dargestellt.

Offen: Die ausdrückliche Owner-Abnahme bleibt nach der automatisierten und
lokalen Laufzeitprüfung getrennt.

## 11. August 2026 – Einzelne Runs und adaptive Main-Hub-Fläche

Ziel: Die globale Zielmenge durch eine zeilenbezogene Run-Eingabe ersetzen,
unnötige Bauplanfilter vorläufig entfernen und den Kalkulator beim Einklappen
der oberen Bereiche automatisch vergrößern.

Entwicklung:

- die globale Zielmengeneingabe aus dem Main-Hub-Kalkulator entfernt und die
  vorhandene Spalte **Runs** je Gegenstand editierbar gemacht;
- eine getrennte Run-Projektion ergänzt, die nur den geänderten Kandidaten aus
  dem gespeicherten Szenario neu berechnet. Sie skaliert Ausgabe, Material,
  Dauer, Installation, Erlös und Gebühren, berechnet anschließend Beschaffung,
  Logistik und Kosten dieser Zeile neu und kennzeichnet die Wiederverwendung
  der erfassten gewichteten Stückpreise ausdrücklich;
- Run-Overrides bewusst nicht in den Trigger der vollständigen
  Kandidatenvorbereitung aufgenommen und bei einem neuen Chancen-Snapshot
  verworfen;
- Bauplanbesitz, Bauplantyp/-quelle und LP-BPC-Quelle aus sichtbaren Filtern und
  Main-Hub-Kandidatenprojektion entfernt, ohne die zugrunde liegenden Daten oder
  andere Programmabläufe zu löschen;
- Favoriten in eine eigene Karte direkt unter den Produktionsklassen verschoben
  und die übrigen Filterkarten in ein breitenadaptives Raster ohne horizontalen
  Kartenscroller gesetzt;
- die Höhe des oberen Filter-/Datengrundlagenbereichs an beide
  Aufklappzustände gebunden, sodass der Kalkulator den frei werdenden Platz
  unmittelbar übernimmt;
- deutsche und englische Texte, Domänen- und Layouttests sowie die laufende
  Dokumentation aktualisiert.

Ergebnis: Eine Run-Änderung betrifft nur das gewählte Item; andere vorbereitete
Chancen werden nicht erneut berechnet. Die Filter nutzen die Fensterbreite,
Favoriten sind fachlich getrennt, und eingeklappte obere Bereiche geben ihre
Höhe an den Kalkulator zurück.

Prüfung: Der isolierte fokussierte Market-Lauf bestand 36 Tests; sieben
fokussierte App-Layout-/Darstellungstests bestanden ebenfalls. Der vollständige
isolierte SwiftPM-Lauf bestand 333 Swift-Testing-Tests in 25 Suites sowie sieben
XCTest-Fälle. Der native, unsignierte Xcode-Build war erfolgreich. Striktes
Swift-Format, beide Lokalisierungs-Plists, doppelte Lokalisierungsschlüssel und
`git diff --check` bestanden.

Das isolierte Xcode-Bundle wurde mit dem vorhandenen vollständigen Snapshot
visuell geprüft: Bauplanbesitz und Bauplantyp/-quelle waren nicht mehr
vorhanden; Favoriten stand direkt unter Produktionsklasse; die Karten brachen
breitenadaptiv ohne eigenen horizontalen Kartenscroller um. Nach dem Einklappen
von Filter und Datengrundlage dockte der Kalkulator unmittelbar oben an. Beim
ersten Kandidaten änderte die Eingabe von einem auf zwei Runs nur diese Zeile:
Menge `200 → 400`, Dauer `38 Min. → 1 Std., 15 Min.`, Kosten `228.950 →
457.901 ISK` und Erlös `2.448.000 → 4.896.000 ISK`; die Kandidatenzahl blieb
`2.446 / 3.971`, die folgenden Run-Felder und Zeilenwerte unverändert. Das
Informationssymbol zur Preis-Snapshot-Grenze war sichtbar und zugänglich.

Offen: Aktuelle Markttiefe wird absichtlich erst durch **Aktualisieren**
geladen. Live-ESI-Prüfung und ausdrückliche Owner-Abnahme bleiben getrennt.

## 11. August 2026 – Eine Runs-Quelle und standortgenaue Blaupausen

Ziel: Die zweite Zielmenge im Produktionsbaum beseitigen und eigene
BPCs/BPOs beziehungsweise öffentliche BPC-Verträge für genau die im
Kalkulator gewählten Runs auswerten.

Entwicklung:

- die editierbaren Runs der Kalkulatorzeile zur einzigen Mengenquelle für den
  zugehörigen Produktionsbaum gemacht; der Baum übernimmt die vollständige
  Ausgabe automatisch und wird bei einer Run-Änderung nur für dieses Item
  verzögert neu geladen;
- das tägliche Gewinnpotenzial auf die verkaufbare Menge der gewählten Charge
  begrenzt: ausreichender Tagesbedarf ergibt höchstens den Chargengewinn,
  geringerer Bedarf reduziert ihn proportional;
- die Blueprint-Bestände weiterhin aus den persönlichen, auch vom
  Blaupausenbereich verwendeten Snapshots gelesen, aber auswählbare BPCs/BPOs
  auf frische Quellen und den eindeutig passenden Produktionsort begrenzt;
- mehrere eigene BPCs am richtigen Ort als gemeinsame Run-Abdeckung
  zugelassen und Charaktere, Kopien, verfügbare Runs und Standort in Auswahl
  und Hilfe sichtbar gemacht;
- einen begrenzten deterministischen Vertragsselektor ergänzt, der nur exakt
  zuordenbare Main-Hub-Einzel-BPC-Verträge verwendet, mehrere Verträge bis zur
  benötigten Run-Zahl kombinieren kann und deren vollständige Preise in die
  strikte Planrechnung übernimmt; Bündel und unvollständige Details bleiben
  ausgeschlossen;
- ungültig gewordene Blueprint-Auswahlen nach einer Mengenänderung auf die
  aktuelle belegte Empfehlung zurückgeführt sowie Lokalisierung, Verträge,
  Tests und laufende Dokumentation aktualisiert.

Ergebnis: Kalkulator und Produktionsbaum verwenden dieselben Runs. Eigene
Blaupausen an anderen oder nicht eindeutig zugeordneten Orten erscheinen nicht
als verfügbar; mehrere passende BPCs oder mehrere eindeutige BPC-Verträge
können die angeforderte Run-Zahl gemeinsam decken. Unbekannte BPC-/BPO-Kosten
bleiben ausdrücklich unverfügbar, sofern sie nicht aus eindeutigen Verträgen
oder einer manuellen Umlage stammen.

Prüfung: Der fokussierte isolierte Market-Lauf bestand 36 Tests und der
fokussierte Industry-Lauf 22 Tests. Der vollständige isolierte SwiftPM-Lauf
bestand 334 Swift-Testing-Tests in 25 Suites sowie sieben XCTest-Fälle.
Striktes Swift-Format, beide Lokalisierungs-Plists, doppelte
Lokalisierungsschlüssel und `git diff --check` bestanden. Der native,
unsignierte macOS-Xcode-Build endete mit `** BUILD SUCCEEDED **`.

Offen: Live-ESI-Vertragsangebote, eine visuelle Prüfung mit realen
Charakter-BPCs/BPOs, VoiceOver und ausdrückliche Owner-Abnahme bleiben
getrennte Nachweise. Eine einzelne konkrete BPC-Instanz wird noch nicht als
persistente Reservierung verbucht; die Auswahl gilt für die geöffnete Sitzung.

## 11. August 2026 – Persistente Chancenfilter und erklärbarer BPO-Standort

Ziel: Die zuletzt verwendeten Main-Hub-Chancenfilter nach einem Neustart
beibehalten und einen vorhandenen, aber nicht auswählbaren BPO/BPC-Bestand
verständlich auflösen.

Entwicklung:

- Suchtext, Produkt- und Produktionsklassen, Favoritenmodus, Kategorie, Gruppe,
  Ergebnisfilter und Filter-Aufklappzustand in der bestehenden lokalen
  App-Defaults-Domäne gespeichert; Tagesbedarf und Materialbudget waren dort
  bereits persistent;
- leere Mehrfachauswahlen als echten gespeicherten Zustand von einer noch nicht
  vorhandenen Einstellung unterschieden und veraltete exakte Kategorie- oder
  Gruppenauswahlen erst nach Laden eines neuen Snapshots gezielt verworfen;
- konkrete beibehaltene Blueprintinstanzen aus frischen, teilweisen oder
  veralteten Quellen wieder auswählbar gemacht, ohne einen nicht-frischen
  Gesamtbestand als vollständig auszugeben;
- den Standort einer Blueprintinstanz über ihren Asset-Wurzelstandort
  aufgelöst, damit BPOs/BPCs in Containern am exakten Produktionsort nicht mehr
  fälschlich herausfallen;
- BPOs und BPCs an anderen Standorten getrennt gezählt und den generischen
  Status **ungeklärt** in diesem Fall durch **Eigenes BPO/BPC an einem anderen
  Standort** samt Verschiebe- und Aktualisierungshinweis ersetzt;
- deutsche und englische Texte, fokussierte Regressionstests und die laufende
  Dokumentation ergänzt.

Ergebnis: Die Main-Hub-Filter stellen den letzten lokalen Zustand wieder her.
Eine faktisch gespeicherte Blaupause am exakten Standort bleibt auch als
gekennzeichneter letzter Bestand auswählbar; ein BPO an einem anderen Standort
wird nicht fälschlich verwendbar, erklärt aber jetzt unmittelbar den nötigen
nächsten Schritt. Die schreibgeschützte Prüfung des aktuellen lokalen Bestands
bestätigte frische Blueprintquellen und für den naheliegenden Industrial-Fall
einen vom konfigurierten Fertigungsstandort abweichenden BPO-Standort.

Prüfung: Der fokussierte isolierte Industry-Lauf bestand 23 Tests einschließlich
der neuen Regression für ein veraltetes BPO in einem Container am exakten
Produktionsstandort. Der vollständige isolierte SwiftPM-Lauf bestand 335
Swift-Testing-Tests in 25 Suites sowie sieben XCTest-Fälle. Der native,
unsignierte macOS-Xcode-Build endete mit `** BUILD SUCCEEDED **`; beide
Lokalisierungsdateien und `git diff --check` bestanden. Striktes Swift-Format
wurde für die drei geänderten Swift-Dateien geprüft.

Offen: Die visuelle Prüfung der wiederhergestellten Filter und der neuen
Standortmeldung, VoiceOver, ein erneuter Live-ESI-Abgleich sowie die ausdrückliche
Owner-Abnahme bleiben manuelle Nachweise. Eine Blaupause muss nach einem
tatsächlichen Standortwechsel weiterhin über Blaupausen und Besitz aktualisiert
werden.

## 2026-08-13 – Drei-Hub-Verkaufsstrategien und Direkthandel im Planner

Ziel: Die Produktionskosten sollten wieder klar von Lagerverbrauch und
Verkaufswegen getrennt werden. Main-, Home- und Koalitions-Hub sollten jeweils
fachlich passende Marktgebühren und Logistikketten erhalten; Home und Coalition
zusätzlich einen gebührenfreien Direkthandel.

Entwicklung:

- vor der Änderung den vollständigen Checkout einschließlich der vorhandenen
  gemischten Nutzeränderungen als
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-planner-before.tar.gz`
  gesichert und das Archivverzeichnis lesend geprüft;
- `IndustryPlanningContext` und `IndustryPlanSnapshot` um einen getrennten
  Coalition-Marktsnapshot sowie Home-/Coalition-Direkthandel erweitert;
- Main-, Home- und Coalition-Marktwerte parallel und ortsgebunden geladen;
  fehlender oder verbotener Zugriff auf einen sekundären Hub lässt nur dessen
  Strategien unverfügbar;
- den bestehenden Preisvertrag um `directTrade` ergänzt: niedrigster aktueller
  Sell-Order-Preis des exakten Hubs als Referenz, ohne Markttiefenverbrauch,
  EVE-Markt-Verkaufssteuer oder Markt-Brokergebühr;
- Sofortverkauf weiterhin aus vollständig gedeckter Buy-Order-Tiefe mit
  Verkaufssteuer und 0 Brokergebühr berechnet; eingestellten Verkauf weiterhin
  aus dem niedrigsten Sell-Order-Preis mit Verkaufssteuer und Brokergebühr;
  für die ESI-Region `10001004` wird dabei CCPs zusätzlicher Exordium-Aufschlag
  von 5 % auf nicht sofort ausgeführte Orders eingerechnet und durch einen
  eigenen deterministischen Gebühren-Test abgesichert;
- Produktionskosten unverändert aus vollständigem Main-Hub-Materialersatzwert,
  BPC/BPO, Installation und eingehender Materiallogistik gebildet. Main-Verkauf
  ergänzt die Fertigproduktlogistik zurück zum Main Hub, Coalition-Marktverkauf
  die Route zur Coalition-Struktur; Home-Verkauf und beide Direkthandel-Fälle
  ergänzen keine Fertigproduktlogistik;
- Planner-Layout so geordnet, dass Lagerverbrauch direkt unter Kosten steht.
  Verkaufssteuer und Brokergebühr erscheinen genau einmal in der jeweiligen
  Strategiekarte; das doppelte Sammelfeld wurde entfernt;
- deutsche und englische Texte sowie `dokumentation.md`,
  `Documentation/PRODUCTION_BASIS.md`, `Documentation/HANDOFFS.md` und
  `Documentation/ACCEPTANCE.md` aktualisiert.

Ergebnis: Der etablierte Planner zeigt Sofortverkauf und eingestellten Verkauf
am Main Hub sowie Sofortverkauf, eingestellten Verkauf und Direkthandel am Home
und Coalition Hub mit der jeweils zutreffenden Kosten-, Logistik- und
Gebührenzusammensetzung. Unbekannte Markt-, Tarif-, Volumen- oder
Zugriffsinformationen bleiben unbekannt; vertragsspezifische Kosten werden nicht
erfunden.

Prüfung: Das App- und App-Testziel kompilierten im isolierten SwiftPM-Build.
Fokussiert bestanden 23 Industry-, 16 Market-Pricing- und 8
Production-Overview-Tests. Der abschließende vollständige isolierte
SwiftPM-Lauf bestand 337 Swift-Testing-Tests in 25 Suites sowie 7 XCTest-Fälle,
einschließlich des neuen Exordium-Gebührentests. Striktes Swift-Format,
beide Lokalisierungskataloge, Duplikatprüfung und `git diff --check` bestanden.
Ein erster Build im gemeinsam genutzten `.build` wurde wegen einer während des
Linkens veränderten vorhandenen Objektdatei verworfen; der danach vollständig
isolierte Scratch-Build lief sauber. Zwei native, unsignierte Xcode-Versuche
blieben bereits in der lokalen Paketauflösung bei 0 Prozent CPU stehen und
legten kein DerivedData an, auch mit deaktivierter Paketaktualisierung; sie
wurden kontrolliert beendet und nicht als Build-Nachweis gewertet.

Offen: Live ESI/Player-Structure-Zugriff, Abgleich realer Händlergebühren und
Hauling-Tarife, Vertragspreis-/Vertragskostenentscheidung, visuelles Layout,
Tastatur, VoiceOver und ausdrückliche Owner-Abnahme.

## 2026-08-13 – Vertragsreferenz, Routenstatus und Capital-Grenzen

Ziel: Der Direkthandel sollte reale öffentliche Verträge statt Marktorders als
Vergleich verwenden und seine feste Vertragsgebühr berücksichtigen. Jede
Verkaufsstrategie sollte beide Transportrichtungen sichtbar bewerten; zu große
oder im Highsec unzulässige Produkte durften dabei nicht als kostenlos gelten.

Entwicklung:

- vor der Änderung den vollständigen Checkout einschließlich der vorhandenen
  gemischten Nutzeränderungen in
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-direct-trade-before.tar.gz`
  gesichert und das Archivverzeichnis lesend geprüft;
- einen vollständigkeitsgebundenen `PublicContractReferenceSnapshot` ergänzt,
  der nur exakte, öffentliche Item-Exchange-Angebote mit einem angebotenen Typ,
  ohne angeforderte Position und mit positivem Preis zulässt und nach Stückpreis
  statt Gesamtpreis auswählt;
- Direkthandel vom Markt-Orderbuch getrennt, die feste
  Vertragserstellungsgebühr von 10.000 ISK je Produktvertrag aufgenommen und
  Verkaufssteuer sowie Brokergebühr weiterhin mit 0 ISK ausgewiesen;
- `LogisticsRouteAssessment` mit `calculated`, `notRequired`,
  `manualTransferRequired`, `prohibited` und `unavailable` eingeführt. Jede
  Strategiekarte zeigt Main Hub → Produktion sowie Produktion → Verkaufsort;
  eigenständige Logistikkarten und Logistik in der sichtbaren Kosten-
  Zwischensumme wurden entfernt;
- übergroße Einzelstücke als manuell zu planenden Transport modelliert; bis zur
  manuellen Klärung bleiben Szenariogesamtkosten, Gewinn, Marge und ROI
  unverfügbar;
- die dokumentierte Highsec-Beschränkung für Capital-Schiffe auf den
  Produktionsrückweg zum Main Hub angewendet. Main-Marktverkauf bleibt für die
  betroffenen Capital-Gruppen gesperrt, Home-/Coalition-Verkauf bleibt an
  konfigurierten erreichbaren Orten möglich; Freighter und Jump Freighter sind
  ausdrücklich ausgenommen;
- deutsche/englische Oberfläche sowie `dokumentation.md`,
  `Documentation/PRODUCTION_BASIS.md`, `Documentation/HANDOFFS.md` und
  `Documentation/ACCEPTANCE.md` auf den aktuellen Vertrag gebracht.

Ergebnis: Produktionskosten zeigen Materialwiederbeschaffung, BPC/BPO und
Installation ohne Logistik. Jede Verkaufsstrategie addiert ihre tatsächlich
erforderlichen Routen genau einmal. Der Direkthandel nutzt einen belastbaren
öffentlichen Vertragsvergleich und seine Vertragsgebühr, ohne Marktgebühren zu
erfinden. Unvollständige Vertragsabdeckung, manuelle Transporte und verbotene
Capital-Routen bleiben explizit unverfügbar.

Prüfung: Der isolierte App-Ziel-Build bestand. Neue deterministische Tests
decken niedrigsten Vertragsstückpreis, Ausschluss von Bündeln und
Tauschforderungen, unvollständige/trunkierte Vertragsabdeckung, beide
Logistikrichtungen, übergroße Einzelstücke, Capital-Highsec-Sperre sowie
Freighter-/Jump-Freighter-Ausnahmen ab. Der fokussierte isolierte Lauf bestand
69 Tests in drei Suites. Der vollständige isolierte SwiftPM-Lauf baute Core,
App und App-Tests und bestand 341 Swift-Testing-Tests in 25 Suites sowie 7
XCTest-Fälle. Striktes Swift-Format, beide Lokalisierungskataloge,
Duplikatprüfung und `git diff --check` bestanden. Native Xcode-Evidenz wurde
nicht erneut beansprucht, nachdem die unmittelbar vorherigen Versuche in
diesem Checkout bereits vor der DerivedData-Erzeugung in der lokalen
Paketauflösung stehen geblieben waren.

Offen: Live-Abgleich der Vertragserstellungsgebühr und repräsentativer
öffentlicher Verträge im Spiel, tatsächliche Capital-/Hauling-Routen,
Player-Structure-Zugriff, visuelles Layout, Tastatur, VoiceOver und ausdrückliche
Owner-Abnahme. Dieser Stand wurde durch den nachfolgenden Eintrag zur
universumsweiten Referenz und zur Trennung von Vertragshandel und Direkthandel
fachlich abgelöst.

## 2026-08-13 – Universumsweite Vertragsreferenz und getrennter Vertragshandel

Ziel: Der im gemeldeten Ark-Plan sichtbare Bruttoerlös sollte seine Quelle
eindeutig als Markt oder öffentliche Verträge ausweisen. Direkthandel sollte
den niedrigsten vergleichbaren öffentlichen Vertragspreis im gesamten
importierten Universum verwenden, aber keine Vertrags- oder Marktgebühren
abziehen. Ein tatsächlich veröffentlichter Vertrag sollte als eigene
Verkaufsstrategie mit Vertragskosten berechnet werden. Historische
Coalition-Pläne ohne auswertbare Rückroute durften fehlende Gesamtkosten nicht
als 0 ISK behandeln.

Entwicklung:

- vor der Korrektur den vollständigen gemischten Checkout in
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-contract-pricing-before.tar.gz`
  gesichert und das Archiv lesend geprüft;
- die Public-Contracts-Projektion um einen vollständigkeitsgebundenen
  universumsweiten Mindeststückpreis ergänzt. Ein optionaler Satz erlaubter
  Regions-IDs ist bereits Teil des Datenvertrags, die spätere Auswahl in den
  Einstellungen bleibt jedoch bewusst offen;
- Home und Coalition jeweils um einen eigenständigen Vertragshandel ergänzt.
  Vertragshandel verwendet die öffentliche Vertragsreferenz, 0 ISK
  Markt-Verkaufssteuer und 0 ISK Markt-Brokergebühr sowie einen je Hub manuell
  bestätigten kombinierten Satz nicht erstattbarer öffentlicher
  Vertragsgebühren. Ein unbekannter Satz hält Nettoerlös und Gewinn
  unverfügbar; eine erstattbare Kaution wird nicht als Kosten behandelt;
- Direkthandel als gebührenfreien Vergleich korrigiert: keine Verkaufssteuer,
  keine Brokergebühr und keine Vertragsgebühr. Damit wurde die zuvor
  angenommene feste 10.000-ISK-Vertragsgebühr entfernt;
- Bruttozeilen und Berechnungsdetails nach Datenquelle getrennt: Markt,
  öffentlicher Vertragsumsatz oder öffentlicher Vertragsvergleich;
- den historischen Fallback für fehlende ausgehende Routen präzisiert. Ein
  alter Plan zeigt weiterhin keine erfundenen Gesamtkosten oder Gewinne und
  fordert nun ausdrücklich zu einer Neuberechnung für Route 2 auf;
- Persistenz rückwärtskompatibel um optionale Vertragshandels-Szenarien und
  Vertragssätze erweitert; deutsche und englische Texte sowie die fachlichen
  Verträge und Akzeptanznachweise aktualisiert.

Ergebnis: Marktstrategien beziehen ihren Bruttoerlös weiterhin aus dem
jeweiligen Hub-Markt. Vertragshandel und Direkthandel beziehen ihre Referenz aus
dem niedrigsten vergleichbaren vollständigen öffentlichen Item-Exchange-Angebot
des importierten Universums. Nur Vertragshandel zieht den manuell bestätigten
nicht erstattbaren Vertragskostensatz ab. Der gemeldete historische
Coalition-Fall bleibt bis zur Neuberechnung ehrlich unverfügbar, statt eine
fehlende Rückroute als kostenlos zu werten.

Prüfung: Fokussiert bestanden 54 Public-Contract- und Industry-Tests in zwei
Suites. Der vollständige isolierte SwiftPM-Lauf baute Core, App und App-Tests
und bestand 343 Swift-Testing-Tests in 25 Suites sowie 7 XCTest-Fälle. Der
native unsignierte Xcode-App-Build bestand. Striktes Swift-Format, beide
Lokalisierungskataloge, die Prüfung auf doppelte Schlüssel und
`git diff --check` bestanden.

Offen: Vergleich repräsentativer öffentlicher Verträge und der aktuellen
öffentlichen Vertragsgebühren im Spiel, UI-Auswahl der erlaubten Regionen,
Live ESI/Player-Structure-Zugriff, Neuberechnung und Sichtprüfung des gemeldeten
Ark-Plans, Tastatur, VoiceOver und ausdrückliche Owner-Abnahme.

## 2026-08-13 – Vorläufige Rentabilität bei manuellem Transport

Ziel: Bei einem über dem Kuriervertragslimit liegenden Produkt wie der Ark
sollten bekannte Produktions- und Routenkosten nicht länger vollständig
verschwinden. Gewinn, Marge und ROI sollten trotz noch unbekanntem manuellem
Transport als klar gekennzeichnete Vorabrechnung sichtbar sein. Der
Vertragshandel sollte den universumsweit niedrigsten öffentlichen
Vertragspreis weiterhin verwenden und auch bei einer noch nicht belegten
persönlichen Vertragsgebühr eine ehrliche Vorabrechnung liefern.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout in
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-manual-route-contract-profit-before.tar.gz`
  gesichert und das Archivverzeichnis lesend geprüft;
- `manualTransferRequired` von einer verbotenen oder anderweitig nicht
  verfügbaren Route getrennt. Produktionskosten und alle berechenbaren
  Teilrouten werden nun als bekannte Szenariokosten summiert; nur der manuelle
  Transport bleibt als zusätzlicher unbekannter Kostenbestandteil offen;
- Gewinn, Marge und ROI für diesen Fall als vorläufige Obergrenzen vor
  Transport berechnet und in Karte, Hilfetext und Berechnungsdetails eindeutig
  so bezeichnet. Verbotene oder anderweitig nicht verfügbare Routen bleiben
  weiterhin vollständig sperrend;
- den universumsweiten Public-Contracts-Mindeststückpreis unverändert als
  Erlösbasis für Vertragshandel und Direkthandel beibehalten. Markt-
  Brokergebühr und Markt-Verkaufssteuer bleiben dort 0 ISK;
- beim Vertragshandel einen fehlenden persönlichen öffentlichen
  Vertragsgebührensatz nicht als 0 ISK behauptet. Stattdessen erscheinen
  Erlös, Gewinn, Marge und ROI bis zur Profilhinterlegung ausdrücklich **vor
  öffentlicher Vertragsgebühr**. ESI stellt weder beim beobachteten Vertrag noch
  für einen hypothetisch neu erstellten Vertrag ein persönliches Gebührenangebot
  bereit;
- deutsche und englische Darstellung sowie `dokumentation.md`,
  `Documentation/PRODUCTION_BASIS.md`, `Documentation/HANDOFFS.md` und
  `Documentation/ACCEPTANCE.md` auf den neuen Vorbehaltsvertrag aktualisiert.

Ergebnis: Ein manueller Transport löscht die wirtschaftliche Vergleichbarkeit
nicht mehr. Die App zeigt die bekannte Kostenbasis als „plus Transportkosten“
und kennzeichnet die daraus berechneten Kennzahlen als Obergrenzen. Beim
Vertragshandel stammt der Bruttoerlös weiterhin aus dem niedrigsten passenden
öffentlichen Vertrag des vollständig importierten Universums; ein bestätigter
Vertragsgebührensatz führt zur endgültigen Netto-Rechnung, ein fehlender Satz
zu einer sichtbar vorläufigen Rechnung statt zu einem erfundenen Gebührenwert.

Prüfung: Der fokussierte isolierte Industry-Lauf bestand 25 Tests. Der
vollständige isolierte SwiftPM-Lauf baute Core, App und App-Tests und bestand
343 Swift-Testing-Tests in 25 Suites sowie 7 XCTest-Fälle. Striktes
Swift-Format, beide Lokalisierungskataloge, Duplikatprüfung,
Dokumentations-Linkprüfung und `git diff --check` bestanden. Der abschließende
native unsignierte Xcode-App-Build bestand ebenfalls.

Offen: Sichtprüfung des gemeldeten Ark-Plans, Eingabe und Vergleich der aktuell
von EVE angezeigten persönlichen öffentlichen Vertragsgebühr, ein realer
manueller Transportpreis, Live ESI/Public-Contracts-Vollständigkeit, Tastatur,
VoiceOver und ausdrückliche Owner-Abnahme.

## 2026-08-13 – Drei Verkaufswege je Hub und Ark-Produktbild

Ziel: Der Planner sollte den getrennten Spieler-Direkthandel vollständig
entfernen und an Main Hub, Home Hub und Koalitions-Hub ausschließlich
Sofortverkauf, eingestellten Marktverkauf und öffentlichen Vertragshandel
zeigen. Jeder Vertragshandel sollte den universumsweit niedrigsten passenden
öffentlichen Vertragspreis und die Vertragsgebühr berücksichtigen. In der
BPC/BPO-Kostenkarte sollte die Ark außerdem als Schiff statt mit einem
unpassenden Typsymbol erscheinen.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout in
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-three-sale-strategies-before.tar.gz`
  gesichert und das Archiv lesend geprüft;
- `directTrade` aus dem Preisvertrag, den neuen Plansnapshots, Berechnungen,
  Karten und Tests entfernt. Alte serialisierte Direkthandelsfelder bleiben als
  unbekannte JSON-Schlüssel lesbar und blockieren das Dekodieren nicht;
- Vertragshandel am Main Hub ergänzt. Ein einziger vollständiger,
  universumsweiter Public-Contracts-Snapshot versorgt Main, Home und Coalition
  mit dem niedrigsten vergleichbaren Stückpreis für exakt einen angebotenen
  Produkttyp ohne angeforderte Positionen oder Bündel;
- den pro Hub hinterlegten, in EVE bestätigten kombinierten nicht erstattbaren
  Vertragsgebührensatz nun auch am Main Hub weitergereicht und vom
  Vertragserlös abgezogen. Markt-Verkaufssteuer und Markt-Brokergebühr bleiben
  dort 0 ISK. Fehlt der persönliche Satz, bleibt die Rechnung ausdrücklich
  vor dieser Gebühr vorläufig;
- die offiziellen CCP-Unterlagen erneut geprüft: Der Support beschreibt den
  öffentlichen Item-Exchange-Ablauf, veröffentlicht aber keine persönliche
  Vertragsgebührenformel. Die dokumentierten Market-Order-Sätze werden deshalb
  nicht als Vertragsgebühr umgedeutet; ESI liefert keine Gebührenvorschau für
  einen hypothetisch neu erstellten Vertrag;
- die BPC/BPO-Kostenzeile auf die offizielle Renderdarstellung des produzierten
  Typs mit offiziellem Icon-Fallback umgestellt. Für die Ark wird damit Typ
  `28850` gerendert. Der Produktname verwendet einen separaten gemeinsamen
  Kopierknopf; nur der Chevron öffnet die Details;
- deutsche und englische Texte sowie `dokumentation.md`,
  `Documentation/PRODUCTION_BASIS.md`, `Documentation/HANDOFFS.md` und
  `Documentation/ACCEPTANCE.md` auf den neuen Dreiervertrag aktualisiert.

Ergebnis: Jeder der drei Hubs besitzt genau die drei gewünschten
Verkaufsstrategien. Der Vertragspreis stammt aus dem vollständigen importierten
Universum, seine bestätigte Vertragsgebühr fließt als eigener Abzug ein, und
keine Marktorder kann stillschweigend als Vertragsreferenz dienen. Die Ark-
Kostenzeile verwendet die Schiffsdarstellung und bleibt kopier- sowie
aufklappbar, ohne beide Klickziele zu vermischen.

Prüfung: Der vollständige isolierte SwiftPM-Lauf baute Core, App und App-Tests
und bestand 343 Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle. Der
frische native unsignierte Xcode-App-Build endete mit `BUILD SUCCEEDED`.
Striktes Swift-Format für die betroffenen Dateien, beide
Lokalisierungskataloge, doppelte Lokalisierungsschlüssel, lokale
Dokumentationslinks und `git diff --check` wurden erfolgreich geprüft.

Offen: Sichtprüfung des Ark-Bilds und der neun Karten, Tastatur und VoiceOver,
Live-Vergleich des universumsweiten Vertragspreises, Eingabe der aktuell in EVE
angezeigten persönlichen Vertragsgebühr, spätere Regionsauswahl und
ausdrückliche Owner-Abnahme.

## 2026-08-13 – Verpacktes Transportvolumen statt Schiffsvolumen

Ziel: Die vom Planner für fertige Schiffe berechneten Kurierverträge sollten
das Volumen des verpackten Gegenstands verwenden. Der gemeldete Zehn-Hulk-Plan
hatte aus dem entpackten Volumen fünf Verträge und dadurch stark überhöhte
Transportkosten gebildet.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout unter
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-13-packaged-volume-before.tar.gz`
  gesichert und das Archiv lesend geprüft;
- den aktiven SDE-Build `3458726`, seine ursprüngliche `types.jsonl` und den
  SQLite-Katalog lesend geprüft. Alle 26.992 veröffentlichten Katalogtypen
  hatten `packaged_volume = NULL`; Hulk und Ark enthielten im aktuellen
  clientbasierten SDE nur die entpackten Werte 150.000 beziehungsweise
  18.500.000 m³. `COALESCE(packaged_volume, volume)` war damit die konkrete
  Ursache der falschen Verträge;
- aktuelle öffentliche ESI-Typdetails mit Kompatibilitätsheader geprüft: Hulk
  Typ `22544` liefert `packaged_volume = 3.750`, Ark Typ `28850` liefert
  `packaged_volume = 1.300.000` m³;
- den SDE-Katalog so geändert, dass ausschließlich ein tatsächlich vorhandenes
  `packaged_volume` zurückgegeben wird. Das entpackte `volume` ist kein
  Transportfallback mehr;
- `UniverseTypeVolumeService` ergänzt. Er lädt nur die bereits vom
  Produktionsgraph ermittelten Typen über das öffentliche ESI, begrenzt die
  Parallelität, nutzt den bestehenden ESI-Cache und liefert einen
  quellengebundenen vollständigen, partiellen oder unverfügbaren Snapshot;
- `PackagedVolumeSnapshotCatalog` komponiert diesen unveränderlichen Snapshot
  mit den statischen Blueprint-, Typ- und Klassifikationsdaten. Planner,
  experimentelle geführte Planung, Reaktionen und Main-Hub-Chancen verwenden
  dieselbe verpackte Volumenquelle. Fehlende ESI-Typen bleiben unverfügbar;
- deutsche und englische Warntexte sowie Architektur-, Produktionsbasis-,
  Übergabe- und Akzeptanzdokumentation auf die getrennten SDE-/ESI-Quellen
  aktualisiert.

Ergebnis: Zehn Hulks werden mit dem aktuellen CCP-Wert als 37.500 m³ in genau
einen 350.000-m³-Kuriervertrag eingeordnet. Der angenommene Wert 25.000 m³ ist
aktuell nicht der von CCP gelieferte Wert; die fachliche Korrektur von fünf auf
einen Vertrag bleibt bestehen. Eine Ark ist auch verpackt 1.300.000 m³ groß und
bleibt deshalb als einzelner Gegenstand oberhalb des Standardlimits sichtbar.

Prüfung: Drei gezielte Swift-Tests bestanden: öffentliche ESI-Werte und Cache,
fehlender SDE-Rückfall sowie zehn Hulks mit 37.500 m³ in einem Vertrag. Der
vollständige isolierte SwiftPM-Lauf bestand anschließend 346 Swift-Testing-Tests
in 25 Suites sowie 8 XCTest-Fälle. Auch der frische unsignierte native
Xcode-Debug-Build war erfolgreich. Striktes Swift-Format, die beiden
Lokalisierungskataloge, doppelte Schlüssel, lokale Dokumentationslinks und
`git diff --check` wurden abschließend geprüft.

Offen: Reale Neuberechnung des gemeldeten Zehn-Hulk-Plans im laufenden Programm,
Vergleich der daraus entstehenden Kosten mit dem Transportanbieter, visuelle
Warnungs-/Routendarstellung, Tastatur, VoiceOver und Owner-Abnahme.

## 2026-08-14 – Korrekte EVE-Bilder für rekursive Produktionspläne

Ziel: Sichtbare EVE-Gegenstände sollten programmweit das Bild ihrer exakten
Type-ID zeigen. Im gemeldeten Rhea-Plan stand neben dem Produktnamen das blaue
Symbol eines anderen Gegenstands.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout unter
  `/private/tmp/EVE_NEXUS_SIMPLE-backup-2026-08-14-item-images-before.tar.gz`
  gesichert und das Archiv lesend geprüft;
- den aktiven SDE-Katalog und den gespeicherten Rhea-Plan ausschließlich lesend
  untersucht. Die Produktionsanfrage beginnt mit Self-Harmonizing Power Core
  Typ `2872`; der produzierte, nicht von einem anderen Planknoten referenzierte
  Wurzelknoten ist Rhea Typ `28844`. Das gezeigte blaue Bild gehörte damit exakt
  zum fälschlich ausgewählten ersten Rohstoffknoten;
- `IndustryPlanSnapshot.topLevelProductNode(for:)` als gemeinsamen fachlichen
  Resolver ergänzt. Er wählt je Anfrage den produzierten Wurzelknoten statt des
  ersten beliebigen Knotens eines rekursiv kind-zuerst gespeicherten Plans;
- BPC/BPO-Kostenzeile, historische Planner-Darstellung,
  Produktionsübersichtsprojektion und -entwürfe sowie das Produktionsbuch auf
  denselben Resolver umgestellt. Ein Regressionstest beweist die Auswahl des
  Endprodukts, obwohl ein Rohstoff der erste gespeicherte Knoten ist;
- alle Bild-Aufrufstellen in Core, App und Tests geprüft. Blueprint-, Material-
  und Strukturzeilen verwenden weiterhin die Type-ID ihrer eigenen sichtbaren
  Entität. Die letzte separat aufgebaute Typbild-URL der Strukturdarstellung
  verwendet nun ebenfalls `EVETypeImageURL`; direkte EVE-Typbild-URLs liegen im
  App-Quelltext nur noch an dieser gemeinsamen Grenze;
- Itemvertrag, Architektur, Skill-Übergabe, Hauptdokumentation und
  Akzeptanzmatrix auf die gemeinsame Produktwurzel und die getrennte
  Bild-/Namensidentität aktualisiert.

Ergebnis: Eine rekursive Planung kann keinen Rohstoff oder ein Zwischenprodukt
mehr als Bild für das beschriftete Endprodukt verwenden. Der gemeldete Rhea-Fall
liefert Typ `28844` an die offizielle Schiffsdarstellung; fehlende oder
unaufgelöste Type-IDs bleiben weiterhin explizit und werden nicht geraten.

Prüfung: Der gezielte Produktwurzeltest bestand. Der vollständige isolierte
SwiftPM-Lauf baute Core, App und App-Tests und bestand 347 Swift-Testing-Tests in
25 Suites sowie 8 XCTest-Fälle. Der frische unsignierte native Xcode-Debug-Build
war erfolgreich. Striktes Swift-Format, beide Lokalisierungskataloge, doppelte
Schlüssel, lokale Dokumentationslinks und `git diff --check` wurden erfolgreich
geprüft.

Offen: Den Rhea-Plan im neu gebauten laufenden Programm erneut öffnen und das
Schiffsbild visuell bestätigen. Stichproben in allen Modulen, langsamer oder
fehlgeschlagener Bildabruf, Tastatur, VoiceOver und ausdrückliche Owner-Abnahme
bleiben getrennte Sichtprüfungen.

## 2026-08-14 – Capital-Mindestpreis und Gewinn ohne Highsec-Brokergebühr

Ziel: In der Produktionsübersicht sollten Capitals mit ausdrücklich
verbotenem Highsec-Main-Hub-Verkauf trotz nicht anwendbarer Brokergebühr ihren
Kosten-plus-10-Prozent-Mindestpreis sowie Steuer und Gewinn aus einem manuell
eingetragenen Verkaufspreis berechnen. Eine wirklich unbekannte, aber
anwendbare Brokergebühr durfte dabei nicht still zu null werden.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout ohne Build- und
  Git-Verwaltungsdaten unter
  `/private/tmp/EVE-NEXUS-SIMPLE-before-production-overview-fix-2026-08-14-205016.tar.gz`
  gesichert; SHA-256
  `e96749a39c96e3fdbbf2ca25caaba6871b7df20e9641a85f0962d47befbfdf8d`;
- `SaleScenarioResult` um die getrennt eingefrorenen Verkaufssteuer- und
  Brokergebührensätze sowie die Broker-Anwendbarkeit ergänzt. Auch ein wegen
  der Capital-Highsec-Regel nicht ausführbares Szenario behält damit den
  belegten Steuersatz, ohne einen Brokerbetrag zu erfinden;
- `ProductionOverviewProjector` auf die expliziten Satzfelder umgestellt und
  für historische Capital-Snapshots einen ausschließlich snapshotinternen
  Home-/Coalition-Fallback ergänzt. Aktuelle Profildaten werden nicht in die
  Historie eingemischt;
- Mindestpreis, prognostizierten Gewinn, Marge und realen Gewinn so getrennt,
  dass eine ausdrücklich nicht anwendbare Brokergebühr als `—` sichtbar
  bleibt, rechnerisch aber keinen Abzug bildet. Ein lediglich unbekannter Satz
  für einen möglichen Listenverkauf blockiert die Nettowerte weiterhin;
- die deutsche und englische Produktionsübersicht um den Capital-Hinweis
  ergänzt sowie Architektur-, Übergabe-, Akzeptanz- und Anwenderdokumentation
  aktualisiert.

Ergebnis: Bei einem Highsec-gesperrten Capital verwendet `Min. +10 %` die
vollständigen Produktionskosten plus zehn Prozent und rechnet den bekannten
Verkaufssteuersatz brutto hoch. Nach Eingabe eines Verkaufspreises erscheinen
Steuer, prognostizierter Gewinn und Marge; der reale Gewinn berücksichtigt die
verkaufte Menge. Ohne Verkaufspreis bleibt ein Steuerbetrag weiterhin
unberechenbar. Die Broker-Spalte bleibt als nicht anwendbar `—`.

Prüfung: Der isolierte fokussierte SwiftPM-Lauf baute Core, App und Tests und
bestand zehn Tests in den Suites Produktionsübersicht und Industry Planner.
Abgedeckt sind der neue Capital-Fall, der weiterhin blockierende wirklich
unbekannte Brokergebührensatz und das Lesen eines historischen Snapshots ohne
die neuen Satzfelder. Der anschließende vollständige isolierte SwiftPM-Lauf
bestand 347 Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle. Der frische
native unsignierte Xcode-Debug-Build war erfolgreich. Striktes Swift-Format,
beide Lokalisierungskataloge, doppelte Lokalisierungsschlüssel, lokale
Dokumentationslinks und `git diff --check` bestanden ebenfalls.

Offen: Sichtprüfung der gemeldeten Bane-/Rorqual-Zeilen im laufenden Programm,
Tastatur, VoiceOver und ausdrückliche Owner-Abnahme bleiben eigenständige
Nachweise. Eine Zeile ohne eingetragenen Verkaufspreis kann weiterhin keinen
Steuerbetrag oder Verkaufsgewinn anzeigen.

## 2026-08-15 – Planner-Eingabefehler direkt an der Eingabe

Ziel: Kontinuierlich erkannte Eingabefehler sollten im Planner unmittelbar bei
der betroffenen Eingabe auffallen und nicht erst unterhalb der letzten
Produktionen erscheinen.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout ohne Build- und
  Git-Verwaltungsdaten unter
  `/private/tmp/EVE-NEXUS-SIMPLE-before-planner-input-error-placement-2026-08-15-072734.tar.gz`
  gesichert; SHA-256
  `2dcdcd562d0e139cc8e17db4ffdfeb477e0e27535bbec68e85e0a138e155f700`;
- die vorhandene nummerierte Fehlerausgabe unverändert in die Fläche
  **Produzieren** direkt unter die Zeile mit **Berechnen** verschoben;
- die Fehlerfläche mit einer stabilen Accessibility-Kennung versehen und
  Anwenderdokumentation sowie Akzeptanzmatrix an die tatsächliche Platzierung
  angepasst.

Ergebnis: Ungültige oder unvollständige Zeilen werden weiterhin während des
Tippens erkannt. Der zugehörige Hinweis steht nun vor Lageroptionen und letzten
Produktionen direkt bei der Eingabe; **Berechnen** bleibt bei Fehlern wie bisher
deaktiviert. Parser und Kalkulationslogik wurden nicht verändert.

Prüfung: Der gezielte Parser-Test für BPC/BPO ohne vollständigen Kostenbetrag
bestand; dabei wurde der geänderte App-Target vollständig kompiliert. Der
anschließende vollständige isolierte SwiftPM-Lauf bestand 347
Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle. Der frische native
unsignierte Xcode-Debug-Build war erfolgreich. Striktes Swift-Format,
Skill-Suite-Links, beide Lokalisierungskataloge, doppelte
Lokalisierungsschlüssel und `git diff --check` wurden abschließend geprüft.

Offen: Sichtprüfung im laufenden bevölkerten Programm sowie Tastatur,
VoiceOver und ausdrückliche Owner-Abnahme.

## 2026-08-15 – Dashboard-Startsync und täglicher Vermögensverlauf

Ziel: Das Dashboard sollte beim Programmstart seine privaten Finanz- und
Bestandsquellen tatsächlich aktualisieren, den Wallet-Stand nachvollziehbar
auffrischen und statt eines schwer lesbaren Index-Graphen einen belastbaren
täglichen Verlauf zeigen. Bereits in laufender Produktion verbrauchte
Materialien sollten im Vermögen sichtbar bleiben.

Entwicklung:

- vor der Änderung den gemischten Checkout außerhalb des Arbeitsverzeichnisses
  unter `/private/tmp/EVE-NEXUS-SIMPLE-backup-2026-08-15-dashboard.tar.gz`
  gesichert; Gzip-Integrität und Inhaltsverzeichnis wurden geprüft, SHA-256
  `cb67d3e7b5550932d094470d2692a41db622443affba487baaf598a7b0cfca9c`;
- beim ersten Dashboard-Aufruf pro App-Prozess einen vollständigen Sync aller
  verbundenen Charaktere reserviert. Wallet, Assets, Industry Jobs, Orders,
  private Contracts sowie berechtigte Corporation-Wallets/-Assets werden mit
  ihren Quellzuständen gespeichert; die Wallet-Karte kann denselben Ablauf
  manuell wiederholen und zeigt vollständige oder partielle Ergebnisse;
- Vermögenshistorie weiterhin auf höchstens einen ersetzbaren Punkt pro lokalem
  Kalendertag begrenzt, aber Diagramme auf echte Datumsabstände und eine
  adaptive Werteskala umgestellt. Gesamtwert, Wallet, Assets und **In
  Produktion** sind getrennt betrachtbar; auf Net Worth lassen sich die
  Komponenten einzeln ein- und ausblenden;
- aktive, pausierte und abholbereite Manufacturing-/Reaction-Jobs aus den
  gespeicherten Jobquellen mit ihren SDE-Materialanforderungen bewertet.
  Bekannte Blueprint-ME wird berücksichtigt, ausgelieferte, abgebrochene und
  zurückgesetzte Jobs werden ausgeschlossen. Unbekannte Facility-/Rig-Abzüge,
  fehlende SDE-Definitionen oder Preise bleiben ausdrücklich geschätzt oder
  unvollständig;
- deutsche und englische Oberfläche, Anwenderdokumentation, Skill-Handoffs und
  Akzeptanzmatrix aktualisiert.

Ergebnis: Der erste Dashboard-Aufruf stößt genau einmal einen sichtbaren
privaten Charakter-Sync an und erzeugt nach erfolgreicher öffentlicher
Preisaktualisierung den Tagespunkt. Fehlgeschlagene Einzelquellen behalten den
letzten bekannten Stand statt null. Die Verlaufsgrafik zeigt reale Tage und
hebt auch kleinere Veränderungen hervor; gebundene Produktionsmaterialien
verschwinden nicht mehr vollständig aus dem bekannten Vermögen.

Prüfung: Der fokussierte isolierte SwiftPM-Lauf bestand 15
Dashboard-Projektionstests einschließlich der neuen Produktionsmaterial-
Bewertung. Zehn Runtime-Feature-Tests bestanden einschließlich der
Einmalreservierung des Startsyncs, ungleicher Tagesabstände und adaptiver
Skalierung. Der anschließende vollständige isolierte SwiftPM-Lauf baute Core,
App und Tests und bestand 350 Swift-Testing-Tests in 25 Suites sowie 8
XCTest-Fälle. Striktes Swift-Format für die geänderten Swift-Dateien, beide
Lokalisierungskataloge, doppelte Lokalisierungsschlüssel und
`git diff --check` bestanden. Der native unsignierte Xcode-Build erreichte die
Dashboard-Dateien, ist im gemischten Arbeitsstand aber nicht abgeschlossen:
die parallel neu angelegte `OreRefining.swift` ist noch nicht im
Xcode-Projekt registriert, sodass dort fachfremde `CompressedOreOption`- und
`CompressedOreRefiningPlan`-Typen fehlen.

Offen: Ein echter Start mit privaten ESI-Daten wurde nicht ausgelöst. Vergleich
mit Wallet, Assets und laufenden Jobs im EVE-Client, mehrere reale Tagespunkte,
enge Fensterbreite, Tastatur, VoiceOver, CPU/RSS und ausdrückliche
Owner-Abnahme bleiben eigenständige Live- und Sichtnachweise.

## 2026-08-15 – Compressed-Ore-Refining für Planner-Logistik

Ziel: Ungedeckte Mineralien sollten nicht mehr grundsätzlich unkomprimiert vom
Main Hub zum Produktionsort transportiert werden. Der Planner sollte
komprimierte Erze einschließlich Markttiefe, skillabhängiger Ausbeute,
Refining-Anlage, Gebühr und vollständiger Logistik prüfen und nur bei einem
echten vollständigen Kostenvorteil auswählen.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout einschließlich
  `.git` außerhalb des Arbeitsverzeichnisses unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-compressed-ore-refining-full.tar.gz`
  gesichert; das lesbare 38-MB-Archiv hat SHA-256
  `1259082bae3a5f4f0273758096dc47cd7c798c8dd891bbe74d9e08b6e066b5f1`;
- die persistierte Production Basis um die optionale
  Compressed-Ore-Refining-Regel, mehrere bereits vorhandene
  Strukturkonfigurationen als Refining-Ziele, eine bestätigte optionale
  Refining-Gebühr und eine optionale feste Charakterzuordnung je Anlage
  erweitert. Ohne feste Zuordnung wird pro Erz der ertragsstärkste verbundene
  Charakter anhand von Reprocessing, Reprocessing Efficiency und
  erzspezifischem Processing bestimmt;
- EVEStaticDataKit und den SQLite-Katalogadapter 3 um das offizielle
  `typeMaterials`-Dataset, Refining-Ausgaben, Dogma-Skillzuordnung und
  Asteroiden-/Monderz-Rig-Ausbeuten erweitert. Vorhandene ältere Kataloge
  bleiben lesbar; fehlende Tabellen führen zur ausdrücklichen direkten
  Mineralroute und benötigen vor Nutzung einen sicheren gleichen Build-
  Neuimport oder ein SDE-Update;
- die Planner-Domäne so erweitert, dass sie direkte Mineralbeschaffung und
  -logistik gegen vollständigen Erzeinkauf, Transport zur gewählten Anlage,
  skillabhängige gerundete Ausgabe, Adjusted-Price-basierte Refining-Gebühr und
  die tatsächliche Kuriervertragsaufteilung vergleicht. Nur positive
  Gesamtersparnis bleibt ausgewählt; unvollständige Skills, SDE-Daten, Preise,
  Gebühren, Volumina oder Raten werden nicht als null behandelt;
- Ergebnis-Snapshot, Kostenkarte, Refining-Aufschlüsselung und
  EVE-Multibuy-Liste um gewähltes Erz, Restmineralien, Anlage, kopierbares
  System, kopierbaren Charakter, Ausbeute, Gebühr, beide vollständigen Wege und
  Ersparnis erweitert. Refining-Implantate bleiben ausdrücklich unberücksichtigt;
- deutsche und englische Lokalisierung, Xcode-Projektmitgliedschaft,
  `dokumentation.md` und
  [Production-Basis-Vertrag](Documentation/PRODUCTION_BASIS.md) aktualisiert.

Ergebnis: Der normale Planner kann mehrere Refining-Anlagen in verschiedenen
Systemen bewerten und je Erz automatisch den besten belegten Charakter wählen.
Eine teurere oder unvollständige Erzroute verändert weder Mineralcargo noch
Einkaufsliste; eine günstigere vollständige Route ersetzt nur die gedeckten
Mineralien und bleibt als eigener Kosten- und Logistiknachweis sichtbar.

Prüfung: Der vollständige isolierte SwiftPM-Lauf baute Core, App und Tests und
bestand 353 Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle. Darin
enthalten sind neue Nachweise für SDE-`typeMaterials`, Skillformel und
Abrundung, Auswahl des besseren Charakters, günstige Erzroute, Rückfall bei
teurem Erz sowie angepasste Multibuy-Zeilen. Der native unsignierte
Xcode-Debug-Build mit isoliertem DerivedData endete mit `BUILD SUCCEEDED` und
kompilierte `OreRefining.swift` im Core-Target. Striktes Swift-Format, beide
Lokalisierungskataloge, doppelte Lokalisierungsschlüssel und
`git diff --check` bestanden.

Offen: Ein sicherer SDE-Neuimport des lokal aktiven echten Builds, Live-ESI-
Markttiefe, reale Charakter-Skills, die konkrete Darfnor-Tatara einschließlich
in EVE bestätigter Gebühr/Rigs, ein realer Planner-Vergleich, visuelle Prüfung
bei verschiedenen Fensterbreiten, VoiceOver, CPU/RSS und ausdrückliche
Owner-Abnahme wurden nicht durchgeführt. Refining-Implantate benötigen einen
eigenen verifizierten Datenvertrag, bevor sie eingerechnet werden dürfen.

## 2026-08-15 – SDE-Zeiger, Dashboard-Raster und ESI-Teilstatus

Ziel: Der in der laufenden App als nicht installiert gemeldete SDE-Katalog mit
dem Rohfehler `invalidPointer`, die unausgewogene Industriekapazität im
Dashboard und die gelben Asset-Hinweise der ESI-Charaktere sollten gemeinsam,
aber mit getrennten Ursachen geprüft und behoben werden.

Entwicklung:

- vor den Änderungen den vollständigen gemischten Checkout außerhalb des
  Arbeitsverzeichnisses unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-sde-dashboard-esi-fix.tar.gz`
  gesichert; das lesbare 39-MB-Archiv hat SHA-256
  `b117af2707c7c310cb0dcb20273a6ddeb592680d85b57ceac80a7b88e5d04573`;
- den echten aktiven Katalogzeiger und die zugehörige SQLite-Datei nur lesend
  geprüft. Der aktive, vollständig vorhandene Build 3458726 verwendete den
  früheren kanonischen Adapter-v2-Dateinamen; die auf Adapter 3 angehobene
  Prüfung akzeptierte dagegen nur noch die aktuelle v3-Datei oder den
  unversionierten Legacy-Namen. Dadurch wurde ein gültiger Katalog fälschlich
  als `invalidPointer` und anschließend als nicht installiert behandelt;
- die Zeigerprüfung so erweitert, dass kanonische versionierte Katalogdateien
  ab Version 1 bis zur aktuellen Adapterversion lesbar bleiben. Neue Dateien
  werden weiter ausschließlich mit Adapter 3 erzeugt; fremde Pfade,
  nichtkanonische und zukünftige Versionen bleiben gesperrt. Ein Regressionstest
  belegt die Lesbarkeit des v2-Zeigers, und die App übersetzt einen tatsächlich
  ungültigen Zeiger nun in einen verständlichen, datenbewahrenden Hinweis;
- die sechs Industriekapazitätskarten von einem frei adaptiven Raster auf
  stabile Alternativen 3×2, 2×3 und 1×6 umgestellt. Dadurch bleibt das
  Dashboard bei breiten Fenstern ausgeglichen und bei engen Fenstern lesbar;
- Callback-Anzeige, PKCE-Anfrage, Loopback-Server und Rückrufvalidierung geprüft:
  alle verwenden exakt `http://localhost:52722/callback`. Die gespeicherten
  Snapshots zeigten erfolgreiche ESI-Aktualisierungen; die gelben Hinweise
  stammten stattdessen aus nicht erreichbaren beziehungsweise nicht auflösbaren
  Player-Structure-Orten in den Asset-Daten. Die ESI-Seite bezeichnet diesen
  Zustand jetzt ausdrücklich als teilweise verfügbare Assets, nennt die Zahl
  der Orte und bestätigt, dass die Assets erhalten bleiben;
- deutsche und englische Lokalisierung sowie `dokumentation.md` aktualisiert.

Ergebnis: Der vorhandene Adapter-v2-Katalog wird wieder als installierter Build
3458726 erkannt und blockiert die sichere Update- oder Neuimportvorschau nicht
mehr. Das Dashboard zeigt bei der geprüften breiten Fenstergröße drei mal zwei
Kapazitätskarten. Der ESI-Hinweis unterscheidet unaufgelöste Strukturorte von
einem Berechtigungs- oder Callbackfehler.

Prüfung: Ein fokussierter isolierter SwiftPM-Lauf bestand 33 Tests aus den
`SQLiteStaticCatalogTests` und `AuthAndBlueprintTests`, einschließlich des
neuen v2-Zeigerfalls und der bestehenden exakten Callbacktests. Striktes
Swift-Format für die geänderten Swift-Dateien, beide Lokalisierungskataloge und
`git diff --check` bestanden. Der native unsignierte Xcode-Debug-Build mit
isoliertem DerivedData endete mit `BUILD SUCCEEDED`. Ein App-Start mit leerem
isoliertem Datenroot bestätigte visuell das 3×2-Dashboard-Raster. Ein zweiter
App-Start mit einer Kopie ausschließlich des echten SDE-Verzeichnisses erkannte
Build 3458726 und erreichte über **Nach SDE-Update suchen** die offizielle
Metadatenvorschau; sie meldete einen neueren offiziellen Build und die
erforderliche Schemafreigabe. Es wurde weder importiert noch aktiviert und die
Produktionsdaten wurden nicht verändert. Nach der Dokumentationsänderung baute
der vollständige isolierte SwiftPM-Lauf Core, App und Tests und bestand 354
Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle.

Offen: Ein SDE-Update oder Neuimport im produktiven Datenroot, Schemafreigabe,
vollständiger App-Neustart und Owner-Abnahme bleiben bewusst offen. Ebenso
offen sind ein neuer Live-SSO-Browserdurchlauf, der externe Abgleich der im
EVE-Developer-Portal registrierten Redirect-URL, ein Live-ESI-Vergleich der
unzugänglichen Strukturen, VoiceOver sowie CPU/RSS. Der erfolgreiche vorhandene
ESI-Sync belegt keinen neuen Login, und die isolierte Live-Metadatenprüfung
belegt keine SDE-Aktivierung.

## 2026-08-15 – Fehlende `typeDogma.dogmaEffects` im SDE-Update

Ziel: Der vom Owner bestätigte Import des neueren offiziellen SDE-Builds
3466501 scheiterte in der Mappingphase mit
`invalidField(dataset: typeDogma, line: 1, field: "dogmaEffects")`, während
der aktive Build 3458726 weiterhin verfügbar blieb.

Entwicklung:

- vor der Änderung den vollständigen gemischten Checkout einschließlich der
  bestehenden Arbeitsstände unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-typedogma-optional-effects-fix.tar.gz`
  gesichert; das lesbare 298-MB-Archiv hat SHA-256
  `efa09d494fb701f2a22588ab73aea657264f0c99f95619d2f6c457865b925307`;
- die fehlgeschlagene SDE-Operation und das beibehaltene öffentliche Paket nur
  lesend untersucht. Build 3466501, Inhaltshash
  `5b53a5c03a9e3116ff6f1ed6a3f97ecacc471155ec7a58dde33926927c064950`
  und die vollständigen acht benötigten Datasets waren vorhanden. In
  `typeDogma` fehlt `dogmaEffects` bei 10.713 von 26.828 Typen; Zeile 1 für
  Typ 18 enthält Attribute, aber erwartungsgemäß keine Effekte. Die erste
  Mapper-Erweiterung für `typeMaterials` bezog diesen reprocessbaren Typ nun
  erstmals ein und behandelte das ausgelassene optionale Feld fälschlich als
  ungültig;
- `JSONLinesSDECatalogMapper` so korrigiert, dass ausschließlich ein
  ausgelassenes `dogmaEffects` als leere Effektmenge gilt. Ein vorhandener
  falscher Typ, ungültige Effekt-IDs und Dubletten werden weiterhin abgewiesen;
  Reaktionsskill und Reaction-Rigs müssen ihre fachlich erforderlichen Effekte
  weiterhin in der nachfolgenden Profilvalidierung belegen;
- einen deterministischen Regressionstest für das ausgelassene Feld sowie je
  einen ausdrücklich opt-in geschalteten Real-SDE-Mapper- und SQLite-
  Aktivierungstest ergänzt. Ohne Pfadvariable bleiben reale öffentliche
  Pakete aus dem normalen Testsatz ausgeschlossen;
- `dokumentation.md` und die Acceptance-Matrix um die aktuelle Feldsemantik,
  Teststufen, temporäre Aktivierung und offene Owner-Abnahme ergänzt.

Ergebnis: Das vollständig vorbereitete offizielle Build-3466501-Paket passiert
nun die gesamte Mappingphase. Es kann in eine isolierte SQLite-Datenbank
gestreamt, erneut geöffnet und atomar aktiviert werden. Der produktive aktive
Katalog wurde durch Diagnose und Nachweise nicht verändert und blieb auf Build
3458726.

Prüfung: Der fokussierte deterministische Regressionstest bestand. Der
opt-in Real-SDE-Mapper verarbeitete das vollständige öffentliche Paket in
22,539 Sekunden. Der weitergehende opt-in Test schrieb denselben Build in einen
neuen temporären SQLite-Katalog, öffnete ihn erneut und aktivierte ihn dort in
48,084 Sekunden. Das eigenständige EVEStaticDataKit bestand sieben
deterministische Tests; sein Real-SDE-Test wurde ohne Opt-in erwartungsgemäß
übersprungen. Der vollständige App-Lauf bestand 354 deterministische
Swift-Testing-Tests in 25 Suites und 8 XCTest-Fälle; der getrennte Real-SDE-
Test wurde im Standardsatz erwartungsgemäß übersprungen. Der native unsignierte
Xcode-Debug-Build endete mit `BUILD SUCCEEDED`. Striktes Swift-Format und
`git diff --check` bestanden. Der erste native Buildversuch scheiterte nur an
der Dateisandbox für globale Swift-/Clang-Caches; der identische erlaubte Lauf
war erfolgreich.

Offen: Der Owner muss den neu gebauten App-Stand starten und das produktive
Update erneut bestätigen. Erst ein dort erfolgreich sichtbarer Abschluss,
vollständiges Beenden und Neuöffnen sowie die anschließende Main-Hub-Analyse
belegen die produktive Aktivierung. Sichtprüfung der neuen Refining-Daten,
Tastatur, VoiceOver, längerfristige CPU/RSS-Messung und ausdrückliche
Owner-Abnahme bleiben getrennt offen.

## 2026-08-15 – Hauptfenster startet maximiert

Ziel: Die App soll nach jedem neuen Start mit einem maximierten Hauptfenster
erscheinen, ohne in den nativen macOS-Vollbildmodus zu wechseln.

Entwicklung:

- einen kleinen AppKit-Starthelfer in die gemeinsame Wurzel beider
  Persistenzzustände eingebunden;
- den sichtbaren Arbeitsbereich des aktuellen Bildschirms als einmaligen
  Fensterrahmen verwendet, sodass Menüleiste und Dock frei bleiben;
- die Anwendung nach der ersten Maximierung bewusst nicht mehr in manuelle
  Größenänderungen eingreifen lassen;
- das aktuelle Verhalten und den getrennten Abnahmestand in
  `dokumentation.md` und der Acceptance-Matrix festgehalten.

Ergebnis: Jedes neu erzeugte App-Hauptfenster wird einmal auf den sichtbaren
Arbeitsbereich seines Bildschirms erweitert. Die bisherige SwiftUI-Startgröße
1180 × 760 bleibt als Rückfall erhalten, die Mindestinhaltsgröße 640 × 480 und
freie spätere Größenänderungen bleiben unverändert.

Prüfung: Striktes Swift-Format bestand. Ein fokussierter AppKit-Test setzte ein
Testfenster exakt auf den vorgegebenen sichtbaren Bildschirmrahmen und belegte,
dass ein anschließendes manuelles Skalieren durch einen zweiten Aufruf nicht
überschrieben wird. Der anschließende vollständige SwiftPM-Lauf bestand 356
Swift-Testing-Tests in 25 Suites und 8 XCTest-Fälle. Der erste Versuch wurde
ausschließlich durch Apples lokale
SwiftPM-Dateisandbox blockiert; derselbe Lauf mit isolierten Build- und
Modulcache-Pfaden war erfolgreich.

Offen: Visuelle Prüfung nach vollständigem Beenden und Neustart, Verhalten an
einem zweiten Bildschirm, Tastatur, VoiceOver und ausdrückliche Owner-Abnahme
bleiben getrennte Laufzeitnachweise.

## 2026-08-15 – Frachtpositionen und ESI-Volumen für Compressed Ore

Ziel: Die Planner-Logistik sollte je Kuriervertrag offenlegen, welche
Main-Hub-Einkäufe tatsächlich zum Produktions-/Home Hub transportiert werden.
Außerdem sollte der vorhandene Vergleich zwischen direkten Mineralien und
komprimiertem Erz das bereits geladene öffentliche ESI-Transportvolumen auch
im eigentlichen Ore-Vergleich zuverlässig verwenden.

Entwicklung:

- vor der Änderung den gemischten Checkout außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-logistics-breakdown-ore-fix.tar.gz`
  gesichert; das lesbare 40-MB-Archiv hat SHA-256
  `53645fdc0c8ed4ebcf947aaffe7fd5a9086b6cdfd875a27d1c8f88e489556534`;
- die unveränderliche Logistikdomäne um Frachtpositionen je erzeugtem Vertrag
  erweitert. Die ganzzahlige Vertragsaufteilung führt Typ, aufgelösten Namen,
  Menge, Volumen und anteilige Sicherheitsleistung mit und speichert diese
  Daten im Plan-Snapshot. Ältere Snapshots ohne Positionen bleiben lesbar und
  werden nicht nachträglich geschätzt;
- den `PackagedVolumeSnapshotCatalog` korrigiert: Das bereits von öffentlichem
  ESI geladene `packaged_volume` wird nun auch in jede komprimierte Erzoption
  übernommen. Das SDE bleibt ausschließlich für Chargengröße,
  Mineralausgaben und erzspezifischen Processing-Skill zuständig;
- die aufgeklappte Planner-Logistikkarte um die konkreten Positionen erweitert.
  Aufgelöste Gegenstandsnamen verwenden `EVEEntityText` und sind getrennt vom
  Disclosure direkt kopierbar; ein fehlender Name bleibt ausdrücklich
  unverfügbar;
- deutsche/englische Lokalisierung, Production-Basis-Vertrag, Skill-Handoff,
  Acceptance-Matrix und `dokumentation.md` aktualisiert.

Ergebnis: Nach einer neuen Berechnung lässt sich jeder Inbound-Vertrag direkt
mit der Einkaufsliste abgleichen. Bei einer wirtschaftlich besseren
Compressed-Ore-Route zeigt dieselbe Aufschlüsselung das gekaufte Erz und die
verbleibenden direkten Materialien. Ore ersetzt Mineralien weiterhin nur dann,
wenn Einkauf, Refining-Gebühr und vollständig gerundete Logistik zusammen
günstiger sind.

Prüfung: Die fokussierten Regressionen belegen eine gesplittete 383-Einheiten-
Fracht einschließlich exakter Vertragsmengen/-volumina, das Dekodieren eines
historischen Vertrags ohne Inhaltsfeld sowie die Auswahl des besten Refining-
Charakters und der günstigeren Ore-Route mit einem ausschließlich durch den
ESI-Snapshot gelieferten Erzvolumen; teures Erz lässt die direkte Mineralroute
unverändert. Der vollständige isolierte SwiftPM-Lauf baute Core und App und
bestand 357 Swift-Testing-Tests in 25 Suites sowie 8 XCTest-Fälle. Beide
Lokalisierungskataloge, doppelte Schlüssel und `git diff --check` bestanden.
Der native unsignierte Xcode-Debug-Build endete mit `BUILD SUCCEEDED`.

Offen: Es wurden keine aktuellen Main-Hub-Orders, privaten Charakter-Skills,
Tatara-Einstellungen oder Providerpreise live abgefragt. Ein realer
Tritanium-/Pyerite-lastiger Plan, der Abgleich mit EVE und dem Courier-
Kalkulator sowie Sichtprüfung, Tastatur, VoiceOver, CPU/RSS und ausdrückliche
Owner-Abnahme bleiben getrennt offen.

## 2026-08-15 – Logistikroute und Refining-Bereitschaft nachvollziehbar

Ziel: Die in den Verkaufsstrategien sichtbare Main-Hub-Route sollte dieselben
tatsächlichen Verträge und Frachtpositionen wie die Einkaufsliste ausweisen.
Zugleich sollte eine nicht ausgeführte Compressed-Ore-Optimierung ihren
konkreten Sperrgrund zeigen und nicht wie eine ausgebliebene Aktualisierung
wirken.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-logistics-route-audit.tar.gz`
  gesichert; das geprüfte Archiv hat SHA-256
  `579a0f801d7d00fada18e58f66663093b3ca6abc433ca10578403113c32e73f8`;
- die Refining-Bereitschaft als vollständige Ursachenliste modelliert:
  fehlender Service, fehlende Erzausbeute und unbestätigte Gebühr bleiben
  getrennte Zustände. Ein bestätigtes 0 % ist weiterhin von einem leeren,
  unbekannten Feld verschieden;
- in den Industrieeinstellungen jede relevante Refining-Anlage mit ihrem
  konkreten Bereitschaftsstatus ergänzt. Ein bereits berechneter Planner-
  Snapshot weist zusätzlich Sperrgrund und Berechnungszeit aus und fordert
  nach einer Einstellungsänderung zur neuen Berechnung auf;
- jede Verkaufsstrategie um die tatsächlichen Kurierabschnitte und deren
  aufklappbare, kopierbare Frachtpositionen ergänzt. Die Zusammenfassung zählt
  ausschließlich diese Abschnitte; der missverständliche Hinweis einer
  einzelnen Zwischenroute wird nicht mehr als abweichende Gesamtanzahl
  angezeigt;
- Produktionshistorie und Dokumentation stellen klar, dass gespeicherte
  Logistik- und Refiningwerte von aktuellen Einstellungen nicht nachträglich
  verändert werden.

Ergebnis: Der auf den Screenshots vorhandene Reprocessing-Service und die
50-%-Erzausbeute reichen bei leerer Refining-Gebühr bewusst nicht für den
Ore-Vergleich. Die Oberfläche benennt nun genau die fehlende Gebührenbestätigung.
Nach Eingabe der tatsächlichen Gebühr und einer neuen Berechnung zeigen die
Strategiekarten sämtliche Main-Hub-Lieferverträge und ihre Items. Historische
434-Mio.-ISK-Zeilen dürfen dabei von einer aktuellen 402-Mio.-ISK-Rechnung
abweichen und bleiben unverändert.

Prüfung: Die neuen fokussierten Regressionen für vollständige Refining-
Bereitschaft sowie konsistente Routenhinweise bestanden. Der vollständige
isolierte SwiftPM-Lauf baute Core und App und bestand 358 Swift-Testing-Tests
in 25 Suites sowie 8 XCTest-Fälle. Striktes Swift-Format und beide
Lokalisierungskataloge bestanden; der unsignierte native Xcode-Debug-Build
endete erfolgreich. Keine Live-ESI- oder Marktanfrage wurde ausgeführt.

Offen: Die tatsächliche Refining-Gebühr der Tatara muss der Owner aus EVE
übernehmen und danach den Plan neu berechnen. Die visuelle Laufzeitprüfung des
neuen Status- und Vertragsbereichs, der Abgleich mit aktuellen Main-Hub-Orders,
Providerpreis, Tastatur, VoiceOver, CPU/RSS und ausdrückliche Owner-Abnahme
bleiben offen.

## 2026-08-15 – Jump-Freighter-Transport zum Coalition Hub

Ziel: Die Route vom Home Hub zum Coalition Hub sollte nicht länger mit dem
allgemeinen Kurierpreis berechnet werden. Stattdessen sollte ein auswählbarer
Jump Freighter mit aktuellem Pilotenkönnen, einer realen Sprungroute und dem
vorgegebenen Durchschnittspreis aller vier Isotope bewertet werden.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-jump-freighter-logistics.tar.gz`
  gesichert; das geprüfte Archiv hat SHA-256
  `b0343bbb394cdbbe1ceea1efe4a3599f8f4fc42dbd2ca7eb19fbd78be32c5156`;
- eine eigene unveränderliche Jump-Freighter-Domäne für Schiff, Isotop,
  Pilotenwahl, Skills, DOTLAN-Route, Flugladung, vier Preisnachweise und
  Gesamtkosten ergänzt. Ältere Profile und Plan-Snapshots bleiben durch
  optionale Felder und sichere Standardwerte lesbar;
- die Laufzeitkoordination löst Home- und Coalition-Hub-Systeme über ESI auf,
  verwendet nur frische geeignete Charakter-Skills, lädt den passenden
  DOTLAN-Plan und die vier Main-Hub-Isotopenorderbücher. Planner erhält nur
  unveränderliche Quellensnapshots und startet selbst keine Netzwerkanfrage;
- Produkte werden in ganzen Einheiten auf die sichtbare nutzbare Kapazität je
  Einwegflug verteilt. Die DOTLAN-Menge pro Flug wird mit der Fluganzahl und
  dem arithmetischen Mittel aus Helium, Oxygen, Nitrogen und Hydrogen Isotopes
  bewertet. Fehlende Daten bleiben unverfügbar; übergroße Einzelitems verlangen
  weiterhin einen manuellen Transport;
- die Industrieeinstellungen um Aktivierung, Schiff, automatische oder feste
  Pilotenwahl und nutzbare Kapazität ergänzt. Die Coalition-Strategie zeigt die
  vollständige Route, Skills, Kraftstoff, vier Preise, Mittelwert, Flüge und
  konkrete Frachtpositionen; sämtliche EVE-Namen verwenden die gemeinsame
  Kopierinteraktion;
- Production-Basis, Architektur, Handoff, Acceptance-Matrix und aktuelle
  Anwenderdokumentation an den neuen Quellennachweis angepasst.

Ergebnis: Nach Aktivierung ersetzt die Jump-Freighter-Gesamtsumme den normalen
Kurierpreis ausschließlich auf Route 2 zum Coalition Hub. Der bisherige
Kurierweg bleibt bei deaktivierter Option unverändert. Die Standardkapazität
von 350.000 m³ ist ausdrücklich nur eine änderbare Fit-Annahme; Rückflugtreibstoff
ist nicht enthalten.

Prüfung: Acht fokussierte Core-Tests decken URL-Aufbau, aktuellen DOTLAN-HTML-
Parser, die Ablehnung widersprüchlicher Isotop-, Summen- und Volumennachweise,
automatische Pilotenwahl, ganzzahlige Flugaufteilung, Vier-Isotopen-Mittelwert,
fehlenden Preis und historische Dekodierung ab. Die vorhandene
Drei-Hub-Regression belegt zusätzlich, dass der neue Betrag alle Coalition-
Strategien erreicht. Der öffentliche DOTLAN-Plan für Ark 5/5/5 von UALX-3 nach
C-J6MT wurde am 15. August 2026 live gelesen: drei Sprünge, 20,314 Lichtjahre
und 44.690 Helium Isotopes pro Flug. Der vollständige isolierte SwiftPM-Lauf
baute Core und App und bestand 366 Swift-Testing-Tests in 26 Suites sowie 8
XCTest-Fälle. Striktes Swift-Format, beide Lokalisierungskataloge, doppelte
Lokalisierungsschlüssel, die Xcode-Projektdatei und `git diff --check`
bestanden; der unsignierte native Xcode-Debug-Build endete mit
`BUILD SUCCEEDED`.

Offen: Es wurden keine privaten Skills und keine aktuellen Main-Hub-Preise des
Owners live abgefragt. Auswahl des tatsächlich verwendeten Schiffs/Piloten,
nutzbare Fit-Kapazität, Abgleich der Route und Kraftstoffmenge, Rückflugpolicy,
visuelle Prüfung, Tastatur, VoiceOver, CPU/RSS und ausdrückliche Owner-Abnahme
bleiben getrennt offen.

## 2026-08-15 – Gebaute Capitals springen selbst zum Coalition Hub

Ziel: Ein im Plan fertiggestelltes sprungfähiges Capital durfte nicht als
Fracht des konfigurierten Jump Freighters behandelt werden. Jede gebaute Hülle
sollte ihre eigene Strecke und ihren eigenen Treibstoffbedarf erhalten.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-capital-self-jump.tar.gz`
  gesichert; SHA-256
  `f847d0181f7fb372196132447c3b5a8ecc75bc91e3b67a5ac39117773467b67b`;
- eine explizite Selbstsprung-Policy für Carrier-, Dreadnought-, Force-
  Auxiliary-, Supercarrier-, Titan-, Capital-Industrial- und
  Jump-Freighter-Gruppen ergänzt. Ein gewöhnlicher Freighter bleibt außerhalb
  dieser Policy;
- Capital-Produkte vor der Frachtaufteilung aus dem Cargo entfernt. Runtime
  lädt je Produkttyp eine eigene DOTLAN-Route mit dem exakten Typnamen und
  JDC/JFC; Planner multipliziert die Isotopenmenge dieser Route mit der Zahl der
  fertiggestellten Hüllen;
- die bisherigen Jump-Freighter-Flüge für alle übrigen Produkte unverändert
  beibehalten und beide Kostenbestandteile mit demselben aktuellen
  Vier-Isotopen-Mittelwert zusammengeführt. Fehlende Selbstsprungdaten bleiben
  blockierend und fallen weder auf Fracht, Kurierkosten noch 0 ISK zurück;
- Strategieansicht und Industrieeinstellungen um getrennte Capital-Hüllen,
  Pilot, Sprungabschnitte, Isotop, Menge je Hülle, Gesamtmenge und Kosten
  ergänzt. Gerenderte EVE-Namen verwenden die gemeinsame Kopierinteraktion;
- Fachvertrag, Architektur, Handoff und Anwenderdokumentation an die neue
  Grenze zwischen Fracht und selbstspringender Hülle angepasst.

Ergebnis: Ein gebauter Jump Freighter, eine Rorqual oder ein anderes durch die
Policy als selbst sprungfähig ausgewiesenes Capital belegt keine
Frachterkapazität. Bei zwei gebauten Hüllen wird derselbe verifizierte
Einweg-Sprungplan zweimal berechnet. Ist die Sprunglogistik deaktiviert oder
fehlt eine Route, bleibt die Coalition-Rentabilität unverfügbar. Die konkrete
Hull-Command-Berechtigung des ausgewählten Charakters ist noch kein
automatischer Nachweis und bleibt als Owner-Abgleich offen.

Prüfung: 13 fokussierte Sprunglogistiktests und alle 29 Industry-Planner-Tests
bestanden. Sie decken insbesondere die Rorqual-URL mit Skillziffern `550`, den
beibehaltenen DOTLAN-HTML-Nachweis, Capital-Piloten ohne Jump-Freighters-Skill,
Hüllenmultiplikation, Gruppengrenze, historische Dekodierung und die
Planner-Regression ab, in der die Rorqual trotz eines vorhandenen
Jump-Freighter-Routensnapshots ausschließlich als Selbstsprung berechnet wird.
Der öffentliche DOTLAN-Plan für Rorqual JDC 5/JFC 5 von UALX-3 nach C-J6MT
wurde am 15. August 2026 live gelesen: drei Sprünge, 20,314 Lichtjahre und
40.627 Oxygen Isotopes je Hülle.

Der vollständige isolierte SwiftPM-Lauf baute Core und App und bestand 371
Swift-Testing-Tests in 26 Suites sowie 8 XCTest-Fälle. Striktes Swift-Format
der geänderten Swift-Dateien, beide Lokalisierungskataloge, die
Xcode-Projektdatei und `git diff --check` bestanden. Der unsignierte native
Xcode-Debug-Build endete mit `BUILD SUCCEEDED`.

Offen: Private Skilldaten, tatsächliche Hull-Command-Berechtigung, aktuelle
Main-Hub-Preise, visueller Abgleich, Tastatur, VoiceOver, CPU/RSS und
ausdrückliche Owner-Abnahme bleiben getrennt offen.

## 2026-08-15 – Feste Sprungroutenprofile je Capital-Klasse

Ziel: Die Route vom Home Hub zum Coalition Hub sollte wahlweise als konkrete,
vom Owner festgelegte Folge direkter Sprünge berechnet werden. Jump Freighter,
Carrier, Dreadnought, Force Auxiliary, Supercarrier, Titan und Capital
Industrial sollten dieselbe Route bewusst teilen oder jeweils ein eigenes
Profil erhalten können.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-fixed-capital-routes.tar.gz`
  gesichert; SHA-256
  `dccea5f8788339435687e1a140a4d349f1ab7777043e3b52d0911d27d4dff73b`;
- persistierbare Sprungroutenprofile mit geordneten ESI-Sonnensystemen und
  optionalen Cyno-Struktur- oder Einsatzortnamen ergänzt. Die sieben
  Schiffsklassen besitzen getrennte Zuordnungen; mehrere dürfen ausdrücklich
  dieselbe Profil-ID verwenden. Alte Profile dekodieren ohne erfundene
  Zuordnung als automatische DOTLAN-Route;
- bei einem festen Profil jeden Abschnitt zwischen Home Hub, Zwischenpunkten
  und Coalition Hub einzeln für das tatsächliche Schiff und den gewählten
  Piloten geladen. Nur genau ein passender direkter DOTLAN-Sprung wird
  akzeptiert; Lichtjahre und Isotope werden über die geprüften Abschnitte
  addiert;
- unvollständige, gelöschte, nicht direkte oder außerhalb der Reichweite
  liegende Profile als blockierend behandelt. Es gibt keinen stillen Rückfall
  auf automatische DOTLAN-Routenwahl, Fracht, Kurierkosten oder 0 ISK;
- die Industrieeinstellungen um Profilpflege, Zwischenpunkte und Zuordnung je
  Klasse ergänzt. Die Strategiedetails zeigen automatische oder feste Quelle,
  Profil, kopierbare Systeme und Cyno-Orte sowie jeden gespeicherten
  DOTLAN-Abschnitt;
- Produktionsvertrag, Architektur, Handoff, Acceptance-Matrix und
  Anwenderdokumentation an die feste Routenquelle angepasst.

Ergebnis: Der Owner kann wenige gemeinsame Routenprofile pflegen und trotzdem
für jede Klasse einzeln bestimmen, ob sie ein Profil oder automatische
Routenwahl verwendet. Ein gemeinsam genutztes Profil wird nicht pauschal als
passend angenommen, sondern für jede konkrete Hülle und den Piloten erneut
geprüft. Cyno-Namen dokumentieren den Einsatzort, beeinflussen aber weder
Reichweite noch Treibstoff.

Prüfung: 18 fokussierte Sprunglogistiktests bestanden. Sie decken insbesondere
geteilte und getrennte Klassenzuordnungen, Löschbereinigung, historische
Dekodierung, geordnete direkte Teilstrecken, gespeicherte Profil-/Cyno- und
Quellnachweise, Ablehnung unterbrochener Routen und Capital-Treibstoff ab. Der
vollständige isolierte SwiftPM-Lauf baute Core und App und bestand 376
Swift-Testing-Tests in 26 Suites sowie 8 XCTest-Fälle. Striktes Swift-Format,
beide Lokalisierungskataloge, die Xcode-Projektdatei und `git diff --check`
bestanden; der unsignierte native Xcode-Debug-Build endete mit
`BUILD SUCCEEDED`.

Offen: Es wurde noch kein tatsächlich gewünschtes festes Routenprofil des
Owners eingegeben oder live mit jeder Hüllenklasse abgeflogen. Cyno-Zugang,
Hull-Command-Berechtigung, aktuelle Isotopenpreise, Rückflugpolicy, visuelle
Prüfung, Tastatur, VoiceOver, CPU/RSS und ausdrückliche Owner-Abnahme bleiben
getrennt offen.

## 2026-08-15 – Planner-Eingabe und SDE-Baum wiederverwenden

Ziel: Wiederholte Planner-Berechnungen mit derselben Produktliste sollten nicht
mehrfach dieselbe Eingabe parsen, Produkttypen auflösen und den gleichen
rekursiven SDE-Baum für Marktbedarf und Capital-Erkennung durchlaufen.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-15-pre-planner-speed.tar.gz`
  gesichert; SHA-256
  `7a6c85b98a95ef2cef7045ac8d9e945317f7cdc2f1e923d73d179d7001a98b84`;
- `IndustryPlannerInputPreparation` ergänzt. Ein Durchlauf löst wiederholte
  Produktnamen einmal auf, besucht gemeinsam verwendete Produktionszweige
  einmal und liefert Markt-Typen, angeforderte Produkte und selbstspringende
  Capitals gemeinsam;
- die eigentliche Kalkulation an dieselbe vorbereitete Request-/Typ-Zuordnung
  angebunden. Der geführte Produktionsweg verwendet sie für Referenz- und
  Auswahlplan ebenfalls erneut;
- in `RuntimeState` einen bewusst auf genau einen Eintrag begrenzten Cache
  ergänzt. Sein Schlüssel enthält SDE-Build, SDE-Inhaltshash, exakten
  Eingabetext sowie Compressed-Ore- und Sprungtreibstoffoption. Änderungen
  ersetzen den Eintrag; Markt, Assets, Gebühren, Routen und Ergebnis-Snapshots
  bleiben aktuelle Berechnungseingaben;
- einen deterministischen Query-Count-Test ergänzt, der zwei gleiche
  Produktzeilen vorbereitet und berechnet, ohne die zugrunde liegende
  Typauflösung, Definition, Benennung oder Klassifikation zu wiederholen.

Ergebnis: Die erste Berechnung bereitet weiterhin den vollständigen benötigten
Graphen vor. Folgeberechnungen desselben Entwurfs, etwa nach einer Lager- oder
Make-or-Buy-Änderung, überspringen diese unveränderte SDE-Vorarbeit. Fachliche
Mengen, Preise, Logistik und explizite unbekannte Zustände bleiben unverändert.

Prüfung: Die fokussierte Performance-Suite bestand fünf Tests. Der neue Test
belegt je genau einen zugrunde liegenden Aufruf für Produktname, Definition,
Typname und Klassifikation trotz zweier gleicher Eingabezeilen und
anschließender Planung. Alle 29 Industry-Planner-Tests bestanden. Der
synthetische Marktbenchmark blieb fachlich identisch und lag bei rund 70 ms für
vier unvorbereitete Quote-Pässe gegenüber rund 19 ms Vorbereitung plus rund
13 ms für vier vorbereitete Pässe. Der vollständige isolierte SwiftPM-Lauf
bestand 377 Swift-Testing-Tests in 26 Suites sowie acht XCTest-Fälle. Der
native, unsignierte Xcode-Debug-Build wurde nach mehreren Minuten ohne weiteren
Buildfortschritt abgebrochen; macOS hielt die ausgelagerten Projektdateien bei
der Bereitstellung fest. Das ist keine erfolgreiche native Build-Evidenz und
auch kein gemeldeter Swift-Compilerfehler. Striktes Swift-Format, beide
Lokalisierungskataloge, die Xcode-Projektdatei und der auf diese Änderung
begrenzte `git diff --check` bestanden.

Offen: Die tatsächliche Verbesserung eines tiefen Plans mit der gefüllten
Produktionsdatenbank ist noch nicht in der laufenden App gemessen. CPU, RSS,
erste gegenüber wiederholter Laufzeit sowie visuelle, Tastatur-, VoiceOver- und
Owner-Abnahme bleiben getrennt offen.

## 2026-08-15 – Logistik als eigener Arbeitsbereich und flüssigere Routeneingabe

Ziel: Die Kurier-, Jump-Freighter- und festen Capital-Routen sollten nicht mehr
in den Industrieeinstellungen verborgen sein. Die als hakelig und langsam
empfundene Routeneingabe sollte auf ihre konkrete Ursache geprüft und
entsprechend entlastet werden.

Entwicklung:

- den gemischten Checkout vor der Änderung außerhalb des Arbeitsverzeichnisses
  unter `/private/tmp/EVE-NEXUS-SIMPLE-backup-20260815-0100.tar.gz` gesichert;
  SHA-256
  `38fe706ffa5e3560a522535dd70cc17c4f159376a2c7fe08eb8a75629e6f1d55`;
- `Logistik` als eigenen etablierten Eintrag der Hauptnavigation ergänzt und
  die beiden Logistikbereiche aus **Industry Settings** entfernt. Compressed
  Ore Refining bleibt als Produktions-/Refining-Einstellung in Industrie;
- die Logistikseite auf einen kompakten lokalen Entwurf umgestellt. Änderungen
  an Tarif, Frachtraum, Pilot, Profilnamen, Wegpunkten und Cyno-Orten publizieren
  dadurch nicht mehr bei jedem Tastendruck die vollständige `ProductionBasis`
  und bauen nicht die große Industrieeinstellungsansicht neu auf. Erst ein
  erfolgreicher Persistenzvorgang übernimmt den Entwurf; Abbrechen und ein
  fehlgeschlagenes Speichern erhalten den letzten gespeicherten Stand;
- die zweite Verzögerungsquelle beseitigt: Der bisherige erste Suchbegriff
  musste den vollständigen öffentlichen ESI-Sonnensystemindex samt
  Namensauflösung erst aufbauen. **Logistik** startet diesen geteilten Index nun
  beim Öffnen im Hintergrund. Die interaktive Darstellung ist auf 50 Treffer
  begrenzt, der vollständige Cache bleibt erhalten, und vorhandene Treffer
  verschwinden während einer Folgesuche nicht mehr;
- unbekannte Hubnamen bleiben als `Nicht konfiguriert` sichtbar und werden
  nicht als erfundener kopierbarer EVE-Ortsname ausgegeben;
- Anwenderdokumentation, Architekturvertrag, Production-Basis-Vertrag,
  Acceptance-Matrix und deutsche/englische Lokalisierung aktualisiert.

Ergebnis: Logistik ist unabhängig von Industrie auffindbar und pflegbar. Die
Routenbearbeitung verursacht deutlich weniger SwiftUI-/Observable-Arbeit, und
der unvermeidliche erste öffentliche ESI-Indexaufbau beginnt vor der ersten
Eingabe. Fehler beim Indexaufbau löschen keine vorhandene Route und erzeugen
keinen erfundenen leeren oder kostenlosen Transportzustand.

Prüfung: Der fokussierte Core-Test belegt, dass das Vorwärmen genau den
öffentlichen GET-/POST-Indexaufbau ausführt und die anschließende begrenzte
Suche keine weitere Anfrage erzeugt. Der fokussierte App-Test belegt den neuen
etablierten Navigationspunkt. Der vollständige isolierte SwiftPM-Lauf baute
Core und App und bestand 379 Swift-Testing-Tests in 26 Suites sowie acht
XCTest-Fälle. Striktes Swift-Format, beide Lokalisierungskataloge und
`git diff --check` bestanden. Der native unsignierte Xcode-Debug-Build mit
isoliertem DerivedData endete mit `BUILD SUCCEEDED`. Es wurden keine privaten
ESI-Daten oder Live-DOTLAN-Routen abgerufen.

Offen: Die wahrgenommene Geschwindigkeit muss mit den tatsächlich gepflegten
Routen in der laufenden, befüllten App verglichen werden. Visuelles Layout,
Tastatur, VoiceOver, CPU/RSS, aktuelle ESI-Netzlaufzeit und ausdrückliche
Owner-Abnahme bleiben getrennt offen.

## 2026-08-15 – Planer 2: schlanker Gewinnvergleich und gemeinsame Rechenbeschleunigung

Ziel: Einen klar getrennten, experimentellen Planungsweg mit sehr wenigen
sichtbaren Eingaben, sofort vergleichbarem Gewinn/ROI und einer direkt
nutzbaren Einkaufsliste bereitstellen. Gleichzeitig sollten die langen
Produktions- und Make-or-Buy-Berechnungen aller Planner ohne Änderung der
etablierten Markt-, Gebühren-, Rundungs- oder Produktionsregeln weniger
doppelte Arbeit ausführen.

Entwicklung:

- den bereits gemischten Checkout vor der Änderung vollständig außerhalb des
  Arbeitsverzeichnisses unter
  `/private/tmp/EVE-NEXUS-SIMPLE-backup-2026-08-15_20-27-14_CEST.zip`
  gesichert; der ZIP-Test bestand, Größe `337198059` Byte, SHA-256
  `146e87bda11286cc76626a94f771ddde425a9f9b75acf580d5103f2876eb2db1`;
- das bisherige geführte Experiment als **Planer 2 (Experiment)** klar vom
  etablierten Planner benannt. Item und Menge sind die sichtbaren
  Haupteingaben; ME/TE bleiben in **Erweiterte Produktionswerte** erreichbar;
- die erste Ergebnisstufe auf Gewinn und ROI für alle verfügbaren Main- und
  Home-Hub-Verkaufswege reduziert. Ein Klick öffnet erst dann Erlös, Kosten,
  Steuern, Gebühren, Logistik, Jobs und Dauer. Vorläufige oder unvollständige
  Ergebnisse sind bereits auf der eingeklappten Karte bezeichnet;
- EVE-Ortsnamen im geöffneten Detail bewusst als getrennte
  `EVEEntityText`-Kopierziele umgesetzt, damit Kopieren nicht gleichzeitig die
  Ergebnis-Karte schließt;
- die Einkaufsliste unmittelbar unter den Gewinnkarten sichtbar gemacht. Sie
  benennt Main Hub und Produktionsziel, zeigt zu kaufende Typen und Einheiten
  und verwendet für Anzeige und Multibuy-Export dieselbe endgültige,
  gegebenenfalls durch Compressed Ore ersetzte Einkaufsliste;
- die etablierten Katalogverträge um gebündelte Abfragen für Namen,
  Industrieklassifikationen und verpackte Volumen ergänzt. Vorbereitung und
  Logistik laden unterschiedliche Typen dadurch gesammelt und der vorhandene
  Memoisierungskatalog speichert auch gebündelte Treffer und Fehlwerte;
- Referenz- und Auswahlrechnung innerhalb desselben unveränderlichen
  Planungsdurchlaufs entdoppelt: Eine Make-or-Buy-Analyse wird nur bei exakt
  gleicher benötigter Menge, SDE-Version, Regelversion und Markt-Snapshot-ID
  wiederverwendet. Ein geänderter Markt-Snapshot berechnet neu;
- nur Planer 2 darf Gewinn und ROI vor noch ungeklärten Bauplankosten als
  ausdrücklich **vorläufig** anzeigen. Der etablierte Planner und rekursive
  Produktionswege behalten ihre bisherige strikte Kostenvollständigkeit;
- die bestehende Marktakquise sowie Preis-, Gebühren-, Rundungs-,
  Produktions- und Einkaufsregeln nicht umgebaut; Anwenderdokumentation,
  Architektur, Handoffs und Acceptance-Matrix aktualisiert.

Ergebnis: Planer 2 ist eine sitzungsgebundene, deutlich ruhigere
Vergleichsansicht und verändert weder den aktiven Plan noch die
Produktionsübersicht. Die gemeinsame Planungsengine vermeidet wiederholte
Metadaten-, Volumen- und identische Make-or-Buy-Arbeit, sodass auch der
etablierte Planner von der Rechenentlastung profitiert. Fehlende Bauplan-,
Routen-, Gebühren- oder Marktdaten bleiben ausdrücklich sichtbar und werden
nicht als null angenommen.

Prüfung: Die fokussierte Query-Efficiency-Suite bestand sechs Tests. Der neue
Regressionstest belegt Wiederverwendung bei identischem Snapshot und eine neue
Quote-ID nach geändertem Snapshot. Der synthetische Quote-Test blieb fachlich
gleich und maß in diesem Lauf rund 71 ms für die unvorbereitete Vergleichslast
gegenüber rund 19 ms Vorbereitung plus rund 13 ms für die vorbereitete Last;
dies ist kein Messwert einer befüllten App. Die vollständige isolierte
SwiftPM-Aktion baute Core und App und bestand 380 Swift-Testing-Tests in 26
Suites sowie acht XCTest-Fälle. Die native, unsignierte Xcode-Testaktion baute
die App und bestand 359 Tests in 23 Suites mit `TEST SUCCEEDED`. Striktes
Swift-Format, beide Lokalisierungskataloge, die Prüfung auf doppelte
Lokalisierungsschlüssel und `git diff --check` bestanden.

Offen: Die tatsächliche Laufzeit eines tiefen Plans mit der befüllten
Produktionsdatenbank wurde nicht gemessen. Vergleich von erster und
wiederholter Berechnung, CPU/RSS, visuelles Layout, Größenänderung, Tastatur,
VoiceOver, Live-Marktwerte und ausdrückliche Owner-Abnahme bleiben getrennt
offen.

## 2026-08-16 – Aufgelöste Refining-Ausgaben und kostenneutraler Lagerüberschuss

Ziel: Der Planner zeigte bei `Compressed Bountiful Loparite` die bekannte
Scandium-Type-ID 16639 als „Nicht aufgelöster Mineraltyp“. Zugleich sollte
eindeutig belegt und sichtbar werden, dass nicht benötigte Raffinerieausgaben
ins Lager gehen, aber keine Kostengutschrift für das hergestellte Produkt
erzeugen.

Entwicklung:

- den vollständigen gemischten Checkout einschließlich `.git` und lokaler
  Buildablage vor der Änderung unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-16-152103-pre-refining-surplus-fix-full.tar`
  gesichert; das lesbare 1,0-GB-Archiv hat SHA-256
  `5bfd174975285067efb114123a3992026e7a38f756eb876270559f3e5e01b594`;
- für jede konkrete Raffinerieausgabe den SDE-Namen, Gesamtmenge, im aktuellen
  Plan verwendete Menge und geplanten Lagerüberschuss im unveränderlichen
  Snapshot ergänzt. Alte Ausgaben ohne diese optionalen Felder bleiben lesbar;
- den bisherigen Namensabruf von den aktuell benötigten Mineralpositionen auf
  alle Ausgaben der geprüften Erzoptionen erweitert. Damit werden auch reine
  Nebenprodukte wie Scandium aufgelöst und über die gemeinsame kopierbare
  EVE-Typdarstellung ausgegeben. Ein tatsächlich nicht auflösbarer SDE-Typ
  bleibt mit Type-ID, Menge und ausdrücklicher Warnung erhalten;
- die Planner-Oberfläche um die getrennten Angaben **In diesem Plan verwendet**
  und **Geplanter Lagerüberschuss** sowie den Kostenhinweis ergänzt. Der
  geplante Zugang verändert keinen faktischen ESI-/Asset-Snapshot;
- die bestehende Kostenregel unverändert explizit abgesichert: Nur verwendete
  Ausgaben reduzieren direkte Mineralbedarfe. Nebenprodukt und
  Chargenüberschuss erhalten keine Wertgutschrift; vollständiger Erzeinkauf,
  Transport und Refining-Gebühr bleiben im Produkt;
- `dokumentation.md`, Architektur-, Production-Basis-, Handoff- und
  Acceptance-Vertrag sowie deutsche und englische Lokalisierung aktualisiert.

Ergebnis: Eine neu berechnete Loparite-Raffineriezeile zeigt Scandium statt der
rohen Type-ID. Jede Ausgabe trennt Gesamtmenge, Planverbrauch und den in das
Lager einzuplanenden Rest, ohne diesen Rest gegen die Produktkosten zu rechnen.

Prüfung: Der lokale aktive SDE-Katalog Build `3466501` wurde ausschließlich
lesend geprüft. Er löst Type-ID 16639 als **Scandium** auf und enthält für
`Compressed Bountiful Loparite` Hydrocarbons, Scandium, Platinum und Promethium.
Der fokussierte Refining-Test und anschließend alle 34 Industry-Planner-Tests
bestanden. Der vollständige isolierte SwiftPM-Lauf baute Core und App und
bestand 400 Swift-Testing-Tests in 26 Suites sowie 11 App-XCTest-Fälle, 411
Tests insgesamt. Striktes Swift-Format, beide Lokalisierungskataloge und die
begrenzte Diff-Whitespace-Prüfung bestanden. Die ersten beiden nicht isolierten
beziehungsweise verschachtelt gesandboxten Versuche endeten vor der
Kompilierung am globalen Modulcache beziehungsweise `sandbox_apply`; der
identische erlaubte isolierte Lauf bestand.

Offen: Die betroffene gespeicherte alte Berechnung wird nicht still mit neuen
Regeln umgeschrieben. Sie muss in der laufenden App neu berechnet und danach mit
dem EVE-Reprocessing-Fenster verglichen werden. Visuelles Layout bei enger und
weiter Breite, Tastatur, VoiceOver, native Xcode-/Signierungsprüfung und
ausdrückliche Owner-Abnahme bleiben getrennt offen.

## 2026-08-16 – Reaktionen im Main-Hub-Chancen-Katalog

Ziel: Vollständige veröffentlichte Reaktionsprodukte wie `Hypnagogic Neurolink
Enhancer` fehlten im Main-Hub-Chancenbereich, obwohl Dashboard und
Reaktionsanalyse sie kannten. Der sichtbare Filter **Reaktionen** klassifizierte
nur bereits vorhandene Manufacturing-Zeilen nach Namen und aktivierte keine
SDE-Reaktionsdefinitionen.

Entwicklung:

- vor der Änderung den aktuellen Quell- und Git-Arbeitsstand einschließlich
  unversionierter Dateien unter
  `/private/tmp/EVE-NEXUS-SIMPLE-2026-08-16-162159-pre-market-reaction-opportunities-worktree.tar`
  gesichert; nur die reproduzierbaren beiden `.build`-Caches und die seit der
  geprüften Vollsicherung von 15:21 unveränderte `.git/objects`-Ablage wurden
  ausgelassen. SHA-256:
  `2318b6afd0b194e6b07e0a77667a41a897e91c368338867e4dfcbb21ea0a6d14`;
- den Chancen-Scan um vollständige `reactionDefinitions()` ergänzt und den
  ausgewählten Reaktionsanlagen-Kontext samt Reaktions-Systemkostenindex in die
  unveränderliche Analyse übergeben;
- die vorhandene Reaktionslogik für Materialmultiplikator, Run-Rundung, Dauer
  und EIV-Installation als gemeinsame Produktionskostenprojektion
  wiederverwendet. Reaktionen erhalten keine Manufacturing-ME-/TE-Regeln und
  keine Blueprint-Umlage;
- die Zeilenaktivität optional und rückwärtskompatibel gespeichert. Alte
  Chancen-Snapshots ohne Aktivität bleiben als Manufacturing lesbar;
- den Produktfilter **Reaktionen** an die tatsächliche SDE-Aktivität gebunden.
  Reaktionszeilen zeigen ME/TE als nicht anwendbar, lassen Runs weiter ändern
  und projizieren diese Änderung mit Reaktionsrundung;
- vollständige Produkte ohne aktive Main-Hub-Verkaufsorder nicht mehr aus dem
  Katalog entfernt. Erlös und abhängige Gewinnwerte bleiben mit blockierender
  Ursache unverfügbar;
- UI-Texte, deutsche und englische Lokalisierung, Dokumentation,
  Architektur-, Handoff-, Production-Basis- und Acceptance-Vertrag
  aktualisiert.

Ergebnis: Nach einem neuen Main-Hub-Update sind die 119 im aktiven SDE
veröffentlichten Reaktionsformeln grundsätzlich Teil des Chancen-Snapshots.
Hypnagogic, Meta-Operant und andere Molecular-Forged Materials werden über ihre
Reaktionsaktivität gefiltert. Ihre Markt-Chancen-Zeile berechnet den möglichen
Verkaufserfolg getrennt vom Make-or-Buy-Wert der Reaktionsanalyse.

Prüfung: Die fokussierte Market-Browser-Suite bestand 40 Tests; der separate
Reaktionsvertrag bestand 7 Tests. Der vollständige isolierte SwiftPM-Lauf baute
Core und App und bestand 401 Swift-Testing-Tests in 26 Suites sowie 11
App-XCTest-Fälle, insgesamt 412 Tests. Das verschachtelte EVEStaticDataKit
bestand sieben deterministische Tests; der ausdrücklich optionale Real-SDE-Test
wurde ohne Paketpfad übersprungen. Striktes Swift-Format, beide
Lokalisierungskataloge und die begrenzte Diff-Whitespace-Prüfung bestanden. Der
erste nicht isolierte Versuch scheiterte vor der Kompilierung am gesperrten
globalen Modulcache, der zweite am verschachtelten SwiftPM-Sandbox; die in
beschreibbare lokale Pfade gelegten identischen Läufe bestanden. Der aktuelle
unsigned Xcode-Versuch scheiterte zunächst vor der Kompilierung an gesperrten
Caches; der freigegebene identische Lauf blieb nach dem Aufruf ohne normalen
Buildfortschritt und wurde beendet. Er ist weder Erfolg noch Compilerfehler.

Offen: Ein neuer Main-Hub-Live-Scan wurde nicht gestartet. Nach **Update** müssen
Hypnagogic und Meta-Operant in der laufenden App gesucht und Materialien,
Installation, Dauer, Gewinn sowie Reaktionsfilter gegen Reaktionsanalyse und
EVE verglichen werden. Visuelles Layout, Sortierung, Tastatur, VoiceOver,
native Xcode-/Signierungsprüfung und Owner-Abnahme bleiben getrennt offen.

## 2026-09-24 – Gesicherter lokaler Neustart nach Neuinstallation

Ziel: Nach ausdrücklich freigegebenem Neustart den vorhandenen Projektstand
weiterverwenden und die App mit einem neuen EVE-Datenspeicher betreiben.

Durchgeführt:

- Originalprojekt ausschließlich als Quellbasis verwendet; keine Swift-, Paket-
  oder Xcode-Projektdateien verändert und das Vollbackup unverändert belassen.
- Die drei gefundenen Store-Kandidaten an Kopien geprüft: SQLite intakt, jedoch
  fremdes leeres Modell `APIRequestModel`. Keine EVE-Altdaten wiederhergestellt.
- Einen frischen Schema-v2-Store isoliert erzeugt und geöffnet. Den bisherigen
  App-Datenordner vor Aktivierung unter
  `~/Library/Application Support/com.local.EVENexusSimple.vor-Neustart-20260924-223323`
  unverändert gesichert; Dateihashes nach dem Wechsel bestätigt. Die globale
  `default.store` blieb unangetastet.
- Die getestete native App unter `~/Applications/EVE Nexus Simple.app` lokal
  ad-hoc signiert installiert; tiefe strikte Signaturprüfung bestanden.
- Offizielles CCP-SDE 3542233 über die vorhandene Download-, Validierungs-,
  Staging- und Aktivierungsstrecke installiert. Katalogadapter v4 enthält
  53.060 Typen, 5.082 Blueprints und 19.138 Aktivitäten. Die 21 unaufgelösten
  Typreferenzen bleiben als Quelldatenbefund erhalten. Es gab keinen alten
  SDE-Katalog, für den eine separate SDE-Rollbacksicherung anzulegen war.
- Dashboard ohne Wiederherstellungsfehler geöffnet; die SDE-Seite zeigt den
  installierten Build und bestätigt nach Updateprüfung die Aktualität.
  Persönliche Charaktere sind noch nicht angemeldet. Die ESI-Seite ist für
  die Anmeldung geöffnet; automatische Vertrags- und Main-Hub-Scans pausieren.

Prüfung: Xcode 27.0 / Swift 6.4, macOS arm64. Isolierter SwiftPM-Lauf:
416 bestandene Tests und ein zunächst übersprungener Real-SDE-Test.
Nativer Xcode-Debuglauf: 383 bestandene Tests und ein zunächst übersprungener
Real-SDE-Test. Separates StaticDataKit: sieben bestanden, ein Real-SDE-Test
zunächst übersprungen. Anschließend wurden beide unterschiedlichen Real-SDE-
Tests mit dem tatsächlich heruntergeladenen Paket gesondert ausgeführt
und bestanden (je ein Test; SQLite-Aktivierung und Paket-Mapping). Frischer Store startet mit Exit 0,
der fremde Altstore reproduziert an einer Kopie den Migrationsfehler 134504.

Offen: Persönliche EVE-SSO-Anmeldung, Charakter-Synchronisation und anschließende
Anlagen-/Markt-/Logistik-Konfiguration sowie fachliche Owner-Abnahme. Der
Neustart ist keine Wiederherstellung früherer lokaler Pläne. Der bekannte
Legacy-Import ohne Modellzuordnungsprüfung wurde nicht im Quellcode verändert.

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

## 24. September 2026 – Abgeschnittene Kopfmenüs korrigiert

Fehler: Mit vorbereiteter Vertragsdatenbank verschoben sich der oberste
Navigationseintrag und die Einstellungsreiter unter die Titelleiste. Der
Navigationsbereich maß im 1077 Punkte hohen Fenster 1305,5 Punkte und begann
bei y = -88. Die mehrzeilige, vertikal fest dimensionierte Statusmeldung
wurde für die Mindestgrößenberechnung mit zu geringer Breite gemessen.

Änderung: `PublicContractSidebarStatus` begrenzt seine Messbreite auf die
bestehende minimale Seitenleistenbreite von 180 Punkten. Die Darstellung bei
normaler Breite bleibt erhalten. Fenstermaximierung und native Titelleiste
bleiben unverändert. Die Komponente ist für den Layout-Regressionstest
modulintern zugänglich.

Prüfung: `sidebarStatusMinimumMeasurementDoesNotInflateWindowHeight` scheitert
mit dem bisherigen Layout (752 Punkte minimale Fußleistenhöhe gegenüber rund
102 Punkten bei Seitenleistenbreite) und besteht mit der Korrektur. Alle
13 Tests von `RuntimeFeatureStateTests`, der isolierte native Xcode-Build und
striktes `swift-format` für beide geänderten Swift-Dateien bestehen.
Visuell durch Codex geprüft: Kopfmenüs und oberster Navigationseintrag im
maximierten Fenster sowie im kleinen Fenster (901 × 539 Punkte) erreichbar;
bei kleiner Höhe scrollt die Seitenleiste. Der korrigierte Navigationsbereich
misst bei maximiertem Fenster 1077 Punkte und beginnt bei y = 0.

Die lokal signierte App wurde unter
`/Users/svenstolze/Applications/EVE Nexus Simple.app` aktualisiert und mit den
vorhandenen drei Charakteren gestartet. Die Einstellungsreiter sind in der
installierten Version sichtbar. Die vorherige App liegt gesichert im
Arbeitsordner der Wiederherstellungsaufgabe unter
`work/layout-fix/previous-app/EVE Nexus Simple.app`. Während des Austauschs
blieben die Datenbankdateien nach SHA-256-Vergleich unverändert. Quellbackup,
App-Daten und Schlüsselbund wurden nicht zurückgesetzt.

Offen: Abnahme durch den Nutzer und ein breiterer Layout-Check aller Module.
Im kleinen Einstellungsfenster ist weiterhin die vorhandene Darstellung der
Schriftgrößen-Auswahl zu eng; dies betrifft nicht die korrigierte Kopfmenü-
Verschiebung.

## Konsolidierungsnachweis 25.09.2026

SwiftPM 417 bestanden / 1 Skip, Kit 7 / 1, Xcode Build erfolgreich und native Tests
385 / 1. Nur opt-in Real-SDE-Skips; keine Fachlogikänderung durch die Konsolidierung.
Originalarbeitsbäume samt Git und Index recoverbar archiviert. Technische und
historische Namensausnahmen sowie die nicht integrierten Nexus-Komponenten sind
im Konsolidierungsbericht offen ausgewiesen. Kein neues Feature geplant.


## 25.09.2026 – Fachliche Konsolidierung nach Checkpoint 182f1a9

Der ausdrücklich freigegebene Implementierungsauftrag ersetzt die frühere Beschränkung auf
organisatorische Zusammenführung. Vorhandene Projekt-, Lager-/CSV-, Reservierungs-, Preis-/Einkaufs-,
Wissenschafts-, Beleg- und Sicherungsabläufe sind in die aktive App integriert. SwiftData V3 ist
additiv; alte Snapshots und technische Identitäten bleiben erhalten. CSV-Parser und ISK-Werttyp
wurden aus der Legacy-Quelle adaptiert, UI-/Persistenzkonflikte über aktive Adapter aufgelöst.
Die entfernte Finanzansicht, alte Datenbankimporte und nur geplante Vorhaben bleiben ausgeschlossen.

Bei der Prüfung wurden insbesondere macOS-Pfadkanonisierung und temporäre SQLite-Begleitdateien
in Sicherungen, centgenaue Journalteilbeträge, veraltete Vorschauen, Archivstatus und konkrete
Wissenschaftsdauern abgesichert. Nachweise und verbleibende Live-/Owner-Grenzen stehen in
[FUNCTIONAL_VALIDATION.md](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md).
Es folgt kein automatischer Featureauftrag.

Abschlussnachtrag 25.09.2026: Vorschauen zeigen zusätzlich konkrete gespeicherte Mengen/Beträge;
fehlender SDE-Katalog wird verständlich erklärt. Isolierter nativer Bedien-Smoketest mit Projekt,
Lager, Wissenschaftssperre, Verkaufsbeleg-Einstieg und geprüfter Sicherung durchgeführt.
V2-Wiederherstellung nach absichtlich unvollständiger V3-Initialisierung ergänzt. Letzte sichtbare
Altbezeichnungen in den Berechtigungserklärungen bereinigt. Finale Zahlen: SwiftPM 451 bestanden +
1 opt-in Skip, Kit 7 + 1, native Core-Tests 415 + 1; Details und Legacy-Einzelfehler im aktuellen Prüfbericht.

Legacy-Nachprüfung: 715 Fälle bestanden, ein alter Architektur-/UI-Texttest mit sieben Assertions
zur ausdrücklich entfernten Finanzansicht. Nur dessen großer Accounts-Bildschirm wurde in der
temporären Testkopie wegen einer Compilergrenze ausgeklammert; keine Testdatei oder Archivquelle geändert.
Die sieben Aussagen sind in LEGACY_TEST_DISPOSITIONS einzeln eingeordnet. Finale Reservierungsvorschauen
bewahren außerdem die manuelle Herkunft eines ohne ESI gerechneten Plans und verlangen frische ESI-Daten.


## 25.09.2026 – Lokale Release-App und separate DEV-Datenkopie

Auf ausdrücklichen Folgeauftrag normale `.app` und `-DEV.app` unter `dist/` erstellt.
DEV ist ein Export desselben aktiven Projekts, kein zweiter Quellprojektstand. Ein kleiner
Paketstarter prüft die eingebettete Datenkopie und übernimmt sie beim ersten Start atomar
in einen eigenen Datenordner. Eigene Bundle-ID, UserDefaults-Domäne und Schlüsselbunddienst
halten DEV-Schreibzugriffe getrennt; produktive Identitäten bleiben unverändert.
Der lokale Schlüsselbund wird nicht exportiert. DEV-Live-Abfragen erfordern erneute Anmeldung.

Release- und nativer Debug-Build erfolgreich. SwiftPM: 452 bestanden + 1 optionaler Skip;
EVEStaticDataKit: 7 + 1; native Tests: 416 + 1. Der neue Test prüft DEV-Schlüsselbundabfragen
und unveränderte produktive Dienstnamen. Synthetischer Pakettest prüft committed WAL-Inhalte,
Erststart, isolierte Daten/Einstellungen und tatsächliche Bundle-ID nach dem Start, Erhalt von
DEV-Änderungen beim Wiederstart sowie Ablehnung beschädigter Seeds und unvollständiger Ziele.
Bei dieser Prüfung wurden macOS-Pfadkanonisierung und das explizite Schließen der temporären
SQLite-Sicherungen abgesichert. Prüfprotokolle: `/private/tmp/eve-dev-*.log`, natives Ergebnis
`/private/tmp/eve-dev-native-tests.xcresult`.

Finaler Datenexport: 29 Dateien einschließlich Einstellungen, 437.424.810 Bytes, fünf
konsistente SQLite-Sicherungen einschließlich der lokalen Katalog- und Sicherungsdateien.
Originaldaten und Einstellungen vor/nach Export identisch geprüft; Schlüsselbund nicht gelesen.
Die finale private Datenkopie wurde nicht für Funktionstests gestartet. Starter und App wurden
mit ausschließlich synthetischen Daten geprüft. Lokale Ad-hoc-Signatur; keine Notarisierung,
keine Installation über die bestehende App, kein Live-Service-Test und keine Nutzerabnahme.
Details und reproduzierbare Prüfung: [DEV_EXPORT.md](Documentation/DEV_EXPORT.md).


Exportnachtrag: Die fertigen Apps liegen unter `~/Downloads/`. Der File Provider ergänzte im
synchronisierten Dokumente-Ordner wiederholt Finder-Metadaten an den Frameworks und störte damit
die strikte Signaturprüfung. Beide Pakete wurden deshalb aus `dist/` an den lokalen Zielort
verschoben und dort erneut geprüft. Es wurde kein ZIP-/Cloud-Archiv angelegt; `dist/` enthält
nur Build-Metadaten. Die installierte produktive App wurde nicht ersetzt.


## 25.09.2026 – DEV-Startfehler und native Fensterzuordnung korrigiert

Nutzerbefund: „DEV-Einstellungen sind nicht lesbar.“ Die eingebettete und bereits kopierte
Einstellungsdatei waren intakt. macOS liefert bei `UserDefaults(suiteName:)` für die eigene
Bundle-ID keinen zusätzlichen Einstellungsbereich. Die bisherigen Tests verwendeten eine
abweichende Smoke-Domäne und deckten den normalen Erststart deshalb nicht vollständig ab.
Der neue synthetische Test reproduzierte den identischen Fehler mit eigener Bundle-Domäne;
`.standard` löst ihn ohne Datenersetzung.

Die anschließende native Prüfung deckte zusätzlich eine fehlerhafte LaunchServices-Zuordnung
beim `exec`-Wechsel vom Hilfsstarter auf: Der UI-Prozess lief, wurde aber mit PID -1 zugeordnet.
DEV übernimmt die Daten jetzt über `DevelopmentAppBootstrap` vor dem Erzeugen der SwiftUI-App
im tatsächlichen App-Executable. Der zusätzliche Starter entfällt. Standard- und DEV-Domänen,
Schlüsselbundtrennung und Datenpfade bleiben erhalten. `AppDefaults` behandelt ebenfalls die
eigene Bundle-ID ausdrücklich als Standarddomäne. Keine fachlichen Berechnungen verändert.

Prüfung: SwiftPM 452 bestanden + 1 opt-in Skip, Kit 7 + 1, native Tests 416 + 1; Release- und
Debug-Build erfolgreich. Erweiterter synthetischer Pakettest prüft zehn Grenzen einschließlich
nativer Executable-Zuordnung, eigener Bundle-Domäne, gemischter Property-List-Typen, Wiederaufnahme
eines unterbrochenen Einstellungsimports und Erhalt geänderter DEV-Einstellungen bei Neustart.
Protokolle: `/private/tmp/eve-dev-own-domain-red.log`, `eve-dev-native-entry-export-checks.log`,
`eve-dev-native-entry-tests.log`, `eve-dev-start-fix-kit-tests.log`, `eve-dev-native-entry-debug.log`,
`eve-dev-native-entry-release.log`; natives Ergebnis `/private/tmp/eve-dev-native-entry.xcresult`.

Die Programmdateien der DEV-App unter Downloads wurden aktualisiert und lokal neu signiert.
Vorherige Programmdateien liegen lokal unter
`/private/var/folders/ss/lwz_fgl94c36jczpz9p9vq8h0000gn/T/eve-dev-code-before-native-fix-yihxc7x_`.
Eingebettete Daten und die bereits angelegte DEV-Arbeitskopie wurden nicht ersetzt. Die normale
App wurde nicht aktualisiert oder beendet. Regulärer Start über Finder anschließend beobachtet:
DEV-Hauptfenster „Dashboard“ erreichbar, kopierte Charakter- und Bestandsdaten sichtbar,
keine Startfehlermeldung. Keine neue Anmeldung durchgeführt; Live-Zugriffe nicht abgenommen.


## 25.09.2026 – Einstellungsreiter unter der Titelleiste stabilisiert

Nutzerbefund: Die obere Bereichsauswahl schwankte in ihrer Höhe und verschwand
teilweise unter dem Fensterrahmen. In der laufenden DEV-App auf Allgemein und ESI
sichtbar nachvollzogen. Die bisherige Geschwister-VStack reservierte den oberen
sicheren Bereich nicht für die Reiter; der innere Scrollbereich berücksichtigte
den Fensterabstand separat.

`SettingsWorkspaceLayout` reserviert die Navigation mit `safeAreaInset` oberhalb
des Seiteninhalts. `DataSettingsNavigationBar` behält ihre Eigenhöhe, erstreckt den
Hintergrund über die verfügbare Breite und verwendet unverändert Reiter bzw. die
bestehende kompakte Menüauswahl. Keine festen Titelleisten-Pixelabstände eingeführt.
Berechnungen, Einstellungen, Datenpfade und Anmeldung bleiben unverändert.

Automatische Prüfung mit synthetischen Daten: SwiftPM 454 bestanden + 1 opt-in Skip,
EVEStaticDataKit 7 + 1, native Core-Tests 416 + 1; Xcode Debug und Release erfolgreich.
Neue UI-Geometrieprüfungen: Eigenhöhe bei 420/900/2300 Punkten Breite und 80/1300
Punkten Angebotshöhe; Reiter unter der nativen Toolbar bei 2555 × 1300 und
900 × 540 Punkten. Die ursprüngliche Überdeckung trat im vereinfachten nativen
Testfenster nicht auf; diese Tests sind zusätzliche Layoutabdeckung, kein
behaupteter automatischer Rot-/Grün-Nachweis. Protokolle liegen lokal unter
`/private/tmp/eve-settings-layout-{tests,kit,debug,release,native-tests}.log`.

Die bestehende DEV-App unter Downloads wurde aktualisiert, signiert und regulär
geöffnet. Reiter auf Allgemein, ESI und Industrieeinstellungen vollständig sichtbar;
maximiertes Fenster (Screenshot 2560 × 1357) und Bildschirmviertel (1281 × 679),
Seitenwechsel sowie Scrollen geprüft. Anschließend ESI und ursprüngliche Fenstergröße
wiederhergestellt. Vorherige Programmdateien für Rücknahme:
`/private/tmp/eve-dev-code-before-layout-fix-1790330772`.

Seed einschließlich Manifest (30 Dateien) und vorhandene DEV-Arbeitskopie
(38 Dateien) direkt vor/nach Programmaustausch per SHA-256 unverändert. Keine
Benutzerdaten in Tests oder Git übernommen. Normale App nicht ersetzt oder beendet.
Keine Live-Service-Abnahme oder Nutzerabnahme behauptet. Keine weiteren offenen
Probleme in dieser Layoutkorrektur; weitere Funktionsarbeit ist nicht Bestandteil.


## 25.09.2026 – Geprüften Build auf normale App übertragen

Auf ausdrücklichen Benutzerauftrag den bereits geprüften Release-Build des Quellstands
`8beff4ce2bd2b439b0c621a69e4f504a07e44b05` auf die normale App unter Downloads übertragen.
Keine Codeänderung und kein zusätzlicher Datenexport. Bisherige App regulär beendet und
lokal unter `/private/tmp/eve-normal-build-before-layout-j520kqe9/` zur Rücknahme gesichert.
Paket mit unveränderter produktiver Bundle-ID lokal signiert; strikte Signaturprüfung
bestanden. Alle 38 vorhandenen Daten-/Einstellungsdateien waren unmittelbar vor/nach
Austausch per SHA-256 identisch. DEV-App bei dieser Übertragung unverändert.

Normale App anschließend regulär geöffnet: Dashboard vorhanden, Allgemeine Einstellungen
zeigen die Reiter vollständig unterhalb der Titelleiste. Die erfolgreichen Debug-/Release-
Builds und Tests der vorherigen Korrektur gelten für denselben unveränderten Build;
keine erneuten Fachtests mit Benutzerdaten durchgeführt. `dist/BUILD_INFO.json` aktualisiert.
Keine offenen Übertragungsprobleme, keine neue Funktionsplanung oder Live-Service-Abnahme.


## 26.09.2026 – Market Browser aus der Navigation entfernt

Auf Nutzerauftrag den eigenständigen Market Browser vollständig aus der
Hauptnavigation und aus den sichtbaren Modulhinweisen der ESI-Berechtigungen
entfernt. Der Dashboard-Hinweis bezeichnet die verbleibenden Abläufe nur noch
als Marktanalysen. Planner, Main-Hub-Chancen sowie Moon- und
Mineralien-Kaufanalyse behalten ihre bestehenden gemeinsamen Markt-, Struktur-
und Preisroutinen; Berechnungsregeln, Datenpfade und Berechtigungen wurden nicht
verändert.

Ein App-Test sichert ab, dass `marketBrowser` nicht mehr als primärer
Navigationsfall vorhanden ist. Der vollständige isolierte SwiftPM-Lauf besteht
mit 455 Tests; der ausdrücklich opt-in Real-SDE-Test bleibt wie vorgesehen
übersprungen. Das separate `EVEStaticDataKit` besteht mit 8 Tests einschließlich
dieses vorgesehenen Skips. Der native, unsignierte Xcode-Debug-Build endet mit
`BUILD SUCCEEDED`. Die vorhandenen Build-Ausgaben im synchronisierten
Projektpfad trugen zunächst Finder-/Resource-Fork-Metadaten; deshalb liefen die
erfolgreichen Prüfungen mit isolierten temporären Build-Verzeichnissen. Keine
Live-ESI- oder Nutzerabnahme behauptet.


## 26.09.2026 – Rekursive Produktionskalkulation entfernt

Auf Nutzerauftrag den eigenständigen Bereich „Rekursive Kalkulation“ aus der
Hauptnavigation und dem App-Build entfernt. Ebenfalls entfernt wurden dessen
dedizierter EVE-Zeilenimport, die erzwungene Vollproduktion herstellbarer
Zwischenprodukte, die besondere Main→Home-/Rückroutenprojektion, die
Produktionsbuch-Rekonstruktion und der separate Runtime-Einstieg.

Planner und Main-Hub-Chancen behalten den gemeinsamen rekursiven
Produktionsgraphen, Lager-/Reservierungslogik, Blueprintquellen, ME/TE,
Reaktionsformeln, Markt-, Installations- und Logistikberechnung. Der vom
Planner-Parametereditor weiterhin benötigte lokalisierte Zahlenparser wurde
neutral benannt und mit eigenem Regressionstest erhalten. Die laufende bzw.
installierte DEV-App wurde in diesem Schritt nicht ersetzt.

Der vollständige isolierte SwiftPM-Lauf besteht mit 450 Tests. Das separate
`EVEStaticDataKit` besteht mit 8 Tests einschließlich des vorgesehenen
opt-in Real-SDE-Skips. Beide Lokalisierungskataloge sind gültig; der native,
unsignierte Xcode-Debug-Build endet mit `BUILD SUCCEEDED`. Keine Live-ESI-,
installierte-App- oder Nutzerabnahme behauptet.


## 26.09.2026 – Eigenständige Industriejobs-Ansicht entfernt

Auf Nutzerauftrag den eigenständigen Bereich „Industriejobs“ aus der
Hauptnavigation und dem App-Build entfernt. Die ausschließlich dort verwendete
sortierbare Jobtabelle mit Status-/Aktivitätsfiltern, eigener Standortauflösung
und ihren Textressourcen wurde ebenfalls entfernt.

Die ESI-Jobabfrage, Quellzustände und per Charakter gespeicherten Job-Snapshots
bleiben erhalten. Das Dashboard integriert weiterhin Slot-Auslastung,
Aktivitätskapazitäten, bereite und bevorstehende Jobs; der vollständige
Dashboard-Refresh synchronisiert die Jobdaten weiterhin manuell und beim ersten
Aufruf eines App-Laufs. Nettowert behält aktive Fertigungs- und Reaktionsjobs
für die geschätzte laufende Produktion. Der Berechtigungsdialog nennt dafür nun
Dashboard und Nettowert statt des entfernten Bereichs. Die laufende bzw.
installierte DEV-App wurde nicht ersetzt.

Der vollständige isolierte SwiftPM-Lauf besteht mit 450 Tests. Das separate
`EVEStaticDataKit` besteht mit 8 Tests; beide Läufe enthalten nur den
vorgesehenen opt-in Real-SDE-Skip. Die deutschen und englischen
Lokalisierungskataloge sind gültig, und der native unsignierte Xcode-Debug-Build
endet mit `BUILD SUCCEEDED`. Keine Live-ESI-, installierte-App- oder
Nutzerabnahme behauptet.


## 27.09.2026 – Preisprofile und Sicherung in Einstellungen integriert

Auf Nutzerauftrag den gemeinsamen Toolbar-Einstieg „Preisprofile & Sicherung“
und die beiden eigenständigen Bereiche der Projektverwaltung entfernt. Manuelle
Preisprofile einschließlich Gültigkeit, Einzelpreisen, CSV-Import und
Bestätigungsvorschau sind nun direkt in den Markteinstellungen eingebettet.
Lokale Sicherung, Prüfung, vorbereitete Wiederherstellung, anonymisierter
Diagnoseexport und letzte Importberichte liegen in den allgemeinen Einstellungen.

Die zugehörigen Fachmodelle und Verträge bleiben erhalten: Projektzuweisungen
verwenden weiterhin manuelle Preisprofile, aktive Marktpreise bleiben der
Standard, und Wiederherstellungen werden weiterhin geprüft beim nächsten
App-Start ausgeführt. Automatische Sicherheitskopien für Migrationen und
SDE-Aktualisierungen wurden nicht verändert. Die laufende beziehungsweise
installierte DEV-App wurde in diesem Schritt nicht ersetzt.

Der vollständige isolierte SwiftPM-Lauf besteht mit 450 Tests. Das separate
`EVEStaticDataKit` besteht mit 8 Tests einschließlich des vorgesehenen opt-in
Real-SDE-Skips. Der native unsignierte Xcode-Debug-Build endet mit
`BUILD SUCCEEDED`; die einzige fachfremde Compiler-Warnung bleibt die bereits
bekannte TaskLocal-Abkündigung im ESI-Client. Keine Live-ESI-, installierte-App-
oder visuelle Nutzerabnahme behauptet.


## 27.09.2026 – Projektverwaltung in Planner-Abläufe integriert

Auf Nutzerauftrag den Toolbar-Einstieg „Projekte & Einkauf“ und den gemeinsamen,
bereichsumschaltenden Dialog „Projektverwaltung“ entfernt. Projektwahl und
-einstellungen sind jetzt unmittelbar im Planner sichtbar beziehungsweise
einklappbar. Nach einer Berechnung erscheinen Reservierungen bei der
Lagerverwendung sowie Einkaufsbudget und -fortschritt direkt nach der
Einkaufsliste. Manuelle Lager, Wissenschaftsaufträge und Verkaufsbelege bleiben
ausschließlich über ihre fachlich passenden Arbeitsbereiche erreichbar.

Die Fachmodelle und Funktionen bleiben erhalten: Projektlebenszyklus,
Lagerfreigaben, Preisprofilzuweisung, Kostenersatzwerte, persistente
Reservierungen, Konfliktauflösung, Budget, Teilkäufe und Exporte verwenden
weiterhin denselben `ConsolidationWorkspace`. Der Planner aktualisiert den für
Reservierungen erforderlichen ESI-Bestand weiterhin über seinen vorhandenen
Bestandsablauf. Eine Regression sichert ab, dass Projekte, Reservierungen und
Einkauf nicht erneut als Bereiche des gemeinsamen Dialogs erscheinen.

Der vollständige isolierte SwiftPM-Lauf besteht mit 450 Tests. Das separate
`EVEStaticDataKit` besteht mit 8 Tests einschließlich des vorgesehenen opt-in
Real-SDE-Skips. Der native unsignierte Xcode-Debug-Build endet mit
`BUILD SUCCEEDED`; die einzige fachfremde Compiler-Warnung bleibt die bereits
bekannte TaskLocal-Abkündigung im ESI-Client. Keine Live-ESI-, installierte-App-
oder visuelle Nutzerabnahme behauptet.


## 27.09.2026 – Wallet in das Dashboard integriert

Auf Nutzerauftrag den eigenständigen Wallet-Eintrag aus der Hauptnavigation und
die separate Wallet-Ansicht entfernt. Die Finanzsektion des Dashboards zeigt
weiterhin den verfügbaren Gesamtsaldo und jetzt zusätzlich je Charakter den
Quellzustand, den letzten Aktualisierungszeitpunkt, eine gezielte
Wallet-Aktualisierung und den unmittelbar zugehörigen Fehlerzustand. Der
Dashboard-Gesamtsync bleibt der gemeinsame Weg zur Aktualisierung aller
privaten Finanz-, Bestands- und Jobdaten.

Die bestehenden Wallet-Verträge und Routinen bleiben erhalten:
`WalletPortfolioSnapshot` summiert ausschließlich verfügbare Werte,
`CharacterWalletService` führt den gezielten ESI-Abruf aus, der letzte bekannte
Wert wird bei einem fehlgeschlagenen Abruf bewahrt und Snapshot-Metadaten werden
weiterhin zusammen mit dem Charakterstand gespeichert. Eine
Navigationsregression sichert ab, dass Wallet nicht erneut als eigenständiger
Bereich erscheint. Die laufende beziehungsweise installierte DEV-App wurde in
diesem Schritt nicht ersetzt.

Der vollständige isolierte SwiftPM-Lauf besteht mit 450 Tests. Das separate
`EVEStaticDataKit` besteht mit 8 Tests einschließlich des vorgesehenen opt-in
Real-SDE-Skips. Beide Lokalisierungskataloge sind gültig. Der native
unsignierte Xcode-Debug-Build endet mit `BUILD SUCCEEDED`; die einzige
fachfremde Compiler-Warnung bleibt die bereits bekannte TaskLocal-Abkündigung
im ESI-Client. Keine Live-ESI-, installierte-App- oder visuelle Nutzerabnahme
behauptet.


## 29.09.2026 – Horizontales Einstellungsmenü stabilisiert

Das horizontale Menü unter „Daten & Einstellungen“ ist nun ausschließlich an
die verfügbare Breite der Detailspalte gebunden. Zuvor konnte insbesondere der
intrinsisch breite ESI-Inhalt die Vermessung des oberen `safeAreaInset`
verbreitern und die Navigation unter die Sidebar verschieben. Ein
`GeometryReader` begrenzt jetzt sowohl den Seiteninhalt als auch den
Inset-Inhalt auf den realen Detailspaltenrahmen; überbreiter Inhalt wird an
dieser Grenze abgeschnitten, ohne Auswahlzustand, Navigationstitel oder
Datenlogik zu verändern. Bei ausreichender Breite bleibt der segmentierte
Picker zentriert, bei wenig Platz greift weiterhin die kompakte Menüauswahl.

Ein neuer Geometrietest vergleicht normale und absichtlich 4.000 Punkte breite
Seiteninhalte bei 900 × 540 und 2.555 × 1.300 Punkten. Er sichert ab, dass die
Navigation in beiden Fällen dieselben horizontalen Grenzen besitzt und nicht
aus der Detailspalte herausragt. Der vollständige isolierte SwiftPM-Lauf
besteht mit 451 Tests. Das separate `EVEStaticDataKit` besteht mit 8 Tests
einschließlich des vorgesehenen opt-in Real-SDE-Skips. Der native unsignierte
Xcode-Debug-Build endet mit `BUILD SUCCEEDED`; die native Xcode-Testaktion
besteht mit 412 Tests und `TEST SUCCEEDED`. Die bekannte fachfremde
TaskLocal-Abkündigung im ESI-Client bleibt unverändert.

Für die Sichtprüfung wurde eine isolierte, frisch gebaute Debug-App mit
getrenntem Datenverzeichnis verwendet. Alle sechs Einstellungsbereiche wurden
mehrfach gewechselt. Zusätzlich wurde die Sidebar ein- und ausgeblendet sowie
von 220 über 480 bis auf 1.600 Punkte verbreitert. Das Menü blieb jeweils in
der Detailspalte; bei der extrem schmalen Detailspalte erschien wie vorgesehen
die kompakte Auswahl. Die installierte DEV-App und reale ESI-Nutzerdaten wurden
nicht verändert.

## 02.10.2026 – Review-Fehler korrigiert und vollständige Wiederherstellung ergänzt

Auf Nutzerauftrag drei konkret reproduzierte Fehler im aktiven Projekt korrigiert:
Die Legacy-Übernahme veröffentlicht erst einen vollständigen WAL-bewussten
SQLite-Snapshot. Der Planner berechnet Zwischenprodukte nur für gekaufte und
aus dem Lager verbrauchte Mengen, wodurch der Teilbestandsfall 23 statt 38 ISK
ergibt und mit Übersicht sowie neuer Historie übereinstimmt. Das ESI-Kennzeichen
für Blueprint-Kopien bleibt durch Synchronisierung und Speicherung erhalten;
Kopien werden ausgeschlossen, unbekannte ältere Werte bleiben sichtbar unvollständig.

Die zusätzlich freigegebene vollständige Wiederherstellung aktiviert nach Neustart
und ausdrücklicher Bestätigung ausschließlich den gewählten früheren SwiftData-Bestand.
Beide Stände bleiben gesichert; es wird nicht zusammengeführt. Datensperre,
Unterprozess-Sperrerhalt, Modell-/Nutzdatenprüfung und ein dauerhaftes
Austauschprotokoll mit geprüfter Rücknahme schützen den Vorgang. Die aktuelle
V3-Kette wurde statt der veralteten Planannahme V2 verwendet. Vorhandene lokale
Dokumentations- und Konfigurationsänderungen wurden erhalten; kein Commit oder
Push durchgeführt.

Der vollständige isolierte SwiftPM-Lauf besteht mit 477 Fällen: 476 bestanden,
ein vorgesehener Real-SDE-Skip. Das separate Kit besteht mit 7 von 8 Fällen
plus einem Skip. Der native unsignierte Debug-/Testlauf endet mit
`TEST SUCCEEDED` (430 bestanden, ein Skip). Isolierter nativer Start und
separater V3-Prüfprozess sind erfolgreich. Quellen, gezielte Abbruch-/WAL-/
Migrations-/Bewertungsregressionen und verbleibende Grenzen stehen im
[Prüfnachweis](Documentation/REVIEW_FIXES_2026-10-02.md).

GPT-6.1 Sol High übernahm Kosten, Blueprint-Datenfluss, UI/Lokalisierung,
Regressionen und native Dateizuordnung; GPT-Astra High übernahm die komplexe
Wiederherstellung und ihre unabhängige Prüfung. Dabei entdeckte Lücken beim
Sperrerhalt des Prüfprozesses und bei bekannten JSON-Einstellungssnapshots wurden
vor dem erfolgreichen Abschluss korrigiert. Fremde gültige SQLite-Dateien werden
vor SwiftData zurückgewiesen. Live-, visuelle, vollständige VoiceOver- und
Eigentümerabnahmen bleiben offen; produktive Daten und installierte Apps wurden
nicht als Fixtures verwendet.

## 17.10.2026 – Kompaktes Dashboard mit gemeinsamen Analyseergebnissen

Der freigegebene Dashboardplan ist lokal umgesetzt. Unter der Kapazität stehen
abholbereite Jobs, die nächsten 48 Stunden und die fünf offenen Produktionsjobs
mit dem höchsten Rohstoffwert. Die ersten beiden Listen zeigen fünf Einträge
und lassen sich vollständig öffnen. Wallet- und Nettowertdetails sind zunächst
zugeklappt; das Finanzlayout verteilt die Breite 1:2 zugunsten des 280 Punkte
hohen Graphen. Schmale Fenster stapeln die Karten. Zeit- und Wertbeschriftungen
haben eigenen Platz; auch ein einzelner Nullwert wird auf seiner Wertachse
korrekt positioniert.

Die bestehende Produktionsbewertung liefert Einzeljobwerte an Top 5 und
Vermögenssumme. Fehlende Preise bleiben außerhalb der Rangfolge und sichtbar
unvollständig. Die Reaktionskarte verwendet alle negativen Ergebnisse des
gemeinsamen Snapshots mit dessen Markt, Runs und tatsächlichem Transportziel.
Ihr Detailknopf übergibt einen einmaligen Negativfilter. Die beiden
Einkaufsanalysen bereiten je Material eine gemeinsame Kaufempfehlung vor;
Dashboard, Detailansicht und Mineralienticker konsumieren diese Ergebnisse.
Der separate Tageshistorienabruf des Tickers ist entfernt. Identische laufende
Aktualisierungen werden geteilt, geänderte Kontexte nacheinander abgearbeitet
und Ergebnisse innerhalb von fünf Minuten wiederverwendet. Konfigurationsfremde
Ergebnisse werden nicht als aktuelle Empfehlungen dargestellt.

Abschließende Prüfung des fertigen Quellstands:

- Vollständiges SwiftPM: 39 App-Tests und 427 Core-Tests erfolgreich.
- Separates `EVEStaticDataKit`: 8 Tests erfolgreich.
- Nativer macOS-arm64-Debug-Build und Xcode-Tests erfolgreich; Ergebnisbericht
  meldet 434 bestandene Tests, keine Fehler und einen übersprungenen opt-in
  Test für ein echtes öffentliches SDE-Paket. Dynamische Parameter ergeben
  zusätzliche Einzelausführungen; die Zahl 434 folgt der Berichtszusammenfassung.
- Synthetische Komponentenansichten mit 0, 5 und 50 Einträgen bei 600, 1000
  und 1440 Punkten Breite gerendert und visuell geprüft; lange Namen, große
  ISK-Beträge, zugeklappte Charakterdetails und Graphbeschriftungen passen.
  Ein anfänglich zu knapp bemessener Testgrenzwert für drei gestapelte
  Aufklappknöpfe wurde korrigiert; der abschließende Lauf ist erfolgreich.
- `git diff --check` und beide Lokalisierungsdateien fehlerfrei geprüft.

Lokale Nachweise: `/private/tmp/eve-dashboard-20261017/swift-final-tests.log`,
`kit-tests.log`, `native-verified-tests.log` und
`native-verified-tests.xcresult` im selben Ordner. Die neun synthetischen
Renderbilder liegen im temporären Systemordner unter
`eve-dashboard-20261017/visual-checks/`.

Bestehende lokale Änderungen wurden erhalten. Das vorhandene Xcode-Projekt
wurde verwendet; diese Dashboardänderung benötigt keine zusätzlichen
Dateizuordnungen oder persistierten Schemas. Produktbeschreibung und Architektur
sind aktualisiert. Keine Veröffentlichung, Installation oder Prüfung mit
produktiven Charakterdaten; echte ESI-/SSO-, vollständige UI-/VoiceOver- und
Eigentümerabnahme bleiben offen. Die native Prüfung verwendete
`CODE_SIGNING_ALLOWED=NO` und ist keine notarierte Release-Auslieferung.

## 17.10.2026 – Aktualisierte Dashboard-App zum Ausprobieren bereitgestellt

Auf ausdrücklichen Wunsch wurde der aktuelle lokale Arbeitsstand als Release
mit dem vorhandenen `EVENexusSimple.xcodeproj` gebaut und separat nach
`/Users/svenstolze/Downloads/EVE New Eden Nexus - Assets, Industry, Markets-Dashboard-2026-10-17.app`
übertragen. Die ältere App vom 15.10.2026 wurde nicht überschrieben. Der Build
enthält HEAD `44d85b4d0bb44b5348e8944f7bd617ec0f7ba7d9` einschließlich der
vorhandenen lokalen Änderungen und des Dashboardumbaus; er stellt keinen
unveränderten Git-Release dar. Keine Codeänderung, kein Commit oder Push im
Rahmen dieses Build-Auftrags.

Der Release-Build endete mit Exit 0. Beide Architekturen `x86_64 arm64`, die
kanonische Bundle-ID, die neuen deutschen Dashboardressourcen sowie die lokale
Ad-hoc-Signatur einschließlich beider eingebetteter Frameworks wurden geprüft.
Ein Start mit separatem leerem Application-Support-Ordner, eigener
Test-Einstellungsdomäne, deaktivierten Hintergrunddiensten und automatischem
Beenden nach dem Öffnen des Test-Stores endete mit Exit 0. Nach dem Übertragen
nach Downloads wurde die vollständige Signatur nochmals erfolgreich geprüft;
der Finder zeigt die neue Datei. Die normale App wurde nicht mit produktiven
Daten gestartet. Beim späteren Nutzerstart verwendet sie die unveränderte
kanonische Datenidentität und damit den vorhandenen Datenstand.

Quelleninventar und erneuter Prüfsummenvergleich belegen unveränderte
Build-Eingaben während der Erstellung. Nachweise liegen unter
`/private/tmp/eve-dashboard-release-20261017.OgLPkU/`: `release-build.log`,
`source-manifest.sha256`, `source-verification.log`, `startup-smoke.log`,
`signature-verification.log` und `app-binary.sha256`.
Xcode gab neben bestehenden Swift-/Simulatorwarnungen eine widersprüchliche
Diagnose über einen Compile-Aufruf mit Exit 0 aus; der Gesamtbuild, die
Paketprüfung und der isolierte Start waren erfolgreich. Die vollständigen
automatischen Tests des Dashboardumbaus wurden im vorigen Schritt bestanden
und bei diesem unveränderten Build-Auftrag nicht erneut ausgeführt.
Die Ausgabe ist lokal signiert, nicht notarisiert; Live-Dashboard- und
Eigentümerabnahme erfolgen durch den Nutzer.

## 17.10.2026 – Drei Marktübersichten direkt nebeneinander

Auf Wunsch stehen negative Reaktionen, Mondmaterialkaufanalyse und
Mineralienkaufanalyse jetzt unter dem Mineralienticker in einer gemeinsamen
Zeile mit drei gleich breiten, oben ausgerichteten Karten. Das vorhandene
responsive Kartenlayout stapelt sie nur bei zu geringer Fensterbreite.
Berechnungen, gemeinsame Datenquellen, Aufklappverhalten und Kopieraktionen
bleiben erhalten. Produktbeschreibung ist aktualisiert; bestehende lokale
Änderungen wurden erhalten.

Die vollständigen SwiftPM-Prüfungen sind erfolgreich (39 App- und 427
Core-Tests), ebenso das separate StaticDataKit (8 Tests) und der native
macOS-Debug-Build mit Tests (434 bestanden, ein opt-in Echt-SDE-Test
übersprungen). Die vorhandenen Layoutprüfungen für das verwendete
Dreispaltenlayout sind enthalten. Nachweise:
`/private/tmp/eve-dashboard-20261017/swift-market-layout-tests.log`,
`kit-market-layout-tests.log`, `native-market-layout-tests.log` und
`native-market-layout-tests.xcresult` im selben Ordner.

Zusätzlich wurde die Universal-Release-App neu gebaut, lokal ad-hoc-signiert
und mit isolierten leeren Testdaten und deaktivierten Hintergrunddiensten
erfolgreich bis zum Öffnen des Stores gestartet. Sie liegt separat als
`/Users/svenstolze/Downloads/EVE New Eden Nexus - Assets, Industry, Markets-Dashboard-2026-10-17-v2.app`
bereit und wurde im Finder angezeigt. Frühere App-Dateien bleiben erhalten.
Build-, Quellen-, Signatur- und Startnachweise liegen unter
`/private/tmp/eve-dashboard-market-layout-20261017.VpHSj3/`.
`git diff --check` ist erfolgreich. Kein Commit, Push oder produktiver
Teststart; die App ist nicht notarisiert. Nutzerabnahme der neuen Anordnung
bleibt offen.

## 19.10.2026 – Übergabe an Claude, neuer Projektordner, Feature-Sperre aufgehoben

Auf Wunsch des Nutzers wird das bisher mit Codex entwickelte Projekt mit Claude
weitergeführt. Anlass für den Umzug: Im iCloud-synchronisierten Ordner
`~/Documents/EVE New Eden Nexus - Assets, Industry, Markets` waren nahezu alle
Quell-, Test- und `.git`-Dateien ausgelagert („nur in iCloud“). Der Nutzer hat
das Projekt nach `/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`
kopiert; das ist der neue einzige Arbeitsstand.

Änderungen (nur Steuerdokumente, kein Code): neuer Pfad in AGENTS, README,
WORKFLOW und PROJECT_STATE; neue `CLAUDE.md`, die `AGENTS.md` einbindet;
MODEL_POLICY nach Werkzeug getrennt (Codex-Vorgabe unverändert, für Claude keine
feste Vorgabe); die Sperre gegen neue Funktionen in AGENTS, WORKFLOW, ROADMAP und
PROJECT_STATE ist aufgehoben – Weiterentwicklung nur auf ausdrücklichen Auftrag.
Datierte Nachweise unter `Documentation/` nennen weiterhin den alten Pfad und
bleiben als historische Belege unverändert.

Prüfung: Im neuen Ordner sind alle 367 Projektdateien lesbar; Git erkennt Branch
`consolidation/2026-09-25-single-source`, HEAD `44d85b4`. Die uncommitteten
Codex-Änderungen (29 geänderte, 4 neue Dateien) sind unverändert erhalten.
Kein Build/Test ausgeführt (Bearbeitung ohne Xcode-Umgebung), kein Commit, kein Push.
Offen: uncommittete Änderungen auf dem Mac prüfen, testen und committen; alte
Kopie unter `~/Documents` umbenennen oder entfernen.

## 19.10.2026 – Uncommittete Codex-Änderungen im neuen Ordner verifiziert

Auftrag: den uncommitteten Stand auf `consolidation/2026-09-25-single-source`
(HEAD `44d85b4`) sichten, Zustand bewerten und das Begonnene abschließen.
Umfang: Review-Fehlerkorrekturen und vollständige Wiederherstellung (02.10.),
kompaktes Dashboard und Marktübersichten (17.10.), Steuerdokumente (19.10.).
Ergebnis: Die Arbeit war inhaltlich abgeschlossen; offen war nur die erneute
Prüfung nach dem Ordnerumzug. Keine Codeänderung nötig.

Prüfung (Claude, Xcode 27.1, Swift 6.4, isolierte Pfade unter
`/private/tmp/eve-claude-verify-20261019/`, eigener Application-Support-Root,
eigene Preferences-Suite, `EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1`):

- SwiftPM `swift test --disable-sandbox`: 427 Core- und 39 App-Swift-Testing-Fälle
  sowie 19 XCTest-Fälle bestanden, ein vorgesehener Real-SDE-Skip; Exit 0
  (`swift-tests.log`).
- `Packages/EVEStaticDataKit`: 8 Fälle, 7 bestanden, ein Real-SDE-Skip
  (`kit-tests.log`).
- Natives `xcodebuild` Scheme `EVENexusSimple`, Debug, macOS arm64,
  `CODE_SIGNING_ALLOWED=NO build test`: `BUILD SUCCEEDED`, `TEST SUCCEEDED`,
  434 bestanden, ein Skip (`native-tests.log`, `native-tests.xcresult`).
- Neue Dateien `StoreFullRestore.swift`, `FullStoreRecovery.swift` und
  `StoreFullRestoreTests.swift` sind in SwiftPM und in den Xcode-Build-Phasen
  enthalten; `git diff --check` fehlerfrei; DE-/EN-Kataloge mit `plutil -lint`
  gültig, ohne doppelte Schlüssel und ohne neue Abdeckungslücken gegenüber HEAD.

Offen: lokaler Commit (nur auf ausdrücklichen Auftrag), Live-ESI-/SSO-,
visuelle, VoiceOver- und Eigentümerabnahme. Kein Push. Anschließend auf
Nutzerauftrag lokal als `90b4cc4` committet. Die alte Kopie hat der Nutzer in
`~/Documents/EVE New Eden Nexus - Assets, Industry, Markets - Alt` umbenannt;
sie ist kein Arbeitsstand.

## 19.10.2026 – Übernahmeprüfung durch Claude auf HEAD `81d258b`

Auftrag: nach der Übernahme von Codex alle Prüfungen isoliert ausführen und den
Arbeitsstand committen. Vorgefunden: Arbeitsbaum sauber, HEAD `81d258b`; die
erwarteten rund 39 uncommitteten Änderungen waren bereits als `90b4cc4`
committet. Keine Codeänderung.

Prüfung (Xcode 27.1, Swift 6.4, macOS arm64; Daten, Preferences-Suite
`com.local.EVENexusSimple.claude-handover-20261019`, Modulcaches, TMPDIR und
DerivedData unter `/private/tmp/eve-nexus-claude-handover-20261019/`,
`EVE_NEXUS_DISABLE_BACKGROUND_SERVICES=1`):

- `swift test --disable-sandbox`: 427 Core- und 39 App-Swift-Testing-Fälle sowie
  19 XCTest-Fälle bestanden, ein Real-SDE-Skip; Exit 0 (`swift-tests.log`).
- `Packages/EVEStaticDataKit`: 8 Fälle, ein Real-SDE-Skip; Exit 0 (`kit-tests.log`).
- `xcodebuild` Scheme `EVENexusSimple`, Debug, `platform=macOS,arch=arm64`,
  `CODE_SIGNING_ALLOWED=NO`: `BUILD SUCCEEDED` (`native-build.log`),
  `TEST SUCCEEDED` mit 434 bestanden, ein Skip (`native-tests.log`,
  `native-tests.xcresult`).
- `git diff --check` fehlerfrei (`diff-check.log`).

Offen: Live-ESI-/SSO-, visuelle, VoiceOver- und Eigentümerabnahme. Kein Push.

## 19.10.2026 – Eigentümerprüfung, Blueprint-Standorte, VoiceOver

Eigentümerprüfung mit dem signierten Debug-Build
`~/Developer/EVE New Eden Nexus Builds/2026-10-19-debug-8961e00/` (Apple
Development, Team `99K5WATB4A`, nicht notarisiert), vorher Datensicherung durch
den Eigentümer: SSO und ESI funktionieren live; Dashboard, Märkte, Kosten und
Blueprint-Kopien in Ordnung.

Fehler: In der Blueprint-Übersicht standen BPO und BPC immer bei „Unbekannter
Ort“. Ursache: `BlueprintsView` nutzte die rohe ESI-`location_id`; bei
Blueprints in Containern, Schiffen oder Büros ist das die Item-ID des Behälters,
und alle IDs ab 10¹² (auch nicht eingerichtete Spielerstrukturen) wurden ohne
Namensquelle verworfen. Korrektur: neue Core-Funktion
`AssetWarehouse.rootLocationsByItemID()` (auch von `ProductionTree` genutzt,
fachlich unverändert); die Übersicht ordnet Blueprints damit über den
Asset-Bestand der Charaktere ihrem Wurzelstandort zu und nimmt den gespeicherten
Strukturnamen, dann die eingerichtete Struktur, dann den öffentlichen ESI-Namen.
Nicht auflösbare Orte bleiben ausdrücklich unbekannt. Neuer Test
`mapsNestedBlueprintItemsToTheirNamedRootStructure` mit synthetischen Daten.

VoiceOver: auf Entscheidung des Eigentümers kein Abnahmeschritt mehr, da es nur
im Hauptmenü zuverlässig funktioniert; Code und Beschriftungen unverändert.

Prüfung (isoliert, `/private/tmp/eve-nexus-claude-bplocations-20261019/`):
SwiftPM 428 Core- und 39 App-Swift-Testing- sowie 19 XCTest-Fälle bestanden, ein
Real-SDE-Skip; Kit 8 Fälle, ein Skip; `xcodebuild` Debug arm64 `BUILD SUCCEEDED`
und `TEST SUCCEEDED` (435 bestanden, ein Skip); `git diff --check` fehlerfrei.

Live geprüft: Mit dem signierten Build
`~/Developer/EVE New Eden Nexus Builds/2026-10-19-debug-8961e00-bplocations/`
(Basis `8961e00` plus diese Korrektur) hat der Eigentümer die korrekten
Blueprint-Standorte bestätigt. Auf Auftrag lokal committet.

Offen: Real-SDE-Tests (opt-in), Tastaturprüfung, Notarisierung. Kein Push.

## 19.10.2026 – Push, Sicherungs-Tag, Arbeitsbranch `main`

Auf Auftrag des Eigentümers: `consolidation/2026-09-25-single-source` per
Fast-Forward nach `origin/main` gepusht (`44d85b4..ce5eb0b`, vorher Suche nach
Tokens und Schlüsseln ohne Fund); lokaler `main` von `c50e005` auf `ce5eb0b`
nachgezogen; annotierter Tag `stand-2026-10-19` auf `ce5eb0b` gesetzt und
gepusht; Konsolidierungsbranch lokal gelöscht (vollständig in `main`
enthalten). AGENTS.md und WORKFLOW.md: Arbeitsbranch `main`; Commit, Push und
Tags nur auf ausdrücklichen Auftrag, weiterhin kein Force-Push und kein
Umschreiben der Historie. Keine Codeänderung, daher kein Testlauf.
Diese Steuerdatei-Änderungen auf Auftrag auf `main` committet und nach
`origin` gepusht.

## 19.10.2026 – Fertigungsprojekte aus dem Planner entfernt

Auftrag des Eigentümers: Den Bereich „Produktionsprojekt“ aus Code, Berechnung und Workflow
entfernen; nur das Produkt eintragen und rechnen lassen. Entscheidungen: Reservierungen und
Einkaufsbudget/-fortschritt ganz entfernen, Wissenschaftsaufträge global, manuelle Lager nicht
einrechnen. Details: `Documentation/Consolidation/DECISIONS.md`.

Umsetzung:
- **Planner:** Ohne Projektpanel sowie ohne Reservierungs- und Einkaufspanel. Die Sperre „Ein aktives
  Fertigungsprojekt auswählen“ ist entfernt. Eingabe und Plan kommen ausschließlich aus
  `StoredPlannerDraft`/`StoredPlan`. Kein projektbezogener Bestandsersatz und keine Reservierungen aus
  Plänen anderer Projekte mehr. Die Wissenschaftsversorgung kommt aus allen nicht archivierten Aufträgen.
- **Core:** Projekt-, Reservierungs-, Konflikt-, Einkaufs- und Budgetlogik entfernt. Die Datenfelder
  bleiben als Altdaten erhalten. `SavedScienceJob.projectID` ist optional. `validate()` prüft keine
  Projektbezüge mehr.
- **Wissenschaftsansicht** ohne Projektauswahl. Preisprofile sind Referenzpreise; der Marktimport
  liest den aktuellen Plan. Diagnoseexport weist Altdaten getrennt aus. Der Erststart legt kein Projekt an.
- **Tests:** Projekt-, Reservierungs- und Budgettests entfernt. Neu sind Altdaten-Roundtrip, globale
  Wissenschaftsreservierungen, Lager-Vorschau, Revisions- und Bestandsinvalidierung ohne Projekte sowie
  Migration ohne Projektanlage.

Prüfung: SwiftPM 422 Core- und 39 App-Swift-Testing- sowie 19 XCTest-Fälle bestanden, ein
Real-SDE-Skip. Kit 8 Fälle bestanden. `xcodebuild` Debug arm64 `TEST SUCCEEDED`. `git diff --check`
fehlerfrei. Hinweis: SwiftPM-Builds scheiterten zunächst am Codesign wegen erweiterter Attribute im
`.build`-Ordner; nach `xattr -cr` auf die Build-Produkte erfolgreich.

Live geprüft: Der Eigentümer hat im Debug-Build aus Xcode eine Ishtar-Berechnung ohne Projekt
bestätigt; BPO/BPC-Quellen und Reaktionsgruppen funktionieren. Auf Auftrag lokal committet.

Offen: Neustart-Wiederherstellung und Wissenschaftsauftrag mit Versorgung nicht gesondert live
geprüft. Weitere Hinweise aus der Live-Prüfung (Finanzübersicht, Sofortverkauf, Compressed-Erze,
belegte BPOs) sind eigene Aufträge.

## 19.10.2026 – Freighter und Jump Freighter als Large Ships

Auftrag des Eigentümers aus der Live-Prüfung: Items sollen an den in den Einstellungen je
Produktklasse festgelegten Stationen gebaut werden; Jump Freighter gehören dabei zu den Large Ships,
nicht zu den Capitals. Eigentümerentscheid: Freighter und Jump Freighter werden „Large“.

Befund: Die Zuordnung je Produktklasse funktionierte. Die feste Einordnung in
`SQLiteStaticCatalog.manufacturingCategory` zählte „Freighter“ und „Jump Freighter“ aber zu
Capital. Dadurch liefen sie an die Capital-Anlage mit Capital-Rig-Boni.

Änderung: Beide Gruppen sind jetzt Large. Die Selbstsprung-Regel (`CapitalSelfJumpPolicy`)
hing zusätzlich an der Kategorie Capital. Sie entscheidet jetzt nur über die sprungfähige
Schiffsgruppe, damit ein gebauter Jump Freighter weiterhin selbst springt. Die Highsec-Regel
für Capitals bleibt im Ergebnis unverändert, weil Frachter dort schon Ausnahmen waren.

Prüfung: Neue Tests zur Einordnung und zum Selbstsprung eines als Large eingeordneten Jump
Freighters. SwiftPM: 423 Core- und 39 App-Swift-Testing- sowie 19 XCTest-Fälle bestanden, ein
Real-SDE-Skip. `xcodebuild` Debug arm64 `TEST SUCCEEDED`. `git diff --check` fehlerfrei.

Offen: Live-Prüfung mit einem Jump Freighter im Planner (Anlage, Rig-Boni, Selbstsprung in der
Logistik). Nicht committet.

## 19.10.2026 – Kein Kauf nicht transportierbarer Items in der Kauf-/Bauanalyse

Auftrag des Eigentümers aus der Live-Prüfung: „Empfehlungen übernehmen“ hat zum Beispiel
Freighter am Main Hub gekauft statt gebaut. Items, die nicht per Jump Freighter oder Vertrag
transportiert werden können, müssen an der Produktionsstation gebaut werden.

Ursache: In der Logistikrechnung wurde ein Item, das verpackt größer als das Transportlimit ist
(bei dir 350.000 m³), nur mit einer Warnung aus der Fracht genommen. Die Kauf-Variante erhielt
dadurch 0 ISK Transport und wirkte günstiger.

Änderung: In `makeOrBuyAnalysis` gilt ein solcher Kauf als unmöglich. Kaufkosten und
Kauflogistik sind nicht verfügbar, die Empfehlung lautet „Bauen“ mit der Warnung
`make-or-buy.purchase-not-transportable`, und die Übernahme setzt das Item auf Bauen. Liegt der
Main Hub an der Anlage selbst, gibt es keinen Transport, und der Kauf bleibt vergleichbar. Eine
manuell gewählte Bezugsart „Kaufen“ wird nicht gesperrt; dort bleibt die bestehende
Logistikwarnung sichtbar.

Prüfung: Der bestehende Kauf-/Bauanalysetest prüft zusätzlich eine 400.000-m³-Komponente
(Empfehlung Bauen, kein Kaufpreis, Übernahme Bauen). SwiftPM: 423 Core- und 39 App-Tests
bestanden, XCTest grün. `xcodebuild` Debug arm64 `TEST SUCCEEDED`. `git diff --check` fehlerfrei.

Offen: Live-Prüfung mit einem Jump Freighter (Freighter als Komponente). Nicht committet.

## 19.10.2026 – Eigene Blueprints mit 0 ISK, Kosten pro Einheit inklusive Lieferung

Befund aus der Live-Prüfung: „Produktionskosten inklusive Lieferung“ war im Ark-Plan nicht
verfügbar, obwohl Zwischensumme (5,25 Mrd. ISK) und Lieferung (348 Mio. ISK) angezeigt wurden.
Ursache: 26 gebaute Knoten mit eigener BPO/BPC ohne eingetragene Kosten. Nach der bisherigen Regel
blieb die Gesamtsumme deshalb unverfügbar. Zwischensumme und Kosten pro Einheit zeigten trotzdem
nur die bekannten Blueprint-Kosten, und „pro Einheit“ rechnete ohne Lieferung, obwohl die Erklärung
„inklusive Lieferung“ sagte.

Eigentümerentscheide:
- Eigene BPOs/BPCs ohne Betrag zählen mit 0 ISK.
- Kosten pro Einheit enthalten die Lieferung.

Änderung:
- `ProductionTreeBlueprintCostProjector` ordnet `useOwnedBPO`/`useOwnedBPC` ohne Betrag eine
  0-ISK-Zuordnung zu. Kopieren, Invention und Käufe brauchen weiterhin einen Betrag.
- Neuer Hinweis `industry.blueprint-owned-counted-zero`.
- `productionCostPerOutputUnit` basiert auf `totalProductionCost`.
- Deutsche Übersetzung der Erklärung ergänzt.

Prüfung: Projektor-Test erweitert (eigene BPO/BPC → 0 ISK; Invention, Kopie und fehlender Blueprint
bleiben ungelöst). Die Kosten-pro-Einheit-Erwartungen in zwei Tests sind auf die neue Regel
umgestellt. SwiftPM: 423 Core- und 39 App-Tests bestanden. `xcodebuild` Debug arm64 `TEST SUCCEEDED`.
`git diff --check` fehlerfrei.

Offen: Live-Prüfung im Ark-Plan. Ob alle 26 Knoten eigene Blueprints sind, zeigt erst diese
Prüfung; ohne Blueprint bleibt die Summe weiter unverfügbar. Nicht committet.

## 19.10.2026 – Nur Standardmineralien, verständliche Planner-Warnungen

Auftrag des Eigentümers aus der Live-Prüfung:
1. Die Mineralien-Kaufempfehlung zeigte 15 Items, darunter seltene Sondermineralien
   (Chromodynamic Tricarboxyls, Neo-Jadarite, Eleutrium, Crystalline Raspite/Polycrase/
   Moissanite/Kangite). Sie spielen im Spiel keine Rolle und sollen verschwinden.
2. Die Planner-Warnungen waren unverständlich (Typ-IDs statt Namen, Informationshinweise
   gemischt mit echten Problemen). Nur entscheidende Warnungen mit echten Namen anzeigen.

Änderung:
- `MaterialPurchaseCatalogKind.includedTypeIDs` beschränkt `.minerals` auf die acht
  Standardmineralien (34–40, 11399); `SQLiteStaticCatalog.materialPurchaseCatalog` filtert
  danach. Analyse, Kaufempfehlung und Dashboard-Ticker nutzen denselben Katalog. Erklärtext
  (de/en) angepasst. Mondmaterialien unverändert.
- `IndustryWarningText.blueprintRunsShort` als gemeinsame Formulierung für
  `industry.blueprint-supply-insufficient-runs` in Planner und Produktionsbaum, mit
  Blueprintnamen statt Typ-ID. Der Planner löst den Namen über den SDE-Katalog auf; ohne
  Namen bleibt „an unresolved Blueprint (type ID …)“ sichtbar.
- `logistics.single-item-volume-exceeded` nennt den Itemnamen und sagt, dass das Item
  manuell transportiert werden muss. `industry.warehouse-source-not-fresh` umformuliert.
- `PlannerView.decisiveWarnings` blendet `.information` aus, entfernt gleichlautende
  Meldungen und stellt blockierende Warnungen voran. Codes, Schweregrade und Rechenregeln
  sind unverändert; nur die Anzeige im Warnungspanel ist gefiltert.

Prüfung: Katalogtest um Crystalline Kangite in Gruppe 18 erweitert (wird ausgeschlossen);
App-Test für Filter, Deduplizierung, Reihenfolge und Blueprint-Text; Logistiktest prüft den
neuen Text ohne „Type “-Präfix. SwiftPM: 423 Core-Tests und App-Tests bestanden,
`EVEStaticDataKit` 8 Tests bestanden. `xcodebuild` Debug arm64 `TEST SUCCEEDED`;
der Erklärtext in den `.strings`-Dateien wurde danach angepasst und mit `plutil -lint` und
`swift build` geprüft. `git diff --check` fehlerfrei.

Offen: Meldungstexte bleiben englisch (keine Lokalisierung dynamischer Warnungen).
Live-Prüfung durch den Eigentümer. Nicht committet.

## 19.10.2026 – Bauplanauswahl nach Ort, Runs, ME und TE

Auftrag des Eigentümers: In der Auswahl des bevorzugten konkreten Bauplans standen
Item-IDs („Item 1037196637011 · 6 runs · ME 10 · TE 20“). Wichtig sind stattdessen Standort,
ME, Runs und TE; der Bauplanname steht bereits darüber. Gleiche Baupläne sollen als
„10× … ME 9 · TE 14“ zusammengefasst werden.

Änderung:
- Gemeinsame Aufbereitung `ConcreteBlueprintSourceMenu` (in `PlaceholderViews.swift`) für
  Planner (**Bevorzugter Bauplan**) und Produktionsbaum (**Konkreter Bauplan**). Titel:
  Anzahl bei mehr als einem Exemplar, Standort (bzw. „Ort ungeklärt“, „(anderer Ort)“),
  Runs, ME, TE und bei Verträgen/Marktaufträgen der Preis. Keine Item-, Vertrags- oder
  Auftrags-IDs mehr.
- Gruppierung nach Original/Kopie, Produktionsort ja/nein, Standortname, Runs, ME, TE und
  Preis; Reihenfolge bleibt die bisherige (Produktionsort zuerst).
- Auswahl eines Eintrags speichert alle Instanzen der Gruppe als bevorzugte Quellen; die
  Zuteilung (`BlueprintSupplyPlanner`, unverändert) ordnet sie entsprechend vor. Jede
  Instanz bleibt ein eigener Fertigungsjob.
- Neue Lokalisierungen (de/en) für Ort ungeklärt, anderer Ort, 1 Durchlauf, unbegrenzte
  Durchläufe und die bisher unübersetzten Picker-Beschriftungen.

Prüfung: App-Test `testConcreteBlueprintChoicesMergeIdenticalCopiesWithoutItemIDs`
(Gruppierung, Reihenfolge, Titel ohne IDs, Auswahl-Zuordnung). `swift test` bestanden
(423 Core-Tests, App-Tests inkl. neuem Test), `EVEStaticDataKit` 8 Tests bestanden,
`xcodebuild` Debug arm64 `TEST SUCCEEDED`, `plutil -lint` für beide `.strings` OK.

Offen: Sichtprüfung in der laufenden App durch den Eigentümer. Nicht committet.

## 19.10.2026 – Eigentümerabnahme für Commit `dcc067e`

Der Eigentümer hat die Änderungen aus Commit `dcc067e` in der laufenden App geprüft und als in
Ordnung abgenommen: Standardmineralien, Planner-Warnungen, Bauplanauswahl nach Ort/Runs/ME/TE,
eigene Blueprints mit 0 ISK und Kosten pro Einheit inklusive Lieferung, Kauf-/Bauanalyse für
nicht transportierbare Items sowie Freighter und Jump Freighter als Large Ships. Die vorherigen
Einträge vom 19.10.2026 mit dem Vermerk „Nicht committet“ sind damit committet, gepusht
(`origin/main`) und vom Eigentümer abgenommen.

Offen: nichts aus diesen Aufträgen. Warnungstexte bleiben englisch (bewusst nicht Teil des
Auftrags).

## 19.10.2026 – Komprimiertes Erz statt Mineralien im Planner überprüft

Auftrag des Eigentümers: Prüfen, dass der Planner Mineralbedarf lieber als komprimiertes
Erz am Main Hub kauft und zum Home Hub liefert, weil die Lieferung der Mineralien selbst
zu teuer ist.

Befund:
- Die Prüfung existierte bereits (`optimizeCompressedOreRefining`). In der lokalen
  Production Basis des Eigentümers ist sie jedoch **ausgeschaltet**. Der Planner gab dazu
  keinen Hinweis. Zusätzlich hat die Tatara „B9E-H6 - GEZ T2 React Reproc“ keine
  bestätigte Refining-Gebühr; ohne sie gilt die Anlage nicht als Refining-fähig.
  Die lokalen Daten wurden nur aus einer Kopie gelesen und nicht verändert.
- Zum Vergleich der letzte Ark-Plan: etwa 21,7 Mio. Mineralieneinheiten, also etwa
  217.000 m³. Bei 900 ISK/m³ kostet die direkte Lieferung damit etwa 195 Mio. ISK.
- Schwächen im Code: Ein Erz musste eine Mineralposition allein vollständig decken.
  Reichte die Markttiefe nicht, fiel es ganz weg. Außerdem wurden Erz- und
  vermiedener Mineraltransport je Vorschlag getrennt auf Millionen gerundet,
  nicht im gemeinsamen Lieferpaket bewertet.

Änderung:
- Jeder Erzvorschlag wird über die Kurierkosten des gemeinsamen Lieferpakets
  Main Hub → Home Hub bewertet: verbleibende Direktkäufe plus bereits gewählte Erze,
  vorher und nachher. Grundlage sind dieselbe Vertragsaufteilung und Rundung.
- Reicht die Markttiefe nicht aus, werden die tatsächlich verfügbaren ganzen Chargen
  gekauft. Den Rest decken andere Erze oder der Direktkauf. Dazu gibt es den neuen
  Hinweis `refining.ore-depth-limited`.
- Ist der Vergleich ausgeschaltet und es existiert ein passendes komprimiertes Erz für
  gelieferte Mineralien, zeigt der Planner `refining.comparison-disabled` im Bereich
  **Compressed-Ore-Vergleich** (de/en lokalisiert). Der Grundtext dieses Bereichs wird
  jetzt über die Lokalisierung ausgegeben.
- Die abschließende Gesamtprüfung beider Wege und alle übrigen Rechenregeln
  (Ausbeute, Chargenrundung, Gebühr, Überschuss ohne Wertgutschrift) bleiben
  unverändert.

Prüfung: Neue Core-Tests `compressedOreIsValuedInsideTheSharedInboundCourierCargo`,
`compressedOreUsesAvailableDepthAndKeepsTheRestDirect` und
`disabledCompressedOreComparisonIsReportedForShippedMinerals`. `swift test` bestanden
(426 Core-Tests, 39 App-Tests), `EVEStaticDataKit` 8 Tests bestanden, `xcodebuild` Debug arm64 `TEST SUCCEEDED`,
`plutil -lint` für beide `.strings` OK.

Offen: Der Eigentümer muss den Vergleich in **Data & Settings → Industrie**
einschalten und die Refining-Gebühr der Tatara bestätigen; danach neu berechnen.
Nicht modelliert ist der Weitertransport der Mineralien von der Refining-Anlage
(B9E-H6) zum Produktionsort (UALX-3). Nicht committet; keine Eigentümerabnahme.

## 19.10.2026 – Standard-Refining-Gebühr 1 % für Tatara

Auftrag des Eigentümers: Für die Tatara als Standard eine Refining-Gebühr von 1 % einrichten.

Änderung:
- `IndustryStructureKind.defaultReprocessingTaxRate` ist für `.tatara` 1 %, für alle anderen
  Anlagen `nil`. `ConfiguredIndustryStructure.effectiveReprocessingTaxRate` verwendet die
  eingetragene Gebühr, sonst diesen Standard. Readiness-Prüfung und Planner rechnen damit.
- Die gespeicherte Gebühr bleibt unverändert, ein leeres Feld also `nil`. Ein eingetragener
  Wert, auch 0 %, hat Vorrang. Es gibt keine Migration und keine Schemaänderung.
- Das Einstellungsfeld zeigt bei einer Tatara den Platzhalter „Standard 1 %“ und einen
  angepassten Hinweistext (de/en).
- Folge für den Eigentümerstand: Die Tatara „B9E-H6 - GEZ T2 React Reproc“ (Gebührenfeld leer)
  ist damit Refining-fähig. Der Compressed-Ore-Vergleich selbst muss weiterhin in
  **Daten & Einstellungen → Industrie** eingeschaltet werden.

Prüfung: Test `tataraUsesTheOnePercentStandardUntilATaxIsEntered`. Der Readiness-Test
verwendet für den Fall „Gebühr unbekannt“ jetzt eine Athanor. `swift test` bestanden
(427 Core-Tests, 39 App-Tests), `EVEStaticDataKit` 8 Tests bestanden, `xcodebuild` Debug
arm64 `TEST SUCCEEDED`, `plutil -lint` für beide `.strings` OK.

Offen: Sichtprüfung in der App durch den Eigentümer. Nicht committet.

## 19.10.2026 – Standard-Refining-Gebühr 1 % für alle Spielerstrukturen

Auftrag des Eigentümers: Bei allen Strukturservices soll standardmäßig 1 % Servicegebühr
anfallen; eine Änderung bleibt in den Einstellungen möglich.

Änderung: `IndustryStructureKind.defaultReprocessingTaxRate` ist jetzt für jeden Strukturtyp außer
`.npcStation` 1 %, nicht mehr nur für die Tatara. Ein eingetragener Wert (auch 0 %) hat Vorrang;
gespeicherte Werte bleiben unverändert, ein leeres Feld also `nil`. Das Einstellungsfeld zeigt
„Standard 1 %“, der Hinweistext spricht vom Strukturstandard (de/en). Die Job-Facility-Tax für
Fertigung, Reaktionen und Forschung (`facilityTaxRate`) ist von dieser Änderung nicht betroffen.

Prüfung: `playerStructuresUseTheOnePercentStandardUntilATaxIsEntered` prüft alle Strukturtypen
außer der NPC-Station sowie den Vorrang eingetragener Werte. Der Readiness-Test erwartet für eine
Athanor ohne Service nur noch die fehlenden Angaben zu Service und Ausbeute. `swift test`
bestanden (427 Core-Tests, 39 App-Tests), `EVEStaticDataKit` 8 Tests bestanden, `xcodebuild`
Debug arm64 `TEST SUCCEEDED`, `plutil -lint` OK.

Offen: Ob die Job-Facility-Tax ebenfalls einen Standard von 1 % erhalten soll, ist noch nicht
entschieden. Sichtprüfung in der App durch den Eigentümer. Nicht committet.

## 19.10.2026 – Standard-Facility-Tax 1 % für Fertigung, Reaktionen und Forschung

Auftrag des Eigentümers: Die Job-Facility-Tax für Fertigung, Reaktionen und Forschung soll
standardmäßig 1 % betragen, solange er nichts anderes einträgt.

Änderung:
- `IndustryStructureKind.defaultFacilityTaxRate`: 1 % für alle Strukturtypen außer
  `.npcStation`.
- `ConfiguredIndustryStructure.facilityTaxRate` ist jetzt der wirksame Wert: eingetragener
  Wert, sonst Strukturstandard. Alle bestehenden Kostenrechnungen (Planner, Reaktionen,
  Forschung, Main-Hub-Chancen) lesen ihn unverändert über diese Eigenschaft.
  `enteredFacilityTaxRate` ist der optionale Eingabewert; `nil` bedeutet Standard.
- Persistenz: Der Wert bleibt unter dem bisherigen Schlüssel `facilityTaxRate` gespeichert,
  neu kommt `facilityTaxRateIsEntered` hinzu (explizite `CodingKeys`, keine Schemaänderung
  der Store-Tabellen). Altdaten ohne dieses Feld: gespeicherte 0 % war der frühere
  Vorgabewert und wird als nicht eingetragen gelesen (also 1 %), andere Werte als
  eingetragen. Eine wirklich gebührenfreie Struktur muss einmal ausdrücklich 0 % erhalten.
- Einstellungsfeld **Anlagensteuer**: Platzhalter „Standard 1 %“ und Hinweistext (de/en).
- Die Fallback-Profile ohne konfigurierte Struktur (`ManufacturingProfile`, `ReactionProfile`)
  bleiben unverändert.

Folge für den Eigentümerstand: Alle gespeicherten Strukturen hatten 0 %; Planner, Reaktionen
und Forschung rechnen nach dem nächsten Start mit 1 % Anlagensteuer. Installationskosten
steigen entsprechend.

Prüfung: Tests `playerStructuresUseTheOnePercentJobFacilityTaxUntilATaxIsEntered` und
`legacyStructureZeroFacilityTaxBecomesTheStandard` (Altdaten 0 → Standard, 0,05 → eingetragen,
bestätigte 0 % übersteht das Speichern). `recommendsBuildAndShowsSavingsForTheCompleteRequiredQuantity`
setzt seine Struktur jetzt ausdrücklich auf 0 %, weil seine Erwartungswerte darauf beruhen.
`swift test` bestanden (429 Core-Tests, 39 App-Tests), `EVEStaticDataKit` 8 Tests bestanden,
`xcodebuild` Debug arm64 `TEST SUCCEEDED`, `plutil -lint` OK.

Offen: Sichtprüfung in der App durch den Eigentümer. Nicht committet.

## 19.10.2026 – CI-Fehler: Typprüfung in `ConcreteBlueprintSourceMenu.groupKey`

Befund: Die GitHub-CI (macos-15, Swift 6.1.2) schlug für `6f2f533` und `d1b089d` fehl. Der Compiler
konnte den Array-Ausdruck in `groupKey` (`PlaceholderViews.swift`, aus `dcc067e`) nicht in
angemessener Zeit typprüfen. Lokal mit neuerem Xcode trat das nicht auf.

Änderung: Der Ausdruck ist in einzelne, ausdrücklich als `String` typisierte Teile zerlegt.
Schlüsselinhalt und Reihenfolge sind unverändert.

Prüfung: lokaler Build mit `-warn-long-expression-type-checking=300` ohne Meldung, `swift test`
bestanden. Ob die CI wieder grün ist, zeigt erst der nächste Push.

Nachtrag: Der CI-Lauf für `68ac548` kam an der Typprüfung vorbei, scheiterte aber am App-Test
`EVEItemPresentationTests` (aus `dcc067e`). Swift 6.1.2 erlaubt den synchronen Aufruf von
`PlannerView.decisiveWarnings` aus einem Test ohne Main Actor nicht. Die reine Filterfunktion ist
jetzt `nonisolated`. Lokal (Swift 6.4) ist `swift test` bestanden. Eine Swift-6.1-Toolchain steht
lokal nicht zur Verfügung; den Nachweis liefert die CI.

## 20.10.2026 – Kaufanalysen: „Alle anzeigen“ verdrängte die übrige Ansicht

Befund: In Moon- und Mineralien-Kaufanalyse lag der Inhalt in einem festen,
nicht scrollbaren `VStack` in Fensterhöhe. Klappte man die Liste „Empfohlene
Kauforte“ auf (20 Mondmaterialien), wurde der Stapel höher als das Fenster: Die
Vergleichstabelle schrumpfte auf null Höhe und der Kopfbereich rutschte oben aus
dem Bild.

Änderung: Die ganze Seite liegt in einer senkrechten `ScrollView`; die
Vergleichstabelle scrollt nur noch waagerecht und zeigt alle Zeilen in voller
Höhe. Lade- und Leerzustand erhalten eine Mindesthöhe statt `Spacer`. Rechenregeln,
Sortierung und Bildexport sind unverändert.

Prüfung: `xcodebuild … build` und `xcodebuild … test` (Debug, arm64) erfolgreich,
`swift test` mit 429 Tests bestanden. Nicht geprüft: Sichtkontrolle in der laufenden App mit Live-Marktdaten,
Eigentümerabnahme offen.

## 20.10.2026 – Kompakte Kaufort-Empfehlungen in den Kaufanalysen

Auftrag: Die Karte „Empfohlene Kauforte“ in Moon- und Mineralien-Kaufanalyse
nahm mit einer Zeile pro Material zu viel Platz ein.

Änderung: Die Fachansichten zeigen die Empfehlungen jetzt als kompaktes Raster
(Name, Kaufort, Preis untereinander je Zelle, Zellen nebeneinander, ohne
Aufklappen). Mondmaterialien sind nach den Klassen R4 bis R64 gruppiert, über
eine feste Zuordnung der 20 Typ-IDs in `MoonMaterialRarityClass` (gegen die
lokale SDE 3607705 abgeglichen). Mineralien bleiben alphabetisch. Die
Dashboard-Karten behalten die bisherige Fünfer-Vorschau. Rechenregeln unverändert.

Prüfung: Neuer Core-Test zur Klassengruppierung; `swift test` (430 Tests),
`xcodebuild … build` und `xcodebuild … test` erfolgreich. Nicht geprüft:
Sichtkontrolle mit Live-Marktdaten, Eigentümerabnahme offen.

## 20.10.2026 – Nettowert: Baupläne bewerten, Charaktertabelle ausrichten

Auftrag: In der Nettowert-Seite war die Charaktertabelle verschoben, BPOs blieben
als „Blaupausenstatus unbekannt“ unbewertet und BPCs wurden ausgeschlossen.
BPOs sollen mit dem Wiederbeschaffungswert aus Baupläne (Forschung bis zum
aktuellen ME/TE), BPCs mit einem Marktwert, laufende Industrie geschätzt bzw.
rekursiv bewertet werden.

Änderung:
- Ursache der Verschiebung: Die Charakterspalte hatte nur eine Mindestbreite und
  wuchs mit der Hinweiszeile. Jetzt feste Spaltenbreiten, umbrechende Hinweise.
- Ursache der unbekannten Bauplanstatus: ESI liefert `is_blueprint_copy` nur für
  Kopien; Originale wurden ohne Kennzeichen als unbekannt gezählt. Der Projektor
  nutzt jetzt den gespeicherten Blueprint-Datensatz (gleiche Item-ID) und die
  Stapelregel.
- BPO: `DashboardBlueprintValuationBuilder` verwendet
  `BlueprintResearchCostCalculator` (gleiche Regel wie Baupläne). Ohne
  Forschungsanlage bei erforschten BPOs: SDE-Basispreis als sichtbare Schätzung.
- BPC: niedrigster Preis je Run aus zurechenbaren öffentlichen Einzel-BPC-Verträgen
  × eigene Runs. Ohne Angebot weiterhin unbewertet („ohne Vertragspreis“).
  Abweichung vom Wunsch „Markt-Durchschnitt“: BPCs haben keine Marktorders; der
  ESI-Preis des Typs ist der BPO-Preis.
- In Produktion: Materialien ohne Referenzpreis rekursiv über ihre SDE-Eingänge.
  Weiterhin ESI-Referenzpreise (Average, Fallback Adjusted), nicht Jita-Orderbuch.
- Bewertungsrichtlinie `…-bpo-research-bpc-contracts-v4`; ältere Tagespunkte
  behalten ihren Regelstand, neue Felder werden abwärtskompatibel dekodiert.

Prüfung: Neue Core-Tests `NetWorthBlueprintValuationTests` (BPO-Forschungswert,
Basispreis-Fallback, unerforschte BPOs, BPC-Run-Preis, rekursive Materialien);
`swift test` (435 Tests, ein einmaliger Dateisystem-Flake in
`interruptedTransactionsRollBack` war einzeln und im Wiederholungslauf grün),
`EVEStaticDataKit` separat grün, `xcodebuild … test` (Debug, arm64) grün.
Der neue Code liegt in bestehenden Dateien, weil XcodeGen lokal fehlt. Nicht geprüft:
Sichtkontrolle mit echten Charakterdaten und befülltem Vertragsindex;
Eigentümerabnahme offen.

## 20.10.2026 – Planner: Produktionskosten inklusive Lieferung „nicht verfügbar“

Auftrag: Im Planner (Siege Module I, 5 Runs, ME 10/TE 20) war „Produktionskosten
inklusive Lieferung“ und damit der Stückpreis nicht verfügbar, obwohl
Zwischensumme und Lieferung berechnet waren. Bereich im Abgleich mit den
EVE-Regeln prüfen; BPC-Kosten aus den Verträgen mit passender Run-Zahl ermitteln
(Eigentümerentscheidung).

Befund:
- Der gespeicherte Plan enthielt einen konkreten BPC-Versorgungsplan aus zwei
  Jita-Verträgen (3 Runs ME 8 für 3,5 Mio., 2 von 3 Runs ME 10 für 3,98 Mio.,
  zusammen 7,48 Mio. ISK), aber keine Bauplan-Kostenzuordnung. Der Planner nahm
  die Kosten des Versorgungsplans nur bei Wissenschaftsaufträgen, für Vertrags-BPCs
  dagegen den Preis des Baum-Selektors. Fehlte dieser (z. B. nach einem
  wiederhergestellten Versorgungsplan), blieb der Bauplan ungeklärt.
- Widerspruch in der Anzeige: BPC/BPO zeigte 0 ISK, Zwischensumme und
  Verkaufsszenarien rechneten mit 0 ISK Bauplankosten, nur die Gesamtsumme war
  „nicht verfügbar“.

Änderung:
- `ProductionTreeBlueprintCostProjector.contractBPCAllocations` bewertet einen
  vollständig durch öffentliche BPC-Verträge gedeckten Versorgungsplan mit den
  vollen Vertragspreisen; der Planner verwendet diesen Betrag bei der Aktion
  „BPC per Vertrag kaufen“. Run-Fehlmengen, andere Quellen oder fehlende Preise
  bleiben ungeklärt.
- `BlueprintCostBreakdown.unresolvedBlueprintCount` und `acceptedTotal`: Bei
  ungeklärter Quelle sind BPC/BPO, Zwischensumme, Gesamtkosten, Stückkosten,
  Verkaufsszenarien, Produktionsübersicht und Produktionsaufzeichnung
  einheitlich „nicht verfügbar“. Historische Pläne ohne das Feld bleiben unverändert.

Nachtrag nach Eigentümertest (gleicher Tag): Die erste Korrektur reichte nicht,
die App zeigte „0 Bauschritte“. Eigentliche Ursache: `RuntimeState` setzt beim
Produktionsbaum für alle Markt-Typen ohne Make-or-Buy-Empfehlung die Vorgabe
„kaufen“, auch für das angefragte Endprodukt. Der Planner baut Endprodukte
trotzdem, der Baum blendete aber deren Bauschritt aus. Damit fehlten
Bauplanaktion, Vertragspreis und Kostenzuordnung jedes Endprodukts. Jetzt gelten
angefragte Wurzelknoten im `ManufacturingProductionTreeProjector` immer als
„bauen“. Test: `requestedRootStaysABlueprintStepDespiteBuyPreference`.

EVE-Abgleich (EVE University Wiki, Manufacturing/Research/Blueprints): Jobkosten
= EIV × (SCI × Strukturbonus + Anlagensteuer + SCC 4 % + Alpha 0,25 %) entsprechen
der Umsetzung; Materialmenge max(Runs, aufrunden(Basis × Runs × ME × Anlage)) ebenso.
Offen: Das Wiki nennt kein Runden auf zwei Nachkommastellen vor dem Aufrunden;
Drittwerkzeuge tun das. Ohne belastbare Primärquelle unverändert gelassen.

Prüfung: Neue Core-Tests `contractBPCSupplyChargesWholeContractsCoveringRequiredRuns`
und `requestedRootStaysABlueprintStepDespiteBuyPreference`,
erweiterter Test `strictProductionTreeCostsRequireEveryProducedBlueprintAllocation`;
`swift test` (437 Swift-Testing-Tests) und `xcodebuild … test` (Debug, arm64) grün.
Nicht geprüft: `EVEStaticDataKit` (unverändert), Sichtkontrolle in der
App mit Live-Verträgen; Eigentümerabnahme offen.

## 20.10.2026 – Lagerwarnung nur bei möglicherweise unvollständigem Bestand

Auftrag: Die Planner-Warnung „Some character assets in the production warehouse
are not up to date (partial)“ erschien, obwohl alle 14 Charaktere frisch
synchronisiert waren. Ursache: 11 Asset-Snapshots stehen auf „partial“, weil ESI
für 1–10 Spielerstrukturen ohne Zugriff keinen Namen liefert. Die Mengen waren
vollständig, keine Item-Position war ohne Ort.

Änderung:
- `AssetWarehouse.stockSourceStates`/`stockRelevantSourceStates`: Ein nur wegen
  fehlender Struktur- oder Divisionsnamen teilweiser Snapshot gilt für den Bestand
  als frisch (gleiche Diagnose-Präfixe wie die Nettowert-Bewertung).
  `structureNameGaps` nennt Charakter und Anzahl. Ältere kodierte Lager ohne die
  Felder verhalten sich wie bisher.
- Planner-Warnung, Produktionsbaum-Warnung und Projektbestand („known“) verwenden
  den bestandsrelevanten Status. Neue Planner-Warnung bei Asset-Orten, die nicht
  zugeordnet werden können; fehlende Strukturnamen nur als Informationshinweis.
- Lageransicht: Warnzeile nach bestandsrelevantem Status, darunter ein Hinweis je
  Charakter mit kopierbarem Namen und Zahl fehlender Strukturnamen.

Prüfung: Neuer Core-Test `missingStructureNamesAloneDoNotMakeStockIncomplete`;
`swift test` und `xcodebuild … test` (Debug, arm64) grün. Nicht geprüft:
Sichtkontrolle in der App; Eigentümerabnahme offen.

## 20.10.2026 – Produktionsübersicht: fehlende Gebührensätze aus dem Main Hub

Auftrag: In der Produktionsübersicht blieben Steuer, Broker, `Min. +10 %`,
prognostizierter und realer Gewinn sowie die Marge einer verkauften Ark leer.
Ursache: Die Zeile wurde am 19.10.2026 um 16:01 aufgezeichnet, die Jita-Sätze
(Händlercharakter, 4,2 % Steuer, 1,8 % Broker) wurden erst um 21:12
eingerichtet. Der Main-Hub-Verkauf im Plansnapshot hatte daher weder Steuer-
noch Brokersatz. Home- und Coalition-Szenarien kannten nur die Steuer, keinen
Structure-Brokersatz. Diagnose an einer schreibgeschützten Kopie der lokalen
Datenbank; die Nutzdaten wurden nicht verändert.

Entscheidung des Eigentümers: Fehlende Sätze werden aus den aktuellen
Main-Hub-Einstellungen ergänzt und gekennzeichnet.

Änderung:
- Core: `ProductionOverviewRequestProjection.fillingMissingFeeRates(from:)`
  ergänzt nur fehlende Sätze; gespeicherte Sätze haben Vorrang, eine nicht
  anwendbare Brokergebühr bleibt nicht anwendbar. Neue Kennzeichen
  `salesTaxRateIsCurrentSetting`/`brokerFeeRateIsCurrentSetting`,
  `ProductionOverviewFeeRates` und `ProductionBasis.productionOverviewFeeRates`.
- App: Der Projektions-Cache ergänzt beim Lesen. Tabelle, Seitensortierung und
  die Gesamtsummen verwenden die aktuellen Main-Hub-Sätze; die Summen werden bei
  einer Satzänderung neu geladen. Ergänzte Steuer- und Brokerbeträge erscheinen
  kursiv mit Herkunftshinweis im Tooltip, dazu ein Erklärtext über der Tabelle (de/en).

Prüfung: Neue Core-Tests `missingRecordedFeeRatesUseCurrentMainHubRates`,
`recordedFeeRatesWinOverCurrentMainHubRates` und
`unavailableCurrentRatesKeepMissingFeeRatesExplicit`; `swift test`
(441 Swift-Testing-Tests), `swift test` in `Packages/EVEStaticDataKit` und
`xcodebuild … test` (Debug, arm64) grün. Nicht geprüft: Sichtkontrolle in der
App; Eigentümerabnahme offen. Erwartung für die Ark-Zeile (nicht in der App
geprüft): Steuer ≈ 264,6 Mio., Broker ≈ 113,4 Mio., realer Gewinn ≈ 0,48 Mrd. ISK.

## 20.10.2026 – Planner: BPO/BPC-Auflösung und endgültige Berechnung angleichen

Auftrag: Gesamten Planner-Workflow prüfen (Rhea, ME 3/TE 2). Finanzübersicht und
Verkaufsszenarien zeigten „nicht verfügbar“, dazu fünf Run-Fehlmengen-Warnungen,
obwohl passende BPCs (z. B. Capital Cargo Bay mit 40 Runs) und BPOs vorhanden sind.

Befund aus dem gespeicherten Plan: 52 von 62 produzierten Blueprints ohne
Kostenquelle (41 Reaktionen, 11 Komponenten), Versorgungspläne für kleinere
Run-Zahlen als benötigt (Capital Cargo Bay 27 statt 44, Capital Quantum
Microprocessor 705 statt 962 auf einem BPO). Ursache: Der Produktionsbaum für die
BPO/BPC-Auflösung setzte Typen ohne Planner-Vorgabe auf die Kauf-/Bauempfehlung
bzw. pauschal auf „kaufen“ und erzwang Lagerverbrauch; die endgültige Berechnung
baut dagegen alles Baubare mit den eigenen Vorgaben. Bauschritte, die der Baum als
Kauf sah, bekamen keine Blueprint-Kosten, und die Versorgung wurde für einen
anderen Produktionsgraphen geplant.

Änderung:
- `manufacturingProductionTree(usesExactPlannerPreferences:)`: Der Planner lässt
  den Baum mit genau seinen Vorgaben rechnen; fehlende Typen übernehmen die
  Entscheidung des Planner-Vorlaufs. Main-Hub-Chancen bleiben unverändert.
- `consumeBlueprintJobs`: Mehrbedarf auf einem Blueprint-Original läuft auf
  demselben Original weiter statt als Run-Fehlmenge.

Nicht geändert: Die Warnung „Rhea is too large for a courier contract“ ist
fachlich korrekt (1.300.000 m³ verpackt, Kurierlimit 350.000 m³); Szenarien mit
dieser Route weisen den Transport als ausstehend aus.

Prüfung: Neuer Core-Test `ownedOriginalCoversRunsBeyondItsPlannedSupply`;
`swift test` und `xcodebuild … test` (Debug, arm64) grün. Die Angleichung im
Baum (App-Schicht) ist nicht automatisch getestet. Nicht geprüft: Sichtkontrolle
mit dem Rhea-Plan; Eigentümerabnahme offen.

## 20.10.2026 – Gestapelte Blueprint-Originale (Reaktionsformeln)

Befund (Rhea-Plan): 13 Reaktionsformeln blieben ohne Kostenquelle, obwohl sie im
Besitz sind. Sie liegen als Stapel unbenutzter Originale vor (z. B. 24× Hexite);
ESI meldet dann eine positive Menge statt `-1`. `OwnedBlueprintInstance` stufte
das als `unknown` ein, daher galten sie weder als BPO noch als Formel.

Änderung: `OwnedBlueprintInstance.kind(quantity:runs:)` – positive Menge mit
`runs = -1` ist ein Original. Der Dekoder stuft gespeicherte `unknown`-Einträge
neu ein, damit vorhandene Snapshots ohne neue Synchronisation greifen.

Prüfung: Neuer Core-Test `stackedUnusedOriginalsAreOriginalsIncludingStoredSnapshots`;
`swift test` und `xcodebuild … test` (Debug, arm64) grün. Nicht geprüft:
Sichtkontrolle mit dem Rhea-Plan; Eigentümerabnahme offen.

## 20.10.2026 – Bewertung eigener BPCs im Planner

Auftrag (Eigentümerentscheidung): Eigene BPCs ohne eingetragenen Betrag nicht mehr
mit 0 ISK, sondern „Markt, sonst Herstellung“ bewerten.

Änderung:
- Core `OwnedBPCValuation` (in `BlueprintResearch.swift`): Vertragswert je Run
  (nur Angebote mit mindestens gleichem ME/TE), Itemwert, Science-Gebühr je Run,
  Decryptor-Ableitung aus ME/TE/Runs, erwartete Inventionskosten je Run.
- `RuntimeState.ownedBPCValues`: Kopierkosten (T1) bzw. erwartete
  Inventionskosten (T2) mit SDE-Definitionen, Adjusted Prices, Systemindizes
  der konfigurierten Kopier-/Inventionsanlage, Main-Hub-Preisen für Datacores
  und Decryptor und den besten Skills aller Charaktere. Gebührenfaktor der
  Forschungsanlagen in `scienceFacilityContext` zusammengeführt.
- Planner (`valuingOwnedBPCs`): ersetzt die 0-ISK-Zuordnung eigener BPCs durch
  den Wert, mit lokalisierter Herkunftsangabe.
- `BlueprintMaterial` erhält einen öffentlichen Initialisierer.

Beispiel: Die Rhea-BPC (8 Runs, ME 4, TE 4) entspricht einer Invention mit
Optimized Augmentation Decryptor (Basis 1 Run, ME 2, TE 4).

Annahme: Inventionsgebühr = Itemwert des T2-Produkts × 2 % × Gebührenfaktor;
das EVE University Wiki belegt den Itemwert-Bezug, den Faktor 2 % nur fürs Kopieren.

Prüfung: Neuer Core-Test `ownedBPCValuationUsesMarketThenInferredInventionInputs`;
`swift test` und `xcodebuild … test` (Debug, arm64) grün. Die App-seitige
Datenbeschaffung ist nicht automatisch getestet. Nicht geprüft: Werte im
Rhea-Plan, Plausibilität gegen Spielwerte; Eigentümerabnahme offen.

Nachtrag (Eigentümerentscheidung, gleicher Tag): Ist der Decryptor nicht eindeutig
bestimmbar, wird der Mittelwert der erwarteten Inventionskosten aller passenden
Decryptoren verwendet (`OwnedBPCValuation.decryptorCandidates`, `average`).

## 21.10.2026 – Eingaben des Allianzmarkts (manuell)

Auftrag (Eigentümer): Preisfeld mit Tausenderpunkten und Nachkommastellen,
Menge automatisch aus der Produktion mit Pfeil hoch/runter, Gebühr als
öffentliche Vertragsgebühr übernehmen.

Änderung:
- `PlannerAllianceInputParser.groupedEditingText` gruppiert Preis und Menge beim
  Tippen nach App-Sprache; Menge ohne Nachkommastellen.
- Menge vorbelegt mit der produzierten Stückzahl, Stepper und Pfeiltasten
  (1 … produzierte Menge); die volle Menge bleibt als `nil` („alles“) gespeichert.
- `PlannerAllianceSaleCalculator.calculate(…, publicContractFeeRate:)`: ohne
  manuellen Satz gilt die bestätigte öffentliche Vertragsgebühr des Lieferhubs;
  Ergebnis trägt `feeSource` und `appliedFeeRate` (ältere Snapshots: `nil`).
  Am Produktionsort gibt es keinen Handelsort und damit keinen Satz; dann
  bleibt die 0-%-Annahme sichtbar.

Prüfung: Neue Tests `allianceSaleUsesTheDeliveryHubContractFeeUnlessAManualRateExists`,
`allianceEditingTextGroupsThousandsAndKeepsTheDecimalSeparator`, erweiterter
Parser-Test; `swift test` und `xcodebuild … test` (Debug, arm64) grün.
Nicht geprüft: Sichtkontrolle in der laufenden App, insbesondere Pfeiltasten im
Mengenfeld und Cursorverhalten beim Gruppieren; Eigentümerabnahme offen.

## 22.10.2026 – Allianzmarkt rechnet live

Befund (Eigentümer-Screenshot): Preis eingetragen, Karte zeigte trotzdem
„Nicht verfügbar – Trage einen Allianzpreis ein“. Ursache: Die Karte rechnete
nur mit dem zuletzt per Button übernommenen Stand, nicht mit den Feldern.
Die Kostenbasis selbst (`totalProductionCost` = Material + Blaupausen +
Installation + Eingangslogistik, plus Lieferung) war korrekt.

Änderung: Die editierbare Karte rechnet aus den aktuellen Feldwerten; gültige
Eingaben werden nach 600 ms automatisch übernommen und gespeichert. Neue
Rechenzeile Erlös − Gebühr − Kosten (Produktion + Lieferung) = Gewinn.
Rechenregeln unverändert.

Prüfung: `swift test` und `xcodebuild … test` (Debug, arm64) grün. Nicht
geprüft: Sichtkontrolle in der laufenden App; Eigentümerabnahme offen.

## 23.10.2026 – Laufzeit: weniger Neuzeichnen, keine Zeilen-Set-Bauten, parallele ESI-Seiten

Auftrag (Eigentümer): Alle Berechnungsschritte und Abläufe auf Geschwindigkeit
prüfen; die App fühlt sich durch die vielen Abrufe und Daten träge an.

Befund (statische Durchsicht, keine Messung in der laufenden App):
- `RuntimeState` war ein `ObservableObject` mit rund 90 `@Published`-Werten.
  Jede Änderung (auch gedrosselter Fortschritt von Contracts und Hub-Scans)
  zeichnete alle rund 40 beobachtenden Ansichten neu, darunter Dashboard,
  Hub-Chancen und Handel.
- Hub-Chancen: `defaultEfficiencyAssumption` baute für jede Zeile zweimal ein
  Set aller LP-Store-Typen; im Sortiervergleich zusätzlich für jeden der
  n·log n Vergleiche. Bei Tausenden Zeilen und Katalogen mit Tausenden Typen
  entstanden so Millionen Hash-Operationen auf dem Hauptthread.
- `marketAnalysisContextIdentity` kodierte die gesamte Produktionsbasis bei
  jedem Lesen als JSON (Dashboard, Mond-/Mineralanalysen, Reaktionen).
- Dashboard und Net Worth dekodierten den gespeicherten Vermögensverlauf (bis
  365 Stände) bei jedem Zeichnen mehrfach, im Dashboard zusätzlich je
  Charakterzeile.
- `getAllPages` und das Regions-Orderbuch der NPC-Hub-Scans (The Forge rund
  400 Seiten) luden strikt nacheinander; private Vertragsitems (bis 500 je
  Charakter) ebenso.
- Nach jedem Charakterabgleich wurden die vorherigen großen Snapshots auf dem
  Hauptthread dekodiert, obwohl sie nur bei fehlgeschlagenem Abruf nötig sind.

Änderung:
- `RuntimeState` auf `@Observable` umgestellt; Ansichten verwenden
  `@Environment(RuntimeState.self)`, die Profilbindungen `Bindable`. Der
  Feature-Kanal des Planers bleibt.
- `loyaltyStoreOfferedTypeIDSet` einmal je Katalog im Runtime-Zustand;
  Chancenfilter liest Einstellungen einmal je Durchlauf; Sortierung projiziert
  jede Zeile einmal (Decorate-Sort, gleicher Komparator mit Tie-Breaker).
- Gecachte Markt-Kontextkennung (ungültig bei jeder Basisänderung, Lesezugriff
  bleibt beobachtet); `DashboardWealthHistoryCache` für Dashboard und Net
  Worth.
- `ESIOrderedLoader` (höchstens vier offene Elemente, Auslieferung streng in
  Reihenfolge) für `getAllPages`, `locationOrderSnapshot` und private
  Vertragsitems; Seitenzahlprüfung, Fortschritt, Abbruch und Teilzustände
  unverändert. Public-Contracts-Import unverändert gedrosselt.
- `CharacterSyncPersistence` dekodiert vorherige Snapshots nur, wenn der neue
  Abruf keinen Wert hat (identisch zu `retainingLastKnownValue`).

Rechenregeln, Datenmodelle, Schema und Migrationskette sind unverändert.

Prüfung (automatisch):
- Neue Tests: Beobachtung nur gelesener Runtime-Werte, gecachte
  Markt-Kontextkennung samt Invalidierung, Vermögensverlauf-Cache, geordneter
  Loader mit Fensterbegrenzung, sechsseitiges `getAllPages` mit
  Ausführung außer Reihenfolge, vierseitiger Orderbuchscan mit monotonem
  Fortschritt, Weiterführung des letzten bekannten Standes nach
  fehlgeschlagenem Abruf.
- `swift test` isoliert: 525 Swift-Testing-Tests in 35 Suites plus 70 Tests in
  3 Suites bestanden (ein vorgesehener Real-SDE-Skip).
- `EVEStaticDataKit`: 11 Tests bestanden.
- `xcodebuild … test` (Debug, arm64, unsigniert): 525 Tests, `TEST SUCCEEDED`.
- `swift-format lint --strict` der geänderten Dateien: 320 statt zuvor 325
  Befunde, keine neuen; `git diff --check` fehlerfrei.
- Isolierter Start der Debug-App (eigener Datenordner und Preferences, ohne
  Hintergrunddienste, nur per PID beendet): 15 Sekunden ohne Absturz. Die
  Bereiche wurden dabei nicht visuell durchgeklickt.

Nicht geprüft: Messung von Latenz, CPU und RSS in der laufenden App mit
echten Daten (Instruments), Live-ESI-Laufzeit der parallelen Seiten,
Eigentümerabnahme. Bewusst nicht umgesetzt: parallele Home-/Coalition-Scans
(dokumentierte Reihenfolge, Token-Refresh ohne Single-Flight), Kodierung der
Sync-Snapshots abseits des Hauptthreads, externe Speicherung großer
SwiftData-Blobs (Schemaänderung).

## 23.10.2026 – ESI-Regelprüfung: globale Limits und Seitenkonsistenz

Auftrag (Eigentümer): Prüfen, dass alle ESI-Regeln eingehalten werden.

Quellen (am 23.10.2026 gelesen): CCP-Seiten
[Best Practices](https://developers.eveonline.com/docs/services/esi/best-practices/),
[Rate Limiting](https://developers.eveonline.com/docs/services/esi/rate-limiting/),
[X-Pages](https://developers.eveonline.com/docs/services/esi/pagination/x-pages/),
[Overview](https://developers.eveonline.com/docs/services/esi/overview/), die
CCP-Blogposts zu paralleler Paginierung und zum Fehlerlimit (2017) sowie die
OpenAPI-Spezifikation für `2025-12-16` (Token-Gruppen der genutzten Routen,
z. B. `char-contract` 600/15m, `char-wallet` 150/15m, `market-order`
12000/15m).

Befund:
- Eingehalten: User-Agent mit App-Name, Version und Kontakt; gültiges
  `X-Compatibility-Date` 2025-12-16 und `X-Tenant`; Wiederverwendung bis
  `Expires`; `If-None-Match`/`If-Modified-Since`; Prüfung von `X-Pages`;
  Automatikläufe planen ab Laufende statt im festen Takt; der Statusabruf geht
  an status.eveonline.com, nicht an ESI.
- Verletzt bzw. lückenhaft: Fehler- und Rate-Limit-Header wertete nur der
  Public-Contracts-Import aus. Ein 420 oder 429 pausierte nur die eine Anfrage,
  parallele Anfragen liefen weiter; knappe Token-Budgets bremsten nichts.
  Besonders `char-contract`: bis zu 500 Vertragsitems je Abgleich kosten bis
  1.000 Tokens bei 600 je 15 Minuten. `getAllPages` und der Regions-
  Orderbuchscan prüften nicht, dass alle Seiten denselben `Last-Modified`
  haben (offener Punkt SEC-OPEN-07 aus dem Sicherheitsaudit).
- Paralleles Seitenladen ist von CCP ausdrücklich empfohlen (Blog 2017) und
  ohne Obergrenze; die eigenen Grenzen (4 je Ressource, 6 global, 2
  automatisch) bleiben.

Änderung:
- `ESIRequestCoordinator` zeichnet jede Antwort auf: Fehlerlimit ≤ 20 oder 420
  hält alle neuen Anfragen bis Fensterende + 1 s; 429 hält das Bucket
  (Gruppe × Charakter/öffentlich) bzw. die Routenfamilie bis `Retry-After`;
  knappe Buckets werden auf Fenster ÷ Tokens × 2 Sekunden gestreckt. Warten
  ohne Transportplatz, abbrechbar. Wiederholte 420/429 warten über diese
  Sperren statt über einen eigenen Schlaf.
- `firstPage` wartet bei Ablauf von Seite 1 innerhalb von 5 s auf die
  Aktualisierung; `ESIPageSnapshotChange` erzwingt gleiche `Last-Modified`
  über alle Seiten, mit einmaligem Neulesen nur der veralteten Seiten.
- Nach Hub-Scans wird nur das Regions-Orderbuch aus dem Cache entfernt,
  Einzeltyp-Preise (`type_id`) bleiben bis zu ihrem `Expires`.

Prüfung (automatisch): zehn neue Tests (Fehlerlimit-Pause, 420-Wiederholung
nach Reset, 429 nur im eigenen Bucket, Drosselung und Aufhebung, Parsen von
`150/15m`, Routenfamilien, Neulesen nach Aktualisierung, Ablehnung dauerhaft
gemischter Stände, Warten auf bevorstehende Aktualisierung, gezielter
Cache-Abwurf). `swift test` isoliert: 535 + 70 Tests bestanden;
`EVEStaticDataKit` 11; `xcodebuild … test` `TEST SUCCEEDED`;
`swift-format lint --strict` der geänderten ESI-Dateien ohne Befund;
`git diff --check` fehlerfrei.

Nicht geprüft: Verhalten gegen Live-ESI (echte Limit-Header, 420/429),
Laufzeit großer Vertragslisten unter Drosselung. Offen: Jitter beim Backoff
(SEC-OPEN-07); nach einer Speicher-Verdrängung oder dem Freigeben großer
Antworten kann ein späterer Abruf vor `Expires` erneut gesendet werden – ESI
liefert dann seine zwischengespeicherte Antwort, es entstehen also nur
vermeidbare Abrufe, keine Cache-Umgehung.

## 23.10.2026 – Statische EVE-Daten: weniger ESI-Abrufe und Katalogabfragen

Anlass: Eigentümerfrage, ob sich das Programm durch vorab lokal gespeicherte,
unveränderliche EVE-Daten (Blueprints, Materialien, Items, Schiffe)
beschleunigen lässt.

Befund:
- Das ist größtenteils bereits umgesetzt. Das SDE liegt als SQLite-Katalog
  lokal vor (Build 3632936, 26 MB: 53.288 Typen, 5.100 Blueprints, 36.558
  Materialzeilen). Blueprints und Items werden nie per ESI geholt.
- Verbleibende statische Lasten:
  - Für das verpackte Volumen fragte `UniverseTypeVolumeService` je Typ ein
    ESI-Typdetail ab. Beim Main-Hub-Scan sind das 4.765 Typen, nach jedem
    Neustart erneut. Das SDE enthält inzwischen für 26.347 von 27.309
    veröffentlichten Typen ein echtes `packagedVolume`, darunter für alle
    4.765. Die alte ESI-Regel stammt aus Build 3458726 (nur NULL-Werte).
  - `manufacturingDefinitions()`/`reactionDefinitions()` liefen als eine
    Abfragefolge je Produkt: 4.054 Produkte × 3 Abfragen, die
    Produktabfrage je Blueprint ohne Index (`SCAN blueprint_products`).
  - Beim Start dekodierte `industryFacilityReferences()` rund 74 % der
    27,7 MB großen Paketdatei `typeDogma.jsonl` für 152 Typen.
- Nicht statisch und daher nicht vorab speicherbar: Orderbücher, öffentliche
  Verträge und Charakterdaten. Lasten auf dem Hauptthread und in den Ansichten
  sind laut Eigentümer ein eigener späterer Auftrag.

Änderung (Eigentümerentscheidung zur Volumenquelle in
[DECISIONS.md](Documentation/Consolidation/DECISIONS.md)):
- `UniverseTypeVolumeService` nimmt zuerst das SDE-`packagedVolume` über
  `catalog.packagedVolumes(typeIDs:)` und fragt ESI nur noch für Typen ohne
  SDE-Wert. Quelle des Snapshots: `CCP SDE`, `ESI universe types` oder beides;
  Diagnose `sde.packaged-volume:<n>`. Ist das SDE nicht lesbar, bleibt der
  ESI-Weg. Das entpackte `volume` ersetzt weiterhin nie einen fehlenden Wert.
- `SQLiteStaticCatalog` lädt vollständige Definitionen mit drei
  mengenbasierten Abfragen und hält sie je Aktivität für die aktive
  Katalogdatei. Ein Produkt mit mehreren qualifizierten Blueprints nutzt die
  bisherige Einzelabfrage (im aktiven SDE: 0 Fälle). Die Produktreihenfolge
  ist auf dem aktiven Katalog lesend identisch geprüft.
- Katalogadapter 6:
  - Der Mapper übernimmt die Dogma-Attribute der Kategorien 65 und 66 in die
    neue Tabelle `type_dogma`, eine JSON-Liste je Typ im SDE-eigenen Format.
    So bleibt ein vorhandener Typ mit leerer Attributliste vorhanden, statt zu
    fehlen. Das weicht im Detail vom Plan ab (eine Zeile je Attribut).
  - Neu sind außerdem die Indizes `idx_product_blueprint` und
    `idx_skill_blueprint`.
  - Kataloge bis Adapter 5 lesen Dogma weiter aus der Paketdatei.
- Dokumentation: `PRODUCT.md`, `ARCHITECTURE.md`, `DECISIONS.md`,
  `PROJECT_STATE.md`.

Prüfung (automatisch):
- Neue Tests:
  - vier Tests zur Volumenquelle: nur SDE ohne ESI-Anfrage, Mischfall, Lücke
    in beiden Quellen, SDE nicht lesbar;
  - Gleichheit der mengenbasierten und der Einzel-Definitionen samt Material-
    und Produktreihenfolge, zweitem Produkt, Doppel-Blueprint und
    unaufgelöstem Material;
  - Cache bis zum Katalogwechsel;
  - Indizes und Dogma-Tabelle in beiden Schreibwegen;
  - Facility-Daten aus der Tabelle ohne Paketdatei sowie aus der Paketdatei
    ohne Tabelle;
  - Dogma-Auswahl im Mapper.
- Bestehende Tests auf den Dateinamen `catalog-v6` angepasst.
- Opt-in gegen das reale öffentliche SDE-Paket des Builds 3632936
  (`EVE_STATIC_DATA_KIT_REAL_PACKAGE`):
  - Der Mapper liefert die Raitaru-Dogma (23 s).
  - Isolierter Import (50 s): die mengenbasierten Definitionen gleichen für
    alle Fertigungs- und Reaktionsprodukte der Einzelabfrage.
  - Die Facility-Referenz aus der Tabelle ist identisch mit der aus der
    Paketdatei.
- `swift test` 548 + 70 Tests bestanden; `EVEStaticDataKit` 12 Tests (1
  Opt-in übersprungen); `xcodebuild … test` `TEST SUCCEEDED`.
- `swift-format lint --strict`: keine neuen Befunde. `SQLiteStaticCatalog.swift`
  (7) und `RuntimeState.swift` (72) hatten dieselben Befunde schon vor dem
  Commit. Korrektur vom 23.10.2026: Der ursprüngliche Lint-Lauf hatte die
  Dateiliste nicht richtig übergeben; der Vorher-/Nachher-Vergleich wurde
  nachgeholt. `git diff --check` fehlerfrei.
- Die Läufe umfassen auch die uncommitteten Änderungen paralleler Sitzungen.
- Datenbankebene, Kopie des aktiven Katalogs mit `sqlite3`:
  - alle 4.054 Fertigungsdefinitionen alt 0,60 s, neu 0,04 s;
  - die Einzelabfrage je Blueprint mit den neuen Indizes 0,23 s statt 0,60 s;
  - `EXPLAIN QUERY PLAN`: `SEARCH … USING INDEX` statt `SCAN`.

Nicht geprüft:
- Laufzeit in der echten App: Startzeit, Dauer des Main-Hub-Scans, ESI-Last.
- Live-Vergleich SDE- gegen ESI-Volumen über die Stichproben hinaus.
- Eigentümerabnahme.
- Die Dogma-Beschleunigung braucht einmal „SDE → Neuimport des aktuellen
  Katalogs“ (etwa 5 Minuten) und einen Neustart. Bis dahin arbeitet die App mit
  dem v5-Katalog wie bisher.

Offen (eigene Aufträge):
- Universumsdaten lokal (kleiner Effekt).
- Persistenter ESI-HTTP-Cache und Vertrags-304-Pfad.
- UI- und Hauptthread-Lasten:
  - O(n²) in der Lager-Tabelle;
  - Dashboard-Dekodierung alle 60 s;
  - große `StoredCharacter`-Blobs ohne `.externalStorage`;
  - Synchronisationsspeicherung auf dem Hauptthread.
- Alte SDE-Pakete: rund 1,3 GB Speicher, ohne Geschwindigkeitseffekt.

Nachtrag 23.10.2026 – Neuimport und isolierte Prüfung:
- Commit `3100021` (nur eigene Änderungen, nicht gepusht).
- „SDE → Neuimport des aktuellen Katalogs“ lief laut Installationsprotokoll
  von 09:12:09 bis 09:13:11 Uhr (Download 99 MB, Status `completed`).
- Lesend geprüft: Der aktive Zeiger nennt
  `sde-3632936-fd6749fdcf9c-catalog-v6.sqlite`. Der Katalog enthält:
  - `type_dogma` mit 491 Typen, darunter Raitaru;
  - `idx_product_blueprint` und `idx_skill_blueprint`;
  - unverändert 53.288 Typen und 5.100 Blueprints.
- Die Debug-App läuft seit 10:17 Uhr, also nach dem Neuimport.
- Isolierter Testlauf nur des committeten Stands (`git archive` von
  `02b61a2`, ohne uncommittete Änderungen paralleler Sitzungen, eigene
  DerivedData): `swift test` 535 + 66 Tests, `EVEStaticDataKit` 12,
  `xcodebuild … test` `TEST SUCCEEDED`.
- Weiter offen:
  - Messung in der laufenden App (Startzeit, Dauer des Main-Hub-Scans,
    ESI-Last);
  - Eigentümerabnahme.

## 23.10.2026 – Messprotokoll mit CCP-Regelprüfung und Offline-Benchmark

Anlass: Offene Messung von Startzeit, Main-Hub-Scan und ESI-Last. Vorgabe des
Eigentümers: Alle CCP-Vorgaben für ESI müssen erfüllt sein.

Entscheidungen des Eigentümers:
- Ein kleines, dauerhaftes Messprotokoll ohne Charakterdaten.
- Vorher-/Nachher-Werte kommen aus einem Offline-Benchmark.
- Der Live-Lauf folgt erst nach einem ESI-Cache, der Neustarts übersteht. Der
  ist ein eigener Auftrag, sobald die ESI-Sitzung ihre Änderungen an
  `ESIClient.swift` committet hat.

Quellen der CCP-Regeln (gelesen am 23.10.2026):
[Best Practices](https://developers.eveonline.com/docs/services/esi/best-practices/),
[Rate Limiting](https://developers.eveonline.com/docs/services/esi/rate-limiting/),
[Overview](https://developers.eveonline.com/docs/services/esi/overview/),
[X-Pages](https://developers.eveonline.com/docs/services/esi/pagination/x-pages/).
Bekannte Lücke dazu: Laut Best Practices soll vor `Expires` nicht aktualisiert
werden. Der Cache liegt aber nur im Arbeitsspeicher, also ruft jeder App-Start
noch gültige Daten erneut ab.

Änderung:
- `PerformanceLog`/`PerformanceStopwatch` (Core) schreiben ins Systemprotokoll
  (Subsystem `com.local.EVENexusSimple`, Kategorie `performance`, Stufe notice).
  Erfasst werden:
  - Startmeilensteine relativ zum Prozessstart;
  - die Profil-Referenzdaten;
  - Dogma- und Definitionsladen des SDE-Katalogs mit Quelle bzw.
    Cache-Treffer;
  - jede Phase des Main-Hub-Scans samt Home-/Coalition-Hub, die
    Volumendiagnose und die ESI-Differenz des Scans.
- `MeasuringESITransport` hängt rein beobachtend unter dem App-ESI-Client. Er
  verändert nichts, sendet nichts selbst und wiederholt nichts. Er zählt je
  Routenfamilie (`{id}` statt Kennungen) und prüft die CCP-Vorgaben passiv:
  - fehlender User-Agent oder fehlendes Compatibility-Date;
  - ein Compatibility-Date in der Zukunft;
  - frühe GET-Abrufe vor `Expires`;
  - 420/429;
  - die niedrigsten Fehler- und Token-Budgets.
- `ESIClient.swift` blieb unberührt.
- Die vier neuen Dateien sind von Hand in `project.pbxproj` eingetragen
  (ID-Präfix `01A0D001`), weil XcodeGen nicht verwendet wird.

Prüfung (automatisch):
- Sechs neue Transport-Tests:
  - Routenvorlage;
  - unveränderte Weitergabe von Anfrage, Antwort und Fehler;
  - Statusklassen;
  - früher Abruf vor bzw. nach `Expires`, POST zählt nicht;
  - fehlende Header und Compatibility-Date in der Zukunft;
  - 420/429 samt Mindestbudgets und Zusammenfassung ohne Kennungen.
- `swift test` 555 + 70 Tests; `EVEStaticDataKit` 12; `xcodebuild … test`
  555 Tests, `TEST SUCCEEDED`.
- `swift-format lint --strict`: neue Dateien ohne Befund, in den geänderten
  Dateien keine neuen Befunde. `git diff --check` fehlerfrei.
- Das Systemprotokoll der Testläufe enthält 66 Zeilen der Kategorie
  `performance`, nur mit Namen, Dauern und Anzahlen.
- Opt-in-Benchmark `StaticCatalogBenchmarkTests` (`EVE_NEXUS_RUN_BENCHMARKS=1`,
  echtes SDE-Paket 3632936, isolierter Import, ohne Netz, Debug-Build, Median
  aus drei Läufen):

  | Messung | alt | neu |
  |---|---|---|
  | Facility-Dogma | 529,3 ms aus der Paketdatei | 58,0 ms aus der Tabelle |
  | 4.054 Fertigungsdefinitionen | 654,5 ms, Einzelabfragen ohne Indizes | 53,2 ms mengenbasiert kalt, 0,0 ms aus dem Cache |
  | ESI-Volumenabrufe je Main-Hub-Scan | 4.765 | 0 |

Nicht geprüft:
- Live-Lauf in der echten App: Startzeit, Scan-Dauer, ESI-Last und
  CCP-Zähler. Er ist bewusst zurückgestellt, bis der dauerhafte Cache steht.
- Eigentümerabnahme.

Offen (Folgeaufträge in dieser Reihenfolge):
1. ESI-Cache, der Neustarts übersteht (Ablaufzeiten, Validatoren, Antworten),
   damit kein Abruf vor `Expires` erfolgt.
2. Live-Lauf mit Auswertung des Messprotokolls und Abnahmeliste.

## 23.10.2026 – Dauerhafter ESI-Antwortcache

Anlass: Laut CCP Best Practices soll vor `Expires` nicht aktualisiert werden.
Der ESI-Cache lag nur im Arbeitsspeicher. Jeder App-Start und jede Verdrängung
führte zu Abrufen noch gültiger Daten. Entscheidungen des Eigentümers in
[DECISIONS.md](Documentation/Consolidation/DECISIONS.md).

Änderung:
- `ESIResponseDiskCache` (`ESIResponseStoring`) ist eine eigene SQLite-Datei
  `caches/esi-responses.sqlite` mit Schema v1, WAL und einem eigenen kleinen
  Wrapper mit BLOB-Spalten.
  - Je Eintrag: Inhalt, ETag, Last-Modified, Expires, Seitenzahl, Status und
    Herkunft. Der Schlüssel `partition|url` ist derselbe wie im Speicher.
  - LRU-Grenze 512 MB, Räumung auf 90 %.
  - Einträge eines anderen Compatibility-Date fallen beim Öffnen weg.
  - Bei einem Datenbankfehler wird der Speicher für den Lauf abgeschaltet,
    ohne dass ein Abruf scheitert.
  - Ins Messprotokoll schreibt er Öffnen, Treffer, Speichern und Räumungen.
- Einbindung in `ESIClient`:
  - Bei einem Fehltreffer im Speicher wird zuerst die Platte gefragt.
  - Frische Einträge kommen ohne Netz zurück; abgelaufene liefern die
    Validatoren für einen bedingten Abruf.
  - Neue Antworten werden durchgeschrieben.
  - Ein nicht mehr lesbarer Inhalt von der Platte wird verworfen und neu
    geladen.
  - `persistsDurably` hält das öffentliche Regions-Orderbuch ohne `type_id`
    und `/contracts/public/` nur im Speicher.
  - Charakter-Trennung, Seitenwechsel bei neuem Snapshot und gezielte
    Massenfreigabe löschen auch die dauerhaften Kopien. Speicher-Trim und
    Speicherdruck tun das nicht.
- `RuntimeState` übergibt den Speicher. Der Ordner `caches` steht auf der
  Ausnahmeliste von `ConsolidationBackup`.
- Zwei neue Dateien sind im Xcode-Projekt eingetragen (Präfix `01A0D002`).

Prüfung (automatisch):
- Neun neue Tests:
  - Neustart mit frischem Eintrag ohne Netzabruf;
  - Neustart mit abgelaufenem Eintrag: bedingter Abruf mit `If-None-Match`,
    304 verlängert die Ablaufzeit;
  - Massenabrufe nur im Speicher, Strukturbuch und Einzeltyp-Preise dauerhaft;
  - Charakter-Trennung löscht nur dessen Einträge;
  - LRU-Räumung;
  - anderes Compatibility-Date verworfen;
  - unlesbarer Inhalt wird aus dem Netz ersetzt;
  - unbenutzbare Datei lässt Abrufe weiterlaufen;
  - Seiten eines anderen Snapshots werden dauerhaft entfernt.
- Der Sicherungstest prüft, dass `caches` nicht in der `.nexusbackup` landet.
- `swift test` 564 + 70 Tests; `EVEStaticDataKit` 12; `xcodebuild … test`
  564 Tests, `TEST SUCCEEDED`.
- `swift-format lint --strict`: neue Dateien ohne Befund, keine neuen Befunde
  in den geänderten Dateien. `git diff --check` fehlerfrei.

Nicht geprüft:
- Verhalten in der laufenden App: Zähler `early` nach einem Neustart, Dauer
  und Dateigröße mit echten Charakteren.
- Eigentümerabnahme.

Offen: Auftrag 3, der Live-Lauf mit Auswertung (Startzeit, Main-Hub-Scan,
ESI-Last, CCP-Zähler) und Abnahmeliste.

## 23.10.2026 – Live-Lauf: Start, Main-Hub-Scan und ESI-Last

Ablauf:
- Der Eigentümer hat die App beendet und in Xcode neu gebaut und gestartet
  (Stand `3236ae9`): erster Start mit leerem dauerhaftem Cache um 21:29.
- Danach folgten ein zweiter Start um 21:31 und um 21:34 ein manueller
  Main-Hub-Scan über **Update**.
- Aufgezeichnet wurde mit `/usr/bin/log stream` (Kategorie `performance`). Die
  echte App wurde nicht ferngesteuert.

Ergebnisse (live geprüft, echte Daten):

| Messung | 1. Start (Cache leer) | 2. Start (Cache gefüllt) |
|---|---|---|
| Konfiguration bereit | 6,0 s | 5,3 s |
| Charaktere synchronisiert | 26,6 s | 17,8 s |
| Start abgeschlossen | 26,9 s | 18,2 s |
| Dauerhafter Cache beim Öffnen | 0 Einträge | 818 Einträge, 41 MB |

- Facility-Dogma kam beide Male aus der Katalogtabelle: 152 Typen in 4–5 ms.
- Zweiter Start bis zum Scan (2,8 min):
  - 780 Antworten von der Platte statt von ESI;
  - 343 Netzabrufe, davon 163 als 304.
  - Für den ersten Start fehlt die Anzahl der Netzabrufe, weil die
    ESI-Zusammenfassung erst beim nächsten Abruf nach 60 s erscheint und die
    App vorher beendet wurde (Messlücke).
- Main-Hub-Scan manuell, 24,5 s gesamt:

  | Phase | Dauer |
  |---|---|
  | Definitionen, Orderbuch, Preise, Systeme | 9,8 s |
  | Nachfrage | 0,9 s |
  | Namen, Klassifikationen, Volumen | 0,08 s (4.765 Volumen aus dem SDE, kein `/universe/types`-Abruf) |
  | Analyse | 1,0 s |
  | Speichern | 0,8 s |
  | Home-Hub | 1,5 s |
  | Coalition-Hub | 10,3 s |

  - Die ESI-Last des Scans: 458 Anfragen, davon 404 Seiten des
    Regions-Orderbuchs und 54 Strukturmarkt-Abrufe, rund 102 MB.
- Cache-Ordner danach: 55 MB.

CCP-Regelprüfung (live):
- Erfüllt:
  - User-Agent und Compatibility-Date bei allen Anfragen vorhanden, kein
    Datum in der Zukunft;
  - keine 420 und keine 429;
  - Token-Budgets weit im grünen Bereich (niedrigster Restwert `char-wallet`
    142);
  - im Scan selbst kein früher Abruf.
- Befund 1: 51 Antworten mit 4xx vor dem Scan, rechnerisch genau die 51
  Strukturdetail-Abrufe `/universe/structures/{id}` ohne 304.
  `PlayerStructureSearchService` fragt nicht zugängliche Strukturen bei jedem
  Start erneut ab (403, „inaccessible“) und merkt sich das nicht.
  - Folge: Das Fehlerbudget sank auf 49 von 100. Die App bremst erst bei 20;
    CCP rät von wiederholten 4xx ab, die je 5 Tokens kosten.
- Befund 2: Sechs frühe Abrufe des Strukturmarkt-Orderbuchs
  `/markets/structures/{id}/` vor dem Scan. Die Ursache ist nicht geklärt.
  Möglich sind ein zweiter Abruf derselben URL mit einem anderen Charakter
  oder ein Neulesen nach einem Snapshot-Wechsel. Der Zähler erkennt Abrufe
  nur je URL.

Eigentümerabnahme: am 23.10.2026 erteilt, für die statischen Daten aus dem
SDE, das Messprotokoll und den dauerhaften ESI-Cache. Grundlage war die
Abnahmeliste: Industrieprofile (Strukturen, Service-Module, Rigs),
Main-/Home-/Coalition-Hub-Chancen nach dem Scan, verpackte Volumen im Planner,
Charakterdaten nach dem Neustart und Geschwindigkeit.

Offen:
- Folgeaufträge:
  - nicht zugängliche Strukturen merken statt bei jedem Start erneut abfragen;
  - Ursache der frühen Strukturmarkt-Abrufe klären;
  - ESI-Zusammenfassung zusätzlich beim Startende schreiben.
