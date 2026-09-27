# Kanonischer Komponentenvergleich

Projekt: EVE New Eden Nexus - Assets, Industry, Markets. Standardmodell: Astra Medium.

Der organisatorische Ausgangsstand ist in Git-Checkpoint `182f1a9` erhalten. Die anschließende,
ausdrücklich autorisierte fachliche Integration ist in [FUNCTIONAL_CONSOLIDATION.md](FUNCTIONAL_CONSOLIDATION.md)
beschrieben; jede Legacy-Feature-ID ist in [FEATURE_COVERAGE.md](FEATURE_COVERAGE.md) zugeordnet.

| Bereich | Aktive kanonische Quelle | Zusammenführung |
| --- | --- | --- |
| App, Navigation, Profile | Bestehende SwiftUI-App | Projekte, Reservierungen und Einkauf im Planner; übrige Fachverwaltung am jeweiligen Arbeitsbereich; Preisprofile in Markt-, Sicherung in Allgemeine Einstellungen |
| Auth, SSO, ESI, Charaktere | Aktive Dienste | Keine zweite Anmeldung; vorhandene Wallet-Snapshots für Belege |
| SDE, Katalog und Updates | EVEStaticDataKit / SQLiteStaticCatalog | Veröffentlichte Typvalidierung und bestehende Science-Definitionen |
| Projekte, Lager, Reservierungen | ConsolidationWorkspace / ConsolidationController | Legacy-Fachverträge mit aktuellem Schutz-/Bestandsmodell |
| CSV und Geldbeträge | ConsolidationCSV / ConsolidationMoney | Direkte Portierung; Quellabhängigkeiten auf aktiven Kern umgestellt |
| Industrie, Reaktionen, Logistik | IndustryPlanner und vorhandene Rechner | Bestehende Regeln unverändert; konkrete Wissenschaftsvoraussetzungen ergänzt |
| Märkte, Public Contracts, Loyalty Store | Aktive Dienste | Unverändert; manuelle Profile sind ausdrücklich gewählte Budgeteingaben |
| Produktionsbuch | Bestehende Zeilen und Projektion | Kostenstand und bestätigte Verkaufszuordnungen verknüpft, keine zweite Historie |
| Persistenz | V1/V2 unverändert, additive V3 | Versionierter atomarer Arbeitsdatenverbund, keine Legacy-Store-Migration |
| Sicherung | ConsolidationBackup und App-Lebenszyklus | Online-Snapshots, Manifest, Prüfung und Start-Wiederherstellung |
| Tests | SwiftPM, natives Core-Testtarget, Kit | Bestehende Tests plus portierte CSV-Fälle, Fach- und Migrationstests |

Die alternative Architektur, nummerierte Xcode-Projekte und historische Roadmaps bleiben Quellen im Archiv.
