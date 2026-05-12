# Marathon Coding Rules

Rules for writing C++, QML, and shell code in this repo. Applies equally to human and AI-assisted authors. The goal is a codebase that doesn't look or behave like LLM output: dense, idiomatic, no defensive bloat, no resurrection of patterns the toolkit already provides.

If you change something in violation of a rule below, the change must include a one-line justification in the commit body.

---

## Section A — Banned patterns regardless of author

These produce slow, fragile, or misleading code. They show up disproportionately in LLM output and in tired humans. Catch them in review.

### A1. No defensive code for impossible failures

- Don't wrap calls in `try`/`catch` (or `if (ptr)`) when failure can't happen — internal callers, constructed-just-above pointers, framework guarantees.
- Don't null-check the return of `new` (it throws or aborts; this isn't 1990).
- Don't null-check `parent()` / `this` / a member you just initialised in the constructor.
- Don't add `Q_ASSERT(ptr)` immediately followed by `if (!ptr) return;` — pick one. If the contract says it can't be null, assert. If it can, handle the real case.

**Why:** every "harmless" guard makes the real intent harder to read and lets the wrong invariant survive into production.

### A2. No silent exception/error swallowing

- `catch (...) {}` is banned outright. So is `catch (...) { qWarning() << "oops"; }` followed by carrying on as if nothing happened.
- If a call can genuinely fail and the caller can recover, recover explicitly.
- If it can fail and the caller can't recover, let it propagate or crash. Loud failure beats corrupted state.

### A3. No comments that restate the code

```cpp
// BAD
m_count++;  // increment count
if (!user.isEmpty()) {  // check if user is not empty
    // ...
}
```

Only write a comment when the **why** is non-obvious — a hidden invariant, a workaround for a specific bug (with bug ID), behaviour that would surprise a reader, or a constraint the type system can't express. If removing the comment wouldn't confuse a future reader, delete it.

### A4. No "added for X" / "used by Y" / "fixes issue Z" comments

That belongs in the commit message and the PR. Comments rot; commit history doesn't.

### A5. No over-abstraction for one or two call sites

- Don't create a wrapper function for a one-line stdlib/Qt call.
- Don't create a class with one method that's only called from one place.
- Don't create a `Manager` / `Helper` / `Utils` / `Service` class until there's an actual second call site and the duplication hurts. Three similar lines is better than a premature abstraction.

### A6. No `auto` for non-obvious types

`auto` is fine for iterators, lambdas, `make_shared` returns, and template ceremony. It is **not** fine when the reader can't tell from the right-hand side what the type is. `auto x = something()` where `something()` is a function the reader has to chase is reader-hostile.

Special hazard: `auto s = QString("a") + QString("b");` deduces `QStringBuilder`, not `QString` — silently wrong. (clazy: `auto-unexpected-qstringbuilder`.)

### A7. No defensive null-checks on Qt parent-owned pointers

`QObject` parent ownership is the contract. If a child's `parent()` is set, it lives until the parent dies. Don't check; rely on the invariant.

### A8. No reinventing what the toolkit ships

- Don't roll your own string trimming, list reversal, debounce, mutex wrapper, signal-slot connection helper, event filter base class, atomic counter, etc. Qt and the STL have these.
- Specifically: don't write a "ResourceGuard" / "ScopedX" — `QScopedPointer`, `std::unique_ptr`, `QSignalBlocker` already exist.

---

## Section B — C++ / Qt rules

Largely the clazy ruleset, distilled to the cases that bite Marathon.

### B1. Always use Qt 5+ member-function `connect()`

```cpp
// BAD (old SIGNAL/SLOT — runtime check, easy to typo)
connect(button, SIGNAL(clicked()), this, SLOT(onClicked()));

// GOOD
connect(button, &QPushButton::clicked, this, &MyClass::onClicked);
```

### B2. Never emit raw pointers in signals

Especially over queued connections — the pointee may be gone by the time the slot runs. If you must convey identity across threads, use a value, an ID, or a `QPointer`.

### B3. Lambda captures in `connect()`

If the lambda outlives the captured stack frame (any queued or threaded connection), don't capture by reference. Don't capture `this` unless you also pass `this` as the connection context — otherwise the lambda fires after `this` is destroyed.

```cpp
// GOOD
connect(timer, &QTimer::timeout, this, [this] { /* ... */ });
//                                ^^^^ context object — disconnect on this->destroyed
```

### B4. Every `QObject` subclass that uses signals/slots needs `Q_OBJECT`

Without it, signals and properties silently don't work, and moc gives no error. Easy to miss after a refactor; clazy `missing-qobject-macro` catches it.

### B5. Don't iterate with non-const range-for over Qt containers

`for (auto &item : container)` detaches a Qt implicit-shared container if it's the only reference, even if you don't mutate. Use `qAsConst()` or `std::as_const()` for read loops.

```cpp
// BAD — detaches
for (const auto &x : map.values()) { /* ... */ }

// GOOD — no detach
for (const auto &x : std::as_const(map)) { /* ... */ }
```

### B6. Use `Q_ENUM`, not `Q_ENUMS`

`Q_ENUMS` is deprecated since Qt 5.5. `Q_ENUM` integrates with the meta-object system properly.

### B7. Use `QDateTime::currentDateTimeUtc()` if you don't need a timezone

`currentDateTime()` does timezone work; if you're going to convert to UTC anyway or just want a monotonic point, skip it.

### B8. Don't chain `QString::arg()`

```cpp
// BAD — three temporaries
str.arg(a).arg(b).arg(c)

// GOOD — multi-arg overload, no temporaries
str.arg(a, b, c)
```

### B9. Don't use `QFileInfo(path).exists()`

Use the static `QFileInfo::exists(path)` — no temporary `QFileInfo` object.

### B10. Don't `qDeleteAll(map.values())` or `qDeleteAll(map.keys())`

It's an extra allocation. `qDeleteAll(map)` works directly.

### B11. Pass large types by `const &`

`QString`, `QList`, `QImage`, any std container — by `const &` unless you intend to move from it. clazy `function-args-by-ref` flags this.

### B12. Don't poll. Subscribe.

If a state can change via signal, listen for the signal. If a service publishes events (D-Bus, PipeWire, NetworkManager, ModemManager, udev) **listen for the event** — do not `QTimer` + `pw-dump`/`mmcli`/`nmcli`/`busctl introspect` every N seconds. We already paid for this once with `AudioRoutingManager`'s `pw-dump` exec-poll; don't add another.

### B13. RT-scheduled threads are explicit and rare

`RTScheduler` is for compositor + input only. Don't sprinkle `SCHED_RR` requests. Don't bump nice values to chase performance. If a thread is too slow under `SCHED_OTHER`, the answer is usually "do less work in it" or "move work off it," not "give it a higher priority."

### B14. Don't store wall-clock time in property strings updated on a 1Hz timer

Use a `QTimer` aligned to the next minute boundary (see `SystemStatusStore::scheduleNextMinute()`). Wall-clock-driven rendering at 1Hz is what killed our idle CPU pre-Fix-1+2.

### B15. Lazy-construct expensive D-Bus clients

If a peripheral subsystem (e.g. Bluetooth, Location, Sensors) won't be touched until the user permits it or opens the relevant page, don't construct its IPC client in `main()`. See the marathon-app-runner permission-gated construction in `tools/marathon-app-runner/main.cpp` for the pattern.

---

## Section C — QML rules

### C1. The first line of every item is `id`

Conventional order, top to bottom:

```qml
ItemType {
    id: root                       // C1, C6
    // 1. property declarations
    property int someThing: 0
    // 2. property assignments
    width: parent.width
    height: 48
    // 3. attached properties (anchors, Layout.*, KeyNavigation.*)
    anchors.fill: parent
    // 4. states / transitions
    states: [...]
    // 5. signal handlers (shortest to longest, Component.onCompleted ALWAYS last)
    onClicked: doThing()
    Component.onCompleted: { ... }
    // 6. child items
    Rectangle { ... }
}
```

### C2. Top-level item id is always `root`

So nested code can refer up unambiguously. If you nest two `id: root` they shadow; restructure.

### C3. Don't set `id` on items you don't reference

Items with `id` participate in QML's name resolution and take memory in the JS context. Only `id` the items you reference.

### C4. No two-way bindings

Two `width: other.width` bindings pointing at each other = binding loop = Qt log spam = scene-graph dirty thrash. One side of every dependency is authoritative; the other derives.

### C5. Prefer `implicitWidth` / `implicitHeight` over `width` / `height` in reusable components

A reusable component tells its parent what it'd like to be. The parent decides the final size. Don't hard-code `width: 200` inside `MarathonButton.qml`.

### C6. No anonymous `Rectangle { color: "transparent" }` as a layout helper

If you want a logical container, use `Item`. Transparent `Rectangle` allocates a scene-graph node it doesn't need.

### C7. No `Connections { target: someSingleton }` without a guard

If the singleton is delayed in construction (most C++ singletons are), `target` resolves to `null` on first parse and `Connections` warns. Pattern:

```qml
Connections {
    target: SomeSingleton  // OK if SomeSingleton is qmlSingleton-registered
    function onSignal() { ... }
}
```

Don't use `connect()` in delegate `Component.onCompleted` — the slot survives the delegate. Use `Connections` inside the delegate.

### C8. No `running: true` on `NumberAnimation` / `PropertyAnimation` / `SequentialAnimation` with `loops: Animation.Infinite` unless gated

If the parent is hidden or off-screen, the animation **still keeps the scene graph dirty**. Gate `running` on actual visibility:

```qml
// BAD — burns LLVMpipe forever, even when lockScreen is hidden
NumberAnimation { running: true; loops: Animation.Infinite; ... }

// GOOD
NumberAnimation { running: lockScreen.visible; loops: Animation.Infinite; ... }
```

This is the bug Fix 1 patched. Don't reintroduce it.

### C9. No Column/Row with hundreds of items

Use `ListView`, `GridView`, `Repeater` only for short fixed lists. Above ~20 visible items, switch to a delegate-recycling view.

### C10. Business logic lives in C++, not QML JS blocks

A QML JS block longer than ~20 lines, or that does I/O, or that calls more than two unrelated singletons, should be a C++ slot/Q_INVOKABLE on a singleton. QML is for layout, binding, and transitions.

### C11. Avoid context properties

Use `qmlRegisterSingletonInstance` / `QML_SINGLETON` / `QML_ELEMENT`. Context properties are global, untyped, and undiscoverable.

### C12. Hard-coded colors and fonts only in the theme singleton

Same for spacings, radii, durations. `Constants.qml`, `MarathonTheme.qml`, or wherever — never inline hex codes in 30 different components. Restyling becomes impossible.

### C13. Use `Loader` for non-critical UI on the boot path

The lockscreen chevron, OOBE pages 2-7, the quick-settings details panel — all should be `Loader { active: shouldShow; asynchronous: true }`. We had to fix several of these because they were instantiated eagerly and animating before the user ever saw them.

### C14. No `Qt.callLater` to "fix" binding ordering

If you reach for `Qt.callLater` to break a binding ordering problem, the binding graph is wrong. Fix the dependencies, don't paper over them.

---

## Section D — Project-level "is this AI slop?" smell tests

Before committing AI-assisted code, scan for these. They show up regardless of language.

- [ ] Every function has a docstring/comment that restates its name. → delete most of them.
- [ ] Functions are uniformly 30+ lines with a `// Step 1:` `// Step 2:` rhythm. → flatten and rename so the structure is in the call graph, not the comments.
- [ ] Every value is suffixed with `Object` / `Response` / `Data` / `Result`. → use the thing's actual name.
- [ ] Generic catch-blocks that log and continue. → see A2.
- [ ] Helper class with one method called from one place. → inline it.
- [ ] Three lines that import `Q_*` macros that aren't used. → remove.
- [ ] `// TODO: handle error here` left in production code. → either handle it or delete the comment.
- [ ] Function named `process<Thing>` / `handle<Thing>` / `execute<Thing>` where a verb would be specific (`compose`, `dispatch`, `enqueue`). → rename.
- [ ] Configuration object passed everywhere with 12 fields, 3 used. → split the object or pass the 3.
- [ ] A `Manager` that owns another `Manager` that owns a `Manager`. → flatten.
- [ ] Confident comments claiming "this is thread-safe" / "this never blocks" with no proof. → either prove it (with a test or invariant doc) or delete the claim.

---

## Section E — Acceptable patterns that LOOK like slop but aren't

To be fair: not every defensive line is slop.

- **Boundary validation** at the program's edges (user input, network deserialisation, D-Bus method args, file parsing) is correct. The line you draw with the world has to be defended. Inside that line, trust your types.
- **An assert that can never fire** is fine in debug builds — it's a contract pin, not defensive code. `Q_ASSERT(ptr)` documents and enforces the invariant; the cost in release is zero.
- **A wrapper around a verbose Qt call** is fine if (a) the wrapper appears 4+ times and (b) the wrapper name is more readable than the underlying call. Two call sites and an opaque name = inline it.

---

## Section F — Process rules for AI-assisted changes

- **Always run** the change in the actual binary before claiming it works. "It compiles" is not "it works".
- **Verify imports/symbols exist** when the model produces unfamiliar names. Hallucinated APIs (functions/classes/headers that look right but aren't) are the #1 LLM tell.
- **Diff-review every line** of AI-assisted changes the same way you'd review a stranger's PR. The author has to internalise what the LLM wrote — otherwise the reviewer is doing all the work.
- **Resist the "make it pass" reflex** — if a test or build fails, fix the root cause, don't sprinkle catch blocks until the symptom goes away.
- **Match the existing code style.** If the surrounding file uses `m_member` and `someFunction`, don't introduce `member_` and `some_function`. Stylistic drift is a top tell of generated code.
- **No commit-message theatre.** Don't add Co-Authored-By trailers from AI assistants. Don't write commit messages that sound like a Medium article.

---

## Section G — Atomic, considered commits

Every commit is a discrete unit of meaning. AI-assisted authoring makes it easy to dump a bundle of half-related changes; that habit is forbidden here.

### G1. One logical change per commit

A commit does one thing. If the subject line needs "and" to describe what's in it, split it.

- A bug fix and a refactor of nearby code → two commits.
- Two independent bug fixes that touch the same file → two commits.
- Adding a feature and tidying a stylistic nit you noticed on the way → two commits.
- Adding tests for an existing function → its own commit if the function's behaviour didn't change; bundled with the change otherwise.

If you've already mixed them in your working tree, stage hunks: `git add -p`, `git commit`, then the rest.

### G2. Subject line is imperative, ≤72 characters, no trailing punctuation

```
GOOD: perf(audio): stop pw-dump polling once audio card is detected
GOOD: fix(qemu-gpu): wire up Zink + Venus path for virtio-gpu acceleration
BAD:  Fixed the audio bug.
BAD:  feat: added a bunch of stuff for the audio and updated some other things in the routing layer as well
```

If the change has scope, use the existing convention: `type(scope): subject` — see the repo log for the live vocabulary (`perf`, `fix`, `feat`, `docs`, `refactor`, `chore`). Don't invent a new type when an existing one fits.

### G3. Body explains WHY, not WHAT

The diff already shows what changed. The body should explain:
- The motivation (which bug, which constraint, which performance ceiling, which user-visible symptom)
- The decision (why this approach over the alternative the reader will think of)
- The consequence the reader needs to know (what now breaks if reverted, what now works that didn't)

Wrap at ~72 columns. Two short paragraphs usually beats one long one.

### G4. Every commit builds and (where applicable) passes tests on its own

`git bisect` is the contract — every commit on the trunk must compile and run. If a sequence of three commits is in a "broken in the middle" state, squash or rewrite before pushing. We don't ship trees where commit N requires commit N+1 to be usable.

### G5. Don't bundle unrelated files

If a single commit touches `apps/phone/`, `shell/src/wayland/`, and `marathon-core/src/marathonappinstaller.cpp`, audit it. It's almost certainly three commits in a trench coat.

Exception: a single cross-cutting rename or interface change that genuinely affects all three is one commit; the subject must say so.

### G6. Don't commit generated artifacts, build output, IDE state, or scratch files

`build/`, `*.o`, `.qmlc`, `.cache/`, `.claude/`, `core.*`, `*.swp`. Add to `.gitignore` once; never again.

### G7. Don't commit AI-tool trailers, "Generated by …" markers, or Co-Authored-By for AI assistants

Per **Section A** + user policy in this repo. Commit messages are human attribution; the AI did not, in any meaningful sense, take responsibility for the work.

### G8. Reference issues and PRs in the body, not the subject

```
GOOD subject: fix(scanner): handle empty appId fast path
GOOD body:    Fixes #142.

BAD  subject: fix(scanner): handle empty appId fast path (#142)
```

### G9. Squash review-noise commits before merging

`wip`, `fix typo`, `address review`, `final fix`, `actually working this time` — all squashed into the parent on the branch before the branch is merged to `main` / `alpha-1`. The history that lands on the trunk is the history we'd want to read in two years, not a session transcript.

### G10. Force-push only your own un-merged branches

Never force-push `main`, `alpha-1`, or any branch someone else's branch is based on. `git push --force-with-lease` for your feature branch; `git push --force` is banned.

### G11. The commit reflects what got tested, not what got planned

If the plan was "fix A and B" but B turned out to require a different approach and isn't done, commit A alone. Don't ship a half-B in the commit that fixes A "because it's almost done." Half-implementations rot.

### G12. Self-review the diff before writing the message

`git diff --cached` before every commit. If your description doesn't match what you see, the description is wrong, or the diff has accidents in it (debug prints, commented-out code, an unrelated formatter pass). Fix the diff, then write the message.

---

## How to use this document

- Reviewers: cite rule IDs (e.g., "A3", "B12", "C8") in review comments. Faster than re-explaining.
- New contributors: read once. You don't have to memorise it; the IDs are the index.
- AI-assisted contributors: paste the relevant section into your prompt when working on the corresponding code.

Updates to this file require a PR like any other code change.
