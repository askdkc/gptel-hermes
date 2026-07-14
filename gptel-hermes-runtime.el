;;; gptel-hermes-runtime.el --- Native runtime tools for gptel-hermes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 dkc

;;; Commentary:

;; Workspace-scoped files, Git patches, terminal processes, and deliberately
;; bounded Emacs Lisp tools for gptel-hermes.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'subr-x)
(require 'gptel)

(defgroup gptel-hermes-runtime nil
  "Native runtime tools for gptel-hermes."
  :group 'gptel-hermes)

(defcustom gptel-hermes-enable-unsafe-elisp-eval nil
  "Whether to expose the unsandboxed `hermes_elisp_eval' tool.

Enabling this gives the model the full permissions of the Emacs process."
  :type 'boolean
  :group 'gptel-hermes-runtime)

(defcustom gptel-hermes-elisp-call-allowlist
  '("buffer-name" "buffer-file-name" "buffer-string" "point"
    "point-min" "point-max")
  "Read-only function names accepted by `hermes_elisp_call'.

Adding a mutating or secret-reading function changes the security boundary."
  :type '(repeat string)
  :group 'gptel-hermes-runtime)

(defcustom gptel-hermes-terminal-timeout 30
  "Default timeout in seconds for `hermes_terminal'."
  :type 'number
  :group 'gptel-hermes-runtime)

(defconst gptel-hermes-runtime--max-file-bytes (* 8 1024 1024))
(defconst gptel-hermes-runtime--max-file-write-bytes (* 1 1024 1024))
(defconst gptel-hermes-runtime--max-output-bytes (* 128 1024))
(defconst gptel-hermes-runtime--max-process-output-bytes (* 64 1024))
(defconst gptel-hermes-runtime--max-patch-bytes (* 1 1024 1024))
(defconst gptel-hermes-runtime--max-elisp-output-bytes (* 64 1024))
(defconst gptel-hermes-runtime--max-terminal-timeout 300)
(defconst gptel-hermes-runtime--safe-environment
  '("PATH" "LANG" "LC_ALL" "LC_CTYPE" "TMPDIR"))
(defconst gptel-hermes-runtime--fixed-environment
  '(("CI" . "1")
    ("PAGER" . "cat")
    ("GIT_PAGER" . "cat")
    ("GIT_TERMINAL_PROMPT" . "0")
    ("TERM" . "dumb")
    ("NO_COLOR" . "1")))

(defvar-local gptel-hermes--workspace-root nil
  "Canonical workspace root for the current buffer, or nil.")
(defvar-local gptel-hermes--workspace-initial-directory nil
  "Initial `default-directory' captured for workspace selection.")
(defvar-local gptel-hermes--workspace-initialized-p nil
  "Non-nil after the current buffer has captured its workspace decision.")

(defun gptel-hermes-runtime--error-string (error-data)
  "Return a concise string for ERROR-DATA."
  (if (condition-case nil
          (error-message-string error-data)
        (error nil))
      (error-message-string error-data)
    (format "%s" error-data)))

(defun gptel-hermes-runtime--remote-p (path)
  "Return non-nil when PATH is a TRAMP path."
  (or (file-remote-p path) (file-remote-p default-directory)))

(defun gptel-hermes-runtime--canonical-directory (path)
  "Return canonical directory PATH, or signal an actionable error."
  (when (gptel-hermes-runtime--remote-p path)
    (error "TRAMP workspaces are not supported"))
  (let ((expanded (file-name-as-directory (expand-file-name path))))
    (unless (file-directory-p expanded)
      (error "Workspace directory does not exist: %s" path))
    (file-name-as-directory (file-truename expanded))))

(defun gptel-hermes-runtime--home-directory ()
  "Return the canonical user's home directory."
  (file-name-as-directory (file-truename (expand-file-name "~"))))

(defun gptel-hermes-runtime--under-p (path directory)
  "Return non-nil when canonical PATH is DIRECTORY or below it."
  (let ((directory (file-name-as-directory (file-truename directory)))
        (path (file-name-as-directory (file-truename path))))
    (or (string= path directory)
        (string-prefix-p directory path))))

(defun gptel-hermes-runtime--initial-workspace-candidate (directory)
  "Return an automatic workspace candidate for DIRECTORY, or nil."
  (when (gptel-hermes-runtime--remote-p directory)
    (error "TRAMP workspaces are not supported"))
  (let* ((directory (gptel-hermes-runtime--canonical-directory directory))
         (home (gptel-hermes-runtime--home-directory))
         (project (ignore-errors (project-current nil directory)))
         (project-root (and project
                            (project-root project)
                            (gptel-hermes-runtime--canonical-directory
                             (project-root project)))))
    (cond
     ((and project-root
           (gptel-hermes-runtime--under-p project-root home)
           (not (string= project-root home)))
      project-root)
     ((and (gptel-hermes-runtime--under-p directory home)
           (not (string= directory home)))
      directory)
     (t nil))))

(defun gptel-hermes-runtime-initialize-workspace ()
  "Capture the current buffer's workspace decision once."
  (unless gptel-hermes--workspace-initialized-p
    (setq-local gptel-hermes--workspace-initial-directory
                (expand-file-name default-directory))
    (setq-local gptel-hermes--workspace-root
                (gptel-hermes-runtime--initial-workspace-candidate
                 gptel-hermes--workspace-initial-directory))
    (setq-local gptel-hermes--workspace-initialized-p t))
  gptel-hermes--workspace-root)

(defun gptel-hermes-workspace-root ()
  "Return the current workspace root, showing it when called interactively."
  (interactive)
  (let ((root gptel-hermes--workspace-root))
    (when (called-interactively-p 'interactive)
      (message "%s" (or root "Workspace is unset")))
    root))

(defun gptel-hermes-set-workspace (&optional directory)
  "Set the current buffer's workspace to DIRECTORY."
  (interactive (list (read-directory-name "Workspace: " default-directory nil t)))
  (setq-local gptel-hermes--workspace-root
              (gptel-hermes-runtime--canonical-directory directory))
  (setq-local gptel-hermes--workspace-initialized-p t)
  (when (called-interactively-p 'interactive)
    (message "gptel-hermes workspace: %s" gptel-hermes--workspace-root))
  gptel-hermes--workspace-root)

(defun gptel-hermes-clear-workspace ()
  "Clear the current buffer's workspace."
  (interactive)
  (setq-local gptel-hermes--workspace-root nil
              gptel-hermes--workspace-initialized-p t)
  (when (called-interactively-p 'interactive)
    (message "gptel-hermes workspace cleared"))
  nil)

(defun gptel-hermes-workspace-status ()
  "Return and, interactively, display the current workspace status."
  (interactive)
  (let ((status (if gptel-hermes--workspace-root
                    (format "Workspace: %s" gptel-hermes--workspace-root)
                  "Workspace unset; use gptel-hermes-set-workspace")))
    (when (called-interactively-p 'interactive)
      (message "%s" status))
    status))

(defun gptel-hermes-runtime--workspace-or-error ()
  "Return the current workspace or signal an actionable error."
  (or gptel-hermes--workspace-root
      (error "Hermes workspace is unset; use gptel-hermes-set-workspace")))

(defun gptel-hermes-runtime--path-components (path)
  "Return slash-separated components of PATH."
  (split-string (replace-regexp-in-string "\\\\" "/" path) "/" t))

(defun gptel-hermes-runtime--secret-path-p (relative)
  "Return non-nil when RELATIVE names a sensitive path."
  (let* ((parts (gptel-hermes-runtime--path-components relative))
         (basename (car (last parts))))
    (or (member ".git" parts)
        (member ".ssh" parts)
        (member ".gnupg" parts)
        (member ".aws" parts)
        (member ".kube" parts)
        (and (string-match-p "\\`\\.env\\(?:\\..+\\)?\\'" basename)
             (not (member basename '(".env.example" ".env.sample"
                                      ".env.template"))))
        (string-match-p "\\`\\.authinfo" basename)
        (member basename '(".netrc" ".npmrc" ".pypirc" "id_rsa"
                           "id_ed25519" "credentials.json"))
        (string-match-p "\\.\\(?:pem\\|key\\)\\'" basename)
        (string-match-p "\\`service-account.*\\.json\\'" basename))))

(defun gptel-hermes-runtime--reject-dot-dot (path)
  "Reject parent components in PATH."
  (when (member ".." (gptel-hermes-runtime--path-components path))
    (error "Path must not contain ..: %s" path)))

(defun gptel-hermes-runtime--nearest-existing-parent (path)
  "Return (CANONICAL-PARENT . REMAINING-COMPONENTS) for PATH."
  (let ((candidate path)
        (remaining nil))
    (while (and (not (file-exists-p candidate))
                (not (file-symlink-p candidate)))
      (let ((name (file-name-nondirectory (directory-file-name candidate))))
        (when (string-empty-p name)
          (error "No existing parent for path: %s" path))
        (push name remaining)
        (setq candidate (file-name-directory (directory-file-name candidate)))))
    (cons (file-truename candidate) remaining)))

(defun gptel-hermes-runtime--resolve-path (path operation &optional allow-missing)
  "Resolve PATH under the workspace for OPERATION.

OPERATION is one of `read', `write', `cwd', or `patch'.  When
ALLOW-MISSING is non-nil, the final destination may not exist."
  (unless (and (stringp path) (not (string-empty-p path)))
    (error "Path must be a non-empty string"))
  (when (string-match-p "[\0\r\n]" path)
    (error "Path contains a control character"))
  (gptel-hermes-runtime--reject-dot-dot path)
  (let* ((root (gptel-hermes-runtime--workspace-or-error))
         (root (file-name-as-directory (file-truename root)))
         (expanded (expand-file-name path root))
         (relative (file-relative-name expanded root)))
    (when (gptel-hermes-runtime--remote-p expanded)
      (error "Remote paths are not supported"))
    (when (or (string-prefix-p "../" relative)
              (string= relative ".."))
      (error "Path escapes the workspace: %s" path))
    (when (gptel-hermes-runtime--secret-path-p relative)
      (error "Refusing access to a secret path: %s" path))
    (pcase-let ((`(,parent . ,remaining)
                 (gptel-hermes-runtime--nearest-existing-parent expanded)))
      (let* ((canonical
              (file-name-as-directory parent))
             (canonical
              (directory-file-name
               (expand-file-name (mapconcat #'identity remaining "/") canonical)))
             (exists (or (file-exists-p expanded) (file-symlink-p expanded)))
             (canonical-relative (file-relative-name canonical root)))
        (unless (gptel-hermes-runtime--under-p canonical root)
          (error "Path escapes the workspace through a symlink: %s" path))
        (when (gptel-hermes-runtime--secret-path-p canonical-relative)
          (error "Refusing access to a secret path: %s" path))
        (when (and (eq operation 'cwd)
                   (not (file-directory-p expanded)))
          (error "Working directory is not a directory: %s" path))
        (when (and (memq operation '(read patch))
                   (not exists)
                   (not allow-missing))
          (error "Path does not exist: %s" path))
        (list :path canonical
              :relative canonical-relative
              :root root
              :exists exists
              :directory-p (file-directory-p expanded)
              :symlink-p (file-symlink-p expanded))))))

(defun gptel-hermes-runtime--file-sha256 (path)
  "Return the byte SHA-256 of regular PATH."
  (with-temp-buffer
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defun gptel-hermes-runtime--truncate-string (text limit)
  "Return TEXT bounded to LIMIT bytes, with an explicit marker."
  (if (<= (string-bytes text) limit)
      text
    (let* ((marker "\n[output truncated]")
           (budget (max 0 (- limit (string-bytes marker))))
           (low 0)
           (high (length text)))
      (while (< low high)
        (let* ((middle (/ (+ low high 1) 2))
               (candidate (substring text 0 middle)))
          (if (<= (string-bytes candidate) budget)
              (setq low middle)
            (setq high (1- middle)))))
      (concat (substring text 0 low) marker))))

(defun gptel-hermes-file-read (path &optional start-line end-line)
  "Read PATH from the workspace, optionally limiting START-LINE through END-LINE."
  (let* ((resolved (gptel-hermes-runtime--resolve-path path 'read))
         (file (plist-get resolved :path)))
    (unless (file-regular-p file)
      (error "Path is not a regular file: %s" path))
    (unless (file-readable-p file)
      (error "File is not readable: %s" path))
    (when (> (file-attribute-size (file-attributes file))
             gptel-hermes-runtime--max-file-bytes)
      (error "Input file exceeds %d bytes: %s"
             gptel-hermes-runtime--max-file-bytes path))
    (let ((content (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))
      (when (string-match-p "\0" content)
        (error "Binary/NUL-containing files are not supported: %s" path))
      (let* ((total (if (string-empty-p content)
                        0
                      (with-temp-buffer
                        (insert content)
                        (count-lines (point-min) (point-max)))))
             (start (or start-line 1))
             (end (or end-line total)))
        (unless (or (and (= total 0)
                         (= start 1)
                         (or (= end 0) (= end 1)))
                    (and (integerp start) (> start 0)
                         (integerp end) (>= end start)
                         (<= start total) (<= end total)))
          (error "Invalid line range %s-%s for %d lines" start end total))
        (let ((selected
               (if (or (= total 0) (and (= start 1) (= end total)))
                   content
                 (with-temp-buffer
                   (insert content)
                   (goto-char (point-min))
                   (forward-line (1- start))
                   (let ((begin (point)))
                     (forward-line (- end start -1))
                     (buffer-substring-no-properties begin (point))))))
              (truncated nil))
          (when (> (string-bytes selected)
                   gptel-hermes-runtime--max-output-bytes)
            (setq selected
                  (gptel-hermes-runtime--truncate-string
                   selected gptel-hermes-runtime--max-output-bytes)
                  truncated t))
          (format "Path: %s\nSHA-256: %s\nLines: %d-%d of %d\nTruncated: %s\n\n%s"
                  (plist-get resolved :relative)
                  (gptel-hermes-runtime--file-sha256 file)
                  (if (= total 0) 0 start)
                  (if (= total 0) 0 end)
                  total
                  (if truncated "yes" "no")
                  selected))))))

(defun gptel-hermes-runtime--write-file-atomically (path content mode replace)
  "Write CONTENT to PATH atomically, preserving MODE when supplied.

When REPLACE is nil, fail if another writer created PATH after preflight."
  (let ((directory (file-name-directory path))
        (temporary nil))
    (make-directory directory t)
    (setq temporary
          (make-temp-file (expand-file-name "hermes-file-" directory)
                          nil ".tmp"))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region content nil temporary nil 'silent))
          (when mode
            (set-file-modes temporary mode))
          (setq mode nil)
          (rename-file temporary path replace)
          (setq temporary nil))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))))

(defun gptel-hermes-file-write (path content mode &optional expected-sha256)
  "Create or replace PATH with CONTENT using MODE and EXPECTED-SHA256."
  (unless (member mode '("create" "replace"))
    (error "Mode must be create or replace"))
  (unless (stringp content)
    (error "Content must be a string"))
  (when (> (string-bytes content) gptel-hermes-runtime--max-file-write-bytes)
    (error "File content exceeds %d bytes"
           gptel-hermes-runtime--max-file-write-bytes))
  (let* ((resolved (gptel-hermes-runtime--resolve-path path 'write t))
         (destination (plist-get resolved :path))
         (exists (plist-get resolved :exists)))
    (when (plist-get resolved :symlink-p)
      (error "Refusing a symlink destination: %s" path))
    (when (and exists (file-directory-p destination))
      (error "Destination is a directory: %s" path))
    (pcase mode
      ("create"
       (when exists (error "Destination already exists: %s" path)))
      ("replace"
       (unless (and (stringp expected-sha256)
                    (not (string-empty-p expected-sha256)))
         (error "Replace requires expected_sha256"))
       (unless exists (error "Destination does not exist: %s" path))
       (unless (file-regular-p destination)
         (error "Destination is not a regular file: %s" path))
       (unless (string= (downcase expected-sha256)
                        (downcase (gptel-hermes-runtime--file-sha256 destination)))
         (error "Stale SHA-256 for %s" path))))
    (let ((permissions (and exists (file-modes destination))))
      (gptel-hermes-runtime--write-file-atomically
       destination content permissions (string= mode "replace"))
      (format "Path: %s\nMode: %s\nSHA-256: %s"
              (plist-get resolved :relative) mode
              (gptel-hermes-runtime--file-sha256 destination)))))

(defun gptel-hermes-runtime--git-run (root &rest args)
  "Run Git with ARGS in ROOT and return (STATUS OUTPUT)."
  (with-temp-buffer
    (let* ((default-directory root)
           (status (condition-case error-data
                       (apply #'process-file "git" nil t nil args)
                     (file-missing
                      (list 'file-missing (gptel-hermes-runtime--error-string
                                           error-data))))))
      (list status (buffer-string)))))

(defun gptel-hermes-runtime--git-root (workspace)
  "Return Git's canonical top-level for WORKSPACE."
  (pcase-let ((`(,status ,output)
               (gptel-hermes-runtime--git-run workspace "rev-parse"
                                              "--show-toplevel")))
    (when (or (not (integerp status)) (/= status 0))
      (error "Workspace is not a Git repository: %s" (string-trim output)))
    (file-name-as-directory (file-truename (string-trim output)))))

(defun gptel-hermes-runtime--validate-patch-path (path)
  "Validate a Git patch PATH below ROOT."
  (unless (and (stringp path) (not (string-empty-p path)))
    (error "Git patch contains an empty path"))
  (let ((resolved (gptel-hermes-runtime--resolve-path path 'patch t)))
    (when (plist-get resolved :symlink-p)
      (error "Git patch path must not be a symlink: %s" path))
    (when (and (plist-get resolved :exists)
               (not (file-regular-p (plist-get resolved :path))))
      (error "Git patch path is not a regular file: %s" path)))
  path)

(defun gptel-hermes-runtime--patch-paths (numstat)
  "Return and validate paths reported by NUMSTAT below the workspace."
  (let (paths)
    (dolist (field (split-string numstat "\0" t) (nreverse paths))
      (let ((path (if (string-match "\\`[^\t]*\t[^\t]*\t\\(.*\\)\\'" field)
                      (match-string 1 field)
                    field)))
        (push (gptel-hermes-runtime--validate-patch-path path) paths)))))

(defun gptel-hermes-runtime--git-summary-path (path)
  "Decode one Git PATH, including simple C-style quoting."
  (if (and (> (length path) 1)
           (eq (aref path 0) ?\")
           (eq (aref path (1- (length path))) ?\"))
      (condition-case nil
          (car (read-from-string path))
        (error path))
    path))

(defun gptel-hermes-runtime--patch-body-paths (patch)
  "Validate rename and copy paths declared in PATCH's body.

Git's `--summary' output may compress a pair of paths with braces, which
loses the actual source path.  The patch body retains each path verbatim in
`rename from/to' and `copy from/to' records, so validate those records
directly instead."
  (dolist (line (split-string patch "\n" t))
    (when (string-match
           "\\`\\(?:rename\\|copy\\) \\(?:from\\|to\\) \\(.*\\)\\'"
           line)
      (let ((path (gptel-hermes-runtime--git-summary-path
                   (string-trim-right (match-string 1 line) "\r"))))
        (gptel-hermes-runtime--validate-patch-path
         path)))))

(defun gptel-hermes-runtime--json-true-p (value)
  "Return non-nil when VALUE is a JSON true value, not JSON false."
  (and value (not (memq value '(:json-false json-false)))))

(defun gptel-hermes-apply-patch (patch &optional check-only)
  "Check or apply standard unified Git PATCH; CHECK-ONLY controls mutation."
  (unless (stringp patch)
    (error "Patch must be a string"))
  (when (> (string-bytes patch) gptel-hermes-runtime--max-patch-bytes)
    (error "Patch exceeds %d bytes" gptel-hermes-runtime--max-patch-bytes))
  (setq check-only (gptel-hermes-runtime--json-true-p check-only))
  (let* ((workspace (gptel-hermes-runtime--workspace-or-error))
         (workspace (file-name-as-directory (file-truename workspace)))
         (git-root (gptel-hermes-runtime--git-root workspace)))
    (unless (string= workspace git-root)
      (error "Workspace must be the canonical Git top-level: %s" git-root))
    (let ((patch-file
           (make-temp-file (expand-file-name "hermes-patch-" workspace)
                           nil ".diff")))
      (unwind-protect
          (let* ((coding-system-for-write 'utf-8-unix)
                 (_ (write-region patch nil patch-file nil 'silent))
                 (numstat-result
                  (gptel-hermes-runtime--git-run
                   workspace "apply" "--numstat" "-z" patch-file))
                 (numstat-status (car numstat-result))
                 (numstat (cadr numstat-result)))
            (when (or (not (integerp numstat-status)) (/= numstat-status 0))
              (error "Git apply --numstat failed: %s" (string-trim numstat)))
            (gptel-hermes-runtime--patch-body-paths patch)
            (gptel-hermes-runtime--patch-paths numstat)
            (let* ((stat-result
                    (gptel-hermes-runtime--git-run
                     workspace "apply" "--stat" patch-file))
                   (stat-status (car stat-result))
                   (stat (cadr stat-result)))
              (when (or (not (integerp stat-status)) (/= stat-status 0))
                (error "Git apply --stat failed: %s" (string-trim stat)))
              (let* ((check-result
                      (gptel-hermes-runtime--git-run
                       workspace "apply" "--check" patch-file))
                     (check-status (car check-result))
                     (check (cadr check-result)))
                (when (or (not (integerp check-status)) (/= check-status 0))
                  (error "Git apply --check failed: %s" (string-trim check)))
                (unless check-only
                  (let* ((apply-result
                          (gptel-hermes-runtime--git-run
                           workspace "apply" patch-file))
                         (apply-status (car apply-result))
                         (apply-output (cadr apply-result)))
                    (when (or (not (integerp apply-status)) (/= apply-status 0))
                      (error "Git apply failed: %s" (string-trim apply-output)))))
                (format "Patch: %s\nWorkspace: %s\n\n%s"
                        (if check-only "check passed" "applied")
                        workspace
                        (string-trim-right stat)))))
        (when (file-exists-p patch-file)
          (delete-file patch-file))))))

(defun gptel-hermes-runtime--list-arguments (arguments)
  "Convert JSON ARRAY ARGUMENTS to a proper list of strings."
  (let ((arguments (cond
                    ((null arguments) nil)
                    ((vectorp arguments) (append arguments nil))
                    ((listp arguments) arguments)
                    (t (error "Arguments must be a JSON array")))))
    (dolist (argument arguments arguments)
      (unless (and (stringp argument)
                   (not (string-match-p "[\0\r\n]" argument)))
        (error "Terminal arguments must be strings without control characters")))))

(defun gptel-hermes-runtime--terminal-environment (home)
  "Return a sanitized process environment using temporary HOME."
  (let (environment)
    (dolist (name gptel-hermes-runtime--safe-environment)
      (when-let ((value (getenv name)))
        (push (concat name "=" value) environment)))
    (dolist (entry gptel-hermes-runtime--fixed-environment)
      (push (concat (car entry) "=" (cdr entry)) environment))
    (push (concat "HOME=" home) environment)
    environment))

(defun gptel-hermes-runtime--terminal-state (process)
  "Return terminal state stored on PROCESS."
  (let ((value (process-get process 'gptel-hermes-terminal-state)))
    (if (and (consp value) (listp (car value)))
        (car value)
      value)))

(defun gptel-hermes-runtime--terminal-set-state (process state)
  "Store shared terminal STATE on PROCESS and its stderr process."
  (let ((cell (process-get process 'gptel-hermes-terminal-state)))
    (if (and (consp cell) (listp (car cell)))
        (setcar cell state)
      (process-put process 'gptel-hermes-terminal-state state))))

(defun gptel-hermes-runtime--terminal-filter (process output stream)
  "Append OUTPUT from PROCESS to STREAM's bounded buffer."
  (let* ((state (gptel-hermes-runtime--terminal-state process))
         (buffer (plist-get state stream))
         (truncated-key (if (eq stream :stdout) :stdout-truncated
                          :stderr-truncated)))
    (when (and state (buffer-live-p buffer)
               (not (plist-get state truncated-key)))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert output)
        (when (> (string-bytes (buffer-string))
                 gptel-hermes-runtime--max-process-output-bytes)
          (let ((bounded
                 (gptel-hermes-runtime--truncate-string
                  (buffer-string)
                  gptel-hermes-runtime--max-process-output-bytes)))
            (erase-buffer)
            (insert bounded)
            (setq state (plist-put state truncated-key t)))))
      (gptel-hermes-runtime--terminal-set-state process state))))

(defun gptel-hermes-runtime--terminal-filter-stdout (process output)
  "Process filter for PROCESS stdout; OUTPUT is appended to its buffer."
  (gptel-hermes-runtime--terminal-filter process output :stdout))

(defun gptel-hermes-runtime--terminal-filter-stderr (process output)
  "Process filter for PROCESS stderr; OUTPUT is appended to its buffer."
  (gptel-hermes-runtime--terminal-filter process output :stderr))

(defun gptel-hermes-runtime--terminal-timeout (process)
  "Terminate PROCESS after its timeout."
  (when (process-live-p process)
    (let ((state (gptel-hermes-runtime--terminal-state process)))
      (gptel-hermes-runtime--terminal-set-state
       process (plist-put state :timed-out t)))
    (delete-process process)))

(defun gptel-hermes-runtime--terminal-result (process)
  "Build and clean up the completed terminal PROCESS."
  (let* ((state (gptel-hermes-runtime--terminal-state process))
         (done (plist-get state :done)))
    (unless done
      (setq state (plist-put state :done t))
      (gptel-hermes-runtime--terminal-set-state process state)
      (when-let ((timer (plist-get state :timer)))
        (cancel-timer timer))
      (let* ((stdout-buffer (plist-get state :stdout))
             (stderr-buffer (plist-get state :stderr))
             (stdout (if (buffer-live-p stdout-buffer)
                         (with-current-buffer stdout-buffer (buffer-string))
                       ""))
             (stderr (if (buffer-live-p stderr-buffer)
                         (with-current-buffer stderr-buffer (buffer-string))
                       ""))
             (stderr-truncated (> (string-bytes stderr)
                                  gptel-hermes-runtime--max-process-output-bytes))
             (stderr (if stderr-truncated
                         (gptel-hermes-runtime--truncate-string
                          stderr gptel-hermes-runtime--max-process-output-bytes)
                       stderr))
             (timed-out (plist-get state :timed-out))
             (status (unless timed-out (process-exit-status process)))
             (result (format "Program: %s\nExit status: %s\nTimed out: %s\n"
                             (plist-get state :program)
                             (if timed-out "terminated" status)
                             (if timed-out "yes" "no"))))
        (setq result
              (concat result
                      (format "Stdout truncated: %s\nStderr truncated: %s\n\n"
                              (if (plist-get state :stdout-truncated) "yes" "no")
                              (if (or (plist-get state :stderr-truncated)
                                      stderr-truncated)
                                  "yes" "no"))
                      "STDOUT:\n" stdout
                      "\nSTDERR:\n" stderr))
        (when-let ((stderr-process (plist-get state :stderr-process)))
          (when (process-live-p stderr-process)
            (delete-process stderr-process)))
        (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
        (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
        (when-let ((home (plist-get state :home)))
          (when (file-directory-p home)
            (delete-directory home t)))
        (funcall (plist-get state :callback) result)))))

(defun gptel-hermes-runtime--terminal-sentinel (process _event)
  "Finish PROCESS exactly once when it exits."
  (when (memq (process-status process) '(exit signal closed failed))
    (gptel-hermes-runtime--terminal-result process)))

(defun gptel-hermes-terminal (callback program arguments &optional cwd timeout)
  "Run PROGRAM asynchronously and call CALLBACK with a bounded result."
  (condition-case error-data
      (let* ((workspace (gptel-hermes-runtime--workspace-or-error))
             (cwd (if cwd
                      (plist-get (gptel-hermes-runtime--resolve-path cwd 'cwd)
                                 :path)
                    workspace))
             (arguments (gptel-hermes-runtime--list-arguments arguments))
             (timeout (or timeout gptel-hermes-terminal-timeout)))
        (unless (and (stringp program) (not (string-empty-p program)))
          (error "Program must be a non-empty string"))
        (unless (and (numberp timeout) (> timeout 0))
          (error "Timeout must be positive"))
        (setq timeout (min timeout gptel-hermes-runtime--max-terminal-timeout))
        (let* ((home (make-temp-file "hermes-home-" t))
               (stdout (generate-new-buffer " *hermes-terminal stdout*"))
               (stderr (generate-new-buffer " *hermes-terminal stderr*"))
               (stderr-process nil)
               (state-cell nil)
               (process-environment
                (gptel-hermes-runtime--terminal-environment home))
               (default-directory cwd))
          (condition-case process-error
              (progn
                (setq stderr-process
                      (make-pipe-process
                       :name "gptel-hermes-terminal stderr"
                       :buffer stderr
                       :noquery t))
              (let ((process (make-process
                              :name "gptel-hermes-terminal"
                              :command (cons program arguments)
                              :buffer stdout
                              :stderr stderr-process
                              :connection-type 'pipe
                              :noquery t
                              :filter #'gptel-hermes-runtime--terminal-filter-stdout
                              :sentinel #'gptel-hermes-runtime--terminal-sentinel)))
                (setq state-cell
                      (list (list :callback callback :program program
                                  :stdout stdout :stderr stderr :home home)))
                (process-put process 'gptel-hermes-terminal-state state-cell)
                (process-put stderr-process 'gptel-hermes-terminal-state state-cell)
                (set-process-filter stderr-process
                                     #'gptel-hermes-runtime--terminal-filter-stderr)
                (set-process-filter process #'gptel-hermes-runtime--terminal-filter-stdout)
                (set-process-sentinel process #'gptel-hermes-runtime--terminal-sentinel)
                (set-process-query-on-exit-flag process nil)
                ;; No stdin argument is exposed.  Close the pipe so readers
                ;; exit instead of waiting until the timeout.
                (process-send-eof process)
                (gptel-hermes-runtime--terminal-set-state
                 process
                 (plist-put
                  (plist-put (gptel-hermes-runtime--terminal-state process)
                            :stderr-process stderr-process)
                  :timer
                  (run-at-time timeout nil
                               #'gptel-hermes-runtime--terminal-timeout
                               process)))))
            (error
             (when (and stderr-process (process-live-p stderr-process))
               (delete-process stderr-process))
             (when (buffer-live-p stdout) (kill-buffer stdout))
             (when (buffer-live-p stderr) (kill-buffer stderr))
             (when (file-directory-p home) (delete-directory home t))
             (funcall callback
                      (format "Terminal error: %s"
                              (gptel-hermes-runtime--error-string process-error)))))))
    (error
     (funcall callback (format "Terminal error: %s"
                               (gptel-hermes-runtime--error-string error-data))))))

(defun gptel-hermes-runtime--elisp-function-name (function)
  "Validate FUNCTION as an allowlisted function name."
  (unless (stringp function)
    (error "Function must be a string"))
  (let ((allowed (mapcar (lambda (item)
                           (if (symbolp item) (symbol-name item) item))
                         gptel-hermes-elisp-call-allowlist)))
    (unless (member function allowed)
      (error "Function is not allowlisted: %s" function))
    (intern function)))

(defun gptel-hermes-elisp-call (function &optional arguments)
  "Call one allowlisted Emacs Lisp FUNCTION with JSON ARRAY ARGUMENTS."
  (let* ((symbol (gptel-hermes-runtime--elisp-function-name function))
         (arguments (cond
                     ((null arguments) nil)
                     ((vectorp arguments) (append arguments nil))
                     ((listp arguments) arguments)
                     (t (error "Arguments must be a JSON array")))))
    (unless (fboundp symbol)
      (error "Allowlisted function is not defined: %s" function))
    (gptel-hermes-runtime--truncate-string
     (format "Function: %s\nResult: %s"
             function (prin1-to-string (apply symbol arguments)))
     gptel-hermes-runtime--max-elisp-output-bytes)))

(defun gptel-hermes-runtime--read-one-form (text)
  "Read exactly one Lisp form from TEXT."
  (unless (stringp text)
    (error "Form must be a string"))
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (let ((form (read (current-buffer))))
      (skip-chars-forward " \t\r\n")
      (unless (eobp)
        (error "Trailing non-whitespace data after one form"))
      form)))

(defun gptel-hermes-elisp-eval (form)
  "Evaluate exactly one unsandboxed Emacs Lisp FORM."
  (unless gptel-hermes-enable-unsafe-elisp-eval
    (error "Unsafe Elisp evaluation is disabled; set gptel-hermes-enable-unsafe-elisp-eval"))
  (gptel-hermes-runtime--truncate-string
   (format "Warning: unsandboxed Emacs Lisp evaluation\nResult: %s"
           (prin1-to-string (eval (gptel-hermes-runtime--read-one-form form) t)))
   gptel-hermes-runtime--max-elisp-output-bytes))

(defun gptel-hermes-runtime--confirm-patch (&rest arguments)
  "Confirm patch application unless ARGUMENTS request a check only."
  (not (gptel-hermes-runtime--json-true-p (cadr arguments))))

(defvar gptel-hermes--runtime-file-read-tool
  (gptel-make-tool
   :name "hermes_file_read"
   :function #'gptel-hermes-file-read
   :description "Read a bounded text file inside the captured Hermes workspace and return its SHA-256."
   :args (list '(:name "path" :type string :description "Workspace-relative file path")
               '(:name "start_line" :type integer :optional t
                 :description "One-based first line")
               '(:name "end_line" :type integer :optional t
                 :description "One-based inclusive last line"))
   :category "hermes-runtime" :confirm nil :include t))

(defvar gptel-hermes--runtime-file-write-tool
  (gptel-make-tool
   :name "hermes_file_write"
   :function #'gptel-hermes-file-write
   :description "Atomically create or replace a text file inside the Hermes workspace. Replace requires the SHA-256 returned by hermes_file_read."
   :args (list '(:name "path" :type string :description "Workspace-relative file path")
               '(:name "content" :type string :description "Replacement file contents")
               '(:name "mode" :type string :enum ["create" "replace"]
                 :description "Create a new file or replace an existing one")
               '(:name "expected_sha256" :type string :optional t
                 :description "Required for replace"))
   :category "hermes-runtime" :confirm t :include t))

(defvar gptel-hermes--runtime-apply-patch-tool
  (gptel-make-tool
   :name "hermes_apply_patch"
   :function #'gptel-hermes-apply-patch
   :description "Check or apply a standard unified Git patch at the captured workspace top-level."
   :args (list '(:name "patch" :type string :description "Standard unified diff")
               '(:name "check_only" :type boolean :optional t
                 :description "Only validate the patch when true"))
   :category "hermes-runtime" :confirm #'gptel-hermes-runtime--confirm-patch
   :include t))

(defvar gptel-hermes--runtime-terminal-tool
  (gptel-make-tool
   :name "hermes_terminal"
   :function #'gptel-hermes-terminal
   :description "Run an executable asynchronously with an argv array in the Hermes workspace. Standard input is closed. This is not an OS sandbox; confirmed programs can access the network and absolute paths."
   :args (list '(:name "program" :type string :description "Executable name or path")
               '(:name "arguments" :type array :items (:type string)
                 :description "Argument strings; no shell is inserted")
               '(:name "cwd" :type string :optional t
                 :description "Workspace-relative working directory")
               '(:name "timeout" :type number :optional t
                 :description "Timeout in seconds, capped at 300"))
   :category "hermes-runtime" :confirm t :async t :include t))

(defvar gptel-hermes--runtime-elisp-call-tool
  (gptel-make-tool
   :name "hermes_elisp_call"
   :function #'gptel-hermes-elisp-call
   :description "Call one explicitly allowlisted read-only Emacs Lisp function. The allowlist is the security boundary."
   :args (list '(:name "function" :type string :description "Exact allowlisted function name")
               '(:name "arguments" :type array :items (:type string) :optional t
                 :description "JSON array converted to Lisp arguments"))
   :category "hermes-runtime" :confirm nil :include t))

(defvar gptel-hermes--runtime-elisp-eval-tool
  nil
  "Lazily-created unsafe Elisp tool, or nil until explicitly enabled.")

(defun gptel-hermes-runtime--unsafe-elisp-eval-tool ()
  "Return the lazily-created unsafe Elisp tool."
  (or gptel-hermes--runtime-elisp-eval-tool
      (setq gptel-hermes--runtime-elisp-eval-tool
            (gptel-make-tool
             :name "hermes_elisp_eval"
             :function #'gptel-hermes-elisp-eval
             :description "Evaluate exactly one form with the full permissions of Emacs. Unsandboxed and disabled unless explicitly enabled."
             :args (list '(:name "form" :type string
                           :description "Exactly one Emacs Lisp form"))
             :category "hermes-runtime" :confirm t :include t))))

(defun gptel-hermes-runtime-tools ()
  "Return the runtime tool list for the current buffer."
  (append (list gptel-hermes--runtime-file-read-tool
                gptel-hermes--runtime-file-write-tool
                gptel-hermes--runtime-apply-patch-tool
                gptel-hermes--runtime-terminal-tool
                gptel-hermes--runtime-elisp-call-tool)
          (when gptel-hermes-enable-unsafe-elisp-eval
            (list (gptel-hermes-runtime--unsafe-elisp-eval-tool)))))

(provide 'gptel-hermes-runtime)
;;; gptel-hermes-runtime.el ends here
