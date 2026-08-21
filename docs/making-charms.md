# Making charms

A charm is one JSON file. Publishing it to this repository's `charms/`
catalog makes it installable by every Dangle user from **Charm → Get New
Charms…** — no app release involved.

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
| `notes` | Optional. This charm's own notes — shown instead of the pack's while it hangs, text only. Omit to fall back to whatever pack the charm is hung on. |

## What can hang

**`glyph3d`** — a real extruded shape with chamfered edges, PBR chrome, and
reflections from the pack gradient. Three glyphs have bespoke geometry built
from rounded capsules and bezier curves (typeset text never looks right
extruded):

- `</>` — the code mark
- `heart` — a lacquer heart
- `clover` — four heart-leaves and a stem

Any other `glyph` string is extruded as heavy monospaced type, which works
for single characters (`&`, `λ`, `∞`) and gets worse the longer the string.
For a new shape at Lucky Dangle quality, add a path function to
[`Charm3D.swift`](../Sources/DangleKit/Charm3D.swift) (see `codeGlyphPath` /
`heartPath` / `cloverPath` — they're ~30 lines each) and a case for it in
`makeScene`, then reference it by name from your charm JSON. That does need
an app release, so shape PRs ride the next version; color/emoji charms ship
instantly.

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
