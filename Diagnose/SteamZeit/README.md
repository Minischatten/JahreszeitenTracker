# Steam-/Systemzeit-Diagnose

Separater Swift-Helfer; verändert weder Tracker noch FT2-Dateien oder Saves.
Lädt die installierte FT2-Steam-Bibliothek und verwendet nur Initialisierung,
Utils-Schnittstelle, Zeitabruf, Callback-Verarbeitung und Shutdown.
Kein RestartAppIfNecessary, kein Zugriff auf den FT2-Prozess.

## Start

Steam unter demselben macOS-Benutzer geöffnet und angemeldet lassen.
Für den isolierten Vergleich FT2 vorher beenden. Im Terminal ausführen:

```sh
cd Diagnose/SteamZeit
xcrun swiftc SteamZeit.swift -module-cache-path ModuleCache -o SteamZeit
STEAM_API_LIBRARY='/pfad/zur/FT2-Installation/FarmTogether2.app/Contents/Frameworks/MonoEmbedRuntime/osx/libsteam_api.dylib' ./SteamZeit
```

Die Befehle werden vom Repository-Hauptverzeichnis aus ausgeführt.
`STEAM_API_LIBRARY` muss ausdrücklich auf die vorhandene lokale Steam-Bibliothek
der eigenen FT2-Installation zeigen; es wird keine Bibliothek mitgeliefert.

Der Helfer läuft 180 Sekunden und schreibt ungefähr alle 100 ms eine Zeile
in eine neue `Messung-<UTC-Startzeit>.csv` in diesem Ordner.
Die eigene `steam_appid.txt` muss im Diagnoseordner bleiben.
Bei fehlgeschlagener Initialisierung wird keine Messung begonnen.

`system_minus_steam_seconds` ist der Mittelwert der beiden Date()-Messungen
minus unveränderte Steam-Ganzsekunden. Positiv bedeutet Systemzeit voraus.
Monotone Werte stammen aus `ProcessInfo.systemUptime` und erlauben das
Erkennen von Messpausen und Änderungen der Systemzeit.
Die Steam-Ganzsekunden liefern keine Aussage über ihre interne Rundungsregel.

## Erneut bauen

```sh
xcrun swiftc SteamZeit.swift -module-cache-path ModuleCache -o SteamZeit
```

Ein eigener Compiler-Cache bleibt in diesem Diagnoseordner.
Steam selbst kann bei Initialisierung seine üblichen internen Aktivitäten
ausführen. Der Helfer schreibt ausschließlich seine CSV-Datei.
