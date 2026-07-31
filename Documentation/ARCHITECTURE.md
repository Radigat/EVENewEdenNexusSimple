# Architecture and skill ownership

| Module | Owning skill | Input | Output |
| --- | --- | --- | --- |
| Governance | `eve-documentation-kit` | decisions and evidence | ADRs, contracts, handoffs |
| SDE lifecycle | `eve-sde-integration` | CCP metadata/archive | validated candidate |
| Static package | `eve-static-data-kit` | accepted SDE profile | static catalog batches |
| Authentication | `eve-auth-kit` | SSO callback | authorization snapshot, token lease |
| ESI transport | `eve-esi-kit` | request and token lease | provenance-bearing response |
| Character | `eve-character-kit` | ESI character responses | character snapshot |
| Personal wallet | target composition using `eve-auth-kit`, `eve-esi-kit` and `eve-ui-kit` | character authorization and sourced balance | cross-character portfolio |
| Assets | `eve-assets-kit` | paged per-character asset responses | immutable owner snapshots and station/owner warehouse projection |
| Blueprints | `eve-blueprints-kit` | SDE definitions and ESI instances | activity candidates |
| Market | `eve-market-kit` | ESI orders and prices | order snapshot and quote |
| Reactions | `eve-reactions-kit` | SDE reaction activities | reaction candidates |
| Industry | `eve-industry-kit` | accepted domain snapshots | industry plan snapshot |
| Presentation | `eve-ui-kit` | view states and commands | SwiftUI presentation |
| Verification | `eve-testing-kit` | contracts and fixtures | separated evidence |
| Updates | `eve-update-kit` | version inventory and preview | confirmed orchestration |

The modules never infer missing private data. `fresh`, `partial`, `stale`,
`forbidden` and `unavailable` remain explicit. SDE base prices and ESI adjusted
prices are never market-price fallbacks.

The active catalog stores the package-derived `ReactionRuleProfile` unchanged;
the app does not derive a second set of dogma rules. SwiftData stores production
profiles, characters, each character's complete sourced asset snapshot, global
stock targets, plans, a mirror of the active SDE pointer and the latest
per-character/per-domain ESI snapshot metadata. Updating a domain replaces its
metadata and prunes older duplicates. Build-specific SDE payloads remain in
SQLite.

`AssetWarehouse` is a read-only projection over every persisted personal asset
snapshot. It resolves bounded item/container ancestry, groups the root location
first and the character owner second, retains inventory flags and snapshot
freshness, and excludes unresolved roots or container cycles from allocatable
stock. SDE supplies type names. Public ESI universe names supply NPC station
names where available; configured ACL-protected player structures reuse their
accepted Profile names and otherwise remain explicit IDs.

`StoredStockTarget` is an owner-entered minimum per type for the combined
warehouse. Assets remains factual and immutable. Industry derives
`allocatable = max(factual - target, 0)`, then subtracts active plan
reservations. A target shortfall is visible but never becomes negative stock.
All current manufacturing and reaction graph steps consume this one projection;
the shared pool does not claim that assets were transported between locations.
Invention, copying and research facilities consume the same contract when their
job planners are added, but version 1 still does not claim executable Science
job planning.

Planner continuity and the Production Overview are target-composition
persistence.
`StoredPlannerDraft` retains the latest production and manual-stock text without
turning either into a calculated fact. A successful calculation replaces the
single active `StoredPlan`; reopening the Planner restores that immutable
`IndustryPlanSnapshot`. Each material requirement freezes its SDE category,
group and optional production activity. The Planner therefore presents only
non-producible inputs as raw materials, grouped by source group, and places
manufacturable or reactable intermediates in a separate section below.
The catalog also exposes a read-only packaged-volume query. Industry uses it
after graph completion for configured logistics; SwiftUI never performs
type-volume joins.
`EVEMultibuyExport` derives a deterministic clipboard payload solely from
material requirements whose frozen `toBuy` quantity is positive. It emits one
plain `ItemName Quantity` line per type, without prices or presentation labels;
the app copies that payload only after the user presses the Multibuy export
button.
Explicit **Record production** creates one
`StoredProductionOverviewRow` per requested product and retains the complete
original plan as the row's source snapshot. The row stores the spreadsheet
inputs and provenance needed for the `EVE-indu- Delve.xlsx`
`Produktionsübersicht`: date, product, runs, ME/TE, system, units, source costs,
sale price and sold units. `ProductionOverviewCalculation` owns the derived
production cost, total sale value, cost per unit, 10% minimum sale price,
projected profit, margin and real profit. Unknown source costs remain `nil`;
they never become zero.

The planner freezes `IndustryCostBreakdown`: materials, manual top-level
BPC/BPO cost, system-index cost, Facility Tax, SCC surcharge, Alpha surcharge,
installation total and optional logistics. Logistics is one independent route
per enabled direction and uses the higher of SDE-volume charge or 0.5% Jita
replacement collateral, rounded up to 1 million ISK for every generated
contract. A route above the configured limit is split deterministically into
whole-item contracts; only a single packaged item above the limit is blocking.
Missing tariff, volume, collateral, or a valid contract limit makes the total
unavailable. The default is 350,000 m³; a provider-confirmed exception is an
explicit Profile input for indivisible oversized items. Sale
scenarios separately freeze gross revenue, Sales Tax, Broker Fee and net
revenue.

When recording a multi-product plan, the compact legacy Production Overview
still allocates the aggregate installation cost in proportion to known
material cost, or equally when no positive material cost exists. The
active/saved `IndustryPlanSnapshot` retains the authoritative complete
breakdown. Blueprint cost, sale price per unit and sold units remain editable
business inputs. `PlannerPersistenceController` owns SwiftData commands;
SwiftUI presents the draft, active plan, last five overview rows and the full
table.

The production basis is a target-owned `ProductionBasis` snapshot. SDE category
and group queries classify products into Capital, Medium, Large, Small,
Modules & Components, or Structures & Fuel. Industry owns deterministic
facility selection and records the selected structure on plan nodes and job
costs. SwiftUI only edits the accepted configuration and displays the resulting
selection. See `PRODUCTION_BASIS.md`.

Manufacturing systems are a list with stable IDs. Every configured structure
or station references one configured activity-system ID, so facilities in
different systems can coexist in one production basis. Reaction, invention,
blueprint copying, material research and time research retain separate system
configurations. A public ESI universe index supplies system names and IDs.
Public system, constellation and region details supply the saved region and
security band; the UI never offers `Unknown` as a selectable space type.
SwiftUI submits a debounced search command only after three characters and
never owns transport logic.

The same Profile composition refreshes the public `/industry/systems` snapshot
and displays every returned activity index beneath each selected system.
Manufacturing-system labels are persisted user annotations and are deliberately
excluded from facility-selection rules. The automatic production matrix shows
the system resolved through the selected facility assignment.

The target-owned catalog adapter streams the active SDE package's `typeDogma`
records for structures, Standup service modules and rigs. It publishes
immutable definitions to Industry; SwiftUI cannot edit Manufacturing ME/TE,
Reaction material/time, Science job-cost/time or Reprocessing-yield
modifiers. Service-module compatibility and enabled activities gate automatic
facility selection. The selected structure size limits the rig picker and both
the SDE slot count and the owner-specified maximum of three are enforced.
Laboratories enable Invention or Research activities while their job-cost/time
bonuses remain rig-derived. ESI does not reveal the fitted service modules, so
the owner records them explicitly and unresolved legacy/NPC capability remains
`needsReview`.

Authenticated player-structure discovery remains in ESI. The official API does
not enumerate every docking ACL for a character. The service therefore combines
two explicit paths: name search for ACL-visible structures, and automatic
candidate discovery from the character's asset locations, industry facilities,
and current or historical market-order locations. Every candidate is verified
through the ACL-protected structure-detail route and filtered to the configured
system. NPC stations, stale IDs and forbidden details remain distinguishable
diagnostics. ESI conditional caches are partitioned by character identity.
There is no parallel structure, service-module, facility-tax or rig
implementation in the UI.

Character capability snapshots are optionally persisted with each local
character record. The SDE-backed Science skill list and those freshness-aware
snapshots feed `InventionReadinessMatrix`; unavailable skill sheets remain
unknown. See `INVENTION_SKILL_MATRIX.md`.

Personal wallet balances use the authenticated
`/characters/{character_id}/wallet/` ESI route and the
`esi-wallet.read_character_wallet.v1` scope. `CharacterWalletService` owns the
scope-checked ESI-to-source-state mapping. SwiftData stores the complete
`Sourced<Double>` balance per character, including provenance and diagnostics.
`WalletPortfolioSnapshot` is target composition: it sorts characters and sums
only balances that actually contain a value. A missing or forbidden balance
makes the portfolio partial or unavailable; it is never substituted with zero.
SwiftUI issues refresh commands through `RuntimeState` and does not receive a
token or call ESI directly.

`RuntimeState` retains one `EVESSOService` actor per normalized client ID.
Short-lived access-token leases are therefore reused across character, wallet,
skill and structure commands instead of re-reading the refresh token for every
operation. Refresh tokens remain exclusively in macOS Keychain. The store
prefers Apple's Data Protection Keychain with
`AfterFirstUnlockThisDeviceOnly`, requests no user-presence policy and migrates
legacy file-based entries on first access. Ad-hoc local builds without the
required signing entitlement fall back to the legacy Keychain rather than
writing an unprotected token.

The Characters UI owns the explicit local disconnect command. It first removes
the refresh token through the Auth boundary, then deletes the character's local
authorization, wallet/capability/asset snapshots, and ESI metadata. Production
records are a separate owner-controlled business history and are not deleted by
disconnecting a character.

The Characters page keeps data synchronization separate from authorization.
Data synchronization reuses existing grants without opening a browser.
Authorization accepts whichever character the owner selects in EVE SSO. After
JWT verification, the returned character ID selects the matching local record
for reauthorization or creates a new record; the UI never asks the owner to
preselect the same local row. The refresh token is stored only under that
verified character ID, so selecting one character cannot replace another
character's credential.

Each character row also presents an exclusive scope disclosure. Expanding one
character collapses the previous selection and renders only that character's
sorted, granted scopes from the token-free `AuthorizationSnapshot`, together
with the authorization time. No credential material is exposed to SwiftUI.

The Profile page owns a saved `ProductionBasis` baseline and publishes only its
dirty state and save/discard commands to the navigation composition. Leaving
Profile while dirty is blocked by a three-way confirmation: save and continue,
discard and continue, or cancel. A failed save keeps the user on Profile, and
discard restores the exact last loaded or saved baseline before navigation.

The same basis binds market-order selling to one connected trader character.
The Character boundary supplies sourced skills and unmodified standings; the
Industry configuration derives the Jita IV-4 sales tax and NPC broker fee
under rule `ccp-market-fees-2026-07-02`. SwiftUI displays that immutable
evidence and requests a character capability refresh through `RuntimeState`;
it does not call ESI or calculate fees itself. Missing or forbidden source
data produces unavailable fees, so the Market boundary cannot create a listed
sale quote with an invented zero rate.

The Profile-owned `LogisticsConfiguration` stores only owner decisions:
enabled directions, route labels and the current ISK/m³ rate. Industry composes
those settings with SDE packaged volume and complete Jita sell-depth
collateral. Blueprint supplies manual BPC/BPO provenance while Industry owns
the accepted line-level cost allocation. UI displays the immutable blueprint
entries and generated courier contracts, including both candidate charges,
the winning basis and million-ISK rounding; it does not calculate either
cost.

Automatic reaction-facility assignment is a Reactions-to-Industry handoff.
Only reaction-capable refineries in the configured reaction system are ranked.
The accepted selection is persisted with the basis and becomes the
`ReactionProfile` consumed by planning; manufacturing selection remains a
separate category-specific decision.

Blueprint-to-Industry composition owns the four Science-facility selections:
invention, copying, material research and time research. Each selection is
restricted to its configured solar system and ranks SDE-derived job-cost
multiplier before time multiplier and facility tax. The Profile view consumes
`ScienceFacilitySelection`; it neither interprets dogma nor claims that an
owned BPO/BPC job can already be executed by the version-1 planner.

The application composition loads the newest saved `ProductionBasis` before
the Planner enables calculation. The same preflight awaits the public industry
system indices and facility references used by installation-cost configuration,
so the first plan uses the same accepted configuration as later plans.

The SwiftUI theme uses the exact semantic values from `SPEC_DESIGN.md`: base
`#0B0F1A`, surface `#131A2A`, elevated `#1B2438`, border `#263149`, cyan accent
`#35C7E8`, amber highlight `#F5B942` and the specified status colors. Layout
spacing, card and badge radii, sidebar widths and input heights are centralized
beside the colors; ISK values use monospaced digits and the amber highlight.

## Version 1 boundaries

- Personal characters only.
- Personal wallet balances and their cross-character sum; no corporation
  wallet, journal or transaction presentation.
- Manufacturing and reactions; invention configuration is visible and stored,
  but invention planning is unsupported.
- The Forge/Jita IV-4 market only.
- Local storage only; no cloud sync.
- No corporation data, transport optimization, multi-hub optimization or job
  installation.
