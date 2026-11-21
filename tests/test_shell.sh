#!/bin/bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$REPO/mount-and-blade2-coop.sh"
WORK=$(mktemp -d /tmp/coop-shell.XXXXXX)
trap 'case "$WORK" in /tmp/coop-shell.*) rm -rf -- "$WORK";; esac' EXIT
ROOT="$WORK/instance with spaces/bannerlord-coop"
mkdir -p "$ROOT"
passed=0
pass() { passed=$((passed+1)); printf 'PASS %s\n' "$1"; }
reject() { if ("$@") >/dev/null 2>&1; then printf 'Expected failure\n' >&2; exit 1; fi; }

bash -n "$REPO/mount-and-blade2-coop.sh"
for path in "$REPO"/*.json; do jq -e . "$path" >/dev/null; done
[[ $(jq -r .prefix "$REPO/manifest.json") == '' ]]
grep -Fx 'Meta.DisplayName=Mount & Blade II: Bannerlord Co-op' "$REPO/mount-and-blade2-coop.kvp" >/dev/null
jq -e 'all(.[]; .FieldName != "steam_username") and
  any(.[]; .FieldName == "ServerPassword" and .InputType == "Password" and .IncludeInCommandLine == false) and
  any(.[]; .FieldName == "SteamAdvertise" and .ParamFieldName == "$.steam" and .InputType == "checkbox" and .DefaultValue == "false")' \
  "$REPO/mount-and-blade2-coopconfig.json" >/dev/null
jq -e 'any(.[]; .UpdateSourcePlatform == "Windows" and .UpdateSourceData == "powershell.exe") and
  any(.[]; .UpdateSourcePlatform == "Linux" and .UpdateSourceData == "/bin/bash") and
  any(.[]; .UpdateSourcePlatform == "All" and .UpdateSource == "SteamCMD" and .UpdateSourceData == "228980")' \
  "$REPO/mount-and-blade2-coopupdates.json" >/dev/null
jq -e '.[0].ConfigFile == "data/server-config.json" and .[0].AutoMap == true' \
  "$REPO/mount-and-blade2-coopmetaconfig.json" >/dev/null
if grep -E 'python|base64' "$REPO/mount-and-blade2-coop.kvp" "$REPO/mount-and-blade2-coopupdates.json"; then exit 1; fi
grep -Fx 'App.ExecutableWin=server\engine\dotnet\dotnet.exe' "$REPO/mount-and-blade2-coop.kvp" >/dev/null
grep -Fx 'App.ExecutableLinux=/usr/bin/env' "$REPO/mount-and-blade2-coop.kvp" >/dev/null
if grep '^App.CommandLineArgs=' "$REPO/mount-and-blade2-coop.kvp" | grep -Eq '\.(sh|ps1|bat)'; then exit 1; fi
pass 'AMP manifests: masked password, no username/Python/base64, requested display name'

cp "$REPO/mount-and-blade2-coop.sh" "$ROOT/mount-and-blade2-coop.sh"
bash "$ROOT/mount-and-blade2-coop.sh" init
prepare_config 4300
jq -e '.port==4300 and .password=="" and .saveName=="saveauto1" and .steam==false' "$ROOT/data/server-config.json" >/dev/null
pass 'first-run configuration'

cat > "$ROOT/data/server-config.json" <<'JSON'
{"saveName":"campaign-1","autosaveMinutes":7,"futureOption":42,"steam":true,"password":"p\"a\\ss,} | & $(touch SHOULD_NOT_EXIST)\nПривіт"}
JSON
cp "$ROOT/data/server-config.json" "$WORK/amp-config.json"
bash "$ROOT/mount-and-blade2-coop.sh" init
cmp "$WORK/amp-config.json" "$ROOT/data/server-config.json"
pass 'Update init creates the AutoMap target and preserves existing AMP settings'
prepare_config 4400
jq -e '.futureOption==42 and .port==4400 and .saveName=="campaign-1" and .autosaveMinutes==7 and .steam==true' "$ROOT/data/server-config.json" >/dev/null
jq -s -e '.[0].password==.[1].password' "$WORK/amp-config.json" "$ROOT/data/server-config.json" >/dev/null
[[ ! -e SHOULD_NOT_EXIST ]]
pass 'password quotes, backslashes, newline, Unicode and shell metacharacters survive JSON merge'

jq '.password="" | .steam=false' "$ROOT/data/server-config.json" > "$WORK/blank.json"
mv "$WORK/blank.json" "$ROOT/data/server-config.json"
prepare_config 4400
jq -e '.password=="" and .steam==false' "$ROOT/data/server-config.json" >/dev/null
pass 'clearing password disables password protection'

printf '{"saveName":"saveauto1","password":"stale","steam_username":"ignored"}\n' > "$ROOT/settings.json"
printf '{"saveName":"dadada","password":"legacy","futureOption":42}\n' > "$ROOT/data/server-config.json"
prepare_config 4400
jq -e '.saveName=="dadada" and .password=="legacy" and .futureOption==42' "$ROOT/data/server-config.json" >/dev/null
pass 'stale legacy settings.json cannot overwrite values AMP wrote to server config'

for invalid in 0 04200 65535 -1 '4200;echo bad'; do reject prepare_config "$invalid"; done
reject prepare 4200 4201 Coop
pass 'invalid/overlapping allocations rejected'

printf '{"saveName":"../../escape"}\n' > "$ROOT/data/server-config.json"
reject prepare_config 4200
printf '{"saveName":"safe","password":123}\n' > "$ROOT/data/server-config.json"
reject prepare_config 4200
printf '{"saveName":"safe","steam":"true"}\n' > "$ROOT/data/server-config.json"
reject prepare_config 4200
pass 'save traversal and non-string password rejected'

printf '{"password":"keep", // comment\n}\n' > "$ROOT/data/server-config.json"
cp "$ROOT/data/server-config.json" "$WORK/original.json"
reject prepare_config 4200
cmp "$WORK/original.json" "$ROOT/data/server-config.json"
pass 'invalid server JSON fails without overwriting original'

mkdir -p "$ROOT/../.virtualhome/Steam/config"
cache="$ROOT/../.virtualhome/Steam/config/config.vdf"
cat > "$cache" <<'VDF'
"InstallConfigStore"
{
  "Software" { "Valve" { "Steam" {
    "ConnectCache" { "irrelevant" "DO_NOT_PRINT_PRIVATE_TOKEN" }
    "Accounts" {
      "OWNER" { "SteamID" "123" }
    }
  } } }
}
VDF
printf '# placeholder\n' > "$ROOT/steamcmd.sh"
[[ $(cached_accounts "$cache") == owner ]]
[[ $(steam_account) == owner ]]
pass 'AMP cache parser handles compact/nested VDF, emits only account name'

sed 's/"OWNER" { "SteamID" "123" }/"stale" { "SteamID" "12" } "OWNER" { "SteamID" "123" }/' \
  "$cache" > "$WORK/multiple.vdf"
cp "$WORK/multiple.vdf" "$cache"
cat > "$ROOT/steamcmd.sh" <<'SH'
#!/bin/bash
[[ "$4" == owner ]] || exit 1
printf "Logging in user 'owner'...\033[0mOK\n"
SH
[[ $(steam_account) == owner ]]
sed 's/"stale" { "SteamID" "12" } //' "$cache" > "$WORK/single.vdf"
cp "$WORK/single.vdf" "$cache"
pass 'multiple AMP accounts use a reusable cached token without username setting'

sed 's/ConnectCache/NotACache/g' "$cache" > "$WORK/no-cache.vdf"
reject cached_accounts "$WORK/no-cache.vdf"
printf '"ConnectCache" "DO_NOT_PRINT_PRIVATE_TOKEN" malformed\n' > "$WORK/bad-cache.vdf"
if cached_accounts "$WORK/bad-cache.vdf" > "$WORK/error.log" 2>&1; then exit 1; fi
if grep -q DO_NOT_PRINT_PRIVATE_TOKEN "$WORK/error.log"; then exit 1; fi
pass 'missing/malformed cache rejected without exposing token'

suffix="steamapps/workshop/content/261550/3770450698/DedicatedServer"
mkdir -p "$ROOT/steam/Steam/$suffix/engine/dotnet" "$ROOT/../.virtualhome/Steam/$suffix/engine/dotnet"
touch "$ROOT/steam/Steam/$suffix/engine/dotnet/dotnet.exe" "$ROOT/../.virtualhome/Steam/$suffix/engine/dotnet/dotnet.exe"
[[ $(game_dir) == "$(cd "$ROOT/../.virtualhome/Steam/$suffix" && pwd -P)" ]]
pass 'new AMP Workshop layout takes precedence over legacy copy'

cat > "$ROOT/steamcmd.sh" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$HOME" == */.virtualhome ]]
[[ "$1" == +@NoPromptForPassword && "$2" == 1 ]]
[[ " $* " == *' +login owner +workshop_download_item 261550 3770450698 validate +quit '* ]]
if read -r -t 1 unexpected; then exit 9; fi
printf '\033[0mSuccess. Downloaded item 3770450698 to workshop\033[0m\n'
printf '\033[33mSteam warning\033[0m\n' >&2
SH
update > "$WORK/update.log"
grep -q 'Workshop update finished' "$WORK/update.log"
grep -Fqx $'\033[33mSteam warning\033[0m' "$WORK/update.log"
pass 'Workshop update uses AMP HOME, cached account and closed stdin'

printf '#!/bin/bash\nprintf "ERROR! Download item failed\\n"\nexit 0\n' > "$ROOT/steamcmd.sh"
reject update
pass 'SteamCMD exit zero without download confirmation does not pass update'

# Preparation must return to AMP rather than launch any game process.
printf '{"saveName":"safe","password":"DO_NOT_LEAK_SERVER_PASSWORD"}\n' > "$ROOT/data/server-config.json"
game=$(game_dir)
mkdir -p "$game/engine/Modules/Coop" "$game/engine/bin/Win64_Shipping_Server" "$ROOT/.wine" "$ROOT/data/Game Saves" "$WORK/bin"
printf '<Module>\n<Id value="Coop" />\n</Module>\n' > "$game/engine/Modules/Coop/SubModule.xml"
printf 'existing progress\n' > "$ROOT/data/Game Saves/safe.sav"
touch "$ROOT/.wine/system.reg"
stage_server
for binary in wine wineboot wineserver socat xvfb-run; do
    # shellcheck disable=SC2016 # The fixture expands COOP_CAPTURE when invoked.
    printf '#!/bin/bash\ntouch "$COOP_CAPTURE"\nexit 99\n' > "$WORK/bin/$binary"
    chmod +x "$WORK/bin/$binary"
done
export COOP_CAPTURE="$WORK/launch-args"
(export PATH="$WORK/bin:$PATH"; prepare 4500 7210 Coop)
[[ ! -f "$COOP_CAPTURE" ]]
grep -q 'existing progress' "$ROOT/data/Game Saves/safe.sav"
jq -e '.password=="DO_NOT_LEAK_SERVER_PASSWORD" and .port==4500' "$ROOT/data/server-config.json" >/dev/null
pass 'Pre-start preserves config/save and returns without launching the game'
reject prepare 4500 7210 CoopNightly
mv "$ROOT/server/.amp-coop-ready" "$WORK/ready-marker"
reject prepare 4500 7210 Coop
mv "$WORK/ready-marker" "$ROOT/server/.amp-coop-ready"
pass 'incompatible module ID or incomplete staging fails before engine launch'

mv "$ROOT/server/.amp-coop-managed" "$WORK/managed-marker"
printf 'do not remove\n' > "$ROOT/server/unmanaged-file"
reject stage_server
test -f "$ROOT/server/unmanaged-file"
mv "$WORK/managed-marker" "$ROOT/server/.amp-coop-managed"
stage_server
[[ ! -e "$ROOT/server/unmanaged-file" ]]
grep -q 'existing progress' "$ROOT/data/Game Saves/safe.sav"
pass 'Update refuses unmanaged server directories and only mirrors disposable application files'
printf 'All %s shell checks passed\n' "$passed"
