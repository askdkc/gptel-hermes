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
            (let ((snapshot gptel-system-prompt))
              (with-temp-file (expand-file-name "MEMORY.md"
                                                (expand-file-name "memories" home))
                (insert "after\n"))
              (should (equal snapshot gptel-system-prompt))
              (should (string-match-p "before" snapshot))
              (should-not (string-match-p "after" snapshot))
              (should (string-match-p "frontend base" snapshot)))))
      (delete-directory home t))))

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
