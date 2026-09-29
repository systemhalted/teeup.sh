# AeroSpace

[AeroSpace](https://nikitabobko.github.io/AeroSpace) tiles your windows, i3 style. It manages workspaces, and arranges windows in tiles or accordion layouts.

First run requires Accessibility access: go to System Settings > Privacy & Security > Accessibility and turn AeroSpace on. Then start it with `open -a AeroSpace`. It starts at login automatically.

## Keys

The configuration file defines two modes: main and service. The main keys use Option (`alt`). Some bindings offer Emacs-style aliases alongside the standard keys.

### Main mode: Focus

| Keys | Action |
|---|---|
| `alt-h`, `alt-j`, `alt-k`, `alt-l` | Focus left, down, up, right |
| `alt-ctrl-b`, `alt-ctrl-n`, `alt-ctrl-p`, `alt-ctrl-f` | Focus left, down, up, right (Emacs style) |

### Main mode: Move

| Keys | Action |
|---|---|
| `alt-shift-h`, `alt-shift-j`, `alt-shift-k`, `alt-shift-l` | Move left, down, up, right |
| `alt-ctrl-shift-b`, `alt-ctrl-shift-n`, `alt-ctrl-shift-p`, `alt-ctrl-shift-f` | Move left, down, up, right (Emacs style) |

### Main mode: Workspaces

| Keys | Action |
|---|---|
| `alt-1` to `alt-9` | Switch to workspace 1 to 9 |
| `alt-shift-1` to `alt-shift-9` | Move window to workspace 1 to 9 |
| `alt-tab` | Back to the previous workspace |
| `alt-shift-tab` | Move workspace to the next monitor |

### Main mode: Layouts

| Keys | Action |
|---|---|
| `alt-slash` | Tiles layout |
| `alt-comma` | Accordion layout |
| `alt-backslash` | Tiling floating |
| `alt-f` | Full screen |
| `alt-enter` | Open a new WezTerm window |

### Main mode: Resize

| Keys | Action |
|---|---|
| `alt-minus` | Shrink |
| `alt-equal` | Grow |

### Main mode: Service mode

| Keys | Action |
|---|---|
| `alt-shift-semicolon` | Enter service mode |

### Service mode

Service mode bindings perform one job and return to main mode.

| Keys | Action |
|---|---|
| `esc` | Reload config |
| `r` | Flatten workspace tree |
| `f` | Toggle layout floating tiling |
| `backspace` | Close all windows but current |
| `alt-shift-h`, `alt-shift-j`, `alt-shift-k`, `alt-shift-l` | Join with left, down, up, right |
| `alt-ctrl-shift-b`, `alt-ctrl-shift-n`, `alt-ctrl-shift-p`, `alt-ctrl-shift-f` | Join with left, down, up, right (Emacs style) |

## Configuration

Edit `~/.config/aerospace/aerospace.toml`. teeup copies this file once, and after that it is yours to modify. Reload it with `esc` in service mode, or run `aerospace reload-config`.

For multiple displays, you can assign workspaces to specific monitors in the config. See [AeroSpace's guide](https://nikitabobko.github.io/AeroSpace/guide) for anything beyond the teeup configuration.

## Troubleshooting

Run `teeup doctor` to check if AeroSpace is running and configured correctly. See the [doctor page](doctor-and-troubleshooting.md) for details.

## Removing it

Run `teeup remove aerospace`. To skip installing it entirely, use `TEEUP_SKIP=aerospace`.
