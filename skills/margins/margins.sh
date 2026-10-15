#!/usr/bin/env bash
# margins: a conversation held inside one file. It gets its own git history,
# a watch, and replies placed by line number. See SKILL.md.
#
#   margins.sh init   <file>                    give the file its own history (v0)
#   margins.sh watch  <file>                    Monitor command: one line per real save
#   margins.sh turn   <file>                    show the author's edit, commit it as their turn
#   margins.sh reply  <file> <after> <textfile> insert textfile after line <after>, commit as ours
#   margins.sh end    <file> "<summary>"        write the closing line, tag it, and stop the watch
#   margins.sh reopen <file>                    lift the close, so the watch can be armed again
#   margins.sh version
#
# Each command also appends one line to this agent session's state file,
# which the Claude Code plugin reads to draw the band above the prompt and to
# notice a dialog left without a watch. MARGINS_DIR moves that file.
set -euo pipefail
MARGINS_VERSION=1.0.0

case "${1:-}" in
version | --version | -v) echo "margins $MARGINS_VERSION"; exit 0 ;;
'' | help | --help | -h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
cmd=$1
[ -e "${2:?no file}" ] || { echo "margins: no such file: $2" >&2; exit 1; }
f="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
dir="$(dirname "$f")"; base="$(basename "$f")"
G=(git --git-dir="$dir/.${base%.*}.dialog.git" --work-tree="$dir")

# The session this shell belongs to, and the file its state goes to: the same
# path the plugin resolves from the session id.
sid=${MARGINS_SESSION:-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}}
if [ -n "${MARGINS_DIR:-}" ]; then sdir=$MARGINS_DIR
elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ]; then sdir=$XDG_RUNTIME_DIR/margins
else sdir=${TMPDIR:-/tmp}/margins-$(id -u)
fi
state_file=$sdir/${sid//[^A-Za-z0-9._-]/_}.log

# state <event> [detail]: one tab-separated line, never fatal. The plugin
# keeps the last word per file.
state() {
    { [ -d "$sdir" ] || (umask 077 && mkdir -p "$sdir"); } 2>/dev/null || return 0
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$1" "$f" "${2:-}" >> "$state_file" 2>/dev/null || true
}

turns() { "${G[@]}" rev-list --count HEAD; }
fingerprint() { cksum < "$f" 2>/dev/null | cut -d' ' -f1 || echo missing; }
unread() { ! "${G[@]}" diff --quiet -- "$base"; }

case "$cmd" in
init)
    if [ -e "$dir/.${base%.*}.dialog.git" ]; then
        echo "already versioned: $dir/.${base%.*}.dialog.git"
    else
        git init -q --bare "$dir/.${base%.*}.dialog.git"
        "${G[@]}" config core.bare false
        "${G[@]}" config user.name "$(git config user.name || echo author)"
        "${G[@]}" config user.email "$(git config user.email || echo author@localhost)"
        "${G[@]}" add -- "$base"
        "${G[@]}" commit -qm "v0" -- "$base"
        echo "versioned: $dir/.${base%.*}.dialog.git"
    fi
    state open "$(turns)"
    ;;
watch)
    # A save is an event only if, once the file has been still for two
    # seconds, it differs from the last committed turn. Our own reply is
    # written and committed in one step, so it never reaches the event.
    ns=''
    [ -e /proc/self/ns/pid ] && ns=$(readlink /proc/self/ns/pid 2>/dev/null | tr -cd 0-9)
    state watch "$$ $ns"
    trap 'state unwatch "$$"' EXIT
    trap 'exit 0' TERM INT HUP
    last=""
    while true; do
        # The end is a tag in the dialog's own history, so the watch ends
        # itself the moment `end` runs, and says so: an expiry is never
        # mistaken for a close, nor a close for an expiry.
        if "${G[@]}" rev-parse -q --verify refs/tags/closed >/dev/null; then
            echo "$base: dialog closed, watch ended"; exit 0
        fi
        cur="$(fingerprint)"
        if [ "$cur" != "$last" ]; then
            sleep 2
            again="$(fingerprint)"
            if [ "$again" = "$cur" ]; then
                last="$cur"
                if unread 2>/dev/null; then
                    state save "$(turns)"
                    echo "$base saved by the author ($cur)"
                fi
            fi
        fi
        sleep 1
    done
    ;;
turn)
    if ! unread; then echo "no edit since the last turn"; exit 0; fi
    # Committed first, printed after: a reader that cuts the output short
    # (head, sed q) used to kill this before the commit, and the same turn
    # came back on the next save.
    n="$(turns)"
    "${G[@]}" commit -qm "author, turn $n" -- "$base"
    state turn "$((n + 1))"
    # Every line the author added or changed, with its number in the file
    # as it is now. A block can end on a line that is not theirs to speak
    # in -- a box ticked on the next item's heading -- so the reply goes
    # after the last line of *their words*, chosen from this list.
    "${G[@]}" diff -U0 HEAD~1 HEAD -- "$base" | awk '
        /^@@/ { split($3, a, ","); ln = substr(a[1], 2); next }
        /^\+\+\+/ { next }
        /^\+/ { printf "author line %d: %s\n", ln, substr($0, 2); ln++; next }
        /^-/ && !/^---/ { printf "author removed: %s\n", substr($0, 2) }'
    echo "----"
    "${G[@]}" diff HEAD~1 HEAD -- "$base"
    ;;
reply)
    after="${3:?line number to reply after}"; text="${4:?file holding the reply}"
    if unread; then echo "the author has edited since the last turn: run turn first"; exit 1; fi
    python3 - "$f" "$after" "$text" <<'PY'
import sys
path, after, text = sys.argv[1], int(sys.argv[2]), open(sys.argv[3]).read().rstrip('\n')
lines = open(path).read().split('\n')
if not 0 <= after <= len(lines):
    raise SystemExit(f"line {after} is outside the file (it has {len(lines)})")
lines[after:after] = [''] + text.split('\n')
open(path, 'w').write('\n'.join(lines))
PY
    n="$(turns)"
    "${G[@]}" commit -qm "claude, turn $n" -- "$base"
    state reply "$((n + 1))"
    echo "replied after line $after"
    ;;
end)
    summary="${3:?a one-line summary of how the dialog ended}"
    if unread; then echo "the author has edited since the last turn: run turn first"; exit 1; fi
    "${G[@]}" rev-parse -q --verify refs/tags/closed >/dev/null && { echo "already closed"; exit 0; }
    printf '\n---\nDIALOG CLOSED. %s Nothing here is watched any more; to reopen, ask in the chat.\n' "$summary" >> "$f"
    n="$(turns)"
    "${G[@]}" commit -qm "closed, turn $n" -- "$base"
    "${G[@]}" tag closed
    state closed "$((n + 1))"
    echo "closed; the watch exits within a second"
    ;;
reopen)
    "${G[@]}" tag -d closed >/dev/null 2>&1 || true
    state open "$(turns)"
    echo "reopened: arm the watch again"
    ;;
*) echo "margins: unknown command $cmd" >&2; exit 2 ;;
esac
