import AppKit
import QuartzCore

/// A port of canvas-confetti's particle physics (the library behind the
/// familiar web confetti): a sharp pop, quick decay, then a gentle constant
/// fall with wobble and flutter. Rendered as lightweight CALayers and stepped
/// from the engine's display link.
///
/// canvas-confetti — https://github.com/catdad/canvas-confetti
/// Copyright (c) 2020, Kiril Vatev. Licensed under the ISC license:
/// permission to use, copy, modify, and/or distribute this software for any
/// purpose with or without fee is hereby granted, provided that the above
/// copyright notice and this permission notice appear in all copies. The
/// software is provided "as is" without warranty of any kind.
public final class ConfettiSystem {

    public let container = CALayer()

    private struct Particle {
        var x: CGFloat
        var y: CGFloat
        var angle2D: CGFloat
        var velocity: CGFloat
        var wobble: CGFloat
        var wobbleSpeed: CGFloat
        var tiltAngle: CGFloat
        var tick: CGFloat
        var totalTicks: CGFloat
        var scalar: CGFloat
        var gravity: CGFloat
        var decay: CGFloat
        let layer: CALayer
    }

    private var particles: [Particle] = []

    public var isActive: Bool { !particles.isEmpty }

    /// canvas-confetti's default palette.
    private static let palette = ["#26CCFF", "#A25AFD", "#FF5E7E", "#88FF5A",
                                  "#FCFF42", "#FFA62D", "#FF36FF"]

    public init() {}

    /// The "basic" burst: a cone fired upward from the origin.
    /// Angle is measured like canvas-confetti (90 = straight up).
    public func burst(at origin: CGPoint,
                      count: Int = 60,
                      angleDegrees: CGFloat = 90,
                      spreadDegrees: CGFloat = 55,
                      startVelocity: CGFloat = 34) {
        for _ in 0..<count {
            let spread = (spreadDegrees * .pi / 180)
            // y grows downward here, same as canvas 2D, so up is -sin.
            let angle2D = -(angleDegrees * .pi / 180)
                + CGFloat.random(in: -0.5...0.5) * spread
            let scalar = CGFloat.random(in: 0.7...1.1)

            let layer = CALayer()
            let isCircle = Bool.random()
            let side = 7.5 * scalar
            layer.bounds = CGRect(x: 0, y: 0, width: side, height: side * (isCircle ? 1 : 1.35))
            layer.backgroundColor = NSColor(hex: Self.palette.randomElement()!).cgColor
            layer.cornerRadius = isCircle ? layer.bounds.width / 2 : 1.5
            layer.position = origin
            container.addSublayer(layer)

            particles.append(Particle(
                x: origin.x, y: origin.y,
                angle2D: angle2D,
                velocity: startVelocity * CGFloat.random(in: 0.55...1.15),
                wobble: CGFloat.random(in: 0...(2 * .pi)),
                // canvas-confetti advances wobble by 0.05–0.11 rad per 60fps
                // tick — slow. Anything faster reads as jitter, not flutter.
                wobbleSpeed: min(0.11, CGFloat.random(in: 0.05...0.15)),
                tiltAngle: CGFloat.random(in: 0...(2 * .pi)),
                tick: 0,
                totalTicks: 200,
                scalar: scalar,
                gravity: 3,
                decay: 0.9,
                layer: layer))
        }
    }

    /// Advance by one display frame. `frameDt` is wall-clock seconds; physics
    /// constants are canvas-confetti's per-60fps-tick values.
    public func step(frameDt: CGFloat) {
        guard !particles.isEmpty else { return }
        let k = min(frameDt * 60, 3)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var survivors: [Particle] = []
        survivors.reserveCapacity(particles.count)
        for var p in particles {
            p.x += cos(p.angle2D) * p.velocity * k
            p.y += sin(p.angle2D) * p.velocity * k + p.gravity * k
            p.velocity *= pow(p.decay, k)
            p.wobble += p.wobbleSpeed * k
            p.tiltAngle += 0.1 * k
            p.tick += k

            let progress = p.tick / p.totalTicks
            if progress >= 1 || p.y > container.bounds.height + 40 {
                p.layer.removeFromSuperlayer()
                continue
            }

            let wobbleX = p.x + 10 * p.scalar * cos(p.wobble)
            p.layer.position = CGPoint(x: wobbleX, y: p.y)
            // Tilt + flutter: rotate in-plane, squash gently on a fake axis.
            var t = CATransform3DMakeRotation(p.tiltAngle, 0, 0, 1)
            let flutter = 0.45 + 0.55 * abs(sin(p.wobble))
            t = CATransform3DScale(t, 1, flutter, 1)
            p.layer.transform = t
            p.layer.opacity = Float(1 - progress)
            survivors.append(p)
        }
        particles = survivors
        CATransaction.commit()
    }

    public func removeAll() {
        particles.forEach { $0.layer.removeFromSuperlayer() }
        particles.removeAll()
    }
}
