#!/usr/bin/env bash
# Stop hook: keeps Claude from ending its turn while a dialog is open and
# nothing watches it, which would leave the author's next save unanswered.
# Blocks at most once per stop (stop_hook_active) and never for a dialog that
# was closed with `end`. MARGINS_REARM=0 turns it off.

[ "${MARGINS_REARM:-1}" = 0 ] && exit 0
input=$(cat)

# No jq: the two fields are read out of the JSON text.
re='"stop_hook_active"[[:space:]]*:[[:space:]]*true'
[[ $input =~ $re ]] && exit 0
re='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ $input =~ $re ]] || exit 0
sid=${BASH_REMATCH[1]}

if [ -n "${MARGINS_DIR:-}" ]; then sdir=$MARGINS_DIR
elif [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then sdir=$XDG_RUNTIME_DIR/margins
else sdir=${TMPDIR:-/tmp}/margins-$(id -u)
fi
log=$sdir/${sid//[^A-Za-z0-9._-]/_}.log
[ -f "$log" ] || exit 0

own_ns=''
[ -e /proc/self/ns/pid ] && own_ns=$(readlink /proc/self/ns/pid 2>/dev/null | tr -cd 0-9)

# One line per dialog that is not closed: <path> TAB <watch pid> TAB <its pid namespace>,
# the pid empty when no watch was armed or the last one said it ended.
open=$(awk -F'\t' '
    $2 == "closed" { closed[$3] = 1; pid[$3] = ""; next }
    $2 == "open" || $2 == "save" || $2 == "turn" || $2 == "reply" { closed[$3] = 0; seen[$3] = 1 }
    $2 == "watch" { closed[$3] = 0; seen[$3] = 1; split($4, w, " "); pid[$3] = w[1]; ns[$3] = w[2] }
    $2 == "unwatch" && pid[$3] == $4 { pid[$3] = "" }
    END { for (p in seen) if (!closed[p]) printf "%s\t%s\t%s\n", p, pid[p], ns[p] }' "$log")
[ -n "$open" ] || exit 0

unwatched=()
while IFS=$'\t' read -r path pid ns; do
    [ -e "$path" ] || continue
    if [ -n "$pid" ]; then
        [ -n "$ns" ] && [ -n "$own_ns" ] && [ "$ns" != "$own_ns" ] && continue
        kill -0 "$pid" 2>/dev/null && continue
    fi
    unwatched+=("$path")
done <<< "$open"
[ ${#unwatched[@]} -gt 0 ] || exit 0

helper=$(cd "${BASH_SOURCE[0]%/*}/.." 2>/dev/null && pwd -P)/margins.sh
names=$(printf '%s, ' "${unwatched[@]}"); names=${names%, }
msg="margins: the dialog in $names is still open but nothing watches it, so the author's next save would go unanswered. Run \`$helper turn <file>\` in case a save is waiting, then arm a Monitor on \`$helper watch <file>\` (timeout at the maximum). If the dialog is over, close it with \`$helper end <file> '<outcome>'\` instead."
msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
printf '{"decision":"block","reason":"%s"}\n' "$msg"
