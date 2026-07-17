import SwiftUI

// the "how to install games" page, reached from the toolbar. plain, friendly
// steps for getting a windows game onto the shelf.
struct InstallInstructionsView: View {
    var onOpenSteam: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingEngineSetup = false

    private let steps: [(String, String, String)] = [
        ("1", "open steam",
         "hit \u{201c}open steam\u{201d}. a windows steam window opens inside decant. the first time, sign in with your steam account (it remembers you after)."),
        ("2", "find your game",
         "in steam, go to your library and pick a windows game you own. cozy single-player games work great."),
        ("3", "install it",
         "click install and let it download. it lands in decant's own space, separate from your mac steam."),
        ("4", "refresh the shelf",
         "come back to decant and hit \u{201c}refresh\u{201d}. the game appears on your shelf."),
        ("5", "play",
         "click a game, then hit play. decant launches it through wine 11 + dxmt, straight to metal on your mac."),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgHi, Palette.bg, Palette.bgDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Text("how to install games")
                        .font(PixelFont.bold(20))
                        .foregroundColor(Palette.brand)
                    Spacer()
                    PixelButton(label: "done", top: Palette.cork, bottom: Palette.corkDk, text: Palette.cream) { dismiss() }
                }

                ScrollView {
                    VStack(spacing: 12) {
                        engineLink
                        ForEach(steps, id: \.0) { step in
                            stepCard(number: step.0, title: step.1, body: step.2)
                        }
                        noteCard
                    }
                    .padding(2)
                }

                PixelButton(label: "▶  open steam now", top: Palette.wineHi, bottom: Palette.wine, text: Palette.cream, fill: true) {
                    onOpenSteam()
                    dismiss()
                }
            }
            .padding(18)
            .frame(minWidth: 460, minHeight: 520)
        }
        .bevel(width: 3)
        .sheet(isPresented: $showingEngineSetup) { EngineSetupView() }
    }

    // links out to the separate one-time engine setup. these game steps
    // assume the wine engine is already up; if it isn't, start here.
    private var engineLink: some View {
        Button { showingEngineSetup = true } label: {
            HStack(spacing: 10) {
                Text("first time on this machine?")
                    .font(PixelFont.medium(14))
                    .foregroundColor(Palette.cream)
                Spacer(minLength: 6)
                Text("set up the engine  →")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Palette.cream)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.cork, Palette.corkDk], startPoint: .top, endPoint: .bottom))
            .bevel(width: 2)
        }
        .buttonStyle(.plain)
    }

    private func stepCard(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(PixelFont.bold(20))
                .foregroundColor(Palette.cream)
                .frame(width: 38, height: 38)
                .background(LinearGradient(colors: [Palette.wineHi, Palette.wine], startPoint: .top, endPoint: .bottom))
                .bevel(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PixelFont.medium(16))
                    .foregroundColor(Palette.ink)
                Text(body)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LinearGradient(colors: [Palette.cream, Palette.label], startPoint: .top, endPoint: .bottom))
        .bevel(width: 2)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("good to know")
                .font(PixelFont.bold(15))
                .foregroundColor(Palette.cream)
            Text("single-player and many online games run well. games with kernel-level anti-cheat (a lot of competitive multiplayer) don't run on macos in any wrapper, that's a mac limitation, not decant's.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.cream.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Palette.wood, Palette.woodDk], startPoint: .top, endPoint: .bottom))
        .bevel(raised: false, width: 2)
    }
}
