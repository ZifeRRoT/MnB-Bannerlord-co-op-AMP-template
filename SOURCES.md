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
of BannerlordCoopServer.exe / the @DS@ CLI. Commands, the ready marker, and the
port pair come from the third-party launcher and have not been confirmed by
running the Workshop binary on Linux. Check exact engine, .NET, and game versions
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

Preparation uses mount-and-blade2-coop.sh, which exits before the game starts.
Startup uses the standard env/xvfb-run/socat/Wine executables in Linux Docker;
no custom scripts are called during startup. Native Windows support was removed
in ConfigVersion 12. Docker is recommended; running directly on a Linux host
without a container has not been tested.
No Python or base64 is used. FetchURL retrieves the helper from main. This URL is
mutable: set a verified commit in UpdateSourceData for reproducibility, or restore
the matching helper version from backup. jq reads the password from JSON, not argv.

The user supplied an installed SubModule.xml with Id=Coop, Version=v0.1.7, and
CoopNightly listed as incompatible. Therefore App.AppSettings.CoopModuleId=Coop.
Pre-start validates the ID rather than editing the mod's XML.

This is a private experimental template. Similarity to AMPTemplates does not
establish CubeCoders acceptance or runtime compatibility with AMP 2.8.
Tests cover synthetic auth/cache data, passwords, Update ordering, staging only
inside a managed server/ directory, save preservation, rejection of an incorrect
module ID, and ensuring Pre-start does not launch the game. Real Steam Guard,
Workshop download, and campaign operation still need verification in Linux/Docker.

The Wine smoke test checks prefix creation, the data path, and stop through the
same env/xvfb-run/socat chain. It checks the mechanism without launching the game.

2026-11-22: native Windows AMP support was discontinued at the user's request.
The PowerShell helper, Windows Update/Pre-start stages, and corresponding tests
were removed. Windows Workshop binaries and ForceDownloadPlatform=Windows remain
because Wine uses them inside the Linux container. This template does not claim
to meet the official AMPTemplates cross-platform requirement.
