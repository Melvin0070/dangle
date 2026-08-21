# Packs

A pack is the customization layer: one `pack.json` (plus optional assets in
the same folder) that fully describes what hangs from the screen and what it
says. The app resolves packs in this order:

1. `$DANGLE_PACK` — explicit path, wins over everything
2. `~/Library/Application Support/Dangle/pack.json` — your edited copy
3. The pack bundled inside the app
4. A built-in fallback (`</>` with one note)

Choose **Edit Pack…** from the menu bar icon and Dangle copies the active
pack to Application Support and reveals it. Edit, then choose **Reload
Pack** — no rebuild needed (hotkey changes apply on next launch).

## Schema

```jsonc
{
  "name": "My Pack",               // shown nowhere yet; names the pack
  "charm": {
    "kind": "glyph3d",             // "glyph3d", "glass", or "emoji"
    "glyph": "</>",                // see docs/making-charms.md
    "size": 96,                    // points
    "gradientHexes": ["#E8590C", "#FFB86B", "#FF5E78"],
    "accentHex": "#E8590C",        // twin bead color in the flat scene diagram
    "menuGlyph": "</>"             // optional menu bar text/emoji
  },
  "thread": { "colorHex": "#FFFFFF", "width": 3 },
  "noteSeconds": 7,                // how long a note stays up
  "noteIntervalMinutes": 30,       // spontaneous notes; null to disable
  "hotkeys": {                     // optional; ctrl/opt/cmd/shift + a-z0-9
    "toggle": "ctrl+opt+d",
    "note": "ctrl+opt+n",
    "bless": "ctrl+opt+b"
  },
  "blessSoundPath": "chime.aiff",  // optional, relative to pack.json
  "notes": [
    "The words that appear under the charm. Text only — nothing else."
  ]
}
```

Notes rotate in order, advancing on every click of the charm, ⌃⌥N, the
interval timer, and `dangle://note`. The note card shows exactly the text —
no author, no counter. If the hanging charm has its own notes (see
[docs/making-charms.md](making-charms.md)), those rotate instead of the
pack's; switching back to **Pack Charm** returns to these.

## Bundling a pack into a build

```bash
DANGLE_BUNDLE_PACK=path/to/pack.json make app   # just the app
make gift PACK=path/to/pack.json                # app + DMG, ready to hand over
```

Put your own packs in `Packs/local/` — it's gitignored, so custom names and
notes never end up in a repository.

### Charms only that pack has

A pack can carry charms of its own in a `charms/` folder next to its
`pack.json`:

```
Packs/local/mine/
  pack.json
  charms/voto.json
  charms/sorte.json
```

They install alongside the published catalog and appear in the **Charm**
menu, so a private build can ship charms nobody else ever sees. They are
ordinary charm files — see [docs/making-charms.md](making-charms.md) — and
a `glyph3d` one still needs its shape to exist in the app it is built into.

One gotcha: if the pack's own `charm` block is identical to a charm already
installed, the menu drops the **Pack Charm** entry as a duplicate and the
pack's notes become unreachable. Give the pack charm its own gradient or
size so the two are distinguishable.
