# SPDX-License-Identifier: Apache-2.0
"""Regression checks for dependency reproducibility and honest smoke verdicts."""
import argparse
import importlib.util
from pathlib import Path
import socket
import subprocess
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


kit = load("kit", TOOLS / "kit.py")
verify = load("verify", TOOLS / "quickstart" / "verify.py")


class ToolingTests(unittest.TestCase):
    def test_compile_error_is_not_retried(self):
        failure = subprocess.CompletedProcess([], 1, "", "SyntaxError: invalid syntax")
        with patch.object(kit, "bots", return_value=failure) as bots:
            verdict, result = kit.bots_verdict("smoke", [])
        self.assertIsNone(verdict)
        self.assertEqual(result.returncode, 1)
        bots.assert_called_once()

    def test_transient_connection_is_retried(self):
        failure = subprocess.CompletedProcess([], 1, "", "ECONNREFUSED")
        success = subprocess.CompletedProcess([], 0, '{"verdict":"PASS"}', "")
        with patch.object(kit, "bots", side_effect=[failure, success]) as bots, patch.object(kit.time, "sleep"):
            verdict, _ = kit.bots_verdict("smoke", [])
        self.assertEqual(verdict["verdict"], "PASS")
        self.assertEqual(bots.call_count, 2)

    def test_real_fail_is_not_retried(self):
        result = subprocess.CompletedProcess([], 1, '{"verdict":"FAIL"}', "ECONNRESET")
        with patch.object(kit, "bots", return_value=result) as bots:
            verdict, _ = kit.bots_verdict("smoke", [])
        self.assertEqual(verdict["verdict"], "FAIL")
        bots.assert_called_once()

    def test_pass_json_with_failure_exit_fails_smoke(self):
        result = subprocess.CompletedProcess([], 2, '{"verdict":"PASS"}', "")
        with patch.object(kit, "ensure_bots"), patch.object(kit, "wait_for_server", return_value=True), \
                patch.object(kit, "bots_verdict", return_value=({"verdict": "PASS"}, result)):
            self.assertEqual(kit.cmd_smoke(argparse.Namespace(url="http://127.0.0.1:12345", db="test", godot=False)), 1)

    def test_fresh_bots_install_uses_frozen_lock(self):
        with patch.object(Path, "exists", return_value=False), patch.object(kit, "npm", return_value="npm"), \
                patch.object(kit, "spacetime", return_value=["spacetime"]), patch.object(kit, "run") as run:
            kit.ensure_bots()
        self.assertEqual(run.call_args_list[0].args[0], ["npm", "ci", "--no-audit", "--no-fund"])

    def test_busy_port_is_rejected_before_start(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            sock.listen()
            with self.assertRaises(OSError):
                verify.reserve_port(sock.getsockname()[1])

    def test_bots_run_local_tsx_without_npx_download(self):
        with patch.object(kit, "which", return_value="node"), patch.object(kit, "run") as run:
            kit.bots(["--mode", "smoke"])
        command = run.call_args.args[0]
        self.assertEqual(command[0], "node")
        self.assertTrue(command[1].endswith("cli.mjs"))
        self.assertNotIn("npx", command)


if __name__ == "__main__":
    unittest.main()
