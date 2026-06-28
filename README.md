# check.el

The universal anti-hallucination engine for Emacs.

## Install

### use-package
```elisp
(use-package check
  :load-path "~/path/to/check-emacs"
  :config
  (setq check-client-id "YOUR_CLIENT_ID")
  (check-mode 1))
```

### straight.el
```elisp
(straight-use-package
 '(check :type git :host github :repo "golproductions/check.el"))
```

Or set `GOL_CLIENT_ID` environment variable instead.

## Commands

- `M-x check-validate-command`
- `M-x check-validate-region`
- `M-x check-validate-line`
- `M-x check-setup`

## Get a Client ID

Free at [golproductions.com/check](https://www.golproductions.com/check.html)
