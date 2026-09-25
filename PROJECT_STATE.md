# EVE New Eden Nexus - Assets, Industry, Markets – Projektstatus

Stand: 25.09.2026. Standardmodell: **Astra Medium**.
Es gibt nur einen aktiven Projektstand: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.
Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Übernommener Ist-Stand

Aktive Basis: vollständiger lokaler Simple-Arbeitsbaum auf
`e3bc7a900e89cc8f39f10f9795c9f1a7537056da`, einschließlich 83 Statuszeilen
mit bereits vorhandenen Änderungen. Der Fensterlayout-Fix vom 24.09. und sein
Regressionstest bleiben erhalten. Keine Änderung von Rechenregeln, Persistenz,
SSO, ESI, SDE oder Featurefreigaben.

Das aktuelle Vollbackup enthält keine exklusiven fachlichen Dateien: 153 identisch,
fünf abweichend. Die aktuelle Fensterkorrektur und Xcode-Dateizuordnung haben Vorrang.
Der Nexus-Altstand (`058d4942d01782ad22a223ba6cd499d984ebe978`, 266 Statuszeilen)
ist einschließlich untracked Dateien, Projektbuch, 28 Schemafassungen, Tests und
Dokumentation vollständig als Legacy-Quelle gesichert.

Die organisatorische Zusammenführung ist von funktionaler Verschmelzung zu unterscheiden:
Die abweichenden Legacy-Modelle für Projektbudget, Reservierungen und bestätigte
Chargen-/Wallet-Verkaufszuordnungen sind **nicht** in die aktive App integriert.
Sie werden nicht als neue oder bereits äquivalente App-Funktionen ausgegeben.
Details und fachliche Konflikte: [Komponentenvergleich](Documentation/Consolidation/COMPONENTS.md).

## Verifikation

Maßgeblich ist der [Prüfbericht vom 25.09.2026](Documentation/Consolidation/VALIDATION.md).
Ältere Acceptance-Einträge bleiben datierte Nachweise. Nicht ausgeführte Live-Tests
oder visuelle Freigaben gelten nicht als bestanden.

## Verbleibende Grenzen

- Historischer Production-Tracker-Pfad ist lokal nicht vorhanden; kein eigenständiger
  Quellstand dieses Namens konnte übernommen werden.
- Nicht kompatible Legacy-Fachkomponenten bleiben archiviert. Eine Funktionsvereinigung
  würde neue Adapter, UI-/Datenmodelländerungen und Migrationen erfordern und wurde
  aufgrund des Auftrags nicht vorgenommen.
- ChatGPT-Projektanzeige und bereits installierte Alt-App sind separate Oberflächen;
  ihr tatsächlicher Endzustand wird im Abschlussbericht genannt. Die Repositorydateien
  behaupten keine globale Modellauswahl.
- Historische technische Namen und Logo-Artwork bleiben nachvollziehbare Ausnahmen;
  [Namensregister](Documentation/Consolidation/LEGACY_NAMES.md).
- Bekannte Produktgrenzen und ausstehende Fach-/Owner-Abnahmen aus PRODUCT und
  Documentation/ACCEPTANCE bleiben bestehen; Konsolidierung schließt sie nicht still.

## Verifizierter Abschluss der lokalen Konsolidierung

SwiftPM: 417 bestanden, 1 Skip. StaticDataKit: 7 bestanden, 1 Skip.
Xcode Debug: Build erfolgreich; 385 native Tests bestanden, 1 Skip.
Alle Skips betreffen ausdrücklich opt-in Real-SDE-Nachweise. Keine Testfehler.
Beide früheren Arbeitsordner sind in das dokumentierte Legacy-Archiv verschoben;
Quellhashes und Git-Zustände wurden bestätigt. Alle vorhandenen aktiven Fachquellen
und Tests sind erhalten. Eine fehlende native Testdateizuordnung wurde ergänzt.
Die vollständige funktionale Verschmelzung sowie die Sidebar-Umbenennung bleiben
die oben und im Prüfbericht offengelegten Grenzen. Keine Folgeentwicklung freigegeben.
