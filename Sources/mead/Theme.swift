import SwiftUI

// the coquette potion-shop palette: soft pink fields, dark maroon plaques
// and item slots, an ornate gold frame, and vivid magenta heart accents.
// reskinned from a pixel-art rpg inventory screen reference.
enum Palette {
    // backgrounds
    static let bgOuter     = Color(hex: 0xe98fb8)
    static let bgPanel     = Color(hex: 0xf6cde0)
    static let bgPanelDeep = Color(hex: 0xefb8d2)

    // plaques: dark banners and description boxes
    static let plaque      = Color(hex: 0x3a2233)
    static let plaqueDk    = Color(hex: 0x241420)

    // item slots
    static let slot        = Color(hex: 0x4c2c40)
    static let slotDk      = Color(hex: 0x351f2e)
    static let slotEmpty   = Color(hex: 0xe3a8c2)  // an open, unfilled slot: solid, not a murky blend

    // the ornate gold frame and accents
    static let gold        = Color(hex: 0xdba646)
    static let goldDk      = Color(hex: 0xa9722c)

    // text
    static let ink         = Color(hex: 0x3a2233)
    static let inkSoft     = Color(hex: 0x8a5570)
    static let textCream   = Color(hex: 0xfaf0e6)

    // hearts, sparkles, badges
    static let heart       = Color(hex: 0xd6236f)
    static let heartDk     = Color(hex: 0x9c1a52)

    // buttons
    static let playGreen   = Color(hex: 0x4ea35c)
    static let playGreenDk = Color(hex: 0x357a41)
    static let closeRed    = Color(hex: 0xc85062)
    static let closeRedDk  = Color(hex: 0x8f2f3d)
    static let neutral     = Color(hex: 0xf0b9d4)
    static let neutralDk   = Color(hex: 0xb97e9c)
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

// the ornate double-line gold frame used around the whole window and major
// panels, echoing the reference's scrollwork border: a dark outer line, a
// bright inner line, and a small heart medallion at each corner.
struct OrnateFrame: ViewModifier {
    var corner: CGFloat = 18
    var heartCorners: Bool = true

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(Palette.goldDk, lineWidth: 6))
            .overlay(
                RoundedRectangle(cornerRadius: max(corner - 3, 0))
                    .inset(by: 3)
                    .stroke(Palette.gold, lineWidth: 2)
            )
            .overlay(alignment: .topLeading) { if heartCorners { cornerHeart } }
            .overlay(alignment: .topTrailing) { if heartCorners { cornerHeart } }
            .overlay(alignment: .bottomLeading) { if heartCorners { cornerHeart } }
            .overlay(alignment: .bottomTrailing) { if heartCorners { cornerHeart } }
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private var cornerHeart: some View {
        Text("♥")
            .font(.system(size: 12))
            .foregroundColor(Palette.heart)
            .padding(7)
    }
}

extension View {
    func ornateFrame(corner: CGFloat = 18, heartCorners: Bool = true) -> some View {
        modifier(OrnateFrame(corner: corner, heartCorners: heartCorners))
    }
}

// a dark maroon plaque with a gold border: the swiftui cousin of the
// reference's "INVENTORY" title banner and description box.
struct Plaque<Content: View>: View {
    var cornerRadius: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                LinearGradient(colors: [Palette.plaque, Palette.plaqueDk],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Palette.gold, lineWidth: 2.5))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// the game shelf's outer frame: a plaque title banner over a pink content
// panel, all inside one rounded, gold-edged boundary.
struct CozyPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Plaque(cornerRadius: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(Palette.textCream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            content()
                .background(Palette.bgPanel)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.goldDk, lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// a chunky, two-tone pixel button: a light top edge fading to a darker
// bottom edge with a dark outline, matching the reference's USE/CLOSE
// button style. pass matching `tint`/`tintDown` pairs (see the *Dk palette
// entries) for a proper 3d look; a flat color works too if you only pass
// `tint`.
struct CozyButton: View {
    let label: String
    var tint: Color = Palette.neutral
    var tintDown: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textCream)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [tint, tintDown ?? tint],
                                   startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.plaqueDk, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}
