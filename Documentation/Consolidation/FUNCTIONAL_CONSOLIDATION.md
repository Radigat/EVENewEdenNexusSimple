# Fachliche Konsolidierung – 25.09.2026

Projekt: **EVE New Eden Nexus - Assets, Industry, Markets**. Standardmodell: **GPT-5.6 Sol High**.
Es gibt nur einen aktiven Projektstand. Legacy-Projekte dienen ausschließlich als Quelle für die Konsolidierung.

## Grundlage und Herkunft

Aktiver Projektordner: `/Users/svenstolze/Documents/EVE New Eden Nexus - Assets, Industry, Markets`.
Branch: `consolidation/2026-09-25-single-source`. Ausgangs-HEAD: `182f1a936950632bc84641904150c4c3e7782a55`.
Der aktuelle App- und Rechenkern bleibt maßgeblich. Die archivierte ältere Entwicklungslinie liefert
Projektlebenszyklus, manuelle Lager, CSV-Verträge, Reservierungen, Preisprofile, Einkaufsfortschritt,
Belegzuordnung und Sicherungsabläufe. Ihr separater App-/Domain-/Persistence-Stack wird nicht eingebaut.
Der CSV-Dateileser und -Parser einschließlich acht Tests sowie der exakte ISK-Werttyp sind direkt adaptiert;
die übrigen Dienste verbinden diese Fachverträge mit den vorhandenen aktiven Typen und Diensten.

Die Simple-Basis stammt aus `e3bc7a900e89cc8f39f10f9795c9f1a7537056da` einschließlich ihres damaligen
Arbeitsbaums. Die ältere Nexus-Quelle stammt aus `058d4942d01782ad22a223ba6cd499d984ebe978` einschließlich
uncommitteter Dateien. Beide bleiben unter `Documents/_archive/EVE-Nexus-Konsolidierung-2026-09-25/` erhalten.
Das vollständige Backup vom 23.09. bleibt ebenfalls unverändert erhalten. Es enthält 153 identische und
fünf abweichende Dateien, aber keine exklusiven Fachquellen. Archivregister, Herkunftsinventare und
ursprüngliche Patches bleiben unter `_archive/` bzw. diesem Dokumentverzeichnis erhalten.

## Bedienung und Übernahmen

**Fertigungsprojekte sind Datensätze in derselben App, keine weiteren Projektordner.**
Projektwahl und -einstellungen sind direkt in den Planner eingebettet. Nach einer Berechnung liegen
Reservierungen bei der Lagerverwendung sowie Einkaufsbudget und -fortschritt bei der Einkaufsliste.
Warehouse, Blueprints und Produktionsübersicht öffnen nur ihre jeweils passenden Fachdialoge für
manuelle Lager, Wissenschaftsaufträge beziehungsweise Verkaufsbelege. Preisprofile sind direkt in
den Markteinstellungen integriert; lokale Sicherung, Wiederherstellung und Diagnose liegen in den
allgemeinen Einstellungen. Der frühere bereichsumschaltende Projektverwaltungsdialog ist entfernt.

- Projekte: stabile UUID, getrennte Eingaben/Handbestände/Blueprint-Versorgung, Status, Duplizieren,
  Archivieren/Wiederherstellen, Priorität, Lagerfreigaben, Ausschlüsse, Gesamtmengenlimits und Preisprofil.
  Duplikate übernehmen weder Reservierungen noch alte Ergebnis-Snapshots, Einkaufsabweichungen oder Belege.
  Aktive Reservierungen verhindern das Archivieren. Ohne aktives Fertigungsprojekt wird nicht gerechnet.
- Manuelle Lager: dauerhafte Mengen nach veröffentlichter CCP-Typ-ID, Notizen, Umbenennen und reversibles
  Archivieren. Eine Eingabe ersetzt eine Menge. Namen sind normalisiert und auch über Archive eindeutig.
  Manuelle Lager werden nur ausdrücklich zugeschaltet; bereits in ESI enthaltene Bestände dürfen nicht
  nochmals als unabhängiges Lager eingetragen werden. Planner-Handeingaben behalten ihren bisherigen Vorrang.
- CSV: UTF-8/UTF-16-BOM/Windows-1252/Latin-1, Komma/Semikolon/Tabulator, gequotete und mehrzeilige Felder;
  16 MiB, 100.000 Zeilen, 64 Spalten. Spaltennamen sind zuordenbar. Ersetzen/Überspringen ist global und
  je Typ wählbar. Fehler blockieren standardmäßig; ausdrücklich ausgelassene ungültige Zeilen werden
  protokolliert. Bei doppelten Typen werden beide Zeilen abgelehnt bzw. ausgelassen, niemals summiert.
  Vorschau, Übernahme und Bericht gehören zu einer Revision und einem Speichervorgang. Berichte enthalten
  Dateiname, Hash, Format und Zeilenergebnisse, keinen ursprünglichen Dateipfad.
- Verfügbarkeit: bestehende Schutzmengenberechnung zuerst, bestätigte Reservierungen anderer Projekte danach.
  Reservierungen sind nach Herkunft getrennt. Ein ohne ESI gerechneter Plan reserviert keine ESI-Mengen. Eine Mengenobergrenze gilt einmal über alle gewählten Quellen.
  Verbrauch/Freigabe verändert den physischen Bestand nicht. Ablaufdaten sind Hinweise. Konflikte aus
  Bestandsverlust, reduziertem Bedarf, Ausschlüssen oder entfernten Lagerfreigaben ergeben einen stabilen
  Prioritätsvorschlag, der ausdrücklich bestätigt werden muss. Fehlende ESI-Daten sind kein leeres Lager.
- Preise/Einkauf: exakte positive Centbeträge, Gültigkeit mit ausgeschlossenem Endzeitpunkt, CSV und
  bestätigte Übernahme der gewichteten Preise eines gespeicherten Plans. Profile gelten ausdrücklich für
  das Einkaufsbudget und werden in den bestehenden Markteinstellungen gepflegt; es werden keine fiktiven
  Marktorders erzeugt. Offene Mengen, Zielabweichungen und
  gekaufte Mengen sind getrennt. Einkaufsfortschritt erzeugt keinen Lagerzugang. CSV-/Textausgabe kann alle
  aktiven Projekte nach Typ zusammenfassen. Logistik-/Installationsbeträge sind ausdrücklich beschriftete
  Ersatzwerte, keine zusätzlichen Aufschläge. Das Budget ist keine alternative Gewinnrechnung.
- Wissenschaft: vorhandene SDE-Aktivitäten, Skillanforderungen, Decryptoren und Fachrechner werden verwendet.
  Geprüfte Anlage am Blueprint-Standort, frische Charakter-/Blueprintdaten und vollständige Kosten sind
  Voraussetzungen. Copying liefert konkrete Kopien/Runs; Forschung liefert künftig geplantes ME/TE;
  Invention trennt Erwartung und Konfidenzplan. Input-BPC-Runs werden projektübergreifend berücksichtigt;
  geplante Kopien sind als Invention-Eingang wählbar. Aufträge und ihre Versorgung sind gespeichert und
  kontrolliert archivierbar; abhängige Invention verhindert vorzeitiges Archivieren der Kopie.
  Die Fertigung übernimmt die konkreten Effizienzen und Kosten. Wissenschaftszeiten werden konservativ
  sequenziell vor der Fertigung eingeplant. Bei unveränderten Eingaben ohne solche Aufträge bleiben die
  bisherigen Rechenwege unverändert. Ingame-Jobs werden niemals gestartet, Assets nicht vorweg geändert.
- Produktionsbuch: aktuelle Nummerierung, Zeilen und gespeicherte Plan-Snapshots bleiben erhalten. Beim
  ausdrücklichen Beginn eines Belegvorgangs wird der Kostenstand unveränderlich gesichert; vorher bleibt
  die bisherige Kostenbearbeitung möglich. Verkäufe können manuell, aus frischen Wallet-Transaktionen
  oder durch ausdrückliche Bestätigung eines positiven Journalbetrags erfasst werden. Journalbelege
  benötigen eine bestätigte Artikelmenge; Markt-Transaktionsjournalzeilen sind ausgeschlossen, um denselben
  Marktverkauf nicht doppelt zu importieren. Teilbeträge werden centgenau verteilt, der Rundungsrest bleibt
  beim abschließenden Teil. Beleg-ID, Restmenge und Produktionsmenge begrenzen jede Zuordnung. Beim Wechsel
  in den Belegmodus werden frühere manuelle Verkaufswerte gesichert; die aktuelle Zeile folgt ausschließlich
  den Zuordnungen. Historische Daten bleiben nach Trennen eines Charakters erhalten. Die bestehende
  Gebühren-/Gewinnberechnung bleibt maßgeblich; belegte Erlöse werden zusätzlich ausdrücklich brutto gezeigt.
- Sicherung: Die Bedienung liegt in den allgemeinen Einstellungen. Konsistente SQLite-Online-Snapshots
  einschließlich WAL, Prüfsummen, Manifest und verifizierte
  Wiederherstellung beim nächsten App-Start. Vorher entstehen eine zusätzliche Sicherung und ein erhaltener
  vorheriger Datenordner. Die aktuelle Familie ist `com.local.EVENexusSimple`, das Paket `.nexusbackup`.
  Alte Nexus-Backups und künftige unbekannte Schemas werden nicht still importiert. Diagnoseexporte enthalten
  Versionen und Mengen, keine Namen, IDs, Pfade, Kontakte oder Tokens. Keychain-Geheimnisse werden nicht gesichert.

## Daten- und Schnittstellenvertrag

SwiftData V3 ergänzt ausschließlich `StoredConsolidationWorkspace`. Die V1-/V2-Modelle bleiben unverändert.
Der neue Datensatz enthält einen versionierten, atomar gespeicherten Verbund mit stabilen verknüpften
Identitäten; die Revision schützt Vorschauen vor zwischenzeitlichen Änderungen. Bestehende Drafts,
aktive und inaktive Pläne sowie Produktionszeilen werden nicht entfernt. Nur der bisherige Arbeitsentwurf
und aktive Plan werden dem ersten Fertigungsprojekt zugeordnet. Inaktive Pläne bleiben Historie.
Die Initialisierung ist wiederholbar ohne Doppelanlage. Originale gespeicherte Snapshot-Bytes bleiben erhalten.

`ConsolidationWorkspace`/`ConsolidationPreview` im bestehenden Kern bilden die neuen Fachgrenzen;
`ConsolidationController` ist der SwiftData-Adapter. CSV-, Sicherungs- und Wissenschaftsadapter verwenden
bestehende Dienste. Die vorhandenen Planner-Schnittstellen erhalten optionale Stock-Adapter;
die optionale Invention-Dauer bleibt mit alten Snapshots decodierbar. Es gibt keine zweite SSO-/ESI- oder
SDE-Implementierung. Bundle-ID, Swift-Module, Callback, Schlüsselbunddienste und Datenpfade bleiben stabil.

## Bewusste Auflösung der Widersprüche

- Aktuelle Berechnung, Rundung und Schutzmengen haben Vorrang vor abweichenden Legacy-Formeln.
  Neue exakte Belegbeträge führen zu keiner globalen Umstellung bisheriger Double-Berechnungen.
- Die vorhandene durchgehende Produktionsnummerierung hat Vorrang vor einer konkurrierenden Jahreszählung.
  Es gibt keine zweite Chargentabelle und keine nachträgliche Umnummerierung.
- Kosten-/Belegzuordnung lebt im bestehenden Produktionsbuch. Zurückgezogene Projektfinanz- und
  Gewinn-/ROI-Ansichten werden nicht wiederhergestellt. Bestehende aktuelle Gewinnanzeigen bleiben erhalten.
- Alte Datenbanken werden nicht eingelesen. Eine Verbindung ihrer Schemaversionen 1–28 mit der aktiven
  Migrationskette wäre ein anderer Auftrag und ist ausdrücklich ausgeschlossen.
- Nur geplante Metenox-, Statistik-, Cloud-, PI- und Distributionsvorhaben bleiben Archivmaterial.
  Bereits vorhandene aktuelle Logistik-, Markt-, Reaktions- und Corporation-Funktionen bleiben erhalten.
- Die aktuelle Oberfläche ersetzt die alte projektzentrierte App-Hülle. Historische Architektur-/UI-Tests,
  die entfernte Ansichten verlangen, sind keine wieder einzuführenden Funktionen. Der begrenzte aktuelle
  Legacy-Testlauf ergibt 715 bestandene Fälle und einen alten Oberflächentest mit sieben Assertions;
  [Einzelbewertung und Compilergrenze](LEGACY_TEST_DISPOSITIONS.md) sind dokumentiert. Fachlich relevante
  Parser-/Betrags- und Lebenszyklusfälle sind in die aktiven Tests übernommen.

## Nachweise und Grenzen

Vollständige Feature-Zuordnung: [FEATURE_COVERAGE.md](FEATURE_COVERAGE.md).
Aktuelle Build-, Test-, Pfad- und Git-Nachweise: [FUNCTIONAL_VALIDATION.md](FUNCTIONAL_VALIDATION.md).
Der ursprüngliche organisatorische Checkpoint bleibt in [VALIDATION.md](VALIDATION.md) historisch nachvollziehbar.
Reale SDE-/ESI-/SSO- und Eigentümerabnahmen sind von synthetischen Tests und dem isolierten UI-Sichttest getrennt.
Der produktive Benutzerbestand und die bereits installierte Alt-App werden durch die Prüfungen nicht ersetzt.
