# Emacs

Emacs is in the daily tier. teeup installs the GUI build and the `emacs-app` cask. This puts `emacs` and `emacsclient` on your `PATH`. Emacs runs as a daemon from login onward. git and the shell use `emacsclient` as their editor.

<!-- SCREENSHOT: An Emacs window opened with `e README.md` from WezTerm, showing the teeup starter layer with the current theme. -->

## The four flavors

The wizard asks which configuration to install. The answer is `TEEUP_EMACS_FLAVOR`.

| Flavor | What teeup does |
|---|---|
| `starter` | The default. A thin `~/.config/emacs/init.el` that loads teeup's small, built-ins-only layer from the checkout, plus `~/.config/emacs/local.el` for your own settings. |
| `doom` | Clones [Doom Emacs](https://github.com/doomemacs/core) into `~/.config/emacs` and runs `doom install --no-env`. Your private config is `~/.config/doom`. |
| `spacemacs` | Clones Spacemacs into `~/.emacs.d`. Spacemacs finishes its own setup, and writes `~/.spacemacs`, on the first start. |
| `none` | Leaves your Emacs configuration alone. The daemon still runs. See [Your own configuration and teeup's theme](#your-own-configuration-and-teeups-theme). |

If a directory is in the way, for example a starter setup where Doom should go, teeup moves it aside as `<name>.teeup_backup_<timestamp>` rather than deleting it. Emacs reads `~/.emacs.el`, `~/.emacs` and `~/.emacs.d` before `~/.config/emacs`; if one of those exists, teeup warns you that Emacs reads it instead and leaves it where it is.

## Your own configuration and teeup's theme

When using the `none` flavor, you can add this snippet to your `init.el` to use teeup's theme and font. It only reads teeup's files. The theme follows macOS light/dark when the daemon starts and updates after each `teeup theme set` or `teeup install font`.

```elisp
;; Follow teeup's theme and font. teeup calls (teeup-apply) on a running
;; daemon after every `teeup theme set` and `teeup install font`.
(require 'subr-x)
(defun teeup-apply ()
  (let* ((state (expand-file-name "~/.local/state/teeup/"))
         (dark (string= "Dark" (string-trim (shell-command-to-string
                 "defaults read -g AppleInterfaceStyle 2>/dev/null"))))
         (theme (expand-file-name (format "current/theme/%s/emacs.el"
                                          (if dark "dark" "light"))
                                  state))
         (font (expand-file-name "current/font" state)))
    (when (file-readable-p theme)
      (load theme nil t)
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme teeup-theme-name t))
    (when (and (display-graphic-p) (file-readable-p font))
      (set-face-attribute 'default nil :family
                          (string-trim (with-temp-buffer
                                         (insert-file-contents font)
                                         (buffer-string)))))))
(teeup-apply)
```

## The daemon and emacsclient

A LaunchAgent, `sh.teeup.emacs`, starts `Emacs --fg-daemon` at login. launchd restarts it after a crash, but not after you stop it on purpose.

| Command | What it opens |
|---|---|
| `e <file>` | A new Emacs window (`emacsclient -c`) |
| `et <file>` | A frame in the current terminal (`emacsclient -t`) |
| `$EDITOR` and `$VISUAL` | `emacsclient -t`, so git, `teeup config edit` and other tools open in the terminal |

If the daemon is not running, `emacsclient` from the shell starts one. teeup's shell sets an empty `ALTERNATE_EDITOR` to enable this.

The daemon keeps the configuration it loaded at start. After you change the flavor or edit your init files, restart it:

```sh
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

`teeup configure emacs` prints that line too.

## Changing the flavor

Set the answer, then configure Emacs again:

```sh
teeup config set TEEUP_EMACS_FLAVOR doom
teeup configure emacs
launchctl kickstart -k gui/$(id -u)/sh.teeup.emacs
```

`teeup update` also applies a changed flavor, because it configures the daily tier again. If your machine file pins `TEEUP_EMACS_FLAVOR`, `teeup config set` warns you that the pin wins; change it there instead (see [Answers and machines](answers-and-machines.md)).

## Doom's command line

With the `doom` flavor, the Doom CLI is on your `PATH`, because teeup's shell adds `~/.config/emacs/bin`. After editing `~/.config/doom`, run:

```sh
doom sync
```

`doom doctor` and `doom upgrade` work the same way. teeup runs `doom install` only once, while `~/.config/doom/init.el` does not exist yet. teeup disables Doom's default template theme so its own theme applies; your own `doom-theme` setting overrides it.


## Removing Emacs

`teeup remove emacs` unloads the daemon's LaunchAgent and uninstalls the cask. Your configuration in `~/.config/emacs`, `~/.config/doom` or `~/.emacs.d` stays. If Emacs will not start or the wrong build runs, see [Doctor and troubleshooting](doctor-and-troubleshooting.md).
