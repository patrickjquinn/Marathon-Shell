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

## Reef-updated Marathon apps

Not built yet. This is the plan for the apps the image ships but Reef updates
([docs/OTA.md, "What updates how"](../OTA.md#what-updates-how)): Maps, Music,
Notes, Calendar, Mail, Gallery, Pilot, Pacific and the other apps that are not
the system's own.

**Where the copies live.** Reef cannot install into the OS:

- QEMU's `/usr` is a read-only erofs slot.
- A Pi root slot is replaced whole by the next update.
- A Q25 root is a new file each update.

The home directory is the one place every device keeps across updates: on the
Pi it is the data partition, and on the Q25 it is `home.luks`. Marathon apps
already have a signed package format whose user installs live there:

- `.marathon` packages, each a zip with a minisign signature beside it;
- `crates/marathon-apps`, which installs them to `~/.local/share/marathon/apps/<id>/files`
  with a receipt;
- Marathon's own signing keys in `/usr/share/marathon/system-keys`.

**Publishing.**

1. The image keeps installing every app in `/usr/share/marathon-apps`.
2. A Reef-updated app is also packaged as `<id>-<version>.marathon` from the
   same build.
3. The package is signed with Marathon's app key. This is a new minisign key:
   the private key stays with the publisher, and the public key goes in
   `/usr/share/marathon/system-keys`.
4. The package is uploaded to the release `apps/<arch>` of marathon-updates.

**The app's version.** Every manifest still says `1.0.0`. An app's version
gains the build's `IMAGE_VERSION` (`1.0.0.26111001`), so a later build always
sorts higher.

**The catalogue entry:**

```json
"install": {"kind": "marathon", "app_id": "maps",
            "url": "https://github.com/patrickjquinn/marathon-updates/releases/download/apps/aarch64/maps-1.0.0.26111001.marathon",
            "sha256": "…", "min_image": "26111001"}
```

**Installing.** The store handler gains a `marathon:<id>` backend. It
downloads the package, checks the catalogue's `sha256`, and installs it with
`marathon_apps::install_package`, which checks the minisign signature.

**Which copy runs.** Two changes in `crates/marathon-apps`:

- **Installing.** Today `place` refuses any id the OS ships. It accepts one
  only when the package is signed by a system key and is newer than the OS's
  copy.
- **Choosing.** Today `find` and `scan` always prefer the OS's copy. They
  pick the user copy only when it is signed by a system key, is newer than
  the OS's copy, and its `min_image` is no newer than the running
  `IMAGE_VERSION`; otherwise the OS's copy runs.

So the two never fight:

- An OS update never downgrades an app. A newer image carries a newer copy,
  which then runs, and Reef removes the older one in the home directory.
- Reef offers an update only when the catalogue's version is newer than the
  copy that runs.

**ABI.** An app's native plugin links the OS's Qt and Keel, and an older
library may lack a symbol a newer build uses. A user copy therefore runs only
on an image at least as new as `min_image`. Reef shows a newer package for an
older image as "update the phone first". Packages for Reef are built from the
stable image's package set.

**Older Reefs.** `Install` is an internally tagged enum, so a Reef that
doesn't know `marathon` rejects the whole catalogue. Reef therefore needs to
learn to skip unknown kinds, and that Reef must be in every image the feeds
serve, before any `marathon` entry is published. Until then, marathon-updates'
validator accepts only `flatpak` and `android`.

**Closed and system pieces.**

- **Pacific** is an apk in `/usr` today (`packaging/vendor/shipwright.lock`).
  It moves to Reef once Shipwright's sync produces a signed `.marathon`
  bundle for it. Its WebKit engine (`wpewebkit`) stays in the image.
- **Pilot's** app can move the same way. `pilotd` is a system service: it
  stays in the image until user services can run from the home directory.
- **Reef and Deckard** update with the OS.
