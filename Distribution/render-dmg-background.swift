import AppKit

let args = CommandLine.arguments
 guard args.count == 5, let logo = NSImage(contentsOfFile: args[3]) else {
    fatalError("Usage: swift render-dmg-background.swift layout.json app.json logo.png output.png")
}
let layout = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let app = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
func number(_ key: String) -> CGFloat { CGFloat((layout[key] as! NSNumber).doubleValue) }
let width = number("width"), height = number("height")
// Fixed pixel canvas for the shared WSS distribution layout, independent of screen scale.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: number("lightGray"), alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: width, height: number("brandingHeight")).fill()
let logoSize = number("logoSize")
logo.draw(in: NSRect(x: (width - logoSize) / 2, y: number("logoBottom"), width: logoSize, height: logoSize))
func centered(_ text: String, bottom: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let textWidth = (text as NSString).size(withAttributes: attributes).width
    (text as NSString).draw(at: NSPoint(x: (width - textWidth) / 2, y: bottom), withAttributes: attributes)
}
centered("\(app["appName"] as! String) installieren", bottom: number("titleBottom"),
    font: .systemFont(ofSize: number("titleSize"), weight: .semibold), color: .black)
centered(layout["subtitle"] as! String, bottom: number("subtitleBottom"),
    font: .systemFont(ofSize: number("subtitleSize")), color: .darkGray)
("→" as NSString).draw(at: NSPoint(x: number("arrowX"), y: number("arrowBottom")),
    withAttributes: [.font: NSFont.systemFont(ofSize: number("arrowSize"), weight: .light), .foregroundColor: NSColor.gray])
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
