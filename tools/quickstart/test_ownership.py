# SPDX-License-Identifier: Apache-2.0
"""Real listener and cancellation regressions; no CLI/server install required."""
import importlib.util
import json
import contextlib
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verify_ownership", Path(__file__).with_name("verify.py"))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)
POPEN = subprocess.Popen


def python(code, **kwargs):
    return POPEN([sys.executable, "-B", "-c", code], **kwargs, **verify.process_options())


def until(predicate):
    deadline = time.monotonic() + 10
    while not predicate():
        if time.monotonic() >= deadline:
            raise AssertionError("real child did not become ready within 10 seconds")
        time.sleep(.02)


def running(pid):
    if verify.WIN:
        return pid in verify.windows_parents()
    try:
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def http_code(port):
    return ("import http.server\n"
            "class Handler(http.server.BaseHTTPRequestHandler):\n"
            " def do_GET(self): self.send_response(200); self.end_headers(); self.wfile.write(b'pong')\n"
            " def log_message(self,*args): pass\n"
            f"http.server.HTTPServer(('127.0.0.1', {port}), Handler).serve_forever()")


class OwnershipTests(unittest.TestCase):
    def run_main(self, directory, competing=False):
        """Stub build tools only; real startup, HTTP, OS ownership, and cleanup."""
        processes, commands = [], []
        work = Path(directory) / "run"
        descendant = Path(directory) / "server-child.pid"
        port = None

        def reserve(requested):
            nonlocal port
            self.assertIn("--noEmit", commands[-1])  # select immediately after setup
            port = original_reserve(requested)
            if competing:
                foreign = python(http_code(port), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                processes.append(foreign)
                until(lambda: verify.listener_owners(port, {foreign.pid}) == {foreign.pid})
            return port

        class Completed:
            returncode = 0
            pid = 0
            def poll(self): return 0
            def wait(self, **kw): return 0

        def launch(command, **kw):
            if command[0] == "taskkill":
                return POPEN(command, **kw)
            commands.append(command)
            if "start" in command:
                if competing:
                    code = "import time; time.sleep(60)"
                else:
                    # The listener is a descendant of the CLI root, as with spacetime.
                    code = ("import subprocess,sys; from pathlib import Path; "
                            f"p=subprocess.Popen([sys.executable,'-B','-c',{http_code(port)!r}],"
                            f"creationflags={subprocess.CREATE_NO_WINDOW if verify.WIN else 0}); "
                            f"Path({str(descendant)!r}).write_text(str(p.pid)); p.wait()")
                proc = POPEN([sys.executable, "-B", "-c", code], **kw)
                processes.append(proc)
                return proc
            text = ""
            if command[0] == "git" and "rev-parse" in command:
                text = "test-revision"
            elif "--version" in command:
                text = "v22.0.0" if command[0] == "node" else "tool version 2.14.0"
            if "build" in command:
                wasm = Path(kw["env"]["CARGO_TARGET_DIR"]) / "wasm32-unknown-unknown/release/mmo_server.wasm"
                wasm.parent.mkdir(parents=True)
                wasm.write_bytes(b"test-build-stub")
            kw["stdout"].write(text)
            kw["stdout"].flush()
            return Completed()

        original_reserve = verify.reserve_port
        try:
            with patch.object(sys, "argv", ["verify.py", "--work-dir", str(work)]), \
                    patch.object(verify.platform, "platform", return_value="ownership-regression"), \
                    patch.object(verify, "compact_path", side_effect=lambda value: value), \
                    patch.object(verify.shutil, "which", side_effect=lambda value: value), \
                    patch.object(verify, "reserve_port", side_effect=reserve), \
                    patch.object(verify.subprocess, "Popen", side_effect=launch):
                result = verify.main()
            receipt = json.loads((work / "receipt.json").read_text())
            self.assertIsNotNone(processes[-1].poll(), "main must reap its real server")
            if competing:
                self.assertIsNone(processes[0].poll(), "foreign listener must survive")
                self.assertEqual(result, 1)
                self.assertEqual(receipt["verdict"], "FAIL")
                self.assertIn("ownership conflict", receipt["error"])
                self.assertFalse(any("publish" in c for c in commands))
            else:
                self.assertEqual(result, 0)
                self.assertEqual(receipt["verdict"], "PASS")
                self.assertTrue(any("publish" in c for c in commands))
                self.assertIn("listener_ownership", receipt["server"])
                until(lambda: not running(int(descendant.read_text())))
                self.assertEqual(verify.listener_owners(port, set()), set())
        finally:
            for proc in processes:
                verify.stop_owned(proc)

    def test_competing_listener_live_initializing_child_never_publishes(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_main(directory, competing=True)

    def test_owned_descendant_listener_allows_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_main(directory)

    def test_keyboard_interrupt_reaps_real_step_and_tree_preserves_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "child.pid"
            # The grandchild listens, so disappearance can be checked without
            # process-control access to any unrelated PID (or zombie ambiguity).
            port = verify.reserve_port(0)
            grandchild = ("from pathlib import Path; import http.server,os; "
                          f"s=http.server.HTTPServer(('127.0.0.1',{port}),http.server.SimpleHTTPRequestHandler); "
                          f"Path({str(ready)!r}).write_text(str(os.getpid())); s.serve_forever()")
            code = ("import subprocess,sys; "
                    f"p=subprocess.Popen([sys.executable,'-B','-c',{grandchild!r}],"
                    f"creationflags={subprocess.CREATE_NO_WINDOW if verify.WIN else 0}); p.wait()")
            processes = []
            interruption = KeyboardInterrupt("test cancellation during step wait")

            class Interrupted:
                def __init__(self, command, **kw):
                    self.proc = POPEN([sys.executable, "-B", "-c", code], **kw)
                    processes.append(self.proc)
                    self.first = True
                def __getattr__(self, name): return getattr(self.proc, name)
                def wait(self, **kw):
                    if self.first:
                        self.first = False
                        until(ready.exists)
                        raise interruption
                    return self.proc.wait(**kw)

            def launch(command, **kw):
                return POPEN(command, **kw) if command[0] == "taskkill" else Interrupted(command, **kw)

            try:
                with patch.object(sys, "argv", ["verify.py", "--work-dir", str(Path(directory) / "run")]), \
                        patch.object(verify.platform, "platform", return_value="interrupt-regression"), \
                        patch.object(verify.subprocess, "Popen", side_effect=launch):
                    with self.assertRaises(KeyboardInterrupt) as raised:
                        verify.main()
                self.assertIs(raised.exception, interruption)
                self.assertIsNotNone(processes[0].poll())
                pid = int(ready.read_text())
                until(lambda: not running(pid))
                until(lambda: not verify.listener_owners(port, {pid}))
                self.assertEqual(json.loads((Path(directory) / "run/receipt.json").read_text())["verdict"], "FAIL")
            finally:
                for proc in processes:
                    verify.stop_owned(proc)

    def test_cleanup_error_does_not_replace_original_exception(self):
        with patch.object(verify, "stop_owned", side_effect=OSError("cleanup failure")):
            original = KeyboardInterrupt("original")
            with self.assertRaises(KeyboardInterrupt) as raised:
                with verify.owning(type("Proc", (), {"pid": 123})()):
                    raise original
            self.assertIs(raised.exception, original)
            self.assertIn("cleanup failure", original.__notes__[0])

    def test_unsupported_inspection_fails_closed(self):
        with patch.object(verify, "WIN", False), patch.object(verify.sys, "platform", "unsupported"):
            with self.assertRaisesRegex(RuntimeError, "Windows and Linux only"):
                verify.listener_owners(12345, {1})

    def test_ownership_inspection_error_after_http_is_not_retried(self):
        with patch.object(verify, "assert_owned_listener", side_effect=[True, PermissionError("inspection denied")]), \
                patch.object(verify.urllib.request, "urlopen", return_value=contextlib.nullcontext()):
            with self.assertRaisesRegex(PermissionError, "inspection denied"):
                verify.wait_for_owned_server(None, 12345)

    def test_ipv6_competing_listener_is_also_rejected(self):
        with socket.socket(socket.AF_INET6) as listener:
            try:
                listener.bind(("::1", 0))
            except OSError as exc:
                self.skipTest(f"IPv6 loopback unavailable: {exc}")
            listener.listen()
            proc = python("import time; time.sleep(60)", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                with self.assertRaisesRegex(RuntimeError, "ownership conflict"):
                    verify.assert_owned_listener(proc, listener.getsockname()[1])
                self.assertIsNone(proc.poll())
                self.assertGreaterEqual(listener.fileno(), 0)
            finally:
                verify.stop_owned(proc)


if __name__ == "__main__":
    unittest.main()
