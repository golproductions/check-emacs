;;; check.el --- GOL Check: Anti-Hallucination Firewall -*- lexical-binding: t; -*-

;; Author: GOL Productions
;; URL: https://github.com/golproductions/check.el
;; Version: 1.0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, ai, validation

;;; Commentary:
;; Validates AI-generated commands before execution.
;; Catches hallucinated commands, fake APIs, and invalid operations.
;; Get your Client ID at golproductions.com/check.html

;;; Code:

(defgroup check nil
  "GOL Check anti-hallucination firewall."
  :group 'tools
  :prefix "check-")

(defcustom check-client-id (or (getenv "GOL_CLIENT_ID") "")
  "GOL Productions Client ID."
  :type 'string
  :group 'check)

(defcustom check-enabled t
  "Whether Check validation is enabled."
  :type 'boolean
  :group 'check)

(defconst check--api-url "https://triage.golproductions.com/preflight")
(defconst check--instant-url "https://triage.golproductions.com/instant-key")
(defconst check--channel "emacs")
(defconst check--version "1.0.1")

(defconst check--machine-key-file (expand-file-name "~/.check/key")
  "One free GOL Client ID per machine, shared by every Check client.
The npm hook, MCP server, and all editor integrations read and write
this file, so every tool on the machine uses the same free key.")

(defun check--read-machine-key ()
  "Return the machine key from `check--machine-key-file', or nil."
  (when (file-readable-p check--machine-key-file)
    (let ((k (string-trim (with-temp-buffer
                            (insert-file-contents check--machine-key-file)
                            (buffer-string)))))
      (unless (string-empty-p k) k))))

(defun check--write-machine-key (key)
  "Persist KEY to `check--machine-key-file'."
  (condition-case nil
      (progn
        (make-directory (file-name-directory check--machine-key-file) t)
        (with-temp-file check--machine-key-file (insert key)))
    (error nil)))

(defun check--device-fingerprint ()
  "One-way hash of coarse machine facts. No personal data.
The recipe (hostname|platform|arch|username, Node.js-style tokens) is
shared by every Check client so all tools on one machine resolve to the
same free key."
  (let ((platform (pcase system-type
                    ((or 'windows-nt 'cygwin 'ms-dos) "win32")
                    ('darwin "darwin")
                    (_ "linux")))
        (arch (let ((conf (downcase system-configuration)))
                (if (or (string-match-p "aarch64" conf)
                        (string-match-p "arm64" conf))
                    "arm64" "x64"))))
    (secure-hash 'sha256
                 (mapconcat #'identity
                            (list (or (system-name) "")
                                  platform
                                  arch
                                  (or (user-login-name) ""))
                            "|"))))

(defun check--mint-instant-key ()
  "Resolve the machine key, minting one only if no Check client has yet.
Persist and return it, or nil on failure."
  (let ((existing (check--read-machine-key)))
    (if existing
        (progn
          (setq check-client-id existing)
          (customize-save-variable 'check-client-id existing)
          existing)
      (let ((url-request-method "POST")
            (url-request-extra-headers
             `(("Content-Type" . "application/json")
               ("User-Agent" . ,(concat "emacs/" check--version))))
            (url-request-data
             (encode-coding-string
              (json-encode `(("fingerprint" . ,(check--device-fingerprint))
                             ("channel" . ,check--channel)))
              'utf-8)))
        (condition-case nil
            (let ((buf (url-retrieve-synchronously check--instant-url t t 10)))
              (when buf
                (with-current-buffer buf
                  (goto-char (point-min))
                  (when (re-search-forward "\n\n" nil t)
                    (let* ((json-object-type 'alist)
                           (data (json-read))
                           (cid (alist-get 'client_id data)))
                      (when (and cid (not (string-empty-p cid)))
                        (setq check-client-id cid)
                        (customize-save-variable 'check-client-id cid)
                        (check--write-machine-key cid)
                        cid))))))
          (error nil))))))

(defun check--validate (command callback)
  "Validate COMMAND via Check API, call CALLBACK with result."
  (when (string-empty-p check-client-id)
    ;; No key yet: mint one instantly. No email, no browser.
    (unless (check--mint-instant-key)
      (user-error "Check: could not activate. Check your connection and try again")))
  (let ((url-request-method "POST")
        (url-request-extra-headers
         `(("Content-Type" . "application/json")
           ("X-GOL-CLIENT-ID" . ,check-client-id)
           ("User-Agent" . ,(concat "emacs/" check--version))))
        (url-request-data
         (encode-coding-string
          (json-encode `(("command" . ,command)
                         ("platform" . "emacs")
                         ("channel" . ,check--channel)
                         ("v" . ,check--version)))
          'utf-8)))
    (url-retrieve
     check--api-url
     (lambda (status)
       (if (plist-get status :error)
           (funcall callback nil "Network error")
         (goto-char url-http-end-of-headers)
         (let* ((json-object-type 'alist)
                (data (json-read)))
           (funcall callback
                    (alist-get 'verdict data)
                    (alist-get 'reason data)))))
     nil t t)))

;;;###autoload
(defun check-validate-command (command)
  "Validate COMMAND with GOL Check."
  (interactive "sCommand to validate: ")
  (unless check-enabled
    (user-error "Check is disabled"))
  (message "Check: Validating...")
  (check--validate
   command
   (lambda (verdict reason)
     (let ((short (substring command 0 (min 80 (length command)))))
       (if (string= verdict "runnable")
           (message "Check: ✓ Runnable — %s" short)
         (message "Check: ✗ Blocked — %s" (or reason short)))))))

;;;###autoload
(defun check-validate-region (beg end)
  "Validate region BEG to END as a command with GOL Check."
  (interactive "r")
  (check-validate-command (buffer-substring-no-properties beg end)))

;;;###autoload
(defun check-validate-line ()
  "Validate the current line as a command with GOL Check."
  (interactive)
  (check-validate-command
   (string-trim (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position)))))

;;;###autoload
(defun check-setup ()
  "Set the GOL Check Client ID interactively."
  (interactive)
  (let ((id (read-string "GOL Client ID: " check-client-id)))
    (setq check-client-id id)
    (customize-save-variable 'check-client-id id)
    (message "Check: Client ID saved.")))

;;;###autoload
(define-minor-mode check-mode
  "Minor mode for GOL Check validation."
  :lighter " Check"
  :global t
  :group 'check)

(provide 'check)
;;; check.el ends here
