# EVE-Itemdarstellung

Stand: 14. August 2026

## Vertrag

`EVEItemText` ist die gemeinsame SwiftUI-Darstellung für einen aufgelösten
EVE-Typnamen mit positiver Type-ID. Sie kombiniert:

- `EVEItemIcon` für das kleine Vorschaubild;
- `EVEEntityText` für den exakten sichtbaren und kopierbaren Namen.

Das Icon wird gemäß der
[offiziellen EVE-Image-Server-Dokumentation](https://developers.eveonline.com/docs/services/image-server/)
über `https://images.evetech.net/types/{typeID}/icon?size=64&tenant=tranquility`
bezogen und abhängig vom Kontext mit 18 bis 28 Punkten dargestellt. Die
Type-ID bestimmt das Bild; Name, Gruppe oder Kategorie werden nicht zur
Bildsuche verwendet.

Die sichtbare fachliche Entität und die Type-ID müssen identisch sein:

- ein Produktname verwendet die Type-ID des produzierten Endprodukts;
- ein Blueprintname verwendet die Type-ID des Blueprints;
- ein Material- oder Strukturtyp verwendet seine eigene Type-ID.

Eine Type-ID eines Rohstoffs, Zwischenprodukts oder Blueprints darf deshalb
nicht neben dem Namen des Endprodukts erscheinen, auch wenn beide aus derselben
Planung oder Auswahl stammen.

## Zustände und Bedienung

- Während des Ladens erscheint ein neutrales lokales Item-Symbol.
- Kann das Bild nicht geladen werden, erscheint ein lokaler Bildfehler-
  Platzhalter; der Itemname und seine übrigen Fachdaten bleiben erhalten.
- Ungültige Type-IDs erzeugen keine URL. Hat eine ältere oder importierte
  Darstellung keine faktisch aufgelöste Type-ID, bleibt sie bei der
  Namensdarstellung ohne geratenes Bild.
- Das dekorative Icon ist für VoiceOver ausgeblendet. Der Name bleibt der
  zugängliche Kopier-Button mit lokalisiertem Erfolgs- oder Fehlerfeedback.
- Ein Bildklick wählt keine Zeile und löst keine fachliche Aktion aus. In
  Suchergebnis- oder Picker-Zeilen bleibt dagegen der umgebende Auswahl-Click
  maßgeblich; das dortige Icon ist rein visuell.

## Bestandsverlauf (seit 09.11.2026)

`EVEItemText` zeigt hinter dem Namen den gemeinsamen `MarketStockHistoryButton`
(Kurvensymbol). Er öffnet über den nächsten `.marketStockHistoryHost()` die
eine `MarketStockItemDetailView` mit den zentral gespeicherten Hub-Daten
([MARKTBESTAND_PLAN.md](MARKTBESTAND_PLAN.md), P6). Das Hauptfenster und
jedes Sheet installieren einen Host; ohne Host bleibt der Button verborgen.
Die Tagestabelle startet mit dem Home Hub; Handel übergibt den Ziel-Hub der
Route, Marktbestand den gewählten Hub. `showsMarketStockHistory: false` gilt
nur für Such- und Auswahlergebnisse, den Kopf des Verlaufs und Stellen, die den
gemeinsamen Button selbst platzieren (Handel nach dem Logbuch-Plus,
Marktbestand am Zeilenende). Besitzt eine Disclosure den Zeilenklick
(Reaktionskarten), liegt der Button mit dem transparenten Kopierziel darüber.
Regel: [AGENTS.md](../AGENTS.md), „Bestandsverlauf je Item“.

## Abdeckung

Die gemeinsame Darstellung ist für aufgelöste Items in Dashboard und
Mineralticker, Assets/Warehouse, Blueprints, Dashboard-Jobkarten, Planner und
Guided Production, Marktchancen und Produktionsbaum, Public Contracts,
Reaktionen, Moon-Materialanalyse, Net-Worth-Details sowie Produktionshistorie
eingebunden.
Service-Module, Rigs und SDE-Produktsucher zeigen ebenfalls das Type-Icon in
ihren Auswahlzeilen.

Rekursive Industriepläne speichern Rohstoffe und Zwischenprodukte vor ihrem
Endprodukt. `IndustryPlanSnapshot.topLevelProductNode(for:)` ermittelt deshalb
je Produktionsanfrage den produzierten Wurzelknoten, der von keinem anderen
Knoten derselben Anfrage als Kind referenziert wird. Planner-BPC/BPO-Zeilen,
historische Planner-Darstellung, Produktionsbuch, Produktionsentwürfe und
Produktionsübersicht verwenden gemeinsam diesen Knoten. Der erste beliebige
Knoten einer Anfrage darf nicht als Produkt-Type-ID dienen.

Persistenz-, SDE-, ESI-, Markt- und Kalkulationsverträge ändern sich dadurch
nicht. Die Bildanforderung ist eine getrennte UI-Netzwerkgrenze und ersetzt
keine fehlende Domänenauflösung.

## Nachweisgrenzen

Automatische Tests prüfen die kanonische Bild-URL, die Ablehnung ungültiger
Type-IDs und einen rekursiven Plan, dessen erster Knoten ein Rohstoff, dessen
produzierter Wurzelknoten aber das sichtbare Endprodukt ist. Der vollständige
SwiftPM-Lauf kompiliert die App einschließlich der betroffenen SwiftUI-Bereiche
und prüft Core und App. Eine isoliert gebaute
Vorschau wurde im dunklen Erscheinungsbild für Dashboard, Main-Hub-Chancen und
das Planner-Produktionsbuch visuell geprüft: Die geladenen Bilder blieben
kompakt und erkennbar, die Namen weiterhin anklickbar und die Tabellenzeilen
stabil. Im Produktionsbuch wurden fünf vorhandene historische Endprodukte mit
unterschiedlichen, zu ihren produzierten Type-IDs gehörenden Bildern geprüft.
Reales Langzeit-Cache- und Offline-Verhalten, große scrollende Listen,
PNG-Export der Moon-Tabelle, das helle Erscheinungsbild, Tastatur, VoiceOver und
Owner-Abnahme müssen getrennt geprüft werden.
