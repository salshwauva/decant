import SwiftUI
import AppKit

// renders a themed Finder icon for a game and stamps it onto that game's
// wine/steam-generated desktop shortcuts. steam-under-wine drops a raw
// .desktop and .url file straight onto the real macOS desktop for every
// installed game (the bottle's wine "desktop" folder is the real one), and
// macOS has no idea how to render an icon for either format, so they show
// up as generic blank files sitting next to mead's own pixel-art icon.
// this repaints them as a small locket medallion in the same coquette
// palette and pixel font as AppIcon-source.jpg: a round gold-ringed
// centerpiece over a soft pink field, scattered hearts and sparkles.
enum GameIconTheme {
    // matches the icon sizes a real .icns carries, so Finder has a sharp
    // representation at every size it actually draws (dock, get-info,
    // list view, quick look).
    private static let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]

    static func icon(for game: Game) -> NSImage {
        let initial = String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        let hue = hash(game.appID)

        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        for side in sizes {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(side), pixelsHigh: Int(side),
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            )!
            rep.size = NSSize(width: side, height: side)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(initial: initial, hueShift: hue, in: NSRect(x: 0, y: 0, width: side, height: side))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return image
    }

    // a stable, cheap per-game hue offset so each medallion reads as
    // distinct at a glance without needing bespoke art per title.
    private static func hash(_ appID: String) -> Double {
        let sum = appID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360)
    }

    private static func draw(initial: String, hueShift: Double, in rect: NSRect) {
        let bg = NSColor(Palette.bgOuter)
        bg.setFill()
        NSBezierPath(rect: rect).fill()

        let ringColor = NSColor(Palette.gold).blended(withFraction: 0.18, of: NSColor(hue: CGFloat(hueShift / 360), saturation: 0.35, brightness: 1, alpha: 1)) ?? NSColor(Palette.gold)

        // scattered hearts/sparkles ring, echoing AppIcon-source.jpg's trim.
        let accents: [(CGFloat, CGFloat, CGFloat, String, NSColor)] = [
            (0.16, 0.82, 0.07, "♥", NSColor(Palette.heart)),
            (0.85, 0.83, 0.055, "♥", NSColor(Palette.heartSoft)),
            (0.12, 0.55, 0.045, "✦", NSColor(Palette.gold)),
            (0.88, 0.52, 0.05, "✦", NSColor(Palette.goldBright)),
            (0.20, 0.22, 0.05, "♥", NSColor(Palette.heartSoft)),
            (0.80, 0.20, 0.06, "♥", NSColor(Palette.heart)),
            (0.5, 0.90, 0.04, "✦", NSColor(Palette.gold)),
        ]
        for (fx, fy, fSize, glyph, color) in accents {
            drawGlyph(glyph, color: color,
                      at: NSPoint(x: rect.width * fx, y: rect.height * fy),
                      size: rect.width * fSize)
        }

        // the medallion: dark plaque gradient disc, gold double ring, a
        // small bow-heart clasp at the top, and the game's initial in the
        // bundled pixel font.
        let discRect = rect.insetBy(dx: rect.width * 0.20, dy: rect.height * 0.20)
        let discPath = NSBezierPath(ovalIn: discRect)
        let gradient = NSGradient(colors: [NSColor(Palette.plaque), NSColor(Palette.plaqueDk)])
        gradient?.draw(in: discPath, angle: -90)

        discPath.lineWidth = rect.width * 0.018
        ringColor.setStroke()
        discPath.stroke()

        let innerRing = NSBezierPath(ovalIn: discRect.insetBy(dx: rect.width * 0.02, dy: rect.width * 0.02))
        innerRing.lineWidth = rect.width * 0.006
        NSColor(Palette.goldBright).setStroke()
        innerRing.stroke()

        drawGlyph("♥", color: NSColor(Palette.heart),
                   at: NSPoint(x: rect.width * 0.5, y: discRect.maxY + rect.height * 0.02),
                   size: rect.width * 0.075)

        if let font = NSFont(name: "PixelifySans-Bold", size: rect.width * 0.26) ?? NSFont(name: "PixelifySans-Bold", size: 1) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "PixelifySans-Bold", size: rect.width * 0.26) ?? font,
                .foregroundColor: NSColor(Palette.textCream),
            ]
            let str = NSAttributedString(string: initial, attributes: attrs)
            let strSize = str.size()
            str.draw(at: NSPoint(x: discRect.midX - strSize.width / 2,
                                  y: discRect.midY - strSize.height / 2.6))
        }
    }

    private static func drawGlyph(_ glyph: String, color: NSColor, at point: NSPoint, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: point.x - strSize.width / 2, y: point.y - strSize.height / 2))
    }
}

// finds the wine/steam-generated shortcuts for installed games on the real
// desktop and restyles them. steam under wine regenerates these each time
// it notices a game is installed, always with a generic or missing icon,
// so this is safe (and cheap) to re-run on every refresh.
enum DesktopShortcuts {
    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    static func retheme(_ games: [Game]) {
        for game in games {
            let icon = GameIconTheme.icon(for: game)
            for ext in ["desktop", "url"] {
                let path = desktop.appendingPathComponent("\(game.name).\(ext)").path
                guard FileManager.default.fileExists(atPath: path) else { continue }
                NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
            }
        }
    }
}
