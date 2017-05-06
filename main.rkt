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

(module+ test
  ;; Tests to be run with raco test
  )

(module+ main
  (require racket/file
           racket/string
           "private/api-runner.rkt")
  
  (define CONFIG-PATH (build-path (current-directory) ".cuttlefishrc"))

  (define default-config
    (hash "json-out-path" "/tmp"
          "chapter-json-file" (build-path (current-directory) "chapters.json")))

  (define config (make-parameter default-config))  
  
  (define (read-config path)
    (apply hash
           (map string-trim
                (regexp-match* #px"[~/\\w.-]+"
                 (string-normalize-spaces
                  (file->string CONFIG-PATH #:mode 'text))))))
  
  (if (file-exists? CONFIG-PATH)
    (parameterize ([config (read-config CONFIG-PATH)])
      (run-workers (config)))
    (run-workers (config))))
