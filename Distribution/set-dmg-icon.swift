import AppKit
let args = CommandLine.arguments
 guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]),
       NSWorkspace.shared.setIcon(icon, forFile: args[2], options: []) else {
    fatalError("Could not apply the existing app icon to the DMG file")
}
