# Modellrichtlinie

Projekt: EVE New Eden Nexus - Assets, Industry, Markets

Aktuelle Regel: Es gibt nur einen aktiven Projektstand. Legacy-Projekte dienen
ausschließlich als Quelle für die Konsolidierung.

## Codex

Standardmodell: GPT-5.6 Sol, Reasoning-Stufe High. Die lokale Codex-Vorgabe ist
in `.codex/config.toml` hinterlegt.

## Claude

Seit 19.10.2026 wird das Projekt hauptsächlich mit Claude weiterentwickelt
(Einstieg über `CLAUDE.md`). Es gilt das in der jeweiligen Sitzung gewählte
Claude-Modell; eine projektweite feste Vorgabe gibt es derzeit nicht.

## Für alle Werkzeuge

Eine ausdrückliche Benutzeranweisung für die aktuelle Aufgabe hat Vorrang.
Frühere Modellstrategien in Archivmaterial sind außer Kraft.

Es gibt keinen automatischen Wechsel des Modells oder der Reasoning-Stufe. Falls
das Standardmodell für eine Aufgabe voraussichtlich nicht ausreicht, muss vor
jedem Wechsel nachgefragt werden. Die Nachfrage enthält zwei oder drei konkrete,
auf die Aufgabe zugeschnittene Optionen mit exaktem Modell und exakter
Reasoning-Stufe, kennzeichnet die Empfehlung und nennt kurz den relevanten
Qualitäts-, Latenz- oder Kosten-Trade-off. Erst nach der Freigabe wird mit der
ausgewählten Option fortgefahren.

Die Projektvorgabe ändert keine globalen App-Einstellungen. Legacy-Modellvorgaben
und dortige Agenten-/Kit-Aufträge werden nicht reaktiviert.
