import SwiftUI

// the game detail sheet: a close mirror of the reference inventory
// screen's item-detail popup (ornate frame, a title plaque, a large hero
// image ringed with heart/sparkle accents, a description plaque, and a
// USE/CLOSE-style button pair), mapped onto what it's logically for here:
// launch the game, or back out.
struct GameDetailView: View {
    let game: Game
    let isLaunching: Bool
    let onPlay: () -> Void
    let onClose: () -> Void

    private var coverURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
    }

    var body: some View {
        ZStack {
            Palette.bgOuter.ignoresSafeArea()

            VStack(spacing: 14) {
                Plaque {
                    Text(game.name.uppercased())
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(Palette.textCream)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }

                hero

                Plaque {
                    Text("Steam AppID \(game.appID) \u{00b7} \(isLaunching ? "launching through wine + dxmt\u{2026}" : "ready to play")")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Palette.textCream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    CozyButton(label: isLaunching ? "starting\u{2026}" : "\u{25b6}  PLAY",
                               tint: Palette.playGreen, tintDown: Palette.playGreenDk,
                               action: onPlay)
                        .disabled(isLaunching)
                    CozyButton(label: "\u{2715}  CLOSE",
                               tint: Palette.closeRed, tintDown: Palette.closeRedDk,
                               action: onClose)
                }
            }
            .padding(20)
        }
        .ornateFrame(corner: 18, heartCorners: true)
        .frame(width: 420, height: 460)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Palette.bgPanelDeep)

            AsyncImage(url: coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fit).padding(14)
                } else {
                    Text(String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(Palette.heart)
                }
            }

            // corner sparkle/heart accents, echoing the reference's
            // floating hearts and diamonds around the potion bottle.
            VStack {
                HStack {
                    Text("\u{2726}").foregroundColor(Palette.gold)
                    Spacer()
                    Text("\u{2665}").foregroundColor(Palette.heart)
                }
                Spacer()
                HStack {
                    Text("\u{2665}").foregroundColor(Palette.heart)
                    Spacer()
                    Text("\u{2726}").foregroundColor(Palette.gold)
                }
            }
            .font(.system(size: 18))
            .padding(10)
        }
        .frame(height: 200)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.gold, lineWidth: 2.5))
    }
}
