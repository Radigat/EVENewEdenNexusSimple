# Plan: Lagerverkauf-Abgleich

Stand: 25.10.2026 · Status: **implementiert, automatisch geprüft**. Live-Prüfung
und Eigentümerabnahme sind offen, siehe Abschnitt E.

Der Eigentümer möchte vorrätige oder schon produzierte Items bewerten: Lohnt es
sich, sie am gewählten Hub zu verkaufen, verglichen mit einer Neuproduktion? Je
Item zeigt die App den Mindestpreis, ab dem der Verkauf Gewinn gegenüber der
Neuproduktion bringt. Die Neuproduktion enthält Material, Installation,
Blueprint-Anteil und Logistik; der Verkauf enthält die Marktgebühren.

## A. Entscheidungen des Eigentümers (25.10.2026)

| Thema | Entscheidung |
|---|---|
| Kostenbasis | Hub-Chancen-Rechnung des gewählten Hubs, umgerechnet auf die Menge und auf ME/TE |
| Itemquelle | Items samt Anzahl im Spiel kopieren und einfügen; englische und deutsche Namen |
| Preisregel | Gewinnschwelle; kein Margenaufschlag |
| Verkaufsarten | eigene Sell-Order und Direktverkauf an eine Buy-Order, beide gezeigt |
| Orderpreis | ein zulässiger Preisschritt unter dem besten Sell |
| Markttiefe | Rechnung zum besten Buy-Preis, daneben die Tiefe; zu geringe Tiefe macht den Gesamtgewinn zur Obergrenze in Warnfarbe |
| Platzierung | eigener Seitenleisten-Eintrag direkt unter dem Handelslogbuch, Hub-Auswahl in der Ansicht |
| Annahmen | dieselben Schalter und ME/TE-Standards wie die Hub-Chancen; ME/TE je Zeile änderbar |
| Speicherung | Liste bleibt gespeichert, bis sie geleert wird; „Ersetzen“ oder „Ergänzen“ beim Einfügen |
| Spalten | alle Spalten immer sichtbar, horizontal scrollbar |
| Name | englischer SDE-Name, kopierbar; Hinweis mit Originaltext bei abweichendem eingefügtem Namen |
| Hervorhebung | Marktpreis grün ab Mindestpreis, sonst rot; Spalte „Empfehlung“ |
| Sortierung | beim Öffnen Gewinn gesamt (Empfehlung) absteigend; unbekannte Werte in beiden Richtungen am Ende |
| Gleichstand | Direktverkauf wird empfohlen |

## B. Einfügen und Namen

- Zeile mit Tab (Inventarliste): Spalte 1 Name, Spalte 2 Menge; leere Menge = 1.
- Zeile ohne Tab: zuerst die ganze Zeile als Name, sonst `Name x Menge`,
  `Name xMenge` oder `Name Menge`.
- Mengen dürfen die Tausendertrenner `.`, `,`, Leerzeichen, NBSP und
  Apostroph enthalten; erlaubt sind 1 bis 1.000.000.000. Höchstens 1 MiB und
  1.000 Zeilen.
- Namensauflösung: exakter englischer SDE-Name (ohne Groß-/Kleinschreibung,
  nur veröffentlichte Typen), danach der deutsche Name. Mehrere Treffer gelten
  als mehrdeutig.
- Deutsche Namen liegen ab Katalogadapter 7 in `item_type_localized_names`.
  Ein älterer Katalog bleibt nutzbar; deutsche Zeilen melden dann „deutsche
  Namen erst nach SDE-Neuimport“.
- Gleiche Typen werden summiert. Nicht erkannte Zeilen bleiben mit Grund
  sichtbar und erhalten nie einen Wert.

## C. Fachregeln

Für die gewählte Hub-Rolle H, das Item i und die Menge n
(`StockSaleComparison.swift`, Regelversion `stock-sale-2026-10-25`):

- **Scan-Zeile:** aus dem Hub-Chancen-Snapshot der Datenrolle von H
  (`tradeDataRole`); ein Hub am selben Ort wie Main bzw. Home nutzt dessen Scan.
- **Läufe:** `runs = ⌈n ÷ outputPerRun⌉`, `produced = runs × outputPerRun`.
- **ME/TE:** eigene Zeilenwahl, sonst `ManufacturingOpportunityEfficiencyDefaults`.
  Reaktionen haben kein ME/TE.
- **Kostenkette** wie in den Hub-Chancen: Eigenbau der Zwischenprodukte nach
  Schalter, Umrechnung auf Läufe und ME/TE, Beschaffung mit **leerem Lager**
  (vollständige Wiederbeschaffung am Main Hub), Logistik der Verkaufsroute von H,
  Kosten mit Kostenblatt und Vertragskontext.
- **K** = Material + Installation + Blueprint-Anteil bzw. -Erwerb + Logistik bis H;
  **k = K ÷ produced**.
- **Gebühren:** Verkaufssteuer t und Maklergebühr b aus den Markteinstellungen
  von H.
- **Mindestpreis Sell-Order** = k ÷ (1 − t − b); **Mindestpreis Direktverkauf**
  = k ÷ (1 − t).
- **Eigene Order** = ein Preisschritt unter dem besten Sell
  (`MarketPriceTick.nextBelow`).
- **Gewinn je Stück:** Sell-Order = Orderpreis × (1 − t − b) − k;
  Direktverkauf = bester Buy × (1 − t) − k. **Gesamt** = je Stück × n.
- **Tiefe:** Ist die Stückzahl zum besten Buy kleiner als n, ist der
  Direkt-Gesamtgewinn eine Obergrenze (Warnfarbe).
- **Empfehlung:** höherer bekannter Gesamtgewinn > 0; Gleichstand →
  Direktverkauf; alle bekannten ≤ 0 → „Behalten“; nichts bewertbar → „—“.
  Die Spalte sortiert nach dem Gesamtgewinn der empfohlenen Art.
- **Transport der Lagerware** wird nicht gesondert angesetzt: Die Neuproduktion
  enthält bereits die Lieferung bis H.
- **Fehlende Daten** bleiben unbekannt („—“ mit Grund), nie 0. Ohne Scan-Zeile
  gibt es Marktpreise, aber keine Kosten, Mindestpreise und Gewinne.
- **Nicht enthalten:** Relist- und Orderänderungsgebühren.
- Die Rechnung nutzt die gewichteten Main-Hub-Stückpreise des Scans; sie lädt
  keine neue Markttiefe.

## D. Checkliste

| Schritt | Stand |
|---|---|
| P1 Deutsche SDE-Namen, Katalogadapter 7 | implementiert, automatisch geprüft |
| P2 Core: Parser, Liste, Kostenprojektor, Rechner, Sortierer | implementiert, automatisch geprüft |
| P3 Ansicht, Seitenleiste, Speicherung, Lokalisierung, Xcode-Projekt | implementiert, automatisch geprüft (Build und Navigationstest) |
| P4 Dokumentation | erledigt |
| Live-Prüfung und Eigentümerabnahme | offen |

## E. Owner-Testleitfaden

1. Einmal **Daten & Einstellungen → SDE → Neuimport des aktuellen Katalogs**
   (etwa 5 Minuten), danach App neu starten. Erst dann gibt es deutsche Namen.
2. **Hub-Märkte aktualisieren** oder den automatischen Hub-Scan abwarten.
3. Im EVE-Client (englisch) Items in der Inventar-Listenansicht markieren,
   Cmd+C, im Lagerverkauf-Abgleich einfügen, „Liste ersetzen“.
4. Dasselbe mit deutschem Client und „Zur Liste hinzufügen“: Mengen gleicher
   Items werden summiert, der Hinweis nennt den deutschen Originalnamen.
5. Hub wechseln (Main, Home, Coalition) und prüfen, dass Gebühren-Chip,
   Logistik/Stück und Mindestpreise sich ändern.
6. Ein Item mit den Hub-Chancen vergleichen (gleiche Läufe und ME/TE): Kosten
   je Stück sollen übereinstimmen, abgesehen von der Logistik, die hier ohne
   Lageranrechnung gerechnet wird.
7. Mindestpreis Sell-Order gegen die Kachel „Kosten pro Item“ eines gleich
   großen Planner-Laufs halten; Abweichungen durch eigene Blueprints oder
   Planner-Logistik notieren.
8. ME/TE einer Zeile ändern, Zeile entfernen, App neu starten: Liste und
   Werte bleiben erhalten. „Liste leeren“ fragt nach.
