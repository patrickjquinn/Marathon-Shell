# Monorepo migration: Marathon-Image → Marathon-Shell

Absorb `MarathonOS/Marathon-Image` into `patrickjquinn/Marathon-Shell` as a
subtree at `packaging/`, preserving all 163 commits of history. Executed
2026-08-31.

**Status: done.** Pre-merge state is tagged `pre-monorepo` here and
`pre-monorepo-image` in Marathon-Image.

## Why

| Finding | Evidence |
|---|---|
| One changeset, two repos | 36 of Image's 38 active days coincide with a Shell commit (95%). Last commits 11 s apart. |
| Atomic commits impossible | `docs/CODING_RULES.md` requires them; a shell change + apk dep is 2 commits, 2 repos, no shared ref. |
| Shell APK not reproducible | `packages/marathon-shell/APKBUILD:101` fetches `archive/ux-overhaul.tar.gz` — a floating branch, no commit pin. |
| 520 fossil files | `packages/marathon-shell/{shell,apps}` last touched 2025-10-23, unreferenced by the APKBUILD. ~45 MB of `.wav`. |
| Doc drift | `UI_DESIGN_SYSTEM.md`, `APP_DEVELOPMENT.md`, `APP_MANIFEST_SCHEMA.md`, `DEVELOPMENT_WORKFLOW.md` exist and differ in both trees. |
| Two duranium mechanisms | `scripts/qemu/duranium-overlay/` (rsync) and `pipeline-patches/` (git am) both write `mkosi.finalize`, `mkosi.images/base/mkosi.{conf,postinst}`, `scripts/mkosi-configure.py`. Cost r80–r87 seven rounds of lost postinst fixes (see `setup-trees.sh:104`). |

## Target layout

Marathon-Image's internal structure is preserved wholesale under one prefix.
This is deliberate — it keeps two relative-path contracts working with zero
edits:

- `packages/linux-marathon/APKBUILD:44` reads `../../devices/$_device/…`
- all nine `scripts/qemu/lib/build-*-apk.sh` derive `APORTS_SRC="$MARATHON_IMAGE_DIR/packages"`

```
Marathon-Shell/
├── shell/  apps/  marathon-ui/  marathon-core/  …   (unchanged)
├── scripts/                                          (unchanged, 9 defaults repointed)
├── docs/                                             (absorbs Image's unique docs)
└── packaging/                     ← git subtree, full history
    ├── packages/                  15 aports
    ├── pipeline-patches/          15-patch duranium series + bootstrap.sh
    ├── configs/                   system config drop-ins
    └── devices/                   kernel-config fragments
```

## Steps

### 0. Preconditions — verify before touching anything

1. Push Marathon-Image's 5 unpushed commits.
   → verify: `git -C ../Marathon-Image rev-list --count origin/main..main` prints `0`
2. Land or stash the 2 untracked Image scripts (`build-cm5-pmbootstrap.sh`,
   `push-cm5.sh`) — a subtree add reads committed state only, so untracked
   files are silently left behind.
   → verify: `git -C ../Marathon-Image status --short` is empty
3. Decide on Shell's 10 dirty paths (in-progress Maps work). The subtree add
   is a merge commit and wants a clean tree.
   → verify: `git status --short` is empty
4. Tag the pre-merge state on both sides for a clean escape hatch.
   → verify: `git tag | grep pre-monorepo` on each

### 1. Subtree add

`git-subtree` is not installed on the build host and needs sudo, so the
merge used the plumbing `git subtree add` runs internally — identical
result:

```sh
git remote add marathon-image https://github.com/MarathonOS/Marathon-Image.git
git fetch marathon-image main
git merge -s ours --no-commit --allow-unrelated-histories marathon-image/main
git read-tree --prefix=packaging/ -u marathon-image/main
git commit    # with git-subtree-dir / -mainline / -split trailers
```

**Querying pre-merge history.** Because the files moved under a prefix in
a `-s ours` merge, `git log --follow` does not traverse it. All 163
commits are ancestors of `HEAD`; reach them via the *old* path:

```sh
git log --full-history -- packages/marathon-shell/APKBUILD   # 94 commits
```

→ verify: `git log --oneline packaging/packages/marathon-shell/APKBUILD | wc -l` > 1
  (history crossed the boundary, not a squashed import)
→ verify: `ls packaging/packages | wc -l` prints `15`

### 2. Repoint the nine resolution sites

Change the default only; the env override stays honoured so an external
checkout still works during the transition.

```sh
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-${MARATHON_SHELL_SRC}/packaging}"
```

| File | Line |
|---|---|
| `scripts/qemu/lib/build-marathon-shell-apk.sh` | 15 |
| `scripts/qemu/lib/build-marathon-base-config-apk.sh` | 9 |
| `scripts/qemu/lib/build-marathon-plymouth-theme-apk.sh` | 9 |
| `scripts/qemu/lib/build-marathon-mail-oauth-apk.sh` | 19 |
| `scripts/qemu/lib/build-postmarketos-ui-marathon-apk.sh` | 14 |
| `scripts/qemu/lib/build-qmf-apk.sh` | 19 |
| `scripts/qemu/lib/build-device-marathon-apk.sh` | 16 |
| `scripts/marathon.d/common.sh` | 52 |
| `scripts/build-image.sh` | 292 (hardcoded `../Marathon-Image/packages/marathon-plymouth-theme`) |

Then `scripts/qemu/lib/setup-trees.sh` — delete the clone-or-find block
(lines 30–48) and set `MARATHON_IMAGE_SRC="$MARATHON_SHELL_SRC/packaging"`
directly. Drop `MARATHON_IMAGE_GIT` / `MARATHON_IMAGE_REF`.

→ verify: `grep -rn "Developer/Marathon-Image" scripts/` returns nothing
→ verify: `for f in $(git ls-files 'scripts/**/*.sh'); do bash -n $f || echo FAIL $f; done` is silent

### 3. Delete the fossils

- `packaging/packages/marathon-shell/{shell,apps}` — 520 files, dead since
  2025-10-23. History is preserved in the subtree; only the working tree
  loses them.
- `packaging/scripts/build-rootless*.sh`, `complete-build.sh`,
  `build-marathon-qemu.sh`, `sync-and-build-marathon.sh` — superseded by
  `scripts/build-image.sh` (`feedback_duranium_primary`).
  `docs/DEVICE_OVERLAYS.md` independently called this path dead.

**Deviation from plan:** `build-cm5-pmbootstrap.sh` and `push-cm5.sh`
were untracked in Marathon-Image and read as fossils by filename, but
are current — duranium's UKI/erofs/verity chain does not boot Pi 5
firmware, so pmbootstrap is the canonical CM5 path. Committed to
Marathon-Image first (`564329c`) so the subtree, which reads committed
state only, would carry them.

`packaging/{devices,configs}` are also called dead by DEVICE_OVERLAYS.md
but `packages/linux-marathon/APKBUILD` still reads `../../devices/`, so
they were retained rather than deleted on a doc's say-so.

→ verify: `scripts/build-image.sh` still resolves — grep the deleted names
  across `scripts/` and `packaging/` for stragglers first.

### 4. Reconcile docs

Diffed all six files in Image's `packages/marathon-shell/docs/`: last
genuine edits were 2025-11-09, mostly 2025-10-23, and the four that
shadowed live docs were pre-restructure versions carrying nothing
unique. Dropped. `BUILD_THIS.md` (an Oct-2025 macOS QML quickstart) and
`UI_IMPLEMENTATION_SUMMARY.md` (a completion report of the style
Section E bans) went with them.

Image's 13 docs moved to top-level `docs/`. **Deviation from plan:**
`TROUBLESHOOTING.md` became `DEVICE_TROUBLESHOOTING.md` — it covers
OS-on-device issues while the root `TROUBLESHOOTING.md` covers shell
build/runtime, and two same-basename files in one repo invites citing
the wrong one.

→ verify: no filename appears in both `docs/` and `packaging/`

### 5. Update entry points

- `README.md` — one repo, one clone
- `docs/IMAGE_BUILD_ARCHITECTURE.md` — the "THREE independent git trees"
  section is now two
- `docs/BUILDING.md` — same
- `CLAUDE.md` / `CONTEXT.md` — repo layout

### 6. Archive Marathon-Image

Archive on GitHub (read-only, history intact) with a README pointer.
Do **not** delete — the subtree keeps hashes, but the old remote is the
cheapest audit trail.

## Open decisions

**Licensing.** `packaging/LICENSE` is MIT (inherited from
Marathon-Image); the repo root is Apache 2.0. Both are © Patrick Quinn,
so unifying them is available but is the owner's call, not a migration
side-effect. Left as-is.

## Deliberately out of scope

Two follow-ups, each its own commit, each verified by a real image build:

1. **Converge the duranium mechanisms.** `pipeline-patches/` moves in as-is.
   Folding it together with `scripts/qemu/duranium-overlay/` is the fix for
   the last-writer-wins bug, but doing it inside the migration commit means
   a broken image build is indistinguishable from a broken migration.
2. **Switch the shell APKBUILD to local source.** The monorepo makes
   `source=` a local path instead of `archive/ux-overhaul.tar.gz` — the
   single biggest correctness win here, and the reason the merge is worth
   doing. It changes build behaviour, so it lands and is validated alone.

## Rollback

`git reset --hard pre-monorepo` on `ux-overhaul`. The subtree add is one
merge commit; nothing outside `packaging/` and the nine repointed lines is
touched.
