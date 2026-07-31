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
- a connected-character trader plus ESI-derived sales tax and Jita IV-4
  broker fee;
- optional inbound and outbound logistics using SDE packaged volumes, Jita
  replacement collateral and an owner-entered ISK/m³ rate;
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

Logistics follows the owner-provided Standard Rate reference captured on
2026-07-30 under rule `standard-haulage-split-2026-07-30`. The screenshot does not
contain the current ISK/m³ calculator value, so Profile requires an explicit
owner-entered rate and never invents one.

The owner may enable either or both directions:

- Jita purchases to the configured production location;
- finished products from the production location to Jita.

Each direction is a courier route. Cargo volume is CCP SDE
`packagedVolume × quantity`. Inbound collateral is the complete Jita purchase
quote. Outbound collateral is a new volume-depth Jita sell quote for the
finished cargo. A missing volume, incomplete market depth or invalid rate
blocks logistics and therefore all-cost profit; none becomes 0 ISK.

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
of its allocated quantities and is charged and rounded independently.

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
and logistics.
Sales Tax and Broker Fee are sale-scenario deductions. Immediate sale applies
Sales Tax but no Broker Fee; listed sale applies both. Profit, margin and ROI
use net revenue and total production cost including logistics.

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
calculation time and rule `ccp-market-fees-2026-07-02`.

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
  `3451778`.
- Production definitions: only published blueprint types with published,
  resolved products and fully resolved materials are selectable. Unpublished
  SDE test/legacy recipes are excluded.
- Current prices and system indices: ESI snapshots at plan calculation time.
- Structure and rig values: active CCP SDE `typeDogma` records.
- Logistics volumes: active CCP SDE `packagedVolume`, with the same type
  record's SDE `volume` as the explicit fallback.
- Logistics collateral: the plan's timestamped Jita order snapshot.
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
  path: /Users/svenstolze/Documents/EVE NEXUS SIMPLE
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
