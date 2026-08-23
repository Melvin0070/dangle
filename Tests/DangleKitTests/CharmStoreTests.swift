import Testing
import Foundation
@testable import DangleKit

@Suite struct CharmStoreTests {

    /// The repository's own charm catalog, used as a local fetch source.
    private var repoIndexURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("charms/index.json")
    }

    private func makeStore() throws -> (store: CharmStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dangle-tests-\(UUID().uuidString)")
        return (CharmStore(directory: dir, indexURL: repoIndexURL), dir)
    }

    @Test func emptyStoreListsNothing() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.installedCharms().isEmpty)
        #expect(store.charm(id: "heart") == nil)
    }

    @Test func installThenListRoundTrips() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let charm = Charm(
            id: "heart", name: "Heart",
            charm: .init(kind: .glyph3d, glyph: "heart", size: 96,
                         gradientHexes: ["#C81E3C"], accentHex: "#C81E3C",
                         menuGlyph: "❤️"))
        try store.install(charm)
        #expect(store.installedCharms() == [charm])
        #expect(store.charm(id: "heart") == charm)
        // Installing again overwrites rather than duplicating.
        try store.install(charm)
        #expect(store.installedCharms().count == 1)
    }

    @Test func ignoresBrokenCharmFiles() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        #expect(store.installedCharms().isEmpty)
    }

    @Test func fetchInstallsOnlyNewCharms() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fetch = try await withCheckedThrowingContinuation { cont in
            store.fetchNewCharms { cont.resume(with: $0) }
        }
        #expect(fetch.added.count >= 2)
        #expect(fetch.failedCount == 0)
        #expect(store.charm(id: "heart") != nil)
        #expect(store.charm(id: "clover") != nil)

        // A second fetch finds nothing new.
        let again = try await withCheckedThrowingContinuation { cont in
            store.fetchNewCharms { cont.resume(with: $0) }
        }
        #expect(again.added.isEmpty)
        #expect(again.failedCount == 0)
    }

    @Test func installRejectsHostileIDs() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["../escape", "a/b", "", "UPPER", "sp ace", String(repeating: "x", count: 65)] {
            let charm = Charm(id: id, name: "Evil",
                              charm: .init(kind: .emoji, glyph: "😈", size: 72,
                                           gradientHexes: nil, accentHex: "#000000",
                                           menuGlyph: nil))
            #expect(throws: (any Error).self) { try store.install(charm) }
        }
        #expect(store.installedCharms().isEmpty)
    }
}
