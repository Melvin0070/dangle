import AppKit
import QuartzCore

/// The hanging object: a glass gradient tile with a glyph, or a bare emoji.
/// Pivots at the thread loop just above its top edge, and tilts in pseudo-3D
/// with its swing velocity.
public final class CharmLayer: CALayer {

    public static let loopGap: CGFloat = 6

    private let gradient = CAGradientLayer()
    private let shade = CAGradientLayer()
    private let specular = CAGradientLayer()
    private let glyphLayer = CALayer()
    private var isGlass = true
    private var side: CGFloat = 96

    /// Distance from the rope end (the loop) to the charm's visual center.
    /// Static because callers need it for 3D charms too, which are not
    /// CharmLayers and have their own measured height.
    public static func hangOffset(forHeight height: CGFloat) -> CGFloat {
        loopGap + height / 2
    }

    public convenience init(pack: DanglePack) {
        self.init()
        configure(pack: pack)
    }

    public func configure(pack: DanglePack) {
        side = pack.charmSize
        isGlass = pack.charm.kind != .emoji
        sublayers?.forEach { $0.removeFromSuperlayer() }
        removeAllAnimations()

        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        // Pivot at the loop, slightly above the top edge.
        anchorPoint = CGPoint(x: 0.5, y: -Self.loopGap / side)

        if isGlass {
            configureGlass(pack: pack)
        } else {
            configureEmoji(pack: pack)
        }
    }

    private func configureGlass(pack: DanglePack) {
        let radius = side * 0.27
        let colors = pack.gradientColors

        gradient.frame = bounds
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = radius
        gradient.masksToBounds = true
        gradient.borderWidth = 1
        gradient.borderColor = NSColor.white.withAlphaComponent(0.34).cgColor
        addSublayer(gradient)

        // Slow drift: rotate the gradient stops through the palette forever.
        let shifted = Array(colors.dropFirst()) + [colors[0]]
        let drift = CABasicAnimation(keyPath: "colors")
        drift.fromValue = colors.map(\.cgColor)
        drift.toValue = shifted.map(\.cgColor)
        drift.duration = 4.5
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(drift, forKey: "drift")

        // Depth: darker pool toward the bottom.
        shade.frame = bounds
        shade.colors = [NSColor.clear.cgColor,
                        NSColor.black.withAlphaComponent(0.30).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.45)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        shade.cornerRadius = radius
        shade.masksToBounds = true
        addSublayer(shade)

        // Specular: the top light that sells the glass.
        specular.frame = CGRect(x: side * 0.10, y: side * 0.05,
                                width: side * 0.80, height: side * 0.36)
        specular.colors = [NSColor.white.withAlphaComponent(0.42).cgColor,
                           NSColor.white.withAlphaComponent(0).cgColor]
        specular.startPoint = CGPoint(x: 0.5, y: 0)
        specular.endPoint = CGPoint(x: 0.5, y: 1)
        specular.cornerRadius = side * 0.18
        addSublayer(specular)

        if let glyph = Rendering.glyphImage(pack.charm.glyph, fontSize: side * 0.35,
                                            monospaced: true, shadowed: true) {
            placeGlyph(glyph)
        }

        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.5
        shadowRadius = 14
        shadowOffset = CGSize(width: 0, height: 8)
        shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius,
                            cornerHeight: radius, transform: nil)
    }

    private func configureEmoji(pack: DanglePack) {
        if let glyph = Rendering.glyphImage(pack.charm.glyph, fontSize: side * 0.72,
                                            monospaced: false, shadowed: false) {
            placeGlyph(glyph)
        }
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.35
        shadowRadius = 8
        shadowOffset = CGSize(width: 0, height: 5)
        shadowPath = nil
    }

    private func placeGlyph(_ image: CGImage) {
        let w = CGFloat(image.width) / 2
        let h = CGFloat(image.height) / 2
        glyphLayer.contents = image
        glyphLayer.contentsScale = 2
        glyphLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        glyphLayer.position = CGPoint(x: side / 2, y: side / 2)
        addSublayer(glyphLayer)
    }

    /// Swing rotation about the loop plus a velocity-driven pseudo-3D tilt.
    public func orient(angle: CGFloat, tiltY: CGFloat, tiltX: CGFloat) {
        var t = CATransform3DIdentity
        t.m34 = -1.0 / 450.0
        // Flipped (y-down) geometry: positive z-rotation reads clockwise, so
        // the charm needs -angle to lean the way the rope does.
        t = CATransform3DRotate(t, -angle, 0, 0, 1)
        t = CATransform3DRotate(t, tiltY, 0, 1, 0)
        t = CATransform3DRotate(t, tiltX, 1, 0, 0)
        transform = t
    }

    /// The tiny twin bead that sits halfway up the thread. Emoji charms get
    /// no bead at all — a miniature copy of an arbitrary emoji reads as
    /// clutter rather than a charm detail.
    public static func bead(pack: DanglePack) -> CALayer {
        let bead = CALayer()
        if pack.charm.kind == .emoji {
            return bead
        }
        if pack.charm.kind == .glyph3d {
            // A little chrome ball, same metal as the glyph.
            let s: CGFloat = 11
            let ball = CAGradientLayer()
            ball.type = .radial
            ball.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            ball.colors = [NSColor.white.withAlphaComponent(0.95).cgColor,
                           NSColor(hex: "#B9B9C4").cgColor,
                           NSColor(hex: "#4A4A55").cgColor]
            ball.locations = [0, 0.35, 1]
            ball.startPoint = CGPoint(x: 0.35, y: 0.3)
            ball.endPoint = CGPoint(x: 1.1, y: 1.1)
            ball.cornerRadius = s / 2
            ball.shadowColor = NSColor.black.cgColor
            ball.shadowOpacity = 0.45
            ball.shadowRadius = 3
            ball.shadowOffset = CGSize(width: 0, height: 2)
            return ball
        }
        let s: CGFloat = 14
        let gradient = CAGradientLayer()
        gradient.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        gradient.colors = pack.gradientColors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = 5
        gradient.borderWidth = 1
        gradient.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        gradient.position = .zero
        return gradient
    }
}
