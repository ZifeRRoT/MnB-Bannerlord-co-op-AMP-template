"""Embed the reviewed runtime in AMP Update; no remote script or bootstrap step.

Run after changing runtime.py. --check fails if the committed manifest is stale.
"""
import base64
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
payload = base64.b64encode((root / 'runtime.py').read_bytes()).decode('ascii')
code = ("import base64,pathlib,sys; "
        "p=pathlib.Path(sys.argv[1]); "
        "p.parent.mkdir(parents=True,exist_ok=True); "
        f"p.write_bytes(base64.b64decode('{payload}')); p.chmod(0o600)")
stages = [
    {"UpdateStageName": "Install bundled reviewed runtime", "UpdateSourcePlatform": "Linux",
     "UpdateSource": "Executable", "UpdateSourceData": "/usr/bin/python3",
     "UpdateSourceArgs": '-c "' + code + '" "{{$FullRootDir}}runtime.py"', "SkipOnFailure": False},
    {"UpdateStageName": "Update Co-op Workshop files (cached Steam login)", "UpdateSourcePlatform": "Linux",
     "UpdateSource": "Executable", "UpdateSourceData": "/usr/bin/python3",
     "UpdateSourceArgs": '-u "{{$FullRootDir}}runtime.py" update', "SkipOnFailure": False}
]
result = json.dumps(stages, indent=2) + '\n'
output = root / 'bannerlord-coopupdates.json'
if '--check' in sys.argv:
    if output.read_text(encoding='utf-8') != result:
        sys.exit('Update manifest is stale; run python3 tools/build_template.py')
    print('Bundled runtime matches source')
else:
    output.write_text(result, encoding='utf-8', newline='\n')
