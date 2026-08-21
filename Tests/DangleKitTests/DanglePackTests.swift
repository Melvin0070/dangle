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
        #expect(pack.charm.kind == "glyph3d")
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
        guard spec.kind == "glyph3d" else { return }
        // A charm carrying its own path data does not need a glyph at all.
        if spec.pathData != nil { return }
        #expect(Charm3D.bespokeGlyphs.contains(spec.glyph) || spec.glyph.count <= 2,
                "\(source): glyph3d \"\(spec.glyph)\" has no geometry and would hang as text")
    }

    @Test func loadFailsOnMissingFile() {
        #expect(throws: (any Error).self) {
            _ = try DanglePack.load(from: URL(fileURLWithPath: "/nonexistent/pack.json"))
        }
    }

    @Test func fallbackShipsTheCodeCharm() {
        #expect(DanglePack.fallback.charm.glyph == "</>")
        #expect(DanglePack.fallback.charm.kind == "glyph3d")
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
