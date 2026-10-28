#!/bin/bash -p
# Unprivileged compatibility entry point. Never authorize this mutable script as root.
set -euo pipefail
export PATH=/usr/bin:/bin
exec /usr/bin/python3 -I "$(dirname -- "${BASH_SOURCE[0]}")/bluetooth-client.py" "$@"
