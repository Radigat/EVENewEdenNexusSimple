# Legacy-Quellen – ausschließlich Archiv

Einziges aktives Projekt: **EVE New Eden Nexus - Assets, Industry, Markets**, Projektstamm eine Ebene oberhalb.
Alle Inhalte hier sind Quellen für die Konsolidierung; keine aktive App, kein
zweiter Workflow, kein automatisch auszuführender Prompt.

| Archiv | Inhalt |
| --- | --- |
| simple-current-source.tar.gz | vollständiger übernommener Simple-Quellarbeitsbaum vor Änderungen, 158 Dateien |
| nexus-legacy-source.tar.gz | vollständiger Nexus-Quellarbeitsbaum, 733 Dateien inklusive Dokumentation, Tests, Projektbuch und vorhandener Xcode-Archive |
| simple-backup-20260923-delta.tar.gz | fünf abweichende Backup-Dateien; übrige 153 bytegleich zum Simple-Quellarchiv |
| simple-duplicate-xcode-from-head.tar.gz | bereits zuvor gelöschtes zweites Simple-Xcode-Projekt aus ursprünglichem Git-HEAD |
| Optimierung-legacy.md | frühere Optimierungsliste, außer Kraft |

Prüfsummen: [SHA256SUMS](SHA256SUMS). Inventare, HEADs, Branches und getrennte
Git-Patches: [Herkunft](../Documentation/Consolidation/source-inventory.json).
Archive enthalten Quellmaterial, keine Build-Caches, Git-Metadaten, SwiftPM-Caches
oder persönlichen Xcode-Fensterzustände. Die originalen Ordner einschließlich
Git, Index, ignorierter Dateien und Build-Caches bleiben vollständig unter
`/Users/svenstolze/Documents/_archive/EVE-Nexus-Konsolidierung-2026-09-25/` erhalten.
Die Backup-Quelle unter Documents und das externe Vollbackup bleiben unverändert.

Wiederherstellung nur in einen gesonderten Legacy-Prüfordner: erst SHA-256 prüfen,
dann gewünschtes tar.gz entpacken. Für den exakten Backup-Quellstand erst das
Simple-Quellarchiv und danach das Backup-Delta entpacken. Nicht über den aktiven
Projektstamm oder produktive App-Daten entpacken. Es wird kein zweiter aktiver
Projektstand durch das Archiv freigegeben.

## Zusätzliche historische Nachweise

[Recovery-20260924](Recovery-20260924/README.md) enthält zwei unveränderte Berichte
aus der Wiederherstellung. Der alte Recovery-Arbeitsordner ist durch LEGACY.md markiert.
Index-/Arbeitsbaum-Patches im Konsolidierungsordner liegen als verlustfreie .patch.gz vor.
