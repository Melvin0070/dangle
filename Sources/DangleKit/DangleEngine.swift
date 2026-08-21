import AppKit
import QuartzCore

/// Owns the rope, the overlay window, the layer tree, and the display link.
/// This is the whole runtime: packs feed it content, the app shell feeds it
/// commands (summon, dismiss, ritual).
public final class DangleEngine: NSObject {

    public private(set) var pack: DanglePack
    private var packBaseURL: URL?

    private let rope: VerletRope
    private var window: DangleWindow!
    private var view: DangleView!
    private var screen: NSScreen!

    private let backThread = CAShapeLayer()
    private let threadGradient = CAGradientLayer()
    private let threadMask = CAShapeLayer()
    private let threadSheen = CAShapeLayer()
    private let loopLayer = CAShapeLayer()
    private var beadLayer = CALayer()
    private let charm = CharmLayer()
    private var charm3D: Charm3DView?
    private let confetti = ConfettiSystem()
    private let noteView = NoteView()

    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var accumulator: CGFloat = 0
    private var elapsed: CGFloat = 0
    private var prevPts: [VerletRope.Point] = []
    private var tiltY: CGFloat = 0
    private var tiltX: CGFloat = 0
    private var activityLevel: CGFloat = 0
    private var charmActiveNow = false
    private var idlePhase: CGFloat = 0
    private var mouseNearCharm = false
    private var linkIsFast = true
    private var charm3DSleeping = false
    private let charm3DSnapshot = CALayer()

    /// Swap the live SceneKit view for a bitmap of its last frame.
    private func sleepCharm3D(_ v: Charm3DView) {
        charm3DSleeping = true
        let size = v.frame.size
        charm3DSnapshot.contents = v.snapshot()
        charm3DSnapshot.contentsScale = view.window?.backingScaleFactor ?? 2
        charm3DSnapshot.bounds = CGRect(origin: .zero, size: size)
        charm3DSnapshot.position = CGPoint(x: v.frame.midX, y: v.frame.midY)
        view.layer?.addSublayer(charm3DSnapshot)
        v.setLive(false)
        v.removeFromSuperview()
    }

    /// Bring the live view back; the bitmap lingers a beat to cover the
    /// first re-render.
    private func wakeCharm3D(_ v: Charm3DView) {
        charm3DSleeping = false
        view.addSubview(v, positioned: .below, relativeTo: noteView)
        v.setLive(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.charm3DSleeping else { return }
            self.charm3DSnapshot.removeFromSuperlayer()
        }
    }

    private func setLinkRate(active: Bool) {
        guard let link = displayLink, active != linkIsFast else { return }
        linkIsFast = active
        link.preferredFrameRateRange = active
            ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            : CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
    }

    private var dragMoved: CGFloat = 0
    private var lastDragPoint: CGPoint = .zero
    private var mouseInteractive = false

    private var noteHideTimer: Timer?
    private var noteIntervalTimer: Timer?
    private var noteVisible = false

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let anchorX = "dangle.anchorX"
        static let dangled = "dangle.dangled"
        static let noteIndex = "dangle.noteIndex"
        static let behind = "dangle.behindWindows"
        static let autoNotes = "dangle.autoNotes"
        static let charmID = "dangle.charmID"
    }

    public var isDangled: Bool { rope.dangled }
    public var isBehindWindows: Bool { defaults.bool(forKey: Keys.behind) }
    public var autoNotesEnabled: Bool {
        get {
            if let stored = defaults.object(forKey: Keys.autoNotes) as? Bool { return stored }
            return (pack.noteIntervalMinutes ?? 0) > 0
        }
        set { defaults.set(newValue, forKey: Keys.autoNotes); scheduleIntervalNotes() }
    }

    /// The pack with any user charm override applied. Overrides are stored as
    /// a single id: "emoji:🍀" hangs a bare emoji, anything else names an
    /// installed charm from the CharmStore. Cached because the render loop
    /// reads it every frame; recomputed whenever the pack or override change.
    public private(set) lazy var effectivePack: DanglePack = resolveEffectivePack()
    public var charmOverrideID: String? { defaults.string(forKey: Keys.charmID) }

    private func resolveEffectivePack() -> DanglePack {
        var p = pack
        guard let id = defaults.string(forKey: Keys.charmID) else { return p }
        if id.hasPrefix("emoji:") {
            p.charm.kind = "emoji"
            p.charm.glyph = String(id.dropFirst("emoji:".count))
            p.charm.size = 72
            p.charm.menuGlyph = nil
        } else if let charm = CharmStore.shared.charm(id: id) {
            p.charm = charm.charm
        }
        return p
    }

    public override init() {
        let resolved = DanglePack.resolve()
        pack = resolved.pack
        packBaseURL = resolved.baseURL
        rope = VerletRope()
        super.init()
    }

    // MARK: Setup

    public func start() {
        setUpWindow()
        setUpLayers()
        restoreState()
        setUpDisplayLink()
        startWatchdog()
        scheduleIntervalNotes()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Nonactivating panels can drop out of the window order on Space
        // switches; re-assert so the charm lives on every Space.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // The view's display link auto-suspends when the screen sleeps or
        // locks and does not reliably resume; rebuild it on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(rebuildDisplayLink),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(rebuildDisplayLink),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func spaceChanged() {
        ensureRunning()
    }

    /// The view-based display link can start (or wake) suspended if it is
    /// created before the window is composited. A cheap watchdog notices
    /// "should be running, but no ticks" and rebuilds it.
    private var watchdog: Timer?
    private var tickCount: UInt64 = 0

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let shouldRun = !(self.displayLink?.isPaused ?? true)
            let stalled = CACurrentMediaTime() - self.lastTick > 1.5
            if shouldRun && stalled {
                self.rebuildDisplayLink()
            }
        }
    }

    @objc private func rebuildDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        setUpDisplayLink()
        ensureRunning()
    }

    /// Re-assert the window and revive the loop — safe to call any time.
    private func ensureRunning() {
        window.orderFrontRegardless()
        if rope.dangled || noteVisible || confetti.isActive {
            displayLink?.isPaused = false
            lastTick = CACurrentMediaTime()
        }
    }

    private var stripHeight: CGFloat { 580 }

    private func setUpWindow() {
        screen = NSScreen.screens.first ?? NSScreen.main
        let f = screen.frame
        let frame = NSRect(x: f.minX, y: f.maxY - stripHeight,
                           width: f.width, height: stripHeight)
        window = DangleWindow(frame: frame)
        view = DangleView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view

        view.onMouseDown = { [weak self] p in self?.beginDrag(at: p) }
        view.onMouseDragged = { [weak self] p in self?.continueDrag(at: p) }
        view.onMouseUp = { [weak self] p in self?.endDrag(at: p) }

        rope.minAnchorX = 90
        rope.maxAnchorX = f.width - 90
        window.setBehindWindows(isBehindWindows)
        window.orderFrontRegardless()
    }

    private func setUpLayers() {
        guard let root = view.layer else { return }
        let p = effectivePack

        // The cord is a tapered ribbon, not a constant stroke: a dark
        // under-ribbon for edge and depth, the gradient body on top, and a
        // hairline sheen down the center so it reads as a round cord.
        backThread.fillColor = NSColor.black.withAlphaComponent(0.38).cgColor
        backThread.strokeColor = nil

        threadGradient.frame = view.bounds
        threadMask.fillColor = NSColor.black.cgColor
        threadMask.strokeColor = nil
        threadGradient.mask = threadMask

        threadSheen.fillColor = nil
        threadSheen.strokeColor = NSColor.white.withAlphaComponent(0.30).cgColor
        threadSheen.lineWidth = 0.9
        threadSheen.lineCap = .round

        loopLayer.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
        loopLayer.path = CGPath(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 8, height: 8),
                                transform: nil)
        loopLayer.fillColor = nil
        loopLayer.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor
        loopLayer.lineWidth = 2.5

        confetti.container.frame = view.bounds

        root.addSublayer(backThread)
        root.addSublayer(threadGradient)
        root.addSublayer(threadSheen)
        root.addSublayer(beadLayer)
        root.addSublayer(loopLayer)
        root.addSublayer(confetti.container)
        root.addSublayer(charm)
        view.addSubview(noteView)

        applyCharmStyle(p)
    }

    private var uses3D = false
    private var threadTopWidth: CGFloat = 4.2
    private var threadBottomWidth: CGFloat = 1.9

    /// What the hanging charm actually occupies, which is only a square for
    /// the 2D kinds. Never smaller than the charm size, so a charm stays as
    /// easy to grab as it has always been however tight its glyph is.
    private var charmExtents = CGSize(width: 96, height: 96)

    private func applyCharmStyle(_ p: DanglePack) {
        uses3D = p.charm.kind == "glyph3d"
        threadTopWidth = CGFloat(p.thread.width) + 1.2
        threadBottomWidth = max(1.6, CGFloat(p.thread.width) * 0.62)
        charm3D?.removeFromSuperview()
        charm3D = nil
        charm3DSnapshot.removeFromSuperlayer()
        charm3DSleeping = false
        charm.removeFromSuperlayer()
        if uses3D {
            let v = Charm3DView(pack: p)
            view.addSubview(v, positioned: .below, relativeTo: noteView)
            charm3D = v
            charmExtents = CGSize(width: max(v.metrics.width, p.charmSize),
                                  height: max(v.metrics.height, p.charmSize))
        } else {
            view.layer?.addSublayer(charm)
            charm.configure(pack: p)
            charmExtents = CGSize(width: p.charmSize, height: p.charmSize)
        }
        rope.hangOffset = CharmLayer.loopGap + charmExtents.height / 2
        rope.charmRadius = max(40, max(charmExtents.width, charmExtents.height) * 0.8)

        let threadColor = NSColor(hex: p.thread.colorHex)
        threadGradient.colors = [threadColor.withAlphaComponent(0.58).cgColor,
                                 threadColor.withAlphaComponent(0.24).cgColor]
        threadGradient.startPoint = CGPoint(x: 0.5, y: 0)
        threadGradient.endPoint = CGPoint(x: 0.5, y: 0.6)

        // The 3D charm carries its own chrome ring at the pivot; the flat
        // loop is only for the 2D charm kinds.
        loopLayer.isHidden = uses3D

        beadLayer.removeFromSuperlayer()
        beadLayer = CharmLayer.bead(pack: p)
        view.layer?.insertSublayer(beadLayer, above: threadSheen)
    }

    private func restoreState() {
        let saved = defaults.double(forKey: Keys.anchorX)
        let defaultX = screen.frame.width * 0.72
        rope.anchorX = saved > 0
            ? min(max(CGFloat(saved), rope.minAnchorX), rope.maxAnchorX)
            : defaultX
        let wasDangled = defaults.object(forKey: Keys.dangled) as? Bool ?? true
        if wasDangled {
            rope.setDangled(true)
        }
    }

    private func setUpDisplayLink() {
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        linkIsFast = true
        lastTick = CACurrentMediaTime()
    }

    @objc private func screensChanged() {
        guard let newScreen = NSScreen.screens.first else { return }
        screen = newScreen
        let f = screen.frame
        window.setFrame(NSRect(x: f.minX, y: f.maxY - stripHeight,
                               width: f.width, height: stripHeight), display: true)
        view.frame = NSRect(origin: .zero, size: window.frame.size)
        threadGradient.frame = view.bounds
        confetti.container.frame = view.bounds
        rope.maxAnchorX = f.width - 90
        rope.anchorX = min(max(rope.anchorX, rope.minAnchorX), rope.maxAnchorX)
    }

    // MARK: Commands

    public func summon(withNote: Bool = true) {
        // Even when already dangling, a summon revives a suspended loop —
        // the escape hatch if the system ever freezes the overlay.
        ensureRunning()
        guard !rope.dangled else { return }
        rope.setDangled(true)
        defaults.set(true, forKey: Keys.dangled)
        displayLink?.isPaused = false
        lastTick = CACurrentMediaTime()
        if withNote {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.rope.dangled else { return }
                self.showNextNote()
            }
        }
    }

    public func dismiss() {
        guard rope.dangled else { return }
        rope.setDangled(false)
        defaults.set(false, forKey: Keys.dangled)
        hideNote()
    }

    public func toggle() {
        rope.dangled ? dismiss() : summon()
    }

    /// The ritual, kept simple: one confetti blast from behind the charm.
    public func bless() {
        let wasHidden = !rope.dangled
        if wasHidden { summon(withNote: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasHidden ? 0.85 : 0)) { [weak self] in
            guard let self else { return }
            let center = self.rope.charmCenter
            self.confetti.burst(at: center)
            self.displayLink?.isPaused = false
            self.playBlessSound()
        }
    }

    /// dangle://debug — dump loop state for diagnostics.
    public func dumpDebug() {
        let s = """
        dangled=\(rope.dangled) paused=\(displayLink?.isPaused ?? true)
        linkFast=\(linkIsFast) charmActive=\(charmActiveNow)
        activityLevel=\(activityLevel) mouseNearCharm=\(mouseNearCharm)
        noteVisible=\(noteVisible) confetti=\(confetti.isActive)
        anchorX=\(rope.anchorX) charm=\(effectivePack.charm.kind)/\(effectivePack.charm.glyph)
        ticks=\(tickCount)
        """
        try? s.write(toFile: "/tmp/dangle-debug.txt", atomically: true, encoding: .utf8)
    }

    public func setBehindWindows(_ behind: Bool) {
        defaults.set(behind, forKey: Keys.behind)
        window.setBehindWindows(behind)
    }

    public func reloadPack() {
        let resolved = DanglePack.resolve()
        pack = resolved.pack
        packBaseURL = resolved.baseURL
        effectivePack = resolveEffectivePack()
        applyCharmStyle(effectivePack)
        scheduleIntervalNotes()
    }

    /// Hang an installed charm by id, or an emoji via "emoji:🍀".
    /// Unknown ids are ignored rather than persisted as a dead override.
    public func setCharmOverride(id: String) {
        guard id.hasPrefix("emoji:") || CharmStore.shared.charm(id: id) != nil else {
            return
        }
        switchCharm {
            self.defaults.set(id, forKey: Keys.charmID)
            self.effectivePack = self.resolveEffectivePack()
            self.applyCharmStyle(self.effectivePack)
        }
    }

    public func clearCharmOverride() {
        switchCharm {
            self.defaults.removeObject(forKey: Keys.charmID)
            self.effectivePack = self.resolveEffectivePack()
            self.applyCharmStyle(self.effectivePack)
        }
    }

    /// VerletRope's private dip (0.18s) plus lift (0.3s) reach `isFullyHidden`
    /// in ~0.48s; the extra margin covers frame jitter so the old charm is
    /// reliably off screen before the new one applies.
    private static let charmSwitchDelay: TimeInterval = 0.65
    private var pendingCharmSwitch: DispatchWorkItem?
    private var charmSwitchInFlight = false

    /// A charm change reads as the old one leaving and the new one
    /// arriving, not an instant swap mid-air: put away first if currently
    /// dangling, apply the change, then drop back in. Picking again before
    /// that finishes re-times the drop from the newer choice instead of
    /// letting the stale one apply and re-summon over it.
    private func switchCharm(_ apply: @escaping () -> Void) {
        let wasVisible = rope.dangled || charmSwitchInFlight
        pendingCharmSwitch?.cancel()
        guard wasVisible else {
            apply()
            return
        }
        charmSwitchInFlight = true
        dismiss()  // no-op if a prior pick already dismissed it
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.charmSwitchInFlight = false
            apply()
            self.summon(withNote: false)
        }
        pendingCharmSwitch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.charmSwitchDelay, execute: work)
    }

    // MARK: Notes

    /// Shown for any hand-picked emoji, which has no notes of its own —
    /// generic enough to fit whatever was picked, not tied to the pack.
    private static let genericEmojiNotes = [
        "However you got here, hi.",
        "Whatever this means to you, it's yours now.",
        "Give it a flick.",
        "Some days just need something hanging from the top of the screen.",
        "You picked this one. That's reason enough.",
    ]

    /// The charm's own notes take over while it hangs; a hand-picked emoji
    /// gets the generic set; otherwise the pack's.
    private var activeNotes: [String] {
        guard let id = charmOverrideID else { return pack.notes }
        if id.hasPrefix("emoji:") { return Self.genericEmojiNotes }
        if let notes = CharmStore.shared.charm(id: id)?.notes, !notes.isEmpty {
            return notes
        }
        return pack.notes
    }

    public func showNextNote() {
        let notes = activeNotes
        guard !notes.isEmpty else { return }
        // Asked for a note while hidden? Drop in first, then speak — and only
        // advance the rotation when the note will actually be seen.
        guard rope.dangled else {
            summon(withNote: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.rope.dangled else { return }
                self.showNextNote()
            }
            return
        }
        let index = defaults.integer(forKey: Keys.noteIndex) % notes.count
        defaults.set(index + 1, forKey: Keys.noteIndex)
        show(text: notes[index])
    }

    /// A note from outside the pack — dangle://note?text=…
    public func showCustomNote(text: String) {
        if !rope.dangled { summon(withNote: false) }
        let delay: Double = rope.dangled ? 0 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.show(text: text)
        }
    }

    private func show(text: String) {
        guard rope.dangled else { return }
        noteHideTimer?.invalidate()
        noteVisible = true

        let size = noteView.configure(text: text)
        let top = rope.tuning.hangY + rope.restLength + CharmLayer.loopGap
            + charmExtents.height + 18
        let x = min(max(rope.anchorX, size.width / 2 + 12),
                    screen.frame.width - size.width / 2 - 12)
        noteView.setFrameOrigin(NSPoint(x: x - size.width / 2, y: top))
        noteView.present()

        noteHideTimer = Timer.scheduledTimer(withTimeInterval: max(pack.noteSeconds, 2),
                                             repeats: false) { [weak self] _ in
            self?.hideNote()
        }
    }

    private func hideNote() {
        guard noteVisible else { return }
        noteVisible = false
        noteHideTimer?.invalidate()
        noteView.dismiss()
    }

    private func scheduleIntervalNotes() {
        noteIntervalTimer?.invalidate()
        guard autoNotesEnabled, let minutes = pack.noteIntervalMinutes, minutes > 0 else { return }
        noteIntervalTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60,
                                                 repeats: true) { [weak self] _ in
            guard let self, self.rope.dangled else { return }
            self.showNextNote()
        }
    }

    private func playBlessSound() {
        guard let rel = pack.blessSoundPath, let base = packBaseURL else { return }
        NSSound(contentsOf: base.appendingPathComponent(rel), byReference: true)?.play()
    }

    // MARK: Simulation loop

    @objc private func tick(_ link: CADisplayLink) {
        tickCount += 1
        let now = CACurrentMediaTime()
        var frame = CGFloat(now - lastTick)
        lastTick = now
        frame = min(frame, 1.0 / 15.0)
        accumulator += frame
        elapsed += frame

        updateMouse()
        var steps = 0
        while accumulator >= VerletRope.dt && steps < 8 {
            prevPts = rope.pts
            rope.step()
            accumulator -= VerletRope.dt
            steps += 1
        }
        render()
        idlePhase += frame
        confetti.step(frameDt: frame)

        // Power-saving idle throttle (30Hz + frame-skipped 3D) traded away
        // for always-smooth motion: CPU is cheap, a stutter after 1-2 idle
        // seconds is not. Re-enable with `setLinkRate(active: charmActiveNow
        // || mouseNearCharm)` if idle CPU needs trimming later.
        setLinkRate(active: true)

        // Fully retracted and quiet: stop burning frames until summoned.
        if rope.isFullyHidden && !noteVisible && !confetti.isActive {
            displayLink?.isPaused = true
        }
    }

    private func simMouseLocation() -> CGPoint {
        let g = NSEvent.mouseLocation
        return CGPoint(x: g.x - screen.frame.minX, y: screen.frame.maxY - g.y)
    }

    private func updateMouse() {
        let p = simMouseLocation()
        let inStrip = p.y >= 0 && p.y <= stripHeight
        rope.mouse = inStrip ? p : nil

        // Distance-to-charm for the dumpDebug diagnostic only — rendering
        // runs at full rate regardless (see tick()'s setLinkRate call).
        if inStrip, rope.dangled {
            let c = rope.charmCenter
            mouseNearCharm = hypot(p.x - c.x, p.y - c.y) < 260
        } else {
            mouseNearCharm = false
        }

        let interactive = rope.dragging || (inStrip && rope.dangled && hitTestCharm(p))
        if interactive != mouseInteractive {
            mouseInteractive = interactive
            window.ignoresMouseEvents = !interactive
        }
    }

    private func hitTestCharm(_ p: CGPoint) -> Bool {
        let angle = rope.endAngle
        let e = rope.end
        let dx = p.x - e.x
        let dy = p.y - e.y
        let ca = cos(angle), sa = sin(angle)
        let localX = dx * ca - dy * sa
        let localY = dx * sa + dy * ca
        let pad: CGFloat = 8
        return abs(localX) <= charmExtents.width / 2 + pad
            && localY >= -pad
            && localY <= CharmLayer.loopGap + charmExtents.height + pad
    }

    private func beginDrag(at p: CGPoint) {
        guard rope.dangled, hitTestCharm(p) else { return }
        rope.dragging = true
        rope.dragTo(p)
        dragMoved = 0
        lastDragPoint = p
    }

    private func continueDrag(at p: CGPoint) {
        guard rope.dragging else { return }
        rope.dragTo(p)
        dragMoved += hypot(p.x - lastDragPoint.x, p.y - lastDragPoint.y)
        lastDragPoint = p
    }

    private func endDrag(at p: CGPoint) {
        guard rope.dragging else { return }
        rope.dragging = false
        rope.dragTarget = nil
        defaults.set(Double(rope.anchorX), forKey: Keys.anchorX)
        if dragMoved < 6 {
            // A click, not a drag: fidget and say something kind.
            rope.flick()
            showNextNote()
        }
    }

    // MARK: Rendering

    private struct RenderPoint { var x: CGFloat; var y: CGFloat }

    private func render() {
        // Blend between the last two physics states so motion stays smooth
        // at any display refresh rate.
        let curr = rope.pts
        let prev = prevPts.count == curr.count ? prevPts : curr
        let alpha = min(max(accumulator / VerletRope.dt, 0), 1)
        var pts = [RenderPoint]()
        pts.reserveCapacity(curr.count)
        for i in 0..<curr.count {
            pts.append(RenderPoint(x: prev[i].x + (curr[i].x - prev[i].x) * alpha,
                                   y: prev[i].y + (curr[i].y - prev[i].y) * alpha))
        }
        let m = pts.count
        let end = pts[m - 1]
        let beforeEnd = pts[m - 2]
        let angle = atan2(end.x - beforeEnd.x, end.y - beforeEnd.y)

        // Velocity-driven pseudo-3D tilt, smoothed so it breathes.
        let vel = rope.endVelocity
        tiltY += (min(max(vel.x * 0.05, -0.5), 0.5) - tiltY) * 0.12
        tiltX += (min(max(-vel.y * 0.025, -0.22), 0.22) - tiltX) * 0.12

        // Kept only for the dumpDebug diagnostic; no longer gates rendering.
        let speed = hypot(vel.x, vel.y)
        activityLevel = max(speed, activityLevel * 0.96)
        charmActiveNow = rope.dragging || confetti.isActive || activityLevel > 0.3

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // One round of Chaikin turns the 12-point polyline into a smooth
        // spine for the tapered ribbon.
        var spine = [RenderPoint]()
        spine.reserveCapacity(m * 2)
        spine.append(pts[0])
        for i in 0..<(m - 1) {
            let a = pts[i], b = pts[i + 1]
            spine.append(RenderPoint(x: a.x * 0.75 + b.x * 0.25,
                                     y: a.y * 0.75 + b.y * 0.25))
            spine.append(RenderPoint(x: a.x * 0.25 + b.x * 0.75,
                                     y: a.y * 0.25 + b.y * 0.75))
        }
        spine.append(pts[m - 1])

        backThread.path = ribbonPath(spine, topWidth: threadTopWidth + 1.6,
                                     bottomWidth: threadBottomWidth + 1.6)
        threadMask.path = ribbonPath(spine, topWidth: threadTopWidth,
                                     bottomWidth: threadBottomWidth)
        let sheen = CGMutablePath()
        sheen.move(to: CGPoint(x: spine[0].x, y: spine[0].y))
        for p in spine.dropFirst() {
            sheen.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        threadSheen.path = sheen

        // Twin bead halfway up the thread.
        let bi = CGFloat(m - 1) * 0.5
        let i0 = Int(bi), f = bi - CGFloat(i0)
        let bx = pts[i0].x + (pts[i0 + 1].x - pts[i0].x) * f
        let by = pts[i0].y + (pts[i0 + 1].y - pts[i0].y) * f
        let beadAngle = atan2(pts[i0 + 1].x - pts[i0].x, pts[i0 + 1].y - pts[i0].y)
        beadLayer.position = CGPoint(x: bx, y: by)
        beadLayer.transform = CATransform3DMakeRotation(-beadAngle, 0, 0, 1)

        if let charm3D {
            // SceneKit burns ~6% CPU merely existing in the window, paused or
            // not, so it still sleeps to a bitmap once fully off-screen — but
            // stays live for the entire time it's visible, including the
            // idle breeze, so nothing ever steps down to a lower rate while
            // dangling.
            let wantLive = !rope.isFullyHidden
            if wantLive && charm3DSleeping {
                wakeCharm3D(charm3D)
            } else if !wantLive && !charm3DSleeping {
                sleepCharm3D(charm3D)
            }
            if !charm3DSleeping {
                let s = charm3D.viewSide
                // The glyph pivot sits at the view's center; park it on
                // the rope end so the chrome ring meets the ribbon.
                charm3D.setFrameOrigin(NSPoint(x: end.x - s / 2, y: end.y - s / 2))
                charm3D.orient(swing: angle, tiltY: tiltY, tiltX: tiltX, idle: idlePhase)
            } else {
                // Keep the parked bitmap on the rope end; sub-pixel breeze
                // drift skips the move.
                if abs(end.x - charm3DSnapshot.position.x) > 0.35
                    || abs(end.y - charm3DSnapshot.position.y) > 0.35 {
                    charm3DSnapshot.position = CGPoint(x: end.x, y: end.y)
                }
            }
        } else {
            loopLayer.position = CGPoint(x: end.x, y: end.y)
            charm.position = CGPoint(x: end.x, y: end.y)
            charm.orient(angle: angle, tiltY: tiltY, tiltX: tiltX)
        }

        CATransaction.commit()
    }

    /// A closed, tapered ribbon around the spine: offset each point along its
    /// normal by half the local width, out one side and back the other.
    private func ribbonPath(_ spine: [RenderPoint], topWidth: CGFloat,
                            bottomWidth: CGFloat) -> CGPath {
        let n = spine.count
        var left = [CGPoint](); left.reserveCapacity(n)
        var right = [CGPoint](); right.reserveCapacity(n)
        for i in 0..<n {
            let prev = spine[max(i - 1, 0)]
            let next = spine[min(i + 1, n - 1)]
            let tx = next.x - prev.x
            let ty = next.y - prev.y
            let len = max(hypot(tx, ty), 1e-4)
            let nx = -ty / len
            let ny = tx / len
            let t = CGFloat(i) / CGFloat(n - 1)
            let half = (topWidth + (bottomWidth - topWidth) * t) / 2
            left.append(CGPoint(x: spine[i].x + nx * half, y: spine[i].y + ny * half))
            right.append(CGPoint(x: spine[i].x - nx * half, y: spine[i].y - ny * half))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}
