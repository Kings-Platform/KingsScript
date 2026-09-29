#!/usr/bin/env python3
# `kings docs-check [--root DIR] [--skip PREFIX]... [--no-global] [-v]`: deterministic hygiene check of a
# markdown docs tree. Reports, never fixes — what a broken link meant to point at is a human call.

import os
import re
import sys
import unicodedata

USAGE = """Usage: kings docs-check [--root DIR] [--skip PREFIX]... [--no-global] [-v]
  Checks, without fixing anything:
    1. relative link to a .md that doesn't resolve
    2. #anchor that doesn't exist in the target page
    3. page not reachable, following links, from the README.md responsible for it
       (the closest one up the tree)
    4. docs/ page cited by a skill (.claude/skills/*/SKILL.md) that doesn't exist

  --root DIR        folder to check; default: $KINGS_DOCS_ROOT, else the current folder.
                    Pages live in <root>/docs, or in <root> itself when there's no docs/
  --skip PREFIX     link prefix that isn't validated (e.g. a path into another repo); repeatable
  --no-global       skip the machine-wide Claude files (~/.claude/CLAUDE.md, ~/.claude/agents/),
                    which are checked by default since they cite the docs too
  -v, --verbose     also lists every file checked

  One line per problem. Exit 1 on problems, 0 when there are only warnings."""

SKIP_PREFIXES = ("http://", "https://", "mailto:")

# Append-only folders: the index links the folder, not each file in it.
EXEMPT_DIRS = {"ai-sessions"}
IGNORED_DIRS = {"node_modules"}

LINK_RE = re.compile(r"\]\(([^)\s]+?\.md)(#[^)]*)?\)")
BARE_ANCHOR_RE = re.compile(r"\]\((#[^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$", re.M)
SKILL_REF_RE = re.compile(r"`?(docs/[A-Za-z0-9_./-]+\.md)`?")

# Only real emoji ranges count: a backtick (Sk), `|`/`>` (Sm) or a combining accent (Mn) is a
# symbol/mark to Unicode, but doesn't make an anchor ambiguous.
EMOJI_RANGES = (
    (0x2300, 0x23FF),    # Miscellaneous Technical
    (0x2600, 0x27BF),    # Misc Symbols + Dingbats
    (0x2B00, 0x2BFF),    # Arrows/symbols
    (0x1F000, 0x1FAFF),  # Emoji & pictographs
    (0xFE0F, 0xFE0F),    # variation selector
    (0x200D, 0x200D),    # zero-width joiner
)


# ---------------------------------------------------------------------------------- input

# Flag first, then the environment, then the current folder.
def parse_args(args):
    opts = {"root": os.environ.get("KINGS_DOCS_ROOT") or os.getcwd(), "skip": [], "verbose": False,
            "global": True}
    while args:
        a = args.pop(0)
        if a == "--root" and args:
            opts["root"] = args.pop(0)
        elif a == "--skip" and args:
            opts["skip"].append(args.pop(0))
        elif a == "--no-global":
            opts["global"] = False
        elif a in ("-v", "--verbose"):
            opts["verbose"] = True
        elif a in ("-h", "--help"):
            print(USAGE)
            sys.exit(0)
        else:
            print(f"docs-check: unknown argument: {a}\n\n{USAGE}", file=sys.stderr)
            sys.exit(1)
    opts["root"] = os.path.abspath(os.path.expanduser(opts["root"]))
    return opts


def docs_dir(root):
    docs = os.path.join(root, "docs")
    return docs if os.path.isdir(docs) else root


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return None


# Hidden folders and dependencies are never docs; .claude is collected on its own.
def walk(base, exempt=frozenset()):
    for dirpath, dirnames, names in os.walk(base):
        dirnames[:] = [d for d in dirnames
                       if not d.startswith(".") and d not in IGNORED_DIRS and d not in exempt]
        yield dirpath, dirnames, names


# Machine-wide Claude files: they point at the docs as much as the project's own ones do.
def global_md_files():
    claude = os.path.expanduser("~/.claude")
    out = [os.path.join(d, n) for d, _, names in os.walk(os.path.join(claude, "agents"))
           for n in names if n.endswith(".md")]
    if os.path.isfile(os.path.join(claude, "CLAUDE.md")):
        out.append(os.path.join(claude, "CLAUDE.md"))
    return out


# Every relevant .md: the docs tree, the project's CLAUDE.md, skills and agents.
def md_files(root, include_global):
    out = [os.path.join(d, n) for d, _, names in walk(docs_dir(root)) for n in names
           if n.endswith(".md")]
    for dirpath, _, names in os.walk(os.path.join(root, ".claude")):
        out += [os.path.join(dirpath, n) for n in names if n.endswith(".md")]
    claude_md = os.path.join(root, "CLAUDE.md")
    if os.path.isfile(claude_md):
        out.append(claude_md)
    if include_global:
        out += global_md_files()
    return sorted(set(out))


def shown(path, root):
    if path.startswith(root + os.sep):
        return os.path.relpath(path, root)
    return path.replace(os.path.expanduser("~"), "~")


# -------------------------------------------------------------------------------- anchors

# GitHub's anchor algorithm. The step naive versions get wrong: EACH space becomes a hyphen,
# without collapsing, so `## A — B` becomes `a--b` once the em dash is dropped.
def github_slug(heading):
    s = unicodedata.normalize("NFC", heading.strip().lower()).replace("`", "")
    s = "".join(c for c in s if not unicodedata.category(c).startswith(("S", "M")))
    s = re.sub(r"[^\w\s-]", "", s, flags=re.UNICODE)
    return s.replace(" ", "-").strip("-")


# Renderers disagree on emoji in slugs (GitHub drops them, some editors keep them), so an
# anchor to such a heading is only a warning.
def heading_has_emoji(heading):
    return any(a <= ord(c) <= b for c in heading for a, b in EMOJI_RANGES)


# Returns (every slug, slugs of headings that had an emoji).
def headings_of(path, cache):
    if path not in cache:
        all_slugs, emoji_slugs = set(), set()
        for m in HEADING_RE.finditer(read(path) or ""):
            slug = github_slug(m.group(2))
            all_slugs.add(slug)
            if heading_has_emoji(m.group(2)):
                emoji_slugs.add(slug)
        cache[path] = (all_slugs, emoji_slugs)
    return cache[path]


# Loose form for emoji headings: a link that kept U+FE0F still matches the slug that lost it.
def loose(slug):
    return re.sub("[-️‍]", "", slug)


# ---------------------------------------------------------------------------------- checks

def check_anchor(ctx, src, target_path, anchor, label):
    slugs, emoji_slugs = headings_of(target_path, ctx["headings"])
    if anchor in slugs:
        return
    if loose(anchor) in {loose(s) for s in emoji_slugs}:
        ctx["warnings"].append(f"EMOJI     {shown(src, ctx['root'])} → {label}"
                               " (anchor to a heading with emoji — ambiguous slug,"
                               " prefer the parent section)")
    else:
        ctx["problems"].append(f"ANCHOR    {shown(src, ctx['root'])} → {label}")


# Checks 1 and 2: relative link and anchor.
def check_links(ctx, files):
    for f in files:
        text = read(f)
        if text is None:
            continue
        folder = os.path.dirname(f)
        for m in LINK_RE.finditer(text):
            target, anchor = m.group(1), (m.group(2) or "")[1:]
            if target.startswith(ctx["skip"]):
                continue
            resolved = os.path.normpath(os.path.join(folder, target))
            if not os.path.isfile(resolved):
                ctx["problems"].append(f"BROKEN    {shown(f, ctx['root'])} → {target}")
            elif anchor:
                check_anchor(ctx, f, resolved, anchor, f"{target}#{anchor}")
        for m in BARE_ANCHOR_RE.finditer(text):
            anchor = m.group(1)[1:]
            check_anchor(ctx, f, f, anchor, f"#{anchor} (this page)")


# Every .md reachable from `start` following links, transitively: a README linking a page that
# links its sub-pages indexes all of them.
def reachable_from(ctx, start):
    seen, queue = {start}, [start]
    while queue:
        f = queue.pop()
        if f not in ctx["links"]:
            folder = os.path.dirname(f)
            targets = set()
            for m in LINK_RE.finditer(read(f) or ""):
                if m.group(1).startswith(ctx["skip"]):
                    continue
                resolved = os.path.normpath(os.path.join(folder, m.group(1)))
                if os.path.isfile(resolved):
                    targets.add(resolved)
            ctx["links"][f] = targets
        for t in ctx["links"][f] - seen:
            seen.add(t)
            queue.append(t)
    return seen


# Check 3: the responsible index is the closest README.md up the tree, so a subfolder with its
# own README prunes that subtree from the index above. Naming the file in the README body
# (without a link) still counts.
def check_index(ctx):
    readme_dirs = [d for d, _, names in walk(docs_dir(ctx["root"]), EXEMPT_DIRS)
                   if "README.md" in names]
    for rdir in readme_dirs:
        readme = os.path.join(rdir, "README.md")
        body = read(readme)
        if body is None:
            continue
        reachable = reachable_from(ctx, readme)
        for dirpath, dirnames, names in walk(rdir, EXEMPT_DIRS):
            dirnames[:] = [d for d in dirnames
                           if not os.path.isfile(os.path.join(dirpath, d, "README.md"))]
            for n in sorted(names):
                full = os.path.join(dirpath, n)
                if n.endswith(".md") and n != "README.md" and full not in reachable and n not in body:
                    ctx["problems"].append(f"ORPHAN    {os.path.relpath(full, rdir)}"
                                           f" (not reachable from {shown(readme, ctx['root'])})")


# Check 4: a skill citing `docs/.../Page.md` in prose, which the link check doesn't see.
def check_skills(ctx):
    root = ctx["root"]
    for dirpath, _, names in os.walk(os.path.join(root, ".claude", "skills")):
        if "SKILL.md" not in names:
            continue
        f = os.path.join(dirpath, "SKILL.md")
        for m in SKILL_REF_RE.finditer(read(f) or ""):
            if not os.path.isfile(os.path.join(root, m.group(1))):
                ctx["problems"].append(f"SKILL     {shown(f, root)} cites {m.group(1)}"
                                       " (doesn't exist)")


# ---------------------------------------------------------------------------------- report

def print_report(ctx, files, verbose):
    skills = len([f for f in files if f.endswith("SKILL.md")])
    print(f"docs-check: {len(files)} files, {skills} skill(s)  [{ctx['root']}]")
    if verbose:
        for f in files:
            print(f"  · {shown(f, ctx['root'])}")
    for lines in (ctx["problems"], ctx["warnings"]):
        if lines:
            print()
            print("\n".join(sorted(set(lines))))

    n, nw = len(set(ctx["problems"])), len(set(ctx["warnings"]))
    print()
    if not n and not nw:
        print("no problems")
        return
    parts = []
    if n:
        parts.append(f"{n} problem{'s' if n > 1 else ''}")
    if nw:
        parts.append(f"{nw} warning{'s' if nw > 1 else ''}")
    print(" · ".join(parts))


def main():
    opts = parse_args(sys.argv[1:])
    if not os.path.isdir(opts["root"]):
        print(f"docs-check: {opts['root']} is not a folder", file=sys.stderr)
        sys.exit(1)
    ctx = {"root": opts["root"], "skip": SKIP_PREFIXES + tuple(opts["skip"]),
           "problems": [], "warnings": [], "headings": {}, "links": {}}

    files = md_files(ctx["root"], opts["global"])
    check_links(ctx, files)
    check_index(ctx)
    check_skills(ctx)
    print_report(ctx, files, opts["verbose"])
    sys.exit(1 if ctx["problems"] else 0)


if __name__ == "__main__":
    main()
