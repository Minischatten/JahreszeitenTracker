# Phase 1: automatische FT2-Synchronisation

## Bedienung

Die vier vorhandenen Trackerplätze bleiben unabhängig. Für den gewünschten Platz
„FT2-Ordner…“ wählen und den Ordner freigeben, der die Bereichsdateien enthält.
Das kleine Menü „FT2: 1“ bezeichnet den FT2-Spielstandslot, nicht den Farmbereich:
FT2: 1 sucht farm_0_0.data bis farm_0_5.data; FT2: 2 entsprechend farm_1_*.data.
Alle sechs Bereiche eines Slots werden berücksichtigt. Die App durchsucht nicht
rekursiv übergeordnete Steam-/Backup-Verzeichnisse und wählt keine fremden Slots.

Nach Auswahl und anschließend ungefähr alle zehn Sekunden werden die Dateien
im Hintergrund geprüft. Der neueste gültige eingebettete Speicherzeitpunkt gewinnt.
Die App muss für die Prüfung laufen; nach einem Neustart wird der Ordnerzugriff
über das gespeicherte Security-Scoped-Bookmark wieder aufgenommen.

„Trennen“ beendet die Ordnerprüfung und erhält die letzte Referenz. Manuelle
Einstellungen und Sekundenkorrekturen bleiben möglich. Ein wirklich neuerer Save
setzt diese Korrekturen zurück und synchronisiert erneut. Gleich alte Saves ändern
auch eine zwischenzeitlich manuell korrigierte Referenz nicht.

## Schreibschutz

FT2SaveAccess ist die einzige Produktionsschnittstelle zum Save-Dateiinhalt:
Darwin.open mit O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, fstat, read,
close. Keine Schreib-, Rename-, Delete- oder Attributänderungsoperationen. Nur
reguläre Dateien, keine Datei-Symlinks. Änderung von Größe, mtime oder ctime
während des Lesens verwirft die Speicherkopie. Bei atomarem Austausch kann noch
ein konsistenter älterer Snapshot gelesen werden; der nächste Scan holt auf.

Der vom NSOpenPanel freigegebene Ordner erhält ein Bookmark mit
securityScopeAllowOnlyReadAccess. Die Xcode-Konfiguration verwendet
ENABLE_APP_SANDBOX=YES und ENABLE_USER_SELECTED_FILES=readonly. Keine
zusätzlichen Zugriffsrechte, keine temporären Dateien im Save-Verzeichnis und
keine Verarbeitung von .bak-Dateien. Betriebssystembedingte Zugriffserfassung
(z.B. atime) wird von der App weder angefordert noch verändert.

App-Zustand und Bookmark werden ausschließlich in den eigenen UserDefaults
unter savedFarmsData_v1 gespeichert. Vorhandene manuelle Datensätze bleiben
wegen optionaler neuer Felder lesbar. Der Manager wird zwischen Fenstern geteilt.

## Parser und Validierung

Gzip mit zlib (inklusive CRC und ISIZE), genau ein Stream, keine Restdaten.
Maximal 16 MiB komprimiert, 64 MiB entpackt, 64 Verschachtelungen und vier
Millionen Werte. Diese Grenzen können große zukünftige Saves kontrolliert
ablehnen; sie sind keine Größenbehauptung über sämtliche FT2-Farmen.

Strukturelles vollständiges Durchlaufen des beobachteten Formats: C1 Objekt,
C7 Liste, C8 Ende, numerische Feldkennungen; primitive MessagePack-artige Werte.
Nur Root-Felder 0, 15, 16, 18, 21 werden gespeichert. Unbekannte Typbytes,
doppelte Objektfelder, fehlende Abschlüsse, falsche Feldtypen und unbekannte
Versionen werden abgelehnt. Phase 1 akzeptiert ausschließlich die beobachtete
Version 347. Keine heuristische Bytefolgensuche.

Erforderlich: nichtnegative interne Zeit, Saisonindex 0...3, Restzeit >0 und
<=1020, gültiger DateTime-Ticks-Bereich und höchstens fünf Minuten zukünftiger
Speicherzeitpunkt. Eine Saisonphase am exakten Wechsel mit Restzeit 0 wird
vorsichtshalber nicht importiert; der nächste konsistente Save kann folgen.

Neuere Saves ersetzen die Referenz; ältere werden abgelehnt. Gleiche Zeitstempel
mit widersprüchlichen Zeit-/Saisonwerten werden ebenfalls abgelehnt, auch zwischen
Bereichsdateien. Nicht lesbare oder ungültige Kandidaten werden übersprungen.
Kein gültiger Kandidat: bisheriger Zustand bleibt erhalten. Der Parser wird erst
vollständig abgeschlossen und validiert, bevor der Manager überhaupt mutiert.

## Zeitsemantik

Feld 16 wird zentral in TrackerClock als UTC-.NET-DateTime-Ticks seit 0001-01-01
interpretiert und in Date umgerechnet. Alle Messdaten passen dazu; ein DateTime.Kind
ist im beobachteten Integer nicht enthalten. Winterzeit und Verhalten bei lokalen
Uhrumstellungen wurden noch nicht kontrolliert gemessen. Keine eigene DST-Korrektur.
Die Umrechnung ist bewusst zentral anpassbar.

Aus Feld 15, Feld 18, Feld 21 und Speicherzeit wird der absolute Beginn der
Referenzsaison abgeleitet. SeasonCalculator berechnet den Zustand direkt aus dem
übergebenen Date, Dauer 1020 und positivem Modulo 4080. Beliebig viele verpasste
Zyklen benötigen keine Timeraufrufe. Rückwärts gehende Systemzeit wird ebenfalls
mathematisch konsistent behandelt, garantiert aber nicht dasselbe FT2-Verhalten.

Die bekannte Sekundenabweichung zwischen interner Zeit und Echtzeit kann bis
zum nächsten neueren Save bleiben, auch nahe einer Saisongrenze. Das ist eine
Vorhersage, keine dauerhaft sekundengenaue Spielanbindung.

## Prüfung

sh Tests/run-tests.sh
sh Tests/run-tests.sh /pfad/zu/ft2-testspielstaenden

Die zweite Variante liest vorhandene Bereichsdateien, verifiziert Referenzwerte
und Saisonraster und prüft ihre Hashes davor/danach. Sie schreibt nicht in diese
Dateien. Synthetische beschädigte Gzip-/Strukturfixtures und Verzeichnistests
werden ausschließlich unter einem neuen temporären Ordner erzeugt. Compiler-
und Testartefakte liegen ebenfalls außerhalb der FT2-Verzeichnisse.

Der Xcode-Build prüft zusätzlich die App-Integration. NSOpenPanel, Bookmark-
Wiederaufnahme und die signierte App-Sandbox müssen im normalen App-Betrieb
auf dem Benutzer-Mac verifiziert werden; der unsigned Build bestätigt sie nicht.
