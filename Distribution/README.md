# Wiederverwendbarer WirdSchonSoftware-DMG-Stil

Der DMG-Erstellungsprozess basiert auf dem projektübergreifend verwendeten WSS-Distribution-Workflow.

- `wss-layout.json`: feste gemeinsame WSS-Layoutparameter. 640 × 480 pt Hintergrund, heller Installationsbereich oben, schwarzer Branding-Bereich unten, 240-pt-WSS-Logo, grauer Pfeil, 80-pt-Icons. Keine Karten oder zusätzlichen Installationstexte.
- `app-dmg.json`: Appname, Bundle-Identifier, Projekt/Scheme, erwartete Version/Build/Mindestversion, Pfad zum bereits vorhandenen AppIcon innerhalb der App, Volume-Name und DMG-Dateiname.
- `render-dmg-background.swift`: rendert daraus den separaten Hintergrund; `WSS_Logo.png` bleibt unverändert.
- `configure-dmg.py`: Finder-Fenster und Iconpositionen aus derselben Vorlage. `Programme` ist ein Link auf `/Applications`.
- `set-dmg-icon.swift`: weist der DMG-Datei das bereits vorhandene AppIcon zu. `.VolumeIcon.icns` innerhalb der DMG ist eine exakte Kopie des kompilierten AppIcon; das Custom-Icon-Flag des Volumes wird gesetzt. Kein zweites Icon-Design.

## Erneut bauen

Voraussetzungen: macOS, Xcode und Python 3.10 oder neuer mit `venv`/`pip`; Internetzugang für die versionsgebundenen Buildwerkzeuge `ds-store 1.3.3` und `mac-alias 2.2.3`. Diese werden isoliert in `/private/tmp` installiert und nicht mitgeliefert. Apples Python 3.9 reicht hierfür nicht; gegebenenfalls `PYTHON` auf einen bereits installierten neueren Interpreter setzen.

```sh
bash Distribution/build-dmg.sh
```

Optional: `PYTHON=/pfad/zu/python3`. Eine vorhandene Ausgabe vorher verschieben; das Script überschreibt sie nicht. Ohne `APP_PATH` baut das Script ausschließlich die mittels `git archive HEAD` exportierten, committed App-Quellen als frisches Universal-Release-Archiv.

Xcode signiert das Release-Archiv ad hoc (`CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY=-`) und übernimmt dabei die im Projekt definierten Entitlements. Das Script deaktiviert die Signierung nicht und signiert die App anschließend nicht erneut. `verify-app.py` prüft beide Architekturen einschließlich Sandbox und benutzergewähltem Nur-Lese-Zugriff, Version, Mindestversion, Sprachen und AppIcon. Diese Prüfung erfolgt vor dem Packaging und nochmals direkt im schreibgeschützt gemounteten fertigen DMG. Fehlende Entitlements führen zum Abbruch; dies gilt auch für ein übergebenes `APP_PATH`.

Für andere WSS-Apps oder spätere Versionen nur die app-spezifische Konfiguration anpassen, die gemeinsame Layoutdatei beibehalten. Ein bereits erzeugtes Release-App-Bundle kann explizit übergeben werden:

```sh
APP_PATH=/pfad/zur/Release-App.app APP_CONFIG=/pfad/app-dmg.json OUTPUT=/pfad/App-1.0.dmg bash Distribution/build-dmg.sh
```

`LAYOUT_CONFIG` kann ebenfalls gesetzt werden. `DMG-Commit.txt` dokumentiert den Commit beim frischen Archivbau; bei einem übergebenen `APP_PATH` muss dessen Herkunft separat nachvollzogen werden. Die Prüfsumme liegt neben der DMG. Temporäre Builds/Archive/Werkzeuge werden nie in die DMG aufgenommen.

## Signierung und Gatekeeper

Die veröffentlichte App ist **ad-hoc signiert**. Sie ist **nicht mit einer Apple Developer ID signiert und nicht von Apple notarisiert**. macOS/Gatekeeper kann deshalb nach dem Download den ersten Start blockieren.

Nach einem blockierten Start kann der Benutzer die App bewusst über **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** freigeben. Diesen Schritt nur vornehmen, wenn die Herkunft der App vertrauenswürdig ist. [Weitere Informationen von Apple](https://support.apple.com/de-de/102445).

Für die derzeitige kostenlose Open-Source-Hobbyprojekt-Verteilung wird bewusst kein kostenpflichtiger Apple-Developer-Account verwendet. Dieser Signierungszustand ist eine bewusste Eigenschaft der Verteilung und keine Zusage einer späteren Developer-ID-Signierung oder Notarisierung.

Nutzerhinweise zur Installation und zum ersten Start stehen in der [deutschen README](../README.md#installation-und-erster-start) und auf Englisch in der [English README](../README.en.md#installation-and-first-launch).

Das Volume-Icon ist Teil der DMG. Das zusätzliche Finder-Icon der äußeren DMG-Datei wird in macOS-Dateimetadaten gespeichert und kann bei einer Übertragung ohne Metadaten verloren gehen; das enthaltene Volume-Icon bleibt erhalten.
