# KingsScript — Graph

`kings graph` queries a code dependency graph built by [Graphify](https://github.com/Graphify-Labs/graphify)
(tree-sitter AST extraction — no API key, no network, zero LLM tokens). Mostly run by AI agents
instead of ad-hoc grep, so the output is compact and every query opens with a staleness banner.

#### Index

- [Requirements](#requirements)
- [Commands](#commands)
- [Paths](#paths)
- [Gotchas](#gotchas)
- [For AI agents](#for-ai-agents)

## Requirements

| Tool | Install |
|---|---|
| Python 3 | System one — standard library only |
| Graphify | `uv tool install graphifyy` — the package has two y's, the binary is `graphify` |

```bash
# No uv yet
brew install uv

# Install, then put ~/.local/bin on the PATH (restart the shell after)
uv tool install graphifyy
uv tool update-shell
```

> Don't `pip install` it on macOS — it breaks with `ModuleNotFoundError`. `graph` finds the binary
> on the `PATH`, then in `~/.local/bin`.

## Commands

| Command | Answers |
|---|---|
| `kings graph info` | Graph state: which branch/commit it came from and how far behind the working tree it is |
| `kings graph find <pattern>` | Name → graph node(s), with id, flagging `[protocol]` |
| `kings graph deps <Type>` | Full dependency survey: stored **and** init-only dependencies, what the init builds, contract width, existing tests/mocks, methods, callers |
| `kings graph impact <Type> [depth]` | Blast radius of changing a type, grouped by module and depth (default `2`) |
| `kings graph update [path]` | Regenerates the graph and stamps `SOURCE.json` with branch, commit and time |

Every command accepts `--graph DIR`. Exit codes: `0` success · `1` error.

## Paths

| What | Resolved from |
|---|---|
| Graph folder | `--graph DIR` → `$KINGS_GRAPH_DIR` → `<git root of the cwd>/graphify-out` |
| `graph.json` | `<graph folder>/graph.json`, or `<graph folder>/graphify-out/graph.json` |
| `SOURCE.json` | Next to `graph.json` — read from one folder up when the graph is inside `graphify-out/` and it's only there (older layout) |
| Repo `update` reads | `[path]`, else the git root of the cwd — must be a git repo |

To keep the graph out of the repo, point `KINGS_GRAPH_DIR` (in `config.env`) at any other folder.
`update` runs `graphify extract <repo> --code-only --no-cluster --out <folder>` and moves the
`graphify-out/cache/` that `extract` leaks into the repo next to the graph.

> [!NOTE]
> A graphify without `extract` falls back to `graphify update <repo>`, which can only write to
> `<repo>/graphify-out` — any other graph folder asks for `uv tool upgrade graphifyy`.

## Gotchas

- **Regenerating the graph is the user's call.** A graph behind the working tree is the normal
  state, not a bug — every query prints the drift (commits ahead/behind, source files changed,
  uncommitted files) so nobody trusts a stale graph silently.
- `deps` exists because `graphify explain <Type>` doesn't roll up method parameters — looking only
  at the type's node, a dependency injected through the init seems not to exist.
- `deps` is tuned for Swift (stored fields, `implements` → protocol). On other languages
  `find`, `impact` and `info` work the same, but `deps` marks every init parameter as init-only.
- The graph fails by silent omission and knows nothing about behavior — a starting point, never the
  source of truth. Without `SOURCE.json`, the banner uses graphify's own `built_at_commit`.

## For AI agents

Snippet for a project's `CLAUDE.md`:

```markdown
### Dependency graph — check before grepping
`kings graph deps | impact | find | info` queries a local dependency graph of this repo in ~1s,
at zero LLM cost. It names the function holding each reference and types the relationship
(`inherits` ≠ `calls` ≠ `references`). Starting point, never source of truth: read the staleness
banner and confirm behavior in the code. Never run `kings graph update` unless asked.
```
