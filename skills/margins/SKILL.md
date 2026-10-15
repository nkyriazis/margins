---
name: file-dialog
description: Hold a conversation inside a file instead of the chat. The file gets its own git history, a watch fires on each of the user's saves, and Claude reads the diff, answers in place beneath what they wrote, and acts on what they decided. Use when the user says to "watch" a file, to answer "in the file", to put a file "in isolated versioning", or to work through a list of open calls by editing a document.
---

# File dialog

The user's brief, 2026-10-14: "put this file in isolated versioning and
watch it. each time i save you read the diff and pick up the conversation
there." It worked for five open calls on a video edit, in one file, with
replies, questions back, and decisions applied as they landed: "I liked
this, we should make a skill out of it."

A save is a turn. The diff since the last turn is the user's message. The
file holds the whole thread, in order, under each item.

## Set up

1. Write the file (or take the user's). One item per numbered section, with
   the question, the context they need and the default. End each item with
   the question it asks.
2. `~/.claude/skills/file-dialog/dialog.sh init <file>`: a history of its
   own, `.<name>.dialog.git` beside the file, never the project's repo and
   never staged there. The project's `.gitignore` should already cover the
   folder; check, and say if it does not.
3. Arm a Monitor with `dialog.sh watch <file>`, `timeout_ms` at the maximum,
   described as "saves to <file>". It emits only when the file, once still
   for two seconds, differs from the last turn, so a reply Claude writes and
   commits does not fire it. Re-arm on every expiry until the dialog ends.
4. Tell the user the path, that each save is a turn, and that anything
   unanswered keeps its default.

## Each turn

1. `dialog.sh turn <file>`: prints every line the user added or changed,
   numbered as the file now stands ("author line 25: Nikos. Under load
   ..."), what they removed, and the diff, then commits it as their turn. Read it whole, and never pipe it into `head` or `sed q`: a cut
   pipe kills it before the commit, and the same turn comes back next time. If it says "no edit since the last turn", the event
   was ours or a no-op save: say nothing in the file.
2. Sort each block the way the react-loop sorts a note: a decision ("yes",
   "go with yours", their own words) is applied in the project now; a
   question is answered; an idea with a question mark is built, with any
   objection in one line beside it.
3. Write each reply to a scratch file and place it with
   `dialog.sh reply <file> <line> <scratch>`, where `<line>` is the number of
   the last line of *their words* in that item, from step 1. A changed
   line can be a box ticked on the next item's heading: replying after it
   lands the reply inside the wrong item (it nearly did on the second
   dialog). **Never place a reply by matching text.** An
   anchor that runs into the next block splits that block: twice in the
   first dialog a reply landed after the next item's heading, cutting "5."
   and "Full" off their lines. When several blocks get replies, place them
   from the bottom of the file up, so earlier numbers still hold.
4. Reply in the user's thread format (`Name: ...` / `Claude: ...`, indented
   under the item), short, the point first. Say what was done, not that it
   will be: "Applied, restaged, gate passes" with the commit.
5. In chat, one line per item that moved, and the path. The file is the
   record; the chat is the notice.

## The end

The end is said, in the file and in the chat, so neither side is left
wondering whether the other is still listening.

- **It ends when** every item is closed (applied, or "closed, no change"),
  or the user writes that it is done ("done", "that's all", "end"), or
  says so in the chat.
- **Then**, in this order:
  1. `dialog.sh end <file> "<what was decided, what was applied, what is left>"`
     appends a `DIALOG CLOSED.` line naming the outcome, commits it and tags
     the history `closed`. The watch sees the tag and exits on its own,
     printing "dialog closed, watch ended"; that event is the proof it
     stopped. If it does not arrive within a few seconds, stop the Monitor
     with TaskStop.
  2. In the chat, one line: closed, the outcome, and that nothing is
     watched any more.
- **An expiry is not an end.** A watch that times out while items are
  still open is re-armed, and the chat says nothing. Expiry with every item
  closed and no `end` run is a missed end: run it.
- **Reopen** only when asked: `dialog.sh reopen <file>`, then arm the
  watch again.

## Rules

- **Only the user's words in the diff are their message.** Our own lines
  coming back in a diff mean a turn was not committed: run `turn` before
  writing, and `reply` refuses when the user has unread edits.
- **Do not edit the user's lines.** A typo, a stray line we caused, a
  formatting slip of ours is ours to fix, as its own commit, said in chat.
- **A deleted line is a message too**: the user removing our text, or a
  stray word, is read before anything else.
- **A tick or a plain "yes" needs no reply.** The user deleted a "ticked, closed" line
  (it had also landed inside a reply): the tick is the close. Reply only where there is
  something to say.
- **Close each item explicitly** ("closed, no change" or "applied") and
  end with what remains open, so the file says where the dialog stands.
- **The history is the user's undo.** Never rewrite or squash it.
