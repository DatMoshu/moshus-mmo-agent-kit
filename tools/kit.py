#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""kit.py - one entry point for Moshu's MMO Agent Kit.

Stdlib only (Python 3.11+). Reads versions from stdb.lock. Every command prints what it runs.

  python tools/kit.py doctor                 check toolchains against stdb.lock
  python tools/kit.py server [--isolated]    run a local SpacetimeDB (spacetime start)
  python tools/kit.py publish [--wipe]       build + publish the dev module
  python tools/kit.py bindings [--check]     regenerate TS + Godot client bindings
  python tools/kit.py smoke [--godot]        two clients join and move; PASS/FAIL
  python tools/kit.py loadtest --bots 100    swarm + budgets.json gate; PASS/CONCERNS/FAIL
  python tools/kit.py check [PATH...]        hallucinated-API / anti-pattern scan
  python tools/kit.py new NAME --dest DIR    scaffold a new game from the templates
  python tools/kit.py vendor-skills          refresh skills/vendor/official from upstream
  python tools/kit.py kb-export              rebuild kb/stdb-kb.sqlite from kb/*.json
  python tools/kit.py install-claude         copy agents/skills into .claude/ for Claude Code

Environment:
  SPACETIME       path to the spacetime CLI (default: `spacetime` on PATH)
  SPACETIME_ARGS  extra global CLI args, e.g. "--root-dir .kit/root --config-path .kit/cli.toml"
  GODOT           path to a Godot 4.7.x binary (console build on Windows)
  KIT_WASM        prebuilt module .wasm to publish/generate from instead of building
  KIT_RETRIES     retries for transient failures (default 2; 0 disables)
  KIT_RETRY_BASE  first backoff delay in seconds (default 2; doubles each retry, with jitter)

Runners are safe to re-run (see docs/processes/ops-runners.md): they retry only transient failures
(connection refused/reset, timeouts, HTTP 429/502/503/504), never a real FAIL verdict, and read JSON
with utf-8-sig so a UTF-8 BOM written by another tool does not break parsing.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import sys
import tomllib
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = tomllib.loads((ROOT / "stdb.lock").read_text(encoding="utf-8-sig"))
BOTS = ROOT / "tools" / "loadtest" / "bots"
GODOT_TEMPLATE = ROOT / LOCK["dev"].get("godot_client", "templates/client/godot")
WEB_ADMIN = ROOT / LOCK["dev"].get("web_admin", "templates/client/web-admin")
SIDECAR = ROOT / LOCK["dev"].get("sidecar", "templates/sidecar")
IS_WIN = os.name == "nt"
RETRIES = max(0, int(os.environ.get("KIT_RETRIES", "2")))
RETRY_BASE = max(0.0, float(os.environ.get("KIT_RETRY_BASE", "2")))
TRANSIENT = re.compile(r"connection (?:refused|reset|aborted|closed)|timed? ?out|temporarily unavailable|broken pipe|"
                       r"ECONNREFUSED|ECONNRESET|ETIMEDOUT|EAI_AGAIN|error sending request|"
                       r"\b(?:429|502|503|504)\b", re.I)


def say(msg: str) -> None:
    print(f"[kit] {msg}", flush=True)


def run(cmd: list[str], cwd: Path | None = None, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    say("$ " + " ".join(shlex.quote(str(c)) for c in cmd) + (f"   (in {cwd})" if cwd else ""))
    return subprocess.run([str(c) for c in cmd], cwd=cwd, check=check, text=True, encoding="utf-8",
                          errors="replace", capture_output=capture, shell=False)


class Transient(Exception):
    """A failure worth retrying: the same step may succeed if run again unchanged."""


def read_json(path: Path):
    """JSON from a file, tolerating a UTF-8 BOM (PowerShell 5 `Out-File`/`Set-Content -Encoding utf8` add one)."""
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def retry(what: str, fn, attempts: int | None = None):
    """Run fn(); on a transient failure wait base * 2^n (with jitter) and run it again.

    fn must be idempotent. Non-transient errors and real verdicts are returned or raised at once."""
    tries = (RETRIES if attempts is None else attempts) + 1
    for i in range(1, tries + 1):
        try:
            return fn()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 502, 503, 504) or i == tries:
                raise
            err: Exception = e
        except (Transient, urllib.error.URLError, ConnectionError, TimeoutError) as e:
            if i == tries:
                raise
            err = e
        delay = RETRY_BASE * (2 ** (i - 1)) * (0.5 + random.random() / 2)
        say(f"{what}: transient failure ({err}); retry {i}/{tries - 1} in {delay:.1f}s")
        time.sleep(delay)
    raise AssertionError("unreachable")


def http_get(url: str, timeout: float = 30) -> str:
    def once() -> str:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.read().decode("utf-8-sig")
    return retry(f"GET {url}", once)


def wait_for_server(url: str) -> bool:
    """Ping the server (GET /v1/ping) with retries; say why if it never answers."""
    try:
        http_get(f"{url}/v1/ping", timeout=5)
        return True
    except Exception as e:  # noqa: BLE001
        say(f"server {url} did not answer /v1/ping ({e}). Start it with `python tools/kit.py server`.")
        return False


def which(name: str) -> str | None:
    found = shutil.which(name)
    if not found and IS_WIN:
        found = shutil.which(name + ".cmd") or shutil.which(name + ".exe")
    if not found and name in ("cargo", "rustup"):
        cand = Path.home() / ".cargo" / "bin" / (name + (".exe" if IS_WIN else ""))
        found = str(cand) if cand.exists() else None
    return found


def module_source(module: Path) -> list[str]:
    """--module-path normally; --bin-path when KIT_WASM points at a prebuilt module
    (e.g. on a machine that can run SpacetimeDB but cannot build Rust)."""
    wasm = os.environ.get("KIT_WASM")
    return ["--bin-path", wasm] if wasm else ["--module-path", str(module)]


def spacetime() -> list[str]:
    exe = os.environ.get("SPACETIME") or which("spacetime")
    if not exe:
        sys.exit("spacetime CLI not found. Install SpacetimeDB "
                 f"{LOCK['spacetimedb']['version']} (see README) or set SPACETIME=/path/to/spacetime")
    return [exe, *shlex.split(os.environ.get("SPACETIME_ARGS", ""), posix=not IS_WIN)]


def npm() -> str:
    exe = which("npm")
    if not exe:
        sys.exit(f"npm not found. Install Node {LOCK['toolchain']['node']}.")
    return exe


def godot() -> str | None:
    return os.environ.get("GODOT") or which("godot") or which("godot4")


def dev(args, key: str) -> str:
    return getattr(args, key, None) or LOCK["dev"][{"url": "url", "db": "database", "module": "module"}[key]]


def ws_url(http_url: str) -> str:
    return re.sub(r"^http", "ws", http_url)


# ----------------------------------------------------------------------------------------------
def cmd_doctor(args) -> int:
    want = LOCK["spacetimedb"]["version"]
    problems = 0

    def report(name: str, ok: bool, detail: str) -> None:
        nonlocal problems
        problems += 0 if ok else 1
        print(f"  {'OK  ' if ok else 'FAIL'} {name:<10} {detail}")

    print(f"stdb.lock wants spacetimedb {want}, rust {LOCK['toolchain']['rust']}, node {LOCK['toolchain']['node']}, godot {LOCK['toolchain']['godot']}")
    try:
        out = subprocess.run([*spacetime(), "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
        m = re.search(r"tool version (\d+\.\d+\.\d+)", out) or re.search(r"(\d+\.\d+\.\d+)", out)
        report("spacetime", bool(m) and m.group(1) == want, (m.group(1) if m else out.strip()) +
               ("" if m and m.group(1) == want else f"  -> need {want}: `spacetime version install {want}` then `spacetime version use {want}`, or set SPACETIME"))
    except SystemExit as e:
        report("spacetime", False, str(e))
    cargo = which("cargo")
    if cargo:
        rv = subprocess.run([cargo, f"+{LOCK['toolchain']['rust']}", "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        report("rust", rv.returncode == 0, rv.stdout.strip() or f"toolchain {LOCK['toolchain']['rust']} missing -> `rustup toolchain install {LOCK['toolchain']['rust']} --target wasm32-unknown-unknown`")
        rustup = which("rustup")
        if rustup:
            tl = subprocess.run([rustup, "target", "list", "--installed", "--toolchain", LOCK["toolchain"]["rust"]], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
            report("wasm32", "wasm32-unknown-unknown" in tl, "installed" if "wasm32-unknown-unknown" in tl else f"`rustup target add wasm32-unknown-unknown --toolchain {LOCK['toolchain']['rust']}`")
        if IS_WIN:
            # Build scripts and proc-macros compile for the host, which on *-msvc needs link.exe.
            has_link = bool(shutil.which("link.exe")) or bool(_vs_installs())
            report("msvc", has_link, "C++ build tools found" if has_link else
                   "link.exe not found: install 'Build Tools for Visual Studio' with the C++ workload, "
                   "or build on Linux/WSL and set KIT_WASM=path/to/module.wasm")
    else:
        report("rust", False, "cargo not found -> https://rustup.rs")
    node = which("node")
    if node:
        v = subprocess.run([node, "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()
        major = int(re.sub(r"\D", "", v.split(".")[0]) or 0)
        report("node", major >= 22, v)
    else:
        report("node", False, "not found (needed for smoke/loadtest/web admin)")
    g = godot()
    if g:
        v = subprocess.run([g, "--version", "--headless"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip().splitlines()
        ver = v[-1] if v else "?"
        report("godot", ver.startswith(LOCK["toolchain"]["godot"]), ver + " (optional)")
    else:
        print("  SKIP godot      not found; set GODOT=... to enable the Godot client + `smoke --godot` (optional)")
    report("python", sys.version_info >= (3, 11), sys.version.split()[0])
    print("doctor:", "all good" if problems == 0 else f"{problems} problem(s)")
    return 0 if problems == 0 else 1


def _vs_installs() -> list[str]:
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if not vswhere.exists():
        return []
    out = subprocess.run([str(vswhere), "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                          "-property", "installationPath"], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    return [l for l in out.splitlines() if l.strip()]


def cmd_server(args) -> int:
    cmd = spacetime()
    if args.isolated and "--root-dir" in cmd:
        say("SPACETIME_ARGS already sets --root-dir; using it instead of the --isolated .kit paths")
    elif args.isolated:
        kitdir = ROOT / ".kit"
        kitdir.mkdir(exist_ok=True)
        cmd += ["--root-dir", str(kitdir / "root"), "--config-path", str(kitdir / "cli.toml")]
    listen = re.sub(r"^https?://", "", dev(args, "url"))
    cmd += ["start", "--listen-addr", listen]
    if args.isolated:
        cmd += ["--data-dir", str(ROOT / ".kit" / "data")]
    say("Ctrl+C to stop. Leave this running in its own terminal.")
    return run(cmd, check=False).returncode


def cmd_publish(args) -> int:
    module = ROOT / dev(args, "module") if not Path(dev(args, "module")).is_absolute() else Path(dev(args, "module"))
    cmd = [*spacetime(), "publish", dev(args, "db"), "--server", dev(args, "url"), *module_source(module), "--yes"]
    if args.wipe:
        cmd.append("--delete-data")

    def once() -> int:
        res = run(cmd, check=False, capture=True)
        out = (res.stdout or "") + (res.stderr or "")
        print(out, end="" if out.endswith("\n") else "\n")
        if res.returncode != 0 and TRANSIENT.search(out):
            raise Transient(f"exit {res.returncode}")
        return res.returncode
    # Re-publishing the same module is idempotent, so a connection blip is safe to retry.
    try:
        return retry("publish", once)
    except Transient:
        return 1


def fetch_schema(url: str, db: str) -> str:
    return http_get(f"{url}/v1/database/{db}/schema?version=10", timeout=20)


def _order_insensitive(text: str) -> list[str]:
    """Lines sorted, and the items of any [..] list literal sorted, so pure reordering compares equal."""
    def sort_list(m: re.Match) -> str:
        return "[" + ", ".join(sorted(x.strip() for x in m.group(1).split(","))) + "]"
    return sorted(re.sub(r"\[([^\[\]]*)\]", sort_list, line) for line in text.splitlines())


def ensure_godot_import(g: str) -> None:
    """Run `godot --headless --import` once if the project was never imported.

    A fresh clone has no .godot/global_script_class_cache.cfg, so scripts run with -s (tools/codegen.gd) cannot
    resolve the SDK's class_names (SpacetimePlugin, SpacetimeCodegen, ...) and fail to parse. Raises if the
    import does not produce the cache, so the failure names the cause instead of a GDScript parse error."""
    cache = GODOT_TEMPLATE / ".godot" / "global_script_class_cache.cfg"
    if cache.exists():
        return
    say("Godot project not imported yet; running godot --headless --import once")
    run([g, "--headless", "--path", str(GODOT_TEMPLATE), "--import"], check=False, capture=True)
    if not cache.exists():
        raise SystemExit(f"godot --import did not create {cache}; run it by hand: {g} --headless --path {GODOT_TEMPLATE} --import")


def cmd_bindings(args) -> int:
    module = ROOT / dev(args, "module")
    rc = 0
    # TypeScript (bots, web admin, sidecar) straight from the module source.
    for out in [BOTS / "src" / "module_bindings", WEB_ADMIN / "src" / "module_bindings", SIDECAR / "src" / "module_bindings"]:
        if (out.parent.parent / "package.json").exists():
            rc |= run([*spacetime(), "generate", "--lang", "typescript", "--out-dir", str(out),
                       *module_source(module), "--yes"], check=False).returncode
    # Godot (flametime SDK) from the published schema; needs a running server with the module.
    if not (GODOT_TEMPLATE / "project.godot").exists():
        return rc  # no Godot client in this project
    g = godot()
    if not g:
        say("GODOT not set: skipped Godot bindings (the template ships bindings for templates/server/rust-single)")
        return rc
    try:
        schema = fetch_schema(dev(args, "url"), dev(args, "db"))
    except Exception as e:  # noqa: BLE001
        say(f"could not fetch schema from {dev(args, 'url')} ({e}); publish first")
        return 1
    tmp = ROOT / ".kit"
    tmp.mkdir(exist_ok=True)
    (tmp / "schema.json").write_text(schema, encoding="utf-8")
    ensure_godot_import(g)  # codegen.gd uses the SDK's class_names, which only resolve after an import
    rc |= run([g, "--headless", "--path", str(GODOT_TEMPLATE), "-s", "res://tools/codegen.gd", "--",
               "--schema", str(tmp / "schema.json")], check=False).returncode
    run([g, "--headless", "--path", str(GODOT_TEMPLATE), "--import"], check=False, capture=True)
    if args.check:
        st = run(["git", "status", "--porcelain", "--", str(GODOT_TEMPLATE / "spacetime_bindings")], cwd=ROOT, capture=True, check=False)
        drift = []
        names = run(["git", "diff", "--name-only", "--", str(GODOT_TEMPLATE / "spacetime_bindings")], cwd=ROOT, capture=True, check=False).stdout
        names += run(["git", "ls-files", "--others", "--exclude-standard", "--full-name", "--", str(GODOT_TEMPLATE / "spacetime_bindings")],
                     cwd=ROOT, capture=True, check=False).stdout
        for line in names.splitlines():
            rel = line.strip()
            if not rel:
                continue
            # The GDScript codegen does not emit tables in a stable order across servers;
            # a file whose lines are only reordered is not drift.
            old_txt = run(["git", "show", f"HEAD:{rel}"], cwd=ROOT, capture=True, check=False).stdout or ""
            new_path = ROOT / rel
            new_txt = new_path.read_text(encoding="utf-8", errors="replace") if new_path.is_file() else ""
            if _order_insensitive(old_txt) != _order_insensitive(new_txt):
                drift.append(line)
        if drift:
            say("bindings drift: regenerated Godot bindings differ from the committed ones:\n" + "\n".join(drift))
            return 1
        if st.stdout.strip():
            say("Godot bindings differ only in line order (codegen ordering); no drift")
    return rc


def ensure_bots() -> None:
    if not (BOTS / "node_modules").exists():
        run([npm(), "install", "--no-audit", "--no-fund"], cwd=BOTS)
    if not (BOTS / "src" / "module_bindings" / "index.ts").exists():
        run([*spacetime(), "generate", "--lang", "typescript", "--out-dir", str(BOTS / "src" / "module_bindings"),
             *module_source(ROOT / LOCK["dev"]["module"]), "--yes"])


def bots(args_list: list[str], capture: bool = True) -> subprocess.CompletedProcess:
    npx = which("npx") or sys.exit("npx not found")
    return run([npx, "tsx", "src/main.ts", *args_list], cwd=BOTS, check=False, capture=capture)


def last_json(text: str) -> dict | None:
    for line in reversed(text.strip().splitlines()):
        line = line.strip().lstrip("\ufeff")
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return None


def bots_verdict(what: str, args_list: list[str]) -> tuple[dict | None, subprocess.CompletedProcess]:
    """Run the bot harness; retry only when it produced no verdict (crash, refused connection).

    A FAIL verdict is a real result and is never retried. Each run uses fresh identities, so re-runs are safe."""
    last: list = [None]

    def once():
        res = bots(args_list)
        last[0] = res
        verdict = last_json(res.stdout or "")
        if verdict is None:
            raise Transient("no verdict from the bot harness")
        return verdict, res
    try:
        return retry(what, once)
    except Transient:
        return None, last[0]


def cmd_smoke(args) -> int:
    ensure_bots()
    url, db = dev(args, "url"), dev(args, "db")
    if not wait_for_server(url):
        print("SMOKE FAIL (server unreachable)")
        return 1
    verdict, res = bots_verdict("smoke", ["--mode", "smoke", "--uri", ws_url(url), "--db", db])
    print(json.dumps(verdict, indent=2) if verdict else ((res.stdout or "") + (res.stderr or "")))
    ok = bool(verdict) and verdict.get("verdict") == "PASS"
    if args.godot:
        ok = godot_smoke(url, db) and ok
    print("SMOKE", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def godot_smoke(url: str, db: str) -> bool:
    g = godot()
    if not g:
        say("GODOT not set; cannot run the Godot smoke")
        return False
    ensure_godot_import(g)
    base = [g, "--headless", "--path", str(GODOT_TEMPLATE), "--", "--autopilot", "--url", url, "--db", db, "--seconds", "8"]
    say("starting two headless Godot clients")
    # Log to files, not pipes: the SDK is chatty and a full pipe (4 KB on Windows) would stall
    # the second client until the first one exits, so they would never be online together.
    logdir = Path(tempfile.mkdtemp(prefix="kit-godot-"))
    procs = []
    for name, d in (("A", "1,0"), ("B", "0,1")):
        log = open(logdir / f"{name}.log", "w", encoding="utf-8")
        procs.append((name, subprocess.Popen(base + ["--dir", d], stdout=log, stderr=subprocess.STDOUT), log))
    ok = True
    for name, p, log in procs:
        try:
            p.wait(timeout=90)
        except subprocess.TimeoutExpired:
            p.kill()
            ok = False
        log.close()
        out = (logdir / f"{name}.log").read_text(encoding="utf-8", errors="replace")
        line = next((l for l in out.splitlines() if l.startswith("AUTOPILOT")), "AUTOPILOT FAIL (no verdict)\n" + out[-2000:])
        print(f"  godot {name}: {line}")
        ok = ok and p.returncode == 0 and "PASS" in line
    shutil.rmtree(logdir, ignore_errors=True)
    return ok


def cmd_loadtest(args) -> int:
    ensure_bots()
    budgets = read_json(ROOT / "tools" / "loadtest" / "budgets.json")
    if not wait_for_server(dev(args, "url")):
        print("LOADTEST FAIL (server unreachable)")
        return 1
    report, res = bots_verdict("loadtest", ["--mode", "swarm", "--uri", ws_url(dev(args, "url")), "--db", dev(args, "db"),
                                            "--bots", str(args.bots), "--duration", str(args.duration)])
    if not report:
        print(res.stdout or "", res.stderr or "")
        print("LOADTEST FAIL (no report)")
        return 1
    secs = max(1, report.get("duration_seconds", args.duration))
    report["updates_per_bot_per_sec"] = round(report.get("row_updates_received", 0) / max(1, report.get("bots_ready", 1)) / secs, 1)
    verdict, notes = "PASS", []
    for key, rule in budgets["metrics"].items():
        val = report
        for part in key.split("."):
            val = val.get(part) if isinstance(val, dict) else None
        if val is None:
            notes.append(f"{key}: missing from report")
            verdict = "CONCERNS" if verdict == "PASS" else verdict
            continue
        worse = (lambda v, lim: v > lim) if rule.get("dir", "max") == "max" else (lambda v, lim: v < lim)
        if "fail" in rule and worse(val, rule["fail"]):
            notes.append(f"{key}={val} breaks fail limit {rule['fail']} ({rule.get('why', '')})")
            verdict = "FAIL"
        elif "warn" in rule and worse(val, rule["warn"]):
            notes.append(f"{key}={val} past warn limit {rule['warn']} ({rule.get('why', '')})")
            verdict = "CONCERNS" if verdict == "PASS" else verdict
    if report.get("bots_ready", 0) < args.bots:
        notes.append(f"only {report.get('bots_ready')} of {args.bots} bots got ready")
        verdict = "FAIL"
    out_dir = BOTS / "reports"
    out_dir.mkdir(exist_ok=True)
    report["verdict"], report["notes"] = verdict, notes
    path = out_dir / f"loadtest-{args.bots}bots.json"
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"LOADTEST {verdict}  (report: {path.relative_to(ROOT)})")
    return 0 if verdict != "FAIL" else 1


def _relposix(f: Path) -> str:
    try:
        return f.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return f.as_posix()


def _scannable(text: str, suffix: str) -> str:
    """Blank out text the hallucination rules must not judge, keeping line numbers.

    Markdown: only fenced code blocks are scanned (prose and tables may name wrong APIs on purpose).
    Any file: lines between `kit:allow-begin` and `kit:allow-end` markers are skipped.
    """
    out, in_fence, allow = [], False, False
    for line in text.split("\n"):
        if "kit:allow-begin" in line:
            allow = True
        keep = not allow
        if suffix == ".md":
            if line.lstrip().startswith(("```", "~~~")):
                in_fence = not in_fence
                keep = False
            elif not in_fence:
                keep = False
        if "kit:allow-end" in line:
            allow = False
        out.append(line if keep else "")
    return "\n".join(out)


def cmd_check(args) -> int:
    catalog = read_json(ROOT / "rules" / "hallucinations.json")
    paths = [Path(p) for p in (args.paths or ["."])]
    exts = {".rs", ".ts", ".tsx", ".js", ".cs", ".gd", ".cpp", ".h", ".md", ".toml", ".json", ".py", ".sh", ".ps1", ".yml", ".yaml"}
    skip = {"node_modules", "target", ".git", ".godot", "module_bindings", "spacetime_bindings", "vendor", "addons", ".kit", "samples", "kb"}
    hits = 0
    for base in paths:
        files = [base] if base.is_file() else [p for p in base.rglob("*") if p.is_file() and p.suffix in exts and not (set(p.parts) & skip)]
        for f in files:
            if f.name in ("hallucinations.json", "kit.py"):
                continue
            try:
                text = f.read_text(encoding="utf-8-sig", errors="ignore")
            except OSError:
                continue
            text = _scannable(text, f.suffix)
            for rule in catalog["rules"]:
                if rule.get("ext") and f.suffix not in rule["ext"]:
                    continue
                if rule.get("path") and not re.search(rule["path"], _relposix(f)):
                    continue
                for m in re.finditer(rule["pattern"], text, re.M):
                    line = text.count("\n", 0, m.start()) + 1
                    ctx_line = text.splitlines()[line - 1] if text else ""
                    if "kit:allow" in ctx_line:
                        continue
                    hits += 1
                    print(f"{f}:{line}: [{rule['id']}] {rule['message']}\n    fix: {rule['fix']}")
    print(f"check: {hits} finding(s)")
    return 1 if hits else 0


def cmd_new(args) -> int:
    dest = Path(args.dest).resolve() / args.name
    if dest.exists():
        sys.exit(f"{dest} already exists; refusing to overwrite")
    ignore = shutil.ignore_patterns("target", "node_modules", ".godot", "reports", "codegen_debug", ".kit")
    server_src = ROOT / "templates" / "server" / args.server
    if not server_src.exists():
        sys.exit(f"unknown server template {args.server}: {[p.name for p in (ROOT / 'templates' / 'server').iterdir()]}")
    shutil.copytree(server_src, dest / "server", ignore=ignore)
    if args.client != "none":
        shutil.copytree(ROOT / "templates" / "client" / args.client, dest / "client", ignore=ignore)
    if getattr(args, "sidecar", False):
        shutil.copytree(ROOT / "templates" / "sidecar", dest / "sidecar", ignore=ignore)
    for d in ("rules", "skills", "agents", "docs"):
        if (ROOT / d).exists():
            shutil.copytree(ROOT / d, dest / d, ignore=ignore)
    for f in ("AGENTS.md", "CLAUDE.md", "stdb.lock", ".gitignore", "NOTICE"):
        if (ROOT / f).exists():
            shutil.copy2(ROOT / f, dest / f)
    shutil.copytree(ROOT / "tools", dest / "tools", ignore=ignore)
    db = re.sub(r"[^a-z0-9-]", "-", args.name.lower())
    lock = (dest / "stdb.lock").read_text(encoding="utf-8-sig")
    lock = lock.replace('database = "mmo-dev"', f'database = "{db}-dev"').replace('module = "templates/server/rust-single"', 'module = "server"')
    lock = lock.replace("[dev]\n", "[dev]\n" + ('godot_client = "client"\n' if args.client in ("godot", "godot-shard") else "")
                        + ('web_admin = "client"\n' if args.client == "web-admin" else ""), 1)
    (dest / "stdb.lock").write_text(lock, encoding="utf-8")
    cfg = dest / "client" / "spacetime_bindings" / "plugin_config.tres"
    if cfg.exists():
        cfg.write_text(cfg.read_text(encoding="utf-8").replace('"mmo-dev"', f'"{db}-dev"'), encoding="utf-8")
    cargo = dest / "server" / "Cargo.toml"
    if cargo.exists():
        cargo.write_text(re.sub(r'^name = ".*"$', f'name = "{db.replace("-", "_")}_server"', cargo.read_text(encoding="utf-8"), count=1, flags=re.M), encoding="utf-8")
    if getattr(args, "sidecar", False):
        lock = (dest / "stdb.lock").read_text(encoding="utf-8-sig").replace("[dev]\n", '[dev]\nsidecar = "sidecar"\n', 1)
        (dest / "stdb.lock").write_text(lock, encoding="utf-8")
    say(f"created {dest}")
    if args.server == "rust-sharded":
        print(f"next:\n  cd {dest}\n  python tools/kit.py doctor\n  python server/scripts/dev_up.py --regions 2   # global + 2 regions, peered"
              "\n  see server/README.md for the handoff protocol and client flow")
    elif args.server == "rust-shard":
        print(f"next:\n  cd {dest}\n  python tools/kit.py doctor\n  python tools/kit.py server --isolated   # own terminal"
              f"\n  python tools/shard/fixture_game.py live --publish --db {db}-dev --godot $GODOT   # publish, seed, play Meadowmere"
              "\n  see docs/SHARD_CORE.md (world document, Game hooks, vendoring)")
    else:
        print(f"next:\n  cd {dest}\n  python tools/kit.py doctor\n  python tools/kit.py publish\n  python tools/kit.py smoke")
    if args.client in ("unity", "unreal"):
        print(f"  client/README.md: {args.client} starter (read its Status line first)")
    return 0


OFFICIAL = ["concepts", "rust-server", "typescript-server", "csharp-server", "cpp-server",
            "typescript-client", "csharp-client", "unity", "unreal", "cli", "mcp"]


def cmd_vendor_skills(args) -> int:
    base = "https://raw.githubusercontent.com/clockworklabs/SpacetimeDB/{ref}/codex-plugin/plugins/spacetimedb/skills/{name}/SKILL.md"
    out = ROOT / "skills" / "vendor" / "official"
    names = sorted(p.name for p in out.iterdir() if p.is_dir()) if out.exists() else OFFICIAL
    changed = 0
    for name in names:
        url = base.format(ref=args.ref, name=name)
        try:
            body = http_get(url)
        except Exception as e:  # noqa: BLE001
            print(f"  SKIP {name}: {e}")
            continue
        target = out / name / "SKILL.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        old = target.read_text(encoding="utf-8") if target.exists() else ""
        if old != body:
            target.write_text(body, encoding="utf-8")
            changed += 1
            print(f"  UPDATED {name}")
        else:
            print(f"  same    {name}")
    lic = "https://raw.githubusercontent.com/clockworklabs/SpacetimeDB/{ref}/codex-plugin/plugins/spacetimedb/LICENSE"
    try:
        (out / "LICENSE").write_text(http_get(lic.format(ref=args.ref)), encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        print(f"  could not refresh LICENSE ({e}); keep the existing Apache-2.0 LICENSE file")
    (out / "SOURCE.txt").write_text(
        "upstream: https://github.com/clockworklabs/SpacetimeDB/tree/{0}/codex-plugin/plugins/spacetimedb/skills\n"
        "ref: {0}\nfetched: {1}\nlicense: Apache-2.0 (see LICENSE); unmodified copies\n".format(
            args.ref, time.strftime("%Y-%m-%d")), encoding="utf-8")
    print(f"vendor-skills: {changed} changed. Review the diff, re-run `python tools/kit.py check`, then commit.")
    return 0


def cmd_install_claude(args) -> int:
    """Copy roles and kit skills to where Claude Code looks (.claude/agents, .claude/skills)."""
    dest = Path(args.dest).resolve() if args.dest else ROOT
    agents_out, skills_out = dest / ".claude" / "agents", dest / ".claude" / "skills"
    agents_out.mkdir(parents=True, exist_ok=True)
    skills_out.mkdir(parents=True, exist_ok=True)
    n = 0
    for f in sorted((ROOT / "agents").glob("*.md")):
        if f.name.lower() != "readme.md":
            shutil.copy2(f, agents_out / f.name)
            n += 1
    m = 0
    for d in sorted((ROOT / "skills").iterdir()):
        if d.is_dir() and (d / "SKILL.md").exists():
            shutil.copytree(d, skills_out / d.name, dirs_exist_ok=True)
            m += 1
    official = ROOT / "skills" / "vendor" / "official"
    if official.exists():  # official skills keep their upstream names (cli, rust-server, unity, ...)
        for d in sorted(official.iterdir()):
            if d.is_dir() and (d / "SKILL.md").exists():
                shutil.copytree(d, skills_out / d.name, dirs_exist_ok=True)
                m += 1
    say(f"installed {n} agents and {m} skills under {dest / '.claude'} (regenerated copies; edit the originals)")
    return 0


def cmd_kb_export(args) -> int:
    kb = ROOT / "kb"
    db_path = kb / "stdb-kb.sqlite"
    if db_path.exists():
        db_path.unlink()
    con = sqlite3.connect(db_path)
    total = 0
    for jf in sorted(kb.glob("*.json")):
        rows = read_json(jf)
        if not rows:
            continue
        table = jf.stem.replace("-", "_")
        cols = sorted({k for r in rows for k in r})
        con.execute(f'CREATE TABLE "{table}" ({", ".join(f"{c!r} TEXT" for c in cols)})')
        for r in rows:
            if r.get("visibility", "public") != "public":
                sys.exit(f"{jf.name}: non-public row found; the public KB must not contain it")
            con.execute(f'INSERT INTO "{table}" VALUES ({",".join("?" * len(cols))})',
                        [json.dumps(r[c]) if isinstance(r.get(c), (list, dict)) else r.get(c) for c in cols])
        total += len(rows)
    con.commit()
    con.close()
    say(f"wrote {db_path.relative_to(ROOT)} ({total} rows). Try: sqlite3 kb/stdb-kb.sqlite \"select title from gotchas\"")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="kit.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--url", help=f"server URL (default {LOCK['dev']['url']})")
        sp.add_argument("--db", help=f"database name (default {LOCK['dev']['database']})")
        return sp

    sub.add_parser("doctor")
    s = common(sub.add_parser("server")); s.add_argument("--isolated", action="store_true", help="keep CLI config + data under .kit/")
    s = common(sub.add_parser("publish")); s.add_argument("--module"); s.add_argument("--wipe", action="store_true", help="delete data (dev only)")
    s = common(sub.add_parser("bindings")); s.add_argument("--module"); s.add_argument("--check", action="store_true")
    s = common(sub.add_parser("smoke")); s.add_argument("--godot", action="store_true")
    s = common(sub.add_parser("loadtest")); s.add_argument("--bots", type=int, default=100); s.add_argument("--duration", type=int, default=20)
    s = sub.add_parser("check"); s.add_argument("paths", nargs="*")
    s = sub.add_parser("new"); s.add_argument("name"); s.add_argument("--dest", default=".."); s.add_argument("--server", default="rust-single"); s.add_argument("--client", default="godot", choices=["godot", "godot-shard", "web-admin", "unity", "unreal", "none"]); s.add_argument("--sidecar", action="store_true", help="also copy templates/sidecar")
    s = sub.add_parser("vendor-skills"); s.add_argument("--ref", default="master")
    sub.add_parser("kb-export")
    s = sub.add_parser("install-claude"); s.add_argument("--dest", help="project root (default: this repo)")
    args = p.parse_args()
    return {"doctor": cmd_doctor, "server": cmd_server, "publish": cmd_publish, "bindings": cmd_bindings,
            "smoke": cmd_smoke, "loadtest": cmd_loadtest, "check": cmd_check, "new": cmd_new,
            "vendor-skills": cmd_vendor_skills, "kb-export": cmd_kb_export,
            "install-claude": cmd_install_claude}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
