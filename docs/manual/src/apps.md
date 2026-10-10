# Apps

In addition to the terminal and the editors, teeup installs other apps.

| App | Capability | Tier | Notes |
|---|---|---|---|
| Firefox Developer Edition | `firefox-developer-edition` | lazy | This is the daily browser. |
| Obsidian | `obsidian` | lazy | An app for notes. It needs macOS 12 or newer. |
| Raycast | `raycast` | lazy | A launcher for apps and commands. teeup does not change the Spotlight key. |
| Google Chrome | `chrome` | lazy | Needs macOS 13 or newer. |
| AeroSpace | `aerospace` | core | A tiling window manager. It needs macOS 13 or newer. |
| Ollama | `ollama` | lazy | Runs local language models. teeup does not download a model for you. |
| Herdr | `herdr` | lazy | An agent multiplexer that runs in your terminal. |

The browsers, Obsidian, and Raycast are Homebrew casks. If the machine uses MacPorts, teeup marks these apps as "not applicable" and shows the download page of the vendor.

## teeup launch

`teeup launch` opens an app. If the app is missing, teeup first installs the capability that provides it, and then opens it. If the app already runs, macOS brings it to the front.

```sh
teeup launch Google Chrome     # no quotes needed
teeup launch chrome            # the capability name works too
teeup launch Obsidian
```

teeup ignores the case of an app name, but you must type a capability name exactly as `teeup list` shows it. The Launch section of `teeup menu` shows every installed app.

## AeroSpace

[AeroSpace](https://github.com/nikitabobko/AeroSpace) tiles your windows in the i3 style. Read the [AeroSpace](aerospace.md) page for its keys and configuration.

<!-- SCREENSHOT: Three windows tiled by AeroSpace (WezTerm, Emacs, Firefox Developer Edition) on workspace 1. -->

## Ollama

teeup installs Ollama as the `ollama-app` cask, which includes the `ollama` command. If teeup cannot install the cask (for example, on a Mac older than macOS 14), it installs the `ollama` formula instead. When you need a model, download one:

```sh
ollama pull llama3.2
```

## Herdr

When you type `herdr`, teeup offers to install Herdr. Start Herdr in a project directory. To detach Herdr, type `ctrl+b q`. When you run `herdr` again, Herdr reattaches.
