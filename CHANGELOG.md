# Changelog

## 1.0.0

The first public release. margins grew out of a personal Claude Code skill named `file-dialog`.

- A Claude Code plugin: install with two commands, `margins` on the Bash tool's PATH.
- A band above the prompt with one row per dialog: whose turn it is, and whether the file is watched.
- A Stop hook that keeps Claude from ending its turn while a dialog is open and nothing watches it.
- A per-session state file that each command appends to, which the band and the hook read.
- `margins version` and `margins help`.
- Works on macOS: `cksum` replaces `sha1sum`.
