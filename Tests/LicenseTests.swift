import Foundation
import CryptoKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    precondition(condition, message)
}
func text(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
let license = try Data(contentsOf: root.appendingPathComponent("LICENSE"))
let checksum = SHA256.hash(data: license).map { String(format: "%02x", $0) }.joined()
// Pin the complete, unmodified text retrieved from gnu.org/licenses/gpl-3.0.txt.
check(checksum == "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986", "complete official GPLv3 text")
let readme = try text("README.md")
let branding = try text("BRANDING.md")
check(readme.contains("ausschließlich Version 3 (SPDX: GPL-3.0-only)"), "explicit version-3-only grant")
check(readme.contains("[LICENSE](LICENSE)") && readme.contains("[BRANDING.md](BRANDING.md)"), "license and branding navigation")
check(readme.contains("347, 350 und 352"), "documented confirmed save versions")
for document in [readme, branding] {
    check(!document.contains("GPL-3.0-" + "or-later"), "no later-version project grant")
}
let assetRoot = root.appendingPathComponent("JahreszeitenTracker/Assets.xcassets")
let iconFiles = try FileManager.default.contentsOfDirectory(atPath: assetRoot.appendingPathComponent("AppIcon.appiconset").path)
    .filter { $0.hasSuffix(".png") }
var expected = Set(iconFiles.map { "JahreszeitenTracker/Assets.xcassets/AppIcon.appiconset/" + $0 })
expected.insert("Documentation/Branding/JahreszeitenTracker-Icon.png")
expected.insert("Distribution/WSS_Logo.png")
expected.insert("JahreszeitenTracker/Assets.xcassets/WSS_Logo.imageset/WSS_Logo.png")
let listed = Set(branding.components(separatedBy: "\n").filter { $0.hasPrefix("- `") && $0.hasSuffix(".png`") }
    .map { String($0.dropFirst(3).dropLast()) })
check(expected.count == 13 && listed == expected, "exact separate-branding PNG inventory, no broad asset exclusion")
for path in listed {
    check(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "reserved graphic exists")
}
for season in ["Spring", "Summer", "Autumn", "Winter"] {
    check(readme.contains("Season\(season).imageset") && branding.contains("Season\(season).imageset/"), "season group explicitly GPL-covered")
    let files = try FileManager.default.contentsOfDirectory(atPath: assetRoot.appendingPathComponent("Season\(season).imageset").path)
        .filter { $0.hasSuffix(".png") }
    check(files.count == 3, "season 1x/2x/3x resources retained")
}
check(branding.contains("Die zugehörigen `Contents.json`-Dateien") && branding.contains("GPL-3.0-only"), "technical configurations remain GPL-covered")
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("JahreszeitenTracker/Localizable.xcstrings"))) as! [String: Any]
let strings = catalog["strings"] as! [String: Any]
check(strings["Quellcode: GPL-3.0-only\nBranding separat lizenziert."] != nil, "localized About license entry")
check(strings["Copyright © 2026 WirdSchonSoftware. Alle Rechte vorbehalten."] == nil, "obsolete blanket copyright entry removed")
print("Passed \(checks) licensing checks")
