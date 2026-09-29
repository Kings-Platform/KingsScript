# KingsScript — DocsCheck

`kings docs-check` checks the hygiene of a markdown docs tree, deterministically — it reports and
never fixes, since what a broken link meant to point at is a human call.

## Usage

| Check | Line | Catches |
|---|---|---|
| Relative `.md` link that doesn't resolve | `BROKEN` | A file renamed or moved, with links still pointing to the old path |
| `#anchor` missing in the target page | `ANCHOR` | A section renamed, with the index still linking the old name |
| Page not reachable, following links, from its `README.md` | `ORPHAN` | A page nobody links to |
| `docs/...md` cited by a skill that doesn't exist | `SKILL` | Skill and docs out of sync |
| Anchor to a heading with emoji | `EMOJI` | Warning only — see below |

| Flag | Effect |
|---|---|
| `--root DIR` | Folder to check |
| `--skip PREFIX` | Link prefix that isn't validated, e.g. a path into another repo — repeatable |
| `--no-global` | Skips `~/.claude/CLAUDE.md` and `~/.claude/agents/` — checked by default, since they cite the docs too |
| `-v` | Also lists every file checked |

Exit codes: `1` on any problem (or a bad argument) · `0` when clean or with warnings only.

## Paths

| What | Resolved from |
|---|---|
| Root | `--root DIR` → `$KINGS_DOCS_ROOT` → the current folder |
| Pages | `<root>/docs/`, or `<root>` itself when there's no `docs/` |
| Also checked | `<root>/CLAUDE.md` and every `.md` under `<root>/.claude/` (skills, agents) |
| Index of a page | The closest `README.md` up the tree — a subfolder with its own README owns its subtree |

Hidden folders and `node_modules/` are skipped. `ai-sessions/` folders are append-only logs, so
their files aren't required to be indexed one by one.

## Gotchas

- Anchors follow GitHub's slug rule, where **each space becomes a hyphen** without collapsing —
  `## A — B` becomes `a--b` once the em dash is dropped. Collapsing spaces reports false positives.
- Renderers disagree on emoji in slugs, so an anchor to such a heading is a warning. The fix is to
  drop the emoji from the heading and keep the status in a table.
- A page counts as indexed when the README links it, links a page that links it (transitively), or
  names the file in its text.
- It doesn't catch semantic drift — a rule that changed meaning in a page that's still linked
  looks fine.
