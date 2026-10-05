# Apps

teeup installs the terminal and the editors. teeup also installs other apps.

| App | Capability | Tier | Notes |
|---|---|---|---|
| Firefox Developer Edition | `firefox-developer-edition` | lazy | This is the daily browser. |
| Obsidian | `obsidian` | lazy | This app is for notes. This app needs macOS 12 or a newer version. |
| Google Chrome | `chrome` | lazy | This app needs macOS 13 or a newer version. |
| AeroSpace | `aerospace` | core | This app is a tiling window manager. This app needs macOS 13 or a newer version. |
| Ollama | `ollama` | lazy | This app uses local language models. teeup does not download a model for you. |
| Herdr | `herdr` | lazy | This app is an agent multiplexer. This app runs in your terminal. |

The browsers and Obsidian are Homebrew casks. If the machine uses MacPorts, teeup marks these apps as "not applicable". teeup shows the download page of the vendor.

## teeup launch

`teeup launch` opens an app. If the app is missing, teeup installs the capability that provides the app. Then, teeup opens the app. If the app already runs, macOS brings the app to the front.

```sh
teeup launch Google Chrome     # no quotes needed
teeup launch chrome            # the capability name works too
teeup launch Obsidian
```

teeup ignores the case of an app name. You must type a capability name exactly as `teeup list` shows it. The Launch section of `teeup menu` shows every installed app.

## AeroSpace

[AeroSpace](https://github.com/nikitabobko/AeroSpace) tiles your windows in the i3 style. Read the [AeroSpace](aerospace.md) page for the keys and the configuration.

<!-- SCREENSHOT: Three windows tiled by AeroSpace (WezTerm, Emacs, Firefox Developer Edition) on workspace 1. -->

## Ollama

teeup installs Ollama as the `ollama-app` cask. This cask includes the `ollama` command. If teeup cannot install the cask, teeup installs the `ollama` formula instead. For example, teeup cannot install the cask on a Mac that is older than macOS 14. When you need a model, download one:

```sh
ollama pull llama3.2
```

## Herdr

If you type `herdr`, teeup asks if you want to install Herdr. Start Herdr in a project directory. To detach Herdr, type `ctrl+b q`. When you run `herdr` again, Herdr reattaches.
