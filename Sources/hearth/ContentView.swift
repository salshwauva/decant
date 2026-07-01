import SwiftUI

struct ContentView: View {
    @State private var status: EngineStatus = .noEngine
    @State private var games: [Game] = []
    @State private var showingInstructions = false
    @State private var launching: String? = nil

    private var bottle: URL { EnginePaths.bottle(EngineManager.defaultBottle) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xfff4dd), Palette.cream, Palette.cream2],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                toolbar
                CozyPanel(title: "✿  your shelf") {
                    shelf
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }
            .padding(16)
        }
        .onAppear(perform: refresh)
        .sheet(isPresented: $showingInstructions) {
            InstallInstructionsView(onOpenSteam: openSteam)
        }
    }

    private var engineReady: Bool {
        if case .noEngine = status { return false }
        return true
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("✿ hearth")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0xfff6e6))
                    .shadow(color: Palette.woodDk.opacity(0.6), radius: 0, y: 2)
                Text("a cozy home for your windows games")
                    .font(.system(size: 15, design: .monospaced))
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

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            CozyButton(label: "▶  open steam", tint: Palette.sage, action: openSteam)
            CozyButton(label: "＋  how to install games", tint: Palette.gold) {
                showingInstructions = true
            }
            Spacer()
            CozyButton(label: "⟳  refresh", tint: Palette.panel2, action: refresh)
        }
    }

    // MARK: shelf

    @ViewBuilder private var shelf: some View {
        if games.isEmpty {
            emptyShelf
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(games) { game in
                        GameCard(game: game,
                                 isLaunching: launching == game.appID,
                                 onPlay: { play(game) })
                    }
                }
                .padding(14)
            }
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("🪴").font(.system(size: 52))
            Text("no games on the shelf yet")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.ink)
            Text("open steam, install a windows game, then hit refresh.\ntap \u{201c}how to install games\u{201d} for the steps.")
                .multilineTextAlignment(.center)
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(Palette.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: status bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(engineReady ? Palette.sage : Palette.coral)
                .frame(width: 10, height: 10)
            Text(engineReady ? "engine: ready · wine 11 + dxmt" : status.headline)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Palette.ink)
            Spacer()
            Text("\(games.count) game\(games.count == 1 ? "" : "s")")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.inkSoft)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Palette.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 3))
    }

    // MARK: actions

    private func refresh() {
        status = EngineManager.status()
        games = SteamManager.installedGames(bottle)
    }

    private func openSteam() {
        guard let engine = Engine.detect() else { return }
        try? SteamManager.launchClient(bottle, engine: engine)
    }

    private func play(_ game: Game) {
        guard let engine = Engine.detect() else { return }
        launching = game.appID
        try? SteamManager.launchGame(appID: game.appID, bottle: bottle, engine: engine)
        // clear the launching pip after a moment (the game spins up detached)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if launching == game.appID { launching = nil }
        }
    }
}

// MARK: - Game card

private struct GameCard: View {
    let game: Game
    let isLaunching: Bool
    let onPlay: () -> Void

    private var initial: String {
        String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    // steam's public store banner for the app (every game has one).
    private var coverURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Palette.peach, Palette.coral],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initial)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: 0xfff6e6))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            AsyncImage(url: coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1.5))

            Text(game.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            CozyButton(label: isLaunching ? "starting…" : "▶  play",
                       tint: isLaunching ? Palette.panel2 : Palette.sage,
                       action: onPlay)
                .disabled(isLaunching)
        }
        .padding(12)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 2))
    }
}

// MARK: - Cozy button

struct CozyButton: View {
    let label: String
    var tint: Color = Palette.panel2
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.lineDk, lineWidth: 2))
                .offset(y: pressed ? 2 : 0)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}
