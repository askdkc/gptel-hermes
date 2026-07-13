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

(defun gptel-hermes-test--write-skill (root skill-id content)
  (let ((path (gptel-hermes-test--skill-path root skill-id)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert content))
    path))

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

(ert-deftest gptel-hermes-skill-tools-have-confirmation-policies ()
  (should-not (gptel-tool-confirm gptel-hermes--skill-validate-tool))
  (should (eq t (gptel-tool-confirm gptel-hermes--skill-create-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--skill-validate-tool)))
  (should (eq t (gptel-tool-include gptel-hermes--skill-create-tool)))
  (should (equal "hermes_skill_validate"
                 (gptel-tool-name gptel-hermes--skill-validate-tool)))
  (should (equal "hermes_skill_create"
                 (gptel-tool-name gptel-hermes--skill-create-tool))))

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

(ert-deftest gptel-hermes-sync-copies-bundled-skills-on-enable ()
  (let* ((source (gptel-hermes-test--bundled-skills-fixture))
         (destination (make-temp-file "gptel-hermes-destination-" t)))
    (unwind-protect
        (let ((gptel-hermes--bundled-skills-directory source)
              (gptel-hermes-skills-directory destination))
          (with-temp-buffer
            (setq-local gptel-system-prompt "base")
            (gptel-hermes-enable))
          (should (equal "bundled demo skill\n"
                         (gptel-hermes--read
                          (expand-file-name "category/demo/SKILL.md" destination))))
          (should-not (file-exists-p
                       (expand-file-name "DESCRIPTION.md" destination)))
          (should-not (file-exists-p
                       (expand-file-name "references/ignored/SKILL.md" destination)))
          (should (file-exists-p
                   (expand-file-name ".gptel-hermes-bundled-skills" destination))))
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
                         (expand-file-name ".gptel-hermes-bundled-skills" source)))))
      (delete-directory source t))))

(provide 'gptel-hermes-tests)
;;; gptel-hermes-tests.el ends here
