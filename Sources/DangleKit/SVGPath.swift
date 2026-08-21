import Foundation
import CoreGraphics

/// Reads and writes the `d` attribute of an SVG path.
///
/// This is what lets a charm ship a *shape* as data rather than as a case in
/// `Charm3D`. Path data arrives from a catalog over the network, so it is
/// treated as hostile input: bounded, strictly parsed, and never partially
/// applied — a malformed path throws rather than hanging a half-drawn charm.
public enum SVGPath {

    /// Roughly a hand-drawn glyph an order of magnitude over: enough for any
    /// charm, far short of a path that would stall the tessellator.
    public static let maxSegments = 4_000
    public static let maxSourceBytes = 64 * 1_024

    public enum Failure: Error, Equatable {
        case tooLarge
        case tooManySegments
        case unsupportedCommand(Character)
        case malformed
        case empty
    }

    // MARK: Reading

    /// Parses a `d` attribute into a path in the y-up space the charm
    /// geometry uses — SVG counts y downward, so the result is flipped.
    public static func path(from d: String) throws -> CGPath {
        guard d.utf8.count <= maxSourceBytes else { throw Failure.tooLarge }

        var reader = Reader(d)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?
        var segments = 0
        var started = false

        func bump() throws {
            segments += 1
            guard segments <= maxSegments else { throw Failure.tooManySegments }
        }

        while true {
            reader.skipSeparators()
            if let next = reader.peekCommand() {
                command = next
                reader.advance()
            } else if reader.atEnd {
                break
            } else if command == nil {
                throw Failure.malformed
            }
            guard let cmd = command else { throw Failure.malformed }

            let relative = cmd.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y)
                         : CGPoint(x: x, y: y)
            }

            switch Character(cmd.uppercased()) {
            case "M":
                guard let x = reader.number(), let y = reader.number() else {
                    throw Failure.malformed
                }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                started = true
                lastCubicControl = nil
                lastQuadControl = nil
                // Further pairs after a moveto are implicit linetos.
                command = relative ? "l" : "L"
            case "L":
                guard let x = reader.number(), let y = reader.number() else {
                    throw Failure.malformed
                }
                guard started else { throw Failure.malformed }
                current = point(x, y)
                path.addLine(to: current)
                try bump()
                lastCubicControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = reader.number(), started else { throw Failure.malformed }
                current = relative ? CGPoint(x: current.x + x, y: current.y)
                                   : CGPoint(x: x, y: current.y)
                path.addLine(to: current)
                try bump()
                lastCubicControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = reader.number(), started else { throw Failure.malformed }
                current = relative ? CGPoint(x: current.x, y: current.y + y)
                                   : CGPoint(x: current.x, y: y)
                path.addLine(to: current)
                try bump()
                lastCubicControl = nil
                lastQuadControl = nil
            case "C":
                guard let x1 = reader.number(), let y1 = reader.number(),
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number(), started
                else { throw Failure.malformed }
                let c1 = point(x1, y1), c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                try bump()
                lastCubicControl = c2
                lastQuadControl = nil
            case "S":
                guard let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number(), started
                else { throw Failure.malformed }
                let c1 = lastCubicControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                try bump()
                lastCubicControl = c2
                lastQuadControl = nil
            case "Q":
                guard let x1 = reader.number(), let y1 = reader.number(),
                      let x = reader.number(), let y = reader.number(), started
                else { throw Failure.malformed }
                let c = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                try bump()
                lastQuadControl = c
                lastCubicControl = nil
            case "T":
                guard let x = reader.number(), let y = reader.number(), started
                else { throw Failure.malformed }
                let c = lastQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                current = point(x, y)
                path.addQuadCurve(to: current, control: c)
                try bump()
                lastQuadControl = c
                lastCubicControl = nil
            case "A":
                guard let rx = reader.number(), let ry = reader.number(),
                      let rot = reader.number(), let large = reader.flag(),
                      let sweep = reader.flag(),
                      let x = reader.number(), let y = reader.number(), started
                else { throw Failure.malformed }
                let end = point(x, y)
                try addArc(to: end, from: current, rx: rx, ry: ry,
                           rotationDegrees: rot, largeArc: large, sweep: sweep,
                           into: path, bump: bump)
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
            case "Z":
                guard started else { throw Failure.malformed }
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                throw Failure.unsupportedCommand(cmd)
            }

            if reader.atEnd { break }
        }

        guard !path.isEmpty else { throw Failure.empty }
        // SVG's y axis points down; charm geometry's points up.
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        guard let flipped = path.copy(using: &flip) else { throw Failure.malformed }
        return flipped
    }

    /// One SVG elliptical arc as up to four cubic segments — CGPath has no
    /// arc-to-endpoint primitive, and the endpoint parameterization SVG uses
    /// has to be converted to a center before it can be swept.
    private static func addArc(to end: CGPoint, from start: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDegrees: CGFloat,
                               largeArc: Bool, sweep: Bool,
                               into path: CGMutablePath,
                               bump: () throws -> Void) rethrows {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            try bump()
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        // An arc too small to reach its endpoint is scaled up until it can.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let num = max(rx * rx * ry * ry - den, 0)
        let coefficient = (largeArc != sweep ? 1.0 : -1.0) * sqrt(den > 0 ? num / den : 0)
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            let a = acos(min(max(len > 0 ? dot / len : 0, -1), 1))
            return (ux * vy - uy * vx) < 0 ? -a : a
        }
        let sx = (x1 - cx1) / rx, sy = (y1 - cy1) / ry
        let ex = (-x1 - cx1) / rx, ey = (-y1 - cy1) / ry
        var theta = angle(1, 0, sx, sy)
        var sweepAngle = angle(sx, sy, ex, ey)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }

        func onArc(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }

        // A cubic tracks a circular arc well up to a quarter turn, badly past it.
        let count = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let step = sweepAngle / CGFloat(count)
        let alpha = 4.0 / 3.0 * tan(step / 4)
        for _ in 0..<count {
            let next = theta + step
            let p1 = onArc(theta), p2 = onArc(next)
            let t1 = tangent(theta), t2 = tangent(next)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + alpha * t1.x, y: p1.y + alpha * t1.y),
                          control2: CGPoint(x: p2.x - alpha * t2.x, y: p2.y - alpha * t2.y))
            try bump()
            theta = next
        }
    }

    // MARK: Writing

    /// Serializes a path back to a `d` attribute, flipping y-up geometry back
    /// into SVG's y-down space so `path(from: string(from: p))` is a no-op.
    public static func string(from path: CGPath) -> String {
        var out: [String] = []
        func num(_ v: CGFloat) -> String {
            var s = String(format: "%.3f", v)
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s == "-0" ? "0" : s
        }
        func pair(_ p: CGPoint) -> String { "\(num(p.x)) \(num(-p.y))" }

        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                out.append("M \(pair(e.points[0]))")
            case .addLineToPoint:
                out.append("L \(pair(e.points[0]))")
            case .addQuadCurveToPoint:
                out.append("Q \(pair(e.points[0])) \(pair(e.points[1]))")
            case .addCurveToPoint:
                out.append("C \(pair(e.points[0])) \(pair(e.points[1])) \(pair(e.points[2]))")
            case .closeSubpath:
                out.append("Z")
            @unknown default:
                break
            }
        }
        return out.joined(separator: " ")
    }

    // MARK: Scanning

    private struct Reader {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        var atEnd: Bool { i >= chars.count }

        mutating func advance() { i += 1 }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == "," || chars[i].isWhitespace { i += 1 }
        }

        func peekCommand() -> Character? {
            guard i < chars.count else { return nil }
            let c = chars[i]
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) ? c : nil
        }

        /// SVG numbers run together — "1.5.5" is two numbers, and a sign
        /// starts a new one — so this cannot lean on Double's parser alone.
        mutating func number() -> CGFloat? {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "+" || chars[i] == "-" {
                s.append(chars[i])
                i += 1
            }
            var sawDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber {
                    s.append(c)
                    i += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    s.append(c)
                    i += 1
                } else {
                    break
                }
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                var exponent = "e"
                if j < chars.count, chars[j] == "+" || chars[j] == "-" {
                    exponent.append(chars[j])
                    j += 1
                }
                var sawDigit = false
                while j < chars.count, chars[j].isNumber {
                    exponent.append(chars[j])
                    j += 1
                    sawDigit = true
                }
                if sawDigit {
                    s += exponent
                    i = j
                }
            }
            guard let value = Double(s) else { return nil }
            return CGFloat(value)
        }

        /// Arc flags are single characters, and may be written unseparated.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            switch chars[i] {
            case "0": i += 1; return false
            case "1": i += 1; return true
            default: return nil
            }
        }
    }
}
