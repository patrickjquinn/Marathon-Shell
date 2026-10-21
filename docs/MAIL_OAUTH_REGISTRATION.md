# Marathon Mail OAuth client IDs

Marathon's Gmail and Outlook sign-in flows use OAuth 2.0 PKCE
installed-app authentication. PKCE replaces the client secret with a
per-flow proof of possession, which means an OAuth client ID alone is
not a credential — it is safe to publish in an open-source binary.
This is the same pattern Thunderbird, Evolution, GNOME Online Accounts,
Geary, and K-9 Mail use.

## How client IDs resolve

marathon-maild resolves the client ID for each provider through
a three-tier ladder. Highest precedence first:

| Layer | Source | Used by |
|-------|--------|---------|
| 1 | Runtime env var: `MARATHON_OAUTH_GOOGLE_CLIENT_ID`, `MARATHON_OAUTH_MICROSOFT_CLIENT_ID` | Enterprise forks, per-machine overrides |
| 2 | Compile-time embedded: `MARATHON_DEFAULT_GOOGLE_CLIENT_ID`, `MARATHON_DEFAULT_MICROSOFT_CLIENT_ID` (set at `cargo build` time) | Marathon's own image build |
| 3 | Empty | Community forks / pre-registration builds — the provider is not offered and Mail shows only the password setup |

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
     marathon-maild sends no secret (PKCE).

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

Copy `crates/marathon-maild/oauth-clients.env.example` to
`oauth-clients.env` beside it (gitignored) and fill in
`MARATHON_DEFAULT_GOOGLE_CLIENT_ID` and `MARATHON_DEFAULT_MICROSOFT_CLIENT_ID`.
`scripts/qemu/lib/build-marathon-shell-apk.sh` passes them into the
marathon-shell build, where `option_env!` in
`crates/marathon-maild/src/oauth.rs` bakes them into marathon-maild.

With neither set, `Mail1.OAuthProviders` answers empty and Mail offers
only the password setup (Fastmail, iCloud, Gmail with an app password,
self-hosted).

Check on a device: `busctl --user call org.marathonos.Mail
/org/marathonos/Shell/Mail org.marathonos.Shell.Mail1 OAuthProviders`
lists `gmail` and `outlook` once their IDs are baked in.

## Forks / enterprise overrides

`MARATHON_OAUTH_GOOGLE_CLIENT_ID` and `MARATHON_OAUTH_MICROSOFT_CLIENT_ID`
in marathon-maild's environment win over the baked IDs, no rebuild needed:

```ini
# /etc/systemd/user/marathon-maild.service.d/override.conf
[Service]
Environment=MARATHON_OAUTH_GOOGLE_CLIENT_ID=...
Environment=MARATHON_OAUTH_MICROSOFT_CLIENT_ID=...
```
