import importlib.util
import json
import base64
from pathlib import Path
import tempfile
import unittest
import shlex
import subprocess
import sys

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).parents[1] / "runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class ConfigTests(unittest.TestCase):
    def test_preserve_password_and_unknown_options(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            password = 'a"b\\c,} Unicode: Привіт'
            (root / "server-config.json").write_text(json.dumps({"password": password, "future": 42}))
            runtime.prepare_config(root, {"saveName": "campaign-1", "autosaveMinutes": 5}, 4300)
            result = json.loads((root / "server-config.json").read_text())
            self.assertEqual(result["password"], password)
            self.assertEqual(result["future"], 42)
            self.assertEqual(result["port"], 4300)

    def test_bad_save_name_cannot_escape_data_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                runtime.prepare_config(Path(folder), {"saveName": "../../escape"}, 4200)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_invalid_ports(self):
        for value in (0, "04200", "4200; touch bad", 65535, -1, "9" * 50):
            with self.subTest(value=value), self.assertRaises(ValueError):
                runtime.port(value, 65534)

    def test_invalid_existing_config_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "server-config.json"
            path.write_text('{"password":"secret", // comment\n}')
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                runtime.prepare_config(Path(folder), {}, 4200)
            self.assertEqual(path.read_bytes(), before)

    def test_amp_include_files_and_port_offset(self):
        root = Path(__file__).parents[1]
        kvp = (root / "bannerlord-coop.kvp").read_text()
        for filename in ("bannerlord-coopports.json", "bannerlord-coopupdates.json",
                         "bannerlord-coopconfig.json", "bannerlord-coopmetaconfig.json", "manifest.json"):
            json.loads((root / filename).read_text())
        ports = json.loads((root / "bannerlord-coopports.json").read_text())
        self.assertEqual(ports[0]["ChildPorts"][0]["Offset"], 1)
        self.assertIn("App.ExitMethod=String", kvp)
        self.assertIn("App.ExitString=stop", kvp)

    def test_embedded_runtime_matches_reviewable_source(self):
        root = Path(__file__).parents[1]
        stages = json.loads((root / 'bannerlord-coopupdates.json').read_text())
        encoded = stages[0]['UpdateSourceArgs'].split("b64decode('")[1].split("')")[0]
        self.assertEqual(base64.b64decode(encoded), (root / 'runtime.py').read_bytes())

    def test_update_bootstrap_installs_runtime_in_path_with_spaces(self):
        root = Path(__file__).parents[1]
        stages = json.loads((root / 'bannerlord-coopupdates.json').read_text())
        with tempfile.TemporaryDirectory(prefix='coop test ') as folder:
            args = stages[0]['UpdateSourceArgs'].replace('{{$FullRootDir}}', folder + '/')
            subprocess.run([sys.executable, *shlex.split(args)], check=True)
            self.assertEqual((Path(folder) / 'runtime.py').read_bytes(), (root / 'runtime.py').read_bytes())


if __name__ == "__main__":
    unittest.main()
