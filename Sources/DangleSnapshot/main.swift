import AppKit
import SceneKit
import Metal
import DangleKit

// Renders a pack's charm, a note, and a mid-swing physics scene to PNGs.
// Used for pack previews in the README and for eyeballing changes without
// launching the app. Usage: dangle-snapshot [pack.json] [output-dir]

let args = CommandLine.arguments

// --svg <glyph>: print a built-in shape as SVG path data and exit. A charm
// can carry that string as `pathData` instead of naming a glyph, so this is
// how you take one of the bundled shapes as a starting point for your own.
if let flagIndex = args.firstIndex(of: "--svg") {
    guard args.count > flagIndex + 1 else {
        fatalError("--svg needs a glyph name, e.g. --svg clover")
    }
    let name = args[flagIndex + 1]
    var probe = DanglePack.fallback
    probe.charm.glyph = name
    probe.charm.pathData = nil
    probe.charm.size = 96
    guard Charm3D.bespokeGlyphs.contains(name) else {
        fatalError("no bespoke shape named \"\(name)\"; try one of "
            + Charm3D.bespokeGlyphs.sorted().joined(separator: ", "))
    }
    print(SVGPath.string(from: Charm3D.bespokePath(named: name, size: 96).cgPath))
    exit(0)
}

// --icon <out.png> [pack.json]: render the app icon (Big Sur rounded square,
// the 3D charm mid-turn) and exit. Used once per charm change: make icon.
if let flagIndex = args.firstIndex(of: "--icon") {
    let out = URL(fileURLWithPath: args.count > flagIndex + 1
        ? args[flagIndex + 1] : "AppIcon.png")
    guard let device = MTLCreateSystemDefaultDevice() else {
        fatalError("--icon needs Metal")
    }
    let canvas: CGFloat = 1024
    // Big Sur icon grid: an 824pt rounded square centered on a 1024 canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185

    var iconPack = DanglePack.fallback
    if args.count > flagIndex + 2 {
        iconPack = try DanglePack.load(from: URL(fileURLWithPath: args[flagIndex + 2]))
    }
    iconPack.charm.size = 430
    let renderer = SCNRenderer(device: device, options: nil)
    let built = Charm3D.makeScene(pack: iconPack, viewSide: 1024)
    built.glyphNode.eulerAngles = SCNVector3(0.10, 0.42, 0.10)
    // Center the glyph body: its pivot is the thread loop above the shape.
    built.glyphNode.position = SCNVector3(
        0, built.metrics.height / 2 + CharmLayer.loopGap, 0)
    // No thread in the icon, so no ring either.
    built.glyphNode.childNodes.forEach { $0.isHidden = true }
    renderer.scene = built.scene
    let charmShot = renderer.snapshot(atTime: 0,
                                      with: CGSize(width: canvas, height: canvas),
                                      antialiasingMode: .multisampling4X)

    guard let image = Rendering.rasterize(size: CGSize(width: canvas, height: canvas),
                                          scale: 1, draw: { ctx in
        let path = CGPath(roundedRect: plate, cornerWidth: radius,
                          cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        if let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [NSColor(hex: "#1B1B26").cgColor,
                                        NSColor(hex: "#0B0B12").cgColor] as CFArray,
                               locations: [0, 1]) {
            ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: canvas), options: [])
        }
        if let cg = charmShot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // rasterize() flips to top-left origin; un-flip for the bitmap.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: canvas)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
            ctx.restoreGState()
        }
    }) else { fatalError("icon render failed") }

    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try png.write(to: out)
    print("wrote \(out.path)")
    exit(0)
}

let packURL = args.count > 1 ? URL(fileURLWithPath: args[1]) : nil
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "snapshots")

let pack: DanglePack
if let packURL, let loaded = try? DanglePack.load(from: packURL) {
    pack = loaded
} else {
    pack = .fallback
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func write(_ image: CGImage, to name: String) {
    let url = outDir.appendingPathComponent(name)
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(name)")
    }
    do {
        try data.write(to: url)
    } catch {
        fatalError("could not write \(url.path): \(error.localizedDescription)")
    }
    print("wrote \(url.path)")
}

// Draws the charm tile in plain CG — a static approximation of the live
// layer tree (no gradient drift, no tilt), close enough to judge the look.
func drawCharm(_ ctx: CGContext, at center: CGPoint, angle: CGFloat) {
    let side = pack.charmSize
    let radius = side * 0.27
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    // In a y-up context, +angle aligns the charm's hang axis with the rope.
    ctx.rotate(by: angle)

    let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
    if pack.charm.kind == "glass" {
        let path = CGPath(roundedRect: rect, cornerWidth: radius,
                          cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let colors = pack.gradientColors.map(\.cgColor) as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: colors, locations: nil) {
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
        }
        // Specular top light.
        if let spec = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [NSColor.white.withAlphaComponent(0.4).cgColor,
                                          NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: nil) {
            ctx.drawLinearGradient(spec,
                                   start: CGPoint(x: 0, y: rect.maxY),
                                   end: CGPoint(x: 0, y: rect.maxY - side * 0.4),
                                   options: [])
        }
        ctx.resetClip()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.34).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()
    }
    let glyphScale: CGFloat = switch pack.charm.kind {
    case "emoji": 0.72
    case "glass": 0.35
    default: 0.8
    }
    if let glyph = Rendering.glyphImage(pack.charm.glyph,
                                        fontSize: side * glyphScale,
                                        monospaced: pack.charm.kind != "emoji",
                                        shadowed: pack.charm.kind != "emoji") {
        let w = CGFloat(glyph.width) / 2, h = CGFloat(glyph.height) / 2
        ctx.draw(glyph, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
    ctx.restoreGState()
}

// 1. The charm at rest.
let charmCard = CGSize(width: 220, height: 220)
if let image = Rendering.rasterize(size: charmCard, draw: { ctx in
    ctx.setFillColor(NSColor(srgbRed: 0.055, green: 0.055, blue: 0.08, alpha: 1).cgColor)
    ctx.fill(CGRect(origin: .zero, size: charmCard))
    // rasterize() hands us a flipped (y-down) context; drawCharm's rotation
    // convention assumes y-up, so angle 0 here keeps it upright either way.
    drawCharm(ctx, at: CGPoint(x: 110, y: 110), angle: 0)
}) {
    write(image, to: "charm.png")
}

// 1b. The real 3D charm, rendered offscreen with SceneKit, mid-swing.
if pack.charm.kind == "glyph3d", let device = MTLCreateSystemDefaultDevice() {
    let renderer = SCNRenderer(device: device, options: nil)
    let built = Charm3D.makeScene(pack: pack)
    built.scene.background.contents = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.08, alpha: 1)
    built.glyphNode.eulerAngles = SCNVector3(0.08, 0.55, 0.3)
    // Center the glyph body; its pivot is the thread loop above the shape.
    built.glyphNode.position = SCNVector3(
        0, built.metrics.height / 2 + CharmLayer.loopGap, 0)
    renderer.scene = built.scene
    let side = built.metrics.viewSide * 2
    let image = renderer.snapshot(atTime: 0,
                                  with: CGSize(width: side, height: side),
                                  antialiasingMode: .multisampling4X)
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        write(cg, to: "charm3d.png")
    }
}

// 2. A note.
if let first = pack.notes.first, let note = Rendering.noteImage(first) {
    write(note.image, to: "note.png")
}

// 3. A mid-swing scene: flick the rope, run a few steps, draw thread + charm.
let sceneSize = CGSize(width: 480, height: 460)
let rope = VerletRope(random: { 0.7 })
rope.hangOffset = CharmLayer.loopGap + pack.charmSize / 2
rope.anchorX = sceneSize.width / 2
rope.settleInstantly()
rope.flick()
for _ in 0..<30 { rope.step() }

let scale: CGFloat = 2
let w = Int(sceneSize.width * scale), h = Int(sceneSize.height * scale)
guard let ctx = CGContext(data: nil, width: w, height: h,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("no context") }
ctx.scaleBy(x: scale, y: scale)

// y-up context; sim is y-down. Convert as we draw.
let H = sceneSize.height
func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }

ctx.setFillColor(NSColor(srgbRed: 0.055, green: 0.055, blue: 0.08, alpha: 1).cgColor)
ctx.fill(CGRect(origin: .zero, size: sceneSize))

let pts = rope.pts.map { up(CGPoint(x: $0.x, y: $0.y)) }
let path = CGMutablePath()
path.move(to: pts[0])
for i in 1..<(pts.count - 1) {
    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
    path.addQuadCurve(to: mid, control: pts[i])
}
path.addLine(to: pts[pts.count - 1])
ctx.addPath(path)
ctx.setStrokeColor(NSColor(hex: pack.thread.colorHex).withAlphaComponent(0.3).cgColor)
ctx.setLineWidth(CGFloat(pack.thread.width))
ctx.setLineCap(.round)
ctx.strokePath()

// Twin bead halfway up.
let bead = up(rope.interpolated(0.5).point)
ctx.setFillColor(NSColor(hex: pack.charm.accentHex).cgColor)
ctx.fillEllipse(in: CGRect(x: bead.x - 6, y: bead.y - 6, width: 12, height: 12))

let center = up(rope.charmCenter)
drawCharm(ctx, at: center, angle: rope.endAngle)

if let scene = ctx.makeImage() {
    write(scene, to: "scene.png")
}
print("endAngle after flick+30 steps: \(rope.endAngle)")

// Physics diagnostics: --windstats prints idle-breeze endpoint speeds so
// activity thresholds can be set from data, not guesses.
if args.contains("--windstats") {
    let r = VerletRope(random: { 0.5 })
    r.anchorX = 400
    r.settleInstantly()
    for _ in 0..<(120 * 20) { r.step() }  // settle any transient
    var maxS: CGFloat = 0, sum: CGFloat = 0
    let n = 120 * 20
    for _ in 0..<n {
        r.step()
        let v = r.endVelocity
        let s = hypot(v.x, v.y)
        maxS = max(maxS, s)
        sum += s
    }
    print(String(format: "idle wind end speed px/step: max %.3f mean %.3f", maxS, sum / CGFloat(n)))
}
