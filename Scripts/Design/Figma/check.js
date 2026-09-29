#!/usr/bin/env node
// `kings fig-check [file.fig] [--update]`: regression test of the extractor against per-file expected counts.
// The .fig format changes between Figma versions and openfig-core follows by reverse engineering, so the
// typical break is SILENT — it keeps parsing and returns less. That's why this compares numbers.
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { FIGMAS_DIR, FIXTURES_DIR, requireDependencies } from "./lib/env.js";

let of, pagesOf, childrenOf, isRemoved, nodeKey, extractTree;

const USAGE = `Usage: kings fig-check [file.fig] [--update]

  (no file)            checks every .fig in ${FIGMAS_DIR}
  <file.fig>           checks only that file
  --update             rewrites the expected counts (intentional change)

Expected counts live in ${FIXTURES_DIR}/<name>.expected.json`;

const expectedPathOf = (figPath) => join(FIXTURES_DIR, `${basename(figPath).replace(/\.fig$/i, "")}.expected.json`);

// Runs before the dependency check, so --help works without npm install.
function parseArgs(argv) {
  if (argv.includes("-h") || argv.includes("--help")) { console.log(USAGE); process.exit(0); }
  const unknown = argv.find((a) => a.startsWith("--") && a !== "--update");
  if (unknown) { console.error(`ERROR: Unknown flag: ${unknown}\n\n${USAGE}`); process.exit(1); }
  return { update: argv.includes("--update"), targets: argv.filter((a) => !a.startsWith("--")).map((a) => resolve(a)) };
}

// Loaded only after the dependency check: a static import would crash before any message could be printed.
async function loadModules() {
  requireDependencies();
  of = await import("openfig-core");
  ({ pagesOf, childrenOf, isRemoved, nodeKey } = await import("./lib/fig.js"));
  ({ extractTree } = await import("./lib/extract.js"));
}

// Without arguments, the figmas folder next to the extracts is the test set.
function listTargets(targets) {
  if (targets.length) return targets;
  if (!existsSync(FIGMAS_DIR)) { console.error(`ERROR: Nothing to check: ${FIGMAS_DIR} doesn't exist.`); process.exit(1); }
  const found = readdirSync(FIGMAS_DIR).filter((f) => f.toLowerCase().endsWith(".fig")).map((f) => join(FIGMAS_DIR, f));
  if (!found.length) { console.error(`ERROR: No .fig in ${FIGMAS_DIR}.`); process.exit(1); }
  return found;
}

// The largest top-level frame of each page is a stable sample: if component expansion or override
// resolution regresses, its count drops here before anywhere else.
async function measureFile(figPath) {
  const doc = await of.parseFig(new Uint8Array(readFileSync(figPath)));
  const pages = pagesOf(doc);
  const samples = [];
  for (const page of pages) {
    const tops = childrenOf(doc, page).filter((n) => !isRemoved(n) && n.type === "FRAME" && n.size);
    const largest = tops.sort((a, b) => b.size.x * b.size.y - a.size.x * a.size.y)[0];
    if (!largest) continue;
    const { stats } = extractTree(doc, largest, { maxDepth: 40, maxNodes: 20000 });
    samples.push({ page: page.name, frame: largest.name, id: nodeKey(largest), nodes: stats.nodes, expanded: stats.expanded, overridesApplied: stats.overridesApplied });
  }
  return {
    figKiwiVersion: doc.header?.version,
    nodes: doc.nodes.length,
    pages: pages.length,
    images: doc.images?.size ?? 0,
    instances: doc.nodes.filter((n) => n.type === "INSTANCE").length,
    symbols: doc.nodes.filter((n) => n.type === "SYMBOL").length,
    samples,
  };
}

// Every mismatched count, as readable lines.
function compareCounts(expected, actual) {
  const failures = [];
  const cmp = (field, e, a) => { if (e !== a) failures.push(`${field}: expected ${e}, got ${a}`); };
  for (const k of ["figKiwiVersion", "nodes", "pages", "images", "instances", "symbols"]) cmp(k, expected[k], actual[k]);
  cmp("sample count", expected.samples.length, actual.samples.length);
  for (const e of expected.samples) {
    const a = actual.samples.find((x) => x.id === e.id);
    if (!a) { failures.push(`sample ${e.id} (${e.frame}) is gone`); continue; }
    for (const k of ["nodes", "expanded", "overridesApplied"]) cmp(`${e.frame} [${e.id}] ${k}`, e[k], a[k]);
  }
  return failures;
}

// Rewrites the expected counts — for an intentional change (new openfig-core, extractor edited).
function saveExpected(name, expectedPath, actual) {
  mkdirSync(FIXTURES_DIR, { recursive: true });
  writeFileSync(expectedPath, `${JSON.stringify(actual, null, 2)}\n`);
  console.log(`OK ${name}: expected counts saved (${actual.nodes} nodes, ${actual.samples.length} samples).`);
}

// "ok", "mismatch" (a regression) or "error" (nothing to compare against).
async function checkFile(figPath, update) {
  const name = basename(figPath);
  if (!existsSync(figPath)) { console.error(`ERROR: ${name}: file not found (${figPath})`); return "error"; }
  console.error(`Checking ${name}…`);
  const actual = await measureFile(figPath);
  const expectedPath = expectedPathOf(figPath);

  if (update) { saveExpected(name, expectedPath, actual); return "ok"; }
  if (!existsSync(expectedPath)) { console.error(`ERROR: ${name}: no baseline at ${expectedPath}. Run with --update to save it.`); return "error"; }

  const failures = compareCounts(JSON.parse(readFileSync(expectedPath, "utf8")), actual);
  if (failures.length) {
    console.log(`FAIL ${name}: ${failures.length} mismatch(es)`);
    for (const f of failures) console.log(`   ${f}`);
    return "mismatch";
  }
  console.log(`OK ${name}: no regression — ${actual.nodes} nodes, ${actual.pages} pages, ${actual.samples.length} samples checked.`);
  return "ok";
}

async function main() {
  const { update, targets } = parseArgs(process.argv.slice(2));
  await loadModules();
  const results = [];
  for (const figPath of listTargets(targets)) results.push(await checkFile(figPath, update));
  if (results.includes("mismatch")) console.error("\nIf the change is intentional (new openfig-core, extractor edited), run with --update.");
  process.exit(results.every((r) => r === "ok") ? 0 : 1);
}

main().catch((e) => {
  console.error(`ERROR: ${e.message}`);
  process.exit(1);
});
