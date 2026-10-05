# Runtimes

teeup controls language runtimes with [mise](https://mise.jdx.dev). mise is in the core tier. The languages are not in the core tier. You install the languages that you use. You use one command for each language.

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

You install one language per command. The `teeup status` command lists the installed languages below "Dev envs". The menu shows the languages below "Install", then "Language runtimes".

## Homebrew or mise?

teeup installs a tool with mise when you need more than one version of the tool. teeup installs a tool with Homebrew or MacPorts when one current version is correct for the whole Mac.

mise installs these items:
- Language runtimes. Projects specify their own versions in `mise.toml`. The `mise activate` command changes between the versions when you change directories. Homebrew keeps one version of each formula.
- The AI command-line tools. These tools include Claude Code, Codex, Gemini CLI, Copilot CLI, and OpenCode. mise downloads each tool the first time that you run the tool.

Homebrew or MacPorts installs the other tools. These tools include the command-line tools (ripgrep, fd, bat, jq, and the rest), git, delta, lazygit, the GitHub CLI, tmux, Neovim, Starship, and mise. Homebrew installs the apps from Homebrew casks. MacPorts has no casks. When you use MacPorts, MacPorts installs WezTerm and Emacs from ports. teeup tells you to download the other apps yourself.

The `teeup update` command upgrades the packages that teeup installed. This command also runs `mise upgrade` for the tools in your global mise configuration.

Most capabilities accept a copy of a command that you installed a different way. For example, you can use a ripgrep installation that you already have. teeup accepts the command only if its version command runs. A broken command or a stale shim on `PATH` does not replace the package.

The GitHub CLI is an exception. teeup always installs its own `gh`. git uses `gh` to sign in. The `teeup doctor github` command warns when a different `gh` comes first on `PATH`. When you add a tool to mise with `mise use -g`, you must control the tool yourself.

## Where the versions live

Each runtime goes into your global mise configuration, `~/.config/mise/config.toml`. teeup runs mise from `/` for this operation. A `mise.toml` file in the current project cannot redirect the installation. If you already specified a version in the global configuration, teeup keeps the version. teeup does not replace the version with the latest version.

Project versions operate the usual mise way. You write a `mise.toml` file in the project by hand or with `mise use`. The shell of teeup runs `mise activate zsh`. The correct version is on `PATH` when you move between directories. The `teeup update` command runs `mise upgrade` for the global tools.

The new runtime is on `PATH` at the next prompt in the shell where you ran the command. Other shells find the new runtime after you open a new terminal.

## No shims for runtimes

Lazy capabilities get shims, but runtimes do not get shims. You can read [Tiers](tiers.md) for more information. macOS already has commands such as `python3`, `ruby`, and `java`. A teeup shim must never replace these commands. When you type `python`, teeup does not ask you to install the tool. Run `teeup install dev-env python` to install Python.

## Rust

mise installs Rust through rustup. rustup puts toolchains in `~/.rustup` and `~/.cargo`. The shell of teeup puts `~/.cargo/bin` on `PATH`. This configuration makes sure that the system finds the packages that you install with `cargo install`. The system searches `~/.cargo/bin` after `~/.local/bin`. Because of this sequence, a cargo binary never replaces a teeup wrapper.

## Java and javav

The `javav` command changes Java for the current shell only.

| Command | What it does |
|---|---|
| `javav 21` | Install Corretto 21 if necessary and use the version in this shell |
| `javav zulu-17` | Install a different vendor and version, and use the version in this shell |
| `javav` | Show `JAVA_HOME`, the `java` on `PATH`, and the version |

A version number without a vendor name means Corretto. If you want to use a different vendor as the default vendor, set `JAVAV_VENDOR` in `~/.config/zsh/local.zsh`. For example, write `export JAVAV_VENDOR=zulu` in the file.

## Go

The shell of teeup sets `GOPATH` to `~/Development/GoWorkspace`. If you set `GOPATH` yourself, the shell does not change the variable. The shell adds the `bin` directory of the workspace to `PATH` when the directory exists.
