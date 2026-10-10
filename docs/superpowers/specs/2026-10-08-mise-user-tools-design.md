# User tools through mise, pinned to the teeup release

Date: 2026-10-08. Status: draft for the owner's review. Issue: #112.

## Goal

The version of every command-line tool that teeup installs for the user is
fixed by the teeup release, and it changes only when the checkout moves to
a new release. Since 0.3.0-beta, `teeup update` follows releases, so tools
change only when teeup changes. Today `teeup update` runs `brew upgrade`
and `mise upgrade`, so the tools move to the newest version on every update,
whatever release is checked out.

The owner's rule (#112, 2026-10-08):

- **What teeup itself needs comes from the package manager** (Homebrew or
  MacPorts).
- **The tools the user uses come from mise**, at exact versions, with no
  per-call cost. Omarchy's `mise use -g` + `mise x` wrapper adds about
  120 ms to each call; this design adds nothing.

## The split

| Source | Tools | Why |
|---|---|---|
| Package manager | the package manager, mise, git, gh, gum, jq | teeup needs them: to install, for its checkout and updates, to sign in, for the wizard and its JSON edits |
| Package manager | zsh, zsh-completions, zsh-autosuggestions, zsh-syntax-highlighting | teeup's shell layer; the plugins are not binaries |
| Package manager | curl, wget, tree, gnupg | mise has no package |
| Package manager | btop | no macOS build upstream |
| Package manager | colima, docker, docker-compose | colima needs lima, which the package manager installs as a dependency |
| Package manager | every cask | mise does not install apps |
| mise | ripgrep, fd, fzf, bat, eza, zoxide, yq, tealdeer, dust, delta, git-lfs, lazygit, starship, neovim, tmux, herdr, ollama (the CLI) | user tools, each with an `aqua:` source that checks checksums |

jq is in the first group only: teeup needs it, and the user gets the same
copy. The `ollama-app` cask stays a cask.

## Design

### The lock file

`share/teeup/tools.lock` is the one list of pinned versions. Each line is
`<mise tool> <version>`, for example `ripgrep 14.1.1`. A release changes it
in its release PR. A test checks that every tool named in any capability's
metadata has exactly one lock line, and that the lock names nothing else.

### Capability metadata

A new field, `mise_tools="<tool>:<command> ..."`, lists a capability's mise
tools with the command each provides, for example
`mise_tools="ripgrep:rg fd:fd tealdeer:tldr"` in cli-tools. These tools
leave `packages` and `package_commands`. `cap_check` validates the field:
pairs are well formed, each tool has a lock line, and no command appears in
two capabilities.

| Capability | `packages` after | `mise_tools` |
|---|---|---|
| cli-tools | jq btop tree wget curl gnupg | ripgrep:rg fd:fd fzf:fzf bat:bat eza:eza zoxide:zoxide yq:yq tealdeer:tldr dust:dust |
| git | git | delta:delta git-lfs:git-lfs lazygit:lazygit |
| starship | — | starship:starship |
| neovim | — | neovim:nvim |
| tmux | — | tmux:tmux |
| herdr | — | herdr:herdr |
| ollama | (cask `ollama-app` only) | ollama:ollama |

Capabilities that now have only `mise_tools` gain `requires=mise`.

### Install order

`capabilities/core.list` moves `mise` to just after `teeup-runtime` and
before `zsh`, `starship`, `cli-tools` and `git`. mise needs only the
package manager. For the AI CLIs, nothing else changes.

### `lib/mise.sh`: new functions

Every call keeps the `-C /` rule.

- `mise_tools_conf_write` writes `~/.config/mise/conf.d/teeup.toml` from
  the lock, listing only the tools of installed capabilities. The file
  carries a teeup marker and is teeup's own. The user's
  `~/.config/mise/config.toml` is never edited for these tools. Because
  the versions are in a mise config, `mise prune` keeps them.
- `mise_tool_install <tool> <command>`:
  1. Read the version from the lock.
  2. If needed, `mise -C / install <tool>@<version>`.
  3. Find the binary with `mise -C / which --tool <tool>@<version>
     <command>`.
  4. Point `~/.local/bin/<command>` at it with a symlink. A file there that
     teeup did not create is kept, with a warning, as `mise_wrapper_write`
     does today. (Changed to two-hop links in review: `~/.local/bin/<command>`
     points at `~/.local/state/teeup/tools/<command>`, which points at the
     binary.)
- `mise_tool_remove <tool> <command>` removes the link if it is teeup's. When
  packages are removed, it also runs `mise -C / uninstall <tool>@<version>`,
  then rewrites the conf.d file.

The link means a call runs the binary directly: no mise process, no
wrapper. If a tool needs to know its install path (for example Neovim
finds its runtime files next to the binary), the link may not work. Then
that tool gets a two-line script that `exec`s the absolute path; bash
startup costs about 1 ms. The Mac verification below decides which tools
need it.

### Install, configure, update

- A capability's `install` runs `mise_tool_install` for each pair in
  `mise_tools`, next to the `pkg_install` calls for its `packages`.
- `configure` rewrites the conf.d file and repairs a missing link, so
  `teeup configure <cap>` is the repair path.
- `teeup update`:
  - It refreshes the conf.d file and runs `mise_tool_install` for every
    installed capability's tools. A tool whose lock version changed is
    installed and re-linked.
  - The old version is left installed. `mise prune` removes it later.
  - `mise_upgrade` stays for what the user added with `mise use -g`. Pinned
    exact versions do not move with `mise upgrade`.
- Package-manager formulae cannot be pinned. `pkg_upgrade_all` runs only
  when `_update_checkout` moved the checkout to a different commit, which
  means a new release, or new commits on the main channel. An update that
  stays on the same release leaves them alone.

### Lazy tools

neovim, tmux, herdr and ollama stay lazy. Their shims in
`~/.local/state/teeup/shims` remain last on `PATH`. The first call installs
the capability through `cmd_lazy_run`, which now runs `mise_tool_install`.
After that the link in `~/.local/bin` comes first, so the shim no longer
fires.

### PATH

`~/.local/bin` already comes before the Homebrew and MacPorts directories
(`capabilities/zsh/default/env`). The mise link therefore wins over an old
Homebrew copy in every shell.

In shells that run `mise activate`, mise puts its own install directories
first. For teeup's tools these hold the same pinned version. A version the
user sets for a tool in their own `config.toml` wins there, by design. The
Mac verification checks the order between `config.toml` and `conf.d`.

### Doctor

`doctor_metadata_check` gains a `mise_tools` pass for each tool:

- **ok:** the link exists, points into the pinned install, and the command
  runs (`command_runs`).
- **failure:** the link is missing, or its target is gone (for example after
  `mise uninstall`). The fix is `teeup configure <cap>`.
- **notice:** the package manager still has an old copy of the tool. The
  notice prints `brew uninstall <pkg>` (or `sudo port uninstall <pkg>`).
  teeup does not remove it. Whether it should is an open question (#112).

The #109/#110 shadowing checks keep working for the package-manager group.

### Existing Macs

A migration does the move:

1. Write the conf.d file.
2. For every installed capability, run `mise_tool_install` for its tools.

The old Homebrew or MacPorts copies stay installed, and doctor prints the
command to remove them. `teeup update`'s `pkg_upgrade_all` no longer names
these packages, so they stop being upgraded.

### Remove and uninstall

- `teeup remove <cap>` removes the links and, with packages, the pinned
  installs (`mise_tool_remove`).
- `teeup uninstall`:
  - It removes the links and the conf.d file.
  - With `--packages`, it also uninstalls the pinned versions.
  - The summary lists the mise commands next to the `brew uninstall` lines.

### MacPorts

A MacPorts Mac gets the same mise tools as a Homebrew Mac. The `tldr` to
`tealdeer` mapping in `package_candidates` is no longer needed for
cli-tools. btop and colima stay on ports. The
`docker-compose` port is Compose v1 (1.29.2); the colima capability gets a
separate check, outside this change.

## Docs

- Manual, Runtimes "Homebrew or mise?": the rule changes to "teeup's own
  tools from the package manager, your tools from mise at the release's
  versions".
- Manual, Updates: tools change only with a new release.
- Manual, Doctor: the old-copy notice.
- CONTRIBUTING step 6 (how to choose a source), and the new `mise_tools`
  field.
- CHANGELOG.

## Verification

Tests, all run inside the shellenv sandbox:

- `tests/lib/mise.sh`:
  - the conf.d file is written from the lock for installed capabilities only;
  - `mise_tool_install` runs `install` with the pinned version, then links
    the `which` result;
  - a foreign file at the link path is kept;
  - remove deletes only teeup's link;
  - every mise call uses `-C /`.
- `tests/lib/capability.sh`: `cap_check` rejects a bad `mise_tools` pair, a
  tool without a lock line, and a command in two capabilities.
- `tests/docs.sh` or a new suite: the lock and the metadata agree.
- `tests/lib/doctor.sh`: ok, missing link, dangling link, and the old-copy
  notice with the right uninstall command for each backend.
- `tests/cli.sh`: `teeup update` upgrades package-manager formulae only when
  the checkout moved, and re-links a tool whose lock version changed.
- `tests/lib/migrations.sh`: the migration links the tools and leaves the
  Homebrew copies installed.

On a Mac, before the release (the owner):

1. For each tool in the mise group:
   - `mise -C / install <tool>@<version>` works through `aqua:`, on Apple
     Silicon and on Intel;
   - the linked command runs;
   - Neovim, tmux and starship work through a link.
2. Order of `conf.d/teeup.toml` and `config.toml` under `mise activate`.
3. A work-network run: mise downloads through the CA bundle teeup exports.
4. On an existing Mac: the migration, the doctor notice, and that `rg`,
   `nvim` and `starship` resolve to `~/.local/bin`.

## Out of scope

- Removing the old Homebrew or MacPorts copies automatically.
- Moving `gh` to mise. teeup needs it, so it stays on the package manager.
- Pinning package-manager formulae, which Homebrew cannot do.
- The MacPorts Compose v1 gap.
