# margins

[![CI](https://github.com/nkyriazis/margins/actions/workflows/ci.yml/badge.svg)](https://github.com/nkyriazis/margins/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Talk to your coding agent inside a file, in your own editor, instead of the chat.**

<p align="center">
  <img src="docs/demo.gif" width="900" alt="Claude Code on the left, decisions.md open in Neovim on the right. Claude writes two open calls about cart.py into the file and starts watching it, and a band above the prompt reads 'decisions.md, turn 1, your turn, watching'. The author types 'yes' under the first item and 'clamp it to 0-100, and add a test for both' under the second, then saves. Claude's replies appear in the editor under each answer, the code is changed and tested, and the dialog closes with a summary line while the band reads 'closed after 5 turns'.">
</p>

Some work is a list of decisions: five open calls on a release, a review with a dozen comments, a plan with questions on every step. In the chat, each answer scrolls the last one away. You can't answer item 3 before item 1, and a week later the decisions are buried in a transcript.

With margins, Claude writes the open questions into a file, each with its context and a default. You answer in your editor, in any order, and save. Each save is a turn. Claude reads what you changed, replies beneath your words in the file, and acts on what you decided. The file keeps the whole thread under each item, and it has a git history of its own, so every turn can be undone.

```markdown
## 1. Database for the job queue?
sqlite locks on concurrent writers, and the workers now run four at a time.
Default: postgres. OK?

   Nikos: yes, but keep sqlite for the tests, CI has no postgres.

   Claude: Done. Postgres in prod, sqlite in tests (a3f9e1c), 212 tests pass.
   Closed.

## 2. Ship on Friday?
Two flaky tests left on main. Default: ship, mark them flaky. Ship?

   Nikos: what are they?
```

Above the prompt, Claude Code shows where each dialog stands:

```
✎ release-2.0.md · turn 6 · your turn · watching
```

## Install

In Claude Code, install the plugin:

```
/plugin marketplace add nkyriazis/margins
/plugin install margins@margins
```

Restart Claude Code. For other agents, or just the skill without the plugin, see [More ways to install](#more-ways-to-install).

## Everyday use

Ask for it when a task turns into a list of decisions:

```
review cart.py and put your open calls in decisions.md with margins, then watch it
```

Or hand Claude a file you already have:

```
watch notes/review.md, I'll answer in the file
```

Then work in your editor. Answer, ask back, write "yes", tick a box, delete a line you disagree with, and save. Claude answers in the file and writes one line per item in the chat. When every item is closed, or you write "done", Claude writes a closing line with the outcome and stops watching.

## What you get

- **The file is the conversation.** Each item collects its own thread, in order, right under the question. Nothing is lost to scrollback, and you can come back to it later.
- **Any editor.** vim, VS Code, Obsidian, nano. A save is all margins needs.
- **Decisions are applied, not just noted.** "yes" on a change means Claude makes it, then says what it did and the commit.
- **Its own history.** The file gets a git history in `.<name>.dialog.git` next to it, one commit per turn, separate from your project's repository. `git --git-dir=.<name>.dialog.git log -p` shows every turn, and nothing is ever squashed.
- **Replies land in the right place.** Claude places each reply by line number, after the last line you wrote in that item, never by matching text. A reply can't split the next item's heading.
- **A band above the prompt.** One row per dialog says whose turn it is, and turns red when nothing is watching the file.
- **It doesn't forget to listen.** A watch can expire or die. If Claude is about to stop while a dialog is open and unwatched, a hook stops it and says what to run.
- **A clear end.** The dialog closes in the file and in the chat, so neither side is left wondering whether the other is still listening.

## How it works

`margins.sh` does the mechanical parts, and the [skill](skills/margins/SKILL.md) tells the agent how to hold the conversation.

| Command | What it does |
|---|---|
| `margins init <file>` | Gives the file its own git history, `.<name>.dialog.git`, beside it |
| `margins watch <file>` | Prints one line per real save. Claude Code arms it as a Monitor. A save counts once the file has been still for two seconds and differs from the last turn, so Claude's own replies never fire it |
| `margins turn <file>` | Commits your edit as a turn and prints each line you added or changed with its number, plus what you removed |
| `margins reply <file> <line> <text-file>` | Inserts a reply after that line and commits it. It refuses while you have edits it hasn't read |
| `margins end <file> "<outcome>"` | Writes the closing line, commits, and tags the history `closed`. The watch sees the tag and exits |
| `margins reopen <file>` | Lifts the close |

Each command also appends a line to a small state file for the agent session, in `$XDG_RUNTIME_DIR/margins` or `/tmp/margins-<uid>`. The plugin reads it once a second to draw the band, and the Stop hook reads it to find dialogs with no live watch. Nothing goes over the network.

## Configuration

Set these in the environment, or under `env` in Claude Code's `settings.json`.

| Variable | Default | Effect |
|---|---|---|
| `MARGINS_BAND` | `1` | `0` hides the band above the prompt |
| `MARGINS_REARM` | `1` | `0` turns off the Stop hook that keeps a dialog watched |
| `MARGINS_DIR` | | Where the session state files go |

## Works with

Linux and macOS, bash 3.2 or newer, git and python3. The band and the Stop hook need Claude Code 2.1.287 or newer. The skill works in any agent that reads skills. Without a Monitor tool the agent runs the watch in the background and checks it between turns.

## More ways to install

**Other agents.** `npx skills add nkyriazis/margins` installs the skill for Codex, Gemini CLI, opencode, Cursor, Goose and the other agents `skills` knows about.

**From a clone.** Copy the skill into your skills folder:

```bash
git clone https://github.com/nkyriazis/margins
cp -R margins/skills/margins ~/.claude/skills/
```

**Developing.** `claude --plugin-dir ./margins` loads the plugin from a clone. `tests/run.sh` runs the tests.

## Uninstall

`/plugin uninstall margins@margins`, or remove `~/.claude/skills/margins`. Dialog histories stay next to their files as `.<name>.dialog.git` until you delete them.

## License

MIT
