# Runtimes

teeup controls language runtimes with [mise](https://mise.jdx.dev). mise is in the core tier, but the languages are not. You install the languages that you use, with one command for each language.

```sh
teeup install dev-env python
```

| Language | Command | What it installs |
|---|---|---|
| Python | `teeup install dev-env python` | The latest Python, and [uv](https://docs.astral.sh/uv/) |
| Node | `teeup install dev-env node` | The latest Node |
| Java | `teeup install dev-env java` | The latest Java |
| Ruby | `teeup install dev-env ruby` | The latest Ruby |
| Rust | `teeup install dev-env rust` | The latest Rust, through mise's rust backend, which uses rustup |
| Go | `teeup install dev-env go` | The latest Go |

`teeup status` lists the installed languages below "Dev envs", and the menu shows them below "Install", then "Language runtimes".

## Homebrew or mise?

teeup installs a tool with mise when you need more than one version of it. It uses Homebrew or MacPorts when one current version is correct for the whole Mac.

mise installs these items:
- Language runtimes. Projects specify their own versions in `mise.toml`, and `mise activate` changes between them when you change directories. Homebrew keeps one version of each formula.
- The AI command-line tools: Claude Code, Codex, Gemini CLI, Copilot CLI, and OpenCode. mise downloads each tool the first time that you run it.

Homebrew or MacPorts installs the other tools. These include the command-line tools (ripgrep, fd, bat, jq, and the rest), git, delta, lazygit, the GitHub CLI, tmux, Neovim, Starship, and mise. Homebrew installs the apps from Homebrew casks. MacPorts has no casks, so with MacPorts, WezTerm and Emacs come from ports and teeup tells you to download the other apps yourself.

`teeup update` upgrades the packages that teeup installed, and runs `mise upgrade` for the tools in your global mise configuration.

Most capabilities accept a copy of their command that you installed a different way, such as your own ripgrep, if its version command runs. A broken command or a stale shim on `PATH` does not replace the package.

The GitHub CLI is an exception: teeup always installs its own `gh`, because git uses `gh` to sign in. `teeup doctor github` warns when a different `gh` comes first on `PATH`. If you add a tool to mise yourself with `mise use -g`, you must control that tool yourself.

## Where the versions live

Each runtime goes into your global mise configuration, `~/.config/mise/config.toml`. teeup runs mise from `/` for this, so a `mise.toml` file in the current project cannot redirect the installation. If you already specified a version there, teeup keeps it and does not replace it with the latest version.

Project versions operate the usual mise way, with a `mise.toml` file in the project that you write by hand or with `mise use`. The teeup shell runs `mise activate zsh`, so the correct version is on `PATH` when you move between directories. `teeup update` runs `mise upgrade` for the global tools.

The new runtime is on `PATH` at the next prompt in the shell where you ran the command. Other shells find the new runtime after you open a new terminal.

## No shims for runtimes

Lazy capabilities get shims (see [Tiers](tiers.md)), but runtimes do not. macOS already has commands such as `python3`, `ruby`, and `java`, and a teeup shim must never replace them. When you type `python`, teeup does not ask you to install anything. Run `teeup install dev-env python` to install Python.

## Rust

mise installs Rust through rustup, which puts toolchains in `~/.rustup` and `~/.cargo`. The teeup shell puts `~/.cargo/bin` on `PATH`, so the shell finds the packages that you install with `cargo install`. `~/.cargo/bin` comes after `~/.local/bin` on `PATH`, so a cargo binary never replaces a teeup wrapper.

## Java and javav

The `javav` command changes Java for the current shell only.

| Command | What it does |
|---|---|
| `javav 21` | Install Corretto 21 if necessary and use it in this shell |
| `javav zulu-17` | The same, for a different vendor and version |
| `javav` | Show `JAVA_HOME`, the `java` on `PATH`, and its version |

A version number without a vendor name means Corretto. To use a different vendor as the default, set `JAVAV_VENDOR` in `~/.config/zsh/local.zsh`, for example `export JAVAV_VENDOR=zulu`.

## Go

The teeup shell sets `GOPATH` to `~/Development/GoWorkspace` if you did not set it yourself. It adds the `bin` directory of the workspace to `PATH` when that directory exists.
