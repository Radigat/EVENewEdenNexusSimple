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

The sidebar now has one shared **Data & Settings** entry. Its horizontal menu
opens **SDE**, **ESI**, **Industry Settings** and **Market Settings** in that
order, without adding four separate entries to the main navigation.

The EVE application client ID is built into the app. The registered callback
must be exactly `http://localhost:52722/callback`. Refresh tokens are written
only to the macOS Keychain. They are never copied into SwiftData or an
unencrypted file. The app reuses one in-memory SSO session per client ID, so
normal ESI actions do not repeatedly read the same token. A legacy Keychain item
may request access once while it is migrated; prompt-free Data Protection
Keychain access requires running the app with a stable Apple Development
signature. No client secret is used.

The CCP User-Agent operator contact is the public project address
`projekt-st@gmx.de` and is not shown in **Data & Settings**. It is compiled into
the application and can be overridden through
`EVE_NEXUS_CCP_USER_AGENT_CONTACT` for a local development run. ESI and SDE
requests use the normalized value only as part of their User-Agent. It is not
an authentication credential. The SDE surface contains only the installed
state plus update check and installation controls.
The update result shows the installed build, current official
build, latest CCP schema boundary and successful check time separately. “No
newer schema boundary” means only that CCP's latest recorded schema boundary is
not newer than the installed build; it does not replace the build comparison.

Under **Data & Settings → ESI**, **Sync all** refreshes every saved
character with the existing grants. **Authorize or add character** accepts
whichever character is selected in EVE SSO: the verified character ID
automatically reauthorizes the matching saved character or adds a new one. EVE
SSO still requires a separate browser selection and consent for every character
whose scopes are renewed.

The app checks CCP's public EVE status page at launch and periodically while it
is open. A global banner distinguishes Tranquility maintenance, Login/SSO
problems and ESI problems. During the daily 11:00 UTC downtime, a UTC-based
fallback notice remains available even if the status page cannot be reached.
The ESI page also changes its progress text after the browser callback
so a completed SSO connection is not mistaken for the longer, downstream ESI
data synchronization.

**All items** combines the stored personal asset snapshots of all synchronized
characters at every location, including finished ships. A shared remembered
switch optionally adds synchronized Corporation hangars as separate owners.
**Warehouse** is a
separate production view: it retains only items at exact station or Player
Structure IDs actually selected in Industry Settings for manufacturing, reactions,
invention, copying or research. Assignments at several facilities and systems
are combined; configured but unused structures and Main-Hub market inventory
are excluded. It also excludes SDE category `Ship` plus every
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
The **Industry Calculator · Main Hub** restores the last successfully completed
candidate list at launch, including its market and SDE provenance. Its filters
start with every supported product and ownership state enabled, so only a
filter selected in the current session narrows that list. Warehouse and the
Main Hub/Shopping/Costs menu stay visible before an item is selected, and short
result lists remain docked to the top of the calculator.
Click a candidate name or its chevron to open the recursive production tree.
The tree has its own adjustable target quantity, keeps bought intermediates
expandable, applies stock from the exact configured activity locations before a
Build/Buy fallback, and shows the Main-Hub recommendation for the complete
required quantity. Blueprint rows distinguish owned BPC/BPO evidence, copying,
invention and indexed contract availability without converting bundled contract
prices into invented per-run costs. Tree production totals require complete
Main-Hub-to-facility and finished-product-to-Main-Hub logistics; missing inputs
remain unavailable rather than zero.
The inventory filter accepts a partial item name from three letters or an exact
type ID, reduces the view to matching rows and opens their locations and owners.
Item and solar-system result popovers use a larger scrollable result area.
Corporation hangars require a character with the EVE role `Director` and the
new Corporation Assets, Corporation Roles and Corporation Divisions scopes.
Use **Update permissions** for that character and then synchronize it. Missing
scope, missing Director role or an ESI failure remains visibly unavailable and
never becomes an apparently empty hangar. `CorpSAG1` through `CorpSAG7` retain
their raw flags and display the division name returned by ESI. If several
Directors synchronize the same Corporation, its inventory is counted only once.
Run **Sync all** once after installing this version so existing characters
receive their newly persisted snapshots. Asset locations with ESI type `other`,
structure-range station IDs, and structure-range `item` parents that are not
another returned asset are retained as Player Structures, including Lowsec and
Highsec Upwell production sites. Their names and type IDs are resolved with the
authorized character's `esi-universe.read_structures.v1` grant and docking
access. If either is missing, the structure and its stock remain visible under
the explicit structure ID instead of being removed from warehouse availability.
The location list is collapsed by default: its fully clickable row shows the
station or structure, owner count and total item quantity. Expanding it
reveals the owners and then their individual contents. Player Structures
use the official EVE type icon for the resolved Azbel, Sotiyo, Athanor or other
Upwell type.

The **Blueprints** sidebar item combines the stored personal blueprint
snapshots of all synchronized characters. The list distinguishes originals
from copies and shows owner, location, runs, ME and TE. Selecting an original
loads its active SDE definition and current ESI adjusted prices, then displays
the separate and cumulative ME/TE research costs for levels 1 through 10 using
the configured Material Research and Time Research facilities in
**Data & Settings → Industry Settings**.
The displayed BPO total is a current replacement estimate consisting of the
SDE base price plus the calculated research cost to the blueprint's present
ME/TE. It is neither a historical purchase price nor a guaranteed contract
sale price. Copies are never treated as researchable, and unresolved
facilities, prices or special research materials remain explicit instead of
being valued as zero. Run **Sync all** once after installing this version so
existing characters receive their newly persisted blueprint snapshot.

The Industry Settings structure picker can discover Player Structures from a character's
asset locations, industry jobs and market orders. This covers structures the
character has actually used. ESI does not expose a complete list of all docking
ACL entries, so an unused but accessible structure must still be found with the
three-character name search.

Live SDE/ESI tests are opt-in and are separate from deterministic tests. The app
does not install jobs in EVE. Corporation support is currently limited to
authorized asset hangars and wallet balances; invention planning remains
outside version 1.

The **Wallet** sidebar item shows the available total and the personal balance
for every connected character. Use **Refresh all wallets** or the refresh button
beside one character to update balances. The app requires
`esi-wallet.read_character_wallet.v1`; missing, forbidden and stale values stay
visible and are never counted as zero.

The dedicated **Net Worth** page records one local valuation point per calendar
day and offers 7-, 30-, 90-day and complete-history views, combined or per
character. It separates wallet, priced personal assets, remaining sell-order
value, actual buy-order escrow, own outstanding item/auction contracts and the
collateral of own in-progress courier contracts. Accessible Corporation assets
and wallet divisions are included once per Corporation. Blueprint Copies,
unresolved prices, missing permissions and missing Corporation roles stay
explicit rather than becoming zero. Price gaps identify the affected EVE types
and explain that the public ESI price route needs no SSO scope. Corporation
cards state how many unique Corporations are included and whether Director or
Accountant access is missing. Existing characters must use **Update
permissions** once for the new contract and Corporation-wallet scopes. A manual
snapshot replaces the same day's point, and individual historical points can
be deleted only after confirmation.

The Planner saves its input draft and the latest successfully calculated plan
locally, so moving to ESI, Wallet or another page does not reset
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
The **Data & Settings → Market Settings** page owns the three market roles:
Main, Home and Coalition. Jita, Amarr, Rens and Hek are built-in
Main choices; any additional ESI-resolved NPC station can also become the
**Main Hub**. Planner market depth, every planned purchase and its plain
`Item name Quantity` Multibuy list use only this hub. For every producible
component, intermediate reaction and base reaction, the Planner compares the
complete required quantity at the Main Hub with the required production batch.
**Home Hub** may be the same location, in which case hub-to-home logistics are
not charged. **Coalition Hub** requires an authenticated ESI Player Structure;
additional resolved locations can remain stored as role candidates but are not
loaded as markets until assigned to one of these three roles. The selected roles
drive Moon analysis and the selectable single-market basis in Reactions. A
location carrying multiple roles appears only once. Moon analysis can also
export the complete comparison as a PNG, including every selected hub and Moon material, with
the export date and time in the image heading and file name;
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
The result separates input purchases, their transport to the reaction facility,
output replacement value, direct-purchase transport and total, immediate-sale
revenue/spread, installation cost, make-or-buy savings and positive, negative
or unavailable value creation. The comparison therefore prices the complete
batch on both paths: reaction inputs plus inbound logistics and installation
versus buying the output plus inbound logistics. It uses the Industry Settings logistics
rate, SDE packaged volumes, replacement-value collateral, contract splitting
and per-contract rounding shared with the Planner. Missing volume, collateral
or an enabled but incomplete tariff keeps the comparison unavailable; explicitly
disabled logistics contributes 0 ISK. Finished-product transport for an
immediate sale remains outside the gross sale-spread observation. A verified
Industry Settings reaction facility contributes its material/time multipliers, system
index, facility tax, SCC and clone surcharges; otherwise the screen explicitly
uses a material-only SDE baseline.
Search, reaction-type/status filters and ascending or descending value sorting
cover the full result set. Value creation and margin stay visible on each row,
and the complete row is the disclosure target for the detailed calculation.
Missing market depth never becomes zero.

See `Documentation/ACCEPTANCE.md` for the exact split between implemented and
tested behavior, current-service verification and owner acceptance.
