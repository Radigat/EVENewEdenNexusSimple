# Invention skill matrix contract

## Ownership and sources

- `eve-static-data-kit` and the target SQLite adapter supply every published
  type in the SDE `Skill` category and `Science` group.
- `eve-character-kit` supplies immutable per-character skill snapshots from
  `esi-skills.read_skills.v1`.
- `eve-industry-kit` composes the cross-character readiness matrix.
- `eve-ui-kit` presents the matrix and refresh command without handling tokens
  or calling ESI directly.

The target persists the encoded `CharacterCapabilitySnapshot` beside each
stored authorization snapshot. Refresh tokens remain Keychain-only.

Every stored connected character receives a matrix column, even when its skill
snapshot is missing or cannot currently be refreshed. Additional columns
remain available through horizontal scrolling. The complete row containing the
chevron and title is an accessible disclosure button, not only the chevron.

## Level semantics

- A missing skill in a complete `fresh` ESI skill snapshot is level 0.
- A missing skill in `partial`, `stale`, `forbidden` or `unavailable` data is
  unknown.
- A connected character without any capability snapshot remains visible with
  every level unknown.
- The UI displays unknown explicitly and never converts it to level 0.

All SDE Science skills are displayed. Skills whose names identify Encryption
Methods, Engineering, Physics or Technology are highlighted for the broad
readiness comparison.

## Readiness conclusion

The conclusion ranks characters by average known level across the highlighted
invention-related skills, then by number of trained relevant skills. It is a
breadth indicator, not an exact invention chance.

An exact chance requires a concrete invention activity with its base
probability, the blueprint's encryption and two science skills, their character
levels, and an optional decryptor. Until that activity contract is implemented,
the UI states this limitation beside the conclusion.
