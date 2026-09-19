;;; init.el --- ~/.config/emacs/init.el, yours  -*- lexical-binding: t -*-

;; teeup installed this file once and will not overwrite it. The thick layer
;; is capabilities/emacs/default/teeup/init.el in the teeup checkout, upgraded
;; by `teeup update`. Put your own settings in ~/.config/emacs/local.el, which
;; loads last, or below the layer call at the bottom of this file.

;; --- where the checkout is ---------------------------------------------------
;; The daemon started by launchd gets TEEUP_PATH from its LaunchAgent, a
;; shell exports it, and ~/.config/teeup/env (written by teeup-runtime)
;; covers everything else. Each value in that file went through bash's
;; `printf %q`, so a path with a space, a quote or a non-ASCII byte comes back
;; as a backslash-escaped word or a $'...' ANSI-C literal; teeup--unquote
;; undoes both.
(defun teeup--unquote (word)
  "Return the plain text of one shell WORD as bash would expand it."
  (let ((i 0) (n (length word)) (out nil))
    (while (< i n)
      (let ((c (aref word i)))
        (cond
         ;; '...' keeps everything literal.
         ((eq c ?')
          (let ((j (or (string-search "'" word (1+ i)) n)))
            (push (substring word (1+ i) j) out)
            (setq i (1+ j))))
         ;; "...": backslash escapes only $ ` " \ and newline.
         ((eq c ?\")
          (let ((j (1+ i)) (buf nil))
            (while (and (< j n) (not (eq (aref word j) ?\")))
              (let ((cj (aref word j)))
                (if (and (eq cj ?\\) (< (1+ j) n)
                         (memq (aref word (1+ j)) '(?$ ?` ?\" ?\\ ?\n)))
                    (progn (push (aref word (1+ j)) buf) (setq j (+ j 2)))
                  (push cj buf) (setq j (1+ j)))))
            (push (concat (nreverse buf)) out)
            (setq i (1+ j))))
         ;; $'...': ANSI-C quoting with \NNN octal, \xHH and the usual escapes.
         ((and (eq c ?$) (< (1+ i) n) (eq (aref word (1+ i)) ?'))
          (let ((j (+ i 2)) (buf nil))
            (while (and (< j n) (not (eq (aref word j) ?')))
              (let ((cj (aref word j)))
                (if (and (eq cj ?\\) (< (1+ j) n))
                    (let ((nx (aref word (1+ j))))
                      (cond
                       ((and (>= nx ?0) (<= nx ?7))
                        (let ((k (1+ j)) (v 0))
                          (while (and (< k n) (< (- k j) 4)
                                      (>= (aref word k) ?0) (<= (aref word k) ?7))
                            (setq v (+ (* v 8) (- (aref word k) ?0)) k (1+ k)))
                          (push (logand v 255) buf)
                          (setq j k)))
                       ((and (eq nx ?x) (< (+ j 2) n)
                             (string-match-p "[0-9a-fA-F]" (string (aref word (+ j 2)))))
                        (let ((k (+ j 2)) (hex ""))
                          (while (and (< k n) (< (length hex) 2)
                                      (string-match-p "[0-9a-fA-F]" (string (aref word k))))
                            (setq hex (concat hex (string (aref word k))) k (1+ k)))
                          (push (string-to-number hex 16) buf)
                          (setq j k)))
                       ((eq nx ?n) (push ?\n buf) (setq j (+ j 2)))
                       ((eq nx ?t) (push ?\t buf) (setq j (+ j 2)))
                       ((eq nx ?r) (push ?\r buf) (setq j (+ j 2)))
                       ((eq nx ?a) (push 7 buf) (setq j (+ j 2)))
                       ((eq nx ?b) (push 8 buf) (setq j (+ j 2)))
                       ((memq nx '(?e ?E)) (push 27 buf) (setq j (+ j 2)))
                       ((eq nx ?f) (push 12 buf) (setq j (+ j 2)))
                       ((eq nx ?v) (push 11 buf) (setq j (+ j 2)))
                       (t (push nx buf) (setq j (+ j 2)))))
                  (push cj buf) (setq j (1+ j)))))
            ;; The bytes are raw UTF-8; decode them back into characters.
            (push (decode-coding-string (apply #'unibyte-string (nreverse buf)) 'utf-8) out)
            (setq i (1+ j))))
         ;; A bare backslash makes the next character literal.
         ((and (eq c ?\\) (< (1+ i) n))
          (push (string (aref word (1+ i))) out)
          (setq i (+ i 2)))
         (t (push (string c) out) (setq i (1+ i))))))
    (apply #'concat (nreverse out))))

(defun teeup--env-file-value (key)
  "Return KEY from ~/.config/teeup/env, or nil when the file lacks it."
  (let ((file (expand-file-name "teeup/env" (or (getenv "XDG_CONFIG_HOME") "~/.config")))
        (re (concat "^export " (regexp-quote key) "=\\(.+\\)$")))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward re nil t)
          (teeup--unquote (match-string 1)))))))

(defvar teeup-path
  (or (getenv "TEEUP_PATH")
      (teeup--env-file-value "TEEUP_PATH")
      (expand-file-name "~/.local/share/teeup"))
  "The teeup checkout.")

(defvar teeup-state-dir
  (or (getenv "TEEUP_STATE_DIR")
      (teeup--env-file-value "TEEUP_STATE_DIR")
      (expand-file-name "teeup" (or (getenv "XDG_STATE_HOME") "~/.local/state")))
  "Where teeup keeps the rendered theme and the font name.")

;; --- the teeup layer ---------------------------------------------------------
(let ((layer (expand-file-name "capabilities/emacs/default/teeup/init.el" teeup-path)))
  (if (file-readable-p layer)
      (load layer nil t)
    (message "teeup: no layer at %s; set TEEUP_PATH or run: teeup configure teeup-runtime" layer)))

;; Your own settings go below this line, or in local.el.
(let ((local (expand-file-name "local.el" user-emacs-directory)))
  (when (file-readable-p local)
    (load local nil t)))

;;; init.el ends here
