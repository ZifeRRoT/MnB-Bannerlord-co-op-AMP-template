#!/usr/bin/env python3
"""Private AMP runtime. No credentials are accepted on the command line."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
APP = "261550"
ITEM = "3770450698"


def read_settings():
    path = ROOT / "settings.json"
    if not path.exists():
        path.write_text(json.dumps({"steam_username": "", "saveName": "saveauto1",
                                    "autosaveMinutes": 5, "region": "EU"}, indent=2))
        path.chmod(0o600)
    return json.loads(path.read_text())


def parse_vdf(text):
    """Read Steam's text KeyValues without printing or copying authentication data."""
    tokens = []
    pattern = re.compile(r'\s+|//[^\n]*|"((?:\\.|[^"\\])*)"|([{}])')
    position = 0
    while position < len(text):
        match = pattern.match(text, position)
        if not match:
            raise ValueError("Cannot read AMP Steam cache format; authenticate again through AMP Update")
        position = match.end()
        if match.group(1) is not None:
            tokens.append(("text", re.sub(r'\\(["\\])', r'\1', match.group(1))))
        elif match.group(2):
            tokens.append((match.group(2), None))
    index = 0
    def block(nested=False):
        nonlocal index
        result = {}
        while index < len(tokens):
            kind, key = tokens[index]
            index += 1
            if kind == "}" and nested:
                return result
            if kind != "text" or index >= len(tokens):
                raise ValueError("Invalid AMP Steam cache structure")
            kind, value = tokens[index]
            index += 1
            if kind == "{":
                value = block(True)
            elif kind != "text":
                raise ValueError("Invalid AMP Steam cache structure")
            result[key.casefold()] = value
        if nested:
            raise ValueError("Incomplete AMP Steam cache structure")
        return result
    return block()


def cached_account(cache, selected=""):
    accounts = set()
    has_cache = False
    def visit(node):
        nonlocal has_cache
        for key, value in node.items():
            if key == "connectcache" and value:
                has_cache = True
            if key == "accounts" and isinstance(value, dict):
                accounts.update(name for name, details in value.items()
                                if isinstance(details, dict) and details.get("steamid")
                                and re.fullmatch(r"[a-z0-9_]{1,64}", name))
            if isinstance(value, dict):
                visit(value)
    try:
        contents = cache.read_text(encoding="utf-8-sig")
    except UnicodeError:
        raise RuntimeError("Cannot decode AMP Steam cache; authenticate again through AMP Update") from None
    visit(parse_vdf(contents))
    if not accounts or not has_cache:
        raise RuntimeError("No reusable AMP Steam login. Run Update and enter the Steam Guard code in AMP")
    if selected:
        if not isinstance(selected, str) or selected.casefold() not in accounts:
            raise RuntimeError("Selected Steam username is not in AMP's cache; clear it or authenticate that account in AMP")
        return selected.casefold()
    if len(accounts) != 1:
        raise RuntimeError("Multiple cached Steam accounts; select Steam username in Co-op settings")
    return next(iter(accounts))


def steam():
    # Matches the Linux Workshop stage in upstream halo3-project-reclaimer.
    # Do not fall back to another instance's cache or the host user's HOME.
    home = ROOT.parent / ".virtualhome"
    exe = ROOT / "steamcmd.sh"
    cache = home / "Steam/config/config.vdf"
    if not exe.is_file() or not cache.is_file():
        raise RuntimeError("AMP Steam login is missing. Run Update and complete its Steam login dialog")
    user = cached_account(cache, read_settings().get("steam_username", ""))
    return exe, dict(os.environ, HOME=str(home)), user


def game_dir():
    suffix = Path("steamapps/workshop/content") / APP / ITEM / "DedicatedServer"
    for base in (ROOT / "workshop", ROOT.parent / ".virtualhome/Steam",
                 ROOT / "steam/Steam", ROOT / "steam", ROOT):
        game = base / suffix
        if (game / "engine/dotnet/dotnet.exe").is_file():
            return game
    raise RuntimeError("Workshop DedicatedServer missing. Authenticate, then run AMP Update.")


def download():
    exe, env, user = steam()
    args = ["+@NoPromptForPassword", "1", "+@sSteamCmdForcePlatformType", "windows",
            "+force_install_dir", str(ROOT / "workshop"), "+login", user,
            "+workshop_download_item", APP, ITEM, "validate", "+quit"]
    subprocess.run(["/bin/bash", str(exe), *args], env=env, check=True, cwd=exe.parent,
                   stdin=subprocess.DEVNULL, timeout=7200)
    game_dir()
    print("[coop] Update finished; Workshop versions are mutable. Back up before updating.", flush=True)


def port(value, maximum=65535):
    if not re.fullmatch(r"[1-9][0-9]{0,4}", str(value)) or not 1 <= int(value) <= maximum:
        raise ValueError("Invalid allocated port")
    return int(value)


def prepare_config(data, settings, game_port):
    name = settings.get("saveName", "saveauto1")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", name):
        raise ValueError("saveName must contain only letters, digits, _ or -")
    minutes = settings.get("autosaveMinutes", 5)
    if type(minutes) is not int or not 1 <= minutes <= 1440:
        raise ValueError("autosaveMinutes must be 1..1440")
    path = data / "server-config.json"
    # Keep unknown settings; fail on JSONC rather than silently discarding edits.
    config = json.loads(path.read_text()) if path.exists() else {"password": ""}
    config.update(port=port(game_port, 65534), saveName=name,
                  autosaveMinutes=minutes, logFile=True, steam=False)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(config, ensure_ascii=False, indent=2))
    temporary.chmod(0o600)
    temporary.replace(path)
    return name


def start(game_port, engine_port):
    game_port, engine_port = port(game_port, 65534), port(engine_port)
    if engine_port in (game_port, game_port + 1):
        raise ValueError("Engine port overlaps Co-op ports")
    for binary in ("wine", "wineboot", "winepath", "xvfb-run", "script"):
        if not shutil.which(binary):
            raise RuntimeError(f"Missing container dependency: {binary}")
    game = game_dir()
    settings = read_settings()
    region = settings.get("region", "EU")
    if not re.fullmatch(r"[A-Z]{2,8}", region):
        raise ValueError("Invalid region")
    data = ROOT / "data"
    data.mkdir(exist_ok=True, mode=0o700)
    name = prepare_config(data, settings, game_port)
    saves = data / "Game Saves"
    saves.mkdir(exist_ok=True)
    if not (saves / f"{name}.sav").exists():
        shutil.copy2(game / "server-data/Game Saves/default_new_game.sav", saves / f"{name}.sav")
    # The engine bundles .NET. Wine Mono/Gecko are unnecessary and their installer
    # dialogs can block unattended prefix initialization under Xvfb.
    env = dict(os.environ, WINEPREFIX=str(ROOT / ".wine"), WINEARCH="win64",
               WINEDEBUG="-all", WINEDLLOVERRIDES="mscoree,mshtml=")
    if not (ROOT / ".wine/system.reg").exists():
        try:
            subprocess.run(["xvfb-run", "-a", "wineboot", "-i"], env=env, check=True, timeout=180)
            # Wine may keep registry changes in wineserver until it exits.
            subprocess.run(["wineserver", "-k"], env=env, check=True, timeout=15)
            subprocess.run(["wineserver", "-w"], env=env, check=True, timeout=15)
        except (subprocess.SubprocessError, OSError):
            subprocess.run(["wineserver", "-k"], env=env, check=False)
            raise
        if not (ROOT / ".wine/system.reg").exists():
            raise RuntimeError("Wine prefix initialization did not produce system.reg")
    def windows(path):
        # All instance paths are absolute Unix paths on Wine's standard Z: drive.
        # Avoid starting wineserver on a temporary DISPLAY merely to map a path.
        return "Z:" + str(path.resolve()).replace("/", "\\")
    env.update(BANNERLORD_USER_DIR=windows(data), COOP_DATA_DIR=windows(data),
               DOTNET_ROOT=windows(game / "engine/dotnet"), DOTNET_MULTILEVEL_LOOKUP="0")
    xml = ET.parse(game / "engine/Modules/Coop/SubModule.xml")
    mid = xml.find("Id").get("value")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", mid):
        raise ValueError("Invalid Coop module id")
    modules = f"_MODULES_*Native*SandBoxCore*Sandbox*{mid}*DedicatedServer.Windows*_MODULES_"
    command = ["wine", str(game / "engine/dotnet/dotnet.exe"), "TaleWorlds.Starter.DotNetCore.dll",
               modules, "/dedicatedcustomserver", str(engine_port), region, "0"]
    os.chdir(game / "engine/bin/Win64_Shipping_Server")
    # script provides a real PTY to Wine. Disable echo so commands are not repeated.
    # --return propagates game exit status; exec keeps AMP attached throughout.
    os.execvpe("xvfb-run", ["xvfb-run", "-a", "script", "--quiet", "--return",
                          "--command", "stty -echo inlcr; exec " + shlex.join(command), "/dev/null"], env)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        action = sys.argv[1] if len(sys.argv) > 1 else ""
        if action == "update":
            download()
        elif action == "login":
            raise RuntimeError("Steam login is now managed by AMP. Click Update and use its Steam login dialog")
        elif action == "init":
            read_settings()
        elif action == "start" and len(sys.argv) == 4:
            start(*sys.argv[2:])
        else:
            raise ValueError("Usage: runtime.py init|login|update|start GAME_PORT ENGINE_PORT")
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError, ET.ParseError) as exc:
        print(f"[coop] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
