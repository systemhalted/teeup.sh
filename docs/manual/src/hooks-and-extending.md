# Hooks and extending

teeup supports custom additions through hooks, menu rows, and capabilities.

## Hooks

A hook is a script of yours that teeup runs after an event. Hooks are in `~/.config/teeup/hooks/<event>.d/`.

| Event | Runs after | Arguments |
|---|---|---|
| `post-bootstrap` | `./bootstrap` | None |
| `post-update` | `teeup update` | None after a full update, and the capability name after `teeup update <capability>` |
| `theme-set` | `teeup theme set` | The theme name |

teeup runs every file in the directory with `bash`, in name order, so number the files to set the order:

```sh
# ~/.config/teeup/hooks/post-update.d/10-brew-cleanup.sh
if [ -z "${1:-}" ] && command -v brew >/dev/null 2>&1; then
  brew cleanup
fi
```

teeup adds `TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR` and `TEEUP_HOOK_EVENT` to the environment of a hook. The standard input of a hook is empty, so a hook cannot ask questions. If a hook fails, teeup prints a warning and continues.

Each directory has an `example.sample` file that documents its event. teeup does not run files that end in `.sample`, and it rewrites the sample when its own copy changes. teeup does not change the other files in the directory. If you set `DRY_RUN=true`, teeup lists the hooks but does not run them.

## Menu rows

The menu (see [The menu](the-menu.md)) is `share/teeup/menu.json` in the checkout. To change the menu, write `~/.config/teeup/menu.json` in the same format: one JSON object with dotted ids as keys. For example, `install.editors.zed` is a row under `install.editors`.

| Field | Meaning |
|---|---|
| `label` | Required. The text that the row shows. |
| `icon` | Optional. teeup prints it before the label. |
| `action` | A shell command line. A row with an action runs it, and a row without an action is a submenu. |
| `when` | A shell condition. If it exits with a non-zero status, teeup hides the row. |
| `title` | The header that teeup shows when you open the submenu. The default value is the label. |

If a row has the same id as a row in the shipped file, it replaces all of the shipped row, in the same position. teeup adds a new id at the end of its submenu. To hide a shipped row, add `"when": "false"` to the row.

```json
{
  "tools": {"label": "My tools"},
  "tools.notes": {"label": "Open notes", "action": "teeup launch Obsidian"},
  "setup.migrate": {"label": "Retire the old wiring", "when": "false"}
}
```

teeup runs conditions and actions with the `bin/` directory of the checkout first on the `PATH`, so `teeup` always means the teeup that you run. Run `teeup dev check` to lint the menu.

## Your own capability

A capability is a directory under `capabilities/` in the checkout. To start a capability from the skeleton, run:

```sh
teeup dev new-capability mytool
```

The command writes the `capabilities/mytool/` directory, with the `capability` metadata file, the `install` and `configure` scripts, and a test. The new capability is lazy, so it does not change what `./bootstrap` installs until you move it to a different tier.

| File | Holds |
|---|---|
| `capability` | `summary`, `group`, `tier`, `requires`, `provides`, `packages`, `casks`, `apps`, and `interactive` |
| `install` | A script that installs packages and does nothing else |
| `configure` | A script that writes configuration and does nothing else |
| `remove`, `doctor` | Optional. `remove` removes what teeup cannot remove from the metadata, and `doctor` checks the health of the capability. |
| `config/`, `home/`, `default/` | Files that teeup copies once to `~/.config`, files that it copies once to `$HOME`, and the teeup layer |

Then check the capability:

```sh
teeup dev check mytool
```

The "Adding a capability" section of `CONTRIBUTING.md` in the checkout has more information. It shows how to:

- Report that a capability does not apply to a Mac.
- Add a themed template.
- Write macOS preferences so that `teeup remove` can restore them.
- Register lazy commands and apps.

A capability that you add lives in your checkout of teeup. If the checkout has uncommitted changes, `teeup update` stops. After you commit the changes, `git pull --ff-only` cannot fast-forward, so the update prints a warning and continues with your checkout as it is. Keep the capability on a branch that you merge yourself, or send it upstream.
