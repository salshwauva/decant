import SwiftUI

// the "how to install games" page, reached from the toolbar button. plain,
// friendly steps for getting a windows game onto the shelf.
struct InstallInstructionsView: View {
    var onOpenSteam: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "open steam",
         "hit \u{201c}open steam\u{201d}. a windows steam window opens inside mead. the first time, sign in with your steam account (it remembers you after)."),
        ("2", "find your game",
         "in steam, go to your library and pick a windows game you own. cozy single-player games work great."),
        ("3", "install it",
         "click install and let it download. it lands in mead's bottle, fully separate from your mac steam."),
        ("4", "refresh the shelf",
         "come back to mead and hit \u{201c}refresh\u{201d}. the game appears on your shelf."),
        ("5", "play",
         "tap a game's slot, then hit play. mead launches it through wine 11 + dxmt, straight to metal on your mac."),
    ]

    var body: some View {
        ZStack {
            Palette.bgOuter.ignoresSafeArea()

            VStack(spacing: 12) {
                Plaque {
                    HStack {
                        Text("\u{2661} how to install games")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(Palette.textCream)
                        Spacer()
                        CozyButton(label: "done", tint: Palette.neutral, tintDown: Palette.neutralDk) { dismiss() }
                            .fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(steps, id: \.0) { step in
                            stepCard(number: step.0, title: step.1, body: step.2)
                        }
                        noteCard
                    }
                    .padding(.vertical, 4)
                }

                CozyButton(label: "\u{25b6}  open steam now", tint: Palette.playGreen, tintDown: Palette.playGreenDk) {
                    onOpenSteam()
                    dismiss()
                }
            }
            .padding(18)
            .frame(minWidth: 460, minHeight: 520)
        }
        .ornateFrame(corner: 18, heartCorners: true)
    }

    private func stepCard(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textCream)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.heart))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.ink)
                Text(body)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.gold, lineWidth: 2))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("good to know")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textCream)
            Text("single-player and many online games run well. games with kernel-level anti-cheat (a lot of competitive multiplayer) don't run on macos in any wrapper, that's a mac limitation, not mead's.")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Palette.textCream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Palette.plaque, Palette.plaqueDk], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.gold, lineWidth: 2))
    }
}
