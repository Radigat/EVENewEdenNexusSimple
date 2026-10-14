# EVE New Eden Nexus - Assets, Industry, Markets

Projekt: EVE New Eden Nexus - Assets, Industry, Markets

Standardmodell: GPT-5.6 Sol High

Aktuelle Regel: Es gibt nur einen aktiven Projektstand.

Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

Einziger aktiver Projektordner: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.
Diese Regeln ersetzen die Projektsteuerung aller Legacy-Stände; historische
Prompts und AGENTS-Dateien in Archiven sind keine aktiven Aufträge.

## Verbindliche Arbeitsgrenzen

- Ausschließlich die ausdrücklich autorisierte fachliche Konsolidierung bestehender
  Funktionen durchführen; notwendige Adapter, UI-Anbindung und additive Migrationen
  gehören dazu. Bestehende Rechenregeln erhalten. Keine weiteren Funktionen planen
  oder implementieren. Nach Prüfung, lokalem Checkpoint und Abschlussbericht stoppen.
- Tatsächlicher Quellcode, vorhandener Diff und konkrete Benutzeranweisung haben
  Vorrang vor historischen Planungen. Geplant, implementiert, getestet und vom
  Eigentümer abgenommen getrennt ausweisen.
- Vor Änderungen Branch, HEAD, Index und Arbeitsbaum prüfen. Vorhandene lokale
  Änderungen erhalten. Altstände nicht löschen; ihre Herkunft und Konflikte
  in `Documentation/Consolidation/DECISIONS.md` dokumentieren.
- Aktuelle Steuerdateien sind README, PROJECT_STATE, ARCHITECTURE, PRODUCT,
  WORKFLOW, MODEL_POLICY und ROADMAP im Projektstamm. Detailverträge unter
  `Documentation/` bleiben erhalten. Alte Einstiegspfade sind nur Verweise.
- Bundle-ID, Swift-Module, Keychain-Dienste, OAuth-Callback, UserDefaults,
  Datenbankpfade, Schemas und Migrationsketten nicht durch Namensbereinigung ändern.
- Bestehende deterministische Fachregeln, explizite fehlende Datenzustände,
  SDE-/ESI-Trennung und lokale Datenintegrität bewahren. Keine produktiven
  Benutzerdaten als Testdaten verwenden; keine Tokens in Git oder Protokollen.
- Bei Code-/Projektänderungen SwiftPM und natives Xcode-Debug prüfen; das lokale
  `EVEStaticDataKit` separat testen. Live-Abnahmen bleiben opt-in.
- Git nur in dieser eigenen Repository-Wurzel verwenden, niemals im
  übergeordneten Home-Repository. Der Benutzerauftrag autorisiert den lokalen
  Konsolidierungs-Checkpoint. Kein Push, Force-Push oder Umschreiben der Historie.
- `MODEL_POLICY.md` ist die verbindliche Modellvorgabe. Kein automatischer
  Wechsel des Modells oder der Reasoning-Stufe: Reicht GPT-5.6 Sol High nicht
  aus, vor einem Wechsel nachfragen und zwei oder drei konkrete Vorschläge mit
  exaktem Modell, Reasoning-Stufe, Empfehlung und kurzem Trade-off geben.

## Erhaltene Interaktionsregeln

## Copyable EVE names

- Every visible EVE item or type name, including products, blueprints and reaction outputs, must be directly clickable to copy its exact displayed name.
- Every visible EVE place name, including solar systems, regions, stations and player structures, must be directly clickable to copy its exact displayed name.
- Apply the same behavior to other visible EVE entity names, such as characters and corporations, for a consistent interface.
- Use the shared `EVEEntityText` component so copying provides localized visible success or failure feedback plus an accessible label and hint. Do not implement isolated clipboard variants.
- A copy click must not also select a row, toggle disclosure, activate a picker or trigger a double-click action. If an enclosing control must own the primary click, provide a separate, equally visible copy target instead of leaving the name uncopyable.
- Preserve unresolved or unavailable names as explicit states. Never replace missing domain data with an invented name, raw identifier presented as a resolved name, or zero.

## Sortable data tables

- Every column header in a tabular collection of peer data rows must be clickable and sort that column.
- Repeated clicks on the active column must alternate between ascending and descending order, with a visible direction indicator and an accessible label and value.
- Sort by the column's factual typed value, not by a decorated or rounded display string: numbers numerically, dates chronologically, status by an explicit documented rank, and resolved names textually.
- Keep missing or unavailable values distinct from zero. Place them deterministically after known values in ascending order and before known values in descending order unless the screen documents a stronger domain rule.
- Add a stable final tie-breaker, normally the row's persistent identity, so equal values never make rows jump unpredictably.
- Prefer native SwiftUI `Table` sorting. Custom tables must reuse the shared sortable-header presentation or an existing tested domain sort descriptor instead of implementing unrelated arrows or click behavior.
- Preserve the selected sort while filters or live snapshots update during the current view lifetime.
- Do not apply global row sorting to forms, card grids, key/value summaries, or hierarchical/tree tables where reordering would break parent-child or prescribed sequence semantics. If peer rows exist within a hierarchy, sort only within the same parent and keep the hierarchy intact.

## Continuous documentation

- Keep `PRODUCT.md` current as part of every implementation, bug fix, migration, configuration change, or material behavior change. Documentation is part of the change, not a deferred follow-up.
- Record the corresponding development step in `dev-diary.md` with its date, scope, result, verification evidence, and remaining open work.
- Describe only the current factual behavior in `PRODUCT.md`; move chronology and superseded behavior to `dev-diary.md` instead of leaving contradictory guidance in the main documentation.
- Keep planned, implemented, automatically verified, live-service-verified, and owner-accepted states distinct. Never present one evidence level as another.
- Link to the authoritative contract or evidence under `Documentation/` rather than duplicating detailed rules in several files. Preserve explicit unavailable, partial, stale, forbidden, and unresolved states in all documentation.

## Fachliche Konsolidierungsverträge

Maßgeblich sind [Funktionsvertrag](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md) und
[Feature-Zuordnung](Documentation/Consolidation/FEATURE_COVERAGE.md).
Fertigungsprojekte sind Datensätze in der einzigen aktiven App, keine weiteren Arbeitsordner.
