# Changelog

## 0.1.0

Initial release.

- 12-point verlet rope at a fixed 120Hz with render interpolation, idle
  wind, cursor repulsion, drag, flick, stretch, and edge bounce
- Extruded 3D `</>` charm (SceneKit, PBR chrome, gradient reflections, HDR
  bloom) with 2D glass-tile and emoji charm kinds
- Charm catalog: new charms install from the repository via
  **Charm → Get New Charms…**, no app update needed
- Packs: one JSON file for charm, thread, notes, hotkeys, and timings, with
  live reload and `make gift` for personalized builds
- Notes with native vibrancy, monograms, and a rotation counter
- Bless ritual: canvas-confetti-style burst via ⌃⌥B or `dangle://bless`
- `dangle://` URL scheme for scripting
- Global hotkeys (Carbon, no accessibility permission), behind-windows mode,
  launch at login
- Idle CPU ~1% of one core: 30Hz quiet loop, SceneKit sleep-to-bitmap,
  full pause when dismissed
