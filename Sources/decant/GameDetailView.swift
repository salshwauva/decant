import SwiftUI

// the game detail sheet: a large cover over a cream bottle-label (wax-seal
// accent, title, steam id, ready line) and a PLAY / CLOSE pair. mirrors the
// reference inventory screen's item popup, mapped onto what it's for here:
// launch the game, or back out.
struct GameDetailView: View {
    let game: Game
    let isLaunching: Bool
    let onPlay: () -> Void
    let onClose: () -> Void
    var onUninstall: () -> Void = {}

    private var coverURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgHi, Palette.bg, Palette.bgDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                hero
                label
                HStack(spacing: 12) {
                    PixelButton(label: isLaunching ? "pouring…" : "▶  PLAY",
                                top: Palette.wineHi, bottom: Palette.wine, text: Palette.cream, fill: true,
                                action: onPlay)
                        .disabled(isLaunching)
                    PixelButton(label: "✕  CLOSE",
                                top: Palette.cork, bottom: Palette.corkDk, text: Palette.cream, fill: true,
                                action: onClose)
                }
                // quiet, secondary: hands off to steam's own uninstall dialog.
                Button(action: onUninstall) {
                    Text("uninstall from steam")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.inkMut)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(isLaunching)
            }
            .padding(20)
        }
        .bevel(width: 3)
        .frame(width: 420, height: 486)
    }

    @ViewBuilder private var hero: some View {
        if isLaunching {
            // the game is pouring — literally. the pour animation stands in
            // for the cover while it spins up.
            ZStack {
                LinearGradient(colors: [Palette.niche, Palette.nicheDk], startPoint: .top, endPoint: .bottom)
                PourAnimation()
                    .frame(height: 170)
                    .padding(.top, 6)
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .bevel(raised: false, width: 3)
        } else {
            AsyncImage(url: coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [Palette.wine, Palette.wineDk], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                            .font(PixelFont.bold(56))
                            .foregroundColor(Palette.cream)
                    }
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .bevel(raised: false, width: 3)
        }
    }

    private var label: some View {
        VStack(spacing: 0) {
            // wax seal straddling the top edge of the label
            Text("♥")
                .font(.system(size: 13))
                .foregroundColor(Palette.sealInk)
                .frame(width: 30, height: 30)
                .background(
                    RadialGradient(colors: [Palette.seal, Palette.sealDk],
                                   center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 24)
                )
                .bevel(width: 2)
                .offset(y: 15)
                .zIndex(1)

            VStack(spacing: 6) {
                Text(game.name)
                    .font(PixelFont.bold(22))
                    .foregroundColor(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("STEAM #\(game.appID)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Palette.inkMut)
                Divider().overlay(Palette.labelEdge).padding(.top, 5)
                Text(isLaunching ? "pouring… · wine 11 + dxmt" : "ready to play · wine 11 + dxmt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.inkDim)
                    .padding(.top, 5)
            }
            .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Palette.cream, Palette.label], startPoint: .top, endPoint: .bottom))
            .bevel(width: 2)
        }
    }
}
