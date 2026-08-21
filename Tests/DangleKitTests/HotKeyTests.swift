import Testing
@testable import DangleKit

@Suite struct HotKeyTests {

    @Test func parsesCanonicalSpec() throws {
        let parsed = try #require(HotKeyCenter.parse("ctrl+opt+d"))
        #expect(parsed.keyCode == 0x02)
        #expect(parsed.modifiers == [.control, .option])
    }

    @Test func acceptsModifierSynonymsAndCase() throws {
        let a = try #require(HotKeyCenter.parse("Control+Alt+D"))
        let b = try #require(HotKeyCenter.parse("ctrl+option+d"))
        #expect(a.keyCode == b.keyCode)
        #expect(a.modifiers == b.modifiers)
        let cmd = try #require(HotKeyCenter.parse("cmd+shift+b"))
        #expect(cmd.modifiers == [.command, .shift])
    }

    @Test func rejectsBadSpecs() {
        #expect(HotKeyCenter.parse("d") == nil)            // no modifier
        #expect(HotKeyCenter.parse("ctrl+opt") == nil)     // no key
        #expect(HotKeyCenter.parse("ctrl+opt+é") == nil)   // unknown key
        #expect(HotKeyCenter.parse("") == nil)
    }
}
