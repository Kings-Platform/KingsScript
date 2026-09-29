#!/usr/bin/env node
// `kings fig-parse <file.fig> [flags]`: turns a Figma .fig into AI-readable artifacts (catalog, node tree, JSON).
// Every run writes to a new `<file>_<date_time>` folder, so an older extraction is never overwritten.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { FIG_DIR, requireDependencies } from "./lib/env.js";

let of, pagesOf, childrenOf, nodeKey, isRemoved, extractTree, treeText, toSVG, countGeometry;
let outDirName, writeFrame, writeIndex, writeImages, writeThumbnail, collectImageHashes, slug;

const USAGE = `Usage: kings fig-parse <file.fig> [flags]

  (no filter)          writes only the catalog (index.md + thumbnail)
  --frame <text>       extracts the top-level frame whose name contains <text>
  --id <sid:lid>       extracts by exact id (disambiguates repeated names)
  --all-frames         extracts every top-level container (use with --page)
  --page <text>        limits to pages whose name contains <text>

  --out <folder>       output root (default: $KINGS_FIG_DIR, or ~/Documents/FigExtracts)
  --stdout             prints to the screen instead of writing to disk
  --json               with --stdout, prints JSON instead of the tree
  --images used|all|none   which images to copy (default: used)
  --svg <id|name>      converts that node (and its subtree) to SVG in icons/. Repeatable.
                       Never runs on its own: only converts what you explicitly ask for

  --all                in the catalog, also lists loose nodes
  --include-hidden     includes nodes with visible:false
  --no-expand          doesn't expand INSTANCE (doesn't resolve the referenced SYMBOL)
  --depth <n>          maximum tree depth (default 40)
  --max-nodes <n>      node cap per frame (default 20000)`;

const CONTAINERS = new Set(["FRAME", "SECTION", "SYMBOL", "INSTANCE", "GROUP", "BOOLEAN_OPERATION"]);
const match = (name, needle) => (name ?? "").toLowerCase().includes(needle.toLowerCase());
const dim = (n) => (n.size ? `${Math.round(n.size.x)}x${Math.round(n.size.y)}` : "-");
const isId = (t) => /^\d+:\d+$/.test(t);

// Runs before the dependency check, so --help and usage errors work without npm install.
function parseArgs(argv) {
  const o = { file: null, page: null, frame: null, id: null, allFrames: false, svg: [], out: FIG_DIR, stdout: false, json: false, images: "used", all: false, includeHidden: false, expand: true, depth: 40, maxNodes: 20000 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--page") o.page = argv[++i];
    else if (a === "--frame") o.frame = argv[++i];
    else if (a === "--id") o.id = argv[++i];
    else if (a === "--all-frames") o.allFrames = true;
    else if (a === "--out") o.out = argv[++i];
    else if (a === "--stdout") o.stdout = true;
    else if (a === "--json") o.json = true;
    else if (a === "--images") o.images = argv[++i];
    else if (a === "--svg") o.svg.push(argv[++i]);
    else if (a === "--all") o.all = true;
    else if (a === "--include-hidden") o.includeHidden = true;
    else if (a === "--no-expand") o.expand = false;
    else if (a === "--depth") o.depth = Number(argv[++i]);
    else if (a === "--max-nodes") o.maxNodes = Number(argv[++i]);
    else if (a === "-h" || a === "--help") { console.log(USAGE); process.exit(0); }
    else if (a.startsWith("--")) { console.error(`ERROR: Unknown flag: ${a}\n\n${USAGE}`); process.exit(1); }
    else o.file = a;
  }
  if (!o.file) { console.error(USAGE); process.exit(1); }
  if (!["used", "all", "none"].includes(o.images)) { console.error("ERROR: --images accepts used|all|none"); process.exit(1); }
  return o;
}

// Loaded only after the dependency check: a static import would crash before any message could be printed.
async function loadModules() {
  requireDependencies();
  of = await import("openfig-core");
  ({ pagesOf, childrenOf, nodeKey, isRemoved } = await import("./lib/fig.js"));
  ({ extractTree } = await import("./lib/extract.js"));
  ({ treeText } = await import("./lib/tree.js"));
  ({ toSVG, countGeometry } = await import("./lib/svg.js"));
  ({ outDirName, writeFrame, writeIndex, writeImages, writeThumbnail, collectImageHashes, slug } = await import("./lib/output.js"));
}

// Fails with the path instead of a raw ENOENT stack.
function resolveFigFile(file) {
  const figPath = resolve(file);
  if (!existsSync(figPath)) { console.error(`ERROR: File not found: ${figPath}`); process.exit(1); }
  return figPath;
}

// A real file peaks near 1 GB of heap here — the reason the dispatcher raises --max-old-space-size.
async function parseFigFile(figPath) {
  console.error(`Parsing ${figPath}…`);
  return of.parseFig(new Uint8Array(readFileSync(figPath)));
}

// Top-level frames that match the command-line filters.
function selectFrames(doc, opts) {
  const pages = pagesOf(doc).filter((p) => !opts.page || match(p.name, opts.page));
  const hits = [];
  for (const page of pages) {
    for (const n of childrenOf(doc, page)) {
      if (isRemoved(n)) continue;
      if (opts.id) { if (nodeKey(n) === opts.id) hits.push({ page, node: n }); }
      // --frame only looks at containers: a loose annotation (TEXT/VECTOR) is never the screen you want
      else if (opts.frame) { if (CONTAINERS.has(n.type) && match(n.name, opts.frame)) hits.push({ page, node: n }); }
      else if (opts.allFrames && CONTAINERS.has(n.type)) hits.push({ page, node: n });
    }
  }
  return { pages, hits };
}

// Same extraction options for every frame of a run.
function extractFrame(doc, node, opts) {
  return extractTree(doc, node, {
    includeHidden: opts.includeHidden,
    expandInstances: opts.expand,
    maxDepth: opts.depth,
    maxNodes: opts.maxNodes,
  });
}

// A node only becomes SVG if it has its own geometry or some vector descendant.
function hasVector(doc, node, depth = 0) {
  if (node.vectorData || node.fillGeometry?.length || node.strokeGeometry?.length) return true;
  if (depth > 6) return false;
  return childrenOf(doc, node).some((c) => hasVector(doc, c, depth + 1));
}

// Name search looks FIRST in this run's extracted screens (what was just read); falling back to the
// filtered pages is too broad in a real file, where an icon name matches hundreds of nodes.
function findSvgTargets(doc, target, opts, trees = []) {
  if (isId(target)) {
    const n = doc.nodeMap.get(target);
    return { found: n ? [n] : [], scope: "id" };
  }
  if (trees.length) {
    const ids = new Set();
    const visitTree = (n) => {
      if (match(n.name, target)) ids.add(n.id);
      for (const c of n.children ?? []) visitTree(c);
    };
    for (const t of trees) visitTree(t);
    const onScreen = [...ids].map((id) => doc.nodeMap.get(id)).filter((n) => n && hasVector(doc, n));
    if (onScreen.length) return { found: onScreen, scope: "screen" };
  }
  const pages = pagesOf(doc).filter((p) => !opts.page || match(p.name, opts.page));
  const found = [];
  const visit = (n, depth) => {
    if (isRemoved(n) || depth > 40) return;
    if (match(n.name, target) && hasVector(doc, n)) found.push(n);
    for (const c of childrenOf(doc, n)) visit(c, depth + 1);
  };
  for (const p of pages) for (const c of childrenOf(doc, p)) visit(c, 0);
  return { found, scope: trees.length ? "fallback" : "page" };
}

// Ambiguous names write nothing and list the candidates, so the user repeats with the exact id.
function convertSvgs(doc, opts, outDir, trees = []) {
  const written = [];
  for (const target of opts.svg) {
    const { found, scope } = findSvgTargets(doc, target, opts, trees);
    if (!found.length) { console.error(`WARN: --svg "${target}": no vector node with that ${isId(target) ? "id" : "name"}.`); continue; }
    if (found.length > 1 && !isId(target)) {
      const where = scope === "fallback" ? " (not in the extracted screens, so the whole page was searched)" : "";
      console.error(`WARN: --svg "${target}": ${found.length} nodes match${where} — repeat with the exact id:`);
      for (const n of found.slice(0, 8)) console.error(`     --svg ${nodeKey(n)}   ${n.type} ${dim(n)} ${JSON.stringify(n.name)}`);
      if (found.length > 8) console.error(`     … +${found.length - 8}`);
      continue;
    }
    const node = found[0];
    const { tree } = extractTree(doc, node, { includeHidden: opts.includeHidden, expandInstances: opts.expand, maxDepth: opts.depth, maxNodes: opts.maxNodes, withGeometry: true });
    const svg = toSVG(tree, { title: node.name });
    const paths = countGeometry(tree);
    if (!outDir) { console.log(svg); written.push({ id: nodeKey(node), paths }); continue; }
    const dir = join(outDir, "icons");
    mkdirSync(dir, { recursive: true });
    const file = `${slug(node.name)}--${nodeKey(node).replace(":", "-")}.svg`;
    writeFileSync(join(dir, file), svg);
    written.push({ id: nodeKey(node), file: `icons/${file}`, paths });
  }
  return written;
}

// Lists every match with its id, since frame names repeat a lot in real files.
function failOnAmbiguousHits(hits, hint) {
  console.error(`ERROR: ${hits.length} frames match — use ${hint}:`);
  for (const h of hits) console.error(`  --id ${nodeKey(h.node)}   [${h.page.name}] ${h.node.type} ${dim(h.node)} ${JSON.stringify(h.node.name)}`);
  process.exit(1);
}

// --stdout: catalog without a filter, the tree (or JSON) of the selected frames otherwise.
function printToStdout(doc, opts) {
  if (opts.svg.length) { convertSvgs(doc, opts, null); return; }
  const { pages, hits } = selectFrames(doc, opts);
  if (!opts.frame && !opts.id && !opts.allFrames) {
    console.log(`# ${doc.meta?.file_name ?? "(unnamed)"} — fig-kiwi v${doc.header?.version}`);
    console.log(`${doc.nodes.length} nodes · ${pagesOf(doc).length} pages · ${doc.images?.size ?? 0} images\n`);
    for (const page of pages) {
      const tops = childrenOf(doc, page).filter((n) => !isRemoved(n));
      const shown = opts.all ? tops : tops.filter((n) => CONTAINERS.has(n.type));
      console.log(`## ${page.name}  (${tops.length} top-level nodes)`);
      for (const n of shown) console.log(`   ${nodeKey(n).padEnd(12)} ${n.type.padEnd(10)} ${dim(n).padEnd(12)} ${JSON.stringify(n.name)}  (${childrenOf(doc, n).length} children)`);
      const loose = tops.length - shown.length;
      if (loose > 0) console.log(`   … + ${loose} loose nodes — use --all to list them`);
      console.log("");
    }
    return;
  }
  if (!hits.length) { console.error("ERROR: No top-level frame matches the filter. Run without a filter to see the catalog."); process.exit(1); }
  if (hits.length > 1 && !opts.allFrames) failOnAmbiguousHits(hits, "--id, --page or a more specific name");
  for (const { page, node } of hits) {
    const { tree, stats } = extractFrame(doc, node, opts);
    if (opts.json) { console.log(JSON.stringify({ page: page.name, frame: node.name, stats, tree }, null, 2)); continue; }
    console.log(`# ${JSON.stringify(node.name)} — page ${JSON.stringify(page.name)} — ${dim(node)}`);
    console.log(`${stats.nodes} nodes · ${stats.expanded} instances expanded · ${stats.overridesApplied} overrides applied\n`);
    console.log(treeText(tree));
  }
}

// A new folder per run: two extractions in the same minute get a -2, -3 suffix instead of mixing.
function createOutDir(opts, figPath, date) {
  const base = join(resolve(opts.out), outDirName(figPath, date));
  let outDir = base;
  for (let i = 2; existsSync(outDir); i++) outDir = `${base}-${i}`;
  mkdirSync(outDir, { recursive: true });
  return outDir;
}

// Default mode: catalog, selected frames, images, requested SVGs and meta.json in a new folder.
function writeToDisk(doc, opts, figPath) {
  const { hits } = selectFrames(doc, opts);
  if ((opts.frame || opts.id) && !hits.length) {
    console.error("ERROR: No top-level frame matches the filter. Run without a filter to write only the catalog and see the ids.");
    process.exit(1);
  }
  if (hits.length > 1 && !opts.allFrames) failOnAmbiguousHits(hits, "--id, --page or --all-frames");

  const date = new Date();
  const outDir = createOutDir(opts, figPath, date);
  const extracted = new Map();
  const hashes = new Set();
  const trees = [];
  let totalNodes = 0;
  for (const { page, node } of hits) {
    const { tree, stats } = extractFrame(doc, node, opts);
    trees.push(tree);
    totalNodes += stats.nodes;
    if (opts.images === "used") collectImageHashes(tree, hashes);
    extracted.set(nodeKey(node), writeFrame(outDir, { page, node, tree, stats, source: figPath }));
  }

  const images = opts.images === "all" ? writeImages(doc, new Set(doc.images?.keys() ?? []), outDir)
    : opts.images === "used" ? writeImages(doc, hashes, outDir)
      : [];
  const svgs = convertSvgs(doc, opts, outDir, trees);
  const thumb = writeThumbnail(doc, outDir);
  writeIndex(outDir, { doc, figPath, pages: pagesOf(doc), childrenOf, nodeKey, isRemoved, extracted, date, images });
  writeFileSync(join(outDir, "meta.json"), `${JSON.stringify({
    source: figPath,
    extractedAt: date.toISOString(),
    figKiwiVersion: doc.header?.version,
    fileName: doc.meta?.file_name,
    figExportedAt: doc.meta?.exported_at,
    totals: { nodes: doc.nodes.length, pages: pagesOf(doc).length, imagesInFile: doc.images?.size ?? 0 },
    extraction: { frames: hits.length, nodes: totalNodes, imagesCopied: images.length, options: { page: opts.page, frame: opts.frame, id: opts.id, allFrames: opts.allFrames, depth: opts.depth, maxNodes: opts.maxNodes, expandInstances: opts.expand, includeHidden: opts.includeHidden, images: opts.images } },
    command: `kings fig-parse ${process.argv.slice(2).join(" ")}`,
  }, null, 2)}\n`);

  console.log(outDir);
  console.log(`   index.md${thumb ? " · thumbnail.png" : ""} · ${hits.length} frame(s), ${totalNodes} nodes · ${images.length} image(s)`);
  if (!hits.length && !svgs.length) console.error("No frame extracted — open index.md, find the screen's id and run again with --id <id>.");
  for (const [id, f] of extracted) console.log(`   ${id} -> ${f.tree}`);
  for (const sv of svgs) console.log(`   ${sv.id} -> ${sv.file} (${sv.paths} path${sv.paths === 1 ? "" : "s"})`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  await loadModules();
  const figPath = resolveFigFile(opts.file);
  const doc = await parseFigFile(figPath);
  if (opts.stdout) printToStdout(doc, opts);
  else writeToDisk(doc, opts, figPath);
}

main().catch((e) => {
  console.error(`ERROR: ${e.message}`);
  process.exit(1);
});
