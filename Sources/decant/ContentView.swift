import SwiftUI

struct ContentView: View {
    @State private var status: EngineStatus = .noEngine
    @State private var games: [Game] = []
    @State private var showingInstructions = false
    @State private var launching: String? = nil
    @State private var selectedGame: Game? = nil

    private var bottle: URL { EnginePaths.bottle(EngineManager.defaultBottle) }

    // measured natural height of the game grid, so the library can size to
    // its contents (few games -> short rack) up to a cap, past which it
    // scrolls instead of growing further.
    @State private var libraryHeight: CGFloat = 0

    // a fixed four-wide grid of fixed-width niches: deterministic width (so
    // the window doesn't reflow) and deterministic rows (so height tracks
    // the game count). spacing widened for more air between games.
    private let columnCount = 4
    private let cellWidth: CGFloat = 168
    private let gridSpacing: CGFloat = 22
    // ~3 rows before the library starts scrolling.
    private let libraryCap: CGFloat = 484

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: gridSpacing), count: columnCount)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgHi, Palette.bg, Palette.bgDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                toolbar
                rack
                installHelp
                ledger
            }
            .padding(16)
        }
        .bevel(width: 3)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showingInstructions) {
            InstallInstructionsView(onOpenSteam: openSteam)
        }
        .sheet(item: $selectedGame) { game in
            GameDetailView(
                game: game,
                isLaunching: launching == game.appID,
                onPlay: { play(game) },
                onClose: { selectedGame = nil },
                onUninstall: { uninstall(game) }
            )
        }
    }

    private var engineReady: Bool {
        if case .noEngine = status { return false }
        return true
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            BrandLogo(size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("DECANT")
                    .font(PixelFont.bold(31))
                    .tracking(4)
                    .foregroundColor(Palette.brand)
                    .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
                Text("WINDOWS GAMES ON APPLE SILICON")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Palette.inkMut)
            }
            Spacer()
            Text("apple silicon")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.brassInk)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(LinearGradient(colors: [Palette.brassHi, Palette.brass], startPoint: .top, endPoint: .bottom))
                .bevel(width: 2)
        }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // adding a game means installing it in steam, so this opens the
            // steam client where the library and store live.
            PixelButton(label: "＋  add a game", top: Palette.wineHi, bottom: Palette.wine, text: Palette.cream, action: openSteam)
            Spacer()
            PixelButton(label: "⟳  refresh", top: Palette.cork, bottom: Palette.corkDk, text: Palette.cream, action: refresh)
        }
    }

    // the help link, sitting below the cellar rather than in the top toolbar.
    private var installHelp: some View {
        HStack {
            PixelButton(label: "?  how to install games", top: Palette.cork, bottom: Palette.corkDk, text: Palette.cream) {
                showingInstructions = true
            }
            Spacer()
        }
    }

    // MARK: the rack

    private var rack: some View {
        VStack(spacing: 12) {
            rackHead
            if games.isEmpty {
                emptyShelf
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                        ForEach(games) { game in
                            ItemSlot(game: game, isLaunching: launching == game.appID) {
                                selectedGame = game
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: LibraryHeightKey.self, value: g.size.height)
                    })
                }
                .frame(height: min(libraryHeight, libraryCap))
                .onPreferenceChange(LibraryHeightKey.self) { libraryHeight = $0 }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.32))
        .bevel(raised: false, width: 3)
    }

    private var rackHead: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.nicheBd).frame(height: 2)
            Text("YOUR  GAMES")
                .font(PixelFont.medium(14))
                .tracking(4)
                .foregroundColor(Palette.inkDim)
                .fixedSize()
            Rectangle().fill(Palette.nicheBd).frame(height: 2)
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Text("no games yet")
                .font(PixelFont.bold(20))
                .foregroundColor(Palette.ink)
            Text("hit \u{201c}add a game\u{201d}, install a windows game in steam,\nthen refresh. it shows up here.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.inkMut)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: ledger status

    private var ledger: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(engineReady ? Palette.pip : Palette.wine)
                .frame(width: 9, height: 9)
                .shadow(color: (engineReady ? Palette.pip : Palette.wine).opacity(0.7), radius: 4)
            Text(engineReady ? "engine: ready · wine 11 + dxmt" : status.headline)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.inkDim)
            Spacer()
            Text("\(games.count) game\(games.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.inkMut)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Palette.ledgerHi, Palette.ledgerLo], startPoint: .top, endPoint: .bottom)
        )
        .bevel(raised: false, width: 2)
    }

    // MARK: actions

    private func refresh() {
        status = EngineManager.status()
        games = SteamManager.installedGames(bottle)
        // steam-under-wine drops a fresh, genericly-iconed shortcut on the
        // real desktop for any newly installed game, so this re-applies
        // the official steam icon and clean name every refresh.
        DesktopShortcuts.retheme(games, bottle: bottle)
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

    private func uninstall(_ game: Game) {
        guard let engine = Engine.detect() else { return }
        try? SteamManager.uninstallGame(appID: game.appID, bottle: bottle, engine: engine)
        selectedGame = nil
    }
}

// MARK: - Item slot (a filled niche: a game you own)

private struct ItemSlot: View {
    let game: Game
    let isLaunching: Bool
    let onTap: () -> Void
    @State private var hovering = false

    private var initial: String {
        String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    private var coverURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Palette.wine, Palette.wineDk],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initial)
                .font(PixelFont.bold(32))
                .foregroundColor(Palette.cream)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                AsyncImage(url: coverURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipped()
                .bevel(raised: false, width: 2)
                .opacity(isLaunching ? 0.5 : 1)

                BrassPlate(text: isLaunching ? "starting…" : game.name, starting: isLaunching)
            }
            .padding(9)
            .background(LinearGradient(colors: [Palette.niche, Palette.nicheDk], startPoint: .top, endPoint: .bottom))
            .bevel(width: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !isLaunching ? 1.035 : 1.0)
        .shadow(color: Palette.brass.opacity(hovering && !isLaunching ? 0.6 : 0),
                radius: hovering ? 10 : 0)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .disabled(isLaunching)
    }
}

// carries the game grid's natural height up so the library can size to its
// contents (and cap into a scroll past a threshold).
private struct LibraryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
