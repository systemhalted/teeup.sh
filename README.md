<p align="center">
  <img src="assets/teeup_logo.png" alt="teeup.sh logo" width="520">
</p>

<h1 align="center">
  <img src="assets/teeup_emoji.png" alt="" width="32" height="32">
  teeup.sh
</h1>

<p align="center">
  Get your new machine ready for the first drive.
</p>

> teeup is a modular, macOS-only environment distribution (design:
> `docs/superpowers/specs/2026-09-11-omarchy-inspired-redesign-design.md`).
> It lives in `bootstrap`, `bin/teeup`, `lib/` and `capabilities/`.

## New runtime (preview)

```bash
git clone https://github.com/systemhalted/teeup.sh ~/.local/share/teeup
cd ~/.local/share/teeup
./bootstrap --dry-run     # preview everything it would do
./bootstrap               # run it
teeup status              # what is installed
teeup list                # every capability and its tier
teeup install <name>      # install and configure one capability
teeup theme set catppuccin        # re-render every app's colours, light and dark
teeup install font "Fira Code"    # switch every tool to another Nerd Font
teeup secret set <name>   # store a secret in the macOS Keychain
teeup launch cursor       # open an app, installing its cask on first use
teeup install dev-env go  # install a language runtime through mise
teeup menu                # every teeup action as a keyboard-driven list
teeup config get          # the answers, and which of them a machine file pins
teeup migrate legacy      # retire the old teeup and chezmoi wiring on this Mac
```

~/.local/bin joins your PATH through the shell layer the zsh capability installs, so teeup is spelled ~/.local/bin/teeup until you open a new terminal.

The core tier is complete: `xcode-clt`, `package-manager`, `teeup-runtime`,
`dev-dirs`, `zsh`, `starship`, `cli-tools`, `secrets`, `git`, `ssh`, `github`,
`mise`, `wezterm`, `fonts`, `aerospace`, `keyboard`, `macos-defaults`,
`theme`. The daily tier (`emacs`, `zed`, `firefox-developer-edition`,
`obsidian`) installs at bootstrap when you say yes to it. `neovim`, `vscode`
and `chrome` are lazy: `teeup install <name>` brings one in when you want it.
`teeup list` is always the source of truth.

### Finding your way around

`teeup menu` puts every action behind one list. It uses `gum` when gum is
installed, `fzf` when it is not, and a plain numbered list when neither is
there, so it works over ssh and inside a script. `teeup menu install` opens
straight at the Install submenu; inside a submenu, an empty line, `q` or
Escape goes back one level, and doing the same at the top level leaves the
menu.

The menu is `share/teeup/menu.json`: one JSON object whose keys are dotted
ids, so `install.editors.zed` is a row under `install.editors`. Each row is an
object of one-line strings:

| Field | Meaning |
|---|---|
| `label` | required; what the row shows |
| `icon` | optional; printed before the label |
| `action` | a shell command line; a row with one is a leaf, a row without one is a submenu |
| `when` | a shell condition; the row is hidden when it exits non-zero |
| `title` | header shown when the submenu is open; defaults to `label` |

`when` is why the Install list shrinks as the machine fills up: each row asks
`! teeup has <capability>`, and `teeup has` exits 0 only for something already
installed. Conditions and actions run with the checkout's `bin/` first on
`PATH`.

To add or change rows, write `~/.config/teeup/menu.json` in the same format.
An id that is also in the shipped file replaces that row **whole** and keeps
its position; an id that is not is appended. To hide a shipped row, give it
`"when": "false"`.

`teeup config` manages the answers file:

```bash
teeup config get                       # every answer, and which ones are pinned
teeup config get TEEUP_THEME           # the value the rest of teeup will see
teeup config set TEEUP_NAME Ada Lovelace
teeup config edit                      # $VISUAL or $EDITOR on the file itself
```

Precedence is your answers, then the first of `~/.config/teeup/machines/<hostname>.conf`
and the checkout's own `machines/<hostname>.conf` that exists -- that one file
wins outright, and the two are never merged, because a half-applied machine
file is worse than one file that is clearly in charge. `teeup config set`
never writes the machine file; when the machine file pins the key you are
setting, it says so, because a write that has no effect is otherwise
impossible to notice. A work identity (`TEEUP_WORK_EMAIL` and its companions)
is read only from the machine file, never from the answers, so `teeup config
set TEEUP_WORK_EMAIL ...` refuses and names the machine file to edit instead.
`teeup config edit` checks that the file still parses as shell and rolls your
edit back if it does not -- teeup sources it at the start of every command, so
a broken line would break the verb that would fix it.

### Editors

- **Emacs** runs as a daemon from the `sh.teeup.emacs` LaunchAgent, so
  `emacsclient -t` (the editor git and the shell use) always has a server;
  `emacsclient -c` (a window) also does when the daemon is a GUI build (the
  `emacs-app` cask, or MacPorts' `emacs-app` port, found under
  `/Applications`, `~/Applications` or, on MacPorts, its own applications
  directory). A terminal-only build (MacPorts' plain `emacs` port, or
  Homebrew's `emacs` formula) still runs the daemon, but `emacsclient -c`
  cannot open a window from it, which teeup says at configure time. The
  answer `TEEUP_EMACS_FLAVOR` picks the configuration: `starter` (the
  default: a thin `~/.config/emacs/init.el` over teeup's built-ins-only
  layer), `doom` (Doom cloned into `~/.config/emacs`, then
  `doom install --no-env`), `spacemacs` (cloned into `~/.emacs.d`) or `none`
  (your own configuration, untouched). The wizard asks it with the daily set;
  change it with `./bootstrap --reconfigure`, or pin it in the machine file,
  then run `teeup configure emacs`.
- **Zed** and **VS Code** keep their own `settings.json`
  (`~/.config/zed/settings.json`, which Zed reads whatever `XDG_CONFIG_HOME`
  says, and `~/Library/Application Support/Code/User/settings.json`). teeup
  sets only the theme, font and theme-extension keys in them through `jq`,
  and leaves the rest alone. Comments inside the object do not survive that
  edit, so a file that has them is backed up first; a settings file that is a
  symlink is never written.
- **Neovim** gets the LazyVim starter layout under `~/.config/nvim`, every
  file yours after the first copy, with teeup's layer on `package.path`. A
  pre-existing `~/.config/nvim/init.lua` teeup did not install is backed up
  and replaced, with the diff against your previous file printed. LazyVim
  needs Neovim 0.11.2 or later.

`teeup theme set` and `teeup install font` reach every editor teeup has
installed: each has a themed template that names the theme for the palette
(Modus for Emacs, `catppuccin-mocha`/`catppuccin-latte` for Neovim and the
Catppuccin extension for Zed and VS Code) and a hook that tells a running
editor to pick it up.

### Terminals and file icons

teeup's terminal is WezTerm, and the font teeup installs (JetBrainsMono Nerd
Font, or whichever `teeup install font` chose) reaches WezTerm, Emacs, Zed,
VS Code and Neovim. It does not reach Terminal.app or any other terminal you
use: their fonts stay as you set them.

That shows in `ls`, which the shell layer points at `eza --icons=auto`. In a
terminal whose font is not a Nerd Font, some icons still appear -- macOS finds
the older ones in the installed Nerd Font through font fallback -- but folders
and most file types show as `?` boxes, because recent eza draws them with
Material Design icons (code points U+F0000 and up) that Terminal.app does not
take from a fallback font. Either work in WezTerm, or set the other
terminal's font to the Nerd Font yourself. In Terminal.app that is
Settings > Profiles > Text > Font > "JetBrainsMono Nerd Font".

Per-machine overrides live in `~/.config/teeup/machines/<hostname>.conf` -- your own file, never in this checkout, so `git pull` never touches it -- sourced after your answers and winning over them: it is where `TEEUP_PACKAGE_MANAGER=macports` or `TEEUP_SKIP="aerospace"` belongs. (`machines/<hostname>.conf` in the checkout itself still works, checked second, for anyone who keeps a fork instead.) It is also the only place a work identity is configured -- teeup's own git/ssh/GitHub identity is a single one, `TEEUP_NAME`/`TEEUP_EMAIL` from the wizard, full stop; a machine that also needs a work identity sets `TEEUP_WORK_EMAIL` here (plus `TEEUP_WORK_GH_HOST` for a GitHub Enterprise host, or `TEEUP_WORK_GH_ACCOUNT` when work is a second account on github.com), which gives that machine a second SSH key uploaded to that identity's own GitHub host and account. See `machines/example.conf.sample`.

### Lazy capabilities

Capabilities outside the core and daily tiers use `tier=lazy`. Bootstrap does
not download them; `teeup list --tier lazy` shows each capability and how to
reach it.

```bash
docker ps                         # asks to install Colima on the first call
teeup launch cursor               # installs and opens Cursor when supported
teeup install dev-env python      # installs Python and uv through mise
claude                            # installs Claude Code through mise, then runs it
teeup install colima              # explicit install form for a capability
```

- **Shims.** `teeup configure teeup-runtime` writes one shim for each command
  in a lazy capability's `provides=` field under
  `~/.local/state/teeup/shims`. The shell appends that directory last on
  `PATH`. `teeup lazy-run` executes a real command when one exists elsewhere
  on `PATH` or under the package-manager prefix. At a terminal, a missing
  command prompts before installing and configuring its capability, skips
  requirements already recorded done, then runs with the original arguments. A
  missing requirement is still installed. Without a terminal it prints the
  corresponding `teeup install` command and exits 127. `TEEUP_SKIP` removes a
  capability's shims and makes `lazy-run` refuse it.
- **Launchers.** `teeup launch <app|capability>` uses `open -a` for an app in
  `/Applications` or `~/Applications`, installing the capability first when
  the bundle is absent. A cask-only capability such as Cursor is recorded as
  not applicable with MacPorts; Cursor also requires macOS 12 or newer.
- **Runtimes.** `teeup install dev-env <python|node|java|ruby|rust|go>` uses
  mise's global configuration from `/`, so a project `mise.toml` cannot
  redirect it, and keeps a version the user pinned. Python also installs
  `uv`; Rust uses mise's rust backend and rustup. Runtimes do not get shims,
  because macOS already provides some of their command names. `javav 21`
  switches Java for one shell.
- **AI CLIs.** Each command has one lazy capability: `ai-claude`, `ai-codex`,
  `ai-gemini`, `ai-copilot` and `ai-opencode`. Calling `claude` offers to set up
  only `ai-claude`; `teeup install ai` installs all five as an explicit bundle.
  Each leaf writes one wrapper under `~/.local/bin`, which installs its tool
  through mise on first use and runs it with `mise x` afterward. Gemini also
  loads Node. Before a download the wrapper prints
  `Installing Claude Code through mise (first run, can take a minute)...`;
  lazy capability and wrapper output is appended to
  `$TEEUP_STATE_DIR/logs/lazy.log`. An interrupted first
  download can be retried by calling the command again. A file at one of those
  paths that teeup did not write, including Claude Code's native launcher, is
  preserved.
- **Shipped lazy capabilities.** `neovim`, `vscode` and `chrome` come from the
  daily-tier phase. This phase adds `colima` (Colima, Docker CLI and Compose),
  the five `ai-*` leaves and their `ai` bundle, `herdr`, `tmux`, `ollama` (app
  and CLI where available, without model
  downloads) and `cursor`. The tmux config is copied once and remains
  user-owned; teeup skips that copy when `~/.tmux.conf` exists. `teeup status`
  lists generated shims and installed development environments.

### Keeping a Mac up to date

```bash
teeup update                  # the whole machine
DRY_RUN=true teeup update      # ... as a preview that changes nothing
teeup update wezterm          # one capability: its packages, then its configure
teeup reset starship          # the shipped starship.toml back, your copy backed up
teeup remove cursor           # undo what a capability installed
teeup doctor                  # is this Mac actually in the state teeup says?
teeup doctor git              # one capability
```

`teeup doctor` reports three outcomes, not two, and its exit status says
which: **0** means teeup verified the machine is healthy, **1** means it
found problems (each named with the one command that fixes it), and **2**
means something material could not be checked at all -- an unreadable config,
a package manager that does not answer, a GitHub host it could not reach.
That third status exists because exiting 0 about a machine teeup could not
look at is a claim it never verified; a check that cannot run says so rather
than passing quietly. Advisory notes that are not verification gaps (the
AeroSpace Accessibility step, an ssh agent holding no key yet) stay warnings
and do not change the exit status.

`teeup update` does spec section 9's list in order: `git pull --ff-only` in
the checkout, any pending migrations, `brew update && brew upgrade && brew
upgrade --cask` (or `port selfupdate && port upgrade outdated`), `mise
upgrade`, `configure` again for every installed core and daily capability
(skipping one this Mac cannot have), the theme re-rendered, and your
`post-update` hooks. Lazy capabilities are left alone -- their configure can
start a VM. A checkout with uncommitted changes stops it before anything else
runs, and so does a migration that fails; every other problem, including one
capability's `configure` failing, is a warning that lets the rest of the run
continue, and the command exits non-zero when there was one. Offline, the
pull and the package manager warn and the rest still runs, which makes
`teeup update` the repair path for a bootstrap that stopped half way.

- **Migrations** are `migrations/<epoch>.sh` in the checkout, each run once
  per machine (`teeup dev add-migration` starts one, named from the last
  commit). A fresh `./bootstrap` marks them all applied without running them.
  A file in `migrations/` not named exactly `<epoch>.sh` is announced and
  skipped rather than run. A migration that ships a changed config calls
  `migration_refresh <cap>`, which replaces the copies nobody edited and
  leaves an edited one alone.
- **`teeup reset <cap>`** re-runs the capability's own `configure` with every
  `copy_config_once` turned into "back up, replace, show the diff", so a file
  teeup renders for this machine (the zsh home files, `~/.config/git/config`)
  comes back rendered rather than as a raw template. It refuses a symlinked
  or non-writable destination, and refuses outright when it cannot back the
  file up first — a reset never overwrites a file whose backup did not
  happen. A backup whose content matched the shipped file is deleted again,
  and the theme and font hooks run afterwards, so a reset `starship.toml`
  carries the current palette.
- **`teeup remove <cap>`** runs the capability's own `remove` script when it
  has one (eleven capabilities ship one today: `macos-defaults` puts every
  preference back the way it found it, `emacs` and `keyboard` unload their
  LaunchAgents, `colima` stops the VM before Homebrew can orphan it, each of the
  five `ai-*` leaves deletes its one teeup-written wrapper, the `ai` bundle
  removes all five leaves, and `emacs` and `wezterm` also uninstall the
  MacPorts port their install put there when casks were unavailable), then
  uninstalls the casks and packages
  its metadata names, then forgets it. Your configuration files stay where
  they are. It refuses while another installed capability requires it, and it
  refuses outright rather than claim success when a capability ships no
  `remove` script and names no packages or casks: there is nothing for it to
  undo. Seven capabilities are in that position today — `dev-dirs`,
  `package-manager`, `secrets`, `ssh`, `teeup-runtime`, `theme` and
  `xcode-clt` — so `teeup remove secrets` tells you so instead of quietly
  marking it gone. A `remove` script that answers "not applicable on this
  machine" is reported too, rather than passed off as a clean removal.
- **Hooks** are your own scripts under
  `~/.config/teeup/hooks/<event>.d/`, run with `bash` in file-name order.
  The events are `post-bootstrap`, `post-update` (with the capability name
  after `teeup update <cap>`) and `theme-set` (with the theme name). Each
  directory holds an `example.sample` that documents it; `.sample` files
  never run. A hook that fails prints a warning and nothing is aborted.

### Migrating a Mac that already had teeup or chezmoi

```bash
DRY_RUN=true teeup migrate legacy   # read what it would do first
teeup migrate legacy
teeup doctor                        # names anything still left over, and how to fix it
```

`teeup migrate legacy` retires the two things this teeup replaced. It removes
what the old monolithic `teeup.sh` left in your home directory -- `~/.teeup.common`,
`~/.config/mac-setup`, and the `~/.teeupshrc` and `~/.shellrc.common` symlinks --
and neutralises the shell lines that loaded them, along with the Oh My Zsh,
Powerlevel10k and Antigen lines teeup's own zsh layer and starship replace. It
disables the SDKMAN, rbenv and pyenv init lines that would otherwise shadow
mise, and leaves those toolchains on disk: they hold versions you may still
want, and it is the shell lines, not the directories, that make them win.

Then the chezmoi half. Files chezmoi manages in your home directory are
**moved aside**, never deleted, as `<name>.teeup_backup_<timestamp>` beside the
original, so teeup can install its own version into the gap and you can lift
anything personal out of the backup. Before moving anything it lists them in
two groups -- the ones teeup ships a config for, and the ones it does not,
which only the backup copy will hold -- and asks once. The default is no, and
a run with no terminal attached moves nothing at all. Straight after moving
them, it reinstalls teeup's own version of each file it ships, for every
capability installed on this machine -- so `~/.zshrc` and the other shell
files are back before the migration says it is done, and the next terminal
has teeup's layer.

What it will never do:

- delete the chezmoi source directory, or anything inside it. On these machines
  that is `~/Work/environment/dotfiles`, which still serves Linux.
- run `chezmoi purge`, which would delete exactly that. Every chezmoi call in
  teeup goes through a wrapper that accepts only `managed`, `source-path` and
  `--version`; a test fails the build if a second call site appears anywhere.
- delete anything inside any git checkout under your home directory, or
  anything outside your home directory, whatever a config says.
- move your shell rc files aside when teeup's own zsh layer is not installed
  here -- that would leave you with no `~/.zshrc` at all. It says so and stops.

The one thing it can delete is `~/.config/chezmoi`, the config that points
chezmoi at its source, and only after asking, defaulting to no. The checkout
itself stays.

Every step runs to the end. A refusal is reported and never stops the rest,
and the exit status is non-zero when anything was left alone.

Afterwards, `teeup doctor` names what is still left over: an Oh My Zsh
directory, Powerlevel10k files, a shell file that still loads a predecessor,
chezmoi still pointing at a source directory, or a `~/.gitconfig.local` whose
`[user]` block git still reads. Each finding comes with the command that
fixes it.

### Taking teeup off a Mac

```bash
DRY_RUN=true teeup uninstall        # a preview: no questions, and nothing is changed
teeup uninstall                     # asks first; keeps packages unless you say yes
teeup uninstall --packages          # also uninstall what the capabilities installed
teeup uninstall --identity          # also the git identity teeup generated, and (if teeup put them there and you never touched them) ~/.ssh/config and git/config
teeup uninstall --yes               # no questions (needed without a terminal); takes every default
```

`teeup uninstall` works in a fixed order. First it takes teeup's lines out of
your zsh home files, before anything they load is removed: a `~/.zshrc`
teeup installed and you never edited is replaced by a short one of your own
(never deleted, so zsh always has one), `~/.zshenv` and `~/.zprofile` go, and
in a file you edited only teeup's lines are disabled, with a copy of the file
as it was beside it. Then every installed capability comes off, dependents
first, through the same removal `teeup remove` uses -- packages only when you
ask for them, which is also true of what the AI tools installed through
mise. teeup's LaunchAgents are unloaded next; then every config file teeup
copied and you never edited is removed, and every one you edited stays; and
last, once the run has gone cleanly, teeup's own command, config and state
come off: `~/.config/teeup` loses only the files teeup wrote, and stays --
with anything of yours in it named instead -- when a machine file, a hook or
a theme of your own is there too; `~/.local/state/teeup` loses only the
entries teeup itself wrote there, and only once teeup can tell the directory
is really its own (a `cap-*` install marker inside its `done/` directory) --
anything else it finds there stays, named; and `~/.local/bin/teeup` goes
last (wherever `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `TEEUP_CONFIG_DIR` and
`TEEUP_STATE_DIR` put the first two).

What it keeps unless you say otherwise: the packages and apps (it asks,
defaulting to no; Homebrew or MacPorts itself stays either way; while the
packages stay, so do mise and the tools it manages, and a new shell needs
the printed `mise activate` line the same way it needs Homebrew's or
MacPorts' own); your SSH
keys, always -- teeup never deletes one, with or without `--identity`, and
instead names each one with the commands that drop its Keychain passphrase
and move it aside by hand; and, without `--identity`, your git identity and
a pristine `~/.ssh/config` or `~/.config/git/config`. `--identity` takes off
what it can of that: the git identity file teeup generated,
`~/.config/git/local` (moved aside rather than deleted, since teeup never
wrote it), and `~/.ssh/config` and `~/.config/git/config` if teeup put them
there and you left them alone. What it never removes: Homebrew or MacPorts,
the Xcode Command Line Tools, `~/Work`, the secrets in your Keychain, and
the checkout itself. The summary names each one with the command that
removes it by hand, and when a file teeup replaced at install time is still
beside it as a `.teeup_backup_*` copy, it offers to put that back.

It refuses anything outside your home directory, anything inside a git
checkout, and any symlink it would have to write through, and it will not
uninstall the zsh your login shell runs. A refusal or a failure makes it exit
non-zero and keeps teeup's own state and command in place, so running it
again after you fix the cause finishes the job -- the command it prints
carries whichever of `--packages`, `--identity` and `--yes` this run needed,
so pasting it back just works. A second run on a clean Mac changes nothing.
The shell you ran it from still has teeup's hooks loaded, so open a new
terminal afterwards.
