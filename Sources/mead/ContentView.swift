import SwiftUI

struct ContentView: View {
    @State private var status: EngineStatus = .noEngine
    @State private var games: [Game] = []
    @State private var showingInstructions = false
    @State private var launching: String? = nil
    @State private var selectedGame: Game? = nil

    private var bottle: URL { EnginePaths.bottle(EngineManager.defaultBottle) }

    // pad the shelf out with a few empty gold-bordered slots, the same way
    // the reference inventory screen shows open slots alongside filled
    // ones -- a visual hint that there's room for more, not just decoration
    // for its own sake. capped so a big library doesn't produce a wall of
    // empty boxes.
    private var emptySlotCount: Int {
        guard !games.isEmpty else { return 0 }
        let columns = 4
        let remainder = games.count % columns
        let fillRow = remainder == 0 ? 0 : columns - remainder
        return min(fillRow + columns, 8)
    }

    var body: some View {
        ZStack {
            Palette.bgOuter.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                toolbar
                CozyPanel(title: "✿  Y O U R   G A M E S  ✿") {
                    shelf
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }
            .padding(16)
        }
        .ornateFrame(corner: 16, heartCorners: true)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showingInstructions) {
            InstallInstructionsView(onOpenSteam: openSteam)
        }
        .sheet(item: $selectedGame) { game in
            GameDetailView(
                game: game,
                isLaunching: launching == game.appID,
                onPlay: { play(game) },
                onClose: { selectedGame = nil }
            )
        }
    }

    private var engineReady: Bool {
        if case .noEngine = status { return false }
        return true
    }

    // MARK: header — the plaque title banner

    private var header: some View {
        Plaque {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("♥").foregroundColor(Palette.heart).font(.system(size: 14))
                    Text("MEAD")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(Palette.textCream)
                    Text("♥").foregroundColor(Palette.heart).font(.system(size: 14))
                }
                Spacer()
                Text("apple silicon")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Palette.plaqueDk)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Palette.gold)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            CozyButton(label: "▶  open steam", tint: Palette.playGreen, tintDown: Palette.playGreenDk, action: openSteam)
            CozyButton(label: "＋  how to install games", tint: Palette.gold, tintDown: Palette.goldDk) {
                showingInstructions = true
            }
            Spacer()
            CozyButton(label: "⟳  refresh", tint: Palette.neutral, tintDown: Palette.neutralDk, action: refresh)
        }
    }

    // MARK: shelf

    @ViewBuilder private var shelf: some View {
        if games.isEmpty {
            emptyShelf
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(games) { game in
                        ItemSlot(game: game, isLaunching: launching == game.appID) {
                            selectedGame = game
                        }
                    }
                    ForEach(0..<emptySlotCount, id: \.self) { _ in
                        EmptyItemSlot()
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
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
                .fill(engineReady ? Palette.playGreen : Palette.closeRed)
                .frame(width: 10, height: 10)
            Text(engineReady ? "engine: ready · wine 11 + dxmt" : status.headline)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(Palette.textCream)
            Spacer()
            Text("\(games.count) game\(games.count == 1 ? "" : "s")")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.textCream.opacity(0.75))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            LinearGradient(colors: [Palette.plaque, Palette.plaqueDk], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.gold, lineWidth: 2.5))
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

// MARK: - Item slot (a filled inventory slot: a game you own)

private struct ItemSlot: View {
    let game: Game
    let isLaunching: Bool
    let onTap: () -> Void

    private var initial: String {
        String(game.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    // steam's public store banner for the app (every game has one).
    private var coverURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Palette.heart, Palette.heartDk],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initial)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.textCream)
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
                .frame(height: 78)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.gold, lineWidth: 1.5))
                .opacity(isLaunching ? 0.5 : 1)

                Text(isLaunching ? "starting…" : game.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.textCream)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(9)
            .background(
                LinearGradient(colors: [Palette.slot, Palette.slotDk], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.gold, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
    }
}

// MARK: - Empty item slot (open shelf space, echoing the reference's empty inventory slots)

private struct EmptyItemSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Palette.slotEmpty)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .foregroundColor(Palette.goldDk.opacity(0.6))
            )
            .aspectRatio(1, contentMode: .fit)
    }
}
