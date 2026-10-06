# AeroSpace

[AeroSpace](https://nikitabobko.github.io/AeroSpace) controls workspaces and puts your windows in tile or accordion layouts, in the i3 style.

AeroSpace needs Accessibility access the first time it runs:

1. Open System Settings > Privacy & Security > Accessibility.
2. Enable AeroSpace.
3. Run `open -a AeroSpace`.

After that, AeroSpace starts automatically when you sign in.

## Keys

The configuration file has two modes: the main mode and the service mode. The main keys use Option (`alt`), and some shortcuts also have Emacs-style aliases.

### Main mode: Focus

| Keys | Action |
|---|---|
| `alt-h`, `alt-j`, `alt-k`, `alt-l` | Focus the left, down, up, or right window |
| `alt-ctrl-b`, `alt-ctrl-n`, `alt-ctrl-p`, `alt-ctrl-f` | Focus the left, down, up, or right window (Emacs style) |

### Main mode: Move

| Keys | Action |
|---|---|
| `alt-shift-h`, `alt-shift-j`, `alt-shift-k`, `alt-shift-l` | Move the window left, down, up, or right |
| `alt-ctrl-shift-b`, `alt-ctrl-shift-n`, `alt-ctrl-shift-p`, `alt-ctrl-shift-f` | Move the window left, down, up, or right (Emacs style) |

### Main mode: Workspaces

| Keys | Action |
|---|---|
| `alt-1` to `alt-9` | Go to workspace 1 to 9 |
| `alt-shift-1` to `alt-shift-9` | Move the window to workspace 1 to 9 |
| `alt-tab` | Return to the previous workspace |
| `alt-shift-tab` | Move the workspace to the next monitor |

### Main mode: Layouts

| Keys | Action |
|---|---|
| `alt-slash` | Use the tiled layout |
| `alt-comma` | Use the accordion layout |
| `alt-backslash` | Change the window to floating or tiled |
| `alt-f` | Use the full screen |
| `alt-enter` | Open a new WezTerm window |

### Main mode: Resize

| Keys | Action |
|---|---|
| `alt-minus` | Make the window smaller |
| `alt-equal` | Make the window larger |

### Main mode: Service mode

| Keys | Action |
|---|---|
| `alt-shift-semicolon` | Enter the service mode |

### Service mode

Each service mode key does one task, and then AeroSpace returns to the main mode.

| Keys | Action |
|---|---|
| `esc` | Reload the configuration |
| `r` | Flatten the workspace tree |
| `f` | Change the layout to floating or tiled |
| `backspace` | Close all windows except the current window |
| `alt-shift-h`, `alt-shift-j`, `alt-shift-k`, `alt-shift-l` | Join the left, down, up, or right window |
| `alt-ctrl-shift-b`, `alt-ctrl-shift-n`, `alt-ctrl-shift-p`, `alt-ctrl-shift-f` | Join the left, down, up, or right window (Emacs style) |

## Configuration

Edit `~/.config/aerospace/aerospace.toml`. teeup copies this file one time, and after that you can change it. If you have `~/.aerospace.toml`, teeup keeps it and does not install its own file, because AeroSpace does not run if it finds two configuration files. To reload the configuration, press `esc` in the service mode or run `aerospace reload-config`.

If you have more than one display, you can assign workspaces to specific monitors in the configuration file. For more than the teeup configuration, read [AeroSpace's guide](https://nikitabobko.github.io/AeroSpace/guide).

## Troubleshooting

Run `teeup doctor` to check that AeroSpace runs and its configuration is correct. Read the [doctor page](doctor-and-troubleshooting.md) for more information.

## Removing it

Run `teeup remove aerospace`. If you do not want to install AeroSpace, use `TEEUP_SKIP=aerospace`.
