#!/usr/bin/python3 -I
"""Bounded, validated user preferences; atomic replacement preserves the last file."""
import json
import math
import os
import re
from pathlib import Path
import signal
import stat
import sys
import tempfile

MAX_BYTES = 65536
BUTTONS = {'back', 'forward', 'middle', 'tiltLeft', 'tiltRight'}
ACTIONS = {'default', 'workspace_next', 'workspace_prev', 'window_close', 'window_float',
           'window_fullscreen', 'window_next', 'overview', 'screenshot', 'media_play_pause',
           'media_next', 'media_prev', 'mute', 'tab_next', 'tab_prev', 'browser_back',
           'browser_forward', 'custom_shortcut', 'custom_command', 'profile_next'}


def valid_map(key, value, complete=False):
    if not isinstance(value, dict) or not set(value) <= BUTTONS:
        return False
    if complete and set(value) != BUTTONS:
        return False
    limit = 256 if key == 'customShortcuts' else 2048
    return all(isinstance(v, str) and '\x00' not in v and
               (v in ACTIONS if key == 'buttons' else len(v) <= limit)
               for v in value.values())


def valid_profiles(value):
    if not isinstance(value, list) or not 1 <= len(value) <= 32:
        return False
    ids = set()
    for item in value:
        if not isinstance(item, dict) or set(item) != {'id', 'name', 'buttons', 'customShortcuts', 'customCommands'}:
            return False
        identity = item['id']
        name = item['name']
        if not isinstance(identity, str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', identity) or identity in ids:
            return False
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80 or any(ord(c) < 32 for c in name):
            return False
        ids.add(identity)
        if not all(valid_map(key, item[key], complete=True) for key in ('buttons', 'customShortcuts', 'customCommands')):
            return False
    return True


def validate(raw):
    if len(raw.encode('utf-8')) > MAX_BYTES:
        raise ValueError('Preferences exceed 64 KiB')
    cfg = json.loads(raw)
    if not isinstance(cfg, dict):
        raise ValueError('Preferences must be an object')
    v2 = 'version' in cfg
    if v2 and (type(cfg['version']) is not int or cfg['version'] != 2
               or not {'profiles', 'activeProfileId', 'profileShortcut'} <= set(cfg)):
        raise ValueError('Invalid preferences version')
    for key, value in cfg.items():
        if key == 'sensitivity':
            valid = type(value) in (int, float) and math.isfinite(value) and -1 <= value <= 1
        elif key == 'accelProfile':
            valid = value in ('adaptive', 'flat')
        elif key in ('naturalScroll', 'autoReconnect'):
            valid = type(value) is bool
        elif key in ('buttons', 'customShortcuts', 'customCommands'):
            valid = not v2 and valid_map(key, value)
        elif key == 'version':
            valid = v2
        elif key == 'profiles':
            valid = v2 and valid_profiles(value)
        elif key == 'activeProfileId':
            profiles = cfg.get('profiles')
            valid = v2 and isinstance(value, str) and isinstance(profiles, list) and any(
                isinstance(p, dict) and p.get('id') == value for p in profiles
            )
        elif key == 'profileShortcut':
            valid = v2 and isinstance(value, str) and len(value) <= 256 and '\x00' not in value
        else:
            valid = False
        if not valid:
            raise ValueError('Invalid preference: ' + key)
    return cfg


def read(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('Preferences must be a regular file')
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('Preferences exceed 64 KiB')
    return validate(raw.decode('utf-8'))


def write(path, raw):
    cfg = validate(raw)
    rendered = json.dumps(cfg, ensure_ascii=False, indent=2) + '\n'
    if len(rendered.encode('utf-8')) > MAX_BYTES:
        raise ValueError('Preferences exceed 64 KiB')
    path.parent.mkdir(parents=True, exist_ok=True)
    # Never follow a final symlink or replace a special file.
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError('Preferences must be a regular file')
    fd, name = tempfile.mkstemp(prefix='.mx-ergo-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    signal.alarm(5)
    if len(sys.argv) < 3:
        raise ValueError('Invalid arguments')
    action, path = sys.argv[1:3]
    if action == 'read' and len(sys.argv) == 3:
        print(json.dumps(read(Path(path))))
    elif action == 'write' and len(sys.argv) == 4:
        write(Path(path), sys.argv[3])
    else:
        raise ValueError('Invalid arguments')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('MX Ergo: ' + str(error), file=sys.stderr)
        sys.exit(1)
