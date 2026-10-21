# EVE New Eden Nexus - Assets, Industry, Markets – Architektur

> Kanonische Architektur des aktiven Bestands. SwiftUI-App `EVENexusSimpleApp`,
> Fachkern `EVENexusCore`, SQLite-Brücke `CSQLite` und lokales `EVEStaticDataKit`
> bleiben unverändert geschichtet. Die in der Tabelle genannten Skills sind
> historische Verantwortungsbezeichnungen, keine zusätzlich vorhandenen Swift-Packages.
> Die alternative Legacy-Architektur mit Domain/Application/Infrastructure/Persistence
> ist vollständig archiviert und keine zweite aktive Implementierung.
> Auswahl und Grenzen: [Konsolidierungsentscheidungen](Documentation/Consolidation/DECISIONS.md).

## Additive fachliche Integration

SwiftData V3 ergänzt einen versionierten, revisionsgesicherten Arbeitsdatenverbund.
V1 und V2 bleiben eingefroren. Lager-, Preis-, Wissenschafts- und Belegdienste leben im
bestehenden Kern; Projekt-, Reservierungs- und Einkaufsdatensätze sind seit 19.10.2026 nur noch
dekodierbare Altdaten ohne Logik; die App stellt Persistenz und Bedienung bereit.
Die Details zu Schnittstellen, Wissenschaftsversorgung und Sicherung stehen im
[Funktionsvertrag](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md).

Fertigungsprojekte samt Projektwahl, Reservierungen und Einkaufsbudget/-fortschritt
sind entfernt; der Planner hält Eingabe und Plan ausschließlich in
`StoredPlannerDraft`/`StoredPlan`. Die Preisprofil-Bedienung ist Teil der
bestehenden Markteinstellungen, die lokale Sicherung/Wiederherstellung und der
anonymisierte Diagnoseexport sind Teil der allgemeinen Einstellungen. Das
verbleibende `ConsolidationWorkbenchView` dient nur den fachlich zugeordneten
Dialogen für manuelle Lager, Wissenschaftsaufträge und Verkaufsbelege.
Automatische Migrations- und SDE-Sicherungen bleiben im Kern und im
App-Lebenszyklus unabhängig von diesen Bedienflächen aktiv.

Der eng begrenzte vollständige SwiftData-Restore ergänzt diese Sicherung:
`StoreFullRestore` besitzt Snapshot, Datensperre, Vorgangsprotokoll und
Dateiaustausch; `FullStoreRecovery` besitzt die bewusste Auswahl und isolierte
SwiftData-Prüfung. Die Prüfung läuft ohne normale Startimporte in einem
kurzlebigen Prozess. Die normale App öffnet den kanonischen Store erst nach
der Prüfung ausstehender Vorgänge. Schlüsselbund, Preferences, SDE und separate
Markt-/Vertragsspeicher gehören nicht zum Austausch. Vertrag und Nachweise:
[Review-Korrekturen](Documentation/REVIEW_FIXES_2026-10-02.md).

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
| Blueprints | `eve-blueprints-kit` | SDE definitions and ESI instances | owned portfolio and research quote |
| Market | `eve-market-kit` | ESI orders and prices | order snapshot and quote |
| Reactions | `eve-reactions-kit` | SDE reaction activities, market quotes and optional verified facility context | reaction candidates and profitability snapshot |
| Industry | `eve-industry-kit` | accepted domain snapshots | industry plan snapshot |
| Presentation | `eve-ui-kit` | view states and commands | SwiftUI presentation |
| Verification | `eve-testing-kit` | contracts and fixtures | separated evidence |
| Updates | `eve-update-kit` | version inventory and preview | confirmed orchestration |

The modules never infer missing private data. `fresh`, `partial`, `stale`,
`forbidden` and `unavailable` remain explicit. SDE base prices and ESI adjusted
prices are never market-price fallbacks.

Item presentation follows the shared
[`ITEM_PRESENTATION.md`](Documentation/ITEM_PRESENTATION.md) contract. The visible resolved
entity owns the image Type ID: products use the produced root item, Blueprints
use their Blueprint Type ID, and materials or structures use their own Type ID.
Recursive Industry plans are child-first, so all Planner and Production
Overview consumers resolve a request through
`IndustryPlanSnapshot.topLevelProductNode(for:)`; they never use the first
arbitrary request node as an end-product image.

The active catalog stores the package-derived `ReactionRuleProfile` unchanged;
the app does not derive a second set of dogma rules. SwiftData stores production
profiles, characters, each character's complete sourced personal and authorized
Corporation asset snapshots, global
stock targets, each character's complete sourced blueprint snapshot, plans, a
mirror of the active SDE pointer and the latest per-character/per-domain ESI
snapshot metadata. Updating a domain replaces its metadata and prunes older
duplicates. Build-specific SDE payloads remain in SQLite.

Application startup treats the primary SwiftData container as the availability
gate for background work. After the container opens, the root view starts the
runtime-owned `StartupDataLoad` once per process: character synchronization and
planner configuration run in parallel, then moon, mineral and reaction analyses
run while `releaseStartupAutomaticScans` opens the gate for the automatic
Main-Hub and Public-Contracts schedules. The Dashboard joins this character
result instead of synchronizing again. When that container cannot be opened, the recovery
surface is shown without opening or migrating the secondary Public Contracts
store and without starting ESI or automation tasks. On a normal launch,
independent active-SDE, service-status, demand-ledger, opportunity-snapshot and
Contract-automation loads are started together; actor isolation still owns
their state updates.

The primary store has one stable canonical location below
`com.local.EVENexusSimple/ApplicationData`, independent of whether the app is
started by Xcode or SwiftPM. Startup copies a legacy `default.store` only when
the canonical store does not yet exist, never deletes the source, creates a
pre-migration backup, and opens an explicit versioned SwiftData schema. The
current V1-to-V2 change is lightweight and adds the Corporation fields. A
one-time protected recovery import can merge newer character, ESI-metadata and
setting rows into an older, more complete store before background work starts.
App-owned `UserDefaults` keys likewise use the stable application domain and
copy missing values from the former executable-name domain once.

The version identifiers and migration-stage list are computed static metadata
rather than stored static SwiftData values. This preserves the exact V1/V2
schema and migration graph while remaining compilable on the Swift 6.1 SDK used
by the `macos-15` GitHub Actions lane. Large SwiftUI refresh fingerprints are
assembled from explicitly typed component arrays for the same compatibility
reason; their ordering, separators and domain values remain unchanged.

The public EVE status-page boundary decodes its `updated_at` timestamp with an
explicit ISO 8601 strategy that accepts both fractional and whole seconds. It
does not rely on Foundation's toolchain-dependent default `.iso8601` behavior;
invalid timestamps still make the response explicitly unavailable through the
existing decoding error.

The normalized CCP User-Agent operator contact is the intentionally public
project address `projekt-st@gmx.de`, not a user setting or authentication
credential. It is compiled into the application and can be overridden by a
development environment variable; the former local `AppSetting` is accepted
only as a hidden migration fallback. Update presentation keeps installed
build, official build and the highest CCP
`afterBuildNumber` schema boundary separate. A candidate exists only when no
catalog is installed or the official build is greater than the active build.
An older metadata response can therefore never trigger a downgrade.

`AssetWarehouse` is a read-only projection over every selected persisted personal
or Corporation asset snapshot. It resolves bounded item/container ancestry,
groups the root location first and the asset owner second, retains inventory flags and snapshot
freshness, and excludes unresolved roots or container cycles from allocatable
stock. Each projected item retains the type IDs of its container ancestry. The
production projection uses SDE category `Ship` to remove both each ship and
every descendant fitted to or stored inside it, while an ordinary hangar
container and its descendants remain eligible. SDE supplies type names. Public ESI universe names supply NPC station
names where available. Asset locations typed `other`, structure-range IDs
historically typed `station`, and structure-range `item` parents absent from the
returned asset IDs become Player Structure roots and remain allocatable. The
last case matters because ESI may use `item` both for an actual container and
for a structure-range root: a matching returned item ID stays a container,
while only the unmatched high parent becomes a structure candidate. Character
synchronization resolves candidate names and type IDs through the ACL-protected
structure-detail route and persists successful values in the immutable asset
snapshot. Missing scope, forbidden docking ACL and stale structure details
produce a partial source state but never remove the structure's assets;
unresolved names remain explicit IDs.

The projection builds one item index and resolves each root once. Target
composition caches the latest projection by persisted snapshot identity so
Assets and Planner reuse it instead of decoding and rebuilding on every SwiftUI
render. SDE type names and category/group classifications are joined in chunks
of at most 500 IDs rather than one SQLite query per asset type. The shared All
items and Warehouse presentation additionally aggregates each
location/owner/type/inventory-flag row and organizes the result off the main
actor. The remembered presentation choice is either one alphabetical section,
SDE group sections, or SDE category sections exposed as main groups; unresolved
classifications remain in an explicit `Unclassified` section. Lazy grids render
only expanded owners. The name-resolution identity contains visible and target
type IDs but not target quantities or timestamps, so editing an existing
minimum does not restart the asset-name and location-name joins.

`StoredStockTarget` is an owner-entered minimum per type for the production
warehouse. The **All items** projection remains factual and covers every known
location. The **Warehouse** projection filters it to exact production-facility
IDs selected in Profile for the configured manufacturing categories, reaction
system, invention, copying and ME/TE research. Activities assigned to the same
station or Player Structure are merged, while configured but unused structures
and Main-Hub market inventory are excluded. A missing exact ESI location ID
remains visibly unresolved; the projection never infers a facility from a
solar-system name. It also removes SDE category `Ship`. A visible Warehouse row commits its local
minimum draft only on Return or focus loss; zero removes the target. The manual
add control queries published active-SDE item names only after three characters
and persists the selected type ID and exact name, never an unverified free-text
alias. Raw ESI inventory flags remain preserved and are displayed beneath a
readable storage-position label. One shared persisted switch controls whether
Corporation snapshots contribute to All items, Warehouse and Planner stock.
Corporation synchronization first verifies
`esi-characters.read_corporation_roles.v1` and the `Director` role, then pages
`/corporations/{corporation_id}/assets` with
`esi-assets.read_corporation_assets.v1`; division names come from the separately
scoped divisions endpoint. Multiple acting Directors for one Corporation are
deduplicated before quantities are projected. Missing scopes, missing Director
role and endpoint failures retain forbidden or unavailable source state and are
never converted to an empty hangar. Industry derives
`allocatable = max(factual - target, 0)`, then subtracts active plan
reservations. A target shortfall is visible but never becomes negative stock.
All current manufacturing and reaction graph steps consume this one projection;
the shared pool does not claim that assets were transported between locations.
Concrete copying, research and invention planning now uses these established
source contracts through the additive consolidation adapter. It never executes in-game jobs.

`BlueprintPortfolio` is a read-only target composition over every persisted
personal blueprint snapshot. It retains owner identity, source state and
snapshot provenance while keeping the ESI distinction between an original
(`quantity = -1`) and a copy (`quantity = -2`). The Blueprint boundary joins a
selected instance with its active SDE definition. Market supplies a
provenance-bearing current adjusted-price snapshot, while Industry supplies
the separately configured ME and TE research systems, facilities, job-cost
multipliers, taxes and surcharges. `BlueprintResearchCostCalculator` owns the
ten official level multipliers and returns separate step and cumulative ME/TE
costs. SwiftUI only presents that quote.

The displayed BPO value is deliberately named a replacement estimate: current
SDE base price plus current-cost research to the instance's present ME/TE.
It does not claim historical spend or contract-market value. BPCs are not
researchable. A missing adjusted price, facility or SDE reference prevents an
invented total. Blueprints with extra SDE research materials retain a blocking
warning and omit a replacement total until their level-scaling rule has
separate verified evidence.

Planner continuity and the Production Overview are target-composition
persistence.
`StoredPlannerDraft` retains the latest production and manual-stock text without
turning either into a calculated fact. A successful calculation replaces the
single active `StoredPlan`; reopening the Planner restores that immutable
`IndustryPlanSnapshot`. Every required material freezes its SDE category,
group, production eligibility, source preference and Main Hub provenance. Raw
materials permit buy or warehouse; eligible manufacturing and reaction
intermediates additionally permit produce and default to it. A bought or
warehouse-supplied intermediate becomes a replacement-value leaf and its own
production branch, descendant material demand and installation job are omitted.
Changing an individual source preference immediately requests the same normal
Planner recalculation used by the bulk recommendation command, so the visible
snapshot never intentionally mixes the old graph with the new preference. A warehouse shortfall
creates a purchase only for the uncovered quantity. Every producible component
and reaction intermediate also freezes a make-or-buy analysis for the complete
required quantity: exact Main Hub depth and inbound logistics for buying versus
the batch-rounded direct inputs, installation and inbound logistics for building.
`MakeOrBuyRecommendationApplication` maps only available recommendations onto a
new preference set. UI composition then requests a normal Planner recalculation;
the resulting immutable snapshot, rather than the comparison preview, owns the
final costs, production jobs and Main Hub shopping list. Raw-material choices
and unavailable recommendations are preserved. `IndustryJobCost` freezes the
displayable job identity, runs, output quantity, ME/TE, top-level marker,
facility and installation cost so the UI does not reconstruct a build list from
market or SDE data.

`IndustryPlanner.prepare` also warms immutable names and classifications for
the bounded graph through catalog batch contracts. Logistics resolves names
and packaged volumes per cargo batch instead of once per line. A recursive
reference plan may hand matching make-or-buy analyses to its immediately
following selected scenario only when SDE build, Industry rule version and
Main-Hub market snapshot identity still match; each reused row must also match
the exact required quantity. A different market identity or quantity performs
the normal comparison again. These are query- and duplicate-work reductions;
they do not alter order-depth selection, costs, fees, logistics rules or
rounding.

Compressed-ore procurement is projected before inbound courier splitting.
Covered direct-mineral quantities are removed first; the selected compressed
ore and every remaining Main-Hub purchase then form one factual cargo manifest
for the configured Main-Hub-to-Home-Hub route. The refining structure remains
the operational facility and does not create a separate long-haul destination.
Every concrete ore output freezes its SDE type name, produced quantity,
plan-used quantity and planned warehouse surplus. Surplus does not mutate the
Assets snapshot and is not a cost credit; the full ore, transport and refining
cost stays on the product. This keeps the Assets-to-Industry handoff immutable
while making planned future inventory explicit.
Each facility profile may assign no refining implant or one official
`Reprocessing RX-801`, `RX-802` or `RX-804` selection per character. Yield
ranking and the frozen proposal apply the selected 1%, 2% or 4% multiplier
after facility and skill yield. The optional persisted mapping keeps legacy
profiles decodable as no implant. This mapping is a facility-scoped planning
assumption, not a synchronized claim about the character's currently active
clone; Character supplies skill evidence while Industry owns the hypothetical
implant scenario.

`ProductionBasis.tradingLocations` is the authoritative procurement-location
configuration. Every entry freezes a `ProcurementLocation` plus its own trader
and `MarketTaxConfiguration`. `mainTradingLocationID` is restricted to Jita,
Amarr, Dodixie, Rens or Hek; it supplies Planner market depth and is synchronized
into `LogisticsConfiguration.homeTradeHub` for the historical logistics contract.
`homeTradingLocationID` is independent and may name any configured NPC station
or ACL-visible Player Structure without changing the Planner price source.
Additional stations come from public ESI search; Player Structures use the
selected character's authenticated ESI search and detail scopes. Legacy profiles
migrate the old field named `homeTradingLocationID` into the new Main Hub and
leave the new Home Hub unconfigured. Production structures are not injected as
Trading Location choices. Selecting an authenticated ESI Player Structure whose
name matches a saved legacy Trading Location upgrades that entry in place. Its
stable configuration ID, Home-Hub role, trader and fee evidence are retained.

Accounting, Broker Relations and unmodified standings remain sourced from the
trader character. Each fee calculation also freezes its Trading Location. NPC
station refresh resolves the owner corporation and faction through ESI before
calculating the broker fee. A Player Structure's owner-defined broker fee is not
exposed by ESI and therefore remains unavailable rather than becoming zero.
The catalog exposes only an actually imported `packaged_volume`; it never
coalesces a missing value with assembled SDE `volume`. Runtime resolves the
bounded set of graph-relevant public `/universe/types/{type_id}/` records,
freezes their `packaged_volume` values as a sourced snapshot and composes that
snapshot with the static catalog before Industry calculates logistics. SwiftUI
never performs type-volume joins or ESI requests.
`EVEShoppingList` derives the deterministic, sorted set of purchase rows solely
from material requirements whose frozen `toBuy` quantity is positive. It
retains the exact quantity and the matching market quote for presentation;
incomplete quote depth remains unavailable and prevents a factual purchase
total. `EVEMultibuyExport` consumes this same projection, so the expanded Market
details and clipboard payload cannot select different items. Each plan has one
Main Hub purchase group. The export emits one plain
`ItemName Quantity` line per type, without prices or presentation labels; the
app copies the payload only after the user presses its Multibuy export button.
The Main Hub row is a full-width disclosure. Its expanded table shows every
item, quantity, complete weighted unit price, line total and market coverage;
the export button remains a separate action.
`EVEMultibuyExport.make(items:)` is the single line formatter. The Planner
purchase-location hint (`MaterialPurchaseLocationHints`) joins shopping lines
with the already prepared mineral and moon-material recommendations and groups
one Multibuy export per recommended location. It never alters plan costs or
starts network work. `PlannerPurchaseLocationHintPanel` sorts it through the
shared `SortableTableHeader`.
The same formatter also creates a separate replenishment payload from positive
`fromStock` quantities. The Planner displays those warehouse-consumption lines
with quantity, weighted Main Hub unit price and replacement value; they do not alter
the immediate purchase list or add a second cost.
Explicit **Record production** creates one
`StoredProductionOverviewRow` per requested product and retains the complete
original plan as the row's source snapshot. The row stores the spreadsheet
inputs and provenance needed for the `EVE-indu- Delve.xlsx`
`Produktionsübersicht`: date, product, runs, ME/TE, system, units, source costs,
sale price and sold units. `ProductionOverviewCalculation` owns the derived
production cost, total sale value, cost per unit, 10% minimum sale price,
projected profit, margin and real profit. Unknown source costs remain `nil`;
they never become zero.

`SaleScenarioResult` also freezes optional sales-tax and broker-fee rates plus
whether a broker fee is applicable. `ProductionOverviewProjector` therefore
keeps a known tax rate when a restricted capital has no legal Highsec Main-Hub
quote, while marking the broker fee as not applicable rather than inventing a
zero fee. The minimum price and profit omit that non-applicable fee but still
deduct known sales tax. A missing rate for an otherwise applicable listed sale
remains unavailable and blocks net profitability. Legacy snapshots may recover
tax only from their own evidenced Home/Coalition sale amounts; current Profile
state is never injected into historical rows.

The recent five-row preview and complete overview both use the same editable
`ProductionOverviewGrid` and `StoredProductionOverviewRow`. BPO/BPC cost, sale
price and sold quantity are direct text fields in both views. The sold control
also provides a quick not-sold/full-sale toggle without removing partial-sale
quantities. Every accepted edit saves through the surrounding SwiftData
composition; failed saves roll back rather than leaving an unsaved value
visible.

The planner freezes `IndustryCostBreakdown`: full source-aware material replacement,
manual top-level BPC/BPO cost, system-index cost, Facility Tax, SCC surcharge,
Alpha surcharge, installation total and inbound logistics. Procurement
logistics transports purchased quantities and make-or-buy direct inputs from
the Main Hub to their configured Home-Hub production facility and uses
the higher of public-ESI packaged-volume charge or 0.5% replacement collateral, rounded up to 1
million ISK for every generated contract. A matching hub/production location
creates no leg. Main-Hub sale scenarios add a separate finished-product route
from the Home Hub back to the Main Hub; Home-Hub sale scenarios freeze that
return route as zero. The comparison uses exact ESI location identity before
tariff validation, so identical Main and Home locations remove both directions
without requiring a transport rate. A route above the configured limit is split deterministically
into whole-item contracts; only a single packaged item above the limit is
blocking.
Missing tariff, volume, collateral, or a valid contract limit makes the total
unavailable. The default is 350,000 m³; a provider-confirmed exception is an
explicit Profile input for indivisible oversized items. Sale
scenarios separately freeze location-bound gross revenue, Sales Tax, Broker
Fee, net revenue, finished-product logistics, scenario total cost, profit,
margin and ROI. Home-Hub market or fee failure leaves only those Home-Hub
scenarios unavailable and preserves the Main-Hub plan.

`IndustryPlanSnapshot.targetMarket` (`PlannerTargetMarket`) is an optional
decision label. It is absent in legacy snapshots and never feeds a
calculation. `PlannerTargetMarketSuggestion` picks the market of the highest
finite, non-pending sale scenario. The Planner keeps the draft choice in the
`AppSetting` key `planner.target-market.draft.v1`. It labels newly saved plans
with it and re-encodes the active plan when the choice changes; the
Production Overview reads the label from each row's snapshot copy. No
SwiftData schema change is involved.

The manual alliance sale (`PlannerAllianceSaleInput` →
`PlannerAllianceSaleCalculator` → optional
`IndustryPlanSnapshot.allianceSale`) is computed from the frozen plan and
never changes the nine market scenarios. Its cost is
`totalProductionCost` plus the existing outbound logistics of the chosen
delivery hub's listed-sale scenario. Revenue covers only accepted units, the fee
defaults to an explicit 0 % assumption, and multi-product plans, missing price,
cost or route stay unavailable. `PlannerTargetMarket.allianceMarket` extends the
target-market label. The suggestion considers a complete, non-provisional
alliance result and loses ties to market scenarios.

`IndustryCostBreakdown.total` is the only current-plan total constructor:
material replacement + entered BPC/BPO allocation + complete Installation +
logistics. `Installation` is itself the sum of system-index cost, Facility Tax,
SCC surcharge and Alpha surcharge, so none of those detail lines is added a
second time. `effectiveLogisticsCost` is zero only when logistics was disabled;
an enabled but incomplete logistics calculation keeps the total unavailable.
The recorded total exposes a recomputation consistency check. Sales Tax and
Broker Fee reduce their sale scenario's revenue and are not production-cost
components.

Material valuation follows the selected production graph without double
counting. Industry quotes the complete requirement of every non-produced input
once against Jita sell depth and uses those values for material and total
production cost. The informational warehouse-consumption countervalue is the
actual stock allocation multiplied by the same quote's weighted unit price; it
is already contained in material replacement and is not added again.
Operational purchase and stock quotes remain only as backward-compatible
snapshot detail. Missing full-requirement depth keeps both the affected
aggregate and warehouse countervalue unavailable instead of valuing owned
stock at zero. This is a current replacement-value estimate, not historical
acquisition cost.

When recording a multi-product plan, the compact legacy Production Overview
allocates aggregate installation, Blueprint and logistics cost in proportion
to known material cost, or equally when no positive material cost exists. The
active/saved `IndustryPlanSnapshot` retains the authoritative complete
breakdown. Blueprint cost, sale price per unit and sold units remain editable
business inputs. `PlannerPersistenceController` owns SwiftData commands;
SwiftUI presents the draft, active plan, last five overview rows and the full
table.

Recursive reconstruction remains session-only until the user deliberately
publishes it. Its Production Overview preview is built from the same immutable
row drafts used by the persistence command. Publishing stores one row per
imported finished product and one shared route-adjusted snapshot after a
confirmation dialog. Main→Home freezes Home-Hub listed-sale prices and fees;
Main→Home→Main freezes Main-Hub listed-sale prices and adds the finished-product
return leg to logistics before allocation. The provenance timestamp identifies
the current-market reconstruction; it is never labelled as historical actual
cost. A failed SwiftData save rolls back the whole row batch.

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
configurations. A public ESI universe index supplies system names and IDs. Its
initial `/universe/names` batches use a bounded concurrency of four, and all
concurrent searches share the same in-flight index build so that a cancelled
debounced query cannot restart the complete fetch.
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
modifiers. Each structure owns one physical solar-system location, while
service-module compatibility and enabled activities make it eligible for any
number of matching Manufacturing, Reaction or Science configurations in that
location. Industry ranks the best eligible structure independently for every
activity; the UI does not require a second manual structure assignment. The
selected structure size limits the rig picker and both the SDE slot count and
the owner-specified maximum of three are enforced.
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
system. Asset synchronization additionally resolves the concrete structure
roots already present in the downloaded character inventory and embeds accepted
names and type IDs in that snapshot. Detail requests are bounded to six
concurrent calls. NPC stations, stale IDs and forbidden details remain
distinguishable diagnostics. ESI conditional caches are partitioned by
character identity.
Fresh cached bodies are reused until their server expiry. The in-memory cache
is least-recently-used bounded to 512 entries and 64 MiB, and disconnecting a
character purges only that character's private entries. Jita order-book fan-out
is cancellable and limited to six concurrent per-type requests; it does not
create unbounded tasks for a large plan. Each regional type response discards
orders from every station except the exact configured location before it is
retained, reducing peak memory without changing location-bound depth pricing.
Every network miss and POST additionally passes one `ESIRequestCoordinator`
owned by the app's shared `ESIClient`. The coordinator admits at most six
transports process-wide and at most two requests marked as automatic work;
interactive work is selected before queued standard or automatic work while
FIFO order remains stable inside one priority. Queue cancellation removes the
waiter without consuming a permit. Each individual retry attempt releases its
permit before the existing cancellation-aware backoff, so a sleeping retry
cannot stall unrelated work. Paging order, compatibility and conditional-cache
headers, response provenance, 420/429 mapping, idempotent GET retry and the
non-retrying POST contract remain in the transport layer unchanged.

Cache release follows ownership boundaries. Persisted Public Contract region
and item pages and the consumed catalog-wide Main-Hub order family discard only
their matching public response bodies. Planner completion trims the shared LRU
working set to 32 MiB only when it is larger. A macOS memory-pressure warning
trims it to 16 MiB and a critical event drops all derived HTTP bodies plus the
decoded opportunity-store copy; atomic files and Runtime last-known-good values
remain available. A later request therefore performs a normal revalidation or
reload rather than observing an invented empty response.
The catalog-wide Main-Hub opportunity scan remains a complete paginated regional
read, but its page bodies are removed from the ESI memory cache after the durable
demand observation and compact best-buy/best-sell projection have succeeded. The
large order-ID demand ledger is loaded only for that observation and released
again after the atomic write. Its V2 persistence stores each exact-hub baseline
as a compact `[order ID, type ID, location ID, side, remaining volume]` row and
still decodes the verbose V1 representation. Observation walks the incoming
orders once, compares and builds the successor baseline together, and checks
cooperative cancellation every 2,048 orders before atomically publishing the
result. Catalog analysis runs outside the main actor and checks cancellation
while walking definitions. The production tree does not
retain or reuse that catalog-wide book: it requests complete depth only for the
types required by the selected tree. Automatic Main-Hub scans are always
enabled at app start (owner decision 2026-10-20); the former persisted consent
keys are no longer read, and a Dashboard pause lasts only for the current run.
Manual refresh remains available. Interactive
Planner calculations cancel scheduled or running automatic Main-Hub and Public
Contracts work, preserve their last complete or resumable state, and restore
their schedules only after the last overlapping calculation finishes. Explicit
manual scans are not cancelled by this automatic-work rule.

Planner input discovery is a separate bounded preparation boundary. One pass
parses the input, resolves each repeated root name once, traverses each shared
production type once, and derives the market-type set, requested products and
self-jumping Capitals together. `RuntimeState` retains at most one such
preparation plus its memoized SDE catalog. Reuse requires an exact match of SDE
build, SDE content hash, input text, compressed-ore option and jump-fuel option.
The prepared request/type mapping is passed into calculation rather than being
parsed and resolved again. Any key change replaces the entry; market, asset,
fee, route and other mutable snapshots remain fresh inputs to every plan and
are not part of this cache.
There is no parallel structure, service-module, facility-tax or rig
implementation in the UI.

Character capability snapshots are optionally persisted with each local
character record. The SDE-backed Science skill list and those freshness-aware
snapshots feed `InventionReadinessMatrix`; unavailable skill sheets remain
unknown. See `INVENTION_SKILL_MATRIX.md`.

The standalone Industry Jobs table is removed from the navigation and build
target. Per-character sourced job snapshots remain part of character
synchronization. Dashboard owns their capacity, activity, ready and upcoming
projections; Net Worth consumes active Manufacturing and Reaction jobs for its
explicitly estimated in-production component. Missing, stale, partial or
forbidden job sources retain their prior source-state semantics and never
become an empty authoritative list.

`ManufacturingOpportunityTopRanking.rank` projects a saved opportunity snapshot
with fixed standard assumptions:

- no Warehouse stock,
- installation, sales tax and broker fee included,
- no Blueprint allocation,
- the snapshot's `saleRoute(for:)`.

It returns the highest daily profit potentials, with a stable type-ID tie
order. `DashboardTopOpportunitiesPanel` runs it off the main actor for the Main,
Home and Coalition snapshots. It hands Build through
`DashboardNavigationRequest.plannerLaunch` and performs no network work.

`DashboardInProgressIndustryProjector.projectJobs` supplies the same per-job
material values to the open-job ranking and the in-production aggregate.
`MaterialPurchaseRecommendationProjector` selects one fresh configured purchase
market per material. `RuntimeState` prepares these recommendations once per
analysis snapshot for Dashboard, the purchase views and the mineral ticker.
`SharedAnalysisRefresh` joins identical in-flight refreshes and serializes changed
contexts; configuration identity and the five-minute reuse window prevent
screen-local duplicate analyses. Dashboard consumes the shared reaction snapshot
with its original runs, market and logistics destination. Navigation passes a
one-use negative-reaction filter without introducing persisted routing state.

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

`DashboardWealthProjector` also composes the Net Worth history contract. Each
character contributes sourced wallet, personal assets, open sell orders, the
escrow value actually returned by ESI for open buy orders, own active personal
item/auction contracts and own in-progress personal courier contracts. Asset
and included contract-item reference prices use ESI average price with adjusted
price as an explicit fallback; Blueprint Copies are excluded because their runs
and ME/TE value cannot be derived from these rows. Courier value is explicitly
the contract collateral estimate because ESI does not expose the cargo value.
The reference-price route is public and therefore has no SSO-scope remedy when
ESI omits a type. New history points retain the unresolved SDE type names for a
clickable diagnosis; the value remains unknown rather than becoming zero.
Accessible Corporation asset and wallet snapshots are deduplicated by
Corporation ID before they are added. Assets require Director; wallets require
Accountant or Junior Accountant. Missing scopes, roles, item pages, types,
orders, escrow or collateral keep the snapshot partial. Per-Corporation
coverage records how many unique Corporations contributed a value and how many
failed the required role check. Asset location-name or division-label failures
do not downgrade the valuation when the complete asset inventory is present.
`NetWorthView` persists
at most one point per calendar day (365 points maximum), renders combined
component and per-character histories, and owns manual replacement plus
confirmed point deletion.

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
authorization, wallet/capability/personal and Corporation asset snapshots, and
ESI metadata. Production
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

`EVEOnlineStatusClient` reads CCP's public Statuspage summary through a bounded
10-second, 1-MiB transport and maps Game Server, Login and ESI independently.
`RuntimeState` refreshes this snapshot after the previous check rather than
bursting requests. SwiftUI presents one global service banner and uses the
official status as the primary source. A deterministic 11:00–11:20 UTC window
is only a fallback for the documented daily Tranquility restart; it never
asserts that SSO or ESI failed. The character authorization progress changes
from browser callback to SSO verification and then ESI synchronization, and a
completed batch reports how many characters retained incomplete or unavailable
domain states instead of calling every result complete.

Each character row also presents an exclusive scope disclosure. Expanding one
character collapses the previous selection and renders only that character's
sorted, granted scopes from the token-free `AuthorizationSnapshot`, together
with the authorization time. No credential material is exposed to SwiftUI.

The Industry Settings page and the top-level Logistics page edit separate local
drafts of one saved `ProductionBasis` baseline and publish only dirty state and
save/discard commands to the navigation composition. Leaving either page while
dirty is blocked by a three-way confirmation: save and continue, discard and
continue, or cancel. A failed save keeps the user on the current page. Logistics
route typing stays in its compact local draft and publishes the accepted basis
only after persistence succeeds.

The same basis binds market-order selling to one connected trader character.
The Character boundary supplies sourced skills and unmodified standings; the
Industry configuration derives the Jita IV-4 sales tax and NPC broker fee
under rule `ccp-market-fees-2026-08-13`. SwiftUI displays that immutable
evidence and requests a character capability refresh through `RuntimeState`;
it does not call ESI or calculate fees itself. Missing or forbidden source
data produces unavailable fees, so the Market boundary cannot create a listed
sale quote with an invented zero rate.

The top-level Logistics workspace owns presentation and editing of the
`LogisticsConfiguration`, which stores only owner decisions:
enabled inbound routing, route labels and the current ISK/m³ rate. Industry
always evaluates the finished-product return route for Main-Hub sale scenarios
when logistics is enabled and composes both directions with a frozen public-ESI packaged-volume snapshot and complete Main-Hub sell-depth
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

The Reactions navigation entry is a separate catalog-wide comparison, not a
mutable production plan. `SQLiteStaticCatalog.reactionDefinitions()` returns
one complete, published definition per SDE reaction formula. Runtime composes
those definitions with a location-bound `MarketOrderSnapshot`, adjusted prices
and, when fully verified, the Profile reaction facility and system index.
`ReactionProfitabilityAnalyzer` prices every input from sell depth, the output
replacement value from sell depth and immediate disposal from buy depth for the
selected batch. Runtime also supplies the selected market location, configured
reaction destination and packaged public-ESI volumes. The shared
`LogisticsCostCalculator` applies the Profile m³ rate, 0.5% replacement
collateral floor, whole-item contract splitting and million-ISK rounding to
both alternatives. Reaction cost is input depth plus inbound input logistics
plus installation; direct-purchase cost is output depth plus inbound output
logistics. Positive value creation is the complete direct-purchase total saved
by making rather than buying the output. Immediate-sale spread remains a
separate gross observation before character-specific sales tax and outbound
finished-product logistics. An identical exact origin/destination has zero
transport; explicitly disabled logistics contributes zero with a visible
status. Missing depth, packaged volume, collateral, enabled tariff data or an
unverified facility stays unavailable. Without a verified facility the UI
labels a material-only SDE baseline and does not treat installation, structure,
rig or clone costs as zero. Jita is the persisted default, while Amarr,
Dodixie, Rens and Hek use their own region and station order scopes.

The Moon and mineral purchase analyses are separate read-only market
comparisons backed by one shared domain and presentation contract. Their item
scopes are the complete published SDE groups `Moon Materials` and `Mineral`;
neither screen falls back to a hard-coded type list. Their market scope is the
deduplicated persisted Main, Home and Coalition role assignments plus every
explicit comparison market. There is no independent fixed-market list or Jita
fallback column. NPC role locations filter public
regional sell orders to the exact configured station. Player Structure role
orders do not come from the public regional endpoint: Runtime obtains an
in-memory lease for a connected character carrying
`esi-markets.structure_markets.v1`, then Market requests the paginated
`/markets/structures/{structure_id}/` order book once and filters the requested
material type IDs locally. The Profile trader for that Trading Location is
preferred when eligible; another eligible character may supply the lease when
the preferred character cannot. Authorization, missing scope, ACL denial,
destroyed/replaced structure and rate-limit failures remain distinct source
diagnostics. Only a successful empty structure response becomes a no-orders
state. For each material
and location, the lowest valid sell price is the band basis, the displayed
limit is exactly 110% of that price, and availability is the sum of remaining
sell-order volume priced at or below the limit. Each location remains an
independent `Sourced<MarketOrderSnapshot>`: missing, forbidden, partial and
stale markets remain visible and never become zero price or zero inventory.
Each analysis header derives Main, Home, Coalition and comparison badges from
the saved Profile roles; no location has a hard-coded role.
An unresolved legacy Home Hub is repaired directly beneath the Home-Hub picker:
the ESI structure search is prefilled with the system name and replaces the
selected configuration in place. Its configuration UUID, Home-Hub role, trader
and fee evidence survive; an already configured duplicate of the selected ESI
structure is merged away.
Among fresh locations with a valid sell price, distinct lowest prices receive
dense ranks one through three. Equal prices share a rank; stale or unavailable
observations are not ranked. UI maps rank one to green, rank two to yellow and
rank three to red, and always includes the textual rank so color is not the
only signal.
NPC material requests ask the regional endpoint for sell orders only and retain the
per-type query so a refresh never downloads an entire regional order book. The
Forge public order book measured 404 pages on 2026-08-02, making that apparent
bulk shortcut materially slower. In addition to the shared ESI response cache
and bounded request concurrency, Runtime reuses each completed analysis
snapshot during ESI's five-minute market cache window. Moon and mineral states,
errors and refresh identities remain separate. A changed SDE build, Profile
market resolution, selected trader, client ID or authorization identity
invalidates the affected reuse immediately.

The cross-region Market Browser implementation remains a separate read-only
market snapshot, but it is no longer exposed as a navigation area. The active
Planner, Main-Hub opportunity and material-analysis workflows keep using their
own shared trade-hub market services; removing the menu entry does not remove
those requests or calculations. For
one published SDE item it requests public sell and buy orders from every ESI
region with bounded concurrency; a failed or forbidden region is recorded as a
failure and does not erase orders returned by other regions. Location and solar
system labels come from the shared universe-name resolver. Security status is
loaded from the public system-detail endpoint with at most eight concurrent
requests and mapped to Highsec, Lowsec or Nullsec; unresolved values remain an
explicit separate filter state. Each order's location row shows the EVE-client
display value immediately before the station or structure name. It deliberately
omits the separately resolved system name because EVE station and structure
names already contain their system context. The value applies CCP's one-decimal
rounding rule, including the `0.0 < x < 0.05` exception, and the eleven official
security-status colors; the visible number remains the non-color accessibility
signal. Player-structure IDs cannot be sent to the
32-bit universe-name endpoint. The Browser therefore tries the existing
connected character authorizations with `esi-universe.read_structures.v1`
until a structure name is resolved or every eligible character reports it
inaccessible. Orders remain visible when authorization, scope or ACL access is
missing. The Market Browser does not calculate navigation routes or jump
counts, and a player structure's docking ACL cannot be inferred from its
visible public order.

The Browser retains each regional response's ESI `Last-Modified` value as a
dataset timestamp. It is not presented as a guaranteed per-order modification
time. The `eve-tycoon-five-percent-2026-08-01` summary policy follows the
[EVE Tycoon API contract](https://evetycoon.com/docs): buy orders below 10% of
the best buy and sell orders above ten times the best sell are excluded, then
the best buy-side and sell-side 5% of remaining volume are averaged with exact
partial-order weighting. Average margin is the gross difference divided by
the 5% average buy price. Sell and buy volumes are quantities in the remaining
active orders, not historical completed-sale volume; historical market
activity requires the separate region-history contract.

Public Contracts is an independent, local search index for active public ESI
contracts. It discovers the current region set through `/universe/regions/`,
loads every reported page from `/contracts/public/{region_id}/`, and then loads
every reported item page for each newly observed contract through
`/contracts/public/items/{contract_id}/`. No SSO scope is required. A separate
WAL-mode SQLite database retains region eligibility, contracts, item-detail
completion and failures so a cancelled or interrupted initial import resumes
without repeating completed detail requests. Regional contracts become active
only after all pages agree on `X-Pages` and `Last-Modified`; an inconsistent or
duplicate page set leaves the previous regional snapshot intact.
When every conditional page response is `304 Not Modified`, the cached page
count remains part of the response envelope even if the 304 omits `X-Pages`,
and the store advances only the region freshness metadata. A normal successful
response still compares every factual contract field, but an identical row is
not updated merely to change its observation time. This avoids rebuilding the
WAL for an unchanged all-region refresh. Full region activation checks task
cancellation every 128 incoming, existing and persisted rows; cancellation
rolls back the open region transaction before the next region is attempted.

Public-contract response fields follow the current OpenAPI requiredness.
Optional `for_corporation` remains `nil`/unknown when CCP omits it. Existing
stores migrate that column from `NOT NULL` to nullable transactionally while
retaining every contract and item. Three schema-decoding failures within one
run stop the importer with its partial data preserved instead of repeating the
same incompatible request across every region.

Public item rows also persist the official Blueprint copy flag, remaining
runs, material efficiency and time efficiency. A versioned one-time migration
requeues only previously `ready` contracts that already contain recognized
Blueprint items and records a completion marker in the same transaction.
Existing item rows remain available until the normal bounded detail importer
atomically replaces that contract's items; the migration therefore does not
turn missing legacy Blueprint facts into zero or discard searchable data.

Every app start re-enables persisted automatic continuation (owner decision
2026-10-20); a manual stop pauses it until the next start.
While the app remains open, unfinished work resumes after a persisted safety
window; after relaunch it resumes no sooner than 15 seconds after startup.
First-import completion is persisted independently from current freshness: a
region is complete once it has a successful snapshot, and a later failed
refresh does not erase that history. Regions without any successful snapshot,
including temporarily unavailable regions, remain initial-import work and run
when eligible or at their earliest persisted retry time. Only after every
region has succeeded once and no item work remains does the six-hour refresh
policy apply. Manual stop cancels the current or scheduled task and persists
automatic updates as disabled. This is in-process scheduling only: a quit app
has no launch agent and sends no ESI requests.

Each run processes regions sequentially with a minimum 250 ms spacing. Item
details use at most two concurrent requests, one globally paced start every
500 ms and batches of at most 100 contracts. Responses are persisted before
their one-shot ESI cache bodies are released, so the speedup does not create an
unbounded memory queue. Contracts that expire before their detail turn are
removed locally, while known detail-free Courier and Loan contracts retain an
explicit `not_applicable` item state instead of spending ESI error budget or
being represented as an empty successful detail response. Cache expiry
controls the earliest next regional request, while `Retry-After`, ESI
error-limit reset headers and current rate-limit headers can extend waits. The
indexer pauses before the error budget falls below its safety floor, stops the
run on a surfaced 420/429 response, and backs off unavailable regions without
turning them into empty results. A Contract-index safety wait suspends only
this import task; other app ESI commands remain available, although a shared
CCP service or rate-limit incident can affect them independently. These guards
reduce load but cannot guarantee that CCP will never change limits or block a
client; live response headers and future published ESI policy remain
authoritative.

Contract item names, groups and categories are joined locally from the active
SDE. Search and offered/requested filters therefore make `Ark` distinguishable
from `Arkonor` by selecting `Ship` and `Jump Freighter`. Missing SDE metadata or
incomplete ESI work remains visible as incomplete indexing rather than an
invented empty contract set. Industry resolves Blueprint offers in bounded bulk
queries over exact `type_id` values. An empty result can prove that no offer was
found only when every region is fresh, every region has completed its initial
import, and no region or item-detail failure is pending.

Contract start and end locations are registered with the same local index.
NPC-station IDs are resolved in bounded batches through `/universe/names` and
the stable names are retained locally; an unresolved public name is retried no
sooner than six hours later. Player-structure IDs are never sent to that
32-bit-compatible name endpoint. Without an authorized structure-detail
resolver their names remain explicitly unavailable instead of becoming an
empty string, a numeric label or an invented station. The Contracts UI presents
Region, Location, SDE category/group, contract type, expiry and amount in that
order. Results use a two-column card grid, omit the internal Contract ID, and
preserve a single column when the window is too narrow. The ESI safety
and first-import explanations use the shared full-row disclosure control and
persist their collapsed state. A critical region-error count remains visible
when those disclosures are collapsed; the detailed view separates first-import
completion, currently fresh regions, failures and the earliest failed-region
retry.

Reaction formulas are not assigned one invented global run maximum. The
30-day industry-job window is combined with each formula's active SDE duration
and the accepted facility time multiplier to derive `maximumRunsPerJob`.
The lower bound is one so a single run remains legal when it already exceeds
30 days.
Economic batches above that formula-specific value keep their requested total
but expose `requiredJobCount`; the shared input range begins with the current
neutral SDE maximum and is replaced by the analyzed catalog maximum. Sorting is
owned by the immutable reaction result contract, including lowest value
creation first with unavailable values last.

Market locations are owned by one persisted Market Settings aggregate rather
than Profile UI. Each exact ESI location can carry Main, Home and Coalition
roles simultaneously. Unassigned saved locations are role candidates, not
markets, and therefore do not produce order requests or comparison columns.
Main requires a resolved NPC station with station, system and region IDs.
Coalition requires a resolved Player Structure and never implies market ACL
success merely from its label. Home may equal Main; normalization then binds
the logistics destination to the same exact location so no hub-to-home leg is
created. Planner consumes Main, Moon and mineral purchase analyses consume the
selected role set with identical locations deduplicated, and Reactions consumes
one selected role hub at a time. Failed
private structure markets remain unavailable and are never replaced by public
regional orders.

The optional Home-to-Coalition transport is a distinct jump-logistics boundary,
not another courier tariff. Runtime resolves the configured hubs to exact solar
systems, selects fresh synchronized navigation skills and obtains an immutable
DOTLAN route for the configured cargo hull plus one hull-specific route for
every requested self-propelled Capital product. Jump Freighter, Carrier,
Dreadnought, Force Auxiliary, Supercarrier, Titan and Capital Industrial each
own an independent assignment to automatic routing or a persisted fixed-route
profile. Profiles may be shared deliberately and retain ordered ESI-resolved
systems plus optional owner-entered cyno-location labels. Fixed profiles are
not path hints: Runtime requests every consecutive pair separately and accepts
only one matching direct DOTLAN leg for the actual hull and pilot. The retained
assessment owns profile identity, waypoints and all segment URLs. An invalid
fixed assignment remains unavailable and never falls back to automatic routing.
Runtime also loads the four exact
Main-Hub isotope order books. Industry removes those Capitals before cargo
allocation, multiplies their own route fuel by completed hull quantity, and
performs the remaining deterministic flight and cost calculation without
starting network work itself. UI only edits the hull, pilot policy and usable
cargo assumption and renders the retained route, price, cargo and Capital-jump
evidence. A missing system, pilot, isotope quote, packaged volume or
unrecognized external response is propagated as unavailable; a Capital cannot
fall back to cargo, 0 ISK or the generic courier route. Historical snapshots
retain the evidence available at calculation time and do not contact DOTLAN
when reopened.

SwiftUI disclosures use `FullWidthDisclosureButton` and
`FullWidthDisclosure`. The entire visible label row is the semantic button and
reports expanded/collapsed state; the chevron is only a visual indicator.
Embedded actions such as sync or disconnect remain separate controls rather
than nested buttons.

The SwiftUI theme uses the exact semantic values from `SPEC_DESIGN.md`: base
`#0B0F1A`, surface `#131A2A`, elevated `#1B2438`, border `#263149`, cyan accent
`#35C7E8`, amber highlight `#F5B942` and the specified status colors. Layout
spacing, card and badge radii, sidebar widths and input heights are centralized
beside the colors; ISK values use monospaced digits and the amber highlight.

## Version 1 boundaries

- Personal characters plus opt-in, read-only Corporation asset hangars through
  an explicitly authorized Director; other Corporation domains remain outside
  this boundary.
- Personal wallet balances and their cross-character sum; no corporation
  wallet, journal or transaction presentation.
- Manufacturing and reactions; invention configuration is visible and stored,
  but invention planning is unsupported.
- Planner valuation and purchases use the Market Settings Main Hub. Jita,
  Amarr, Rens and Hek are prepared choices, and additional resolved NPC
  stations can be selected. Reactions selects one location from the same
  configured market set.
- Local storage only; no cloud sync.
- No Corporation wallet/jobs/orders, transport optimization, multi-hub
  optimization or job installation. Main, Home and Coalition opportunity lists
  and the Planner target market compare hubs side by side but do not optimize
  a split across them.

## Main Hub opportunity scan

The opportunity scan is a read-only comparison, not a production plan. Market
owns one cancellable snapshot of the configured NPC Main Hub. It is started
manually or by the automatic schedule released after the startup load; Home
and Coalition scans follow in the same run. Industry joins both complete published SDE manufacturing definitions and
complete reaction definitions to that immutable snapshot. Manufacturing rows
use the per-category selected manufacturing facility. Reaction rows reuse the
authoritative Reactions quantity, per-job rounding, duration and EIV
installation calculation with the separately configured reaction facility and
reaction system index. UI owns filters, favorites, selection and scenario
input; it does not fetch ESI or calculate prices itself.

`OpportunityHubRole` (`main`, `home`, `coalition`) parameterizes the scan.
Materials are always quoted against the Main-Hub market. A Home or Coalition
role additionally requires its own exact `saleMarket`, which supplies product
orders, supply/demand coverage and the market source; a missing or mismatched
sale market throws `inconsistentMarketLocation`. Main-Hub snapshots leave the
new `hubRole`/`saleHub` fields `nil`, so their encoded files keep the
historical keys. `ManufacturingOpportunitySaleRoute` selects the logistics:

- `mainHubRoundTrip` keeps the historical Main → production → Main round trip.
- `homeHub` drops the return leg and adds a production → Home leg only when the
  production location differs.
- `coalitionHub` also adds an injected Home → Coalition amount; `nil` makes the
  logistics unavailable.

Role files are `market/<role>-hub-demand.json` and
`market/<role>-hub-opportunities.json`; the Main-Hub paths are unchanged.
The Home-Hub scan is a tail step of `performManufacturingOpportunityAnalysis`.
It reuses the loaded definitions, names, volumes, adjusted prices, facility
context and the full Main-Hub material market, so it inherits scheduling,
priority and cancellation.

- `HomeHubOpportunityScanTarget` resolves the configured Home Hub to an NPC
  station, a Player Structure, `sharesMainHub` (no second scan), `notConfigured`
  or `unresolved`.
- Structure markets use the authorizations most recently handed over through
  `rememberMarketAuthorizations` and the shared structure-lease selection.
- Home-Hub failures map through the material-market failure classification.
  They retain the last snapshot as stale and never alter the Main-Hub snapshot.

Secondary hubs share one implementation: `secondaryHubOpportunities`
(`SecondaryHubOpportunityState` per role), per-role demand and snapshot stores,
`HubOpportunityScanTarget` (also `sharesHomeHub` for a Coalition Hub equal to
the Home Hub) and `analyzeSecondaryHubOpportunities(role:context:)`. The
Main-Hub scan runs Home, then Coalition.

For Coalition the runtime freezes an `OpportunityCoalitionTransportBasis` in
the snapshot:

- **Jump Freighter:** the DOTLAN cargo route via
  `plannerJumpFreighterRouteLoad`, plus the Main-Hub isotope order books.
- **Courier:** the Profile courier rate and contract limit.
- **Unavailable:** carries a reason.

`ManufacturingOpportunitySnapshot.saleRoute(for:)` derives each row's onward
cost from that basis, so run edits re-price the transport. Self-jumping capitals
stay unavailable: blocked without jump logistics, and left to the Planner with
it.

`ManufacturingOpportunitiesView(hubRole:)` serves all three navigation entries.
`ManufacturingOpportunityContractContext` (universe-wide
`PublicContractReferenceSnapshot`, the hub's confirmed
`publicContractFeeRate`) enters
`ManufacturingOpportunityScenarioProjector.costs(…, contract:)`. The projector
fills `ManufacturingOpportunityCostProjection.contract`, which carries price,
revenue, fee, profit, ROI and provisional/before-fee flags.
`RuntimeState.loadOpportunityContractReferences` reads only the local index in
bounded batches, reuses an identical type set for five minutes and never
contacts ESI. Sort columns `.contractPrice` and `.contractProfit` use the typed
values, with unavailable values last.
Coalition rows project logistics through `saleRoute(for:)`.
`ManufacturingOpportunityLogisticsProjection.onwardTransportCost` and
`ManufacturingOpportunityCostProjection.onwardTransportCost` expose the
Home → Coalition share, which the sortable column `.onwardTransport` uses.

- **Data:** For `home` it reads the Home-Hub snapshot, demand and progress
  instead of the Main-Hub values.
- **Logistics:** It projects logistics through
  `ManufacturingOpportunitySnapshot.defaultSaleRoute`.
- **Persisted filters:** It re-initializes the persisted filter `@AppStorage`
  keys through `OpportunityHubRole.storageKey`, so Main-Hub keys stay unchanged.
- **Texts:** `OpportunityHubText` renames only sale-side wording and the sale
  warning codes. Material purchases remain Main-Hub texts.
- **Planner handoff:** `PlannerLaunchRequest.targetMarket` carries the selected
  hub to the Planner, which ignores it until P10.

Every complete supported definition remains a candidate even when the exact
Main Hub has no active product order. Sell and buy coverage are recorded
separately; missing sell coverage keeps revenue and every dependent metric
unavailable with a blocking reason instead of removing the row. The snapshot
carries separate complete manufacturing and reaction-definition counts, all
active Main-Hub order types and the resulting candidates. It is neither the
complete SDE item count nor completed-sale history.

The persisted row activity is optional for backward compatibility: a missing
value denotes a legacy manufacturing-only scan. Current reaction rows are
classified by their SDE activity, so Molecular-Forged and other reaction
materials enter the Reactions product family regardless of category/group
wording. Reactions expose Runs but no ME/TE, use reaction rounding during local
run projection and never receive the optional manufacturing Blueprint
allocation. Missing ME/TE sort values retain deterministic unavailable-value
ordering.

The workspace follows a three-level calculator layout: one default-expanded
`Filters and scenario` disclosure above the result grid, the dense opportunity
table across the complete
available width in the center, and one full-width lower workbench split into
responsive Warehouse and Main-Hub/Shopping/Cost columns. The disclosure uses
an adaptive, vertically bounded card grid for ownership, Blueprints, products,
production class, catalog, result, Runs and costs/budget. Each card exposes a
localized hover explanation, and economic table headings expose their factual
source and formula. It replaces the
former Simple Profile, Cost Sheet and Advanced Filters tabs without changing
the navigation entry. The target quantity is persisted separately from the
legacy run setting. Older snapshots retain their decoded run value for
compatibility, while every new manual or automatic Main-Hub analysis clears the
legacy override and derives whole runs per product from target quantity and SDE
output per run.
Product-family
filters use category and group metadata already carried by the active SDE
definition. Production-class filters consume the SDE type's `metaGroupID` and
`techLevel`: Tech I, Tech II, Tech III, Faction, Storyline and
other/unclassified are multi-select values. They are OR-combined within their
filter group and AND-combined with the independently multi-selected product
families such as Ships, Modules or Components. Saved scans or legacy catalog
adapters without these fields remain explicitly unclassified; the UI does not
derive a production class from an item name. Size stays visibly unavailable
until the catalog exposes authoritative metadata.
Personal Blueprint ownership comes from the selected character's Blueprint
snapshot and Corporation ownership from the selected character's Corporation
asset snapshot. `Not owned` is available only when the relevant ownership
evidence is complete; otherwise the item remains explicitly `Unknown`.
Warehouse and the lower tab strip remain visible before a candidate is
selected. In that state Warehouse summarizes the assigned production
locations and their factual snapshot coverage; the selected lower tab keeps an
explicit item-selection placeholder. Selecting a candidate replaces those
summaries with its material, market, shopping and cost rows. Short result lists
use a top-leading scroll anchor, so unused space remains below the table.

The search field is bound directly to the result filter so input and visible
results cannot diverge. The domain search policy normalizes the query once per
filter pass and performs no name, group or category matching below three
trimmed characters. Active product-family and ownership filters are
session-local and start with every supported state enabled, so a previous
narrow view cannot hide the restored catalog on the next visit. Favorites and
scenario-cost settings remain persisted. Each filter pass decodes favorites and
ownership evidence once, projects each surviving row's Cost Sheet once, and
sorts those cached projections. The toolbar no
longer performs a second duplicate filter-and-sort pass merely to display a
count. Search and filtering remain local operations over the immutable
analysis snapshot and do not start ESI requests.

The optional material-purchase ceiling is a local view over already prepared
candidate procurement values and is intentionally excluded from the expensive
candidate-projection identity. Changing only this ceiling therefore filters the
cached list without repeating ownership decoding, logistics, fees or sorting.
Its value is the wallet cash for material shortfalls after factual Warehouse,
protected-stock and active-reservation allocation; unknown coverage becomes an
explicit exclusion while the limit is active.

The optional minimum-average-demand quick filter is likewise a local view over
the prepared rows. Zero disables it and preserves unavailable averages in the
result. A positive threshold accepts only a known multi-day average at or above
that value; unavailable history never becomes zero.

The scenario owns a positive per-product Blueprint-run count capped by the
existing one-million-run UI limit. `produced quantity = runs × SDE output per
run`; material, installation, duration, inbound and outbound logistics, listed
revenue and total scenario profit all use that complete batch. A run override
reprojects only the affected saved candidate from captured weighted unit prices
and does not rerun the catalog-wide scan. The on-demand production tree has no
second quantity control: it consumes the same runs and produced quantity and
reloads only that product after a run change.

Every successful complete opportunity scan is encoded in a versioned envelope
and atomically stored as the last-known-good list. Runtime loads that immutable
snapshot before an optional refresh, preserving its captured time, SDE and
market provenance and all candidate rows. An unreadable or unsupported saved
file remains visible as an error and is never silently replaced; the current
scan may remain visible in memory, but saving is reported as unavailable until
the stored file can be reviewed.

The Cost Sheet is an immutable scenario projection over the base opportunity.
Material replacement value remains the cost basis; installation cost, sales
tax and broker fee can be included separately, and Blueprint allocation per run
can be entered explicitly. Main-Hub opportunity profit always requires the
complete configured route: purchase at the Main Hub, inbound shortfall to the
exact Home Hub, production, outbound finished product to the Main Hub, then
listed sale with the configured tax and broker fee. Exact equal Main/Home
identities contribute zero logistics. A different hub with disabled or
incomplete logistics makes profit unavailable instead of silently contributing
zero. The projection never mutates the underlying market snapshot or a saved
production plan.
In the displayed formula, total cost is material replacement value plus
installation, optional Blueprint allocation and required Profile logistics.
Gross revenue is the lowest active exact-Main-Hub sell price times complete
scenario output. Sales tax and broker fee use the configured trader rates and
reduce gross revenue; profit is that net revenue minus total cost. Daily profit
potential is profit per produced unit times the lower of complete batch output
and current observed daily demand, so it cannot exceed this batch's profit.

Warehouse and Shopping are first-level procurement projections, not a
recursive build graph. Only factual stock at the exact facilities currently
assigned to manufacturing, reactions, invention, copying and research is
eligible. The combined scope may span several systems and locations. Protected stock targets and active-plan reservations
are subtracted before allocation. Consumed stock retains its proportional
full-demand Main-Hub replacement value, while the Shopping List reports only
the cash required for the remaining quantity. A missing or partial Warehouse
snapshot blocks stock allocation and Shopping output rather than inventing an
empty Warehouse.

`Daily demand` is a persisted conservative lower-bound rate for the exact Main
Hub, not regional history and not an assertion that all completed trades are
known. Ledger schema v4 also retains the newest valid rate snapshot for each of
the latest 30 UTC days. The UI derives the exact previous UTC day's rate, the
current-versus-previous approximate percentage and a rounded average over known
days only. A missing day or type is omitted rather than converted to zero, and
a Main-Hub scope change clears the history. Existing v1-v3 ledgers migrate
without inventing past observations; history starts accumulating with
subsequent valid updates.

The first order-book snapshot establishes a baseline. Each later
snapshot compares the same order ID, type, side and location; only decreases on
surviving orders are counted. New, disappeared, expired or cancelled orders are
not guessed. Coverage is tracked per product type, so a globally successful
comparison cannot turn an unobserved type into zero demand. Intervals are
retained in a rolling 24-hour window across UTC midnight and normalized to one
day only after at least 30 minutes. A hub change, non-forward timestamp or gap
over 24 hours establishes a new baseline. Before a type has two suitable
snapshots and at least one comparable order, its daily demand and daily profit
potential remain unavailable.

The daily dictionaries remain only in the dedicated demand ledger and runtime
summary. Opportunity rows freeze current, previous-day, average, recorded-day
count and change percentage; the saved opportunity snapshot deliberately drops
the full history to avoid duplicating up to 30 catalog-wide dictionaries in
memory and on disk.

The persisted catalog scan keeps a neutral 0/0 research baseline because no
concrete owned or acquired Blueprint has yet been selected. The visible table
then owns session-only Runs, ME and TE as a marked screening hypothesis for
every row. No tech-level-only ME cap is applied; factual source provenance owns
the accepted values and manual assumptions use ME 0...10 and TE 0...20. New
snapshots persist the SDE base
material quantities plus facility material/time multipliers, so the item-only
projection uses the same rounding functions as `IndustryPlanner`. Older
snapshots remain decodable; changing ME without those inputs emits an explicit
approximation warning until the scan is refreshed. Runs scale output, material
rounding, installation, production duration, both transport legs and sale
revenue together. The table derives `daily profit potential` as exact
scenario profit per produced unit multiplied by `min(produced quantity,
observed daily demand)`. Demand at or above the selected batch therefore yields
the batch profit; lower demand reduces the value proportionally. This remains a
comparison metric, not a promise that every sale is realized; unavailable
demand remains unavailable and sorts after factual values.

The Main-Hub workspace formats displayed integers and ISK values with the
selected app locale. German therefore uses a point grouping separator, also
while editing Runs, Blueprint allocation and purchase-budget fields. Parsing
removes only the selected locale's grouping separator, so grouped input remains
the same factual value.

Refreshing stays cancellable. The automatic schedule (always enabled since
2026-10-20, pausable for the current run) and the optional `Check when opened`
policy start at most one scan every six hours from the last observation; this is
not a daemon or continuous poll. The base calculation reports contribution before Blueprint allocation and
hauling; the Cost Sheet labels the resulting scenario values and can include
both explicit amounts. Missing Main-Hub depth, adjusted price, selected-facility
index/context, trader fees or enabled Cost-Sheet amounts propagates as
unavailable.

The opportunities workspace owns no recursive production tree, Warehouse
workbench, depth tab, Shopping List or Cost-details tab. Clicking the product
name copies it through the shared EVE-name control. **Build** transfers the
visible product, output quantity, runs, ME and TE directly into the established
Planner. Because the compact opportunities table has no concrete Blueprint
source picker, it does not fabricate a source identity or a
`BlueprintSupplyPlan`; the Planner resolves and validates that supply. Workflows
that already selected a concrete source continue to transfer its complete
supply plan and snapshot identities without silently replacing its efficiency.
Consequently an unresolved opportunity row and a Planner sale card are
like-for-like only when batch, efficiency, material sources, Blueprint costs,
market snapshot/depth and route are the same. The screen states that boundary
instead of presenting a captured direct-recipe screening result as the
authoritative recursive plan.

Opportunity logistics uses `productionLocationName` as the actual production
endpoint. `homeTradeHub` remains routing context and can no longer short-circuit
costs merely because it equals the Main Hub while the explicit production name
differs. Only an actual production-name/Main-Hub match yields zero round-trip
cost; otherwise enabled complete logistics is required.

Each producible node carries its SDE Blueprint type, requested quantity,
rounded produced quantity, runs, activity, ME/TE and assigned facility.
Retained fresh, partial or stale personal owned-instance evidence distinguishes
BPO and BPC, runs and exact location;
Corporation asset evidence can prove only that an item type is present and
therefore remains `unknown` kind. Manufacturing, reactions, copying, invention
and ME/TE research inventory are checked against their separately assigned
exact locations. A Blueprint at a research-only location is reported there but
is not treated as immediately usable for production. The local public-contract
index stores the official copy flag, remaining runs, ME and TE. A price becomes
attributable only for an active item-exchange Contract at the exact Main Hub
with a positive price, exactly one offered Blueprint line, no requested line,
quantity one and complete Blueprint details. Several retained
fresh/partial/stale owned BPCs may jointly cover the required runs regardless
of equal or different ME/TE, but each owned item remains a separate
manufacturing job with its own allocation, rounding and remaining runs. The UI
retains their character names, copy count, available runs and source state. A
source outside the manufacturing facility creates an explicit transfer;
unresolved endpoints block the plan. If owned
coverage is insufficient, a bounded deterministic selector may combine several
attributable BPC Contracts until their known runs cover the node, charging each
selected Contract's full price as acquisition cost. A BPO Contract and a
factual Main-Hub BPO sell order remain distinct capital purchases whose full
price is shown separately; only an explicitly entered batch allocation enters
profit. Market orders never create BPC sources. Bundles, zero prices and
legacy rows without Blueprint details remain visible but excluded. Incomplete,
stale or failed Contract coverage yields `unresolved`, never a false
`unavailable` recommendation. Owned BPC, owned BPO, copying, invention and
Loyalty Store selections likewise require an explicit cost. With strict tree
costing, one unresolved produced Blueprint makes total production cost and
profit unavailable rather than artificially free.

The Planner's BPO/BPC panel is persistently collapsible and groups produced
steps into reactions, components and remaining SDE categories. A group source
operation updates every compatible step and reports how many incompatible
steps stayed unchanged; each row remains independently selectable. Exact-site
owned BPO/BPC qualities are exposed as concrete ME/TE variants. Selecting one
locks its factual ME/TE into the per-product `productionEfficiencies` map used
by both the preflight tree and final `RuntimeState.calculate`. A BPC contract
with common known ME/TE behaves the same way. Manual external BPC and BPO
assumptions retain bounded per-row controls of ME 0...10 and TE 0...20.
Factual owned, Contract and Science sources retain their supplied values,
including an invented T2 BPC at ME 5 after a Process Decryptor; legacy T2 BPOs
remain distinct provenance. Reactions omit ME/TE.

The Blueprint Science catalog is schema v4. Copying, ME research, TE research
and invention activities retain their SDE materials, products, duration and
required skills; decryptors retain probability, runs, ME and TE Dogma
modifiers. `BlueprintSciencePlanner` separates copies from runs per copy,
permits research only on originals, consumes one input-BPC run per invention
attempt, computes skill/decryptor probability, and separates expected cost from
the smallest whole-attempt binomial plan reaching 95% confidence. The app binds concrete Copy/Research/Invention jobs to Planner supply after
validating facility, fresh blueprint/skill sources, costs, licensed runs and persisted project identity.
Science durations are counted once and conservatively precede manufacturing; incomplete jobs remain blocked. Tech-III reverse
engineering is explicitly unsupported.

The former standalone **Recursive calculation** workspace is removed from the
navigation and build target. Its EVE-row import, force-produce projection,
special route projection and dedicated Runtime entry point are removed. The
shared recursive production graph remains owned by Planner and Main-Hub
opportunities, including factual Warehouse allocation, Blueprint source and
ME/TE selection, reactions, market depth, installation cost and logistics.

Loyalty Store item classification is a separate manually refreshed, atomically
saved snapshot. One refresh reads the public NPC-corporation list and each
public LP offer endpoint sequentially at automatic priority. Later Faction,
Tech, product and LP-BPC filter combinations are local set membership checks and
perform no ESI request. ESI supplies LP cost, ISK cost and required items but no
BPC runs, ME or TE; therefore the LP source requires an explicit complete ISK
equivalent before it affects production profit.

The selected tree forces complete logistics policy: purchased lines are grouped
by the facility that consumes them for Main-Hub-to-facility legs, and every
finished top-level output receives a facility-to-Main-Hub leg. Each leg retains
sourced public-ESI packaged volume, replacement collateral, contract splitting
and rounding. Missing ESI volume never falls back to assembled SDE `volume`.
Missing tariff, volume, collateral or complete Main-Hub depth makes logistics
and dependent totals unavailable rather than zero. Cross-facility movement of
an intermediate is not inferred when the current planner graph has no explicit
transfer edge.

The Opportunity header is no longer pinned over an expanded Build tree. The
outer opportunity table and the recursive tree each retain their own column
schema and header in the same horizontal scroll coordinate space.
