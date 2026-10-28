<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# Pilot

Pilot is Marathon's assistant, built to Shipwright's Pilot spec (`docs/specs/pilot.md` in Shipwright, where Pilot began). It came into Marathon from Shipwright 7a6c40a8 with the Marathon adapters, direct mode, on-screen context and local mode; the Sailfish adapters are still in it.

| Path | What |
| --- | --- |
| `crates/pilotd/` | `pilotd`, the session service `org.shipwright.Pilot` (Rust, zbus), packaged as `shoal-pilotd`; its unit, D-Bus activation file, Marathon configuration and shell admission in `data/` |
| `apps/pilot/` | `shoal-pilot`, the Pilot app (Keel QML in `ui/`, CXX-Qt), packaged as `shoal-pilot` |
| `crates/keel-mcp/`, `crates/keel-actions-schema/` | `keel-mcp`, the apps' Keel Actions as one MCP server (spec section 9), and the schema it validates with |
| `tools/keel-launcher/` | The build helpers the app includes: linking Keel's SailfishApp, compiling the QML ahead of time |
| `crates/pilotd/redaction-cases.json` | Redaction cases run by pilotd's tests |

Speech (`voice/`, `piper/`), Pilot Lite, the Lipstick pieces and the RPM packaging stayed in Shipwright. On Marathon pilotd answers with the model on the phone (`[local]`: marathon-llm's llama-server, its embeddings to pick tools, marathon-websearch) unless direct mode (`[direct]`, the owner's own Groq and Jev keys) is set up; there is no relay and no licence.

## Build and test

pilotd and keel-mcp are members of the workspace in `crates/`:

```
cargo build --manifest-path crates/Cargo.toml -p pilotd -p keel-mcp
QT_QPA_PLATFORM=offscreen cargo test --manifest-path crates/Cargo.toml -p pilotd -p keel-mcp -p keel-actions-schema
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --locked -- -D warnings
```

The bus tests need `dbus-daemon` (each starts its own, marathon-rt's `testing::PrivateBus`) and are skipped without it unless `MARATHON_TEST_STRICT` is set. They use no keys and no network: Jev, the LLM endpoint and the Lighthouse scorer are a local fake HTTP server (`crates/pilotd/tests/common/mod.rs`). `spawns_the_keel_mcp_program` runs the real `keel-mcp` once `cargo build -p keel-mcp` has.

The app is a Cargo workspace of its own (`apps/pilot/Cargo.toml`): it links Keel's SailfishApp (`KEEL_SAILFISHAPP_INCLUDEDIR`, `KEEL_SAILFISHAPP_LIBDIR`; see `tools/keel-launcher/link_sailfishapp.rs`). `scripts/qemu/lib/build-pilot-apk.sh` builds all three packages from this tree.

One turn without D-Bus, against whatever the config points at:

```
pilotd --data-dir /tmp/pilot --ask "set a timer for 10 minutes"
```

## pilotd

A turn (spec section 4):

1. **Redact** (`redact.rs`). Phone numbers, email addresses, postal addresses (English, Nordic and French/Spanish street forms, UK postcodes, Eircodes, five-digit codes with a town), contact names from the address book (full name, and the first name alone when it has three or more letters) and account numbers (IBANs, Luhn-valid card numbers, digits after "account", "sort code", "IBAN", "card", "reference" and similar) become `<PHONE_1>`, `<EMAIL_1>`, `<ADDRESS_1>`, `<CONTACT_1>`, `<ACCOUNT_1>`. The map stays in memory for the turn; its `Debug` output hides the values. Model text and tool arguments get the originals back on the device (`restore`, `restore_json`); tool results are redacted again with the same map before they go back to the model.
2. **Decide** (`jev.rs`). One request with the section 5.1 question set: `intent` (Choice over the 13 intents), `needs_generation` (Noul), `ambiguity` (Score). Answers are type-checked: every question answered, probabilities in [0, 1], options from the question, scores inside the legend.
3. **Route** (`route.rs`), section 5.2 top to bottom, thresholds from config:
   - confidence >= 0.85, needs_generation < 0.3, ambiguity < 1.0: deterministic handler;
   - ambiguity >= 1.0: one templated clarifying question (the answer is joined to the first utterance and handled locally, no second Jev call);
   - `open_ended` or needs_generation >= 0.6: Qwen;
   - anything else: Qwen with Jev's top two intents as hints.
   A confident intent without a deterministic handler in this build (call, message, calendar_add, device_toggle, navigation) goes to Qwen with that intent as the hint.
4. **Act.** Handlers (`intents.rs` for slots, `system_tools.rs` for execution) cover the five spike intents: timer, alarm, reminder, media, calendar query, plus cancel. They call the same validated system tools Qwen calls.
5. **Qwen** (`llm.rs`, `pipeline.rs`). OpenAI-compatible chat completions with the tool registry. `reasoning_effort` is `none` for conversation, `low` for tool loops, `medium` when the user asks to "work this out"; the values are config. Every tool call is parsed and validated against its JSON Schema (`schema.rs`, `tools.rs`); an invalid call goes back to the model once with the validator's message, a second invalid call ends the turn with "Pilot could not complete that request." Destructive and outbound calls (send, call, calendar add, flight mode, and any MCP tool with `destructiveHint` or `openWorldHint`) stop at a **confirmation card**; `Confirm(id, true)` re-validates and runs it, a card is good for one answer and five minutes.
6. **Log** (`store.rs`). Every remote call: timestamp, provider, purpose, request bytes, reply bytes, latency, result (`ok`, `http-429`, `transport`, `region-blocked`, `offline`, ...). Never the payload. A separate decision log keeps each Jev answer (top intent, confidence, second intent, needs_generation, ambiguity), the route and the outcome (`done`, `confirmed`, `declined`, `failed`, `dropped`, `corrected` when the next turn cancels it), for threshold calibration. Both are exportable as one JSON document and wiped together (`secure_delete`, WAL truncated). Each keeps 90 days and at most 5000 rows (`LOG_KEEP_DAYS`, `LOG_KEEP_ROWS`), trimmed as rows are added.

Without the network (privacy switch, text consent off, or Jev unreachable), `intents::local_intent` recognises unambiguous timer, alarm, reminder, media, calendar and cancel phrasings and runs them through the same tools.

| Module | Role |
| --- | --- |
| `redact.rs` | PII redactor and placeholder map |
| `jev.rs` | `JevClient`: `HttpJev` (hosted Jev) and `ScoreJev` (Lighthouse scorer over SGLang `/v1/score`) |
| `llm.rs` | `LlmClient`: `OpenAiClient` with tools, JSON mode, `reasoning_effort`, region check |
| `remote.rs` | The only HTTP path: direct mode's keys, egress logging, offline refusal, abandon on privacy switch |
| `direct.rs` | Direct mode: the owner's Groq and Jev keys, requests shaped as the relay shaped them; local mode's region stamp |
| `route.rs` | Section 5.2 thresholds |
| `intents.rs` | Local slot parsers and offline intent recognition (English) |
| `schema.rs` | JSON Schema subset validator; refuses schemas it cannot enforce |
| `tools.rs` | Registry: model-safe names, validation, output schemas, confirmation policy |
| `system_tools.rs` | Section 6.2 system tools over the adapters |
| `adapters/` | Marathon's shell services (`marathon.rs`) when `org.marathonos.Shell` is on the bus; else timed, MPRIS, mkcal, qtcontacts-sqlite, oFono, ConnMan, systemd voice unit |
| `privacy.rs` | Privacy switch sources and the offline state |
| `settings.rs` | Per-capability consent and backend choice |
| `store.rs` | Egress and decision logs and the triage list (SQLite, 0600) |
| `triage.rs` | Proactive triage, the notification monitor and the calendar watch |
| `events.rs` | Pilot in Lipstick's Events view: the widget's summary, the notification fallback |
| `photo.rs` | Camera photos checked and stripped of metadata before upload |
| `calibrate.rs` | `pilotd --calibrate`: the section 5.2 thresholds against logged outcomes |
| `mcp.rs` | MCP client, Keel Actions as registry entries, plan prechecks |
| `pipeline.rs` | The turn |
| `dbus.rs` | `org.shipwright.Pilot1` |

### D-Bus interface

`org.shipwright.Pilot` on the session bus, object `/org/shipwright/Pilot`, interface `org.shipwright.Pilot1`. Structured values are JSON strings.

| Member | Signature | Meaning |
| --- | --- | --- |
| `Ask(text, spoken)` | `sb -> s` | One turn; returns `{"turn", "route", "cards": [...], "spoken"}` |
| `Confirm(id, approved)` | `sb -> s` | Answers a confirmation card |
| `Listen()` | `-> s` | A push-to-talk turn through pilot-voice |
| `Look(question, jpeg)` | `say -> s` | A camera turn with the photo the person took |
| `Triage(limit)` | `u -> s` | Triaged events, newest first; 0 for all |
| `OpenEvents()` | | Pilot's Events view widget or entry was tapped: mark seen, open the app's events page |
| `EventsSummary()` | `-> s` | For the widget: `{"summary", "titles"}` of triage news, or `{}` |
| `ShowSheet()` | | The system-wide gesture (`shoal-pilot-gesture-patch`): bring up the app's sheet |
| `Settings()` | `-> s` | Consent per capability, backend, available backends, offline |
| `SetConsent(name, on)` | `sb` | `text_qa`, `voice_cloud`, `vision`, `triage`, `cloud_asr`, `spoken_nudges` |
| `SetBackend(name)` | `s` | `standard` or `lighthouse` |
| `SetLocale(name)` | `s` | The person's locale (`de_DE`), sent by the app when it connects: the language Pilot answers in, imperial weather units for US, LR and MM, place names and dates in that language. Without it, pilotd's `LC_ALL`/`LC_MESSAGES`/`LANG`, else English |
| `EgressLog(limit)` | `u -> s` | Newest first; 0 for all |
| `Export()` | `-> s` | Egress and decision logs and the triage list, `"format": "shoal-pilot-export/1"` |
| `Wipe()` | | Deletes the logs, the triage list, pending cards and the last response |
| `Offline` | property `b` | Privacy switch engaged |
| `LastResponse` | property `s` | Headline of the last turn, for the cover |
| `EventsRequested` | property `u` | Counts `OpenEvents`; a running app shows its events page on change |
| `SheetRequested` | property `u` | Counts `ShowSheet`; a running app opens its sheet on change |
| `TurnFinished(result)` | signal `s` | Every turn and confirmation |
| `TriageAdded(item)` | signal `s` | One newly triaged event |

Cards (`kind`): `response` (`text`, `source`: handler, local, qwen), `clarify` (`text`, `intent`), `confirm` (`id`, `title`, `detail`, `tool`, `destructive`, `outbound`), `camera` (`text`, `question`: open the viewfinder, then `Look` with the photo and that question), `offline` (`text`), `error` (`text`).

Sandboxed callers need the `ShoalPilot` Sailjail permission (`pilotd/sailjail/ShoalPilot.permission`). `pilotd` itself is an unsandboxed user service, as the Shoal Push distributor is: it talks to timed, oFono and ConnMan on the system bus and reads the calendar and contacts databases, which no Sailjail profile combines (spec section 8.1).

### Backends and processing region

`pilotd` holds no API key of its own. In local mode the model and the embeddings are servers on the phone and nothing leaves it; in direct mode the owner's keys (`$XDG_CONFIG_HOME/shoal-pilot/keys.env`, refused unless 0600) go each to its own upstream, Groq's chat completions and Jev, with the requests shaped as Shipwright's relay shaped them (`direct.rs`).

- **Jev wire format.** The request is section 5.1 verbatim. The reply format is not in the spec and Jev is waitlist-only, so `jev::parse_answers` accepts `{"answers": {...}}` or a bare map, a choice as `{"distribution": {option: p}}` or `[{"option", "p"}]` with optional `confidence`, a score as `value` or `position`, a noul as `p` or `probability`. Confirm against Jev's documentation on access.
- **Processing region, fail closed.** Pilot uses Groq's public endpoint, which processes in the United States (decided 4 October 2026; Groq's EU region is an Enterprise option Pilot does not wait for). The relay, the only thing that talks to Groq, stamps every LLM reply with `x-pilot-processing-region` set to the region of its upstream (`us`). `pilotd` drops any reply without that header or with a region outside `allowed_regions` (default `["eu", "us"]`), logs `region-blocked`, and shows "The answer was blocked because Pilot could not confirm where it was processed." The header name and allowed values are config: `allowed_regions = ["eu"]` accepts EU processing only (an EU upstream or Lighthouse). The egress log names the provider `groq`.
- **No relay.** Without a configuration the model on the phone answers. Marathon's `/etc/shoal-pilot/pilotd.toml` turns local mode on explicitly; `[local] enabled` wins over `[direct]`.
- **Lighthouse.** `[backends.lighthouse]` with `jev.kind = "score"`: each question becomes one `/v1/score` request whose prompt lists the options with labels; SGLang returns the softmax restricted to the label tokens (`apply_softmax: true`). Noul uses the yes/no tokens, Score reports the probability-weighted legend position. Label token ids depend on the scorer's tokenizer and are config. `SetBackend("lighthouse")` switches both clients at once.

Configuration: [`crates/pilotd/pilotd.example.toml`](../../crates/pilotd/pilotd.example.toml), read from `$XDG_CONFIG_HOME/shoal-pilot/pilotd.toml`, else `/etc/shoal-pilot/pilotd.toml`. Endpoints, model ids, effort values and thresholds are all there; plain `http://` is refused except to the local machine.

### Privacy switch

The Jolla Phone's switch is on the **session bus**: service `org.sailfishos.privacyswitch`, object `/privacyswitch`, interface `org.sailfishos.privacyswitch`, method `privacyModeActive() -> b`, signal `privacyModeActiveChanged(b)` (Sailfish OS 5.2.0.13 and later). This comes from the Sailfish forum ("The free association Privacy Toggle thread"), not from Jolla's documentation. The hardware also sends `KEY_F22` (engaged) and `KEY_F21` (released) on an input device, which needs the `input` group, so `pilotd` uses D-Bus.

When engaged: the offline state flips, every remote client refuses new requests, requests in flight are abandoned at once (no reply is read), pending confirmation cards and clarifications are dropped, `shoal-pilot-voice.service` is stopped through the systemd user manager, and `Offline` changes on D-Bus. Timers, alarms, reminders, media and calendar queries still work from text. A missing switch service means no switch; any other failure to read it is treated as engaged.

`[privacy] source` selects `sailfish` (default), `none`, or `file:PATH` (a file holding `1` or `0`, polled every 500 ms: for tests, and for wiring the input event through a udev rule if a device lacks the D-Bus service).

### Sailfish services used

| Tool or handler | Service | How |
| --- | --- | --- |
| `timer.set`, `alarm.set`, `reminder.create` | timed, `com.nokia.time` on the system bus | `add_event` with timed's `event_io_t`, built as the Clock app's `Nemo.Alarms` builds countdowns and single-shot alarms, so they show in Clock. Reminders are one-off alarms with Pilot's title. |
| `media.control` | MPRIS 2, session bus | The playing player, else a paused one, else the first |
| `calendar.query` | mkcal's SQLite store | Read-only; mkcal has no query D-Bus API and its library is Qt 5 |
| `contacts.lookup`, redactor names | qtcontacts-sqlite's database | Read-only, names cached for a minute |
| `call.dial` | oFono `VoiceCallManager.Dial`, system bus | Confirmation card always |
| `device.toggle` | ConnMan technologies and `OfflineMode` | Flight mode needs a card |
| `camera.capture` | The app's viewfinder | Offered to the model; the pipeline answers it with a camera card, and nothing is captured until the person presses the shutter |
| Triage: notifications and SMS | `org.freedesktop.Notifications` (Lipstick) | A monitor connection (`BecomeMonitor`) watching `Notify` calls; commhistoryd posts SMS and chat messages through it with `x-nemo.messaging.*` categories |
| Triage: calendar changes | mkcal's SQLite store | Polled every minute for the coming week |
| `messages.send`, `calendar.add`, `notifications.read` | | Declared, not offered to the model yet: SMS must go through Telepathy to appear in Messages; mkcal writes need a Qt 5 helper; reading notifications back needs Lipstick's notification list |

### What runs in the background

- **pilotd** starts by D-Bus activation (the app, the Events widget, a trigger) and then stays up for the session. It does not exit when idle, on purpose: it holds state that would be lost or broken by an exit and a later re-activation. In memory: the conversation so far (follow-up questions), the timers and alarms it set (so "cancel that timer" and "make it 20 minutes" work), open confirmation cards and a pending clarifying question, and the last response the app shows. Running tasks: the notification monitor and calendar watch for proactive triage when that is switched on, the privacy-switch watch (it closes the microphone), the wake-word subscription when a detector is configured, and the keel-mcp child. Idle, it does no work: the calendar watch skips mkcal entirely while triage is off and, while on, opens the database only after its file changed (`Calendar::stamp`); its timer is tokio's, which does not wake a suspended phone. A keel-mcp that keeps dying is restarted once at once, then after 5 s, 10 s, ... up to 10 minutes (`mcp_restart_backoff`).
- **pilot-voice** (D-Bus activated) exits after five minutes with no turn and no download, unless a wake-word detector is configured; the next spoken turn activates it again.
- **pilot-tts** (socket activated) exits after five minutes with no connection and kills its warm Piper run; the socket starts it again. pilotd sends `{"stop": true}` only while an utterance it sent is unanswered, so interrupting nothing never starts it.
- The pilotd and pilot-voice units have `StartLimitIntervalSec=300` and `StartLimitBurst=5`, so a failing one gives up instead of restarting forever.

## Memory (`pilotd/src/memory.rs`, `intents::memory_command`)

"Remember that my partner loves orchids" is kept on the phone (`memory` table) with no model and no network; "what do you remember?" lists, "forget about the orchids" forgets the best word match, and Settings lists everything with Forget on each. The model also has `memory.remember` for facts said other ways ("bear in mind that …"). The newest 30 facts go to Qwen with a typed question as context, redacted like the question and marked as the person's own words; Export includes them and Delete wipes them.

## Web search (`pilotd/src/web.rs`)

`web.search` calls the relay's `/v1/search` (Cloudflare Web Search; providers that keep no data). It is read-only, so no card, and its results reach the model only as untrusted content, which makes every later action in the turn need a yes. The query goes out as the model wrote it from the redacted question: placeholders are dropped, never restored. Jev's `needs_web` question decides when Pilot searches before Qwen answers (threshold `web_first`, 0.6): a small model answers news, scores and office holders from memory if left to choose.

`pilotd` is installed setgid `privileged`, as Sailfish's own services that read user data: the calendar (mkcal) and the address book (qtcontacts-sqlite) are under `~/.local/share/system/privileged`, mode 770.

## Keel Actions as tools (`pilotd/src/mcp.rs`)

Every Keel app's actions reach Pilot through `keel-mcp` (`keel/actions/mcp`, spec section 9.4). pilotd starts it as a child process (`[mcp] command`, default `/usr/bin/keel-mcp --stdio`; skipped when it is not installed) and talks MCP to it with its own small client: JSON-RPC 2.0, one message per line, `initialize`, `tools/list` (with pagination, again every 15 s so new apps appear) and `tools/call`. Nothing in pilotd is specific to keel-mcp beyond the `org.shipwright.keel/*` metadata it reads, so another MCP server on a byte stream works the same way.

- **Names.** keel-mcp exposes `<app-id>__<name>` and keeps the manifest's `<app-id>/<name>` in `_meta`; the registry uses the manifest name as canonical and its own model-safe name for the model (`org.example.notes/notes.create` is `org_example_notes_notes_create`).
- **Rules (section 9.3).** Arguments are validated against `inputSchema` in pilotd before keel-mcp sees them (keel-mcp validates again, and validates results against `outputSchema`). `readOnlyHint` never needs a card; `destructiveHint`, `openWorldHint` and the manifest's `confirm` flag always do. `x-keel-*` schema keywords are annotations; a tool whose schema uses anything the validator cannot enforce is not offered.
- **Sensitive results.** A result keel-mcp marks sensitive (Keys' search, for example) is shown to the person on a card and replaced by "shown to the person" in what the model gets.
- **Untrusted results.** A result keel-mcp marks untrusted (`_meta["org.shipwright.keel/untrusted"]`, or a plan step marked `untrusted`: a web page Pacific read, someone's message) reaches the model only inside its tool result, as `untrusted_content` with a note that it is data and never instructions; its text is never the summary, and it never goes into the system or user messages. For the rest of the turn every action that changes something, even one that needs no card on its own, waits for the person's yes, so text in a page cannot act through Pilot.
- **Two-stage routing (section 9.5).** With app tools present, the first Jev request also asks a `domain` Choice: one option per system area (calendar, messaging, media, system, vision) and one per Keel app, each described by its tools' titles. The model then sees only that domain's tools (the top two when Jev's confidence is under 0.6). A domain with more than six tools gets stage two: a second Jev request, a Choice over that domain's actions with their descriptions as the criteria, and only the three likeliest are offered. Without app tools the first request is unchanged.
- **Plans (section 9.7).** `keel__plan.run` is offered with any app's tools. When the model calls it, pilotd first runs `keel__plan.validate`: an invalid plan (unknown tool, wrong types, a bad entity reference) goes back to the model like an invalid call, once. A valid plan with any step that needs the person's yes gets one confirmation card listing every step ("1. notes.create; 2. notes.delete (needs your yes)"); after Allow, pilotd runs it with `confirmed`. keel-mcp stops at the first failing step and reports which steps ran.

Tests (`pilotd/tests/mcp.rs`) run the real keel-mcp server in process over a pipe, with a stand-in app behind it: Keel's golden notes manifest through two-stage routing, invalid arguments, the destructive card, a two-step plan with one card, an invalid plan, untrusted content kept as data with the next action behind a card; the Shoal apps' real manifests as their builds generate them (`target/debug/keel-actions`: Keys, Mail, Migrate, Reef, iCloud, 17 tools) with their confirmation rules and Keys' sensitive search; and the keel-mcp program itself over stdio on a private bus. The last two are skipped when those have not been built.

Not yet: `KeelContext` (on-screen awareness needs the foreground app, which only Lipstick knows), entity resources in prompts, and the personal index of section 9.7.

## Proactive triage (`pilotd/src/triage.rs`)

Spec section 5.3, opt-in through the `triage` consent and off while the privacy switch is on. Each new notification, SMS or calendar change gets one Jev request (purpose `triage`): Noul `worth_interrupting`, Choice `bucket` (`act_now`, `today`, `later`, `ignore`) and Score `urgency` (routine, time-sensitive, urgent). Title and body are redacted first (cut to 500 characters each); the app name and the source are sent as they are.

- **Sources.** A monitor connection on the session bus sees every `org.freedesktop.Notifications.Notify` call; Sailfish's preview hints (`x-nemo-preview-summary`, `-body`) stand in when summary and body are empty. Battery, USB, transfer, connectivity and warning categories, transient notifications and Pilot's own are skipped. The calendar is polled every `[triage] calendar_poll_secs` (60) for the coming week; events added, moved or removed since the last poll are triaged (the first poll is only the baseline).
- **Cost.** An identical event within ten minutes is triaged once, and at most `[triage] per_hour` (60) requests go out in any hour; past that, events are not triaged.
- **Results** stay on the device: the `triage` table (newest 200, with the real title and body), `Triage(limit)` and the `TriageAdded` signal for the Events list, included in the export and deleted by Wipe.
- **Nudges.** Nothing is spoken unless `worth_interrupting >= [triage] nudge_at` (0.9) and spoken nudges are on; then pilot-tts says where it came from and the title ("Message: Anna Virtanen"), never the body.

## Camera turns (`pilotd/src/photo.rs`)

Spec phase 4, opt-in through the `vision` consent. A camera question ("what am I looking at", Jev's `camera_vision` intent, or the model calling `camera.capture`) returns a `camera` card; the app opens the viewfinder (`ui/pages/CameraPage.qml`, QtMultimedia), and nothing is captured until the person presses the shutter. The app scales the photo to 1280 pixels on its long side and re-encodes it with Qt, which applies the EXIF orientation and writes no metadata (`keel_prepare_photo`, `app/cpp/launcher.cpp`), sends the bytes with `Look(question, jpeg)` and deletes both files. pilotd does not rely on that: it walks the JPEG's segments without decoding it, refuses anything that is not a JPEG, is over 1600 pixels on a side or 1.5 MB, and drops every APP0 to APP15 segment (EXIF, XMP, ICC, maker notes), every comment, and anything after the first image (where multi-picture files keep more images). The redacted question and the photo go to Qwen with no tools and thinking off (purpose `vision`).

## Threshold calibration (`pilotd --calibrate`)

Spec section 5.2 asks for the thresholds to be calibrated against logged outcomes before release. `pilotd --calibrate` reads the decision log on the device and prints, per route, the turns and how many were corrected, cancelled or declined, and for the deterministic route the same by intent confidence in 0.05 bands from the current threshold. It suggests the lowest `intent_confidence` at which handler turns are corrected at most 5% of the time over at least 30 turns. It only keeps or raises the value: below the threshold turns go to Qwen, so the log has no handler outcomes there. Nothing is sent; testers share the report if they choose.

## The app (`app/`, `ui/`)

`shoal-pilot` is a Keel app like Shoal Keys: a CXX-Qt executable shared object (`app/`, its own Cargo workspace) that loads `ui/` through Keel's SailfishApp view and exposes the `Pilot` singleton (`import Shipwright.Pilot 1.0`). The singleton is a thin client of `org.shipwright.Pilot1` (`app/src/client.rs`): turns run on a worker thread and come back as `turnFinished(json)`, everything else is a quick call; a watcher thread follows `Offline` and `LastResponse` and reconnects when pilotd (re)appears. The app holds no state of its own beyond the conversation on screen.

| File | What |
| --- | --- |
| `ui/pages/MainPage.qml` | The conversation and the sheet: a docked panel at the bottom edge with the text field, send and mic. Swiping up from the bottom edge opens it when it is closed. Confirmation cards show the action, mark outbound ones ("leaves this phone") and take Allow or Cancel once. An offline banner while the privacy switch is engaged; the mic is disabled then. |
| `ui/components/NowView.qml` | The home before anything is asked (pilotd's `Now`, read on the phone): a greeting with some personality ("Hello, night owl", "Morning, Patrick" with the name set in Settings, "Patrick returns!" after days away) and the date, running timers, alarms and reminders, the next events, triage that needs the person, and four suggestion tiles (`SuggestionTile.qml`) |
| `ui/components/TimerCard.qml`, `ClockCard.qml`, `AgendaCard.qml` | Typed cards: a timer counting down in a ring with +1 min and Cancel (`ExtendTimer`, `CancelClock`), an alarm or reminder with its time, how far off it is and Cancel, an agenda |
| `ui/components/AnswerCard.qml` | A written answer: paragraphs and bulleted lines, the web pages it came from as chips (tap to open), where it was made and how long it took, and follow-up questions as rows |
| `ui/components/StageLine.qml` | What Pilot is doing during a turn (`TurnProgress`): thinking, searching the web for what, reading which sites, writing |
| `ui/components/Orb.qml` | Pilot's presence: a lit sphere in the highlight colour that breathes when idle, swells with the voice and sends out ripples while listening (pilot-voice's `Level`, passed on as `TurnProgress` stage `level`), and turns an arc while thinking. Small with a mic in the bar (tap to talk); large in the listening panel, with "Listening…" then "Got it…" while the phone recognises the words |
| `ui/components/MemoryCard.qml` | What Pilot remembers: a fact just kept (Undo), the list (Forget on each), one just forgotten |
| `ui/components/Glass.qml`, `Chip.qml` | The card surface and the pill used for chips |
| `ui/components/TurnCard.qml` | The user's words, and the cards without a design of their own (clarify, confirm, camera, offline, error) |
| `ui/cover/CoverPage.qml` | A running timer counting down in a ring; else the next alarm or reminder and the last answer; type and talk actions |
| `ui/pages/CameraPage.qml` | The viewfinder for a camera turn (QtMultimedia, loaded only when opened): a question field and the shutter |
| `ui/pages/OnboardingDialog.qml` | First-run opt-in (spec section 10): what stays local, what goes where, accept or "local only" |
| `ui/pages/SettingsPage.qml` | Per-capability consent (typed and spoken questions, camera, triage, cloud speech recognition, spoken nudges), backend (standard or Lighthouse), egress log, export to `~/Downloads/pilot-export-<time>.json` (0600), delete with a remorse timer |
| `ui/pages/EgressLogPage.qml` | Every remote call: purpose, provider, sizes, latency, result |
| `ui/pages/TriagePage.qml` | Proactive triage results, the in-app stand-in for the Events view tab |
| `ui/cover/CoverPage.qml` | State (offline, thinking) and the last response; cover actions: type (the sheet, keyboard up) and speak; offline, type only |

Sailjail: `Permissions=ShoalPilot;Downloads;Camera` (`app/packaging/shoal-pilot.desktop`). The camera is used only on the viewfinder page. The app never touches the network, microphone or audio; pilotd and its helpers do.

**Lipstick, not the app.** Two surfaces in spec section 8.2 belong to the home screen ([`lipstick/README.md`](lipstick/README.md)). The Events view gets a Pilot widget at its top, registered in Lipstick's widget registry as Jolla's Weather widget is, so no patch is needed: "1 to act on now, 2 for today", which opens the app's events page (`EventsSummary`, `OpenEvents`, `--events`). The system-wide gesture, a longer, quicker swipe up from the bottom edge (`ShowSheet`, `--sheet`), is a two-hunk change to the home screen's `compositor.qml` that the package `shoal-pilot-gesture-patch` applies itself, with no Patchmanager. It applies only where the change fits exactly (a dry run), and is put back on removal and around home-screen updates. The app also has the edge swipe inside its own window.

The app's Sailfish smoke test (`app/tests`) stayed in Shipwright.

## Speech (`voice/`)

Not part of Marathon: `voice/` stayed in Shipwright, and Marathon builds neither executable. What follows is how it works there.

Two executables from one standalone Cargo workspace (`shoal/pilot/voice`, excluded from the root workspace because whisper.cpp builds with CMake):

**`pilot-voice`** serves `org.shipwright.Pilot.Voice` (`org.shipwright.Pilot.Voice1` at `/org/shipwright/Pilot/Voice`) on the session bus; only pilotd calls it. `Listen()` opens the microphone through PulseAudio's simple API (`pulse.rs`, five FFI calls, no binding crate), lets the VAD bound one utterance, closes the microphone, and transcribes it; `Cancel()`, `Status()`, `DownloadModel(size)`, a `State` property, a `Level` signal (the microphone's level, 0 to 1, about 16 a second while listening, for the app's orb) and a `WakeWord` signal complete it. `--input FILE` reads a WAV as the microphone, in real time. It is D-Bus activated (`shoal-pilot-voice.service`), so the microphone is untouched until the first spoken turn, and pilotd stops the unit when the privacy switch engages.

- **VAD** (`vad.rs`): an energy detector with an adaptive noise floor in 30 ms frames, 300 ms preroll, 900 ms end silence (configurable), 5 s no-speech timeout, 15 s cap. Cheap enough for the A55 cores and needs no model. The spec names Silero or WebRTC VAD; either fits behind the `Vad` trait if this proves too simple on the phone's microphones.
- **ASR** (`asr.rs`): whisper.cpp (MIT) through whisper-rs (Unlicense), CPU only: no GPU, BLAS or OpenMP back ends; built twice for the phone (`rpm/cross-build.sh`, `voice/src/cpu.rs`): `/usr/bin/pilot-voice` with `GGML_CPU_ARM_ARCH=armv8-a`, which runs on every phone we target (the Xperia 10 II's Snapdragon 665 is ARMv8.0 with no dot product), and `/usr/libexec/shoal-pilot/pilot-voice-armv8.2` with `armv8.2-a+dotprod`; the first `exec`s the second at start when `/proc/cpuinfo` lists `asimddp` (`PILOT_VOICE_NO_DISPATCH=1` keeps the plain build, for comparing them). ggml's own run-time dispatch (`GGML_BACKEND_DL`, `GGML_CPU_ALL_VARIANTS`) needs shared libraries, which whisper-rs-sys 0.15's build script cannot produce. `NoCpu` now comes only from the ARMv8.2 build run by hand on a processor without dot product. Bindings are the pre-generated ones (`WHISPER_DONT_GENERATE_BINDINGS=1`), so no libclang is needed.
- **Model size by power state** (`power.rs`): base by default; tiny when the battery is under 20 % and not charging, or the hottest thermal zone is over 45 °C (sysfs `power_supply` and `thermal`); whatever is installed if the choice is not.
- **Models** (`models.rs`): never shipped, never in the repository. `pilot-voice --download tiny|base` (or `DownloadModel`) fetches whisper.cpp's ggml file from its Hugging Face repository with `curl`, checks the SHA-256 published there, and only then moves it into `$XDG_DATA_HOME/shoal-pilot/models/`. English-only by default; `--multilingual` for other languages.
- **Push-to-talk and wake word** (`wake.rs`): push-to-talk is the UI's mic button and the cover action (pilotd's `Listen`). The wake word is an optional hook: `--wake-command CMD` runs a detector (an openWakeWord runner pinned to the A55 cores, say) and each line it prints fires `WakeWord`, on which pilotd runs a spoken turn; the detector is paused (SIGSTOP) while a turn has the microphone. No detector is shipped.

**`pilot-tts`** speaks on a Unix socket, `$XDG_RUNTIME_DIR/shoal-pilot/tts.sock` (directory 0700, socket activated by `shoal-pilot-tts.socket`): one JSON line `{"text": ...}` speaks and answers `{"ok": true}` after playback; `{"stop": true}` cuts it short (pilotd sends it when the privacy switch engages). It links no TTS code: it runs a Piper executable (`--model voice.onnx --output_raw`) per request and plays the raw PCM through PulseAudio.

**Licence choice (spec section 11).** Piper's maintained line, OHF-Voice/piper1-gpl, is GPL-3.0. Pilot uses an MIT Piper instead: rhasspy/piper 1.2 (MIT, archived) or its MIT fork piper-plus, which have a narrower set of voices. The executable is a separate program at `/usr/libexec/shoal-pilot/piper`, run by `pilot-tts` as a subprocess; `pilot-tts` talks to pilotd only over its socket. So no GPL code is linked into pilotd, and none into `pilot-tts`. Voices (`.onnx` plus `.onnx.json`) carry their own licences (often CC BY 4.0 or MIT; check each) and are downloaded like the ASR models. Packaging the MIT Piper binary and choosing voices is still to do, and the spec's "legal review before shipping in a paid product" stands.

**pilotd's side.** `Listen()` on `org.shipwright.Pilot1` runs a spoken turn: refused with an offline card while the privacy switch is on (pilot-voice is not even asked), "I didn't hear anything." for silence, otherwise the transcript goes through the pipeline as a spoken turn and the headline is sent to `pilot-tts`. Spoken turns need the spoken-questions consent (`voice_cloud`) for anything remote; without it, timers, alarms, reminders, media and the calendar still work from voice. The result carries `transcript`, which the app shows as the user's words.

Build and test (needs CMake, a C++ compiler and libpulse development files):

```
cd shoal/pilot/voice
WHISPER_DONT_GENERATE_BINDINGS=1 cargo test           # VAD, WAV, power policy, model download, TTS socket, D-Bus service
PILOT_VOICE_TEST_MODEL=<dir>/ggml-tiny.en.bin WHISPER_DONT_GENERATE_BINDINGS=1 cargo test -- --ignored
cargo test --no-default-features                      # without whisper.cpp
```

The fixture `tests/fixtures/jfk-ask-not.wav` is the first 7.5 s of whisper.cpp's `samples/jfk.wav` (Kennedy's 1961 inaugural address, public domain; MIT as distributed by whisper.cpp). With the tiny English model (77.7 MB, downloaded to a scratch directory and deleted afterwards), `pilot-voice --transcribe tests/fixtures/jfk-ask-not.wav` printed `{"text":"And so my fellow Americans ask not what your country can do for you.","model":"tiny","audio_ms":7500,"decode_ms":1708}` on this x86 host (debug build of the Rust side, release build of whisper.cpp). The app's smoke test runs a spoken turn through the real `pilot-voice` (fixture as the microphone, `--fake-asr`) when given its path.

## Needs device verification

1. **timed events.** On a phone: "set a timer for 1 minute", "alarm at <two minutes from now>", "remind me to test in 1 minute". Each fires with the alarm dialog; the timer and the alarm appear in Clock and can be edited there; `pilotd` gets a non-zero cookie. Check that reminders (no `type` attribute, `APPLICATION=shoal_pilot`) show the dialog with their title.
2. **mkcal.** With events today, tomorrow and an all-day event: "what's on my calendar today/tomorrow" lists them at the right local times. Recurring events are returned only at their first occurrence (no `Rules` expansion yet); note what the phone shows instead.
3. **Contacts.** Redaction uses the phone's names: `pilotd --ask "text <a contact's first name>"` with `SHOAL_PILOT_LOG=debug` against a local relay shows `<CONTACT_1>` in the request; the database path and the `deleted` filter match the device's schema version.
4. **MPRIS.** With the Media app playing: "pause", "next track", "resume".
5. **oFono dial and ConnMan toggles** from confirmation cards; flight mode via ConnMan `OfflineMode` matches the top menu's flight mode.
6. **Privacy switch.** `busctl --user call org.sailfishos.privacyswitch /privacyswitch org.sailfishos.privacyswitch privacyModeActive` answers; toggling the switch flips `Offline` within a second, stops `shoal-pilot-voice.service`, and a question asked while engaged produces no egress row. Repeat with the switch configured not to cut the microphone: Pilot must still go offline.
7. **Unsandboxed user service.** `shoal-pilotd.service` starts by D-Bus activation from the Pilot UI under Sailjail with the `ShoalPilot` permission, and `pilotd` can reach timed, oFono and ConnMan on the system bus as the default user.
8. **Local time.** Timers and reminders across a DST change (`next_local` ignores DST between now and the target).
9. **App on the phone.** Install `shoal-pilot`; start Pilot from the launcher under Sailjail (`ShoalPilot`, `Downloads`); onboarding appears once; a question and a timer work; the cover shows the last answer; the cover's mic action brings the app up (voice arrives with `pilot-voice`); export lands in `~/Downloads`.
10. **System edge swipe (Lipstick).** The gesture patch package on Sailfish OS 5.2.0.15: [`lipstick/README.md`](lipstick/README.md#needs-device-verification), steps 2 and 3.
11. **Events view (Lipstick).** The Pilot widget, and the notification fallback if switched on: [`lipstick/README.md`](lipstick/README.md#needs-device-verification), steps 1 and 4.
12. **Microphone and speaker on the phone.** `pilot-voice` under the systemd user session records through PulseAudio with `media.role=voice`: check Sailfish's audio policy grants capture (and what it shows the user), that the stream closes when the turn ends, and that stopping the unit (privacy switch) releases it at once. Tune the VAD thresholds on the phone's microphones in a quiet room, a street and a car.
13. **whisper.cpp on the Dimensity 7100 and the Snapdragon 665.** Cross-build both builds (`rpm/cross-build.sh`; needs `pulseaudio-devel` in the SDK target); check `ps` shows `pilot-voice-armv8.2` serving on the Jolla Phone and `pilot-voice` on an Xperia 10 II, and that the 10 II transcribes; time base and tiny on a 5 s utterance (spec target: 400 ms end of speech to transcript); check the battery and thermal paths `power.rs` reads exist under `/sys/class`.
14. **pilot-tts.** Package an MIT Piper executable at `/usr/libexec/shoal-pilot/piper` and a voice; `systemctl --user start shoal-pilot-tts.socket`; a spoken turn's answer is heard; `{"stop": true}` cuts it; first audio within the 100 ms budget is not expected with a per-request process and needs a resident engine if it matters.
15. **Wake word.** With an openWakeWord runner as `--wake-command`, "Pilot" starts a turn; measure the battery cost on the A55 cores over a day (spec section 14).
16. **Keel Actions on the phone.** With `shipwright-keel-actions` and the Shoal apps installed and `keel-mcp` at `/usr/bin/keel-mcp`: "lock my passwords" runs Keys' `keys.lock` with no card; "send the draft to Anna" shows Mail's card; a request spanning two apps produces one plan card.
17. **Triage on the phone.** With triage on: an SMS, a chat message and a missed call appear in the Pilot events list with sensible buckets; a battery warning does not. Confirm that Sailfish's session bus lets pilotd (same user) become a monitor (`dbus-daemon` allows it by default; the log says "notification triage unavailable" if not), and that commhistoryd's notifications carry the `x-nemo.messaging.sms` category assumed here. Move a calendar event and see it listed. With spoken nudges on, only interrupt-worthy events are spoken. Count Jev requests over a day of normal use against `per_hour`.
18. **Camera.** `qt6-qtmultimedia` with a camera backend on the phone; the Camera Sailjail permission prompt; the viewfinder shows, the shutter saves into the app's cache, the answer arrives and no photo is left in `~/.cache/org.shipwright/shoal-pilot`. Check the size and quality at 1280 pixels are enough for labels and plants, and the turn's latency over mobile data.
