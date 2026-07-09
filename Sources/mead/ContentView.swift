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
            LinearGradient(colors: [Palette.bgOuter, Palette.bgOuterDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

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
                        .font(PixelFont.bold(26))
                        .tracking(4)
                        .foregroundColor(Palette.textCream)
                        .shadow(color: Palette.heart.opacity(0.5), radius: 6)
                    Text("♥").foregroundColor(Palette.heart).font(.system(size: 14))
                }
                Spacer()
                Text("apple silicon")
                    .font(PixelFont.medium(12))
                    .foregroundColor(Palette.plaqueDk)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.gold)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Palette.goldDk, lineWidth: 1.5))
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
        // the outer window margin is too thin to show floating accents, so
        // they live here instead, behind the shelf's own open pink space
        // where there's actually room for them to be seen.
        ZStack {
            FloatingAccents()
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
    }

    private var emptyShelf: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("🪴").font(.system(size: 52))
            Text("no games on the shelf yet")
                .font(PixelFont.bold(20))
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
                .shadow(color: (engineReady ? Palette.playGreen : Palette.closeRed).opacity(0.7), radius: 4)
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
        .shadow(color: Palette.plaqueDk.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    // MARK: actions

    private func refresh() {
        status = EngineManager.status()
        games = SteamManager.installedGames(bottle)
        // steam-under-wine drops a fresh, genericly-iconed shortcut on the
        // real desktop for any newly installed game, so this re-applies
        // the themed icon every refresh rather than once at install time.
        DesktopShortcuts.retheme(games)
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
    @State private var hovering = false

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
                ZStack(alignment: .topTrailing) {
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

                    // a little sparkle badge, echoing the reference's habit
                    // of dotting hearts on the label itself, not just
                    // around the item.
                    Text("✦")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.goldBright)
                        .shadow(color: Palette.plaqueDk.opacity(0.6), radius: 1)
                        .padding(4)
                }

                Text(isLaunching ? "starting…" : game.name)
                    .font(PixelFont.medium(13))
                    .foregroundColor(Palette.textCream)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(9)
            .background(
                LinearGradient(colors: [Palette.slot, Palette.slotDk], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(hovering ? Palette.goldBright : Palette.gold, lineWidth: hovering ? 2.5 : 2)
            )
            .shadow(color: Palette.goldBright.opacity(hovering ? 0.55 : 0), radius: hovering ? 8 : 0)
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(hovering ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
        .disabled(isLaunching)
    }
}

// a button style that just scales/darkens on press, for views (like item
// slots) that already carry their own background/border chrome and only
// need the press feedback, not PixelButtonStyle's full chunky-button look.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
            .overlay(
                Text("♡")
                    .font(.system(size: 22))
                    .foregroundColor(Palette.heartDk.opacity(0.3))
            )
            .aspectRatio(1, contentMode: .fit)
    }
}
