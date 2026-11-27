# Plan: Doktrin-Bedarf

Stand: 26.11.2026 · Status: **implementiert, automatisch geprüft, Import mit
echter Wiki-Sitzung in der App geprüft**. Die Tabelle mit Marktdaten eines
echten Home Hubs und die Eigentümerabnahme sind offen, siehe Abschnitt F.
Allumis als zweite Quelle (Abschnitt G): implementiert, automatisch geprüft,
Login und Import vom Eigentümer live geprüft. Soll allein aus Allumis
(Abschnitt H, 27.11.2026): implementiert und automatisch geprüft; Sichtprüfung
mit echten Daten und Eigentümerabnahme offen.

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
| Sollbestand | ~~ein Soll je Doktrin~~, seit 27.11.2026 ersetzt durch das Soll aus Allumis (Abschnitt H) |
| Tabellenumfang | alle Fits des Wikis zählen für „Fits“ (wie im Bild); das Soll kommt nur aus Allumis-Fits mit Soll |
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
- **Soll:** aus Allumis, Regeln in Abschnitt H (bis 26.11.2026 „Benötigt“
  aus dem eigenen Soll je Doktrin).
- **Ist:** Sell-Stück aller Verkäufer am Home Hub beim letzten Bestandspunkt
  (bis 26.11.2026 „Gelistet“).
- **Verkauft/Tag Region:** Ø 30 Tage der ESI-Markthistorie der Region des Home
  Hubs (beide Orderseiten). **Verkauft/Tag Hub:** Teilverkäufe je erfasstem Tag
  über 30 Tage aus der Bestandshistorie (Untergrenze, unvollständig in
  Warnfarbe).
- **Reichweite:** Ist ÷ Region/Tag; „ausverkauft“ bei 0 gelistet und
  Verkäufen, „keine Verkäufe“ bei 0 pro Tag, sonst unbekannt.
- **Fehlmenge:** Soll − Ist, mindestens 0, also was noch gebaut oder
  importiert werden muss; ohne Soll 0, ohne Allumis-Import oder ohne
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
  Obergrenze der Sollwerte), `DoctrineStock.swift` (Soll aus Allumis,
  Fehlmenge, Reichweite, Empfehlung, Sortierung), `DoctrineWikiImport.swift` (Abruf mit eingespeistem Fetch).
- App: `DoctrineWikiSession.swift` (WebKit-Speicher, Login-Sheet, Importer mit
  Cookies), `DoctrineStockView.swift` (Seite), `RuntimeState`
  (`doctrineItemCatalogMetadata`), Navigation `NavigationSection.doctrineStock`.
- Allumis (Abschnitt G): Kern `DoctrineAllumis.swift` (Parser, Snapshot,
  Import, Zuordnung, Item-Werte), App `DoctrineAllumisSession.swift`
  (eigener WebKit-Speicher, Login-Sheet, Import-Steuerung), App-Einstellung
  `doctrine-stock.allumis.v1`, Tests `DoctrineAllumisTests` (11 Tests mit
  künstlichen JSON-Zeilen).
- Tests: `Tests/EVENexusCoreTests/DoctrineStockTests.swift` (17 Tests mit
  künstlichen Wiki-Ausschnitten), Navigationsreihenfolge in
  `HUDNavigationGroupTests` und `RuntimeFeatureStateTests`.

## F. Offen

- Tabelle mit Markt- und Bestandsdaten eines echten Home Hubs ansehen. Die
  abgeschottete Debug-App hatte keinen Home Hub; Bau-, Import- und
  Verkaufswerte sind deshalb nur automatisch geprüft.
- Eigentümerabnahme der Annahmen in Abschnitt A („von Claude festgelegt“).
- Allumis: Zuordnungsquote mit echten Daten und Eigentümerabnahme der
  Annahmen in Abschnitt G.
- Soll aus Allumis (Abschnitt H): Sichtprüfung mit den Allumis-Daten des
  Eigentümers und Eigentümerabnahme.

## G. Allumis (26.11.2026)

Der Eigentümer möchte die Soll-Vorgaben der Allianz automatisch auslesen und
mit seinem Soll je Doktrin abgleichen, sehen, zu welcher Doktrin ein Item
gehört, und die Tabelle um Angaben von Allumis ergänzen. Die Allumis-Tabelle
wird nicht nachgebaut.

### Entscheidungen des Eigentümers (26.11.2026)

| Thema | Entscheidung |
|---|---|
| Allumis-Soll | Vergleich in der Doktrin-Liste plus Knopf, der den häufigsten Allumis-Wert der Fits als Doktrin-Soll übernimmt; das eigene Soll bleibt maßgeblich |
| Doktrin-Zuordnung | Spalte „Doktrinen“ (mit Soll hervorgehoben) und Auswahl „Doktrin“ über der Tabelle |
| Neue Spalten | Soll Allumis, Verluste 10 Tage, Home ÷ Main (Preis in % des Main Hubs), Verkauft/Tag Allumis (Ø 7 Tage) |
| Allumis-Fits ohne Wiki | eigene Gruppe „Nur bei Allumis“ mit Soll wie eine Doktrin |

Von Claude festgelegt (zur Abnahme): eigener WebKit-Speicher für Allumis
(Abmelden trifft nur diese Quelle); Gleichstand beim häufigsten Wert nimmt den
größeren; Refit-Items zählen weder für Inhalt noch Soll (wie Refits im Wiki);
„Home ÷ Main“ rechnet mit den eigenen Marktdaten statt mit den
Allumis-Preisen; der Doktrin-Filter blendet nur Zeilen aus, die Zahlen bleiben
die über alle Doktrinen; Allumis-Ort fest im Code (`staging`). Die Regeln
„Allumis-Soll“, „Allumis-Spalte“ und „Soll Allumis je Item“ dieses Abschnitts
gelten seit 27.11.2026 in der Fassung von Abschnitt H.

### Quelle

- Allumis „Brave Doctrine Market Management“, betrieben von Suffia (Brave
  Supply Officer), nicht Teil von Brave IT. Login nur für Mitglieder von Brave
  Collective oder Brave United über EVE SSO.
- Daten: `https://api.allumis.co.uk/api/?path=/doctrine/ships/detailedtable/&loc=staging`
  liefert JSON, eine Zeile je Fit: `node_index` (Fitting-ID), `itemName`
  (Rumpf), `fittingName`, `minStock` (Soll in Fits), `avg7dVol`, `dropped`,
  `destroyed`, Preise und `_children` mit den Items („Fit Item“ oder
  „Refit Item“, `quantity`). Zahlen kommen meist als Text.
- Befund 26.11.2026 (mit Anmeldung des Eigentümers, nur lesend): 232 Fits,
  3.847 Item-Zeilen, davon 7 Refit-Items; `minStock` der Items ist Fit-Soll ×
  Menge; `avg7dVol`, `dropped` und `destroyed` sind je Item in allen Fits
  gleich; die Spalte „Items lost last 10 days“ ist `dropped + destroyed`.
  `loc` kennt `staging`, `secondary` und `deployment`; der Staging-Markt ist
  die Struktur 1046664001931 und damit der Home Hub des Eigentümers.
- Abgleich mit der Wiki-Bibliothek vom 26.11.2026: 205 der 232 Allumis-Fits
  (EFT der Fit-Liste) hatten exakt den Inhalt eines Wiki-Fits; die übrigen
  27 sind Ratting-, Fun-Fleet- und PodSaver-Fits außerhalb der Wiki-Doktrinen
  oder geänderte Fits. 20 Wiki-Fits kennt Allumis nicht.

### Sitzung und Datenschutz

- Login im Web-Fenster der App (`https://api.allumis.co.uk/login/` → EVE SSO →
  `/authenticate/` → `/user/`). Angemeldet gilt eine Seite unter `/user` auf
  dem API-Host.
- Allumis leitet Pfade ohne Schrägstrich am Ende auf `http://` um (z. B.
  `/login` → `http://api.allumis.co.uk/login/`, geprüft 26.11.2026). Diese
  Adresse lud im Web-Fenster nie, nach 60 Sekunden blieb das Fenster mit
  Zeitüberschreitung weiß (vom Eigentümer als Absturz gemeldet). Deshalb endet
  die Login-Adresse auf `/`, und das Web-Fenster ersetzt jede Navigation und
  Weiterleitung auf `http://` eines Allumis-Hosts durch ihre `https`-Form.
- Allumis setzt das Cookie `session` auch für Besucher ohne Anmeldung. Der
  Chip zeigt „Allumis-Sitzung aktiv“ deshalb erst, wenn in diesem App-Lauf das
  Login-Fenster eine angemeldete Seite gesehen oder ein Import geklappt hat;
  mit Cookie ohne solche Bestätigung „Allumis-Sitzung gespeichert, nicht
  geprüft“, nach abgewiesenem Import oder Abmelden „Nicht bei Allumis
  angemeldet“.
- Eigener persistenter `WKWebsiteDataStore` (feste ID in
  `DoctrineAllumisSession`), getrennt vom Wiki. „Abmelden“ löscht nur ihn.
  Allumis setzt das Cookie `session` mit 12 Stunden Laufzeit; die Sitzung
  übersteht also einen Neustart innerhalb dieser Zeit.
- Der Import sendet die Cookies nur an `api.allumis.co.uk` (flüchtige
  `URLSession`, keine Cookie-Übernahme) und folgt keiner Weiterleitung auf
  einen anderen Host. Weiterleitung, 401, 403 oder eine Antwort ohne
  `application/json` gelten als „nicht angemeldet“.
- Gespeichert wird nur das Ergebnis (`doctrine-stock.allumis.v1`): Fits mit
  Soll und Items, Item-Werte, Hinweise. Keine Preise, keine Sitzungsdaten.

### Regeln

- **Zuordnung:** jedes Allumis-Fit höchstens einem Wiki-Fit und umgekehrt, in
  drei Durchgängen: (1) gleicher Inhalt und gleicher Name, (2) gleicher
  Inhalt, (3) gleicher Rumpf und Name, dann als „Inhalt weicht ab“ markiert.
  Inhalt = Rumpf und Items mit summierten Mengen, nach Typ-ID oder sonst Name,
  ohne Refits. Name = Fitname ohne führende Kürzel in eckigen Klammern, klein,
  einfache Leerzeichen. Allumis-Fits gehen nach aufsteigender Fitting-ID und
  nehmen das erste freie Wiki-Fit in Bibliotheksreihenfolge.
- **Nur bei Allumis:** nicht zugeordnete Allumis-Fits bilden die Doktrin
  `allumis:only` (Fit-IDs `allumis:<Fitting-ID>`). Sie zählen für „Fits“,
  „Doktrinen“, „Soll“ und den Filter wie Wiki-Fits.
- **Allumis-Spalte der Doktrin-Liste** (seit 27.11.2026 „Soll je Fit“): die
  Allumis-Sollwerte der Fits der Doktrin mit Häufigkeit, „x von y Fits“;
  sortiert nach dem häufigsten Wert, bei Gleichstand dem größeren. Der
  Übernehmen-Pfeil ist seit 27.11.2026 entfernt.
- **Soll Allumis je Item:** seit 27.11.2026 das Soll der Tabelle, Regeln in
  Abschnitt H.
- **Verkauft/Tag Allumis** = `avg7dVol`; **Verluste 10 Tage** = `dropped +
  destroyed`, unbekannt, wenn einer fehlt. Stimmen die Werte eines Items in
  zwei Fits nicht überein, gilt der größere.
- **Home ÷ Main** = bester Sell am Home Hub ÷ niedrigster Sell am Main Hub,
  unbekannt, wenn einer fehlt oder 0 ist.
- **Doktrinen je Item:** jede Doktrin mit mindestens einem Fit, das das Item
  als Rumpf oder Item enthält; Sortierung nach ihrer Anzahl.

### Geschwindigkeit (26.11.2026)

Eigentümer: Die Seite ist sehr langsam, das Login-Fenster braucht ewig. Befund
in der isolierten Debug-App mit 759 Item-Zeilen: Die Zeilen lagen in einem
`LazyVStack` innerhalb des waagerechten Scrollbereichs der Tabelle im
senkrechten Seiten-Scrollbereich. So sah der Stapel keinen senkrechten
Sichtbereich und baute alle Zeilen (16.300 Bedienungshilfen-Elemente, 776
Item-Bilder). Beim Öffnen des Login-Fensters rechnete AppKit in jedem
Animationsschritt Mindestgröße und Layout des ganzen Fensters neu: rund 850
von 2.023 Hauptthread-Proben, Klick bis Fenster 1,7 s. Die Ursache bestand
schon vor Allumis; die fünf neuen Spalten haben die Last je Zeile erhöht.
Korrektur nach dem Muster der Hub-Chancen-Tabelle: Kopfzeile und ein eigener
senkrechter Scrollbereich fester Höhe im waagerechten Scrollbereich. Danach
1.938 Elemente und 78 Item-Bilder, also nur die sichtbaren Zeilen. Die
Ladezeit des Login-Fensters ist nach der Korrektur nicht nachgemessen.

Eigentümer danach: deutlich besser, aber der Start der Seite braucht noch.
Messung in seiner Xcode-Debug-Instanz (Neustart, Seite sofort geöffnet,
`sample` 90 s, nur lesend): Hauptthread in 29.009 von 29.563 Proben
beschäftigt, davon 20.145 in SwiftUIs Neuauswertung nach Datenänderungen.
Größte Posten der Seite: Allumis-Spalte der Doktrin-Liste mit ihren Texten
(rund 4.500), Lesen der App-Sprache aus den UserDefaults für jede Zahl
(rund 3.600), sichtbare Tabellenzeilen (rund 3.600), Tabellenberechnung
(rund 2.700). Häufigster Auslöser: Jeder Fortschrittsschritt der
Regionshistorie (rund 900 Items) wertete die ganze Seite neu aus.
Umbau ohne Änderung der Rechenregeln:
- Fortschrittszeile der Regionshistorie als eigene Ansicht
  (`DoctrineHistoryProgressLine`), die Seite liest den Fortschritt nicht mehr.
- Doktrin-Liste und Tabellenzeilen als vergleichbare Ansichten
  (`DoctrineListRowView`, `DoctrineStockRowView`, `.equatable()`); eine Zeile
  wird nur neu gebaut, wenn sich ihr Inhalt, ihr Soll oder die Berechnung
  ändert.
- Texte der Doktrin-Liste einmal je Import oder Sprache vorberechnet
  (`DoctrineListRowModel`).
- Gebietsschema einmal gelesen (`DoctrineNumberFormat`), folgt dem
  Gebietsschema der Umgebung; Typ-IDs der Bibliothek zwischengespeichert.
- Tabellenberechnung wartet 150 ms, damit ein Schub von Datenänderungen
  beim Öffnen nur eine Berechnung auslöst.

Nachmessung mit dem Eigentümer (gleicher Ablauf, 26.11.2026): Hauptthread
untätig in 5.860 von 36.485 Proben (vorher 554 von 29.563). Der Doktrin-Seite
zuordenbar sind noch rund 370 Proben (vorher rund 10.800): Doktrin-Liste und
Tabellenzeilen kaum messbar, Tabellenberechnung rund 760 (vorher 2.700),
Lesen der App-Sprache rund 510 (vorher 3.900). Rund 12.000 Proben dieses
Laufs gehören zum Dashboard, auf dem die App startet (Kartenlayout und
Ansicht); im ersten Lauf kam es kaum vor. Das ist nicht Teil dieser Seite.

## H. Soll allein aus Allumis (27.11.2026)

Eigentümer: Der Import funktioniert, aber für das System ist nicht klar, was
Soll und was Ist ist und wie viel nachproduziert werden muss. Die Vorgaben aus
Allumis sollen auf die Items verteilt und mit dem aktuellen Bestand abgeglichen
werden, damit er keine eigene Tabelle mehr führen muss.

### Entscheidungen des Eigentümers (27.11.2026)

| Thema | Entscheidung |
|---|---|
| Soll-Quelle | nur Allumis: Soll je Fit × Menge im Fit, auf die Items verteilt. Die eigene Soll-Spalte je Doktrin und der Übernehmen-Pfeil entfallen; der gespeicherte Wert (`doctrine-stock.targets.v1`) bleibt unangetastet. Wiki-Fits ohne Allumis-Gegenstück haben kein Soll. |
| Ist-Bestand | alle Sell-Orders am Home Hub (alle Verkäufer), wie Allumis den Staging-Markt misst; keine eigenen Assets, keine laufenden Jobs |
| Item in mehreren Fits | Summe über alle Fits (alle Fits gleichzeitig komplett kaufbar) |
| Darstellung | Spalten „Soll · Ist · Fehlmenge“ nebeneinander, „Benötigt“ und „Soll Allumis“ zu „Soll“ zusammengelegt; Standardsortierung Fehlmenge absteigend; Zählerzeile mit Items mit Fehlmenge |

Von Claude festgelegt (zur Abnahme): Bei einem zugeordneten Wiki-Fit zählt
für das Soll der Inhalt des Allumis-Fits, auch wenn er abweicht; Items, die
nur das Allumis-Fit hat, bekommen deshalb eine Zeile. „Fits“ und „Doktrinen“
zählen ein Fit, wenn das Item im Wiki- oder im Allumis-Inhalt steht. Der
Tooltip der Spalte „Doktrinen“ nennt je Doktrin ihren Anteil am Soll; ein Fit
mehrerer Doktrinen zählt dort bei jeder, die Anteile können sich deshalb zu
mehr als dem Soll addieren. Die Zählerzeile nennt die Zahl der Allumis-Fits
mit Soll.

### Regeln

- **Soll je Item** = Σ über alle Allumis-Fits von Fit-Soll × Menge im Fit,
  Rumpf einmal je Fit, Refits nicht. Jedes Allumis-Fit zählt genau einmal,
  auch wenn mehrere Doktrinen es nutzen. Fit-Soll höchstens 10.000, Summe
  höchstens 10¹².
- Kein Allumis-Fit mit Soll nutzt das Item → Soll 0, Anzeige „–“. Ohne
  Allumis-Import ist das Soll unbekannt, Anzeige „—“, und die Seite weist
  darauf hin.
- **Ist** = Sell-Stück aller Verkäufer am Home Hub beim letzten
  Bestandspunkt; ohne Bestandsstand unbekannt.
- **Fehlmenge** = max(0, Soll − Ist): was noch gebaut oder importiert werden
  muss. Soll 0 → 0; Soll oder Ist unbekannt → unbekannt.
- **Bau/Stück** rechnet weiter für die Fehlmenge, mindestens einen Lauf.
- **Doktrinen je Item:** die mit Anteil am Soll zuerst; Anteil = Σ über die
  Fits der Doktrin von Fit-Soll × Menge.

### Umsetzung

- Kern: `DoctrineAllumisMerge` führt `hasAllumisImport`, das Allumis-Fit je
  Fit-ID (`allumisFitByFitID`) und alle Typ-IDs beider Inhalte
  (`allTypeIDs`); `DoctrineDemandAggregator.demands(sources:)` rechnet Soll und
  Anteile je Doktrin; `DoctrineAllumisItemFigures` enthält nur noch Verkäufe
  und Verluste; Sortierspalte `allumisRequiredQuantity` entfällt.
- App: `DoctrineStockView` ohne eigene Sollwerte, Doktrin-Liste ohne Soll-Feld
  und Pfeil, Spalte „Soll je Fit“, Item-Tabelle mit „Soll · Ist · Fehlmenge“.
- Tests: `DoctrineStockTests` (Soll aus Allumis, unbekanntes Soll, Fehlmenge),
  `DoctrineAllumisTests` (Summe je Fit, geteiltes Fit, abweichender Inhalt,
  Refits, Anteile je Doktrin, Sortierung mit unbekanntem Soll).
