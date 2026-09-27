# Fachlicher Abdeckungsnachweis

Quelle: archivierte Feature-Matrix; Status gegen vorhandenen Quellcode und die ausdrücklich freigegebenen Konsolidierungsentscheidungen eingeordnet.

| Legacy-ID | Funktion | Kanonische Entscheidung |
| --- | --- | --- |
| TEC-001 | Native macOS-App mit Swift/SwiftUI | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-002 | Zentrale Sidebar, Dashboard, Suche | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-003 | Lokale SwiftData-Datenbank | Aktive SwiftData-Kette V1→V2→V3; additive Arbeitsdaten statt Import der Legacy-Schemas. |
| TEC-004 | Versionierte Migrationen | Aktive SwiftData-Kette V1→V2→V3; additive Arbeitsdaten statt Import der Legacy-Schemas. |
| TEC-005 | Zentrale Fehlerbehandlung | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-006 | Strukturiertes Logging | Aktuelle Diagnose-/Quellzustände beibehalten; redigierter Diagnoseexport ergänzt. Kein zweiter Logger. |
| TEC-007 | Automatisierte Tests | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-013 | Begrenzte Katalogsuche und gestaffelte Großgraphen-UI | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-014 | Adaptive, tastatur- und VoiceOver-vermittelbare Kernoberfläche | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-010 | Versionierte Referenzdaten und gemeinsame Testhelfer | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-008 | Lokale Backups und Restore | In Allgemeine Einstellungen integrierte, konsistente SQLite-Sicherung, geprüftes neues Datenfamilienformat und Wiederherstellung beim Start; SDE-Rollback bleibt bestehen. |
| TEC-009 | Domain, Application, Infrastructure und Persistence getrennt | Aktive Core/App-Schichtung beibehalten; Legacy-Schichten werden über Adapter zusammengeführt. |
| TEC-011 | Eigene Git-Wurzel mit reviewbarer Baseline | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| TEC-012 | Eigenständiges Xcode-Projekt und gemeinsame Schemes | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DST-001 | Lokale Eigennutzung auf dem Rechner des Projekteigentümers | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DST-002 | App Store oder direkte öffentliche macOS-Verteilung | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| DAT-000 | Offizielle JSONL-Dateien validieren und versioniert stagen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-001 | Itemtypen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-002 | Gruppen und Kategorien | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-003 | Blueprintdefinitionen/-materialien/-produkte | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-004 | Produktionszeiten und -aktivitäten | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-005 | Reaktionsrezepte | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-006 | Item- und Blueprintabfragen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-011 | Eindeutige Fertigungs- und Reaktionsrezepte aus aktiver SDE-Version auflösen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-007 | Offizielle Build-/Schema-Prüfung und HTTP-Caching | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-008 | Download, ZIP-Sicherheit, isolierter Import und Rollback | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-009 | Updateprotokoll, Einstellungen und Automatisierung | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| DAT-010 | Skill-, Dogma-, Meta- und weitere Daten bedarfsgesteuert ergänzen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CMP-001 | CCP-DLA, Drittanbieterkennzeichnung, Eigentumshinweis und Owner-Aufgaben | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| PRJ-001 | Zielprodukt und Menge erfassen | Im Planner integriert: stabile Fertigungsprojekte, eigene Entwürfe, Status und reversibles Archiv. |
| PRJ-002 | Projekt lokal speichern/listen | Im Planner integriert: stabile Fertigungsprojekte, eigene Entwürfe, Status und reversibles Archiv. |
| PRJ-003 | Projektstatus verwalten | Im Planner integriert: stabile Fertigungsprojekte, eigene Entwürfe, Status und reversibles Archiv. |
| PRJ-004 | Duplizieren und archivieren | Im Planner integriert: stabile Fertigungsprojekte, eigene Entwürfe, Status und reversibles Archiv. |
| CAL-001 | Produktionsgraph erzeugen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-002 | Runs und Ausgabemengen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-003 | Material Efficiency | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-004 | Mehrstufige T1-Ketten | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-005 | T2-Ketten | Aktuelle UI/Rechner bleiben Grundlage; konkrete Copying-, Forschungs- und Invention-Aufträge sind angebunden. |
| CAL-006 | Reaktionen als Stufen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-007 | Gleiche Materialien zusammenführen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| CAL-008 | Zyklen/fehlende Rezepte erkennen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| INV-001 | Lagerorte und manuelle Mengen | Übernommen: manuelle Lager, kontrollierter CSV-Import und projektbezogene Verfügbarkeit. |
| INV-002 | CSV-Bestandsimport | Übernommen: manuelle Lager, kontrollierter CSV-Import und projektbezogene Verfügbarkeit. |
| INV-003 | Verfügbarkeit und Ausschlüsse | Übernommen: manuelle Lager, kontrollierter CSV-Import und projektbezogene Verfügbarkeit. |
| SAF-001 | Mindest-, Ziel- und Warnbestand | Zusammengeführt: aktuelle Schutzformel und Zielmenge erhalten; unabhängige Warnschwellen ergänzt. |
| RES-001 | Materialien für Projekte reservieren | Bei der Planner-Lagerverwendung integriert: persistente Herkunftsreservierungen, Lebenszyklus, Prioritätsvorschau und Konflikte. |
| RES-002 | Konkurrenz und Schutzmengen erkennen | Bei der Planner-Lagerverwendung integriert: persistente Herkunftsreservierungen, Lebenszyklus, Prioritätsvorschau und Konflikte. |
| BOB-001 | Bestand verwenden und Zwischenstufen bauen/kaufen | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| PRC-001 | Manuelle Preise und Profile | In Markteinstellungen integriert: exakte manuelle Preisprofile, Gültigkeit und CSV-Vorschau; aktive Marktpreise bleiben Standard. |
| PRC-002 | CSV-Preisimport | In Markteinstellungen integriert: exakte manuelle Preisprofile, Gültigkeit und CSV-Vorschau; aktive Marktpreise bleiben Standard. |
| FIN-001 | Material-/Job-/Gesamtkosten | Zurückgezogene Legacy-Ansicht bleibt entfernt; bestehende aktuelle Rechnung/Wallet und erforderliche Belegdienste bleiben nutzbar. |
| FIN-002 | Erlös, Gewinn, Marge, ROI, Break-even | Zurückgezogene Legacy-Ansicht bleibt entfernt; bestehende aktuelle Rechnung/Wallet und erforderliche Belegdienste bleiben nutzbar. |
| FIN-003 | Materialeinkauf, Logistik, Produktion und benötigtes Projektbudget | Übernommen als ausdrückliches Einkaufsbudget mit ersetzenden Kostenangaben; aktuelle Gewinnlogik bleibt maßgeblich. |
| FIN-004 | Fortlaufende Jahresnummer, Charge, Produkt, Runs, ME/TE, optionaler Ort/Charakter und Output | Bestehendes Produktionsbuch ist kanonisch; laufende Nummern bleiben erhalten, keine konkurrierende Jahreszählung. |
| FIN-005 | Material, Job/Index, SCC/Facility, Blueprint, Logistik, Gebühren und Stückpreis | Vorhandene Kostenprojektion plus unveränderlicher Kosten-/Quellnachweis im selben Produktionsbuch. |
| FIN-006 | Verkaufsmengen, bestätigte Walletbelege, Durchschnittspreis und Realgewinn | Übernommen: bestätigte Teilverkäufe aus manuellen, Wallet- und Journalbelegen; aktuelle Gebühren-/Gewinnformeln erhalten. |
| FIN-007 | Produktions-/Verkaufsstatistik, Diagramme und Gesamtwallet | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| IND-001 | Mondzusammensetzung, Output, Fuel, Miete, Gewinn und Break-even | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| BUY-001 | Fehlmengen aggregieren | Bei der Planner-Einkaufsliste integriert: projektspezifische und aggregierte Einkaufspositionen, Zielabweichungen, Teilkäufe und Export. |
| BUY-002 | Bearbeiten, gekauft, CSV, Text | Bei der Planner-Einkaufsliste integriert: projektspezifische und aggregierte Einkaufspositionen, Zielabweichungen, Teilkäufe und Export. |
| UI-001 | Integrierter Produktions-/Inventionsworkspace mit Lager | Aktuelle UI/Rechner bleiben Grundlage; konkrete Copying-, Forschungs- und Invention-Aufträge sind angebunden. |
| SSO-001 | EVE SSO PKCE und Keychain | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| ESI-001 | Öffentliche Charakterdaten und persönliche Assets/Blueprints/Jobs | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| MKT-001 | Live-Marktpreise | Aktive Entsprechung beibehalten; bestehende Tests und Bedienung maßgeblich. |
| WAL-001 | Wallet, Transaktionen und historische Projektzuordnungen | Zurückgezogene Legacy-Ansicht bleibt entfernt; bestehende aktuelle Rechnung/Wallet und erforderliche Belegdienste bleiben nutzbar. |
| REA-001 | Vollständiges Reaktionsmanagement | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| PI-001 | PI, Logistik, Kalender, Kapazität | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| COR-001 | Corp-Daten, Rollen, gemeinsame Projekte | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| CLD-001 | Cloud und Mehrbenutzerbetrieb | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |
| OPT-001 | Solver, KI und Optimierungsengine | Kein zusätzlicher Legacy-Ausbau: nur geplant, zurückgestellt oder nicht freigegeben. Bereits vorhandene aktuelle Teilfunktionen bleiben erhalten. |

## Konkrete Quellen und aktive Prüfstellen

Die Zeilen der obigen Matrix stammen aus der archivierten `Documentation/FEATURE_MATRIX.md`.
Die fachlich übernommenen Verträge sind insbesondere in diesen vorhandenen Quellgruppen umgesetzt;
Quellpfade beziehen sich auf den unveränderten Legacy-Ordner, Zielpfade auf den aktiven Projektstamm.

| Herkunft im Legacy-Stand | Aktive Umsetzung | Prüfnachweis |
| --- | --- | --- |
| Application/ProductionProjectLifecycle.swift und ProductionProjectRepository.swift | ConsolidationWorkspace, ConsolidationPersistence, Projects-Formular | Projekt-/Duplikat-/Archivtests; synthetische Migration und unabhängige Entwürfe |
| Application/InventoryManagement.swift, InventoryAvailability.swift, InventoryCSVImport.swift | Workspace, Imports, Warehouse-/CSV-Formulare | Mengenlimits, Herkunft, Importatomarität und Invalidierung |
| Infrastructure/DelimitedInventoryCSVParser.swift | ConsolidationCSV.swift | Alle acht InventoryCSVParserTests adaptiert |
| Application/ProjectReservation.swift und ReservationConflict.swift | Workspace-Ledger und Konfliktvorschau | Mehrprojekt-, Prioritäts-, Teilverbrauchs- und Freigabetests |
| Domain/PriceProfile.swift, Application/PriceProfileManagement.swift | ConsolidationMoney, Imports und Preisprofilverwaltung | Exaktes Geld, Gültigkeit, fehlende Werte, Überlauf |
| Application/ProjectBudgetPlanning.swift, ProjectEconomics.swift, ShoppingListManagement.swift | Explizites Einkaufsbudget, Ersatzbeträge, Fortschritt, aggregierter Export | Budgetabgrenzung und Bestandsneutralität |
| Application/ProductionBatchCostManagement.swift und ProductionBatchSaleManagement.swift | Aktuelles Produktionsbuch plus Kosten-/Belegzuordnung | Teilverkauf, Doppelbeleg, Überverkauf und Cent-Restverteilung |
| Application/LocalBackupManagement.swift, Persistence/SQLiteLocalBackupService.swift | ConsolidationBackup und Allgemeine Einstellungen | WAL-Snapshot, Prüfsummen, fremdes Format und Wiederherstellung |
| Aktive Blueprints/BlueprintModels.swift und vorhandene SDE-/Research-Dienste | ConsolidationScience und Science-Formular | Bestehende Wahrscheinlichkeitsfälle, konkrete Versorgung und Zeitregression |

`ConsolidationTests.swift`, `ConsolidationCSVParserTests.swift` und
`ConsolidationPersistenceTests.swift` sind die aktiven ergänzenden Testgruppen.
Alte UI-/Architekturtests werden nach [Einzelfehlerbewertung](LEGACY_TEST_DISPOSITIONS.md) behandelt.
