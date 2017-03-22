#lang racket
(require racket/async-channel
         gregor
         json
         (except-in "hash.rkt" get)
         "chunk-list.rkt"
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

;; How many threads/channels to spin up to do work
(define thread-count 3)

;; Mutable state
(define chapters (box '()))
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
    (set-box! chapters
              (call-with-input-file CHAPTERS_JSON (λ (in) (read-json in))))
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
         [l thread-count]
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
  (if (equal? payload 'DONE)
      'DONE
      (get-in '(dataService adapter) (cdr payload))))


;; Worker Threads
;; ==============

#|

General outline:
----------------

1) Create a list of n work-channels
2) Create a worker-threads for each channel
3) Partition list of chapters into (length work-channels) lists
4) append 'DONE to the end of each chapters list
5) For each chapters list push chapter into a channel
6) Each thread should terminate on 'DONE

|#

;; Returns a thread bound to id which calls a function based on adapter
;; from the WORKERS hash. If a worker function is registered, its output is
;; tossed onto the file-channel. Errors are logged immediately.
(define (dispatch-worker thread-id chan)
  (thread
   (λ ()
     (let loop ()
       (define item (async-channel-get chan))
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

;; Build a list of chapter payloads with corresponding # of DONE symbols for
;; passing to threads
(define chapter-payloads
  (let* ([chapters (unbox chapters)]
         [pairs (hash->list chapters)]
         [chunks (chunk-list pairs thread-count)])
    (map (λ (x) (append x '(DONE))) chunks)))

;; Create a list of async worker channels equal to thread-count
;; Worker channel has a buffer size equal to # of items in chapters chunk
(define work-channels
  (for/list ([i (range thread-count)]
             [chapters chapter-payloads])
    (make-async-channel (length chapters))))

;; Spin up a worker thread on each channel
(define work-threads
  (for/list ([ch work-channels]
             [id (range (length work-channels))])
    (dispatch-worker id ch)))

;; Load payloads into the channels
(for ([chan work-channels]
      [chapters chapter-payloads])
  (for ([chapter chapters])
    (async-channel-put chan chapter)))

;; We have to explicitly drop a wait on each thread or it will immediately
;; close before it takes work off the channels (synchronization)
(for-each thread-wait work-threads)
(thread-wait logging-thread)
