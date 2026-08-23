import Testing
import Foundation
import AppKit
@testable import DangleKit

@Suite struct DanglePackTests {

    @Test func decodesAFullPack() throws {
        let json = """
        {
          "name": "Test",
          "charm": { "kind": "glyph3d", "glyph": "</>", "size": 96,
                     "gradientHexes": ["#E8590C", "#FFB86B"], "accentHex": "#E8590C" },
          "thread": { "colorHex": "#FFFFFF", "width": 3 },
          "noteSeconds": 7,
          "noteIntervalMinutes": 30,
          "hotkeys": { "toggle": "ctrl+opt+d" },
          "notes": [ "Hi" ]
        }
        """
        let pack = try JSONDecoder().decode(DanglePack.self, from: Data(json.utf8))
        #expect(pack.name == "Test")
        #expect(pack.charm.kind == .glyph3d)
        #expect(pack.charmSize == 96)
        #expect(pack.notes == ["Hi"])
        #expect(pack.noteIntervalMinutes == 30)
        #expect(pack.hotkeys?["toggle"] == "ctrl+opt+d")
    }

    @Test func decodesWithOptionalsMissing() throws {
        let json = """
        {
          "name": "Bare",
          "charm": { "kind": "emoji", "glyph": "🍀", "accentHex": "#2F9E44" },
          "thread": { "colorHex": "#FFFFFF", "width": 2 },
          "noteSeconds": 5,
          "notes": []
        }
        """
        let pack = try JSONDecoder().decode(DanglePack.self, from: Data(json.utf8))
        #expect(pack.charmSize == 96)  // size defaults
        #expect(pack.noteIntervalMinutes == nil)
        #expect(pack.hotkeys == nil)
        #expect(pack.gradientColors.count == 3)  // default gradient
    }

    @Test func repositoryPacksAndCharmsDecode() throws {
        // Every pack and charm shipped in the repository must stay valid.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DangleKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let fm = FileManager.default

        let packsDir = root.appendingPathComponent("Packs")
        let packs = try fm.contentsOfDirectory(at: packsDir, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath && $0.lastPathComponent != "local" }
        #expect(!packs.isEmpty)
        for dir in packs {
            let url = dir.appendingPathComponent("pack.json")
            let pack = try DanglePack.load(from: url)
            expectRenderableGlyph(pack.charm, source: dir.lastPathComponent)
        }

        let charmsDir = root.appendingPathComponent("charms")
        let index = try JSONDecoder().decode(
            CharmIndex.self,
            from: Data(contentsOf: charmsDir.appendingPathComponent("index.json")))
        #expect(!index.charms.isEmpty)
        for entry in index.charms {
            let charm = try JSONDecoder().decode(
                Charm.self,
                from: Data(contentsOf: charmsDir.appendingPathComponent(entry.file)))
            #expect(charm.id == entry.id)
            // Every catalog charm speaks for itself once hung.
            #expect(!(charm.notes ?? []).isEmpty)
            expectRenderableGlyph(charm.charm, source: entry.file)
        }
    }

    /// A glyph3d charm naming a shape nobody built does not fail — it hangs
    /// the name itself, extruded as type. That is right for "&" or "λ" and
    /// silently wrong for "caravel", so anything longer has to be bespoke.
    private func expectRenderableGlyph(_ spec: DanglePack.CharmSpec, source: String) {
        guard spec.kind == .glyph3d else { return }
        // A charm carrying its own path data does not need a glyph at all.
        if spec.pathData != nil { return }
        #expect(Charm3D.BespokeGlyph.allNames.contains(spec.glyph) || spec.glyph.count <= 2,
                "\(source): glyph3d \"\(spec.glyph)\" has no geometry and would hang as text")
    }

    /// A pack someone was given is a keepsake, not a cache — it has to keep
    /// loading in every later version. This is a frozen 1.0 pack: if a schema
    /// change ever stops it decoding, that change breaks packs already in the
    /// wild, and this test is the place to find that out. Never "fix" it by
    /// editing the JSON; make the decoder tolerate it, or add a migration.
    @Test func packsWrittenForVersion1StillDecode() throws {
        let json = """
        {
          "name": "Keepsake",
          "charm": {
            "kind": "glyph3d", "glyph": "moon", "size": 100,
            "gradientHexes": ["#1B1B2E", "#8E8AA8", "#C8A15A"],
            "accentHex": "#C8A15A", "menuGlyph": "☾",
            "fillHex": "#C8C2D8", "metalness": 1.0, "roughness": 0.24,
            "depth": 12, "chamfer": 2.2, "pathEvenOdd": true,
            "pathData": "M 0 -40 A 40 40 0 1 0 0 40 A 30 30 0 1 1 0 -40 Z"
          },
          "thread": { "colorHex": "#FFFFFF", "width": 3 },
          "noteSeconds": 8,
          "noteIntervalMinutes": 30,
          "hotkeys": { "toggle": "ctrl+opt+d", "note": "ctrl+opt+n" },
          "notes": ["Still here.", "Still yours."]
        }
        """
        let pack = try JSONDecoder().decode(DanglePack.self, from: Data(json.utf8))
        #expect(pack.name == "Keepsake")
        #expect(pack.charm.pathData?.isEmpty == false)
        #expect(pack.charm.pathEvenOdd == true)
        #expect(pack.charm.depth == 12)
        #expect(pack.notes.count == 2)
        #expect(pack.hotkeys?["note"] == "ctrl+opt+n")
    }

    /// Same promise for a charm file, which is what a private pack's own
    /// charms/ folder ships and what CharmStore writes into Application
    /// Support — those files outlive the app that installed them.
    @Test func charmsWrittenForVersion1StillDecode() throws {
        let json = """
        {
          "id": "keepsake", "name": "Keepsake",
          "charm": { "kind": "glyph3d", "glyph": "heart", "accentHex": "#C81E3C" },
          "notes": ["Still here."]
        }
        """
        let charm = try JSONDecoder().decode(Charm.self, from: Data(json.utf8))
        #expect(charm.id == "keepsake")
        #expect(charm.notes == ["Still here."])
    }

    /// Forward compatibility the other way: a pack written by a *newer*
    /// version must not break an older app. Unknown keys are ignored.
    @Test func unknownFieldsAreIgnored() throws {
        let json = """
        {
          "name": "Future",
          "charm": { "kind": "glyph3d", "glyph": "heart", "accentHex": "#C81E3C",
                     "someFieldFromLater": { "nested": [1, 2, 3] } },
          "thread": { "colorHex": "#FFFFFF", "width": 3 },
          "noteSeconds": 7,
          "notes": ["Hi"],
          "packLevelFieldFromLater": true
        }
        """
        let pack = try JSONDecoder().decode(DanglePack.self, from: Data(json.utf8))
        #expect(pack.name == "Future")
        #expect(pack.charm.glyph == "heart")
    }

    /// The gift case: a pack lives in Application Support so that replacing
    /// Dangle.app cannot take it away. Seeding must therefore be strictly
    /// once — a later app's bundled pack must never win over the copy the
    /// user owns, edited or not.
    @Test func seedingNeverOverwritesAnExistingPack() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("dangle-seed-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("bundled.json")
        try JSONEncoder().encode(DanglePack.fallback).write(to: source)
        let dest = tmp.appendingPathComponent("Dangle/pack.json")

        #expect(DanglePack.seedPack(from: source, to: dest))
        #expect(fm.fileExists(atPath: dest.path))

        // Stand in for a pack the user owns, then try to seed over it.
        var mine = DanglePack.fallback
        mine.name = "Mine, edited"
        try JSONEncoder().encode(mine).write(to: dest)

        #expect(DanglePack.seedPack(from: source, to: dest) == false)
        #expect(try DanglePack.load(from: dest).name == "Mine, edited")
    }

    /// A source that is not a decodable pack must not be seeded at all —
    /// better no file than one that shadows the bundled pack with garbage.
    @Test func seedingRejectsAnUnreadableSource() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("dangle-seed-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("bundled.json")
        try Data("{ not a pack }".utf8).write(to: source)
        let dest = tmp.appendingPathComponent("Dangle/pack.json")

        #expect(DanglePack.seedPack(from: source, to: dest) == false)
        #expect(!fm.fileExists(atPath: dest.path))
    }

    @Test func loadFailsOnMissingFile() {
        #expect(throws: (any Error).self) {
            _ = try DanglePack.load(from: URL(fileURLWithPath: "/nonexistent/pack.json"))
        }
    }

    @Test func fallbackShipsTheCodeCharm() {
        #expect(DanglePack.fallback.charm.glyph == "</>")
        #expect(DanglePack.fallback.charm.kind == .glyph3d)
    }

    @Test func hexColorsParse() {
        let orange = NSColor(hex: "#E8590C")
        #expect(abs(orange.redComponent - CGFloat(0xE8) / 255) < 0.001)
        #expect(abs(orange.greenComponent - CGFloat(0x59) / 255) < 0.001)
        #expect(abs(orange.blueComponent - CGFloat(0x0C) / 255) < 0.001)
        // Malformed input falls back to gray rather than crashing.
        let gray = NSColor(hex: "nope")
        #expect(abs(gray.redComponent - 0.5) < 0.001)
    }
}
