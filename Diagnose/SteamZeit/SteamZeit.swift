import Foundation
import Darwin

// Separate process: only Steam initialization, callbacks, time query and shutdown.
let libraryPath = ProcessInfo.processInfo.environment["STEAM_API_LIBRARY"] ?? ""
func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
guard !libraryPath.isEmpty else { fail("STEAM_API_LIBRARY muss auf die lokal installierte libsteam_api.dylib zeigen.") }
let folder = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
guard chdir(folder.path) == 0 else { fail("Diagnoseordner nicht erreichbar.") }
guard let library = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
    fail("Bibliothek konnte nicht geladen werden: " + String(cString: dlerror()))
}
func symbol<T>(_ name: String, as type: T.Type) -> T {
    guard let address = dlsym(library, name) else { fail("Fehlendes Symbol: " + name) }
    return unsafeBitCast(address, to: type)
}
let initialize = symbol("SteamAPI_Init", as: (@convention(c) () -> Bool).self)
let shutdown = symbol("SteamAPI_Shutdown", as: (@convention(c) () -> Void).self)
let callbacks = symbol("SteamAPI_RunCallbacks", as: (@convention(c) () -> Void).self)
let getUtils = symbol("SteamAPI_SteamUtils_v010", as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
let getTime = symbol("SteamAPI_ISteamUtils_GetServerRealTime", as: (@convention(c) (UnsafeMutableRawPointer) -> UInt32).self)
guard initialize() else { fail("SteamAPI_Init fehlgeschlagen. Steam muss unter demselben Benutzer angemeldet laufen und FT2 muss im Konto verfügbar sein.") }
defer { shutdown(); dlclose(library) }
guard let utils = getUtils() else { fail("SteamUtils-Schnittstelle nicht verfügbar.") }
let runID = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
let output = folder.appendingPathComponent("Messung-\(runID).csv")
guard FileManager.default.createFile(atPath: output.path, contents: nil) else { fail("CSV konnte nicht angelegt werden.") }
let file = try FileHandle(forWritingTo: output)
defer { try? file.close() }
func write(_ line: String) throws { try file.write(contentsOf: Data((line + "\n").utf8)) }
try write("# app_id=2418520; init=true; library=\(libraryPath); duration_seconds=180; interval_seconds=0.1")
try write("sample,date_before_unix,date_after_unix,monotonic_before_seconds,monotonic_after_seconds,steam_unix_seconds,system_minus_steam_seconds,call_duration_seconds")
func monotonic() -> Double { ProcessInfo.processInfo.systemUptime }
let started = monotonic()
var sample = 0
print("SteamAPI_Init erfolgreich. Messung läuft drei Minuten. CSV: \(output.path)")
fflush(stdout)
while monotonic() - started < 180 {
    callbacks()
    let monoBefore = monotonic()
    let before = Date().timeIntervalSince1970
    let steam = getTime(utils)
    let after = Date().timeIntervalSince1970
    let monoAfter = monotonic()
    let difference = (before + after) / 2 - Double(steam)
    try write(String(format: "%d,%.9f,%.9f,%.9f,%.9f,%u,%.9f,%.9f", locale: Locale(identifier: "en_US_POSIX"), sample, before, after, monoBefore, monoAfter, steam, difference, monoAfter - monoBefore))
    sample += 1
    // Absolute scheduling avoids accumulating the time spent performing each call.
    let delay = started + Double(sample) * 0.1 - monotonic()
    if delay > 0 { Thread.sleep(forTimeInterval: delay) }
}
try file.synchronize()
print("Fertig: \(sample) Messungen, \(output.path)")
