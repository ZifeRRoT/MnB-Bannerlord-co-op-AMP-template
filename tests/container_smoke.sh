#!/bin/bash
# Run inside disposable AMP Wine image. No game files or Steam credentials.
set -euo pipefail
WORK=$(mktemp -d /tmp/coop-wine.XXXXXX)
export WINEPREFIX="$WORK/wine" WINEARCH=win64 WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml='
cleanup() { wineserver -k 2>/dev/null || true; case "$WORK" in /tmp/coop-wine.*) rm -rf -- "$WORK";; esac; }
trap cleanup EXIT
timeout 180 xvfb-run -a wineboot -i
timeout 15 wineserver -k
timeout 15 wineserver -w
test -f "$WINEPREFIX/system.reg"
printf 'WINE_PREFIX_OK\n'
printf '@echo off\r\necho WINE_READY\r\nset /p command=\r\nif "%%command%%"=="stop" (echo WINE_STOP_OK & exit /b 7)\r\nexit /b 9\r\n' > "$WORK/console.cmd"
printf -v command '%q ' wine cmd /c "Z:${WORK//\//\\}\\console.cmd"
# Keep stdin open until Wine has opened its console, like AMP's live console.
mkfifo "$WORK/input"
exec 3<> "$WORK/input"
export SHELL=/bin/bash
timeout 90 xvfb-run -a script --quiet --return --command "stty -echo inlcr; exec $command" /dev/null \
  < "$WORK/input" > "$WORK/output" 2>&1 &
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
[[ "$status" == 7 ]]
grep -q WINE_STOP_OK "$WORK/output"
printf 'WINE_STDIO_STOP_AND_EXIT_STATUS_OK\n'
