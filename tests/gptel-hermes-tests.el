;;; gptel-hermes-tests.el --- isolated checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-hermes)

(defun gptel-hermes-test--fixture ()
  (let* ((home (make-temp-file "gptel-hermes-" t))
         (skill-dir (expand-file-name "skills/code/demo" home))
         (memory-dir (expand-file-name "memories" home)))
    (make-directory skill-dir t)
    (make-directory memory-dir t)
    (with-temp-file (expand-file-name "SKILL.md" skill-dir)
      (insert "---\nname: demo\ndescription: Test skill\n---\n# FULL BODY\n"))
    (with-temp-file (expand-file-name "MEMORY.md" memory-dir) (insert "before\n"))
    (with-temp-file (expand-file-name "USER.md" memory-dir) (insert "user preference\n"))
    home))

(defun gptel-hermes-test--bundled-skills-fixture ()
  (let* ((root (make-temp-file "gptel-hermes-bundled-" t))
         (skill-dir (expand-file-name "category/demo" root)))
    (make-directory skill-dir t)
    (with-temp-file (expand-file-name "SKILL.md" skill-dir)
      (insert "bundled demo skill\n"))
    (make-directory (expand-file-name "references/ignored" root) t)
    (with-temp-file (expand-file-name "SKILL.md"
                                      (expand-file-name "references/ignored" root))
      (insert "must not be copied\n"))
    (with-temp-file (expand-file-name "DESCRIPTION.md" root)
      (insert "must not be copied\n"))
    root))

(defun gptel-hermes-test--org-fixture ()
  (let* ((root (make-temp-file "gptel-hermes-org-" t))
         (directory (expand-file-name "org" root))
         (agenda (expand-file-name "work.org" directory))
         (outside (expand-file-name "outside.org" root)))
    (make-directory directory t)
    (with-temp-file agenda
      (insert "#+TODO: TODO DOIN WAIT TRET REMD | DONE SKIP\n"
              "* TODO [#A] API仕様を確認 :202607:work:\n"
              "DEADLINE: <2026-07-31 Fri>\n"
              "* DOIN リリース準備 :202607:\n"
              "* DONE 完了済み :202607:\n"
              "* REMD 月次リマインド :202606:\n"))
    (with-temp-file outside
      (insert "* TODO 対象外ファイル\n"))
    (list :root root :directory directory :agenda agenda :outside outside)))

(defun gptel-hermes-test--cleanup-org-fixture (fixture)
  (let ((root (plist-get fixture :root)))
    (dolist (buffer (buffer-list))
      (when (and (buffer-file-name buffer)
                 (string-prefix-p (file-name-as-directory (file-truename root))
                                  (file-truename (buffer-file-name buffer))))
        (kill-buffer buffer)))
    (delete-directory root t)))

(defun gptel-hermes-test--skill-path (root skill-id)
  (expand-file-name (concat skill-id "/SKILL.md")
                    (file-name-as-directory root)))

(defun gptel-hermes-test--resource-files-under-root (root)
  "Return all regular resource files below ROOT, excluding SKILL.md files."
  (cl-remove-if
   (lambda (path)
     (string= "SKILL.md" (file-name-nondirectory path)))
   (cl-remove-if-not #'file-regular-p
                     (directory-files-recursively root ".*" t))))

(defun gptel-hermes-test--read-resource (path)
  "Read resource PATH without text decoding assumptions."
  (with-temp-buffer
    (insert-file-contents-literally path)
    (buffer-string)))

(defun gptel-hermes-test--elisp-blocks (content)
  "Return Elisp fenced blocks from CONTENT."
  (let (blocks)
    (dolist (part (split-string content (make-string 3 96)))
      (let ((part (string-trim-left part)))
        (when (string-match "^elisp[ \t]*\n" part)
          (push (substring part (match-end 0)) blocks))))
    (nreverse blocks)))

(defun gptel-hermes-test--write-skill (root skill-id content)
  (let ((path (gptel-hermes-test--skill-path root skill-id)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert content))
    path))

(defconst gptel-hermes-test--legacy-tool-names
  '("read_file" "write_file" "patch" "terminal" "search_files"
    "skill_manage" "delegate_task" "session_search" "web_search"
    "web_extract" "browser_navigate" "browser_snapshot" "browser_console"
    "browser_vision" "browser_click" "browser_type" "browser_press"
    "browser_scroll" "browser_back" "vision_analyze" "computer_use"
    "yb_query_group_info" "yb_query_group_members" "yb_send_dm"
    "td_get_par_info" "td_get_operator_info" "td_get_hints" "td_get_focus"
    "td_get_network" "td_create_operator" "td_execute_python"
    "td_set_operator_pars" "td_get_errors" "td_get_perf"
    "td_get_screenshot" "td_reinit_extension" "td_write_dat"
    "process" "execute_code" "memory" "todo" "cronjob" "clarify"
    "image_gen")
  "Legacy and model-facing external tool names checked in bundled documentation.")

(defconst gptel-hermes-test--directly-migratable-legacy-tools
  '("read_file" "write_file" "patch" "terminal" "search_files")
  "Legacy calls that must be rewritten to standard gptel-hermes tools.")

(defun gptel-hermes-test--legacy-call-uses (content)
  "Return legacy tool uses in CONTENT.

Inspect code blocks, explicit inline-code tool names, and call-like lines.
Both parenthesized calls and shell-style calls such as
`read_file \"wiki/index.md\"' are recognized. Ordinary prose such as
\"Emacs process (\" is not treated as a call. External tool names are included
so required dependencies cannot be hidden from the audit."
  (let ((case-fold-search nil)
        (in-code nil)
        (line-number 0)
        (fence-regexp
         (concat "^[[:space:]]*\\(?:"
                 (make-string 3 96)
                 "\\|~~~\\)"))
        uses)
    (dolist (line (split-string content "\n"))
      (setq line-number (1+ line-number))
      (when (string-match-p fence-regexp line)
        (setq in-code (not in-code)))
      (unless (string-match-p fence-regexp line)
        (dolist (name gptel-hermes-test--legacy-tool-names)
          (let ((token (format "\\_<%s\\_>" (regexp-quote name))))
            (when (or
                   ;; Tool syntax in a fenced code block: both
                   ;; name(...) and name "argument" forms are valid.
                   (and in-code
                        (or (string-match-p
                             (concat token "[ \\t]*(") line)
                            (string-match-p
                             (concat "^[[:space:]]*" token
                                     "[ \\t]+[\\\"']") line)))
                   ;; Backticks identify an inline call or shell-style
                   ;; invocation, but a bare `tool_name' mention is prose.
                   (string-match-p
                    (format "`%s\\(?:[ \\t]*(\\|[ \\t]+[\\\"']\\)"
                            token)
                    line)
                   ;; An explicit imperative tool instruction is a hard
                   ;; dependency even when it is written outside a code block.
                   (string-match-p
                    (format "Use the `%s` tool\\(?:[[:space:]]\\|\\'\\)"
                            (regexp-quote name))
                    line)
                   ;; A call-like line outside a fence.
                   (string-match-p
                    (format
                     "^[[:space:]]*\\(?:[-*+]\\|[0-9]+[.)]\\|→\\|>\\)?[[:space:]]*%s\\(?:[ \\t]*(\\|[ \\t]+[\\\"']\\)"
                     token)
                    line))
              (push (list name line-number line) uses)))))
      (unless (string-match-p fence-regexp line)
        (dolist (name '("pty=true" "background=true"))
          (when (string-match-p (regexp-quote name) line)
            (push (list name line-number line) uses)))))
    (nreverse uses)))

(defun gptel-hermes-test--legacy-required-tool (name)
  "Return the declared dependency required for legacy NAME."
  (if (member name '("pty=true" "background=true"))
      "terminal"
    name))

(ert-deftest gptel-hermes-legacy-scanner-detects-shell-style-calls ()
  (let* ((content (concat
                   "```sh\n"
                   "read_file \"$WIKI/index.md\"\n"
                   "search_files \"topic\" path=\"$WIKI\"\n"
                   "```\n"
                   "Emacs process ( is ordinary prose.\n"
                   "Use `web_search` when the optional integration is available.\n"
                   "Use the `image_gen` tool for the final artifact.\n"
                   "todo(\"plan\")\n"
                   "cronjob(\"create\")\n"
                   "clarify(\"venue\")\n"))
         (uses (gptel-hermes-test--legacy-call-uses content))
         (names (mapcar #'car uses)))
    (should (member "read_file" names))
    (should (member "search_files" names))
    (should-not (member "process" names))
    (should-not (member "web_search" names))
    (should (member "image_gen" names))
    (should (member "todo" names))
    (should (member "cronjob" names))
    (should (member "clarify" names))))

(ert-deftest gptel-hermes-bundled-hermes-calls-match-metadata ()
  (dolist (path (gptel-hermes--skill-files-under-root
                 gptel-hermes--bundled-skills-directory))
    (let* ((content (gptel-hermes--read path))
           (meta (gptel-hermes--frontmatter content))
           (required (plist-get (gptel-hermes--required-tools-data meta)
                                :tools)))
      (dolist (tool (cl-remove-if-not
                     (lambda (name) (string-prefix-p "hermes_" name))
                     gptel-hermes--all-tool-names))
        (when (string-match-p
               (format "\\_<%s[ \\t]*(" (regexp-quote tool)) content)
          (should (member tool required)))))))

(ert-deftest gptel-hermes-bundled-resources-use-current-terminal-schema ()
  (let ((paths (gptel-hermes-test--resource-files-under-root
                gptel-hermes--bundled-skills-directory)))
    (should paths)
    (dolist (path paths)
      (let ((content (gptel-hermes-test--read-resource path)))
        (should-not (string-match-p
                     "\"command\"[[:space:]]*:" content))
        (should-not (string-match-p
                     "\"workdir\"[[:space:]]*:" content))
        ;; This reference intentionally documents upstream Hermes tool names;
        ;; all executable gptel-hermes resources must use current names.
        (unless (string-suffix-p
                "/autonomous-ai-agents/hermes-agent/references/native-mcp.md"
                path)
          (should-not (string-match-p
                       "\\_<\\(?:read_file\\|write_file\\|search_files\\|terminal\\)[[:space:]]*("
                       content)))))))

(ert-deftest gptel-hermes-touchdesigner-shaders-use-direct-dat-write ()
  (dolist (relative '("creative/touchdesigner-mcp/SKILL.md"
                      "creative/touchdesigner-mcp/references/network-patterns.md"
                      "creative/touchdesigner-mcp/references/pitfalls.md"))
    (let ((content (gptel-hermes--read
                    (expand-file-name
                     relative gptel-hermes--bundled-skills-directory))))
      (should (string-match-p "td_write_dat" content))
      (should-not (string-match-p
                   "/tmp/\\(?:my_\\)?shader\\.glsl\\|/tmp/file\\.glsl"
                   content)))))

(ert-deftest gptel-hermes-home-references-have-safe-terminal-policy ()
  (let ((home-regexp (regexp-opt '("~/" "$HOME" "${HOME" "HERMES_HOME"))))
    (dolist (path (gptel-hermes--skill-files-under-root
                   gptel-hermes--bundled-skills-directory))
      (let* ((content (gptel-hermes--read path))
             (meta (gptel-hermes--frontmatter content))
             (required (plist-get (gptel-hermes--required-tools-data meta)
                                  :tools)))
        (when (string-match-p home-regexp content)
          (should-not (and (member "hermes_terminal" required)
                           (not (member "hermes_terminal_authenticated"
                                        required))))
          (if (member "hermes_terminal_authenticated" required)
              (should (string-match-p
                       "hermes_terminal_authenticated\\|real HOME\\|persistent"
                       content))
            (when (member "hermes_terminal" required)
              (should (string-match-p
                       "temporary HOME\\|workspace.*path\\|manual.*outside\\|does not need to persist"
                       content)))))))))

(ert-deftest gptel-hermes-agent-skills-set-long-running-terminal-timeout ()
  (dolist (skill '("autonomous-ai-agents/claude-code"
                   "autonomous-ai-agents/codex"
                   "autonomous-ai-agents/opencode"
                   "autonomous-ai-agents/hermes-agent"))
    (let ((content (gptel-hermes--read
                    (gptel-hermes-test--skill-path
                     gptel-hermes--bundled-skills-directory skill))))
      (should (string-match-p "timeout=300" content)))))

(ert-deftest gptel-hermes-agent-skills-sanitize-project-verification ()
  (dolist (skill '("autonomous-ai-agents/claude-code"
                   "autonomous-ai-agents/codex"
                   "autonomous-ai-agents/opencode"))
    (let* ((content (gptel-hermes--read
                     (gptel-hermes-test--skill-path
                      gptel-hermes--bundled-skills-directory skill)))
           (required (plist-get
                      (gptel-hermes--required-tools-data
                       (gptel-hermes--frontmatter content))
                      :tools)))
      (should (member "hermes_terminal" required))
      (should (member "hermes_terminal_authenticated" required))
      (should (string-match-p
               "verification command in a separate `hermes_terminal` call"
               content))
      (should (string-match-p
               "project tests,[[:space:]]+builds, hooks" content))
      (dolist (line (split-string content "\n"))
        (when (string-match-p "arguments=" line)
          (should-not (string-match-p
                       "\\_<run\\_>.*\\_<tests?\\_>" line))))))
  (let ((claude (gptel-hermes--read
                 (gptel-hermes-test--skill-path
                  gptel-hermes--bundled-skills-directory
                  "autonomous-ai-agents/claude-code"))))
    (should (string-match-p
             "--tools\", \"Read,Edit,Write\"" claude))))

(ert-deftest gptel-hermes-claude-review-includes-all-worktree-diffs ()
  (let ((content (gptel-hermes--read
                  (expand-file-name "autonomous-ai-agents/claude-code/SKILL.md"
                                    gptel-hermes--bundled-skills-directory))))
    (should (string-match-p
             "git diff HEAD --no-ext-diff --unified=80" content))
    (should (string-match-p
             "git ls-files -z --others --exclude-standard" content))
    (should (string-match-p "git diff --no-index" content))
    (should (string-match-p
             "git diff --no-ext-diff --unified=80 >>" content))))

(ert-deftest gptel-hermes-claude-review-uses-safe-single-line-terminal-argv ()
  (let* ((content (gptel-hermes--read
                   (expand-file-name "autonomous-ai-agents/claude-code/SKILL.md"
                                     gptel-hermes--bundled-skills-directory)))
         (line (cl-find-if (lambda (value)
                             (string-match-p "arguments=\\[\\\"-c\\\"" value))
                           (split-string content "\n"))))
    (should line)
    (should-not (string-match-p "\\\\n" line))
    (should (string-match-p "--safe-mode" line))))

(ert-deftest gptel-hermes-review-comments-have-runtime-safe-examples ()
  (let ((claude (gptel-hermes--read
                 (expand-file-name "autonomous-ai-agents/claude-code/SKILL.md"
                                   gptel-hermes--bundled-skills-directory)))
        (github (gptel-hermes--read
                 (expand-file-name "github/github-code-review/SKILL.md"
                                   gptel-hermes--bundled-skills-directory)))
        (cheatsheet (gptel-hermes--read
                     (expand-file-name
                      "github/github-repo-management/references/github-api-cheatsheet.md"
                      gptel-hermes--bundled-skills-directory)))
        (nano (gptel-hermes--read
               (expand-file-name "productivity/nano-pdf/SKILL.md"
                                 gptel-hermes--bundled-skills-directory)))
        (himalaya (gptel-hermes--read
                   (expand-file-name "email/himalaya/SKILL.md"
                                     gptel-hermes--bundled-skills-directory))))
    (should (string-match-p "--safe-mode" claude))
    (should (string-match-p "sanitized.*hermes_terminal.*searches and tests"
                            github))
    (should (string-match-p (regexp-quote "${GH_OWNER:?GitHub owner unavailable")
                            github))
    (should (string-match-p (regexp-quote "GH_OWNER=${BASH_REMATCH[1]}")
                            github))
    (should (string-match-p
             "bash -c 'set -eu; \\. .*GITHUB_TOKEN.*GH_OWNER"
             cheatsheet))
    (should (string-match-p
             "requires_tools:.*hermes_terminal_authenticated" nano))
    (should (string-match-p "hermes_terminal_authenticated(program=\"nano-pdf\""
                            nano))
    (should (string-match-p
             (regexp-quote
              "hermes_terminal_authenticated(program=\"sh\", arguments=[\"-c\"")
             himalaya))
    (should-not (string-match-p "program:[[:space:]]*\"sh\"" himalaya))))

(ert-deftest gptel-hermes-stateless-bounded-skill-workflows ()
  (let ((comfy (gptel-hermes--read
                (expand-file-name "creative/comfyui/SKILL.md"
                                  gptel-hermes--bundled-skills-directory)))
        (comfy-workflows
         (gptel-hermes--read
          (expand-file-name "creative/comfyui/workflows/README.md"
                            gptel-hermes--bundled-skills-directory)))
        (p5js (gptel-hermes--read
               (expand-file-name "creative/p5js/SKILL.md"
                                 gptel-hermes--bundled-skills-directory)))
        (github (gptel-hermes--read
                 (expand-file-name "github/github-code-review/SKILL.md"
                                   gptel-hermes--bundled-skills-directory)))
        (cheatsheet
         (gptel-hermes--read
          (expand-file-name
           "github/github-repo-management/references/github-api-cheatsheet.md"
           gptel-hermes--bundled-skills-directory)))
        (nano (gptel-hermes--read
               (expand-file-name "productivity/nano-pdf/SKILL.md"
                                 gptel-hermes--bundled-skills-directory)))
        (nano-calls 0))
    (should (string-match-p "hard-capped at 300 seconds" comfy))
    (should (string-match-p "nohup" comfy))
    (should (string-match-p (regexp-quote "comfyui-job.pid") comfy))
    (should (string-match-p "detached or externally" comfy))
    (should (string-match-p "foreground terminal call after 300s"
                            comfy-workflows))
    (should (string-match-p "nohup" p5js))
    (should (string-match-p (regexp-quote "p5-server.pid") p5js))
    (should (string-match-p (regexp-quote "rm -f p5-server.pid") p5js))
    (should-not (string-match-p (regexp-quote "$OWNER") github))
    (should-not (string-match-p (regexp-quote "$REPO") github))
    (should (string-match-p (regexp-quote "$GH_OWNER/$GH_REPO") github))
    (should (string-match-p "gh auth token" cheatsheet))
    (should (string-match-p
             (regexp-quote "GITHUB_TOKEN:?GitHub token unavailable")
             cheatsheet))
    (dolist (line (split-string nano "\n"))
      (when (string-match-p
             "hermes_terminal_authenticated(program=\"nano-pdf\"" line)
        (setq nano-calls (1+ nano-calls))
        (should (string-match-p "timeout=300" line))))
    (should (= nano-calls 4))))

(ert-deftest gptel-hermes-github-curl-fallback-handles-missing-origin ()
  (skip-unless (executable-find "bash"))
  (let* ((root (make-temp-file "gptel-hermes-github-env-" t))
         (bin (expand-file-name "bin" root))
         (gh (expand-file-name "gh" bin))
         (git (expand-file-name "git" bin))
         (curl (expand-file-name "curl" bin))
         (helper
          (expand-file-name "github/github-auth/scripts/gh-env.sh"
                            gptel-hermes--bundled-skills-directory))
         (review
          (gptel-hermes--read
           (expand-file-name "github/github-code-review/SKILL.md"
                             gptel-hermes--bundled-skills-directory)))
         (command-line
          (cl-find-if
           (lambda (line)
             (string-match-p
              "^bash -c .*https://github.com/OWNER/REPO/pull/123" line))
           (split-string review "\n"))))
    (unwind-protect
        (progn
          (make-directory bin)
          (with-temp-file gh
            (insert "#!/bin/sh\n"
                    "case \"$1:$2\" in\n"
                    "  auth:status) exit 0 ;;\n"
                    "  auth:token) printf 'keychain-token\\n' ;;\n"
                    "  api:user) printf 'octocat\\n' ;;\n"
                    "  *) exit 1 ;;\n"
                    "esac\n"))
          (with-temp-file git
            (insert "#!/bin/sh\n"
                    "[ \"${GH_TEST_NO_ORIGIN:-}\" = 1 ] && exit 2\n"
                    "if [ \"$1:$2:$3\" = remote:get-url:origin ]; then\n"
                    "  printf 'git@github.com:owner/repo.git\\n'\n"
                    "else\n"
                    "  exit 1\n"
                    "fi\n"))
          (with-temp-file curl
            (insert "#!/bin/sh\n"
                    "for argument do last=$argument; done\n"
                    "printf '%s\\n' \"$last\"\n"))
          (set-file-modes gh #o755)
          (set-file-modes git #o755)
          (set-file-modes curl #o755)
          (should command-line)
          (let ((process-environment (copy-sequence process-environment))
                (default-directory (file-name-as-directory root)))
            (setenv "PATH"
                    (concat bin
                            (if (characterp path-separator)
                                (char-to-string path-separator)
                              path-separator)
                            (or (getenv "PATH") "")))
            (setenv "HOME" root)
            (setenv "HERMES_HOME" nil)
            (setenv "GITHUB_TOKEN" nil)
            (with-temp-buffer
              (should
               (= 0
                  (call-process
                   "bash" nil t nil "-c"
                   (concat
                    "set -eu; . \"$1\" >/dev/null; "
                    "printf '%s|%s|%s|%s' \"$GITHUB_TOKEN\" "
                    "\"$GH_OWNER\" \"$GH_REPO\" \"$GH_AUTH_METHOD\"")
                   "bash" helper)))
              (should (equal "keychain-token|owner|repo|gh"
                             (buffer-string))))
            (setenv "GH_TEST_NO_ORIGIN" "1")
            (with-temp-buffer
              (should
               (= 0
                  (call-process
                   "bash" nil t nil "-c"
                   (concat
                    "set -eu; . \"$1\" >/dev/null; "
                    "printf '%s|%s|%s|%s' \"$GITHUB_TOKEN\" "
                    "\"$GH_OWNER\" \"$GH_REPO\" \"$GH_AUTH_METHOD\"")
                   "bash" helper)))
              (should (equal "keychain-token|||gh" (buffer-string))))
            (with-temp-buffer
              (should
               (= 0
                  (call-process
                   "bash" nil t nil "-c"
                   (replace-regexp-in-string
                    "/absolute/path/returned-by-hermes_skill_resource_path"
                    helper command-line t t))))
              (should (string-match-p
                       (regexp-quote
                        "https://api.github.com/repos/OWNER/REPO/pulls/123")
                       (buffer-string)))
              (should (string-match-p
                       (regexp-quote
                        "https://api.github.com/repos/OWNER/REPO/pulls/123/files")
                       (buffer-string))))))
      (delete-directory root t))))

(defconst gptel-hermes-test--claude-review-producer
  (concat
   "set -eu\n"
   "input=\"$1\"\n"
   "files=\"$(mktemp /tmp/gptel-hermes-test-files.XXXXXX)\"\n"
   "trap 'rm -f \"$files\"' EXIT HUP INT TERM\n"
   "if git rev-parse --verify HEAD >/dev/null 2>&1; then\n"
   "  git diff HEAD --no-ext-diff --unified=80 >\"$input\"\n"
   "else\n"
   "  git diff --cached --no-ext-diff --unified=80 >\"$input\"\n"
   "  git diff --no-ext-diff --unified=80 >>\"$input\"\n"
   "fi\n"
   "git ls-files -z --others --exclude-standard >\"$files\"\n"
   "xargs -0 -n1 sh -c 'if [ \"$#\" -eq 0 ]; then exit 0; fi; status=0; git diff --no-index --no-ext-diff --unified=80 -- /dev/null \"$1\" >>\"$0\" || status=$?; [ \"$status\" -eq 1 ] || exit \"$status\"' \"$input\" <\"$files\"\n")
  "Producer used by the Claude review regression test.")

(defun gptel-hermes-test--run-claude-review-producer (directory output)
  "Run the review producer in DIRECTORY, writing the diff to OUTPUT."
  (let ((default-directory (file-name-as-directory directory)))
    (call-process "sh" nil nil nil "-c"
                  gptel-hermes-test--claude-review-producer
                  "sh" output)))

(defun gptel-hermes-test--git (&rest arguments)
  "Run git with ARGUMENTS and return its exit status."
  (apply #'call-process "git" nil nil nil arguments))

(ert-deftest gptel-hermes-claude-review-producer-is-nul-safe-and-fails-loudly ()
  (skip-unless (and (executable-find "git")
                    (executable-find "sh")
                    (executable-find "mktemp")
                    (executable-find "xargs")))
  (let* ((root (make-temp-file "gptel-hermes-review-repo-" t))
         (output-dir (make-temp-file "gptel-hermes-review-output-" t))
         (output (expand-file-name "review.diff" output-dir))
         (newline-name (concat "line" "\n" "break")))
    (unwind-protect
        (progn
          (let ((default-directory (file-name-as-directory root)))
            (should (= 0 (gptel-hermes-test--git "init" "-q")))
            (should (= 0 (gptel-hermes-test--git "config" "user.email"
                                                  "test@example.invalid")))
            (should (= 0 (gptel-hermes-test--git "config" "user.name"
                                                  "Test")))
            (with-temp-file (expand-file-name "initial.txt" root)
              (insert "initial\n"))
            (should (= 0 (gptel-hermes-test--git "add" "--" "initial.txt")))
            (with-temp-file (expand-file-name "initial.txt" root)
              (insert "initial-post-index\n"))
            (should (= 0 (gptel-hermes-test--run-claude-review-producer
                          root output))))
          (should (string-match-p "initial"
                                  (gptel-hermes--read output)))
          (should (string-match-p "initial-post-index"
                                  (gptel-hermes--read output)))
          (let ((default-directory (file-name-as-directory root)))
            (should (= 0 (gptel-hermes-test--git "commit" "-qm" "initial")))
            (with-temp-file (expand-file-name "initial.txt" root)
              (insert "tracked-modified\n"))
            (with-temp-file (expand-file-name "staged.txt" root)
              (insert "staged\n"))
            (should (= 0 (gptel-hermes-test--git "add" "--" "staged.txt")))
            (with-temp-file (expand-file-name "--stat" root)
              (insert "option-named\n"))
            (with-temp-file (expand-file-name newline-name root)
              (insert "newline-named\n"))
            (should (= 0 (gptel-hermes-test--run-claude-review-producer
                          root output))))
          (let ((content (gptel-hermes--read output)))
            (should (string-match-p "tracked-modified" content))
            (should (string-match-p "staged" content))
            (should (string-match-p "option-named" content))
            (should (string-match-p "newline-named" content)))
          (let ((empty-repo (make-temp-file "gptel-hermes-review-empty-" t)))
            (unwind-protect
                (should-not (= 0
                               (gptel-hermes-test--run-claude-review-producer
                                empty-repo output)))
              (delete-directory empty-repo t))))
      (delete-directory root t)
      (delete-directory output-dir t))))

(ert-deftest gptel-hermes-research-paper-declares-external-workflow-tools ()
  (let* ((path (expand-file-name
                "research/research-paper-writing/SKILL.md"
                gptel-hermes--bundled-skills-directory))
         (meta (gptel-hermes--frontmatter (gptel-hermes--read path)))
         (required (plist-get (gptel-hermes--required-tools-data meta) :tools)))
    (dolist (tool '("todo" "cronjob" "clarify"))
      (should (member tool required)))))

(ert-deftest gptel-hermes-baoyu-infographic-declares-only-hard-capabilities ()
  (let* ((content
          (gptel-hermes--read
           (gptel-hermes-test--skill-path
            gptel-hermes--bundled-skills-directory
            "creative/baoyu-infographic")))
         (meta (gptel-hermes--frontmatter content))
         (required (plist-get (gptel-hermes--required-tools-data meta)
                              :tools)))
    (should (member "image_gen" required))
    (should-not (member "clarify" required))
    (should (string-match-p "ask the user in the conversation" content))
    (should-not (string-match-p "clarify.*tool" content))))

(ert-deftest gptel-hermes-api-key-skills-use-authenticated-no-echo-setup ()
  (dolist (skill '("creative/comfyui"
                   "mlops/evaluation/lm-evaluation-harness"
                   "mlops/evaluation/weights-and-biases"
                   "productivity/notion"))
    (let* ((path (gptel-hermes-test--skill-path
                  gptel-hermes--bundled-skills-directory skill))
           (content (gptel-hermes--read path))
           (meta (gptel-hermes--frontmatter content))
           (required (plist-get (gptel-hermes--required-tools-data meta)
                                :tools)))
      (should (member "hermes_terminal_authenticated" required))
      (should-not (string-match-p "export[[:space:]]+.*API_KEY" content))
      (should (string-match-p "read-passwd" content))))
  (let ((content
         (gptel-hermes--read
          (expand-file-name
           "mlops/evaluation/lm-evaluation-harness/references/api-evaluation.md"
           gptel-hermes--bundled-skills-directory))))
    (should (string-match-p "setenv.*OPENAI_API_KEY" content))
    (should (string-match-p "setenv.*ANTHROPIC_API_KEY" content))
    (should-not (string-match-p "echo[[:space:]]+\\\$OPENAI_API_KEY" content))
    (should-not (string-match-p "echo[[:space:]]+\\\$ANTHROPIC_API_KEY"
                                content))))

(ert-deftest gptel-hermes-api-key-elisp-blocks-return-nil ()
  (dolist (path '("creative/comfyui/SKILL.md"
                  "mlops/evaluation/lm-evaluation-harness/SKILL.md"
                  "mlops/evaluation/lm-evaluation-harness/references/api-evaluation.md"
                  "mlops/evaluation/weights-and-biases/SKILL.md"
                  "productivity/notion/SKILL.md"))
    (let ((content (gptel-hermes--read
                    (expand-file-name path
                                      gptel-hermes--bundled-skills-directory))))
      (dolist (block (gptel-hermes-test--elisp-blocks content))
        (when (string-match-p "read-passwd" block)
          (let ((process-environment (copy-sequence process-environment)))
            (cl-letf (((symbol-function 'read-passwd)
                       (lambda (&rest _) "test-secret")))
              (should-not (eval (read block))))))))))

(ert-deftest gptel-hermes-review-fix-skill-metadata-and-paths ()
  (dolist (spec '(("productivity/maps" "hermes_terminal"
                   "hermes_skill_resource_path")
                  ("data-science/jupyter-live-kernel"
                   "hermes_terminal_authenticated")
                  ("productivity/google-workspace"
                   "hermes_skill_resource_path")
                  ("mlops/inference/vllm"
                   "hermes_terminal_authenticated")))
    (let* ((path (gptel-hermes-test--skill-path
                  gptel-hermes--bundled-skills-directory (car spec)))
           (content (gptel-hermes--read path))
           (tools (plist-get
                   (gptel-hermes--required-tools-data
                    (gptel-hermes--frontmatter content))
                   :tools)))
      (should (member (cadr spec) tools))
      (when (caddr spec)
        (should (member (caddr spec) tools)))))
  (let* ((maps (gptel-hermes--read
                (gptel-hermes-test--skill-path
                 gptel-hermes--bundled-skills-directory "productivity/maps")))
         (maps-tools (plist-get
                      (gptel-hermes--required-tools-data
                       (gptel-hermes--frontmatter maps))
                      :tools))
        (jupyter (gptel-hermes--read
                  (gptel-hermes-test--skill-path
                   gptel-hermes--bundled-skills-directory
                   "data-science/jupyter-live-kernel")))
        (google (gptel-hermes--read
                 (gptel-hermes-test--skill-path
                  gptel-hermes--bundled-skills-directory
                  "productivity/google-workspace")))
        (touch (gptel-hermes--read
                (gptel-hermes-test--skill-path
                 gptel-hermes--bundled-skills-directory
                 "creative/touchdesigner-mcp")))
        (vllm (gptel-hermes--read
               (gptel-hermes-test--skill-path
                gptel-hermes--bundled-skills-directory "mlops/inference/vllm")))
        (editing (gptel-hermes--read
                  (expand-file-name
                   "productivity/powerpoint/editing.md"
                   gptel-hermes--bundled-skills-directory))))
    (should-not (member "web_search" maps-tools))
    (should (string-match-p "web_search.*available" maps))
    (should (string-match-p
             "current opening status could not be verified"
             maps))
    (should (string-match-p "do not infer" maps))
    (should-not (string-match-p "\\$MAPS\\|^MAPS=" maps))
    (should (string-match-p
             "hermes_terminal([[:space:]]*program=\\\"python3\\\""
             maps))
    (should (string-match-p
             "python3[[:space:]]+\\\"/absolute/path/returned-by-hermes_skill_resource_path\\\""
             maps))
    (should-not (string-match-p
                 "requires_tools:.*execute_code" jupyter))
    (should (string-match-p "hermes_skill_resource_path" google))
    (should-not (string-match-p "\\$GSETUP\\|\\$GAPI" google))
    (should (string-match-p
             "python3[[:space:]]+\\\"/absolute/path/returned-by-hermes_skill_resource_path\\\""
             google))
    (should-not (string-match-p
                 "HERMES_HOME.*google-workspace/scripts" google))
    (dolist (tool '("td_get_par_info" "td_create_operator"
                    "td_execute_python" "td_get_operator_info"
                    "td_get_hints" "td_get_focus" "td_get_network"
                    "td_set_operator_pars" "td_get_errors" "td_get_perf"
                    "td_get_screenshot"))
      (should (string-match-p
               (concat "requires_tools:.*" (regexp-quote tool))
               touch)))
    (should-not (string-match-p
                 "requires_tools:.*hermes_terminal_authenticated" touch))
    (should (string-match-p "external gptel MCP bridge" touch))
    (should-not (string-match-p "scripts/setup\\.sh" touch))
    (should (string-match-p "one-shot terminal" vllm))
    (should (string-match-p "external process manager" vllm))
    (should (string-match-p "test ! -e unpacked" editing))))

(ert-deftest gptel-hermes-dispatching-parallel-agents-is-external ()
  (let* ((path (gptel-hermes-test--skill-path
                gptel-hermes--bundled-skills-directory
                "superpowers/dispatching-parallel-agents"))
         (content (gptel-hermes--read path))
         (required (plist-get
                    (gptel-hermes--required-tools-data
                     (gptel-hermes--frontmatter content))
                    :tools)))
    (should (equal '("delegate_task") required))
    (should (string-match-p "delegate_task(goal=" content))
    (should (string-match-p
             "not[[:space:]]+provided by gptel-hermes"
             content))))

(defun gptel-hermes-test--org-entry (fixture heading)
  (cl-find-if (lambda (entry)
                (string= heading (plist-get entry :heading)))
              (gptel-hermes--org-task-entries
               (list (file-truename (plist-get fixture :agenda))))))

(ert-deftest gptel-hermes-org-agenda-resolves-files-directories-and-duplicates ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let* ((agenda (file-truename (plist-get fixture :agenda)))
               (directory (file-truename (plist-get fixture :directory)))
               (org-agenda-files (list directory agenda directory
                                        (expand-file-name "missing.org"
                                                          directory)))
               (gptel-hermes-org-directory-fallback nil)
               (files (gptel-hermes--org-agenda-files)))
          (should (= 1 (length files)))
          (should (equal agenda (car files))))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-agenda-empty-is-safe-and-explicit-fallback-works ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let ((org-agenda-files nil)
              (gptel-hermes-org-directory-fallback nil))
          (should-not (gptel-hermes--org-agenda-files))
          (should (string-match-p "未設定"
                                  (gptel-hermes-org-agenda "open"))))
      (gptel-hermes-test--cleanup-org-fixture fixture)))
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let ((org-agenda-files nil)
              (org-directory (plist-get fixture :directory))
              (gptel-hermes-org-directory-fallback t))
          (should (member (file-truename (plist-get fixture :agenda))
                          (gptel-hermes--org-agenda-files))))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-agenda-views-use-custom-keywords-and-planning-data ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let ((org-agenda-files (list (plist-get fixture :agenda))))
          (let ((open (gptel-hermes-org-agenda "open" nil 100))
                (all (gptel-hermes-org-agenda "all" nil 100))
                (tagged (gptel-hermes-org-agenda "tag" "202607" 100)))
            (should (string-match-p "API仕様を確認" open))
            (should (string-match-p "DOIN" open))
            (should (string-match-p "REMD" open))
            (should-not (string-match-p "完了済み" open))
            (should (string-match-p "完了済み" all))
            (should (string-match-p "202607" tagged))
            (should-not (string-match-p "月次リマインド" tagged))
            (should (string-match-p "優先度: A" tagged))
            (should (string-match-p "期限: <2026-07-31 Fri>" tagged))))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-task-requires-fresh-agenda-target-and-scope ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let* ((org-agenda-files (list (plist-get fixture :agenda)))
               (entry (gptel-hermes-test--org-entry fixture "API仕様を確認"))
               (file (plist-get entry :file))
               (line (plist-get entry :line)))
          (should-error
           (gptel-hermes-org-task "todo" file (1+ line)
                                  "API仕様を確認" "DOIN"))
          (should-error
           (gptel-hermes-org-task "todo" file line
                                  "別の見出し" "DOIN"))
          (should-error
           (gptel-hermes-org-task "todo" (plist-get fixture :outside) 1
                                  "対象外ファイル" "DOIN"))
          (should-error
           (gptel-hermes-org-task "todo" file line
                                  "API仕様を確認" "NOT-A-STATE")))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-task-changes-one-state-with-org-todo ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let* ((org-agenda-files (list (plist-get fixture :agenda)))
               (org-log-done nil)
               (entry (gptel-hermes-test--org-entry fixture "API仕様を確認"))
               (result (gptel-hermes-org-task
                        "todo" (plist-get entry :file) (plist-get entry :line)
                        (plist-get entry :heading) "DONE")))
          (should (string-match-p "Org task updated" result))
          (should (string-match-p "\\* DONE \\[#A\\] API仕様を確認"
                                  (gptel-hermes--read
                                   (plist-get fixture :agenda)))))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-capture-uses-template-and-reports-available-keys ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let ((org-agenda-files (list (plist-get fixture :agenda)))
              (org-directory (plist-get fixture :directory))
              (org-capture-templates
               '(("t" "Task" entry (file+headline "work.org" "Captured")
                  "* TODO %?"))))
          (let ((missing (gptel-hermes-org-task
                          "capture" nil nil nil nil "ignored" "x")))
            (should (string-match-p "t" missing))
            (should-not (string-match-p "ignored"
                                        (gptel-hermes--read
                                         (plist-get fixture :agenda)))))
          (let ((org-capture-templates
                 '(("x" "Outside" entry (file "../outside.org")
                    "* TODO %?"))))
            (should-error
             (gptel-hermes-org-task
              "capture" nil nil nil nil "must not escape agenda" "x")))
          (let ((result (gptel-hermes-org-task
                         "capture" nil nil nil nil "新しいタスク" "t")))
            (should (string-match-p "Org capture complete" result))
            (should (string-match-p "新しいタスク"
                                    (gptel-hermes--read
                                     (plist-get fixture :agenda))))))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-capture-requires-configured-templates ()
  (let ((fixture (gptel-hermes-test--org-fixture)))
    (unwind-protect
        (let ((org-agenda-files (list (plist-get fixture :agenda)))
              (org-capture-templates nil))
          (should-error
           (gptel-hermes-org-task "capture" nil nil nil nil "text" "t")))
      (gptel-hermes-test--cleanup-org-fixture fixture))))

(ert-deftest gptel-hermes-org-tools-have-read-and-confirmation-policies ()
  (should-not (gptel-tool-confirm gptel-hermes--org-agenda-tool))
  (should (eq t (gptel-tool-confirm gptel-hermes--org-task-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--org-agenda-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--org-task-tool)))
  (should (equal "hermes_org_agenda"
                 (gptel-tool-name gptel-hermes--org-agenda-tool)))
  (should (equal "hermes_org_task"
                 (gptel-tool-name gptel-hermes--org-task-tool))))

(ert-deftest gptel-hermes-default-home-is-isolated-from-hermes-agent ()
  (let ((gptel-hermes-home nil)
        (process-environment (copy-sequence process-environment)))
    (setenv "HERMES_HOME" "/tmp/existing-hermes-home")
    (should (equal (file-name-as-directory
                    (expand-file-name "~/.gptel-hermes"))
                   (gptel-hermes--home)))))

(ert-deftest gptel-hermes-prompt-is-index-plus-memory-not-skill-body ()
  (let ((home (gptel-hermes-test--fixture)))
    (unwind-protect
        (let ((gptel-hermes-home home)
              (gptel-hermes-skills-directory (expand-file-name "skills" home)))
          (let ((prompt (gptel-hermes--prompt)))
            (should (string-match-p "demo | Test skill" prompt))
            (should (string-match-p "before" prompt))
            (should (string-match-p "user preference" prompt))
            (should-not (string-match-p "FULL BODY" prompt))))
      (delete-directory home t))))

(ert-deftest gptel-hermes-selected-skill-is-model-facing-result ()
  (let ((home (gptel-hermes-test--fixture)))
    (unwind-protect
        (let* ((gptel-hermes-home home)
               (gptel-hermes-skills-directory (expand-file-name "skills" home))
               (result (funcall (gptel-tool-function gptel-hermes--skill-tool) "demo")))
          (should (string-match-p "Source: skills/code/demo/SKILL.md" result))
          (should (string-match-p "# FULL BODY" result))
          (should (eq (gptel-tool-include gptel-hermes--skill-tool) t)))
      (delete-directory home t))))

(ert-deftest gptel-hermes-skill-resource-path-resolves-bundled-resource ()
  (let* ((root (make-temp-file "gptel-hermes-resource-" t))
         (user (make-temp-file "gptel-hermes-resource-user-" t))
         (resource (expand-file-name "demo/scripts/check.py" root))
         (root-resource (expand-file-name "demo/root.txt" root)))
    (unwind-protect
        (progn
          (gptel-hermes-test--write-skill
           root "demo"
           "---\nname: demo\ndescription: Demo\nrequires_tools: [hermes_terminal, hermes_terminal_authenticated]\n---\n# Body\n")
          (make-directory (file-name-directory resource) t)
          (with-temp-file resource (insert "print('ok')\n"))
          (with-temp-file root-resource (insert "root\n"))
          (let ((gptel-hermes--bundled-skills-directory root)
                (gptel-hermes-skills-directory user))
            (let ((result (gptel-hermes-skill-resource-path
                           "demo" "scripts/check.py")))
              (should (string-match-p
                       (regexp-quote (concat "Effective path: " resource))
                       result))
              (should (string-match-p
                       "Terminal tool: hermes_terminal by default"
                       result))
              (should (string-match-p
                       "hermes_terminal_authenticated only when the Skill"
                       result))
              (should (string-match-p
                       (regexp-quote
                        (concat "Skill directory: "
                                (file-name-as-directory
                                 (expand-file-name "demo" root))))
                       result))
              (should (string-match-p
                       "do not use a workspace-relative scripts/ path"
                       result)))
            (should (string-match-p
                     (regexp-quote
                      (concat "Skill directory: "
                              (file-name-as-directory
                               (expand-file-name "demo" root))))
                     (gptel-hermes-skill-resource-path
                      "demo" "root.txt")))))
      (delete-directory root t)
      (delete-directory user t))))

(ert-deftest gptel-hermes-bundled-script-docs-use-resolvable-paths ()
  (let ((comfy (gptel-hermes--read
                (expand-file-name "creative/comfyui/SKILL.md"
                                  gptel-hermes--bundled-skills-directory)))
        (maps (gptel-hermes--read
               (expand-file-name "productivity/maps/SKILL.md"
                                 gptel-hermes--bundled-skills-directory)))
        (powerpoint (gptel-hermes--read
                     (expand-file-name "productivity/powerpoint/SKILL.md"
                                       gptel-hermes--bundled-skills-directory)))
        (editing (gptel-hermes--read
                  (expand-file-name "productivity/powerpoint/editing.md"
                                    gptel-hermes--bundled-skills-directory)))
        (workflows (gptel-hermes--read
                    (expand-file-name "creative/comfyui/workflows/README.md"
                                      gptel-hermes--bundled-skills-directory))))
    (dolist (content (list comfy maps powerpoint editing workflows))
      (should-not (string-match-p
                   "^[[:space:]]*\\(?:python3?\\|bash\\)[[:space:]]+scripts/"
                   content)))
    (should-not (string-match-p "--workflow[[:space:]]+workflows/"
                                (concat comfy "\n" workflows)))
    (should-not (string-match-p "scripts/scripts/\\|workflows/workflows/"
                                (concat comfy "\n" powerpoint "\n"
                                        editing "\n" workflows)))
    (should (string-match-p "Skill[[:space:]]+directory" comfy))
    (should (string-match-p "Skill[[:space:]]+directory" workflows))
    (should (string-match-p "hermes_skill_resource_path" maps))
    (should-not (string-match-p "~/.hermes/skills/maps" maps))
    (dolist (resource '("creative/comfyui/scripts/hardware_check.py"
                        "creative/comfyui/scripts/run_workflow.py"
                        "productivity/powerpoint/scripts/add_slide.py"
                        "productivity/powerpoint/scripts/clean.py"))
      (should (file-regular-p
               (expand-file-name resource gptel-hermes--bundled-skills-directory))))
    (dolist (missing '("scripts/thumbnail.py" "scripts/office/unpack.py"
                       "scripts/office/soffice.py" "scripts/office/pack.py"))
      (should-not (string-match-p (regexp-quote missing)
                                  (concat powerpoint "\n" editing))))))

(ert-deftest gptel-hermes-bundled-resource-workflows-declare-resolution ()
  (dolist (spec '("media/youtube-content"
                  "productivity/ocr-and-documents"
                  "productivity/google-workspace"
                  "productivity/maps"
                  "productivity/powerpoint"
                  "productivity/web-endpoint-monitoring"
                  "research/arxiv"
                  "research/research-paper-writing"
                  "creative/excalidraw"
                  "creative/manim-video"
                  "creative/p5js"
                  "github/github-code-review"
                  "github/github-repo-management"))
    (let* ((content (gptel-hermes--read
                     (gptel-hermes-test--skill-path
                      gptel-hermes--bundled-skills-directory spec)))
           (tools (plist-get
                   (gptel-hermes--required-tools-data
                    (gptel-hermes--frontmatter content))
                   :tools)))
      (should (member "hermes_skill_resource_path" tools))
      (should (string-match-p "hermes_skill_resource_path" content))))
  (dolist (resource '("creative/excalidraw/scripts/upload.py"
                      "creative/manim-video/scripts/setup.sh"
                      "creative/p5js/scripts/serve.sh"
                      "media/youtube-content/scripts/fetch_transcript.py"
                      "productivity/google-workspace/scripts/setup.py"
                      "productivity/maps/scripts/maps_client.py"
                      "productivity/ocr-and-documents/scripts/extract_pymupdf.py"
                      "productivity/powerpoint/scripts/add_slide.py"
                      "productivity/web-endpoint-monitoring/scripts/http_image_watch.py"
                      "research/arxiv/scripts/search_arxiv.py"
                      "research/research-paper-writing/templates/neurips2025/main.tex"
                      "github/github-auth/scripts/gh-env.sh"))
    (should (file-regular-p
             (expand-file-name resource gptel-hermes--bundled-skills-directory)))))

(ert-deftest gptel-hermes-bundled-execution-skills-declare-terminal-tools ()
  (dolist (spec '(("creative/comfyui" "hermes_terminal_authenticated")
                  ("productivity/powerpoint" "hermes_terminal")))
    (let* ((path (gptel-hermes-test--skill-path
                  gptel-hermes--bundled-skills-directory (car spec)))
           (meta (gptel-hermes--frontmatter (gptel-hermes--read path)))
           (required (plist-get (gptel-hermes--required-tools-data meta)
                                :tools)))
      (should (member (cadr spec) required)))))

(ert-deftest gptel-hermes-powerpoint-repack-removes-stale-entries ()
  (skip-unless (and (executable-find "zip") (executable-find "unzip")))
  (let* ((root (make-temp-file "gptel-hermes-pptx-" t))
         (unpacked (expand-file-name "unpacked" root))
         (fresh (expand-file-name "fresh" root))
         (archive (expand-file-name "output.pptx" root))
         (tmpdir (make-temp-file "gptel-hermes-pptx-tmp-" t))
         (tmp (expand-file-name "output.pptx" tmpdir)))
    (unwind-protect
        (progn
          (make-directory unpacked t)
          (with-temp-file (expand-file-name "stale.txt" unpacked)
            (insert "stale\n"))
          (let ((default-directory (file-name-as-directory unpacked)))
            (should (= 0 (call-process "zip" nil nil nil "-qr" archive "."))))
          (make-directory fresh t)
          (with-temp-file (expand-file-name "keep.txt" fresh)
            (insert "keep\n"))
          (let ((default-directory (file-name-as-directory fresh)))
            (should (= 0 (call-process "zip" nil nil nil "-qr" tmp "."))))
          (rename-file tmp archive t)
          (with-temp-buffer
            (should (= 0 (call-process "unzip" nil t nil "-Z1" archive)))
            (goto-char (point-min))
            (should (search-forward "keep.txt" nil t))
            (goto-char (point-min))
            (should-not (search-forward "stale.txt" nil t))))
      (delete-directory root t)
      (delete-directory tmpdir t))))

(ert-deftest gptel-hermes-petdex-preview-documents-interactive-terminal ()
  (let ((content (gptel-hermes--read
                  (expand-file-name "productivity/petdex/SKILL.md"
                                    gptel-hermes--bundled-skills-directory))))
    (should (string-match-p "user's interactive terminal" content))
    (should (string-match-p "stdin closed" content))
    (should (string-match-p "Always pass the explicit slug" content))
    (should-not (string-match-p "omit slug for a picker" content))
    (should-not (string-match-p "3\\. Preview it:" content))))

(ert-deftest gptel-hermes-skill-validate-accepts-minimal-frontmatter ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "demo"
           "---\nname: demo\ndescription: A minimal skill\n---\n# Body\n")
          (let ((result (gptel-hermes-skill-validate "demo")))
            (should (string-match-p "Skill validation passed" result))
            (should (string-match-p "Name: demo" result))
            (should (string-match-p "Description: A minimal skill" result))
            (should (string-match-p "Body length: 7 characters" result))
            (should (string-match-p "Validation: success" result))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-validate-accepts-nested-metadata-and-arrays ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "metadata-demo"
           (concat "---\n"
                   "name: metadata-demo\n"
                   "description: \"Metadata: arrays remain supported.\"\n"
                   "version: 1.0.0\n"
                   "platforms: [linux, macos]\n"
                   "metadata:\n"
                   "  hermes:\n"
                   "    tags: [one, two]\n"
                   "    related_skills: [demo]\n"
                   "---\n"
                   "# Metadata body\n"))
          (let ((result (gptel-hermes-skill-validate "metadata-demo")))
            (should (string-match-p "Skill validation passed" result))
            (should (string-match-p "Metadata: arrays remain supported\." result))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-validate-reports-frontmatter-structure-errors ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "no-start"
           "name: no-start\ndescription: Missing opening\n---\n# Body\n")
          (gptel-hermes-test--write-skill
           root "no-close"
           "---\nname: no-close\ndescription: Missing closing\n# Body\n")
          (let ((no-start (gptel-hermes-skill-validate "no-start"))
                (no-close (gptel-hermes-skill-validate "no-close")))
            (should (string-match-p "first line" no-start))
            (should (string-match-p "closing" no-close))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-validate-reports-required-fields-and-size-errors ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "missing-fields"
           "---\nversion: 1.0.0\n---\n# Body\n")
          (gptel-hermes-test--write-skill
           root "bad-name"
           "---\nname: Bad_Name\ndescription: Present\n---\n# Body\n")
          (gptel-hermes-test--write-skill
           root "long-description"
           (concat "---\nname: long-description\ndescription: "
                   (make-string 1025 ?x) "\n---\n# Body\n"))
          (gptel-hermes-test--write-skill
           root "empty-body"
           "---\nname: empty-body\ndescription: Present\n---\n  \n")
          (gptel-hermes-test--write-skill
           root "too-large"
           (concat "---\nname: too-large\ndescription: Present\n---\n"
                   (make-string 100001 ?x)))
          (let ((missing (gptel-hermes-skill-validate "missing-fields"))
                (bad-name (gptel-hermes-skill-validate "bad-name"))
                (long-description (gptel-hermes-skill-validate "long-description"))
                (empty-body (gptel-hermes-skill-validate "empty-body"))
                (too-large (gptel-hermes-skill-validate "too-large")))
            (should (string-match-p "name is missing" missing))
            (should (string-match-p "description is missing" missing))
            (should (string-match-p "lowercase" bad-name))
            (should (string-match-p "1024" long-description))
            (should (string-match-p "body.*empty" empty-body))
            (should (string-match-p "100000" too-large))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-bundled-skills-pass-validation ()
  (let ((gptel-hermes-skills-directory
         gptel-hermes--bundled-skills-directory))
    (should-not (gptel-hermes--skill-validation-failures))
    (dolist (path (gptel-hermes--skill-files-under-root
                   gptel-hermes--bundled-skills-directory))
      (let* ((content (gptel-hermes--read path))
             (meta (gptel-hermes--frontmatter content))
             (required (gptel-hermes--required-tools-data meta)))
        (should (assoc "requires_tools" meta))
        (should (plist-get required :present))
        (should-not (plist-get required :errors))))))

(ert-deftest gptel-hermes-bundled-skills-declare-legacy-dependencies ()
  (dolist (path (gptel-hermes--skill-files-under-root
                 gptel-hermes--bundled-skills-directory))
    (let* ((content (gptel-hermes--read path))
           (meta (gptel-hermes--frontmatter content))
           (required (gptel-hermes--required-tools-data meta))
           (tools (plist-get required :tools)))
      (dolist (use (gptel-hermes-test--legacy-call-uses content))
        (let* ((legacy-name (car use))
               (expected (gptel-hermes-test--legacy-required-tool legacy-name)))
          (if (member legacy-name
                      gptel-hermes-test--directly-migratable-legacy-tools)
              (ert-fail
               (format "%s:%d still uses directly migratable legacy tool %s"
                       path (nth 1 use) legacy-name))
            (unless (member expected tools)
              (ert-fail
               (format "%s:%d uses %s without requires_tools dependency"
                       path (nth 1 use) legacy-name)))))))))

(ert-deftest gptel-hermes-skill-validation-rejects-unsafe-relative-ids ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (dolist (skill-id '("../escape" "/absolute" "a//b" "/leading"
                              "trailing/" "a\\b" "a/./b" "a/../b"
                              "Bad/name" "bad/name_with_underscore"))
            (should (string-match-p "Skill validation failed"
                                    (gptel-hermes-skill-validate skill-id)))
            (should-error
             (gptel-hermes-skill-create skill-id "Description" "# Body"))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-create-uses-user-directory-and-refreshes-index ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (let ((result (gptel-hermes-skill-create
                         "software-development/new-skill"
                         "A newly created skill"
                         "# New skill body\n")))
            (should (string-match-p "Skill created successfully" result))
            (should (string-match-p "Index: refreshed" result)))
          (let ((path (gptel-hermes-test--skill-path
                       root "software-development/new-skill")))
            (should (equal
                     (concat "---\n"
                             "name: new-skill\n"
                             "description: \"A newly created skill\"\n"
                             "---\n"
                             "# New skill body\n")
                     (gptel-hermes--read path)))
            (should (string-match-p "Skill validation passed"
                                    (gptel-hermes-skill-validate
                                     "software-development/new-skill")))
            (should (string-match-p "new-skill | A newly created skill"
                                    (gptel-hermes--index)))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-create-refuses-overwrite-and-invalid-content ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory root))
          (let ((path (gptel-hermes-test--write-skill
                       root "existing" "original content\n")))
            (should-error
             (gptel-hermes-skill-create "existing" "New description" "# New"))
            (should (equal "original content\n"
                           (gptel-hermes--read path))))
          (should-error
           (gptel-hermes-skill-create "invalid-empty-body" "Description" "  \n"))
          (should-not (file-exists-p
                       (gptel-hermes-test--skill-path root "invalid-empty-body")))
          (should-error
           (gptel-hermes-skill-create "invalid-long-description"
                                      (make-string 1025 ?x) "# Body"))
          (should-not (file-exists-p
                       (gptel-hermes-test--skill-path
                        root "invalid-long-description"))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-create-refuses-bundled-directory ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes-skills-directory
               gptel-hermes--bundled-skills-directory))
          (should-error
           (gptel-hermes-skill-create "must-not-write" "Description" "# Body")))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-create-refuses-bundled-subtree-before-writing ()
  (let* ((root (make-temp-file "gptel-hermes-skill-" t))
         (bundled-root (expand-file-name "skills" root))
         (destination (expand-file-name "skills/new/SKILL.md" root)))
    (make-directory bundled-root t)
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory bundled-root)
              (gptel-hermes-skills-directory root))
          (should-error
           (gptel-hermes-skill-create "skills/new" "Description" "# Body"))
          (should-not (file-exists-p destination))
          (should-not (file-exists-p (file-name-directory destination))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-custom-options-belong-to-gptel-hermes-group ()
  (let ((members (get 'gptel-hermes 'custom-group)))
    (dolist (variable '(gptel-hermes-skills-directory
                        gptel-hermes-home
                        gptel-hermes-org-directory-fallback))
                (should
                 (cl-some (lambda (member)
                  (eq variable (if (consp member) (car member) member)))
                members)))))

(ert-deftest gptel-hermes-requires-tools-parser-accepts-supported-lists ()
  (let ((data (gptel-hermes--required-tools-data
               '(("requires_tools" . "[hermes_file_read, hermes_terminal]")))))
    (should (plist-get data :present))
    (should (equal '("hermes_file_read" "hermes_terminal")
                   (plist-get data :tools)))
    (should-not (plist-get data :errors)))
  (let ((data (gptel-hermes--required-tools-data
               '(("requires_tools" . "[]")))))
    (should (plist-get data :present))
    (should-not (plist-get data :tools))
    (should-not (plist-get data :errors)))
  (should-not (plist-get (gptel-hermes--required-tools-data nil) :present)))

(ert-deftest gptel-hermes-requires-tools-parser-rejects-malformed-lists ()
  (dolist (value '("hermes_terminal"
                   "[hermes terminal]"
                   "[hermes.terminal]"
                   "[hermes_terminal,]"
                   "[hermes_terminal, hermes_terminal]"
                   "[hermes_terminal"))
    (should (plist-get
             (gptel-hermes--required-tools-data
              (list (cons "requires_tools" value)))
             :errors))))

(ert-deftest gptel-hermes-skill-index-filters-missing-tools ()
  (let ((root (make-temp-file "gptel-hermes-tools-" t)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory root)
              (gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "available"
           "---\nname: available\ndescription: Available\nrequires_tools: [hermes_file_read]\n---\n# Available\n")
          (gptel-hermes-test--write-skill
           root "missing"
           "---\nname: missing\ndescription: Missing\nrequires_tools: [not_installed]\n---\n# Missing\n")
          (gptel-hermes-test--write-skill
           root "custom"
           "---\nname: custom\ndescription: Custom\nrequires_tools: [custom_tool]\n---\n# Custom\n")
          (gptel-hermes-test--write-skill
           root "invalid"
           "---\nname: invalid\ndescription: Invalid\nrequires_tools: [custom_tool,]\n---\n# Invalid\n")
          (let* ((custom-tool
                  (gptel-make-tool :name "custom_tool"
                                   :function #'ignore
                                   :description "Test tool"
                                   :args nil))
                 (status (gptel-hermes--skill-index-status
                          (mapcar #'gptel-tool-name
                                  (list gptel-hermes--runtime-file-read-tool
                                        custom-tool)))))
            (should (equal '("available" "custom")
                           (mapcar (lambda (entry) (plist-get entry :name))
                                   (plist-get status :entries))))
            (should (equal '("missing")
                           (mapcar (lambda (entry) (plist-get entry :name))
                                   (plist-get status :incompatible))))
            (should (equal '("invalid")
                           (mapcar (lambda (entry) (plist-get entry :name))
                                   (plist-get status :invalid))))
            (should (equal '("not_installed")
                           (gptel-hermes--skill-missing-tools
                            (car (plist-get status :incompatible))
                            (list "hermes_file_read" "custom_tool"))))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-view-reports-required-and-missing-tools ()
  (let ((root (make-temp-file "gptel-hermes-view-" t)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory root)
              (gptel-hermes-skills-directory root)
              (gptel-hermes--effective-tool-names '("hermes_file_read")))
          (gptel-hermes-test--write-skill
           root "demo"
           "---\nname: demo\ndescription: Demo\nrequires_tools: [hermes_file_read, not_installed]\n---\n# Body\n")
          (let ((result (gptel-hermes-skill-view "demo")))
            (should (string-match-p "Required tools: hermes_file_read, not_installed"
                                    result))
            (should (string-match-p "Missing tools in current buffer: not_installed"
                                    result))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-send-enables-current-buffer-before-sending ()
  (let ((home (gptel-hermes-test--fixture))
        sent)
    (unwind-protect
        (let ((gptel-hermes-home home)
              (gptel-hermes--bundled-skills-directory
               (expand-file-name "skills" home))
              (gptel-hermes-skills-directory
               (expand-file-name "skills" home)))
          (with-temp-buffer
            (setq-local gptel-system-prompt "base")
            (cl-letf (((symbol-function 'gptel-send)
                       (lambda (&optional arg)
                         (setq sent
                               (list arg
                                     gptel-hermes--enabled-p
                                     (and (string-match-p
                                           "## Hermes Skills"
                                           gptel-system-prompt)
                                          t)
                                     (and (member
                                           "hermes_skill_view"
                                           (mapcar #'gptel-tool-name gptel-tools))
                                          t))))))
              (gptel-hermes-send '(4))))
          (should (equal '((4) t t t) sent)))
      (delete-directory home t))))

(ert-deftest gptel-hermes-global-send-mode-binds-outside-and-inside-gptel ()
  (let ((was-enabled gptel-hermes-global-send-mode))
    (unwind-protect
        (progn
          (gptel-hermes-global-send-mode 1)
          (with-temp-buffer
            (should (eq (key-binding (kbd "C-c RET"))
                        #'gptel-hermes-send)))
          (with-temp-buffer
            (text-mode)
            (gptel-mode 1)
            (should (eq (key-binding (kbd "C-c RET"))
                        #'gptel-hermes-send))))
      (gptel-hermes-global-send-mode (if was-enabled 1 -1)))))

(ert-deftest gptel-hermes-enable-removes-disabled-hermes-tools ()
  (let* ((home (gptel-hermes-test--fixture))
         (gptel-hermes-home home)
         (gptel-hermes--bundled-skills-directory
          (expand-file-name "skills" home))
         (gptel-hermes-skills-directory
          (expand-file-name "skills" home))
         (gptel-hermes--runtime-elisp-eval-tool nil)
         (gptel-hermes-enable-unsafe-elisp-eval t)
         (gptel-hermes-enable-authenticated-terminal t))
    (unwind-protect
        (with-temp-buffer
          (setq-local gptel-system-prompt "base")
          (gptel-hermes-enable)
          (should (member "hermes_elisp_eval"
                          (mapcar #'gptel-tool-name gptel-tools)))
          (should (member "hermes_terminal_authenticated"
                          (mapcar #'gptel-tool-name gptel-tools)))
          (let ((gptel-hermes-enable-unsafe-elisp-eval nil))
            (let ((gptel-hermes-enable-authenticated-terminal nil))
              (gptel-hermes-enable)
              (should-not (member "hermes_terminal_authenticated"
                                  (mapcar #'gptel-tool-name gptel-tools))))
            (gptel-hermes-enable)
            (should-not (member "hermes_elisp_eval"
                                (mapcar #'gptel-tool-name gptel-tools)))
            (should (= 1 (cl-count "hermes_file_read"
                                   (mapcar #'gptel-tool-name gptel-tools)
                                   :test #'equal)))))
      (delete-directory home t))))

(ert-deftest gptel-hermes-skill-tools-have-confirmation-policies ()
  (should-not (gptel-tool-confirm gptel-hermes--skill-validate-tool))
  (should (eq t (gptel-tool-confirm gptel-hermes--skill-create-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--skill-validate-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--skill-create-tool)))
  (should (equal "hermes_skill_validate"
                 (gptel-tool-name gptel-hermes--skill-validate-tool)))
  (should (equal "hermes_skill_create"
                 (gptel-tool-name gptel-hermes--skill-create-tool))))

(ert-deftest gptel-hermes-skill-overlay-prefers-user-and-falls-back-per-resource ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         (bundled-skill "cat/demo/SKILL.md")
         (bundled-ref "cat/demo/references/from-bundle.txt")
         (user-skill "cat/demo/SKILL.md")
         (user-ref "cat/demo/references/from-user.txt"))
    (unwind-protect
        (progn
          (make-directory (file-name-directory (expand-file-name bundled-ref bundled)) t)
          (with-temp-file (expand-file-name bundled-skill bundled)
            (insert "---\nname: demo\ndescription: bundled\n---\n# Bundle\n"))
          (with-temp-file (expand-file-name bundled-ref bundled) (insert "bundle"))
          (make-directory (file-name-directory (expand-file-name user-ref user)) t)
          (with-temp-file (expand-file-name user-skill user)
            (insert "---\nname: demo\ndescription: user\n---\n# User\n"))
          (with-temp-file (expand-file-name user-ref user) (insert "user"))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (let ((entry (gptel-hermes--effective-skill-entry-by-id "cat/demo")))
              (should (equal user-skill
                             (file-relative-name (plist-get entry :path) user)))
              (should (equal (expand-file-name bundled-ref bundled)
                             (gptel-hermes--skill-resource-path
                              "cat/demo" "references/from-bundle.txt")))
              (should (equal (expand-file-name user-ref user)
                             (gptel-hermes--skill-resource-path
                              "cat/demo" "references/from-user.txt")))
              (should (string-match-p "bundle"
                                      (gptel-hermes-skill-view
                                       "cat/demo" "references/from-bundle.txt")))
              (should (string-match-p "user"
                                      (gptel-hermes-skill-view
                                       "cat/demo" "references/from-user.txt"))))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-update-is-copy-on-write-and-reports-drift ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         (path "cat/demo/SKILL.md"))
    (unwind-protect
        (progn
          (make-directory (file-name-directory (expand-file-name path bundled)) t)
          (with-temp-file (expand-file-name path bundled)
            (insert "---\nname: demo\ndescription: bundled\n---\n# Bundle\n"))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (let* ((bundled-path (expand-file-name path bundled))
                   (sha (gptel-hermes--file-sha256 bundled-path))
                   (content "---\nname: demo\ndescription: user\n---\n# User\n"))
              (should (string-match-p "copy-on-write"
                                      (or (documentation
                                           #'gptel-hermes-skill-update)
                                          "copy-on-write")))
              (gptel-hermes-skill-update "cat/demo" content sha)
              (should (equal content
                             (gptel-hermes--read (expand-file-name path user))))
              (should (string-match-p "bundled_sha256="
                                      (gptel-hermes--read
                                       (gptel-hermes--skill-origin-path "cat/demo"))))
              (with-temp-file bundled-path (insert "changed"))
              (should (string-match-p "Bundled upstream changed: yes"
                                      (gptel-hermes-skill-view "cat/demo")))
              (should-error
               (gptel-hermes-skill-update "cat/demo" content "stale")))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-migration-backs-up-and-removes-legacy-copies ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         backup
         reported)
    (unwind-protect
        (progn
          (dolist (path '("cat/same/SKILL.md" "cat/different/SKILL.md"))
            (make-directory (file-name-directory (expand-file-name path bundled)) t))
          (with-temp-file (expand-file-name "cat/same/SKILL.md" bundled)
            (insert "same"))
          (with-temp-file (expand-file-name "cat/different/SKILL.md" bundled)
            (insert "bundle"))
          (copy-directory bundled user nil t t)
          (with-temp-file (expand-file-name "cat/different/SKILL.md" user)
            (insert "user"))
          (make-directory (expand-file-name "cat/different/scripts" user) t)
          (with-temp-file (expand-file-name "cat/different/scripts/check.sh" user)
            (insert "#!/bin/sh\\n"))
          (with-temp-file (expand-file-name ".gptel-hermes-origin"
                                            (expand-file-name "cat/same" user))
            (insert "bundled_sha256=old\n"))
          (with-temp-file (expand-file-name ".gptel-hermes-bundled-skills" user))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                      ((symbol-function 'message)
                       (lambda (format-string &rest arguments)
                         (setq reported
                               (apply #'format format-string arguments)))))
              (let* ((noninteractive nil)
                     (result
                      (call-interactively
                       #'gptel-hermes-migrate-skill-overlay)))
                (setq backup
                      (when (string-match "differing backups: \\(.*\\)$" result)
                        (match-string 1 result)))
                (should (equal reported result)))
              (should-not (file-exists-p
                           (expand-file-name "cat/same/SKILL.md" user)))
              (should-not (file-exists-p
                           (expand-file-name "cat/different/SKILL.md" user)))
              (should-not (file-exists-p
                           (expand-file-name
                            "cat/same/.gptel-hermes-origin" user)))
              (should (file-exists-p
                       (expand-file-name "cat/different/SKILL.md" backup)))
              (should (file-exists-p
                       (expand-file-name "cat/different/scripts/check.sh" backup)))
              (should-not (file-exists-p
                           (expand-file-name "cat/different/scripts/check.sh" user))))))
      (delete-directory root t)
      (when (and backup (file-directory-p backup))
        (delete-directory backup t)))))

(ert-deftest gptel-hermes-skill-migration-retains-nested-user-skill ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         (parent "cat/parent/SKILL.md")
         (nested "cat/parent/custom/SKILL.md")
         (resource "cat/parent/custom/references/user.txt")
         backup)
    (unwind-protect
        (progn
          (make-directory
           (file-name-directory (expand-file-name parent bundled)) t)
          (with-temp-file (expand-file-name parent bundled)
            (insert "same"))
          (copy-directory bundled user nil t t)
          (make-directory
           (file-name-directory (expand-file-name resource user)) t)
          (with-temp-file (expand-file-name nested user)
            (insert "user skill"))
          (with-temp-file (expand-file-name resource user)
            (insert "user resource"))
          (with-temp-file
              (expand-file-name ".gptel-hermes-bundled-skills" user))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
              (let ((result (gptel-hermes-migrate-skill-overlay)))
                (when (string-match "differing backups: \\(.*\\)$" result)
                  (setq backup (match-string 1 result)))))
            (should-not (file-exists-p (expand-file-name parent user)))
            (should (equal "user skill"
                           (gptel-hermes--read
                            (expand-file-name nested user))))
            (should (equal "user resource"
                           (gptel-hermes--read
                            (expand-file-name resource user))))
            (should (file-exists-p (expand-file-name nested backup)))))
      (delete-directory root t)
      (when (and backup (file-directory-p backup))
        (delete-directory backup t)))))

(ert-deftest gptel-hermes-skill-migration-removes-marker-with-no-copies ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         (marker (expand-file-name ".gptel-hermes-bundled-skills" user)))
    (unwind-protect
        (progn
          (make-directory bundled t)
          (make-directory user t)
          (with-temp-file marker (insert "legacy\n"))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (let ((result (gptel-hermes-migrate-skill-overlay)))
              (should (string-match-p "marker removed" result)))
            (should-not (file-exists-p marker))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-skill-customize-records-bundled-origin ()
  (let* ((root (make-temp-file "gptel-hermes-overlay-" t))
         (bundled (expand-file-name "bundled" root))
         (user (expand-file-name "user" root))
         (skill "cat/demo/SKILL.md"))
    (unwind-protect
        (progn
          (make-directory (file-name-directory (expand-file-name skill bundled)) t)
          (with-temp-file (expand-file-name skill bundled)
            (insert "---\nname: demo\ndescription: bundled\n---\n# Body\n"))
          (let ((gptel-hermes--bundled-skills-directory bundled)
                (gptel-hermes-skills-directory user))
            (gptel-hermes-skill-customize "cat/demo")
            (with-temp-file (expand-file-name skill bundled)
              (insert "changed"))
            (should (string-match-p "Bundled upstream changed: yes"
                                    (gptel-hermes-skill-view "cat/demo")))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-memory-writes-persist-and-target-user ()
  (let ((home (gptel-hermes-test--fixture)))
    (unwind-protect
        (let ((gptel-hermes-home home)
              (gptel-hermes-skills-directory (expand-file-name "skills" home)))
          (gptel-hermes-memory "add" "memory" "new fact")
          (should (string-match-p "new fact"
                                  (gptel-hermes--read
                                   (gptel-hermes--memory-path "memory"))))
          (gptel-hermes-memory "replace" "user" "user preference" "new preference")
          (should (string-match-p "new preference"
                                  (gptel-hermes--read
                                   (gptel-hermes--memory-path "user"))))
          (gptel-hermes-memory "remove" "memory" "new fact")
          (should-not (string-match-p "new fact"
                                      (gptel-hermes--read
                                       (gptel-hermes--memory-path "memory")))))
      (delete-directory home t))))

(ert-deftest gptel-hermes-enable-keeps-a-stable-buffer-prompt ()
  (let ((home (gptel-hermes-test--fixture)))
    (unwind-protect
        (let ((gptel-hermes-home home)
              (gptel-hermes--bundled-skills-directory
               (expand-file-name "skills" home))
              (gptel-hermes-skills-directory (expand-file-name "skills" home)))
          (with-temp-buffer
            (setq-local gptel-system-prompt "frontend base")
            (gptel-hermes-enable)
            (should (member "hermes_org_agenda"
                            (mapcar #'gptel-tool-name gptel-tools)))
            (should (member "hermes_org_task"
                            (mapcar #'gptel-tool-name gptel-tools)))
            (should (member "hermes_skill_validate"
                            (mapcar #'gptel-tool-name gptel-tools)))
            (should (member "hermes_skill_create"
                            (mapcar #'gptel-tool-name gptel-tools)))
            (gptel-hermes-enable)
            (should (= 2 (length (cl-remove-if-not
                                  (lambda (tool)
                                    (member (gptel-tool-name tool)
                                            '("hermes_skill_validate"
                                              "hermes_skill_create")))
                                  gptel-tools))))
            (let ((snapshot gptel-system-prompt))
              (with-temp-file (expand-file-name "MEMORY.md"
                                                (expand-file-name "memories" home))
                (insert "after\n"))
              (should (equal snapshot gptel-system-prompt))
              (should (string-match-p "before" snapshot))
              (should-not (string-match-p "after" snapshot))
              (should (string-match-p "frontend base" snapshot)))))
      (delete-directory home t))))

(ert-deftest gptel-hermes-enable-validates-and-refreshes-skill-index ()
  (let ((root (make-temp-file "gptel-hermes-skill-" t)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory root)
              (gptel-hermes-skills-directory root))
          (gptel-hermes-test--write-skill
           root "initial"
           "---\nname: initial\ndescription: Initial skill\n---\n# Initial\n")
          (with-temp-buffer
            (setq-local gptel-system-prompt "base")
            (gptel-hermes-enable)
            (should (string-match-p "initial | Initial skill"
                                    gptel-system-prompt))
            (gptel-hermes-test--write-skill
             root "created-later"
             "---\nname: created-later\ndescription: Created later\n---\n# Later\n")
            (should-not (string-match-p "created-later | Created later"
                                        gptel-system-prompt))
            (gptel-hermes-enable)
            (should-not (gptel-hermes--skill-validation-failures))
            (should (string-match-p "created-later | Created later"
                                    gptel-system-prompt))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-enable-uses-bundled-fallback-without-copy ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory destination))
          (with-temp-buffer
            (setq-local gptel-system-prompt "base")
            (gptel-hermes-enable))
          (should-not (file-exists-p
                       (expand-file-name "category/demo/SKILL.md" destination)))
          (should-not (file-exists-p
                       (expand-file-name ".gptel-hermes-bundled-skills" destination)))
          (should (equal
                   (expand-file-name "category/demo/SKILL.md" source)
                   (car (gptel-hermes--skill-files))))
          (should-not (file-exists-p
                       (expand-file-name "references/ignored/SKILL.md" destination))))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-enable-warns-about-legacy-overlay-marker ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t))
         (marker (expand-file-name ".gptel-hermes-bundled-skills" destination))
         warning)
    (unwind-protect
        (progn
          (with-temp-file marker (insert ""))
          (let ((gptel-hermes--bundled-skills-directory source)
                (gptel-hermes-skills-directory destination))
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (_type message &rest _)
                         (setq warning message)))
                      ((symbol-function 'gptel-hermes-runtime-initialize-workspace)
                       (lambda () nil)))
              (with-temp-buffer
                (setq-local gptel-system-prompt "base")
                (gptel-hermes-enable))))
          (should (string-match-p "Legacy skill copies" warning))
          (should (string-match-p "gptel-hermes-migrate-skill-overlay"
                                  warning)))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-sync-creates-missing-destination ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination-parent (make-temp-file "gptel-hermes-destination-" t))
         (destination (expand-file-name "profiles/main/skills"
                                       destination-parent)))
    (delete-directory destination-parent t)
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory destination))
          (gptel-hermes--sync-bundled-skills)
          (should (file-exists-p
                   (expand-file-name "category/demo/SKILL.md" destination)))
          (should (file-exists-p
                   (expand-file-name ".gptel-hermes-bundled-skills" destination))))
      (delete-directory source t)
      (when (file-directory-p destination-parent)
        (delete-directory destination-parent t)))))

(ert-deftest gptel-hermes-sync-preserves-existing-skill ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t))
         (destination-skill (expand-file-name "category/demo/SKILL.md" destination)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory destination-skill) t)
          (with-temp-file destination-skill (insert "user skill\n"))
          (let ((gptel-hermes--bundled-skills-directory source)
                (gptel-hermes-skills-directory destination))
            (let ((result (gptel-hermes--sync-bundled-skills)))
              (should (= 0 (plist-get result :copied)))
              (should (= 1 (plist-get result :existing))))
            (should (equal "user skill\n"
                           (gptel-hermes--read destination-skill)))))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-reinstall-skills-overwrites-bundled-files-only ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t))
         (destination-skill
          (expand-file-name "category/demo/SKILL.md" destination))
         (custom-skill
          (expand-file-name "custom/own/SKILL.md" destination))
         (marker
          (expand-file-name ".gptel-hermes-bundled-skills" destination)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory destination-skill) t)
          (make-directory (file-name-directory custom-skill) t)
          (with-temp-file destination-skill (insert "user override\n"))
          (with-temp-file custom-skill (insert "custom skill\n"))
          (with-temp-file marker)
          (let ((gptel-hermes--bundled-skills-directory source)
                (gptel-hermes-skills-directory destination))
            (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
              (should-error (gptel-hermes-reinstall-skills)
                            :type 'user-error))
            (should (equal "user override\n"
                           (gptel-hermes--read destination-skill)))
            (let (prompt)
              (let ((result
                     (cl-letf (((symbol-function 'yes-or-no-p)
                                (lambda (question)
                                  (setq prompt question)
                                  t)))
                       (gptel-hermes-reinstall-skills))))
                (should (eq 'reinstalled (plist-get result :status)))
                (should (= 1 (plist-get result :overwritten)))
                (should (= 0 (plist-get result :copied))))
              (should (string-match-p (regexp-quote destination) prompt)))
            (should (equal "bundled demo skill\n"
                           (gptel-hermes--read destination-skill)))
            (should (equal "custom skill\n"
                           (gptel-hermes--read custom-skill)))
            (should (file-exists-p marker))))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-sync-marker-prevents-a-second-copy ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t))
         (destination-skill (expand-file-name "category/demo/SKILL.md" destination)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory destination))
          (gptel-hermes--sync-bundled-skills)
          (delete-file destination-skill)
          (let ((result (gptel-hermes--sync-bundled-skills)))
            (should (eq 'already-synchronized (plist-get result :status)))
            (should-not (file-exists-p destination-skill))))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-sync-failure-does-not-write-marker ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t))
         (marker (expand-file-name ".gptel-hermes-bundled-skills" destination)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory destination))
          (cl-letf (((symbol-function 'copy-file)
                     (lambda (&rest _args) (error "simulated copy failure"))))
            (should-error (gptel-hermes--sync-bundled-skills)))
          (should-not (file-exists-p marker)))
      (delete-directory source t)
      (delete-directory destination t))))

(ert-deftest gptel-hermes-sync-skips-bundled-source-itself ()
  (let ((source (gptel-hermes-test--bundled-skills-fixture)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory source))
          (let ((result (gptel-hermes--sync-bundled-skills)))
            (should (eq 'bundled (plist-get result :status)))
            (should-not (file-exists-p
                         (expand-file-name ".gptel-hermes-bundled-skills" source))))
          (should-error (gptel-hermes-reinstall-skills) :type 'user-error))
      (delete-directory source t))))

(provide 'gptel-hermes-tests)
;;; gptel-hermes-tests.el ends here
