# Localisation Implementation Plan

**Goal:** Every user-facing string in the shell, its apps and its services
is translatable through standard catalogs, one language setting switches
the system, and German, French, Spanish and Irish ship as reviewable drafts.

**Architecture:** Qt's `qt_add_translations` builds one `.ts` catalog per
component and embeds the `.qm` under `:/i18n`; a small C++ `Translations`
service in `shell/src/services/` installs them in the shell and the app
runner. Rust uses Fluent via `i18n-embed`, with a shared `marathon-i18n`
crate for the language list and selection. The shell owns the setting and
pushes `LANG`/`LANGUAGE` to apps and services.

**Tech Stack:** Qt 6.11 LinguistTools (`lupdate`, `lrelease`), QML `qsTr`,
C++ `QTranslator`, Rust `i18n-embed` + `i18n-embed-fl` + `rust-embed`,
cxx-qt, zbus.

**Spec:** `docs/design/2026-10-26-localisation.md`

## Global Constraints

- Catalog paths: `translations/<component>/<component>_<lang>.ts`; components `shell`, `silica`, and each app directory name under `apps/` except `test`.
- Fluent paths: `crates/<crate>/i18n/<lang>/<crate>.ftl`, English source in `i18n/en/`.
- Languages: `de`, `fr`, `es`, `ga` (status `preview`), `en` (status `complete`, the source), `en_XA` (status `pseudo`, listed only when `MARATHON_PSEUDO_LOCALE=1`).
- Setting: ini key `system/language`, property `language`, `QString`, default empty (image default, English).
- `qsTr` with a `//:` comment on every string whose meaning isn't obvious from the text; `%n` for counts; no concatenation of translated pieces.
- Machine drafts: `type="unfinished"` in `.ts`; `# draft` comment above each Fluent message.
- Follow `docs/CODING_RULES.md`; terse comments; atomic commits, no AI trailers.

## Review Focus

- Switching language while an app is open: the shell retranslates at once; the open app keeps its language until relaunched, and nothing crashes. Test in Task 2.
- A language code with no catalog for a component (a new app, or `ga` before its draft exists) falls back to English, never to raw IDs or blanks. Test in Task 2 (C++) and Task 4 (Rust).
- Plurals in Irish, which has five forms: `%n` strings resolve per Qt's Irish rule. Test in Task 6.
- Text 35% longer than English (pseudo) must not overlap or clip in the status bar, nav bar, quick settings and the Settings main page. Checked on device in Task 8.
- An empty or unknown `system/language` value (old settings files) means English with no warnings spam. Test in Task 1.

---

### Task 1: The language setting and the language list

**Files:**
- Create: `crates/marathon-i18n/` (`Cargo.toml`, `src/lib.rs`), add to `crates/Cargo.toml` workspace members
- Create: `translations/languages.json`
- Modify: `crates/marathon-shell-native/src/settings.rs` (field next to `keyboard_language`, line ~445; qproperty next to line 89)
- Modify: `crates/marathon-app-native/src/settings.rs` (mirror, next to line 291)

**Interfaces:**
- Produces (Rust): `marathon_i18n::Language { code: &'static str, native_name: &'static str, english_name: &'static str, status: Status }`, `enum Status { Complete, Preview, Pseudo }`, `fn languages() -> Vec<Language>` (pseudo entries only when `MARATHON_PSEUDO_LOCALE=1`), `fn resolve(setting: &str, env: Option<&str>) -> &'static str` (setting if listed, else the language part of `env` if listed, else `"en"`).
- Produces (QML, both Settings objects): `property string language`, `readonly property var availableLanguages` (list of `{ code, nativeName, englishName, status }`).

- [ ] **Step 1: Write failing tests in `crates/marathon-i18n/src/lib.rs`**: `resolve("de", None) == "de"`; `resolve("", Some("fr_FR.UTF-8")) == "fr"`; `resolve("xx", Some("C")) == "en"`; `resolve("", None) == "en"`; `languages()` contains `en`, `de`, `fr`, `es`, `ga` and no `en_XA` without the env var.
- [ ] **Step 2: Run** `cargo test -p marathon-i18n` — expect failures (crate empty).
- [ ] **Step 3: Implement** `languages.json` (`[{"code":"en","nativeName":"English","englishName":"English","status":"complete"}, {"code":"de","nativeName":"Deutsch",...,"status":"preview"}, {"code":"fr","nativeName":"Français"}, {"code":"es","nativeName":"Español"}, {"code":"ga","nativeName":"Gaeilge"}, {"code":"en_XA","nativeName":"[Ëñğļîšĥ]","englishName":"Pseudo","status":"pseudo"}]`), embedded with `include_str!` and parsed with `serde_json`; `resolve` per the interface.
- [ ] **Step 4: Run** `cargo test -p marathon-i18n` — PASS.
- [ ] **Step 5: Add `language` and `availableLanguages`** to both Settings objects through their existing field macros (`"system/language", "language"` in the shell; `"language"` in app-native), `availableLanguages` built from `marathon_i18n::languages()`. Extend the existing settings tests in each crate: a fresh settings file reads `language == ""`; writing `"de"` round-trips.
- [ ] **Step 6: Run** `cargo test -p marathon-shell-native -p marathon-app-native settings` and `cargo clippy -p marathon-i18n -p marathon-shell-native -p marathon-app-native -- -D warnings` — PASS.
- [ ] **Step 7: Commit** "Add a system language setting and the language list".

### Task 2: Catalogs built and loaded in the shell and the app runner

**Files:**
- Modify: `CMakeLists.txt` (find `LinguistTools`; `set(MARATHON_LANGUAGES de fr es ga en_XA)`)
- Modify: `shell/CMakeLists.txt` (`qt_add_translations(marathon-shell TS_FILE_DIR ${CMAKE_SOURCE_DIR}/translations/shell TS_FILE_BASE shell RESOURCE_PREFIX /i18n LUPDATE_OPTIONS -no-obsolete -locations relative)`; a `silica` catalog over `marathon-silica/**/*.qml`, embedded in both the shell and the runner)
- Modify: `apps/CMakeLists.txt` `add_marathon_app` (same call per app, `TS_FILE_BASE ${APP_NAME}`, dir `translations/${APP_NAME}`; skipped for `test`)
- Create: `shell/src/services/translations.h`, `shell/src/services/translations.cpp`
- Modify: `shell/main.cpp` (install at startup, before `engine.load`; reconnect on `languageChanged`)
- Modify: `tools/marathon-app-runner/CMakeLists.txt` (compile `translations.cpp`), `tools/marathon-app-runner/main.cpp` (install after the app's library is loaded, catalogs `{appDir, "silica"}`)
- Modify: `crates/marathon-shell-native/src/sandbox.rs:201` (pass `LANGUAGE` as well as `LANG`)
- Test: `tests/shell/test_translations.cpp` (+ `tests/shell/CMakeLists.txt`), fixture `tests/shell/data/i18n/test_de.ts` compiled to `.qm` by the test target

**Interfaces:**
- Consumes: `Settings.language` (Task 1).
- Produces: `class Translations : public QObject { public: Translations(QStringList catalogs, QObject *parent); bool install(const QString &code); QString code() const; signals: void installed(QString code); }` — `install` removes its previous translators, loads `:/i18n/<catalog>_<code>.qm` for each catalog (missing files are skipped silently), sets `QLocale::setDefault(QLocale(code == "en_XA" ? "en" : code))`, sets `LANG=<code>.UTF-8` and `LANGUAGE=<code>` with `qputenv`, returns whether any catalog loaded. The shell additionally calls `engine.retranslate()` and pushes `LANG`/`LANGUAGE` to the systemd user manager (`org.freedesktop.systemd1.Manager.SetEnvironment`).

- [ ] **Step 1: Write failing tests** `test_translations.cpp`: `installsTheCatalog` (install "de" with the fixture → `QCoreApplication::translate("Ctx", "Hello") == "Hallo"`); `unknownLanguageFallsBack` (install "xx" → returns false, translate returns "Hello", no warning via `QTest::failOnWarning`); `switchingReplacesTheOld` (install "de" then "en" → "Hello"); `setsLocale` (after "de", `QLocale().name() == "de_DE"`); `setsTheEnvironment` (`qgetenv("LANGUAGE") == "de"`).
- [ ] **Step 2: Run** `ctest -R Shell_Translations` — fails to build (no class).
- [ ] **Step 3: Implement** `Translations` and the CMake catalog wiring; run `cmake --build build --target update_translations` to create the empty `.ts` files and commit them.
- [ ] **Step 4: Run** `ctest -R Shell_Translations` — PASS; `cmake --build build` — the shell and runner build with the catalogs embedded.
- [ ] **Step 5: Wire the shell and runner** as in Files; in the shell, `languageChanged` → `install` → `engine.retranslate()` and the systemd environment push.
- [ ] **Step 6: Commit** "Build translation catalogs and load them in the shell and apps".

### Task 3: Mark the shell's, Marathon.Silica's and the apps' remaining strings

**Files:**
- Modify: the QML under `shell/qml/`, `marathon-silica/`, `apps/*/` (not `apps/test`) holding bare user-facing strings; user-facing C++ strings under `shell/src/` and `tools/` get `tr()`
- Create: `tests/lint/check-untranslated.py`, wired into `scripts/lint.sh` beside `check-silica-imports.sh`

**Interfaces:**
- Consumes: the catalogs from Task 2.
- Produces: `check-untranslated.py <files…>` exits 1 listing `file:line: "text"` for a string literal assigned to `text`, `title`, `label`, `description`, `placeholderText`, `valueText`, `subtitle`, `message` or a `qsTr`-less `Accessible.name`, unless wrapped in `qsTr`/`qsTrId` or the line carries `// i18n: not user-facing`.

- [ ] **Step 1: Write the checker and its test** `tests/lint/test_check_untranslated.py` (pytest, as `test_check_test_reachability.py` does): flags `text: "Hello"`; passes `text: qsTr("Hello")`; passes `objectName: "x"`; passes a line marked `// i18n: not user-facing`.
- [ ] **Step 2: Run** `python3 -m pytest tests/lint/test_check_untranslated.py` — PASS; run the checker over the tree — expect the ~330 current hits.
- [ ] **Step 3: Wrap every hit** in `qsTr` with a `//:` comment where the text alone is ambiguous. Replace hand-built English formats (`"h:mm AP"`, month and day name arrays, `"Today"`/`"Yesterday"` concatenation) with `Qt.locale()` / `Date.toLocaleString` / `qsTr` whole sentences. Split by area for parallel work: shell components; shell core/models/ui; Marathon.Silica; Settings; the other apps.
- [ ] **Step 4: Run** the checker over the tree — zero hits; `cmake --build build --target update_translations` — the catalogs gain the strings; the touched QML suites (`tests/ui`, each app's `tests/`) pass.
- [ ] **Step 5: Commit** per area: "Mark the shell's strings for translation", "…Marathon.Silica's…", "…Settings'…", "…the apps' remaining…", "Check for untranslated strings in lint".

### Task 4: Fluent in the Rust services

**Files:**
- Modify: `crates/marathon-i18n/src/lib.rs` (loader helpers)
- Create per crate holding user-facing text (`marathon-shell-native`, `marathon-app-native`, `marathon-apps`, `marathon-telephonyd`, `marathon-store-handler`, `marathon-davd`, `marathon-medialibd`, `marathon-maild`, `marathon-rt`, `marathon-weatherd`): `i18n.toml`, `i18n/en/<crate>.ftl`, a `static LOADER` and the `fl!` wrapper in the crate's `lib.rs`/`main.rs`
- Modify: each crate's user-facing strings → `fl!("message-id", args)`

**Interfaces:**
- Consumes: `marathon_i18n::resolve` (Task 1).
- Produces: `marathon_i18n::select(loader: &FluentLanguageLoader, code: &str)` (selects `code`, falling back to `en`); `marathon_i18n::current() -> &'static str` (= `resolve("", env LANGUAGE or LANG)`); in `marathon-shell-native`, a `language_changed` hook from Settings that calls `select` on its loader.

- [ ] **Step 1: Write failing tests** in `marathon-i18n`: with an in-test loader holding `en` and `de` messages, `select(&l, "de")` then `l.get("hello") == "Hallo"`; `select(&l, "ga")` (no catalog) falls back to `"Hello"`.
- [ ] **Step 2: Run** `cargo test -p marathon-i18n` — FAIL, then implement `select`/`current` — PASS.
- [ ] **Step 3: Convert each crate's strings** to Fluent messages with stable kebab-case IDs named for where they appear (`battery-low-title`, `battery-low-body = Turn on Battery Saver…`), plurals with Fluent selectors, and existing unit tests updated to read through the loader in `en`.
- [ ] **Step 4: Run** `cargo test --workspace` and `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check` — PASS.
- [ ] **Step 5: Commit** one per crate: "Translate <crate>'s messages with Fluent".

### Task 5: The pseudo-language

**Files:**
- Create: `tools/i18n/pseudo.py`, `tools/i18n/test_pseudo.py`
- Create (generated, committed): `translations/*/*_en_XA.ts`, `crates/*/i18n/en-XA/*.ftl`

**Interfaces:**
- Produces: `pseudo.py` rewrites every `<translation>` of each `*_en_XA.ts` from its `<source>` and writes each crate's `en-XA` Fluent file from its `en` one: letters accented (`a→á, e→ë, i→î, o→ø, u→ü, n→ñ, c→ç`…), padded with `~` to 135% length, wrapped in `[` `]`, placeholders (`%1`, `%n`, `{ $count }`, markup) untouched, entries marked finished.

- [ ] **Step 1: Write tests** `test_pseudo.py`: `"Hello" → "[Ĥëļļø~~]"`-shaped (bracketed, ≥135% length, no ASCII vowels); `"%n new"` keeps `%n`; `"{ $count } new"` keeps `{ $count }`; `"<b>Bold</b>"` keeps tags.
- [ ] **Step 2: Run** `python3 -m pytest tools/i18n` — FAIL, implement — PASS.
- [ ] **Step 3: Generate** the pseudo files; build; commit "Add an en_XA pseudo-language for layout checks".

### Task 6: Machine drafts for German, French, Spanish and Irish

**Files:**
- Modify (generated content): `translations/*/*_{de,fr,es,ga}.ts`, `crates/*/i18n/{de,fr,es,ga}/*.ftl`

**Interfaces:**
- Consumes: the extracted catalogs (Tasks 3–4).

- [ ] **Step 1: Write the plural test** in `tests/shell/test_translations.cpp`: `irishPluralsResolve` — install `ga`, `QCoreApplication::translate("MarathonPeek", "%n new", nullptr, n)` for n = 1, 2, 3, 7, 11 returns that form's draft text (fixture rows copied from the real `shell_ga.ts`).
- [ ] **Step 2: Draft** every string per language, each `<translation type="unfinished">` (numerus forms per Qt's rule for the language) and each Fluent message preceded by `# draft`; keep placeholders exactly; follow the `//:` comments. One catalog per worker.
- [ ] **Step 3: Validate**: `lrelease` over every `.ts` reports no errors and no placeholder mismatches; a script check that every `%1`/`%n`/`{ $x }` in a source appears in its translation; `cargo test --workspace` (Fluent files parse).
- [ ] **Step 4: Run** `ctest -R Shell_Translations` — PASS.
- [ ] **Step 5: Commit** per language: "Draft German translations for review" (and French, Spanish, Irish).

### Task 7: Language in Settings, and the translators' guide

**Files:**
- Create: `apps/settings/pages/LanguagePage.qml`, `apps/settings/tests/tst_languagepage.qml`
- Modify: `apps/settings/pages/MainPage.qml` (a "Language" entry beside Keyboard), `apps/settings/SettingsLogic.js` if it routes pages
- Create: `docs/TRANSLATING.md`
- Modify: `README.md` docs list

**Interfaces:**
- Consumes: `Settings.language`, `Settings.availableLanguages` (Task 1).

- [ ] **Step 1: Write failing tests** `tst_languagepage.qml`: lists one row per `availableLanguages` entry showing `nativeName`, with English name as the description; a `preview` row says "Preview: machine translated"; tapping "Deutsch" sets `Settings.language` to `"de"`; the current language row is highlighted.
- [ ] **Step 2: Run** the Settings suite — FAIL; implement the page with Silica `ListItem`s and a `PageHeader` "Language", and the MainPage entry — PASS.
- [ ] **Step 3: Write `docs/TRANSLATING.md`**: for developers (mark strings, `//:` comments, `%n`, Fluent IDs, `update_translations`, the lint check) and for translators (the catalog layout as Weblate components, `unfinished`/`# draft` meaning, how a reviewed string becomes finished, the pseudo-language).
- [ ] **Step 4: Commit** "Choose the language in Settings" and "Document how to translate Marathon".

### Task 8: On the device

- [ ] **Step 1:** Build and install the shell apk on the HackberryPi; in Settings, choose Deutsch. Screenshot: home, status bar, quick settings, the Hub, Settings' main page, a notification from a service after its restart. The shell switches without a restart; Settings shows German after relaunch.
- [ ] **Step 2:** With `MARATHON_PSEUDO_LOCALE=1`, choose the pseudo-language and screenshot the same surfaces; fix every clipped or overlapping label found (Review Focus 4) and every string still in plain English (an unmarked string).
- [ ] **Step 3:** Choose English again; confirm everything returns.
- [ ] **Step 4:** Run the full lint (`scripts/lint.sh`, clippy, fmt) and the touched test suites; commit fixes; bump `pkgrel`; push; check `gh run list`.
