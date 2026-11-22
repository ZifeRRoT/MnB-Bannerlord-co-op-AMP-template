#!/bin/bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$REPO/mount-and-blade2-coop.sh"
WORK=$(mktemp -d /tmp/coop-players.XXXXXX)
trap 'case "$WORK" in /tmp/coop-players.*) rm -rf -- "$WORK";; esac' EXIT
passed=0
pass() { passed=$((passed+1)); printf 'PASS %s\n' "$1"; }
events() { grep '^\[AMP-Coop\]' "$1" || true; }

cat > "$WORK/session.in" <<'LOG'
[DedicatedServer] player connecting: peer 0 from 203.0.113.7
@DS@{"ev":"players","list":[{"id":0,"name":"(joining)","state":"handshake","addr":"203.0.113.7:59027"}]}
@DS@{"ev":"players","list":[{"id":0,"name":"(joining)","state":"creating character","addr":"203.0.113.7:59027"}]}
@DS@{"ev":"players","list":[{"id":0,"name":"Player One","state":"loading","addr":"203.0.113.7:59027"}]}
[DedicatedServer] player entered the campaign: peer 0
@DS@{"ev":"players","list":[{"id":0,"name":"Player One","state":"on map","addr":"203.0.113.7:59027"}]}
[DedicatedServer] player disconnected: peer 0 (RemoteConnectionClose)
@DS@{"ev":"players","list":[]}
@DS@{"ev":"players","list":[{"id":1,"name":"(joining)","state":"handshake","addr":"203.0.113.7:52730"}]}
@DS@{"ev":"players","list":[{"id":1,"name":"Player One","state":"loading","addr":"203.0.113.7:52730"}]}
@DS@{"ev":"players","list":[{"id":1,"name":"Player One","state":"on map","addr":"203.0.113.7:52730"}]}
[DedicatedServer] player disconnected: peer 1 (RemoteConnectionClose)
@DS@{"ev":"players","list":[]}
LOG
track_players < "$WORK/session.in" > "$WORK/session.out"
printf '[AMP-Coop] join\tpeer-0\tPlayer One\t203.0.113.7:59027\n[AMP-Coop] leave\tpeer-0\n[AMP-Coop] join\tpeer-1\tPlayer One\t203.0.113.7:52730\n[AMP-Coop] leave\tpeer-1\n' > "$WORK/expected"
events "$WORK/session.out" > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
pass 'new character and reconnect produce one join and one leave per peer'
sed '/^\[AMP-Coop\]/d' "$WORK/session.out" > "$WORK/raw"
cmp "$WORK/session.in" "$WORK/raw"
pass 'original server console lines are preserved'

cat > "$WORK/multiple.in" <<'LOG'
@DS@{"ev":"players","list":[{"id":0,"name":"Alice","addr":"203.0.113.1:4000"},{"id":1,"name":"Bob","addr":"203.0.113.2:4000"}]}
@DS@{"ev":"players","list":[{"id":0,"name":"Alice","addr":"203.0.113.1:4000"},{"id":1,"name":"Bob","addr":"203.0.113.2:4000"}]}
@DS@{"ev":"players","list":[{"id":0,"name":"Alice","addr":"203.0.113.1:4000"}]}
@DS@{"ev":"players","list":[]}
LOG
track_players < "$WORK/multiple.in" > "$WORK/multiple.out"
printf '[AMP-Coop] join\tpeer-0\tAlice\t203.0.113.1:4000\n[AMP-Coop] join\tpeer-1\tBob\t203.0.113.2:4000\n[AMP-Coop] leave\tpeer-1\n[AMP-Coop] leave\tpeer-0\n' > "$WORK/expected"
events "$WORK/multiple.out" > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
pass 'all players in a snapshot are tracked and missing disconnect lines are reconciled'

cat > "$WORK/invalid.in" <<'LOG'
@DS@{"ev":"players","list":[{"id":2,"name":"Alice","addr":"203.0.113.1:4000"}]}
@DS@{"ev":"state","phase":"serving"}
@DS@{"ev":"players","list":null}
@DS@{"ev":"players","list":[{"id":"2","name":"Wrong"}]}
@DS@{"ev":"players","list":[{"id":2,"name":"Wrong"},{"id":2,"name":"Duplicate"}]}
@DS@{"ev":"players","list":broken}
ordinary output
@DS@{"ev":"players","list":[{"id":2,"name":"(joining)","state":"loading","addr":"203.0.113.1:4000"}]}
[DedicatedServer] player disconnected: peer 999 (Timeout)
@DS@{"ev":"players","list":[]}
LOG
track_players < "$WORK/invalid.in" > "$WORK/invalid.out"
[[ $(events "$WORK/invalid.out" | wc -l) == 2 ]]
pass 'malformed or unrelated events do not erase users; unknown peers do not remove another user'

cat > "$WORK/duplicates.in" <<'LOG'
@DS@{"ev":"players","list":[{"id":0,"name":"Same","addr":"203.0.113.1:4000"}]}
@DS@{"ev":"players","list":[{"id":0,"name":"Same","addr":"203.0.113.1:4000"},{"id":1,"name":"Same","addr":"203.0.113.2:4000"}]}
[DedicatedServer] player disconnected: peer 0 (Timeout)
@DS@{"ev":"players","list":[{"id":1,"name":"Same","addr":"203.0.113.2:4000"}]}
LOG
track_players < "$WORK/duplicates.in" > "$WORK/duplicates.out"
printf '[AMP-Coop] join\tpeer-0\tSame\t203.0.113.1:4000\n[AMP-Coop] join\tpeer-1\tSame [peer 1]\t203.0.113.2:4000\n[AMP-Coop] leave\tpeer-0\n[AMP-Coop] leave\tpeer-1\n' > "$WORK/expected"
events "$WORK/duplicates.out" > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
pass 'duplicate names receive stable distinct display names for AMP'

cat > "$WORK/wrapped.in" <<'LOG'
@DS@{"ev":"players","list":[{"id":3,"name":"Ali
ce","state":"on map","addr":"[2001:db8::1]:4000"}]
}
@DS@{"ev":"players","list":[]}
LOG
track_players < "$WORK/wrapped.in" > "$WORK/wrapped.out"
printf '[AMP-Coop] join\tpeer-3\tAlice\t[2001:db8::1]:4000\n[AMP-Coop] leave\tpeer-3\n' > "$WORK/expected"
events "$WORK/wrapped.out" > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
pass 'wrapped JSON snapshots are reassembled without changing raw output'

printf '\033[?25l@DS@{"ev":"players","list":[{"id":4,"name":"Мандрівник \\"A\\"\\nB","addr":"203.0.113.4:4000"}]}\033[K\r\r\n' > "$WORK/ansi.in"
track_players < "$WORK/ansi.in" > "$WORK/ansi.out"
printf '[AMP-Coop] join\tpeer-4\tМандрівник "A" B\t203.0.113.4:4000\n[AMP-Coop] leave\tpeer-4\n' > "$WORK/expected"
events "$WORK/ansi.out" > "$WORK/actual"
cmp "$WORK/expected" "$WORK/actual"
sed '/^\[AMP-Coop\]/d' "$WORK/ansi.out" > "$WORK/raw"
cmp "$WORK/ansi.in" "$WORK/raw"
pass 'ANSI and CR bytes pass through; Unicode and escaped names are decoded safely'

ROOT="$WORK/runtime"
mkdir -p "$ROOT/server/engine/bin/Win64_Shipping_Server" "$WORK/bin"
cp "$REPO/mount-and-blade2-coop.sh" "$ROOT/mount-and-blade2-coop.sh"
cat > "$WORK/bin/wine" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$BANNERLORD_USER_DIR" == "Z:$COOP_TEST_ROOT/data" ]]
[[ "$COOP_DATA_DIR" == "$BANNERLORD_USER_DIR" ]]
[[ "$DOTNET_ROOT" == "Z:$COOP_TEST_ROOT/server/engine/dotnet" ]]
[[ "$PWD" == "$COOP_TEST_ROOT/server/engine/bin/Win64_Shipping_Server" ]]
[[ "$*" == '../../dotnet/dotnet.exe TaleWorlds.Starter.DotNetCore.dll _MODULES_*Native*SandBoxCore*Sandbox*Coop*DedicatedServer.Windows*_MODULES_' ]]
printf '@DS@{"ev":"players","list":[{"id":5,"name":"Fixture","addr":"203.0.113.5:4000"}]}\n'
stty -icanon min 1 time 0
IFS= read -r -d $'\r' command
[[ "$command" == stop ]]
printf 'FIXTURE_STOP_OK\n'
exit "${COOP_TEST_EXIT:-0}"
SH
chmod +x "$WORK/bin/wine"
export COOP_TEST_ROOT="$ROOT"
printf 'stop\n' | PATH="$WORK/bin:$PATH" timeout 20 bash "$ROOT/mount-and-blade2-coop.sh" start Coop > "$WORK/start.out" 2>&1
grep -q FIXTURE_STOP_OK "$WORK/start.out"
grep -q $'^\[AMP-Coop\] join\tpeer-5\tFixture\t' "$WORK/start.out"
grep -q $'^\[AMP-Coop\] leave\tpeer-5' "$WORK/start.out"
pass 'startup preserves stdin/stop, Wine data paths, module args and bridge EOF cleanup'
if printf 'stop\n' | PATH="$WORK/bin:$PATH" COOP_TEST_EXIT=23 timeout 20 bash "$ROOT/mount-and-blade2-coop.sh" start Coop > "$WORK/failure.out" 2>&1; then
  printf 'Expected nonzero startup exit\n' >&2; exit 1
fi
grep -q FIXTURE_STOP_OK "$WORK/failure.out"
pass 'nonzero engine exit is not hidden by the console bridge'
printf 'All %s player checks passed\n' "$passed"
