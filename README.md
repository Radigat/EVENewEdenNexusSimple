# EVE New Eden Nexus - Assets, Industry, Markets

Native lokale macOS-App für Assets, Industrieplanung und Märkte in EVE Online.
Einziger aktiver Projektstand: `/Users/svenstolze/Developer/EVE New Eden Nexus - Assets, Industry, Markets`. Entwicklung mit Codex und Claude; Modellvorgaben je Werkzeug in [MODEL_POLICY.md](MODEL_POLICY.md).

Der zuletzt verwendete lokale App-Stand einschließlich aller vorhandenen Änderungen,
Tests und `EVEStaticDataKit` ist die aktive Codebasis. Andere Entwicklungslinien
sind vollständig als Quellen archiviert. Ihre fehlenden vorhandenen Fachabläufe sind über Adapter
in die aktive App integriert; bestehende Berechnungsregeln bleiben maßgeblich.

Aktueller Umfang und Entscheidungen: [Fachliche Konsolidierung](Documentation/Consolidation/FUNCTIONAL_CONSOLIDATION.md).
Prüfnachweise: [Aktuelle Verifikation](Documentation/Consolidation/FUNCTIONAL_VALIDATION.md).

| Dokument | Verbindlicher Inhalt |
| --- | --- |
| [PROJECT_STATE.md](PROJECT_STATE.md) | Ist-Stand, Verifikation und offene Grenzen |
| [PRODUCT.md](PRODUCT.md) | vollständig erhaltene aktuelle Funktionsbeschreibung |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Komponenten und Fachverträge |
| [AGENTS.md](AGENTS.md) | Arbeitsregeln und ein aktiver Stand (für Claude über [CLAUDE.md](CLAUDE.md) eingebunden) |
| [WORKFLOW.md](WORKFLOW.md) | Build, Tests und Git |
| [MODEL_POLICY.md](MODEL_POLICY.md) | Modellvorgaben je Werkzeug und freigabepflichtige Eskalation |
| [ROADMAP.md](ROADMAP.md) | Konsolidierung abgeschlossen; Weiterentwicklung auf Auftrag |
| [Konsolidierung](Documentation/Consolidation/DECISIONS.md) | Herkunft, Auswahl und Konflikte |
| [Archiv](_archive/README.md) | gesicherte Altstände und Wiederherstellung |

## Öffnen und prüfen

Voraussetzungen: macOS 14+, Swift 6 und Xcode. Das vorhandene Projekt direkt öffnen:

```sh
open EVENexusSimple.xcodeproj
swift test
swift test --package-path Packages/EVEStaticDataKit
xcodebuild -project EVENexusSimple.xcodeproj -scheme EVENexusSimple \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/eve-nexus-build test CODE_SIGNING_ALLOWED=NO
```

Das App-Produkt trägt den neuen Projektnamen. Technische Target-/Modulnamen,
Bundle-ID, Keychain und Datenpfade bleiben zur Kompatibilität unverändert.
Die native Testsuite deckt das vorhandene Core-Testtarget ab; SwiftPM prüft zusätzlich
App-Tests. Für vollständig isolierte Prüfläufe siehe [WORKFLOW.md](WORKFLOW.md).
`project.yml` nicht blind regenerieren: das vorhandene Xcode-Projekt enthält
zusätzliche historische Einstellungen; XcodeGen ist hier nicht installiert.

SSO-Callback bleibt `http://localhost:52722/callback`. Lokale Konfiguration,
SDE, ESI, Laufzeit und bekannte fachliche Grenzen stehen in [PRODUCT.md](PRODUCT.md).
