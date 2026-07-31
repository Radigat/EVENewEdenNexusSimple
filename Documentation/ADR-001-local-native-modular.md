# ADR-001: Local native modular application

Status: accepted

EVE Nexus Simple uses Swift 6, SwiftUI and a macOS 14 deployment target. The
application target owns presentation and composition. `EVENexusCore` owns domain
contracts and orchestration. The vendored `EVEStaticDataKit` remains unchanged.

App records and update pointers are stored locally. Large static-data catalogs
are build-specific SQLite databases activated through a small pointer file.
Refresh tokens are stored exclusively in macOS Keychain. The preferred
implementation is the app-scoped Data Protection Keychain without a
user-presence requirement; local ad-hoc builds retain a legacy Keychain
compatibility path. Access-token leases are cached only in process memory.

Every saved plan records its SDE build, ESI compatibility date, snapshot IDs,
price timestamp and industry rule version so results remain reproducible.
