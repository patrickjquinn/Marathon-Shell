#!/usr/bin/env bash
# bootstrap.sh — clone upstream postmarketos/duranium at the pinned
# merge-base commit and apply Marathon's local divergence as a series
# of git-am patches. Produces a duranium-build/ tree that can build
# the r180 HackberryPi CM5 image.
#
# Why this layout (instead of a Marathon-owned duranium fork): the user
# explicitly preferred patches-in-Marathon-Image to keep the upstream
# relationship visible. Cost: when upstream drifts past the pinned
# commit, patches may need rebasing.
#
# Usage:
#   ./bootstrap.sh [DEST_DIR]
#
# DEST_DIR defaults to $HOME/duranium-build. Pass an alternate to
# stage in /tmp/scratch etc.

set -euo pipefail

UPSTREAM="https://gitlab.postmarketos.org/postmarketOS/duranium.git"
# Last commit on upstream main where Marathon's patch series cleanly
# applies. Bump after a successful rebase.
PINNED_COMMIT="394290c68276e07cc1de326e60d467ee603a920c"

MKOSI_UPSTREAM="https://github.com/systemd/mkosi.git"
# Last mkosi commit Marathon's pipeline was validated against (r180
# image build, 2026-06-19). mkosi master moves fast and breaks our
# config periodically; pin here.
MKOSI_COMMIT="dc801b00a3c8b77c7ad0a5ea6dd684ea3c689546"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${1:-$HOME/duranium-build}"
DURANIUM_DIR="$DEST_DIR/duranium"
MKOSI_DIR="$DEST_DIR/mkosi-src"

# Idempotent: an already-bootstrapped tree is left alone so callers
# (scripts/qemu/lib/setup-trees.sh) can invoke this unconditionally. A
# directory that exists but is NOT a bootstrapped tree is still an error
# — that state is ambiguous and clobbering it would lose work.
#
# The marker is a patch commit subject in git log. A file marker will not
# do: setup-trees.sh rsyncs marathon-extras/ into the tree separately, so
# its presence says nothing about whether git am ever ran.
SKIP_DURANIUM=0
if [ -d "$DURANIUM_DIR" ]; then
    if git -C "$DURANIUM_DIR" log --format=%s -n 60 2>/dev/null \
         | grep -q 'synthesize /boot/loader/entries'; then
        echo "==> $DURANIUM_DIR already bootstrapped — skipping"
        SKIP_DURANIUM=1
    else
        echo "error: $DURANIUM_DIR exists but has no Marathon patches applied." >&2
        echo "       Move or delete it, then re-run." >&2
        exit 1
    fi
fi
SKIP_MKOSI=0
if [ -d "$MKOSI_DIR" ]; then
    if [ -x "$MKOSI_DIR/bin/mkosi" ]; then
        echo "==> $MKOSI_DIR already present — skipping"
        SKIP_MKOSI=1
    else
        echo "error: $MKOSI_DIR exists but has no bin/mkosi." >&2
        exit 1
    fi
fi

mkdir -p "$DEST_DIR"
if [ "$SKIP_DURANIUM" = "0" ]; then
echo "==> cloning upstream duranium into $DURANIUM_DIR"
git clone "$UPSTREAM" "$DURANIUM_DIR"

cd "$DURANIUM_DIR"
echo "==> checking out pinned commit $PINNED_COMMIT"
git checkout "$PINNED_COMMIT"

# Configure a local identity so git am can apply patches without
# inheriting the developer's name. The patches carry their own author
# headers; the committer just needs valid name + email set.
if ! git config user.email >/dev/null 2>&1; then
    git config user.email "marathon-bootstrap@localhost"
    git config user.name  "Marathon Bootstrap"
fi

echo "==> applying $(ls "$SCRIPT_DIR"/*.patch | wc -l) patches"
git am "$SCRIPT_DIR"/*.patch
fi

if [ "$SKIP_MKOSI" = "0" ]; then
echo "==> cloning mkosi into $MKOSI_DIR"
git clone "$MKOSI_UPSTREAM" "$MKOSI_DIR"
cd "$MKOSI_DIR"
echo "==> checking out pinned mkosi commit $MKOSI_COMMIT"
git checkout "$MKOSI_COMMIT"
fi

cd "$DEST_DIR"
echo "==> next steps:"
echo "   1. Populate \$HOME/.marathon-secrets/ with SKYZMTGV.nmconnection.raw"
echo "      and ensure ~/.ssh/id_ed25519.pub exists."
echo "   2. Build per docs/BUILDING.md."
echo "==> done."
echo "   duranium tree:  $DURANIUM_DIR (at $PINNED_COMMIT + Marathon patches)"
echo "   mkosi source:   $MKOSI_DIR (at $MKOSI_COMMIT)"
