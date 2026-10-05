# teeup Manual screenshots

This document has a list of the screenshots for the manual.
Each page has an HTML comment, `<!-- SCREENSHOT: <what to capture> -->`.
This HTML comment shows the location for the screenshot.
The published manual does not show the HTML comment.

Capture the screenshots on the macOS VM.
Save the screenshots in the `docs/manual/src/images/` directory.
Use short descriptive names for the images.
Replace the HTML comment with the image and its alt text.
Select the check box for the entry in this document.
mdBook does not publish this file, because it is outside the `src/` directory.

## Part 1: The Basics

### Welcome to teeup (`src/welcome.md`)

- [ ] A WezTerm window on a new, bootstrapped Mac. The window shows the Starship prompt and the output of `teeup status`.

### Getting started (`src/getting-started.md`)

- [ ] The bootstrap wizard in Terminal.app with gum. The wizard shows the "Install the daily set too (Emacs, Zed, Firefox Developer Edition, Obsidian)?" confirmation.
- [ ] The end of a real `./bootstrap` run. The output shows "Bootstrap finished in ..." and the "Open a new terminal" hint.

### The teeup command (`src/the-teeup-command.md`)

- [ ] Terminal output of `teeup help` in WezTerm. The window is full height so that every verb is visible.

### The menu (`src/the-menu.md`)

- [ ] `teeup menu` at the top level in WezTerm with gum. The output shows Install, Launch, Style, Check, Setup and Update.
- [ ] The Install submenu in gum. The submenu shows Editors, Apps, AI, Shell and containers, Language runtimes and the ".." row.
- [ ] The numbered-list fallback draws the same Install submenu. Run `TEEUP_MENU_PICKER=plain teeup menu install`. The submenu shows the "Choice (empty or q to go back):" prompt.

### Tiers (`src/tiers.md`)

- [ ] Output of `teeup list --tier lazy`. The output shows the "[on first: ...]" and "launch: ..." column.
- [ ] The output of `docker ps` on a new Mac. The output shows the "docker is provided by capability colima. Install now?" prompt in gum.

## Part 3: The Applications

### Terminal (`src/terminal.md`)

- [ ] A WezTerm window with two panes side by side (leader then 3). The tab bar shows the workspace name and clock on the right.

### Emacs (`src/emacs.md`)

- [ ] An Emacs window that you open with `e README.md` from WezTerm. The window shows the teeup starter layer with the current theme.

### Other editors (`src/other-editors.md`)

- [ ] Zed and VS Code side by side after `teeup theme set`. Both editors show the same palette.

### AI tools (`src/ai-tools.md`)

- [ ] WezTerm after you type `claude` on a new Mac. The output shows the "Install now?" prompt and then the "Installing Claude Code through mise (first run, can take a minute)..." line.

### Shell tools (`src/shell-tools.md`)

- [ ] `ll` in a project directory in WezTerm. The output shows the eza icons and the git status column.

## Part 2: Look and Feel

### Themes (`src/themes.md`)

- [ ] The theme picker from `teeup theme set`. The picker shows the available themes.

### Containers (`src/containers.md`)

- [ ] The first `docker ps` on a new Mac. The output shows the Install now? prompt, the colima start output, and the empty container list.

### Apps (`src/apps.md`)

- [ ] Three windows (WezTerm, Emacs, Firefox Developer Edition) on workspace 1. AeroSpace tiles the windows.

## Part 4: Configuration

## Part 5: Moving In and Out

### Migrating (`src/migrating.md`)

- [ ] `DRY_RUN=true teeup migrate legacy` on a Mac with the old teeup and chezmoi. The output shows the "[DRY-RUN] Would ..." lines and the two lists of chezmoi files.

### Uninstall (`src/uninstall.md`)

- [ ] The end of `DRY_RUN=true teeup uninstall`. The output shows the "teeup uninstall summary" with its "Would remove" and "Kept" sections and the "Run it for real with:" line.

## Part 6: Help

### Doctor and troubleshooting (`src/doctor-and-troubleshooting.md`)

- [ ] `teeup doctor` on a healthy Mac. The output ends with "teeup doctor: everything checked is healthy."
