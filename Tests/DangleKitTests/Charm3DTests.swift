import Testing
import Foundation
import AppKit
import SceneKit
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
        #expect(Charm3D.BespokeGlyph.allNames == ["</>", "code", "heart", "clover"])
        #expect(!Charm3D.codeGlyphPath(size: 96).isEmpty)
        #expect(!Charm3D.heartPath(size: 96).isEmpty)
        #expect(!Charm3D.cloverPath(size: 96).isEmpty)
        for glyph in Charm3D.BespokeGlyph.allNames {
            #expect(!Charm3D.bespokePath(named: glyph, size: 96).isEmpty,
                    "\(glyph) is listed as bespoke but has no path")
        }
    }

    /// A bespoke shape's depth, chamfer and finish are defaults a charm may
    /// state over, the same as a `pathData` charm can. Nothing shipped sets
    /// them, so this is about the two paths behaving alike rather than about
    /// any charm that exists today.
    @Test func aBespokeCharmCanStateItsOwnFinish() throws {
        var spec = DanglePack.CharmSpec(kind: .glyph3d, glyph: "heart",
                                        size: 96, gradientHexes: nil,
                                        accentHex: "#C81E3C")
        var pack = DanglePack.fallback
        pack.charm = spec

        func shape(_ pack: DanglePack) -> SCNShape? {
            Charm3D.makeScene(pack: pack, viewSide: 200).glyphNode.geometry as? SCNShape
        }

        // SceneKit stores these as Float, so compare with a tolerance.
        func isNear(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

        // Untouched, the heart keeps its built-in lacquer and extrusion.
        let stock = try #require(shape(pack))
        #expect(isNear(stock.extrusionDepth, 15))
        #expect(isNear(stock.chamferRadius, 2.8))
        #expect(stock.materials.first?.diffuse.contents as? NSColor
                == NSColor(hex: "#C81E3C"))

        spec.fillHex = "#123456"
        spec.depth = 30
        spec.chamfer = 1
        pack.charm = spec
        let overridden = try #require(shape(pack))
        #expect(isNear(overridden.extrusionDepth, 30))
        #expect(isNear(overridden.chamferRadius, 1))
        #expect(overridden.materials.first?.diffuse.contents as? NSColor
                == NSColor(hex: "#123456"))
    }

    /// A charm whose shape arrived as `pathData` must be extruded from that
    /// path. If shape-as-data ever stopped working, the charm would fall back
    /// to extruding its glyph *name* as text — a pack asking for "esfera"
    /// would hang the word "esfera" — and it would do so silently. Charms
    /// that exist only as path data have no other geometry to fall back on.
    @Test func aPathDataCharmIsExtrudedFromItsPath() throws {
        var pack = DanglePack.fallback
        pack.charm = DanglePack.CharmSpec(
            kind: .glyph3d,
            // A name with no bespoke geometry: only the path can save it.
            glyph: "no-such-shape", size: 96, gradientHexes: nil,
            accentHex: "#C8A15A",
            pathData: "M 0 -40 A 40 40 0 1 0 0 40 A 30 30 0 1 1 0 -40 Z")

        let geometry = Charm3D.makeScene(pack: pack, viewSide: 200).glyphNode.geometry
        #expect(geometry is SCNShape, "path data no longer builds the shape")
        #expect(!(geometry is SCNText), "the charm degraded to its name as text")

        // The same charm without its path really does degrade to text, so the
        // assertion above is discriminating rather than always true.
        pack.charm.pathData = nil
        let degraded = Charm3D.makeScene(pack: pack, viewSide: 200).glyphNode.geometry
        #expect(degraded is SCNText)
    }

    /// Names map to exactly one shape. Two cases claiming the same name would
    /// make `BespokeGlyph(name:)` pick by declaration order and silently hang
    /// the wrong geometry.
    @Test func bespokeNamesAreUnambiguous() {
        let all = Charm3D.BespokeGlyph.allCases.flatMap(\.names)
        #expect(all.count == Set(all).count, "two shapes answer to the same name")
        for shape in Charm3D.BespokeGlyph.allCases {
            for name in shape.names {
                #expect(Charm3D.BespokeGlyph(name: name) == shape)
            }
        }
    }
}
