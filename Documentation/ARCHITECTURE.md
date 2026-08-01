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

The active catalog stores the package-derived `ReactionRuleProfile` unchanged;
the app does not derive a second set of dogma rules. SwiftData stores production
profiles, characters, each character's complete sourced asset snapshot, global
stock targets, each character's complete sourced blueprint snapshot, plans, a
mirror of the active SDE pointer and the latest per-character/per-domain ESI
snapshot metadata. Updating a domain replaces its metadata and prunes older
duplicates. Build-specific SDE payloads remain in SQLite.

The target also stores the normalized CCP User-Agent owner contact as an
`AppSetting`; it is not an authentication credential. Update presentation keeps
installed build, official build and the highest CCP `afterBuildNumber` schema
boundary separate. A candidate exists only when no catalog is installed or the
official build is greater than the active build. An older metadata response can
therefore never trigger a downgrade.

`AssetWarehouse` is a read-only projection over every persisted personal asset
snapshot. It resolves bounded item/container ancestry, groups the root location
first and the character owner second, retains inventory flags and snapshot
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
IDs configured in Profile and removes SDE category `Ship`; it does not infer a
facility from a solar-system name. A visible Warehouse row commits its local
minimum draft only on Return or focus loss; zero removes the target. The manual
add control queries published active-SDE item names only after three characters
and persists the selected type ID and exact name, never an unverified free-text
alias. Raw ESI inventory flags remain preserved and are displayed beneath a
readable storage-position label. Corporation hangars remain unavailable until
an authorized corporation-assets snapshot contract is added. Industry derives
`allocatable = max(factual - target, 0)`, then subtracts active plan
reservations. A target shortfall is visible but never becomes negative stock.
All current manufacturing and reaction graph steps consume this one projection;
the shared pool does not claim that assets were transported between locations.
Invention, copying and research facilities consume the same contract when their
job planners are added, but version 1 still does not claim executable Science
job planning.

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
Trading Location choices.

Accounting, Broker Relations and unmodified standings remain sourced from the
trader character. Each fee calculation also freezes its Trading Location. NPC
station refresh resolves the owner corporation and faction through ESI before
calculating the broker fee. A Player Structure's owner-defined broker fee is not
exposed by ESI and therefore remains unavailable rather than becoming zero.
The catalog also exposes a read-only packaged-volume query. Industry uses it
after graph completion for configured logistics; SwiftUI never performs
type-volume joins.
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

The recent five-row preview and complete overview both use the same editable
`ProductionOverviewGrid` and `StoredProductionOverviewRow`. BPO/BPC cost, sale
price and sold quantity are direct text fields in both views. The sold control
also provides a quick not-sold/full-sale toggle without removing partial-sale
quantities. Every accepted edit saves through the surrounding SwiftData
composition; failed saves roll back rather than leaving an unsaved value
visible.

The planner freezes `IndustryCostBreakdown`: full source-aware material replacement,
manual top-level
BPC/BPO cost, system-index cost, Facility Tax, SCC surcharge, Alpha surcharge,
installation total and optional logistics. Procurement logistics transports
purchased quantities and make-or-buy direct inputs from the Main Hub to their
configured production facility and uses
the higher of SDE-volume charge or 0.5% replacement collateral, rounded up to 1
million ISK for every generated contract. A matching hub/production location
creates no leg; finished-product transport is outside this calculation. A route
above the configured limit is split deterministically
into whole-item contracts; only a single packaged item above the limit is
blocking.
Missing tariff, volume, collateral, or a valid contract limit makes the total
unavailable. The default is 350,000 m³; a provider-confirmed exception is an
explicit Profile input for indivisible oversized items. Sale
scenarios separately freeze gross revenue, Sales Tax, Broker Fee and net
revenue.

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
create unbounded tasks for a large plan.
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

The Reactions navigation entry is a separate catalog-wide comparison, not a
mutable production plan. `SQLiteStaticCatalog.reactionDefinitions()` returns
one complete, published definition per SDE reaction formula. Runtime composes
those definitions with a location-bound `MarketOrderSnapshot`, adjusted prices
and, when fully verified, the Profile reaction facility and system index.
`ReactionProfitabilityAnalyzer` prices every input from sell depth, the output
replacement value from sell depth and immediate disposal from buy depth for the
selected batch. Positive value creation is the replacement value saved by
making rather than buying the output; immediate-sale spread remains a separate
gross observation before character-specific sales tax. Missing depth or an
unverified facility stays unavailable. Without a verified facility the UI
labels a material-only SDE baseline and does not treat installation, structure,
rig or clone costs as zero. Jita is the persisted default, while Amarr,
Dodixie, Rens and Hek use their own region and station order scopes.

The Moon purchase analysis is a separate read-only market comparison. Its item
scope is the complete published SDE group `Moon Materials`; it does not mix in
moon ores or compressed ore variants. For Jita, Amarr, Hek and Dodixie the
market boundary filters public regional sell orders to the exact NPC station.
For UALX-3 and C-J6MT it first uses the matching Profile player-structure ID
and otherwise the known, time-sensitive fallback location ID. For each material
and location, the lowest valid sell price is the band basis, the displayed
limit is exactly 110% of that price, and availability is the sum of remaining
sell-order volume priced at or below the limit. Each location remains an
independent `Sourced<MarketOrderSnapshot>`: missing, forbidden, partial and
stale markets remain visible and never become zero price or zero inventory.
Among fresh locations with a valid sell price, distinct lowest prices receive
dense ranks one through three. Equal prices share a rank; stale or unavailable
observations are not ranked. UI maps rank one to green, rank two to yellow and
rank three to red, and always includes the textual rank so color is not the
only signal.
The ESI cache and bounded request concurrency remain owned by the shared Market
service.

The cross-region Market Browser is a separate read-only market snapshot. For
one published SDE item it requests public sell and buy orders from every ESI
region with bounded concurrency; a failed or forbidden region is recorded as a
failure and does not erase orders returned by other regions. Location and solar
system labels come from the shared universe-name resolver. Optional jump counts
use the public route endpoint from the selected Profile or manually selected
origin. Route work is bounded and `notChecked` remains distinct from zero jumps
or `unreachable`; a player structure's docking ACL cannot be inferred from a
route result.

The Browser retains each regional response's ESI `Last-Modified` value as a
dataset timestamp. It is not presented as a guaranteed per-order modification
time. The summary's average seller price is weighted by remaining active sell
volume, and its sell/buy volumes are quantities in active orders. They are not
historical completed-sale volume; historical market activity requires the
separate region-history contract.

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

- Personal characters only.
- Personal wallet balances and their cross-character sum; no corporation
  wallet, journal or transaction presentation.
- Manufacturing and reactions; invention configuration is visible and stored,
  but invention planning is unsupported.
- Planner valuation and purchases use the Profile Main Hub selected from Jita,
  Amarr, Dodixie, Rens or Hek; the Reactions comparison retains its independent
  hub selection.
- Local storage only; no cloud sync.
- No corporation data, transport optimization, multi-hub optimization or job
  installation.
