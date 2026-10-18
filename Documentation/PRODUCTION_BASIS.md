# Production basis contract

## Purpose and ownership

The production basis is the local, versioned configuration consumed by
`eve-industry-kit`. `eve-ui-kit` presents it, while `eve-sde-integration`
supplies item category and group facts. SwiftUI does not classify items or
calculate facility selection.

This implementation follows the visible Ravworks Industry Config contract
inspected on 2026-07-30:

- multiple manufacturing systems plus separate reaction, invention, blueprint
  copying, material-research and time-research systems;
- system selection from the current public ESI universe index after three
  entered characters;
- current per-system ESI cost indices for manufacturing, invention, reaction,
  copying, research and any additional activity returned by ESI;
- informational manufacturing labels such as Small, Medium, Large, Capital,
  Modules, Structures or All;
- optional cost-index overrides;
- persistent Trading Locations with one connected-character trader each and a
  required standard NPC Main Hub for Planner prices and purchases;
- ESI-derived sales tax and Jita IV-4 broker fee from the Jita trader;
- optional procurement logistics using public ESI packaged volumes, replacement
  collateral and an owner-entered ISK/m³ rate;
- manufacturing and reaction slots plus job split thresholds;
- invention cost reduction and three explicit skill states;
- production blacklist presets and item-name overrides;
- configured structures, ESI-resolved regions and security bands, installed
  SDE service modules and up to three size-compatible rigs;
- automatic manufacturing, reaction and blueprint-activity facility
  assignment from SDE-backed modifiers.

The app deliberately presents six manufacturing classes requested by the
owner: Capital, Medium, Large, Small, Modules & Components, and Structures &
Fuel.

## Data contract

`ProductionBasis` is stored as one Codable snapshot in SwiftData. It contains:

- one or more manufacturing `ActivitySystemConfiguration` values plus
  dedicated reaction, invention, copying, material-research and time-research
  values;
- one profile-level clone state;
- character-bound market-fee, logistics, scheduling, invention and blacklist
  configuration;
- one or more immutable-ID `ConfiguredIndustryStructure` values;
- automatic or manual class-to-structure assignments;
- an automatic or manual reaction-structure assignment;
- automatic or manual facility assignments for invention, copying, material
  research and time research;
- intermediate-blueprint ME/TE defaults and an industry rule version.

The Profile editor compares its draft against the last successfully loaded or
saved snapshot. A visible warning marks a changed draft. Any sidebar navigation
away from Profile is intercepted until the owner saves, explicitly discards
the draft, or cancels navigation. Discard restores the saved snapshot; a
failed SwiftData save never completes the requested navigation.

Each configured structure carries a clearly labelled internal name, type,
configured activity-system association, security band, tax, structure bonuses,
job-cost multiplier, installed service modules, rigs and modifier source.
Clone state is profile-level, not a property of a structure. The selectable UI
contains only actual NPC and Upwell/faction structure types; legacy `Custom`
values are retained solely for decoding and migrate to an unbonused NPC
station. Unknown security remains a domain source state, not a selectable
space type.

System search does not require a new character scope. `eve-esi-kit` builds a
cached, provenance-bearing index from public `/universe/systems` and batched
`/universe/names` responses, then filters that index locally only after the
third character. After selection, `/universe/systems/{id}`,
`/universe/constellations/{id}` and `/universe/regions/{id}` resolve security,
constellation and region. A saved selection always contains the ESI-resolved
name and ID; incomplete search text is not silently accepted.

Player-structure linking is intentionally name-based because ESI offers no
endpoint that enumerates every ACL-visible structure in a selected system.
`/characters/{character_id}/search` finds candidate IDs after at least three
characters and `/universe/structures/{structure_id}` validates access and
filters results to the configured system. This requires
`esi-search.search_structures.v1` and `esi-universe.read_structures.v1`; older
character grants must be reauthorized. Corporation structure enumeration and
roles remain outside the personal-app boundary.

Security classification uses the ESI region identity and unrounded
`security_status`: Highsec starts at 0.45, positive values below that are
Lowsec, and zero or negative values are Nullsec. Anoikis system or region IDs
remain Wormhole. When a structure is created or reassigned, it inherits the
resolved status and band from its manufacturing system immediately; the
planner never falls back to a guessed Highsec rig multiplier.

Manufacturing labels are owner notes only. They do not filter products, change
facility ranking or override the six-category automatic production matrix.
That matrix exposes both the selected structure/station and its assigned solar
system. Cost indices are fetched from `/industry/systems`, retain the raw ESI
activity name for forward compatibility and are never replaced with zero when
the source is unavailable.

## Selection and planner behavior

Automatic manufacturing selection is deterministic:

1. exclude structures without an enabled Manufacturing service;
2. choose the structure with the highest effective material bonus for the
   classified product;
3. if tied, choose the highest time bonus;
4. if still tied, use the case-insensitive structure name as the stable order.

Manual assignments override this order. The Planner records the selected
facility and manufacturing class on each produced node and job-cost row.
Different facilities are not consolidated into one intermediate job.

Automatic reaction selection considers only Athanor or Tatara refineries with
an enabled Reactor service in the selected reaction system and excludes Highsec
or unresolved security contexts. It ranks the lowest effective material
multiplier first, then time, job-cost multiplier, facility tax and finally the
case-insensitive structure name. The derived assignment is stored with the
basis and is recalculated when the reaction system, structures, service
modules, rigs or automatic-selection state changes.

The Main-Hub opportunity snapshot consumes this same selected reaction facility
and the current reaction system cost index. It does not substitute a
manufacturing facility for reaction candidates. Missing or review-required
reaction-facility evidence keeps installation and dependent profitability
unavailable; it is never treated as a zero-cost reaction job.

Automatic blueprint-activity selection is scoped to the activity's configured
system and requires the matching Invention Lab or Research Lab service. For
invention, copying, material research and time research it ranks the lowest
effective job-cost multiplier first, then the lowest time multiplier, facility
tax and finally the stable case-insensitive facility name. Manual assignments
override that ranking. Missing, unresolved, service-incompatible or
wrong-system facilities remain visibly `needsReview`; they never become a
zero-cost facility.

The active SDE catalog supplies the product category and group. The target app
maps ships to Capital, Large, Medium or Small and uses Modules & Components as
the safe non-ship fallback. Structure and fuel groups map to Structures & Fuel.
The mapping is target-owned and tested; the portable SDE package remains
unchanged.

The Planner also consumes:

- one delimiter-free `Product Want ME TE` row per requested product; `Want`
  is the desired output quantity, and the planner derives whole blueprint runs
  as `ceil(Want / output-per-run)`;
- an optional guided Manufacturing-product input above that text contract. Its
  local active-SDE search starts after three characters, admits only published
  products whose Manufacturing blueprint and materials are fully resolved,
  and exposes the selected SDE output per run. Entered Runs, ME `0...10` and
  TE `0...20` are validated before `Runs × output-per-run` is appended as the
  exact `Want` value at the end of the text input. The search is static-data
  backed and does not require ESI authorization;
- ESI industry-system cost indices unless a visible override is present;
- per-structure facility tax and job-cost multiplier;
- configured market fees;
- the optional versioned logistics tariff;
- explicit production blacklists;
- manufacturing and reaction slot counts for deterministic makespan
  estimation.

Manufacturing materials are calculated job-wide from the active SDE
blueprint: base material per run times derived runs, blueprint ME, selected
structure multiplier and matching rig multiplier, followed by one upward
rounding step and the one-unit-per-run floor. Time uses the SDE activity time,
derived runs, blueprint TE and the selected structure/rig time multipliers.
Structure and rig reductions are separate multiplicative factors; their
percentages are not added. Reactions use their own output-per-run and facility
profile and never receive blueprint ME or TE.

Reactions remain separate and receive no ME or TE.

## Logistics and cost-breakdown contract

Logistics follows the owner-provided Standard Rate reference under rule
`main-hub-to-production-2026-08-01`. The reference does not contain the
current ISK/m³ calculator value, so the top-level Logistics workspace requires
an explicit owner-entered rate and never invents one. Route editing uses a local
draft and is merged into the shared Production Basis only by a successful save.

The Production Basis freezes one standard NPC Main Hub. Every material purchase,
including a bought intermediate or warehouse shortfall, uses that hub. Industry
creates `Main Hub → production facility` routes for the actual shopping list and
separately evaluates the same inbound route for both sides of each make-or-buy
comparison: the finished component when buying, or the direct recipe inputs when
building. A Main Hub equal to the production location creates no route.
Finished-product transport is outside this calculation.

When **Compressed Ore Refining** is enabled, mineral shortfalls receive an
additional procurement comparison under rule
`compressed-ore-refining-upwell-2026-08-15`. The active SDE `typeMaterials`
dataset supplies each published compressed ore's batch outputs, while
`typeDogma` attribute 790 supplies its ore-specific Processing skill. The
profile may contain several Reprocessing structures in different systems.
Each eligible structure must have a resolved Reprocessing service, a resolved
ore-yield multiplier and an explicitly confirmed Reprocessing tax; an empty
tax remains unknown, while entered 0% means confirmed fee-free.

Industry settings expose the exact readiness issues per relevant facility:
missing Reprocessing service, missing ore-yield source, and unconfirmed tax are
separate states. A facility with a service and yield but an empty tax is
therefore visible as incomplete. Facility, character and tax changes apply to
the next explicit Planner calculation; they do not mutate an already produced
snapshot.

The structure editor also exposes the selected equipment source, its yield
after the security-space multiplier, the separate hull bonus and the resulting
facility yield before character multipliers. When a Tatara still selects its
service module, the UI states that no configured compatible Reprocessing rig
improves it and names the SDE-backed `Standup L-Set Reprocessing Monitor II`
candidate. That rig remains an owner configuration input because ESI does not
prove which rigs are fitted to an arbitrary Player Structure.

For every evaluated ore and facility, the Planner either uses the structure's
fixed character or deterministically chooses the connected character with the
highest complete yield for that ore. The current skill contract is:

```text
equipmentYield = max(
  Reprocessing service yield,
  applicable rig yield × security-space multiplier
)
facilityYield = equipmentYield
              × (1 + structure Reprocessing bonus)
yield = facilityYield
      × (1 + Reprocessing level × 0.03)
      × (1 + Reprocessing Efficiency level × 0.02)
      × (1 + ore-specific Processing level × 0.02)
      × (1 + selected implant bonus)
output = floor(SDE batch output × required batches × yield)
```

The SDE rig value is already the complete equipment base (for example 0.53 for
a Tech-II ore rig), not an additive `+0.03`. Its low-security or null-security
multiplier applies only when that compatible rig is fitted. SDE dogma attribute
2722 supplies the multiplicative structure bonus: 2% for Athanor and 5.5% for
Tatara in the currently validated public SDE. The catalog recognizes the
specialized medium asteroid-, moon-ore- and ice-rigs as well as the large and
extra-large Reprocessing Monitor that applies to all three material kinds.
Missing service, structure, rig, size or security evidence is never replaced
with an invented modifier.

Fresh, retained partial and retained stale skill snapshots remain
distinguishable. Forbidden or unavailable skills cannot authorize a refining
route. The facility profile stores an explicit hypothetical implant choice per
character (none, RX-801, RX-802 or RX-804); it is not inferred from the live
clone. Legacy profiles decode as no implant.

The comparison consumes complete Main-Hub sell-order depth for compressed ore,
adds the configured fee against adjusted mineral output value, transports the
ore to the selected Refining structure, and compares that landed result with
the displaced direct mineral purchase and transport. It then recomputes both
complete inbound routes using actual courier splitting and rounding. A
compressed-ore substitution survives only when the selected complete landed
cost is lower. Otherwise the original mineral quantities, prices, cargo and
Multibuy lines remain unchanged. Selected ore, remaining minerals, facility,
system, character, yield, fee, both landed totals and savings are persisted in
the immutable plan snapshot. The immutable public-ESI packaged-volume snapshot
is also applied to every compressed-ore option before comparison; SDE remains
authoritative for batch size, mineral output and ore-specific Processing skill.
The fee uses the complete actually produced mineral stack, including any
surplus from whole batches. Batch selection uses the smallest whole-batch count
whose jointly rounded output covers the requirement; it does not round every
batch separately.

Each selected ore output freezes its active-SDE name, total produced quantity,
quantity used by this plan and planned warehouse surplus. Only used quantity
displaces direct mineral demand. Surplus never receives a value credit and does
not mutate the factual Asset snapshot; complete ore purchase, transport and
Reprocessing fee remain assigned to the product. Historical outputs without
the added allocation fields remain readable.

Catalog adapter version 3 is required for this comparison. An older active
catalog remains usable for existing planning but cannot fabricate
`typeMaterials`; the owner must run the safe same-build SDE reimport (or
install a newer build) before enabling the feature.

The Main Hub Opportunities scenario has the stronger complete-route contract:
for different exact Main/Home identities it always prices the purchased
material shortfall `Main Hub → Home Hub` and the full manufactured output
`Home Hub → Main Hub` before listed-sale profit. Disabling or incompletely
configuring this route makes profit unavailable. Its explicit Blueprint runs
scale both cargo legs through `runs × SDE output per run`; identical exact
location identities short-circuit both legs to zero.

Cargo volume is public CCP ESI `packaged_volume × quantity`. The current
client-driven SDE may expose only assembled `volume`; that field is never a
transport fallback. Collateral uses the
purchased quantity at the full-requirement replacement unit value. A missing
volume, incomplete replacement depth or invalid rate blocks logistics and
therefore all-cost profit; none becomes 0 ISK.

```text
volumeCharge = cargoVolumeM3 × configuredISKPerM3
collateralCharge = accurateCollateral × 0.5%
unroundedCharge = max(volumeCharge, collateralCharge)
roundedCharge = ceil(unroundedCharge / 1,000,000) × 1,000,000
```

The 350,000 m³ reference limit is the Profile default and is checked per
generated contract. Cargo above the limit is sorted deterministically by
packaged unit volume and allocated in whole item quantities using
first-fit-decreasing. This creates the smallest practical set of contracts
without dividing an item. Each contract receives the proportional collateral
of its allocated quantities and is charged and rounded independently. Every
new logistics leg persists its exact allocated item type, resolved name when
available, quantity, volume and collateral. The Planner exposes these lines in
the expanded contract card, so direct minerals, selected compressed ore and
remaining materials can be reconciled with the shopping list. Historical
snapshots without cargo lines remain readable and do not infer missing content.

Every sale-scenario inbound route exposes the same actual contract legs and
their cargo lines. Its displayed contract count is derived only from those
legs; an intermediate split warning is not presented as a competing route
total. When compressed-ore comparison is enabled but unavailable, the current
plan exposes the first specific `refining.*` blocker and its calculation time.
The owner must recalculate after changing a facility, character or tax.
Persisted production-history rows remain immutable evidence of their saved
logistics and Refining result and are never recomputed from current settings.

### Jump logistics to the Coalition Hub

The optional Coalition route uses a separate Jump Freighter fuel contract
instead of the courier ISK-per-m³ tariff. The Profile selects a hull and either
a fixed connected pilot or automatic selection. Automatic selection accepts
only fresh skill snapshots, prefers the highest Jump Drive Calibration level,
then the lowest combined fuel multiplier from Jump Fuel Conservation and Jump
Freighters. The authoritative skill type IDs are `21611`, `21610` and `29029`.

CCP ESI resolves the exact Home- and Coalition-Hub solar-system names and
supplies current Main-Hub orders. DOTLAN supplies the route and per-flight fuel
quantity through a request of the form
`/jump/<Hull>,<JDC><JFC><JF>/<HomeSystem>:<CoalitionSystem>`. The HTML result is
accepted only when its ordered systems, individual legs, total lightyears,
isotope type, total isotope amount and volume can all be parsed. DOTLAN is an
external planning source rather than CCP ESI; an unavailable response or an
unrecognized schema leaves the Coalition route unavailable instead of falling
back to 0 ISK or to an unrelated courier tariff.

Route selection is persisted independently for Jump Freighter, Carrier,
Dreadnought, Force Auxiliary, Supercarrier, Titan and Capital Industrial.
Each class either uses automatic DOTLAN routing or references one versioned
fixed-route profile. A profile is an ordered list of ESI-resolved intermediate
solar systems or a complete list that also contains the configured Home and
Coalition endpoints. Matching saved endpoints are normalized before the leg
pairs are created, so a complete route cannot create artificial endpoint
self-legs. Every waypoint may also retain an optional owner-entered cyno
structure or operational-location label. Several classes may deliberately
reference the same profile, while the assignment remains individually
changeable. The label is operational evidence only and never changes distance
or fuel.

For a fixed profile Runtime requests every consecutive pair from Home Hub via
the profile systems to Coalition Hub separately. Each response must contain
exactly one direct leg whose endpoints equal the requested pair. Validation and
fuel use the actual hull and selected pilot for that calculation, so a shared
profile may succeed for one class and remain unavailable for another. A
missing/deleted/incomplete profile, non-direct segment, range failure or parser
failure is blocking and cannot silently use automatic DOTLAN, cargo, courier
cost or 0 ISK. Automatic path choice occurs only for a class explicitly set to
automatic. The immutable assessment retains the profile identity, ordered
waypoints and every segment source URL.

The owner-configured usable cargo capacity defaults to an explicit planning
assumption of 350,000 m³. Outgoing products are allocated in whole quantities
to one-way flights. Each flight consumes the complete retained DOTLAN fuel
amount; return flights are not included. A single packaged item larger than
the entered usable capacity becomes `manualTransferRequired`.

Before that allocation, each top-level produced ship in a jump-capable Capital
group is removed from cargo. Carrier, Dreadnought, Force Auxiliary,
Supercarrier, Titan, Capital Industrial Ship and Jump Freighter groups receive
one hull-specific DOTLAN route per product type. Their request uses the exact
type name. Non-Jump-Freighter Capitals use `<JDC><JFC>0`; a produced Jump
Freighter flying itself uses its actual `<JDC><JFC><JF>` profile. Per-hull fuel
is multiplied by the completed hull quantity. The same four-isotope average
values both cargo flights and self-jumps. A plain Freighter is not jump capable
and is not classified as a self-jump. Missing Capital route evidence blocks
the Coalition total rather than putting that hull back into cargo or assigning
0 ISK.

The price rule
`main-hub-lowest-sell-average-four-isotopes-v1` obtains one current lowest
eligible Main-Hub sell price for each of Helium, Oxygen, Nitrogen and Hydrogen
Isotopes and calculates their arithmetic mean:

```text
averageIsotopePrice = (helium + oxygen + nitrogen + hydrogen) / 4
totalFuel = dotlanFuelPerFlight × flightCount
coalitionTransportCost = totalFuel × averageIsotopePrice

capitalFuel = Σ(dotlanFuelPerHull × completedHullQuantity)
capitalSelfJumpCost = capitalFuel × averageIsotopePrice
```

All four component prices, the average, selected hull and pilot, skills,
DOTLAN legs, fuel per flight, total fuel, flights and exact cargo lines are
frozen in the route assessment. If even one isotope price is missing, the
average and the complete Coalition scenario cost remain unavailable. Older
snapshots without the optional Jump Freighter or Capital-self-jump breakdown
continue to decode and
are never backfilled from current routes or prices.

If one packaged item itself exceeds the configured limit, planning remains
blocking. Because the supplied reference says the limit applies only in 99% of
cases, the owner may then enter a provider-confirmed exception limit.
Containers remain unsupported; the planner does not infer repackaging.

## Blueprint-cost input contract

The top-level format is:

```text
Product Want ME TE [BPC|BPO BlueprintCostISK]
```

Examples:

```text
Ark 1 10 20 BPC 175000000
Capital Cargo Bay 25 10 20 BPO 5000000
```

The amount is the total blueprint cost allocated to that production line.
`BPC` is treated as a consumed copy acquisition cost. A `BPO` remains a
reusable owned original, so the entered amount is an explicit owner allocation
or amortization share, never an inferred full market purchase price. Missing
entries remain visibly excluded rather than silently guessed. Industry stores
the line-level kind, amount and treatment, totals them separately, and includes
the accepted total in production cost, profit, margin and ROI.

`IndustryCostBreakdown` separates material cost, BPC/BPO cost, system-index
cost, Facility Tax, SCC surcharge, Alpha surcharge, complete installation cost
and inbound material logistics. The visible Costs subtotal contains material,
Blueprint allocation and installation only; logistics remains frozen in the
domain breakdown for scenario accounting but is displayed per route instead of
inside that subtotal. Warehouse consumption is an informational Main-Hub
replacement-value subset of material cost and is never added twice. For each
bought or stocked material, the planner retains a complete Main-Hub quote for
the full required quantity and values only the bought plus consumed-stock
quantity at that quote's weighted unit price. A stock-first intermediate's
produced shortfall contributes its recursive input costs instead of another
replacement charge for the produced units. Missing full-demand market depth
keeps material and total production costs unavailable, even when the stock
quantity alone could be quoted. Actual purchase cash cost and warehouse
replacement value remain separate. New production-history records retain the
same request-level leaf valuation; existing frozen history is not recalculated.
Every sale card exposes Route 1 from Main to production and Route 2 from production to the
selected sale location. Main sale scenarios require the return route, Home
normally short-circuits Route 2 when production and sale locations are
identical, and Coalition scenarios use the distinct production-to-Coalition
route. Exact identical locations cost 0 ISK. One item larger than the courier
limit becomes `manualTransferRequired`. The planner still sums production and
every calculated route as known scenario cost, then exposes profit, margin and
ROI as provisional upper bounds before the additional manual transport. The
manual route is never recorded as 0 ISK. Prohibited or otherwise unavailable
route evidence still leaves scenario total and profit unavailable.

Sales Tax and Broker Fee are deductions owned by each sale scenario and are not
duplicated in a separate total. Immediate sale applies Sales Tax but no Broker
Fee; listed sale applies both using the exact hub's trader evidence. Main,
Home and Coalition Contract Sale instead use the lowest per-unit price
of a public single-type Item Exchange offer with no requested lines across the
complete imported universe. Bundles, requested-item exchanges and
incomplete/truncated Public Contract coverage cannot establish a lowest
reference. The immutable reference accepts an optional region-ID set so a
future Market Settings control can narrow price formation without changing the
quote contract; the current runtime passes no set and therefore uses all
regions. Contract Sale represents an actually published contract:
it applies 0 EVE market Sales Tax and Broker Fee and deducts the manually
confirmed combined non-refundable public-contract fee rate stored at that hub.
ESI does not expose the personal creation-fee quote for issuing a new contract.
An unknown fee therefore keeps the fee itself explicit and exposes revenue,
profit, margin and ROI only as provisional values before that fee; once the
rate shown by EVE is configured, the final deductions are calculated. A
refundable deposit is not treated as cost. All three hub strategies retain their
required logistics routes. Final profit, margin and ROI use net revenue and the
strategy-specific total cost; provisional values are visibly qualified.

`HighSecurityCapitalTransferPolicy` rejects the production-to-Main route and
Main market scenarios for SDE Ship nodes classified as Capital, except the
Freighter and Jump Freighter groups. Home and Coalition strategies remain
available at configured reachable locations. CCP's support article
[Capital Ships in High Security Space](https://support.eveonline.com/hc/en-us/articles/203280661-Capital-Ships-in-High-Security-Space)
is the authority for the mechanical restriction; a contract never turns an
unreachable Highsec destination into a valid route. CCP's official
[Item Exchange Contract](https://support.eveonline.com/hc/en-us/articles/206758389-Item-Exchange-Contract)
article distinguishes public and private contracts but does not publish a
complete current public-contract fee formula. Historical 10,000 ISK private-
contract guidance is therefore not reused for public Contract Sale. The
comparison rule is `public-item-exchange-reference-2026-08-13`.

The immutable `SaleScenarioResult` freezes the optional tax and broker rates
separately from their price-dependent amounts and records whether Broker Fee is
applicable. Production Overview therefore treats a Highsec-prohibited Capital
broker fee as not applicable, keeps its cell unavailable rather than presenting
an invented zero amount, and excludes it from minimum-price and profit
arithmetic. A known Sales Tax rate remains applicable to a manually entered
sale price. The 10% minimum gross price is production cost per unit times 1.10,
grossed up for every known applicable sales deduction. Missing production cost,
sale price, tax evidence, or an applicable but unknown broker rate stays
unavailable. Historical plans may recover a tax rate only from evidenced
amounts inside their own Home or Coalition snapshots; current Profile values do
not rewrite history.

The Market Taxes panel requires one connected character as the trader. The
character capability snapshot supplies Accounting, Broker Relations and
unmodified standings. For Jita IV-4, the rule uses Caldari State faction ID
`500001` and Caldari Navy corporation ID `1000035`. Sales tax is
`7.5% × (1 − 11% × Accounting level)`. The NPC-station broker fee is
`3% − 0.3% × Broker Relations level − 0.03% × faction standing − 0.02% ×
corporation standing`, with the official 1% floor. ESI supplies the source
skills and standings, not a precomputed future tax percentage. Forbidden,
unavailable or partial data never becomes a zero fee; the listed-sale quote
remains unavailable until both effective rates are known. The applied
calculation stores the character ID, source states, snapshot identities,
calculation time and rule `ccp-market-fees-2026-08-13`. For an NPC station in
Exordium (ESI region `10001004`), the listed-sale fee also contains CCP's
additional 5% charge for non-immediate market orders; immediate sale and
Contract Sale do not receive that market surcharge.
The authoritative CCP support article
[Broker Fee and Sales Tax](https://support.eveonline.com/hc/en-us/articles/203218962-Broker-Fee-and-Sales-Tax),
updated 2026-03-02 and reviewed for this implementation on 2026-08-13, states
that Broker Fees apply when non-immediate market orders are created and Sales
Tax is deducted from sellers after a market sale. These market deductions are
therefore not reused as public-contract fees. Contract Sale requires the
separately confirmed manual public-contract fee.
CCP's
[Cradle of War expansion notes](https://www.eveonline.com/news/view/cradle-of-war-expansion-notes),
published 2026-06-05 and reviewed 2026-08-13, are authoritative for the
Exordium-specific 5% non-immediate-order charge.

Invention, blueprint-copying, material-research and time-research systems and
facility selections are stored and visible. The Profile page also presents all
published SDE Science skills in a cross-character matrix. Its conclusion
compares broad invention readiness only; concrete BPO/BPC research, copying
and invention job planning remains outside version 1 and requires the owned
blueprint instance plus the activity-specific SDE definition.

## Structure, service-module and rig modifier contract

The target adapter joins the active catalog to the matching validated SDE
package and streams only required `typeDogma` records. Structure type, size,
rig-slot count, base manufacturing ME/TE and job-cost multiplier therefore
come from the active build. The same adapter publishes the Standup
Manufacturing Plant and shipyards, Reactor services, Invention Lab, Research
Lab, Hyasyoda Research Lab and Reprocessing Facility. Their SDE structure-group
or type restrictions filter the picker. Enabled activities and Reprocessing
yield multipliers are read-only SDE facts.

Rig lists are filtered by the selected structure's M/L/XL size; no more than
the structure slot count or three rows are accepted. Manufacturing-rig ME/TE,
reaction-rig material/time, and Science-rig job-cost and time reductions are
read-only and security-scaled from SDE dogma. The adapter recognizes the
Standup Invention, Blueprint Copy, ME Research and TE Research rig families
and never applies their attributes as manufacturing ME/TE. Laboratories enable
the activity; their effective Science bonuses continue to come from the
matching rigs. A Reprocessing Facility exposes normal, moon, ice and gas yield
multipliers rather than an invented ME/TE value.

Facility tax remains an explicit manual value. Neither the character-visible
structure detail nor the corporation structure contract publishes a facility
tax. Thukker rigs remain excluded with a visible `needsReview` diagnostic
until their additional dogma modifier is modeled rather than guessed.

The current production matrix intentionally uses the six owner-facing product
classes. Basic-versus-advanced ship-rig specialization is preserved in the
selected rig name but is not yet a seventh planner classification dimension.

## Source identity and limitations

- Product classification: active CCP SDE build, currently owner-accepted build
  `3451778`. A newly imported catalog also preserves the type record's optional
  `metaGroupID` and `techLevel` for Main-Hub production-class filtering. A
  legacy catalog without those adapter columns remains readable but the class
  stays unavailable until a current catalog is activated; names are never used
  as a substitute.
- Production definitions: only published blueprint types with published,
  resolved products and fully resolved materials are selectable. Unpublished
  SDE test/legacy recipes are excluded.
- Current prices and system indices: ESI snapshots at plan calculation time.
- Structure and rig values: active CCP SDE `typeDogma` records.
- Compressed-ore material outputs and ore-specific Processing skill:
  active CCP SDE `typeMaterials` plus the matching `typeDogma` record.
- Logistics volumes: bounded public ESI `/universe/types/{type_id}/` snapshots
  at compatibility date `2025-12-16`. Missing `packaged_volume` remains
  unavailable; the active SDE type's assembled `volume` is never substituted.
- Logistics collateral: the plan's timestamped Main Hub order snapshot.
- Rule version: `2026.07-v1`.

ESI does not publish the installed or online service-module fit of an
ACL-visible player structure. The owner therefore records modules explicitly;
legacy profiles and NPC-station service availability remain visible
`needsReview` states until confirmed. Production skill availability and
real-time job-slot occupancy are not inferred from a configured structure.

## Handoff envelope

```yaml
handoffVersion: 1
producerSkill: eve-sde-integration
consumerSkills:
  - eve-industry-kit
  - eve-ui-kit
  - eve-testing-kit
target:
  path: /Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets
  platform: macOS 14 / Swift 6
scope:
  requestedFeatures:
    - Ravworks-oriented production configuration
    - six manufacturing classes
    - automatic manufacturing, reaction and blueprint-activity facility selection
    - character-bound ESI market fee calculation
  excludedFeatures:
    - invention planning
    - live service-module and slot occupancy
sourceIdentity:
  sdeBuild: 3451778
  esiCompatibilityDate: 2025-12-16
  fetchedAt: 2026-07-30
contracts:
  protocols:
    - IndustryCatalogQuerying.industryClassification
    - SQLiteStaticCatalog.industryFacilityReferences
    - PlayerStructureSearchService.search
  snapshotTypes:
    - ProductionBasis
    - ProductionFacilitySelection
    - ReactionFacilitySelection
    - ScienceFacilitySelection
    - MarketFeeCalculation
  schemaVersions:
    industryRules: 2026.07-v1
decisions:
  - material bonus wins before time bonus
  - manual assignment overrides automatic selection
  - only reaction-capable refineries in the reaction system are auto-ranked
  - Science facilities are ranked only in the matching activity system
  - Science job-cost and time rig attributes remain separate from ME and TE
  - Jita fees bind to one connected trader and sourced capability snapshot
  - unresolved modifiers remain needsReview
  - facility tax remains manual because ESI does not publish it
openRisks:
  - Thukker rig special modifiers remain needsReview
  - broad product classes do not yet distinguish basic and advanced ship rigs
  - concrete BPO/BPC invention, copying and research execution remains unsupported
next:
  skill: eve-testing-kit
  requestedOutcome: verify selection, classification, blacklist and scheduling
```
