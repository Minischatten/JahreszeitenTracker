# Lokalisierungsprüfungen

Die Fachtests bleiben unabhängig von der ausgewählten Sprache:

```sh
sh Tests/run-tests.sh
```

Nach einem App-Build prüft der separate native Testhelfer dessen tatsächlich
kompilierte Sprachressourcen und Bundle-Metadaten:

```sh
sh Tests/run-localization-tests.sh /absoluter/Pfad/JahreszeitenTracker.app
```

Vor dem Testhelfer prüft `BundleLocalizationTests.swift` das originale `.app`
direkt: Bundle-ID, Development-Sprache, `Bundle.localizations`, tatsächlich
vorhandene und lesbare `.lproj/Localizable.strings` sowie Apples Sprachauswahl
für Deutsch/Englisch einschließlich regionaler Sprachpräferenzen. Eine optionale
`CFBundleLocalizations`-Deklaration muss mit den Ressourcen übereinstimmen;
bei normalen `.lproj`-Ressourcen ist dieser Schlüssel nicht erforderlich.
Diese Prüfungen testen nicht die zwischengespeicherte Sprachauswahlliste der
Systemeinstellungen. Diese muss zusätzlich im nativen Dialog geprüft werden.

Der Helfer verwendet ausschließlich synthetische Farmdaten und eine temporäre,
isolierte UserDefaults-Domain. Er startet Deutsch, Englisch und den deutschen
Fallback bei einer nicht unterstützten Sprache über Apples `AppleLanguages`.
Alle Übersetzungen, Interpolationen, Saisonkennungen und Accessibility-Texte
werden geprüft. Gerenderte Übersichts-, Detail-, Einstellungs- und Dialogansichten
liegen im am Ende ausgegebenen temporären Vorschauordner. Der native NSAlert
prüft die Dialogtexte und deren Layout; er ersetzt keinen interaktiven Test des
tatsächlichen SwiftUI-Bestätigungsdialogs oder von VoiceOver.

Die App selbst besitzt keine Spracherkennung und keinen Sprachschalter.
`Localizable.xcstrings` enthält Deutsch als Ausgangssprache und Englisch.
Die normale macOS-Sprachauswahl bestimmt die Darstellung nach einem Neustart.
Farmnamen, Pfade, Versionsnummern und persistierte Kennungen bleiben unverändert.
