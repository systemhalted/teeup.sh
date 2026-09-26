# The teeup Manual

Date: 2026-09-26. Status: approved by the owner (source, timing and scope
chosen 2026-09-26). Amended 2026-09-26: the manual moved from systemhalted.in
into this repo, built with mdBook and published at teeup.systemhalted.in.

## Goal

A multi-page manual for teeup.sh at `https://teeup.systemhalted.in/`, modelled
on the Omarchy Manual (learn.omacom.io/2/the-omarchy-manual). It uses short
pages, one topic per page, grouped into parts. Command and key tables
carry the reference material, and screenshots show what the user will see.
The tone is conversational but exact.

## Decisions

- **Source** lives in this repo as Markdown under `docs/manual/`, built with
  mdBook. teeup's README stays short and links to the published manual.
- **Timing:** written now on branch `docs/manual`, merged when ready, and
  published when teeup 0.1.0-beta is tagged. The manual describes the beta:
  teeup's main plus `teeup uninstall` and the phase 4d themes, including
  Terminal.app and Doom theming.
- **Scope:** the full manual below, about 25 pages.

## Build and publishing

- **mdBook** in `docs/manual/`: `book.toml`, `src/SUMMARY.md` and one
  `src/<slug>.md` per chapter. `SUMMARY.md` is the single source of order:
  each part is a `# Part N: Name` heading, followed by its chapters as list
  links in reading order. Search is on.
- **Title:** the book's title, and so the site's, is "The teeup Manual".
- **Domain:** `src/CNAME` holds `teeup.systemhalted.in`. mdBook copies every
  non-Markdown file in `src/` into the output, so the CNAME reaches the
  published site.
- **Workflow:** `.github/workflows/manual.yml` installs a pinned mdBook
  release, runs `mdbook build docs/manual`, and deploys the output to GitHub
  Pages with `actions/upload-pages-artifact` and `actions/deploy-pages`. It
  runs only on tags matching `v*` and on `workflow_dispatch`. Actions are
  pinned by major version, as `ci.yml` pins them.
- **Local build:** `mise exec mdbook@<version> -- mdbook build docs/manual`.
  The output directory is ignored by git and never committed.
- **Parts 2 and 5** are listed in `SUMMARY.md` only once their pages exist,
  since mdBook would otherwise create empty files for the missing links.

## Page conventions

- Each page starts with a `# Title` heading, the chapter's name as it appears
  in `SUMMARY.md`.
- The prose follows the owner's writing rules. None of these phrasings appear:
  "No X, no Y" chains, "Did not X, did not Y" chains, "That's the whole ...",
  "Don't VERB it ... VERB it", "Sit with that", "You already know",
  "is the entire ...", "The entire ... is", "X is real, and/not ...",
  "The punchline is", "Worth naming". State things plainly.
- Every command, flag, path, key binding and message on a page is checked
  against teeup's code at the beta commit before it is written. When the code
  and the README disagree, the code wins.
- Links between chapters are relative `.md` links, which mdBook rewrites.
- Screenshots go under `docs/manual/src/images/` as short descriptive names
  with alt text. Until the owner captures them on the macOS VM, a page carries
  an HTML comment `<!-- SCREENSHOT: <what to capture> -->`, which does not
  render. `docs/manual/screenshots.md`, outside `src/` so it is not
  published, collects the list.

## Chapters

**Part 1: The Basics**
1. `welcome`: what teeup is (your Mac as a distribution, Omarchy-inspired),
   and who it is for.
2. `getting-started`: requirements (macOS version, Apple Silicon or Intel,
   Homebrew or MacPorts), `git clone` and `./bootstrap`, the wizard's
   questions, and what the first run installs (core and daily tiers).
3. `the-teeup-command`: every verb, as a table (install, configure, reset,
   update, remove, uninstall, theme, list, launch, has, secret, status,
   doctor, config, menu, migrate, dev, commands, version), with DRY_RUN.
4. `the-menu`: `teeup menu`, its sections, gum vs the numbered fallback, and
   Escape to go back.
5. `tiers`: core, daily and lazy, and what lazy shims do on the first run.

**Part 2: Look and Feel**
6. `themes`: `teeup theme set/list/current`, the four themes, light and dark
   following macOS, what each themed tool picks up (Terminal.app, WezTerm,
   Starship, bat, Zed, Emacs starter and Doom, Neovim, VS Code), and a new
   window for Terminal.app.
7. `fonts`: `teeup install font`, Nerd Font icons, and the Terminal.app
   caveat.
8. `prompt`: Starship and its palette.

**Part 3: The Applications**
9. `terminal`: WezTerm (and the VM front_end note) and Terminal.app.
10. `emacs`: flavors (starter, doom, spacemacs, none), the daemon and
    emacsclient, changing the flavor, and Doom's CLI on PATH.
11. `other-editors`: Zed, Neovim, VS Code and Cursor.
12. `ai-tools`: the ai-claude, ai-codex, ai-gemini, ai-copilot and ai-opencode
    leaves and the `ai` bundle, install on first run, lazy.log, and removal.
13. `shell-tools`: zsh without a framework, eza aliases (the `ls` table),
    bat, fzf, zoxide, ripgrep, fd, delta, lazygit, btop, and tldr.
14. `runtimes`: mise, `teeup install dev-env <lang>`, uv and rustup.
15. `containers`: Colima and Docker.
16. `apps`: Firefox Developer Edition, Obsidian, Chrome, AeroSpace, Ollama
    and Herdr, and `teeup launch`.

**Part 4: Configuration**
17. `updates`: `teeup update` (the whole machine and one capability, what
    runs in which order, and core plus daily re-configure).
18. `answers-and-machines`: the answers file, `teeup config get/set/edit`
    (VISUAL before EDITOR), `machines/<host>.conf` pins, and the personal
    overlay.
19. `dotfiles`: where configs live, copy-once and pristine rules, `local`
    files you own, and `teeup reset`.
20. `identity`: git identity, ssh keys (teeup never deletes one), the work
    machine file, and GitHub.
21. `secrets`: `teeup secret` and the Keychain.
22. `macos-defaults`: what teeup sets, Caps Lock, and the keyboard.
23. `hooks-and-extending`: hooks and adding your own capability (a pointer to
    CONTRIBUTING).

**Part 5: Moving In and Out**
24. `migrating`: from the old teeup or chezmoi, `teeup migrate legacy`, and
    the dry run first.
25. `uninstall`: `teeup uninstall`, its flags, what it keeps, and the rerun.

**Part 6: Help**
26. `doctor-and-troubleshooting`: `teeup doctor`, the logs
    (`~/.local/state/teeup/logs`), and common problems seen on real Macs
    (Nerd Font icons, WezTerm in a VM, `brew uninstall emacs` and the cask
    rename, Emacs daemon restarts).
27. `faq`.

## Keeping it honest

- `tests/docs.sh` checks the manual on every CI run, since it now lives in the
  same repo:
  - every code-formatted `` `teeup <verb> ...` `` in `docs/manual/src/*.md` names
    a verb in `bin/teeup`'s dispatcher (`teeup_verbs` in `lib/dev.sh`);
    `teeup commands` lists capabilities, not verbs, so it cannot be the source;
  - every link in `SUMMARY.md` points at a file that exists;
  - every `.md` file in `src/` is linked from `SUMMARY.md`.
- Publishing is gated on teeup's beta tag: the workflow runs on `v*` tags.
