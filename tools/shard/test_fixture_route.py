"""The fixture must prove both peers, retain diagnostics, and isolate player data."""
import argparse
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import fixture_game


class FixtureRoute(unittest.TestCase):
    def exercise(self, outputs, timeout=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            client = root / "client"
            (client / ".godot").mkdir(parents=True)
            logs = root / "logs"
            args = argparse.Namespace(godot="synthetic-godot", url="http://127.0.0.1:1",
                                      db="synthetic", renderer="2d", logs=str(logs))
            launches = []

            class Process:
                def __init__(self, command, **kwargs):
                    self.index = len(launches)
                    self.pid = self.index + 1
                    self.returncode = 0
                    self.output = kwargs["stdout"]
                    launches.append((command, kwargs))

                def wait(self, **kwargs):
                    # Catch an accidental sequential start-and-wait harness.
                    self_test.assertEqual(len(launches), 2)
                    self.output.write(outputs[self.index])
                    self.output.flush()
                    if timeout and self.index == 0:
                        raise fixture_game.subprocess.TimeoutExpired("synthetic-godot", 120)
                    return 0

                def poll(self):
                    return self.returncode

            self_test = self
            with patch.object(fixture_game, "CLIENT", client), \
                 patch.object(fixture_game.subprocess, "Popen", Process), \
                 patch.object(fixture_game.time, "sleep"):
                result = fixture_game.godot_route(args, fixture_game.build())
            self.assertNotEqual(launches[0][1]["env"]["APPDATA"], launches[1][1]["env"]["APPDATA"])
            for i in (1, 2):
                self.assertEqual((logs / f"client-{i}.log").read_text(), outputs[i - 1])
            self.assertTrue((logs / "launches.json").is_file())
            return result

    def test_two_peers_and_complete_logs(self):
        self.assertTrue(self.exercise(["diagnostics\nAUTOPILOT PASS one\n", "AUTOPILOT PASS two\n"]))

    def test_zero_exit_without_second_pass_is_failure(self):
        self.assertFalse(self.exercise(["AUTOPILOT PASS one\n", "SOURCE only\n"]))

    def test_script_error_with_pass_is_failure(self):
        self.assertFalse(self.exercise(["AUTOPILOT PASS one\n", "SCRIPT ERROR: synthetic\nAUTOPILOT PASS two\n"]))

    def test_timeout_with_racing_success_is_failure(self):
        self.assertFalse(self.exercise(["AUTOPILOT PASS one\n", "AUTOPILOT PASS two\n"], timeout=True))


if __name__ == "__main__":
    unittest.main()
