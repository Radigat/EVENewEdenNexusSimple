# EVE New Eden Nexus - Assets, Industry, Markets – Arbeitsstand

Es gibt nur einen aktiven Projektstand. Legacy-Projekte dienen ausschließlich
als Quelle für die Konsolidierung. Modellvorgaben: [MODEL_POLICY.md](MODEL_POLICY.md).

## Abgeschlossen: Konsolidierung

Die ausdrücklich beauftragte fachliche Zusammenführung ist umgesetzt. Ihr Umfang,
bewusste Ausschlüsse und Nachweise stehen im [Funktionsvertrag](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md)
und im [Prüfbericht](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md).

## Aktuell: Weiterentwicklung (seit 19.10.2026)

Neue Funktionen, Fehlerkorrekturen und Verbesserungen sind freigegeben und werden
auf ausdrücklichen Benutzerauftrag umgesetzt. Es gibt keine automatisch
anschließende Entwicklung und keine ungefragten Folgefeatures.

Historische Roadmaps, Projektbuch, P00–P61 und nur spezifizierte Vorhaben bleiben
unveränderte Quellen im Archiv. Sie können als Ideenquelle dienen, werden aber
erst durch einen ausdrücklichen Auftrag zu aktiver Arbeit. Live-/Eigentümerabnahmen
sind weiterhin separat auszuweisen.

## Geplant

Noch keine weiteren Vorhaben festgelegt.

## Umgesetzt, Abnahme offen

- [Marktbestand-Plan](Documentation/MARKTBESTAND_PLAN.md) (29.10.2026, P1–P8
  implementiert und automatisch geprüft):
  - Bestandshistorie je Item für Main, Home und Coalition Hub aus den
    vorhandenen Hub-Scans (Zugang, Teilverkauf, verschwundene Orders,
    Netto).
  - Feste Termine 06:00/13:00; kein Hub-Scan vor ESI-`Expires`.
  - Hintergrundbetrieb mit Menüleiste und Login-Start.
  - Eigene SQLite-Datei: 7 Tage Einzelpunkte, 90 Tage Tageswerte.
  - Handel-Spalten aus der Historie, Item-Graph und Ansicht „Marktbestand“.
  - Live- und Eigentümerabnahme offen (Leitfaden in Abschnitt I).

- [Lagerverkauf-Plan](Documentation/LAGERVERKAUF_PLAN.md) (25.10.2026,
  implementiert und automatisch geprüft): Lagerverkauf-Abgleich je Hub mit
  eingefügten Items (englische und deutsche Namen, Katalogadapter 7),
  Neuproduktionskosten aus der Hub-Chancen-Rechnung, Mindestpreisen für
  Sell-Order und Direktverkauf und Empfehlung. SDE-Neuimport, Live- und
  Eigentümerabnahme offen (Leitfaden in Abschnitt E).
- [Handel-Plan](Documentation/HANDEL_PLAN.md) (22.10.2026, implementiert und
  automatisch geprüft):
  - Bereich Handel mit SDE-Marktgruppen-Kacheln, Import Main→Home/Coalition
    sowie Home ↔ Coalition in beide Richtungen, Steuern, Logistik und
    Tagesbedarf.
  - Handelslogbuch mit Wallet-Abgleich.
  - Live- und Eigentümerabnahme offen (Checkliste in Abschnitt H).
- [Hub-Chancen-Plan](Documentation/HUB_CHANCEN_PLAN.md) (20./21.10.2026,
  implementiert und automatisch geprüft): zentraler Startablauf, Home- und
  Coalition-Hub-Chancen, Verträge in den Chancen, Top-Chancen (am 26.10.2026 entfernt), Zielmarkt und
  Allianzmarkt im Planner, Kaufort-Hinweis. Live- und Eigentümerabnahme offen.
