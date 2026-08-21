# Contributing to Dangle

Thanks for stopping by. Dangle is small on purpose — a zero-dependency
AppKit app — and contributions that keep it small are the easiest to land.

## Building

Only the Xcode Command Line Tools are required (no Xcode):

```bash
make run        # build dist/Dangle.app and open it
make debug      # debug-configuration build
make test       # run the test suite
make snapshot   # render charm/note/scene PNGs to snapshots/
make clean
```

`make test` handles the extra framework paths that `swift test` needs on a
Command Line Tools-only machine; on a full Xcode install or CI, plain
`swift test` also works.

## What lives where

- `Sources/DangleKit` — everything interesting: `VerletRope` (physics),
  `DangleEngine` (the runtime loop and rendering), `Charm3D` (SceneKit
  charm), `CharmLayer` (2D charm kinds), `NoteView`, `ConfettiSystem`,
  `DanglePack` (pack model), `CharmStore` (charm catalog), `HotKeys`.
- `Sources/DangleApp` — the menu bar shell and URL scheme. Thin by design.
- `Sources/DangleSnapshot` — offscreen renders for the README, the app icon
  (`--icon`), and physics diagnostics (`--windstats`).

## Ground rules

- **No dependencies.** The whole app is AppKit, Core Animation, SceneKit,
  and Carbon hotkeys. Please keep it that way.
- **Performance is a feature.** The idle path must stay near 1% of a core:
  the loop drops to 30Hz when quiet, the SceneKit view sleeps to a bitmap,
  and the display link pauses when dismissed. If your change touches the
  render loop, measure before and after (`ps -o cputime -p <pid>` deltas
  over a minute of idling is enough) and put the numbers in the PR.
- **Physics changes need the numbers too.** `swift run DangleSnapshot --windstats`
  prints idle-breeze endpoint speeds; the engine's sleep thresholds are set
  from that data, and `make test` pins the assumption down.
- **Tests run headless.** Test DangleKit logic (physics, parsing, stores);
  avoid tests that need a window server or a GPU.

## Adding a charm

The friendliest contribution there is — see
[docs/making-charms.md](docs/making-charms.md). Charm PRs need: the charm
JSON in `charms/`, an entry in `charms/index.json`, and a screenshot in the
PR description (`DANGLE_PACK=path/to/try-pack.json make run` or
`… make snapshot` — the doc shows how to build the try-pack).

## Commits

Conventional Commits, imperative mood: `feat(engine): …`, `fix(charm3d): …`,
`docs: …`. One logical change per commit.
