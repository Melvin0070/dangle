# Changelog

## 0.2.0

- **Breaking:** notes are text only. Removed the author field and rotation
  counter from the note card, `pack.json`'s `notes` array is now plain
  strings instead of `{text, from}` objects, and `dangle://note?text=…`
  drops the `&from=` parameter.
- Catalog charms can carry their own notes (`Charm.notes`); Heart and
  Four-Leaf Clover each speak for themselves. Falls back to the pack's notes
  when a charm has none, or when the pack charm is active.
- Charm rendering no longer steps down after 1-2 idle seconds: the charm
  stays at full rate (120Hz physics, live SceneKit) for as long as it's on
  screen. Idle CPU rose from ~1.3% to ~12% of one core in exchange; still 0%
  once dismissed. The old throttle path is still in the code as a one-line
  revert for anyone who wants it back.
- Fixed a cold-launch crash: opening a `dangle://` URL before the app had
  ever launched hit a nil window.
- CharmStore hardening: atomic writes, HTTP status checks, catalog id
  validation, and reentrancy guard on **Get New Charms…**.

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
  full pause when dismissed (superseded in 0.2.0 — see above)
- Universal (arm64 + x86_64) release builds
