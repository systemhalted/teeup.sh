# Apps

Besides the terminal and the editors, teeup installs additional apps.

| App | Capability | Tier | Notes |
|---|---|---|---|
| Firefox Developer Edition | `firefox-developer-edition` | lazy | The daily browser. |
| Obsidian | `obsidian` | lazy | Notes. Needs macOS 12 or newer. |
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

[AeroSpace](https://github.com/nikitabobko/AeroSpace) tiles your windows, i3 style. See the [AeroSpace](aerospace.md) page for its keys and configuration.

<!-- SCREENSHOT: Three windows tiled by AeroSpace (WezTerm, Emacs, Firefox Developer Edition) on workspace 1. -->

## Ollama

Ollama installs as the `ollama-app` cask, which includes the `ollama` command. If the cask cannot install, for example on a Mac older than macOS 14, teeup installs the `ollama` formula instead. Pull a model when you need one:

```sh
ollama pull llama3.2
```

## Herdr

Typing `herdr` offers to install it. Start it in a project directory; `ctrl+b q` detaches, and running `herdr` again reattaches.
