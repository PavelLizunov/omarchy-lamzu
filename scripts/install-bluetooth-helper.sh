#!/bin/bash -p
# Run manually as administrator after reviewing this version. Never called by the plugin.
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
[[ $EUID -eq 0 ]] || { echo 'Run the reviewed installer as administrator.' >&2; exit 1; }
[[ $# -eq 0 ]] || { echo 'No arguments accepted.' >&2; exit 2; }
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../system" && pwd -P)"
# Fixed destinations, protected ancestors, no replacement of symlinks or non-root files.
check_path() {
  local current="$1"
  while [[ "$current" != / ]]; do
    if [[ -e "$current" || -L "$current" ]]; then
      [[ ! -L "$current" && ( -f "$current" || -d "$current" ) ]] || return 1
      [[ $(stat -c %u -- "$current") == 0 ]] || return 1
      local mode
      mode=$(stat -c %a -- "$current")
      (( (8#$mode & 8#022) == 0 )) || return 1
    fi
    current=$(dirname -- "$current")
  done
}
helper=/usr/local/libexec/omarchy-mx-ergo-bluetooth
policy=/usr/share/polkit-1/actions/io.github.pavellizunov.mx-ergo.bluetooth.policy
check_path "$helper"
check_path "$policy"
[[ -f "$source_dir/omarchy-mx-ergo-bluetooth" && ! -L "$source_dir/omarchy-mx-ergo-bluetooth" ]]
[[ -f "$source_dir/io.github.pavellizunov.mx-ergo.bluetooth.policy" && ! -L "$source_dir/io.github.pavellizunov.mx-ergo.bluetooth.policy" ]]
# Existing installations are not overwritten silently. Remove/update deliberately after restore.
[[ ! -e "$helper" && ! -e "$policy" ]] || { echo 'Helper already installed; review an explicit upgrade.' >&2; exit 1; }
[[ -d /usr/local/libexec ]] || install -d -o root -g root -m 755 /usr/local/libexec
install -o root -g root -m 755 -- "$source_dir/omarchy-mx-ergo-bluetooth" "$helper"
if ! install -o root -g root -m 644 -- "$source_dir/io.github.pavellizunov.mx-ergo.bluetooth.policy" "$policy"; then
  rm -f -- "$helper"
  exit 1
fi
echo 'Installed optional helper and Polkit action. No Bluetooth settings were changed.'
