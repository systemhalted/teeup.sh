# teeup Manual screenshots

This document lists the screenshots that the manual pages need. Each page
marks the location with an HTML comment, `<!-- SCREENSHOT: <what to capture> -->`,
which the published manual does not show.

1. Capture the screenshots on the macOS VM.
2. Save them in `docs/manual/src/images/` with short descriptive names.
3. Replace the HTML comment with the image and its alt text.
4. Select the check box for the entry in this document.

mdBook does not publish this file, because it is outside `src/`.

## Part 1: The Basics

### Welcome to teeup (`src/welcome.md`)

- [ ] A WezTerm window on a new, bootstrapped Mac that shows the Starship prompt and the output of `teeup status`.

### Getting started (`src/getting-started.md`)

- [ ] The bootstrap wizard in Terminal.app with gum, which shows the "Install the daily set too (Emacs, Zed, Firefox Developer Edition, Obsidian)?" confirmation.
- [ ] The end of a real `./bootstrap` run, which shows "Bootstrap finished in ..." and the "Open a new terminal" hint.

### The teeup command (`src/the-teeup-command.md`)

- [ ] Terminal output of `teeup help` in WezTerm, at full height so that every verb is visible.

### The menu (`src/the-menu.md`)

- [ ] `teeup menu` at the top level in WezTerm with gum, which shows Install, Launch, Style, Check, Setup and Update.
- [ ] The Install submenu in gum, which shows Editors, Apps, AI, Shell and containers, Language runtimes and the ".." row.
- [ ] The same Install submenu from the numbered-list fallback (run `TEEUP_MENU_PICKER=plain teeup menu install`), which shows the "Choice (empty or q to go back):" prompt.

### Tiers (`src/tiers.md`)

- [ ] Output of `teeup list --tier lazy`, which shows the "[on first: ...]" and "launch: ..." column.
- [ ] `docker ps` on a new Mac, which shows the "docker is provided by capability colima. Install now?" prompt in gum.

## Part 3: The Applications

### Terminal (`src/terminal.md`)

- [ ] A WezTerm window with two panes side by side (leader then 3) and a tab bar that shows the workspace name and clock on the right.

### Emacs (`src/emacs.md`)

- [ ] An Emacs window that `e README.md` opens from WezTerm, which shows the teeup starter layer with the current theme.

### Other editors (`src/other-editors.md`)

- [ ] Zed and VS Code side by side after `teeup theme set`, both with the same palette.

### AI tools (`src/ai-tools.md`)

- [ ] WezTerm after you type `claude` on a new Mac, which shows the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line.

### Shell tools (`src/shell-tools.md`)

- [ ] `ll` in a project directory in WezTerm, which shows the eza icons and the git status column.

## Part 2: Look and Feel

### Themes (`src/themes.md`)

- [ ] The theme picker from `teeup theme set`, which shows the available themes.

### Containers (`src/containers.md`)

- [ ] The first `docker ps` on a new Mac, which shows the Install now? prompt, the colima start output, and the empty container list.

### Apps (`src/apps.md`)

- [ ] Three windows (WezTerm, Emacs, Firefox Developer Edition) that AeroSpace tiles on workspace 1.

## Part 4: Configuration

## Part 5: Moving In and Out

### Migrating (`src/migrating.md`)

- [ ] `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and chezmoi, which shows the "[DRY-RUN] Would ..." lines and the two lists of chezmoi files.

### Uninstall (`src/uninstall.md`)

- [ ] The end of `DRY_RUN=true teeup uninstall`, which shows the "teeup uninstall summary" with its "Would remove" and "Kept" sections and the "Run it for real with:" line.

## Part 6: Help

### Doctor and troubleshooting (`src/doctor-and-troubleshooting.md`)

- [ ] `teeup doctor` on a healthy Mac, which ends with "teeup doctor: everything checked is healthy."
