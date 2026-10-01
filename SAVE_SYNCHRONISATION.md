# Dynamische FT2-Hauptfarmverwaltung

## Bedienung

In den Einstellungen „Spielstandordner auswählen …“ wählen und den übergeordneten Speicherordner freigeben,
der `farms.mlk` und den Unterordner `farms/` enthält. Der bisher ausgewählte
Bereichsordner allein reicht für Farmnamen und Identitäten nicht aus.

Die Hauptansicht zeigt bei einer registrierten Hauptfarm direkt deren Karte.
Ab zwei Farmen startet die Ansicht in der Übersicht mit vollständig anklickbaren
Karten. „Alle Farmen“ führt aus einer geöffneten Farm zurück. Die Übersicht
verwendet ein adaptives scrollbares LazyVGrid. Es gibt keine feste Kartenanzahl.
Die Einzelfarmkarte enthält Saisonbild, Saisonname, Countdown, kurzen Status und
die nächste Saison. Alle vier Saisonbilder stammen aus den vorhandenen Assets.

Über das Zahnrad oder das native Einstellungen-Menü öffnet sich SettingsView.
Nur dort stehen Spielstandordner-Auswahl, „Zugriff entfernen“ und der Zugriffsstatus.
Namen werden ausschließlich für die Anzeige getrimmt. Keine technischen Save-
Informationen werden dauerhaft auf den Farmkarten angezeigt.

Alle zehn Sekunden wird die aktive Speicherquelle im Hintergrund gelesen.
Neue Hauptfarmen und weitere Bereiche werden dabei automatisch berücksichtigt.
„Trennen“ beendet die Prüfung und erhält alle Referenzen. Die letzte Quelle
bleibt für die Anzeige bekannt; ihre Countdowns laufen weiter.

Manuelle Saisonwahl, Slider, Starten, Sekundenkorrekturen und „Jetzt gestartet“
sind vollständig entfernt, einschließlich ihrer Modellfelder und Methoden.
Eine vorhandene gültige automatische Referenz ist die einzige Saisonzeitbasis.
Ohne Referenz zeigt die Karte „Warte auf Spielstand“ statt einer erfundenen Saison.
Alte manuelle Werte im gespeicherten Katalog werden ignoriert und beim Speichern
nicht erneut geschrieben. Es bleibt kein manueller Fallback oder Offset aktiv.

## Identität und Persistenz

Die FT2-Identität ist `(sourceID, slotIndex, creation_time)`. Die Speicherquelle
besitzt eine persistierte UUID, einen Pfad und ein ausschließlich lesendes
Security-Scoped-Bookmark. Erneute Auswahl desselben normalisierten Pfads verwendet
wieder dieselbe Quellen-ID. Bookmark-Auffrischung verändert keine Farmidentität.
Eine Farmumbenennung ändert nur `name`, nicht Identität oder Referenz.
Doppelte Namen sind zulässig. Eine wiederverwendete Slot-ID mit anderer
Erstellungszeit erzeugt einen separaten Datensatz; der alte bleibt erhalten.
Zusätzlich sind interne Tracker-IDs stabile, nicht als FT2-Slot interpretierte IDs.

Der neue Katalog liegt in den eigenen UserDefaults unter `ft2FarmCatalog_v2`.
Die alte Vier-Farmen-Konfiguration unter `savedFarmsData_v1` wird nicht mehr
verwendet, gelesen oder neu geschrieben. Es gibt keine Legacy-Migration und
keine Archivmeldung. Bereits vorhandene `legacyFarms`-Felder in einem gültigen
v2-Katalog werden beim Dekodieren ignoriert und beim nächsten Speichern nicht
mehr ausgegeben. Aktive Farmen, Quellen, Auswahl und Referenzen bleiben erhalten. Ein noch vorhandener alter v1-UserDefaults-Schlüssel ist
wirkungslos; die App löscht ihn nicht eigenständig.

Die Auswahl verwendet weiterhin die komplette persistierte FarmIdentity.
Die Navigation selbst ist lokaler SwiftUI-Zustand und startet bei mehreren Farmen
in der Übersicht. preferredViewMode wird nicht mehr gelesen oder geschrieben;
vorhandene Werte werden beim erneuten Speichern entfernt, ohne Farmen, Quellen
oder Referenzen zu verändern. Ein vorhandener älterer selectedFarmID-Wert wird
beim Laden anhand des bestehenden Datensatzes in die FarmIdentity überführt.

Registrierung, momentane Verfügbarkeit und erfolgreich geprüfte Referenz werden
getrennt behandelt. Ein kompletter erfolgreicher Metadatenscan bestimmt die
Registrierung. Temporäre Lesefehler ändern sie nicht und blenden deshalb keine
zuletzt registrierte Farm als entfernt dar. Erst ein erfolgreicher Scan ohne diese
Identität markiert sie als inaktiv. Auf Karten: „Synchronisiert“ für eine erfolgreich geprüfte
Referenz, „Letzter Stand“ bei fortgerechneter Referenz ohne aktuelle Bestätigung,
„Warte auf Spielstand“ ohne Referenz. Inaktive Farmen zeigen immer
„Farm nicht mehr gefunden“, unabhängig von der erhaltenen Referenz. Diese Flags beeinflussen keine Zeitrechnung.

Ein erneuter erfolgreicher Scan aktualisiert den Namen auch ohne neuen Bereichs-
Save. Farmen, die in einem vollständigen gültigen Metadaten-Snapshot fehlen,
werden als nicht registriert markiert und bleiben gedimmt an ihrer bisherigen
Position sichtbar. Ihre letzte Referenz wird weitergerechnet. Nur die Aktion
„Farm endgültig löschen“ in der Detailansicht entfernt nach Bestätigung den
vollständigen Tracker-Datensatz. Sie löscht keine FT2-Dateien und prüft die volle
Identität und den inaktiven Zustand erneut vor dem Entfernen. Fehlende oder defekte
Metadaten verändern keine Referenzen. Ein anderer ausgewählter Quellordner erhält
eine eigene Identität; alte Datensätze bleiben erhalten. Ein umbenannter Ordner
funktioniert über sein Bookmark weiter; eine manuelle Auswahl unter einem neuen
Pfad kann eine neue Quellen-ID erzeugen. Diese Quellenzusammenführung ist offen.

## Lesen von farms.mlk

Aktueller FT2-Build, Version 347:

1. SaveStream.ConvertFromByte: `((byte XOR 255) + 31) modulo 256`.
2. Gzip entpacken mit CRC-/ISIZE-Prüfung, genau ein Stream, keine Restdaten.
3. UTF-8-JSON mit unquoted Eigenschaftsnamen normalisieren.
4. Typisiert `farms[].slotIndex`, `farms[].farm.creation_time` und
   `farms[].farm.name` lesen. Int64-Zeiten werden nicht über Double umgewandelt.

Die Normalisierung ist ein begrenzter struktureller Parser, keine Regex-Ersetzung
und keine Auswertung von Text. Er erhält escaped Strings, prüft doppelte Schlüssel,
Verschachtelung und Restdaten. JSONDecoder prüft anschließend die JSON-Syntax.
Doppelte Slot-IDs, ungültige Identitäten oder unbekannte Metadatenversionen führen
zur Ablehnung des gesamten Snapshots. Bei einem Fehler wird keine Farm als gelöscht
interpretiert. Maximal 10.000 registrierte Farmen pro Metadatendokument.

## Bereichsauswahl und Zeitsemantik

Pro registrierter Hauptfarm werden nur exakt `farm_<ID>_0.data` bis
`farm_<ID>_5.data` berücksichtigt, ohne Rekursion, Common-Dateien oder `.bak`.
Ein Bereich muss nicht bereits existieren. Der höchste gültige eingebettete
Zeitpunkt aus Feld 16 gewinnt. Alle vier Referenzwerte stammen gemeinsam aus
einer Bereichsdatei. Ein Save vor der Erstellungszeit der Farm wird ausgeschlossen,
damit bei Slot-Wiederverwendung keine alten Bereichsdateien übernommen werden.
Widersprüchliche neueste Saves mit gleichem Zeitpunkt werden abgelehnt.

Vor und nach dem Bereichsscan werden die Metadaten als stabile Snapshot-Datei
gelesen und verglichen. Eine Änderung verwirft das Gesamtergebnis. Dateien können
weiterhin zwischen den Scans entstehen oder verschwinden; der nächste Scan holt
auf. Das Verfahren stellt keine transaktionale FT2-Speicherung her.

Die bestehende Referenzarithmetik bleibt unverändert: UTC-.NET-DateTime-Ticks,
1020 Sekunden pro Saison, positiver Modulo 4080, absolute Systemzeit. Feld 15 ist
worldTicks, 18 nextSeasonChange, 21 currentSeason. Nur die sichtbare Restzeit nutzt
`min(remaining + 2, 1020)`. Die +2 Sekunden verändern weder Saison noch Wechsel.

## Schreibschutz und Grenzen

FT2SaveAccess ist die Produktionsschnittstelle zu FT2-Dateien: Darwin.open mit
O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, fstat, read, close. Keine Schreib-,
Rename-, Delete-, Reparatur- oder Attributoperationen. Reguläre Dateien, keine
Datei-Symlinks; auch ein verknüpfter Bereichsordner wird abgelehnt. Änderungen von
Größe, mtime oder ctime während des Lesens verwerfen den Snapshot. Keine temporären
Dateien in FT2-Verzeichnissen. Verarbeitung ausschließlich im Arbeitsspeicher.

Bookmark: securityScopeAllowOnlyReadAccess. Xcode: App-Sandbox aktiviert und
ENABLE_USER_SELECTED_FILES=readonly. Betriebssystembedingte Zugriffserfassung
wird von der App weder angefordert noch verändert.

Maximal 16 MiB komprimiert, 64 MiB entpackt, 64 Verschachtelungen und vier Millionen
Werte. Die Bereichsparsing-Regeln bleiben bestehen: Version 347, keine doppelten
Objektfelder, gültige Zeiten, Saison 0...3, Restzeit >0 und <=1020, höchstens fünf
Minuten zukünftiger Speicherzeitpunkt. Neuere Saves ersetzen die Referenz; ältere,
gleichzeitige widersprüchliche oder kaputte Kandidaten nicht.

## Analyse: Löschen im aktuellen FT2-Code

Untersucht: Assembly-CSharp.dll, SHA256
`d7a7613849acb748d1d78801e5274f4993ff4670237e176f32bd9de4ade6a78e`.

- Core.SaveManager.DeleteSlot() ruft LocalFarmHeader.Delete() auf, entfernt den
  Slot aus `slots`, bereinigt gegebenenfalls currentFarm/selectedFarmIndex,
  sortiert die Liste, wählt eine Farm und ruft Save() auf.
- SaveManager.ToJson() serialisiert nur die aktuelle `slots`-Liste nach `farms`;
  SaveManager.Save() schreibt `farms.mlk`. Damit verschwindet der registrierte
  Eintrag beim erfolgreichen Speichern.
- LocalFarmHeader.Delete() ruft FarmData.DeleteFarm(header) auf. Diese Methode
  stellt über StorageManager.Post einen asynchronen PlayerIOOperation ein.
- Die IO-Überladung FarmData.DeleteFarm(storage, object) erzeugt ausschließlich
  GetFarmPath(false), prüft FileExists und ruft DeleteFile für die Common-Datei
  `farms/farm_<ID>.data` auf. Sie enthält keine Bereichsschleife und keine
  Löschaufrufe für Bereichsdateien oder `.bak`.

Registrierung und Dateilöschung sind daher keine atomare Operation. Aus dem
untersuchten Ablauf folgt insbesondere keine Garantie, dass alle Bereichsdateien
verschwinden. Der Tracker verwendet die Registrierung aus farms.mlk und bewahrt
verschwundene Identitäten auf; zurückgebliebene Dateinamen registrieren keine Farm.
Keine Löschfunktion des Spiels wurde ausgeführt.

ID-Vergabe: CreateSlot() ruft GetFreeSlot() auf; zufälliger Start 0...49, danach
inkrementieren, solange GetFarm(ID) einen registrierten Slot liefert. Keine
fortlaufenden IDs und keine feste Beschränkung auf vier Hauptfarmen.

## Prüfung

```sh
sh Tests/run-tests.sh
sh Tests/run-tests.sh '/pfad/zu/ft2-testspielstaenden' '<Benutzerordner>/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>'
```

Synthetische Testdateien werden nur in frischen temporären Testordnern erzeugt.
Die optionale Variante liest historische Bereichssaves und den echten Katalog,
vergleicht den Katalog mit der aktuellen Registrierung und prüft die Hashes
aller gelesenen Dateien vorher und nachher. Der zweite Testsatz prüft den Manager mit einer isolierten UserDefaults-
Suite, einschließlich Persistenz, Entfernung manueller Altzustände und unabhängiger Saisonreferenzen.

Der macOS-Build prüft die App-Integration. Auswahl, Wiederaufnahme des Bookmarks
und Sandbox-Zugriff müssen zusätzlich im normalen signierten Xcode-App-Lauf auf
dem Mac geprüft werden. Ein unsigned Build bestätigt diese Zugriffswege nicht.
