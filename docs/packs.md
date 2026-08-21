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
  "name": "Farewell",              // shown nowhere yet; names the pack
  "charm": {
    "kind": "glyph3d",             // "glyph3d", "glass", or "emoji"
    "glyph": "</>",                // see docs/making-charms.md
    "size": 96,                    // points
    "gradientHexes": ["#E8590C", "#FFB86B", "#FF5E78"],
    "accentHex": "#E8590C",        // note monograms
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
    { "text": "The words that appear under the charm.", "from": "A name" }
  ]
}
```

Notes rotate in order, advancing on every click of the charm, ⌃⌥N, the
interval timer, and `dangle://note`. The counter under the note shows where
you are in the rotation.

## Bundling a pack into a build

```bash
DANGLE_BUNDLE_PACK=path/to/pack.json make app   # just the app
make gift PACK=path/to/pack.json                # app + DMG, ready to hand over
```

`Packs/farewell/` is a template with sample notes; copy it into
`Packs/local/` (gitignored) before filling in real names and real words.
