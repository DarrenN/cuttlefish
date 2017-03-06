#lang racket
(require racket/async-channel
         gregor
         json
         (except-in "hash.rkt" get)
         "logger.rkt"
         "workers/meetup.rkt")

;; ================
;; Worker Functions
;; ================
;; Define worker functions by their adapter key from the chapter.json files

(define WORKERS
  (hash "meetup" worker-meetup))

;; TODO: paths should be set by args or ENV vars
(define CHAPTERS_JSON (build-path (current-directory) "data" "chapters.json"))
(define CHAPTERS_OUTPUT (build-path "/tmp"))

;; Mutable state
(define chapters (box '()))
(define thread-count (box 0))
(define state (box '()))


;; Logging
;; =======
;; TODO: path should be set by ARGS or ENV vars
(define logging-thread
  (launch-log-daemon (build-path "/tmp") "racket-test-logger"))

;; Read JSON
;; =========
;; If we can't open the chapters file then crash out
(if (file-exists? CHAPTERS_JSON)
    (begin
      (set-box! chapters
                (call-with-input-file CHAPTERS_JSON (λ (in) (read-json in))))
      (set-box! thread-count
                (length (hash-keys (unbox chapters)))))
    (begin
      (format-log "FATAL: Cannot open ~a" CHAPTERS_JSON)
      (printf "FATAL: Cannot open ~a" CHAPTERS_JSON)
      (kill-thread logging-thread)
      (exit 1)))


;; Write JSON to files
;; ====================
(define (write-chapter-response response)
  (let* ([id (car response)]
         [resp (cadr response)]
         [path (build-path CHAPTERS_OUTPUT (format "~a.json" id))])
    (with-handlers ([exn:fail?
                     (λ (exn) (channel-put
                               result-channel
                               (format "ERROR: Could not write to ~a : ~a" path (exn-message exn))))])
      (begin
        (with-output-to-file path #:mode 'text #:exists 'replace
          (λ () (display (jsexpr->string resp))))
        (channel-put result-channel (format "WROTE: ~a" path))))))

;; Payload should be in the format (id jsexpr?) or an error
(define (write-response resp)
  (case (car resp)
    ['ERROR
     (channel-put result-channel (format "ERROR: ~a" (cdr resp)))]
    [else (write-chapter-response resp)]))

;; Keep tabs on how many 'DONE messages come in and terminate when they all
;; phone home
(define (maintain-done-state done)
  (let* ([s (unbox state)]
         [l (unbox thread-count)]
         [n (cons done s)])
    (if (equal? (length n) l)
        (begin
          (sleep 2) ; allow time to flush the log
          (kill-thread logging-thread))
        (set-box! state n))))


;; Result channel - writes to log file
(define result-channel (make-channel))
(define result-thread
  (thread
   (λ ()
     (let loop ()
       (let ([r (channel-get result-channel)])
         (if (equal? r 'DONE)
             (maintain-done-state r)
             (format-log "~a" r)))
       (loop)))))

;; Read adapter key from chapter payload
(define (get-adapter payload)
  (if (equal? (car payload) 'DONE)
      'DONE
      (get-in '(dataService adapter) (cdr payload))))


;; Worker Threads
;; ==============

;; Work channel has a buffer size of thread count
(define work-channel (make-async-channel (unbox thread-count)))

;; Returns a thread bound to id which calls a function based on adapter
;; from the WORKERS hash. If a worker function is registered, its output is
;; tossed onto the file-channel. Errors are logged immediately.
(define (dispatch-worker thread-id)
  (thread
   (λ ()
     (let loop ()
       (define item (async-channel-get work-channel))
       (define adapter (get-adapter item))
       (cond
         [(equal? adapter 'DONE)
          (channel-put result-channel 'DONE)]
         [(hash-has-key? WORKERS adapter)
          (write-response ((hash-ref WORKERS "meetup") format-log thread-id item))
          (loop)]
         [else
          (channel-put
           result-channel
           (format "ERROR: Adapter ~a not registered! [~a]" adapter (car item)))
          (loop)])))))

;; Spin up worker threads
(define work-threads (map dispatch-worker (range (unbox thread-count))))

;; Build a list of chapter payloads with corresponding # of DONE symbols for
;; passing to threads
(define chapter-payloads
  (let* ([chapters (unbox chapters)]
         [pairs (hash->list chapters)]
         [dones (make-list (length pairs) '(DONE))])
    (append pairs dones)))

;; Load payloads into the channels
(for ([item chapter-payloads])
  (async-channel-put work-channel item))

;; We have to explicitly drop a wait on each thread or it will immediately
;; close before it takes work off the channels (synchronization)
(for-each thread-wait work-threads)
(thread-wait logging-thread)
