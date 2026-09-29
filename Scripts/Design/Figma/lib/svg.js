// Vector node -> SVG. Opt-in (`--svg` only): icons are normally exported from Figma itself.
// Two cases exist in real files: resolved geometry (`fillGeometry`/`strokeGeometry`, where openfig-core
// gives the svgPath) and only a vector network blob — the common case for outline icons, built here.
import * as of from "openfig-core";

const n2 = (v) => Math.round(v * 1000) / 1000;

// Solid paint -> { color, opacity } as SVG wants them (hex apart from alpha).
function svgPaint(paint) {
  if (!paint || paint.visible === false) return null;
  const op = paint.opacity ?? 1;
  if (paint.type === "SOLID" && paint.color) {
    const c = paint.color;
    const hex = "#" + [c.r, c.g, c.b].map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("").toUpperCase();
    return { color: hex, opacity: (c.a ?? 1) * op, approximated: false };
  }
  // Gradients and images aren't reproduced faithfully: the first stop stands in, and it's FLAGGED so
  // nobody treats the output as true to the design.
  const stop = paint.stops?.[0]?.color;
  if (stop) {
    const hex = "#" + [stop.r, stop.g, stop.b].map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("").toUpperCase();
    return { color: hex, opacity: (stop.a ?? 1) * op, approximated: paint.type };
  }
  return { color: "#000000", opacity: op, approximated: paint.type };
}

// Segments come loose and unordered: chains them by shared vertex, flipping a segment that comes reversed.
function networkToPath(net) {
  const { vertices: V, segments: S } = net;
  if (!S.length) return "";
  const used = new Set();
  const byVertex = new Map();
  S.forEach((s, i) => {
    for (const v of [s.start.vertex, s.end.vertex]) {
      if (!byVertex.has(v)) byVertex.set(v, []);
      byVertex.get(v).push(i);
    }
  });

  const commandOf = (seg, reversed) => {
    const a = reversed ? seg.end : seg.start;
    const b = reversed ? seg.start : seg.end;
    const pa = V[a.vertex];
    const pb = V[b.vertex];
    const straight = !a.dx && !a.dy && !b.dx && !b.dy;
    if (straight) return `L${n2(pb.x)} ${n2(pb.y)}`;
    return `C${n2(pa.x + a.dx)} ${n2(pa.y + a.dy)} ${n2(pb.x + b.dx)} ${n2(pb.y + b.dy)} ${n2(pb.x)} ${n2(pb.y)}`;
  };
  const neighbor = (vertex) => (byVertex.get(vertex) ?? []).find((i) => !used.has(i));

  const parts = [];
  for (let start = 0; start < S.length; start++) {
    if (used.has(start)) continue;
    used.add(start);
    let seg = S[start];
    const cmds = [`M${n2(V[seg.start.vertex].x)} ${n2(V[seg.start.vertex].y)}`, commandOf(seg, false)];
    const firstVertex = seg.start.vertex;
    let current = seg.end.vertex;

    for (let next = neighbor(current); next !== undefined; next = neighbor(current)) {
      used.add(next);
      seg = S[next];
      const reversed = seg.start.vertex !== current;
      cmds.push(commandOf(seg, reversed));
      current = reversed ? seg.start.vertex : seg.end.vertex;
    }
    if (current === firstVertex) cmds.push("Z");
    parts.push(cmds.join(""));
  }
  return parts.join(" ");
}

// `merged` is the node with its override applied — it holds the paints that apply to this instance.
export function buildGeometry(doc, node, merged) {
  const paths = [];
  let resolved = { fill: [], stroke: [] };
  // Argument order is (doc, node): reversed, it silently returns empty paths instead of throwing.
  try { resolved = of.resolveVectorNodePaths(doc, node); } catch { /* node without resolvable geometry */ }

  // No resolvable paint means the node is NOT drawn: a black default would paint the instance's own
  // invisible frame over the whole icon.
  for (const p of resolved.fill ?? []) {
    const paint = svgPaint((p.paints ?? merged.fillPaints)?.[0]);
    if (!paint) continue;
    paths.push({ d: p.svgPath, fill: paint.color, fillOpacity: paint.opacity, fillRule: p.windingRule === "ODD" ? "evenodd" : "nonzero", approximated: paint.approximated });
  }
  for (const p of resolved.stroke ?? []) {
    // Stroke geometry already comes as a filled region — that's why it's painted with `fill`.
    const paint = svgPaint((p.paints ?? merged.strokePaints)?.[0]);
    if (!paint) continue;
    paths.push({ d: p.svgPath, fill: paint.color, fillOpacity: paint.opacity, fillRule: "nonzero", approximated: paint.approximated });
  }

  if (!paths.length && node.vectorData?.vectorNetworkBlob !== undefined) {
    try {
      const net = of.parseVectorNetworkBlob(of.getBlobBytes(doc, node.vectorData.vectorNetworkBlob));
      const d = networkToPath(net);
      // A vector node with no paint at all isn't drawn.
      if (d && (merged.fillPaints?.length || merged.strokePaints?.length)) {
        const fillPaint = svgPaint(merged.fillPaints?.[0]);
        const strokePaint = svgPaint(merged.strokePaints?.[0]);

        // The path lives in `normalizedSize` space; the node may be drawn at another scale.
        const ns = node.vectorData.normalizedSize;
        const sx = ns?.x ? (merged.size?.x ?? ns.x) / ns.x : 1;
        const sy = ns?.y ? (merged.size?.y ?? ns.y) / ns.y : 1;
        paths.push({
          d,
          scale: sx !== 1 || sy !== 1 ? [n2(sx), n2(sy)] : undefined,
          fill: fillPaint?.color,
          fillOpacity: fillPaint?.opacity,
          stroke: strokePaint?.color,
          strokeOpacity: strokePaint?.opacity,
          strokeWidth: merged.strokeWeight,
          // SVG only has centered strokes: Figma's INSIDE/OUTSIDE has no equivalent.
          strokeAlign: merged.strokeAlign,
          linecap: (merged.strokeCap ?? "").toLowerCase() || undefined,
          linejoin: (merged.strokeJoin ?? "").toLowerCase() || undefined,
          approximated: fillPaint?.approximated || strokePaint?.approximated,
        });
      }
    } catch { /* missing blob or a newer format — the node comes out without geometry, and the SVG says so */ }
  }
  return paths.length ? paths : undefined;
}

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// One <path>, writing only the attributes that differ from the SVG defaults.
function pathTag(p, indent) {
  const at = [`d="${p.d}"`];
  if (p.scale) at.push(`transform="scale(${p.scale[0]} ${p.scale[1]})"`);
  at.push(p.fill ? `fill="${p.fill}"` : `fill="none"`);
  if (p.fill && p.fillOpacity !== undefined && p.fillOpacity < 1) at.push(`fill-opacity="${n2(p.fillOpacity)}"`);
  if (p.fillRule === "evenodd") at.push(`fill-rule="evenodd"`);
  if (p.stroke) {
    at.push(`stroke="${p.stroke}"`);
    if (p.strokeOpacity !== undefined && p.strokeOpacity < 1) at.push(`stroke-opacity="${n2(p.strokeOpacity)}"`);
    if (p.strokeWidth) at.push(`stroke-width="${n2(p.strokeWidth)}"`);
    if (p.linecap && p.linecap !== "none") at.push(`stroke-linecap="${p.linecap}"`);
    if (p.linejoin && p.linejoin !== "miter") at.push(`stroke-linejoin="${p.linejoin}"`);
  }
  return `${indent}<path ${at.join(" ")}/>`;
}

// The root goes at the origin: its matrix places the icon INSIDE the screen, which doesn't apply here.
export function toSVG(tree, { title } = {}) {
  const lines = [];
  const warnings = new Set();
  let withGeometry = 0;

  const walk = (node, depth, isRoot) => {
    const ind = "  ".repeat(depth + 1);
    const m = node.matrix;
    const needsGroup = !isRoot && m && (m[0] !== 1 || m[1] !== 0 || m[2] !== 0 || m[3] !== 1 || m[4] !== 0 || m[5] !== 0);
    if (needsGroup) lines.push(`${ind}<g transform="matrix(${m.map(n2).join(" ")})">`);
    const inner = needsGroup ? `${ind}  ` : ind;

    if (node.opacity !== undefined && node.opacity < 1) lines.push(`${inner}<g opacity="${node.opacity}">`);
    for (const p of node.geometry ?? []) {
      lines.push(pathTag(p, node.opacity !== undefined && node.opacity < 1 ? `${inner}  ` : inner));
      withGeometry++;
      if (p.approximated) warnings.add(`${p.approximated} approximated by its first color stop`);
      if (p.strokeAlign && p.strokeAlign !== "CENTER") warnings.add(`strokeAlign ${p.strokeAlign} rendered as centered (SVG has no equivalent)`);
    }
    if (node.opacity !== undefined && node.opacity < 1) lines.push(`${inner}</g>`);

    // A resized instance's content lives in the component's space: scaled here.
    const scale = node.contentScale;
    if (scale) lines.push(`${inner}<g transform="scale(${scale[0]} ${scale[1]})">`);
    for (const c of node.children ?? []) walk(c, depth + (needsGroup ? 1 : 0) + (scale ? 1 : 0), false);
    if (scale) lines.push(`${inner}</g>`);
    if (needsGroup) lines.push(`${ind}</g>`);
  };
  walk(tree, 0, true);

  const w = tree.w ?? 0;
  const h = tree.h ?? 0;
  const head = [`<svg xmlns="http://www.w3.org/2000/svg" width="${n2(w)}" height="${n2(h)}" viewBox="0 0 ${n2(w)} ${n2(h)}" fill="none">`];
  if (title) head.push(`  <title>${esc(title)}</title>`);
  for (const a of warnings) head.push(`  <!-- ${esc(a)} -->`);
  if (!withGeometry) head.push(`  <!-- no vector geometry found in this node -->`);
  return `${[...head, ...lines, "</svg>"].join("\n")}\n`;
}

export const countGeometry = (tree) => (tree.geometry?.length ?? 0) + (tree.children ?? []).reduce((a, c) => a + countGeometry(c), 0);
