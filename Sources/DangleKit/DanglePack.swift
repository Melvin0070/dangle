import Foundation
import AppKit

/// A pack is the customization layer: one JSON file (plus optional assets)
/// that fully describes what hangs from the screen and what it says.
public struct DanglePack: Codable, Equatable {
    public var name: String
    public var charm: CharmSpec
    public var thread: ThreadSpec
    public var notes: [Note]
    /// Seconds a note stays on screen.
    public var noteSeconds: Double
    /// Minutes between spontaneous notes. nil or <= 0 disables the timer.
    public var noteIntervalMinutes: Double?
    /// Optional global hotkeys, e.g. {"toggle": "ctrl+opt+D", "note": "ctrl+opt+N"}.
    public var hotkeys: [String: String]?
    /// Optional sound file (relative to the pack) played on dangle://bless.
    public var blessSoundPath: String?

    public struct CharmSpec: Codable, Equatable {
        /// "glyph3d" hangs the glyph as a real extruded 3D shape (SceneKit),
        /// "glass" hangs a gradient glass tile with a glyph, and "emoji"
        /// hangs a bare glyph. All get a tiny twin as the middle bead.
        public var kind: String
        /// The glyph: "</>" for glass, any emoji for emoji kind.
        public var glyph: String
        /// Tile side in points (glass) or glyph size (emoji). Default 96.
        public var size: Double?
        /// Motion-gradient colors for the glass tile, top-left to bottom-right.
        public var gradientHexes: [String]?
        /// Accent used by notes, confetti, and the glow.
        public var accentHex: String
        /// Emoji or short text shown in the menu bar while this charm hangs.
        public var menuGlyph: String?
    }

    public struct ThreadSpec: Codable, Equatable {
        public var colorHex: String
        public var width: Double
    }

    public struct Note: Codable, Equatable {
        public var text: String
        public var from: String
    }

    public var charmSize: CGFloat { CGFloat(charm.size ?? 96) }
    public var gradientColors: [NSColor] {
        let hexes = charm.gradientHexes ?? ["#5B8CFF", "#8B5CF6", "#22D3EE"]
        return hexes.map { NSColor(hex: $0) }
    }

    public static func load(from url: URL) throws -> DanglePack {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DanglePack.self, from: data)
    }

    /// Resolution order: $DANGLE_PACK, then Application Support, then the
    /// bundled pack, then a built-in fallback. This is what makes the app an
    /// engine: drop a pack.json into Application Support and it is yours.
    public static func resolve() -> (pack: DanglePack, baseURL: URL?) {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["DANGLE_PACK"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(appSupport.appendingPathComponent("Dangle/pack.json"))
        }
        if let bundled = Bundle.main.url(forResource: "pack", withExtension: "json") {
            candidates.append(bundled)
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            if let pack = try? load(from: url) {
                return (pack, url.deletingLastPathComponent())
            }
        }
        return (.fallback, nil)
    }

    public static let fallback = DanglePack(
        name: "Dangle",
        charm: CharmSpec(kind: "glyph3d", glyph: "</>", size: 96,
                         gradientHexes: ["#E8590C", "#FFB86B", "#FF5E78"],
                         accentHex: "#E8590C"),
        thread: ThreadSpec(colorHex: "#FFFFFF", width: 3),
        notes: [Note(text: "Edit pack.json to make this yours.", from: "Dangle")],
        noteSeconds: 7,
        noteIntervalMinutes: nil,
        hotkeys: nil,
        blessSoundPath: nil
    )
}

public extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: CGFloat
        if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
        } else {
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
