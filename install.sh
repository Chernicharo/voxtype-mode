#!/bin/bash
# Installs voxtype-mode into the current user's home. No sudo, no system files.
#
#   ./install.sh          symlink the scripts (git pull then updates them in place)
#   ./install.sh --copy   copy the scripts instead

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype"
DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/voxtype.service.d"

mode=link
[[ ${1:-} == --copy ]] && mode=copy

command -v voxtype >/dev/null || {
  echo "voxtype is not installed or not on PATH. Install it first: https://voxtype.io" >&2
  exit 1
}

systemctl --user cat voxtype.service >/dev/null 2>&1 || {
  echo "The voxtype user service is missing. Run 'voxtype setup systemd' first." >&2
  exit 1
}

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DROPIN_DIR"

for script in voxtype-mode voxtype-daemon-launch; do
  rm -f "$BIN_DIR/$script"
  if [[ $mode == link ]]; then
    ln -s "$REPO_DIR/bin/$script" "$BIN_DIR/$script"
  else
    install -m 755 "$REPO_DIR/bin/$script" "$BIN_DIR/$script"
  fi
  echo "installed $BIN_DIR/$script ($mode)"
done
chmod +x "$REPO_DIR"/bin/*

# Never clobber configs someone has already tuned.
for example in mode.conf config.cpu.toml config.gpu.toml; do
  if [[ -e $CONFIG_DIR/$example ]]; then
    echo "kept existing $CONFIG_DIR/$example"
  else
    cp "$REPO_DIR/config/$example.example" "$CONFIG_DIR/$example"
    echo "created $CONFIG_DIR/$example"
  fi
done

install -m 644 "$REPO_DIR/systemd/mode.conf" "$DROPIN_DIR/mode.conf"
echo "installed $DROPIN_DIR/mode.conf"

systemctl --user daemon-reload

echo
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "NOTE: $BIN_DIR is not on your PATH — add it to use 'voxtype-mode' directly."; echo ;;
esac

echo "Next: make sure both models are downloaded, then pick a mode."
echo
echo "  voxtype setup model --list      # what you already have"
echo "  voxtype-mode gpu                # accurate mode"
echo "  voxtype-mode cpu                # light mode, frees all VRAM"
echo
echo "Set 'model' in $CONFIG_DIR/config.{cpu,gpu}.toml to models you actually have."
echo "Heads up: 'voxtype setup --download --model small' resolves to SenseVoice-small,"
echo "not Whisper small, and still exits 0. Use the interactive 'voxtype setup model',"
echo "or fetch ggml-small.bin straight from huggingface.co/ggerganov/whisper.cpp."
