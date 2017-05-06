#lang racket/base

(module+ test
  (require rackunit))
;; Notice
;; To install (from within the package directory):
;;   $ raco pkg install
;; To install (once uploaded to pkgs.racket-lang.org):
;;   $ raco pkg install <<name>>
;; To uninstall:
;;   $ raco pkg remove <<name>>
;; To view documentation:
;;   $ raco docs <<name>>
;;
;; For your convenience, we have included a LICENSE.txt file, which links to
;; the GNU Lesser General Public License.
;; If you would prefer to use a different license, replace LICENSE.txt with the
;; desired license.
;;
;; Some users like to add a `private/` directory, place auxiliary files there,
;; and require them in `main.rkt`.
;;
;; See the current version of the racket style guide here:
;; http://docs.racket-lang.org/style/index.html

;; Code here

(module+ main
  (require racket/cmdline
           racket/file
           racket/string
           "private/api-runner.rkt")

  (define default-configfile-path
    (build-path (current-directory) ".cuttlefishrc"))

  ;; If no cmdline path then use default path
  (define config-path
    (let* ([args (current-command-line-arguments)]
           [arg0 (if (zero? (vector-length args))
                     #f
                     (vector-ref args 0))])
      (if (path-string? arg0)
          (path->complete-path arg0)
          default-configfile-path)))
  
  (define default-config
    (hash "json-out-path" "/tmp"
          "chapter-json-file" (build-path (current-directory) "chapters.json")))

  (define config (make-parameter default-config))  

  ;; Read config file and parse into hash
  (define (read-config path)
    (apply hash
           (map string-trim
                (regexp-match* #px"[~/\\w.-]+"
                 (string-normalize-spaces
                  (file->string path #:mode 'text))))))
  
  (if (and (path? config-path) (file-exists? config-path))
    (parameterize ([config (read-config config-path)])
      (run-workers (config)))
    (run-workers (config))))
