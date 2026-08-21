import Foundation
import CoreGraphics

/// A 12-point verlet rope, stepped at a fixed 120Hz.
///
/// Coordinate system: x grows right, y grows DOWN, y = 0 is the top edge of the
/// screen. The anchor rests slightly above the top edge and retracts far above
/// it when dismissed, so the charm "drops in" and "lifts out" through the edge.
public final class VerletRope {

    public struct Point {
        public var x: CGFloat
        public var y: CGFloat
        public var px: CGFloat
        public var py: CGFloat
    }

    public struct Tuning {
        public var count: Int = 12
        public var segment: CGFloat = 15.5
        /// Anchor y when dangled (slightly above the top edge).
        public var hangY: CGFloat = -4
        /// Anchor y when dismissed (fully off screen, card included).
        public var hiddenY: CGFloat = -420
        public var damping: CGFloat = 0.98
        public var gravity: CGFloat = 0.125
        public var iterations: Int = 5
        /// How far the rope may stretch while dragged, as a multiple of rest length.
        public var maxStretch: CGFloat = 1.4
        public init() {}
    }

    public static let dt: CGFloat = 1.0 / 120.0
    private static let liftDuration: CGFloat = 0.3

    public let tuning: Tuning
    public private(set) var pts: [Point]

    /// Distance from the rope's end point to the hanging object's center,
    /// measured along the rope's end direction.
    public var hangOffset: CGFloat

    /// Radius of the cursor's influence around the charm center. Scale this
    /// with the charm's size so the whole object feels alive, not just its
    /// middle.
    public var charmRadius: CGFloat = 40

    public var anchorX: CGFloat
    public private(set) var anchorY: CGFloat
    /// Set to smoothly glide the anchor along the top edge (non-drag re-hang).
    public var anchorXTarget: CGFloat?
    public var minAnchorX: CGFloat = 90
    public var maxAnchorX: CGFloat = 1000

    public private(set) var dangled = false
    public var dragging = false
    public var dragTarget: CGPoint?
    /// Cursor position in rope coordinates; nil when the cursor is elsewhere.
    public var mouse: CGPoint?
    /// Called when a drag along the top edge slides the anchor.
    public var onAnchorSlide: ((CGFloat) -> Void)?

    private var lastMouse: CGPoint?
    private var mouseVX: CGFloat = 0
    private var mouseVY: CGFloat = 0
    private var elapsed: CGFloat = 0
    private var dipRemaining: CGFloat = 0
    private var dipY: CGFloat = 0
    private var liftT: CGFloat = -1
    private var liftFromY: CGFloat = 0
    private var random: () -> CGFloat

    public init(tuning: Tuning = Tuning(), hangOffset: CGFloat = 0,
                random: @escaping () -> CGFloat = { CGFloat.random(in: 0..<1) }) {
        self.tuning = tuning
        self.hangOffset = hangOffset
        self.random = random
        self.anchorX = 0
        self.anchorY = tuning.hiddenY
        self.pts = (0..<tuning.count).map { i in
            Point(x: 0, y: tuning.hiddenY + CGFloat(i) * tuning.segment,
                  px: 0, py: tuning.hiddenY + CGFloat(i) * tuning.segment)
        }
    }

    public var end: Point { pts[tuning.count - 1] }
    public var seg: CGFloat { tuning.segment }
    public var restLength: CGFloat { seg * CGFloat(tuning.count - 1) }
    public var maxLength: CGFloat { restLength * tuning.maxStretch }
    private var hangTarget: CGFloat { tuning.hangY - 0 }

    /// Direction of the last segment; 0 when hanging straight down.
    public var endAngle: CGFloat {
        let a = pts[tuning.count - 2]
        let b = pts[tuning.count - 1]
        return atan2(b.x - a.x, b.y - a.y)
    }

    /// Center of the hanging object, `hangOffset` past the rope's end.
    public var charmCenter: CGPoint {
        let angle = endAngle
        let e = end
        return CGPoint(x: e.x + hangOffset * sin(angle),
                       y: e.y + hangOffset * cos(angle))
    }

    /// Point and tangent at normalized position t in [0, 1] along the rope.
    public func interpolated(_ t: CGFloat) -> (point: CGPoint, angle: CGFloat) {
        let m = tuning.count
        let a = min(max(t, 0), 1) * CGFloat(m - 1)
        let i = min(Int(a), m - 2)
        let f = a - CGFloat(i)
        let p = pts[i], q = pts[i + 1]
        return (CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f),
                atan2(q.x - p.x, q.y - p.y))
    }

    /// Snap the rope to a straight vertical rest below the anchor, no motion.
    public func settleInstantly() {
        anchorY = hangTarget
        dangled = true
        for i in 0..<tuning.count {
            pts[i].x = anchorX
            pts[i].px = anchorX
            pts[i].y = anchorY + CGFloat(i) * seg
            pts[i].py = pts[i].y
        }
    }

    /// Impulse on the end point, in a random horizontal direction.
    public func flick() {
        let sign: CGFloat = random() < 0.5 ? 1 : -1
        pts[tuning.count - 1].px += (18 + random() * 8) * sign
    }

    /// A little downward dip-and-spring, like the charm taking a bow.
    public func bow() {
        pts[tuning.count - 1].py -= 9
    }

    /// End-point velocity in points per physics step.
    public var endVelocity: CGPoint {
        let e = pts[tuning.count - 1]
        return CGPoint(x: e.x - e.px, y: e.y - e.py)
    }

    public func setDangled(_ on: Bool) {
        guard on != dangled else { return }
        dangled = on
        if on {
            dipRemaining = 0
            liftT = -1
            flick()
        } else {
            // Dip slightly before lifting away, like a breath before leaving.
            dipRemaining = 0.18
            dipY = anchorY + 16
        }
    }

    /// True once the rope has fully retracted off screen.
    public var isFullyHidden: Bool {
        !dangled && liftT < 0 && dipRemaining <= 0 && anchorY <= tuning.hiddenY + 1
    }

    public func dragTo(_ p: CGPoint) {
        let dx = p.x - anchorX
        let dy = p.y - anchorY
        let dist = max(hypot(dx, dy), 1)
        let len = min(max(dist - hangOffset, 1), maxLength)
        dragTarget = CGPoint(x: anchorX + dx / dist * len,
                             y: anchorY + dy / dist * len)
    }

    public func step() {
        let m = tuning.count
        elapsed += Self.dt

        // Glide toward a programmatic anchor target (re-hang without dragging).
        if let target = anchorXTarget, !dragging {
            let d = target - anchorX
            anchorX += min(max(d * 0.02, -3.6), 3.6)
            if abs(target - anchorX) < 0.5 {
                anchorX = target
                anchorXTarget = nil
            }
        }

        // Anchor vertical motion: drop in, or dip-then-lift away.
        if dangled {
            liftT = -1
            let target = hangTarget
            anchorY += (target - anchorY) * 0.08
            if abs(anchorY - target) < 0.5 { anchorY = target }
        } else if dipRemaining > 0 {
            dipRemaining -= Self.dt
            anchorY += (dipY - anchorY) * 0.15
            if dipRemaining <= 0 {
                liftT = 0
                liftFromY = anchorY
            }
        } else if liftT >= 0 {
            liftT += Self.dt
            let t = min(liftT / Self.liftDuration, 1)
            let ease = t * t * (3 - 2 * t)
            anchorY = liftFromY + (tuning.hiddenY - liftFromY) * ease
            if t >= 1 { liftT = -1 }
        }

        // Idle wind: two slow sines, stronger toward the free end.
        let wind = 0.0035 * sin(elapsed * 0.55) + 0.002 * sin(elapsed * 1.3 + 0.8)

        // Verlet integration.
        for i in 1..<m {
            var p = pts[i]
            let vx = (p.x - p.px) * tuning.damping
            let vy = (p.y - p.py) * tuning.damping
            p.px = p.x
            p.py = p.y
            p.x += vx + wind * (CGFloat(i) / CGFloat(m - 1))
            p.y += vy + tuning.gravity
            pts[i] = p
        }

        // Cursor: the charm leans away from a passing pointer.
        if let mouse, !dragging {
            if let last = lastMouse {
                mouseVX = mouseVX * 0.75 + (mouse.x - last.x) * 0.25
                mouseVY = mouseVY * 0.75 + (mouse.y - last.y) * 0.25
            }
            lastMouse = mouse

            let center = charmCenter
            let cx = center.x - mouse.x
            let cy = center.y - mouse.y
            let dist = hypot(cx, cy)
            let radius = charmRadius
            if dist < radius && dist > 0.5 {
                let u = (radius - dist) / radius
                let push = u * u * 0.4
                let vel = u * 0.1
                let fx = cx / dist * push + min(max(mouseVX, -14), 14) * vel
                let fy = cy / dist * push + min(max(mouseVY, -14), 14) * vel
                pts[m - 1].x += fx
                pts[m - 1].y += fy * 0.35
            }

            // Mid-rope points get a gentler brush-aside.
            for i in 1..<(m - 2) {
                let dx = pts[i].x - mouse.x
                let dy = pts[i].y - mouse.y
                let sq = dx * dx + dy * dy
                if sq < 1600 && sq > 1 {
                    let d = sq.squareRoot()
                    let f = (40 - d) / 40 * 0.8
                    pts[i].x += dx / d * f
                    pts[i].y += dy / d * f
                }
            }
        } else {
            lastMouse = nil
            mouseVX = 0
            mouseVY = 0
        }

        // Dragging near the top edge slides the anchor: re-hang anywhere.
        if dragging, let target = dragTarget, target.y < 60 {
            anchorX += (target.x - anchorX) * 0.12
            anchorX = min(max(anchorX, minAnchorX), maxAnchorX)
            onAnchorSlide?(anchorX)
        }

        // Constraint relaxation.
        let rest = seg
        for _ in 0..<tuning.iterations {
            pts[0].x = anchorX
            pts[0].y = anchorY
            if dragging, let target = dragTarget {
                pts[m - 1].x = target.x
                pts[m - 1].y = target.y
            }
            for i in 0..<(m - 1) {
                let a = pts[i], b = pts[i + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let d = max(hypot(dx, dy), 1e-4)
                let f = (d - rest) / d / 2
                let ox = dx * f
                let oy = dy * f
                if i == 0 {
                    // Anchor is immovable; the child takes the full correction.
                    pts[1].x -= ox * 2
                    pts[1].y -= oy * 2
                } else if dragging && i == m - 2 {
                    // While dragged the end is pinned; the parent takes it all.
                    pts[i].x += ox * 2
                    pts[i].y += oy * 2
                } else {
                    pts[i].x += ox
                    pts[i].y += oy
                    pts[i + 1].x -= ox
                    pts[i + 1].y -= oy
                }
            }
        }

        // The top of the screen is a physical edge: once settled, an
        // over-swing bumps it with a small bounce instead of sailing past
        // and getting clipped. Skipped during drop-in/lift-out, when the
        // whole chain legitimately travels above the edge.
        if dangled && abs(anchorY - tuning.hangY) < 1 {
            let ceiling: CGFloat = 2
            for i in 1..<m where pts[i].y < ceiling {
                let vy = pts[i].y - pts[i].py
                pts[i].y = ceiling
                pts[i].py = ceiling + vy * 0.25
            }
        }
    }
}
