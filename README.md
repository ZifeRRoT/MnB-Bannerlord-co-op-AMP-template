# Mount & Blade II: Bannerlord Co-op for AMP

An experimental Generic template for Linux amd64. Docker is recommended.
The Docker setup uses one `cubecoders/ampbase:wine-stable` container with Xvfb,
socat PTY, and Wine. No custom Dockerfile is needed. Bash runs only during
Update and Pre-start, then exits; the startup command does not invoke the helper.
No Python or base64 is used. Native Windows AMP is not supported.

Local shell tests and a Wine smoke test check preparation and console handling
with a test executable. The PR bot also reported a real Linux run that installed
the Workshop build, reached Ready, listened on UDP 4200, applied settings after
restart, and saved the world on a clean stop in about eight seconds. Client
connections and long-term campaign persistence still need verification. This is a
standalone Linux template, not a cross-platform AMPTemplates submission candidate.

## Installation

ADS → Configuration → Instance Deployment → Configuration Repositories → **+**:

```text
ZifeRRoT/MnB-Bannerlord-co-op-AMP-template:main
```

Click Fetch Latest, refresh the browser, and find
**Mount & Blade II: Bannerlord Co-op** under Create Instance.
The Community prefix has been removed.

Docker is recommended. Bash, jq, Wine, wineboot, wineserver, Xvfb, xauth, socat,
and timeout have been checked in the Wine image. Without Docker, install these
dependencies on the Linux host. The template expects Wine at `/usr/bin/wine`,
the Xvfb wrapper at `/usr/bin/xvfb-run`, and socat at `/usr/bin/socat`.
Running directly on a Linux host without a container has not been tested.
The engine includes its own .NET runtime; no separate runtime download is needed.

Template files: `manifest.json`, `mount-and-blade2-coop.kvp`,
`mount-and-blade2-coopconfig.json`, `mount-and-blade2-coopmetaconfig.json`,
`mount-and-blade2-coopports.json`, `mount-and-blade2-coopupdates.json`,
`mount-and-blade2-coopstart.json`, and `mount-and-blade2-coop.sh`.

For local testing, locate your ADS DeploymentTemplates directory using
`ampinstmgr list` and `find /home/amp /opt -type d -name DeploymentTemplates`.
As the ADS owner, copy manifest.json and the mount-and-blade2-coop* files into a
new LOCAL-BannerlordCoop-main subdirectory, add the repository
LOCAL/BannerlordCoop:main, and fetch it. The helper is still downloaded from the
published main branch of this repository.

This standalone repository downloads its helper directly from GitHub so it works
before the AMPTemplates submission is merged. The separate AMPTemplates PR uses
the repository CDN, as required by its review rules.

## Settings

| AMP field | Effect |
| --- | --- |
| Server password | Masked player password; leave empty to disable password protection |
| Campaign save | Save name without an extension: ASCII letters, digits, `_`, `-` |
| Autosave minutes | Autosave interval, 1–1440 minutes |
| Register server in Steam | Sets the steam field; disabled by default, applied after Stop → Start |
| Accept server EULA | Explicit acceptance through DS_ACCEPT_EULA; disabled by default |

Changes take effect on the next **Start**. Server password is the password for
players joining the server. Enter Steam credentials in AMP's Steam login dialog.
There is no Steam username setting: the account is selected from AMP's cache.
If several accounts are cached, the helper checks their tokens without a password
and uses the first reusable account. Legacy settings.json is no longer used.
No engine port, region, or permission arguments are passed at startup.

AMP AutoMap writes settings directly to data/server-config.json, which the server
reads. Apply changes with Stop → Start. The shell helper does not copy old
defaults from settings.json. The password is never passed through argv or the
environment and is not printed by the helper. jq escapes quotes, backslashes,
and Unicode. A masked UI field does not encrypt files on disk; keep backups private.

Register server in Steam enables Steam advertising only when Steam API is
available to the running engine. The SteamCMD cache is used for downloads and
does not create a runtime Steam session. Steam visibility is not guaranteed in a
container with only SteamCMD; actual registration still needs verification.
To disable advertising, clear the checkbox and restart the game. Pre-start
preserves the selected true/false value.

### Accepting the EULA without console input

After Update, read `server/EULA.md` (or EULA.txt) and `server/LICENSE.txt` in
File Manager. If you agree, enable **Accept server EULA** and perform Stop → Start.
AMP passes the server-supported `DS_ACCEPT_EULA=true` variable to Linux/Wine.
The server records acceptance in `data/eula.txt`; the template does not fabricate
that file or send `yes` to stdin. Terms may change after updates: review them
before Start if the option remains enabled.

Clearing the checkbox disables automatic acceptance but does not delete an
existing server-written eula.txt. The PR bot confirmed that, without prior acceptance, the disabled default leaves
Start in Configuring at `Accept the EULA? [y/N]`. Read the terms, then enable the
option or answer the prompt in AMP Console. Local tests check the default and mapping.

## Steam Guard and Update

A Steam account that owns Bannerlord (`261550`) is required. Click Update and
complete Steam login, password, and Guard in AMP's standard dialog.

Update runs four stages:

1. FetchURL downloads the shell helper from this repository's published main branch.
2. Helper init creates data/server-config.json if missing. AutoMap needs this
   file before the game starts. Init preserves an existing file.
3. The standard SteamCMD stage for app 228980 (Common Redistributables) handles
   AMP authentication. It may download Windows redistributables, not the full game.
4. The helper downloads Workshop item 3770450698 through the same SteamCMD, then
   copies DedicatedServer into the physical `server/` directory. Stdin is closed,
   NoPromptForPassword=1, and the timeout is two hours.

The SteamCMD cache is expected at `../.virtualhome/Steam/config/config.vdf`.
This path comes from the upstream Project Reclaimer template; confirm that it
matches your AMP installation. Enter passwords and Guard codes in AMP's dialog.

The separate `server/` copy provides a stable executable and WorkingDir without a
dynamic shell launcher. It requires roughly one additional dedicated build's
worth of space beyond the Workshop copy (the observed Workshop download was
about 6.5 GB). Allow space for both copies, the Wine prefix, and backups before
Update. The helper clears only the managed `server/` directory marked with
`.amp-coop-managed`; it does not clear data/. A completed copy receives an
`.amp-coop-ready` marker. Pre-start refuses to proceed without it, preventing an
interrupted Update from launching a partially copied engine.

This follows the Login/Workshop Download pattern in halo3-project-reclaimer.
If Guard is already OK but the console remains at `app_update 228980 validate`,
the SteamCMD stage is still running; the helper's Co-op download has not started.
If progress stalls, check Steam's content_log.txt. If no reusable cache exists,
retry Update and complete Guard in AMP's dialog.

Update checks for download success confirmation and the bundled engine/.NET
files. Start does not update the game automatically. Main and Workshop content
are mutable: use a verified revision and keep backups. The shell helper must be published
in this repository's main branch so FetchURL can retrieve it. Template generation is no
longer required.

## Upgrading an existing template

1. Stop the game normally and create a backup.
2. After publishing the changes: ADS → Instance Deployment → **Fetch Latest**.
3. Right-click the Co-op instance tile → **Refresh Configuration**.
4. Review the fields and set **Server password** before Start. An empty field
   opens the server and replaces any password previously entered manually in JSON.
5. Run Update, then Stop → Start. Check saveName and autosaveMinutes in
   data/server-config.json after Start. Do not publish the password.

The current template maps metaconfig to
data/server-config.json. Update alone does not change this mapping: Refresh
Configuration first. If the instance's active metaconfig.json still contains
ConfigFile=settings.json, it uses the old mapping.

AppConfigId is preserved. Because template files were renamed, some ADS builds
may fail to locate the old ConfigRoot during Refresh. If that happens, keep the
instance and check its template association. This migration has not been verified
in a real AMP deployment. You can change an existing instance's friendly name
separately.

The data directory remains **bannerlord-coop/**: saves, the Wine prefix, and the
cache are not moved. The new AMPTemplates submission starts at ConfigVersion 1,
independently of earlier private-template versions. Linux remains the only runtime
platform and Docker is recommended. Refresh existing private instances manually;
the reset version is not an automatic upgrade signal.
Refresh Configuration on an existing Linux instance. A native Windows instance
cannot become a Linux instance through this change: create a separate Linux/Docker
instance and import the campaign while the game is stopped.
Run Update after Refresh to create `server/` before Start.
The new KVP does not use the old runtime.py.

The user-provided installed module ID is `Coop`, version `v0.1.7`. It is set in
the internal `App.AppSettings.CoopModuleId`, not exposed as a UI field. Pre-start
compares it with the staged SubModule.xml and stops on a mismatch. A different
build requires a verified change to this template value. The helper does not
silently rename CoopNightly to Coop or modify the mod's files.

## Ports and console

| Allocation | Purpose |
| --- | --- |
| UDP 4200 | Co-op player connection port; the only published allocation |

AMP passes the allocated GamePort to the shell helper. A second instance needs
its own player port. The PR bot observed only UDP 4200 listening, so the previous
4201 and 7210 external allocations have been removed. No TCP allocation is added.

The entire `/dedicatedcustomserver 7210 EU 0` block has been removed. Direct tests
of the installed Coop v0.1.7 / Bannerlord v1.4.8 build reached Ready, listened on
UDP 4200, saved the world, and exited cleanly without this block. Removing only
some of its positional values failed with engine exit code 82. No internal
engine port setting or corresponding Pre-start validation remains. The player
port is read from data/server-config.json.

Ready marker: `coop server up, waiting for clients`. Expected commands include
help, status, players, save, and stop; check help/@DS@ in the installed build.
AMP Stop sends stop and is configured to wait 180 seconds. The PR bot observed a world save
and clean exit in about eight seconds on Linux. Force Stop does not guarantee a save.

SteamCMD output is passed through without ANSI filtering. AMP's console may
show color/cursor escape codes as characters; these alone do not indicate a
login or download failure.

Pre-start validates configuration, ports, and module ID, creates a missing save,
initializes the Wine prefix, then returns control to AMP.
Linux startup uses the standard chain
`env → xvfb-run → socat EXEC → Wine → bundled dotnet.exe`.
The command executed under Wine, from WorkingDir, is:

```text
../../dotnet/dotnet.exe TaleWorlds.Starter.DotNetCore.dll "_MODULES_*Native*SandBoxCore*Sandbox*Coop*DedicatedServer.Windows*_MODULES_"
```

socat provides a PTY with echo=0 and inlcr; EXEC does not use a shell for the
engine. Startup does not call our .sh helper. The password is absent from the
command line.

The physical WorkingDir is `server/engine/bin/Win64_Shipping_Server`.
The standard env executable sets BANNERLORD_USER_DIR, COOP_DATA_DIR, and DOTNET_ROOT
to absolute Wine paths Z:/… before launching Xvfb. This does not depend on cwd
changes inside the game. Windows engine binaries remain necessary for Wine.
MonitorChildProcessName matches dotnet, the Starter DLL, and the Co-op module token.
Additional Workshop mods are not supported yet.

## Data and backups

| Path relative to the instance root | Contents |
| --- | --- |
| bannerlord-coop/data/Game Saves/ | .sav saves and matching .json files |
| bannerlord-coop/data/logs/ | Mod logs |
| bannerlord-coop/data/server-config.json | AMP settings and game configuration, including the password |
| bannerlord-coop/server/ | Managed executable/engine copy, replaced by Update |
| bannerlord-coop/.wine/ | Wine prefix |
| .virtualhome/Steam/ | Private Linux Steam cache and possible Workshop files |
| bannerlord-coop/workshop/ | Newly downloaded Workshop files |
| bannerlord-coop/steam/ | Legacy location, if used by an earlier installation |

To import a campaign, stop the game, copy both the .sav and matching .json into
Game Saves, and enter the save name without an extension. Existing saves are not
overwritten by seeding. The helper preserves unknown fields in server-config.json;
use JSON without comments. Invalid JSON causes an error without erasing the original.

After Stop, as the instance owner:

```bash
read -r -p 'Absolute Co-op AMP instance directory: ' INSTANCE_DIR
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
BACKUP_FILE="$HOME/bannerlord-coop-$(date +%Y%m%d-%H%M%S).tar.gz"
umask 077
tar -C "$INSTANCE_DIR" -czf "$BACKUP_FILE" bannerlord-coop .virtualhome
```

The archive contains tokens and passwords. To roll back, stop the game and its
instance in ADS, move the current directories to new sibling locations, and
restore a verified backup:

```bash
test -d "$INSTANCE_DIR/bannerlord-coop" || exit 1
read -r -p 'Absolute backup archive path: ' BACKUP_FILE
test -f "$BACKUP_FILE" || exit 1
tar -tzf "$BACKUP_FILE" # Inspect your archive before restoring it.
mv "$INSTANCE_DIR/bannerlord-coop" "$INSTANCE_DIR/bannerlord-coop.before-rollback-$(date +%Y%m%d-%H%M%S)"
if [ -d "$INSTANCE_DIR/.virtualhome" ]; then
  mv "$INSTANCE_DIR/.virtualhome" "$INSTANCE_DIR/.virtualhome.before-rollback-$(date +%Y%m%d-%H%M%S)"
fi
tar -xzf "$BACKUP_FILE" -C "$INSTANCE_DIR"
```

Restore the helper, template, engine, and data from matching revisions together.

## Validation

Local requirements: Bash, jq, awk, and standard Unix tools.

```bash
bash tests/test_shell.sh
```

From the repository root on Linux with Docker:

```bash
docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
  --mount "type=bind,source=$PWD,target=/work,readonly" -w /work \
  cubecoders/ampbase:wine-stable tests/test_shell.sh

docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
  --mount "type=bind,source=$PWD,target=/work,readonly" -w /work \
  cubecoders/ampbase:wine-stable tests/container_smoke.sh
```

Tests cover password/JSON handling, synthetic cache data, ports, staging, save
preservation, and ensuring Pre-start returns without launching the game. The
Wine smoke test runs Windows cmd through the same xvfb-run/socat chain and checks
the data path and stop input. It does not launch the game.

The PR bot reported successful Workshop installation (about 6.5 GB), Ready,
UDP 4200 listening, a world save on clean Stop, and password/save name/autosave/
Steam flag changes in data/server-config.json after restart. Its test replaced
the helper URL with the repository CDN URL; the AMPTemplates PR uses that URL.
This standalone repository uses its own GitHub raw URL and does not depend on
the helper being published on the AMPTemplates CDN.
The report covers the tested build before allocation cleanup. Subsequent local
tests ran the actual installed build without the engine argument block in a
Linux Docker volume on Windows: Ready, UDP 4200, shutdown save, and exit code 0
all passed with Steam advertising disabled. These direct engine tests do not
replace an AMP deployment and monitoring test of this final template revision.

The following still need verification in Linux/Docker:

- The AMPTemplates PR's Update works once its helper is published on the repository CDN.
- A real client can connect and incorrect passwords are rejected.
- The game uses the configured values; Steam advertising actually works.
- Console accepts help/status/save; AMP monitoring and lifecycle checks pass
  with the final simplified template.
- Restart restores progress and characters; recreating the container with the
  same bind mount preserves data.
- CPU/RAM and monitoring belong to the correct instance; a second instance has
  no port or file conflicts.

Until these checks are complete, treat this template as a draft. Matching the
structure and passing tests do not imply acceptance by CubeCoders.
