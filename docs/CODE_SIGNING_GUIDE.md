# Marathon Code Signing Guide

Every `.marathon` package must be signed before Marathon installs it. The
signature covers the whole archive, and the installer checks it before it
opens the archive at all.

## How it works

- The signature is a [minisign](https://jedisct1.github.io/minisign/)
  detached signature (Ed25519) over the archive's bytes, stored next to the
  package as `<package>.marathon.minisig`.
- Installing copies the package and its signature into a private temporary
  directory, checks the signature over that copy, and only then extracts the
  same copy. A package that fails the check is never unpacked.
- The signature must be made by a trusted key that is not revoked.
- Only pre-hashed signatures are accepted. That is what `minisign -S` makes
  by default; `minisign -S -l` makes the legacy kind, which is refused.

The check lives in Rust (`crates/marathon-core-native/src/signature.rs`,
using the [`minisign`](https://crates.io/crates/minisign) crate) and is
called from `MarathonAppVerifier::verifyPackage`.

## Making a key

Use the standard minisign tool (packaged as `minisign` on Alpine,
postmarketOS, Fedora, Debian and Homebrew):

```bash
minisign -G          # writes ~/.minisign/minisign.key (password-protected)
                     # and minisign.pub
minisign -G -W       # the same without a password, e.g. for CI secrets
```

The public key file looks like this; the hex after `public key:` is the key id:

```
untrusted comment: minisign public key: BDC597FE8CF7F6F3
RWTz9veM/pfFvaHGXJDKwGIRS/MP5g/syiBzHNpL/aymxdZvs/8LDhpF
```

Keep the secret key out of version control and back it up.

## Signing

```bash
# Package and sign in one step
marathon-dev package ./my-app my-app.marathon --key ~/.minisign/minisign.key

# Sign an existing package (the key defaults to ~/.minisign/minisign.key)
marathon-dev sign my-app.marathon [secret-key]

# The minisign CLI works too
minisign -S -m my-app.marathon
```

`marathon-dev` asks for the key's password on the terminal if it has one.
Re-packaging removes a `.minisig` left from an earlier build, since it would
not match the new archive.

Ship the `.minisig` with the package: a store serves it at the package URL
plus `.minisig`, and a sideloaded package needs it in the same directory.

## Verifying

```bash
marathon-dev verify my-app.marathon
minisign -V -p minisign.pub -m my-app.marathon   # any minisign tool
```

`marathon-dev verify` checks against the device's trusted keys and prints
the signing key id.

## Trusted keys

Marathon trusts the minisign public keys (`*.pub`) in:

| Directory | Who puts keys there |
|---|---|
| `/usr/share/marathon/trusted-keys/` | The OS packages: Marathon's own release keys |
| `~/.config/marathon/trusted-keys/` | The user: a developer trusting their own key |

To trust your own key on a development device:

```bash
mkdir -p ~/.config/marathon/trusted-keys
cp ~/.minisign/minisign.pub ~/.config/marathon/trusted-keys/my-key.pub
```

Several keys can be trusted at once. To rotate, ship the new key, start
signing with it, then revoke the old one.

Older Marathon builds used OpenPGP keys (`*.asc`, `*.gpg`) in
`~/.config/marathon/trusted-keys/`. Those files are ignored now; replace
them with minisign `.pub` keys.

A key file that does not parse stops every verification until it is fixed
or removed, rather than being skipped.

### Revocation

A file named `revoked` in either trusted-keys directory lists key ids that
are no longer trusted, one per line, `#` for comments:

```
# leaked 2026-10-02
4D9129AD84930B56
```

A revocation in any directory applies to a key trusted in any other, so an
OS update can withdraw a key a user added themselves. Ids that are not 16 hex
digits are an error, so a typo cannot quietly drop a revocation.

## The developer override

`MARATHON_ALLOW_UNSIGNED=1` lets the installer accept:

- a package with no `.minisig`, and
- an install from an app directory (`marathon-dev install ./my-app`), which
  has no archive to sign.

It does not accept a signature that is invalid, untrusted or revoked: it
waives the signature, not the check of one that is there. Every install it
lets through is logged to syslog (`LOG_AUTH`, `[SECURITY] Unsigned ...`).

```bash
MARATHON_ALLOW_UNSIGNED=1 marathon-dev install ./my-app
```

## Permissions at install time

Before installing, the installer describes every permission the package's
`manifest.json` declares (see
[APP_MANIFEST_SCHEMA.md](APP_MANIFEST_SCHEMA.md#permissions-array-of-strings)).
A permission it has no description for refuses the install. An update that
declares permissions the installed version does not have is held until the
user agrees to them; `marathon-dev install` shows them and asks for
`--approve-permissions`.

## Troubleshooting

| Message | Meaning |
|---|---|
| `Package is not signed` | No `.minisig` beside the package. Sign it, or use the override while developing. |
| `Invalid signature` | The package changed after signing, the `.minisig` belongs to another file, or it is a legacy (`-l`) signature. Re-sign. |
| `signed by key X, which is not trusted` | Add key X's `.pub` to a trusted-keys directory. |
| `signed by key X, which is revoked` | Sign with a current key. |
| `Failed to load trusted keys` | A `.pub` or `revoked` file in a trusted-keys directory does not parse. |
| `Permissions with no description` | The manifest declares a permission Marathon does not know. |
