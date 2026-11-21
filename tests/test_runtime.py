import importlib.util
import json
import base64
from pathlib import Path
import tempfile
import unittest
import shlex
import subprocess
import sys
from unittest.mock import patch

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
        self.assertEqual(base64.b64decode(encoded), (root / 'runtime.py').read_text(encoding='utf-8').encode('utf-8'))

    def test_update_bootstrap_installs_runtime_in_path_with_spaces(self):
        root = Path(__file__).parents[1]
        stages = json.loads((root / 'bannerlord-coopupdates.json').read_text())
        with tempfile.TemporaryDirectory(prefix='coop test ') as folder:
            args = stages[0]['UpdateSourceArgs'].replace('{{$FullRootDir}}', folder + '/')
            subprocess.run([sys.executable, *shlex.split(args)], check=True)
            self.assertEqual((Path(folder) / 'runtime.py').read_bytes(), (root / 'runtime.py').read_text(encoding='utf-8').encode('utf-8'))


class SteamTests(unittest.TestCase):
    @staticmethod
    def cache(accounts='"owner" { "SteamID" "123" }', token='"ConnectCache" "private-token"'):
        return '"InstallConfigStore" { "Software" { "Valve" { "Steam" { ' + token + \
            ' "Accounts" { ' + accounts + ' } } } } }'

    def test_selects_amp_account_without_exposing_token(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.vdf'
            path.write_text(self.cache())
            self.assertEqual(runtime.cached_account(path), 'owner')

    def test_multiple_accounts_require_selection(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.vdf'
            path.write_text(self.cache('"one" { "SteamID" "1" } "two" { "SteamID" "2" }'))
            with self.assertRaisesRegex(RuntimeError, 'Multiple cached'):
                runtime.cached_account(path)
            self.assertEqual(runtime.cached_account(path, 'TWO'), 'two')
            with self.assertRaisesRegex(RuntimeError, 'not in AMP'):
                runtime.cached_account(path, 'other')

    def test_missing_token_does_not_fall_back_to_password(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.vdf'
            path.write_text(self.cache(token=''))
            with self.assertRaisesRegex(RuntimeError, 'Steam Guard code'):
                runtime.cached_account(path)

    def test_malformed_cache_error_does_not_include_contents(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config.vdf'
            path.write_text('"ConnectCache" "private-token" unexpected')
            with self.assertRaises(ValueError) as caught:
                runtime.cached_account(path)
            self.assertNotIn('private-token', str(caught.exception))

    def test_uses_same_instance_virtualhome_and_native_steamcmd(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'bannerlord-coop'
            root.mkdir()
            (root / 'steamcmd.sh').touch()
            cache = Path(folder) / '.virtualhome/Steam/config/config.vdf'
            cache.parent.mkdir(parents=True)
            cache.write_text(self.cache())
            with patch.object(runtime, 'ROOT', root):
                exe, env, user = runtime.steam()
            self.assertEqual(exe, root / 'steamcmd.sh')
            self.assertEqual(env['HOME'], str(Path(folder) / '.virtualhome'))
            self.assertEqual(user, 'owner')

    def test_old_private_cache_cannot_bypass_amp_authentication(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'bannerlord-coop'
            old_cache = root / 'steam/Steam/config/config.vdf'
            old_cache.parent.mkdir(parents=True)
            old_cache.write_text(self.cache())
            with patch.object(runtime, 'ROOT', root), self.assertRaisesRegex(RuntimeError, 'AMP Steam login'):
                runtime.steam()

    def test_workshop_download_is_noninteractive_and_uses_cached_account(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch.object(runtime, 'ROOT', root), \
                 patch.object(runtime, 'steam', return_value=(root / 'steamcmd.sh', {'HOME': '/instance/.virtualhome'}, 'owner')), \
                 patch.object(runtime, 'game_dir'), patch.object(runtime.subprocess, 'run') as run:
                runtime.download()
            args, kwargs = run.call_args
            self.assertIn('+workshop_download_item', args[0])
            self.assertEqual(args[0][args[0].index('+login') + 1], 'owner')
            self.assertEqual(args[0][args[0].index('+login') + 2], '+workshop_download_item')
            self.assertIn('+@NoPromptForPassword', args[0])
            self.assertEqual(kwargs['stdin'], subprocess.DEVNULL)
            self.assertEqual(kwargs['env']['HOME'], '/instance/.virtualhome')
            self.assertTrue(kwargs['check'])

    def test_new_amp_download_precedes_legacy_game_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'bannerlord-coop'
            suffix = Path('steamapps/workshop/content/261550/3770450698/DedicatedServer')
            for base in (root / 'steam/Steam', root.parent / '.virtualhome/Steam'):
                exe = base / suffix / 'engine/dotnet/dotnet.exe'
                exe.parent.mkdir(parents=True)
                exe.touch()
            with patch.object(runtime, 'ROOT', root):
                self.assertEqual(runtime.game_dir(), root.parent / '.virtualhome/Steam' / suffix)

    def test_update_stage_authenticates_before_downloading_workshop(self):
        root = Path(__file__).parents[1]
        stages = json.loads((root / 'bannerlord-coopupdates.json').read_text())
        self.assertEqual(stages[1]['UpdateSource'], 'SteamCMD')
        self.assertEqual(stages[1]['UpdateSourceData'], '228980')
        self.assertFalse(stages[1]['SkipOnFailure'])
        self.assertTrue(stages[2]['UpdateSourceArgs'].endswith(' update'))
        kvp = (root / 'bannerlord-coop.kvp').read_text()
        self.assertIn('App.SteamForceLoginPrompt=True', kvp)
        self.assertIn('App.SteamUpdateAnonymousLogin=False', kvp)


if __name__ == "__main__":
    unittest.main()
