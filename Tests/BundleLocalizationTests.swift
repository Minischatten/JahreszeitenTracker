import Foundation

// Inspect the original app bundle directly, without a replacement executable,
// copied Info.plist, resource symlink or dependency on the test host's language.
var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    precondition(condition, message)
}
for path in CommandLine.arguments.dropFirst() {
    guard let bundle = Bundle(path: path) else { fatalError("Invalid app bundle: \(path)") }
    check(bundle.bundleIdentifier == "Yasha.JahreszeitenTracker", "original application identity")
    check(bundle.developmentLocalization == "de", "German development language in original Info.plist")
    check(Set(bundle.localizations) == Set(["de", "en"]), "original bundle advertises both languages")
    if let declared = bundle.infoDictionary?["CFBundleLocalizations"] as? [String] {
        check(Set(declared).isSuperset(of: ["de", "en"]), "optional explicit declaration must agree with resources")
    }
    for (language, translation) in [("de", "Synchronisiert"), ("en", "Synced")] {
        let directory = URL(fileURLWithPath: path).appendingPathComponent("Contents/Resources/\(language).lproj")
        let file = directory.appendingPathComponent("Localizable.strings")
        check(FileManager.default.fileExists(atPath: file.path), "actual compiled \(language) resource exists")
        let data = try Data(contentsOf: file)
        let table = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        check(table["Synchronisiert"] == translation, "actual compiled \(language) translation")
        let licenseKey = "Quellcode: GPL-3.0-only\nBranding separat lizenziert."
        check(table[licenseKey] == (language == "de" ? licenseKey : "Source code: GPL-3.0-only\nBranding licensed separately."),
              "About license text present in actual compiled resource")
        check(table["Copyright © 2026 WirdSchonSoftware. Alle Rechte vorbehalten."] == nil,
              "no obsolete blanket copyright entry in compiled resource")
        let localizedBundle = Bundle(url: directory)!
        check(localizedBundle.localizedString(forKey: "Synchronisiert", value: nil, table: "Localizable") == translation,
              "native lookup directly in original \(language) resources")
        check(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [language]).first == language,
              "Apple resolves explicit/system \(language) preference")
    }
    check(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["en-US"]).first == "en", "English regional preference")
    check(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["de-DE"]).first == "de", "German regional preference")
    print("Original bundle: \(path) — languages: \(bundle.localizations.sorted()), development: \(bundle.developmentLocalization!)")
}
print("Passed \(checks) original-bundle localization checks")
