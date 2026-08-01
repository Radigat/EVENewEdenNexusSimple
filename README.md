# EVE Nexus Simple

EVE Nexus Simple is a local macOS 14+ industry planner for EVE Online. It is
implemented as a Swift 6/SwiftUI application and keeps SDE, SSO, ESI, character,
assets, blueprints, market, reactions and industry planning behind separate
contracts.

## Open in Xcode

```sh
xcodegen generate
open EVENexusSimple.xcodeproj
```

The Swift package can be validated without signing:

```sh
swift test
```

The generated native project can be validated with:

```sh
xcodebuild -project EVENexusSimple.xcodeproj \
  -scheme EVENexusSimple \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/EVENexusSimpleDerivedData \
  test CODE_SIGNING_ALLOWED=NO
```

## Runtime configuration

Set the EVE application client ID in **Data & Settings**. The registered callback
must be exactly `http://localhost:52722/callback`. Refresh tokens are written only
to the macOS Keychain. They are never copied into SwiftData or an unencrypted
file. The app reuses one in-memory SSO session per client ID, so normal ESI
actions do not repeatedly read the same token. A legacy Keychain item may
request access once while it is migrated; prompt-free Data Protection Keychain
access requires running the app with a stable Apple Development signature. No
client secret is used.

The CCP User-Agent owner contact in **Data & Settings** is stored locally after
**Save contact**, **Check for SDE update**, or leaving the page with a valid
changed value. The update result shows the installed build, current official
build, latest CCP schema boundary and successful check time separately. “No
newer schema boundary” means only that CCP's latest recorded schema boundary is
not newer than the installed build; it does not replace the build comparison.

Under **Characters**, **Sync all** refreshes every saved character with the
existing grants. **Authorize or add character** accepts whichever character is
selected in EVE SSO: the verified character ID automatically reauthorizes the
matching saved character or adds a new one. EVE SSO still requires a separate
browser selection and consent for every character whose scopes are renewed.

The app checks CCP's public EVE status page at launch and periodically while it
is open. A global banner distinguishes Tranquility maintenance, Login/SSO
problems and ESI problems. During the daily 11:00 UTC downtime, a UTC-based
fallback notice remains available even if the status page cannot be reached.
The Characters page also changes its progress text after the browser callback
so a completed SSO connection is not mistaken for the longer, downstream ESI
data synchronization.

**All items** combines the stored personal asset snapshots of all synchronized
characters at every location, including finished ships. **Warehouse** is a
separate production view: it retains only items at exact station or Player
Structure IDs linked in Profile and excludes SDE category `Ship` plus every
module, charge or container whose ancestor chain enters a ship. Loose hangar
items and contents of ordinary hangar containers remain available. Locations are
shown first, each character owner expands below the location, and the owner's
contents retain their raw ESI inventory flags with a readable storage-position
label and an in-app explanation for values such as `AutoFit` and `Unlocked`.
Both views offer one shared, remembered arrangement: alphabetically, by active-
SDE group, or by active-SDE main group/category. Grouped sections show their
type and unit totals; types without resolved SDE classification remain visible
under `Unclassified`. Large owner lists are organized once off the UI thread,
rendered lazily, and do not repeat SDE name resolution when a minimum changes.
Edit the minimum directly beside any visible Warehouse item; Return or leaving
the field saves it. Additional items use the active SDE name search after at
least three typed characters, so only an exact published result can be selected. A shortfall
becomes a visible alarm and the Planner can use only stock above the minimum.
The inventory filter accepts a partial item name from three letters or an exact
type ID, reduces the view to matching rows and opens their locations and owners.
Item and solar-system result popovers use a larger scrollable result area.
Corporation hangars are not synchronized yet and remain explicitly
unavailable rather than appearing empty. Run
**Sync all** once after installing this version so existing characters receive
their newly persisted asset snapshot. Asset locations with ESI type `other`,
structure-range station IDs, and structure-range `item` parents that are not
another returned asset are retained as Player Structures, including Lowsec and
Highsec Upwell production sites. Their names and type IDs are resolved with the
authorized character's `esi-universe.read_structures.v1` grant and docking
access. If either is missing, the structure and its stock remain visible under
the explicit structure ID instead of being removed from warehouse availability.
The location list is collapsed by default: its fully clickable row shows the
station or structure, character count and total item quantity. Expanding it
reveals the characters and then their individual contents. Player Structures
use the official EVE type icon for the resolved Azbel, Sotiyo, Athanor or other
Upwell type.

The **Blueprints** sidebar item combines the stored personal blueprint
snapshots of all synchronized characters. The list distinguishes originals
from copies and shows owner, location, runs, ME and TE. Selecting an original
loads its active SDE definition and current ESI adjusted prices, then displays
the separate and cumulative ME/TE research costs for levels 1 through 10 using
the configured Material Research and Time Research facilities in **Profile**.
The displayed BPO total is a current replacement estimate consisting of the
SDE base price plus the calculated research cost to the blueprint's present
ME/TE. It is neither a historical purchase price nor a guaranteed contract
sale price. Copies are never treated as researchable, and unresolved
facilities, prices or special research materials remain explicit instead of
being valued as zero. Run **Sync all** once after installing this version so
existing characters receive their newly persisted blueprint snapshot.

The Profile structure picker can discover Player Structures from a character's
asset locations, industry jobs and market orders. This covers structures the
character has actually used. ESI does not expose a complete list of all docking
ACL entries, so an unused but accessible structure must still be found with the
three-character name search.

Live SDE/ESI tests are opt-in and are separate from deterministic tests. The app
does not install jobs in EVE and does not support corporation data or invention
planning in version 1.

The **Wallet** sidebar item shows the available total and the personal balance
for every connected character. Use **Refresh all wallets** or the refresh button
beside one character to update balances. The app requires
`esi-wallet.read_character_wallet.v1`; missing, forbidden and stale values stay
visible and are never counted as zero.

The Planner saves its input draft and the latest successfully calculated plan
locally, so moving to Characters, Wallet or another sidebar page does not reset
the production setup. On launch, it loads the newest saved Production Basis and
its installation-cost reference inputs before enabling the first calculation.
The Planner initially expands every producible intermediate. Raw inputs offer
**Buy** or **Use warehouse**; producible materials additionally offer
**Produce**. Changing this source immediately recalculates the plan. Buying or
taking an intermediate from the warehouse removes its own production branch,
its input materials and its installation job. Protected targets and active
reservations remain unavailable; if selected warehouse stock is short, only
the uncovered remainder stays on the shopping list. Every input not produced
inside the plan is valued once at its full current Main Hub replacement depth.
The Costs panel separately shows the Main Hub countervalue of the quantity actually
consumed from the warehouse. This value uses the same weighted full-demand
unit prices, is informational only and is not added to the total again.
Profile manages Trading Locations and selects one standard NPC station as the
**Main Hub**. Planner market depth, every planned purchase and its plain
`Item name Quantity` Multibuy list use only this hub. For every producible
component, intermediate reaction and base reaction, the Planner compares the
complete required quantity at the Main Hub with the required production batch.
Profile separately selects a **Home Hub** from any configured location and can
add public NPC stations or character-accessible Player Structures through ESI;
configured production Tatara/Sotiyo entries are not proposed as Trading
Locations. Every Trading Location has its own trader and fee evidence. Accounting,
Broker Relations and unmodified standings are explicitly attributed to that
character and location. Player Structure broker fees remain unavailable because
ESI does not expose the owner-defined rate.
The comparison includes direct inputs, installation and Main-Hub-to-production
logistics, shows the cheaper option and the absolute ISK saving, and remains
unavailable when the hub cannot fill the required quantity or another input is
unknown. The user can still override the recommendation.
**Apply recommendations and calculate** transfers every available analysis to
the Produce/Buy choices and creates a new immutable plan. Its recalculated cost,
production-job and Main Hub Multibuy sections are the resulting build and
shopping lists. The build list shows product, activity, runs, output quantity,
ME/TE, facility and installation cost. Raw-material choices and unavailable
analyses remain unchanged.
The shopping list's **Market** row opens a complete review table before export:
item, purchase quantity, weighted unit price, line total and covered market
quantity. It uses the same sorted purchase projection as the Multibuy payload;
missing or partial sell depth remains unavailable and does not become a zero
price or an apparently complete purchase total.
**Record production** appends one row per produced item to the
**Production Overview**, following the `Produktionsübersicht` worksheet in
`EVE-indu- Delve.xlsx`. The Planner shows the five newest rows; the full
overview contains the same 21 business columns from number and date through
material, index, blueprint and market costs to projected and real profit.
Blueprint cost, sale price per unit and sold units remain editable after
recording in both the five-row Planner preview and the complete Production
Overview. The sale control can mark a row not sold or fully sold, while the
quantity field retains partial sales. Real profit updates from the persisted
sale price and sold quantity. Calculated values update from those inputs while
unresolved source costs—including an unentered BPO/BPC cost—stay visibly
unavailable.
The active Planner also separates system-index cost, Facility Tax, SCC, Alpha
surcharge, Sales Tax and Broker Fee. Optional procurement logistics calculate
`Main Hub → production facility` for purchases and make-or-buy input materials.
Each generated contract uses SDE packaged volumes, replacement-value collateral,
the larger of the configured m³ charge or 0.5% collateral, and its own
million-ISK upward rounding. A missing tariff, packaged volume, collateral depth
or production location keeps the affected comparison unavailable instead of
turning the unknown cost into zero.

Top-level production lines may append `BPC <total ISK>` or
`BPO <allocated ISK>` after Product, Want, ME and TE. BPC is treated as a
consumed copy acquisition cost; BPO is an owner-entered allocation for the
reusable original. Both are shown separately and included in total cost,
profit, margin and ROI.

**Reactions** evaluates every complete published reaction formula in the active
SDE catalog. It defaults to 100 runs and Jita, while both the exact run count
and NPC hub (Jita, Amarr, Dodixie, Rens or Hek) are selectable and persisted.
The run control no longer uses an arbitrary million-run ceiling. The app derives
the maximum runs of one 30-day job separately for every formula from its SDE
duration and the active facility time basis. If one run alone exceeds 30 days,
that run remains valid; larger analyzed batches show the number of jobs required.
The result separates input purchases, output replacement value, immediate-sale
revenue/spread, installation cost, make-or-buy savings and positive, negative
or unavailable value creation. A verified Profile reaction facility contributes
its material/time multipliers, system index, facility tax, SCC and clone
surcharges; otherwise the screen explicitly uses a material-only SDE baseline.
Search, reaction-type/status filters and ascending or descending value sorting
cover the full result set. Value creation and margin stay visible on each row,
and the complete row is the disclosure target for the detailed calculation.
Missing market depth never becomes zero.

See `Documentation/ACCEPTANCE.md` for the exact split between implemented and
tested behavior, current-service verification and owner acceptance.
