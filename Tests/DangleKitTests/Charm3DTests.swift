import Testing
import Foundation
import AppKit
@testable import DangleKit

@Suite struct Charm3DTests {

    /// A charm that is already square-ish must come out at exactly the size
    /// it always has — the aspect fix is not allowed to resize what ships.
    @Test func squareGlyphKeepsItsOldSize() {
        let (scale, m) = Charm3D.fit(bbW: 100, bbH: 100, size: 96)
        #expect(abs(scale - (96 * 0.82) / 100) < 0.0001)
        #expect(abs(m.height - 96 * 0.82) < 0.0001)
        #expect(abs(m.width - m.height) < 0.0001)
    }

    @Test func wideGlyphStaysInsideItsView() {
        // A 3:1 boat: fitted on height alone this would be ~2.5× charm size
        // wide, well past the view it swings in.
        let (_, m) = Charm3D.fit(bbW: 300, bbH: 100, size: 96)
        #expect(m.width <= 96 * 1.9 + 0.001)
        let reach = hypot(m.width / 2, m.height + CharmLayer.loopGap)
        #expect(reach < m.viewSide / 2)
    }

    /// Whatever the shape, a full 360° swing about the loop has to stay
    /// inside the view — that is the whole job of the derived view size.
    @Test func everyAspectRatioFitsItsView() {
        for bbW in stride(from: 20.0, through: 600.0, by: 20.0) {
            let (_, m) = Charm3D.fit(bbW: CGFloat(bbW), bbH: 100, size: 96)
            let reach = hypot(m.width / 2, m.height + CharmLayer.loopGap)
            #expect(reach < m.viewSide / 2, "aspect \(bbW)/100 overswings its view")
        }
    }

    @Test func fixedSideOverridesTheDerivedView() {
        let (_, m) = Charm3D.fit(bbW: 100, bbH: 100, size: 430, fixedSide: 1024)
        #expect(m.viewSide == 1024)
    }

    @Test func degenerateBoundsDoNotDivideByZero() {
        let (scale, m) = Charm3D.fit(bbW: 0, bbH: 0, size: 96)
        #expect(scale.isFinite)
        #expect(m.viewSide.isFinite)
    }

    @Test func everyBespokeGlyphHasAPath() {
        // The catalog guard trusts this set; an entry with no case in
        // makeScene would hang as extruded text and still pass that test.
        #expect(Charm3D.bespokeGlyphs == ["</>", "code", "heart", "clover"])
        #expect(!Charm3D.codeGlyphPath(size: 96).isEmpty)
        #expect(!Charm3D.heartPath(size: 96).isEmpty)
        #expect(!Charm3D.cloverPath(size: 96).isEmpty)
        for glyph in Charm3D.bespokeGlyphs {
            #expect(!Charm3D.bespokePath(named: glyph, size: 96).isEmpty,
                    "\(glyph) is listed as bespoke but has no path")
        }
    }
}
