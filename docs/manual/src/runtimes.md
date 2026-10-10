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

teeup uses two sources. The tools that teeup itself needs come from Homebrew or MacPorts. The tools that you use come from mise, at the versions of the teeup release.

| Source | Tools |
|---|---|
| Homebrew or MacPorts | mise, git, the GitHub CLI, gum, jq, zsh and its plugins, curl, wget, tree, GnuPG, btop, Colima and Docker, and every app |
| mise, at the versions of the release | ripgrep, fd, fzf, bat, eza, zoxide, yq, tealdeer (`tldr`), dust, delta, git-lfs, lazygit, Starship, Neovim, tmux, Herdr, and the Ollama command |
| mise, at the versions that you choose | Language runtimes, the AI command-line tools, and every tool that you add with `mise use -g` |

The file `share/teeup/tools.lock` in the teeup checkout records the versions of the second row. A new teeup release can change these versions. teeup installs each tool with mise and links it in two steps. The link in `~/.local/bin` points to a link in `~/.local/state/teeup/tools`, and that link points to the tool. A command then starts the tool directly, without mise, so it starts as fast as a Homebrew copy.

teeup records the same versions in `~/.config/mise/conf.d/teeup.toml`, so `mise prune` keeps them. teeup never edits your `~/.config/mise/config.toml`. mise reads both files, and its own rules decide which version applies. See the [mise configuration](https://mise.jdx.dev/configuration.html) page.

Language runtimes come from mise because projects need different versions. Each project specifies its versions in `mise.toml`, and `mise activate` changes between them when you change directories. mise downloads each AI tool the first time that you run it.

A Mac with MacPorts gets the same tools from mise as a Mac with Homebrew. MacPorts has no casks, so with MacPorts, WezTerm and Emacs come from ports and teeup tells you to download the other apps yourself.

`teeup update` installs a new pinned version when a release changes it. It upgrades the Homebrew or MacPorts packages only when it moves teeup to a new commit. It also runs `mise upgrade` for the tools in your global mise configuration. See [Updates](updates.md).

Most capabilities accept a copy of their command that you installed a different way, such as your own jq, if its version command runs. A broken command or a stale shim on `PATH` does not replace the package. A file of your own at `~/.local/bin/rg`, or at the path of another pinned tool, stays, and teeup does not link that tool. teeup owns a link in `~/.local/bin` only when it points into `~/.local/state/teeup/tools`. If you link a tool to a mise install yourself, your link stays, and `teeup remove` does not uninstall that version.

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
