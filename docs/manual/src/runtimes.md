# Runtimes

teeup manages language runtimes with [mise](https://mise.jdx.dev). mise is in the core tier; the languages are not. You add the ones you use, one command each.

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

One language per command. `teeup status` lists the ones you have under "Dev envs", and the menu offers them under Install, then Language runtimes.

## Where the versions live

Each runtime goes into your global mise configuration, `~/.config/mise/config.toml`. teeup runs mise from `/` for this, so a `mise.toml` in whatever project you happen to be in cannot redirect the install. If you already pinned a version there, teeup keeps it rather than replacing it with the latest.

Project versions work the usual mise way: a `mise.toml` in the project, written by hand or with `mise use`. teeup's shell runs `mise activate zsh`, so the right version is on `PATH` as you move between directories. `teeup update` runs `mise upgrade` for the global tools.

The new runtime is on `PATH` at the next prompt in the shell you ran the command in. Other shells pick it up once you open a new terminal.

## No shims for runtimes

Lazy capabilities get shims (see [Tiers](tiers.md)), but runtimes do not. macOS already has commands such as `python3`, `ruby` and `java`, and a teeup shim must never stand in front of them. So typing `python` does not offer to install anything; run `teeup install dev-env python` instead.

## Rust

mise installs Rust through rustup, which puts toolchains in `~/.rustup` and `~/.cargo`. teeup's shell puts `~/.cargo/bin` on `PATH`, so anything you `cargo install` is found, but after `~/.local/bin`, so a cargo binary never shadows one of teeup's wrappers.

## Java and javav

`javav` switches Java for the current shell only:

| Command | What it does |
|---|---|
| `javav 21` | Install Corretto 21 if needed and use it in this shell |
| `javav zulu-17` | The same, for another vendor and version |
| `javav` | Show `JAVA_HOME`, the `java` on `PATH`, and its version |

A bare version number means Corretto. To default to another vendor, set `JAVAV_VENDOR` in `~/.config/zsh/local.zsh`, for example `export JAVAV_VENDOR=zulu`.

## Go

teeup's shell sets `GOPATH` to `~/Development/GoWorkspace` unless you set it yourself, and adds its `bin` directory to `PATH` when it exists.
