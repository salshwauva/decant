import SwiftUI

// the cozy pixel palette, carried over from the wisp ui so mead feels like
// the same world: warm cream, wood, peach, sage.
enum Palette {
    static let cream    = Color(hex: 0xf6e7c8)
    static let cream2   = Color(hex: 0xefd8ad)
    static let panel    = Color(hex: 0xfcf3df)
    static let panel2   = Color(hex: 0xf6e8cb)
    static let ink      = Color(hex: 0x5b4636)
    static let inkSoft  = Color(hex: 0x9a7f63)
    static let line     = Color(hex: 0xcda468)
    static let lineDk   = Color(hex: 0xa87b46)
    static let wood     = Color(hex: 0xbb8259)
    static let woodDk   = Color(hex: 0x9c6743)
    static let peach    = Color(hex: 0xf0a285)
    static let coral    = Color(hex: 0xe07a5f)
    static let sage     = Color(hex: 0x8aa872)
    static let sageDk   = Color(hex: 0x6c8c54)
    static let gold     = Color(hex: 0xe7b65a)
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

// a chunky cozy panel, the swiftui cousin of the web ui's .panel.
struct CozyPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.line).frame(height: 2)
                }
            content()
        }
        .background(Palette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.line, lineWidth: 3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
