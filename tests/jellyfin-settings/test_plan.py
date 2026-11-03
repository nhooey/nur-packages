"""Unit tests of jellyfin-apply-settings' pure planning, with no Jellyfin.

Run: python3 -I tests/jellyfin-settings/test_plan.py <path to the script>
"""

import importlib.util
import sys
import unittest

spec = importlib.util.spec_from_file_location("jas", sys.argv.pop(1))
jas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jas)


def expand(p):
    return p.replace("~", "/home/u", 1)


STATE = {
    "encoding": {"H264Crf": 23, "HardwareAccelerationType": "none", "Other": 1},
    "users": [{"Name": "u", "Id": "42", "Configuration": {"SubtitleMode": "Default", "X": 0}}],
    "folders": [{"Name": "Movies", "Locations": ["/home/u/Video/Movies"]}],
}


class Plan(unittest.TestCase):
    def test_matching_settings_plan_nothing(self):
        settings = {"encoding": {"H264Crf": 23}, "users": {"u": {"SubtitleMode": "Default"}},
                    "libraries": {"Movies": {"type": "movies", "paths": ["~/Video/Movies"]}}}
        self.assertEqual(jas.plan(STATE, settings, expand), ((), ()))

    def test_encoding_keeps_unlisted_keys(self):
        drift, reqs = jas.plan(STATE, {"encoding": {"H264Crf": 20}}, expand)
        self.assertEqual(drift, ("encoding.H264Crf: Jellyfin has 23, declared 20",))
        (method, path, body, _), = reqs
        self.assertEqual((method, path), ("POST", "/System/Configuration/encoding"))
        self.assertEqual(body, {"H264Crf": 20, "HardwareAccelerationType": "none", "Other": 1})

    def test_user_config_posted_by_id(self):
        _, reqs = jas.plan(STATE, {"users": {"u": {"SubtitleMode": "Always"}}}, expand)
        (_, path, body, _), = reqs
        self.assertEqual(path, "/Users/42/Configuration")
        self.assertEqual(body, {"SubtitleMode": "Always", "X": 0})

    def test_unknown_user_skipped(self):
        drift, reqs = jas.plan(STATE, {"users": {"nobody": {"X": 1}}}, expand)
        self.assertEqual(reqs, ())
        self.assertTrue(drift[0].endswith("; skipped"))

    def test_new_library_and_path_then_one_scan(self):
        settings = {"libraries": {
            "Movies": {"type": "movies", "paths": ["~/Video/Movies", "~/More"]},
            "Music": {"type": "music", "paths": ["~/Music"]}}}
        drift, reqs = jas.plan(STATE, settings, expand)
        self.assertEqual(drift, ("libraries.Movies: lacks path /home/u/More",
                                 "libraries.Music: missing in Jellyfin"))
        self.assertEqual([r[1].split("?")[0] for r in reqs],
                         ["/Library/VirtualFolders/Paths", "/Library/VirtualFolders",
                          "/Library/Refresh"])

    def test_plan_does_not_mutate_state(self):
        before = repr(STATE)
        jas.plan(STATE, {"encoding": {"H264Crf": 1}, "users": {"u": {"X": 2}}}, expand)
        self.assertEqual(repr(STATE), before)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
