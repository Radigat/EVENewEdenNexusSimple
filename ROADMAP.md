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

Prompts liegen fertig vor; umgesetzt wird nur auf ausdrücklichen Auftrag
(Stand 08.11.2026).

- Restliche Prompt-Reihe der [App-Analyse](Documentation/ANALYSE_2026-11-02.md),
  Abschnitte 7 und 8:
  - A6b: Beim Strukturmarkt weitere Charaktere nur nach 403 oder fehlendem
    Zugriff probieren, bei vorübergehenden Fehlern die echte Ursache zeigen.
  - A7: Aufräumen und Konsistenz (P-L7, P-L8); vorher Eigentümerfragen zu
    H-L1 und P-L5. Der Teilpunkt `MarketBrowserView` ist seit 07.11.2026
    erledigt.
  - A8: große Umbauten G12 und G13, nur wenn Messwerte sie rechtfertigen.
  - Zurückgestellt: A5 (G5, G11) und G9.
- D9 im [HUD-Plan](Documentation/DESIGN_HUD_2026-11-07.md): nur für Befunde
  aus der Eigentümerabnahme.

Offene Eigentümerentscheidungen und Befunde ohne Auftrag stehen gesammelt in
[PROJECT_STATE.md](PROJECT_STATE.md), Abschnitt „Offene Punkte“.

## Vom Eigentümer abgenommen

- [Dashboard nach Board](Documentation/DASHBOARD_BOARD_2026-11-07.md)
  (07./08.11.2026, DB1–DB8): Seitenkopf mit ESI-Status und „Alles
  aktualisieren“, Kennzahlenreihe, Nettowert-Zeitraum, Main-Hub-Chancen ·
  Top 5, Nacharbeiten B1–B10 und Kacheltitel. Am 08.11.2026 insgesamt als
  „i. O.“ abgenommen, ohne Einzelmarkierungen; für die nur mit echten Daten
  prüfbaren Punkte (Abschnitt 7.2) liegen keine Ergebnisse je Punkt vor.
- Statische Daten lokal und dauerhafter ESI-Antwortcache (23.10.2026), siehe
  [PROJECT_STATE.md](PROJECT_STATE.md).

## Umgesetzt, Abnahme offen

- [Oberflächenstil „New Eden HUD“](Documentation/DESIGN_HUD_2026-11-07.md)
  (07.11.2026, D1–D8 implementiert und automatisch geprüft): Umschalter,
  gemeinsame Bausteine, Seitenleiste in Gruppen, HUD-Fassung aller Bereiche.
  Eigentümerabnahme mit echten Daten offen (Checkliste in Abschnitt 7).
- [App-Analyse](Documentation/ANALYSE_2026-11-02.md), Prompts A1–A6
  (02.–05.11.2026, implementiert, automatisch geprüft, vom Eigentümer live
  gemessen): Messpunkte und Golden-Master, Planer-Pipeline mit Datensitzung,
  Zeilen-Cache im Handel, ESI-Parallelität zwölf, Home und Coalition
  gleichzeitig. Offen: Sichtprüfung von A4, Messung von A6 bei normaler
  ESI-Lage, Eigentümerabnahme.
- Planer-Ausbau (30.10.–07.11.2026, implementiert und automatisch geprüft;
  Nachweise in [dev-diary.md](dev-diary.md) und
  [ACCEPTANCE.md](Documentation/ACCEPTANCE.md)): feste Blueprint-Quelle,
  Einkaufsorte samt Vergleichsmärkten, Automatik, Schrittplaner mit
  Rentabilität, Lagerbewertung, Reaktionsformeln, Jobdauer mit Skills und
  Implantaten, Charaktere je Standort und Tätigkeit, ohne Umschalter
  Einzel-/Sammelproduktion. Jobkosten live gegen das EVE-Jobfenster
  abgeglichen (Abweichung 0,0343 %). Eigentümerabnahme mit echten Plänen
  (Ark, Nomad, Rhea) offen.
- Einzelkorrekturen vom 07./08.11.2026 (implementiert und automatisch geprüft):
  Market Browser entfernt, Hinweis in Öffentlichen Verträgen, Vertragssuche
  nach Preis und Region, Item-Verlauf mit Mouse-over, Schriftgröße in der
  ganzen App, übersetzte Eingabefehler im Planer. Sichtprüfung mit echten
  Daten und Eigentümerabnahme offen.
- Nachträge vom 24.–30.10.2026 zu Handel, Hub-Chancen, Planner und
  Lagerverkauf (implementiert und automatisch geprüft; Übersicht in
  [PROJECT_STATE.md](PROJECT_STATE.md)). Sichtprüfung und Eigentümerabnahme
  offen.
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
