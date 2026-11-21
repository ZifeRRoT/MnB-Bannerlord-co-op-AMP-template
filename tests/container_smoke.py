"""Runs only in a disposable Wine container; creates its prefix under /tmp."""
import importlib.util
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    shutil.copy2('/work/runtime.py', root / 'runtime.py')
    spec = importlib.util.spec_from_file_location('smoke_runtime', root / 'runtime.py')
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    env = dict(os.environ)
    if '--skip-steam' not in sys.argv:
        exe, env = runtime.steam()
        subprocess.run(['/bin/bash', str(exe), '+quit'], env=env, check=True, timeout=180)
        print('STEAMCMD_SMOKE_OK', flush=True)
    # A PTY must remain writable after startup and propagate the child's exit code.
    child = root / 'child.py'
    child.write_text('import sys\nprint("PTY_READY", flush=True)\n'
                     'assert input() == "stop"\nprint("PTY_STOP_OK", flush=True)\nsys.exit(7)\n')
    proc = subprocess.Popen(['script', '--quiet', '--return', '--command',
                             f'stty -echo; exec python3 {child}', '/dev/null'],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        if not select.select([proc.stdout], [], [], 15)[0]:
            raise RuntimeError('PTY startup timed out')
        assert b'PTY_READY' in proc.stdout.readline()
        proc.stdin.write(b'stop\n')
        proc.stdin.flush()
        output = proc.communicate(timeout=15)[0]
        assert b'PTY_STOP_OK' in output, output
        assert proc.returncode == 7, proc.returncode
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    print('PTY_STOP_AND_EXIT_STATUS_OK', flush=True)
    # Verify Wine can actually initialize, rather than only reporting its version.
    env.update(WINEPREFIX=str(root / 'wine'), WINEARCH='win64', WINEDEBUG='-all',
               WINEDLLOVERRIDES='mscoree,mshtml=')
    subprocess.run(['xvfb-run', '-a', 'wineboot', '-i'], env=env, check=True, timeout=120)
    subprocess.run(['wineserver', '-k'], env=env, check=True)
    subprocess.run(['wineserver', '-w'], env=env, check=True, timeout=15)
    assert (root / 'wine/system.reg').exists()
    print('WINE_PREFIX_OK', flush=True)
    # Exercise Windows console input through Wine and PTY, without game files.
    batch = root / 'console.cmd'
    batch.write_bytes(b'@echo off\r\necho WINE_READY\r\nset /p command=\r\n'
                      b'if "%command%"=="stop" (echo WINE_STOP_OK & exit /b 7)\r\nexit /b 9\r\n')
    windows_batch = 'Z:' + str(batch).replace('/', '\\')
    import shlex
    proc = subprocess.Popen(['xvfb-run', '-a', 'script', '--quiet', '--return',
                             '--command', 'stty -echo inlcr; exec ' + shlex.join(['wine', 'cmd', '/c', windows_batch]),
                             '/dev/null'], env=env, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        if not select.select([proc.stdout], [], [], 60)[0]:
            raise RuntimeError('Wine console startup timed out')
        line = proc.stdout.readline()
        assert b'WINE_READY' in line, line
        proc.stdin.write(b'stop\n')
        proc.stdin.flush()
        output = proc.communicate(timeout=30)[0]
        assert b'WINE_STOP_OK' in output, output
        assert proc.returncode == 7, proc.returncode
    finally:
        subprocess.run(['wineserver', '-k'], env=env, check=False)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    print('WINE_STDIO_STOP_AND_EXIT_STATUS_OK', flush=True)
