;;; check.el --- GOL Check: Anti-Hallucination Firewall -*- lexical-binding: t; -*-

;; Author: GOL Productions
;; URL: https://github.com/golproductions/check.el
;; Version: 1.0.0
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
(defconst check--version "1.0.0")

(defun check--validate (command callback)
  "Validate COMMAND via Check API, call CALLBACK with result."
  (when (string-empty-p check-client-id)
    (user-error "Check: No Client ID set. Customize `check-client-id' or set GOL_CLIENT_ID env var"))
  (let ((url-request-method "POST")
        (url-request-extra-headers
         `(("Content-Type" . "application/json")
           ("X-GOL-CLIENT-ID" . ,check-client-id)
           ("User-Agent" . ,(concat "emacs/" check--version))))
        (url-request-data
         (encode-coding-string
          (json-encode `(("command" . ,command)
                         ("platform" . "emacs")
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
