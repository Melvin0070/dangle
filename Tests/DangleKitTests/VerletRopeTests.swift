import Testing
import CoreGraphics
@testable import DangleKit

/// A rope with deterministic "randomness" so physics tests are reproducible.
private func makeRope() -> VerletRope {
    let rope = VerletRope(random: { 0.7 })
    rope.anchorX = 400
    rope.minAnchorX = 90
    rope.maxAnchorX = 900
    return rope
}

@Suite struct VerletRopeTests {

    @Test func startsHiddenAboveTheScreen() {
        let rope = makeRope()
        #expect(!rope.dangled)
        #expect(rope.pts.allSatisfy { $0.y < 0 })
    }

    @Test func settleInstantlyHangsStraightDown() {
        let rope = makeRope()
        rope.settleInstantly()
        #expect(rope.dangled)
        for (i, p) in rope.pts.enumerated() {
            #expect(abs(p.x - 400) < 0.001)
            #expect(abs(p.y - (rope.tuning.hangY + CGFloat(i) * rope.seg)) < 0.001)
        }
    }

    @Test func dropInConvergesToHangingRest() {
        let rope = makeRope()
        rope.setDangled(true)
        for _ in 0..<(120 * 10) { rope.step() }
        // Anchor reaches its hang height and the rope ends near rest length.
        #expect(abs(rope.anchorY - rope.tuning.hangY) < 1)
        let dx = rope.end.x - rope.anchorX
        let dy = rope.end.y - rope.anchorY
        let reach = (dx * dx + dy * dy).squareRoot()
        #expect(abs(reach - rope.restLength) < rope.seg)
    }

    @Test func segmentsStayNearRestLengthWhileSwinging() {
        let rope = makeRope()
        rope.settleInstantly()
        rope.flick()
        for _ in 0..<60 { rope.step() }
        for i in 0..<(rope.pts.count - 1) {
            let a = rope.pts[i], b = rope.pts[i + 1]
            let d = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            // Verlet relaxation is approximate; segments may stretch a little
            // mid-swing but must stay in the same neighborhood as rest.
            #expect(abs(d - rope.seg) < rope.seg * 0.5)
        }
    }

    @Test func flickImpartsVelocity() {
        let rope = makeRope()
        rope.settleInstantly()
        let before = rope.endVelocity
        #expect(abs(before.x) < 0.001)
        rope.flick()
        rope.step()
        let after = rope.endVelocity
        #expect(abs(after.x) > 0.5)
    }

    @Test func dismissEventuallyFullyHides() {
        let rope = makeRope()
        rope.settleInstantly()
        rope.setDangled(false)
        #expect(!rope.isFullyHidden)  // dips first, like a breath
        for _ in 0..<(120 * 5) { rope.step() }
        #expect(rope.isFullyHidden)
    }

    @Test func dragRespectsMaxStretch() {
        let rope = makeRope()
        rope.settleInstantly()
        rope.dragging = true
        rope.dragTo(CGPoint(x: 400, y: 2000))  // far beyond reach
        guard let target = rope.dragTarget else {
            Issue.record("dragTo should set a target")
            return
        }
        let dist = (target.y - rope.anchorY)
        #expect(dist <= rope.maxLength + 0.001)
    }

    @Test func anchorGlideReachesTarget() {
        let rope = makeRope()
        rope.settleInstantly()
        rope.anchorXTarget = 600
        for _ in 0..<(120 * 10) { rope.step() }
        #expect(abs(rope.anchorX - 600) < 1)
        #expect(rope.anchorXTarget == nil)
    }

    @Test func idleBreezeStaysGentle() {
        let rope = makeRope()
        rope.settleInstantly()
        for _ in 0..<(120 * 20) { rope.step() }  // settle transients
        var maxSpeed: CGFloat = 0
        for _ in 0..<(120 * 20) {
            rope.step()
            let v = rope.endVelocity
            maxSpeed = max(maxSpeed, (v.x * v.x + v.y * v.y).squareRoot())
        }
        // The engine's 3D sleep threshold (0.12) assumes the breeze peaks
        // well below it; this pins that assumption down.
        #expect(maxSpeed < 0.12)
        #expect(maxSpeed > 0.001)  // but the breeze is alive
    }

    @Test func interpolatedEndpointsMatchRope() {
        let rope = makeRope()
        rope.settleInstantly()
        let start = rope.interpolated(0).point
        let end = rope.interpolated(1).point
        #expect(abs(start.x - rope.pts[0].x) < 0.001)
        #expect(abs(start.y - rope.pts[0].y) < 0.001)
        #expect(abs(end.x - rope.end.x) < 0.001)
        #expect(abs(end.y - rope.end.y) < 0.001)
    }
}
