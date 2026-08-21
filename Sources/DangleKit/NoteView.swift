import AppKit
import QuartzCore

/// A note beneath the charm: real macOS vibrancy, serif for the words,
/// a monogram for the author, and a quiet counter.
public final class NoteView: NSView {

    private let effect = NSVisualEffectView()
    private let quoteField = NSTextField(wrappingLabelWithString: "")
    private let monogram = CATextLayer()
    private let monogramBacking = CAGradientLayer()
    private let fromField = NSTextField(labelWithString: "")
    private let counterField = NSTextField(labelWithString: "")

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

        monogramBacking.cornerRadius = 11
        monogramBacking.startPoint = CGPoint(x: 0, y: 0)
        monogramBacking.endPoint = CGPoint(x: 1, y: 1)
        monogram.fontSize = 10
        monogram.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        monogram.foregroundColor = NSColor.white.cgColor
        monogram.alignmentMode = .center
        monogram.contentsScale = 2
        effect.layer?.addSublayer(monogramBacking)
        effect.layer?.addSublayer(monogram)

        fromField.font = .systemFont(ofSize: 12, weight: .medium)
        fromField.textColor = NSColor.white.withAlphaComponent(0.62)
        effect.addSubview(fromField)

        counterField.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        counterField.textColor = NSColor.white.withAlphaComponent(0.34)
        effect.addSubview(counterField)

        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Lays out the note for the given content and returns its size.
    @discardableResult
    public func configure(note: DanglePack.Note, accent: NSColor,
                          gradient: [NSColor], counter: String?) -> CGSize {
        quoteField.stringValue = "\u{201C}\(note.text)\u{201D}"
        fromField.stringValue = note.from
        counterField.stringValue = counter ?? ""
        monogram.string = String(note.from.prefix(1)).uppercased()
        monogramBacking.colors = (gradient.count >= 2 ? gradient : [accent, accent])
            .map(\.cgColor)

        let pad = Self.pad
        let quoteSize = quoteField.sizeThatFits(
            NSSize(width: Self.maxTextWidth, height: 500))
        let fromSize = fromField.intrinsicContentSize
        let width = max(quoteSize.width, fromSize.width + 30 + 80) + pad * 2
        let height = quoteSize.height + 10 + 22 + pad * 2

        let size = CGSize(width: ceil(width), height: ceil(height))
        setFrameSize(size)
        effect.frame = bounds
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius,
                                   cornerHeight: Self.cornerRadius, transform: nil)

        quoteField.frame = NSRect(x: pad, y: pad,
                                  width: Self.maxTextWidth, height: quoteSize.height)
        let rowY = pad + quoteSize.height + 10
        monogramBacking.frame = CGRect(x: pad, y: rowY, width: 22, height: 22)
        monogram.frame = CGRect(x: pad, y: rowY + 4.5, width: 22, height: 13)
        fromField.frame = NSRect(x: pad + 30, y: rowY + 3,
                                 width: fromSize.width + 4, height: fromSize.height)
        let counterSize = counterField.intrinsicContentSize
        counterField.frame = NSRect(x: size.width - pad - counterSize.width,
                                    y: rowY + 5, width: counterSize.width,
                                    height: counterSize.height)
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
