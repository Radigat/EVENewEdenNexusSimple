# Bewusst erhaltene Legacy-Bezeichnungen

Aktiver Projekt-/Produktname: **EVE New Eden Nexus - Assets, Industry, Markets**.

| Bezeichnung | Erhaltungsgrund |
| --- | --- |
| EVENexusSimple.xcodeproj / Scheme EVENexusSimple | technische Build-Einstiegspunkte; eine einzige aktive Projektdatei |
| EVENexusSimple, EVENexusSimpleApp, EVENexusCore, EVE_Nexus_Simple | Package-/Target-/Swift-Modulidentitäten, Imports und SwiftData-Laufzeitidentität |
| com.local.EVENexusSimple, EVENexusSimple.store, Refresh-Token-Service | bestehende Daten, Preferences, Keychain-Zugriff und Migrationen bewahren |
| EVE Nexus Simple in AppDefaults | historische Preferences-Domain als Migrationsquelle; nicht Projektname |
| EVE-Nexus-Simple in SourceState/SDELifecycleService und Vertragstest | bestehender HTTP-User-Agent; Netzwerkvertrag unverändert |
| de.newedennexus.tokens in optionalem Live-SDE-Script | bestehender Keychain-Kontaktschlüssel, kein Projektpfad; Script nicht ausgeführt |
| new-eden-nexus-simple-logo*.png, vorhandenes Logo-Artwork | vorhandene Bildressourcen beibehalten; Neugestaltung nicht beauftragt |
| Git-Remote EVENewEdenNexusSimple | vorhandenes Remote bleibt erreichbar; kein Auftrag zum externen Repository-Rename |
| Alte Namen/Pfade in dev-diary, Acceptance, Security-Audit, Quellinventaren, Patches und Archiven | datierte Herkunft und Wiederherstellbarkeit; keine aktiven Arbeitswurzeln |

Der installierte Alt-Build unter `~/Applications/EVE Nexus Simple.app` ist ein
separates Installationsartefakt. Die Konsolidierung überschreibt weder diese App
noch Benutzerdaten. Der neu gebaute App-Produktname steht im Prüfbericht.
