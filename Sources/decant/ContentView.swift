import SwiftUI
import AppKit

struct ContentView: View {
    @State private var status: EngineStatus = .noEngine
    @State private var games: [Game] = []
    @State private var showingInstructions = false
    @State private var launching: String? = nil
    @State private var selectedGame: Game? = nil
    // user-visible feedback: errors (red) and soft notes (dump trim, etc.)
    @State private var banner: String? = nil
    @State private var bannerIsError = true
    @State private var dumpSummary: String? = nil

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
    private let gridSpacing: CGFloat = 64
    // ~3 rows before the library starts scrolling.
    private let libraryCap: CGFloat = 560

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
                if let banner {
                    bannerBar(banner, error: bannerIsError)
                }
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

    // green only when wine + bottle are both present.
    private var engineFullyReady: Bool { status.isFullyReady }

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
            HStack(spacing: 5) {
                Text("♥").foregroundColor(Palette.cream.opacity(0.85))
                Text("\(games.count) game\(games.count == 1 ? "" : "s")")
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Palette.cream)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(LinearGradient(colors: [Palette.wineHi, Palette.wine], startPoint: .top, endPoint: .bottom))
            .clipShape(Capsule())
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
                        AddGameTile(action: openSteam)
                    }
                    .padding(.vertical, 4)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: LibraryHeightKey.self, value: g.size.height)
                    })
                }
                .frame(height: min(libraryHeight, libraryCap))
                .background(cellarBackdrop)
                .clipShape(Rectangle())    // keep the fill image inside the games area
                .onPreferenceChange(LibraryHeightKey.self) { libraryHeight = $0 }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.30))
        .bevel(raised: false, width: 3)
    }

    // a faint pixel wine-cellar, drawn only behind the game tiles so it reads
    // as texture there without touching the section header or the frame.
    @ViewBuilder private var cellarBackdrop: some View {
        if let bg = Assets.cellarBG {
            Image(nsImage: bg)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fill)
                .opacity(0.22)
        }
    }

    private var rackHead: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.nicheBd).frame(height: 2)
            HStack(spacing: 7) {
                Text("✦").foregroundColor(Palette.brass)
                Text("♥").foregroundColor(Palette.seal)
                Text("YOUR  GAMES")
                    .font(PixelFont.medium(14))
                    .tracking(4)
                    .foregroundColor(Palette.inkDim)
                Text("♥").foregroundColor(Palette.seal)
                Text("✦").foregroundColor(Palette.brass)
            }
            .font(.system(size: 13))
            .fixedSize()
            Rectangle().fill(Palette.nicheBd).frame(height: 2)
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Text("no games yet")
                .font(PixelFont.bold(20))
                .foregroundColor(Palette.ink)
            Text(emptyShelfHint)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.inkMut)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyShelfHint: String {
        switch status {
        case .noEngine:
            return "engine not installed yet.\nfrom the monorepo:  bash engine/install.sh"
        case .engineNoBottle:
            return "engine is in, but there is no bottle yet.\nrun:  decant --init-bottle  then  decant --install-steam"
        case .ready:
            return "hit \u{201c}add a game\u{201d}, install a windows game in steam,\nthen refresh. it shows up here."
        }
    }

    // MARK: ledger status

    private var ledger: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(engineFullyReady ? Palette.pip : Palette.wine)
                .frame(width: 9, height: 9)
                .shadow(color: (engineFullyReady ? Palette.pip : Palette.wine).opacity(0.7), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.headline)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.inkDim)
                if let dumpSummary {
                    Text(dumpSummary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Palette.inkMut)
                }
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(DecantLog.fileURL)
            } label: {
                Text("log")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Palette.inkMut)
                    .underline()
            }
            .buttonStyle(.plain)
            .help(DecantLog.fileURL.path)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Palette.ledgerHi, Palette.ledgerLo], startPoint: .top, endPoint: .bottom)
        )
        .bevel(raised: false, width: 2)
    }

    private func bannerBar(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(error ? "!" : "i")
                .font(PixelFont.bold(14))
                .foregroundColor(error ? Palette.cream : Palette.ink)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(error ? Palette.cream : Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                banner = nil
            } label: {
                Text("✕")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(error ? Palette.cream.opacity(0.8) : Palette.inkMut)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: error ? [Palette.wineHi, Palette.wine] : [Palette.cork, Palette.corkDk],
                startPoint: .top, endPoint: .bottom)
        )
        .bevel(width: 2)
    }

    // MARK: actions

    private func refresh() {
        status = EngineManager.status()
        games = SteamManager.installedGames(bottle)
        if case .ready(_, let b) = status {
            let report = Housekeeping.evaluateDumps(b)
            dumpSummary = report.summary
        } else {
            dumpSummary = nil
        }
        // steam-under-wine drops a fresh, genericly-iconed shortcut on the
        // real desktop for any newly installed game, so this re-applies
        // the official steam icon and clean name every refresh.
        DesktopShortcuts.retheme(games, bottle: bottle)
    }

    private func showError(_ error: Error) {
        bannerIsError = true
        banner = String(describing: error)
        DecantLog.line("ui error: \(error)")
    }

    private func showNote(_ text: String) {
        bannerIsError = false
        banner = text
    }

    private func openSteam() {
        do {
            let (engine, b) = try EngineManager.requireReady()
            let note = try SteamManager.launchClient(b, engine: engine)
            if let note { showNote(note) } else { banner = nil }
        } catch {
            showError(error)
        }
    }

    private func play(_ game: Game) {
        do {
            let (engine, b) = try EngineManager.requireReady()
            launching = game.appID
            let note = try SteamManager.launchGame(appID: game.appID, bottle: b, engine: engine)
            if let note { showNote(note) } else { banner = nil }
            // clear the launching pip after a moment (the game spins up detached)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if launching == game.appID { launching = nil }
            }
        } catch {
            launching = nil
            showError(error)
        }
    }

    private func uninstall(_ game: Game) {
        do {
            let (engine, b) = try EngineManager.requireReady()
            try SteamManager.uninstallGame(appID: game.appID, bottle: b, engine: engine)
            selectedGame = nil
            banner = nil
        } catch {
            showError(error)
        }
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
                ZStack {
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
                    .brightness(hovering && !isLaunching ? -0.3 : 0)
                    .opacity(isLaunching ? 0.5 : 1)

                    // hovering a game reads as click-to-play: dim the cover and
                    // surface a play chip.
                    if hovering && !isLaunching {
                        Text("▶ play")
                            .font(PixelFont.medium(13))
                            .foregroundColor(Palette.cream)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(LinearGradient(colors: [Palette.wineHi, Palette.wine], startPoint: .top, endPoint: .bottom))
                            .bevel(width: 2)
                    }
                }
                .frame(height: 90)
                .bevel(raised: false, width: 2)

                BrassPlate(text: isLaunching ? "starting…" : game.name, starting: isLaunching)
            }
            .padding(9)
            .background(LinearGradient(colors: [Palette.niche, Palette.nicheDk], startPoint: .top, endPoint: .bottom))
            .bevel(width: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !isLaunching ? 1.035 : 1.0)
        .shadow(color: Palette.wine.opacity(hovering && !isLaunching ? 0.5 : 0),
                radius: hovering ? 10 : 0)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .disabled(isLaunching)
    }
}

// MARK: - Add-a-game tile (an in-grid affordance at the end of the shelf)

private struct AddGameTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("＋").font(.system(size: 30))
                Text("add a game").font(.system(size: 11, design: .monospaced)).tracking(1)
            }
            .foregroundColor(hovering ? Palette.wineDk : Palette.brassDk)
            .frame(maxWidth: .infinity)
            .frame(height: 144)
            .background((hovering ? Palette.wine : Palette.brass).opacity(0.14))
            .overlay(
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    .foregroundColor(hovering ? Palette.wine : Palette.brassDk)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
