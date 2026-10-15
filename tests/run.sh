#!/usr/bin/env bash
# Run every test suite: the script and the Stop hook, then the plugin's mod.
set -u
REPO=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)
failed=0
bash "$REPO/tests/cli.sh" "$REPO" || failed=1
if command -v claude > /dev/null; then
    claude plugin validate --strict "$REPO" || failed=1
    claude plugin test "$REPO" || failed=1
else
    echo "# claude not found: skipping the plugin's tests"
fi
[ "$failed" -eq 0 ] && echo "all suites passed" || echo "some suites failed"
[ "$failed" -eq 0 ]
