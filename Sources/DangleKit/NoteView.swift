import AppKit
import QuartzCore

/// A note beneath the charm: real macOS vibrancy, serif for the words.
/// Text only — no author, no counter.
public final class NoteView: NSView {

    private let effect = NSVisualEffectView()
    private let quoteField = NSTextField(wrappingLabelWithString: "")

    private static let maxTextWidth: CGFloat = 300
    private static let pad: CGFloat = 18
    private static let cornerRadius: CGFloat = 16

    public override var isFlipped: Bool { true }
    // Notes are display-only; clicks fall through to the engine's view.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: 8)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        addSubview(effect)

        quoteField.font = Rendering.serifFont(size: 15.5, italic: true)
        quoteField.textColor = NSColor.white.withAlphaComponent(0.92)
        quoteField.preferredMaxLayoutWidth = Self.maxTextWidth
        effect.addSubview(quoteField)

        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Lays out the note for the given text and returns its size.
    @discardableResult
    public func configure(text: String) -> CGSize {
        quoteField.stringValue = "\u{201C}\(text)\u{201D}"

        let pad = Self.pad
        let quoteSize = quoteField.sizeThatFits(
            NSSize(width: Self.maxTextWidth, height: 500))
        let size = CGSize(width: ceil(quoteSize.width) + pad * 2,
                          height: ceil(quoteSize.height) + pad * 2)
        setFrameSize(size)
        effect.frame = bounds
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius,
                                   cornerHeight: Self.cornerRadius, transform: nil)

        quoteField.frame = NSRect(x: pad, y: pad,
                                  width: Self.maxTextWidth, height: quoteSize.height)
        return size
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius,
                                       bottom: radius, right: radius)
        return image
    }

    public func present() {
        isHidden = false
        let tilt = CGFloat.random(in: -0.012...0.012)
        layer?.setAffineTransform(CGAffineTransform(rotationAngle: tilt))

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        let drop = CABasicAnimation(keyPath: "position.y")
        drop.fromValue = (layer?.position.y ?? 0) - 12
        drop.toValue = layer?.position.y ?? 0
        drop.duration = 0.45
        drop.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer?.add(drop, forKey: "drop")
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.965
        scale.toValue = 1
        scale.duration = 0.45
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer?.add(scale, forKey: "pop")
    }

    public func dismiss(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
            completion?()
        })
    }
}
