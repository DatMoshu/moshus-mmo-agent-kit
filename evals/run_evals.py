#!/usr/bin/env python3
"""Kit self-evals. Run from anywhere: python evals/run_evals.py

1. hallucinations: every sample in evals/hallucinations/samples must trigger exactly the expected rule ids
   (no misses, no extras), proving rules/hallucinations.json catches what it claims.
2. frontmatter: every agents/*.md and skills/stdb-*/SKILL.md has name + description, and the name matches the file.
3. links: every repo path mentioned in AGENTS.md, README.md, agents/ and skills/stdb-* exists.
4. scenarios: prints the agent-behaviour scenarios in evals/scenarios.md (graded by a human or an LLM judge).
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EV = ROOT / "evals"
failures: list[str] = []


def hallucinations() -> None:
    expected = json.loads((EV / "hallucinations" / "expected.json").read_text(encoding="utf-8-sig"))
    for rel, ids in expected.items():
        f = EV / "hallucinations" / rel
        out = subprocess.run([sys.executable, str(ROOT / "tools" / "kit.py"), "check", str(f)],
                             capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
        got = set(re.findall(r":\d+: \[([a-z0-9-]+)\] ", out))
        miss, extra = set(ids) - got, got - set(ids)
        status = "ok" if not miss and not extra else "FAIL"
        print(f"  {status:4} {rel}: {len(got)} rule(s)" + (f" missing={sorted(miss)}" if miss else "") + (f" extra={sorted(extra)}" if extra else ""))
        if status != "ok":
            failures.append(f"hallucinations:{rel}")


def frontmatter() -> None:
    files = [p for p in (ROOT / "agents").glob("*.md") if p.name.lower() != "readme.md"]
    files += list((ROOT / "skills").glob("stdb-*/SKILL.md"))
    for f in files:
        m = re.match(r"---\n(.*?)\n---\n", f.read_text(encoding="utf-8-sig").replace("\r\n", "\n"), re.S)
        meta = dict(re.findall(r"^(\w+):\s*(.+)$", m.group(1), re.M)) if m else {}
        want = f.parent.name if f.name == "SKILL.md" else f.stem
        if meta.get("name") != want or not meta.get("description"):
            failures.append(f"frontmatter:{f.relative_to(ROOT)}")
            print(f"  FAIL frontmatter {f.relative_to(ROOT)}")
    print(f"  ok   frontmatter: {len(files)} files checked")


# Paths that a *generated game project* creates; the kit itself does not ship them.
PROJECT_ONLY = ("docs/north-star.md", "docs/milestones.md", "docs/systems/", "docs/migrations/",
                "docs/security-review-", "kb/stdb-kb.sqlite", "tools/loadtest/bots/reports/")


def links() -> None:
    texts = [ROOT / "AGENTS.md", ROOT / "README.md", *ROOT.glob("agents/*.md"), *ROOT.glob("skills/stdb-*/SKILL.md"),
             *ROOT.glob("docs/**/*.md"), *ROOT.glob("rules/*.md"), *ROOT.glob("recipes/*.md")]
    missing = set()
    for t in texts:
        for p in re.findall(r"(?<![\w/.-])((?:rules|docs|recipes|evals|kb|templates|tools|skills|agents)/[A-Za-z0-9_./-]+)", t.read_text(encoding="utf-8-sig")):
            p = p.rstrip(".,):`")
            if "<" in p or p.startswith(PROJECT_ONLY) or "*" in p:
                continue
            if not (ROOT / p).exists():
                missing.add(f"{p}  (in {t.relative_to(ROOT)})")
    for m in sorted(missing):
        print(f"  FAIL link {m}")
    if missing:
        failures.append("links")
    else:
        print(f"  ok   links: {len(texts)} files checked")


def main() -> int:
    print("[evals] hallucination rules"); hallucinations()
    print("[evals] frontmatter"); frontmatter()
    print("[evals] links"); links()
    sc = EV / "scenarios.md"
    if sc.exists():
        n = len(re.findall(r"^## ", sc.read_text(encoding="utf-8-sig"), re.M))
        print(f"[evals] {n} agent scenarios in evals/scenarios.md (grade manually or with an LLM judge)")
    print(f"[evals] {'PASS' if not failures else 'FAIL: ' + ', '.join(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
