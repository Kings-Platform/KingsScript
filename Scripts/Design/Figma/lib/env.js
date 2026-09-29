// Paths and runtime checks shared by both entry points. Only node: imports, so it loads before npm install.
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const TOOL_DIR = dirname(dirname(fileURLToPath(import.meta.url)));
export const FIG_DIR = process.env.KINGS_FIG_DIR || join(homedir(), "Documents", "FigExtracts");
export const FIGMAS_DIR = join(FIG_DIR, "figmas");
// Fixtures live next to the data, not in the repo, so private designs never get committed.
export const FIXTURES_DIR = join(FIG_DIR, "fixtures");

// A static import of openfig-core would crash at link time with ERR_MODULE_NOT_FOUND before any message.
export function requireDependencies() {
  if (existsSync(join(TOOL_DIR, "node_modules", "openfig-core"))) return;
  console.error(`ERROR: Dependencies missing — run: npm install --prefix ${TOOL_DIR}`);
  process.exit(1);
}
