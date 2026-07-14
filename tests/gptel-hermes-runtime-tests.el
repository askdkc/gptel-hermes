;;; gptel-hermes-runtime-tests.el --- runtime checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-hermes-runtime)

(defun gptel-hermes-runtime-test--root ()
  "Create a temporary workspace root."
  (make-temp-file "gptel-hermes-runtime-" t))

(defun gptel-hermes-runtime-test--with-workspace (root function)
  "Call FUNCTION in a temporary buffer using ROOT as workspace."
  (with-temp-buffer
    (gptel-hermes-set-workspace root)
    (funcall function)))

(defun gptel-hermes-runtime-test--await (result-cell &optional seconds)
  "Wait until RESULT-CELL contains a value, bounded by SECONDS."
  (let ((deadline (+ (float-time) (or seconds 5))))
    (while (and (not (car result-cell)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (car result-cell)))

(ert-deftest gptel-hermes-runtime-workspace-home-and-explicit-selection ()
  (let ((home (file-name-as-directory (file-truename (expand-file-name "~")))))
    (with-temp-buffer
      (let ((gptel-hermes--workspace-initialized-p nil)
            (gptel-hermes--workspace-root nil)
            (default-directory home))
        (should-not (gptel-hermes-runtime-initialize-workspace)))
      (let ((root (make-temp-file "gptel-hermes-outside-" t)))
        (unwind-protect
            (should (equal (file-name-as-directory (file-truename root))
                           (gptel-hermes-set-workspace root)))
          (delete-directory root t))))))

(ert-deftest gptel-hermes-runtime-paths-reject-escape-secrets-and-symlinks ()
  (let* ((root (gptel-hermes-runtime-test--root))
         (outside (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".gitignore" root)
            (insert "normal"))
          (with-temp-file (expand-file-name ".env" root)
            (insert "secret"))
          (with-temp-file (expand-file-name "config.env" root)
            (insert "normal"))
          (make-symbolic-link outside (expand-file-name "escape" root))
          (make-symbolic-link (expand-file-name ".env" root)
                              (expand-file-name "public-env" root))
          (gptel-hermes-runtime-test--with-workspace
           root
           (lambda ()
             (should (string-match-p "normal"
                                     (gptel-hermes-file-read ".gitignore")))
             (should (string-match-p "normal"
                                     (gptel-hermes-file-read "config.env")))
             (should-error (gptel-hermes-file-read "../escape"))
             (should-error (gptel-hermes-file-read ".env"))
             (should-error (gptel-hermes-file-read "public-env"))
             (should-error (gptel-hermes-file-write
                            "escape/new.txt" "x" "create")))))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest gptel-hermes-runtime-file-write-sha-and-atomicity ()
  (let ((root (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (gptel-hermes-runtime-test--with-workspace
         root
         (lambda ()
           (gptel-hermes-file-write "file.txt" "before" "create")
           (let* ((read (gptel-hermes-file-read "file.txt"))
                  (sha (progn
                         (string-match "SHA-256: \\([[:xdigit:]]+\\)" read)
                         (match-string 1 read))))
             (should-error (gptel-hermes-file-write
                            "file.txt" "after" "replace" "stale"))
             (should (string-match-p "before"
                                     (gptel-hermes-file-read "file.txt")))
             (gptel-hermes-file-write "file.txt" "after" "replace" sha)
             (should (string-match-p "after"
                                     (gptel-hermes-file-read "file.txt"))))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-runtime-file-read-ranges-and-binary-rejection ()
  (let ((root (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "lines.txt" root)
            (insert "one\ntwo\nthree\n"))
          (with-temp-file (expand-file-name "binary" root)
            (insert "ok\0bad"))
          (gptel-hermes-runtime-test--with-workspace
           root
           (lambda ()
             (let ((result (gptel-hermes-file-read "lines.txt" 2 2)))
               (should (string-match-p "Lines: 2-2 of 3" result))
               (should (string-match-p "two" result))
               (should-not (string-match-p "one" result)))
             (should-error (gptel-hermes-file-read "binary")))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-runtime-apply-patch-checks-and-applies ()
  (let ((root (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "file.txt" root)
            (insert "old\n"))
          (call-process "git" nil nil nil "-C" root "init" "-q")
          (call-process "git" nil nil nil "-C" root "add" "file.txt")
          (let ((patch "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n"))
            (gptel-hermes-runtime-test--with-workspace
             root
             (lambda ()
               (should (string-match-p "check passed"
                                       (gptel-hermes-apply-patch patch t)))
               (should (string-match-p "old"
                                       (gptel-hermes-file-read "file.txt")))
              (should (gptel-hermes-runtime--confirm-patch
                       patch :json-false))
              (should-not (gptel-hermes-runtime--confirm-patch patch t))
              (should (string-match-p "applied"
                                      (gptel-hermes-apply-patch
                                       patch :json-false)))
              (should (string-match-p "new"
                                      (gptel-hermes-file-read "file.txt")))))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-runtime-patch-body-validates-rename-and-copy-paths ()
  (let ((root (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (gptel-hermes-runtime-test--with-workspace
         root
         (lambda ()
           (should-not
            (condition-case nil
                (progn
                  (gptel-hermes-runtime--patch-body-paths
                   "rename from old.txt\nrename to new.txt\n")
                  (gptel-hermes-runtime--patch-body-paths
                   "copy from old.txt\ncopy to new.txt\n")
                  nil)
              (error t)))
           (should-error
            (gptel-hermes-runtime--patch-body-paths
             "rename from .env\nrename to new.txt\n"))
           (should-error
            (gptel-hermes-runtime--patch-body-paths
             "rename from \"dir/.env\"\nrename to \"dir/public.txt\"\n"))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-runtime-apply-patch-rejects-compressed-rename-secret-source ()
  (let ((root (gptel-hermes-runtime-test--root)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "dir" root))
          (with-temp-file (expand-file-name "dir/.env" root)
            (insert "secret\n"))
          (call-process "git" nil nil nil "-C" root "init" "-q")
          (let ((patch
                 (concat
                  "diff --git a/dir/.env b/dir/public.txt\n"
                  "similarity index 100%\n"
                  "rename from dir/.env\n"
                  "rename to dir/public.txt\n")))
            (gptel-hermes-runtime-test--with-workspace
             root
             (lambda ()
               (should-error (gptel-hermes-apply-patch patch t))
               (should (file-exists-p (expand-file-name "dir/.env" root)))
               (should-not
                (file-exists-p (expand-file-name "dir/public.txt" root)))))))
      (delete-directory root t))))

(ert-deftest gptel-hermes-runtime-elisp-boundaries ()
  (with-temp-buffer
    (should-not gptel-hermes--runtime-elisp-eval-tool)
    (should (string-match-p "Function: buffer-name"
                            (gptel-hermes-elisp-call "buffer-name")))
    (should-error (gptel-hermes-elisp-call "kill-emacs"))
    (should-not (member "featurep" gptel-hermes-elisp-call-allowlist))
    (let ((gptel-hermes-enable-unsafe-elisp-eval nil))
      (should-error (gptel-hermes-elisp-eval "(+ 1 2)")))
    (let ((gptel-hermes-enable-unsafe-elisp-eval t))
      (should (string-match-p "3"
                              (gptel-hermes-elisp-eval "(+ 1 2)")))
      (should-error (gptel-hermes-elisp-eval "(+ 1 2) (+ 3 4)")))))

(ert-deftest gptel-hermes-runtime-terminal-is-async-and-sanitized ()
  (let ((root (gptel-hermes-runtime-test--root))
        (result-cell (list nil))
        (calls 0))
    (unwind-protect
        (gptel-hermes-runtime-test--with-workspace
         root
         (lambda ()
           (gptel-hermes-terminal
            (lambda (result)
              (setq calls (1+ calls))
              (setcar result-cell result))
            "/bin/sh"
            ["-c" "printf out; printf err >&2; test -z \"$HOME\"" ]
            nil 2)
           (let ((result (gptel-hermes-runtime-test--await result-cell)))
             (should result)
             (should (= 1 calls))
             (should (string-match-p "Exit status: 1" result))
             (should (string-match-p (concat "STDOUT:\n" "out") result))
             (should (string-match-p (concat "STDERR:\n" "err") result)))))
      (delete-directory root t))))

(provide 'gptel-hermes-runtime-tests)
;;; gptel-hermes-runtime-tests.el ends here
