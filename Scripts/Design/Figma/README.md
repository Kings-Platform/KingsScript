# Figma — fig-parse and fig-check

Reads a Figma `.fig` file offline and writes text artifacts an AI can implement a screen from:
hierarchy, size, position, auto-layout, fills, strokes, effects, fonts and text, with component
overrides already applied.

#### Index

- [Requirements](#requirements)
- [Commands](#commands)
- [Output](#output)
- [Gotchas](#gotchas)

## Requirements

| Tool | Version |
|---|---|
| Node.js | 20 or newer — tested on 24 |
| [`openfig-core`](https://www.npmjs.com/package/openfig-core) | `^0.4.1`, pure JS, no native build |

```bash
# Install the dependencies once (node_modules/ is not committed)
npm install --prefix Scripts/Design/Figma
```

> Without `node_modules/`, both commands stop with the exact `npm install` line to run.

## Commands

```bash
kings fig-parse <file.fig> [flags]        # catalog, or the frames the flags select
kings fig-check [file.fig] [--update]     # regression check against expected counts
```

Both run through `node --max-old-space-size=8192` — parsing a real file peaks near 1 GB of heap.

**`fig-parse` flags:**

| Flag | What it does |
|---|---|
| *(no filter)* | Writes only the catalog (`index.md` + `thumbnail.png`) |
| `--frame <text>` | Extracts the top-level frame whose name contains `<text>` |
| `--id <sid:lid>` | Extracts by exact id — the reliable selector |
| `--all-frames` | Extracts every top-level container (use with `--page`) |
| `--page <text>` | Limits to pages whose name contains `<text>` |
| `--out <folder>` | Output root — default `$KINGS_FIG_DIR` |
| `--stdout` | Prints to the screen instead of writing to disk |
| `--json` | With `--stdout`, prints JSON instead of the tree |
| `--images used\|all\|none` | Which images to copy — default `used` |
| `--svg <id\|name>` | Converts that vector node to SVG in `icons/` — repeatable, opt-in |
| `--all` | In the catalog, also lists loose nodes |
| `--include-hidden` | Includes nodes with `visible:false` |
| `--no-expand` | Doesn't expand instances — debugging only |
| `--depth <n>` | Maximum tree depth — default `40` |
| `--max-nodes <n>` | Node cap per frame — default `20000` |

**`fig-check`:**

| Call | What it does |
|---|---|
| `kings fig-check` | Checks every `.fig` in `$KINGS_FIG_DIR/figmas/` |
| `kings fig-check <file.fig>` | Checks only that file |
| `kings fig-check <file.fig> --update` | Rewrites its expected counts — for an intentional change |

Exit codes: `0` success · `1` error, mismatch or missing baseline.

## Output

`KINGS_FIG_DIR` (in `~/.kingsScripts/config.env`) defaults to `~/Documents/FigExtracts`.

| Path | What it is |
|---|---|
| `$KINGS_FIG_DIR/<fig-name>_<YYYY-MM-DD_HHMM>/` | One new folder per run — `-2`, `-3` suffix in the same minute |
| `…/index.md` | Catalog: pages and their top-level containers with id and size, links to what was extracted |
| `…/frames/<page>/<frame>--<id>.tree.txt` | The main read — one line per node |
| `…/frames/<page>/<frame>--<id>.json` | Same data, for values the tree hides (font postscript, gradient stops) |
| `…/images/<hash>.<ext>` | Rasters cited in the tree as `fill:image(<hash>)` |
| `…/icons/<name>--<id>.svg` | Only with `--svg` |
| `…/thumbnail.png`, `…/meta.json` | Thumbnail embedded in the `.fig`, and extraction metadata |
| `$KINGS_FIG_DIR/figmas/` | The `.fig` files `fig-check` runs on by default |
| `$KINGS_FIG_DIR/fixtures/<name>.expected.json` | Expected counts per file — outside the repo, so private designs never get committed |

Result lines go to stdout; progress, warnings and errors to stderr.

## Gotchas

- **The typical failure is silent.** A format change or a regression keeps parsing and returns
  less — default component text instead of the screen's, for example. That's why `fig-check`
  compares counts (nodes, expanded instances, applied overrides), not just "it ran".
- `--depth` defaults to 40 on purpose — nested components easily pass 25 levels, and a depth of 8
  cut three quarters of a real screen.
- Frame names repeat a lot (several identical names on one page is common): use `--id` from
  `index.md` whenever more than one frame matches.
- `--svg` is opt-in and never runs on a normal extraction — vector nodes come out as
  `vectorPath: "unavailable"`, which is expected. Gradients and `INSIDE`/`OUTSIDE` strokes are
  approximated, and the SVG says so in a comment.
- `--images all` copies every raster in the file — more than 100 MB on a real one. The default
  `used` copies only what the extracted frames cite.
