import AppKit
import SceneKit

/// A real 3D charm: the glyph extruded in SceneKit with chamfered edges and
/// a dark glassy PBR material, lit by a generated gradient environment so the
/// rim catches the pack's colors. No background — just the floating shape.
public enum Charm3D {

    /// How big the charm actually came out, and the view that has to hold it.
    public struct Metrics: Equatable {
        /// The glyph's rendered extents in points, after fitting.
        public let width: CGFloat
        public let height: CGFloat
        /// Side of the square view a full 360° swing about the loop needs.
        public let viewSide: CGFloat
    }

    /// A shape built in code rather than shipped as `pathData`. Anything a
    /// pack names that is not one of these is extruded as type, which only
    /// reads for one or two characters — a longer string is almost always a
    /// shape nobody built, hung as the literal word instead.
    ///
    /// One case per shape, owning its names, its geometry and its finish, so
    /// adding a shape is one case and the compiler finds the rest. Most new
    /// shapes should be `pathData` in a charm file and need nothing here.
    public enum BespokeGlyph: CaseIterable, Sendable {
        case code
        case heart
        case clover

        /// Every name a pack may use for this shape.
        public var names: [String] {
            switch self {
            case .code: ["</>", "code"]
            case .heart: ["heart"]
            case .clover: ["clover"]
            }
        }

        public init?(name: String) {
            guard let match = Self.allCases.first(where: { $0.names.contains(name) })
            else { return nil }
            self = match
        }

        /// Every name any bespoke shape answers to.
        public static var allNames: Set<String> {
            Set(allCases.flatMap(\.names))
        }

        func path(size: CGFloat) -> NSBezierPath {
            switch self {
            case .code: codeGlyphPath(size: size)
            case .heart: heartPath(size: size)
            case .clover: cloverPath(size: size)
            }
        }

        var extrusion: (depth: CGFloat, chamfer: CGFloat) {
            switch self {
            case .code: (16, 2.6)
            case .heart: (15, 2.8)
            case .clover: (13, 2.4)
            }
        }

        /// A shape that wants its own colour instead of the default chrome.
        var lacquer: (hex: String, metalness: Double, roughness: Double)? {
            switch self {
            case .code: nil
            case .heart: ("#C81E3C", 0.9, 0.22)
            case .clover: ("#2F9E44", 0.85, 0.28)
            }
        }
    }

    /// The path behind a bespoke glyph name, so tooling can export one as a
    /// starting point for a charm's own `pathData`. Empty for anything else.
    public static func bespokePath(named glyph: String, size: CGFloat) -> NSBezierPath {
        BespokeGlyph(name: glyph)?.path(size: size) ?? NSBezierPath()
    }

    /// Fits a glyph of the given bounding box to the charm size, and works
    /// out the view its swing needs. Pure math on purpose: the aspect-ratio
    /// rules are the easiest thing here to get wrong and the hardest to see.
    public static func fit(bbW: CGFloat, bbH: CGFloat, size: CGFloat,
                           fixedSide: CGFloat? = nil) -> (scale: CGFloat, metrics: Metrics) {
        // Height sets the scale, so square-ish charms come out exactly as
        // they always have. The width cap is what lets a wide shape hang at
        // all: fitted on height alone, a 3:1 glyph ends up wider than the
        // view it swings in, and a stray glyph name extruded as a whole word
        // ends up wider still.
        let scale = min((size * 0.82) / max(bbH, 0.001),
                        (size * 1.90) / max(bbW, 0.001))
        let width = bbW * scale
        let height = bbH * scale
        // A full swing about the loop sweeps a circle of this radius. Sizing
        // the view from the glyph — rather than from a fixed multiple of the
        // charm size — is what makes any aspect ratio safe to hang.
        let reach = hypot(width / 2, height + CharmLayer.loopGap)
        return (scale, Metrics(width: width, height: height,
                               viewSide: fixedSide ?? (reach + 8) * 2))
    }

    /// Scene units are points (orthographic camera), so layout math matches
    /// the 2D engine exactly. `fixedSide` pins the view for offscreen
    /// renders; live charms size the view to their own swing.
    public static func makeScene(pack: DanglePack, viewSide fixedSide: CGFloat? = nil)
        -> (scene: SCNScene, glyphNode: SCNNode, metrics: Metrics) {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let (glyphNode, metrics) = makeGlyph(pack: pack, fixedSide: fixedSide)
        scene.rootNode.addChildNode(glyphNode)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = metrics.viewSide / 2
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

        return (scene, glyphNode, metrics)
    }

    /// The extruded glyph itself, fitted to the pack's charm size and pivoted
    /// at its thread loop, plus the chrome ring the thread ties to.
    private static func makeGlyph(pack: DanglePack, fixedSide: CGFloat?)
        -> (SCNNode, Metrics) {
        let size = pack.charmSize
        let geometry: SCNGeometry
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.metalness.contents = 1.0
        material.roughness.contents = 0.2
        material.diffuse.contents = NSColor(hex: "#9A9AA6")

        if let d = pack.charm.pathData {
            // A shape that arrived as data rather than as a case in this
            // file. Normalizing resolves the overlapping subpaths design
            // tools emit; SceneKit's tessellator cannot, and fills rings
            // solid when handed them raw.
            let rule: CGPathFillRule = (pack.charm.pathEvenOdd ?? false) ? .evenOdd : .winding
            if let parsed = try? SVGPath.path(from: d) {
                let shape = SCNShape(path: NSBezierPath(cgPath: parsed.normalized(using: rule)),
                                     extrusionDepth: CGFloat(pack.charm.depth ?? 13))
                shape.chamferRadius = CGFloat(pack.charm.chamfer ?? 2.4)
                geometry = shape
            } else {
                // Bad path data is not worth crashing over, and not worth
                // hiding either: hang the fallback so the charm reads as
                // visibly wrong rather than quietly missing.
                let fallback = BespokeGlyph.code
                let shape = SCNShape(path: fallback.path(size: size),
                                     extrusionDepth: fallback.extrusion.depth)
                shape.chamferRadius = fallback.extrusion.chamfer
                geometry = shape
            }
            applyMaterialOverrides(pack.charm, to: material)
            return finish(geometry: geometry, material: material,
                          size: size, fixedSide: fixedSide)
        }

        if let bespoke = BespokeGlyph(name: pack.charm.glyph) {
            // Built-in geometry beats any typeface in 3D. The shape's own
            // depth, chamfer and finish are defaults, not fixtures: a charm
            // that states them wins, exactly as it does for `pathData`.
            let shape = SCNShape(
                path: bespoke.path(size: size),
                extrusionDepth: CGFloat(pack.charm.depth ?? Double(bespoke.extrusion.depth)))
            shape.chamferRadius = CGFloat(pack.charm.chamfer ?? Double(bespoke.extrusion.chamfer))
            geometry = shape
            if let lacquer = bespoke.lacquer {
                material.diffuse.contents = NSColor(hex: lacquer.hex)
                material.metalness.contents = lacquer.metalness
                material.roughness.contents = lacquer.roughness
            }
            applyMaterialOverrides(pack.charm, to: material)
        } else {
            let text = SCNText(string: pack.charm.glyph, extrusionDepth: 15)
            text.font = NSFont.monospacedSystemFont(ofSize: size, weight: .black)
            text.flatness = 0.05
            text.chamferRadius = 2.2
            geometry = text
        }
        return finish(geometry: geometry, material: material,
                      size: size, fixedSide: fixedSide)
    }

    /// Per-charm material overrides, so a charm that arrived as data can pick
    /// its own colour and finish without a case in this file.
    private static func applyMaterialOverrides(_ spec: DanglePack.CharmSpec,
                                               to material: SCNMaterial) {
        if let hex = spec.fillHex { material.diffuse.contents = NSColor(hex: hex) }
        if let metalness = spec.metalness { material.metalness.contents = metalness }
        if let roughness = spec.roughness { material.roughness.contents = roughness }
    }

    /// Everything downstream of the shape itself: fit it, pivot it at the
    /// thread loop, and hang the ring the thread ties to.
    private static func finish(geometry: SCNGeometry, material: SCNMaterial,
                               size: CGFloat, fixedSide: CGFloat?) -> (SCNNode, Metrics) {
        geometry.materials = [material]

        let glyphNode = SCNNode(geometry: geometry)
        let (minB, maxB) = glyphNode.boundingBox
        let bbW = maxB.x - minB.x
        let bbH = maxB.y - minB.y
        let (scale, metrics) = fit(bbW: bbW, bbH: bbH, size: size, fixedSide: fixedSide)
        glyphNode.scale = SCNVector3(scale, scale, scale)
        // Pivot at the thread loop: top-center of the glyph, loopGap above it.
        let pivotX = minB.x + bbW / 2
        let pivotY = maxB.y + CharmLayer.loopGap / scale
        let pivotZ = (minB.z + maxB.z) / 2
        glyphNode.pivot = SCNMatrix4MakeTranslation(pivotX, pivotY, pivotZ)
        // Pivot at the CENTER of the view, so no overswing can ever clip
        // against the view's own bounds.
        glyphNode.position = SCNVector3(0, 0, 0)

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

        return (glyphNode, metrics)
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
        // angle — a smaller ratio reads as a narrower, more pointed V. The
        // slash's reach is set independently of chevH so it stays long
        // regardless of how narrow the chevrons get.
        let chevH = s * 0.16
        let chevW = s * 0.34
        let thick = s * 0.125
        let slashHalf = s * 0.34
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
        addCapsule(from: CGPoint(x: 0.115 * s, y: slashHalf),
                   to: CGPoint(x: -0.115 * s, y: -slashHalf), width: thick * 0.88)
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
    public let metrics: Charm3D.Metrics
    public var viewSide: CGFloat { metrics.viewSide }

    public init(pack: DanglePack) {
        // The scene sizes its own view around the glyph's swing, whatever
        // shape the glyph turned out to be.
        let built = Charm3D.makeScene(pack: pack)
        metrics = built.metrics
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: built.metrics.viewSide,
                                 height: built.metrics.viewSide),
                   options: nil)
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
