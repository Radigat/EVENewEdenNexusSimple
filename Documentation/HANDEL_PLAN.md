# Plan: Bereich „Handel“ (Hub-Preisvergleich, Handelsrouten, Logbuch mit Wallet-Abgleich)

Stand: 22.10.2026 · Status: **implementiert, automatisch geprüft** (P0–P8).
Live-Prüfung und Eigentümerabnahme sind offen, siehe Abschnitt H.

Grundlage ist ein Referenzbild des Eigentümers. Es zeigt Kacheln je
Marktgruppe, etwa *Harvest Equipment*, *Raw Moon Materials* und *Fullerenes*.
Jede Kachel enthält:

- die Chips „Source: Jita · Target: UALX · Items: N“,
- je einen Umschalter für Quelle und Ziel (Min-Sell | Max-Buy),
- eine Tabelle mit Name, Quellpreis, Zielpreis und Diff %. Pfeile kennzeichnen
  die Abweichungsstufen, fehlende Preise erscheinen als „—“.

Ziel ist ein eigener Bereich **Handel**. Er soll beantworten, welche Items ich
in Jita mitnehme und zu welchem Preis ich sie im Home- oder Coalition-Hub
verkaufe. Dazu kommen:

- Station Trading getrennt je Hub (am 22.10.2026 ersetzt durch Home ↔ Coalition,
  siehe Abschnitt I),
- Steuern und Gebühren beim Ein- und Verkauf,
- Logistik,
- tägliche Bedarfe und Mengen,
- ein Einkaufs-Logbuch, das mit den Wallet-Transaktionen der Charaktere
  abgeglichen wird.

## A. Entscheidungen des Eigentümers (22.10.2026)

| Thema | Entscheidung |
|---|---|
| Modi | Ursprünglich Import Main→Home, Import Main→Coalition, Station Trading Main / Home / Coalition. Seit 22.10.2026: Main→Home, Main→Coalition, Home→Coalition, Coalition→Home (Abschnitt I) |
| Kategorien | SDE-Marktgruppen werden importiert (Katalogadapter v5) |
| Einkauf | umschaltbar: Min-Sell (Sofortkauf, keine Gebühr) oder Max-Buy (eigene Buy-Order mit Broker-Gebühr) |
| Verkauf | Standard ist eine eingestellte Sell-Order (Steuer und Broker); Direktverkauf an eine Buy-Order ist eine Option (nur Steuer) |
| Tagesbedarf | Die Hub-Scans werden erweitert: Strukturen laden das volle Orderbuch. Hub-Chancen und Handel teilen sich einen gemeinsamen Bedarfs-Ledger |
| Mengen | nur Anzeige (Tagesbedarf, Ordertiefe, offene Logbuch-Mengen), keine Mengenempfehlung |
| Logbuch-Speicher | eigene SQLite-Datei `dataRoot/trade/trade-logbook.sqlite` nach dem Muster von `PublicContractStore`, kein SwiftData-Schemawechsel |
| Wallet-Abgleich | Käufe werden automatisch übernommen, Verkäufe nach FIFO zugeordnet |
| Charaktere | alle autorisierten Charaktere mit Wallet-Scope; der Charakter ist je Eintrag sichtbar |
| Fertigungskäufe | werden übernommen. Käufe von Materialien aktiver Produktionspläne erhalten den Status „Fertigung, ignoriert“, der sich manuell umschalten lässt |
| Ist-Gebühren | Umsatzsteuer **belegt** aus dem Wallet-Journal; Broker-Gebühr **berechnet** (Satz × Orderwert) und als „berechnet, nicht belegt“ markiert |

## B. Befunde im Quellcode (Stand 22.10.2026)

- **Marktgruppen:** `SQLiteStaticCatalog` speichert nur
  `item_types.market_group_id`. Es gibt weder eine Tabelle für Marktgruppen
  noch Namen oder eine Hierarchie.
  - `catalogAdapterVersion` steht auf 4. Eine Anhebung erzwingt keinen
    Neuimport, denn ältere Katalogdateien bleiben gültig. Neue Abfragen
    brauchen daher einen Guard, der prüft, ob die Tabelle existiert (Muster:
    `decryptors`).
  - Das Schema steht zweimal im Code, in `write(snapshot:)` und im
    Streaming-Writer.
- **Tagesbedarf:** Der Bedarf stammt aus `ManufacturingOpportunityDemandSnapshot`.
  Er wird aus dem Abbau überlebender Orders gemessen, mit Tageshistorie und
  `dailySummary(for:)`.
  - Bei NPC-Stationen deckt das vollständige Orderbuch alle Items ab.
  - Bei Spieler-Strukturen filtert
    `RuntimeState.secondaryHubMarketSnapshot` → `structureOrderSnapshot(typeIDs:)`
    auf Fertigungsprodukte. Für Handelsitems fehlt dort deshalb heute der Bedarf.
- **Wallet:** `ESIWalletTransactionDTO` dekodiert kein `location_id`,
  `journal_ref_id` und `is_personal`. Ohne diese Felder lässt sich kein Hub
  zuordnen.
  - Im Speicher liegt nur `RuntimeState.lastCharacterSync`, also nur ein
    Charakter.
  - ESI liefert Transaktionen nur für etwa 30 Tage. Das Logbuch muss sie
    deshalb selbst dauerhaft speichern.
- **Gebühren:** `MarketTaxConfiguration` liefert `effectiveSalesTaxRate` und
  `effectiveBrokerFeeRate` (inklusive Exordium-Zuschlag). Spieler-Strukturen
  brauchen eine manuelle Broker-Gebühr. `MarketPriceEngine` kennt bisher keine
  Broker-Gebühr auf Buy-Orders.
- **Logistik:** `LogisticsCostCalculator` rechnet je Vertrag
  `max(Volumen × ISK/m³, Collateral × 0,5 %)` und rundet auf 1 Mio. ISK auf.
  Der Jump Freighter läuft über `JumpFreighterLogisticsCalculator`.

## C. Fachformeln (Standardwerte)

Fehlende Werte ergeben `nil` und werden als „—“ angezeigt, nie als 0. Beim
Sortieren stehen sie deterministisch hinter (aufsteigend) bzw. vor
(absteigend) den bekannten Werten.

Abkürzungen:

- `sS`, `sB`: beste Sell- bzw. Buy-Order am Quell-Hub
- `tS`, `tB`: beste Sell- bzw. Buy-Order am Ziel-Hub
- `tax`, `brk`: Umsatzsteuer und Broker-Gebühr des jeweiligen Hubs
- `v`: gepacktes Volumen je Einheit

| Größe | Formel |
|---|---|
| Diff % | (Zielpreis − Quellpreis) / Quellpreis, jeweils gemäß Umschalter |
| Einkauf C | Min-Sell: `sS` · Max-Buy: `up(sB) × (1 + brk_src)` |
| Transport T (Import) | `max(v × ISK/m³, C × collateralRate)` nach der bestehenden Kurier-Max-Regel; in der Kachel als Richtwert ohne Rundung. Mit Menge über `LogisticsCostCalculator.calculateLegs` bzw. `JumpFreighterLogisticsCalculator`. Fehlt ISK/m³, ist T `nil` |
| Netto-Verkauf N | Sell-Order: `down(tS) × (1 − tax − brk)` · Direktverkauf: `tB × (1 − tax)` |
| Gewinn / Marge / ROI | `P = N − C − T` / `P ÷ N` / `P ÷ (C + T)` |
| Gewinn/m³ | `P ÷ v`; `nil`, wenn P fehlt oder v fehlt bzw. ≤ 0 ist (Abschnitt J) |
| Station Trading (entfernt am 22.10.2026) | `T = 0`, `P = down(S) × (1 − tax − brk) − up(B) × (1 + brk)`, Spread `(S − B) ÷ B` |
| Ist-Gewinn (Logbuch) | FIFO-Menge × (Ist-VK − belegte Steuer − berechneter Broker) − Ist-EK × (1 + brk) − Transportanteil |

Zusätzliche Regeln (Entscheidung zu U1 und U2 vom 22.10.2026):

- **Eigene Orders:** Eigene Orders werden um genau einen zulässigen Preisschritt
  verbessert. `down(p)` ist der nächste gültige Preis unterhalb von `p`, `up(p)`
  der nächste gültige Preis oberhalb.
  - Gültig sind Preise mit höchstens 4 signifikanten Stellen, mindestens aber
    0,01 ISK. Beispiele: 706.000 → 705.900, 5.490 → 5.489, 5,49 → 5,48.
  - Die Regel beruht auf dem Wissensstand des Assistenten und wurde nicht
    gegen eine CCP-Quelle belegt. Die Live-Prüfung steht aus.
  - Kachel und Diff % zeigen weiterhin die unveränderten besten Preise wie im
    Referenzbild.
- **Änderungsgebühren:** Gebühren für Relist bzw. Orderänderung werden **nicht**
  eingerechnet. Die Oberfläche weist darauf hin, dass sie im Ergebnis fehlen.
- **Collateral:** Basis ist der Einkaufswert C (bei Max-Buy einschließlich
  Broker). Es gilt die bestehende Max-Regel.
- **Route Main→Coalition** (Entscheidung vom 22.10.2026): zwei Etappen. Die
  erste ist Main→Home per Kurier mit dem Profil-Satz. Die zweite ist
  Home→Coalition wie bei den Hub-Chancen: per Jump Freighter, wenn er aktiviert
  ist, sonst per Kurier. Die Kosten beider Etappen werden addiert.
- **Jump Freighter je Einheit** (Entscheidung vom 22.10.2026): Ohne Menge gilt
  Flugkosten ÷ nutzbare Kapazität × Volumen, also ein Richtwert bei voller
  Ladung. Mit Menge wird jeder angefangene Flug voll bezahlt; ein Flug trägt
  ⌊Kapazität ÷ Volumen⌋ Einheiten.
- **Vertragslimit:** Ist eine einzelne Einheit größer als das
  Kurier-Vertragslimit, gilt der Transport als nicht verfügbar (manueller
  Transport) und nicht als kostenlos.

## D. Prompts

Arbeitsweise:

- Jeder Prompt endet mit einem Abschlussbericht. Er weist getrennt aus, was
  geplant, implementiert, automatisch geprüft und live geprüft ist, und nennt
  am Ende wörtlich den **nächsten Prompt**.
- Ist ein Punkt unklar oder müsste geraten werden, wird angehalten und
  nachgefragt. Danach werden dieses Dokument und der Folgeprompt angepasst.
- Vor jedem Prompt wird `git status` geprüft. Die Regeln aus `AGENTS.md`
  gelten. `PRODUCT.md` und `dev-diary.md` werden fortgeschrieben.
- Geprüft wird mit SwiftPM, mit `EVEStaticDataKit` separat und mit einem
  nativen Xcode-Debug-Build.
- Commits gibt es nur auf ausdrücklichen Auftrag.

| Prompt | Status |
|---|---|
| P0 Plan dokumentieren | erledigt (22.10.2026) |
| P1 SDE-Marktgruppen | implementiert, automatisch geprüft (22.10.2026); Neuimport und Live-Prüfung offen |
| P2 Handelsrechner | implementiert, automatisch geprüft (22.10.2026) |
| P3 Hub-Scans erweitern | implementiert, automatisch geprüft (22.10.2026); Live-Scan einer Struktur offen |
| P4 Handels-UI | implementiert, automatisch geprüft, mit synthetischem Katalog visuell geprüft (22.10.2026); Prüfung mit Live-Preisen offen |
| P5 Logbuch-Store | implementiert, automatisch und isoliert visuell geprüft (22.10.2026) |
| P6 Wallet-Daten | implementiert, automatisch geprüft (22.10.2026); Live-Abgleich mit echten Charakteren offen |
| P7 Automatischer Abgleich | implementiert, automatisch geprüft (22.10.2026); Live-Abgleich mit echten Wallets offen |
| P8 Gesamtprüfung | erledigt (22.10.2026): alle Läufe grün, Doku abgeglichen, Checkliste in Abschnitt H |

**P0: Plan dokumentieren**
> Lege `Documentation/HANDEL_PLAN.md` an. Es enthält die Entscheidungen, die
> Formeln, die Prompts P1–P8 und die offenen Punkte U1–U8. Verweise aus
> `ROADMAP.md` darauf. Kein Code.

**P1: SDE-Marktgruppen**
> Handel P1: Importiere die SDE-Marktgruppen.
> - In EVEStaticDataKit: `SDEDatasetKind.marketGroups`,
>   `StaticMarketGroupSnapshot` und ein Mapper.
> - Katalogadapter v5 mit der Tabelle `market_groups` und einem Index auf
>   `item_types.market_group_id`, in beiden Writern.
> - Die APIs `marketGroups()` und `tradeItems(inMarketGroupSubtree:)` prüfen
>   per Guard, ob die Tabelle existiert. Ein v4-Katalog liefert dann ein leeres
>   Ergebnis mit dem Hinweis „SDE-Neuimport nötig“.
> - Tests in EVEStaticDataKit und in den Katalogtests.
> Siehe Documentation/HANDEL_PLAN.md.

**P2: Handelsrechner (Core, rein)**
> Handel P2: Lege `Sources/EVENexusCore/Trade/TradeModels.swift` und
> `TradeCalculator.swift` an. Sie enthalten `TradeMode`, die Buy- und
> Sell-Seite, die Gebühren- und Transportbasis sowie `TradeRow` mit allen
> Formeln aus HANDEL_PLAN.md Abschnitt C.
> - `TradeCalculatorTests` prüfen dabei auch die Übereinstimmung mit
>   `MarketPriceEngine` bei listedSale (Netto auf denselben Bruttopreis).
> - Neu ist `MarketPriceTick.nextBelow(_:)` / `nextAbove(_:)` für die
>   4-Stellen-Regel, mit Grenzfalltests (Zehnerpotenzen, 0,01-Untergrenze).
> - U1 und U2 sind entschieden (Abschnitt C).

**P3: Hub-Scans erweitern (volles Orderbuch, Bedarf, Tiefe)**
> Handel P3: Ergänze `structureOrderSnapshot(typeIDs: Set<Int64>?)`, wobei
> `nil` alle Typen bedeutet.
> - Der Home- und der Coalition-Scan nutzen bei Strukturen das volle
>   Orderbuch und füttern damit den bestehenden Bedarfs-Ledger.
> - `MarketOrderTypeSummary` bekommt optional `bestSellVolume` und
>   `bestBuyVolume`.
> - Die Hub-Chancen-Ergebnisse bleiben unverändert; Regressionstests sichern
>   das ab.
> - Die Bedarfshistorie wird weitergeführt; der Scan lädt immer das volle
>   Orderbuch (U3 ist entschieden).

**P4: Handels-UI**
> Handel P4: Lege `NavigationSection.trade` („Handel“) nach
> `.coalitionHubOpportunities` an, dazu `TradeView.swift`.
> - Eine Modusleiste mit fünf Modi und eine Marktgruppen-Auswahl.
> - Kacheln wie im Referenzbild.
> - Detailspalten: Einkauf, Transport, Netto, Gewinn, Marge, ROI, Ø- und
>   aktueller Tagesbedarf am Ziel sowie Ordertiefe.
> - Namen über `EVEEntityText`, Spaltenköpfe über `SortableTableHeader`.
> - Lokalisierung en/de und Eintrag in der pbxproj.
> - RuntimeState liefert die Transportbasis:
>   - Main→Home: eine Kurier-Etappe mit dem Profil-Satz.
>   - Main→Coalition: dieselbe Kurier-Etappe plus die Home→Coalition-Etappe aus
>     `coalitionTransportBasis`.
>   - Für den Jump Freighter gilt: Flugkosten = Isotope je Flug × Ø
>     Isotopenpreis im Main Hub.
> - Kacheln sind die Kinder des gewählten Marktgruppen-Knotens; eigene Items
>   des Knotens bilden eine Zusatzkachel. Der Knoten wird modusübergreifend
>   gespeichert.
> - Pfeilschwellen 25 % und 30 % sind einstellbar; negative Diff bekommt einen
>   Abwärtspfeil.
> - Datenquellen:
>   - Main Hub: `mainHubMarketState`.
>   - Home und Coalition: `marketState` der Hub-Chancen.
>   - Tagesbedarf: die vorhandenen Bedarfssnapshots.
>   - Gebühren: `MarketTaxConfiguration` der Hub-Rollen.
> - U4 ist entschieden.

**P5: Logbuch-Store und manuelle Einträge**
> Handel P5: Lege `TradeLogbookStore` an (CSQLite, Migrationen über
> `user_version`), gespeichert unter `dataRoot/trade/trade-logbook.sqlite`.
> - Das Schema umfasst:
>   - Einkäufe,
>   - Verkaufszuordnungen,
>   - Status (gekauft / unterwegs / gelistet / verkauft / Fertigung-ignoriert /
>     ausgeschlossen),
>   - geplanten Ziel-VK.
> - Ein eigener Seitenleisteneintrag „Handelslogbuch“ (`NavigationSection`)
>   direkt unter „Handel“.
> - Die Erinnerung läuft nur in der App: Je Eintrag stehen der geplante VK und
>   der aktuelle beste Sell-Preis am Ziel-Hub nebeneinander. Hervorgehoben
>   wird, wenn der Zielpreis erreicht ist. Es gibt keine
>   Systembenachrichtigung.
> - Einträge entstehen über „Ins Logbuch“ aus einer Kachelzeile oder manuell.
> - Im Handels-UI kommt die Spalte „offene Logbuch-Menge“ dazu.
> - Store-Tests, Lokalisierung en/de, pbxproj.

**P6: Wallet-Daten aller Charaktere**
> Handel P6: Erweitere `ESIWalletTransactionDTO` additiv um `locationID`,
> `journalRefID` und `isPersonal`.
> - Nach jeder Charakter-Synchronisierung (`RuntimeState.syncCharacter`, beim
>   Start ohnehin für alle autorisierten Charaktere) werden die
>   Wallet-Transaktionen und das Wallet-Journal dieses Charakters idempotent
>   in der Logbuch-DB gespeichert. Das geschieht per Migration `user_version` 2
>   mit eigenen Tabellen, Schlüssel ist die `transaction_id` bzw. die
>   Journal-ID. So bleiben die Daten über die 30-Tage-Grenze von ESI hinaus
>   erhalten.
> - Nur persönliche Charakter-Wallets, keine Corporation-Wallet.
> - Im Handelslogbuch:
>   - ein Knopf „Wallets abgleichen“, der alle autorisierten Charaktere
>     synchronisiert,
>   - eine Statuszeile je Charakter (Stand, fehlend, verboten, veraltet).
> - Eine Zuordnung zu Logbuch-Einträgen gibt es noch nicht (P7).
> - Store- und App-Tests, Lokalisierung, pbxproj. U5 ist entschieden.

**P7: Automatischer Abgleich (FIFO)**
> Handel P7: Automatischer Abgleich der gespeicherten Wallet-Transaktionen
> mit dem Logbuch (Regeln in Abschnitt E, U6–U8 und P7-Rückfragen).
> - **Käufe:** Kauftransaktionen ab dem einstellbaren Startdatum (Standard:
>   Tag der Einrichtung) werden übernommen, wenn sie in einem der drei Hubs
>   liegen (Ort = konfigurierte Station oder Struktur).
>   - Jede Transaktion wird ein eigener Eintrag, gespeichert mit Charakter und
>     Transaktions-ID. Ein erneuter Abgleich legt nichts doppelt an.
>   - Ziel-Hub: Main → Home, sonst derselbe Hub.
>   - Käufe von Materialien aktiver Planner-Pläne (`StoredPlan.isActive`)
>     erhalten den Status „Fertigung, ignoriert“.
>   - Transport wird für die Menge geschätzt und als „geschätzt“ markiert;
>     manuell überschreibbar.
> - **Verkäufe:** Zuordnung nach FIFO je Item und Ziel-Hub zu den ältesten
>   offenen Einkäufen. Verkäufe an anderen Orten bleiben als „nicht
>   zugeordnet“ sichtbar und lassen sich manuell zuordnen.
> - **Gebühren:**
>   - Die Umsatzsteuer gilt als belegt, sie kommt aus dem Journal
>     (`transaction_tax`, Kontext = Transaktions-ID).
>   - Der Broker ist berechnet: Satz × Orderwert, markiert als „berechnet,
>     nicht belegt“.
> - **Orderart:** Sie wird aus der Orderhistorie bzw. den offenen Orders des
>   Charakters erkannt (eigene Buy- oder Sell-Order zu Item, Ort und Preis).
>   Ist sie nicht erkennbar, gilt beim Kauf Sofortkauf, beim Verkauf eine
>   eigene Sell-Order; beides wird als „angenommen“ markiert.
> - **Anzeige:** Ist- und Planwerte stehen nebeneinander, Abweichungen werden
>   hervorgehoben.
> - Store-Migration (Verknüpfungstabellen), Tests, Lokalisierung, pbxproj.

**P8: Gesamtprüfung und Abnahme-Checkliste**
> Handel P8: Gesamtprüfung mit SwiftPM, EVEStaticDataKit und Xcode Debug.
> - Abgleich von PRODUCT.md, ARCHITECTURE.md, PROJECT_STATE.md,
>   FEATURE_COVERAGE.md und DECISIONS.md.
> - Eine Abnahme-Checkliste für den Eigentümer; die Live-ESI-Prüfung ist
>   opt-in.

## E. Offene Punkte

Diese Punkte werden im jeweiligen Prompt vor dem Start beim Eigentümer
erfragt. Bis dahin gilt nichts davon als entschieden.

- **U1 (P2), Transport:** entschieden am 22.10.2026. Es gilt die Max-Regel,
  Collateral-Basis ist der Einkaufswert C.
- **U2 (P2), Orderpreise:** entschieden am 22.10.2026. Eigene Orders werden um
  einen zulässigen Preisschritt (4 signifikante Stellen) verbessert.
  Relist-Gebühren werden nicht eingerechnet; ein Hinweis macht das sichtbar.
- **U3 (P3), Bedarfsmessung:** entschieden am 22.10.2026.
  - Die bestehende Bedarfshistorie wird weitergeführt; Fertigungsprodukte
    behalten ihre Tageshistorie.
  - Neue Handelsitems starten ohne Historie und zeigen „—“, bis zwei Scans im
    Abstand von mindestens 30 Minuten vorliegen.
  - Strukturen laden bei **jedem** Home- und Coalition-Scan das volle
    Orderbuch, auch beim automatischen Start. Die längere Scan-Dauer und die
    größere Bedarfsdatei sind akzeptiert.
- **U4 (P4), Kachel-Ebene:** entschieden am 22.10.2026.
  - Der Nutzer wählt einen Knoten im Marktgruppen-Baum. Jede direkte
    Untergruppe wird zu einer Kachel mit allen Items ihres Teilbaums.
  - Hat der Knoten selbst Items, bilden sie eine zusätzliche Kachel mit dem
    Namen des Knotens.
  - Der zuletzt gewählte Knoten wird gespeichert und gilt gemeinsam für alle
    fünf Modi.
  - Pfeile: Es gibt zwei einstellbare Schwellen für die Diff %, Standard 25 %
    (einfacher Pfeil nach oben) und 30 % (Doppelpfeil). Eine negative
    Differenz bekommt einen Pfeil nach unten. Die Schwellen gelten für alle
    Kacheln.
- **P5-Rückfragen:** entschieden am 22.10.2026. Die Erinnerung läuft nur in
  der App (geplanter VK neben aktuellem Zielpreis, Hervorhebung bei
  Erreichen), ohne macOS-Mitteilung. Das Logbuch bekommt einen eigenen
  Seitenleisteneintrag „Handelslogbuch“ unter „Handel“.
- **U5 (P6), Corporation-Wallet:** entschieden am 22.10.2026. Es werden nur
  die persönlichen Charakter-Wallets genutzt. Die Übernahme erfolgt nach jeder
  Charakter-Synchronisierung und zusätzlich über den Knopf „Wallets
  abgleichen“ im Handelslogbuch.
- **U6 (P7), FIFO-Grenzen:** entschieden am 22.10.2026. FIFO gilt je Item und
  Ziel-Hub. Verkäufe an anderen Orten bleiben „nicht zugeordnet“ und lassen
  sich manuell zuordnen.
- **U7 (P7), aktiver Produktionsplan:** entschieden am 22.10.2026. Als
  Fertigungsmaterial gelten Materialien von Planner-Plänen mit
  `StoredPlan.isActive`.
- **U8 (P7), Ist-Transportkosten:** entschieden am 22.10.2026. Der Transport
  wird beim Anlegen für die Menge geschätzt (aktuelle Transportbasis), als
  „geschätzt“ markiert und ist manuell überschreibbar.
- **P7-Rückfragen:** entschieden am 22.10.2026.
  - Ziel-Hub automatisch übernommener Käufe: Main → Home, sonst derselbe Hub.
  - Ein Eintrag je Transaktion, ohne Bündelung.
  - Übernahme erst ab einem einstellbaren Startdatum (Standard: Tag der
    Einrichtung).
  - Festgelegt ohne Rückfrage, weil es aus der Aussage „Direktverkauf ist
    selten“ folgt: Die Orderart wird aus der Orderhistorie erkannt. Ist sie
    nicht erkennbar, gilt Sofortkauf bzw. eigene Sell-Order, markiert als
    „angenommen“.

## F. Wiederverwendung

- `MarketTaxConfiguration`, `ProductionBasis` (Hub-Rollen, Gebühren)
- `LogisticsCostCalculator`, `JumpFreighterLogisticsCalculator`,
  `OpportunityCoalitionTransportBasis`
- `TradeHubMarketService.locationOrderSnapshot` / `structureOrderSnapshot`
- `ManufacturingOpportunityDemandSnapshot.dailySummary(for:)`
- `CharacterSyncService` (Wallet-Paging)
- `PublicContractStore` als Muster für den Store
- `EVEEntityText`, `SortableTableHeader`, `AppTableSortDescriptor`,
  `ISKAmount`
- `MarketPriceEngine` als Testreferenz

## G. Verifikation

- `swift build` und `swift test` im Projektstamm, `swift test --package-path
  Packages/EVEStaticDataKit` und ein natives Xcode-Debug-Build.
- Manuelle Prüfung in der App:
  - Nach dem SDE-Neuimport erscheinen die Marktgruppen.
  - Die Kachel Harvest Equipment liefert im Modus Main→Home plausible Preise
    und Diff %.
  - Tagesbedarf und Ordertiefe sind sichtbar.
  - Ein Testkauf erscheint nach der Wallet-Synchronisierung im Logbuch.
  - Der Verkauf wird nach FIFO zugeordnet.
  - Die belegte Steuer und der berechnete Broker sind korrekt ausgewiesen.
- Jedes Ergebnis wird mit seiner Nachweisstufe ausgewiesen.

## H. Abnahme-Checkliste für den Eigentümer

Ehrlicher Stand: Alles unten ist automatisch geprüft und in einer isolierten
Testinstanz angesehen, aber **nicht** mit echten Daten ausprobiert. Die
Live-ESI-Prüfung ist opt-in und gehört dir. Bitte jeden Punkt abhaken oder mit
Befund zurückmelden.

**Vorbereitung**
- [ ] In **Daten & Einstellungen → Allgemein** eine Sicherung anlegen, bevor der
      neue Build die Logbuch-Datei anlegt und die SDE neu importiert wird.

**SDE-Marktgruppen (P1)**
- [ ] **Daten & Einstellungen → SDE → Neuimport des aktuellen Katalogs** und
      danach die App neu starten.
      - Erwartung: Der Import gelingt.
      - Bricht er mit fehlender `marketGroups.jsonl` ab, bitte sofort melden;
        das ist die einzige ungeprüfte Annahme dieses Schritts.
- [ ] Im Bereich **Handel** erscheinen über „Alle Marktgruppen“ die Wurzelgruppen
      wie im Ingame-Markt (z. B. Ship Equipment, Manufacture & Research).

**Hub-Scans (P3)**
- [ ] **Hub-Märkte aktualisieren** ausführen.
      - Erwartung: Main-, Home- und Coalition-Scan laufen durch.
      - Bitte die Dauer des Strukturscans notieren.
- [ ] Die Hub-Chancen zeigen für Fertigungsprodukte dieselben Werte wie vor dem
      Update.

**Handel (P2/P4)**
- [ ] Im Modus Main → Home zur Kachel **Harvest Equipment** und zu den **Raw Moon
      Materials** navigieren. Die Preise Min-Sell Jita und Home, Diff % und die
      Pfeile mit dem Referenzbild und dem Ingame-Markt vergleichen.
- [ ] Mit **Details anzeigen** prüfen:
      - Einkauf (Max-Buy enthält die Broker-Gebühr),
      - Netto-Verkauf mit den Sätzen aus den Markteinstellungen,
      - Transport mit dem Profil-Kurier bzw. dem Jump Freighter für Coalition.
- [ ] **4-Stellen-Preisschritt:** Bei einer Order um 706.000 ISK rechnet die App
      eine eigene Sell-Order zu 705.900. Bitte ingame bestätigen, dass das der
      nächste zulässige Preis ist. Das ist eine Annahme ohne CCP-Beleg.
- [ ] Home → Coalition und Coalition → Home liefern plausible Werte; der
      Transport nutzt die Home-↔-Coalition-Etappe in der jeweiligen Richtung.
- [ ] Tagesbedarf und Tiefe erscheinen. Für neue Items braucht es dafür zwei
      Scans im Abstand von mindestens 30 Minuten.

**Handelslogbuch (P5)**
- [ ] „Ins Logbuch“ an einer Zeile, Menge eintragen, speichern.
      - Der Eintrag steht im **Handelslogbuch**.
      - Im Handel zeigt „Offen (Logbuch)“ die Menge.
- [ ] Die Erinnerung zeigt „Zielpreis erreicht“ bzw. „unter Plan“, sobald
      Marktdaten in der Sitzung vorliegen.
- [ ] Einen Teilverkauf von Hand erfassen und den realisierten Gewinn
      nachrechnen.

**Wallet und Abgleich (P6/P7)**
- [ ] **Wallets abgleichen**:
      - Jeder Charakter hat eine Statuszeile.
      - Fehlende Berechtigungen werden als solche angezeigt.
- [ ] **Käufe übernehmen ab** auf ein Datum vor einem bekannten Jita-Kauf
      setzen.
      - Der Kauf erscheint mit Wallet-Symbol, Ziel Home Hub und geschätztem
        Transport.
      - Die Kaufart ist erkannt oder als angenommen markiert.
- [ ] Ein Kauf eines Materials aus einem aktiven Planner-Plan erscheint als
      „Fertigung, ignoriert“.
- [ ] Ein Verkauf am Ziel-Hub ist nach FIFO zugeordnet.
      - Die belegte Steuer stimmt mit dem Wallet-Journal überein.
      - Die Broker-Gebühr ist berechnet.
- [ ] Ein Verkauf an einem anderen Ort erscheint unter „Nicht zugeordnete
      Verkäufe“ und lässt sich per **Zuordnen** zuweisen.
- [ ] Nach einem Neustart und einem weiteren Abgleich gibt es keine doppelten
      Einträge.

**Rückmeldung**
- [ ] Gefundene Abweichungen mit Item, Hub, erwartetem und angezeigtem Wert
      melden. Daraus werden gezielte Fehlerkorrekturen.

## I. Nachtrag 22.10.2026: Routen statt Station Trading

Eigentümerauftrag nach Abschluss von P8:
- Station Trading Main, Home und Coalition wird entfernt (Rückfrage: alle drei).
- Neu ist Handel zwischen Home und Coalition Hub in beide Richtungen.

Entscheidungen:
- **Routen:** Main → Home, Main → Coalition, Home → Coalition, Coalition → Home
  (`TradeMode`, `TradeRoute`). Eine gespeicherte alte Auswahl fällt auf
  Main → Home zurück.
- **Transport:**
  - Home ↔ Coalition nutzt die Home-→-Coalition-Etappe der Hub-Chancen (Jump
    Freighter oder Profil-Kurier). Für Coalition → Home werden Start und Ziel
    getauscht.
  - Annahme: Die Treibstoffkosten je Jump-Freighter-Flug sind in beiden
    Richtungen gleich. Die Sprungdistanz ist symmetrisch; abweichende
    Routenprofile sind nicht berücksichtigt.
- **Wallet-Abgleich (Rückfrage):** Käufe im Home Hub bekommen das Ziel
  Coalition Hub, Käufe im Coalition Hub das Ziel Home Hub, jeweils mit
  geschätztem Transport. Ist der andere Hub nicht eingerichtet oder derselbe
  Ort, bleibt der Kauf-Hub das Ziel (Transport 0).
- Die Station-Trading-Formel in Abschnitt C bleibt nur als Verlauf stehen.

## J. Nachtrag 23.10.2026: Top-20-Kachel

Eigentümerauftrag: In einer gewählten Marktgruppe soll vor den
Untergruppen-Kacheln (Battlecruisers usw.) ein erster Block mit den 20 Items
stehen, die gemäß der Auswahl von Quelle und Ziel die höchste Differenz haben.
Wahlweise soll die Rangfolge nach ISK pro m³ gelten, damit das Volumen
einfließt. So muss man nicht erst alle Kacheln durchsehen.

Eigentümerentscheidungen (Rückfragen vom 23.10.2026):
1. Die Rangfolge ist umschaltbar zwischen Diff % und Gewinn/m³. Gewinn/m³ ist
   der Gewinn nach Steuer, Broker und Transport ÷ Packvolumen (Abschnitt C),
   nicht die Rohdifferenz.
2. Die Top-20-Kachel gilt nur innerhalb der gewählten Marktgruppe. Auf der
   Ebene „Alle Marktgruppen“ gibt es keine.
3. Die Spalte Gewinn/m³ steht in allen Kacheln, immer sichtbar, direkt nach
   Diff %.
4. Gerankt werden nur Items mit positivem Wert. Gibt es weniger als 20, ist die
   Liste kürzer. Unbekannte Werte und Werte ≤ 0 werden getrennt als Anzahl
   ausgewiesen.
5. Die Top-Kachel hat eine eigene Sortierung. Beim Start und bei jedem Wechsel
   der Kennzahl gilt: Kennzahl absteigend. Klicks auf die Spaltenköpfe sortieren
   nur sie; die übrigen Kacheln teilen ihre gemeinsame Sortierung.
6. Die Kachel erscheint nur, wenn die gewählte Gruppe mehr als eine Kachel oder
   mehr als 20 Items hat.

Rechenkern: `TradeRow.profitPerCubicMeter`, `TradeSortColumn.profitPerCubicMeter`,
`TradeTopRankingMetric` (gespeicherte Raw-Werte `difference`,
`profitPerCubicMeter`) und `TradeTopRanking` (Grenze 20, Gleichstand nach
Type-ID).

Umsetzung in vier Teilen: (1) Rechenkern und Tests, (2) Spalte Gewinn/m³,
(3) Top-20-Kachel, (4) Gesamtprüfung. Stand und Prüfnachweise je Teil stehen im
[Entwicklungstagebuch](../dev-diary.md).

## K. Nachtrag 23.10.2026: Top-20 nach Gewinn/m³ oder ROI

Eigentümerauftrag: Die Rangfolge nach Diff % ergibt keinen Sinn, weil eine hohe
Preisdifferenz allein nichts über den Gewinn sagt. Entscheidend ist der Gewinn
nach Steuer, Broker und Transport: Er muss positiv sein, und Gewinn/m³ oder ROI
sollen möglichst hoch sein. Die Rangfolge nach Diff % entfällt.

Eigentümerentscheidungen (Rückfragen vom 23.10.2026), ersetzen Punkt 1 und
ergänzen Punkt 4 aus Abschnitt J:
1. Die Rangfolge ist umschaltbar zwischen Gewinn/m³ und ROI. ROI ist der
   Gewinn ÷ (Einkauf + Transport) aus Abschnitt C.
2. Nur die Rangfolge nach Diff % entfällt. Die Spalte Diff % bleibt in allen
   Kacheln, auch in der Top-20-Kachel.
3. Gerankt wird nur, wer einen bekannten Gewinn > 0 und einen bekannten
   Kennzahlwert > 0 hat. Unbekannter Kennzahlwert zählt als „ohne bekannten
   Wert“; bekannter Kennzahlwert mit Gewinn oder Wert ≤ 0 bzw. unbekanntem
   Gewinn zählt als „ohne positiven Gewinn oder Wert“.
4. Bei Rangfolge nach ROI zeigt die Top-20-Kachel die Spalte ROI immer, auch
   ohne Details, direkt nach Gewinn/m³. In den Detailspalten dieser Tabelle
   steht ROI dann nicht ein zweites Mal.

Rechenkern: `TradeTopRankingMetric` mit den gespeicherten Raw-Werten
`profitPerCubicMeter` und `returnOnInvestment`. Ein gespeicherter Altwert
`difference` wird nicht mehr erkannt und fällt auf Gewinn/m³ zurück; der
UserDefaults-Schlüssel `trade.top-ranking` bleibt unverändert.

## L. Nachtrag 24.10.2026: Handelsvolumen aus der ESI-Markthistorie

Eigentümerauftrag: Gewinn je Stück, Gewinn/m³ und ROI reichen nicht. Ein Item,
das kaum gehandelt wird, bringt trotz hoher Marge wenig. Gebraucht wird je Item,
wie viel in den letzten 1, 2, 5, 7 und 30 Tagen gehandelt wurde.

Eigentümerentscheidungen (Rückfragen vom 24.10.2026):
1. Gezeigt wird nur das Gesamtvolumen. ESI trennt die Historie nicht nach
   Kauf- und Verkaufsseite; eine geschätzte Aufteilung gibt es nicht.
2. Abgeleitete Kennzahlen: Ø Stück/Tag und Gewinnpotenzial/Tag.
3. Zeiträume 1/2/5/7/30 Tage. Der gewählte Zeitraum steht als Spalte, alle
   fünf im Tooltip.
4. Die Top-20-Rangfolge bleibt unverändert.

Quelle: `GET /markets/{region_id}/history/?type_id=` (öffentlich, ein Abruf je
Item) für die Region des Zielhubs der Route. Fehlt die Region, bleibt der Wert
unbekannt.

Formeln (Rechenkern `MarketTypeVolumeHistory`, `TradeDisplayRow`):
- Ankertag A = UTC-Tag vor dem UTC-Datum von `Last-Modified`; ohne Header der
  UTC-Tag vor dem Abruf. Liefert ESI einen Tag nach A, wird dieser Tag zu A.
- Gehandelt(N) = Summe `volume` der UTC-Tage A−N+1 … A. Tage ohne Eintrag
  zählen 0, weil ESI Tage ohne Handel auslässt. Eine leere Antwort ist 0.
  Zeilen mit unlesbarem Datum oder negativem Volumen werden verworfen.
- Ø Stück/Tag(N) = Gehandelt(N) ÷ N.
- Gewinn/Tag(N) = Gewinn je Stück (Abschnitt C) × Ø Stück/Tag(N), eine
  Obergrenze. Ohne Gewinn oder Historie unbekannt; negativer Gewinn bleibt
  negativ.
- Ein fehlgeschlagener Abruf (404, Fehler) ist „nicht verfügbar“, nie 0. Ein
  404 wird 24 Stunden gemerkt.

Abruf: `TradeHubMarketService.volumeHistory(typeIDs:regionID:)` mit höchstens
vier gleichzeitigen Anfragen. Der ESI-Antwortcache speichert die Historie
dauerhaft bis `Expires`. `RuntimeState` hält die Ergebnisse je Region nur im
Arbeitsspeicher und lädt nur Items nach, die fehlen oder deren Ankertag vor
gestern (UTC) liegt.

Offen: Die Ankerregel ist nur gegen synthetische Antworten getestet. Ob
`Last-Modified` der Historie wie angenommen das Datum der täglichen
Aktualisierung trägt, bestätigt erst eine Live-Abnahme (opt-in).

## M. Nachtrag 24.10.2026: Volumen am Zielhub selbst

Eigentümerauftrag: Das Handelsvolumen muss das Volumen am Zielort zeigen. Die
ESI-Markthistorie gibt es nur je Region. Entscheidung des Eigentümers: zusätzlich
ein hub-genaues Volumen je Zeitraum aus dem Bedarfsledger des Zielhubs zeigen
und die Regionsspalte klar als Region beschriften.

Formel (`ManufacturingOpportunityDemandSnapshot.hubTradedVolume`):
- Grundlage sind die Tagesdatensätze des Ledgers: je UTC-Tag mit Scan die
  zuletzt gültige 24-Stunden-Schätzung der Stück, die aus weiterhin gelisteten
  Orders des Zielhubs verschwunden sind (Untergrenze; Methode
  `exact-hub-rolling-24h-surviving-order-depletion-daily-history-v3`).
- Zielhub(N) = Summe dieser Tageswerte der UTC-Tage heute−N+1 … heute, dazu
  die Zahl der erfassten Tage. Tage ohne Datensatz für das Item sind unbekannt
  und zählen nicht als 0. Ohne erfassten Tag ist der Wert unbekannt.
- Sortiert wird nach der Summe; ein unvollständiger Zeitraum wird in
  Warnfarbe gezeigt und im Tooltip mit „k von N Tagen“ belegt.

Beschriftung: „Zielhub N T“, „Region N T“, „Gewinn/Tag (Region)“,
„Ø Region/Tag“. Gewinn/Tag rechnet weiter mit dem Regionsvolumen.

## N. Nachtrag 24.10.2026: Einziger Markt der Region

Eigentümerbefund: In Tenerifis gibt es nur den Markt in UALX-3, trotzdem
weichen „Zielhub“ und „Region“ ab. Ursache: Der Ledger zählt nur Abnahmen
weiterhin gelisteter Orders; eine komplett gekaufte Order verschwindet und
zählt nicht. Eigentümerentscheidung: eine Einstellung in der App, mit der ein
Handelsort als einziger Markt seiner Region markiert wird.

Regeln:
- `TradingLocationConfiguration.isOnlyMarketInRegion`, Standard `false`,
  Schalter je Handelsort in den Markteinstellungen. Gespeichert wird das Feld
  nur, wenn es gesetzt ist. Ein Wechsel auf einen anderen Ort
  (`updateTradingLocation` mit anderer `locationID`) setzt es zurück.
- Ist es beim Zielhub der Route gesetzt, gilt für „Zielhub N T“
  `HubTradedVolume.regionHistory`: Gehandelt(N) der Regionshistorie (Abschnitt
  L), N von N Tagen erfasst. Die Spalte heißt dann „Zielhub N T (Region)“.
- Die App prüft nicht, ob die Region wirklich nur einen Markt hat; das ist eine
  Aussage des Eigentümers.

## O. Nachtrag 24.10.2026: Gewinnpotenzial je Zeitraum

Eigentümerauftrag: je eine Spalte, die den Gewinn je Stück mit der Stückzahl
des gewählten Zeitraums multipliziert, einmal für den Zielhub, einmal für die
Region.

Formeln (`TradeDisplayRow.hubProfitPotential`, `regionProfitPotential`):
- Gewinnpot. Zielhub(N) = Gewinn je Stück (Abschnitt C) × Zielhub(N)
  (Abschnitt M, bzw. Regionshistorie bei „Einziger Markt der Region“,
  Abschnitt N).
- Gewinnpot. Region(N) = Gewinn je Stück × Gehandelt(N) (Abschnitt L).
- Ohne Gewinn oder Volumen unbekannt, nie 0; ein negativer Gewinn bleibt
  negativ. Beide sind Obergrenzen, weil sich andere Händler das Volumen
  teilen. Ein unvollständiger Zielhub-Zeitraum wird in Warnfarbe gezeigt.

Beschriftung: „Gewinnpot. Zielhub N T“ (bzw. „… (Region)“) und
„Gewinnpot. Region N T“, sortierbar, nach „Gewinn/Tag (Region)“, in ganzen ISK.
