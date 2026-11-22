# Sources and verification limits — 2026-11-22

- [AMP Generic wiki](https://github.com/CubeCoders/AMP/wiki/Configuring-the-%27Generic%27-AMP-module): manifest, Git/LOCAL repositories, Executable update stages, STDIO/ExitMethod.
- [AMP custom images](https://github.com/CubeCoders/AMP/wiki/Using-custom-Docker-images-with-AMP-and-the-generic-module): base image and the `/AMP` bind mount.
- [AMPTemplates](https://github.com/CubeCoders/AMPTemplates/tree/5b57587ab959a89b34aea48a1c508295a9ce081f): compared skyrim-together-reborn, abiotic-factor, conan-exiles, and arma3 for Wine, SteamCMD, String stop, and ChildPorts.Offset.
- [Submission rules](https://github.com/CubeCoders/AMPTemplates#readme): verify the application lifecycle on Windows and Linux before submission; custom scripts are allowed for Update/Pre-start, not startup. The upstream halo3-project-reclaimer uses xvfb-run as a standard Linux compatibility wrapper and includes a Windows branch.
- EULA automation: [server-manager lib/license.sh](https://github.com/PlodyIce/bannerlordcoop-server-manager/blob/ac80c8a079de91f4291e2045fd7a573dea565d26/lib/license.sh) and docs/ARCHITECTURE.md describe server-side DS_ACCEPT_EULA=true and engine-written eula.txt since Coop v0.1.6. This is a third-party source; the mechanism has not been verified here against the real build. The AMP option defaults to false and does not generate an acceptance file itself.
- At the same AMPTemplates revision, `halo3-project-reclaimerupdates.json` has a Linux Workshop Login stage using `SteamCMD`, app `228980`, and the Windows download platform, followed by an Executable download using `$FullRootDir/steamcmd.sh` and `../.virtualhome/Steam/config/config.vdf`. Its KVP sets SteamUpdateAnonymousLogin=False and SteamForceLoginPrompt=True. This template follows that pattern without downloading the full game.
- [Steam login in AMP](https://discourse.cubecoders.com/t/why-is-amp-asking-for-my-steam-login-details/2310): standard login dialog and SteamCMD cache; AMP does not log credentials.
- [Updating an existing instance's configuration](https://discourse.cubecoders.com/t/satisfactory-template-update/4998): Fetch Latest → Refresh Configuration → Update.
- [Third-party dedicated launcher](https://github.com/geofmigliacci/egg-bannerlord-coop/tree/aac59029ba1e25c544df68b8780da03e784ffea9): .NET engine invocation, Workshop layout, ports, save seeding, TTY, commands/ready marker. This is not an official AMP component. Its code is not included; the helper was written in this repository.
- [Official Co-op repository](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/tree/81827688001aca48a15b925bd92aece227b219c7): README links to Workshop 3770450698; deploy/Server Instructions.md requires matching versions and keeping .sav together with .json; doc/ServerDataLocations.md describes BANNERLORD_USER_DIR/COOP_DATA_DIR.
- Steam advertising: the server-config steam field appears in the third-party dedicated launcher. [Server-manager configuration](https://github.com/PlodyIce/bannerlordcoop-server-manager/blob/main/docs/CONFIGURATION.md) describes STEAM_ADVERTISE as runtime server advertising. At the inspected revision, the official source/Coop.Core/Server/ServerModule.cs registers a Steam advertiser only when SessionDiscovery.SteamAvailable is true; otherwise it uses NoopSessionAdvertiser. A SteamCMD cache does not prove that runtime Steam API is available. The UI switch sets steam=true/false; actual Steam visibility has not been verified.

The official repository's public code does not contain the current implementation
of BannerlordCoopServer.exe / the @DS@ CLI. Commands and the original port pair came from the third-party launcher.
The PR bot has since confirmed the ready marker and graceful stop on Linux,
with only UDP 4200 listening; unused external port allocations were removed. Check exact engine, .NET, and game versions
in release-info.txt after downloading with an entitled account.

The registry returned this linux/amd64 manifest:
`sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Downloaded index digest:
`sha256:d3fd4f741da84e7be0d74ce59b153047d6eaea187459c934ffe4a9c3a07bc76b`.
Wine 11.0, jq, xvfb-run, xauth, socat, wineboot, and wineserver were checked in a
running cubecoders/ampbase:wine-stable container. SteamCMD is not on PATH;
its installation and authentication are handled by AMP's standard SteamCMD stage.

The image tag is mutable. To reproduce the inspected image, set
Meta.SpecificDockerImage to
`cubecoders/ampbase@sha256:82460488879b929eb6c08a53352647503ea80634227500a8971cef0d30b898cb`.
Workshop content and the SteamCMD bootstrap are also mutable; keep a local backup
for rollback.

Preparation uses mount-and-blade2-coop.sh and returns to AMP before startup.
The private template now also calls its start action to run the standard
env/xvfb-run/socat/Wine executables and translate player telemetry for AMP.
Native Windows support was removed
during private-template development; the new upstream submission starts at ConfigVersion 1. Docker is recommended; running directly on a Linux host
without a container has not been tested.
No Python or base64 is used. This standalone repository retrieves its helper from
its published GitHub main branch. The separate AMPTemplates PR uses the repository
CDN as required by review. Both sources are mutable; restore the matching helper from backup
when reproducing an older deployment. jq reads the password from JSON, not argv.

The user supplied an installed SubModule.xml with Id=Coop, Version=v0.1.7, and
CoopNightly listed as incompatible. Therefore App.AppSettings.CoopModuleId=Coop.
Pre-start validates the ID rather than editing the mod's XML.

This is a private experimental template. Similarity to AMPTemplates does not
establish CubeCoders acceptance or runtime compatibility with AMP 2.8.
Tests cover synthetic auth/cache data, passwords, Update ordering, staging only
inside a managed server/ directory, save preservation, rejection of an incorrect
module ID, and ensuring Pre-start does not launch the game. The user-provided PR bot report confirms real Linux Workshop installation, Ready,
UDP 4200, restart-time configuration mapping, and a world save on clean stop.
Client connections, password enforcement, and long-term persistence remain unverified.

The Wine smoke test checks prefix creation, the data path, and stop through the
same env/xvfb-run/socat chain. It checks the mechanism without launching the game.

2026-11-22: native Windows AMP support was discontinued at the user's request.
The PowerShell helper, Windows Update/Pre-start stages, and corresponding tests
were removed. Windows Workshop binaries and ForceDownloadPlatform=Windows remain
because Wine uses them inside the Linux container. This template does not claim
to meet the official AMPTemplates cross-platform requirement.

## PR review follow-up

The user supplied an amp-template-bot report: after switching the helper to
`https://cdn-repo.c7rs.com/AMPTemplates/mount-and-blade2-coop.sh`, a Linux test
installed about 6.5 GB, reached `coop server up`, listened on UDP 4200, and saved
the world before exiting cleanly in about eight seconds. Password, save name,
autosave, and Steam flag changes appeared in data/server-config.json after restart.
Windows was skipped because Meta.OS is Linux. Without previous EULA acceptance,
the default-disabled acceptance option leaves Start waiting at the console prompt.

The AMPTemplates PR applies the CDN URL, repository field order, initial ConfigVersion 1,
release notes, EULA description, and environment cleanup. Only GamePort remains
externally allocated. An internal CoopEnginePort setting was initially retained,
then removed after the direct engine tests below. The final template still needs
an AMP bot rerun.

## Direct engine argument tests

The installed Workshop build (2026-10-30, Bannerlord v1.4.8, Coop v0.1.7) was
tested under Wine 11.0 in a Linux Docker volume on Windows with independent
test campaigns and Steam advertising disabled. The user explicitly authorized
EULA acceptance for these tests. All ten cases retained the same Starter DLL
and module token.

The full `/dedicatedcustomserver 7210 EU 0` block, `/dedicatedcustomserver 0 EU 0`,
and omission of the entire block each reached Ready, listened on UDP 4200,
saved the campaign, and exited with code 0 after stop. All seven partially
specified forms failed with engine exit code 82. Inspection of the installed
engine parser confirmed positional ServerPort, ServerRegion, and Permission
values after the flag; omission of the whole flag avoids that parsing branch.

The template therefore omits the whole block and removes its internal port
setting, Pre-start argument, and port-overlap checks. Monitoring now matches
the Starter DLL and Co-op module token. Client connections, Steam advertising,
and AMP process monitoring after this change remain unverified. The actual
game tests required a Linux filesystem in this environment; control launches
directly from Windows bind mounts failed before normal startup.

## AMP player tracking

The user supplied real first-character, disconnect, and reconnect logs. Player
snapshots are `@DS@` JSON with ev=players and list entries containing peer id,
name, state, and address. Names first appear during loading; a reconnect receives
a new peer ID. Explicit disconnect lines identify only the peer, and the next
snapshot removes it from the list.

The installed AMP 2.8.0.10 GenericModule was inspected: UserJoinRegex creates a
SimpleUser from username/userid/endpoint, rejects duplicates by name or ID, and
does not update existing users. UserLeaveRegex can remove users by ID. The
console configuration has no complete-JSON-roster setting. MetricsRegex exposes
named numeric groups as extra metrics, rather than changing the user list.

The private Bash helper now runs a jq stdout bridge that reconciles snapshots
and adds one synthetic line per join/leave. This permits multiple players in a
single snapshot without relying on one regex match to process an entire JSON
array. Original server lines and ANSI codes are preserved. Startup command
input remains connected to socat/Wine; the adapter only processes output.
The public AMPTemplates submission is not modified by this change.
