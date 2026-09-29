// Normalizer: turns a raw .fig node into a lean object with the exact values needed to rebuild the screen.
// Filters noise (glyphs, blobs, geometry) WITHOUT rounding meaning away — a number here is the number in the file.
import { childrenOf, nodeKey, guidKey, resolveSymbol, buildOverrideIndex, isRemoved } from "./fig.js";
import { buildGeometry } from "./svg.js";

const r2 = (v) => (typeof v === "number" ? Math.round(v * 100) / 100 : v);
const pct = (v) => `${Math.round(v * 100)}%`;

// Figma color (0-1 floats) -> hex; alpha becomes a readable suffix instead of 8 digits.
export function color(c, extraOpacity = 1) {
  if (!c) return null;
  const hex = "#" + [c.r, c.g, c.b].map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("").toUpperCase();
  const a = (c.a ?? 1) * extraOpacity;
  return a >= 0.999 ? hex : `${hex} @${pct(a)}`;
}

// One paint as a CSS-like string; hidden paints are dropped.
function paint(p) {
  if (!p || p.visible === false) return null;
  const op = p.opacity ?? 1;
  switch (p.type) {
    case "SOLID":
      return color(p.color, op);
    case "GRADIENT_LINEAR":
    case "GRADIENT_RADIAL":
    case "GRADIENT_ANGULAR":
    case "GRADIENT_DIAMOND": {
      const kind = p.type.replace("GRADIENT_", "").toLowerCase();
      const stops = (p.stops ?? []).map((s) => `${color(s.color, op)} ${pct(s.position ?? 0)}`).join(", ");
      return `${kind}-gradient(${stops})`;
    }
    case "IMAGE": {
      const hash = imageHash(p.image?.hash);
      return `image(${hash ?? "?"}${p.imageScaleMode ? `, ${p.imageScaleMode}` : ""})`;
    }
    default:
      return p.type;
  }
}

// The image hash comes as 20 bytes; the .fig's images/ folder names files by their hex.
export function imageHash(bytes) {
  if (!bytes) return null;
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function paints(list) {
  const out = (list ?? []).map(paint).filter(Boolean);
  return out.length ? out : undefined;
}

// Shadows and blurs as short readable strings; hidden effects are dropped.
function effects(list) {
  const out = [];
  for (const e of list ?? []) {
    if (e.visible === false) continue;
    const off = e.offset ? `${r2(e.offset.x)},${r2(e.offset.y)}` : "0,0";
    switch (e.type) {
      case "DROP_SHADOW":
      case "INNER_SHADOW":
        out.push(`${e.type === "DROP_SHADOW" ? "shadow" : "inner-shadow"}(${color(e.color)}, offset ${off}, blur ${r2(e.radius ?? 0)}${e.spread ? `, spread ${r2(e.spread)}` : ""})`);
        break;
      case "FOREGROUND_BLUR":
      case "LAYER_BLUR":
        out.push(`blur(${r2(e.radius ?? 0)})`);
        break;
      case "BACKGROUND_BLUR":
        out.push(`backdrop-blur(${r2(e.radius ?? 0)})`);
        break;
      default:
        out.push(`${e.type}(${r2(e.radius ?? 0)})`);
    }
  }
  return out.length ? out : undefined;
}

// A single radius, or [tl, tr, br, bl] when the corners are independent.
function corners(n) {
  const ind = n.rectangleCornerRadiiIndependent;
  if (ind) {
    const v = [n.rectangleTopLeftCornerRadius, n.rectangleTopRightCornerRadius, n.rectangleBottomRightCornerRadius, n.rectangleBottomLeftCornerRadius].map((x) => r2(x ?? 0));
    return v.some((x) => x !== 0) ? v : undefined;
  }
  return n.cornerRadius ? r2(n.cornerRadius) : undefined;
}

// The .fig calls it stack*; translated to the vocabulary Figma shows in its UI.
function autoLayout(n) {
  if (!n.stackMode || n.stackMode === "NONE") return undefined;
  const padT = n.stackVerticalPadding ?? 0;
  const padL = n.stackHorizontalPadding ?? 0;
  const padB = n.stackPaddingBottom ?? padT;
  const padR = n.stackPaddingRight ?? padL;
  return {
    direction: n.stackMode === "HORIZONTAL" ? "row" : "column",
    gap: r2(n.stackSpacing ?? 0),
    padding: [r2(padT), r2(padR), r2(padB), r2(padL)], // top, right, bottom, left
    justify: n.stackPrimaryAlignItems,
    align: n.stackCounterAlignItems,
    sizingPrimary: n.stackPrimarySizing,
    sizingCounter: n.stackCounterSizing,
    wrap: n.stackWrap === "WRAP" ? true : undefined,
    reverseZIndex: n.stackReverseZIndex || undefined,
  };
}

// How the node behaves INSIDE its parent's auto-layout.
function layoutChild(n) {
  const out = {};
  if (n.stackChildPrimaryGrow) out.grow = n.stackChildPrimaryGrow;
  if (n.stackChildAlignSelf && n.stackChildAlignSelf !== "AUTO") out.alignSelf = n.stackChildAlignSelf;
  if (n.stackPositioning === "ABSOLUTE") out.absolute = true;
  return Object.keys(out).length ? out : undefined;
}

// MIN/MIN is the default and would only add noise to every line.
function constraints(n) {
  const h = n.horizontalConstraint;
  const v = n.verticalConstraint;
  if (!h && !v) return undefined;
  if ((h ?? "MIN") === "MIN" && (v ?? "MIN") === "MIN") return undefined;
  return { h: h ?? "MIN", v: v ?? "MIN" };
}

// Font and text settings, leaving out the ones at their default.
function typography(n) {
  if (!n.fontName && !n.fontSize) return undefined;
  const lh = n.lineHeight;
  return {
    family: n.fontName?.family,
    style: n.fontName?.style,
    postscript: n.fontName?.postscript,
    size: r2(n.fontSize),
    lineHeight: lh ? (lh.units === "PERCENT" ? `${r2(lh.value)}%` : lh.units === "RAW" ? "auto" : r2(lh.value)) : undefined,
    letterSpacing: n.letterSpacing ? (n.letterSpacing.units === "PERCENT" ? `${r2(n.letterSpacing.value)}%` : r2(n.letterSpacing.value)) : undefined,
    align: n.textAlignHorizontal,
    alignVertical: n.textAlignVertical !== "TOP" ? n.textAlignVertical : undefined,
    case: n.textCase && n.textCase !== "ORIGINAL" ? n.textCase : undefined,
    decoration: n.textDecoration && n.textDecoration !== "NONE" ? n.textDecoration : undefined,
    autoResize: n.textAutoResize,
    maxLines: n.maxLines,
    truncation: n.textTruncation && n.textTruncation !== "DISABLED" ? n.textTruncation : undefined,
  };
}

// Rotation is embedded in the transform matrix.
function rotation(t) {
  if (!t) return undefined;
  const deg = (Math.atan2(t.m10 ?? 0, t.m00 ?? 1) * 180) / Math.PI;
  return Math.abs(deg) < 0.01 ? undefined : r2(deg);
}

// Drops empty fields so the JSON only carries what the node sets.
function clean(obj) {
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    if (v === undefined || v === null || (typeof v === "object" && !Array.isArray(v) && v !== null && Object.keys(v).length === 0)) delete obj[k];
  }
  return obj;
}

// `override` carries the fields the INSTANCE overrides when we're inside a component expansion.
export function normalize(node, { override = null, fromComponent = false, doc = null, withGeometry = false } = {}) {
  const n = override ? { ...node, ...override } : node;
  const size = n.size ?? n.derivedTextData?.layoutSize;
  const out = {
    id: nodeKey(node),
    type: n.type,
    name: n.name,
    x: r2(n.transform?.m02 ?? 0),
    y: r2(n.transform?.m12 ?? 0),
    w: r2(size?.x),
    h: r2(size?.y),
    rotation: rotation(n.transform),
    visible: n.visible === false ? false : undefined,
    opacity: n.opacity !== undefined && n.opacity < 1 ? r2(n.opacity) : undefined,
    blendMode: n.blendMode && n.blendMode !== "NORMAL" ? n.blendMode : undefined,
    clip: n.frameMaskDisabled === false ? true : undefined,
    mask: n.mask ? (n.maskType ?? true) : undefined,
    radius: corners(n),
    fills: paints(n.fillPaints),
    strokes: paints(n.strokePaints),
    strokeWeight: n.strokePaints?.length ? r2(n.strokeWeight) : undefined,
    strokeAlign: n.strokePaints?.length ? n.strokeAlign : undefined,
    dashPattern: n.dashPattern?.length ? n.dashPattern.map(r2) : undefined,
    effects: effects(n.effects),
    layout: autoLayout(n),
    layoutChild: layoutChild(n),
    constraints: constraints(n),
    text: n.textData?.characters,
    font: typography(n),
    scrollDirection: n.scrollDirection && n.scrollDirection !== "NONE" ? n.scrollDirection : undefined,
    fromComponent: fromComponent || undefined,
  };
  if (n.type === "INSTANCE" || n.type === "SYMBOL") out.component = n.name;
  if (withGeometry && doc) {
    // Full matrix, not just x/y: icons have rotated and mirrored nodes, and a round trip through the angle loses the mirroring.
    const t = n.transform;
    if (t) out.matrix = [t.m00 ?? 1, t.m10 ?? 0, t.m01 ?? 0, t.m11 ?? 1, t.m02 ?? 0, t.m12 ?? 0];
    const g = buildGeometry(doc, node, n);
    if (g) out.geometry = g;
  } else if (n.type === "VECTOR" || n.type === "BOOLEAN_OPERATION") {
    out.vectorPath = "unavailable"; // convertible with --svg
  }
  return clean(out);
}

// An INSTANCE has no children of its own in the .fig — its content lives in the SYMBOL, so it's
// expanded here, with the instance's overrides applied by guid path.
export function extractTree(doc, root, opts = {}) {
  const {
    includeHidden = false,
    expandInstances = true,
    maxDepth = 40,
    maxNodes = 20000,
    withGeometry = false,
  } = opts;
  const stats = { nodes: 0, expanded: 0, overridesApplied: 0, truncated: false, unresolvedComponents: [] };

  // Overrides are addressed by a PATH of `overrideKey`s (not the node id), each ancestor instance opens
  // its own scope, and the outermost scope wins: the instance on the screen decides the final text.
  const resolveOverride = (scopes, okey) => {
    let merged = null;
    for (let i = scopes.length - 1; i >= 0; i--) {
      const s = scopes[i];
      const path = okey ? [...s.path, okey] : s.path;
      const hit = s.index.get(path.join(">")) ?? (okey ? s.index.get(okey) : null);
      if (hit) merged = { ...(merged ?? {}), ...hit };
    }
    return merged;
  };

  const build = (node, depth, ctx) => {
    if (stats.nodes >= maxNodes) { stats.truncated = true; return null; }
    if (isRemoved(node)) return null;

    const okey = node.overrideKey ? guidKey(node.overrideKey) : null;
    const scopes = ctx.scopes.map((s) => ({ index: s.index, path: okey ? [...s.path, okey] : s.path }));
    const override = scopes.length ? resolveOverride(ctx.scopes, okey) : null;
    if (override) stats.overridesApplied++;

    const effectiveVisible = override?.visible ?? node.visible;
    if (!includeHidden && effectiveVisible === false) return null;

    const out = normalize(node, { override, fromComponent: ctx.inComponent, doc, withGeometry });
    stats.nodes++;

    if (depth >= maxDepth) { out.truncatedAt = "maxDepth"; return out; }

    let kids = childrenOf(doc, node);
    let childScopes = scopes;
    let inComponent = ctx.inComponent;

    if (node.type === "INSTANCE" && expandInstances) {
      const symbol = resolveSymbol(doc, node);
      if (!symbol) {
        out.componentSource = "external-library"; // library component not embedded in the .fig
        stats.unresolvedComponents.push(node.name);
      } else if (ctx.symbolStack.includes(nodeKey(symbol))) {
        out.componentSource = "recursive"; // instance inside its own component
      } else {
        kids = childrenOf(doc, symbol);
        // A resized instance keeps its content in the SYMBOL's space; without this scale the SVG
        // overflows its viewBox (a 24x24 icon inside a 16x16 instance).
        if (withGeometry && symbol.size && out.w && out.h) {
          const sx = out.w / symbol.size.x;
          const sy = out.h / symbol.size.y;
          if (Math.abs(sx - 1) > 0.001 || Math.abs(sy - 1) > 0.001) out.contentScale = [Math.round(sx * 1000) / 1000, Math.round(sy * 1000) / 1000];
        }
        // The instance opens its own override scope while staying inside the outer ones.
        childScopes = [...scopes, { index: buildOverrideIndex(node), path: [] }];
        inComponent = true;
        stats.expanded++;
        ctx = { ...ctx, symbolStack: [...ctx.symbolStack, nodeKey(symbol)] };
      }
    }

    const children = [];
    for (const k of kids) {
      const c = build(k, depth + 1, { inComponent, scopes: childScopes, symbolStack: ctx.symbolStack });
      if (c) children.push(c);
    }
    if (children.length) out.children = children;
    return out;
  };

  const tree = build(root, 0, { inComponent: false, scopes: [], symbolStack: [] });
  return { tree, stats };
}
