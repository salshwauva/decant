import SwiftUI

// the coquette potion-shop palette: soft pink fields, dark maroon plaques
// and item slots, an ornate gold frame, and vivid magenta heart accents.
// reskinned from a pixel-art rpg inventory screen reference.
enum Palette {
    // backgrounds
    static let bgOuter     = Color(hex: 0xe98fb8)
    static let bgOuterDeep = Color(hex: 0xd9689e)  // gradient edge, for depth instead of a flat fill
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
    static let goldBright  = Color(hex: 0xf3cf85)  // hover glow / shimmer highlight

    // text
    static let ink         = Color(hex: 0x3a2233)
    static let inkSoft     = Color(hex: 0x8a5570)
    static let textCream   = Color(hex: 0xfaf0e6)

    // hearts, sparkles, badges
    static let heart       = Color(hex: 0xd6236f)
    static let heartDk     = Color(hex: 0x9c1a52)
    static let heartSoft   = Color(hex: 0xe888b4)

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

// bundled Pixelify Sans, registered at launch in MeadApp.swift. falls back
// to the system rounded font automatically if registration ever fails,
// since SwiftUI treats an unresolvable custom font name as "use default."
enum PixelFont {
    static func bold(_ size: CGFloat) -> Font { .custom("PixelifySans-Bold", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PixelifySans-Medium", size: size) }
    static func regular(_ size: CGFloat) -> Font { .custom("PixelifySans-Regular", size: size) }
}

// a soft, gently animated field of hearts and sparkles behind the main
// content, echoing the reference's abundant floating accents rather than
// four static corner glyphs. every glyph bobs and twinkles on its own
// offset timer so the motion reads as alive, not a single synced pulse.
private struct FloatAccent: Identifiable {
    let id = Int.random(in: Int.min...Int.max)
    let glyph: String
    let x: CGFloat      // 0...1, relative to the container
    let y: CGFloat      // 0...1
    let size: CGFloat
    let color: Color
    let delay: Double
    let duration: Double
}

private let floatAccents: [FloatAccent] = [
    FloatAccent(glyph: "♥", x: 0.05, y: 0.08, size: 20, color: Palette.heart, delay: 0.0, duration: 2.6),
    FloatAccent(glyph: "♥", x: 0.95, y: 0.10, size: 15, color: Palette.heartSoft, delay: 0.5, duration: 3.0),
    FloatAccent(glyph: "✦", x: 0.09, y: 0.30, size: 13, color: Palette.gold, delay: 0.9, duration: 2.2),
    FloatAccent(glyph: "✦", x: 0.92, y: 0.34, size: 16, color: Palette.goldBright, delay: 0.2, duration: 2.8),
    FloatAccent(glyph: "♥", x: 0.03, y: 0.58, size: 12, color: Palette.heartSoft, delay: 1.1, duration: 2.4),
    FloatAccent(glyph: "♥", x: 0.96, y: 0.62, size: 22, color: Palette.heart, delay: 0.6, duration: 3.2),
    FloatAccent(glyph: "✦", x: 0.50, y: 0.04, size: 12, color: Palette.gold, delay: 1.3, duration: 2.0),
    FloatAccent(glyph: "♥", x: 0.07, y: 0.85, size: 16, color: Palette.heart, delay: 0.3, duration: 2.9),
    FloatAccent(glyph: "✦", x: 0.94, y: 0.88, size: 14, color: Palette.goldBright, delay: 0.8, duration: 2.5),
]

struct FloatingAccents: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(floatAccents) { a in
                    Text(a.glyph)
                        .font(.system(size: a.size))
                        .foregroundColor(a.color)
                        .shadow(color: a.color.opacity(0.5), radius: 3)
                        .position(x: geo.size.width * a.x, y: geo.size.height * a.y)
                        .offset(y: animate ? -7 : 7)
                        .opacity(animate ? 0.95 : 0.45)
                        .animation(
                            Animation.easeInOut(duration: a.duration)
                                .repeatForever(autoreverses: true)
                                .delay(a.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}

// the ornate double-line gold frame used around the whole window and major
// panels: a dark outer line, a bright inner line, and a small heart +
// sparkle cluster at each corner (rather than a lone glyph), plus a soft
// drop shadow so the whole thing reads as a raised, physical object.
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
            .overlay(alignment: .topLeading) { if heartCorners { cornerCluster(sparkleX: 1, sparkleY: -1) } }
            .overlay(alignment: .topTrailing) { if heartCorners { cornerCluster(sparkleX: -1, sparkleY: -1) } }
            .overlay(alignment: .bottomTrailing) { if heartCorners { cornerCluster(sparkleX: -1, sparkleY: 1) } }
            .overlay(alignment: .bottomLeading) { if heartCorners { cornerCluster(sparkleX: 1, sparkleY: 1) } }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: Palette.plaqueDk.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    // a heart with a small sparkle tucked toward the outside of the
    // corner, so all four clusters point outward rather than being
    // identical stamps.
    private func cornerCluster(sparkleX: CGFloat, sparkleY: CGFloat) -> some View {
        ZStack {
            Text("♥")
                .font(.system(size: 13))
                .foregroundColor(Palette.heart)
            Text("✦")
                .font(.system(size: 8))
                .foregroundColor(Palette.goldBright)
                .offset(x: 9 * sparkleX, y: 9 * sparkleY)
        }
        .padding(8)
    }
}

extension View {
    func ornateFrame(corner: CGFloat = 18, heartCorners: Bool = true) -> some View {
        modifier(OrnateFrame(corner: corner, heartCorners: heartCorners))
    }
}

// a dark maroon plaque with a gold border and a soft drop shadow: the
// swiftui cousin of the reference's "INVENTORY" title banner and
// description box.
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
            .shadow(color: Palette.plaqueDk.opacity(0.4), radius: 5, x: 0, y: 3)
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
                    .font(PixelFont.bold(17))
                    .tracking(1)
                    .foregroundColor(Palette.textCream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            content()
                .background(
                    LinearGradient(colors: [Palette.bgPanel, Palette.bgPanelDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.goldDk, lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Palette.plaqueDk.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

// a chunky, two-tone pixel button with a genuine pressed/hover state (not
// just a static color swap): it scales down and drops its shadow when
// pressed, and glows on hover. pass matching `tint`/`tintDown` pairs (see
// the *Dk palette entries) for the 3d look; a flat color works too if you
// only pass `tint`.
struct CozyButton: View {
    let label: String
    var tint: Color = Palette.neutral
    var tintDown: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(PixelButtonStyle(tint: tint, tintDown: tintDown ?? tint))
        .scaleEffect(hovering ? 1.035 : 1.0)
        .shadow(color: Palette.goldBright.opacity(hovering ? 0.6 : 0), radius: hovering ? 7 : 0)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct PixelButtonStyle: ButtonStyle {
    var tint: Color
    var tintDown: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelFont.medium(14))
            .foregroundColor(Palette.textCream)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [tint, tintDown], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.plaqueDk, lineWidth: 2))
            .shadow(color: Palette.plaqueDk.opacity(0.45),
                    radius: 0, x: 0, y: configuration.isPressed ? 0 : 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
