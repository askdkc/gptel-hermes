---
requires_tools: []
name: emacs-lisp
description: "Practical Emacs Lisp coding patterns, gotchas, and API quickref distilled from the GNU Emacs Lisp Reference Manual (Emacs 30.2)."
version: 1.0.0
author: Hermes Agent
license: MIT
---

# Emacs Lisp Skill

Quick-reference for writing correct, idiomatic Emacs Lisp. Based on the full reference manual (44 chapters, Emacs 30.2).

## Lexical vs Dynamic Binding

**Always use lexical binding in new code.** Put this at the top:

```elisp
;;; foo.el --- Foo package  -*- lexical-binding: t; -*-
```

### Lexical (the default in modern Emacs)
- Variable reference must be **textually within** the binding construct
- Creates **closures** — lexical environment lives on after `let` exits
- Faster, safer, compiler catches more errors

```elisp
(let ((x 0))
  (setq my-fn (lambda () (setq x (1+ x))))) ; closure captures x
(funcall my-fn) ; => 1
(funcall my-fn) ; => 2
```

### Dynamic (what `defvar`/`defcustom`/`defconst` creates)
- Any code can access the most recent dynamic binding
- `defvar` **permanently marks a variable as special** (dynamic)
- `(defvar x)` without value marks special only in current scope

```elisp
(defvar x -99)
(defun getx () x)
(let ((x 1)) (getx)) ; => 1 (dynamic: sees current binding)
```

**Gotcha:** `symbol-value`, `boundp`, `set` only work on dynamic bindings, never lexical.

## Variable Definition

```elisp
(defvar foo)                  ; declare without init (suppresses byte-comp warnings)
(defvar bar 23 "docstring")   ; init only if void — does NOT overwrite
(defconst pi 3.14159 "Pi")    ; ALWAYS sets value (but not enforced — advisory only)
```

- `defvar` does NOT re-evaluate if the variable already has a value
- `defconst` ALWAYS re-evaluates
- `defconst` also marks as `risky` (for file-local variables)

## Local Bindings

```elisp
(let ((x 1) (y 2))           ; parallel binding — y sees OLD x
  ...)
(let* ((x 1) (y x))           ; sequential — y sees new x
  ...)
(letrec ((f (lambda () (f)))) ; all bound before values computed — for recursive closures
  ...)
(dlet ((x 1))                 ; force DYNAMIC binding even in lexical scope
  ...)
(named-let loop ((i 0))       ; named let for recursion
  (when (< i 10)
    (do-something i)
    (loop (1+ i))))
```

## Conditionals

```elisp
(if test then else1 else2...)  ; else forms are implicit progn

(when test body...)            ; (if test (progn body...) nil)
(unless test body...)          ; (if test nil body...)

(cond
  ((numberp x) ...)
  ((stringp x) ...)
  (t (error "default")))       ; t = catch-all

;; Modern let- variants (Emacs 28+):
(when-let* ((a (compute-a))
            (b (compute-b a)))  ; stops at first nil
  (use a b))

(if-let* ((x (maybe-x)))
    (do-with x)
  (fallback))

(while-let ((line (read-line))) ; loop until nil
  (process line))
```

## pcase — Pattern Matching

Preferred over `cond` for destructuring:

```elisp
(pcase value
  (`(+ ,a ,b) (+ a b))        ; backquote pattern
  ((and (pred numberp) n) n)  ; predicate + binding
  ((pred stringp) (upcase it))
  (`(,key . ,val) (cons key val))
  (_ (error "no match")))      ; catch-all
```

## Iteration

```elisp
(while condition body...)           ; returns nil
(dolist (var list [result]) body...)  ; returns result or nil
(dotimes (var count [result]) body...) ; 0 to count-1
```

## Functions

```elisp
(defun fn (a &optional b &rest rest) ...)
(funcall fn arg1 arg2)         ; call via computed function symbol/value
(apply fn arg1 arg2 '(3 4 5))  ; spread last arg as args
(apply-partially '+ 1)         ; => (lambda (&rest args) (apply '+ 1 args))
```

### No-op functions
```elisp
(identity x)  ; return x
(ignore &rest) ; return nil, ignore args
(always &rest) ; return t
```

## Macros

```elisp
(defmacro with-temp-message (msg &rest body)
  `(let ((old-msg (current-message)))
     (unwind-protect
         (progn (message "%s" ,msg) ,@body)
       (message "%s" old-msg))))
```

- `,value` — evaluate and insert
- `,@list` — splice list elements inline
- `(gentemp "tmp")` or `make-symbol` for hygienic gensyms
- Use `(eval-when-compile (require 'foo))` if only macros are needed at compile time

**Pitfall:** Don't evaluate macro args multiple times — use `let` to hold values:
```elisp
;; WRONG: (if test) evaluated twice
(defmacro bad (test) `(if ,test (do-a) (do-b)))

;; RIGHT:
(defmacro good (test) `(let ((v ,test)) (if v (do-a) (do-b))))
```

## Advising Functions

```elisp
;; Named function advice (advice-add/remove)
(advice-add 'my-fn :before #'before-fn)
(advice-add 'my-fn :after #'after-fn)
(advice-add 'my-fn :around #'around-fn)    ; (around-fn orig-fn &rest args)
(advice-add 'my-fn :filter-args #'filter)  ; modify args before call
(advice-add 'my-fn :filter-return #'filter) ; modify return value
(advice-remove 'my-fn #'advice-fn)

;; Function value advice (add-function/remove-function)
(add-function :before (process-filter proc) #'tracer)
(remove-function (process-filter proc) #'tracer)
```

## Hooks

```elisp
;; Normal hook: list of functions, no args, name ends in "-hook"
(add-hook 'foo-mode-hook #'my-foo-init)
(remove-hook 'foo-mode-hook #'my-foo-init)
(run-hooks 'foo-mode-hook)

;; Abnormal hook: functions take args, name ends in "-functions"
(add-hook 'foo-functions #'my-fn)  ; still works
(run-hook-with-args 'foo-functions arg1 arg2)

;; Single-function hook: value is one function, name ends in "-function"
(setq foo-function #'my-fn)         ; don't use add-hook
(add-function :before (var foo-function) #'advice)  ; use add-function instead
```

## Quoting / Backquote / Eval

```elisp
'foo              ; => (quote foo) — return symbol unevaluated
'(+ 1 2)          ; => (+ 1 2) — return list as-is
`(+ 1 ,(+ 1 1))   ; => (+ 1 2)
`(1 ,@'(2 3) 4)   ; => (1 2 3 4) — splice

(eval form)        ; evaluate any Lisp object
(eval form t)      ; evaluate in current lexical environment (lexical-binding only)
```

## Byte-Compilation Tips

### Suppress compiler warnings
```elisp
;; Best: suppress specific warning
(with-suppressed-warnings ((obsolete old-fn))
  (old-fn))

;; Coarse: suppress all
(with-no-warnings body...)

;; Prevent "function not defined" warnings:
(declare-function fn-name "file.el" (arg1 arg2))
(eval-when-compile (require 'other-package))

;; For variables:
(defvar my-var)  ; declare without init — suppresses "not defined"
```

### Conditional compilation
```elisp
(eval-when-compile ...)     ; only at compile time
(eval-and-compile ...)      ; both compile and load time
```

## Coding Conventions (from Appendix D)

| Rule | Example |
|------|---------|
| Prefix globals | `mypackage-fn`, `mypackage-var` |
| Private symbols | `mypackage--internal-fn` (double hyphen) |
| Predicates | `framep`, `frame-live-p` |
| Boolean vars | `foo-flag` or `is-foo` (NOT `foo-p`) |
| Hook variables | end in `-hook` (normal) or `-functions` (abnormal) |
| Function variables | end in `-function` |
| Lexical binding | `lexical-binding: t` at file top |
| `provide` feature | at end of file |
| Check with | `M-x checkdoc` |

### Don't change behavior on load
```elisp
;; WRONG: side effects at top level
(message "foo loaded")
(global-set-key (kbd "C-c f") #'foo-command)

;; RIGHT: provide command to enable
(defun foo-mode () ...)
```

## Package Authoring

### File header template
```elisp
;;; foo.el --- Do foo with bars  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Your Name

;; Author: Your Name <email>
;; Version: 1.0.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: convenience
;; URL: https://example.com/foo

;; This file is NOT part of GNU Emacs.

;;; Commentary:
;; Quick description, usage, and setup instructions.
;;
;;   (require 'foo)
;;   (foo-mode 1)

;;; Code:

;; ... definitions ...

(provide 'foo)
;;; foo.el ends here
```

### Writing Commentary

The `Commentary` section is what `M-x describe-package` shows. It must be
self-contained — a user who found the package on MELPA has no other context.

**Structure:**
1. One-line summary of what the package does
2. One-paragraph explanation with key features
3. Minimal setup code block (single `require` + enable)
4. Optionally: link to full README or manual

**Rules:**
- Every line starts with `;;` (two semicolons)
- Blank lines use `;;` alone (not empty)
- Closing uses `;;; Code:` as the boundary marker
- Do NOT repeat the file header (`;;; foo.el --- ...`) in Commentary

**Good example (gptel-hermes):**
```elisp
;;; Commentary:

;; gptel-hermes makes selected Hermes Agent capabilities available in Emacs
;; chat sessions through gptel.  It indexes bundled or user-provided
;; SKILL.md files, loads selected skills on demand, injects persistent
;; memory into the system prompt, and provides gptel tools for skill
;; viewing and memory management.
;;
;; Add `gptel-hermes-enable' to `gptel-mode-hook' to enable it
;; automatically:
;;
;;   (add-hook 'gptel-mode-hook #'gptel-hermes-enable)

;;; Code:
```

**Bad example:**
```elisp
;;; Commentary:

;; This package does stuff. See README for details.

;;; Code:
```

**Check:** `M-x checkdoc` validates Commentary completeness.

### Customization group and options
```elisp
(defgroup foo nil
  "Foo customization group."
  :group 'convenience
  :prefix "foo-")

(defcustom foo-bar t
  "Whether to bar."
  :type 'boolean
  :group 'foo)

(defcustom foo-count 42
  "Number of foos."
  :type 'integer
  :group 'foo)
```

### Autoload cookies
```elisp
;;;###autoload
(define-minor-mode foo-mode
  "Toggle foo mode."
  :global t
  :group 'foo
  ...)

;;;###autoload
(defun foo-do-thing ()
  "Do a thing."
  (interactive)
  ...)
```

### Minor mode (complete)
```elisp
;;;###autoload
(define-minor-mode foo-mode
  "Toggle Foo mode.
When enabled, bars all foos in the current buffer."
  :lighter " Foo"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c f b") #'foo-bar)
            (define-key map (kbd "C-c f q") #'foo-quit)
            map)
  (if foo-mode
      (progn
        (add-hook 'before-save-hook #'foo--on-save nil t)
        (foo--setup))
    (remove-hook 'before-save-hook #'foo--on-save t)
    (foo--teardown)))

(defun foo--on-save ()
  "Run before save in foo-mode buffers."
  (message "Foo saved"))

;;;###autoload
(define-globalized-minor-mode global-foo-mode
  foo-mode foo--turn-on
  :group 'foo)

(defun foo--turn-on ()
  "Enable `foo-mode' unless in a special buffer."
  (unless (or (minibufferp) (derived-mode-p 'special-mode))
    (foo-mode 1)))
```

### Package conventions checklist
- `lexical-binding: t` in the first line
- Header with `;;; foo.el ---` and `;;; Commentary:`
- `;;;###autoload` on public entry points
- `defgroup` / `defcustom` for user options
- Local hooks with `nil t` (buffer-local via `add-hook`)
- `provide` at end
- `M-x checkdoc` passes
- `M-x package-lint-current-buffer` passes (install `package-lint` from ELPA)

### Batch verification on macOS

If the `emacs` command is not on `PATH`, invoke the macOS application binary
directly at `/Applications/Emacs.app/Contents/MacOS/Emacs`:

```sh
/Applications/Emacs.app/Contents/MacOS/Emacs --batch -L /path/to/gptel -L . \
  -f batch-byte-compile foo.el
/Applications/Emacs.app/Contents/MacOS/Emacs --batch -L /path/to/gptel -L . -L tests \
  -l tests/foo-tests.el \
  -f ert-run-tests-batch-and-exit
```

## Error Handling

```elisp
(condition-case var
    (risky-operation)
  (error (message "Caught: %s" var)))
(condition-case nil
    (risky-operation)
  ((arith-error file-error) (fallback)))

(unwind-protect
    (do-stuff)
  (cleanup-1)
  (cleanup-2))  ; always runs, even on throw/error

;; Nonlocal exits
(catch 'my-tag
  (when (done) (throw 'my-tag result))
  ...)
```

## Key API Quickref

### Buffers
```elisp
(current-buffer)
(with-current-buffer buf body...)
(with-temp-buffer body...)       ; creates temp, kills after
(buffer-name) (buffer-file-name)
(get-buffer-create "*name*")
(set-buffer buf)                 ; only for primitive use; prefer with-current-buffer
```

### Text / Point
```elisp
(point) (point-min) (point-max)
(goto-char pos)
(insert "text") (insert-char char count)
(delete-region start end)
(delete-char count &optional killflag)
(buffer-substring start end)
(buffer-string)                  ; whole buffer content
(save-excursion body...)         ; restore point after
(save-restriction body...)       ; restore narrowing after
```

### Strings
```elisp
(concat a b c)
(format "value: %s" val)
(string-match regexp str)        ; returns index or nil
(replace-regexp-in-string regexp rep str)
(string-trim str)
(string-split str separator)
(string-join list separator)
```

### Searching
```elisp
(search-forward "text" limit t)  ; t = no error on fail
(re-search-forward regexp limit t)
(looking-at regexp)
(looking-back regexp limit)
(thing-at-point 'symbol)
```

### Lists
```elisp
(car x) (cdr x) (cons a b)
(nth n list)
(push val place) (pop place)
(mapcar fn list)
(mapc fn list)                   ; like mapcar but for side effects only
(dolist (x list) ...)
(string-to-list str)              ; string → list of chars (Emacs 30+)
;; NOTE: dolist does NOT accept strings directly — wrong-type-argument listp
(cl-remove-if pred list)
(cl-find item list)
(seq-filter pred list)           ; seq.el
```

### Hash Tables
```elisp
(make-hash-table :test 'equal)   ; 'eq (default), 'eql, 'equal
(puthash key val table)
(gethash key table default)
(remhash key table)
(maphash (lambda (k v) ...) table)
```

### Minor Mode Template
```elisp
(define-minor-mode foo-mode
  "Toggle foo mode."
  :lighter " Foo"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c f") #'foo-command)
            map)
  (if foo-mode
      (add-hook 'after-save-hook #'foo-on-save nil t)
    (remove-hook 'after-save-hook #'foo-on-save t)))
```

## Debugging

```elisp
(debug)                    ; enter debugger at this point
(debug-on-entry 'fn-name)  ; break on function entry
(cancel-debug-on-entry)
(trace-function 'fn-name)  ; trace calls
(untrace-function 'fn-name)
(message "debug: %S" val)  ; quick print (to *Messages* buffer)
(backtrace)                 ; print call stack
```

## Common Pitfalls

1. **Quoting in `add-hook`**: `(add-hook 'hook #'my-fn)` — use `#'`, not `'my-fn`
2. **`let` order**: bindings are parallel — `(let ((x 1) (y x)) ...)` y gets OLD x
3. **`defvar` doesn't reset**: if var already has value, `defvar` won't change it
4. **`dolist` return**: optional result form — `(dolist (x list result) ...)`
5. **`while` always returns nil**
6. **List mutability**: `'(1 2 3)` returns a shared constant — don't mutate it
7. **Lexical scoping**: `symbol-value` can't see lexical bindings
8. **Macro argument evaluation**: use `let` to avoid double evaluation
9. **`eval-when-compile` for macros**: if a file only uses macros from another package, don't `require` at runtime
