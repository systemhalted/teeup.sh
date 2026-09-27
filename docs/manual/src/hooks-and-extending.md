# Hooks and extending

teeup has three places for your own additions: hooks that run after teeup does something, menu rows, and whole new capabilities.

## Hooks

A hook is a script of yours that teeup runs after an event. Hooks live in `~/.config/teeup/hooks/<event>.d/`.

| Event | Runs after | Arguments |
|---|---|---|
| `post-bootstrap` | `./bootstrap` | none |
| `post-update` | `teeup update` | none after a full update; the capability name after `teeup update <capability>` |
| `theme-set` | `teeup theme set` | the theme name |

Every file in the directory runs with `bash`, in name order, so number them to set the order:

```sh
# ~/.config/teeup/hooks/post-update.d/10-brew-cleanup.sh
if [ -z "${1:-}" ] && command -v brew >/dev/null 2>&1; then
  brew cleanup
fi
```

A hook gets `TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR` and `TEEUP_HOOK_EVENT` in its environment. Its standard input is empty, so it cannot ask questions. A hook that fails prints a warning, and teeup carries on.

Each directory has an `example.sample` that documents its event. Files ending in `.sample` never run, and teeup rewrites the sample when its copy changes. The rest of the directory is yours. With `DRY_RUN=true`, teeup lists the hooks it would run instead of running them.

## Menu rows

The menu (see [The menu](the-menu.md)) is `share/teeup/menu.json` in the checkout. To change it, write `~/.config/teeup/menu.json` in the same format: one JSON object whose keys are dotted ids. `install.editors.zed` is a row under `install.editors`.

| Field | Meaning |
|---|---|
| `label` | Required. What the row shows. |
| `icon` | Optional. Printed before the label. |
| `action` | A shell command line. A row with one runs it; a row without one is a submenu. |
| `when` | A shell condition. The row is hidden when it exits non-zero. |
| `title` | The header shown when the submenu is open. Defaults to the label. |

A row whose id is also in the shipped file replaces that row whole, in the same position. A new id is added at the end of its submenu. To hide a shipped row, give it `"when": "false"`.

```json
{
  "tools": {"label": "My tools"},
  "tools.notes": {"label": "Open notes", "action": "teeup launch Obsidian"},
  "setup.migrate": {"label": "Retire the old wiring", "when": "false"}
}
```

Conditions and actions run with the checkout's `bin/` first on `PATH`, so `teeup` always means the teeup you are running. `teeup dev check` lints the menu.

## Your own capability

A capability is a directory under `capabilities/` in the checkout. Start one from the skeleton:

```sh
teeup dev new-capability mytool
```

That writes `capabilities/mytool/` with its `capability` metadata file, `install` and `configure` scripts, and a test. The new capability is lazy, so it does not change what `./bootstrap` installs until you move it to another tier.

| File | Holds |
|---|---|
| `capability` | `summary`, `group`, `tier`, `requires`, `provides`, `packages`, `casks`, `apps`, `interactive` |
| `install` | Installs packages, and nothing else |
| `configure` | Writes configuration, and nothing else |
| `remove`, `doctor` | Optional. Undo what teeup cannot undo from the metadata; check the capability's health |
| `config/`, `home/`, `default/` | Files copied once to `~/.config`, files copied once to `$HOME`, and teeup's own layer |

Then check it:

```sh
teeup dev check mytool
```

`CONTRIBUTING.md` in the checkout has the full contract, under "Adding a capability": how to report that a capability does not apply to a Mac, how to add a themed template, how to write macOS preferences so `teeup remove` can restore them, and how lazy commands and apps are registered.

A capability you add lives in your checkout of teeup. `teeup update` stops while the checkout has uncommitted changes, and once you commit, `git pull --ff-only` can no longer fast-forward, so the update warns and carries on with your checkout as it is. Keep it on a branch you merge yourself, or send it upstream.
