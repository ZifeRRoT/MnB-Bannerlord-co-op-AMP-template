#!/bin/bash
# Run inside disposable AMP Wine image. No game files or Steam credentials.
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$REPO/mount-and-blade2-coop.sh"
WORK=$(mktemp -d /tmp/coop-wine.XXXXXX)
export WINEPREFIX="$WORK/wine" WINEARCH=win64 WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml='
cleanup() { wineserver -k 2>/dev/null || true; case "$WORK" in /tmp/coop-wine.*) rm -rf -- "$WORK";; esac; }
trap cleanup EXIT
timeout 180 xvfb-run -a wineboot -i
timeout 15 wineserver -k
timeout 15 wineserver -w
test -f "$WINEPREFIX/system.reg"
printf 'WINE_PREFIX_OK\n'
mkdir -p "$WORK/instance/server/engine/bin/Win64_Shipping_Server" "$WORK/instance/data"
printf '{}\n' > "$WORK/instance/data/server-config.json"
printf '@echo off\r\nif not exist "%%BANNERLORD_USER_DIR%%/server-config.json" exit /b 9\r\necho DATA_PATH_OK\r\necho @DS@{"ev":"players","list":[{"id":0,"name":"Wine Fixture","addr":"203.0.113.1:4200"}]}\r\necho WINE_READY\r\nset /p command=\r\nif "%%command%%"=="stop" (echo WINE_STOP_OK & exit /b 0)\r\nexit /b 9\r\n' > "$WORK/instance/server/engine/bin/Win64_Shipping_Server/console.cmd"
cd "$WORK/instance/server/engine/bin/Win64_Shipping_Server"
# Keep stdin open until Wine has opened its console, like AMP's live console.
mkfifo "$WORK/input"
exec 3<> "$WORK/input"
timeout 90 env "BANNERLORD_USER_DIR=Z:$WORK/instance/data" "COOP_DATA_DIR=Z:$WORK/instance/data" \
  xvfb-run -a socat STDIO 'EXEC:/usr/bin/wine cmd /c console.cmd,pty,setsid,ctty,echo=0,inlcr' \
  < "$WORK/input" 2>&1 | track_players > "$WORK/output" &
child=$!
ready=false
for ((attempt=0; attempt<60; attempt++)); do
    if grep -q WINE_READY "$WORK/output"; then ready=true; break; fi
    kill -0 "$child" 2>/dev/null || break
    sleep 1
done
if [[ "$ready" != true ]]; then cat "$WORK/output"; exit 1; fi
printf 'stop\n' >&3
set +e
wait "$child"
status=$?
set -e
exec 3>&-
cat "$WORK/output"
[[ "$status" == 0 ]]
grep -q DATA_PATH_OK "$WORK/output"
grep -q WINE_STOP_OK "$WORK/output"
grep -q $'^\[AMP-Coop\] join\tpeer-0\tWine Fixture\t' "$WORK/output"
grep -q $'^\[AMP-Coop\] leave\tpeer-0' "$WORK/output"
printf 'WINE_DATA_PATH_PLAYERS_AND_STOP_OK\n'
