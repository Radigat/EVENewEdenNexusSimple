# Plan: Doktrin-Bedarf

Stand: 26.11.2026 · Status: **implementiert, automatisch geprüft, Import mit
echter Wiki-Sitzung in der App geprüft**. Die Tabelle mit Marktdaten eines
echten Home Hubs und die Eigentümerabnahme sind offen, siehe Abschnitt F.

Der Eigentümer möchte eine eigene Seite, auf der er sieht, welche Items und
Schiffe die Allianz-Doktrinen am Home Hub brauchen, wie schnell sie sich
verkaufen, wie lange der Bestand reicht und was gebaut werden muss. Je Item
zeigt eine Schnellkalkulation, ob Bauen oder Import vom Main Hub (Jita)
günstiger ist. Vorbild war die Kachel „Doctrine stock at UALX-3“ von Keelworks
(Eigentümer-Bild).

## A. Entscheidungen des Eigentümers (25.11.2026)

| Thema | Entscheidung |
|---|---|
| Fit-Quelle | Import aus dem Brave-Wiki (Mitgliederbereich) per Login in der App |
| Wiki-Sitzung | bleibt gespeichert wie in einem Browser; „Abmelden“ löscht sie. Befund 26.11.2026: Wiki und Brave Core setzen nur Sitzungs-Cookies, die Sitzung endet deshalb mit der App; neu anmelden kostet einen Klick, wenn EVE SSO das Konto kennt. Der Eigentümer hat die angepassten Texte am 26.11.2026 freigegeben. |
| Aktualisieren | nur per Knopf „Aus Wiki aktualisieren“ |
| Sollbestand | ein Soll je Doktrin; es gilt streng für jedes Fit der Doktrin, Varianten eingeschlossen |
| Tabellenumfang | alle Fits des Wikis zählen für „Fits“ (wie im Bild); der Bedarf kommt nur aus Doktrinen mit Soll |
| Toter Abschnittsanker | die Doktrin bekommt alle Fits der verlinkten Schiffsseite, dazu ein Hinweis |
| Optionale Schiffe | Fits aus „Other ships you can use“ zählen wie Kern-Fits |
| Verkäufe/Tag | zwei Spalten: ESI-Regionshistorie (30 Tage) und Home-Hub-Bestandshistorie; Reichweite und Fehlmenge rechnen mit der Region |
| Importpreis | Sofortkauf zum niedrigsten Sell am Main Hub plus Transport der Etappe Main → Home |
| Nicht baubare Items | bleiben in der Tabelle, nur mit Import-Rechnung |
| Name und Platz | „Doktrin-Bedarf“ (englisch „Doctrine stock“), Seitenleiste direkt unter Marktbestand |

Von Claude festgelegt (zur Abnahme): Filter „Alle / Rümpfe / Module & Sonstiges
/ Munition & Ladungen / Drohnen“ nach SDE-Kategorie; Standardsortierung
Reichweite aufsteigend (ausverkauft zuerst); eine geladene Ladung
(`Modul, Ladung`) zählt je Modul einmal, weil EFT die Lademenge nicht nennt;
Gleichstand Bauen/Import empfiehlt Import; die Baukosten gelten für die
Fehlmenge, mindestens einen Lauf, mit den ME/TE-Standards der Hub-Chancen.

## B. Wiki-Quelle

- Wiki: `https://wiki.bravecollective.com` (DokuWiki, Login über Brave Core
  und EVE SSO). Doktrinen: Namensraum `member:alliance:military:doctrines`
  ohne die Übersicht `start`. Fits: Schiffsseiten in
  `member:alliance:military:doctrines:ships`.
- Verzeichnis: `/?idx=<Namensraum>`; gezählt werden Links auf bestehende Seiten
  (`wikilink1`) direkt in diesem Namensraum.
- Seiteninhalt: `?do=export_raw` (Klartext). Eine Antwort ohne `text/plain`
  (z. B. eine Login-Seite) gilt als nicht lesbar. Ist das Doktrin-Verzeichnis
  leer oder keine Seite lesbar, meldet der Import „erneut anmelden“.
- Ein Fit ist ein `<code>`-Block, dessen erste Zeile `[Rumpf, Fitname]` ist.
  Blöcke ohne diesen Kopf (Refits) zählen nicht. `/* … */`-Kommentare zeigt das
  Wiki nicht; ihr Inhalt zählt weder als Überschrift noch als Fit.
- Abschnittsanker wie DokuWiki mit `useslash`: klein, ohne Akzente, `/`
  trennt wie `:` und verschwindet, Sonderzeichen werden `_`, Wiederholung
  erhält `1`, `2`, … Geprüft am 25.11.2026: 731 von 732 Überschriften der 110
  Schiffsseiten stimmten, die Abweichung war eine auskommentierte Überschrift
  (danach behoben).
- Zuordnung Doktrin → Fit: eigene Fits der Doktrin-Seite und alle Links auf
  Schiffsseiten. Ein Anker wählt die Fits seines Abschnitts; er passt auch mit
  oder ohne End-`s`. Ein toter Anker gibt alle Fits der Seite plus Hinweis,
  eine fehlende Seite nur einen Hinweis. Ein Fit zählt je Doktrin einmal.
- Import in der App am 26.11.2026 mit echter Sitzung: 35 Doktrinen, 225 Fits,
  34 Hinweise (32 tote Abschnittsanker, 2 fehlende Schiffsseiten: legion,
  navitas), alle 3.866 Item-Zeilen der Fits einer Type-ID zugeordnet, 759
  Items in der Tabelle.
- Stand der Erkundung am 25.11.2026: 35 Doktrin-Seiten, 110 Schiffsseiten,
  225 Fits (221 auf Schiffsseiten, 4 auf Doktrin-Seiten), 34 tote Anker,
  2 fehlende Schiffsseiten.

## C. Sitzung und Datenschutz

- Die Anmeldung läuft im Wiki selbst in einem Web-Fenster der App. Die App
  sieht kein Passwort und speichert keine Zugangsdaten.
- Die Sitzung liegt in einem eigenen WebKit-Datenspeicher
  (`WKWebsiteDataStore(forIdentifier:)`, feste ID in `DoctrineWikiSession`).
  „Abmelden“ löscht alle Daten dieses Speichers.
- Der Speicher behält, was die Seiten dauerhaft setzen. Wiki und Brave Core
  setzen nur Sitzungs-Cookies, die Wiki-Sitzung endet also mit der App; EVE
  SSO kann sich das Konto merken, dann reicht beim Neu-Anmelden ein Klick
  (geprüft am 26.11.2026). Die App speichert keine Sitzungs-Cookies selbst.
- Beim Import werden die Cookies dieses Speichers nur an den Wiki-Host
  gesendet (eigene flüchtige `URLSession`, keine Cookie-Übernahme). Einer
  Weiterleitung auf einen anderen Host folgt der Import nicht, weil sie die
  Cookies mitnähme; die Seite gilt dann als nicht lesbar. Zwischen zwei Seiten
  liegt eine Pause von 80 ms.
- Der Import läuft im `DoctrineWikiImportController` und damit unabhängig
  von der Seite: Verlassen der Seite bricht ihn nicht ab, nur „Abbrechen“.
- Gespeichert werden nur das Ergebnis (`doctrine-stock.library.v1`) und die
  Sollwerte (`doctrine-stock.targets.v1`) als App-Einstellungen, also Teil der
  normalen Sicherung.

## D. Rechnung je Item

- **Fits:** Anzahl der Fits des ganzen Imports, die das Item als Rumpf oder
  Item enthalten.
- **Benötigt:** Σ über Doktrinen mit Soll: Soll × Menge im Fit (Rumpf 1 je
  Fit).
- **Gelistet:** Sell-Stück am Home Hub beim letzten Bestandspunkt.
- **Verkauft/Tag Region:** Ø 30 Tage der ESI-Markthistorie der Region des Home
  Hubs (beide Orderseiten). **Verkauft/Tag Hub:** Teilverkäufe je erfasstem Tag
  über 30 Tage aus der Bestandshistorie (Untergrenze, unvollständig in
  Warnfarbe).
- **Reichweite:** Gelistet ÷ Region/Tag; „ausverkauft“ bei 0 gelistet und
  Verkäufen, „keine Verkäufe“ bei 0 pro Tag, sonst unbekannt.
- **Fehlmenge:** Benötigt − Gelistet, mindestens 0; ohne Soll 0, ohne
  Bestandsstand unbekannt.
- **Bau/Stück:** `StockSaleProductionCostProjector` (Rechnung der
  Home-Hub-Chancen wie im Lagerverkauf-Abgleich) für die Fehlmenge, mindestens
  einen Lauf; Material am Main Hub, Installation, Blueprint-Anteil bzw.
  Invention, Logistik bis zum Home Hub; Schalter der Hub-Chancen. Nicht baubar
  laut `plannerBuildTargets()` → „nicht baubar“.
- **Import/Stück:** niedrigster Sell am Main Hub plus Transport je Stück auf
  der Etappe Main → Home (`TradeCalculator`, wie im Handel). Sind Home und Main
  Hub derselbe Ort, ist der Transport 0.
- **Empfehlung:** der günstigere Weg; bei Gleichstand Import. Fehlt eine Seite,
  gibt es nur dann eine Empfehlung, wenn der andere Weg unmöglich ist (nicht
  baubar bzw. kein Sell am Main Hub). Darunter die Ersparnis je Stück.
- **Gewinn/Stück:** eigene Sell-Order einen Preisschritt unter dem besten Sell
  am Home Hub, nach Verkaufssteuer und Maklergebühr, minus Kosten des
  empfohlenen Wegs. Ohne Sell am Home Hub unbekannt.
- Unbekannte Werte bleiben „—“ mit Grund im Info-Symbol, nie 0. Sortierung nach
  dem typisierten Wert, unbekannt aufsteigend hinten, absteigend vorn; „keine
  Verkäufe“ ist eine unbegrenzte Reichweite; Gleichstand nach Typ-ID.

## E. Umsetzung

- Kern (`Sources/EVENexusCore/Doctrine/`): `DoctrineWiki.swift` (EFT- und
  DokuWiki-Parser, Verzeichnis), `DoctrineLibrary.swift` (Modell, Aufbau,
  Sollwerte), `DoctrineStock.swift` (Bedarf, Reichweite, Empfehlung,
  Sortierung), `DoctrineWikiImport.swift` (Abruf mit eingespeistem Fetch).
- App: `DoctrineWikiSession.swift` (WebKit-Speicher, Login-Sheet, Importer mit
  Cookies), `DoctrineStockView.swift` (Seite), `RuntimeState`
  (`doctrineItemCatalogMetadata`), Navigation `NavigationSection.doctrineStock`.
- Tests: `Tests/EVENexusCoreTests/DoctrineStockTests.swift` (17 Tests mit
  künstlichen Wiki-Ausschnitten), Navigationsreihenfolge in
  `HUDNavigationGroupTests` und `RuntimeFeatureStateTests`.

## F. Offen

- Tabelle mit Markt- und Bestandsdaten eines echten Home Hubs ansehen. Die
  abgeschottete Debug-App hatte keinen Home Hub; Bau-, Import- und
  Verkaufswerte sind deshalb nur automatisch geprüft.
- Eigentümerabnahme der Annahmen in Abschnitt A („von Claude festgelegt“).
