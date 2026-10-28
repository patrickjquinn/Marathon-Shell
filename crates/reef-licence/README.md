<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# reef-licence

Licence tokens for paid Reef apps, and their offline verification (docs/plan.md, "Payments and licences"). Apps link this crate and check their licence against an embedded Ed25519 public key with no network access. The licence service (`services/licence-service`) issues tokens with the `sign` feature, which apps never enable.

## Token format (v1)

```
v1.<base64url(payload)>.<base64url(signature)>
```

- **payload**: canonical JSON of the claims. Keys are in lexicographic order, with no whitespace and integers only. An absent `exp` is omitted, never `null`. Identifier strings are limited to `[A-Za-z0-9._-]`, 1 to 128 characters, so escaping never happens.

  ```json
  {"app":"shoal-messages","exp":1792800000,"iat":1790000000,"kid":"k2026a","lid":"lic_4f0c…","plan":"subscription"}
  ```

  | Key | Meaning |
  | --- | --- |
  | `app` | App id the licence unlocks |
  | `exp` | Expiry, Unix seconds. Required for `subscription`; optional (usually absent) for `one_off` |
  | `iat` | Issued at, Unix seconds |
  | `kid` | Id of the signing key (rotation) |
  | `lid` | Licence id: 128 random bits, device-independent, the handle for refresh and revocation |
  | `plan` | `one_off` or `subscription` |

- **signature**: Ed25519 (RFC 8032) over the ASCII bytes `v1.<base64url(payload)>`. The version prefix is part of the signed bytes.
- base64url is unpadded and must have zero trailing bits. A token is at most 2048 bytes (a typical one is about 250).

**Why canonical JSON and not CBOR.** The payload is six short fields. JSON keeps a token readable with `base64 -d`, and serde_json is already a dependency of both the service and the store client. The verifier re-encodes the parsed claims and requires byte equality with the payload, which gives every licence exactly one valid encoding: whitespace, key order, `null` for absent, escapes, duplicate keys and unknown keys are all rejected. CBOR would save a few dozen bytes at the cost of a new dependency and a format that is harder to inspect.

**Verification order.** Length and prefix, then base64, then JSON (only to read `kid`), then key lookup and `verify_strict`, then the canonical-form check, then semantic checks (`exp` after `iat`, a subscription has `exp`), then the app id (`Licence::verify`; `verify_any_app` skips it), then time. So an expired token for another app reports `WrongApp`. Nothing in the payload is trusted until the signature has verified. `verify_strict` rejects non-canonical and small-order signatures, and weak (small-order) public keys are refused when they are loaded.

**Time rules** (`Policy`, defaults shown):

- `clock_skew_secs = 300`: a token issued up to 5 minutes in the future is accepted, and expiry is extended by the same margin.
- `subscription_grace_secs = 7 days`: a subscription past `exp + skew` verifies as `Standing::Grace` until the grace period ends, so an app used offline keeps working while it retries a refresh. After that it is `Error::Expired`.
- A one-off licence with an `exp` gets no grace period.

**Key rotation.** Apps embed a `KeySet` holding the current key and the next one (`KeySet::from_embedded(&[("k2026a", "<base64url>")])`). The service starts signing with the next key only after apps carrying it have shipped.

**Detached signatures and the revocation list.** `Signer::sign_detached` and `KeySet::verify_detached` sign response bodies. The signature header has the form `v1.<kid>.<base64url sig>`, computed over `shipwright-detached-signature-v1\n` followed by the body. Because of that context prefix, a detached signature can never pass as a token signature. `RevocationList` is the signed list of refunded licence ids that the service publishes at `/v1/revocations`.

## API

```rust
use reef_licence::{KeySet, Licence, Policy, Standing};

let keys = KeySet::from_embedded(&[("k2026a", "BQ16MOeMWXJK…")])?;
match Licence::verify(&token, "shoal-bridge", &keys, &Policy::default(), now) {
    Ok(Licence { standing: Standing::Active, .. }) => unlock(),
    Ok(Licence { standing: Standing::Grace { grace_ends, .. }, .. }) => unlock_and_nag(grace_ends),
    Err(e) => show_locked(e),
}
```

**Embedding the keys at build time.** Apps do not write their keys into the source. The `build` feature (`reef_licence::build`, taken as a build-dependency) gives a build script `embed_keys()`, which reads `SHIPWRIGHT_LICENCE_KEYS` in the form `kid:base64url[,kid:base64url...]` (what `shipwright-licence-service public-key` prints, the same form as `PILOT_RELAY_LICENCE_KEYS`), checks every entry as `KeySet::insert_text` does at run time (key id of `[A-Za-z0-9._-]`, a 32-byte unpadded base64url key that is a valid, non-weak Ed25519 point, no repeated key id) and fails the build on anything else. It writes the value of `EMBEDDED_KEYS` to `$OUT_DIR/licence_keys.rs`, which the app `include!`s. Unset or blank gives an empty set, which rejects every token. In a release build (`--cfg release_build`) a key id starting with `staging` or `test`, in any case, fails the build, so a test key cannot ship. The Reef client, Shoal Keys and Shoal Mail use it.

The issuing side is only available with `features = ["sign"]`:

```rust
let signer = Signer::from_seed_text("k2026a", &std::fs::read_to_string(key_file)?)?;
let token = signer.issue(&claims)?; // refuses claims a verifier would reject
```

## Licence hand-off (sandboxed apps)

Paid apps run under Sailjail and cannot read Reef's licence directory (`~/.local/share/shipwright-reef/licences/`). Instead of the user pasting a token, Reef offers it on the session bus, and apps ask at start-up:

| | |
| --- | --- |
| Bus name | `org.shipwright.Reef.Licences`, D-Bus activated (`/usr/share/dbus-1/services/org.shipwright.Reef.Licences.service`) |
| Process | `shipwright-reef-licenced` (reef-backend `src/bin`, service in `src/licenced.rs`): exits after 30 s idle |
| Object, interface | `/org/shipwright/Reef/Licences`, `org.shipwright.Reef.Licences1` |
| Method | `GetLicence(s app_id) -> (s token)` |
| Errors | `org.shipwright.Reef.Licences1.Error.NotFound` (none stored, or revoked by the stored revocation list), `...Error.InvalidAppId` |
| Sailjail | `/etc/sailjail/permissions/ShipwrightLicences.permission`: `dbus-user.talk org.shipwright.Reef.Licences`, shipped by the Reef client RPM; apps add `ShipwrightLicences` to `Permissions=` |
| Client | `reef_licence::handoff::fetch(app_id)` (feature `handoff-client`, zbus blocking, 5 s timeout) |

Users: Shoal Mail (`shipwright-shoal-mail`, `Engine::adopt_licence(licence::token_from_reef)`) and Shoal Keys (`shipwright-shoal-keys`, `licence::adopt_from_reef`). (The Shoal Bridge UI used it until it became free on 12 October 2026 and dropped its licence gate.) Each asks only when it holds no fully valid licence (none, or a subscription in grace), verifies the answer exactly like a pasted token, stores it in its own data directory, and keeps paste-in as the fallback (no Reef, no permission, or Reef holds nothing). The rules they follow are in "Licence policy for Shipwright apps" below.

**Why the service does not authenticate the caller (decision (a)).** Sailjail filters D-Bus by bus name, not by method argument, so any app granted `ShipwrightLicences` can ask for any app id. We accept that rather than check the caller's identity, because a token is not a secret that protects the user:

- It is signed, device-independent and bound to one app id. It unlocks only that app, which verifies its own id offline; another app holding it gains nothing.
- It is the same string the user pastes today, so the service gives no more than paste-in already exposes.
- Unsandboxed processes (anything with `Sandboxing=Disabled`, a shell) can read the licence directory directly; caller authentication would not change that.
- The residual risk is an app that collects other apps' tokens and publishes them for others to use unpaid. Every token carries a licence id (`lid`), so the licence service can see one licence used at scale and revoke it, and the permission has to be declared in the app's desktop file, where store review sees it.

The alternative (b), `GetConnectionUnixProcessID` and then `/proc/<pid>/exe` or Sailjail's per-app data, depends on Sailjail internals that are not a stable interface, breaks when several apps share an executable (keel-shell launches every Keel app), and would still leave the unsandboxed path open. If tokens ever become user secrets (for example, if they start carrying account data), revisit this.

**Why a separate binary, not the Reef GUI.** An app asking at start-up must not open Reef's window, the GUI is usually not running, and activation of a small process is fast. The binary only reads the licence directory and answers one method.

## Licence policy for Shipwright apps

Owner decision, 2026-10-01: "zero friction, whatever is easiest for the user". Every paid Shipwright app follows this policy; the app READMEs point here and document only their own trial and what their licence unlocks. Today that is Shoal Mail (`shoal/mail/README.md`, "Licence and trial") and Shoal Keys (`shoal/keys/README.md`, "Licence"). The Shoal Bridge UI is free since 12 October 2026 and has no licence code (`shoal/bridge-airpods/ui/README.md`, "Free").

1. **Any valid licence token for the app is accepted, one-off or subscription**, whatever plan the app is sold on. "Valid" means `Licence::verify` passes for the app's own id with `Policy::default()`:
   - 5 minutes of clock skew on the issue time and the expiry;
   - a subscription past `exp + skew` stays usable for 7 days of grace (`Standing::Grace`), during which the app works fully and asks Reef for a renewal; after that it is treated as no licence;
   - a one-off with an `exp` gets no grace.
   A token for another app id, an unknown key, a bad signature or a malformed token is refused, and a refused token never replaces a stored valid one.
2. **Fetched from Reef automatically.** At start-up, and when the app returns to the foreground (for example after the user bought the licence through Reef: the checkout carries a claim code from Reef, and Reef fetches the token with it when the user comes back, `reef/client/ui/README.md`, "Buying"), the app asks Reef's hand-off service (above) for its token whenever it holds no fully valid licence (none, or a subscription in grace). This must stay cheap: no question at all while a fully valid licence is stored, and none while one is pending. A token from Reef is checked exactly like a pasted one.
3. **Paste-in only as the fallback**, for when Reef is not installed, the app lacks `ShipwrightLicences`, or Reef holds nothing. It is always available in the app's settings.
4. **Trials stay as they are** (each app's README: Keys is free with an optional licence; Mail is free since 3 October 2026, its 30-day trial kept only as a policy for the tests; the Bridge UI is free since 12 October 2026, with no trial).
5. **Nothing that worked before is locked away** beyond what each app's README already documents. Without a licence (or once a subscription's grace has ended) the app falls back to its documented unlicensed state: Mail read-only after the trial, Keys' password health report locked (the vault, import and export never are). No app ever locks the user out of their own data.

Status (2026-10-01): points 1 to 5 are implemented in both apps' licence code and tests (`shoal-mail-core` `licence.rs` and `Engine::adopt_licence`, `shoal-keys-core` `licence.rs`). The Bridge UI had them too, with the foreground re-check wired, until it became free (12 October 2026). In Mail and Keys the core call is ready and cheap when licensed (`Engine::adopt_licence`, `licence::adopt_from_reef`), but the app layers (`shoal/mail/app`, `shoal/keys/app` and their QML) do not yet call it when the app becomes active; until they do, those two apps pick up a new purchase at the next start, or by paste-in.

## Build and test

```
cargo test -p reef-licence                 # 29 tests; the signing code is compiled for tests
cargo clippy -p reef-licence --all-targets -- -D warnings
cargo clippy -p reef-licence --all-targets --features sign -- -D warnings
cargo clippy -p reef-licence --all-targets --all-features -- -D warnings
cargo test -p reef-backend --test licenced_dbus   # the hand-off over a private dbus-daemon
```

The tests cover: canonical encoding (whitespace, key order, `null`, escapes, unknown and duplicate keys); a signed but non-canonical payload; a token signed with the wrong key under the right `kid`; an unknown `kid`; rotation; a payload swapped under a valid signature; a flipped bit in the signature; every single-character substitution in a token; malformed and oversized tokens and `v2`; issue-time skew; one-off expiry without grace; subscription grace boundaries; a strict zero policy; detached-signature tampering; and cross-protocol replay (a detached signature used as a token signature).

Dependencies: `ed25519-dalek 3` (MSRV 1.85), `base64 0.23`, `serde`, `serde_json`; with `handoff-client`, `zbus 5` (blocking API on async-io, no tokio).

## Needs device verification

- Offline verification cost on the Jolla Phone: time `Licence::verify` at app start in a release build. It should take well under a millisecond; record the figure.
- Clock behaviour: after a reboot without network, check that the phone's clock is inside the 5-minute skew, or that the licence shows as in grace rather than failing. Test by booting in flight mode.
- Licence hand-off under Sailjail. Install Reef (with `shipwright-reef-licenced`, the activation file and `ShipwrightLicences.permission`) and save a Mail licence in Reef. Start Shoal Mail from the app grid with a fresh data directory: Settings should show it licensed without pasting. Then:
  - `dbus-send --session --print-reply --dest=org.shipwright.Reef.Licences /org/shipwright/Reef/Licences org.shipwright.Reef.Licences1.GetLicence string:shipwright-shoal-mail` from a shell returns the token, and `ps` shows `shipwright-reef-licenced` exiting about 30 s later.
  - Remove `ShipwrightLicences` from Mail's desktop file: the call must fail quickly (no hang at start-up) and paste-in must still work.
  - Uninstall Reef while Mail still lists `ShipwrightLicences`: check that Sailjail still launches Mail with the permission file missing. If it refuses, the permission file must move to a small package that paid apps require.
  - Check that D-Bus activation works through Sailjail's D-Bus proxy (the first call starts the service).
