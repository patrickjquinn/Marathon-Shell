# Localisation

Marathon ships in English only and has no translation pipeline: no catalogs,
no loader, no language setting. The apps already mark about 1,840 strings
with `qsTr`; the shell marks 156 and leaves roughly 190 bare; the Rust
services hold about 136 user-facing strings. This sets up translation the
way the Qt and Rust ecosystems expect, so native speakers can review and
improve every language later without touching code.

## Goals

- Every user-facing string, in QML, C++ and Rust, is marked and extracted
  into a catalog that Weblate can edit.
- One system language setting. The shell switches live; apps and services
  pick it up on their next start.
- Dates, times and numbers follow the language's locale.
- German, French, Spanish and Irish ship as machine drafts, marked
  unfinished so a reviewer sees every string still needs a native eye, and
  labelled "Preview" in the language list.
- A pseudo-language exposes unmarked strings and clipped layouts.
- A lint check stops new bare strings from landing.

## Non-goals

- Translating Keel's own strings. Keel is used unmodified; its catalogs
  belong to Keel.
- Right-to-left layout. None of the first languages need it; mirroring is
  its own project.
- The onboarding language picker. The onboarding redesign builds it on
  this foundation.
- The developer test app (`apps/test`).

## Decisions

- **QML and C++: Qt's own pipeline.** `qsTr()` / `tr()` with `//:`
  translator comments and `%n` plurals; `qt_add_translations` runs
  `lupdate` into Qt `.ts` files and compiles `.qm` into each target's
  resources under `:/i18n`. Contextual `qsTr` rather than `qsTrId`: the
  apps already use it, and it needs no ID registry.
- **Catalog layout: one per component**, `translations/<component>/<component>_<lang>.ts`:
  `shell`, `silica` (Marathon.Silica, loaded by the shell and every app)
  and one per app. Each is one Weblate component.
- **Rust: Fluent**, through `i18n-embed` and its `fl!` macro, which checks
  message IDs at compile time. Files live at
  `crates/<crate>/i18n/<lang>/<crate>.ftl`, the `i18n-embed` convention,
  which Weblate reads natively. A shared `marathon-i18n` crate holds the
  language list and the selection rule.
- **The setting:** `system/language` in the shell's settings, a language
  code such as `de`, empty for the image default. Exposed as `language`
  on Settings1 so the Settings app can change it.
- **Propagation.** The shell installs its translators, sets the default
  `QLocale`, sets `LANG` and `LANGUAGE` in its own environment (which the
  sandbox passes to every app it launches) and in the systemd user
  manager's (which services read when they start), then calls
  `retranslate()` on its engine. The app runner loads the app's catalog
  and the `silica` catalog for the language in `LANGUAGE` at launch.
- **The language list** is `translations/languages.json`: code, native
  name, English name and status (`complete`, `preview`, or `pseudo`).
  `marathon-i18n` embeds it; both Settings objects expose it as
  `availableLanguages`. A `pseudo` entry is listed only when
  `MARATHON_PSEUDO_LOCALE=1`.
- **Pseudo-language `en_XA`:** accented, 35% longer, bracketed English,
  generated from the English sources by `tools/i18n/pseudo.py` for both
  formats.

## Constraints

- Machine drafts are written with `type="unfinished"` in `.ts` files and
  `# draft` above each Fluent message; nothing machine-written is ever
  marked finished.
- Translator comments say where the string appears and what any `%1`
  stands for.
- Strings are whole sentences: no concatenating translated fragments.
- Marathon's copy rules (`docs/CODING_RULES.md`) apply to the English
  source; translations follow each language's own conventions.
