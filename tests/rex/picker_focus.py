"""Exercise the actual config + close watcher against a disposable local Rex server.

Run with python3 tests/rex/picker_focus.py. No app, user server or reload needed.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


REX = shutil.which('rex')
CONFIG = Path(__file__).resolve().parents[2] / 'rex'


def until(check):
    end = time.monotonic() + 4
    while not check():
        if time.monotonic() >= end:
            raise AssertionError('timed out waiting for test state')
        time.sleep(.025)


def test(tmp):
    # Use a private, short socket path (Darwin limits Unix socket path length).
    socket = tmp / 's'
    target = 'unix://' + str(socket)
    cli = [REX, '-S', target, '--autostart=false', '--timeout=3s']
    picker = tmp / 'hold'
    picker.write_text('#!/bin/sh\nexec /bin/sleep 45\n')
    picker.chmod(0o700)
    env = dict(HOME=str(tmp), PATH=os.environ['PATH'], XDG_STATE_HOME=str(tmp),
               SHELL='/bin/sh', REX_PICKER_PATH=str(picker))

    def call(*args):
        out = subprocess.check_output(cli + list(args), env=env, timeout=5)
        return json.loads(out) if out.strip() else None

    processes = []
    try:
        processes.append(subprocess.Popen([REX, 'server', 'run', '--listen', target,
            '--state-dir', str(tmp / 'server'), '--restore=false', '--config', str(CONFIG / 'init.lua')],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        until(socket.exists)
        created = call('new', 'test', '--json', '--shell=none', '--', '/bin/sleep', '45')
        session = created['session_id']
        first = created['initial_windows'][0]['block_ids'][0]
        origin = call('split', '-s', session, '-b', first, '--json', '--shell=none', '--',
                      '/bin/sleep', '45')['block_ids'][0]
        processes.append(subprocess.Popen(cli + ['do', str(CONFIG / 'follow-terminal-drawer.lua'),
            '--all', '--for', '35s'], env=env, stdout=subprocess.DEVNULL))
        for move_away in (False, True):
            call('api', 'call', '-s', session, 'session.focus_block', json.dumps({'block_id': origin}))
            layer = call('do', '-s', session, '-b', origin, 'open_url_picker', '--json')
            marker = tmp / 'rex/picker-focus' / (layer['block_ids'][0].replace(':', '_') + '.tsv')
            until(marker.exists)
            if move_away:
                call('api', 'call', '-s', session, 'session.focus_block', json.dumps({'block_id': first}))
            time.sleep(.15)  # let the watcher observe focus before closing the layer
            call('api', 'call', '-s', session, 'session.close_layer', json.dumps({'layer_id': layer['layer_id']}))
            until(lambda: not marker.exists())
            def focused():
                view = call('api', 'call', '-s', session, 'session.view')
                return next(w for w in view['windows'] if w['window_id'] == view['active_window_id'])['focused_block_id']
            until(lambda: focused() == (first if move_away else origin))
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=4)


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(dir='/tmp', prefix='rex-focus-') as directory:
        test(Path(directory))
    print('Picker close restored its origin and left deliberately moved focus alone.')
