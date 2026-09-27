# Apps

Besides the terminal and the editors, teeup installs a handful of apps.

| App | Capability | Tier | Notes |
|---|---|---|---|
| Firefox Developer Edition | `firefox-developer-edition` | daily | The daily browser. |
| Obsidian | `obsidian` | daily | Notes. Needs macOS 12 or newer. |
| Google Chrome | `chrome` | lazy | Needs macOS 13 or newer. |
| AeroSpace | `aerospace` | core | Tiling window manager. Needs macOS 13 or newer. |
| Ollama | `ollama` | lazy | Local language models. No model is downloaded for you. |
| Herdr | `herdr` | lazy | An agent multiplexer that runs in your terminal. |

The browsers and Obsidian are Homebrew casks. On a MacPorts machine teeup marks them "not applicable" and names the vendor's download page.

## teeup launch

`teeup launch` opens an app. If the app is missing, it installs the capability that provides it first, then opens it. If the app is already running, macOS brings it to the front.

```sh
teeup launch Google Chrome     # no quotes needed
teeup launch chrome            # the capability name works too
teeup launch Obsidian
```

An app name is matched without regard to case; a capability name must be typed as `teeup list` shows it. The Launch section of `teeup menu` lists every installed app.

## AeroSpace

[AeroSpace](https://github.com/nikitabobko/AeroSpace) tiles your windows, i3 style. Its configuration is `~/.config/aerospace/aerospace.toml`, copied once and yours after that. If you already have `~/.aerospace.toml`, teeup keeps it and does not install its own, because AeroSpace refuses to run with two.

AeroSpace needs one step from you, once per Mac: System Settings, Privacy & Security, Accessibility, then turn AeroSpace on. Until then it cannot move a window. teeup prints this reminder the first time, then start it with `open -a AeroSpace`.

The main keys all use Option (`alt`):

| Keys | Action |
|---|---|
| `alt-enter` | Open a new WezTerm window |
| `alt-h`, `alt-j`, `alt-k`, `alt-l` | Focus left, down, up, right |
| `alt-shift-h`, `alt-shift-j`, `alt-shift-k`, `alt-shift-l` | Move the window left, down, up, right |
| `alt-1` to `alt-9` | Switch to workspace 1 to 9 |
| `alt-shift-1` to `alt-shift-9` | Move the window to that workspace |
| `alt-tab` | Back to the previous workspace |
| `alt-f` | Full screen |
| `alt-slash` / `alt-comma` | Tiles layout / accordion layout |
| `alt-minus` / `alt-equal` | Shrink / grow |
| `alt-shift-semicolon` | Service mode |

`alt-ctrl` with `b`, `n`, `p` and `f` does the same as `h`, `j`, `k` and `l`, for Emacs hands.

<!-- SCREENSHOT: Three windows tiled by AeroSpace (WezTerm, Emacs, Firefox Developer Edition) on workspace 1. -->

## Ollama

Ollama installs as the `ollama-app` cask, which includes the `ollama` command. If the cask cannot install, for example on a Mac older than macOS 14, teeup installs the `ollama` formula instead. Pull a model when you need one:

```sh
ollama pull llama3.2
```

## Herdr

Typing `herdr` offers to install it. Start it in a project directory; `ctrl+b q` detaches, and running `herdr` again reattaches.
