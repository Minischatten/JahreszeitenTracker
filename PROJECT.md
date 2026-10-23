# JahreszeitenTracker – technischer Arbeitskontext

Diese Datei dient als kompakter Einstieg für die Projektarbeit und Codex. Maßgeblich
bleiben Code, Tests und Build-Konfigurationen. Bei fachlichen Änderungen diesen
Kontext mitpflegen; keine vollständige Entwicklungschronik führen.

## Zweck und Plattform

Kostenloses Hobbyprojekt für Farm Together 2 (FT2): aktuelle Saison und Restzeit
pro Hauptfarm aus Spielständen ableiten und unabhängig vom laufenden Spiel anzeigen.
Enthalten sind automatische Erkennung/Synchronisation, Farmübersicht und Details,
persistente Kartenreihenfolge per Drag & Drop, ausgeblendete/inaktive Farmen sowie
einmalige Saison-Erinnerungen. Keine manuelle Saison-/Zeitkorrektur in der Oberfläche.

- Native macOS-App, Minimum macOS 14.0; Release universal für `arm64` und `x86_64`.
- SwiftUI mit gezielten AppKit-Brücken; Foundation/Combine, System-zlib und
  UserNotifications. Keine Swift Packages oder eingebetteten FT2-/Steam-Bibliotheken.
- `JahreszeitenTrackerApp.swift`: gemeinsame Instanzen, Fenster, Settings und Commands.
- `TrackerCore.swift`: Zeit-/Saisonarithmetik und zentrale Versionspolitik ohne UI,
  Timer oder Persistenz; Berechnungen bekommen den Zeitpunkt explizit übergeben.
- `FT2SaveParser.swift` / `FT2FarmMetadata.swift`: Plot- bzw. Metadatenparser.
- `FT2SaveAccess.swift`: macOS-Dateizugriff, konsistente Snapshots und Plot-Auswahl.
- `FarmCatalog.swift`: Identitäten, Referenzen, Merge, Reihenfolge, Status und Navigation.
- `FarmManager.swift`: MainActor-ObservableObject, Persistenz und Scan-Steuerung;
  Dateilesen erfolgt in einem abgetrennten Task. Polling ungefähr alle 10 Sekunden.
- `ContentView`, `FarmCardView`, `SettingsView`, `AboutView`, `ReminderView`: Darstellung.

## FT2-Zugriff: ausschließlich lesen

Der Benutzer wählt seinen Steam-ID-Ordner ausdrücklich über `NSOpenPanel` aus.
Üblicher Pfad:

```text
~/Library/Application Support/Milkstone Studios/FarmTogether2/SteamStorage/<Steam-ID>/
```

Der Dialog schlägt das vorhandene `SteamStorage` vor, andernfalls das Benutzer-Home.
Keine automatische Steam-ID-Auswahl oder rekursive Spielstandsuche.

App Sandbox und `user-selected.read-only` bleiben aktiv. Security-Scoped Bookmarks
werden mit `.securityScopeAllowOnlyReadAccess` erzeugt. `FT2SaveAccess` öffnet Dateien
mit `O_RDONLY`/`O_NOFOLLOW`, akzeptiert nur reguläre Dateien und prüft Größe sowie
Änderungszeiten vor/nach dem Lesen. Verknüpfte Plot-Verzeichnisse werden abgelehnt;
`farms.mlk` wird am Scan-Ende erneut verglichen. Entpacken nur im Arbeitsspeicher.
**Niemals FT2-Dateien ändern, löschen oder zurückschreiben.**

## Format, Erkennung und Identität

- `farms.mlk` registriert Hauptfarmen: Version und Einträge mit `slotIndex`,
  `farm.creation_time` und `farm.name`. Byte-Transformation, Gzip, danach normalisiertes
  JSON mit teils unquoted Schlüsseln; keine Ausführung des gelesenen Textes.
- Zugehörige Plot-Dateien liegen in `farms/`: exakt `farm_<slot>_<index>.data`.
  Kanonische nichtnegative Integer-Indizes, keine feste Bereichsobergrenze, keine
  Rekursion. Andere Slots, globale `farm_<slot>.data`, Backups und ungültige Namen
  werden ausgeschlossen. Nur vorhandene Bereichsdateien zählen; nicht vorhandene Bereiche werden nicht
  künstlich ergänzt.
- Plot-Saves: Gzip und beobachtete FT2-Binärvariante, **kein Standard-MessagePack**.
  Feld 0 ist die Version; Synchronisationsfelder sind 15, 16, 18 und 21.
  Der Parser durchläuft das gesamte Dokument, überspringt unterstützte unbekannte
  Felder und validiert Typen, doppelte Schlüssel, Grenzen und vollständiges Ende.
  Größenlimits: komprimiert 16 MiB, entpackt 64 MiB; weitere Struktur-/Tiefenlimits
  stehen im jeweiligen Parser.
- `FarmIdentity = sourceID (UUID) + slotIndex + creationTime`. Name und Slot allein
  sind keine Identität. `sourceID` gehört zur gespeicherten Ordnerquelle; Wiederwahl
  desselben gespeicherten Pfades verwendet deren UUID weiter.
- Slot-Wiederverwendung mit anderer `creation_time` erzeugt eine neue Farm. Plot-Saves
  vor deren Erstellungszeit werden ignoriert. Exakt wiederkehrende Identitäten können
  durch bestätigte Metadaten wieder registriert werden.
- Neueste Referenz anhand **eingebetteter Feld-16-Zeit**, nicht Dateimodifikation oder
  Dateiname. Alle vier Timingwerte gemeinsam aus derselben Plot-Datei übernehmen.
  Widersprüchliche neueste Gleichstände werden abgelehnt; ältere Referenzen ersetzen
  keine neueren. Bei gleichem Zeitpunkt und gleichem Zustand bleibt die Referenz gültig.

## Versionen und Vertrauensmodell

Zentrale Freigabe: `FT2VersionPolicy.confirmed` in `TrackerCore.swift`:
**347, 350, 352**. **348, 349 und 351 sind nicht bestätigt.**
`mayRead` erlaubt bestätigte Versionen sowie Versionen größer als 347 zum defensiven
Leseversuch. Strukturell lesbar bedeutet nicht bestätigt; neue Freigaben benötigen
reale Datenprüfung und Praxistest, keine automatische Bestätigung von Zwischenversionen.

- Bestätigt und aktuell verifiziert: normaler Synchronisationsstatus.
- Unbestätigt, aber vollständig validiert: für bereits registrierte, exakt passende
  Identitäten können Referenzen aktualisiert werden; sichtbar bleibt eine Versionswarnung.
- Nicht sicher lesbar: keine neue Referenz; vorhandene gültige Referenz bleibt erhalten.
  Ohne Referenz keinen Countdown erfinden. Versionsbeobachtungen werden persistiert;
  eine alte gültige Datei darf Warnungen über erkannte inkompatible Dateien nicht verdecken.
- **Nur vollständige erfolgreiche Metadaten-Scans einer bestätigten Version sind
  autoritativ für Registrierung, Namen und neue Identitäten.** Unbestätigte Metadaten
  löschen/deaktivieren keine bekannten Farmen, übernehmen keine Umbenennungen und
  erzeugen keine neue persistente Farmidentität oder deren Countdown. Inaktive Farmen
  werden dadurch nicht reaktiviert.
- Nicht lesbare Metadaten sind kein leerer Katalog. Einzelne/alle ungültige Plot-Dateien
  sind keine gelöschte Farm; letzte Referenzen bleiben erhalten. Details:
  `FarmCatalog.apply/merge`, `FT2SaveAccess.areaSnapshot`.

## Zeitmodell und Anzeige

- Feld 15 `worldTicks`: globale interne Sekundenachse.
- Feld 16: Save-Zeit als .NET-DateTime-Ticks; `10_000_000` Ticks/Sekunde,
  Unix-Epoche `621_355_968_000_000_000`. Beobachtete Saves entsprechen UTC;
  DateTime.Kind ist in diesen Bytes nicht enthalten.
- Feld 18 `nextSeasonChange`: nächste Grenze auf der internen Zeitachse.
- Feld 21 `currentSeason`: 0 Frühling, 1 Sommer, 2 Herbst, 3 Winter.
- Saisonlänge **1020 Sekunden**, Viererzyklus **4080 Sekunden**. Gespeicherter
  Saisonbeginn = `savedAt + (nextBoundary - gameTime) - 1020`.
  `SeasonCalculator` berechnet mit absoluter Systemzeit und positiv normalisiertem
  Modulo; keine fortlaufende Timer-Akkumulation, auch mehrere Offlinewechsel sind möglich.
- Validierung u. a.: `gameTime >= 0`, Grenze strikt danach und höchstens 1020 Sekunden
  entfernt, Index 0–3, Save höchstens 300 Sekunden in der Zukunft; genaue Limits im Code.
- **Nur Anzeige:** `CountdownDisplay.seconds = Int(min(remaining + 2, 1020))`.
  +2 Sekunden und 17:00-Clamp nicht auf Saison, Referenz, Wechsel oder Reminder anwenden.
  Keine zweite Zeitlogik einführen. Messergebnisse und Aussagegrenzen der empirischen
  Kompensation stehen in `SAVE_SYNCHRONISATION.md`; Steam-Laufzeitbibliothek unnötig.

## Status, Darstellung und sensible UI-Regeln

`FarmSyncState` unterscheidet „Synchronisiert“, „Letzter Stand“, „Warte auf Spielstand“,
„Farm nicht mehr gefunden“, „Neue Spielstandversion erkannt“, „Letzter Stand – neue
Spielstandversion“ und „Neue Spielstandversion nicht lesbar“. Nur bestätigte und
aktuell verifizierte Referenzen erhalten das grüne Synchronisiert-Symbol. Ordnerausfall
verhindert nicht das Weiterrechnen einer vorhandenen Referenz.

- `registered=false` entsteht bei bestätigter Abwesenheit im autoritativen Katalog.
  Inaktive Farm bleibt grau, anklickbar, mit letzter Referenz und bisheriger Position.
  Endgültiges Entfernen nur nach Bestätigung, vollständig aus dem Tracker, nie aus FT2.
- `hidden` ist persistent pro vollständiger Identität; fehlendes Feld wird als `false`
  geladen. Änderung nur identitätsbasiert über den Manager, keine veraltete Farmkopie
  zurückschreiben. Verstecken schließt eine geöffnete Detailansicht nicht.
- `FarmPresentationSession.showHiddenFarms` ist gemeinsamer, **nichtpersistenter**
  Sitzungszustand mit Startwert `false`. Menü und Views teilen dieselbe Instanz.
  Commands beobachten ausschließlich dieses Modell, **nicht den regelmäßig publizierenden
  FarmManager**: sonst droht Neuaufbau des geöffneten Darstellung-Menüs mit Verlust
  von Systemeinträgen. Keine zusätzliche Persistenz oder AppKit-Menüreparatur einführen.
- Eine bekannte und dargestellte Farm: automatische Details. Mehrere bekannte Farmen:
  Übersicht, auch wenn nur eine sichtbar ist. Alle versteckt: eigener Leerzustand.
  Explizites Notification-Routing kann versteckte Farmen öffnen.
- Katalogarray ist die einzige persistente Reihenfolge. Gefiltertes D&D belegt nur
  Positionen dargestellter Farmen neu; versteckte behalten ihre Katalogposition.
  Neue Identitäten werden angehängt; Umbenennen/Inaktivität ändern die Reihenfolge nicht.
- `InitialWindowFocus` in `ContentView.swift`: öffentlicher AppKit-Startresponder,
  Schutz auch bei späteren initialen Layouts bis zur ersten bewussten Eingabe.
  Tab/Shift-Tab übergeben an gültige native Key-Views; Helper ist keine dauerhafte
  Tab-Station. Native Button-Fokussierbarkeit, Space, Klick, Hover und D&D erhalten.
  Kein `.focusable(false)`, keine privaten SwiftUI-Klassen oder zeitbasierten Delays.

## Einmalige Saison-Erinnerungen

`SeasonReminder`/`ReminderRules` enthalten Identität und Terminlogik;
`ReminderManager` verwaltet Zustand/Persistenz, `MacNotificationService` bindet
UserNotifications an. Berechtigung erst beim Setzen einer Erinnerung anfragen.

Neue Erinnerung nur für registrierte Farm mit bestätigter Referenz und ohne offene
Versionsprobleme. Ziel ist der nächste Beginn der gewählten Saison; bei aktuell
laufender Zielsaison deren nächster Zyklus. Termin aus derselben unkompensierten
Referenz berechnen, Systemtrigger auf volle Sekunde aufrunden, `repeats=false`.

Pro Farm wird beim Setzen der bisherige Reminder ersetzt. Request-ID
`season-reminder.<Reminder-UUID>` bleibt beim Korrigieren/Umbenennen gleich.
Neue gültige Referenz korrigiert das ursprünglich gewählte Ereignis, nicht automatisch
zum nächsten Zyklus rollen. Verstecken lässt Reminder bestehen; bestätigte Inaktivität
bricht ihn ab, endgültig fehlende Farm und manuelles Abbrechen entfernen ihn.
Abgelaufene Termine werden `expired`; fehlender zukünftiger Systemrequest wird beim
Wiederherstellen `cancelled`, nicht automatisch neu geplant. Terminale Datensätze können
persistiert bleiben; daraus folgt keine Wiederholung.

Systemregistrierte lokale Benachrichtigungen benötigen keinen eigenen Hintergrundprozess.
Routing verwendet vollständige FarmIdentity, kann Fenster öffnen/App aktivieren, auch
für versteckte Farmen. Tests mit echtem macOS müssen insbesondere Zustellung bei aktivem
Fenster, geschlossenem Fenster und nach ⌘Q sowie Klick/Kaltstart-Routing abdecken;
Systemberechtigungen und Zustellung nicht allein aus Unit-Tests ableiten.

## Persistenz und Lokalisierung

`UserDefaults.standard` der sandboxed App, jeweils JSON als Data:

- `ft2FarmCatalog_v2`: Quellen (UUID, Pfad, Read-only-Bookmark, Metadatenhinweise),
  aktive/angezeigte Quelle, ausgewählte Identität, Farmen samt Reihenfolge, Name,
  Hidden-/Registrierungszustand, Versionsinformationen und letzter Referenz.
- `seasonReminders_v1`: Reminder-ID, vollständige Farmidentität, Zielindex, Zeitpunkte,
  Referenz, Name und Zustand. Systemrequests zusätzlich durch macOS verwaltet.

Wiederherstellung validiert Katalog/Referenzen; Verfügbarkeit und aktuelle Verifikation
werden beim Start zurückgesetzt. Zugriff entfernen behält Referenzen, deaktiviert
jedoch die aktive Quelle. Container und Preferences folgen der Bundle-ID; deren Änderung
ist keine transparente Migration. Keine Containerbereinigung als Nebenwirkung.

Deutsch ist Entwicklungssprache (`developmentRegion=de`), Englisch zweite Sprache.
`Localizable.xcstrings`, native Apple-Sprachwahl, kein eigener Schalter/Spracherkennung.
Volle lokalisierte Satzvorlagen mit unveränderten dynamischen Parametern verwenden;
keine lokalisierten Strings als Identitäten oder fachliche Entscheidungswerte.

## Release, Distribution und Lizenz

- Aktuelle konfigurierte Version **1.0.2 (Build 4)** in Projekt und `Distribution/app-dmg.json`.
- Dauerhafte Bundle-ID: `com.wirdschonsoftware.jahreszeitentracker` (Debug/Release).
  Eigener D&D-Typ: `com.wirdschonsoftware.jahreszeitentracker.farm-card`.
- WSS-DMG: `Distribution/build-dmg.sh`, `wss-layout.json`, `app-dmg.json`; kein Layout
  bei jedem Release neu interpretieren. Standardmäßig committed Quellen über
  `git archive HEAD`, alternativ explizites `APP_PATH` mit separat belegter Herkunft.
- Ad-hoc-Signierung über Xcode mit Projekt-Entitlements, keine Developer ID/Notarisierung,
  keine Zusage dafür. Gatekeeper-Freigabe wie in den READMEs beschrieben; keine globalen
  Sicherheits-Deaktivierungen dokumentieren. Keine Updateprüfung implementiert.
- `verify-app.py` prüft Universal-App, Version, Mindestversion, Bundle-/Signatur-ID,
  Sandbox/Read-only, Sprachen und AppIcon vor Packaging **und in der fertigen DMG**.
  Volume-Icon aus AppIcon, `Programme` → `/Applications`; temporäre Buildwerkzeuge
  nicht mitliefern. Details in `Distribution/README.md` / `README.en.md`.
- Generierte `Distribution/DMG-Background.png`, `DMG-Commit.txt`, `*.dmg` und
  `*.dmg.sha256` sind ignoriert; Scripts/Templates/Konfigurationen bleiben versioniert.
- **GPL-3.0-only** für eigene Code-/Test-/Dokumentations-/Buildbestandteile und Saisonbilder.
  WSS-Logo, AppIcon und transparente README-Iconvariante sind separat lizenziert:
  exakte Dateien/Bedingungen in `BRANDING.md` / `BRANDING.en.md`. Keine pauschale
  GPL-Freigabe aller Assets. `Distribution/WSS_Logo.png` ist unverändertes Original.
- Keine Original-Saves, FT2-/Steam-DLLs oder dekompilierten Quelltexte mitliefern.
  Testprojektionen enthalten kleine technische Einzelwerte; keine vollständigen Saves.

## WSS-Website

`wirdschonsoftware.com` besitzt eine minimale statische Landingpage auf Deutsch und
Englisch. WirdSchonSoftware wird ausdrücklich als gemeinsamer Name für private
Softwareprojekte dargestellt, nicht als Firma oder Unternehmen. Der JahreszeitenTracker
wird als öffentliches Projekt mit Verweis auf sein GitHub-Repository vorgestellt.
Impressum und Datenschutzerklärung sind vorhanden. Keine Analytics, kein Tracking,
keine Cookies und keine extern geladenen Assets. HTTPS ist eingerichtet; HTTP wird
auf HTTPS umgeleitet, HSTS ist aktiviert.

## Verifikation bei Änderungen

- `sh Tests/run-tests.sh`: Core-/Parser-/Katalog-, Manager-, Reminder- und Lizenzprüfungen.
- `sh Tests/run-localization-tests.sh /pfad/zur/JahreszeitenTracker.app`: tatsächliches
  Bundle, DE/EN, Sprach-Fallback, UI-/Navigations-/Fokusprüfungen und Vorschauen.
  String-Catalog-JSON allein belegt keine nutzbare Bundle-Lokalisierung.
- Für Releases Debug und Universal-Archive prüfen, Mach-O beider Architekturen und
  macOS-14-Minimum kontrollieren; Signatur/Entitlements ausdrücklich an gemounteter
  DMG-App. Mount-/Kopiertest, SHA-256, Icons und unverändertes WSS-Layout kontrollieren.
- Regressionen besonders für Versionstrust/gemischte Saves, Slot-Reuse, Lesefehler,
  Referenzkonflikte, Hidden/D&D/Navigation sowie Reminder-Lifecycle erhalten.
  Versionsfreigaben benötigen reale FT2-Daten und Saison-/Countdown-Praxistest.
- Menü bei laufenden Scans geöffnet lassen; Initialfokus mit 1/mehreren sichtbaren
  Karten, Hidden-Filter und Versionswarnung sowie Tab/Shift-Tab/Space manuell prüfen.
- Keine persönlichen Pfade/Steam-IDs, fremde Analyseartefakte oder temporäre Diagnostik
  in öffentliche Quellen aufnehmen. Vor Commit Diff und Status prüfen; generierte
  Distribution-Artefakte nicht versionieren. Diese Datei autorisiert keine Commits,
  Pushes, History-Rewrites oder Veröffentlichungen.

## Offene Ideen / nächste mögliche Arbeiten

**Arbeitsoptionen, keine zugesagten Features und keine öffentliche Roadmap.**
Die folgenden Prioritäten und externen Beobachtungen stammen aus dem aktuellen
Arbeitsauftrag; sie sind nicht als bereits implementierter Repository-Stand zu lesen.

1. **First-Run-Onboarding**
   Prüfen, ob Einstellungen bei wirklich unkonfigurierter Installation automatisch
   geöffnet werden sollten. Echten First Run ohne konfigurierte Quelle von einem
   konfigurierten, vorübergehend nicht erreichbaren/nicht lesbaren Ordner unterscheiden.
2. **Automatische Updateprüfung**
   Konzept über GitHub-Veröffentlichungen untersuchen, insbesondere Sparkle-Eignung.
   Sicherheits-, Signatur-, Appcast- und Distributionsanforderungen berücksichtigen;
   noch keine konkrete Implementierungsentscheidung voraussetzen.
3. **DMG-Dateiicon nach Download**
   Nach beobachtetem Downloadweg geht das äußere Finder-Icon verloren, während das
   Volume-Icon erhalten bleibt. Bei künftigem Release portable Erhaltung oder bewussten
   Verzicht untersuchen. Kein aktueller Funktionsfehler, kein Anlass für neuen Release.
4. **Pflanz-/Ernteinformationen**
   Größere mögliche Erweiterung: verlässlich aus FT2-Daten ermitteln, was aktuell
   saisonal anpflanzbar bzw. bei relevanten Pflanzen/Kräutern erntbar ist. Änderungen
   zwischen FT2-Versionen berücksichtigen. Keine Zusage für Version 2.0 oder einen Release.
