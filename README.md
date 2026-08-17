# voxtype-mode

Switch [voxtype](https://voxtype.io) between a **light CPU mode** and an **accurate GPU
mode** with one command — no `sudo`, in about a second.

```console
$ voxtype-mode cpu
voxtype → CPU mode (model: small)
voxtype VRAM: 0 MiB   |   GPU free: 6688 MiB

$ voxtype-mode gpu
voxtype → GPU mode (model: large-v3-turbo)
voxtype VRAM: 1552 MiB   |   GPU free: 5122 MiB
```

## The problem

The voxtype daemon loads its Whisper model at startup and **keeps it resident for as long
as it runs**. There is no idle-unload setting — not in `voxtype daemon --help`, not in
`voxtype config`, not in the config file.

With `large-v3-turbo` on GPU that is ~1.5 GB of VRAM held permanently. On an 8 GB card
that is roughly 19% gone before a game even starts, which is enough to cause texture
stutter in titles that already run close to the limit.

The obvious fix — stop the service before gaming — costs you dictation entirely. This
keeps dictation working in both states and just changes how much it costs you.

## How it works

`voxtype setup gpu --enable/--disable` swaps the `/usr/bin/voxtype` symlink, which needs
root every time. That is a bad fit for something you toggle before every gaming session.

This takes a different route, entirely inside your home directory:

| Piece | Role |
|---|---|
| `~/.config/systemd/user/voxtype.service.d/mode.conf` | Drop-in redirecting `ExecStart` to the launcher |
| `~/.local/bin/voxtype-daemon-launch` | Picks binary + config from the active mode |
| `~/.config/voxtype/config.cpu.toml` / `config.gpu.toml` | One config per mode |
| `~/.local/bin/voxtype-mode` | The command you actually run |

The daemon binary is chosen per mode, so the GPU build is never even started in CPU mode.
Auto-detection picks `voxtype-avx512` only when `/proc/cpuinfo` really reports `avx512f`
(the build ships regardless and dies with `SIGILL` otherwise), then falls back to
`voxtype-avx2`; on the GPU side it tries Vulkan, then CUDA, then native.

Because it is a systemd `.d/` drop-in rather than an edit to `voxtype.service`, package
updates that rewrite the unit do not wipe it.

### CPU mode still uses the GPU client binary — and that is fine

`/usr/bin/voxtype` stays pointing at whatever variant your package manager installed. In
CPU mode the *client* you invoke (`voxtype record start`, what your compositor keybinding
calls) may therefore be the Vulkan build talking to an AVX2 *daemon*. That works: the
client is a thin IPC caller over a Unix socket and loads no model. Verified end to end —
`record start` → `recording` → `record stop` → `transcribing`.

One consequence: `voxtype info variants` and `voxtype setup gpu --status` read that
symlink, so they will keep reporting the packaged variant regardless of mode. Use
`voxtype-mode status` for the truth.

### The default resets itself every boot

The active mode is written to `$XDG_RUNTIME_DIR/voxtype-mode`, which lives on tmpfs and is
wiped on every boot and logout. With no file present the launcher falls back to
`DEFAULT_MODE` (`cpu` out of the box). So if you switch to GPU and forget to switch back,
the next boot fixes it for you — and if you would rather it persist, that is a one-line
change to a normal path in `mode.conf`.

## Requirements

- voxtype installed, with its systemd **user** service set up (`voxtype setup systemd`)
- systemd user session (any modern desktop Linux)
- `nvidia-smi` optional — only used to print VRAM numbers

## Install

```bash
git clone https://github.com/Chernicharo/voxtype-mode ~/personal/voxtype-mode
cd ~/personal/voxtype-mode
./install.sh
```

`install.sh` symlinks the scripts into `~/.local/bin`, so `git pull` updates them in place.
Pass `--copy` to copy instead. Existing configs are never overwritten.

Then point each mode at a model you actually have:

```bash
voxtype setup model --list
$EDITOR ~/.config/voxtype/config.cpu.toml   # model = "small"
$EDITOR ~/.config/voxtype/config.gpu.toml   # model = "large-v3-turbo"
```

> **Downloading `small` is booby-trapped.** `voxtype setup --download --model small`
> resolves the name to *SenseVoice*-small, fails with "requires the 'sensevoice' feature"
> — and **still exits 0**, so scripts and CI see success while no model lands on disk.
> Use the interactive `voxtype setup model`, or fetch it directly:
>
> ```bash
> curl -fL -o ~/.local/share/voxtype/models/ggml-small.bin \
>   https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
> ```

Uninstall with `./uninstall.sh` — the daemon returns to its packaged `ExecStart` and your
configs are left in place.

## Usage

```
voxtype-mode cpu      Small model on the CPU. Frees all VRAM.
voxtype-mode gpu      Large model on the GPU. Best accuracy.
voxtype-mode toggle   Switch to the other mode.
voxtype-mode status   Active mode, model and VRAM usage (default).
```

Switching restarts the daemon and waits for the new model to finish loading before
returning, so when the command exits, dictation is genuinely ready.

## Keybinding (Omarchy / Hyprland)

You switch modes *before* doing something else — launching a game, joining a call — so
opening a terminal for it defeats the purpose. Put it on a key.

**Suggested: `SUPER + CTRL + SHIFT + X`.**

Omarchy already keeps voxtype on `X`: `SUPER + CTRL + X` is "Toggle dictation" (and `F9`
is push-to-talk). Adding `SHIFT` to the dictation toggle gives you "toggle *how*
dictation runs" on the same key — the same shape Omarchy uses elsewhere, where
`SUPER + SPACE` opens the launcher and `SUPER + CTRL + SHIFT + SPACE` opens the theme
menu. Nothing in stock Omarchy claims the combo.

Add it to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + SHIFT + X", "Toggle voxtype CPU/GPU mode",
  [[bash -c 'id=$(notify-send -a voxtype -p "voxtype" "switching mode…"); notify-send -a voxtype -r "$id" "voxtype" "$(voxtype-mode toggle 2>&1)"']])
```

Hyprland reloads on save; `hyprctl reload && hyprctl configerrors` confirms it, and
`omarchy menu keybindings --print` should now list the binding.

The `notify-send` wrapper is the point of the whole line. Launched from a keybinding there
is no terminal to print to, and the switch is not instant — it restarts the daemon and
waits for the model to load. So the first notification fires *before* the switch to say it
started, and the second replaces it with the result: mode, model and VRAM.

Replacing rather than stacking is what `-p` and `-r` do: `-p` prints the id of the
notification just posted, `-r` reposts over that id. Both are plain `notify-send`, so any
spec-compliant daemon handles it. The `2>&1` matters too — if the switch fails (missing
model, incompatible binary) the error text ends up in the notification instead of
disappearing with the stderr of a process that has no terminal.

The command is `voxtype-mode toggle` and not a full path because `install.sh` puts it in
`~/.local/bin`, which is already on the Hyprland session's `PATH`.

<details>
<summary>Omarchy before 4.0 (<code>bindings.conf</code> instead of <code>bindings.lua</code>)</summary>

```ini
bind = SUPER CTRL SHIFT, X, exec, bash -c 'id=$(notify-send -a voxtype -p "voxtype" "switching mode…"); notify-send -a voxtype -r "$id" "voxtype" "$(voxtype-mode toggle 2>&1)"'
```

</details>

If you prefer explicit modes over a toggle, bind `voxtype-mode cpu` and `voxtype-mode gpu`
to two keys instead — both are idempotent, so pressing the one you are already in just
restarts the daemon in the same mode.

## Omarchy bar widget

If you would rather click than press a key, there is a companion Omarchy plugin that puts
the current mode in the status bar and switches on click:

```bash
omarchy plugin add https://github.com/Chernicharo/omarchy-plugin-voxtype-mode --enable
```

It is a thin front end — it reads `voxtype-mode status --json` and calls `voxtype-mode
toggle`, so the widget, the keybinding and the terminal all stay in sync. See
[omarchy-plugin-voxtype-mode](https://github.com/Chernicharo/omarchy-plugin-voxtype-mode).

## Configuration

`~/.config/voxtype/mode.conf` (all optional):

```bash
DEFAULT_MODE=cpu                            # mode after each boot
#VOXTYPE_LIB_DIR=/usr/lib/voxtype
#CPU_BINARY=/usr/lib/voxtype/voxtype-avx2   # skip auto-detection
#GPU_BINARY=/usr/lib/voxtype/voxtype-vulkan
```

Everything else — model, language, threads, feedback sounds — is per-mode in
`config.cpu.toml` and `config.gpu.toml`, in voxtype's own format. Setting `threads` in the
CPU config is worth it: it caps how many cores transcription may take while a game runs.

## Model notes

Measured on a Ryzen 5 3600 (AVX2, no AVX-512) with an RTX 4060 8 GB:

| Model | Size | VRAM in GPU mode | Multilingual |
|---|---|---|---|
| `base.en` | 141 MB | ~200 MB | no — English only |
| `small` | 465 MB | ~600 MB | yes |
| `large-v3-turbo` | 1549 MB | 1552 MB | yes |

`.en` variants do not transcribe other languages at all, no matter what `language` says —
if you dictate in anything but English, both modes need a non-`.en` model.

## Status

Built and verified on Omarchy 4.0.0 (Arch + Hyprland), voxtype 0.7.5, Ryzen 5 3600 +
RTX 4060. The hardware detection is written to generalize, but AVX-512, CUDA and MIGraphX
paths are **untested** — reports welcome.

## License

MIT
