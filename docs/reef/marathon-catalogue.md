# Reef's catalogue for Marathon

Reef shows three kinds of app in one store: Flathub's and F-Droid's, which the
store handler keeps on the phone, and the apps in Reef's own catalogue, which
this file describes. Reef's entry wins when it lists an app Flathub or F-Droid
also has: its title, screenshots, licence and price are shown instead.

## Where Reef reads it

`https://reefstore.app/marathon/<arch>/catalogue.json`, where `<arch>` is the
phone's processor as Rust names it: `aarch64` or `x86_64`. Icons and
screenshots are paths relative to that directory (`assets/notes.png`); Reef
fetches them from there and from nowhere else. `REEF_STORE_URL` overrides the
directory on a development phone (`{arch}` is replaced).

The file is either a catalogue (below) or the store index that
`tools/build/reef/gen-store.py` writes; both carry the same install
information.

## Catalogue

```json
{
  "schema": 1,
  "release": "marathon",
  "arch": "aarch64",
  "generated_at": "2026-10-28T12:00:00Z",
  "featured": ["notes"],
  "packages": [
    {
      "name": "notes",
      "version": "2.1",
      "title": "Notes",
      "summary": "Write things down",
      "description": "Plain text notes, synced.",
      "category": "Office",
      "tested_on": [],
      "publisher": "Example Ltd",
      "icon": "assets/notes.png",
      "screenshots": ["assets/notes-1.png"],
      "homepage": "https://example.org",
      "spdx": "GPL-3.0-or-later",
      "added": "2026-10-28",
      "licence": {"model": "free"},
      "install": {"kind": "flatpak", "remote": "flathub", "ref": "app/org.example.Notes/aarch64/stable"}
    }
  ]
}
```

`name` is Reef's id for the app; it never reaches the phone's package
managers.

### `install`: what installs it

| `kind` | Fields | Marathon installs it |
| --- | --- | --- |
| `flatpak` | `remote`, `ref`: a full ref or the app id | from Flathub (`remote` must be `flathub`) |
| `android` | `package`, `store` | from F-Droid through Deckard (`store` must be `fdroid`) |

Any other kind, remote or store is not installable on Marathon yet: the app
is listed with a note saying so. In the store index the same objects go in
each app's `sources` list.

### `licence`

`{"model": "free"}`, or a paid app:
`{"model": "one_off" | "subscription", "app_id": "<licence app id>",
"purchase_url": "https://..."}`. Paid apps install like free ones and check
their own licence; Reef's Buy opens the purchase URL with a claim code and
collects the licence from the licence service once it is paid
(`apps/reef/UI.md`, "Buying").

### Optional fields

`description`, `publisher`, `homepage`, `source` (the source code's URL),
`spdx`, `size` (bytes), `added` and `changelog` (`[{version, date,
notes: [...]}]`, newest first), `keywords`, `screenshots` (at most 5) and
`featured` at the top level. Everything Reef reads is in
`crates/reef-backend/src/catalogue.rs` (`Package`).
