// Low-level navigation over the document returned by openfig-core — no design interpretation here.
import * as of from "openfig-core";

export const nodeKey = (node) => of.nodeId(node);
export const guidKey = (guid) => `${guid.sessionID}:${guid.localID}`;

// childrenMap may hold either ids or node objects, so every child is resolved to a node.
export function childrenOf(doc, node) {
  const raw = doc.childrenMap.get(nodeKey(node)) ?? [];
  return raw.map((c) => (typeof c === "string" ? doc.nodeMap.get(c) : c)).filter(Boolean);
}

// Null when the component comes from an external library that isn't embedded in the .fig.
export function resolveSymbol(doc, instance) {
  const symbolID = instance.symbolData?.symbolID;
  if (!symbolID) return null;
  return doc.nodeMap.get(guidKey(symbolID)) ?? null;
}

// Indexed twice on purpose (full guid path and last guid): real files carry paths pointing at
// library sessions that don't match the local subtree, and the last-guid fallback recovers them.
export function buildOverrideIndex(instance) {
  const index = new Map();
  const add = (entry, list) => {
    const guids = entry.guidPath?.guids;
    if (!guids?.length) return;
    const full = guids.map(guidKey).join(">");
    const last = guidKey(guids[guids.length - 1]);
    for (const key of [full, last]) {
      const bucket = index.get(key) ?? {};
      index.set(key, { ...bucket, ...list(entry) });
    }
  };
  for (const o of instance.symbolData?.symbolOverrides ?? []) add(o, ({ guidPath, ...rest }) => rest);
  for (const d of instance.derivedSymbolData ?? []) add(d, ({ guidPath, ...rest }) => rest);
  return index;
}

// Pages are the CANVAS nodes, in file order.
export const pagesOf = (doc) => doc.nodes.filter((n) => n.type === "CANVAS");

// The parser already returns the current state, but a .fig can still carry history.
export const isRemoved = (node) => node.phase === "REMOVED";
