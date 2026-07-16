import SwiftUI

// the bright cellar palette: a warm daylight tasting-room, not a dark
// dungeon. cream/parchment grounds, honey-oak rack, brass nameplates,
// berry-wine accents, dark-on-light text. square corners with two-tone
// pixel bevels (see the bevel modifier) carry the retro-game feel.
enum Palette {
    // grounds
    static let bg        = Color(hex: 0xfbeaf1)
    static let bgHi      = Color(hex: 0xfef3f8)
    static let bgDeep    = Color(hex: 0xf2dbe6)
    static let page      = Color(hex: 0xe9cdd9)
    static let titlebar  = Color(hex: 0xf3dde8)
    static let titleEdge = Color(hex: 0xe0bdcf)

    // text (deep plum on light pink)
    static let ink       = Color(hex: 0x5a2440)
    static let inkDim    = Color(hex: 0x8a4568)
    static let inkMut    = Color(hex: 0xb07f98)
    static let cream     = Color(hex: 0xfdf3f8)

    // rosewood rack
    static let wood      = Color(hex: 0xc77b9e)
    static let woodDk    = Color(hex: 0xa85a80)
    static let woodEdge  = Color(hex: 0x7e3c5e)
    static let woodShade = Color(hex: 0x5a2440)  // bevel low-tone, rack shadow

    // cubby niche
    static let niche     = Color(hex: 0xfdeef5)
    static let nicheDk   = Color(hex: 0xf6dfeb)
    static let nicheBd   = Color(hex: 0xe2b8ce)

    // hot-pink action
    static let wine      = Color(hex: 0xd94f92)
    static let wineHi    = Color(hex: 0xe86aa6)
    static let wineDk    = Color(hex: 0x9c2f66)

    // brass (pink + gold reads coquette)
    static let brass     = Color(hex: 0xdca63f)
    static let brassHi   = Color(hex: 0xf3d385)
    static let brassDk   = Color(hex: 0xa9772a)
    static let brassInk  = Color(hex: 0x4a2a10)

    // brass nameplate
    static let plateHi   = Color(hex: 0xf2cf79)
    static let plateLo   = Color(hex: 0xd6a743)

    // mauve cork (refresh / close)
    static let cork      = Color(hex: 0xb87a99)
    static let corkDk    = Color(hex: 0x8a5273)
    static let corkEdge  = Color(hex: 0x5f3450)

    // near-white pink bottle-label
    static let label     = Color(hex: 0xfdf3f8)
    static let labelEdge = Color(hex: 0xecccdd)

    // wax seal (brand mark + label accent)
    static let seal      = Color(hex: 0xe86aa6)
    static let sealDk    = Color(hex: 0xb23f70)
    static let sealBd    = Color(hex: 0x8a2f5c)
    static let sealInk   = Color(hex: 0xfff0f6)

    // misc
    static let brand     = Color(hex: 0xb23472)  // DECANT wordmark
    static let pip       = Color(hex: 0x5aa55f)  // engine-ready dot (green = go)
    static let emptyBd   = Color(hex: 0xd9a8c2)
    static let ledgerHi  = Color(hex: 0xf6e0ec)
    static let ledgerLo  = Color(hex: 0xecccdd)

    // bevel tones (fill-agnostic, so one pair works on any panel)
    static let bevelHi   = Color.white.opacity(0.6)
    static let bevelLo   = Color(hex: 0x5a2440).opacity(0.45)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// bundled Pixelify Sans, registered at launch in DecantApp.swift. falls
// back to the system font automatically if registration ever fails, since
// SwiftUI treats an unresolvable custom font name as "use default."
enum PixelFont {
    static func bold(_ size: CGFloat) -> Font { .custom("PixelifySans-Bold", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PixelifySans-Medium", size: size) }
    static func regular(_ size: CGFloat) -> Font { .custom("PixelifySans-Regular", size: size) }
}

// the signature retro-game border: a chunky two-tone pixel bevel with hard
// square corners. a raised panel is lit top-left and shadowed bottom-right;
// a sunken one (recessed niches, covers, the rack interior) inverts it. the
// four edges are drawn as overlay bars rather than a per-side border, which
// swiftui has no native form of.
struct Bevel: ViewModifier {
    var raised: Bool = true
    var width: CGFloat = 3
    var hi: Color = Palette.bevelHi
    var lo: Color = Palette.bevelLo

    func body(content: Content) -> some View {
        let top = raised ? hi : lo
        let leading = raised ? hi : lo
        let bottom = raised ? lo : hi
        let trailing = raised ? lo : hi
        return content
            .overlay(alignment: .top)      { Rectangle().fill(top).frame(height: width) }
            .overlay(alignment: .bottom)   { Rectangle().fill(bottom).frame(height: width) }
            .overlay(alignment: .leading)  { Rectangle().fill(leading).frame(width: width) }
            .overlay(alignment: .trailing) { Rectangle().fill(trailing).frame(width: width) }
    }
}

extension View {
    func bevel(raised: Bool = true, width: CGFloat = 3, hi: Color = Palette.bevelHi, lo: Color = Palette.bevelLo) -> some View {
        modifier(Bevel(raised: raised, width: width, hi: hi, lo: lo))
    }
}

// a chunky beveled pixel button: raised at rest, pressed-in (sunken bevel +
// downward nudge) while held. pass the two-stop fill and text color; the
// bevel tones are shared so every button reads as the same material.
struct PixelButton: View {
    let label: String
    var top: Color = Palette.cork
    var bottom: Color = Palette.corkDk
    var text: Color = Palette.cream
    var fill: Bool = false           // stretch to full width
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(label) }
            .buttonStyle(BevelButtonStyle(top: top, bottom: bottom, text: text, fill: fill))
    }
}

struct BevelButtonStyle: ButtonStyle {
    var top: Color
    var bottom: Color
    var text: Color
    var fill: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelFont.medium(14))
            .foregroundColor(text)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            )
            .bevel(raised: !configuration.isPressed)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// the wax-seal brand mark. a placeholder for Sophia's own decant graphic:
// swap the inner monogram for an Image when the asset lands.
struct BrandSeal: View {
    var size: CGFloat = 42

    var body: some View {
        Text("D")
            .font(PixelFont.bold(size * 0.5))
            .foregroundColor(Palette.sealInk)
            .frame(width: size, height: size)
            .background(
                RadialGradient(colors: [Palette.seal, Palette.sealDk],
                               center: UnitPoint(x: 0.38, y: 0.32),
                               startRadius: 0, endRadius: size * 0.8)
            )
            .bevel(width: 3)
    }
}

// the engraved brass nameplate under each game (and the vintage/apple-silicon
// tag): a raised brass pixel plate with dark, letter-pressed text.
struct BrassPlate: View {
    let text: String
    var starting: Bool = false

    var body: some View {
        Text(text)
            .font(PixelFont.medium(13))
            .foregroundColor(starting ? Palette.cream : Palette.brassInk)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: starting ? [Palette.wineHi, Palette.wine]
                                                 : [Palette.plateHi, Palette.plateLo],
                               startPoint: .top, endPoint: .bottom)
            )
            .bevel(width: 2)
    }
}
