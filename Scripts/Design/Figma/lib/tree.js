// Text tree: one line per node with what drives implementation — the JSON is only for exact values.
// A `~` before the type means the node came from expanding a component (it isn't loose on the screen).

const q = (s) => JSON.stringify(s ?? "");
const short = (s, max = 60) => (s.length > max ? `${s.slice(0, max)}…` : s);

// Builds the property list of one line, skipping everything the node doesn't set.
function props(n) {
  const p = [];
  if (n.w !== undefined || n.h !== undefined) p.push(`${n.w ?? "?"}x${n.h ?? "?"}`);
  p.push(`@${n.x},${n.y}`);
  if (n.rotation) p.push(`rot:${n.rotation}°`);
  if (n.layout) {
    const l = n.layout;
    const pad = l.padding.every((v) => v === l.padding[0]) ? `${l.padding[0]}` : l.padding.join(",");
    p.push(`AL:${l.direction} gap:${l.gap} pad:${pad}${l.justify ? ` justify:${l.justify}` : ""}${l.align ? ` align:${l.align}` : ""}`);
  }
  if (n.layoutChild?.grow) p.push("grow");
  if (n.layoutChild?.absolute) p.push("absolute");
  if (n.layoutChild?.alignSelf) p.push(`self:${n.layoutChild.alignSelf}`);
  if (n.constraints) p.push(`c:${n.constraints.h}/${n.constraints.v}`);
  if (n.radius !== undefined) p.push(`r:${Array.isArray(n.radius) ? n.radius.join("/") : n.radius}`);
  if (n.fills) p.push(`fill:${n.fills.map((f) => short(f, 48)).join(" + ")}`);
  if (n.strokes) p.push(`stroke:${n.strokes.join(" + ")}${n.strokeWeight ? ` ${n.strokeWeight}px` : ""}${n.strokeAlign ? ` ${n.strokeAlign}` : ""}`);
  if (n.effects) p.push(n.effects.join(" "));
  if (n.opacity !== undefined) p.push(`opacity:${n.opacity}`);
  if (n.blendMode) p.push(`blend:${n.blendMode}`);
  if (n.visible === false) p.push("HIDDEN");
  if (n.mask) p.push("MASK");
  if (n.clip) p.push("clip");
  if (n.scrollDirection) p.push(`scroll:${n.scrollDirection}`);
  if (n.font) {
    const f = n.font;
    p.push(`font:${[f.family, f.style].filter(Boolean).join("/")} ${f.size ?? "?"}${f.lineHeight ? ` lh:${f.lineHeight}` : ""}${f.letterSpacing ? ` ls:${f.letterSpacing}` : ""}${f.align ? ` ${f.align}` : ""}${f.case ? ` ${f.case}` : ""}${f.truncation ? ` ${f.truncation}` : ""}${f.maxLines ? ` maxLines:${f.maxLines}` : ""}`);
  }
  if (n.componentSource) p.push(`component:${n.componentSource}`);
  if (n.truncatedAt) p.push(`[truncated: ${n.truncatedAt}]`);
  return p.join("  ");
}

// Depth-first, two spaces of indent per level.
export function renderTree(node, { indent = 0, lines = [] } = {}) {
  const type = `${node.fromComponent ? "~" : ""}${node.type}`;
  const text = node.text !== undefined ? ` text:${q(short(node.text.replace(/\n/g, "\\n"), 80))}` : "";
  lines.push(`${"  ".repeat(indent)}${type} ${q(node.name)}${text}  ${props(node)}`.trimEnd());
  for (const c of node.children ?? []) renderTree(c, { indent: indent + 1, lines });
  return lines;
}

export const treeText = (node) => renderTree(node).join("\n");
