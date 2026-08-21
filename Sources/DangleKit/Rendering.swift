import AppKit
import CoreGraphics

/// Small rasterization helpers shared by the charm layers and the snapshot tool.
public enum Rendering {

    public static func rasterize(size: CGSize, scale: CGFloat = 2,
                                 draw: (CGContext) -> Void) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Flip to a top-left origin so layout reads like the design.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// The charm glyph rendered crisp, with a soft shadow for glass kinds.
    public static func glyphImage(_ glyph: String, fontSize: CGFloat,
                                  monospaced: Bool, shadowed: Bool) -> CGImage? {
        let font: NSFont = monospaced
            ? .monospacedSystemFont(ofSize: fontSize, weight: .semibold)
            : .systemFont(ofSize: fontSize)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: monospaced ? -1.0 : 0,
        ]
        if shadowed {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 6
            attrs[.shadow] = shadow
        }
        let s = NSAttributedString(string: glyph, attributes: attrs)
        let bounds = s.size()
        let pad: CGFloat = 12
        let size = CGSize(width: ceil(bounds.width) + pad * 2,
                          height: ceil(bounds.height) + pad * 2)
        return rasterize(size: size, draw: { _ in
            s.draw(at: NSPoint(x: pad, y: pad))
        })
    }

    /// Note card as a bitmap — used only by the snapshot tool; the app itself
    /// shows notes as live vibrancy views.
    public static func noteImage(_ text: String) -> (image: CGImage, size: CGSize)? {
        let maxTextWidth: CGFloat = 300
        let pad: CGFloat = 18

        let quoteFont = serifFont(size: 15.5, italic: true)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let quote = NSAttributedString(
            string: "\u{201C}\(text)\u{201D}",
            attributes: [.font: quoteFont,
                         .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                         .paragraphStyle: para])

        let textRect = quote.boundingRect(with: NSSize(width: maxTextWidth, height: 500),
                                          options: [.usesLineFragmentOrigin])
        let size = CGSize(width: ceil(textRect.width) + pad * 2,
                          height: ceil(textRect.height) + pad * 2)

        guard let image = rasterize(size: size, draw: { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path = CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.12, blue: 0.15, alpha: 0.95).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                               cornerWidth: 15.5, cornerHeight: 15.5, transform: nil))
            ctx.strokePath()

            quote.draw(with: NSRect(x: pad, y: pad, width: maxTextWidth, height: textRect.height),
                       options: [.usesLineFragmentOrigin])
        }) else { return nil }
        return (image, size)
    }

    public static func serifFont(size: CGFloat, italic: Bool) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
            .withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
}
