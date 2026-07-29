import SwiftUI

// the "set up the engine" page, linked from the install-games guide. one-time
// prerequisite: the monorepo's engine/install.sh builds wine 11 + dxmt into
// ~/Library/Application Support/decant. the app detects and drives that stack.
struct EngineSetupView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String, String)] = [
        ("1", "install the build tools",
         "you'll compile wine + dxmt once. install xcode + command line tools, the metal toolchain (xcodebuild -downloadComponent MetalToolchain), and homebrew. the engine scripts pull bison, meson, llvm, flex, and friends as needed."),
        ("2", "build the engine",
         "from the decant monorepo run  bash engine/install.sh  (~1 hour first time). it installs wine 11, rebuilds winemac.so with default symbol visibility, builds dxmt, creates the bottle layout under ~/Library/Application Support/decant, and deploys the launch scripts."),
        ("3", "create the bottle (if needed)",
         "full install.sh already sets up the steam bottle. if you only need a fresh prefix:  decant --init-bottle"),
        ("4", "install steam",
         "run  decant --install-steam  if steam is not in the bottle yet, then open steam and sign in once. it remembers you after."),
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
            Text("decant is one monorepo: engine/ builds the wine 11 + dxmt stack into ~/Library/Application Support/decant, and this app is the front end. the hard compile is a one-time bash engine/install.sh. the decant binary lives at /Applications/decant.app/Contents/MacOS/decant.")
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
