# Sourced by the build helpers that `git archive` a local checkout. The
# archive is the commit, so edits not committed would be left out unseen.
require_clean() {
    local src=$1
    shift
    [ "${ALLOW_DIRTY:-0}" = 1 ] && return 0
    local dirty
    dirty="$(git -C "$src" status --porcelain -- "$@")"
    [ -z "$dirty" ] && return 0
    printf 'error: %s has changes the archived commit would leave out:\n%s\n' "$src" "$dirty" >&2
    echo "commit them, or set ALLOW_DIRTY=1 to build the commit without them" >&2
    exit 1
}
