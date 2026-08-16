#!/bin/bash
# Reverts install.sh: the daemon goes back to the packaged ExecStart.
# Your config.cpu.toml / config.gpu.toml are left alone — delete them yourself
# if you want them gone.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
DROPIN="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/voxtype.service.d/mode.conf"
MODE_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/voxtype-mode"

rm -f "$BIN_DIR/voxtype-mode" "$BIN_DIR/voxtype-daemon-launch" "$DROPIN" "$MODE_FILE"
rmdir --ignore-fail-on-non-empty "$(dirname "$DROPIN")" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user restart voxtype 2>/dev/null || true

echo "Removed. voxtype is back on its packaged ExecStart:"
systemctl --user show -p ExecStart --value voxtype
echo
echo "Config files kept in ${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/"
