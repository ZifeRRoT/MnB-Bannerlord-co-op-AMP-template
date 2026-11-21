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
import tarfile
import urllib.request
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


def steam():
    home = ROOT / "steam"
    home.mkdir(exist_ok=True, mode=0o700)
    exe = home / "steamcmd.sh"
    if not exe.exists():
        archive = home / "steamcmd.tar.gz"
        urllib.request.urlretrieve(
            "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz", archive)
        with tarfile.open(archive) as data:
            # Steam's bootstrap contains only regular files/directories. Reject links
            # and traversal, including future archive changes.
            for member in data.getmembers():
                target = (home / member.name).resolve()
                if not target.is_relative_to(home.resolve()) or not (member.isfile() or member.isdir()):
                    raise ValueError("Unsafe Steam bootstrap archive")
            data.extractall(home)
        archive.unlink()
    return exe, dict(os.environ, HOME=str(home))


def game_dir():
    suffix = Path("steamapps/workshop/content") / APP / ITEM / "DedicatedServer"
    for base in (ROOT / "steam/Steam", ROOT / "steam"):
        game = base / suffix
        if (game / "engine/dotnet/dotnet.exe").is_file():
            return game
    raise RuntimeError("Workshop DedicatedServer missing. Authenticate, then run AMP Update.")


def download(login=False):
    settings = read_settings()
    user = settings.get("steam_username", "")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,64}", user):
        raise ValueError("Set steam_username in private settings.json first")
    exe, env = steam()
    if login:
        if not sys.stdin.isatty():
            raise RuntimeError("Login requires docker exec -it terminal, never AMP console")
        args = ["+login", user, "+quit"]
    else:
        args = ["+@NoPromptForPassword", "1", "+login", user,
                "+workshop_download_item", APP, ITEM, "validate", "+quit"]
    subprocess.run(["/bin/bash", str(exe), *args], env=env, check=True, cwd=exe.parent)
    if not login:
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
        if action in ("login", "update"):
            download(action == "login")
        elif action == "init":
            read_settings()
        elif action == "start" and len(sys.argv) == 4:
            start(*sys.argv[2:])
        else:
            raise ValueError("Usage: runtime.py init|login|update|start GAME_PORT ENGINE_PORT")
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError, ET.ParseError) as exc:
        print(f"[coop] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
