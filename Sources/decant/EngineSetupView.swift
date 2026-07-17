import SwiftUI

// the "set up the engine" page, linked from the install-games guide. this is
// the one-time, technical prerequisite: decant runs games on a home-built
// wine 11 + dxmt stack in ~/Library/Application Support/hearth, and only
// detects it. the app can't build the engine for you, so these are the steps
// to build it by hand. the hard part (compiling wine + dxmt) points at the
// recipe; the bottle and steam steps use decant's own cli.
struct EngineSetupView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "install the build tools",
         "you'll compile a small wine stack from source. install xcode + command line tools, the metal toolchain (xcodebuild -downloadComponent MetalToolchain), homebrew, and the build deps: bison 3.8, meson 1.10.2 (in a venv), llvm 15, flex, zstd."),
        ("2", "build wine 11 + dxmt",
         "follow the recipe at github.com/notpop/steam-on-m1-wine to build wine 11. rebuild winemac.so with default symbol visibility, build the dxmt fork, and install its dlls. drop the finished \u{201c}Wine Stable.app\u{201d} into ~/Library/Application Support/hearth/engines/wine11/."),
        ("3", "create the bottle",
         "run  decant --init-bottle  in terminal. it boots a fresh windows environment (the bottle) where steam and your games will live."),
        ("4", "install steam",
         "run  decant --install-steam , then open steam and sign in once. it remembers you after."),
        ("5", "check it",
         "run  decant --doctor , or just reopen decant. the footer should read \u{201c}engine: ready\u{201d} with a green dot. now the install-a-game steps will work."),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgHi, Palette.bg, Palette.bgDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Text("set up the engine")
                        .font(PixelFont.bold(20))
                        .foregroundColor(Palette.brand)
                    Spacer()
                    PixelButton(label: "done", top: Palette.cork, bottom: Palette.corkDk, text: Palette.cream) { dismiss() }
                }

                ScrollView {
                    VStack(spacing: 12) {
                        introCard
                        ForEach(steps, id: \.0) { step in
                            stepCard(number: step.0, title: step.1, body: step.2)
                        }
                        gotchasCard
                    }
                    .padding(2)
                }
            }
            .padding(18)
            .frame(minWidth: 460, minHeight: 520)
        }
        .bevel(width: 3)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("one-time setup")
                .font(PixelFont.bold(15))
                .foregroundColor(Palette.brand)
            Text("decant plays games on a home-built wine 11 + dxmt engine kept in ~/Library/Application Support/hearth. it's a technical, one-time build. decant only detects and drives it, so you set it up once by hand. the decant binary lives at /Applications/decant.app/Contents/MacOS/decant.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Palette.cream, Palette.label], startPoint: .top, endPoint: .bottom))
        .bevel(width: 2)
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

    private var gotchasCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("gotchas from building it")
                .font(PixelFont.bold(15))
                .foregroundColor(Palette.cream)
            Text("bison must be homebrew's 3.8, not apple's 2.3. meson must be 1.10.2 in a venv (1.11 is too new). llvm 15 needs -L/usr/local/lib -lzstd. you need the xcode metal toolchain. dxmt's com_guid.cpp needs #include <iomanip>.")
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
