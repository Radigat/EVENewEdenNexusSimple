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

**Assets & Warehouse** combines the stored asset snapshots of all synchronized
characters. Locations are shown first, each character owner expands below the
location, and the owner's contents retain their inventory flags. Set a target
quantity for any SDE item to protect a minimum combined stock. The Planner can
use only the quantity above those targets and shows warehouse quantity, target,
allocated stock and the remaining production need beside every material. Run
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
Unless disabled, the Planner uses the combined all-character warehouse for
manufacturing and reaction material allocation. Manual stock remains an
explicit per-calculation override. The shared pool does not imply that items
have been moved between stations; logistics remain an owner decision. Material
costs separately show quantities to buy and quantities consumed from warehouse
or manual stock. Consumed stock remains included in material and total
production cost at its current Jita replacement value; it is not treated as
free merely because it is already owned.
The result groups true raw inputs by their SDE source category at the top and
keeps producible materials, including intermediates and reactions, in a
separate section below.
**Copy for EVE Multibuy** copies only materials with a positive purchase
quantity as plain `Item name Quantity` lines. Paste the result into EVE's
Multibuy **Import from Clipboard** action.
**Record production** appends one row per produced item to the
**Production Overview**, following the `Produktionsübersicht` worksheet in
`EVE-indu- Delve.xlsx`. The Planner shows the five newest rows; the full
overview contains the same 21 business columns from number and date through
material, index, blueprint and market costs to projected and real profit.
Blueprint cost, sale price per unit and sold units remain editable after
recording; calculated values update from those inputs while unresolved source
costs—including an unentered BPO/BPC cost—stay visibly unavailable.
The active Planner also separates system-index cost, Facility Tax, SCC, Alpha
surcharge, Sales Tax and Broker Fee. Optional inbound and outbound logistics
split oversized routes into whole-item contracts. Each contract uses SDE
packaged volumes, its allocated Jita replacement collateral, the larger of the
configured m³ charge or 0.5% collateral, and its own million-ISK upward
rounding.

Top-level production lines may append `BPC <total ISK>` or
`BPO <allocated ISK>` after Product, Want, ME and TE. BPC is treated as a
consumed copy acquisition cost; BPO is an owner-entered allocation for the
reusable original. Both are shown separately and included in total cost,
profit, margin and ROI.

See `Documentation/ACCEPTANCE.md` for the exact split between implemented and
tested behavior, current-service verification and owner acceptance.
