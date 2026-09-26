# EVE New Eden Nexus - Assets, Industry, Markets – Projektstatus

Stand: 25.09.2026. Standardmodell: **Astra Medium**.
Es gibt nur einen aktiven Projektstand: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.
Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Fachlicher Stand

Die organisatorische Basis `182f1a9` ist um die freigegebenen vorhandenen Fachabläufe ergänzt:
Fertigungsprojekte, manuelle Lager/CSV, dauerhafte Reservierungen, Preisprofile/Einkauf,
konkrete Wissenschaftsaufträge, Kosten-/Verkaufsbelege und lokale Sicherung/Wiederherstellung.
Die heutige Oberfläche und aktuelle Berechnungen bleiben Grundlage. V3 ergänzt die Datenhaltung;
bestehende Modelle, Nummern, historische Werte und technische Kennungen werden erhalten.
Preisprofile sind in die Markteinstellungen, Sicherung/Wiederherstellung in die allgemeinen
Einstellungen integriert; der frühere gemeinsame Toolbar-Einstieg und seine beiden Bereiche in
der Projektverwaltung sind entfernt.

Maßgeblich: [Funktionsvertrag](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md),
[Feature-Zuordnung](Documentation/Consolidation/FEATURE_COVERAGE.md) und
[aktuelle Verifikation](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md).

## Grenzen

- Keine Migration alter Nexus-Datenbanken; vorhandene aktuelle Nutzerdaten werden additiv migriert.
- Zurückgezogene Finanzansichten und nur geplante Vorhaben bleiben ausgeschlossen.
- Tests verwenden ausschließlich synthetische Bestände. Reale SDE-/ESI-/SSO-Abnahme und
  vollständige Eigentümer-/VoiceOver-Abnahme werden nicht behauptet.
- Die bereits installierte Alt-App und die ChatGPT-Projektanzeige sind separate Oberflächen.
  Dieser Auftrag ersetzt keine produktive Installation und ändert keine globalen Modelleinstellungen.
- Der historisch genannte Production-Tracker-Ordner liegt weiterhin nicht als eigener Quellstand vor.

Nach lokalem Git-Checkpoint und Abschlussbericht endet der Auftrag. Keine neue Funktionsplanung.
