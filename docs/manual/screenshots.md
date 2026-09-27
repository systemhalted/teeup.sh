# teeup Manual screenshots

The screenshots the manual pages ask for. Each page marks the spot with an
HTML comment, `<!-- SCREENSHOT: <what to capture> -->`, which does not render.
Capture them on the macOS VM, save them under `docs/manual/src/images/` with
short descriptive names, replace the comment with the image and its alt text,
and tick the entry here. This file sits outside `src/`, so it is not published.

## Part 1: The Basics

### Welcome to teeup (`src/welcome.md`)

- [ ] A WezTerm window on a freshly bootstrapped Mac, showing the Starship
  prompt and the output of `teeup status`.

### Getting started (`src/getting-started.md`)

- [ ] The bootstrap wizard in Terminal.app with gum, showing the "Install the
  daily set too (Emacs, Zed, Firefox Developer Edition, Obsidian)?"
  confirmation.
- [ ] The end of a real ./bootstrap run, showing "Bootstrap finished in ..."
  and the "Open a new terminal" hint.

### The teeup command (`src/the-teeup-command.md`)

- [ ] Terminal output of `teeup help` in WezTerm, full height so every verb is
  visible.

### The menu (`src/the-menu.md`)

- [ ] `teeup menu` at the top level in WezTerm with gum, showing Install,
  Launch, Style, Check, Setup and Update.
- [ ] The Install submenu in gum, showing Editors, Apps, AI, Shell and
  containers, Language runtimes and the ".." row.
- [ ] The same Install submenu drawn by the numbered-list fallback (run:
  TEEUP_MENU_PICKER=plain teeup menu install), showing the "Choice (empty or q
  to go back):" prompt.

### Tiers (`src/tiers.md`)

- [ ] Output of `teeup list --tier lazy`, showing the "[on first: ...]" and
  "launch: ..." column.
- [ ] Typing `docker ps` on a fresh Mac, showing the "docker is provided by
  capability colima. Install now?" prompt in gum.

## Part 3: The Applications

### Terminal (`src/terminal.md`)

- [ ] A WezTerm window with two panes side by side (leader then 3) and the tab
  bar showing the workspace name and clock on the right.

### Emacs (`src/emacs.md`)

- [ ] An Emacs window opened with `e README.md` from WezTerm, showing the
  teeup starter layer with the current theme.

### Other editors (`src/other-editors.md`)

- [ ] Zed and VS Code side by side after `teeup theme set`, both showing the
  same palette.

### AI tools (`src/ai-tools.md`)

- [ ] WezTerm after typing `claude` on a fresh Mac, showing the "Install now?"
  prompt and then the "Installing Claude Code through mise (first run, can
  take a minute)..." line.

### Shell tools (`src/shell-tools.md`)

- [ ] `ll` in a project directory in WezTerm, showing eza's icons and git
  status column.

### Containers (`src/containers.md`)

- [ ] The first `docker ps` on a fresh Mac: the Install now? prompt, the
  colima start output, and the empty container list.

### Apps (`src/apps.md`)

- [ ] Three windows tiled by AeroSpace (WezTerm, Emacs, Firefox Developer
  Edition) on workspace 1.

## Part 4: Configuration

## Part 5: Moving In and Out

### Migrating (`src/migrating.md`)

- [ ] `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and
  chezmoi, showing the "[DRY-RUN] Would ..." lines and the two lists of
  chezmoi files.

### Uninstall (`src/uninstall.md`)

- [ ] The end of `DRY_RUN=true teeup uninstall`, showing the "teeup uninstall
  summary" with its "Would remove" and "Kept" sections and the "Run it for
  real with:" line.

## Part 6: Help

### Doctor and troubleshooting (`src/doctor-and-troubleshooting.md`)

- [ ] `teeup doctor` on a healthy Mac, ending with "teeup doctor: everything
  checked is healthy."
