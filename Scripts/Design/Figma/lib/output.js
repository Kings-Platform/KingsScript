// Writes the artifacts to disk. One extraction = one new `<file>_<date_time>` folder; nothing is overwritten.
import { mkdirSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { treeText } from "./tree.js";

// Filesystem-safe name that keeps whatever is readable from the original.
export function slug(name, max = 60) {
  const s = (name ?? "")
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  return (s || "unnamed").slice(0, max).replace(/-+$/, "");
}

// Local time as YYYY-MM-DD_HHMM, sortable in a folder listing.
export function stamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}`;
}

export const outDirName = (figPath, date) => `${slug(basename(figPath).replace(/\.fig$/i, ""), 80)}_${stamp(date)}`;

// Extension from magic bytes — the .fig stores the raw raster with no file name.
function imageExt(bytes) {
  const b = bytes;
  if (b[0] === 0x89 && b[1] === 0x50) return "png";
  if (b[0] === 0xff && b[1] === 0xd8) return "jpg";
  if (b[0] === 0x47 && b[1] === 0x49) return "gif";
  if (b[8] === 0x57 && b[9] === 0x45) return "webp";
  return "bin";
}

// Normalized fills come out as `image(<hash>, MODE)`, so the hash is read back from that text.
export function collectImageHashes(tree, acc = new Set()) {
  for (const key of ["fills", "strokes"]) {
    for (const v of tree[key] ?? []) {
      const m = /^image\(([0-9a-f]{40})/.exec(v);
      if (m) acc.add(m[1]);
    }
  }
  for (const c of tree.children ?? []) collectImageHashes(c, acc);
  return acc;
}

// Copies the rasters to images/, named by hash so the tree's `fill:image(<hash>)` points straight at them.
export function writeImages(doc, hashes, outDir) {
  if (!hashes.size) return [];
  const dir = join(outDir, "images");
  mkdirSync(dir, { recursive: true });
  const written = [];
  for (const h of hashes) {
    const bytes = doc.images?.get(h);
    if (!bytes) continue;
    const file = `${h}.${imageExt(bytes)}`;
    writeFileSync(join(dir, file), bytes);
    written.push(file);
  }
  return written;
}

// The thumbnail embedded in the .fig — the only picture of the file without opening Figma.
export function writeThumbnail(doc, outDir) {
  if (!doc.thumbnail?.length) return null;
  writeFileSync(join(outDir, "thumbnail.png"), doc.thumbnail);
  return "thumbnail.png";
}

// Writes a frame's `.tree.txt` + `.json` and returns their relative paths for the index.
export function writeFrame(outDir, { page, node, tree, stats, source }) {
  const pageDir = slug(page.name, 40);
  const dir = join(outDir, "frames", pageDir);
  mkdirSync(dir, { recursive: true });
  const base = `${slug(node.name)}--${tree.id.replace(":", "-")}`;
  const head = [
    `# ${JSON.stringify(node.name)} — page ${JSON.stringify(page.name)} — ${tree.w}x${tree.h}`,
    `${stats.nodes} nodes · ${stats.expanded} instances expanded · ${stats.overridesApplied} overrides applied${stats.truncated ? " · WARNING: TRUNCATED by --max-nodes" : ""}`,
  ];
  if (stats.unresolvedComponents.length) {
    const u = [...new Set(stats.unresolvedComponents)];
    head.push(`WARNING: ${u.length} external library components, with no content in the file: ${u.slice(0, 5).join(", ")}${u.length > 5 ? `, +${u.length - 5}` : ""}`);
  }
  writeFileSync(join(dir, `${base}.tree.txt`), `${head.join("\n")}\n\n${treeText(tree)}\n`);
  writeFileSync(join(dir, `${base}.json`), `${JSON.stringify({ page: page.name, frame: node.name, source, stats, tree }, null, 2)}\n`);
  return { tree: `frames/${pageDir}/${base}.tree.txt`, json: `frames/${pageDir}/${base}.json` };
}

const CONTAINERS = new Set(["FRAME", "SECTION", "SYMBOL", "INSTANCE", "GROUP", "BOOLEAN_OPERATION"]);
const dim = (n) => (n.size ? `${Math.round(n.size.x)}x${Math.round(n.size.y)}` : "-");

// The entry point for an AI in a new session: full catalog, links to what was extracted, and the command for the rest.
export function writeIndex(outDir, { doc, figPath, pages, childrenOf, nodeKey, isRemoved, extracted, date, images }) {
  const L = [];
  L.push(`# ${doc.meta?.file_name ?? basename(figPath)}`);
  L.push("");
  L.push(`Extracted from \`${figPath}\` on ${date.toLocaleString("en-US")}.`);
  L.push(`fig-kiwi v${doc.header?.version} · ${doc.nodes.length.toLocaleString("en-US")} nodes · ${pages.length} pages · ${doc.images?.size ?? 0} images in the file · ${images.length} copied here`);
  L.push("");
  L.push("## How to read");
  L.push("");
  L.push("1. Find the screen in the table of the right page, below.");
  L.push("2. Open its `.tree.txt` — it's the main read: one line per node, with size, position, auto-layout, color, font and text.");
  L.push("3. Only go to the `.json` when you need a value the tree doesn't show (font postscript, letterSpacing, gradient stops).");
  L.push("");
  L.push("Tree conventions: `~` before the type = node came from inside a component · `@x,y` = position relative to the parent · `AL:` = auto-layout (`gap`, `pad` as top,right,bottom,left) · `c:` = constraints · `fill:image(<hash>)` points to the file in `images/`.");
  L.push("");
  L.push("To extract a frame that wasn't extracted yet:");
  L.push("");
  L.push("```");
  L.push(`kings fig-parse "${figPath}" --id <id from the table>`);
  L.push("```");
  L.push("");
  L.push("## Pages");
  for (const page of pages) {
    const tops = childrenOf(doc, page).filter((n) => !isRemoved(n));
    const containers = tops.filter((n) => CONTAINERS.has(n.type));
    const loose = tops.length - containers.length;
    L.push("");
    L.push(`### ${page.name}`);
    L.push("");
    L.push(`${tops.length} top-level nodes — ${containers.length} containers${loose ? `, ${loose} loose nodes (annotation, arrow, screenshot)` : ""}.`);
    if (!containers.length) continue;
    L.push("");
    L.push("| Frame | Type | Size | id | Extracted |");
    L.push("|---|---|---|---|---|");
    for (const n of containers) {
      const key = nodeKey(n);
      const e = extracted.get(key);
      const links = e ? `[tree](${e.tree}) · [json](${e.json})` : "—";
      L.push(`| ${n.name.replace(/\|/g, "\\|")} | ${n.type} | ${dim(n)} | \`${key}\` | ${links} |`);
    }
  }
  L.push("");
  writeFileSync(join(outDir, "index.md"), `${L.join("\n")}\n`);
  return "index.md";
}
