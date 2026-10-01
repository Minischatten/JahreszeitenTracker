# Drei-Minuten-Messung vom 1. Oktober 2026

Start: 08:38:31 UTC / 10:38:31 Berliner Ortszeit.
SteamAPI_Init außerhalb der Codex-Sandbox erfolgreich; innerhalb der Sandbox
war die Steam-Verbindung nicht verfügbar. Vollständig beendet, Exitcode 0.

CSV: `Messung-2026-10-01T08-38-31Z.csv`

| Größe | Ergebnis |
|---|---:|
| Messungen | 1800 |
| Abstand erste bis letzte Messung, monoton | 179,898980 s |
| Systemzeit minus Steam-Ganzzahl, Minimum | +0,602181 s |
| Maximum | +1,602624 s |
| Mittelwert | +1,115494 s |
| Mittlere Differenz pro Minute | +1,124418 / +1,108349 / +1,113716 s |
| Median Dauer des eingerahmten Aufrufs | 0,000509 s |
| Maximale Dauer | 0,007560 s |
| Größter Messabstand | 0,105825 s |
| Steam-Schritte zwischen Messungen | 1619 × 0 s, 180 × +1 s |
| Änderung Systemzeit gegenüber monotoner Zeit insgesamt | +0,001047 s |

Die Messung zeigt einen stabilen positiven Unterschied zum gelieferten
Steam-Ganzsekundenwert mit ungefähr einer Sekunde Spannweite. Keine negativen
Steam-Schritte, Mehrsekundensprünge oder langen Messpausen wurden beobachtet.
Die Messung liefert keinen Hinweis auf eine Systemzeitkorrektur in der
Größenordnung einer Sekunde.

Die Steam-Sekundensprünge wurden jeweils zwischen benachbarten Messungen
eingeklammert: untere Grenzen Systemzeit minus neuer Steam-Sekunde
0,498929 bis 0,602624 s, obere Grenzen 0,602181 bis 0,704158 s.
Das ist mit einer weitgehend stabilen Sprungphase um +0,60 s vereinbar.
Die Rohwert-Spannweite ist nicht als Schwankung eines kontinuierlichen
Steam-/Systemzeit-Offsets um eine Sekunde zu interpretieren.

Ohne Kenntnis der internen Quantisierung kann daraus kein exakt bestimmter
kontinuierlicher Steam-/Systemzeit-Offset abgeleitet werden. Der Mittelwert
enthält Quantisierung und die konkrete Abtastphase.

Die Richtung passt zum Vorsprung des Trackers. Die Zeitquellen liefern hier
einen Beitrag von ungefähr 0,6 bis 1,6 Sekunden, aber keine alleinige Erklärung
für eine präzise gemessene Differenz von 2 bis 3 Sekunden. Die bisherigen
visuellen Vergleiche waren nicht präzise. FT2-Tickphase, Widget-Aktualisierung
und Tracker-Anzeige wurden in diesem isolierten Test nicht gemessen.

Aus diesem kurzen Test lässt sich kein fester Korrekturoffset oder eine
langfristige Drift ableiten. Der Spielprozess wurde weder geöffnet noch
untersucht; ob FT2 während der Messung geschlossen war, wurde nicht überprüft.
