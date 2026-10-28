#!/usr/bin/python3 -I
"""Check the installed trust boundary before invoking the optional system helper."""
import json
import os
from pathlib import Path
import re
import stat
import sys

HELPER = Path('/usr/local/libexec/omarchy-mx-ergo-bluetooth')


def trusted_helper(path=HELPER, owner=0):
    try:
        for item in [*reversed(path.parents), path]:
            info = item.lstat()
            if info.st_uid != owner or info.st_mode & 0o022 or not (
                stat.S_ISDIR(info.st_mode) if item != path else stat.S_ISREG(info.st_mode)
            ):
                return False
        return os.access(path, os.X_OK)
    except OSError:
        return False


def command(action, adapter, trusted):
    if action not in ('--status', '--enable', '--disable', '--remove-legacy'):
        raise ValueError('Invalid operation')
    if adapter != '-' and not re.fullmatch(r'hci[0-9]+', adapter):
        raise ValueError('Invalid adapter')
    if not trusted:
        return None
    args = [str(HELPER), action, adapter]
    return args if action == '--status' else ['/usr/bin/pkexec', *args]


def main(argv):
    if len(argv) != 2:
        raise ValueError('Expected operation and adapter')
    args = command(*argv, trusted_helper())
    if args is None:
        if argv[0] != '--status':
            raise ValueError('Install the trusted Bluetooth helper first; see README')
        legacy = any(Path(p).exists() for p in (
            '/etc/tmpfiles.d/bluetooth-low-latency.conf',
            '/etc/udev/rules.d/50-bluetooth-performance.rules'))
        print(json.dumps({'version': 1, 'helperAvailable': False, 'configured': legacy,
                          'canRestore': False, 'state': 'legacy' if legacy else 'unavailable'}))
    else:
        os.execv(args[0], args)


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError) as error:
        print('MX Ergo Bluetooth: ' + str(error), file=sys.stderr)
        sys.exit(1)
