# Changelog

## Unreleased

- A `pathData` charm is now covered by a test that it still extrudes from
  its path rather than silently degrading to its glyph name as text —
  including the negative case, so the assertion cannot pass vacuously.
- The two Application Support locations a user owns are pinned by a test.
  That is a change-detector, not a mechanism: it exists to stop a rename
  going in unnoticed, and moving either path still needs a migration
  written at the time.
- `CharmStore.defaultDirectory` is public, so the installed-charms location
  is stated once instead of being computed inline.

## 0.5.0

- **Your pack now survives replacing the app.** On first run Dangle copies the
  bundled pack to `~/Library/Application Support/Dangle/pack.json` and never
  writes there again — not on update, not if you never edited it. Packs used
  to live only inside `Dangle.app`, so installing a new build silently threw
  away whatever the old one was carrying. Charms already worked this way;
  packs now do too. The trade: default-pack improvements no longer reach an
  existing install, and deleting your copy takes the new one.
- A pack that fails to parse now says so on stderr, naming the file and the
  reason, instead of quietly falling back to the stock pack.
- `charm.kind` is a real type now (`DanglePack.Kind`) instead of a bare
  string compared with `==` in a dozen places. The JSON is unchanged, and a
  kind written by a newer Dangle decodes as `unrecognized` and hangs as glass
  rather than taking the whole pack down.
- The charm override — an installed charm or a hand-picked emoji — is a
  `CharmOverride` enum instead of a `"emoji:🍀"` string parsed with
  `hasPrefix` at four call sites. The stored form is unchanged, so an
  override picked by an earlier build still resolves.
- Built-in 3D shapes are one `Charm3D.BespokeGlyph` case each, owning their
  names, geometry and finish, instead of a name set and two parallel switches
  kept in sync by hand.
- `fillHex`, `metalness`, `roughness`, `depth` and `chamfer` now apply to the
  built-in shapes too, not only to `pathData` charms — a heart with a
  `fillHex` used to render the built-in red and silently ignore it. Their
  built-in values are defaults now, so nothing that ships changes: no charm
  in the catalog states any of these.
- Frozen-schema tests pin the 1.0 pack and charm formats, so a future change
  that would stop an already-given pack from loading fails CI instead of
  reaching someone's machine. Unknown fields stay ignored, so a pack written
  by a newer Dangle still loads on an older one.

## 0.4.0

- **A charm can carry its own shape.** Give it `pathData` — an SVG `d`
  attribute — and that path is the charm, extruded, chamfered and hung like
  any other. A new 3D charm no longer needs a case in `Charm3D` and an app
  release; it is JSON like everything else. `fillHex`, `metalness`,
  `roughness`, `depth` and `chamfer` came along so a data-only charm can pick
  its own finish.
- `swift run DangleSnapshot --svg <glyph>` prints a bundled shape as path
  data, to start from rather than from nothing.
- Path data is untrusted input and is treated as such: 64 KB and 4,000
  segments, strict parsing, and a malformed path rejected whole rather than
  drawn half-finished. Paths are normalized before extrusion, so the
  overlapping subpaths design tools emit come out right instead of filling
  solid — SceneKit's own tessellator fills overlapping rings solid and
  notches shapes where they cross.
- **Any aspect ratio can hang now.** The 3D charm used to be fitted on
  height alone inside a fixed `2.15 × size` view, so anything wider than
  square grew straight past the view it swings in and clipped. The glyph is
  now fitted on height *and* capped on width, and the view sizes itself from
  the glyph's actual swing radius. Square-ish charms render byte-identically;
  wide ones simply work. The `</>` gains a few points of headroom it was
  quietly short of at full swing.
- The engine tracks the charm's real extents instead of assuming a square,
  so the grab box, cursor repulsion, and note placement follow the shape.
  Never smaller than the old square, so nothing gets harder to grab.
- `make test` now fails a `glyph3d` charm or pack whose glyph has no
  geometry. Those used to hang the glyph *name* as extruded text, silently:
  a pack asking for `"caravel"` really did dangle the word "caravel".
- A pack can carry its own charms in a `charms/` folder next to
  `pack.json`; `make gift` bundles them alongside the catalog. Private
  builds can now ship charms that were never published anywhere.

## 0.2.5

Pre-1.0 cleanup pass — no user-facing feature changes, all internal:

- Fixed a real race in charm-switching: picking a second charm while the
  first one's put-away animation was still in flight could revert to the
  stale first choice. Rapid re-picks now always resolve to the latest one.
- Widened the put-away timing margin (0.5s → 0.65s) against the rope's
  measured ~0.48s dip-and-lift, which left almost no room for frame jitter.
- Removed two genuinely dead pieces of `VerletRope` API (`bow()`,
  `onAnchorSlide`) that nothing in the app ever called or assigned.
- Replaced a force-unwrap in `CharmStore`'s directory resolution with a
  fallback, for consistency with how the rest of the codebase handles that
  same system call.
- Corrected stale comments and docs left behind by earlier changes: the
  "one-line flip" description of the disabled idle-throttle overstated how
  much of it survives in the code, a doc still described the clover with a
  stem that was removed two releases ago, and a comment about cursor
  proximity "pre-arming" frame rate no longer matched what the code does.
- `.gitignore` now covers `.swiftpm/`/`xcuserdata/`; the pack-asset bundling
  step in `make-app.sh` no longer picks up stray dotfiles like `.DS_Store`.

## 0.2.4

- Redrew the `</>` charm: narrower, sharper `<`/`>` chevrons, a longer
  center slash, and slightly thinner strokes overall.

## 0.2.3

- All three charms — `</>`, Heart, Four-Leaf Clover — now install at first
  launch. They're bundled with the app (`Contents/Resources/Charms/`) and
  seeded into the CharmStore on startup, so nothing needs fetching from
  **Get New Charms…** just to have the default set. `</>` also gained its
  own notes, same as the other two.
- The Charm menu no longer sets "Pack Charm" apart with its own section: it
  only appears at all when the active pack's charm isn't one of the
  installed ones (a genuinely custom charm), and then it's just another row
  in the same list, not a separated special case.

## 0.2.2

- Corrected the `</>` chevron angle from 0.2.1: narrower and more pointed,
  not wider — 0.2.1 opened the angle in the wrong direction.
- Changing charms (menu, `Pick an Emoji…`, or `dangle://charm`) now puts
  the current charm away first, then drops the new one back in, instead of
  swapping it instantly mid-air.

## 0.2.1

- The `</>` charm's chevrons are wider and more open — less pointy, more
  clearly angled.
- The clover no longer has a stem; at charm scale it read as a stray nub,
  not a stem. Four leaves stand alone.
- Real notes for Heart and Four-Leaf Clover (six each), and a generic set
  for any hand-picked emoji instead of showing the pack's how-to-use notes.
- The thread no longer carries a miniature twin of a hand-picked emoji as
  its bead — a shrunk copy of an arbitrary emoji read as clutter, not detail.

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
