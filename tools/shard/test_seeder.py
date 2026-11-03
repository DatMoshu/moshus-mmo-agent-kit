"""Task1578: accepted DIALOGUE-ID-COMPAT.md sections2/5 D1-D4, synthetic only.
Provenance: original tests; clean implementer ultima-mmo-worker-night9, 2026-11-03.
"""
import copy
import unittest
from unittest.mock import patch
import seeder
import fixture_game

class DialogueIds(unittest.TestCase):
    def test_native_domain_survives_json_and_call(self):
        for talk in [0, 1, 15, 255, 256, 319, 1025, 1430, 65535]:
            with self.subTest(talk=talk):
                doc = fixture_game.build()
                doc["npcs"][0]["talk"] = talk
                doc = seeder.json.loads(seeder.json.dumps(doc))
                with patch.object(seeder, "call") as call:
                    seeder.seed(doc, "unused", "synthetic", jobs=1)
                calls = [c for c in call.call_args_list if c.args[2] == "seed_npcs"]
                self.assertEqual(calls[0].args[-1][0], talk)
                self.assertIs(type(calls[0].args[-1][0]), int)

    def test_rejects_before_any_destructive_call(self):
        for talk in [-1, 65536, True, False, 1.0, "1025", None]:
            with self.subTest(talk=talk):
                doc = fixture_game.build()
                doc["npcs"][-1]["talk"] = talk
                before = copy.deepcopy(doc)
                with patch.object(seeder, "call") as call:
                    with self.assertRaises(SystemExit):
                        seeder.seed(doc, "unused", "synthetic")
                call.assert_not_called()
                self.assertEqual(doc, before)

    def test_absent_talk_defaults_zero(self):
        doc = fixture_game.build()
        for npc in doc["npcs"]:
            npc.pop("talk")
        with patch.object(seeder, "call") as call:
            seeder.seed(doc, "unused", "synthetic", jobs=1)
        self.assertEqual(next(c for c in call.call_args_list if c.args[2] == "seed_npcs").args[-1], [0, 0, 0])

    def test_slot_count_bound_preflight(self):
        doc = fixture_game.build()
        npc = doc["npcs"][0]
        doc["npcs"] = [dict(npc, slot=i) for i in range(256)]
        seeder.validate(doc)
        doc["npcs"].append(dict(npc, slot=0))
        with patch.object(seeder, "call") as call:
            with self.assertRaises(SystemExit):
                seeder.seed(doc, "unused", "synthetic")
        call.assert_not_called()

if __name__ == "__main__":
    unittest.main()
