import SwiftUI

// loads image assets bundled by scripts/bundle.sh (no xcode asset catalog,
// so these are read from the app's Resources folder by name).
enum Assets {
    static func image(_ relativePath: String) -> NSImage? {
        guard let base = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: base.appendingPathComponent(relativePath))
    }

    // the pixel "D" decanter monogram (transparent), for the header brand.
    static let logoD: NSImage? = image("logo-d.png")

    // the pixel wine-cellar backdrop, drawn faintly behind the game shelf.
    static let cellarBG: NSImage? = image("cellar-bg.jpg")

    // the pour clip as a keyed transparent frame sequence, preloaded once so
    // playback doesn't hit disk every frame.
    static let pourFrames: [NSImage] = (0..<60).compactMap {
        image(String(format: "pour/pour_%02d.png", $0))
    }
}

// the pouring-bottle loading animation, played while a game spins up.
// "decant" means pour, so a launching game literally pours. cycles the
// bundled frame sequence at 10fps; degrades to nothing if the frames are
// missing (SwiftUI just renders the empty Group).
struct PourAnimation: View {
    var frames: [NSImage] = Assets.pourFrames
    @State private var index = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !frames.isEmpty {
                Image(nsImage: frames[min(index, frames.count - 1)])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onReceive(timer) { _ in
            guard !frames.isEmpty else { return }
            index = (index + 1) % frames.count
        }
    }
}

// the header brand mark: the real pixel "D" monogram when bundled, with the
// drawn wax-seal as a fallback.
struct BrandLogo: View {
    var size: CGFloat = 44

    var body: some View {
        if let d = Assets.logoD {
            Image(nsImage: d)
                .resizable()
                .interpolation(.none)
                .frame(width: size, height: size)
        } else {
            BrandSeal(size: size)
        }
    }
}
