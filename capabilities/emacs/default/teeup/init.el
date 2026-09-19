;;; teeup/init.el --- teeup's Emacs layer  -*- lexical-binding: t -*-

;; Loaded by the thin ~/.config/emacs/init.el. This file is teeup's: edit it
;; in the checkout, not in your home directory. It is a small, built-ins-only
;; starter, so a fresh Mac gets a working Emacs before any package downloads;
;; MELPA is configured for M-x package-install and use-package :ensure.

(defvar teeup-path (expand-file-name "~/.local/share/teeup"))
(defvar teeup-state-dir (expand-file-name "~/.local/state/teeup"))
(defvar teeup-font-height 140
  "Default face height in 1/10 pt. Set it in local.el, then (teeup-apply).")
(defvar teeup-font-family "JetBrainsMono Nerd Font"
  "The family `teeup install font` recorded; refreshed by `teeup-apply'.")
(defvar teeup-theme-mode nil "dark or light, as last applied.")
(defvar teeup-theme-name nil "The theme symbol the rendered palette named.")
(defvar teeup-theme-colors nil "The semantic palette, as an alist of strings.")

;; --- packages ----------------------------------------------------------------
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-readable-p custom-file)
  (load custom-file nil t))

;; --- defaults ----------------------------------------------------------------
(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      make-backup-files nil
      create-lockfiles nil
      auto-save-default t
      use-short-answers t
      confirm-kill-emacs nil
      sentence-end-double-space nil
      require-final-newline t
      load-prefer-newer t)
(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 80)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(menu-bar-mode -1)
(column-number-mode 1)
(global-auto-revert-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(save-place-mode 1)
(show-paren-mode 1)
(electric-pair-mode 1)
(delete-selection-mode 1)
(fido-vertical-mode 1)
(when (fboundp 'which-key-mode) (which-key-mode 1))
(when (fboundp 'global-display-line-numbers-mode)
  (add-hook 'prog-mode-hook #'display-line-numbers-mode))
(when (eq system-type 'darwin)
  ;; Option is Meta, Command is Super; Cmd-V/Cmd-C keep macOS meaning.
  (setq ns-option-modifier 'meta
        ns-command-modifier 'super
        ns-pop-up-frames nil))

;; --- appearance, theme and font ----------------------------------------------
(defun teeup--read-first-line (path)
  "Return the first non-blank line of PATH, or nil."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (let ((line (string-trim (buffer-substring-no-properties
                                (point) (line-end-position)))))
        (unless (string-empty-p line) line)))))

(defun teeup-appearance ()
  "Return \"dark\" or \"light\": TEEUP_APPEARANCE from a shell, else macOS.
`defaults read -g AppleInterfaceStyle` prints Dark in dark mode and fails in
light mode, the same rule the zsh layer and lib/macos.sh use."
  (let ((env (getenv "TEEUP_APPEARANCE")))
    (cond
     ((member env '("dark" "light")) env)
     ((and (executable-find "defaults")
           (string= "Dark"
                    (string-trim
                     (with-output-to-string
                       (with-current-buffer standard-output
                         (call-process "defaults" nil t nil "read" "-g" "AppleInterfaceStyle"))))))
      "dark")
     (t "light"))))

(defun teeup-apply-font ()
  "Point the default face at the family in current/font."
  (setq teeup-font-family
        (or (teeup--read-first-line (expand-file-name "current/font" teeup-state-dir))
            teeup-font-family))
  (when (display-graphic-p)
    (set-face-attribute 'default nil :family teeup-font-family :height teeup-font-height)))

(defun teeup-apply-theme ()
  "Load the theme the rendered palette for the current appearance names."
  (setq teeup-theme-mode (teeup-appearance))
  (let ((rendered (expand-file-name (concat "current/theme/" teeup-theme-mode "/emacs.el")
                                    teeup-state-dir)))
    (if (file-readable-p rendered)
        (load rendered nil t)
      ;; Before the first `teeup theme set`, use the built-in Modus themes.
      (setq teeup-theme-name (if (string= teeup-theme-mode "dark") 'modus-vivendi 'modus-operandi))))
  ;; A palette may name a theme this Emacs does not have (a MELPA theme not
  ;; installed yet); say so and keep the current one rather than failing the
  ;; whole init, which in a daemon would leave nothing to connect to.
  (when teeup-theme-name
    (condition-case err
        (progn
          (mapc #'disable-theme custom-enabled-themes)
          (load-theme teeup-theme-name t))
      (error (message "teeup: could not load theme %s: %s"
                      teeup-theme-name (error-message-string err))))))

(defun teeup-apply ()
  "Re-read the theme and font teeup recorded and apply both.
`teeup theme set` and `teeup install font` call this through emacsclient."
  (interactive)
  (teeup-apply-theme)
  (teeup-apply-font))

(teeup-apply)
;; A daemon has no graphic display until the first frame, so the font is set
;; again when a frame appears; and emacs-plus builds signal appearance changes.
(add-hook 'server-after-make-frame-hook #'teeup-apply-font)
(when (boundp 'ns-system-appearance-change-functions)
  (add-hook 'ns-system-appearance-change-functions (lambda (_appearance) (teeup-apply))))

;; --- keys --------------------------------------------------------------------
(global-set-key (kbd "C-x C-b") #'ibuffer)
(global-set-key (kbd "M-/") #'hippie-expand)
(global-set-key (kbd "C-c t") #'teeup-apply)

(provide 'teeup-init)
;;; teeup/init.el ends here
