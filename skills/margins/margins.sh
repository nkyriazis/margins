#!/usr/bin/env bash
# A conversation held inside one file: its own git history, a watch, and
# replies placed by line number. See SKILL.md.
#
#   dialog.sh init  <file>                    give the file its own history (v0)
#   dialog.sh watch <file>                    Monitor command: one line per real save
#   dialog.sh turn  <file>                    show the author's edit, commit it as their turn
#   dialog.sh reply <file> <after> <textfile> insert textfile after line <after>, commit as ours
#   dialog.sh end   <file> "<summary>"        write the closing line, tag it, and stop the watch
set -euo pipefail
cmd="${1:?usage: dialog.sh init|watch|turn|reply|end|reopen <file> ...}"; f="$(realpath "${2:?no file}")"
dir="$(dirname "$f")"; base="$(basename "$f")"
G=(git --git-dir="$dir/.${base%.*}.dialog.git" --work-tree="$dir")

case "$cmd" in
init)
    [ -e "$dir/.${base%.*}.dialog.git" ] && { echo "already versioned: $dir/.${base%.*}.dialog.git"; exit 0; }
    git init -q --bare "$dir/.${base%.*}.dialog.git"
    "${G[@]}" config core.bare false
    "${G[@]}" config user.name "$(git config user.name || echo author)"
    "${G[@]}" config user.email "$(git config user.email || echo author@localhost)"
    "${G[@]}" add -- "$base"
    "${G[@]}" commit -qm "v0" -- "$base"
    echo "versioned: $dir/.${base%.*}.dialog.git"
    ;;
watch)
    # A save is an event only if, once the file has been still for two
    # seconds, it differs from the last committed turn. Our own reply is
    # written and committed in one step, so it never reaches the event.
    last=""
    while true; do
        # The end is a tag in the dialog's own history, so the watch ends
        # itself the moment `end` runs, and says so: an expiry is never
        # mistaken for a close, nor a close for an expiry.
        if "${G[@]}" rev-parse -q --verify refs/tags/closed >/dev/null; then
            echo "$base: dialog closed, watch ended"; exit 0
        fi
        cur="$(sha1sum "$f" 2>/dev/null | cut -c1-12 || echo missing)"
        if [ "$cur" != "$last" ]; then
            sleep 2
            again="$(sha1sum "$f" 2>/dev/null | cut -c1-12 || echo missing)"
            if [ "$again" = "$cur" ]; then
                last="$cur"
                "${G[@]}" diff --quiet -- "$base" 2>/dev/null || echo "$base saved by the author ($cur)"
            fi
        fi
        sleep 1
    done
    ;;
turn)
    if "${G[@]}" diff --quiet -- "$base"; then echo "no edit since the last turn"; exit 0; fi
    # Committed first, printed after: a reader that cuts the output short
    # (head, sed q) used to kill this before the commit, and the same turn
    # came back on the next save.
    n="$("${G[@]}" rev-list --count HEAD)"
    "${G[@]}" commit -qm "author, turn $n" -- "$base"
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
    "${G[@]}" diff --quiet -- "$base" || { echo "the author has edited since the last turn: run turn first"; exit 1; }
    python3 - "$f" "$after" "$text" <<'PY'
import sys
path, after, text = sys.argv[1], int(sys.argv[2]), open(sys.argv[3]).read().rstrip('\n')
lines = open(path).read().split('\n')
if not 0 <= after <= len(lines):
    raise SystemExit(f"line {after} is outside the file (it has {len(lines)})")
lines[after:after] = [''] + text.split('\n')
open(path, 'w').write('\n'.join(lines))
PY
    n="$("${G[@]}" rev-list --count HEAD)"
    "${G[@]}" commit -qm "claude, turn $n" -- "$base"
    echo "replied after line $after"
    ;;
end)
    summary="${3:?a one-line summary of how the dialog ended}"
    "${G[@]}" diff --quiet -- "$base" || { echo "the author has edited since the last turn: run turn first"; exit 1; }
    "${G[@]}" rev-parse -q --verify refs/tags/closed >/dev/null && { echo "already closed"; exit 0; }
    printf '\n---\nDIALOG CLOSED. %s Nothing here is watched any more; to reopen, ask in the chat.\n' "$summary" >> "$f"
    n="$("${G[@]}" rev-list --count HEAD)"
    "${G[@]}" commit -qm "closed, turn $n" -- "$base"
    "${G[@]}" tag closed
    echo "closed; the watch exits within a second"
    ;;
reopen)
    "${G[@]}" tag -d closed >/dev/null 2>&1 || true
    echo "reopened: arm the watch again"
    ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
