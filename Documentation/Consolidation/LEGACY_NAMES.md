# Bewusst erhaltene Legacy-Bezeichnungen

Aktiver Projekt-/Produktname: **EVE New Eden Nexus - Assets, Industry, Markets**.

Aktueller Abschlussnachweis: [FINAL_AUDIT_2026-10-14.md](FINAL_AUDIT_2026-10-14.md).

| Bezeichnung | Erhaltungsgrund |
| --- | --- |
| EVENexusSimple.xcodeproj / Scheme EVENexusSimple | technische Build-Einstiegspunkte; eine einzige aktive Projektdatei. `project.yml` beschreibt die Grundstruktur, ist aber ohne nachgewiesene XcodeGen-Reproduktion nicht alleinige Quelle der Projektdatei |
| EVENexusSimple, EVENexusSimpleApp, EVENexusCore, EVE_Nexus_Simple | Package-/Target-/Swift-Modulidentitäten, Imports und SwiftData-Laufzeitidentität |
| com.local.EVENexusSimple, EVENexusSimple.store, Refresh-Token-Service | bestehende Daten, Preferences, Keychain-Zugriff und Migrationen bewahren |
| EVE Nexus Simple in AppDefaults | historische Preferences-Domain als Migrationsquelle; nicht Projektname |
| EVE-Nexus-Simple in SourceState/SDELifecycleService und Vertragstest | bestehender HTTP-User-Agent; Netzwerkvertrag unverändert |
| de.newedennexus.tokens in optionalem Live-SDE-Script | bestehender Keychain-Kontaktschlüssel, kein Projektpfad; Script nicht ausgeführt |
| new-eden-nexus-simple-logo*.png, vorhandenes Logo-Artwork | vorhandene Bildressourcen beibehalten; Neugestaltung nicht beauftragt |
| Git-Remote EVENewEdenNexusSimple | vorhandene technische Repository-Adresse bleibt erreichbar; die GitHub-Beschreibung trägt den kanonischen Projektnamen |
| Alte Namen/Pfade in dev-diary, Acceptance, Security-Audit, Quellinventaren, Patches und Archiven | datierte Herkunft und Wiederherstellbarkeit; keine aktiven Arbeitswurzeln |

Der installierte Alt-Build unter `~/Applications/EVE Nexus Simple.app` ist ein
separates Installationsartefakt. Die Konsolidierung überschreibt weder diese App
noch Benutzerdaten. Der neu gebaute App-Produktname steht im Prüfbericht.

Das frühere `EVENexusSimple 2.xcodeproj` ist nicht aktiv. Es wurde im
Konsolidierungs-Checkpoint `182f1a9` aus dem Arbeitsbaum entfernt und bleibt im
Archiv `_archive/simple-duplicate-xcode-from-head.tar.gz` wiederherstellbar.


Nach der fachlichen Zusammenführung wurden auch die sichtbaren Berechtigungserklärungen in beiden
Sprachen umgestellt. Alte Namen in Portierungs-Kommentaren und im Test für das abgelehnte fremde
Sicherungsformat bleiben absichtliche Herkunfts-/Negativtestbezeichnungen. Die ChatGPT-Projektanzeige
„EVE New Eden Nexus“ bleibt vom Repository getrennt; sie wird hier nicht als zweiter aktiver Codebestand behandelt.
