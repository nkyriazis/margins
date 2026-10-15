#!/usr/bin/env bash
# Tests for margins.sh and the Stop hook, in a scratch directory.
#   bash tests/cli.sh [repo]
set -u
REPO=${1:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)}
M=$REPO/skills/margins/margins.sh
REARM=$REPO/skills/margins/hooks/rearm.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/margins-test.XXXXXX")
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
export MARGINS_DIR=$T/state MARGINS_SESSION=s1 GIT_CONFIG_GLOBAL=$T/gitconfig
git config --global user.name tester; git config --global user.email t@example.com
n=0; failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); failed=$((failed + 1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/#   /'; }
check() { local name=$1; shift; if "$@" > "$T/out" 2>&1; then ok "$name"; else no "$name" "$(cat "$T/out")"; fi; }
has() { grep -q -- "$1" "$T/out"; }
stop() { printf '{"session_id":"s1","stop_hook_active":%s}' "${1:-false}" | bash "$REARM"; }

cd "$T" || exit 1
printf '# Plan\n\n1. Which database?\n   Default: sqlite. Which one?\n\n2. Ship Friday?\n   Default: yes.\n' > plan.md

check "init gives the file its own history" "$M" init plan.md
check "the history sits beside the file" test -d .plan.dialog.git
check "init twice is harmless" "$M" init plan.md

"$M" turn plan.md > "$T/out"
if has "no edit since the last turn"; then ok "turn without an edit says so"; else no "turn without an edit says so" "$(cat "$T/out")"; fi

sed -i.bak '4a\
   Nikos: postgres, we need concurrent writers.' plan.md && rm -f plan.md.bak
"$M" turn plan.md > "$T/out"
if has "author line 5: .*postgres"; then ok "turn numbers the author's lines"; else no "turn numbers the author's lines" "$(cat "$T/out")"; fi
"$M" turn plan.md > "$T/out"
if has "no edit since"; then ok "a turn is committed once"; else no "a turn is committed once" "$(cat "$T/out")"; fi

printf '   Claude: switched to postgres, migrations pass.\n' > "$T/r1"
check "reply lands after the given line" "$M" reply plan.md 5 "$T/r1"
if sed -n '7p' plan.md | grep -q "Claude: switched"; then ok "the reply is under the author's words"; else no "the reply is under the author's words" "$(cat -n plan.md)"; fi
if sed -n '9p' plan.md | grep -q "^2. Ship"; then ok "the next item is untouched"; else no "the next item is untouched" "$(cat -n plan.md)"; fi

echo "   Nikos: yes" >> plan.md
if "$M" reply plan.md 3 "$T/r1" > "$T/out" 2>&1; then no "reply refuses with unread edits"; else has "run turn first" && ok "reply refuses with unread edits" || no "reply refuses with unread edits" "$(cat "$T/out")"; fi
"$M" turn plan.md > /dev/null

if "$M" reply plan.md 999 "$T/r1" > "$T/out" 2>&1; then no "reply refuses a line past the end"; else ok "reply refuses a line past the end"; fi

# The watch: a save fires, our own reply does not, and the close ends it.
"$M" watch plan.md > "$T/watch" 2>&1 &
wpid=$!
sleep 4
echo "   Nikos: one more thing" >> plan.md
for _ in $(seq 1 20); do grep -q "saved by the author" "$T/watch" && break; sleep 0.5; done
if grep -q "saved by the author" "$T/watch"; then ok "watch fires on the author's save"; else no "watch fires on the author's save" "$(cat "$T/watch")"; fi
"$M" turn plan.md > /dev/null
printf '   Claude: noted.\n' > "$T/r2"
"$M" reply plan.md "$(grep -n 'one more thing' plan.md | cut -d: -f1)" "$T/r2" > /dev/null
sleep 5
if [ "$(grep -c "saved by the author" "$T/watch")" = 1 ]; then ok "our own reply does not fire the watch"; else no "our own reply does not fire the watch" "$(cat "$T/watch")"; fi

stop > "$T/out"
if [ ! -s "$T/out" ]; then ok "the Stop hook is quiet while a watch runs"; else no "the Stop hook is quiet while a watch runs" "$(cat "$T/out")"; fi

kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
stop > "$T/out"
if has '"decision":"block"' && has 'plan.md is still open'; then ok "the Stop hook blocks when the watch is gone"; else no "the Stop hook blocks when the watch is gone" "$(cat "$T/out")"; fi
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/out" 2>/dev/null; then ok "the Stop hook writes valid JSON"; else no "the Stop hook writes valid JSON" "$(cat "$T/out")"; fi
stop true > "$T/out"
if [ ! -s "$T/out" ]; then ok "the Stop hook blocks once per stop"; else no "the Stop hook blocks once per stop" "$(cat "$T/out")"; fi
MARGINS_REARM=0 stop > "$T/out"
if [ ! -s "$T/out" ]; then ok "MARGINS_REARM=0 turns the Stop hook off"; else no "MARGINS_REARM=0 turns the Stop hook off" "$(cat "$T/out")"; fi

"$M" watch plan.md > "$T/watch" 2>&1 &
wpid=$!
sleep 1
check "end closes the dialog" "$M" end plan.md "Postgres chosen and applied."
if tail -n 1 plan.md | grep -q "DIALOG CLOSED. Postgres chosen"; then ok "the close is written in the file"; else no "the close is written in the file" "$(tail -n 3 plan.md)"; fi
for _ in $(seq 1 10); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.5; done
if grep -q "dialog closed, watch ended" "$T/watch" && ! kill -0 "$wpid" 2>/dev/null; then ok "the watch ends itself on close"; else no "the watch ends itself on close" "$(cat "$T/watch")"; fi
stop > "$T/out"
if [ ! -s "$T/out" ]; then ok "the Stop hook is quiet once the dialog is closed"; else no "the Stop hook is quiet once the dialog is closed" "$(cat "$T/out")"; fi

check "reopen lifts the close" "$M" reopen plan.md
stop > "$T/out"
if has '"decision":"block"'; then ok "a reopened dialog needs a watch again"; else no "a reopened dialog needs a watch again" "$(cat "$T/out")"; fi

events=$(cut -f2 "$MARGINS_DIR/s1.log" | tr '\n' ' ')
case $events in
"open open turn reply turn watch save turn reply unwatch watch closed unwatch open ") ok "the state file records each step" ;;
*) no "the state file records each step" "$events" ;;
esac

git -C "$T" status > /dev/null 2>&1 && no "no repository is made in the folder itself" || ok "no repository is made in the folder itself"
"$M" version | grep -q "^margins [0-9]" && ok "version" || no "version"

echo "1..$n"
echo "# $n tests, $failed failed"
[ "$failed" -eq 0 ]
