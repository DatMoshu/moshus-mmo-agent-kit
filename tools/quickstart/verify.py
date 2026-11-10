#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build rust-single and prove two clients see each other move on an owned server.

Requires the pinned CLI + Rust toolchain, Node >=22 and Python >=3.11.
Run from any directory: python tools/quickstart/verify.py
The fresh work directory retains logs, isolated CLI config/data, dependency caches,
build outputs and receipt.json. No fleet services, credentials or prebuilt wasm needed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
WIN = os.name == "nt"


def process_options() -> dict:
    return {"creationflags": subprocess.CREATE_NO_WINDOW} if WIN else {"start_new_session": True}


def stop_owned(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    if WIN:
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                       capture_output=True, **process_options())
    else:
        os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if WIN:
            proc.kill()
        else:
            os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()


def reserve_port(port: int) -> int:
    # Fail before launching anything if the requested port is already in use.
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", port))
        return sock.getsockname()[1]


def compact_path(path: str) -> str:
    """Keep existing tools once; long inherited Windows PATHs break npm's cmd.exe scripts."""
    seen = set()
    result = []
    for entry in path.split(os.pathsep):
        key = os.path.normcase(os.path.normpath(entry))
        if entry and key not in seen and Path(entry).is_dir():
            seen.add(key)
            result.append(entry)
    return os.pathsep.join(result)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, help="new directory for isolated state and evidence")
    parser.add_argument("--port", type=int, default=0, help="loopback port; default: a free OS-assigned port")
    parser.add_argument("--loadtest", action="store_true", help="also run a 10-bot, 5-second diagnostic gate")
    args = parser.parse_args()
    if args.port == 3000:
        parser.error("use a nondefault port to keep development servers separate")
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="mmo-kit-verify-"))
    if args.work_dir:
        work.mkdir(parents=True, exist_ok=False)
    print(f"Verification evidence: {work}", flush=True)
    lock = tomllib.loads((ROOT / "stdb.lock").read_text(encoding="utf-8-sig"))
    env = dict(os.environ)
    for key in list(env):
        if key.lower().startswith("npm_config_") or key.upper() in ("NPM_TOKEN", "NODE_AUTH_TOKEN"):
            env.pop(key)
    for key in ("KIT_WASM", "SPACETIME_ARGS", "GODOT", "CARGO_ENCODED_RUSTFLAGS", "RUSTFLAGS", "RUSTC_WRAPPER"):
        env.pop(key, None)
    env.update(CARGO_HOME=str(work / "cargo-home"), CARGO_TARGET_DIR=str(work / "target"),
               npm_config_cache=str(work / "npm-cache"), npm_config_update_notifier="false",
               npm_config_registry="https://registry.npmjs.org/",
               npm_config_userconfig=str(work / "npm-user.conf"), npm_config_globalconfig=str(work / "npm-global.conf"))
    for name in ("npm-user.conf", "npm-global.conf"):
        (work / name).write_text("", encoding="utf-8")
    receipt = {"verdict": "FAIL", "steps": [], "source": str(ROOT), "platform": platform.platform(),
               "python": sys.version.split()[0], "toolchain_install": "prerequisite; excluded from run timing"}
    started = time.monotonic()
    server = None
    server_log = None

    def step(name: str, command: list[str], cwd: Path = ROOT, timeout: int = 600) -> str:
        print(f"[{name}] {subprocess.list2cmdline(command)}", flush=True)
        t0 = time.monotonic()
        path = work / f"{name}.log"
        with path.open("w", encoding="utf-8") as log:
            proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, **process_options())
            try:
                code = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                stop_owned(proc)
                code = 124
        receipt["steps"].append({"step": name, "command": command, "cwd": str(cwd),
                                 "exit_code": code, "seconds": round(time.monotonic() - t0, 3), "log": path.name})
        output = path.read_text(encoding="utf-8", errors="replace")
        if code:
            raise RuntimeError(f"{name}: exit {code}; see {path}\n{output[-3000:]}")
        return output

    try:
        receipt["git_sha"] = step("revision", ["git", "rev-parse", "HEAD"]).strip()
        receipt["git_status_before"] = step("source-status", ["git", "status", "--porcelain"]).strip()
        port = reserve_port(args.port)
        url = f"http://127.0.0.1:{port}"
        receipt["url"] = url
        cli = os.environ.get("SPACETIME") or shutil.which("spacetime")
        if not cli:
            raise RuntimeError(f"Install SpacetimeDB {lock['spacetimedb']['version']} or set SPACETIME to its CLI")
        cli_cmd = [cli, "--root-dir", str(work / "cli-root"), "--config-path", str(work / "cli.toml")]
        version = step("cli-version", [*cli_cmd, "--version"])
        if not re.search(r"tool version " + re.escape(lock["spacetimedb"]["version"]) + r"\b", version):
            raise RuntimeError("CLI does not match stdb.lock; install the pinned release")
        node, npm, cargo = shutil.which("node"), shutil.which("npm"), shutil.which("cargo")
        if not all((node, npm, cargo)):
            raise RuntimeError("Install Node >=22 (with npm) and Rust via rustup; put node, npm and cargo on PATH")
        if WIN:
            env["PATH"] = compact_path(str(Path(node).parent) + os.pathsep + env.get("PATH", ""))
        if int(step("node-version", [node, "--version"]).strip().lstrip("v").split(".")[0]) < 22:
            raise RuntimeError("Node >=22 is required")
        rust = lock["toolchain"]["rust"]
        step("rust-version", [cargo, f"+{rust}", "--version"])
        linker = shutil.which("link.exe") if WIN else None
        if linker and "git" in [part.lower() for part in Path(linker).parts]:
            raise RuntimeError("Git link.exe shadows the Microsoft linker. Run from Developer PowerShell for Visual Studio (C++ workload).")
        step("check", [sys.executable, "tools/kit.py", "check"])
        module = ROOT / lock["dev"]["module"]
        step("cargo-fetch", [cargo, f"+{rust}", "fetch", "--locked", "--target", "wasm32-unknown-unknown"], module)
        step("build", [cargo, f"+{rust}", "build", "--locked", "--target", "wasm32-unknown-unknown", "--release"], module)
        package = tomllib.loads((module / "Cargo.toml").read_text(encoding="utf-8"))["package"]["name"]
        wasm = work / "target" / "wasm32-unknown-unknown" / "release" / (package.replace("-", "_") + ".wasm")
        if not wasm.is_file():
            raise RuntimeError(f"Source build produced no module: {wasm}")
        receipt["wasm_sha256"] = hashlib.sha256(wasm.read_bytes()).hexdigest()
        bots = ROOT / "tools" / "loadtest" / "bots"
        step("npm-ci", [npm, "ci", "--no-audit", "--no-fund"], bots)
        step("bindings", [*cli_cmd, "generate", "--lang", "typescript", "--out-dir",
                          str(bots / "src" / "module_bindings"), "--bin-path", str(wasm), "--yes"])
        tracked = step("tracked-bindings", ["git", "ls-files", "tools/loadtest/bots/src/module_bindings"]).strip()
        receipt["bindings_baseline"] = "tracked" if tracked else "generated on demand; no committed bot bindings"
        if tracked:
            step("bindings-drift", ["git", "diff", "--exit-code", "--", "tools/loadtest/bots/src/module_bindings"])
        step("typecheck", [node, str(bots / "node_modules/typescript/bin/tsc"), "--noEmit"], bots)
        server_cmd = [*cli_cmd, "start", "--listen-addr", f"127.0.0.1:{port}", "--data-dir", str(work / "data")]
        server_log = (work / "server.log").open("w", encoding="utf-8")
        server = subprocess.Popen(server_cmd, cwd=ROOT, env=env, stdout=server_log,
                                  stderr=subprocess.STDOUT, **process_options())
        receipt["server"] = {"command": server_cmd, "pid": server.pid}
        deadline = time.monotonic() + 45
        while True:
            if server.poll() is not None:
                raise RuntimeError("Server exited during startup; see server.log")
            try:
                with urllib.request.urlopen(url + "/v1/ping", timeout=1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Server startup timed out; see server.log")
                time.sleep(0.2)
        step("publish", [*cli_cmd, "publish", "kit-verify", "--server", url, "--bin-path", str(wasm), "--yes"])
        step("smoke", [sys.executable, "tools/kit.py", "smoke", "--url", url, "--db", "kit-verify"], timeout=90)
        if args.loadtest:
            step("loadtest", [sys.executable, "tools/kit.py", "loadtest", "--url", url, "--db", "kit-verify",
                              "--bots", "10", "--duration", "5"], timeout=90)
        receipt["verdict"] = "PASS"
    except (OSError, ValueError, RuntimeError) as exc:
        receipt["error"] = str(exc)
        print(str(exc), file=sys.stderr)
    finally:
        if server is not None:
            stop_owned(server)
            receipt["server"]["exit_code"] = server.returncode
        if server_log is not None:
            server_log.close()
        receipt["seconds"] = round(time.monotonic() - started, 3)
        (work / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"VERIFY {receipt['verdict']} ({receipt['seconds']}s); {work / 'receipt.json'}")
    return 0 if receipt["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
