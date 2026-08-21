import Testing
import Foundation
import CoreGraphics
@testable import DangleKit

@Suite struct SVGPathTests {

    @Test func parsesAbsoluteAndRelativeCommands() throws {
        let absolute = try SVGPath.path(from: "M 0 0 L 10 0 L 10 10 Z")
        let relative = try SVGPath.path(from: "m 0 0 l 10 0 l 0 10 z")
        #expect(absolute.boundingBox.width == relative.boundingBox.width)
        #expect(absolute.boundingBox.height == relative.boundingBox.height)
    }

    /// SVG counts y downward; charm geometry counts it up. Getting this
    /// backwards hangs every imported shape upside down.
    @Test func flipsIntoYUpSpace() throws {
        let path = try SVGPath.path(from: "M 0 0 L 10 20 Z")
        #expect(path.boundingBox.minY < 0)
        #expect(abs(path.boundingBox.maxY) < 0.001)
    }

    @Test func handlesRunTogetherNumbers() throws {
        // ".5.5" is two numbers, and a minus sign starts a new one — a naive
        // split on whitespace and commas gets both wrong.
        let path = try SVGPath.path(from: "M.5.5L2-1Z")
        #expect(!path.isEmpty)
        #expect(abs(path.boundingBox.width - 1.5) < 0.001)
    }

    @Test func handlesExponentNotation() throws {
        let path = try SVGPath.path(from: "M 0 0 L 1e2 5E1 Z")
        #expect(abs(path.boundingBox.width - 100) < 0.001)
        #expect(abs(path.boundingBox.height - 50) < 0.001)
    }

    @Test func implicitLineToAfterMoveTo() throws {
        let implicit = try SVGPath.path(from: "M 0 0 5 0 5 5 Z")
        let explicit = try SVGPath.path(from: "M 0 0 L 5 0 L 5 5 Z")
        #expect(implicit.boundingBox == explicit.boundingBox)
    }

    @Test func smoothCurvesReflectTheirControlPoint() throws {
        let path = try SVGPath.path(from: "M 0 0 C 0 5 5 5 5 0 S 10 -5 10 0")
        #expect(!path.isEmpty)
        #expect(abs(path.boundingBox.width - 10) < 0.001)
    }

    @Test func arcsBecomeCurves() throws {
        // A half circle of radius 5 spans 10 across and 5 deep.
        let path = try SVGPath.path(from: "M 0 0 A 5 5 0 0 1 10 0 Z")
        #expect(abs(path.boundingBox.width - 10) < 0.05)
        #expect(abs(path.boundingBox.height - 5) < 0.05)
    }

    @Test func arcTooSmallForItsEndpointsIsScaledUp() throws {
        // rx/ry of 1 cannot reach a point 10 away; SVG says grow the radii.
        let path = try SVGPath.path(from: "M 0 0 A 1 1 0 0 1 10 0")
        #expect(abs(path.boundingBox.width - 10) < 0.05)
    }

    @Test func degenerateArcRadiiFallBackToALine() throws {
        let path = try SVGPath.path(from: "M 0 0 A 0 0 0 0 1 10 0")
        #expect(abs(path.boundingBox.width - 10) < 0.001)
        #expect(path.boundingBox.height < 0.001)
    }

    // MARK: Hostile input

    @Test func rejectsOversizedSource() {
        let huge = "M 0 0 " + String(repeating: "L 1 1 ", count: 20_000)
        #expect(throws: SVGPath.Failure.tooLarge) { _ = try SVGPath.path(from: huge) }
    }

    @Test func rejectsTooManySegments() {
        // Under the byte cap, over the segment cap.
        let dense = "M0 0" + String(repeating: "l1 1", count: SVGPath.maxSegments + 10)
        #expect(dense.utf8.count <= SVGPath.maxSourceBytes)
        #expect(throws: SVGPath.Failure.tooManySegments) { _ = try SVGPath.path(from: dense) }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { _ = try SVGPath.path(from: "hello") }
        #expect(throws: (any Error).self) { _ = try SVGPath.path(from: "M 0") }
        #expect(throws: (any Error).self) { _ = try SVGPath.path(from: "L 1 1") }
    }

    @Test func rejectsEmptyInput() {
        #expect(throws: (any Error).self) { _ = try SVGPath.path(from: "") }
        #expect(throws: (any Error).self) { _ = try SVGPath.path(from: "   ") }
    }

    // MARK: Round trip

    /// Export then re-import has to be the identity, or `--svg` would hand
    /// people a shape that comes back mirrored.
    @Test func roundTripsThroughSerialization() throws {
        for glyph in ["</>", "heart", "clover"] {
            let original = Charm3D.bespokePath(named: glyph, size: 96).cgPath
            let d = SVGPath.string(from: original)
            let reparsed = try SVGPath.path(from: d)
            let a = original.boundingBox, b = reparsed.boundingBox
            #expect(abs(a.minX - b.minX) < 0.01, "\(glyph) minX")
            #expect(abs(a.minY - b.minY) < 0.01, "\(glyph) minY")
            #expect(abs(a.width - b.width) < 0.01, "\(glyph) width")
            #expect(abs(a.height - b.height) < 0.01, "\(glyph) height")
        }
    }

    @Test func serializerEmitsNoStrayPrecision() {
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        let d = SVGPath.string(from: square)
        #expect(!d.contains(".000"))
        #expect(!d.contains("-0 "))
    }
}
