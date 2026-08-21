import AppKit
import SceneKit

/// A real 3D charm: the glyph extruded in SceneKit with chamfered edges and
/// a dark glassy PBR material, lit by a generated gradient environment so the
/// rim catches the pack's colors. No background — just the floating shape.
public enum Charm3D {

    /// Scene units are points (orthographic camera), so layout math matches
    /// the 2D engine exactly.
    public static func makeScene(pack: DanglePack, viewSide: CGFloat)
        -> (scene: SCNScene, glyphNode: SCNNode) {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = viewSide / 2
        camera.zNear = 1
        camera.zFar = 400
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomThreshold = 0.85
        camera.bloomIntensity = 0.7
        camera.bloomBlurRadius = 8
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 160)
        scene.rootNode.addChildNode(cameraNode)

        // Reflections carry the color: a dark studio strip with the pack's
        // gradient as the key band.
        if let env = environmentMap(colors: pack.gradientColors) {
            scene.lightingEnvironment.contents = env
            scene.lightingEnvironment.intensity = 2.0
        }
        let key = SCNLight()
        key.type = .directional
        key.intensity = 750
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-CGFloat.pi / 4, CGFloat.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = NSColor(hex: "#DDE2FF")
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(CGFloat.pi / 8, -CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(fillNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 160
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let size = pack.charmSize
        let geometry: SCNGeometry
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = 0.2
        material.diffuse.contents = NSColor(hex: "#9A9AA6")

        switch pack.charm.glyph {
        case "</>", "code":
            // A bespoke chunky </> beats any typeface in 3D.
            let shape = SCNShape(path: codeGlyphPath(size: size), extrusionDepth: 16)
            shape.chamferRadius = 2.6
            geometry = shape
        case "heart":
            let shape = SCNShape(path: heartPath(size: size), extrusionDepth: 15)
            shape.chamferRadius = 2.8
            geometry = shape
            material.diffuse.contents = NSColor(hex: "#C81E3C")
            material.metalness.contents = 0.9
            material.roughness.contents = 0.22
        case "clover":
            let shape = SCNShape(path: cloverPath(size: size), extrusionDepth: 13)
            shape.chamferRadius = 2.4
            geometry = shape
            material.diffuse.contents = NSColor(hex: "#2F9E44")
            material.metalness.contents = 0.85
            material.roughness.contents = 0.28
        default:
            let text = SCNText(string: pack.charm.glyph, extrusionDepth: 15)
            text.font = NSFont.monospacedSystemFont(ofSize: size, weight: .black)
            text.flatness = 0.05
            text.chamferRadius = 2.2
            geometry = text
        }
        geometry.materials = [material]

        let glyphNode = SCNNode(geometry: geometry)
        let (minB, maxB) = glyphNode.boundingBox
        let bbW = maxB.x - minB.x
        let bbH = maxB.y - minB.y
        let scale = (size * 0.82) / bbH
        glyphNode.scale = SCNVector3(scale, scale, scale)
        // Pivot at the thread loop: top-center of the glyph, loopGap above it.
        let pivotX = minB.x + bbW / 2
        let pivotY = maxB.y + CharmLayer.loopGap / scale
        let pivotZ = (minB.z + maxB.z) / 2
        glyphNode.pivot = SCNMatrix4MakeTranslation(pivotX, pivotY, pivotZ)
        // Pivot at the CENTER of the view, so no overswing can ever clip
        // against the view's own bounds.
        glyphNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(glyphNode)

        // The link the thread ties to: a small chrome ring at the pivot,
        // riding the glyph so the connection never separates.
        let torus = SCNTorus(ringRadius: 5.4 / scale, pipeRadius: 1.7 / scale)
        torus.ringSegmentCount = 48
        torus.pipeSegmentCount = 24
        torus.materials = [material]
        let ringNode = SCNNode(geometry: torus)
        // SCNTorus lies in the xz plane; face it toward the camera.
        ringNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        ringNode.position = SCNVector3(pivotX, pivotY, pivotZ)
        glyphNode.addChildNode(ringNode)

        return (scene, glyphNode)
    }

    /// The </> built from rounded capsules — two arms per chevron overlapping
    /// at the apex, plus the slash — so the 3D shape is chunky and soft-edged,
    /// not typeset.
    static func codeGlyphPath(size s: CGFloat) -> NSBezierPath {
        let combined = CGMutablePath()
        func addCapsule(from a: CGPoint, to b: CGPoint, width t: CGFloat) {
            let len = hypot(b.x - a.x, b.y - a.y)
            let rect = CGRect(x: -t / 2, y: -t / 2, width: len + t, height: t)
            let capsule = CGPath(roundedRect: rect, cornerWidth: t / 2,
                                 cornerHeight: t / 2, transform: nil)
            var tf = CGAffineTransform(translationX: a.x, y: a.y)
                .rotated(by: atan2(b.y - a.y, b.x - a.x))
            if let placed = capsule.copy(using: &tf) {
                combined.addPath(placed)
            }
        }
        // Proportions: the slash runs taller than the chevrons (the classic
        // code-mark silhouette) and keeps clear air on both sides — its edge
        // never touches the chevron apexes. chevH:chevW controls the chevron
        // angle — a smaller ratio reads as a narrower, more pointed V.
        let chevH = s * 0.20
        let chevW = s * 0.28
        let thick = s * 0.15
        let lx = -0.43 * s
        addCapsule(from: CGPoint(x: lx - chevW / 2, y: 0),
                   to: CGPoint(x: lx + chevW / 2, y: chevH), width: thick)
        addCapsule(from: CGPoint(x: lx - chevW / 2, y: 0),
                   to: CGPoint(x: lx + chevW / 2, y: -chevH), width: thick)
        let rx = 0.43 * s
        addCapsule(from: CGPoint(x: rx + chevW / 2, y: 0),
                   to: CGPoint(x: rx - chevW / 2, y: chevH), width: thick)
        addCapsule(from: CGPoint(x: rx + chevW / 2, y: 0),
                   to: CGPoint(x: rx - chevW / 2, y: -chevH), width: thick)
        addCapsule(from: CGPoint(x: 0.115 * s, y: chevH * 1.4),
                   to: CGPoint(x: -0.115 * s, y: -chevH * 1.4), width: thick * 0.88)
        let bezier = NSBezierPath(cgPath: combined)
        bezier.flatness = 0.05
        return bezier
    }

    /// A lacquer heart: one closed bezier, tip down, lobes up.
    static func heartCurve(size s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -0.45 * s))
        p.addCurve(to: CGPoint(x: 0.30 * s, y: 0.26 * s),
                   control1: CGPoint(x: 0.38 * s, y: -0.15 * s),
                   control2: CGPoint(x: 0.48 * s, y: 0.08 * s))
        p.addCurve(to: CGPoint(x: 0, y: 0.18 * s),
                   control1: CGPoint(x: 0.16 * s, y: 0.40 * s),
                   control2: CGPoint(x: 0.02 * s, y: 0.32 * s))
        p.addCurve(to: CGPoint(x: -0.30 * s, y: 0.26 * s),
                   control1: CGPoint(x: -0.02 * s, y: 0.32 * s),
                   control2: CGPoint(x: -0.16 * s, y: 0.40 * s))
        p.addCurve(to: CGPoint(x: 0, y: -0.45 * s),
                   control1: CGPoint(x: -0.48 * s, y: 0.08 * s),
                   control2: CGPoint(x: -0.38 * s, y: -0.15 * s))
        p.closeSubpath()
        return p
    }

    static func heartPath(size s: CGFloat) -> NSBezierPath {
        let bezier = NSBezierPath(cgPath: heartCurve(size: s))
        bezier.flatness = 0.05
        return bezier
    }

    /// Four-leaf clover: four heart-shaped leaves, tips meeting at the
    /// center. No stem — at charm scale a stem short enough not to look
    /// like a stray nub reads as nothing at all, so the leaves stand alone.
    static func cloverPath(size s: CGFloat) -> NSBezierPath {
        let combined = CGMutablePath()
        let leaf = heartCurve(size: s * 0.52)
        for k in 0..<4 {
            // Slide each heart outward so its tip rests at the center, then
            // fan the four copies onto the diagonals.
            let angle = CGFloat(k) * .pi / 2 + .pi / 4
            var tf = CGAffineTransform(rotationAngle: angle)
                .translatedBy(x: 0, y: 0.30 * s)
            if let placed = leaf.copy(using: &tf) {
                combined.addPath(placed)
            }
        }
        let bezier = NSBezierPath(cgPath: combined)
        bezier.flatness = 0.05
        return bezier
    }

    /// A fake studio: dark, with the pack gradient as a horizontal light band
    /// and a white streak up top. Enough for stylized PBR reflections.
    static func environmentMap(colors: [NSColor]) -> CGImage? {
        let size = CGSize(width: 512, height: 256)
        return Rendering.rasterize(size: size, scale: 1, draw: { ctx in
            // Bright sky above, dark floor below, so faces shade with angle.
            if let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: [NSColor(hex: "#C2C5D2").cgColor,
                                             NSColor(hex: "#5A5A66").cgColor,
                                             NSColor(hex: "#26262E").cgColor] as CFArray,
                                    locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(sky,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 0, y: size.height),
                                       options: [])
            }

            let band = colors.map { $0.cgColor } as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: band, locations: nil) {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 88, width: size.width, height: 100))
                ctx.drawLinearGradient(grad,
                                       start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: size.width, y: 0),
                                       options: [])
                ctx.restoreGState()
            }
            // Studio strips: a bright key overhead and a soft kicker below.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 40, y: 18, width: 260, height: 34))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            ctx.fill(CGRect(x: 320, y: 196, width: 150, height: 24))
        })
    }
}

/// SCNView that never intercepts the mouse — the engine owns interaction.
public final class Charm3DView: SCNView {

    public private(set) var glyphNode: SCNNode?
    public let viewSide: CGFloat

    public init(pack: DanglePack) {
        // Big enough that a full 360° swing about the centered pivot stays
        // inside the view — the glyph's reach is ~0.95× charm size.
        viewSide = pack.charmSize * 2.15
        super.init(frame: NSRect(x: 0, y: 0, width: viewSide, height: viewSide),
                   options: nil)
        let built = Charm3D.makeScene(pack: pack, viewSide: viewSide)
        scene = built.scene
        glyphNode = built.glyphNode
        backgroundColor = .clear
        antialiasingMode = .multisampling2X
        allowsCameraControl = false
        rendersContinuously = false
        isPlaying = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    private var live = true

    /// SceneKit keeps its internal render loop firing even with
    /// rendersContinuously off, fully re-rendering every vsync. Hard-pause
    /// it whenever the charm is quiet; CA keeps compositing the last frame.
    public func setLive(_ wantLive: Bool) {
        guard wantLive != live else { return }
        live = wantLive
        if wantLive { play(nil) } else { pause(nil) }
    }

    private var lastEuler = SCNVector3(99, 99, 99)

    /// Swing about the loop (z), 3D turn from velocity + idle drift (y, x).
    public func orient(swing: CGFloat, tiltY: CGFloat, tiltX: CGFloat, idle: CGFloat) {
        // Screen-plane: swinging right (positive angle) is counterclockwise
        // on screen, which is +z in SceneKit's y-up view space.
        let euler = SCNVector3(tiltX, 0.34 * sin(idle * 0.5) + tiltY, swing)
        // Below ~0.17° of change nothing is visible — skip the scene write so
        // SceneKit doesn't re-render. Cuts idle-sway GPU/CPU work to a crawl
        // while keeping full frame rate the moment the charm really moves.
        let delta = max(abs(euler.x - lastEuler.x),
                        max(abs(euler.y - lastEuler.y), abs(euler.z - lastEuler.z)))
        guard delta > 0.003 else { return }
        lastEuler = euler
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        glyphNode?.eulerAngles = euler
        SCNTransaction.commit()
    }
}
