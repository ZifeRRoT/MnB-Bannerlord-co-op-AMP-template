#!/bin/bash
# AMP Co-op runtime. Credentials belong to AMP's native SteamCMD dialog.
set +x
set -euo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
APP=261550
ITEM=3770450698

die() { printf '[coop] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[coop] %s\n' "$*"; }

# SteamCMD emits ANSI CSI sequences even when AMP is not a terminal. Keep text,
# Unicode and line breaks; remove only terminal color/cursor control sequences.
strip_ansi() { LC_ALL=C sed -u -E $'s|\033\\[[0-?]*[ -/]*[@-~]||g'; }

settings() {
    if [[ ! -f "$ROOT/settings.json" ]]; then
        printf '%s\n' '{"saveName":"saveauto1","autosaveMinutes":5,"password":""}' > "$ROOT/settings.json"
    fi
    chmod 600 "$ROOT/settings.json"
    jq -e 'type == "object" and
      ((.saveName // "saveauto1") | type == "string" and test("^[A-Za-z0-9_-]{1,80}$")) and
      ((.autosaveMinutes // 5) | type == "number" and floor == . and . >= 1 and . <= 1440) and
      ((has("password") | not) or (.password | type == "string"))' \
      "$ROOT/settings.json" >/dev/null || die 'Invalid settings.json; check save name, autosave and password type'
}

check_port() {
    if [[ ! "$1" =~ ^[1-9][0-9]{0,4}$ ]] || (( 10#$1 > ${2:-65535} )); then
        die 'Invalid allocated port'
    fi
}

game_dir() {
    local base suffix="steamapps/workshop/content/$APP/$ITEM/DedicatedServer"
    for base in "$ROOT/workshop" "$ROOT/../.virtualhome/Steam" "$ROOT/steam/Steam" "$ROOT/steam" "$ROOT"; do
        if [[ -f "$base/$suffix/engine/dotnet/dotnet.exe" ]]; then
            (cd -- "$base/$suffix" && pwd -P)
            return
        fi
    done
    die 'Workshop DedicatedServer missing; run AMP Update'
}

cached_accounts() {
    # Tokenize quoted KeyValues, tracking the Accounts object instead of grepping
    # nearby lines. Only account names leave awk; cache/token values never do.
    awk '
    function token(kind, val, lower) {
      if (kind == "}") {
        if (key != "" || depth < 1) { bad=1; return }
        if (depth == accountdepth) accountdepth=0
        depth--; return
      }
      if (kind == "{") {
        if (key == "") { bad=1; return }
        path[++depth]=key
        if (tolower(key)=="accounts") accountdepth=depth
        if (tolower(key)=="connectcache") hascache=1
        key=""; return
      }
      if (key == "") { key=val; return }
      lower=tolower(key)
      if (lower=="connectcache" && val!="") hascache=1
      if (accountdepth && depth==accountdepth+1 && lower=="steamid" && val!="") {
        if (path[depth] ~ /^[A-Za-z0-9_]+$/) names[tolower(path[depth])]=1
      }
      key=""
    }
    {
      line=$0; sub(/\r$/, "", line)
      while (length(line)) {
        if (match(line,/^[ \t]+/)) { line=substr(line,RLENGTH+1); continue }
        if (line ~ /^\/\//) break
        if (match(line,/^"([^"\\]|\\.)*"/)) {
          value=substr(line,2,RLENGTH-2); line=substr(line,RLENGTH+1)
          token("text",value); continue
        }
        if (line ~ /^[{}]/) { token(substr(line,1,1),""); line=substr(line,2); continue }
        bad=1; break
      }
    }
    END {
      if (bad || depth || key!="" || !hascache) exit 1
      for (name in names) print name
    }' "$1"
}

steam_account() {
    local cache="$ROOT/../.virtualhome/Steam/config/config.vdf" names account probe
    [[ -f "$ROOT/steamcmd.sh" && -f "$cache" ]] || die 'Steam login missing; complete AMP Update login dialog'
    names=$(cached_accounts "$cache") || die 'No readable reusable Steam cache; retry AMP Update with Steam Guard code'
    [[ -n "$names" ]] || die 'No account in AMP Steam cache; retry AMP Update login'
    if [[ "$names" != *$'\n'* ]]; then printf '%s\n' "$names"; return; fi
    # Several old accounts can remain in Steam cache. Probe tokens without stdin,
    # passwords or a new UI field; use the first account whose cached login works.
    probe=$(mktemp "$ROOT/.steam-probe.XXXXXX")
    while IFS= read -r account; do
        if HOME="$ROOT/../.virtualhome" TERM=dumb NO_COLOR=1 timeout 180 /bin/bash "$ROOT/steamcmd.sh" \
            +@NoPromptForPassword 1 +login "$account" +quit </dev/null 2>&1 | strip_ansi >"$probe" &&
            grep -Eq 'Logging in.*[.][.][.]OK' "$probe"; then
            rm -f -- "$probe"
            printf '%s\n' "$account"
            return
        fi
    done <<< "$names"
    rm -f -- "$probe"
    die 'No cached account could log in; complete AMP Update login again'
}

update() {
    local account output
    account=$(steam_account)
    output=$(mktemp "$ROOT/.workshop-update.XXXXXX")
    if ! HOME="$ROOT/../.virtualhome" TERM=dumb NO_COLOR=1 timeout 7200 /bin/bash "$ROOT/steamcmd.sh" \
        +@NoPromptForPassword 1 +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$ROOT/workshop" +login "$account" \
        +workshop_download_item "$APP" "$ITEM" validate +quit </dev/null 2>&1 | strip_ansi | tee "$output"; then
        rm -f -- "$output"
        die 'Workshop update failed; retry AMP Update login if the cached session expired'
    fi
    if ! grep -Eq "Success[.] Downloaded item $ITEM([[:space:]]|$)" "$output"; then
        rm -f -- "$output"
        die 'SteamCMD did not confirm the Workshop download; existing files were left in place'
    fi
    rm -f -- "$output"
    game_dir >/dev/null
    log 'Workshop update finished'
}

prepare_config() {
    local port=$1 data="$ROOT/data" temporary old
    check_port "$port" 65534
    settings
    mkdir -p -- "$data"
    old="$data/server-config.json"
    # Secrets are read from files, never passed as jq --arg / environment values.
    if [[ ! -f "$old" ]]; then printf '{}\n' > "$old"; fi
    temporary=$(mktemp "$data/.server-config.XXXXXX")
    if ! jq -s --argjson port "$port" '
      .[0] as $old | .[1] as $settings |
      if ($old | type) != "object" then error("Expected server config object") else
      $old + {port:$port, saveName:($settings.saveName // "saveauto1"),
        autosaveMinutes:($settings.autosaveMinutes // 5), logFile:true, steam:false,
        password:(if $settings | has("password") then $settings.password else ($old.password // "") end)} end
      ' "$old" "$ROOT/settings.json" > "$temporary"; then
        rm -f -- "$temporary"
        die 'Invalid JSON configuration; existing server-config.json was preserved'
    fi
    chmod 600 "$temporary"
    mv -f -- "$temporary" "$old"
}

start() {
    local port=$1 engine=$2 game data name mid token command binary
    check_port "$port" 65534; check_port "$engine"
    (( engine != port && engine != port+1 )) || die 'Engine port overlaps Co-op ports'
    for binary in wine wineboot wineserver xvfb-run script timeout; do
        command -v "$binary" >/dev/null || die "Missing container dependency: $binary"
    done
    game=$(game_dir)
    prepare_config "$port"
    data="$ROOT/data"
    name=$(jq -r '.saveName // "saveauto1"' "$ROOT/settings.json")
    mkdir -p -- "$data/Game Saves"
    if [[ ! -f "$data/Game Saves/$name.sav" ]]; then
        cp -- "$game/server-data/Game Saves/default_new_game.sav" "$data/Game Saves/$name.sav"
    fi
    export WINEPREFIX="$ROOT/.wine" WINEARCH=win64 WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml='
    if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
        if ! timeout 180 xvfb-run -a wineboot -i; then
            wineserver -k || true
            die 'Wine prefix initialization failed'
        fi
        timeout 15 wineserver -k
        timeout 15 wineserver -w
        [[ -f "$WINEPREFIX/system.reg" ]] || die 'Wine registry missing after initialization'
    fi
    export BANNERLORD_USER_DIR="Z:${data//\//\\}" COOP_DATA_DIR="Z:${data//\//\\}"
    export DOTNET_ROOT="Z:${game//\//\\}\\engine\\dotnet" DOTNET_MULTILEVEL_LOOKUP=0
    mid=$(sed -n 's/.*<Id[[:space:]]*value="\([A-Za-z0-9_.-]*\)".*/\1/p' "$game/engine/Modules/Coop/SubModule.xml" | head -n 1)
    [[ "$mid" =~ ^[A-Za-z0-9_.-]+$ ]] || die 'Cannot read Coop module Id'
    token="_MODULES_*Native*SandBoxCore*Sandbox*$mid*DedicatedServer.Windows*_MODULES_"
    cd -- "$game/engine/bin/Win64_Shipping_Server"
    # %q quotes only paths/module names/ports. Password stays in JSON on disk.
    printf -v command '%q ' wine "$game/engine/dotnet/dotnet.exe" TaleWorlds.Starter.DotNetCore.dll \
        "$token" /dedicatedcustomserver "$engine" EU 0
    export SHELL=/bin/bash
    exec xvfb-run -a script --quiet --return --command "stty -echo inlcr; exec $command" /dev/null
}

main() {
    command -v jq >/dev/null || die 'jq is required; refresh the AMP container packages'
    case "${1:-}" in
        update) update ;;
        init) settings ;;
        start) [[ $# == 3 ]] || die 'Usage: mount-and-blade2-coop.sh start GAME_PORT ENGINE_PORT'; start "$2" "$3" ;;
        *) die 'Usage: mount-and-blade2-coop.sh init|update|start GAME_PORT ENGINE_PORT' ;;
    esac
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
