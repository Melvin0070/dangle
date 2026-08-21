# Making charms

A charm is one JSON file. `</>`, Heart, and Four-Leaf Clover ship bundled
with the app; publishing a new one to this repository's `charms/` catalog
makes it installable by every Dangle user from **Charm → Get New Charms…**
— no app release involved.

## The file

```json
{
  "id": "clover",
  "name": "Four-Leaf Clover",
  "charm": {
    "kind": "glyph3d",
    "glyph": "clover",
    "size": 96,
    "gradientHexes": ["#2F9E44", "#69DB7C", "#B2F2BB"],
    "accentHex": "#2F9E44",
    "menuGlyph": "🍀"
  },
  "notes": [
    "Luck finds the ones who keep showing up.",
    "Give it a flick before anything that could use a little luck."
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Stable, lowercase, unique across the catalog. Also the filename. Letters, digits, and hyphens only, 64 chars max — it's used as a filename. |
| `name` | What the Charm menu shows. |
| `charm.kind` | `glyph3d` (extruded 3D), `glass` (gradient tile), or `emoji`. |
| `charm.glyph` | What to hang — see below. |
| `charm.size` | Points, default 96. |
| `charm.gradientHexes` | Colors for rim reflections (3D) or the tile gradient (glass). |
| `charm.accentHex` | Accent for the twin bead in the flat scene diagram. |
| `charm.menuGlyph` | Emoji or short text for the menu bar while this charm hangs. |
| `charm.pathData` | An SVG `d` attribute. When present it *is* the shape and `glyph` is ignored. See below. |
| `charm.pathEvenOdd` | Fill `pathData` by the even-odd rule. Design tools write `fill-rule="evenodd"` for most compound shapes. |
| `charm.fillHex` | Material color. Default is the dark chrome. |
| `charm.metalness` | 0–1, default 1. |
| `charm.roughness` | 0–1, default 0.2. |
| `charm.depth` | Extrusion depth in points, default 13. |
| `charm.chamfer` | Chamfer radius in points, default 2.4. |
| `notes` | Optional. This charm's own notes — shown instead of the pack's while it hangs, text only. Omit to fall back to whatever pack the charm is hung on. |

## What can hang

**`glyph3d`** — a real extruded shape with chamfered edges, PBR chrome, and
reflections from the pack gradient. Some glyphs have bespoke geometry built
from rounded capsules, stroked ellipses, and bezier curves (typeset text
never looks right extruded) — `Charm3D.bespokeGlyphs` is the authoritative
list:

- `</>` — the code mark
- `heart` — a lacquer heart
- `clover` — four heart-leaves, tips meeting at the center, no stem

Shape, not just outline: a charm is one flat path extruded with a chamfer,
wearing one material. Interior detail is invisible — a silhouette has no
inside — and strokes thinner than about `0.06 × size` disappear under the
chamfer. Overlapping subpaths are resolved for you — `pathData` is
normalized before extrusion, because SceneKit's own tessellator fills
overlapping rings solid and notches shapes where they cross.

Any aspect ratio hangs — the view sizes itself to the glyph's swing — but
the thread ties to the top-center of the glyph's *bounds*, so put some
material there. A shape whose tallest point is off to one side hangs from a
ring floating in mid-air.

Any other `glyph` string is extruded as heavy monospaced type, which works
for single characters (`&`, `λ`, `∞`) and gets worse the longer the string.
`make test` fails a catalog charm whose `glyph3d` glyph is neither bespoke
nor short, because the fallback would silently hang the name itself as text.

### Shapes as data

You do not need a case in `Charm3D` to hang a new shape. Give the charm
`pathData` — an SVG `d` attribute — and that path *is* the charm:

```json
{
  "id": "moon",
  "name": "Crescent",
  "charm": {
    "kind": "glyph3d",
    "glyph": "moon",
    "accentHex": "#C8A15A",
    "gradientHexes": ["#1B1B2E", "#8E8AA8", "#C8A15A"],
    "fillHex": "#C8C2D8",
    "metalness": 1.0,
    "roughness": 0.25,
    "pathData": "M 0 -40 A 40 40 0 1 0 0 40 A 30 30 0 1 1 0 -40 Z"
  }
}
```

Draw the shape in Figma, Illustrator, or Affinity, export SVG, and copy the
`d` attribute out. Hand-typing bezier control points and re-rendering to see
what happened is a bad way to spend an afternoon. To start from a shape that
already ships:

```bash
swift run DangleSnapshot --svg clover
```

The parser takes `M L H V C S Q T A Z`, absolute and relative. Path data
from a catalog is untrusted input, so it is bounded: 64 KB of source and
4,000 segments, and a malformed path is rejected whole rather than drawn
half-finished. Coordinates are in SVG's y-down space and any scale you like
— the charm is fitted to `charm.size` by its bounding box either way.

A charm with `pathData` ships like any other charm: a JSON file, no app
release. Only new *named* glyphs still need one.

**`glass`** — a rounded gradient tile with the glyph on top, animated
gradient drift. The lightest kind.

**`emoji`** — the bare glyph, big. Zero effort, often exactly right.

## Test it

```bash
# Splice your charm into the default pack and hang it, no catalog involved:
jq '.charm = input.charm' Packs/default/pack.json my-charm.json > /tmp/try-pack.json
DANGLE_PACK=/tmp/try-pack.json make run

# Or render it to PNGs in snapshots/:
DANGLE_PACK=/tmp/try-pack.json make snapshot
```

You can also point the whole charm-store at a local catalog while testing
the install flow: `DANGLE_CHARM_INDEX=/path/to/charms/index.json`.

## Publish it

1. Add `charms/<id>.json`.
2. Add an entry to `charms/index.json`.
3. Open a PR with a screenshot or `make snapshot` render.

`make test` validates that every published charm decodes.
