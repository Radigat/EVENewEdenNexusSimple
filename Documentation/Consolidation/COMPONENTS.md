# Komponentenvergleich

Projekt: EVE New Eden Nexus - Assets, Industry, Markets. Entscheidung vom 25.09.2026; keine neue Fachimplementierung.

| Bereich | Aktive kanonische Quelle | Legacy-Quelle und Entscheidung |
| --- | --- | --- |
| App, Dashboard, Profile, Laufzeit, Fensterkorrektur | Simple: Sources/EVENexusSimpleApp einschließlich untracked Dateien | Nexus RootView/AppNavigation, Themen und andere UI archiviert; kein zweites App-Target |
| Auth, SSO, ESI und Charaktere | Simple: EVENexusCore/Auth, ESI, Character | Nexus EVESSOAuthorizationFlow/ESICharacterSynchronization mit anderem Callback/Keychain-/Persistenzmodell archiviert; kein Überschreiben funktionierender Anmeldung |
| SDE-Staging, Katalog, Aktivierung | Simple: Packages/EVEStaticDataKit, SDE/SQLiteStaticCatalog, Update/SDELifecycleService | Nexus SDEInstallation und SwiftData-Katalog bleiben Referenz; Datenmodelle sind nicht austauschbar |
| Assets, Blueprints, Warehouse | Simple: Assets/AssetWarehouse, Blueprints, ReservationLedger | Nexus manuelles/CSV-Inventar, Projektreservierungen und Auswahlrepository bleiben erhalten, aber nicht als äquivalente Simple-Funktion gewertet |
| Industrie, Reaktionen, Invention-Grundlagen, Logistik | Simple: Industry, Reactions; einschließlich JumpFreighterLogistics, OreRefining und Tests | Nexus ProductionGraph/RecipeResolution und IndustryRules besitzen eigene Typen/Rundungsverträge; kein heuristisches Zusammenmischen |
| Märkte, Loyalty Store, Public Contracts | Simple: Market, Contracts, LoyaltyStoreCatalog | Nexus Preisprofile, CSV-Import, Marktimport als Legacy erhalten; keine Änderung der aktiven Preisquellen |
| Produktionsbuch | Simple ProductionJournal, ProductionOverview, ProductionBookViews | Nexus ProductionBatch/Cost/Sale und SwiftData-Schemas v26–v28 sind **keine** identischen Dubletten; bestätigte Wallet-Verkaufszuordnung und ProjectBudget nur archiviert |
| Persistenz und Migration | Simple PersistenceModels, PersistenceSchemaV1, PersistenceRecovery und AppDataPaths | Nexus Schemas v1–v28/MigrationPlan vollständig archiviert; keine gegenseitige Store-Migration |
| Tests | Alle aktuellen Simple-Core-/App-Tests und Kit-Tests erhalten | Nexus-Tests bleiben im Quellarchiv; nicht als aktive Tests gezählt; historisch 10 bekannte Fehler laut Status, nicht neu verifiziert |
| Steuerung und fachliche Dokumentation | Root-Dokumente plus aktuelle Simple-Detailverträge | Projektbuch, ADRs, Berichte, Featurematrix und Prompts aus Nexus vollständig archiviert, ausdrücklich keine aktiven Folgeaufträge |

## Fachliche Auflösung der Widersprüche

Der lokal zuletzt verwendete und reparierte App-Stand ist die einzige ausführbare
Linie. Auswahlgrund sind belegte Nutzung, erhaltene Funktionalität und unveränderte
Datenverträge, nicht allein Dateizeitpunkte. Der ältere Nexus-Stand ist in einzelnen
Bereichen breiter, besitzt aber eine andere Daten- und Anwendungsarchitektur.
Ohne neue Adapter lässt er sich weder als Dateidublette ersetzen noch in den aktuellen
Produktionspfad einbauen. Diese Komponenten sind als ungelöste funktionale Vereinigung
offengelegt, vollständig erhalten und nicht versehentlich gelöscht.

Die bisherige Planning-Analyse hatte keinen technisch geprüften Komponenten-Mergeplan.
Deshalb wird hier keine unbelegte Gleichwertigkeit oder vollständige Fachintegration
behauptet. Metenox, P60/P61 und nur im Projektbuch geplante Kits bleiben historische
Planung; sie sind keine vorhandene Funktion, die durch diese Konsolidierung entfällt.
