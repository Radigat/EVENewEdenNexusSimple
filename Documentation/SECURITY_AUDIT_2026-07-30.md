# Security and robustness audit — 2026-07-30

## Result

The current source builds through Swift Package Manager and the native Xcode
project. The deterministic suite passes with 84 tests in 13 suites, and
`swift format lint --strict` reports no findings.

No known critical code-level finding remains open from this review. That is
not a claim that the app is attack-proof or distribution-ready. Release
hardening, local-data protection, migration recovery, and owner operating
acceptance remain separate work.

## Threat model used

The review assumed:

- malformed or repeated OAuth callbacks sent to the temporary loopback port;
- a malicious web page racing the real browser callback;
- oversized, paginated, inconsistent, or rate-limited ESI responses;
- malformed or unexpectedly large SDE and local pointer data;
- corrupt, negative, non-finite, or extreme user-entered quantities and money;
- repeated actions that grow the local database or consume memory;
- a user who confirms the wrong action or cannot recognize a partial result;
- theft of the Mac, access to the user's macOS account, or accidental
  publication of local credentials.

The app cannot protect its data after an attacker has full control of the
signed-in macOS account or the running process. Refresh tokens are kept in
Keychain, but character snapshots, wallet values, plans, and production
records are currently normal local SwiftData/SQLite data.

## Findings fixed in this review

| ID | Area | Change |
| --- | --- | --- |
| AUTH-01 | OAuth callback | Exact scheme/host/port/path checks, one-time and expiring authorization attempts, duplicate-query rejection, state binding, replay rejection, request-size limits, and loopback-peer checks replace crash-prone or ambiguous callback handling. |
| AUTH-02 | Tokens and JWT | Token/JWT sizes, claims, scopes, character IDs, expiry, JWKS response size, and identity-service hosts are bounded. Auth sessions use ephemeral, non-caching network sessions with timeouts. |
| PRIV-01 | Character removal | A destructive confirmation now deletes the local refresh token, character authorization/snapshots, and ESI metadata. The UI explicitly states that production records remain and EVE website access is not remotely revoked. |
| ESI-01 | Transport | Endpoint/query, response, and page-count limits were added. Changing pagination is rejected, private validators remain character-partitioned, and generic POST is no longer retried automatically. |
| INPUT-01 | User input | Production and manual-stock inputs now have byte, line, name, quantity, and aggregate limits. Invalid input is bounded before it is copied into diagnostics. |
| NUM-01 | Arithmetic | Reservation, industry, market, and production-overview calculations reject invalid values or use checked/saturating arithmetic instead of trapping on overflow or non-finite values. Production graph depth, node count, and material fan-out are bounded. |
| SDE-01 | Update safety | Active-pointer filenames and hashes are validated against traversal/tampering. Installation requires the newly fetched preview to exactly match the displayed preview. A schema-review requirement must now be explicitly confirmed after opening the CCP changelog; it is no longer hard-coded as accepted. |
| DATA-01 | Persistence | Repeated ESI syncs update the latest character/domain metadata instead of growing duplicate rows without limit. Existing duplicates are pruned during the next update. Settings and activation-pointer save failures are surfaced instead of silently ignored. |
| DATA-02 | Local files | Credential, signing, environment, Keychain, and local database artifacts were added to `.gitignore`. No real credential was found by the bounded source scan. |
| QA-01 | Code quality | Remaining strict Swift-format findings and avoidable force-unwrapping in the live acceptance runner were removed. |

## Verification evidence

- `swift test` with writable scratch and module caches:
  **84 tests in 13 suites passed**.
- `swift format lint --recursive --parallel --strict Sources Tests`:
  **passed with no findings**.
- `xcodebuild -project EVENexusSimple.xcodeproj -scheme EVENexusSimple
  -configuration Debug ... CODE_SIGNING_ALLOWED=NO build`:
  **BUILD SUCCEEDED**.
- The auth, ESI, test-surface, and update/version inventory scripts from the
  modular EVE skill suite were run read-only.
- `gitleaks` was not installed, so a real entropy/history secret scan was not
  completed. The repository also has no commit history yet.

Technical evidence does not replace live EVE verification or owner acceptance.
The existing live-service evidence remains in `ACCEPTANCE.md`.

## Open tasks

| Priority | ID | Task and acceptance condition |
| --- | --- | --- |
| P0 before distribution | SEC-OPEN-01 | Enable App Sandbox with the minimum network client/server entitlements, then test the loopback callback, Keychain access, SDE storage, and migration from the current non-sandbox Application Support location. Build with a stable Apple Development/Developer ID identity, enable hardened runtime, archive, notarize, and verify Gatekeeper. |
| P0 before distribution | SEC-OPEN-02 | Decide and document protection for private local snapshots and production data. Either rely explicitly on FileVault plus a protected macOS account, or implement application-level encryption with a Keychain-held key and tested backup/recovery. Verify behavior after device lock and under a second macOS user. |
| P0 before next push | SEC-OPEN-03 | A Git baseline now exists, but the worktree contains extensive owner changes. Before staging or pushing, obtain owner approval, inspect scope and ignore rules, stage selectively, and run Gitleaks against the worktree plus existing history. |
| P0 project hygiene | SEC-OPEN-04 | Confirm that `EVENexusSimple.xcodeproj` is the sole intended project, then remove or archive `EVENexusSimple 2.xcodeproj`. The older copy omits current sources and tests and can produce misleading builds. Do not delete it until a recoverable baseline exists. |
| P1 | SEC-OPEN-05 | Introduce explicit SwiftData schema versions, migration plans, and a non-destructive corrupted-store recovery screen. Test upgrade, interrupted migration, full disk, read-only disk, and rollback behavior. |
| P1 | SEC-OPEN-06 | Replace post-download body-size checks for ESI and SSO metadata/token calls with streaming/delegate limits that cancel chunked responses before the whole body is buffered. Keep the current limits as a second defense. |
| P1 | SEC-OPEN-07 | Add a central ESI request budget using `X-ESI-Error-Limit-Remain` and `X-ESI-Error-Limit-Reset`, jittered backoff, and cancellation-aware scheduling. The current bounded retry policy is safe but not a complete multi-request coordinator. See the official [ESI rate-limit documentation](https://developers.eveonline.com/docs/services/esi/rate-limiting/). |
| P1 | SEC-OPEN-08 | Add disk-space preflight and an owner-visible retention/export policy for SDE backups, installation logs, plans, and production records. Never delete business records silently. |
| P1 owner acceptance | SEC-OPEN-09 | Exercise authorize, forged/wrong callback, timeout, reauthorization, sync-all, and disconnect with real characters. Confirm local records and Keychain entries disappear as described, then document the separate EVE website revocation procedure. |
| P1 owner acceptance | SEC-OPEN-10 | Run the pending keyboard, VoiceOver, rapid-click, offline, slow-network, port-in-use, sleep/wake, and app-termination tests. Confirm every partial/stale/forbidden state remains visible and no destructive action proceeds on a double click. |
| P2 | SEC-OPEN-11 | Replace remaining raw `String(describing: error)` UI fallbacks with stable user-safe codes plus a separate redacted diagnostic export. Ensure file paths, tokens, authorization codes, and private payloads never enter logs or screenshots. |
| P2 | SEC-OPEN-12 | Add fuzz/property tests for callback parsing, production input, SDE pointers, pagination headers, recursive planning graphs, and numeric boundaries. Add performance ceilings for 1,000 input rows and large but valid ESI/SDE fixtures. |

## Current security boundary

- EVE SSO uses Authorization Code with PKCE and validates the JWT locally
  against CCP metadata/JWKS. The official SSO guidance requires state, PKCE,
  signature, issuer, audience, and expiry validation:
  <https://developers.eveonline.com/docs/services/sso/>.
- Refresh tokens remain in macOS Keychain; access tokens exist only in process
  memory for their short lease.
- The callback listener exists only during authorization and accepts one valid,
  state-bound request on the configured loopback endpoint.
- ESI owns transport and provenance; SDE remains a separate update pipeline.
- Missing or forbidden private EVE data is not converted into an empty or zero
  business value.
- A local debug build is evidence that the code compiles. It is not a signed,
  notarized, sandboxed distribution artifact.
