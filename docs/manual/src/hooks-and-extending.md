# Hooks and extending

teeup supports custom additions through hooks, menu rows, and capabilities.

## Hooks

A hook is a script that teeup runs after an event. Hooks are in the `~/.config/teeup/hooks/<event>.d/` directory.

| Event | Runs after | Arguments |
|---|---|---|
| `post-bootstrap` | `./bootstrap` | teeup provides no arguments. |
| `post-update` | `teeup update` | teeup provides no arguments after a full update. teeup provides the capability name after `teeup update <capability>`. |
| `theme-set` | `teeup theme set` | teeup provides the theme name. |

teeup runs every file in the directory with `bash` in name order. Number the files to set the run order:

```sh
# ~/.config/teeup/hooks/post-update.d/10-brew-cleanup.sh
if [ -z "${1:-}" ] && command -v brew >/dev/null 2>&1; then
  brew cleanup
fi
```

teeup adds `TEEUP_PATH`, `TEEUP_CONFIG_DIR`, `TEEUP_STATE_DIR` and `TEEUP_HOOK_EVENT` to the environment of a hook. The standard input of a hook is empty. A hook cannot ask questions. If a hook fails, teeup prints a warning and continues.

Each directory has an `example.sample` file. This file documents the event of the directory. teeup does not run files that end in `.sample`. teeup rewrites the sample when the teeup copy changes. You can use the rest of the directory. If you set `DRY_RUN=true`, teeup lists the hooks, but teeup does not run the hooks.

## Menu rows

The menu is `share/teeup/menu.json` in the checkout. See [The menu](the-menu.md). Write `~/.config/teeup/menu.json` in the same format to change the menu. The format is one JSON object. The keys of the JSON object are dotted ids. For example, `install.editors.zed` is a row under `install.editors`.

| Field | Meaning |
|---|---|
| `label` | This field is required. The row shows this text. |
| `icon` | This field is optional. teeup prints the icon before the label. |
| `action` | This field contains a shell command line. A row with an action runs the command. A row without an action is a submenu. |
| `when` | This field contains a shell condition. If the condition exits with a non-zero status, teeup hides the row. |
| `title` | This field contains the header. teeup shows this header when you open the submenu. The default value is the label. |

If a row has the same id as a row in the shipped file, the new row replaces the shipped row. teeup keeps the replaced row in the same position. teeup adds a new id at the end of the submenu. To hide a shipped row, add `"when": "false"` to the row.

```json
{
  "tools": {"label": "My tools"},
  "tools.notes": {"label": "Open notes", "action": "teeup launch Obsidian"},
  "setup.migrate": {"label": "Retire the old wiring", "when": "false"}
}
```

teeup runs conditions and actions with the `bin/` directory of the checkout first on the `PATH`. Thus, `teeup` always means the teeup program that you run. Run `teeup dev check` to lint the menu.

## Your own capability

A capability is a directory under `capabilities/` in the checkout. Run this command to start a capability from the skeleton:

```sh
teeup dev new-capability mytool
```

The command writes the `capabilities/mytool/` directory. The directory contains the `capability` metadata file, the `install` script, the `configure` script, and a test. The new capability is lazy. The capability does not change what `./bootstrap` installs. If you move the capability to another tier, `./bootstrap` installs the capability.

| File | Holds |
|---|---|
| `capability` | This file contains `summary`, `group`, `tier`, `requires`, `provides`, `packages`, `casks`, `apps`, and `interactive`. |
| `install` | The script installs packages. The script does not do other tasks. |
| `configure` | The script writes configuration. The script does not do other tasks. |
| `remove`, `doctor` | These files are optional. The remove script removes items that teeup cannot remove from the metadata. The doctor script checks the health of the capability. |
| `config/`, `home/`, `default/` | teeup copies `config/` files to `~/.config` once. teeup copies `home/` files to `$HOME` once. The `default/` directory contains the layer of teeup. |

Run this command to check the capability:

```sh
teeup dev check mytool
```

The "Adding a capability" section in the `CONTRIBUTING.md` file of the checkout contains more information. The section shows how to report that a capability does not apply to a Mac. The section shows how to add a themed template. The section shows how to write macOS preferences so that `teeup remove` can restore the preferences. The section also shows how to register lazy commands and apps.

A capability that you add lives in your checkout of teeup. If the checkout has uncommitted changes, the `teeup update` command stops. When you commit the changes, `git pull --ff-only` cannot fast-forward. Thus, the update prints a warning and continues with the current state of your checkout. Keep the capability on a branch that you merge yourself. You can also send the capability upstream.
