# Reef's catalogue for Marathon

Reef shows three kinds of app in one store: Flathub's and F-Droid's, which the
store handler keeps on the phone, and the apps in Reef's own catalogue, which
this file describes. Reef's entry wins when it lists an app Flathub or F-Droid
also has: its title, screenshots, licence and price are shown instead.

## Where Reef reads it

`https://patrickjquinn.github.io/marathon-updates/reef/<arch>/catalogue.json`,
where `<arch>` is the phone's processor as Rust names it: `aarch64` or
`x86_64`. That is GitHub Pages for
[patrickjquinn/marathon-updates](https://github.com/patrickjquinn/marathon-updates),
whose `site/` it serves. Icons and screenshots are paths relative to that
directory (`assets/notes.png`); Reef fetches them from there and from nowhere
else. `REEF_STORE_URL` overrides the directory on a development phone
(`{arch}` is replaced).

The file is either a catalogue (below) or a store index; both carry the same
install information.

## Signature

Beside each catalogue is `catalogue.json.asc`, a detached ASCII GnuPG
signature over its exact bytes by the Reef catalogue key: the scheme Reef's
Sailfish OS store uses for its index (`store/index.json.asc`, checked with
`gpgv` against the key the client ships). The catalogue's `revision`, an
integer, never goes backwards, so a client that remembers the highest it
accepted can refuse a replayed older catalogue.

| | |
|---|---|
| public key | `keys/marathon-reef.asc` in marathon-updates, fingerprint `F2E11B366BAF957F487B86E64D63ECF4806B0F6E` |
| private key | `~/.marathon-secrets/reef/gnupg` on the publisher's machine only |
| sign | `tools/reef-catalogue sign site/reef/<arch>/catalogue.json --gnupghome ~/.marathon-secrets/reef/gnupg`: checks the catalogue, stamps `generated_at` and a higher `revision`, signs |
| check | `tools/reef-catalogue verify site/reef/*/catalogue.json`, run by marathon-updates' CI on every push; the Pages deploy runs it first and publishes nothing that fails |

Reef does not check the signature yet: it trusts HTTPS to GitHub Pages, as
it trusted HTTPS to reefstore.app. Checking it means shipping the key
dearmored in the shipwright-reef package (gpgv reads no armored keys) with
`gpgv` as a dependency, fetching `catalogue.json.asc` beside the catalogue in
`jobs::refresh`, refusing the catalogue on a bad signature or a lower
`revision` than the one kept beside the cache, and signing the `file://`
stores in its tests.

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
