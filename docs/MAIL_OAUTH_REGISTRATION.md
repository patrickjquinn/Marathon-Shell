# Mail OAuth client registration

Marathon's mail-oauth helper (`/usr/bin/marathon-mail-oauth`) speaks
RFC 7636 PKCE against Google and Microsoft to obtain XOAUTH2 refresh
tokens for Gmail and Outlook IMAP/SMTP. The flow is the standard
installed-app pattern: no client secret, just a public client ID + a
loopback redirect URI + PKCE.

The shipping binary reads the client IDs from environment variables so
the same binary can be redistributed under a different brand / channel
without rebuilding. Placeholder defaults (`OWN_BEFORE_SHIP-...`) cause
the helper to refuse to start with an explicit error envelope, so an
unregistered build fails loudly the first time a user taps "Sign in
with Google".

## Required environment variables

```
MARATHON_OAUTH_GOOGLE_CLIENT_ID=<your-google-client-id>
MARATHON_OAUTH_MICROSOFT_CLIENT_ID=<your-azure-client-id>
```

Production images set these via the systemd unit
`marathon-mail-oauth.service` (or the calling app-runner's environment;
the helper reads `std::env::var` at runtime so anything in the process
environment works).

## Google (Gmail) registration

Steps as of 2026-05. Google updates the console layout periodically;
the OAuth concepts have been stable since 2018.

1. Open https://console.cloud.google.com/ and pick or create a project
   for Marathon.
2. Enable the Gmail API: *APIs & Services → Library → Gmail API →
   Enable*. (You don't need any of the analytics APIs.)
3. *APIs & Services → OAuth consent screen*:
   - User type: **External** (unless your Workspace covers all your
     users)
   - App name: `Marathon Mail`
   - User support email: yours
   - Logo: optional but improves the consent dialog
   - Authorised domains: leave empty for an installed app
   - Scopes (add when prompted):
     - `https://mail.google.com/` (full read/write to verify IMAP IDLE
       works; `gmail.modify` is insufficient for label changes via
       IMAP)
     - `openid`, `email`, `profile`
   - Test users: add your test Gmail accounts while the app is in
     **Testing** status; submit for verification when shipping wider.
4. *APIs & Services → Credentials → Create credentials → OAuth client
   ID*:
   - Application type: **Desktop app**
   - Name: `Marathon Mail (Linux)`
   - Click *Create*. Copy the *Client ID* — that's your value for
     `MARATHON_OAUTH_GOOGLE_CLIENT_ID`. The *Client Secret* shown is
     **not** needed (PKCE flow); leave it stored if you want, but
     marathon-mail-oauth passes an empty secret.
5. Until verification, expect "This app isn't verified" on first
   login — that's expected for a desktop OAuth client in testing.
   For broader release submit a verification request from the same
   page (typically takes 1-4 weeks; expect a security review for the
   `mail.google.com` scope).

## Microsoft (Outlook / Office 365 / Microsoft 365) registration

Steps as of 2026-05 against the Microsoft Entra admin centre (formerly
Azure AD).

1. https://entra.microsoft.com/ → *Identity → Applications → App
   registrations → New registration*.
   - Name: `Marathon Mail`
   - Supported account types: **Accounts in any organisational
     directory + personal Microsoft accounts** (so Outlook.com works
     alongside corporate)
   - Redirect URI: leave blank now; we'll add a loopback one in step 3.
2. Once created, note the *Application (client) ID* — that's your value
   for `MARATHON_OAUTH_MICROSOFT_CLIENT_ID`.
3. *Authentication → Platform configurations → Add a platform → Mobile
   and desktop applications* → tick the
   `http://localhost` redirect URI option. We also need a wildcard
   loopback because marathon-mail-oauth binds to `127.0.0.1:0` (a
   random port chosen at flow time). Microsoft accepts
   `http://localhost` without a port for desktop clients — that's the
   one to keep.
4. Set *Allow public client flows* to **Yes** under the same
   Authentication blade. PKCE is the default token-handshake mode.
5. *API permissions → Add a permission → Microsoft Graph → Delegated*:
   - `IMAP.AccessAsUser.All`
   - `SMTP.Send`
   - `User.Read`
   - `offline_access`
   Click *Grant admin consent* if you're shipping for a tenant; for a
   personal-account-only build it's not required.
6. *Manifest* — confirm `signInAudience` is
   `AzureADandPersonalMicrosoftAccount`. For pure-corporate builds use
   `AzureADMyOrg` and the `common` endpoint URL in the helper will
   still work as long as you replace it with `organizations`. (We
   default to `common`.)

## After registration

Set the env vars on the image:

```
# /etc/marathon/mail-oauth.env  (or wherever systemd loads from)
MARATHON_OAUTH_GOOGLE_CLIENT_ID=842XXXXX...apps.googleusercontent.com
MARATHON_OAUTH_MICROSOFT_CLIENT_ID=4f9d3e2a-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

Reload the systemd user instance and reauthenticate from the Mail app.

## Verifying the registration

From inside the QEMU image:

```
$ MARATHON_PERM_SECRET_SERVICE=1 \
  MARATHON_OAUTH_GOOGLE_CLIENT_ID=... \
  /usr/bin/marathon-mail-oauth add --provider gmail --account-id test
Open this URL in your browser to authorise Marathon Mail:
https://accounts.google.com/o/oauth2/v2/auth?…
```

If you instead see

```
{"kind":"error","code":"io","message":"… still the placeholder …"}
```

the env var is unset or still `OWN_BEFORE_SHIP…`. Fix that and retry.
