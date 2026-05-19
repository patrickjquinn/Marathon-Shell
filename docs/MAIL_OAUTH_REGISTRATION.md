# Marathon Mail OAuth client IDs

Marathon's Gmail and Outlook sign-in flows use OAuth 2.0 PKCE
installed-app authentication. PKCE replaces the client secret with a
per-flow proof of possession, which means an OAuth client ID alone is
not a credential — it is safe to publish in an open-source binary.
This is the same pattern Thunderbird, Evolution, GNOME Online Accounts,
Geary, and K-9 Mail use.

## How client IDs resolve

`marathon-mail-oauth` resolves the client ID for each provider through
a three-tier ladder. Highest precedence first:

| Layer | Source | Used by |
|-------|--------|---------|
| 1 | Runtime env var: `MARATHON_OAUTH_GOOGLE_CLIENT_ID`, `MARATHON_OAUTH_MICROSOFT_CLIENT_ID` | Enterprise forks, per-machine overrides |
| 2 | Compile-time embedded: `MARATHON_DEFAULT_GOOGLE_CLIENT_ID`, `MARATHON_DEFAULT_MICROSOFT_CLIENT_ID` (set at `cargo build` time) | Marathon's own image build |
| 3 | Empty | Community forks / pre-registration builds — helper returns `kind:"error", code:"oauth_not_configured"` and the QML side routes users to the classic IMAP setup |

For the Marathon project's own image (`duranium-build`), layer 2 is the
correct one: the project owns one Gmail client and one Outlook client,
their IDs are baked into the apk at build time via the APKBUILD, and
users get "Sign in with Google" / "Sign in with Microsoft" working out
of the box. Layer 1 is the override path; layer 3 is the honest "this
build hasn't shipped OAuth yet" state.

When unconfigured (layer 3), the Mail app's no-account state still
offers full classic-IMAP setup (Fastmail, iCloud, Gmail-with-app-
password, self-hosted), so a community fork is not blocked from
running Marathon Mail — only from offering one-tap Google/Microsoft.

## Status

As of the latest commit: **Marathon has not yet registered shipping
client IDs.** The project-shipped Mail app falls back to classic-IMAP
on this surface. Patrick (project maintainer) executes the playbook
below once, commits the resulting IDs into the apkbuild's build()
step, and OAuth ships from then on.

## Project-maintainer playbook (one-time per provider)

This section is for the project owner / a release maintainer; it does
not concern end users.

### Google (Gmail)

Steps as of 2026-05. Google rearranges the Cloud Console periodically,
but the OAuth concepts are stable since 2018.

1. Open https://console.cloud.google.com/ and create a project named
   `Marathon Mail` (or pick an existing one for the project).
2. *APIs & Services → Library → Gmail API → Enable*. No other API is
   needed; do not enable Drive / Calendar / Analytics.
3. *APIs & Services → OAuth consent screen*:
   - User type: **External**
   - App name: `Marathon Mail`
   - User support email: a project mailing list address
   - Logo: use the Marathon icon at `marathon-shell/assets/marathon.png`
   - Authorised domains: leave empty (installed-app, no web origins)
   - Scopes (added on the next step):
     - `https://mail.google.com/` — full IMAP + SMTP access via XOAUTH2
     - `openid`, `email`, `profile` — userinfo endpoint for the
       From: address auto-detection
   - Test users: add the maintainer's account while the app is in
     **Testing** status. Submit for verification when shipping wider
     than the test-user list. Expect a security review for
     `mail.google.com` scope (1–4 weeks typical).
4. *APIs & Services → Credentials → Create credentials → OAuth client
   ID*:
   - Application type: **Desktop app**
   - Name: `Marathon Mail (Linux)`
   - Copy the **Client ID** (looks like
     `842XXXXX-XXXXX.apps.googleusercontent.com`).
   - The Client Secret shown is **not** used (PKCE replaces it);
     marathon-mail-oauth passes an empty secret string.

### Microsoft (Outlook / Office 365 / Microsoft 365)

Steps as of 2026-05 against Microsoft Entra (formerly Azure AD).

1. https://entra.microsoft.com/ → *Identity → Applications → App
   registrations → New registration*.
   - Name: `Marathon Mail`
   - Supported account types: **Accounts in any organisational
     directory and personal Microsoft accounts** — so Outlook.com works
     alongside corporate.
   - Redirect URI: leave blank now; add in step 3.
2. Note the *Application (client) ID* — that's your value for
   `MARATHON_DEFAULT_MICROSOFT_CLIENT_ID`.
3. *Authentication → Add a platform → Mobile and desktop applications*
   → tick the `http://localhost` redirect URI. (Marathon's loopback
   binds to `127.0.0.1:<random>`; Microsoft accepts `http://localhost`
   without a port for desktop clients.)
4. Set *Allow public client flows* to **Yes** on the same Authentication
   blade. PKCE is the default token handshake mode.
5. *API permissions → Add a permission → Microsoft Graph → Delegated*:
   - `IMAP.AccessAsUser.All`
   - `SMTP.Send`
   - `User.Read`
   - `offline_access`
   For a personal-account-only build, *Grant admin consent* is not
   required. For a tenant-shipped build, it is.

## Baking the IDs into Marathon's image

Once both client IDs are registered, edit
`Marathon-Image/packages/marathon-mail-oauth/APKBUILD`:

```sh
build() {
    cd "$builddir"
    MARATHON_DEFAULT_GOOGLE_CLIENT_ID="842XXXXX-XXXXX.apps.googleusercontent.com" \
    MARATHON_DEFAULT_MICROSOFT_CLIENT_ID="4f9d3e2a-XXXX-XXXX-XXXX-XXXXXXXXXXXX" \
        cargo auditable build --frozen --release
}
```

Rust's `option_env!` macro reads both at compile time and bakes the
strings as constants in the binary. No runtime env var is needed
after that; the helper just works.

Rebuild + rebake:

```
$ bash marathon-extras/build-marathon-mail-oauth-apk.sh
$ python3 scripts/build-image.py device-qemu-aarch64 ui-marathon
```

Verify on QEMU:

```
$ MARATHON_PERM_SECRET_SERVICE=1 /usr/bin/marathon-mail-oauth \
    add --provider gmail --account-id test-account
Open this URL in your browser to authorise Marathon Mail:
https://accounts.google.com/o/oauth2/v2/auth?…
```

If you instead see

```
{"kind":"error","code":"oauth_not_configured","message":"…"}
```

then the env vars were not visible to `cargo build`, the binary was
compiled without baking them. Re-check the APKBUILD build() function
and rebuild.

## Forks / enterprise overrides

A Marathon fork or an IT department that wants to ship Marathon with
its own OAuth client (e.g. corporate tenant restriction) overrides via
runtime env var, no rebuild needed. Drop a systemd unit:

```ini
# /etc/systemd/user/marathon-mail-oauth.service.d/override.conf
[Service]
Environment=MARATHON_OAUTH_GOOGLE_CLIENT_ID=...
Environment=MARATHON_OAUTH_MICROSOFT_CLIENT_ID=...
```

or set them in the per-app launch env via the manifest's `env` block
(not yet implemented; see `docs/APP_MANIFEST_SCHEMA.md` for the
future env-injection field).

The runtime override wins regardless of what was baked at compile time.
