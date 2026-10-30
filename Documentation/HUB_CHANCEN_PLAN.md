# Plan: Ablaufdiagramm, Home-/Coalition-Hub-Chancen und Produktionsentscheidung

Stand: 21.10.2026 · Status: **implementiert, automatisch geprüft** (P0–P13). Live- und Eigentümerabnahme offen; siehe Abschnitt E.

Grundlage ist das Ablaufdiagramm des Eigentümers:

Programmstart → ESI laden → (a) Reaktionen, Blueprints, Lager, Mond- und
Mineralien-Kaufanalyse, (b) Dashboard-Update, (c) öffentliche Verträge sowie
Main-, Home- und Coalition-Hub-Chancen → Planer und Hub-Chancen →
Produktionsplanung.

Bei der Produktionsplanung entscheidet der Eigentümer:

- **Zielmarkt:** Main Hub, Home Hub, Coalition Hub oder Allianzmarkt (Slack).
- **Item:** nach ROI, Bedarf oder eigener Entscheidung.

Im Moment der Wahl prüft die App:

- BPC-/BPO-Bestand,
- BPC-/BPO-Kosten,
- Materialbedarf: was am Main Hub gekauft wird und welche Mineralien an welchem Ort.

Alle Berechnungen sollen auf bereits abgerufenen Daten beruhen.

Entscheidungen des Eigentümers (20.10.2026):

- **Allianzmarkt (Slack)** ist ein manuelles Verkaufsziel. Preis und Menge werden
  selbst eingetragen; es gibt keine Slack-API-Anbindung.
- **Programmstart:** Alle Daten werden automatisch geladen, auch die schweren Scans.
  Das ersetzt die heutigen Opt-ins für den automatischen Main-Hub-Scan und für die
  Fortsetzung des Vertragsindex. Diese bewusste Regeländerung wird in P1 in
  [DECISIONS.md](Consolidation/DECISIONS.md) dokumentiert.

Evidenzgrenze: Die Bewertung in Abschnitt A stützt sich auf den
Dokumentationsstand von [PRODUCT.md](../PRODUCT.md) und
[ARCHITECTURE.md](../ARCHITECTURE.md) vom 20.10.2026. Prompt P0 prüft sie gegen
den Quellcode.

## A. Abgleich Diagramm ↔ Ausgangsstand vom 20.10.2026

Die Tabelle zeigt den Stand vor der Umsetzung. Was daraus umgesetzt wurde, steht in Abschnitt B.

| # | Diagrammpunkt | Stand | Beleg / Lücke |
|---|---|---|---|
| 1 | Programmstart → ESI laden | 🟡 teilweise | Beim Start laden SDE, Dienststatus, Bedarfsledger und der letzte Chancen-Snapshot. Die Vertragsautomatik startet nach mindestens 15 s, aber nur nach Opt-in. Der Charakter-Sync läuft erst beim **ersten Dashboard-Aufruf**. Der Main-Hub-Scan läuft nur manuell, per Opt-in oder über „Beim Öffnen prüfen“. Einen zentralen Startablauf gibt es nicht. |
| 2 | ESI → Lager, Blueprints | ✅ | Vollständiger Charakter-Sync: Assets, Blueprints, Jobs, Orders, Wallet und Corporation-Bestände. |
| 3 | ESI → Reaktionen, Mond- und Mineralien-Kaufanalyse | ✅ (auf Abruf) | Über `SharedAnalysisRefresh` mit 5-Minuten-Wiederverwendung und Dashboard-Karten. Es gibt keinen ausdrücklichen Start beim Programmstart. |
| 4 | Dashboard-Update | ✅ | Jobs, Kapazität, Wallet, Nettowert, negative Reaktionen, Mond/Mineral und Ticker. |
| 5 | Dashboard → Planer / Hub-Chancen | ❌ | Das Dashboard hat keine Chancen-Kacheln und keine Sprünge zu Hub-Chancen oder Planer. Vorhanden ist nur der Detailsprung zu den Reaktionen. |
| 6 | Öffentliche Verträge laden | ✅ (Opt-in) | Lokaler, fortsetzbarer Index mit 6-Stunden-Refresh. |
| 7 | Main-Hub-Chancen | ✅ | Kandidaten, ROI, Gewinn, Tagesbedarf (30-Tage-Ledger), ISK/h, Filter, Favoriten; **Bauen** übergibt an den Planner. |
| 8 | Home-Hub-Chancen | ❌ | Scan, Bedarfsledger und Ansicht gibt es nur für den Main Hub. |
| 9 | Coalition-Hub-Chancen | ❌ | Wie Home Hub. Der Coalition Hub ist eine Player Structure und braucht den Structure-Market-Scope. |
| 10 | Verträge → Hub-Chancen | ❌ | Die Chancen nutzen nur Sell-Orders am Main Hub. Vertragspreise fließen nur in Planner-Szenarien und BPC-Kosten. |
| 11 | Planer | ✅ | Produktionsgraph, Build/Buy, Lager, Logistik, Gebühren und 9 Verkaufsszenarien (Main/Home/Coalition × Sofortverkauf/Order/Vertrag). |
| 12 | Entscheidung Zielmarkt Main/Home/Coalition | 🟡 | Alle drei Hubs werden als Szenarien gerechnet. Ein ausdrücklich gewählter Zielmarkt wird aber weder im Plan noch in der Produktionsübersicht gespeichert. |
| 13 | Allianzmarkt (Slack) | ❌ | Es gibt kein manuelles Verkaufsziel. |
| 14 | Itemwahl: ROI, Bedarf, eigene Entscheidung | 🟡 | Für den Main Hub vollständig: ROI, Tagesbedarf, Favoriten und freie Planner-Eingabe. Für Home und Coalition fehlen ROI- und Bedarfsdaten. |
| 15 | BPC-/BPO-Bestand prüfen | ✅ | Planner-Fläche BPO/BPC mit Standortabgleich, Transfer und Vertragsabdeckung. |
| 16 | BPC-/BPO-Kostenkalkulation | ✅ | Seit Commit b6e2547: Vertragspreis je Run, Schätzung der Kopier- und Inventionskosten, Herkunft sichtbar. |
| 17 | Materialbedarf: was am Main Hub kaufen | ✅ | Einkaufsliste mit Multibuy, Lagerverbrauch, Make-or-Buy und komprimiertes Erz. |
| 18 | Materialbedarf: welche Mineralien wo kaufen | 🟡 | Die Mineralien- und Mond-Kaufanalyse mit Kaufort-Empfehlung gibt es, sie ist aber **nicht** mit dem Plan verbunden. Der Planner kauft immer am Main Hub. |
| 19 | Rechnung aus bereits abgerufenen Daten | 🟡 | Chancen und Analysen nutzen Snapshots. Der Planner lädt die Markttiefe bei jeder Berechnung bewusst neu, damit die Tiefe exakt ist. Der geplante Kaufort-Hinweis im Planner soll vorhandene Analyse-Snapshots wiederverwenden. |

Codeprüfung P0 (20.10.2026, nur gelesen): Alle 19 Einträge der Statusspalte
stimmen mit dem Quellcode überein; es gab keine Korrektur. Hinweis für P2: Das
Dashboard hat bereits eine Karte „Automatic data“
(`dashboard.automatic-data-status` in `ContentView.swift`) mit Zeilen für
Verträge und Main-Hub-Markt. P2 sollte diese Karte erweitern statt eine zweite
anzulegen.

## B. Checkliste

Fertig

- [x] Charakter-Sync: Lager, Blueprints, Jobs, Wallet, Orders, Corporation-Bestände
- [x] Reaktionen, Mond- und Mineralien-Kaufanalyse inkl. Kaufort-Empfehlung
- [x] Dashboard-Update (Jobs, Finanzen, Marktkarten, Ticker)
- [x] Öffentlicher Vertragsindex (fortsetzbar)
- [x] Main-Hub-Chancen mit ROI, Gewinn, Tagesbedarf, Favoriten und Übergabe an den Planner
- [x] Planner mit BPC-/BPO-Bestand, BPC-/BPO-Kosten, Main-Hub-Einkaufsliste und 9 Verkaufsszenarien

Ehemals teilweise

- [x] Zentraler, vollautomatischer Startablauf „ESI laden“ – P1 umgesetzt (20.10.2026); Ladestatus auf dem Dashboard – P2 umgesetzt (20.10.2026)
- [x] Zielmarkt im Planner ausdrücklich wählen und speichern – P10 umgesetzt (21.10.2026)
- [x] Kaufort für Mineralien und Mondmaterialien im Plan anzeigen (aus vorhandener Analyse), Multibuy je Kaufort – P12 umgesetzt (21.10.2026)
- [x] Itemwahl nach ROI und Bedarf auch für Home und Coalition – P4–P7 umgesetzt (20.10.2026)

Ehemals fehlend

- [x] Hub-Chancen-Kern je Hub-Rolle parametrisierbar – P3 umgesetzt (20.10.2026)
- [x] Home Hub: Markt-Snapshot, Bedarfsledger und Chancenansicht – P4 und P5 umgesetzt (20.10.2026)
- [x] Coalition Hub: Structure-Markt-Snapshot, Bedarfsledger und Chancenansicht – P6 und P7 umgesetzt (20.10.2026)
- [x] Vertragspreise als zusätzliche Erlösquelle in den Hub-Chancen – P8 umgesetzt (21.10.2026)
- [x] Dashboard-Kacheln „Top-Chancen je Hub“ mit Sprung zu Chancen und Planner – P9 umgesetzt (21.10.2026)
- [x] Allianzmarkt als manuelles Verkaufsziel – P11 umgesetzt (21.10.2026)

Abschluss

- [x] Dokumentation, Acceptance, Handoffs und Owner-Testleitfaden – P13 (21.10.2026)
- [ ] Live-Prüfung (echte Charaktere, Structure-Märkte, DOTLAN, vollständiger Vertragsindex)
- [ ] Visuelle und fachliche Eigentümerabnahme nach Abschnitt E

## C. Plan: Reihenfolge und Abhängigkeiten

```
P0 Verifikation ──► P1 Startablauf ──► P2 Dashboard-Ladestatus
                └─► P3 Chancen-Kern generisch ──► P4 Home-Snapshot/Ledger ──► P5 Home-Chancen-Ansicht
                                              └─► P6 Coalition-Snapshot/Ledger ──► P7 Coalition-Chancen-Ansicht
                                                        P5 + P7 ──► P8 Verträge in Chancen ──► P9 Dashboard-Chancen-Kacheln
P10 Zielmarkt im Planner ──► P11 Allianzmarkt manuell
P12 Kaufort-Hinweis Mineralien/Mond im Planner
P13 Abschluss: Doku, Acceptance, Owner-Test
```

Für jeden Schritt gilt:

- kleiner Diff mit eigenen Tests,
- Prüfung mit SwiftPM und Xcode-Debug,
- PRODUCT.md und dev-diary.md im selben Schritt aktualisieren,
- danach stoppen und berichten.

Commits gibt es nur auf ausdrücklichen Auftrag.

Feste Reihenfolge, jeder Prompt endet mit „→ Nächster Prompt“:

P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → P9 → P10 → P11 → P12 → P13 → Ende.
Nach P13 folgt kein weiterer Prompt, nur ein Abschlussbericht mit den offenen
Owner-Abnahmen.

## D. Prompts (einzeln kopierbar)

### Gemeinsamer Vorspann (jedem Prompt voranstellen)

> Arbeite nach AGENTS.md/CLAUDE.md. Lies vorher `git status --short --branch` und den
> vorhandenen Diff; fremde Änderungen bleiben erhalten. Ändere bestehende
> Rechenregeln nur, wenn der Prompt es ausdrücklich sagt. Fehlende Daten bleiben
> ausdrücklich unverfügbar und werden nie zu 0. Zeige EVE-Namen über
> `EVEEntityText`/`EVEItemText` an und mache Tabellen über den gemeinsamen Header
> sortierbar. Pflege PRODUCT.md und dev-diary.md im selben Schritt. Prüfe mit
> `swift test` und einem Xcode-Debug-Build. Danach stoppen und berichten; geplant,
> implementiert und getestet dabei getrennt ausweisen. Kein Commit.
> **Gib am Ende des Berichts immer den nächsten Prompt laut Reihenfolge in
> `Documentation/HUB_CHANCEN_PLAN.md` vollständig und kopierfertig aus,
> einschließlich dieses Vorspanns.** Hake den erledigten Punkt in der Checkliste
> (Abschnitt B) ab. Ist ein Schritt blockiert, nenne den Blocker und gib trotzdem
> den nächsten ausführbaren Prompt vor.

### P0 – Verifikation (nur lesen)

> Prüfe Abschnitt A von `Documentation/HUB_CHANCEN_PLAN.md` gegen den Code. Nenne
> für jede Zeile die maßgeblichen Typen und Dateien:
>
> - Startpfad in `RuntimeState` und im App-Einstieg
> - Dashboard-Sync
> - Main-Hub-Scan und Bedarfsledger
> - `SharedAnalysisRefresh` und `MaterialPurchaseRecommendationProjector`
> - Market-Settings-Rollen
> - Planner-Verkaufsszenarien
>
> Korrigiere im Plan nur die Statusspalte, wo der Code abweicht. Keine Codeänderung.

→ Nächster Prompt: P1

### P1 – Zentraler Startablauf „ESI laden“

> Führe einen zentralen Startablauf ein. Nach erfolgreichem Öffnen des Stores
> soll er automatisch:
>
> 1. alle verbundenen Charaktere synchronisieren. Bisher geschieht das erst beim
>    ersten Dashboard-Aufruf; der Dashboard-Einmal-Sync nutzt dann den laufenden
>    oder fertigen Start-Sync statt eines zweiten.
> 2. danach parallel Reaktionen, Mond- und Mineralien-Analyse über
>    `SharedAnalysisRefresh` anstoßen.
> 3. den Main-Hub-Chancen-Scan starten.
> 4. den Public-Contracts-Import fortsetzen oder starten.
>
> Eigentümerentscheid vom 20.10.2026: Alles läuft immer automatisch. Die
> bisherigen Opt-ins für den Main-Hub-Auto-Scan und die Vertragsfortsetzung
> entfallen; begründe das in `Documentation/Consolidation/DECISIONS.md`.
>
> Beibehalten werden:
>
> - die Transportgrenze (max. 6 Anfragen, davon max. 2 automatisch),
> - der Planner-Vorrang mit kooperativem Abbruch,
> - die 6-Stunden- und 5-Minuten-Wiederverwendung,
> - der Recovery-Modus, der nichts startet.
>
> Schreibe Tests für Reihenfolge, Deduplizierung und Abbruch.

→ Nächster Prompt: P2

### P2 – Ladestatus auf dem Dashboard

> Zeige auf dem Dashboard eine kompakte Statuszeile des Startablaufs. Bereiche:
> Charaktere, Lager/Blueprints, Reaktionen, Mond, Mineralien, Main-Hub-Chancen und
> Verträge. Je Bereich erscheinen der Zustand (fresh, partial, stale, forbidden,
> unavailable oder läuft) und der Zeitpunkt. Nur vorhandene Runtime-Zustände
> darstellen, keine neue Netzwerklogik.

→ Nächster Prompt: P3

### P3 – Chancen-Kern je Hub-Rolle parametrisieren (Refactor ohne Verhaltensänderung)

> Mache Main-Hub-Opportunity-Scan, Kostenprojektion, Bedarfsledger und
> Snapshot-Speicherung über eine Hub-Rolle (main/home/coalition) und eine exakte
> Location parametrisierbar.
>
> Der Main Hub bleibt bitgenau gleich: vorhandene Snapshot- und Ledger-Dateien,
> Schlüssel und Migrationen ändern sich nicht. Neue Rollen bekommen eigene
> Dateien.
>
> Route je Rolle:
>
> - **Main:** Kauf am Main Hub → Produktion → Rücktransport zum Main Hub.
> - **Home:** Kauf am Main Hub → Produktion, kein Rücktransport (wie im Planner).
> - **Coalition:** wie Home, zusätzlich Route Home → Coalition (Kurier oder
>   Sprunglogistik wie im Planner).
>
> Gebühren kommen aus dem Händlerprofil des jeweiligen Hubs. Umfang: nur Kern und
> Tests, noch keine neue UI. Golden-Tests belegen, dass die Main-Hub-Ergebnisse
> unverändert bleiben.

→ Nächster Prompt: P4

### P4 – Home-Hub-Markt-Snapshot und Bedarf

> Lade für den konfigurierten Home Hub einen katalogweiten Order-Snapshot:
>
> - **NPC-Station:** regionale Orders, gefiltert auf die exakte Station.
> - **Player Structure:** `/markets/structures/{id}/` mit Charakter-Lease
>   (`esi-markets.structure_markets.v1`, wie bei Mond und Mineral).
>
> Führe ein eigenes Bedarfsledger für die exakte Home-Location. Ist Home = Main,
> keinen zweiten Scan starten, sondern die Main-Daten wiederverwenden. Fehlender
> Scope oder ACL bleibt sichtbar unverfügbar. Hänge den Snapshot in den
> P1-Startablauf ein.

→ Nächster Prompt: P5

### P5 – Ansicht „Home-Hub-Chancen“

> Füge den Navigationseintrag „Home-Hub-Chancen“ hinzu. Er verwendet die
> Main-Hub-Chancen-Oberfläche mit der Rolle home wieder: Filter, Spalten,
> Runs/ME/TE und Favoriten. Persistierte Filter werden je Hub getrennt gespeichert.
>
> **Bauen** übergibt wie bisher an den Planner und zusätzlich den Zielmarkt
> „Home Hub“; der Planner nutzt ihn ab P10. Ist kein Home Hub konfiguriert, zeigt
> die Ansicht einen erklärenden Leerzustand mit Link zu den Markteinstellungen.

→ Nächster Prompt: P6

### P6 – Coalition-Hub-Markt-Snapshot und Bedarf

> Wie P4, aber für den Coalition Hub (immer eine Player Structure). Zusätzlich die
> Kosten der Route Home → Coalition aus der vorhandenen Logistik- bzw.
> Sprunglogistik-Konfiguration. Fehlt die Route oder ein Pilot, bleibt der Gewinn
> unverfügbar. Capitals sind am Coalition Hub erlaubt. Hänge den Snapshot in den
> Startablauf ein.

→ Nächster Prompt: P7

### P7 – Ansicht „Coalition-Hub-Chancen“

> Wie P5, aber mit der Rolle coalition. Zusätzliche Spalte: Transportkosten
> Home → Coalition.

→ Nächster Prompt: P8

### P8 – Öffentliche Verträge als Erlösquelle in den Hub-Chancen

> Ergänze in allen drei Chancenansichten eine sortierbare Spalte „Vertragspreis“:
> der niedrigste passende Einzel-Item-Exchange-Vertrag, nach derselben
> Passungsregel wie beim Planner-Vertragshandel. Dazu Gewinn und ROI beim Verkauf
> über Vertrag, mit dem bestätigten Vertragsgebührensatz.
>
> Ist der Index unvollständig, wird der Wert als „vorläufig“ markiert. Gibt es kein
> Angebot, bleibt er unverfügbar. Nur den lokalen Index abfragen, keinen ESI-Abruf.

→ Nächster Prompt: P9

### P9 – Dashboard-Kacheln „Top-Chancen“

> Am 26.10.2026 auf Eigentümerauftrag samt Code, Speicher und Tests wieder
> entfernt; der folgende Abschnitt ist nur noch Historie.

> Füge eine Dashboard-Karte mit den Top 5 je Hub (Main/Home/Coalition) hinzu,
> sortiert nach täglichem Gewinnpotenzial aus den gespeicherten Snapshots. Ein
> Klick öffnet die jeweilige Chancenansicht, **Bauen** öffnet den Planner. Keine
> neue Berechnung, nur vorhandene Snapshots.

→ Nächster Prompt: P10

### P10 – Zielmarkt im Planner wählen und speichern

> Im Planner wird ein Zielmarkt ausdrücklich gewählt: Main, Home oder Coalition,
> ab P11 auch Allianzmarkt. Vorgeschlagen wird das Szenario mit dem höchsten
> verfügbaren Gewinn; der Vorschlag ist übersteuerbar.
>
> Das gewählte Szenario wird hervorgehoben und im Plan-Snapshot sowie in der
> Produktionsübersicht gespeichert. Die neuen Felder sind additiv und versioniert;
> alte Snapshots bleiben ohne Zielmarkt lesbar. Eine Übergabe aus P5 oder P7 setzt
> den Zielmarkt vor.

→ Nächster Prompt: P11

### P11 – Allianzmarkt als manuelles Verkaufsziel

> Füge ein zehntes Verkaufsszenario „Allianzmarkt (manuell)“ hinzu:
>
> - Stückpreis und optional die Abnahmemenge werden im Planner eingegeben.
> - Optional ein Lieferort aus den vorhandenen Hubs; der Transport folgt der
>   bestehenden Logistikregel.
> - Gebühren sind 0 %, sofern nichts eingetragen ist, und werden ausdrücklich als
>   manuelle Annahme gekennzeichnet.
> - Ohne Preis bleibt das Szenario unverfügbar.
>
> Das Szenario wird im Snapshot und in der Produktionsübersicht gespeichert.
> Optional gibt es einen kopierbaren Angebotstext für Slack (Item, Menge, Preis)
> über einen `EVEEntityText`-konformen Kopierknopf.

→ Nächster Prompt: P12

### P12 – Kaufort-Hinweis für Mineralien und Mondmaterialien im Planner

> Zeige in der Planner-Einkaufsliste für Mineralien und Mondmaterialien:
>
> - den günstigsten konfigurierten Kaufort aus der vorhandenen Analyse
>   (`MaterialPurchaseRecommendationProjector`, bereits geladener Snapshot, Alter
>   sichtbar),
> - die Preisdifferenz zum Main Hub,
> - Multibuy je Kaufort.
>
> Die Kostenrechnung bleibt nach der bestehenden Regel Main-Hub-basiert; der
> Hinweis ist nur eine Entscheidungshilfe. Kein zusätzlicher ESI-Abruf. Fehlt die
> Analyse, erscheint der Hinweis „Analyse nicht geladen“.

→ Nächster Prompt: P13

### P13 – Abschluss

> Gleiche PRODUCT.md, ARCHITECTURE.md (Hub-Rollen-Chancen, Startablauf),
> `Documentation/ACCEPTANCE.md` und dev-diary.md ab. Setze die Checkliste in
> `Documentation/HUB_CHANCEN_PLAN.md` auf erledigt und weise offene Live- und
> Owner-Abnahmen getrennt aus. Schreibe einen kurzen Owner-Testleitfaden: Start →
> Dashboard → Hub-Chancen → Bauen → Zielmarkt → Kaufort → Produktion erfassen.

→ Ende (kein weiterer Prompt; Abschlussbericht mit offenen Owner-Abnahmen)

## E. Owner-Testleitfaden

Voraussetzung: In **Daten & Einstellungen → Markteinstellungen** sind Main, Home
und Coalition Hub mit Händlern gewählt, möglichst mit bestätigtem
Vertragsgebührensatz. Mindestens ein Charakter hat den Scope
`esi-markets.structure_markets.v1`. Die Logistik ist konfiguriert, für
Coalition optional mit Sprunglogistik.

1. **Start:** App starten und nichts anklicken. Auf dem Dashboard läuft in
   **Automatic data → Programmstart** zuerst „Charaktere“ und „Lager & Baupläne“,
   danach Reaktionen, Mondmaterialien und Mineralien. Anschließend erscheinen
   die Zeilen Verträge, Main-, Home- und Coalition-Hub-Markt mit Status bzw.
   „Nächster Lauf“. Erwartung: kein zweiter Charakter-Sync beim Öffnen des
   Dashboards.
2. **Top-Chancen:** Nach einem Hub-Scan zeigt die Karte **Top-Chancen** je Hub
   bis zu fünf Produkte mit „/ Tag“ und ROI. Ein Klick auf den Hub-Titel öffnet
   die Chancenliste.
3. **Main-, Home- und Coalition-Hub-Chancen:**
   - Jede Ansicht hat eigene Filter. Ein Suchtext in Home erscheint nicht in
     Main.
   - Home zeigt keinen Rückweg zum Main Hub.
   - Coalition zeigt die Spalte **Home → Coalition**; ein unbekannter Wert hat
     einen Grund in den Zeilendetails.
   - **Vertragspreis** und **Vertragsgewinn** sind sortierbar. „≈“ steht für
     vorläufig, „—“ für kein Angebot.
4. **Bauen:** In einer Hub-Ansicht oder auf dem Dashboard **Bauen** drücken. Der
   Planner übernimmt Charge, ME/TE und den Zielmarkt des Hubs.
5. **Zielmarkt:** Berechnen. Der Vorschlag nennt den Hub mit dem höchsten
   endgültigen Gewinn, die Karten des gewählten Hubs sind umrandet. Eine Wahl
   ändern und den Planner neu öffnen: Die Wahl bleibt erhalten.
6. **Allianzmarkt:** Einen Preis, eine Abnahmemenge kleiner als die Ausgabe und
   einen Lieferort eintragen, dann übernehmen.
   - Der Gewinn enthält die vollen Produktionskosten, ein Hinweis nennt die
     unverkauften Einheiten.
   - Den Slack-Text kopieren und in einem Editor prüfen.
   - Ohne Preis ist das Szenario unverfügbar.
7. **Kaufort-Hinweis:** Die EVE-Einkaufsliste aufklappen.
   - Für Mineralien und Mondmaterialien stehen Kaufort, Preis, Main-Hub-Preis
     und Differenz.
   - „Multibuy kopieren · Ort“ ins EVE-Multibuy-Fenster einfügen.
   - Plankosten und Main-Hub-Multibuy bleiben unverändert.
8. **Produktion erfassen:** In der Produktionsübersicht steht der Zielmarkt in
   der Spalte **Ziel**. Ältere Einträge zeigen „Nicht gewählt“.

Gefundene Abweichungen bitte mit Schrittnummer melden.
