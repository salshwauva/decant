import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            // warm cream wash behind everything
            LinearGradient(
                colors: [Color(hex: 0xfff4dd), Palette.cream, Palette.cream2],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                CozyPanel(title: "✿  your shelf") {
                    emptyShelf
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("✿ hearth")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0xfff6e6))
                    .shadow(color: Palette.woodDk.opacity(0.6), radius: 0, y: 2)
                Text("a cozy home for your windows games")
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(hex: 0xffe9c8))
            }
            Spacer()
            Text("apple silicon")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.ink)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Palette.gold)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Palette.wood, Palette.woodDk],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.woodDk, lineWidth: 3))
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("🪴")
                .font(.system(size: 52))
            Text("the shelf is empty for now")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.ink)
            Text("once the engine is set up, your windows games\nwill gather here, ready to plant and play.")
                .multilineTextAlignment(.center)
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(Palette.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.coral).frame(width: 10, height: 10)
            Text("engine: not set up yet")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Palette.ink)
            Spacer()
            Text("phase 0 · cozy shell")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.inkSoft)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Palette.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 3))
    }
}
