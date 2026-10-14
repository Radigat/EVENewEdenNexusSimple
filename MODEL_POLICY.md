# Modellrichtlinie

Projekt: EVE New Eden Nexus - Assets, Industry, Markets

Standardmodell: GPT-5.6 Sol High

Aktuelle Regel: Es gibt nur einen aktiven Projektstand.

Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

Diese Festlegung gilt für ChatGPT, Work und Codex. GPT-5.6 Sol ist das Modell,
High die Reasoning-Stufe. Die lokale Codex-Vorgabe ist zusätzlich in
`.codex/config.toml` hinterlegt. Frühere Modellstrategien in Archivmaterial sind
außer Kraft. Eine ausdrückliche Benutzeranweisung für die aktuelle Aufgabe hat
Vorrang.

Es gibt keinen automatischen Wechsel des Modells oder der Reasoning-Stufe. Falls
GPT-5.6 Sol High für eine Aufgabe voraussichtlich nicht ausreicht, muss vor jedem
Wechsel nachgefragt werden, welches Modell verwendet werden darf. Die Nachfrage
enthält zwei oder drei konkrete, auf die Aufgabe zugeschnittene Optionen mit
exaktem Modell und exakter Reasoning-Stufe, kennzeichnet die Empfehlung und nennt
kurz den relevanten Qualitäts-, Latenz- oder Kosten-Trade-off. Erst nach der
Freigabe wird mit der ausgewählten Option fortgefahren.

Die Projektvorgabe ändert keine globalen App-Einstellungen. Eine bereits laufende
Sitzung kann ihre beim Start gewählte Konfiguration beibehalten; neue Aufgaben im
vertrauten Projekt verwenden die Projektkonfiguration, sofern sie nicht ausdrücklich
überschrieben wird. Es gibt keinen automatischen Folgeauftrag.

Die fachliche Zusammenführung verwendet denselben Standard. Legacy-Modellvorgaben
und dortige Agenten-/Kit-Aufträge werden nicht reaktiviert. Der Abschlussbericht beendet den Auftrag.
