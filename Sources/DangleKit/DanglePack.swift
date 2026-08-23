import Foundation
import AppKit

/// A pack is the customization layer: one JSON file (plus optional assets)
/// that fully describes what hangs from the screen and what it says.
public struct DanglePack: Codable, Equatable {
    public var name: String
    public var charm: CharmSpec
    public var thread: ThreadSpec
    /// The words shown under the charm — text only, nothing else.
    public var notes: [String]
    /// Seconds a note stays on screen.
    public var noteSeconds: Double
    /// Minutes between spontaneous notes. nil or <= 0 disables the timer.
    public var noteIntervalMinutes: Double?
    /// Optional global hotkeys, e.g. {"toggle": "ctrl+opt+D", "note": "ctrl+opt+N"}.
    public var hotkeys: [String: String]?
    /// Optional sound file (relative to the pack) played on dangle://bless.
    public var blessSoundPath: String?

    /// How a charm is drawn. Not a plain `String` enum: an unrecognised kind
    /// has to keep decoding, or a pack written by a newer Dangle would be
    /// refused whole by an older one.
    public enum Kind: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        /// A real extruded 3D shape (SceneKit).
        case glyph3d
        /// A gradient glass tile with the glyph on top.
        case glass
        /// The bare glyph, big.
        case emoji
        /// Written by a version that knows something this one does not.
        /// Drawn as `glass`, which needs nothing but a glyph and colors.
        case unrecognized(String)

        public init(rawValue: String) {
            switch rawValue {
            case "glyph3d": self = .glyph3d
            case "glass": self = .glass
            case "emoji": self = .emoji
            default: self = .unrecognized(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .glyph3d: "glyph3d"
            case .glass: "glass"
            case .emoji: "emoji"
            case .unrecognized(let raw): raw
            }
        }

        public init(from decoder: any Decoder) throws {
            self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public struct CharmSpec: Codable, Equatable {
        /// All kinds get a tiny twin as the middle bead.
        public var kind: Kind
        /// The glyph: "</>" for glass, any emoji for emoji kind.
        public var glyph: String
        /// Tile side in points (glass) or glyph size (emoji). Default 96.
        public var size: Double?
        /// Motion-gradient colors for the glass tile, top-left to bottom-right.
        public var gradientHexes: [String]?
        /// Accent used for the twin bead in the flat scene diagram.
        public var accentHex: String
        /// Emoji or short text shown in the menu bar while this charm hangs.
        public var menuGlyph: String?
        /// An SVG `d` attribute. When present it *is* the charm's shape, and
        /// `glyph` is ignored — this is what lets a new 3D shape ship as data
        /// instead of as a case in `Charm3D`.
        public var pathData: String?
        /// Fill the path by the even-odd rule instead of nonzero. Design
        /// tools write `fill-rule="evenodd"` for most compound shapes.
        public var pathEvenOdd: Bool?
        /// Overrides for the extruded material. All optional; the defaults
        /// are the dark chrome every charm started out wearing.
        public var fillHex: String?
        public var metalness: Double?
        public var roughness: Double?
        public var depth: Double?
        public var chamfer: Double?
    }

    public struct ThreadSpec: Codable, Equatable {
        public var colorHex: String
        public var width: Double
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

    /// Where a user's own pack lives. Survives replacing Dangle.app, which is
    /// the whole point: the app is disposable, the pack is not.
    public static var userPackURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Dangle/pack.json")
    }

    /// Copies the bundled pack to Application Support the first time the app
    /// runs, and never touches it again. Without this a pack lives only inside
    /// the .app, so replacing the app — an update, a re-download — silently
    /// throws away whatever it was carrying. Charms already survive this way
    /// (`CharmStore.seedBundledCharms`); packs did not.
    ///
    /// Deliberately seed-once: a later version's bundled pack must never
    /// overwrite the copy the user owns, even if the user never edited it.
    @discardableResult
    public static func seedBundledPack() -> Bool {
        seedPack(from: Bundle.main.url(forResource: "pack", withExtension: "json"),
                 to: userPackURL)
    }

    /// Split out from `seedBundledPack` so the never-overwrite promise is
    /// testable without a real app bundle.
    @discardableResult
    static func seedPack(from source: URL?, to dest: URL?) -> Bool {
        let fm = FileManager.default
        guard let dest, let source,
              !fm.fileExists(atPath: dest.path),
              let data = try? Data(contentsOf: source),
              // Only seed something the app can actually read back.
              (try? JSONDecoder().decode(DanglePack.self, from: data)) != nil
        else { return false }
        try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        return (try? data.write(to: dest, options: .atomic)) != nil
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
        if let user = userPackURL {
            candidates.append(user)
        }
        if let bundled = Bundle.main.url(forResource: "pack", withExtension: "json") {
            candidates.append(bundled)
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            do {
                return (try load(from: url), url.deletingLastPathComponent())
            } catch {
                // Falling through silently would swap someone's pack for the
                // stock one with no clue why, so say which file and why.
                FileHandle.standardError.write(Data(
                    "Dangle: ignoring \(url.path) — \(error)\n".utf8))
            }
        }
        return (.fallback, nil)
    }

    public static let fallback = DanglePack(
        name: "Dangle",
        charm: CharmSpec(kind: .glyph3d, glyph: "</>", size: 96,
                         gradientHexes: ["#E8590C", "#FFB86B", "#FF5E78"],
                         accentHex: "#E8590C"),
        thread: ThreadSpec(colorHex: "#FFFFFF", width: 3),
        notes: ["Edit pack.json to make this yours."],
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
