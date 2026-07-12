import SwiftUI
import AppKit

// stamps each game's official steam icon onto its desktop shortcut, and
// makes the shortcut's finder label read as the plain game name.
//
// steam-under-wine drops a .desktop and a .url shortcut onto the real
// macOS desktop for every installed game. each one points at the real
// steam-assigned icon via an ICONFILE line
// (C:\Program Files (x86)\Steam\steam\games\<hash>.ico inside the bottle),
// but macOS renders neither shortcut format natively, so they show up as
// blank generic files with the raw ".desktop"/".url" extension visible.
//
// this loads that official .ico, upscales it with nearest-neighbor so the
// pixel art stays crisp at every finder size, sets it as the file's custom
// icon, and hides the extension so the label is just "Fields of Mistria".

enum GameIcon {
    // the finder sizes worth carrying so every place finder draws the icon
    // (dock, get-info, list/column/icon views, quick look) has a sharp rep.
    private static let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512]

    // the official steam icon for a game, read from the shortcut's ICONFILE
    // path and mapped into the bottle. nil if the shortcut or the .ico is
    // missing, in which case the caller falls back to a themed medallion.
    static func official(for game: Game, bottle: URL, desktop: URL) -> NSImage? {
        guard let icoPath = officialIcoPath(for: game, bottle: bottle, desktop: desktop),
              FileManager.default.fileExists(atPath: icoPath),
              let src = NSImage(contentsOfFile: icoPath) else { return nil }
        return crisp(src)
    }

    // parses the ICONFILE=C:\...\<hash>.ico line out of the game's .url
    // shortcut and rewrites the windows path onto the bottle's drive_c.
    private static func officialIcoPath(for game: Game, bottle: URL, desktop: URL) -> String? {
        let urlFile = desktop.appendingPathComponent("\(game.name).url")
        guard let text = try? String(contentsOf: urlFile, encoding: .utf8) else { return nil }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("iconfile=") else { continue }
            let winPath = String(line.dropFirst("iconfile=".count))
            // "C:\Program Files (x86)\..." -> "<bottle>/drive_c/Program Files (x86)/..."
            guard let colon = winPath.firstIndex(of: ":") else { return nil }
            let afterDrive = winPath[winPath.index(after: colon)...]          // "\Program Files..."
            let unixTail = afterDrive.replacingOccurrences(of: "\\", with: "/")
            let driveC = bottle.appendingPathComponent("drive_c")
            return driveC.path + unixTail
        }
        return nil
    }

    // redraws the source icon into a fresh multi-size image with
    // interpolation disabled, so upscaling a small (often 32px) steam .ico
    // to finder's larger sizes keeps hard pixel edges instead of blurring.
    private static func crisp(_ src: NSImage) -> NSImage {
        let out = NSImage(size: NSSize(width: 512, height: 512))
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
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
            ctx?.imageInterpolation = .none
            NSGraphicsContext.current = ctx
            src.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                     from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            out.addRepresentation(rep)
        }
        return out
    }
}

// a themed locket-medallion icon in the app's coquette style, used only as
// a fallback when a game has no official steam .ico to borrow.
enum GameIconTheme {
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

    private static func hash(_ appID: String) -> Double {
        let sum = appID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360)
    }

    private static func draw(initial: String, hueShift: Double, in rect: NSRect) {
        let bg = NSColor(Palette.bgOuter)
        bg.setFill()
        NSBezierPath(rect: rect).fill()

        let ringColor = NSColor(Palette.gold).blended(withFraction: 0.18, of: NSColor(hue: CGFloat(hueShift / 360), saturation: 0.35, brightness: 1, alpha: 1)) ?? NSColor(Palette.gold)

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
// desktop, stamps each with its official steam icon (falling back to a
// themed medallion), and hides the .desktop/.url extension so the label
// reads as the plain game name. steam regenerates these shortcuts whenever
// it notices a game installed, always blank-iconed and extension-bare, so
// this is safe and cheap to re-run on every refresh.
enum DesktopShortcuts {
    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    static func retheme(_ games: [Game], bottle: URL) {
        for game in games {
            let icon = GameIcon.official(for: game, bottle: bottle, desktop: desktop)
                ?? GameIconTheme.icon(for: game)
            for ext in ["desktop", "url"] {
                var file = desktop.appendingPathComponent("\(game.name).\(ext)")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                NSWorkspace.shared.setIcon(icon, forFile: file.path, options: [])
                // show the label as just the game name, not "<game>.desktop".
                var values = URLResourceValues()
                values.hasHiddenExtension = true
                try? file.setResourceValues(values)
            }
        }
    }
}
