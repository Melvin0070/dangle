import Testing
import Foundation
@testable import DangleKit

@Suite struct CharmOverrideTests {

    /// The stored format predates the type and is what is already sitting in
    /// people's UserDefaults, so it has to round-trip exactly.
    @Test func roundTripsThroughItsStoredForm() {
        let cases: [CharmOverride] = [.installed(id: "clover"), .emoji("🍀")]
        for override in cases {
            #expect(CharmOverride(rawValue: override.rawValue) == override)
        }
        #expect(CharmOverride.installed(id: "clover").rawValue == "clover")
        #expect(CharmOverride.emoji("🍀").rawValue == "emoji:🍀")
    }

    @Test func readsOverridesStoredByEarlierBuilds() {
        #expect(CharmOverride(rawValue: "emoji:🍀") == .emoji("🍀"))
        #expect(CharmOverride(rawValue: "clover") == .installed(id: "clover"))
    }

    @Test func rejectsEmptyAndPrefixOnlyValues() {
        #expect(CharmOverride(rawValue: "") == nil)
        #expect(CharmOverride(rawValue: "emoji:") == nil)
    }

    @Test func exposesTheCaseTheCharmMenuNeeds() {
        #expect(CharmOverride.installed(id: "heart").installedID == "heart")
        #expect(CharmOverride.emoji("🍀").installedID == nil)
        #expect(CharmOverride.emoji("🍀").isEmoji)
        #expect(!CharmOverride.installed(id: "heart").isEmoji)
    }
}

@Suite struct CharmKindTests {

    @Test func knownKindsRoundTrip() throws {
        for kind: DanglePack.Kind in [.glyph3d, .glass, .emoji] {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(DanglePack.Kind.self, from: data) == kind)
        }
        #expect(DanglePack.Kind.glyph3d.rawValue == "glyph3d")
    }

    /// A kind this version has never heard of must not take the whole pack
    /// down with it — a pack written by a newer Dangle still has to hang.
    @Test func unrecognizedKindSurvivesDecoding() throws {
        let json = """
        {
          "name": "From the future",
          "charm": { "kind": "hologram", "glyph": "🍀", "accentHex": "#2F9E44" },
          "thread": { "colorHex": "#FFFFFF", "width": 3 },
          "noteSeconds": 7,
          "notes": ["Hi"]
        }
        """
        let pack = try JSONDecoder().decode(DanglePack.self, from: Data(json.utf8))
        #expect(pack.charm.kind == .unrecognized("hologram"))
        // And it re-encodes as itself rather than being flattened to a known
        // kind, so round-tripping a pack does not quietly rewrite it.
        #expect(pack.charm.kind.rawValue == "hologram")
    }
}
